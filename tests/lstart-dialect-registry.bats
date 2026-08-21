#!/usr/bin/env bats
#
# {pid,lstart} DIALECT in the cc-registry triple — backlog bb9f69a6a2fa.
#
# THE HALF-PIN. `hooks/session-register.sh` writes the registry row's `lstart` and
# `bin/cc-sessions` + `bin/cc-notify` read it. All three pinned `TZ=UTC` — and only TZ. But
# `ps -o lstart=` renders through LC_TIME as well, and the two axes are independent, so a half-pin
# still leaves two spellings of ONE instant that differ in month/day ORDER:
#
#     canonical      TZ=UTC LC_ALL=C    `Fri Aug 21 15:45:00 2026`
#     UTC + ambient  TZ=UTC, en_CA      `Fri 21 Aug 15:45:00 2026`   <- every row the store holds
#     C at local TZ  LC_ALL=C           `Fri Aug 21 08:45:00 2026`
#     bare ambient                      `Fri 21 Aug 08:45:00 2026`
#
# WHY THIS WAS NOT LATENT. The rows are written by SESSIONS (LANG=en_CA.UTF-8), and both readers are
# reached from launchd jobs, which set no LANG and therefore render in C — measured, all 25 installed
# com.claude LaunchAgents set no LANG/LC_*, and two reach these readers (com.claude.boot-resume ->
# boot-resume.sh; com.claude.lead-supervisor -> lead-supervisor.sh, 21 call sites). Measured against
# an isolated copy of the live store at one instant: at the writer's own locale 10 sessions resolve
# LIVE, under LC_ALL=C only 3. Seven live sessions invisible to every unattended reader — cc-notify
# silently fails to resolve the peer, cc-sessions drops the row from the addressing view and reaps it
# past CC_REG_RETAIN_H.
#
# WHY A REPRODUCTION MUST PIN THE READER'S LOCALE. The defect lives in the DIFFERENCE between the
# writer's environment and the reader's. A test that inherits its reader locale holds that difference
# at whatever the box happens to supply, and its meaning becomes a property of the box — green on the
# desk, meaningless off-box, where `scripts/offbox-run.sh` runs `env -i LC_ALL=C`. Every case below
# sets LC_ALL explicitly.
#
# WHY THE FIX NORMALISES RATHER THAN RE-RENDERS. Re-running `ps` in the writer's dialect is the
# obvious repair and it does not work: under an exported `LC_ALL=C`, `TZ=UTC ps` overrides only TZ
# and LC_ALL still wins, so the reader cannot get the ambient rendering back. A reader does not know
# the writer's environment and cannot restore it. Both dialects here share TZ=UTC and differ only in
# field ORDER, so the readers canonicalise the ORDER instead — one `ps` fork, no dependence on
# anyone's locale. The normaliser cases below pin that it re-orders WITHOUT laundering a genuinely
# different start time.
#
# EXTRACTION: each predicate is pulled OUT OF THE REAL FILE at test time and sourced, so the bytes
# under test are the shipped bytes (memory: control-must-replay-the-real-artifact). `load_fn`
# asserts `declare -F` for every requested symbol, because an un-extracted function exits 127 and
# bats renders that as a WARNING while `[ "$status" -eq 1 ]` passes vacuously.

setup() {
  export BATS_TEST_TMPDIR="${BATS_TEST_TMPDIR:-$(mktemp -d)}"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  REPO="${CC_REDPROOF_TREE:-$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)}"
  export REPO

  # A real live process, so `kill -0` inside pid_live answers truthfully.
  sleep 300 &
  LIVE_PID=$!
  export LIVE_PID

  # The stub renders ONE fixed instant in the dialect its ambient env implies — the measured
  # behaviour of the real `ps`, reduced to the two axes these predicates depend on. Placed first on
  # $PATH; never /bin/ps, which would render one dialect and no-op the whole suite.
  STUB_DIR="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$STUB_DIR"
  cat > "$STUB_DIR/ps" <<'STUB'
#!/bin/bash
want=""; prev=""
for a in "$@"; do
  [ "$prev" = "-p" ] && want="$a"
  prev="$a"
done
[ -n "$want" ] || exit 1
[ "$want" = "$CC_STUB_LIVE_PID" ] || exit 1          # any other pid: gone (ESRCH shape)
if [ "${CC_STUB_UNREADABLE:-0}" = "1" ]; then exit 1; fi
if [ "${TZ:-}" = "UTC" ] && [ "${LC_ALL:-}" = "C" ]; then
  printf '%s\n' 'Fri Aug 21 15:45:00 2026'
elif [ "${TZ:-}" = "UTC" ]; then
  printf '%s\n' 'Fri 21 Aug 15:45:00 2026'
elif [ "${LC_ALL:-}" = "C" ]; then
  printf '%s\n' 'Fri Aug 21 08:45:00 2026'
else
  printf '%s\n' 'Fri 21 Aug 08:45:00 2026'
fi
STUB
  chmod +x "$STUB_DIR/ps"
  export CC_STUB_LIVE_PID="$LIVE_PID"
  export PATH="$STUB_DIR:$PATH"

  CANON='Fri Aug 21 15:45:00 2026'
  UTC_AMBIENT='Fri 21 Aug 15:45:00 2026'   # the dialect every live registry row is written in
  C_LOCAL='Fri Aug 21 08:45:00 2026'
  RECYCLED='Thu Jan  1 00:00:00 1970'
  export CANON UTC_AMBIENT C_LOCAL RECYCLED
}

teardown() {
  # `|| true`, not a trailing `; true`: the kill is the last command of the AND-list, so errexit is
  # NOT exempt there, and a child already REAPED under load returns 1 and aborts the body — a test
  # that passes on its merits going red only under load
  # (memory: kill-on-reaped-child-fails-fast-path-hides-it).
  [ -n "${LIVE_PID:-}" ] && { kill "$LIVE_PID" 2>/dev/null || true; }
  return 0
}

# Pull <fn> (and any helper it calls) out of the REAL file and source it.
load_fn() { # <file> <fn>...
  local file="$1"; shift
  local out="$BATS_TEST_TMPDIR/fn.$$.sh" fn
  : > "$out"
  for fn in "$@"; do
    awk -v F="$fn" '
      done_fn { next }
      $0 ~ "^"F"\\(\\) *\\{" && $0 ~ "\\}[[:space:]]*$" { print; done_fn=1; next }
      $0 ~ "^"F"\\(\\) *\\{"                            { inb=1 }
      inb { print }
      inb && /^\}/ { done_fn=1; inb=0 }
    ' "$REPO/$file" >> "$out"
  done
  [ -s "$out" ] || { echo "extraction of [$*] from $file produced NOTHING" >&2; return 1; }
  # shellcheck disable=SC1090
  . "$out"
  local missing=""
  for fn in "$@"; do
    declare -F "$fn" >/dev/null 2>&1 || missing="$missing $fn"
  done
  [ -z "$missing" ] || { echo "load_fn: NOT DEFINED after sourcing $file:$missing" >&2; return 1; }
}

# ── SITE 1 — bin/cc-sessions reg_lstart_matches (the lazy stale-sweep) ───────────────────────────

@test "R1 cc-sessions: a row written by a session is NOT stale to a C-locale reader" {
  # THE BUG. Record in the store's real dialect; reader is a launchd job (LC_ALL=C exported).
  # Pre-fix the reader renders canonical, compares it to a day-first record, and reaps a live
  # session. This is the only case in the file that changes verdict across the fix.
  export LC_ALL=C LANG=C
  load_fn bin/cc-sessions reg_lstart_norm reg_lstart_matches
  run reg_lstart_matches "$UTC_AMBIENT" "$LIVE_PID"
  [ "$status" -eq 0 ]
}

@test "R1 cc-sessions CONTROL: reader at the writer's own locale (green both sides of the fix)" {
  export LC_ALL=en_CA.UTF-8 LANG=en_CA.UTF-8
  load_fn bin/cc-sessions reg_lstart_norm reg_lstart_matches
  run reg_lstart_matches "$UTC_AMBIENT" "$LIVE_PID"
  [ "$status" -eq 0 ]
}

@test "R1 cc-sessions CONTROL: a canonical record matches a C-locale reader (green both sides)" {
  export LC_ALL=C LANG=C
  load_fn bin/cc-sessions reg_lstart_norm reg_lstart_matches
  run reg_lstart_matches "$CANON" "$LIVE_PID"
  [ "$status" -eq 0 ]
}

@test "R2 cc-sessions CONVICTS: a genuinely recycled pid is still stale" {
  # The converse half. A tolerant read must not become a disabled read
  # (memory: guard-proxy-fails-in-both-directions).
  export LC_ALL=C LANG=C
  load_fn bin/cc-sessions reg_lstart_norm reg_lstart_matches
  run reg_lstart_matches "$RECYCLED" "$LIVE_PID"
  [ "$status" -eq 1 ]
}

@test "R2 cc-sessions CONVICTS: a recycled pid spelled DAY-FIRST is still stale" {
  # The normaliser re-orders; it must not launder a different instant into a match.
  export LC_ALL=C LANG=C
  load_fn bin/cc-sessions reg_lstart_norm reg_lstart_matches
  run reg_lstart_matches "Thu  1 Jan 00:00:00 1970" "$LIVE_PID"
  [ "$status" -eq 1 ]
}

@test "R3 cc-sessions: an UNREADABLE ps fails OPEN (documented bias preserved)" {
  export LC_ALL=C LANG=C CC_STUB_UNREADABLE=1
  load_fn bin/cc-sessions reg_lstart_norm reg_lstart_matches
  run reg_lstart_matches "$UTC_AMBIENT" "$LIVE_PID"
  [ "$status" -eq 0 ]
}

@test "R3 cc-sessions: a row carrying NO lstart fails OPEN (predates the field)" {
  export LC_ALL=C LANG=C
  load_fn bin/cc-sessions reg_lstart_norm reg_lstart_matches
  run reg_lstart_matches "" "$LIVE_PID"
  [ "$status" -eq 0 ]
}

# ── SITE 2 — bin/cc-notify pid_live (name -> live pane resolution, the pager's own gate) ─────────

@test "R4 cc-notify: a peer registered by a session RESOLVES for a C-locale pager" {
  # THE BUG, second site. boot-resume.sh pages through cc-notify under launchd's C locale.
  export LC_ALL=C LANG=C
  load_fn bin/cc-notify reg_lstart_norm pid_live
  run pid_live "$LIVE_PID" "$UTC_AMBIENT"
  [ "$status" -eq 0 ]
}

@test "R4 cc-notify CONTROL: pager at the writer's own locale (green both sides of the fix)" {
  export LC_ALL=en_CA.UTF-8 LANG=en_CA.UTF-8
  load_fn bin/cc-notify reg_lstart_norm pid_live
  run pid_live "$LIVE_PID" "$UTC_AMBIENT"
  [ "$status" -eq 0 ]
}

@test "R5 cc-notify CONVICTS: a recycled pid is not the recorded peer" {
  export LC_ALL=C LANG=C
  load_fn bin/cc-notify reg_lstart_norm pid_live
  run pid_live "$LIVE_PID" "$RECYCLED"
  [ "$status" -eq 1 ]
}

@test "R5 cc-notify CONVICTS: the '-' sentinel is an ABSENT lstart, never a value" {
  export LC_ALL=C LANG=C
  load_fn bin/cc-notify reg_lstart_norm pid_live
  run pid_live "$LIVE_PID" "-"
  [ "$status" -eq 0 ]
}

@test "R6 cc-notify: an UNREADABLE ps fails OPEN (a hiccup cannot retire a live peer)" {
  export LC_ALL=C LANG=C CC_STUB_UNREADABLE=1
  load_fn bin/cc-notify reg_lstart_norm pid_live
  run pid_live "$LIVE_PID" "$UTC_AMBIENT"
  [ "$status" -eq 0 ]
}

# ── SITE 3 — the normaliser itself, and the WRITE that makes it converge ─────────────────────────

@test "R7 normaliser: day-first is re-ordered, month-first is left alone (idempotent)" {
  export LC_ALL=C LANG=C
  load_fn bin/cc-sessions reg_lstart_norm
  [ "$(reg_lstart_norm "$UTC_AMBIENT")" = "$CANON" ]
  [ "$(reg_lstart_norm "$CANON")" = "$CANON" ]
  [ "$(reg_lstart_norm "$(reg_lstart_norm "$UTC_AMBIENT")")" = "$CANON" ]
}

@test "R7 normaliser CONTROL: a malformed value is passed through, never mangled" {
  export LC_ALL=C LANG=C
  load_fn bin/cc-sessions reg_lstart_norm
  [ "$(reg_lstart_norm "garbage")" = "garbage" ]
  [ "$(reg_lstart_norm "")" = "" ]
}

@test "R8 the two readers carry the SAME normaliser (drift here re-opens the defect)" {
  # A per-file copy is the shape this fleet uses (bin/ tools source no shared lib), so the risk is
  # DRIFT, not absence. Compare the extracted bodies rather than trusting two greps.
  #
  # SPAN: the invariant is that the two copies BEHAVE alike, so comments and trailing whitespace are
  # stripped before the diff. Pinning the comment text too would red on a harmless doc edit — an
  # assertion spanning more than its subject tripwires the next honest change
  # (memory: assertion-span-must-equal-its-subject).
  export LC_ALL=C LANG=C
  a="$BATS_TEST_TMPDIR/a.sh"; b="$BATS_TEST_TMPDIR/b.sh"
  strip() { sed 's/[[:space:]]*#.*$//; s/[[:space:]]*$//' | grep -v '^$'; }
  awk '/^reg_lstart_norm\(\) *\{/{i=1} i{print} i&&/^\}/{exit}' "$REPO/bin/cc-sessions" | strip > "$a"
  awk '/^reg_lstart_norm\(\) *\{/{i=1} i{print} i&&/^\}/{exit}' "$REPO/bin/cc-notify"   | strip > "$b"
  [ -s "$a" ] || { echo "no reg_lstart_norm in bin/cc-sessions"; false; }
  [ -s "$b" ] || { echo "no reg_lstart_norm in bin/cc-notify"; false; }
  diff "$a" "$b" || { echo "reg_lstart_norm has DRIFTED between the two readers"; false; }
}

@test "R9 the WRITE is pinned canonical — exactly one lstart producer, TZ and LC both" {
  # Counted, not first-match: a second producer added later must fail this rather than hide behind
  # `-m1` (memory: greedy-anchor-matches-the-longer-token).
  export LC_ALL=C LANG=C
  prod="$(grep -c 'lstart=\$(TZ=UTC LC_ALL=C ps -o lstart=' "$REPO/hooks/session-register.sh" || true)"
  [ "${prod:-0}" -eq 1 ] || { echo "canonical lstart producers = ${prod:-0}, expected 1"; false; }
  half="$(grep -c 'lstart=\$(TZ=UTC ps -o lstart=' "$REPO/hooks/session-register.sh" || true)"
  [ "${half:-0}" -eq 0 ] || { echo "HALF-PINNED lstart producers still present = ${half:-0}"; false; }
}
