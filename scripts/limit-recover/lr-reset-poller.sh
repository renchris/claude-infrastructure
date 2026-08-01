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
# SHIPPED-POSTURE: LR_POLLER_AUTOFIRE=1
#   The installed LaunchAgent SETS this, so unattended auto-resume is LIVE in production. This marker
#   and com.reso.lr-reset-poller.plist are ONE SSOT pair; LR-v in tests/lr-reset-poller.bats compares
#   them structurally, so drifting either side fails the suite. Change both in the same commit.
#
# SAFETY — the CODE default is notify-only, but that is NOT the shipped posture. Unset/0
# LR_POLLER_AUTOFIRE ⇒ detect + NOTIFY + log only (no session is spawned); production overrides it to
# 1 in the plist, so a limit-parked session IS resumed unattended with nobody watching. Do not read
# the code default as "auto-resume is off" — read the plist (until 2026-07-30 this header still said
# "OFF by default … set it ONLY after eyeballing a live cycle", which had been false for 12 days and
# understated what the daemon does). Live receipt: the LaunchAgent was installed
# 2026-07-18T17:00:15-0700 and RunAtLoad fired a REAL resume 10s later —
# `2026-07-19T00:00:25Z RESUMED 6802c9b8 … on next4 (autofire) — pane opened` in poller.log.
# Kill switch: LR_POLLER_DISABLED=1 (or unload). Idempotent, fail-open, never crashes the daemon.
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

# Bound every call that reaches the iTerm2 / AppleEvent surface (machine-wide API wedge,
# 2026-07-26: a bare `it2 session list --json` returned rc 124 with zero output while blocked forks
# piled up). spawn_gui drives iTerm2 directly and this poller is a launchd job, so an unbounded AppleEvent
# wedges the job forever; the caller already falls back to tmux when the GUI spawn fails (LR-m).
# timeout(1) is resolved by ABSOLUTE PATH as well as PATH — launchd jobs and hooks run with a
# minimal PATH excluding Homebrew, exactly where coreutils installs it, so a PATH-only lookup would
# leave the AUTOMATED callers unbounded while interactive shells stayed safe. No timeout(1) ⇒ run
# unbounded rather than break the call. Seams: LRP_OSA_TIMEOUT_S · LRP_OSA_TIMEOUT_BIN
# (set-but-EMPTY disables verbatim; `${VAR:-}` cannot tell unset from set-empty).
LRP_TIMEOUT_S="${LRP_OSA_TIMEOUT_S:-15}"
if [ -n "${LRP_OSA_TIMEOUT_BIN+set}" ]; then
  LRP_TIMEOUT_BIN="$LRP_OSA_TIMEOUT_BIN"
else
  LRP_TIMEOUT_BIN=""
  for _c in "$(command -v timeout 2>/dev/null || true)" "$(command -v gtimeout 2>/dev/null || true)" \
            /opt/homebrew/bin/timeout /usr/local/bin/timeout \
            /opt/homebrew/bin/gtimeout /usr/local/bin/gtimeout; do
    [ -n "$_c" ] && [ -x "$_c" ] && { LRP_TIMEOUT_BIN="$_c"; break; }
  done
fi
lrp_bounded() {
  if [ -z "$LRP_TIMEOUT_BIN" ] || [ ! -x "$LRP_TIMEOUT_BIN" ]; then "$@"; return $?; fi
  "$LRP_TIMEOUT_BIN" -k 3 "$LRP_TIMEOUT_S" "$@"
}


[[ -n "${LR_POLLER_DISABLED:-}" ]] && exit 0

LR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUDIT="$LR/lr-audit.py"
STATE="$HOME/.reso/limit-recover"
PARKED="$STATE/parked"; RESUMED="$STATE/resumed"; LOG="$STATE/poller.log"
CLAIMS="$STATE/fire-claims"
mkdir -p "$PARKED" "$RESUMED" "$CLAIMS"
# Parse EVERY argument, not just $1. Until 2026-07-30 this read `[[ "${1:-}" == "--dry-run" ]] && DRY=1`,
# so `--once --dry-run` silently ran FOR REAL and spawned live sessions — a preview flag that is
# silently ignored is worse than no preview flag at all, because the operator has already decided it is
# safe to run. The documented order is [--dry-run] [--once], but `--once --dry-run` is what a human
# types when ADDING dry-run to a command already in their shell history, and no test had ever passed
# --dry-run in a non-first position, which is exactly why it survived (found by LR-t).
# Unknown args are REFUSED, not ignored: silence is what hid this. launchd runs the script bare, so
# the loop is a no-op there.
DRY=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY=1 ;;
    --once)    : ;;   # accepted no-op — this script is single-pass by construction (launchd re-runs it)
    *) printf 'lr-reset-poller: unknown argument: %s\nusage: lr-reset-poller.sh [--dry-run] [--once]\n' "$arg" >&2; exit 2 ;;
  esac
done

# ── SELF-OVERLAP LOCK (skip, never queue) ──────────────────────────────────────────────
# launchd fires this every ~10 min, but a tick does per-session lr-audit subprocesses and
# claude-accounts calls; on a loaded box a tick can outrun its own interval. Overlapping
# ticks each pass the "already running" guard below and fire the SAME session twice —
# observed 2026-07-26: FOUR concurrent `--resume 076a1186-…`, three spawned within ~90 s,
# ~1.9 GB and four processes appending to ONE transcript. Same class as the cc-reaper
# self-overlap. SKIP (not queue): a missed tick costs 10 minutes; a doubled tick costs a
# duplicate session. Holder identity is pid+lstart — `kill -0` alone wedges forever on a
# recycled pid. Seam: LR_POLLER_LOCK_DIR lets the suite stay off the real state dir.
LOCKD="${LR_POLLER_LOCK_DIR:-$STATE/poller.lock}"
_lstart_of() { ps -o lstart= -p "$1" 2>/dev/null | tr -s ' '; }
if ! mkdir "$LOCKD" 2>/dev/null; then
  _hp=$(cat "$LOCKD/pid" 2>/dev/null || echo "")
  _hl=$(cat "$LOCKD/lstart" 2>/dev/null || echo "")
  if [[ "$_hp" =~ ^[0-9]+$ ]] && kill -0 "$_hp" 2>/dev/null && [[ "$(_lstart_of "$_hp")" == "$_hl" ]]; then
    exit 0                                   # a genuine live tick holds it — skip this one
  fi
  rm -rf "$LOCKD" 2>/dev/null || true         # stale (dead or pid recycled) — steal it
  mkdir "$LOCKD" 2>/dev/null || exit 0        # lost the race to another tick — skip
fi
echo $$ > "$LOCKD/pid"; _lstart_of $$ > "$LOCKD/lstart"
trap 'rm -rf "$LOCKD" 2>/dev/null || true' EXIT INT TERM

# ── FIRE CLAIM (closes the pgrep race) ─────────────────────────────────────────────────
# The "already running" guard is `pgrep -f "resume <sid>"` — it looks for the claude CHILD.
# But the spawn chain is launcher → lr-fire-resume.sh → expect → claude: for the seconds
# that chain takes (longer on a loaded box), NO process carries `--resume <sid>` yet, so a
# following tick sees "not running" and fires a second one. The claim is written BEFORE the
# spawn, so the sid is reserved for the whole chain, not just once the child exists.
# TTL-bounded (15 min ≈ 1.5 ticks): a spawn that genuinely failed must not wedge the session
# out of recovery forever.
CLAIM_TTL_MIN="${LR_CLAIM_TTL_MIN:-15}"
sid_claimed() { # $1=sid -> 0 if a FRESH claim exists
  local c="$CLAIMS/$1"
  [[ -f "$c" ]] || return 1
  if [[ -n $(find "$c" -mmin "+$CLAIM_TTL_MIN" 2>/dev/null) ]]; then
    rm -f "$c" 2>/dev/null || true; return 1   # expired — reclaimable
  fi
  return 0
}
claim_sid() { : > "$CLAIMS/${1:?claim_sid needs a sid}" 2>/dev/null || true; }
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
# shellcheck source=/dev/null
for _CC_AM in "${CC_ACCOUNT_MAP:-}" "$(dirname "$0")/../../lib/account-map.generated.sh" "$HOME/.claude/lib/account-map.generated.sh"; do
  [ -n "$_CC_AM" ] && [ -f "$_CC_AM" ] && { source "$_CC_AM"; break; }
done
acct_of_cfg() { cc_acct_name_for_dir_basename "${1##*/}"; }

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

# ── per-uid temp dir (CWE-377/CWE-59) ──────────────────────────────────────────────────
# The launcher below is written, chmod +x'd and then executed BY PATH from another process, so it
# must live where no other uid can pre-create its name. /tmp is mode 1777: the sticky bit stops
# another uid replacing a file we already own, but NOT pre-creating a name that does not exist yet
# — a planted symlink turns the `>` into an arbitrary-file clobber plus a chmod +x on the target.
#
# NOT `${TMPDIR:-/tmp}` on its own. MEASURED 2026-07-30: launchd does not inject TMPDIR into
# LaunchAgent jobs (14 of 15 sampled user agents had it ABSENT; `launchctl getenv TMPDIR` is
# empty), and this poller's whole production role IS a LaunchAgent — so that fallback would land
# right back in the 1777 /tmp in the one context that matters, and the fix would read as applied
# while being inert. `getconf DARWIN_USER_TEMP_DIR` reads the per-uid dir from confstr rather than
# the environment (verified under `env -i`), so it survives an empty env. Last resort stays /tmp:
# a launcher we cannot place securely is still better than no resume at all.
lrp_tmpdir() {
  local d="${TMPDIR:-}"
  [ -n "$d" ] || d="$(getconf DARWIN_USER_TEMP_DIR 2>/dev/null || true)"
  { [ -n "$d" ] && [ -d "$d" ] && [ -w "$d" ]; } || d="/tmp"
  printf '%s' "${d%/}"
}

# ── headless-capable resume spawn (P0-8) ───────────────────────────────────────────────
SPAWN_MECH="${LR_POLLER_SPAWN:-auto}"
# spawn_gui <launcher> — open a terminal window (kitty when we are in kitty, else iTerm2; either way
# an Aqua session is required). 0 = opened.
# ⚠️ NEVER `create window with default profile command "X"` (incident 2026-07-25): iTerm2 keeps X as
# a SESSION-SCOPED PROFILE OVERRIDE, and ⌘D copies the current session's profile — so every split off
# the spawned window silently re-ran the launcher (concurrent duplicate `claude --resume` of one
# transcript) where the operator expected a plain shell. Create a bare window, then `write text` the
# launcher; `exec` keeps the old lifecycle. Repair pre-fix panes: scripts/iterm-clear-sticky-command.sh
lrp_kitty() { # bounded `kitty @ …` — socket seam kept out of the call site
  if [ -n "${CC_TERM_KITTY_TO:-}" ]; then lrp_bounded "${CC_TERM_KITTY:-kitty}" @ --to "$CC_TERM_KITTY_TO" "$@"
  else lrp_bounded "${CC_TERM_KITTY:-kitty}" @ "$@"; fi
}
spawn_gui() {
  # ── kitty first, when this IS kitty (2026-07-31) ──────────────────────────────────────────────
  # The AppleScript below now refuses correctly inside a kitty fleet (`is running` short-circuit),
  # which means the GUI mechanism degrades to tmux — a DETACHED session the operator never sees.
  # That is the right failure and the wrong outcome: on a box where a terminal is right there, a
  # resume belongs in a visible window. The predicate MIRRORS bin/it2-wrapper:75 exactly, kill
  # switch included, so this poller cannot disagree with handoff-fire.sh / cc-pane about the
  # terminal. Failure still `return 1` → spawn_resume's `auto` falls through to tmux, so LR-m's
  # contract ("GUI unavailable → tmux rather than stranding the resume") is unchanged.
  # The launcher is passed as ARGV to `launch`, not typed into a shell, so none of the iTerm2 arm's
  # write-text quoting applies; and kitty has no profile-override concept, so the 2026-07-25
  # sticky-command incident below has no kitty analogue to re-create.
  if [ -n "${KITTY_WINDOW_ID:-}" ] && [ -z "${IT2_WRAPPER_NO_KITTY:-}" ]; then
    command -v "${CC_TERM_KITTY:-kitty}" >/dev/null 2>&1 || return 1
    lrp_kitty launch --type=os-window -- /bin/bash "$1" >/dev/null 2>&1 || return 1
    return 0
  fi
  command -v osascript >/dev/null 2>&1 || return 1
  # Multi `-e` (not a heredoc) on purpose: the AppleScript stays in ARGV, which is where
  # tests/lr-reset-poller.bats' osascript stub observes the spawn — a heredoc would move it to
  # stdin and silently blind three GUI-spawn assertions (fixture-shape parity).
  # `is running` FIRST, and iTerm2 addressed by bundle id (2026-07-31). "iTerm2" is only the
  # CFBundleName of iTerm.app, so the old NAME lookup resolved solely while iTerm2 was already
  # running; after the kitty migration this poller could hang on an undismissable "Where is iTerm2?"
  # modal every 10 minutes. Failing here is the DESIGNED path, not a regression: spawn_resume's
  # `auto` mechanism falls back to spawn_tmux, which is exactly what LR-m pins ("GUI unavailable →
  # falls back to tmux rather than stranding the resume"). Launching iTerm2 instead would resurrect
  # the app behind the operator on a fleet that deliberately left it.
  lrp_bounded osascript >/dev/null 2>&1 \
    -e 'if not (application id "com.googlecode.iterm2" is running) then error "iTerm2 is not running"' \
    -e 'tell application id "com.googlecode.iterm2"' \
    -e 'set newWin to (create window with default profile)' \
    -e "tell current session of newWin to write text \"exec /bin/bash $1\"" \
    -e 'end tell'
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
  local proj=""
  # The killed session's OWN cwd basename — the packet's subject project, declared by the producer
  # that actually knows it (bin/cc-decide § TWO PRODUCER-DECLARED FIELDS). Without it the fired
  # default was filed against the sweep's launchd host project instead of the work's real home.
  # Guarded: `basename ""` yields ".", and a packet claiming project "." is worse than none.
  [[ -n "$cwd" ]] && proj="$(basename "$cwd" 2>/dev/null || true)"
  local marker="$STATE/spend-packet/$sid"
  mkdir -p "$STATE/spend-packet"
  [[ -f "$marker" ]] && return 0                       # already surfaced — no per-tick spam
  local what deadline id
  what="Session ${sid:0:8} ($acct) hit the monthly spend limit — a billing-plane cap with NO reset time, so it cannot be auto-resumed on the same account. Choose how to continue its work${cwd:+ (cwd: $cwd)}."
  deadline="$(python3 -c "from datetime import datetime,timezone,timedelta;import sys;print((datetime.now(timezone.utc)+timedelta(hours=float(sys.argv[1]))).isoformat(timespec='seconds').replace('+00:00','Z'))" "$SPEND_VETO_HOURS" 2>/dev/null)"
  if [[ -z "$CC_DECIDE_BIN" ]]; then                   # never silent: surface via notify, mark once
    log "ERROR $sid ($acct) — monthly-spend kill but cc-decide unavailable; packet NOT opened (notified)"
    lrp_bounded osascript -e "display notification \"${sid:0:8} ($acct) hit the monthly spend limit — cross-account continuation needed (cc-decide missing).\" with title \"lr-reset-poller\"" >/dev/null 2>&1 || true
    : > "$marker"; return 0
  fi
  id="$("$CC_DECIDE_BIN" open --class B \
        --what "$what" \
        --option "cross-account::resume the work on another Max account (next/next2/next3/next4) with quota headroom — quota-plane isolation" \
        --option "cap-raise::operator raises the monthly spend cap (money-path — operator only)" \
        --option "kimi-hedge::engage the Kimi hedge key (operator key required)" \
        --recommendation "cross-account continuation (quota-plane isolation)" \
        --default "cross-account continuation on another Max account with quota headroom" \
        --default-effect change \
        --project "$proj" \
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
    #
    #    SPEND TEXT IS NOT EVIDENCE — REQUIRE THE ENVELOPE (2026-07-25). A bare text match opened
    #    FALSE class-B packets against two healthy next4 sessions: the limit-recover SKILL
    #    DESCRIPTION itself contains the example string "Teammate @x failed - You've hit your
    #    monthly spend limit", and that description rides in the skill_listing attachment of EVERY
    #    session — so `grep -E "$SPEND_RE"` matches sessions that never hit anything. The transcript
    #    is JSONL (one record per line), so a genuine kill puts the text and "isApiErrorMessage"[[:space:]]*:[[:space:]]*true
    #    on the SAME line; the skill-listing attachment never does. That conjunct is the cheap
    #    structural pre-filter (measured on the 2026-07-25 incident: genuine 3 text lines / 1 with
    #    envelope; both false sessions 1 text line / 0 with envelope). lr-audit then confirms
    #    authoritatively, as the session|weekly branch below already does.
    #    On no confirmation, FALL THROUGH (never `continue`): a short transcript can carry the
    #    skill-listing text in its tail AND a genuine session|weekly kill, and an unconditional
    #    continue here shadowed the auto-resume path for it.
    if printf '%s' "$tail_bytes" | grep -iE "$SPEND_RE" | grep -q '"isApiErrorMessage"[[:space:]]*:[[:space:]]*true'; then
      if head -c 8000 "$tx" 2>/dev/null | grep -q '"agentName"'; then
        if [[ ! -f "$STATE/teammate-skip/$sid" ]]; then
          mkdir -p "$STATE/teammate-skip"; : > "$STATE/teammate-skip/$sid"
          log "SKIP  $sid — teammate session (lead-owned recovery)"
        fi
        continue
      fi
      spend_cwd=$(cwd_of "$tx")
      spend_aj=$(mktemp)
      python3 "$AUDIT" --config-dir "$cfg" --session "$sid" --cwd "${spend_cwd:-$HOME}" \
          --json "$spend_aj" --quiet >/dev/null 2>&1 || true
      spend_ok=$(python3 -c "
import json,sys
try: es=json.load(open(sys.argv[1])).get('limit_events',[])
except Exception: es=[]
print('1' if any(e.get('kind')=='monthly_spend' for e in es) else '')
" "$spend_aj" 2>/dev/null); rm -f "$spend_aj"
      if [[ -n "$spend_ok" ]]; then
        open_spend_packet "$sid" "$acct" "$spend_cwd"
        continue
      fi
      log "SKIP  $sid ($acct) — spend envelope present but lr-audit found no monthly_spend event; falling through"
    fi
    # cheap pre-filter: a genuine limit line near the tail (isApiErrorMessage confirmed by lr-audit).
    # The envelope conjunct is part of the PRE-filter, not just lr-audit's job (2026-07-25): the
    # limit-recover skill description quotes "You've hit your session/weekly limit" verbatim and
    # ships in every session's skill_listing, so the bare text matched universally and paid for an
    # lr-audit subprocess on EVERY session, EVERY tick. lr-audit still rules on the verdict below.
    printf '%s' "$tail_bytes" | grep -E "You've hit your (session|weekly) limit" \
      | grep -q '"isApiErrorMessage"[[:space:]]*:[[:space:]]*true' || continue
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
    # already running, OR a fresh claim from an in-flight spawn chain (see FIRE CLAIM above)
    { pgrep -f "resume $sid" >/dev/null 2>&1 || sid_claimed "$sid"; } && continue
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
# sel_reason <sid> — why lr-select did not select this sid, verbatim from its decision record.
sel_reason() {
  python3 -c "
import json,sys
try: d=json.load(open(sys.argv[1]))
except Exception: sys.exit(0)
for k in ('listed','filtered'):
    for r in d.get(k,[]):
        if r.get('sid')==sys.argv[2]:
            print(r.get('reason','')); sys.exit(0)
" "$STATE/last-selection.json" "$1" 2>/dev/null
}
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
  # Read the record's fields WITHOUT an interpreter in the path. The pre-2026-07-30 form was
  # `eval "$(python3 … json.dumps …)"`, on the assumption that JSON quoting is shell quoting.
  # It is not: json.dumps escapes `"` and `\` but NOT `$` or a backtick, and bash expands BOTH
  # inside the double quotes it emits. `cwd` is a directory NAME, and `proj$(...)` is a legal
  # one on APFS — such a record is also perfectly valid JSON, so it passes the §1 writer
  # (printf '%s' into a JSON string) unmangled and detonated here. This is a LOADED launchd
  # job (com.reso.lr-reset-poller), so the payload ran unattended. NUL-delimited fields cannot
  # collide with any byte a JSON string value may hold, and `read` never interprets content.
  # Fail CLOSED: a short/over-long read (unreadable, malformed, or a value containing a literal
  # NUL) skips the record rather than proceeding with half-assigned fields.
  _fields=()
  while IFS= read -r -d '' _v; do _fields+=("$_v"); done < <(python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
sys.stdout.write("".join(str(d.get(k,""))+"\0" for k in ("sid","acct","cfg","cwd","reset_at_utc")))
' "$pf" 2>/dev/null)
  if (( ${#_fields[@]} != 5 )); then
    log "SKIP  $(basename "$pf") — unreadable or malformed parked record"
    continue
  fi
  sid="${_fields[0]}"; acct="${_fields[1]}"; cfg="${_fields[2]}"
  cwd="${_fields[3]}"; reset_at_utc="${_fields[4]}"
  reset_epoch=$(python3 -c "import sys,calendar,time; from datetime import datetime; print(int(calendar.timegm(datetime.fromisoformat(sys.argv[1].replace('Z','+00:00')).utctimetuple())))" "$reset_at_utc" 2>/dev/null || echo 0)
  (( now < reset_epoch )) && continue                        # reset not reached yet
  { pgrep -f "resume $sid" >/dev/null 2>&1 || sid_claimed "$sid"; } && { mv "$pf" "$RESUMED/$(basename "$pf")" 2>/dev/null; rm -f "$PARKED/$sid.notified"; continue; }
  # Not the winner for its worktree → LIST it and retire THIS limit event. Leaving it parked
  # would just re-elect it next tick once the winner is running (already-running filters the
  # winner out) — sprawl at 10-minute cadence. The session is not lost: resume it explicitly by
  # sid, and a genuinely new limit event re-parks it via the REPARK path above.
  if ! printf '%s\n' "$WINNER_SIDS" | grep -qx "$sid"; then
    # Log the REAL reason, not an assumed one. A non-winner may have lost the per-worktree
    # contest, or may have been filtered outright (no transcript, teammate, cwd gone) — those
    # are different facts and "not the winner" would misattribute them.
    why="$(sel_reason "$sid")"; [[ -n "$why" ]] || why="not selected"
    case "$why" in
      *total-ceiling*)
        # Lost the RUN ceiling, not the per-worktree contest — nothing else covers this worktree,
        # so retiring it would strand a project with no session at all. Leave it PARKED and let the
        # next tick take it: the pre-consolidation CAP semantics, preserved deliberately.
        log "CAP   $sid ($acct) — $why; deferred to next tick"
        continue ;;
      *)
        # Lost the per-worktree contest (a winner IS covering this worktree), or was filtered as
        # unresumable. Retire this limit event; a new one re-parks via the REPARK path above.
        log "LISTED $sid ($acct) — $why; consolidated, resume by sid if wanted"
        mv "$pf" "$RESUMED/$(basename "$pf")" 2>/dev/null; rm -f "$PARKED/$sid.notified"
        continue ;;
    esac
  fi
  if ! account_has_headroom "$acct"; then log "WAIT  $sid — $acct still capped, retry next tick"; continue; fi
  (( fired >= MAX_PER_RUN )) && { log "CAP   per-run resume cap ($MAX_PER_RUN) reached; deferring rest"; break; }
  if [[ "$AUTOFIRE" == "1" && $DRY -eq 0 ]]; then
    # MINT THE UNIQUE NAME FIRST, ADD THE SUFFIX AFTER — the same idiom (and for the same reason)
    # as handoff-fire.sh's WT_DEPS. BSD mktemp substitutes only a TRAILING `XXXXXX`; given
    # `…-XXXXXX.sh` it creates the file named LITERALLY that, so the name carries ZERO entropy and
    # the SECOND mint dies `mkstemp failed … File exists` — and nothing ever removes these, so it
    # stays dead. The `.sh` suffix is kept deliberately: an operator reads this path off a parked
    # pane, and scripts/iterm-clear-sticky-command.sh matches generated launchers by it.
    # ${sid:0:8} stays a READABILITY prefix only — mktemp, not the sid, is the entropy budget.
    launch_dir="${LR_POLLER_LAUNCH_DIR:-$(lrp_tmpdir)}"   # seam: tests redirect off the shared /tmp
    if ! launcher="$(mktemp "$launch_dir/lr-poller-launch-${sid:0:8}-XXXXXX" 2>/dev/null)"; then
      log "ERROR  $sid — could not mint a launcher under $launch_dir; skipping this tick"
      continue
    fi
    mv "$launcher" "$launcher.sh" && launcher="$launcher.sh"
    # %q for EVERY interpolated value — this file is bash SOURCE, so each field is code until
    # it is quoted as data. The pre-2026-07-30 form spent its one %q on the `/limit-recover`
    # CONSTANT and interpolated the three attacker-reachable fields with %s inside literal
    # double quotes, which is exactly backwards: a `cwd` of `proj$(…)` re-expanded when the
    # launcher ran. %q emits a form that re-reads as the original word, so no field can leave
    # its argv slot. (`$LR` is script-derived, not record-derived, but takes %q too — a bare
    # %s there would break on any space in the install path.)
    { echo '#!/bin/bash'; printf 'exec %q %q %q %q --prompt %q\n' \
        "$LR/lr-fire-resume.sh" "$acct" "$cwd" "$sid" "/limit-recover"; } > "$launcher"; chmod +x "$launcher"
    # Claim BEFORE spawning: the claude child does not carry `--resume <sid>` until the
    # launcher→expect→claude chain completes, and until then pgrep cannot see it.
    claim_sid "$sid"
    if mech=$(spawn_resume "$launcher" "$sid"); then
      log "RESUMED $sid on $acct (autofire, $mech) — pane opened"
      mv "$pf" "$RESUMED/$(basename "$pf")"; rm -f "$PARKED/$sid.notified"; fired=$((fired+1))
    else
      rm -f "$CLAIMS/$sid" 2>/dev/null || true   # spawn failed ⇒ release immediately, don't wait out the TTL
      log "ERROR  $sid — resume spawn failed (LR_POLLER_SPAWN=$SPAWN_MECH; no GUI and no tmux)"
    fi
  elif [[ ! -f "$PARKED/$sid.notified" ]]; then    # notify ONCE per parked session (no per-tick spam)
    # The REMEDY must match WHY this branch was reached. Both strings said "Set LR_POLLER_AUTOFIRE=1"
    # unconditionally until 2026-07-30 — but reaching here with AUTOFIRE=1 means --dry-run suppressed
    # the fire, so on the production box (AUTOFIRE=1) that advised setting a variable already set and
    # read as "auto-resume is off" while it was on. Same defect class as the plist/header drift.
    if [[ "$AUTOFIRE" == "1" ]]; then
      mode="dry-run";     hint="autofire IS on; --dry-run suppressed the resume"
    else
      mode="notify-only"; hint="set LR_POLLER_AUTOFIRE=1 to auto-resume"
    fi
    # headless-safe user alert (a LaunchAgent runs in the Aqua session ⇒ notifications work)
    lrp_bounded osascript -e "display notification \"${sid:0:8} ($acct) limit reset — resumable. ${hint}.\" with title \"lr-reset-poller\"" >/dev/null 2>&1 || true
    : > "$PARKED/$sid.notified"
    log "READY $sid on $acct — $mode, notified once ($hint)"
  fi
done
exit 0
