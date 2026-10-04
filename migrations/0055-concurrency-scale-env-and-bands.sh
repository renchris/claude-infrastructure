#!/bin/bash
# migration-class: c10
# migration-step: apply the operator-only half of the 2026-10-04 concurrency fixes (docs/research/concurrency-scale-2026-10-04/README.md §3 rows 1, 2, 5, 17). In the ONE shared ~/.claude/settings.json (every account): set env CLAUDE_CODE_CERT_STORE=bundled, which removes the system-CA keychain query that froze four launches for 15-46 min, and env AGENT_BROWSER_IDLE_TIMEOUT_MS=1800000, so an idle agent-browser tree exits after 30 min; give the SessionStart hook net-context-stamp.sh a 5 s timeout. Then reload four launchd jobs into the bands their repo plists now declare: capacity-alarm and qos-census to Standard, deploy-live and worktree-gc-infra out of Background into taskpolicy utility. CERT_STORE=bundled drops trust in CAs that exist only in the system keychain (the mkcert root, "VoiceInk Dev"); add NODE_EXTRA_CA_CERTS if Claude Code's own TLS must reach an mkcert-signed host. It writes settings.json and reloads launchd jobs, which is C10.
# migration-run: bash ~/Development/claude-infrastructure/migrations/0055-concurrency-scale-env-and-bands.sh --confirm settings.json+launchd
# migration-batch-hold: manual — it boots out and bootstraps four LIVE launchd jobs, which the batch's scratch-HOME rehearsal cannot sandbox (launchctl is machine-wide); run its migration-run line by hand
# migration-verify: bash "${CC_MIGRATION_REPO:-$HOME/Development/claude-infrastructure}/migrations/0055-concurrency-scale-env-and-bands.sh" --verify
#
# The verifier is config-dir-INVARIANT (as 0036-0054): one shared settings file and four machine-wide
# launchd jobs give one answer from every config dir.
#
# ══ 0055 — the operator-only half of the concurrency-scale fix list ═════════════════════════════════
# (a) env, rows 1 and 2.
#   CLAUDE_CODE_CERT_STORE=bundled. Claude Code 2.1.284 defaults its CA stores to bundled,system, and
#   loading "system" is one synchronous keychain query (SecItemCopyMatching to secd) on the main
#   thread with no timeout. On 10-04 secd backed up and four launches sat 896-2,743 s before
#   registering (j-startup-hang.md). It belongs in the settings `env` block, not a shell export: bg
#   and daemon sessions inherit the environment of whatever started their supervisor. A typo falls
#   back silently to bundled,system, so the value is written and read back exactly. NOT verified by a
#   live launch here; verify with one launch under CLAUDE_CODE_DEBUG_LOGS and grep
#   "CA certs: stores=bundled". The token read can still stall for a bounded time.
#   AGENT_BROWSER_IDLE_TIMEOUT_MS=1800000. Seven agent-browser trees held 9.55 GB of RSS, most near
#   idle; the vendor's idle timeout was documented and never configured. Applies to daemons started
#   after the change; a logged-in or challenge-solved browser is lost after 30 idle minutes.
# (b) launchd bands, row 5. The repo plists changed in the commit that added this file; install.sh
#   copies them into ~/Library/LaunchAgents at converge, but a LOADED job keeps the band it was
#   loaded with until it is booted out and bootstrapped again, which is this step.
#     com.claude.capacity-alarm, com.claude.qos-census  → ProcessType Standard
#     com.claude.deploy-live, com.claude.worktree-gc-infra → no ProcessType, exec via taskpolicy -c utility
#   A job whose tick is running is never booted out mid-run (bootout kills the tick, and a
#   deploy-live tick may be mid-advance). It is waited for briefly; one still running at that bound
#   is handed to a DETACHED GAP WAITER (this file, --reload-when-idle) that polls until the tick
#   exits and reloads the job in the gap before the next StartInterval firing, then logs its
#   verdict. WHY A WAITER AND NOT A LONGER WAIT (2026-10-04, two operator runs both ended "still
#   running after 120s — NOT reloaded"): com.claude.deploy-live is effectively always running. Its
#   launchd tick runs at PRI 4 in the very Background band this step removes, so one tick takes
#   25 min to 1 h 50 min, and the gap between ticks is only the 0-600 s until the next interval
#   firing. No foreground bound an operator would sit through reliably lands in that gap; a
#   5 s poll that outlives the run lands in the first one. deploy-live has no run lock to wait on
#   (scripts/deploy-live.sh, "THIS SCRIPT HAS NO RUN LOCK"), and the detached converge kicks from
#   ship-land are separate processes outside the job, so bootout never reaches them; the
#   launchd tick's own state is the only thing the reload must wait for.
#   NOT INCLUDED, on purpose: row 5's "pollers to Background". com.reso.lr-reconciler is watched by
#   com.reso.lr-reconciler-watchdog, which kills a reconciler whose loop makes no progress for 180 s;
#   the Background band is the one this research measured starving jobs for minutes at this load, so
#   demoting the reconciler would turn starvation into watchdog kills and pages. gl.reso.load-sampler
#   is the reso repo's job and has no SSOT here.
# (c) net-context-stamp timeout, row 17 / j-startup-hang.md F6: the one SessionStart hook registered
#   with no timeout. It measured 0.05-0.20 s; the timeout only bounds a hang.
#
# SAFETY. settings.json is edited once through its real path (README rule 7), backed up, verified by
# content (only the two env keys and the one hook timeout may differ), and read back. An env key the
# operator already set to a different value is left alone and the step refuses. Idempotent: a second
# run changes nothing. Rollback: the printed `cp -p` line for settings; for a job, re-load its
# previous plist from the printed backup dir.
#
# Usage: bash migrations/0055-concurrency-scale-env-and-bands.sh            (same as --dry-run)
#        bash migrations/0055-concurrency-scale-env-and-bands.sh --dry-run | --verify
#        bash migrations/0055-concurrency-scale-env-and-bands.sh --confirm settings.json+launchd
#        (internal) --reload-when-idle <label> <standard|utility> <backup-dir>   the gap waiter
# Exit: 0 applied / already applied / dry run ok / verify live, or every busy job has a live gap
#       waiter (SCHEDULED: --verify reads NOT live until its reload lands; the waiter's verdict is
#       in $STATE_DIR/0055-reband.log) · 1 failure, not live, or a waiter could not be started
#       (re-run) · 2 usage · 3 REFUSED, an account settings.json is forked
# Seams (tests): CC_SETTINGS_PARITY_BIN · CC_0055_LAUNCHCTL · CC_MIGRATION_LA_DIR · CC_MIGRATION_REPO
#                CC_0055_WAIT_S (default 20) · CC_0055_POLL_S (default 5) · CC_0055_IDLE_WAIT_S
#                (the waiter's bound, default 14400) · CC_0055_STATE_DIR (default
#                ~/.claude/autonomy/migrations) · CC_0055_DETACH=inline (run the waiter in the
#                foreground, for tests)
# bash 3.2-safe.
# shellcheck disable=SC2016,SC2329  # SC2016: single-quoted strings are jq programs ($c/$t are jq variables); SC2329: the per-job functions are called by name through each_job
set -uo pipefail

N=0055
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${CC_MIGRATION_REPO:-$(cd "$here/.." && pwd)}"
f="$HOME/.claude/settings.json"
parity="${CC_SETTINGS_PARITY_BIN:-$HOME/.claude/bin/cc-settings-parity}"
LC="${CC_0055_LAUNCHCTL:-launchctl}"
LA="${CC_MIGRATION_LA_DIR:-$HOME/Library/LaunchAgents}"
DOMAIN="gui/$(id -u)"
WAIT_S="${CC_0055_WAIT_S:-20}"
POLL_S="${CC_0055_POLL_S:-5}"
IDLE_WAIT_S="${CC_0055_IDLE_WAIT_S:-14400}"
STATE_DIR="${CC_0055_STATE_DIR:-$HOME/.claude/autonomy/migrations}"
REBAND_LOG="$STATE_DIR/0055-reband.log"
CERT=bundled
IDLE=1800000
HOOK_TIMEOUT=5
STANDARD="com.claude.capacity-alarm com.claude.qos-census"
UTILITY="com.claude.deploy-live com.claude.worktree-gc-infra"

say() { printf '%s: %s\n' "$N" "$*"; }
err() { printf '%s: %s\n' "$N" "$*" >&2; }
command -v jq >/dev/null 2>&1 || { err "jq required — nothing written"; exit 1; }

mode=""
case "${1:-}" in
  ''|--dry-run) mode=dry ;;
  --verify) mode=verify ;;
  --confirm) [ "${2:-}" = "settings.json+launchd" ] || { err "--confirm must name its target: --confirm settings.json+launchd"; exit 2; }
             mode=apply ;;
  --reload-when-idle)
             case "${3:-}" in standard|utility) ;; *) err "--reload-when-idle <label> <standard|utility> <backup-dir>"; exit 2 ;; esac
             case " $STANDARD $UTILITY " in *" ${2:-} "*) ;; *) err "--reload-when-idle: ${2:-} is not one of this step's jobs"; exit 2 ;; esac
             [ -n "${4:-}" ] || { err "--reload-when-idle: backup dir required"; exit 2; }
             mode=waiter ;;
  *) err "unknown argument $1 (use --dry-run, --verify or --confirm settings.json+launchd)"; exit 2 ;;
esac

# ── settings.json ────────────────────────────────────────────────────────────────────────────────
[ -f "$f" ] || { err "$f not found — nothing written"; exit 1; }
real="$f"
if [ -L "$f" ]; then t="$(readlink "$f")"; case "$t" in /*) real="$t" ;; *) real="$(dirname "$f")/$t" ;; esac; fi
jq -e . "$real" >/dev/null 2>&1 || { err "$real is not valid JSON — nothing written"; exit 1; }

# Every hook entry naming net-context-stamp.sh carries a numeric timeout (none registered ⇒ true).
STAMP_OK='[.hooks // {} | .[]? | .[]? | .hooks[]? | select((.command // "") | test("net-context-stamp\\.sh"))
           | (.timeout | type) == "number"] | all'
settings_live() { # $1=file → rc 0 iff both env keys hold the exact values and the stamp hook is bounded
  jq -e --arg c "$CERT" --arg t "$IDLE" \
    '(.env.CLAUDE_CODE_CERT_STORE == $c) and (.env.AGENT_BROWSER_IDLE_TIMEOUT_MS == $t) and ('"$STAMP_OK"')' \
    "$1" >/dev/null 2>&1
}
# The same document with every key this migration may touch removed: equal before and after ⇒ no
# other byte of meaning moved.
REST='del(.env.CLAUDE_CODE_CERT_STORE, .env.AGENT_BROWSER_IDLE_TIMEOUT_MS)
      | if (.hooks | type) == "object" then .hooks |= with_entries(.value |= (if type == "array" then map(
          if (.hooks | type) == "array" then .hooks |= map(
            if ((.command // "") | test("net-context-stamp\\.sh")) then del(.timeout) else . end) else . end) else . end))
        else . end'

# ── launchd ──────────────────────────────────────────────────────────────────────────────────────
job_print()   { "$LC" print "$DOMAIN/$1" 2>/dev/null; }
job_loaded()  { job_print "$1" >/dev/null; }
job_running() { job_print "$1" | grep -E '^[[:space:]]*state = running' >/dev/null; }
# The LOADED job is in its new band: never the background or adaptive spawn type, and for the two
# utility jobs the loaded argv itself carries the taskpolicy exec.
job_in_band() { # $1=label $2=standard|utility
  local out; out="$(job_print "$1")" || return 1
  printf '%s\n' "$out" | grep -E 'spawn type = (background|adaptive)' >/dev/null && return 1
  [ "$2" = standard ] && return 0
  printf '%s\n' "$out" | grep -F 'taskpolicy -c utility' >/dev/null
}
ssot_ok() { # $1=label $2=kind → rc 0 iff the repo plist carries the re-band
  local s="$REPO/launchd/$1.plist"
  [ -f "$s" ] || return 1
  if [ "$2" = standard ]; then
    grep -E '<key>ProcessType</key>[[:space:]]*<string>Standard</string>' "$s" >/dev/null
  else
    grep -F 'taskpolicy -c utility' "$s" >/dev/null && ! grep -F '<string>Background</string>' "$s" >/dev/null
  fi
}
each_job() { # $1=function taking (label kind)
  local l
  for l in $STANDARD; do "$1" "$l" standard; done
  for l in $UTILITY;  do "$1" "$l" utility;  done
}
# The gap waiter for a label: its pid file, and whether that pid is still OUR waiter (a recycled pid
# running anything else reads as no waiter).
waiter_pidfile() { printf '%s/0055-reband-%s.pid' "$STATE_DIR" "$1"; }
waiter_alive() { # $1=label → prints the pid and rc 0 iff a waiter for it is running
  local p; p="$(cat "$(waiter_pidfile "$1")" 2>/dev/null)" || return 1
  case "$p" in ''|*[!0-9]*) return 1 ;; esac
  ps -o command= -p "$p" 2>/dev/null | grep -F -e "--reload-when-idle $1 " >/dev/null || return 1
  printf '%s' "$p"
}
# Reload one job that is NOT running: install the repo plist, bootout, bootstrap, read back. $3 is
# the backup dir. Sets failed=1 on any failure. Re-checks running immediately before the bootout,
# so the window in which a fresh StartInterval tick could be caught is the few ms after that read.
do_reload() { # $1=label $2=kind $3=bdir
  local l="$1" src="$REPO/launchd/$1.plist" dst="$LA/$1.plist" i=0
  if [ -f "$dst" ] && ! cmp -s "$src" "$dst"; then cp -p "$dst" "$3/$l.plist" 2>/dev/null || true; fi
  if ! cmp -s "$src" "$dst" 2>/dev/null; then
    mkdir -p "$LA" && cp "$src" "$dst.tmp.$$" && mv -f "$dst.tmp.$$" "$dst" || { err "$l: install of $dst FAILED"; failed=1; return 0; }
  fi
  job_running "$l" && { err "$l: a tick started before the bootout — NOT reloaded"; failed=1; return 0; }
  "$LC" bootout "$DOMAIN/$l" 2>/dev/null || { err "$l: bootout FAILED — left as it was"; failed=1; return 0; }
  # bootout is asynchronous: wait (bounded) until launchd no longer holds the label.
  while job_loaded "$l" && [ "$i" -lt 20 ]; do sleep 1; i=$((i + 1)); done
  "$LC" bootstrap "$DOMAIN" "$dst" || { err "$l: bootstrap FAILED — re-load it: launchctl bootstrap $DOMAIN $dst"; failed=1; return 0; }
  if job_in_band "$l" "$2"; then say "$l: reloaded and read back in the $2 band"
  else err "$l: reloaded but does NOT read back in the $2 band"; failed=1; fi
}

if [ "$mode" = waiter ]; then
  # Detached by the apply step; every line goes to $REBAND_LOG. Polls the label's own launchd state
  # until its tick exits, then reloads in the gap. Never boots out a running tick, at any bound.
  l="$2"; kind="$3"; bdir="$4"; failed=0; waited=0
  say "$(date '+%F %T') $l: gap waiter pid $$ started (bound ${IDLE_WAIT_S}s, poll ${POLL_S}s)"
  while :; do
    if ! job_loaded "$l"; then say "$(date '+%F %T') $l: no longer loaded — nothing to reload"; exit 0; fi
    if job_in_band "$l" "$kind"; then say "$(date '+%F %T') $l: already in its $kind band"; exit 0; fi
    job_running "$l" || break
    if [ "$waited" -ge "$IDLE_WAIT_S" ]; then
      err "$(date '+%F %T') $l: verdict=GAVE-UP — still running at every poll for ${IDLE_WAIT_S}s; NOT reloaded. Re-run the step."
      exit 1
    fi
    sleep "$POLL_S"; waited=$((waited + POLL_S))
  done
  do_reload "$l" "$kind" "$bdir"
  if [ "$failed" = 0 ]; then say "$(date '+%F %T') $l: verdict=RELOADED after ${waited}s waiting for the gap"; exit 0; fi
  err "$(date '+%F %T') $l: verdict=FAILED — see above; backups in $bdir"; exit 1
fi

if [ "$mode" = verify ]; then
  bad=0
  "$parity" check >/dev/null 2>&1 || { err "NOT live — accounts do not all share $f ($parity check failed)"; bad=1; }
  settings_live "$f" || { err "NOT live — $f lacks env CLAUDE_CODE_CERT_STORE=$CERT, env AGENT_BROWSER_IDLE_TIMEOUT_MS=$IDLE, or a timeout on net-context-stamp.sh"; bad=1; }
  verify_job() {
    job_loaded "$1" || return 0          # not loaded ⇒ nothing runs in a wrong band; the file applies at its next load
    local w
    job_in_band "$1" "$2" && return 0
    if w="$(waiter_alive "$1")"; then err "NOT live — $1 is loaded in its old band; its gap waiter (pid $w) reloads it when the running tick exits, verdict in $REBAND_LOG"
    else err "NOT live — $1 is loaded in its old band"; fi
    bad=1
  }
  each_job verify_job
  [ "$bad" = 0 ] || exit 1
  say "live — settings carry both env keys and the hook timeout; every loaded job is in its new band"
  exit 0
fi

# ── preflight (dry run and apply share it) ───────────────────────────────────────────────────────
for k in CLAUDE_CODE_CERT_STORE:$CERT AGENT_BROWSER_IDLE_TIMEOUT_MS:$IDLE; do
  cur="$(jq -r --arg k "${k%%:*}" '.env[$k] // "unset"' "$real")"
  case "$cur" in
    unset|"${k#*:}") ;;
    *) err "$real already sets env ${k%%:*} to '$cur' — an operator value, left unchanged; nothing written"; exit 1 ;;
  esac
done
jq -e '(.env // {}) | type == "object"' "$real" >/dev/null 2>&1 || { err "env is not an object — left unchanged"; exit 1; }
"$parity" check >/dev/null 2>&1 || {
  err "REFUSED — accounts do not all share $f ($parity check failed), so the change would reach some accounts and not others. Converge with 0037 first."
  exit 3
}
pre_job() { ssot_ok "$1" "$2" || { err "MISSING — $REPO/launchd/$1.plist does not carry the $2 re-band; the wiring commit did not land intact"; exit 1; }; }
each_job pre_job

need_settings=1; settings_live "$real" && need_settings=0
if [ "$need_settings" = 1 ]; then
  say "will set in $real: env.CLAUDE_CODE_CERT_STORE=\"$CERT\", env.AGENT_BROWSER_IDLE_TIMEOUT_MS=\"$IDLE\", timeout $HOOK_TIMEOUT on net-context-stamp.sh"
else
  say "settings already applied — $real carries both env keys and the hook timeout"
fi
plan_job() {
  if ! job_loaded "$1"; then say "$1: not loaded — nothing to reload (its plist applies at the next load)"
  elif job_in_band "$1" "$2"; then say "$1: already in its new band"
  else say "$1: will reload into the $2 band (bootout + bootstrap of $LA/$1.plist; if its tick is running, a detached waiter does it in the gap after the tick)"; fi
}
each_job plan_job
[ "$mode" = dry ] && { say "DRY RUN — nothing written, nothing reloaded. Apply: --confirm settings.json+launchd"; exit 0; }

# ── apply: settings ──────────────────────────────────────────────────────────────────────────────
bdir="$HOME/.claude/backups/concurrency-scale-$N-$(date +%Y%m%d%H%M%S)"
mkdir -p "$bdir" || { err "backup dir FAILED — nothing written"; exit 1; }
if [ "$need_settings" = 1 ]; then
  cp -p "$real" "$bdir/settings.json" || { err "backup FAILED — nothing written"; exit 1; }
  tmp="$(dirname "$real")/.settings.json.tmp-$N-$$"
  EDIT='.env = ((.env // {}) + {CLAUDE_CODE_CERT_STORE: $c, AGENT_BROWSER_IDLE_TIMEOUT_MS: $t})
        | if (.hooks | type) == "object" then .hooks |= with_entries(.value |= (if type == "array" then map(
            if (.hooks | type) == "array" then .hooks |= map(
              if ((.command // "") | test("net-context-stamp\\.sh")) and ((.timeout | type) != "number")
              then . + {timeout: $h} else . end) else . end) else . end))
          else . end'
  if ! jq --arg c "$CERT" --arg t "$IDLE" --argjson h "$HOOK_TIMEOUT" "$EDIT" "$real" > "$tmp" 2>/dev/null || ! jq -e . "$tmp" >/dev/null 2>&1; then
    rm -f "$tmp"; err "jq edit FAILED — nothing written"; exit 1
  fi
  same_rest="$(jq -n --slurpfile a "$real" --slurpfile b "$tmp" '($a[0] | '"$REST"') == ($b[0] | '"$REST"')' 2>/dev/null)"
  if [ "$same_rest" != true ] || ! settings_live "$tmp"; then
    rm -f "$tmp"; err "edit did not verify by content — nothing written"; exit 1
  fi
  mv "$tmp" "$real" || { rm -f "$tmp"; err "write FAILED — nothing written"; exit 1; }
  say "settings written. Backup: $bdir/settings.json (restore: cp -p $bdir/settings.json $real)"
  "$parity" check >/dev/null 2>&1 || err "WARNING — cc-settings-parity check now fails; restore with the line above"
  settings_live "$f" || { err "did NOT verify through $f"; exit 1; }
  say "verified — $f carries both env keys and the hook timeout. Takes effect in NEW sessions."
  say "check the launch fix once: start one session with CLAUDE_CODE_DEBUG_LOGS set and grep its debug log for 'CA certs: stores=bundled'"
fi

# ── apply: launchd ───────────────────────────────────────────────────────────────────────────────
scheduled=0; failed=0
reload_job() { # $1=label $2=kind
  local l="$1" waited=0 w
  job_loaded "$l" || { say "$l: not loaded — left alone"; return 0; }
  job_in_band "$l" "$2" && { say "$l: already in its new band"; return 0; }
  # Never boot out a tick in flight: bootout kills it, and a deploy-live tick may be mid-converge.
  while job_running "$l"; do
    if [ "$waited" -ge "$WAIT_S" ]; then
      if w="$(waiter_alive "$l")"; then
        say "$l: still running; its gap waiter from an earlier run (pid $w) is still waiting — left to it"
        scheduled=1; return 0
      fi
      mkdir -p "$STATE_DIR" || { err "$l: cannot create $STATE_DIR — NOT reloaded; re-run"; failed=1; return 0; }
      if [ "${CC_0055_DETACH:-}" = inline ]; then
        bash "$here/$(basename "${BASH_SOURCE[0]}")" --reload-when-idle "$l" "$2" "$bdir" >> "$REBAND_LOG" 2>&1 \
          || { err "$l: gap waiter FAILED — see $REBAND_LOG"; failed=1; return 0; }
        say "$l: reloaded by the gap waiter (inline) — see $REBAND_LOG"; return 0
      fi
      # shellcheck disable=SC1091  # the detacher is resolved beside this file at run time
      . "$here/../scripts/lib/detach.sh" 2>/dev/null && command -v detach >/dev/null 2>&1 \
        && w="$(detach "$REBAND_LOG" /bin/bash "$here/$(basename "${BASH_SOURCE[0]}")" --reload-when-idle "$l" "$2" "$bdir")" \
        && [ -n "$w" ] && printf '%s\n' "$w" > "$(waiter_pidfile "$l")" \
        || { err "$l: still running after ${WAIT_S}s and the gap waiter could NOT be started — NOT reloaded; re-run"; failed=1; return 0; }
      say "$l: tick still running after ${WAIT_S}s — SCHEDULED: gap waiter pid $w reloads it when the tick exits (bound ${IDLE_WAIT_S}s); verdict in $REBAND_LOG"
      scheduled=1; return 0
    fi
    sleep "$POLL_S"; waited=$((waited + POLL_S))
  done
  do_reload "$l" "$2" "$bdir"
}
each_job reload_job
[ "$failed" = 0 ] || { err "one or more jobs failed to reload — see above; backups in $bdir"; exit 1; }
if [ "$scheduled" = 1 ]; then
  say "done except the SCHEDULED reload(s) above — nothing more to run. --verify reads NOT live until each waiter's reload lands; its verdict line (verdict=RELOADED) is in $REBAND_LOG."
  exit 0
fi
say "done — settings and all four launchd bands verified by read-back."
exit 0
