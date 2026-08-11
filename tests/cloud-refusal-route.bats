#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2329
#   Structurally false under bats: every @test body IS its own subshell, so an `export` inside one
#   is *meant* to be test-local (SC2030/SC2031), and setup()'s helpers are invoked from those test
#   subshells rather than from file scope (SC2329).
#
# cloud-refusal-route.sh — THE REFUSAL LOOP (CLOUD_BACKLOG_PIPELINE.md W3, §5 clause 6).
#
# WHAT THIS SUITE IS GUARDING. This script SENDS — off-box, spending quota, to a machine that will
# act on whatever it is told. Every defect available to it is therefore a MISROUTE, and each one has
# a different victim:
#
#   · routing a CUT to the VM asks a machine to fix code that is not broken   [d079576e]
#   · routing the IDENTITY WALL to the VM asks it to defeat a gate that works [§13.4-13.5]
#   · routing a SIBLING'S red to the VM makes it own a loose end it did not cause
#   · routing to the WRONG session sends a real brief to a real VM about someone else's work
#   · looping forever spends the quota nobody is watching
#
# So every arm below is paired: the refusal that MUST route to the VM sits beside the one that must
# NOT, over bodies that differ only in the axis under test. The by-design arm's control is the one
# that matters most — cloud-reconcile's SUCCESS line contains the word "unattributable", so a
# matcher keyed on that word would classify every healthy cloud land as an identity refusal, and a
# suite that only ever fed it real refusals would never find out.
#
# HERMETIC: real git for the stale-resolved arm (it is a content read against a trunk, and a stub
# git would test the stub). The three things that reach the outside world — cc-offload say,
# cc-notify, cc-cloud fill-paths — are stubs that RECORD THEIR ARGV, so the tests assert on what was
# actually asked for rather than on prose.

setup() {
  SUT="${BATS_TEST_DIRNAME}/../scripts/cloud-refusal-route.sh"
  [ -x "$SUT" ] || skip "cloud-refusal-route.sh not executable"
  command -v jq >/dev/null 2>&1 || skip "jq required"

  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_CLOUD_STATE="$BATS_TEST_TMPDIR/state"; mkdir -p "$CC_CLOUD_STATE"
  export CC_REFUSAL_NOW=1786480000
  export SAYS="$BATS_TEST_TMPDIR/says"; : >"$SAYS"; : >"$SAYS.n"
  export PINGS="$BATS_TEST_TMPDIR/pings"; : >"$PINGS"; : >"$PINGS.n"
  export STUBDIR="$BATS_TEST_TMPDIR/stubs"; mkdir -p "$STUBDIR"

  # ── cc-offload: the OFF-BOX arm. Records the whole argv, so "was the VM told, and what with"
  #    is a fact rather than an inference. CC_OFFLOAD_RC lets one test make the send fail.
  cat >"$STUBDIR/cc-offload" <<'EOF'
#!/usr/bin/env bash
printf 'CALL\n' >>"$SAYS.n"
{ printf 'ARGV'; for a in "$@"; do printf '\037%s' "$a"; done; printf '\n'; } >>"$SAYS"
exit "${CC_OFFLOAD_RC:-0}"
EOF
  # ── cc-notify: the HOME arm, same treatment.
  cat >"$STUBDIR/cc-notify" <<'EOF'
#!/usr/bin/env bash
printf 'CALL\n' >>"$PINGS.n"
{ printf 'ARGV'; for a in "$@"; do printf '\037%s' "$a"; done; printf '\n'; } >>"$PINGS"
exit "${CC_NOTIFY_RC:-0}"
EOF
  # ── cc-cloud: only `fill-paths --print` is reached, and only when the declaration carries no
  #    path set. CC_FILL_PRINT is what it derives; unset means it derives nothing, which is the
  #    honest empty case the default-direction arm turns on.
  cat >"$STUBDIR/cc-cloud" <<'EOF'
#!/usr/bin/env bash
[ -n "${CC_FILL_PRINT:-}" ] && printf '%s\n' "$CC_FILL_PRINT"
exit 0
EOF
  chmod +x "$STUBDIR"/cc-offload "$STUBDIR"/cc-notify "$STUBDIR"/cc-cloud
  export CC_REFUSAL_OFFLOAD_BIN="$STUBDIR/cc-offload"
  export CC_REFUSAL_NOTIFY_BIN="$STUBDIR/cc-notify"
  export CC_REFUSAL_CLOUD_BIN="$STUBDIR/cc-cloud"

  export ID=session_01TEST
  export BRANCH=claude/fire-20260811T000000Z-1-1
}

# ── fixtures ─────────────────────────────────────────────────────────────────────────────────────

decl() { # [paths] [repo] [trunk]
  { printf 'id=%s\n' "$ID"
    printf 'branch=%s\n' "$BRANCH"
    printf 'remote=origin\n'
    printf 'repo=%s\n' "${2:-$BATS_TEST_TMPDIR/norepo}"
    printf 'trunk=%s\n' "${3:-origin/main}"
    printf 'paths=%s\n' "${1:-}"
    printf 'account=next3\n'
    printf 'url=https://claude.ai/code/%s\n' "$ID"
    printf 'notify_back=371\n'
    printf 'custody=%s\n' "$ID"
  } >"$CC_CLOUD_STATE/$ID.decl"
}

# The REAL shape cloud-return writes: KV header, a bare `--`, then the land's combined output.
artifact() { # <rc> <at> <body>
  { printf 'id=%s\nbranch=%s\nrc=%s\nat=%s\n--\n' "$ID" "$BRANCH" "$1" "$2"
    printf '%s\n' "$3"; } >"$CC_CLOUD_STATE/$ID.land-refused"
}

# The lander's preamble and tail, TRANSCRIBED FROM THE FIRST REAL ARTIFACT this rail ever produced
# (2026-08-11) rather than composed here. Both are carried by every body on purpose, because each
# holds a trap a hand-written fixture would never think to include — and TWO of them were live
# defects found exactly this way:
#
#   · `scripts/desk-land.sh` + a /private/tmp worktree — what a path-SCRAPING classifier convicts
#   · "unattributable", from cloud-reconcile's SUCCESS line — what a word-keyed identity matcher hits
#   · `→ gate: git-identity escape ratchet` — a PROGRESS line ship-land prints whenever that arm
#     RUNS, green or red, so every refusal raised by a LATER arm contains the string "git-identity"
#   · desk-land's exit-code LEGEND — which spells `9 GATE-KILLED` as VOCABULARY on every failure
#
# Carrying them in the shared fixture means a regression on any of the four reds EVERY arm below,
# not one. (memory: control-must-replay-the-real-artifact — a fixture cannot surprise you with what
# a real producer writes.)
preamble() {
  cat <<EOF
→ $BRANCH — re-authored 2 commit(s) as <ren.chris@outlook.com> (2 of them were unattributable); provenance in Cloud-session / Original-commit / Original-branch trailers, and 'origin' still holds the originals.
→ desk-land: created throwaway worktree for '$BRANCH': /private/tmp/.desk-land-x-15071 (removed on exit)
→ desk-land: handing '$BRANCH' to the ship rail (/private/tmp/.desk-land-x-15071/scripts/ship-land.sh)…
→ ship-land[unlocked]: fetch + rebase + gate (statics + ratchets + bounded smoke) — no lock held
→ gate: statics memo — 0 file verdict(s) carried, 0 proven fresh.
→ gate: git-identity escape ratchet (a fixture identity that can land in the caller's repo)
→ gate: test-hermeticity ratchet (before bats — seconds, and it names the file)
EOF
}

# desk-land's own failure tail. The parenthesised code map is the trap.
desk_tail() { # <ship-land exit code>
  cat <<EOF
✗ desk-land: ship rail exited $1 for '$BRANCH' — surfaced verbatim (2 dirty/preflight · 3 escalation-PARK · 5 rebase-conflict · 6 gate-red · 7 push non-ff · 8 verify-fail · 9 GATE-KILLED · 75 LOCK-STARVED). NOT retrying blindly — but 9 and 75 are statements about the MACHINE, not findings about the tree: those two ARE the retryable ones.
✗ $BRANCH — lander exited $1.
EOF
}

# A REAL hermeticity red, copied from a live run of scripts/test-hermeticity-lint.sh. Note that it
# names the suite by BASENAME — the measured spelling the full-path-only matcher would miss.
hermeticity_red() { # <basename>
  cat <<EOF
$(preamble)
  LEAK     $1: setup() does not fixture \$HOME — it runs against the live ~/
test-hermeticity-lint: ⛔ 1 new non-hermetic suite(s) above.
  Fix: in setup(), \`export HOME="\$BATS_TEST_TMPDIR/home"; mkdir -p "\$HOME"\`, then
       seed whatever fixture state the subject reads under it. Do NOT add to the allowlist.
✗ gate: test-hermeticity RED — something THIS LAND CHANGES runs against ambient state.
✗ ship-land: GATE RED — not pushing.
$(desk_tail 6)
EOF
}

# COUNT CALLS, NOT LINES — and count them in a file the payload cannot reach. A routed payload is
# the gate's own MULTI-LINE verdict, so a counter that grepped the argv log would read one send as
# eleven and every `-eq 1` would fail while the send was perfect. The stubs stamp one `CALL` line
# per invocation into a sidecar; the argv log stays for content assertions.
# (`grep -c .` also prints 0 AND exits 1 on an empty file, so an `|| echo 0` fallback would append a
# SECOND zero and break every comparison in the no-send case — hence `return 0` rather than `||`.)
says_n() { grep -c . "$SAYS.n" 2>/dev/null; return 0; }
pings_n() { grep -c . "$PINGS.n" 2>/dev/null; return 0; }

# ═══ 1. THE CUT — a non-verdict, and the distinction is the whole of d079576e ════════════════════

@test "a land killed by a bound (rc=143) is a NON-VERDICT: nothing is routed, no cycle is spent" {
  decl "tests/probe.bats"
  artifact 143 1786479000 "$(preamble)
✗ ship-land: verdict=killed signal=SIGTERM role=outer branch=$BRANCH — this land was TERMINATED from outside; it did not fail a gate and nothing was proven about the tree."
  run "$SUT" --id "$ID"
  [ "$status" -eq 0 ]
  [[ "$output" == *"arm=cut"* ]]
  [[ "$output" == *"NOT ROUTED"* ]]
  [ "$(says_n)" -eq 0 ]
  [ "$(pings_n)" -eq 0 ]
  # and it consumed no cycle — the bound is for real evidence
  run bash -c "jq -s '[.[]|select(.routed==\"vm\")]|length' '$CC_CLOUD_STATE/$ID.refusal-route'"
  [ "$output" = "0" ]
}

@test "CONTROL for the cut: the same body without the kill, at a gate-red rc, DOES route" {
  decl "tests/probe.bats"
  artifact 70 1786479000 "$(hermeticity_red probe.bats)"
  run "$SUT" --id "$ID"
  [ "$status" -eq 0 ]
  [[ "$output" == *"arm=vm"* ]]
  [ "$(says_n)" -eq 1 ]
}

@test "ship-land's own killed token is enough on its own, at any rc" {
  decl "tests/probe.bats"
  artifact 70 1786479000 "$(preamble)
✗ ship-land: verdict=killed signal=SIGTERM role=outer — nothing was proven about the tree."
  run "$SUT" --id "$ID"
  [[ "$output" == *"arm=cut"* ]]
  [ "$(says_n)" -eq 0 ]
}

@test "GATE-KILLED is a claim about the machine, not the tree — never routed" {
  decl "tests/probe.bats"
  artifact 9 1786479000 "$(preamble)
⛔ ship-land: GATE-KILLED — the gate died without earning a verdict, so this is NOT a red and NOT evidence about your tree."
  run "$SUT" --id "$ID"
  [[ "$output" == *"arm=cut"* ]]
  [ "$(says_n)" -eq 0 ]
}

@test "CONTROL: desk-land's exit-code LEGEND spells 'GATE-KILLED' on every failure — vocabulary, not a verdict" {
  # THE FIRST REAL ARTIFACT FAILED HERE, and no fixture written by hand would have. desk-land
  # surfaces a code map on every non-zero ship rail — `(… 8 verify-fail · 9 GATE-KILLED · 75
  # LOCK-STARVED)` — so a bare `*"GATE-KILLED"*` read an ordinary hermeticity RED as a cut, refused
  # to route it, and the refusal loop would have been silently inert on its first live run. The
  # matcher must anchor on the EMITTER (`ship-land: GATE-KILLED`), never on the token.
  decl "tests/probe.bats"
  artifact 70 1786479000 "$(hermeticity_red probe.bats)"
  grep -q '9 GATE-KILLED' "$CC_CLOUD_STATE/$ID.land-refused"     # the trap is really in the body
  run "$SUT" --id "$ID"
  [[ "$output" != *"arm=cut"* ]]
  [[ "$output" == *"arm=vm"* ]]
  [ "$(says_n)" -eq 1 ]
}

@test "…and a REAL kill still reads as a cut even with that legend present" {
  # The other half of the same pair: tightening the matcher must not make it blind. Both spellings
  # of a genuine kill are in one body here, alongside the legend that must be ignored.
  decl "tests/probe.bats"
  artifact 70 1786479000 "$(preamble)
⛔ ship-land: GATE-KILLED — the gate died without earning a verdict, so this is NOT a red.
$(desk_tail 9)"
  run "$SUT" --id "$ID"
  [[ "$output" == *"arm=cut"* ]]
  [ "$(says_n)" -eq 0 ]
}

# ═══ 2. THE IDENTITY WALL — by design, and its control is the load-bearing one ═══════════════════

@test "an identity-gate refusal goes HOME, never to the VM — the re-authoring land owns it" {
  decl "docs/vm.md"
  artifact 70 1786479000 "✗ $BRANCH — NOT landed. This range is authored by someone GitHub cannot attribute, so githooks/pre-push would refuse the push. It could not be re-authored: no effective git identity."
  run "$SUT" --id "$ID"
  [ "$status" -eq 0 ]
  [[ "$output" == *"arm=by-design"* ]]
  [ "$(says_n)" -eq 0 ]
  [ "$(pings_n)" -eq 1 ]
  grep -q "NOT the VM's to fix" "$PINGS"
}

@test "CONTROL: cloud-reconcile's SUCCESS line says 'unattributable' and must NOT read as an identity refusal" {
  # This is the vacuous-fixture guard. Every body in this suite carries the success line via
  # preamble(); if the matcher keyed on the word rather than on the refusal spellings, EVERY test
  # here would classify by-design and the suite would still be green on the arms that expect a
  # ping. Pinning it explicitly is what makes the other arms mean anything.
  decl "tests/probe.bats"
  artifact 70 1786479000 "$(hermeticity_red probe.bats)"
  run "$SUT" --id "$ID"
  [[ "$output" != *"arm=by-design"* ]]
  [[ "$output" == *"arm=vm"* ]]
}

@test "a git-identity GATE ARM red is by-design too — the VM cannot change who authored its commits" {
  decl "docs/vm.md"
  artifact 6 1786479000 "$(preamble)
✗ gate: git-identity RED — a file THIS LAND CHANGES can write its test identity into the caller's repo.
✗ ship-land: GATE RED — not pushing."
  run "$SUT" --id "$ID"
  [[ "$output" == *"arm=by-design"* ]]
  [ "$(says_n)" -eq 0 ]
}

@test "CONTROL: 'git-identity' is a PROGRESS line on every land that reaches that arm" {
  # The second live defect, and the more damaging of the two. ship-land prints
  # `→ gate: git-identity escape ratchet (…)` whenever that arm RUNS — green or red — so a bare
  # `*"git-identity"*` would classify EVERY refusal raised by a later arm (utc-stamp, self-path,
  # pane-spawn, permission-gate, bats, smoke …) as the by-design identity wall and send it home.
  # The loop would have worked only for the handful of arms that run BEFORE git-identity.
  decl "tests/probe.bats"
  artifact 6 1786479000 "$(preamble)
→ gate: script-dir resolution ratchet (a repo root derived from an unresolved \$0)
✗ gate: self-path RED: tests/probe.bats
✗ ship-land: GATE RED — not pushing.
$(desk_tail 6)"
  grep -q 'git-identity escape ratchet' "$CC_CLOUD_STATE/$ID.land-refused"   # the trap is present
  run "$SUT" --id "$ID"
  [[ "$output" != *"arm=by-design"* ]]
  [[ "$output" == *"arm=vm"* ]]
  [ "$(says_n)" -eq 1 ]
}

# ═══ 3. FIXABLE-BY-VM — the gate named a file this session's own commits wrote ═══════════════════

@test "a red naming the VM's own file BY FULL PATH routes off-box, with the gate's verdict verbatim" {
  decl "scripts/vm-tool.sh"
  artifact 6 1786479000 "$(preamble)
✗ gate: bash -n RED: scripts/vm-tool.sh
✗ ship-land: GATE RED — not pushing."
  run "$SUT" --id "$ID"
  [ "$status" -eq 0 ]
  [[ "$output" == *"arm=vm"* ]]
  [ "$(says_n)" -eq 1 ]
  # the SEND is addressed to the causing session and carries the gate's OWN line
  grep -q "$ID" "$SAYS"
  grep -q "bash -n RED: scripts/vm-tool.sh" "$SAYS"
  grep -q "LAND REFUSED" "$SAYS"
  # and the ledger records WHICH spelling matched, so a hit stays auditable
  grep -q '"match":"path:scripts/vm-tool.sh"' "$CC_CLOUD_STATE/$ID.refusal-route"
}

@test "a red naming the VM's file BY BASENAME ONLY still routes — the measured hermeticity spelling" {
  # test-hermeticity-lint reports `LEAK  probe.bats:` for tests/probe.bats. A full-path-only
  # matcher reads NOT-NAMED over a red that names the file perfectly, and the refusal would have
  # been sent home for a human to diagnose — the exact hand-work W3 exists to delete.
  decl "tests/probe.bats"
  artifact 6 1786479000 "$(hermeticity_red probe.bats)"
  run "$SUT" --id "$ID"
  [[ "$output" == *"arm=vm"* ]]
  [ "$(says_n)" -eq 1 ]
  grep -q '"match":"basename:probe.bats"' "$CC_CLOUD_STATE/$ID.refusal-route"
  grep -q "does not fixture" "$SAYS"
}

@test "the payload carries the lint's REMEDY, not only its diagnosis" {
  # The remedy wraps onto continuation lines that carry no failure marker of their own. A payload
  # built by grepping matching lines would deliver "you leaked \$HOME" and drop "here is how to fix
  # it", which is the half the VM actually acts on.
  decl "tests/probe.bats"
  artifact 6 1786479000 "$(hermeticity_red probe.bats)"
  run "$SUT" --id "$ID"
  grep -q "seed whatever fixture state the subject reads under it" "$SAYS"
}

@test "the path set is DERIVED from the VM's own commits when the declaration has none" {
  decl ""                       # nothing recorded yet — the pre-land state after a refusal
  export CC_FILL_PRINT="tests/probe.bats"
  artifact 6 1786479000 "$(hermeticity_red probe.bats)"
  run "$SUT" --id "$ID"
  [[ "$output" == *"arm=vm"* ]]
  [ "$(says_n)" -eq 1 ]
}

# ═══ 4. THE DEFAULT DIRECTION — home, never off-box ══════════════════════════════════════════════

@test "a red naming a file OUTSIDE this session's diff is not the VM's to fix" {
  decl "docs/vm.md"
  artifact 6 1786479000 "$(preamble)
✗ gate: bash -n RED: scripts/somebody-elses.sh
✗ ship-land: GATE RED — not pushing."
  run "$SUT" --id "$ID"
  [[ "$output" == *"arm=local-only"* ]]
  [ "$(says_n)" -eq 0 ]
  [ "$(pings_n)" -eq 1 ]
}

@test "an UNDERIVABLE path set routes home — uncertainty never goes off-box" {
  decl ""
  # CC_FILL_PRINT unset: the derivation returns nothing, which is honest and must not become a guess
  artifact 6 1786479000 "$(preamble)
✗ gate: shellcheck RED
✗ ship-land: GATE RED — not pushing."
  run "$SUT" --id "$ID"
  [[ "$output" == *"arm=local-only"* ]]
  [[ "$output" == *"uncertainty routes home"* ]]
  [ "$(says_n)" -eq 0 ]
  [ "$(pings_n)" -eq 1 ]
}

@test "the lander's own preamble must not convict scripts/desk-land.sh" {
  # The naive classifier scrapes paths out of the verdict text; the preamble names desk-land and a
  # /private/tmp worktree in every single artifact, so that classifier would find a 'failing file'
  # in a body whose gate named nothing at all.
  decl "docs/vm.md"
  artifact 6 1786479000 "$(preamble)
✗ ship-land: GATE RED — not pushing."
  run "$SUT" --id "$ID"
  [[ "$output" == *"arm=local-only"* ]]
  [ "$(says_n)" -eq 0 ]
}

@test "machine-side causes route home: a non-fast-forward is a race, not a defect" {
  decl "docs/vm.md"
  artifact 7 1786479000 "$(preamble)
✗ ship-land: push to origin/main REJECTED (non-fast-forward — a sibling beat you inside the window)."
  run "$SUT" --id "$ID"
  [[ "$output" == *"arm=local-only"* ]]
  [[ "$output" == *"lost a race"* ]]
  [ "$(says_n)" -eq 0 ]
}

@test "a machine-side cause wins even when the red also names the VM's file" {
  # Precedence, stated as a test: a content-verify failure is about THIS box dropping content, and
  # the VM cannot clear it however many of its own files appear in the log.
  decl "docs/vm.md"
  artifact 8 1786479000 "$(preamble)
✗ ship-land: post-push CONTENT-VERIFY FAILED after 3 auto-retry attempt(s) — your paths are NOT intact on origin/main (docs/vm.md)."
  run "$SUT" --id "$ID"
  [[ "$output" == *"arm=local-only"* ]]
  [ "$(says_n)" -eq 0 ]
}

# ═══ 5. ATTRIBUTION — the causing session, never the nearest one ═════════════════════════════════

@test "a refusal whose branch disagrees with the declaration is REFUSED, not routed" {
  decl "tests/probe.bats"
  { printf 'id=%s\nbranch=%s\nrc=6\nat=1786479000\n--\n' "$ID" "claude/somebody-elses-branch"
    hermeticity_red probe.bats; } >"$CC_CLOUD_STATE/$ID.land-refused"
  run "$SUT" --id "$ID"
  [ "$status" -eq 0 ]
  [[ "$output" == *"REFUSING TO ROUTE"* ]]
  [ "$(says_n)" -eq 0 ]
  [ "$(pings_n)" -eq 0 ]
}

@test "a refusal with no declaration names no causing session, so nothing is sent" {
  artifact 6 1786479000 "$(hermeticity_red probe.bats)"
  run "$SUT" --id "$ID"
  [[ "$output" == *"REFUSING TO ROUTE"* ]]
  [ "$(says_n)" -eq 0 ]
  [ "$(pings_n)" -eq 0 ]
}

# ═══ 6. THE BOUND ════════════════════════════════════════════════════════════════════════════════

@test "the loop is bounded at 2 VM cycles and then wakes a human WITH the chain" {
  decl "tests/probe.bats"
  artifact 6 1786479001 "$(hermeticity_red probe.bats)"
  run "$SUT" --id "$ID"; [[ "$output" == *"cycle 1/2"* ]]
  artifact 6 1786479002 "$(hermeticity_red probe.bats)"
  run "$SUT" --id "$ID"; [[ "$output" == *"cycle 2/2"* ]]
  [ "$(says_n)" -eq 2 ]
  artifact 6 1786479003 "$(hermeticity_red probe.bats)"
  run "$SUT" --id "$ID"
  [ "$status" -eq 0 ]
  [[ "$output" == *"EXHAUSTED"* ]]
  [ "$(says_n)" -eq 2 ]          # NOT a third send
  [ "$(pings_n)" -eq 1 ]
  grep -q "REFUSAL LOOP EXHAUSTED" "$PINGS"
  # the chain is PRINTED, not merely referenced — the human gets the evidence, not a pointer
  [[ "$output" == *"REFUSAL CHAIN"* ]]
  [[ "$output" == *"arm=vm"* ]]
}

@test "a cut does not spend a cycle, so a killed land cannot exhaust a real budget" {
  decl "tests/probe.bats"
  artifact 143 1786479001 "$(preamble)
✗ ship-land: verdict=killed signal=SIGTERM — nothing was proven about the tree."
  run "$SUT" --id "$ID"
  artifact 143 1786479002 "$(preamble)
✗ ship-land: verdict=killed signal=SIGTERM — nothing was proven about the tree."
  run "$SUT" --id "$ID"
  artifact 6 1786479003 "$(hermeticity_red probe.bats)"
  run "$SUT" --id "$ID"
  [[ "$output" == *"cycle 1/2"* ]]       # the first REAL refusal is still cycle 1
  [ "$(says_n)" -eq 1 ]
}

@test "the cycle counter survives the marker being overwritten by the next refusal" {
  # `<id>.land-refused` is written with `>`, so a counter living inside it would be reset by the
  # very event it bounds and the loop would run forever reading 'cycle 1'.
  decl "tests/probe.bats"
  artifact 6 1786479001 "$(hermeticity_red probe.bats)"; run "$SUT" --id "$ID"
  artifact 6 1786479002 "$(hermeticity_red probe.bats)"; run "$SUT" --id "$ID"
  run bash -c "jq -s '[.[]|select(.routed==\"vm\")]|length' '$CC_CLOUD_STATE/$ID.refusal-route'"
  [ "$output" = "2" ]
}

@test "CC_REFUSAL_MAX_CYCLES is the bound, and it is honoured" {
  export CC_REFUSAL_MAX_CYCLES=1
  decl "tests/probe.bats"
  artifact 6 1786479001 "$(hermeticity_red probe.bats)"; run "$SUT" --id "$ID"
  artifact 6 1786479002 "$(hermeticity_red probe.bats)"; run "$SUT" --id "$ID"
  [[ "$output" == *"EXHAUSTED"* ]]
  [ "$(says_n)" -eq 1 ]
}

# ═══ 7. IDEMPOTENCE ══════════════════════════════════════════════════════════════════════════════

@test "the same refusal is routed ONCE — a re-sweep waits on the VM rather than re-sending" {
  decl "tests/probe.bats"
  artifact 6 1786479000 "$(hermeticity_red probe.bats)"
  run "$SUT" --id "$ID"; [ "$(says_n)" -eq 1 ]
  run "$SUT" --id "$ID"
  [[ "$output" == *"already handled"* ]]
  [ "$(says_n)" -eq 1 ]
}

@test "two refusals inside one second are two refusals — the key is not the timestamp alone" {
  # `at` has one-second resolution. Keyed on it alone, a second refusal in the same second would
  # be swallowed as a duplicate and the VM would never hear about it.
  decl "tests/probe.bats"
  artifact 6 1786479000 "$(hermeticity_red probe.bats)"
  run "$SUT" --id "$ID"
  artifact 6 1786479000 "$(hermeticity_red other-probe.bats)
✗ gate: bash -n RED: tests/probe.bats"
  run "$SUT" --id "$ID"
  [ "$(says_n)" -eq 2 ]
}

@test "a send that did NOT go is not latched, so the next pass retries it" {
  decl "tests/probe.bats"
  artifact 6 1786479000 "$(hermeticity_red probe.bats)"
  CC_OFFLOAD_RC=8 run "$SUT" --id "$ID"
  [[ "$output" == *"THE SEND FAILED"* ]]
  run "$SUT" --id "$ID"
  [[ "$output" != *"already handled"* ]]
  [ "$(says_n)" -eq 2 ]
}

# ═══ 8. STALENESS — by CONTENT, because the land re-authors ══════════════════════════════════════

@test "a refusal whose work has SINCE LANDED is stale and is not routed" {
  REPO="$BATS_TEST_TMPDIR/repo"
  git init -q "$REPO"
  mkdir -p "$REPO/docs" && printf 'landed\n' >"$REPO/docs/vm.md"
  git -C "$REPO" add -A
  git -C "$REPO" -c user.email=t@t -c user.name=t commit -q -m seed
  git -C "$REPO" branch trunkref HEAD
  decl "docs/vm.md" "$REPO" "trunkref"
  artifact 6 1786479000 "$(hermeticity_red probe.bats)
✗ gate: bash -n RED: docs/vm.md"
  run "$SUT" --id "$ID"
  [ "$status" -eq 0 ]
  [[ "$output" == *"STALE"* ]]
  [ "$(says_n)" -eq 0 ]
}

@test "CONTROL: the same refusal with the path ABSENT from the trunk is live and DOES route" {
  REPO="$BATS_TEST_TMPDIR/repo"
  git init -q "$REPO"
  printf 'x\n' >"$REPO/other"
  git -C "$REPO" add -A
  git -C "$REPO" -c user.email=t@t -c user.name=t commit -q -m seed
  git -C "$REPO" branch trunkref HEAD
  decl "docs/vm.md" "$REPO" "trunkref"
  artifact 6 1786479000 "$(preamble)
✗ gate: bash -n RED: docs/vm.md"
  run "$SUT" --id "$ID"
  [[ "$output" != *"STALE"* ]]
  [[ "$output" == *"arm=vm"* ]]
  [ "$(says_n)" -eq 1 ]
}

# ═══ 9. THE PAYLOAD BOUND ════════════════════════════════════════════════════════════════════════

@test "an over-long verdict is truncated and the truncation is NAMED in the payload itself" {
  export CC_REFUSAL_PAYLOAD_MAX=200
  decl "tests/probe.bats"
  BIG="$(printf '✗ gate: probe.bats RED\n'; for i in $(seq 1 60); do printf 'line %s of gate noise that pads the verdict well past the bound\n' "$i"; done)"
  artifact 6 1786479000 "$BIG"
  run "$SUT" --id "$ID"
  [ "$(says_n)" -eq 1 ]
  grep -q "truncated: 200 of" "$SAYS"
}

# ═══ 10. THE PASS ════════════════════════════════════════════════════════════════════════════════

@test "a box with no refusals costs nothing to sweep and says so" {
  run "$SUT" --sweep
  [ "$status" -eq 0 ]
  [[ "$output" == *"no refusal artifacts"* ]]
  [ "$(says_n)" -eq 0 ]
}

@test "--dry-run classifies and PRINTS the payload without sending anything" {
  decl "tests/probe.bats"
  artifact 6 1786479000 "$(hermeticity_red probe.bats)"
  run "$SUT" --id "$ID" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Dry run"* ]]
  [[ "$output" == *"does not fixture"* ]]
  [ "$(says_n)" -eq 0 ]
  [ "$(pings_n)" -eq 0 ]
  # and a dry run must not latch, or the real pass would skip the refusal it never routed
  run "$SUT" --id "$ID"
  [ "$(says_n)" -eq 1 ]
}

@test "--classify is a pure read: a verdict, no send, no state" {
  decl "tests/probe.bats"
  artifact 6 1786479000 "$(hermeticity_red probe.bats)"
  run "$SUT" --classify "$CC_CLOUD_STATE/$ID.land-refused"
  [ "$status" -eq 0 ]
  [[ "$output" == *"arm=vm"* ]]
  [[ "$output" == *"match=basename:probe.bats"* ]]
  [ "$(says_n)" -eq 0 ]
  [ ! -f "$CC_CLOUD_STATE/$ID.refusal-route" ]
}

@test "--chain prints the marker, the gate's verdict and every route taken" {
  decl "tests/probe.bats"
  artifact 6 1786479000 "$(hermeticity_red probe.bats)"
  run "$SUT" --id "$ID"
  run "$SUT" --chain "$ID"
  [ "$status" -eq 0 ]
  [[ "$output" == *"REFUSAL CHAIN"* ]]
  [[ "$output" == *"$BRANCH"* ]]
  [[ "$output" == *"does not fixture"* ]]
  [[ "$output" == *"routed=vm"* ]]
}

@test "the sweep handles every artifact on the box, keyed by the file that names its session" {
  decl "tests/probe.bats"
  artifact 6 1786479000 "$(hermeticity_red probe.bats)"
  ID2=session_02TEST
  { printf 'id=%s\nbranch=b2\nremote=origin\nrepo=x\npaths=docs/two.md\nnotify_back=371\n' "$ID2"; } >"$CC_CLOUD_STATE/$ID2.decl"
  { printf 'id=%s\nbranch=b2\nrc=6\nat=1786479000\n--\n' "$ID2"
    printf '✗ gate: bash -n RED: docs/two.md\n'; } >"$CC_CLOUD_STATE/$ID2.land-refused"
  run "$SUT" --sweep
  [ "$status" -eq 0 ]
  [[ "$output" == *"2 refusal artifact(s) examined"* ]]
  [ "$(says_n)" -eq 2 ]
  grep -q "$ID" "$SAYS"
  grep -q "$ID2" "$SAYS"
}

# ═══ 11. THE WIRING ══════════════════════════════════════════════════════════════════════════════
# Every arm above is hermetic, and a hermetic suite cannot see whether anything CALLS this script.
# W2's own suite records exactly that shape: a router nothing invokes routes nothing, and every test
# here would stay green. These four are structural on purpose — running the real 300 s sweep costs
# more than the suite it lives in.

@test "autonomy-sweep INVOKES cloud-refusal-route --sweep (a loop nothing calls closes nothing)" {
  local sweep="${BATS_TEST_DIRNAME}/../scripts/autonomy-sweep.sh"
  [ -f "$sweep" ] || skip "autonomy-sweep.sh absent"
  # Anchor on the INVOCATION, not on the tool name: the name also appears in the assignment, and a
  # test that matched only the assignment would stay green over a script that is never run.
  grep -q 'cloud-refusal-route.sh' "$sweep"
  grep -q -- '_cloudrfz" --sweep' "$sweep"
}

@test "…and it is called AFTER the return pass, which is what writes the artifact it consumes" {
  # Ordering is the whole value of routing in the same tick: the return pass files
  # `<id>.land-refused`, so a router placed above it would always be reading the PREVIOUS tick's
  # refusals and every routed verdict would reach the VM 300 s late.
  local sweep="${BATS_TEST_DIRNAME}/../scripts/autonomy-sweep.sh"
  [ -f "$sweep" ] || skip "autonomy-sweep.sh absent"
  local ret_line rfz_line
  ret_line="$(grep -n '_cloudret" --sweep' "$sweep" | head -1 | cut -d: -f1)"
  rfz_line="$(grep -n '_cloudrfz" --sweep' "$sweep" | head -1 | cut -d: -f1)"
  [ -n "$ret_line" ] && [ -n "$rfz_line" ] || false
  [ "$ret_line" -lt "$rfz_line" ]
}

@test "…and ABOVE the nothing-new early exit, where a quiet fleet still reaches it" {
  # A refused land produces no page and no alarm; it is silent by construction. Anchored on CODE —
  # the invocation and the `total_new` test that IS the exit — never on the prose around them.
  local sweep="${BATS_TEST_DIRNAME}/../scripts/autonomy-sweep.sh"
  [ -f "$sweep" ] || skip "autonomy-sweep.sh absent"
  local call_line exit_line
  call_line="$(grep -n '_cloudrfz" --sweep' "$sweep" | head -1 | cut -d: -f1)"
  exit_line="$(grep -n 'total_new" -eq 0' "$sweep" | head -1 | cut -d: -f1)"
  [ -n "$call_line" ] && [ -n "$exit_line" ] || false
  [ "$call_line" -lt "$exit_line" ]
}

@test "the sweep's call is GATED to the deployed copy — a suite may never send off-box" {
  # Stricter than the return path's version of this guard, and for a stricter reason: cloud-return
  # lands a branch, this hands a real VM a brief it will ACT on. The four concurrent suite copies
  # measured landing against the live store on 2026-08-11 would have been four identical refusal
  # briefs sent to one machine.
  local sweep="${BATS_TEST_DIRNAME}/../scripts/autonomy-sweep.sh"
  [ -f "$sweep" ] || skip "autonomy-sweep.sh absent"
  local gate_line rfz_line
  # The gate keys on the UNRESOLVED $0: the deployed path is a SYMLINK into the checkout, so a
  # resolved path is identical in both cases and the discriminator disappears.
  gate_line="$(grep -n 'case "\$0" in' "$sweep" | head -1 | cut -d: -f1)"
  rfz_line="$(grep -n '_cloudrfz" --sweep' "$sweep" | head -1 | cut -d: -f1)"
  [ -n "$gate_line" ] && [ -n "$rfz_line" ] || false
  [ "$gate_line" -lt "$rfz_line" ]
  grep -q 'skipped-not-deployed' "$sweep"
  # …and the guard must actually govern THIS call, not merely precede it in the file.
  grep -q '_cloudret_deployed" != 1' "$sweep"
}
