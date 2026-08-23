#!/usr/bin/env bats
# backlog-telemetry.bats — the close-attribution gap, and the readout that measures it.
#
# SUBJECTS: bin/cc-backlog (the `lane` / `closedBy` stamp on a `done`) and
# scripts/backlog-telemetry.sh (the renderer that counts what carries no lane as `unattributed`).
#
# THE RED-PROOF, two arms, because one is not a proof:
#   · arm 1 (A1/A2) replays the PRE-FIX bin/cc-backlog from a LITERAL sha and shows it writes no
#     lane at all. A literal sha, never `origin/main`: that ref advances past the fix the moment it
#     lands, after which the control replays the FIXED artifact and compares the fix to itself. It
#     then either reds permanently or — worse — passes vacuously. That exact error cost a land at
#     rc 6 from scripts/moving-ref-control-lint.sh.
#   · arm 2 (C1) is the control that can actually FAIL: the same fixture through the same renderer,
#     asserting the unattributed count DROPS for a new close while the historical row STAYS
#     unattributed. Run against the pre-fix subject it reports 2 of 2 unattributed and reds. A
#     fixture that is green on both sides asserts nothing.
#
# The MARKER assertion (`! grep -q '_bl_derive_lane'`) is what makes arm 1 honest: it proves the
# replayed artifact really is pre-fix. Derived from the measured diff of the two files, not from
# prose — the obvious spelling is usually named in the post-fix file's own explanatory comment and
# greps 1 on BOTH sides.

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  D="$BATS_TEST_TMPDIR"
  # Hermetic HOME: the subject reads $HOME for the live store and the drain root, and a test that
  # let either resolve to the operator's real one would read — or write — production state.
  export HOME="$D/home"
  mkdir -p "$HOME"
  export CC_BACKLOG_FILE="$D/backlog.jsonl"
  BL="$REPO/bin/cc-backlog"
  TELEM="$REPO/scripts/backlog-telemetry.sh"

  # PRE-FIX SUBJECT — a LITERAL sha (the fix commit's parent), never a moving ref.
  PRE="$D/cc-backlog-prefix"
  git -C "$REPO" show e6e5a4355:bin/cc-backlog > "$PRE" 2>/dev/null || true
  chmod +x "$PRE" 2>/dev/null || true
}

# The store the whole suite reasons about: ONE historical close carrying no lane (exactly the shape
# of all 2,296 rows in the live store at build time) and TWO open rows to close during the test.
seed_store() {
  printf '%s\n' \
    '{"id":"aaaaaaaaaaaa","ts":"2026-08-01T00:00:00Z","event":"add","title":"historical","project":"p"}' \
    '{"id":"aaaaaaaaaaaa","ts":"2026-08-01T01:00:00Z","event":"done","evidence":"legacy close, no lane"}' \
    '{"id":"bbbbbbbbbbbb","ts":"2026-08-02T00:00:00Z","event":"add","title":"fresh one","project":"p"}' \
    '{"id":"cccccccccccc","ts":"2026-08-02T00:00:00Z","event":"add","title":"fresh two","project":"p"}' \
    > "$CC_BACKLOG_FILE"
}

# A synthetic process ancestry: <pid> → "<ppid> <command>". Feeds CC_BACKLOG_PSFIX_DIR so a lane
# branch is chosen by the fixture rather than by wherever the suite happens to be running.
ancestry() { # <dir> <pid> <ppid> <command...>
  local dir="$1" pid="$2" ppid="$3"; shift 3
  mkdir -p "$dir"
  printf '%s %s\n' "$ppid" "$*" > "$dir/$pid"
}

lane_of() { # <id> → the lane recorded on that id's LAST done record ("" when none)
  jq -r --arg i "$1" 'select(.id == $i and .event == "done") | .lane // ""' "$CC_BACKLOG_FILE" | tail -1
}

# ── ARM 1 — the pre-fix subject, replayed from a literal sha ─────────────────────────────────────

@test "A1 RED-PROOF: the PINNED PRE-FIX cc-backlog stamps NO lane on a done" {
  [ -s "$PRE" ] || skip "pre-fix commit e6e5a4355 unavailable (shallow clone?)"
  # The replay must actually BE pre-fix, or this arm passes for the wrong reason.
  ! grep -q '_bl_derive_lane' "$PRE" || false
  seed_store
  CC_BACKLOG_LANE=cloud bash "$PRE" "done" bbbbbbbbbbbb --evidence "closed by the pre-fix subject" >/dev/null 2>&1 || true
  run lane_of bbbbbbbbbbbb
  [ "$status" -eq 0 ]
  # The defect, pinned as a VALUE and not merely as the absence of a new identifier: the pre-fix
  # subject was TOLD the lane and still recorded nothing, so the close is unattributable.
  [ "$output" = "" ]
}

@test "A2 the FIXED cc-backlog stamps the declared lane on the same fixture" {
  seed_store
  CC_BACKLOG_LANE=cloud bash "$BL" "done" bbbbbbbbbbbb --evidence "closed by the fixed subject" >/dev/null
  run lane_of bbbbbbbbbbbb
  [ "$status" -eq 0 ]
  [ "$output" = "cloud" ]
}

@test "A3 the historical lane-less done is NEVER retroactively given a lane" {
  seed_store
  CC_BACKLOG_LANE=cloud bash "$BL" "done" bbbbbbbbbbbb --evidence "a later close" >/dev/null
  run lane_of aaaaaaaaaaaa
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

# ── ARM 2 — the control that can FAIL: the renderer's unattributed count ─────────────────────────

@test "C1 CONTROL: unattributed DROPS for a new close while the historical row stays unattributed" {
  seed_store
  # Two closes, both attributed; one historical close that is not. The renderer must report exactly
  # that split. Against the pre-fix subject all three read unattributed and this case reds.
  CC_BACKLOG_LANE=cloud       bash "$BL" "done" bbbbbbbbbbbb --evidence "cloud lane close"  >/dev/null
  CC_BACKLOG_LANE=local-drain bash "$BL" "done" cccccccccccc --evidence "local lane close"  >/dev/null

  run bash "$TELEM" --json
  [ "$status" -eq 0 ]
  local model="$output"
  [ "$(printf '%s' "$model" | jq -r '.closes.total')" = "3" ]
  [ "$(printf '%s' "$model" | jq -r '.closes.attributed')" = "2" ]
  [ "$(printf '%s' "$model" | jq -r '.closes.unattributed')" = "1" ]
  [ "$(printf '%s' "$model" | jq -r '[.lanes[] | select(.lane == "cloud")       | .closes] | first')" = "1" ]
  [ "$(printf '%s' "$model" | jq -r '[.lanes[] | select(.lane == "local-drain") | .closes] | first')" = "1" ]
}

@test "C2 RED-PROOF of C1: the same fixture closed by the PRE-FIX subject reports 3 of 3 unattributed" {
  [ -s "$PRE" ] || skip "pre-fix commit e6e5a4355 unavailable (shallow clone?)"
  ! grep -q '_bl_derive_lane' "$PRE" || false
  seed_store
  CC_BACKLOG_LANE=cloud       bash "$PRE" "done" bbbbbbbbbbbb --evidence "cloud lane close" >/dev/null 2>&1 || true
  CC_BACKLOG_LANE=local-drain bash "$PRE" "done" cccccccccccc --evidence "local lane close" >/dev/null 2>&1 || true

  run bash "$TELEM" --json
  [ "$status" -eq 0 ]
  local model="$output"
  [ "$(printf '%s' "$model" | jq -r '.closes.total')" = "3" ]
  # This is the number C1 asserts is 2. Pre-fix it is 0, which is what makes C1 a control and not
  # an assertion nobody has watched fail.
  [ "$(printf '%s' "$model" | jq -r '.closes.attributed')" = "0" ]
  [ "$(printf '%s' "$model" | jq -r '.closes.unattributed')" = "3" ]
}

# ── the derivation itself: every lane branch, chosen by fixture rather than by ambient ancestry ──

@test "D1 an ancestor running cloud-return.sh derives lane cloud" {
  seed_store
  ancestry "$D/ps1" 100 200 /bin/bash "$HOME/.claude/bin/cc-backlog" "done" bbbbbbbbbbbb
  ancestry "$D/ps1" 200 1   /bin/bash "$HOME/.claude/scripts/cloud-return.sh" --sweep
  CC_BACKLOG_PSFIX_DIR="$D/ps1" CC_BACKLOG_PS_START_PID=100 \
    bash "$BL" "done" bbbbbbbbbbbb --evidence "closed on the cloud return path" >/dev/null
  run lane_of bbbbbbbbbbbb
  [ "$output" = "cloud" ]
}

@test "D2 an ancestor running autonomy-sweep.sh derives lane sweep" {
  seed_store
  ancestry "$D/ps2" 100 200 /bin/bash "$HOME/.claude/bin/cc-backlog" "done" bbbbbbbbbbbb
  ancestry "$D/ps2" 200 1   /bin/bash "$HOME/.claude/scripts/autonomy-sweep.sh"
  CC_BACKLOG_PSFIX_DIR="$D/ps2" CC_BACKLOG_PS_START_PID=100 \
    bash "$BL" "done" bbbbbbbbbbbb --evidence "closed on the sweep path" >/dev/null
  run lane_of bbbbbbbbbbbb
  [ "$output" = "sweep" ]
}

@test "D3 a claude ancestor outside the drain root derives lane session" {
  seed_store
  ancestry "$D/ps3" 100 200 /bin/bash "$HOME/.claude/bin/cc-backlog" "done" bbbbbbbbbbbb
  ancestry "$D/ps3" 200 1   "$HOME/.claude-220/node_modules/.bin/claude" --permission-mode auto
  CC_BACKLOG_PSFIX_DIR="$D/ps3" CC_BACKLOG_PS_START_PID=100 CC_BACKLOG_DRAIN_ROOT="$D/nowhere" \
    bash "$BL" "done" bbbbbbbbbbbb --evidence "closed by an ordinary session" >/dev/null
  run lane_of bbbbbbbbbbbb
  [ "$output" = "session" ]
}

@test "D4 the SAME claude ancestor, cwd under the drain root, derives lane local-drain" {
  seed_store
  ancestry "$D/ps4" 100 200 /bin/bash "$HOME/.claude/bin/cc-backlog" "done" bbbbbbbbbbbb
  ancestry "$D/ps4" 200 1   "$HOME/.claude-220/node_modules/.bin/claude" --permission-mode auto
  mkdir -p "$D/drainroot/recycle-11"
  cd "$D/drainroot/recycle-11"
  CC_BACKLOG_PSFIX_DIR="$D/ps4" CC_BACKLOG_PS_START_PID=100 CC_BACKLOG_DRAIN_ROOT="$D/drainroot" \
    bash "$BL" "done" bbbbbbbbbbbb --evidence "closed by the local 24/7 drain" >/dev/null
  run lane_of bbbbbbbbbbbb
  [ "$output" = "local-drain" ]
}

@test "D5 a harness NAMED only in an ancestor's prose does NOT capture the lane" {
  # The trap this derivation is built around. A Claude Code session carries its whole brief in argv,
  # so the word `cloud-return.sh` appears in the command line of an ordinary interactive session
  # whenever the brief happens to discuss it — measured on this box. Anchoring on argv POSITION is
  # what keeps a MENTION from reading as a verdict; a substring test attributes this close to cloud.
  seed_store
  ancestry "$D/ps5" 100 200 /bin/bash "$HOME/.claude/bin/cc-backlog" "done" bbbbbbbbbbbb
  ancestry "$D/ps5" 200 1   "$HOME/.claude-220/node_modules/.bin/claude" --permission-mode auto \
    "your brief: fix scripts/cloud-return.sh and scripts/autonomy-sweep.sh in the cloud lane"
  CC_BACKLOG_PSFIX_DIR="$D/ps5" CC_BACKLOG_PS_START_PID=100 CC_BACKLOG_DRAIN_ROOT="$D/nowhere" \
    bash "$BL" "done" bbbbbbbbbbbb --evidence "an ordinary session that merely mentions the harnesses" >/dev/null
  run lane_of bbbbbbbbbbbb
  [ "$output" = "session" ]
}

@test "D6 an unresolvable ancestry writes NO lane rather than guessing one" {
  seed_store
  ancestry "$D/ps6" 100 1 /usr/bin/some-unknown-harness --flag
  CC_BACKLOG_PSFIX_DIR="$D/ps6" CC_BACKLOG_PS_START_PID=100 \
    bash "$BL" "done" bbbbbbbbbbbb --evidence "closed by something nothing recognises" >/dev/null
  run lane_of bbbbbbbbbbbb
  [ "$output" = "" ]
}

@test "D7 an out-of-set CC_BACKLOG_LANE is refused and warned about, never minted" {
  seed_store
  ancestry "$D/ps7" 100 1 /usr/bin/some-unknown-harness --flag
  # The warning is on STDERR by contract (it is a diagnostic, not the verb's output), so it is
  # captured to a file rather than read out of $output — `run` does not merge the two here.
  env CC_BACKLOG_LANE=clod CC_BACKLOG_PSFIX_DIR="$D/ps7" CC_BACKLOG_PS_START_PID=100 \
    bash "$BL" "done" bbbbbbbbbbbb --evidence "a typo in the declared lane" >/dev/null 2>"$D/d7.err"
  run cat "$D/d7.err"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ignoring CC_BACKLOG_LANE=clod"* ]] || false
  run lane_of bbbbbbbbbbbb
  [ "$output" = "" ]
}

# ── the renderer's own contracts ─────────────────────────────────────────────────────────────────

@test "E1 the daily series folds the SIX state verbs and treats annotations as non-state" {
  # `venue` and `link` must not win as last-event: a fold that lets them read open=86 where the
  # truth is 260. `claim` is CLAIMED and is NOT open.
  printf '%s\n' \
    '{"id":"aaaaaaaaaaaa","ts":"2026-08-01T00:00:00Z","event":"add"}' \
    '{"id":"bbbbbbbbbbbb","ts":"2026-08-01T00:00:00Z","event":"add"}' \
    '{"id":"cccccccccccc","ts":"2026-08-01T00:00:00Z","event":"add"}' \
    '{"id":"cccccccccccc","ts":"2026-08-01T02:00:00Z","event":"block","needs":"operator"}' \
    '{"id":"bbbbbbbbbbbb","ts":"2026-08-01T03:00:00Z","event":"claim","by":"w1","venue":"cloud"}' \
    '{"id":"aaaaaaaaaaaa","ts":"2026-08-01T04:00:00Z","event":"venue","venue":"cloud"}' \
    '{"id":"aaaaaaaaaaaa","ts":"2026-08-01T05:00:00Z","event":"link"}' \
    > "$CC_BACKLOG_FILE"
  run bash "$TELEM" --json
  [ "$status" -eq 0 ]
  local m="$output"
  [ "$(printf '%s' "$m" | jq -r '.current.open')"    = "1" ]
  [ "$(printf '%s' "$m" | jq -r '.current.blocked')" = "1" ]
  [ "$(printf '%s' "$m" | jq -r '.current.claimed')" = "1" ]
  [ "$(printf '%s' "$m" | jq -r '.current.live')"    = "2" ]
}

@test "E2 a lane that has closed NOTHING renders a NAMED verdict, never a silent zero" {
  seed_store
  CC_BACKLOG_LANE=cloud bash "$BL" "done" bbbbbbbbbbbb --evidence "only the cloud lane produced" >/dev/null
  run bash "$TELEM"
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=lane-silent"* ]] || false
  [[ "$output" == *"lane=local-drain"* ]] || false
  [[ "$output" == *"unattributed"* ]] || false
}

@test "E3 an absent store is an ABSENT INSTRUMENT, refused — never rendered as an empty backlog" {
  export CC_BACKLOG_FILE="$D/there-is-no-store-here.jsonl"
  run bash "$TELEM"
  [ "$status" -eq 2 ]
  [[ "$output" == *"ABSENT INSTRUMENT"* ]] || false
}

@test "E4 a stalled lane past its cadence renders verdict=lane-stalled" {
  # Seeded relative to now, never as an absolute literal: a pinned date becomes the past and the
  # case silently changes meaning. A negative offset is always in the past by construction.
  local old
  old="$(TZ=UTC date -u -v-400H +%Y-%m-%dT%H:%M:%SZ)"
  printf '%s\n' \
    '{"id":"aaaaaaaaaaaa","ts":"'"$old"'","event":"add"}' \
    '{"id":"aaaaaaaaaaaa","ts":"'"$old"'","event":"done","lane":"cloud","evidence":"long ago"}' \
    > "$CC_BACKLOG_FILE"
  run bash "$TELEM"
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=lane-stalled"* ]] || false
  [[ "$output" == *"lane=cloud"* ]] || false
}
