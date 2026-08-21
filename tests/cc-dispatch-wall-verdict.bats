#!/usr/bin/env bats
# cc-dispatch — the CONSUMER half of cc-wave-plan's wall verdict (backlog 63c8215eacdc, F1 in
# docs/plans/CLOUD_BACKLOG_PIPELINE.md § A1).
#
# WHAT THIS SUITE EXISTS TO PROVE. cc-wave-plan became four-valued at S3 — capped(4) capacity(4)
# auth(5) unknown(6), each with its own operator action — and tests/cc-wave-plan-verdict.bats pins
# all four with 25 discriminating tests. cc-dispatch is its ONLY executable consumer, and it read
# the EXIT CODE alone: every 4 became "⛔ QUOTA CLIFF … run /limit-recover", and 5/6 fell into the
# fail-closed die3 default. A distinction that is produced, tested and landed but destroyed at its
# one consumer is not a distinction at all. Both halves are MEASURED, not argued:
#
#   · capacity → ~/.claude/autonomy/idl.jsonl:77973, the one quota-cliff record on this box, carries
#     reason:"wave-overflow" action:"reduce-wave-size" with four accounts at 1-8% of their 5-hour
#     window. The operator was paged to run /limit-recover over a nearly-empty fleet.
#   · unknown → docs/research/usage-telemetry-100p-2026-08-16/utilization.md F13: the live dispatcher
#     exited 3 on `wave-plan returned non-cliff rc=6 — refusing to fire blind`, launchctl
#     LastExitStatus 768, with `failed` per day at 7 · 20 · 16 · 16 · 96 · 136 over 08-11..08-16.
#
# THE SPINE IS PAIRS, like the producer suite: rc 4 alone CANNOT separate capped from capacity, so
# every claim here is two runs of one harness differing only in the WALL[] token on the producer's
# stderr. A single-sided assertion would pass against a consumer that always said the same thing —
# which is precisely the defect.
#
# RED-PROOF. Each test below names its verdict on the pristine pre-change binary, recovered with
#   git archive origin/main bin/cc-dispatch | tar -x -C <tmpdir>
# and run through the CC_DISPATCH_UNDER_TEST seam (kept so the proof is re-runnable, not a claim).
# Three cases are BY DESIGN GREEN ON BOTH ARMS and say so in their names: they pin behaviour this
# change had to LEAVE ALONE (the capped path, the unlabelled-rc fallback, the fail-closed default
# for an rc outside the contract). A change that narrows a guard must prove the guard still bites.

setup() {
  export CC_BACKLOG_PROJECT_WARN=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  DISP="${CC_DISPATCH_UNDER_TEST:-$REPO/bin/cc-dispatch}"
  BACKLOG="$REPO/bin/cc-backlog"
  C="$BATS_TEST_TMPDIR/case"
  mkdir -p "$C/pages" "$C/stubs"
  # HERMETIC: $HOME is fixtured, so nothing here can read or write the operator's live ~/.claude —
  # cc-dispatch's spawn default is $HOME/.claude/scripts/handoff-fire.sh and several of its seams
  # fall back under $HOME. Required by scripts/test-hermeticity-lint.sh for every NEW suite.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude"
  # Same three pins as tests/cc-dispatch.bats: the capacity gate (this box lives above 2.0/core, so
  # unpinned the fire assertions go red BY LOAD), and all three dispatch_kick seams (an unfixtured
  # `cc-backlog add` backgrounds a SECOND dispatcher that races this test's own pass for the
  # singleton — a real post-land red, stamped four times in postland/flakes.jsonl).
  export CC_FIRE_CAPACITY_GATE=off
  export CC_BACKLOG_KICK=off
  export CC_BACKLOG_KICK_MARKER="$BATS_TEST_TMPDIR/.dispatch-kick"
  export CC_BACKLOG_KICK_BIN="$BATS_TEST_TMPDIR/no-such-dispatch"

  # wave-plan stub. PER-CALL rc and stderr (line N of each file governs call N, last line repeats),
  # because the capacity arm's whole point is that a SECOND call happens with a smaller wave. The
  # wave width of every call is recorded so the re-plan is observable rather than inferred.
  cat > "$C/stubs/waveplan" <<'EOF'
#!/bin/bash
items=""
while [ $# -gt 0 ]; do case "$1" in --items) items="$2"; shift 2 ;; *) shift ;; esac; done
n=$(( $(cat "$WP_CALLS" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$WP_CALLS"
printf '%s' "$items" | jq 'length' >> "$WP_WAVES"
rc="$(sed -n "${n}p" "$WP_RC_FILE" 2>/dev/null)";  [ -n "$rc" ]  || rc="$(tail -1 "$WP_RC_FILE" 2>/dev/null || echo 0)"
err="$(sed -n "${n}p" "$WP_ERR_FILE" 2>/dev/null)"; [ -n "$err" ] || err="$(tail -1 "$WP_ERR_FILE" 2>/dev/null || true)"
[ -n "$err" ] && printf '%s\n' "$err" >&2
[ "$rc" = 0 ] || exit "$rc"
printf '%s' "$items" \
  | jq -c '[ .[] | {id, account:"next3", fire_line:["--prompt-file","/tmp/fire.txt","--account","next3"]} ]'
EOF
  cat > "$C/stubs/spawn" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$SPAWN_LOG"
exit 0
EOF
  # MUST be stubbed: unstubbed, cc-dispatch resolves the operator's REAL claude-accounts and
  # free_slots would be computed from the live fleet, so every assertion below would invert whenever
  # the desk happens to hold >= CEILING sessions.
  cat > "$C/stubs/accounts" <<'EOF'
#!/bin/bash
printf '{"rows":[{"acct":"a","k":0}]}\n'
EOF
  chmod +x "$C/stubs/waveplan" "$C/stubs/spawn" "$C/stubs/accounts"

  : > "$C/wp_rc"; : > "$C/wp_err"; : > "$C/wp_waves"; echo 0 > "$C/wp_calls"
  export WP_RC_FILE="$C/wp_rc" WP_ERR_FILE="$C/wp_err" \
         WP_CALLS="$C/wp_calls" WP_WAVES="$C/wp_waves" SPAWN_LOG="$C/spawn.log"
  export CC_BACKLOG_FILE="$C/backlog.jsonl"
  export CC_DISPATCH_BACKLOG_BIN="$BACKLOG" \
         CC_DISPATCH_WAVEPLAN_BIN="$C/stubs/waveplan" \
         CC_DISPATCH_SPAWN_BIN="$C/stubs/spawn" \
         CC_DISPATCH_ACCOUNTS_BIN="$C/stubs/accounts" \
         CC_DISPATCH_PAGES_DIR="$C/pages" \
         CC_DISPATCH_IDL="$C/idl.jsonl" \
         CC_DISPATCH_PROJECT="/repo/proj" \
         CC_DISPATCH_MAX_SPAWN=2 \
         CC_DISPATCH_CEILING=6 \
         CC_DISPATCH_SID="bats"
}

add_item() { "$BACKLOG" add --title "$1" --project proj --source bats; }

# The producer's REAL stderr shapes (fixture-shape parity with bin/cc-wave-plan's wall_emit case
# block — a convenient approximation here would prove nothing about the real pair).
wall_capacity_line() { printf 'cc-wave-plan: ⛔ WALL[capacity] — wave of %s items exceeds capacity (1 accounts, %s slot(s) total — every ranked account is at its per-wave cap). STOP: plan a smaller wave — the accounts have headroom, this is wave sizing. capacity=%s. No plan emitted.' "$1" "$2" "$2"; }
wall_capped_line()   { printf 'cc-wave-plan: ⛔ WALL[capped] — no account has general headroom (rank empty). STOP: run /limit-recover (disk-truth audit, re-run or transplant). No plan emitted.'; }
wall_auth_line()     { printf 'cc-wave-plan: ⛔ WALL[auth] — every account is logged out (rank rc=3). STOP: run /relogin. This is an AUTH wall, not a quota wall.'; }
wall_unknown_line()  { printf 'cc-wave-plan: ⚠️  WALL[unknown] — claude-accounts --rank exceeded the 20s bound. NOT a wall and NOT a page: the oracle gave no answer. Retry next pass. No plan emitted.'; }

pagefile()   { local f; for f in "$C/pages"/*.page; do [ -e "$f" ] || continue; printf '%s' "$f"; return 0; done; return 1; }
has_page()   { [ -n "$(pagefile)" ]; }
n_pages()    { find "$C/pages" -type f -name '*.page' 2>/dev/null | wc -l | tr -d ' '; }
idl_has()    { grep -q "\"action\":\"$1\"" "$C/idl.jsonl"; }
calls()      { cat "$C/wp_calls" 2>/dev/null || echo 0; }

# ── PAIR 1: rc 4 is TWO states. The whole defect in two runs. ─────────────────────────────────────

@test "PAIR 1a: rc 4 + WALL[capacity] → deferred, NO page, NO abstention (RED pre-fix: paged a cliff)" {
  add_item cap >/dev/null
  printf '4\n' > "$C/wp_rc"; wall_capacity_line 6 0 > "$C/wp_err"
  run "$DISP" --once
  [ "$status" -eq 0 ]
  # ` || false` on every non-final negation: under bats' errexit a bare `! cmd` mid-test can only
  # ever pass, so it asserts nothing (memory: negated-assertion-dead-unless-final). Caught here by
  # scripts/bats-assert-liveness.py, which flagged five of them in this file's first draft.
  ! has_page || false
  ! idl_has abstained || false
  [ ! -s "$C/spawn.log" ]
  printf '%s' "$output" | grep -q 'NOT a quota cliff'
}

@test "PAIR 1b: the SAME rc 4 with WALL[capped] DOES page and abstain (by design green on both arms — the capped path is unchanged)" {
  add_item capped >/dev/null
  printf '4\n' > "$C/wp_rc"; wall_capped_line > "$C/wp_err"
  run "$DISP" --once
  [ "$status" -eq 0 ]
  has_page
  idl_has abstained
  [ ! -s "$C/spawn.log" ]
}

@test "PAIR 1c: capacity and capped differ ONLY in the WALL token, and produce different pages — so the rc cannot be the discriminator" {
  add_item a >/dev/null
  printf '4\n' > "$C/wp_rc"; wall_capacity_line 6 0 > "$C/wp_err"
  run "$DISP" --once
  [ "$status" -eq 0 ]
  local after_capacity; after_capacity="$(n_pages)"
  wall_capped_line > "$C/wp_err"
  run "$DISP" --once
  [ "$status" -eq 0 ]
  local after_capped; after_capped="$(n_pages)"
  [ "$after_capacity" -eq 0 ]
  [ "$after_capped" -ge 1 ]
}

# ── PAIR 2: the non-verdict that killed the live dispatcher (F13) ────────────────────────────────

@test "PAIR 2a: rc 6 WALL[unknown] → exit 0, deferred, NO page, NO 'failed' record (RED pre-fix: exit 3, the measured LastExitStatus 768)" {
  add_item unk >/dev/null
  printf '6\n' > "$C/wp_rc"; wall_unknown_line > "$C/wp_err"
  run "$DISP" --once
  [ "$status" -eq 0 ]
  ! has_page || false
  ! idl_has failed || false
  [ ! -s "$C/spawn.log" ]
}

@test "PAIR 2b: an rc OUTSIDE the four defined verdicts still fails closed and LOUD (by design green on both arms — the guard was narrowed, not removed)" {
  add_item weird >/dev/null
  printf '7\n' > "$C/wp_rc"; : > "$C/wp_err"
  run "$DISP" --once
  [ "$status" -eq 3 ]
  [ ! -s "$C/spawn.log" ]
}

# ── PAIR 3: an auth wall names /relogin, and only an auth wall does ──────────────────────────────

@test "PAIR 3a: rc 5 WALL[auth] → exit 0, pages /relogin and NEVER /limit-recover (RED pre-fix: exit 3, no page at all)" {
  add_item auth >/dev/null
  printf '5\n' > "$C/wp_rc"; wall_auth_line > "$C/wp_err"
  run "$DISP" --once
  [ "$status" -eq 0 ]
  has_page
  grep -q 'relogin' "$(pagefile)"
  ! grep -q 'limit-recover' "$(pagefile)" || false
  [ ! -s "$C/spawn.log" ]
}

@test "PAIR 3b: positive control — the capped page DOES name /limit-recover and never /relogin" {
  add_item capped >/dev/null
  printf '4\n' > "$C/wp_rc"; wall_capped_line > "$C/wp_err"
  run "$DISP" --once
  [ "$status" -eq 0 ]
  has_page
  grep -q 'headroom' "$(pagefile)"
  ! grep -q 'relogin' "$(pagefile)"
}

# ── PAIR 4: `reduce-wave-size` is an ACTION, and something now performs it ───────────────────────

@test "PAIR 4a: WALL[capacity] with capacity=1 RE-PLANS at 1 item and fires (RED pre-fix: abstained, zero spawn, forever)" {
  add_item one >/dev/null; add_item two >/dev/null
  printf '4\n0\n' > "$C/wp_rc"                       # call 1 walls, call 2 (the smaller wave) places
  { wall_capacity_line 2 1; printf '\n'; } > "$C/wp_err"
  run "$DISP" --once
  [ "$status" -eq 0 ]
  [ "$(calls)" -eq 2 ]
  # the SECOND wave is the reduced one — the observable the pre-fix path can never produce
  [ "$(sed -n '2p' "$C/wp_waves")" -eq 1 ]
  [ -s "$C/spawn.log" ]
  ! has_page
}

@test "PAIR 4b: the re-plan happens AT MOST ONCE — a second capacity wall is taken at face value, never looped" {
  add_item one >/dev/null; add_item two >/dev/null
  printf '4\n4\n' > "$C/wp_rc"                       # both calls wall
  { wall_capacity_line 2 1; wall_capacity_line 1 1; } > "$C/wp_err"
  run "$DISP" --once
  [ "$status" -eq 0 ]
  [ "$(calls)" -eq 2 ]
  [ ! -s "$C/spawn.log" ]
  ! has_page
}

@test "PAIR 4c: capacity=0 (no usable bound on the wire) defers without re-planning — never a wave of zero" {
  add_item one >/dev/null; add_item two >/dev/null
  printf '4\n' > "$C/wp_rc"; wall_capacity_line 2 0 > "$C/wp_err"
  run "$DISP" --once
  [ "$status" -eq 0 ]
  [ "$(calls)" -eq 1 ]
  [ ! -s "$C/spawn.log" ]
  ! has_page
}

# ── The fallback, and the parity that keeps this fixture honest ──────────────────────────────────

@test "fallback: a bare rc 4 with NO WALL token still reads as capped (by design green on both arms — lane v1 and a failed capture must not change behaviour)" {
  add_item v1 >/dev/null
  printf '4\n' > "$C/wp_rc"; : > "$C/wp_err"        # lane v1 emits no WALL[] token at all
  run "$DISP" --once
  [ "$status" -eq 0 ]
  has_page
  idl_has abstained
}

@test "LC_ALL=C: the WALL token parses byte-wise too — the producer's line is emoji-prefixed" {
  add_item locale >/dev/null
  printf '4\n' > "$C/wp_rc"; wall_capacity_line 6 0 > "$C/wp_err"
  LC_ALL=C run "$DISP" --once
  [ "$status" -eq 0 ]
  ! has_page                                         # still read as capacity, not capped
}

@test "parity: the producer EMITS the two tokens this consumer parses (neither side may drift alone)" {
  grep -q 'WALL\[capacity\]' "$REPO/bin/cc-wave-plan"
  grep -q 'capacity=\${WALL_CAPACITY_N' "$REPO/bin/cc-wave-plan"
  grep -q 'WALL\\\[' "$REPO/bin/cc-dispatch"
  grep -q 'capacity=' "$REPO/bin/cc-dispatch"
}
