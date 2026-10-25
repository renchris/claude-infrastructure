#!/usr/bin/env bats
# lever-flags.bats — the usage levers' control plane (docs/plans/USAGE_LEVERS.md § W7+ §3, wave S1):
# hooks/lib/lever_flags.py and its bash 3.2 twin hooks/lib/lever-flags.sh, bin/cc-lever,
# hooks/lever-arm-start.sh and the lineage hand-over in scripts/handoff-fire.sh hf_succ_stage.
#
# Contracts held here, each at its real boundary:
#   · precedence: hook kill > CC_LEVER_EXCLUDE > CC_LEVER_ALL/Dn (lower only) > flags.json > pct 0;
#     unreadable → pct 0 flag_src=unreadable; a stale guard heartbeat on a live lever → deadman
#   · the two libs give the SAME row for every scenario and the same hash for a corpus of units
#   · a fixed salt nests 10% ⊂ 50% ⊂ 100%
#   · cc-lever refuses every raise missing --confirm, a fresh heartbeat, an ADVANCE, or with a trip open
#   · a recycle hands the predecessor's lineage root to the successor (env export and pane file)
# The bash lib runs under /bin/bash (3.2 on macOS), the interpreter every hook's shebang gets.
# shellcheck disable=SC2030,SC2031  # each @test is its own subshell: a per-test export is the point

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd -P)"
  PY=/usr/bin/python3
  LIBPY="$REPO/hooks/lib/lever_flags.py"; LIBSH="$REPO/hooks/lib/lever-flags.sh"; CLI="$REPO/bin/cc-lever"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  # the lineage case extracts handoff-fire.sh functions: pin its machine-load gates and account seams
  export CC_FIRE_CAPACITY_GATE=off CC_FIRE_HEADROOM_GATE=off CC_ADMIT_GATE=off
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/account-sweep.json" CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/claude-accounts" \
         CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-"
  export CC_LEVER_STATE_DIR="$BATS_TEST_TMPDIR/st" CC_LEVER_LOG_DIR="$BATS_TEST_TMPDIR/log"
  mkdir -p "$CC_LEVER_STATE_DIR" "$CC_LEVER_LOG_DIR"
  F="$CC_LEVER_STATE_DIR/flags.json"; HB="$CC_LEVER_STATE_DIR/guard.heartbeat"
  unset CC_LEVER_ALL CC_LEVER_D1 CC_LEVER_D2 CC_LEVER_D3 CC_LEVER_D4 CC_LEVER_EXCLUDE CC_LEVER_LINEAGE \
        CC_IRS CC_WORKFLOW_SHADOW CC_IDLE_KEEPALIVE CC_SUBAGENT_LONG_BASH CC_LEVER_DEADMAN_S \
        CC_HOOK_PARENT_PID KITTY_WINDOW_ID CC_TERM ITERM_SESSION_ID CC_LEVER_ARM_START
}

# flags <D1 entry JSON> — a flag file whose D1 is the given entry (salts fixed so results are stable)
flags() {
  jq -n --argjson e "$1" '{v:1, rev:7, levers:{D1:({salt:"s1", split_salt:"x1", stage:"S0", pct:0, holdback:0,
     mode:"shadow", params_id:"p0", candidate:null, trip:null} + $e)}}' > "$F"
}

# both <lever> <unit> → asserts py and sh rows are equal as JSON values; leaves the row in $ROW
both() {
  local py sh
  py="$("$PY" -I "$LIBPY" arm "$1" "$2")"
  sh="$(/bin/bash -c '. "$1"; lf_arm "$2" "$3" && lf_arm_json' _ "$LIBSH" "$1" "$2")"
  jq -en --argjson a "$py" --argjson b "$sh" '$a == $b' >/dev/null || { printf 'py %s\nsh %s\n' "$py" "$sh"; return 1; }
  ROW="$py"
}
field() { printf '%s' "$ROW" | jq -r ".$1"; }

@test "precedence ladder: each rung gives the same arm, flag_src and pct in both libs" {
  # no file at all: the default is pct 0 and nothing to hash
  both D1 unit-a; [ "$(field flag_src)" = default ]; [ "$(field arm)" = ctrl ]; [ "$(field u)" = null ]
  # S0 shadow (the shipped default): arms computed, every unit control
  flags '{}'; both D1 unit-a; [ "$(field flag_src)" = file ]; [ "$(field arm)" = ctrl ]; [ "$(field u)" != null ]
  # live 100% with a fresh heartbeat: treated
  flags '{"stage":"S3","mode":"live","pct":100}'; touch "$HB"
  both D1 unit-a; [ "$(field arm)" = treat ]; [ "$(field pct_eff)" = 100 ]; [ "$(field flag_rev)" = 7 ]
  # an env var can only lower: off and control win, any other value is ignored
  CC_LEVER_ALL=off both D1 unit-a; [ "$(field flag_src)" = env-off ]; [ "$(field arm)" = ctrl ]
  CC_LEVER_D1=control both D1 unit-a; [ "$(field flag_src)" = env-control ]; [ "$(field pct_eff)" = 0 ]
  CC_LEVER_D1=treat both D1 unit-a; [ "$(field arm)" = treat ]
  CC_LEVER_D2=off both D1 unit-a; [ "$(field arm)" = treat ]          # another lever's clamp is not D1's
  # eval runs are excluded; the hook's own kill beats everything, exclusion included
  CC_LEVER_EXCLUDE=1 both D1 unit-a; [ "$(field arm)" = excluded ]; [ "$(field flag_src)" = excluded ]
  CC_IRS=off CC_LEVER_EXCLUDE=1 both D1 unit-a; [ "$(field arm)" = off ]; [ "$(field flag_src)" = hook-kill ]
  CC_IDLE_KEEPALIVE=off both D1 unit-a; [ "$(field arm)" = treat ]    # D3's kill does not touch D1
  # an un-acked trip latches pct 0; an acked one releases it
  flags '{"stage":"S3","mode":"live","pct":100,"trip":{"id":"t1"}}'
  both D1 unit-a; [ "$(field arm)" = ctrl ]; [ "$(field flag_src)" = file ]; [ "$(field pct_eff)" = 0 ]
  flags '{"stage":"S3","mode":"live","pct":100,"trip":{"id":"t1","acked_at":"2026-10-24T00:00:00Z"}}'
  both D1 unit-a; [ "$(field arm)" = treat ]
  # mode shadow or off at any pct is pct 0
  flags '{"stage":"S2","mode":"shadow","pct":50}'; both D1 unit-a; [ "$(field pct_eff)" = 0 ]
}

@test "dead-man: a live lever whose guard heartbeat is older than 1800 s or absent reads pct 0" {
  flags '{"stage":"S3","mode":"live","pct":100}'
  both D1 unit-a; [ "$(field flag_src)" = deadman ]; [ "$(field arm)" = ctrl ]          # absent
  touch -t 202001010000 "$HB"
  both D1 unit-a; [ "$(field flag_src)" = deadman ]; [ "$(field pct_eff)" = 0 ]        # stale
  CC_LEVER_DEADMAN_S=999999999 both D1 unit-a; [ "$(field arm)" = treat ]              # the bound is the knob
  # at pct 0 the dead-man changes nothing, so the row still says the file decided it
  flags '{}'; both D1 unit-a; [ "$(field flag_src)" = file ]
}

@test "unreadable: garbage, empty, two documents and every malformed lever field read pct 0 in both libs" {
  local bad
  for bad in 'not json' '' '{"v":1}{"v":1}' '[1]' '{"levers":3}'; do
    printf '%s' "$bad" > "$F"; touch "$HB"
    both D1 unit-a || { echo "file: $bad"; false; }
    [ "$(field flag_src)" = unreadable ] || { echo "file: $bad → $(field flag_src)"; false; }
    [ "$(field arm)" = ctrl ]
  done
  for bad in '{"pct":10.5}' '{"pct":true}' '{"pct":101}' '{"holdback":60}' '{"salt":"a b"}' '{"salt":null}' \
             '{"stage":"S"}' '{"stage":null}' '{"mode":"enforce"}' '{"mode":null}' '{"trip":"x"}' \
             '{"candidate":7}' '{"candidate":{"share":"10"}}'; do
    flags "$(jq -c '. + {"mode":"live","pct":100} + $b' --argjson b "$bad" <<< '{}')"
    both D1 unit-a || { echo "entry: $bad"; false; }
    [ "$(field flag_src)" = unreadable ] || { echo "entry: $bad → $(field flag_src)"; false; }
    [ "$(field arm)" = ctrl ]
  done
  # jq cannot tell 10 from 10.0, so neither lib may: both accept an integral float
  flags '{"stage":"S3","mode":"live","pct":100.0}'; both D1 unit-a; [ "$(field arm)" = treat ]
  # a lever missing from a well-formed file is unreadable for that lever only
  both D2 unit-a; [ "$(field flag_src)" = unreadable ]
}

@test "hash parity: py and sh give the same h and u on a 400-unit corpus, and the same arms at 10/50/100% with holdback and candidate" {
  local i
  "$PY" -c '
import sys; sys.path.insert(0, sys.argv[1]); import lever_flags as lf
for i in range(400):
    salt = ("s%d" % (i % 7)) + "-" + "abc"[i % 3]
    unit = ["sess-%d" % i, "%08x-dead-beef:%d" % (i * 2654435761 % 2**32, 1729000000 + i), "agent_%d" % i][i % 3]
    h = lf.h52(salt, unit); print(salt, unit, h, "%.6f" % lf.u6(h))' "$REPO/hooks/lib" > "$BATS_TEST_TMPDIR/corpus"
  [ "$(wc -l < "$BATS_TEST_TMPDIR/corpus")" -eq 400 ]
  /bin/bash -c '. "$1"; while read -r s u h u6; do lf_hash "$s" "$u"; [ "$LF_H" = "$h" ] && [ "$LF_U6" = "$u6" ] \
      || { echo "MISMATCH $s $u py=$h/$u6 sh=$LF_H/$LF_U6"; exit 1; }; done < "$2"' _ "$LIBSH" "$BATS_TEST_TMPDIR/corpus"
  touch "$HB"
  # under salt s1 these units cover every arm: treat at 10% (2, 8), inc and cand at 50% (0, 2), ctrl
  # (1, 9) and the 10% holdback (12, 24)
  local seen=""
  for i in 0 1 2 8 9 12 24; do
    flags '{"stage":"S1","mode":"live","pct":10}';  both D1 "sess-$i"; seen="$seen $(field arm)"
    flags '{"stage":"S2","mode":"live","pct":50,"candidate":{"id":"c1","share":50,"round_salt":"r1"}}'; both D1 "sess-$i"
    seen="$seen $(field variant)"
    flags '{"stage":"S3","mode":"live","pct":100,"holdback":10}'; both D1 "sess-$i"; seen="$seen $(field arm)"
  done
  for i in treat ctrl holdback inc cand; do [[ "$seen" == *" $i"* ]] || { echo "no unit reached $i: $seen"; false; }; done
}

@test "nesting: under one fixed salt the 10% cohort sits inside 50%, which sits inside 100%, at about those shares" {
  run "$PY" -c '
import sys; sys.path.insert(0, sys.argv[1]); import lever_flags as lf
hs = [lf.h52("fixed-salt", "lineage-%d" % i) for i in range(4000)]
t = {p: {i for i, h in enumerate(hs) if lf.below(h, p)} for p in (10, 50, 100)}
assert t[10] <= t[50] <= t[100] and len(t[100]) == 4000, "not nested"
for p in (10, 50):
    share = len(t[p]) / 4000.0
    assert abs(share - p / 100.0) < 0.03, (p, share)
print(len(t[10]), len(t[50]))' "$REPO/hooks/lib"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "cc-lever: first use writes the default — every lever S0, pct 0, mode shadow — and status reads it" {
  run "$PY" "$CLI" status --json
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(jq '[.levers[] | select(.stage == "S0" and .pct == 0 and .mode == "shadow" and .pct_eff == 0)] | length' <<< "$output")" -eq 4 ]
  [ "$(jq '[.levers[] | select((.salt | length) == 16 and (.split_salt | length) == 16 and .salt != .split_salt)] | length' "$F")" -eq 4 ]
  [ "$(jq -r '.verb' "$CC_LEVER_LOG_DIR/lever-flags.jsonl")" = init ]
}

@test "cc-lever: a raise is refused without --confirm, a fresh heartbeat, an ADVANCE, or with a trip open" {
  "$PY" "$CLI" status >/dev/null
  run "$PY" "$CLI" stage D2 S1;                  [ "$status" -eq 3 ]; [[ "$output" == *"needs --confirm"* ]] || false
  run "$PY" "$CLI" stage D2 S1 --confirm D3;     [ "$status" -eq 3 ]; [[ "$output" == *"does not name the target"* ]] || false
  run "$PY" "$CLI" stage D2 S1 --confirm;        [ "$status" -eq 3 ]; [[ "$output" == *"heartbeat absent"* ]] || false
  touch "$HB"
  run "$PY" "$CLI" stage D2 S1 --confirm;        [ "$status" -eq 3 ]; [[ "$output" == *"no lever-score verdict"* ]] || false
  printf '{"ts":"2099-01-01T00:00:00Z","lever":"D2","stage":"S0","verdict":"REVERT"}\n' > "$CC_LEVER_LOG_DIR/lever-score.jsonl"
  run "$PY" "$CLI" stage D2 S1 --confirm;        [ "$status" -eq 3 ]; [[ "$output" == *"is REVERT, not ADVANCE"* ]] || false
  printf '{"ts":"2000-01-01T00:00:00Z","lever":"D2","stage":"S0","verdict":"ADVANCE"}\n' > "$CC_LEVER_LOG_DIR/lever-score.jsonl"
  run "$PY" "$CLI" stage D2 S1 --confirm;        [ "$status" -eq 3 ]; [[ "$output" == *"predates the stage start"* ]] || false
  jq '.levers.D2.trip = {"id":"trip-9"}' "$F" > "$F.n" && mv "$F.n" "$F"
  # an A/A row logged after the ADVANCE carries no verdict and must not shadow it (the raise below)
  printf '{"ts":"2099-01-01T00:00:00Z","lever":"D2","stage":"S0","verdict":"ADVANCE"}\n{"ts":"2099-01-02T00:00:00Z","kind":"aa","lever":"D2","stage":"S0"}\n' > "$CC_LEVER_LOG_DIR/lever-score.jsonl"
  run "$PY" "$CLI" stage D2 S1 --confirm;        [ "$status" -eq 3 ]; [[ "$output" == *"un-acked trip trip-9"* ]] || false
  # nothing above changed the file: D2 is still S0 at pct 0
  [ "$(jq -c '.levers.D2 | [.stage, .pct, .mode]' "$F")" = '["S0",0,"shadow"]' ]
  [ "$(jq -s '[.[] | select(.verb == "raise")] | length' "$CC_LEVER_LOG_DIR/lever-flags.jsonl")" -eq 0 ]
  # the ack releases the latch without raising; the next raise then rotates the salt
  local salt; salt="$(jq -r '.levers.D2.salt' "$F")"
  run "$PY" "$CLI" ack trip-9 --confirm;         [ "$status" -eq 3 ]; [[ "$output" == *"needs --reason"* ]] || false
  run "$PY" "$CLI" ack trip-9 --reason fixed;    [ "$status" -eq 3 ]; [[ "$output" == *"needs --confirm"* ]] || false
  run "$PY" "$CLI" ack trip-9 --reason fixed --confirm
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(jq -c '.levers.D2 | [.stage, .pct]' "$F")" = '["S0",0]' ]
  run "$PY" "$CLI" stage D2 S1 --confirm D2
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(jq -c '.levers.D2 | [.stage, .pct, .mode, .trip]' "$F")" = '["S1",50,"live",null]' ]
  [ "$(jq -r '.levers.D2.salt' "$F")" != "$salt" ]
  [ "$(tail -1 "$CC_LEVER_LOG_DIR/lever-flags.jsonl" | jq -r '[.verb, .verdict_ref, .to.pct] | @tsv')" = "$(printf 'raise\tD2@2099-01-01T00:00:00Z\t50')" ]
}

@test "cc-lever: lowering needs no gate; candidate refuses outside a live S2/S3; an unreadable file is never overwritten" {
  "$PY" "$CLI" status >/dev/null
  jq '.levers.D3 |= (.stage = "S2" | .pct = 50 | .mode = "live")' "$F" > "$F.n" && mv "$F.n" "$F"
  run "$PY" "$CLI" off D3
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(jq -c '.levers.D3 | [.stage, .pct, .mode]' "$F")" = '["S0",0,"off"]' ]
  run "$PY" "$CLI" candidate D1 --id c1 --share 50 --confirm
  [ "$status" -eq 3 ]; [[ "$output" == *"only inside a live S2/S3"* ]] || false
  run "$PY" "$CLI" promote D1 --confirm
  [ "$status" -eq 3 ]; [[ "$output" == *"no candidate"* ]] || false
  printf 'garbage' > "$F"
  run "$PY" "$CLI" off D1
  [ "$status" -eq 3 ]; [[ "$output" == *"unreadable"* ]] || false
  [ "$(cat "$F")" = garbage ]
  run "$PY" "$CLI" history -n 5
  [ "$status" -eq 0 ]; [[ "$output" == *"off "*"D3"* ]] || false
}

@test "lever-arm-start: one kind=session row, no stdout, every arm ctrl at S0; the kill switch writes nothing" {
  "$PY" "$CLI" status >/dev/null
  run /bin/bash "$REPO/hooks/lever-arm-start.sh" <<< '{"session_id":"sid-start-1","source":"startup"}'
  [ "$status" -eq 0 ]; [ -z "$output" ]
  local r="$CC_LEVER_LOG_DIR/lever-arms.jsonl" i
  # the row is written by a background python (the start is never held); give it a loaded box's time
  for i in $(seq 1 180); do [ -s "$r" ] && [ -s "$CC_LEVER_STATE_DIR/arms/sid-start-1" ] && break; sleep 1; done
  [ "$(wc -l < "$r")" -eq 1 ]
  [ "$(wc -c < "$r")" -le 2048 ]
  jq -e '.kind == "session" and .sid == "sid-start-1" and .lineage == "sid-start-1" and .lineage_src == "self"
         and (.ts | test("^[0-9-]+T[0-9:]+Z$")) and .flag_src == "file"
         and ([.arms[] | select(.arm == "ctrl" and .pct_eff == 0 and (.u | type) == "number")] | length) == 2' "$r"
  [ "$(cat "$CC_LEVER_STATE_DIR/arms/sid-start-1")" = "lineage=sid-start-1 src=self" ]
  CC_LEVER_ARM_START=off run /bin/bash "$REPO/hooks/lever-arm-start.sh" <<< '{"session_id":"sid-start-2"}'
  [ "$status" -eq 0 ]; [ ! -e "$CC_LEVER_STATE_DIR/arms/sid-start-2" ]; [ "$(wc -l < "$r")" -eq 1 ]
}

@test "lineage: hf_succ_stage exports the predecessor's root and writes the pane file the successor resolves" {
  local HF="$REPO/scripts/handoff-fire.sh" f
  for f in hf_lever_lineage hf_succ_mode hf_succ_stage; do
    eval "$(sed -n "/^$f() {/,/^}/p" "$HF")"
    declare -F "$f" >/dev/null || { echo "could not extract $f"; false; }
  done
  # the predecessor was itself a successor: its arms cache names root-0
  mkdir -p "$CC_LEVER_STATE_DIR/arms"; printf 'lineage=root-0 src=env\n' > "$CC_LEVER_STATE_DIR/arms/pred-1"
  # the stage itself is refused here (no pane-successor lib), which is the case that most needs the file
  # shellcheck disable=SC2329  # called by the extracted hf_succ_stage
  hf_succ_lib_load() { return 1; }
  unset RESUME_LAUNCHER RCY_TRANSPLANTED_SOURCE RCY_TRANSPLANT_CAUSE RCY_REMOTE
  # shellcheck disable=SC2034  # read by the extracted hf_lever_lineage / hf_succ_stage
  SID=44 rcy_old_sid=pred-1 CC_PANE_SUCCESSOR=on
  run hf_succ_stage /dev/ttys044 "$BATS_TEST_TMPDIR/cmd"
  [ "$status" -eq 1 ]
  jq -e '.pane == "44" and .pred_sid == "pred-1" and .root == "root-0" and .succ_sid == null and (.epoch | type) == "number"' \
    "$CC_LEVER_STATE_DIR/lineage/44.json"
  # the staged .cmd exports it: run the producer far enough to write the .cmd
  hf_succ_lib_load() { return 0; }
  cc_pane_successor_stage() { return 0; }
  emit_recycle_event() { return 0; }
  config_dir_for_launcher() { echo "$BATS_TEST_TMPDIR/cfg"; }
  # shellcheck disable=SC2034  # read by the extracted hf_succ_stage
  LAUNCHER=claude2 WATCHER_PID=$$ CMD="true"
  hf_succ_stage /dev/ttys044 "$BATS_TEST_TMPDIR/cmd" >/dev/null
  grep -qx 'export CC_LEVER_LINEAGE=root-0' "$BATS_TEST_TMPDIR/cmd.succ" || { cat "$BATS_TEST_TMPDIR/cmd.succ"; false; }
  # a typed relaunch has no env: the first new session in pane 44 takes the file, once
  run "$PY" -I "$LIBPY" lineage --sid succ-1 --pane 44
  [ "$output" = "$(printf 'root-0\tlineage-file')" ]
  [ "$(jq -r .succ_sid "$CC_LEVER_STATE_DIR/lineage/44.json")" = succ-1 ]
  run "$PY" -I "$LIBPY" lineage --sid other-2 --pane 44;   [ "$output" = "$(printf 'other-2\tself')" ]
  # sticky: succ-1 keeps its answer, and the bash twin reads it from the cache with builtins
  run "$PY" -I "$LIBPY" lineage --sid succ-1 --pane none;  [ "$output" = "$(printf 'root-0\tlineage-file')" ]
  run /bin/bash -c '. "$1"; lf_lineage succ-1; printf "%s %s" "$LF_LINEAGE" "$LF_LINEAGE_SRC"' _ "$LIBSH"
  [ "$output" = "root-0 lineage-file" ]
  # env beats every file; a pane file past its TTL, or naming this session as the predecessor, is ignored
  CC_LEVER_LINEAGE=root-env run "$PY" -I "$LIBPY" lineage --sid succ-1 --no-write;  [ "${output%%	*}" = root-env ]
  jq '.succ_sid = null | .epoch = 1000' "$CC_LEVER_STATE_DIR/lineage/44.json" > "$BATS_TEST_TMPDIR/l" && mv "$BATS_TEST_TMPDIR/l" "$CC_LEVER_STATE_DIR/lineage/44.json"
  run "$PY" -I "$LIBPY" lineage --sid late-3 --pane 44 --no-write;  [ "$output" = "$(printf 'late-3\tself')" ]
  jq --argjson ep "$(date +%s)" '.epoch = $ep | .pred_sid = "pred-x"' "$CC_LEVER_STATE_DIR/lineage/44.json" > "$BATS_TEST_TMPDIR/l" \
    && mv "$BATS_TEST_TMPDIR/l" "$CC_LEVER_STATE_DIR/lineage/44.json"
  run "$PY" -I "$LIBPY" lineage --sid pred-x --pane 44 --no-write;  [ "$output" = "$(printf 'pred-x\tself')" ]
  run "$PY" -I "$LIBPY" lineage --sid succ-x --pane 44 --no-write;  [ "$output" = "$(printf 'root-0\tlineage-file')" ]
}
