#!/bin/bash
# idle-keepalive.sh — the idle-scoped prompt-cache keepalive for MAIN sessions, in SHADOW mode.
#
# Plan: docs/plans/USAGE_LEVERS.md § W3. It logs the moment it WOULD wake an idle session; it never
# wakes one. The switch-on decision is due after about 7 days of logs (bin/cc-idle-cache-readout).
#
# ── WHY A NEW TIMER, NOT A TWEAK TO THE EXISTING WAKE PATHS (reproduced in round 2, decision 3) ───
# A main session's cache lives 1 h, and the 3300 s wake that used to beat it no longer fires:
#   · hooks/session-continue.sh (wake_floor) stands its 3300 s floor DOWN whenever
#     mailbox-wake-arm.sh is registered on Stop with asyncRewake — which it is, on every account;
#   · that mechanical watcher runs `cc-await-ping --timeout 14340` and exits SILENTLY on timeout;
#   · and a keepalive bolted onto mailbox-wake-arm.sh does nothing, because its claim guard exits
#     when a watcher is already armed — and the watcher survives across turns (one ran 3h17m).
# So the keepalive must be its own hook, timed from the GAP START, not from whenever a watcher
# happened to be armed, and it must not care whether a watcher is armed. This file is that hook.
#
# ── WHAT IT DOES ─────────────────────────────────────────────────────────────────────────────────
# Registered on Stop with asyncRewake (migrations/0077), so the harness runs it in the background
# and does not reap it at the turn's end. At launch — the gap start — it notes the transcript size,
# then sleeps until gap start + CC_KEEPALIVE_WAKE_S (3300). If a new user or assistant record was
# appended meanwhile, the gap is over and it exits (idle-scoped: one timer per gap, and a new Stop
# launches the next one). Any OTHER record is not a turn: the away_summary system record that lands
# ~190 s into a gap used to end 52% of timers, because the old test was "the file grew" (W6). If
# the session is still idle, it writes a kind=wake row through hooks/lib/idle_gap.py — context
# size, whether a mailbox watcher is armed right then, whether the session's own background job was
# running and whether a running watcher would fire before the cache TTL — and exits 0. CC_KEEPALIVE_MAX_WAKES (1) bounds the wakes per gap ("about one wake per gap").
#
# SHADOW BY DEFAULT. asyncRewake wakes the model only on exit 2, and the EXIT trap below exits 0 on
# every path but the one D3 treatment wake (W7+ S12, below), which only a lever raised above pct 0
# can reach. The kind=gap rows (gap
# length, the rebuild the next request actually paid) come from the SYNCHRONOUS Stop hook
# hooks/cache-expiry-tracker.sh, which is already registered, so the ledger runs before 0077 does.
#
# W7+ S2 (docs/plans/USAGE_LEVERS.md § W7+ §2 D3 "Arm", §3 "Telemetry rows"): at EACH due time,
# before anything else happens there, it re-reads the lever flag file and computes D3's arm for the
# gap episode (hooks/lib/lever-flags.sh lf_arm, unit "<sid>:<episode start>", the lever's salt), and
# appends one kind=arm row to ~/.claude/logs/lever-arms.jsonl (UTC Z, ≤ 2 KB, one write) in BOTH
# arms; the arm then rides on the would-wake row (wake v3). The episode start is the gap state's own
# (hooks/lib/idle_gap.py), so the arm, wake and gap rows join on one unit. D3's busy-scoped
# eligibility is decided on the wake row, where the session's jobs are read. Nothing reads the arm
# back to act on it: no treatment branch exists yet (wave S12), and the trap still forces exit 0.
#
# W7+ S12 (plan § W7+ §2 D1 and D3, §3 "Never tunable"): the TREATMENT, reachable only at pct > 0.
# lf_arm gives treat only to a live lever above pct 0 with a fresh guard heartbeat and no un-acked
# trip; every lever is S0 / pct 0 today, so every path below still logs and exits 0.
#   D3  at each due time hooks/lib/idle_gap.py would-wake decides: arm treat at pct_eff > 0, the
#       session's own job busy (by its launching tool), no watcher firing before the TTL, not
#       headless, and the gap's one wake unspent. It writes the wake row (fired: true) FIRST and
#       prints "wake"; only then does this hook exit 2, the asyncRewake wake, with a one-line ask.
#   D1  once per gap, CC_D1_N_MIN (15) idle minutes in, if the gap opened at >= CC_D1_K (200)
#       thousand tokens: the D1 arm of the lineage root and its kind=arm row, then idle_gap.py
#       d1-due writes kind=would_recycle (the IRS v2 field names) in both arms. In treatment, with G1
#       (nothing busy) and G4 (no pending question) holding, it also writes the brief (G3/G5,
#       scripts/lib/idle_recycle_brief.py), the kind=d1_recycle row the lever guard reads, and the
#       treated D1 event in the IRS log; this hook then runs handoff-fire.sh --recycle with that
#       brief as the prompt. handoff-fire writes kind=d1_engage when the successor engages.
#   ONE wake per gap across both levers: whichever acts first claims <state>/wakes/<sid>.<gap start>
#   with O_EXCL, and a claimed gap never wakes again. Never tunable, like the headless exemption.
# Kill switches win on every path: CC_IDLE_KEEPALIVE=off (this hook), CC_LEVER_ALL / CC_LEVER_D1 /
# CC_LEVER_D3 = off or control, and CC_IRS=off for D1 (lf_arm lowers the arm; idle_gap.py re-checks).
#
# Kill switch: CC_IDLE_KEEPALIVE=off. Seams (tests): CC_IDLE_KEEPALIVE_HARNESS_ARGV /
# CC_IDLE_KEEPALIVE_HARNESS_FD1 (as mailbox-wake-arm.sh's), CC_IDLE_KEEPALIVE_SETTLE_S,
# CC_IDLE_KEEPALIVE_POLL_S, CC_KEEPALIVE_WAKE_S, CC_KEEPALIVE_MAX_WAKES, CC_D1_IDLE_S. bash 3.2-safe.
set -uo pipefail
_rc=0
trap 'exit "$_rc"' EXIT

[ "${CC_IDLE_KEEPALIVE:-shadow}" = shadow ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

_stdin="$(cat 2>/dev/null || true)"

# ── HEADLESS GUARD — the same three oracles as hooks/mailbox-wake-arm.sh (read its header) ───────
# asyncRewake is dispatched SYNCHRONOUSLY in a non-interactive session, so a 55-minute timer would
# block a `claude -p` for 55 minutes. A one-shot has no idle gap to keep warm anyway.
if [ "${CC_IDLE_KEEPALIVE_HARNESS_ARGV+x}" = x ]; then
  _harness="$CC_IDLE_KEEPALIVE_HARNESS_ARGV"; _harness_pid=""
else
  _harness=""; _harness_pid=""; _anc="$PPID"; _hops=0
  while [ -n "$_anc" ] && [ "$_anc" != 1 ] && [ "$_hops" -lt 6 ]; do
    _cmdline="$(ps -o command= -p "$_anc" 2>/dev/null || true)"
    case "$_cmdline" in *claude*|*node*) _harness="$_cmdline"; _harness_pid="$_anc"; break ;; esac
    _anc="$(ps -o ppid= -p "$_anc" 2>/dev/null | tr -d ' ' || true)"
    _hops=$(( _hops + 1 ))
  done
fi
[ -n "$_harness" ] || exit 0
case "$_harness" in
  *--input-format*stream-json*) : ;;
  *)
    case " $_harness " in *" -p "*|*" --print "*) exit 0 ;; esac
    [ "${CLAUDE_CODE_ENTRYPOINT:-}" != sdk-cli ] || exit 0
    if [ "${CC_IDLE_KEEPALIVE_HARNESS_FD1+x}" = x ]; then
      _fd1="$CC_IDLE_KEEPALIVE_HARNESS_FD1"
    elif [ -n "$_harness_pid" ]; then
      # fd 1 from libproc, never lsof: lsof lstat-scans /dev for device names, the walk that hung
      # every caller on 2026-10-25 (DESIGN.md I4). PROC_PIDLISTFDS returns each fd's TYPE only and
      # reads no vnode; a vnode stdout (type 1) on a process whose ctty is a pty (tdev 16/N, printed
      # with no lookup) is the TUI's terminal. A pipe or socket stdout is not.
      _fd1=""
      _tdev="$(ps -o tdev= -p "$_harness_pid" 2>/dev/null | tr -d ' ')"
      case "$_tdev" in
        16/[0-9]*)
          _fdt="$(python3 -I -c 'import ctypes, sys
lp = ctypes.CDLL("/usr/lib/libproc.dylib"); b = ctypes.create_string_buffer(32768)
n = lp.proc_pidinfo(int(sys.argv[1]), 1, 0, b, len(b))
print(next((int.from_bytes(b.raw[i + 4:i + 8], "little") for i in range(0, max(n, 0), 8)
            if int.from_bytes(b.raw[i:i + 4], "little", signed=True) == 1), -1))' "$_harness_pid" 2>/dev/null)"
          [ "$_fdt" = 1 ] && printf -v _fd1 '/dev/ttys%03d' "${_tdev#16/}" ;;
      esac
    else
      _fd1=""
    fi
    case "$_fd1" in /dev/tty*|/dev/pts/*) : ;; *) exit 0 ;; esac
    ;;
esac

_row="$(printf '%s' "$_stdin" | jq -r '[(.session_id // ""), (.transcript_path // "")] | join("\t")' 2>/dev/null)" || exit 0
_sid="${_row%%$'\t'*}"; _tp="${_row#*$'\t'}"
case "$_sid" in ''|*[!0-9A-Za-z-]*) exit 0 ;; esac
[ -f "$_tp" ] || exit 0

_lib="${BASH_SOURCE[0]%/*}/lib"
[ -f "$_lib/idle_gap.py" ] || exit 0

_num() { case "$1" in ''|*[!0-9]*) printf '%s' "$2" ;; *) printf '%s' "$1" ;; esac; }
_wake_s="$(_num "${CC_KEEPALIVE_WAKE_S:-}" 3300)"
_max="$(_num "${CC_KEEPALIVE_MAX_WAKES:-}" 1)"
_settle="$(_num "${CC_IDLE_KEEPALIVE_SETTLE_S:-}" 20)"
_poll="$(_num "${CC_IDLE_KEEPALIVE_POLL_S:-}" 60)"
# Strictly under the registered hook timeout (0077 registers 14400), as mailbox-wake-arm.sh does.
_bound=14340
_d1_n="$(_num "${CC_D1_N_MIN:-}" 15)"
_d1_s="$(_num "${CC_D1_IDLE_S:-}" $(( _d1_n * 60 )))"   # the wait from launch; the seam, as CC_KEEPALIVE_WAKE_S
_d1_k="$(_num "${CC_D1_K:-}" 200)"

_launch="$(date +%s)"
# The Stop's own hooks append records for a moment after it fires; let them land before the
# snapshot, or the first poll would read them as a new turn and end every gap at once.
sleep "$_settle"
_size() { stat -f %z "$1" 2>/dev/null || stat -c %s "$1" 2>/dev/null || echo x; }
_size0="$(_size "$_tp")"
# Did a new turn start? A user or assistant main-thread record past the snapshot. Rescanning from
# the snapshot each poll costs only what an idle gap appends, and never splits a record.
_turned() {
  [ "$(_size "$_tp")" != "$_size0" ] || return 1
  case "$_size0" in ''|*[!0-9]*) return 0 ;; esac
  tail -c +$(( _size0 + 1 )) "$_tp" 2>/dev/null \
    | jq -Rne '[inputs | fromjson? | objects
                | select((.type == "user" or .type == "assistant") and .isSidechain != true)]
               | length > 0' >/dev/null 2>&1
}

# Is a mailbox watcher armed right now? Recorded, never obeyed: coexistence is the point.
_watcher() {
  local _m="$_lib/mailbox-pending.sh" _k _pane
  [ -f "$_m" ] || { printf 'unknown'; return; }
  # shellcheck source=lib/mailbox-pending.sh
  # shellcheck disable=SC1091
  . "$_m" 2>/dev/null || { printf 'unknown'; return; }
  command -v mailbox_wake_armed >/dev/null 2>&1 || { printf 'unknown'; return; }
  _pane="${CC_PANE_ID:-${ITERM_SESSION_ID:-}}"; _pane="${_pane##*:}"
  for _k in $(mailbox_keyset "${_pane:-$_sid}" 2>/dev/null || printf '%s\n' "${_pane:-$_sid}"); do
    mailbox_wake_armed "$_k" && { printf 'true'; return; }
  done
  printf 'false'
}

# The gap episode's start: the state file idle_gap.py wrote at this same Stop, when it is this
# gap's (started within 300 s of this timer's launch); else the launch itself.
_episode() {
  local _st="${CC_IDLE_KEEPALIVE_STATE:-$HOME/.claude/state/idle-keepalive}/$_sid.json" _r _s _e
  _r="$(jq -r '[(.start // ""), (.episode // .start // "")] | map(tostring) | join(" ")' "$_st" 2>/dev/null)" || _r=""
  _s="${_r%% *}"; _e="${_r#* }"; _s="${_s%.*}"; _e="${_e%.*}"
  case "$_s$_e" in ''|*[!0-9]*) printf '%s' "$_launch"; return ;; esac
  if [ $(( _s - _launch )) -le 300 ] && [ $(( _launch - _s )) -le 300 ] && [ "$_e" -le "$_s" ]; then
    printf '%s' "$_e"
  else
    printf '%s' "$_launch"
  fi
}

_lf() {
  [ -f "$_lib/lever-flags.sh" ] || return 1
  # shellcheck source=lib/lever-flags.sh
  # shellcheck disable=SC1091
  . "$_lib/lever-flags.sh" 2>/dev/null || return 1
  command -v lf_arm >/dev/null 2>&1
}

# A lever's arm at this due time (a FRESH flag read) and its kind=arm row; sets _aj for the event row.
# <lever> <unit> <due_n>: D3 "<sid>:<episode>" with its wake count, D1 the lineage root with "d1".
_arm_row() {
  _aj=""
  _lf || return 0
  lf_arm "$1" "$2" || return 0
  _aj="$(lf_arm_json)"
  local _cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}" _logd="${CC_LEVER_LOG_DIR:-$HOME/.claude/logs}" _r _dn="$3"
  case "$_dn" in ''|*[!0-9]*) _dn="$(lf_jstr "$_dn")" ;; esac
  _cfg="${_cfg%/}"; _cfg="${_cfg##*/}"
  _r="${_aj%\}},\"acct\":$(lf_jstr "${_cfg:-.claude}"),\"due_n\":$_dn,\"gap_start\":\"$(date -u -r "$_launch" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)\",\"hook\":\"idle-keepalive\",\"kind\":\"arm\",\"sid\":\"$_sid\",\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"v\":1}"
  [ "${#_r}" -lt 2048 ] || return 0
  [ -d "$_logd" ] || mkdir -p "$_logd" 2>/dev/null || return 0
  printf '%s\n' "$_r" >> "$_logd/lever-arms.jsonl" 2>/dev/null || true
}

# Sleep until <epoch>; exit 0 the moment the gap ends (a new turn) or the hook's bound runs out.
_wait_until() {
  while :; do
    _now="$(date +%s)"
    [ "$_now" -lt "$1" ] || return 0
    [ $(( _now - _launch )) -lt "$_bound" ] || exit 0
    _left=$(( $1 - _now )); [ "$_left" -le "$_poll" ] || _left="$_poll"
    sleep "$_left"
    ! _turned || exit 0                               # the gap ended: a new turn wrote the transcript
  done
}

# D1 at its due time. The context gate runs in bash on the gap state (written by idle_gap.py stop at
# this same Stop), so a gap that opened below CC_D1_K forks nothing; above it, the arm row comes
# first, then the would_recycle row, then — treatment only — the recycle.
_d1_due() {
  local _st="${CC_IDLE_KEEPALIVE_STATE:-$HOME/.claude/state/idle-keepalive}/$_sid.json" _r _s _c _out _brief _rid
  _r="$(jq -r '[(.start // ""), (.ctx // 0)] | map(tostring) | join(" ")' "$_st" 2>/dev/null)" || return 0
  _s="${_r%% *}"; _c="${_r#* }"; _s="${_s%.*}"
  case "$_s$_c" in ''|*[!0-9]*) return 0 ;; esac
  [ $(( _s - _launch )) -le 300 ] && [ $(( _launch - _s )) -le 300 ] || return 0
  [ "$_c" -ge $(( _d1_k * 1000 )) ] || return 0
  _lf || return 0
  lf_lineage "$_sid"
  _arm_row D1 "$LF_LINEAGE" d1
  _out="$(/usr/bin/env python3 -I "$_lib/idle_gap.py" d1-due "$_sid" "$_launch" "$_aj" "${LF_LINEAGE_SRC:-}" \
    "$_d1_k" "$_d1_n" false 2>/dev/null)" || return 0
  case "$_out" in "recycle"$'\t'*) ;; *) return 0 ;; esac
  _out="${_out#recycle$'\t'}"; _brief="${_out%%$'\t'*}"; _rid="${_out#*$'\t'}"
  [ -f "$_brief" ] || return 0
  # The gap's one wake is spent on this recycle, whatever handoff-fire makes of it.
  CC_D1_RECYCLE_ID="$_rid" CC_D1_RECYCLE_SID="$_sid" \
    "$HOME/.claude/scripts/handoff-fire.sh" --recycle --prompt-file "$_brief" </dev/null \
    >> "${CC_IDLE_KEEPALIVE_STATE:-$HOME/.claude/state/idle-keepalive}/d1-fire.log" 2>&1 || true
  exit 0
}

if [ "$_d1_s" -gt 0 ] && [ "$_d1_s" -lt "$_wake_s" ]; then
  _wait_until $(( _launch + _d1_s ))
  _d1_due
fi

_n=0
_due=$(( _launch + _wake_s ))
while [ "$_n" -lt "$_max" ]; do
  _wait_until "$_due"
  _n=$(( _n + 1 ))
  _arm_row D3 "$_sid:$(_episode)" "$_n"               # before anything acts at this due time
  _v="$(/usr/bin/env python3 -I "$_lib/idle_gap.py" would-wake "$_sid" "$_launch" "$(_watcher)" "$_n" "$_aj" false \
    2>/dev/null)" || _v=""
  if [ "$_v" = wake ]; then
    # THE WAKE (D3 treatment): asyncRewake delivers stderr to the model on exit 2. The wake row is
    # already written (fired: true) and the gap's wake claimed, so this cannot repeat in this gap.
    printf '%s\n' "Keepalive wake (lever D3): this session has sat idle about $(( _wake_s / 60 )) min while its own background job runs; the wake only keeps the prompt cache warm. Answer in one line and keep waiting; start nothing new." >&2
    _rc=2
    exit 2
  fi
  _due=$(( _due + _wake_s ))
done
exit 0
