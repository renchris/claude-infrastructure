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

# CHANGED 2026-08-07 — this asserted `-eq 18` and had ALREADY been bumped 7 → 14 → 18 by three
# commits that did nothing but ADD selftest checks; a7cba56d added 8 more (→ 26) and reddened it a
# fourth time. An exact count is a tripwire on the growth of the very suite it guards: every
# legitimate new check fails it, so the number, not the defect, is what gets "fixed". Worse, it never
# asserted the premise its own name claims — `-eq 18` conflates "non-vacuous" with "exactly this
# many", and at 18 it would have passed a reporter that counted 36 while rendering 18.
# What survives is that premise, as the two independent things that make a suite non-vacuous:
#   FLOOR — a DOWNWARD ratchet. Growth passes freely; a DELETED check reds, and lowering the floor
#           has to be a deliberate edit (memory: downward-ratchet-catches-the-over-scoped-marker).
#   TALLY — the summary's own `N passed` must equal the `  ok ` lines it actually rendered. A
#           reporter that claims GREEN while emitting nothing is exactly the vacuous pass this test
#           exists to catch (memory: claimed-outcome-vs-checked-outcome).
# The count is environment-stable: every check emits exactly one okp/badp, and the sole conditional
# (jq present vs absent, hooks/activation-watch.sh:385-388) emits one either way.
@test "selftest passes, is non-vacuous (floor), and its tally matches what it rendered" {
  floor=26                        # raise when checks are added; LOWERING it is a deliberate act
  run "$H" --selftest
  [ "$status" -eq 0 ]
  # `|| true` normalizes grep's rc-1-on-zero-matches, which would otherwise abort the test HERE with
  # a cryptic "grep -c failed" and never reach the floor. It swallows no verdict — the count is data,
  # and the assertions below are the verdict (contrast memory: claimed-outcome-vs-checked-outcome).
  ok_lines="$(printf '%s' "$output" | grep -c '^  ok ' || true)"
  claimed="$(printf '%s' "$output" | sed -n 's/^activation-watch --selftest: \([0-9][0-9]*\) passed,.*/\1/p')"
  [ "$ok_lines" -ge "$floor" ]
  # Two lines, never `[ -n "$claimed" ] && [ ... ]`: in an `&&` list only the command after the FINAL
  # `&&` is seen by set -e, so a short-circuit on the left half is ABSORBED — an unparseable summary
  # would have passed this test vacuously, the very class it exists to catch. (tests/bats-assert-
  # liveness.bats classifies that shape `and-absorbed`; it caught this exact line.)
  [ -n "$claimed" ]
  [ "$claimed" = "$ok_lines" ]
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

# ══════════════════════════════════════════════════════════════════════════════════════════════════
# M6 · axis 4 ENV-ARM effect-read (backlog 80321b2556e6) — the class axes 1 and 3 are both blind to
#
# Axis 1 is silenced by the `.done` marker; axis 3 needs a launchd job and an env-var arm installs
# none. So an activation whose whole effect is `export VAR=1` in a sourced file can be marked done
# and never take effect, with every sensor reading clean — which is exactly what happened to
# 10-lead-crash-orphan-close (marked done 2026-07-30, nothing sourced the file, orphaned assignee
# panes left RUNNING). Most of these drive `--envarm` rather than the bare hook: it runs axis 4
# ALONE, so a finding here is attributable to this axis and not borrowed from another's silence.
# ══════════════════════════════════════════════════════════════════════════════════════════════════

# stage an env-arm activation. $1=script name · $2=env-file path · $3…=lines written to that file
# (pass none to leave the file ABSENT, the NOT-STAGED case).
arm() {
  local s="$1" ef="$2"; shift 2
  printf '#!/bin/bash\nENVFILE="%s"\n' "$ef" > "$Q/$s"
  : > "$Q/$s.done"
  [ "$#" -eq 0 ] || printf '%s\n' "$@" > "$ef"
  return 0
}

@test "M6: an armed variable the consumer cannot see → NOT-DELIVERED (invisible to axes 1 and 3)" {
  arm "70-arm-activate.sh" "$BATS_TEST_TMPDIR/w.env" 'export M6_FIXTURE_VAR=1'
  CC_ACTIVATION_DIR="$Q" run env -u M6_FIXTURE_VAR "$H" --envarm
  [ "$status" -eq 1 ]
  printf '%s' "$output" | grep -q 'ARMED BUT NOT IN EFFECT'
  printf '%s' "$output" | grep -q 'M6_FIXTURE_VAR \[NOT-DELIVERED\]'
}

@test "M6 POSITIVE CONTROL: a DELIVERED variable yields NO row (the axis can go quiet)" {
  # The trailing comment is the REAL file's shape (`export LCW_ORPHAN_CLOSE=1   # arm …`); a value
  # parser that kept it would compare "1   # arm …" against "1" and this axis would fire forever on
  # a healthy arm — an alarm that always fires carries as many bits as one that cannot
  # (memory: alarm-polarity-and-attention-budget).
  arm "70-arm-activate.sh" "$BATS_TEST_TMPDIR/w.env" 'export M6_FIXTURE_VAR=1   # armed, with a comment'
  CC_ACTIVATION_DIR="$Q" M6_FIXTURE_VAR=1 run "$H" --envarm
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'GREEN'
  ! printf '%s' "$output" | grep -q 'ARMED BUT NOT IN EFFECT' || false
}

@test "M6: OVERRIDDEN is distinguished from NOT-DELIVERED — they have OPPOSITE fixes" {
  # Same law axis 3 had to learn for DISABLED vs NOT-INSTALLED. "add a source line" is the wrong
  # remedy for a variable that IS being delivered and then reset by something later in the chain.
  arm "70-arm-activate.sh" "$BATS_TEST_TMPDIR/w.env" 'export M6_FIXTURE_VAR=1'
  CC_ACTIVATION_DIR="$Q" M6_FIXTURE_VAR=0 run "$H" --envarm
  [ "$status" -eq 1 ]
  printf '%s' "$output" | grep -q 'M6_FIXTURE_VAR \[OVERRIDDEN: file=1 live=0\]'
  # The BRACKETED row form, not the bare word: the finding's own remedy text names all three states
  # (they have different fixes, so it must), and asserting absence of the bare string matches that
  # explanation instead of a row. Caught here — this assertion failed against a correct subject.
  ! printf '%s' "$output" | grep -q '\[NOT-DELIVERED\]' || false
}

@test "M6: a .done marker over an env file that was never written → NOT-STAGED" {
  arm "70-arm-activate.sh" "$BATS_TEST_TMPDIR/never-written.env"        # no lines ⇒ file absent
  CC_ACTIVATION_DIR="$Q" run "$H" --envarm
  [ "$status" -eq 1 ]
  printf '%s' "$output" | grep -q 'NOT-STAGED'
}

@test "M6: an env-file path that does not resolve is REPORTED, never a silent skip" {
  printf '#!/bin/bash\nENVFILE="$SOME_UNSET_THING/w.env"\n' > "$Q/70-arm-activate.sh"
  : > "$Q/70-arm-activate.sh.done"
  CC_ACTIVATION_DIR="$Q" run "$H" --envarm
  [ "$status" -eq 1 ]
  printf '%s' "$output" | grep -q 'UNRESOLVED-PATH'
}

@test "M6: an un-run env-arm is axis 1's, not axis 4's (no .done ⇒ silent here)" {
  printf '#!/bin/bash\nENVFILE="%s"\n' "$BATS_TEST_TMPDIR/w.env" > "$Q/70-arm-activate.sh"
  printf 'export M6_FIXTURE_VAR=1\n' > "$BATS_TEST_TMPDIR/w.env"       # NO .done marker
  CC_ACTIVATION_DIR="$Q" run env -u M6_FIXTURE_VAR "$H" --envarm
  [ "$status" -eq 0 ]
  ! printf '%s' "$output" | grep -q 'ARMED BUT NOT IN EFFECT' || false
}

@test "M6 DISCRIMINATOR: the class is an env-file ASSIGNMENT, not the word 'export'" {
  # Both directions in one test, because a guard keyed on a spelling fails BOTH ways (memory:
  # guard-proxy-fails-in-both-directions). A kill-switch line, a PATH line and an echo'd
  # instruction all contain `export VAR=` while arming nothing through a sourced file.
  printf '#!/bin/bash\necho "Kill switch: export CC_SOMETHING=off"\nexport PATH="/x:$PATH"\n' \
    > "$Q/71-prose-activate.sh"
  : > "$Q/71-prose-activate.sh.done"
  arm "70-arm-activate.sh" "$BATS_TEST_TMPDIR/w.env" 'export M6_FIXTURE_VAR=1'
  CC_ACTIVATION_DIR="$Q" run env -u M6_FIXTURE_VAR "$H" --envarm
  [ "$status" -eq 1 ]
  printf '%s' "$output" | grep -q '70-arm-activate.sh'                  # in class → named
  ! printf '%s' "$output" | grep -q '71-prose-activate.sh' || false     # prose only → NOT named
}

@test "M6 DISCRIMINATOR: a script that only MENTIONS a .env path is still out of class" {
  # The case the cheap pre-filter CANNOT decide, and the only one that actually exercises the
  # discriminator. Found by mutation: widening the `sed` to key on `export` survived the whole suite,
  # because the prose fixture above contains no `.env` string at all — so the PRE-FILTER was
  # rejecting it and the discriminator was never reached. Two redundant filters read as one tested
  # filter (memory: cost-gate-must-be-strictly-weaker — a fast path that shadows the real test makes
  # its own mutation control vacuous). This fixture passes the pre-filter by construction, so only
  # the ASSIGNMENT rule can reject it.
  printf '#!/bin/bash\n# to disarm, edit ~/.claude/autonomy/other.env by hand\nexport CC_SOMETHING=off\n' \
    > "$Q/72-mentions-activate.sh"
  : > "$Q/72-mentions-activate.sh.done"
  CC_ACTIVATION_DIR="$Q" run "$H" --envarm
  [ "$status" -eq 0 ]
  ! printf '%s' "$output" | grep -q '72-mentions-activate.sh' || false
}

@test "M6 REAL-ARTIFACT control: the actual queue selects the one env-arm and none of its siblings" {
  # A hand-written approximation can pass vacuously (memory: control-must-replay-the-real-artifact),
  # so this replays the SHIPPED scripts. Four of them carry a bare `export VAR=` in prose; exactly
  # one arms through a sourced env file. Stable whichever state the operator's real watchdog.env is
  # in — absent ⇒ NOT-STAGED, present ⇒ NOT-DELIVERED with the var unset — and both are "named",
  # which is what this asserts. It reads that file; it executes nothing from $HOME.
  local src="$REPO/docs/activation/pending-activation"
  for s in 04-page-channel 10-close-attrib 13-mailbox-gc 26-curl-gate-scope \
           10-lead-crash-orphan-close; do
    cp "$src/$s-activate.sh" "$Q/" && : > "$Q/$s-activate.sh.done"
  done
  CC_ACTIVATION_DIR="$Q" run env -u LCW_ORPHAN_CLOSE "$H" --envarm
  [ "$status" -eq 1 ]
  printf '%s' "$output" | grep -q '10-lead-crash-orphan-close-activate.sh'
  for s in 04-page-channel 10-close-attrib 13-mailbox-gc 26-curl-gate-scope; do
    ! printf '%s' "$output" | grep -q "$s-activate.sh" || false
  done
}

@test "M6 kill switch: CC_ACTIVATION_ENVARM=off silences the axis" {
  arm "70-arm-activate.sh" "$BATS_TEST_TMPDIR/w.env" 'export M6_FIXTURE_VAR=1'
  CC_ACTIVATION_DIR="$Q" CC_ACTIVATION_ENVARM=off run env -u M6_FIXTURE_VAR "$H" --envarm
  [ "$status" -eq 0 ]
  ! printf '%s' "$output" | grep -q 'ARMED BUT NOT IN EFFECT' || false
}

@test "M6: axis 4 composes into the SessionStart emit as ONE valid JSON object" {
  arm "70-arm-activate.sh" "$BATS_TEST_TMPDIR/w.env" 'export M6_FIXTURE_VAR=1'
  stage "p0-99-activate.sh" "$OLD"                    # axis 1 fires too ⇒ both must coexist
  CC_ACTIVATION_DIR="$Q" CC_ACTIVATION_DAMP_S=0 run env -u M6_FIXTURE_VAR "$H"
  [ "$status" -eq 0 ]
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$output" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null
    ctx="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')"
  else
    ctx="$output"
  fi
  printf '%s' "$ctx" | grep -q 'ACTIVATION QUEUE'
  printf '%s' "$ctx" | grep -q 'ARMED BUT NOT IN EFFECT'
}
