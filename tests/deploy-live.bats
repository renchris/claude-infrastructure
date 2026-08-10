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
@test "WITHIN BUDGET: newest green is BEHIND the live HEAD ⇒ still refuses, tree unmoved" {
  deadlock                                      # green behind live HEAD; trunk 2 ahead
  before="$(git -C "$SHARED" rev-parse HEAD)"
  run dl                                        # default budget 25 commits / 6h — 2 commits is inside it
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "DESCENDANT of live HEAD"
  [ "$(git -C "$SHARED" rev-parse HEAD)" = "$before" ]
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
      bash "$NIGHTLY"
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
  SPY="$BATS_TEST_TMPDIR/bats-spy"; BLSPY="$BATS_TEST_TMPDIR/backlog-spy"
  cat > "$SPY" <<'SPY'
#!/bin/bash
printf '%s\n' "$1" >> "$CC_SPY_LOG"
case "$1" in
  *host-red*) printf 'not ok 1 - boom\nnot ok 2 - boom2\n'; exit 1 ;;
  *host-cut*) exit 124 ;;                 # OUR bound firing: non-zero naming ZERO tests
  # A suite that PASSES while unprefixed stderr splices into its stream: rc 0, one real `ok`, and
  # four C30 shapes that merely OPEN with `not ok`. The worst case for a loose grammar — a green
  # live layer paged and backlogged as RED.
  *host-torn*) printf 'not ok\nnot ok3 squashed\nnot okay then\nnot okcorpus: 3 suites\n'
               printf 'ok 1 - fine\n'; exit 0 ;;
  # …and the control: the same splice around ONE genuine verdict, which must still page.
  *host-tsplice*) printf 'not okay then\nnot ok 1 - boom\nnot okcorpus: 3 suites\n'; exit 1 ;;
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
  printf '#!/usr/bin/env bats\n@test "x" { true; }\n' > "$SHARED/tests/host-torn.bats"
  printf '#!/usr/bin/env bats\n@test "x" { false; }\n' > "$SHARED/tests/host-tsplice.bats"
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

@test "refresh runs on the GREEN-BEHIND REFUSAL — the exit that made it dead code (2026-07-30)" {
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
  advance_origin c                               # trunk moves again; the layer stays ⇒ lag 1
  run dlp
  [ "$status" -eq 1 ]
  # The refusal is unchanged in POLARITY — still fail-closed — but no longer claims a rollback:
  # the target is an ancestor, so `--ff-only` would exit 0 without moving anything (§1.7). Lag is 1
  # commit, far inside the 25-commit budget, so T2 cannot authorise a degrade and this is a refusal.
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
