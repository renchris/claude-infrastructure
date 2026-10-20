#!/usr/bin/env bats
# kitty-pane-guard — the fullscreen guard, the action log and the never-relaunch rule at the two
# operator-facing removal paths: bin/kitty-pane-menu and bin/kitty-confirm-close.
#
# THE INCIDENT (docs/research/kitty-crash-2026-10-15/README.md § Chosen fix). Emptying a fullscreen
# kitty OS window crashed kitty and took 18 live sessions with it; the attribution stopped at 75%
# because "Move to <window>" and kitty-confirm-close wrote nothing; and `tell application "kitty"
# to activate` in the menu's refocus LAUNCHED kitty again at 00:01:28. So:
#   · every removal runs bin/kitty-fullscreen-guard as its LAST gate, and acts only on rc 0;
#   · an INTENT row reaches kitty-pane-actions.jsonl before the destroy, a RESULT row after it;
#   · focus goes back by PID through NSRunningApplication, never by application name.
#
# NOTHING HERE TOUCHES A REAL KITTY OR A REAL osascript. `kitty`, `osascript` and the guard are
# stubs; every one appends to ONE call log, so ORDER (guard before detach, intent before destroy)
# is asserted on what the subject actually executed. The kitty stub stamps each call with the
# number of intent rows already on disk, which is what makes "fsynced BEFORE the destroy"
# observable. KITTY_LISTEN_ON names a socket that is never created, on purpose: nothing on the
# address path may stat it (tests/kitty-pane-menu-route.bats carries the same trap).
#
# RED-proof: run 2026-10-15 with KPG_MENU/KPG_CLOSE pointed at `git show HEAD:bin/<file>` copies
# (pre-fix 52d853b06): 1-5 and 7-13 fail (no guard call, no log rows, no destination re-check,
# both activates name application "kitty"); 6 passes on both, since pre-fix logged nothing at all.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  MENU_SRC="${KPG_MENU:-$REPO/bin/kitty-pane-menu}"
  CLOSE_SRC="${KPG_CLOSE:-$REPO/bin/kitty-confirm-close}"
  [ -f "$MENU_SRC" ]; [ -f "$CLOSE_SRC" ]
  unset KITTY_WINDOW_ID KITTY_PID CC_PANE_CMD CC_PANE_CMD_DIR CC_PANE_CMD_INTERACTIVE CC_KITTY_CONF
  HOME="$BATS_TEST_TMPDIR/home"; export HOME
  mkdir -p "$HOME/.claude/cc-registry"
  export CC_KITTY_PANE_ACTIONS_LOG="$BATS_TEST_TMPDIR/actions.jsonl"
  export CC_SPAWN_LOG_FILE="$BATS_TEST_TMPDIR/spawn.jsonl"
  export CALLS="$BATS_TEST_TMPDIR/calls.log" KPG_TREE="$BATS_TEST_TMPDIR/tree.json"
  export KPG_LS_N="$BATS_TEST_TMPDIR/ls.n"
  : >"$CALLS"; : >"$KPG_LS_N"

  STUBS="$BATS_TEST_TMPDIR/stubs"; mkdir -p "$STUBS"
  # kitty: logs every call with the intent rows already on disk; the Nth full `ls` may answer
  # from KPG_TREE2 (a destination that dies between the pop and the pick).
  cat >"$STUBS/kitty" <<'SH'
#!/bin/sh
n=$(grep -c '"phase":"intent"' "$CC_KITTY_PANE_ACTIONS_LOG" 2>/dev/null || true)
echo "kitty $* [intents=${n:-0}] [wid=${KITTY_WINDOW_ID:-}]" >>"$CALLS"
case " $* " in
  *" ls --match "*) cat "$KPG_TREE" ;;
  *" ls "*) echo x >>"$KPG_LS_N"
     if [ -n "$KPG_TREE2" ] && [ "$(wc -l <"$KPG_LS_N")" -ge 2 ]; then cat "$KPG_TREE2"; else cat "$KPG_TREE"; fi ;;
esac
exit 0
SH
  # osascript: the dialog answers KPG_PICK; confirm-close's dialog answers KPG_BUTTON (Cancel = rc 1).
  cat >"$STUBS/osascript" <<'SH'
#!/bin/sh
echo "osascript $*" >>"$CALLS"
case "$*" in *"choose from list"*) printf '%s\n' "$KPG_PICK" ;; esac
if [ "$1" = "-" ]; then cat >/dev/null
  [ "$KPG_BUTTON" = "Close" ] && { echo Close; exit 0; }; echo "User canceled." >&2; exit 1; fi
exit 0
SH
  cat >"$STUBS/guard" <<'SH'
#!/bin/sh
n=$(grep -c '"phase":"intent"' "$CC_KITTY_PANE_ACTIONS_LOG" 2>/dev/null || true)
echo "guard $* [intents=${n:-0}]" >>"$CALLS"
exit "${STUB_RC:-0}"
SH
  chmod +x "$STUBS/kitty" "$STUBS/osascript" "$STUBS/guard"
  export CC_KITTY_FS_GUARD="$STUBS/guard" CC_TERM_KITTY="$STUBS/kitty"

  # A copy with the lib beside it the way the checkout lays it out, and without the native probe
  # binary, so the centered-dialog path (the osascript stub) is the one the menu takes.
  BIN="$BATS_TEST_TMPDIR/co/bin"; mkdir -p "$BIN" "$BATS_TEST_TMPDIR/co/lib"
  cp "$MENU_SRC" "$BIN/kitty-pane-menu"; cp "$CLOSE_SRC" "$BIN/kitty-confirm-close"
  chmod +x "$BIN/kitty-pane-menu" "$BIN/kitty-confirm-close"
  cp "$REPO/lib/kitty_pane_actions.py" "$BATS_TEST_TMPDIR/co/lib/"
  export PATH="$STUBS:$PATH" KITTY_LISTEN_ON="unix:$BATS_TEST_TMPDIR/sock"
  ADDR="unix:$BATS_TEST_TMPDIR/sock"

  # os-window 1 (macOS window 101): window 50 alone — the last pane, the incident's shape.
  # os-window 2 (macOS window 102): tab 2, window 60, the move destination.
  cat >"$KPG_TREE" <<'JSON'
[{"id": 1, "platform_window_id": 101, "is_active": true,
  "tabs": [{"id": 1, "is_active": true, "is_focused": true,
            "windows": [{"id": 50, "is_active": true, "is_focused": true, "at_prompt": true,
                         "title": "where I clicked", "cwd": "/tmp/a", "foreground_processes": []}]}]},
 {"id": 2, "platform_window_id": 102,
  "tabs": [{"id": 2, "is_active": true, "is_focused": false,
            "windows": [{"id": 60, "is_active": true, "is_focused": false, "at_prompt": true,
                         "title": "destination", "cwd": "/tmp/b", "foreground_processes": []}]}]}]
JSON
}

# The line numbers of the first call matching each pattern, so order is asserted on execution.
first() { grep -n -- "$1" "$CALLS" | head -1 | cut -d: -f1; }
rows() { python3 -c 'import json,sys; [print(json.dumps(json.loads(l), sort_keys=True, ensure_ascii=False)) for l in open(sys.argv[1])]' "$CC_KITTY_PANE_ACTIONS_LOG"; }

@test "1 Move to <window>: destination re-checked, then the guard with the exact argv, then the detach" {
  KPG_PICK="destination — 1 pane" run python3 "$BIN/kitty-pane-menu"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  run grep -c "^guard --window 50 --to $ADDR --mode toggle --scope pane --tool kitty-pane-menu " "$CALLS"
  [ "$output" = "1" ] || { cat "$CALLS"; false; }
  g=$(first '^guard '); d=$(first 'detach-window --match id:50 --target-tab id:2')
  [ -n "$g" ] || { cat "$CALLS"; false; }
  [ -n "$d" ] || { cat "$CALLS"; false; }
  [ "$g" -lt "$d" ] || { cat "$CALLS"; false; }
  # The re-check is a FRESH full `ls` taken after the pick and before the guard.
  [ "$(wc -l <"$KPG_LS_N")" -ge 2 ] || false
  run grep -c 'layout_action equalize' "$CALLS"
  [ "$output" = "1" ] || { cat "$CALLS"; false; }
}

@test "2 guard rc 3: no detach, no second alert from the menu (the guard owns it), result row rc 3" {
  STUB_RC=3 KPG_PICK="destination — 1 pane" run python3 "$BIN/kitty-pane-menu"
  [ "$status" -eq 0 ]
  run grep -c 'detach-window\|layout_action equalize' "$CALLS"
  [ "$output" = "0" ] || { cat "$CALLS"; false; }
  run grep -c 'display alert' "$CALLS"
  [ "$output" = "0" ] || { cat "$CALLS"; false; }
  run rows
  grep -q '"phase": "result".*"rc": 3.*"verdict": "refused"' <<<"$output" || { echo "$output"; false; }
}

@test "3 guard refusing for another reason (rc 4): no detach and no fullscreen alert" {
  STUB_RC=4 KPG_PICK="destination — 1 pane" run python3 "$BIN/kitty-pane-menu"
  [ "$status" -eq 0 ]
  run grep -c 'detach-window\|display alert' "$CALLS"
  [ "$output" = "0" ] || { cat "$CALLS"; false; }
}

@test "4 Move to New Window: guarded; rc 0 detaches, rc 3 does not" {
  KPG_PICK="Move to New Window" run python3 "$BIN/kitty-pane-menu"
  [ "$status" -eq 0 ]
  g=$(first "^guard --window 50 --to $ADDR --mode toggle --scope pane --tool kitty-pane-menu ")
  d=$(first '^kitty @ detach-window --match id:50 --to')
  [ -n "$g" ] || { cat "$CALLS"; false; }
  [ -n "$d" ] || { cat "$CALLS"; false; }
  [ "$g" -lt "$d" ] || { cat "$CALLS"; false; }
  : >"$CALLS"
  STUB_RC=3 KPG_PICK="Move to New Window" run python3 "$BIN/kitty-pane-menu"
  run grep -c 'detach-window' "$CALLS"
  [ "$output" = "0" ] || { cat "$CALLS"; false; }
}

@test "5 the menu's intent row is on disk before the guard and before the destroy" {
  KPG_PICK="destination — 1 pane" run python3 "$BIN/kitty-pane-menu"
  grep -q '^guard .*\[intents=1\]$' "$CALLS" || { cat "$CALLS"; false; }
  grep -q '^kitty @ detach-window .*\[intents=1\] \[wid=\]$' "$CALLS" || { cat "$CALLS"; false; }
  run rows
  [ "${#lines[@]}" -eq 2 ] || { echo "$output"; false; }
  grep -q '"choice": "destination — 1 pane".*"os_window_id": 1.*"panes": 1.*"phase": "intent".*"platform_window_id": 101.*"tool": "kitty-pane-menu".*"wid": 50' <<<"${lines[0]}" || { echo "$output"; false; }
  grep -q '"phase": "result".*"rc": 0.*"verdict": "safe"' <<<"${lines[1]}" || { echo "$output"; false; }
}

@test "6 a cancelled menu logs nothing and runs no guard" {
  KPG_PICK="" run python3 "$BIN/kitty-pane-menu"
  [ "$status" -eq 0 ]
  [ ! -s "$CC_KITTY_PANE_ACTIONS_LOG" ] || { rows; false; }
  run grep -c '^guard ' "$CALLS"
  [ "$output" = "0" ]
}

@test "7 Close Pane is NOT guarded by the menu (confirm-close guards after its own dialog)" {
  KPG_BUTTON=Cancel KPG_PICK="Close Pane" run python3 "$BIN/kitty-pane-menu"
  [ "$status" -eq 0 ]
  # The pane is at a prompt, so confirm-close closes it silently — through ITS guard, once.
  run grep -c '^guard .*--tool kitty-pane-menu' "$CALLS"
  [ "$output" = "0" ] || { cat "$CALLS"; false; }
  run grep -c '^guard --window 50 .*--tool kitty-confirm-close' "$CALLS"
  [ "$output" = "1" ] || { cat "$CALLS"; false; }
}

@test "8 destination gone between the pop and the pick: no guard, no detach, a move-failed line" {
  printf '[{"id": 1, "platform_window_id": 101, "tabs": [{"id": 1, "windows": [{"id": 50}]}]}]\n' \
    >"$BATS_TEST_TMPDIR/tree2.json"
  KPG_TREE2="$BATS_TEST_TMPDIR/tree2.json" KPG_PICK="destination — 1 pane" run python3 "$BIN/kitty-pane-menu"
  [ "$status" -eq 0 ]
  [[ "$output" == *"move failed: destination tab id:"*" is gone"* ]] || { echo "$output"; false; }
  run grep -c '^guard \|detach-window' "$CALLS"
  [ "$output" = "0" ] || { cat "$CALLS"; false; }
  # the attribution row the action log exists for: the pick, and why nothing happened
  run rows
  grep -q '"phase": "result".*"verdict": "destination-gone"' <<<"${lines[1]}" || { echo "$output"; false; }
}

@test "9 confirm-close: Cancel never calls the guard; Close runs the guard, then close-window" {
  busy="$BATS_TEST_TMPDIR/busy.json"
  sed 's/"at_prompt": true/"at_prompt": false/' "$KPG_TREE" >"$busy"
  KPG_TREE="$busy" KPG_BUTTON=Cancel run python3 "$BIN/kitty-confirm-close" window --window 50
  [ "$status" -eq 0 ]
  run grep -c '^guard \|close-window' "$CALLS"
  [ "$output" = "0" ] || { cat "$CALLS"; false; }
  [ ! -s "$CC_KITTY_PANE_ACTIONS_LOG" ] || { rows; false; }

  : >"$CALLS"
  KPG_TREE="$busy" KPG_BUTTON=Close run python3 "$BIN/kitty-confirm-close" window --window 50
  [ "$status" -eq 0 ]
  g=$(first "^guard --window 50 --to $ADDR --mode toggle --scope pane --tool kitty-confirm-close ")
  c=$(first '^kitty @ close-window --match id:50 .*\[intents=1\] \[wid=\]$')
  d=$(first '^osascript - ')
  [ -n "$g" ] && [ -n "$c" ] && [ -n "$d" ] && [ "$d" -lt "$g" ] && [ "$g" -lt "$c" ] || { cat "$CALLS"; false; }
}

@test "10 confirm-close not-busy: guard then close; guard rc 3 closes nothing, no second alert" {
  run python3 "$BIN/kitty-confirm-close" window --window 50
  [ "$status" -eq 0 ]
  g=$(first '^guard --window 50 '); c=$(first 'close-window --match id:50')
  [ -n "$g" ] || { cat "$CALLS"; false; }
  [ -n "$c" ] || { cat "$CALLS"; false; }
  [ "$g" -lt "$c" ] || { cat "$CALLS"; false; }
  : >"$CALLS"; : >"$CC_KITTY_PANE_ACTIONS_LOG"
  STUB_RC=3 run python3 "$BIN/kitty-confirm-close" window --window 50
  run grep -c 'close-window' "$CALLS"
  [ "$output" = "0" ] || { cat "$CALLS"; false; }
  run grep -c 'display alert' "$CALLS"
  [ "$output" = "0" ] || { cat "$CALLS"; false; }
  run rows
  grep -q '"choice": "close-silent".*"phase": "intent"' <<<"${lines[0]}" || { echo "$output"; false; }
  grep -q '"phase": "result".*"rc": 3' <<<"${lines[1]}" || { echo "$output"; false; }
}

@test "11 confirm-close os-window scope passes --scope os-window" {
  run python3 "$BIN/kitty-confirm-close" os-window --window 50
  [ "$status" -eq 0 ]
  run grep -c '^guard --window 50 .*--scope os-window --tool kitty-confirm-close' "$CALLS"
  [ "$output" = "1" ] || { cat "$CALLS"; false; }
}

@test "12 refocus: a parent that is not kitty runs no osascript; a kitty parent is activated by pid" {
  for f in kitty-pane-menu:refocus kitty-confirm-close:refocus_parent_kitty; do
    F="$BIN/${f%%:*}" FN="${f##*:}" python3 - <<'PY'
import importlib.machinery, importlib.util, os, types
loader = importlib.machinery.SourceFileLoader("subj", os.environ["F"])
spec = importlib.util.spec_from_loader("subj", loader)
m = importlib.util.module_from_spec(spec); loader.exec_module(m)
for comm, want in (("/bin/zsh", False), ("/Applications/kitty.app/Contents/MacOS/kitty", True)):
    calls = []
    def fake_run(argv, *a, **k):
        calls.append(list(argv))
        out = comm + "\n" if argv[0] == "ps" else ""
        return types.SimpleNamespace(returncode=0, stdout=out, stderr="")
    m.subprocess.run = fake_run
    m.os.getppid = lambda: 4242
    getattr(m, os.environ["FN"])()
    osa = [c for c in calls if c[0] == "osascript"]
    assert bool(osa) == want, (comm, calls)
    if want:
        script = " ".join(osa[0])
        assert "NSRunningApplication" in script and "4242" in script, script
        assert 'application "kitty"' not in script, script
print("ok")
PY
  done
}

@test "13 the menu's chooser dialog never names application kitty" {
  KPG_PICK="" run python3 "$BIN/kitty-pane-menu"
  grep -q 'choose from list' "$CALLS" || { cat "$CALLS"; false; }
  run grep -c 'application "kitty"' "$CALLS"
  [ "$output" = "0" ] || { cat "$CALLS"; false; }
}

@test "14 Paste targets the clicked pane with --self + KITTY_WINDOW_ID, never the ignored action --match" {
  # RED-proof: against the pre-fix menu the call is `action --match id:50 paste_from_selection`, which
  # kitty 0.48.2 runs on the ACTIVE window.
  KPG_PICK="Paste" run python3 "$BIN/kitty-pane-menu"
  [ "$status" -eq 0 ]
  grep -q '^kitty @ .*action --self paste_from_selection .*\[wid=50\]' "$CALLS" || { cat "$CALLS"; false; }
  run grep -c 'action --match' "$CALLS"
  [ "$output" = "0" ] || { cat "$CALLS"; false; }
}

@test "15 a move that EMPTIES its source follows the pane after the source closed; one that does not, never focuses" {
  # docs/research/kitty-lastpane-move-2026-10-19/README.md § 1a: the guard's exit from fullscreen
  # takes the display to the desktop and nothing took the operator on. The source's platform id is
  # one no window owns, so the real window-server read says "gone" without touching a real window.
  export KPG_TREE2="$BATS_TEST_TMPDIR/tree2.json"
  sed 's/"platform_window_id": 101/"platform_window_id": 2147483646/' "$KPG_TREE" >"$KPG_TREE.x"
  mv "$KPG_TREE.x" "$KPG_TREE"
  # from the 2nd full ls on (the destination re-check, then the follow's poll) os-window 1 is gone
  cat >"$KPG_TREE2" <<'JSON'
[{"id": 2, "platform_window_id": 102,
  "tabs": [{"id": 2, "is_active": true, "is_focused": false,
            "windows": [{"id": 60, "is_active": false, "is_focused": false, "at_prompt": true,
                         "title": "destination", "cwd": "/tmp/b", "foreground_processes": []},
                        {"id": 50, "is_active": true, "is_focused": false, "at_prompt": true,
                         "title": "where I clicked", "cwd": "/tmp/a", "foreground_processes": []}]}]}]
JSON
  KPG_PICK="destination — 1 pane" run python3 "$BIN/kitty-pane-menu"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  d=$(first 'detach-window --match id:50 --target-tab id:2'); f=$(first 'focus-window --match id:50')
  [ -n "$d" ] || { cat "$CALLS"; false; }
  [ -n "$f" ] || { cat "$CALLS"; false; }
  [ "$d" -lt "$f" ] || { cat "$CALLS"; false; }
  rows | grep -q '"followed": true' || { rows; false; }
  # the source never goes away (case 1's shape): no focus, today's behavior
  unset KPG_TREE2; : >"$CALLS"; : >"$KPG_LS_N"
  KPG_PICK="destination — 1 pane" run python3 "$BIN/kitty-pane-menu"
  [ "$status" -eq 0 ]
  run grep -c 'focus-window' "$CALLS"
  [ "$output" = "0" ] || { cat "$CALLS"; false; }
}
