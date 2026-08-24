#!/usr/bin/env bats
# deploy-live.sh — green-stamp-gated advance of the live layer (+ the nightly postland-inertness
# guard). Fully isolated: a bare "origin" + a "shared" clone under BATS_TEST_TMPDIR, a fixture
# stamps dir, and an install.sh stub that records its invocation. No real checkout is touched.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  DL="$REPO/scripts/deploy-live.sh"
  NIGHTLY="$REPO/scripts/nightly-regression.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"   # hermetic: never touch the live ~/
  ORIGIN="$BATS_TEST_TMPDIR/origin.git"
  SHARED="$BATS_TEST_TMPDIR/shared"
  STAMPS="$BATS_TEST_TMPDIR/postland/stamps"
  PAGES="$BATS_TEST_TMPDIR/pages"
  INSTALL_LOG="$BATS_TEST_TMPDIR/install.invoked"
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@x GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@x
  git init -q --bare "$ORIGIN"
  git init -q "$SHARED"; git -C "$SHARED" remote add origin "$ORIGIN"
  commit_push a
  git -C "$SHARED" branch -M main 2>/dev/null || true
  git -C "$SHARED" push -q -u origin main
  mkdir -p "$STAMPS"
  printf '#!/bin/bash\necho ran >> "%s"\n' "$INSTALL_LOG" > "$SHARED/install.sh"
  chmod +x "$SHARED/install.sh"
}

commit_push() { # <name> — commit in the shared clone (caller pushes when it wants origin ahead)
  echo "$1" > "$SHARED/$1.txt"; git -C "$SHARED" add -A; git -C "$SHARED" commit -q -m "$1"
}

stamp() { # <rev> [verdict]
  local tree; tree="$(git -C "$SHARED" rev-parse "$1^{tree}")"
  printf '{"verdict":"%s","tree":"%s"}\n' "${2:-green}" "$tree" > "$STAMPS/$tree.json"
}

# /bin/bash EXPLICITLY, not PATH's bash: com.claude.deploy-live.plist execs /bin/bash, which on macOS
# is 3.2, and 3.2 mis-parses constructs a homebrew bash 5 on PATH accepts silently (a `case` pattern's
# `)` inside a $( ) closes the substitution). Testing under a different bash than the job runs is how
# such a bug reaches production green — one did, in bin/cc-blockers, on 2026-07-28.
dl() { env DEPLOY_REPO="$SHARED" CC_POSTLAND_DIR="$BATS_TEST_TMPDIR/postland" \
           CC_PAGES_DIR="$PAGES" /bin/bash "$DL" "$@"; }

# dl against a MUTATED copy of the subject — arm 2 of a red-proof. The mutant is built by `sed` over
# the WORKING TREE, never by replaying a ref: a branch name would compare the fix to itself and pass
# for its author every time (moving-ref-control-lint refuses that shape). Each caller counts its
# anchor BEFORE and AFTER the substitution, so a rename of the mutated site reds the anchor instead
# of quietly producing a mutant byte-identical to the subject.
dlm() { # <mutant-path> [args…]
  local m="$1"; shift
  env DEPLOY_REPO="$SHARED" CC_POSTLAND_DIR="$BATS_TEST_TMPDIR/postland" \
      CC_PAGES_DIR="$PAGES" /bin/bash "$m" "$@"
}

# advance origin/main by N commits while the clone's HEAD stays put (the deploy-lag shape)
advance_origin() { # <name...>
  local head; head="$(git -C "$SHARED" rev-parse HEAD)"
  for n in "$@"; do commit_push "$n"; done
  git -C "$SHARED" push -q origin main
  git -C "$SHARED" reset -q --hard "$head"
}

@test "ff stops at the newest STAMPED ancestor (two un-stamped commits on top)" {
  advance_origin b c d
  stamp "origin/main~2"                       # b is green; c,d un-stamped
  want="$(git -C "$SHARED" rev-parse origin/main~2)"
  run dl
  [ "$status" -eq 0 ]
  [ "$(git -C "$SHARED" rev-parse HEAD)" = "$want" ]
  echo "$output" | grep -q "2 un-stamped commit"
}

@test "at trunk tip with NO green anywhere: exit 0 silently, never a refusal" {
  # L10 (lead-added, from the first live v2 evaluation 2026-08-07). The layer sits exactly on
  # origin/main and NO stamp exists at or above it, so every tier's candidate set is empty and the
  # ladder used to fall through to T3's die — reporting "nothing is safe to deploy" about a set that
  # was simply EMPTY, and exiting 1. At the healthy steady state that is 144 refusals/day and
  # launchctl pinned at exit 1, which is the signal that hid the original 33h freeze.
  # No stamp at all here, deliberately: it proves the exit is keyed on TIP, not on stamp state.
  before="$(git -C "$SHARED" rev-parse HEAD)"
  run dl
  [ "$status" -eq 0 ] || false
  echo "$output" | grep -q "at trunk tip" || false
  echo "$output" | grep -qv "REFUSED" || false
  [ "$(git -C "$SHARED" rev-parse HEAD)" = "$before" ] || false
}

@test "at trunk tip while the newest green is BEHIND: still exit 0, not a rollback refusal" {
  # L10b. The exact live shape on 2026-08-07: HEAD == tip, and the only green tree is an ancestor.
  # The old ladder reached the anti-rollback guard and refused; there is nothing above the layer, so
  # the correct verdict is completion. Distinct from L10 because a stamp EXISTS here — if the at-tip
  # exit were ever keyed on "no green found" instead of on TIP, this case would regress and L10 would
  # not catch it.
  stamp HEAD                                   # green on the tree we are already on
  advance_origin c                             # trunk moves...
  git -C "$SHARED" merge -q --ff-only origin/main   # ...and the layer follows it to the tip
  before="$(git -C "$SHARED" rev-parse HEAD)"
  run dl
  [ "$status" -eq 0 ] || false
  echo "$output" | grep -q "at trunk tip" || false
  [ "$(git -C "$SHARED" rev-parse HEAD)" = "$before" ] || false
}

@test "already deployed: HEAD is the newest green — exit 0, no merge" {
  advance_origin b
  stamp HEAD                                   # the commit we are already on
  before="$(git -C "$SHARED" rev-parse HEAD)"
  run dl
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "already deployed"
  [ "$(git -C "$SHARED" rev-parse HEAD)" = "$before" ]
}

@test "no green stamp within the scan window: refuses, writes an epoch-headed page, HEAD unmoved" {
  advance_origin b c
  before="$(git -C "$SHARED" rev-parse HEAD)"
  run dl
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "REFUSED"
  tip="$(git -C "$SHARED" rev-parse origin/main | cut -c1-12)"
  [ -f "$PAGES/deploy-blocked-$tip.page" ]
  head -1 "$PAGES/deploy-blocked-$tip.page" | grep -qE '^[0-9]+$'
  [ "$(git -C "$SHARED" rev-parse HEAD)" = "$before" ]
}

@test "a RED-verdict stamp is not green — still refuses" {
  advance_origin b
  stamp origin/main red
  run dl
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "no GREEN stamp"
}

@test "stamps dir ABSENT: refuses without --bootstrap" {
  advance_origin b
  rm -rf "$BATS_TEST_TMPDIR/postland"
  run dl
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "verification net is not active"
}

@test "--bootstrap with no stamps dir deploys the tip under a loud UNSTAMPED banner" {
  advance_origin b
  rm -rf "$BATS_TEST_TMPDIR/postland"
  run dl --bootstrap
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "UNSTAMPED bootstrap deploy"
  [ "$(git -C "$SHARED" rev-parse HEAD)" = "$(git -C "$SHARED" rev-parse origin/main)" ]
}

@test "--force overrides the gate when stamps exist but nothing is green" {
  advance_origin b c
  run dl --force
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "gate BYPASSED"
  [ "$(git -C "$SHARED" rev-parse HEAD)" = "$(git -C "$SHARED" rev-parse origin/main)" ]
}

@test "--dry-run mutates nothing (no merge, no install, no page)" {
  advance_origin b c
  before="$(git -C "$SHARED" rev-parse HEAD)"
  run dl --dry-run                              # nothing green → decision is a refusal
  [ "$status" -eq 1 ]
  [ ! -e "$PAGES" ]
  stamp origin/main
  run dl --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "DRY RUN"
  [ "$(git -C "$SHARED" rev-parse HEAD)" = "$before" ]
  [ ! -f "$INSTALL_LOG" ]
}

# NARROWED 2026-08-07, deliberately NOT deleted. As written this test pinned the LIVE DEADLOCK as
# correct behaviour: "newest green is behind live HEAD ⇒ refuse", with no budget in the fixture and
# so no way for the refusal ever to end. Left as-is it would have become a guard on the bug the
# two-tier rebuild exists to remove. It now pins the half that IS still correct — inside the staleness
# budget the lane still refuses — and its PAST-BUDGET sibling (L2, at the foot of this file) pins the
# other half against the identical fixture, so the pair is a clean A/B on exactly one variable.
#
# FLIPPED 2026-08-10 (backlog 2e7fe6fd5b7c), and the A/B pair with L2 is intact — only the in-budget
# arm's verdict changed, from `refuse` to `wait`. The 2026-08-07 narrowing kept the refusal because
# the face it was fixing was the lag-0 one; it never asked whether an in-budget refusal was itself
# the defect. It is. MEASURED on the live box: live HEAD 5f63cdc1 with the newest green ed095d4b one
# step behind it, lag 24 commit(s) / 5h against a 25 / 6h budget — inside on BOTH axes — refused and
# wrote a page reading "the live layer is FROZEN until a tree verifies green", which dispatched a
# work item onto a state that was not frozen, had not tripped its budget, and would degrade through
# T2 of its own accord within the hour. `die` exiting 1 through the healthy steady state is the same
# cost the at-tip fix names at deploy-live.sh:790 — the lane pinned at exit 1 until a real refusal
# is indistinguishable from the noise. The two assertions that carry the SUBJECT are unchanged: the
# tree must not move, and the diagnosis must still be stated.
@test "WITHIN BUDGET: newest green is BEHIND the live HEAD ⇒ WAITS (exit 0), tree unmoved" {
  deadlock                                      # green behind live HEAD; trunk 2 ahead
  before="$(git -C "$SHARED" rev-parse HEAD)"
  run dl                                        # default budget 25 commits / 6h — 2 commits is inside it
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "DESCENDANT of live HEAD"   # the diagnosis survives the benign exit
  echo "$output" | grep -qv "REFUSED"
  [ "$(git -C "$SHARED" rev-parse HEAD)" = "$before" ]
  # and no page is minted for a state that is inside its own budget — the page IS the false alarm
  [ -z "$(ls -A "$PAGES" 2>/dev/null)" ]
}

@test "install.sh is invoked on a successful deploy" {
  advance_origin b
  stamp origin/main
  run dl
  [ "$status" -eq 0 ]
  [ -f "$INSTALL_LOG" ]
  echo "$output" | grep -q "install.sh ok"
}

@test "fetch failure is loud and fatal (bad remote)" {
  advance_origin b
  stamp origin/main
  git -C "$SHARED" remote set-url origin "$BATS_TEST_TMPDIR/does-not-exist.git"
  run dl
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "git fetch origin main FAILED"
}

@test "non-repo DEPLOY_REPO refuses" {
  run env DEPLOY_REPO="$BATS_TEST_TMPDIR/nope" CC_POSTLAND_DIR="$BATS_TEST_TMPDIR/postland" \
      CC_PAGES_DIR="$PAGES" bash "$DL"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "not a git checkout"
}

# ── nightly-regression postland_inertness (env-seam wired, stubbed check-set) ──────────────────
nightly() { # runs the nightly with every other check stubbed green
  mkdir -p "$BATS_TEST_TMPDIR/gt" "$BATS_TEST_TMPDIR/empty"
  printf '#!/usr/bin/env bats\n@test "ok" { true; }\n' > "$BATS_TEST_TMPDIR/gt/ok.bats"
  printf '<?xml version="1.0"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict/></plist>\n' \
    > "$BATS_TEST_TMPDIR/good.plist"
  env CC_NIGHTLY_NOTIFY=/usr/bin/true CC_NIGHTLY_NEVERSTUCK=/usr/bin/true CC_NIGHTLY_ABSTAIN=/usr/bin/true \
      CC_NIGHTLY_GATE_GLOB="$BATS_TEST_TMPDIR/empty/*.sh" CC_NIGHTLY_LINT_GLOB="$BATS_TEST_TMPDIR/empty/*.sh" \
      CC_NIGHTLY_BATS_DIR="$BATS_TEST_TMPDIR/gt" CC_NIGHTLY_PLIST_GLOB="$BATS_TEST_TMPDIR/good.plist" \
      CC_NIGHTLY_PAGEDIR="$PAGES" CC_NIGHTLY_LOG="$BATS_TEST_TMPDIR/reg.log" \
      CC_NIGHTLY_REPO="$SHARED" CC_NIGHTLY_POSTLAND_DIR="$1" CC_NIGHTLY_POSTLAND_AGE=0 \
      CC_NIGHTLY_POSTLAND_VERIFY="${PV_STUB:-/usr/bin/true}" \
      bash "$NIGHTLY"
}

# ── nightly step 3c: the post-land verifier's OWN instrument (item cb8b9620ddef) ─────────────────
# The seam above is stubbed rather than left to default, and that is not tidiness: step 3c runs
# scripts/postland-verify.sh --selftest, which lands fixture commits and runs a real bats corpus —
# 424s measured. Defaulted, the two inertness tests above would each pay it to assert nothing.
#
# WHY THESE LIVE HERE AND NOT ONLY IN nightly-regression --selftest. That selftest matches neither
# *gate*.sh nor *lint*.sh either, so nothing schedules it — a guard written only there would rot the
# same way the thing it guards did. `bats tests/` IS step 1 of the nightly and the post-land corpus,
# so the guard belongs in the corpus. Their subject is this file's own subject one step on: step 5
# (postland-inertness, above) abstains on exactly one fact, the stamps dir not existing, and step 3c
# is the one check in the job that can create it.
pv_stub() { # <name> <body…> → an executable stand-in for postland-verify.sh, path on stdout
  local n="$1"; shift
  mkdir -p "$BATS_TEST_TMPDIR/pv"
  { printf '#!/bin/bash\n'; printf '%s\n' "$@"; } > "$BATS_TEST_TMPDIR/pv/$n"
  chmod +x "$BATS_TEST_TMPDIR/pv/$n"
  printf '%s' "$BATS_TEST_TMPDIR/pv/$n"
}

@test "nightly 3c: postland-verify --selftest is RUN, with the flag and a sandboxed state dir" {
  advance_origin b
  # The stub reds unless it got both. `case $HOME` is the sandbox predicate stated the way the
  # defect states it: postland-verify's main() runs ensure_dirs BEFORE dispatch, so every $HOME-
  # rooted knob must be moved or a bare --selftest writes into live state.
  PV_STUB="$(pv_stub pv-ok.sh \
    '[ "${1:-}" = "--selftest" ] || { echo "no --selftest flag"; exit 1; }' \
    '[ -n "${CC_POSTLAND_DIR:-}" ] || { echo "UNSANDBOXED: CC_POSTLAND_DIR unset"; exit 1; }' \
    'case "$CC_POSTLAND_DIR" in "$HOME"/*) echo "UNSANDBOXED: live state"; exit 1 ;; esac' \
    'mkdir -p "$CC_POSTLAND_DIR/stamps"' \
    'echo "postland-verify selftest: 53 passed, 0 failed"')"
  export PV_STUB
  run nightly "$BATS_TEST_TMPDIR/no-such-postland"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "ok   postland-verify.sh --selftest"
}

@test "nightly 3c: the instrument check does NOT manufacture step 5's postland-inertness RED" {
  advance_origin b
  # The incident this pair exists for: 3c writes $CC_POSTLAND_DIR/stamps, step 5 green-abstains only
  # while that dir is absent. Unsandboxed, night one creates it and every night after reds over a net
  # the box never adopted. Both verdicts are read from ONE run — separately, the manufactured red
  # would not appear until the second night, which is what makes this class survive review.
  PV_STUB="$(pv_stub pv-mkdir.sh \
    'mkdir -p "${CC_POSTLAND_DIR:?CC_POSTLAND_DIR unset — the check is unsandboxed}/stamps"' \
    'echo "postland-verify selftest: 53 passed, 0 failed"')"
  export PV_STUB
  run nightly "$BATS_TEST_TMPDIR/no-such-postland"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "ok   postland-verify.sh --selftest"
  echo "$output" | grep -q "ok   postland-inertness"
  [ ! -d "$BATS_TEST_TMPDIR/no-such-postland/stamps" ]
}

@test "nightly 3c: a FAILING instrument reds the night and its detail reaches the page" {
  # ANTI-VACUITY for the pair above: both pass just as well against a check that is launched and then
  # ignored. Only a stub that fails proves its verdict reaches the night's.
  advance_origin b
  PV_STUB="$(pv_stub pv-red.sh 'echo "postland-verify selftest: 52 passed, 1 failed"' 'exit 1')"
  export PV_STUB
  run nightly "$BATS_TEST_TMPDIR/no-such-postland"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "RED  postland-verify.sh --selftest"
  grep -q "52 passed, 1 failed" "$PAGES/nightly-regression.page"
}

@test "nightly 3c: POSTLAND_VERIFY=off SKIPS the check — a kill switch is not a green" {
  # postland-verify exits 0 above its own dispatch when killed, so a bare run would score `ok` having
  # proven nothing. The stub reds if it is reached at all, so a skip is the only way this passes.
  advance_origin b
  PV_STUB="$(pv_stub pv-red.sh 'echo reached; exit 1')"
  export PV_STUB POSTLAND_VERIFY=off
  run nightly "$BATS_TEST_TMPDIR/no-such-postland"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "skip postland-verify.sh --selftest"
  ! echo "$output" | grep -q "ok   postland-verify.sh --selftest" || false
  grep -q "postland-verify.sh:kill-switched" "$BATS_TEST_TMPDIR/reg.log"
}

@test "nightly postland-inertness: RED when the net exists but a settled trunk commit is unstamped" {
  advance_origin b
  run nightly "$BATS_TEST_TMPDIR/postland"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "RED  postland-inertness"
  grep -q "postland net INERT" "$PAGES/nightly-regression.page"   # the page carries WHY, not just the name
}

@test "nightly postland-inertness: green-abstains when the stamps dir does not exist" {
  advance_origin b
  run nightly "$BATS_TEST_TMPDIR/no-such-postland"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "ok   postland-inertness"
}

# ── nightly step 5b: postland-green-starvation (backlog 01ab05685857) ────────────────────────────
# The condition step 5 cannot see. It keys on a stamp EXISTING, and the producer's own vocabulary
# calls a `cut` "no verdict" — so a net that stamps every tick and never earns a green reads ALIVE
# there while trunk goes unproven. Measured on the box as three breaches of the 24h budget
# (57h/53h/26h), none of which paged. Every test below asserts BOTH check names off ONE run: the
# whole claim is that the two verdicts DISAGREE, and either one alone is satisfied by a check that
# simply mirrors the other.
commit_at() { # <name> <epoch> — a trunk commit with a CHOSEN clock (the quantity 5b measures)
  echo "$1" > "$SHARED/$1.txt"; git -C "$SHARED" add -A
  GIT_AUTHOR_DATE="$2 +0000" GIT_COMMITTER_DATE="$2 +0000" \
    git -C "$SHARED" commit -q -m "$1"
  git -C "$SHARED" push -qf origin gs:main
}

# EVERY commit's clock has to be ours, ROOT INCLUDED, or these tests silently stop discriminating.
# setup()'s `a` is dated NOW, so on a trunk built on top of it the OLDEST unproven commit is always
# ~0s old — and an implementation that walks straight past a green (i.e. one keyed on the newest
# green's AGE, which is what this check must NOT be) abstains for that reason alone. Measured while
# writing these: the mutant survived tests 2 and 3 until trunk started from an orphan.
new_trunk() { # <name> <epoch> — replace origin/main with a history whose every clock is chosen here
  git -C "$SHARED" checkout -q --orphan gs
  commit_at "$1" "$2"
}

offbox_green() { # <rev> — the off-box lane's WEAKER acquittal, in its own store
  local tree; tree="$(git -C "$SHARED" rev-parse "$1^{tree}")"
  mkdir -p "$BATS_TEST_TMPDIR/postland/offbox"
  printf '{"verdict":"green","scope":"offbox-hermetic","tree":"%s"}\n' "$tree" \
    > "$BATS_TEST_TMPDIR/postland/offbox/$tree.json"
}

starved_trunk() { # a green 3d back, then two RED-stamped commits landed 2d ago
  local old=$(( $(date +%s) - 3 * 86400 )) mid=$(( $(date +%s) - 2 * 86400 ))
  new_trunk base "$old"; stamp origin/main green
  commit_at r1 "$mid"; stamp origin/main red
  commit_at r2 "$mid"; stamp origin/main red
}

@test "nightly 5b: RED when trunk carries UNPROVEN content past the green budget" {
  starved_trunk
  run nightly "$BATS_TEST_TMPDIR/postland"
  [ "$status" -ne 0 ]
  # THE PAIR, off one run: step 5 is SATISFIED by the red stamps (the net is demonstrably running)
  # and 5b still reds. A single-verdict assertion here would pass against a copy of step 5.
  echo "$output" | grep -q "ok   postland-inertness" || false
  echo "$output" | grep -q "RED  postland-green-starvation" || false
  grep -q "postland net GREEN-STARVED" "$PAGES/nightly-regression.page" || false
  grep -q "newest verdict over that span: red" "$PAGES/nightly-regression.page" || false
  grep -q "2 commit(s) sit above the newest green" "$PAGES/nightly-regression.page" || false
}

@test "nightly 5b: an ANCIENT green on the trunk TIP abstains — the quiet-trunk control" {
  # The control that separates this check from the row's own wording. Stamps are TREE-keyed and a
  # proven tree is deliberately never re-run, so a trunk that has not moved for a week keeps a
  # week-old newest green and is FULLY proven the whole time. An implementation keyed on "newest
  # green stamp age" — which is what the row says — reds here, on a healthy machine.
  new_trunk old7 "$(( $(date +%s) - 7 * 86400 ))"; stamp origin/main green
  run nightly "$BATS_TEST_TMPDIR/postland"
  [ "$status" -eq 0 ] || false
  echo "$output" | grep -q "ok   postland-green-starvation" || false
}

@test "nightly 5b: a YOUNG unproven span abstains — the budget is a budget, not a tripwire" {
  # Trunk moved ten minutes ago after a long quiet spell: the newest green is 3 days old and nothing
  # is wrong. Only the span nothing has re-proven is old enough to convict, and it is 600s here.
  new_trunk base "$(( $(date +%s) - 3 * 86400 ))"; stamp origin/main green
  commit_at fresh "$(( $(date +%s) - 600 ))"
  run nightly "$BATS_TEST_TMPDIR/postland"
  echo "$output" | grep -q "ok   postland-green-starvation" || false
}

@test "nightly 5b: a stamps dir that has NEVER stamped is step 5's fact, not 5b's" {
  # Two checks paging over one repair is the noise that gets a nightly ignored. The dir exists
  # (setup mints it) and is empty, so step 5 reds on it and 5b says nothing at all.
  advance_origin b
  run nightly "$BATS_TEST_TMPDIR/postland"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "RED  postland-inertness" || false
  echo "$output" | grep -q "ok   postland-green-starvation" || false
}

@test "nightly 5b: green-abstains when the net is not adopted (no stamps dir)" {
  advance_origin b
  run nightly "$BATS_TEST_TMPDIR/no-such-postland"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "ok   postland-green-starvation" || false
}

@test "nightly 5b: an off-box acquittal is REPORTED and never cancels the red" {
  # The off-box lane proves a hermetic SUBSET, so it cannot acquit the host-coupled suites this
  # check is about — but which of the two it is changes the repair entirely, so the page says so.
  # Anti-laundering: if a file drop under offbox/ could turn this green, the weaker claim would
  # silently become the stronger one, which is the exact reason it lives in its own store.
  starved_trunk
  offbox_green origin/main
  run nightly "$BATS_TEST_TMPDIR/postland"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "RED  postland-green-starvation" || false
  grep -q "off-box acquittal: yes, off-box hermetic green from" "$PAGES/nightly-regression.page" || false
}

@test "nightly 5b: a bare file drop under offbox/ is NOT an acquittal (both fields, or neither)" {
  starved_trunk
  local tree; tree="$(git -C "$SHARED" rev-parse origin/main^{tree})"
  mkdir -p "$BATS_TEST_TMPDIR/postland/offbox"
  printf '{"verdict":"green","tree":"%s"}\n' "$tree" > "$BATS_TEST_TMPDIR/postland/offbox/$tree.json"
  run nightly "$BATS_TEST_TMPDIR/postland"
  grep -q "off-box acquittal: none" "$PAGES/nightly-regression.page" || false
}

# ── --auto autopilot (LAND_PIPELINE_V2 §4.3) ─────────────────────────────────────────────────────
# EVERY `[[ ]]` below carries `|| false`. Not style — a non-final `[[ ]]` is errexit-EXEMPT under
# bats, so it is a DEAD assertion that can never fail its test (`[ ]` and simple commands ARE live).
# Measured here 2026-07-28: without it, the --force/--bootstrap test passed against the PRE-Phase-A
# script, because that script also exits 2 on an unknown `--auto` arg and the only assertion that
# could tell the two apart was the dead one. Do not strip the `|| false`.
# Every seam is fixtured, so nothing here runs a real suite or touches the live layer:
#   CC_DEPLOY_BATS_BIN  → a SPY that records the suite it was handed and returns a verdict keyed on
#                         the suite NAME, so red/cut/green are deterministic without control files.
#   CC_BACKLOG_BIN      → a spy recording the packet argv.
#   CC_DEPLOY_TIMEOUT_BIN= → SET-EMPTY, the script's documented disable. Deliberate: a suite that
#                         resolved the real timeout(1) would encode whether coreutils happens to be
#                         installed on the host running it, which is not what these tests assert.
auto_setup() {
  export CC_SPY_LOG="$BATS_TEST_TMPDIR/bats.spy"
  export CC_BACKLOG_LOG="$BATS_TEST_TMPDIR/backlog.spy"
  export CC_FLIP_CTL="$BATS_TEST_TMPDIR/flip.ctl"     # steers tests/host-flip.bats (see the SPY)
  SPY="$BATS_TEST_TMPDIR/bats-spy"; BLSPY="$BATS_TEST_TMPDIR/backlog-spy"
  cat > "$SPY" <<'SPY'
#!/bin/bash
printf '%s\n' "$1" >> "$CC_SPY_LOG"
case "$1" in
  *host-red*) printf 'not ok 1 - boom\nnot ok 2 - boom2\n'; exit 1 ;;
  *host-cut*) exit 124 ;;                 # OUR bound firing: non-zero naming ZERO tests
  # OUR bound firing on a suite that had ALREADY named failures — the TRUNCATED run. `host-cut`
  # above only ever covered the tidy shape (killed before any test finished); a real long suite is
  # killed MID-CORPUS, having emitted whatever it reached.
  *host-trunc*) printf 'not ok 1 - reached\nnot ok 2 - reached\n'; exit 124 ;;
  # A suite that PASSES while unprefixed stderr splices into its stream: rc 0, one real `ok`, and
  # four C30 shapes that merely OPEN with `not ok`. The worst case for a loose grammar — a green
  # live layer paged and backlogged as RED.
  *host-torn*) printf 'not ok\nnot ok3 squashed\nnot okay then\nnot okcorpus: 3 suites\n'
               printf 'ok 1 - fine\n'; exit 0 ;;
  # …and the control: the same splice around ONE genuine verdict, which must still page.
  *host-tsplice*) printf 'not okay then\nnot ok 1 - boom\nnot okcorpus: 3 suites\n'; exit 1 ;;
  # STEERED by a control file, so ONE suite can change verdict between ticks. Every branch above is
  # keyed on the suite NAME and is therefore constant for all time, which cannot exercise a rule
  # about CONSECUTIVE outcomes — "a verdict clears the streak" needs the same suite to cut, then
  # pass. Default 124 (cut) so a test that never writes the control file still gets a cut.
  *host-flip*) fc="$(cat "$CC_FLIP_CTL" 2>/dev/null || true)"
               case "$fc" in ''|*[!0-9]*) fc=124 ;; esac
               case "$fc" in 0) printf 'ok 1 - fine\n' ;; 1) printf 'not ok 1 - boom\n' ;; esac
               exit "$fc" ;;
  *)          printf 'ok 1 - fine\n'; exit 0 ;;
esac
SPY
  # shellcheck disable=SC2016  # $* / $CC_BACKLOG_LOG belong to the SPY being written, not to us
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "$CC_BACKLOG_LOG"\n' > "$BLSPY"
  chmod +x "$SPY" "$BLSPY"
}

dla() { # deploy-live --auto with every side channel spied
  env DEPLOY_REPO="$SHARED" CC_POSTLAND_DIR="$BATS_TEST_TMPDIR/postland" CC_PAGES_DIR="$PAGES" \
      CC_DEPLOY_BATS_BIN="$SPY" CC_BACKLOG_BIN="$BLSPY" CC_DEPLOY_TIMEOUT_BIN= \
      /bin/bash "$DL" --auto "$@"
}

seed_host_suites() { # <manifest-body> — commit suites+manifest onto origin/main, leave HEAD behind
  local head; head="$(git -C "$SHARED" rev-parse HEAD)"
  mkdir -p "$SHARED/scripts" "$SHARED/tests"
  printf '#!/usr/bin/env bats\n@test "x" { true; }\n' > "$SHARED/tests/host-ok.bats"
  printf '#!/usr/bin/env bats\n@test "x" { true; }\n' > "$SHARED/tests/host-two.bats"
  printf '#!/usr/bin/env bats\n@test "x" { false; }\n' > "$SHARED/tests/host-red.bats"
  printf '#!/usr/bin/env bats\n@test "x" { true; }\n' > "$SHARED/tests/host-cut.bats"
  printf '#!/usr/bin/env bats\n@test "x" { true; }\n' > "$SHARED/tests/host-trunc.bats"
  printf '#!/usr/bin/env bats\n@test "x" { true; }\n' > "$SHARED/tests/host-torn.bats"
  printf '#!/usr/bin/env bats\n@test "x" { false; }\n' > "$SHARED/tests/host-tsplice.bats"
  printf '#!/usr/bin/env bats\n@test "x" { true; }\n' > "$SHARED/tests/host-flip.bats"
  printf '%s\n' "$1" > "$SHARED/scripts/host-suites.manifest"
  git -C "$SHARED" add -A; git -C "$SHARED" commit -q -m host-suites
  git -C "$SHARED" push -q origin main
  git -C "$SHARED" reset -q --hard "$head"      # the suites arrive WITH the advance, as in life
}

@test "--auto: nothing new stamped green ⇒ SILENT exit 0 (the steady state must not narrate)" {
  auto_setup
  advance_origin b
  stamp origin/main
  run dla                                        # first tick advances
  [ "$status" -eq 0 ]
  run dla                                        # second tick: TARGET == HEAD
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  # positive control: the SAME state without --auto still narrates, so the emptiness above is the
  # flag's doing and not a test that could never see output.
  run dl
  [ "$status" -eq 0 ]
  [[ "$output" == *"already deployed"* ]] || false
}

@test "--auto refuses --force/--bootstrap with exit 2, BEFORE any network read" {
  auto_setup
  git -C "$SHARED" remote set-url origin "$BATS_TEST_TMPDIR/does-not-exist.git"
  run dla --force                                # a fetch would exit 1; 2 proves we never got there
  [ "$status" -eq 2 ]
  [[ "$output" == *"cannot be combined"* ]] || false
  run dla --bootstrap
  [ "$status" -eq 2 ]
  # positive control: without --auto, --force is still honored (the guard is scoped to the flag)
  git -C "$SHARED" remote set-url origin "$ORIGIN"
  advance_origin b
  run dl --force
  [ "$status" -eq 0 ]
  [[ "$output" == *"gate BYPASSED"* ]] || false
}

@test "--auto no-stamps refusal: pages ONCE, then silent inside the damp window, still exit 1" {
  auto_setup
  advance_origin b
  rm -rf "$BATS_TEST_TMPDIR/postland"
  run dla
  [ "$status" -eq 1 ]
  [[ "$output" == *"verification net is not active"* ]] || false
  [ -f "$PAGES/deploy-no-stamps.page" ]
  head -1 "$PAGES/deploy-no-stamps.page" | grep -qE '^[0-9]+$'   # epoch-headed like every page
  run dla                                        # same reason, inside the window
  [ "$status" -eq 1 ]                            # fail-closed is NOT what gets damped
  [ -z "$output" ]
  # positive control: without --auto the same refusal is loud every single time
  run dl; [[ "$output" == *"verification net is not active"* ]] || false
  run dl; [[ "$output" == *"verification net is not active"* ]] || false
}

@test "--auto damping is subject+state: a CHANGED refusal reason re-pages immediately" {
  auto_setup
  advance_origin b
  rm -rf "$BATS_TEST_TMPDIR/postland"
  run dla; [ "$status" -eq 1 ]                   # arms the damp on no-stamps-dir
  run dla; [ -z "$output" ]                      # damped
  mkdir -p "$STAMPS"                             # reason CHANGES: dir exists, nothing green
  run dla
  [ "$status" -eq 1 ]
  [[ "$output" == *"no GREEN stamp"* ]] || false          # loud again despite the 24h window still running
}

@test "--auto damping: an ELAPSED window re-pages the SAME reason" {
  auto_setup
  advance_origin b
  rm -rf "$BATS_TEST_TMPDIR/postland"
  run dla; [ "$status" -eq 1 ]
  run dla; [ -z "$output" ]
  d="$BATS_TEST_TMPDIR/postland/deploy-auto.damp"
  [ -f "$d" ]                                    # the marker is read from disk, never assumed
  # Age it 25h. Seeded RELATIVE to now and SIGNED — a literal date would rot this test into a
  # fleet-wide red the moment the calendar moved past it. The state key is copied back from the
  # marker itself rather than re-guessed, so the test cannot drift from the script's own format.
  printf '%s\n%s\n' "$(( $(date +%s) - 90000 ))" "$(sed -n '2p' "$d")" > "$d"
  run dla
  [ "$status" -eq 1 ]
  [[ "$output" == *"verification net is not active"* ]] || false
}

@test "--auto: a healthy advance CLEARS the damp so the next failure is loud at once" {
  auto_setup
  advance_origin b
  rm -rf "$BATS_TEST_TMPDIR/postland"
  run dla; run dla; [ -z "$output" ]             # damped
  mkdir -p "$STAMPS"; stamp origin/main
  run dla
  [ "$status" -eq 0 ]
  [ ! -f "$BATS_TEST_TMPDIR/postland/deploy-auto.damp" ]
}

@test "advance ⇒ EVERY manifest suite runs against the live layer; comments/blanks/absent skipped" {
  auto_setup
  seed_host_suites '# host partition
tests/host-ok.bats

  tests/host-two.bats   # indented, with a trailing comment
tests/absent.bats'
  stamp origin/main
  run dla
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$CC_SPY_LOG" | tr -d ' ')" -eq 2 ]      # EXACT: absent is skipped, not counted
  grep -qx 'tests/host-ok.bats'  "$CC_SPY_LOG"
  grep -qx 'tests/host-two.bats' "$CC_SPY_LOG"
  [[ "$output" == *"absent in the deployed tree"* ]] || false
}

@test "host RED ⇒ page + backlog naming the suite, exit 0, live layer NOT rolled back" {
  auto_setup
  seed_host_suites 'tests/host-red.bats'
  stamp origin/main
  want="$(git -C "$SHARED" rev-parse origin/main)"
  run dla
  [ "$status" -eq 0 ]                                   # a live-layer finding never fails the deploy
  [ "$(git -C "$SHARED" rev-parse HEAD)" = "$want" ]     # and never rolls back
  pf="$PAGES/deploy-host-red-$(printf '%.12s' "$want").page"
  [ -f "$pf" ]
  head -1 "$pf" | grep -qE '^[0-9]+$'
  grep -q 'tests/host-red.bats' "$pf"
  grep -q 'NOT a rollback trigger' "$pf"
  grep -q 'post-deploy HOST RED' "$CC_BACKLOG_LOG"
  grep -q 'host-red.bats' "$CC_BACKLOG_LOG"
}

# The two channels key DIFFERENTLY on purpose: the page is per-deploy (sha), the backlog is
# per-finding (failing set). cc-backlog's event key is project+title+source, so a sha in the title
# mints a fresh item every deploy for one unresolved finding — measured at 5 items for
# tests/deploy-parity-live.bats(1), 2 of them auto-blocked as "the worker cannot land". This pins
# both halves at once, and it FAILS against the pre-fix title (two distinct lines, not one).
@test "host RED backlog is keyed on the FAILING SET, not the sha (page stays per-sha)" {
  auto_setup
  seed_host_suites 'tests/host-red.bats'
  stamp origin/main
  first="$(git -C "$SHARED" rev-parse origin/main)"
  run dla
  [ "$status" -eq 0 ]

  advance_origin later                                  # a second deployable commit ⇒ a NEW sha
  stamp origin/main
  second="$(git -C "$SHARED" rev-parse origin/main)"
  [ "$first" != "$second" ]
  run dla
  [ "$status" -eq 0 ]

  # per-deploy channel keeps its granularity: one page per deployed sha
  [ -f "$PAGES/deploy-host-red-$(printf '%.12s' "$first").page" ]
  [ -f "$PAGES/deploy-host-red-$(printf '%.12s' "$second").page" ]

  # per-finding channel collapses: ONE distinct backlog call across both deploys, naming no sha
  [ "$(sort -u "$CC_BACKLOG_LOG" | wc -l | tr -d ' ')" -eq 1 ]
  grep -q 'post-deploy HOST RED: tests/host-red.bats(2)' "$CC_BACKLOG_LOG"
  ! grep -qE "${first:0:12}|${second:0:12}" "$CC_BACKLOG_LOG"
}

@test "host CUT is a NON-VERDICT (R6): named 0 tests ⇒ no page, no backlog, deploy still 0" {
  auto_setup
  seed_host_suites 'tests/host-cut.bats'
  stamp origin/main
  run dla
  [ "$status" -eq 0 ]
  [[ "$output" == *"CUT"* ]] || false
  # find, not `ls | grep`: an unmatched glob would expand to its own literal and read as a HIT,
  # which would make this assertion pass for the wrong reason. `[ ]` keeps it live under errexit.
  [ "$(find "$PAGES" -name 'deploy-host-red-*.page' 2>/dev/null | wc -l | tr -d ' ')" -eq 0 ]
  [ ! -s "$CC_BACKLOG_LOG" ]
}

# ── A RUN WE KILLED IS A NON-VERDICT EVEN WHEN IT NAMED FAILURES FIRST ───────────────────────────
# `notok > 0` was tested BEFORE `rc == 124`, so a suite our own bound killed mid-corpus was reported
# RED — paged, and filed as a backlog item a worker is then dispatched to chase. Two things make
# that wrong, and the second is why it matters more than the first:
#   1. The failures were observed under exactly the contention that made the bound fire. That is the
#      load-sensitivity scripts/host-suites.manifest documents at length (rc=2 fork exhaustion
#      fabricating a leak) — the failures least entitled to be believed, not the most.
#   2. The failing SET is a function of WHERE THE KILL LANDED, not of the tree. The backlog title
#      carries that count, and cc-backlog mints its event key from project+title+source — so one
#      unresolved condition mints a NEW item every time load shifts the truncation point. That is
#      the same non-idempotency the sha-in-the-title fix above removed, arriving by another door.
# MEASURED 2026-08-10 on tests/test-hermeticity-lint.bats, which is how this was found: 52/52 green
# in a clean tree at 272s against a 300s bound, and 6 of 6 host runs CUT. The one time it ever
# "spoke" it produced backlog cb9980e4b0e5, `HOST RED: tests/test-hermeticity-lint.bats(2)` — a
# truncated run promoted to a claim about a tree that was green.
# The reached failures are NAMED in the log line rather than discarded: a non-verdict must not also
# be a silence. The too-strong direction is held by the two `host-red` cases above — an ORDINARY
# named failure (rc 1) must still page and still file.
@test "host TRUNCATED: our bound firing AFTER named failures is a CUT, never a RED" {
  auto_setup
  seed_host_suites 'tests/host-trunc.bats'
  stamp origin/main
  run dla
  [ "$status" -eq 0 ]
  [[ "$output" == *"CUT  tests/host-trunc.bats"* ]] || false
  [[ "$output" == *"2 named failure(s)"* ]] || false    # not discarded — a non-verdict is not a silence
  [[ "$output" != *"RED  tests/"* ]] || false
  [ "$(find "$PAGES" -name 'deploy-host-red-*.page' 2>/dev/null | wc -l | tr -d ' ')" -eq 0 ]
  [ ! -s "$CC_BACKLOG_LOG" ]                            # no item for a worker to chase
}

# ── A LINE THAT ONLY OPENS WITH `not ok` IS NOT A NAMED FAILURE ──────────────────────────────────
# R6's "a NAMED failure is the only red" is enforced here by `grep -c '^not ok'`, and that spelling
# does not implement the rule it is quoting: TAP spells a result `not ok <N> <desc>`, so without the
# <N> the pattern also counts a line truncated mid-write and any unprefixed stderr that happens to
# open with those bytes — routine here, since the suite is captured `2>&1`. postland-verify fixed
# its own three readers (C30, TAP_NOTOK_RE); this lane kept the loose one. Consequence is narrower
# than the land gate's exit 6 but not nothing: host_checks pages AND files a backlog item, so a
# GREEN live layer mints a finding that a worker is then dispatched to chase.
@test "host TORN TAP: a PASSING suite whose stream carries torn 'not ok' bytes is ok, not RED" {
  auto_setup
  seed_host_suites 'tests/host-torn.bats'
  stamp origin/main
  run dla
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok   tests/host-torn.bats"* ]] || false
  [[ "$output" != *"RED"* ]] || false
  [ "$(find "$PAGES" -name 'deploy-host-red-*.page' 2>/dev/null | wc -l | tr -d ' ')" -eq 0 ]
  [ ! -s "$CC_BACKLOG_LOG" ]                     # no page, and no item for a worker to chase
}

@test "host TORN CONTROL: ONE real 'not ok 1' inside the same splice still pages as RED" {
  # The too-strong direction. A grammar tightened past the point where it sees a genuine failure
  # has deleted the check, not fixed it — and this lane fails silently when that happens, because
  # host_checks never blocks and never changes the exit code.
  auto_setup
  seed_host_suites 'tests/host-tsplice.bats'
  stamp origin/main
  want="$(git -C "$SHARED" rev-parse origin/main)"
  run dla
  [ "$status" -eq 0 ]
  [[ "$output" == *"RED  tests/host-tsplice.bats — 1 failing"* ]] || false   # EXACTLY one, not three
  [ -f "$PAGES/deploy-host-red-$(printf '%.12s' "$want").page" ]
  grep -q 'post-deploy HOST RED' "$CC_BACKLOG_LOG"
}

# ── THE CONSECUTIVE-CUT COUNTER, PER SUITE (backlog 75463ef0d0f9) ────────────────────────────────
# R6 makes a single cut safe by refusing to call it a failure. Nothing then made a PERMANENT cut
# unsafe: tests/test-hermeticity-lint.bats reached no verdict on 6 of 6 host runs across 12 days
# against a bound below its runtime, and every artifact an operator reads was indistinguishable from
# a healthy lane. One correct `CUT` line per run, forever, carries the same zero bits as an alarm
# that always fires. Ported from scripts/postland-verify.sh (CUT_MAX/CUT_COOLOFF) with the key
# changed from the TREE to the SUITE — see the per-suite test below, which is the whole change.
tick() { # <name> [ENV=VAL…] — one full deploy: a new deployable commit, stamped, then --auto
  local nm="$1"; shift
  # Advance ONLY once the clone has caught up. seed_host_suites deliberately leaves HEAD behind
  # origin/main (the suites arrive WITH the advance, as in life), so the first tick deploys that
  # seeded commit — committing on a behind-HEAD would diverge and the push would be rejected.
  if [ "$(git -C "$SHARED" rev-parse HEAD)" = "$(git -C "$SHARED" rev-parse origin/main)" ]; then
    advance_origin "$nm"
  fi
  stamp origin/main
  run env DEPLOY_REPO="$SHARED" CC_POSTLAND_DIR="$BATS_TEST_TMPDIR/postland" CC_PAGES_DIR="$PAGES" \
          CC_DEPLOY_BATS_BIN="$SPY" CC_BACKLOG_BIN="$BLSPY" CC_DEPLOY_TIMEOUT_BIN= "$@" \
          /bin/bash "$DL" --auto
  [ "$status" -eq 0 ] || { echo "tick $nm exited $status: $output"; false; }
}
# host_cut_page slugs the suite path with `tr -c 'A-Za-z0-9._-' '-'`: tests/host-cut.bats becomes
# tests-host-cut.bats. Spelled out rather than derived, so a change to the slugging is a RED here.
cutpage() { printf '%s/deploy-host-cut-tests-host-%s.bats.page' "$PAGES" "$1"; }

@test "host CUT counter: silent below CUT_MAX, then ONE page + backlog naming the suite" {
  auto_setup
  seed_host_suites 'tests/host-cut.bats'
  tick t1                                          # cut 1/3 — the default CUT_MAX, pinned here
  [ ! -f "$(cutpage cut)" ]
  tick t2                                          # cut 2/3
  [ ! -f "$(cutpage cut)" ]                        # a page before CUT_MAX is the alarm-polarity bug
  [ ! -s "$CC_BACKLOG_LOG" ]
  tick t3                                          # cut 3/3 ⇒ news
  [ -f "$(cutpage cut)" ]
  head -1 "$(cutpage cut)" | grep -qE '^[0-9]+$'   # page-file contract: epoch first (autonomy-sweep)
  grep -q 'tests/host-cut.bats' "$(cutpage cut)"
  grep -q '3 consecutive deploys' "$(cutpage cut)"
  grep -q 'do not bisect' "$(cutpage cut)"         # HONEST: a cut is never a claim about the tree
  grep -q 'post-deploy HOST CUT (no verdict): tests/host-cut.bats' "$CC_BACKLOG_LOG"
  [[ "$output" == *"PAGE tests/host-cut.bats"* ]] || false
  [ "$(find "$PAGES" -name 'deploy-host-red-*.page' | wc -l | tr -d ' ')" -eq 0 ]  # still not a RED
}

# THE CHANGE OF KEY, and the only test that can see it. postland tracks ONE streak on the tree
# because it runs one corpus per sweep; the host lane runs N independent suites against one live
# layer, so a tree-keyed port would have any green neighbour clear the streak of a suite that is
# cutting forever — which is precisely the shape that went unnoticed (the hermeticity wrapper cut on
# every run while tests/deploy-parity-live.bats passed on every run, in the same tick).
@test "host CUT counter is PER SUITE: a green neighbour never clears a cutting suite's streak" {
  auto_setup
  seed_host_suites 'tests/host-cut.bats
tests/host-ok.bats'
  tick t1; tick t2; tick t3
  [ -f "$(cutpage cut)" ]                          # the cutting suite still reaches CUT_MAX…
  [ ! -f "$(cutpage ok)" ]                         # …and the green one never pages at all
  [ "$(grep -c 'tests/host-ok.bats' "$CC_SPY_LOG")" -eq 3 ]   # it kept running every tick
}

@test "a VERDICT clears the streak: cut,cut,ok,cut,cut never reaches CUT_MAX" {
  auto_setup
  seed_host_suites 'tests/host-flip.bats'
  tick t1; tick t2                                 # 2 cuts — one short
  printf '0\n' > "$CC_FLIP_CTL"; tick t3           # a VERDICT (ok) ⇒ streak cleared, row dropped
  [[ "$output" == *"ok   tests/host-flip.bats"* ]] || false
  [ ! -f "$BATS_TEST_TMPDIR/postland/host-cuts" ]  # cleared by writing NO row, never a 0 row
  printf '124\n' > "$CC_FLIP_CTL"; tick t4; tick t5
  [ ! -f "$(cutpage flip)" ]                       # 2+2 is not 4: consecutive, not cumulative
  tick t6                                          # …and the third IN A ROW still pages
  [ -f "$(cutpage flip)" ]
}

# A RED is a verdict, and it already has its own channel two tests up. Counting it here would page
# the same suite a second time under a headline asserting the opposite ("NO claim was produced").
@test "a RED every deploy feeds the RED channel only — never the cut counter" {
  auto_setup
  seed_host_suites 'tests/host-red.bats'
  tick t1; tick t2; tick t3
  [ ! -f "$(cutpage red)" ]
  ! grep -q 'HOST CUT' "$CC_BACKLOG_LOG" || false
  grep -q 'post-deploy HOST RED' "$CC_BACKLOG_LOG"
}

# CUT_MAX and the COOL-OFF are one mechanism, not two. The cool-off is this lane's only damping —
# its RED page is sha-keyed and so is naturally per-deploy, but a cut page keyed on the suite would
# otherwise be rewritten every 600s tick forever, which is the 570-near-duplicate-pages defect
# hooks/lib/page-damp.sh was built for. It buys the load back too: a suite that provably is not
# reaching a verdict stops being fed a full HOST_TIMEOUT_S of a loaded box every tick.
@test "past CUT_MAX the suite is SKIPPED (spoken, with its remaining time), not re-run" {
  auto_setup
  seed_host_suites 'tests/host-cut.bats'
  tick t1; tick t2; tick t3
  [ "$(grep -c 'tests/host-cut.bats' "$CC_SPY_LOG")" -eq 3 ]
  before="$(stat -f %m "$(cutpage cut)")"
  tick t4
  [ "$(grep -c 'tests/host-cut.bats' "$CC_SPY_LOG")" -eq 3 ]   # NOT run a 4th time
  [[ "$output" == *"cut cool-off: 3 consecutive non-verdicts"* ]] || false
  [[ "$output" == *"s left)"* ]] || false           # bounded and spoken, never a silent skip
  [ "$(stat -f %m "$(cutpage cut)")" = "$before" ]  # and the page is NOT re-sent while suppressed
}

@test "cool-off EXPIRED ⇒ the suite runs again and the finding re-asserts at n+1" {
  auto_setup
  seed_host_suites 'tests/host-cut.bats'
  tick t1; tick t2; tick t3
  # 0 is the documented disable — `elapsed -lt 0` is never true — so this tick sees an EXPIRED
  # cool-off by construction, without sleeping or hand-editing the state file it is testing.
  tick t4 CC_DEPLOY_HOST_CUT_COOLOFF=0
  [ "$(grep -c 'tests/host-cut.bats' "$CC_SPY_LOG")" -eq 4 ]
  grep -q '4 consecutive deploys' "$(cutpage cut)"  # re-asserted: an unchanging page reads as resolved
  # …and the BACKLOG key did not move with the count. cc-backlog mints its event key from
  # project+title+source, so an `n` in the title would mint a fresh item per cool-off for one
  # unresolved finding — the same non-idempotency the sha-in-the-title fix removed.
  [ "$(sort -u "$CC_BACKLOG_LOG" | wc -l | tr -d ' ')" -eq 1 ]
  ! grep -qE '[0-9]+ consecutive|[0-9]{12}' "$CC_BACKLOG_LOG"
}

# ── THE DOCUMENTED DISABLE, BOTH DIRECTIONS ─────────────────────────────────────────────────────
# The knob block says "0 disables either half without a separate kill switch". That was true of the
# COOLOFF half for free (`elapsed -lt 0` is never true) and FALSE of the MAX half, whose guard is
# `-ge`: `n >= 0` holds on the FIRST cut, so CC_DEPLOY_HOST_CUT_MAX=0 paged immediately and put
# every cutting suite into cool-off — the exact opposite of off, from the value the comment names as
# the off switch. Both cases below are needed and neither implies the other: the first proves 0
# turns the mechanism OFF, the second proves it did not merely shift the threshold by one, which is
# the mistake this fix could easily have introduced (memory: guard-proxy-fails-in-both-directions).
# The positive control that the knob is not simply dead is the CUT_MAX test above, which pins the
# default MAX=3 as silent on ticks 1-2 and paging on tick 3 — not duplicated here.
@test "CUT_MAX=0 DISABLES the counter: cuts forever ⇒ no page, no backlog, never suppressed" {
  auto_setup
  seed_host_suites 'tests/host-cut.bats'
  tick t1 CC_DEPLOY_HOST_CUT_MAX=0
  tick t2 CC_DEPLOY_HOST_CUT_MAX=0
  tick t3 CC_DEPLOY_HOST_CUT_MAX=0                 # past the DEFAULT max, so a leak would show here
  tick t4 CC_DEPLOY_HOST_CUT_MAX=0
  [ ! -f "$(cutpage cut)" ]
  [ ! -s "$CC_BACKLOG_LOG" ]
  [[ "$output" != *"PAGE"* ]] || false
  # …and the OTHER half of the same knob: with the alarm off the suite is never cool-off-skipped
  # either, so it is still being run and still able to produce a verdict on any later tick.
  [ "$(grep -c 'tests/host-cut.bats' "$CC_SPY_LOG")" -eq 4 ]
  [[ "$output" != *"cut cool-off"* ]] || false
}

@test "CUT_MAX=1 pages on the FIRST cut — 0 is DISABLE, never an off-by-one" {
  auto_setup
  seed_host_suites 'tests/host-cut.bats'
  tick t1 CC_DEPLOY_HOST_CUT_MAX=1
  [ -f "$(cutpage cut)" ]
  grep -q '1 consecutive deploys' "$(cutpage cut)"
  grep -q 'post-deploy HOST CUT (no verdict): tests/host-cut.bats' "$CC_BACKLOG_LOG"
  [[ "$output" == *"PAGE tests/host-cut.bats"* ]] || false
}

@test "manifest MISSING ⇒ host checks skipped silently, bats never invoked at all" {
  auto_setup
  advance_origin b                               # no manifest is ever committed here
  stamp origin/main
  run dla
  [ "$status" -eq 0 ]
  [ ! -e "$CC_SPY_LOG" ]                         # the contract: missing ⇒ empty set ⇒ no host run
  [[ "$output" != *"host check"* ]] || false
  [[ "$output" == *"install.sh ok"* ]] || false           # positive control: the advance itself DID happen
}

# ── the UNCONDITIONAL link refresh ───────────────────────────────────────────────────────────────
# The defect pinned here (2026-07-30): the namespace reconcile lived BELOW `merge --ff-only`, so
# every early exit — "already deployed", the rollback refusal, the no-green refusal — returned before
# a single link was created. On the live host the rollback refusal is PERMANENT: ~/.claude is
# per-file symlinks into the checkout, so every land advances the live layer for free while TARGET
# (last-green) lags by the verify duration, leaving live HEAD forever ahead of it. Measured: 96
# consecutive `would ROLL BACK` lines in deploy.log, 174 commits of lag, refresh unrun for days.
# The `[[ ]] || false` rule from the --auto block above applies verbatim to every test below.
#
# The stub reproduces the real contract exactly: `MISSING: ln -sf <src> <dest>` is emitted only at
# deploy-parity-assert.sh:310, and the two-space-indented `PENDING` report at :306 — which must NEVER
# be actioned, because linking a staged-pending file erases the "activation un-run" signal
# (tests/deploy-parity.bats:315).
seed_parity() { # <rc> — stub assert that cats $PARITY_OUT and exits <rc>; caller fills it via miss/pending
  PARITY_OUT="$BATS_TEST_TMPDIR/parity.out"
  ASSERT="$BATS_TEST_TMPDIR/parity-assert.sh"
  LIVE="$BATS_TEST_TMPDIR/live"
  : > "$PARITY_OUT"; mkdir -p "$LIVE" "$SHARED/hooks"
  printf '#!/bin/bash\ncat "%s"\nexit %s\n' "$PARITY_OUT" "$1" > "$ASSERT"
  chmod +x "$ASSERT"
}
miss() {    # <repo-relative> — a tracked file with no live link; returns its dest via $DEST
  echo "payload-$1" > "$SHARED/$1"
  DEST="$LIVE/$1"
  printf 'MISSING: ln -sf %s %s\n' "$SHARED/$1" "$DEST" >> "$PARITY_OUT"
}
pending() { # <repo-relative> — unlinked BY DESIGN; the assert reports it, nobody may link it
  echo "payload-$1" > "$SHARED/$1"
  PDEST="$LIVE/$1"
  printf '  PENDING %s unlinked BY DESIGN — staged: 99-fixture-activate.sh\n' "$1" >> "$PARITY_OUT"
}
dlp() { env DEPLOY_REPO="$SHARED" CC_POSTLAND_DIR="$BATS_TEST_TMPDIR/postland" \
            CC_PAGES_DIR="$PAGES" CC_DEPLOY_PARITY_ASSERT="$ASSERT" /bin/bash "$DL" "$@"; }

@test "refresh runs on the GREEN-BEHIND non-advance — the exit that made it dead code (2026-07-30)" {
  seed_parity 1
  miss hooks/brand-new.sh
  stamp HEAD                                     # the newest green is the commit already live...
  commit_push b; git -C "$SHARED" push -q origin main   # ...and both HEAD and origin move past it
  # FIXTURE CORRECTED 2026-08-07. This used to stop above, at lag 0, and its own comment read "this
  # stays a refusal forever" — which pinned a DEFECT as intended behaviour. At lag 0 the candidate
  # set is empty, so refusing is wrong: there is nothing to deploy, safe or otherwise, and `die`
  # exiting 1 every 600s is what made launchctl read exit 1 forever and hid the original freeze.
  # The layer now exits 0 "at trunk tip" there (covered by its own two tests above).
  # This test's SUBJECT was never the exit code — it is the 2026-07-30 regression that link_refresh
  # was dead code below the advance, asserted by [ -L "$DEST" ]. So keep that intact and put the
  # fixture back on the path it means to exercise: trunk one commit ahead, green behind live HEAD,
  # inside the T2 budget ⇒ a genuine, still-correct refusal.
  #
  # EXIT CODE UPDATED 2026-08-10 (backlog 2e7fe6fd5b7c) — the SUBJECT is untouched and the test is
  # not weakened. That in-budget green-behind state is now a WAIT (exit 0) rather than a refusal;
  # this test's own comment above already says its subject was never the exit code, and the exit
  # code is only the vehicle for reaching a NON-ADVANCING path. It still reaches one: the tree does
  # not move, and [ -L "$DEST" ] — the actual 2026-07-30 regression guard — is unchanged and still
  # the assertion that would fail if link_refresh ever fell below the advance again. It cannot: the
  # call sits UNCONDITIONALLY at deploy-live.sh:630, ahead of the fetch and of the whole tier
  # ladder, which is why every early return in this lane has one of these tests.
  advance_origin c                               # trunk moves again; the layer stays ⇒ lag 1
  before="$(git -C "$SHARED" rev-parse HEAD)"
  run dlp
  [ "$status" -eq 0 ]
  [ "$(git -C "$SHARED" rev-parse HEAD)" = "$before" ]   # non-advancing: the path this test needs
  # The diagnosis is unchanged — the lane still names the green-behind state, it just no longer
  # spends a refusal on a lag of 1 commit that is far inside the 25-commit budget.
  echo "$output" | grep -q "DESCENDANT of live HEAD"
  [ -L "$DEST" ]                                 # ...yet the link now exists anyway
  [ "$(readlink "$DEST")" = "$SHARED/hooks/brand-new.sh" ]
}

@test "refresh runs on the ALREADY-DEPLOYED exit (the second early return)" {
  seed_parity 1
  miss hooks/late-arrival.sh
  stamp HEAD
  run dlp
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "already deployed"
  [ -L "$DEST" ]
}

@test "refresh runs on the NO-GREEN-STAMP refusal (the third early return)" {
  seed_parity 1
  miss hooks/unstamped-era.sh
  advance_origin b                               # origin moves, nothing is ever stamped
  run dlp
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "no GREEN stamp"
  [ -L "$DEST" ]
}

@test "refresh precedes the FETCH — a dead network must not strand a landed file" {
  seed_parity 1
  miss hooks/offline.sh
  git -C "$SHARED" remote set-url origin "$BATS_TEST_TMPDIR/nope.git"
  run dlp
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "git fetch origin main FAILED"
  [ -L "$DEST" ]
}

@test "a PENDING file is NEVER linked — the refresh must not erase the staged-activation signal" {
  seed_parity 1
  miss hooks/real-miss.sh; REAL="$DEST"
  pending hooks/staged-pending.sh
  stamp HEAD
  run dlp
  [ "$status" -eq 0 ]
  [ -L "$REAL" ]                                 # the genuine gap IS repaired...
  [ ! -e "$PDEST" ]                              # ...and the by-design gap is left exactly alone
  [[ "$output" != *"staged-pending.sh"* ]] || false
}

@test "assert NO-VERDICT (rc 3) relinks NOTHING and says so — an empty list is not 'nothing missing'" {
  seed_parity 3                                  # rc 3 = the assert's own enumeration failed
  miss hooks/never-link-me.sh                    # text present, but the verdict is void
  stamp HEAD
  run dlp
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "NO VERDICT"
  [ ! -e "$DEST" ]
}

# ── THE WIDENED UNIVERSE (2026-08-10, P6) ────────────────────────────────────────────────────────
# The assert's pathspec grew from 5 of install.sh's ~19 deploy classes to every SYMLINK class, and
# because this function consumes a VERDICT rather than re-deriving a want-list, that widening needed
# no code here. These two tests are what makes that claim checkable rather than asserted: the first
# proves a newly-covered class is repaired by the same generic path (no per-class logic exists, and
# none may be added), and the second proves the classes install.sh deploys by COPY can never be
# converted into symlinks by this loop — install.sh:289 calls exactly that "a critical bug", since a
# link into the working tree dangles on any branch switch and git fails OPEN on a dangling hook.
@test "refresh repairs a NEWLY-COVERED class (agents/) through the same generic path" {
  seed_parity 1
  mkdir -p "$SHARED/agents"
  miss agents/deep-research.md                   # NAME-invoked surface, zero grep-able callers
  stamp HEAD
  run dlp
  [ "$status" -eq 0 ]
  [ -L "$DEST" ]
  [ "$(readlink "$DEST")" = "$SHARED/agents/deep-research.md" ]
  echo "$output" | grep -q "link-refresh: 1 live link"
}

@test "refresh NEVER acts on a COPY-class finding — COPYMISS is not an ln -sf line" {
  seed_parity 1
  miss hooks/genuine-link.sh; REAL="$DEST"
  # The copy-class verdicts as the assert actually spells them. If a future edit ever widened the
  # grep — or the assert ever emitted a copy class as `MISSING: ln -sf` — this test is what reds.
  {
    printf '  COPYMISS  statusline.sh          deployed by cp, and it is NOT there\n'
    printf '  COPYSTALE launchd/*.plist        copy DIFFERS from repo\n'
    printf '  CLAUDEMD  CLAUDE.md              live global instructions DIVERGE\n'
  } >> "$PARITY_OUT"
  stamp HEAD
  run dlp
  [ "$status" -eq 0 ]
  [ -L "$REAL" ]                                 # the genuine symlink gap IS repaired...
  [ ! -e "$LIVE/statusline.sh" ]                 # ...and no copy class is touched, in any direction
  [ ! -e "$LIVE/CLAUDE.md" ]
  echo "$output" | grep -q "link-refresh: 1 live link"
}

@test "--dry-run previews the refresh and creates NO link" {
  seed_parity 1
  miss hooks/preview-only.sh
  stamp HEAD
  run dlp --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "would link"
  echo "$output" | grep -q "WOULD BE created"
  [ ! -e "$DEST" ]
  [ ! -f "$INSTALL_LOG" ]                        # and it is still not install.sh doing this
}

@test "--auto with nothing missing is SILENT (the steady state must not narrate 144×/day)" {
  auto_setup
  seed_parity 1                                  # a clean assert: zero MISSING lines
  advance_origin b
  stamp origin/main
  run env DEPLOY_REPO="$SHARED" CC_POSTLAND_DIR="$BATS_TEST_TMPDIR/postland" CC_PAGES_DIR="$PAGES" \
          CC_DEPLOY_BATS_BIN="$SPY" CC_BACKLOG_BIN="$BLSPY" CC_DEPLOY_TIMEOUT_BIN= \
          CC_DEPLOY_PARITY_ASSERT="$ASSERT" /bin/bash "$DL" --auto
  [ "$status" -eq 0 ]
  run env DEPLOY_REPO="$SHARED" CC_POSTLAND_DIR="$BATS_TEST_TMPDIR/postland" CC_PAGES_DIR="$PAGES" \
          CC_DEPLOY_BATS_BIN="$SPY" CC_BACKLOG_BIN="$BLSPY" CC_DEPLOY_TIMEOUT_BIN= \
          CC_DEPLOY_PARITY_ASSERT="$ASSERT" /bin/bash "$DL" --auto
  [ "$status" -eq 0 ]
  [ -z "$output" ]                               # TARGET == HEAD and nothing missing ⇒ not one line
}

@test "--auto DOES narrate a real repair (positive control for the silence above)" {
  auto_setup
  seed_parity 1
  miss hooks/auto-repair.sh
  stamp HEAD
  run env DEPLOY_REPO="$SHARED" CC_POSTLAND_DIR="$BATS_TEST_TMPDIR/postland" CC_PAGES_DIR="$PAGES" \
          CC_DEPLOY_BATS_BIN="$SPY" CC_BACKLOG_BIN="$BLSPY" CC_DEPLOY_TIMEOUT_BIN= \
          CC_DEPLOY_PARITY_ASSERT="$ASSERT" /bin/bash "$DL" --auto
  [ "$status" -eq 0 ]
  [ -n "$output" ]                               # a state CHANGE always reaches the log
  echo "$output" | grep -q "link-refresh: 1 live link"
  [ -L "$DEST" ]
}

@test "CC_DEPLOY_PARITY_ASSERT SET-EMPTY disables the refresh (a seam that cannot turn off is not one)" {
  seed_parity 1
  miss hooks/disabled.sh
  stamp HEAD
  run env DEPLOY_REPO="$SHARED" CC_POSTLAND_DIR="$BATS_TEST_TMPDIR/postland" \
          CC_PAGES_DIR="$PAGES" CC_DEPLOY_PARITY_ASSERT= /bin/bash "$DL"
  [ "$status" -eq 0 ]
  [ ! -e "$DEST" ]
  [[ "$output" != *"link-refresh"* ]] || false
}

# ── COPY-class drift: the half link_refresh must not repair, and nobody was reading ──────────────
# Filed as backlog 590fedde86cc, whose stated consequence ("ADDED files never get symlinked") this
# suite's own subject REFUTES — link_refresh repairs every symlink class unconditionally, and the
# live host measured 20/20 classes at 0 missing on 2026-08-21. The surviving true half is the COPY
# classes: they have no unconditional repairer BY DESIGN (see the deploy-live.sh block above the
# function — a link into the working tree dangles on any branch switch), so install.sh is the only
# one, and it refuses from a behind-trunk checkout — the state deploy-live itself creates. The
# verdict was computed on every tick and consumed by nobody; these tests pin that it is now read.
#
# The fixture uses the PRODUCER's own line shape, deploy-parity-assert.sh's single report() site
# `printf '  %-9s %-22s %s\n'`, so a rename there fails these tests rather than silently muting them.
copydrift() { # <token> <subject> — one copy-class verdict line, exactly as report() emits it
  printf '  %-9s %-22s %s\n' "$1" "$2" "copy differs from repo → run ./install.sh" >> "$PARITY_OUT"
}

@test "copy-class drift is REPORTED and PAGED with an EMPTY missing list (the steady-state return)" {
  seed_parity 1
  copydrift STALE claude-latest                  # no miss(): this is exactly the early-return path
  stamp HEAD
  run dlp
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "copy-drift: 1 copy-class file(s) DIFFER"
  echo "$output" | grep -q "claude-latest"
  [ -f "$PAGES/deploy-copy-drift.page" ]
  grep -q "claude-latest" "$PAGES/deploy-copy-drift.page"
  grep -q "install.sh is the only copy repairer" "$PAGES/deploy-copy-drift.page"
}

@test "every copy token the producer emits is seen — STALE · COPYMISS · COPYSTALE · CLAUDEMD" {
  seed_parity 1
  copydrift COPYMISS  githooks/pre-commit
  copydrift COPYSTALE statusline.sh
  copydrift CLAUDEMD  CLAUDE.md
  copydrift STALE     claude-latest
  stamp HEAD
  run dlp
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "copy-drift: 4 copy-class file(s) DIFFER"
}

@test "copy drift is REPORTED, never REPAIRED — no copy-class file is ever linked" {
  seed_parity 1
  copydrift COPYMISS githooks/pre-commit
  miss hooks/real-symlink-class.sh               # the symlink half still repairs, alongside it
  stamp HEAD
  run dlp
  [ "$status" -eq 0 ]
  [ -L "$DEST" ]                                 # symlink class: repaired
  [ ! -e "$LIVE/githooks/pre-commit" ]           # copy class: reported and untouched
  echo "$output" | grep -q "copy-drift: 1 copy-class file(s) DIFFER"
}

@test "the page is the EDGE not the level — an unchanged drift set is silent on the second tick" {
  seed_parity 1
  copydrift STALE claude-latest
  stamp HEAD
  run dlp
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "copy-drift: 1 copy-class file(s) DIFFER"
  rm -f "$PAGES/deploy-copy-drift.page"          # prove the SECOND tick does not re-write it
  run dlp
  [ "$status" -eq 0 ]
  [[ "$output" != *"copy-drift:"* ]] || false
  [ ! -f "$PAGES/deploy-copy-drift.page" ]
}

@test "a CHANGED drift set re-pages immediately (the damp above can fail — this is its control)" {
  seed_parity 1
  copydrift STALE claude-latest
  stamp HEAD
  run dlp
  [ "$status" -eq 0 ]
  rm -f "$PAGES/deploy-copy-drift.page"
  copydrift COPYSTALE statusline.sh              # the SET changed ⇒ the signature key must differ
  run dlp
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "copy-drift: 2 copy-class file(s) DIFFER"
  [ -f "$PAGES/deploy-copy-drift.page" ]
}

@test "the refresh is idempotent — a second tick relinks nothing and narrates nothing" {
  seed_parity 1
  miss hooks/once.sh
  stamp HEAD
  run dlp
  [ "$status" -eq 0 ]
  [ -L "$DEST" ]
  # the real assert stops reporting a path once it resolves; the stub is static, so drop the line
  # ourselves to model that — otherwise this would assert the STUB's behavior, not the script's.
  : > "$PARITY_OUT"
  run dlp
  [ "$status" -eq 0 ]
  [[ "$output" != *"link-refresh"* ]] || false
  [ -L "$DEST" ]
}

# ── TWO-TIER TARGET SELECTION: T1 verified · T2 degraded · T3 blocked (§2.2) ─────────────────────
# The defect these pin: a single green-only tier is an ABSORBING state. The verifier emits 0.17
# greens/day and trunk moves ~63/day, so the green pointer permanently lags; once any other writer
# moves live HEAD past it the target is history and the advance refuses forever — 534 identical
# refusals, launchd runs=276 all exit 1, live layer 91 commits stale, zero pages.
# Every `[[ ]]` below carries `|| false` for the reason stated in the --auto block above.
dlb() { # <max-lag-commits> <max-lag-hours> [args…] — dl with the degrade budget PINNED, so no test
        # here rides on whatever the defaults happen to be
  local mc="$1" mh="$2"; shift 2
  env DEPLOY_REPO="$SHARED" CC_POSTLAND_DIR="$BATS_TEST_TMPDIR/postland" CC_PAGES_DIR="$PAGES" \
      CC_DEPLOY_MAX_LAG_COMMITS="$mc" CC_DEPLOY_MAX_LAG_HOURS="$mh" /bin/bash "$DL" "$@"
}

aged_push() { # <name> <seconds-ago> — commit at a BACKDATED author/committer date, then push.
              # Seeded RELATIVE to now, never a literal date, so the calendar cannot rot this suite.
  local ts; ts="$(( $(date +%s) - $2 ))"
  echo "$1" > "$SHARED/$1.txt"; git -C "$SHARED" add -A
  GIT_AUTHOR_DATE="$ts +0000" GIT_COMMITTER_DATE="$ts +0000" git -C "$SHARED" commit -q -m "$1"
  git -C "$SHARED" push -q origin main
}

deadlock() { # the MEASURED live state: the only green is BEHIND live HEAD, and trunk is 2 ahead.
             # Shared by the within-budget refusal above and its past-budget sibling L2 below, so
             # the two differ in the BUDGET and in nothing else.
  stamp HEAD
  commit_push b; git -C "$SHARED" push -q origin main
  advance_origin c d
}

@test "L1 T1 VERIFIED wins even with the budget blown — the green DESCENDANT, not the newest not-red" {
  advance_origin b c
  stamp "origin/main~1"                          # b is green AND a descendant of live HEAD
  want="$(git -C "$SHARED" rev-parse "origin/main~1")"
  run dlb 0 0                                    # budget wide open: T2 fires if T1 ever cedes to it
  [ "$status" -eq 0 ]
  [ "$(git -C "$SHARED" rev-parse HEAD)" = "$want" ]      # b — NOT the tip c that T2 would take
  [[ "$output" != *"DEGRADED"* ]] || false
  [ "$(find "$PAGES" -name 'deploy-degraded-*.page' 2>/dev/null | wc -l | tr -d ' ')" -eq 0 ]
}

@test "L2 T2 DEGRADED past the COMMIT budget: banner + page, and the live layer ADVANCES" {
  deadlock
  before="$(git -C "$SHARED" rev-parse HEAD)"
  want="$(git -C "$SHARED" rev-parse origin/main)"
  run dlb 1 999                                  # 2 > 1 commits; the hours clock is pinned OUT
  [ "$status" -eq 0 ]
  [ "$(git -C "$SHARED" rev-parse HEAD)" = "$want" ]
  [ "$want" != "$before" ]                       # it MOVED — the deadlock is the thing being killed
  [[ "$output" == *"DEGRADED deploy"* ]] || false
  [[ "$output" == *"2 commit(s) behind trunk"* ]] || false  # the banner names what authorised it
  pf="$PAGES/deploy-degraded-$(printf '%.12s' "$want").page"
  [ -f "$pf" ]
  head -1 "$pf" | grep -qE '^[0-9]+$'            # epoch-headed like every page in this lane
  grep -q 'authorised by' "$pf"
}

@test "L3 T2 DEGRADED on the HOURS budget alone (commit lag nowhere near its own budget)" {
  aged_push old 36000                            # live HEAD is 10h old and IS origin/main
  advance_origin b                               # trunk +1 — one commit, deep inside 25
  want="$(git -C "$SHARED" rev-parse origin/main)"
  run dlb 25 6
  [ "$status" -eq 0 ]
  [ "$(git -C "$SHARED" rev-parse HEAD)" = "$want" ]
  [[ "$output" == *"h since the live commit was authored"* ]] || false
  [[ "$output" != *"commit(s) behind trunk"* ]] || false    # the COMMIT clock did not authorise it
}

@test "L4 T2 walks BACK past a RED-stamped commit and takes the one below it" {
  advance_origin b c
  stamp origin/main red                          # the tip is RED — ineligible
  want="$(git -C "$SHARED" rev-parse "origin/main~1")"
  run dlb 1 999
  [ "$status" -eq 0 ]
  [ "$(git -C "$SHARED" rev-parse HEAD)" = "$want" ]        # b — NOT the red tip
  [[ "$output" == *"DEGRADED deploy"* ]] || false
  grep -q 'walked back past 1 RED' "$PAGES/deploy-degraded-$(printf '%.12s' "$want").page"
}

@test "L5 T2 ACCEPTS a cut/hung stamp — a NON-VERDICT is not a red (R6)" {
  advance_origin b c
  before="$(git -C "$SHARED" rev-parse HEAD)"
  tip="$(git -C "$SHARED" rev-parse origin/main)"
  stamp origin/main cut
  run dlb 1 999
  [ "$status" -eq 0 ]
  [ "$(git -C "$SHARED" rev-parse HEAD)" = "$tip" ]         # the CUT tip IS deployable
  git -C "$SHARED" reset -q --hard "$before"                # …and again for `hung`, from the SAME
  stamp origin/main hung                                    # start, so neither rides on the other
  run dlb 1 999
  [ "$status" -eq 0 ]
  [ "$(git -C "$SHARED" rev-parse HEAD)" = "$tip" ]
  # The DISCRIMINATOR: an eligibility test that accepted everything would pass both halves above.
  # The same fixture with a real RED verdict must NOT take the tip.
  git -C "$SHARED" reset -q --hard "$before"
  stamp origin/main red
  run dlb 1 999
  [ "$status" -eq 0 ]
  [ "$(git -C "$SHARED" rev-parse HEAD)" != "$tip" ]
}

@test "L6 CC_DEPLOY_DEGRADE=off restores today's refusal exactly (a switch that cannot kill is not one)" {
  deadlock
  before="$(git -C "$SHARED" rev-parse HEAD)"
  run env DEPLOY_REPO="$SHARED" CC_POSTLAND_DIR="$BATS_TEST_TMPDIR/postland" CC_PAGES_DIR="$PAGES" \
          CC_DEPLOY_MAX_LAG_COMMITS=1 CC_DEPLOY_MAX_LAG_HOURS=0 CC_DEPLOY_DEGRADE=off \
          /bin/bash "$DL"
  [ "$status" -eq 1 ]                            # the budget is BLOWN on both clocks and it still refuses
  [[ "$output" == *"DESCENDANT of live HEAD"* ]] || false
  [ "$(git -C "$SHARED" rev-parse HEAD)" = "$before" ]
  [ "$(find "$PAGES" -name 'deploy-degraded-*.page' 2>/dev/null | wc -l | tr -d ' ')" -eq 0 ]
  # positive control: SAME state, SAME blown budget, switch ON ⇒ it degrades and advances. Without
  # this the test would also pass against a T2 that never fires at all.
  run dlb 1 0
  [ "$status" -eq 0 ]
  [ "$(git -C "$SHARED" rev-parse HEAD)" = "$(git -C "$SHARED" rev-parse origin/main)" ]
}

@test "L7 T3 BLOCKED: every commit above live HEAD is RED ⇒ refuse + page, tree unmoved" {
  advance_origin b c
  stamp origin/main red; stamp "origin/main~1" red
  before="$(git -C "$SHARED" rev-parse HEAD)"
  run dlb 1 999
  [ "$status" -eq 1 ]
  [ "$(git -C "$SHARED" rev-parse HEAD)" = "$before" ]
  [[ "$output" == *"red all the way down"* ]] || false
  tip="$(git -C "$SHARED" rev-parse origin/main | cut -c1-12)"
  [ -f "$PAGES/deploy-trunk-red-$tip.page" ]      # its OWN class, not the generic blocked page
  head -1 "$PAGES/deploy-trunk-red-$tip.page" | grep -qE '^[0-9]+$'
  grep -q '2 commit(s) above live HEAD' "$PAGES/deploy-trunk-red-$tip.page"
}

@test "L8 a DIRTY tracked file blocks BY NAME — tree unmoved, file untouched, never stashed" {
  echo v1 > "$SHARED/shared.txt"; git -C "$SHARED" add -A; git -C "$SHARED" commit -q -m base
  git -C "$SHARED" push -q origin main
  base="$(git -C "$SHARED" rev-parse HEAD)"
  echo v2 > "$SHARED/shared.txt"; git -C "$SHARED" add -A; git -C "$SHARED" commit -q -m bump
  git -C "$SHARED" push -q origin main
  git -C "$SHARED" reset -q --hard "$base"       # trunk is 1 ahead and that commit rewrites shared.txt
  stamp origin/main                              # T1 has a green descendant — this is NOT a tier test
  printf 'peer session work\n' > "$SHARED/shared.txt"      # a peer's UNCOMMITTED edit to that path
  run dl
  [ "$status" -eq 1 ]
  [[ "$output" == *"DIRTY TREE"* ]] || false     # a named state, not "(dirty tree? diverged?)"
  [[ "$output" == *"shared.txt"* ]] || false     # …naming the blocking path
  [ "$(git -C "$SHARED" rev-parse HEAD)" = "$base" ]             # the tree did not move
  [ "$(cat "$SHARED/shared.txt")" = "peer session work" ]        # the peer's work is UNTOUCHED
  [ -f "$PAGES/deploy-dirty-tree.page" ]
  grep -q 'never stashes' "$PAGES/deploy-dirty-tree.page"
  [ ! -f "$INSTALL_LOG" ]                        # and nothing downstream of the merge ran
}

@test "L8b a dirty tracked file OUTSIDE the advance's path set does NOT block (no over-refusal)" {
  # The blocking set is an INTERSECTION. A pre-flight that refused on any dirty file would trade the
  # green-stamp freeze for a dirty-file freeze — this checkout is shared and is dirty most of the day.
  echo v1 > "$SHARED/untouched.txt"; git -C "$SHARED" add -A; git -C "$SHARED" commit -q -m base
  git -C "$SHARED" push -q origin main
  advance_origin b                               # b touches b.txt only, never untouched.txt
  stamp origin/main
  printf 'peer edit\n' > "$SHARED/untouched.txt"
  want="$(git -C "$SHARED" rev-parse origin/main)"
  run dl
  [ "$status" -eq 0 ]
  [ "$(git -C "$SHARED" rev-parse HEAD)" = "$want" ]
  [ "$(cat "$SHARED/untouched.txt")" = "peer edit" ]       # still the peer's, still uncommitted
}

@test "L8c an UNTRACKED file at a path the advance ADDS blocks BY NAME — never moved, never deleted" {
  # THE THIRD CAUSE (2026-08-11). merge_blockers() skips `??` and said so on the claim "untracked
  # cannot block a --ff-only" — false. Proven in a throwaway repo: an untracked file sitting where
  # the advance ADDS a tracked one gives "The following untracked working tree files would be
  # overwritten by merge" and exit 1. Pre-fix this test reaches the post-merge shrug ("BOTH named
  # causes RULED OUT"), which is the live symptom: deploy.log carries two of those, unexplained,
  # because git's stderr was discarded. The remedy half matters as much as the detection half — an
  # untracked file exists ONLY in this checkout, so no land, branch or stash can bring one back.
  advance_origin newfile                         # trunk ADDS newfile.txt; the layer stays put
  stamp origin/main                              # T1 has a green descendant — not a tier test
  base="$(git -C "$SHARED" rev-parse HEAD)"
  printf 'peer scratch, tracked by nobody\n' > "$SHARED/newfile.txt"   # the collision
  run dl
  [ "$status" -eq 1 ]
  [[ "$output" == *"UNTRACKED COLLISION"* ]] || false        # its OWN class, not the dirty one
  [[ "$output" != *"RULED OUT"* ]] || false                  # …named BEFORE the merge, not shrugged at after
  [[ "$output" == *"newfile.txt"* ]] || false                # …naming the blocking path
  [ "$(git -C "$SHARED" rev-parse HEAD)" = "$base" ]                          # the tree did not move
  [ "$(cat "$SHARED/newfile.txt")" = "peer scratch, tracked by nobody" ]      # the file is UNTOUCHED
  [ -f "$PAGES/deploy-untracked-collision.page" ]
  grep -q 'never moves or deletes' "$PAGES/deploy-untracked-collision.page"
  [ ! -f "$INSTALL_LOG" ]                        # and nothing downstream of the merge ran
}

@test "L8d an untracked file OUTSIDE the advance's added set does NOT block (no over-refusal)" {
  # The mirror of L8b, and it guards the same failure mode from the other side: the live checkout
  # carries 22 untracked paths on an ordinary day, so an arm that refused on ANY untracked file would
  # trade the green-stamp freeze for an untracked-file freeze and wedge the lane permanently.
  advance_origin b                               # b adds b.txt and nothing else
  stamp origin/main
  printf 'scratch\n' > "$SHARED/unrelated-scratch.txt"
  want="$(git -C "$SHARED" rev-parse origin/main)"
  run dl
  [ "$status" -eq 0 ]
  [ "$(git -C "$SHARED" rev-parse HEAD)" = "$want" ]         # it advanced anyway
  [ "$(cat "$SHARED/unrelated-scratch.txt")" = "scratch" ]   # still there, still untracked
}

@test "L8f a REDUNDANT untracked blocker is named PROVABLY LOSSLESS — and is still not removed" {
  # THE HALF THAT DID NOT LAND WITH THE THIRD CAUSE (item 40625550e49f, filed 2026-08-11T20:18Z;
  # b088240bb landed the DETECTION two hours later and stopped there). The refusal told every
  # operator "they exist only in this checkout, so no land, branch or stash can bring one back" —
  # true of the general case, FALSE of the one that actually wedged the lane. The live blocker was
  # docs/ground-up-payloads/LOCUS-GAP-BRIEF-2026-08-08.md, byte-identical to the blob trunk was
  # adding (same sha 1ed1c149) because someone drafted it in the SHARED checkout before the same
  # content landed from a worktree. Nothing was at risk; git's own "move or remove" was the cure;
  # the advance then went clean. The operator was told the pessimistic answer, and the live layer sat
  # 31 commits behind a budget of 25 with 13 ADDED files silently skipping every `[ -f x ] && . x`.
  #
  # THE FIXTURE MUST REACH THE ARM UNDER TEST, which is guard THREE in a chain: the green-stamp
  # ladder, then the dirty-TRACKED arm, then this one. A fixture that fell out earlier would exit
  # non-zero for the wrong reason and credit nothing — so the class is asserted, not just the code.
  advance_origin newfile                          # trunk ADDS newfile.txt containing "newfile\n"
  stamp origin/main
  base="$(git -C "$SHARED" rev-parse HEAD)"
  echo newfile > "$SHARED/newfile.txt"            # byte-identical to the incoming blob
  want_blob="$(git -C "$SHARED" rev-parse "origin/main:newfile.txt")"
  [ "$(git -C "$SHARED" hash-object --path newfile.txt -- "$SHARED/newfile.txt")" = "$want_blob" ]
  run dl
  [ "$status" -eq 1 ]
  [[ "$output" == *"UNTRACKED COLLISION"* ]] || false         # reached guard 3, not 1 or 2
  [[ "$output" == *"PROVABLY LOSSLESS"* ]] || false           # …and said the TRUE thing about it
  [ -f "$PAGES/deploy-untracked-collision.page" ]
  grep -q 'PROVABLY LOSSLESS' "$PAGES/deploy-untracked-collision.page"
  grep -q "rm $SHARED/newfile.txt" "$PAGES/deploy-untracked-collision.page"   # the EXACT command
  # …and the pessimistic claim is NOT made about a path it is false of. COUNTED, never `! grep -q`:
  # errexit skips an inverted rc, so a mid-test negation always passes (bats-assert-liveness flags it).
  [ "$(grep -c 'no land, branch or stash can bring one back' \
       "$PAGES/deploy-untracked-collision.page")" -eq 0 ]
  # B1 — CLASSIFY, NEVER ACT. "Provably lossless" licenses the OPERATOR's rm, not ours. This is the
  # lane's standing invariant and the row's literal "offer the move-aside" is NOT read as permission.
  [ "$(cat "$SHARED/newfile.txt")" = "newfile" ]              # the file is UNTOUCHED
  grep -q 'never moves or deletes' "$PAGES/deploy-untracked-collision.page"
  [ "$(git -C "$SHARED" rev-parse HEAD)" = "$base" ]          # the tree did not move
  [ ! -f "$INSTALL_LOG" ]

  # ARM 2 — the MUTANT. Neutering the classifier so every path answers "unique" IS the pre-fix
  # behaviour exactly, and it must lose the lossless verdict on this same fixture.
  [ "$(grep -c '^untracked_is_redundant() { # <to-sha>' "$DL")" -eq 1 ]
  MUT="$BATS_TEST_TMPDIR/dl-mut-noredundant.sh"
  sed 's@^untracked_is_redundant() { # .*@untracked_is_redundant() { return 1; # MUTANT@' "$DL" > "$MUT"
  [ "$(grep -c '^untracked_is_redundant() { # <to-sha>' "$MUT")" -eq 0 ]   # the mutant really mutated
  [ "$(grep -c 'return 1; # MUTANT' "$MUT")" -eq 1 ]
  rm -f "$PAGES/deploy-untracked-collision.page"
  run dlm "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"UNTRACKED COLLISION"* ]] || false         # same arm, same fixture…
  [[ "$output" != *"PROVABLY LOSSLESS"* ]] || false           # …and the verdict is GONE
  grep -q 'no land, branch or stash can bring one back' "$PAGES/deploy-untracked-collision.page"
}

@test "L8g an untracked blocker whose bytes DIFFER is never called lossless (fail-closed)" {
  # The discriminating half. An oracle that answered "redundant" for every collision would be green
  # on L8f and catastrophic here: it would tell the operator to rm the only copy of a peer's file.
  # One byte of difference is deliberate — the two cases are otherwise identical, so a test that
  # passed by accident on L8f's fixture cannot also pass here.
  advance_origin newfile
  stamp origin/main
  base="$(git -C "$SHARED" rev-parse HEAD)"
  printf 'newfile and one more byte\n' > "$SHARED/newfile.txt"
  run dl
  [ "$status" -eq 1 ]
  [[ "$output" == *"UNTRACKED COLLISION"* ]] || false
  [[ "$output" != *"PROVABLY LOSSLESS"* ]] || false
  [ -f "$PAGES/deploy-untracked-collision.page" ]
  [ "$(grep -c 'PROVABLY LOSSLESS' "$PAGES/deploy-untracked-collision.page")" -eq 0 ]
  grep -q 'NOT RECOVERABLE' "$PAGES/deploy-untracked-collision.page"
  grep -q 'no land, branch or stash can bring one back' "$PAGES/deploy-untracked-collision.page"
  [ "$(cat "$SHARED/newfile.txt")" = "newfile and one more byte" ]
  [ "$(git -C "$SHARED" rev-parse HEAD)" = "$base" ]
}

@test "L8h a SYMLINK to identical bytes is NOT lossless — the -L guard is load-bearing, not decor" {
  # THE FAIL-CLOSED CASE THAT LOOKS LIKE THE SAFE ONE. `git hash-object` FOLLOWS a symlink, so the
  # blob it computes here EQUALS the incoming blob (measured) and a hash-only oracle would declare
  # this provably lossless. It is not: `rm newfile.txt` removes the LINK, the merge writes a regular
  # file, and elsewhere.txt — the only thing that actually held those bytes as an untracked artifact
  # — is a different path the advance never restores. Uncertainty answers UNIQUE here because the two
  # errors are not symmetric: a false "redundant" invites deleting the only copy of something, a
  # false "unique" costs a hand-check.
  advance_origin newfile
  stamp origin/main
  base="$(git -C "$SHARED" rev-parse HEAD)"
  echo newfile > "$SHARED/elsewhere.txt"
  ln -s elsewhere.txt "$SHARED/newfile.txt"
  # the trap, pinned: hash-object through the link really does agree with the incoming blob, so this
  # test is not passing because the shas happen to differ.
  [ "$(git -C "$SHARED" hash-object --path newfile.txt -- "$SHARED/newfile.txt")" \
    = "$(git -C "$SHARED" rev-parse "origin/main:newfile.txt")" ]
  run dl
  [ "$status" -eq 1 ]
  [[ "$output" == *"UNTRACKED COLLISION"* ]] || false
  [[ "$output" != *"PROVABLY LOSSLESS"* ]] || false
  [ -L "$SHARED/newfile.txt" ]                                # still a link, still untouched
  [ "$(git -C "$SHARED" rev-parse HEAD)" = "$base" ]

  # ARM 2 — strip the -L guard and the oracle DOES call it lossless. Without this arm the guard could
  # be deleted tomorrow and every test above would stay green.
  [ "$(grep -c 'symlink: -f follows it' "$DL")" -eq 1 ]
  MUT="$BATS_TEST_TMPDIR/dl-mut-nolinkguard.sh"
  sed '/symlink: -f follows it/d' "$DL" > "$MUT"
  [ "$(grep -c 'symlink: -f follows it' "$MUT")" -eq 0 ]
  run dlm "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"PROVABLY LOSSLESS"* ]] || false           # the guard was the only thing stopping it
}

@test "L8e a merge failure NO pre-flight models reports GIT'S OWN words, never a shrug" {
  # The generic half of the same defect, and the one that covers the causes this lane will never
  # model. `>/dev/null 2>&1` discarded git's stderr, then the arm below told the operator "read git
  # status by hand" — asking them to re-derive what it had just deleted. index.lock is the realistic
  # instance rather than a contrived one: the live checkout is SHARED and its reflog shows a second
  # actor fast-forwarding it, so a concurrent git holding the lock is the standing explanation for
  # the two unexplained "RULED OUT" refusals in deploy.log.
  #
  # It also pins the new oracle's FAIL-OPEN contract: read-tree -n hits the same lock and dies
  # "fatal: Unable to create …", which is NOT the untracked pattern, so untracked_blockers must
  # yield nothing and let the merge speak. An oracle that guessed a class from an unparsed error
  # would refuse here under the wrong name.
  advance_origin b
  stamp origin/main
  base="$(git -C "$SHARED" rev-parse HEAD)"
  touch "$SHARED/.git/index.lock"                # a concurrent git in the shared checkout
  run dl
  [ "$status" -eq 1 ]
  [[ "$output" == *"GIT SAID"* ]] || false                   # git's own words reached the operator…
  [[ "$output" == *"index.lock"* ]] || false                 # …naming a cause no pre-flight here models
  [[ "$output" != *"UNTRACKED COLLISION"* ]] || false        # the new oracle failed OPEN, not into a wrong class
  [ "$(git -C "$SHARED" rev-parse HEAD)" = "$base" ]
  [ ! -f "$INSTALL_LOG" ]
}

@test "L9 the launchd job execs even when the ~/.claude symlink is ABSENT (59 exec failures)" {
  P="$REPO/launchd/com.claude.deploy-live.plist"
  run plutil -lint "$P"
  [ "$status" -eq 0 ]
  # Run the plist's OWN command string, not a copy of it — a hand-retyped approximation would pass
  # vacuously the moment the two drift.
  cmd="$(plutil -extract ProgramArguments.2 raw -o - "$P")"
  fake="$BATS_TEST_TMPDIR/fakehome"
  mkdir -p "$fake/Development/claude-infrastructure/scripts"
  printf '#!/bin/bash\nprintf "REACHED %%s\\n" "$*"\n' \
    > "$fake/Development/claude-infrastructure/scripts/deploy-live.sh"
  chmod +x "$fake/Development/claude-infrastructure/scripts/deploy-live.sh"
  # the repo copy exists; the symlink the job used to exec unconditionally does NOT — exactly the
  # state in which it logged 59 × "cannot execute: No such file or directory" and never started.
  run env HOME="$fake" /bin/bash -c "$cmd"
  [ "$status" -eq 0 ]
  [[ "$output" == *"REACHED --auto"* ]] || false
  # …and the LIVE layer still wins when it is there: a fallback that shadowed the deploy would make
  # every future advance of this script inert.
  mkdir -p "$fake/.claude/scripts"
  printf '#!/bin/bash\nprintf "LIVE %%s\\n" "$*"\n' > "$fake/.claude/scripts/deploy-live.sh"
  chmod +x "$fake/.claude/scripts/deploy-live.sh"
  run env HOME="$fake" /bin/bash -c "$cmd"
  [ "$status" -eq 0 ]
  [[ "$output" == *"LIVE --auto"* ]] || false
}

@test "the real assert emits the MISSING contract this refresh parses (the stub is not the spec)" {
  # Guards the seam between the two files: if deploy-parity-assert.sh ever renames the prefix or
  # reorders the fields, every test above keeps passing against the stub while production goes inert.
  run grep -n "MISSING: ln -sf %s %s" "$REPO/scripts/deploy-parity-assert.sh"
  [ "$status" -eq 0 ]
  run grep -n "MISSING: ln -sf " "$REPO/scripts/deploy-live.sh"
  [ "$status" -eq 0 ]
}

# ── --offline · the DECISION-ONLY probe the operator platter asks for a verdict (§2.6 D5 / V9) ────
# bin/cc-do and hooks/operator-readout.sh used to platter `bash …/deploy-live.sh` as the operator's
# RUN 1 while that exact command had refused 534 consecutive times. They now ask THIS script whether
# an advance is possible rather than re-deriving its tier ladder in a renderer — one arbiter, so the
# two surfaces cannot drift from the policy or from each other. They ask with `--offline`, and three
# of its properties are load-bearing. One leg each, below.

@test "--offline reaches the SAME verdict as a fetching run (T1 green target)" {
  advance_origin b c
  stamp origin/main
  want="$(git -C "$SHARED" rev-parse origin/main)"
  run dl --dry-run --offline
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "would fast-forward .* → ${want:0:12}" || false
  # …and the fetching spelling agrees, which is what makes --offline a COST change and not a POLICY
  # change. A probe that answered differently from the run it predicts would be its own defect.
  run dl --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "would fast-forward .* → ${want:0:12}" || false
}

@test "--offline decides with the remote UNREACHABLE — the absence of the fetch, not a lucky answer" {
  # The strong form of "it does not touch the network": break the remote and require the RIGHT
  # verdict anyway. This matters twice. operator-readout.sh is a Stop hook, so a fetching probe puts
  # a network round-trip on every turn close; and decisively, a FAILED fetch `die`s rc 1, which the
  # caller reads as "the lane refuses" — a renderer reporting a deploy blocker THAT IT CAUSED.
  advance_origin b
  stamp origin/main
  want="$(git -C "$SHARED" rev-parse origin/main)"
  git -C "$SHARED" remote set-url origin "$BATS_TEST_TMPDIR/no-such-origin.git"
  run dl --dry-run --offline
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "would fast-forward .* → ${want:0:12}" || false
}

@test "CONTROL: the same state WITHOUT --offline dies on the fetch (so the leg above proves absence)" {
  # Without this pair the test above passes on a box whose broken remote is never contacted for some
  # unrelated reason — an absence assertion needs a positive control that CAN fail the same way.
  advance_origin b
  stamp origin/main
  git -C "$SHARED" remote set-url origin "$BATS_TEST_TMPDIR/no-such-origin.git"
  run dl --dry-run
  [ "$status" -ne 0 ]
  echo "$output" | grep -q 'git fetch origin main FAILED' || false
}

@test "--offline with NO already-fetched origin/main REFUSES — unknown is never assumed safe" {
  # The fail direction is the whole design: a caller that cannot learn the tip must be told so, not
  # handed a pass. Deleting the remote-tracking ref is the reachable spelling of a checkout that has
  # never fetched — and the guard must fire BEFORE the generic "cannot resolve" death, or its own
  # message never reaches the renderer that has to explain the state.
  advance_origin b
  stamp origin/main
  git -C "$SHARED" update-ref -d refs/remotes/origin/main
  run dl --dry-run --offline
  [ "$status" -ne 0 ]
  echo "$output" | grep -q 'no already-fetched origin/main' || false
}

@test "the T1/T1H/T2 ladders read sha+tree from ONE process, not a rev-parse fork per commit" {
  # A performance change to the SELECTION path is a correctness risk, so this pins the mechanism the
  # behaviour tests above exercise: 200 x `rev-parse <sha>^{tree}` measured 2.233s against 0.011s
  # for `git log --format`, and that 200x IS the whole cost of an evaluation — the lane runs 144x/day
  # and the platter probe has to be cheap enough for a Stop hook. `git log --format` is the
  # header-free spelling of `rev-list --format`; the sha lists were verified identical.
  # ANCHORED TO CODE, NOT PROSE (`^[^#]*` — nothing but non-# before the match). The first spelling
  # of this test counted the old pattern anywhere in the file and went red on deploy-live.sh's OWN
  # comment explaining the removal: a guard that forbids NAMING the defect you fixed also deletes
  # its provenance, and a text guard that cannot tell code from a comment fails in both directions.
  # FLOOR + A PINNED ZERO, not an exact count. This assertion was `-eq 2` and went red the moment a
  # THIRD ladder (T1H) was added that uses the one-process read CORRECTLY — an exact count over a
  # population that is expected to grow can only fire on its own subject's growth, never on the
  # regression it was written for (memory: exact-count-assertion-tripwires-its-own-subject). The
  # property is "every ladder uses the cheap read AND no ladder forks per commit", so the floor
  # tracks the ladders that exist and the zero is what actually guards the defect.
  run grep -c "^[^#]*log --format='%H %T'" "$DL"
  [ "$status" -eq 0 ]
  [ "$output" -ge 3 ]                                   # T1, T1H and T2 — at least one per ladder
  run grep -c '^[^#]*rev-parse "\$sha^{tree}"' "$DL"
  [ "$output" -eq 0 ]                                   # and the per-commit fork is gone from the code
}

@test "--offline ALONE never mutates — decision-only, even without --dry-run" {
  # A no-network mode that could still really merge would deploy an arbitrarily stale tip without
  # ever saying it had not looked. It is also what takes this mode OFF the actuation path, which is
  # what lets its missing-ref refusal above declare `gate_bounded:` honestly: a gate that cannot
  # withhold an advance can only decline to answer. Asserted on the TREE, not on the banner.
  advance_origin b
  stamp origin/main
  before="$(git -C "$SHARED" rev-parse HEAD)"
  run dl --offline
  [ "$status" -eq 0 ]
  [ "$(git -C "$SHARED" rev-parse HEAD)" = "$before" ]      # the layer did not move
  [ ! -f "$INSTALL_LOG" ]                                   # and install.sh was never invoked
  echo "$output" | grep -q 'DRY RUN' || false
}

@test "CONTROL: the same call WITH a fetch and no --offline DOES deploy (so the leg above is not vacuous)" {
  # Without this, "--offline does not mutate" is satisfied by a fixture in which nothing would have
  # deployed anyway — the vacuous-control shape §2.8 A-6 names. Same state, one flag removed.
  advance_origin b
  stamp origin/main
  want="$(git -C "$SHARED" rev-parse origin/main)"
  run dl
  [ "$status" -eq 0 ]
  [ "$(git -C "$SHARED" rev-parse HEAD)" = "$want" ]
  [ -f "$INSTALL_LOG" ]
}

# ── T1H · the SECOND green producer's tier (backlog b4f93c9fa73c) ────────────────────────────────
# The off-box store is a SEPARATE directory from stamps/ on purpose: no consumer of stamps/ reads
# any field but .verdict, so a subset green written there would silently become a T1 target. These
# tests are the RED-controls for that separation and for the tier's two conjuncts.

offbox_stamp() { # <rev> [scope] — write an off-box GREEN for that rev's TREE
  local tree; tree="$(git -C "$SHARED" rev-parse "$1^{tree}")"
  mkdir -p "$BATS_TEST_TMPDIR/postland/offbox"
  printf '{"verdict":"green","tree":"%s","scope":"%s","producer":"github-actions"}\n' \
    "$tree" "${2:-offbox-hermetic}" > "$BATS_TEST_TMPDIR/postland/offbox/$tree.json"
}

@test "H1 T1H advances on an OFF-BOX green with NO lag budget tripped, and names the reduced scope" {
  advance_origin b c
  offbox_stamp origin/main
  want="$(git -C "$SHARED" rev-parse origin/main)"
  run dlb 999 999                                # both budgets pinned OUT — T2 cannot fire
  [ "$status" -eq 0 ]
  [ "$(git -C "$SHARED" rev-parse HEAD)" = "$want" ]
  [[ "$output" == *"HERMETIC deploy"* ]] || false
  [[ "$output" == *"machine-coupled suites are NOT covered"* ]] || false
  [[ "$output" != *"DEGRADED deploy"* ]] || false
  [ "$(find "$PAGES" -name 'deploy-degraded-*.page' 2>/dev/null | wc -l | tr -d ' ')" -eq 0 ]
}

@test "H2 CONTROL — with the off-box stamp REMOVED the identical setup refuses" {
  # Without this, H1 proves only that the lane advanced, not that the OFF-BOX STAMP is why.
  advance_origin b c
  before="$(git -C "$SHARED" rev-parse HEAD)"
  run dlb 999 999
  [ "$status" -ne 0 ]
  [ "$(git -C "$SHARED" rev-parse HEAD)" = "$before" ]
  [[ "$output" != *"HERMETIC deploy"* ]] || false
}

@test "H3 an on-box RED on the same tree BLOCKS T1H — the subset must not overrule what it cannot see" {
  advance_origin b c
  offbox_stamp origin/main
  stamp origin/main red                          # the on-box verifier judged this very tree RED
  before="$(git -C "$SHARED" rev-parse HEAD)"
  run dlb 999 999
  [ "$status" -ne 0 ]
  [ "$(git -C "$SHARED" rev-parse HEAD)" = "$before" ]
  [[ "$output" != *"HERMETIC deploy"* ]] || false
}

@test "H3b CONTROL — a CUT on that tree does NOT block T1H (R6: a non-verdict is not a red)" {
  advance_origin b c
  offbox_stamp origin/main
  stamp origin/main cut
  want="$(git -C "$SHARED" rev-parse origin/main)"
  run dlb 999 999
  [ "$status" -eq 0 ]
  [ "$(git -C "$SHARED" rev-parse HEAD)" = "$want" ]
  [[ "$output" == *"HERMETIC deploy"* ]] || false
}

@test "H4 a green WITHOUT scope:offbox-hermetic is NOT eligible for T1H" {
  # The conflation the separate directory exists to prevent, tested at the reader: a full-corpus
  # shaped record ({"verdict":"green"}) dropped into offbox/ must not be spendable as T1H.
  advance_origin b c
  local tree; tree="$(git -C "$SHARED" rev-parse "origin/main^{tree}")"
  mkdir -p "$BATS_TEST_TMPDIR/postland/offbox"
  printf '{"verdict":"green","tree":"%s"}\n' "$tree" > "$BATS_TEST_TMPDIR/postland/offbox/$tree.json"
  before="$(git -C "$SHARED" rev-parse HEAD)"
  run dlb 999 999
  [ "$status" -ne 0 ]
  [ "$(git -C "$SHARED" rev-parse HEAD)" = "$before" ]
}

@test "H4b CONTROL — the same record WITH the scope field is eligible" {
  advance_origin b c
  offbox_stamp origin/main
  run dlb 999 999
  [ "$status" -eq 0 ]
  [[ "$output" == *"HERMETIC deploy"* ]] || false
}

@test "H5 T1 still WINS over T1H — a full-corpus green outranks a subset one" {
  advance_origin b c
  stamp "origin/main~1"                          # b: FULL green, a descendant of live HEAD
  offbox_stamp origin/main                       # c: off-box green, newer
  want="$(git -C "$SHARED" rev-parse "origin/main~1")"
  run dlb 999 999
  [ "$status" -eq 0 ]
  [ "$(git -C "$SHARED" rev-parse HEAD)" = "$want" ]        # b, not the newer off-box c
  [[ "$output" != *"HERMETIC deploy"* ]] || false
}

@test "H6 T1H OUTRANKS T2 — positive evidence beats absence, and no degraded page is written" {
  advance_origin b c
  offbox_stamp "origin/main~1"                   # b is off-box green; c is unstamped everywhere
  want="$(git -C "$SHARED" rev-parse "origin/main~1")"
  run dlb 0 0                                    # budget wide open: T2 would take the TIP c
  [ "$status" -eq 0 ]
  [ "$(git -C "$SHARED" rev-parse HEAD)" = "$want" ]        # b — T1H's choice, not T2's tip
  [[ "$output" == *"HERMETIC deploy"* ]] || false
  [ "$(find "$PAGES" -name 'deploy-degraded-*.page' 2>/dev/null | wc -l | tr -d ' ')" -eq 0 ]
}

@test "H7 CC_DEPLOY_OFFBOX=off restores the previous ladder exactly (a switch that cannot kill is not one)" {
  advance_origin b c
  offbox_stamp origin/main
  before="$(git -C "$SHARED" rev-parse HEAD)"
  run env DEPLOY_REPO="$SHARED" CC_POSTLAND_DIR="$BATS_TEST_TMPDIR/postland" CC_PAGES_DIR="$PAGES" \
      CC_DEPLOY_MAX_LAG_COMMITS=999 CC_DEPLOY_MAX_LAG_HOURS=999 CC_DEPLOY_OFFBOX=off \
      /bin/bash "$DL"
  [ "$status" -ne 0 ]
  [ "$(git -C "$SHARED" rev-parse HEAD)" = "$before" ]
  [[ "$output" != *"HERMETIC"* ]] || false
}

@test "H8 the puller is BOUNDED — a hanging pull cannot become a deploy refusal" {
  # The add-on rule: a side-car must fail no wider than itself. A pull that hangs must cost the lane
  # its bound and nothing else — not the evaluation, and not the advance.
  advance_origin b c
  offbox_stamp origin/main
  local stub="$BATS_TEST_TMPDIR/hang-pull.sh"
  printf '#!/bin/bash\nsleep 30\n' > "$stub"; chmod +x "$stub"
  want="$(git -C "$SHARED" rev-parse origin/main)"
  local t0 t1
  t0="$(date +%s)"
  run env DEPLOY_REPO="$SHARED" CC_POSTLAND_DIR="$BATS_TEST_TMPDIR/postland" CC_PAGES_DIR="$PAGES" \
      CC_DEPLOY_MAX_LAG_COMMITS=999 CC_DEPLOY_MAX_LAG_HOURS=999 \
      CC_OFFBOX_PULL_BIN="$stub" CC_DEPLOY_OFFBOX_PULL_S=2 \
      /bin/bash "$DL"
  t1="$(date +%s)"
  [ "$status" -eq 0 ]                                       # the hang did NOT refuse the deploy
  [ "$(git -C "$SHARED" rev-parse HEAD)" = "$want" ]         # and did NOT stop the advance
  [ "$(( t1 - t0 ))" -lt 20 ]                                # bounded well under the stub's 30s
}

@test "H9 an ABSENT puller is a no-op, not an error — the lane runs unchanged without it" {
  advance_origin b c
  offbox_stamp origin/main
  want="$(git -C "$SHARED" rev-parse origin/main)"
  run env DEPLOY_REPO="$SHARED" CC_POSTLAND_DIR="$BATS_TEST_TMPDIR/postland" CC_PAGES_DIR="$PAGES" \
      CC_DEPLOY_MAX_LAG_COMMITS=999 CC_DEPLOY_MAX_LAG_HOURS=999 \
      CC_OFFBOX_PULL_BIN="$BATS_TEST_TMPDIR/does-not-exist" /bin/bash "$DL"
  [ "$status" -eq 0 ]
  [ "$(git -C "$SHARED" rev-parse HEAD)" = "$want" ]
}

# ── G · A GREEN ON LIVE HEAD IS A STATE, NOT A TARGET (2026-08-10, backlog 3b22efbc2340) ──────────
# `merge-base --is-ancestor X X` is TRUE, so T1's ancestry test used to match live HEAD against
# ITSELF and set TARGET=HEAD. Everything below T1 is wrapped in `if [ -z "$TARGET" ]`, so that one
# reflexive match skipped T1H and T2 entirely and made the lag budget STRUCTURALLY UNREACHABLE:
# once the layer sat on any green tree the lane said "already deployed" and exited 0 however far
# trunk ran ahead — and under --auto that path is SILENT by design. One green FROZE the layer where
# zero greens did not, which is strictly worse than the loud refusal it replaced.
# G1/G2 are a discriminating PAIR: identical shape, the only difference is whether HEAD is green.
# Before the fix G1 failed and G2 passed, so the pair indicts the reflexive match and nothing else.

@test "G1 a green ON live HEAD does NOT freeze the ladder — T2 still degrades past the budget" {
  advance_origin b c d
  stamp HEAD green                               # the live layer's OWN tree is green
  before="$(git -C "$SHARED" rev-parse HEAD)"
  run dlb 2 999                                  # lag 3 > budget 2 ⇒ T2 is authorised
  [ "$status" -eq 0 ] || false
  [ "$(git -C "$SHARED" rev-parse HEAD)" != "$before" ] || false
  [ "$(git -C "$SHARED" rev-list --count HEAD..origin/main)" -eq 0 ] || false
  [[ "$output" == *"DEGRADED deploy"* ]] || false
  # the refusal text names the real state, not a rollback hazard that is not present
  [[ "$output" == *"newest GREEN tree IS live HEAD"* ]] || false
}

@test "G2 CONTROL — the identical shape with NO green anywhere degrades too (so G1 is not vacuous)" {
  advance_origin b c d
  before="$(git -C "$SHARED" rev-parse HEAD)"
  run dlb 2 999
  [ "$status" -eq 0 ] || false
  [ "$(git -C "$SHARED" rev-parse HEAD)" != "$before" ] || false
  [[ "$output" == *"DEGRADED deploy"* ]] || false
}

@test "G3 INSIDE the budget a green on HEAD is still the benign 'already deployed' exit 0" {
  # The state the fix must NOT convert into a refusal: green on the layer, a few unstamped commits
  # above, lag well inside budget. Exit 0, no advance, and it still says "already deployed".
  advance_origin b c
  stamp HEAD green
  before="$(git -C "$SHARED" rev-parse HEAD)"
  run dlb 25 999
  [ "$status" -eq 0 ] || false
  [ "$(git -C "$SHARED" rev-parse HEAD)" = "$before" ] || false
  [[ "$output" == *"already deployed"* ]] || false
  [[ "$output" == *"2 un-stamped commit(s) above"* ]] || false
}

@test "G4 T1H OUTRANKS the green-on-HEAD rest state — a proven tree deploys, budget or not" {
  # Ordering proof: the benign exit sits AFTER T1H, so positive off-box evidence above the layer
  # still advances instead of being swallowed by "already deployed". Budget deliberately wide open.
  advance_origin b c
  stamp HEAD green
  offbox_stamp origin/main
  want="$(git -C "$SHARED" rev-parse origin/main)"
  run dlb 999 999
  [ "$status" -eq 0 ] || false
  [ "$(git -C "$SHARED" rev-parse HEAD)" = "$want" ] || false
  [[ "$output" == *"HERMETIC deploy"* ]] || false
}

@test "G5 past the budget with trunk RED all the way down: green-on-HEAD refuses LOUDLY, not exit 0" {
  # The freeze is still a freeze — the fix must not launder it into silence. Everything above the
  # layer is red, so T2 finds nothing and T3 refuses with a page, despite HEAD being green.
  advance_origin b c
  stamp HEAD green
  stamp origin/main red
  stamp "origin/main~1" red
  before="$(git -C "$SHARED" rev-parse HEAD)"
  run dlb 1 999
  [ "$status" -ne 0 ] || false
  [ "$(git -C "$SHARED" rev-parse HEAD)" = "$before" ] || false
  [[ "$output" == *"red all the way down"* ]] || false
}

# ── J · INSIDE THE BUDGET IS A WAIT, ON EVERY FACE OF IT (2026-08-10, backlog 2e7fe6fd5b7c) ────────
# G (above) gave the green-AT-head state its benign in-budget exit. It has a SIBLING FACE that G did
# not reach: the newest green sitting strictly BEHIND live HEAD — the shape a previous DEGRADED (T2)
# advance leaves behind, because a degraded deploy moves the layer without minting a green for where
# it landed. Both faces say the same thing about the only question this lane answers — "is anything
# above the layer proven?" — and the answer is no in both. But only one had an exit: green-at-head
# exits 0 and waits, green-behind fell through T1/T1H/T2 to T3's `die`.
#
# MEASURED on the live box 2026-08-10T19:5xZ, and it is what dispatched this item: live HEAD
# 5f63cdc1 with the newest green ed095d4b one step behind it, lag 24 commit(s) / 5h against a budget
# of 25 / 6h — INSIDE both budgets on both axes — and the lane refused, wrote a
# `deploy-blocked-*.page` reading "the live layer is FROZEN until a tree verifies green", and exited
# 1. Every clause of that page was wrong about the state: nothing was frozen, the budget had not
# tripped, and T2 would have degraded of its own accord an hour later. It is the SAME defect class
# G was built for and the SAME cost the at-tip fix names at deploy-live.sh:790 — a lane pinned at
# exit 1 through its healthy steady state, where the next REAL refusal is indistinguishable from
# the noise.
#
# THE IN-BUDGET ARM ITSELF is not re-tested here — it is the "WITHIN BUDGET … ⇒ WAITS" test above,
# flipped in place against the shared `deadlock()` fixture, and its past-budget sibling L2 is the
# other half of that A/B. Re-rolling the same fixture under a J label would have given this file two
# spellings of one assertion, and the pair would then drift apart on whichever one a later change
# happened to touch. What J adds is only what nothing else holds: the three exclusions below, each
# of which is a capability the fix is close enough to delete that it must be pinned.

@test "J1 past the budget with trunk RED all the way down: green-BEHIND refuses LOUDLY, not exit 0" {
  # G5's sibling on this face. A genuine freeze must stay a freeze — T2 finds only red, so T3
  # refuses, and the benign wait must not swallow it.
  deadlock
  stamp origin/main red
  stamp "origin/main~1" red
  before="$(git -C "$SHARED" rev-parse HEAD)"
  run dlb 1 999
  [ "$status" -ne 0 ] || false
  [ "$(git -C "$SHARED" rev-parse HEAD)" = "$before" ] || false
  [[ "$output" == *"red all the way down"* ]] || false
}

@test "J2 NO green anywhere inside the budget still REFUSES — absence is the alarm, not a wait" {
  # The face deliberately left OUT of the wait, and the load-bearing exclusion. green-behind proves
  # the producer WORKS (it minted that green), so a green above is plausibly coming and waiting is
  # honest. No green in the whole scan window is the VERIFIER-INERT condition, where the net may
  # simply be dead — waiting quietly there is the exact failure mode the loudness exists for.
  # Identical to the deadlock fixture except that the one green stamp is never written, so the pair
  # is a clean A/B on the presence of a green and nothing else.
  commit_push b; git -C "$SHARED" push -q origin main
  advance_origin c d
  before="$(git -C "$SHARED" rev-parse HEAD)"
  run dlb 25 999                                    # the same in-budget lag the wait exits 0 on
  [ "$status" -ne 0 ] || false
  [ "$(git -C "$SHARED" rev-parse HEAD)" = "$before" ] || false
  [[ "$output" == *"REFUSED"* ]] || false
}

@test "J3 with the degrade kill switch OFF the in-budget wait REFUSES — a wait that cannot end" {
  # CC_DEPLOY_DEGRADE=off is the operator electing a strict green-only gate, which means T2 can
  # never fire and "wait for the budget" is waiting for something that will never arrive. Exiting 0
  # there would convert their deliberate strictness into permanent silence.
  deadlock
  before="$(git -C "$SHARED" rev-parse HEAD)"
  run env DEPLOY_REPO="$SHARED" CC_POSTLAND_DIR="$BATS_TEST_TMPDIR/postland" CC_PAGES_DIR="$PAGES" \
          CC_DEPLOY_MAX_LAG_COMMITS=25 CC_DEPLOY_MAX_LAG_HOURS=999 CC_DEPLOY_DEGRADE=off \
          /bin/bash "$DL"
  [ "$status" -ne 0 ] || false
  [ "$(git -C "$SHARED" rev-parse HEAD)" = "$before" ] || false
  [[ "$output" == *"REFUSED"* ]] || false
}

# ── R7 · a fail-closed path must ESCALATE on repetition (backlog f495d5374c01, §5 row P5) ─────────
# The lane was measured refusing 601 consecutive times with ZERO escalations: subject+state damping
# makes one refusal quiet (correct) and then makes every subsequent one quiet FOREVER (the defect).
# Every test below fixes one half of that — the loud half past the threshold, and the quiet half
# below it. Both, or the guard is only half-proven (memory: guard-proxy-fails-in-both-directions).

R7_REF="" # set in r7_setup — the streak file the script writes

r7_setup() {
  auto_setup
  R7_REF="$BATS_TEST_TMPDIR/postland/deploy-refusals"
}

dlr() { # deploy-live --auto with the R7 knobs pinned and every side channel spied
  env DEPLOY_REPO="$SHARED" CC_POSTLAND_DIR="$BATS_TEST_TMPDIR/postland" CC_PAGES_DIR="$PAGES" \
      CC_DEPLOY_BATS_BIN="$SPY" CC_BACKLOG_BIN="$BLSPY" CC_DEPLOY_TIMEOUT_BIN= \
      CC_DEPLOY_MAX_LAG_COMMITS="${R7_LAGC:-999}" CC_DEPLOY_MAX_LAG_HOURS="${R7_LAGH:-999}" \
      CC_DEPLOY_REFUSE_MAX="${R7_MAX:-3}" CC_DEPLOY_REFUSE_COOLOFF="${R7_COOL:-21600}" \
      CC_DEPLOY_SCAN="${R7_SCAN:-200}" CC_DEPLOY_BLIND_SCAN="${R7_BLIND:-2000}" \
      CC_DEPLOY_DEGRADE="${R7_DEGRADE:-on}" PATH="${R7_PATH:-$PATH}" \
      /bin/bash "$DL" --auto "$@"
}

r7_famine() { # stamps dir exists, nothing green anywhere, commits stranded above, budget NOT tripped
  advance_origin b c d                  # three commits above the live layer, none stamped
}

@test "R7 THE DEFECT: a refusal that REPEATS past the threshold escalates — it is not damped forever" {
  # PRE-FIX THIS IS RED. Before this arm, tick 1 pages and every tick after it is byte-for-byte
  # silent at any repetition count (601 measured on the live host). The assertion that fails is the
  # one on the LATER ticks: no ESCALATED token, no backlog row, ever.
  r7_setup; r7_famine
  run dlr; [ "$status" -eq 1 ]                       # tick 1 — loud (the damp's first page)
  [[ "$output" != *"ESCALATED"* ]] || false          # ...but NOT an escalation: once is not repetition
  run dlr; [ "$status" -eq 1 ]; [ -z "$output" ]     # tick 2 — damped silent, correctly
  run dlr; [ "$status" -eq 1 ]                       # tick 3 == REFUSE_MAX — repetition IS the signal
  [[ "$output" == *"ESCALATED verdict=escalated"* ]] || false
  [[ "$output" == *"class=no-green"* ]] || false
  [[ "$output" == *"n=3"* ]] || false
  # …and it reached the store that OUTLIVES the run and that the operator block renders.
  grep -q "needs" "$CC_BACKLOG_LOG" || false
  grep -q "deploy lane refusing on repeat" "$CC_BACKLOG_LOG" || false
}

@test "R7 THE QUIET HALF: below the threshold NOTHING is emitted — one refusal is the lane working" {
  # The control for the test above. A guard proven in one direction only is half a guard: an
  # escalation that fired on every refusal would carry exactly as many bits as one that never fires.
  r7_setup; r7_famine
  R7_MAX=99                                          # unreachable in this test's tick budget
  run dlr; [ "$status" -eq 1 ]                       # the ONE loud refusal, as before
  [[ "$output" != *"ESCALATED"* ]] || false
  for _ in 1 2 3 4 5; do run dlr; [ "$status" -eq 1 ]; [ -z "$output" ] || false; done
  [ ! -f "$CC_BACKLOG_LOG" ] || ! grep -q "deploy lane refusing on repeat" "$CC_BACKLOG_LOG" || false
  [ -z "$(find "$PAGES" -name 'deploy-refusal-escalation-*' 2>/dev/null)" ] || false
  # ...and the counter WAS running the whole time, so the silence is a budget and not a broken arm.
  [ "$(awk '{print $2}' "$R7_REF")" -eq 6 ] || false
}

# The SIBLING of the HOST_CUT_MAX=0 case further up, and it is a REGRESSION PIN, not a fix: this
# knob's comment makes the same "0 disables either half" promise, and unlike HOST_CUT_MAX it already
# keeps it — refusal_bump's `[ "$REFUSE_MAX" -gt 0 ] || return 0` rejects 0 before the `-lt` guard
# that would otherwise mis-read it (`n < 0` is never true, so 0 would escalate on the FIRST refusal).
# Nothing about the counter is otherwise disabled, so the assertion has to be that the LEDGER never
# appears at all — the function returns before it is written.
@test "R7 REFUSE_MAX=0 DISABLES the counter — the sibling knob keeps the same promise" {
  r7_setup; r7_famine
  R7_MAX=0
  run dlr; [ "$status" -eq 1 ]                       # tick 1 — the ordinary damped refusal, unchanged
  [[ "$output" != *"ESCALATED"* ]] || false
  for _ in 1 2 3 4 5 6 7; do run dlr; [ "$status" -eq 1 ]; [ -z "$output" ] || false; done
  [ ! -f "$R7_REF" ]                                 # never even opened its ledger, at 8 refusals
  [ ! -f "$CC_BACKLOG_LOG" ] || ! grep -q "deploy lane refusing on repeat" "$CC_BACKLOG_LOG" || false
  [ -z "$(find "$PAGES" -name 'deploy-refusal-escalation-*' 2>/dev/null)" ] || false
}

@test "R7 the STRUCTURAL-BLINDNESS case is its OWN culprit, never 'the verifier is red'" {
  # §2.E's measured shape: the newest on-trunk GREEN sat 320 commits down against SCAN_N=200, so the
  # ladder could not see a green that EXISTED. Reporting that as a red verifier sends the operator
  # to fix the wrong machine. SCAN_N=2 here reproduces it at fixture scale.
  #
  # PATH IS PINNED TO /usr/bin:/bin, AND THAT PIN IS THE TEST'S SHARPEST ASSERTION. The probe's
  # first spelling used `awk -v list=…`, which macOS /usr/bin/awk (BWK) REFUSES when the value
  # carries newlines — rc 2, no output, so the blindness verdict could never fire under launchd,
  # whose PATH has no homebrew. It went green here anyway, on a homebrew awk this suite happened to
  # resolve. Unpinned, this test asserts a property of whoever's PATH ran it
  # (memory: hermetic-in-stubs-not-in-interpreter).
  r7_setup
  advance_origin b c d
  stamp HEAD                                         # green at depth 4 of origin/main…
  R7_SCAN=2 R7_PATH=/usr/bin:/bin                    # …and the ladder only ever looks 2 deep
  run dlr; run dlr; run dlr
  [[ "$output" == *"culprit=scan-window-blind"* ]] || false
  [[ "$output" == *"green_depth=4"* ]] || false
  [[ "$output" == *"scan_n=2"* ]] || false
  grep -q "OUTSIDE the scan window" "$CC_BACKLOG_LOG" || false
  # the page says WHY raising the scan is not loosening the gate — the operator's first objection
  grep -q "does NOT loosen the gate" "$PAGES/deploy-refusal-escalation-scan-window-blind.page" || false
}

@test "R7 CONTROL: with NO green anywhere the same repetition is a FAMINE, not blindness" {
  # The discriminator between the two culprits is the existence of a green outside the window. This
  # is the identical tick sequence with that one fact removed — if the probe ever degenerated into
  # "always blame the window", this test goes red and the one above would not.
  r7_setup; r7_famine
  R7_SCAN=2
  run dlr; run dlr; run dlr
  [[ "$output" == *"culprit=verifier-famine"* ]] || false
  [[ "$output" == *"green_depth=-"* ]] || false
  [[ "$output" != *"scan-window-blind"* ]] || false
  grep -q "verifier famine" "$CC_BACKLOG_LOG" || false
}

@test "R7 a green the ladder SAW but cannot deploy is verifier-LAG, never famine" {
  # Caught in the live replay BEFORE this landed, and it is the reason lag and famine are two
  # culprits. Against the real store the refusal read "the newest GREEN tree IS live HEAD; none of
  # the 11 commit(s) above it has verified" while the escalation beneath it said "no GREEN tree
  # anywhere in the newest 2000 commits". One artifact, two lines, and the FALSE one named the
  # culprit. Where the ladder's own evidence and the probe's silence disagree, the ladder wins.
  r7_setup
  stamp HEAD                                         # a green sits exactly ON the live layer…
  advance_origin b c                                 # …and nothing above it has verified
  # Past the budget AND with the degrade switch off: the operator's documented strict green-only
  # gate, which is the one configuration where this state is a refusal rather than a T2 advance
  # (the same shape tests G5 and J1 already pin).
  R7_LAGC=0 R7_DEGRADE=off
  run dlr; run dlr; run dlr
  [[ "$output" == *"class=green-at-head"* ]] || false
  [[ "$output" == *"culprit=verifier-lag"* ]] || false
  [[ "$output" != *"famine"* ]] || false
  grep -q "nothing ABOVE the live layer has verified" "$CC_BACKLOG_LOG" || false
  grep -q "the producer is alive" "$PAGES/deploy-refusal-escalation-verifier-lag.page" || false
}

@test "R7 a RED trunk is a THIRD culprit — the gate working, not a gate to fix" {
  r7_setup
  advance_origin b c
  stamp origin/main red; stamp origin/main~1 red     # every candidate above the layer is RED
  R7_LAGC=0                                          # past the budget ⇒ T2 runs, walks back, finds none
  run dlr; run dlr; run dlr
  [[ "$output" == *"culprit=trunk-red"* ]] || false
  [[ "$output" == *"class=trunk-red"* ]] || false
  grep -q "RED all the way down" "$CC_BACKLOG_LOG" || false
}

@test "R7 no stamps dir escalates as VERIFIER-INERT, and only after it has repeated" {
  r7_setup; r7_famine
  rm -rf "$BATS_TEST_TMPDIR/postland"
  run dlr; [[ "$output" != *"ESCALATED"* ]] || false
  run dlr; run dlr
  [[ "$output" == *"culprit=verifier-inert"* ]] || false
  [[ "$output" == *"class=no-stamps-dir"* ]] || false
}

@test "R7 the re-assertion is BOUNDED BOTH WAYS: damped inside the cool-off, loud again past it" {
  # Unbounded damping IS the bug being fixed, so an escalation that fired once and then went quiet
  # forever would have rebuilt it one level up. It must re-assert — and not 144x/day either.
  r7_setup; r7_famine
  run dlr; run dlr; run dlr
  [[ "$output" == *"ESCALATED"* ]] || false
  run dlr; [ -z "$output" ] || false                  # inside the cool-off: quiet
  # Age the last-escalation stamp past the window. Seeded RELATIVE to now and read back from the
  # script's own file, so this test cannot drift from the format or rot with the calendar.
  read -r c n f _ < "$R7_REF"
  printf '%s %s %s %s\n' "$c" "$n" "$f" "$(( $(date +%s) - 30000 ))" > "$R7_REF"
  run dlr
  [[ "$output" == *"ESCALATED"* ]] || false
  [[ "$output" == *"n=5"* ]] || false                 # the streak kept counting through the silence
}

@test "R7 a HEALTHY ADVANCE clears the streak — recovery then re-failure is not pre-escalated" {
  r7_setup; r7_famine
  run dlr; run dlr                                    # streak = 2, one below the threshold
  [ "$(awk '{print $2}' "$R7_REF")" -eq 2 ] || false
  stamp origin/main
  run dlr; [ "$status" -eq 0 ]                        # advances
  [ ! -f "$R7_REF" ] || false                         # cleared with the damp, in one place
  advance_origin e                                    # a NEW famine begins
  run dlr; [[ "$output" != *"ESCALATED"* ]] || false  # …at 1, not at 3
}

@test "R7 a CHANGE of culprit restarts the streak — a different machine is different news" {
  r7_setup; r7_famine
  rm -rf "$BATS_TEST_TMPDIR/postland"
  run dlr; run dlr                                    # no-stamps-dir, streak 2
  [ "$(awk '{print $1" "$2}' "$R7_REF")" = "no-stamps-dir 2" ] || false
  mkdir -p "$STAMPS"                                  # the class CHANGES to no-green
  run dlr
  [ "$(awk '{print $1" "$2}' "$R7_REF")" = "no-green 1" ] || false
  [[ "$output" != *"ESCALATED"* ]] || false           # inheriting the old count would page here
}

@test "R7 the backlog title carries NO volatile digits — one condition is one item, not one per tick" {
  # cc-backlog's event key is a hash of project+title+source, so a count or a sha in the title mints
  # a NEW blocked item every cool-off for ONE unresolved finding (5 items for 1 finding, 2026-08-05).
  r7_setup; r7_famine
  run dlr; run dlr; run dlr
  read -r c n f _ < "$R7_REF"
  printf '%s %s %s %s\n' "$c" "$n" "$f" "$(( $(date +%s) - 30000 ))" > "$R7_REF"
  run dlr
  [ "$(grep -c "deploy lane refusing on repeat" "$CC_BACKLOG_LOG")" -eq 2 ] || false
  [ "$(grep "deploy lane refusing on repeat" "$CC_BACKLOG_LOG" | sort -u | wc -l | tr -d ' ')" -eq 1 ] || false
}

@test "R7 a DECISION-ONLY call never moves the counter (--dry-run and --offline are not ticks)" {
  # The streak is a fact about the unattended lane. An operator asking for a verdict, or the platter
  # asking with --offline, must not push the machine toward a page it did not cause.
  r7_setup; r7_famine
  run dlr --dry-run; [ ! -f "$R7_REF" ] || false
  run dlr --offline; [ ! -f "$R7_REF" ] || false
  run dl;            [ ! -f "$R7_REF" ] || false      # …and neither does a non---auto run
  run dlr;           [ -f "$R7_REF" ] || false        # positive control: a real tick DOES
}

@test "R7 the escalation cannot break the lane — a hostile backlog binary changes nothing" {
  # memory: addon-failure-exceeds-its-blast-radius. A side-car that kills the deploy run is worse
  # than the silence it replaces, so the escalation is proven to fail no wider than itself.
  r7_setup; r7_famine
  printf '#!/bin/bash\nexit 9\n' > "$BLSPY"; chmod +x "$BLSPY"
  before="$(git -C "$SHARED" rev-parse HEAD)"
  run dlr; run dlr; run dlr
  [ "$status" -eq 1 ] || false                        # the refusal's own exit code, unchanged
  [[ "$output" == *"ESCALATED"* ]] || false
  [[ "$output" == *"item=none"* ]] || false           # CHECKED, not claimed: the filing did not happen
  [ "$(git -C "$SHARED" rev-parse HEAD)" = "$before" ] || false
}

# ── the anti-rollback guard, CLASSIFIED (2026-08-19) ─────────────────────────────────────────────
# "HEAD is not an ancestor of TARGET" hid two states with opposite remedies, and answered both with
# a sentence measured on only one of them. These pin the split. The live instance that motivated it:
# the shared checkout sat 29 drain recycles on ONE commit whose content was already on trunk under a
# rebased sha, and the refusal told every reader to "land or drop those commits by hand".
#
# RED-PROOF, honestly stated: SUP1/SUP3/SUP4/SUP5 fail against pre-fix deploy-live.sh, which emits
# the descendant sentence for every one of these states. SUP2 and SUP6 are GREEN PRE-FIX BY
# CONSTRUCTION — one asserts an ABSENCE of mutation, the other asserts a sentence the pre-fix script
# already emits (it is the preservation arm). They are kept because the whole value of this change
# is WHICH sentence fires, so the arm that must NOT change needs a pin too.

# The guard is only REACHABLE once the lane has stopped waiting: inside the degrade budget, a green
# tree that is not a descendant of live HEAD is an ordinary "waiting" exit 0. The fleet's real lag
# (49 commits) had long exceeded that budget; a 1-commit fixture has not. Force the trip so these
# cases pin the GUARD rather than the budget.
dl_lagged() { # [EXTRA_ENV=val ...]
  env DEPLOY_REPO="$SHARED" CC_POSTLAND_DIR="$BATS_TEST_TMPDIR/postland" CC_PAGES_DIR="$PAGES" \
      CC_DEPLOY_MAX_LAG_COMMITS=0 CC_DEPLOY_MAX_LAG_HOURS=0 "$@" /bin/bash "$DL"
}

# shared HEAD holds a commit whose CONTENT is on origin under a DIFFERENT sha — the rebased-land
# shape. Same diff, different commit message ⇒ same patch-id, different object.
# Staging is EXPLICIT, never `add -A`: setup's install.sh stub is untracked, and sweeping it into
# only the first of the two commits makes their diffs differ — which silently destroys the very
# supersession the fixture exists to create (measured while writing these).
diverge_superseded() {
  local base live; base="$(git -C "$SHARED" rev-parse HEAD)"
  echo super > "$SHARED/super.txt"; git -C "$SHARED" add super.txt
  git -C "$SHARED" commit -q -m "super (the object the live checkout keeps)"
  live="$(git -C "$SHARED" rev-parse HEAD)"
  git -C "$SHARED" reset -q --hard "$base"
  echo super > "$SHARED/super.txt"; git -C "$SHARED" add super.txt
  git -C "$SHARED" commit -q -m "super (same change, landed under a rebased sha)"
  git -C "$SHARED" push -q origin main
  git -C "$SHARED" reset -q --hard "$live"
  git -C "$SHARED" fetch -q origin
}

# shared HEAD holds a commit that exists NOWHERE else — dropping it destroys work
diverge_unlanded() {
  local base live; base="$(git -C "$SHARED" rev-parse HEAD)"
  echo mine > "$SHARED/mine.txt"; git -C "$SHARED" add mine.txt
  git -C "$SHARED" commit -q -m "mine (never landed anywhere)"
  live="$(git -C "$SHARED" rev-parse HEAD)"
  git -C "$SHARED" reset -q --hard "$base"
  echo theirs > "$SHARED/theirs.txt"; git -C "$SHARED" add theirs.txt
  git -C "$SHARED" commit -q -m "theirs"
  git -C "$SHARED" push -q origin main
  git -C "$SHARED" reset -q --hard "$live"
  git -C "$SHARED" fetch -q origin
}

# ANTI-VACUITY. A fixture that silently failed to produce the state under test would let every
# assertion below pass over a case that does not exist. Assert the STATE, never the intent.
assert_diverged() {
  run git -C "$SHARED" merge-base --is-ancestor HEAD origin/main
  [ "$status" -ne 0 ] || false                        # HEAD is NOT on trunk
  run git -C "$SHARED" merge-base --is-ancestor origin/main HEAD
  [ "$status" -ne 0 ] || false                        # ...and trunk is not on HEAD ⇒ genuinely diverged
}
assert_same_patch_id() {                              # the fixture really is a rebased land
  local a b
  a="$(git -C "$SHARED" show HEAD | git -C "$SHARED" patch-id --stable | awk '{print $1}')"
  b="$(git -C "$SHARED" show origin/main | git -C "$SHARED" patch-id --stable | awk '{print $1}')"
  [ -n "$a" ] || false
  [ "$a" = "$b" ] || false
}

@test "diverged-but-SUPERSEDED is named as already-landed and hands over the drop command (SUP1)" {
  diverge_superseded
  assert_diverged
  assert_same_patch_id
  stamp origin/main
  run dl_lagged
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"DIVERGED but ALREADY LANDED"* ]] || false
  [[ "$output" == *"present on it by CONTENT"* ]] || false
  [[ "$output" == *"reset --keep origin/main"* ]] || false
  [[ "$output" == *"1 commit(s)"* ]] || false
}

@test "diverged-but-SUPERSEDED still moves NOTHING — it only changes the sentence (SUP2)" {
  diverge_superseded
  assert_diverged
  stamp origin/main
  before="$(git -C "$SHARED" rev-parse HEAD)"
  run dl_lagged
  [ "$status" -eq 1 ] || false
  [ "$(git -C "$SHARED" rev-parse HEAD)" = "$before" ] || false
  [ ! -f "$INSTALL_LOG" ] || false                     # ...and install.sh never ran
}

@test "genuinely un-landed divergence is named as work-destroying and never offers the drop (SUP3)" {
  diverge_unlanded
  assert_diverged
  stamp origin/main
  run dl_lagged
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"DIVERGED"* ]] || false
  [[ "$output" == *"DESTROY work"* ]] || false
  [[ "$output" != *"ALREADY LANDED"* ]] || false
  [[ "$output" != *"reset --keep"* ]] || false        # the one sentence that must never appear here
}

@test "a MERGE commit in the diverging set fails CLOSED to the work-destroying wording (SUP4)" {
  # A merge has no single patch-id, so supersession is not adjudicable over it. Fail-closed means
  # the safe-to-drop sentence is WITHHELD, not that the merge is skipped.
  local live
  git -C "$SHARED" checkout -q -b side
  echo s > "$SHARED/s.txt"; git -C "$SHARED" add s.txt; git -C "$SHARED" commit -q -m side
  git -C "$SHARED" checkout -q main
  echo m > "$SHARED/m.txt"; git -C "$SHARED" add m.txt; git -C "$SHARED" commit -q -m mainline
  git -C "$SHARED" merge -q --no-ff -m "merge side" side
  live="$(git -C "$SHARED" rev-parse HEAD)"
  git -C "$SHARED" reset -q --hard origin/main
  echo t > "$SHARED/t.txt"; git -C "$SHARED" add t.txt; git -C "$SHARED" commit -q -m theirs
  git -C "$SHARED" push -q origin main
  git -C "$SHARED" reset -q --hard "$live"
  git -C "$SHARED" fetch -q origin
  assert_diverged
  stamp origin/main
  run dl_lagged
  [ "$status" -eq 1 ] || false
  [[ "$output" != *"ALREADY LANDED"* ]] || false
  [[ "$output" == *"DESTROY work"* ]] || false
}

@test "the scan bound fails CLOSED — an over-budget ahead-set never reads as safe to drop (SUP5)" {
  diverge_superseded
  assert_diverged
  assert_same_patch_id                                 # the state IS superseded; only the bound refuses
  stamp origin/main
  run dl_lagged CC_DEPLOY_SUPERSEDE_SCAN=0
  [ "$status" -eq 1 ] || false
  [[ "$output" != *"ALREADY LANDED"* ]] || false
  [[ "$output" == *"DESTROY work"* ]] || false
}

@test "case A's original sentence survives the classification, pinned in SOURCE (SUP6)" {
  # HONEST LABEL: this is a SOURCE pin, not a behavioural one, because case A (TARGET an ancestor of
  # live HEAD) is NOT REACHABLE through the lane's own target selection. Two constructions were
  # measured 2026-08-19 and the lane diverted before the guard in both:
  #   · green behind live HEAD, trunk ahead   → the DEGRADE arm re-targets FORWARD to the newest
  #                                             not-red commit, which is a descendant, so the guard
  #                                             never sees a behind-HEAD target
  #   · live linearly ahead of trunk          → "at trunk tip — nothing above the live layer", exit 0
  # That matches the guard's own provenance: its 2026-08-07 measurement was taken in a throwaway
  # repo, not through this lane. So the arm is defensive, and the only thing that can regress is the
  # sentence being moved out from under its test — which is exactly what this pins.
  local a b
  a="$(grep -n 'is-ancestor "\$TARGET" "\$HEAD_SHA"' "$DL" | head -1 | cut -d: -f1)"
  b="$(grep -n 'NEVER HAPPENED' "$DL" | head -1 | cut -d: -f1)"
  # Assert both ENDPOINTS exist before anything arithmetic runs on them: a stale anchor that matched
  # nothing would otherwise compare empty to empty and read as a clean pass.
  [ -n "$a" ] || false
  [ -n "$b" ] || false
  [ "$b" -gt "$a" ] || false                           # the sentence is INSIDE the case-A arm...
  [ "$((b - a))" -le 3 ] || false                      # ...immediately, not merely somewhere below
}

@test "the divergence refusal PAGES, so a frozen live layer stops being a silence (SUP7)" {
  # The half that let this run 29 recycles undetected: the guard `die`d bare — no refusal_bump, no
  # page — so it was a standing state generating no event. permission-gate-lint's 545-refusal scar
  # is the same shape. The page is the event.
  diverge_superseded
  assert_diverged
  stamp origin/main
  run dl_lagged
  [ "$status" -eq 1 ] || false
  [ -f "$PAGES/deploy-diverged-superseded.page" ] || false
  run grep -cF 'reset --keep origin/main' "$PAGES/deploy-diverged-superseded.page"
  [ "$output" -ge 1 ] || false                        # the page carries the remedy, not just the fact
  run grep -cF 'FROZEN' "$PAGES/deploy-diverged-superseded.page"
  [ "$output" -ge 1 ] || false                        # ...and says what the freeze costs
}

# ── ORPHAN prune: the live link whose repo source was DELETED (backlog 456d5c61f4c8) ─────────────
# The mirror of link_refresh. The assert gained a reverse sweep because its forward walk iterates
# the TRACKED listing and a deleted file has left that listing — so its live symlink survives,
# resolving for `command -v` and failing with ENOENT at exec, seen by nobody. Two were live on the
# operator's host when this landed (bin/cc-cloud-watch, bin/browsermcp-wrapper.sh).
#
# THIS CONSUMER DELETES, so it does not trust the verdict it is given. Every case below fixes the
# assert's output and varies only what is actually on disk: the actuator re-derives the dangling
# predicate itself, and the three controls are what prove a wrong or stale verdict cannot destroy
# anything (memory: make-the-actuator-the-arbiter). Nothing here can remove a path that resolves.
orphan() { # <live-relative> — a DANGLING link into the fixture repo; returns its path via $ODEST
  ODEST="$LIVE/$1"
  mkdir -p "${ODEST%/*}"
  ln -sfn "$SHARED/$1" "$ODEST"                    # $SHARED/$1 deliberately never created
  printf 'ORPHAN: rm -f %s\n' "$ODEST" >> "$PARITY_OUT"
}

@test "ORPHAN: a dangling live link into the checkout is PRUNED (RED-PROOF)" {
  seed_parity 1
  orphan hooks/cc-deleted.sh
  [ -L "$ODEST" ]                                  # present before...
  [ ! -e "$ODEST" ]                                # ...and already inert, which is what makes it safe
  stamp HEAD
  run dlp
  [ "$status" -eq 0 ]
  [ ! -L "$ODEST" ]                                # gone
  echo "$output" | grep -q "orphan-prune: 1 dead live link"
}

@test "ORPHAN control: a verdict naming a HEALTHY link deletes NOTHING — the actuator re-derives" {
  seed_parity 1
  mkdir -p "$LIVE/hooks"
  echo payload > "$SHARED/hooks/alive.sh"
  ln -sfn "$SHARED/hooks/alive.sh" "$LIVE/hooks/alive.sh"
  # A stale or simply wrong verdict: the link resolves, so the prune must refuse it on its own
  # evidence rather than on the assert's say-so. This is the case the row feared and the reason the
  # predicate is "is it dangling", never "is it tracked".
  printf 'ORPHAN: rm -f %s\n' "$LIVE/hooks/alive.sh" >> "$PARITY_OUT"
  stamp HEAD
  run dlp
  [ "$status" -eq 0 ]
  [ -L "$LIVE/hooks/alive.sh" ]                    # untouched
  [ -e "$LIVE/hooks/alive.sh" ]                    # and still resolving
  [[ "$output" != *"orphan-prune"* ]]
}

@test "ORPHAN control: a verdict naming a REAL FILE deletes NOTHING — only symlinks are ever claimed" {
  seed_parity 1
  mkdir -p "$LIVE/hooks"
  echo "hand-written, in no checkout" > "$LIVE/hooks/real.sh"
  printf 'ORPHAN: rm -f %s\n' "$LIVE/hooks/real.sh" >> "$PARITY_OUT"
  stamp HEAD
  run dlp
  [ "$status" -eq 0 ]
  [ -f "$LIVE/hooks/real.sh" ]                     # an unversioned real file is STRAY's problem
  [[ "$output" != *"orphan-prune"* ]]
}

@test "ORPHAN control: --dry-run previews the prune and removes NOTHING" {
  seed_parity 1
  orphan hooks/cc-deleted.sh
  stamp HEAD
  run dlp --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "would prune"
  echo "$output" | grep -q "WOULD BE pruned"
  [ -L "$ODEST" ]                                  # still there
}

@test "ORPHAN control: the prune and the refresh are disjoint — one tick does both, neither flaps" {
  seed_parity 1
  miss hooks/brand-new.sh                          # a genuine gap the refresh must still repair
  orphan hooks/cc-deleted.sh                       # and a dead link the prune must remove
  stamp HEAD
  run dlp
  [ "$status" -eq 0 ]
  [ -L "$DEST" ]                                   # created
  [ ! -L "$ODEST" ]                                # removed
  echo "$output" | grep -q "link-refresh: 1 live link"
  echo "$output" | grep -q "orphan-prune: 1 dead live link"
}

@test "ORPHAN control: no ORPHAN line ⇒ the prune narrates nothing (the 144×/day silence contract)" {
  seed_parity 1
  miss hooks/only-a-miss.sh
  stamp HEAD
  run dlp
  [ "$status" -eq 0 ]
  [[ "$output" != *"orphan-prune"* ]] || false          # `|| false`: a mid-test [[ ]] is dead otherwise
  [[ "$output" != *"would prune"* ]]
}
