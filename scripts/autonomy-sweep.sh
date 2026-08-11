#!/bin/bash
# autonomy-sweep.sh — THE ONE pull-based consumer of the escalation write-only dirs (a18 SO-5,
# a17 S-7/D-2: the escalation lattice terminated NOWHERE — every layer wrote durable evidence into
# dirs with no reader). This is the single sweep that drains them and turns dead-letter records into
# a desk WAKE. launchd-runnable (a 300s tick) and supervisor-callable.
#
# Each run:
#   0. D4 author-death JOIN: teardown INTENT markers with no close OUTCOME whose pane is still
#      present become synthetic `handoff-orphan` records (see § D4 below).
#   1. Collect NEW records (deduped by a per-record .seen marker) from:
#        pages/                  supervisor page stamps
#        cc-announce-alarms/     announce-layer alarms
#        completion-push/        terminal-completion pushes whose verdict != "verified" (stuck)
#        decisions/*.json        OPEN class-B/C packets awaiting operator early-veto
#        handoff-alarms/         handoff-fire alarm records (D1) + this sweep's own D4 orphans
#   2. Run `cc-decide expire-sweep` — the sweep is the class-B default ACTUATOR: for each fired
#      default it appends a cc-backlog item (bounded + auditable), NEVER acting inline. A default
#      the PRODUCER declared `no-change` actuates nothing, so it is counted + summarised but gets
#      NO backlog item — an open item is cc-dispatch's fire predicate, and a worker must never be
#      spawned on "hold (no change without ruling)". The item is filed against the packet's own
#      declared `subject_project` when it has one, else this sweep's host project.
#   3. If anything NEW exists → walk the escalation LADDER (D2, `CC_SWEEP_LADDER=v2`), each rung
#      gated ONLY on its OWN precondition:
#        r1 desk push — ONE cc-notify to the desk ROLE (cc-roles/desk, resolved at send-time —
#           SO-1 role indirection), and ONLY when a role is wired. Marks .seen IF AND ONLY IF
#           delivery was actually PROVEN — cc-notify's `verdict=` token, never its exit code, and
#           never the mere existence of a role file (see § DELIVERY IS A VERDICT below; a dead uuid
#           is still non-empty). A role that is UNSET is a normal configuration, not a fault.
#        r2 OS banner — fires on new records REGARDLESS of role state (the whole point: with
#           cc-roles/ empty, r1 does not run at all and the banner used to be nested INSIDE it).
#           Damped per-record by `.bannered`; never marks .seen (a banner is not a proven read).
#        r3 loud stderr + IDL row whenever r1 did not REACH — the records are deliberately left
#           UNSEEN, so the next sweep re-surfaces them until something proves a reader.
#      `CC_SWEEP_LADDER=legacy` restores the pre-D2 nested logic byte-for-byte (the kill switch).
#   4. Write ONE {fired|abstained} IDL record (B-3: didn't-fire ≠ never-ran).
#   5. Age-compact: the .seen markers AND the seven write-only event dirs (see below). A record that
#      ages out with NO .seen marker is counted into an `expired-unread` IDL row + a ledger line
#      first — an unread escalation must never leave by a quiet unlink (D2 rung 4).
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
#   · CC_ROLES_DIR · CC_IDL · CC_SWEEP_SEEN_DIR (dual-keyed: hash + `<basename>.seen`)
#   · CC_SWEEP_SEEN_TTL_DAYS (default 7)
#   · CC_COMMS_ALARM_DIR · CC_PUSH_RECORDS_DIR · CC_TEARDOWN_RECORDS_DIR
#   · CC_INBOX_GUARD_STATE_DIR · CC_MAILBOX_DIR · CC_EVENT_TTL_DAYS (default 7)
#   · CC_NOTIFY_BIN · CC_DECIDE_BIN · CC_BACKLOG_BIN
#   · CC_SWEEP_OS_CHANNEL (auto|on|off) · CC_SWEEP_NOTIFY_TIMEOUT_S (default 25)
#   · CC_SWEEP_LADDER (v2|legacy, default v2 — `legacy` is the D2 kill switch)
#   D4: CC_HANDOFF_ALARM_DIR · CC_EXPIRED_LEDGER · CC_HANDOFF_JOIN (1|0)
#   · CC_HANDOFF_JOIN_DEADLINE_S (default 900) · CC_TEARDOWN_DIR · CC_CLOSE_ATTRIB_LOG · CC_IT2_BIN
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
LADDER="${CC_SWEEP_LADDER:-v2}"
# The six write-only event dirs this sweep now age-reaps (defaults match each PRODUCER's own env
# name, so a test that redirects the producer redirects the reaper with it).
COMMS_ALARM_DIR="${CC_COMMS_ALARM_DIR:-$HOME/.claude/autonomy/comms-alarms}"
PUSH_RECORDS_DIR="${CC_PUSH_RECORDS_DIR:-$HOME/.claude/autonomy/push-records}"
TEARDOWN_DIR="${CC_TEARDOWN_RECORDS_DIR:-$HOME/.claude/cc-teardown}"
INBOX_GUARD_DIR="${CC_INBOX_GUARD_STATE_DIR:-$HOME/.claude/autonomy/inbox-guard}"
MAILBOX_DIR="${CC_MAILBOX_DIR:-$HOME/.claude/mailbox}"
EVENT_TTL="${CC_EVENT_TTL_DAYS:-7}"
# D1 alarm records (handoff-fire) + this sweep's own D4 orphans — a SEVENTH event dir, collected
# like the others and reaped on the same horizon.
HANDOFF_ALARM_DIR="${CC_HANDOFF_ALARM_DIR:-$HOME/.claude/handoff-alarms}"
EXPIRED_LEDGER="${CC_EXPIRED_LEDGER:-$HOME/.claude/autonomy/expired-unread.jsonl}"
LADDER="${CC_SWEEP_LADDER:-v2}"
# D4 join inputs. JOIN_MARKER_DIR is deliberately NOT the TEARDOWN_DIR above: that one is
# `cc-teardown/` (push RECORDS, reaped); this is `watchdog/teardown/` (teardown INTENT markers,
# read-only here). Their env names match each PRODUCER's own, per the convention above.
JOIN_MARKER_DIR="${CC_TEARDOWN_DIR:-$HOME/.claude/watchdog/teardown}"
CLOSE_ATTRIB_LOG="${CC_CLOSE_ATTRIB_LOG:-$HOME/.claude/logs/close-attrib.jsonl}"
IT2_BIN="${CC_IT2_BIN:-$HOME/.claude/bin/it2}"
JOIN_DEADLINE_S="${CC_HANDOFF_JOIN_DEADLINE_S:-900}"

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

# ── THE SEEN KEY IS DUAL (2026-08-07) ────────────────────────────────────────────────────────────
# This sweep's original key is a HASH of the record's full PATH — collision-proof across dirs, but
# unreadable and ungreppable from anywhere else, so no other tool could ever ack a record or ask
# whether one had been read. D3's render and D5's `cc-escalations` both need that, and they can only
# name a record by its BASENAME. So every .seen decision is now written TWICE:
#   · the hash key  — unchanged, so the ~1,193 markers already on disk stay valid;
#   · `<record-basename>.seen` — the literal form the render/CLI side writes on ack and greps.
# The READ side takes EITHER (a record acked by the CLI carries only the literal key; one drained by
# this sweep before today carries only the hash). Caveat worth stating rather than hiding: the
# literal key is basename-scoped, so two records sharing a basename across two dirs share it. Live
# names are uuids, decision ids and alarm-<utc>-<pid>-<rand>, so the set is collision-free today —
# and the failure direction is a record read as ALREADY-SEEN, which the loud-expiry pass would then
# report as drained rather than lost.
# The two NEW marker kinds below (.bannered, .orphan-checked) have no legacy on disk, so they are
# single literal keys only — a second spelling of a key nobody has ever written buys nothing.
seen_key()  { printf '%s' "$1" | shasum -a 256 | cut -c1-32; }
seen_lit()  { printf '%s.seen' "$(basename "$1")"; }
is_new()    { [ ! -f "$SEEN_DIR/$(seen_key "$1")" ] && [ ! -f "$SEEN_DIR/$(seen_lit "$1")" ]; }
mark_seen() { : > "$SEEN_DIR/$(seen_key "$1")" 2>/dev/null || true
              : > "$SEEN_DIR/$(seen_lit "$1")" 2>/dev/null || true; }

# Accumulator of surfaced record paths (newline-separated; marked .seen only after a delivery).
SURFACED=""
add_surfaced() { SURFACED="${SURFACED}$1
"; }

new_pages=0 new_alarms=0 new_pushfailed=0 open_decisions=0 fired_defaults=0 fired_nochange=0
new_handoff_alarms=0 expired_unread=0
ha_classes=""   # newline-separated `class` values of the handoff-alarm records surfaced this run

# BOUNDED: every external call this sweep makes reaches the iTerm2/AppleEvent path, the proven
# machine-wide wedge class (2026-07-26: a bare `it2 session list --json` returned rc 124 with
# blocked forks piling up across ~110 sessions) — cc-notify below, and the D4 world probe. This runs
# from launchd on a 300 s tick; an unbounded call would wedge the sweep INSIDE the one act it exists
# to perform. rc 124 needs no branch of its own at the notify site — it is non-zero, so it takes the
# REFUSED path, records stay unseen, and the next sweep retries. That is exactly right for a cut
# send: we never learned whether it was enqueued, so re-surfacing is the safe error. (The D4 probe
# treats it as NO-DATA for the same reason — see § D4.)
TIMEOUT_BIN="$(command -v timeout 2>/dev/null || command -v gtimeout 2>/dev/null || true)"
sweep_bounded() { # <seconds> <cmd…> — rc 124 on a cut (timeout(1)'s contract)
  local s="$1"; shift
  if [ -z "$TIMEOUT_BIN" ] || [ ! -x "$TIMEOUT_BIN" ]; then "$@"; return $?; fi
  "$TIMEOUT_BIN" -k 5 "$s" "$@"
}
NOTIFY_TIMEOUT_S="${CC_SWEEP_NOTIFY_TIMEOUT_S:-25}"

log_idl() { # <disposition> <extra JSON OBJECT (optional, jq-built {…}; default {})>
  mkdir -p "$(dirname "$IDL")" 2>/dev/null || true
  local extra="${2:-}"; [ -n "$extra" ] || extra='{}'
  # jq-encode EVERY field (numerics via --argjson, strings via --arg): a value carrying a " /
  # backslash / newline then can NEVER emit a malformed IDL line — one malformed line aborts the
  # cc-audit four-zeros `jq -rs` slurp (reads as "no records" ⇒ silent D9/alarm false-GREEN).
  jq -cn --arg ts "$(now_iso)" --arg disp "$1" \
    --argjson np "$new_pages" --argjson na "$new_alarms" --argjson npf "$new_pushfailed" \
    --argjson od "$open_decisions" --argjson fd "$fired_defaults" \
    --argjson fnc "$fired_nochange" --argjson nha "$new_handoff_alarms" --argjson extra "$extra" \
    '{ts:$ts,tool:"autonomy-sweep",disposition:$disp,new_pages:$np,new_alarms:$na,
      new_pushfailed:$npf,open_decisions:$od,fired_defaults:$fd,
      fired_nochange:$fnc,new_handoff_alarms:$nha} + $extra' \
    >> "$IDL" 2>/dev/null || true
}

# Read one STRING field out of a single-line JSON record WITHOUT jq. The producers of these records
# are deliberately dependency-free (printf-JSON — D1's hf_alarm, write_teardown_marker), so a
# truncated or half-written record must degrade to "" here rather than abort the sweep.
json_field() { # <file> <key> → value | ""
  grep -o "\"$2\":\"[^\"]*\"" "$1" 2>/dev/null | head -1 | cut -d'"' -f4
}
file_mtime() { # <file> → epoch seconds | 0   (BSD `stat -f`, GNU `stat -c` — never-stuck-gate idiom)
  stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0
}

# ── 0. D4 — AUTHOR-DEATH JOIN ─────────────────────────────────────────────────────────────────────
# The one class no push and no watcher covers: the detached watcher ITSELF dies (reboot, box kill —
# detach() survives a group SIGKILL but not the machine). Nothing then closes the pane and nothing
# reports that nothing did. Joined here, at sweep cadence, from three independent readings:
#   INTENT  a teardown marker in watchdog/teardown/ (written pre-exit by the fire/shutdown paths)
#   OUTCOME a close-attrib row for the same id with a verdict starting `closed`
#   WORLD   the pane still present in a BOUNDED terminal listing
# Marker past the deadline + no outcome + pane STILL THERE ⇒ ONE synthetic `handoff-orphan` record.
# Pane gone + no row ⇒ benign (vendor close, or the fail-open attrib path) — NO alarm: an alarm that
# fires on the ordinary case carries the same zero bits as one that cannot fire (alarm-polarity law).
#
# THREE bounds, each measured against the live population (1,019 markers, 1,013 past the deadline,
# 2026-08-07) rather than assumed:
#  · ONE probe per SWEEP, cached — not one per marker. Per-marker probing would have been 1,013
#    calls × a 10 s bound inside a 300 s tick.
#  · EXACT-TOKEN match against the listing, never a substring. `it2 session list` returns short
#    numeric ids on this box (kitty-normalised: `240 7 263 …`), so a marker for pane `4` substring-
#    matches `240`. Measured on the live set: substring ⇒ 40 orphan records, all false;
#    exact-token ⇒ 0 (memory: pgrep-f-matches-agent-briefs — a blob match counts the wrong thing).
#  · JOIN_MAX_PER_TICK caps the work a single tick can take on, and the remainder is COUNTED into
#    the pass row (never a silent cap). The `.orphan-checked` marker makes each verdict once-ever,
#    so a backlog drains over ticks instead of spiking one.
# COVERAGE, stated honestly: the world probe adjudicates only the id space its listing returns. A
# marker from another terminal reads as ABSENT ⇒ benign ⇒ never alarms. That is fail-quiet by
# choice — a probe that cannot see a pane must not claim it is orphaned (probe-acting-on-absence).
JOIN_MAX_PER_TICK=100
join_world_out=""
join_world_rc=-1        # -1 = not probed yet this sweep
join_world_probe() {
  [ "$join_world_rc" -ne -1 ] && return 0
  join_world_out="$(sweep_bounded 10 "$IT2_BIN" session list 2>/dev/null)"
  join_world_rc=$?      # rc on its OWN line: `local x="$(…)"` would swallow it
  return 0
}
join_world_has() { # <pane> → 0 present · 1 absent. EXACT token equality, never a substring.
  local p="$1" line tok rc=1
  # `set -f` for the split: the tokens must come from the LISTING, and an unquoted `$line` also
  # PATHNAME-EXPANDS, so a listing carrying a `*` would invent tokens out of the filesystem. Restored
  # below — `break 2` rather than an early `return` is what guarantees the restore is reached.
  set -f
  while IFS= read -r line; do
    # shellcheck disable=SC2086  # word-splitting the line into tokens is the point
    for tok in $line; do [ "$tok" = "$p" ] && { rc=0; break 2; }; done
  done <<EOF
$join_world_out
EOF
  set +f
  return "$rc"
}
join_closed() { # <pane> → 0 iff a close OUTCOME row exists for this id
  [ -f "$CLOSE_ATTRIB_LOG" ] || return 1
  local rows
  # NO PIPE into grep -q here: under `set -o pipefail` an early-exiting grep SIGPIPEs its producer
  # and the pipeline reads 141 — i.e. FALSE on a match, inverting the probe (memory:
  # pipefail-inverts-early-exit-probe). Capture first, test the blob second.
  rows="$(grep -F "\"id_requested\":\"$1\"" "$CLOSE_ATTRIB_LOG" 2>/dev/null || true)"
  case "$rows" in *'"verdict":"closed'*) return 0 ;; esac
  return 1
}
run_handoff_join() {
  [ "${CC_HANDOFF_JOIN:-1}" = 1 ] || return 0
  [ -d "$JOIN_MARKER_DIR" ] || return 0
  local m base pane sid mode age rec nowe
  local examined=0 deferred=0 n_closed=0 n_nopane=0 n_gone=0 n_nodata=0 n_orphan=0
  nowe="$(date -u +%s)"
  while IFS= read -r m; do
    [ -n "$m" ] || continue
    base="$(basename "$m")"
    # once-ever guard: a verdict is reached at most one time per marker (except NO-DATA, which
    # deliberately leaves no marker so a blind tick retries rather than acquitting).
    [ -f "$SEEN_DIR/$base.orphan-checked" ] && continue
    age=$(( nowe - $(file_mtime "$m") ))
    [ "$age" -ge "$JOIN_DEADLINE_S" ] || continue      # not yet due — re-examined next tick
    if [ "$examined" -ge "$JOIN_MAX_PER_TICK" ]; then deferred=$((deferred + 1)); continue; fi
    examined=$((examined + 1))
    pane="$(json_field "$m" pane)"; sid="$(json_field "$m" sid)"; mode="$(json_field "$m" mode)"
    if [ -z "$pane" ]; then
      n_nopane=$((n_nopane + 1)); : > "$SEEN_DIR/$base.orphan-checked" 2>/dev/null || true; continue
    fi
    if join_closed "$pane"; then
      n_closed=$((n_closed + 1)); : > "$SEEN_DIR/$base.orphan-checked" 2>/dev/null || true; continue
    fi
    join_world_probe
    if [ "$join_world_rc" -ne 0 ]; then
      # NO-DATA (rc 124 cut, no binary, terminal not running): we learned NOTHING about the world.
      # Do NOT mark checked — a blind probe may neither alarm nor acquit.
      n_nodata=$((n_nodata + 1)); continue
    fi
    if join_world_has "$pane"; then
      mkdir -p "$HANDOFF_ALARM_DIR" 2>/dev/null || true
      rec="$HANDOFF_ALARM_DIR/alarm-$(date -u +%Y%m%dT%H%M%SZ)-$$-${RANDOM}.json"
      # FROZEN record shape, printf-JSON (no jq): the field values come from json_field, whose
      # pattern cannot return a `"`, so this cannot emit a malformed record.
      printf '{"kind":"handoff-alarm","class":"handoff-orphan","pane":"%s","sid":"%s","successor":"","detail":"teardown mode=%s armed %ss ago; no close outcome; pane still open","ts":"%s"}\n' \
        "$pane" "$sid" "$mode" "$age" "$(now_iso)" > "$rec" 2>/dev/null || true
      n_orphan=$((n_orphan + 1))
      log_idl join "$(jq -cn --arg marker "$base" --arg pane "$pane" --arg sid "$sid" \
        --arg mode "$mode" --argjson age "$age" --arg record "$rec" \
        '{join:"orphan",marker:$marker,pane:$pane,sid:$sid,mode:$mode,age_s:$age,record:$record}')"
    else
      n_gone=$((n_gone + 1))
    fi
    : > "$SEEN_DIR/$base.orphan-checked" 2>/dev/null || true
  done < <(find "$JOIN_MARKER_DIR" -maxdepth 1 -type f -name '*.json' 2>/dev/null)
  # ONE pass row, not one row per marker: the first tick against the live fleet adjudicates ~1,000
  # historical markers, and a row apiece would put 1,000 lines into the IDL that cc-audit slurps.
  # The ALARM keeps its own per-record row above; the benign verdicts are counted (alarm-polarity).
  if [ "$examined" -gt 0 ] || [ "$deferred" -gt 0 ]; then
    log_idl join "$(jq -cn --argjson ex "$examined" --argjson df "$deferred" \
      --argjson cl "$n_closed" --argjson np "$n_nopane" --argjson gn "$n_gone" \
      --argjson nd "$n_nodata" --argjson orp "$n_orphan" \
      '{join:"pass",examined:$ex,deferred:$df,closed:$cl,no_pane_key:$np,benign_gone:$gn,
        no_data:$nd,orphan:$orp}')"
  fi
}
run_handoff_join

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
# handoff-alarms: D1's capture-before-notify records, plus the D4 orphans raised above. Their CLASS
# is read with grep, not jq — these are written by a dependency-free producer in a detached watcher,
# so a half-written record must cost a class label, never the whole sweep.
for f in "$HANDOFF_ALARM_DIR"/*.json; do
  [ -f "$f" ] || continue
  is_new "$f" || continue
  new_handoff_alarms=$((new_handoff_alarms + 1)); add_surfaced "$f"
  hacls="$(json_field "$f" class)"
  ha_classes="${ha_classes}${hacls:-unknown}
"
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

total_new=$((new_pages + new_alarms + new_pushfailed + open_decisions + fired_defaults + new_handoff_alarms))

# ── LOUD EXPIRY (D2 rung 4) — an unread escalation may not leave by a quiet unlink ────────────────
# EVIDENCE law says a record ages out at CC_EVENT_TTL_DAYS once it can no longer be read as live.
# For a record that was NEVER read that is a silent loss, and silent loss is the entire class this
# sweep exists to end. Each source record past the horizon with NO .seen marker gets one ledger line
# + is counted into ONE `expired-unread` IDL row before the reaper touches it.
#
# ORDERING IS LOAD-BEARING: this runs BEFORE the .seen compaction below. The markers age out on the
# same horizon as the records they describe, so compacting first would delete the very evidence that
# a record HAD been read, and every properly-drained record would then be reported as expired-unread.
#
# Scanned dirs = the ones this sweep both SURFACES and REAPS. A dir that is reaped but never
# surfaced (comms-alarms/, push-records/, cc-teardown/) would report every record as unread forever,
# which is an alarm that cannot distinguish anything. completion-push/ is filtered by the same
# verdict predicate the collector uses — a `verified` record was never stuck, so it is not unread.
expire_scan() { # <dir> <store-label> [verdict-filtered:1]
  [ -d "$1" ] || return 0
  local rec cls v
  while IFS= read -r rec; do
    [ -n "$rec" ] || continue
    if [ "${3:-0}" = 1 ]; then
      v="$(jq -r '.verdict // ""' "$rec" 2>/dev/null || echo "")"
      case "$v" in verified) continue ;; esac
    fi
    is_new "$rec" || continue          # HAS a .seen marker ⇒ it was read ⇒ silent, as today
    expired_unread=$((expired_unread + 1))
    cls="$(json_field "$rec" class)"
    mkdir -p "$(dirname "$EXPIRED_LEDGER")" 2>/dev/null || true
    printf '{"ts":"%s","record":"%s","class":"%s","store":"%s"}\n' \
      "$(now_iso)" "$rec" "${cls:-unknown}" "$2" >> "$EXPIRED_LEDGER" 2>/dev/null || true
  done < <(find "$1" -maxdepth 1 -type f -mtime +"$EVENT_TTL" 2>/dev/null)
}
expire_scan "$HANDOFF_ALARM_DIR" handoff-alarms
expire_scan "$PAGES_DIR"         pages
expire_scan "$COMPLETION_DIR"    completion-push 1
# Emitted ONLY when it is non-zero: a row asserting "0 records were lost" on every 300 s tick would
# be the alarm that always fires, and reading one would tell the operator nothing (alarm-polarity).
[ "$expired_unread" -gt 0 ] && log_idl expired-unread \
  "$(jq -cn --argjson n "$expired_unread" --arg ledger "$EXPIRED_LEDGER" \
     '{kind:"expired-unread",n:$n,ledger:$ledger,
       why:"records aged past CC_EVENT_TTL_DAYS with no .seen marker — nobody ever read them"}')"

# ── age-compact the .seen markers ──
find "$SEEN_DIR" -type f -mtime +"$SEEN_TTL" -delete 2>/dev/null || true

# ── age-reap the write-only EVENT dirs (audit 03 fix 5; see the EVIDENCE law above) ──
# One horizon, seven paths, `-maxdepth 1 -type f` so a nested subdir is never walked into. Each dir
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
reap_event_dir "$HANDOFF_ALARM_DIR"  # D1 alarm records + D4 orphans (counted out loud above first)
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

# ── 2b. BACKLOG HEALTH — measured EVERY sweep, deliberately ABOVE the nothing-new early exit ──────
# The two backlog-health tools landed inert: a7bf7068 gave items a falsifier and 596b39a7 gave the
# duplicate-cluster shape a detector, and NOTHING invoked either. That is the exact failure this
# repo keeps rediscovering — a conclusion parked where no enforcing store reads it — committed by
# the change that was documenting it. This block is the caller.
#
# WHY ABOVE THE EARLY EXIT: `total_new -eq 0` is the COMMON case, and backlog rot is precisely the
# condition that produces no pages and no alarms while it accumulates. Wiring health below that gate
# would measure it only on sweeps that already had other news — i.e. never, on a quiet store that is
# quietly rotting.
#
# The trigger FILES rather than prints (its `--file` writes ONE condition-keyed row), so a crossed
# threshold reaches the operator through the item machinery that already exists — the readout, the
# ledger, dispatch — instead of a log line nobody opens. Nothing here alters $total_new or the exit
# below: a filed item surfaces on its own terms, on the NEXT sweep, which keeps this block free of
# any say in whether the desk is woken tonight.
#
# BEST-EFFORT, but never `|| true` on its own: swallowing the code would make a broken detector
# indistinguishable from a clean store (memory: claimed-outcome-vs-checked-outcome). Each rc is
# captured and journalled, so "the detector could not run" and "the store is healthy" stay apart.
# `set -e` is not in force here (line 44 is `set -uo pipefail`), so a non-zero cannot abort the sweep.
_sw="${BASH_SOURCE[0]}"
while [ -L "$_sw" ]; do
  _swd="$(cd "$(dirname "$_sw")" && pwd)"; _sw="$(readlink "$_sw")"
  case "$_sw" in /*) ;; *) _sw="$_swd/$_sw" ;; esac
done
_SWEEP_DIR="$(cd "$(dirname "$_sw")" && pwd)"
_trigger="$_SWEEP_DIR/backlog-consolidation-trigger.sh"
_ratchet="$_SWEEP_DIR/backlog-ratchet.sh"
# SELF-CONTAINED BOUND, not sweep_bounded(). That helper and its TIMEOUT_BIN are defined ~100 lines
# BELOW this point, and bash resolves a function only at call time — so calling it here would exit
# 127 "command not found". With no `set -e` that is SILENT, and rc 127 would have been journalled
# below as if it were the detector's own verdict: a broken caller reading exactly like a clean store.
# Caught before landing; the block is placed high on purpose (see above), so it brings its own bound.
_tmo="$(command -v timeout 2>/dev/null || command -v gtimeout 2>/dev/null || true)"
_bounded() { if [ -n "$_tmo" ] && [ -x "$_tmo" ]; then "$_tmo" -k 5 60 "$@"; else "$@"; fi; }
_trig_rc="skipped"; _rat_rc="skipped"
if [ -x "$_trigger" ]; then _bounded bash "$_trigger" --file >/dev/null 2>&1; _trig_rc=$?; fi
if [ -x "$_ratchet" ]; then _bounded bash "$_ratchet" --assert >/dev/null 2>&1; _rat_rc=$?; fi
log_idl backlog-health "$(jq -cn --arg t "$_trig_rc" --arg r "$_rat_rc" \
  '{consolidation_trigger_rc:$t, ratchet_rc:$r,
    note:"rc 0 = healthy or filed; 1 = ratchet saw coverage FALL; skipped = tool absent (not clean)"}')"

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
# handoff alarms carry a CLASS (strand-risk · husk-pane · recycle-dead · handoff-orphan) and the
# class is the whole point of the line — "3 handoff-alarm(s)" tells the kind, not the idea.
if [ "$new_handoff_alarms" -gt 0 ]; then
  ha_note=""
  while IFS= read -r ln; do
    [ -n "$ln" ] || continue
    ha_note="${ha_note}${ln}, "
  done < <(printf '%s' "$ha_classes" | sort | uniq -c | sed 's/^ *//')
  ha_note="${ha_note%, }"
  summary="$summary ${new_handoff_alarms} handoff-alarm(s)"
  [ -n "$ha_note" ] && summary="${summary} (${ha_note})"
  summary="${summary},"
fi
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
# ── r2 damping (D2) ───────────────────────────────────────────────────────────────────────────────
# A `.bannered` marker is DELIBERATELY a different store from `.seen`, and the distinction is the
# whole reason r2 can be safe: a banner proves only that something was PUT IN FRONT OF a human, never
# that one READ it, so it must not let a record be forgotten (that is the `mark_seen` contract, and
# spending it on an unprovable read is the data-loss regression task #120 fixed). `.bannered` bounds
# the POST instead — one banner per record, ever. So a permanently role-less fleet banners each new
# record exactly once and then goes quiet, while the records themselves stay surfaced until a real
# reader takes them. That is what dissolves the storm argument which kept r2 nested inside r1.
mark_surfaced_bannered() {
  printf '%s' "$SURFACED" | while IFS= read -r rec; do
    [ -n "$rec" ] && { : > "$SEEN_DIR/$(basename "$rec").bannered" 2>/dev/null || true; }
  done
}
count_unbannered() { # → how many surfaced records have never been on a banner
  local rec n=0
  while IFS= read -r rec; do
    [ -n "$rec" ] || continue
    [ -f "$SEEN_DIR/$(basename "$rec").bannered" ] && continue
    n=$((n + 1))
  done <<EOF
$SURFACED
EOF
  printf '%s' "$n"
}

DESK_TARGET=""
[ -f "$ROLES_DIR/desk" ] && DESK_TARGET="$(head -1 "$ROLES_DIR/desk" 2>/dev/null | tr -d '[:space:]')"

# ── ladder_legacy — the pre-D2 nested logic, preserved BYTE-FOR-BYTE as the kill switch. ──────────
# Kept whole rather than deleted so `CC_SWEEP_LADDER=legacy` is a genuine revert of THIS change and
# not a re-implementation of it from memory, and so the suite can pin both shapes against each other.
ladder_legacy() {
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
}

# ── ladder_v2 — THREE INDEPENDENT RUNGS ───────────────────────────────────────────────────────────
# The defect this replaces is STRUCTURAL, not a wording bug: the OS banner — the ONLY channel here
# with no liveness dependency — lived INSIDE the `[ -n "$DESK_TARGET" ]` arm. With cc-roles/ empty
# (the operator's deliberate state since 2026-08-07) that arm does not run at all, so the no-role
# branch logged one IDL row, retried forever, and NEVER bannered. Measured on this box before the
# fix: 1,009 records (316 pages · 426 alarms · 256 stuck completion pushes · 11 open decisions)
# re-collected and re-dropped every 300 s for four days, `notification-center` deliveries all-time
# ZERO, newest .seen marker frozen at the hour the desk role went away. A rung that fires only when a
# DIFFERENT rung's precondition holds is not a fallback — it is the same single point of failure,
# spelled twice. (memory: liveness-free-channel-never-gated-behind-liveness; the sibling STALE-desk
# case was fixed by task #120 and this ABSENT-desk case was left on the old branch — stale and absent
# are different states selecting different code paths, so a fix for one is not a fix for the other.)
ladder_v2() {
  local reached=0 notified_as notify_out notify_rc notify_verdict unbannered

  # ── r1 · DESK PUSH (accelerator) — runs ONLY when a role is wired. Role-unset is a NORMAL
  # configuration here, never an error and never a fault to repair. ──
  if [ -n "$DESK_TARGET" ] && [ -n "$NOTIFY" ]; then
    notified_as="role:desk"
    # Address the ROLE, never the uuid read above: cc-notify re-reads cc-roles/desk at SEND time and
    # follows the `.forward` chain, so a desk recycled since this sweep started still gets the wake
    # (a18 SO-1). DESK_TARGET gates on "is a channel wired at all", which is exactly why it can
    # never be the delivery evidence. CAPTURE stderr — the `verdict=` token lives there, and the
    # exit code alone is NOT the outcome (measured 2026-07-31 against a dead pane:
    # `verdict=mailbox-only enqueued=1 reason=target-not-live unacked=997` at rc 0).
    notify_out="$(CC_ROLES_DIR="$ROLES_DIR" sweep_bounded "$NOTIFY_TIMEOUT_S" "$NOTIFY" --role desk "$summary" 2>&1)"
    notify_rc=$?
    notify_verdict="$(printf '%s' "$notify_out" | grep -oE 'verdict=[a-z-]+' | head -1 | cut -d= -f2)"
    : "${notify_verdict:=unreadable}"   # a verdict we cannot READ is a THIRD state, never success
    if [ "$notify_rc" -eq 0 ] && [ "$notify_verdict" = delivered ]; then
      reached=1
      mark_surfaced_seen
      log_idl fired "$(jq -cn --arg summary "$summary" --arg v "$notify_verdict" \
        '{notified:"role:desk",delivered:true,channel:"desk",verdict:$v,summary:$summary}')"
    fi
  else
    notified_as="no-desk-role"; notify_rc=-1; notify_verdict="no-role"
  fi
  [ "$reached" -eq 1 ] && return 0

  # ── r2 · OS BANNER — fires whenever r1 did not REACH, INCLUDING when no role exists at all.
  # Damped per-record by `.bannered`, so the storm argument that kept this off the REFUSED path no
  # longer binds: a permanently refusing transport re-surfaces the same records every 300 s, and
  # every one of them is already bannered, so no second post is possible. ──
  unbannered="$(count_unbannered)"
  if [ "$unbannered" -gt 0 ] && sweep_escalate_os "${total_new} new escalation record(s)" \
       "${unbannered} escalation record(s) nobody has read. ${summary}"; then
    mark_surfaced_bannered
    log_idl fired "$(jq -cn --arg summary "$summary" --argjson n "$unbannered" \
      '{notified:"os-banner",delivered:false,channel:"notification-center-advisory",bannered:$n,
        summary:$summary,
        why:"banner is not proof of read — records stay surfaced until something proves a reader"}')"
  fi

  # ── r3 · LOUD — always, when r1 did not REACH. The wake the operator did not get is itself an
  # incident record (a17 S-4), and the records are deliberately left UNSEEN. ──
  log_idl fired "$(jq -cn --arg summary "$summary" --arg v "$notify_verdict" --arg n "$notified_as" \
    --argjson rc "$notify_rc" \
    '{notified:$n,delivered:false,channel:"none",verdict:$v,notify_rc:$rc,summary:$summary,
      why:"nothing proved a reader — records left unseen, the next sweep re-surfaces them"}')"
  echo "autonomy-sweep: NEW records UNDELIVERED verdict=$notify_verdict rc=$notify_rc target=$notified_as — nothing proved a reader; records left unseen, will retry" >&2
}

case "$LADDER" in
  legacy) ladder_legacy ;;
  *)      ladder_v2 ;;
esac
exit 0
