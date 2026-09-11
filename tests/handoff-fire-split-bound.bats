#!/usr/bin/env bats
# handoff-fire.sh SPLIT BOUND + ADOPTION — the "anchor gone" refusal that was never an anchor loss.
#
# Incident, 2026-09-07..10 (docs/research/cloud-lane-redesign-2026-09-10/C3-local-refusals.md §1c):
# 69 of 297 dispatcher fires exited rc 1 with "firing pane N not found in iTerm2 (settled + retried) —
# anchor gone". The anchors were LIVE — 535, 643 and 672 each took successful splits hours later, and a
# kitty window id is never reused within one kitty process. What happened instead: it2_split bounded a
# whole `it2-kitty session split` run with hf_bounded's ONE-round-trip 10s, around a kitty call that
# it2-kitty itself bounds at 15s. Under load the outer bound killed a split kitty had already COMPLETED:
# the pane existed and was running the predelivered brief, the 0.8s retry launched a second, and the
# refusal said "Nothing was launched". Fire 4b0095d1ee73 left two transcripts 12s apart under ONE
# engagement marker (6a5a218fd9a8 and 9d1c8dadf1f8 the same, 15s and 16s apart).
#
# The fake it2 below models kitty on the one axis that matters: it CREATES the pane before it answers,
# and its answer can be slow, garbled, or preceded by a warning. Every case counts creations, because a
# fire that "fails" after creating a pane is the defect, not a safe refusal.

setup() {
  export CC_FIRE_CAPACITY_GATE=off CC_FIRE_HEADROOM_GATE=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  # Hermetic terminal: this suite may itself run inside a kitty pane, and an inherited KITTY_WINDOW_ID
  # would point in_kitty/kt at the operator's REAL kitty. Kitty cases opt back in explicitly.
  unset KITTY_WINDOW_ID KITTY_LISTEN_ON CC_TERM_KITTY_TO IT2_WRAPPER_NO_KITTY IT2_KITTY_TIMEOUT_S \
        HANDOFF_SPLIT_TIMEOUT_S HF_SPLIT_TIMEOUT_S
  # A fired pane carries these (bin/it2-kitty --env), so a suite run from one would otherwise hand the
  # fake splitter a stranger's command and record it as this fire's launch env.
  unset CC_PANE_CMD CC_PANE_CMD_INTERACTIVE CC_PANE_CMD_DIR
  # Non-$HOME seams the script reads: pinned to ABSENT paths inside the test dir, never /tmp or PATH.
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/account-sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/claude-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-"
  eval "$(sed -n '/^hf_bounded() {/,/^}/p;/^hf_bounded_s() {/,/^}/p;/^it2_split() {/,/^}/p;/^spawn() {/,/^}/p;/^hf_adopt_split_pane() {/,/^}/p;/^hf_anchor_live() {/,/^}/p;/^in_kitty() {/p;/^kt() {/p' "$HF")"
  # The script's OWN bound configuration, not a copy of it — so a pre-fix tree is measured with the
  # bound it actually shipped.
  eval "$(grep -E '^HF_(SPLIT_)?TIMEOUT_S=' "$HF")"
  HF_TIMEOUT_BIN="$(command -v timeout || command -v gtimeout || echo /opt/homebrew/bin/timeout)"

  export CREATED="$BATS_TEST_TMPDIR/created"; : > "$CREATED"
  FAKE_IT2="$BATS_TEST_TMPDIR/it2"
  cat > "$FAKE_IT2" <<'SH'
#!/usr/bin/env bash
[ "${1:-}" = session ] && [ "${2:-}" = split ] || exit 0
shift 2; id=""
while [ $# -gt 0 ]; do case "$1" in -s) id="${2:-}"; shift 2 ;; *) shift ;; esac; done
if [ "$id" != "${LIVE_ID:-LIVE}" ]; then
  echo "Error: window_id is not a recognized location in window_id:$id" >&2; exit 1   # real kitty text
fi
if [ "${FAKE_MODE:-ok}" = refuse ]; then echo "it2-kitty: kitty launch failed (rc=1): boom" >&2; exit 1; fi
# kitty CREATES the pane first — with the launch env it was handed — and only then answers.
n=$(( $(wc -l < "$CREATED") + 101 ))
echo "$n" >> "$CREATED"
[ -n "${CC_PANE_CMD:-}" ] && printf '%s' "$CC_PANE_CMD" > "$CREATED.$n"
case "${FAKE_MODE:-ok}" in
  slow)   sleep "${FAKE_SLEEP:-2}"; echo "Created new pane: $n" ;;
  warn)   echo "it2-kitty: could not mark pane $n armed — its command will be typed" >&2
          echo "Created new pane: $n" ;;
  garble) echo "it2-kitty: kitty launch failed (rc=124): " >&2; exit 1 ;;
  *)      echo "Created new pane: $n" ;;
esac
SH
  chmod +x "$FAKE_IT2"
  # Assignments marked SC2034 below are READ by the eval'd real functions (it2_split, spawn), which
  # the linter cannot see through the eval.
  # shellcheck disable=SC2034
  REAL_IT2="$FAKE_IT2"

  # `kitty @ ls`: the anchor window, every pane the fake it2 created (with its launch env, as kitty
  # reports it), and optionally a FOREIGN pane running some other fire's command.
  FAKE_KITTY="$BATS_TEST_TMPDIR/kitty"
  cat > "$FAKE_KITTY" <<'SH'
#!/usr/bin/env bash
for a in "$@"; do
  [ "$a" = ls ] || continue
  exec /usr/bin/python3 - "$CREATED" "${ANCHOR_WIN:-7}" "${FOREIGN_CMD:-}" <<'PY'
import json, os, sys
created, anchor, foreign = sys.argv[1], sys.argv[2], sys.argv[3]
wins = [] if anchor == "none" else [{"id": int(anchor), "env": {}}]
if foreign:
    wins.append({"id": 55, "env": {"CC_PANE_CMD": foreign}})
for line in open(created).read().split():
    p = created + "." + line
    wins.append({"id": int(line), "env": {"CC_PANE_CMD": open(p).read()} if os.path.exists(p) else {}})
print(json.dumps([{"tabs": [{"windows": wins}]}]))
PY
done
exit 1
SH
  chmod +x "$FAKE_KITTY"

  FRONTMOST_MARK="$BATS_TEST_TMPDIR/frontmost"; rm -f "$FRONTMOST_MARK"
  LAND_MARK="$BATS_TEST_TMPDIR/land";           rm -f "$LAND_MARK"
  spawn_frontmost() { echo win > "$FRONTMOST_MARK"; echo WINPANE; }
  it2_land()        { echo "$1" > "$LAND_MARK"; return 0; }
  as_tab()          { echo NOTFOUND; }
  # shellcheck disable=SC2034
  CMD="claude --fire-marker $BATS_TEST_NUMBER-$$"          # unique per fire, as the real prompt path is
  # shellcheck disable=SC2034
  SURFACE=split-right
}

kitty_on() { export KITTY_WINDOW_ID=7 CC_KITTY_BIN="$FAKE_KITTY" LIVE_ID=7; FIRING_SID=7; }
created() { wc -l < "$CREATED" | tr -d ' '; }

@test "THE INCIDENT: a split slower than one IPC round-trip is not convicted — ONE pane, landed" {
  # HF_TIMEOUT_S is scaled 10 -> 1 and the fake answers in 2s: the split outlives one round-trip, as
  # every refused fire's did. Pre-fix the 1s bound kills it after the pane exists, the retry creates a
  # second, and the fire refuses: created=2, rc 1.
  HF_TIMEOUT_S=1; FAKE_MODE=slow FAKE_SLEEP=2; export FAKE_MODE FAKE_SLEEP
  FIRING_SID=LIVE
  run spawn
  echo "$output"
  [ "$(created)" = 1 ]
  [ "$status" -eq 0 ]
  [ "$(cat "$LAND_MARK")" = 101 ]
}

@test "inner bound <= outer bound: the split's timeout exceeds the kitty bound INSIDE it (measured on the call)" {
  # Records the duration it2_split actually hands timeout(1) (argv: -k 3 <S> cmd...), and compares it to
  # the default bin/it2-kitty bounds its own kitty launch with. Pre-fix: 10 against 15.
  local rec="$BATS_TEST_TMPDIR/bound"
  HF_TIMEOUT_BIN="$BATS_TEST_TMPDIR/timeout-rec"
  printf '#!/usr/bin/env bash\necho "$3" > %q\nshift 3\nexec "$@"\n' "$rec" > "$HF_TIMEOUT_BIN"
  chmod +x "$HF_TIMEOUT_BIN"
  run it2_split LIVE vertically
  [ "$status" -eq 0 ]
  local inner
  inner="$(sed -n 's/^TIMEOUT_S="\${IT2_KITTY_TIMEOUT_S:-\([0-9]*\)}"$/\1/p' "$REPO/bin/it2-kitty")"
  [ -n "$inner" ]
  echo "split bound=$(cat "$rec") inner kitty bound=$inner"
  [ "$(cat "$rec")" -gt "$inner" ]
}

@test "a failed split whose pane EXISTS is ADOPTED — never a second session of one brief" {
  kitty_on; HF_ARGV_ACTIVE=1; export FAKE_MODE=garble FOREIGN_CMD="claude --fire-marker someone-else"
  run spawn
  echo "$output"
  [ "$(created)" = 1 ]
  [ "$status" -eq 0 ]
  [ "$(cat "$LAND_MARK")" = 101 ]                         # ours — never the foreign pane 55
  [[ "$output" == *"ADOPTED"* ]] || false
}

@test "a bound EXPIRY with nothing adoptable is not retried, and is not called an anchor loss" {
  # Both bounds scaled to 1s so the pre-fix tree (which ignores HF_SPLIT_TIMEOUT_S) also expires.
  # shellcheck disable=SC2034
  HF_TIMEOUT_S=1 HF_SPLIT_TIMEOUT_S=1
  export FAKE_MODE=slow FAKE_SLEEP=3
  FIRING_SID=LIVE
  run spawn
  echo "$output"
  [ "$(created)" = 1 ]
  [ "$status" -ne 0 ]
  [[ "$output" == *"NOT retrying"* ]] || false
  [[ "$output" == *"NOT firing into a random window"* ]] || false
  [[ "$output" != *"anchor gone"* ]] || false
  [ ! -f "$FRONTMOST_MARK" ]
}

@test "a failure on a LIVE anchor names the splitter's reason, not 'anchor gone'" {
  kitty_on; HF_ARGV_ACTIVE=0; export FAKE_MODE=refuse
  run spawn
  echo "$output"
  [ "$(created)" = 0 ]
  [ "$status" -ne 0 ]
  [[ "$output" == *"LIVE pane 7"* ]] || false
  [[ "$output" == *"boom"* ]] || false                    # the splitter's own stderr reaches the log
  [[ "$output" != *"anchor gone"* ]] || false
  [ ! -f "$FRONTMOST_MARK" ]
}

@test "a success line preceded by a warning is a success — not a failure that retries" {
  export FAKE_MODE=warn
  # shellcheck disable=SC2034
  FIRING_SID=LIVE
  run spawn
  echo "$output"
  [ "$(created)" = 1 ]
  [ "$status" -eq 0 ]
  [ "$(cat "$LAND_MARK")" = 101 ]
}

@test "EQUIVALENCE GUARD: a genuinely GONE anchor still refuses as 'anchor gone', creating nothing" {
  # Green in both arms by design: it asserts the fix did not LOSE the true-positive refusal. Its power
  # is shown by a mutant (hf_anchor_live forced to 0), not by a pre/post pair.
  kitty_on; export ANCHOR_WIN=none LIVE_ID=none
  run spawn
  echo "$output"
  [ "$(created)" = 0 ]
  [ "$status" -ne 0 ]
  [[ "$output" == *"anchor gone"* ]] || false
  [ ! -f "$FRONTMOST_MARK" ]
}

@test "EQUIVALENCE GUARD: adoption never takes a pane running ANOTHER fire's command" {
  # Green pre-fix by absence (no adoption existed); its power is the mutant that matches any
  # non-empty CC_PANE_CMD.
  kitty_on
  # shellcheck disable=SC2034
  HF_ARGV_ACTIVE=1
  export FAKE_MODE=refuse FOREIGN_CMD="claude --fire-marker someone-else"
  run spawn
  echo "$output"
  [ "$status" -ne 0 ]
  [ ! -f "$LAND_MARK" ]
  [[ "$output" != *"ADOPTED"* ]] || false
}
