#!/usr/bin/env bats
# deploy-live.sh residency_report() — "did the live layer reach the RUNNING PROCESSES?"
# (master 475222a572de half 1: prove convergence by reading the running image, not the symlink.)
#
# FULLY HERMETIC. Every case drives the real scripts/deploy-live.sh against a fixture DEPLOY_REPO
# under BATS_TEST_TMPDIR carrying its own launchd/*.plist and its own scripts/lib/cc-common.sh, with
# `launchctl` and `ps` PATH-stubbed. HOME is redirected. No real daemon, checkout or launchd domain
# is read. /usr/libexec/PlistBuddy IS invoked for real (cc-common calls it by absolute path, so it
# cannot be PATH-shadowed) — that stays hermetic because it only ever READS the fixture plist.
#
# RED-PROOF PINNED TO A SHA, NOT origin/main: the pre-fix control is 0889cdb9f (recycle #56's tip,
# the last commit before residency_report existed). Pinning to a moving ref would silently stop
# testing anything the moment the fix lands, and a control that skips reads exactly like one that
# passes. A/B rig: `git worktree add --detach <tmp> 0889cdb9f`, copy ONLY this file into its tests/,
# run there — $REPO resolves from the test file's own dir, so the SUBJECT stays pre-fix.
#
# PREDICTED PRE-FIX SPLIT (recorded before the run, per the predict-then-run rule):
#   RED   — 1, 2, 3, 5, 6, 7   (they assert a residency line that does not exist pre-fix)
#   GREEN — 4, 8               (green PRE-FIX BY CONSTRUCTION, and that is stated, not hidden:
#                               4 asserts an ABSENCE and 8 asserts a PRESERVATION, so neither can
#                               fail against a build that emits no residency line at all. They are
#                               here to pin regressions of the fix, not to demonstrate the defect.)
#
# EVERY CASE CAPTURES `out="$output"` IMMEDIATELY after `run dl`. `run` overwrites $output, so a
# second `run grep … <<<"$output"` would grep the FIRST grep's COUNT — a vacuous pass that reads
# exactly like a real one. The helper asserts below all use `run`, so this is not optional.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  DL="$REPO/scripts/deploy-live.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"      # hermetic: never touch the live ~/
  ORIGIN="$BATS_TEST_TMPDIR/origin.git"
  SHARED="$BATS_TEST_TMPDIR/shared"
  STUB="$BATS_TEST_TMPDIR/stub"; mkdir -p "$STUB"
  PSLOG="$BATS_TEST_TMPDIR/ps.calls"; LCLOG="$BATS_TEST_TMPDIR/launchctl.calls"
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@x GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@x
  git init -q --bare "$ORIGIN"
  git init -q "$SHARED"; git -C "$SHARED" remote add origin "$ORIGIN"
  echo a > "$SHARED/a.txt"; git -C "$SHARED" add -A; git -C "$SHARED" commit -q -m a
  git -C "$SHARED" branch -M main 2>/dev/null || true
  git -C "$SHARED" push -q -u origin main
  mkdir -p "$SHARED/scripts/lib" "$SHARED/launchd"
  cp "$REPO/scripts/lib/cc-common.sh" "$SHARED/scripts/lib/cc-common.sh"
  mk_stubs
}

# ── the fixture's OWN anti-vacuity guard ────────────────────────────────────────────────────────
# Without this, every behavioural case below would pass against a fixture whose cc-common carries no
# probes at all — the run would take the NO VERDICT arm and the assertions would never enter the
# branch under test. Refuse to assert until the probes are present.
assert_probes_present() {
  local p
  for p in plist_is_resident resident_pid resident_program resident_image_stale; do
    run grep -cF "$p() {" "$SHARED/scripts/lib/cc-common.sh"
    [ "${output:-0}" -ge 1 ] || false
  done
}

# Prove the stubs were actually CONSULTED. A case concluding "no resident daemon is executing" is
# otherwise indistinguishable from one where launchctl was never called at all.
assert_launchctl_hit() { run grep -cF list "$LCLOG"; [ "${output:-0}" -ge 1 ] || false; }
assert_ps_hit()        { run grep -cF -- -p "$PSLOG"; [ "${output:-0}" -ge 1 ] || false; }

# count <needle> <haystack> — one grep, count-form only. `grep -q` under pipefail can return 141 on
# the very input it matched, and `grep -c` prints 0 and EXITS 1, which is a live assertion under
# errexit. `run` + $output is the only shape that is safe in both directions here.
cnt() { run grep -cF -- "$1" <<<"$2"; printf '%s' "${output:-0}"; }

mk_stubs() {
  # launchctl: `list <label>` prints a plist-ish block carrying a PID for KNOWN labels only, and
  # exits 1 for anything else — which is what resident_pid reads as "not executing".
  cat > "$STUB/launchctl" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >> "$LCLOG"
if [ "${1:-}" = list ] && [ -n "${2:-}" ]; then
  case "$2" in
    com.claude.fixture-stale)   echo '	"PID" = 4242;' ;;
    com.claude.fixture-current) echo '	"PID" = 4343;' ;;
    com.claude.fixture-exempt)  echo '	"PID" = 4444;' ;;
    *) exit 1 ;;
  esac
  exit 0
fi
exit 1
SH
  # ps: faithful where fidelity is what makes a case creditable — it exits 1 for an unknown pid
  # exactly as the real ps does, so the subject's error handling can actually be mutated red.
  # lstart is emitted in the C-locale/UTC rendering resident_image_stale pins (`%a %b %e %T %Y`).
  #
  # 4242/4343 emit `/bin/bash <prog> --daemon`: BOTH /bin/bash and <prog> are real files, and
  # resident_program keeps the LAST such token — which is exactly the property that makes it read
  # the script rather than its interpreter. 4444 emits a BARE command name resolving to no file at
  # all, which is the real com.claude.caffeinate-floor shape (measured 2026-08-19: prog='').
  cat > "$STUB/ps" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >> "$PSLOG"
pid=""; want=""
while [ $# -gt 0 ]; do
  case "$1" in
    -p) pid="$2"; shift 2 ;;
    -o) want="$2"; shift 2 ;;
    *)  shift ;;
  esac
done
case "$pid" in
  4242) argv="/bin/bash $FX_STALE --daemon" ;;
  4343) argv="/bin/bash $FX_CURRENT --daemon" ;;
  4444) argv="caffeinate -dimsu" ;;
  *) exit 1 ;;
esac
case "$want" in
  command=) echo "$argv" ;;
  lstart=)  echo "Mon Aug 17 00:00:00 2026" ;;
  *) exit 1 ;;
esac
exit 0
SH
  chmod +x "$STUB/launchctl" "$STUB/ps"
}

mk_plist() { # <label> — a REAL plist with a boolean KeepAlive, read by the real PlistBuddy
  cat > "$SHARED/launchd/$1.plist" <<XML
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$1</string>
  <key>KeepAlive</key><true/>
</dict></plist>
XML
}

mk_prog() { # <path> <touch-stamp> — the image a fixture daemon is "executing"
  printf '#!/bin/bash\n:\n' > "$1"; chmod +x "$1"; touch -t "$2" "$1"
}

dl() { # drive the real subject against the fixture, with the stubs first on PATH
  env DEPLOY_REPO="$SHARED" \
      CC_POSTLAND_DIR="$BATS_TEST_TMPDIR/postland" CC_PAGES_DIR="$BATS_TEST_TMPDIR/pages" \
      CC_DEPLOY_LAUNCHCTL_BIN="$STUB/launchctl" \
      FX_STALE="$BATS_TEST_TMPDIR/stale-prog.sh" FX_CURRENT="$BATS_TEST_TMPDIR/current-prog.sh" \
      PSLOG="$PSLOG" LCLOG="$LCLOG" PATH="$STUB:$PATH" \
      /bin/bash "$DL" --dry-run --offline 2>&1
}

@test "1 a resident daemon executing an image NEWER than its start is reported STALE" {
  assert_probes_present
  mk_plist com.claude.fixture-stale
  mk_prog "$BATS_TEST_TMPDIR/stale-prog.sh" 202608200000     # 3 days AFTER the stubbed lstart
  run dl; local out="$output"
  assert_launchctl_hit; assert_ps_hit
  [ "$(cnt 'residency: 1 of 1 executing resident daemon(s) are running STALE bytes' "$out")" -eq 1 ] || false
}

@test "2 a resident daemon executing an image OLDER than its start is reported CURRENT" {
  assert_probes_present
  mk_plist com.claude.fixture-current
  mk_prog "$BATS_TEST_TMPDIR/current-prog.sh" 202608100000    # 7 days BEFORE the stubbed lstart
  run dl; local out="$output"
  assert_launchctl_hit; assert_ps_hit
  [ "$(cnt 'residency: 1 of 1 executing resident daemon(s) are running current bytes' "$out")" -eq 1 ] || false
}

@test "3 a resident daemon whose argv names no file on disk is counted EXEMPT, never fresh" {
  assert_probes_present
  mk_plist com.claude.fixture-exempt
  run dl; local out="$output"
  assert_ps_hit
  # The denominator is never silent: exempt is REPORTED, not dropped. And it must not be laundered
  # into the fresh count — `0 of 0 … current bytes` would be a freshness claim about nothing.
  [ "$(cnt '1 exempt (argv names no file on disk)' "$out")" -eq 1 ] || false
  [ "$(cnt 'residency: no resident daemon is executing' "$out")" -eq 1 ] || false
  [ "$(cnt 'current bytes' "$out")" -eq 0 ] || false
}

@test "4 an empty launchd population emits NO residency line at all" {
  # GREEN PRE-FIX BY CONSTRUCTION (absence assertion). Pins the ordering that keeps this change
  # inert in every existing fixture repo: population is tested BEFORE the probe lib, so a repo with
  # no launchd/ has no subject and stays silent rather than emitting a NO VERDICT into every suite.
  run dl; local out="$output"
  [ "$(cnt 'residency:' "$out")" -eq 0 ] || false
}

@test "5 plists present but the probe lib ABSENT is a NO VERDICT, not a freshness claim" {
  mk_plist com.claude.fixture-stale
  rm -f "$SHARED/scripts/lib/cc-common.sh"
  run dl; local out="$output"
  [ "$(cnt 'residency: NO VERDICT' "$out")" -eq 1 ] || false
  [ "$(cnt 'current bytes' "$out")" -eq 0 ] || false
}

@test "6 a cc-common that PREDATES the probes is a NO VERDICT, not 'no resident daemon is executing'" {
  # THE REGRESSION THIS CASE EXISTS FOR, found by running the fix against the real shared checkout
  # on 2026-08-19: that checkout is frozen below b2763f882, so the lib was present and readable but
  # carried none of the probes. `-r` passed, the source succeeded, and the loop emitted 26 lines of
  # `plist_is_resident: command not found` before concluding "no resident daemon is executing" — a
  # confident measurement manufactured out of a non-verdict, on a host where two daemons WERE stale.
  mk_plist com.claude.fixture-stale
  printf '#!/usr/bin/env bash\nresolve_bin() { :; }\n' > "$SHARED/scripts/lib/cc-common.sh"
  run dl; local out="$output"
  [ "$(cnt 'residency: NO VERDICT' "$out")" -eq 1 ] || false
  [ "$(cnt 'command not found' "$out")" -eq 0 ] || false
  [ "$(cnt 'no resident daemon is executing' "$out")" -eq 0 ] || false
}

@test "7 the report runs UNCONDITIONALLY, ahead of the early exits that claim convergence" {
  # install.sh runs only on the advance path, so the 144-ticks/day steady state is exactly where the
  # question is never asked. This pins that residency_report is not nested under the advance.
  assert_probes_present
  mk_plist com.claude.fixture-stale
  mk_prog "$BATS_TEST_TMPDIR/stale-prog.sh" 202608200000
  run dl; local out="$output"
  [ "$(cnt 'STALE bytes' "$out")" -eq 1 ] || false      # emitted though nothing was deployed
}

@test "8 a residency line never becomes the LAST line of a refusal (cc-do / operator-readout read tail -1)" {
  # GREEN PRE-FIX BY CONSTRUCTION (preservation assertion). bin/cc-do:147 and
  # hooks/operator-readout.sh:359 both take `tail -1` of the COMBINED stream as the refusal reason.
  # residency_report prints at the same point migrations_converge already does, so the ordering is
  # inherited rather than new — this case is what stops a later edit from moving it below `die`.
  assert_probes_present
  mk_plist com.claude.fixture-stale
  mk_prog "$BATS_TEST_TMPDIR/stale-prog.sh" 202608200000
  run dl; local out="$output"
  local last; last="$(printf '%s\n' "$out" | tail -1)"
  case "$last" in *residency:*) false ;; esac
}
