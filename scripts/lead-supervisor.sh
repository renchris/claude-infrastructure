#!/bin/bash
# lead-supervisor.sh — out-of-session (bash) watchdog for multi-day UNWATCHED autonomy runs.
#
# ── RULING #1 (operator, 2026-07-14): it PAGES, never auto-recovers. ──
# It DETECTS + CHECKPOINT-preserves (pure insurance) + PAGES. The operator, or a delegated *live*
# session, performs any respawn/close. It is bash and cannot call in-session tools, so it PHYSICALLY
# CANNOT improvise a close on a live pane — and it must not try. The only auto-*acts* are the safe,
# effect-verified ones (checkpoint-preserve of a confirmed-DEAD lead's worktree); every *recovery* is paged.
#
# ── WHAT IT STRUCTURALLY CANNOT SEE (blind-check pre-mortem, audit §3i / blueprint §3.3) ──
# S-3  It cannot see IN-SESSION state AT ALL — MODAL dialogs, the composer, mid-turn reasoning are
#      invisible to an out-of-session bash sweep. This is STRUCTURAL blindness, not a policy gap: it
#      cannot be fixed by a better rule. So a suspected MODAL (a live pane emitting nothing, no work-
#      products) is PAGED, never actioned — the supervisor declares the blindness instead of papering it.
# S-3b The page path encodes deadline → RE-OBSERVATION, NEVER action on silence. reply-compliance is
#      NOT a liveness signal (a busy lead ignores pages). At a page deadline the supervisor does a fresh
#      effects-dark RE-READ; disposition (escalate) gates on THAT, never on the silence. Proven load-
#      bearing by the first live stall-page cycle (§3h): a lead ran dark 69-75m, the deadline expired with
#      no reply, and the mandatory re-read found it ALIVE + productive. Silence-reap would have killed it.
# S-4  Every sweep emits a heartbeat/outcome record to the IDL — a sweep that finds nothing records THAT
#      IT LOOKED. "Who watches the watcher": the watcher's heartbeat is an outcome record; its ABSENCE
#      is the alarm. A silently-crashed daemon must not be indistinguishable from a quiet system.
# B-1  It independently covers a session PAST-THRESHOLD ∧ NOT-STOPPING — the exact case the boundary hook
#      is blind to (the hook fires on Stop; a session hung/working-past-boundary never Stops).
#
# Modes:  --once  one sweep then exit (cron/test) · --daemon  loop (default) · --selftest  prove the logic.
# Env seams: CC_TELEMETRY_DIR · CC_IDL · CC_SUPERVISOR_LOG · CC_PAGE_TO · CC_SUP_T · CC_SUP_STALL_S ·
#            CC_SUP_PAGE_DEADLINE_S · CC_SUP_TRUNK · CC_SUP_GC_S · CC_SUP_OWNER_PAT · CC_PAGE_TO_FILE ·
#            CC_REGISTRY_DIR · SUPERVISOR_SWEEP_MAX_S · SUPERVISOR_SWEEP · CC_SUP_TIMEOUT_BIN ·
#            CC_SUP_GIT_TIMEOUT_S · CC_SUP_FIND_TIMEOUT_S · CC_SUP_CKPT_TIMEOUT_S · CC_SUP_NOTIFY_TIMEOUT_S ·
#            CC_SUP_PANE_DELTA_TOL · CC_SUP_SELFCHECK_MIN_PERSIST · CC_SUP_OS_CHANNEL
set -uo pipefail

# ── BOUNDED EXTERNALS: one hung fork must never end all supervision (audit 2026-07-22 root cause 4, S1) ──
# This daemon had ZERO timeout guards. Every sweep forks git (work_landed ×5, reobserve_effects), a
# filesystem walk (reobserve_effects), teammate-checkpoint.sh, and cc-notify — and the loop is STRICTLY
# SEQUENTIAL, so ONE fork that never returns stops every subsequent sweep forever. The failure is SILENT
# by construction: the pager is the thing that hung, so nothing is left to report it (the observed
# last-exit −9 with 0-byte logs). An in-code comment already admitted a ~5-min `find` hang and mitigated
# it with `-prune` rather than a bound — a latency fix, not a liveness one.
#
# WHY THESE FOUR AND NOT EVERY FORK. Bounded here are the classes that can genuinely block on something
# other than CPU: git (index.lock contention, a pathological repo), the filesystem walk (deep/slow trees,
# stalled volumes), an external SCRIPT that itself forks git, and cc-notify (the iTerm2/AppleEvent path —
# the PROVEN machine-wide wedge of 2026-07-26, where a bare `it2 session list` returned rc 124 with
# blocked forks piling up across ~110 sessions). Deliberately NOT wrapped: jq/stat/date/ps scalar reads
# of known-small local files — they have never hung here, and wrapping them would add ~6 forks per
# telemetry row per 30s sweep for no measured risk. If that judgement is ever wrong, the seam below
# bounds them too without a redesign.
#
# timeout(1) is resolved by ABSOLUTE PATH as well as PATH: launchd runs this daemon with a minimal PATH
# that EXCLUDES Homebrew, which is exactly where coreutils installs timeout — a PATH-only lookup would
# leave the launchd-run daemon (the only caller that matters) unbounded while an interactive test looked
# safe. No timeout(1) anywhere ⇒ run UNBOUNDED rather than break every external call: a missing binary
# must not turn `git`/`find` into rc 127, which would read as "cannot prove landed" and page on every
# healthy session. Seam: CC_SUP_TIMEOUT_BIN (set-but-EMPTY disables verbatim; `${VAR:-}` cannot tell
# unset from set-empty).
if [ -n "${CC_SUP_TIMEOUT_BIN+set}" ]; then
  SUP_TIMEOUT_BIN="$CC_SUP_TIMEOUT_BIN"
else
  SUP_TIMEOUT_BIN=""
  for _c in "$(command -v timeout 2>/dev/null || true)" "$(command -v gtimeout 2>/dev/null || true)" \
            /opt/homebrew/bin/timeout /usr/local/bin/timeout \
            /opt/homebrew/bin/gtimeout /usr/local/bin/gtimeout; do
    [ -n "$_c" ] && [ -x "$_c" ] && { SUP_TIMEOUT_BIN="$_c"; break; }
  done
fi
# Per-CLASS bounds: a git scalar read is sub-second when healthy, a pruned tree walk is seconds, the
# checkpoint script forks git itself, and cc-notify's own it2 shim self-bounds at 30s (so bound BELOW it
# — an outer bound above an inner one never fires). Each stays well under the reaper-horizon floor.
SUP_GIT_TIMEOUT_S="${CC_SUP_GIT_TIMEOUT_S:-15}"
SUP_FIND_TIMEOUT_S="${CC_SUP_FIND_TIMEOUT_S:-30}"
SUP_CKPT_TIMEOUT_S="${CC_SUP_CKPT_TIMEOUT_S:-60}"
SUP_NOTIFY_TIMEOUT_S="${CC_SUP_NOTIFY_TIMEOUT_S:-20}"
# `-k <n>`: SIGTERM at the bound, SIGKILL n seconds later — a fork that ignores TERM (a wedged
# AppleEvent client does) would otherwise keep the bound from actually releasing the sweep.
sup_bounded(){ # $1=seconds  $2..=command — rc 124 on a cut (timeout(1)'s contract)
  local s="$1"; shift
  if [ -z "$SUP_TIMEOUT_BIN" ] || [ ! -x "$SUP_TIMEOUT_BIN" ]; then "$@"; return $?; fi
  "$SUP_TIMEOUT_BIN" -k 5 "$s" "$@"
}
sup_git(){  sup_bounded "$SUP_GIT_TIMEOUT_S"  git "$@"; }

# The sweep interval SHARES reaper-horizon-lint's constant — never fork the number (invariant 7; the
# horizon floor is 10× this, enforced there). The actual daemon loop may be faster, never slower.
SUPERVISOR_SWEEP_MAX_S="${SUPERVISOR_SWEEP_MAX_S:-600}"
SWEEP="${SUPERVISOR_SWEEP:-30}"
[ "$SWEEP" -le "$SUPERVISOR_SWEEP_MAX_S" ] 2>/dev/null || SWEEP="$SUPERVISOR_SWEEP_MAX_S"

T="${CC_SUP_T:-73}"                                    # past-threshold (used_pct) — the B-1 boundary
STALL_S="${CC_SUP_STALL_S:-1800}"                      # telemetry age past which a live pid is a STALL? candidate
DEADLINE_S="${CC_SUP_PAGE_DEADLINE_S:-900}"            # page deadline before the re-observe (15m default)
TRUNK="${CC_SUP_TRUNK:-origin/main}"                   # trunk for the clean-completion landed-check (cf. cc-classify CC_CLASSIFY_TRUNK)
GC_S="${CC_SUP_GC_S:-21600}"                           # telemetry age past which a LIVE-OWNER row is GC'd — a hung/pid-recycled owner would STALL?-escalate every sweep forever (item fdc101e8b0c7). reaper-horizon-lint bounds this ≥ SUPERVISOR_SWEEP_MAX_S×10; default 6h = 12× STALL_S.
OWNER_PAT="${CC_SUP_OWNER_PAT:-claude}"               # a live pid OWNS its telemetry row only if its process command matches this — kill -0 alone reads a RECYCLED pid as the original session (the STALL? zombie)
TEL_DIR="${CC_TELEMETRY_DIR:-/tmp/cc-telemetry}"
IDL="${CC_IDL:-$HOME/.claude/autonomy/idl.jsonl}"
SUPLOG="${CC_SUPERVISOR_LOG:-$HOME/.claude/autonomy/supervisor.log}"
PAGEDIR="${CC_SUPERVISOR_PAGEDIR:-$HOME/.claude/autonomy/pages}"
PAGE_TO="${CC_PAGE_TO:-}"                              # EXPLICIT pane override (CC_PAGE_TO wins over the role)
PAGE_TO_FILE="${CC_PAGE_TO_FILE:-$HOME/.claude/cc-roles/desk}"   # the ROLE file cc-notify --role resolves (/dev/null disables)
# D7 send-damping state beside this pager's own state, so it inherits the CC_SUPERVISOR_PAGEDIR test
# isolation seam. Lives in a `damp/` SUBDIR: autonomy-sweep globs "$PAGES_DIR"/*.page at the top level
# only, so damp markers can never be mistaken for page records and wake the desk.
CC_PAGE_DAMP_DIR="${CC_PAGE_DAMP_DIR:-$PAGEDIR/damp}"
# cc-registry maps paneUUID → session_id (single shared dir across accounts). Bridges the desk role file
# (which holds a PANE uuid) to a telemetry session_id for the registered-desk STALL? exemption (item ff95faea46c8).
REGISTRY_DIR="${CC_REGISTRY_DIR:-$HOME/.claude/cc-registry}"
# ── PermissionRequest beacon (hooks/cc-permission-beacon.sh) — desk-anti-hitl §B2 ──
# A permission prompt on an unattended session HANGS (nothing in-session can answer). The MODAL is
# invisible to this bash sweep (S-3), but the HARNESS-emitted beacon at PERMPEND_DIR/<sid>.json IS
# readable → a precise "PERMISSION-PENDING: <cmd>" page instead of a slow, detail-free STALL?/MODAL.
PERMPEND_DIR="${CC_PERMPEND_DIR:-/tmp/cc-permission-pending}"   # MUST match the hook's default + seam
PERMPEND_NOTICE_S="${CC_PERMPEND_NOTICE_S:-120}"      # page a prompt pending ≥ this (auto-approved tools clear in ms ⇒ no false page)
PERMPEND_HORIZON_S="${CC_PERMPEND_HORIZON_S:-86400}"  # reap an orphaned beacon past this (hard-kill w/o SessionEnd + no telemetry)
# ── L2-c wait-contract watchdog (desk-audit G-P4-2, open since 2026-07-18) ──
# `wait-contract-lint.sh --sweep` is the ONE organ that enforces a wait contract INDEPENDENT of the
# waiter's own liveness — a DISK scan with {pid,start-time} identity, so a recycled pid cannot fake a
# live waiter. It was built, its --selftest is 13/13 GREEN, and it had NO scheduled caller anywhere:
# not here, not in launchd. A waiter that dies mid-wait therefore left an OPEN contract nobody paged —
# the exact 77-min-strand class the L2 layer was built to close, with the safety net never once fired.
# The clean contracts dir is NOT an exoneration: SATISFIED/TIMED_OUT are written producer-side by
# bin/cc-wait's close_contract at block-end; the sweep only PAGES and MARKS, it never closes.
# The supervisor is the right caller because it already IS the out-of-session, waiter-independent
# cadence — and this is a pure disk scan, i.e. exactly the class of work bash CAN do (no S-3 blindness).
WAIT_CONTRACTS_DIR="${CC_WAIT_CONTRACTS_DIR:-$HOME/.claude/wait-contracts}"  # cc-wait's OWN seam name — never fork the constant
SUP_WCLINT_TIMEOUT_S="${CC_SUP_WCLINT_TIMEOUT_S:-60}"   # bounded like every other external (it forks jq per contract)
# ── fired-peer lifecycle records: the "STARTED THEN DIED" half nobody owned ──
# handoff-fire.sh stamps `engagedAt` on cc-fired/<pane>.json the instant an oracle PROVED the peer
# engaged. Measured 2026-08-18: that field had ZERO production readers — one writer, two bats cases,
# docs, nothing else. So a peer that engaged and then died or stalled without self-closing left an OPEN
# record (closedAt null) that nothing aged: cc-classify drops an idle, unlanded, teamless pane into
# `owned-wait`, which is in NEITHER cc-reaper's REAPABLE_RE nor its SURFACE_PAGE_RE — never reaped,
# never surfaced, no board row. Start-ack owns "never started"; this owns "started, then went dark".
# Liveness signal = the peer's OWN transcript mtime (the same signal this file already trusts over
# telemetry), read from the record's `transcript` field — measured present and resolvable on 57/57 live
# open+engaged records.
# TWO horizons, and the upper one is load-bearing: on the live box 47 of 53 cold records are >7 days
# old — pre-existing archaeology whose originator is long gone. Paging those on the first sweep is the
# 2026-07-19 storm (53 findings at once). Past the upper horizon the record is cc-gc's, not the pager's.
FIRED_DIR="${CC_FIRED_DIR:-$HOME/.claude/cc-fired}"     # cc-reaper's OWN seam name — never fork the constant
FIRED_DARK_S="${CC_SUP_FIRED_DARK_S:-3600}"             # transcript silence past which an OPEN engaged peer is dark
FIRED_DARK_MAX_S="${CC_SUP_FIRED_DARK_MAX_S:-604800}"   # …and past which it is archaeology, not an actionable page
WCLINT_BIN="${CC_WCLINT_BIN:-}"
if [ -z "$WCLINT_BIN" ]; then
  for _c in "$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)/scripts/wait-contract-lint.sh" \
            "$HOME/.claude/scripts/wait-contract-lint.sh" "$(command -v wait-contract-lint.sh 2>/dev/null || true)"; do
    [ -n "$_c" ] && [ -x "$_c" ] && { WCLINT_BIN="$_c"; break; }
  done
fi
# cc-notify must resolve under launchd's bare default PATH (/usr/bin:/bin:...) — env override →
# beside-script repo bin → ~/.claude/bin → PATH (the autonomy-sweep resolve_bin order)
NOTIFY_BIN="${CC_NOTIFY_BIN:-}"
if [ -z "$NOTIFY_BIN" ]; then
  for _c in "$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)/bin/cc-notify" "$HOME/.claude/bin/cc-notify" "$(command -v cc-notify 2>/dev/null || true)"; do
    [ -n "$_c" ] && [ -x "$_c" ] && { NOTIFY_BIN="$_c"; break; }
  done
fi
# D7 send-damping (best-effort: absent lib ⇒ undamped, i.e. today's behaviour, never a lost page).
for _c in "$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)/hooks/lib/page-damp.sh" \
          "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/lib/page-damp.sh" "$HOME/.claude/hooks/lib/page-damp.sh"; do
  # shellcheck disable=SC1090,SC1091
  [ -f "$_c" ] && { . "$_c" 2>/dev/null || true; break; }
done

# ── the ONE send path for every supervisor page (v3 D2/D7) ───────────────────────────────────────
# ROLE-addressed by default: cc-notify resolves the role file at send time AND follows a `.forward`
# chain / reroutes a dead target — none of which a locally-cat'd uuid can do. Role name + dir are
# DERIVED from PAGE_TO_FILE (dirname → CC_ROLES_DIR, basename → role), so every existing seam keeps
# working unchanged (default → cc-roles/desk; the E2E's custom path → its own dir; /dev/null → not a
# regular file ⇒ no send). CC_PAGE_TO still forces one explicit pane.
#
# ── COMMS TRUTHFULNESS: the cc-notify RC IS the outcome; an ATTEMPT is not a send. ──
# This function used to `|| true` the cc-notify call and unconditionally `return 0`, i.e. it reported
# "sent" for an outcome it never looked at. Its callers write the `.notified` DAMPING marker on that
# 0 — so a page cc-notify REFUSED (rc 3: the role file holds a target that resolves to nothing; rc 5:
# the inbox is unwritable) was recorded as notified and NEVER RE-SENT. The supervisor's one
# operator-facing act would then be silent for the life of the incident, while the IDL showed a page.
# Now the rc decides, and a failure is LOUD (an IDL record) and RETRIED (no marker ⇒ the next sweep
# re-sends). Enqueue — not drain — is the bar cc-notify's rc 0 actually certifies; the dead-inbox
# case (rc 0, "mailbox only") is cc-notify's own reroute-to-desk path plus cc-inbox-guard's backstop,
# deliberately NOT re-paged here (a per-sweep re-page of an undrainable box is the 2026-07-19 storm).
# Returns 0 = ENQUEUED (or damping-suppressed) ⇒ caller records its marker · 1 = no channel wired ·
# 2 = send attempted and cc-notify FAILED ⇒ marker NOT recorded, so the next sweep retries.
# ── THERE IS NO DESK, AND THAT IS A SUPPORTED CONFIGURATION (2026-08-01) ─────────────────────────
# This pager was designed around a live "desk" orchestrator session: cc-roles/desk names a pane, and
# a page counts as DELIVERED when cc-notify reaches it. That fleet is not what runs here. No desk
# session is kept; com.claude.desk-invariant — the only organ that can CREATE one — is not loaded;
# and the role file still holds an iTerm2 pane uuid from 2026-07-26 whose pane has self-closed and
# whose `.forward` successor is equally dead, in a fleet that has since moved to kitty panes. So
# `cc-notify --role desk` returns rc 0 with verdict=mailbox-only/unverified FOREVER. That is a
# STATIC CONFIGURATION, not a transient fault, and the pager must be excellent in it — not merely
# survive it.
#
# e6d789a8 was right that rc alone is not the outcome (15.2 h of pages recorded as sent into a box
# holding 997 unacked lines). But it routed EVERY non-delivered verdict down the failure path, which
# `damp_forget`s the D7 marker so the next sweep re-sends. Against a permanently dead desk that is an
# unbounded loop: measured 2026-08-01, 8,025 `page SEND FAILED` lines and up to 1,519 OS
# notifications in ONE hour, 14 per 30 s sweep — precisely the 2026-07-19 composer storm the D7
# comments forbid. The remedy overshot the bug: silence became noise, and noise is the same zero bits
# (memory: alarm-polarity-and-attention-budget).
#
# The missing distinction is that "not delivered to a live pane" is THREE outcomes, and only the
# last is retryable:
#   REACHED   rc 0 + verdict=delivered  — a live session holds it. Done.
#   RECORDED  rc 0 + any other verdict  — enqueued to a mailbox with no proven reader. Under a
#             desk-less fleet this is the NORMAL steady state. The operator is reached on the
#             liveness-free channel instead, and the D7 marker is KEPT: the page WAS delivered, just
#             by the other channel. Re-deriving it every 30 s adds no information.
#   REFUSED   rc != 0 (3 unresolvable · 5 inbox unwritable · 124 cut at the bound) — the transport
#             took nothing at all. Marker withheld ⇒ the next sweep genuinely retries. This, and
#             only this, is the case e6d789a8's retry was built for.
#
# And because one notification PER FINDING is still a storm at 14 findings a sweep, the RECORDED
# class is DIGESTED (digest_flush): findings accumulate across the sweep and leave as ONE
# notification naming the causes.
#
# page_escalate_os <title-tail> <message> — delivery on a channel with NO liveness dependency.
# Notification Center needs no live pane and no role file, so it cannot rot the way cc-roles/desk did
# (it addressed a dead pane for 15 h on 2026-07-31). Text is passed as an AppleScript ARGV item,
# never interpolated into the script source — the message is attacker-adjacent (it quotes a blocked
# session's command line, which on 2026-07-31 was a shell-injection probe full of quotes and $( )).
# Still best-effort — it can never break the sweep that raised it — but it now RETURNS ITS OUTCOME
# (0 = posted · 1 = no channel, or the post failed/was cut) instead of always claiming 0. A caller
# that keeps a damping marker on the strength of this call must be able to tell whether anything was
# actually put in front of a human (memory: claimed-outcome-vs-checked-outcome).
page_escalate_os(){ # $1=title-tail  $2=message → 0 = POSTED · 1 = not posted
  os_channel_available || return 1
  sup_bounded 10 osascript - "$1" "$2" >/dev/null 2>&1 <<'OSA' || return 1
on run argv
  set v to item 1 of argv
  set m to item 2 of argv
  if (count of m) > 200 then set m to (text 1 thru 200 of m)
  display notification m with title ("Claude fleet — " & v) sound name "Funk"
end run
OSA
  return 0
}

# Is a liveness-free operator surface available AT ALL? If osascript is absent there is no desk-less
# delivery path, so RECORDED must stay a hard failure that retries — exactly the pre-2026-08-01
# posture. A capability we cannot use must never be assumed present.
#
# CC_SUP_OS_CHANNEL is a real operator switch as well as the test seam: `off` gives back the
# mailbox-only-and-retry posture (for a box where Notification Center is not the right surface, or a
# desk IS being run), `on` forces the channel, `auto` (default) probes. A pure `command -v` with no
# seam would be untestable in the one direction that matters — a suite cannot un-find /usr/bin/
# osascript via PATH, so the no-channel branch would ship unproven, which is how this whole class
# shipped in the first place.
os_channel_available(){
  case "${CC_SUP_OS_CHANNEL:-auto}" in
    off) return 1 ;;
    on)  return 0 ;;
    *)   command -v osascript >/dev/null 2>&1 ;;
  esac
}

# ── DIGEST — one notification per SWEEP, never one per finding ────────────────────────────────────
# Accumulated by send_page's RECORDED branch, flushed once at the end of sweep().
#
# FILE-backed, not shell globals, and that is load-bearing: sweep() collects its findings through
# COMMAND SUBSTITUTION — `r="$(assess "$f")"` and `pp="$(sweep_permission_pending)"` — so every
# send_page call runs inside a SUBSHELL. A counter incremented there mutates a copy that dies with
# the subshell, leaving the parent to flush an empty digest: findings recorded, operator never told.
# Measured on T32's first GREEN run — the anti-storm assertions passed while posts=0, i.e. the half
# that suppresses noise worked and the half that delivers had silently gone. A file crosses the
# subshell boundary; a variable cannot.
DIGEST_FILE="${CC_SUP_DIGEST_FILE:-$PAGEDIR/digest.pending}"
digest_add(){ # $1=state-fingerprint — reduce it to its CAUSE word and record it
  local c="${1:-page}"
  case "$c" in
    page:*:*) c="${c##*:}" ;;        # page:<sid>:<STATE> → the STATE is the news, not the sid
    *:*)      c="${c%%:*}" ;;        # permpend:… / selfcheck:… → the class word
  esac
  [ -n "$c" ] || c="page"
  _ensure
  printf '%s\n' "$c" >> "$DIGEST_FILE" 2>/dev/null || true
}
# The digest fingerprint is the distinct CAUSE SET plus a BUCKETED count — never the raw count. A
# fleet flapping 13↔14 findings is the same news and must stay quiet, while a NEW cause class, or a
# jump from 2 to 14, crosses a bucket and breaks through on the next sweep. (page-damp's contract:
# the fingerprint is the page's STATE, never a counter — a raw count is a counter wearing a state's
# clothes, and it would silently disable damping while looking wired.)
digest_bucket(){ # $1=n
  if   [ "$1" -le 1 ]; then printf '1'
  elif [ "$1" -le 4 ]; then printf '2-4'
  elif [ "$1" -le 9 ]; then printf '5-9'
  else                      printf '10+'
  fi
}
digest_flush(){
  [ -s "$DIGEST_FILE" ] || { rm -f "$DIGEST_FILE" 2>/dev/null; return 0; }
  local n causes fp
  n="$(wc -l < "$DIGEST_FILE" 2>/dev/null | tr -dc '0-9')"; : "${n:=0}"
  causes="$(sort -u "$DIGEST_FILE" 2>/dev/null | tr '\n' ',' | sed 's/,$//')"
  # CONSUME before deciding: a flush that returns early (damped) must not leave the pending set to
  # be re-counted next sweep, which would inflate every later digest by the whole backlog.
  rm -f "$DIGEST_FILE" 2>/dev/null
  [ "$n" -gt 0 ] || return 0
  fp="digest:${causes}:$(digest_bucket "$n")"
  if command -v damp_should_send >/dev/null 2>&1; then
    damp_should_send "os:notification-center" "$fp" || return 0    # unchanged news, inside the TTL
  fi
  if page_escalate_os "${n} session(s) need attention" \
       "No desk session is registered, so these were recorded to the mailbox and surfaced here instead. Causes: ${causes}. Detail: tail ${SUPLOG}"; then
    idl page_digest "\"n\":$n,\"causes\":$(json_str "$causes"),\"channel\":\"notification-center\",\"why\":\"no live desk — the liveness-free channel is the PRIMARY operator surface in this configuration; one digest per sweep, damped on the cause set\""
    printf '%s  digest POSTED n=%s causes=%s\n' "$(utc)" "$n" "$causes" >> "$SUPLOG" 2>/dev/null || true
  else
    # Nothing reached a human. Drop the digest's own marker so the next sweep re-posts it — the
    # per-finding markers stay (they are mailbox records); this one is the operator-facing claim.
    command -v damp_forget >/dev/null 2>&1 && damp_forget "os:notification-center" "$fp"
    printf '%s  digest POST FAILED n=%s causes=%s\n' "$(utc)" "$n" "$causes" >> "$SUPLOG" 2>/dev/null || true
  fi
  return 0
}

send_page(){ # $1=message [$2=state-fingerprint]
  local msg="$1" fp="${2:-}" target rdir rname rc=0
  [ -n "$NOTIFY_BIN" ] || return 1
  # resolved only to GATE on "is a channel wired at all" — the ADDRESS used below is the role itself
  target="$PAGE_TO"; [ -n "$target" ] || target="$(head -n1 "$PAGE_TO_FILE" 2>/dev/null | tr -d '[:space:]')"
  [ -n "$target" ] || return 1
  if [ -n "$fp" ] && command -v damp_should_send >/dev/null 2>&1; then
    damp_should_send "${PAGE_TO:-role:$PAGE_TO_FILE}" "$fp" || return 0   # suppressed, but still "handled"
  fi
  # BOUNDED: cc-notify reaches the iTerm2/AppleEvent path, the proven machine-wide wedge class
  # (2026-07-26: a bare `it2 session list --json` returned rc 124 with blocked forks piling up across
  # ~110 sessions). An unbounded page would hang the pager INSIDE the one act it exists to perform.
  # rc 124 needs no new branch: it is non-zero, so it takes the FAILED path below — marker withheld,
  # incident recorded, next sweep retries. That is precisely right for a cut send (we never learned
  # whether it was enqueued, so re-sending is the safe error).
  # CAPTURE cc-notify's stderr — it emits a parseable `verdict=` token, and the exit code alone is
  # NOT the outcome. Measured 2026-07-31: paging a role whose pane is dead returns
  #   verdict=mailbox-only enqueued=1 reason=target-not-live unacked=997   with rc=0
  # cc-notify is entirely honest ("no drain will run", "DELIVERED IS NOT READ"); this function was
  # the liar, because it checked `rc` and never read the token. Consequence: a session sat blocked
  # on a permission prompt for 15.2 hours while every page was recorded as SENT into a box holding
  # 997 unacked messages that no drain would ever run.
  # See memory claimed-outcome-vs-checked-outcome: emit a structured verdict its consumer can PARSE
  # — the token existed; nobody parsed it.
  local _out=""
  if [ -n "$PAGE_TO" ]; then
    _out="$(sup_bounded "$SUP_NOTIFY_TIMEOUT_S" "$NOTIFY_BIN" "$PAGE_TO" "$msg" 2>&1)"; rc=$?
  else
    rdir="$(dirname "$PAGE_TO_FILE")"; rname="$(basename "$PAGE_TO_FILE")"
    _out="$(CC_ROLES_DIR="$rdir" sup_bounded "$SUP_NOTIFY_TIMEOUT_S" "$NOTIFY_BIN" --role "$rname" "$msg" 2>&1)"; rc=$?
  fi

  # A verdict we cannot READ is a THIRD state — never silently promoted to success.
  local _verdict
  _verdict="$(printf '%s' "$_out" | grep -oE 'verdict=[a-z-]+' | head -1 | cut -d= -f2)"
  : "${_verdict:=unreadable}"

  # ── REACHED ──
  if [ "$rc" = 0 ] && [ "$_verdict" = delivered ]; then
    return 0
  fi

  # ── RECORDED — enqueued, but no live reader. The steady state of a desk-less fleet. ──
  # The mailbox record stands (a desk registered later drains it); the OPERATOR is reached on the
  # liveness-free channel, digested to one notification per sweep. The D7 marker is KEPT, because
  # the page was delivered — by the other channel. Re-sending it every 30 s is the storm, not the fix.
  if [ "$rc" = 0 ] && os_channel_available; then
    digest_add "$fp"
    printf '%s  page RECORDED (no live desk) verdict=%s fp=%s → digest\n' \
      "$(utc)" "$_verdict" "${fp:-none}" >> "$SUPLOG" 2>/dev/null || true
    return 0
  fi

  # ── REFUSED (or RECORDED with no liveness-free channel to fall back on) ──
  # Nothing anywhere took this page. Escalate what we can and RETRY: the D7 marker was written BEFORE
  # the attempt (an intent to send), and a failed send must not burn its TTL suppressing the retry.
  # The notification for THIS class goes through the digest as well, never one-per-finding: a
  # transport that starts refusing does so for every finding at once, so a per-finding escalation
  # here would rebuild the same storm in the other arm.
  if [ "$rc" = 0 ]; then
    echo "lead-supervisor: PAGE-UNDELIVERED verdict=$_verdict rc=$rc target=${PAGE_TO:-role:$PAGE_TO_FILE} — enqueued to a box with no drain, and no osascript channel to fall back on." >&2
  else
    digest_add "transport-refused"
  fi
  [ -n "$fp" ] && command -v damp_forget >/dev/null 2>&1 && damp_forget "${PAGE_TO:-role:$PAGE_TO_FILE}" "$fp"
  # NEVER silent: the page the operator did not get is itself an incident record (S-4).
  idl page_send_failed "\"target\":$(json_str "${PAGE_TO:-role:$(basename "$PAGE_TO_FILE")}"),\"notify_rc\":$rc,\"why\":\"cc-notify refused the page (rc $rc: 3=unresolvable target, 5=inbox unwritable, 124=CUT at the ${SUP_NOTIFY_TIMEOUT_S}s bound — send never completed) — NOT delivered; damping marker withheld so the next sweep retries\""
  printf '%s  page SEND FAILED rc=%s target=%s\n' "$(utc)" "$rc" "${PAGE_TO:-role:$(basename "$PAGE_TO_FILE")}" >> "$SUPLOG" 2>/dev/null || true
  return 2
}

now(){ date +%s; }
utc(){ date -u +%Y-%m-%dT%H:%M:%SZ; }
# JSON-encode an arbitrary string for safe embedding in an IDL line (quotes/backslashes/newlines) —
# never raw-%s a worker/command string into JSON (the malformed-IDL class, cc-backlog 666c6a64c45e).
json_str(){ jq -cn --arg s "${1:-}" '$s' 2>/dev/null || printf '""'; }
fmt_since(){ date -r "${1:-0}" +%H:%M 2>/dev/null || printf '%s' "${1:-?}"; }   # epoch → local HH:MM for the page
_ensure(){ mkdir -p "$(dirname "$IDL")" "$(dirname "$SUPLOG")" "$PAGEDIR" 2>/dev/null || true; }

# ── S-4: heartbeat — one IDL line PER SWEEP (even an all-clear one), plus per-finding records. ──
idl(){ # $1=kind  $2=json-body(no braces)
  _ensure; printf '{"ts":"%s","actor":"lead-supervisor","kind":"%s",%s}\n' "$(utc)" "$1" "$2" >> "$IDL" 2>/dev/null || true
}
heartbeat(){ # $1=n_swept $2=n_findings $3=n_gc(optional)
  idl heartbeat "\"swept\":$1,\"findings\":$2,\"gc\":${3:-0},\"sweep_s\":$SWEEP"
  printf '%s  swept=%s findings=%s gc=%s\n' "$(utc)" "$1" "$2" "${3:-0}" >> "$SUPLOG" 2>/dev/null || true
}

# ── PAGE — the only operator-facing act (besides safe checkpointing). Records a durable page + best-
#    effort cc-notify. NEVER reaps/closes anything. Deadline-stamped so resolve_page can re-observe. ──
page(){ # $1=sid $2=state $3=detail
  _ensure
  local pf="$PAGEDIR/$1.page" nf="$PAGEDIR/$1.notified"
  [ -f "$pf" ] || printf '%s\n' "$(now)" > "$pf"           # stamp the deadline clock on first page only
  idl page "\"sid\":\"$1\",\"state\":\"$2\",\"detail\":\"$3\""
  # composer damping: ONE notify per sid per STATE — a re-sweep of an already-notified state stays
  # IDL/mailbox-quiet; a state CHANGE (DEAD→ESCALATED) re-notifies (2026-07-19 page-storm fix: every
  # ~30s sweep re-notified every known-dead session, flooding the desk composer)
  local last; last="$(cat "$nf" 2>/dev/null || true)"
  [ "$last" = "$2" ] && return 0
  # ESCALATED is STICKY: the STALL?→ESCALATED pair re-fires every sweep for a zombie (stale telemetry
  # + reused pid), so equality damping alone still leaks 2 notifies/sweep — after an ESCALATED send,
  # only a genuine worsening to DEAD notifies again; the OK-branch clear_page resets the marker on a
  # true recovery, but a VOID keeps it (void_page, item 1c324d9fcc32) so a STALL?→void→re-STALL?
  # oscillation stays composer-damped — the stale-telemetry situation that triggered it still persists.
  [ "$last" = "ESCALATED" ] && [ "$2" != "DEAD" ] && return 0
  # Addressing resolves per page, not at startup (send_page): a pane rebind (role-file rewrite)
  # redirects pages with no plist edit and no daemon restart. D7 fingerprint = sid+state ONLY —
  # $3 (detail) carries volatile text that would change every sweep and silently defeat damping.
  if send_page "⚠️ SUPERVISOR PAGE — session $1 is $2: $3 (operator/delegated-live-session recovers; supervisor never auto-acts)" "page:$1:$2"; then
    printf '%s\n' "$2" > "$nf"                             # recorded only on a cc-notify-CONFIRMED enqueue
  fi                                                       # (rc 0). No channel wired (1) or a refused send
}                                                          # (2) leaves the marker off ⇒ the next sweep retries.
clear_page(){ rm -f "$PAGEDIR/$1.page" "$PAGEDIR/$1.notified" 2>/dev/null || true; }
# ── void a page WITHOUT resetting the notify-damping marker (item 1c324d9fcc32). ──
# A VOID means "alive + working, no escalation" — NOT "incident cleared, re-arm the alarm". The
# telemetry-staleness that raised the STALL? still persists, so the very next sweep re-pages the SAME
# candidate; dropping .notified here (as clear_page does) let every STALL?→void→re-STALL? cycle re-notify
# the desk (one composer ping per DEADLINE_S — the idle-live oscillation). Reset only the deadline clock
# (.page); keep .notified so the ongoing situation stays damped until it genuinely CHANGES (DEAD/ESCALATED
# break through; a true recovery clears it via the OK-branch clear_page).
void_page(){ rm -f "$PAGEDIR/$1.page" 2>/dev/null || true; }

# ── PERMISSION-PENDING page — a SEPARATE namespace (.permpend.*) from the telemetry-liveness pages so
#    assess()'s clear_page (fired every sweep for a below-threshold session) can NEVER clobber it. A
#    prompt-blocked session has stale telemetry, so assess would otherwise clear a permpend page. ──
page_permpend(){ # $1=sid $2=cmd $3=beacon_ts $4=age_s
  _ensure
  local sid="$1" cmd="$2" ts="$3" age="$4" nf="$PAGEDIR/$1.permpend.notified"
  idl permission_pending "\"sid\":\"$sid\",\"since\":$ts,\"age_s\":$age,\"cmd\":$(json_str "$cmd")"
  # Composer damping: ONE notify per PENDING EPISODE (keyed by the beacon ts). A NEW prompt (new ts)
  # re-notifies; the SAME prompt across sweeps stays quiet. clear_permpend resets on resolution.
  local last; last="$(cat "$nf" 2>/dev/null || true)"
  [ "$last" = "$ts" ] && return 0
  # D7 fingerprint = the EPISODE (sid + beacon ts): a new prompt is a new ts ⇒ new fingerprint ⇒ sends.
  # ${age} is excluded — it grows every sweep and would defeat damping while looking wired.
  if send_page "⛔ PERMISSION-PENDING — session $sid blocked ${age}s on a permission prompt: ${cmd} (since $(fmt_since "$ts")). Nothing in-session can answer; operator/live-session must approve or deny." "permpend:$sid:$ts"; then
    printf '%s\n' "$ts" > "$nf"                             # recorded only on a CONFIRMED enqueue (send_page rc 0)
  fi
}
clear_permpend(){ rm -f "$PAGEDIR/$1.permpend.notified" 2>/dev/null || true; }

# ── effect RE-READ (S-3b core): is a session emitting WORK-PRODUCTS, independent of whether it replied? ──
# "fresh" = new commits OR worktree file mtimes since the page. "dark" = none. "unknown" = WE COULD NOT
# LOOK — a bounded probe was CUT before it could answer.
#
# The third state is load-bearing, not defensive dressing. `dark` is the input the escalation path acts
# on, so folding a cut probe into `dark` would let a slow-but-healthy repo (a deep tree, a git index under
# contention) manufacture the escalation this whole protocol exists to prevent — the same trap the
# `-newermt` note below records, arriving through the timeout instead of through BSD find. And folding it
# into `fresh` would silently EXONERATE a genuinely hung lead. Neither is honest, so a cut says so, and
# resolve_page routes it: no escalation, but a durable IDL record naming which probe was cut (a
# never-answering probe is itself an incident — it must not read as a quiet system).
reobserve_effects(){ # $1=sid $2=cwd $3=since_epoch → prints "fresh" | "dark" | "unknown"
  local cwd="$2" since="$3" verdict=dark rc=0
  if [ -n "$cwd" ] && [ -d "$cwd" ]; then
    # a commit after the page = unambiguous liveness
    local last_commit
    last_commit="$(sup_git -C "$cwd" log -1 --format=%ct 2>/dev/null)"; rc=$?
    [ "$rc" = 124 ] && { printf 'unknown'; return; }
    [ "${last_commit:-0}" -gt "$since" ] 2>/dev/null && verdict=fresh
    # any tracked/untracked file touched after the page = work in flight. Use `-newer <ref>` (portable);
    # BSD find rejects `-newermt @epoch` ("Can't parse date/time"), which would make EVERY re-read read
    # dark and escalate a healthy lead — the exact silence-reap this protocol exists to prevent.
    if [ "$verdict" = dark ]; then
      local ref; ref="$(mktemp 2>/dev/null)"
      if [ -n "$ref" ]; then
        touch -t "$(date -r "$since" +%Y%m%d%H%M.%S 2>/dev/null || echo 197001010000)" "$ref" 2>/dev/null
        # PERF: -prune generated/scratch trees. `-not -path` still DESCENDS into them; -prune does not.
        # doc_classifier holds 1.27M files (tmp/ = 921K scale/prof fixtures). A full walk took ~5min vs
        # the 30s SWEEP, so sweeps overlapped and pinned the disk at ~1.6k tps while the box sat idle.
        # -prune bounds the COMMON case; the timeout bounds the pathological one it cannot predict.
        local hit
        hit="$(sup_bounded "$SUP_FIND_TIMEOUT_S" find "$cwd" \( -name .git -o -name tmp -o -name node_modules -o -name .venv -o -name venv -o -name __pycache__ -o -name .next -o -name dist -o -name .worktrees \) -prune -o -type f -newer "$ref" -print -quit 2>/dev/null)"; rc=$?
        rm -f "$ref"
        [ "$rc" = 124 ] && { printf 'unknown'; return; }
        [ -n "$hit" ] && verdict=fresh
      fi
    fi
  fi
  printf '%s' "$verdict"
}

# ── S-3b: at a page deadline, RE-OBSERVE; disposition (escalate) gates on the effects re-read ONLY. ──
resolve_page(){ # $1=sid $2=cwd
  local sid="$1" cwd="$2" pf="$PAGEDIR/$1.page"
  [ -f "$pf" ] || return 0
  local paged_at; paged_at="$(cat "$pf" 2>/dev/null || echo 0)"
  [ "$(( $(now) - ${paged_at:-0} ))" -ge "$DEADLINE_S" ] || return 0   # deadline not up yet — keep waiting
  # reply-compliance is NOT liveness: we do not read any reply. Only the fresh effects re-read decides.
  local effects; effects="$(reobserve_effects "$sid" "$cwd" "$paged_at")"
  if [ "$effects" = dark ]; then
    escalate_page "$sid" "$cwd"                 # effects-dark ⇒ disposition (never reached from silence alone)
  elif [ "$effects" = unknown ]; then
    # PROBE CUT — we did not observe dark, so we must not escalate; we did not observe fresh either, so
    # claiming "fresh-effects" would be a lie in the audit trail. Record the non-verdict under its own
    # IDL kind and re-observe next deadline. A repeated page_indeterminate for one sid is the signal that
    # this cwd is unprobeable within the bounds (raise CC_SUP_FIND_TIMEOUT_S / prune the tree) — visible
    # precisely because it is NOT filed as a void.
    idl page_indeterminate "\"sid\":\"$sid\",\"why\":\"effects re-read CUT by its timeout bound (git ${SUP_GIT_TIMEOUT_S}s / find ${SUP_FIND_TIMEOUT_S}s) — neither fresh nor dark was observed; NOT escalating on an unobserved state, re-observing at the next deadline\""
    void_page "$sid"                            # reset the deadline clock; keep notify damping
  else
    idl page_void "\"sid\":\"$sid\",\"why\":\"fresh-effects-after-deadline\""   # alive + working ⇒ VOID
    void_page "$sid"                            # reset the deadline clock but KEEP notify damping (item 1c324d9fcc32)
  fi
}
escalate_page(){ # $1=sid $2=cwd — page LOUDER (still page-only; the operator recovers). Never a reap.
  idl page_escalate "\"sid\":\"$1\",\"detail\":\"effects-dark past deadline — operator action needed\""
  page "$1" ESCALATED "no work-products across the page deadline; supervisor re-read confirms dark (still not auto-acting)"
}

# ── safe insurance: checkpoint a confirmed-DEAD lead's worktrees before anyone removes them (D-B). ──
checkpoint_preserve(){ # $1=sid $2=cwd
  local cwd="$2" rc=0
  [ -n "$cwd" ] && [ -d "$cwd" ] || return 0
  if command -v teammate-checkpoint.sh >/dev/null 2>&1; then
    # BOUNDED: this is an external script that forks git itself, so it inherits every git stall mode —
    # and it runs on the DEAD-lead path, i.e. exactly when the sweep must keep moving to page the
    # operator. A cut costs one checkpoint (insurance, already best-effort) and is recorded as such;
    # an unbounded hang here would cost every later sweep.
    CC_CHECKPOINT_MEMBER="supervisor-$1" sup_bounded "$SUP_CKPT_TIMEOUT_S" teammate-checkpoint.sh "$cwd" >/dev/null 2>&1 || rc=$?
  fi
  if [ "$rc" = 124 ]; then
    # NEVER silent: a checkpoint that did not happen must not be logged as one (the insurance the DEAD
    # page promises is now absent, and only this record says so).
    idl checkpoint_timeout "\"sid\":\"$1\",\"cwd\":\"$cwd\",\"bound_s\":$SUP_CKPT_TIMEOUT_S,\"why\":\"teammate-checkpoint.sh exceeded its bound and was cut — the dead lead's worktree is NOT checkpoint-preserved; the DEAD page below still fires\""
    return 0
  fi
  idl checkpoint "\"sid\":\"$1\",\"cwd\":\"$cwd\",\"why\":\"dead-lead-preserve\""
}

# ── CLEAN-COMPLETION detection (item 9b183d78c723): is a dead worker's worktree shipped+clean? ──
# 0 IFF clean tree AND the branch's content is landed on trunk — mirrors cc-classify / cc-reaper
# work_landed and cc-teardown-safety-gate G-a (the codebase-canonical shipped+clean gate). P0-17
# landed-by-CONTENT (incident dfacccd): a squash/cherry-pick land (different sha, same content) leaves
# HEAD "N ahead" by COUNT though the work is durably on trunk, so a bare count check would strand a
# finished session forever. A missing / non-git / unresolved-trunk worktree returns 1 — we cannot PROVE
# it clean, so the caller PAGES (the safe direction); work is never silently reaped unless verified landed.
# Every git call here is BOUNDED (sup_git). A cut yields rc 124, which this function treats exactly like
# any other failure — return 1 = "cannot PROVE clean+landed" ⇒ the caller PAGES. That is the safe
# direction and needs no new branch: a timed-out probe must never be read as "landed" and silently reaped.
work_landed(){ # $1=cwd → 0 clean+landed, 1 otherwise
  local cwd="$1"
  [ -n "$cwd" ] && [ -d "$cwd" ] || return 1
  sup_git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1 || return 1
  [ -z "$(sup_git -C "$cwd" status --porcelain 2>/dev/null)" ] || return 1
  local ahead; ahead="$(sup_git -C "$cwd" rev-list --count "$TRUNK"..HEAD 2>/dev/null)" || return 1
  [ "${ahead:-1}" = 0 ] && return 0                                 # fast path: 0 ahead by COUNT → landed
  # content path (squash/cherry-pick-tolerant): `git cherry` marks a HEAD commit '+' only when NO patch-id
  # equivalent is on trunk; zero '+' ⇒ every ahead commit is durably landed. tree-diff-0 = squash backstop.
  local cherry_out
  if cherry_out="$(sup_git -C "$cwd" cherry "$TRUNK" HEAD 2>/dev/null)"; then
    printf '%s\n' "$cherry_out" | grep -q '^+' || return 0
  fi
  sup_git -C "$cwd" diff --quiet "$TRUNK" HEAD 2>/dev/null && return 0
  return 1
}

# ── auto-reap a clean completion — the clean lifecycle end of a dispatched worker, NEVER a page. ──
# A dead worker whose worktree is shipped+clean left NOTHING stranded; the DEAD page exists to surface
# LOST/unlanded work, so this is a normal exit, not an incident. Reap = drop the telemetry row + clear any
# standing page/notify marker (autonomy/pages/<sid>.{page,notified}); recorded to the IDL (S-4 auditable —
# the reap is an outcome record, never a silent deletion).
reap_clean(){ # $1=sid $2=cwd
  idl reap "\"sid\":\"$1\",\"cwd\":\"$2\",\"why\":\"clean-completion-shipped-clean-worktree\""
  rm -f "$TEL_DIR/$1.json" 2>/dev/null || true
  clear_page "$1"
  printf '%s  reap sid=%s (clean+landed — dispatched-worker lifecycle end)\n' "$(utc)" "$1" >> "$SUPLOG" 2>/dev/null || true
}

# ── transcript liveness (item 1c324d9fcc32): the session's own JSONL is appended on EVERY message / ──
# tool event, so its mtime is a FAR fresher liveness signal than telemetry `ts`. The telemetry writer is
# the statusline, which stops emitting when a pane is not actively rendering (statusline.sh:48 — "a
# session inside ONE long operation, or genuinely hung, renders ZERO times"): a healthy BACKGROUNDED /
# long-turn / idle-interactive session goes telemetry-stale for hours while its transcript stays warm
# (measured 2026-07-19: a live session at 3.5-DAY-stale telemetry with a 5-min-warm transcript). Prints
# the transcript's age in seconds; a huge sentinel when it cannot be resolved (no config_dir / missing
# file) so the caller treats "unprovable" as COLD — fail-safe: we never exempt a stall we cannot disprove.
transcript_age(){ # $1=cwd $2=config_dir $3=sid → prints age_s (999999999 = unresolved ⇒ cold)
  local cwd="$1" cfg="$2" sid="$3" slug tp mt
  { [ -n "$cwd" ] && [ -n "$cfg" ] && [ -n "$sid" ]; } || { printf '%s' 999999999; return; }
  # CC projects/ dir mangling: EVERY character outside [a-zA-Z0-9] → '-'. This read `sed 's|[/.]|-|g'`
  # under the comment "every '/' and '.' → '-'", which is narrower than the encoder
  # (`A.replace(/[^a-zA-Z0-9]/g,"-")`, and 1,661 live project dirs all match ^[-a-zA-Z0-9]+$). The
  # direction matters here: a narrow slug names a directory that CANNOT exist, so the `[ -f "$tp" ]`
  # below misses, transcript_age returns its unresolved sentinel — which this caller reads as COLD —
  # and a demonstrably-alive session with a fresh transcript is paged STALL? anyway. The warm-transcript
  # exemption at the call site is exactly what stops that, and it was unreachable for any cwd holding
  # a character other than '/', '.', '-' or alphanumerics (e.g. ~/Development/doc_classifier, a real
  # repo on this box). Fail direction: a FALSE page about a healthy session.
  slug="$(printf '%s' "$cwd" | LC_ALL=C sed 's/[^a-zA-Z0-9]/-/g')"
  tp="$cfg/projects/$slug/$sid.jsonl"
  [ -f "$tp" ] || { printf '%s' 999999999; return; }
  mt="$(stat -f %m "$tp" 2>/dev/null || stat -c %Y "$tp" 2>/dev/null || echo 0)"   # BSD stat, then GNU fallback
  printf '%s' "$(( $(now) - ${mt:-0} ))"
}

# ── registered-desk identity (item ff95faea46c8): is this telemetry sid THE monitoring desk? ──
# The desk is a legitimately-idle MONITOR — it watches quietly between pages, so during a normal quiet
# window (30m+) its telemetry AND its transcript both go stale while the session is fully ALIVE (cc-reaper
# classifies it [active]; its pid is real, not reused). Telemetry-freshness is therefore a FALSE liveness
# proxy for the desk, and the warm-transcript exemption above cannot save it — an idle monitor emits no
# transcript messages between pages either, so BOTH ages exceed STALL_S and it false-flags STALL?→ESCALATED
# every deadline. A pid-identity check (does the pid run claude?) does NOT help: the desk's pid legitimately
# runs claude. The fix is IDENTITY-based, keyed on the correct liveness signal (pid alive), not staleness:
# desk liveness is authoritatively owned by desk-invariant.sh (assistant-turn recency + owned wait-contracts,
# launchd every 300s) plus cc-reaper's [active] surface, so lead-supervisor must NOT double-count it with a
# structurally-wrong staleness heuristic. Coverage is not lost: a DEAD desk pid still hits the DEAD branch
# above (effect-verified), and a genuinely-hung (pid-alive) desk is caught by desk-invariant + the permission
# beacon. Identity bridge mirrors is_monitoring_desk (waiting-recycle.sh) / desk-invariant.sh: the desk role
# file (PAGE_TO_FILE) holds the desk's PANE uuid OR its sid; map a pane via cc-registry/<pane>.json.session_id.
is_registered_desk(){ # $1=telemetry session_id → 0 iff it is the registered monitoring desk
  local sid="$1" ref rsid
  [ -n "$sid" ] || return 1
  ref="$(head -1 "$PAGE_TO_FILE" 2>/dev/null | tr -d '[:space:]')"
  [ -n "$ref" ] || return 1
  [ "$ref" = "$sid" ] && return 0                        # role file holds the sid directly
  rsid="$(jq -r '.session_id // .sessionId // empty' "$REGISTRY_DIR/$ref.json" 2>/dev/null)"  # else ref is a pane uuid → registry-bridge
  [ -n "$rsid" ] && [ "$rsid" = "$sid" ]
}

# ── pid-identity: does this pid still OWN its telemetry row, or was it recycled? (item fdc101e8b0c7) ──
# kill -0 proves only that SOME process holds the pid — after a session exits, the OS recycles its pid to
# an unrelated process (or a NEWER claude), so a days-dead row's pid reads as "alive" and the STALL? branch
# re-escalates it every sweep (the zombie: 266841ba 14h-stale, 5277b63a 3d-stale, 2026-07-19). A live pid
# is the ORIGINAL owner only if its process command still marks it a claude session. This resolves the
# recycled-by-NON-claude case in assess() (route it to DEAD, insurance intact); the recycled-by-claude and
# genuine-hung-owner cases (command still matches) are dropped by gc_stale once the row ages past GC_S.
pid_alive_owner(){ # $1=pid → 0 iff alive AND its process command marks it a claude session owner
  local p="$1"
  [ -n "$p" ] && kill -0 "$p" 2>/dev/null || return 1
  ps -p "$p" -o command= 2>/dev/null | grep -qiF "$OWNER_PAT"
}

# ── GC — drop a LIVE-OWNER telemetry row that has been stale past the horizon (item fdc101e8b0c7). ──
# The statusline re-exports a row every turn boundary, so cc-context's own contract is "rows older than
# ~15m are idle or closed". Past GC_S (default 6h = 12× STALL_S) the owning claude has not emitted for
# hours — hung, or its pid recycled to another claude — yet its command still matches, so the STALL?
# branch would re-page it EVERY sweep forever. GC drops the row (+ any standing page) so the zombie stops
# re-paging; recorded to the IDL (S-4 auditable). GUARD: only a still-ALIVE OWNER is GC'd here — a GONE or
# recycled-NON-owner pid is left to assess(), whose DEAD path reap_clean's a clean completion and
# checkpoint-preserves + PAGES a stranded death (dirty/unlanded); GC must never silently drop that
# insurance. Self-healing: a still-live idle owner re-exports a fresh row on its next turn boundary.
gc_stale(){ # → prints the count of horizon-stale live-owner rows dropped
  local f sid ts pid age g=0
  [ -d "$TEL_DIR" ] || { echo 0; return; }
  for f in "$TEL_DIR"/*.json; do
    [ -e "$f" ] || continue
    ts="$(jq -r '.ts // 0' "$f" 2>/dev/null)"; ts="${ts%.*}"; case "$ts" in ''|*[!0-9]*) ts=0;; esac
    age=$(( $(now) - ts ))
    [ "$age" -ge "$GC_S" ] || continue
    pid="$(jq -r '.pid // empty' "$f" 2>/dev/null)"
    pid_alive_owner "$pid" || continue                              # GONE / recycled-non-owner → leave for assess()
    sid="$(jq -r '.session_id // empty' "$f" 2>/dev/null)"
    rm -f "$f" 2>/dev/null || true
    [ -n "$sid" ] && clear_page "$sid"
    idl gc "\"sid\":\"${sid:-unknown}\",\"age\":$age,\"horizon\":$GC_S,\"pid\":\"${pid:-}\",\"why\":\"live-owner pid on telemetry ${age}s stale >= ${GC_S}s horizon — hung or pid-recycled owner; dropped the row so it stops re-paging every sweep\""
    g=$((g+1))
  done
  echo "$g"
}

# ── classify one telemetry row and route to a PAGE (never an action) ──
assess(){ # $1=telemetry-json-file → prints 1 if it produced a finding, else 0
  local f="$1" sid used ts cwd cfg pid age
  sid="$(jq -r '.session_id // empty' "$f" 2>/dev/null)"; [ -n "$sid" ] || { echo 0; return; }
  used="$(jq -r '.used_pct // 0' "$f" 2>/dev/null)"; used="${used%.*}"; case "$used" in ''|*[!0-9]*) used=0;; esac
  ts="$(jq -r '.ts // 0' "$f" 2>/dev/null)"; ts="${ts%.*}"; case "$ts" in ''|*[!0-9]*) ts=0;; esac
  cwd="$(jq -r '.cwd // empty' "$f" 2>/dev/null)"
  cfg="$(jq -r '.config_dir // empty' "$f" 2>/dev/null)"
  pid="$(jq -r '.pid // empty' "$f" 2>/dev/null)"
  age=$(( $(now) - ts ))

  # DEAD — the owning pid is GONE, or was RECYCLED to a non-claude process (kill -0 lies: it proves only
  # that SOME process holds the pid, item fdc101e8b0c7). Either way the original session has exited, so it
  # is classified exactly like pid-gone. CLEAN COMPLETION vs STRANDED death (item 9b183d78c723).
  if [ -n "$pid" ] && ! pid_alive_owner "$pid"; then
    # A dead worker whose worktree is shipped+clean (clean tree AND content landed on trunk) finished its
    # dispatched item and exited — a normal lifecycle end, ~68% of dead-pid rows (13/19, 2026-07-19) and the
    # dominant source of desk wake-toil. Auto-reap and NEVER page. Only an UNFINISHED/stranded death (dirty
    # tree, unlanded commits, or a cwd we cannot prove clean) is checkpoint-preserved + PAGED, as before.
    if work_landed "$cwd"; then reap_clean "$sid" "$cwd"; echo 0; return; fi
    local why="owning pid $pid gone"
    kill -0 "$pid" 2>/dev/null && why="owning pid $pid recycled to a non-claude process (session gone)"
    checkpoint_preserve "$sid" "$cwd"; page "$sid" DEAD "$why; worktree checkpoint-preserved"; echo 1; return
  fi
  # STALL? — pid ALIVE and still a claude OWNER but telemetry stale: a CANDIDATE, never an action. Page with
  # the deadline→re-observe protocol; a resolve_page on the next sweep re-reads effects. (Age alone can NEVER
  # confirm a stall — a healthy long turn renders zero times too; only the effects re-read discriminates. A
  # recycled/non-owner pid took the DEAD branch above; a genuinely-hung owner ages out via gc_stale.)
  # WARM-TRANSCRIPT EXEMPTION (item 1c324d9fcc32): telemetry staleness alone is a FALSE stall signal, so
  # require the transcript ALSO stale before treating a live owner as a candidate — a warm transcript ⇒ the
  # session is demonstrably alive ⇒ fall through to OK (stops the idle-live STALL?→void→re-STALL? oscillation).
  # REGISTERED-DESK EXEMPTION (item ff95faea46c8): a pid-alive registered monitoring desk is legitimately idle
  # between pages — BOTH telemetry and transcript go stale by design, so `! is_registered_desk` drops it to OK;
  # its liveness is owned by desk-invariant.sh, not this staleness proxy (see is_registered_desk).
  if pid_alive_owner "$pid" && [ "$age" -ge "$STALL_S" ] && ! is_registered_desk "$sid"; then
    local tage; tage="$(transcript_age "$cwd" "$cfg" "$sid")"
    if [ "$tage" -ge "$STALL_S" ]; then
      # SAME-SWEEP GUARD (2026-07-25 flaky-gate incident): resolve only a PRE-EXISTING page. page()
      # stamps paged_at in integer seconds, so a page created at X.99s read by resolve_page at
      # X+1.00s computes deadline-elapsed=1 — with a 1s deadline the page "expires" inside its own
      # sweep ⇒ phantom same-sweep ESCALATE (a 2-notify storm the e2e catches as a sporadic,
      # load-sensitive flake — T22b forces it deterministically). The deadline clock starts AT the
      # page; re-observation belongs to a later sweep. Deferred, never dropped: the next sweep's
      # re-page finds the file pre-existing and resolves normally.
      local had_page=0; [ -f "$PAGEDIR/$sid.page" ] && had_page=1
      page "$sid" "STALL?" "pid alive but telemetry ${age}s + transcript ${tage}s stale — CANDIDATE; re-observing effects at deadline"
      [ "$had_page" = 1 ] && resolve_page "$sid" "$cwd"
      echo 1; return
    fi
  fi
  # B-1 — PAST-THRESHOLD ∧ NOT-STOPPING: fill ≥ T but the session is live and fresh (still working, never
  # Stopped) so the boundary hook cannot fire for it. Advise via a page; the live session's own model acts.
  if [ "$used" -ge "$T" ] && [ "$age" -lt "$STALL_S" ]; then
    page "$sid" PAST-THRESHOLD "used ${used}% ≥ ${T}% and still running (not Stopping) — the boundary hook is blind here; advise /handoff"
    echo 1; return
  fi
  # OK — clear any stale page (fresh + below threshold + alive).
  clear_page "$sid"; echo 0
}

# ── a human-legible one-liner for the blocked command, from the harness-authored tool_input ──
# Bash → the command; Write/Edit/etc → the file path; anything else → tool_name + compact input.
beacon_cmd(){ # $1=beacon-file → single-line, ≤160 chars
  local f="$1" c
  c="$(jq -r '
        .tool_input.command
        // .tool_input.file_path
        // .tool_input.path
        // ((.tool_name // "tool") + " " + ((.tool_input // {}) | tostring))' "$f" 2>/dev/null)"
  [ -n "$c" ] && [ "$c" != "null" ] || c="$(jq -r '.tool_name // "?"' "$f" 2>/dev/null)"
  c="$(printf '%s' "$c" | tr '\n\t' '  ' | sed 's/  */ /g')"   # collapse to one line
  [ "${#c}" -gt 160 ] && c="${c:0:157}..."
  printf '%s' "${c:-?}"
}

# ── PERMISSION-PENDING beacons: harness-emitted, UNSPOOFABLE. Unlike the MODAL blindness (S-3) the
#    supervisor CANNOT see, a permission prompt leaves a durable beacon it CAN read → a precise,
#    command-attached page (minutes-latency) instead of a slow detail-free STALL?/MODAL. ──
sweep_permission_pending(){ # prints the number of PERMISSION-PENDING pages produced this sweep
  local dir="$PERMPEND_DIR" found=0 bf sid ts age tel pid cmd
  [ -d "$dir" ] || { echo 0; return; }
  for bf in "$dir"/*.json; do
    [ -e "$bf" ] || continue
    sid="$(basename "$bf" .json)"
    case "$sid" in *[!A-Za-z0-9._-]*|''|.|..) continue ;; esac      # ignore stray/unsafe filenames
    ts="$(jq -r '.ts // 0' "$bf" 2>/dev/null)"; ts="${ts%.*}"; case "$ts" in ''|*[!0-9]*) ts=0;; esac
    age=$(( $(now) - ts ))
    # REAP 1 — owning session provably DEAD (pid gone via its telemetry): the prompt died with it. No page.
    tel="$TEL_DIR/$sid.json"
    if [ -f "$tel" ]; then
      pid="$(jq -r '.pid // empty' "$tel" 2>/dev/null)"
      if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
        rm -f "$bf" 2>/dev/null; clear_permpend "$sid"; continue
      fi
    fi
    # REAP 2 — orphan past the long horizon (hard-kill with no SessionEnd AND no telemetry to pid-check).
    # A ts=0 (malformed) beacon has age≈now ≥ horizon ⇒ reaped, never paged (fail-safe on garbage).
    if [ "$age" -ge "$PERMPEND_HORIZON_S" ]; then
      rm -f "$bf" 2>/dev/null; clear_permpend "$sid"; continue
    fi
    # PAGE — genuinely pending past the notice threshold.
    if [ "$age" -ge "$PERMPEND_NOTICE_S" ]; then
      cmd="$(beacon_cmd "$bf")"
      page_permpend "$sid" "$cmd" "$ts" "$age"
      found=$((found+1))
    fi
  done
  echo "$found"
}

# ── V3: telemetry↔LIVE-PANE delta self-check — "is my world-view even populated?" (audit 2026-07-22) ──
# EVERY pager path in this file starts from `$TEL_DIR/*.json`. That dir is a SINGLE, FRAGILE world-view:
# it lives in /tmp (reboot-cleared), and its only writer is the statusline, which stops emitting the
# moment a pane is not actively rendering (statusline.sh:48). So the supervisor's world can be EMPTY
# while sessions are live — and an empty world produces a clean all-clear heartbeat, indistinguishable
# from a genuinely quiet fleet. Sessions invisible here are invisible to DEAD, STALL?, PAST-THRESHOLD and
# the permission beacon alike: they have no pager at all, and nothing says so.
#
# cc-reaper already answers this for itself (P0-12b, cc-reaper:528-556) with an INDEPENDENT count that
# deliberately does not read the same source it is checking. This is that check, for this daemon.
#
# LOCKSTEP: the process-identity clause below is the same one cc-reaper live_pane_count and cc-reconcile
# live_claude_pids carry, and it must not drift from them — argv0 is the claude binary (or its cli.js),
# excluding headless one-shots (-p/--print/--version) and env-inherited node/MCP children. `claude.exe` is
# the eval-track install's own binary name and a FIRST-CLASS interactive session (session-register.sh:63),
# so omitting it would undercount live panes and desensitize this detector in both directions. The clause
# is duplicated across ~10 files in this tree with no lint holding them together; consolidating that is
# named as follow-on work, NOT done here — a silent 11th copy with no note would be the worse option.
live_pane_count(){
  ps -wwEo command= 2>/dev/null | awk '
    { t0=$1
      if (t0!="claude" && t0!="claude.exe" && t0 !~ /\/claude$/ && t0 !~ /\/claude\.exe$/ && t0 !~ /cli\.js/) next
      for (i=2; i<=7 && i<=NF; i++) if ($i=="-p" || $i=="--print" || $i=="--version") next
      c++ }
    END { print c+0 }'
}
PANE_DELTA_TOL="${CC_SUP_PANE_DELTA_TOL:-0}"                 # live−enumerated > tol ⇒ blind spot (mirrors cc-reaper's default)
SELFCHECK_MIN_PERSIST="${CC_SUP_SELFCHECK_MIN_PERSIST:-2}"   # delta must persist N sweeps — a spawn mid-sweep is not a blind spot
# PAGE-ONLY and DAMPED, like every other act here: page once per delta, and again only on a genuine
# WORSENING. An undamped per-sweep re-page of a standing condition is the 2026-07-19 composer storm.
self_check(){ # $1=enumerated-count
  local enum="$1" live delta sf consec paged
  live="$(live_pane_count)"
  case "$live" in ''|*[!0-9]*) return 0 ;; esac      # unreadable ps ⇒ ABSTAIN (no verdict), never a phantom Δ
  delta=$(( live - enum ))
  sf="$PAGEDIR/selfcheck.state"
  if [ "$delta" -le "$PANE_DELTA_TOL" ]; then
    _ensure; printf '0 0\n' > "$sf" 2>/dev/null || true   # re-arm on recovery
    return 0
  fi
  _ensure
  read -r consec paged < <(cat "$sf" 2>/dev/null || echo "0 0"); consec="${consec:-0}"; paged="${paged:-0}"
  consec=$(( consec + 1 ))
  if [ "$consec" -ge "$SELFCHECK_MIN_PERSIST" ] && { [ "$paged" = 0 ] || [ "$delta" -gt "$paged" ]; }; then
    idl selfcheck_page "\"live\":$live,\"enumerated\":$enum,\"delta\":$delta,\"persisted_sweeps\":$consec,\"why\":\"$delta live Claude pane(s) are absent from the supervisor's telemetry world-view — they have NO pager coverage on any path (DEAD/STALL?/PAST-THRESHOLD/permission-beacon all iterate that dir)\""
    # D7 fingerprint = the DELTA, so a worsening blind spot breaks through while a standing one stays quiet.
    send_page "⚠️ SUPERVISOR SELF-CHECK — ${live} live Claude pane(s) but only ${enum} in telemetry (Δ${delta} unseen). Those sessions have NO supervisor coverage: every pager path reads ${TEL_DIR}, so a stall/death there pages NOBODY. Likely the statusline is not emitting (backgrounded/long-turn panes) or ${TEL_DIR} was reboot-cleared. Compare \`ls ${TEL_DIR}\` against the live interactive-claude procs." \
              "selfcheck:blind:delta$delta" && paged="$delta"
    printf '%s  self-check BLIND live=%s enum=%s delta=%s\n' "$(utc)" "$live" "$enum" "$delta" >> "$SUPLOG" 2>/dev/null || true
  fi
  printf '%s %s\n' "$consec" "$paged" > "$sf" 2>/dev/null || true
}

# ── L2-c: run the wait-contract watchdog on this sweep's cadence (G-P4-2) ──
# The lint OWNS the page (page-once per state on the contract file, escalation at 3 repeats), so this
# never re-pages what the lint already paged — a second page for the same fact is the wolf-cry the L2
# marker exists to prevent. What the supervisor adds is (a) a caller at all, and (b) the divergence in
# its OWN heartbeat: a sweep that found an orphaned wait must not record an all-clear (S-4).
# Counting is keyed on the ASCII words in the lint's own report lines — never the ⛔/⏰ glyphs, which a
# C-locale byte-split would make unmatchable (memory: c-locale-turns-character-ops-into-byte-ops).
sweep_wait_contracts(){ # prints the number of DIVERGENT contracts found this sweep
  local out rc n
  if [ -z "$WCLINT_BIN" ] || [ ! -x "$WCLINT_BIN" ]; then
    # The watchdog is UNRESOLVABLE — declare it, but not once per 30 s forever. The marker is a FILE,
    # never a shell variable: this function runs inside a COMMAND SUBSTITUTION, so a variable set here
    # mutates a copy that dies with the subshell (the digest's own measured trap, above).
    _ensure
    if [ ! -f "$PAGEDIR/wclint-missing" ]; then
      : > "$PAGEDIR/wclint-missing" 2>/dev/null || true
      idl wait_contract_sweep_unavailable "\"why\":\"wait-contract-lint.sh is not resolvable from this daemon (checked beside-script, ~/.claude/scripts, PATH) — OPEN wait contracts have NO liveness-independent watchdog; run ./install.sh from the checkout\""
    fi
    echo 0; return
  fi
  rm -f "$PAGEDIR/wclint-missing" 2>/dev/null || true      # re-arm: a later disappearance is news again
  [ -d "$WAIT_CONTRACTS_DIR" ] || { echo 0; return; }      # nobody has ever waited — vacuous, not an alarm
  out="$(sup_bounded "$SUP_WCLINT_TIMEOUT_S" "$WCLINT_BIN" --sweep "$WAIT_CONTRACTS_DIR" 2>&1)"; rc=$?
  if [ "$rc" = 124 ]; then
    idl wait_contract_sweep_cut "\"bound_s\":$SUP_WCLINT_TIMEOUT_S,\"dir\":$(json_str "$WAIT_CONTRACTS_DIR"),\"why\":\"the wait-contract sweep was CUT at its bound — this sweep produced NO verdict on wait contracts (a cut probe is not an all-clear)\""
    echo 0; return
  fi
  n="$(grep -c -E 'DEAD-WAITER|PAST-DEADLINE|ESCALATED' <<<"$out" | tr -d ' ')"
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  if [ "$n" -gt 0 ]; then
    idl wait_contract_divergence "\"n\":$n,\"dir\":$(json_str "$WAIT_CONTRACTS_DIR"),\"detail\":$(json_str "$(grep -E 'DEAD-WAITER|PAST-DEADLINE|ESCALATED' <<<"$out" | head -5)"),\"why\":\"an OPEN wait contract diverged (dead waiter or past deadline) — the lint paged it page-once; recovery is PAGED, never auto\""
    printf '%s  wait-contract divergence n=%s\n' "$(utc)" "$n" >> "$SUPLOG" 2>/dev/null || true
  fi
  echo "$n"
}

# ── the fired-peer dark sweep: read `engagedAt`, age the OPEN records (see the horizons above) ──
# PAGE-ONCE per pane via a marker FILE (this function runs inside a command substitution, so a shell
# variable would die with the subshell — the digest's own measured trap), and ONE aggregate page per
# sweep rather than one per pane: 6 findings on the first live sweep must arrive as one message, never
# as six. The marker is REMOVED when the record closes or goes warm again, so a genuine recurrence is
# news a second time.
sweep_fired_dark(){ # prints the number of dark fired peers found this sweep
  local f pane engaged closed tp mt age n=0 fresh=0 names="" mk
  [ -d "$FIRED_DIR" ] || { echo 0; return; }
  _ensure; mkdir -p "$PAGEDIR/fired-dark" 2>/dev/null || true
  for f in "$FIRED_DIR"/*.json; do
    [ -e "$f" ] || continue
    pane="$(jq -r '.paneUUID // empty' "$f" 2>/dev/null)"
    # ADDRESS SHAPE: a safe filename component, NOT "hex-shaped". `hdl-<hex>` is a real pane
    # address (bin/cc-pane-headless:124/:197); the hex spelling refused it. SSOT rationale:
    # hooks/session-register.sh. Backlog 4b9d5e93b40a (writer) + 5d1b5dd9b3db (this consumer).
    case "$pane" in ''|.|..|.*|*[!A-Za-z0-9._-]*) continue ;; esac
    mk="$PAGEDIR/fired-dark/$pane"
    closed="$(jq -r '.closedAt // "null"' "$f" 2>/dev/null || echo x)"
    engaged="$(jq -r '.engagedAt // "null"' "$f" 2>/dev/null || echo x)"
    # SPENT (self-closed) or NEVER-ENGAGED are both other organs' business — and a spent record that
    # once paged must re-arm, or a later pane reusing the id would be silently suppressed.
    if [ "$closed" != null ] || [ "$engaged" = null ] || [ "$engaged" = x ]; then
      rm -f "$mk" 2>/dev/null || true; continue
    fi
    tp="$(jq -r '.transcript // empty' "$f" 2>/dev/null)"
    if [ -z "$tp" ] || [ ! -f "$tp" ]; then
      # UNPROVABLE, declared rather than folded into either verdict: with no readable transcript we
      # cannot say dark and must not say healthy. Recorded once per pane, never paged.
      if [ ! -f "$mk.unprovable" ]; then
        : > "$mk.unprovable" 2>/dev/null || true
        idl fired_peer_unprovable "\"pane\":$(json_str "$pane"),\"why\":\"an OPEN engaged fired-peer record whose transcript is null or missing — this sweep can neither prove nor disprove that the peer is still alive\""
      fi
      continue
    fi
    rm -f "$mk.unprovable" 2>/dev/null || true
    mt="$(stat -f %m "$tp" 2>/dev/null || stat -c %Y "$tp" 2>/dev/null || echo 0)"
    age=$(( $(now) - ${mt:-0} ))
    if [ "$age" -lt "$FIRED_DARK_S" ] || [ "$age" -ge "$FIRED_DARK_MAX_S" ]; then
      [ "$age" -lt "$FIRED_DARK_S" ] && rm -f "$mk" 2>/dev/null || true    # warm again ⇒ re-arm
      continue
    fi
    n=$((n+1))
    [ -f "$mk" ] && continue                                    # already declared — no wolf-cry
    : > "$mk" 2>/dev/null || true
    fresh=$((fresh+1)); names="${names:+$names }$pane"
    idl fired_peer_dark "\"pane\":$(json_str "$pane"),\"originator\":$(json_str "$(jq -r '.originator // .firedBy // ""' "$f" 2>/dev/null)"),\"cwd\":$(json_str "$(jq -r '.cwd // ""' "$f" 2>/dev/null)"),\"engaged_at\":$(json_str "$engaged"),\"transcript_age_s\":$age,\"why\":\"a fired peer ENGAGED and then went dark for ${age}s without ever self-closing (closedAt null) — cc-classify calls this owned-wait, which is in neither REAPABLE_RE nor SURFACE_PAGE_RE, so nothing else reaps it, pages it or gives it a board row\""
  done
  if [ "$fresh" -gt 0 ]; then
    send_page "⚠️ ${fresh} fired peer(s) ENGAGED then went DARK (no self-close, transcript silent ≥$(( FIRED_DARK_S / 60 ))m): ${names}. Nothing reaps or surfaces this state — re-observe each pane, then close it or hand its work back. Recovery is PAGED, never auto." \
              "fired-dark:n$fresh" || true
    printf '%s  fired-peer dark n=%s new=%s\n' "$(utc)" "$n" "$fresh" >> "$SUPLOG" 2>/dev/null || true
  fi
  echo "$n"
}

sweep(){
  local n=0 found=0 gc r pp wc fd
  gc="$(gc_stale)"                 # GC horizon-stale live-owner zombies FIRST — they are resolved, not a per-sweep finding
  if [ -d "$TEL_DIR" ]; then
    for f in "$TEL_DIR"/*.json; do
      [ -e "$f" ] || continue
      n=$((n+1)); r="$(assess "$f")"; found=$(( found + ${r:-0} ))
    done
  fi
  # MODAL is STRUCTURALLY invisible to this bash sweep (S-3): we cannot read a modal/permission dialog or
  # the composer. We never claim a session is modal-free; a live-but-effect-dark session is PAGED as a
  # possible MODAL for the operator to eyeball. (Recorded here so the blindness is declared, not hidden.)
  # But a permission prompt DOES leave a harness-emitted beacon — read it for a precise page (§B2).
  pp="$(sweep_permission_pending)"; found=$(( found + ${pp:-0} ))
  # L2-c: the wait-contract watchdog runs on THIS cadence (G-P4-2) — a disk scan, so it is enforceable
  # from bash and survives the death of every waiter it audits.
  wc="$(sweep_wait_contracts)"; found=$(( found + ${wc:-0} ))
  # The other liveness-independent disk contract: a fired peer that engaged and then went dark.
  fd="$(sweep_fired_dark)"; found=$(( found + ${fd:-0} ))
  # V3 self-check LAST, on the count this sweep actually enumerated: a heartbeat of "swept 0, found 0" is
  # an all-clear that must not be emitted while live panes sit outside the world-view it swept.
  self_check "$n"
  # LAST act of the sweep: every page RECORDED-but-not-delivered above leaves as ONE notification.
  # This is the desk-less fleet's primary operator surface, so it must run after self_check — a
  # blind-spot page belongs in the same digest as the findings it may explain.
  digest_flush
  heartbeat "$n" "$found" "$gc"
}

case "${1:-}" in
  --selftest)   exec bash "$(dirname "$0")/supervisor-e2e.sh" ;;
  --once)       sweep ;;
  --daemon|"")  while :; do sweep; sleep "$SWEEP"; done ;;
  *)            echo "usage: lead-supervisor.sh [--once|--daemon|--selftest]" >&2; exit 2 ;;
esac
