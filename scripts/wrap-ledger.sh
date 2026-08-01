#!/usr/bin/env bash
# wrap-ledger.sh — pure-read Session-Close ledger computer (P0-2 / T-P6-1).
#
# THE DEFECT it closes (G-P6-4): the resident Session-Close Protocol claims the readout is
# "un-fakeable" because "the agent runs the git/gate reads itself" — but the tool that runs
# them (`/wrap`) never existed, so the readout was self-report from memory: a model could emit
# "✅ Complete" having read nothing. This script IS that tool: it computes the worst-open rung
# and the --full ledger from LIVE git/gate/DoD facts ONLY, so the rung reports facts.
#
# ── OUTPUT MODES ──
#   wrap-ledger.sh            → one-line human readout (the worst-open rung sentence)   [default]
#   wrap-ledger.sh --machine  → KEY=value lines for hooks (RUNG=… DIRTY=… UNLANDED=… …)
#   wrap-ledger.sh --full     → the dense SESSION LEDGER block (per CLAUDE.md §Session Close)
#
# ── RUNG (worst-open, priority ⛔ > 📤 > 🔧 > 📦 > 👤 > ✅) ──
#   This ledger computes the four FACT-derivable rungs {🔧, 📦, 👤, ✅}. ⛔ (needs-a-decision) and
#   📤 (out-of-context) are model-state, NOT derivable from git — the model overlays them; when
#   present they dominate. Derivation:
#     🔧  dirty tree ∨ gate ran-but-stale-on-HEAD ∨ DoD remainder > 0   (loose ends / unverified)
#     📦  clean ∧ verified-or-n/a ∧ committed-but-unlanded (ahead>0 ∨ git-cherry '+')  (parked)
#     👤  ✅-eligible on the git facts, but THIS SESSION filed operator-only step(s) still unrun
#     ✅  clean ∧ not-stale ∧ landed ∧ remainder = 0 ∧ no unrun operator step from this session
#   committed-but-unlanded is ALWAYS 📦, NEVER a silent ✅ — the FM1 park-and-call-it-done hazard.
#   A DoD file that is ABSENT is reported out loud ("no durable DoD"); a ✅-eligible git state with
#   no DoD is NOT silently upgraded to a clean ✅ (completeness is unverifiable without the DoD).
#
#   👤 (G-CS-1): ✅ claims "safe to close, nothing unsaved", and CLAUDE.md's own ✅ definition
#   already requires "no operator step this session created left unrun" — but nothing COMPUTED
#   that, so a close read ✅ while steps only the operator can run sat filed and unrun. 👤 counts
#   `cc-backlog list --blocked --json` rows whose `.session` equals the CURRENT session id, and
#   NOTHING else: the standing pile (~200 blocked items) already has a home in operator-readout's
#   counted ◆ line, and a rung that counted it would fire at every close forever — an alarm that
#   always fires carries exactly as many bits as one that cannot (MEMORY.md alarm-polarity).
#   Session id: --session > $WRAP_SESSION_ID > $CLAUDE_SESSION_ID > unresolvable. Unresolvable ⇒
#   YOURS=0 + YOURS_SRC=none and the rung stays ✅ — an unknown session NEVER manufactures a 👤.
#
# ── LAW ── fail-LOUD, never fail-silent-open: outside a git repo (or on a read error) this exits
#   non-zero with a stderr note and NEVER prints RUNG=✅. A consumer that can't get a ledger must
#   treat that as "cannot confirm", not as "complete". Pure-read: writes nothing anywhere.
#
# Env seams (tests): WRAP_TRUNK · WRAP_DOD_DIR · WRAP_DOD_FILE · WRAP_GATE_GREEN ·
#                    WRAP_SESSION_ID · CC_BACKLOG_BIN
set -uo pipefail

MODE="readout"
SESSION_FLAG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --machine) MODE="machine" ;;
    --full)    MODE="full" ;;
    --readout|"") MODE="readout" ;;
    --session) shift; SESSION_FLAG="${1:-}" ;;
    --session=*) SESSION_FLAG="${1#--session=}" ;;
    -h|--help) printf 'usage: wrap-ledger.sh [--machine|--full|--readout] [--session <sid>]\n'; exit 0 ;;
    *) printf 'wrap-ledger: unknown arg: %s\n' "$1" >&2; exit 2 ;;
  esac
  shift
done

die_notrepo() {
  printf 'wrap-ledger: not inside a git work tree (%s) — cannot compute a ledger.\n' "$PWD" >&2
  # Emit a structured, NON-✅ machine line so a consumer parsing stdout still sees "unknown".
  [ "$MODE" = "machine" ] && printf 'RUNG=?\nTRUNK=none\nERROR=not-a-git-repo\n'
  exit 3
}

command -v git >/dev/null 2>&1 || { printf 'wrap-ledger: git not found.\n' >&2; exit 3; }
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die_notrepo

# ── Trunk ref: explicit override → origin/HEAD → origin/main → origin/master → none ──
TRUNK="${WRAP_TRUNK:-}"
if [ -z "$TRUNK" ]; then
  TRUNK="$(git rev-parse --abbrev-ref origin/HEAD 2>/dev/null || true)"
  [ -n "$TRUNK" ] || { git rev-parse --verify -q origin/main >/dev/null 2>&1 && TRUNK="origin/main"; }
  [ -n "$TRUNK" ] || { git rev-parse --verify -q origin/master >/dev/null 2>&1 && TRUNK="origin/master"; }
fi
git rev-parse --verify -q "$TRUNK" >/dev/null 2>&1 || TRUNK=""   # unresolvable → treat as no upstream

HEAD_SHA="$(git rev-parse HEAD 2>/dev/null || true)"

# ── Dirty tree ──
PORC="$(git status --porcelain 2>/dev/null || true)"
DIRTY_N="$(printf '%s' "$PORC" | grep -c . 2>/dev/null || echo 0)"; case "$DIRTY_N" in ''|*[!0-9]*) DIRTY_N=0 ;; esac
DIRTY=0; [ "$DIRTY_N" -gt 0 ] && DIRTY=1

# ── Ahead / unlanded-by-content ──
AHEAD=0; CHERRY=0; SHAS=""
if [ -n "$TRUNK" ]; then
  AHEAD="$(git rev-list --count "$TRUNK"..HEAD 2>/dev/null || echo 0)"; case "$AHEAD" in ''|*[!0-9]*) AHEAD=0 ;; esac
  # git cherry prints '+ <sha>' for commits whose patch is NOT present upstream (content-absent).
  if git cherry "$TRUNK" HEAD 2>/dev/null | grep -q '^+ '; then CHERRY=1; fi
  SHAS="$(git rev-list --abbrev-commit "$TRUNK"..HEAD 2>/dev/null | head -5 | tr '\n' ' ' | sed 's/ *$//' || true)"
fi
UNLANDED=0; { [ "$AHEAD" -gt 0 ] || [ "$CHERRY" -eq 1 ]; } && UNLANDED=1

# ── Gate-green marker: green (== HEAD) · stale (present, ≠ HEAD) · none (absent) ──
GATE_FILE="${WRAP_GATE_GREEN:-$(git rev-parse --git-common-dir 2>/dev/null)/gate-green}"
GATE="none"
if [ -f "$GATE_FILE" ]; then
  GATE_SHA="$(head -1 "$GATE_FILE" 2>/dev/null | tr -d '[:space:]' || true)"
  if [ -n "$GATE_SHA" ] && [ "$GATE_SHA" = "$HEAD_SHA" ]; then GATE="green"; else GATE="stale"; fi
fi

# ── Frozen-DoD remainder (unchecked "- [ ]" items). Absent ⇒ reported, never silently ✅. ──
DOD_FILE="${WRAP_DOD_FILE:-}"
if [ -z "$DOD_FILE" ]; then
  DOD_DIR="${WRAP_DOD_DIR:-$HOME/.claude/autonomy/dod}"
  TOP="$(git rev-parse --show-toplevel 2>/dev/null || printf '%s' "$PWD")"
  DHASH="$(printf '%s' "$TOP" | shasum 2>/dev/null | cut -c1-16)"
  DOD_FILE="$DOD_DIR/${DHASH:-unknown}.md"
fi
DOD="absent"; REMAINDER=0
if [ -f "$DOD_FILE" ]; then
  DOD="present"
  REMAINDER="$(grep -cE '^[[:space:]]*[-*][[:space:]]+\[[[:space:]]\]' "$DOD_FILE" 2>/dev/null || echo 0)"
  case "$REMAINDER" in ''|*[!0-9]*) REMAINDER=0 ;; esac
fi

# ── Operator-only steps THIS SESSION filed (the 👤 rung) ──
# Session id, in order: --session > $WRAP_SESSION_ID > $CLAUDE_SESSION_ID > unresolvable ("").
SID="$SESSION_FLAG"
SID_SRC="flag"
[ -n "$SID" ] || { SID="${WRAP_SESSION_ID:-}"; SID_SRC="WRAP_SESSION_ID"; }
[ -n "$SID" ] || { SID="${CLAUDE_SESSION_ID:-}"; SID_SRC="CLAUDE_SESSION_ID"; }
[ -n "$SID" ] || SID_SRC=""

# cc-backlog resolution: env seam first (test stub), then the sibling search order.
_resolve_backlog_bin() {
  if [ -n "${CC_BACKLOG_BIN:-}" ]; then printf '%s' "$CC_BACKLOG_BIN"; return 0; fi
  local c
  for c in "$(dirname "$0")/../bin/cc-backlog" "$HOME/.claude/bin/cc-backlog" \
           "$(command -v cc-backlog 2>/dev/null || true)"; do
    [ -n "$c" ] && [ -x "$c" ] && { printf '%s' "$c"; return 0; }
  done
  return 1
}

# Bound the fork: this runs from a Stop hook on every turn close, and a wedged backlog read must
# never hold the close open. No `timeout` on PATH ⇒ run unbounded rather than lose the signal.
_bounded() { local s="$1"; shift
  if command -v timeout >/dev/null 2>&1; then timeout "$s" "$@"; else "$@"; fi
}

# YOURS = blocked backlog items whose .session == $SID. ANY failure (no binary, non-zero exit,
# no jq, unparseable json, timeout) ⇒ YOURS=0 + YOURS_SRC=error. Fail-OPEN: a backlog we cannot
# read never blocks a close and never invents an operator step.
YOURS=0; YOURS_SRC="skip"        # skip = not computed (a worse rung already governs)
count_operator_steps() {
  if [ -z "$SID" ]; then YOURS=0; YOURS_SRC="none"; return 0; fi
  local bin json n
  bin="$(_resolve_backlog_bin)" || { YOURS=0; YOURS_SRC="error"; return 0; }
  command -v jq >/dev/null 2>&1 || { YOURS=0; YOURS_SRC="error"; return 0; }
  json="$(_bounded "${WRAP_BACKLOG_TIMEOUT_S:-5}" "$bin" list --blocked --json 2>/dev/null)" \
    || { YOURS=0; YOURS_SRC="error"; return 0; }
  n="$(printf '%s' "$json" | jq -r --arg sid "$SID" \
        '[ .[] | select((.session // "") == $sid) ] | length' 2>/dev/null)" \
    || { YOURS=0; YOURS_SRC="error"; return 0; }
  case "$n" in ''|*[!0-9]*) YOURS=0; YOURS_SRC="error"; return 0 ;; esac
  YOURS="$n"; YOURS_SRC="$SID_SRC"
}

# ── Compute the worst-open FACT rung + its readout ──
RUNG="✅"; READOUT="✅ Complete & live on trunk — nothing to do."
if [ "$DIRTY" -eq 1 ]; then
  RUNG="🔧"; READOUT="🔧 Loose ends — ${DIRTY_N} uncommitted change(s) in the tree; continuing."
elif [ "$GATE" = "stale" ]; then
  RUNG="🔧"; READOUT="🔧 Loose ends — gate not green on HEAD (re-run the gate); continuing."
elif [ "$REMAINDER" -gt 0 ]; then
  RUNG="🔧"; READOUT="🔧 Loose ends — ${REMAINDER} frozen-DoD item(s) remain; continuing."
elif [ "$UNLANDED" -eq 1 ]; then
  RUNG="📦"; READOUT="📦 Done, but only on a branch (${AHEAD} commit(s) unlanded) — /ship to land it (else lost)."
else
  # ✅-eligible on the git facts. ONLY here does the operator-step count matter — on the 🔧/📦
  # paths it cannot change the answer, so it is never paid for (cost discipline: Stop hook, every
  # close). A missing trunk means "landed" is unproven, so 👤 (which asserts landed) is not
  # computed there — that case keeps its pre-existing ordering below.
  [ -n "$TRUNK" ] && count_operator_steps
  if [ "$YOURS" -gt 0 ]; then
    # 👤 outranks the absent-DoD note: an unrun operator step is a fact, an unverifiable scope is not.
    RUNG="👤"; READOUT="👤 My side is done & landed — ${YOURS} step(s) need you; see the OPERATOR block."
  elif [ "$DOD" = "absent" ]; then
    # ✅-eligible git state, but no durable DoD to confirm the scope was met → say so, never silent ✅.
    RUNG="✅"; READOUT="✅ Clean & landed — but NO durable DoD to confirm scope (completeness unverified; frozen a DoD via ~/.claude/autonomy/dod)."
  elif [ -z "$TRUNK" ]; then
    RUNG="🔧"; READOUT="🔧 Loose ends — no upstream trunk to compare landing against; continuing."
  fi
fi

emit_machine() {
  printf 'RUNG=%s\n' "$RUNG"
  printf 'READOUT=%s\n' "$READOUT"
  printf 'DIRTY=%s\n' "$DIRTY"
  printf 'DIRTY_N=%s\n' "$DIRTY_N"
  printf 'AHEAD=%s\n' "$AHEAD"
  printf 'CHERRY=%s\n' "$CHERRY"
  printf 'UNLANDED=%s\n' "$UNLANDED"
  printf 'GATE=%s\n' "$GATE"
  printf 'DOD=%s\n' "$DOD"
  printf 'DOD_FILE=%s\n' "$DOD_FILE"
  printf 'REMAINDER=%s\n' "$REMAINDER"
  printf 'YOURS=%s\n' "$YOURS"
  printf 'YOURS_SRC=%s\n' "$YOURS_SRC"
  printf 'TRUNK=%s\n' "${TRUNK:-none}"
  printf 'SHAS=%s\n' "$SHAS"
}

emit_full() {
  local trunk_disp="${TRUNK:-none}"
  local gate_disp; case "$GATE" in
    green) gate_disp="✓ green on HEAD" ;;
    stale) gate_disp="✗ stale (ran on an earlier commit; re-run)" ;;
    *)     gate_disp="n/a (no gate-green marker)" ;;
  esac
  local dod_disp
  if [ "$DOD" = "present" ]; then dod_disp="present · remainder: ${REMAINDER} item(s)"
  else dod_disp="ABSENT (no durable DoD — completeness unverifiable) · expected ${DOD_FILE}"; fi
  printf 'SESSION LEDGER  (live git/gate reads · base = %s)\n' "$trunk_disp"
  printf 'Frozen DoD:     %s\n' "$dod_disp"
  printf 'Dirty tree:     %s\n' "$( [ "$DIRTY" -eq 1 ] && printf 'YES — %s file(s)' "$DIRTY_N" || printf 'no' )"
  printf 'Gate-green:     %s\n' "$gate_disp"
  printf 'Committed:      %s ahead of %s   (%s)\n' "$AHEAD" "$trunk_disp" "${SHAS:-none}"
  printf 'Unlanded(content): %s\n' "$( [ "$UNLANDED" -eq 1 ] && printf 'YES — /ship to land (else lost)' || printf 'no — landed' )"
  local yours_disp; case "$YOURS_SRC" in
    none)  yours_disp="unknown — session id unresolvable (not counted)" ;;
    error) yours_disp="unknown — backlog unreadable (not counted)" ;;
    skip)  yours_disp="not counted (a worse rung governs)" ;;
    *)     yours_disp="$( [ "$YOURS" -gt 0 ] && printf '%s operator-only step(s) filed this session, UNRUN — see the OPERATOR block' "$YOURS" || printf 'none filed this session' )" ;;
  esac
  printf 'Yours (operator): %s\n' "$yours_disp"
  printf 'Rung:           %s\n' "$RUNG"
  printf 'Next:           %s\n' "$(rung_next)"
}

rung_next() {
  case "$RUNG" in
    "🔧") printf 'continue → finish · run-gate · commit (explicit paths)' ;;
    "📦") printf '/ship to land (verified net-positive work is drivable — not a hold)' ;;
    "👤") printf 'surface the OPERATOR block — %s step(s) are the operator'"'"'s (my side is done)' "$YOURS" ;;
    "✅") printf 'complete — nothing to do' ;;
    *)    printf 'model-state (⛔/📤) overrides — surface it' ;;
  esac
}

case "$MODE" in
  machine) emit_machine ;;
  full)    emit_full ;;
  *)       printf '%s\n' "$READOUT" ;;
esac
exit 0
