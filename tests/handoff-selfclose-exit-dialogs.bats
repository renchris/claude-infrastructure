#!/usr/bin/env bats
# handoff-fire.sh self-close under kitty — the /exit DIALOGS (2026-10-03, pane 10).
#
# THE INCIDENT. `self-close --successor 83` typed /exit into pane 10. The /exit TOOK — and on
# 2.1.284 that is not the end: the session had queued a Claude-drafted feedback report, so /exit
# showed "You have 1 unsent feedback draft · Enter to review & send · Esc to discard and exit". The
# watcher's one blind CR at 60s opened the drafts panel, and the pane stayed on that panel (in the
# end inside one draft, "Send feedback" focused — one more CR would have SENT it). At 180s the
# force-close met bin/it2-kitty's composer guard, which read the panel as UNKNOWN and refused all
# four attempts (rc 67), correctly; hf_alarm close-failed-live, finished session left alive.
#
# THE KEYS MEAN OPPOSITE THINGS PER DIALOG (read out of the bundle's /exit `call`, then rendered on
# a throwaway kitty pane — the fixtures under tests/fixtures/selfclose-exit-dialogs/ are those
# captures, the panel-draft one is pane 10's own refusal snapshot):
#   nudge        Enter = open the panel           Esc = DISCARD the drafts and exit
#   panel        Esc   = close, drafts kept       Enter = review, and inside a draft SEND it
#   background   index of "Exit and stop tasks"   Esc = Stay — the exit is cancelled
#
# So the fix is a screen reader, not a better blind key: hooks/lib/pane-modal.sh (the one
# enumeration) recognises the dialogs, and the watcher's sc_exit_unblock presses AT MOST ONE key per
# checkpoint. Part 1 pins the recogniser on the real screens; part 2 runs the real watcher against a
# pane whose screen advances only when it receives the right key, and whose close refuses while
# claude is alive (the composer guard), so a wrong or missing key ends in close-failed-live.

setup() {
  export CC_FIRE_CAPACITY_GATE=off CC_FIRE_HEADROOM_GATE=off
  # Hermetic: the subject never sees the operator's live ~/, and its account-sweep seams point at
  # ABSENT paths (those sensors fail open on one) instead of /tmp defaults and a PATH-resolved tool.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/absent-sweep-stamp.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/absent-claude-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-lock-"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"
  LIB="$REPO/hooks/lib/pane-modal.sh"
  FX="$REPO/tests/fixtures/selfclose-exit-dialogs"

  SHIM="$BATS_TEST_TMPDIR/shim"; mkdir -p "$SHIM"
  export PS_DEAD_DIR="$BATS_TEST_TMPDIR/dead"; mkdir -p "$PS_DEAD_DIR"
  export PS_TTY_REG="$BATS_TEST_TMPDIR/ps-tty-reg"; : > "$PS_TTY_REG"
  # The liveness model of tests/handoff-selfclose.bats, reduced to what the watcher asks: a tty's
  # root shell, claude as its DESCENDANT (the expect shape), and the foreground group. A dead-marked
  # tty keeps its shell and loses claude, so pane_cc_state reads `shell`.
  cat > "$SHIM/ps" <<'SH'
#!/usr/bin/env bash
reg="$PS_TTY_REG"
root_pid() { local n; n="$(grep -nxF -- "$1" "$reg" | head -1 | cut -d: -f1)"
  if [ -z "$n" ]; then printf '%s\n' "$1" >> "$reg"; n="$(wc -l < "$reg" | tr -d ' ')"; fi
  printf '%s' "$(( 700000 + n * 10 ))"; }
tty_live() { [ ! -e "$PS_DEAD_DIR/$1" ]; }
fmt="" tty="" pid="" pgid="" all=0
while [ $# -gt 0 ]; do case "$1" in
  -axo|-Ao) fmt="$2"; all=1; shift 2 ;; -o) fmt="$fmt${2:-}"; shift 2 ;;
  -t) tty="${2##*/}"; shift 2 ;; -p) pid="${2:-}"; shift 2 ;; -g) pgid="${2:-}"; shift 2 ;; *) shift ;;
esac; done
if [ "$all" = 1 ]; then
  while IFS= read -r t; do [ -n "$t" ] || continue; p="$(root_pid "$t")"; printf '%s 1\n' "$p"
    tty_live "$t" && printf '%s %s\n' "$((p + 1))" "$p"; done < "$reg"; exit 0; fi
if [ -n "$pid" ]; then
  while IFS= read -r t; do [ -n "$t" ] || continue; p="$(root_pid "$t")"
    if [ "$pid" = "$p" ]; then c=zsh; a=-zsh
    elif [ "$pid" = "$((p + 1))" ] && tty_live "$t"; then c=claude; a=/opt/cc/bin/claude
    else continue; fi
    case "$fmt" in *comm*) echo "$c" ;; *tty*) echo "$t" ;; *args*) echo "$a" ;; esac; exit 0
  done < "$reg"; exit 0; fi
if [ -n "$pgid" ]; then
  while IFS= read -r t; do [ -n "$t" ] || continue; p="$(root_pid "$t")"; [ "$pgid" = "$p" ] || continue
    case "$fmt" in *comm*) echo "$p zsh" ;; *) echo "$p" ;; esac; exit 0; done < "$reg"; exit 0; fi
[ -n "$tty" ] || exit 0
p="$(root_pid "$tty")"
case "$fmt" in *comm*) tty_live "$tty" && echo expect ;; *) echo "$p" ;; esac
exit 0
SH
  # Every sleep in the watcher is a wait for the outside world, which here answers instantly.
  printf '#!/bin/sh\nexit 0\n' > "$SHIM/sleep"
  chmod +x "$SHIM/ps" "$SHIM/sleep"
  export PATH="$SHIM:$PATH"

  # THE PANE. ~/.claude/bin/it2 is the only transport the watcher uses; this one serves a screen out
  # of $HOME/screens/<state> and moves the state ONLY on the key that genuinely advances it. A key
  # that does not advance it is still recorded, so a wrong key is visible, not merely ineffective.
  H="$BATS_TEST_TMPDIR/home"; mkdir -p "$H/.claude/bin" "$H/.claude/cc-roles" "$H/screens"
  cp "$FX"/*.txt "$H/screens/"
  printf 'DESK-PANE\n' > "$H/.claude/cc-roles/desk"
  cat > "$H/.claude/bin/it2" <<'SH'
#!/usr/bin/env bash
st="$(cat "$HOME/state")"
case "${1:-} ${2:-}" in
  "session list") printf '%s\n' PREDSID; exit 0 ;;
  "session read") cat "$HOME/screens/$st.txt"; exit 0 ;;
  "session close")
    printf 'close\n' >> "$HOME/keys.log"
    # bin/it2-kitty's composer guard: a pane still running claude behind a dialog is refused.
    [ -e "$PS_DEAD_DIR/TTY-A" ] && exit 0
    exit 67 ;;
  "session send")
    shift 2; [ "${1:-}" = -s ] && shift 2
    k="$*"
    case "$k" in $'\r') n=CR ;; $'\x1b') n=ESC ;; *) n="TEXT:$k" ;; esac
    printf '%s@%s\n' "$n" "$st" >> "$HOME/keys.log"
    gone() { : > "$PS_DEAD_DIR/TTY-A"; echo shell > "$HOME/state"; }
    case "$st:$n" in
      nudge:CR)           echo panel-list > "$HOME/state" ;;
      panel-list:ESC)     echo bgwork > "$HOME/state" ;;
      panel-draft:ESC)    echo bgwork > "$HOME/state" ;;
      bgwork:TEXT:1)      gone ;;
      empty:TEXT:/exit)   echo typed > "$HOME/state" ;;
      typed:CR)           gone ;;
      stranded:CR)        gone ;;
    esac
    exit 0 ;;
esac
exit 0
SH
  cat > "$H/.claude/bin/cc-notify" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$HOME/ccnotify-calls.log"; exit 0
SH
  chmod +x "$H/.claude/bin/it2" "$H/.claude/bin/cc-notify"

  # composer screens for the composer half (recycle_nudge_decision / composer_content)
  RULE='────────────────────────────────────────────────────────────'
  printf '⏺ done\n%s\n❯ \n%s\n  (1) #7 abc 20%%\n' "$RULE" "$RULE" > "$H/screens/empty.txt"
  printf '⏺ done\n%s\n❯ /exit\n%s\n  (1) #7 abc 20%%\n' "$RULE" "$RULE" > "$H/screens/typed.txt"
  cp "$H/screens/typed.txt" "$H/screens/stranded.txt"
  printf '⏺ done\n%s\n❯ please also check the deploy log\n%s\n  (1) #7 abc 20%%\n' "$RULE" "$RULE" > "$H/screens/draft.txt"
  printf '  Do you want to make this edit to f.txt?\n  ❯ 1. Yes\n    2. No\n  Esc to cancel\n' > "$H/screens/unknown.txt"
  printf '➜ ~ \n' > "$H/screens/shell.txt"

  # kitty identity is what selects the screen-reading arm; the DIVERT env stays off so nothing here
  # can reach a real kitty (hf_close_pane's post-read then reports `unverified`, which is fine).
  export CC_TERM=kitty
  unset KITTY_WINDOW_ID KITTY_LISTEN_ON
  export IT2_WRAPPER_NO_KITTY=1
}

watch() { # $1 = initial screen; remaining = extra env
  printf '%s\n' "$1" > "$H/state"; shift
  run env HOME="$H" HF_SELFCLOSE_GRACE_S=180 HF_SELFCLOSE_GRACE_STEP_S=5 "$@" \
      bash "$HF" __selfclose PREDSID TTY-A
}
keys() { cat "$H/keys.log" 2>/dev/null; }

# ── 1. THE RECOGNISER, ON THE REAL SCREENS ───────────────────────────────────────────────────────

@test "lib: the unsent-drafts nudge is recognised as nudge" {
  run bash -c ". '$LIB'; pane_drafts_dialog < '$FX/nudge.txt'"
  [ "$status" -eq 0 ]; [ "$output" = nudge ]
}

@test "lib: the drafts panel is recognised in BOTH views — the list and pane 10's open draft" {
  run bash -c ". '$LIB'; pane_drafts_dialog < '$FX/panel-list.txt'"
  [ "$status" -eq 0 ]; [ "$output" = panel ]
  run bash -c ". '$LIB'; pane_drafts_dialog < '$FX/panel-draft.txt'"
  [ "$status" -eq 0 ]; [ "$output" = panel ]
}

@test "lib: the background dialog yields the STOP index (1) and the recycle's KEEP index (2) unchanged" {
  run bash -c ". '$LIB'; pane_bgwork_stop_choice < '$FX/bgwork.txt'"
  [ "$status" -eq 0 ]; [ "$output" = 1 ]
  run bash -c ". '$LIB'; pane_bgwork_choice < '$FX/bgwork.txt'"
  [ "$status" -eq 0 ]; [ "$output" = 2 ]
}

@test "lib: a pane that only QUOTES the dialogs above a live composer is not at one" {
  # This repo's own panes display these strings constantly (this file, the lib, the commit).
  printf '%s\n' '  the nudge reads "You have 1 unsent feedback draft" and then' \
    '  "Enter to review & send · Esc to discard and exit" — see pane-modal.sh' \
    '────────────────────────────────' '❯ ' '────────────────────────────────' '  (1) #7 abc' \
    > "$BATS_TEST_TMPDIR/prose.txt"
  run bash -c ". '$LIB'; pane_drafts_dialog < '$BATS_TEST_TMPDIR/prose.txt'"
  [ "$status" -eq 1 ]
}

@test "lib: a nudge frame left in scrollback does not outvote the panel at the bottom" {
  cat "$FX/nudge.txt" "$FX/panel-list.txt" > "$BATS_TEST_TMPDIR/both.txt"
  run bash -c ". '$LIB'; pane_drafts_dialog < '$BATS_TEST_TMPDIR/both.txt'"
  [ "$output" = panel ]
}

# ── 2. THE WATCHER, END TO END ───────────────────────────────────────────────────────────────────

@test "pane 10's sequence: nudge → Enter, panel → Esc, background → its stop index; claude exits and the pane closes" {
  watch nudge
  [ "$status" -eq 0 ]
  [ "$(keys | head -3 | tr '\n' ' ')" = "CR@nudge ESC@panel-list TEXT:1@bgwork " ]
  keys | grep -qx close
  [[ "$output" == *"enter:drafts-nudge"* ]]
  [[ "$output" == *"esc:drafts-panel"* ]]
  [[ "$output" == *"key-1:background-work-stop"* ]]
  [ "$(printf '%s\n' "$output" | tail -1)" = "→ closed pane PREDSID (attempt 1/4)" ]   # the log ENDS in its verdict
  ! grep -q CLOSE-FAILED "$H/ccnotify-calls.log" 2>/dev/null
}

@test "pane 10's final screen — an OPEN draft with 'Send feedback' focused — gets Esc, never CR" {
  watch panel-draft
  [ "$(keys | head -1)" = "ESC@panel-draft" ]
  ! keys | grep -q 'CR@panel-draft'
  keys | grep -qx close
}

@test "an unrecognised dialog gets NO key, and the close-failed-live guard still refuses" {
  watch unknown
  ! keys | grep -qv '^close$'                       # not one keystroke reached the pane
  [[ "$output" == *"hold:"* ]]
  [[ "$output" == *"claude is STILL RUNNING"* ]]
  grep -q HANDOFF-CLOSE-FAILED-LIVE "$H/ccnotify-calls.log"
}

@test "an operator draft in the composer is never submitted — the old blind 60s CR would have" {
  watch draft
  ! keys | grep -q '^CR@draft'
  [[ "$output" == *"hold:hold"* ]]
}

@test "a stranded /exit in the composer is submitted (what the old 60s CR was for)" {
  watch stranded
  [ "$(keys | head -1)" = "CR@stranded" ]
  keys | grep -qx close
}

@test "an EMPTY composer with claude alive gets ONE verified /exit retype, and not before 40s" {
  watch empty
  [ "$(keys | grep -c 'TEXT:/exit')" -eq 1 ]
  [[ "$output" == *"at 20s → hold:composer-empty"* ]]
  [[ "$output" == *"at 40s → retype:composer-empty"* ]]
  keys | grep -qx close
}

@test "iTerm2 identity is untouched: no screen read, the legacy CR at 60s" {
  watch draft CC_TERM=iterm2
  [ "$(keys | grep -c '^CR@')" -eq 1 ]
  [[ "$output" != *"exit-unblock"* ]]
}
