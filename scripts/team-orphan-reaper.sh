#!/bin/bash
# team-orphan-reaper.sh — Archive dead teams + auto-deny stale permission
# requests. Invoked by launchd every 10 minutes.
#
# A team whose lead is DECLARED OFF-BOX (`cc-cloud is-offbox`) is exempt from the whole ladder: every
# oracle here is local to this box, so all of them answer "dead" about a session that is merely
# elsewhere. See the OFF-BOX ABSTAIN block below. Such a team is also skipped by the stale-permission
# scan — that scan auto-DENIES on a local clock, and this file has no basis for a claim about the
# pace of a session it cannot see.
#
# A team is ARCHIVED only on POSITIVE evidence of death:
#   - ~/.claude/teams/<name>/config.json exists with a leadSessionId, AND
#   - that lead has an EXISTING watchdog pid file whose pid fails `kill -0` (dead), AND
#   - no live session (cc-sessions registry) occupies a member worktree or matches a member/lead name.
# A MISSING or empty watchdog pid file is UNKNOWN, not dead — the watchdog may not have written it yet,
# or an in-place /handoff of a named team left a stale leadSessionId whose pid file is gone while a
# SUCCESSOR actively drives the team. Such teams are SURFACED (logged + best-effort operator page),
# never archived: archiving a LIVE team erases cc-classify's owned-wait / coordination-hold signals and
# cascades toward the pane reaper. Absence of a pid file is not evidence of death.
#
# Also: for LIVE teams, scan inboxes for permission_request envelopes older
# than PERM_TIMEOUT_MIN (default 5); append a permission_response deny envelope
# so the teammate unblocks.
#
# Kill switch: export TEAM_ORPHAN_REAPER_DISABLED=1 (or launchctl unload)

set -uo pipefail

if [[ "${TEAM_ORPHAN_REAPER_DISABLED:-0}" == "1" ]]; then
  exit 0
fi

readonly TEAMS_DIR="${TEAM_REAPER_TEAMS_DIR:-$HOME/.claude/teams}"
readonly WATCHDOG_DIR="${TEAM_REAPER_WATCHDOG_DIR:-$HOME/.claude/watchdog}"
readonly ARCHIVE_DIR="$TEAMS_DIR/_archive"
readonly LOG_FILE="${TEAM_REAPER_LOG_FILE:-$HOME/.claude/logs/team-reaper.log}"
readonly PERM_TIMEOUT_MIN="${TEAM_REAPER_PERM_TIMEOUT_MIN:-5}"
# Where the bounded-abstain clock and the page-damping markers live (see the UNKNOWN branch).
readonly STATE_DIR="${TEAM_REAPER_STATE_DIR:-$HOME/.claude/autonomy/team-reaper-state}"
# Ceiling past which an UNKNOWN team stops abstaining. The legitimate reasons for UNKNOWN are
# short-lived (the watchdog has not written its pid file yet) or covered by the positive oracles
# (an in-place /handoff left a stale leadSessionId while a successor drives the team — caught by
# occupancy or the registry). 6h matches the repo's other owned-wait ceiling; a team UNKNOWN and
# UNOCCUPIED for longer is not a team anyone is waiting on.
readonly UNKNOWN_MAX_S="${TEAM_REAPER_UNKNOWN_MAX_S:-21600}"
# Separate ceiling for an UNRESOLVED probe (no lsof). Past it the operator is paged ONCE; it never
# archives at any age, because an unanswered probe is not proof of death.
readonly UNRESOLVED_MAX_S="${TEAM_REAPER_UNRESOLVED_MAX_S:-$UNKNOWN_MAX_S}"

# Helper CLIs for the archive-safety gate: cc-sessions (live-session registry cross-check) and
# cc-notify (operator page for an UNKNOWN-liveness team). Resolve PATH-first so a test PATH-shim wins,
# then fall back to the standard install path; empty ⇒ unavailable, and the caller degrades gracefully
# (a missing registry only forfeits its extra KEEP evidence — it never fails the sweep).
_reaper_bin() { command -v "$1" 2>/dev/null || { [ -x "$HOME/.claude/bin/$1" ] && printf '%s\n' "$HOME/.claude/bin/$1"; }; }
readonly CC_SESSIONS_BIN="${CC_SESSIONS_BIN:-$(_reaper_bin cc-sessions)}"
readonly CC_NOTIFY_BIN="${CC_NOTIFY_BIN:-$(_reaper_bin cc-notify)}"

# ── OFF-BOX ABSTAIN (CLOUD_OBSERVABILITY.md §5.2, liar #3 — THE DESTRUCTIVE ONE) ─────────────────
# Every liveness oracle in this file is local to this box: `kill -0` on a watchdog pid, `lsof -d cwd`
# over local processes, and a cc-sessions registry written by local SessionStart hooks. A team whose
# lead runs in an Anthropic-managed VM answers NO to all three — every time, by construction — and
# this script's honest-looking ladder then walks straight to `archive_team`. It runs on a 600s
# launchd timer, so an unattended cloud fleet would be archived within ten minutes of being fired,
# by our own safety mechanism, with a log line reading "no watchdog record, no process occupying any
# member worktree, no live session — for longer than the ceiling".
#
# That last sentence is what makes this the dangerous one: the three oracles are not broken, they
# are ANSWERING CORRECTLY about a box the session is not on. Adding a fourth local oracle cannot
# help. The only fix is a declaration this box can read, which is what `cc-cloud is-offbox` is.
#
# Checked FIRST, before `lead_liveness` — not folded into the DEAD arm. An off-box lead has no
# watchdog pid file at all, so it enters the UNKNOWN arm, and the UNKNOWN arm archives too (past
# UNKNOWN_MAX_S). Guarding only the word "DEAD" would have left the destructive path open on the
# branch the case actually takes.
#
# Seam: CC_CLOUD_BIN — SET, including set to EMPTY, honored verbatim so a test can disable the
# lookup; `${VAR:-}` cannot tell unset from set-empty. Fails CLOSED toward the existing behaviour:
# no cc-cloud, unreadable state, or an undeclared id all leave every verdict as it was. It can only
# ever PREVENT an archive, never cause one — strictly the conservative direction.
if [[ -n "${CC_CLOUD_BIN+set}" ]]; then
  CC_CLOUD_BIN_R="$CC_CLOUD_BIN"
else
  CC_CLOUD_BIN_R="$(_reaper_bin cc-cloud)"   # separate from `readonly`: SC2155 masks the rc
fi
readonly CC_CLOUD_BIN_R
lead_is_offbox() { # $1=leadSessionId → 0 iff DECLARED off-box and not retired
  [[ -n "${1:-}" ]] || return 1
  [[ -n "$CC_CLOUD_BIN_R" ]] && [[ -x "$CC_CLOUD_BIN_R" ]] || return 1
  "$CC_CLOUD_BIN_R" is-offbox "$1" >/dev/null 2>&1
}

mkdir -p "$ARCHIVE_DIR" "$(dirname "$LOG_FILE")" 2>/dev/null || true

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE" 2>/dev/null || true
}

# Three-state liveness of the recorded lead:
#   0 = ALIVE   (pid file present, pid answers kill -0 — keep existing semantics: ANY live pid ⇒ alive,
#                including a recycled non-claude pid; we do NOT add pid-identity checking here)
#   1 = DEAD    (pid file present, pid fails kill -0 — POSITIVE evidence of death; may proceed to archive)
#   2 = UNKNOWN (no pid file, or an empty one — absence of evidence, NOT evidence of death; surface it)
lead_liveness() {
  local sid="$1"
  local pid_file="$WATCHDOG_DIR/$sid.pid"
  [[ -f "$pid_file" ]] || return 2          # no watchdog record — UNKNOWN (was wrongly "assume dead")
  local pid
  pid=$(cat "$pid_file" 2>/dev/null || echo "")
  [[ -z "$pid" ]] && return 2               # empty pid file — no pid to test ⇒ UNKNOWN, not dead
  kill -0 "$pid" 2>/dev/null && return 0     # a live pid ⇒ alive (existing semantics preserved)
  return 1                                   # pid file present + pid dead ⇒ DEAD (positive evidence)
}

# Best-effort operator page (never fails the sweep). Addresses the operator ROLE so a recycled desk is
# followed automatically; a missing role / unavailable cc-notify is a silent no-op.
cc_notify_page() { # $1=message
  [[ -n "$CC_NOTIFY_BIN" ]] || return 0
  "$CC_NOTIFY_BIN" --role operator "$1" >/dev/null 2>&1 || true
}

# Registry cross-check before archiving a DEAD-lead team: a dead lead pid is not a dead TEAM. An
# in-place /handoff or a crash-respawn mints a successor session that drives the team from a member
# worktree (its cwd sits inside one) or under a member/lead name. Return 0 (KEEP) iff cc-sessions
# reports a live session matching either signal; 1 otherwise. cc-sessions unavailable / unreadable ⇒ 1
# (no extra KEEP evidence — the sweep falls back to the pid-death verdict it already has).
team_has_live_session() { # $1=team_dir
  local cfg="$1/config.json" rows
  [[ -f "$cfg" ]] || return 1
  [[ -n "$CC_SESSIONS_BIN" ]] || { log "registry cross-check skipped ($1): cc-sessions unavailable"; return 1; }
  rows="$("$CC_SESSIONS_BIN" --json 2>/dev/null)" || return 1
  case "$rows" in '['*) ;; *) return 1 ;; esac          # not a JSON array ⇒ ignore, no false KEEP
  # One jq pass: a live session KEEPs the team if its .name is a member/lead name OR its .cwd is inside
  # a member worktree (.worktree or .cwd). --slurpfile tolerates a malformed config (parse error ⇒ empty
  # stream ⇒ jq -e exits non-zero ⇒ no false KEEP). Member names include "team-lead", so the lead is covered.
  printf '%s' "$rows" | jq -e --slurpfile cfg "$cfg" '
    ($cfg[0] // {}) as $c
    | ([ ($c.members // [])[]? | (.worktree, .cwd) | select(type == "string" and . != "") ]) as $wts
    | ([ ($c.members // [])[]? | .name              | select(type == "string" and . != "") ]) as $names
    | any(.[]?;
        ((.name // "") as $n | $n != "" and ($names | index($n) != null))
        or
        ((.cwd  // "") as $d | $d != "" and (any($wts[]; . as $w | $d == $w or ($d | startswith($w + "/")))))
      )
  ' >/dev/null 2>&1
}

# procs_cwd_under <dir> → pids of live processes whose CWD is at or below <dir>, one per line.
#
# THE POSITIVE LIVENESS ORACLE. Everything above it asks whether a RECORD of the lead exists; this
# asks whether anyone is actually WORKING. macOS has no /proc, so a process's cwd is only readable
# through lsof(8) — a SYSTEM binary (/usr/sbin/lsof), present under the bare PATH a launchd sweep
# runs with. `-d cwd -F pn` is the terse form: a `p<pid>` line, then the `n<path>` for that cwd.
#
# NOT keyed on argv. cc-wave-plan fires the launcher with the worktree path in ITS argv and the
# launcher then exits; the surviving worker inherits only the cwd. So `pgrep -f "$wt"` is blind to
# the actual worker while it thinks — measured against a live dispatched session: pgrep → 0,
# processes with cwd in the worktree → 6. That exact blindness reaped a live claim and
# double-dispatched a peer onto occupied work (memory: argv-is-sampling-cwd-is-durable). Occupancy
# is durable; a mention in argv is sampling.
#
# PREFIX, not equality: a worker that cd'd into a subdirectory is still working, and an lsof path
# ARGUMENT matches the cwd EXACTLY, so the prefix match lives in awk instead.
#
# PHYSICAL, not logical: lsof reports a cwd physically resolved (a process in /var/… is reported
# under /private/var/…), so a prefix match against the RAW path alone sees NOTHING whenever any
# component of the worktree root is a symlink — blind while looking like it works. Both forms are
# compared; they are identical when nothing is symlinked, so this only ever ADDS a match.
#
# BOUNDED: lsof can block indefinitely on an unresponsive mount and this runs inside a sweep. A
# timed-out probe yields no pids, which the CALLER must read as UNRESOLVED (a non-verdict), never
# as "nobody is there" — our own timeout must not forge the death evidence.
#
# …and saying that in a comment was not enough to make it true (2026-07-30, backlog 9efae9e3cfc1).
# The caller CANNOT read a timeout as UNRESOLVED unless this function tells it apart from an answer,
# and it did not: every failure path returned rc 0 with empty stdout, identical to "asked, nobody
# there". `team_occupied` pre-checked the BINARY and so caught only the missing-lsof case; a lsof
# that was present and simply did not return inside the cap fell through as UNOCCUPIED, i.e. a real
# verdict, and past UNKNOWN_MAX_S that ARCHIVES a live team. So the rc contract is the mechanism, and
# the comment above was the requirement it was missing (memory: feature-durability-mechanism-not-memory):
#   rc 0  ANSWERED    the probe RAN; the pids it found (possibly NONE) are on stdout. A real verdict.
#   rc 2  UNRESOLVED  no binary, seam disabled, timed out, or no output at all. A NON-VERDICT.
# Empty output is UNRESOLVED rather than "nobody home" because a full-system `lsof -d cwd` always
# reports at least this process's own cwd — a truly empty read means the probe did not complete.
# The identical fold was fixed in bin/cc-backlog's copy of this probe in the same change; there it
# reopened live workers instead of archiving live teams.
#
# Seam: TEAM_REAPER_LSOF_BIN — UNSET ⇒ resolve one. SET, including set to EMPTY ⇒ honored verbatim,
# so `TEAM_REAPER_LSOF_BIN=` genuinely disables the probe. `${VAR:-}` cannot tell unset from
# set-empty, and a seam that cannot turn a thing OFF is not a seam.
procs_cwd_under() {
  local dir="$1" bin out pdir
  [[ -n "$dir" ]] || return 0
  pdir="$(cd "$dir" 2>/dev/null && pwd -P 2>/dev/null)" || pdir=""
  if [[ -n "${TEAM_REAPER_LSOF_BIN+set}" ]]; then
    bin="$TEAM_REAPER_LSOF_BIN"
  else
    bin=/usr/sbin/lsof
    [[ -x "$bin" ]] || bin="$(command -v lsof 2>/dev/null || true)"
  fi
  [[ -n "$bin" ]] && [[ -x "$bin" ]] || return 2   # no probe to run ⇒ UNRESOLVED, not "nobody there"
  if command -v timeout >/dev/null 2>&1; then
    out="$(timeout "${TEAM_REAPER_ORACLE_TIMEOUT_S:-10}" "$bin" -a -d cwd -w -F pn 2>/dev/null || true)"
  else
    out="$("$bin" -a -d cwd -w -F pn 2>/dev/null || true)"
  fi
  [[ -n "$out" ]] || return 2                      # timed out / crashed ⇒ UNRESOLVED (see the header)
  printf '%s\n' "$out" | awk -v d="$dir" -v pd="$pdir" '
    function under(n, base) { return base != "" && (n == base || index(n, base "/") == 1) }
    /^p/ { p = substr($0, 2); next }
    /^n/ { n = substr($0, 2); if (under(n, d) || under(n, pd)) print p }' | sort -u
  # EXPLICIT, not the pipeline's rc: under `set -o pipefail` a hiccup in awk/sort would otherwise
  # surface as rc 1 or 2 and be misread as a liveness verdict. The probe ran; that is what rc 0 means.
  return 0
}

# team_occupied <team_dir> — is anyone actually WORKING in this team's worktrees?
#   0 OCCUPIED   positive evidence of life: a live process's cwd is at/below a member worktree.
#   1 UNOCCUPIED the probe ANSWERED and found nobody. A real verdict.
#   2 UNRESOLVED the probe could not be run at all (no lsof binary, or the seam disabled it). A
#                NON-VERDICT — the absence of an answer, not the answer "dead". Callers must
#                ABSTAIN on this and must never archive on it at any age.
# The three states are the whole point: folding UNRESOLVED into UNOCCUPIED would let a missing
# lsof archive every team on the machine (memory: gate-never-ran-vs-gate-red — one exit code for
# two outcomes forces every caller to lie).
team_occupied() {
  local cfg="$1/config.json" wt n
  [[ -f "$cfg" ]] || return 2
  # Can we probe at all? Resolve exactly as procs_cwd_under does, so the answer matches reality.
  local bin
  if [[ -n "${TEAM_REAPER_LSOF_BIN+set}" ]]; then bin="$TEAM_REAPER_LSOF_BIN"
  else bin=/usr/sbin/lsof; [[ -x "$bin" ]] || bin="$(command -v lsof 2>/dev/null || true)"; fi
  [[ -n "$bin" ]] && [[ -x "$bin" ]] || return 2
  # A probe that ran for SOME worktrees and starved on others has not answered for this team: a
  # worker could be sitting in exactly the one we could not read. Positive evidence anywhere still
  # wins (it is proof, and no starvation can retract it), so this only decides the "found nobody"
  # case — where it is the difference between "nobody is working" and "we did not manage to look".
  local starved=""
  while IFS= read -r wt; do
    [[ -n "$wt" ]] || continue
    [[ -d "$wt" ]] || continue
    # SKIP A SHARED CHECKOUT. Occupancy is only evidence about THIS team when the directory is a
    # dedicated per-team worktree. A main checkout is shared by every session on the machine, so
    # processes sitting in it say nothing about any particular team — counting them is a FALSE
    # ALIVE that would pin a dead team forever, re-creating the very stall this leg removes.
    # Measured 2026-07-26 on the actually-stalled session-85cf3b06: its only member cwd is
    # ~/Development/claude-infrastructure (the shared checkout, and this repo's symlink source),
    # where 45 live processes legitimately sat.
    # The test is self-describing and needs no path list: git makes `.git` a DIRECTORY in a main
    # checkout and a FILE in a linked worktree. So `.git`-is-a-dir ⇒ shared ⇒ no signal here.
    # Limit, stated honestly: this skips the checkout TOPLEVEL, which is the shape members
    # actually carry; a member cwd pointing at a SUBDIRECTORY of a shared checkout would still be
    # probed. A team with no dedicated worktree therefore yields "unoccupied" rather than
    # "unresolved" — occupancy is INAPPLICABLE, not unanswerable, and the registry cross-check and
    # the age ceiling below are then what decide it.
    [[ -d "$wt/.git" ]] && { log "occupancy: skipping shared checkout $wt (main checkout — not a per-team worktree)"; continue; }
    local out prc n=0
    out="$(procs_cwd_under "$wt")"; prc=$?
    [[ -z "$out" ]] || n="$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
    if [[ "$n" -gt 0 ]] 2>/dev/null; then
      log "occupancy: $n live process(es) with cwd under $wt — team is ALIVE"
      return 0
    fi
    [[ "$prc" -ne 2 ]] || starved="$wt"
  done < <(jq -r '[ (.members[]? | (.worktree, .cwd)) ] | map(select(type=="string" and . != "")) | unique[]' \
             "$cfg" 2>/dev/null || true)
  if [[ -n "$starved" ]]; then
    log "occupancy: the probe never answered for $starved — UNRESOLVED, not unoccupied"
    return 2
  fi
  return 1
}

# unknown_since <team> → epoch when this team was FIRST seen UNKNOWN (stamping it on first sight).
# The abstain has to be bounded, and bounding it needs a clock that survives across sweeps.
unknown_since() {
  local team="$1"
  local f="$STATE_DIR/$team.unknown-since" now v
  now=$(date +%s)
  mkdir -p "$STATE_DIR" 2>/dev/null || true
  if [[ -f "$f" ]]; then
    v=$(cat "$f" 2>/dev/null || echo "")
    case "$v" in ''|*[!0-9]*) v="$now"; echo "$v" > "$f" 2>/dev/null || true ;; esac
    printf '%s' "$v"
  else
    echo "$now" > "$f" 2>/dev/null || true
    printf '%s' "$now"
  fi
}

# Forget a team's UNKNOWN bookkeeping (it resolved, went live, or was archived).
unknown_clear() { rm -f "$STATE_DIR/$1.unknown-since" "$STATE_DIR/$1.paged" 2>/dev/null || true; }

# Page the operator AT MOST ONCE per team per unknown-episode. The un-damped page is what turned a
# correct abstention into an infinite manual step: 77 identical "unknown-liveness session-85cf3b06"
# pages for ONE team, plus 11 for another, every sweep, forever. A repeated page is not more
# information — it is the same information, and it trains the operator to ignore the channel.
page_once() { # $1=team  $2=message
  local m="$STATE_DIR/$1.paged"
  mkdir -p "$STATE_DIR" 2>/dev/null || true
  [[ -f "$m" ]] && return 0
  cc_notify_page "$2"
  : > "$m" 2>/dev/null || true
}

archive_team() {
  local team_dir="$1"
  local team_name
  team_name=$(basename "$team_dir")
  local ts
  ts=$(date +%s)
  local dest="$ARCHIVE_DIR/${team_name}-${ts}"

  if mv "$team_dir" "$dest" 2>/dev/null; then
    log "archived orphan team: $team_name → $dest"
    unknown_clear "$team_name"   # the episode is over; never leave a stale clock or page-damp behind

    # Clean up associated watchdog files
    local lead_sid
    lead_sid=$(jq -r '.leadSessionId // empty' "$dest/config.json" 2>/dev/null)
    if [[ -n "$lead_sid" ]]; then
      rm -f "$WATCHDOG_DIR/$lead_sid.pid" "$WATCHDOG_DIR/$lead_sid.id" "$WATCHDOG_DIR/cp-$lead_sid.count"
    fi
  else
    log "FAIL: could not archive $team_dir"
  fi
}

scan_stale_permissions() {
  local team_dir="$1"
  local team_name
  team_name=$(basename "$team_dir")
  local cutoff_epoch
  cutoff_epoch=$(( $(date +%s) - PERM_TIMEOUT_MIN * 60 ))

  for inbox in "$team_dir/inboxes"/*.json; do
    [[ -f "$inbox" ]] || continue
    local member
    member=$(basename "$inbox" .json)
    [[ "$member" == "team-lead" ]] && continue

    # Find unread permission_requests older than cutoff
    local stale
    stale=$(jq -c --arg cutoff "$cutoff_epoch" '
      [.[] | select(.read == false)
           | select((.text | fromjson?).type == "permission_request")
           | select((.timestamp | sub("\\.[0-9]+Z"; "Z") | fromdateiso8601) < ($cutoff | tonumber))]
    ' "$inbox" 2>/dev/null || echo '[]')

    local count
    count=$(echo "$stale" | jq 'length' 2>/dev/null || echo 0)
    [[ "$count" == "0" ]] && continue

    log "auto-deny $count stale permission_request(s) for $team_name/$member"

    # Append one deny envelope per stale request — UNDER A MUTEX. The crash-watchdog
    # (lead-crash-watchdog.sh) appends shutdown/deny envelopes to this SAME inbox; two read-modify-write
    # cycles with last-mv-wins would silently drop one side's envelope. An inline mkdir lock (portable —
    # macOS has no flock) whose dir name is SHARED VERBATIM with the watchdog ("$inbox.lock.d") makes the
    # two exclude each other. Acquire ≤2s (0.1s steps), self-break a stale lock (holder died) >10s old,
    # and on give-up proceed lock-free — dup-biased: a duplicate deny is harmless, a hung reaper is not.
    local lockd="$inbox.lock.d" waited=0 lmt lnow lage
    while ! mkdir "$lockd" 2>/dev/null; do
      lmt=$(stat -f %m "$lockd" 2>/dev/null || stat -c %Y "$lockd" 2>/dev/null || echo 0)
      lnow=$(date +%s 2>/dev/null || echo 0)
      lage=$(( lnow - lmt ))
      if [[ "$lage" -ge 10 ]]; then rm -rf "$lockd" 2>/dev/null; continue; fi   # stale → holder died, break it
      [[ "$waited" -ge 2000 ]] && break                                          # gave up → proceed lock-free
      sleep 0.1 2>/dev/null || sleep 1; waited=$(( waited + 100 ))
    done
    local tmp
    tmp=$(mktemp)
    # shellcheck disable=SC2015  # deliberate A&&B||C: tmp is rm'd on either jq-or-mv failure; a successful mv cannot reach the rm
    jq --argjson stale "$stale" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)" '
      . + ($stale | map({
        from: "reaper",
        text: ("{\"type\":\"permission_response\",\"request_id\":\"" + ((.text | fromjson).request_id // "unknown") + "\",\"decision\":\"deny\",\"reason\":\"lead unresponsive >5min — try alternative or report blocker\"}"),
        summary: "stale permission request auto-denied",
        timestamp: $ts,
        read: false
      }))
    ' "$inbox" > "$tmp" && mv "$tmp" "$inbox" || rm -f "$tmp"
    rmdir "$lockd" 2>/dev/null || true
  done
}

main() {
  log "reaper sweep — start"

  local live_count=0
  local archived_count=0
  local unknown_count=0

  for team_dir in "$TEAMS_DIR"/*/; do
    team_dir=${team_dir%/}
    [[ -d "$team_dir" ]] || continue
    local team_name
    team_name=$(basename "$team_dir")
    [[ "$team_name" == "_archive" ]] && continue
    [[ -f "$team_dir/config.json" ]] || continue

    local lead_sid
    lead_sid=$(jq -r '.leadSessionId // empty' "$team_dir/config.json" 2>/dev/null)
    if [[ -z "$lead_sid" ]]; then
      log "skip $team_name: no leadSessionId"
      continue
    fi

    # OFF-BOX: no local oracle in this file can speak to this team. KEEP, log, move on — and do NOT
    # count it as `live`, because we did not observe life; we observed that we cannot look. Its
    # liveness lives in `cc-cloud show <id>` (observables O1-O5), which is a different instrument.
    if lead_is_offbox "$lead_sid"; then
      log "keep $team_name: lead $lead_sid is DECLARED OFF-BOX — no local oracle applies (cc-cloud show $lead_sid)"
      unknown_clear "$team_name"     # end any UNKNOWN episode this team accrued before it was declared
      unknown_count=$((unknown_count + 1))
      continue
    fi

    local liveness
    lead_liveness "$lead_sid"; liveness=$?
    if [[ "$liveness" -eq 0 ]]; then
      scan_stale_permissions "$team_dir"
      unknown_clear "$team_name"   # a live pid file ends any prior UNKNOWN episode + its page damp
      live_count=$((live_count + 1))
    elif [[ "$liveness" -eq 2 ]]; then
      # UNKNOWN — no/empty watchdog pid file. Absence of a RECORD is not evidence of death, so this
      # must never archive on the pid file alone. But the previous behaviour — log + page, every
      # sweep, forever — turned a correct abstention into a PERMANENT MANUAL STEP: measured 77
      # identical pages for session-85cf3b06 and 11 for session-69dfb701, each re-emitting
      # "if the team is truly dead, clean up <dir>". An abstention that never resolves is not a
      # safety property, it is an unbounded operator debt.
      #
      # So: ask a POSITIVE oracle (is anyone actually working?), damp the page to once, and BOUND
      # the abstain so it terminates.
      local occ since age
      team_occupied "$team_dir"; occ=$?
      since=$(unknown_since "$team_name"); age=$(( $(date +%s) - since ))

      if [[ "$occ" -eq 0 ]]; then
        # POSITIVE evidence of life — someone is working in a member worktree right now. This is
        # the common case behind the 77 pages, and it needs no operator at all.
        log "keep $team_name: unknown pid file, but worktree OCCUPIED (live process cwd) — alive"
        unknown_clear "$team_name"
        live_count=$((live_count + 1))
      elif [[ "$occ" -eq 2 ]]; then
        # NON-VERDICT: the probe could not run — no lsof, the seam disabled it, or it did not return
        # inside its cap. Never archive on this at any age — our own inability to look is not
        # evidence of death, and a TIMEOUT is our own bound firing, not the machine answering. Bound
        # it so it still terminates: past the ceiling the operator is paged ONCE and left to decide.
        if [[ "$age" -ge "$UNRESOLVED_MAX_S" ]]; then
          log "unknown-liveness $team_name: liveness probe UNRESOLVED for ${age}s (no lsof, or it never answered) — paging once, NOT archiving"
          page_once "$team_name" "team-orphan-reaper: '$team_name' — cannot probe liveness (no lsof, or the probe never answered) after ${age}s; NOT archiving on a non-verdict. Decide manually: $TEAMS_DIR/$team_name"
        else
          log "unknown-liveness $team_name: probe UNRESOLVED, abstaining (${age}s of ${UNRESOLVED_MAX_S}s)"
        fi
        unknown_count=$((unknown_count + 1))
      elif team_has_live_session "$team_dir"; then
        # The probe answered "unoccupied", but the registry knows a successor driving the team by
        # member/lead name. Still alive.
        log "keep $team_name: unknown pid file, unoccupied worktrees, but a live session matches a member/lead name"
        unknown_clear "$team_name"
        live_count=$((live_count + 1))
      elif [[ "$age" -ge "$UNKNOWN_MAX_S" ]]; then
        # RESOLVED. Every oracle has answered and none of them found life: no watchdog record, no
        # process occupying any member worktree, no live session in the registry — for longer than
        # the ceiling. Archiving is reversible (mv into _archive/), which is what makes resolving
        # here the right side to err on: the alternative is paging forever.
        log "archive $team_name: UNKNOWN + unoccupied + no live session for ${age}s (≥${UNKNOWN_MAX_S}s) — resolving"
        archive_team "$team_dir"
        unknown_clear "$team_name"
        archived_count=$((archived_count + 1))
      else
        # Within the grace window — the watchdog may simply not have written its pid file yet.
        log "unknown-liveness $team_name: unoccupied, abstaining (${age}s of ${UNKNOWN_MAX_S}s)"
        unknown_count=$((unknown_count + 1))
      fi
    else
      # DEAD by positive evidence (pid file present, pid fails kill -0). Cross-check the live-session
      # registry first: a successor may drive the team from a member worktree/name (KEEP), else archive.
      # The occupancy oracle is asked here too — a dead LEAD pid is not a dead TEAM, and an assignee
      # still working in its worktree is the most direct evidence of that. It can only ever PREVENT
      # an archive, never cause one, so it is strictly the conservative direction.
      if team_occupied "$team_dir"; then
        log "keep $team_name: lead pid dead but a member worktree is OCCUPIED (live process cwd) — assignees still working"
        live_count=$((live_count + 1))
      elif team_has_live_session "$team_dir"; then
        log "keep $team_name: lead pid dead but a live session matches a member worktree/name (successor-driven)"
        live_count=$((live_count + 1))
      else
        archive_team "$team_dir"
        archived_count=$((archived_count + 1))
      fi
    fi
  done

  log "reaper sweep — done: $live_count live, $archived_count archived, $unknown_count unknown"
}

main "$@"
