#!/usr/bin/env bats
#
# {pid,lstart} DIALECT across the bin/ tools — backlog 7a00b5de1ec0.
#
# THE BUG A SINGLE-PROCESS TEST CANNOT SEE. `ps -o lstart=` formats through LC_TIME *and* TZ, so one
# live pid renders as several different strings depending on who is looking. A test that writes and
# reads inside ONE process holds the locale constant by construction and is therefore green on both
# sides of the fix — which is exactly why tests/cc-reaper.bats:1145 caught the PADDING half of this
# class and missed the locale half. Every case below drives a STUBBED `ps` placed first on $PATH
# (never /bin/ps, which on a C-locale box silently renders one dialect and no-ops the whole suite).
#
# The three dialects are not guessed spellings — they are what this fleet was MEASURED to produce for
# ONE pid at ONE instant (memory: denylist-enumerates-spellings-not-the-class):
#     canonical  TZ=UTC LC_ALL=C   `Fri Aug 21 15:45:00 2026`
#     ambient    LANG=en_CA.UTF-8  `Fri 21 Aug 08:45:00 2026`
#     C at local TZ                `Fri Aug 21 08:45:00 2026`
#
# EXTRACTION, and why it is not a lookalike. Each predicate is pulled OUT OF THE REAL FILE at test
# time and sourced, because these tools run their main logic on source. The bytes under test are the
# shipped bytes, not a transcription (memory: control-must-replay-the-real-artifact). That the
# extraction actually REACHES the site is not assumed: the per-site mutant arm in
# scripts/redproof-lstart-dialect.sh rewrites ONE file's matcher and requires exactly ONE test here
# to go red, so a test that silently stopped exercising its subject fails loud.

setup() {
  export BATS_TEST_TMPDIR="${BATS_TEST_TMPDIR:-$(mktemp -d)}"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  REPO="${CC_REDPROOF_TREE:-$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)}"
  export REPO

  # A real live process, so `kill -0` in the predicates answers truthfully.
  sleep 300 &
  LIVE_PID=$!
  export LIVE_PID

  # The stub renders ONE fixed instant in the dialect its ambient env implies — the measured
  # behaviour of the real ps, reduced to what these predicates depend on.
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
elif [ "${LC_ALL:-}" = "C" ]; then
  printf '%s\n' 'Fri Aug 21 08:45:00 2026'
else
  printf '%s\n' 'Fri 21 Aug 08:45:00 2026'
fi
STUB
  chmod +x "$STUB_DIR/ps"
  export CC_STUB_LIVE_PID="$LIVE_PID"
  export PATH="$STUB_DIR:$PATH"

  # PIN THE READER'S LOCALE EXPLICITLY — do NOT inherit it. A test for a locale defect whose own
  # reader-side locale comes from the environment has a meaning that is a property of the box it ran
  # on. The hermetic off-box runner (`scripts/offbox-run.sh`) uses `env -i LC_ALL=C`, so there the
  # reader's "ambient" IS C, the same-dialect control below has no dialect to match, and the suite
  # goes red for a reason that has nothing to do with the subject. Measured: 15/1 off-box, green on
  # the desk. The value need not be a locale the box has generated — the stub keys on `LC_ALL != C`,
  # which is exactly the distinction the real `ps` makes here.
  export LC_ALL=en_CA.UTF-8

  AMBIENT='Fri 21 Aug 08:45:00 2026'
  C_LOCAL='Fri Aug 21 08:45:00 2026'
  CANON='Fri Aug 21 15:45:00 2026'
  RECYCLED='Thu Jan  1 00:00:00 1970'
  export AMBIENT C_LOCAL CANON RECYCLED
}

teardown() {
  # `|| true`, not a trailing `; true` and not the `&&` above: the kill is the last command of the
  # AND-list, so errexit is NOT exempt there, and a child already REAPED under load returns 1 and
  # aborts the body — a test that passed on its own merits going red only under load
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
    # A one-line definition (`f(){ ...; }`) is taken WHOLE and nothing follows it; only a multi-line
    # definition runs to its column-0 `}`. Conflating the two swallows every line up to the NEXT
    # function's brace, dragging unrelated top-level code (including `die3` calls) into the sourced
    # file. The block-start pattern must also tolerate a trailing COMMENT after the brace, which is
    # this repo's house style for a signature note — requiring end-of-line after `{` matched none of
    # the multi-line matchers and extracted NOTHING for them.
    awk -v F="$fn" '
      done_fn { next }
      $0 ~ "^"F"\\(\\) *\\{" && $0 ~ "\\}[[:space:]]*$" { print; done_fn=1; next }
      $0 ~ "^"F"\\(\\) *\\{"                            { inb=1 }
      inb { print }
      inb && /^\}/ { done_fn=1; inb=0 }
    ' "$REPO/$file" >> "$out"
  done
  # An empty extraction is a VACUOUS test, not a pass.
  [ -s "$out" ] || { echo "extraction of [$*] from $file produced NOTHING" >&2; return 1; }
  # shellcheck disable=SC1090
  . "$out"
  # THE POSITIVE CONTROL ON THE INSTRUMENT ITSELF. An un-extracted function makes `run <fn>` exit
  # 127, and bats renders that as a WARNING (BW01) while `[ "$status" -eq 1 ]` happily passes — so
  # every negative-direction case here would go green while testing nothing at all. Measured: 5 of
  # this suite's cases were vacuously green exactly that way before this guard existed.
  local missing=""
  for fn in "$@"; do
    declare -F "$fn" >/dev/null 2>&1 || missing="$missing $fn"
  done
  [ -z "$missing" ] || { echo "load_fn: NOT DEFINED after sourcing $file:$missing" >&2; return 1; }
}

# ── SITE 1 — bin/cc-backlog land_lock_owner (reads a record land-lock.sh WRITES) ─────────────────
@test "S1 cc-backlog: a land-lock record from a C-locale writer is not a stranger" {
  load_fn bin/cc-backlog llo_lstart_matches
  run llo_lstart_matches "$C_LOCAL" "$LIVE_PID"
  [ "$status" -eq 0 ]
}

@test "S1 cc-backlog CONTROL: a same-dialect record still matches (green both sides)" {
  load_fn bin/cc-backlog llo_lstart_matches
  run llo_lstart_matches "$AMBIENT" "$LIVE_PID"
  [ "$status" -eq 0 ]
}

@test "S1 cc-backlog CONTROL: a genuinely recycled pid IS a stranger (green both sides of the fix)" {
  load_fn bin/cc-backlog llo_lstart_matches
  run llo_lstart_matches "$RECYCLED" "$LIVE_PID"
  [ "$status" -eq 1 ]
}

# ── SITE 2 — bin/cc-reaper sweep lock (this file owns both ends) ─────────────────────────────────
@test "S2 cc-reaper: a sweep-lock record from a C-locale sweep keeps the holder ALIVE" {
  load_fn bin/cc-reaper proc_lstart lstart_matches
  run lstart_matches "$C_LOCAL" "$LIVE_PID"
  [ "$status" -eq 0 ]
}

@test "S2 cc-reaper: an UNREADABLE ps honours the holder rather than breaking the mutex" {
  load_fn bin/cc-reaper proc_lstart lstart_matches
  CC_STUB_UNREADABLE=1 run lstart_matches "$C_LOCAL" "$LIVE_PID"
  [ "$status" -eq 0 ]
}

@test "S2 cc-reaper CONTROL: a recycled pid still breaks the lock" {
  load_fn bin/cc-reaper proc_lstart lstart_matches
  run lstart_matches "$RECYCLED" "$LIVE_PID"
  [ "$status" -eq 1 ]
}

# ── SITE 3 — bin/cc-reaper watchdog census (reads lead-crash-watchdog's .daemon record) ──────────
@test "S3 cc-reaper: a .daemon record from a C-locale watchdog is not an untracked orphan" {
  load_fn bin/cc-reaper wd_lstart wd_lstart_matches
  run wd_lstart_matches "$C_LOCAL" "$LIVE_PID"
  [ "$status" -eq 0 ]
}

@test "S3 cc-reaper CONTROL: unverifiable identity stays NOT-ours (documented bias preserved)" {
  load_fn bin/cc-reaper wd_lstart wd_lstart_matches
  CC_STUB_UNREADABLE=1 run wd_lstart_matches "$C_LOCAL" "$LIVE_PID"
  [ "$status" -eq 1 ]
}

# ── SITE 4 — bin/cc-dispatch singleton lock (this file owns both ends) ───────────────────────────
@test "S4 cc-dispatch: a lock owner recorded by a C-locale dispatcher reads LIVE" {
  load_fn bin/cc-dispatch is_uint lock_holder_live
  LOCK_DIR="$BATS_TEST_TMPDIR/dispatch.lock"; mkdir -p "$LOCK_DIR"
  printf '%s|%s\n' "$LIVE_PID" "$C_LOCAL" > "$LOCK_DIR/owner"
  run lock_holder_live
  [ "$status" -eq 0 ]
}

@test "S4 cc-dispatch CONTROL: a recycled owner is stale, so the lock is broken" {
  load_fn bin/cc-dispatch is_uint lock_holder_live
  LOCK_DIR="$BATS_TEST_TMPDIR/dispatch.lock"; mkdir -p "$LOCK_DIR"
  printf '%s|%s\n' "$LIVE_PID" "$RECYCLED" > "$LOCK_DIR/owner"
  run lock_holder_live
  [ "$status" -eq 1 ]
}

# ── SITE 5 — bin/cc-respawn verify-stopped (the --start string comes from a CALLER) ──────────────
@test "S5 cc-respawn: a --start from a C-locale caller is the SAME process" {
  load_fn bin/cc-respawn start_is_same
  run start_is_same "$C_LOCAL" "$LIVE_PID"
  [ "$status" -eq 0 ]
}

@test "S5 cc-respawn CONTROL: a genuinely recycled pid is still a stranger" {
  load_fn bin/cc-respawn start_is_same
  run start_is_same "$RECYCLED" "$LIVE_PID"
  [ "$status" -eq 1 ]
}

# ── SITE 6 — bin/cc-pane-headless is_live (this file owns both ends of meta `pstart`) ────────────
@test "S6 cc-pane-headless: a pstart recorded by a C-locale process stays LIVE" {
  load_fn bin/cc-pane-headless pstart_of pstart_matches
  run pstart_matches "$C_LOCAL" "$LIVE_PID"
  [ "$status" -eq 0 ]
}

@test "S6 cc-pane-headless CONTROL: a recycled agent is dead" {
  load_fn bin/cc-pane-headless pstart_of pstart_matches
  run pstart_matches "$RECYCLED" "$LIVE_PID"
  [ "$status" -eq 1 ]
}

# ── SITE 7 — bin/cc-deathwatch-kqueue (the start column comes from the WATCH FILE) ───────────────
@test "S7 cc-deathwatch-kqueue: a watch-file start from a C-locale writer is not 'recycled'" {
  run env CC_STUB_LIVE_PID="$LIVE_PID" PATH="$STUB_DIR:$PATH" python3 -c "
import importlib.util, sys
spec = importlib.util.spec_from_loader('dw', loader=None)
m = importlib.util.module_from_spec(spec)
exec(open('$REPO/bin/cc-deathwatch-kqueue').read().split('def main(')[0], m.__dict__)
sys.exit(0 if m.start_is_same('$C_LOCAL', $LIVE_PID) else 1)
"
  [ "$status" -eq 0 ]
}

@test "S7 cc-deathwatch-kqueue CONTROL: a genuinely recycled pid IS 'recycled'" {
  run env CC_STUB_LIVE_PID="$LIVE_PID" PATH="$STUB_DIR:$PATH" python3 -c "
import importlib.util, sys
spec = importlib.util.spec_from_loader('dw', loader=None)
m = importlib.util.module_from_spec(spec)
exec(open('$REPO/bin/cc-deathwatch-kqueue').read().split('def main(')[0], m.__dict__)
sys.exit(0 if m.start_is_same('$RECYCLED', $LIVE_PID) else 1)
"
  [ "$status" -eq 1 ]
}
