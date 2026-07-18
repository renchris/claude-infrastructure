#!/bin/bash
# lr-reset-poller.sh — close the "limit-hit session stays idle forever" gap.
#
# Nothing in the stack watches a usage-limit reset and re-fires the parked session
# (verified 2026-07-11: resume-sessions keepalive only nudges RUNNING panes; lr-audit
# parses the reset time but schedules nothing; no launchd job is limit-aware). This poller
# does: it detects limit-parked sessions across all accounts, ledgers their reset times,
# and at reset (with account headroom) resumes them — prompt-free, thanks to
# lr-preseed-env.sh (see memory reference-limit-recover-autonomous-resume-preseed).
#
# SAFETY — auto-spawn is OFF by default. Unset/0 LR_POLLER_AUTOFIRE ⇒ detect + NOTIFY +
# log only (no session is spawned). Set LR_POLLER_AUTOFIRE=1 ONLY after eyeballing a live
# cycle's log. Kill switch: LR_POLLER_DISABLED=1. Idempotent, fail-open, never crashes the
# daemon. Monthly-spend caps have no reset ⇒ ignored (need /usage-credits).
#
# Usage: lr-reset-poller.sh [--dry-run] [--once]   (launchd runs it bare every ~10 min)
set -uo pipefail

[[ -n "${LR_POLLER_DISABLED:-}" ]] && exit 0

LR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUDIT="$LR/lr-audit.py"
STATE="$HOME/.reso/limit-recover"
PARKED="$STATE/parked"; RESUMED="$STATE/resumed"; LOG="$STATE/poller.log"
mkdir -p "$PARKED" "$RESUMED"
DRY=0; [[ "${1:-}" == "--dry-run" ]] && DRY=1
AUTOFIRE="${LR_POLLER_AUTOFIRE:-0}"
RECENCY_MIN=$(( 48 * 60 ))          # only sessions touched in the last 48h
MAX_PER_RUN=4                       # runaway guard

log() { printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >> "$LOG"; }
acct_of_cfg() { case "$1" in
  *.claude-next) echo next ;; *.claude-secondary) echo next2 ;;
  *.claude-tertiary) echo next3 ;; *.claude-quaternary) echo next4 ;; *) echo "" ;;
esac; }

# account headroom: session_pct AND weekly_pct < 100 (never resume into a still-capped acct).
# ⚠️ Blind-check fix (2026-07-15, caught by LR-c): the original captured the JSON into $j but ran
# `python3 - <<PY`, whose sys.stdin.read() is EMPTY (stdin was already consumed as the program text)
# → the except branch exited 0 on EVERY call — the guard never once observed a quota (§3i: a check
# that cannot observe what it guards is indistinguishable from no check). The JSON is now PIPED in.
account_has_headroom() {
  local acct="$1" j
  j=$("$HOME/bin/claude-accounts" --json 2>/dev/null) || return 0   # unreadable ⇒ don't block
  printf '%s' "$j" | python3 -c '
import json,sys
acct=sys.argv[1]
try: rows=json.loads(sys.stdin.read()).get("rows",[])
except Exception: sys.exit(0)
for r in rows:
    if r.get("acct")==acct:
        sys.exit(0 if (r.get("session_pct",0)<100 and r.get("weekly_pct",0)<100) else 1)
sys.exit(0)' "$acct" 2>/dev/null
}

fired=0
# ── 1. DETECT + LEDGER parked sessions ────────────────────────────────────────────────
for cfg in "$HOME"/.claude-next "$HOME"/.claude-secondary "$HOME"/.claude-tertiary "$HOME"/.claude-quaternary; do
  [[ -d "$cfg/projects" ]] || continue
  acct=$(acct_of_cfg "$cfg"); [[ -n "$acct" ]] || continue
  while IFS= read -r tx; do
    [[ -n "$tx" ]] || continue
    sid=$(basename "$tx" .jsonl)
    # cheap pre-filter: a genuine limit line near the tail (isApiErrorMessage confirmed by lr-audit)
    tail -c 20000 "$tx" 2>/dev/null | grep -qE "You've hit your (session|weekly) limit" || continue
    # teammate sessions (implicit-team assignees carry "agentName" on their early
    # records; leads never do) are recovered by their LEAD via the team-aware
    # lr-audit — a bare --resume here would detach them from team semantics
    # (inbox/agentName wiring) and duplicate the lead's respawn.
    if head -c 8000 "$tx" 2>/dev/null | grep -q '"agentName"'; then
      if [[ ! -f "$STATE/teammate-skip/$sid" ]]; then
        mkdir -p "$STATE/teammate-skip"; : > "$STATE/teammate-skip/$sid"
        log "SKIP  $sid — teammate session (lead-owned recovery)"
      fi
      continue
    fi
    pgrep -f "resume $sid" >/dev/null 2>&1 && continue        # already running
    # cwd from the transcript itself (avoids lossy slug-decoding)
    cwd=$(python3 -c "
import json,sys
for ln in open(sys.argv[1],encoding='utf-8'):
    try: o=json.loads(ln)
    except: continue
    c=o.get('cwd')
    if c: print(c); break
" "$tx" 2>/dev/null)
    [[ -n "$cwd" && -d "$cwd" ]] || continue
    # authoritative classification via lr-audit (isApiErrorMessage + reset parse)
    aj=$(mktemp); python3 "$AUDIT" --config-dir "$cfg" --session "$sid" --cwd "$cwd" \
        --json "$aj" --quiet >/dev/null 2>&1 || true
    read -r kind reset < <(python3 -c "
import json,sys
try: es=json.load(open(sys.argv[1])).get('limit_events',[])
except Exception: es=[]
es=[e for e in es if e.get('kind') in ('session','weekly','fable') and e.get('resets_at_utc')]
if es: e=es[-1]; print(e['kind'], e['resets_at_utc'])
" "$aj" 2>/dev/null); rm -f "$aj"
    [[ -n "${reset:-}" ]] || continue                        # no genuine reset-bearing limit
    # RECURRENCE (LR-i, 2026-07-15): the resumed/ marker is EVENT-keyed, never sid-keyed-forever.
    # The original `[[ -f $RESUMED/$sid.json ]] && continue` (pre-parse, sid-keyed) meant a session
    # resumed ONCE could never re-park on its NEXT limit — fatal for multi-day runs, which hit a
    # 5h limit every window. Skip only when THIS event's reset is not newer than the handled one
    # (ISO-8601 UTC compares lexicographically); a newer event clears the marker and re-parks.
    if [[ -f "$RESUMED/$sid.json" ]]; then
      prev=$(jq -r '.reset_at_utc // ""' "$RESUMED/$sid.json" 2>/dev/null || echo "")
      if [[ -n "$prev" && ! "$reset" > "$prev" ]]; then continue; fi
      rm -f "$RESUMED/$sid.json"
      log "REPARK $sid — new limit event (resets $reset > handled ${prev:-unknown})"
    fi
    if [[ ! -f "$PARKED/$sid.json" ]]; then
      printf '{"sid":"%s","acct":"%s","cfg":"%s","cwd":"%s","kind":"%s","reset_at_utc":"%s","parked_at":"%s"}\n' \
        "$sid" "$acct" "$cfg" "$cwd" "$kind" "$reset" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$PARKED/$sid.json"
      log "PARKED $sid ($acct, $kind) resets $reset  cwd=$cwd"
    fi
  done < <(find "$cfg/projects" -maxdepth 2 -name '*.jsonl' -mmin "-$RECENCY_MIN" 2>/dev/null)
done

# ── 2. RESUME (or notify) parked sessions whose reset has passed ───────────────────────
now=$(date -u +%s)
for pf in "$PARKED"/*.json; do
  [[ -e "$pf" ]] || continue
  eval "$(python3 -c "
import json,sys
d=json.load(open(sys.argv[1]))
for k in ('sid','acct','cfg','cwd','reset_at_utc'):
    print('%s=%s'%(k,json.dumps(str(d.get(k,'')))))
" "$pf")"
  reset_epoch=$(python3 -c "import sys,calendar,time; from datetime import datetime; print(int(calendar.timegm(datetime.fromisoformat(sys.argv[1].replace('Z','+00:00')).utctimetuple())))" "$reset_at_utc" 2>/dev/null || echo 0)
  (( now < reset_epoch )) && continue                        # reset not reached yet
  pgrep -f "resume $sid" >/dev/null 2>&1 && { mv "$pf" "$RESUMED/$(basename "$pf")" 2>/dev/null; rm -f "$PARKED/$sid.notified"; continue; }
  if ! account_has_headroom "$acct"; then log "WAIT  $sid — $acct still capped, retry next tick"; continue; fi
  (( fired >= MAX_PER_RUN )) && { log "CAP   per-run resume cap ($MAX_PER_RUN) reached; deferring rest"; break; }
  if [[ "$AUTOFIRE" == "1" && $DRY -eq 0 ]]; then
    launcher="/tmp/lr-poller-launch-${sid:0:8}.sh"
    { echo '#!/bin/bash'; printf 'exec "%s/lr-fire-resume.sh" "%s" "%s" "%s" --prompt %q\n' \
        "$LR" "$acct" "$cwd" "$sid" "/limit-recover"; } > "$launcher"; chmod +x "$launcher"
    osascript -e "tell application \"iTerm2\" to create window with default profile command \"/bin/bash $launcher\"" >/dev/null 2>&1 \
      && { log "RESUMED $sid on $acct (autofire) — pane opened"; mv "$pf" "$RESUMED/$(basename "$pf")"; rm -f "$PARKED/$sid.notified"; fired=$((fired+1)); } \
      || log "ERROR  $sid — osascript window open failed"
  elif [[ ! -f "$PARKED/$sid.notified" ]]; then    # notify ONCE per parked session (no per-tick spam)
    mode=$([[ "$AUTOFIRE" == "1" ]] && echo "dry-run" || echo "notify-only")
    # headless-safe user alert (a LaunchAgent runs in the Aqua session ⇒ notifications work)
    osascript -e "display notification \"${sid:0:8} ($acct) limit reset — resumable. Set LR_POLLER_AUTOFIRE=1 to auto-resume.\" with title \"lr-reset-poller\"" >/dev/null 2>&1 || true
    : > "$PARKED/$sid.notified"
    log "READY $sid on $acct — $mode, notified once (LR_POLLER_AUTOFIRE=1 to auto-resume)"
  fi
done
exit 0
