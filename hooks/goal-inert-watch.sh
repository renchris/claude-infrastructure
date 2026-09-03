#!/usr/bin/env bash
# goal-inert-watch.sh — Stop hook: say so when an armed `/goal` is being SKIPPED by Claude Code.
#
# THE DEFECT (measured 2026-08-09, docs/research/goal-in-handoff-2026-08-08.md § RESOLVED).
# `/goal <condition>` registers a `type:"prompt"` Stop hook. The FIRST thing CC's Stop handler does
# is delete that hook again whenever the task registry holds non-terminal background work:
#
#     if(_We(B)||Tio(B)){ … i.sessionHooksRegistry.remove(kt(),"Stop",y),
#                         w("[goal] evaluation deferred — background work still running") }
#     … finally{ if(y) i.sessionHooksRegistry.add(kt(),"Stop","",y) }
#
# The `finally` puts it back, so the registry reads CORRECT before the Stop and CORRECT after it,
# and is wrong only DURING — the one moment nothing can observe. `Tio` fires on any non-terminal
# `local_bash` task, and this box tells every session to arm `cc-await-ping --timeout 14400` as a
# background Bash "before you go idle". That watcher is non-terminal for FOUR HOURS, so on this box
# an armed goal is inert by default: measured 2h / ~12 turns / 0 evaluations, and no log the
# operator ever sees. The deferral itself is CC's, is deliberate, and is not ours to fix — judging
# "is the objective met?" mid-flight would read an incomplete transcript and burn an LLM call per
# Stop. What IS ours is that the failure is silent. This hook is the compensating control: it makes
# the skip LOUD, from a hook we own, on the same Stop where the skip happens.
#
# ── FIRE PREDICATE ── (1), (2) and (4) always, plus EITHER arm (3a) or arm (3b), else silent:
#   1. stdin is a Stop payload carrying `background_tasks` (CC ships it — YTe @237761:
#      `{background_tasks: cip(i.taskRegistry.all()), session_crons: uip()}` spread into the input).
#      The KEY must be present; an EMPTY list is a legitimate input, not a reason to abstain — see
#      trap (c) and arm 3b.
#   2. the transcript's LAST `goal_status` ATTACHMENT is a sentinel with met=false — i.e. a goal is
#      ARMED and has never been evaluated since. A non-sentinel last record means the evaluator IS
#      running (nothing to report); `sentinel:true, met:true` is the CLEAR marker (goal is gone).
#   3a. NAMED — ≥1 background task of a type CC's predicate counts AND whose carve-outs we can
#      decide. We can point at the culprit, so the message names it.
#   3b. BLIND — no such task is VISIBLE, yet the goal has stayed armed-and-unevaluated across ≥2
#      real user turns since its arm sentinel. Two turns means at least one Stop has come and gone
#      writing no evaluation record, so the goal IS being skipped even though the payload cannot
#      say by what (trap (c)). ≥2 rather than ≥1 because an INTERRUPTED turn produces a user
#      message with NO Stop at all; a single interrupt must not fire this. Arm 3b's message states
#      the fact it can prove (unevaluated across N turns) and offers the foreground-bash mechanism
#      as the likely cause, never as a certainty.
#   4. not damped (page-damp, keyed on the condition — a state, never a clock). One fingerprint
#      covers both arms: they report the same situation, so the second must not re-page.
#
# ⚠️ THREE TRAPS THIS HOOK IS BUILT AROUND, each of which silently produces the WRONG answer:
#   (a) `background_tasks[].type` is the DISPLAY name, not the raw one. `F$o` @237760745 maps
#       local_bash→"shell", local_agent→"subagent", local_workflow→"workflow",
#       in_process_teammate→"teammate", remote_agent→"cloud session". A hook grepping `local_bash`
#       matches NOTHING and reports all-clear forever — the caller-census-keyed-on-path defect.
#   (b) a bare `grep goal_status` on a transcript matches the assistant's own PROSE about goals. On
#       the session that produced this finding it returned 6 hits where the truth was 1, which
#       nearly inverted the conclusion. Every read here filters `type == "attachment"` first.
#   (c) `background_tasks` is a BACKGROUNDED-ONLY view, but the deferral gate reads the RAW
#       registry — so AN EMPTY LIST IS NOT EVIDENCE THAT NOTHING IS DEFERRING. Verified in
#       2.1.231; `cip` is `w1f` there, and its filter is `LR` @283039039:
#           function LR(e){ if(e.status!=="running"&&e.status!=="pending")            return !1;
#                           if("isBackgrounded" in e && e.isBackgrounded===!1)        return !1;
#                           return !0 }
#       The gate does no such filtering — @284195995 it is `let Y=i.taskRegistry.all(); if(kFe(Y)
#       ||vKo(Y)){…remove the goal hook…}`, and `vKo` (the doc's `Tio`) @290802207 is
#           function vKo(e){ for(let t of Object.values(e))
#                            if(t.type==="local_bash" && !HH(t.status)) return !0; return !1 }
#       — no `isBackgrounded` test anywhere in it. Every ORDINARY Bash tool call registers a
#       `local_bash` task with `isBackgrounded:!1` (@284278600), and nothing sweeps foreground
#       tasks at turn end: `k6e` ("background them all") is reachable only from the ctrl-b
#       keybinding and the SDK `background_tasks` control request. So a foreground bash that is
#       still `running`/`pending` when a Stop fires DEFERS THE GOAL WHILE BEING INVISIBLE HERE.
#       The deferring set is a strict SUPERSET of the reportable set. Arm 3b is the compensating
#       control; it cannot name such a task, only prove that something skipped the goal.
#
# ── WHY WE ABSTAIN ON teammate / cloud session ──
#   `_We`/`kFe` excludes `in_process_teammate && isIdle` and `remote_agent && isLongRunning`.
#   Neither flag is in the `cip()` payload, so for those two types we CANNOT decide whether CC would
#   defer. We count only the three types with no carve-out (shell · subagent · workflow) — where the
#   payload is sufficient to reproduce CC's predicate FOR THE TASKS IT CARRIES. It is never
#   sufficient for the tasks it OMITS (trap (c)), which is why an empty list now routes to arm 3b
#   instead of to silence. Under-reporting is still the correct direction WITHIN an arm: a hook that
#   cried "your goal is inert" at a session whose goal was fine would be trained around.
#   `shell` alone covers cc-await-ping, which is the entire observed cause. Arm 3b recovers these
#   two as well, for free and without guessing: it never claims WHICH task deferred the goal, only
#   that the goal went unevaluated — which is true of an idle-teammate session or not, and if CC
#   did evaluate (because the carve-out applied) the evaluation record makes arm 3b abstain.
#
# ── DELIVERY ── pure-advisory `{"systemMessage": …}`, NEVER `{decision:"block"}` and NEVER
#   `additionalContext`. Per CLAUDE.md § Session Close (measured on 2.1.220): additionalContext
#   DOES reach the model at Stop but FORCES another turn and increments the same consecutive-block
#   counter; systemMessage is the only Stop field that does not extend the turn. This hook informs,
#   it does not steer — it must not be able to hold a session open. Always exits 0.
#
# Tests: tests/goal-inert-watch.bats (incl. the display-name mutation — swap "shell" for
# "local_bash" and the fire case must go silent — and M3, which neuters arm 3b and asserts the
# foreground-bash case goes back to reporting a false all-clear).
set -uo pipefail

# ── B-3 TELEMETRY (backlog 61a3b40d8695, goal-inert half) ─────────────────────────────────────────
# This hook had written ZERO IDL records — measured over 978,400 records across 17 files (current +
# 16 rotations), it appears in none of them. `_gi_abstain` was a bare `exit 0` at 10 call sites and
# `idl_init` was never called, so "this session has no goal" (the correct, common no-op), "the
# transcript was unreadable" (blind), and "this hook never ran at all" were byte-identical. That is
# the ambiguity boundary-handoff.sh:17-19 exists to remove, and it matters more here than for most
# hooks: this file IS a compensating control for a silent failure, so a silent compensating control
# is worth nothing.
#
# REASON VOCABULARY IS THE LOAD-BEARING CHOICE, NOT THE ROW COUNT. Logging ENROLS this hook in
# scripts/idl-abstain-alarm.sh, which pages INERT when `abstained == total AND blind_share >=
# CC_ABSTAIN_BLIND_PCT` and reports the green DORMANT-100 otherwise. So the blind-set tokens (no-jq,
# no-stdin, no-transcript-path, transcript-missing) are used ONLY where this hook genuinely could
# not look, and every reached-guard disposition gets its own non-blind token. The dominant reason in
# production will be `no-goal` — most sessions never arm one — which is a guard that WAS reached and
# legitimately not met, so the hook lands on DORMANT-100 (green, surfaced for review) rather than
# paging. hooks/desk-brief-inject.sh:25-35 is the landed precedent for exactly this enrolment, and
# it made the same call for the same reason.
_giscd="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
_gilib="$_giscd/lib/idl-log.sh"
[ -f "$_gilib" ] || { _git="${BASH_SOURCE[0]}"; [ -L "$_git" ] && _git="$(readlink "$_git")"
  _gilib="$(cd "$(dirname "$_git")" 2>/dev/null && pwd)/lib/idl-log.sh"; }
[ -f "$_gilib" ] || _gilib="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/lib/idl-log.sh"
[ -f "$_gilib" ] || _gilib="$HOME/.claude/hooks/lib/idl-log.sh"
SID=""
# shellcheck source=lib/idl-log.sh
# shellcheck disable=SC1091  # runtime-resolved source; the ship gate runs shellcheck without -x
if [ -r "$_gilib" ] && . "$_gilib" 2>/dev/null && command -v idl_init >/dev/null 2>&1; then
  idl_init "${GOAL_INERT_IDL:-${CC_IDL:-$HOME/.claude/autonomy/idl.jsonl}}" "goal-inert-watch" SID
else
  # Telemetry must never be able to break a Stop hook: degrade to a no-op writer, never to an error.
  log_idl() { :; }
fi

_gi_abstain() { log_idl abstained "${1:-unspecified}" "${2:-}"; exit 0; }

input="$(cat 2>/dev/null || true)"
[ -n "$input" ] || _gi_abstain "no-stdin"
command -v jq >/dev/null 2>&1 || _gi_abstain "no-jq"

# ── (1) a Stop payload, with the task list CC hands us ────────────────────────────────────────────
TP="$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null || true)"
SID="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null || true)"
[ -n "$TP" ] || _gi_abstain "no-transcript-path"
case "$TP" in "~"*) TP="$HOME${TP#\~}" ;; esac
[ -f "$TP" ] || _gi_abstain "transcript-missing"

# The `background_tasks` KEY is what makes this a Stop/SubagentStop payload. Its presence is the
# check; its emptiness is not (trap (c)) — an empty list routes to arm 3b, never to silence.
printf '%s' "$input" | jq -e 'has("background_tasks")' >/dev/null 2>&1 || _gi_abstain "not-a-stop-payload"

# ── (3a) deferring background work, by DISPLAY name, restricted to the decidable types ────────────
# `cip()`'s producer already filters to status running|pending, so anything present here is
# non-terminal; the status re-check is belt-and-braces against a future payload change.
DEFERRERS="$(printf '%s' "$input" | jq -r '
  [ (.background_tasks // [])[]
    | select((.type // "") | IN("shell","subagent","workflow"))
    | select(((.status // "running") | IN("completed","failed","killed")) | not)
    | "\(.type): \(.command // .description // "-")" ] | .[]' 2>/dev/null || true)"

# ── (2) A LIVE GOAL — armed-and-never-evaluated, OR evaluated-then-STOPPED ────────────────────────
# WAS: `sentinel==true && met==false`, i.e. the arm marker must still be the NEWEST goal record.
# That detects only *never-evaluated-since-arming* and is blind to *stopped-evaluating* — the very
# failure this hook exists for. A goal that evaluated once and then went inert writes a non-sentinel
# newest record, so the old gate abstained on it forever (backlog 0f4147dcb20b).
#
# QUANTIFIED, so this is not a theoretical gap. Over 1,511 goal_status attachments across 626
# transcripts and all four account roots: sentinel and evaluation records are cleanly separable
# (`sentinel` appears only on arm/clear, `reason` only on evaluations, ZERO ambiguous records), and
# there are 25 windows where a live goal went ≥2 turns unevaluated with a non-sentinel newest
# record — 12.6% of all inert windows, invisible to this hook until now.
#
# USE THE LIB, DO NOT EDIT THE COPY. hooks/lib/goal-state.sh already ships `goal_liveness`, which
# returns the state, the evaluation count SINCE THE LAST ARM, and what the newest record was — and
# this file hand-rolled a near-copy of it. Two readers of one record dictionary is exactly the shape
# that lets a class of bug survive in one of them (MEMORY.md sibling-auditors-must-share-the-state-
# model), which is what happened here: the lib's dictionary already documented the non-sentinel
# unmet record as LIVE while this gate treated it as absent.
_gslib="$_giscd/lib/goal-state.sh"
[ -f "$_gslib" ] || _gslib="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/lib/goal-state.sh"
[ -f "$_gslib" ] || _gslib="$HOME/.claude/hooks/lib/goal-state.sh"
# shellcheck source=lib/goal-state.sh
# shellcheck disable=SC1091
[ -r "$_gslib" ] && . "$_gslib" 2>/dev/null
command -v goal_liveness >/dev/null 2>&1 || _gi_abstain "no-goal-state-lib"
GI_TSV="$(goal_liveness "$TP" 2>/dev/null)" || _gi_abstain "goal-unreadable"
IFS=$'\t' read -r GI_STATE GI_EVALS GI_LAST _GI_EPOCH COND <<< "$GI_TSV"
case "$GI_EVALS" in ''|*[!0-9]*) GI_EVALS=0 ;; esac
# `absent` (no goal ever armed) is the common no-op and gets its own token; `cleared`/`failed` mean
# the goal is gone. Neither is blind — the guard was reached and the fire condition is not met.
[ "$GI_STATE" = "live" ] || _gi_abstain "no-goal:${GI_STATE:-?}"

# ── (3b) BLIND arm — nothing REPORTABLE is deferring, so prove the skip from elapsed turns ────────
# Only reached when the payload names no deferrer, so the extra transcript pass costs nothing on the
# hot path. TURNS counts REAL typed user messages after the arm sentinel: a tool_result carries an
# ARRAY content and a system-injected turn carries isMeta, so both are excluded — leaving only
# messages that could not exist unless the session went idle first.
# THE THRESHOLD IS NOT A NEW VALUE CHOICE — it is arm 3b's, re-anchored. `:35-38` explains why ≥2
# and not ≥1: an INTERRUPTED turn produces a user message with no Stop at all, so a single interrupt
# must not fire this. What changes is what it counts FROM. GOAL_LN is the newest goal_status
# ATTACHMENT, which for a never-evaluated goal IS the arm sentinel (so the blind arm is unchanged)
# and for a stopped-evaluating goal is the last EVALUATION — exactly the re-anchoring W2 needs.
#
# WALL-CLOCK AGE WOULD BE WRONG and was rejected: an idle session accrues age without accruing
# turns, so an age threshold would fire on a session that is simply not being used.
#
# THE NAMED ARM NOW NEEDS THE THRESHOLD TOO, BUT ONLY IN THE STOPPED CASE. With a never-evaluated
# goal, a visible deferrer is sufficient on its own (unchanged — 0 turns required). With a goal that
# HAS evaluated, a live background task means CC will defer the NEXT evaluation, which is one Stop
# of normal, correct behaviour; firing on that would page at nearly every Stop of every goal session.
# Requiring the same ≥2 unevaluated turns is what makes the relaxed gate report INERTNESS rather
# than deferral.
GI_ARM=named
[ -n "$DEFERRERS" ] || GI_ARM=blind
TURNS=0
if [ "$GI_ARM" = "blind" ] || [ "$GI_LAST" != "arm" ]; then
  GOAL_LN="$(grep -an 'goal_status' "$TP" 2>/dev/null | jq -Rrn '
    [ inputs
      | capture("^(?<ln>[0-9]+):(?<rec>.*)$")
      | select((.rec | fromjson? // empty | select(.type == "attachment") | .attachment.type)
               == "goal_status")
      | (.ln | tonumber) ] | last // empty' 2>/dev/null || true)"
  [ -n "$GOAL_LN" ] || _gi_abstain "goal-line-unresolvable"
  TURNS="$(tail -n +"$((GOAL_LN + 1))" "$TP" 2>/dev/null | jq -Rrn '
    [ inputs
      | (fromjson? // empty)
      | select(.type == "user")
      | select((.isMeta // .message.isMeta // false) | not)
      | select((.message.content? | type) == "string") ] | length' 2>/dev/null || echo 0)"
  case "$TURNS" in ''|*[!0-9]*) TURNS=0 ;; esac
  [ "$TURNS" -ge 2 ] || _gi_abstain "below-turn-threshold:${TURNS}" \
    "$(jq -cn --argjson t "$TURNS" --argjson e "$GI_EVALS" --arg a "$GI_ARM" --arg l "$GI_LAST" \
      '{turns:$t,evals:$e,arm:$a,last:$l}' 2>/dev/null)"
fi

# ── (4) damping — fingerprint is the STATE (the condition), never a clock ─────────────────────────
# Same resolution ladder the sibling Stop hooks use — hooks/ is symlinked into the live layer, so
# resolve beside the script first, then the configured layer, then $HOME. A missing lib degrades to
# UNDAMPED (fail-open), never to silent: losing a true warning is worse than repeating one.
_gscd="$(dirname "${BASH_SOURCE[0]}")"
_dampsh="$_gscd/lib/page-damp.sh"
[ -f "$_dampsh" ] || _dampsh="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/lib/page-damp.sh"
[ -f "$_dampsh" ] || _dampsh="$HOME/.claude/hooks/lib/page-damp.sh"
if [ -r "$_dampsh" ]; then
  # shellcheck source=lib/page-damp.sh
  # shellcheck disable=SC1091  # runtime-resolved source; the ship gate runs shellcheck without -x
  . "$_dampsh" 2>/dev/null || true
  if command -v damp_should_send >/dev/null 2>&1; then
    # THE FINDING CLASS JOINS THE FINGERPRINT (W2). It used to be the condition alone, i.e. ONE page
    # per goal ever — which would let the never-evaluated page permanently suppress the newly-visible
    # stopped-evaluating page, since both carry the same condition. They are DIFFERENT findings about
    # the same goal ("it never started" vs "it started and stopped"), and the second is the one this
    # relaxation exists to surface. Deliberately the CLASS and not the evaluation count: keying on
    # `evals` would re-page on every stall of a goal that is otherwise progressing, so the budget
    # stays at most two pages per goal.
    _gi_class=never; [ "$GI_LAST" = "arm" ] || _gi_class=stalled
    _fp="GOAL-INERT:${_gi_class}:$(printf '%s' "$COND" | cksum 2>/dev/null | tr -dc '0-9' || true)"
    damp_should_send "goal-inert-${SID:-unknown}" "$_fp" || _gi_abstain "damped:${_gi_class}"
  fi
fi

N="$(printf '%s\n' "$DEFERRERS" | grep -c . 2>/dev/null || echo 0)"
SHORT="$COND"; [ "${#SHORT}" -gt 120 ] && SHORT="${SHORT:0:117}..."

# The two arms differ ONLY in the cause paragraph: one names the culprit, the other says why it
# cannot and what the likeliest invisible culprit is. Everything else — the headline, the goal
# echo, the remedy — is identical, because the operator's next action is the same either way.
if [ "$GI_ARM" = "named" ]; then
  CAUSE="$(printf '%s\n' \
"   CC deletes the goal's Stop hook whenever background work is live, then silently restores it," \
"   so the registry always LOOKS healthy. $N background task(s) are holding it off right now:" \
"$(printf '%s\n' "$DEFERRERS" | sed 's/^/     · /')" \
"" \
"   A 4-hour cc-await-ping watcher never settles, so the goal stays inert for as long as it runs.")"
else
  CAUSE="$(printf '%s\n' \
"   CC deletes the goal's Stop hook whenever background work is live, then silently restores it," \
"   so the registry always LOOKS healthy. ${TURNS} of your turns have gone by since it was armed" \
"   with no evaluation recorded, so at least one Stop skipped it." \
"" \
"   NOTHING IS NAMEABLE HERE — and that is itself the finding. The hook payload lists only" \
"   BACKGROUNDED tasks (CC filters \`isBackgrounded === false\` out of it), while the deferral gate" \
"   reads the raw task registry and counts ANY non-terminal local_bash. So the likeliest culprit is" \
"   a FOREGROUND bash still registered as running — invisible here by construction.")"
fi

# The goal line states the EVALUATION COUNT, because the two findings this hook can now make are
# distinguished by exactly that number and the operator's reading of them differs: 0 means the goal
# never started, N means it ran and then stopped — the second was invisible before W2.
if [ "$GI_LAST" = "arm" ]; then
  GI_ECHO="   goal (armed, 0 evaluations so far): \"$SHORT\""
else
  GI_ECHO="   goal (armed, ${GI_EVALS} evaluation(s), then STOPPED — none in your last ${TURNS} turns): \"$SHORT\""
fi

MSG="$(printf '%s\n' \
"⚠️  YOUR /goal IS NOT BEING EVALUATED — Claude Code skipped it at this Stop." \
"" \
"$GI_ECHO" \
"" \
"$CAUSE" \
"" \
"   To keep a session going, use the mechanism we own — it is unaffected by this:" \
"     ~/.claude/hooks/session-continue.sh set \"<the ONE next step>\"" \
"   Detail: docs/research/goal-in-handoff-2026-08-08.md" \
"     §§ RESOLVED 2026-08-09 · The foreground blind spot 2026-08-14")"

log_idl fired "goal-inert:${GI_ARM}" "$(jq -cn --arg a "$GI_ARM" --arg l "$GI_LAST" \
  --argjson e "$GI_EVALS" --argjson t "$TURNS" --argjson n "$N" \
  '{arm:$a,last:$l,evals:$e,turns:$t,deferrers:$n}' 2>/dev/null)"
jq -nc --arg m "$MSG" '{systemMessage:$m}' 2>/dev/null || true
exit 0
