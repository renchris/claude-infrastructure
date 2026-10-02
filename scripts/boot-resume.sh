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
#                 macOS Desktop each), start the keepalive scoped to the INTERRUPTED rows only, then
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
#   closed itself on purpose too) · CC_BOOT_RESUME_ACTIVITY_TAIL (transcript lines read, default 4000).
# BSD+GNU portable, no eval, fail-loud. bash 3.2-safe.
set -uo pipefail

REGISTRY_DIR="${CC_REGISTRY_DIR:-$HOME/.claude/cc-registry}"
ROLES_DIR="${CC_ROLES_DIR:-$HOME/.claude/cc-roles}"
IDL="${CC_IDL:-$HOME/.claude/autonomy/idl.jsonl}"
STATE_DIR="${CC_BOOT_RESUME_STATE_DIR:-$HOME/.claude/autonomy/boot-resume}"
KEEPALIVE_INTERVAL="${CC_KEEPALIVE_INTERVAL:-240}"

usage() { sed -n '2,/^set -uo/p' "$0" | sed 's/^# \{0,1\}//; /^set -uo/d'; }
case "${1:-}" in -h|--help) usage; exit 0 ;; esac

command -v jq >/dev/null 2>&1 || { echo "boot-resume: jq required" >&2; exit 1; }

now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }

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
NOTIFY="$(resolve_bin "${CC_NOTIFY_BIN:-}" cc-notify)"
# The addressless fallback for a delta with no desk role (see step 3 in the header). Resolved
# here rather than at the use site so an unresolvable cc-backlog is a KNOWN-empty string on the
# one path that reads it, never a bare name hitting the launchd PATH (/usr/bin:/bin).
BACKLOG="$(resolve_bin "${CC_BACKLOG_BIN:-}" cc-backlog)"
LAUNCH="$(resolve_bin "${CC_RESUME_LAUNCH_BIN:-}" boot-resume-launch.sh boot-resume-launch.sh)"
# The batch opener (2x2 per native-fullscreen Desktop) and the nudge classifier. Both live in bin/;
# resolve_bin's ../bin rung finds them from scripts/. An absent layout falls back to one window per
# session through $LAUNCH (the pre-2026-09-30 path); an absent classifier makes every row UNKNOWN,
# which is the fail-safe direction (restored, never nudged).
LAYOUT="$(resolve_bin "${CC_RESUME_LAYOUT_BIN:-}" cc-resume-layout.sh)"
CLASSIFY="$(resolve_bin "${CC_RESUME_CLASSIFY_BIN:-}" cc-resume-classify.py)"
KSOCK_BIN="$(resolve_bin "${CC_KITTY_SOCKET_BIN:-}" cc-kitty-socket)"
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
MARKER="$STATE_DIR/last-boot-epoch"

case "${1:-}" in --print-boottime) printf '%s\n' "$BOOT"; exit 0 ;; esac

log_idl() { # <disposition> <extra-json>
  mkdir -p "$(dirname "$IDL")" 2>/dev/null || true
  printf '{"ts":"%s","tool":"boot-resume","disposition":"%s","boot":"%s","mode":"%s","source":"%s","retired_skipped":%s%s}\n' \
    "$(now_iso)" "$1" "$BOOT" "$MODE" "$SOURCE" "${n_retired:-0}" "${2:-}" >> "$IDL" 2>/dev/null || true
}

# ── guard: unreadable boottime is a blind check → abstain LOUD, never mark, never act. ──
if [ -z "$BOOT" ]; then
  log_idl abstained ',"reason":"no-boottime"'
  echo "boot-resume: could not read kern.boottime — abstaining" >&2
  exit 0
fi

# ── idempotency: this boot already handled → exactly-one-page invariant. ──
if [ -f "$MARKER" ] && [ "$(cat "$MARKER" 2>/dev/null)" = "$BOOT" ]; then
  log_idl abstained ',"reason":"already-processed","n_open":0,"resumed":0'
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
prev_boot="$(tr -d '[:space:]' < "$MARKER" 2>/dev/null)"
case "$prev_boot" in
  ''|*[!0-9]*) ;;
  *) [ "$prev_boot" -lt "$BOOT" ] && [ "$prev_boot" -gt "$LOWER" ] && LOWER="$prev_boot" ;;
esac

# 1. roster — the snapshot a scripted reboot takes of `cc-sessions --json`. A roster that parses and
#    lists nobody is an answer ("nothing was live"), so it ends the search; one that does not parse
#    is not, so the search goes on.
roster=""; roster_start=0
for f in "$ROSTER_DIR"/reboot-*.roster.json; do
  [ -f "$f" ] || continue
  st="$(tr -d '[:space:]' < "${f%.roster.json}.start" 2>/dev/null)"
  case "$st" in ''|*[!0-9]*) continue ;; esac
  { [ "$st" -gt "$LOWER" ] && [ "$st" -lt "$BOOT" ] && [ "$st" -gt "$roster_start" ]; } || continue
  roster="$f"; roster_start="$st"
done
if [ -n "$roster" ]; then
  if rows="$(jq -r --arg pad "$TSV_PAD" "$JQ_CELL"'
        [ (if type == "array" then . else (.sessions // []) end)[]
          | select(type == "object" and (.session_id // "") != "") ]
        | unique_by(.session_id)[]
        | [(.account|cell), (.cwd|cell), (.session_id|cell), (.name|cell), (.branch|cell)] | @tsv' \
        "$roster" 2>/dev/null)"; then
    SOURCE=roster; SOURCE_LABEL="roster $(basename "$roster" .roster.json)"; ANCHOR="$roster_start"
    read_rows "$rows"
  fi
fi

# 2. shutdown tombstones (hooks/session-deregister.sh). reason=other also fires when the operator
#    closes ONE pane, so a tombstone alone is not a shutdown. What is: the LAST burst before the boot.
#    A shutdown SIGHUPs every pane together (measured: 19 sessions ended inside 4 s at 15:25:27-31
#    on 2026-09-30), while a closed pane is a lone earlier stamp. Where the kernel had already set
#    kern.willshutdown when the hook ran, those tombstones are taken outright instead.
if [ -z "$SOURCE" ] && [ -d "$TOMB_DIR" ]; then
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
retired_marker() { # <sid> → "<mode>\t<ts to the second>" for a self-close marker, else ""
  [ -f "$TEARDOWN_DIR/$1.json" ] || return 0
  jq -r --arg sid "$1" 'select(type == "object" and .sid == $sid
           and (.mode == "terminal" or .mode == "successor") and (.ts | type) == "string")
         | [.mode, .ts[0:19]] | @tsv' "$TEARDOWN_DIR/$1.json" 2>/dev/null
}
iso_sec() { case "$1" in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]) return 0 ;; esac; return 1; }
RETIRED=""; n_retired=0
if [ "${CC_BOOT_RESUME_SKIP_RETIRED:-on}" != off ] && [ "$n_open" -gt 0 ]; then
  KEPT=""; n_kept=0
  while IFS=$'\t' read -r k_acct k_cwd k_sid k_name k_br; do
    [ -n "$k_sid" ] && [ "$k_sid" != "$TSV_PAD" ] || continue
    r_sid="$(unpad "$k_sid")"; r_acct="$(unpad "$k_acct")"
    mk="$(retired_marker "$r_sid" | head -1)"
    if [ -n "$mk" ]; then
      mk_mode="${mk%%	*}"; mk_ts="${mk#*	}"
      tf="$(transcript_file "$r_acct" "$r_sid")"; act=""
      [ -n "$tf" ] && act="$(last_activity "$tf")"
      if iso_sec "$mk_ts" && iso_sec "$act" && [[ "$mk_ts" > "$act" ]]; then
        r_alias="$(map_account "$r_acct")"; r_launcher=""
        command -v cc_acct_launcher_for_name >/dev/null 2>&1 && r_launcher="$(cc_acct_launcher_for_name "$r_alias")"
        r_name="$(unpad "$k_name")"; r_cwd="$(unpad "$k_cwd")"
        RETIRED="${RETIRED}  - ${r_name:-${r_sid:0:8}} (${r_sid}): ${mk_mode} self-close marker ${TEARDOWN_DIR}/${r_sid}.json at ${mk_ts}Z, after its last activity ${act}Z — to bring it back: cd '${r_cwd:-.}' && ${r_launcher:-claude} --resume ${r_sid}
"
        n_retired=$((n_retired + 1))
        continue
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

mark_processed() { mkdir -p "$STATE_DIR" 2>/dev/null || true; printf '%s\n' "$BOOT" > "$MARKER" 2>/dev/null || true; }

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
resume_held=0   # rc 5: not ours to launch — the reconciler owns it, its launch lock is held, it already
                # has a live holder, or it is PARKED-REBOOT in page mode. Not broken, not waiting on us.
n_fire=0        # sessions SELECTED to fire (post-consolidation) — distinct from n_open (sessions found)
n_int=0         # classifier verdicts over the sessions that passed the ownership check
n_rest=0
opener=""       # desktops (cc-resume-layout --desktops) | windows (one launcher window per session)
desk_windows=0; desk_fs_ok=0; desk_fs_bad=0
nudged=""       # the keepalive's markers: cwds of INTERRUPTED sessions only
kv() { printf '%s\n' "$2" | tr ' ' '\n' | sed -n "s/^$1=//p" | head -1; }   # <key> <summary-line>
num() { case "$1" in ''|*[!0-9]*) printf 0 ;; *) printf '%s' "$1" ;; esac; }
if [ "$MODE" = "resume" ]; then
  if [ -z "$LAUNCH" ] || [ ! -x "$LAUNCH" ]; then
    log_idl failed ",\"n_open\":$n_open,\"resumed\":0,\"delivered\":false,\"reason\":\"no-resume-launcher\""
    echo "boot-resume: mode=resume but no executable resume launcher — not marking boot; will retry" >&2
    exit 3
  fi
  mkdir -p "$STATE_DIR" 2>/dev/null || true
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
  ADMITTED=""
  while IFS=$'\t' read -r alias sid cwd br label; do
    alias="$(unpad "$alias")"; sid="$(unpad "$sid")"; cwd="$(unpad "$cwd")"
    br="$(unpad "$br")"; label="$(unpad "$label")"
    [ -n "$sid" ] || continue
    if [ -z "$br" ] && [ -n "$cwd" ] && [ -d "$cwd" ]; then
      br="$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
      [ "$br" = HEAD ] && br=""
    fi
    "$LAUNCH" --check-only "$alias" "$cwd" "$sid" "$br" >/dev/null 2>&1
    case "$?" in
      0) ;;
      5) resume_held=$((resume_held + 1)); continue ;;
      *) resume_fail=$((resume_fail + 1)); continue ;;
    esac
    ADMITTED="${ADMITTED}${alias}	${sid}	${cwd}	${br}	${label:-${sid:0:8}}
"
  done <<EOF
$WINNERS
EOF

  # 2. CLASSIFY: which of them the shutdown INTERRUPTED mid-turn. Only those are nudged. A failed
  #    classifier, or one that returned a different number of rows, is no evidence at all, so every
  #    row becomes UNKNOWN — restored, never nudged (the classifier's own fail-safe polarity).
  n_adm="$(printf '%s' "$ADMITTED" | grep -c . || true)"
  CLASSIFIED=""
  if [ "$n_adm" -gt 0 ] && [ -n "$CLASSIFY" ] && [ -x "$CLASSIFY" ]; then
    CL_ARGS=()
    [ "$SOURCE" != registry ] && CL_ARGS=(--boot-epoch "$ANCHOR")
    CLASSIFIED="$(printf '%s' "$ADMITTED" | "$CLASSIFY" ${CL_ARGS[@]+"${CL_ARGS[@]}"} 2>"$STATE_DIR/last-classify.txt")" || CLASSIFIED=""
  fi
  if [ "$(printf '%s' "$CLASSIFIED" | grep -c . || true)" != "$n_adm" ]; then
    CLASSIFIED="$(printf '%s' "$ADMITTED" | awk -F'\t' 'NF { print $0 "\tUNKNOWN" }')"
  fi
  n_int="$(printf '%s\n' "$CLASSIFIED" | awk -F'\t' '$NF == "INTERRUPTED"' | grep -c . || true)"
  n_rest=$((n_adm - n_int))

  # 3. OPEN. The operator's layout: <=4 panes per OS window as a 2x2, each window native-fullscreen
  #    on its own Desktop (cc-resume-layout.sh --desktops). At login there may be no kitty yet — exit
  #    3 means no live control socket — so open one and give it a moment before falling back.
  layout_rc=127; layout_sum=""
  if [ "$n_adm" -gt 0 ] && [ -n "$LAYOUT" ] && [ -x "$LAYOUT" ]; then
    tries="${CC_BOOT_RESUME_KITTY_TRIES:-10}"; poll="${CC_BOOT_RESUME_KITTY_POLL:-3}"; opened=0
    while :; do
      # To a file, not $( … | grep): the layout's exit status is the verdict (3 = no kitty), and a
      # command substitution's pipeline status never reaches this shell. pipefail makes $? the
      # layout's own, since printf cannot fail here.
      printf '%s' "$ADMITTED" | "$LAYOUT" --desktops >"$STATE_DIR/last-layout.out" 2>>"$STATE_DIR/last-layout.txt"
      layout_rc=$?
      layout_sum="$(grep '^cc-resume-layout: verdict=' "$STATE_DIR/last-layout.out" 2>/dev/null | tail -1)"
      [ "$layout_rc" = 3 ] && [ "$tries" -gt 0 ] || break
      [ "$opened" = 1 ] || { "$OPEN_BIN" -a kitty >/dev/null 2>&1; opened=1; }
      tries=$((tries - 1)); sleep "$poll"
    done
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
      "$LAUNCH" "$alias" "$cwd" "$sid" "$br" >/dev/null 2>&1
      case "$?" in
        0) resumed=$((resumed + 1)) ;;
        9) resume_shed=$((resume_shed + 1)) ;;
        5) resume_held=$((resume_held + 1)) ;;
        *) resume_fail=$((resume_fail + 1)) ;;
      esac
    done <<EOF
$ADMITTED
EOF
  fi

  # 4. KEEPALIVE, scoped to the INTERRUPTED sessions. It re-nudges any idle pane whose cwd CONTAINS
  #    a marker, and it cannot tell a parked session from a stalled one — so a marker must never
  #    reach an AT-REST pane: a cwd shared with (or a prefix of) any non-INTERRUPTED row is dropped,
  #    and so is a cwd with a space (the marker list is space-separated). No marker ⇒ no keepalive.
  nudged="$(printf '%s\n' "$CLASSIFIED" | awk -F'\t' '
      NF && $3 != "" { if ($NF == "INTERRUPTED") intr[$3] = 1; else rest[$3] = 1 }
      END { for (c in intr) { bad = (c ~ / /); for (r in rest) if (index(r, c)) bad = 1
                              if (!bad) print c } }' | sort | tr '\n' ' ')"
  nudged="${nudged% }"
  if [ -n "$nudged" ] && [ "$resumed" -gt 0 ] && [ -n "$KEEPALIVE" ] && [ -x "$KEEPALIVE" ]; then
    # Under launchd there is no KITTY_WINDOW_ID, and the keepalive's kitty arm is inert without a
    # socket, so hand it the live one. Detached into its own session: launchd reaps the job's
    # process group when this script exits, and a nohup'd child shares that group.
    ka_sock="${CC_TERM_KITTY_TO:-}"
    [ -z "$ka_sock" ] && [ -n "$KSOCK_BIN" ] && ka_sock="$("$KSOCK_BIN" 2>/dev/null | head -1)"
    mkdir -p "$HOME/.reso" 2>/dev/null || true
    _dl="$(dirname "$0")/lib/detach.sh"
    # shellcheck source=lib/detach.sh
    # shellcheck disable=SC1091  # runtime-resolved source; the ship gate runs shellcheck without -x
    if [ -f "$_dl" ] && . "$_dl" 2>/dev/null && command -v detach >/dev/null 2>&1; then
      detach "$HOME/.reso/keepalive.out" env CC_KEEPALIVE_MARKERS="$nudged" CC_TERM_KITTY_TO="$ka_sock" \
        "$KEEPALIVE" "$KEEPALIVE_INTERVAL" >/dev/null 2>&1 || true
    else
      CC_KEEPALIVE_MARKERS="$nudged" CC_TERM_KITTY_TO="$ka_sock" \
        nohup "$KEEPALIVE" "$KEEPALIVE_INTERVAL" >>"$HOME/.reso/keepalive.out" 2>&1 &
      disown 2>/dev/null || true
    fi
  fi
fi

# ── build the boot-delta page (T-P16-7): what was open, jobs status, and what to do. ──
boot_h="$(date -u -r "$BOOT" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || printf '%s' "$BOOT")"
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
# The skipped sessions are NAMED, each with the command that brings it back: a skip is a judgment
# about intent, and the operator is the one who can overrule it.
[ "$n_retired" -gt 0 ] && listing="${listing}⏭ ${n_retired} not resumed — they closed themselves on purpose after their last activity:
${RETIRED}"

if [ "$MODE" = "resume" ]; then
  where="one window each"
  [ "$opener" = desktops ] && where="${desk_windows} fullscreen Desktop(s), ${desk_fs_ok} verified fullscreen"
  msg="🔄 boot-delta: rebooted ${boot_h} · source: ${SOURCE_LABEL} · resumed ${resumed}/${n_fire} session(s) into ${where}.
  ${n_int} were cut off mid-turn and are being nudged to continue; ${n_rest} had stopped at a pause point (or could not be read) and were restored WITHOUT a nudge."
  [ "$desk_fs_bad" -gt 0 ] && msg="${msg} ⚠ ${desk_fs_bad} window(s) did not go fullscreen (Accessibility permission for kitty?) — the panes are fine, only the Desktop placement is not."
  [ "$n_open" -gt "$n_fire" ] && msg="${msg}
  consolidated: ${n_open} ghost(s) → ${n_fire} fired (max ${MAX_PER_WT}/worktree, ${MAX_TOTAL} total). The rest are LISTED, not lost — ${STATE_DIR}/last-triage.txt"
  [ "$resume_fail" -gt 0 ] && msg="${msg} ⚠ ${resume_fail} failed to launch — check /resume-sessions."
  # A shed session is deferred, not lost, and it must SAY so: a boot-delta reading "resumed 1/4"
  # with no other line is indistinguishable from three launcher failures (§12.4's whole concern is
  # that the boot storm silently eats the recovery).
  [ "$resume_shed" -gt 0 ] && msg="${msg} ⏸ ${resume_shed} shed by the capacity gate (box saturated at boot) — re-run /resume-sessions once it settles."
  [ "$resume_held" -gt 0 ] && msg="${msg} ⏸ ${resume_held} not launched — owned by the limit-recovery reconciler, already running, or parked for the reboot (see cc-lr status --cohort)."
  msg="${msg}
${listing}desk-jobs: ${dj_up}/${dj_total} com.claude agent(s) up."
else
  msg="🔄 boot-delta: rebooted ${boot_h} · ${n_open} session(s) were live when the box went down (source: ${SOURCE_LABEL}; NOT auto-resumed, posture=page):
${listing}desk-jobs: ${dj_up}/${dj_total} com.claude agent(s) up.
→ resume: /resume-sessions   ·   enable auto-resume: echo resume > ${STATE_DIR}/mode"
fi

# ── deliver to the desk ROLE (resolved at send-time). No role ⇒ FAIL LOUD, do NOT mark processed. ──
DESK_TARGET=""
[ -f "$ROLES_DIR/desk" ] && DESK_TARGET="$(head -1 "$ROLES_DIR/desk" 2>/dev/null | tr -d '[:space:]')"

if [ -n "$DESK_TARGET" ] && [ -n "$NOTIFY" ]; then
  "$NOTIFY" "$DESK_TARGET" "$msg" >/dev/null 2>&1 || true   # cc-notify's mailbox fallback ⇒ durable at exit 0
  mark_processed
  log_idl fired ",\"n_open\":$n_open,\"resumed\":$resumed,\"resume_failed\":$resume_fail,\"resume_shed\":$resume_shed,\"resume_held\":$resume_held,\"interrupted\":$n_int,\"at_rest\":$n_rest,\"opener\":\"$opener\",\"fullscreen_ok\":$desk_fs_ok,\"fullscreen_failed\":$desk_fs_bad,\"desk_jobs_up\":$dj_up,\"desk_jobs_total\":$dj_total,\"notified\":\"$DESK_TARGET\",\"delivered\":true"
  exit 0
else
  # ── a wake with nobody to WAKE is not a wake with nobody to TELL. ────────────────────────────────
  # Two distinct causes reach this branch and the record must say which: the role is absent, or
  # cc-notify itself did not resolve. The old record called both "no-desk-role", which sends the next
  # reader at the roles dir for a fault that may be in resolve_bin's ladder.
  why=no-desk-role
  [ -n "$DESK_TARGET" ] && why=no-notify-bin

  # The page itself, verbatim, on disk beside this script's own state — the one store that needs no
  # address, no daemon and no drain. It is what the backlog row POINTS AT, so the row stays one line.
  mkdir -p "$STATE_DIR" 2>/dev/null || true
  undeliv="$STATE_DIR/undelivered-$BOOT.page"
  printf '%s\n' "$msg" > "$undeliv" 2>/dev/null || true

  # The step text carries the whole decision: how many, when, where the full text is, what to run,
  # and the cure for the CLASS (claim the role) so the next boot does not come back here.
  step="boot-resume could not page the desk ($why): ${n_open} session(s) were open before the ${boot_h} reboot and nothing was told. Full delta: ${undeliv} — recover with /resume-sessions in any Claude session, then run \`cc-roles claim desk\` from the desk pane so the next boot pages directly."
  # No --run: the recovery is a slash command inside a Claude session, not a shell command, and
  # `cc-roles claim desk` would bind the role to cc-do's throwaway shell rather than to the desk pane.
  # cmd_needs' own header says an absent falsifier is honest and a fabricated one lies; same here.
  bid=""
  if [ -n "$BACKLOG" ]; then
    bid="$("$BACKLOG" needs "$step" --class needs-human --receipt "$undeliv" --project claude-infrastructure 2>/dev/null | tail -1 | tr -d '[:space:]')"
    # An id is hex. Anything else — a warning line, an empty write, a usage error — is NOT a filing,
    # and treating it as one is how a fallback reports delivery it never made.
    case "$bid" in ''|*[!0-9a-f]*) bid="" ;; esac
  fi

  if [ -n "$bid" ]; then
    # DELIVERED, durably, to a lane that is read. Marking here is what converts an unbounded silent
    # retry into one surfaced item — the whole point of the fallback.
    mark_processed
    log_idl fired ",\"n_open\":$n_open,\"resumed\":$resumed,\"resume_failed\":$resume_fail,\"resume_shed\":$resume_shed,\"resume_held\":$resume_held,\"interrupted\":$n_int,\"at_rest\":$n_rest,\"opener\":\"$opener\",\"fullscreen_ok\":$desk_fs_ok,\"fullscreen_failed\":$desk_fs_bad,\"desk_jobs_up\":$dj_up,\"desk_jobs_total\":$dj_total,\"delivered\":true,\"channel\":\"backlog-needs\",\"backlog_id\":\"$bid\",\"reason\":\"$why\""
    echo "boot-resume: no desk role — the ${n_open}-session boot delta was filed as operator-blocked backlog item $bid (full text: $undeliv)" >&2
    exit 0
  fi

  # The addressless channel failed TOO. Now the original polarity is the right one: a17 S-7 stands —
  # do NOT mark, so a re-run re-attempts both legs.
  log_idl failed ",\"n_open\":$n_open,\"resumed\":$resumed,\"delivered\":false,\"reason\":\"$why\",\"fallback\":\"backlog-unavailable\""
  echo "boot-resume: ${n_open} session(s) open at last boot, no desk role at $ROLES_DIR/desk AND cc-backlog unavailable — undelivered, will retry (full text: $undeliv)" >&2
  exit 4
fi
