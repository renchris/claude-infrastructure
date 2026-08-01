#!/bin/bash
# autonomy-sweep.sh — THE ONE pull-based consumer of the escalation write-only dirs (a18 SO-5,
# a17 S-7/D-2: the escalation lattice terminated NOWHERE — every layer wrote durable evidence into
# dirs with no reader). This is the single sweep that drains them and turns dead-letter records into
# a desk WAKE. launchd-runnable (a 300s tick) and supervisor-callable.
#
# Each run:
#   1. Collect NEW records (deduped by a per-record .seen marker) from:
#        pages/                  supervisor page stamps
#        cc-announce-alarms/     announce-layer alarms
#        completion-push/        terminal-completion pushes whose verdict != "verified" (stuck)
#        decisions/*.json        OPEN class-B/C packets awaiting operator early-veto
#   2. Run `cc-decide expire-sweep` — the sweep is the class-B default ACTUATOR: for each fired
#      default it appends a cc-backlog item (bounded + auditable), NEVER acting inline. A default
#      the PRODUCER declared `no-change` actuates nothing, so it is counted + summarised but gets
#      NO backlog item — an open item is cc-dispatch's fire predicate, and a worker must never be
#      spawned on "hold (no change without ruling)". The item is filed against the packet's own
#      declared `subject_project` when it has one, else this sweep's host project.
#   3. If anything NEW exists → ONE cc-notify to the desk ROLE (cc-roles/desk, resolved at
#      send-time — SO-1 role indirection), then mark those records .seen IF AND ONLY IF a delivery
#      was actually PROVEN — cc-notify's `verdict=` token, never its exit code, and never the mere
#      existence of a role file (see § DELIVERY IS A VERDICT below; a dead uuid is still non-empty).
#   4. Write ONE {fired|abstained} IDL record (B-3: didn't-fire ≠ never-ran).
#   5. Age-compact: the .seen markers AND the six write-only event dirs (see below).
#
# EVIDENCE law (inv7), amended 2026-07-25 (audit 03 §1b/§1c, fix 5): source records used to be
# NEVER deleted. That made every event dir unbounded — `comms-alarms/` had *zero* rm sites of any
# kind, `pages/` 389 files, `push-records/` 318 — and the audit's systemic finding was that the
# reaper lint has a FLOOR but no CEILING, so nothing could ever notice. The law is now: a source
# record is never deleted while it can still be READ AS LIVE, and ages out at CC_EVENT_TTL_DAYS
# (7 d = 604,800 s, ~1000× the reaper-horizon-lint floor) once it cannot. Seven days is two orders
# of magnitude past the 300 s sweep that drains these dirs, so no observer can miss a record.
# `decisions/` and `backlog.jsonl` are deliberately EXCLUDED — they are durable ledgers, not events.
# `inbox-guard/` is a DAMPING marker store, not an event log, so age alone must not clear it (that
# would re-fire the escalation it damps); it reaps only when its mailbox subject is also gone.
#
# Env (tests): CC_PAGES_DIR · CC_ANNOUNCE_ALARM_DIR · CC_COMPLETION_RECORDS_DIR · CC_DECISIONS_DIR
#   · CC_ROLES_DIR · CC_IDL · CC_SWEEP_SEEN_DIR · CC_SWEEP_SEEN_TTL_DAYS (default 7)
#   · CC_COMMS_ALARM_DIR · CC_PUSH_RECORDS_DIR · CC_TEARDOWN_RECORDS_DIR
#   · CC_INBOX_GUARD_STATE_DIR · CC_MAILBOX_DIR · CC_EVENT_TTL_DAYS (default 7)
#   · CC_NOTIFY_BIN · CC_DECIDE_BIN · CC_BACKLOG_BIN
#   · CC_SWEEP_OS_CHANNEL (auto|on|off) · CC_SWEEP_NOTIFY_TIMEOUT_S (default 25)
#   BSD+GNU portable, no eval, fail-loud.
set -uo pipefail

PAGES_DIR="${CC_PAGES_DIR:-$HOME/.claude/autonomy/pages}"
ALARM_DIR="${CC_ANNOUNCE_ALARM_DIR:-$HOME/.claude/cc-announce-alarms}"
COMPLETION_DIR="${CC_COMPLETION_RECORDS_DIR:-$HOME/.claude/completion-push}"
DECISIONS_DIR="${CC_DECISIONS_DIR:-$HOME/.claude/autonomy/decisions}"
ROLES_DIR="${CC_ROLES_DIR:-$HOME/.claude/cc-roles}"
IDL="${CC_IDL:-$HOME/.claude/autonomy/idl.jsonl}"
SEEN_DIR="${CC_SWEEP_SEEN_DIR:-$HOME/.claude/autonomy/sweep-seen}"
SEEN_TTL="${CC_SWEEP_SEEN_TTL_DAYS:-7}"
# The six write-only event dirs this sweep now age-reaps (defaults match each PRODUCER's own env
# name, so a test that redirects the producer redirects the reaper with it).
COMMS_ALARM_DIR="${CC_COMMS_ALARM_DIR:-$HOME/.claude/autonomy/comms-alarms}"
PUSH_RECORDS_DIR="${CC_PUSH_RECORDS_DIR:-$HOME/.claude/autonomy/push-records}"
TEARDOWN_DIR="${CC_TEARDOWN_RECORDS_DIR:-$HOME/.claude/cc-teardown}"
INBOX_GUARD_DIR="${CC_INBOX_GUARD_STATE_DIR:-$HOME/.claude/autonomy/inbox-guard}"
MAILBOX_DIR="${CC_MAILBOX_DIR:-$HOME/.claude/mailbox}"
EVENT_TTL="${CC_EVENT_TTL_DAYS:-7}"

usage() { sed -n '2,/^set -uo/p' "$0" | sed 's/^# \{0,1\}//; /^set -uo/d'; }
case "${1:-}" in -h|--help) usage; exit 0 ;; esac

command -v jq >/dev/null 2>&1 || { echo "autonomy-sweep: jq required" >&2; exit 1; }

now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# Shared helpers (consolidation audit 02): resolve_bin lived here AND in boot-resume.sh, already drifted.
# Resolution ladder mirrors the hooks/lib house idiom: beside-script → CFG → ~/.claude.
_ccl="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/lib/cc-common.sh"
[ -f "$_ccl" ] || _ccl="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/scripts/lib/cc-common.sh"
[ -f "$_ccl" ] || _ccl="$HOME/.claude/scripts/lib/cc-common.sh"
# shellcheck source=lib/cc-common.sh
# shellcheck disable=SC1091  # runtime-resolved source; the ship gate runs shellcheck without -x
if ! . "$_ccl" 2>/dev/null; then
  # Fail LOUD: this is a launchd job, and silently proceeding with unresolved helper paths is the
  # silent-degradation failure mode these scripts exist to avoid.
  echo "autonomy-sweep: FATAL — cannot source $_ccl (resolve_bin unavailable)" >&2
  exit 1
fi
NOTIFY="$(resolve_bin "${CC_NOTIFY_BIN:-}"  cc-notify)"
DECIDE="$(resolve_bin "${CC_DECIDE_BIN:-}"  cc-decide)"
BACKLOG="$(resolve_bin "${CC_BACKLOG_BIN:-}" cc-backlog)"

mkdir -p "$SEEN_DIR" 2>/dev/null || true

seen_key()  { printf '%s' "$1" | shasum -a 256 | cut -c1-32; }
is_new()    { [ ! -f "$SEEN_DIR/$(seen_key "$1")" ]; }
mark_seen() { : > "$SEEN_DIR/$(seen_key "$1")" 2>/dev/null || true; }

# Accumulator of surfaced record paths (newline-separated; marked .seen only after a delivery).
SURFACED=""
add_surfaced() { SURFACED="${SURFACED}$1
"; }

new_pages=0 new_alarms=0 new_pushfailed=0 open_decisions=0 fired_defaults=0 fired_nochange=0

# ── 1. collect NEW pages / alarms ──────────────────────────────────────────────
for f in "$PAGES_DIR"/*.page; do
  [ -e "$f" ] || continue
  is_new "$f" && { new_pages=$((new_pages + 1)); add_surfaced "$f"; }
done
for f in "$ALARM_DIR"/*; do
  [ -f "$f" ] || continue
  is_new "$f" && { new_alarms=$((new_alarms + 1)); add_surfaced "$f"; }
done
# completion-push: only records whose verdict is NOT "verified" are stuck (push-failed / pending).
for f in "$COMPLETION_DIR"/*; do
  [ -f "$f" ] || continue
  is_new "$f" || continue
  v="$(jq -r '.verdict // ""' "$f" 2>/dev/null || echo "")"
  case "$v" in verified) continue ;; esac
  new_pushfailed=$((new_pushfailed + 1)); add_surfaced "$f"
done

# ── 2. expire-sweep = the class-B default ACTUATOR (append to backlog, never act inline) ──
if [ -n "$DECIDE" ]; then
  # FIVE fields: "fired <id> <subject_project|-> <change|no-change> <default>". Every cell is
  # PADDED by the emitter (bin/cc-decide § cmd_expire_sweep) precisely because tab is IFS-
  # whitespace: an empty cell here would collapse the run and shift `deffect` into `dproj` on the
  # no-project packets, i.e. on the exact population this branch exists to handle.
  while IFS="$(printf '\t')" read -r tag did dproj deffect ddef; do
    [ "$tag" = "fired" ] || continue
    fired_defaults=$((fired_defaults + 1))

    # A NO-CHANGE default actuates NOTHING — "hold (no change without ruling)", "disclose-only
    # (already landed; silence = no further change)", "park this decision to the backlog and
    # continue other work". Each of those became an OPEN backlog item, and `open` is exactly
    # cc-dispatch's fire predicate, so the next tick could claim it and spawn a peer session whose
    # entire assignment was to change nothing. The fired default is still COUNTED (so it lands in
    # the summary + the IDL and still wakes the desk) — it is only kept out of the dispatch queue.
    # The trail survives without a work item: the packet itself is the evidence (transitioned to
    # `expired-actioned`, never deleted — inv7) plus cc-decide's own expire-sweep IDL line.
    # The predicate is cc-decide's, read verbatim; nothing here inspects the default's wording.
    if [ "$deffect" = "no-change" ]; then
      fired_nochange=$((fired_nochange + 1))
      continue
    fi

    if [ -n "$BACKLOG" ]; then
      # --project EXPLICITLY. This sweep runs from launchd with cwd=/, and omitting it left
      # cc-backlog to default off $(pwd) → project "/", which matches no dispatcher filter: 5 of
      # these records sat structurally undrained for 8 days (item f7abcbdee98c). cc-backlog now
      # REFUSES a degenerate default rather than storing one, so this value must be passed.
      #
      # PREFER the packet's own declared subject: the producer knew its cwd, so a project recorded
      # at `cc-decide open --project` is the decision's real subject rather than the sweep's host.
      # Absent ("-"), fall back to the host project as before — the sweep must NEVER recover the
      # subject by grepping a path out of `what_plain`; that is the shape-classifier that must not
      # be built (memory: fixture-vs-real-classifier-needs-a-producer — classify by the producer's
      # literal emission, never by shape). On the fallback the SUBJECT stays resolvable by the
      # reader from `--dod-ref decision:<id>`, which is exact.
      dispatch_project="$dproj"
      case "$dispatch_project" in
        ""|"-") dispatch_project="${CC_SWEEP_PROJECT:-claude-infrastructure}" ;;
      esac
      "$BACKLOG" add --title "class-B default fired: $ddef" \
        --project "$dispatch_project" \
        --source autonomy-sweep --dod-ref "decision:$did" >/dev/null 2>&1 || true
    fi
  done < <("$DECIDE" expire-sweep 2>/dev/null || true)
fi

# ── decisions still OPEN after the expire-sweep → surface once (awaiting early-veto) ──
for f in "$DECISIONS_DIR"/*.json; do
  [ -e "$f" ] || continue
  # status FOLD (see bin/cc-decide § SFOLD): an ABSENT or empty `.status` reads as "open". A packet
  # written outside `cc-decide open` can omit the key entirely, and a bare `// ""` would drop it from
  # the page — silently, since this is a `continue`. Fail OPEN: an unclassifiable packet must page.
  st="$(jq -r '.status // "" | if . == "" then "open" else . end' "$f" 2>/dev/null || echo "open")"
  [ "$st" = "open" ] || continue
  is_new "$f" || continue
  open_decisions=$((open_decisions + 1)); add_surfaced "$f"
done

total_new=$((new_pages + new_alarms + new_pushfailed + open_decisions + fired_defaults))

# ── age-compact the .seen markers ──
find "$SEEN_DIR" -type f -mtime +"$SEEN_TTL" -delete 2>/dev/null || true

# ── age-reap the six write-only EVENT dirs (audit 03 fix 5; see the EVIDENCE law above) ──
# One horizon, six paths, `-maxdepth 1 -type f` so a nested subdir is never walked into. Each dir
# is drained by THIS sweep on a 300 s tick, so a 7-day-old record has been surfaced ~2,000 times.
reap_event_dir() { # <dir>
  [ -d "$1" ] || return 0
  find "$1" -maxdepth 1 -type f -mtime +"$EVENT_TTL" -delete 2>/dev/null || true
}
reap_event_dir "$PAGES_DIR"          # supervisor page stamps  (389 files, oldest 07-14)
reap_event_dir "$COMMS_ALARM_DIR"    # comms safety gate       (395 files, ZERO rm sites before this)
reap_event_dir "$PUSH_RECORDS_DIR"   # push-send verdicts      (318 files)
reap_event_dir "$COMPLETION_DIR"     # completion-push records (77 files)
reap_event_dir "$TEARDOWN_DIR"       # cc-teardown records     (154 files)
# inbox-guard is DAMPING state, not an event log: `<key>.escalated` suppresses a repeat escalation
# for mailbox <key>. Age alone must not clear it — that would re-fire the very page it damps (the
# 216-page storm lesson). Reap only when the marker is BOTH past the horizon AND its mailbox
# subject is gone, at which point the marker can no longer damp anything.
if [ -d "$INBOX_GUARD_DIR" ]; then
  while IFS= read -r mk; do
    [ -n "$mk" ] || continue
    key="$(basename "$mk" .escalated)"
    [ -n "$(find "$MAILBOX_DIR" -maxdepth 1 -name "$key*" -print 2>/dev/null | head -1)" ] && continue
    rm -f "$mk" 2>/dev/null || true
  done < <(find "$INBOX_GUARD_DIR" -maxdepth 1 -type f -name '*.escalated' -mtime +"$EVENT_TTL" 2>/dev/null)
fi

log_idl() { # <disposition> <extra JSON OBJECT (optional, jq-built {…}; default {})>
  mkdir -p "$(dirname "$IDL")" 2>/dev/null || true
  local extra="${2:-}"; [ -n "$extra" ] || extra='{}'
  # jq-encode EVERY field (numerics via --argjson, strings via --arg): a value carrying a " /
  # backslash / newline then can NEVER emit a malformed IDL line — one malformed line aborts the
  # cc-audit four-zeros `jq -rs` slurp (reads as "no records" ⇒ silent D9/alarm false-GREEN).
  jq -cn --arg ts "$(now_iso)" --arg disp "$1" \
    --argjson np "$new_pages" --argjson na "$new_alarms" --argjson npf "$new_pushfailed" \
    --argjson od "$open_decisions" --argjson fd "$fired_defaults" \
    --argjson fnc "$fired_nochange" --argjson extra "$extra" \
    '{ts:$ts,tool:"autonomy-sweep",disposition:$disp,new_pages:$np,new_alarms:$na,
      new_pushfailed:$npf,open_decisions:$od,fired_defaults:$fd,
      fired_nochange:$fnc} + $extra' \
    >> "$IDL" 2>/dev/null || true
}

if [ "$total_new" -eq 0 ]; then
  log_idl abstained '{"reason":"nothing-new"}'
  exit 0
fi

# ── 3. build a compact summary + notify the desk ROLE (resolved at send-time) ──
summary="[desk-sweep] NEW:"
[ "$new_pages"      -gt 0 ] && summary="$summary ${new_pages} page(s),"
[ "$new_alarms"     -gt 0 ] && summary="$summary ${new_alarms} alarm(s),"
[ "$new_pushfailed" -gt 0 ] && summary="$summary ${new_pushfailed} push-failed,"
[ "$open_decisions" -gt 0 ] && summary="$summary ${open_decisions} open decision(s),"
# fired defaults split two ways: the ones that queued work, and the no-change ones that are
# SURFACED here but deliberately never dispatched. Reporting only the total would read as "N items
# queued" on a sweep that queued none of them.
if [ "$fired_defaults" -gt 0 ]; then
  summary="$summary ${fired_defaults} class-B default(s) fired"
  # ${summary} BRACED, not $summary: `$summary→backlog` parses the multibyte arrow into the NAME,
  # so under `set -u` the sweep died with "summary\xe2: unbound variable" — rc 1 on exactly the
  # runs that queued something. Caught by the positive control, which is why it exists.
  [ "$((fired_defaults - fired_nochange))" -gt 0 ] && summary="${summary}→backlog"
  [ "$fired_nochange" -gt 0 ] && summary="${summary} (${fired_nochange} no-change: surfaced, NOT dispatched)"
  summary="${summary},"
fi
summary="${summary%,}"

# ── DELIVERY IS A VERDICT, NOT AN EXIT CODE (2026-08-01) ──────────────────────────────────────────
# This block used to discard cc-notify's rc (`|| true`), route its stderr to /dev/null, and then
# mark_seen UNCONDITIONALLY on the strength of the desk role file merely being NON-EMPTY. Both
# halves were wrong on this machine, and had been for weeks:
#   · No desk orchestrator runs here. cc-roles/desk holds an iTerm2 pane uuid from 2026-07-26 whose
#     pane has self-closed and whose `.forward` successor is equally dead, so cc-notify returns
#     rc 0 with verdict=mailbox-only/unverified FOREVER. That is a STATIC CONFIGURATION, not a
#     transient fault, and this sweep must be correct in it.
#   · The a17 S-7 protection below ("no desk role ⇒ do NOT mark seen, retry next sweep") keys on
#     DESK_TARGET being EMPTY. A role file holding a DEAD uuid is non-empty, so that branch is
#     structurally UNREACHABLE in precisely the configuration it exists for.
# Net effect: every page, comms alarm, push-failure and open decision was written into a box no
# drain will ever run and then marked .seen — permanent SILENT LOSS, never re-surfaced. The inline
# comment asserting "delivered … makes this durable" was simply false. (964 markers were sitting in
# ~/.claude/autonomy/sweep-seen when this was found.)
#
# The remedy mirrors scripts/lead-supervisor.sh § send_page (e5894631): "not delivered to a live
# pane" is THREE outcomes, and only .seen-worthiness distinguishes them.
#   REACHED   rc 0 + verdict=delivered — a live session holds it ⇒ mark seen.
#   RECORDED  rc 0 + any other verdict — enqueued to a mailbox with NO PROVEN READER. Under a
#             desk-less fleet this is the NORMAL steady state, so a bare retry-forever is the
#             2026-07-19 storm, not a fix. Reach the operator on a channel with no liveness
#             dependency instead, and mark seen ONLY if that channel actually took it.
#   REFUSED   rc != 0 (3 unresolvable · 5 inbox unwritable · 124 cut at the bound), or RECORDED
#             with no liveness-free channel to fall back on — nothing anywhere took it ⇒ NEVER
#             mark seen, say so loudly, and let the next sweep re-surface the same records.
# memory: claimed-outcome-vs-checked-outcome — the structured verdict token existed all along;
# nobody parsed it.

# BOUNDED: cc-notify reaches the iTerm2/AppleEvent path, the proven machine-wide wedge class
# (2026-07-26: a bare `it2 session list --json` returned rc 124 with blocked forks piling up across
# ~110 sessions). This runs from launchd on a 300 s tick; an unbounded send would wedge the sweep
# INSIDE the one act it exists to perform. rc 124 needs no branch of its own — it is non-zero, so it
# takes the REFUSED path, records stay unseen, and the next sweep retries. That is exactly right for
# a cut send: we never learned whether it was enqueued, so re-surfacing is the safe error.
TIMEOUT_BIN="$(command -v timeout 2>/dev/null || command -v gtimeout 2>/dev/null || true)"
sweep_bounded() { # <seconds> <cmd…> — rc 124 on a cut (timeout(1)'s contract)
  local s="$1"; shift
  if [ -z "$TIMEOUT_BIN" ] || [ ! -x "$TIMEOUT_BIN" ]; then "$@"; return $?; fi
  "$TIMEOUT_BIN" -k 5 "$s" "$@"
}
NOTIFY_TIMEOUT_S="${CC_SWEEP_NOTIFY_TIMEOUT_S:-25}"

# Is a liveness-free operator surface available AT ALL? Notification Center needs no live pane and
# no role file, so it cannot rot the way cc-roles/desk did. Where it is absent there is no desk-less
# delivery path at all, and RECORDED must stay a hard non-delivery that retries — the pre-fix
# posture, minus the false .seen.
#
# CC_SWEEP_OS_CHANNEL is a real operator switch as well as the test seam: `off` restores
# mailbox-only-and-retry (for a box where Notification Center is not the right surface, or where a
# desk IS being run), `on` forces the channel, `auto` (default) probes. A bare `command -v` with no
# seam would leave the no-channel branch untestable — no suite can un-find /usr/bin/osascript via
# PATH — which is how this whole class shipped unproven in the first place.
os_channel_available() {
  case "${CC_SWEEP_OS_CHANNEL:-auto}" in
    off) return 1 ;;
    on)  return 0 ;;
    *)   command -v osascript >/dev/null 2>&1 ;;
  esac
}

# Delivery on a channel with NO liveness dependency. Best-effort — it can never break the sweep that
# raised it — but it RETURNS ITS OUTCOME (0 = posted · 1 = no channel, or the post failed/was cut),
# because the caller forgets records on the strength of this call and must be able to tell whether
# anything was actually put in front of a human (memory: claimed-outcome-vs-checked-outcome).
# Text is passed as an AppleScript ARGV item, never interpolated into the script source: the summary
# is machine-built from counts today, but a caller that ever widens it must not be able to inject.
# One post per SWEEP at most, and only when NEW records exist — a record surfaces once, so the
# channel is self-damping and needs no marker store of its own.
sweep_escalate_os() { # <title-tail> <message> → 0 = POSTED · 1 = not posted
  os_channel_available || return 1
  sweep_bounded 10 osascript - "$1" "$2" >/dev/null 2>&1 <<'OSA' || return 1
on run argv
  set v to item 1 of argv
  set m to item 2 of argv
  if (count of m) > 200 then set m to (text 1 thru 200 of m)
  display notification m with title ("Claude fleet — " & v) sound name "Funk"
end run
OSA
  return 0
}

mark_surfaced_seen() { # forget the records — ONLY ever called on a proven delivery
  printf '%s' "$SURFACED" | while IFS= read -r rec; do [ -n "$rec" ] && mark_seen "$rec"; done
}

DESK_TARGET=""
[ -f "$ROLES_DIR/desk" ] && DESK_TARGET="$(head -1 "$ROLES_DIR/desk" 2>/dev/null | tr -d '[:space:]')"

if [ -n "$DESK_TARGET" ] && [ -n "$NOTIFY" ]; then
  # Address the ROLE, never the uuid read above: cc-notify re-reads cc-roles/desk at SEND time and
  # follows the `.forward` chain, so a desk recycled since this sweep started still gets the wake
  # (a18 SO-1 role indirection — which this file's header has claimed since it was written, while
  # the code sent to a snapshot). DESK_TARGET is now read ONLY to gate on "is a channel wired at
  # all", which is also precisely why it can never be the delivery evidence.
  # CAPTURE stderr: cc-notify prints a machine-parseable `verdict=` token there, and the exit code
  # alone is NOT the outcome. Measured 2026-07-31 against a dead pane:
  #   cc-notify: verdict=mailbox-only enqueued=1 reason=target-not-live unacked=997   with rc=0
  notify_out="$(CC_ROLES_DIR="$ROLES_DIR" sweep_bounded "$NOTIFY_TIMEOUT_S" "$NOTIFY" --role desk "$summary" 2>&1)"
  notify_rc=$?
  # A verdict we cannot READ is a THIRD state — never silently promoted to success.
  notify_verdict="$(printf '%s' "$notify_out" | grep -oE 'verdict=[a-z-]+' | head -1 | cut -d= -f2)"
  : "${notify_verdict:=unreadable}"

  if [ "$notify_rc" -eq 0 ] && [ "$notify_verdict" = delivered ]; then
    # ── REACHED — a live session holds it. ──
    mark_surfaced_seen
    log_idl fired "$(jq -cn --arg summary "$summary" --arg v "$notify_verdict" \
      '{notified:"role:desk",delivered:true,channel:"desk",verdict:$v,summary:$summary}')"
  elif [ "$notify_rc" -eq 0 ] && sweep_escalate_os "${total_new} new escalation record(s)" \
         "No live desk session took this, so it was recorded to the mailbox and surfaced here. ${summary}"; then
    # ── RECORDED, and the liveness-free channel TOOK it. The records were delivered — by the other
    # channel — so they are forgotten. Re-surfacing them every 300 s adds no information. ──
    mark_surfaced_seen
    log_idl fired "$(jq -cn --arg summary "$summary" --arg v "$notify_verdict" \
      '{notified:"role:desk",delivered:true,channel:"notification-center",verdict:$v,summary:$summary,
        why:"no live desk — enqueued to the mailbox with no proven reader, so the operator was reached on the liveness-free channel instead"}')"
  else
    # ── REFUSED — nothing anywhere took it. Markers WITHHELD so the next sweep re-surfaces the same
    # records. Deliberately NOT escalated to the OS channel: a permanently refusing transport
    # re-surfaces its records every 300 s, and there is no damping store here, so a post on this
    # path would be an unbounded notification storm (the failure mode e5894631 was fixed for).
    # NEVER silent: the wake the operator did not get is itself an incident record (a17 S-4). ──
    log_idl fired "$(jq -cn --arg summary "$summary" --arg v "$notify_verdict" --argjson rc "$notify_rc" \
      '{notified:"role:desk",delivered:false,channel:"none",verdict:$v,notify_rc:$rc,summary:$summary,
        why:"cc-notify did not reach a live reader and no liveness-free channel took it — records NOT marked seen, the next sweep re-surfaces them"}')"
    echo "autonomy-sweep: NEW records UNDELIVERED verdict=$notify_verdict rc=$notify_rc target=role:desk — nothing proved a reader; records left unseen, will retry" >&2
  fi
else
  # No desk role (or no notify binary): fail LOUD and do NOT mark seen → the SAME records
  # re-surface next sweep once the role is set (a17 S-7: never let a wake drain to nobody).
  log_idl fired '{"notified":"no-desk-role","delivered":false}'
  echo "autonomy-sweep: NEW records but no desk role at $ROLES_DIR/desk — undelivered, will retry" >&2
fi
exit 0
