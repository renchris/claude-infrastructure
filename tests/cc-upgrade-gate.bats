#!/usr/bin/env bats
# cc-upgrade-gate — HERMETIC contract + known-bad tests. No network, no real binary, no quota.
#
# The orchestrator globs check*.sh from CC_UPGRADE_GATE_CHECKS (default = real lib) — every test
# points it at a temp dir of stub probes so we NEVER glob the real (mid-write) sibling checks; only
# common.sh is exercised from the real lib. HOME is a temp dir so no real ~/.claude-next is touched.
# The candidate "binary" is always a stub that answers --version + emits canned --output-format json.
#
# Bats 1.13: `run` merges stdout+stderr into $output, so wherever we parse the machine JSON we
# redirect the gate's stdout to a file and drop stderr — the exit code still propagates as $status.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  GATE="$REPO/scripts/cc-upgrade-gate.sh"
  COMMON="$REPO/lib/cc-upgrade-gate/common.sh"
  export REPO GATE COMMON
}

# a candidate stub binary that registers claude-opus-5 (answers --version; emits modelUsage on json)
_stub_bin_registers() {
  printf '#!/usr/bin/env bash\ncase " $* " in *" --version "*) echo 2.1.999;; *) echo '\''{"is_error":false,"result":"ok","modelUsage":{"claude-opus-5":{}}}'\'';; esac\n' > "$1"
  chmod +x "$1"
}

# ── #1 known-bad baseline: binary that does NOT register the model fails LOUD at check #1 ──────────
@test "known-bad binary (model unregistered) → check #1 FAIL, verdict RED, exit 1" {
  TMPC="$BATS_TEST_TMPDIR/checks"; mkdir -p "$TMPC"
  cp "$REPO/lib/cc-upgrade-gate/check01_binary.sh" "$TMPC/"
  # answers --version but comes back with EMPTY modelUsage → the model is not registered
  printf '#!/usr/bin/env bash\ncase " $* " in *" --version "*) echo 2.1.999;; *) echo '\''{"is_error":false,"result":"ok","modelUsage":{}}'\'';; esac\n' > "$TMPC/stubbin"
  chmod +x "$TMPC/stubbin"
  H="$BATS_TEST_TMPDIR/home"; mkdir -p "$H/.claude-next"   # so check01 RUNS (not SKIP)
  JSON="$BATS_TEST_TMPDIR/out.json"

  run bash -c 'HOME="$1" CC_UPGRADE_GATE_CHECKS="$2" bash "$3" "$4" claude-opus-5 next >"$5" 2>/dev/null' \
      _ "$H" "$TMPC" "$GATE" "$TMPC/stubbin" "$JSON"
  [ "$status" -eq 1 ]
  grep -q '"verdict": "RED"' "$JSON"
  run python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); c=next(x for x in r["checks"] if x["check"]==1); sys.exit(0 if c["status"]=="FAIL" else 1)' "$JSON"
  [ "$status" -eq 0 ]
}

# ── #2 the mirror: a binary that DOES register the model passes check #1 → GREEN ───────────────────
@test "registered model → check #1 PASS, verdict GREEN, exit 0" {
  TMPC="$BATS_TEST_TMPDIR/checks"; mkdir -p "$TMPC"
  cp "$REPO/lib/cc-upgrade-gate/check01_binary.sh" "$TMPC/"
  _stub_bin_registers "$TMPC/stubbin"
  H="$BATS_TEST_TMPDIR/home"; mkdir -p "$H/.claude-next"
  JSON="$BATS_TEST_TMPDIR/out.json"

  run bash -c 'HOME="$1" CC_UPGRADE_GATE_CHECKS="$2" bash "$3" "$4" claude-opus-5 next >"$5" 2>/dev/null' \
      _ "$H" "$TMPC" "$GATE" "$TMPC/stubbin" "$JSON"
  [ "$status" -eq 0 ]
  grep -q '"verdict": "GREEN"' "$JSON"
  run python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); c=next(x for x in r["checks"] if x["check"]==1); sys.exit(0 if c["status"]=="PASS" else 1)' "$JSON"
  [ "$status" -eq 0 ]
}

# ── #2b the documented invocation is a per-file symlink (~/.claude/scripts/…) with no lib beside it ─
@test "invoked through a symlink outside the repo → still finds lib/cc-upgrade-gate (not exit 2)" {
  TMPC="$BATS_TEST_TMPDIR/checks"; mkdir -p "$TMPC"
  cp "$REPO/lib/cc-upgrade-gate/check01_binary.sh" "$TMPC/"
  _stub_bin_registers "$TMPC/stubbin"
  H="$BATS_TEST_TMPDIR/home"; mkdir -p "$H/.claude-next" "$H/.claude/scripts"
  ln -s "$GATE" "$H/.claude/scripts/cc-upgrade-gate.sh"
  JSON="$BATS_TEST_TMPDIR/out.json"

  run bash -c 'HOME="$1" CC_UPGRADE_GATE_CHECKS="$2" bash "$3" "$4" claude-opus-5 next >"$5" 2>/dev/null' \
      _ "$H" "$TMPC" "$H/.claude/scripts/cc-upgrade-gate.sh" "$TMPC/stubbin" "$JSON"
  [ "$status" -eq 0 ]
  grep -q '"verdict": "GREEN"' "$JSON"
}

# ── #3 common.sh contract: emit_result writes exactly one valid JSON line with the given fields ────
@test "common.sh: emit_result appends exactly one valid JSON line carrying its fields" {
  RES="$BATS_TEST_TMPDIR/results.jsonl"; : > "$RES"
  run bash -c 'export GATE_RESULTS="$1"; source "$2"; emit_result 7 spawn-teams PASS "the-evidence" "the-detail"' \
      _ "$RES" "$COMMON"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$RES" | tr -d ' ')" -eq 1 ]
  run python3 -c 'import json,sys; o=json.load(open(sys.argv[1])); sys.exit(0 if (o=={"check":7,"slug":"spawn-teams","status":"PASS","evidence":"the-evidence","detail":"the-detail"}) else 1)' "$RES"
  [ "$status" -eq 0 ]
}

# ── #3 common.sh contract: json_has_model gates on model-present AND not-is_error ──────────────────
@test "common.sh: json_has_model — PASS only when model present AND is_error falsey" {
  # present + not-error → exit 0
  run bash -c 'source "$1"; printf "%s" "$2" | json_has_model claude-opus-5' _ "$COMMON" '{"modelUsage":{"claude-opus-5":{}}}'
  [ "$status" -eq 0 ]
  # empty modelUsage → exit 1
  run bash -c 'source "$1"; printf "%s" "$2" | json_has_model claude-opus-5' _ "$COMMON" '{"modelUsage":{}}'
  [ "$status" -eq 1 ]
  # model present but is_error true (a demotion/error) → exit 1
  run bash -c 'source "$1"; printf "%s" "$2" | json_has_model claude-opus-5' _ "$COMMON" '{"is_error":true,"modelUsage":{"claude-opus-5":{}}}'
  [ "$status" -eq 1 ]
}

# ── #3 common.sh contract: json_get prints the scalar value (empty on absent) ──────────────────────
@test "common.sh: json_get prints the scalar value, empty on absent key" {
  run bash -c 'source "$1"; printf "%s" "$2" | json_get is_error' _ "$COMMON" '{"is_error":true,"modelUsage":{}}'
  [ "$status" -eq 0 ]
  [ "$output" = "True" ]
  run bash -c 'source "$1"; printf "%s" "$2" | json_get nope' _ "$COMMON" '{"is_error":true}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ── #3 common.sh contract: build_stub_binary makes an exec that records argv + spawn depth ─────────
@test "common.sh: build_stub_binary records argv + spawn depth to STUB_LOG" {
  LOG="$BATS_TEST_TMPDIR/stub.log"; : > "$LOG"
  FAKE="$BATS_TEST_TMPDIR/fakebin"
  run bash -c 'export STUB_LOG="$1"; source "$2"; build_stub_binary "$3"; CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1 "$3" --model claude-opus-5 --print --output-format json' \
      _ "$LOG" "$COMMON" "$FAKE"
  [ "$status" -eq 0 ]
  [ -x "$FAKE" ]
  grep -q '^ARGV: --model claude-opus-5 --print --output-format json$' "$LOG"
  grep -q '^SPAWN_DEPTH=1$' "$LOG"
}

# ── #4 verdict aggregation: PASS + SKIP + PASS (no FAIL) → GREEN; SKIP never drags red ─────────────
@test "verdict aggregation: SKIP does not drag red (pass+skip+pass → GREEN, exit 0)" {
  TMPC="$BATS_TEST_TMPDIR/checks"; mkdir -p "$TMPC"
  printf '#!/usr/bin/env bash\ncheck_90(){ emit_result 90 alpha PASS "ok" "d"; }\n' > "$TMPC/check90_alpha.sh"
  printf '#!/usr/bin/env bash\ncheck_91(){ emit_result 91 beta SKIP "n/a" "d"; }\n' > "$TMPC/check91_beta.sh"
  printf '#!/usr/bin/env bash\ncheck_92(){ emit_result 92 gamma PASS "ok" "d"; }\n' > "$TMPC/check92_gamma.sh"
  _stub_bin_registers "$TMPC/stubbin"   # only needed for --version + preflight; the checks don't call it
  H="$BATS_TEST_TMPDIR/home"; mkdir -p "$H"
  JSON="$BATS_TEST_TMPDIR/out.json"

  run bash -c 'HOME="$1" CC_UPGRADE_GATE_CHECKS="$2" bash "$3" "$4" claude-opus-5 next >"$5" 2>/dev/null' \
      _ "$H" "$TMPC" "$GATE" "$TMPC/stubbin" "$JSON"
  [ "$status" -eq 0 ]
  grep -q '"verdict": "GREEN"' "$JSON"
  grep -q '"skip": 1' "$JSON"   # the SKIP was counted, not silently dropped
}

# ── #4 verdict aggregation: flipping one check to FAIL → RED + exit 1 ──────────────────────────────
@test "verdict aggregation: any FAIL → RED, exit 1" {
  TMPC="$BATS_TEST_TMPDIR/checks"; mkdir -p "$TMPC"
  printf '#!/usr/bin/env bash\ncheck_90(){ emit_result 90 alpha PASS "ok" "d"; }\n' > "$TMPC/check90_alpha.sh"
  printf '#!/usr/bin/env bash\ncheck_91(){ emit_result 91 beta SKIP "n/a" "d"; }\n' > "$TMPC/check91_beta.sh"
  printf '#!/usr/bin/env bash\ncheck_92(){ emit_result 92 gamma FAIL "regressed" "d"; }\n' > "$TMPC/check92_gamma.sh"
  _stub_bin_registers "$TMPC/stubbin"
  H="$BATS_TEST_TMPDIR/home"; mkdir -p "$H"
  JSON="$BATS_TEST_TMPDIR/out.json"

  run bash -c 'HOME="$1" CC_UPGRADE_GATE_CHECKS="$2" bash "$3" "$4" claude-opus-5 next >"$5" 2>/dev/null' \
      _ "$H" "$TMPC" "$GATE" "$TMPC/stubbin" "$JSON"
  [ "$status" -eq 1 ]
  grep -q '"verdict": "RED"' "$JSON"
}

# ── #15 spawn-depth EFFECT: the one character that separates containment from GH #84974 ───────────
# #6 proves SPAWN_DEPTH=1 is DELIVERED. It cannot prove the binary then contains anything: on
# 2.1.225 delivery was correct and nesting ran one level deeper than configured anyway (#84974).
# These four cases pin the effect side. The FAIL case is the red-proof — it is the literal pre-fix
# shape, and it must go red or the probe is decoration.
_g15_run() {  # $1 = fixture path → prints "STATUS :: evidence"
  bash -c '
    export GATE_BIN="$1"
    emit_result(){ echo "$3 :: $4"; }
    . "$2/lib/cc-upgrade-gate/check15_depth_effect.sh"
    check_15
  ' _ "$1" "$REPO"
}

@test "check15: EXCLUSIVE '>' guard is GH #84974 → FAIL (red-proof, the pre-fix shape)" {
  F="$BATS_TEST_TMPDIR/gt.bin"
  printf 'let de=0,be=1;if(de>be)throw p("subagent_launch","subagent_depth_cap"),new E("Subagent nesting limit reached");' > "$F"
  run _g15_run "$F"
  [ "$status" -eq 0 ]
  [[ "$output" == FAIL* ]] || false
  [[ "$output" == *"#84974"* ]]
}

@test "check15: INCLUSIVE '>=' guard contains nesting → PASS" {
  F="$BATS_TEST_TMPDIR/ge.bin"
  printf 'let de=0,be=1;if(de>=be)throw p("subagent_launch","subagent_depth_cap"),new E("Subagent nesting limit reached");' > "$F"
  run _g15_run "$F"
  [ "$status" -eq 0 ]
  [[ "$output" == PASS* ]]
}

@test "check15: no depth-cap marker → SKIP, never a false green" {
  F="$BATS_TEST_TMPDIR/none.bin"; printf 'nothing to see here' > "$F"
  run _g15_run "$F"
  [ "$status" -eq 0 ]
  [[ "$output" == SKIP* ]]
}

@test "check15: marker present but comparison unreadable → FAIL (an unread guard is not a guard)" {
  # anchor with no comparison anywhere in the preceding window ⇒ containment UNVERIFIED, fail-closed
  F="$BATS_TEST_TMPDIR/unk.bin"
  printf 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa subagent_depth_cap' > "$F"
  run _g15_run "$F"
  [ "$status" -eq 0 ]
  [[ "$output" == FAIL* ]] || false
  [[ "$output" == *UNVERIFIED* ]]
}

@test "check15: the string table alone must not decide — a healthy SEA has many anchor copies" {
  # regression pin: scanning only the FIRST anchor reads the constant pool and reports UNKNOWN on a
  # healthy build. Measured against real 2.1.260 while building this probe. Pool copies first, code last.
  F="$BATS_TEST_TMPDIR/pool.bin"
  printf 'subagent_depth_cap\0subagent_depth_cap\0PAD;if(de>=be)throw p("subagent_launch","subagent_depth_cap")' > "$F"
  run _g15_run "$F"
  [ "$status" -eq 0 ]
  [[ "$output" == PASS* ]]
}

# ── #16 per-agent token budget switch (decision D6, migration 0060) ──────────────────────────────
# The stub answers the parent-side question the way 2.1.293 was measured to: with
# CLAUDE_CODE_RIPPLING_TULIP set to a number in its env it quotes the budget sentence, and a
# --settings file's env value replaces the shell value (D6 arm S0). STUB16 selects a binary that
# ignores the settings value (the regression), one that never shows a budget (cannot tell), and one
# that answers nothing. The FAIL case is the red-proof: the switch went inert and the probe must say so.
_g16_run() {  # $1 = STUB16 mode → prints "STATUS :: evidence :: detail"
  bash -c '
    export HOME="$1/home" GATE_BIN="$1/stub16" GATE_MODEL=claude-opus-5-5 GATE_ACCOUNTS=next GATE_RETRIES=1 STUB16="$3"
    mkdir -p "$HOME/.claude-next"
    . "$2/lib/cc-upgrade-gate/common.sh"
    emit_result(){ echo "$3 :: $4 :: $5"; }
    . "$2/lib/cc-upgrade-gate/check16_agent_budget.sh"
    check_16
  ' _ "$BATS_TEST_TMPDIR" "$REPO" "$1"
}

_g16_stub() {
  cat > "$BATS_TEST_TMPDIR/stub16" <<'STUB'
#!/usr/bin/env bash
v="${CLAUDE_CODE_RIPPLING_TULIP:-}"; sf=""
while [ $# -gt 0 ]; do [ "$1" = --settings ] && { sf="$2"; shift; }; shift; done
[ "$STUB16" = silent ] && exit 1
if [ -n "$sf" ] && [ "$STUB16" != ignores ]; then v="$(jq -r '.env.CLAUDE_CODE_RIPPLING_TULIP // empty' "$sf")"; fi
r=NONE
if [ "$STUB16" != noforce ] && [ -n "$v" ] && [ "$v" != 0 ]; then
  r="Each fresh agent you launch has a budget of $(printf "%'d" "$v" 2>/dev/null || echo "$v") tokens, counting the context it starts with."
fi
jq -cn --arg r "$r" '{is_error:false,result:$r,modelUsage:{"claude-opus-5-5":{}}}'
STUB
  chmod +x "$BATS_TEST_TMPDIR/stub16"
}

@test "check16: the switch removes a forced budget → PASS" {
  _g16_stub
  run _g16_run honors
  [ "$status" -eq 0 ]
  [[ "$output" == PASS* ]] || { echo "$output"; false; }
  [[ "$output" == *"server flags: none cached"* ]] || { echo "$output"; false; }
}

@test "check16: a binary that still shows the budget with the switch set → FAIL (red-proof)" {
  _g16_stub
  run _g16_run ignores
  [ "$status" -eq 0 ]
  [[ "$output" == FAIL* ]] || { echo "$output"; false; }
  [[ "$output" == *"0060 is inert"* ]]
}

@test "check16: a control that shows no budget cannot tell → SKIP, never a false green" {
  _g16_stub
  run _g16_run noforce
  [[ "$output" == SKIP* ]] || { echo "$output"; false; }
  [[ "$output" == *"cannot tell"* ]]
}

@test "check16: no usable answer, or no executable binary → SKIP" {
  _g16_stub
  run _g16_run silent
  [[ "$output" == SKIP* ]] || { echo "$output"; false; }
  rm "$BATS_TEST_TMPDIR/stub16"
  run _g16_run honors
  [[ "$output" == SKIP* ]] || { echo "$output"; false; }
}

@test "check16: a budget flag cached in an account is named in the evidence" {
  _g16_stub
  mkdir -p "$BATS_TEST_TMPDIR/home/.claude-next"
  printf '{"cachedGrowthBookFeatures":{"tengu_rippling_tulip":250000}}\n' > "$BATS_TEST_TMPDIR/home/.claude-next/.claude.json"
  run _g16_run honors
  [[ "$output" == PASS* ]] || { echo "$output"; false; }
  [[ "$output" == *"claude-next:tengu_rippling_tulip=250000"* ]] || { echo "$output"; false; }
  [[ "$output" == *"ALARM"* ]]
}
