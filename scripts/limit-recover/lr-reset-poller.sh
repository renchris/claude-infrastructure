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
# daemon.
#
# SPAWN MECHANISM (P0-8, 2026-07-19): LR_POLLER_SPAWN=auto|gui|tmux (default auto). The GUI
# path (osascript → iTerm2 window) needs an Aqua session; a LaunchDaemon / SSH / pre-login
# (P0-10) context has none. `tmux` resumes into a DETACHED tmux PTY instead — fully headless
# (attach later with `tmux attach -t lr-resume-<sid8>`); `auto` tries GUI then falls back to
# tmux so a resume is never silently failed. (tmux over `claude -p`: -p is a one-shot print
# turn that exits — it cannot sustain the parked session's ongoing /goal-driven work.)
#
# MONTHLY-SPEND (P0-8 / I-LIVE-1, 2026-07-19): a billing-plane cap ("You've hit your monthly
# spend limit") has NO reset time, so it cannot be scheduled for auto-resume — but it is NEVER
# silently ignored (the pre-2026-07-19 session|weekly pre-filter dropped it entirely). The
# poller opens a class-B cc-decide packet (default = cross-account continuation, operator
# decision #3) so the strand is surfaced for an async early-veto decision, never left dead.
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
MAX_PER_RUN=4                       # runaway guard (per TICK — see consolidation below)
# ── session-sprawl consolidation (incident 2026-07-21) ────────────────────────────────
# MAX_PER_RUN alone bounds a TICK, not a recovery: 14 parked sessions in one worktree still
# all came up, just spread over ~35 min instead of 2 s. lr-select is the shared decision point
# (boot-resume.sh and the resume-sessions skill consult the same one) — it groups parked
# candidates by worktree and returns the ONE per group that holds the most real state.
SELECT="${LR_SELECT_BIN:-$LR/lr-select.py}"
MAX_PER_WT="${LR_POLLER_MAX_PER_WORKTREE:-1}"

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

# cwd_of <transcript> — the first cwd field (avoids lossy slug-decoding). Empty if none.
cwd_of() {
  python3 -c "
import json,sys
for ln in open(sys.argv[1],encoding='utf-8'):
    try: o=json.loads(ln)
    except: continue
    c=o.get('cwd')
    if c: print(c); break
" "$1" 2>/dev/null
}

# ── headless-capable resume spawn (P0-8) ───────────────────────────────────────────────
SPAWN_MECH="${LR_POLLER_SPAWN:-auto}"
# spawn_gui <launcher> — open an iTerm2 window (needs an Aqua session). 0 = opened.
spawn_gui() {
  command -v osascript >/dev/null 2>&1 || return 1
  osascript -e "tell application \"iTerm2\" to create window with default profile command \"/bin/bash $1\"" >/dev/null 2>&1
}
# spawn_tmux <launcher> <sid> — run the launcher in a DETACHED tmux session (headless PTY). 0 = created.
spawn_tmux() {
  command -v tmux >/dev/null 2>&1 || return 1
  tmux new-session -d -s "lr-resume-${2:0:8}" "/bin/bash $1" >/dev/null 2>&1
}
# spawn_resume <launcher> <sid> — echo the mechanism used (gui|tmux) on success; non-zero on failure.
spawn_resume() {
  local launcher="$1" sid="$2"
  case "$SPAWN_MECH" in
    gui)  spawn_gui  "$launcher"        && { echo gui;  return 0; }; return 1 ;;
    tmux) spawn_tmux "$launcher" "$sid" && { echo tmux; return 0; }; return 1 ;;
    *)    spawn_gui  "$launcher"        && { echo gui;  return 0; }   # auto: GUI first…
          spawn_tmux "$launcher" "$sid" && { echo tmux; return 0; }   # …then headless tmux
          return 1 ;;
  esac
}

# ── monthly-spend → class-B decision packet (P0-8 / I-LIVE-1) ───────────────────────────
SPEND_RE="(hit|reached) your monthly spend limit"     # billing-plane cap; distinct from session|weekly
SPEND_VETO_HOURS="${LR_SPEND_VETO_HOURS:-1}"          # the class-B default fires this long after opening
CC_DECIDE_BIN="$(command -v cc-decide 2>/dev/null || true)"
if [[ -z "$CC_DECIDE_BIN" ]]; then
  for c in "$HOME/.claude/bin/cc-decide" "$LR/../../bin/cc-decide"; do
    [[ -x "$c" ]] && { CC_DECIDE_BIN="$c"; break; }
  done
fi
# open_spend_packet <sid> <acct> [cwd] — surface a no-reset billing kill as a class-B decision
# packet (never silent-park). Idempotent: a marker prevents re-opening every tick.
open_spend_packet() {
  local sid="$1" acct="$2" cwd="${3:-}"
  local marker="$STATE/spend-packet/$sid"
  mkdir -p "$STATE/spend-packet"
  [[ -f "$marker" ]] && return 0                       # already surfaced — no per-tick spam
  local what deadline id
  what="Session ${sid:0:8} ($acct) hit the monthly spend limit — a billing-plane cap with NO reset time, so it cannot be auto-resumed on the same account. Choose how to continue its work${cwd:+ (cwd: $cwd)}."
  deadline="$(python3 -c "from datetime import datetime,timezone,timedelta;import sys;print((datetime.now(timezone.utc)+timedelta(hours=float(sys.argv[1]))).isoformat(timespec='seconds').replace('+00:00','Z'))" "$SPEND_VETO_HOURS" 2>/dev/null)"
  if [[ -z "$CC_DECIDE_BIN" ]]; then                   # never silent: surface via notify, mark once
    log "ERROR $sid ($acct) — monthly-spend kill but cc-decide unavailable; packet NOT opened (notified)"
    osascript -e "display notification \"${sid:0:8} ($acct) hit the monthly spend limit — cross-account continuation needed (cc-decide missing).\" with title \"lr-reset-poller\"" >/dev/null 2>&1 || true
    : > "$marker"; return 0
  fi
  id="$("$CC_DECIDE_BIN" open --class B \
        --what "$what" \
        --option "cross-account::resume the work on another Max account (next/next2/next3/next4) with quota headroom — quota-plane isolation" \
        --option "cap-raise::operator raises the monthly spend cap (money-path — operator only)" \
        --option "kimi-hedge::engage the Kimi hedge key (operator key required)" \
        --recommendation "cross-account continuation (quota-plane isolation)" \
        --default "cross-account continuation on another Max account with quota headroom" \
        --deadline "$deadline" \
        --session-sid "$sid" 2>>"$LOG")" \
    || { log "ERROR $sid ($acct) — cc-decide open failed (retrying next tick)"; return 0; }
  : > "$marker"
  log "SPEND $sid ($acct) — monthly-spend, no reset → class-B decision packet opened ($id; default fires $deadline)"
}

fired=0
# ── 1. DETECT + LEDGER parked sessions ────────────────────────────────────────────────
for cfg in "$HOME"/.claude-next "$HOME"/.claude-secondary "$HOME"/.claude-tertiary "$HOME"/.claude-quaternary; do
  [[ -d "$cfg/projects" ]] || continue
  acct=$(acct_of_cfg "$cfg"); [[ -n "$acct" ]] || continue
  while IFS= read -r tx; do
    [[ -n "$tx" ]] || continue
    sid=$(basename "$tx" .jsonl)
    tail_bytes=$(tail -c 20000 "$tx" 2>/dev/null)
    # ── MONTHLY-SPEND (billing plane) — a cap with NO reset. lr-audit can schedule nothing
    #    (nothing to wait for), and the session|weekly pre-filter below would DROP it silently
    #    (the pre-2026-07-19 gap). Per P0-8 / I-LIVE-1: surface a class-B packet, never park.
    #    Teammates are lead-owned (their lead's own spend kill carries the packet) — skip.
    if printf '%s' "$tail_bytes" | grep -qiE "$SPEND_RE"; then
      if head -c 8000 "$tx" 2>/dev/null | grep -q '"agentName"'; then
        if [[ ! -f "$STATE/teammate-skip/$sid" ]]; then
          mkdir -p "$STATE/teammate-skip"; : > "$STATE/teammate-skip/$sid"
          log "SKIP  $sid — teammate session (lead-owned recovery)"
        fi
        continue
      fi
      open_spend_packet "$sid" "$acct" "$(cwd_of "$tx")"
      continue
    fi
    # cheap pre-filter: a genuine limit line near the tail (isApiErrorMessage confirmed by lr-audit)
    printf '%s' "$tail_bytes" | grep -qE "You've hit your (session|weekly) limit" || continue
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
    cwd=$(cwd_of "$tx")
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

# ── 1b. CONSOLIDATE: decide the winners ONCE, before any firing ────────────────────────
# Candidates = parked sessions whose reset has passed. lr-select applies the per-worktree rule
# and the total ceiling (MAX_PER_RUN, so the existing bound is preserved and unified rather than
# second-guessed). Losers are moved to RESUMED/ below — LISTED, never deleted: the transcript is
# intact and can be resumed explicitly by sid, and a NEW limit event re-parks them normally.
# No --allow-missing-cwd here: this caller fires lr-fire-resume.sh WITHOUT --branch, so it cannot
# recreate a reaped worktree and must not fire into one.
now=$(date -u +%s)
WINNER_SIDS=""
if [[ ! -x "$SELECT" ]]; then
  # Fail CLOSED, loudly — same discipline as boot-resume.sh. The "working" fallback (fire
  # everything up to the per-tick cap) is the incident itself; an un-fired resume is recoverable
  # by a human, 8.8 GB of resurrected sessions took the machine down.
  log "ERROR lr-select missing at $SELECT — refusing to fire unconsolidated resumes this tick"
  exit 0
fi
sel_input=$(python3 -c "
import json,sys,glob,os,calendar
from datetime import datetime
now=int(sys.argv[2])
for p in sorted(glob.glob(os.path.join(sys.argv[1],'*.json'))):
    try: d=json.load(open(p))
    except Exception: continue
    try: e=calendar.timegm(datetime.fromisoformat(str(d.get('reset_at_utc','')).replace('Z','+00:00')).utctimetuple())
    except Exception: continue
    if now < e: continue
    print('%s:%s:%s'%(d.get('acct',''),d.get('sid',''),d.get('cwd','')))
" "$PARKED" "$now" 2>/dev/null)
if [[ -n "$sel_input" ]]; then
  sel_args=()
  while IFS= read -r c; do [[ -n "$c" ]] && sel_args+=(--candidate "$c"); done <<< "$sel_input"
  if (( ${#sel_args[@]} > 0 )); then
    WINNER_SIDS=$("$SELECT" "${sel_args[@]}" \
      --max-per-worktree "$MAX_PER_WT" --max-total "$MAX_PER_RUN" \
      --json "$STATE/last-selection.json" 2>"$STATE/last-triage.txt" | cut -f2)
    n_cand=$(printf '%s\n' "$sel_input" | grep -c . || true)
    n_win=0; [[ -n "$WINNER_SIDS" ]] && n_win=$(printf '%s\n' "$WINNER_SIDS" | grep -c . || true)
    (( n_cand > n_win )) && log "CONSOLIDATED $n_cand ready → $n_win winner(s) (max $MAX_PER_WT/worktree, $MAX_PER_RUN total); see $STATE/last-triage.txt"
  fi
fi

# ── 2. RESUME (or notify) parked sessions whose reset has passed ───────────────────────
for pf in "$PARKED"/*.json; do
  [[ -e "$pf" ]] || continue
  eval "$(python3 -c "
import json,sys
d=json.load(open(sys.argv[1]))
for k in ('sid','acct','cfg','cwd','reset_at_utc'):
    print('%s=%s'%(k,json.dumps(str(d.get(k,'')))))
" "$pf")"
  # sid/acct/cfg/cwd/reset_at_utc are populated by the eval'd python above — shellcheck cannot
  # trace an eval, so it reports reset_at_utc as unassigned (SC2154). It IS assigned.
  # shellcheck disable=SC2154
  reset_epoch=$(python3 -c "import sys,calendar,time; from datetime import datetime; print(int(calendar.timegm(datetime.fromisoformat(sys.argv[1].replace('Z','+00:00')).utctimetuple())))" "$reset_at_utc" 2>/dev/null || echo 0)
  (( now < reset_epoch )) && continue                        # reset not reached yet
  pgrep -f "resume $sid" >/dev/null 2>&1 && { mv "$pf" "$RESUMED/$(basename "$pf")" 2>/dev/null; rm -f "$PARKED/$sid.notified"; continue; }
  # Not the winner for its worktree → LIST it and retire THIS limit event. Leaving it parked
  # would just re-elect it next tick once the winner is running (already-running filters the
  # winner out) — sprawl at 10-minute cadence. The session is not lost: resume it explicitly by
  # sid, and a genuinely new limit event re-parks it via the REPARK path above.
  if ! printf '%s\n' "$WINNER_SIDS" | grep -qx "$sid"; then
    log "LISTED $sid ($acct) — not the per-worktree winner; consolidated, resume by sid if wanted"
    mv "$pf" "$RESUMED/$(basename "$pf")" 2>/dev/null; rm -f "$PARKED/$sid.notified"
    continue
  fi
  if ! account_has_headroom "$acct"; then log "WAIT  $sid — $acct still capped, retry next tick"; continue; fi
  (( fired >= MAX_PER_RUN )) && { log "CAP   per-run resume cap ($MAX_PER_RUN) reached; deferring rest"; break; }
  if [[ "$AUTOFIRE" == "1" && $DRY -eq 0 ]]; then
    launcher="/tmp/lr-poller-launch-${sid:0:8}.sh"
    { echo '#!/bin/bash'; printf 'exec "%s/lr-fire-resume.sh" "%s" "%s" "%s" --prompt %q\n' \
        "$LR" "$acct" "$cwd" "$sid" "/limit-recover"; } > "$launcher"; chmod +x "$launcher"
    if mech=$(spawn_resume "$launcher" "$sid"); then
      log "RESUMED $sid on $acct (autofire, $mech) — pane opened"
      mv "$pf" "$RESUMED/$(basename "$pf")"; rm -f "$PARKED/$sid.notified"; fired=$((fired+1))
    else
      log "ERROR  $sid — resume spawn failed (LR_POLLER_SPAWN=$SPAWN_MECH; no GUI and no tmux)"
    fi
  elif [[ ! -f "$PARKED/$sid.notified" ]]; then    # notify ONCE per parked session (no per-tick spam)
    mode=$([[ "$AUTOFIRE" == "1" ]] && echo "dry-run" || echo "notify-only")
    # headless-safe user alert (a LaunchAgent runs in the Aqua session ⇒ notifications work)
    osascript -e "display notification \"${sid:0:8} ($acct) limit reset — resumable. Set LR_POLLER_AUTOFIRE=1 to auto-resume.\" with title \"lr-reset-poller\"" >/dev/null 2>&1 || true
    : > "$PARKED/$sid.notified"
    log "READY $sid on $acct — $mode, notified once (LR_POLLER_AUTOFIRE=1 to auto-resume)"
  fi
done
exit 0
