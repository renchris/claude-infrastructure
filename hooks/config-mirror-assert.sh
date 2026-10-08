#!/bin/bash
# SessionStart backstop: re-assert the knowledge-layer mirror for the CURRENT account, in case a
# session was launched WITHOUT the zsh wrapper (raw `claude`, IDE, --resume). No-op for account 1
# (default ~/.claude, CLAUDE_CONFIG_DIR unset) and for any non-claude config dir. Race-safe: runs
# the mirror in default (no --convert) mode, which only creates missing symlinks + heals leaks.
# A hook fires AFTER config is loaded, so it fixes the NEXT session, not the running one — the
# launcher wrapper is the primary mechanism; this is belt-and-suspenders.
set -euo pipefail
cfg="${CLAUDE_CONFIG_DIR:-}"
[ -z "$cfg" ] && exit 0                        # account 1 default → nothing to mirror
[ "$cfg" = "$HOME/.claude" ] && exit 0         # the source itself
case "$cfg" in "$HOME/.claude-"*) ;; *) exit 0 ;; esac
# -f = skip rc files (fast, no p10k/nvm cost); source the single-source-of-truth lib, then sync.
# Stderr is CAPTURED rather than discarded: the mirror reports a forked real dir there (a condition
# safe mode cannot fix, so it survives every future run until someone converts it), and discarding
# that is what let ~/.claude-next carry a frozen `commands` for seven weeks with nothing said.
err="$(zsh -fc "source \"$HOME/.claude/lib/config-mirror.zsh\"; _cc_sync_account \"$cfg\"" 2>&1 >/dev/null || true)"
forks="$(printf '%s\n' "$err" | grep -c 'FORKED real' 2>/dev/null || true)"
# Only warnings are emitted. The healthy "re-asserted" line said nothing a session could act on and
# was re-read for the rest of every context (docs/research/token-efficiency-2026-09-23/measure/hooks.md
# §5 row 11); a clean run is now silent, and `msg` stays empty unless a check below finds something.
msg=""
if [ "${forks:-0}" -gt 0 ] 2>/dev/null; then
  # Backups are not findings. A median 216 forked names (p90 425) were ~90% settings.json.bak-*
  # copies that shadow nothing anyone reads, and reporting them made a 746-entry line out of 3 real
  # forks. So only NON-backup forks are counted and named; a fork list that is all backups says
  # nothing. "Backup" is the library's own rule (lib/config-mirror.zsh: `${forks:#*bak*}`), not a
  # second definition: two readers of one list must agree on what they skip.
  names="$(printf '%s\n' "$err" | sed -n "s/.*FORKED real '\([^']*\)'.*/\1/p")"
  live="$(printf '%s\n' "$names" | grep -v 'bak' | grep -v '^$' || true)"
  if [ -n "$live" ]; then
    nlive="$(printf '%s\n' "$live" | wc -l | tr -d ' ')"
    case "$nlive" in ''|*[!0-9]*) nlive=0 ;; esac
    shown="$(printf '%s\n' "$live" | head -5 | paste -sd' ' - || true)"
    more=""
    [ "$nlive" -gt 5 ] 2>/dev/null && more=" (+$(( nlive - 5 )) more: zsh -fc 'source ~/.claude/lib/config-mirror.zsh; _cc_sync_account $cfg' 2>&1 | grep FORKED | grep -v bak)"
    msg="⚠ $nlive FORKED real entry(ies) shadow ~/.claude in ${cfg##*/}: $shown$more — this account does NOT see updates to them. Converge with all that account's panes closed: zsh -fc 'source ~/.claude/lib/config-mirror.zsh; _cc_sync_account --convert $cfg'"
  fi
fi
# ── settings parity (migration 0037) ─────────────────────────────────────────────────────────────
# settings.json is the one FORKED entry that changes BEHAVIOUR — it decides which hooks, permission
# rules and classifier rules this account runs — so it gets its own line naming WHAT differs from the
# shared file, instead of sitting anonymously in the count above. Operator ruling 2026-09-23:
# accounts are interchangeable, so any difference is a defect. Silent once the account's
# settings.json is a symlink to ~/.claude/settings.json; it speaks again if something re-forks it.
par="$HOME/.claude/bin/cc-settings-parity"
if [ -f "$par" ] && command -v python3 >/dev/null 2>&1; then
  pline="$(python3 "$par" check --account-dir "$cfg" --brief 2>/dev/null || true)"
  [ -n "$pline" ] && msg="${msg:+$msg  }$pline"
fi

# ── HOOK_SURFACE_100P §4 registration assertion (migration 0019) ─────────────────────────────────
# The plan asks for "the expected registration COUNT". A count is the wrong instrument: every
# legitimate registration change moves it, so it false-alarms until someone edits a magic number,
# and an alarm that fires on correct behaviour says as little as one that cannot fire at all
# (MEMORY.md alarm-polarity-and-attention-budget). A NAMED-presence check has the same protective
# value with no maintenance drift — it goes off only when a registration we deliberately made has
# VANISHED, which is the actual failure mode (a malformed sibling entry silently disabling the file).
#
# HONEST LIMIT, stated because it would otherwise read as fuller cover than it is: this hook is
# itself registered in settings.json, so if that file is wholly disabled this check does not run
# either — it detects DRIFT (an entry removed, a file half-edited), never total-disable. Detecting
# total-disable needs an observer outside the hook system; deploy-live is the natural home and it
# does not do this today.
sf="$cfg/settings.json"
if [ -f "$sf" ] && command -v jq >/dev/null 2>&1; then
  # `. as $root` FIRST: inside range() the dot is the range's NUMBER, not the document, so an
  # unqualified .hooks[...] there indexes an integer and jq dies. Caught by the drift control below,
  # which is why that control had to be one that could actually fail.
  missing="$(jq -r '
      . as $root
      | ["StopFailure","stop-failure-marker","InstructionsLoaded","instructions-loaded","PostToolBatch","post-tool-batch"]
        as $pairs
      | [range(0; ($pairs|length); 2) as $i
         | $pairs[$i] as $ev | $pairs[$i+1] as $frag
         | select( ([$root.hooks[$ev][]?.hooks[]?.command] | map(select(test($frag))) | length) == 0 )
         | $ev ]
      | join(" ")' "$sf" 2>/dev/null || true)"
  # Only speak when at least one is present — i.e. after 0019 has run. Before that they are ALL
  # absent by design, and announcing that every session would be the always-firing alarm above.
  any_present="$(jq -r '[.hooks.StopFailure[]?.hooks[]?.command,
                         .hooks.InstructionsLoaded[]?.hooks[]?.command,
                         .hooks.PostToolBatch[]?.hooks[]?.command] | length' "$sf" 2>/dev/null || echo 0)"
  if [ "${any_present:-0}" -gt 0 ] 2>/dev/null && [ -n "${missing:-}" ]; then
    msg="${msg:+$msg  }⚠ hook-surface registration DRIFT in ${cfg##*/}: $missing registered by migration 0019 is now ABSENT — a hook we wired is silently not running. Re-run: bash ~/Development/claude-infrastructure/migrations/0019-hook-surface-registration.sh"
  fi
fi

# ── per-agent token budget (decision D6, migration 0060) ─────────────────────────────────────────
# The server can turn on a per-agent token budget (flags tengu_rippling_tulip /
# tengu_streamed_bumblebee); sub-agents shown one stop early with no error. Speak only when THIS
# account's cache holds a flag ON while CLAUDE_CODE_RIPPLING_TULIP=0 is absent from its settings env:
# silent on 2026-10-08, when no account caches either flag. ~0.08 s (two jq reads), measured inside a
# ~1.1 s child the dispatcher runs in parallel.
abf="$HOME/.claude/bin/cc-agent-budget-flags"
if [ -x "$abf" ]; then
  bline="$("$abf" --account-dir "$cfg" --brief 2>/dev/null || true)"
  [ -n "$bline" ] && msg="${msg:+$msg  }$bline"
fi

[ -n "$msg" ] || exit 0
msg="knowledge-layer mirror (${cfg##*/}): $msg"

# Top-level `systemMessage`, not additionalContext: it renders in the operator's terminal at 0 model
# tokens, where additionalContext is model context the TUI hides (hooks/accounts-board.sh header has
# the channel proof; 0 of ~720 sessions in 7 days acted on this line as context). The key must be
# top-level: hookSpecificOutput.systemMessage is silently ignored.
# Built with a real encoder — the message carries operator text and paths, and a printf-built string
# would break the hook's stdout contract on the first quote or backslash.
CC_MSG="$msg" python3 -c 'import json,os;print(json.dumps({"systemMessage":os.environ["CC_MSG"]}))' 2>/dev/null \
  || printf '{"systemMessage":"knowledge-layer mirror for %s reported a warning; run the mirror by hand to see it."}\n' "${cfg##*/}"
exit 0
