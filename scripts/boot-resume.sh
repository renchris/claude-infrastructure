#!/bin/bash
# boot-resume.sh — P0-10 AGENT HALF: the post-login auto-resume chain (T-P16-2) + boot-delta
# pager (T-P16-7). A RunAtLoad LaunchAgent entrypoint that runs once at GUI login and closes the
# reboot-recovery gap G-P16-1/-4: after a reboot nothing relaunches Claude Code, and the lead
# supervisor's /tmp telemetry is wiped — so previously-open desk sessions sit dead until a human acts.
#
# Each run (idempotent PER BOOT — exactly one page per reboot):
#   1. DETECT the sessions that were live when the box went down, from the first source that has
#      them (the page and the IDL record name which one answered):
#        roster     — the newest ~/.claude/autonomy/reboot-*.roster.json whose sibling .start epoch
#                     falls after the previous boot and before this one (s1-reboot.sh writes both
#                     before a scripted reboot; it is `cc-sessions --json` taken at that moment).
#        tombstones — ~/.claude/autonomy/shutdown-tombstones/*.json, written by
#                     hooks/session-deregister.sh when a session dies by signal (reason=other). The
#                     last BURST before this boot is the shutdown; see the DETECT block.
#        registry   — the old rule, now the fallback for a hard power loss, where no SessionEnd ran:
#                     a ~/.claude/cc-registry row whose startedAt predates the boot and whose
#                     transcript was written within 24h of it.
#      WHY THE ORDER (measured at the 2026-09-30 15:24 scripted reboot): a GRACEFUL shutdown runs
#      every session's SessionEnd hook, which used to DELETE its registry row, so the registry held
#      only 11 stale crash ghosts from earlier days, overlap 0 with the 20 sessions that were live.
#      The registry rule is right only for the one case where no hook ran at all.
#   2. DECIDE: the boot-epoch marker dedups multiple logins within one boot; the POSTURE mode is the
#      OPERATOR's reboot-posture call (this is "reboot posture is operator; resume code is agent"):
#        page   (DEFAULT) — page the delta once, do NOT resume. Ruling #1 (supervisor PAGES, never
#                 auto-recovers) is the safe default → this is the DoD's "or pages once if deferred".
#        resume — check each session's ownership (boot-resume-launch.sh --check-only), classify it
#                 (bin/cc-resume-classify.py: INTERRUPTED / AT-REST / UNKNOWN), open them all through
#                 cc-resume-layout.sh --desktops (<=4 panes per native-fullscreen OS window, one
#                 macOS Desktop each), start the keepalive scoped to the INTERRUPTED rows only (under
#                 restore v2: no keepalive — an inbox note per session and a launch-argument prompt
#                 for the rows with open work, see step 2b), then
#                 page a summary. AT-REST and UNKNOWN sessions are restored and never nudged — they
#                 stopped at a pause point on purpose. Operator opts in.
#   3. ACT + LOG: always emit ONE {fired|abstained|failed} IDL record (abstention-logged, B-3). A
#      delta with no reachable desk role does not drain to nobody (a17 S-7) — it falls back to a
#      channel that needs NO address: the full page is written to <state>/undelivered-<boot>.page and
#      filed as an operator-blocked `cc-backlog needs` row, and ONLY THEN is the boot marked. If that
#      durable filing also fails, the original fail-loud stands: do NOT mark, exit 4, retry.
#      WHY THE FALLBACK EXISTS (backlog cae796cb1bfb, measured at the 2026-08-25 00:16 reboot): the
#      no-role branch used to fail loud and never mark, which is the right POLARITY over the wrong
#      CHANNEL — its loudness is a stderr line under launchd that no human reads, so an unbounded
#      retry is a SILENT one. Five identical `failed / no-desk-role` records in 21 min (07:45→08:06),
#      each computing n_open=8 correctly, none delivered, and nothing surfaced until a human happened
#      to look. The delta was right every time; only the address was missing. The class is that
#      cc-roles/desk has exactly ONE writer (bin/desk-register / `cc-roles claim`, both MANUAL) and a
#      DELETER (autonomy-sweep expires it as stale), so after a sweep or a reboot nothing re-creates
#      it. Not cured by having desk-brief-inject claim the role at SessionStart: desk is singular and
#      every session runs that hook, so the wrong pane would claim it.
#      WHY `cc-backlog needs` AND NOT THE .page CHANNEL (the item proposed either; they are not
#      equivalent today): autonomy-sweep drains $CC_PAGES_DIR in phase `1-collect-pages-alarms`,
#      which its own in-tree measurement records as STARVED — `stopped_before` names that phase 35 of
#      49 self-bound ticks (scripts/autonomy-sweep.sh § 0a-i). A page stamp is a channel that mostly
#      does not land. A `needs` row is born blocked, kicks no dispatch (so it cannot spawn into the
#      boot storm this script already guards against), and is rendered at every session close.
#
#   0. HEARTBEAT (W3 P3a-i, 2026-10-04): every tick first records the live fleet into
#      ~/.claude/autonomy/heartbeat/<bootuuid>/<kitty-pid>/ (scripts/lib/restore-heartbeat.sh). After a
#      hard power-off the newest heartbeat, at most one tick old, is the roster: it competes with the
#      alarm roster by start epoch, so it outranks a roster taken hours before. Registry rows that
#      started after the heartbeat's tick are added, since they were live at the cut too. Live without
#      the restore-v2 flag: without it a power-off restores at most 4 sessions (the registry cap).
#      A SCRIPTED reboot (2026-10-13): alarm-reboot-prep.sh takes that same heartbeat itself, at its own
#      start epoch and with the kitty tree checked, so the heartbeat is the source and restore v2
#      replays the arrangement the operator had (cc-resume-layout.sh --restore, LAYOUT FIDELITY). A tree
#      the prep could not vouch for carries hb.layout-degraded and is not replayed: plain rows instead.
#      The prep also saves each pane's unsent prompt-box text; restore v2 types it back into the pane
#      its session came back in, after the layout and the prompts, and never submits it (step 5 below,
#      scripts/lib/reboot-drafts.sh).
#
# EVENT MODE: --event <epoch> --kind restart|crash [--kitty-pid K] [--roster-dir D] [--plan-only]
#   A restore inside the running boot (a kitty restart or crash; reached through cc-restore). The
#   event epoch stands in for the boot, the roster is the heartbeat only (D, default the newest
#   heartbeat dir; for --kind crash the newest whose kitty is dead, or <this boot>/K with
#   --kitty-pid), and its done-marker is <state>/events/<K-or-epoch>.done. It never reads the boot
#   identity check and never writes last-boot-epoch or last-boot-uuid, so the next reboot is still
#   detected. --kind restart takes a fresh heartbeat first. --plan-only prints the roster, the
#   retired sessions and the rows the layout would get, then exits 0 having launched nothing.
#
# RESTORE V2 (W3 P3a-ii): every event, and a reboot while <state>/restore-v2 exists (never created
#   here; deleting it is the off switch). A recycle retires its predecessor once its successor is
#   found; each row takes its account from its newest transcript and its model, effort and permission
#   mode from its last real records; the layout gets row-contract columns 6-11 and --restore; the
#   launches start at once with the per-launch load term off (load per core is logged, never waited
#   on: 15-40 per core is this machine's design point); a launched-once
#   ledger (<state>/events/<id>/launched, fed by the layout's map lines) keeps a later round from
#   opening a sid twice; rows on accounts at their weekly limit are restored and never nudged; the
#   event is marked done only once nothing was shed or its deadline (counted from the event's first
#   run, <event>/started) has passed. It pages as soon as the layout returns and follows up once the
#   prompts are confirmed, to the reboot's owner session, else the desk role, else a live lead role.
#
# REBOOT RESUME PERFECTION (2026-10-21; docs/research/reboot-resume-2026-10-21/REPORT.md R1-R20):
#   the classifier reads up to the true cut (<event>/cut: the restored sessions' shutdown tombstone
#   burst, else their newest pre-boot transcript write, else the heartbeat tick) instead of the last
#   tick; the reboot prep's owner session (reboot-<date>.owner) is passed as --owner; a RETIRED row
#   (a self-close that was under way) is never relaunched and is named in the page; each pane's
#   unread mail is carried to its session before the layout; held sessions are logged to
#   <event>/held.log and an Agent Teams member's lead is told to respawn it; a heartbeat is taken
#   right after the layout and at exit.
#
# KITTY PAGES (W3 P5), on every tick of an already-handled boot, after the heartbeat. Neither one ever
#   restarts or relaunches anything: a deliberate quit cannot be told from a crash, and a crash
#   cluster would loop. Each files one operator row and pages the desk once per kitty pid.
#     crash — a kitty with a heartbeat this boot is gone, and no <state>/events/<pid>.done says its
#             fleet was restored. Its last heartbeat is copied to <state>/events/<pid>/hb/<pid>/ and
#             the row carries `cc-restore --after-crash --kitty-pid <pid>`.
#     deaf  — the main kitty's accept queue is full AND `sample` shows no KittyPeerMon thread
#             (scripts/lib/kitty-queue.sh, the detector handoff-fire.sh uses). Remote control is
#             dead, the sessions are still working. Same row title as handoff-fire's stuck-kitty row,
#             so one wedge is one row. The page carries `cc-restore --restart-kitty --confirm <pid>`
#             and says to wait while load per core is over the restore start gate.
# PLAN MODE (W3 P5): while <state>/restore-v2.plan exists (never created here), a tick of an
#   already-handled boot also writes what a v2 restore of the live fleet would do to
#   <state>/events/boot-<boot>/plan.txt, once per touch of that file. Nothing is launched. The
#   operator reads it and renames the file to restore-v2 to turn the reboot path on.
#
# C10: this is machinery the OPERATOR loads via launchd (launchd/com.claude.boot-resume.plist,
# RunAtLoad, shipped UNLOADED). The agent never loads launchd. Activation + rollback + the posture
# switch: docs/activation/boot-resume-activate-snippet.md.
#
# Env (config + tests): CC_REGISTRY_DIR · CC_ROLES_DIR · CC_IDL · CC_BOOT_RESUME_STATE_DIR ·
#   CC_BOOT_RESUME_MODE (page|resume; else <state>/mode; else page) · CC_BOOTTIME_OVERRIDE (sec) ·
#   CC_NOTIFY_BIN · CC_RESUME_LAUNCH_BIN · CC_KEEPALIVE_BIN · CC_LAUNCHCTL_BIN · CC_KEEPALIVE_INTERVAL ·
#   CC_BACKLOG_BIN (the no-role durable fallback; a test MUST stub it or it writes the live ledger) ·
#   CC_BOOT_RESUME_ROSTER_DIR · CC_SHUTDOWN_TOMB_DIR · CC_BOOT_RESUME_TOMB_BURST (s, default 120) ·
#   CC_RESUME_LAYOUT_BIN · CC_RESUME_CLASSIFY_BIN · CC_KITTY_SOCKET_BIN · CC_OPEN_BIN ·
#   CC_BOOT_RESUME_KITTY_TRIES / _KITTY_POLL (wait for a kitty to come up; tests set POLL=0) ·
#   CC_TEARDOWN_DIR (self-close markers) · CC_BOOT_RESUME_SKIP_RETIRED (off = resume a session that
#   closed itself on purpose too) · CC_BOOT_RESUME_ACTIVITY_TAIL (transcript lines read, default 4000) ·
#   restore v2: CC_HANDOFF_LOG · CC_ACCOUNTS_BIN · CC_RESTORE_EXHAUSTED_PCT (100) · CC_RESTORE_DEADLINE_S
#   (1800 after the event's first run) · CC_RESTORE_NOW · CC_BOOT_RESUME_META_TAIL (1500) ·
#   CC_RESTORE_CONFIRM_S (90, wall clock) · CC_RESTORE_CONFIRM_CMD (test seam for rn_confirm) ·
#   CC_RESTORE_REBIND_BIN · CC_MAILBOX_LIB (hooks/lib/mailbox-pending.sh; CC_MAILBOX_DIR via it) ·
#   CC_TASKPOLICY_BIN (/usr/sbin/taskpolicy; the same-boot tick's demotion) · kitty pages:
#   CC_BOOT_RESUME_PS_BIN (/bin/ps) · CC_RESTORE_BIN (the cc-restore the pages name) ·
#   CC_HF_NETSTAT_FILE · CC_KQ_SAMPLE_BIN · CC_KITTY_WEDGED_QUEUE_N · CC_BOOT_RESUME_KITTY_PAGES=off.
# BSD+GNU portable, no eval, fail-loud. bash 3.2-safe.
set -uo pipefail

REGISTRY_DIR="${CC_REGISTRY_DIR:-$HOME/.claude/cc-registry}"
ROLES_DIR="${CC_ROLES_DIR:-$HOME/.claude/cc-roles}"
IDL="${CC_IDL:-$HOME/.claude/autonomy/idl.jsonl}"
STATE_DIR="${CC_BOOT_RESUME_STATE_DIR:-$HOME/.claude/autonomy/boot-resume}"
KEEPALIVE_INTERVAL="${CC_KEEPALIVE_INTERVAL:-240}"

usage() { sed -n '2,/^set -uo/p' "$0" | sed 's/^# \{0,1\}//; /^set -uo/d'; }
case "${1:-}" in -h|--help) usage; exit 0 ;; esac

# ── event mode arguments, parsed before BOOT is read (see EVENT MODE in the header). ──
EVENT=""; EVENT_KIND=""; EVENT_KPID=""; EVENT_ROSTER_DIR=""; PLAN_ONLY=0
if [ "${1:-}" != --print-boottime ]; then
  while [ $# -gt 0 ]; do
    case "$1" in
      --event)      EVENT="${2:-}"; shift 2 || shift ;;
      --kind)       EVENT_KIND="${2:-}"; shift 2 || shift ;;
      --kitty-pid)  EVENT_KPID="${2:-}"; shift 2 || shift ;;
      --roster-dir) EVENT_ROSTER_DIR="${2:-}"; shift 2 || shift ;;
      --plan-only)  PLAN_ONLY=1; shift ;;
      *) echo "boot-resume: unknown argument '$1' (see --help)" >&2; exit 2 ;;
    esac
  done
  if [ -n "$EVENT$EVENT_KIND$EVENT_KPID$EVENT_ROSTER_DIR" ] || [ "$PLAN_ONLY" = 1 ]; then
    case "$EVENT" in ''|*[!0-9]*) echo "boot-resume: --event needs an epoch" >&2; exit 2 ;; esac
    case "$EVENT_KIND" in restart|crash) ;; *) echo "boot-resume: --kind must be restart or crash" >&2; exit 2 ;; esac
    case "$EVENT_KPID" in *[!0-9]*) echo "boot-resume: --kitty-pid needs a pid" >&2; exit 2 ;; esac
  fi
fi

command -v jq >/dev/null 2>&1 || { echo "boot-resume: jq required" >&2; exit 1; }

now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }
# R20: a local clock stamp on each line of a log this job keeps (one perl, not a date per line).
ts_lines() {
  if [ -x /usr/bin/perl ]; then /usr/bin/perl -MPOSIX -ne 'BEGIN { $| = 1 } print strftime("%H:%M:%S ", localtime), $_'
  else cat; fi
}

# Shared helpers (consolidation audit 02): resolve_bin lived here AND in autonomy-sweep.sh, already drifted.
# Resolution ladder mirrors the hooks/lib house idiom: beside-script → CFG → ~/.claude.
_ccl="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/lib/cc-common.sh"
[ -f "$_ccl" ] || _ccl="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/scripts/lib/cc-common.sh"
[ -f "$_ccl" ] || _ccl="$HOME/.claude/scripts/lib/cc-common.sh"
# shellcheck source=lib/cc-common.sh
# shellcheck disable=SC1091  # runtime-resolved source; the ship gate runs shellcheck without -x
if ! . "$_ccl" 2>/dev/null; then
  # Fail LOUD: this is a launchd job, and silently proceeding with unresolved helper paths is the
  # silent-degradation failure mode these scripts exist to avoid.
  echo "boot-resume: FATAL — cannot source $_ccl (resolve_bin unavailable)" >&2
  exit 1
fi
# The heartbeat (step 0). Missing is loud, not fatal: the reboot path still has its other sources.
_hbl="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/lib/restore-heartbeat.sh"
[ -f "$_hbl" ] || _hbl="$HOME/.claude/scripts/lib/restore-heartbeat.sh"
# shellcheck source=lib/restore-heartbeat.sh
# shellcheck disable=SC1091  # runtime-resolved source; the ship gate runs shellcheck without -x
. "$_hbl" 2>/dev/null || echo "boot-resume: ⚠ cannot source $_hbl — no heartbeat this run" >&2
heartbeat() { command -v hb_tick >/dev/null 2>&1 || return 0; hb_tick >/dev/null || true; }
# Recovery delivery (restore v2 only). Missing is loud, not fatal: the fleet still comes back, with
# no note and no prompt, and the page says so.
_rnl="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/lib/restore-note.sh"
[ -f "$_rnl" ] || _rnl="$HOME/.claude/scripts/lib/restore-note.sh"
# shellcheck source=lib/restore-note.sh
# shellcheck disable=SC1091  # runtime-resolved source; the ship gate runs shellcheck without -x
. "$_rnl" 2>/dev/null || echo "boot-resume: ⚠ cannot source $_rnl — no restore notes this run" >&2
# The deaf-kitty detector, shared with handoff-fire.sh (one detector, never two). Missing = no deaf page.
_kql="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/lib/kitty-queue.sh"
[ -f "$_kql" ] || _kql="$HOME/.claude/scripts/lib/kitty-queue.sh"
# shellcheck source=lib/kitty-queue.sh
# shellcheck disable=SC1091  # runtime-resolved source; the ship gate runs shellcheck without -x
. "$_kql" 2>/dev/null || echo "boot-resume: ⚠ cannot source $_kql — no deaf-kitty page this run" >&2
# The unsent drafts the reboot prep saved (restore v2 only). Missing = the drafts stay on disk, untyped.
_rdl="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/lib/reboot-drafts.sh"
[ -f "$_rdl" ] || _rdl="$HOME/.claude/scripts/lib/reboot-drafts.sh"
# shellcheck source=lib/reboot-drafts.sh
# shellcheck disable=SC1091  # runtime-resolved source; the ship gate runs shellcheck without -x
. "$_rdl" 2>/dev/null || echo "boot-resume: ⚠ cannot source $_rdl — saved drafts are not typed back this run" >&2
NOTIFY="$(resolve_bin "${CC_NOTIFY_BIN:-}" cc-notify)"
# The addressless fallback for a delta with no desk role (see step 3 in the header). Resolved
# here rather than at the use site so an unresolvable cc-backlog is a KNOWN-empty string on the
# one path that reads it, never a bare name hitting the launchd PATH (/usr/bin:/bin).
BACKLOG="$(resolve_bin "${CC_BACKLOG_BIN:-}" cc-backlog)"
LAUNCH="$(resolve_bin "${CC_RESUME_LAUNCH_BIN:-}" boot-resume-launch.sh boot-resume-launch.sh)"
# The batch opener (by default a 2x2 per native-fullscreen Desktop; under --restore, which restore
# v2 passes, one row of up to 6 panes per window) and the nudge classifier. Both live in bin/;
# resolve_bin's ../bin rung finds them from scripts/. An absent layout falls back to one window per
# session through $LAUNCH (the pre-2026-09-30 path); an absent classifier makes every row UNKNOWN,
# which is the fail-safe direction (restored, never nudged).
LAYOUT="$(resolve_bin "${CC_RESUME_LAYOUT_BIN:-}" cc-resume-layout.sh)"
CLASSIFY="$(resolve_bin "${CC_RESUME_CLASSIFY_BIN:-}" cc-resume-classify.py)"
KSOCK_BIN="$(resolve_bin "${CC_KITTY_SOCKET_BIN:-}" cc-kitty-socket)"
# R8: re-binds roles and forwards named by the old pane numbers, right after the layout. Under a bats
# harness only an explicit seam runs (it claims roles and writes forwards in the live stores).
REBIND=""
if [ -n "${CC_RESTORE_REBIND_BIN:-}" ] || [ -z "${BATS_TEST_FILENAME:-}${BATS_TEST_TMPDIR:-}${BATS_VERSION:-}" ]; then
  REBIND="$(resolve_bin "${CC_RESTORE_REBIND_BIN:-}" cc-restore-rebind)"
fi
# R3: the mailbox library whose mailbox_migrate carries a pane's mail to its session.
MAILBOX_LIB="${CC_MAILBOX_LIB:-$(cd "$(dirname "$0")" 2>/dev/null && pwd)/../hooks/lib/mailbox-pending.sh}"
[ -f "$MAILBOX_LIB" ] || MAILBOX_LIB="$HOME/.claude/hooks/lib/mailbox-pending.sh"
OPEN_BIN="${CC_OPEN_BIN:-/usr/bin/open}"
ROSTER_DIR="${CC_BOOT_RESUME_ROSTER_DIR:-$HOME/.claude/autonomy}"
TOMB_DIR="${CC_SHUTDOWN_TOMB_DIR:-$HOME/.claude/autonomy/shutdown-tombstones}"
TOMB_BURST="${CC_BOOT_RESUME_TOMB_BURST:-120}"

# ── machine-capacity admission (MACHINE_CAPACITY_V2 §12.1 / §12.4) lives in the LAUNCHER. ──────
# §12.4 called this script a LATENT BOMB in precise terms: it resumes at GUI login, i.e. INTO the
# boot storm — measured loadavg 346 at boot+2 min, decaying to 89 within 90 s — and it had no
# capacity term at all. Its operator consequence, verbatim: *"activating boot-resume as-is converts
# 'the box crashed' into 'the box crashes, reboots, and fires 4 Opus-max sessions into a load-346
# storm, ungated.'"*
#
# The term is in `boot-resume-launch.sh`, not here, because that is the seam that ACTUALLY spawns
# (opens the window, runs reso-resume-one) and it has a second caller — the resume-sessions skill's
# hand path. Gating the spawn point covers both; gating here would cover one and would have to be
# re-derived for the other. This script's job is to read the launcher's rc 9 and keep a SHED ghost
# distinct from a FAILED one (see the fire loop below).
# ── the shared resume-selection decision point (session-sprawl consolidation, 2026-07-21).
#    Without it this loop fires one session PER GHOST — the incident shape (14 sessions, one
#    project, 2.76 GB RSS). resolve_bin's search does not reach the limit-recover subdir. ──
SELECT="${CC_RESUME_SELECT_BIN:-}"
if [ -z "$SELECT" ]; then
  for cand in "$(dirname "$0")/limit-recover/lr-select.py" \
              "$HOME/.claude/scripts/limit-recover/lr-select.py"; do
    [ -x "$cand" ] && { SELECT="$cand"; break; }
  done
fi
MAX_PER_WT="${CC_BOOT_RESUME_MAX_PER_WORKTREE:-1}"
MAX_TOTAL="${CC_BOOT_RESUME_MAX_TOTAL:-4}"
# ── the ~/.reso fallback, and why it now SPEAKS (backlog 8550b6129d9c, measured 2026-08-12) ──
# resolve_bin's ladder is beside-script → ../bin → $CLAUDE_CONFIG_DIR/bin → ~/.claude/bin → PATH.
# It never reaches ~/.reso/bin, so this second line is what actually resolved the keepalive on this
# box — and for weeks it resolved to an UNTRACKED 2026-07-04 `#!/bin/zsh` copy with a frozen
# worktree list, while the tracked, tested, shellchecked bin/reso-keepalive sat unlinked. The
# landed fix could not execute and the buggy original ran at every boot, silently, because taking a
# fallback looked exactly like taking the primary. install.sh now symlinks the tracked file to this
# path, so the fallback normally resolves to repo code.
# The WARN is the part that survives the next occurrence: a fallback to a path that is NOT a symlink
# into the checkout means the deployed copy is nobody's output — outside the ship gate, the linters
# and every reader that could see it rot. Loud, not fatal: resuming the fleet on an old keepalive
# still beats not resuming it (this is a launchd job), so this degrades and says so.
KEEPALIVE="$(resolve_bin "${CC_KEEPALIVE_BIN:-}" reso-keepalive)"
if [ -z "$KEEPALIVE" ] && [ -x "$HOME/.reso/bin/reso-keepalive" ]; then
  KEEPALIVE="$HOME/.reso/bin/reso-keepalive"
  if [ ! -L "$HOME/.reso/bin/reso-keepalive" ]; then
    echo "boot-resume: ⚠ keepalive resolved to an UNTRACKED copy at $KEEPALIVE (not a symlink into the checkout) — it is outside the ship gate and may be arbitrarily stale. Run install.sh to link the tracked bin/reso-keepalive." >&2
  fi
fi
LAUNCHCTL="${CC_LAUNCHCTL_BIN:-launchctl}"

# ABSOLUTE default, matching scripts/capacity-alarm.sh:276 — com.claude.boot-resume.plist's PATH
# stops at /usr/bin:/bin and sysctl lives in /usr/sbin, so the bare name resolves in the operator's
# shell and nowhere the job actually runs. boottime() swallows the failure with 2>/dev/null, which
# is the fail-open polarity this whole lint exists for: an unreachable sysctl reads as "no boot
# time" rather than as an error. Probe rather than hardcode so a box without /usr/sbin still
# resolves; the CC_SYSCTL_BIN seam is unchanged and still wins.
SYSCTL="${CC_SYSCTL_BIN:-}"
if [ -z "$SYSCTL" ]; then
  for _c in /usr/sbin/sysctl /sbin/sysctl; do [ -x "$_c" ] && { SYSCTL="$_c"; break; }; done
  # No `command -v sysctl` tail: that spelling puts the bare name back at command position, which is
  # the very finding this fix clears, and it would resolve against the same PATH that lacks it.
  [ -n "$SYSCTL" ] || SYSCTL=/usr/sbin/sysctl
fi
# ── boottime (sec). sysctl prints `{ sec = NNN, usec = NNN } <date>`. Anchor on the LEADING `{ sec = `
#    — a bare `.*sec = ` GREEDILY matches `usec = ` and captures the usec field (the wrong number). ──
boottime() {
  if [ -n "${CC_BOOTTIME_OVERRIDE:-}" ]; then printf '%s' "$CC_BOOTTIME_OVERRIDE"; return 0; fi
  "$SYSCTL" -n kern.boottime 2>/dev/null | sed -n 's/^{ sec = \([0-9][0-9]*\).*/\1/p'
}
# ── boot IDENTITY. kern.boottime is wall-clock minus uptime, so a clock step moves it: on 2026-10-02
#    a network drop and the NTP re-sync after it moved this boot from 1790799966 to 1790799965, the
#    exact-match marker read that as a NEW boot, and the job replayed a two-day-old roster into 15
#    panes on accounts those sessions had long left ("No conversation found" x7). kern.bootsessionuuid
#    is minted once per boot and no clock touches it, so it is the identity; the epoch stays the
#    WINDOW anchor below. An override epoch with no override uuid reads as "no uuid", so a test that
#    simulates a new boot is never vetoed by the real machine's uuid. ──
bootuuid() {
  if [ -n "${CC_BOOTUUID_OVERRIDE+x}" ]; then printf '%s' "$CC_BOOTUUID_OVERRIDE"; return 0; fi
  [ -n "${CC_BOOTTIME_OVERRIDE:-}" ] && return 0
  "$SYSCTL" -n kern.bootsessionuuid 2>/dev/null | tr -d '[:space:]'
}
# Epoch fallback for a marker written before the uuid existed (or a box that cannot read it): the
# same boot within ±N s, the rule compressor-sentinel.sh's freeze_boot_already learned from the same
# jitter. Two real boots are a whole uptime apart, never a minute.
BOOT_EPOCH_TOLERANCE="${CC_BOOT_EPOCH_TOLERANCE:-60}"

RECENCY_WINDOW="${CC_BOOT_RESUME_RECENCY_WINDOW:-86400}"   # 24h
# ── transcript_mtime <account> <sid> <cwd> → epoch secs of the session's transcript LAST write, or "".
#    A session open at the reboot has a transcript written just before boottime (resume-sessions rule);
#    this is what separates the true open set from accumulated CRUFT — crashed sessions that died
#    without a SessionEnd deregister and linger in the durable registry (81 such were live on this
#    machine at build time). find -print -quit is ~0.01s per lookup (measured). ──
transcript_mtime() {
  if [ -n "${CC_TRANSCRIPT_MTIME_BIN:-}" ]; then "$CC_TRANSCRIPT_MTIME_BIN" "$1" "$2" "$3" 2>/dev/null; return 0; fi
  local cfg="$HOME/.$1" path
  [ -d "$cfg/projects" ] || return 0
  # A GLOB, not `find`: a session transcript is always projects/<slug>/<sid>.jsonl, one level down.
  # The recursive find walked every subagent file under every project and, at login under launchd's
  # LowPriorityIO, kept this job running for more than 17 minutes on 2026-09-30. The glob costs one
  # stat per project directory, and it follows the ~/.claude-next/projects symlink on its own.
  for path in "$cfg"/projects/*/"$2".jsonl; do
    [ -f "$path" ] && { stat -f %m "$path" 2>/dev/null; return 0; }
  done
}

# ── config-dir basename (registry `account` field) → reso-resume-one account alias. ──
# .claude and .claude-next are the SAME account (mirror) → next (accounts.json's "next" entry
# declares "claude" as an alias for exactly this). Unknown → echo raw (reso rejects loud). Backed
# by the accounts.json-generated map (any N accounts) — see lib/account-map.generated.sh.
# shellcheck source=/dev/null
for _CC_AM in "${CC_ACCOUNT_MAP:-}" "$(dirname "$0")/../lib/account-map.generated.sh" "$HOME/.claude/lib/account-map.generated.sh"; do
  [ -n "$_CC_AM" ] && [ -f "$_CC_AM" ] && { source "$_CC_AM"; break; }
done
map_account() { # <config-basename>
  local r; r="$(cc_acct_name_for_dir_basename "$1")"
  [ -n "$r" ] && printf '%s' "$r" || printf '%s' "$1"
}

# ── posture mode: env → <state>/mode → default page (ruling #1 safe default). ──
resolve_mode() {
  local m="${CC_BOOT_RESUME_MODE:-}"
  [ -z "$m" ] && [ -f "$STATE_DIR/mode" ] && m="$(tr -d '[:space:]' < "$STATE_DIR/mode" 2>/dev/null)"
  case "$m" in resume) printf 'resume' ;; *) printf 'page' ;; esac
}

BOOT="$(boottime)"
MODE="$(resolve_mode)"
SOURCE=""; SOURCE_LABEL=""
BOOT_MARKER="$STATE_DIR/last-boot-epoch"
MARKER="$BOOT_MARKER"
UUID_MARKER="$STATE_DIR/last-boot-uuid"
BOOT_UUID="$(bootuuid)"
# Event mode: the event epoch is the anchor and its own marker is the idempotency record. The boot
# markers above are READ (the previous boot bounds the roster window) and never written.
if [ -n "$EVENT" ]; then
  BOOT="$EVENT"; MODE=resume
  MARKER="$STATE_DIR/events/${EVENT_KPID:-$EVENT}.done"
fi
# ── RESTORE V2 (W3 P3a-ii): the restore-v2 behaviour — recycle successors retire their predecessor,
#    the account/model/effort/permission mode come from the newest transcript, contract columns 6-11,
#    the launched-once ledger, account headroom and the restore capacity mode. An event is always
#    v2; a reboot is v2 only while <state>/restore-v2 exists (deleting it is the off switch). Nothing
#    here ever creates that file. EVENT_DIR holds the event's ledger, map lines and load log. ──
RESTORE_V2=0
{ [ -n "$EVENT" ] || [ -f "$STATE_DIR/restore-v2" ]; } && RESTORE_V2=1
HB_HI="$BOOT"   # the newest heartbeat start a restore may take (a restart's own tick may pass BOOT)
EVENT_ID="${EVENT_KPID:-$EVENT}"; [ -n "$EVENT" ] || EVENT_ID="boot-$BOOT"
EVENT_DIR="$STATE_DIR/events/$EVENT_ID"

case "${1:-}" in --print-boottime) printf '%s\n' "$BOOT"; exit 0 ;; esac

log_idl() { # <disposition> <extra-json>
  mkdir -p "$(dirname "$IDL")" 2>/dev/null || true
  printf '{"ts":"%s","tool":"boot-resume","disposition":"%s","boot":"%s","mode":"%s","source":"%s","retired_skipped":%s%s}\n' \
    "$(now_iso)" "$1" "$BOOT" "$MODE" "$SOURCE" "${n_retired:-0}" \
    "${EVENT:+,\"event\":$EVENT,\"kind\":\"$EVENT_KIND\",\"plan_only\":$([ "$PLAN_ONLY" = 1 ] && echo true || echo false)}${2:-}" \
    >> "$IDL" 2>/dev/null || true
}

# ── guard: unreadable boottime is a blind check → abstain LOUD, never mark, never act. ──
if [ -z "$BOOT" ]; then
  log_idl abstained ',"reason":"no-boottime"'
  echo "boot-resume: could not read kern.boottime — abstaining" >&2
  exit 0
fi

# ── idempotency: this boot already handled → exactly-one-page invariant. ──
same_boot() { # rc 0 when the markers say this boot was already handled
  local mu me d
  mu="$(tr -d '[:space:]' < "$UUID_MARKER" 2>/dev/null)"
  # Both uuids readable → they alone decide, in BOTH directions: a differing uuid is a new boot even
  # when the epochs sit close together.
  if [ -n "$BOOT_UUID" ] && [ -n "$mu" ]; then [ "$mu" = "$BOOT_UUID" ]; return; fi
  me="$(tr -d '[:space:]' < "$BOOT_MARKER" 2>/dev/null)"
  case "$me" in ''|*[!0-9]*) return 1 ;; esac
  d=$((BOOT - me)); [ "$d" -lt 0 ] && d=$((-d))
  [ "$d" -le "$BOOT_EPOCH_TOLERANCE" ]
}
# ── KITTY PAGES + PLAN MODE (W3 P5; see the header). Run on the ticks of an already-handled boot. ──
PS_BIN="${CC_BOOT_RESUME_PS_BIN:-/bin/ps}"
RESTORE_BIN="${CC_RESTORE_BIN:-$HOME/.claude/bin/cc-restore}"
_kp_under_bats() { [ -n "${BATS_TEST_FILENAME:-}${BATS_TEST_TMPDIR:-}${BATS_VERSION:-}" ]; }
kitty_pid_alive() { # <pid> → rc 0 when that pid is a running kitty (a reused pid is not)
  local c; c="$("$PS_BIN" -o comm= -p "$1" 2>/dev/null)"; c="${c%%$'\n'*}"
  [ "${c##*/}" = kitty ]
}
page_desk() { # <message> — best effort; the backlog row is the durable half
  local t=""
  [ -f "$ROLES_DIR/desk" ] && t="$(head -1 "$ROLES_DIR/desk" 2>/dev/null | tr -d '[:space:]')"
  [ -n "$t" ] && [ -n "$NOTIFY" ] && cc_run "$NOTIFY" "$t" "$1" >/dev/null 2>&1
  return 0
}
crash_page() {
  local root uuid d kp n ev bid step
  command -v hb_root >/dev/null 2>&1 || return 0
  root="$(hb_root)"; uuid="$(_hb_bootuuid 2>/dev/null)"
  [ -d "$STATE_DIR/restore.lock" ] && return 0          # a restore is running: its kitty died on purpose
  for d in "$root/${uuid:-nouuid}"/*; do
    kp="${d##*/}"
    case "$kp" in 0|''|*[!0-9]*) continue ;; esac
    [ -f "$d/hb.roster.json" ] || continue
    kitty_pid_alive "$kp" && continue
    ev="$STATE_DIR/events/$kp"
    { [ -e "$ev.done" ] || [ -e "$ev/crash-paged" ]; } && continue
    n="$(jq 'if type == "array" then length else 0 end' "$d/hb.roster.json" 2>/dev/null)"
    case "$n" in ''|*[!0-9]*) n=0 ;; esac
    mkdir -p "$ev/hb" 2>/dev/null || continue
    # The last good heartbeat, kept with the event: the heartbeat root is pruned after 7 days.
    [ -d "$ev/hb/$kp" ] || cp -R "$d" "$ev/hb/$kp" 2>/dev/null || true
    if [ "$n" -eq 0 ]; then : > "$ev/crash-paged"; continue; fi   # nothing was live in it: nothing to restore
    step="restart kitty (pid $kp is gone): $n session(s) were live in it at its last heartbeat and nothing has restored them. If you quit it on purpose, ignore this; otherwise run the command."
    bid=""
    [ -n "$BACKLOG" ] && bid="$(cc_run "$BACKLOG" needs "$step" --class needs-human --run "$RESTORE_BIN --after-crash --kitty-pid $kp" \
        --falsifier "test -e $ev.done" --project claude-infrastructure 2>/dev/null | tail -1 | tr -d '[:space:]')"
    case "$bid" in ''|*[!0-9a-f]*) bid="" ;; esac
    page_desk "💥 kitty $kp is gone and $n session(s) went with it. Nothing was relaunched (a quit and a crash look the same). To restore them: $RESTORE_BIN --after-crash --kitty-pid $kp   (preview: add --dry-run)"
    log_idl fired ",\"reason\":\"kitty-crash-page\",\"kitty_pid\":$kp,\"n_open\":$n,\"resumed\":0,\"backlog_id\":\"$bid\""
    # Marked only once the row is filed, so a tick where cc-backlog was unreachable tries again.
    [ -n "$bid" ] && : > "$ev/crash-paged"
  done
  return 0
}
deaf_page() {
  local kp sock why nc l1 per hold=""
  command -v kq_deaf >/dev/null 2>&1 || return 0
  # Under a bats harness the real netstat and sample are never run: the capture seam must be set.
  if _kp_under_bats && [ -z "${CC_HF_NETSTAT_FILE:-}" ]; then return 0; fi
  [ -n "$KSOCK_BIN" ] && [ -x "$KSOCK_BIN" ] || return 0
  for kp in $(CC_KQ_PS_BIN="$PS_BIN" kq_main_kitty_pids); do
    [ -e "$STATE_DIR/deaf-$kp.paged" ] && continue
    # This kitty's own socket, from the one resolver every launchd path uses (it opens no connection:
    # a connect to a deaf kitty would only add one more entry to the queue being measured).
    sock="$(cc_run "$KSOCK_BIN" --all 2>/dev/null | sed -n "s|^unix:\\(.*-$kp\\)\$|\\1|p")"; sock="${sock%%$'\n'*}"
    [ -n "$sock" ] || continue
    why="$(kq_deaf "$sock" "$kp")" || continue
    nc="$("$SYSCTL" -n hw.ncpu 2>/dev/null | tr -d '[:space:]')"; case "$nc" in ''|*[!0-9]*|0) nc=1 ;; esac
    l1="$("$SYSCTL" -n vm.loadavg 2>/dev/null | tr -d '{}' | awk '{ print $1 }')"
    per="$(awk -v l="$l1" -v n="$nc" 'BEGIN { if (l !~ /^[0-9.]+$/) print "?"; else printf "%.2f", l / n }')"
    # Never "wait until load is under": at the standing 15-40 per core that wait has no end, and the
    # restore itself no longer waits for load either (R4, 2026-10-21) — it logs one reading and starts.
    [ "$per" != "?" ] && hold=" Load per core is $per: restart anyway. The restore does not wait for load to fall, so waiting by hand gains nothing."
    # The SAME step, class and falsifier as handoff-fire.sh's stuck-kitty row, so one wedge is one row.
    [ -n "$BACKLOG" ] && cc_run "$BACKLOG" needs "restart kitty (control socket stuck: queue full)" --class needs-human \
        --falsifier "test ! -S $sock" >/dev/null 2>&1
    page_desk "🔇 kitty $kp is deaf: its remote control is dead ($why). The sessions in it are STILL WORKING; only new panes, recycles and handoffs are blocked, and only a restart clears it.${hold} Preview: $RESTORE_BIN --restart-kitty --dry-run   ·   restart and restore: $RESTORE_BIN --restart-kitty --confirm $kp"
    log_idl fired ",\"reason\":\"kitty-deaf-page\",\"kitty_pid\":$kp,\"n_open\":0,\"resumed\":0"
    mkdir -p "$STATE_DIR" 2>/dev/null && : > "$STATE_DIR/deaf-$kp.paged"
  done
  return 0
}
plan_mode() { # restore-v2.plan: what a v2 restore of the live fleet would do, written once per touch
  local flag="$STATE_DIR/restore-v2.plan" out="$EVENT_DIR/plan.txt"
  [ -f "$flag" ] || return 0
  [ -f "$out" ] && [ ! "$flag" -nt "$out" ] && return 0
  mkdir -p "$EVENT_DIR" 2>/dev/null || return 0
  # A second run of this script, in event mode: an event is always v2, bypasses same_boot() and never
  # writes the boot markers, and --plan-only launches nothing. It plans from the tick just taken.
  if "$0" --event "${CC_RESTORE_NOW:-$(date +%s)}" --kind restart --plan-only > "$out.tmp" 2>&1; then mv -f "$out.tmp" "$out"
  else { echo "boot-resume: the v2 plan run failed:"; cat "$out.tmp"; } > "$out" 2>/dev/null; rm -f "$out.tmp"; fi
  return 0
}
kitty_pages() {
  [ "${CC_BOOT_RESUME_KITTY_PAGES:-on}" != off ] || return 0
  crash_page; deaf_page; plan_mode
}

# ── STEP 0, the heartbeat. Every tick of an already-handled boot takes it here, before the exit. The
#    first run of a NEW boot takes it after DETECT instead: cc-sessions sweeps registry rows of dead
#    sessions started over 24 h ago, and on that run those rows are the registry fallback's evidence.
#    Event mode bypasses same_boot() entirely (an event is not a boot); it has its own marker. ──
if [ -n "$EVENT" ]; then
  if [ "$PLAN_ONLY" = 0 ] && [ -f "$MARKER" ]; then
    log_idl abstained ',"reason":"already-processed","n_open":0,"resumed":0'
    exit 0
  fi
  # A planned restart is restored from the fleet as it is NOW. A crash is not: the fleet is gone,
  # and a tick would only record the new kitty. The tick is stamped when it runs, which is after the
  # event epoch the caller took, so the pick's upper bound (HB_HI) moves to the tick's own clock —
  # without that, a restart could never restore from the snapshot it just took (measured
  # 2026-10-05: hb.start 1791179255 against an event of a few seconds before, rc 3 no-heartbeat).
  if [ "$EVENT_KIND" = restart ]; then
    heartbeat
    _hb_now="${CC_HB_NOW:-$(date +%s)}"
    [ "$_hb_now" -gt "$HB_HI" ] 2>/dev/null && HB_HI="$_hb_now"
  fi
elif same_boot; then
  # R5 (2026-10-21): the routine tick of an already-handled boot is housekeeping, so it alone runs in
  # the utility band. The plist no longer demotes the job: a demoted RESTORE ranked below every claude
  # process (priority 20 against 31), a glob took 24-46 s instead of 3.4 s, and the 2026-10-21 restore
  # took 88 minutes. Re-run once, by interpreter path (a #! exec leaks kernel memory on 15.x), with a
  # marker so the re-run does not re-exec again. No taskpolicy(8) ⇒ run here as before.
  if [ -z "${CC_BOOT_RESUME_DEMOTED:-}" ]; then
    _tp="${CC_TASKPOLICY_BIN-/usr/sbin/taskpolicy}"
    _kp_under_bats && [ -z "${CC_TASKPOLICY_BIN:-}" ] && _tp=""
    if [ -n "$_tp" ] && [ -x "$_tp" ]; then
      export CC_BOOT_RESUME_DEMOTED=1
      exec "$_tp" -c utility /bin/bash "$0"
    fi
  fi
  heartbeat
  kitty_pages
  log_idl abstained ',"reason":"already-processed","n_open":0,"resumed":0'
  # Backfill the uuid on a pre-uuid marker, so the next clock step is decided by the uuid.
  if [ -n "$BOOT_UUID" ] && [ ! -s "$UUID_MARKER" ]; then
    printf '%s\n' "$BOOT_UUID" > "$UUID_MARKER" 2>/dev/null || true
  fi
  exit 0
fi

# ── TSV field-collapse guard — docs/research/TSV_FIELD_COLLAPSE_2026-07-25.md ──────────────────
# Tab is IFS-*whitespace*, so `IFS=$'\t' read` collapses a RUN of tabs and ANY empty cell shifts
# every later field one position LEFT — silently, with a zero exit status. This bites the ghost
# scan hard: `.account` and `.name` are absent on plenty of registry entries, so an entry with no
# account read cwd as the account, sid as the cwd and name as the sid — `[ -n "$g_sid" ]` then
# passed on the NAME, and transcript_mtime was called with all three arguments wrong, so the
# session failed its recency test and was never resumed. A reboot silently dropping the sessions
# it exists to bring back. Padded at the emitter (the only durable fix — `//` produces the ""),
# and re-padded into GHOSTS because GHOSTS is itself re-read with `IFS=$'\t' read` twice below.
TSV_PAD=$'\037'
pad()   { [ -n "$1" ] && printf '%s' "$1" || printf '%s' "$TSV_PAD"; }
unpad() { [ "$1" = "$TSV_PAD" ] || printf '%s' "$1"; }

# ── DETECT (see the header for why the sources are tried in this order). Every source yields the
#    same rows: "<config-acct>\t<cwd>\t<sid>\t<name>\t<branch>", padded (see TSV_PAD above).
#    ANCHOR is the moment the sessions died — the classifier's crash anchor. For a graceful reboot
#    that is the SHUTDOWN, not the boot: after an overnight power-off the boot is hours later, and
#    against it every session would read as long at rest and none would be nudged. ──
# shellcheck disable=SC2016  # a jq program: $pad is jq's variable, not the shell's
JQ_CELL='def cell: (if . == null then "" else . end) | tostring
                   | gsub("[\\t\\r\\n]"; " ") | if . == "" then $pad else . end;'
GHOSTS=""
n_open=0
ANCHOR="$BOOT"
REG_NEW_MAX=0
add_row() { # <acct> <cwd> <sid> <name> <branch>, each already padded
  GHOSTS="${GHOSTS}$1	$2	$3	$4	$5
"
  n_open=$((n_open + 1))
}
read_rows() { # <tsv> → add_row per line (cells arrive padded from jq)
  local r_acct r_cwd r_sid r_name r_br
  while IFS=$'\t' read -r r_acct r_cwd r_sid r_name r_br _; do
    [ -n "$r_sid" ] && [ "$r_sid" != "$TSV_PAD" ] || continue
    add_row "$r_acct" "$r_cwd" "$r_sid" "$r_name" "$r_br"
  done <<ROWS
$1
ROWS
}

# The window a source must fall in: after the PREVIOUS boot (this script's own marker, when it ran
# then) and never more than RECENCY_WINDOW before this one — a roster from three reboots ago is
# history, not the set that was live.
LOWER=$((BOOT - RECENCY_WINDOW))
prev_boot="$(tr -d '[:space:]' < "$BOOT_MARKER" 2>/dev/null)"
case "$prev_boot" in
  ''|*[!0-9]*) ;;
  *) [ "$prev_boot" -lt "$BOOT" ] && [ "$prev_boot" -gt "$LOWER" ] && LOWER="$prev_boot" ;;
esac

# 1. roster — the newest of two snapshots of `cc-sessions --json`: the one a scripted reboot takes
#    (alarm-reboot-prep.sh) and the heartbeat every tick takes (step 0). A roster that parses and
#    lists nobody is an answer ("nothing was live"), so it ends the search; one that does not parse
#    is not, so the search goes on. `.start` is read as the FIRST FIELD OF THE FIRST LINE: until
#    2026-10-04 the prep script appended its kalloc reading as a second line, which made every alarm
#    roster unreadable here. A start EQUAL to the anchor counts (an event anchored on its own tick).
roster=""; roster_start=0
# What answered, for restore v2: the roster files read (their paneUUID finds a recycle's successor),
# the heartbeat dirs (their kitty tree gives columns 8-9) and their hb.session.tsv rows.
SRC_FILES=""; HB_DIRS=""; HB_META=""
if [ -z "$EVENT" ]; then
  for f in "$ROSTER_DIR"/reboot-*.roster.json; do
    [ -f "$f" ] || continue
    st="$(head -n 1 "${f%.roster.json}.start" 2>/dev/null | awk '{ print $1 }')"
    case "$st" in ''|*[!0-9]*) continue ;; esac
    { [ "$st" -gt "$LOWER" ] && [ "$st" -le "$BOOT" ] && [ "$st" -gt "$roster_start" ]; } || continue
    roster="$f"; roster_start="$st"
  done
fi
# The heartbeat candidate: "<start>\t<dir>" per directory of the newest tick in the window.
HB_ROOT="$(command -v hb_root >/dev/null 2>&1 && hb_root)"
hb_base="${EVENT_ROSTER_DIR:-$HB_ROOT}"
hb_flag=""
if [ -n "$EVENT" ] && [ -z "$EVENT_ROSTER_DIR" ]; then
  if [ -n "$EVENT_KPID" ]; then
    # The uuid the heartbeat itself keys on, so the path is the one hb_tick wrote.
    hb_uuid="$(command -v _hb_bootuuid >/dev/null 2>&1 && _hb_bootuuid)"
    hb_base="$HB_ROOT/${hb_uuid:-nouuid}/$EVENT_KPID"
  elif [ "$EVENT_KIND" = crash ]; then
    hb_flag=--dead-kitty
  fi
fi
hb_sel=""; hb_start=0
if [ -n "$hb_base" ] && command -v hb_pick >/dev/null 2>&1; then
  hb_sel="$(hb_pick "$hb_base" "$LOWER" "$HB_HI" $hb_flag)" || hb_sel=""
  [ -n "$hb_sel" ] && hb_start="$(printf '%s\n' "$hb_sel" | head -n 1 | cut -f1)"
fi
if [ -n "$hb_sel" ] && [ "$hb_start" -ge "$roster_start" ]; then
  # The sessions that STARTED after the tick were live at the cut too; only the registry knows them.
  reg_new="$(for t in "$REGISTRY_DIR"/*.json; do
               [ -f "$t" ] && jq -c 'select(type == "object")' "$t" 2>/dev/null
             done | jq -cs --argjson lo "$hb_start" --argjson hi "$BOOT" --arg k "$EVENT_KPID" '
               [ .[] | select((.session_id // "") != "" and ((.startedAt // 0) | type) == "number"
                              and (.startedAt / 1000) > $lo and (.startedAt / 1000) <= $hi)
                     | select($k == "" or ((.kitty_pid // ($k | tonumber)) | tostring) == $k) ]' 2>/dev/null)"
  [ -n "$reg_new" ] || reg_new='[]'
  hb_files=""; hb_sess=""; hb_dirs=""
  while IFS=$'\t' read -r _st hd; do
    [ -n "$hd" ] || continue
    hb_files="${hb_files}${hd}/hb.roster.json
"
    hb_dirs="${hb_dirs}${hd}
"
    hb_sess="${hb_sess}$(cat "$hd/hb.session.tsv" 2>/dev/null)
"
  done <<EOF
$hb_sel
EOF
  # Branch (column 5) from the heartbeat's own git read when the roster row carries none.
  # shellcheck disable=SC2016  # a jq program
  if rows="$(printf '%s' "$hb_files" | tr '\n' '\0' | xargs -0 cat 2>/dev/null \
        | jq -rs --arg pad "$TSV_PAD" --argjson reg "$reg_new" --arg sess "$hb_sess" "$JQ_CELL"'
          ($sess | split("\n") | map(split("\t")) | map(select(length >= 6 and .[0] != ""))
             | map({key: .[0], value: (if .[5] == $pad then "" else .[5] end)}) | from_entries) as $br
          | [ (map(if type == "array" then . else (.sessions // []) end) | add // []), $reg ] | add
          | [ .[] | select(type == "object" and (.session_id // "") != "") ]
          | unique_by(.session_id)[]
          | [(.account|cell), (.cwd|cell), (.session_id|cell), (.name|cell),
             ((.branch // $br[.session_id])|cell)] | @tsv')"; then
    n_reg_new="$(printf '%s' "$reg_new" | jq 'length' 2>/dev/null || echo 0)"
    # R1: a row admitted because it started after the tick must be classifiable, so the cut is never
    # earlier than the newest such start (see the CUT block below).
    REG_NEW_MAX="$(printf '%s' "$reg_new" | jq '[.[].startedAt / 1000 | floor] | max // 0' 2>/dev/null)"
    hb_one="$(printf '%s\n' "$hb_sel" | head -n 1 | cut -f2)"
    SOURCE=heartbeat; ANCHOR="$hb_start"
    SRC_FILES="$hb_files"; HB_DIRS="$hb_dirs"; HB_META="$hb_sess"
    SOURCE_LABEL="heartbeat ${hb_one#"${HB_ROOT}"/} at $(date -r "$hb_start" +%H:%M:%S 2>/dev/null || echo "$hb_start")"
    [ "${n_reg_new:-0}" -gt 0 ] && SOURCE_LABEL="${SOURCE_LABEL} + ${n_reg_new} started after it"
    read_rows "$rows"
  fi
fi
if [ -z "$SOURCE" ] && [ -n "$roster" ]; then
  if rows="$(jq -r --arg pad "$TSV_PAD" "$JQ_CELL"'
        [ (if type == "array" then . else (.sessions // []) end)[]
          | select(type == "object" and (.session_id // "") != "") ]
        | unique_by(.session_id)[]
        | [(.account|cell), (.cwd|cell), (.session_id|cell), (.name|cell), (.branch|cell)] | @tsv' \
        "$roster" 2>/dev/null)"; then
    SOURCE=roster; SOURCE_LABEL="roster $(basename "$roster" .roster.json)"; ANCHOR="$roster_start"
    SRC_FILES="$roster"
    read_rows "$rows"
  fi
fi

# 2. shutdown tombstones (hooks/session-deregister.sh). reason=other also fires when the operator
#    closes ONE pane, so a tombstone alone is not a shutdown. What is: the LAST burst before the boot.
#    A shutdown SIGHUPs every pane together (measured: 19 sessions ended inside 4 s at 15:25:27-31
#    on 2026-09-30), while a closed pane is a lone earlier stamp. Where the kernel had already set
#    kern.willshutdown when the hook ran, those tombstones are taken outright instead.
if [ -z "$SOURCE" ] && [ -z "$EVENT" ] && [ -d "$TOMB_DIR" ]; then
  tomb_rows="$(for t in "$TOMB_DIR"/*.json; do
                 [ -f "$t" ] && jq -c 'select(type == "object")' "$t" 2>/dev/null
               done | jq -rs --arg pad "$TSV_PAD" --argjson lo "$LOWER" --argjson hi "$BOOT" \
                     --argjson burst "$TOMB_BURST" "$JQ_CELL"'
        [ .[] | select((.session_id // "") != "" and ((.endedAt // 0) | type) == "number")
              | select(.endedAt > $lo and .endedAt <= $hi) ]
        | (if any(.[]; .hostShutdown == true) then map(select(.hostShutdown == true)) else . end)
        | if length == 0 then empty else
            (map(.endedAt) | max) as $last
            | map(select(.endedAt >= $last - $burst)) | group_by(.session_id) | map(max_by(.endedAt))[]
            | [(.account|cell), (.cwd|cell), (.session_id|cell), (.name|cell), (.branch|cell),
               (.endedAt|tostring)] | @tsv
          end' 2>/dev/null)"
  if [ -n "$tomb_rows" ]; then
    SOURCE=tombstones; SOURCE_LABEL="shutdown tombstones"
    ANCHOR="$(printf '%s\n' "$tomb_rows" | awk -F'\t' '$6 > m { m = $6 } END { print m + 0 }')"
    read_rows "$tomb_rows"
  fi
fi

# An event is restored from a heartbeat or not at all: inside a running boot the registry lists the
# live sessions as well as the dead, and the alarm roster and tombstones describe a reboot.
if [ -n "$EVENT" ] && [ -z "$SOURCE" ]; then
  log_idl failed ',"reason":"no-heartbeat","n_open":0,"resumed":0'
  echo "boot-resume: event ${EVENT} (${EVENT_KIND}): no heartbeat in ${hb_base:-?} between ${LOWER} and ${BOOT} — nothing to restore from" >&2
  exit 3
fi

# 3. registry ghosts — a durable cc-registry row whose process predates this boot (startedAt/1000 <
#    boottime → killed by it) AND whose transcript was written within RECENCY_WINDOW before the
#    boot (excludes long-dead crashed-and-never-deregistered cruft). Only a death with no SessionEnd
#    at all — a power loss, a kernel panic — leaves these, so this is the fallback, never the rule.
if [ -z "$SOURCE" ]; then
  SOURCE=registry; SOURCE_LABEL="registry ghosts"
  if [ -d "$REGISTRY_DIR" ]; then
    for f in "$REGISTRY_DIR"/*.json; do
      [ -e "$f" ] || continue
      row="$(jq -r --arg pad "$TSV_PAD" "$JQ_CELL"'
               [((.startedAt // 0) | cell), (.account | cell), (.cwd | cell),
                (.session_id | cell), (.name | cell)] | @tsv' "$f" 2>/dev/null)" || continue
      [ -n "$row" ] || continue
      IFS=$'\t' read -r started_ms g_acct g_cwd g_sid g_name <<GHOST_ROW
$row
GHOST_ROW
      started_ms="$(unpad "$started_ms")"
      case "$started_ms" in ''|*[!0-9]*) continue ;; esac
      [ "$((started_ms / 1000))" -lt "$BOOT" ] || continue     # live/post-boot session → not a ghost
      [ "$g_sid" != "$TSV_PAD" ] || continue
      mt="$(transcript_mtime "$(unpad "$g_acct")" "$(unpad "$g_sid")" "$(unpad "$g_cwd")")"
      { [ -n "$mt" ] && [ "$mt" -gt "$((BOOT - RECENCY_WINDOW))" ]; } || continue
      add_row "$g_acct" "$g_cwd" "$g_sid" "$g_name" "$TSV_PAD"
    done
  fi
fi

# ── SKIP the sessions that RETIRED ON PURPOSE (2026-10-01). Every source above is a snapshot of
#    who was live at some moment, and nothing asked whether a session closed itself SINCE. Measured:
#    d86e6bd4 ran `handoff-fire.sh self-close --terminal` at 18:43:34Z; about five minutes later a
#    kitty restart resumed it from a roster taken before that, through this script, into a window
#    nobody asked for. The evidence is the teardown marker self-close writes immediately BEFORE it
#    types /exit (handoff-fire.sh write_teardown_marker, <sid>.json, mode terminal|successor) — and
#    it counts only when it is newer than the session's last conversational record. That ordering
#    is the discriminator: a self-close that aborted leaves the session working, so its next tool
#    result post-dates the marker and the session comes back as before. `recycle` relaunches the
#    pane and is not a retirement. File mtime is NOT the activity clock: Claude Code appends
#    untimestamped records (last-prompt, mode, ai-title …) at exit, so the file is always newer
#    than the marker. Missing evidence on either side ⇒ resumed, the pre-2026-10-01 behaviour.
#    Kill switch: CC_BOOT_RESUME_SKIP_RETIRED=off. ──
TEARDOWN_DIR="${CC_TEARDOWN_DIR:-$HOME/.claude/watchdog/teardown}"
transcript_file() { # <config-acct> <sid> → the session's transcript path, or ""
  local d p
  for d in ${1:+"$HOME/.$1"} "$HOME"/.claude*; do
    for p in "$d"/projects/*/"$2".jsonl; do [ -f "$p" ] && { printf '%s' "$p"; return 0; }; done
  done
  return 0
}
last_activity() { # <transcript> → newest user/assistant record time, YYYY-MM-DDTHH:MM:SS (UTC), or ""
  tail -n "${CC_BOOT_RESUME_ACTIVITY_TAIL:-4000}" "$1" 2>/dev/null | jq -Rrn '
    [ inputs | fromjson? | select(type == "object" and (.type == "user" or .type == "assistant")
        and (.timestamp | type) == "string" and (.isMeta | not))
      | select((.message.content // "" | tostring)
               | test("<command-name>/exit</command-name>|<local-command-stdout>") | not)
      | .timestamp[0:19] ] | max // empty' 2>/dev/null
}
retired_marker() { # <sid> → "<mode>\t<ts to the second>\t<pane, padded>" for a self-close marker, else ""
  [ -f "$TEARDOWN_DIR/$1.json" ] || return 0
  # A recycle marker is read only under restore v2, and even then it retires nothing by itself: see
  # recycle_successor below.
  jq -r --arg sid "$1" --arg pad "$TSV_PAD" --argjson v2 "$RESTORE_V2" 'select(type == "object" and .sid == $sid
           and (.mode == "terminal" or .mode == "successor" or ($v2 == 1 and .mode == "recycle"))
           and (.ts | type) == "string")
         | [.mode, .ts[0:19], ((.pane // "") | tostring | if . == "" then $pad else . end)] | @tsv' \
    "$TEARDOWN_DIR/$1.json" 2>/dev/null
}
iso_sec() { case "$1" in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]) return 0 ;; esac; return 1; }
# ── recycle_successor <old sid> <marker ts> <marker pane> <old transcript> → "<sid> (<how>)", or "".
#    Restore v2 only. Main's rule stands — a recycle relaunches the pane and is not a retirement — up
#    to the one case it got wrong: 3a06361f recycled into 90040b85 (pane 6) and a restore then brought
#    3a06361f back too, a duplicate of its own successor beside it (C2-restore-command.md §1). So the
#    old sid is dropped only when handoff-fire logged the recycle as ENGAGED after the marker AND the
#    successor is found. That row carries no successor sid (only target_pane and prev_sid), so the
#    successor is derived, strongest first: a row of the roster being restored in that pane; the
#    pane's registry row, started between the marker and the cut; a transcript in the same project
#    whose first record falls between the marker and the engagement. Nothing found ⇒ kept. ──
HANDOFF_LOG="${CC_HANDOFF_LOG:-$HOME/.claude/logs/handoffs.jsonl}"
recycle_successor() {
  local old="$1" mts="$2" pane="$3" eng ets s f ft
  eng="$(grep -F "\"prev_sid\":\"$old\"" "$HANDOFF_LOG" 2>/dev/null | jq -rs --arg ts "$mts" '
      [ .[] | select(type == "object" and .class == "recycle-engaged" and .engaged == true
                     and (.ts | type) == "string" and .ts[0:19] >= $ts) ]
      | sort_by(.ts) | first // empty | [((.target_pane // "") | tostring), .ts[0:19]] | @tsv' 2>/dev/null)"
  [ -n "$eng" ] || return 0
  ets="${eng#*	}"; [ -n "${eng%%	*}" ] && pane="${eng%%	*}"
  if [ -n "$pane" ] && [ -n "$SRC_FILES" ]; then
    s="$(printf '%s' "$SRC_FILES" | tr '\n' '\0' | xargs -0 cat 2>/dev/null | jq -rs --arg p "$pane" --arg o "$old" '
          [ .[] | (if type == "array" then . else (.sessions // []) end)[]
            | select(type == "object" and ((.paneUUID // "") | tostring) == $p
                     and (.session_id // "") != "" and .session_id != $o) | .session_id ] | first // empty' 2>/dev/null)"
    [ -n "$s" ] && { printf '%s (in the roster, pane %s; recycle-engaged %sZ)' "$s" "$pane" "$ets"; return 0; }
  fi
  if [ -n "$pane" ] && [ -f "$REGISTRY_DIR/$pane.json" ]; then
    s="$(jq -r --arg o "$old" --arg ts "$mts" --argjson hi "$BOOT" '
          select(type == "object" and (.session_id // "") != "" and .session_id != $o
                 and ((.startedAt // 0) | type) == "number"
                 and (.startedAt / 1000) >= (($ts + "Z") | fromdateiso8601) and (.startedAt / 1000) <= $hi)
          | .session_id' "$REGISTRY_DIR/$pane.json" 2>/dev/null | head -n 1)"
    [ -n "$s" ] && { printf '%s (registry row of pane %s; recycle-engaged %sZ)' "$s" "$pane" "$ets"; return 0; }
  fi
  [ -n "$4" ] && [ -f "$4" ] && [ -f "$TEARDOWN_DIR/$old.json" ] || return 0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    s="$(basename "$f" .jsonl)"; [ "$s" != "$old" ] || continue
    ft="$(head -n 50 "$f" 2>/dev/null | jq -Rrn '[inputs | fromjson? | select(type == "object"
            and (.timestamp | type) == "string") | .timestamp[0:19]] | first // empty' 2>/dev/null)"
    iso_sec "$ft" || continue
    { [[ "$ft" < "$mts" ]] || [[ "$ft" > "$ets" ]]; } && continue
    printf '%s (transcript started %sZ; recycle-engaged %sZ)' "$s" "$ft" "$ets"; return 0
  done <<EOF
$(find "$(dirname "$4")" -maxdepth 1 -name '*.jsonl' -newer "$TEARDOWN_DIR/$old.json" 2>/dev/null)
EOF
  return 0
}
RETIRED=""; n_retired=0
ghost_sids() { printf '%s\n' "$GHOSTS" | cut -f3 | grep -v "^${TSV_PAD}\$" | grep . | tr '\n' ' '; }
# R1 (2026-10-21): a session the lead supervisor REAPED (closed after a clean, shipped completion) is
# retired too. Its record is {"actor":"lead-supervisor","kind":"reap","sid":…,"ts":…,"why":…} in the
# IDL, and it counts under the same rule as a self-close marker: only when newer than the session's
# last activity. The newest reap per kept sid, read in one pass. A teardown marker outranks it.
REAPS=""
if [ "${CC_BOOT_RESUME_SKIP_RETIRED:-on}" != off ] && [ "$n_open" -gt 0 ] && [ -f "$IDL" ]; then
  REAPS="$(grep -F '"kind":"reap"' "$IDL" 2>/dev/null | grep -F '"lead-supervisor"' | jq -Rrn --arg sids " $(ghost_sids)" '
      [ inputs | fromjson? | select(type == "object" and .actor == "lead-supervisor" and .kind == "reap"
                                    and (.sid | type) == "string" and (.ts | type) == "string")
        | .sid as $s | select($sids | contains(" " + $s + " ")) ]
      | group_by(.sid) | map(max_by(.ts))[] | [.sid, .ts[0:19], ((.why // "") | tostring | gsub("[\\t\\n]"; " "))] | @tsv' 2>/dev/null)"
fi
if [ "${CC_BOOT_RESUME_SKIP_RETIRED:-on}" != off ] && [ "$n_open" -gt 0 ]; then
  KEPT=""; n_kept=0
  while IFS=$'\t' read -r k_acct k_cwd k_sid k_name k_br; do
    [ -n "$k_sid" ] && [ "$k_sid" != "$TSV_PAD" ] || continue
    r_sid="$(unpad "$k_sid")"; r_acct="$(unpad "$k_acct")"
    mk="$(retired_marker "$r_sid" | head -1)"; rp_why=""
    if [ -z "$mk" ] && [ -n "$REAPS" ]; then
      rp="$(printf '%s\n' "$REAPS" | awk -F'\t' -v s="$r_sid" '$1 == s { print; exit }')"
      [ -n "$rp" ] && { mk="reap	$(printf '%s' "$rp" | cut -f2)	${TSV_PAD}"; rp_why="$(printf '%s' "$rp" | cut -f3)"; }
    fi
    if [ -n "$mk" ]; then
      mk_mode="${mk%%	*}"; mk_rest="${mk#*	}"; mk_ts="${mk_rest%%	*}"; mk_pane="$(unpad "${mk_rest#*	}")"
      tf="$(transcript_file "$r_acct" "$r_sid")"; act=""
      [ -n "$tf" ] && act="$(last_activity "$tf")"
      if iso_sec "$mk_ts" && iso_sec "$act" && [[ "$mk_ts" > "$act" ]]; then
        why="${mk_mode} self-close marker ${TEARDOWN_DIR}/${r_sid}.json at ${mk_ts}Z, after its last activity ${act}Z"
        [ "$mk_mode" = reap ] && why="reaped by the lead supervisor (${rp_why:-no reason recorded}) at ${mk_ts}Z, after its last activity ${act}Z"
        succ=""
        if [ "$mk_mode" = recycle ]; then
          succ="$(recycle_successor "$r_sid" "$mk_ts" "$mk_pane" "$tf")"
          why="recycled into ${succ}, marker ${TEARDOWN_DIR}/${r_sid}.json at ${mk_ts}Z after its last activity ${act}Z"
        fi
        if [ "$mk_mode" != recycle ] || [ -n "$succ" ]; then
          r_alias="$(map_account "$r_acct")"; r_launcher=""
          command -v cc_acct_launcher_for_name >/dev/null 2>&1 && r_launcher="$(cc_acct_launcher_for_name "$r_alias")"
          r_name="$(unpad "$k_name")"; r_cwd="$(unpad "$k_cwd")"
          RETIRED="${RETIRED}  - ${r_name:-${r_sid:0:8}} (${r_sid}): ${why} — to bring it back: cd '${r_cwd:-.}' && ${r_launcher:-claude} --resume ${r_sid}
"
          n_retired=$((n_retired + 1))
          continue
        fi
      fi
    fi
    KEPT="${KEPT}${k_acct}	${k_cwd}	${k_sid}	${k_name}	${k_br}
"
    n_kept=$((n_kept + 1))
  done <<EOF
$GHOSTS
EOF
  GHOSTS="$KEPT"; n_open="$n_kept"
fi
if [ "$n_retired" -gt 0 ]; then
  mkdir -p "$STATE_DIR" 2>/dev/null || true
  printf '%s' "$RETIRED" > "$STATE_DIR/last-retired.txt" 2>/dev/null || true
  printf '%s' "$RETIRED" | sed 's/^  - /boot-resume: skipped retired session /' >&2
fi

# Step 0 for the first run of a new boot: DETECT has read the registry, so the sweep cannot eat it.
[ -z "$EVENT" ] && heartbeat

# ── RESTORE V2 ROW METADATA (W3 P3a-ii; plan § Amendment B gaps 5-8, row contract columns 6-11).
#    A roster says where a session WAS; the transcript says where it went since. So, per kept row:
#    the account is the config dir of its NEWEST transcript (a session that moved accounts comes back
#    on the new one, not the one the roster remembers); model and effort come from its last real
#    assistant record and the permission mode from its last permission-mode record, each falling
#    back to the heartbeat's reading (which itself fell back to the live argv); the branch falls back
#    from the roster to git in the cwd, then to the heartbeat's git read and the transcript's
#    gitBranch when the worktree was reaped; group and slot are the OS window and the order in it,
#    from the heartbeat's kitty tree. META rows: sid acct model effort pm branch group slot, padded. ──
newest_account() { # <sid> <cwd> → "<config basename (no dot) of the newest transcript>\t<newest write at or before CUT_HI>"
  local d b m best="" bm=0 pre=0
  for d in "$HOME"/.claude*; do
    [ -d "$d/projects" ] || continue
    b="${d##*/}"; b="${b#.}"
    m="$(transcript_mtime "$b" "$1" "$2")"
    case "$m" in ''|*[!0-9]*) continue ;; esac
    [ "$m" -gt "$bm" ] && { bm="$m"; best="$b"; }
    # The same reads feed the R1 cut: the session's last write before the machine went down.
    [ "$m" -le "$CUT_HI" ] && [ "$m" -gt "$pre" ] && pre="$m"
  done
  printf '%s\t%s' "$best" "$pre"
}
transcript_meta() { # <transcript> → "model\teffort\tpermission_mode\tbranch", padded
  tail -n "${CC_BOOT_RESUME_META_TAIL:-1500}" "$1" 2>/dev/null | jq -Rrn --arg pad "$TSV_PAD" '
    [inputs | fromjson? | select(type == "object")] as $r
    | ($r | map(select(.type == "assistant" and (.isSidechain | not)
                       and ((.message.model // "") | . != "" and . != "<synthetic>"))) | last) as $a
    | ($r | map(select(.type == "permission-mode")) | last | .permissionMode // "") as $pm
    | [($a.message.model // ""), ($a.effort // ""), $pm,
       (($a.gitBranch // "") | if . == "HEAD" then "" else . end)]
    | map(tostring | gsub("[\\t\\r\\n]"; " ") | if . == "" then $pad else . end) | @tsv' 2>/dev/null
}
tree_slots() { # → "sid\tgroup\tslot" for each roster session found in the heartbeat dirs' kitty trees
  local hd
  while IFS= read -r hd; do
    [ -n "$hd" ] && [ -f "$hd/hb.kitty-ls.json" ] && [ -f "$hd/hb.roster.json" ] || continue
    # A tree the reboot prep marked degraded gives no window groups either: the layout does not
    # replay it, and rows grouped by half of an old arrangement would be a partial one.
    [ -f "$hd/hb.layout-degraded" ] && continue
    jq -r --slurpfile r "$hd/hb.roster.json" --arg kp "${hd##*/}" '
      ($r[0] | if type == "array" then . else [] end
         | map(select(type == "object" and (.session_id // "") != "" and (.paneUUID // "") != "")
               | {key: (.paneUUID | tostring), value: .session_id}) | from_entries) as $m
      | .[]? | .id as $ow
      | [ .tabs[]?.windows[]? | (.id | tostring) | select($m[.] != null) ] | to_entries[]
      | [$m[.value], "k\($kp)w\($ow)", (.key + 1 | tostring)] | @tsv' "$hd/hb.kitty-ls.json" 2>/dev/null
  done <<EOF
$HB_DIRS
EOF
}
team_map() { # → "member sid\tlead sid\tagent name" for each roster session whose pane ran an Agent Teams member
  local hd
  while IFS= read -r hd; do
    [ -n "$hd" ] && [ -f "$hd/hb.kitty-ls.json" ] && [ -f "$hd/hb.roster.json" ] || continue
    # The member's own sid is not in its argv: the window id (= the roster's paneUUID) joins them.
    jq -r --slurpfile r "$hd/hb.roster.json" '
      ($r[0] | if type == "array" then . else [] end
         | map(select(type == "object" and (.session_id // "") != "" and (.paneUUID // "") != "")
               | {key: (.paneUUID | tostring), value: .session_id}) | from_entries) as $m
      | .[]?.tabs[]?.windows[]? | (.id | tostring) as $w | select($m[$w] != null)
      | [ .foreground_processes[]?.cmdline | select(type == "array" and index("--parent-session-id") != null) ] | first // empty
      | . as $a | ($a | index("--parent-session-id")) as $i | ($a | index("--agent-name")) as $j
      | [$m[$w], ($a[$i + 1] // ""), (if $j == null then "" else ($a[$j + 1] // "") end)]
      | select(.[1] != "") | @tsv' "$hd/hb.kitty-ls.json" 2>/dev/null
  done <<EOF
$HB_DIRS
EOF
}
tsv_col() { printf '%s\n' "$1" | cut -f"$2"; }   # <one tsv line> <n>
meta_col() { # <sid> <n> → META column n of that sid, unpadded
  unpad "$(printf '%s\n' "$META" | awk -F'\t' -v s="$1" -v n="$2" '$1 == s { print $n; exit }')"
}
META=""; n_meta_none=0; n_acct_tx=0
# The cut cannot be after the event (a restart's own tick may stamp past it, hence HB_HI).
CUT_HI="$BOOT"; [ "$HB_HI" -gt "$CUT_HI" ] 2>/dev/null && CUT_HI="$HB_HI"
TX_PRE_MAX=0   # newest pre-cut transcript write over the kept rows (R1's second rung)
EXHAUSTED_ACCTS=""; EXH_SIDS=""; n_exhausted=0
if [ "$RESTORE_V2" = 1 ] && [ "$n_open" -gt 0 ]; then
  SLOTS="$(tree_slots)"
  NEWGHOSTS=""
  while IFS=$'\t' read -r m_acct m_cwd m_sid m_name m_br; do
    sid="$(unpad "$m_sid")"; [ -n "$sid" ] || continue
    cwd="$(unpad "$m_cwd")"
    hbr="$(printf '%s\n' "$HB_META" | awk -F'\t' -v s="$sid" '$1 == s { print; exit }')"
    na="$(newest_account "$sid" "$cwd")"; acct="${na%%	*}"; na_pre="${na#*	}"
    case "$na_pre" in ''|*[!0-9]*) na_pre=0 ;; esac
    [ "$na_pre" -gt "$TX_PRE_MAX" ] && TX_PRE_MAX="$na_pre"
    if [ -n "$acct" ]; then n_acct_tx=$((n_acct_tx + 1))
    else acct="$(unpad "$(tsv_col "$hbr" 2)")"; [ -n "$acct" ] || acct="$(unpad "$m_acct")"; fi
    tm=""; tf="$(transcript_file "$acct" "$sid")"
    [ -n "$tf" ] && tm="$(transcript_meta "$tf")"
    model="$(unpad "$(tsv_col "$tm" 1)")"; [ -n "$model" ] || model="$(unpad "$(tsv_col "$hbr" 3)")"
    effort="$(unpad "$(tsv_col "$tm" 2)")"; [ -n "$effort" ] || effort="$(unpad "$(tsv_col "$hbr" 4)")"
    pm="$(unpad "$(tsv_col "$tm" 3)")"; [ -n "$pm" ] || pm="$(unpad "$(tsv_col "$hbr" 5)")"
    br="$(unpad "$m_br")"
    if [ -z "$br" ] && [ -n "$cwd" ] && [ -d "$cwd" ]; then
      br="$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"; [ "$br" = HEAD ] && br=""
    fi
    [ -n "$br" ] || br="$(unpad "$(tsv_col "$hbr" 6)")"
    [ -n "$br" ] || br="$(unpad "$(tsv_col "$tm" 4)")"
    sl="$(printf '%s\n' "$SLOTS" | awk -F'\t' -v s="$sid" '$1 == s { print $2 "\t" $3; exit }')"
    [ -z "$model" ] && [ -z "$effort" ] && n_meta_none=$((n_meta_none + 1))
    META="${META}${sid}	$(pad "$acct")	$(pad "$model")	$(pad "$effort")	$(pad "$pm")	$(pad "$br")	$(pad "$(tsv_col "$sl" 1)")	$(pad "$(tsv_col "$sl" 2)")
"
    NEWGHOSTS="${NEWGHOSTS}$(pad "$acct")	${m_cwd}	${m_sid}	${m_name}	$(pad "$br")
"
  done <<EOF
$GHOSTS
EOF
  GHOSTS="$NEWGHOSTS"
  # Account headroom (P3a item 7): one cache-only read. A row on an account at its weekly limit is
  # still resumed, but it is listed so nothing nudges it — a nudge there buys a refusal, not a turn
  # (27 of 32 roster sessions sat on two exhausted accounts on 10-01). Under a bats harness the real
  # tool is never run unless the seam names one.
  ACCTS_BIN="${CC_ACCOUNTS_BIN:-}"
  if [ -z "$ACCTS_BIN" ] && [ -z "${BATS_TEST_FILENAME:-}${BATS_TEST_TMPDIR:-}${BATS_VERSION:-}" ]; then
    ACCTS_BIN="$(resolve_bin "" claude-accounts)"
  fi
  if [ -n "$ACCTS_BIN" ] && [ -x "$ACCTS_BIN" ]; then
    EXHAUSTED_ACCTS="$(cc_run "$ACCTS_BIN" --json --max-wait 0 2>/dev/null | jq -r --argjson lim "${CC_RESTORE_EXHAUSTED_PCT:-100}" '
        .rows[]? | select(((.weekly_pct // 0) | tonumber? // 0) >= $lim) | .acct // empty' 2>/dev/null | tr '\n' ' ')"
  fi
  if [ -n "$EXHAUSTED_ACCTS" ]; then
    while IFS=$'\t' read -r m_acct _c m_sid _n _b; do
      sid="$(unpad "$m_sid")"; [ -n "$sid" ] || continue
      case " $EXHAUSTED_ACCTS " in *" $(map_account "$(unpad "$m_acct")") "*)
        EXH_SIDS="${EXH_SIDS}${sid} "; n_exhausted=$((n_exhausted + 1)) ;; esac
    done <<EOF
$GHOSTS
EOF
  fi
fi

# ── R1 (2026-10-21): THE CUT, the moment the sessions actually died, which is what the classifier
#    reads up to. It used to be ANCHOR, the source's own stamp — for a heartbeat that is the last tick,
#    and on 2026-10-21 that left the last 9.5 minutes before shutdown unread (551eb39b's promise to
#    run the leak test, 5d19ef73's self-close in flight). Strongest first, each inside (ANCHOR, CUT_HI]:
#    the last burst of shutdown tombstones written by the RESTORED sessions (a lone pane closed by hand
#    belongs to nobody here); else their newest pre-cut transcript write (Claude Code writes at exit,
#    so this is the shutdown even after a hard power-off); else ANCHOR. Never earlier than a row that
#    STARTED after the tick, or that row has nothing to classify. The registry source passes no
#    --boot-epoch (the classifier anchors on kern.boottime itself), and a tombstone source's ANCHOR
#    already is the burst. A later round reuses the first round's cut (<event>/cut): by then the
#    resumed sessions have written past it. ──
tomb_cut() { # <lo> <hi> → newest endedAt of the last burst among the kept rows' tombstones, or ""
  [ -d "$TOMB_DIR" ] || return 0
  for t in "$TOMB_DIR"/*.json; do [ -f "$t" ] && jq -c 'select(type == "object")' "$t" 2>/dev/null; done \
    | jq -rs --argjson lo "$1" --argjson hi "$2" --argjson burst "$TOMB_BURST" --arg sids " $(ghost_sids)" '
        [ .[] | (.session_id // "") as $s
              | select($s != "" and ((.endedAt // 0) | type) == "number"
                       and .endedAt > $lo and .endedAt <= $hi and ($sids | contains(" " + $s + " "))) ]
        | if length == 0 then empty else
            (map(.endedAt) | max) as $last | map(select(.endedAt >= $last - $burst)) | map(.endedAt) | max | floor
          end' 2>/dev/null
}
CUT="$ANCHOR"; CUT_SRC=anchor
case "$ANCHOR" in ''|*[!0-9]*) ANCHOR="$BOOT"; CUT="$BOOT" ;; esac
if [ "$SOURCE" = heartbeat ] || [ "$SOURCE" = roster ]; then
  _c="$(head -n 1 "$EVENT_DIR/cut" 2>/dev/null)"
  if [ "$PLAN_ONLY" = 0 ] && [ "${_c%% *}" -gt 0 ] 2>/dev/null; then
    CUT="${_c%% *}"; CUT_SRC="$(printf '%s' "$_c" | awk '{ print $2 }') (first round)"
  else
    _t="$(tomb_cut "$ANCHOR" "$CUT_HI")"
    if [ "${_t:-0}" -gt "$ANCHOR" ] 2>/dev/null; then CUT="$_t"; CUT_SRC=tombstones
    elif [ "$TX_PRE_MAX" -gt "$ANCHOR" ]; then CUT="$TX_PRE_MAX"; CUT_SRC=transcripts
    fi
    case "$REG_NEW_MAX" in ''|*[!0-9]*) REG_NEW_MAX=0 ;; esac
    [ "$REG_NEW_MAX" -gt "$CUT" ] && [ "$REG_NEW_MAX" -le "$CUT_HI" ] && { CUT="$REG_NEW_MAX"; CUT_SRC=started-after-tick; }
  fi
fi

# ── the reboot's OWNER (R2/R8): the session that ran alarm-reboot-prep.sh, which writes its session id
#    to reboot-<date>.owner beside the .start it stamps. The newest one whose .start falls in this
#    reboot's window, exactly as the roster is chosen. It is passed to the classifier as --owner (the
#    classifier gives it a wake item, so it is prompted) and is the first recipient of the page. An
#    event has no owner: kitty restarts and crashes are not prepared. Absent file ⇒ no owner. ──
OWNER_SID=""
if [ -z "$EVENT" ]; then
  _ost=0
  for f in "$ROSTER_DIR"/reboot-*.owner; do
    [ -f "$f" ] || continue
    st="$(head -n 1 "${f%.owner}.start" 2>/dev/null | awk '{ print $1 }')"
    case "$st" in ''|*[!0-9]*) continue ;; esac
    { [ "$st" -gt "$LOWER" ] && [ "$st" -le "$BOOT" ] && [ "$st" -ge "$_ost" ]; } || continue
    o="$(head -n 1 "$f" 2>/dev/null | tr -d '[:space:]')"
    case "$o" in ''|*[!A-Za-z0-9-]*) continue ;; esac
    OWNER_SID="$o"; _ost="$st"
  done
fi

# Restore v2 marks an event (or a flagged reboot) done only once nothing was shed, or once its
# deadline has passed: until then the next round runs, and the ledger keeps it from launching a sid
# twice. The page goes out once per event, on its first round (<event>/paged).
# R18: the deadline counts from the event's FIRST RUN (<event>/started), not from kern.boottime. On
# 2026-10-21 the login came 47 minutes after the boot, so a deadline of boot + 30 min had already
# passed at the first run, and a shed session would have had no retry round at all.
restore_now() { printf '%s' "${CC_RESTORE_NOW:-$(date +%s)}"; }
restore_t0() { local s; s="$(head -n 1 "$EVENT_DIR/started" 2>/dev/null)"; case "$s" in ''|*[!0-9]*) s="$BOOT" ;; esac; printf '%s' "$s"; }
restore_deadline() { printf '%s' $(( $(restore_t0) + ${CC_RESTORE_DEADLINE_S:-1800} )); }
restore_done() { [ "${resume_shed:-0}" -eq 0 ] || [ "$(restore_now)" -ge "$(restore_deadline)" ]; }
# R4 (2026-10-21): no start gate. It waited up to 600 s per round for load to fall to 6 per core,
# which at this machine's standing 15-40 per core it never does (60 readings from 61.47 to 6.99 on
# 2026-10-21, then the deadline). One reading is kept as telemetry; nothing waits for it.
restore_load_reading() {
  local l1 nc per
  nc="$("$SYSCTL" -n hw.ncpu 2>/dev/null | tr -d '[:space:]')"; case "$nc" in ''|*[!0-9]*|0) nc=1 ;; esac
  l1="$("$SYSCTL" -n vm.loadavg 2>/dev/null | tr -d '{}' | awk '{ print $1 }')"
  per="$(awk -v l="$l1" -v n="$nc" 'BEGIN { if (l !~ /^[0-9.]+$/) print "?"; else printf "%.2f", l / n }')"
  mkdir -p "$EVENT_DIR" 2>/dev/null || true
  printf '%s load1=%s ncpu=%s per_core=%s gate=none\n' "$(restore_now)" "${l1:-?}" "$nc" "$per" >> "$EVENT_DIR/load.log" 2>/dev/null
  printf '%s' "$per"
}
mark_processed() {
  if [ "$RESTORE_V2" = 1 ] && ! restore_done; then return 0; fi
  # An event marks only its own record. Writing the boot markers here would make the next reboot
  # read as already handled (the uuid would not change until then, but the epoch fallback would).
  if [ -n "$EVENT" ]; then
    [ "$PLAN_ONLY" = 1 ] && return 0
    mkdir -p "$(dirname "$MARKER")" 2>/dev/null || true
    printf '%s\n' "$BOOT" > "$MARKER" 2>/dev/null || true
    return 0
  fi
  mkdir -p "$STATE_DIR" 2>/dev/null || true
  printf '%s\n' "$BOOT" > "$MARKER" 2>/dev/null || true
  if [ -n "$BOOT_UUID" ]; then printf '%s\n' "$BOOT_UUID" > "$UUID_MARKER" 2>/dev/null || true
  else rm -f "$UUID_MARKER" 2>/dev/null || true; fi   # a stale uuid must not outvote the epoch
}

# ── --plan-only: what a restore of this event WOULD do, and nothing else — no ownership probe (a
#    live session reads as held), no classifier, no layout, no page, no marker. ──
if [ "$PLAN_ONLY" = 1 ]; then
  echo "boot-resume: plan event=${EVENT} kind=${EVENT_KIND} source=${SOURCE_LABEL:-none} anchor=${ANCHOR} cut=${CUT}(${CUT_SRC}) sessions=${n_open} retired=${n_retired}"
  # The 11 row-contract columns the layout would get, '-' for an empty cell. Column 10 (prompt_file)
  # stays empty here: a prompt is written only for a row classified INTERRUPTED or WAKE-LOST, and a
  # plan runs no classifier.
  echo "boot-resume: plan columns=alias sid cwd branch label model effort group slot prompt_file permission_mode · account from the newest transcript for ${n_acct_tx}/${n_open}"
  dash() { if [ -n "$1" ]; then printf '%s' "$1"; else printf -; fi; }
  n_plan=0
  while IFS=$'\t' read -r acct cwd sid name br; do
    sid="$(unpad "$sid")"; [ -n "$sid" ] || continue
    acct="$(unpad "$acct")"; cwd="$(unpad "$cwd")"; name="$(unpad "$name")"; br="$(unpad "$br")"
    printf 'row\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$(map_account "$acct")" "$sid" "${cwd:--}" "${br:--}" \
      "${name:-${sid:0:8}}" "$(dash "$(meta_col "$sid" 3)")" "$(dash "$(meta_col "$sid" 4)")" \
      "$(dash "$(meta_col "$sid" 7)")" "$(dash "$(meta_col "$sid" 8)")" - "$(dash "$(meta_col "$sid" 5)")"
    case " $EXH_SIDS " in *" $sid "*) printf 'exhausted\t%s\t%s\tresumed, never nudged: the account is at its weekly limit\n' "$sid" "$(map_account "$acct")" ;; esac
    n_plan=$((n_plan + 1))
  done <<EOF
$GHOSTS
EOF
  [ "$n_retired" -gt 0 ] && printf '%s' "$RETIRED" | sed 's/^  - /retired\t/'
  echo "boot-resume: plan verdict=planned rows=${n_plan} retired=${n_retired} launches=0 exhausted=${n_exhausted} no_model=${n_meta_none}"
  log_idl abstained ",\"reason\":\"plan-only\",\"n_open\":$n_open,\"resumed\":0"
  exit 0
fi

# ── reboot happened but nothing was open → nothing lost, no page. Advance the marker. ──
if [ "$n_open" -eq 0 ]; then
  mark_processed
  if [ "$n_retired" -gt 0 ]; then
    log_idl abstained ',"reason":"all-retired","n_open":0,"resumed":0'
  else
    log_idl abstained ',"reason":"no-open-sessions","n_open":0,"resumed":0'
  fi
  exit 0
fi

# ── desk-jobs snapshot (best-effort, informational): loaded com.claude agents + how many up. ──
dj_total=0; dj_up=0
if command -v "${LAUNCHCTL%% *}" >/dev/null 2>&1 || [ -x "$LAUNCHCTL" ]; then
  while IFS=$'\t' read -r pid _status label; do
    case "$label" in com.claude.*) dj_total=$((dj_total + 1)); case "$pid" in ''|-|*[!0-9]*) : ;; *) dj_up=$((dj_up + 1)) ;; esac ;; esac
  done < <("$LAUNCHCTL" list 2>/dev/null || true)
fi

# ── ACT: resume (posture=resume), else page-only (posture=page). ──
resumed=0
resume_fail=0
resume_shed=0   # sessions SELECTED but REFUSED by the capacity term — distinct from resume_fail (launcher error)
resume_ledger=0 # restore v2: already launched by an earlier round of this event (its ledger)
resume_held=0   # rc 5: not ours to launch — the reconciler owns it, its launch lock is held, it already
                # has a live holder, or it is PARKED-REBOOT in page mode. Not broken, not waiting on us.
                # rc 7 counts here too: or an Agent Teams member its lead owns (a new window cannot
                # carry its team identity).
resume_indet=0  # rc 6: launch INDETERMINATE — kitty's client timed out and no window carries the token
                # yet; cc-resume-debt's sweep reconciles it (not held, not failed: not yet known).
n_fire=0       # sessions SELECTED to fire (post-consolidation) — distinct from n_open (sessions found)
n_int=0         # classifier verdicts over the sessions that passed the ownership check
n_rest=0
opener=""       # desktops (cc-resume-layout --desktops) | windows (one launcher window per session)
desk_windows=0; desk_fs_ok=0; desk_fs_bad=0
nudged=""       # the keepalive's markers: cwds of INTERRUPTED sessions only
n_wake=0        # restore v2: at rest, but with work open at the cut that died with the process
n_noted=0; n_note_fail=0   # restore v2: inbox notes written this round / refused by cc-notify
n_prompt=0; n_prompt_ok=0; n_prompt_fb=0; n_prompt_noreply=0; n_prompt_bad=0   # launch-argument prompts
n_draft_typed=0; n_draft_kept=0; n_draft_left=0; drafts_dir=""; layout_ran=0     # the reboot prep's unsent drafts
PROMPTED=""     # restore v2: "<sid>\t<prompt file>\t<nonce>\t<cwd>" per row that got a prompt
kv() { printf '%s\n' "$2" | tr ' ' '\n' | sed -n "s/^$1=//p" | head -1; }   # <key> <summary-line>
num() { case "$1" in ''|*[!0-9]*) printf 0 ;; *) printf '%s' "$1" ;; esac; }
HELD=""; HELD_MEMBERS=""; n_mail_carried=0; n_ret_cls=0; load_per_core=""; MAIL_LOG=""
EARLY_TO=""; EARLY_KIND=""; BL_PID=""; BL_OUT=""

# ── WHO HEARS ABOUT IT (R8, 2026-10-21). The page used to need cc-roles/desk, which nothing re-creates
#    after a sweep or a reboot, so every recent reboot's summary went to a backlog row that said
#    "nothing was told" over 26 resumed sessions. The ladder: the reboot's owner session (the one
#    that ran alarm-reboot-prep.sh, when it is back), else the desk role, else a lead role whose
#    session is live (*-lead, orchestrator; re-resolved by cc-restore-rebind first), else the backlog.
#    Live = this restore launched it, or a registry row started this boot names it with a running pid. ──
sid_live() { # <session id or pane number> → rc 0 when a session of this boot holds it
  local k="$1" kb p
  [ -n "$k" ] || return 1
  [ "$RESTORE_V2" = 1 ] && grep -qxF "$k" "$EVENT_DIR/launched" 2>/dev/null && return 0
  kb="$(boottime)"; case "$kb" in ''|*[!0-9]*) kb=0 ;; esac   # the kernel boot, also in event mode
  for p in $(for f in "$REGISTRY_DIR"/*.json; do [ -f "$f" ] && cat "$f" && echo; done 2>/dev/null \
             | jq -r --arg k "$k" --argjson kb "$kb" 'select(type == "object"
                 and ((.session_id // "") == $k or ((.paneUUID // "") | tostring) == $k)
                 and ((((.startedAt // 0) | if type == "number" then . else 0 end) / 1000) >= $kb))
               | .pid // empty | tostring' 2>/dev/null); do
    case "$p" in ''|*[!0-9]*) continue ;; esac
    kill -0 "$p" 2>/dev/null && return 0
  done
  return 1
}
PAGE_TO=""; PAGE_KIND=""
resolve_page_target() { # sets PAGE_TO and PAGE_KIND; rc 1 when nobody can be told
  local t r
  PAGE_TO=""; PAGE_KIND=""
  if [ -n "$OWNER_SID" ] && sid_live "$OWNER_SID"; then PAGE_TO="$OWNER_SID"; PAGE_KIND=owner; return 0; fi
  t=""; [ -f "$ROLES_DIR/desk" ] && t="$(head -1 "$ROLES_DIR/desk" 2>/dev/null | tr -d '[:space:]')"
  [ -n "$t" ] && { PAGE_TO="$t"; PAGE_KIND=desk; return 0; }
  for r in "$ROLES_DIR"/*-lead "$ROLES_DIR"/orchestrator; do
    [ -f "$r" ] || continue
    t="$(head -1 "$r" 2>/dev/null | tr -d '[:space:]')"
    [ -n "$t" ] && sid_live "$t" && { PAGE_TO="$t"; PAGE_KIND="role:${r##*/}"; return 0; }
  done
  return 1
}
cut_phrase() { # "rebooted 2026-…Z" / "kitty crash at …"
  local w=rebooted; [ -n "$EVENT" ] && w="kitty ${EVENT_KIND} at"
  printf '%s %s' "$w" "$(date -u -r "$BOOT" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || printf '%s' "$BOOT")"
}
page_lists() { # the retired and held sessions, each named — shared by the early page and the final one
  [ "$n_retired" -gt 0 ] && printf '\n⏭ %s not resumed — they closed themselves on purpose, or were closing themselves at the cut:\n%s' "$n_retired" "$RETIRED"
  [ -n "$HELD" ] && printf '\n⏸ not launched by this restore (the launcher said why; %s):\n%s' "$HELD_LOG" "$HELD"
  return 0
}
# shellcheck disable=SC2016  # the backticks are literal: the row tells the operator a command to run
backlog_step() { # <why> → the backlog row's text, true to what happened
  local undeliv="$STATE_DIR/undelivered-$BOOT.page"
  if [ "$MODE" = resume ] && [ "${resumed:-0}" -gt 0 ]; then
    printf 'boot-resume restored %s of %s session(s) after it %s (%s recovery prompt(s) sent), but no session could be told (%s: no owner session, desk role or live lead role). Read the summary: %s. To have the next restore page a session directly, run `cc-roles claim desk` from the desk pane.' \
      "$resumed" "$n_fire" "$(cut_phrase)" "${n_prompt:-0}" "$1" "$undeliv"
  elif [ "$MODE" = resume ]; then
    printf 'boot-resume could not reopen any of the %s session(s) that were open when it %s (%s). Full report: %s — recover with /resume-sessions in any Claude session, then run `cc-roles claim desk` from the desk pane so the next boot pages directly.' \
      "$n_open" "$(cut_phrase)" "$1" "$undeliv"
  else
    printf 'boot-resume could not page the desk (%s): %s session(s) were open when it %s and, in page mode, none were resumed and nothing was told. Full delta: %s — recover with /resume-sessions in any Claude session, then run `cc-roles claim desk` from the desk pane so the next boot pages directly.' \
      "$1" "$n_open" "$(cut_phrase)" "$undeliv"
  fi
}
early_page() { # restore v2, first round, right after the layout
  local where msg why=no-desk-role
  where="one window each"; [ "$opener" = desktops ] && where="${desk_windows} fullscreen Desktop(s)"
  msg="🔄 restore under way: $(cut_phrase) · source: ${SOURCE_LABEL} · reopened ${resumed}/${n_fire} session(s) into ${where} just now. ${n_int} cut off mid-turn and ${n_wake} at rest with work that died got a recovery prompt (${n_prompt} sent; a follow-up page says how many ran); ${n_rest} at rest got an inbox note only."
  [ "$n_mail_carried" -gt 0 ] && msg="${msg} ✉ the unread mail of ${n_mail_carried} session(s) was carried from its old pane number to the session."
  [ "$resume_shed" -gt 0 ] && msg="${msg} ⏸ ${resume_shed} shed by the capacity gate; this restore runs again for them until $(date -r "$(restore_deadline)" +%H:%M 2>/dev/null)."
  [ "$resume_fail" -gt 0 ] && msg="${msg} ⚠ ${resume_fail} failed to launch."
  msg="${msg}$(page_lists)"
  if resolve_page_target && [ -n "$NOTIFY" ]; then
    cc_run "$NOTIFY" "$PAGE_TO" "$msg" >/dev/null 2>&1 || true   # cc-notify's mailbox fallback ⇒ durable at exit 0
    EARLY_TO="$PAGE_TO"; EARLY_KIND="$PAGE_KIND"
    paged_once
    echo "boot-resume: early page delivered to ${PAGE_KIND} ${PAGE_TO}" >&2
    return 0
  fi
  [ -n "$PAGE_TO" ] && why=no-notify-bin
  # Nobody to tell. The page goes to disk now and the backlog row is filed in the BACKGROUND, so the
  # confirm phase is not held by it; the end of the run waits for it before deciding to mark.
  mkdir -p "$STATE_DIR" 2>/dev/null || true
  printf '%s\n' "$msg" > "$STATE_DIR/undelivered-$BOOT.page" 2>/dev/null || true
  if [ -n "$BACKLOG" ]; then
    BL_OUT="$EVENT_DIR/backlog.out"; BL_WHY="$why"
    ( cc_run "$BACKLOG" needs "$(backlog_step "$why")" --class needs-human --receipt "$STATE_DIR/undelivered-$BOOT.page" \
        --project claude-infrastructure > "$BL_OUT" 2>/dev/null ) &
    BL_PID=$!
  fi
  echo "boot-resume: early page undeliverable (${why}); filing to the backlog in the background" >&2
  return 0
}
paged_once() { [ "$RESTORE_V2" = 1 ] || return 0; mkdir -p "$EVENT_DIR" 2>/dev/null && : > "$EVENT_DIR/paged" 2>/dev/null; return 0; }
confirm_one() { # <sid> <nonce> — rn_confirm, or the test seam that stands in for it
  if [ -n "${CC_RESTORE_CONFIRM_CMD:-}" ]; then "$CC_RESTORE_CONFIRM_CMD" "$@"; else rn_confirm "$@"; fi
}
if [ "$MODE" = "resume" ]; then
  if [ -z "$LAUNCH" ] || [ ! -x "$LAUNCH" ]; then
    log_idl failed ",\"n_open\":$n_open,\"resumed\":0,\"delivered\":false,\"reason\":\"no-resume-launcher\""
    echo "boot-resume: mode=resume but no executable resume launcher — not marking boot; will retry" >&2
    exit 3
  fi
  mkdir -p "$STATE_DIR" 2>/dev/null || true
  # Restore capacity mode (P3a item 8): the launches below are paced by the start gate and the
  # layout, so the per-launch load term is switched off for them (capacity-admit.sh's term switch,
  # C18). The headroom, segment and active terms still apply.
  if [ "$RESTORE_V2" = 1 ]; then
    export CC_ADMIT_LOAD_TERM=off
    mkdir -p "$EVENT_DIR" 2>/dev/null || true
    [ -n "$EXH_SIDS" ] && printf '%s' "$EXH_SIDS" | tr ' ' '\n' > "$EVENT_DIR/exhausted" 2>/dev/null
    # R18 and R1: the first round stamps when the restore started and where it cut; later rounds read both.
    [ -s "$EVENT_DIR/started" ] || { restore_now; echo; } > "$EVENT_DIR/started" 2>/dev/null
    [ -s "$EVENT_DIR/cut" ] || printf '%s %s\n' "$CUT" "$CUT_SRC" > "$EVENT_DIR/cut" 2>/dev/null
    # R22, the boot half: after an OS update the 47 minutes from boot to login went to macOS's
    # Template Migration (TotalDuration=1534.31 on 2026-10-21), whose log was dominated by the temp
    # files the reboot prep now prunes. Its durations are kept with the boot's event so the next update
    # measures the gain. Asked once per boot, in the background (`log show` is slow at load), and only
    # its few duration lines are kept. Under a bats harness only an explicit CC_LOG_BIN runs.
    if [ -z "$EVENT" ] && [ ! -e "$EVENT_DIR/template-migration.asked" ]; then
      _lb="${CC_LOG_BIN:-}"; [ -z "$_lb" ] && ! _kp_under_bats && _lb=/usr/bin/log
      if [ -n "$_lb" ] && [ -x "$_lb" ]; then
        : > "$EVENT_DIR/template-migration.asked"
        ( "$_lb" show --style compact --start "$(date -r "$BOOT" '+%Y-%m-%d %H:%M:%S')" \
            --predicate 'process == "templateMigrator" AND (eventMessage CONTAINS "Duration" OR eventMessage CONTAINS "Migration completed")' 2>/dev/null \
            | grep -E 'Duration=|Migration completed' | tail -n 8 > "$EVENT_DIR/template-migration.tmp" \
          && mv -f "$EVENT_DIR/template-migration.tmp" "$EVENT_DIR/template-migration.txt" ) >/dev/null 2>&1 &
      fi
    fi
    # R20: this run's own stderr, timestamped, kept with the event. launchd's log is the other copy.
    exec 2> >(ts_lines | tee -a "$EVENT_DIR/run.stderr" >&2)
    echo "boot-resume: restore ${EVENT_ID} round at $(date -u +%Y-%m-%dT%H:%M:%SZ): ${n_open} row(s), source ${SOURCE_LABEL}, cut ${CUT} (${CUT_SRC}), owner ${OWNER_SID:-none}" >&2
  fi
  # WINNERS rows: "<alias>\t<sid>\t<cwd>\t<branch>\t<label>", padded.
  WINNERS=""
  if [ "$SOURCE" = registry ]; then
    # ── CONSOLIDATE before firing. A reboot can leave many GHOSTS sharing ONE worktree; resuming
    #    each is the 2026-07-21 sprawl incident. lr-select groups by worktree, picks the single
    #    session per group that holds the most real state, and lists the rest. Missing selector =
    #    FAIL LOUD and resume NOTHING — never fall back to firing every ghost, which is the exact bug.
    #    Roster and tombstone rows skip this: each one was a LIVE session when the box went down,
    #    so none of them is sprawl, and two live sessions in one checkout both come back. ──
    if [ -z "$SELECT" ] || [ ! -x "$SELECT" ]; then
      log_idl failed ",\"n_open\":$n_open,\"resumed\":0,\"delivered\":false,\"reason\":\"no-resume-selector\""
      echo "boot-resume: mode=resume but no executable lr-select — refusing to resume unconsolidated" >&2
      exit 3
    fi
    # An ARRAY, not a word-split string: a worktree path containing a space would otherwise break
    # into two argv entries and silently skip that session. bash 3.2 supports indexed arrays.
    SEL_ARGS=()
    while IFS=$'\t' read -r acct cwd sid _name _br; do
      acct="$(unpad "$acct")"; cwd="$(unpad "$cwd")"; sid="$(unpad "$sid")"
      [ -n "$sid" ] || continue
      SEL_ARGS[${#SEL_ARGS[@]}]="--candidate"
      SEL_ARGS[${#SEL_ARGS[@]}]="$(map_account "$acct"):$sid:$cwd"
    done <<EOF
$GHOSTS
EOF
    if [ "${#SEL_ARGS[@]}" -eq 0 ]; then
      log_idl failed ",\"n_open\":$n_open,\"resumed\":0,\"delivered\":false,\"reason\":\"no-usable-ghosts\""
      echo "boot-resume: ${n_open} ghost(s) but none carried a session id — not marking boot" >&2
      exit 3
    fi
    # lr-select pads its winner cells for the same field-collapse reason (its `branch` is routinely "").
    WINNERS="$("$SELECT" "${SEL_ARGS[@]}" --max-per-worktree "$MAX_PER_WT" --max-total "$MAX_TOTAL" \
      --allow-missing-cwd --json "$STATE_DIR/last-selection.json" 2>"$STATE_DIR/last-triage.txt")"
  else
    while IFS=$'\t' read -r acct cwd sid name br; do
      [ -n "$sid" ] && [ "$sid" != "$TSV_PAD" ] || continue
      WINNERS="${WINNERS}$(pad "$(map_account "$(unpad "$acct")")")	${sid}	${cwd}	${br:-$TSV_PAD}	${name:-$TSV_PAD}
"
    done <<EOF
$GHOSTS
EOF
  fi
  [ -n "$WINNERS" ] && n_fire="$(printf '%s\n' "$WINNERS" | grep -c . || true)"

  # 1. OWNERSHIP, per session, before any window opens: the launcher's own fence, PARKED-REBOOT
  #    rule and second-writer check (--check-only opens nothing). ADMITTED is plain TSV for the
  #    layout and the classifier, which both split on single tabs (cut / awk / str.split), so an
  #    empty branch cell is safe there.
  # R10: every session the probe holds (5, 7) or fails is written down WITH the launcher's own reason
  #    (its stderr used to go to /dev/null, so four members of one team were held on 2026-10-21 and
  #    nothing said why) and named in the page. A held Agent Teams member (7) is mapped to its lead
  #    through the --parent-session-id the heartbeat's kitty tree captured from its argv (a team
  #    config's leadSessionId stops matching once the lead is resumed); the lead is told to respawn it.
  HELD_LOG="$STATE_DIR/last-held.log"; [ "$RESTORE_V2" = 1 ] && HELD_LOG="$EVENT_DIR/held.log"
  HELD_ERR="$STATE_DIR/.check-only.err"; HELD=""; HELD_MEMBERS=""
  TEAM_MAP="$(team_map)"
  held_note() { # <sid> <label> <rc> — reads the probe's stderr from $HELD_ERR
    local why lead mname
    why="$(grep . "$HELD_ERR" 2>/dev/null | tail -n 1 | sed 's/^boot-resume-launch: //' | tr '\t' ' ')"
    [ -n "$why" ] || why="exit $3, no reason given"
    lead=""; mname=""
    if [ "$3" = 7 ]; then
      lead="$(printf '%s\n' "$TEAM_MAP" | awk -F'\t' -v s="$1" '$1 == s { print $2; exit }')"
      mname="$(printf '%s\n' "$TEAM_MAP" | awk -F'\t' -v s="$1" '$1 == s { print $3; exit }')"
      HELD_MEMBERS="${HELD_MEMBERS}${1}	${lead}	${mname:-$2}
"
    fi
    printf '%s\t%s\t%s\t%s\t%s\n' "$(now_iso)" "$1" "$3" "${lead:--}" "$why" >> "$HELD_LOG" 2>/dev/null
    case "$3" in 5|7) ;; *) why="FAILED the ownership probe: $why" ;; esac
    HELD="${HELD}  - $2 (${1:0:8}): ${why}${lead:+ (an Agent Teams member of lead ${lead:0:8}, whose restore note asks it to respawn the member)}
"
  }
  ADMITTED=""
  while IFS=$'\t' read -r alias sid cwd br label; do
    alias="$(unpad "$alias")"; sid="$(unpad "$sid")"; cwd="$(unpad "$cwd")"
    br="$(unpad "$br")"; label="$(unpad "$label")"
    [ -n "$sid" ] || continue
    # The launched-once ledger: a sid an earlier round of this event already launched never goes
    # back to the layout. The --check-only probe below re-asks lr_holder_count for every other row,
    # each round, so a session that came up without a map line is not launched twice either.
    if [ "$RESTORE_V2" = 1 ] && grep -qxF "$sid" "$EVENT_DIR/launched" 2>/dev/null; then
      resume_ledger=$((resume_ledger + 1)); continue
    fi
    if [ -z "$br" ] && [ -n "$cwd" ] && [ -d "$cwd" ]; then
      br="$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
      [ "$br" = HEAD ] && br=""
    fi
    [ -z "$br" ] && [ "$RESTORE_V2" = 1 ] && br="$(meta_col "$sid" 6)"   # the reaped-worktree branch
    cc_run "$LAUNCH" --check-only "$alias" "$cwd" "$sid" "$br" >/dev/null 2>"$HELD_ERR"
    c_rc=$?
    case "$c_rc" in
      0) ;;
      5|7) resume_held=$((resume_held + 1)); held_note "$sid" "${label:-${sid:0:8}}" "$c_rc"; continue ;;
      *) resume_fail=$((resume_fail + 1)); held_note "$sid" "${label:-${sid:0:8}}" "$c_rc"; continue ;;
    esac
    if [ "$RESTORE_V2" = 1 ]; then
      # Row contract columns 6-11 (model effort group slot prompt_file permission_mode), each empty
      # cell as TSV_PAD so a reader splitting on runs of tabs keeps its place. prompt_file is P4's.
      ADMITTED="${ADMITTED}${alias}	${sid}	${cwd}	${br}	${label:-${sid:0:8}}	$(pad "$(meta_col "$sid" 3)")	$(pad "$(meta_col "$sid" 4)")	$(pad "$(meta_col "$sid" 7)")	$(pad "$(meta_col "$sid" 8)")	${TSV_PAD}	$(pad "$(meta_col "$sid" 5)")
"
    else
      ADMITTED="${ADMITTED}${alias}	${sid}	${cwd}	${br}	${label:-${sid:0:8}}
"
    fi
  done <<EOF
$WINNERS
EOF

  # 2. CLASSIFY: which of them the shutdown INTERRUPTED mid-turn. Only those are nudged. A failed
  #    classifier, or one that returned a different number of rows, is no evidence at all, so every
  #    row becomes UNKNOWN — restored, never nudged (the classifier's own fail-safe polarity).
  n_adm="$(printf '%s' "$ADMITTED" | grep -c . || true)"
  # 1b. MAIL CARRY (R3), before the classifier reads mailboxes and before any window opens. Mail is
  #     keyed by pane number, and the restore renumbers panes: on 2026-10-21 a lead's "W2 landed"
  #     report sat in its old pane-31 box until the window's next occupant sealed it (31.sealed). For
  #     each admitted row whose old pane (the roster's paneUUID) holds unacked lines from before the
  #     cut, mailbox_migrate moves them to the session's own box, exactly once (it advances the pane's
  #     cursors by what landed). A pane two rows claim is carried to neither: nobody can say whose it is.
  n_mail_carried=0
  if [ "$n_adm" -gt 0 ] && [ -n "$SRC_FILES" ] && [ -f "$MAILBOX_LIB" ]; then
    PANES="$(printf '%s' "$SRC_FILES" | tr '\n' '\0' | xargs -0 cat 2>/dev/null | jq -rs --arg adm " $(printf '%s\n' "$ADMITTED" | cut -f2 | tr '\n' ' ')" '
        [ .[] | (if type == "array" then . else (.sessions // []) end)[]
          | select(type == "object") | (.session_id // "") as $s
          | select($s != "" and ((.paneUUID // "") | tostring | test("^[0-9]+$"))
                   and ($adm | contains(" " + $s + " ")))
          | {p: (.paneUUID | tostring), s: .session_id} ] | unique
        | group_by(.p)[] | select((map(.s) | unique | length) == 1) | .[0] | [.p, .s] | @tsv' 2>/dev/null)"
    if [ -n "$PANES" ]; then
      # The log lives with the event under restore v2; outside it there is no event dir to create.
      MAIL_LOG="$STATE_DIR/last-mail-carry.log"; [ "$RESTORE_V2" = 1 ] && MAIL_LOG="$EVENT_DIR/mail-carry.log"
      n_mail_carried="$( (
        set +u   # the lib is written for hooks, not for set -u
        # shellcheck source=../hooks/lib/mailbox-pending.sh
        # shellcheck disable=SC1091  # runtime-resolved source; the ship gate runs shellcheck without -x
        . "$MAILBOX_LIB" 2>/dev/null || exit 0
        n=0
        while IFS=$'\t' read -r p s; do
          [ -n "$p" ] && [ -n "$s" ] || continue
          old="$(mailbox_window_tagged "$p" "$(mailbox_acked "$p")" "$((CUT + 1))" 2>/dev/null | grep -c '^P ')"
          [ "${old:-0}" -gt 0 ] || continue
          m="$(mailbox_migrate "$p" "$s" 2>/dev/null)"; rc=$?
          printf '%s pane=%s sid=%s pre_cut=%s migrated=%s rc=%s\n' "$(now_iso)" "$p" "$s" "$old" "${m:-0}" "$rc" \
            >> "$MAIL_LOG" 2>/dev/null
          [ "${m:-0}" -gt 0 ] 2>/dev/null && n=$((n + 1))
        done <<PANES_EOF
$PANES
PANES_EOF
        echo "$n" ) )"
      n_mail_carried="$(num "$n_mail_carried")"
    fi
  fi
  CLASSIFIED=""
  if [ "$n_adm" -gt 0 ] && [ -n "$CLASSIFY" ] && [ -x "$CLASSIFY" ]; then
    CL_ARGS=()
    # R1: the true cut, not the source's stamp (see the CUT block).
    [ "$SOURCE" != registry ] && CL_ARGS=(--boot-epoch "$CUT")
    # The reboot's owner gets a wake item. Passed only to a classifier that knows the flag, so an older
    # one is never handed an argument it refuses (argparse exit 2 would make every row UNKNOWN).
    if [ -n "$OWNER_SID" ] && grep -q -e '--owner' "$CLASSIFY" 2>/dev/null; then
      CL_ARGS[${#CL_ARGS[@]}]=--owner; CL_ARGS[${#CL_ARGS[@]}]="$OWNER_SID"
    fi
    if [ "$RESTORE_V2" = 1 ]; then
      # WAKE-LOST and the lost-items file are restore v2's; without the flag the classifier's output
      # is what it always was. The heartbeat dirs say what was live under each session at the cut.
      CL_ARGS[${#CL_ARGS[@]}]=--wake-lost
      CL_ARGS[${#CL_ARGS[@]}]=--lost-json; CL_ARGS[${#CL_ARGS[@]}]="$EVENT_DIR/lost.json"
      while IFS= read -r hd; do
        [ -n "$hd" ] && [ -d "$hd" ] || continue
        CL_ARGS[${#CL_ARGS[@]}]=--hb-dir; CL_ARGS[${#CL_ARGS[@]}]="$hd"
      done <<EOF
$HB_DIRS
EOF
    fi
    CLASSIFIED="$(printf '%s' "$ADMITTED" | cc_run "$CLASSIFY" ${CL_ARGS[@]+"${CL_ARGS[@]}"} 2>"$STATE_DIR/last-classify.txt")" || CLASSIFIED=""
    # R20: each event keeps its own copy; last-classify.txt is overwritten by the next run.
    [ "$RESTORE_V2" = 1 ] && { echo "=== $(now_iso) classify ${CL_ARGS[*]-}"; cat "$STATE_DIR/last-classify.txt"; } >> "$EVENT_DIR/classify.txt" 2>/dev/null
  fi
  if [ "$(printf '%s' "$CLASSIFIED" | grep -c . || true)" != "$n_adm" ]; then
    CLASSIFIED="$(printf '%s' "$ADMITTED" | awk -F'\t' 'NF { print $0 "\tUNKNOWN" }')"
  fi
  # A held Agent Teams member's lead (R10): the member is a teammate item in the lead's lost items,
  # so its restore note names it, and a lead that was otherwise at rest has work that died with the
  # old process — WAKE-LOST, which prompts it. A lead the classifier could not read (UNKNOWN) stays
  # as it is: no evidence is no evidence.
  if [ "$RESTORE_V2" = 1 ] && [ -n "$HELD_MEMBERS" ] && [ -n "$CLASSIFIED" ]; then
    while IFS=$'\t' read -r m_sid m_lead m_name; do
      [ -n "$m_lead" ] || continue
      printf '%s\n' "$CLASSIFIED" | awk -F'\t' -v s="$m_lead" '$2 == s { f = 1 } END { exit !f }' || continue
      CLASSIFIED="$(printf '%s\n' "$CLASSIFIED" | awk -F'\t' -v OFS='\t' -v s="$m_lead" '$2 == s && $NF == "AT-REST" { $NF = "WAKE-LOST" } NF { print }')"
      [ -f "$EVENT_DIR/lost.json" ] || printf '{"sessions":{}}\n' > "$EVENT_DIR/lost.json"
      jq --arg l "$m_lead" --arg n "$m_name" --arg m "$m_sid" '
          .sessions = (.sessions // {})
          | .sessions[$l] = (.sessions[$l] // {verdict: "WAKE-LOST", items: []})
          | .sessions[$l].items = ((.sessions[$l].items // [])
              | if any(.[]; .kind == "teammate" and ((.detail // "") | startswith($n))) then map(
                    if .kind == "teammate" and ((.detail // "") | startswith($n)) then .detail = "\($n): held at restore, respawn it" | .sid = $m else . end)
                else . + [{kind: "teammate", detail: "\($n): held at restore, respawn it", sid: $m}] end)
          | if .sessions[$l].verdict == "AT-REST" then .sessions[$l].verdict = "WAKE-LOST"
              | .sessions[$l].why = ((.sessions[$l].why // "") + "; an Agent Teams member was held at restore") else . end' \
        "$EVENT_DIR/lost.json" > "$EVENT_DIR/lost.json.tmp" 2>/dev/null && mv -f "$EVENT_DIR/lost.json.tmp" "$EVENT_DIR/lost.json"
    done <<EOF
$HELD_MEMBERS
EOF
  fi
  # The classified rows, kept with the event: cc-restore-rebind and cc-restore --compare read them.
  # A later round admits only what is still missing, so its rows are merged over the earlier ones
  # by sid (column 2), never written in their place. R12: the `|| true` is inside the braces — on the
  # first round rows.tsv does not exist yet, and under pipefail a failing cat failed the whole pipe,
  # so the mv never ran and every restore left only rows.tsv.tmp.
  if [ "$RESTORE_V2" = 1 ] && [ "$n_adm" -gt 0 ]; then
    { printf '%s\n' "$CLASSIFIED"; cat "$EVENT_DIR/rows.tsv" 2>/dev/null || true; } \
      | awk -F'\t' 'NF >= 2 && !seen[$2]++' > "$EVENT_DIR/rows.tsv.tmp" 2>/dev/null \
      && mv -f "$EVENT_DIR/rows.tsv.tmp" "$EVENT_DIR/rows.tsv" 2>/dev/null
  fi
  # RETIRED (T1's verdict): the session was closing itself — a handoff-fire.sh self-close tool call was
  #   pending at the cut, or its terminal-intent record was still on disk. It is not relaunched, gets no
  #   note and no prompt, and is named in the page with the command that brings it back. On 2026-10-21
  #   5d19ef73 was mid `self-close --terminal` when the power went, and came back as an idle pane.
  n_ret_cls=0
  RET_SIDS="$(printf '%s\n' "$CLASSIFIED" | awk -F'\t' '$NF == "RETIRED" { print $2 }' | tr '\n' ' ')"
  if [ -n "${RET_SIDS// /}" ]; then
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      r_sid="$(printf '%s' "$line" | cut -f2)"
      case " $RET_SIDS " in *" $r_sid "*) ;; *) continue ;; esac
      r_alias="$(printf '%s' "$line" | cut -f1)"; r_cwd="$(printf '%s' "$line" | cut -f3)"; r_lab="$(printf '%s' "$line" | cut -f5)"
      r_launcher=""; command -v cc_acct_launcher_for_name >/dev/null 2>&1 && r_launcher="$(cc_acct_launcher_for_name "$r_alias")"
      RETIRED="${RETIRED}  - ${r_lab:-${r_sid:0:8}} (${r_sid}): it was closing itself at the cut (a self-close in flight) — to bring it back: cd '${r_cwd:-.}' && ${r_launcher:-claude} --resume ${r_sid}
"
      n_retired=$((n_retired + 1)); n_ret_cls=$((n_ret_cls + 1))
    done <<EOF
$CLASSIFIED
EOF
    ADMITTED="$(printf '%s\n' "$ADMITTED" | awk -F'\t' -v r=" $RET_SIDS " 'NF && !index(r, " " $2 " ")')
"
    CLASSIFIED="$(printf '%s\n' "$CLASSIFIED" | awk -F'\t' '$NF != "RETIRED" && NF')"
    n_adm=$((n_adm - n_ret_cls))
    mkdir -p "$STATE_DIR" 2>/dev/null && printf '%s' "$RETIRED" > "$STATE_DIR/last-retired.txt" 2>/dev/null
  fi
  n_int="$(printf '%s\n' "$CLASSIFIED" | awk -F'\t' '$NF == "INTERRUPTED"' | grep -c . || true)"
  n_wake="$(printf '%s\n' "$CLASSIFIED" | awk -F'\t' '$NF == "WAKE-LOST"' | grep -c . || true)"
  n_rest=$((n_adm - n_int - n_wake))

  # 2b. RECOVERY DELIVERY, restore v2 only (W3 P4), BEFORE any window opens.
  #     Every row gets an inbox note saying what died with the old process: mailbox-drain.sh hands it
  #     to the session as context at resume, and it costs no turn. Only a row with open work
  #     (INTERRUPTED or WAKE-LOST) on an account with quota gets a prompt, and it travels as contract
  #     column 10 to reso-resume-one --prompt-file, a launch argument. Nothing is typed.
  #     Keyed on the SID, never on a map line: a row the layout only confirms later has none.
  #     One note per sid per event (<event>/noted), and a prompt file is reused by a later round, so a
  #     retry tick neither repeats a note nor mints a second nonce. CC_RESTORE_NUDGE=off: notes only.
  if [ "$RESTORE_V2" = 1 ] && [ "$n_adm" -gt 0 ] && command -v rn_note_text >/dev/null 2>&1; then
    rn_kind="${EVENT_KIND:-reboot}"
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      sid="$(printf '%s' "$line" | cut -f2)"; verdict="$(printf '%s' "$line" | awk -F'\t' '{ print $NF }')"
      if ! grep -qxF "$sid" "$EVENT_DIR/noted" 2>/dev/null; then
        if rn_send_note "$sid" "$(rn_note_text "$rn_kind" "$BOOT" "$EVENT_DIR/lost.json" "$sid")"; then
          printf '%s\n' "$sid" >> "$EVENT_DIR/noted" 2>/dev/null; n_noted=$((n_noted + 1))
        else
          n_note_fail=$((n_note_fail + 1))
        fi
      fi
      rn_nudge_wanted "$verdict" "$sid" "$EXH_SIDS" || continue
      pf="$EVENT_DIR/prompts/$sid.txt"; nonce=""
      [ -s "$pf" ] && nonce="$(sed -n 's/.*(restore ref \(R-[0-9a-f]*\)).*/\1/p' "$pf" | tail -n 1)"
      if [ -z "$nonce" ]; then
        nonce="$(rn_nonce)"
        pf="$(rn_write_prompt "$EVENT_DIR/prompts" "$sid" \
               "$(rn_prompt_text "$rn_kind" "$BOOT" "$EVENT_DIR/lost.json" "$sid" "$verdict" "$nonce")")" || continue
      fi
      # Column 4, the worktree: rn_confirm and rn_fallback find the transcript by direct path from it.
      PROMPTED="${PROMPTED}${sid}	${pf}	${nonce}	$(printf '%s' "$line" | cut -f3)
"
      n_prompt=$((n_prompt + 1))
    done <<EOF
$CLASSIFIED
EOF
    if [ -n "$PROMPTED" ]; then
      # Column 10 of the rows the layout is about to read. The prompt list comes first on stdin, the
      # rows after a blank line; a row with fewer than 10 columns is passed through untouched.
      ADMITTED="$( { printf '%s\n' "$PROMPTED"; printf '%s' "$ADMITTED"; } | awk -F'\t' -v OFS='\t' '
        !rows && NF == 0 { rows = 1; next }
        !rows { pf[$1] = $2; next }
        NF >= 10 && ($2 in pf) { $10 = pf[$2] }
        { print }')
"
    fi
  fi

  # 3. OPEN. The operator's layout: each window native-fullscreen on its own Desktop
  #    (cc-resume-layout.sh --desktops). By default that is <=4 panes per OS window as a 2x2; under
  #    restore v2 (--restore) it is one row of up to 6 panes per window. At login there may be no kitty yet — exit
  #    3 means no live control socket — so open one and give it a moment before falling back.
  # No start gate (R4): one load-per-core reading goes to <event>/load.log as telemetry, and the
  # layout starts at once. The layout's own per-pane capacity admission is what paces the launches.
  load_per_core=""
  if [ "$RESTORE_V2" = 1 ] && [ "$n_adm" -gt 0 ]; then
    load_per_core="$(restore_load_reading)"
  fi
  LAY_ARGS=(--desktops)
  [ "$RESTORE_V2" = 1 ] && LAY_ARGS=(--desktops --restore)
  # R20: the layout's stderr, one timestamped copy per event (last-layout.txt used to run on across
  # boots with no time on any line); a restore outside v2 keeps last-layout.txt, now timestamped too.
  LAYOUT_LOG="$STATE_DIR/last-layout.txt"; [ "$RESTORE_V2" = 1 ] && LAYOUT_LOG="$EVENT_DIR/layout.txt"
  layout_rc=127; layout_sum=""
  if [ "$n_adm" -gt 0 ] && [ -n "$LAYOUT" ] && [ -x "$LAYOUT" ]; then
    tries="${CC_BOOT_RESUME_KITTY_TRIES:-10}"; poll="${CC_BOOT_RESUME_KITTY_POLL:-3}"; opened=0
    while :; do
      # To a file, not $( … | grep): the layout's exit status is the verdict (3 = no kitty), and a
      # command substitution's pipeline status never reaches this shell. Its stdout goes to the file
      # and its stderr down the pipe to the timestamped log; PIPESTATUS[1] is the layout's own rc.
      echo "=== $(now_iso) layout ${LAY_ARGS[*]} rows=${n_adm}" | ts_lines >> "$LAYOUT_LOG" 2>/dev/null
      printf '%s' "$ADMITTED" | cc_run "$LAYOUT" "${LAY_ARGS[@]}" 2>&1 >"$STATE_DIR/last-layout.out" | ts_lines >> "$LAYOUT_LOG" 2>/dev/null
      layout_rc="${PIPESTATUS[1]}"; layout_ran=1
      layout_sum="$(grep '^cc-resume-layout: verdict=' "$STATE_DIR/last-layout.out" 2>/dev/null | tail -1)"
      [ "$layout_rc" = 3 ] && [ "$tries" -gt 0 ] || break
      # By PATH, not by name: the staged sandbox build shares kitty's bundle id, so `-a kitty` could
      # open the wrong one. No -n: a second kitty beside a live one is the duplicate this avoids.
      [ "$opened" = 1 ] || { "$OPEN_BIN" -a "${CC_KITTY_APP:-/Applications/kitty.app}" >/dev/null 2>&1; opened=1; }
      tries=$((tries - 1)); sleep "$poll"
    done
  fi
  if [ "$RESTORE_V2" = 1 ] && [ -f "$STATE_DIR/last-layout.out" ]; then
    # One map line per launch (row contract): kept as last-layout.map, appended to the event's own
    # map, and each sid entered in the launched-once ledger.
    grep '^cc-resume-layout: map ' "$STATE_DIR/last-layout.out" > "$STATE_DIR/last-layout.map" 2>/dev/null || true
    if [ -s "$STATE_DIR/last-layout.map" ]; then
      cat "$STATE_DIR/last-layout.map" >> "$EVENT_DIR/map" 2>/dev/null || true
      tr ' ' '\n' < "$STATE_DIR/last-layout.map" | sed -n 's/^sid=//p' >> "$EVENT_DIR/launched" 2>/dev/null || true
    fi
  fi
  if { [ "$layout_rc" = 0 ] || [ "$layout_rc" = 4 ]; } && [ -n "$layout_sum" ]; then
    opener=desktops
    resumed="$(num "$(kv launched "$layout_sum")")"
    resume_shed=$((resume_shed + $(num "$(kv shed "$layout_sum")")))
    resume_fail=$((resume_fail + $(num "$(kv failed "$layout_sum")")))
    desk_windows="$(num "$(kv windows "$layout_sum")")"
    desk_fs_ok="$(num "$(kv fullscreen_ok "$layout_sum")")"
    desk_fs_bad="$(num "$(kv fullscreen_failed "$layout_sum")")"
  elif [ "$n_adm" -gt 0 ]; then
    # No layout, or it could not reach a kitty: one window per session through the launcher, the
    # pre-2026-09-30 path. rc 9 is the launcher's capacity refusal and is NOT a failure: resume_fail
    # means the launcher broke and needs fixing, resume_shed means the box was full — same count,
    # opposite operator action.
    opener=windows
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      alias="$(printf '%s' "$line" | cut -f1)"; sid="$(printf '%s' "$line" | cut -f2)"
      cwd="$(printf '%s' "$line" | cut -f3)";   br="$(printf '%s' "$line" | cut -f4)"
      cc_run "$LAUNCH" "$alias" "$cwd" "$sid" "$br" >/dev/null 2>"$HELD_ERR"
      w_rc=$?
      case "$w_rc" in
        0) resumed=$((resumed + 1))
           [ "$RESTORE_V2" = 1 ] && printf '%s\n' "$sid" >> "$EVENT_DIR/launched" 2>/dev/null ;;
        9) resume_shed=$((resume_shed + 1)) ;;
        5|7) resume_held=$((resume_held + 1)); held_note "$sid" "$(printf '%s' "$line" | cut -f5)" "$w_rc" ;;
        6) resume_indet=$((resume_indet + 1)) ;;
        *) resume_fail=$((resume_fail + 1)) ;;
      esac
    done <<EOF
$ADMITTED
EOF
  fi

  # 3b. RIGHT AFTER THE LAYOUT RETURNS (R8, R9; 2026-10-21). Three things that used to wait for the
  #     confirm phase, or for the next launchd tick, or never ran at all:
  #     - REBIND (v2): roles and forwards that name old pane numbers are re-resolved to the new panes
  #       (cc-restore-rebind; a kitty event's cc-restore runs it again later, which is safe). It reads
  #       the pre-restore roster and roles beside the map, so they are copied in when absent.
  #     - THE PAGE: the summary goes out now, while the prompts are still being confirmed, to the
  #       reboot's owner session, else the desk role, else a live lead role; a follow-up with the
  #       confirmed counts goes to the same session after the confirm phase. With nobody to tell, it
  #       is filed to the backlog in the background, in words that say what actually happened.
  #     - A HEARTBEAT of the restored fleet, and another at every exit from here on: the heartbeat
  #       lives in this same launchd job, so while a restore ran there was none (the new kitty got its
  #       first one 94 minutes after it started, on 2026-10-21).
  if [ "$RESTORE_V2" = 1 ] && [ "$layout_ran" = 1 ] && [ -n "$REBIND" ] && [ -x "$REBIND" ]; then
    [ -s "$STATE_DIR/last-layout.map" ] && cat "$STATE_DIR/last-layout.map" >> "$EVENT_DIR/layout.map" 2>/dev/null
    if [ ! -f "$EVENT_DIR/hb.roster.json" ] && [ -n "$HB_DIRS" ]; then
      printf '%s' "$HB_DIRS" | sed 's|$|/hb.roster.json|' | tr '\n' '\0' | xargs -0 cat 2>/dev/null \
        | jq -s '[.[] | if type == "array" then .[] else empty end]' > "$EVENT_DIR/hb.roster.json" 2>/dev/null || true
    fi
    if [ ! -f "$EVENT_DIR/hb.roles.tsv" ] && [ -n "$HB_DIRS" ]; then
      printf '%s' "$HB_DIRS" | sed 's|$|/hb.roles.tsv|' | tr '\n' '\0' | xargs -0 cat 2>/dev/null | sort -u > "$EVENT_DIR/hb.roles.tsv" 2>/dev/null || true
    fi
    cc_run "$REBIND" "$EVENT_DIR" >> "$EVENT_DIR/rebind.out" 2>&1
    echo "boot-resume: cc-restore-rebind rc $? ($(tail -n 1 "$EVENT_DIR/rebind.out" 2>/dev/null))" >&2
  fi
  if [ "$RESTORE_V2" = 1 ] && [ ! -f "$EVENT_DIR/paged" ] && { [ "$layout_ran" = 1 ] || [ "$opener" = windows ]; }; then
    early_page
  fi
  if [ "$layout_ran" = 1 ] || [ "$opener" = windows ]; then
    heartbeat
    trap 'heartbeat' EXIT
  fi

  # 4. KEEPALIVE, scoped to the INTERRUPTED sessions. It re-nudges any idle pane whose cwd CONTAINS
  #    a marker, and it cannot tell a parked session from a stalled one — so a marker must never
  #    reach an AT-REST pane: a cwd shared with (or a prefix of) any non-INTERRUPTED row is dropped,
  #    and so is a cwd with a space (the marker list is space-separated). No marker ⇒ no keepalive.
  nudged="$(printf '%s\n' "$CLASSIFIED" | awk -F'\t' -v ex=" $EXH_SIDS " '
      NF && $3 != "" { if ($NF == "INTERRUPTED" && !index(ex, " " $2 " ")) intr[$3] = 1; else rest[$3] = 1 }
      END { for (c in intr) { bad = (c ~ / /); for (r in rest) if (index(r, c)) bad = 1
                              if (!bad) print c } }' | sort | tr '\n' ' ')"
  nudged="${nudged% }"
  # Restore v2 starts NO keepalive. It re-types into any idle pane whose cwd holds a marker, and on
  # 2026-10-01 typed prompts did not submit in 30 of 31 panes. The prompt already went out as a
  # launch argument (step 2b); what is left is to read each one back from the transcript.
  if [ "$RESTORE_V2" = 1 ]; then
    nudged=""
    if [ -n "$PROMPTED" ] && command -v rn_confirm >/dev/null 2>&1; then
      # CONFIRM: within CC_RESTORE_CONFIRM_S of the layout returning, a user record with the nonce
      # (submitted) and a real assistant record after it (a turn ran). One shared deadline.
      # R7 (2026-10-21): the deadline is WALL CLOCK. It used to lose CC_RESTORE_CONFIRM_POLL per round
      # however long the round took, and at load one round of rn_confirm calls took minutes, so 90 s
      # ran from 15:35 to 16:10. A session confirmed once is not asked again, and the report below
      # reuses each session's last answer instead of re-reading every transcript.
      c_end=$(( $(date +%s) + ${CC_RESTORE_CONFIRM_S:-90} )); c_poll="${CC_RESTORE_CONFIRM_POLL:-5}"
      C_RES=""   # "<sid>\t<rc>\t<seen>", the newest answer per sid last
      while :; do
        c_open=0
        while IFS=$'\t' read -r sid pf nonce p_cwd; do
          [ -n "$sid" ] || continue
          # Confirmed already (a "<sid>\t0\t" line)? A string match, not a pipe into an early-exit test.
          case "
${C_RES}" in *"
${sid}	0	"*) continue ;; esac
          c_rc=0; c_seen="$(confirm_one "$sid" "$nonce" "$p_cwd" 2>/dev/null)" || c_rc=$?
          C_RES="${C_RES}${sid}	${c_rc}	${c_seen}
"
          [ "$c_rc" = 0 ] || c_open=$((c_open + 1))
        done <<EOF
$PROMPTED
EOF
        [ "$c_open" -gt 0 ] && [ "$(date +%s)" -lt "$c_end" ] || break
        sleep "$c_poll"
      done
      while IFS=$'\t' read -r sid pf nonce p_cwd; do
        [ -n "$sid" ] || continue
        c_last="$(printf '%s\n' "$C_RES" | awk -F'\t' -v s="$sid" '$1 == s { l = $0 } END { print l }')"
        c_rc="$(printf '%s' "$c_last" | cut -f2)"; c_seen="$(printf '%s' "$c_last" | cut -f3)"
        case "$c_rc" in ''|*[!0-9]*) c_rc=2 ;; esac
        case "$c_rc" in
          0) c_v=confirmed; n_prompt_ok=$((n_prompt_ok + 1)) ;;
          # Submitted, but no turn ran (an account at its limit looks like this). A second submit
          # would run the recovery twice, so this is reported, never retried.
          1) c_v=submitted-no-reply; n_prompt_noreply=$((n_prompt_noreply + 1)) ;;
          *) # Never submitted: cc-wake, then the verified paste. Never a blind CR.
             if c_fb="$(rn_fallback "$sid" "$pf" "$nonce" "$p_cwd" 2>/dev/null)"; then
               c_v="fallback ${c_fb}"; n_prompt_fb=$((n_prompt_fb + 1))
             else
               c_v="unconfirmed ${c_fb}"; n_prompt_bad=$((n_prompt_bad + 1))
             fi ;;
        esac
        printf '%s sid=%s nonce=%s %s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$sid" "$nonce" "${c_seen:-user=0 assistant=0}" "$c_v" \
          >> "$EVENT_DIR/prompt.log" 2>/dev/null
      done <<EOF
$PROMPTED
EOF
    fi
    # 5. DRAFTS. alarm-reboot-prep.sh saved the text that sat unsent in each pane's prompt box; each
    #    one is typed back into the pane its session came back in, and never submitted. After the
    #    prompts above, because their fallback pastes into the same box and must find it empty. Only
    #    for the panes THIS round's layout opened: a map left by an earlier restore names window ids
    #    of a kitty that is gone, and the same number now belongs to some other pane.
    if [ -z "$EVENT" ] && [ "$layout_ran" = 1 ] && [ -s "$STATE_DIR/last-layout.map" ] \
       && command -v rd_putback >/dev/null 2>&1 && drafts_dir="$(rd_pick "$ROSTER_DIR" "$LOWER" "$BOOT")"; then
      # The socket is handed to these calls only (launchd gives this job no KITTY_WINDOW_ID).
      d_sock="${CC_TERM_KITTY_TO:-}"
      [ -z "$d_sock" ] && [ -n "$KSOCK_BIN" ] && d_sock="$(cc_run "$KSOCK_BIN" 2>/dev/null | head -1)"
      d_sum="$(CC_TERM_KITTY_TO="$d_sock" rd_putback "$drafts_dir" "$STATE_DIR/last-layout.map" "$EVENT_DIR/drafts.log" 2>/dev/null )" || d_sum=""
      n_draft_typed="$(num "$(kv typed "$d_sum")")"
      n_draft_kept="$(num "$(kv kept "$d_sum")")"
      n_draft_left="$(num "$(kv left "$d_sum")")"
    fi
  fi
  if [ -n "$nudged" ] && [ "$resumed" -gt 0 ] && [ -n "$KEEPALIVE" ] && [ -x "$KEEPALIVE" ]; then
    # Under launchd there is no KITTY_WINDOW_ID, and the keepalive's kitty arm is inert without a
    # socket, so hand it the live one. Detached into its own session: launchd reaps the job's
    # process group when this script exits, and a nohup'd child shares that group.
    ka_sock="${CC_TERM_KITTY_TO:-}"
    [ -z "$ka_sock" ] && [ -n "$KSOCK_BIN" ] && ka_sock="$(cc_run "$KSOCK_BIN" 2>/dev/null | head -1)"
    mkdir -p "$HOME/.reso" 2>/dev/null || true
    _dl="$(dirname "$0")/lib/detach.sh"
    # shellcheck source=lib/detach.sh
    # shellcheck disable=SC1091  # runtime-resolved source; the ship gate runs shellcheck without -x
    cc_argv "$KEEPALIVE"   # reso-keepalive is #!: detach/nohup run its interpreter (cc-run.sh)
    if [ -f "$_dl" ] && . "$_dl" 2>/dev/null && command -v detach >/dev/null 2>&1; then
      detach "$HOME/.reso/keepalive.out" env CC_KEEPALIVE_MARKERS="$nudged" CC_TERM_KITTY_TO="$ka_sock" \
        "${CC_ARGV[@]}" "$KEEPALIVE_INTERVAL" >/dev/null 2>&1 || true
    else
      CC_KEEPALIVE_MARKERS="$nudged" CC_TERM_KITTY_TO="$ka_sock" \
        nohup "${CC_ARGV[@]}" "$KEEPALIVE_INTERVAL" >>"$HOME/.reso/keepalive.out" 2>&1 &
      disown 2>/dev/null || true
    fi
  fi
fi

# ── build the boot-delta page (T-P16-7): what was open, jobs status, and what to do. ──
boot_h="$(date -u -r "$BOOT" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || printf '%s' "$BOOT")"
# An event is a kitty restart or crash inside a running boot, and the page must not call it a reboot.
cut_what=rebooted; [ -n "$EVENT" ] && cut_what="kitty ${EVENT_KIND} at"
listing=""
shown=0
while IFS=$'\t' read -r acct cwd sid name _br; do
  acct="$(unpad "$acct")"; cwd="$(unpad "$cwd")"; sid="$(unpad "$sid")"; name="$(unpad "$name")"
  [ -n "$sid" ] || continue
  if [ "$shown" -lt 8 ]; then
    listing="${listing}  - ${name:-$sid} [$(map_account "$acct")] $(basename "${cwd:-?}") (${sid:0:8})
"
    shown=$((shown + 1))
  fi
done <<EOF
$GHOSTS
EOF
[ "$n_open" -gt "$shown" ] && listing="${listing}  … +$((n_open - shown)) more
"
# The skipped and held sessions are NAMED, each retired one with the command that brings it back: a
# skip is a judgment about intent, and the operator is the one who can overrule it.
_pl="$(page_lists)"; [ -n "$_pl" ] && listing="${listing}${_pl#
}
"

if [ "$MODE" = "resume" ]; then
  where="one window each"
  [ "$opener" = desktops ] && where="${desk_windows} fullscreen Desktop(s), ${desk_fs_ok} verified fullscreen"
  msg="🔄 boot-delta: ${cut_what} ${boot_h} · source: ${SOURCE_LABEL} · resumed ${resumed}/${n_fire} session(s) into ${where}.
  ${n_int} were cut off mid-turn and are being nudged to continue; ${n_rest} had stopped at a pause point (or could not be read) and were restored WITHOUT a nudge."
  # Restore v2 delivers differently, so it says something different: a note for every session, and a
  # launch-argument prompt only where work was open. The keepalive sentence above would be false.
  [ "$RESTORE_V2" = 1 ] && msg="🔄 boot-delta: ${cut_what} ${boot_h} · source: ${SOURCE_LABEL} · resumed ${resumed}/${n_fire} session(s) into ${where}.
  ${n_int} were cut off mid-turn and ${n_wake} were at rest with work that died with the old process; ${n_rest} had stopped at a pause point (or could not be read). ${n_noted} got an inbox note saying what was lost; ${n_prompt} with open work and quota got a recovery prompt as a launch argument (${n_prompt_ok} confirmed in the transcript, ${n_prompt_fb} delivered by the fallback)."
  [ "$desk_fs_bad" -gt 0 ] && msg="${msg} ⚠ ${desk_fs_bad} window(s) did not go fullscreen (Accessibility permission for kitty?) — the panes are fine, only the Desktop placement is not."
  [ "$n_open" -gt "$n_fire" ] && msg="${msg}
  consolidated: ${n_open} ghost(s) → ${n_fire} fired (max ${MAX_PER_WT}/worktree, ${MAX_TOTAL} total). The rest are LISTED, not lost — ${STATE_DIR}/last-triage.txt"
  [ "$resume_fail" -gt 0 ] && msg="${msg} ⚠ ${resume_fail} failed to launch — check /resume-sessions."
  # A shed session is deferred, not lost, and it must SAY so: a boot-delta reading "resumed 1/4"
  # with no other line is indistinguishable from three launcher failures (§12.4's whole concern is
  # that the boot storm silently eats the recovery).
  # Each arm keeps its condition and its message on ONE line: tests/capacity-admit-coverage.bats (22)
  # keys on the emitting statement, so a counted shed that tells nobody fails it.
  shed_retry=0; { [ "$RESTORE_V2" = 1 ] && ! restore_done; } && shed_retry=1
  [ "$resume_shed" -gt 0 ] && [ "$shed_retry" = 1 ] && msg="${msg} ⏸ ${resume_shed} shed by the capacity gate — this restore runs again for them until $(date -r "$(restore_deadline)" +%H:%M 2>/dev/null), and its ledger keeps any session from opening twice."
  [ "$resume_shed" -gt 0 ] && [ "$shed_retry" = 0 ] && msg="${msg} ⏸ ${resume_shed} shed by the capacity gate (box saturated at boot) — re-run /resume-sessions once it settles."
  if [ "$RESTORE_V2" = 1 ]; then
    [ "$resume_ledger" -gt 0 ] && msg="${msg} ${resume_ledger} were already opened by an earlier round of this restore."
    [ "$n_exhausted" -gt 0 ] && msg="${msg} ⚠ ${n_exhausted} sit on account(s) at their weekly limit (${EXHAUSTED_ACCTS% }): restored, never nudged."
    [ "$n_note_fail" -gt 0 ] && msg="${msg} ⚠ ${n_note_fail} inbox note(s) could not be written."
    command -v rn_note_text >/dev/null 2>&1 || msg="${msg} ⚠ scripts/lib/restore-note.sh did not load: no notes and no prompts this round."
    [ "$n_prompt_noreply" -gt 0 ] && msg="${msg} ⚠ ${n_prompt_noreply} prompt(s) were submitted but no turn ran (${EVENT_DIR}/prompt.log)."
    [ "$n_prompt_bad" -gt 0 ] && msg="${msg} ⚠ ${n_prompt_bad} prompt(s) never reached their session, and the fallback could not deliver them either (${EVENT_DIR}/prompt.log) — those sessions are back but idle."
    [ "${CC_RESTORE_NUDGE:-on}" = off ] && msg="${msg} CC_RESTORE_NUDGE=off: notes only, no prompts."
    [ "$n_draft_typed" -gt 0 ] && msg="${msg} ✏ ${n_draft_typed} unsent draft(s) saved before the reboot were typed back into their prompt box, not sent."
    [ "$n_draft_kept" -gt 0 ] && msg="${msg} ⚠ ${n_draft_kept} saved draft(s) were NOT typed back, because the box was not empty or could not be read; the text is in ${drafts_dir}/<session id>/draft.txt (${EVENT_DIR}/drafts.log says why)."
    [ "$n_draft_left" -gt 0 ] && msg="${msg} ${n_draft_left} saved draft(s) belong to sessions this round did not open; they stay in ${drafts_dir}."
    [ "$n_meta_none" -gt 0 ] && msg="${msg} ${n_meta_none} had no recorded model or effort, so they came back on the launcher's defaults."
    [ "$n_mail_carried" -gt 0 ] && msg="${msg} ✉ the unread mail of ${n_mail_carried} session(s) was carried from its old pane number to the session (${MAIL_LOG})."
  fi
  [ "$resume_held" -gt 0 ] && msg="${msg} ⏸ ${resume_held} not launched — owned by the limit-recovery reconciler, already running, parked for the reboot, or an Agent Teams member its lead owns (see cc-lr status --cohort)."
  [ "$resume_indet" -gt 0 ] && msg="${msg} ⏳ ${resume_indet} launch indeterminate, reconciling — kitty did not answer in time and no window has appeared yet; cc-resume-debt's sweep relaunches only if none appears (see cc-resume-debt list --open)."
  msg="${msg}
${listing}desk-jobs: ${dj_up}/${dj_total} com.claude agent(s) up."
else
  msg="🔄 boot-delta: ${cut_what} ${boot_h} · ${n_open} session(s) were live when the box went down (source: ${SOURCE_LABEL}; NOT auto-resumed, posture=page):
${listing}desk-jobs: ${dj_up}/${dj_total} com.claude agent(s) up.
→ resume: /resume-sessions   ·   enable auto-resume: echo resume > ${STATE_DIR}/mode"
fi

V2_IDL=""
if [ "$RESTORE_V2" = 1 ]; then
  V2_IDL=",\"restore_v2\":true,\"wake_lost\":${n_wake},\"noted\":${n_noted},\"note_failed\":${n_note_fail},\"prompts\":${n_prompt},\"prompts_confirmed\":${n_prompt_ok},\"prompts_fallback\":${n_prompt_fb},\"prompts_no_reply\":${n_prompt_noreply},\"prompts_unconfirmed\":${n_prompt_bad},\"drafts_typed\":${n_draft_typed},\"drafts_kept\":${n_draft_kept},\"ledger_skipped\":${resume_ledger},\"exhausted\":${n_exhausted},\"no_model\":${n_meta_none},\"gate\":\"none\",\"load_per_core\":\"${load_per_core:-}\",\"cut\":${CUT},\"cut_src\":\"${CUT_SRC}\",\"owner\":\"${OWNER_SID}\",\"mail_carried\":${n_mail_carried},\"retired_by_classifier\":${n_ret_cls},\"done\":$(restore_done && echo true || echo false)"
  # This round's early page landed (R8): the follow-up, with the confirmed counts, goes to the same
  # session, and the round ends there.
  if [ -n "$EARLY_TO" ]; then
    [ -n "$NOTIFY" ] && cc_run "$NOTIFY" "$EARLY_TO" "(follow-up, prompts confirmed) ${msg}" >/dev/null 2>&1
    mark_processed
    log_idl fired ",\"n_open\":$n_open,\"resumed\":$resumed,\"resume_failed\":$resume_fail,\"resume_shed\":$resume_shed,\"resume_held\":$resume_held,\"interrupted\":$n_int,\"at_rest\":$n_rest,\"opener\":\"$opener\",\"fullscreen_ok\":$desk_fs_ok,\"fullscreen_failed\":$desk_fs_bad,\"desk_jobs_up\":$dj_up,\"desk_jobs_total\":$dj_total,\"notified\":\"$EARLY_TO\",\"notified_as\":\"$EARLY_KIND\",\"early_page\":true,\"delivered\":true${V2_IDL}"
    exit 0
  fi
  # One page per event, not per round: a later round marks and logs, and says nothing.
  if [ -z "$BL_PID" ] && [ -f "$EVENT_DIR/paged" ]; then
    mark_processed
    log_idl fired ",\"n_open\":$n_open,\"resumed\":$resumed,\"resume_failed\":$resume_fail,\"resume_shed\":$resume_shed,\"resume_held\":$resume_held,\"delivered\":true,\"channel\":\"already-paged\"${V2_IDL}"
    exit 0
  fi
fi

# ── deliver: the owner session, else the desk role, else a live lead role (resolve_page_target).
#    Nobody ⇒ the backlog; that failing too ⇒ FAIL LOUD, do NOT mark processed. ──
if [ -z "$BL_PID" ] && resolve_page_target && [ -n "$NOTIFY" ]; then
  cc_run "$NOTIFY" "$PAGE_TO" "$msg" >/dev/null 2>&1 || true   # cc-notify's mailbox fallback ⇒ durable at exit 0
  paged_once
  mark_processed
  log_idl fired ",\"n_open\":$n_open,\"resumed\":$resumed,\"resume_failed\":$resume_fail,\"resume_shed\":$resume_shed,\"resume_held\":$resume_held,\"interrupted\":$n_int,\"at_rest\":$n_rest,\"opener\":\"$opener\",\"fullscreen_ok\":$desk_fs_ok,\"fullscreen_failed\":$desk_fs_bad,\"desk_jobs_up\":$dj_up,\"desk_jobs_total\":$dj_total,\"notified\":\"$PAGE_TO\",\"notified_as\":\"$PAGE_KIND\",\"delivered\":true${V2_IDL}"
  exit 0
else
  # ── a wake with nobody to WAKE is not a wake with nobody to TELL. ────────────────────────────────
  # Two distinct causes reach this branch and the record must say which: nobody to page, or
  # cc-notify itself did not resolve. The old record called both "no-desk-role", which sends the next
  # reader at the roles dir for a fault that may be in resolve_bin's ladder.
  why=no-desk-role
  [ -n "$PAGE_TO" ] && why=no-notify-bin
  [ -n "$BL_PID" ] && why="${BL_WHY:-$why}"

  # The page itself, verbatim, on disk beside this script's own state — the one store that needs no
  # address, no daemon and no drain. It is what the backlog row POINTS AT, so the row stays one line.
  # When the early page already filed the row, this rewrites the file it points at with the full text.
  mkdir -p "$STATE_DIR" 2>/dev/null || true
  undeliv="$STATE_DIR/undelivered-$BOOT.page"
  printf '%s\n' "$msg" > "$undeliv" 2>/dev/null || true

  # The step text carries the whole decision: how many, when, where the full text is, what to run,
  # and the cure for the CLASS (claim the role) so the next boot does not come back here. It says
  # what actually happened (R8): "nothing was told" over 26 resumed sessions was false on 2026-10-21.
  # No --run: the recovery is a slash command inside a Claude session, not a shell command, and
  # `cc-roles claim desk` would bind the role to cc-do's throwaway shell rather than to the desk pane.
  # cmd_needs' own header says an absent falsifier is honest and a fabricated one lies; same here.
  bid=""
  if [ -n "$BL_PID" ]; then
    wait "$BL_PID" 2>/dev/null
    bid="$(tail -1 "$BL_OUT" 2>/dev/null | tr -d '[:space:]')"
  elif [ -n "$BACKLOG" ]; then
    bid="$(cc_run "$BACKLOG" needs "$(backlog_step "$why")" --class needs-human --receipt "$undeliv" --project claude-infrastructure 2>/dev/null | tail -1 | tr -d '[:space:]')"
  fi
  # An id is hex. Anything else — a warning line, an empty write, a usage error — is NOT a filing,
  # and treating it as one is how a fallback reports delivery it never made.
  case "$bid" in ''|*[!0-9a-f]*) bid="" ;; esac

  if [ -n "$bid" ]; then
    # DELIVERED, durably, to a lane that is read. Marking here is what converts an unbounded silent
    # retry into one surfaced item — the whole point of the fallback.
    paged_once
    mark_processed
    log_idl fired ",\"n_open\":$n_open,\"resumed\":$resumed,\"resume_failed\":$resume_fail,\"resume_shed\":$resume_shed,\"resume_held\":$resume_held,\"interrupted\":$n_int,\"at_rest\":$n_rest,\"opener\":\"$opener\",\"fullscreen_ok\":$desk_fs_ok,\"fullscreen_failed\":$desk_fs_bad,\"desk_jobs_up\":$dj_up,\"desk_jobs_total\":$dj_total,\"delivered\":true,\"channel\":\"backlog-needs\",\"backlog_id\":\"$bid\",\"reason\":\"$why\"${V2_IDL}"
    echo "boot-resume: no desk role — the ${n_open}-session boot delta was filed as operator-blocked backlog item $bid (full text: $undeliv)" >&2
    exit 0
  fi

  # The addressless channel failed TOO. Now the original polarity is the right one: a17 S-7 stands —
  # do NOT mark, so a re-run re-attempts both legs.
  log_idl failed ",\"n_open\":$n_open,\"resumed\":$resumed,\"delivered\":false,\"reason\":\"$why\",\"fallback\":\"backlog-unavailable\""
  echo "boot-resume: ${n_open} session(s) open at last boot, no desk role at $ROLES_DIR/desk AND cc-backlog unavailable — undelivered, will retry (full text: $undeliv)" >&2
  exit 4
fi
