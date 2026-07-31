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

@test "refuses to roll back: newest green is BEHIND the live HEAD" {
  stamp HEAD                                    # the commit that is already live
  commit_push b; git -C "$SHARED" push -q origin main   # HEAD and origin both move past it
  before="$(git -C "$SHARED" rev-parse HEAD)"
  run dl
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "ROLL BACK"
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

@test "refresh runs on the ROLLBACK REFUSAL — the exit that made it dead code (2026-07-30)" {
  seed_parity 1
  miss hooks/brand-new.sh
  stamp HEAD                                     # the newest green is the commit already live...
  commit_push b; git -C "$SHARED" push -q origin main   # ...and both HEAD and origin move past it
  run dlp
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "ROLL BACK"           # the refusal is UNCHANGED — still fail-closed
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

@test "the real assert emits the MISSING contract this refresh parses (the stub is not the spec)" {
  # Guards the seam between the two files: if deploy-parity-assert.sh ever renames the prefix or
  # reorders the fields, every test above keeps passing against the stub while production goes inert.
  run grep -n "MISSING: ln -sf %s %s" "$REPO/scripts/deploy-parity-assert.sh"
  [ "$status" -eq 0 ]
  run grep -n "MISSING: ln -sf " "$REPO/scripts/deploy-live.sh"
  [ "$status" -eq 0 ]
}
