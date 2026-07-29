#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# 16-session-beat  —  wire the SESSION PRESENCE BEAT into the LIVE per-account settings.json
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# WHAT: adds, to EVERY config dir that has a settings.json:
#
#     UserPromptSubmit += ~/.claude/hooks/session-beat.sh prompt   (timeout 5)
#     Stop             += ~/.claude/hooks/session-beat.sh stop     (timeout 5)
#
# WHY: SESSION_REGISTRY_V2 §4.1. The beat is how a session ATTESTS "an operator drove this turn" at
#   the instant it knows it, instead of every closer re-deriving it from multi-MB transcripts on every
#   sweep. Measured on the incumbent (1,872 sweeps): the reap decision was a batch snapshot acted on
#   up to 2,099s later (p99; max 55,659s), so an operator typing DURING a sweep was invisible to the
#   decision closing their pane — the 2026-07-24 reaps of two live operator conversations.
#
#   UNTIL THIS RUNS THE PRODUCER IS INERT. That is not silent: cc-reaper's act-time re-take is gated
#   on cb_system_live (the existence gate), which logs `beat-system-inert` and falls back to the v1
#   legs rather than pretending the world is beat-less-because-idle. A built-but-unwired mechanism
#   that fails quiet is the failure mode this repo has hit repeatedly; this one announces itself.
#
# WHY C10 (agent stages; operator runs): this mutates the live harness config of every account. A bad
#   write here breaks every session that starts afterwards, so the agent never self-activates hooks.
#
# SAFETY: per-dir backup to <dir>/settings.json.pre-session-beat.bak BEFORE any write · jq only, never
#   sed · post-write validation (parses AND both commands present) · a failed validation RESTORES that
#   dir's backup and ABORTS LOUD · already-wired dirs are SKIPPED (idempotent, no double-add).
#
# COST: ~2ms per turn. The hook is fail-open by construction (background worker + hard timeout +
#   unconditional exit 0) — a beat can never block, delay or kill a turn.
#
# KILL SWITCH: CC_BEAT=off in the environment makes the producer a no-op without unwiring anything.
#
# RUN IT:  CONFIRM=1 bash ~/.claude/autonomy/pending-activation/16-session-beat-activate.sh
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
set -uo pipefail

# The tilde below is DELIBERATELY unexpanded: these strings are written VERBATIM into settings.json,
# where Claude Code expands them itself. Every existing entry uses this exact form (e.g.
# "~/.claude/hooks/session-register.sh"); substituting $HOME would bake this machine's absolute path
# into a config shared across accounts and templates. The directive must be the LAST comment before
# the command it covers, so it sits immediately above each assignment.
# shellcheck disable=SC2088
UP_CMD='~/.claude/hooks/session-beat.sh prompt'
# shellcheck disable=SC2088
ST_CMD='~/.claude/hooks/session-beat.sh stop'
HOOK="$HOME/.claude/hooks/session-beat.sh"
LIB="$HOME/.claude/hooks/lib/cc-beat.sh"

command -v jq >/dev/null 2>&1 || { echo "⛔ jq required"; exit 2; }

if [ "${CONFIRM:-0}" != 1 ]; then
  cat <<EOF
16-session-beat — DRY RUN (nothing written).
Would append to every config dir's settings.json:
  UserPromptSubmit += $UP_CMD
  Stop             += $ST_CMD
Re-run with:  CONFIRM=1 bash \$0
EOF
  exit 0
fi

# ── Preflight: the hook and its reader must EXIST live, else wiring points at nothing. Both are
#    BRAND-NEW files, and per-file symlink dirs never link a new file, so this is the exact case
#    where "landed" does not mean "deployed" (deploy-lag-checkout-behind-origin).
missing=0
for f in "$HOOK" "$LIB"; do
  if [ ! -e "$f" ]; then echo "⛔ MISSING live file: $f"; missing=1; fi
done
if [ "$missing" = 1 ]; then
  cat <<'EOF'
   The beat files are landed on origin/main but NOT deployed into the live layer.
   Fix first (installs the new symlinks), then re-run this activation:
     bash /Users/chrisren/Development/claude-infrastructure/install.sh
EOF
  exit 2
fi
[ -x "$HOOK" ] || chmod +x "$HOOK" 2>/dev/null

wired=0; skipped=0; failed=0
for dir in "$HOME/.claude" "$HOME/.claude-secondary" "$HOME/.claude-tertiary" "$HOME/.claude-quaternary"; do
  S="$dir/settings.json"
  [ -f "$S" ] || { echo "—  $dir: no settings.json, skipping"; continue; }

  if jq -e --arg u "$UP_CMD" --arg s "$ST_CMD" '
        ((.hooks.UserPromptSubmit // []) | map(.hooks[]?.command) | flatten | index($u)) and
        ((.hooks.Stop             // []) | map(.hooks[]?.command) | flatten | index($s))' "$S" >/dev/null 2>&1; then
    echo "✓  $dir: already wired (idempotent skip)"; skipped=$((skipped+1)); continue
  fi

  cp -p "$S" "$S.pre-session-beat.bak" || { echo "⛔ $dir: backup failed, NOT touching"; failed=$((failed+1)); continue; }

  # Append into the FIRST group of each event (a hook list is a list of groups; appending a command
  # to an existing group never disturbs a sibling group). Create the event if absent.
  if jq --arg u "$UP_CMD" --arg s "$ST_CMD" '
        def add($ev; $cmd):
          if (.hooks[$ev] // null) == null
          then .hooks[$ev] = [{matcher:null, hooks:[{type:"command", command:$cmd, timeout:5}]}]
          elif ((.hooks[$ev] | map(.hooks[]?.command) | flatten | index($cmd)) != null) then .
          else .hooks[$ev][0].hooks += [{type:"command", command:$cmd, timeout:5}]
          end;
        add("UserPromptSubmit"; $u) | add("Stop"; $s)' "$S" > "$S.tmp" 2>/dev/null \
     && jq -e . "$S.tmp" >/dev/null 2>&1 \
     && jq -e --arg u "$UP_CMD" --arg s "$ST_CMD" '
            ((.hooks.UserPromptSubmit | map(.hooks[]?.command) | flatten | index($u)) != null) and
            ((.hooks.Stop             | map(.hooks[]?.command) | flatten | index($s)) != null)' "$S.tmp" >/dev/null 2>&1
  then
    mv -f "$S.tmp" "$S"; echo "✓  $dir: wired"; wired=$((wired+1))
  else
    rm -f "$S.tmp"; cp -p "$S.pre-session-beat.bak" "$S"
    echo "⛔ $dir: write/validation FAILED — backup restored, nothing changed"; failed=$((failed+1))
  fi
done

echo
echo "16-session-beat: wired=$wired skipped=$skipped failed=$failed"
[ "$failed" -gt 0 ] && { echo "⛔ at least one dir failed — see above"; exit 2; }
cat <<'EOF'
✓ Beat producer wired. It takes effect in sessions started (or prompts submitted) from now on.

VERIFY (disk truth — acceptance A1, run after submitting one prompt in any session):
  ls ~/.claude/cc-beats/*.json | wc -l          # > 0
  jq -c '{sid,who,operatorT,seq}' ~/.claude/cc-beats/*.json | tail -3
EOF
exit 0
