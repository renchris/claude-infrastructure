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
#      default it appends a cc-backlog item (bounded + auditable), NEVER acting inline.
#   3. If anything NEW exists → ONE cc-notify to the desk ROLE (cc-roles/desk, resolved at
#      send-time — SO-1 role indirection), then mark those records .seen.
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
#   · CC_NOTIFY_BIN · CC_DECIDE_BIN · CC_BACKLOG_BIN.  BSD+GNU portable, no eval, fail-loud.
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

new_pages=0 new_alarms=0 new_pushfailed=0 open_decisions=0 fired_defaults=0

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
  while IFS="$(printf '\t')" read -r tag did ddef; do
    [ "$tag" = "fired" ] || continue
    fired_defaults=$((fired_defaults + 1))
    if [ -n "$BACKLOG" ]; then
      "$BACKLOG" add --title "class-B default fired: $ddef" \
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
    --argjson od "$open_decisions" --argjson fd "$fired_defaults" --argjson extra "$extra" \
    '{ts:$ts,tool:"autonomy-sweep",disposition:$disp,new_pages:$np,new_alarms:$na,
      new_pushfailed:$npf,open_decisions:$od,fired_defaults:$fd} + $extra' \
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
[ "$fired_defaults" -gt 0 ] && summary="$summary ${fired_defaults} class-B default(s) fired→backlog,"
summary="${summary%,}"

DESK_TARGET=""
[ -f "$ROLES_DIR/desk" ] && DESK_TARGET="$(head -1 "$ROLES_DIR/desk" 2>/dev/null | tr -d '[:space:]')"

if [ -n "$DESK_TARGET" ] && [ -n "$NOTIFY" ]; then
  "$NOTIFY" "$DESK_TARGET" "$summary" >/dev/null 2>&1 || true
  # delivered (cc-notify's mailbox fallback makes this durable) → mark the surfaced records seen.
  printf '%s' "$SURFACED" | while IFS= read -r rec; do [ -n "$rec" ] && mark_seen "$rec"; done
  log_idl fired "$(jq -cn --arg notified "$DESK_TARGET" --arg summary "$summary" '{notified:$notified,summary:$summary}')"
else
  # No desk role (or no notify binary): fail LOUD and do NOT mark seen → the SAME records
  # re-surface next sweep once the role is set (a17 S-7: never let a wake drain to nobody).
  log_idl fired '{"notified":"no-desk-role","delivered":false}'
  echo "autonomy-sweep: NEW records but no desk role at $ROLES_DIR/desk — undelivered, will retry" >&2
fi
exit 0
