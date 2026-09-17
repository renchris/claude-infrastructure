#!/usr/bin/env bats
# G2 — the edge-triggered live-layer converge in ship-land.sh's post_release_finish()
# (backlog 193d63e30c82). Landing is the second-to-last step: ~/.claude is a per-file symlink
# farm over the SHARED CHECKOUT, so a landed commit executes nothing until that checkout
# fast-forwards. This suite owns the TRIGGER and, above all, ITS GUARD.
#
# WHY IT IS DRIVEN BY EXTRACTION: sourcing ship-land.sh would RUN the whole landing pipeline
# (the same reason _pfk_probe and _carveout_extract in tests/ship-land.bats do this). We extract
# the REAL post_release_finish from the REAL source and stub only its unrelated collaborators,
# so the code under test is the shipped text, never a paraphrase of it.
#
# WHY THE STUB IS A REAL FILE AT THE REAL PATH: the fire goes through python3 Popen with
# start_new_session, and what matters is that it lands in the right cwd with the right env. A
# fixture scripts/deploy-live.sh recording cwd+env proves that end to end, instead of asserting
# on the source text.
#
# TWO SPELLINGS HERE ARE FORCED BY hooks/validate-bash.sh, AND BOTH ARE THE BETTER FORM ANYWAY —
# recorded so nobody "tidies" them back and is then blocked with no idea why. (1) Fixture git
# identity is set with the transient `-c user.email=` form on each invocation, never
# `git config user.email`: this repo is one bare repo whose ~100 linked worktrees SHARE a single
# .git/config, so a persisting identity write re-authors every session on the machine. (2) File
# existence is asserted with `-e`: the git-add guard FLATTENS a heredoc before matching, so a
# `git add` on one line plus the regular-file flag on any later line reads as one argv and the
# write is refused — precisely the case the guard's own message says is "not this rule".

_ID=(-c user.email=tester@example.com -c user.name=tester)

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SHIPLAND="$REPO/scripts/ship-land.sh"

  # FIXTURE $HOME, FIRST — before anything here resolves a $HOME-relative path. The subject is
  # well behaved in this suite (DEPLOY_REPO and POSTLAND_DIR are both exported below, and the
  # block under test defaults DEPLOY_REPO to "$HOME/Development/claude-infrastructure"), but the
  # hermeticity lint keys on the setup() rather than on whether a write happened to occur, and it
  # is right to: a suite that CAN reach live state is one that will the next time the subject
  # grows a path. Here that risk is not hypothetical — an unfixtured run whose DEPLOY_REPO export
  # ever regressed would point the guard at the OPERATOR'S REAL SHARED CHECKOUT and, on the clean
  # branch, fire a real deploy-live from a test.
  # Load-bearing beyond this file: an unfixtured suite makes
  # `scripts/test-hermeticity-lint.sh --selftest` exit 1, which routes postland-verify to CUT
  # rather than GREEN (postland-verify.sh:3784-3785; :523 — "never a red, and NEVER A GREEN
  # either"), starving the green-only deploy tier. That is what 6eda05342 had just cured; this
  # suite must not re-open it.
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"

  # --- the LANDER's own repo (irrelevant to the guard, and that is the point: case 6) ----------
  WORK="$BATS_TEST_TMPDIR/work"
  git init -q "$WORK"
  cd "$WORK" || return 1
  echo base > "$WORK/base.txt"
  git -C "$WORK" add base.txt
  git -C "$WORK" "${_ID[@]}" commit -q -m base

  # --- the SHARED CHECKOUT fixture: a clone with a real origin, so `git cherry` is meaningful ---
  DLORIGIN="$BATS_TEST_TMPDIR/dl-origin.git"
  DLREPO="$BATS_TEST_TMPDIR/shared-checkout"
  git init -q --bare "$DLORIGIN"
  git clone -q "$DLORIGIN" "$DLREPO"
  git -C "$DLREPO" checkout -q -b main
  echo live > "$DLREPO/live.txt"
  git -C "$DLREPO" add live.txt
  git -C "$DLREPO" "${_ID[@]}" commit -q -m live-base

  MARKER="$BATS_TEST_TMPDIR/deploy-live-ran"
  mkdir -p "$DLREPO/scripts"
  cat > "$DLREPO/scripts/deploy-live.sh" <<STUB
#!/usr/bin/env bash
# fixture stub — records THAT it ran, WHERE, and with WHICH gating env.
{
  echo "cwd=\$PWD"
  echo "lag=\${CC_DEPLOY_MAX_LAG_COMMITS-<unset>}"
} > "$MARKER"
STUB
  chmod +x "$DLREPO/scripts/deploy-live.sh"
  git -C "$DLREPO" add scripts/deploy-live.sh
  git -C "$DLREPO" "${_ID[@]}" commit -q -m "fixture deploy-live"
  git -C "$DLREPO" push -q -u origin main     # pushed ⇒ the checkout is NOT diverged

  export DEPLOY_REPO="$DLREPO"
  export POSTLAND_DIR="$BATS_TEST_TMPDIR/postland"
  export POSTLAND_VERIFY=off
  export CLAUDE_CODE_SESSION_ID=""            # no --mine arg; keeps the sweep stub simple
  unset SHIP_LAND_BACKUP_REF SHIP_LAND_CONVERGE
}

_diverge() {   # give the shared checkout a commit the trunk does not have
  echo drift > "$DLREPO/drift.txt"
  git -C "$DLREPO" add drift.txt
  git -C "$DLREPO" "${_ID[@]}" commit -q -m "a commit the trunk does not have"
}

_extract_to() {  # $1=dest — the real function plus the collaborators it needs, stubbed
  {
    echo 'set -uo pipefail'
    echo 'post_state_read() { LANDED_HEAD="$(git rev-parse HEAD)"; }'
    echo 'attest_land() { :; }'
    echo 'STRANDED_SWEEP="/usr/bin/true"'
    echo 'SCRIPT_DIR="/nonexistent"'
    sed -n '/^post_release_finish() {/,/^}/p' "$SHIPLAND"
  } > "$1"
}

_probe() {
  local p="$BATS_TEST_TMPDIR/probe.sh"
  _extract_to "$p"
  grep -q 'live-layer converge' "$p" \
    || { echo "EXTRACTION MISS: post_release_finish did not carry the converge block"; return 1; }
  echo "$p"
}

_run_prf() {
  local probe; probe="$(_probe)" || return 1
  printf 'x\n' > "$BATS_TEST_TMPDIR/post-state"
  SHIP_LAND_POST_STATE="$BATS_TEST_TMPDIR/post-state" \
    bash -c 'source "$1"; post_release_finish "$2"' _ "$probe" "${1:-main}"
}

_settle() {  # the fire is DETACHED; wait for the marker rather than racing it
  local i=0
  while [ "$i" -lt 50 ]; do [ -e "$MARKER" ] && return 0; sleep 0.1; i=$((i+1)); done
  return 1
}

# ── 1 · THE RED-PROOF: a clean shared checkout gets converged, detached ───────────────────────
# Pre-diff there is no fire at all, so both the marker and the message are absent: red before,
# green after.
@test "clean shared checkout: the converge fires, detached, in the right cwd" {
  run _run_prf main
  [ "$status" -eq 0 ]
  [[ "$output" == *"live-layer converge kicked"* ]] || false
  _settle || { echo "deploy-live stub never ran; output: $output"; false; }
  # macOS resolves /var -> /private/var, so the stub's $PWD is the RESOLVED path. Compare
  # resolved-to-resolved; weakening this to a suffix match would stop pinning the cwd at all.
  local want; want="$(cd "$DLREPO" && pwd -P)"
  grep -q "cwd=$want" "$MARKER" || { echo "want cwd=$want"; cat "$MARKER"; false; }
}

# ── 2 · the gating env is the DEGRADED tier, never --force ────────────────────────────────────
@test "the fire passes CC_DEPLOY_MAX_LAG_COMMITS=0 and never forces" {
  run _run_prf main
  [ "$status" -eq 0 ]
  _settle
  grep -q '^lag=0$' "$MARKER" || { cat "$MARKER"; false; }
  [[ "$output" != *"force"* ]]
}

# ── 3 · THE GUARD, AND THE REASON THIS SUITE EXISTS ───────────────────────────────────────────
# A diverged shared checkout cannot fast-forward, so firing would cost a GUARANTEED refusal on
# every land. Asserting only "no marker" would be VACUOUS — equally true of a tree with no
# feature at all. The load-bearing half is the WARNING, absent pre-diff, so this is a genuine
# red-proof of the GUARD and not merely of the trigger.
@test "diverged shared checkout: the converge is SKIPPED and says so" {
  _diverge
  run _run_prf main
  [ "$status" -eq 0 ]
  [[ "$output" == *"converge NOT kicked"* ]] || false
  [[ "$output" == *"cherry"* ]] || false        # names the command that inspects it
  [[ "$output" != *"converge kicked (detached"* ]] || false
  sleep 0.5
  [ ! -e "$MARKER" ] || { echo "FIRED INTO A DIVERGED CHECKOUT"; cat "$MARKER"; false; }
}

# ── 4 · the land itself is never turned red by any of this ────────────────────────────────────
@test "a diverged checkout does not fail the land" {
  _diverge
  run _run_prf main
  [ "$status" -eq 0 ]
  [[ "$output" == *"LANDED"* ]]
}

# ── 5 · FAIL-CLOSED: every way the predicate can break must SKIP, never fire ──────────────────
# A non-git DEPLOY_REPO makes `git cherry` exit non-zero. The && chain must swallow that into a
# skip rather than read an unreadable predicate as permission to proceed.
@test "a non-git DEPLOY_REPO skips the fire and does not fail the land" {
  export DEPLOY_REPO="$BATS_TEST_TMPDIR/not-a-repo"
  mkdir -p "$DEPLOY_REPO/scripts"
  cp "$DLREPO/scripts/deploy-live.sh" "$DEPLOY_REPO/scripts/deploy-live.sh"
  run _run_prf main
  [ "$status" -eq 0 ]
  [[ "$output" == *"LANDED"* ]] || false
  sleep 0.5
  [ ! -e "$MARKER" ]
}

@test "an absent deploy-live.sh skips the fire and does not fail the land" {
  rm "$DLREPO/scripts/deploy-live.sh"
  run _run_prf main
  [ "$status" -eq 0 ]
  [[ "$output" == *"LANDED"* ]] || false
  [[ "$output" != *"converge kicked"* ]]
}

# ── 6 · THE PREDICATE READS THE SHARED CHECKOUT, NOT THE LANDER ───────────────────────────────
# The lander's own worktree is ALWAYS ahead of its origin at this point — that is what it just
# landed. A guard reading `git cherry` HERE instead of `git -C $DEPLOY_REPO` would answer a
# different question and skip every time. This pins which repo the predicate is about.
@test "a lander ahead of its own origin still converges a clean shared checkout" {
  echo more > "$WORK/more.txt"
  git -C "$WORK" add more.txt
  git -C "$WORK" "${_ID[@]}" commit -q -m "unpushed work in the LANDER's tree"
  run _run_prf main
  [ "$status" -eq 0 ]
  [[ "$output" == *"live-layer converge kicked"* ]] || false
  _settle || { echo "lander-local state wrongly suppressed the fire"; false; }
}

# ── 7 · kill switch. Green in BOTH arms by construction (pre-diff nothing fires either), so this
# is an EQUIVALENCE GUARD, not a red-proof: it pins that the switch is honoured once the feature
# exists. Its power is demonstrated by the mutant in case 8, never by this case alone.
@test "SHIP_LAND_CONVERGE=off suppresses the fire" {
  export SHIP_LAND_CONVERGE=off
  run _run_prf main
  [ "$status" -eq 0 ]
  [[ "$output" != *"converge kicked"* ]] || false
  sleep 0.5
  [ ! -e "$MARKER" ]
}

# ── 8 · MUTANT CONTROL: delete the guard and case 3 MUST go red ───────────────────────────────
# Case 3 alone cannot prove the guard is load-bearing. This removes ONLY the cherry predicate —
# the file stays intact and the feature stays present, since a mutant that breaks the syntax
# attributes nothing — and requires the diverged checkout to then be fired into.
@test "MUTANT: removing the cherry guard fires into a diverged checkout" {
  _diverge
  local mutant="$BATS_TEST_TMPDIR/mutant.sh"
  _extract_to "$BATS_TEST_TMPDIR/pristine.sh"
  sed 's|dl_cherry="$(git -C "$dl_repo" cherry origin/"$TRUNK" HEAD 2>/dev/null)"|dl_cherry=""|' \
    "$BATS_TEST_TMPDIR/pristine.sh" > "$mutant"
  # the mutation must have APPLIED — a mutant anchored on a string that moved proves nothing
  grep -q 'dl_cherry=""' "$mutant" || { echo "MUTATION DID NOT APPLY"; false; }
  # NOT `grep cherry origin/` — the block's comment and its warning string both carry that
  # phrase, so it cannot separate the executable guard from prose. Anchor on the assignment.
  if grep -q 'dl_cherry="\$(git' "$mutant"; then echo "MUTATION DID NOT REMOVE THE GUARD"; false; fi

  printf 'x\n' > "$BATS_TEST_TMPDIR/post-state"
  SHIP_LAND_POST_STATE="$BATS_TEST_TMPDIR/post-state" \
    bash -c 'source "$1"; post_release_finish main' _ "$mutant" >/dev/null 2>&1
  _settle || { echo "mutant did not fire — case 3 is NOT credited to the guard"; false; }
}
