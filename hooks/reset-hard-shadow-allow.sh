#!/bin/bash
# reset-hard-shadow-allow.sh — state-predicated PreToolUse(Bash) auto-allow hook for the ONE
# reflog-reversible reset shape: `git reset --hard origin/main` / `git reset --hard @{u}`.
# SHADOW by default (LOGS a would-allow, emits NO decision → the settings `ask` prompt still
# fires); emits `permissionDecision:allow` ONLY once explicitly ARMED (a sentinel the operator
# creates AFTER a clean soak). Everything not provably the safe shape stays SILENT (exit 0, no
# decision) → the existing `Bash(git reset --hard:*)` ask / deny array / validate-bash still apply.
#
# WHY THIS EXISTS (Part B, docs/research/desk-anti-hitl-2026-07-19.md §B; cc-backlog 062bdca35dd7):
#   `Bash(git reset --hard:*)` sits in the settings `ask` array (~/.claude/settings.json:407) — a
#   deliberate operator judgment point, everywhere. 24/7 autonomous work STRANDS on it: incident
#   731f0968 hung 133 min because NOTHING can answer a prompt. The design verdict (§B, BINDING) is
#   that the desk must NEVER learn to press "1" — keystroke-approval is fundamentally unsafe
#   (screen-spoof, TOCTOU, the "Yes, don't ask again" ratchet → a *permanent* silent allowlist).
#   The provably-safe alternative is a same-process hook that checks LIVE STATE atomically with the
#   decision — a keystroke never can. Bounded loss (latency) beats unbounded loss (rewritten trunk).
#
# SAFETY MODEL — allow is OPT-IN to one provably-reversible shape; THREE conjuncts, ALL required:
#   1. SHAPE — the anchored single command `git reset --hard <T>`, T ∈ {origin/main, @{u}}, and
#      NOTHING else: no compound/substitution/redirection/newline (the ship-rail metachar guard,
#      ship-rail-push-allow.sh:48-50), no extra flag, no leading `-C`/env-prefix, no other target.
#      The anchor is an ALL-POSITIVE allowlist match — never a negated lookahead (a `grep -qE`
#      `(?!…)` guard is invalid ERE on macOS/BSD → errors → FAILS OPEN; memory
#      reference-grep-lookahead-fails-open-and-tight-allow-hook-doctrine).
#   2. CLEAN TREE — `git status --porcelain` empty at decision time ⇒ the reset discards NO
#      uncommitted work; it only moves the branch ref, which the reflog fully reverses. A dirty
#      tree could lose real work → defer.
#   3. SANCTIONED WORKTREE — cwd is a LINKED git worktree (absolute-git-dir under `.git/worktrees/`),
#      never the primary shared checkout (a `reset --hard` there can disrupt a concurrent session
#      sharing the index) and never a non-repo dir.
#   All three are evaluated in the SAME PROCESS as the decision — atomic, no TOCTOU window a
#   keystroke has. FAIL-CLOSED: any parse error / git failure / uncertainty ⇒ SILENT (exit 0) ⇒
#   the normal ask:407 prompt fires. The hook can only ever ADD an allow to a provably-safe case;
#   it never denies and never widens.
#
# SHADOW vs ARMED (Part B §B.5 sequencing: wire in shadow → arm after a clean soak):
#   • SHADOW (default — no arm sentinel): a matching+passing command is LOGGED as
#     {decision:"would-allow"} to the soak log, and the hook exits SILENT — the ask prompt still
#     fires (human/desk still approves every real reset). This is the observation phase.
#   • ARMED (arm sentinel present): the operator reviewed a clean soak and armed. Now a
#     matching+passing command is LOGGED as {decision:"allow"} AND the allow-JSON is emitted.
#   Arming is the ONLY step that flips behaviour from log-only to auto-allow; it is deliberately
#   SEPARATE from wiring and operator-gated (requires `arm --confirm`). CLI:
#     reset-hard-shadow-allow.sh arm --confirm   # after a clean soak → ARMED (auto-allow live)
#     reset-hard-shadow-allow.sh shadow          # remove the sentinel → back to SHADOW (log-only)
#     reset-hard-shadow-allow.sh status          # mode + soak-log path + would-allow count
#
# Kill switch: RESET_HARD_ALLOW_DISABLED=1  (defer everything, incl. shadow logging).
# Contract: read the PreToolUse payload on stdin, emit allow-JSON + exit 0 to allow, else exit 0 silent.

set -uo pipefail

STATE_DIR="${CC_RESET_HARD_STATE_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/state/reset-hard-allow}"
ARM_SENTINEL="$STATE_DIR/armed"
LOG_FILE="${CC_RESET_HARD_LOG:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/logs/reset-hard-allow-shadow.jsonl}"

now_utc() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# ── CLI mode (arm / shadow / status) ─────────────────────────────────────────────────────────
# Arming is the operator's post-soak act; it is NOT a hook decision. Kept in the same file so the
# script that MAKES the decision is the script that OWNS its arm state (one source of truth).
case "${1:-}" in
  arm)
    if [ "${2:-}" != "--confirm" ]; then
      cat >&2 <<'MSG'
reset-hard-allow: REFUSING a bare `arm`. Arming makes `git reset --hard origin/main|@{u}`
AUTO-ALLOW (no prompt) whenever the tree is clean and cwd is a linked worktree.

Before arming, confirm a CLEAN SOAK:
  1. The hook has been wired in SHADOW and run for a soak window (see docs/RESET-HARD-ACTIVATION.md).
  2. Review the soak log — EVERY entry must be a legitimate reflog-reversible reset:
       reset-hard-shadow-allow.sh status
       jq -c 'select(.decision=="would-allow")' "$HOME/.claude/logs/reset-hard-allow-shadow.jsonl"
  3. No entry surprises you (unexpected cwd, unexpected target, a repo you did not mean to include).

Then arm deliberately:
  reset-hard-shadow-allow.sh arm --confirm
MSG
      exit 2
    fi
    mkdir -p "$STATE_DIR"
    printf '{"armed_at":%s,"by":%s,"cwd":%s}\n' \
      "$(jq -Rn --arg v "$(now_utc)" '$v')" \
      "$(jq -Rn --arg v "${USER:-unknown}" '$v')" \
      "$(jq -Rn --arg v "$PWD" '$v')" > "$ARM_SENTINEL"
    echo "reset-hard-allow: ARMED → $ARM_SENTINEL"
    echo "  Auto-allow is now LIVE for the proven shape (clean tree + linked worktree). Revert with 'shadow'."
    exit 0 ;;
  shadow|disarm|clear)
    rm -f "$ARM_SENTINEL" 2>/dev/null
    echo "reset-hard-allow: SHADOW (arm sentinel removed). Log-only — the ask prompt fires for every reset --hard."
    exit 0 ;;
  status)
    if [ -f "$ARM_SENTINEL" ]; then echo "mode: ARMED — $(cat "$ARM_SENTINEL" 2>/dev/null)"; else echo "mode: SHADOW (log-only; ask prompt fires)"; fi
    echo "state dir: $STATE_DIR"
    echo "soak log:  $LOG_FILE"
    if [ -f "$LOG_FILE" ]; then
      echo "  would-allow events: $(grep -c '"decision":"would-allow"' "$LOG_FILE" 2>/dev/null || echo 0)"
      echo "  allow events:       $(grep -c '"decision":"allow"' "$LOG_FILE" 2>/dev/null || echo 0)"
    else
      echo "  (no soak log yet)"
    fi
    [ "${RESET_HARD_ALLOW_DISABLED:-0}" = "1" ] && echo "KILL SWITCH ACTIVE: RESET_HARD_ALLOW_DISABLED=1 (defers everything)"
    exit 0 ;;
esac

# ── Hook mode ────────────────────────────────────────────────────────────────────────────────
[ "${RESET_HARD_ALLOW_DISABLED:-0}" = "1" ] && exit 0

INPUT=$(cat)
# Fail-closed on malformed input: no command ⇒ defer (the ask prompt handles it).
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null) || exit 0
[ -z "$CMD" ] && exit 0

# ── (1a) metachar / compound guard — defer any compound/substitution/redirection/newline ──────
# A compound line could hide an unsafe command after the safe reset (`git reset --hard origin/main
# && curl x|sh`); a substitution could smuggle an arbitrary ref. Defer every such form to the prompt.
# shellcheck disable=SC2016  # the single-quoted shell metacharacters are LITERALS to match, by design
case "$CMD" in
  *';'*|*'&'*|*'|'*|*'$('*|*'`'*|*'>'*|*'<'*|*$'\n'*) exit 0 ;;
esac

# ── (1b) shape: exactly `git reset --hard <one-token>`, nothing before or after ───────────────
# Anchored ^…$ with a single non-space capture means the WHOLE command must be this four-token
# reset — a leading env-assignment / `git -C dir` / any flag after `--hard` / a trailing token or
# comment all break the anchor → defer. This positive match IS the complete flag guard (no
# negated lookahead, which fails open on macOS ERE).
RESET_RE='^[[:space:]]*git[[:space:]]+reset[[:space:]]+--hard[[:space:]]+([^[:space:]]+)[[:space:]]*$'
[[ "$CMD" =~ $RESET_RE ]] || exit 0
target="${BASH_REMATCH[1]}"
# ── (1c) target allowlist — string equality against the two proven-reversible targets (§B.1) ──
case "$target" in
  origin/main|'@{u}') ;;   # the ONLY auto-allowable targets
  *) exit 0 ;;             # HEAD, HEAD~n, a SHA, origin/<feature>, origin/develop, … → defer
esac

# Resolve the decision cwd from the payload (the reset runs in the session cwd; the anchor already
# excluded `git -C <dir>`, so the target repo IS this dir). Fall back to $PWD for CLI/test contexts.
DIR=$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null)
[ -z "$DIR" ] && DIR="$PWD"
[ -d "$DIR" ] || exit 0

# ── (2) clean tree — `git status --porcelain` must be empty; git failure / dirty ⇒ defer ──────
git -C "$DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
porcelain=$(git -C "$DIR" status --porcelain 2>/dev/null) || exit 0
[ -n "$porcelain" ] && exit 0

# ── (3) sanctioned worktree — a LINKED worktree (absolute-git-dir under .git/worktrees/) ──────
# The primary checkout's absolute-git-dir is `<repo>/.git` (no `/worktrees/`) → defer; a bare repo
# or non-repo → the rev-parse fails or yields no match → defer. Fail-closed on an empty result.
gitdir=$(git -C "$DIR" rev-parse --absolute-git-dir 2>/dev/null) || exit 0
case "$gitdir" in
  */.git/worktrees/*) ;;   # linked worktree → sanctioned
  *) exit 0 ;;             # primary checkout / bare / unresolved → defer
esac

# ── All three conjuncts hold. Log the event; decide by mode (SHADOW logs only; ARMED allows). ──
armed=0; [ -f "$ARM_SENTINEL" ] && armed=1
decision="would-allow"; [ "$armed" = 1 ] && decision="allow"
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // ""' 2>/dev/null)
# Best-effort structured soak log — NEVER block or fail the decision on a log write error.
{
  mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null && \
  printf '{"ts":%s,"decision":"%s","target":"%s","cmd":%s,"cwd":%s,"sid":%s,"clean":true,"linked_worktree":true}\n' \
    "$(jq -Rn --arg v "$(now_utc)" '$v')" "$decision" "$target" \
    "$(jq -Rn --arg v "$CMD" '$v')" "$(jq -Rn --arg v "$DIR" '$v')" "$(jq -Rn --arg v "$SID" '$v')" \
    >> "$LOG_FILE"
} 2>/dev/null || true

# SHADOW: log-only, stay silent → the ask:407 prompt fires (human/desk still approves).
[ "$armed" = 1 ] || exit 0

# ARMED: emit the allow decision.
cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "permissionDecisionReason": "reset-hard-allow: reflog-reversible \`git reset --hard $target\` — clean tree (porcelain empty) + linked worktree; compound/other-target/dirty/primary-checkout all deferred"
  }
}
EOF
exit 0
