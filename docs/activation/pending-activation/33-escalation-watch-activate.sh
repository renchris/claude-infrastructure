#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# 33-escalation-watch  —  register the escalation dead-letter reader as a SessionStart hook (D3)
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# WHAT: ONE idempotent step — insert `~/.claude/hooks/escalation-watch.sh` into
#   `.hooks.SessionStart[0].hooks[]` in ~/.claude/settings.json, after backing the file up.
#
# WHY ONLY THAT: the hook FILE reaches ~/.claude/hooks/ through the repo's normal deploy (the
#   per-file symlink layer, scripts/deploy-live.sh → install.sh). Nothing here copies or links the
#   script — this activation's ONLY job is the settings.json registration, because a hook that
#   exists on disk but appears in no settings.json event array is a file, not a hook. (Conversely, a
#   registration pointing at a path the deploy has not created yet fails open and silently: the
#   verification step below is what tells you which of the two states you are in.)
#
# WHY IT MATTERS: escalation records are written into four dead-letter stores and, until this hook,
#   NOTHING session-facing read them. The push lane is liveness-dependent and currently dead — a live
#   sweep row reads `"notified":"no-desk-role","delivered":false` while carrying new pages, alarms
#   and stuck completion pushes. SessionStart is the one event that cannot be dead for a session that
#   is starting, which is what makes this the GUARANTEED reader (F6/F7/F8/F9).
#
# WHY C10 (agent stages; operator runs): editing settings.json changes how every future session
#   boots. Kill switch after activation: `CC_ESCALATION_WATCH=0`, or remove the entry again.
# Mark done:  touch <this file>.done
# ───────────────────────────────────────────────────────────────────────────────────────────────────
set -uo pipefail
SETTINGS="${CC_SETTINGS_FILE:-$HOME/.claude/settings.json}"
# shellcheck disable=SC2088  # the LITERAL `~/…` is required: every sibling SessionStart entry in
#   settings.json stores this exact form and Claude Code expands it, not the shell. Writing $HOME
#   here would insert an absolute path that no longer matches the file's own convention, and would
#   silently break the idempotency check on any machine whose $HOME differs.
HOOK_CMD="~/.claude/hooks/escalation-watch.sh"
# 10s, not activation-watch's 5s: this box runs above 2.0 load/core routinely and the hook takes one
# perl fork over the whole record corpus (measured 0.4 s live, ~2.6k records). Headroom, not slack —
# a SessionStart hook that times out is a reader that silently is not there.
TIMEOUT=10
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"

echo "== 33-escalation-watch =="
command -v jq >/dev/null 2>&1 || { echo "✗ jq required" >&2; exit 1; }
[ -f "$SETTINGS" ] || { echo "✗ no settings file at $SETTINGS" >&2; exit 1; }
jq -e . "$SETTINGS" >/dev/null 2>&1 || { echo "✗ $SETTINGS is not valid JSON — refusing to touch it" >&2; exit 1; }

# IDEMPOTENCY, checked BEFORE the backup so a re-run leaves no litter behind it.
if jq -e --arg c "$HOOK_CMD" '[.hooks.SessionStart[]?.hooks[]?.command] | index($c)' "$SETTINGS" >/dev/null 2>&1; then
  echo "· already registered — nothing to do."
  grep -n 'escalation-watch' "$SETTINGS" || true
  echo "(re-running this script is safe; it makes no change once the entry exists.)"
  exit 0
fi

echo "Will do: [1] back up $SETTINGS → $SETTINGS.bak-$STAMP"
echo "         [2] jq-insert { type: command, command: $HOOK_CMD, timeout: $TIMEOUT }"
echo "             into .hooks.SessionStart[0].hooks[]  (append; no existing entry is reordered)"
echo "         [3] verify by reading the entry back out of the written file"

if [ "${CONFIRM:-0}" != 1 ]; then
  echo
  echo "(dry run — re-run with CONFIRM=1 to apply:)"
  echo "    CONFIRM=1 bash $HOME/.claude/autonomy/pending-activation/33-escalation-watch-activate.sh"
  exit 0
fi

echo "[1] backup"
cp -p "$SETTINGS" "$SETTINGS.bak-$STAMP" || { echo "✗ backup failed — NOT editing settings" >&2; exit 1; }
echo "  · $SETTINGS.bak-$STAMP"

echo "[2] insert"
# Append to the FIRST SessionStart matcher group, creating the structure if this settings file has
# none. Order within the group is not load-bearing (SessionStart hooks are independent, and this one
# is advisory + read-only), so appending is the least invasive shape.
TMP="$(mktemp "${TMPDIR:-/tmp}/settings.XXXXXX")" || { echo "✗ mktemp failed" >&2; exit 1; }
jq --arg c "$HOOK_CMD" --argjson t "$TIMEOUT" '
  .hooks //= {}
  | .hooks.SessionStart //= [{hooks: []}]
  | if (.hooks.SessionStart | length) == 0 then .hooks.SessionStart = [{hooks: []}] else . end
  | .hooks.SessionStart[0].hooks //= []
  | .hooks.SessionStart[0].hooks += [{type: "command", command: $c, timeout: $t}]
' "$SETTINGS" > "$TMP" || { echo "✗ jq edit failed — settings.json untouched" >&2; rm -f "$TMP"; exit 1; }

# Never `mv` an unvalidated file over settings.json: a truncated or malformed settings.json breaks
# EVERY future session, and the backup above is only useful to someone who knows to look for it.
jq -e . "$TMP" >/dev/null 2>&1 || { echo "✗ produced invalid JSON — settings.json untouched" >&2; rm -f "$TMP"; exit 1; }
mv -f "$TMP" "$SETTINGS" || { echo "✗ move failed — restore with: cp $SETTINGS.bak-$STAMP $SETTINGS" >&2; exit 1; }

echo "[3] verify (read back out of the file that was actually written)"
if jq -e --arg c "$HOOK_CMD" '[.hooks.SessionStart[]?.hooks[]?.command] | index($c)' "$SETTINGS" >/dev/null 2>&1; then
  jq -r --arg c "$HOOK_CMD" '.hooks.SessionStart[]?.hooks[]? | select(.command == $c)
                             | "  ✓ registered: \(.command)  (timeout \(.timeout)s)"' "$SETTINGS"
else
  echo "✗ NOT found after write — restore with: cp $SETTINGS.bak-$STAMP $SETTINGS" >&2
  exit 1
fi

# The registration and the file are two independent facts; report the second one honestly rather
# than letting a green registration imply a live hook.
if [ -e "$HOME/.claude/hooks/escalation-watch.sh" ]; then
  echo "  ✓ hook file present: $HOME/.claude/hooks/escalation-watch.sh"
else
  echo "  ⚠ hook file NOT yet at $HOME/.claude/hooks/escalation-watch.sh — it arrives via the normal"
  echo "    deploy (bash \$REPO/scripts/deploy-live.sh, which runs install.sh and creates the symlink)."
  echo "    Until then this registration is inert and fails open. Registration itself is done."
fi

echo
echo "DONE. Takes effect in the NEXT session (SessionStart fires at session boot, not on this shell)."
echo "Smoke it now:    bash $HOME/.claude/hooks/escalation-watch.sh --selftest"
echo "See it render:   bash $HOME/.claude/hooks/escalation-watch.sh | jq -r '.hookSpecificOutput.additionalContext'"
echo "  (EMPTY output is the healthy state — zero unseen records means the hook says nothing.)"
echo "Kill switch:     export CC_ESCALATION_WATCH=0"
echo "Then:  touch $HOME/.claude/autonomy/pending-activation/33-escalation-watch-activate.sh.done"
