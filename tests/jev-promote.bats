#!/usr/bin/env bats
# `cc-jev promote` — the comparative promotion pass.
#
# WHY A COMPARATIVE PASS AND NOT ANOTHER RANKER. `cc-jev rank` ran on 2026-09-21 and returned
# `often` for 118 of 140 indexed rules — 84.3% on a 4-level scale that never used its top level —
# while `superseded` produced ZERO rows in the >=0.90 band hooks/lib/jev.sh defines as the only
# actionable one. Sound verdicts, worthless ordering. A forced choice has no scale to saturate,
# and it is also the shape the decision actually has: the index is FULL, so a promotion that
# names no demotion is not executable.

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/autonomy"
}
# `|| true` on the kill itself, not a trailing `return 0`: under load the mock can be reaped
# before teardown runs, and silencing stderr does not silence the EXIT STATUS — the failed kill
# aborts the body before anything after it executes. This is a cleanup, never an assertion that
# the target is alive.
teardown() {
  [ -n "${MOCKPID:-}" ] && { kill "$MOCKPID" 2>/dev/null || true; }
  return 0
}

start_mock() {
  node "$REPO/tests/fixtures/jev-mock-gateway.mjs" "${1:-ok}" > "$BATS_TEST_TMPDIR/port" 2>&1 &
  MOCKPID=$!
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    PORT="$(tr -d '\n' < "$BATS_TEST_TMPDIR/port")"; [ -n "$PORT" ] && break; sleep 0.2
  done
  [ -n "$PORT" ]
}

mkcorpus() {  # 12 orphans, 3 incumbents, 2 of them weak
  MEMD="$BATS_TEST_TMPDIR/mem"; mkdir -p "$MEMD"
  for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
    printf -- '---\nname: orph%s\ndescription: orphan rule %s\n---\n\nbody of orphan %s\n' "$i" "$i" "$i" > "$MEMD/orph$i.md"
  done
  for i in 1 2 3; do
    printf -- '---\nname: inc%s\ndescription: incumbent rule %s\n---\n\nbody of incumbent %s\n' "$i" "$i" "$i" > "$MEMD/inc$i.md"
  done
  printf -- '- [I1](inc1.md) — a\n- [I2](inc2.md) — b\n- [I3](inc3.md) — c\n' > "$MEMD/MEMORY.md"
  RANKF="$BATS_TEST_TMPDIR/rank.jsonl"
  printf '%s\n' '{"file":"inc1.md","level":"occasionally"}' \
                '{"file":"inc2.md","level":"almost-never"}' \
                '{"file":"inc3.md","level":"often"}' > "$RANKF"
}
# runp [VAR=val ...] [-- script args ...]
# The split matters: an env assignment must land BEFORE the binary and a script flag AFTER it.
# A first draft put "$@" in env's variable position, so `--yes` became the COMMAND env tried to
# exec — every call exited 127, and a test asserting a refusal code read that as an ordinary
# failure rather than as "the harness never ran the subject".
runp() {
  local envs=()
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do envs+=("$1"); shift; done
  [ $# -gt 0 ] && shift
  env AI_GATEWAY_API_KEY=dummy CC_JEV_RULES_FILE=/dev/null CC_JEV_RANK_ROWS="$RANKF" \
      CC_JEV_PROMO_GAP=0 "${envs[@]}" "$REPO/bin/cc-jev" promote --mem "$MEMD" "$@"
}

@test "promote: refuses without --yes, and sends nothing" {
  mkcorpus
  run runp
  [ "$status" -eq 3 ]
  grep -qF "Re-run with --yes" <<<"$output"
  grep -qF "Nothing has been sent" <<<"$output"
}

@test "promote: ZDR on refuses BEFORE the first call and names the exact command" {
  mkcorpus
  run runp -- --yes
  [ "$status" -eq 4 ]
  grep -qF "REFUSING before the first call" <<<"$output"
  grep -qF "CC_JEV_ZDR=0 cc-jev promote --yes" <<<"$output"
}

# A promotion verdict is only executable as a SWAP, and a swap needs the incumbent it displaces.
# Substituting an arbitrary incumbent would recommend evicting a rule holding its slot correctly.
@test "promote: no weak-incumbent anchors is a REFUSAL, not a silent substitution" {
  mkcorpus
  printf '%s\n' '{"file":"inc3.md","level":"often"}' > "$RANKF"   # no weak rows at all
  run runp CC_JEV_ZDR=0 -- --yes
  [ "$status" -eq 3 ]
  grep -qF "no weak-incumbent anchors" <<<"$output"
  grep -qF "cc-jev rank --yes" <<<"$output"      # it names how to produce them
  grep -qF "Nothing has been sent" <<<"$output"
}

@test "promote: a dead route aborts at the preflight, naming the reason, before the batch" {
  mkcorpus
  run runp CC_JEV_ZDR=0 CC_JEV_BASE_URL="http://127.0.0.1:1" -- --yes
  [ "$status" -eq 4 ]
  grep -qF "preflight call produced no verdict" <<<"$output"
  grep -qF "reason: http" <<<"$output"
}

@test "promote: a full run emits a swap list and never touches the index" {
  mkcorpus
  # cp + cmp rather than md5: the bats corpus runs under com.claude.nightly-regression, whose PATH
  # does not carry /sbin, so `md5` is simply unreachable there — and a byte comparison says WHICH
  # byte moved, which a hash cannot.
  cp "$MEMD/MEMORY.md" "$BATS_TEST_TMPDIR/index.before"
  export MOCK_CHOICE_ROTATE=1
  start_mock ok
  run runp CC_JEV_ZDR=0 CC_JEV_BASE_URL="http://127.0.0.1:$PORT" -- --bias-n 2 --yes
  [ "$status" -eq 0 ]
  grep -qF "SWAP LIST" <<<"$output"
  grep -qE "swap\(s\) proposed" <<<"$output"
  grep -qF "Nothing was edited" <<<"$output"
  cmp -s "$BATS_TEST_TMPDIR/index.before" "$MEMD/MEMORY.md" \
    || { echo "the run MUTATED the index — the entire safety case is that it does not"; false; }
  ROWS=$(grep -o '/.*jev-promote-.*\.jsonl' <<<"$output" | tail -1)
  [ -s "$ROWS" ]
  [ "$(jq -r 'select(.round=="heat")|.id' "$ROWS" | wc -l | tr -d ' ')" -gt 0 ]
  [ "$(jq -r 'select(.round=="h2h")|.id'  "$ROWS" | wc -l | tr -d ' ')" -gt 0 ]
}

# 🚨 THE CONTROL'S OWN ARITHMETIC, RED-PROOFED. The first implementation indexed a --slurpfile as
# $all[0] — the first OBJECT, not the array — so every row errored on stderr, stdout was empty,
# wc -l read 0, and the run printed "0 of 2 pairs (0%) changed" with a ✓ PASS. A broken control
# that reports the safe answer is worse than no control: this is the one check that can refute the
# whole design and it was certifying it out of an error. These rows are hand-built, so the right
# answer is known by construction and no call is made.
@test "bias control: counts a flip when the winner keeps its LETTER across a swap" {
  R="$BATS_TEST_TMPDIR/b.jsonl"
  # r2-1 and r2-2 flip (same letter after the blocks were reversed); r2-3 is consistent.
  printf '%s\n' \
   '{"id":"r2-1","round":"h2h","block_a":"x.md","block_b":"y.md","winner":"a","swapped":false}' \
   '{"id":"r2-2","round":"h2h","block_a":"p.md","block_b":"q.md","winner":"b","swapped":false}' \
   '{"id":"r2-3","round":"h2h","block_a":"m.md","block_b":"n.md","winner":"a","swapped":false}' \
   '{"id":"swap-r2-1","round":"h2h","block_a":"y.md","block_b":"x.md","winner":"a","swapped":true}' \
   '{"id":"swap-r2-2","round":"h2h","block_a":"q.md","block_b":"p.md","winner":"b","swapped":true}' \
   '{"id":"swap-r2-3","round":"h2h","block_a":"n.md","block_b":"m.md","winner":"b","swapped":true}' > "$R"
  run env -u AI_GATEWAY_API_KEY "$REPO/bin/cc-jev" promote --report "$R"
  [ "$status" -eq 0 ]
  grep -qF "2 of 3 pairs (66%) changed their winner" <<<"$output"
  grep -qF "ABOVE the 20% ceiling" <<<"$output"
  grep -qF "COMPARATIVE DESIGN IS REFUTED" <<<"$output"
}

@test "bias control: a clean sweep passes, and the ceiling is the only thing that decides" {
  R="$BATS_TEST_TMPDIR/c.jsonl"
  printf '%s\n' \
   '{"id":"r2-1","round":"h2h","block_a":"x.md","block_b":"y.md","winner":"a","swapped":false}' \
   '{"id":"r2-2","round":"h2h","block_a":"p.md","block_b":"q.md","winner":"b","swapped":false}' \
   '{"id":"swap-r2-1","round":"h2h","block_a":"y.md","block_b":"x.md","winner":"b","swapped":true}' \
   '{"id":"swap-r2-2","round":"h2h","block_a":"q.md","block_b":"p.md","winner":"a","swapped":true}' > "$R"
  run env -u AI_GATEWAY_API_KEY "$REPO/bin/cc-jev" promote --report "$R"
  [ "$status" -eq 0 ]
  grep -qF "0 of 2 pairs (0%) changed" <<<"$output"
  grep -qF "within the 20% ceiling" <<<"$output"
  ! grep -qF "REFUTED" <<<"$output" || { echo "clean sweep called refuted"; false; }
}

# A control that could not RUN is a non-verdict, never a pass. Zero swapped rows must not read as
# zero flips — the emptiness-vs-absence split, on the arm where getting it wrong ships a swap list.
@test "bias control: zero swapped pairs is NOT RUN, and says the list is unvalidated" {
  R="$BATS_TEST_TMPDIR/d.jsonl"
  printf '%s\n' '{"id":"r2-1","round":"h2h","block_a":"x.md","block_b":"y.md","winner":"a","swapped":false}' > "$R"
  run env -u AI_GATEWAY_API_KEY "$REPO/bin/cc-jev" promote --report "$R"
  [ "$status" -eq 0 ]
  grep -qF "NOT RUN (0 swapped pairs)" <<<"$output"
  grep -qF "UNVALIDATED on position" <<<"$output"
  ! grep -qF "within the" <<<"$output" || { echo "absent control reported as a pass"; false; }
}

@test "promote --report: needs no key, no route, and no memory dir" {
  R="$BATS_TEST_TMPDIR/e.jsonl"
  printf '%s\n' '{"id":"r2-1","round":"h2h","block_a":"x.md","block_b":"y.md","winner":"a","swapped":false}' > "$R"
  run env -u AI_GATEWAY_API_KEY CC_JEV_BASE_URL="http://127.0.0.1:1" CC_JEV_MEM_DIR=/nonexistent \
      "$REPO/bin/cc-jev" promote --report "$R"
  [ "$status" -eq 0 ]
  grep -qF "No call is made" <<<"$output"
}

# ── the billing-cliff guard ──────────────────────────────────────────────────────────────────
# The free window ends 2026-09-25 and the route does not stop answering then — it becomes METERED.
# Until 2026-09-21 CC_JEV_FREE_UNTIL was read at exactly one line, inside a printf: displayed,
# never enforced.
@test "jev_window_open: open inside the window, refuses past it, and names the override" {
  run bash -c ". '$REPO/hooks/lib/jev.sh'; CC_JEV_FREE_UNTIL=2099-01-01 jev_window_open"
  [ "$status" -eq 0 ]
  run bash -c ". '$REPO/hooks/lib/jev.sh'; CC_JEV_FREE_UNTIL=2020-01-01 jev_window_open"
  [ "$status" -eq 1 ]
  grep -qF "free AI Gateway window closed" <<<"$output"
  grep -qF "CC_JEV_PAID=1" <<<"$output"
  run bash -c ". '$REPO/hooks/lib/jev.sh'; CC_JEV_FREE_UNTIL=2020-01-01 CC_JEV_PAID=1 jev_window_open"
  [ "$status" -eq 0 ]
}

# FAILS CLOSED. The failure being guarded is SPENDING: a wrong refusal costs a re-run, a wrong
# approval costs a bill. An unreadable clock must therefore leave the window shut.
@test "jev_window_open: an unreadable clock fails CLOSED, not open" {
  D="$BATS_TEST_TMPDIR/bin"; mkdir -p "$D"
  printf '#!/bin/sh\nexit 1\n' > "$D/date"; chmod +x "$D/date"
  run bash -c "PATH='$D:/usr/bin:/bin'; . '$REPO/hooks/lib/jev.sh'; jev_window_open"
  [ "$status" -eq 1 ]
  grep -qF "cannot read the clock" <<<"$output"
  grep -qF "Failing closed" <<<"$output"
}

@test "promote: refuses to call at all once the free window has lapsed" {
  mkcorpus
  run runp CC_JEV_ZDR=0 CC_JEV_FREE_UNTIL=2020-01-01 -- --yes
  [ "$status" -eq 4 ]
  grep -qF "free AI Gateway window closed" <<<"$output"
}

# ── the scheduled batch: inert unless a human armed it ───────────────────────────────────────
# A launchd job is NOT bound by the session permission classifier, so a bare timer here would
# convert one typed command into standing unattended egress. These arms pin the three properties
# that stop that: inert by default, consumed BEFORE the call, and expiring on a clock.
@test "batch: unarmed is INERT and exits 0 — the resting state is not an error" {
  run env CC_JEV_ARM_FILE="$BATS_TEST_TMPDIR/none.arm" CC_JEV_BATCH_LOG="$BATS_TEST_TMPDIR/b.log" \
      "$REPO/scripts/jev/jev-batch.sh"
  [ "$status" -eq 0 ]      # NOT 1: a job that fails on its normal state trains everyone to ignore it
  grep -qF "not-armed" "$BATS_TEST_TMPDIR/b.log"
  # and it names how to arm, so the log is actionable rather than merely true
  grep -qF "cc-jev arm" "$BATS_TEST_TMPDIR/b.log"
}

@test "batch: an EXPIRED arm is consumed and makes no call" {
  A="$BATS_TEST_TMPDIR/exp.arm"
  printf '{"created":"2020-01-01T00:00:00Z","expires":"2020-01-02T00:00:00Z","max_calls":10,"cap_b":1200,"corpus":"memory-orphans"}' > "$A"
  run env CC_JEV_ARM_FILE="$A" CC_JEV_BATCH_LOG="$BATS_TEST_TMPDIR/b.log" "$REPO/scripts/jev/jev-batch.sh"
  [ "$status" -eq 0 ]
  [ ! -f "$A" ]                                   # consumed, so no later tick re-reads it
  grep -qF "EXPIRED" "$BATS_TEST_TMPDIR/b.log"
}

# A token that cannot be parsed cannot be honoured — and leaving it on disk would make every
# subsequent tick re-read the same garbage, a permanent alarm nobody can clear.
@test "batch: a MALFORMED arm is refused AND consumed" {
  A="$BATS_TEST_TMPDIR/bad.arm"; printf 'not json at all' > "$A"
  run env CC_JEV_ARM_FILE="$A" CC_JEV_BATCH_LOG="$BATS_TEST_TMPDIR/b.log" "$REPO/scripts/jev/jev-batch.sh"
  [ "$status" -eq 0 ]
  [ ! -f "$A" ]
  grep -qF "malformed" "$BATS_TEST_TMPDIR/b.log"
}

@test "arm: --status and --revoke, and arming records the terms it consents to" {
  A="$BATS_TEST_TMPDIR/a.arm"
  run env CC_JEV_ARM_FILE="$A" "$REPO/bin/cc-jev" arm --status
  [ "$status" -eq 0 ]; grep -qF "not armed" <<<"$output"
  run env CC_JEV_ARM_FILE="$A" "$REPO/bin/cc-jev" arm --calls 30 --ttl 60
  [ "$status" -eq 0 ]
  [ "$(jq -r '.max_calls' "$A")" = "30" ]
  [ -n "$(jq -r '.expires' "$A")" ]
  [ "$(jq -r '.corpus' "$A")" = "memory-orphans" ]
  grep -qF "never the mailbox" <<<"$output"       # the terms are shown to the human, not just stored
  run env CC_JEV_ARM_FILE="$A" "$REPO/bin/cc-jev" arm --revoke
  [ "$status" -eq 0 ]; [ ! -f "$A" ]
}

@test "arm: refuses to arm once the free window has lapsed" {
  A="$BATS_TEST_TMPDIR/a2.arm"
  run env CC_JEV_ARM_FILE="$A" CC_JEV_FREE_UNTIL=2020-01-01 "$REPO/bin/cc-jev" arm
  [ "$status" -eq 4 ]
  [ ! -f "$A" ]
  grep -qF "free AI Gateway window closed" <<<"$output"
}

@test "plist: ships UNLOADED semantics and names a path that install.sh actually deploys" {
  P="$REPO/launchd/com.claude.jev-batch.plist"
  run plutil -lint "$P"
  [ "$status" -eq 0 ]
  # Both paths are in fact deployed (install.sh:759 has a dedicated scripts/jev/ block), so this
  # is not a reachability assertion — it pins the SINGLE ENTRY POINT, so adding a subcommand never
  # requires editing this plist again.
  # Scope to what launchd EXECUTES. A whole-file grep also reads the comment that EXPLAINS the
  # undeployed path, so it convicts the documentation for describing the trap it avoids — the
  # assertion has to span exactly its subject.
  EXEC="$(plutil -extract ProgramArguments json -o - "$P")"
  grep -qF 'cc-jev' <<<"$EXEC"
  ! grep -qF '.claude/scripts/jev/' <<<"$EXEC" || { echo "plist EXECUTES an undeployed path"; false; }
  grep -qF 'launchctl bootout' "$P"          # the kill switch is written down beside the job
}

# 🚨 AN ARMING IS A SCARCE HUMAN ACT AND MUST NOT BE SPENT ON A LOCAL PRECONDITION.
# consume-before-call is about CALLS: once bytes have left, the authorisation must already be
# gone so a crash cannot leave a live one behind. It is NOT a reason to burn the token on a check
# that makes no call. Measured 2026-09-21: the first version consumed first and then exited 2 at
# jev_available because no key was present — window gone, nothing sent, log reading `run rc=2`
# over an empty rows file.
@test "batch: a missing key PRESERVES the arm — nothing was sent, so nothing was spent" {
  A="$BATS_TEST_TMPDIR/k.arm"
  EXP="$(date -u -v+30M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '+30 minutes' +%Y-%m-%dT%H:%M:%SZ)"
  jq -n --arg e "$EXP" '{created:"x", expires:$e, max_calls:12, cap_b:1200, corpus:"memory-orphans"}' > "$A"
  run env -u AI_GATEWAY_API_KEY CC_JEV_ARM_FILE="$A" CC_JEV_BATCH_LOG="$BATS_TEST_TMPDIR/b.log" \
      "$REPO/scripts/jev/jev-batch.sh"
  [ "$status" -eq 0 ]
  [ -f "$A" ]                                       # THE POINT: still armed
  grep -qF "arm PRESERVED" "$BATS_TEST_TMPDIR/b.log"
}

@test "batch: a lapsed free window PRESERVES the arm too, and says so" {
  A="$BATS_TEST_TMPDIR/w.arm"
  EXP="$(date -u -v+30M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '+30 minutes' +%Y-%m-%dT%H:%M:%SZ)"
  jq -n --arg e "$EXP" '{created:"x", expires:$e, max_calls:12, cap_b:1200, corpus:"memory-orphans"}' > "$A"
  run env AI_GATEWAY_API_KEY=dummy CC_JEV_FREE_UNTIL=2020-01-01 CC_JEV_ARM_FILE="$A" \
      CC_JEV_BATCH_LOG="$BATS_TEST_TMPDIR/b.log" "$REPO/scripts/jev/jev-batch.sh"
  [ "$status" -eq 0 ]
  [ -f "$A" ]
  grep -qF "free window has lapsed" "$BATS_TEST_TMPDIR/b.log"
}

# The whole path, as launchd invokes it: armed token in, rows out, token gone.
@test "batch: an ARMED run produces rows and consumes the token" {
  mkcorpus
  A="$BATS_TEST_TMPDIR/go.arm"
  EXP="$(date -u -v+30M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '+30 minutes' +%Y-%m-%dT%H:%M:%SZ)"
  jq -n --arg e "$EXP" '{created:"x", expires:$e, max_calls:9, cap_b:400, corpus:"memory-orphans"}' > "$A"
  export MOCK_CHOICE_ROTATE=1
  start_mock ok
  run env AI_GATEWAY_API_KEY=dummy CC_JEV_BASE_URL="http://127.0.0.1:$PORT" \
      CC_JEV_ARM_FILE="$A" CC_JEV_BATCH_LOG="$BATS_TEST_TMPDIR/b.log" \
      CC_JEV_MEM_DIR="$MEMD" CC_JEV_RULES_FILE=/dev/null CC_JEV_RANK_ROWS="$RANKF" \
      CC_JEV_PROMO_GAP=0 "$REPO/scripts/jev/jev-batch.sh"
  [ "$status" -eq 0 ]
  [ ! -f "$A" ]                                     # consumed
  grep -qF "run rc=0" "$BATS_TEST_TMPDIR/b.log"
  ROWS="$(grep -o '/.*jev-promote-.*\.jsonl' "$BATS_TEST_TMPDIR/b.log" | tail -1)"
  [ -s "$ROWS" ]                                    # and it actually decided something
  [ "$(jq -r '.round' "$ROWS" | sort -u | head -1)" = "h2h" ]
}
