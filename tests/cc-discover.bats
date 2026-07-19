#!/usr/bin/env bats
# cc-discover — the discovery feed (Program D phase 3). The tool's `selftest` RED-proves every
# critic branch against stubbed sources; these bats add (a) the selftest exit-code + ok-count
# contract and (b) independent CLI-level end-to-end `--once`/`--dry-run` runs through the real
# override surface (proving run_once works outside the in-script selftest helper, not just it).
# Every assertion checks the EFFECT — a backlog record appeared, or did not — never a self-report.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  CD="$REPO/bin/cc-discover"
  BL="$REPO/bin/cc-backlog"
  C="$BATS_TEST_TMPDIR/case"
  mkdir -p "$C"
  # cc-backlog + its store are wired; every discovery SOURCE defaults to ABSENT so each test
  # enables only the one(s) it exercises (an absent source must ABSTAIN, never fabricate).
  export CC_DISCOVER_BACKLOG_BIN="$BL"
  export CC_BACKLOG_FILE="$C/backlog.jsonl"
  export CC_DISCOVER_IDL="$C/idl.jsonl"
  export CC_DISCOVER_FRONTIER_LEDGER="$C/absent-ledger.md"
  export CC_DISCOVER_FINDPLAN="$C/absent-findplan"
  export CC_DISCOVER_GATES="$C/absent-gate"
  export CC_DISCOVER_PROJECT="batscase"
}

# count add-records of a given source in the backlog store (0 if the store is absent).
# The -f guard matters: `jq -rs` on a missing file slurps to [] (prints 0) AND exits non-zero,
# so a bare `|| echo 0` would double the output and break the `-eq` comparison.
count_src() {
  [ -f "$CC_BACKLOG_FILE" ] || { echo 0; return 0; }
  jq -rs --arg s "$1" '[.[]|select(.event=="add" and .source==$s)]|length' "$CC_BACKLOG_FILE" 2>/dev/null || echo 0
}

# ── the selftest contract ────────────────────────────────────────────────────
@test "selftest passes and runs all 14 checks (a zero-check suite must not 'pass')" {
  run "$CD" selftest
  [ "$status" -eq 0 ]
  n_ok="$(printf '%s' "$output" | grep -c '^  ok ')"
  [ "$n_ok" -eq 14 ]
  ! printf '%s' "$output" | grep -q '^  FAIL'
}

@test "unknown arg → exit 2 (fail-loud, no silent no-op)" {
  run "$CD" --bogus
  [ "$status" -eq 2 ]
}

# ── C1 frontier-hole (CLI-level) ─────────────────────────────────────────────
@test "C1 frontier-hole: 1 OPEN hole → exactly 1 frontier-hole add" {
  printf '## Open\n\n### H-3 · CVR seam — OPEN 2026-07-18\n- x\n' > "$C/ledger.md"
  export CC_DISCOVER_FRONTIER_LEDGER="$C/ledger.md"
  run "$CD" --once
  [ "$status" -eq 0 ]
  [ "$(count_src frontier-hole)" -eq 1 ]
}

@test "C1 frontier-hole: a RESOLVED hole (no OPEN marker) does NOT add" {
  printf '## Resolved\n\n### H-2 · old seam — RESOLVED 2026-07-01\n' > "$C/ledger.md"
  export CC_DISCOVER_FRONTIER_LEDGER="$C/ledger.md"
  run "$CD" --once
  [ "$(count_src frontier-hole)" -eq 0 ]
}

# ── C2 plan-open (CLI-level) ─────────────────────────────────────────────────
@test "C2 plan-open: default scope adds ONLY the mission project's rows (foreign plans skipped)" {
  cat > "$C/findplan" <<'EOF'
#!/bin/bash
[ "$1" = "--list-open" ] || exit 0
printf '%s\n' "OPEN        | projA | /p/a.md | Plan A"
printf '%s\n' "IN-PROGRESS | projB | /p/b.md | Plan B"
EOF
  chmod +x "$C/findplan"
  export CC_DISCOVER_FINDPLAN="$C/findplan"
  export CC_DISCOVER_PROJECT=projA
  run "$CD" --once
  [ "$status" -eq 0 ]
  [ "$(count_src plan-open)" -eq 1 ]
}

@test "C2 plan-open: CC_DISCOVER_PLAN_SCOPE=all restores the L4 cross-project walk (2 adds)" {
  cat > "$C/findplan" <<'EOF'
#!/bin/bash
[ "$1" = "--list-open" ] || exit 0
printf '%s\n' "OPEN        | projA | /p/a.md | Plan A"
printf '%s\n' "IN-PROGRESS | projB | /p/b.md | Plan B"
EOF
  chmod +x "$C/findplan"
  export CC_DISCOVER_FINDPLAN="$C/findplan"
  export CC_DISCOVER_PROJECT=projA
  export CC_DISCOVER_PLAN_SCOPE=all
  run "$CD" --once
  [ "$status" -eq 0 ]
  [ "$(count_src plan-open)" -eq 2 ]
}

# ── C3 wiring-inert (CLI-level) ──────────────────────────────────────────────
# Every seed carries .ts, as every real IDL record does — the recency horizon reads it.
@test "C3 wiring-inert: a hook abstained 11/11 (N>=10, 100%) → 1 wiring-inert add" {
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  for _ in $(seq 1 11); do printf '{"hook":"stale-guard","disposition":"abstained","ts":"%s"}\n' "$now"; done > "$C/seed.jsonl"
  export CC_DISCOVER_IDL="$C/seed.jsonl"
  run "$CD" --once
  [ "$status" -eq 0 ]
  [ "$(count_src wiring-inert)" -eq 1 ]
}

@test "C3 wiring-inert: a hook below the N>=10 window does NOT add" {
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  for _ in $(seq 1 5); do printf '{"hook":"g","disposition":"abstained","ts":"%s"}\n' "$now"; done > "$C/seed.jsonl"
  export CC_DISCOVER_IDL="$C/seed.jsonl"
  run "$CD" --once
  [ "$(count_src wiring-inert)" -eq 0 ]
}

@test "C3 wiring-inert: a hook that fired in-horizon is NOT inert → 0 adds" {
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  { for _ in $(seq 1 10); do printf '{"hook":"g","disposition":"abstained","ts":"%s"}\n' "$now"; done
    printf '{"hook":"g","disposition":"fired","ts":"%s"}\n' "$now"; } > "$C/seed.jsonl"
  export CC_DISCOVER_IDL="$C/seed.jsonl"
  run "$CD" --once
  [ "$(count_src wiring-inert)" -eq 0 ]
}

# Regression (e7d326caa6a7): a record-flood night must not false-flag a rare hook that fired that
# night. The fire is buried first, then a 6000-record flood (> the 5000 tail) that a naive global
# tail would let crowd the fire out of view; the fix greps to hook-eval records + exonerates in-horizon fires.
@test "C3 wiring-inert: record-flood does NOT false-flag a rare hook that fired in-horizon (regression: e7d326caa6a7)" {
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  fired="$(date -u -v-2H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '-2 hours' +%Y-%m-%dT%H:%M:%SZ)"
  {
    printf '{"hook":"rare-guard","disposition":"fired","ts":"%s"}\n' "$fired"
    for _ in $(seq 1 6000); do printf '{"actor":"pager","kind":"page","ts":"%s"}\n' "$now"; done
    for _ in $(seq 1 12); do printf '{"hook":"rare-guard","disposition":"abstained","ts":"%s"}\n' "$now"; done
    for _ in $(seq 1 12); do printf '{"hook":"dead-guard","disposition":"abstained","ts":"%s"}\n' "$now"; done
  } > "$C/seed.jsonl"
  export CC_DISCOVER_IDL="$C/seed.jsonl"
  run "$CD" --once
  [ "$status" -eq 0 ]
  # dead-guard (never fired) is added; rare-guard (fired in-horizon) is not
  [ "$(count_src wiring-inert)" -eq 1 ]
  grep -q 'inert hook dead-guard' "$CC_BACKLOG_FILE"
  ! grep -q 'rare-guard' "$CC_BACKLOG_FILE"
}

# ── C4 gate-red (CLI-level) ──────────────────────────────────────────────────
@test "C4 gate-red: a gate exiting non-zero → 1 gate-red add" {
  printf '#!/bin/bash\nexit 7\n' > "$C/redgate"; chmod +x "$C/redgate"
  export CC_DISCOVER_GATES="$C/redgate"
  run "$CD" --once
  [ "$status" -eq 0 ]
  [ "$(count_src gate-red)" -eq 1 ]
}

@test "C4 gate-red: a green gate → 0 adds (RED-prove the negative)" {
  printf '#!/bin/bash\nexit 0\n' > "$C/greengate"; chmod +x "$C/greengate"
  export CC_DISCOVER_GATES="$C/greengate"
  run "$CD" --once
  [ "$(count_src gate-red)" -eq 0 ]
}

# ── abstain / idempotency / dry-run (the load-bearing invariants) ─────────────
@test "all sources absent → ZERO adds + abstentions logged to the IDL (effect-verified)" {
  run "$CD" --once
  [ "$status" -eq 0 ]
  [ ! -f "$CC_BACKLOG_FILE" ] || [ "$(wc -l < "$CC_BACKLOG_FILE" | tr -d ' ')" -eq 0 ]
  ab="$(jq -rs '[.[]|select(.action=="abstained")]|length' "$CC_DISCOVER_IDL" 2>/dev/null || echo 0)"
  [ "$ab" -ge 3 ]
}

@test "abstain never fabricates: a present-but-empty ledger → 0 adds (no spurious candidate)" {
  : > "$C/ledger.md"   # exists, but contains no OPEN holes
  export CC_DISCOVER_FRONTIER_LEDGER="$C/ledger.md"
  run "$CD" --once
  [ "$status" -eq 0 ]
  [ "$(count_src frontier-hole)" -eq 0 ]
}

@test "idempotency: a second --once over unchanged sources adds ZERO new" {
  printf '### H-1 · a — OPEN 2026-07-18\n### H-2 · b — OPEN 2026-07-18\n' > "$C/ledger.md"
  export CC_DISCOVER_FRONTIER_LEDGER="$C/ledger.md"
  run "$CD" --once
  [ "$(count_src frontier-hole)" -eq 2 ]
  run "$CD" --once
  [ "$(count_src frontier-hole)" -eq 2 ]
}

@test "--dry-run: candidates printed, backlog store UNCHANGED (no side effects)" {
  printf '### H-5 · dryhole — OPEN 2026-07-18\n' > "$C/ledger.md"
  export CC_DISCOVER_FRONTIER_LEDGER="$C/ledger.md"
  run "$CD" --dry-run
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q '^candidate \[frontier-hole\]'
  [ ! -f "$CC_BACKLOG_FILE" ]
}
