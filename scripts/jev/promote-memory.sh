#!/usr/bin/env bash
# promote-memory.sh — decide which UNREACHABLE memory lessons deserve an index slot, by forced
# comparison rather than by an absolute score. Run via `cc-jev promote`.
#
# ── WHY THIS EXISTS, AND WHY IT IS NOT ANOTHER RANKER ────────────────────────────────────────
# MEMORY.md is at a hard cap: past 25,000 loader units or 200 lines the loader SILENTLY DROPS
# entries. 146 lessons are indexed; 278 more sit on disk reachable from NOTHING a session loads —
# not the index, not the always-loaded project rules file. Today `cc-memory-rotate` decides what
# occupies a slot on structural proxies (age, size, citation counts), and its own header documents
# mtime as ANTI-CORRELATED with durability. Nothing has ever read the lessons themselves.
#
# 🚨 THE ABSOLUTE FORM OF THIS QUESTION IS ALREADY REFUTED, BY OUR OWN RUN. `cc-jev rank` scored
# 140 indexed rules on 2026-09-21 and returned `often` for 118 of them — 84.3%, on a 4-level scale
# that never once used its top level. `superseded` ranged 0.08–0.89 with ZERO rows at or above the
# 0.90 band `hooks/lib/jev.sh` defines as the only actionable one, so by its own library's rule it
# produced no verdicts at all. Every individual judgment was sound and the ORDERING was worthless.
# Re-using that question on 278 orphans would tie ~233 of them with 118 incumbents.
#
# So this asks a question that HAS NO SCALE TO SATURATE: given these five, which ONE; then, given
# this challenger and this incumbent and exactly one slot, WHICH. A forced choice cannot pile 84%
# into a bucket, because there is no bucket — and it is also the shape the eviction decision
# actually has. Promotion without a matching demotion is not executable: the index is FULL, so
# "this orphan is good" changes nothing and "this orphan beats that incumbent" is a swap.
#
# ── WHAT IT NEVER DOES ───────────────────────────────────────────────────────────────────────
# It writes NO change to MEMORY.md, deletes no topic file, and calls no rotator. It emits a swap
# list and a JSONL. Eviction stays a human read, because a wrong demotion is invisible until the
# day the missing rule would have fired.
#
# ── WHAT LEAVES THE MACHINE ──────────────────────────────────────────────────────────────────
# Per call: the frontmatter `description:` of each file plus a bounded head of its body — our own
# engineering lessons, nothing else. NEVER a transcript, the mailbox, or the msg corpus. Bounded
# at CC_JEV_PROMO_CAP_B per file (default 1200), two files per round-2 call, five per heat.
# Consent is expressed on the command line (--yes), so it lands in shell history rather than in a
# prompt a non-TTY channel cannot deliver.
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
RULES="${CC_JEV_RULES_FILE:-$ROOT/.claude/rules/agent-operating-lessons.md}"
RANKROWS="${CC_JEV_RANK_ROWS:-}"
CAP="${CC_JEV_PROMO_CAP_B:-1200}"
SEED="${CC_JEV_PROMO_SEED:-20260921}"
YES=0; HEATS=0; BIAS="${CC_JEV_PROMO_BIAS_N:-20}"; RESUME=""; REPORT=""; PLANONLY=0; SHAONLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --yes) YES=1; shift ;;
    --heats) HEATS="${2:?--heats needs a count}"; shift 2 ;;
    --bias-n) BIAS="${2:?--bias-n needs a count}"; shift 2 ;;
    --mem) MEM="${2:?--mem needs a dir}"; shift 2 ;;
    --resume) RESUME="${2:?--resume needs a .jsonl}"; shift 2 ;;
    --report) REPORT="${2:?--report needs a .jsonl from a previous run}"; shift 2 ;;
    --plan-calls) PLANONLY=1; shift ;;
    --corpus-sha) SHAONLY=1; shift ;;
    -h|--help) printf 'usage: cc-jev promote [--heats N] [--bias-n N] [--mem DIR] [--resume F.jsonl] [--report F.jsonl] [--plan-calls] [--corpus-sha] [--yes]\n'; exit 0 ;;
    *) printf 'usage: cc-jev promote [--heats N] [--bias-n N] [--mem DIR] [--resume F.jsonl] [--report F.jsonl] [--plan-calls] [--corpus-sha] [--yes]\n' >&2; exit 2 ;;
  esac
done

emit_promo_report() {  # reads globals OUT, done_n, TOTAL, skipped, ABORTED
# NEW decisions and TOTAL ON DISK are different numbers, and conflating them makes a COMPLETE
# resumed pass look like a failed one. `done_n` counts what THIS pass bought; a resume that finds
# every id already present buys nothing and is FINISHED, not empty. The original guard printed
# `No verdicts — nothing to promote` and exited 1 on exactly that case — the success state of the
# feature it was guarding. The denominator every percentage below is computed against is what the
# FILE holds, never what this invocation happened to add.
HAVE_N=$(jq -r 'select(.round!="meta")|.id' "$OUT" 2>/dev/null | wc -l | tr -d ' ')
printf 'DECIDED %s new of %s call(s); %s verdict(s) on disk  (no verdict: %s)\n' \
       "$done_n" "$TOTAL" "${HAVE_N:-0}" "$skipped"
if [ "${HAVE_N:-0}" -eq 0 ]; then printf 'No verdicts at all — nothing to promote.\n'; exit 1; fi
if [ "$done_n" -eq 0 ]; then printf 'Nothing new to buy — this pass was already complete.\n'; fi
done_n="$HAVE_N"

# ── THE BIAS VERDICT COMES FIRST, because it governs whether the rest may be read at all ─────
BN=$(jq -r 'select(.round=="h2h" and .swapped==true)|.id' "$OUT" | wc -l | tr -d ' ')
FLIP=0
if [ "$BN" -gt 0 ]; then
  # 🚨 COMPUTED IN ONE PASS WITH `-s`, AND THE ERROR CHANNEL IS NOT SUPPRESSED. The first version
  # used `--slurpfile all "$OUT"` and then indexed `$all[0]`, which is the FIRST OBJECT of the
  # stream rather than the array of them — so every row raised "Cannot index string with string"
  # on stderr, the stdout was empty, `wc -l` read 0, and the run printed a confident
  # "0 of 2 pairs (0%) changed" and a ✓ PASS. A broken control that reports the safe answer is
  # worse than no control: this is the one check that can refute the whole design, and it was
  # certifying it from an error. `-s` slurps the stream into one array and the lookup is a plain
  # index; a jq failure now empties FLIP, which the guard below turns into a NON-VERDICT.
  FLIP=$(jq -rs '
    (map(select(.round=="h2h" and .swapped==false)) | INDEX(.id)) as $orig
    | map(select(.round=="h2h" and .swapped==true)
          | (.id | sub("^swap-";"")) as $oid
          | ($orig[$oid].winner) as $ow
          | select($ow != null)
          # The swapped call reversed the blocks, so AGREEMENT shows up as the OPPOSITE letter.
          # A verdict that keeps the same letter kept the same SLOT, i.e. it flipped on position.
          | select(($ow=="a" and .winner=="a") or ($ow=="b" and .winner=="b")))
    | length' "$OUT" 2>/dev/null)
fi
BIAS_MAX="${CC_JEV_PROMO_BIAS_MAX:-20}"
printf '\nPOSITION-BIAS CONTROL — the one that can kill this design:\n'
if [ "$BN" -eq 0 ]; then
  printf '  NOT RUN (0 swapped pairs). The swap list below is UNVALIDATED on position — do not act on it.\n'
elif [ -z "$FLIP" ]; then
  # The control could not be COMPUTED. That is a non-verdict, never a pass — see the note above.
  printf '  ✗ COULD NOT BE COMPUTED over %s swapped pair(s). This is NOT a pass.\n' "$BN"
  printf '  The swap list below is UNVALIDATED on position — do not act on it.\n'
else
  PCT=$(( FLIP * 100 / BN ))
  printf '  %s of %s pairs (%s%%) changed their winner when ONLY the order changed.\n' "$FLIP" "$BN" "$PCT"
  if [ "$PCT" -gt "$BIAS_MAX" ]; then
    printf '  ✗ ABOVE the %s%% ceiling. These verdicts are about the SLOT, not about the rule.\n' "$BIAS_MAX"
    printf '  THE COMPARATIVE DESIGN IS REFUTED ON THIS CORPUS. Do not act on the swap list; it is\n'
    printf '  printed below only so the failure is inspectable.\n'
  else
    printf '  ✓ within the %s%% ceiling — order is not driving the verdicts.\n' "$BIAS_MAX"
  fi
fi

# ── THE SWAP LIST — the consumer. A promotion that names no demotion is not executable. ───────
# The index is FULL. "This orphan is good" changes nothing; "this orphan beats that incumbent"
# is an edit a human can make. Every line names both halves, and NOTHING here is applied.
# 🚨 ONE SLOT, ONE SWAP — the list is a MATCHING, not a list of wins. Anchors cycle (22 weak
# incumbents against 56 challengers), so the same incumbent is beaten by several challengers and a
# naive dump proposes evicting it repeatedly. Measured on the first real pass: 45 "swaps" over
# **21 distinct incumbents**, five of them named three times. At most 21 are executable, and an
# operator working the list top-down would reach a line telling them to demote a rule that is
# already gone. The output looked actionable and was not — which is the failure this whole consumer
# exists to avoid, one level in.
# The tiebreak is `same_rule` ASC, and it is an argument rather than a convenience: where two
# challengers both beat the same incumbent, the one stating a MORE DIFFERENT rule adds more to a
# capped index than the one restating it. Surplus challengers are reported as runners-up, honestly
# counted, never as swaps.
# 🚨 OPERATOR DIRECTIVES ARE HELD OUT OF THE LIST, NOT SILENTLY RANKED INTO IT.
# A `feedback-*` rule is not an engineering lesson the model can weigh on "how often would this
# change what an engineer DOES" — it is a standing instruction the operator gave deliberately, and
# its value does not come from how often it fires. Measured on the first real pass: Jev put
# `feedback-handoff-splitright-default.md` up for demotion and it lost all 3 times it was judged.
# 13 of the 146 indexed rules are directives, so this is not a corner case.
# Demoting one is the worst wrong demotion available: it is invisible until an agent quietly stops
# following something the operator believes is in force. So they are separated, named, and made a
# decision rather than a line item — refusing outright would be wrong too, since the operator may
# genuinely want one retired. CC_JEV_PROMO_PROTECT changes the prefix; empty disables the split.
PROTECT="${CC_JEV_PROMO_PROTECT-feedback-}"
_swaps_jq='map(select(.round=="h2h" and .swapped==false and .winner=="a"))
           | group_by(.block_b) | map(sort_by(.same_rule // 1) | .[0]) | sort_by(.same_rule // 1)'
if [ -n "$PROTECT" ]; then
  _DIRECTIVE=$(jq -rs --arg p "$PROTECT" "$_swaps_jq"' | map(select(.block_b|startswith($p)))
               | .[] | "  + \(.block_a)\n  - \(.block_b)   <- OPERATOR DIRECTIVE\n"' "$OUT")
  if [ -n "$_DIRECTIVE" ]; then
    printf '\n🚨 HELD OUT — these displace an OPERATOR DIRECTIVE, not an engineering lesson:\n'
    printf '%s\n' "$_DIRECTIVE"
    printf '  A directive is not weighed on how often it fires; the operator set it deliberately.\n'
    printf '  Decide these one at a time, or not at all. They are NOT counted in the list below.\n'
  fi
fi

printf '\nSWAP LIST — one slot, one swap. Each incumbent appears AT MOST ONCE:\n'
printf '  (promote the first, demote the second. Read both before editing.)\n'
jq -rs --arg p "$PROTECT" "$_swaps_jq"' | map(select($p=="" or ((.block_b|startswith($p))|not)))
       | .[] | "  + \(.block_a)\n  - \(.block_b)\n"' "$OUT" | head -90
# `((X)|not)`, fully parenthesised: jq's `|` binds LOOSER than `or`, so `$p=="" or X|not` is
# `($p=="" or X) | not` — the negation of the whole disjunction. With an empty prefix that made
# every row false and printed `0 executable swap(s)` over a list that had them.
SWAPS=$(jq -rs --arg p "$PROTECT" "$_swaps_jq"' | map(select($p=="" or ((.block_b|startswith($p))|not))) | length' "$OUT")
# A HELD-OUT directive is neither a swap nor a runner-up — it is its own decision. Counting it as
# a runner-up overstated the surplus by exactly the number of directives held out.
HELDN=$(jq -rs --arg p "$PROTECT" "$_swaps_jq"' | map(select($p!="" and (.block_b|startswith($p)))) | length' "$OUT")
WINS=$(jq -r 'select(.round=="h2h" and .swapped==false and .winner=="a")|.id' "$OUT" | wc -l | tr -d ' ')
RUNNERS=$(( WINS - SWAPS - HELDN ))
[ "$RUNNERS" -gt 0 ] && printf '  %s further challenger(s) also beat an incumbent that is already being displaced above —\n  runners-up, not extra slots. Re-run after editing the index to re-match them.\n' "$RUNNERS"
HELD=$(jq -r 'select(.round=="h2h" and .swapped==false and .winner=="b")|.id' "$OUT" | wc -l | tr -d ' ')
printf '  %s executable swap(s); %s incumbent(s) held their slot; %s win(s) total.\n' \
       "$SWAPS" "$HELD" "$WINS"
if [ "$SWAPS" = 0 ] && [ "$HELD" -gt 0 ]; then
  printf '  EVERY incumbent won. Either the index is already correct, or the contest is degenerate —\n'
  printf '  the same failure shape as an 84%%-one-bucket scale, wearing a different form. Say so.\n'
fi

# ── THE FREE PASSENGER ───────────────────────────────────────────────────────────────────────
DUPS=$(jq -r 'select(.round=="h2h" and .swapped==false and (.same_rule//0) >= 0.70)|.id' "$OUT" | wc -l | tr -d ' ')
printf '\nDUPLICATE RULES (same_rule >= 0.70) — bought for zero extra calls:\n'
if [ "$DUPS" = 0 ]; then
  _sd=$(jq -r 'select(.same_rule!=null)|.same_rule' "$OUT" | sort -n \
        | awk '{a[NR]=$1} END{if(NR)printf "n=%d p50 %.2f p90 %.2f max %.2f", NR, a[int(NR*.5)+1], a[int(NR*.9)+1], a[NR]; else printf "n=0"}')
  printf '  none at 0.70. Distribution: %s\n' "$_sd"
else
  jq -r 'select(.round=="h2h" and .swapped==false and (.same_rule//0) >= 0.70)
         | "  \(.same_rule)  \(.block_a)  ==  \(.block_b)"' "$OUT" | sort -rn | head -20
fi

printf '\nrows -> %s\n' "$OUT"
printf 'Nothing was edited. No file was moved, no index line was written, cc-memory-rotate was not called.\n'
[ "$ABORTED" -eq 1 ] && { printf 'Run was ABORTED early — resume with: cc-jev promote --resume %s --yes\n' "$OUT"; exit 1; }
}

# ── --report: RE-READ A PAST RUN, SPENDING NOTHING ───────────────────────────────────────────
# Above every corpus read and every network check, and directly below the function it calls. A
# local re-read of rows already paid for must not need a key, a route, or even the memory dir —
# gating it on any of those would refuse an inspection precisely when the vendor is down, which is
# when you most want to look at what you already have. It is also how the position-bias
# arithmetic is tested, on hand-built rows, with no call.
if [ -n "$REPORT" ]; then
  [ -s "$REPORT" ] || { printf 'no rows at %s\n' "$REPORT" >&2; exit 3; }
  # The meta row stamps WHAT the run was a run of; it is not a verdict, so it must not inflate the
  # denominator every percentage in the report is computed against.
  OUT="$REPORT"
  done_n=$(jq -r 'select(.round!="meta")|.id' "$REPORT" 2>/dev/null | wc -l | tr -d ' ')
  [ "${done_n:-0}" -gt 0 ] || done_n=$(wc -l < "$REPORT" | tr -d ' ')
  TOTAL="$done_n"; skipped=0; ABORTED=0
  printf 'Re-reading %s row(s) from a PREVIOUS run. No call is made.\n' "$done_n"
  emit_promo_report
  exit 0
fi

IDX="$MEM/MEMORY.md"
[ -f "$IDX" ] || { printf 'no index at %s\n' "$IDX" >&2; exit 3; }

# ── THE POPULATION, AND ITS DEFINITION IS LOAD-BEARING ───────────────────────────────────────
# An orphan is a topic file reachable from NEITHER always-loaded surface: not linked from
# MEMORY.md, and not cited by the project rules file (which IS injected into every session in this
# repo and legitimately keeps ~55 lessons reachable without an index slot). Counting only the
# index overstates the orphan set by exactly that many and would put already-reachable rules into
# a contest for a slot they do not need.
# `find -H` is not decoration: the memory dir is commonly reached through a symlink, and BSD find
# skips a symlinked start dir without it — the null then reads as "no lessons", not as "cannot see".
_basenames() { xargs -n1 basename 2>/dev/null | sort -u; }
ALL="$(mktemp)"; INDEXED="$(mktemp)"; ORPH="$(mktemp)"
find -H "$MEM" -maxdepth 1 -name '*.md' ! -name 'MEMORY*.md' -exec basename {} \; | sort -u > "$ALL"
grep -o '](\([^)]*\.md\))' "$IDX" | sed 's/](//;s/)//' | _basenames > "$INDEXED"
comm -23 "$ALL" "$INDEXED" | while read -r f; do
  [ -n "$f" ] || continue
  if [ -f "$RULES" ] && grep -qF "$f" "$RULES"; then continue; fi
  printf '%s\n' "$f"
done > "$ORPH"
N_ALL=$(wc -l < "$ALL" | tr -d ' '); N_IDX=$(wc -l < "$INDEXED" | tr -d ' ')
N_ORPH=$(wc -l < "$ORPH" | tr -d ' ')
[ "$N_ORPH" -ge 5 ] || { printf 'REFUSING: only %s orphan(s) — a heat needs 5 and the contest would be vacuous.\n' "$N_ORPH" >&2; exit 3; }

# ── THE ANCHORS: the incumbents a challenger must actually beat ──────────────────────────────
# Not a random incumbent — the WEAKEST ones, which is the only comparison whose answer is
# executable. They come from a previous `cc-jev rank` run's own output (level almost-never or
# occasionally). With no such run on disk the contest has no opponent and this REFUSES rather than
# silently substituting an arbitrary incumbent: a swap list built against a strong incumbent would
# recommend evicting a rule that is holding its slot correctly.
ANCH="$(mktemp)"
# 🚨 PICK THE NEWEST RUN THAT YIELDS RESOLVABLE ANCHORS — not the newest NON-EMPTY one.
# Those are different predicates and the difference is not hypothetical: a 5-row run left behind by
# a hand repro sat beside the real 140-row run in the same directory, newer by name, non-empty, and
# every one of its rows named a FIXTURE file (alpha.md, beta.md) that does not exist in the memory
# dir. "Newest non-empty" selected it, all 5 rows failed the -f test, and the tool refused with
# "no weak-incumbent anchors" — a true sentence about the file it chose and a false one about the
# machine, which held 22 perfectly good anchors one file down.
# So: walk the runs newest-first and take the FIRST that actually produces an anchor. Selection by
# the property you need, never by a proxy that correlates with it.
_anchors_from() {  # $1=rows file → resolvable weak-incumbent basenames, one per line
  # `.mock != true` first: a run against the local test double must never supply an anchor, and
  # the -f test below is NOT a sufficient filter for that — a mock row naming a file that happens
  # to exist would pass it silently. Rows without the field predate the marker and are allowed
  # through, then still have to resolve; unknown provenance is weaker evidence, not a refusal.
  jq -r 'select((.mock // false) != true)
         | select((.level//"")|test("almost-never|occasionally"))|.file' "$1" 2>/dev/null \
    | _basenames | while read -r f; do [ -n "$f" ] && [ -f "$MEM/$f" ] && printf '%s\n' "$f"; done
}
if [ -n "$RANKROWS" ] && [ -s "$RANKROWS" ]; then
  # An EXPLICIT --rank-rows / CC_JEV_RANK_ROWS is honoured as given: the caller named a file, so a
  # silent fallback to a different one would answer a question nobody asked.
  _anchors_from "$RANKROWS" > "$ANCH"
else
  # The filename carries a UTC stamp set at process start, so a lexical reverse sort is
  # chronological and is not perturbed by a later touch, copy or restore. `-H` because ~/.claude is
  # commonly a symlink and BSD find skips a symlinked start dir without it.
  RANKROWS=""
  while IFS= read -r _cand; do
    [ -n "$_cand" ] || continue
    _anchors_from "$_cand" > "$ANCH"
    if [ -s "$ANCH" ]; then RANKROWS="$_cand"; break; fi
  done <<EOF
$(find -H "$HOME/.claude/autonomy" -maxdepth 1 -name 'jev-rank-*.jsonl' -size +0c 2>/dev/null | sort -r)
EOF
fi
N_ANCH=$(wc -l < "$ANCH" | tr -d ' ')
[ "$N_ANCH" -gt 0 ] || { cat >&2 <<EOF
✗ REFUSING: no weak-incumbent anchors.
  A promotion verdict is only executable as a SWAP, and a swap needs the incumbent it displaces.
  Anchors come from a previous ranking run's own rows (level almost-never / occasionally):

      CC_JEV_ZDR=0 cc-jev rank --yes        # then re-run this

  Looked in: ${RANKROWS:-~/.claude/autonomy/jev-rank-*.jsonl}
  Nothing has been sent.
EOF
exit 3; }

[ "$HEATS" -gt 0 ] || HEATS=$(( (N_ORPH + 4) / 5 ))
R2=$HEATS
TOTAL=$(( 1 + HEATS + R2 + BIAS ))

# --plan-calls: print the call budget for a FULL pass over the live corpus and stop. It exists so
# that `cc-jev arm` can size a window from the population rather than from a constant — ONE
# definition of "the orphans", here, where it already lives. The first default was a hardcoded 60,
# which covered 130 of 278 orphans: one arming produced half a swap list and the shortfall was
# invisible, because a partial pass prints exactly the same summary as a complete one.
if [ "$PLANONLY" -eq 1 ]; then printf '%s\n' "$TOTAL"; exit 0; fi
# --corpus-sha prints the identity of the population as it stands RIGHT NOW, spending nothing, so
# the scheduler can compare it against what the last completed pass recorded.
if [ "$SHAONLY" -eq 1 ]; then
  printf '%s\n' "$( { sort "$ORPH"; printf -- '--\n'; sort "$ANCH"; } | shasum -a 256 2>/dev/null | cut -c1-16)"
  exit 0
fi

OUT="${RESUME:-$HOME/.claude/autonomy/jev-promote-$(date -u +%Y%m%dT%H%M%SZ).jsonl}"
mkdir -p "$(dirname "$OUT")" || { printf 'cannot create %s\n' "$(dirname "$OUT")" >&2; exit 3; }
: >> "$OUT" || { printf 'cannot write %s\n' "$OUT" >&2; exit 3; }

printf 'Index:    %s  (%s indexed of %s topic files)\n' "$IDX" "$N_IDX" "$N_ALL"
printf 'Orphans:  %s reachable from NEITHER the index NOR the always-loaded rules file\n' "$N_ORPH"
printf 'Anchors:  %s weak incumbent(s) from %s\n' "$N_ANCH" "$RANKROWS"
printf 'Plan:     1 preflight + %s heat(s) of 5 + %s head-to-head + %s position-bias = %s call(s)\n' \
       "$HEATS" "$R2" "$BIAS" "$TOTAL"
printf 'Pacing:   ~%s min of calls at the measured 14.8/min; budget %s-%s min with backoff.\n' \
       "$(( TOTAL / 15 + 1 ))" "$(( TOTAL / 15 + 1 ))" "$(( TOTAL / 5 + 1 ))"
printf 'Rows ->   %s%s\n' "$OUT" "$([ -n "$RESUME" ] && printf ' (RESUMING — completed ids are skipped)')"
printf 'Sends:    description + first %s B of body per file. Our own lessons only.\n\n' "$CAP"
if [ "$YES" -ne 1 ]; then
  printf 'Re-run with --yes to send. Nothing has been sent.\n'; exit 3
fi

# ── GUARDS, cheapest first ───────────────────────────────────────────────────────────────────
if [ "${CC_JEV_ZDR:-1}" != 0 ]; then
  cat <<EOF
✗ REFUSING before the first call. ZDR is ON and it is Pro/Enterprise-only, so on this plan every
  one of the $TOTAL calls returns HTTP 403 and this run would decide exactly nothing.

  To send under STANDARD retention (bounded lesson excerpts — our own engineering rules, never a
  transcript, the mailbox, or the msg corpus):

      CC_JEV_ZDR=0 cc-jev promote --yes

  Nothing has been sent.
EOF
  exit 4
fi
jev_window_open || exit 4
jev_available || { printf 'not available — run: cc-jev status\n' >&2; exit 2; }

# ── THE RUN IS AN EXPERIMENT, AND A RESUME MUST BE THE SAME ONE ──────────────────────────────
# The heats are a DETERMINISTIC shuffle of the orphan list (CC_JEV_PROMO_SEED), so "h7" names a
# specific five files only while the population and the seed are unchanged. Add or remove a lesson
# and h7 is a different heat — but `_have h7` would still skip it, silently splicing a verdict
# about five OTHER files into this run's rows. Nothing downstream could detect that: the row shape
# is identical and the winner is a real filename.
# So every run stamps what it was a run OF, and a resume that does not match starts fresh instead.
# MOCK is stamped from the ROUTE, at write time — the one fact that settles whether a row is a
# verdict about the world or about a test double. See hooks/lib/jev.sh::jev_is_mock.
MOCKED=false; jev_is_mock && MOCKED=true
# CORPUS_SHA identifies the POPULATION this run judged, not merely how big it was. A count is a
# weak key: evict one lesson and promote another and it is unchanged while every heat has shifted.
# The unattended scheduler uses it to answer "is there anything new to judge?" — without that it
# would re-run a COMPLETED 133-call pass on every 1800s tick, ~6,384 calls/day over rows it already
# has. Orphans AND anchors, because a change in either makes the contest a different contest.
CORPUS_SHA="$( { sort "$ORPH"; printf -- '--\n'; sort "$ANCH"; } | shasum -a 256 2>/dev/null | cut -c1-16)"
[ -n "$CORPUS_SHA" ] || CORPUS_SHA="unknown"
_meta_row() { jq -nc --arg id meta --arg r meta --argjson o "$N_ORPH" --arg sd "$SEED" \
                  --argjson pl "$TOTAL" --argjson a "$N_ANCH" --argjson m "$MOCKED" \
                  --arg cs "$CORPUS_SHA" \
                  '{id:$id, round:$r, orphans:$o, seed:$sd, plan:$pl, anchors:$a, mock:$m, corpus_sha:$cs}'; }
if [ -n "$RESUME" ] && [ -s "$OUT" ]; then
  _prev="$(jq -c 'select(.round=="meta")' "$OUT" 2>/dev/null | head -1)"
  _po="$(printf '%s' "$_prev" | jq -r '.orphans // empty' 2>/dev/null)"
  _ps="$(printf '%s' "$_prev" | jq -r '.seed // empty' 2>/dev/null)"
  if [ -z "$_prev" ] || [ "$_po" != "$N_ORPH" ] || [ "$_ps" != "$SEED" ]; then
    printf '✗ REFUSING to resume %s — it is a run of a DIFFERENT population.\n' "$OUT" >&2
    printf '  then: %s orphans, seed %s      now: %s orphans, seed %s\n' \
           "${_po:-unstamped}" "${_ps:-unstamped}" "$N_ORPH" "$SEED" >&2
    printf '  Heat ids are positions in a seeded shuffle, so reusing them would splice verdicts\n' >&2
    printf '  about other files into this run. Start a fresh run (drop --resume).\n' >&2
    exit 3
  fi
  printf 'Resuming %s — %s row(s) already paid for.\n' "$OUT" "$(wc -l < "$OUT" | tr -d ' ')"
else
  _meta_row >> "$OUT"
fi

printf 'Preflight: one call before committing to %s...\n' "$TOTAL"
_pf="$(jq -n '{state:"ok", questions:{p:{type:"boolean",instructions:"Is this text non-empty?"}}}' | jev_ask)" || true
if [ -z "$(printf '%s' "$_pf" | jq -r '.answers.p.probability // empty' 2>/dev/null)" ]; then
  printf '✗ REFUSING: the preflight call produced no verdict (reason: %s).\n' "$(jev_reason "$_pf")" >&2
  printf '  The %s calls behind it would have taken ~%s minutes and decided nothing.\n' "$TOTAL" "$(( TOTAL / 15 + 1 ))" >&2
  printf '  Nothing further has been sent. Diagnose with: cc-jev status\n' >&2
  exit 4
fi
printf 'Preflight OK — the route answers.\n\n'
# ── the call machinery: one place, so backoff and the abort rule cannot drift between rounds ──
done_n=0; skipped=0; consec=0; ABORTED=0
_have() {  # $1=row id — resumability. Re-running must not re-buy a verdict already paid for.
  [ -s "$OUT" ] || return 1
  jq -e --arg i "$1" 'select(.id==$i)' "$OUT" >/dev/null 2>&1
}
_excerpt() {  # $1=basename → "description + bounded body head", never the whole file
  local f="$MEM/$1" d
  d="$(sed -n 's/^description: *//p' "$f" | head -1)"
  printf '%s\n%s' "${d:-(no description)}" "$(sed '1,/^---$/d;1,/^---$/d' "$f" | head -c "$CAP")"
}
_ask() {  # $1=spec → prints the reply, retries ONLY on rate-limit, obeys the abort rule
  local spec="$1" out tries=0 wait_s
  out="$(printf '%s' "$spec" | jev_ask)" || true
  while [ "$(printf '%s' "$out" | jq -r '.reason // ""' 2>/dev/null)" = "rate-limited" ] \
        && [ "$tries" -lt "${CC_JEV_PROMO_RETRIES:-5}" ]; do
    tries=$((tries+1)); wait_s=$(( ${CC_JEV_PROMO_BACKOFF:-10} * tries ))
    printf '  … rate-limited, backing off %ss (retry %s/%s)\n' "$wait_s" "$tries" "${CC_JEV_PROMO_RETRIES:-5}" >&2
    sleep "$wait_s"; out="$(printf '%s' "$spec" | jev_ask)" || true
  done
  sleep "${CC_JEV_PROMO_GAP:-3}"
  printf '%s' "$out"
}
_miss() {  # a verdict-less call: VISIBLE, counted, and fatal once it is statistically certain
  skipped=$((skipped+1)); consec=$((consec+1)); printf 'x'
  if [ "$consec" -ge "${CC_JEV_PROMO_MAX_CONSEC_SKIP:-10}" ]; then
    printf '\n✗ ABORTING: %s consecutive calls produced no verdict (last reason: %s).\n' "$consec" "$1" >&2
    printf '  %s decided before the route stopped answering; rows kept at %s\n' "$done_n" "$OUT" >&2
    printf '  Re-run with --resume %s to continue without re-buying them.\n' "$OUT" >&2
    ABORTED=1; return 1
  fi
  return 0
}

# Deterministic shuffle: the SAME heats on every run, so --resume lines up and two runs of the same
# corpus are comparable. `sort -R` would reshuffle and make a resumed run a different experiment.
_shuf() { awk -v s="$SEED" '{printf "%d\t%s\n", (((NR*1103515245+s)%2147483647)+2147483647)%2147483647, $0}' \
          | sort -n | cut -f2-; }

LETTERS="a b c d e"
Q1_INSTR="Five engineering lessons from one codebase's own memory are listed as A through E. The index that makes a lesson reachable to a future agent is at a hard cap, so only some of these can ever be loaded. Choose the ONE whose absence would most often cause a future agent working in this codebase to make a real mistake. Judge the RULE each one states - not how well it is written, not how recent it is, and not how dramatic its incident was."

# ── ROUND 1: heats of five. A forced choice among peers, with no scale to saturate. ───────────
printf 'ROUND 1 — %s heat(s) of five:\n' "$HEATS"
_shuf < "$ORPH" > "$ORPH.s"
WIN="$(mktemp)"
h=0
while [ "$h" -lt "$HEATS" ]; do
  h=$((h+1))
  members="$(sed -n "$(( (h-1)*5 + 1 )),$(( h*5 ))p" "$ORPH.s")"
  [ -n "$members" ] || break
  cnt=$(printf '%s\n' "$members" | grep -c .)
  [ "$cnt" -ge 2 ] || { printf '%s\n' "$members" >> "$WIN"; continue; }   # a 1-member heat has no contest
  id="h$h"
  if _have "$id"; then
    jq -r --arg i "$id" 'select(.id==$i)|.winner' "$OUT" | head -1 >> "$WIN"; printf '='; continue
  fi
  state=""; crit="{}"; i=0
  for f in $members; do
    i=$((i+1)); L=$(printf '%s' "$LETTERS" | cut -d' ' -f"$i")
    state="$state$(printf '=== %s ===\n%s\n\n' "$(printf '%s' "$L" | tr a-e A-E)" "$(_excerpt "$f")")"
    crit="$(printf '%s' "$crit" | jq --arg k "$L" --arg t "$(printf '%s' "$L" | tr a-e A-E) states the rule that would most often prevent a real mistake here" '. + {($k):$t}')"
  done
  spec="$(jq -n --arg s "$state" --arg ins "$Q1_INSTR" --argjson c "$crit" \
          '{state:$s, questions:{pick:{type:"choice", instructions:$ins, criteria:$c}}}')"
  out="$(_ask "$spec")"
  pick=$(printf '%s' "$out" | jq -r '.answers.pick.choice // empty' 2>/dev/null)
  if [ -z "$pick" ]; then _miss "$(jev_reason "$out")" || break; continue; fi
  consec=0; done_n=$((done_n+1))
  idx=$(printf '%s' "$LETTERS" | tr ' ' '\n' | grep -n "^$pick$" | cut -d: -f1)
  w=$(printf '%s\n' "$members" | sed -n "${idx}p")
  printf '%s\n' "$w" >> "$WIN"
  jq -nc --arg id "$id" --arg r heat --arg w "$w" --argjson m "$(printf '%s\n' "$members" | jq -R . | jq -sc .)" \
     --argjson mk "$MOCKED" '{id:$id, round:$r, winner:$w, members:$m, mock:$mk}' >> "$OUT"
  printf '.'
done
printf '\n'

Q2_INSTR="Two engineering lessons from one codebase's memory are given as block A and block B. Exactly one index slot is available and the index is at a hard cap, so one of them will be reachable to a future agent and the other will not. Choose the one whose absence would more often cause a future agent working in this codebase to make a real mistake. Judge the RULE each block states, not how well it is written and not how recent it is."
Q2_A="the rule in block A would more often prevent a real mistake here; B restates something obvious, applies only to one situation that has already been fixed, or describes a tool, path or version that has since been replaced"
Q2_B="the rule in block B would more often prevent a real mistake here; A restates something obvious, applies only to one situation that has already been fixed, or describes a tool, path or version that has since been replaced"
QD_INSTR="Do block A and block B state the SAME underlying rule, differing only in the incident used to illustrate it?"
QD_T="one is a restatement of the other's rule; keeping both in a capped index would be redundant"
QD_F="they state different rules, even if both concern the same subsystem or the same tool"

# _h2h <id> <fileA> <fileB> <swapped?> — ONE head-to-head call, two questions.
# `same_rule` rides along for ZERO marginal calls, and it rides on exactly the pairs where a dedup
# answer changes a decision: a challenger about to displace an incumbent. Standalone dedup over
# this corpus is O(n^2) = 89,676 pairs and is properly refuted; as a passenger it is targeted.
_h2h() {
  local id="$1" fa="$2" fb="$3" sw="$4" spec out win same
  _have "$id" && { printf '='; return 0; }
  spec="$(jq -n --arg s "$(printf '=== BLOCK A ===\n%s\n\n=== BLOCK B ===\n%s\n' "$(_excerpt "$fa")" "$(_excerpt "$fb")")" \
          --arg i2 "$Q2_INSTR" --arg qa "$Q2_A" --arg qb "$Q2_B" \
          --arg id2 "$QD_INSTR" --arg dt "$QD_T" --arg df "$QD_F" \
          '{state:$s, questions:{
             winner:{type:"choice", instructions:$i2, criteria:{a:$qa, b:$qb}},
             same_rule:{type:"boolean", instructions:$id2, criteria:{"true":$dt,"false":$df}}
           }}')"
  out="$(_ask "$spec")"
  win=$(printf '%s' "$out" | jq -r '.answers.winner.choice // empty' 2>/dev/null)
  same=$(printf '%s' "$out" | jq -r '.answers.same_rule.probability // empty' 2>/dev/null)
  [ -n "$win" ] || { _miss "$(jev_reason "$out")" || return 1; return 0; }
  consec=0; done_n=$((done_n+1))
  jq -nc --arg id "$id" --arg r h2h --arg a "$fa" --arg b "$fb" --arg w "$win" \
     --arg sm "${same:-}" --argjson sw "$sw" \
     --argjson mk "$MOCKED" '{id:$id, round:$r, block_a:$a, block_b:$b, winner:$w,
       same_rule:($sm|tonumber? // null), swapped:($sw==1), mock:$mk}' >> "$OUT"
  printf '.'
}

# ── ROUND 2: each heat winner against a WEAK INCUMBENT. This is the executable question. ──────
printf 'ROUND 2 — challengers vs weak incumbents (with the free dedup passenger):\n'
k=0
while IFS= read -r ch; do
  [ -n "$ch" ] || continue
  [ "$ABORTED" -eq 1 ] && break
  k=$((k+1))
  anchor=$(sed -n "$(( (k-1) % N_ANCH + 1 ))p" "$ANCH")
  _h2h "r2-$k" "$ch" "$anchor" 0 || break
done < "$WIN"
printf '\n'

# ── THE CONTROL THAT CAN KILL THIS DESIGN ────────────────────────────────────────────────────
# Two lessons in one state is a form NO existing call site uses, so position bias is un-evidenced
# here rather than known-absent. Re-run a sample of round 2 with A and B swapped: a verdict that
# flips when only the ORDER changes is a verdict about the slot, not about the rule. If flips
# exceed CC_JEV_PROMO_BIAS_MAX (default 20%), the comparative design is DEAD and the report must
# say so rather than shipping a swap list built on position. This control exists to fail.
printf 'CONTROL — %s position-bias re-runs (A and B swapped):\n' "$BIAS"
if [ "$ABORTED" -eq 0 ] && [ "$BIAS" -gt 0 ]; then
  jq -r 'select(.round=="h2h" and .swapped==false)|"\(.id)\t\(.block_a)\t\(.block_b)"' "$OUT" \
    | head -"$BIAS" | while IFS="$(printf '\t')" read -r oid fa fb; do
        printf '%s\t%s\t%s\n' "$oid" "$fa" "$fb"
      done > "$OUT.bias"
  while IFS="$(printf '\t')" read -r oid fa fb; do
    [ -n "$oid" ] || continue
    _h2h "swap-$oid" "$fb" "$fa" 1 || break
  done < "$OUT.bias"
  rm -f "$OUT.bias"
fi
printf '\n\n'

emit_promo_report
rm -f "$ALL" "$INDEXED" "$ORPH" "$ORPH.s" "$ANCH" "$WIN"
exit 0
