#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# curl-gate-scope.sh — a bash scope gate in front of the project-scoped curl-gate.py
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# WHY (docs/plans/HOOK_CHAIN_COST.md §3, backlog 2193948bb00e / MACHINE_CAPACITY_V2.md §8.5.4):
#   curl-gate.py is PROJECT-SCOPED — `if not cwd.startswith(PROJECT_ROOT): sys.exit(0)`
#   (hooks/curl-gate.py:409-410, PROJECT_ROOT=/Users/chrisren/Development/reso-management-app) —
#   but it is registered on the GLOBAL PreToolUse/Bash chain. So every Bash tool call in every
#   OTHER project pays a full python3 interpreter startup to reach a bare exit 0.
#
#   MEASURED (load 16, 10 iterations, median): curl-gate.py 35.41 ms · `python3 -c pass` 31.45 ms
#   · `bash -c :` 7.35 ms. The gate's own work is ~4 ms; the INTERPRETER is the cost, and no edit
#   inside the .py can recover it — python is already running by the time line 409 is reachable.
#   This shim makes the out-of-scope decision in bash and execs python ONLY when the gate could
#   actually decide something.
#
# ── EQUIVALENCE CONTRACT (the thing the tests pin) ─────────────────────────────────────────────────
#   The shim MUST delegate whenever curl-gate.py could emit anything other than a bare exit 0.
#   curl-gate.py's own no-op preconditions (main(), :387-415) are:
#       (1) CURL_GATE_DISABLED=1      (2) tool_name != "Bash"
#       (3) cwd not under PROJECT_ROOT (4) "curl" not a substring of tool_input.command
#   This shim replicates ONLY (3), the most selective one, and defers 1/2/4 to the real gate.
#   Replicating FEWER conditions is always SAFE — a needless delegation costs ~28 ms and never
#   changes a verdict. Replicating MORE would risk the shim and the gate diverging on semantics,
#   which on a security gate is the dangerous direction. So: one condition, the cheapest to get
#   right, and it is checked against the RAW payload bytes.
#
#   WHY THE RAW-BYTES TEST IS SOUND, AND WHY IT IS NOT A BYPASS:
#   The test is "does the literal PROJECT_ROOT path appear anywhere in the payload". It can only
#   ever produce FALSE NEGATIVES for delegation in one direction — a payload that does NOT contain
#   the path cannot have a `cwd` under it, because `cwd` is serialized by Claude Code itself
#   (JSON.stringify, which never \u-escapes printable ASCII), not by the user. A crafted COMMAND
#   string cannot suppress the match: it can only ADD occurrences, which delegates MORE. There is
#   therefore no attacker-reachable input that skips a gate decision the incumbent would have made.
#   Deliberately NOT tested here: the "curl" substring. That one IS attacker-influenced (a \u-escaped
#   spelling in the command would evade a raw-bytes test while curl-gate.py's own parsed check still
#   catches it), so replicating it in the shim would open exactly the bypass the gate exists to close.
#
# FAIL-OPEN, and it must be: this sits on the PreToolUse chain, where row 6's standing constraint is
#   "a hook failure must never block a tool by accident". Every failure path here exits 0 with no
#   stdout, which is the incumbent's own no-op answer. If the real gate is missing/unreadable we do
#   NOT invent a verdict — but note the shim can only ever be MORE permissive than a python3 that
#   failed to start, which is the same posture the chain already had.
#
# Kill switch: CC_CURL_GATE_SCOPE=off → always delegate (i.e. exact incumbent behaviour, no shim).
# ───────────────────────────────────────────────────────────────────────────────────────────────────
set -uo pipefail

# Resolve the real gate relative to THIS file's PHYSICAL location, so a symlinked live layer
# (~/.claude/hooks/* are per-file symlinks into the checkout) still finds its sibling in the
# checkout rather than in the live dir. Same ladder the other hooks use.
_self="${BASH_SOURCE[0]}"
while [ -L "$_self" ]; do
  _link="$(readlink "$_self")"
  case "$_link" in /*) _self="$_link" ;; *) _self="$(dirname "$_self")/$_link" ;; esac
done
HOOK_DIR="$(cd "$(dirname "$_self")" && pwd)"
GATE="${CC_CURL_GATE_BIN:-$HOOK_DIR/curl-gate.py}"

# PROJECT_ROOT is duplicated from curl-gate.py:36 BY NECESSITY (we must decide before paying for
# python). tests/curl-gate-scope.bats asserts the two spellings are identical, so a change to the
# .py that this shim did not follow goes RED instead of silently narrowing the gate's reach.
PROJECT_ROOT="${CC_CURL_GATE_ROOT:-/Users/chrisren/Development/reso-management-app}"

# Read the whole payload with the BUILTIN read — no `cat` fork. -d '' reads to EOF; it returns
# non-zero at EOF, which is the normal case here, so the rc is deliberately ignored.
input=""
IFS= read -r -d '' input || true

delegate() {
  [ -r "$GATE" ] || exit 0            # nothing to delegate to ⇒ incumbent no-op posture
  printf '%s' "$input" | python3 "$GATE"
  exit $?
}

[ "${CC_CURL_GATE_SCOPE:-on}" = "off" ] && delegate
[ -n "$input" ] || exit 0             # empty payload ⇒ the gate would exit 0 at :394-397 anyway

# The one replicated condition, as a bash builtin test — no fork.
case "$input" in
  *"$PROJECT_ROOT"*) delegate ;;
esac

# A LINKED WORKTREE of PROJECT_ROOT lives OUTSIDE it (this machine creates them under
# $HOME/Development/.worktrees/), so the prefix test above cannot see one — it exited 0
# calling itself "a proven no-op" while 64 live reso worktrees ran ungated (2026-08-10).
# The shim cannot tell WHOSE worktree it is without reading that worktree's .git pointer,
# so it delegates and lets curl-gate.py's in_project_scope() make the precise call.
# Gated on the payload mentioning curl at all, so the no-fork fast path is preserved for
# every non-curl Bash call — which is the cost this shim exists to avoid.
WORKTREES_ROOT="${CC_CURL_GATE_WORKTREES_ROOT:-$HOME/Development/.worktrees}"
case "$input" in
  *curl*)
    case "$input" in
      *"$WORKTREES_ROOT"*) delegate ;;
    esac
    ;;
esac

exit 0                                # not PROJECT_ROOT, not a worktree ⇒ genuinely out of scope
