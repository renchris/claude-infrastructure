#!/bin/bash
# bsd-compat.sh — run a macOS-authored command on Linux by putting BSD date(1)/stat(1) shims at the
# front of PATH. An INVESTIGATION tool. It is wired into no gate, no plist and no hook, and the two
# following paragraphs are the reason, not a disclaimer.
#
# ── WHY IT EXISTS ────────────────────────────────────────────────────────────────────────────────
# This repo's dispatch fires cloud sessions into Linux containers, and its test corpus is written
# against BSD userland: 68 files under bin/ scripts/ tests/ reach for `date -v` or `stat -f %m`. On
# Linux every one of them dies at the first fixture with `date: invalid option -- 'v'` — measured on
# tests/cc-blockers.bats, 63 of 105 cases, all before any assertion ran. The consequence is not that
# a cloud session sees red; it is that it sees NOTHING, and then lands its work carrying a verified
# claim it could not actually make. That happened to the change this file was built alongside:
# 1f5bd304 ("green-starved — the alarm for trunk uncertified past its budget") landed with its own
# commit body stating "bats and BSD date(1)/stat(1) are absent in this container, so each body was
# mirrored 1:1 through a Linux harness" and "shellcheck is not installed here and was not run". The
# alarm was correct — but hand-mirroring a suite is a re-implementation of the thing under test, and
# the one defect it cannot detect is a mistake shared between the mirror and the original.
#
# ── WHAT A GREEN RUN UNDER THIS IS NOT ───────────────────────────────────────────────────────────
# It is not a macOS verdict, and it must never be reported as one. The shims translate the two
# syscall-adjacent utilities; they do not make the container Darwin. Anything the corpus reaches for
# that only exists on macOS is still absent, and the suite will say so — on the run this file was
# built for, exactly one case stayed red, `M8 POSITIVE CONTROL … sensors 5/5 readable`, because
# cc-blockers probes `launchctl` and Linux has none (4/5, launchctl:x). That residue is the honest
# shape of a shimmed run and it is why this prints a banner on every invocation: a shimmed green is
# EVIDENCE, of the kind that beats a hand-mirror, and it is still not the native gate. Cite it as
# "N/M under bsd-compat, <residue> platform-absent", never as a bare pass.
#
# Refusing beats approximating, everywhere below: both shims exit 64 on any adjustment or format
# they cannot translate exactly (lib/bsd-compat/{date,stat} carry the per-case reasoning). A shim
# that guesses turns a red suite green for a reason no one will ever look for.
#
# USAGE
#   scripts/bsd-compat.sh <command> [args…]      e.g. scripts/bsd-compat.sh bats tests/cc-blockers.bats
#   scripts/bsd-compat.sh --selftest             prove the translations against known-good answers
#   scripts/bsd-compat.sh --print-path           emit the shim dir, for callers assembling their own PATH
#
# Exit: the command's own status; 64 on usage; 70 if the shim dir is missing; --selftest 0/1.
set -uo pipefail

# Resolve the shim dir from THIS file's own location, fully symlink-resolved. Everything under
# ~/.claude/scripts is a per-file symlink into a checkout, so `dirname "$0"` is the live layer and
# not the repo — the shape scripts/self-path-lint.sh is a ratchet against. Walk the link chain to
# land in the checkout that actually carries lib/bsd-compat/.
self="$0"
while [ -L "$self" ]; do
  target="$(readlink "$self")"
  case "$target" in
    /*) self="$target" ;;
    *)  self="$(cd "$(dirname "$self")" && pwd -P)/$target" ;;
  esac
done
SCRIPT_DIR="$(cd "$(dirname "$self")" && pwd -P)"
SHIM_DIR="$SCRIPT_DIR/lib/bsd-compat"

die() { echo "bsd-compat: $*" >&2; exit 70; }

[ -d "$SHIM_DIR" ] || die "shim dir not found at $SHIM_DIR (expected beside this script)"
for s in date stat; do
  [ -x "$SHIM_DIR/$s" ] || die "$SHIM_DIR/$s missing or not executable"
done

# ── --selftest: the shims' own RED/GREEN controls ────────────────────────────────────────────────
# Each translation is checked against an answer computed WITHOUT the shim, so a shim that silently
# no-ops cannot pass. Refusal cases are checked too: a shim whose guard is broken is a shim that
# approximates, which is the failure mode the whole file is organised against.
selftest() {
  local fails=0 n=0
  check() { # <label> <expected> <actual>
    n=$((n + 1))
    if [ "$2" = "$3" ]; then
      printf '  ok   %s\n' "$1"
    else
      printf '  FAIL %s — expected %q, got %q\n' "$1" "$2" "$3"
      fails=$((fails + 1))
    fi
  }
  check_rc() { # <label> <expected rc> <actual rc>
    n=$((n + 1))
    if [ "$2" = "$3" ]; then
      printf '  ok   %s\n' "$1"
    else
      printf '  FAIL %s — expected rc %s, got %s\n' "$1" "$2" "$3"
      fails=$((fails + 1))
    fi
  }

  echo "bsd-compat --selftest"

  # date: a single adjustment, against GNU's own answer for the same offset.
  check "date -v-30H" \
    "$(/usr/bin/date -d 'now -30 hours' +%Y%m%d%H%M)" \
    "$("$SHIM_DIR/date" -v-30H +%Y%m%d%H%M)"

  check "date -u -v+47H (UTC flag passes through)" \
    "$(/usr/bin/date -u -d 'now +47 hours' +%Y-%m-%dT%H:%M:%SZ)" \
    "$("$SHIM_DIR/date" -u -v+47H +%Y-%m-%dT%H:%M:%SZ)"

  check "date -v-1M (minutes, not months)" \
    "$(/usr/bin/date -d 'now -1 minutes' +%Y%m%d%H%M)" \
    "$("$SHIM_DIR/date" -v-1M +%Y%m%d%H%M)"

  check "date -v-1m (months, not minutes)" \
    "$(/usr/bin/date -d 'now -1 months' +%Y%m)" \
    "$("$SHIM_DIR/date" -v-1m +%Y%m)"

  # THE COMPOSITION CONTROL. BSD applies adjustments left to right; a shim that re-anchored on `now`
  # per adjustment would answer -1H here and look right in every single-adjustment case above.
  check "date -v-1d -v-2H composes (not last-wins)" \
    "$(/usr/bin/date -d 'now -1 days -2 hours' +%Y%m%d%H)" \
    "$("$SHIM_DIR/date" -v-1d -v-2H +%Y%m%d%H)"

  # THE PASS-THROUGH CONTROL: with no -v at all the shim must be indistinguishable from date(1).
  check "date with no -v is plain date" \
    "$(/usr/bin/date -u +%Y-%m-%d)" \
    "$("$SHIM_DIR/date" -u +%Y-%m-%d)"

  # REFUSAL CONTROLS. Each of these silently mistranslated is a fixture that ages to `now`.
  "$SHIM_DIR/date" -v 12H +%H >/dev/null 2>&1; check_rc "date refuses an UNSIGNED adjustment" 64 "$?"
  "$SHIM_DIR/date" -v-3Q  +%H >/dev/null 2>&1; check_rc "date refuses an unknown unit"        64 "$?"
  "$SHIM_DIR/date" -v-xH  +%H >/dev/null 2>&1; check_rc "date refuses a non-numeric magnitude" 64 "$?"

  # stat: against GNU's own answer for the same file.
  local probe; probe="$(mktemp)"; printf 'abcde' > "$probe"
  check "stat -f %m" "$(/usr/bin/stat -c '%Y' "$probe")" "$("$SHIM_DIR/stat" -f %m "$probe")"
  check "stat -f %z" "$(/usr/bin/stat -c '%s' "$probe")" "$("$SHIM_DIR/stat" -f %z "$probe")"
  check "stat -f %i" "$(/usr/bin/stat -c '%i' "$probe")" "$("$SHIM_DIR/stat" -f %i "$probe")"
  check "stat with no -f is plain stat" \
    "$(/usr/bin/stat -c '%s' "$probe")" "$("$SHIM_DIR/stat" -c '%s' "$probe")"
  "$SHIM_DIR/stat" -f %Sm "$probe" >/dev/null 2>&1; check_rc "stat refuses %Sm (no exact GNU form)" 64 "$?"
  "$SHIM_DIR/stat" -f %Lp "$probe" >/dev/null 2>&1; check_rc "stat refuses %Lp (octal vs hex)"      64 "$?"
  rm -f "$probe"

  echo
  if [ "$fails" -eq 0 ]; then
    echo "bsd-compat --selftest: $n/$n OK"
    return 0
  fi
  echo "bsd-compat --selftest: $fails of $n FAILED"
  return 1
}

case "${1:-}" in
  --selftest)   selftest; exit $? ;;
  --print-path) echo "$SHIM_DIR"; exit 0 ;;
  ''|-h|--help)
    sed -n '/^# USAGE/,/^# Exit:/p' "$self" | sed 's/^# \{0,1\}//'
    exit 64
    ;;
esac

# A GREEN UNDER SHIMS IS NOT A NATIVE GREEN, and the one place that can guarantee the reader is told
# is here — stderr, before the command's own output, on every single run.
cat >&2 <<'BANNER'
┌─ bsd-compat: BSD date(1)/stat(1) SHIMMED over GNU userland ─────────────────────────────────────┐
│ This is NOT a macOS run. Only date -v and stat -f are translated; anything else macOS-only is    │
│ still absent and will fail on its own terms. Report results as "under bsd-compat", never as a    │
│ bare pass, and never as the native gate.                                                         │
└─────────────────────────────────────────────────────────────────────────────────────────────────┘
BANNER

PATH="$SHIM_DIR:$PATH" exec "$@"
