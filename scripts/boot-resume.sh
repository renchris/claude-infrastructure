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
LAUNCH="$(resolve_bin "${CC_RESUME_LAUNCH_BIN:-}" boot-resume-launch.sh boot-resume-launch.sh)"

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

# ── DETECT: a session "open at last boot" = a durable registry entry whose process predates this
#    boot (startedAt/1000 < boottime → killed by the reboot) AND whose transcript was written within
#    RECENCY_WINDOW before the boot (the resume-sessions "written just before that boot" rule, which
#    excludes long-dead crashed-and-never-deregistered cruft). Rows: "<config-acct>\t<cwd>\t<sid>\t<name>". ──
GHOSTS=""
n_open=0
if [ -d "$REGISTRY_DIR" ]; then
  for f in "$REGISTRY_DIR"/*.json; do
    [ -e "$f" ] || continue
    row="$(jq -r --arg pad "$TSV_PAD" '
             def cell: (if . == null then "" else . end) | tostring
                       | gsub("[\\t\\r\\n]"; " ") | if . == "" then $pad else . end;
             [((.startedAt // 0) | cell), ((.account // "") | cell), ((.cwd // "") | cell),
              ((.session_id // "") | cell), ((.name // "") | cell)] | @tsv' "$f" 2>/dev/null)" || continue
    [ -n "$row" ] || continue
    IFS=$'\t' read -r started_ms g_acct g_cwd g_sid g_name <<GHOST_ROW
$row
GHOST_ROW
    started_ms="$(unpad "$started_ms")"; g_acct="$(unpad "$g_acct")"; g_cwd="$(unpad "$g_cwd")"
    g_sid="$(unpad "$g_sid")";           g_name="$(unpad "$g_name")"
    case "$started_ms" in ''|*[!0-9]*) continue ;; esac
    [ "$((started_ms / 1000))" -lt "$BOOT" ] || continue     # live/post-boot session → not a ghost
    [ -n "$g_sid" ] || continue
    mt="$(transcript_mtime "$g_acct" "$g_sid" "$g_cwd")"     # stale/absent transcript → cruft, skip
    { [ -n "$mt" ] && [ "$mt" -gt "$((BOOT - RECENCY_WINDOW))" ]; } || continue
    # GHOSTS is itself re-read with `IFS=$'\t' read` twice below, so it stores the PADDED cells.
    GHOSTS="${GHOSTS}$(pad "$g_acct")	$(pad "$g_cwd")	$(pad "$g_sid")	$(pad "$g_name")
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
resume_shed=0   # ghosts SELECTED but REFUSED by the capacity term — distinct from resume_fail (launcher error)
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
  # An ARRAY, not a word-split string: a worktree path containing a space would otherwise break
  # into two argv entries and silently skip that session. bash 3.2 supports indexed arrays.
  SEL_ARGS=()
  while IFS=$'\t' read -r acct cwd sid _name; do
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
  mkdir -p "$STATE_DIR" 2>/dev/null || true
  WINNERS="$("$SELECT" "${SEL_ARGS[@]}" --max-per-worktree "$MAX_PER_WT" --max-total "$MAX_TOTAL" \
    --allow-missing-cwd --json "$STATE_DIR/last-selection.json" 2>"$STATE_DIR/last-triage.txt")"
  n_fire=0
  [ -n "$WINNERS" ] && n_fire="$(printf '%s\n' "$WINNERS" | grep -c . || true)"

  # Resume each WINNER through the (TTY-coupled) launcher seam. Order is irrelevant; each is independent.
  # lr-select pads its winner cells for the same field-collapse reason (its `branch` is routinely "",
  # and a winner with no cwd would otherwise slide the BRANCH NAME into $cwd and launch there).
  while IFS=$'\t' read -r alias sid cwd _br; do
    alias="$(unpad "$alias")"; sid="$(unpad "$sid")"; cwd="$(unpad "$cwd")"
    [ -n "$sid" ] || continue
    branch=""
    [ -n "$cwd" ] && [ -d "$cwd" ] && branch="$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
    # The capacity term lives in the LAUNCHER (the seam that actually opens the window and runs
    # reso-resume-one), not here — see its header. Evaluated per ghost, so the batch SHEDS its tail
    # instead of being all-or-nothing: what fits is resumed, the rest is deferred.
    #
    # rc 9 is the launcher's capacity refusal and is NOT a failure. Keeping the two apart is the
    # whole point: `resume_fail` means the launcher broke and needs fixing, `resume_shed` means the
    # box was full and the session is waiting — same count, opposite operator action.
    "$LAUNCH" "$alias" "$cwd" "$sid" "$branch" >/dev/null 2>&1
    case "$?" in
      0) resumed=$((resumed + 1)) ;;
      9) resume_shed=$((resume_shed + 1)) ;;
      *) resume_fail=$((resume_fail + 1)) ;;
    esac
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

if [ "$MODE" = "resume" ]; then
  msg="🔄 boot-delta: rebooted ${boot_h} · resumed ${resumed}/${n_fire} desk session(s), keepalive started."
  [ "$n_open" -gt "$n_fire" ] && msg="${msg}
  consolidated: ${n_open} ghost(s) → ${n_fire} fired (max ${MAX_PER_WT}/worktree, ${MAX_TOTAL} total). The rest are LISTED, not lost — ${STATE_DIR}/last-triage.txt"
  [ "$resume_fail" -gt 0 ] && msg="${msg} ⚠ ${resume_fail} failed to launch — check /resume-sessions."
  # A shed ghost is deferred, not lost, and it must SAY so: a boot-delta reading "resumed 1/4" with
  # no other line is indistinguishable from three launcher failures (§12.4's whole concern is that
  # the boot storm silently eats the recovery).
  [ "$resume_shed" -gt 0 ] && msg="${msg} ⏸ ${resume_shed} shed by the capacity gate (box saturated at boot) — re-run /resume-sessions once it settles."
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
  log_idl fired ",\"n_open\":$n_open,\"resumed\":$resumed,\"resume_failed\":$resume_fail,\"resume_shed\":$resume_shed,\"desk_jobs_up\":$dj_up,\"desk_jobs_total\":$dj_total,\"notified\":\"$DESK_TARGET\",\"delivered\":true"
  exit 0
else
  # a wake with nobody to wake: keep the delta LIVE (do NOT mark) so a re-run re-attempts it.
  log_idl failed ",\"n_open\":$n_open,\"resumed\":$resumed,\"delivered\":false,\"reason\":\"no-desk-role\""
  echo "boot-resume: ${n_open} session(s) open at last boot but no desk role at $ROLES_DIR/desk — undelivered, will retry" >&2
  exit 4
fi
