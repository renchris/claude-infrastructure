#!/usr/bin/env bats
# activation-watch (SessionStart) — the absence-is-loud re-page for the C10 activation queue (D-v).
# The tool's --selftest RED-proves the age/done/absent logic; these bats add independent CLI-level
# coverage via CC_ACTIVATION_DIR fixtures + the SessionStart additionalContext JSON contract.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  H="$REPO/hooks/activation-watch.sh"
  Q="$BATS_TEST_TMPDIR/queue"
  mkdir -p "$Q"
  OLD="$(date -v-25H +%Y%m%d%H%M.%S 2>/dev/null || echo 200001010000.00)"
  # Axis-2 isolation: mirror := the queue itself ⇒ trivially in parity, so the axis-1 tests measure
  # staleness alone. Without it they read the REAL repo mirror and every fixture (absent from it) is
  # correctly reported LIVE-ONLY — drift noise, not an axis-1 failure. Parity tests override this.
  export CC_ACTIVATION_MIRROR_DIR="$Q"
}
stage() { printf '#!/bin/bash\n' > "$Q/$1"; [ -n "${2:-}" ] && touch -t "$2" "$Q/$1"; return 0; }

@test "selftest passes and runs all 18 checks (a zero-check suite must not 'pass')" {
  run "$H" --selftest
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | grep -c '^  ok ')" -eq 18 ]
  ! printf '%s' "$output" | grep -q '^  FAIL'
}

@test "stale (>24h) un-run activation → named in the additionalContext" {
  stage "p0-14-activate.sh" "$OLD"
  CC_ACTIVATION_DIR="$Q" run "$H"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'p0-14-activate.sh'
  printf '%s' "$output" | grep -q 'ACTIVATION QUEUE'
}

@test "output is valid SessionStart additionalContext JSON" {
  stage "x-activate.sh" "$OLD"
  CC_ACTIVATION_DIR="$Q" run "$H"
  printf '%s' "$output" | jq -e '.hookSpecificOutput.hookEventName == "SessionStart"' >/dev/null
  printf '%s' "$output" | jq -e '.hookSpecificOutput.additionalContext | test("x-activate.sh")' >/dev/null
}

@test "fresh (<24h) un-run activation → named under the FRESH partition, not the rotting one" {
  # CHANGED 2026-07-29 (row 10, §4 F7) — this test PINNED THE DEFECT AS CORRECT. The >24h gate hid
  # the newest half of the queue, which is exactly what a just-finished rebuild stages; measured 13
  # pending / 6 named, with the campaign's own top-lever activations in the invisible half. The claim
  # that survives is the one that was actually worth having: a fresh entry must not be reported as
  # ROTTING. Kill switch coverage is the M3 case below.
  stage "fresh-activate.sh"
  CC_ACTIVATION_DIR="$Q" run "$H"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'fresh-activate.sh'
  printf '%s' "$output" | grep -q 'FRESH'
  ! printf '%s' "$output" | grep -q 'ROTTING' || false
}

@test ".done-marked stale activation → NOT named" {
  stage "ran-activate.sh" "$OLD"
  : > "$Q/ran-activate.sh.done"
  CC_ACTIVATION_DIR="$Q" run "$H"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "absent queue dir → silent, exit 0 (fail-open)" {
  CC_ACTIVATION_DIR="$BATS_TEST_TMPDIR/nope" run "$H"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "mixed queue: stale and fresh are each named under their OWN partition; .done is not" {
  # CHANGED with the case above, same reason. `.done` exclusion is the assertion that mattered and it
  # is unchanged — that is the marker convention, not the age filter.
  stage "stale-a.sh" "$OLD"
  stage "fresh-b.sh"
  stage "done-c.sh" "$OLD"; : > "$Q/done-c.sh.done"
  CC_ACTIVATION_DIR="$Q" run "$H"
  printf '%s' "$output" | grep -q '2 pending-activation script(s) NOT run'
  printf '%s' "$output" | grep -q 'ROTTING (>24h, 1): stale-a.sh'
  printf '%s' "$output" | grep -q 'FRESH (<24h, 1)'
  printf '%s' "$output" | grep -q 'fresh-b.sh'
  ! printf '%s' "$output" | grep -q 'done-c.sh'
}

# ══════════════ axis 2 — SSOT parity: live queue vs the repo mirror ══════════════════════════
# Fixtures are `.done`-MARKED throughout, so axis 1 stays silent and every finding below is
# attributable to the parity axis alone. Marked, not merely fresh: since M3 axis 1 partitions rather
# than filters, freshness no longer buys silence — and borrowing another axis's quiet was never
# isolation, it was a coincidence that happened to hold.

@test "LIVE-ONLY: staged live but never committed → named (the unrecoverable class)" {
  M="$BATS_TEST_TMPDIR/mirror"; mkdir -p "$M"
  stage "12-only-live-activate.sh"
  CC_ACTIVATION_DIR="$Q" CC_ACTIVATION_MIRROR_DIR="$M" run "$H"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q '12-only-live-activate.sh'
  printf '%s' "$output" | grep -q 'LIVE-ONLY'
}

@test "REPO-ONLY: committed but never deployed → named (axis 1 is structurally blind to it)" {
  M="$BATS_TEST_TMPDIR/mirror"; mkdir -p "$M"
  printf '#!/bin/bash\n' > "$M/09-only-repo-activate.sh"
  CC_ACTIVATION_DIR="$Q" CC_ACTIVATION_MIRROR_DIR="$M" run "$H"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q '09-only-repo-activate.sh'
  printf '%s' "$output" | grep -q 'REPO-ONLY'
}

@test "CONTENT-DRIFT: same name, diverged bytes → named (the deploy-lag class)" {
  M="$BATS_TEST_TMPDIR/mirror"; mkdir -p "$M"
  printf '#!/bin/bash\n# LIVE\n' > "$Q/07-drift-activate.sh"
  printf '#!/bin/bash\n# REPO\n' > "$M/07-drift-activate.sh"
  CC_ACTIVATION_DIR="$Q" CC_ACTIVATION_MIRROR_DIR="$M" run "$H"
  printf '%s' "$output" | grep -q '07-drift-activate.sh'
  printf '%s' "$output" | grep -q 'CONTENT-DRIFT'
}

@test "a .local marker exempts an intentionally live-only script" {
  M="$BATS_TEST_TMPDIR/mirror"; mkdir -p "$M"
  stage "secret-activate.sh"; : > "$Q/secret-activate.sh.local"; : > "$Q/secret-activate.sh.done"
  CC_ACTIVATION_DIR="$Q" CC_ACTIVATION_MIRROR_DIR="$M" run "$H"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "in-parity copies → silent (positive control: the firing path must also go quiet)" {
  M="$BATS_TEST_TMPDIR/mirror"; mkdir -p "$M"
  stage "01-agreed-activate.sh"; : > "$Q/01-agreed-activate.sh.done"
  cp "$Q/01-agreed-activate.sh" "$M/"
  CC_ACTIVATION_DIR="$Q" CC_ACTIVATION_MIRROR_DIR="$M" run "$H"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "an unresolvable mirror is REPORTED, never a silent vacuous pass" {
  stage "x-activate.sh"
  CC_ACTIVATION_DIR="$Q" CC_ACTIVATION_MIRROR_DIR="$BATS_TEST_TMPDIR/nope" \
    CC_ACTIVATION_REPO="$BATS_TEST_TMPDIR/nope" run "$H"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'DID NOT RUN'
}

@test "invoked through a SYMLINK the mirror resolves to the CHECKOUT, never ~/.claude (816015ecb30b)" {
  # The live wiring is ~/.claude/hooks/activation-watch.sh → a symlink into the checkout. An
  # underefed BASH_SOURCE yields REPO=~/.claude, where docs/activation/ does not exist, and the
  # whole axis passes vacuously — exactly how the sibling deploy-parity assert stayed silent.
  ln -s "$H" "$BATS_TEST_TMPDIR/linked.sh"
  unset CC_ACTIVATION_MIRROR_DIR          # force the deref + .git-gate path under test
  CC_ACTIVATION_DIR="$Q" run "$BATS_TEST_TMPDIR/linked.sh" --parity
  # resolves to THIS checkout — not ~/.claude, and not the FALLBACK_REPO shared checkout
  printf '%s' "$output" | grep -q "$REPO/docs/activation/pending-activation"
  ! printf '%s' "$output" | grep -q '\.claude/docs/activation'
}

@test "--parity: rc 1 + named drift, rc 0 + GREEN once the copies agree" {
  M="$BATS_TEST_TMPDIR/mirror"; mkdir -p "$M"
  stage "only-live.sh"
  CC_ACTIVATION_DIR="$Q" CC_ACTIVATION_MIRROR_DIR="$M" run "$H" --parity
  [ "$status" -eq 1 ]
  printf '%s' "$output" | grep -q 'only-live.sh'
  cp "$Q/only-live.sh" "$M/"
  CC_ACTIVATION_DIR="$Q" CC_ACTIVATION_MIRROR_DIR="$M" run "$H" --parity
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'GREEN'
}

@test "both axes compose into ONE valid SessionStart emit" {
  M="$BATS_TEST_TMPDIR/mirror"; mkdir -p "$M"
  stage "stale-and-uncommitted-activate.sh" "$OLD"      # stale (axis 1) AND live-only (axis 2)
  CC_ACTIVATION_DIR="$Q" CC_ACTIVATION_MIRROR_DIR="$M" run "$H"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.hookSpecificOutput.hookEventName == "SessionStart"' >/dev/null
  printf '%s' "$output" | jq -e '.hookSpecificOutput.additionalContext | test("ACTIVATION QUEUE")' >/dev/null
  printf '%s' "$output" | jq -e '.hookSpecificOutput.additionalContext | test("ACTIVATION SSOT PARITY")' >/dev/null
}

# ══════════════════════════════════════════════════════════════════════════════════════════════════
# M3 · axis 1 PARTITIONS instead of FILTERING (OPERATOR_SURFACE_V2 §4 F7)
#
# Measured 2026-07-29: 13 pending activations, 6 named. The >24h gate hid the newest half — exactly
# the ones the campaign's own just-finished rebuilds had staged (18-fleet: 12 dark launchd labels;
# 16-session-beat; 17-qos-chokepoint) — so the operator read "6 pending" and believed that was the
# queue. Same law as the class budget: a surface may de-emphasise a class, never delete it.
# ══════════════════════════════════════════════════════════════════════════════════════════════════

@test "M3: the headline COUNT is the whole queue, and fresh entries get their own partition" {
  stage "a-old-activate.sh" "$OLD"
  stage "b-new-activate.sh"
  CC_ACTIVATION_DIR="$Q" run "$H"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q '2 pending-activation script(s) NOT run'
  printf '%s' "$output" | grep -q 'ROTTING'
  printf '%s' "$output" | grep -q 'FRESH'
  printf '%s' "$output" | grep -q 'b-new-activate.sh'
}

@test "M3 POSITIVE CONTROL: a fully .done queue is still SILENT (partitioning is not paging always)" {
  # Without this, a partition that names everything unconditionally would pass the test above while
  # paging on a queue with nothing pending — turning a starvation defect into alarm fatigue.
  stage "c-done-activate.sh" "$OLD"; : > "$Q/c-done-activate.sh.done"
  CC_ACTIVATION_DIR="$Q" run "$H"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "M3 kill switch: CC_ACTIVATION_AGE_FILTER=on restores the >24h filter exactly" {
  stage "a-old-activate.sh" "$OLD"
  stage "b-new-activate.sh"
  CC_ACTIVATION_DIR="$Q" CC_ACTIVATION_AGE_FILTER=on run "$H"
  printf '%s' "$output" | grep -q 'staged >24h and NOT run'
  ! printf '%s' "$output" | grep -q 'b-new-activate.sh' || false
}

# ══════════════════════════════════════════════════════════════════════════════════════════════════
# M4 · LIVE-ONLY adjudicated against TRUNK, not the working tree (§4 F8)
#
# resolve_mirror() dereferences to the SHARED CHECKOUT, so parity is live-vs-checkout. While that
# checkout trails origin/main, a file that IS committed reads "never committed, one `rm` from
# unrecoverable" and the platter says `cp live -> repo` — recreating a committed file as a local diff
# the next fast-forward must conflict on. Deploy lag wearing a parity costume, in the damaging
# direction. Latent on 2026-07-29 (all four live drifts were real); fixed before it fired.
# ══════════════════════════════════════════════════════════════════════════════════════════════════

mkmirror() { # → a checkout whose docs/activation/pending-activation is the repo-side mirror
  local o="$BATS_TEST_TMPDIR/o-$1.git" w="$BATS_TEST_TMPDIR/w-$1"
  git init -q --bare "$o"; git clone -q "$o" "$w" 2>/dev/null
  ( cd "$w" || exit 1; git config user.email t@e.com; git config user.name t; git checkout -q -b main
    mkdir -p docs/activation/pending-activation
    printf '#!/bin/bash\n# committed\n' > docs/activation/pending-activation/landed-activate.sh
    git add -A; git commit -q -m base; git push -q -u origin main ) >/dev/null 2>&1
  printf '%s' "$w"
}

@test "M4: a live file that EXISTS on trunk is UNDEPLOYED-MIRROR, never 'never committed'" {
  w="$(mkmirror m4a)"
  # the checkout is BEHIND trunk for this path — the deploy-lag shape
  ( cd "$w"; git rm -q docs/activation/pending-activation/landed-activate.sh; git commit -q -m drop
    git reset -q --hard HEAD~1; git rm -q --cached docs/activation/pending-activation/landed-activate.sh
    rm -f docs/activation/pending-activation/landed-activate.sh; git commit -q -m "checkout behind" ) >/dev/null 2>&1
  printf '#!/bin/bash\n# committed\n' > "$Q/landed-activate.sh"; : > "$Q/landed-activate.sh.done"
  CC_ACTIVATION_DIR="$Q" CC_ACTIVATION_MIRROR_DIR="$w/docs/activation/pending-activation" run "$H"
  printf '%s' "$output" | grep -q 'UNDEPLOYED-MIRROR'
  printf '%s' "$output" | grep -q 'landed-activate.sh'
  ! printf '%s' "$output" | grep -q "LIVE-ONLY — never committed, one .rm. from unrecoverable: landed-activate.sh" || false
  # …and it must NOT tell the operator to cp a committed file back into the repo
  printf '%s' "$output" | grep -q 'do NOT cp live->repo'
}

@test "M4 POSITIVE CONTROL: a file genuinely absent from trunk is still LIVE-ONLY" {
  # The negative is not data without this: an adjudicator that answered "on trunk" unconditionally
  # would pass the case above while permanently deleting the unrecoverable-file alarm.
  w="$(mkmirror m4b)"
  printf '#!/bin/bash\n' > "$Q/never-committed-activate.sh"; : > "$Q/never-committed-activate.sh.done"
  CC_ACTIVATION_DIR="$Q" CC_ACTIVATION_MIRROR_DIR="$w/docs/activation/pending-activation" run "$H"
  printf '%s' "$output" | grep -q 'LIVE-ONLY'
  printf '%s' "$output" | grep -q 'never-committed-activate.sh'
  ! printf '%s' "$output" | grep -q 'UNDEPLOYED-MIRROR' || false
}

@test "M4: an UNREADABLE trunk yields an UNCONFIRMED verdict, still reported (never a silent pass)" {
  # I7 — an unrunnable check is a finding. A non-checkout mirror has no trunk ref to adjudicate
  # against, and guessing either way is wrong: guess 'on trunk' and the unrecoverable alarm dies,
  # guess 'absent' and the board tells the operator to cp a committed file.
  mkdir -p "$BATS_TEST_TMPDIR/bare-mirror"
  printf '#!/bin/bash\n' > "$Q/orphan-activate.sh"; : > "$Q/orphan-activate.sh.done"
  CC_ACTIVATION_DIR="$Q" CC_ACTIVATION_MIRROR_DIR="$BATS_TEST_TMPDIR/bare-mirror" run "$H"
  printf '%s' "$output" | grep -q 'UNCONFIRMED'
}

@test "M4 kill switch: CC_ACTIVATION_TRUNK_ADJUDICATE=off restores the working-tree verdict" {
  w="$(mkmirror m4c)"
  ( cd "$w"; git rm -q --cached docs/activation/pending-activation/landed-activate.sh
    rm -f docs/activation/pending-activation/landed-activate.sh; git commit -q -m "checkout behind" ) >/dev/null 2>&1
  printf '#!/bin/bash\n# committed\n' > "$Q/landed-activate.sh"; : > "$Q/landed-activate.sh.done"
  CC_ACTIVATION_DIR="$Q" CC_ACTIVATION_MIRROR_DIR="$w/docs/activation/pending-activation" \
    CC_ACTIVATION_TRUNK_ADJUDICATE=off run "$H"
  printf '%s' "$output" | grep -q 'LIVE-ONLY'
  ! printf '%s' "$output" | grep -q 'UNDEPLOYED-MIRROR' || false
}

# ══════════════════════════════════════════════════════════════════════════════════════════════════
# M5 · axis 3 label SCOPE and STATE (§4 F9) — row 12's two laws, one layer out
# ══════════════════════════════════════════════════════════════════════════════════════════════════

lcstub() { # $1=labels reported LOADED (space-sep) $2=labels reported "=> disabled"
  local f="$BATS_TEST_TMPDIR/launchctl-stub"
  { printf '#!/bin/bash\n'
    printf 'case "$1" in\n'
    printf '  list) for l in %s; do printf "%%s\\t0\\t%%s\\n" - "$l"; done ;;\n' "${1:-}"
    printf '  print-disabled) for l in %s; do printf "\\t\\"%%s\\" => disabled\\n" "$l"; done ;;\n' "${2:-}"
    printf 'esac\nexit 0\n'
  } > "$f"; chmod +x "$f"; printf '%s' "$f"
}

@test "M5: a com.chrisren label is IN SCOPE (a com.claude-only pattern is blind by construction)" {
  # 13-mailbox-gc-activate.sh names a com.chrisren label and was unverifiable before this. The same
  # com.claude-only scope is what hid row 4's live reaper from the fleet audit.
  printf '#!/bin/bash\n# loads com.chrisren.mailbox-gc\n' > "$Q/13-gc-activate.sh"
  : > "$Q/13-gc-activate.sh.done"
  CC_ACTIVATION_DIR="$Q" CC_ACTIVATION_LAUNCHCTL_BIN="$(lcstub '' '')" run "$H"
  printf '%s' "$output" | grep -q 'CLAIMED-DONE BUT INERT'
  printf '%s' "$output" | grep -q 'com.chrisren.mailbox-gc'
}

@test "M5 POSITIVE CONTROL: a LOADED label yields NO row (the axis can go quiet)" {
  printf '#!/bin/bash\n# loads com.chrisren.mailbox-gc\n' > "$Q/13-gc-activate.sh"
  : > "$Q/13-gc-activate.sh.done"
  CC_ACTIVATION_DIR="$Q" CC_ACTIVATION_LAUNCHCTL_BIN="$(lcstub 'com.chrisren.mailbox-gc' '')" run "$H"
  ! printf '%s' "$output" | grep -q 'CLAIMED-DONE BUT INERT' || false
}

@test "M5: DISABLED is distinguished from NOT-LOADED — they have OPPOSITE fixes" {
  # `launchctl list` alone maps both onto 'absent', so the row sent the operator to `bootstrap` when
  # the answer was `enable`. The override DB prints `\"<label>\" => disabled`, never true/false —
  # grepping the plist vocabulary against the CLI returns a confident ZERO.
  printf '#!/bin/bash\n# loads com.claude.log-rotation\n' > "$Q/20-rot-activate.sh"
  : > "$Q/20-rot-activate.sh.done"
  CC_ACTIVATION_DIR="$Q" CC_ACTIVATION_LAUNCHCTL_BIN="$(lcstub '' 'com.claude.log-rotation')" run "$H"
  printf '%s' "$output" | grep -q 'com.claude.log-rotation \[DISABLED\]'
  CC_ACTIVATION_DIR="$Q" CC_ACTIVATION_LAUNCHCTL_BIN="$(lcstub '' '')" run "$H"
  printf '%s' "$output" | grep -q 'com.claude.log-rotation \[NOT-LOADED\]'
}

@test "M5 kill switch: CC_ACTIVATION_INERT_SCOPE=claude restores the com.claude-only pattern" {
  printf '#!/bin/bash\n# loads com.chrisren.mailbox-gc\n' > "$Q/13-gc-activate.sh"
  : > "$Q/13-gc-activate.sh.done"
  CC_ACTIVATION_DIR="$Q" CC_ACTIVATION_INERT_SCOPE=claude \
    CC_ACTIVATION_LAUNCHCTL_BIN="$(lcstub '' '')" run "$H"
  ! printf '%s' "$output" | grep -q 'CLAIMED-DONE BUT INERT' || false
}
