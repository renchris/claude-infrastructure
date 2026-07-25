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
