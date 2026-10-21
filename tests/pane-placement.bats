#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031
#   Structurally false under bats: every @test body is its own subshell, so an `export` inside one
#   is meant to be test-local.
#
# scripts/lib/pane-placement.sh — cc_place_pane, the ONE placement policy (lr-wake incident
# 2026-10-18, docs/research/lr-wake-incident-2026-10-18/REPORT.md §4 Wave D, b-tabs.md §5).
#
# The operator rule it encodes: NO kitty tabs, ever; every OS window fullscreen on its own Space; at
# most 4 vertical split panes per Space. Overnight, 22 agent fires became hidden tabs in one OS window
# and three lr spawns became lone, non-fullscreen OS windows (428, 429, 398). Every case below reads
# what the policy SENT kitty (a recording stub whose `ls` is mutable, so a sequence of fires sees its
# own earlier panes) or what it LOGGED, never its internals.
#
# RED on origin/main before this wave: the library does not exist, so every case fails at its first
# assertion; the lr_kitty_spawn cases fail on main's lr-lib.sh, which opened a bare os-window.
#
# Hermetic: HOME, the spawn log and the kitty binary are per-test; no case talks to a real kitty.

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_SPAWN_LOG_FILE="$BATS_TEST_TMPDIR/spawns.jsonl"
  export KLOG="$BATS_TEST_TMPDIR/kitty.log" KSTATE="$BATS_TEST_TMPDIR/ls.json"
  : > "$KLOG"
  export CC_PLACE_KITTY_BIN="$BATS_TEST_DIRNAME/fixtures/pane-placement/fake-kitty.py"
  export CC_TERM_KITTY_TO="unix:$BATS_TEST_TMPDIR/sock"
  export CC_PLACE_LOAD_PER_CORE=0
  unset CC_PLACE_FOCUS CC_PLACE_REQUESTED CC_PLACE_DETAIL CC_MAX_PANES_PER_SPACE KLS_BROKEN KFAIL_SPLIT KSLOW_SPLIT
  unset KITTY_WINDOW_ID KITTY_LISTEN_ON
  # shellcheck source=/dev/null
  . "$REPO/scripts/lib/pane-placement.sh"
}

# one OS window (id 18), one splits tab, panes <ids…>
one_window() {
  python3 -c '
import json, sys
ids = [int(x) for x in sys.argv[2:]]
json.dump([{"id": 18, "tabs": [{"id": 146, "layout": "splits",
           "windows": [{"id": i, "columns": 80, "user_vars": {}} for i in ids]}]}], open(sys.argv[1], "w"))' "$KSTATE" "$@"
}
# append an OS window <osw> holding panes <ids…> to the state
add_window() {
  python3 -c '
import json, sys
d = json.load(open(sys.argv[1])); o = int(sys.argv[2]); ids = [int(x) for x in sys.argv[3:]]
d.append({"id": o, "tabs": [{"id": o * 100, "layout": "splits",
          "windows": [{"id": i, "columns": 80, "user_vars": {}} for i in ids]}]})
json.dump(d, open(sys.argv[1], "w"))' "$KSTATE" "$@"
}
launches() { grep -c -- " launch $1" "$KLOG" || true; }
place() { cc_place_pane "$@" -- --var probe=1 -- /bin/zsh -l; }
# shape of the tree: one line per OS window, `<id> tabs=<n> panes=<n>`
shape() {
  python3 -c '
import json, sys
for o in json.load(open(sys.argv[1])):
    print("%s tabs=%d panes=%d" % (o["id"], len(o["tabs"]), sum(len(t["windows"]) for t in o["tabs"])))' "$KSTATE"
}

@test "3 panes in the anchor's OS window: a vsplit beside the anchor, no focus steal, logged requested/given" {
  one_window 344 345 346
  run place 344 /work/a
  [ "$status" -eq 0 ]
  [ "$output" = 900 ]
  grep -qF -- "launch --type=window --location=vsplit --match window_id:344 --next-to id:344 --cwd=/work/a --dont-take-focus --var cc_place_token=" "$KLOG"
  grep -qF -- "--var probe=1 -- /bin/zsh -l" "$KLOG"
  [ "$(launches --type=os-window)" -eq 0 ]
  run jq -r 'select(.pane=="900") | "\(.surface) \(.detail)"' "$CC_SPAWN_LOG_FILE"
  [[ "$output" == "window cc_place_pane requested=split given=split anchor:344 os_window:18 step:1 panes_before:3 "* ]] || { echo "$output"; false; }
}

@test "4 panes in the anchor's OS window and no other room: a NEW fullscreen OS window, keep-focus, never a tab" {
  one_window 344 345 346 347
  run place 344 /work/a
  [ "$status" -eq 0 ]
  grep -qF -- "launch --type=os-window --cwd=/work/a --os-window-state=fullscreen --keep-focus" "$KLOG"
  [ "$(launches --type=window)" -eq 0 ]
  ! grep -q -- '--type=tab' "$KLOG" || false
  run jq -r 'select(.pane=="900") | "\(.surface) \(.detail)"' "$CC_SPAWN_LOG_FILE"
  [[ "$output" == "os-window cc_place_pane requested=split given=os-window-fs anchor:344 reason:anchor-full "* ]] || { echo "$output"; false; }
}

@test "a full anchor window with another OS window that has room: split THAT window (step 2), cwd still pinned to the anchor" {
  one_window 344 345 346 347
  add_window 21 501 502
  run place 344 current
  [ "$status" -eq 0 ]
  grep -qF -- "launch --type=window --location=vsplit --match window_id:502 --next-to id:502 --source-window id:344 --cwd=current" "$KLOG"
  [ "$(launches --type=os-window)" -eq 0 ]
  [ "$(shape)" = "18 tabs=1 panes=4
21 tabs=1 panes=3" ]
}

@test "step 2 fills the FULLEST window with room first, so overflow windows reach 4 before another opens" {
  one_window 344 345 346 347
  add_window 21 501
  add_window 22 601 602 603
  run place 344 /work/a
  [ "$status" -eq 0 ]
  grep -qF -- "--match window_id:" "$KLOG"
  grep -q -- "--match window_id:60[123] " "$KLOG"
}

# mark OS window <osw> as an lr-recon rig window: every pane's cwd under <root>
rig_window() {
  python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
for o in d:
    if o["id"] == int(sys.argv[2]):
        for t in o["tabs"]:
            for w in t["windows"]: w["cwd"] = sys.argv[3] + "/work/s%02d" % (w["id"] % 100)
json.dump(d, open(sys.argv[1], "w"))' "$KSTATE" "$@"
}

@test "step 2 never splits into an lr-recon rig OS window, and a rig pane never spills out of its rig (W4b)" {
  one_window 344 345 346 347
  add_window 21 501
  add_window 22 601 602 603
  rig_window 22 /private/tmp/lrh-ab12-cure      # the fullest window with room is a rig arm's
  run place 344 /work/a
  [ "$status" -eq 0 ]
  grep -qF -- "--match window_id:501 " "$KLOG"
  ! grep -q -- "--match window_id:60[123] " "$KLOG" || false
  # a rig pane whose own window is full: the operator's window and the OTHER arm's both have room,
  # and neither is taken; it gets a new OS window (the rig's containment sampler would read either)
  : > "$KLOG"
  one_window 344 345 346 347
  rig_window 18 /tmp/lr-rig
  add_window 21 501
  add_window 22 601 602 603
  rig_window 22 /tmp/lrh-ab12-red
  run place 344 /work/a
  [ "$status" -eq 0 ]
  [ "$(launches --type=window)" -eq 0 ]
  [ "$(launches --type=os-window)" -eq 1 ]
}

@test "a window holding 2 tabs is never split into, and a zoomed (stack) tab is never split into" {
  one_window 344 345
  python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
d[0]["tabs"].append({"id": 147, "layout": "splits", "windows": [{"id": 360, "columns": 80}]})
d.append({"id": 30, "tabs": [{"id": 3000, "layout": "stack", "windows": [{"id": 700, "columns": 80}]}]})
json.dump(d, open(sys.argv[1], "w"))' "$KSTATE"
  run place 344 /work/a
  [ "$status" -eq 0 ]
  [ "$(launches --type=window)" -eq 0 ]
  [ "$(launches --type=os-window)" -eq 1 ]
}

@test "REPLAY: 16 fires from one named anchor give 4 new fullscreen OS windows, each 1 tab and at most 4 panes" {
  # The overnight shape: pane 344's OS window already full, 16 rescue fires anchored on it.
  one_window 344 345 346 347
  for _ in $(seq 16); do
    place 344 current >/dev/null || false
  done
  [ "$(launches --type=os-window)" -eq 4 ]
  [ "$(launches --type=window)" -eq 12 ]
  [ "$(grep -c -- '--os-window-state=fullscreen' "$KLOG")" -eq 4 ]
  ! grep -q -- '--type=tab' "$KLOG" || false
  run shape
  [ "${#lines[@]}" -eq 5 ]
  for l in "${lines[@]}"; do
    [[ "$l" == *" tabs=1 panes=4" ]] || { echo "$output"; false; }
  done
  [ "$(jq -s 'length' "$CC_SPAWN_LOG_FILE")" -eq 16 ]
  [ "$(jq -s '[.[] | select(.surface == "tab" or .surface == "bg-tab")] | length' "$CC_SPAWN_LOG_FILE")" -eq 0 ]
}

@test "an unreadable census is a fullscreen OS window, never a blind split" {
  one_window 344
  export KLS_BROKEN=1
  run place 344 /work/a
  [ "$status" -eq 0 ]
  [ "$(launches --type=window)" -eq 0 ]
  grep -qF -- "--os-window-state=fullscreen" "$KLOG"
  grep -q 'reason:census-unreadable' "$CC_SPAWN_LOG_FILE"
}

@test "split retries scale with load: 1 attempt at load 0, 3 at load 8.5, then the fullscreen fallback" {
  one_window 344
  export KFAIL_SPLIT=1
  timeout_bin="$(command -v timeout || command -v gtimeout || true)"
  [ -n "$timeout_bin" ] || skip "no timeout binary"
  run place 344 /work/a
  [ "$status" -eq 0 ]
  [ "$(launches --type=window)" -eq 1 ]
  [ "$(launches --type=os-window)" -eq 1 ]
  : > "$KLOG"; one_window 344
  CC_PLACE_LOAD_PER_CORE=8.5 run place 344 /work/a
  [ "$status" -eq 0 ]
  [ "$(launches --type=window)" -eq 3 ]
  [ "$(launches --type=os-window)" -eq 1 ]
  grep -q 'given=os-window-fs .*reason:split-failed tries:3 load_per_core:8.5' "$CC_SPAWN_LOG_FILE"
}

@test "a split that times out AFTER kitty created the window is adopted, never launched twice" {
  command -v timeout >/dev/null 2>&1 || command -v gtimeout >/dev/null 2>&1 || skip "no timeout binary"
  # A BASH stub, not the python one: under heavy load python's own startup outlasts a 2 s bound, so
  # the timeout would kill it before it created anything and the case would test the wrong thing
  # (measured 2026-10-18 at load 36/core). This one records the window (with the caller's token)
  # within milliseconds, then hangs past the bound; `ls` serves what it recorded.
  S="$BATS_TEST_TMPDIR/slow-kitty"
  cat > "$S" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >> "$KLOG"
case " $* " in
  *" ls "*)
    w=""; [ -s "$KSTATE.tok" ] && w=",{\"id\":900,\"columns\":80,\"user_vars\":{\"cc_place_token\":\"$(cat "$KSTATE.tok")\"}}"
    printf '[{"id":18,"tabs":[{"id":146,"layout":"splits","windows":[{"id":344,"columns":80,"user_vars":{}}%s]}]}]\n' "$w"
    exit 0 ;;
  *" --type=window "*)
    for a in "$@"; do case "$a" in cc_place_token=*) printf '%s' "${a#cc_place_token=}" > "$KSTATE.tok" ;; esac; done
    sleep 30; echo 900; exit 0 ;;
esac
echo 901
SH
  chmod +x "$S"
  CC_PLACE_KITTY_BIN="$S" CC_PLACE_BOUND_BASE_S=2 run place 344 /work/a
  [ "$status" -eq 0 ]
  [ "$output" = 900 ]
  [ "$(launches --type=window)" -eq 1 ]
  [ "$(launches --type=os-window)" -eq 0 ]
}

@test "usage: no -- separator, or cwd \`current\` with no anchor, is rc 2 and sends nothing" {
  one_window 344
  run cc_place_pane 344 /work/a /bin/zsh
  [ "$status" -eq 2 ]
  run cc_place_pane "" current -- /bin/zsh
  [ "$status" -eq 2 ]
  [ ! -s "$KLOG" ]
}

@test "a non-integer anchor (an iTerm2 UUID) never reaches --match: it is placed as unanchored" {
  one_window 344 345
  run place "8F3C1D2E-AAAA-BBBB-CCCC-000000000001" /work/a
  [ "$status" -eq 0 ]
  ! grep -q -- '--match window_id:8F3C' "$KLOG" || false
  grep -qF -- "--match window_id:" "$KLOG"     # step 2: OS window 18 has room
}

@test "every launch fails: rc 1 and NO spawn row (a row means a pane exists)" {
  one_window 344 345 346 347
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s"\n[ "$3" = ls ] && cat "%s"\nexit 1\n' "$KLOG" "$KSTATE" > "$BATS_TEST_TMPDIR/dead-kitty"
  chmod +x "$BATS_TEST_TMPDIR/dead-kitty"
  CC_PLACE_KITTY_BIN="$BATS_TEST_TMPDIR/dead-kitty" run place 344 /work/a
  [ "$status" -eq 1 ]
  [ ! -s "$CC_SPAWN_LOG_FILE" ]
}

# ── lr_kitty_spawn goes through the policy (the 428 / 429 / 398 shape) ──────────────────────────
lr_spawn() {
  export LR_LIB_DIR="$REPO/scripts/limit-recover" CC_TERM_KITTY="$CC_PLACE_KITTY_BIN"
  # shellcheck source=/dev/null
  . "$REPO/scripts/limit-recover/lr-lib.sh"
  lr_kitty_spawn /tmp/lr-launch-x.sh /tmp/wt 509e3aad-0000-0000-0000-000000000001 next3 "$@"
}

@test "lr_kitty_spawn with NO anchor splits into an OS window with room, instead of a lone 1-pane window" {
  one_window 25 26 27
  run lr_spawn
  [ "$status" -eq 0 ]
  [ "$output" = 900 ]
  grep -qF -- "launch --type=window --location=vsplit --match window_id:" "$KLOG"
  [ "$(launches --type=os-window)" -eq 0 ]
  grep -q '"detail":"cc_place_pane requested=os-window given=split .*lr_kitty_spawn .*continuation_of:509e3aad target:next3' "$CC_SPAWN_LOG_FILE"
}

@test "lr_kitty_spawn with NO anchor and every window full opens a FULLSCREEN OS window at the explicit cwd" {
  one_window 25 26 27 28
  run lr_spawn
  [ "$status" -eq 0 ]
  grep -qF -- "launch --type=os-window --cwd=/tmp/wt --os-window-state=fullscreen" "$KLOG"
}

@test "lr_kitty_spawn beside a FULL anchor does not make a fifth pane" {
  one_window 25 26 27 28
  run lr_spawn 26
  [ "$status" -eq 0 ]
  [ "$(launches --type=window)" -eq 0 ]
  grep -qF -- "launch --type=os-window --source-window id:26 --cwd=current --os-window-state=fullscreen" "$KLOG"
  [ "$(shape | head -1)" = "18 tabs=1 panes=4" ]
}
