#!/usr/bin/env bash
# jev.sh — the ONE way a hook asks Jev a typed question. Source it; do not re-implement it.
#
# WHY A LIBRARY AND NOT A CALL SITE. Two hooks want this (anti-deference-nudge and
# completion-assert's authorship arm) and the repo has a standing lesson about exactly that
# shape: `sibling-auditors-must-share-the-state-model` — two checks over one population
# disagreed because only one of them modelled a state. One spelling of "ask Jev", or the two
# hooks drift apart on thresholds, on redaction, and on what a timeout means.
#
# ── THE SAFETY INVARIANT, and every consumer inherits it ─────────────────────────────────────
# Jev may only ever move a decision in the direction today's regex is MEASURED to get wrong,
# and only above CC_JEV_MIN_P. It may never:
#   · suppress a fire the existing matcher already produces,
#   · weaken a deny, a carve-out, or a safety gate,
#   · change behaviour at all when it cannot answer.
# ANY abstain — no key, no deps, timeout, HTTP, kill switch — leaves the caller on exactly
# today's code path. That is what makes landing this a no-op until someone deliberately turns
# it on, and it is why `jev_ask` returns non-zero rather than a default answer.
#
# ── WHY 0.98 ─────────────────────────────────────────────────────────────────────────────────
# Not a taste call. On the one independent benchmark (docs/research/jev-at-cost-api-2026-09-18.md
# §2) Jev's aggregate accuracy LOSES to Haiku 4.5 (62.6% vs 81.3%) and its aggregate ECE loses
# too — but it emits 101 distinct probability values against Haiku's 10, and in its top bin
# (p>=0.98) it decides 7.0% of cases at 97.8% accuracy. The usable product is that
# high-precision tail, not the verdict. So: act only in the tail, abstain everywhere else, and
# never read a mid-band probability as a weak yes. A p of 0.5 is maximum UNCERTAINTY, not "no" —
# the SDK's own type says so: "Model-estimated P(true). Not confidence in either outcome."
#
# ── WHAT MUST NEVER BE SENT ──────────────────────────────────────────────────────────────────
# Callers pass a BOUNDED, PURPOSE-BUILT excerpt — the message under judgment — never a
# transcript, a mailbox, or the `msg` corpus. ZDR is on and fails closed, which is what makes
# model-authored prose acceptable; it is not a licence to widen the payload. jev_ask enforces
# the size ceiling mechanically (CC_JEV_MAX_STATE_B) because a rule stated only in prose is a
# rule nothing executes.
#
# Kill switch: CC_JEV=0 (and absence of AI_GATEWAY_API_KEY is itself an off switch).

# ── ROOT RESOLUTION MUST FOLLOW THE SYMLINK, AND THIS IS NOT A DETAIL ───────────────────────
# The live layer (~/.claude) is a per-file symlink farm over this checkout. A hook sourcing this
# file does so as ~/.claude/hooks/lib/jev.sh, so a naive dirname/../.. yields ~/.claude — which
# has no node_modules and never will, because node_modules is gitignored and lives in the
# CHECKOUT. Unresolved, `jev_available` would return false forever in exactly the environment
# this code exists to run in, and it would do so SILENTLY, since unavailable is a legitimate
# state. That is memory `symlinked-$0-splits-siblings` verbatim: one invocation splits into a
# half that resolves and a half that dies.
# Resolved with a portable loop rather than `readlink -f` (GNU-only semantics on older Darwin).
_jev_resolve_root() {
  local src="${BASH_SOURCE[0]}" dir
  while [ -L "$src" ]; do
    dir="$(cd -P "$(dirname "$src")" && pwd)"
    src="$(readlink "$src")"
    case "$src" in /*) ;; *) src="$dir/$src" ;; esac
  done
  (cd -P "$(dirname "$src")/../.." && pwd)
}
CC_JEV_LIB_ROOT="${CC_JEV_LIB_ROOT:-$(_jev_resolve_root)}"
: "${CC_JEV_MIN_P:=0.98}"
: "${CC_JEV_TIMEOUT_MS:=1500}"
: "${CC_JEV_MAX_STATE_B:=24000}"   # well under Jev's 32k-TOKEN state ceiling; bytes are the cheap bound

# jev_available — cheap, no fork of node. Answers "would a call have any chance of succeeding".
jev_available() {
  [ "${CC_JEV:-1}" != "0" ] || return 1
  [ -n "${AI_GATEWAY_API_KEY:-}" ] || return 1
  [ -f "$CC_JEV_LIB_ROOT/scripts/jev/evaluate.mjs" ] || return 1
  [ -d "$CC_JEV_LIB_ROOT/node_modules/ai" ] || return 1
  command -v node >/dev/null 2>&1 || return 1
  return 0
}

# jev_ask <<< '{"state":…,"questions":{…}}'
#   stdout: ALWAYS one JSON object — {ok:true,answers,…} or {ok:false,reason}
#   rc 0  answered · rc 1 abstained (caller MUST fall through to its existing path)
#
# 🚨 THE REASON IS ON STDOUT, NOT IN A GLOBAL — and that is a bug fix, not a style choice.
# The obvious call shape is `printf '%s' "$spec" | jev_ask`, and the right-hand side of a pipe
# runs in a SUBSHELL, so any variable this function set would be discarded the instant it
# returned. The repo already carries that lesson twice over
# (`assignment-inside-command-substitution-never-escapes`, `subshell eats the global`) and the
# first draft of this file shipped the bug anyway — caught by tests 12 and 13 below. One
# channel, always JSON, works identically piped, here-stringed, or captured.
jev_ask() {
  local spec out rc
  spec="$(cat)"
  if ! jev_available; then printf '{"ok":false,"reason":"unavailable"}'; return 1; fi
  if [ "${#spec}" -gt "$CC_JEV_MAX_STATE_B" ]; then printf '{"ok":false,"reason":"oversize"}'; return 1; fi
  # No `2>/dev/null` on the node call's stdout path: a suppressed stderr turns a failed command
  # into a clean zero (`suppressed-stderr-turns-a-failed-command-into-a-zero`). stderr goes to
  # the hook's own stderr, where the harness records it; only stdout is consumed.
  out="$(printf '%s' "$spec" | CC_JEV_TIMEOUT_MS="$CC_JEV_TIMEOUT_MS" \
        node "$CC_JEV_LIB_ROOT/scripts/jev/evaluate.mjs")"
  rc=$?
  # An empty capture is NOT "it printed nothing" — it is a killed or crashed child, and a
  # consumer that jq's it would read `null` and could mistake that for a verdict
  # (`killed-pipeline-empty-output-is-not-a-verdict`). Synthesise the abstain rather than
  # letting a blank reach the caller.
  if [ -z "$out" ]; then printf '{"ok":false,"reason":"no-output"}'; return 1; fi
  printf '%s' "$out"
  [ "$rc" -eq 0 ]
}

# jev_reason <result-json> — the abstain class, for logging. Always safe to call.
jev_reason() { printf '%s' "$1" | jq -r '.reason // "none"' 2>/dev/null || printf 'none'; }

# jev_bool_confident <result-json> <question-id> [min-p]
#   rc 0  → P(true) >= min-p            "confidently TRUE"
#   rc 1  → anything else, INCLUDING a confident false and a missing answer.
# There is deliberately no "confidently false" helper: no consumer needs one yet, and a second
# threshold nobody has calibrated is a number waiting to be quoted as if it were measured.
jev_bool_confident() {
  local json="$1" id="$2" minp="${3:-$CC_JEV_MIN_P}" p
  p="$(printf '%s' "$json" | jq -r --arg id "$id" '.answers[$id].probability // empty' 2>/dev/null)"
  [ -n "$p" ] || return 1
  awk -v p="$p" -v t="$minp" 'BEGIN{exit !(p+0 >= t+0)}'
}
