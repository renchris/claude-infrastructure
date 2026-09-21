#!/usr/bin/env bash
# rank-memory.sh — score the MEMORY.md index with Jev's `score` primitive. Run via `cc-jev rank`.
#
# WHY THIS EXISTS. The index is at a HARD cap: past 25,000 loader units or 200 lines the loader
# SILENTLY DROPS the newest entries, so every append is a decision about what to evict, taken today
# by `cc-memory-rotate` on structural proxies (age, size, citation counts) because nothing could
# read the ENTRIES THEMSELVES. That is the gap this fills: a semantic read of every indexed rule,
# ranked by how often it would actually change what an agent does.
#
# WHY JEV RATHER THAN A CLAUDE TURN. 146 bounded, independent, typed judgments with a thresholdable
# ordinal is exactly the shape §4 rank 3 identified and the shape `score` exists for — the one
# primitive the retired deference arm never used. It is ~146 calls, free on the Gateway until
# 2026-09-25 and about a cent after. A Claude pass over 146 topic files costs weekly quota that is
# strictly scarcer, and would return prose where this returns a sortable level.
#
# 🚨 WHAT THIS IS NOT. It RANKS; it never edits MEMORY.md, never deletes a topic file, never calls
# cc-memory-rotate. Eviction stays a human read of a ranked list, because a wrong demotion is
# invisible until the day the missing rule would have fired. Output is a JSONL and a summary.
#
# 🚨 IT SENDS MEMORY TOPIC-FILE CONTENT TO A THIRD PARTY. Bounded per file, our own engineering
# lessons only — never a transcript, the mailbox, or the msg corpus (§4's standing refusal). Gated
# on --yes, expressed on the command line so the consent is in shell history rather than in a
# prompt that a non-TTY channel cannot deliver (the failure this repo hit on 2026-09-21).
set -uo pipefail

_resolve_self() {
  local p="$1" d
  while [ -L "$p" ]; do d="$(cd -P "$(dirname "$p")" && pwd)"; p="$(readlink "$p")"
    case "$p" in /*) ;; *) p="$d/$p" ;; esac; done
  printf '%s' "$p"
}
SELF="$(_resolve_self "${BASH_SOURCE[0]}")"
ROOT="$(cd "$(dirname "$SELF")/../.." && pwd)"
# shellcheck source=/dev/null
. "$ROOT/hooks/lib/jev.sh"

MEM="${CC_JEV_MEM_DIR:-$HOME/.claude-secondary/projects/-Users-chrisren-Development-claude-infrastructure/memory}"
N=0; YES=0
while [ $# -gt 0 ]; do
  case "$1" in
    --yes) YES=1; shift ;;
    -n) N="${2:?-n needs a count}"; shift 2 ;;
    --mem) MEM="${2:?--mem needs a dir}"; shift 2 ;;
    -h|--help) printf 'usage: cc-jev rank [-n N] [--mem DIR] [--yes]\n'; exit 0 ;;
    *) printf 'usage: cc-jev rank [-n N] [--mem DIR] [--yes]\n' >&2; exit 2 ;;
  esac
done

jev_available || { printf 'not available — run: cc-jev status\n' >&2; exit 2; }
IDX="$MEM/MEMORY.md"
[ -f "$IDX" ] || { printf 'no index at %s\n' "$IDX" >&2; exit 3; }

# The population: index lines that name a topic file that EXISTS. A line whose target is missing is
# reported, never silently skipped — a broken pointer is itself a demotion candidate and the count
# must be visible or the denominator lies.
ROWS="$(mktemp)"; MISSING=0
grep -o '](\([^)]*\.md\))' "$IDX" | sed 's/](//;s/)//' | while read -r f; do
  [ -f "$MEM/$f" ] && printf '%s\n' "$f"
done > "$ROWS"
TOT=$(wc -l < "$ROWS" | tr -d ' ')
LINKED=$(grep -c '](.*\.md)' "$IDX" || true)
MISSING=$(( LINKED - TOT ))
[ "$TOT" -gt 0 ] || { printf 'REFUSING: 0 resolvable topic files — the ranking would be vacuous.\n' >&2; exit 3; }
[ "$N" -gt 0 ] && [ "$N" -lt "$TOT" ] && { head -"$N" "$ROWS" > "$ROWS.n"; mv "$ROWS.n" "$ROWS"; TOT="$N"; }

OUT="$HOME/.claude/autonomy/jev-rank-$(date -u +%Y%m%dT%H%M%SZ).jsonl"
# CREATE THE DIRECTORY, and fail loudly if that is impossible. Without this the appends below are
# silent no-ops whenever $HOME has no .claude/autonomy — which is EVERY hermetic test run, and any
# fresh machine. The counter still incremented, so the run printed "SCORED 2 of 2" over a file that
# was never written and a summary that read empty: a confident wrong answer, in the direction of
# success. Caught by a fixture, which is exactly the population a real run never covers.
mkdir -p "$(dirname "$OUT")" || { printf 'cannot create %s\n' "$(dirname "$OUT")" >&2; exit 3; }
: >> "$OUT" || { printf 'cannot write %s\n' "$OUT" >&2; exit 3; }
printf 'Index: %s\n' "$IDX"
printf 'Scoring %s indexed rule(s) with the Jev choice primitive' "$TOT"
[ "$MISSING" -gt 0 ] && printf ' (%s index line(s) point at a MISSING file — listed at the end)' "$MISSING"
printf '.\nEach sends ONE bounded topic-file excerpt to Vercel AI Gateway.\n'
printf 'Report -> %s\n' "$OUT"
printf 'PACING: the free tier allows ~4 calls before throttling, so this backs off exponentially.\n'
printf '        Budget roughly %s-%s minutes.\n\n' "$(( TOT / 6 ))" "$(( TOT / 2 ))"
if [ "$YES" -ne 1 ]; then
  printf 'Re-run with --yes to send. Nothing has been sent.\n'; exit 3
fi

CAP="${CC_JEV_RANK_CAP_B:-3000}"
done_n=0; skipped=0
while IFS= read -r f; do
  body="$(head -c "$CAP" "$MEM/$f" 2>/dev/null)"
  [ -n "$body" ] || { skipped=$((skipped+1)); continue; }
  spec="$(jq -n --arg s "$body" '{ state:$s, questions:{
    bite: { type:"choice",
      instructions:"How often would this rule change what an engineer or agent actually DOES on a future task in this codebase? Judge the RULE, not how well it is written.",
      criteria:{ "almost-never":"it restates something obvious, or is so specific to one past incident that it can never recur", "occasionally":"it applies to a narrow situation that does come up", "often":"it applies to a recurring class of work here", "nearly-always":"it would change behaviour on most tasks in this repo" } },
    superseded: { type:"boolean",
      instructions:"Does this read as OBSOLETE - describing a tool, path, version or state that has since been replaced, rather than a durable rule?",
      criteria:{ true:"it is pinned to a specific past incident, a since-changed tool, or a state that has been fixed", false:"it states a generalizable rule that survives its incident" } }
  }}')"
  out="$(printf '%s' "$spec" | jev_ask)" || true
  tries=0
  while [ "$(printf '%s' "$out" | jq -r '.reason // ""' 2>/dev/null)" = "rate-limited" ] \
        && [ "$tries" -lt "${CC_JEV_RANK_RETRIES:-5}" ]; do
    tries=$((tries+1)); wait_s=$(( ${CC_JEV_RANK_BACKOFF:-10} * tries ))
    printf '  … rate-limited, backing off %ss (retry %s/%s)\n' "$wait_s" "$tries" "${CC_JEV_RANK_RETRIES:-5}" >&2
    sleep "$wait_s"; out="$(printf '%s' "$spec" | jev_ask)" || true
  done
  sleep "${CC_JEV_RANK_GAP:-3}"
  # CHOICE, not SCORE, and that is a MEASURED choice rather than a stylistic one. `score` is
  # declared in the SDK types with exactly the shape our mock returns, and the identical round trip
  # is still rejected `invalid-response` while a boolean through the same path succeeds — so the
  # runtime schema is stricter than the published type and the primitive is not usable from here
  # today. `choice` over ORDERED keys carries the same ordinal signal and is the primitive 198 real
  # calls have already exercised. Ordering lives in rank_of() below, never in the model.
  lvl=$(printf '%s' "$out" | jq -r '.answers.bite.choice // empty' 2>/dev/null)
  sup=$(printf '%s' "$out" | jq -r '.answers.superseded.probability // empty' 2>/dev/null)
  if [ -z "$lvl" ]; then skipped=$((skipped+1)); continue; fi
  done_n=$((done_n+1))
  hook="$(grep -F "($f)" "$IDX" | head -1 | sed 's/^- //' | cut -c1-120)"
  jq -nc --arg f "$f" --arg lvl "$lvl" --arg sup "${sup:-}" --arg hook "$hook" \
     '{file:$f, level:$lvl, superseded:($sup|tonumber? // null), hook:$hook}' >> "$OUT"
  printf '.'
done < "$ROWS"
printf '\n\n'

printf 'SCORED %s of %s  (skipped %s)\n' "$done_n" "$TOT" "$skipped"
[ "$done_n" -gt 0 ] || { printf 'No verdicts — nothing to rank.\n'; exit 1; }
printf '\nLEVEL DISTRIBUTION (this is a RANKING, not a verdict on any one rule):\n'
jq -r '.level' "$OUT" | sort | uniq -c | sort -rn | sed 's/^/  /'
printf '\nDEMOTION CANDIDATES — lowest bite, highest obsolescence. READ THEM before evicting any:\n'
jq -r 'select(.level|test("almost-never|occasionally")) | "\(.level)\t\(.superseded // 0)\t\(.hook)"' "$OUT" \
  | sort -t"$(printf '\t')" -k1,1 -k2,2nr | head -25 | sed 's/^/  /'
printf '\nrows -> %s\n' "$OUT"
printf 'Nothing was edited. Eviction is a human read of the list above.\n'
rm -f "$ROWS"
