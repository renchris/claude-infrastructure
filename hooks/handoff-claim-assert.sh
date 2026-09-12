#!/bin/bash
# handoff-claim-assert.sh — Stop hook: the hand-off claim finally has a verifier.
#
# THE CLAIM UNDER AUDIT. A `▶ Run this:` marker asserts "I cannot run this; you must." Every other
# load-bearing close claim on this machine has a producer that refuses it — wrap-ledger.sh for
# "landed", completion-assert.sh for "done", cc-backlog for `needs-human` without a conviction
# number. This one was free text, asserted by the same model that made the inference. Measured over
# 2,690 transcripts: 1,376 emissions, of which the gold set calls 474 (34%) commands the agent
# could and should have run itself.
#
# IT BLOCKS ONLY ON `REFUTED`, AND ONLY BECAUSE THAT ARM MEASURES CLEAN. Scored against the
# 429-command double-labelled gold set (docs/research/silver-platter-enforcement-2026-09-12):
# 165 of 1,379 emissions refuted, 165 correct, ZERO false blocks in 32 days. The HUMAN verdict is
# never surfaced — an affirmation changes nothing the operator does, and a hook that speaks when it
# has nothing to add is the nag anti-deference-nudge.sh:30 warns trains the model to route around it.
#
# FAIL-SAFE, EVERY PATH. No `set -e`. Blocks only via {"decision":"block"} on stdout; every other
# path exits 0 silently. Missing jq, unreadable transcript, absent cc-cannot, an UNRESOLVED verdict
# — all abstain. cc-cannot is itself three-valued and fails to UNRESOLVED, so ignorance never
# reaches this hook as a verdict.
set -uo pipefail

# ── `--why` REFERENCE TIER — dispatched BEFORE stdin is read. A `cat` above this blocks forever on
#    a tty, which is how a pointer becomes "a deletion wearing a pointer's clothes". ──
if [ "${1:-}" = "--why" ]; then
  _wt="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/lib/why-tier.sh"
  [ -f "$_wt" ] || { _wtt="$0"; [ -L "$_wtt" ] && _wtt="$(readlink "$_wtt")"
    _wt="$(cd "$(dirname "$_wtt")" 2>/dev/null && pwd)/lib/why-tier.sh"; }
  [ -f "$_wt" ] || _wt="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/lib/why-tier.sh"
  # shellcheck disable=SC1091
  if [ -f "$_wt" ] && . "$_wt" 2>/dev/null; then why_tier_main "handoff-claim" "${2:-}"; exit $?; fi
  printf 'handoff-claim-assert: FATAL — the --why tier is missing (%s). Cure: bash ~/Development/claude-infrastructure/install.sh\n' "$_wt" >&2
  exit 2
fi

CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
STATE_DIR="${HANDOFF_CLAIM_STATE_DIR:-$CFG/state/handoff-claim}"
MAX="${HANDOFF_CLAIM_MAX:-3}"
abstain() { [ -n "${HANDOFF_CLAIM_DEBUG:-}" ] && printf 'handoff-claim-assert: abstain %s\n' "${1:-}" >&2; exit 0; }

[ -n "${HANDOFF_CLAIM_DISABLED:-}" ] && abstain "kill-switch"
input="$(cat 2>/dev/null || printf '{}')"
command -v jq >/dev/null 2>&1 || abstain "no-jq"

SID="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null || true)"
TP="$(printf '%s'  "$input" | jq -r '.transcript_path // empty' 2>/dev/null || true)"
CWD="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)"
[ -n "$TP" ] || abstain "no-transcript-path"
case "$TP" in "~"*) TP="$HOME${TP#\~}" ;; esac
[ -f "$TP" ] || abstain "transcript-missing"

# Last MAIN-agent text (sidechain records are subagents and carry no operator-facing close).
MSG="$(jq -c 'select(.type=="assistant" and (.isSidechain != true))
              | ([.message.content[]? | select(.type=="text") | .text] | join("\n"))
              | select(. != "")' "$TP" 2>/dev/null | tail -1 \
       | jq -r '. // empty' 2>/dev/null || true)"
[ -n "$MSG" ] || abstain "no-assistant-text"
case "$MSG" in *"▶"*) ;; *) abstain "no-marker" ;; esac

# ── Marker parser. FENCED LINES ARE SKIPPED: the rendered OPERATOR ▸ block is a mandated verbatim
#    relay, and convicting inside it would punish exactly the compliant closes. A mid-sentence
#    inline span is a MENTION, not a use — position is the discriminator, per CLAUDE.md. ──
CANDS="$(printf '%s' "$MSG" | awk '
  BEGIN{fence=0; armed=0}
  { line=$0
    if (line ~ /^[ \t]*```/) { fence=!fence; next }
    if (fence) next
    t=line; sub(/^[[:space:]]+/,"",t); sub(/[[:space:]]+$/,"",t)
    if (t=="") next
    if (index(t,"▶")>0) {
      rest=substr(t, index(t,"▶")+3); sub(/^[[:space:]]*/,"",rest)
      if (rest ~ /:$/ || rest=="") { armed=1; next }
      gsub(/`/,"",rest); print rest; armed=0; next }
    if (armed==1) { gsub(/`/,"",t); if (t!="") print t; armed=0; next }
  }' 2>/dev/null || true)"
[ -n "$CANDS" ] || abstain "no-command-under-marker"

# RESOLVE cc-cannot VIA $0's OWN SYMLINK FIRST. ~/.claude is a tree of per-file symlinks, so a
# BRAND-NEW bin/ file is ABSENT from the live layer rather than stale until install.sh runs — and
# CLAUDE.md's 🚀 rung says exactly that: LIVE_ADDS>0 breaches the converge budget at a lag of 1.
# Found the hard way: the hook abstained `no-cc-cannot` on its own first test. Walking $0 back to
# the checkout means the hook and its binary arrive on the SAME fast-forward, so it is never
# registered-but-inert. (The completion-assert.sh:113-123 pattern.)
CC="$CFG/bin/cc-cannot"
if [ ! -x "$CC" ]; then
  _self="$0"; [ -L "$_self" ] && _self="$(readlink "$_self")"
  _root="$(cd "$(dirname "$_self")/.." 2>/dev/null && pwd)"
  [ -n "$_root" ] && [ -x "$_root/bin/cc-cannot" ] && CC="$_root/bin/cc-cannot"
fi
[ -x "$CC" ] || CC="$HOME/Development/claude-infrastructure/bin/cc-cannot"
[ -x "$CC" ] || abstain "no-cc-cannot"

VERDICTS=""
while IFS= read -r c; do
  [ -n "$c" ] || continue
  out="$("$CC" -- "$c" 2>/dev/null)"; rc=$?
  [ "$rc" -eq 1 ] || continue                      # ONLY a refutation is actionable
  VERDICTS="${VERDICTS}  · ${c}"$'\n'"      → $(printf '%s' "$out" | cut -f2- | tr '\t' ' ')"$'\n'
done <<< "$CANDS"
[ -n "$VERDICTS" ] || abstain "no-refutation"

# A team assignee's only channel is two-way with its lead; it cannot re-address the operator.
if [ -f "$CFG/hooks/lib/agent-identity.sh" ]; then
  # shellcheck disable=SC1091
  . "$CFG/hooks/lib/agent-identity.sh" 2>/dev/null && {
    _aid="$(agent_is_assignee 2>/dev/null || true)"; [ -n "$_aid" ] && abstain "team-assignee:${_aid}"; }
fi

# ── Latch-set + hard cap. An unlatched Stop block is the infinite-loop anti-pattern. ──
mkdir -p "$STATE_DIR" 2>/dev/null || true
find "$STATE_DIR" -name '*.fired' -mtime +7 -delete 2>/dev/null || true
SKEY="$(printf '%s|%s|%s' "$CFG" "$SID" "$CWD" | shasum 2>/dev/null | cut -c1-16)"; [ -n "$SKEY" ] || abstain "no-skey"
HASH="$(printf '%s' "$MSG" | shasum 2>/dev/null | cut -c1-16)";                   [ -n "$HASH" ] || abstain "no-hash"
FIRED="$STATE_DIR/$SKEY.fired"
[ -f "$FIRED" ] && grep -qxF "$HASH" "$FIRED" 2>/dev/null && abstain "latched-already-fired"
N="$(grep -c . "$FIRED" 2>/dev/null || echo 0)"; case "$N" in ''|*[!0-9]*) N=0 ;; esac
[ "$N" -ge "$MAX" ] && abstain "capped:${N}>=${MAX}"
printf '%s\n' "$HASH" >> "$FIRED" 2>/dev/null || true

reason="Hand-off claim REFUTED — you handed the operator a command you can run yourself:
${VERDICTS}
A '▶ Run this:' marker asserts 'I cannot run this; you must'. That claim is now checked against
the filesystem and the scheduler set, not against the sentence beside it. Run the command and
report its RESULT, or — if it is a reference rather than an instruction — cite it in inline
backticks mid-sentence, where CLAUDE.md puts reference-only commands. Then close again.
Detail: ~/.claude/hooks/handoff-claim-assert.sh --why handoff-claim"
jq -nc --arg r "$reason" '{decision:"block",reason:$r}'
exit 0
