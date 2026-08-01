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
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
[ -n "$CMD" ] || exit 0

# Renderers whose stdout IS the deliverable. Keep this list short and literal.
case "$CMD" in
  *"claude-accounts --readout"*)      WHAT="the /accounts table" ;;
  *"operator-readout.sh --render"*)   WHAT="the operator close block" ;;
  *"cc-do --list"*)                   WHAT="the operator step list" ;;
  *)                                  exit 0 ;;
esac

# Only nag when it actually produced something.
OUT=$(printf '%s' "$INPUT" | jq -r '.tool_response.stdout // .tool_response.output // empty' 2>/dev/null)
[ -n "$OUT" ] || exit 0

jq -n --arg w "$WHAT" '{
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    additionalContext: ("RELAY VERBATIM — you just rendered \($w). Paste that output into chat in
full, every row and column, BEFORE any commentary; then add at most 3 lines of interpretation.
Summarising it is the defect the renderer exists to prevent — a paraphrase re-creates the second
renderer the code was written to delete. CLAUDE.md conciseness governs YOUR prose, never a
rendered artifact.")
  }
}' 2>/dev/null || exit 0
exit 0
