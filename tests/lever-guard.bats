#!/usr/bin/env bats
# lever-guard.bats — the usage levers' auto-rollback and its jobs (docs/plans/USAGE_LEVERS.md § W7+ §3
# row "Auto-rollback", §5.1, §6; wave S6): bin/cc-lever-guard, cc-lever's guard_trip writer,
# `cc-lever-score job`, launchd/staged/com.claude.lever-{guard,score}.plist, migrations 0079/0080 and
# the lever retention pass in scripts/rotate-autonomy-logs.sh.
#
# Contracts held here, each at the CLI / file boundary over a scratch HOME and lever store:
#   · a guard BREACH latches a trip and pages at ANY stage; at S0 nothing is demoted; a live lever
#     drops to pct 0 / mode shadow with its stage label kept; a held or acked trip is not re-minted
#   · a live lever blind for two consecutive ticks (an evaluation timeout, then a missing ledger)
#     trips as blind; one tick does not; a pct-0 lever is never blind-tripped
#   · a REVERT score row since the stage began demotes a live lever; one from before it does not
#   · the guard never raises: OK ticks over a demoted lever leave flags.json byte-identical
#   · a tick opens no transcript (FIFOs in every root would block it) and ends well inside 60 s
#   · a trip that cannot be written withholds the heartbeat and exits 1; otherwise the heartbeat lands
#   · both plists exec /usr/bin/python3 -I under bash; the guard plist's own command runs a tick under
#     /bin/bash; the score job's self-bound fires as exit 124
#   · 0079 and 0080 refuse without --confirm and touch nothing; 0080 appends exactly its 12 rules,
#     once, verified by content, and c10-batch --rollback restores the file
#   · lever logs rotate at their gate, rotations younger than 35 d are kept and still read by the
#     scorer, older ones and stale per-session state are pruned; the ledger writer drops aged rows
# RED-proof: (a) file-absence: before S6 bin/cc-lever-guard, `cc-lever trip`, `cc-lever-score job`,
# both plists and both migrations did not exist, so every test here failed. (b) mutants on a scratch
# copy, 2026-10-25: read_jsonl reading the live file only (its c0f0288ea shape) reds test 11;
# BLIND_TICKS = 1 reds 3, 4 and 6; a guard_trip that skips the latch when nothing is demoted reds 1;
# a guard_trip that sets pct 10 / live instead of pct 0 reds 1-4; the evaluation without its SIGALRM
# hangs test 3 on the FIFO ledger, which is the unbounded tick this suite exists to forbid.

load helpers/cc-stub

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd -P)"
  PY=/usr/bin/python3
  GUARD="$REPO/bin/cc-lever-guard"; LEVER="$REPO/bin/cc-lever"; SCORE="$REPO/bin/cc-lever-score"
  export HOME="$BATS_TEST_TMPDIR/home"
  export CC_LEVER_STATE_DIR="$BATS_TEST_TMPDIR/st" CC_LEVER_LOG_DIR="$BATS_TEST_TMPDIR/log" \
         CC_LEVER_PAGES_DIR="$BATS_TEST_TMPDIR/pages" CC_LAND_LOG="$BATS_TEST_TMPDIR/land.jsonl" \
         CC_TOKEN_LEDGER_WORKERS=1
  unset CC_LEVER_ALL CC_LEVER_D1 CC_LEVER_D2 CC_LEVER_D3 CC_LEVER_D4 CC_LEVER_EXCLUDE CC_LEVER_DEADMAN_S \
        CC_NOW CC_LEVER_GUARD_EVAL_S CC_LEVER_SCORE_BUDGET_S CC_LEVER_FLAGS CC_LEVER_HEARTBEAT
  local d
  for d in .claude .claude-secondary .claude-tertiary .claude-quaternary; do mkdir -p "$HOME/$d/projects/p"; done
  mkdir -p "$CC_LEVER_STATE_DIR" "$CC_LEVER_LOG_DIR"
  F="$CC_LEVER_STATE_DIR/flags.json"; HB="$CC_LEVER_STATE_DIR/guard.heartbeat"
  LEDGER="$CC_LEVER_LOG_DIR/lever-ledger.jsonl"; GLOG="$CC_LEVER_LOG_DIR/lever-guard.jsonl"
}

# flags <jq object merged into D1> [<jq object merged into D2>] — a four-lever flag file
flags() {
  jq -n --argjson a "$1" --argjson b "${2:-{\}}" '
    def base($s): {salt:$s, split_salt:("x"+$s), stage:"S0", pct:0, holdback:0, mode:"shadow", params_id:"p0",
                   candidate:null, trip:null, stage_started_at:"2026-10-01T00:00:00Z"};
    {v:1, rev:3, levers:{D1:(base("s1")+$a), D2:(base("s2")+$b), D3:base("s3"), D4:base("s4")}}' > "$F"
}

# ledger <n treated D1 sessions with a context-wall death> — a fresh ledger that breaches T3
ledger() {
  local now i; now="$(date -u +%Y-%m-%dT%H:%M:%S)"; : > "$LEDGER"
  for ((i = 0; i < $1; i++)); do
    printf '{"kind":"ledger","sid":"t%d","acct":".claude","arms":{"D1":{"arm":"treat"}},"last_ts":"%s","ptl":{"death":true}}\n' "$i" "$now" >> "$LEDGER"
  done
}

tick() { "$PY" -I "$GUARD" tick --json; }
lever() { jq -c --arg l "$1" '.levers[$l] | {stage, pct, mode, trip: (.trip.id // null), acked: (.trip.acked_at // null)}' "$F"; }

@test "a breach at S0 latches a trip and pages with nothing to demote; the heartbeat lands" {
  flags '{}'; ledger 3
  run tick
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(jq -r '.levers.D1.verdict' <<<"$output")" = BREACH ]
  [ "$(jq -c '.trips | map([.lever, .cause, .latched, .demoted])' <<<"$output")" = '[["D1","breach",true,false]]' ]
  tid="$(jq -r '.levers.D1.trip.id' "$F")"
  [ "$(lever D1)" = "{\"stage\":\"S0\",\"pct\":0,\"mode\":\"shadow\",\"trip\":\"$tid\",\"acked\":null}" ]
  grep -q "cc-lever ack $tid" "$CC_LEVER_PAGES_DIR/lever-D1.page"
  [ "$(jq -r 'select(.verb=="trip") | .by' "$CC_LEVER_LOG_DIR/lever-flags.jsonl")" = "guard:cc-lever-guard" ]
  [ -f "$HB" ]
  [ "$(lever D2)" = '{"stage":"S0","pct":0,"mode":"shadow","trip":null,"acked":null}' ]
}

@test "a breach on a live lever demotes it to pct 0 keeping the label; a held or acked trip is not re-minted" {
  flags '{"stage":"S1","pct":10,"mode":"live"}'; ledger 3
  run tick
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  tid="$(jq -r '.levers.D1.trip.id' "$F")"
  [ "$(lever D1)" = "{\"stage\":\"S1\",\"pct\":0,\"mode\":\"shadow\",\"trip\":\"$tid\",\"acked\":null}" ]
  rm -f "$CC_LEVER_PAGES_DIR/lever-D1.page"
  run tick                                    # still BREACH: the open trip holds, no new page
  [ "$(jq -c '.trips[0] | [.trip_id, .latched, .demoted]' <<<"$output")" = "[\"$tid\",false,false]" ]
  [ ! -e "$CC_LEVER_PAGES_DIR/lever-D1.page" ]
  run "$PY" -I "$LEVER" ack "$tid" --reason "read it" --confirm
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  run tick                                    # acked within this stage occupancy: still not re-minted
  [ "$(jq -r '.levers.D1.trip.id' "$F")" = "$tid" ]
  [ ! -e "$CC_LEVER_PAGES_DIR/lever-D1.page" ]
  [ "$(jq -r '.levers.D1.pct' "$F")" = 0 ]
}

@test "two blind ticks trip a live lever as blind, one does not, and a pct-0 lever is never blind-tripped" {
  flags '{}' '{"stage":"S1","pct":50,"mode":"live"}'
  mkfifo "$LEDGER"                            # tick 1: the evaluation blocks and times out
  run env CC_LEVER_GUARD_EVAL_S=1 "$PY" -I "$GUARD" tick --json
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(jq -c '[.eval, .levers.D2.nodata, .trips]' <<<"$output")" = '["blind",1,[]]' ]
  [ "$(lever D2)" = '{"stage":"S1","pct":50,"mode":"live","trip":null,"acked":null}' ]
  [ -f "$HB" ]                                # alive but blind: the heartbeat still lands
  rm -f "$LEDGER"                             # tick 2: the ledger is absent, verdict NO-DATA
  run tick
  [ "$(jq -c '[.eval, .levers.D2.verdict, .levers.D2.nodata]' <<<"$output")" = '["ok","NO-DATA",2]' ]
  [ "$(jq -c '.trips | map([.lever, .cause])' <<<"$output")" = '[["D2","blind"]]' ]
  [ "$(jq -r '.levers.D2 | [.pct, .mode, .trip.cause] | @tsv' "$F")" = "$(printf '0\tshadow\tblind')" ]
  [ "$(lever D1)" = '{"stage":"S0","pct":0,"mode":"shadow","trip":null,"acked":null}' ]
  [ -f "$CC_LEVER_PAGES_DIR/lever-D2.page" ] && [ ! -e "$CC_LEVER_PAGES_DIR/lever-D1.page" ]
}

@test "a REVERT score row since the stage began demotes a live lever; one from before it does not" {
  flags '{"stage":"S2","pct":50,"mode":"live","stage_started_at":"2026-10-20T00:00:00Z"}'
  ledger 0
  printf '{"kind":"score","lever":"D1","stage":"S2","verdict":"REVERT","ts":"2026-10-19T00:00:00Z"}\n' > "$CC_LEVER_LOG_DIR/lever-score.jsonl"
  run tick
  [ "$(jq -c '.trips' <<<"$output")" = '[]' ]
  [ "$(jq -r '.levers.D1.pct' "$F")" = 50 ]
  printf '{"kind":"score","lever":"D1","stage":"S2","verdict":"REVERT","ts":"2026-10-21T00:00:00Z"}\n' >> "$CC_LEVER_LOG_DIR/lever-score.jsonl"
  run tick
  [ "$(jq -c '.trips | map([.lever, .cause, .demoted])' <<<"$output")" = '[["D1","revert",true]]' ]
  [ "$(lever D1 | jq -c '[.stage, .pct, .mode]')" = '["S2",0,"shadow"]' ]
}

@test "the guard never raises: OK ticks over a demoted, acked lever leave flags.json byte-identical" {
  flags '{"stage":"S1","pct":0,"mode":"shadow","trip":{"id":"trip-D1-x","at":"2026-10-02T00:00:00Z","acked_at":"2026-10-03T00:00:00Z"}}'
  ledger 0
  before="$(shasum -a 256 "$F")"
  run tick; [ "$status" -eq 0 ]
  run tick; [ "$status" -eq 0 ]
  [ "$(jq -c '[.levers[] | .verdict] | unique' <<<"$output")" = '["IDLE"]' ]
  [ "$(shasum -a 256 "$F")" = "$before" ]
  [ ! -e "$CC_LEVER_LOG_DIR/lever-flags.jsonl" ]
}

@test "a tick opens no transcript and finishes well inside its 60 s bound" {
  flags '{"stage":"S1","pct":10,"mode":"live"}'; ledger 0
  local d
  for d in .claude .claude-secondary .claude-tertiary .claude-quaternary; do
    mkfifo "$HOME/$d/projects/root.jsonl" "$HOME/$d/projects/p/session.jsonl"
  done
  run tick
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(jq -r '.eval' <<<"$output")" = ok ]
  jq -e '.elapsed_s < 60' <<<"$output" >/dev/null
  [ "$(jq -r '.kind' "$GLOG" | sort -u)" = tick ]
}

@test "a trip that cannot be written withholds the heartbeat and exits 1" {
  printf '{not json' > "$F"; ledger 3                 # unreadable flags: readers already treat it as pct 0
  run tick
  [ "$status" -eq 1 ]
  [ "$(jq -c '[.heartbeat, .failed]' <<<"$output")" = '[false,["D1"]]' ]
  [ ! -e "$HB" ]
  [ "$(cat "$F")" = '{not json' ]
  [ "$(jq -r 'select(.kind=="trip") | .ok' "$GLOG")" = false ]
}

@test "both plists exec /usr/bin/python3 -I; the guard plist's own command runs a tick under /bin/bash" {
  local p cmd
  for p in lever-guard:600:true lever-score:3600:false; do
    f="$REPO/launchd/staged/com.claude.${p%%:*}.plist"
    run plutil -lint "$f"; [ "$status" -eq 0 ]
    cmd="$(plutil -extract ProgramArguments.2 raw -o - "$f")"
    # shellcheck disable=SC2016  # the literal $HOME is what the plist must carry for bash -c to expand
    [[ "$cmd" == *'exec /usr/bin/python3 -I "$HOME/.claude/bin/cc-'* ]] || false
    [ "$(plutil -extract ProgramArguments.0 raw -o - "$f")" = /bin/bash ]
    p2="${p#*:}"; [ "$(plutil -extract StartInterval raw -o - "$f")" = "${p2%%:*}" ]
    [ "$(plutil -extract RunAtLoad raw -o - "$f")" = "${p##*:}" ]
    [ "$(plutil -extract ProcessType raw -o - "$f")" = Standard ]
  done
  mkdir -p "$HOME/.claude/bin"
  for p in cc-lever-guard cc-lever cc-lever-score; do ln -s "$REPO/bin/$p" "$HOME/.claude/bin/$p"; done
  flags '{}'; ledger 0
  run /bin/bash -c "$(plutil -extract ProgramArguments.2 raw -o - "$REPO/launchd/staged/com.claude.lever-guard.plist")"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == "lever-guard: eval ok "*"heartbeat written"* ]] || false
  [ -f "$HB" ]
}

@test "the hourly score job bounds itself and exits 124 when the scan overruns" {
  mkfifo "$HOME/.claude/projects/p/session.jsonl"   # the transcript scan blocks on it
  run env CC_LEVER_SCORE_BUDGET_S=2 "$PY" -I "$SCORE" job
  [ "$status" -eq 124 ]
  [[ "$output" == *"job: TIMEOUT at score after "*"(bound 2 s)"* ]]
}

@test "0079 and 0080 refuse without --confirm; 0080 appends its 12 ask rules once and rolls back" {
  local stub="$BATS_TEST_TMPDIR/stub"; mkdir -p "$stub" "$HOME/.claude/bin"
  cc_stub "$stub" launchctl "$(printf '#!/bin/bash\necho "launchctl $*" >> "%s/launchctl.calls"\nexit 1' "$BATS_TEST_TMPDIR")"
  cc_stub "$stub" parity '#!/bin/bash
exit 0'
  : > "$HOME/.claude/bin/cc-lever"                    # 0080 only checks that the live CLI exists
  printf '{"permissions":{"ask":["Bash(fly deploy:*)"],"allow":["Bash(ls:*)"]},"env":{"A":"1"}}\n' > "$HOME/.claude/settings.json"
  orig="$(cat "$HOME/.claude/settings.json")"
  for m in 0079-lever-jobs-activate 0080-lever-raise-ask; do
    run env PATH="$stub:$PATH" CC_SETTINGS_PARITY_BIN="$stub/parity" /bin/bash "$REPO/migrations/$m.sh"
    [ "$status" -eq 2 ]
    [[ "$output" == *"refused"* ]] || false
  done
  [ ! -e "$BATS_TEST_TMPDIR/launchctl.calls" ]
  [ "$(cat "$HOME/.claude/settings.json")" = "$orig" ]
  [ ! -e "$HOME/.claude/backups" ]
  run env CC_SETTINGS_PARITY_BIN="$stub/parity" /bin/bash "$REPO/migrations/0080-lever-raise-ask.sh" --confirm settings.json
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(jq '.permissions.ask | length' "$HOME/.claude/settings.json")" = 13 ]
  [ "$(jq -r '.permissions.ask[1:] | map(capture("cc-lever (?<v>[a-z]+):").v) | unique | join(",")' "$HOME/.claude/settings.json")" = ack,candidate,promote,stage ]
  jq -e --arg h "$HOME" '.permissions.ask | index("Bash(\($h)/.claude/bin/cc-lever stage:*)")' "$HOME/.claude/settings.json" >/dev/null
  [ "$(jq -c 'del(.permissions.ask)' "$HOME/.claude/settings.json")" = "$(jq -c 'del(.permissions.ask)' <<<"$orig")" ]
  run env CC_SETTINGS_PARITY_BIN="$stub/parity" /bin/bash "$REPO/migrations/0080-lever-raise-ask.sh" --confirm settings.json
  [[ "$output" == *"already applied"* ]] || false
  [ "$(jq '.permissions.ask | length' "$HOME/.claude/settings.json")" = 13 ]
  run /bin/bash "$REPO/migrations/0080-lever-raise-ask.sh" --verify; [ "$status" -eq 0 ]
  bdir="$(ls -d "$HOME"/.claude/backups/lever-raise-ask-0080-*)"
  run /bin/bash "$REPO/scripts/c10-batch.sh" --rollback "$bdir"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(cat "$HOME/.claude/settings.json")" = "$orig" ]
}

@test "lever logs keep 35 d of rotations the scorer still reads; stale state and ledger rows are pruned" {
  local L="$CC_LEVER_LOG_DIR/lever-arms.jsonl" now; now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '{"kind":"session","ts":"%s","n":0,"pad":"%070d"}\n{"kind":"session","ts":"%s","n":1}\n' "$now" 0 "$now" > "$L"
  old="$(date -u -v-36d +%Y%m%dT%H%M%SZ)"; young="$(date -u -v-34d +%Y%m%dT%H%M%SZ)"
  # not JSON: a read of either would count as bad, so reading only the in-window rotation shows here
  printf 'x\n' | gzip > "$L.$old.gz"; printf 'x\n' | gzip > "$L.$young.gz"
  mkdir -p "$CC_LEVER_STATE_DIR/arms" "$CC_LEVER_STATE_DIR/proc"
  touch "$CC_LEVER_STATE_DIR/arms/fresh"; touch -t "$(date -v-50d +%Y%m%d%H%M)" "$CC_LEVER_STATE_DIR/arms/stale" "$CC_LEVER_STATE_DIR/proc/stale"
  run env ROTATE_TARGETS="$BATS_TEST_TMPDIR/none.log" CC_IDL="$BATS_TEST_TMPDIR/idl.jsonl" ROTATE_SEAL=0 \
      ROTATE_DRAIN_ASSERT=0 ROTATE_LEVER_TARGETS="$L" ROTATE_LEVER_STATE_DIR="$CC_LEVER_STATE_DIR" \
      ROTATE_LEVER_MAX_BYTES=100 ROTATE_LEVER_RETAIN_D=1 /bin/bash "$REPO/scripts/rotate-autonomy-logs.sh"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"lever=rotated:1,pruned:1,state_pruned:2,retain:35d"* ]] || false
  [ ! -e "$L.$old.gz" ] && [ -e "$L.$young.gz" ] && [ ! -s "$L" ] || false
  [ -e "$CC_LEVER_STATE_DIR/arms/fresh" ] && [ ! -e "$CC_LEVER_STATE_DIR/arms/stale" ] || false
  run "$PY" -I -c 'import sys, time; sys.path.insert(0, sys.argv[1]); import lever_events as le
rows, st = le.read_jsonl(sys.argv[2], time.time() - 7 * 86400)
print(sorted(r["n"] for r in rows), st["bad"])' "$REPO/scripts/lib" "$L"
  [ "$output" = "[0, 1] 0" ]
  old_ts="$(date -u -v-50d +%Y-%m-%dT%H:%M:%S)"; new_ts="$(date -u -v-1d +%Y-%m-%dT%H:%M:%S)"
  printf '{"kind":"ledger","sid":"old","last_ts":"%s"}\n{"kind":"ledger","sid":"new","last_ts":"%s"}\n' "$old_ts" "$new_ts" > "$LEDGER"
  run "$PY" -I "$SCORE" ledger --write
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(jq -r .sid "$LEDGER")" = new ]
}
