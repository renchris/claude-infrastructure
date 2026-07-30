#!/usr/bin/env bats
# utc-stamp-lint — the RATCHET that stops a timestamp from CLAIMING UTC while carrying local time (M4).
#
# The failure it exists for is in-tree history, not a hypothetical: cc-reaper's log() was
#     printf '[%s] ...' "$(date '+%Y-%m-%dT%H:%M:%SZ')"
# and b4e3c355 fixed it to `date -u`, with the commit subject naming the consequence — "a bare date
# read hours stale as Z, faking 'reaper DORMANT'". Timestamp format is a system-wide CONTRACT here:
# producers emit ISO stamps and consumers compare them against a `date -u` baseline (lexically in jq
# at cc-backlog's `.lastTs < $cutoff`, numerically after epoch conversion in cc-inbox-guard and
# cc-reaper), so a single local-time producer under a UTC label shifts every downstream age gate by
# the TZ offset. That is the M4 dimension the per-component audit was structurally blind to.
#
# Three properties are proved here, and all three matter:
#   • it DISCRIMINATES — red on the real scar, green on every legitimate form the tree actually uses;
#   • it is GREEN on the tree as it stands — a lint that ships standing-red is rot, and the nightly
#     runs every scripts/*lint*.sh, so a false red here poisons the whole nightly signal;
#   • it is WIRED AT THE CHOKEPOINT — enforcement by its own suite alone is detection, not a gate
#     (memory: enforcement-must-live-at-the-chokepoint), so run_gate must invoke it.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LINT="$REPO/scripts/utc-stamp-lint.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"   # dogfood the sibling hermeticity rule
  FIX="$BATS_TEST_TMPDIR/fix"; mkdir -p "$FIX"
  # The lying stamp is ASSEMBLED, never written as a literal: a literal would make THIS suite a
  # violation by its own rule, and a lint whose own tests violate it is not shippable. (The lint
  # excludes only itself, not its tests.)
  Z="Z"; FMT="+%Y-%m-%dT%H:%M:%S${Z}"
}

mkdirf() { mkdir -p "$FIX/$1"; }
write() { printf '%s\n' "$2" > "$FIX/$1/probe.sh"; }

@test "1: the lint's own --selftest passes (17/17, both directions)" {
  run bash "$LINT" --selftest
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s' "$output" | grep -q '17/17' || { echo "selftest count changed — update this assertion deliberately: $output"; false; }
}

@test "2: RED on a Z-stamp from a bare date (the b4e3c355 scar shape)" {
  mkdirf scar
  write scar "log(){ printf '[%s]' \"\$(date '$FMT')\"; }"
  run bash "$LINT" "$FIX/scar"
  [ "$status" -eq 1 ] || { echo "expected rc 1, got $status: $output"; false; }
  printf '%s' "$output" | grep -q 'LYING-Z' || { echo "no LYING-Z verdict: $output"; false; }
}

@test "3: GREEN on every legitimate form the tree actually uses" {
  # Measured over the tree before this landed: 84 sites use `date -u` with a Z; 4 use an explicit %z
  # offset (cc-notify, mailbox-pending) which cc-inbox-guard:134 parses offset-aware; dozens use a
  # plain '%Y-%m-%d %H:%M:%S' log prefix that asserts nothing. All must stay legal — a lint that
  # cries wolf over the correct idiom gets disabled.
  mkdirf ok
  {
    printf '%s\n' "a(){ date -u '$FMT'; }"
    printf '%s\n' "b(){ TZ=UTC date -j -f '%Y-%m-%dT%H:%M:%S' \"\$1\" +%s; }"
    printf '%s\n' "c(){ date '+%Y-%m-%dT%H:%M:%S%z'; }"
    printf '%s\n' "d(){ echo \"[\$(date '+%Y-%m-%d %H:%M:%S')] x\"; }"
  } > "$FIX/ok/probe.sh"
  run bash "$LINT" "$FIX/ok"
  [ "$status" -eq 0 ] || { echo "a legitimate UTC/offset/log form was flagged: $output"; false; }
}

@test "4: GREEN when the scar appears only in a COMMENT (prose is not code)" {
  mkdirf prose
  write prose "# a bare \`date '$FMT'\` here is the documented scar
now(){ date -u +%s; }"
  run bash "$LINT" "$FIX/prose"
  [ "$status" -eq 0 ] || { echo "a commented scar was flagged — this trains people to ignore the lint: $output"; false; }
}

@test "5: RED on a NAIVE python datetime rendered with a literal Z" {
  mkdirf py
  printf '%s\n' "stamp = datetime.now().strftime('$FMT')" > "$FIX/py/probe.py"
  run bash "$LINT" "$FIX/py"
  [ "$status" -eq 1 ] || { echo "a naive datetime stamped Z was not flagged: $output"; false; }
}

@test "6: GREEN on an AWARE python datetime (the correct form, used in-tree)" {
  mkdirf pyok
  printf '%s\n' "stamp = datetime.now(timezone.utc).isoformat().replace('+00:00', '$Z')" > "$FIX/pyok/probe.py"
  run bash "$LINT" "$FIX/pyok"
  [ "$status" -eq 0 ] || { echo "the correct aware-datetime form was flagged: $output"; false; }
}

@test "7: own-scope — a violation OUTSIDE the diff is advisory, INSIDE it blocks" {
  mkdirf own
  write own "log(){ date '$FMT'; }"
  CC_UTC_OWN="other.sh" run bash "$LINT" "$FIX/own"
  [ "$status" -eq 0 ] || { echo "a violation outside the own-set BLOCKED — that is the fleet-wide hard stop: $output"; false; }
  printf '%s' "$output" | grep -q 'advisory' || { echo "not reported as advisory: $output"; false; }
  CC_UTC_OWN="probe.sh" run bash "$LINT" "$FIX/own"
  [ "$status" -eq 1 ] || { echo "a violation INSIDE the own-set did not block: $output"; false; }
}

@test "8: own-scope — SET-BUT-EMPTY blocks nothing; ABSENT stays strict" {
  mkdirf tri
  write tri "log(){ date '$FMT'; }"
  CC_UTC_OWN="" run bash "$LINT" "$FIX/tri"
  [ "$status" -eq 0 ] || { echo "an EMPTY own-set blocked — set-empty collapsed into unset: $output"; false; }
  run bash "$LINT" "$FIX/tri"
  [ "$status" -eq 1 ] || { echo "an ABSENT own-set did not block — the strict default was lost: $output"; false; }
}

@test "9: a bad scan target is a NON-VERDICT (2), never a silent pass" {
  run bash "$LINT" /nonexistent/xyz-utc
  [ "$status" -eq 2 ] || { echo "expected rc 2 (loud), got $status: $output"; false; }
}

@test "10: a BARE invocation actually scans (the silent-no-op regression)" {
  # `for t in "${@:-$A $B $C}"` expands the default as ONE word, so the loop body never ran and the
  # lint exited 0 having scanned nothing — a false green in its DEFAULT mode. Assert it reports real
  # work, not just rc 0, since rc 0 is exactly what the bug produced.
  run bash "$LINT"
  [ "$status" -eq 0 ] || { echo "the real tree is not clean: $output"; false; }
  printf '%s' "$output" | grep -qE 'clean — [0-9]+ file' || { echo "bare run reported no scan: $output"; false; }
  # and it must be a non-trivial number of files, not one
  local n; n=$(printf '%s' "$output" | grep -oE 'clean — [0-9]+' | grep -oE '[0-9]+' | sort -rn | head -1)
  [ "${n:-0}" -ge 20 ] || { echo "bare run scanned only ${n:-0} file(s) — the default targets are wrong"; false; }
}

@test "11: the real tree is clean with an EMPTY allowlist (a true ratchet)" {
  for d in bin hooks scripts; do
    run bash "$LINT" "$REPO/$d"
    [ "$status" -eq 0 ] || { echo "$d carries a lying UTC stamp: $output"; false; }
  done
  # nothing grandfathered — the allowlist can only shrink, and it starts at zero
  grep -q 'EMBEDDED_ALLOWLIST=""' "$LINT" || { echo "the allowlist is no longer empty — a violation was grandfathered instead of fixed"; false; }
}

@test "12: it is WIRED INTO run_gate, not enforced only by this suite" {
  # A lint enforced solely by its own bats suite is post-hoc detection: gate-select will not pick this
  # suite up when the edited file is a PRODUCER rather than the lint itself, which is exactly how the
  # hermeticity leak landed twice in one session.
  grep -q 'utc-stamp-lint.sh' "$REPO/scripts/ship-land.sh" || { echo "run_gate does not invoke the lint"; false; }
  grep -q 'CC_UTC_OWN=' "$REPO/scripts/ship-land.sh" || { echo "run_gate does not pass the own-scope set"; false; }
  # the gate must also verify the detector still discriminates before trusting a clean verdict
  grep -qE 'UTC_LINT.*--selftest|--selftest.*utc' "$REPO/scripts/ship-land.sh" || {
    echo "run_gate trusts the lint without running its selftest — a clean verdict from a broken detector"; false; }
}
