#!/bin/bash
# shellcheck disable=SC2015  # the selftest's `[ test ] && okp || badp` reporter idiom is intentional —
# okp/badp always return 0 (printf + arithmetic), so SC2015's "C runs when A true but B fails" cannot occur.
#
# exit-deadline — F4 of the never-let-completion-go-silent bar (scripts/comms-safety-gate.sh). Event-adaptive
# wait/sweep deadlines.
#
# ── THE INCIDENT THAT IS THE SPEC ──────────────────────────────────────────────────────────────────────
# The W5 desk learned of a ship 50 min late — its L2 re-observe DID fire, it was just HOURLY-tuned. The fix
# is not a smaller constant; it is making the deadline an INPUT that TIGHTENS during EXIT SEQUENCES (when a
# completion is imminent and silence is most costly) and relaxes otherwise. This module is the single place
# that answers "are we in an exit sequence?" and resolves the effective deadline; the live wait-contract
# (L2) and reconciler sweep (L4) CALL it at ACTIVATION (C10) instead of hard-coding 3600. Build-vs-activation
# split, exactly like reap-guard: this is a standalone module + --selftest; the live machinery is never
# edited in place.
#
#   exit-deadline.sh resolve [--default <s>] [--exit <s>]   echo the effective deadline (seconds)
#   exit-deadline.sh active                                  exit 0 if in an exit sequence, else 1
#   exit-deadline.sh --selftest
#
# EXIT-SEQUENCE is active when EITHER CC_EXIT_SEQUENCE is truthy (1/true/yes/on) OR the flag file
# ${CC_EXIT_SEQUENCE_FLAG:-~/.claude/exit-sequence.flag} exists. A recipe TOUCHES the flag at exit-start and
# removes it at exit-end, so the tightening is scoped to the exit window.
#
# Defaults (overridable): normal = CC_DEFAULT_DEADLINE_S (3600) · exit = CC_EXIT_DEADLINE_S (900). A call
# site may pass its OWN (--default, --exit) pair (L2 wait and L4 sweep differ); the DETECTION is centralized
# here so every layer tightens on the same signal.
#
# Env: CC_EXIT_SEQUENCE, CC_EXIT_SEQUENCE_FLAG, CC_DEFAULT_DEADLINE_S, CC_EXIT_DEADLINE_S.
# bash 3.2-safe. Exit: 0 = ok (or, for `active`, in an exit sequence) · 1 = `active` and not · 2 = usage.
set -uo pipefail

FLAG_FILE="${CC_EXIT_SEQUENCE_FLAG:-$HOME/.claude/exit-sequence.flag}"
DEF_DEFAULT="${CC_DEFAULT_DEADLINE_S:-3600}"
DEF_EXIT="${CC_EXIT_DEADLINE_S:-900}"

usage() { sed -n '5,26p' "$0" | sed 's/^# \{0,1\}//'; }
die()   { echo "exit-deadline: $*" >&2; exit 2; }

is_exit_sequence() { # 0 = in an exit sequence, 1 = not
  case "${CC_EXIT_SEQUENCE:-}" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
  esac
  [ -f "$FLAG_FILE" ] && return 0
  return 1
}

cmd_resolve() {
  local d="$DEF_DEFAULT" e="$DEF_EXIT"
  while [ $# -gt 0 ]; do
    case "$1" in
      --default) d="${2:?--default needs seconds}"; shift 2 ;;
      --exit)    e="${2:?--exit needs seconds}"; shift 2 ;;
      *)         die "unknown resolve arg '$1'" ;;
    esac
  done
  case "$d$e" in *[!0-9]*) die "--default and --exit must be integer seconds" ;; esac
  if is_exit_sequence; then echo "$e"; else echo "$d"; fi
}

# ── selftest: SEE the deadline change with the exit flag ALONE. Every assertion TRAPS. ─────────────────
PASS=0; FAIL=0
okp()  { printf '  ok   %s\n' "$1"; PASS=$((PASS+1)); }
badp() { printf '  FAIL %s\n' "$1"; FAIL=$((FAIL+1)); }

selftest() {
  local d SELF r a b; d="$(mktemp -d "${TMPDIR:-/tmp}/exit-deadline-selftest.XXXXXX")" || die "mktemp"
  trap 'rm -rf "$d"' EXIT
  SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

  echo "exit-deadline --selftest — the deadline must be an INPUT, not a constant:"

  # (1) NO exit sequence (no env, no flag) → the 3600s default.
  r="$(env -u CC_EXIT_SEQUENCE CC_EXIT_SEQUENCE_FLAG="$d/none" "$SELF" resolve)"
  [ "$r" = 3600 ] && okp "no exit sequence → default 3600s" || badp "default was $r, wanted 3600"

  # (2) exit-sequence FLAG file present → tightened 900s.
  : > "$d/exit.flag"
  r="$(env -u CC_EXIT_SEQUENCE CC_EXIT_SEQUENCE_FLAG="$d/exit.flag" "$SELF" resolve)"
  [ "$r" = 900 ] && okp "exit-sequence flag file → tightened 900s" || badp "flagged was $r, wanted 900"

  # (3) exit-sequence ENV → tightened 900s (the programmatic trigger).
  r="$(CC_EXIT_SEQUENCE=1 CC_EXIT_SEQUENCE_FLAG="$d/none" "$SELF" resolve)"
  [ "$r" = 900 ] && okp "CC_EXIT_SEQUENCE=1 → tightened 900s" || badp "env-flagged was $r, wanted 900"

  # (4) DISCRIMINATION: the SAME resolver gives 3600 vs 900 by the exit flag ALONE — event-adaptive, not a
  #     constant (a hardcoded 3600 cannot tighten in the exit window — the W5 'hourly-tuned' bug).
  a="$(env -u CC_EXIT_SEQUENCE CC_EXIT_SEQUENCE_FLAG="$d/none" "$SELF" resolve)"
  b="$(CC_EXIT_SEQUENCE=on CC_EXIT_SEQUENCE_FLAG="$d/none" "$SELF" resolve)"
  [ "$a" = 3600 ] && [ "$b" = 900 ] && [ "$a" != "$b" ] \
    && okp "DISCRIMINATES 3600 (normal) vs 900 (exit) by the flag alone — the deadline is an INPUT" \
    || badp "no discrimination (normal=$a exit=$b)"

  # (5) per-layer pair: L4 sweep can pass its OWN (--default 1800 --exit 600); detection stays centralized.
  r="$(CC_EXIT_SEQUENCE=1 CC_EXIT_SEQUENCE_FLAG="$d/none" "$SELF" resolve --default 1800 --exit 600)"
  [ "$r" = 600 ] && okp "per-layer pair honored (--exit 600 under an exit sequence)" || badp "per-layer exit was $r, wanted 600"
  r="$(env -u CC_EXIT_SEQUENCE CC_EXIT_SEQUENCE_FLAG="$d/none" "$SELF" resolve --default 1800 --exit 600)"
  [ "$r" = 1800 ] && okp "per-layer pair honored (--default 1800, no exit sequence)" || badp "per-layer default was $r, wanted 1800"

  # (6) `active` exit-code contract (for a recipe's `if exit-deadline active; then …`).
  env -u CC_EXIT_SEQUENCE CC_EXIT_SEQUENCE_FLAG="$d/none" "$SELF" active >/dev/null 2>&1
  local ra=$?; CC_EXIT_SEQUENCE=1 CC_EXIT_SEQUENCE_FLAG="$d/none" "$SELF" active >/dev/null 2>&1; local rb=$?
  [ "$ra" = 1 ] && [ "$rb" = 0 ] && okp "active: exit 1 when normal, exit 0 in an exit sequence" || badp "active exit-codes wrong (normal=$ra exit=$rb)"

  echo "exit-deadline --selftest: $PASS passed, $FAIL failed"
  [ "$FAIL" -eq 0 ] || exit 1
  echo "exit-deadline --selftest: GREEN — exit-sequence tightens 3600→900 (flag OR env); per-layer pairs honored; the deadline is an INPUT."
  exit 0
}

case "${1:-}" in
  resolve)      shift; cmd_resolve "$@" ;;
  active)       if is_exit_sequence; then echo "exit-sequence ACTIVE"; exit 0; else echo "normal (no exit sequence)"; exit 1; fi ;;
  --selftest)   selftest ;;
  -h|--help|"") usage; exit 0 ;;
  *)            die "unknown command '$1' (use resolve | active | --selftest)" ;;
esac
