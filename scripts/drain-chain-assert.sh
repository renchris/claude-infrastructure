#!/usr/bin/env bash
# drain-chain-assert.sh — IS THE 24/7 DRAIN CHAIN ALIVE? (docs/plans/BACKLOG_DRAIN_24_7.md §6)
#
# ── THE DEFECT THIS CLOSES, AND IT IS THE PLAN'S OWN ROOT CAUSE ─────────────────────────────────
# BACKLOG_DRAIN_24_7 §1.2, measured: the local drain ran NINE recycles (2026-08-13T03:56Z →
# 2026-08-16T06:45Z), recycle #9's goal cleared on an effort-scoped condition, and **no recycle #10
# fired**. Nothing chained effort N's clear into effort N+1's fire, and — the part this file is
# about — *nothing noticed*. The chain stopped at 06:45Z and the only instrument that ever reported
# it was the operator, hours later, reading a "drained to zero" close that was per-effort and blind
# to its own blocked tail (§1.1). A 24/7 pipeline whose death is detected by a human is not 24/7;
# it is a pipeline plus a standing obligation to watch it.
#
# §6 states the invariant this script is:
#
#     The chain is alive ⟺ a fire-drain-recycle-N brief younger than 24h exists
#                        OR a drain session holds a live lease
#                        — checked by autonomy-sweep; a dead chain files ONE condition-keyed row
#                        (`local-drain-chain-dead`), never a duplicate storm.
#
# It was written as an invariant and implemented by nothing: `fire-drain-recycle` appeared in the
# plan and in NO script, test or plist on trunk. That is this repo's most-rediscovered defect — a
# conclusion that never reached an enforcing store — and filing it as prose inside the plan that
# diagnoses it would have been the same mistake one level up.
#
# ── WHY IT FILES RATHER THAN PRINTS, AND WHY THE ROW IS CONDITION-KEYED ─────────────────────────
# Same reasoning as backlog-grouping-sweep.sh, whose shape this deliberately copies: a printed
# warning dies with the terminal that showed it, and the drain chain dies UNATTENDED by definition
# — at 06:45Z with nobody watching is exactly the case. `--condition local-drain-chain-dead` folds
# every later filing onto ONE row (cc-backlog's dedupe + cmd_add's update arm keeps its title
# current), so a chain that stays dead for a week is one standing row and not 2,016 of them. A
# detector for backlog inflow that mints a row per 300 s tick would be funny once and then be the
# largest single generator in the store.
#
# ── THE ROW CARRIES ITS OWN RETRACTION ─────────────────────────────────────────────────────────
# `--assert` has exactly the polarity cc-premise's falsifier contract wants: rc 1 while the chain
# is dead, rc 0 the moment a recycle fires or a worker takes a lease. So the row retires itself
# when the condition clears, with no human in the loop — the difference between an alarm with a
# consumer and an alarm with a pager.
#
# ── THE THREE FAIL-OPEN GUARDS, EACH ONE LOAD-BEARING ──────────────────────────────────────────
#   1. NO STORE / NO TOOL / UNREADABLE FOLD ⇒ alive:skipped. "I could not ask" must never render as
#      "the answer was no" (backlog-grouping-sweep.sh's own lesson). A detector that convicts on an
#      unreadable store files a row about the drain when the actual fault is jq.
#   2. ZERO LIVE ROWS ⇒ alive:drained. THIS IS THE SUCCESS STATE, not a defect: §6's own terminal
#      condition is "at true zero live rows, write the chain-complete entry". A chain with nothing
#      to drain is correctly stopped, and a detector that fired there would file its first row on
#      the day the program succeeded and then hold it open forever (memory:
#      cap-whose-population-is-empty — the same trap that left backlog-ratchet.sh red on every run
#      it had ever made, against a 100% high-water its population could not reach).
#   3. ANY LIVE CLAIM COUNTS, whoever holds it. §6 says "a drain session holds a live lease" and
#      this does not try to prove the holder is *the* drain session: `by` is a worker id, the two
#      lanes fire under different ones, and a Lane A cloud worker draining a row is the chain doing
#      its job as much as Lane B is. The question the invariant asks is "is anything draining", and
#      on an ambiguous read the alarm abstains rather than convicts.
#
# LEASE FRESHNESS IS `lastTs`, WHICH IS AN OVER-READ AND DELIBERATELY SO. A claimed row's lastTs is
# normally its claim record, but a later non-venue record (a `link`, say) moves it — so a stale
# claim can read fresh. That error only ever runs toward "alive", i.e. toward NOT filing, which is
# the direction an alarm may be wrong in. The precise claim clock lives in cc-backlog's reap fold
# and is not exposed by `list --json`; reproducing it here would be a second state model of the
# same store, which is how sibling auditors drift (memory: sibling-auditors-must-share-the-state-
# model). CC_BACKLOG_STALE_CLAIM_S is read from the SAME env `cc-backlog reap` reads, so the TTL
# cannot fork.
#
# Usage:
#   drain-chain-assert.sh            report the verdict; SILENT when the chain is alive
#   drain-chain-assert.sh --assert   exit 1 when the chain is dead (the falsifier / a gate)
#   drain-chain-assert.sh --file     file/update ONE condition-keyed row when dead
#   drain-chain-assert.sh --json     the verdict as one JSON object (machine consumers)
# Env:
#   CC_DRAIN_BRIEF_GLOB       default "$TMPDIR-ish/fire-drain-recycle*.txt" — §4.1's brief path
#   CC_DRAIN_CHAIN_MAX_AGE_S  default 86400 (§6's "younger than 24h")
#   CC_BACKLOG_STALE_CLAIM_S  default 5400  — SHARED with `cc-backlog reap`, never re-defaulted here
#   CC_BACKLOG_BIN · CC_DRAIN_NOW (test clock)
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$HERE")"
BACKLOG_BIN="${CC_BACKLOG_BIN:-$REPO/bin/cc-backlog}"
BRIEF_GLOB="${CC_DRAIN_BRIEF_GLOB:-/tmp/fire-drain-recycle*.txt}"
MAX_AGE="${CC_DRAIN_CHAIN_MAX_AGE_S:-86400}"
STALE_CLAIM="${CC_BACKLOG_STALE_CLAIM_S:-5400}"
NOW="${CC_DRAIN_NOW:-$(date +%s)}"
MODE="report"

while [ $# -gt 0 ]; do
  case "$1" in
    --assert) MODE="assert"; shift ;;
    --file)   MODE="file";   shift ;;
    --json)   MODE="json";   shift ;;
    --help|-h) sed -n '2,/^set -uo/p' "$0" | sed 's/^# \{0,1\}//; /^set -uo/d'; exit 0 ;;
    *) printf 'drain-chain-assert: unknown arg %s\n' "$1" >&2; exit 2 ;;
  esac
done

# BSD-first mtime with a GNU fallback whose BSD attempt is CAPTURED AND VALIDATED, never let
# through — the exact shape landed in bin/cc-memory-rotate (4d7bc86d) after this idiom's naive form
# made that rotor a silent no-op on every Linux host. `stat -f` means "format" on BSD and
# "--file-system" on GNU, and GNU takes no format operand: it exits 1, so a bare `||` fallback does
# fire, but it ALSO prints a filesystem block ("File: …", "Block size: …") to STDOUT that
# `2>/dev/null` does not touch. Concatenated with the GNU answer that yields multiline junk, and
# here it would silently drop every brief — the detector would report a dead chain on a box that
# was draining fine, which is the one direction this alarm may not be wrong in.
_mtime() {
  local v
  v=$(stat -f %m -- "$1" 2>/dev/null) || v=""
  case "$v" in *[!0-9]*|'') v="" ;; esac
  if [ -n "$v" ]; then printf '%s' "$v"; return 0; fi
  stat -c %Y -- "$1" 2>/dev/null || echo ""
}

# VERDICT + WHY are ONE pair computed once and rendered by every arm, so the number a gate refuses
# on, the number a row is filed with and the number a human reads are the same read of the same
# store. Two reads would be two populations five minutes apart.
VERDICT="alive"; WHY="skipped"; LIVE=0; BRIEF_AGE=-1; BRIEF=""; LEASES=0

emit() { # render + exit, per mode. Called exactly once.
  case "$MODE" in
    json)
      jq -cn --arg v "$VERDICT" --arg w "$WHY" --arg b "$BRIEF" \
             --argjson l "$LIVE" --argjson a "$BRIEF_AGE" --argjson c "$LEASES" \
        '{verdict:$v, why:$w, live_rows:$l, brief:(if $b=="" then null else $b end),
          brief_age_s:(if $a < 0 then null else $a end), live_leases:$c,
          note:"verdict alive|dead. why: fresh-brief = a recycle brief younger than CC_DRAIN_CHAIN_MAX_AGE_S exists; live-lease = a non-done row is claimed inside CC_BACKLOG_STALE_CLAIM_S; drained = zero live rows, which is the SUCCESS state and never files; skipped/read-failed = could not ask, which is never a conviction. dead means the pile is non-empty and NOTHING is working it."}'
      exit 0 ;;
    assert)
      [ "$VERDICT" = dead ] || exit 0
      printf 'drain-chain-assert: %s\n' "$TITLE" >&2; exit 1 ;;
    report)
      if [ "$VERDICT" = dead ]; then printf 'drain-chain-assert: %s\n' "$TITLE"
      else printf 'drain-chain-assert: chain ALIVE (%s) · %s live row(s)%s\n' "$WHY" "$LIVE" \
             "$([ -n "$BRIEF" ] && printf ' · newest brief %ss old' "$BRIEF_AGE")"; fi
      exit 0 ;;
    file)
      [ "$VERDICT" = dead ] || exit 0
      [ -x "$BACKLOG_BIN" ] || { printf 'no cc-backlog at %s (fail-open)\n' "$BACKLOG_BIN" >&2; exit 0; }
      # `--falsifier` reaches a row only while CREATING it (cmd_add's update arm is deliberately a
      # no-op on a known id), so this attaches once, at first filing; `cc-backlog falsify` is the
      # verb for correcting it later. The TITLE, by contrast, IS kept current by the update arm —
      # which is why the live numbers belong there and not in the condition key.
      "$BACKLOG_BIN" add --project claude-infrastructure \
        --condition local-drain-chain-dead \
        --title "$TITLE" \
        --source drain-chain-assert \
        --falsifier "bash $HERE/drain-chain-assert.sh --assert" \
        --dod-ref "origin/main:docs/plans/BACKLOG_DRAIN_24_7.md" >/dev/null 2>&1 \
        || { printf 'drain-chain-assert: could not file the escalation row\n' >&2; exit 0; }
      exit 0 ;;
  esac
}

# TITLE is referenced by emit() in every arm, so it is defined before the first possible emit.
# Re-assigned once the live figures are known.
TITLE="the 24/7 backlog drain chain is not running"

# ── guard 1: can we ask at all? ────────────────────────────────────────────────────────────────
command -v jq >/dev/null 2>&1 || { WHY="skipped"; emit; }
[ -x "$BACKLOG_BIN" ]         || { WHY="skipped"; emit; }

ROWS="$("$BACKLOG_BIN" list --open --json 2>/dev/null)" || ROWS=""
printf '%s' "$ROWS" | jq -e 'type=="array"' >/dev/null 2>&1 || { WHY="read-failed"; emit; }

LIVE="$(printf '%s' "$ROWS" | jq 'length')"
case "$LIVE" in ''|*[!0-9]*) WHY="read-failed"; LIVE=0; emit ;; esac

# ── guard 2: an empty pile is the SUCCESS state, and success must not file a row ───────────────
[ "$LIVE" -gt 0 ] || { WHY="drained"; emit; }

# ── disjunct A: a fire-drain-recycle-N brief younger than MAX_AGE (§4.1's path) ────────────────
# Newest match wins. The glob is unquoted ON PURPOSE — that is the expansion — and `nullglob` keeps
# a no-match from handing the literal pattern to stat as a filename.
shopt -s nullglob
for _f in $BRIEF_GLOB; do
  [ -f "$_f" ] || continue
  _m="$(_mtime "$_f")"
  case "${_m:-}" in ''|*[!0-9]*) continue ;; esac
  _age=$(( NOW - _m ))
  [ "$_age" -lt 0 ] && _age=0          # a clock skew is not a fresh brief, but it is not -1 either
  if [ "$BRIEF_AGE" -lt 0 ] || [ "$_age" -lt "$BRIEF_AGE" ]; then BRIEF_AGE="$_age"; BRIEF="$_f"; fi
done
shopt -u nullglob

if [ "$BRIEF_AGE" -ge 0 ] && [ "$BRIEF_AGE" -lt "$MAX_AGE" ]; then WHY="fresh-brief"; emit; fi

# ── disjunct B: somebody holds a live lease ────────────────────────────────────────────────────
# `lastTs` is ISO-8601 from the fold; `fromdateiso8601` in jq, and a row whose stamp will not parse
# is counted as NOT a live lease — it cannot prove aliveness, and disjunct B is the arm that has to
# PROVE something for the alarm to stay silent.
LEASES="$(printf '%s' "$ROWS" | jq --argjson now "$NOW" --argjson ttl "$STALE_CLAIM" '
  [ .[]
    | select(.status == "claimed")
    | select( ((.lastTs // "") | if . == "" then null else (try fromdateiso8601 catch null) end)
              as $t | $t != null and ($now - $t) < $ttl ) ] | length' 2>/dev/null)"
case "${LEASES:-}" in ''|*[!0-9]*) LEASES=0 ;; esac
if [ "$LEASES" -gt 0 ]; then WHY="live-lease"; emit; fi

# ── nothing proved aliveness: the pile is non-empty and nothing is working it ──────────────────
VERDICT="dead"; WHY="no-brief-no-lease"
TITLE="$(printf 'the 24/7 backlog drain chain is DEAD — %s live row(s) and nothing is working them: no fire-drain-recycle brief inside %ss (newest: %s) and 0 live leases inside %ss. Restart it with the Lane B recycle-fire template in docs/plans/BACKLOG_DRAIN_24_7.md §4.1' \
  "$LIVE" "$MAX_AGE" \
  "$([ "$BRIEF_AGE" -ge 0 ] && printf '%ss old' "$BRIEF_AGE" || printf 'none')" \
  "$STALE_CLAIM")"
emit
