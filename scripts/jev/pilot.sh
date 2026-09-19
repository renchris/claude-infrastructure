#!/usr/bin/env bash
# pilot.sh — score Jev against REAL closes this fleet has already judged. Run via `cc-jev pilot`.
#
# THE EVIDENCE POSITION THIS EXISTS TO FIX. docs/research/jev-at-cost-api-2026-09-18.md §5:
# "Nobody has ever scored Jev against real labels. That is the state of the evidence." Every
# public number is the vendor's or a relay of it; the one independent benchmark says Jev's
# TERMINAL verdict loses to Haiku 4.5 (62.6% vs 81.3%) and only its DECOMPOSED extractor form
# competes. The semantic arm in anti-deference-nudge.sh is therefore shipped off by default, and
# this is the instrument that decides whether it should ever be on.
#
# ── THE TWO ARMS, AND WHY BOTH ARE NEEDED ────────────────────────────────────────────────────
# A: RECALL ON KNOWN POSITIVES. Closes where the hook already FIRED are labelled positive by the
#    lexical matcher itself — the one label we genuinely hold. Jev must agree with nearly all of
#    them. This arm can FAIL and that is its point: a Jev that misses closes a regex caught is
#    disqualified outright, and no amount of new-fire volume redeems it.
# B: DISCOVERY ON `no-tell`. What Jev would NEWLY fire on. There is NO ground truth here, so
#    this arm reports a RATE and a SAMPLE for hand-reading — never an accuracy. Saying otherwise
#    would be inventing a label, which is the defect the research doc spent 17 agents refuting.
#
# 🚨 ARM B HAS NO LABELS AND THE REPORT SAYS SO ON ITS FACE. A new-fire rate is not a precision.
#    The repo's own census puts real ungated deferrals at ~2.8% of closes with hand-read
#    precision 30%; if arm B fires far above that band, the arm is over-firing, not finding gold.
#
# 🚨 SENDS REAL CLOSING MESSAGES TO A THIRD PARTY. Gated on a typed yes. Only the closing message
#    leaves the machine — no transcript, no paths, no history — and ZDR is on and fails closed.
set -uo pipefail

# Resolve $0 through its symlinks BEFORE deriving anything from it. ~/.claude/{bin,scripts}/ are
# per-file symlinks into the checkout, so an unresolved `dirname "$0"/..` yields ~/.claude — which
# has no node_modules, no tests/ and no .git. The script would not fail; it would read the WRONG
# TREE, and only on the live path (memory symlinked-$0-splits-siblings). No `readlink -f`: GNU-only.
_resolve_self() {
  local p="$1" d
  while [ -L "$p" ]; do
    d="$(cd -P "$(dirname "$p")" && pwd)"
    p="$(readlink "$p")"
    case "$p" in /*) ;; *) p="$d/$p" ;; esac
  done
  printf '%s' "$p"
}
_self="$(_resolve_self "${BASH_SOURCE[0]}")"
ROOT="$(cd -P "$(dirname "$_self")/../.." && pwd)"
# shellcheck source=/dev/null
. "$ROOT/hooks/lib/jev.sh"

N=40; YES=0
while [ $# -gt 0 ]; do
  case "$1" in
    -n) N="${2:?-n needs a count}"; shift 2 ;;
    --yes) YES=1; shift ;;
    *) printf 'usage: cc-jev pilot [-n N] [--yes]\n' >&2; exit 2 ;;
  esac
done

jev_available || { printf 'not available — run: cc-jev status\n' >&2; exit 2; }
command -v jq >/dev/null || { printf 'jq required\n' >&2; exit 2; }

IDL="${CC_IDL_PATH:-$HOME/.claude/autonomy/idl.jsonl}"
[ -r "$IDL" ] || { printf 'no IDL at %s\n' "$IDL" >&2; exit 2; }

OUT="${CC_JEV_PILOT_OUT:-$HOME/.claude/autonomy/jev-pilot-$(date -u +%Y%m%dT%H%M%SZ).jsonl}"

# ── READ THE ROTATED ARCHIVES TOO, AND NEVER WITH `zcat` ─────────────────────────────────────
# The live idl.jsonl holds ~39 sessions; the 5,422 anti-deference evaluations live almost
# entirely in idl.jsonl.*.gz. Reading only the live file yields ZERO labels for arm A — the arm
# that exists to disqualify Jev would silently not run, which is the vacuous positive control
# this repo keeps re-learning. `gunzip -c`, never `zcat`: BSD zcat appends `.Z`, fails, and
# returns empty, which reads as "no rows" (docs/research/jev-at-cost-api-2026-09-18.md § N_sync).
idl_all() { cat "$IDL" 2>/dev/null; gunzip -c "$IDL".*.gz 2>/dev/null; }

# ── ONE ROW PER EVALUATION, NOT ONE PER SESSION ──────────────────────────────────────────────
# The first draft collapsed with `group_by(.sid)|map(.[-1])` and reported 0 fired rows out of
# 606 sessions — because a session that fires once and then abstains 40 times has an ABSTAIN as
# its last row. The 160 fires were all real and all discarded by the dedup key. Sample rows.
POP="$(mktemp)"
idl_all | jq -rc 'select(.hook=="anti-deference-nudge")
                  | {sid, disp:.disposition, reason:.reason, tell:(.tell // "")}' 2>/dev/null > "$POP"
TOTAL=$(wc -l < "$POP" | tr -d ' ')

# Locate each session transcript and take its LAST assistant text — that IS the close.
resolve() { find "$HOME"/.claude*/projects -name "$1.jsonl" -type f 2>/dev/null | head -1; }
msg_with_tell() {
  jq -r --arg t "$2" 'select(.type=="assistant" and (.isSidechain != true))
         | .message.content | if type=="array" then ([.[]?|select(.type=="text")|.text]|join("\n")) else empty end
         | select(. != "") | select(ascii_downcase | contains($t | ascii_downcase))' "$1" 2>/dev/null | head -1
}
last_close() {
  jq -r 'select(.type=="assistant" and (.isSidechain != true))
         | .message.content | if type=="array" then ([.[]?|select(.type=="text")|.text]|join("\n")) else empty end
         | select(. != "")' "$1" 2>/dev/null | tail -1
}

# ARM A LABELS ARE THE *SEMANTIC* FIRES ONLY. `opaque-identifier` (75 rows) is a different
# defect — unexpanded hex ids — and Jev is not being asked to detect it, so counting it as a
# label would score the arm on a question nobody posed. That leaves deference + false-done +
# category-not-idea = 85 genuine labels.
SAMPLE="$(mktemp)"
{ grep '"disp":"fired"' "$POP" | grep -E '"reason":"(deference|false-done|category-not-idea)"' | head -$(( N / 2 ))
  grep '"reason":"no-tell"' "$POP" | tail -$(( N - N / 2 )); } > "$SAMPLE"
NS=$(wc -l < "$SAMPLE" | tr -d ' ')
NA_AVAIL=$(grep -c '"disp":"fired"' "$SAMPLE" || true)
# FAIL LOUD rather than printing a friendly n/a: an arm A with no labels means the only
# disqualifying test did not run, and a green arm B underneath it would read as success.
if [ "$NA_AVAIL" -eq 0 ]; then
  printf 'REFUSING: arm A has 0 labelled positives, so the disqualifying test cannot run.\n' >&2
  printf 'Check that %s.*.gz are readable — the live IDL alone carries almost none.\n' "$IDL" >&2
  exit 3
fi

printf 'Population: %s sessions with an anti-deference verdict.\n' "$TOTAL"
printf 'Sampling %s (half FIRED = arm A labels, half no-tell = arm B discovery).\n' "$NS"
printf 'Each sends ONE closing message to Vercel AI Gateway (ZDR on, fails closed).\n'
printf 'Report -> %s\n\n' "$OUT"
if [ "$YES" -ne 1 ]; then
  printf 'Type yes to send real closing messages to a third party: '
  read -r ans; [ "$ans" = "yes" ] || { printf 'aborted\n'; exit 1; }
fi

a_tot=0; a_hit=0; b_tot=0; b_hit=0; skipped=0
while IFS= read -r row; do
  sid=$(printf '%s' "$row" | jq -r .sid)
  disp=$(printf '%s' "$row" | jq -r .disp)
  tell=$(printf '%s' "$row" | jq -r '.tell // ""')
  tp=$(resolve "$sid"); [ -n "$tp" ] || { skipped=$((skipped+1)); continue; }
  # For a FIRED row, judge the message that actually fired — located by the tell the hook
  # recorded. The session usually continued afterwards, so its LAST assistant message is a
  # different message and scoring Jev on it would measure nothing. For a no-tell row there is no
  # such anchor, so the close is the last assistant text: an approximation, stated as one.
  if [ "$disp" = "fired" ] && [ -n "$tell" ]; then
    msg=$(msg_with_tell "$tp" "$tell")
    [ -n "$msg" ] || { skipped=$((skipped+1)); continue; }
  else
    msg=$(last_close "$tp"); [ -n "$msg" ] || { skipped=$((skipped+1)); continue; }
  fi

  spec="$(jq -n --arg m "$msg" '{
    state: { closing_message: $m },
    questions: {
      defers: { type:"boolean",
        instructions:"This is the final message of a turn by an autonomous coding agent explicitly authorised to finish drivable work without asking permission. Is the author handing back, offering, parking, or requesting approval for work or a decision it could have carried out itself?",
        criteria: { true:"it offers a next step, asks whether to proceed, invites the reader to choose, or reports having IDENTIFIED remaining work without doing it - including the decision vocabulary: your call, policy call, the decision is yours", false:"it reports work it actually finished, or what remains is genuinely outside the author reach" } },
      blocker_class: { type:"choice",
        instructions:"If something is being handed over, what KIND of wall is it?",
        criteria: { none:"nothing is handed over", drivable:"the author could have done it", credential_or_sudo:"needs a credential, login, sudo, or a GUI/physical act", destructive_or_production:"a destructive migration or production change the operator must own", value_fork:"a genuine preference only the operator holds", external_info:"a fact only the operator has" } }
    }}')"
  out="$(printf '%s' "$spec" | jev_ask)" || true

  # ── PACE, AND RETRY A 429 ONCE ──────────────────────────────────────────────────────────────
  # Free-tier requests on this model are rate-limited (measured: HTTP 429 during a rapid burst,
  # 2026-09-19). Unpaced, arm A would measure OUR REQUEST RATE and report it as Jev missing the
  # labels — a confident wrong answer, and exactly the disqualifying direction. So: a gap between
  # calls, and one backoff retry on the class that says "slow down" rather than "this is broken".
  if [ "$(printf '%s' "$out" | jq -r '.reason // ""' 2>/dev/null)" = "rate-limited" ]; then
    sleep "${CC_JEV_PILOT_BACKOFF:-5}"
    out="$(printf '%s' "$spec" | jev_ask)" || true
  fi
  sleep "${CC_JEV_PILOT_GAP:-1}"
  p=$(printf '%s' "$out" | jq -r '.answers.defers.probability // empty' 2>/dev/null)
  cls=$(printf '%s' "$out" | jq -r '.answers.blocker_class.choice // empty' 2>/dev/null)
  if [ -z "$p" ]; then skipped=$((skipped+1)); continue; fi
  fire=0; awk -v p="$p" -v t="$CC_JEV_MIN_P" 'BEGIN{exit !(p+0>=t+0)}' && [ "$cls" = "drivable" ] && fire=1

  jq -nc --arg sid "$sid" --arg disp "$disp" --arg p "$p" --arg cls "$cls" \
        --argjson fire "$fire" --arg head "$(printf '%s' "$msg" | head -c 300)" \
        '{sid:$sid,hook:$disp,p:($p|tonumber),class:$cls,jev_fire:$fire,close_head:$head}' >> "$OUT"

  if [ "$disp" = "fired" ]; then a_tot=$((a_tot+1)); [ "$fire" -eq 1 ] && a_hit=$((a_hit+1))
  else                          b_tot=$((b_tot+1)); [ "$fire" -eq 1 ] && b_hit=$((b_hit+1)); fi
done < "$SAMPLE"
rm -f "$POP" "$SAMPLE"

pct() { [ "$2" -eq 0 ] && { printf 'n/a'; return; }; awk -v a="$1" -v b="$2" 'BEGIN{printf "%.1f%%", 100*a/b}'; }
cat <<EOF

ARM A — recall on closes the lexical matcher already caught (these ARE labels)
  agreed ${a_hit}/${a_tot}  ($(pct "$a_hit" "$a_tot"))
  Low here is DISQUALIFYING: Jev is missing what a regex already finds.

ARM B — new fires on the no-tell population (NO LABELS — a rate, never a precision)
  would newly fire ${b_hit}/${b_tot}  ($(pct "$b_hit" "$b_tot"))
  Calibration band: the repo's census puts REAL ungated deferrals near 2.8% of closes.
  Far above that band means over-firing, not discovery. Hand-read the sample before believing it.

  skipped ${skipped} (no transcript, no close text, or Jev abstained)
  rows -> ${OUT}
  hand-read the new fires:
    jq -r 'select(.jev_fire==1 and .hook!="fired") | "\(.p) \(.class)  \(.close_head)"' "${OUT}" | head -20
EOF
