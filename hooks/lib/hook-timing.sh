# shellcheck shell=bash
# hook-timing.sh — per-hook start/end stamps for the UserPromptSubmit hooks (sourced; bash 3.2).
#
# WHY (docs/research/startup-hooks-2026-10-18/README.md §5 Wave 7; A9-beyond-startup.md F9 and its
# skeptic): UserPromptSubmit hooks leave 0 `hook_success` rows in the transcript, so the typed-prompt
# chain (p50 1.7 s, p90 4.8 s) cannot be attributed to any one of its seven hooks, and a hook the
# harness cancels leaves only the cancel. Per-hook attribution needs self-stamps first.
#
# THE CLOCK is a file's mtime (APFS keeps nanoseconds), the hooks/lib/startup-sentinel.sh idiom:
# /bin/bash 3.2 has no $EPOCHREALTIME and BSD date has no %N, and every clock fork costs ~3-8 ms at a
# load of 300 (measured 2026-10-19: date +3.3 ms, jq -n now +8.3 ms, perl HiRes +12 ms over a bare
# bash start). So the prompt path forks nothing:
#   ht_begin <hook> [event]   `printf > $D/<hook>.<pid>.s` — "<event> <EPOCHREALTIME or ->"; arms
#                             `trap 'ht_end $?' EXIT` (pass --no-trap as $3 when the hook owns its trap
#                             and calls ht_end itself)
#   ht_end <rc>               `printf > $D/<hook>.<pid>.e` — "<rc> <EPOCHREALTIME or -> <HT_SID or ->"
# One `mkdir -p` the first time the directory is missing; builtins otherwise. Under bash ≥ 5 the
# content carries $EPOCHREALTIME and the fold prefers it; under 3.2 the two mtimes are the stamps.
#
# THE FOLD (ht_fold, hooks/lib/hook-timing-fold.sh — a separate file so the seven prompt-path
# sources do not parse it: measured +1.28 ms → +0.75 ms per hook at load ~300) runs in session-beat.sh's
# DETACHED prompt worker, off the prompt path, and turns
# finished pairs into rows of ${CC_HOOK_TIMING_LEDGER:-$HOME/.claude/logs/hook-timing.jsonl}:
#   {"ts","hook","sid","disposition":"timed"|"killed","reason":"<event>","t0":<epoch s>,"ms":N,
#    "rc":N|null,"clock":"rt"|"mtime"}
# A `.s` whose process is gone with no `.e` is a hook that never reached its EXIT trap — killed by the
# harness (or crashed) — and folds as "killed" with the age it had reached. Each pair is claimed by
# renaming its `.s`, so two folders never write the same row.
# IDL-shaped rows, but NOT in idl.jsonl: bin/cc-audit reads a fixed tail of the IDL, and ~7 rows per
# prompt (+~30% of its volume on 2026-10-19) would shrink every other hook's audit window.
#
# Kill switch CC_HOOK_TIMING=off. Default OFF when BATS_TEST_FILENAME is set, so the many suites
# that run these hooks with the real $HOME never write stamps into the live ledger; the suite that
# tests this lib (tests/hook-timing.bats) sets it on.

ht_begin() {
  _HT_F=""
  local m="${CC_HOOK_TIMING:-}" d
  if [ -z "$m" ]; then m=on; [ -n "${BATS_TEST_FILENAME:-}" ] && m=off; fi
  [ "$m" = on ] || return 0
  case "${1:-}" in ''|*[!A-Za-z0-9_-]*) return 0 ;; esac
  d="${CC_HOOK_TIMING_DIR:-$HOME/.claude/state/hook-timing}"
  [ -d "$d" ] || mkdir -p "$d" 2>/dev/null || return 0
  _HT_F="$d/$1.$$"
  # "-" for an absent clock, never an empty field: the fold's `read` collapses empty whitespace
  # fields, which shifted the sid into the clock slot under bash 3.2.
  { printf '%s %s\n' "${2:-UserPromptSubmit}" "${EPOCHREALTIME:--}" > "$_HT_F.s"; } 2>/dev/null \
    || { _HT_F=""; return 0; }
  [ "${3:-}" = --no-trap ] || trap 'ht_end $?' EXIT
  return 0
}

ht_end() {
  [ -n "${_HT_F:-}" ] || return 0
  case "${HT_SID:-}" in *[!0-9A-Za-z_-]*) HT_SID="" ;; esac
  { printf '%s %s %s\n' "${1:-0}" "${EPOCHREALTIME:--}" "${HT_SID:--}" > "$_HT_F.e"; } 2>/dev/null
  _HT_F=""
  return 0
}
