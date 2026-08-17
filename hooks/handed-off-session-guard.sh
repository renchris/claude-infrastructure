#!/usr/bin/env bash
# handed-off-session-guard.sh — refuse to take a prompt in a session whose transcript was
# TRANSPLANTED to another account. UserPromptSubmit; exit 2 blocks the prompt.
#
# ── THE INCIDENT THIS EXISTS FOR (2026-08-16) ───────────────────────────────────────────────────
# Six next3 sessions were transplanted off a 100%-exhausted account with lr-handoff.sh. Five source
# panes were closed; ONE (`ede6a811`, ~/Development/personal) could not be — `self-close` correctly
# REFUSED it because a live teammate would have been orphaned — and that refusal was treated as a
# note rather than a blocker. When next3's 5-hour window refilled at 18:00 the husk simply carried
# on: it re-created `<sid>.jsonl` in the RETIRED store and ran 40 assistant turns against the same
# session id while its successor ran 218 on another account. The operator typed into it, believing
# it live. Neither copy can ever see the other's turns.
#
# ── WHY THE EXISTING SAFETY DID NOT FIRE ────────────────────────────────────────────────────────
# lr-transplant.sh already writes BOTH artifacts a recovery needs: `<sid>.HANDOFF.json` beside the
# source transcript, and a split-brain lock under ~/.reso/limit-recover/locks/. Eleven scripts read
# them — cc-reaper, cc-classify, lr-audit, the lifecycle gate — and every one of them is a SWEEP or
# a REPORT. Nothing was on the path a running session actually takes, so the tombstone could only
# ever describe the split-brain after the fact. A conclusion that never reaches an enforcing store
# advises; it does not enforce. This hook is that store: it sits on the one event where the harm
# lands — an operator prompt entering a husk.
#
# ── FAIL-OPEN, DELIBERATELY ─────────────────────────────────────────────────────────────────────
# Every unknown resolves to exit 0. A guard that blocks on a parse failure would take out ordinary
# sessions repo-wide the first time a payload shape changed; the failure it prevents is rare and
# recoverable, and the failure it could CAUSE is neither.
#
# Escape hatch: CC_HANDED_OFF_GUARD_DISABLED=1 (or delete the tombstone) — for the legitimate case
# where the successor is dead and the operator is deliberately reviving the source.
set -uo pipefail

[ -n "${CC_HANDED_OFF_GUARD_DISABLED:-}" ] && exit 0

INPUT=$(cat 2>/dev/null || true)
[ -n "$INPUT" ] || exit 0

# Resolve python3 ABSOLUTELY as well as by PATH: hooks inherit a minimal PATH in launchd and
# headless contexts, which is exactly where a PATH-only lookup is silently unavailable.
HOG_PY=""
for _c in /usr/bin/python3 "$(command -v python3 2>/dev/null || true)"; do
  [ -n "$_c" ] && [ -x "$_c" ] && { HOG_PY="$_c"; break; }
done

# Read one top-level string field. The key is anchored on its opening quote AND a preceding
# delimiter so a longer key cannot satisfy it — `"session_id"` must not be answered by
# `"parent_session_id"`, the greedy-suffix match that has cost this repo a defect before.
hog_field() {
  local key="$1"
  if [ -n "$HOG_PY" ]; then
    printf '%s' "$INPUT" | "$HOG_PY" -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: sys.exit(0)
v=d.get(sys.argv[1]) if isinstance(d,dict) else None
print(v if isinstance(v,str) else "")
' "$key" 2>/dev/null
  else
    printf '%s' "$INPUT" | sed -n 's/.*[{,[:space:]]"'"$key"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1
  fi
}

SID=$(hog_field session_id)
TP=$(hog_field transcript_path)
[ -n "$SID" ] && [ -n "$TP" ] || exit 0

TOMB="$(dirname "$TP")/$SID.HANDOFF.json"
[ -f "$TOMB" ] || exit 0

TARGET=""
if [ -n "$HOG_PY" ]; then
  TARGET=$("$HOG_PY" -c '
import json,sys
try: d=json.load(open(sys.argv[1]))
except Exception: sys.exit(0)
print(d.get("handed_off_to") or "")
' "$TOMB" 2>/dev/null)
else
  TARGET=$(sed -n 's/.*[{,[:space:]]"handed_off_to"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$TOMB" | head -1)
fi
[ -n "$TARGET" ] || exit 0

# ── Am I the TARGET or the SOURCE? ──────────────────────────────────────────────────────────────
# The successor carries the SAME session id, so identity is the whole question. Two independent
# answers, either of which acquits:
#   (a) my transcript already sits under the target config dir, or
#   (b) my account and the target's are the same ACCOUNT.
# (b) needs the mirror: `~/.claude` and `~/.claude-next` are two directories for ONE account
# (documented in the resume-sessions skill), so a bare string compare would convict every next
# successor of being its own predecessor — the one false positive that would matter.
case "$TP" in "$TARGET"/*) exit 0 ;; esac

hog_acct() {
  case "$(basename "${1%/}")" in
    .claude|.claude-next) printf 'next' ;;
    *) printf '%s' "$(basename "${1%/}")" ;;
  esac
}
ME="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
[ "$(hog_acct "$TARGET")" = "$(hog_acct "$ME")" ] && exit 0

cat >&2 <<EOF
⛔ THIS PANE IS A RETIRED SOURCE — your prompt was NOT delivered.

Session ${SID:0:8} was transplanted to $(hog_acct "$TARGET") ($TARGET) and continues there.
This process still holds the pre-transplant conversation, so anything you say here forks the
session: two copies, neither able to see the other's turns. That is the split-brain the
transplant's tombstone was written to prevent — $TOMB.

  · Say it to the successor instead (it has this whole conversation).
  · Nothing here is lost: this side's transcript stays on disk at $TP.
  · Genuinely reviving this side (successor dead)? Delete the tombstone, or re-run with
    CC_HANDED_OFF_GUARD_DISABLED=1.

Then close this pane.
EOF
exit 2
