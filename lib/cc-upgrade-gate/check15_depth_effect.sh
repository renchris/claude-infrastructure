#!/usr/bin/env bash
# check15_depth_effect.sh — #15 Nested-spawn containment, EFFECT side (GH #84974).
# ─────────────────────────────────────────────────────────────────────────────
# #6 answers "does CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1 REACH the binary?" — delivery. It cannot
# answer "does the binary then CONTAIN anything?" — effect. GH #84974 is the standing proof that the
# two come apart: on 2.1.225 the variable was delivered exactly as #6 requires and nesting ran anyway,
# one level deeper than configured, because the binary's own gate was off by one. A delivery-only
# probe reports PASS across that entire regression. This check reads the CANDIDATE BINARY's gate.
#
# The gate, extracted from 2.1.260 (measured 2026-09-08, audit
# docs/research/cc-version-audit-2026-09-08.md §3):
#
#     let de = ac(n.agentContext);            // current depth, 0-based at the main session
#     let be = $S();                          // resolved max
#     if (de >= be) throw p("subagent_launch","subagent_depth_cap"), … "Subagent nesting limit reached"
#
# INCLUSIVE `>=` with a 0-based root is what makes depth=1 a FLAT topology: a level-1 subagent has
# de=1, hits 1>=1, and is refused. An EXCLUSIVE `>` is precisely #84974 — depth=1 would then permit
# one nested level. So the operator that separates "contained" from "#84974" is a single character,
# and that character is what this probe reads.
#
# Anchors are the two things minification does NOT rewrite: the telemetry slug `subagent_depth_cap`
# and the user-facing refusal text. Identifiers around them are free to change between versions.
# A binary with neither anchor is not interrogable here → SKIP (never a false green, never a false
# red on a stub or a future repack).
# shellcheck shell=bash

# Bytes before the telemetry slug that must contain the comparison. The 2.1.260 form spends ~40;
# 240 absorbs a re-minification without reaching back into an unrelated statement.
_G15_WINDOW="${CC_GATE15_WINDOW:-240}"

check_15() {
  local bin="${GATE_BIN:-}" window="$_G15_WINDOW" out="" op=""

  if [ -z "$bin" ] || [ ! -r "$bin" ]; then
    emit_result 15 spawn-depth-effect SKIP \
      "candidate binary not readable — cannot interrogate its depth gate" \
      "GATE_BIN=${bin:-<unset>}"
    return 0
  fi

  # Read the window preceding the telemetry slug and classify the comparison operator.
  # Emits one token: MISSING (no anchor) / GE (inclusive, contained) / GT (exclusive, #84974) /
  # UNKNOWN (anchor present, no comparison recognised in the window).
  out="$(python3 - "$bin" "$window" <<'PY' 2>/dev/null
import re, sys
path, window = sys.argv[1], int(sys.argv[2])
try:
    data = open(path, 'rb').read()
except OSError:
    print("MISSING"); raise SystemExit(0)

# A SEA binary carries each anchor MANY times — once per string-table entry and once at the real
# call site. Only the code site has a comparison in front of it, so scan EVERY occurrence rather
# than the first: `re.search` alone reads the constant pool and reports UNKNOWN on a healthy build
# (measured against 2.1.260 while building this probe).
anchors = [m.start() for m in re.finditer(rb'subagent_depth_cap', data)]
anchors += [m.start() for m in re.finditer(rb'Subagent nesting limit reached', data)]
if not anchors:
    print("MISSING"); raise SystemExit(0)

tight = re.compile(rb'([A-Za-z_$][A-Za-z0-9_$]*)\s*(>=|>)\s*([A-Za-z_$][A-Za-z0-9_$]*)\s*\)\s*throw')
loose = re.compile(rb'([A-Za-z_$][A-Za-z0-9_$]*)\s*(>=|>)\s*([A-Za-z_$][A-Za-z0-9_$]*)')
ops = set()
for a in sorted(anchors):
    pre = data[max(0, a - window):a]
    hits = tight.findall(pre) or loose.findall(pre)
    if hits:
        ops.add(hits[-1][1])
if not ops:
    print("UNKNOWN"); raise SystemExit(0)
# Fail toward the weaker guard: if ANY reachable site is exclusive, containment is not established.
print("GT" if b'>' in ops else "GE")
PY
)"
  op="${out:-UNKNOWN}"

  case "$op" in
    GE)
      emit_result 15 spawn-depth-effect PASS \
        "binary refuses at depth >= max (inclusive, 0-based root) — SPAWN_DEPTH=1 yields a FLAT topology" \
        "guard reads 'if (depth >= max) throw subagent_depth_cap'; GH #84974 off-by-one NOT present"
      ;;
    GT)
      emit_result 15 spawn-depth-effect FAIL \
        "binary refuses only at depth > max (EXCLUSIVE) — this is GH #84974: SPAWN_DEPTH=1 still permits one nested level" \
        "guard reads 'if (depth > max) throw subagent_depth_cap'; delivery-side #6 cannot see this"
      ;;
    MISSING)
      emit_result 15 spawn-depth-effect SKIP \
        "no depth-cap marker in the candidate binary — not an interrogable build (stub or repacked)" \
        "neither 'subagent_depth_cap' nor 'Subagent nesting limit reached' found"
      ;;
    *)
      emit_result 15 spawn-depth-effect FAIL \
        "depth-cap marker present but its comparison is unrecognised — containment UNVERIFIED, treat as uncapped" \
        "widen with CC_GATE15_WINDOW=<bytes>; fail-closed by design (an unread guard is not a guard)"
      ;;
  esac
  return 0
}
