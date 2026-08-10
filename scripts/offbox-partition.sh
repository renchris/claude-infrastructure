#!/bin/bash
# offbox-partition.sh — the HERMETIC PARTITION of the bats corpus, and the only place it is computed.
#
#   offbox-partition.sh list                 the partition, one `tests/<name>.bats` per line
#   offbox-partition.sh excluded             the suites deliberately kept OUT, one per line
#   offbox-partition.sh shard <i> <n>        shard i (1-based) of n, deterministic and balanced
#   offbox-partition.sh lint                 anti-rot guard. exit 0 clean / 1 + the finding
#   offbox-partition.sh --selftest           RED-proves every law below. exit 1 on any failure
#
# WHY THIS FILE EXISTS. `docs/plans/DEPLOY_LANE_GROUND_UP.md:808` states the constraint that
# blocked its own follow-on for a day: *"that item's premise — 'a green producer the design lacks'
# — requires a hermetic partition that does not exist yet, so the partition is the PREREQUISITE,
# not the CI."* `scripts/host-suites.manifest` partitions on HOST-COUPLING (3 files, the suites that
# assert the DEPLOYED layer). That is a different question from *can this suite prove anything on a
# machine that is not this one*, and answering the second with the first is what made the trigger
# unbuildable. This file answers the second, and `.github/workflows/hermetic.yml` consumes it.
#
# ── THE PARTITION IS A SET DIFFERENCE, AND THAT IS THE WHOLE DESIGN ──────────────────────────────
#
#     partition = tests/*.bats  MINUS  scripts/host-suites.manifest  MINUS  scripts/offbox-excluded.manifest
#
# Copied deliberately from `host-suites.manifest`'s frozen contract, for its stated reason: *"The
# partition is a SET DIFFERENCE, so it is total by construction and never hand-synced."* An
# INCLUSION list would have the opposite failure — a new hermetic suite is simply absent from it, the
# off-box corpus silently narrows, and nothing names the loss. Here a new suite lands INSIDE the
# partition by default and must EARN its way out with a line and a reason.
#
# THE COST OF THAT DIRECTION, STATED RATHER THAN HIDDEN: a genuinely machine-coupled new suite reds
# the off-box run on the land that adds it. That is the intended bill. It is one attributable red
# naming one file, curable by one line here — against the alternative, which is a producer whose
# coverage decays invisibly. And the red is never a landing block: `hermetic.yml` produces a GREEN
# or it produces nothing, it does not gate `/ship` (see § WHAT A RED HERE COSTS).
#
# ── FAIL-CLOSED DIRECTION: TOWARD MORE PROOF, WHICH HERE MEANS A BIGGER PARTITION ────────────────
# Any doubt — a missing manifest, an unreadable one, a `tests/` that will not list — resolves to
# running MORE suites, never fewer, and a partition that cannot be computed at all is an ERROR, never
# an empty set. The reason is specific to a green PRODUCER and inverts the usual reflex: an empty
# partition is VACUOUSLY GREEN, so "narrow on doubt" would make every failure of this script mint the
# strongest possible verdict from zero evidence. `host-suites.manifest` states the same law for the
# same reason (*"A missing manifest means EMPTY: the verifier then runs everything — fail-closed
# toward MORE proof, never less"*), and `NON-DEGENERACY` below is what enforces it as a check rather
# than as an intention.
#
# ── WHAT A RED HERE COSTS, AND WHAT IT DOES NOT ──────────────────────────────────────────────────
# This partition feeds a SECOND OPINION, not the verdict. `scripts/postland-verify.sh` remains the
# sole owner of the full-suite claim. An off-box red produces NO off-box green for that tree; it does
# not block a land, does not revert anything, and does not write a `red` anywhere the deploy lane
# reads. That asymmetry is deliberate: a subset that cannot see the machine-coupled failures has no
# standing to CONVICT a tree, only to acquit the part it actually ran.
set -uo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
ROOT="${CC_OFFBOX_ROOT:-$(cd "$(dirname "$SELF")/.." && pwd)}"

# THREE STATES, NOT TWO, on every manifest seam — `${VAR+set}` and never `${VAR:-default}`.
# `scripts/postland-verify.sh:1121-1124` uses exactly this form for the same variable class, under
# the same reasoning `scripts/test-hermeticity-lint.sh:1280` states outright: *"THREE states, not
# two — and `${VAR:-}` cannot express them, which is the bug this comment exists to prevent
# recurring."* UNSET means "use the shipped manifest"; SET-BUT-EMPTY means "there is no manifest,
# exclude nothing" — a real position a test needs to take, and one `:-` silently converts back into
# the default, so the suite would end up asserting against the shipped list while believing it had
# disabled it.
HOST_MANIFEST="${CC_HOST_MANIFEST+x}"
if [ -n "$HOST_MANIFEST" ]; then HOST_MANIFEST="$CC_HOST_MANIFEST"; else HOST_MANIFEST="$ROOT/scripts/host-suites.manifest"; fi
EXCL_MANIFEST="${CC_OFFBOX_EXCLUDED+x}"
if [ -n "$EXCL_MANIFEST" ]; then EXCL_MANIFEST="$CC_OFFBOX_EXCLUDED"; else EXCL_MANIFEST="$ROOT/scripts/offbox-excluded.manifest"; fi
TESTS_DIR="${CC_OFFBOX_TESTS_DIR:-$ROOT/tests}"

die() { printf 'offbox-partition: %s\n' "$1" >&2; exit "${2:-1}"; }

usage() { sed -n '2,/^set -uo/p' "$SELF" | sed 's/^# \{0,1\}//; /^set -uo/d'; }

# Parse a manifest into bare `tests/x.bats` lines. Comments and blanks ignored, per the frozen
# format contract in host-suites.manifest. An ABSENT manifest is EMPTY (⇒ a wider partition ⇒ more
# proof); an UNREADABLE one is the same, because the two are indistinguishable to a reader and the
# safe reading is the wider one.
manifest_lines() {
  local f="$1"
  [ -r "$f" ] || return 0
  sed 's/#.*//' "$f" | tr -d '\r' | awk 'NF { gsub(/^[ \t]+|[ \t]+$/,""); if ($0 != "") print }'
}

all_suites() {
  [ -d "$TESTS_DIR" ] || die "tests dir not found: $TESTS_DIR" 2
  local f n
  for f in "$TESTS_DIR"/*.bats; do
    [ -e "$f" ] || continue
    n="$(basename "$f")"
    printf 'tests/%s\n' "$n"
  done | LC_ALL=C sort
}

excluded_set() {
  { manifest_lines "$HOST_MANIFEST"; manifest_lines "$EXCL_MANIFEST"; } | LC_ALL=C sort -u
}

partition() {
  local all excl
  all="$(all_suites)"   || return 1
  excl="$(excluded_set)"
  # comm needs both sides sorted with the same collation; LC_ALL=C is set on both producers.
  LC_ALL=C comm -23 <(printf '%s\n' "$all") <(printf '%s\n' "$excl")
}

# NON-DEGENERACY. A partition of zero suites passes every test it runs, so the one verdict this
# script must never allow is a silent empty set. This is NOT a calibrated floor — a constant like
# `>= 200` is exactly the trap scripts/test-hermeticity-lint.sh documents under its own `seen < 20`
# correction, where a threshold tuned to one tree turned every smaller tree into a non-verdict. The
# assertion is structural instead: the partition is non-empty whenever `tests/` is non-empty.
assert_non_degenerate() {
  local nall="$1" npart="$2"
  [ "$nall" -gt 0 ] || die "tests/ holds no *.bats — refusing to call that a partition" 2
  [ "$npart" -gt 0 ] || die "partition is EMPTY while tests/ holds $nall suites — an empty partition is vacuously green, which is the one verdict this must never mint" 2
}

cmd_list() {
  local all part
  all="$(all_suites)" || exit 2
  part="$(partition)"
  assert_non_degenerate "$(printf '%s\n' "$all" | grep -c .)" "$(printf '%s\n' "$part" | grep -c .)"
  printf '%s\n' "$part"
}

cmd_excluded() { excluded_set; }

# SHARDING. Round-robin over the sorted partition, so shard membership is a pure function of the
# suite list and the shard count — no run-to-run drift, and a suite's shard is reproducible from the
# tree alone when reading a failure. Round-robin rather than contiguous blocks because the corpus is
# sorted by NAME, and this repo's names cluster by subsystem (every `handoff-*` adjacent): contiguous
# blocks would put all the slow siblings in one shard.
cmd_shard() {
  local i="${1:-}" n="${2:-}"
  case "$i" in ''|*[!0-9]*) die "shard: index must be a positive integer" 2 ;; esac
  case "$n" in ''|*[!0-9]*) die "shard: count must be a positive integer" 2 ;; esac
  [ "$n" -ge 1 ] || die "shard: count must be >= 1" 2
  [ "$i" -ge 1 ] && [ "$i" -le "$n" ] || die "shard: index $i out of range 1..$n" 2
  cmd_list | awk -v i="$i" -v n="$n" 'NR % n == (i % n)'
}

# LINT — the anti-rot guard, and the half that makes this a RATCHET rather than an exemption list.
#
# UPWARD (an entry that no longer names a real suite) and DOWNWARD (an entry that duplicates
# host-suites.manifest, i.e. buys an exemption it was already granted) are both findings. The
# downward half exists because of a measured incident in this tree: a correctly-placed `gate_bounded:`
# marker still exempted a SIBLING gate, and only the ratchet's downward half saw it — the failure of
# a list like this is never "wrongly placed", it is "correctly placed, wrongly broad".
cmd_lint() {
  local rc=0 line n_excl=0 n_host=0
  local host_set; host_set="$(manifest_lines "$HOST_MANIFEST")"

  while IFS= read -r line; do
    [ -n "$line" ] || continue
    n_excl=$((n_excl + 1))

    case "$line" in
      tests/*.bats) ;;
      *) printf 'offbox-partition lint: NOT a tests/<name>.bats path: %s\n' "$line" >&2; rc=1; continue ;;
    esac

    if [ ! -e "$ROOT/$line" ]; then
      printf 'offbox-partition lint: STALE — excluded suite does not exist: %s\n' "$line" >&2
      rc=1
    fi

    if printf '%s\n' "$host_set" | grep -qxF -- "$line"; then
      printf 'offbox-partition lint: REDUNDANT — %s is already in host-suites.manifest; this line buys nothing and hides a second exemption\n' "$line" >&2
      rc=1
    fi
  done <<EOF
$(manifest_lines "$EXCL_MANIFEST")
EOF

  n_host="$(printf '%s\n' "$host_set" | grep -c . || true)"

  # TOTALITY: every suite in tests/ lands in exactly one of {partition, excluded}. This is what makes
  # the set difference honest — it cannot silently drop a suite that is in neither.
  local nall npart nexcl_eff
  nall="$(all_suites | grep -c . || true)"
  npart="$(partition | grep -c . || true)"
  nexcl_eff="$(LC_ALL=C comm -12 <(all_suites) <(excluded_set) | grep -c . || true)"
  if [ "$((npart + nexcl_eff))" -ne "$nall" ]; then
    printf 'offbox-partition lint: NOT TOTAL — %s suites, %s in partition, %s excluded-and-present (sum %s)\n' \
      "$nall" "$npart" "$nexcl_eff" "$((npart + nexcl_eff))" >&2
    rc=1
  fi

  if [ "$rc" -eq 0 ]; then
    printf 'offbox-partition lint: clean — %s suites = %s partition + %s excluded (%s host, %s off-box)\n' \
      "$nall" "$npart" "$nexcl_eff" "$n_host" "$n_excl"
  fi
  return "$rc"
}

# ── SELFTEST ─────────────────────────────────────────────────────────────────────────────────────
# Every law above gets a POSITIVE CONTROL — a fixture that makes the law false and must therefore
# turn the check RED. A selftest whose controls cannot fail proves nothing, which is the vacuous `ok`
# this repo has paid for more than once.
st_fail=0
st() { # st <name> <expected-rc> <cmd...>
  local name="$1" want="$2"; shift 2
  local out rc
  out="$("$@" 2>&1)"; rc=$?
  if [ "$rc" -eq "$want" ]; then
    printf 'ok   %s (rc=%s)\n' "$name" "$rc"
  else
    printf 'FAIL %s — wanted rc=%s got rc=%s\n%s\n' "$name" "$want" "$rc" "$out" >&2
    st_fail=1
  fi
}

cmd_selftest() {
  # NOT `local` — an EXIT trap runs after the function's frame is gone, so a local would expand to
  # nothing (or trip `set -u`) exactly when the cleanup is due.
  ST_TMP="$(mktemp -d)" || die "selftest: mktemp failed" 1
  trap 'rm -rf "${ST_TMP:-}"' EXIT
  local tmp="$ST_TMP"

  mkdir -p "$tmp/tests" "$tmp/scripts"
  local i
  for i in a b c d e; do printf '@test "%s" { true; }\n' "$i" > "$tmp/tests/$i.bats"; done
  : > "$tmp/scripts/host-suites.manifest"
  : > "$tmp/scripts/offbox-excluded.manifest"

  run_fx() { CC_OFFBOX_ROOT="$tmp" CC_HOST_MANIFEST="$tmp/scripts/host-suites.manifest" \
             CC_OFFBOX_EXCLUDED="$tmp/scripts/offbox-excluded.manifest" \
             CC_OFFBOX_TESTS_DIR="$tmp/tests" bash "$SELF" "$@"; }

  # L1 set difference — 5 suites, 1 host-excluded, 1 off-box-excluded ⇒ 3 in the partition.
  printf 'tests/a.bats\n' > "$tmp/scripts/host-suites.manifest"
  printf 'tests/b.bats\n' > "$tmp/scripts/offbox-excluded.manifest"
  local got; got="$(run_fx list | tr '\n' ' ')"
  if [ "$got" = "tests/c.bats tests/d.bats tests/e.bats " ]; then
    printf 'ok   L1 set difference excludes both manifests\n'
  else
    printf 'FAIL L1 set difference — got: %s\n' "$got" >&2; st_fail=1
  fi

  # L1-control: the difference is REAL, not an artifact — emptying the exclusion re-admits the suite.
  : > "$tmp/scripts/offbox-excluded.manifest"
  run_fx list | grep -qxF 'tests/b.bats' \
    && printf 'ok   L1c control — de-listing re-admits the suite\n' \
    || { printf 'FAIL L1c control — b stayed out after de-listing\n' >&2; st_fail=1; }
  printf 'tests/b.bats\n' > "$tmp/scripts/offbox-excluded.manifest"

  # L2 lint clean on a well-formed fixture.
  st "L2 lint clean" 0 run_fx lint

  # L2a STALE entry ⇒ RED. The control for "the lint can see a rotted line at all".
  printf 'tests/b.bats\ntests/ghost.bats\n' > "$tmp/scripts/offbox-excluded.manifest"
  st "L2a stale entry reds" 1 run_fx lint
  printf 'tests/b.bats\n' > "$tmp/scripts/offbox-excluded.manifest"

  # L2b REDUNDANT entry ⇒ RED. The DOWNWARD half — an exemption already granted elsewhere.
  printf 'tests/a.bats\n' > "$tmp/scripts/offbox-excluded.manifest"
  st "L2b redundant-with-host entry reds" 1 run_fx lint
  printf 'tests/b.bats\n' > "$tmp/scripts/offbox-excluded.manifest"

  # L2c a malformed path ⇒ RED.
  printf 'tests/b.bats\nscripts/not-a-suite.sh\n' > "$tmp/scripts/offbox-excluded.manifest"
  st "L2c non-suite path reds" 1 run_fx lint
  printf 'tests/b.bats\n' > "$tmp/scripts/offbox-excluded.manifest"

  # L3 NON-DEGENERACY — excluding every suite must ERROR, never print an empty (vacuously green) set.
  printf 'tests/a.bats\ntests/b.bats\ntests/c.bats\ntests/d.bats\ntests/e.bats\n' > "$tmp/scripts/offbox-excluded.manifest"
  st "L3 total exclusion is an ERROR, not an empty partition" 2 run_fx list
  printf 'tests/b.bats\n' > "$tmp/scripts/offbox-excluded.manifest"

  # L4 FAIL-OPEN-WIDE — an ABSENT exclusion manifest widens the partition; it never narrows it.
  rm -f "$tmp/scripts/offbox-excluded.manifest"
  got="$(run_fx list | grep -c . || true)"
  [ "$got" -eq 4 ] \
    && printf 'ok   L4 absent manifest widens to 4 (host-excluded only)\n' \
    || { printf 'FAIL L4 absent manifest — expected 4 got %s\n' "$got" >&2; st_fail=1; }
  printf 'tests/b.bats\n' > "$tmp/scripts/offbox-excluded.manifest"

  # L5 SHARDING is total and disjoint — every partition member appears in exactly one shard.
  local n=3 union
  union="$( { run_fx shard 1 $n; run_fx shard 2 $n; run_fx shard 3 $n; } | LC_ALL=C sort )"
  if [ "$union" = "$(run_fx list | LC_ALL=C sort)" ] && [ "$(printf '%s\n' "$union" | LC_ALL=C sort -u | grep -c .)" -eq "$(printf '%s\n' "$union" | grep -c .)" ]; then
    printf 'ok   L5 shards partition the set (total + disjoint)\n'
  else
    printf 'FAIL L5 sharding is not a partition\n%s\n' "$union" >&2; st_fail=1
  fi

  # L5a an out-of-range shard is an ERROR, never a silent empty slice — an empty slice reads as
  # "this shard had nothing to run" and its job goes green, which is the sharded form of L3.
  st "L5a shard 4 of 3 errors" 2 run_fx shard 4 3
  st "L5b shard 0 errors" 2 run_fx shard 0 3

  # L6 THE REAL TREE — the shipped manifests must lint clean, or this script is describing a tree
  # that does not exist. Skipped when invoked against a fixture root.
  if [ -d "$ROOT/tests" ] && [ "$ROOT" != "$tmp" ]; then
    st "L6 the shipped tree lints clean" 0 bash "$SELF" lint
  fi

  [ "$st_fail" -eq 0 ] || { printf '\noffbox-partition --selftest: FAILED\n' >&2; return 1; }
  printf '\noffbox-partition --selftest: all controls green\n'
  return 0
}

case "${1:-}" in
  list)       shift; cmd_list "$@" ;;
  excluded)   shift; cmd_excluded "$@" ;;
  shard)      shift; cmd_shard "$@" ;;
  lint)       shift; cmd_lint "$@" ;;
  --selftest) shift; cmd_selftest "$@" ;;
  -h|--help)  usage ;;
  '')         usage; exit 2 ;;
  *)          die "unknown verb: $1 (try --help)" 2 ;;
esac
