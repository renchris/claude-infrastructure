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
lib="$HOME/.claude/lib/config-mirror.zsh"

# THE MEMORY WALK IS SPLIT (docs/research/startup-hooks-2026-10-18 README §5 unit 5.7). This child
# used to run _cc_sync_account inline, whose memory walk visits every project slug: 2.8 s p50 and
# 4.1 s p90 on the isolated accounts, the slowest SessionStart child in 65 of 68 dispatcher runs, and
# past the dispatcher's 9 s bound at high load, which killed the checks below with it. Now only the
# session's OWN slug is linked inline (from the payload's transcript_path, and only when that path
# lies under this account's projects/), the config mirror and the checks run next, and the full walk
# starts last as a detached single-flight sweep (sweep_start below) whose result nobody here waits
# for. Bounded stdin read, as hooks/session-start.sh does: a caller that leaves stdin open costs at
# most a second, never a hung start.
payload="" own=""
if [ ! -t 0 ]; then IFS= read -r -d '' -t 1 payload || true; fi
if [ -n "$payload" ] && command -v jq >/dev/null 2>&1; then
  tp="$(printf '%s' "$payload" | jq -r '.transcript_path // empty' 2>/dev/null || true)"
  tdir="${tp%/*}"
  [ -n "$tp" ] && [ "${tdir%/*}" = "$cfg/projects" ] && own="${tdir##*/}"
fi

# -f = skip rc files (fast, no p10k/nvm cost); source the single-source-of-truth lib, then sync.
# Stderr is CAPTURED rather than discarded: the mirror reports a forked real dir there (a condition
# safe mode cannot fix, so it survives every future run until someone converts it), and discarding
# that is what let ~/.claude-next carry a frozen `commands` for seven weeks with nothing said.
# Arguments go in as positionals, never spliced into the script text. The `sweep-wanted` line tells
# sweep_start whether this account has a memory walk at all (~/.claude-next shares projects/, so it
# has none); the order mirrors _cc_sync_account, which skips memory when the config mirror fails.
# shellcheck disable=SC2016  # the single-quoted text is zsh source; $1-$3 expand inside zsh
err="$(zsh -fc '
  source "$1" || exit 1
  _cc_sync_config_mirror "$2" || exit 1
  if (( $+functions[_cc_memory_mirror_wanted] )) && _cc_memory_mirror_wanted "$2"; then
    print -u2 "config-mirror-assert: sweep-wanted"
    [[ -z "$3" ]] || _cc_sync_memory_mirror --slug "$3" "$2"
  fi' zsh "$lib" "$cfg" "$own" 2>&1 >/dev/null || true)"
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

if [ -n "$msg" ]; then
  msg="knowledge-layer mirror (${cfg##*/}): $msg"
  # Top-level `systemMessage`, not additionalContext: it renders in the operator's terminal at 0
  # model tokens, where additionalContext is model context the TUI hides (hooks/accounts-board.sh
  # header has the channel proof; 0 of ~720 sessions in 7 days acted on this line as context). The
  # key must be top-level: hookSpecificOutput.systemMessage is silently ignored.
  # Built with a real encoder — the message carries operator text and paths, and a printf-built
  # string would break the hook's stdout contract on the first quote or backslash.
  CC_MSG="$msg" python3 -c 'import json,os;print(json.dumps({"systemMessage":os.environ["CC_MSG"]}))' 2>/dev/null \
    || printf '{"systemMessage":"knowledge-layer mirror for %s reported a warning; run the mirror by hand to see it."}\n' "${cfg##*/}"
fi

# ── the full memory walk, detached (unit 5.7) ───────────────────────────────────────────────────
# Started only AFTER the report above is written, so a sweep that is slow, killed or never starts
# cannot cost the checks their output. Single-flight twice over: a 600 s stamp throttles re-spawn
# across a /clear burst, and a `mkdir` claim keeps two starts that pass the stamp together from both
# walking. The sweep removes the claim when it finishes; a claim older than 1800 s belongs to a
# sweep that died and is broken. scripts/lib/detach.sh gives the sweep its own session, stdin
# /dev/null and its output in the log, so it neither holds this hook's stdout pipe nor dies with the
# dispatcher's process group. Its lines (start, then verdict and ms) go to
# ~/.claude/logs/config-mirror-sweep.log. CC_MIRROR_SWEEP=off disables it; the shell launcher's
# _cc_sync_account still walks every slug on each launch either way.
_cm_deref() {
  local p="$1" t n=0
  while [ -L "$p" ] && [ "$n" -lt 20 ]; do
    t="$(readlink "$p")"
    case "$t" in /*) p="$t" ;; *) p="$(dirname "$p")/$t" ;; esac
    n=$(( n + 1 ))
  done
  printf '%s\n' "$p"
}
sweep_start() {
  [ "${CC_MIRROR_SWEEP:-async}" = off ] && return 0
  case "$err" in *'config-mirror-assert: sweep-wanted'*) ;; *) return 0 ;; esac
  local sd="$HOME/.claude/state/config-mirror" acct="${cfg##*/}" log="$HOME/.claude/logs/config-mirror-sweep.log"
  local stamp="$sd/$acct.sweep-stamp" claim="$sd/$acct.sweep.claim" now last age det
  mkdir -p "$sd" "${log%/*}" 2>/dev/null || return 0
  now="$(date +%s)"
  last="$(stat -f %m "$stamp" 2>/dev/null || echo 0)"
  case "$last" in ''|*[!0-9]*) last=0 ;; esac
  [ $(( now - last )) -ge "${CC_MIRROR_SWEEP_MIN_S:-600}" ] || return 0
  if [ -d "$claim" ]; then
    age="$(stat -f %m "$claim" 2>/dev/null || echo "$now")"
    case "$age" in ''|*[!0-9]*) age="$now" ;; esac
    [ $(( now - age )) -ge "${CC_MIRROR_SWEEP_STALE_S:-1800}" ] && rmdir "$claim" 2>/dev/null
  fi
  mkdir "$claim" 2>/dev/null || return 0
  : > "$stamp" 2>/dev/null || true
  det="$(cd "$(dirname "$(_cm_deref "${BASH_SOURCE[0]}")")/.." 2>/dev/null && pwd)/scripts/lib/detach.sh"
  if [ ! -r "$det" ]; then
    printf '%s config-mirror sweep %s verdict=error reason=detach-missing\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$acct" >>"$log" 2>/dev/null || true
    rmdir "$claim" 2>/dev/null || true
    return 0
  fi
  # shellcheck source=../scripts/lib/detach.sh
  # shellcheck disable=SC1091  # runtime-resolved source; the ship gate runs shellcheck without -x
  . "$det"
  # shellcheck disable=SC2016  # zsh source, expanded by the detached zsh
  detach "$log" zsh -fc '
    zmodload zsh/datetime
    t0=$EPOCHREALTIME rc=1 v=ok
    print -r -- "$(date -u +%Y-%m-%dT%H:%M:%SZ) config-mirror sweep ${2:t} start pid=$$"
    source "$1" && { _cc_sync_memory_mirror "$2"; rc=$? }
    rmdir "$3" 2>/dev/null
    (( rc )) && v=error
    ms=$(( (EPOCHREALTIME - t0) * 1000 ))
    print -r -- "$(date -u +%Y-%m-%dT%H:%M:%SZ) config-mirror sweep ${2:t} verdict=$v rc=$rc ms=${ms%%.*}"
  ' zsh "$lib" "$cfg" "$claim" >/dev/null 2>&1 || rmdir "$claim" 2>/dev/null || true
}
sweep_start || true
exit 0
