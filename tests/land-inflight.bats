#!/usr/bin/env bats
# hooks/lib/land-inflight.sh — the ship-land IN-FLIGHT marker's ONE reader.
#
# THE CLASS (C31/C33/land-lock): `ps -o lstart=` formats through LC_TIME **and** TZ, so the same
# live pid reads as different strings depending on who looks. The marker's writer and its readers
# are DIFFERENT PROCESSES in DIFFERENT locales, so an unpinned compare is a coin toss.
#
# MEASURED 2026-08-21, and this is why the pair was a guaranteed miss rather than a rare one — the
# fleet's two lstart producers write OPPOSITE dialects:
#     ship-land-inflight markers on disk  →  3/3   `Fri Aug 21 08:05:57 2026`  (C)
#     ~/.claude/wait-contracts records    →  64/64 `Fri 21 Aug 11:03:20 2026`  (ambient en_CA)
# Same-moment, same-pid proof on a LIVE land (pid 21936, claude/fire-20260820T172902Z-13979-1):
#     STORED by ship-land        [Fri Aug 21 08:05:57 2026    ]
#     session reader renders     [Fri 21 Aug 08:05:57 2026    ]  → exact compare MISMATCHED,
# so land_inflight_live said NOT-IN-FLIGHT over a running land: wrap-ledger then renders 📦 "on a
# branch only — /ship to land it" DURING the land, and ship-land's exit-11 refusal never fires.
#
# A SINGLE-PROCESS TEST CANNOT SEE THIS BUG — it writes and reads in one env, where the locale is
# constant by construction. Every case below therefore drives a PATH-stubbed `ps` that renders
# per-locale (never /bin/ps, which on a C-locale box would silently no-op and certify nothing),
# and writes the record through the SAME stub the reader uses, so fixture and instrument cannot
# drift apart. Pattern: tests/land-lock.bats stub_locale_ps.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LIB="$REPO/hooks/lib/land-inflight.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"      # hermeticity rule 1
  WT="$BATS_TEST_TMPDIR/wt"; mkdir -p "$WT"
  git -C "$WT" init -q 2>/dev/null
  GD="$(git -C "$WT" rev-parse --absolute-git-dir)"
  MARKER="$GD/ship-land-inflight"
}

teardown() {
  [ -n "${LIVE:-}" ] && kill "$LIVE" 2>/dev/null || true
}

# <mode: skew|blind|stranger> — a $PATH `ps` emulating the hazard. One instant, three renderings.
stub_locale_ps() {
  STUB="$BATS_TEST_TMPDIR/stub"; mkdir -p "$STUB"
  cat > "$STUB/ps" <<PS
#!/bin/bash
q=
for a in "\$@"; do [ "\$a" = "lstart=" ] && q=1; done
[ -n "\$q" ] || exec /bin/ps "\$@"           # every other ps query is the real one
case "$1" in
  blind)    exit 0 ;;                         # the instrument cannot be read at all
  stranger) printf 'Thu Jan  1 00:00:00 2020    \n' ;;   # a DIFFERENT start instant, rendered
                                              # identically in every locale
  *) if [ "\${LC_ALL:-}" = "C" ] && [ "\${TZ:-}" = "UTC" ]; then
       printf 'Fri Aug 21 15:05:57 2026    \n'           # canonical  (TZ=UTC LC_ALL=C)
     elif [ "\${LC_ALL:-}" = "C" ]; then
       printf 'Fri Aug 21 08:05:57 2026    \n'           # C dialect, local TZ  (launchd)
     else
       printf 'Fri 21 Aug 08:05:57 2026    \n'           # ambient en_CA        (session)
     fi ;;
esac
PS
  chmod +x "$STUB/ps"
  PATH="$STUB:$PATH"; export PATH
}

# Write a marker exactly as the PRE-FIX ship-land did — a bare `ps -o lstart=` in the environment
# $1 describes ("launchd" = LC_ALL=C, "session" = ambient). Deliberately NOT via li_lstart: a
# red-proof fixture that calls a symbol the fix ADDS cannot run against the pre-fix tree, so it
# would fail there for the wrong reason and prove nothing (memory:
# red-proof-fixture-must-not-call-the-subject).
write_marker() {
  local who="$1" pid="$2" lst
  if [ "$who" = "launchd" ]; then lst="$(LC_ALL=C ps -o lstart= -p "$pid" 2>/dev/null || true)"
  else                            lst="$(ps -o lstart= -p "$pid" 2>/dev/null || true)"; fi
  { printf 'pid=%s\n' "$pid"; printf 'lstart=%s\n' "$lst"
    printf 'started=%s\n' "$(date +%s)"; printf 'branch=%s\n' "b"; } > "$MARKER"
  [ -s "$MARKER" ]                                    # armed, never silently empty
  grep -q 'lstart=..*' "$MARKER"                      # …and the lstart line is not blank
}

# Read the marker as a SESSION would — with a non-C LC_ALL pinned EXPLICITLY rather than inherited.
# Without this pin the cases below assert different things on different boxes: the off-box runner is
# `env -i LC_ALL=C`, where the reader's "ambient" IS C, so a case written to exercise the ambient
# dialect silently exercises the C one instead (and a hard-coded ambient record can then never
# match). The stub branches on the LC_ALL *string*, so this needs no locale to be installed.
#
# 🚨 ITS STDOUT MUST BE READ SEPARATELY — `run --separate-stderr` AT ANY SITE THAT ASSERTS $output.
# The line above is right that the STUB needs no locale installed, and that is why the trap is easy
# to miss: it is BASH, not the stub, that objects. On a box where en_CA.UTF-8 is not GENERATED —
# every stock container, and the off-box runner is one — bash prints
# `bash: warning: setlocale: LC_ALL: cannot change locale (en_CA.UTF-8)` to stderr at startup, and
# a plain `run` folds stderr into $output, so a prefix assertion matches the WARNING and not the
# reading. MEASURED 2026-08-31 (BACKLOG_DRAIN_24_7, the off-box cause census): 1 of 9 red, and the
# suite's own locale-independence claim is what made the cause invisible. Separating is right rather
# than suppressing — the subject's real stderr stays readable in $stderr.
read_live_as_session() { LC_ALL=en_CA.UTF-8 bash -c ". '$LIB'; land_inflight_live '$WT'"; }

@test "REGRESSION: a land started under launchd is IN FLIGHT to a session reader (cross-locale)" {
  # THE BUG, in its measured production shape: ship-land renders C (3/3 markers on disk), every
  # reader renders ambient, the exact string compare misses, and the guard reports NOT-IN-FLIGHT
  # over a live land — so wrap-ledger tells the operator to /ship a branch that is mid-land.
  stub_locale_ps skew
  /bin/sleep 30 & LIVE=$!
  write_marker launchd "$LIVE"
  grep -q 'lstart=Fri Aug 21 08:05:57' "$MARKER"      # the record really is in the C dialect…
  run --separate-stderr read_live_as_session           # …read by a session-shaped (ambient) env
  [ "$status" -eq 0 ]
  [[ "$output" == "$LIVE "* ]]                        # $output is STDOUT only — see the helper
}

@test "the canonical rendering is the SAME string from a session and from launchd" {
  # The write half of the pair, behaviourally: li_lstart must not inherit its caller's dialect, or
  # pinning the reader alone would just move the mismatch.
  stub_locale_ps skew
  /bin/sleep 30 & LIVE=$!
  a="$(bash -c ". '$LIB'; li_lstart $LIVE")"
  b="$(LC_ALL=C bash -c ". '$LIB'; li_lstart $LIVE")"
  c="$(LC_ALL=en_CA.UTF-8 TZ=America/Vancouver bash -c ". '$LIB'; li_lstart $LIVE")"
  [ -n "$a" ]
  [ "$a" = "$b" ]
  [ "$a" = "$c" ]
}

@test "MIGRATION: a PRE-PIN marker (C dialect, local TZ) is still IN FLIGHT, not a stranger" {
  # A canonical-only reader would reap exactly one live holder on the way in — the fix committing
  # the bug it removes. Every marker already on disk carries a pre-pin rendering.
  stub_locale_ps skew
  /bin/sleep 30 & LIVE=$!
  { printf 'pid=%s\n' "$LIVE"; printf 'lstart=%s\n' 'Fri Aug 21 08:05:57 2026    '
    printf 'started=%s\n' "$(date +%s)"; printf 'branch=%s\n' "b"; } > "$MARKER"
  run read_live_as_session
  [ "$status" -eq 0 ]
}

@test "MIGRATION: a PRE-PIN marker in the reader's OWN ambient dialect is still IN FLIGHT" {
  stub_locale_ps skew
  /bin/sleep 30 & LIVE=$!
  { printf 'pid=%s\n' "$LIVE"; printf 'lstart=%s\n' 'Fri 21 Aug 08:05:57 2026    '
    printf 'started=%s\n' "$(date +%s)"; printf 'branch=%s\n' "b"; } > "$MARKER"
  run read_live_as_session
  [ "$status" -eq 0 ]
}

@test "CONTROL (green on BOTH sides of the fix): same-locale writer and reader still match" {
  # Not evidence for the fix — it is the case a single-process test can see, and it must not have
  # regressed. Named a control so nobody later reads it as the red-proof.
  stub_locale_ps skew
  /bin/sleep 30 & LIVE=$!
  write_marker session "$LIVE"
  run bash -c ". '$LIB'; land_inflight_live '$WT'"
  [ "$status" -eq 0 ]
}

@test "MUTANT: a genuinely recycled pid is NOT laundered alive by the migration fallbacks" {
  # The fallbacks widen what counts as a match, and the false-IN-FLIGHT direction is the dangerous
  # one (it suppresses the 📦 nudge over parked work). This pins that they cannot reach a DIFFERENT
  # start instant: the stub renders 2020 in every locale, so no candidate can equal the record.
  stub_locale_ps stranger
  /bin/sleep 30 & LIVE=$!
  { printf 'pid=%s\n' "$LIVE"; printf 'lstart=%s\n' 'Fri Aug 21 08:05:57 2026    '
    printf 'started=%s\n' "$(date +%s)"; printf 'branch=%s\n' "b"; } > "$MARKER"
  run bash -c ". '$LIB'; land_inflight_live '$WT'"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "an UNREADABLE ps keeps the declared fail direction: NOT in flight, never a false claim" {
  stub_locale_ps blind
  /bin/sleep 30 & LIVE=$!
  { printf 'pid=%s\n' "$LIVE"; printf 'lstart=%s\n' 'Fri Aug 21 08:05:57 2026    '
    printf 'started=%s\n' "$(date +%s)"; printf 'branch=%s\n' "b"; } > "$MARKER"
  run bash -c ". '$LIB'; land_inflight_live '$WT'"
  [ "$status" -eq 1 ]
}

@test "a marker with NO lstart recorded cannot exonerate a recycled pid" {
  stub_locale_ps skew
  /bin/sleep 30 & LIVE=$!
  { printf 'pid=%s\n' "$LIVE"; printf 'started=%s\n' "$(date +%s)"; } > "$MARKER"
  run bash -c ". '$LIB'; land_inflight_live '$WT'"
  [ "$status" -eq 1 ]
}

@test "the WRITER and the READER share one dialect — ship-land records via li_lstart" {
  # The behavioural cases above prove the reader. This pins the other half of the pair, because a
  # writer that drifts back to a bare `ps` re-opens the whole defect with every reader test green.
  # The COUNT is asserted before the line is read: a first-match anchor silently retargets onto any
  # earlier colliding line, which is how the last of these pins went red for a reason that was not
  # a regression (memory: a first-match anchor encodes an unstated no-other-match claim).
  n="$(grep -c "printf 'lstart=%s" "$REPO/scripts/ship-land.sh" || true)"
  [ "$n" -eq 1 ]
  run grep "printf 'lstart=%s" "$REPO/scripts/ship-land.sh"
  # counted, not `[[ ]]`: a non-final [[ ]] is a DEAD assertion under errexit and
  # scripts/bats-assert-liveness.py rejects it. `grep -c` exits 1 on zero, hence the `|| true`.
  n_li="$(printf '%s' "$output" | grep -c 'li_lstart' || true)"
  [ "$n_li" -eq 1 ]
  n_ps="$(printf '%s' "$output" | grep -c 'ps -o lstart' || true)"
  [ "$n_ps" -eq 0 ]
}
