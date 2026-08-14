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

_gi_abstain() { exit 0; }

input="$(cat 2>/dev/null || true)"
[ -n "$input" ] || _gi_abstain
command -v jq >/dev/null 2>&1 || _gi_abstain

# ── (1) a Stop payload, with the task list CC hands us ────────────────────────────────────────────
TP="$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null || true)"
SID="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null || true)"
[ -n "$TP" ] || _gi_abstain
case "$TP" in "~"*) TP="$HOME${TP#\~}" ;; esac
[ -f "$TP" ] || _gi_abstain

# The `background_tasks` KEY is what makes this a Stop/SubagentStop payload. Its presence is the
# check; its emptiness is not (trap (c)) — an empty list routes to arm 3b, never to silence.
printf '%s' "$input" | jq -e 'has("background_tasks")' >/dev/null 2>&1 || _gi_abstain

# ── (3a) deferring background work, by DISPLAY name, restricted to the decidable types ────────────
# `cip()`'s producer already filters to status running|pending, so anything present here is
# non-terminal; the status re-check is belt-and-braces against a future payload change.
DEFERRERS="$(printf '%s' "$input" | jq -r '
  [ (.background_tasks // [])[]
    | select((.type // "") | IN("shell","subagent","workflow"))
    | select(((.status // "running") | IN("completed","failed","killed")) | not)
    | "\(.type): \(.command // .description // "-")" ] | .[]' 2>/dev/null || true)"

# ── (2) an ARMED, never-evaluated goal ────────────────────────────────────────────────────────────
# grep narrows a possibly-huge transcript cheaply; jq then enforces type=="attachment" (trap b).
GOAL="$(grep -a 'goal_status' "$TP" 2>/dev/null | jq -rc --slurp '
  [ .[] | select(.type == "attachment")
        | .attachment | select(.type == "goal_status") ] | last // empty' 2>/dev/null || true)"
[ -n "$GOAL" ] || _gi_abstain

IS_SENTINEL="$(printf '%s' "$GOAL" | jq -r '.sentinel // false' 2>/dev/null || echo false)"
IS_MET="$(printf '%s' "$GOAL" | jq -r '.met // false' 2>/dev/null || echo false)"
# armed-and-unevaluated == the arm marker is still the most recent goal record.
[ "$IS_SENTINEL" = "true" ] && [ "$IS_MET" = "false" ] || _gi_abstain
COND="$(printf '%s' "$GOAL" | jq -r '.condition // ""' 2>/dev/null || true)"

# ── (3b) BLIND arm — nothing REPORTABLE is deferring, so prove the skip from elapsed turns ────────
# Only reached when the payload names no deferrer, so the extra transcript pass costs nothing on the
# hot path. TURNS counts REAL typed user messages after the arm sentinel: a tool_result carries an
# ARRAY content and a system-injected turn carries isMeta, so both are excluded — leaving only
# messages that could not exist unless the session went idle first.
GI_ARM=named
if [ -z "$DEFERRERS" ]; then
  GI_ARM=blind
  GOAL_LN="$(grep -an 'goal_status' "$TP" 2>/dev/null | jq -Rrn '
    [ inputs
      | capture("^(?<ln>[0-9]+):(?<rec>.*)$")
      | select((.rec | fromjson? // empty | select(.type == "attachment") | .attachment.type)
               == "goal_status")
      | (.ln | tonumber) ] | last // empty' 2>/dev/null || true)"
  [ -n "$GOAL_LN" ] || _gi_abstain
  TURNS="$(tail -n +"$((GOAL_LN + 1))" "$TP" 2>/dev/null | jq -Rrn '
    [ inputs
      | (fromjson? // empty)
      | select(.type == "user")
      | select((.isMeta // .message.isMeta // false) | not)
      | select((.message.content? | type) == "string") ] | length' 2>/dev/null || echo 0)"
  case "$TURNS" in ''|*[!0-9]*) TURNS=0 ;; esac
  [ "$TURNS" -ge 2 ] || _gi_abstain
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
    _fp="GOAL-INERT:$(printf '%s' "$COND" | cksum 2>/dev/null | tr -dc '0-9' || true)"
    damp_should_send "goal-inert-${SID:-unknown}" "$_fp" || _gi_abstain
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

MSG="$(printf '%s\n' \
"⚠️  YOUR /goal IS NOT BEING EVALUATED — Claude Code skipped it at this Stop." \
"" \
"   goal (armed, 0 evaluations so far): \"$SHORT\"" \
"" \
"$CAUSE" \
"" \
"   To keep a session going, use the mechanism we own — it is unaffected by this:" \
"     ~/.claude/hooks/session-continue.sh set \"<the ONE next step>\"" \
"   Detail: docs/research/goal-in-handoff-2026-08-08.md" \
"     §§ RESOLVED 2026-08-09 · The foreground blind spot 2026-08-14")"

jq -nc --arg m "$MSG" '{systemMessage:$m}' 2>/dev/null || true
exit 0
