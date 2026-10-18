#!/bin/bash
# relay-verbatim.sh — PostToolUse(Bash): when a CANONICAL RENDERER just ran, re-assert that its
# output must be pasted into chat verbatim, before the model composes its reply.
#
# Why this exists (2026-08-01). `commands/accounts.md` step 2 has said "Paste that output" since
# 2026-07-11, and the readout rendered perfectly — then the model dissolved it into three bullets
# and the operator lost every reset time. The instruction was one soft line competing against
# CLAUDE.md § Communication Discipline's "focused and brief", which had just been tightened.
# Prose lost to prose. This hook is the deterministic side: it fires on the RENDER itself, so the
# reminder arrives in the same turn as the output it governs, and it does not depend on the model
# having read (or weighted) a doc line.
#
# Scope is deliberately narrow — ONLY commands whose entire purpose is to emit an operator-facing
# artifact. A broader matcher would fire on ordinary work and become noise, which is how advisories
# stop being read (see MEMORY.md alarm-polarity-and-attention-budget).
#
# Fail-open by construction: any parse failure exits 0 silently. A reminder hook must never fail
# wider than itself (MEMORY.md addon-failure-exceeds-its-blast-radius).
IFS= read -r -d '' INPUT || true
# Lean hook profile (lib/hook-profile.sh): advisory — skipped for bulk agents, in pure bash, before any fork.
# shellcheck source=/dev/null  # sibling lib; resolved at run time, not by the linter
. "${BASH_SOURCE[0]%/*}/lib/hook-profile.sh" 2>/dev/null && cc_hook_skip advisory "$INPUT" && exit 0
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
[ -n "$CMD" ] || exit 0

# Renderers whose stdout IS the deliverable. Keep this list short and literal.
# The /accounts readout gets its OWN tail (2026-10-18): it leads with its own answer, and the
# generic "add at most 3 lines" arrived at the moment of the paste and outweighed the doc's "add
# nothing unless" rule — on 2026-10-17 the model restated lines 1-2 and the drain line after the
# paste. KEEP ITS TRIGGER LIST AND commands/accounts.md STEP 3 IN STEP: same cases, same words.
# TAIL is assigned here, never inherited: an exported TAIL must not replace the fixed wording.
# The matcher takes `--fresh --readout` too; the settings.json `if` filter (migration 0066) still
# gates which commands reach this hook at all.
TAIL="then add at most 3 lines of interpretation."
case "$CMD" in
  *claude-accounts*--readout*)        WHAT="the /accounts readout"
                                      # shellcheck disable=SC2016  # backticks are markdown code spans, kept literal
                                      TAIL='then STOP: line 1 already answers which account to use. Add nothing unless the readout shows a ↻ line or a `Skipped by the general router:` line, a ⊘/⚠ login or ○ auth line, a 🚨 spend or ⚠ extra-usage toggle line, a lane reading `→ none`, a 🚨/⚠ line about another agent (a routable backend that bills outside a plan or might, or one on a metered API key), or the operator asked a direct question. NOT triggers: the standing "Not wired, because … would bill outside our plans" line, the ⚠ pace rows and the ⚠ fleet-burn line. Then at most 3 lines (commands/accounts.md step 3).' ;;
  *"operator-readout.sh --render"*)   WHAT="the operator close block" ;;
  *"cc-do --list"*)                   WHAT="the operator step list" ;;
  *)                                  exit 0 ;;
esac

# Only nag when it actually produced something.
OUT=$(printf '%s' "$INPUT" | jq -r '.tool_response.stdout // .tool_response.output // empty' 2>/dev/null)
[ -n "$OUT" ] || exit 0

jq -n --arg w "$WHAT" --arg t "$TAIL" '{
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    additionalContext: ("RELAY VERBATIM — you just rendered \($w). Paste that output into chat in
full, every row and column, BEFORE any commentary; \($t)
Summarising it is the defect the renderer exists to prevent — a paraphrase re-creates the second
renderer the code was written to delete. CLAUDE.md conciseness governs YOUR prose, never a
rendered artifact.")
  }
}' 2>/dev/null || exit 0
exit 0
