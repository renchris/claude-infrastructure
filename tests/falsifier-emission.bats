#!/usr/bin/env bats
# falsifier EMISSION — the four machine generators must hand each item its own re-run check.
#
# WHAT THIS SUITE IS FOR. `a7bf7068` landed the `--falsifier` field and taught cc-premise to re-run
# it at claim time; six days later `cc-backlog list --all --json | jq '[.[]|select(.falsifier)]'`
# still read ZERO. The field existed, the caller existed, the tests passed, and the mechanism was
# worth nothing because no producer fed it. Existence checks cannot see that gap — only an assertion
# that a GENERATOR emits can — so §1 asserts emission at the add site, per generator.
#
# 🚨 §2 IS THE LOAD-BEARING HALF, and it is the DoD's third clause: a falsifier whose exit 0 is
# reachable from two different states is WORSE than none, because it reports DONE over a live
# premise. That defect is not hypothetical here — it was measured three times in the wave that
# produced this work:
#   · `deploy-live.sh --dry-run` returns 0 both for "the deadlock is resolved" and for "at trunk tip,
#     nothing to deploy". It was written into a goal criterion and flipped green with the deadlock
#     fully intact.
#   · Its correction, a distance-vs-SCAN_N test, was ALSO wrong: `merge-base --is-ancestor X X` is
#     true, so the target was matched against itself and the lag budget was structurally unreachable.
#   · A `<100` worktree target the janitor could never reach, because 121 of the keeps were dirty
#     trees it correctly refuses to touch.
# So §2 does not ask "does exit 0 happen". It enumerates each probe's REACHABLE STATES, labels every
# one with what the item's premise is doing there, and pins the mapping:
#
#     premise FALSE (the work is genuinely gone)   ⇒ exit 0        — the only way to reach 0
#     premise TRUE  (the work is still live)       ⇒ non-zero
#     COULD NOT ASK (no ledger, no file, no git)   ⇒ non-zero      — never 0
#
# The third row is the one that catches the real bug. "Resolved" and "not applicable" both feel like
# nothing-to-do, and a probe that collapses them retires live work silently. A state list that grows
# a new member with no row here fails loudly rather than defaulting into the success arm (memory:
# new-enum-member-falls-into-fail-closed-default).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  BACKLOG_BIN="$REPO/bin/cc-backlog"
  DISCOVER="$REPO/bin/cc-discover"
  POSTLAND="$REPO/scripts/postland-verify.sh"
  DEPLOY="$REPO/scripts/deploy-live.sh"
  PLANSCAN="$REPO/scripts/plan-phase-scan.sh"
  # HERMETIC $HOME, not merely a redirected store: both the backlog and the postland ledger DEFAULT
  # to ~/.claude/..., so overriding only the override is one unset variable away from the operator's
  # live files — which is exactly what the land gate's test-hermeticity lint refuses.
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/autonomy/postland" "$HOME/.claude/bin" "$HOME/.claude/scripts"
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  export CC_POSTLAND_DIR="$HOME/.claude/autonomy/postland"
  export CC_DISCOVER_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_BACKLOG_BIN="$BACKLOG_BIN"
  export CC_DISCOVER_BACKLOG_BIN="$BACKLOG_BIN"
  # PIN EVERY OTHER CRITIC INERT, by pointing each at an absent source — the same discipline
  # cc-discover's own selftest applies (bin/cc-discover run_case). Only C2 is under test here, and
  # C4's DEFAULT is a live gate-script list that this suite would otherwise EXECUTE: a test that runs
  # the operator's real gates is neither hermetic nor bounded, and it wedged this file for two
  # minutes before it was pinned.
  export CC_DISCOVER_FRONTIER_LEDGER="$BATS_TEST_TMPDIR/absent-ledger.md"
  export CC_DISCOVER_GATES="$BATS_TEST_TMPDIR/absent-gate"
}

fals_of() { # <id> → the stored falsifier string, or empty
  "$BACKLOG_BIN" list --all --json 2>/dev/null \
    | jq -r --arg id "$1" '[.[]|select(.id==$id)][0].falsifier // ""'
}

# ─────────────────────────────────────────────────────────────────────────────────────────────────
# §1 EMISSION — each generator hands the item a probe at ADD time (or, for `needs`, honestly none)
# ─────────────────────────────────────────────────────────────────────────────────────────────────

@test "plan-open: cc-discover stores a falsifier on the item it mints" {
  d="$BATS_TEST_TMPDIR/c2"; mkdir -p "$d"
  printf -- '---\nstatus: open\n---\n\n# A Plan\n\n## Phase 1\n' > "$d/PLAN.md"
  cat > "$d/findplan" <<EOF
#!/bin/sh
[ "\$1" = "--list-open" ] || exit 2
printf 'OPEN | proj | %s | A Plan\n' "$d/PLAN.md"
EOF
  chmod +x "$d/findplan"
  CC_DISCOVER_PROJECT=proj CC_DISCOVER_FINDPLAN="$d/findplan" "$DISCOVER" --once >/dev/null 2>&1
  run "$BACKLOG_BIN" list --all --json
  [ "$status" -eq 0 ]
  n="$(printf '%s' "$output" | jq '[.[]|select(.source=="plan-open" and (.falsifier // "") != "")]|length')"
  [ "$n" -eq 1 ]
  probe="$(printf '%s' "$output" | jq -r '[.[]|select(.source=="plan-open")][0].falsifier')"
  [[ "$probe" == *"plan-phase-scan.sh"* ]] || false
  [[ "$probe" == *"--falsify"* ]] || false
  [[ "$probe" == *"$d/PLAN.md"* ]]
}

@test "plan-open: the stored probe is a RUNNABLE command, and it answers about THIS plan" {
  d="$BATS_TEST_TMPDIR/c2b"; mkdir -p "$d"
  printf -- '---\nstatus: open\n---\n\n# A Plan\n\n## Phase 1\n' > "$d/PLAN.md"
  cat > "$d/findplan" <<EOF
#!/bin/sh
[ "\$1" = "--list-open" ] || exit 2
printf 'OPEN | proj | %s | A Plan\n' "$d/PLAN.md"
EOF
  chmod +x "$d/findplan"
  CC_DISCOVER_PROJECT=proj CC_DISCOVER_FINDPLAN="$d/findplan" "$DISCOVER" --once >/dev/null 2>&1
  probe="$("$BACKLOG_BIN" list --all --json | jq -r '[.[]|select(.source=="plan-open")][0].falsifier')"
  # The probe addresses the LIVE layer ($HOME/.claude/scripts/...) rather than this checkout, so a
  # worktree that gets reaped cannot take the item's only question with it. Link it the way install.sh
  # does and run it exactly as cc-premise does — through `sh -c`, which is what makes the deferred
  # `$HOME` and the single-quoting load-bearing.
  ln -sf "$PLANSCAN" "$HOME/.claude/scripts/plan-phase-scan.sh"
  ln -sf "$REPO/scripts/find-plan.sh" "$HOME/.claude/scripts/find-plan.sh"
  run /bin/sh -c "$probe"
  [ "$status" -eq 1 ]                      # the plan still carries a PENDING section ⇒ still live
  printf -- '---\nstatus: open\n---\n\n# A Plan\n\n## Phase 1 DONE\n' > "$d/PLAN.md"
  run /bin/sh -c "$probe"
  [ "$status" -eq 0 ]                      # nothing left to advance ⇒ premise gone
}

@test "plan-open: a plan path containing a space survives the probe's SECOND parse" {
  d="$BATS_TEST_TMPDIR/c2 spaced"; mkdir -p "$d"
  printf -- '---\nstatus: open\n---\n\n# A Plan\n\n## Phase 1 DONE\n' > "$d/PLAN.md"
  cat > "$BATS_TEST_TMPDIR/findplan-sp" <<EOF
#!/bin/sh
[ "\$1" = "--list-open" ] || exit 2
printf 'OPEN | proj | %s | A Plan\n' "$d/PLAN.md"
EOF
  chmod +x "$BATS_TEST_TMPDIR/findplan-sp"
  CC_DISCOVER_PROJECT=proj CC_DISCOVER_FINDPLAN="$BATS_TEST_TMPDIR/findplan-sp" \
    "$DISCOVER" --once >/dev/null 2>&1
  probe="$("$BACKLOG_BIN" list --all --json | jq -r '[.[]|select(.source=="plan-open")][0].falsifier')"
  ln -sf "$PLANSCAN" "$HOME/.claude/scripts/plan-phase-scan.sh"
  ln -sf "$REPO/scripts/find-plan.sh" "$HOME/.claude/scripts/find-plan.sh"
  run /bin/sh -c "$probe"
  # WITHOUT the quoting this is rc 2 ("file not found") — a truncated path answering confidently.
  [ "$status" -eq 0 ]
}

@test "plan-open: an OLDER deployed plan-phase-scan.sh cannot forge a retraction" {
  # THE VERSION-SKEW HOLE, pinned. plan-phase-scan.sh takes FORMAT as a second positional with a
  # silent default, so a copy predating --falsify prints a section dump and EXITS 0 — which the
  # falsifier contract reads as "premise gone". The stand-in below is exactly that behaviour, and the
  # emitted probe must call it STILL LIVE, not retract the item it just minted.
  d="$BATS_TEST_TMPDIR/skew"; mkdir -p "$d"
  printf -- '---\nstatus: open\n---\n\n# A Plan\n\n## Phase 1\n' > "$d/PLAN.md"
  cat > "$d/findplan" <<EOF
#!/bin/sh
[ "\$1" = "--list-open" ] || exit 2
printf 'OPEN | proj | %s | A Plan\n' "$d/PLAN.md"
EOF
  chmod +x "$d/findplan"
  CC_DISCOVER_PROJECT=proj CC_DISCOVER_FINDPLAN="$d/findplan" "$DISCOVER" --once >/dev/null 2>&1
  probe="$("$BACKLOG_BIN" list --all --json | jq -r '[.[]|select(.source=="plan-open")][0].falsifier')"

  # The PRE-`--falsify` behaviour, reproduced: unknown second positional ⇒ JSON on stdout, exit 0.
  printf '#!/bin/sh\necho "{\\"sections\\": []}"\nexit 0\n' > "$HOME/.claude/scripts/plan-phase-scan.sh"
  chmod +x "$HOME/.claude/scripts/plan-phase-scan.sh"
  run /bin/sh -c "$probe"
  [ "$status" -ne 0 ] || false          # a 0 here is a live plan retracted by a stale binary

  # POSITIVE CONTROL — the same probe against the REAL scanner still retracts a finished plan, so
  # the guard above is not passing merely because the probe can never say yes.
  ln -sf "$PLANSCAN" "$HOME/.claude/scripts/plan-phase-scan.sh"
  ln -sf "$REPO/scripts/find-plan.sh" "$HOME/.claude/scripts/find-plan.sh"
  printf -- '---\nstatus: open\n---\n\n# A Plan\n\n## Phase 1 DONE\n' > "$d/PLAN.md"
  run /bin/sh -c "$probe"
  [ "$status" -eq 0 ]
}

@test "postland-verify: the three no-derived-arm sites build a probe carrying suite AND commit" {
  # The emission sites call fals_red; assert the string it produces, since driving a real
  # AUTO-REVERT/HUNG episode would need a broken trunk. The probe's own behaviour is §2's job.
  run bash -c "set -uo pipefail
    $(awk '/^fals_sq\(\)/,/^# .. --falsify-red/' "$POSTLAND" | sed '$d')
    fals_red tests/foo.bats abc1234def"
  [ "$status" -eq 0 ]
  [[ "$output" == *"postland-verify.sh"* ]] || false
  [[ "$output" == *"--falsify-red"* ]] || false
  [[ "$output" == *"'tests/foo.bats'"* ]] || false
  [[ "$output" == *"'abc1234def'"* ]]
}

@test "postland-verify: a missing half emits NOTHING rather than a half-formed probe" {
  run bash -c "set -uo pipefail
    $(awk '/^fals_sq\(\)/,/^# .. --falsify-red/' "$POSTLAND" | sed '$d')
    fals_red tests/foo.bats ''; echo \"rc=\$?\""
  [[ "$output" == "rc=1" ]]
}

@test "deploy-live: a single-suite failing set gets a probe; a multi-suite set gets none" {
  # Lift all three helpers together. A `/^fals_sq()/,/^}$/` range stops at the FIRST closing brace,
  # which is fals_host's — so fals_host_set never came across and the assertion below passed for the
  # wrong reason (an undefined function is rc 127, which is also non-zero).
  ext="set -uo pipefail
$(awk '/^fals_sq\(\)/,/^host_cut_row\(\)/' "$DEPLOY" | sed '$d')"
  run bash -c "$ext
    fals_host_set ' tests/a.bats(2)'"
  [[ "$output" == *"--falsify-host 'tests/a.bats'"* ]] || false
  # TWO suites, ONE probe subject — the item's premise is about the SET, so answering it with
  # evidence about one member is the two-meanings defect wearing a helpful face. Emit nothing.
  run bash -c "$ext
    fals_host_set ' tests/a.bats(2) tests/b.bats(1)'; echo \"rc=\$?\""
  [[ "$output" == "rc=1" ]]
}

@test "needs: no falsifier by default — an operator step has no oracle to fabricate" {
  id="$("$BACKLOG_BIN" needs 'authenticate the thing in /mcp' --project p)"
  [ -n "$id" ]
  [ -z "$(fals_of "$id")" ]
}

@test "needs: --run is NOT silently reused as a probe (it would DO the step, not ask about it)" {
  id="$("$BACKLOG_BIN" needs 'restart the daemon' --run 'launchctl kickstart -k x' --project p)"
  [ -z "$(fals_of "$id")" ]
}

@test "needs: a caller that HAS a real check can pass one, and it is stored verbatim" {
  id="$("$BACKLOG_BIN" needs 'authenticate X' --falsifier 'test -f /tmp/token && grep -q ok /tmp/token' --project p)"
  [ "$(fals_of "$id")" = 'test -f /tmp/token && grep -q ok /tmp/token' ]
}

# ─────────────────────────────────────────────────────────────────────────────────────────────────
# §2 ONE SUCCESS STATE — exit 0 is reachable ONLY where the item's premise is genuinely FALSE
# ─────────────────────────────────────────────────────────────────────────────────────────────────

# Each table below is `<state-label>|<premise>|<setup>`, premise ∈ FALSE (0 expected) · TRUE
# (non-zero) · UNKNOWN (non-zero — could not ask). A state with no row does not exist for the test,
# which is the point: adding a reachable state to a probe and not classifying it here fails.

assert_state() { # <label> <premise: FALSE|TRUE|UNKNOWN> <rc>
  case "$2" in
    FALSE)          [ "$3" -eq 0 ] || { echo "state '$1': premise is FALSE but rc=$3 (expected 0 — this probe can no longer retire a dead item)"; return 1; } ;;
    TRUE|UNKNOWN)   [ "$3" -ne 0 ] || { echo "state '$1': premise is $2 but rc=0 — exit 0 now means TWO things, and this probe will report DONE over live work"; return 1; } ;;
    *)              echo "unclassified premise '$2' for state '$1'"; return 1 ;;
  esac
}

@test "postland --falsify-red: exit 0 only where a covering green really exists" {
  # EVERY git call carries `-C "$R"`, and $R is a GUARDED argument with a literal suffix. Neither is
  # style: `cd ""` RETURNS 0 and `git -C ""` is a NO-OP, so an unset tmpdir would put these identity
  # writes into whatever repo the process is standing in — and ~100 worktrees on this box share ONE
  # .git/config, so one such call re-authors every session running. The land gate refused this file
  # for exactly that shape.
  R="${BATS_TEST_TMPDIR:?}/r"
  git init -q "$R"
  git -C "$R" config user.email t@t
  git -C "$R" config user.name t
  mkdir -p "$R/tests" "$R/scripts"
  printf 'ok\n' > "$R/tests/subject.bats"
  printf 'tests/hostonly.bats\n' > "$R/scripts/host-suites.manifest"
  printf 'ok\n' > "$R/tests/hostonly.bats"
  git -C "$R" add -A && git -C "$R" commit -qm base
  RED="$(git -C "$R" rev-parse HEAD)"
  printf 'more\n' >> "$R/tests/subject.bats"
  git -C "$R" add -A && git -C "$R" commit -qm after
  GREEN="$(git -C "$R" rev-parse HEAD)"
  export CC_POSTLAND_REPO="$R"
  LG="$CC_POSTLAND_DIR/last-green"

  # covering green ─ the ONLY premise-FALSE state
  printf '%s\n' "$GREEN" > "$LG"
  run bash "$POSTLAND" --falsify-red tests/subject.bats "$RED"
  assert_state "green contains the red commit, suite in corpus" FALSE "$status"

  # the unattributed subject: `tests/` IS the corpus, so a full green covers it by definition
  run bash "$POSTLAND" --falsify-red tests/ "$RED"
  assert_state "whole-corpus subject under a covering green" FALSE "$status"

  # still live ─ the green predates the red
  printf '%s\n' "$RED" > "$LG"
  run bash "$POSTLAND" --falsify-red tests/subject.bats "$GREEN"
  assert_state "the green does NOT contain the red commit" TRUE "$status"

  # could not ask ─ each of these WOULD have been a silent retraction if it returned 0
  printf '%s\n' "$GREEN" > "$LG"
  run bash "$POSTLAND" --falsify-red tests/hostonly.bats "$RED"
  assert_state "host suite — excluded from the corpus, so the green never ran it" UNKNOWN "$status"
  run bash "$POSTLAND" --falsify-red tests/absent-at-green.bats "$RED"
  assert_state "suite did not exist at the green" UNKNOWN "$status"
  rm -f "$LG"
  run bash "$POSTLAND" --falsify-red tests/subject.bats "$RED"
  assert_state "no last-green ledger at all" UNKNOWN "$status"
  printf 'not-a-sha\n' > "$LG"
  run bash "$POSTLAND" --falsify-red tests/subject.bats "$RED"
  assert_state "last-green is not a sha" UNKNOWN "$status"
  printf '%s\n' "$GREEN" > "$LG"
  run bash "$POSTLAND" --falsify-red tests/subject.bats deadbeefdeadbeef
  assert_state "the red sha does not resolve in this repo" UNKNOWN "$status"
  run bash "$POSTLAND" --falsify-red '' "$RED"
  assert_state "no suite named" UNKNOWN "$status"
  CC_POSTLAND_REPO="$BATS_TEST_TMPDIR/not-a-repo" run bash "$POSTLAND" --falsify-red tests/subject.bats "$RED"
  assert_state "repo unusable" UNKNOWN "$status"
}

@test "postland --falsify-red: the KILL SWITCH must not read as a retraction" {
  # main()'s POSTLAND_VERIFY=off arm exits 0, and under the falsifier contract exit 0 means "the
  # premise is gone". Beneath that arm, one env var would silently retract every item this script
  # has ever filed. This is the regression guard for the dispatch sitting ABOVE it.
  K="${BATS_TEST_TMPDIR:?}/k"            # guarded argument + literal suffix — see the sibling above
  git init -q "$K"
  git -C "$K" config user.email t@t
  git -C "$K" config user.name t
  mkdir -p "$K/tests"; printf 'ok\n' > "$K/tests/s.bats"
  git -C "$K" add -A; git -C "$K" commit -qm base
  export CC_POSTLAND_REPO="$K"
  printf '%s\n' "$(git -C "$K" rev-parse HEAD)" > "$CC_POSTLAND_DIR/last-green"
  POSTLAND_VERIFY=off run bash "$POSTLAND" --falsify-red tests/nope.bats deadbeefdeadbeef
  assert_state "kill switch on, question unanswerable" UNKNOWN "$status"
}

@test "deploy-live --falsify-host: exit 0 only where the live layer stopped running the suite" {
  export DEPLOY_REPO="$BATS_TEST_TMPDIR/dr"
  mkdir -p "$DEPLOY_REPO/tests" "$DEPLOY_REPO/scripts"
  export CC_HOST_MANIFEST="$DEPLOY_REPO/scripts/host-suites.manifest"
  printf '# c\ntests/live.bats\ntests/gone.bats\n' > "$CC_HOST_MANIFEST"
  printf 'ok\n' > "$DEPLOY_REPO/tests/live.bats"

  run bash "$DEPLOY" --falsify-host tests/live.bats
  assert_state "in the manifest and present in the deployed tree" TRUE "$status"
  run bash "$DEPLOY" --falsify-host tests/gone.bats
  assert_state "in the manifest but absent from the deployed tree" FALSE "$status"
  run bash "$DEPLOY" --falsify-host tests/never.bats
  assert_state "no longer in the manifest" FALSE "$status"
  run bash "$DEPLOY" --falsify-host
  assert_state "no suite named" UNKNOWN "$status"
  rm -f "$CC_HOST_MANIFEST"
  run bash "$DEPLOY" --falsify-host tests/live.bats
  # An ABSENT manifest is the EMPTY set for the VERIFIER's partition contract. Reading it that way
  # HERE would make every host suite "no longer run" and retract every item this script ever filed —
  # the same emptiness, opposite consequence, so the two consumers part company on it deliberately.
  assert_state "manifest unreadable" UNKNOWN "$status"
}

@test "plan-phase-scan --falsify: exit 0 only where the plan holds no work to advance" {
  d="$BATS_TEST_TMPDIR/p"; mkdir -p "$d"
  fp() { printf -- '---\nstatus: %s\n---\n\n# T\n\n%s\n' "$1" "$2" > "$d/$3"; }

  fp open  '## Phase 1'      pending.md
  run bash "$PLANSCAN" "$d/pending.md" --falsify
  assert_state "open plan with a PENDING section" TRUE "$status"

  fp open  '## Phase 1 DONE' done.md
  run bash "$PLANSCAN" "$d/done.md" --falsify
  assert_state "open plan whose every section is DONE" FALSE "$status"

  # Reached through clause (a) — the frontmatter. This is what keeps the emitted probe a strict
  # SUPERSET of cc-premise's derived plan arm, which it SHADOWS: cc-premise consults a derived arm
  # only when no stored probe exists, so a probe missing this state would have silently removed a
  # retraction that used to work (memory: cost-gate-must-be-strictly-weaker, in the fatal direction).
  fp complete   '## Phase 1' complete.md
  run bash "$PLANSCAN" "$d/complete.md" --falsify
  assert_state "plan declares itself complete" FALSE "$status"
  fp superseded '## Phase 1' superseded.md
  run bash "$PLANSCAN" "$d/superseded.md" --falsify
  assert_state "plan declares itself superseded" FALSE "$status"

  run bash "$PLANSCAN" "$d/absent.md" --falsify
  assert_state "plan file absent" UNKNOWN "$status"
  printf 'prose with no headings at all\n' > "$d/nosec.md"
  run bash "$PLANSCAN" "$d/nosec.md" --falsify
  # THE POSITIVE CONTROL. Without it, "the parser found nothing" and "every section is DONE" are the
  # same absence of a match, and the first would retract a live plan on a parser failure.
  assert_state "scanner found no sections at all" UNKNOWN "$status"
}

# ─────────────────────────────────────────────────────────────────────────────────────────────────
# §3 END TO END — the emitted probe is one cc-premise will actually re-run and act on
# ─────────────────────────────────────────────────────────────────────────────────────────────────

@test "cc-premise REFUSES a claim on an emitted probe's exit 0, and cites the re-run" {
  d="$BATS_TEST_TMPDIR/e2e"; mkdir -p "$d"
  printf -- '---\nstatus: open\n---\n\n# A Plan\n\n## Phase 1\n' > "$d/PLAN.md"
  cat > "$d/findplan" <<EOF
#!/bin/sh
[ "\$1" = "--list-open" ] || exit 2
printf 'OPEN | proj | %s | A Plan\n' "$d/PLAN.md"
EOF
  chmod +x "$d/findplan"
  CC_DISCOVER_PROJECT=proj CC_DISCOVER_FINDPLAN="$d/findplan" "$DISCOVER" --once >/dev/null 2>&1
  id="$("$BACKLOG_BIN" list --all --json | jq -r '[.[]|select(.source=="plan-open")][0].id')"
  [ -n "$id" ]
  ln -sf "$PLANSCAN" "$HOME/.claude/scripts/plan-phase-scan.sh"
  ln -sf "$REPO/scripts/find-plan.sh" "$HOME/.claude/scripts/find-plan.sh"
  export CC_PREMISE_REPO=""                       # the git arms are not the subject here

  run "$REPO/bin/cc-premise" check "$id"
  [ "$status" -eq 0 ]                             # the plan still holds work ⇒ the claim proceeds

  # The work finishes. NOTHING about the item changes — same title, same store — and the verdict
  # flips, which is the entire point of storing a probe rather than prose.
  printf -- '---\nstatus: open\n---\n\n# A Plan\n\n## Phase 1 DONE\n' > "$d/PLAN.md"
  run "$REPO/bin/cc-premise" check "$id"
  [ "$status" -eq 3 ]
  [[ "$output" == *"verdict=falsified"* ]] || false
  [[ "$output" == *"FALSIFIER PASSED"* ]]         # the RE-RUN arm, not a derived/prose one
}
