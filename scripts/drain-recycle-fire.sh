#!/usr/bin/env bash
# drain-recycle-fire.sh — FIRE THE NEXT LINK OF THE 24/7 DRAIN CHAIN, WITH ITS GOAL ATTACHED.
#
# ── THE DEFECT THIS CLOSES ──────────────────────────────────────────────────────────────────────
# BACKLOG_DRAIN_24_7 §4.1 is the SSOT the drain chain regenerates its brief from, and its fire
# command has carried a `--goal` since the template was written. The live chain does not. Measured
# 2026-08-31 over ~/.claude/logs/handoffs.jsonl, which records `goal_requested` on the fire's OWN
# row: **183 recycle-intent fires with `goal_requested:false` against 46 true**, and every one of
# the last forty is false. So for 279 links nothing mechanically bound a recycle to closing a
# backlog row, and the measured result is what DRAIN_CIRCUIT_2026-09-01 §1.4 names: over 7 days,
# **304 trunk commits against 30 backlog closures** — ~10 commits per closure — with the entire file
# footprint being the drain machinery itself. Each recycle audits the recycle before it.
#
# WHY THE TEMPLATE ALONE COULD NOT HOLD, AND WHY THIS IS A SCRIPT. §4.1's fire command is prose a
# session retypes each cycle, and the chain has DIVERGED from it: the brief outgrew a promptable
# payload, so the chain invented a 152-byte pointer (`fire-pointer-<N>.txt`) and fires that instead.
# The divergence was correct; what went with it was the `--goal`, because a hand-retyped command
# loses whatever the retyper does not think of. `handoff-fire.sh --recycle` also INHERITS the
# predecessor's live goal when none is passed (scripts/handoff-fire.sh §GOAL INHERITANCE), so a
# single link that dropped the goal makes every link after it goal-less by construction — which is
# exactly the 183-to-46 shape. A rule that is retyped is a rule that decays; a rule that is a
# CHOKEPOINT does not (memory `enforcement-must-live-at-the-chokepoint`). This file is that
# chokepoint: the goal is not an argument the caller may forget, it is what the caller invokes.
#
# ── THE CLOSURE FLOOR, AND WHY IT LIVES IN THE GOAL RATHER THAN IN THIS SCRIPT ───────────────────
# §4.1 invariant 4 already says "Conservation: close >= file, printed in the close", and §4.1
# invariant 6 says "THE CHAIN IS THE DELIVERABLE: firing recycle #N+1 outranks finishing one more
# row". Read together, a link that files three rows, closes none, and fires its successor has obeyed
# the ranked invariant and merely skipped the unranked one. Over 278 cycles it did.
#
# The floor therefore goes into the GOAL CONDITION, which is the only surface on this box that can
# refuse to let a session stop: the evaluator re-judges after every turn and blocks the Stop until
# the condition is met. It is NOT enforced by this script refusing to fire — that would be the one
# failure mode the chain cannot survive, a link that ends with no successor. Firing stays
# unconditional; what the goal changes is that the session cannot reach the fire having discharged
# nothing.
#
# THE CHECK IS PRINTED, NOT ASSERTED IN PROSE. The goal evaluator is a separate TOOL-LESS model that
# sees only what the session SURFACES, so a condition naming state nobody prints is unreachable and
# can never clear. `--closure-report` is that surface: it prints its own predicate and a
# `floor=MET|UNMET` token computed from the ledger, so the evaluator judges a tool's output rather
# than the session's self-report (memory `claimed-outcome-vs-checked-outcome`).
#
# ── 2026-09-04: THE BRIEF IS GENERATED HERE TOO (BACKLOG_ZERO_2026-09-04 §3) ─────────────────────
# The goal alone was not enough. The live chain never called this wrapper (every one of its last
# eight fires still logged goal_requested:false) and regenerated each brief from its PREDECESSOR'S,
# which by #299 was 3,366 lines with no `cc-backlog claim` left in it. So with no --prompt-file this
# wrapper now writes the successor's brief and pointer from scripts/drain-brief.template.md via
# scripts/drain-brief.sh, and the floor counts PRE-EXISTING rows of THIS lane's project closed by
# THIS lane (closed_pre >= --min, default 3): a link cannot hand its successor anything it wrote,
# and cannot meet the floor on rows it minted or on another lane's closes.
#
# Usage:
#   drain-recycle-fire.sh --num <N+1> [--lane infra] [--project P] [--min 3] [--worktree <abs>]
#                         [handoff-fire args...]
#                                     generate recycle N+1's brief + pointer, arm the goal, and
#                                     --recycle THIS pane into it (the ordinary link-to-link fire)
#   drain-recycle-fire.sh --num <N> --lane L --first [--split-right] [--account auto]
#                                     open a NEW pane for a chain's first link (never recycles the
#                                     caller); provisions the default lane worktree if absent
#   drain-recycle-fire.sh --num <N+1> --prompt-file <pointer> [handoff-fire args...]
#                                     fire a caller-supplied brief verbatim (tests, a hand lane)
#   drain-recycle-fire.sh --num <N+1> [--lane L --project P --min M] --print-goal
#                                     print the condition and exit — no side effect, and the way
#                                     to read back what a fire WOULD arm
#   drain-recycle-fire.sh --closure-report <ISO-8601-Z> [--min M]
#                                     closed / closed_pre / closed_other / filed / net / blocked
#                                     since that instant, with the ids, the predicate and the floor
#                                     verdict. THE COMMAND THE GOAL CONDITION NAMES.
# Env:
#   CC_BACKLOG_FILE     the ledger (default $CLAUDE_CONFIG_DIR/autonomy/backlog.jsonl)
#   CC_DRAIN_PROJECT    default claude-infrastructure — the project the lane drains
#   CC_DRAIN_LANE       default infra · CC_DRAIN_MIN_CLOSED default 3
#   CC_DRAIN_FLOOR_LANE the `lane` a done record must carry to count (default local-drain)
#   CC_DRAIN_FIRE_BIN   default $REPO/scripts/handoff-fire.sh — the fire path, injectable for tests
#   CC_DRAIN_BRIEF_BIN  default $REPO/scripts/drain-brief.sh — the generator, injectable for tests
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$HERE")"
CFG="${CLAUDE_CONFIG_DIR:-${HOME:-}/.claude}"
LEDGER="${CC_BACKLOG_FILE:-$CFG/autonomy/backlog.jsonl}"
PROJECT="${CC_DRAIN_PROJECT:-claude-infrastructure}"
FIRE_BIN="${CC_DRAIN_FIRE_BIN:-$REPO/scripts/handoff-fire.sh}"

die() { printf 'drain-recycle-fire: %s\n' "$1" >&2; exit 2; }

# ── the closure report — the goal condition's printed check ─────────────────────────────────────
# Counts DISTINCT ids, not events: a row closed, reopened and closed again inside one recycle is one
# closure, and counting events would let a single row satisfy the floor twice. `add` is the filing
# verb; cc-backlog's own update arm re-emits `add` for a known id, so the same distinct-id fold is
# what keeps a title refresh from reading as a new filing.
#
# THE FLOOR IS ON PRE-EXISTING ROWS (2026-09-04). The first floor — `closed >= 1 AND closed >= filed`
# — was satisfiable by closing one row a link had itself just filed, and was UNMET whenever a
# SIBLING filed rows inside the window, which the store cannot attribute (add records carry no
# session). Both halves pointed the wrong way: the drain's job is the STANDING pile. So the floor
# now counts `closed_pre` — rows closed in the window whose FIRST add is OLDER than the window — and
# requires `closed_pre >= min` (default CC_DRAIN_MIN_CLOSED=3). `filed` and `net` are still printed:
# they are the conservation readout, and a link that files is told so in the goal, not by this
# number.
closure_report() {
  local since="$1" min="${2:-${CC_DRAIN_MIN_CLOSED:-3}}" out
  case "$since" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T*Z) : ;;
    *) die "--closure-report needs an ISO-8601 Z timestamp (e.g. 2026-09-01T07:00:00Z), got '$since'" ;;
  esac
  case "$min" in ''|*[!0-9]*) die "--min must be digits, got '${min:-}'" ;; esac
  command -v jq >/dev/null 2>&1 || die "jq is required"
  [ -r "$LEDGER" ] || die "no readable ledger at $LEDGER"

  # LANE- AND PROJECT-SCOPED (2026-09-04). The first floor counted every `done` in the window from
  # any lane — measured over the #298 window it read closed=2 and BOTH were somebody else's (one
  # `lane=land`, one the successor's). `done` records carry `lane` (derived by cc-backlog from the
  # closer's ancestry and cwd; a session under the drain root reads `local-drain`) and the id's
  # project comes from its add record, so both are folded here: only a local-drain close of a row in
  # THIS lane's project counts toward the floor. Other lanes' closes are printed as `closed_other`
  # so the reader sees them and the floor does not.
  out="$(jq -rs --arg since "$since" --argjson min "$min" --arg proj "$PROJECT" --arg lane "${CC_DRAIN_FLOOR_LANE:-local-drain}" '
    ( [ .[] | select((.ts // "") >= $since) ] ) as $w
    | ( [ .[] | select(.event == "add") ] | group_by(.id) | map({key: .[0].id, value: (map(.ts) | min)}) | from_entries ) as $first_add
    | ( [ .[] | select(.event == "add") ] | group_by(.id) | map({key: .[0].id, value: (.[0].project // "")}) | from_entries ) as $project_of
    | ( [ $w[] | select(.event == "done") ] ) as $dones
    | ( [ $dones[] | select((.lane // "") == $lane) | .id ] | unique ) as $closed_ids
    | ( [ $dones[] | select((.lane // "") != $lane) | .id ] | unique ) as $other_ids
    | ( [ $closed_ids[] | select(($first_add[.] // "9999") < $since and ($project_of[.] // "") == $proj) ] ) as $pre_ids
    | ( [ $w[] | select(.event == "add")   | .id ] | unique ) as $filed_ids
    | ( [ $w[] | select(.event == "block") | .id ] | unique ) as $blocked_ids
    | ($closed_ids | length) as $closed | ($pre_ids | length) as $pre | ($other_ids | length) as $other
    | ($filed_ids | length) as $filed | ($blocked_ids | length) as $blocked
    | "closed=\($closed) closed_pre=\($pre) closed_other=\($other) filed=\($filed) net=\($closed - $filed) blocked=\($blocked) min=\($min) lane=\($lane) project=\($proj) floor=" +
      (if $pre >= $min then "MET" else "UNMET" end)
      + "\nclosed_ids: " + ($closed_ids | join(" "))
      + "\nclosed_pre_ids: " + ($pre_ids | join(" "))
      + "\nclosed_other_ids: " + ($other_ids | join(" "))
      + "\nfiled_ids: " + ($filed_ids | join(" "))
      + "\nblocked_ids: " + ($blocked_ids | join(" "))
  ' "$LEDGER" 2>/dev/null)" || out=""
  [ -n "$out" ] || die "could not fold the ledger at $LEDGER"

  printf 'DRAIN CLOSURE REPORT — %s --closure-report %s --min %s\n' "${BASH_SOURCE[0]}" "$since" "$min"
  printf 'predicate: DISTINCT ids per event since the instant above, over the whole ledger.\n'
  printf '           closed = ids with a done event whose lane is THIS lane (cc-backlog stamps lane from\n'
  printf '           the closer; a session under the drain root reads local-drain) · closed_pre = those\n'
  printf '           whose FIRST add is older than the window AND whose project is this lane%ss (the\n' "'"
  printf '           standing pile, not rows filed and closed inside one link) · closed_other = done\n'
  printf '           events from any other lane, shown and never counted · filed = ids with an add\n'
  printf '           event (a title refresh re-emits add on a KNOWN id, so distinct-id is what keeps it\n'
  printf '           from reading as a filing) · net = closed - filed · blocked = ids routed to the operator.\n'
  printf 'floor:     MET requires closed_pre >= min. A recycle that discharges nothing pre-existing is\n'
  printf '           UNMET however much it committed or filed — DRAIN_CIRCUIT_2026-09-01 §1.4.\n'
  printf 'ledger:    %s\n' "$LEDGER"
  printf '%s\n' "$out"
  case "$out" in *floor=MET*) return 0 ;; *) return 1 ;; esac
}

# ── the goal condition ──────────────────────────────────────────────────────────────────────────
# ONE LINE, no leading slash, well under the harness's 4000-char cap — all three are refused by
# handoff-fire.sh's check_goal_arm, and a refusal here would cost the chain a link.
#
# THE ORDER OF CLAUSES IS THE FIX. §4.1 records that #124 skipped its ping because the ping had "no
# position in the sequence at all" while the fire did — a duty with no position ahead of the fire is
# unreachable the moment the session takes the goal at its word. The closure floor is that same
# lesson applied to invariant 4: it is stated FIRST and the fire LAST, so invariant 6 is subordinate
# by position and not merely by prose.
goal_condition() {
  local n="$1" since="$2" min="$3" lane="$4" project="$5"
  printf '%s' "recycle #${n} of the 24/7 backlog drain (lane ${lane}, project ${project}) has DISCHARGED PRE-EXISTING BACKLOG ROWS, not audited its own machinery — proven by this session RUNNING and PRINTING \`bash scripts/drain-recycle-fire.sh --closure-report ${since} --min ${min}\` and that output reading floor=MET (closed_pre >= ${min}: rows closed in this window whose first filing is OLDER than the window); every closed row carries same-moment evidence (a command and its output, or a sha whose content is verified on origin/main); every fix is LANDED on origin/main, since a commit on a branch is not a close; this session has run NO \`cc-backlog add\` of a new title and NO \`cc-backlog needs\` (it files nothing — a row it cannot finish is released with \`reopen --by\` or blocked with \`block --needs\`, never re-minted); the one §2.1 entry of at most 8 lines is committed and landed; then the HANDOFF-PING to the lead is SENT and its verdict printed; then recycle #$((n+1)) is FIRED with \`bash scripts/drain-recycle-fire.sh --num $((n+1)) --lane ${lane} --project ${project} --min ${min} --account auto\` as the LAST action and its engagement line printed. Constraints: do not edit scripts/drain-*, scripts/handoff-fire.sh, hooks/, the brief, or BACKLOG_DRAIN_24_7.md beyond that entry unless a claimed row's title names the file; do not satisfy the floor by closing without evidence or by counting another lane's closures; if the floor is still UNMET after adjudicating at least 6 rows, print id → verdict → evidence for every row touched before firing, rather than ending silently."
}

# ── argv ────────────────────────────────────────────────────────────────────────────────────────
NUM=""; PROMPT=""; MODE="fire"; SINCE=""; LANE="${CC_DRAIN_LANE:-infra}"; MIN="${CC_DRAIN_MIN_CLOSED:-3}"
WORKTREE=""; FIRST=0
PASS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --num)              NUM="${2:?--num needs the recycle number being FIRED}"; shift 2 ;;
    --prompt-file)      PROMPT="${2:?--prompt-file needs a path}"; shift 2 ;;
    --lane)             LANE="${2:?--lane needs a name}"; shift 2 ;;
    --project)          PROJECT="${2:?--project needs a label}"; shift 2 ;;
    --min)              MIN="${2:?--min needs a number}"; shift 2 ;;
    --worktree)         WORKTREE="${2:?--worktree needs an absolute path}"; shift 2 ;;
    --first)            FIRST=1; shift ;;
    --print-goal)       MODE="print"; shift ;;
    --closure-report)   MODE="closure"; SINCE="${2:?--closure-report needs an ISO-8601 Z timestamp}"; shift 2 ;;
    --since)            SINCE="${2:?--since needs an ISO-8601 Z timestamp}"; shift 2 ;;
    --help|-h)          sed -n '2,/^set -uo/p' "$0" | sed 's/^# \{0,1\}//; /^set -uo/d'; exit 0 ;;
    *)                  PASS+=("$1"); shift ;;      # everything else is handoff-fire's
  esac
done
case "$MIN" in ''|*[!0-9]*) die "--min must be digits, got '${MIN:-}'" ;; esac
case "$LANE" in ''|*[!a-z0-9-]*) die "--lane must be [a-z0-9-], got '${LANE:-}'" ;; esac

if [ "$MODE" = closure ]; then closure_report "$SINCE" "$MIN"; exit $?; fi

case "${NUM:-}" in ''|*[!0-9]*) die "--num must be the recycle number being fired (digits only)" ;; esac
# The window opens NOW by default: a link measures the rows IT discharged, never its predecessor's.
# An explicit --since lets a session that started earlier pin its own true start instant.
[ -n "$SINCE" ] || SINCE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
[ -n "$WORKTREE" ] || WORKTREE="${HOME:-}/Development/.worktrees/drain/lane-$LANE"
COND="$(goal_condition "$NUM" "$SINCE" "$MIN" "$LANE" "$PROJECT")"

# Fail fast on the three shapes handoff-fire refuses, so a malformed condition costs a message here
# rather than a link that fires without its goal.
case "$COND" in /*) die "the condition must not start with '/'" ;; esac
[ "$(printf '%s' "$COND" | wc -l | tr -d ' ')" = 0 ] || die "the condition must be ONE line"
[ "${#COND}" -lt 4000 ] || die "the condition is ${#COND} chars; the harness caps it at 4000"

if [ "$MODE" = print ]; then printf '%s\n' "$COND"; exit 0; fi

# ── THE BRIEF IS GENERATED HERE, NOT INHERITED (2026-09-04) ─────────────────────────────────────
# With no --prompt-file the wrapper regenerates the successor's brief and pointer from the
# checked-in template (scripts/drain-brief.sh) with THIS window's since/min stamped in. That is the
# whole cure for the old chain's accretion: a link cannot hand its successor anything but the
# template, because the fire path does not read what the link wrote. --prompt-file is kept for a
# caller that has its own brief (tests, a hand-built lane) and is used verbatim.
BRIEF_BIN="${CC_DRAIN_BRIEF_BIN:-$HERE/drain-brief.sh}"
if [ -z "$PROMPT" ]; then
  [ -r "$BRIEF_BIN" ] || die "no drain-brief.sh at $BRIEF_BIN and no --prompt-file given"
  PROMPT="$(bash "$BRIEF_BIN" --num "$NUM" --lane "$LANE" --project "$PROJECT" --worktree "$WORKTREE" \
             --since "$SINCE" --min "$MIN")" || die "drain-brief.sh refused to generate recycle #$NUM (lane $LANE) — see its stderr; nothing fired"
fi
[ -n "$PROMPT" ] || die "--prompt-file is required to fire (the pointer the brief lives behind)"
[ -r "$PROMPT" ] || die "--prompt-file $PROMPT is not readable — refusing to fire a link with no brief"
[ -r "$FIRE_BIN" ] || die "no handoff-fire at $FIRE_BIN"

# --first: the chain's FIRST link is fired from a lead's pane as a NEW pane on the lane's worktree,
# so it must not --recycle (that would relaunch the LEAD's pane). Every later link recycles itself.
# An existing worktree is entered with --cwd; a missing one is provisioned by handoff-fire's own
# --worktree path (off origin/main, under its WTROOT), which lands at exactly the default path the
# brief names. A custom --worktree that does not exist is refused: the brief would `cd` into nothing.
if [ "$FIRST" -eq 1 ]; then
  if [ -d "$WORKTREE" ]; then
    exec bash "$FIRE_BIN" --prompt-file "$PROMPT" --goal "$COND" --cwd "$WORKTREE" "${PASS[@]+"${PASS[@]}"}"
  fi
  [ "$WORKTREE" = "${HOME:-}/Development/.worktrees/drain/lane-$LANE" ] \
    || die "--first: worktree $WORKTREE does not exist and is not the default handoff-fire can provision (…/.worktrees/drain/lane-$LANE)"
  exec bash "$FIRE_BIN" --prompt-file "$PROMPT" --goal "$COND" --worktree "drain/lane-$LANE" "${PASS[@]+"${PASS[@]}"}"
fi
exec bash "$FIRE_BIN" --recycle --prompt-file "$PROMPT" --goal "$COND" "${PASS[@]+"${PASS[@]}"}"
