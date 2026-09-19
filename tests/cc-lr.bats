#!/usr/bin/env bats
# bin/cc-find — one live session from a pane id, a sid8, a statusline tuple, a keyword or --limited
# (LIMIT_RECOVER_100P W4). Hermetic: a fixture registry, fixture stores, fixture telemetry, and a
# `ps` stub wherever a case is about what the process table says.
#
# WHY THIS TOOL EXISTS, measured 2026-09-19 (U07 §0, §4): the shipped lookup `cc-sessions` took
# 30.4–41.0 s and printed no session id at all, and the statusline it was being read against did
# not identify a session either — panes 122 and 124 rendered the BYTE-IDENTICAL line. A registry
# join does the same job in 0.18 s. So the two questions this suite pins are (a) does the cheap
# path stay cheap, and (b) does the ambiguous path REFUSE rather than pick, because an ambiguous
# identification that silently picks one is exactly how a wrong pane gets recycled.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  FIND="$REPO/bin/cc-find"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg"; mkdir -p "$CC_REGISTRY_DIR"
  export CC_TELEMETRY_DIR="$BATS_TEST_TMPDIR/tel"; mkdir -p "$CC_TELEMETRY_DIR"
  export LR_STATE_DIR="$BATS_TEST_TMPDIR/state"; mkdir -p "$LR_STATE_DIR"
  SEC="$HOME/.claude-secondary"; TER="$HOME/.claude-tertiary"
  SLUG="-Users-x-claude-infrastructure"
  mkdir -p "$SEC/projects/$SLUG" "$TER/projects/$SLUG"
  export LR_CONFIG_DIRS="$SEC:$TER"
  CWD="$BATS_TEST_TMPDIR/claude-infrastructure"; mkdir -p "$CWD"
  # The canonical rendering the WRITER pins (hooks/session-register.sh:278). Taken live from this
  # process so the LIVE cases carry a start time that genuinely matches, and the STALE case can
  # differ from it by construction rather than by hoping a constant is wrong.
  LSTART="$(TZ=UTC LC_ALL=C ps -o lstart= -p $$ 2>/dev/null | tr -s ' ' | sed 's/^ *//;s/ *$//')"
  A="aaaaaaaa-1111-4000-8000-000000000001"   # pane 117, next2/xhigh, 45%
  B="bbbbbbbb-2222-4000-8000-000000000002"   # pane 122, next3/high,  40%  ┐ byte-identical
  C="cccccccc-3333-4000-8000-000000000003"   # pane 124, next3/high,  40%  ┘ statuslines
  TM="dddddddd-4444-4000-8000-000000000004"  # pane 130, a TEAMMATE
  ST="eeeeeeee-5555-4000-8000-000000000005"  # pane 140, a reused pid
}

reg() { # <pane> <sid> <account> [pid] [lstart]
  printf '{"paneUUID":"%s","name":"claude-infrastructure-%s","cwd":"%s","account":"%s","pid":%d,"startedAt":1789838449000,"session_id":"%s","surface":"pane","lstart":"%s"}\n' \
    "$1" "$1" "$CWD" "$3" "${4:-$$}" "$2" "${5:-$LSTART}" > "$CC_REGISTRY_DIR/$1.json"
}
tel_row() { # <sid> <cfg> <effort> <used_pct>
  printf '{"ts":1,"session_id":"%s","cwd":"%s","config_dir":"%s","model":"claude-opus-5","effort":"%s","pane":null,"pid":%d,"window":1000000,"used_pct":%s}\n' \
    "$1" "$CWD" "$2" "$3" "$$" "$4" > "$CC_TELEMETRY_DIR/$1.json"
}
plain_tx() { # <store> <sid> — a transcript whose last assistant word is a normal turn
  local f="$1/projects/$SLUG/$2.jsonl"
  printf '{"type":"user","cwd":"%s","timestamp":"2026-09-19T20:00:00.000Z","message":{"role":"user","content":"refactor the census"}}\n' "$CWD" > "$f"
  printf '{"type":"assistant","timestamp":"2026-09-19T20:30:00.000Z","message":{"role":"assistant","model":"claude-opus-5","content":[{"type":"text","text":"done"}]}}\n' >> "$f"
}
limit_tx() { # <store> <sid> — ...and one whose last assistant word is a usage-limit error
  plain_tx "$1" "$2"
  printf '{"type":"assistant","uuid":"u-%s","timestamp":"2026-09-19T21:00:00.000Z","isApiErrorMessage":true,"message":{"role":"assistant","content":[{"type":"text","text":"You'"'"'ve hit your session limit · resets 7:50pm"}]}}\n' "$2" >> "$1/projects/$SLUG/$2.jsonl"
}
teammate_tx() { # <store> <sid> — agentName in the HEAD is rule 0
  local f="$1/projects/$SLUG/$2.jsonl"
  printf '{"type":"user","agentName":"w4","cwd":"%s","timestamp":"2026-09-19T20:00:00.000Z","message":{"role":"user","content":"brief"}}\n' "$CWD" > "$f"
  printf '{"type":"assistant","timestamp":"2026-09-19T20:30:00.000Z","message":{"role":"assistant","model":"claude-opus-5","content":[{"type":"text","text":"ok"}]}}\n' >> "$f"
}
col() { printf '%s' "$1" | cut -f"$2"; }
# The latency judge lives in a file rather than a nested heredoc so this suite stays readable.
budget_judge() {
  cat > "$BATS_TEST_TMPDIR/budget.py" <<'JUDGE'
import os, sys
d = float(sys.argv[2]) - float(sys.argv[1])
lpc = os.getloadavg()[0] / (os.cpu_count() or 1)
print("cc-find: %.3f s at load/core %.2f" % (d, lpc), file=sys.stderr)
if lpc >= float(os.environ.get("CC_FIND_JUDGE_MAX_LPC", "1.0")):
    print("  (box not quiet — timing printed, not judged; the fork-budget case carries the"
          " load-invariant half of the claim)", file=sys.stderr)
    sys.exit(0)
sys.exit(0 if d <= float(os.environ.get("CC_FIND_BUDGET_S", "0.3")) else 1)
JUDGE
}

# ── the cheap keys: a pane id and a sid8 are unique BY CONSTRUCTION ────────────────────────────
# The pane id IS the registry filename and the sid is the session; U07 §4 measured 0 collisions on
# either across 16 live sessions, against 6 of 16 on cwd basename. Everything else the statusline
# renders is a property of a GROUP or of a MOMENT.
@test "pane id resolves to exactly one row, inside the latency budget" {
  reg 117 "$A" claude-secondary; plain_tx "$SEC" "$A"; tel_row "$A" "$SEC" xhigh 45
  budget_judge
  local t0 t1
  t0=$(python3 -c 'import time;print(time.time())')
  run bash "$FIND" 117
  t1=$(python3 -c 'import time;print(time.time())')
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(printf '%s\n' "$output" | grep -c .)" = 1 ] || { echo "$output"; false; }
  [ "$(col "$output" 1)" = "$A" ]
  [ "$(col "$output" 2)" = "117" ]
  [ "$(col "$output" 3)" = "claude-secondary" ]
  [ "$(col "$output" 4)" = "$SEC" ]
  [ "$(col "$output" 5)" = "$CWD" ]
  [ "$(col "$output" 6)" = "LIVE" ]
  # `cc-sessions` takes 30.4-41.0 s for strictly less information (U07 §6b), so the 0.3 s budget is
  # the whole point of the tool and is asserted here — but ONLY in the band a latency question can
  # be answered in. A wall-clock verdict taken on a saturated box is a fact about the BOX: measured
  # this session, the same lookup ran 0.104-0.119 s direct on the live 37-row store and 0.419 s
  # inside bats while the machine sat at load 35, and 0.873 s in the land gate at 1.98/core — a hair
  # INSIDE a 2.0 band. That 2.0 is the capacity gate's REFUSAL line for net-new work, not a quiet-box
  # line, so the judged band is 1.0/core (CC_FIND_JUDGE_MAX_LPC): above it the timing is PRINTED and
  # not judged, and the load-invariant half of the claim — the fork budget — is asserted
  # unconditionally in the case below.
  python3 "$BATS_TEST_TMPDIR/budget.py" "$t0" "$t1"
}

# THE LOAD-INVARIANT HALF OF THE BUDGET. What made the shipped lookup slow was never the box: it
# was a fork per registry row. `cc-find <sid8>` did exactly that in its first draft — 37 rows, 37
# jq processes, 0.399 s measured on the live store against a 0.3 s budget. One pass over the same
# files is 0.09 s. Assert the PROCESS COUNT, which no amount of contention can move, and the wall
# clock follows on any box.
forkbin() { # <tool> — a PATH shim that counts calls and execs the real one
  local real; real="$(command -v "$1")"
  mkdir -p "$BATS_TEST_TMPDIR/forkbin"
  printf '#!/bin/bash\necho %s >> "%s"\nexec %s "$@"\n' "$1" "$BATS_TEST_TMPDIR/forks.log" "$real" \
    > "$BATS_TEST_TMPDIR/forkbin/$1"
  chmod +x "$BATS_TEST_TMPDIR/forkbin/$1"
}
@test "the cheap paths cost a CONSTANT number of forks, not one per registry row" {
  local i sid
  for i in 1 2 3 4 5 6 7 8; do
    sid="0000000$i-0000-4000-8000-00000000000$i"
    reg "20$i" "$sid" claude-secondary; plain_tx "$SEC" "$sid"; tel_row "$sid" "$SEC" high 40
  done
  reg 117 "$A" claude-secondary; plain_tx "$SEC" "$A"; tel_row "$A" "$SEC" xhigh 45
  forkbin jq; forkbin ps
  : > "$BATS_TEST_TMPDIR/forks.log"
  PATH="$BATS_TEST_TMPDIR/forkbin:$PATH" run bash "$FIND" 117
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(grep -c '^jq$' "$BATS_TEST_TMPDIR/forks.log")" -le 2 ] || { cat "$BATS_TEST_TMPDIR/forks.log"; false; }
  [ "$(grep -c '^ps$' "$BATS_TEST_TMPDIR/forks.log")" -le 2 ] || { cat "$BATS_TEST_TMPDIR/forks.log"; false; }
  # the sid8 path walks the WHOLE registry and must still be constant — this is the one the first
  # draft failed, with nine rows costing nine jq calls.
  : > "$BATS_TEST_TMPDIR/forks.log"
  PATH="$BATS_TEST_TMPDIR/forkbin:$PATH" run bash "$FIND" "${A:0:8}"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(grep -c '^jq$' "$BATS_TEST_TMPDIR/forks.log")" -le 3 ] || { cat "$BATS_TEST_TMPDIR/forks.log"; false; }
}

@test "a sid8 resolves to exactly one row — the key the statusline now renders" {
  reg 117 "$A" claude-secondary; plain_tx "$SEC" "$A"; tel_row "$A" "$SEC" xhigh 45
  reg 122 "$B" claude-tertiary;  plain_tx "$TER" "$B"; tel_row "$B" "$TER" high 40
  run bash "$FIND" "${B:0:8}"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(printf '%s\n' "$output" | grep -c .)" = 1 ] || { echo "$output"; false; }
  [ "$(col "$output" 1)" = "$B" ]
  [ "$(col "$output" 2)" = "122" ]
}

@test "the mark the statusline renders is accepted as part of the pane id" {
  reg 117 "$A" claude-secondary; plain_tx "$SEC" "$A"; tel_row "$A" "$SEC" xhigh 45
  run bash "$FIND" '#117'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(col "$output" 2)" = "117" ]
  run bash "$FIND" '#117'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(col "$output" 2)" = "117" ]
}

# ── the tuple: it must REFUSE, because the fields are not a key ────────────────────────────────
# Panes 122 and 124 rendered the byte-identical statusline on 2026-09-19 and were both at 40%.
# A resolver that picks one of those is how a wrong pane gets recycled; the refusal IS the feature.
@test "a tuple matching two sessions REFUSES with rc 2 and prints BOTH candidates" {
  reg 122 "$B" claude-tertiary; plain_tx "$TER" "$B"; tel_row "$B" "$TER" high 40
  reg 124 "$C" claude-tertiary; plain_tx "$TER" "$C"; tel_row "$C" "$TER" high 40
  run bash "$FIND" --tuple '(3) 40% · claude-infrastructure (b80f9408e) · high'
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  [ "$(printf '%s\n' "$output" | grep -c .)" = 2 ] || { echo "$output"; false; }
  [[ "$output" == *"	122	"* ]] || { echo "$output"; false; }
  [[ "$output" == *"	124	"* ]] || { echo "$output"; false; }
}

@test "CONTROL: a tuple only one session can match resolves, and the git sha is never a filter" {
  reg 117 "$A" claude-secondary; plain_tx "$SEC" "$A"; tel_row "$A" "$SEC" xhigh 45
  reg 122 "$B" claude-tertiary;  plain_tx "$TER" "$B"; tel_row "$B" "$TER" high 40
  run bash "$FIND" --tuple '(2) 45% · claude-infrastructure (b80f9408e) · xhigh'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(col "$output" 2)" = "117" ]
  # the sha MOVES under a live session (b80f9408e → 0194d9cb1 inside one 25-minute window,
  # U07 §2a), so a screenshot's sha ages out of agreement with the pane it was taken from. A
  # resolver that filtered on it would refuse the correct answer.
  run bash "$FIND" --tuple '(2) 45% · claude-infrastructure (deadbeef0) · xhigh'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(col "$output" 2)" = "117" ]
}

@test "a tuple carrying the identity segment short-circuits every rank and filter" {
  reg 122 "$B" claude-tertiary; plain_tx "$TER" "$B"; tel_row "$B" "$TER" high 40
  reg 124 "$C" claude-tertiary; plain_tx "$TER" "$C"; tel_row "$C" "$TER" high 40
  # the SAME ambiguous tuple as the refusal above, plus the pane the statusline now renders
  run bash "$FIND" --tuple '(3) #124 cccccccc 40% · claude-infrastructure (b80f9408e) · high'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(col "$output" 2)" = "124" ]
}

# ── liveness is (pid, lstart), never kill -0 and never telemetry age ───────────────────────────
# A registry row is retained after its session dies, so the recycled-pid window is real: `kill -0`
# answers "is SOME process holding this pid", never "is THAT process still this session". Telemetry
# age cannot stand in either — pane 126 was 52.5 minutes stale WHILE ALIVE (U07 §4).
@test "a row whose pid was REUSED — same pid, different start time — is STALE, not LIVE" {
  reg 140 "$ST" claude-secondary "$$" "Thu Jan  1 00:00:01 2026"
  plain_tx "$SEC" "$ST"; tel_row "$ST" "$SEC" high 10
  run bash "$FIND" 140
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(col "$output" 6)" = "STALE" ] || { echo "$output"; false; }
}

@test "CONTROL: the same pid with the recorded start time is LIVE, and an absent pid is DEAD" {
  reg 140 "$ST" claude-secondary "$$"; plain_tx "$SEC" "$ST"; tel_row "$ST" "$SEC" high 10
  run bash "$FIND" 140
  [ "$(col "$output" 6)" = "LIVE" ] || { echo "$output"; false; }
  # a pid the process table does not hold at all is a different verdict from a reused one
  reg 141 "$ST" claude-secondary 999999 "$LSTART"
  run bash "$FIND" 141
  [ "$(col "$output" 6)" = "DEAD" ] || { echo "$output"; false; }
}

# ── rule 0: a teammate is lead-owned and is never a recovery target ────────────────────────────
@test "a transcript whose HEAD carries agentName is TEAMMATE, and never a tuple candidate" {
  reg 130 "$TM" claude-tertiary; teammate_tx "$TER" "$TM"; tel_row "$TM" "$TER" high 40
  run bash "$FIND" 130
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(col "$output" 7)" = "TEAMMATE" ] || { echo "$output"; false; }
  # ...and it is not offered to a ranked lookup at all: the tuple below matches it on every field
  # it filters on, and must come back empty rather than naming a session the lead owns.
  run bash "$FIND" --tuple '(3) 40% · claude-infrastructure (b80f9408e) · high'
  [ "$status" -eq 1 ] || { echo "$output"; false; }
}

# ── --limited: the population a recovery actually acts on ──────────────────────────────────────
@test "--limited lists only rows whose LAST assistant record is a usage-limit error" {
  reg 117 "$A" claude-secondary; limit_tx "$SEC" "$A"; tel_row "$A" "$SEC" xhigh 45
  reg 122 "$B" claude-tertiary;  plain_tx "$TER" "$B"; tel_row "$B" "$TER" high 40
  reg 130 "$TM" claude-tertiary; teammate_tx "$TER" "$TM"; tel_row "$TM" "$TER" high 40
  run bash "$FIND" --limited
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(printf '%s\n' "$output" | grep -c .)" = 1 ] || { echo "$output"; false; }
  [ "$(col "$output" 1)" = "$A" ]
  [ "$(col "$output" 7)" = "LIMITED" ]
}

@test "--limited CONTROL: a session that took a real turn AFTER its limit error is not listed" {
  reg 117 "$A" claude-secondary; limit_tx "$SEC" "$A"; tel_row "$A" "$SEC" xhigh 45
  printf '{"type":"assistant","timestamp":"2026-09-19T21:30:00.000Z","message":{"role":"assistant","model":"claude-opus-5","content":[{"type":"text","text":"back"}]}}\n' \
    >> "$SEC/projects/$SLUG/$A.jsonl"
  run bash "$FIND" --limited
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [ -z "$output" ] || { echo "$output"; false; }
}

# ── --kw: the bounded fallback for when the screenshot carries no key at all ───────────────────
@test "--kw matches the cwd and the transcript head, and is bounded" {
  reg 117 "$A" claude-secondary; plain_tx "$SEC" "$A"; tel_row "$A" "$SEC" xhigh 45
  reg 122 "$B" claude-tertiary;  plain_tx "$TER" "$B"; tel_row "$B" "$TER" high 40
  printf '{"type":"user","cwd":"%s","timestamp":"2026-09-19T20:00:00.000Z","message":{"role":"user","content":"rename the bottle menu importer"}}\n' "$CWD" \
    > "$TER/projects/$SLUG/$B.jsonl"
  run bash "$FIND" --kw 'bottle menu'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(col "$output" 2)" = "122" ] || { echo "$output"; false; }
}

@test "no match at all is rc 1 and prints nothing — an empty answer is never a row" {
  reg 117 "$A" claude-secondary; plain_tx "$SEC" "$A"; tel_row "$A" "$SEC" xhigh 45
  run bash "$FIND" 999
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  run bash "$FIND" 0f0f0f0f
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "iron rule: the resolver only READS — it never types, kills, ships or deploys" {
  # It is reached from a screenshot, i.e. from the one moment an operator is least able to audit
  # what a tool does next. Keep it a pure read.
  ! grep -nE '(^|[^a-zA-Z_-])(kill|pkill|launchctl|git push|osascript)([^a-zA-Z_-]|$)' "$FIND" \
    | grep -v '^[[:space:]]*#' | grep -vE '^[0-9]+:[[:space:]]*#' || false
  ! grep -qE 'send-text|send-key|it2 |ship-land|deploy-live' "$FIND" || false
}
