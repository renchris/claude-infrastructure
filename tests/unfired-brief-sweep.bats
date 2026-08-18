#!/usr/bin/env bats
# unfired-brief-sweep.sh — the detector for a succession that was WRITTEN and never FIRED.
# Backlog 4a11a0ac850a. Consumer of the `prompt_file` primitive added in the same commit.
#
# WHAT THESE CASES ARE ACTUALLY DEFENDING. The sweep is an ABSENCE test, and an absence test has
# exactly two ways to be worthless, both of which look like a working detector from outside:
#
#   TOO LOUD  — it reports every brief on disk, because the field it reads has no history. On the
#               day the primitive landed that was 98 briefs, i.e. 98 false positives on run one.
#               Cases "not armed" and "unknowable, not unfired" pin the two floors that prevent it.
#   TOO QUIET — it reports nothing, ever, because its finding set is structurally empty. This is the
#               dangerous one: it is byte-indistinguishable from a healthy machine. It ALREADY
#               HAPPENED here — `find /tmp` does not traverse the /private/tmp symlink, so the first
#               working draft found 0 files against a glob control's 98. The "through a symlinked
#               brief dir" case exists solely to make that failure loud, and it is pinned against a
#               control count rather than a bare "> 0" so it cannot pass by accident.
#
# RED-PROOF NOTE, stated rather than glossed: this suite's subject is a NEW file, so every case
# trivially reds against pristine origin/main (the script does not exist). A trivial red attributes
# nothing. The load-bearing site is therefore proved by MUTATION instead — see the final case, which
# removes the trailing slash and asserts the sweep goes blind.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SWEEP="$REPO/scripts/unfired-brief-sweep.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/logs"
  # Hermeticity seams: every path this script can read is pinned inside BATS_TEST_TMPDIR, so the
  # operator's real /tmp and real ledger are unreachable from here.
  BRIEFS="$BATS_TEST_TMPDIR/briefs"; mkdir -p "$BRIEFS"
  LEDGER="$BATS_TEST_TMPDIR/handoffs.jsonl"; : > "$LEDGER"
  export CC_BRIEF_DIR="$BRIEFS" CC_HANDOFF_LEDGER="$LEDGER"
}

# Append one ledger row. $1=ts $2=prompt_file (empty ⇒ the key is ABSENT, the pre-primitive shape).
_row() {
  if [ -n "${2:-}" ]; then
    jq -cn --arg ts "$1" --arg pf "$2" '{ts:$ts, class:"handoff", prompt_file:$pf}' >> "$LEDGER"
  else
    jq -cn --arg ts "$1" '{ts:$ts, class:"handoff"}' >> "$LEDGER"
  fi
}
# Stamp a path with an mtime N seconds in the past. $1=path $2=seconds-ago
#
# 🚨 LOCAL TIME, NOT UTC, AND THE SUITE IS WRONG WITHOUT IT. `touch -t` reads its argument as LOCAL
# time; `date -u` prints UTC. Feeding one to the other shifts every fixture mtime by the zone
# offset — measured here at -0700, so a "2 hours ago" brief landed 5 hours in the FUTURE and the
# sweep correctly counted it as held-in-grace. Four cases went red for a defect that was entirely
# in this helper, and the failure direction is the dangerous one: had the offset been positive, the
# fixtures would have drifted deeper into the past and the grace/floor cases would have passed
# VACUOUSLY, certifying boundaries the suite never actually crossed.
_stamp() { touch -t "$(date -v-"$2"S +%Y%m%d%H%M.%S 2>/dev/null || date -d "-$2 seconds" +%Y%m%d%H%M.%S)" "$1"; }
# A brief file with an explicit mtime. $1=name $2=seconds-ago
_brief() {
  local p="$BRIEFS/$1"; printf 'brief\n' > "$p"
  _stamp "$p" "$2"
  printf '%s' "$p"
}
_iso_ago() { date -u -v-"$1"S +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "-$1 seconds" +%Y-%m-%dT%H:%M:%SZ; }

# ── the TOO-LOUD floor: no history ⇒ not armed ─────────────────────────────────────────────────
@test "with no ledger row carrying prompt_file the sweep is NOT ARMED and reports nothing" {
  _row "$(_iso_ago 86400)" ""          # pre-primitive rows: the key is absent, not null
  _brief old-one.txt 7200 >/dev/null   # a brief that would be a false positive
  run bash "$SWEEP" --json
  [ "$status" -eq 0 ]
  [ "$(jq -r '.verdict' <<<"$output")" = "not-armed" ]
  [ "$(jq -r '.findings | length' <<<"$output")" = "0" ]
}

# ── a missing ledger is not an empty one ───────────────────────────────────────────────────────
@test "a missing ledger reports not-armed, never every brief as unfired" {
  rm -f "$LEDGER"
  _brief orphan.txt 7200 >/dev/null
  run bash "$SWEEP" --json
  [ "$status" -eq 0 ]
  [ "$(jq -r '.verdict' <<<"$output")" = "not-armed" ]
  [ "$(jq -r '.findings | length' <<<"$output")" = "0" ]
}

# ── the finding the whole file exists for ──────────────────────────────────────────────────────
@test "an armed sweep reports a brief inside the window that no fire row names" {
  _row "$(_iso_ago 86400)" "$BRIEFS/some-other.txt"    # arms the epoch
  b="$(_brief fire-lost.txt 7200)"
  run bash "$SWEEP" --json
  [ "$status" -eq 0 ]
  [ "$(jq -r '.verdict' <<<"$output")" = "swept" ]
  [ "$(jq -r '.counts.unfired' <<<"$output")" = "1" ]
  [ "$(jq -r '.findings[0]' <<<"$output")" = "$b" ]
}

@test "a brief a fire row does name is clean, not reported" {
  b="$(_brief fire-ok.txt 7200)"
  _row "$(_iso_ago 86400)" "$b"
  run bash "$SWEEP" --json
  [ "$status" -eq 0 ]
  [ "$(jq -r '.counts.clean' <<<"$output")"   = "1" ]
  [ "$(jq -r '.counts.unfired' <<<"$output")" = "0" ]
}

# ── the TOO-LOUD floor, second half: retention, not succession ─────────────────────────────────
# A fire whose row the 1200-row self-trim already deleted leaves a brief that reads unfired for a
# reason that is evidence-expiry. Counted as UNKNOWABLE and excluded from findings — an unknown
# reported as a fault is the same lie as an unknown reported as clean.
@test "a brief older than the floor is unknowable, never a finding" {
  _row "$(_iso_ago 3600)" "$BRIEFS/recent.txt"   # epoch is one hour ago
  _brief fire-ancient.txt 86400 >/dev/null        # brief predates it by a day
  run bash "$SWEEP" --json
  [ "$status" -eq 0 ]
  [ "$(jq -r '.counts.unknowable_pre_floor' <<<"$output")" = "1" ]
  [ "$(jq -r '.counts.unfired' <<<"$output")" = "0" ]
}

# ── not yet fired is not a fault ───────────────────────────────────────────────────────────────
@test "a brief younger than the grace window is held, not reported as lost" {
  _row "$(_iso_ago 86400)" "$BRIEFS/some-other.txt"
  _brief fire-justwritten.txt 5 >/dev/null
  run bash "$SWEEP" --json --grace 1800
  [ "$status" -eq 0 ]
  [ "$(jq -r '.counts.held_in_grace' <<<"$output")" = "1" ]
  [ "$(jq -r '.counts.unfired' <<<"$output")" = "0" ]
}

# ── exactness is the sweep's whole claim ───────────────────────────────────────────────────────
# A substring test would let fire-a.txt be "found" by a row naming fire-ab.txt, silently acquitting
# a genuinely lost succession — a false NEGATIVE in a detector whose only output is findings.
@test "matching is exact: a longer path in the ledger does not acquit a shorter brief" {
  _row "$(_iso_ago 86400)" "$BRIEFS/fire-ab.txt"
  b="$(_brief fire-a.txt 7200)"
  run bash "$SWEEP" --json
  [ "$status" -eq 0 ]
  [ "$(jq -r '.counts.unfired' <<<"$output")" = "1" ]
  [ "$(jq -r '.findings[0]' <<<"$output")" = "$b" ]
}

# ── THE TOO-QUIET pin, proved by MUTATION ──────────────────────────────────────────────────────
# The live defect: `find /tmp` does not traverse Darwin's /tmp → /private/tmp symlink, so the sweep's
# finding set was structurally empty and it reported all-clear over 98 unexamined briefs. Here the
# brief dir is reached through a symlink and the count is asserted against a GLOB control, so the
# case measures traversal rather than merely "some number of files". The mutation removes the
# trailing slash from the real script and asserts the sweep goes blind — without it, a green suite
# would credit no site for this property (memory per-site-mutation-attributes-coverage).
@test "briefs are found through a symlinked brief dir, and the trailing slash is what does it" {
  real="$BATS_TEST_TMPDIR/real-briefs"; mkdir -p "$real"
  ln -s "$real" "$BATS_TEST_TMPDIR/link-briefs"
  export CC_BRIEF_DIR="$BATS_TEST_TMPDIR/link-briefs"
  _row "$(_iso_ago 86400)" "$real/some-other.txt"
  for n in 1 2 3; do
    printf 'brief\n' > "$real/fire-$n.txt"
    _stamp "$real/fire-$n.txt" 7200
  done
  # `ls` over a SHELL GLOB is the point: the subject under test is `find`'s symlink traversal, so a
  # control built from `find` would be a restatement of the thing it independently checks — and it
  # would have agreed with the bug (0 == 0). The glob resolves the symlink through the shell, which
  # is the decorrelated second opinion. Filenames here are fixtures this test creates, so SC2012's
  # actual hazard does not arise. (Directive on its own single line — see SC1073 above.)
  # shellcheck disable=SC2012
  control=$(ls -1 "$BATS_TEST_TMPDIR"/link-briefs/fire-*.txt | wc -l | tr -d ' ')
  [ "$control" = "3" ]

  run bash "$SWEEP" --json
  [ "$status" -eq 0 ]
  [ "$(jq -r '.counts.unfired' <<<"$output")" = "$control" ]

  # MUTANT: revert the traversal fix in a copy. The sweep must go blind — if it does not, this case
  # is not measuring what its name claims and the trailing slash is unattributed.
  mutant="$BATS_TEST_TMPDIR/mutant-sweep.sh"
  # shellcheck disable=SC2016
  # $BRIEF_DIR is LITERAL SOURCE TEXT being matched inside the script, not a value to expand here.
  sed 's|find "$BRIEF_DIR/"|find "$BRIEF_DIR"|g' "$SWEEP" > "$mutant"
  ! cmp -s "$SWEEP" "$mutant" || { echo "mutation was a no-op — the anchor no longer matches" >&2; return 1; }
  run bash "$mutant" --json
  [ "$status" -eq 0 ]
  [ "$(jq -r '.counts.unfired' <<<"$output")" = "0" ]
}

# ── THE CALLER IS PART OF THE FEATURE ──────────────────────────────────────────────────────────
# `wait-contract-lint.sh --sweep` is built, --selftest 13/13 GREEN, and has NO caller in launchd or
# in autonomy-sweep — so the flagship strand watchdog has never once fired in production (desk-audit
# p04 G-P4-2, open to this day). A detector with no scheduler is not a detector. The invariant lives
# in a token that would vanish SILENTLY if someone tidied the sweep, so it is pinned here
# (memory invariant-can-live-in-an-absent-token).
#
# The ORDERING half is the load-bearing one and is asserted by line number, not by presence: a lost
# succession emits no page and no alarm, so a call placed BELOW the `total_new -eq 0` early exit
# would run only on sweeps that already had other news — i.e. never on the quiet fleet where a dead
# chain actually sits. Present-but-below is the failure this case exists to catch, and it is
# indistinguishable from correct by any grep that only asks "is it called".
@test "autonomy-sweep calls the sweep, ABOVE its nothing-new early exit" {
  AS="$REPO/scripts/autonomy-sweep.sh"
  [ -f "$AS" ]
  call_line=$(grep -n 'unfired-brief-sweep.sh' "$AS" | head -1 | cut -d: -f1)
  exit_line=$(grep -n 'reason":"nothing-new' "$AS" | head -1 | cut -d: -f1)
  [ -n "$call_line" ] || { echo "autonomy-sweep does not call unfired-brief-sweep.sh at all" >&2; return 1; }
  [ -n "$exit_line" ] || { echo "the nothing-new early exit anchor no longer matches — this case is blind" >&2; return 1; }
  [ "$call_line" -lt "$exit_line" ]
}
