#!/bin/bash
# SessionStart Hook - MCP Status Logger
# Logs MCP server status and provides additionalContext to warn Claude
# about potential initialization delays (per GitHub issue #723)

set -euo pipefail

LOG_DIR=~/.claude/logs
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/sessions.log"

# `--refresh-mcp-cache` re-enters this same script as a detached background refresher (see the
# MCP section). It must do the probe and NOTHING else — no session log line, no daily prunes, no
# stdout JSON — so the dispatch happens after the probe machinery is defined and before every
# other duty. MCP_MODE is read here, at the top, so the ordering constraint is visible.
MCP_MODE="${1:-}"
[ "$MCP_MODE" = "--refresh-mcp-cache" ] || \
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Session started in $(pwd)" >> "$LOG_FILE"

# === EFFORT ENV-VAR TRIPWIRE (2026-06-11) ===
# CLAUDE_CODE_EFFORT_LEVEL in the process env outranks /effort EVERY turn and
# cannot be cleared from inside a session (Bash-tool `unset` runs in a child
# shell) — the harness contract is: effort defaults ride the launchers'
# `--effort` flag + settings.json effortLevel, NEVER this env var. If it shows
# up here it leaked from a stale shell, a settings.json env block, or a new
# rogue export. The warning is folded into the final hookSpecificOutput JSON
# (this hook's stdout must stay a single JSON object — a bare echo would break
# the parse and demote the whole output to plain context).
EFFORT_WARN=""
if [ -n "${CLAUDE_CODE_EFFORT_LEVEL:-}" ]; then
  # sanitize value for safe JSON interpolation (levels are [a-z0-9]; anything else is suspicious anyway)
  _EFFORT_VAL=$(printf '%s' "$CLAUDE_CODE_EFFORT_LEVEL" | tr -cd '[:alnum:]_-' | cut -c1-32)
  EFFORT_WARN="WARNING: CLAUDE_CODE_EFFORT_LEVEL=${_EFFORT_VAL} is set in this session's environment — /effort is LOCKED to it all session (re-read every turn; cannot be unset from inside). The harness contract (zshrc effort block 2026-06-11) injects --effort at launch instead; find and remove the export (stale pre-fix terminal tab, settings.json env block, or rogue wrapper/launchd export). "
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARN: CLAUDE_CODE_EFFORT_LEVEL=${_EFFORT_VAL} present at SessionStart in $(pwd)" >> "$LOG_FILE"
fi

# === DAILY BACKUP PRUNING (background, non-blocking) ===
PRUNE_SCRIPT="$HOME/.claude/scripts/prune-backups.sh"
LAST_PRUNE_FILE="$HOME/.claude/.last-backup-prune"
TODAY=$(date +%Y-%m-%d)
# The background cache refresher must not consume the daily marker — it would make the real
# session start skip the prune for the rest of the day.
if [ "$MCP_MODE" != "--refresh-mcp-cache" ] && [ -x "$PRUNE_SCRIPT" ]; then
  if [ ! -f "$LAST_PRUNE_FILE" ] || [ "$(cat "$LAST_PRUNE_FILE" 2>/dev/null)" != "$TODAY" ]; then
    echo "$TODAY" > "$LAST_PRUNE_FILE"
    # >/dev/null: a backgrounded child INHERITS this hook's stdout pipe, and the harness does not
    # see EOF until every writer closes it — `&` does not close a descriptor and neither does
    # `disown`. An unredirected background prune can therefore hold the SessionStart chain open
    # long after the hook itself has exited (backlog 50627335fe9b).
    "$PRUNE_SCRIPT" >/dev/null &  # Background, non-blocking
  fi
fi

# === DAILY PLAN-HISTORY PRUNING (background, non-blocking) ===
# Same daily-marker shape as the backup prune above — that wiring is the reference
# (audit 03 §1c calls backups/ "the reference-quality wiring"; plan-history had none).
# Bounds MANIFEST.jsonl to keep-10-per-plan + 90 d and `git gc`s the plan-history repo.
PLAN_PRUNE_SCRIPT="$HOME/.claude/scripts/prune-plan-history.sh"
LAST_PLAN_PRUNE_FILE="$HOME/.claude/.last-plan-history-prune"
if [ "$MCP_MODE" != "--refresh-mcp-cache" ] && [ -x "$PLAN_PRUNE_SCRIPT" ]; then
  if [ ! -f "$LAST_PLAN_PRUNE_FILE" ] || [ "$(cat "$LAST_PLAN_PRUNE_FILE" 2>/dev/null)" != "$TODAY" ]; then
    echo "$TODAY" > "$LAST_PLAN_PRUNE_FILE"
    "$PLAN_PRUNE_SCRIPT" >/dev/null 2>&1 &  # Background, non-blocking
  fi
fi

# === MCP CONNECTIVITY PROBE (resolution fixed 2026-08-11, backlog aac347ddc003) ===
# WHY THE RESOLUTION IS NOT `command -v claude`. Measured over ~/.claude/logs/sessions.log on
# 2026-08-11: the old `command -v claude` gate did NOT skip the probe (7,022 of 8,636 sessions
# logged an MCP Status line) — it resolved, but to the WRONG BINARY. `command -v claude` on the
# hook's inherited PATH finds ~/Library/pnpm/claude, the stock pnpm install, **2.0.5**, while the
# session that fired this hook is 2.1.220. Side by side that same minute:
#     ~/Library/pnpm/claude  mcp list -> 2 servers  (motion, motion-plus)         ✓ Connected
#     ~/.claude-220/…/claude mcp list -> 6 servers  (+ the 4 claude.ai session-connected ones)  ✔
# So on the 81% of starts where it resolved, the sensor reported "MCP: 2 server(s)" into the
# session's additionalContext while the session held 6 — the four claude.ai session-connected
# servers were structurally invisible to it, in the fleet whose MCP memory is the subject. That is
# the failure in memory version-identity-is-the-running-process-not-the-launcher: a launcher name
# on PATH reports ITS track, never the running session's. Note also the checkmark differs by track
# (2.0.5 emits U+2713 ✓, 2.1.220 emits U+2714 ✔) — the count below matches BOTH.
#
# The second half of the defect: when the probe could NOT run (no binary, or every attempt failed)
# CONNECTED_COUNT stayed 0 and the hook emitted the same "MCP not responding" as a genuine
# zero-connected answer. One value meaning both "answered zero" and "could not ask" fabricates a
# finding (memory sensor-default-off-makes-blindness-the-shipping-path). MCP_STATE now separates
# them and the emitted context says which.
#
# COST, AND HOW THE BOUND WAS SIZED. This runs on the SessionStart critical path, so the retry tail
# is now bounded twice — a per-attempt timeout AND a whole-probe budget — where the old loop had no
# ceiling at all (3 unbounded CLI spawns + 3 s of backoff). Measured 2026-08-11 on this box:
#   one `mcp list`, 2.1.220 (6 servers)   : 2.89 / 2.51 / 2.58 s      <- the common path
#   one `mcp list`, claude-latest 2.1.114 : 2.64 / 2.39 s
#   one `mcp list`, stale 2.0.5 (2 servers): 1.29 s                   <- what it used to cost, wrongly
# The first bound written here was 5 s, and a live fixtured run REFUTED it inside the hour: attempt 1
# timed out and the hook only answered on attempt 2, total 10.5 s. The clean-bench number is not the
# band — this box runs sibling agent sessions and a bats corpus, and the probe's own tail sits well
# above its 2.6 s median under that load (memory bound-must-fit-the-band-not-the-bench). 10 s leaves
# ~4x headroom over the measured median; the budget caps the pathological case near 15 s. A too-tight
# bound is not a safe default here: it would convert a healthy probe into a FALSE "could not ask".
#
# WHY IT IS NO LONGER ON THE CRITICAL PATH AT ALL (DESK_ROUTER_AND_STARTUP_V1 W0.2).
# Every number above is a cost paid on EVERY SessionStart — and both SessionStart blocks use a
# null matcher, so `startup`, `resume`, `clear` and `compact` all pay it. Once the 21-29 s
# setup-task-symlinks.sh fork storm was fixed (W0.1), this 2.5 s median WAS the remaining floor.
# It buys one advisory string.
#
# The fix is stale-while-revalidate, not a bigger timeout (raising the bound would make the tail
# worse, which is the opposite of the goal):
#   · fresh cache (<= TTL)      -> serve it, zero subprocesses.
#   · stale cache (<= MAX_AGE)  -> serve it AND detach a background refresh for the NEXT start.
#   · no cache / too old        -> probe INLINE exactly as before, then cache.
# So a healthy fleet pays the 2.5 s once and never again, while a box that has never probed still
# gets a real answer on its first start rather than a fabricated one.
#
# Three deliberate choices, each of which the obvious version gets wrong:
#   · ONLY `ok` results are cached. Caching a failure makes a transient failure STICKY and hides a
#     genuinely broken probe behind a TTL — the runtime form of the anti-capture rule. A probe that
#     could not ask therefore still costs full price on the next start, which is exactly the
#     current behaviour, so this is not a regression: the alarm keeps firing.
#   · Staleness is VISIBLE. A served-from-cache claim carries its age. A board that silently prints
#     stale numbers is worse than no board, and the same holds for a sensor.
#   · MAX_AGE is a hard stop, not decoration. If background refreshes keep failing, the cache
#     eventually stops being served and the inline probe returns — degrading loudly toward the old
#     cost instead of quietly serving an answer from last week.
MAX_ATTEMPTS=${CC_MCP_PROBE_ATTEMPTS:-2}
PROBE_TIMEOUT=${CC_MCP_PROBE_TIMEOUT:-10}   # seconds, per attempt
PROBE_BUDGET=${CC_MCP_PROBE_BUDGET:-15}     # seconds, whole probe including backoff
ATTEMPT=0
DELAY=1
CONNECTED_COUNT=0
DEGRADED_COUNT=0
MCP_STATE=unknown        # ok = the probe ANSWERED (count is real) | unknown = could not ask
MCP_REASON="not attempted"
MCP_AGE=-1               # >=0 ⇒ this answer came from cache, that many seconds old
PROBE_START=$SECONDS

# The cache is keyed per CONFIG DIR: the probe's answer depends on which binary/track the session
# is, and that is what CLAUDE_CONFIG_DIR selects. A single shared file would let account 1's answer
# be served to account 3.
_MCP_CFG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
MCP_CACHE_FILE="${CC_MCP_CACHE_FILE:-$_MCP_CFG_DIR/.mcp-probe-cache}"
MCP_CACHE_TTL=${CC_MCP_CACHE_TTL:-300}          # serve with no refresh
MCP_CACHE_MAX_AGE=${CC_MCP_CACHE_MAX_AGE:-86400} # beyond this, refuse to serve; probe inline
MCP_CACHE_LOCK="$MCP_CACHE_FILE.refresh.lock"
MCP_CACHE_LOCK_STALE=${CC_MCP_CACHE_LOCK_STALE:-600}

_now() { date +%s; }

# Reads the cache into CACHE_*; returns 1 on absent/unparseable/wrong-version/not-ok. A record that
# fails any check is treated as absent, never as a partial answer.
_mcp_cache_read() {
  [ -f "$MCP_CACHE_FILE" ] || return 1
  local v e s c d r
  IFS="$(printf '\t')" read -r v e s c d r < "$MCP_CACHE_FILE" 2>/dev/null || return 1
  [ "$v" = "v1" ] || return 1
  case "$e" in ''|*[!0-9]*) return 1 ;; esac
  case "$c" in ''|*[!0-9]*) return 1 ;; esac
  case "$d" in ''|*[!0-9]*) return 1 ;; esac
  [ "$s" = "ok" ] || return 1
  CACHE_EPOCH="$e"; CACHE_STATE="$s"; CACHE_CONNECTED="$c"; CACHE_DEGRADED="$d"; CACHE_REASON="${r:-}"
  return 0
}

# Atomic (write-temp + rename) so a concurrent reader never sees a half-written record.
_mcp_cache_write() {
  [ "$MCP_STATE" = "ok" ] || return 0
  mkdir -p "$_MCP_CFG_DIR" 2>/dev/null || true
  local tmp="$MCP_CACHE_FILE.$$"
  if printf 'v1\t%s\t%s\t%s\t%s\t%s\n' \
       "$(_now)" "$MCP_STATE" "$CONNECTED_COUNT" "$DEGRADED_COUNT" "$MCP_REASON" > "$tmp" 2>/dev/null; then
    mv -f "$tmp" "$MCP_CACHE_FILE" 2>/dev/null || rm -f "$tmp" 2>/dev/null || true
  else
    rm -f "$tmp" 2>/dev/null || true
  fi
}

# Detach ONE refresher. `mkdir` is the atomic test-and-set — several sessions starting together
# must not each spawn a CLI. A lock left behind by a crash is reaped by age, otherwise refreshes
# would stop forever and the cache would silently rot up to MAX_AGE.
_mcp_spawn_refresh() {
  if [ -d "$MCP_CACHE_LOCK" ]; then
    local lock_m now_s
    lock_m=$(stat -f %m "$MCP_CACHE_LOCK" 2>/dev/null || echo 0)
    now_s=$(_now)
    if [ "$(( now_s - lock_m ))" -gt "$MCP_CACHE_LOCK_STALE" ]; then
      rmdir "$MCP_CACHE_LOCK" 2>/dev/null || true
    fi
  fi
  mkdir "$MCP_CACHE_LOCK" 2>/dev/null || return 0
  # Same script, same probe code — one implementation, two entry points.
  #
  # 🚨 The redirect on the SUBSHELL is load-bearing, and redirecting only the inner `bash` is not
  # enough (that was the bug, 2026-08-16). The harness reads a hook's stdout to EOF, and EOF does
  # not arrive while ANY descendant still holds fd 1. With the inner command redirected but the
  # enclosing `( … ) &` inheriting the pipe, this "detached" refresher blocked the input pipeline
  # for its full run: process-exit 83 ms vs pipe-EOF 3 096 ms on the same hook (n=5), and a pty A/B
  # measured `( sleep 6 ) &` → /help at 6.4 s vs `( sleep 6 ) >/dev/null 2>&1 &` → 1.4 s. The
  # configured `timeout: 10` does NOT cap it, because the hook process itself has already exited.
  # Measured cost of the leak: +2.2 s p50 / +4.2 s p90 of BLOCKED INPUT on 54.4% of session starts.
  ( bash "${BASH_SOURCE[0]}" --refresh-mcp-cache >/dev/null 2>&1
    rmdir "$MCP_CACHE_LOCK" 2>/dev/null || true ) >/dev/null 2>&1 &
}

# Resolve the binary the RUNNING session is, in strictly-decreasing authority. Deliberately no bare
# `command -v claude` rung here: that is the stale stock install this fix exists to stop calling.
# cc-claude-bin keeps it as its own documented last resort and REPORTS that rung, so if it is ever
# reached the log below says so instead of silently answering about another track.
CLAUDE_BIN=""; BIN_RUNG=""
_resolve_claude_bin() {
  if [ -n "${CC_CLAUDE_BIN:-}" ] && [ -x "${CC_CLAUDE_BIN}" ]; then
    printf '%s\t%s\n' "$CC_CLAUDE_BIN" "CC_CLAUDE_BIN override"; return 0
  fi
  # 1. our own parent IS the claude process that fired this hook — the running binary, not a name.
  local _pcmd _first
  _pcmd="$(ps -o command= -p "${PPID:-0}" 2>/dev/null | head -1 || true)"
  _first="${_pcmd%% *}"
  case "${_first##*/}" in
    claude|claude-*)
      if [ -n "$_first" ] && [ -x "$_first" ]; then
        printf '%s\t%s\n' "$_first" "PPID (running session binary)"; return 0
      fi ;;
  esac
  # 2. the fleet SSOT resolver (reads the launcher's own _bin= pin in ~/.zshrc).
  local _r
  if [ -x "$HOME/.claude/bin/cc-claude-bin" ]; then
    _r="$("$HOME/.claude/bin/cc-claude-bin" --explain 2>/dev/null || true)"
    if [ -n "$_r" ]; then printf '%s\n' "$_r"; return 0; fi
  fi
  return 1
}

_TIMEOUT_BIN=""
for _t in timeout gtimeout; do
  if command -v "$_t" >/dev/null 2>&1; then _TIMEOUT_BIN="$_t"; break; fi
done

# The probe itself, unchanged in behaviour and now reachable from two entry points: the inline
# cache-miss path below, and the detached `--refresh-mcp-cache` re-entry. Deliberately ONE
# implementation — a second copy for the background path is how the two answers drift apart.
_mcp_probe() {
if _RES="$(_resolve_claude_bin)"; then
  CLAUDE_BIN="${_RES%%	*}"
  BIN_RUNG="${_RES#*	}"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] MCP probe binary: $CLAUDE_BIN [$BIN_RUNG]" >> "$LOG_FILE"
  MCP_REASON="probe ran but never answered"

  while [ "$ATTEMPT" -lt "$MAX_ATTEMPTS" ]; do
    _LEFT=$(( PROBE_BUDGET - (SECONDS - PROBE_START) ))
    if [ "$_LEFT" -le 0 ]; then
      MCP_REASON="probe budget (${PROBE_BUDGET}s) exhausted after $ATTEMPT attempt(s)"
      break
    fi
    _THIS=$PROBE_TIMEOUT
    [ "$_LEFT" -lt "$_THIS" ] && _THIS=$_LEFT

    # The pane identity is deliberately NOT inherited by this child. `claude mcp list` emits a
    # SessionEnd hook event of its own — reason "other", a fresh session_id, and NO matching
    # SessionStart — so every pane-keyed SessionEnd consumer reads it as THIS pane's session
    # ending, one second into that session's life. That is how every session start came to delete
    # its own cc-registry row (2026-08-05; hooks/session-deregister.sh header carries the
    # measurement). That consumer now proves tenancy before acting, but the phantom event is the
    # source and it fires for every consumer, including ones not written yet: blanking both vars
    # makes it PANELESS, so a pane-keyed hook no-ops at its own pane gate instead of acting on a
    # live pane's state. `claude mcp list` reads neither var for anything of its own. `env -u`
    # (not a `VAR= ` prefix) so they are genuinely ABSENT, which is what the consumers' `${VAR:-}`
    # gates read — and it costs one fork on a path that is already spawning a whole CLI.
    # The timeout wrapper goes INSIDE env -u, so a timed-out probe is still paneless.
    _RC=0
    if [ -n "$_TIMEOUT_BIN" ]; then
      MCP_OUTPUT=$(env -u CC_PANE_ID -u ITERM_SESSION_ID "$_TIMEOUT_BIN" "$_THIS" "$CLAUDE_BIN" mcp list 2>&1) || _RC=$?
    else
      MCP_OUTPUT=$(env -u CC_PANE_ID -u ITERM_SESSION_ID "$CLAUDE_BIN" mcp list 2>&1) || _RC=$?
    fi

    if [ "$_RC" -eq 0 ]; then
      # Count only SOLIDLY-connected lines, matching lib/cc-upgrade-gate/check13_mcp.sh. The old
      # bare `grep -c Connected` also counted "! Connected" degraded rows as healthy. Alternation,
      # not a [✔✓] bracket class — a multibyte bracket expression is byte-wise under a non-UTF-8
      # locale, which a hook cannot assume it has.
      CONNECTED_COUNT=$(printf '%s\n' "$MCP_OUTPUT" | grep -cE '(✔|✓) Connected' || true)
      DEGRADED_COUNT=$(printf '%s\n' "$MCP_OUTPUT" | grep -cE 'timed out|✗|Failed|! Connected' || true)
      MCP_STATE=ok
      MCP_REASON=""
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] MCP Status (attempt $((ATTEMPT+1))):" >> "$LOG_FILE"
      echo "$MCP_OUTPUT" >> "$LOG_FILE"
      if [ "$CONNECTED_COUNT" -gt 0 ]; then
        break
      fi
    elif [ "$_RC" -eq 124 ] || [ "$_RC" -eq 137 ]; then
      [ "$MCP_STATE" = ok ] || MCP_REASON="probe timed out after ${_THIS}s"
    else
      [ "$MCP_STATE" = ok ] || MCP_REASON="probe exited rc=$_RC"
    fi

    ATTEMPT=$((ATTEMPT + 1))
    if [ "$ATTEMPT" -lt "$MAX_ATTEMPTS" ]; then
      sleep $DELAY
      DELAY=$((DELAY * 2))
    fi
  done
else
  MCP_REASON="no claude binary resolved (PPID, cc-claude-bin)"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] MCP probe SKIPPED: $MCP_REASON" >> "$LOG_FILE"
fi
}

# ── Background-refresh entry point ────────────────────────────────────────────────────────────
# Probe, cache, exit. No stdout JSON, no session log line, no daily prunes (guarded above).
if [ "$MCP_MODE" = "--refresh-mcp-cache" ]; then
  _mcp_probe
  _mcp_cache_write
  exit 0
fi

# ── Serve: fresh cache → stale cache + refresh → inline probe ─────────────────────────────────
_MCP_SERVED_FROM_CACHE=0
if _mcp_cache_read; then
  _AGE=$(( $(_now) - CACHE_EPOCH ))
  [ "$_AGE" -lt 0 ] && _AGE=0          # clock moved backwards; treat as fresh, never negative
  if [ "$_AGE" -le "$MCP_CACHE_MAX_AGE" ]; then
    MCP_STATE="$CACHE_STATE"
    CONNECTED_COUNT="$CACHE_CONNECTED"
    DEGRADED_COUNT="$CACHE_DEGRADED"
    MCP_REASON="$CACHE_REASON"
    MCP_AGE="$_AGE"
    _MCP_SERVED_FROM_CACHE=1
    [ "$_AGE" -gt "$MCP_CACHE_TTL" ] && _mcp_spawn_refresh
  fi
fi

if [ "$_MCP_SERVED_FROM_CACHE" -eq 0 ]; then
  _mcp_probe
  _mcp_cache_write
fi

# Sanitize for JSON interpolation — same treatment the effort tripwire gives its value.
MCP_REASON=$(printf '%s' "$MCP_REASON" | tr -cd '[:alnum:] ()=.,:_/-' | cut -c1-120)

# Staleness is part of the claim, never implied. A reader must be able to tell a live answer from
# one carried over from an earlier session.
_CACHE_NOTE=""
if [ "$MCP_AGE" -ge 0 ]; then
  if [ "$MCP_AGE" -lt 60 ]; then _CACHE_NOTE=" [cached ${MCP_AGE}s ago]"
  elif [ "$MCP_AGE" -lt 3600 ]; then _CACHE_NOTE=" [cached $(( MCP_AGE / 60 ))m ago]"
  else _CACHE_NOTE=" [cached $(( MCP_AGE / 3600 ))h ago]"
  fi
fi

# Check agent-browser installation
AGENT_BROWSER_STATUS="not installed"
if command -v agent-browser &> /dev/null; then
  AGENT_BROWSER_STATUS="installed"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] agent-browser: $AGENT_BROWSER_STATUS" >> "$LOG_FILE"
fi

# Output additionalContext for Claude (JSON format).
# THREE states, never two: a probe that could not run must not be spelled the same way as a probe
# that ran and counted zero. The reader acts differently on each — "0 connected" means reach for
# agent-browser, "UNKNOWN" means the MCP tools may well be there and this hook simply failed to
# look, so absence of an MCP claim here is not evidence of absence of MCP.
_DEG=""
[ "$DEGRADED_COUNT" -gt 0 ] && _DEG=" ($DEGRADED_COUNT degraded)"
if [ "$MCP_STATE" = ok ] && [ "$CONNECTED_COUNT" -gt 0 ]; then
  MCP_CLAIM="MCP: $CONNECTED_COUNT server(s) connected${_DEG}${_CACHE_NOTE}. agent-browser: $AGENT_BROWSER_STATUS. If BrowserMCP tools fail with 'No such tool available', use agent-browser skill instead."
elif [ "$MCP_STATE" = ok ]; then
  MCP_CLAIM="MCP: 0 servers connected — the probe RAN and answered zero${_DEG}${_CACHE_NOTE}. agent-browser: $AGENT_BROWSER_STATUS. Use agent-browser skill for browser automation."
else
  MCP_CLAIM="MCP: UNKNOWN — the probe could not ask ($MCP_REASON). This is NOT a report of zero connected servers; MCP tools may be present. agent-browser: $AGENT_BROWSER_STATUS. If a BrowserMCP tool fails with 'No such tool available', use agent-browser skill instead."
fi

cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "${EFFORT_WARN}${MCP_CLAIM}"
  }
}
EOF

exit 0
