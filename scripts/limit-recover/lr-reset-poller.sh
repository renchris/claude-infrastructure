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

# ---- PANE-SPAWN LOG (item 1467ea1dad4f) --------------------------------------------------------
# A launchd job that spawns GUI windows autonomously every ~10 min is the textbook shape of a pane
# nobody can attribute after the fact — the row's `ancestry` will show the launchd parent, which is
# exactly how the "undocumented detached child" hypothesis gets confirmed or killed.
for _psl in "$(dirname "$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")")/../../scripts/lib/pane-spawn-log.sh" \
            "${CLAUDE_CONFIG_DIR:-${HOME:-}/.claude}/scripts/lib/pane-spawn-log.sh" \
            "${HOME:-}/.claude/scripts/lib/pane-spawn-log.sh"; do
  # shellcheck disable=SC1090  # runtime-resolved source; the ship gate runs shellcheck without -x
  [ -f "$_psl" ] && . "$_psl" 2>/dev/null && break
done
unset _psl

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

# ── tmux gets the SAME absolute ladder, and it took 24 days of a false alarm to notice ────────────
# `spawn_tmux` used to open with a bare `command -v tmux || return 1`. Under launchd that guard is
# always FALSE: com.reso.lr-reset-poller.plist sets no PATH, so the job runs on the stock
# /usr/bin:/bin:/usr/sbin:/sbin, and Homebrew is not on it. MEASURED 2026-08-14 in poller.log —
# 1,797 of 2,211 lines (81%) are the identical `resume spawn failed (…; no GUI and no tmux)` across
# 11 sids over 24 days, one sid retried 380 times — while /opt/homebrew/bin/tmux existed throughout.
# So LR-m's whole contract ("GUI unavailable → tmux rather than stranding the resume") had never
# once been honoured in production, and the line asserting "no tmux" was FALSE about the box.
#
# THE GUARD IS WHAT HID IT, and that is the part to carry forward. A bare `tmux` would have been a
# loud 127; `command -v tmux ||` turns the same PATH blindness into a SILENT capability loss —
# which scripts/unattended-path-lint.sh classifies as exactly its `guarded` finding ("it will not
# crash, but the capability is silently lost, which for a gate or an actuator is failing OPEN").
# That lint never reported this file, and the reason is a DIRECTORY: its launchd population is
# `"$root"/launchd/*.plist`, while this job's plist is committed at
# scripts/limit-recover/com.reso.lr-reset-poller.plist — tracked, live-loaded, and outside the set
# the lint enumerates. So the population, not the rule, is what let this through.
#
# Resolution order mirrors LRP_TIMEOUT_BIN three lines up — the idiom was already in this file,
# applied to `timeout` and not to `tmux` (memory: corrected-instrument-can-lie-again). CANDIDATES is
# a seam because a test cannot create /opt/homebrew/bin; set-but-EMPTY means "no candidates", never
# the default (`${VAR+set}`, the convention LRP_OSA_TIMEOUT_BIN documents above).
if [ -n "${LR_POLLER_TMUX_CANDIDATES+set}" ]; then
  _lrp_tmux_cands="$LR_POLLER_TMUX_CANDIDATES"
else
  _lrp_tmux_cands="/opt/homebrew/bin/tmux:/usr/local/bin/tmux"
fi
LRP_TMUX_BIN="$(command -v tmux 2>/dev/null || true)"
if [ -z "$LRP_TMUX_BIN" ] || [ ! -x "$LRP_TMUX_BIN" ]; then
  LRP_TMUX_BIN=""
  _lrp_oifs="$IFS"; IFS=':'
  # shellcheck disable=SC2086  # deliberate IFS=':' split — CANDIDATES is a colon list, like PATH
  for _c in $_lrp_tmux_cands; do
    [ -n "$_c" ] && [ -x "$_c" ] && { LRP_TMUX_BIN="$_c"; break; }
  done
  IFS="$_lrp_oifs"
fi


[[ -n "${LR_POLLER_DISABLED:-}" ]] && exit 0

LR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUDIT="$LR/lr-audit.py"
# THE PREDICATE (LIMIT_DETECT_100P W4 step 2). Four copies of "is this a limit, and which cap" used
# to live in this file; they disagreed with lr-audit and with each other, and the poller's copy was
# the one blind to every model-scoped cap. One fork per CANDIDATE, never per transcript — the cheap
# greps below stay exactly because this costs 0.09 s and the scan walks hundreds of files.
LRPRED="$LR/lr-predicate.sh"
STATE="$HOME/.reso/limit-recover"
PARKED="$STATE/parked"; RESUMED="$STATE/resumed"; LOG="$STATE/poller.log"
# DEFINED HERE, not beside its other callers 160 lines below: the tick lock is the FIRST thing that
# needs to say something, and a `log` that is not yet a function there is a silent skip.
log() { printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >> "$LOG"; }
CLAIMS="$STATE/fire-claims"
# The audit's once-per-fire damping marker dir. Declared HERE rather than beside the audit block
# below because claim_sid() re-arms it (see there), and a fire-lifecycle helper must not depend on
# a variable that is only assigned further down the file.
ENGAGE_NOTED="$STATE/engage-noted"
FIRE_FAIL="$STATE/fire-fail"
mkdir -p "$PARKED" "$RESUMED" "$CLAIMS"
# ── lr-lib.sh — the shared predicates (LIMIT_RECOVER_100P, 2026-09-09) ─────────────────────────
# Liveness by REGISTRY (not argv), the transplant read, the transcript tier and the engagement oracle
# all live there, shared with lr-handoff.sh and lr-fleet.sh. FAIL CLOSED for the arms that need it:
# a poller that cannot tell whether the original pane is alive must not spawn (that is the 2026-09-09
# same-account duplicate), so a missing lib disables the RESUME arm and says so.
# _LRP_SELF must be assigned HERE, before its first read below. It used to be assigned only at the
# engagement-lib block further down, so this loop read it unset. Under `set -u` that kills only the
# `$(dirname …)` SUBSHELL, not the tick: every run printed "_LRP_SELF: unbound variable" to
# poller.launchd.err (160 lines from 59e415e12 to 2026-09-10) and silently lost rung 1, the
# symlink-resolved sibling, falling through to $LR and the live layer. The daemon kept exiting 0.
_LRP_SELF="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")"
LRP_LIB=""
for _lrp_lib in "$(dirname "$_LRP_SELF")/lr-lib.sh" "$LR/lr-lib.sh" "${HOME:-}/.claude/scripts/limit-recover/lr-lib.sh"; do
  [[ -f "$_lrp_lib" ]] && { LRP_LIB="$_lrp_lib"; break; }
done
if [[ -n "$LRP_LIB" ]]; then
  LR_LIB_DIR="$(cd "$(dirname "$LRP_LIB")" && pwd)"; export LR_LIB_DIR
  # shellcheck source=lr-lib.sh
  # shellcheck disable=SC1091
  . "$LRP_LIB"
fi
# ── lr-recon-fence.sh — one actuator family per session (LIMIT_RECOVER_FLEET_V2 W4, § C10) ──────
# The reconciler daemon and this poller can both type into one pane. Every arm below that touches a
# sid asks lrp_may_act first; a sid the reconciler owns is DEFERRED (left exactly as it is) rather
# than driven twice. The fence reads $LR_STATE_DIR, so it is pointed at THIS daemon's state tree
# when nothing else has set it — the recon.on it tests must be the one beside our requests/.
# UNREACHABLE FENCE ⇒ ACT AS BEFORE: the reconciler is opt-in, and a missing file must not stop
# the legacy recovery lane; it is said once per tick so the gap is visible.
[[ -n "${LR_STATE_DIR:-}" ]] || LR_STATE_DIR="$STATE"
LRP_FENCE=0
for _lrp_f in "$(dirname "$_LRP_SELF")/lr-recon-fence.sh" "$LR/lr-recon-fence.sh" "${HOME:-}/.claude/scripts/limit-recover/lr-recon-fence.sh"; do
  # shellcheck source=lr-recon-fence.sh
  # shellcheck disable=SC1091
  [[ -f "$_lrp_f" ]] && . "$_lrp_f" && declare -F lr_recon_may_act >/dev/null 2>&1 && { LRP_FENCE=1; break; }
done
lrp_may_act() { # $1=sid $2=arm → 0 ACT (pair with lrp_act_done on every exit path) · 1 DEFER (logged)
  (( LRP_FENCE )) || return 0
  lr_recon_may_act "$1" "poller-$2" 2>>"$LOG" && return 0
  log "RECON-DEFER $2 $1"
  return 1
}
lrp_act_done() { (( LRP_FENCE )) || return 0; lr_recon_act_done; }
REQUESTS="$STATE/requests"; RESULTS="$STATE/results"
# CLAIMED and RUN_CLAIMS are the request lane's two new stores (W5-A, 2026-09-20), created HERE
# beside the other two because the loop that uses them must never be the thing that decides whether
# they exist: a `mkdir` folded into the consuming branch is a store that appears only on the happy
# path, and its absence then reads as "nothing was ever claimed".
#   CLAIMED     a drained request, MOVED not deleted — the evidence that it reached this daemon
#   RUN_CLAIMS  <sid>.active, one atomic `mkdir` per in-flight run — the reservation `: >` is not
CLAIMED="$STATE/claimed"; RUN_CLAIMS="$STATE/runs/by-sid"
mkdir -p "$REQUESTS" "$RESULTS" "$CLAIMED" "$RUN_CLAIMS"
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
    # A SKIP SAYS SO. This branch exited silently, so a poller.log with a gap in it could not be
    # told from one whose ticks never fired at all — and those want opposite responses (a held
    # lock is the guard WORKING; an absent tick is a dead LaunchAgent).
    mkdir -p "$STATE" 2>/dev/null || true
    log "TICK-SKIP held by pid $_hp"
    exit 0                                   # a genuine live tick holds it — skip this one
  fi
  rm -rf "$LOCKD" 2>/dev/null || true         # stale (dead or pid recycled) — steal it
  mkdir "$LOCKD" 2>/dev/null || exit 0        # lost the race to another tick — skip
fi
echo $$ > "$LOCKD/pid"; _lstart_of $$ > "$LOCKD/lstart"
trap 'rm -rf "$LOCKD" 2>/dev/null || true' EXIT INT TERM
mkdir -p "$STATE" 2>/dev/null || true
log "TICK start"        # the denominator: without it no rate, gap or duty cycle is computable
(( LRP_FENCE )) || log "RECON-FENCE-MISSING lr-recon-fence.sh unreachable — every arm acts as before (legacy)"

# ── THE RECONCILER BACKUP WATCHDOG (LIMIT_RECOVER_FLEET_V2 § C9) ──────────────────────────────────
# With recon.on the operator has handed recovery to the reconciler, and every sid it owns is fenced
# off from this daemon — so a reconciler that died silently leaves those sessions with NO actuator.
# This tick is the independent observer: recon.on present and no fresh heartbeat ⇒ page (at most
# once per 15 min, stamped on STATE, never on a log grep) and kick the job. Bare `kickstart`, never
# `-k`: `-k` kills a running instance, and a reconciler that is alive but slow is exactly the one a
# kill would turn into a dead one. recon.on absent ⇒ nothing at all.
lrp_recon_watchdog() {
  local stamp="$STATE/recon-backup.page" lc="${LR_LAUNCHCTL_BIN:-/bin/launchctl}"
  (( LRP_FENCE )) || return 0
  [[ -e "$LR_STATE_DIR/recon.on" ]] || return 0
  lr_recon_live && return 0
  if [[ $DRY -eq 1 ]]; then log "DRY   recon backup: reconciler heartbeat stale; would page and kickstart"; return 0; fi
  if [[ ! -e "$stamp" ]] || [[ -n "$(find "$stamp" -mmin +"${LR_RECON_BACKUP_PAGE_MIN:-15}" 2>/dev/null)" ]]; then
    : > "$stamp" 2>/dev/null || true
    log "PAGE  recon backup — recon.on is set but the reconciler heartbeat is stale; kickstarting com.reso.lr-reconciler"
    lrp_bounded osascript -e "display notification \"reconciler heartbeat stale — kickstarted; sessions it owns have no actuator until it returns\" with title \"lr-reset-poller\"" >/dev/null 2>&1 || true
  fi
  lrp_bounded "$lc" kickstart "gui/$(id -u)/com.reso.lr-reconciler" >/dev/null 2>>"$LOG" \
    || log "RECON-BACKUP kickstart rc=$? (logged, tick continues)"
  return 0
}
lrp_recon_watchdog

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
claim_sid() {
  : > "$CLAIMS/${1:?claim_sid needs a sid}" 2>/dev/null || true
  # RE-ARM THE AUDIT'S ONCE-PER-FIRE DAMPING. The marker below means "the verdict for the CURRENT
  # claim has been reported", and a new claim is a new fire with a new verdict to reach. Without
  # this the SECOND wedge of a sid is silent forever — the first one spent the marker, and the
  # marker was only ever cleared by an engagement that, for a session that keeps wedging, never
  # comes. That also made the fire-fail counter below uncountable past 1 on the wedge path.
  rm -f "$ENGAGE_NOTED/$1" 2>/dev/null || true
}

# ── FIRE-FAILURE LATCH — the actuator half of the engagement audit (backlog ff0b5cf4528b) ───────
#
# THE DEFERRED DECISION, MADE. 4ba91ad95 shipped the audit below DETECT-ONLY and said why: "adding
# an actuator to a live unattended limit-recovery daemon is a different decision with a different
# blast radius." The measurement that settles the DIRECTION is this daemon's own log: 1,800 of its
# lines are one identical `ERROR … resume spawn failed`, across 11 sids over 24 days, one sid
# retried 380 times — because a failed spawn releases its claim immediately (see §2) and is
# re-fired on the very next tick, without bound. So the defect was never "a fire that did not work
# is not RETRIED"; it is "a fire that cannot work is retried forever". The only safe actuator is
# therefore the one that fires LESS, never the one that fires sooner.
#
# ONE COUNTER, BOTH FAILURE MODES, because they are one fact — this sid's fire did not produce a
# working session:
#   · spawn_resume returned non-zero           → no pane at all            (the 1,800-line class)
#   · spawned, and the audit says NOT-ENGAGED  → a pane that never started (the wedge class)
# An engaged sid CLEARS the counter, so a session that works is never latched by its own history,
# and the count means CONSECUTIVE failures rather than lifetime ones.
#
# A BRAKE, NOT A BAN. At LR_FIRE_FAIL_MAX the sid stops being a candidate for LR_FIRE_LATCH_HOURS
# and the daemon says so ONCE (log + notify); the latch then expires and it competes again. Worst
# case is that ONE session is not auto-resumed for a few hours — the pre-autofire notify-only
# posture, time-bounded and loudly reported — weighed against an unbounded spawn loop. This arm
# cannot make the daemon fire MORE, cannot touch a claim, and cannot reach another sid.
LR_FIRE_FAIL_MAX="${LR_FIRE_FAIL_MAX:-3}"
LR_FIRE_LATCH_HOURS="${LR_FIRE_LATCH_HOURS:-6}"
# Fail back to the defaults on junk rather than letting an unattended daemon do arithmetic on it:
# a non-numeric max makes every `(( ))` below an error, and 0 would suppress every sid silently.
[[ "$LR_FIRE_FAIL_MAX"     =~ ^[1-9][0-9]*$ ]] || LR_FIRE_FAIL_MAX=3
[[ "$LR_FIRE_LATCH_HOURS"  =~ ^[1-9][0-9]*$ ]] || LR_FIRE_LATCH_HOURS=6
mkdir -p "$FIRE_FAIL"

fire_fail_count() { # $1=sid -> the consecutive-failure count (0 when absent, empty or malformed)
  local n=""
  [[ -r "$FIRE_FAIL/${1:?}" ]] && read -r n < "$FIRE_FAIL/$1"
  [[ "$n" =~ ^[0-9]+$ ]] || n=0
  printf '%s' "$n"
}
fire_fail_note() { # $1=sid $2=why — count ONE failed fire; report at the crossing, never per tick
  local sid="${1:?}" why="${2:-unknown}" n
  n=$(( $(fire_fail_count "$sid") + 1 ))
  printf '%s\n' "$n" > "$FIRE_FAIL/$sid" 2>/dev/null || return 0
  (( n == LR_FIRE_FAIL_MAX )) || return 0
  log "LATCHED $sid — $n consecutive fires produced no working session (last: $why); not a candidate for ${LR_FIRE_LATCH_HOURS}h"
  # A LEAD WITH LIVE MEMBERS IS PAGED (D4.8). The banner is this latch's only signal, and for a held
  # lead the latch is the moment its only wake has failed three times — a person has to look.
  if command -v lrp_held_lead >/dev/null 2>&1 && lrp_held_lead "$sid"; then
    lrp_page "held lead" "Team lead ${sid:0:8} was not woken after its limit reset ($n attempts, last: $why). It holds live teammates, so it is never moved or re-spawned; wake it by hand."
    return 0
  fi
  lrp_bounded osascript -e "display notification \"${sid:0:8} — $n resumes produced no working session; auto-resume paused ${LR_FIRE_LATCH_HOURS}h.\" with title \"lr-reset-poller\"" >/dev/null 2>&1 || true
}
fire_fail_clear() { rm -f "$FIRE_FAIL/${1:?}" 2>/dev/null || true; }
fire_latched() { # $1=sid -> 0 while this sid is suppressed; EXPIRES the latch in passing
  local sid="${1:?}" f="$FIRE_FAIL/${1:?}"
  [[ -f "$f" ]] || return 1
  (( $(fire_fail_count "$sid") >= LR_FIRE_FAIL_MAX )) || return 1
  # The window runs from the LAST failure, not the first: every note rewrites this file, so its
  # mtime is the freshest failure. Expiry clears the counter here rather than in a sweep — a second
  # caller in the same tick then finds no file and answers 1 without logging UNLATCHED twice.
  if [[ -z $(find "$f" -mmin "-$(( LR_FIRE_LATCH_HOURS * 60 ))" 2>/dev/null) ]]; then
    rm -f "$f" 2>/dev/null || true
    log "UNLATCHED $sid — ${LR_FIRE_LATCH_HOURS}h latch expired; eligible to fire again"
    # A held lead's latch expiring PAGES and never leads to a spawn (D4.8 — 3c73a9d9 was resumed into
    # a new pane at 18:42:24Z on 2026-09-29, 2 h 17 min after it had recovered by itself).
    if command -v lrp_held_lead >/dev/null 2>&1 && lrp_held_lead "$sid"; then
      lrp_page "held lead" "Team lead ${sid:0:8}: its ${LR_FIRE_LATCH_HOURS}h wake latch expired. It is never re-spawned; the next tick tries one in-place wake only."
    fi
    return 1
  fi
  return 0
}
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

# shellcheck source=/dev/null
# PRESENT IS NOT USABLE. The old loop broke on the first file that EXISTED, so a truncated or
# half-written map — `gen-account-map.sh` wrote its output in place, so a crash mid-write left
# exactly that — satisfied the ladder, shadowed the two good candidates below it, and left
# `cc_acct_name_for_dir_basename` undefined. Every `acct_of_cfg` then failed under `set -u`-ish
# conditions or returned empty, and `[[ -n "$acct" ]] || continue` silently skipped EVERY store:
# a tick that detected nothing, parked nothing and logged nothing wrong. Require the FUNCTION.
for _CC_AM in "${CC_ACCOUNT_MAP:-}" "$(dirname "$0")/../../lib/account-map.generated.sh" "$HOME/.claude/lib/account-map.generated.sh"; do
  [ -n "$_CC_AM" ] && [ -f "$_CC_AM" ] && source "$_CC_AM" 2>/dev/null \
    && declare -F cc_acct_name_for_dir_basename >/dev/null 2>&1 && break
done
if ! declare -F cc_acct_name_for_dir_basename >/dev/null 2>&1; then
  log "FATAL account map unusable — no candidate defined cc_acct_name_for_dir_basename; refusing a tick that would skip every store in silence"
  exit 1
fi
acct_of_cfg() { cc_acct_name_for_dir_basename "${1##*/}"; }

# ── ENGAGEMENT AUDIT — did the sessions this daemon fired actually START? (DETECT-ONLY) ─────────
# THE GAP THIS CLOSES. §2 below claims a sid, spawns, logs `RESUMED … pane opened` and moves on.
# "Pane opened" is the only thing it ever verifies. A resume that opened a pane and then wedged on a
# blocking startup modal is indistinguishable from a healthy one — SessionStart never fires behind a
# dialog, so no session row and no transcript are ever written, and every ordinary liveness probe on
# this box answers "fine" (docs/research/cc-startup-modals-2026-08-04.md §3). The claim then expires
# on a pure wall-clock TTL (CLAIM_TTL_MIN above) and the sid is silently re-fired, with no record
# anywhere that the FIRST fire never engaged. hooks/lib/engagement.sh exists for exactly that class.
#
# WHY IT IS WIRED HERE AND NOWHERE ELSE IN limit-recover (measured 2026-08-12, backlog f76e7d78aaac).
# The filed remedy named lr-fire-resume.sh and scripts/cc-upgrade-gate.sh; both are refuted.
# lr-fire-resume.sh `exec expect`s at :385, so the spawning process BECOMES the session and there is
# no "after the spawn" left to check from. cc-upgrade-gate.sh spawns no pane at all (every probe is
# `--print --output-format json`). This poller is the one component that both spawns AND survives
# its spawns — and it holds a SID, never a pane id, which is why `cc_engaged_sid` exists.
#
# DETECT AND REPORT ONLY — deliberately. This arm does not re-fire, does not release or extend the
# claim and does not touch the fire decision. Adding an actuator to a live unattended
# limit-recovery daemon (LR_POLLER_AUTOFIRE=1 in the shipped plist) is a different decision with a
# different blast radius. What this produces is the record whose absence is the defect.
#
# IT RUNS BEFORE §1b's fail-closed `exit 0`, on purpose: a missing lr-select must stop FIRING, but
# it says nothing about fires already made, and an audit gated behind an unrelated precondition goes
# quiet exactly when the daemon is already degraded.
#
# FAIL-OPEN, unlike bin/cc-wedge-watch, which exits 4 when this lib is missing. Judging engagement
# IS that tool's whole job; this daemon's job is RECOVERING SESSIONS, and it must not stop
# recovering because a library moved. Same three-rung resolution ladder (bin/cc-wedge-watch:136-142)
# — symlink-resolved sibling, plain sibling, live layer — with the opposite failure direction.
LR_ENGAGE_SETTLE_MIN="${LR_ENGAGE_SETTLE_MIN:-3}"
# ENGAGE_NOTED is declared with CLAIMS at the top — claim_sid() re-arms it on every new fire.
LRP_ENGAGE_MISSING="$STATE/engage-lib-missing.notified"
LRP_ENGAGE_LIB=0
_LRP_SELF="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")"
# shellcheck source=../../hooks/lib/engagement.sh
for _elb in "$(dirname "$_LRP_SELF")/../../hooks/lib/engagement.sh" \
            "$LR/../../hooks/lib/engagement.sh" \
            "${HOME:-}/.claude/hooks/lib/engagement.sh"; do
  # shellcheck disable=SC1090,SC1091  # runtime-resolved source; the ship gate runs shellcheck without -x
  [ -r "$_elb" ] && . "$_elb" 2>/dev/null && { LRP_ENGAGE_LIB=1; break; }
done
# RUN AFTER THE REQUEST DRAIN, NOT HERE (LIMIT_RECOVER_FLEET_V2 W6, D1.5). It used to run inline at
# this point, on every claim ever written: ENGAGED claims are never deleted (the only `rm` is §2's
# failed-spawn release), so by 2026-09-29 it re-judged 25 claims dated Aug 4 to Sep 22 and one
# sampled tick spent ~600 of its 602 s here BEFORE the first request was read; tonight's measured
# death-to-dispatch ran 4m50s-8m31s. A request is a live session waiting; an audit of an old fire is
# a report. The call below the drain still precedes §1b and the fire_latched readers (the candidacy
# filter and reroute_parked), which are what its strikes feed. A claim older than
# LR_ENGAGE_MAX_AGE_MIN (default 360 = 6 h, the latch window its strike would feed) is skipped.
LR_ENGAGE_MAX_AGE_MIN="${LR_ENGAGE_MAX_AGE_MIN:-360}"
[[ "$LR_ENGAGE_MAX_AGE_MIN" =~ ^[1-9][0-9]*$ ]] || LR_ENGAGE_MAX_AGE_MIN=360
lrp_engagement_audit() {
  local cf esid
  if [[ "$LRP_ENGAGE_LIB" != 1 ]] || ! command -v cc_engaged_sid >/dev/null 2>&1; then
    # Log ONCE, then stay quiet: this runs every ~10 min forever, and a per-tick line would bury the
    # very records this audit exists to write. The marker is cleared the moment the lib resolves
    # again, so a LATER outage is a fresh line rather than a silence inherited from the first one.
    if [[ ! -f "$LRP_ENGAGE_MISSING" ]]; then
      : > "$LRP_ENGAGE_MISSING"
      log "ENGAGE-SKIP hooks/lib/engagement.sh unavailable — engagement audit off (recovery UNAFFECTED)"
    fi
  else
    rm -f "$LRP_ENGAGE_MISSING" 2>/dev/null || true
    mkdir -p "$ENGAGE_NOTED"
    for cf in "$CLAIMS"/*; do
      [[ -e "$cf" ]] || continue
      esid="$(basename "$cf")"
      # THE SETTLE WINDOW IS LOAD-BEARING. A claim is written BEFORE the launcher→expect→claude chain
      # even starts, so a just-claimed sid has no transcript and no assistant turn BY CONSTRUCTION —
      # asking immediately would report every healthy fire as not-engaged. Wall-clock, like the TTL
      # beside it, and shorter than it so a fire is judged while its claim is still live.
      [[ -n $(find "$cf" -mmin "+$LR_ENGAGE_SETTLE_MIN" 2>/dev/null) ]] || continue
      # PAST THE AGE CAP ⇒ NOT JUDGED (D1.5): its strike would land after the latch it feeds expired.
      [[ -n $(find "$cf" -mmin "+$LR_ENGAGE_MAX_AGE_MIN" 2>/dev/null) ]] && continue
      if cc_engaged_sid "$esid"; then
        # Re-arm: this sid engaged, so a FUTURE fire of the same session that wedges must still be
        # able to report. A marker that is never cleared silences the second incident on any session
        # that ever succeeded once.
        rm -f "$ENGAGE_NOTED/$esid" 2>/dev/null || true
        fire_fail_clear "$esid"   # a session that STARTED carries no failure history into its next fire
        continue
      fi
      [[ -f "$ENGAGE_NOTED/$esid" ]] && continue     # notify ONCE per claim (no per-tick spam)
      # --dry-run REPORTS but must never CLAIM the one report. Writing the damping marker under a
      # preview flag would let an operator's look-first silence the real tick 10 minutes later — the
      # same class as the --dry-run defect this file already carries a header about.
      # The fire-fail count rides the SAME guard, and for the same reason: a preview must not spend a
      # strike either. Both are once-per-fire because claim_sid() re-arms the marker.
      if (( DRY == 0 )); then : > "$ENGAGE_NOTED/$esid"; fire_fail_note "$esid" not-engaged; fi
      log "NOT-ENGAGED $esid — claimed >${LR_ENGAGE_SETTLE_MIN}m ago, no assistant turn (why=${CC_ENGAGE_WHY:-unknown}); claim untouched, counted toward the fire latch"
    done
  fi
}

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
# VERIFIED TYPING (backlog item 270106134cc8). spawn_gui below types a command into a brand-new
# pane. It used to blind-send it with a single `write text`, surviving only because `exec` happens
# to be a shell builtin — a property nothing pinned. Under `setopt CORRECT` an unrecognised command
# word parks the pane on `zsh: correct … [nyae]?`, and THIS poller fires UNATTENDED from a
# LaunchAgent, so there is nobody to answer it. Resolution ladder: beside-script → CFG → ~/.claude.
_cctv="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/../lib/cc-type-verified.sh"
[ -f "$_cctv" ] || _cctv="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/scripts/lib/cc-type-verified.sh"
[ -f "$_cctv" ] || _cctv="$HOME/.claude/scripts/lib/cc-type-verified.sh"
# shellcheck source=../lib/cc-type-verified.sh
# shellcheck disable=SC1091  # runtime-resolved source; the ship gate runs shellcheck without -x
if . "$_cctv" 2>/dev/null; then LRP_TYPE_VERIFIED=1; else LRP_TYPE_VERIFIED=0; fi

SPAWN_MECH="${LR_POLLER_SPAWN:-auto}"
# Resolve the kitty binary ABSOLUTELY. Hooks and launchd jobs run with a minimal PATH that excludes
# Homebrew, so a bare `kitty` does not exist for exactly the AUTOMATED callers this file serves —
# green where a human tests it, dead where it runs. That is what left a teammate pane open for 3h09m
# with its 653 MB claude.exe resident on 2026-08-01 (full account: bin/cc-kitty-bin header).
# Falling back to the previous spelling keeps a partial deploy degraded rather than broken.
CC_KITTY_BIN="${CC_TERM_KITTY:-kitty}"
# Candidate order matters: the SYMLINK-RESOLVED sibling first. ~/.claude/scripts/*.sh are symlinks
# into this checkout, so `dirname "$0"/../bin` alone points at ~/.claude/bin — which only holds
# cc-kitty-bin AFTER install.sh runs. Resolving the link first finds the repo's own bin/ and makes
# the fix live the moment the file does, instead of waiting on a deploy it cannot trigger.
# ${HOME:-} DELIBERATELY: bash expands the ENTIRE for-list before the loop body runs, so a bare
# $HOME under `set -u` aborts this whole script on the third candidate even when the FIRST one
# resolves. With :- it degrades to a nonexistent path `[ -x ]` rejects. See bin/kitty-split-launch.sh.
_CC_KS="$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")"
for _CC_KB in "$(dirname "$_CC_KS")/../../bin/cc-kitty-bin" "$(dirname "$0")/../../bin/cc-kitty-bin" "${HOME:-}/.claude/bin/cc-kitty-bin"; do
  [ -x "$_CC_KB" ] || continue
  _CC_KR="$("$_CC_KB" 2>/dev/null)" && [ -n "$_CC_KR" ] && { CC_KITTY_BIN="$_CC_KR"; break; }
done
# NOTE the ${CC_KITTY_BIN:-…} fallback at every call site below. These functions are EXTRACTED
# INDIVIDUALLY with sed by tests/*.bats ("NOTHING HERE EXECUTES scripts/handoff-fire.sh"), so a
# function that depends on a top-level variable is unset in every extracted-function test — measured
# 2026-08-01, it turned `it2py bgtab` red. Each call site therefore re-states the pre-resolution
# spelling as its own default: production gets the absolute path from the block above, an extracted
# function degrades to exactly the behaviour it had before this change.

# spawn_gui <launcher> — open a terminal window (kitty when we are in kitty, else iTerm2; either way
# an Aqua session is required). 0 = opened.
# ⚠️ NEVER `create window with default profile command "X"` (incident 2026-07-25): iTerm2 keeps X as
# a SESSION-SCOPED PROFILE OVERRIDE, and ⌘D copies the current session's profile — so every split off
# the spawned window silently re-ran the launcher (concurrent duplicate `claude --resume` of one
# transcript) where the operator expected a plain shell. Create a bare window, then `write text` the
# launcher; `exec` keeps the old lifecycle. Repair pre-fix panes: scripts/iterm-clear-sticky-command.sh
# (lrp_kitty lived here until 2026-09-09. spawn_gui's kitty arm moved to lr-lib.sh's
# lr_kitty_spawn — the launchd-safe, socket-resolved, runner-rooted spawn — and left it with no
# caller in this file or any other. Deleted rather than kept: a helper whose only remaining reader
# was a test's `eval "$(sed -n '/^lrp_kitty() {/,/^}/p')"` extraction is dead code with a witness.)
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
  # DAEMON-CONTEXT DISPATCH (LIMIT_RECOVER_100P, 2026-09-09). A launchd job has no $KITTY_WINDOW_ID,
  # so this arm never fired for the fleet's own terminal and `auto` fell through to tmux — seven
  # invisible lr-resume-* sessions, one frozen on a permission prompt nobody could see. bin/cc-kitty-
  # socket proves a LIVE kitty from any context (the same seam lr-handoff.sh took on 2026-08-07), and
  # lr_kitty_spawn launches the window RUNNER-ROOTED (bin/cc-pane-runner: the launcher rides in
  # CC_PANE_CMD, the window survives a refusal with the message on screen, the pane is recyclable).
  if [ -z "${IT2_WRAPPER_NO_KITTY:-}" ] && command -v lr_kitty_spawn >/dev/null 2>&1; then
    local _sock="" _id=""
    _sock="$(lr_kitty_socket 2>/dev/null || true)"
    if [ -n "${KITTY_WINDOW_ID:-}" ] || [ -n "$_sock" ]; then
      command -v "${CC_KITTY_BIN:-${CC_TERM_KITTY:-kitty}}" >/dev/null 2>&1 || return 1
      _id="$(CC_TERM_KITTY_TO="${_sock:-${CC_TERM_KITTY_TO:-}}" CC_TERM_KITTY="${CC_KITTY_BIN:-${CC_TERM_KITTY:-kitty}}" \
             lr_kitty_spawn "$1" "${3:-${PWD:-}}" "${2:-}" "${4:-}")" || return 1
      # (no cc_log_pane_spawn row here: lr_kitty_spawn writes it at the primitive, 2026-09-09.)
      return 0
    fi
  fi
  command -v osascript >/dev/null 2>&1 || return 1
  # No verified-typing helper ⇒ REFUSE the GUI path rather than fall back to a blind send. Under
  # `auto` this drops through to spawn_tmux, which types nothing at all, so the resume still
  # happens — just headless. A degraded resume beats a pane wedged on an unanswerable prompt.
  [ "${LRP_TYPE_VERIFIED:-0}" = 1 ] || {
    echo "lr-reset-poller: verified typing unavailable — skipping GUI spawn (tmux still eligible)" >&2
    return 1
  }
  # Multi `-e` (not a heredoc) on purpose: the AppleScript stays in ARGV, which is where
  # tests/lr-reset-poller.bats' osascript stub observes the spawn — a heredoc would move it to
  # stdin and silently blind three GUI-spawn assertions (fixture-shape parity).
  #
  # CREATE ONLY, then type through osa_type_verified. `write text` appends the newline itself, so a
  # combined call EXECUTES the line before anything can confirm it arrived intact; splitting the two
  # is what makes the echo-verify possible, and `id of` is what lets the helper address this pane.
  #
  # `is running` FIRST, and iTerm2 addressed by bundle id (2026-07-31). "iTerm2" is only the
  # CFBundleName of iTerm.app, so the old NAME lookup resolved solely while iTerm2 was already
  # running; after the kitty migration this poller could hang on an undismissable "Where is iTerm2?"
  # modal every 10 minutes. Failing here is the DESIGNED path, not a regression: spawn_resume's
  # `auto` mechanism falls back to spawn_tmux, which is exactly what LR-m pins ("GUI unavailable →
  # falls back to tmux rather than stranding the resume"). Launching iTerm2 instead would resurrect
  # the app behind the operator on a fleet that deliberately left it.
  command -v cc_log_pane_spawn >/dev/null 2>&1 && cc_log_pane_spawn window iterm2 "" "${PWD:-}" "lr-reset-poller spawn_gui create-window launcher:$(basename -- "$1")"
  local pane
  pane="$(lrp_bounded osascript 2>/dev/null \
    -e 'if not (application id "com.googlecode.iterm2" is running) then error "iTerm2 is not running"' \
    -e 'tell application id "com.googlecode.iterm2"' \
    -e 'set newWin to (create window with default profile)' \
    -e 'return id of (current session of newWin)' \
    -e 'end tell' | tr -d '[:space:]')"
  [ -n "$pane" ] || return 1
  osa_type_verified "$pane" "exec /bin/bash $1"
}
# spawn_tmux <launcher> <sid> — run the launcher in a DETACHED tmux session (headless PTY). 0 = created.
spawn_tmux() {
  [ -n "$LRP_TMUX_BIN" ] && [ -x "$LRP_TMUX_BIN" ] || return 1
  "$LRP_TMUX_BIN" new-session -d -s "lr-resume-${2:0:8}" "/bin/bash $1" >/dev/null 2>&1
}
# spawn_resume <launcher> <sid> — echo the mechanism used (gui|tmux) on success; non-zero on failure.
spawn_resume() {
  local launcher="$1" sid="$2" cwd="${3:-}" acct="${4:-}"
  case "$SPAWN_MECH" in
    gui)  spawn_gui  "$launcher" "$sid" "$cwd" "$acct" && { echo gui;  return 0; }; return 1 ;;
    tmux) spawn_tmux "$launcher" "$sid" && { echo tmux; return 0; }; return 1 ;;
    *)    spawn_gui  "$launcher" "$sid" "$cwd" "$acct" && { echo gui;  return 0; }
          # NO SILENT tmux FALLBACK (LIMIT_RECOVER_100P, 2026-09-09). A resume in a detached tmux
          # pane is not merely invisible — it is UNANSWERABLE: on 2026-09-09 lr-resume-52e35019 sat
          # frozen on a PreToolUse permission prompt with no human able to see it, and five sessions
          # from Aug 29 / Sep 5 were still alive there, unattended, for up to ten days. A session the
          # operator cannot see is a session that can strand forever; the honest outcome when no GUI
          # is reachable is NOT SPAWNED, loudly, and a retry next tick. tmux stays available only as
          # an EXPLICIT choice: LR_POLLER_SPAWN=tmux.
          log "NO-GUI  $sid — no reachable kitty/iTerm2; NOT spawned (tmux is never a silent fallback: a permission prompt there is unanswerable — 52e35019 froze on one 2026-09-09). Set LR_POLLER_SPAWN=tmux to opt in."
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
        --conviction 85 \
        --receipt "lr-reset-poller monthly-spend detector => $sid ($acct) hit the monthly spend cap with no reset time; default ratified as operator decision #3 (commands/limit-recover.md § Unattended mode)" \
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
# ── SIBLING LIBRARIES THE WAKE AND THE HOLDS USE (W6, resolutions 1, 3, 13; D4.1) ───────────────
# lr-page.sh — the liveness-free page (Notification Center + phone). lr-team.sh — the ONE live-member
# test. Both are landed siblings; a missing one is said once per tick and degrades that arm only.
LRP_PAGE_BIN=""
for _c in "$(dirname "$_LRP_SELF")/lr-page.sh" "$LR/lr-page.sh" "${HOME:-}/.claude/scripts/limit-recover/lr-page.sh"; do
  [[ -f "$_c" ]] && { LRP_PAGE_BIN="$_c"; break; }
done
for _c in "$(dirname "$_LRP_SELF")/lr-team.sh" "$LR/lr-team.sh" "${HOME:-}/.claude/scripts/limit-recover/lr-team.sh"; do
  # shellcheck disable=SC1090  # runtime-resolved sibling
  [[ -f "$_c" ]] && . "$_c" 2>/dev/null && break
done
# lrp_page <title tail> <message> → pages through lr-page.sh, logs its verdict line; never fatal.
# The text rides as ARGV (lr-page passes it to AppleScript as an argument, never as source), so an
# operator draft quoted in a page cannot become code — the older notifications in this file
# interpolate and must never carry one.
lrp_page() {
  local v
  if [[ $DRY -eq 1 ]]; then log "DRY   page ($1): $2"; return 0; fi
  if [[ -z "$LRP_PAGE_BIN" ]]; then log "PAGE-LOST ($1) lr-page.sh unreachable — $2"; return 0; fi
  v="$(/bin/bash "$LRP_PAGE_BIN" --title "$1" -- "$2" 2>>"$LOG" | tail -1)"
  log "PAGE  ($1) ${v:-lr-page: no verdict} — $2"
  return 0
}
# lrp_held_lead <sid> → 0 when the session LEADS live members (decision 4: held on every lane, woken
# in place at its reset, never moved and never re-spawned). Unknown (no lr-team.sh) is NOT a lead.
lrp_held_lead() { command -v lr_has_live_teammate >/dev/null 2>&1 && lr_has_live_teammate "${1:?}"; }
# lrp_tx_of <cfg> <sid> → that store's transcript path; rc 1 when none
lrp_tx_of() { local f; for f in "$1"/projects/*/"$2".jsonl; do [[ -f "$f" ]] && { printf '%s' "$f"; return 0; }; done; return 1; }
# lrp_still_limited <transcript> → 0 when its LAST assistant record is a usage-limit api error
lrp_still_limited() {
  local k=""
  command -v lr_last_api_error >/dev/null 2>&1 || return 1
  IFS=$'\t' read -r _ _ k _ <<<"$(lr_last_api_error "${1:-}" 2>/dev/null || true)"
  [[ "$k" == limit ]]
}
# lrp_iso <epoch> → %FT%T UTC (lr_engaged_after's baseline form)
lrp_iso() { date -u -r "${1:?}" +%FT%T 2>/dev/null || python3 -c 'import sys,time;print(time.strftime("%Y-%m-%dT%H:%M:%S",time.gmtime(int(sys.argv[1]))))' "$1"; }
# lrp_draft_hold <sid> <pane> <how> <focused> → keeps the screen and pages ONCE per sid+pane (D6.6, D6.7)
lrp_draft_hold() {
  local sid="$1" pane="$2" how="$3" foc="${4:-}" lcs="" snap="" rowtxt="" mark="$PARKED/$1.draft-paged"
  for lcs in "$LR/../lib/lr-composer-snapshot.sh" "${HOME:-}/.claude/scripts/lib/lr-composer-snapshot.sh" ""; do
    [[ -n "$lcs" && -f "$lcs" ]] && break
  done
  if [[ -n "$lcs" && -f "$lcs" && $DRY -eq 0 ]]; then
    snap="$(/bin/bash "$lcs" snap "$pane" "$sid" "$how" --focused "$foc" --limited 1 2>>"$LOG" || true)"
    [[ -n "$snap" ]] && rowtxt="$(/bin/bash "$lcs" row "$snap" 2>/dev/null | head -1 | cut -c1-120 || true)"
  fi
  [[ -e "$mark" ]] && return 0
  : > "$mark" 2>/dev/null || true
  lrp_page "unsent draft" "Pane $pane holds an unsent draft, so session ${sid:0:8} was not woken after its limit reset${rowtxt:+: \"$rowtxt\"}. Send or clear it; the next tick retries.${snap:+ Screen: $snap}"
}

# ── nudge_in_place — THE AT-RESET WAKE, ONE SPEC (resolution 3; D1.15, D4.7, D7.7) ───────────────
# The only automated route that resumes a live limited pane on its OWN account after its reset, and
# it never once worked: 85 of 85 attempts (09-10 to 09-22) logged NUDGE-FAILED "could not type",
# because it typed through `it2 session run` with only CC_TERM_KITTY_TO set, and under launchd (no
# KITTY_WINDOW_ID, no CC_TERM=kitty) the shim routed to iTerm2. Now:
#   · DELIVERY through cc_tui_submit (scripts/lib/cc-tui.sh), the path request prompt mode already
#     uses: kitty by socket, a composer gate that never types over a draft, and transcript proof.
#   · ONE FOCUS RULE (resolution 1): lr_focus_gate (lr-lib.sh) holds a focused pane unless
#     LR_MOVE_FOCUSED=on, and then only after two empty composer reads. Never re-implemented here.
#   · ONE WAKE TEXT (resolution 2): a plain continue. `/limit-recover` runs the skill, which can
#     choose a MOVE — the opposite of an in-place wake.
#   · TIMING (D4.7): at reset + LR_NUDGE_AFTER_RESET_S (120 s) or later, and only if no assistant
#     turn has appeared since the reset — a session that resumed on its own is left alone.
#   · THE RUN CLAIM (D7.7): the request lane's per-sid claim, so the wake and a request drain never
#     drive one pane at once.
# rc 0 engaged (or already continued) · 1 failed (counts toward the fire latch) · 2 not yet / not
# ours this tick (no strike) · 3 HELD (a person's draft or focus; no strike, paged once).
nudge_in_place() { # $1=sid $2=cfg $3=registry rows ("pane<TAB>pid<TAB>acct<TAB>cwd", first wins) $4=reset epoch [$5=1 await the turn · 0 return once typed]
  local sid="$1" cfg="$2" rows="$3" reset_ep="${4:-0}" await="${5:-1}" pane pid acct cwd tui="" pf t0 waited=0 max ivl rc=0 lead=0 idle crc leadnote=""
  IFS=$'\t' read -r pane pid acct cwd <<<"$(printf '%s\n' "$rows" | head -1)"
  [[ "$reset_ep" =~ ^[0-9]+$ ]] || reset_ep=0
  if (( reset_ep > 0 && $(date +%s) < reset_ep + ${LR_NUDGE_AFTER_RESET_S:-120} )); then
    log "NUDGE-WAIT $sid — reset at $(lrp_iso "$reset_ep")Z; the wake fires ${LR_NUDGE_AFTER_RESET_S:-120}s after it"
    return 2
  fi
  if (( reset_ep > 0 )) && lr_engaged_after "$cfg" "$sid" "$(lrp_iso "$reset_ep")"; then
    log "NUDGE-SKIP $sid — an assistant turn followed the reset; it continued on its own, nothing typed"
    return 0
  fi
  if [[ -n "${LR_CC_TUI_LIB+x}" ]]; then
    [[ -f "${LR_CC_TUI_LIB:-}" ]] && tui="$LR_CC_TUI_LIB"
  else
    for _t in "$LR/../lib/cc-tui.sh" "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/scripts/lib/cc-tui.sh" "${HOME:-}/.claude/scripts/lib/cc-tui.sh"; do
      [[ -f "$_t" ]] && { tui="$_t"; break; }
    done
  fi
  [[ -n "$tui" ]] || { log "NUDGE-SKIP $sid — scripts/lib/cc-tui.sh unreachable; nothing typed (pane $pane stays parked)"; return 2; }
  command -v lr_focus_gate >/dev/null 2>&1 || { log "NUDGE-SKIP $sid — lr-lib.sh has no lr_focus_gate (the live layer is behind); nothing typed"; return 2; }
  crc=0; run_claim_take "$sid" || crc=$?
  if (( crc != 0 )); then log "NUDGE-DEFER $sid — the run claim is held (a live request run drives it); nothing typed"; return 2; fi
  idle="$(command -v lr_hid_idle_s >/dev/null 2>&1 && lr_hid_idle_s || echo unreadable)"
  # Called DIRECTLY, never in $( ): the verdict comes back in LR_FOCUS_* globals.
  lr_focus_gate "$pane" || rc=$?
  if (( rc == 3 )); then
    run_claim_release "$sid"
    log "NUDGE-HELD $sid in pane $pane — ${LR_FOCUS_HOLD:-held} (focused=${LR_FOCUS_STATE:-unknown} idle=${idle}s); nothing typed"
    [[ "${LR_FOCUS_HOLD:-}" == HELD:draft ]] && lrp_draft_hold "$sid" "$pane" HELD:draft 1
    return 3
  fi
  rc=0
  lrp_held_lead "$sid" && { lead=1; leadnote=", a lead with live members"; }
  pf="$RESULTS/$sid.nudge.txt"
  if (( lead )); then
    printf '[limit-recover] The usage limit has reset on %s. Continue the work you were doing before the limit. Teammates whose last turn hit the limit resume when you message them.\n' "$acct" > "$pf"
  else
    printf '[limit-recover] The usage limit has reset on %s. Continue the work you were doing before the limit.\n' "$acct" > "$pf"
  fi
  t0="$(date -u +%FT%T)"
  # SOURCED IN A SUBSHELL, as request prompt mode does: cc-tui.sh must not replace this file's own
  # `log`/`lrp_bounded` for the rest of the tick.
  # shellcheck disable=SC1090  # runtime-resolved sibling
  ( . "$tui" && cc_tui_submit "$pane" "$pf" ) >> "$RESULTS/$sid.nudge.log" 2>&1 || rc=$?
  case "$rc" in
    0|5) : ;;
    3) run_claim_release "$sid"
       log "NUDGE-HELD $sid in pane $pane — HELD:draft (the composer holds text; focused=${LR_FOCUS_STATE:-unknown} idle=${idle}s); nothing typed"
       lrp_draft_hold "$sid" "$pane" HELD:draft "$([[ "${LR_FOCUS_STATE:-}" == yes ]] && echo 1 || echo 0)"
       return 3 ;;
    *) run_claim_release "$sid"
       log "NUDGE-FAILED $sid — cc_tui_submit rc $rc into pane $pane (pid $pid, $acct; focused=${LR_FOCUS_STATE:-unknown} idle=${idle}s); see $RESULTS/$sid.nudge.log"
       return 1 ;;
  esac
  if [[ "$await" == 0 ]]; then
    run_claim_release "$sid"
    log "NUDGE-TYPED $sid in pane $pane (in place on $acct$leadnote; focused=${LR_FOCUS_STATE:-unknown} idle=${idle}s) — the caller re-checks it next tick"
    return 0
  fi
  max="${LR_NUDGE_ENGAGE_S:-120}"; ivl="${LR_NUDGE_IVL:-5}"
  while (( waited < max )); do
    if lr_engaged_after "$cfg" "$sid" "$t0"; then
      run_claim_release "$sid"
      log "NUDGED $sid in pane $pane (in place on $acct, pid $pid$leadnote) — engaged after ${waited}s (focused=${LR_FOCUS_STATE:-unknown} idle=${idle}s)"
      return 0
    fi
    sleep "$ivl"; waited=$((waited + ivl))
  done
  run_claim_release "$sid"
  log "NUDGE-FAILED $sid — typed a continue into pane $pane but no assistant turn within ${max}s (focused=${LR_FOCUS_STATE:-unknown} idle=${idle}s)"
  return 1
}

# ── 0. REQUESTS — a driver's hand-off to this daemon (LIMIT_RECOVER_100P) ────────────────────────
# `/limit-recover fleet` (scripts/limit-recover/lr-fleet.sh) may run the recovery itself; when a
# session's own tool is refused (the auto-mode classifier denies acting on a live pane from inside a
# session) it writes a request here and kickstarts this job. A LaunchAgent runs outside every session
# and every classifier, so this is the locus that cannot be refused. Executed under the same overlap
# lock as everything below; one request at a time; the result is a file the driver can read back.
#
# ══ THE SCHEMA THIS LOOP READS — fixed HERE, by the CONSUMER (W5-A, 2026-09-20) ═════════════════
#   .sid          REQUIRED. Absent/unreadable ⇒ parked as `<name>.malformed.json` and NEVER retried.
#   .kind         ""|"recovery" (default) · "retire-husk" = a BREADCRUMB, filed, never executed
#                 · "upgrade" / "switch" = QUEUED for the one serial drainer (lr-upgrade.sh --drain);
#                   a switch carries .target and .source_pane (cc-lr switch --pane/--sid/--all-idle)
#   .mode         ""|"relaunch" (default) · "prompt" (the C14 repair: re-type into a live composer)
#   .target       account for lr-fleet --target (default "auto")          [relaunch]
#   .source_pane  the pane to act in    [relaunch: --source-pane, optional · prompt: REQUIRED]
#   .requested_by free text. "stop-failure-marker" is POLICY-GATED — see the autorecover gate below.
#   .prompt_file  an existing path to type                                [prompt]
#   .prompt       inline text to type, used when .prompt_file is absent   [prompt, default
#                 /limit-recover]. Read with its OWN jq -r so newlines survive verbatim.
#
# ══ THE FOUR DEFECTS THIS LOOP CARRIED, all live before this wave ═══════════════════════════════
# (1) THE WORKER RAN IN THE FOREGROUND, INSIDE THE TICK LOCK. lr-fleet prices `--one` at 115-658 s
#     (lr-fleet.sh:725), so one request held LOCKD for minutes and every concurrent tick TICK-SKIPped
#     — the self-overlap guard doing its job over a lock that should never have been held that long.
#     `--detach` (lr-fleet.sh:739-768) re-execs the driver under setsid, returns in <= 3 s, and sends
#     the verdict as mail. It REFUSES rather than silently blocking when it cannot reach detach.sh,
#     so passing it can never quietly degrade back to the foreground. (`--detach-inner`, which the
#     plan draft prescribes, exists NOWHERE in this tree.)
# (2) NOTHING RESERVED THE SID. `mkdir` is the atomic reservation that `: >` never was — claim_sid at
#     :225 is `: > "$CLAIMS/$1" || true`, where two writers both "win"; that one guards the SPAWN
#     path and is left alone, and this lane gets a real one.
# (3) THE GLOB IS `*.json` AND THE TRANSPLANT ARM BELOW WRITES INTO THIS VERY DIRECTORY. A
#     `retire-husk-<sid>.json` breadcrumb carries a `.sid`, so it was driven straight through
#     `lr-fleet --one` as if it were a recovery. Dispatch is on the record's SHAPE now, never on the
#     glob — a directory is not a type.
# (4) A DRAINED REQUEST WAS `rm -f`'d. A consumed request that reached nobody then looks exactly like
#     one that was never written; claimed/ is the evidence that closes that gap.
FLEET="${LR_FLEET_BIN:-$LR/lr-fleet.sh}"
HUSK_REQS="$STATE/husk-requests"
UPG_QUEUE="$STATE/upgrade-queue"
UPG_DEFER="$STATE/upgrade-deferred"   # switch requests parked by `cc-lr switch --until-idle` (lr-upgrade.sh)
UPG_BIN="${LR_UPGRADE_BIN:-$LR/lr-upgrade.sh}"
# THE RUN CLAIM IS lr-lib.sh's lr_claim_take (D2, 2026-09-28), the one implementation cc-lr and
# lr-fleet's pool also call. This file used to take it as a bare `mkdir` with NO holder file and wait
# out a 30-minute TTL on anyone else's; on 2026-09-28 the REROUTE arm below left exactly that shape
# behind a detached driver that died at once, and the retry was refused for 30 minutes until the
# operator ran the rmdir. Now: the claim is stamped with this tick's pid while it dispatches, then
# RE-STAMPED with the detached driver's pid (read off lr-fleet's DETACHED line), so it lives exactly
# as long as the work and is stolen the moment that driver dies. Every failure path releases it.
run_claim_take() { # $1=sid → 0 this tick owns the run, 1 a live run already holds it, 2 no claim store
  local note rc=0
  command -v lr_claim_take >/dev/null 2>&1 || { log "RUN-CLAIM-NO-LIB $1 — lr-lib.sh is unreachable, so no run claim can be taken"; return 2; }
  note="$(lr_claim_take "$RUN_CLAIMS" "${1:?run_claim_take needs a sid}" "lr-reset-poller" - "$$" 2>&1 >/dev/null)" || rc=$?
  case "$note" in
    *verdict=stolen-dead-holder*) log "RUN-CLAIM-DEAD-HOLDER $1 — ${note#lr-claim: }; retaken" ;;
    *verdict=stolen-orphan*)      log "RUN-CLAIM-ORPHAN $1 — ${note#lr-claim: }; retaken" ;;
    ?*)                           [[ $rc -eq 0 ]] || log "RUN-CLAIM-HELD $1 — ${note#lr-claim: }" ;;
  esac
  return "$rc"
}
run_claim_release() { lr_claim_release "$RUN_CLAIMS" "${1:?run_claim_release needs a sid}" "$$"; }
# After a detached dispatch: hand the claim to the driver, or release it when none is named.
run_claim_handoff() { # $1=sid $2=the dispatch's output file
  local dp
  dp="$(lr_detached_driver_pid < "$2" 2>/dev/null || true)"
  if [[ -n "$dp" ]] && lr_claim_restamp "$RUN_CLAIMS" "$1" "$$" "$dp" "lr-fleet --one --detach (lr-reset-poller)"; then
    return 0
  fi
  log "RUN-CLAIM-RELEASED $1 — the dispatch named no driver pid${dp:+ (or the claim was no longer ours)}, so the claim guards nothing and is released"
  run_claim_release "$1"
}
# rq_stale_reason <sid> <transcript_path> → rc 0 + a reason on stdout when the request is STALE;
# rc 1 (nothing printed) when the session is still a limited, movable, non-teammate session.
rq_stale_reason() {
  local sid="$1" tp="$2" cfg to="" kind="" c f
  # The hook always writes .transcript_path; an older or hand-written request may not, so look the
  # sid up across the account stores before calling it unconfirmable.
  if [[ -z "$tp" ]] && command -v lr_config_dirs >/dev/null 2>&1; then
    while IFS= read -r c; do
      for f in "$c"/projects/*/"$sid".jsonl "$c"/projects/*/"$sid".jsonl.handed-off; do
        [[ -e "$f" ]] && { tp="${f%.handed-off}"; break 2; }
      done
    done < <(lr_config_dirs 2>/dev/null)
  fi
  [[ -n "$tp" ]] || { echo "no transcript for this sid in any account store, so nothing on disk can confirm it"; return 0; }
  cfg="${tp%%/projects/*}"
  if [[ -e "$tp.handed-off" ]]; then echo "transplanted — the source transcript is tombstoned"; return 0; fi
  if command -v lr_transplant_target >/dev/null 2>&1 && to="$(lr_transplant_target "$sid" "$cfg" 2>/dev/null)"; then
    echo "transplanted to ${to:-another store}"; return 0
  fi
  [[ -f "$tp" ]] || { echo "the transcript is gone from $cfg"; return 0; }
  if head -c 8192 "$tp" 2>/dev/null | grep '"agentName"' >/dev/null; then echo "a teammate — lead-owned, never a recovery target"; return 0; fi
  # DECISION 4: a lead with live members is held on every lane. Retired HERE rather than dispatched,
  # or it spends RQ_MAX_ATTEMPTS on moves the precheck refuses as HELD:team; §2's wake owns it.
  if lrp_held_lead "$sid"; then echo "held:team, resumes in place at reset — a lead with live members is never moved"; return 0; fi
  command -v lr_last_api_error >/dev/null 2>&1 || { echo "lr-lib.sh is unreachable, so LIMITED cannot be confirmed"; return 0; }
  IFS=$'\t' read -r _ _ kind _ <<<"$(lr_last_api_error "$tp" 2>/dev/null || true)"
  [[ "$kind" == limit ]] || { echo "no longer LIMITED — its last assistant record is ${kind:+a $kind error}${kind:-not an api error} (recovered, resumed or working)"; return 0; }
  return 1
}
rq_retire() { # $1=file $2=name $3=sid $4=requested_by $5=reason — files the request, acts on nothing
  jq -n --arg sid "$3" --arg ts "$(date -u +%FT%TZ)" --arg by "$4" --arg why "$5" \
    '{sid:$sid, rc:0, ts:$ts, requested_by:$by, mode:"relaunch", verdict:"retired", reason:$why}' \
    > "$RESULTS/$3.json" 2>/dev/null || true
  mv "$1" "$RESULTS/${2%.json}.retired.json" 2>/dev/null || rm -f "$1"
  log "REQUEST-RETIRED $3 — $5; nothing was done"
}
# The hook lane's retry budget. A dispatched request STAYS in the queue until the session is seen
# recovered (it then retires above as transplanted / no longer LIMITED), so a driver that dies after
# a clean dispatch is retried instead of being consumed — the 2026-09-19 status-log defect: "a
# consumed request that failed looks identical to one never filed". Bounded: at most
# LR_REQUEST_MAX_ATTEMPTS dispatches, LR_REQUEST_RETRY_MIN apart, then filed as exhausted.
RQ_MAX_ATTEMPTS="${LR_REQUEST_MAX_ATTEMPTS:-3}"; [[ "$RQ_MAX_ATTEMPTS" =~ ^[1-9][0-9]*$ ]] || RQ_MAX_ATTEMPTS=3
RQ_RETRY_MIN="${LR_REQUEST_RETRY_MIN:-10}"; [[ "$RQ_RETRY_MIN" =~ ^[0-9]+$ ]] || RQ_RETRY_MIN=10
rq_record_attempt() { # $1=file $2=verdict — bumps .attempts and stamps the attempt, atomically
  local t="$1.tmp.$$"
  jq --arg v "$2" --argjson now "$(date +%s)" \
     '.attempts = ((.attempts // 0) + 1) | .last_attempt_epoch = $now | .last_verdict = $v' "$1" > "$t" 2>/dev/null \
    && mv -f "$t" "$1" 2>/dev/null || { rm -f "$t" 2>/dev/null; log "REQUEST-WARN could not record the attempt on $1"; }
}
# THE PER-ACCOUNT TICK COUNTERS. /bin/bash 3.2 (launchd's interpreter) has no associative arrays,
# so each counter is one "acct=n " string; rq_acct_n reads one account's count, rq_acct_bump adds one.
RQ_STAY_S="${LR_REQUEST_STAY_S:-900}"; [[ "$RQ_STAY_S" =~ ^[0-9]+$ ]] || RQ_STAY_S=900
RQ_MAX_PER_TICK="${LR_REQUEST_MAX_PER_TICK:-4}"; [[ "$RQ_MAX_PER_TICK" =~ ^[1-9][0-9]*$ ]] || RQ_MAX_PER_TICK=4
RQ_TICK_MIN="${LR_POLLER_TICK_MIN:-15}"; [[ "$RQ_TICK_MIN" =~ ^[1-9][0-9]*$ ]] || RQ_TICK_MIN=15
_rq_disp=""; _rq_over=0; _rq_over_by=""; _rq_woke=""
rq_acct_n() { rq_acct_n_of _rq_disp "$1"; } # $1=acct → this tick's dispatch count for it
rq_acct_n_of() { # $1=counter variable name $2=acct → that account's count in that counter
  local e; for e in ${!1}; do [[ "${e%=*}" == "$2" ]] && { printf '%s' "${e##*=}"; return 0; }; done
  printf 0
}
rq_acct_bump() { # $1=counter variable name $2=acct → +1 for that account in that counter
  local e out="" hit=0 v="${!1}"
  for e in $v; do
    if [[ "${e%=*}" == "$2" ]]; then out+="$2=$(( ${e##*=} + 1 )) "; hit=1; else out+="$e "; fi
  done
  (( hit )) || out+="$2=1 "
  printf -v "$1" '%s' "$out"
}
_rq_held=0; _rq_held_sids=""; _rq_recon=0
for _rq in "$REQUESTS"/*.json; do
  [[ -e "$_rq" ]] || continue
  _rq_name="$(basename "$_rq")"
  # `<sid>.cc-lr.json` is ADDRESSED TO THE RECONCILER (cc-lr under recon.on). While it is live the
  # request is its to read, so it is left untouched here; when it is not live the request drains
  # through this loop exactly as a cc-lr-origin request always has, so none strands on a dead daemon.
  case "$_rq_name" in
    *.cc-lr.json) if (( LRP_FENCE )) && lr_recon_live; then _rq_recon=$(( _rq_recon + 1 )); continue; fi ;;
  esac
  if [[ $DRY -eq 1 ]]; then log "DRY   request $_rq_name would be executed via $FLEET"; continue; fi
  # ONE reader, NUL-delimited, no interpreter in the path — the same shape as the parked-record
  # reader in § 2 and for the same reason: a JSON string may hold any byte EXCEPT NUL, so `read -d ''`
  # cannot mis-split a value, and a short read is a FAIL-CLOSED skip rather than half-assigned
  # fields. (The four `jq -r` forks it replaces also silently turned an unparseable file into a
  # record with every field at its default.)
  _rqf=()
  while IFS= read -r -d '' _v; do _rqf+=("$_v"); done < <(python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
if not isinstance(d,dict): raise SystemExit(1)
sys.stdout.write("".join(str(d.get(k) or "")+"\0"
  for k in ("sid","kind","mode","target","source_pane","requested_by","prompt_file",
            "transcript_path","attempts","last_attempt_epoch","reset_at_epoch","account")))
' "$_rq" 2>/dev/null)
  if (( ${#_rqf[@]} != 12 )) || [[ -z "${_rqf[0]}" ]]; then
    log "REQUEST-SKIP $_rq_name — unreadable or no sid; parked as malformed"
    mv "$_rq" "$RESULTS/${_rq_name%.json}.malformed.json" 2>/dev/null || true; continue
  fi
  _rq_sid="${_rqf[0]}"; _rq_kind="${_rqf[1]}"; _rq_mode="${_rqf[2]}"; _rq_target="${_rqf[3]}"
  _rq_pane="${_rqf[4]}"; _rq_by="${_rqf[5]}"; _rq_pfile="${_rqf[6]}"
  _rq_tp="${_rqf[7]}"; _rq_att="${_rqf[8]}"; _rq_last="${_rqf[9]}"
  _rq_reset="${_rqf[10]}"; _rq_acct="${_rqf[11]}"
  [[ "$_rq_att" =~ ^[0-9]+$ ]] || _rq_att=0
  [[ "$_rq_last" =~ ^[0-9]+$ ]] || _rq_last=0
  [[ "$_rq_reset" =~ ^[0-9]+$ ]] || _rq_reset=0
  # The account the session died on: the hook writes it; an older or hand-written request is placed
  # by its transcript's store, and one with neither shares a single "unknown" bucket for the cap.
  if [[ -z "$_rq_acct" && -n "$_rq_tp" ]]; then _rq_acct="$(acct_of_cfg "${_rq_tp%%/projects/*}" 2>/dev/null || true)"; fi
  [[ -n "$_rq_acct" ]] || _rq_acct=unknown
  _rq_hook=0; [[ "$_rq_by" == "stop-failure-marker" ]] && _rq_hook=1

  # ── DRAIN-TIME REVALIDATION (D3, 2026-09-28) — the hook's request is a SNAPSHOT of one death ─────
  # It was true when the session died and can be false by the time it is drained: on 2026-09-28 the
  # held cohort still carried 415a3aac and 55120708, both already recovered by hand. Draining a stale
  # request transplants a session that is fine. So every hook-originated request is re-checked
  # against disk HERE, whether or not the lane is on, and retired with a named reason — never acted
  # on — unless the session is still: on the store the hook saw (no tombstone, no transplant lock),
  # not a teammate, and still LIMITED (its last assistant record is a usage-limit api error). A
  # session that moved to or resumed on a healthy account fails one of the first or the last.
  if (( _rq_hook == 1 )); then
    if _rq_why="$(rq_stale_reason "$_rq_sid" "$_rq_tp")"; then
      rq_retire "$_rq" "$_rq_name" "$_rq_sid" "$_rq_by" "$_rq_why"; continue
    fi
  fi
  [[ -n "$_rq_target" ]] || _rq_target=auto
  [[ -n "$_rq_by" ]] || _rq_by='?'

  # ── THE HOOK-ORIGIN POLICY GATE — SAFETY-CRITICAL, AND IT FAILS CLOSED ────────────────────────
  # hooks/stop-failure-marker.sh writes a request on every rate-limit death. ROUGHLY 30 SESSIONS DIE
  # AT ONCE on one cap, so draining that cohort unattended would transplant thirty sessions onto
  # other accounts with nobody in the loop — and whether this fleet does that is an OPEN OPERATOR
  # DECISION standing at 85% conviction whose shipped default is OFF
  # (docs/plans/LIMIT_RECOVER_100P.md:384). This gate is what makes that hook arm safe to ship.
  #
  # ABSENT FILE ⇒ DO NOT DRAIN. The request is LEFT IN PLACE — not claimed, not moved, not deleted:
  # it is the breadcrumb `cc-find --limited` reads, and the operator's own `touch` is what releases
  # the whole cohort at once. THIS DAEMON MUST NEVER CREATE $STATE/autorecover.on; its absence is
  # the shipped default and creating it here would be the daemon granting itself the permission.
  if [[ "$_rq_by" == "stop-failure-marker" ]] && [[ ! -e "$STATE/autorecover.on" ]]; then
    _rq_held=$(( _rq_held + 1 ))
    # ONE summary line per tick, after the loop — never one per request per tick. A thirty-strong
    # held cohort at a 10-minute cadence is 4,320 identical lines a day, and this daemon has already
    # proved what that costs (1,800 of them, § the fire-failure latch).
    (( ${#_rq_held_sids} < 72 )) && _rq_held_sids="${_rq_held_sids:+$_rq_held_sids,}${_rq_sid:0:8}"
    continue
  fi

  # ── DISPATCH ON THE RECORD'S SHAPE, NEVER ON THE GLOB (defect 3) ──────────────────────────────
  case "$_rq_kind" in
    ''|recovery) : ;;
    retire-husk)
      # NOT a recovery: the transplant arm in § 2 writes this to say a SOURCE PANE is still standing
      # after its session moved. Nothing in the tree consumes it from $REQUESTS (verified by grep,
      # 2026-09-20 — zero readers), and leaving it here means re-logging it on every tick forever,
      # so it is FILED into its own lane where `lr-fleet --retire-husks` can find it.
      mkdir -p "$HUSK_REQS" 2>/dev/null || true
      log "HUSK-REQUEST $_rq_sid — filed to $HUSK_REQS for lr-fleet --retire-husks; a breadcrumb is not a recovery"
      mv "$_rq" "$HUSK_REQS/$_rq_name" 2>/dev/null || true
      continue ;;
    upgrade|switch)
      # cc-lr upgrade (2026-09-22): move an IDLE session onto the current binary + model, in place.
      # cc-lr switch --pane/--sid/--all-idle (2026-09-23): ask an IDLE session to move ITSELF to
      # another account. Same queue, same ONE serial drainer, for the same reasons: the drainer
      # re-judges the idle predicate at execution time (a session that went busy is reported and
      # never typed into), and then waits minutes for the registry flip — far longer than a tick.
      # NOT executed inside this tick: an upgrade /exits and relaunches a live pane and can take
      # minutes, and the tick lock must never be held that long (defect 1 above). The request is
      # QUEUED, and one serial drainer (lr-upgrade.sh --drain, kicked below) takes the queue one
      # session at a time — re-judging the selection predicate and probing capacity at EXECUTION
      # time, before anything is typed. No run claim here: the drainer takes the per-sid mutex itself.
      mkdir -p "$UPG_QUEUE" 2>/dev/null || true
      if mv "$_rq" "$UPG_QUEUE/$_rq_name" 2>/dev/null; then
        log "$( [[ "$_rq_kind" == switch ]] && echo SWITCH-QUEUED || echo UPGRADE-QUEUED ) $_rq_sid (pane ${_rq_pane:-?}${_rqf[3]:+ -> ${_rqf[3]}}) for $_rq_by"
      else
        log "UPGRADE-SKIP $_rq_sid — could not move the request into $UPG_QUEUE (left in place)"
      fi
      continue ;;
    *)
      log "REQUEST-SKIP $_rq_sid — unknown kind '$_rq_kind'; parked (this loop executes recoveries only)"
      mv "$_rq" "$RESULTS/${_rq_name%.json}.unknown-kind.json" 2>/dev/null || true
      continue ;;
  esac

  [[ -n "$_rq_mode" ]] || _rq_mode=relaunch
  case "$_rq_mode" in
    relaunch|prompt) : ;;
    *) log "REQUEST-SKIP $_rq_sid — unknown mode '$_rq_mode'; parked"
       mv "$_rq" "$RESULTS/${_rq_name%.json}.unknown-mode.json" 2>/dev/null || true; continue ;;
  esac

  # EVERY precondition is tested BEFORE the claim, so a refusal can never wedge the sid for the
  # claim's TTL over a run that was never started.
  _rq_tui=""
  if [[ "$_rq_mode" == relaunch ]]; then
    if [[ ! -x "$FLEET" ]]; then
      log "REQUEST-SKIP $_rq_sid — lr-fleet.sh not executable at $FLEET (request left in place)"; continue
    fi
  else
    # scripts/lib/cc-tui.sh is an ADD from this same wave, so it is INERT on the live symlink layer
    # until a converge runs install.sh — a landed-but-unlinked file is absent, not stale, and every
    # `[ -f x ] && . x` guard over one is a SILENT skip. This one is loud.
    # LR_CC_TUI_LIB, when SET, is the whole ladder: a test must be able to name an ABSENT path.
    if [[ -n "${LR_CC_TUI_LIB+x}" ]]; then
      [[ -f "${LR_CC_TUI_LIB:-}" ]] && _rq_tui="${LR_CC_TUI_LIB:-}"
    else
      for _t in "$LR/../lib/cc-tui.sh" "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/scripts/lib/cc-tui.sh" \
                "${HOME:-}/.claude/scripts/lib/cc-tui.sh"; do
        [[ -f "$_t" ]] && { _rq_tui="$_t"; break; }
      done
    fi
    if [[ -z "$_rq_tui" ]]; then
      log "REQUEST-SKIP $_rq_sid — mode:prompt needs scripts/lib/cc-tui.sh and this layer does not carry it yet; request left in place for the next tick"
      continue
    fi
    if [[ -z "$_rq_pane" ]]; then
      log "REQUEST-SKIP $_rq_sid — mode:prompt has no .source_pane; parked as malformed"
      mv "$_rq" "$RESULTS/${_rq_name%.json}.malformed.json" 2>/dev/null || true; continue
    fi
  fi

  # ── STAY NEAR THE RESET, AND PACE THE COHORT (W6b: D1.4, D1.6, resolution 4) ─────────────────
  # Both are checked BEFORE the fence and the claim, and neither spends an attempt: a request held
  # here is exactly as it was, and the next tick sees it again.
  if [[ "$_rq_mode" == relaunch ]]; then
    # D1.4 — a session whose own account resets within LR_REQUEST_STAY_S (default 900 s) stays put.
    # Moving it minutes before its reset buys nothing and costs a transplant and a cold replay; the
    # three dispatches sent 3-4 min before the 06:30Z reset on 2026-09-29 are the measured case, and
    # the 2026-09-10 cascade (13 panes in 8 s, 74 of 92 re-runs lost) is what an unpaced cohort costs.
    if (( _rq_reset > 0 )); then
      _rq_left=$(( _rq_reset - $(date +%s) ))
      if (( _rq_left > 0 && _rq_left < RQ_STAY_S )); then
        log "REQUEST-STAY $_rq_sid ($_rq_acct) — its account resets in ${_rq_left}s (< ${RQ_STAY_S}s); left queued, no attempt spent"
        continue
      fi
    fi
    # D1.4 — PAST THE RESET, WAKE IN PLACE; NEVER MOVE. The account the session died on has headroom
    # again, so a transplant elsewhere buys nothing. A hook request whose session is still limited,
    # with a live pane, gets ONE plain continue through nudge_in_place (focus gate, composer gate,
    # run claim, the wake text) — without its engagement wait: the request stays queued and the next
    # tick retires it the moment the session is no longer LIMITED. Paced: at most LR_WAKE_PER_ACCT
    # (3) per account per tick, each sid a stable 0-LR_WAKE_JITTER_S (90) s after reset + 120 s.
    if (( _rq_hook == 1 && _rq_reset > 0 && $(date +%s) >= _rq_reset )) \
       && command -v lr_registry_live_rows >/dev/null 2>&1 && _rq_rows="$(lr_registry_live_rows "$_rq_sid" 2>/dev/null)"; then
      _rq_jit=$(( $(printf '%s' "$_rq_sid" | cksum | cut -d' ' -f1) % ${LR_WAKE_JITTER_S:-90} ))
      if (( $(date +%s) < _rq_reset + ${LR_NUDGE_AFTER_RESET_S:-120} + _rq_jit )); then continue; fi
      if (( $(rq_acct_n_of _rq_woke "$_rq_acct") >= ${LR_WAKE_PER_ACCT:-3} )); then _rq_over=$(( _rq_over + 1 )); rq_acct_bump _rq_over_by "$_rq_acct"; continue; fi
      lrp_may_act "$_rq_sid" wake || continue
      _rq_nrc=0; nudge_in_place "$_rq_sid" "${_rq_tp%%/projects/*}" "$_rq_rows" "$_rq_reset" 0 || _rq_nrc=$?
      lrp_act_done
      case "$_rq_nrc" in
        0) rq_acct_bump _rq_woke "$_rq_acct"; rq_record_attempt "$_rq" woken-in-place
           log "REQUEST-WAKE $_rq_sid ($_rq_acct) — a continue was typed into its own pane after the reset; the request stays queued until the session is seen recovered" ;;
        1) rq_acct_bump _rq_woke "$_rq_acct"; rq_record_attempt "$_rq" wake-failed ;;
        *) : ;;   # not yet, or held by a person: nothing spent
      esac
      continue
    fi
    # D1.6 — at most RQ_MAX_PER_TICK dispatches per ACCOUNT per tick (default 4, MAX_PER_RUN's
    # number). A 30-death cohort otherwise started 30 detached drivers in one tick. The excess stays
    # queued; the tick's summary line names the depth and the ETA the cap implies.
    if (( $(rq_acct_n "$_rq_acct") >= RQ_MAX_PER_TICK )); then
      _rq_over=$(( _rq_over + 1 )); rq_acct_bump _rq_over_by "$_rq_acct"
      continue
    fi
  fi

  # ── THE RECONCILER FENCE (§ C10) — the first point this iteration touches the sid ─────────────
  # DEFER leaves the request exactly where it is: the reconciler owns the session now, and if it
  # lapses the next tick finds the request again. ACT is paired with lrp_act_done on EVERY exit path
  # below, so a lapsed-verdict launch lock never outlives this sid's iteration.
  lrp_may_act "$_rq_sid" request || continue

  # ── THE PER-SID RUN CLAIM (defect 2) ──────────────────────────────────────────────────────────
  if (( _rq_hook == 1 )); then
    if (( _rq_att >= RQ_MAX_ATTEMPTS )); then
      log "REQUEST-EXHAUSTED $_rq_sid — $_rq_att dispatch(es) and the session is still LIMITED; filed as exhausted (cc-lr recover ${_rq_sid:0:8} retries it by hand)"
      mv "$_rq" "$RESULTS/${_rq_name%.json}.exhausted.json" 2>/dev/null || true; lrp_act_done
      # ONCE: the request leaves the queue on this line, so there is no later tick to repeat it.
      lrp_page "recovery exhausted" "Session ${_rq_sid:0:8} (pane ${_rq_pane:-?}, $_rq_acct) is still limited after $_rq_att recovery attempts. The usual cause is an unsent draft in that pane. cc-lr recover ${_rq_sid:0:8} retries it."
      continue
    fi
    if (( _rq_last > 0 && $(date +%s) - _rq_last < RQ_RETRY_MIN * 60 )); then lrp_act_done; continue; fi
  fi
  _rq_crc=0; run_claim_take "$_rq_sid" || _rq_crc=$?
  if (( _rq_crc == 1 && _rq_hook == 1 )); then
    # A live run holds the sid. The request is KEPT: it retires on its own once the session is seen
    # recovered, and is retried if that run ends with the session still LIMITED.
    log "REQUEST-IN-FLIGHT $_rq_sid — a live run holds the claim; kept for re-check when it ends"
    lrp_act_done; continue
  fi
  if (( _rq_crc == 2 )); then
    log "REQUEST-SKIP $_rq_sid — the run claim could not be taken (no lib or an unwritable store); request left in place for the next tick"
    lrp_act_done; continue
  fi
  if (( _rq_crc != 0 )); then
    # MOVED to claimed/, never deleted — the same evidence rule as a drained request (defect 4). A
    # superseded request is still one that reached this daemon, and its suffix names the outcome.
    log "SUPERSEDED-BY-LIVE-RUN $_rq_sid — $RUN_CLAIMS/$_rq_sid.active is held by a run already in flight; this request is filed to $CLAIMED as superseded"
    mv "$_rq" "$CLAIMED/${_rq_name%.json}.superseded.json" 2>/dev/null || rm -f "$_rq"
    lrp_act_done; continue
  fi

  _rq_rc=0; _rq_verdict=""
  case "$_rq_mode" in
    relaunch)
      log "REQUEST $_rq_sid — dispatching the in-place recovery DETACHED (target $_rq_target${_rq_pane:+, pane $_rq_pane}) for $_rq_by"
      # shellcheck disable=SC2086  # deliberate: ${var:+--flag "val"} must word-split into 0 or 2 args
      "$FLEET" --one "$_rq_sid" --target "$_rq_target" ${_rq_pane:+--source-pane "$_rq_pane"} --from-daemon --detach \
        > "$RESULTS/$_rq_sid.log" 2>&1 || _rq_rc=$?
      _rq_verdict=dispatched
      # rc != 0 from --detach means NOTHING was started (it refuses rather than blocking), so the
      # claim guards no run and must not hold the sid out of recovery until the TTL.
      if (( _rq_rc == 0 )); then run_claim_handoff "$_rq_sid" "$RESULTS/$_rq_sid.log"
      else run_claim_release "$_rq_sid"; _rq_verdict=dispatch-failed; fi
      rq_acct_bump _rq_disp "$_rq_acct"
      ;;
    prompt)
      # C14: the pane is up with an EMPTY composer and nothing was ever submitted, so the repair is
      # to re-type, not to relaunch. `.prompt` is read by its own `jq -r` so a multi-line prompt
      # survives verbatim — the NUL reader above deliberately does not carry it.
      _rq_pf="$_rq_pfile"
      if [[ -z "$_rq_pf" || ! -f "$_rq_pf" ]]; then
        _rq_pf="$RESULTS/$_rq_sid.prompt.txt"
        jq -r '.prompt // "/limit-recover"' "$_rq" > "$_rq_pf" 2>/dev/null || printf '/limit-recover\n' > "$_rq_pf"
      fi
      log "REQUEST $_rq_sid — mode:prompt, re-typing into pane $_rq_pane via $_rq_tui for $_rq_by"
      # SOURCED IN A SUBSHELL. cc-tui.sh is another wave's file and this daemon already defines
      # `log`, `lrp_bounded` and a dozen more at global scope; a sibling library that happened to
      # define any of them would silently replace the poller's for the rest of the tick.
      # shellcheck disable=SC1090  # runtime-resolved sibling, as with every other library here
      ( . "$_rq_tui" && cc_tui_submit "$_rq_pane" "$_rq_pf" ) > "$RESULTS/$_rq_sid.log" 2>&1 || _rq_rc=$?
      case "$_rq_rc" in
        0) _rq_verdict=submitted ;;          1) _rq_verdict=no-such-pane ;;
        2) _rq_verdict=unreadable-or-modal ;; 3) _rq_verdict=composer-occupied ;;
        4) _rq_verdict=paste-not-echoed ;;   5) _rq_verdict=sent-but-no-record ;;
        *) _rq_verdict="rc-$_rq_rc" ;;
      esac
      # Synchronous by construction: whatever happened, no run is left in flight and the sid is free.
      run_claim_release "$_rq_sid"
      ;;
  esac
  jq -n --arg sid "$_rq_sid" --arg rc "$_rq_rc" --arg ts "$(date -u +%FT%TZ)" --arg log "$RESULTS/$_rq_sid.log" \
        --arg by "$_rq_by" --arg mode "$_rq_mode" --arg verdict "$_rq_verdict" \
    '{sid:$sid, rc:($rc|tonumber), ts:$ts, log:$log, requested_by:$by, mode:$mode, verdict:$verdict}' \
    > "$RESULTS/$_rq_sid.json" 2>/dev/null || true
  # MOVED, NEVER DELETED (defect 4). `|| rm -f` only for a store that cannot be written at all —
  # leaving the record here under a held claim would re-log SUPERSEDED-BY-LIVE-RUN every tick.
  if (( _rq_hook == 1 )) && [[ "$_rq_mode" == relaunch ]]; then
    rq_record_attempt "$_rq" "$_rq_verdict"
    log "REQUEST $_rq_sid — $_rq_verdict rc=$_rq_rc, attempt $(( _rq_att + 1 ))/$RQ_MAX_ATTEMPTS; the request stays queued until the session is seen recovered (result $RESULTS/$_rq_sid.json)"
    lrp_act_done; continue
  fi
  mv "$_rq" "$CLAIMED/$_rq_name" 2>/dev/null || rm -f "$_rq"
  log "REQUEST $_rq_sid — $_rq_verdict rc=$_rq_rc (result $RESULTS/$_rq_sid.json)"
  lrp_act_done
done
if (( _rq_over > 0 )); then
  # THE TRICKLE IS STATED, NOT HIDDEN (resolution 4): real ticks run ~14-16 min apart, so the ETA is
  # the deepest account's backlog in ticks times LR_POLLER_TICK_MIN.
  _rq_deep=0; for _e in $_rq_over_by; do (( ${_e##*=} > _rq_deep )) && _rq_deep=${_e##*=}; done
  _rq_ticks=$(( (_rq_deep + RQ_MAX_PER_TICK - 1) / RQ_MAX_PER_TICK ))   # whole ticks: a partial one still costs a tick
  _rq_eta=$(( _rq_ticks * RQ_TICK_MIN ))
  log "REQUEST-QUEUED $_rq_over request(s) over the ${RQ_MAX_PER_TICK}/account/tick cap left queued (by account: ${_rq_over_by% }); queue depth $_rq_over, ETA ~${_rq_eta} min at ~${RQ_TICK_MIN} min/tick"
  # PAGED ONCE PER DEPTH: a new depth is news (a cohort arriving, or draining), the same depth again
  # is not. The stamp is state, never a log grep.
  if [[ "$(cat "$STATE/request-queue.page" 2>/dev/null || true)" != "$_rq_over" ]]; then
    printf '%s\n' "$_rq_over" > "$STATE/request-queue.page" 2>/dev/null || true
    lrp_page "recovery queue" "$_rq_over limited session(s) are queued for recovery (by account: ${_rq_over_by% }). At ${RQ_MAX_PER_TICK} per account per tick the queue drains in about ${_rq_eta} min."
  fi
else
  rm -f "$STATE/request-queue.page" 2>/dev/null || true
fi
if (( _rq_recon > 0 )); then
  log "RECON-OWNED $_rq_recon cc-lr request(s) left for the live reconciler"
fi
if (( _rq_held > 0 )); then
  log "HOOK-HELD $_rq_held hook-originated request(s) NOT drained — $STATE/autorecover.on is absent (sids: $_rq_held_sids); creating that file is the operator's call and releases the whole cohort"
fi
lrp_engagement_audit   # AFTER the drain, never before it (D1.5 — see the function header)

# ── the upgrade drainer: ONE, detached, kicked whenever the queue holds work ────────────────────
# Keyed on the QUEUE, not on "a request arrived this tick": a drainer that died with work left is
# restarted by the next tick rather than stranding the queue until someone writes another request.
# The drainer's own lock (upgrade-drain.lock/pid) makes a second start a no-op, so this check is a
# fast path, not the guarantee. Detached through scripts/lib/detach.sh (start_new_session) so it
# outlives this tick; its output goes to upgrade-drain.log, its verdicts to results/upgrade-<sid>.json.
# The census is bounded like every other fork on this daemon's tick, but by its own (longer) budget:
# lrp_bounded's 15 s is sized for one AppleEvent. LR_UPGRADE_AUTO_TIMEOUT_S, default 60.
lrp_bounded_long() {
  if [ -z "$LRP_TIMEOUT_BIN" ] || [ ! -x "$LRP_TIMEOUT_BIN" ]; then "$@"; return $?; fi
  "$LRP_TIMEOUT_BIN" -k 5 "${LR_UPGRADE_AUTO_TIMEOUT_S:-60}" "$@"
}
lrp_upgrade_kick() {
  local hp det="" d pid
  # A PARKED switch is work too: the drain start is what re-judges it, so a tick that saw only
  # parked requests and did not kick would leave them waiting out their whole --until-idle budget.
  compgen -G "$UPG_QUEUE/*.json" >/dev/null 2>&1 || compgen -G "$UPG_DEFER/*.json" >/dev/null 2>&1 || return 0
  hp="$(cat "$STATE/upgrade-drain.lock/pid" 2>/dev/null || true)"
  if [[ "$hp" =~ ^[0-9]+$ ]] && kill -0 "$hp" 2>/dev/null; then
    log "UPGRADE-DRAIN already running (pid $hp)"; return 0
  fi
  # THE FENCE, per queue: a drainer started over a queue whose every sid the reconciler owns would
  # only walk it and defer each one (the per-sid drive fences live in lr-upgrade.sh). One queued sid
  # that may act is enough to start it. The raw predicate, not may_act: nothing is touched here.
  if (( LRP_FENCE )); then
    local f s n=0 nd=0
    for f in "$UPG_QUEUE"/*.json "$UPG_DEFER"/*.json; do
      [[ -e "$f" ]] || continue
      s="$(jq -r '.sid // ""' "$f" 2>/dev/null || true)"
      n=$(( n + 1 ))
      [[ -n "$s" ]] && lr_recon_defers "$s" 2>/dev/null && nd=$(( nd + 1 ))
    done
    if (( n > 0 && nd == n )); then
      log "UPGRADE-DEFER all $n queued request(s) are on sids the reconciler owns; drainer not started"
      return 0
    fi
  fi
  if [[ $DRY -eq 1 ]]; then log "DRY   upgrade drainer would start: $UPG_BIN --drain"; return 0; fi
  if [[ ! -f "$UPG_BIN" ]]; then log "UPGRADE-SKIP drainer not found at $UPG_BIN (queue left in place)"; return 0; fi
  for d in "$LR/../lib/detach.sh" "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/scripts/lib/detach.sh" "$HOME/.claude/scripts/lib/detach.sh"; do
    [[ -f "$d" ]] && { det="$d"; break; }
  done
  if [[ -z "$det" ]]; then log "UPGRADE-SKIP scripts/lib/detach.sh unreachable — will not run the drainer inside the tick lock"; return 0; fi
  # shellcheck disable=SC1090  # runtime-resolved sibling
  pid="$( . "$det" && detach "$STATE/upgrade-drain.log" /bin/bash "$UPG_BIN" --drain 2>/dev/null )" || pid=""
  log "UPGRADE-DRAIN started${pid:+ pid $pid} ($UPG_BIN --drain)"
}
# +2 THE AUTO-TRIGGER (operator ruling 2026-09-22): every tick, queue every live session whose
# binary/model differs from the launcher pin + SSOT (lr-upgrade.sh --auto-enqueue — it adds nothing
# while the queue holds work or a drainer runs, and it owns both kill switches: LR_UPGRADE_AUTO=off
# and $STATE/upgrade-auto.off). A census, so it is skipped with the census (LR_POLLER_NO_CENSUS).
# Bounded: the census is one ps snapshot plus a jq per registry row, measured ~6 s on 16 rows.
if [[ "${LR_POLLER_NO_CENSUS:-0}" != 1 && "${LR_UPGRADE_AUTO:-on}" != off && -f "$UPG_BIN" ]]; then
  if [[ $DRY -eq 1 ]]; then
    log "DRY   upgrade auto-trigger would run: $UPG_BIN --auto-enqueue"
  else
    _upg_q="$(lrp_bounded_long /bin/bash "$UPG_BIN" --auto-enqueue 2>>"$LOG" || true)"
    [[ -n "$_upg_q" ]] && log "UPGRADE-AUTO queued: $(printf '%s' "$_upg_q" | awk -F'\t' '{printf "%s%s(%s)", (NR>1?" ":""), $1, substr($2,1,8)}')"
  fi
fi
lrp_upgrade_kick
# +3 THE RESUME-DEBT BACKSTOP (docs/plans/CLOSE_RESUME_CUSTODY.md §2 D4): one `cc-resume-debt sweep`
# per tick steps every open debt once, so a debt whose settling watcher died still reaches proof or
# escalation. Kill switch LR_RESUME_DEBT_SWEEP=off; DRY logs only; an absent binary is a silent skip.
# RD: CC_RESUME_DEBT_BIN seam, else the repo bin beside this script, else ~/.claude/bin.
RD="${CC_RESUME_DEBT_BIN:-}"
if [[ -z "$RD" ]]; then
  for _rd in "$LR/../../bin/cc-resume-debt" "$HOME/.claude/bin/cc-resume-debt"; do
    [[ -x "$_rd" ]] && { RD="$_rd"; break; }
  done
fi
if [[ "${LR_RESUME_DEBT_SWEEP:-on}" != off && -n "$RD" && -x "$RD" ]]; then
  if [[ $DRY -eq 1 ]]; then
    log "DRY   resume-debt sweep would run: $RD sweep"
  else
    _rd_out="$(lrp_bounded_long "$RD" sweep 2>>"$LOG" || true)"
    while IFS= read -r _rd_l; do [[ -n "$_rd_l" ]] && log "RESUME-DEBT: $_rd_l"; done <<< "$_rd_out"
  fi
fi

# ── TRANSPLANT-LOCK EXPIRY — the only caller of the TTL (cc-backlog 4f8c73bbdb35) ───────────────
# lr-transplant.sh's split-brain lock had no TTL and no release verb, so an abandoned move held
# custody of its session uuid forever. lr-lock.py owns the policy; this tick is what APPLIES it — a TTL
# nothing enforces is a comment. It expires only what the disk proves carries no custody (ORPHAN,
# ABANDONED) past LR_LOCK_TTL_S; a lock guarding a live successor is never touched, however old.
# Kill switch LR_LOCK_REAP=off. One fork, bounded like every other on this tick; a failure is logged
# and never stops the tick — this daemon's job is recovering sessions, not keeping the lock dir tidy.
if [[ "${LR_LOCK_REAP:-on}" != off && -f "$LR/lr-lock.py" && -d "$STATE/locks" ]]; then
  if [[ $DRY -eq 1 ]]; then
    _lk_out="$(LR_STATE_DIR="$STATE" lrp_bounded python3 "$LR/lr-lock.py" reap --dry-run 2>&1 || true)"
  else
    _lk_out="$(LR_STATE_DIR="$STATE" lrp_bounded python3 "$LR/lr-lock.py" reap 2>&1)" \
      || log "LOCK-REAP rc=$? (logged, tick continues)"
  fi
  [[ -z "${_lk_out:-}" ]] || while IFS= read -r _lk_line; do log "LOCK-REAP $_lk_line"; done <<< "$_lk_out"
fi

# ── the two predicate calls this loop makes, each ONE fork, both through the SSOT ───────────────
# WHY A FUNCTION AND NOT AN INLINE `grep`. Both of these replace a raw `grep` whose exit 1 meant two
# different things at once, and the poller read both as "no". The old `head -c 8000 | grep` for the
# agentName key exits 1 for a session that is NOT a teammate and for a transcript that has been
# rotated away — and the second reading pushed a live teammate into the lead's own respawn. The shim
# REFUSES instead (rc 4, "the predicate could not run"), which is why the call sites branch on
# UNREADABLE before they branch on the verdict. A refusal is never silently a "no".
lrp_is_teammate() { # <transcript> → 0 teammate, 1 not a teammate, 2 UNREADABLE (caller must skip)
  local out rc
  out="$(bash "$LRPRED" is-teammate-head "$1" 2>/dev/null)"; rc=$?
  [ "$rc" -eq 0 ] || return 2
  [ "$(printf '%s' "$out" | jq -r '.teammate')" = true ]
}

lrp_cap_of() { # <transcript> → the cap of the tail's LAST api-error record, empty when not a limit
  local out
  out="$(bash "$LRPRED" classify-tail "$1" 2>/dev/null)" || return 1
  printf '%s' "$out" | jq -r 'if .limit then (.cap // "unknown") else "" end'
}

# ── the census ingest, as a function so it can be run on its own (LIMIT_RECOVER_FLEET_V2 W4) ─────
# $1 = the census JSON (`cc-limited --all --json`). Parks every recoverable row and appends one
# `<acct>\t<cap>\t<reset_ep>` line per parked row to "$1.groups" for the re-surface page below.
# THE PYTHON IS A FILE, NOT A HEREDOC INSIDE `<( … )`. /bin/bash 3.2 — the shell launchd runs this
# daemon under — re-scans a process substitution's text for its closing paren and does not honour
# heredoc boundaries while doing so, so one apostrophe in the program ("the parked record's") made
# the whole census die with `bad substitution: no closing ')'` every tick. A file under the per-uid
# temp dir is parsed by nothing but python.
lrp_census_ingest() {
  local _cj="$1" _pyf sid state acct cap reset_iso reset_ep cwd cfg wait_ok _f kind prev
  _pyf="$(mktemp "$(lrp_tmpdir)/lrp-census-py.XXXXXX" 2>/dev/null)" || { log "CENSUS-SKIP could not write the census reader under $(lrp_tmpdir)"; return 0; }
  cat > "$_pyf" <<'PY'
import json, sys
from datetime import datetime, timezone
# The census carries `resets_at` as an EPOCH and the parked record's `reset_at_utc` is ISO-8601,
# compared LEXICOGRAPHICALLY by the repark rule below. Render it here, once, in UTC: a shell-side
# `date -r` would be the second spelling of one conversion and the two would drift.
try:
    rows = json.load(open(sys.argv[1])).get("rows") or []
except Exception:
    rows = []
for r in rows:
    state = "TEAMMATE" if r.get("teammate") else (r.get("state") or "")
    ep = r.get("resets_at")
    ep = int(ep) if isinstance(ep, (int, float)) and ep else 0
    iso = datetime.fromtimestamp(ep, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ") if ep else ""
    print("\t".join([(x or "-") for x in
                     (str(r.get("sid") or ""), state, str(r.get("group") or ""),
                      str(r.get("cap") or ""), iso, str(ep or ""),
                      str(r.get("cwd") or ""), str(r.get("cfg") or ""))]
                    + ["1" if r.get("recoverable_by_waiting") else "0"]))
PY
  # `-` FOR EMPTY, from the emitter, because TAB is IFS *whitespace*: `IFS=$'\t' read` collapses
  # a run of tabs and drops trailing empties, so a row with no cap and no reset would shift every
  # column left of it and this loop would park the wrong session at the wrong account.
  while IFS=$'\t' read -r sid state acct cap reset_iso reset_ep cwd cfg wait_ok; do
    [[ -n "$sid" ]] || continue
    for _f in cap reset_iso reset_ep cwd cfg; do
      [[ "${!_f}" == "-" ]] && printf -v "$_f" '%s' ""
    done
    [[ "$reset_ep" == "0" ]] && reset_ep=""
    case "$state" in
      TEAMMATE)
        if [[ ! -f "$STATE/teammate-skip/$sid" ]]; then
          mkdir -p "$STATE/teammate-skip"; : > "$STATE/teammate-skip/$sid"
          log "SKIP  $sid — teammate session (lead-owned recovery) [census]"
        fi
        continue ;;
    esac
    # NOT RECOVERABLE BY WAITING is a different fact from "not yet resettable", and only the
    # census carries it. A Fable / monthly-spend cap has no reset to wait for, so parking one
    # creates a record §2 can never discharge — it would sit in `parked/` forever, counted as
    # pending recovery, and the operator would never be told why nothing happened. Say it once
    # per tick instead and leave the record unwritten.
    if [[ "$wait_ok" != "1" ]]; then
      log "LIMITED-NOWAIT $sid ($acct, cap=${cap:-unknown}) — no reset to wait for; not parked${reset_iso:+, resets $reset_iso}"
      continue
    fi
    case "$state" in
      RECOVERABLE*|NO-PANE|PANE-REUSED|RESET-PASSED) : ;;
      *) continue ;;                      # RE-ENGAGED, DUPLICATE, RESUMING, CWD-GONE, … : §2's or nobody's
    esac
    [[ -n "$reset_iso" && -n "$cwd" && -d "$cwd" ]] || continue
    # the poller's own cap vocabulary — `kind` is what §2 and lr-select read
    case "$cap" in
      five_hour) kind=session ;; seven_day) kind=weekly ;;
      model_scoped:*) kind=fable ;; *) kind="${cap:-session}" ;;
    esac
    if [[ -f "$RESUMED/$sid.json" ]]; then
      prev=$(jq -r '.reset_at_utc // ""' "$RESUMED/$sid.json" 2>/dev/null || echo "")
      if [[ -n "$prev" && ! "$reset_iso" > "$prev" ]]; then continue; fi
      rm -f "$RESUMED/$sid.json"
      log "REPARK $sid — new limit event (resets $reset_iso > handled ${prev:-unknown}) [census]"
    fi
    if [[ ! -f "$PARKED/$sid.json" ]]; then
      printf '{"sid":"%s","acct":"%s","cfg":"%s","cwd":"%s","kind":"%s","reset_at_utc":"%s","parked_at":"%s"}\n' \
        "$sid" "$acct" "$cfg" "$cwd" "$kind" "$reset_iso" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$PARKED/$sid.json"
      log "PARKED $sid ($acct, $kind) resets $reset_iso  cwd=$cwd [census]"
    fi
    printf '%s\t%s\t%s\n' "$acct" "${cap:-unknown}" "${reset_ep:-0}" >> "$_cj.groups"
  done < <(python3 "$_pyf" "$_cj")
  rm -f "$_pyf"
  return 0
}

# ── 1. DETECT — ONE census per tick, then the transcript walk as backstop ──────────────
# THE CENSUS IS ASKED ONCE, FOR ALL ACCOUNTS. Per-account calls were the obvious shape and are
# the wrong one: the census memoizes `ps`, the registry and the marker read across every account
# in a single process, so four calls pay that four times AND can disagree with each other — a
# session that moved between two of them appears twice or not at all. One call, one instant.
#
# THE TRANSCRIPT WALK BELOW STAYS, for one release. It is the backstop while this path earns its
# place: the census is marker- and parked-driven, so a session whose marker was GC'd (file-mtime
# keyed) but whose transcript is still on disk is seen only by the walk. Both write the SAME
# `$PARKED/<sid>.json` shape and both guard on `[[ ! -f ]]`, so whichever runs first wins and the
# other is a no-op — they cannot double-park.
CC_LIMITED_BIN="${CC_LIMITED:-$LR/../../bin/cc-limited}"
if [[ -x "$CC_LIMITED_BIN" && "${LR_POLLER_NO_CENSUS:-0}" != 1 ]]; then
  _cj=$(mktemp "${TMPDIR:-/tmp}/lrp-census.XXXXXX")
  if "$CC_LIMITED_BIN" --all --json > "$_cj" 2>/dev/null; then
    lrp_census_ingest "$_cj"
    # THE RE-SURFACE PAGE, damped on STATE and never on a log grep. One page per
    # (account, cap, resetsAt, count): the same cap still holding an hour later is the same
    # fingerprint and is suppressed until page-damp's TTL lets it re-assert (a condition that
    # stops re-asserting is indistinguishable from a resolved one), while a NEW cap or a changed
    # count is a new fingerprint and pages at once. A `grep poller.log` would have keyed on the
    # log's own history, which is a record of what we SAID, not of what is TRUE.
    if [[ -s "$_cj.groups" ]] && [[ -f "$LR/../../hooks/lib/page-damp.sh" ]]; then
      # shellcheck source=/dev/null
      . "$LR/../../hooks/lib/page-damp.sh" 2>/dev/null || true
      if declare -F damp_should_send >/dev/null 2>&1; then
        while IFS=$'\t' read -r g_acct g_cap g_ep g_n; do
          [[ -n "$g_acct" ]] || continue
          if CC_PAGE_DAMP_TTL_S="${CC_PAGE_DAMP_TTL_S:-1800}" \
             damp_should_send "lr-limited" "$g_acct:$g_cap:$g_ep:$g_n"; then
            log "PAGE  $g_n session(s) on $g_acct still held by $g_cap (resets $g_ep)"
            lrp_bounded osascript -e "display notification \"$g_acct: $g_n session(s) held by $g_cap\" with title \"lr-reset-poller\"" >/dev/null 2>&1 || true
          fi
        done < <(sort "$_cj.groups" | uniq -c | awk '{ print $2 "\t" $3 "\t" $4 "\t" $1 }')
      fi
    fi
  else
    log "CENSUS-SKIP cc-limited exited non-zero — this tick runs on the transcript walk alone"
  fi
  rm -f "$_cj" "$_cj.groups"
  # ── THE REAPER: a claim that produced nothing, NAMED ─────────────────────────────────
  # A claim is this daemon's own promise that a recovery is in flight, and a claim whose process
  # is gone blocks the next attempt at that sid for as long as it sits there. `--persist` writes
  # the fault; the log line is what makes it visible without running the census by hand.
  # `|| [ -n "$_fl" ]`: `read` returns non-zero on a final line with no trailing newline, so the
  # plain form DROPS it — and a reaper reporting exactly one dead claim emits exactly that shape.
  while IFS= read -r _fl || [ -n "$_fl" ]; do
    case "$_fl" in *CLAIMED-NOT-LIVE*) log "CLAIMED-NOT-LIVE ${_fl#*CLAIMED-NOT-LIVE }" ;; esac
  done < <("$CC_LIMITED_BIN" --reaper --persist 2>/dev/null || true)
fi

# ── 1a. DETECT (BACKSTOP) + LEDGER parked sessions — the transcript walk ───────────────
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
    # DRAINED, not `grep -q` (2026-08-27). Under `set -o pipefail` an early-exiting last stage
    # closes the pipe on its FIRST match, the stage before it dies of SIGPIPE, pipefail promotes
    # that to the pipeline status, and the `if` reads a genuine match as NO MATCH. This file was
    # invisible to scripts/pipefail-sigpipe-lint.sh — its heredoc tracker latched on the comment at
    # :357 that names `python3 - <<PY` and never unlatched — so these four sites had never been
    # judged and the file carries no allowlist row. This one is the worst of them: it is THREE
    # stages, and an inversion here reads a genuine monthly-spend kill as absent and the session is
    # never recovered.
    #
    # ⚠️ THE CEILING ABOVE USED TO BE STATED AS "`tail -c 20000` — a hard-coded constant ABOVE the
    # 17,427 B floor", AND BOTH HALVES OF THAT WERE THE WRONG QUANTITY (corrected 2026-08-28).
    #   · 17,427 B is not a floor. On identical producer bytes it reads 0/200 at 13 B per line and
    #     43-54/200 at 55 and 149 B; the sibling "ALWAYS from 23,227" is RACY at 137-149/200.
    #   · The binding quantity is what the stage FEEDING grep emits, not what the producer writes —
    #     22,000 producer bytes held constant across six cells, varying only the middle stage's
    #     reduction, reads 279/400 wrong at 18,000 emitted and 0/400 at 15,600.
    #     (Method and full table: the header of scripts/pipefail-sigpipe-lint.sh, the SSOT.)
    # So the number that governs THIS site is what `grep -iE "$SPEND_RE"` hands the last stage, and
    # `tail -c 20000` is only its upper bound. MEASURED over the whole corpus rather than reasoned
    # about — 7,445 transcripts across all four account stores, 2026-08-28
    # (~/.claude/autonomy/feed257.sh): 262 transcripts' tails match SPEND_RE at all, and the largest
    # hands the last stage 19,466 B — 97.3% of the 20,000 B tail. THE FILTER BARELY FILTERS HERE,
    # because a JSONL tail is a handful of very long records and a matching one matches wholesale.
    # 19,466 B emitted sits INSIDE the racy band, so the old comment reached the right conclusion
    # for the wrong reason and the margin it implied does not exist. ⚠️ DO NOT GENERALISE THE RATIO:
    # scripts/postland-verify.sh:3359 measures the same shape reducing ~55x, this one reduces 1.03x.
    # The reduction ratio is a per-site property and it must be measured, never inferred from shape.
    # The site is safe TODAY only because the last stage is drained (`>/dev/null`, reads to EOF);
    # that spelling is what is load-bearing here, not any headroom.
    if printf '%s' "$tail_bytes" | grep -iE "$SPEND_RE" | grep '"isApiErrorMessage"[[:space:]]*:[[:space:]]*true' >/dev/null; then
      lrp_is_teammate "$tx"; _tm=$?
      if [ "$_tm" -eq 2 ]; then
        log "SKIP  $sid — teammate test UNREADABLE (predicate rc!=0); not resuming on a non-verdict"
        continue
      fi
      if [ "$_tm" -eq 0 ]; then
        if [[ ! -f "$STATE/teammate-skip/$sid" ]]; then
          mkdir -p "$STATE/teammate-skip"; : > "$STATE/teammate-skip/$sid"
          log "SKIP  $sid — teammate session (lead-owned recovery)"
        fi
        continue
      fi
      spend_cwd=$(cwd_of "$tx")
      # AUTHORITATIVE, and one fork rather than two plus a whole session audit. lr-audit ruled here
      # only because it owned the predicate; now that the predicate is its own module the shim
      # answers the same question directly off the tail, and answers it about the LAST api-error
      # record — which is the cap the session is actually sitting on.
      if [[ "$(lrp_cap_of "$tx")" == "monthly_spend" ]]; then
        open_spend_packet "$sid" "$acct" "$spend_cwd"
        continue
      fi
      log "SKIP  $sid ($acct) — spend envelope present but the predicate found no monthly_spend cap; falling through"
    fi
    # cheap pre-filter: a genuine limit line near the tail (isApiErrorMessage confirmed by lr-audit).
    # The envelope conjunct is part of the PRE-filter, not just lr-audit's job (2026-07-25): the
    # limit-recover skill description quotes "You've hit your session/weekly limit" verbatim and
    # ships in every session's skill_listing, so the bare text matched universally and paid for an
    # lr-audit subprocess on EVERY session, EVERY tick. lr-audit still rules on the verdict below.
    # STRUCTURAL, not textual (W4 step 2). `"error":"rate_limit"` is T1 — measured equivalent to
    # apiErrorStatus 429 in both directions, 490/490 — and it is strictly BETTER than the prose
    # grep it replaces in both directions at once: it sees the model-scoped and billing caps the
    # `(session|weekly)` alternation was blind to, and it cannot match the limit-recover skill
    # description, which quotes the TEXT into every session's skill_listing but carries no
    # structured error field. The envelope conjunct stays: it is what keeps this a record test.
    printf '%s' "$tail_bytes" | grep -E '"error"[[:space:]]*:[[:space:]]*"rate_limit"' \
      | grep '"isApiErrorMessage"[[:space:]]*:[[:space:]]*true' >/dev/null || continue
    # teammate sessions (implicit-team assignees carry "agentName" on their early
    # records; leads never do) are recovered by their LEAD via the team-aware
    # lr-audit — a bare --resume here would detach them from team semantics
    # (inbox/agentName wiring) and duplicate the lead's respawn.
    lrp_is_teammate "$tx"; _tm=$?
    if [ "$_tm" -eq 2 ]; then
      log "SKIP  $sid — teammate test UNREADABLE (predicate rc!=0); not resuming on a non-verdict"
      continue
    fi
    if [ "$_tm" -eq 0 ]; then
      if [[ ! -f "$STATE/teammate-skip/$sid" ]]; then
        mkdir -p "$STATE/teammate-skip"; : > "$STATE/teammate-skip/$sid"
        log "SKIP  $sid — teammate session (lead-owned recovery)"
      fi
      continue
    fi
    # already running, OR a fresh claim from an in-flight spawn chain (see FIRE CLAIM above)
    sid_claimed "$sid" && continue
    # …but a `--resume` process that is itself sitting on this limit in a LIVE pane is the session to
    # WAKE, not proof it recovered (D1.15): skipping it here meant no parked record, so §2's wake
    # never saw it. Only a live registry row qualifies — without one, §2 could only spawn a duplicate.
    if pgrep -f "resume $sid" >/dev/null 2>&1; then
      { command -v lr_registry_live_rows >/dev/null 2>&1 && lr_registry_live_rows "$sid" >/dev/null 2>&1 && lrp_still_limited "$tx"; } || continue
    fi
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
# A KIND WITH A RESET, never an allowlist of kind names. The old tuple could not even be
# satisfied by 'fable' — lr-audit never emitted that spelling — so it was a three-name list doing
# the work of one question, and every cap it did not name was dropped in silence. A cap that
# carries a reset is exactly the set a TIMER can recover; the others are handled above or by the
# operator.
es=[e for e in es if e.get('resets_at_utc')]
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
  # -H: ~/.claude-next/projects is a SYMLINK to ~/.claude/projects, and BSD find does not descend a
  # symlinked starting point without it. Measured 2026-09-10: 0 transcripts without -H, 123 with it —
  # the poller had never detected, parked or resumed a single `next` session (poller.log: 17 next2,
  # 42 next3, 4 next4, 0 next).
  done < <(find -H "$cfg/projects" -maxdepth 2 -name '*.jsonl' -mmin "-$RECENCY_MIN" 2>/dev/null)
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
# DROP LATCHED SIDS FROM CANDIDACY, not from the fire. A latched sid left in the pool would take
# the per-worktree winner slot (MAX_PER_WT=1) from a session that CAN come up, and then be skipped
# at the fire — starving the worktree instead of braking one session. Filtering here is what keeps
# the latch a brake on this sid alone. Format is acct:sid:cwd.
if [[ -n "$sel_input" ]]; then
  _kept=""
  while IFS= read -r _c; do
    [[ -n "$_c" ]] || continue
    _csid="${_c#*:}"; _csid="${_csid%%:*}"
    fire_latched "$_csid" && continue
    # A sid whose ORIGINAL pane is alive is a NUDGE candidate, never a spawn candidate — it must not
    # take the per-worktree winner slot (MAX_PER_WT=1) from a session that genuinely needs a process,
    # for the same reason a latched sid must not. The contest below bounds RESURRECTIONS (the 8.8 GB
    # incident); nudging a pane that is already open creates no process and is not one.
    command -v lr_registry_live_rows >/dev/null 2>&1 && lr_registry_live_rows "$_csid" >/dev/null 2>&1 && continue
    _kept+="$_c"$'\n'
  done <<< "$sel_input"
  sel_input="${_kept%$'\n'}"
fi
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

# ── 2a. REROUTE a parked session BEFORE its reset, the moment another account routes (2026-09-27) ─
# poller.log 2026-09-26T20:55:27Z "PARKED ac0f0123 (next, weekly) resets 2026-09-27T04:00:00Z":
# minutes later next2 fell below its concurrency cap and was routable, but § 2 skipped the record
# until its OWN account's reset and nothing before that looked at any other account, so the session
# sat parked until an operator asked. So each tick, a not-yet-reset record asks the router the
# question lr-fleet asks — `--rank <lane> --recovery`, which is diagnostic and charges nothing
# (only --assign charges, and lr-fleet does that itself) — and if any account OTHER than the parked
# one routes, dispatches the same detached `lr-fleet --one … --target auto` the request lane uses,
# under the same run claim. The record stays: § 2's transplant arm retires it only on proof.
# One rank call per lane per tick; one dispatch per sid per LR_REROUTE_EVERY_MIN.
# Kill: LR_POLLER_REROUTE=off.
# TWO GATES ADDED BY W6b (LIMIT_RECOVER_FLEET_V2 ruling 1, resolutions 8 and 9):
#   · $STATE/autorecover.on is the ONE zero-human switch, and this arm is an unattended move exactly
#     like a hook request, so it is held when the file is absent. It had no such check: on
#     2026-09-29T03:07Z it fired on 415a3aac while that sid's own hook request was HOOK-HELD (and
#     that dispatch failed, rc=128 — the unattended record is 1 move in 5 attempts). ONE summary
#     line per tick names what was held.
#   · a record whose reset is less than LR_REQUEST_STAY_S (900 s) away stays put, the request lane's
#     own stay-near-reset rule: a move minutes before the reset buys nothing and costs a transplant.
REROUTE_EVERY_MIN="${LR_REROUTE_EVERY_MIN:-15}"
[[ "$REROUTE_EVERY_MIN" =~ ^[1-9][0-9]*$ ]] || REROUTE_EVERY_MIN=15
REROUTE_DIR="$STATE/reroute"
_rr_general="" _rr_general_asked=0 _rr_fable="" _rr_fable_asked=0 _rr_n=0
reroute_rank() { # $1=lane → the router's stdout, asked at most once per tick per lane
  local ab="${CC_ACCOUNTS_BIN:-$HOME/bin/claude-accounts}" out
  if [[ "$1" == fable ]]; then
    (( _rr_fable_asked )) || { _rr_fable="$("$ab" --rank fable --recovery --max-wait 3 2>/dev/null || true)"; _rr_fable_asked=1; }
    out="$_rr_fable"
  else
    (( _rr_general_asked )) || { _rr_general="$("$ab" --rank general --recovery --max-wait 3 2>/dev/null || true)"; _rr_general_asked=1; }
    out="$_rr_general"
  fi
  printf '%s\n' "$out"
}
_rr_held=0
reroute_parked() { # $1=sid $2=acct $3=cfg $4=reset epoch → dispatches or does nothing; never fatal
  local sid="$1" acct="$2" cfg="$3" reset_ep="${4:-0}" lane=general tier cand mark rc=0 left
  [[ "${LR_POLLER_REROUTE:-on}" != off ]] || return 0
  (( AUTOFIRE == 1 && DRY == 0 )) || return 0
  if [[ ! -e "$STATE/autorecover.on" ]]; then _rr_held=$(( _rr_held + 1 )); return 0; fi
  if lrp_held_lead "$sid"; then
    [[ -e "$PARKED/$sid.team-noted" ]] || { log "REROUTE-SKIP $sid — held:team, a lead with live members is never moved; it is woken in place at its reset"; : > "$PARKED/$sid.team-noted"; }
    return 0
  fi
  if [[ "$reset_ep" =~ ^[0-9]+$ ]] && (( reset_ep > 0 )); then
    left=$(( reset_ep - $(date +%s) ))
    if (( left > 0 && left < RQ_STAY_S )); then
      log "REROUTE-STAY $sid ($acct) — its account resets in ${left}s (< ${RQ_STAY_S}s); not moved"
      return 0
    fi
  fi
  (( _rr_n < MAX_PER_RUN )) || return 0
  fire_latched "$sid" && return 0
  { pgrep -f "resume $sid" >/dev/null 2>&1 || sid_claimed "$sid"; } && return 0
  # Moved already: § 2's transplant arm owns it from here, and re-driving a transplanted session
  # with no live holder mails a stranded FAILED row on every attempt.
  if command -v lr_transplant_target >/dev/null 2>&1 && lr_transplant_target "$sid" "$cfg" >/dev/null 2>&1; then
    return 0
  fi
  mark="$REROUTE_DIR/$sid"
  if [[ -f "$mark" ]] && [[ -n "$(find "$mark" -mmin -"$REROUTE_EVERY_MIN" 2>/dev/null)" ]]; then
    return 0
  fi
  if command -v lr_tier_from_transcript >/dev/null 2>&1; then
    tier="$(lr_tier_from_transcript "$cfg" "$sid" 2>/dev/null || true)"
    [[ "$tier" == claude-fable-* ]] && lane=fable
  fi
  cand="$(reroute_rank "$lane" | awk -v src="$acct" 'NF >= 2 && $1 != "none" && $1 != src && $2 ~ /^[0-9.eE+-]+$/ { print $1; exit }')"
  [[ -n "$cand" ]] || return 0
  # The fence sits HERE, after the cheap reads and the router answer and before the first thing
  # that touches the sid: a sid with no candidate never takes a launch lock at all.
  lrp_may_act "$sid" reroute || return 0
  run_claim_take "$sid" || { lrp_act_done; return 0; }
  mkdir -p "$REROUTE_DIR" 2>/dev/null; : > "$mark"
  _rr_n=$((_rr_n + 1))
  log "REROUTE $sid — parked on $acct, but $cand routes now ($lane lane); dispatching the recovery DETACHED (target auto)"
  "$FLEET" --one "$sid" --target auto --from-daemon --detach > "$RESULTS/$sid.log" 2>&1 || rc=$?
  if (( rc != 0 )); then
    run_claim_release "$sid"
    log "REROUTE $sid — dispatch failed rc=$rc (nothing started); retried after ${REROUTE_EVERY_MIN}m, see $RESULTS/$sid.log"
  else
    run_claim_handoff "$sid" "$RESULTS/$sid.log"
  fi
  lrp_act_done
  return 0
}

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
  if (( now < reset_epoch )); then                           # reset not reached yet —
    reroute_parked "$sid" "$acct" "$cfg" "$reset_epoch"      # …but another account may route now
    continue
  fi
  _lrp_keep=0
  if ! sid_claimed "$sid" && pgrep -f "resume $sid" >/dev/null 2>&1 \
     && command -v lr_registry_live_rows >/dev/null 2>&1 && lr_registry_live_rows "$sid" >/dev/null 2>&1 \
     && _lrp_tx="$(lrp_tx_of "$cfg" "$sid")" && lrp_still_limited "$_lrp_tx"; then
    _lrp_keep=1   # D1.15: its only `resume <sid>` holder is still limited in a live pane — wake it, below
  fi
  if (( _lrp_keep == 0 )); then
    { pgrep -f "resume $sid" >/dev/null 2>&1 || sid_claimed "$sid"; } && { mv "$pf" "$RESUMED/$(basename "$pf")" 2>/dev/null; rm -f "$PARKED/$sid.notified"; continue; }
  fi
  # ── TRANSPLANTED elsewhere (LIMIT_RECOVER_100P): /limit-recover moved this session to another
  # account and its successor is on disk, so THIS store's copy is retired. Re-firing it here would be
  # refused by lr-fire-resume's tombstone verdict every tick until the fire latch tripped — a loop
  # that reads as an outage. Retire the record instead, once, and say where the session went.
  if command -v lr_transplant_target >/dev/null 2>&1 && _lrp_to="$(lr_transplant_target "$sid" "$cfg")"; then
    # ── RETIRE ONLY ON RECOVERED (W5-A, 2026-09-20) ───────────────────────────────────────────────
    # THE DEFECT. The `mv` below was UNCONDITIONAL on the transplant READ, and the HUSK branch under
    # it logged `HUSK … retire request written` and then FELL THROUGH to that same `mv` — so this
    # daemon retired the very records its own log said it was not retiring. A tombstone or lock says
    # the session MOVED. It says nothing whatever about whether the successor ever took a turn, and
    # a move that produced nothing is exactly the case where the parked record is the only thing
    # that would re-fire the recovery. Retiring on the move alone discards it.
    #
    # TWO INDEPENDENT POSITIVES, EITHER SUFFICIENT, both about the SUCCESSOR and never about the move:
    #   (1) the run's own state log reads RECOVERED — lr_state_current (lr-lib.sh:439), read from the
    #       newest bundle for this sid. This is that function's FIRST production caller in the tree.
    #   (2) a LIVE registry row under the TARGET cfg — lr_registry_live_rows_in_cfg (lr-lib.sh, added
    #       by this wave). The unscoped lr_registry_live_rows cannot serve here: it takes only a sid,
    #       and a live row on the SOURCE account is the HUSK, i.e. the same answer meaning the
    #       opposite thing.
    #
    # ⚠ MEASURED 2026-09-20, AND IT IS A DISAGREEMENT WITH THE PLAN, NOT A BUG HERE: no writer in
    # this tree ever appends the state `RECOVERED`. The live vocabulary is admitted / gate-admitted /
    # submit-token-armed / relaunch-typed / FAILED / FAILED:submit, and only 4 of ~140 sid dirs carry
    # an events.jsonl at all. So leg (1) is INERT today and leg (2) carries the whole gate. Leg (1)
    # stays because it is the predicate the plan specifies and it goes live the day a writer emits
    # it; re-measure with:
    #   jq -r .state $(find ~/.reso/limit-recover -name events.jsonl) | sort -u
    _lrp_recovered=0; _lrp_bundle=""; _lrp_st=""
    # bundle-<ISO8601> sorts lexically == chronologically, so the last glob hit is the newest run.
    for _lrp_b in "$STATE/$sid"/bundle-*; do [ -d "$_lrp_b" ] && _lrp_bundle="$_lrp_b"; done
    if [[ -n "$_lrp_bundle" ]] && command -v lr_state_current >/dev/null 2>&1; then
      _lrp_st="$(lr_state_current "$_lrp_bundle" 2>/dev/null || true)"
      [[ "$_lrp_st" == RECOVERED ]] && _lrp_recovered=1
    fi
    if (( _lrp_recovered == 0 )) && command -v lr_registry_live_rows_in_cfg >/dev/null 2>&1 \
       && lr_registry_live_rows_in_cfg "$sid" "$_lrp_to" >/dev/null 2>&1; then
      _lrp_recovered=1; _lrp_st="live-row-on-target${_lrp_st:+ (log says $_lrp_st)}"
    fi
    if (( _lrp_recovered == 0 )); then
      # LEFT PARKED — and said ONCE per record, not once per tick. This arm is reached on every tick
      # for as long as the record sits here, and an undamped line is the 1,800-identical-lines shape
      # the fire-failure latch above was built to end. The marker is cleared with `.notified` when
      # the record is finally retired, so a later genuine retire still says so.
      if [[ ! -e "$PARKED/$sid.husk-noted" ]]; then
        log "HUSK $sid (run ${_lrp_bundle:-none} state ${_lrp_st:-none}) — moved to $_lrp_to but the successor has neither RECOVERED nor a live row there; record LEFT PARKED"
        : > "$PARKED/$sid.husk-noted" 2>/dev/null || true
      fi
      continue
    fi
    # ── HUSK (W10, § 10): the record is retired, but is the SOURCE PANE still standing? ──────────
    # Retiring the parked record says the successor carries the session. It says nothing about the
    # window the session LEFT, which is alive, shows the old limit error, and is indistinguishable
    # from live work in the operator's display — the state § 10.1 measured on panes 110/126/150 and
    # which `--locate` could not name. The daemon is the right actuator for it: a session's own Bash
    # tool is REFUSED by auto mode's classifier when it acts on a live pane (measured 401 denials in
    # 30 days), and this poller runs outside every session and every classifier.
    #
    # It writes a REQUEST rather than closing anything inline: the close has four proof gates of its
    # own (lr-fleet --retire-husks) and this loop must not grow a second copy of them — two
    # spellings of one predicate is how the fleet and the launcher came to measure different gates
    # in the first place.
    if [ "${LR_HUSK_RETIRE:-on}" != off ] && command -v lr_husk_state >/dev/null 2>&1 \
       && lr_husk_state "$sid" "$cfg" 2>/dev/null; then
      _lrp_hp=""
      if command -v lr_registry_live_rows >/dev/null 2>&1; then
        _lrp_rows="$(lr_registry_live_rows "$sid" 2>/dev/null || true)"
        _lrp_hp="${_lrp_rows%%$'\n'*}"; _lrp_hp="${_lrp_hp%%$'\t'*}"
      fi
      log "HUSK $sid ($acct) — the session moved to $_lrp_to but its source pane ${_lrp_hp:-?} is still live; retire request written"
      mkdir -p "$STATE/requests" 2>/dev/null || true
      printf '{"kind":"retire-husk","sid":"%s","pane":"%s","cfg":"%s","to":"%s","ts":"%s"}\n' \
        "$sid" "$_lrp_hp" "$cfg" "$_lrp_to" "$(date -u +%FT%TZ)" \
        > "$STATE/requests/retire-husk-$sid.json" 2>/dev/null || true
    fi
    log "TRANSPLANTED $sid ($acct) → $_lrp_to; parked record retired (the successor carries it: ${_lrp_st:-RECOVERED})"
    mv "$pf" "$RESUMED/$(basename "$pf")" 2>/dev/null; rm -f "$PARKED/$sid.notified" "$PARKED/$sid.husk-noted"; continue
  fi
  # LATCHED — leave it PARKED and say nothing. Silence per tick is deliberate: the one LATCHED line
  # at the crossing and the UNLATCHED line at expiry are the whole story, and this daemon has
  # already proved what a per-tick line costs. It must come BEFORE the winner check below, or the
  # sid — filtered out of candidacy above — would fall through to `sel_reason`'s empty answer and be
  # retired as "not selected", which is both a misattribution and a permanent one.
  fire_latched "$sid" && continue
  # ── THE ORIGINAL PANE IS ALIVE: NUDGE IN PLACE, NEVER SPAWN (LIMIT_RECOVER_100P) ───────────────
  # THE 2026-09-09 DEFECT: liveness above is `pgrep -f "resume $sid"`, which is blind to a session
  # launched WITHOUT --resume — every fresh launch. The poller resumed 52e35019 into tmux while pane
  # 616 still held the original process, and one transcript had two writers on one account. The
  # registry row (hooks/session-register.sh) is the store the argv census cannot replace: keyed by
  # pane, names the sid, carries the pid. A live row means the session is sitting at its limit error
  # in a pane the operator can see — the recovery is to TYPE the recovery prompt into THAT pane and
  # prove a fresh assistant turn, not to mint a second process.
  # IT SITS ABOVE THE WINNER CONTEST DELIBERATELY (2026-09-09). It used to sit below, and could
  # therefore never run: lr-select's own liveness census counts a live REGISTRY row as "already
  # running", so the one sid this arm exists for was filtered out of candidacy and retired as
  # `LISTED … already-running` before the nudge was ever reached — the arm was unreachable code and
  # its whole suite red. A live original pane is not a reason to skip the session; it is the reason
  # to type into it. The contest below still bounds every SPAWN.
  if command -v lr_registry_live_rows >/dev/null 2>&1 && _lrp_rows="$(lr_registry_live_rows "$sid")"; then
    if [[ $DRY -eq 1 || "$AUTOFIRE" != "1" ]]; then
      log "LIVE  $sid — original pane $(printf '%s' "$_lrp_rows" | head -1 | cut -f1) is alive (pid $(printf '%s' "$_lrp_rows" | head -1 | cut -f2)); would NUDGE in place, never spawn ($([[ $DRY -eq 1 ]] && echo dry-run || echo notify-only))"
      continue
    fi
    if ! account_has_headroom "$acct"; then log "WAIT  $sid — $acct still capped, retry next tick"; continue; fi
    (( fired >= MAX_PER_RUN )) && { log "CAP   per-run resume cap ($MAX_PER_RUN) reached; deferring rest"; break; }
    lrp_may_act "$sid" nudge || continue
    _lrp_nrc=0; nudge_in_place "$sid" "$cfg" "$_lrp_rows" "$reset_epoch" 1 || _lrp_nrc=$?
    lrp_act_done
    case "$_lrp_nrc" in
      0) mv "$pf" "$RESUMED/$(basename "$pf")" 2>/dev/null; rm -f "$PARKED/$sid.notified" "$PARKED/$sid.draft-paged" "$PARKED/$sid.team-noted"; fired=$((fired+1)) ;;
      2|3) : ;;     # not yet, or held by a person: the record waits, no strike
      *) fire_fail_note "$sid" nudge-failed
         log "ERROR  $sid — nudge into the live pane failed; NOT spawning a duplicate over a live process (retry next tick)" ;;
    esac
    continue
  fi
  # ── A HELD LEAD IS NEVER SPAWNED (D4.8). Its members are live, so a `--resume` in a new pane is a
  # second lead they cannot hear. It continued on its own ⇒ the record retires; otherwise it is
  # paged ONCE and left parked for a person.
  if lrp_held_lead "$sid"; then
    if lr_engaged_after "$cfg" "$sid" "$(lrp_iso "$reset_epoch")"; then
      log "CONTINUED $sid — a held lead took an assistant turn after its reset; record retired"
      mv "$pf" "$RESUMED/$(basename "$pf")" 2>/dev/null; rm -f "$PARKED/$sid.notified" "$PARKED/$sid.team-paged"; continue
    fi
    if [[ ! -e "$PARKED/$sid.team-paged" ]]; then
      : > "$PARKED/$sid.team-paged" 2>/dev/null || true
      lrp_page "held lead" "Team lead ${sid:0:8} ($acct) has live teammates but no live pane to wake after its limit reset. It is never re-spawned; resume it by hand."
    fi
    continue
  fi
  # Not the winner for its worktree → LIST it and retire THIS limit event. Leaving it parked
  # would just re-elect it next tick once the winner is running (already-running filters the
  # winner out) — sprawl at 10-minute cadence. The session is not lost: resume it explicitly by
  # sid, and a genuinely new limit event re-parks it via the REPARK path above.
  if ! printf '%s\n' "$WINNER_SIDS" | grep -x "$sid" >/dev/null; then
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
    # The fence before anything is minted or claimed: a deferred sid leaves no launcher behind.
    lrp_may_act "$sid" resume || continue
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
      lrp_act_done; continue
    fi
    mv "$launcher" "$launcher.sh" && launcher="$launcher.sh"
    # %q for EVERY interpolated value — this file is bash SOURCE, so each field is code until
    # it is quoted as data. The pre-2026-07-30 form spent its one %q on the `/limit-recover`
    # CONSTANT and interpolated the three attacker-reachable fields with %s inside literal
    # double quotes, which is exactly backwards: a `cwd` of `proj$(…)` re-expanded when the
    # launcher ran. %q emits a form that re-reads as the original word, so no field can leave
    # its argv slot. (`$LR` is script-derived, not record-derived, but takes %q too — a bare
    # %s there would break on any space in the install path.)
    # THE TIER RIDES WITH THE RESUME (LIMIT_RECOVER_100P). This launcher used to carry no --model or
    # --effort, so lr-fire-resume fell back to the SSOT default and every unattended recovery of a
    # Fable session silently landed on Opus/max (measured 2026-09-09 on 52e35019: transcript said
    # claude-fable-5-1/xhigh). The transcript is the source of truth; nothing on disk ⇒ no flags,
    # exactly the old behaviour.
    _lrp_tier=""; command -v lr_tier_from_transcript >/dev/null 2>&1 && _lrp_tier="$(lr_tier_from_transcript "$cfg" "$sid" 2>/dev/null || true)"
    _lrp_tm="${_lrp_tier%% *}"; _lrp_te="${_lrp_tier#* }"; [[ "$_lrp_te" == "$_lrp_tier" ]] && _lrp_te=""
    { echo '#!/bin/bash'
      printf 'exec %q %q %q %q' "$LR/lr-fire-resume.sh" "$acct" "$cwd" "$sid"
      [[ -n "$_lrp_tm" ]] && printf ' --model %q' "$_lrp_tm"
      [[ -n "$_lrp_te" ]] && printf ' --effort %q' "$_lrp_te"
      printf ' --prompt %q\n' "/limit-recover"
    } > "$launcher"; chmod +x "$launcher"
    # Claim BEFORE spawning: the claude child does not carry `--resume <sid>` until the
    # launcher→expect→claude chain completes, and until then pgrep cannot see it.
    claim_sid "$sid"
    if mech=$(spawn_resume "$launcher" "$sid" "$cwd" "$acct"); then
      log "RESUMED $sid on $acct (autofire, $mech) — pane opened"
      mv "$pf" "$RESUMED/$(basename "$pf")"; rm -f "$PARKED/$sid.notified"; fired=$((fired+1))
    else
      rm -f "$CLAIMS/$sid" 2>/dev/null || true   # spawn failed ⇒ release immediately, don't wait out the TTL
      fire_fail_note "$sid" spawn-failed          # …but COUNT it: releasing is what makes this re-fire next tick
      # THE LINE MUST DESCRIBE THE RESOLUTION, NOT ASSERT A FACT ABOUT THE BOX. Its predecessor read
      # "no GUI and no tmux" unconditionally, which was FALSE 1,797 times over 24 days — tmux was
      # installed the whole time and only unreachable on the launchd PATH (see the LRP_TMUX_BIN
      # ladder). `tmux=<path>` says the binary resolved and `new-session` itself refused;
      # `tmux=unresolved` says we never found one. Those are different failures with different
      # remedies, and collapsing them is what made this alarm unactionable for three weeks.
      log "ERROR  $sid — resume spawn failed (LR_POLLER_SPAWN=$SPAWN_MECH; tmux=${LRP_TMUX_BIN:-unresolved})"
    fi
    lrp_act_done
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
if (( _rr_held > 0 )); then
  log "REROUTE-HELD $_rr_held parked session(s) not rerouted — $STATE/autorecover.on is absent; the zero-human switch is the operator's to set"
fi
exit 0
