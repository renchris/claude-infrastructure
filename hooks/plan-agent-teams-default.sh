#!/bin/bash
# PreToolUse hook — injects the EXECUTION LOCUS decision point BEFORE work is written. TWO branches,
# because the rule has two arrival paths and for a year it only guarded one:
#   BRANCH 1 (plan files, original)   — "Agent Teams = default" context before a plan is written.
#   BRANCH 2 (source files, 2026-08-11, backlog item 14bcdfee2eb8) — the ACCUMULATING locus check for
#                                       implementation that never touches a plan file at all.
# Non-blocking on both paths. Branch 1 keeps permissionDecision:allow; branch 2 deliberately does NOT
# (see its header — it must not widen auto-approval to every source file).
#
# ── WHY BRANCH 2 EXISTS (docs/ground-up-payloads/LOCUS-GAP-BRIEF-2026-08-08.md) ───────────────────
# The Execution Locus rule (global CLAUDE.md § Agent Teams; plan-conventions skill) was enforced ONLY
# on the plan-authoring path: this hook's own case list at branch 1 and validate-plan-structure.sh's
# matching one both gate on plan-file PATHS. So the locus decision point existed only if the agent
# WROTE A PLAN FILE — and implementation that arrives as operator feedback never does. In the session
# that produced the brief, four implementation slices arrived as corrections ("the URL is stale",
# "these toggles make no sense", …), each produced real code, none began at a plan edit, and the lead
# ran all of them inline without ever writing the one-line justification locus L requires. This hook
# fired EXACTLY ONCE there, on a RETROSPECTIVE plan-doc write made after the code was already
# written, gated and landed — correct text, arriving after the decision it exists to govern.
#
# ── THE HARDER HALF: SALAMI-SLICING ──────────────────────────────────────────────────────────────
# No single operator correction looks like a wave. Slice 1 inline is genuinely defensible. Slices 1-4
# inline is a wave, and by then the lead had spent its window on ~15 browser round trips, 4 gate runs
# and 3 lands. So a correctly-placed sensor is still not enough — it has to ACCUMULATE ACROSS TURNS.
# The question is not "is this task big" but "is this the Nth implementation slice in one session".
# Hence a session-keyed slice counter, not a per-edit test.
#
# ── WHY *HERE* AND NOT AT Stop OR UserPromptSubmit (the brief's three candidates, argued) ─────────
#   · Stop — arrives after the decision it governs, which is the exact failure mode above. It is no
#     longer true that an advisory Stop hook is inert (global CLAUDE.md corrected 2026-08-08:
#     additionalContext DOES reach the model at Stop), but it is not free either — it forces another
#     turn and increments the same block counter the harness caps at 8. Too late AND not cheap.
#   · UserPromptSubmit — would have to CLASSIFY the incoming prompt as implementation-shaped, which
#     is judgment-bound (the brief's constraint 2) and a keyword denylist over operator prose besides
#     (MEMORY.md denylist-enumerates-spellings-not-the-class). It also fires at slice 1, when inline
#     is defensible.
#   · PreToolUse on the edit itself — the chokepoint: the moment of the act, before it, with slices
#     N.. still ahead to dispatch (MEMORY.md enforcement-must-live-at-the-chokepoint). Extending THIS
#     already-registered hook rather than adding a new one also means no settings.json change (C10)
#     and no new file for the live layer to converge (MEMORY.md: a landed diff that ADDS a file is
#     absent, not stale, until the converger runs — an EDIT rides its existing symlink).
#
# ── THE PREDICATE IS FACT-BOUND, AND MEASURED RATHER THAN GUESSED ────────────────────────────────
# Fires when: file is a source file ∧ this is the Nth distinct turn in which this session wrote one
# (N ≥ CC_LOCUS_SLICE_MIN, default 3) ∧ not a team assignee ∧ not already fired this session ∧ no
# operator kill-switch. Measured at EXACT predicate parity over 163 sessions (4 days, 2026-08-11):
# ≥3 slices = 4/163 (2.5%, ~1 fire/day fleet-wide), ≥4 = 1/163. Latched to ONE fire per session. That
# rarity is the point — constraint 3 of the brief is "do not build a nag", and a sensor that fires on
# every source edit is ignored inside a day, which is how the original one failed.
#
# WHY THE THRESHOLD IS 3 AND NOT 4 — the founding case decides it, not taste. Replaying the evidence
# session (tests/fixtures/locus-evidence-session.jsonl, distilled from the real transcript) it scores
# exactly 3 source slices: the 6 counted in the brief's own prose collapse to 3 once plan/doc `.md`
# and `/tmp` briefs are excluded, which they must be — a doc edit is not an implementation slice. So
# a threshold of 4 would NEVER have fired on the very session that motivated this branch, at 4× the
# rarity. At 3 the fire lands at record 38 of that session's 65 (on its Harness.tsx edit), i.e. with
# 42% of it still ahead to dispatch — the property that makes the injection govern anything at all.
#
# ── TWO GATES DELETED BY THEIR OWN POSITIVE CONTROL (do not re-add) ──────────────────────────────
# The brief's evidence session (reso worktree wt-cc-005159-55873, transcript 462e36d1) measures
# 6 slices / 43 source edits. Two "obvious" exemptions were drafted and then REFUTED by replaying it:
#   · "exempt sessions that dispatch" — that session fired real handoff-fire peers (with
#     --notify-back) and STILL ran 6 slices inline. The gate would have exempted the one session this
#     branch was written about. Dispatch-capability was present; per-slice locus judgment is what
#     failed, so session-wide dispatch says nothing.
#   · "exempt fired peers" — same trap one layer down. A fired peer is the lead of its own team and
#     CAN dispatch (global CLAUDE.md § Agent Teams), and the evidence session was operator-driven
#     from its first message. Only TEAM ASSIGNEES are exempt: an assignee is scoped to one brief
#     inside its lead's work and has no authority to dispatch fleet work — the same reasoning
#     dispatch-assert.sh applies at its own assignee guard.
# (MEMORY.md positive-control-the-denominator / guard-proxy-fails-in-both-directions.)
#
# ── WHY THE EXISTING GUARDS DO NOT COVER THIS (inventory before building) ────────────────────────
# dispatch-assert.sh already blocks NARRATED-not-dispatched work, but its fire predicate is a prose
# naming-tell ("deserves its own pass", "follow-up item"). Operator-feedback slices produce no naming
# tell at all — the lead simply does the work — so it is structurally blind to this class. Different
# signal, different defect; neither hook subsumes the other.
#
# Env seams (tests): CC_LOCUS_SLICE_MIN · CC_LOCUS_STATE_DIR · CC_LOCUS_IDL · CC_LOCUS_TAIL_BYTES ·
#   CC_LOCUS_DISABLE · CLAUDE_CONFIG_DIR.
# Fail-safe: EVERY path exits 0 (a PreToolUse hook exiting 2 BLOCKS the tool call); any read/jq
# failure abstains silently.

set -uo pipefail

command -v jq &>/dev/null || exit 0

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

[ -z "$FILE" ] && exit 0

CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
LOCUS_STATE_DIR="${CC_LOCUS_STATE_DIR:-$CFG/state/locus-slice}"
LOCUS_IDL="${CC_LOCUS_IDL:-$CFG/autonomy/idl.jsonl}"
LOCUS_MIN="${CC_LOCUS_SLICE_MIN:-3}"
LOCUS_TAIL="${CC_LOCUS_TAIL_BYTES:-262144}"

# A SOURCE file = code/config the model writes as implementation. Deliberately NOT *.md: docs and
# plans are branch 1's business (and a doc edit is not an implementation slice). Runtime state dirs
# are excluded so the machine's own bookkeeping never counts as a slice.
_locus_is_source() {
  local l
  l="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')"
  case "$l" in
    /tmp/*|/private/tmp/*|*/scratchpad/*|*/node_modules/*|*/.next/*|*/dist/*|*/build/*|*/.git/*) return 1 ;;
    */state/*|*/logs/*|*/autonomy/*|*/backups/*) return 1 ;;
  esac
  case "$l" in
    *.sh|*.bash|*.zsh|*.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs|*.py|*.rb|*.go|*.rs|*.sql|*.css|*.scss|*.toml|*.yaml|*.yml|*.json) return 0 ;;
  esac
  return 1
}

# BRANCH 2 — see the header. Returns 0 always; emits JSON on stdout only when it fires.
_locus_source_branch() {
  local sid cwd tp slug tail_txt turn last_txt skey slices n lib jq_user msg
  [ "${CC_LOCUS_DISABLE:-0}" = "1" ] && return 0
  _locus_is_source "$FILE" || return 0

  # Team assignees only — never fired peers. See "TWO GATES DELETED" in the header.
  lib="$CFG/hooks/lib/agent-identity.sh"
  [ -f "$lib" ] || lib="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/lib/agent-identity.sh"
  # shellcheck source=lib/agent-identity.sh
  # shellcheck disable=SC1090,SC1091  # runtime-resolved source; the ship gate runs shellcheck without -x
  if [ -f "$lib" ] && . "$lib" 2>/dev/null; then
    [ -n "$(agent_is_assignee 2>/dev/null || true)" ] && return 0
  fi

  sid="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)"
  cwd="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)"
  tp="$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || true)"
  case "$tp" in "~"*) tp="$HOME${tp#\~}" ;; esac
  # Resolve the transcript ourselves when the payload does not carry it: the harness stores it at
  # projects/<cwd with / and . replaced by ->/<session_id>.jsonl (verified 2026-08-11). A lookup that
  # can only MISS is not an absence (MEMORY.md lookup-miss-is-not-absence), so do not depend on one field.
  if [ ! -f "${tp:-/nonexistent}" ] && [ -n "$sid" ] && [ -n "$cwd" ]; then
    slug="$(printf '%s' "$cwd" | tr '/.' '--')"
    tp="$CFG/projects/$slug/$sid.jsonl"
  fi
  [ -f "${tp:-/nonexistent}" ] || return 0

  skey="$(printf '%s|%s|%s' "$CFG" "${sid:-?}" "${cwd:-?}" | shasum 2>/dev/null | cut -c1-16)"
  [ -n "$skey" ] || return 0
  mkdir -p "$LOCUS_STATE_DIR" 2>/dev/null || true
  find "$LOCUS_STATE_DIR" \( -name '*.slices' -o -name '*.fired' \) -mtime +7 -delete 2>/dev/null || true
  # The latch. Session-keyed, so a RECYCLE resets it — and that is correct, not a leak: the counter
  # exists to protect THIS window, and a recycled pane has a fresh one to protect.
  [ -f "$LOCUS_STATE_DIR/$skey.fired" ] && return 0

  # The slice token is the ts of the last GENUINE operator message. `isMeta:true` is the structural
  # discriminator for a hook-injected user record — a Stop-hook block reason re-enters the transcript
  # AS a user message (dispatch-assert.sh's own header notes this), and measured 2026-08-11 every
  # injected record carries isMeta:true while real prompts never do. Without that filter each blocked
  # stop would mint a fake slice and walk the count toward a false fire.
  jq_user='select(.type=="user" and (.isSidechain != true) and (.isMeta != true) and (.toolUseResult == null))
           | select(((.message.content|type)=="string")
                    or ([.message.content[]?|select(.type=="text")]|length > 0))'
  # Common branch: a bounded tail. `tail -n +2` drops the partial first line the byte-cut leaves —
  # but ONLY when the cut actually happened: on a transcript smaller than the window it would discard
  # a COMPLETE first record, silently losing the session's opening operator turn (and with it slice 1
  # of every short session). Caught by the real-artifact replay in tests/plan-agent-teams-locus.bats,
  # not by any synthetic case. Instrument the volume, not the rare branch (MEMORY.md
  # diagnostic-ladder-skipped-by-the-common-branch).
  local fsize
  fsize="$(wc -c < "$tp" 2>/dev/null | tr -d ' ')"
  case "$fsize" in ''|*[!0-9]*) fsize=0 ;; esac
  if [ "$fsize" -gt "$LOCUS_TAIL" ]; then
    tail_txt="$(tail -c "$LOCUS_TAIL" "$tp" 2>/dev/null | tail -n +2 || true)"
  else
    tail_txt="$(cat "$tp" 2>/dev/null || true)"
  fi
  turn="$(printf '%s\n' "$tail_txt" | jq -r "$jq_user | (.timestamp // \"\")[0:19] | select(. != \"\")" 2>/dev/null | tail -1 || true)"
  # Rare branch: a long grinding turn can push the operator message out of the window. Read the whole
  # file rather than lose the count — 66 ms over 10 MB (session-writes.sh header), and this is capped
  # at one fire per session anyway.
  if [ -z "$turn" ]; then
    turn="$(jq -r "$jq_user | (.timestamp // \"\")[0:19] | select(. != \"\")" "$tp" 2>/dev/null | tail -1 || true)"
  fi
  [ -n "$turn" ] || return 0

  # Kill-switch: the operator's per-prompt suspension (same phrase list as session-continue (a)).
  last_txt="$(printf '%s\n' "$tail_txt" | jq -r "$jq_user
      | .message.content
      | if type==\"string\" then . elif type==\"array\" then ([.[]?|select(.type==\"text\")|.text]|join(\"\n\")) else empty end
      | select(. != \"\")" 2>/dev/null | tail -1 || true)"
  if [ -n "$last_txt" ] && printf '%s' "$last_txt" | grep -iqE \
      '(^|[^[:alnum:]])and( then)? stop([^[:alnum:]]|$)|no[ _-]?auto[ _-]?continue|(^|[^[:alnum:]])just do [^[:space:]]|(^|[^[:alnum:]])stop here([^[:alnum:]]|$)|come back to this'; then
    return 0
  fi

  slices="$LOCUS_STATE_DIR/$skey.slices"
  grep -qxF "$turn" "$slices" 2>/dev/null || printf '%s\n' "$turn" >> "$slices" 2>/dev/null || true
  n="$(grep -c . "$slices" 2>/dev/null || echo 0)"
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  [ "$n" -ge "$LOCUS_MIN" ] 2>/dev/null || return 0

  : > "$LOCUS_STATE_DIR/$skey.fired" 2>/dev/null || true
  mkdir -p "$(dirname "$LOCUS_IDL")" 2>/dev/null || true
  jq -cn --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo '?')" --arg sid "${sid:-?}" \
        --arg file "$FILE" --arg n "$n" --arg min "$LOCUS_MIN" \
    '{ts:$ts,hook:"plan-agent-teams-default",sid:$sid,disposition:"fired",
      reason:"inline-slice-accumulation",slices:($n|tonumber?),threshold:($min|tonumber?),file:$file}' \
    >> "$LOCUS_IDL" 2>/dev/null || true

  # No permissionDecision, deliberately: branch 1's `allow` is pre-existing behaviour for plan files,
  # and reusing it here would auto-approve every source-file write on the firing turn — a silent
  # widening of auto-approval that has nothing to do with this fix. additionalContext alone is
  # delivered on PreToolUse (backup-before-write.sh's OVERWRITE GUARD ships exactly this shape).
  msg="EXECUTION LOCUS — inline implementation slice #${n} of this session (a fact, not a judgement: source files were written in ${n} distinct operator turns, and every one ran on THIS context, locus L). Slice 1 inline is defensible and often right — an investigative slice, one needing the live system, or work smaller than the brief that would describe it; a dispatch round trip can genuinely be slower than the fix. Slices 1-${n} inline is a WAVE that was never declared one, and the lead's own window is what paid for it: a teammate's output and a lead's both land HERE, a dispatched session's does not (global CLAUDE.md § Agent Teams). Make the locus a decision instead of a default — one of: (S) dispatch the remaining slices — scripts/handoff-fire.sh --prompt-file <brief> --worktree <br> --notify-back <lead-uuid> --goal '<measurable end state> — proven by <the command the session runs and prints>; do not <constraint>'; (T) in-session teammates via Agent({name}) when they must be synthesised against each other immediately AND their combined output is small; (L) keep it inline — legitimate, but then say in ONE line why this slice is the defensible inline case. Then proceed: nothing is blocked and this fires once per session."
  jq -n --arg msg "$msg" '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$msg}}' 2>/dev/null || true
  return 0
}

# === PLAN FILE DETECTION ===
IS_PLAN=false
case "$FILE" in
  "$HOME/.claude/plans/"*.md)                    IS_PLAN=true ;;
  *"/.claude-plans/"*.md)                        IS_PLAN=true ;;
  *"/docs/plans/"*.md)                           IS_PLAN=true ;;
  docs/plans/*.md)                               IS_PLAN=true ;;
  *"/AGENT_TEAM"*".md")                          IS_PLAN=true ;;
  *"PLAN"*".md")                                 IS_PLAN=true ;;
  *"plan"*".md")                                 IS_PLAN=true ;;
esac

# NOT a plan file ⇒ branch 2 (the locus gap: implementation that never touches a plan). This line
# used to be a bare `exit 0`, which is precisely why the rule only ever governed plan authoring.
[ "$IS_PLAN" = false ] && { _locus_source_branch; exit 0; }

# Check if this is an implementation plan (not just a research doc named "plan")
# Look for implementation keywords in the file content if it exists
if [ -f "$FILE" ]; then
  if ! grep -qEi "Phase [1-9]|Implementation|Wave [1-9]|Task [1-9]|Sprint|Milestone|Team|Teammate" "$FILE" 2>/dev/null; then
    # New plan file (doesn't exist yet) or no implementation keywords — still inject context
    # because the model is about to write implementation content
    :
  fi
fi

cat <<'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "additionalContext": "PLAN DEFAULTS: This is a plan file. Include Phase 0 (Agent Team Orchestration) as the FIRST section. Its FIRST field is the EXECUTION LOCUS PER WAVE — where the wave runs, which decides whose context pays for it: S = dispatched handoff session (handoff-fire.sh --prompt-file <brief> --worktree <br> --notify-back <lead-uuid> --goal '<measurable end state> — proven by <the command the session runs and prints>; do not <constraint>'; the DEFAULT for every implementation wave, needs no justification — and --goal is itself the default on every wave fire, one end state per wave, because the goal evaluator is tool-less and can judge only what the session PRINTS) | T = in-session teammates via Agent({name}) — their output lands in the LEAD's window, so justify in one line | L = lead-inline, justify in one line. Then: team roster, task dependency graph, worktree assignments, spawn wave order, and the LEAD's own context budget + succession point. Background subagents remain research/exploration only (no code changes). Rules + rationale: the plan-conventions skill (SSOT). Teammate lifecycle: the agent-teams skill."
  }
}
EOF
