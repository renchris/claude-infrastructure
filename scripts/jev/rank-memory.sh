#!/usr/bin/env bash
# rank-memory.sh — score the MEMORY.md index with Jev's `score` primitive. Run via `cc-jev rank`.
#
# WHY THIS EXISTS. The index is at a HARD cap: past 25,000 loader units or 200 lines the loader
# SILENTLY DROPS the newest entries, so every append is a decision about what to evict, taken today
# by `cc-memory-rotate` on structural proxies (age, size, citation counts) because nothing could
# read the ENTRIES THEMSELVES. That is the gap this fills: a semantic read of every indexed rule,
# ranked by how often it would actually change what an agent does.
#
# 🚨 THE FIRST REAL RUN RANKED NOTHING, AND THAT IS WHY THERE ARE NOW THREE QUESTIONS.
# 140 rules scored, 118 of them (84%) `often`, `superseded` p90 0.39 with 2 rows above 0.70. Every
# verdict was defensible and the ORDERING was worthless: a question that returns one answer for 84%
# of a population has not ranked it. That is Addendum 4's lesson in this script's own shape — the
# deference arm died of a property of its POPULATION, not of the model, and nobody saw it until the
# answers were crosstabbed. So `breadth` was added BESIDE `bite` rather than replacing it (a swap
# would trade one unvalidated rubric for another), and the run now reports the max-bucket share of
# every question, so ONE pass says whether the new one discriminates. `--report FILE.jsonl` re-reads
# any past run and prints the same section for free, which is how this was checked against the real
# 140 rows without spending a call.
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
N=0; YES=0; REPORT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --yes) YES=1; shift ;;
    --report) REPORT="${2:?--report needs a .jsonl from a previous run}"; shift 2 ;;
    -n) N="${2:?-n needs a count}"; shift 2 ;;
    --mem) MEM="${2:?--mem needs a dir}"; shift 2 ;;
    -h|--help) printf 'usage: cc-jev rank [-n N] [--mem DIR] [--yes] [--report FILE.jsonl]\n'; exit 0 ;;
    *) printf 'usage: cc-jev rank [-n N] [--mem DIR] [--yes] [--report FILE.jsonl]\n' >&2; exit 2 ;;
  esac
done

emit_report() {  # reads globals OUT (rows) and done_n (denominator)
# ── rank_order — THE ONLY PLACE THE ORDINAL LIVES ────────────────────────────────────────────
# The model returns an unordered key; the ordering is OURS. Keeping it here rather than in the
# prompt means it can be read, tested and changed without spending a single call, and it is what
# `choice` buys us over the unusable `score`.
rank_order() {
  case "$1" in
    bite)    printf 'almost-never occasionally often nearly-always' ;;
    breadth) printf 'one-tool one-domain cross-domain universal' ;;
    *)       return 1 ;;
  esac
}
_ord_json() { local k i=0; printf '{'; for k in $(rank_order "$1"); do
  [ "$i" -gt 0 ] && printf ','; printf '"%s":%d' "$k" "$i"; i=$((i+1)); done; printf '}'; }

# ── RUBRIC DISCRIMINATION ────────────────────────────────────────────────────────────────────
# 🚨 THIS SECTION IS THE POINT OF THE RUN, AND IT EXISTS BECAUSE OF A MEASURED FAILURE ONE LEVEL UP.
# The deference arm died not because Jev judged badly but because its gate's two halves selected
# DISJOINT sets on real data — a property of the POPULATION, invisible until somebody crosstabbed
# it (docs/research/jev-at-cost-api-2026-09-18.md Addendum 4). The first real run of THIS ranker
# has the same disease in its own shape: 118 of 140 rules came back `often`, and `superseded` had
# a p90 of 0.39 with 2 rows above 0.70. Every individual verdict was defensible and the RANKING
# was worthless, because a question returning one answer for 84% of a population has not ranked it.
# So the run now reports its own discriminating power. A near-constant question is named as such
# HERE, in the output, instead of being discovered by hand a week later.
_maxshare() {  # $1=field → "<label> <count> <pct>"; empty when no row carries the field
  jq -r --arg f "$1" 'select(.[$f]!=null)|.[$f]' "$OUT" | sort | uniq -c | sort -rn | head -1 \
    | awk -v n="$done_n" 'NF{printf "%s %d %d", $2, $1, int($1*100/n + 0.5)}'
}
FLAT="${CC_JEV_RANK_FLAT_PCT:-80}"
# QUESTION NAME -> JSONL FIELD, and they are NOT the same string. `bite`'s answer is stored as
# `level`, which predates this section; reading `.bite` returned null for every row and the report
# said "no answers — the model returned none" over 5 perfectly good verdicts. A confident wrong
# answer in the safe-looking direction, and the only reason it was caught is that the section was
# RUN rather than reviewed. The pairs are written out here so the mismatch cannot recur silently.
_field_of() { case "$1" in bite) printf 'level' ;; *) printf '%s' "$1" ;; esac; }
printf '\nRUBRIC DISCRIMINATION — did each question separate THIS population?\n'
printf 'A question whose answers pile into one bucket ranked nothing, however sound each verdict was.\n'
for q in breadth bite; do
  read -r _lab _cnt _pct <<<"$(_maxshare "$(_field_of "$q")")"
  # TWO DIFFERENT NOTHINGS, and they demand opposite reactions: a question the run never ASKED
  # (an older JSONL, read back with --report) versus one it asked and the model never answered.
  # Collapsing them would report a pre-breadth run as a model failure — the emptiness-vs-absence
  # trap this repo already has a lesson about (docs/lessons/empty-vs-no-surface.md).
  if [ -z "${_pct:-}" ]; then
    if [ "$(jq -r --arg f "$(_field_of "$q")" 'has($f)' "$OUT" | sort -u | tr -d '\n')" = "false" ]; then
      printf '  %-11s (not asked in this run — these rows predate the question)\n' "$q"
    else
      printf '  %-11s (asked, but the model returned no answer on any row)\n' "$q"
    fi
    continue
  fi
  if [ "$_pct" -ge "$FLAT" ]; then
    printf '  %-11s %s%% in [%s] (%s/%s)   <- NEAR-CONSTANT: carried almost no information\n' "$q" "$_pct" "$_lab" "$_cnt" "$done_n"
  else
    printf '  %-11s %s%% in [%s] (%s/%s)   <- discriminates\n' "$q" "$_pct" "$_lab" "$_cnt" "$done_n"
  fi
done
# `superseded` is a boolean, so its analogue of a max bucket is its SPREAD. A posterior whose whole
# mass sits below the gate separates nothing either, and reporting only a median hides exactly that.
# `superseded` is a boolean, so it gets the SAME max-bucket test over coarse bands rather than a
# bespoke one. The first version asked only "how many are above 0.70" and therefore called a run
# where all five answers were an IDENTICAL 0.99 "discriminating" — a one-sided test cannot see a
# distribution pinned at the top, which is the same blindness in the mirror. Bands, then one rule.
SUP_HI=$(jq -r 'select(.superseded!=null and .superseded>=0.70)|.file' "$OUT" | wc -l | tr -d ' ')
SUP_Q=$(jq -r 'select(.superseded!=null)|.superseded' "$OUT" | sort -n \
        | awk '{a[NR]=$1} END{if(NR)printf "p50 %.2f / p90 %.2f", a[int(NR*.5)+1], a[int(NR*.9)+1]}')
read -r _slab _scnt _spct <<<"$(jq -r 'select(.superseded!=null)|.superseded
                | if . >= 0.70 then "hi" elif . >= 0.40 then "mid" else "lo" end' "$OUT" \
         | sort | uniq -c | sort -rn | head -1 \
         | awk -v n="$done_n" 'NF{printf "%s %d %d", $2, $1, int($1*100/n + 0.5)}')"
if [ -n "$SUP_Q" ] && [ -n "${_spct:-}" ]; then
  if [ "$_spct" -ge "$FLAT" ]; then
    printf '  %-11s %s%% in band [%s] · %s · %s of %s above 0.70   <- NEAR-CONSTANT: carried almost no information\n' \
           superseded "$_spct" "$_slab" "$SUP_Q" "$SUP_HI" "$done_n"
  else
    printf '  %-11s %s%% in band [%s] · %s · %s of %s above 0.70   <- discriminates\n' \
           superseded "$_spct" "$_slab" "$SUP_Q" "$SUP_HI" "$done_n"
  fi
fi

printf '\nDISTRIBUTIONS (this is a RANKING, not a verdict on any one rule):\n'
for q in breadth bite; do
  _d=$(jq -r --arg f "$(_field_of "$q")" 'select(.[$f]!=null)|.[$f]' "$OUT" | sort | uniq -c | sort -rn)
  [ -n "$_d" ] || continue      # an empty header under a question nobody asked is noise, not data
  printf '  %s:\n' "$q"; printf '%s\n' "$_d" | sed 's/^/    /'
done

# ── DEMOTION CANDIDATES — narrowest scope first, then lowest bite ────────────────────────────
# WHY BREADTH LEADS THE SORT, AND IT IS AN ARGUMENT ABOUT THE INDEX RATHER THAN ABOUT THE RULES.
# MEMORY.md is the always-loaded surface a session scans BEFORE it knows what it is looking for;
# the topic file is what it opens once it is already IN the situation. A one-tool rule is served
# by being FINDABLE — a grep away in docs/lessons/ — because you will be holding that tool at the
# moment you need it. A cross-domain rule has to be RESIDENT, because nothing about the task will
# tell you to go looking for it. `bite` asks how OFTEN a rule fires, which on a corpus of lessons
# that already survived a rotation is near-constant by construction; breadth asks how WIDE its
# trigger is, which is the axis a scan surface is actually selecting on.
printf '\nDEMOTION CANDIDATES — narrowest scope first, then lowest bite. READ THEM before evicting any:\n'
jq -r --argjson bo "$(_ord_json bite)" --argjson ro "$(_ord_json breadth)" '
  select(.breadth!=null or .level!=null)
  | [ ($ro[.breadth // ""] // 99), ($bo[.level // ""] // 99),
      (.breadth // "-"), (.level // "-"), (.superseded // 0), .hook ]
  | @tsv' "$OUT" \
  | sort -t"$(printf '\t')" -k1,1n -k2,2n -k5,5nr | head -25 | cut -f3- | sed 's/^/  /'

# ── DID THE NEW QUESTION CHANGE ANYTHING? ────────────────────────────────────────────────────
# ONE RUN TESTS THE FIX, instead of swapping one unvalidated rubric for another. If both numbers
# below are 0, `breadth` reproduced `bite` exactly and bought nothing — a real outcome, and one
# that has to be visible in the run rather than inferred from the JSONL a week later.
NEWONLY=$(jq -r 'select((.breadth=="one-tool") and (((.level//"")|test("almost-never|occasionally"))|not))|.file' "$OUT" | wc -l | tr -d ' ')
OLDONLY=$(jq -r 'select(((.level//"")|test("almost-never|occasionally")) and (.breadth!=null) and (.breadth!="one-tool"))|.file' "$OUT" | wc -l | tr -d ' ')
printf '\nDISAGREEMENT with the old bite-only rule: %s row(s) breadth demotes that bite kept; %s the reverse.\n' "$NEWONLY" "$OLDONLY"
if [ "$NEWONLY" = 0 ] && [ "$OLDONLY" = 0 ]; then
  printf '  Both zero — breadth reproduced bite on this population and added nothing. Say so; do not keep it.\n'
fi

printf '\nrows -> %s\n' "$OUT"
printf 'Nothing was edited. Eviction is a human read of the list above.\n'
}


# ── --report: RE-READ A PAST RUN, SPENDING NOTHING ───────────────────────────────────────────
# It sits HERE, immediately below the function it calls and ABOVE every network check, for two
# reasons. (1) Position: a dispatch placed after the run loop would be below its own helper for
# the live path and unreachable before it — the helper-position trap this repo has a standing rule
# about. (2) Scope: re-reading rows off disk needs no key, no route and no plan, so gating it
# behind jev_available would refuse a purely local read whenever the vendor is down.
# It is also how the discrimination report gets validated on REAL data: the 140-row run of
# 2026-09-21 is on disk, its flatness is known, and checking the report against it costs no calls.
if [ -n "$REPORT" ]; then
  [ -s "$REPORT" ] || { printf 'no rows at %s\n' "$REPORT" >&2; exit 3; }
  OUT="$REPORT"; done_n=$(wc -l < "$REPORT" | tr -d ' ')
  printf 'Re-reading %s row(s) from a PREVIOUS run. No call is made.\n' "$done_n"
  printf 'Rows: %s\n' "$REPORT"
  emit_report
  exit 0
fi

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
printf 'Scoring %s indexed rule(s) on breadth + bite (choice) and superseded (boolean)' "$TOT"
[ "$MISSING" -gt 0 ] && printf ' (%s index line(s) point at a MISSING file — listed at the end)' "$MISSING"
printf '.\nEach sends ONE bounded topic-file excerpt to Vercel AI Gateway.\n'
printf 'Report -> %s\n' "$OUT"
printf 'PACING: the free tier allows ~4 calls before throttling, so this backs off exponentially.\n'
printf '        Budget roughly %s-%s minutes.\n\n' "$(( TOT / 6 ))" "$(( TOT / 2 ))"
if [ "$YES" -ne 1 ]; then
  printf 'Re-run with --yes to send. Nothing has been sent.\n'; exit 3
fi

# ── PREFLIGHT: ONE CALL, BEFORE COMMITTING 146 ──────────────────────────────────────────────
# THIS EXISTS BECAUSE ITS ABSENCE COST A RUN. The first version went straight into the loop with
# ZDR at its default (ON), every call 403'd, `lvl` came back empty, and each one incremented
# `skipped` SILENTLY. It would have ground through all 146 over ~70 minutes and reported
# "SCORED 0 of 146" — a confident, well-formatted verdict over a path that never worked, and
# indistinguishable at a glance from "Jev had no opinion about any of them".
#
# Two guards, cheapest first. The static one names the known blocker; the probe catches everything
# else (dead key, revoked allowlist, gateway down, model renamed) by ASKING rather than assuming.
if [ "${CC_JEV_ZDR:-1}" != 0 ]; then
  cat <<EOF
✗ REFUSING before the first call. ZDR is ON and it is Pro/Enterprise-only, so on this plan every
  one of the $TOT calls returns HTTP 403 and this run would score exactly nothing.

  To send under STANDARD retention (bounded topic-file excerpts — our own engineering lessons,
  never a transcript, the mailbox, or the msg corpus):

      CC_JEV_ZDR=0 cc-jev rank --yes

  Nothing has been sent.
EOF
  exit 4
fi

printf 'Preflight: one call before committing to %s...\n' "$TOT"
_pf="$(jq -n '{state:"ok", questions:{p:{type:"boolean",instructions:"Is this text non-empty?"}}}' | jev_ask)" || true
if [ -z "$(printf '%s' "$_pf" | jq -r '.answers.p.probability // empty' 2>/dev/null)" ]; then
  printf '✗ REFUSING: the preflight call produced no verdict (reason: %s).\n' "$(jev_reason "$_pf")" >&2
  printf '  Scoring %s rules would have taken ~%s minutes and reported 0 of %s over a dead path.\n' \
         "$TOT" "$(( TOT / 6 ))" "$TOT" >&2
  printf '  Nothing has been sent. Diagnose with: cc-jev status\n' >&2
  exit 4
fi
printf 'Preflight OK — the route answers. Proceeding.\n\n'

CAP="${CC_JEV_RANK_CAP_B:-3000}"
done_n=0; skipped=0; consec=0
while IFS= read -r f; do
  body="$(head -c "$CAP" "$MEM/$f" 2>/dev/null)"
  [ -n "$body" ] || { skipped=$((skipped+1)); continue; }
  spec="$(jq -n --arg s "$body" '{ state:$s, questions:{
    breadth: { type:"choice",
      instructions:"How WIDE is the set of situations in which an engineer would need this rule? Judge the rule'"'"'s SCOPE, not its importance and not how often it fires - a rule can be critical and still be narrow.",
      criteria:{ "one-tool":"it is about the behaviour of one specific command, flag, file or API - you would only ever need it while using that exact thing", "one-domain":"it generalises across a family of tools or one subsystem - shell scripting, git, the test harness, a scheduler", "cross-domain":"it is about a failure of reasoning or measurement that recurs regardless of which tool is involved", "universal":"it would change how you approach any investigation at all, before you know what the subject is" } },
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
  # CHOICE, not SCORE. 🚨 CORRECTED 2026-09-21 — the reason this comment used to give was FALSE,
  # and it was false in the most expensive way: it named the VENDOR for a defect in our own fixture.
  # It read "`score` is declared in the SDK types with exactly the shape our mock returns, and the
  # identical round trip is still rejected invalid-response … so the runtime schema is stricter than
  # the published type and the primitive is not usable from here today." Every word after "our mock"
  # describes a call that never left 127.0.0.1. `validateEvaluationAnswers` (node_modules/ai/dist/
  # index.js:14503-14530) runs CLIENT-SIDE and demands a COMPLETE probability distribution over
  # every level index; tests/fixtures/jev-mock-gateway.mjs emitted ONE key for score while its
  # choice branch eight lines above emitted the full map. That asymmetry is the entire finding.
  # A local A/B through evaluate.mjs unmodified: one key -> invalid-response; complete map -> ok.
  # So `score` is NOT blocked, and the shape of the error was a fact about our test double.
  # WE STILL USE `choice`, for a reason that survives the correction: refuting the objection
  # establishes ¬objection, never the claim. The score QUESTION shape — `criteria` as an ARRAY of
  # ordered levels — has still never been sent to the real route, while `choice` over an ordered
  # MAP is the primitive 198 real calls have exercised. Switching would trade a measured path for
  # an unmeasured one to gain an ordinal we already hold. Receipt, and the one probe that would
  # settle it: docs/research/jev-100p-2026-09-21/a9-operating-envelope.md §5.
  # `choice` over ORDERED keys carries the same ordinal signal and is the primitive 198 real
  # calls have already exercised. Ordering lives in the caller - the literal key order in
  # rank_order() below - never in the model. (That sentence cited a `rank_of()` that was never
  # written; the ordering was real but the named function was not. A comment is prose nothing
  # executes, so a citation in one is worth exactly one grep.)
  lvl=$(printf '%s' "$out" | jq -r '.answers.bite.choice // empty' 2>/dev/null)
  brd=$(printf '%s' "$out" | jq -r '.answers.breadth.choice // empty' 2>/dev/null)
  sup=$(printf '%s' "$out" | jq -r '.answers.superseded.probability // empty' 2>/dev/null)
  if [ -z "$lvl" ]; then
    # VISIBLE, not silent. A skip that prints nothing is how 146 dead calls looked like progress.
    skipped=$((skipped+1))
    printf 'x'
    # A RUN THAT IS ALL-SKIP IS BROKEN, NOT UNOPINIONATED. Bail once it is statistically certain
    # rather than completing a doomed pass: 10 consecutive misses after a GREEN preflight means the
    # route died mid-run (rate-limit exhaustion, revoked key), and the remaining calls cannot inform.
    consec=$((consec+1))
    if [ "$consec" -ge "${CC_JEV_RANK_MAX_CONSEC_SKIP:-10}" ]; then
      printf '\n✗ ABORTING: %s consecutive calls produced no verdict (last reason: %s).\n' \
             "$consec" "$(jev_reason "$out")" >&2
      printf '  %s scored before the route stopped answering; rows kept at %s\n' "$done_n" "$OUT" >&2
      break
    fi
    continue
  fi
  consec=0
  done_n=$((done_n+1))
  hook="$(grep -F "($f)" "$IDX" | head -1 | sed 's/^- //' | cut -c1-120)"
  jq -nc --arg f "$f" --arg lvl "$lvl" --arg brd "${brd:-}" --arg sup "${sup:-}" --arg hook "$hook" \
     '{file:$f, level:$lvl, breadth:(if $brd=="" then null else $brd end), superseded:($sup|tonumber? // null), hook:$hook}' >> "$OUT"
  printf '.'
done < "$ROWS"
printf '\n\n'

printf 'SCORED %s of %s  (skipped %s)\n' "$done_n" "$TOT" "$skipped"
[ "$done_n" -gt 0 ] || { printf 'No verdicts — nothing to rank.\n'; exit 1; }
emit_report
rm -f "$ROWS"
