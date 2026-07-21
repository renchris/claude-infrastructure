#!/bin/bash
# boot-resume.sh — P0-10 AGENT HALF: the post-login auto-resume chain (T-P16-2) + boot-delta
# pager (T-P16-7). A RunAtLoad LaunchAgent entrypoint that runs once at GUI login and closes the
# reboot-recovery gap G-P16-1/-4: after a reboot nothing relaunches Claude Code, and the lead
# supervisor's /tmp telemetry is wiped — so previously-open desk sessions sit dead until a human acts.
#
# Each run (idempotent PER BOOT — exactly one page per reboot):
#   1. DETECT: kern.boottime + the DURABLE cross-account session registry (~/.claude/cc-registry,
#      survives reboot — NOT /tmp). A "session open at last boot" = a registry ghost whose startedAt
#      (ms) is BEFORE boottime: its process died in the reboot. Post-boot live sessions (startedAt >
#      boottime) are excluded — a live process cannot predate its own boot.
#   2. DECIDE: the boot-epoch marker dedups multiple logins within one boot; the POSTURE mode is the
#      OPERATOR's reboot-posture call (this is "reboot posture is operator; resume code is agent"):
#        page   (DEFAULT) — page the delta once, do NOT resume. Ruling #1 (supervisor PAGES, never
#                 auto-recovers) is the safe default → this is the DoD's "or pages once if deferred".
#        resume — invoke the resume launcher per ghost (config-dir basename → reso-resume-one account
#                 alias, mapped) + start keepalive once, then page a summary. Operator opts in.
#   3. ACT + LOG: always emit ONE {fired|abstained|failed} IDL record (abstention-logged, B-3). A
#      delta with no reachable desk role FAILS LOUD and does NOT mark the boot processed, so a re-run
#      retries (a17 S-7: never let a wake drain to nobody).
#
# C10: this is machinery the OPERATOR loads via launchd (launchd/com.claude.boot-resume.plist,
# RunAtLoad, shipped UNLOADED). The agent never loads launchd. Activation + rollback + the posture
# switch: docs/activation/boot-resume-activate-snippet.md.
#
# Env (config + tests): CC_REGISTRY_DIR · CC_ROLES_DIR · CC_IDL · CC_BOOT_RESUME_STATE_DIR ·
#   CC_BOOT_RESUME_MODE (page|resume; else <state>/mode; else page) · CC_BOOTTIME_OVERRIDE (sec) ·
#   CC_NOTIFY_BIN · CC_RESUME_LAUNCH_BIN · CC_KEEPALIVE_BIN · CC_LAUNCHCTL_BIN · CC_KEEPALIVE_INTERVAL.
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

# Resolve a helper binary: env override → beside-script → CFG bin → ~/.claude/bin → PATH. Echo or "".
resolve_bin() { # <env-value> <basename> [<beside-name>]
  local override="$1" name="$2" beside="${3:-$2}" cand
  if [ -n "$override" ]; then [ -x "$override" ] && printf '%s' "$override"; return 0; fi
  for cand in "$(dirname "$0")/$beside" "$(dirname "$0")/../bin/$name" \
              "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/bin/$name" "$HOME/.claude/bin/$name"; do
    [ -x "$cand" ] && { printf '%s' "$cand"; return 0; }
  done
  command -v "$name" >/dev/null 2>&1 && printf '%s' "$(command -v "$name")"
  return 0
}
NOTIFY="$(resolve_bin "${CC_NOTIFY_BIN:-}" cc-notify)"
LAUNCH="$(resolve_bin "${CC_RESUME_LAUNCH_BIN:-}" boot-resume-launch.sh boot-resume-launch.sh)"
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
KEEPALIVE="$(resolve_bin "${CC_KEEPALIVE_BIN:-}" reso-keepalive)"
[ -z "$KEEPALIVE" ] && [ -x "$HOME/.reso/bin/reso-keepalive" ] && KEEPALIVE="$HOME/.reso/bin/reso-keepalive"
LAUNCHCTL="${CC_LAUNCHCTL_BIN:-launchctl}"

SYSCTL="${CC_SYSCTL_BIN:-sysctl}"
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
  path="$(find "$cfg/projects" -name "$2.jsonl" -print -quit 2>/dev/null | head -1)"
  [ -n "$path" ] && stat -f %m "$path" 2>/dev/null
}

# ── config-dir basename (registry `account` field) → reso-resume-one account alias. ──
# .claude and .claude-next are the SAME account (mirror) → next. Unknown → echo raw (reso rejects loud).
map_account() { # <config-basename>
  case "$1" in
    claude|claude-next)  printf 'next'  ;;
    claude-secondary)    printf 'next2' ;;
    claude-tertiary)     printf 'next3' ;;
    claude-quaternary)   printf 'next4' ;;
    *)                   printf '%s' "$1" ;;
  esac
}

# ── posture mode: env → <state>/mode → default page (ruling #1 safe default). ──
resolve_mode() {
  local m="${CC_BOOT_RESUME_MODE:-}"
  [ -z "$m" ] && [ -f "$STATE_DIR/mode" ] && m="$(tr -d '[:space:]' < "$STATE_DIR/mode" 2>/dev/null)"
  case "$m" in resume) printf 'resume' ;; *) printf 'page' ;; esac
}

BOOT="$(boottime)"
MODE="$(resolve_mode)"
MARKER="$STATE_DIR/last-boot-epoch"

case "${1:-}" in --print-boottime) printf '%s\n' "$BOOT"; exit 0 ;; esac

log_idl() { # <disposition> <extra-json>
  mkdir -p "$(dirname "$IDL")" 2>/dev/null || true
  printf '{"ts":"%s","tool":"boot-resume","disposition":"%s","boot":"%s","mode":"%s"%s}\n' \
    "$(now_iso)" "$1" "$BOOT" "$MODE" "${2:-}" >> "$IDL" 2>/dev/null || true
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

# ── DETECT: a session "open at last boot" = a durable registry entry whose process predates this
#    boot (startedAt/1000 < boottime → killed by the reboot) AND whose transcript was written within
#    RECENCY_WINDOW before the boot (the resume-sessions "written just before that boot" rule, which
#    excludes long-dead crashed-and-never-deregistered cruft). Rows: "<config-acct>\t<cwd>\t<sid>\t<name>". ──
GHOSTS=""
n_open=0
if [ -d "$REGISTRY_DIR" ]; then
  for f in "$REGISTRY_DIR"/*.json; do
    [ -e "$f" ] || continue
    row="$(jq -r '[(.startedAt // 0), (.account // ""), (.cwd // ""), (.session_id // ""), (.name // "")] | @tsv' "$f" 2>/dev/null)" || continue
    [ -n "$row" ] || continue
    IFS=$'\t' read -r started_ms g_acct g_cwd g_sid g_name <<GHOST_ROW
$row
GHOST_ROW
    case "$started_ms" in ''|*[!0-9]*) continue ;; esac
    [ "$((started_ms / 1000))" -lt "$BOOT" ] || continue     # live/post-boot session → not a ghost
    [ -n "$g_sid" ] || continue
    mt="$(transcript_mtime "$g_acct" "$g_sid" "$g_cwd")"     # stale/absent transcript → cruft, skip
    { [ -n "$mt" ] && [ "$mt" -gt "$((BOOT - RECENCY_WINDOW))" ]; } || continue
    GHOSTS="${GHOSTS}${g_acct}	${g_cwd}	${g_sid}	${g_name}
"
    n_open=$((n_open + 1))
  done
fi

mark_processed() { mkdir -p "$STATE_DIR" 2>/dev/null || true; printf '%s\n' "$BOOT" > "$MARKER" 2>/dev/null || true; }

# ── reboot happened but nothing was open → nothing lost, no page. Advance the marker. ──
if [ "$n_open" -eq 0 ]; then
  mark_processed
  log_idl abstained ',"reason":"no-open-sessions","n_open":0,"resumed":0'
  exit 0
fi

# ── desk-jobs snapshot (best-effort, informational): loaded com.claude agents + how many up. ──
dj_total=0; dj_up=0
if command -v "${LAUNCHCTL%% *}" >/dev/null 2>&1 || [ -x "$LAUNCHCTL" ]; then
  while IFS=$'\t' read -r pid _status label; do
    case "$label" in com.claude.*) dj_total=$((dj_total + 1)); case "$pid" in ''|-|*[!0-9]*) : ;; *) dj_up=$((dj_up + 1)) ;; esac ;; esac
  done < <("$LAUNCHCTL" list 2>/dev/null || true)
fi

# ── ACT: resume (posture=resume) per ghost, else page-only (posture=page). ──
resumed=0
resume_fail=0
n_fire=0        # ghosts SELECTED to fire (post-consolidation) — distinct from n_open (ghosts found)
if [ "$MODE" = "resume" ]; then
  if [ -z "$LAUNCH" ] || [ ! -x "$LAUNCH" ]; then
    log_idl failed ",\"n_open\":$n_open,\"resumed\":0,\"delivered\":false,\"reason\":\"no-resume-launcher\""
    echo "boot-resume: mode=resume but no executable resume launcher — not marking boot; will retry" >&2
    exit 3
  fi
  # ── CONSOLIDATE before firing. A reboot can leave many ghosts sharing ONE worktree; resuming
  #    each is the 2026-07-21 sprawl incident. lr-select groups by worktree, picks the single
  #    session per group that holds the most real state, and lists the rest. Missing selector =
  #    FAIL LOUD and resume NOTHING (same discipline as a missing launcher above) — never fall
  #    back to firing every ghost, which is the exact bug. ──
  if [ -z "$SELECT" ] || [ ! -x "$SELECT" ]; then
    log_idl failed ",\"n_open\":$n_open,\"resumed\":0,\"delivered\":false,\"reason\":\"no-resume-selector\""
    echo "boot-resume: mode=resume but no executable lr-select — refusing to resume unconsolidated" >&2
    exit 3
  fi
  SEL_ARGS=""
  while IFS=$'\t' read -r acct cwd sid _name; do
    [ -n "$sid" ] || continue
    SEL_ARGS="$SEL_ARGS --candidate $(map_account "$acct"):$sid:$cwd"
  done <<EOF
$GHOSTS
EOF
  mkdir -p "$STATE_DIR" 2>/dev/null || true
  # SEL_ARGS is a built flag list and MUST word-split into separate --candidate args.
  # shellcheck disable=SC2086
  WINNERS="$("$SELECT" $SEL_ARGS --max-per-worktree "$MAX_PER_WT" --max-total "$MAX_TOTAL" \
    --allow-missing-cwd --json "$STATE_DIR/last-selection.json" 2>"$STATE_DIR/last-triage.txt")"
  n_fire=0
  [ -n "$WINNERS" ] && n_fire="$(printf '%s\n' "$WINNERS" | grep -c . || true)"

  # Resume each WINNER through the (TTY-coupled) launcher seam. Order is irrelevant; each is independent.
  while IFS=$'\t' read -r alias sid cwd _br; do
    [ -n "$sid" ] || continue
    branch=""
    [ -n "$cwd" ] && [ -d "$cwd" ] && branch="$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
    if "$LAUNCH" "$alias" "$cwd" "$sid" "$branch" >/dev/null 2>&1; then
      resumed=$((resumed + 1))
    else
      resume_fail=$((resume_fail + 1))
    fi
  done <<EOF
$WINNERS
EOF
  # start the keepalive watcher ONCE so the resumed panes keep working (their /goal Stop-hook is gone
  # after a resume-from-summary /compact). Best-effort; a stub in tests just records the call.
  if [ -n "$KEEPALIVE" ] && [ -x "$KEEPALIVE" ]; then
    nohup "$KEEPALIVE" "$KEEPALIVE_INTERVAL" >>"$HOME/.reso/keepalive.out" 2>&1 &
    disown 2>/dev/null || true
  fi
fi

# ── build the boot-delta page (T-P16-7): what was open, jobs status, and what to do. ──
boot_h="$(date -u -r "$BOOT" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || printf '%s' "$BOOT")"
listing=""
shown=0
while IFS=$'\t' read -r acct cwd sid name; do
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

if [ "$MODE" = "resume" ]; then
  msg="🔄 boot-delta: rebooted ${boot_h} · resumed ${resumed}/${n_fire} desk session(s), keepalive started."
  [ "$n_open" -gt "$n_fire" ] && msg="${msg}
  consolidated: ${n_open} ghost(s) → ${n_fire} fired (max ${MAX_PER_WT}/worktree, ${MAX_TOTAL} total). The rest are LISTED, not lost — ${STATE_DIR}/last-triage.txt"
  [ "$resume_fail" -gt 0 ] && msg="${msg} ⚠ ${resume_fail} failed to launch — check /resume-sessions."
  msg="${msg}
${listing}desk-jobs: ${dj_up}/${dj_total} com.claude agent(s) up."
else
  msg="🔄 boot-delta: rebooted ${boot_h} · ${n_open} desk session(s) were open at last boot (NOT auto-resumed, posture=page):
${listing}desk-jobs: ${dj_up}/${dj_total} com.claude agent(s) up.
→ resume: /resume-sessions   ·   enable auto-resume: echo resume > ${STATE_DIR}/mode"
fi

# ── deliver to the desk ROLE (resolved at send-time). No role ⇒ FAIL LOUD, do NOT mark processed. ──
DESK_TARGET=""
[ -f "$ROLES_DIR/desk" ] && DESK_TARGET="$(head -1 "$ROLES_DIR/desk" 2>/dev/null | tr -d '[:space:]')"

if [ -n "$DESK_TARGET" ] && [ -n "$NOTIFY" ]; then
  "$NOTIFY" "$DESK_TARGET" "$msg" >/dev/null 2>&1 || true   # cc-notify's mailbox fallback ⇒ durable at exit 0
  mark_processed
  log_idl fired ",\"n_open\":$n_open,\"resumed\":$resumed,\"resume_failed\":$resume_fail,\"desk_jobs_up\":$dj_up,\"desk_jobs_total\":$dj_total,\"notified\":\"$DESK_TARGET\",\"delivered\":true"
  exit 0
else
  # a wake with nobody to wake: keep the delta LIVE (do NOT mark) so a re-run re-attempts it.
  log_idl failed ",\"n_open\":$n_open,\"resumed\":$resumed,\"delivered\":false,\"reason\":\"no-desk-role\""
  echo "boot-resume: ${n_open} session(s) open at last boot but no desk role at $ROLES_DIR/desk — undelivered, will retry" >&2
  exit 4
fi
