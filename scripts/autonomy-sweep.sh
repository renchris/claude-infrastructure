#!/bin/bash
# autonomy-sweep.sh — THE ONE pull-based consumer of the escalation write-only dirs (a18 SO-5,
# a17 S-7/D-2: the escalation lattice terminated NOWHERE — every layer wrote durable evidence into
# dirs with no reader). This is the single sweep that drains them and turns dead-letter records into
# a desk WAKE. launchd-runnable (a 300s tick) and supervisor-callable.
#
# Each run:
#   0a. CLOUD RETURN: land finished cloud work FIRST — measured, this sweep is TERMed as garbage
#       at ~1400 s and never reached its lower half (see the placement note at that block).
#   0b. D4 author-death JOIN: teardown INTENT markers with no close OUTCOME whose pane is still
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
#
# 🚨 THE BARE-NAME LOOKUP BELOW IS NOT THE LATENT UNBOUNDED CALL IT HAS BEEN READ AS, AND THE
# REASON IS THAT "RUNS FROM LAUNCHD" NAMES A LAUNCHER, NOT AN ENVIRONMENT (measured 2026-08-30).
# The standing claim was: on the plist's own PATH neither `timeout` nor `gtimeout` resolves, so
# TIMEOUT_BIN goes empty and sweep_bounded() falls through to the UNBOUNDED arm at the `-z` guard
# below — inside the very sweep whose header (just above) calls an unbounded call the proven
# machine-wide wedge class. REFUTED. com.chrisren.autonomy-sweep.plist does not hand this script
# launchd's minimal PATH; its ProgramArguments interpose `/bin/zsh -lc`, a LOGIN shell, which
# sources /etc/zprofile (path_helper) and ~/.zprofile BEFORE this line ever runs — and
# ~/.zprofile:1 is `eval "$(/opt/homebrew/bin/brew shellenv)"`, which puts /opt/homebrew/bin on
# the PATH. Measured by extracting THIS LINE from this file and eval'ing it under
# `env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin /bin/zsh -lc`: TIMEOUT_BIN=/opt/homebrew/bin/timeout,
# `-x` true, and the resolved binary answers 124 on a 1 s bound over a 5 s sleep (timeout(1)'s own
# cut code). BOTH bare names resolve; `gtimeout` is /opt/homebrew/bin/gtimeout. A MUTE CONTROL —
# the same extraction with both names rewritten to names that exist nowhere — reads EMPTY, so
# "non-empty" is a verdict this harness can fail to reach.
# ⚠️ THE HAZARD IS REAL BUT ITS TRIGGER IS NOT PATH MINIMALISM: it is ~/.zprofile:1 going away.
# Nothing here announces that, and the fallthrough is SILENT when it does. Say that, rather than
# the size-shaped claim it replaces.
# 🚨 AND THE INSTRUMENT LESSON, WHICH IS WHY THE CLAIM SURVIVED: grepping ~/.zprofile for `PATH`
# finds three lines and MISSES the one that decides, because `eval "$(brew shellenv)"` sets PATH
# without the token PATH occurring. A check keyed on the NAME of the thing cannot see a setter
# that never spells it. (The companion site is `_tmo` — at :517, NOT the :505 previously cited.)
TIMEOUT_BIN="$(command -v timeout 2>/dev/null || command -v gtimeout 2>/dev/null || true)"
sweep_bounded() { # <seconds> <cmd…> — rc 124 on a cut (timeout(1)'s contract)
  local s="$1"; shift
  # The `-z` arm below is the fallthrough named above: reachable only if the login PATH stops
  # carrying either binary, NOT because launchd's own PATH is minimal. Measured non-empty here.
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
file_mtime() { # <file> → epoch seconds | 0   (BSD `stat -f`, GNU `stat -c`)
  # 🚨 VALIDATE, never chain on the exit code alone. `stat -f %m <file> || stat -c %Y <file>` looks
  # like the portable idiom and is not one: GNU `stat -f` means "file system status", so on Linux it
  # reads `%m` as a FILENAME, writes the real file's filesystem block to STDOUT, and *then* exits 1.
  # The fallback runs, its epoch is appended to that block, and the caller's `$(( now - $(…) ))`
  # dies with `File: unbound variable` — nine of this file's own suite's cases, on every Linux
  # lander, for a helper that is correct on the box it ships to. A dialect probe must therefore test
  # the OUTPUT, not the status. GNU first because BSD `stat` has no `-c` at all, so it cannot
  # half-succeed the way `-f` does here.
  local m
  m="$(/usr/bin/stat -c %Y "$1" 2>/dev/null)"
  case "$m" in ''|*[!0-9]*) m="$(/usr/bin/stat -f %m "$1" 2>/dev/null)" ;; esac
  case "$m" in ''|*[!0-9]*) m=0 ;; esac
  printf '%s' "$m"
}

# ── HOISTED HELPERS — §0a below is now the highest block that needs them ─────────────────────────
# These were defined at §2b, which used to be the highest block with an external call. §0a is now
# higher and needs them for the identical reason §2b gave: sweep_bounded() and its TIMEOUT_BIN are
# defined ~500 lines BELOW here, and bash resolves a function only at CALL time, so invoking it up
# here would exit 127 "command not found" — and with `set -e` not in force (line 44 is
# `set -uo pipefail`) that is SILENT, journalled as if it were the callee's own verdict. A broken
# caller would read exactly like a clean fleet. So the high blocks bring their own bound.
_sw="${BASH_SOURCE[0]}"
while [ -L "$_sw" ]; do
  _swd="$(cd "$(dirname "$_sw")" && pwd)"; _sw="$(readlink "$_sw")"
  case "$_sw" in /*) ;; *) _sw="$_swd/$_sw" ;; esac
done
_SWEEP_DIR="$(cd "$(dirname "$_sw")" && pwd)"
# Same bare-name lookup as TIMEOUT_BIN's, and the same refutation applies verbatim — measured
# 2026-08-30 by eval'ing THIS line under the environment the plist actually builds: non-empty,
# /opt/homebrew/bin/timeout. See the block above TIMEOUT_BIN for the measurement, the mute control
# and the reason the "launchd PATH is minimal" reading was wrong. This site has now been cited as
# :505 and as :547 — A LINE NUMBER IS A COORDINATE IN A FILE PEOPLE EDIT; re-grep `^_tmo=`.
_tmo="$(command -v timeout 2>/dev/null || command -v gtimeout 2>/dev/null || true)"
# 🚨 THE BOUND IS SIZED FOR THE BAND THIS ACTUALLY RUNS IN, NOT FOR THE BENCH (2026-08-12).
# The 60 s bound was chosen in a foreground shell. This sweep runs from launchd under
# `ProcessType: Background` + `Nice 5` — the Darwin background QoS band, live PRI 4, confined to the
# E-cores. Same work, same box, same minute, measured three ways:
#     foreground 17.5 s   ·   BACKGROUND 68.1 s   ·   utility 20.3 s
# So `--fold` overran a 60 s bound by ~8 s on EVERY sweep and returned rc 124 — 10 of 10 recorded
# runs carry `fold_rc:"124"` / `fold_conservation:"no-verdict"`. The consequence is not a slow probe,
# it is an UNREACHABLE FLIP CRITERION: the §2b caller says to switch `--fold` to `--fold --apply`
# "when fold_conservation has read `ok` across a run of sweeps", and run to completion the fold
# reports `conservation=ok · 19 groups seen · 18 would fold · 0 ambiguous` — the criterion is already
# satisfied and no instrument on this box could observe it.
# (MEMORY: bound-must-fit-the-band-not-the-bench, and cap-whose-population-is-empty — the GREEN
# state did not exist.)
#
# Two changes; the first is the load-bearing one. Run these probes at `utility` instead of inheriting
# Background — the band every other actuator here already moved to
# (launchd/com.claude.postland-verify.plist:62). That is NOT a promotion to foreground: it lifts the
# E-core confinement and nothing else, so the sweep still yields to the operator's work. The bound
# then goes to 180 s — 2.6× the measured background cost, 8.9× the measured utility cost — so it
# remains a real bound while fitting the worst band ever observed rather than the best.
_qos=""; [ -x /usr/sbin/taskpolicy ] && _qos=/usr/sbin/taskpolicy   # fail-open: no taskpolicy ⇒ plain exec
_bounded() {
  if [ -n "$_tmo" ] && [ -x "$_tmo" ]; then
    ${_qos:+$_qos -c utility} "$_tmo" -k 5 "${CC_SWEEP_BOUND_S:-180}" "$@"
  else
    ${_qos:+$_qos -c utility} "$@"
  fi
}

# ── 0a. CLOUD RETURN — FIRST, because a block this sweep never REACHES does nothing ──────────────
# 🚨 WHY THIS IS THE FIRST THING THE SWEEP DOES, AND IT IS A MEASUREMENT, NOT A PREFERENCE.
# This block was §2d — after the D4 join, the page/alarm collection, the expire-sweep actuator, the
# backlog-health probes and the config-parity check. Every one of those comments argues, correctly,
# for being ABOVE the nothing-new early exit. None of them noticed that being above that exit is
# worth nothing if control never arrives at all.
#
# Measured 2026-09-01 over the live IDL, window 01:12→05:17Z (~4 h ≈ 48 ticks at the 300 s cadence),
# filtering `tool=="autonomy-sweep"`:
#
#     join            6 rows          ← §0, the first block
#     backlog-health  0 rows          ← §2b
#     config-parity   0 rows          ← §2c
#     cloud-return    0 rows          ← THIS block, which is unconditional and logs even when it skips
#
# `log_idl cloud-return` below is UNCONDITIONAL — every path through here journals, including
# `skipped-not-deployed` — so zero rows cannot mean "it ran and had nothing to do". It means control
# never got here. Corroborated from the other side, in `~/.claude/logs/cc-reaper.log`:
# `autonomy-sweep.sh` is that log's single largest subject at 719 TERM rows, collected as
# `orphan-bash` at ages 1362-2063 s. So the sweep is started every 300 s, runs for ~25-35 minutes,
# is killed as garbage long before its lower half, and has been for weeks.
#
# THAT MAKES ORDER THE FIX, not a tuning knob. Run at t≈0 s this block completes inside its own
# 900 s bound with ~450 s of margin against the EARLIEST kill ever recorded (1362 s); run at §2d it
# was reached about once in 48 ticks (docs/plans/DRAIN_CIRCUIT_2026-09-01.md §3b C). Nothing below
# depends on anything this block sets except the refusal router immediately after it, which travels
# with it, so the move is order-only.
#
# WHY NOT INSTEAD WHITELIST THE SWEEP IN cc-reaper, which is the apparently-obvious fix: the reaper
# is currently this job's ONLY watchdog. launchd does not stack a second instance of a running job,
# so a sweep that hangs stops the cadence entirely, and today the TERM at ~1400 s is what lets the
# next tick start. Exempting it would convert a periodic job into a permanently wedged one — a
# strictly worse failure, and unlike this reordering it is not order-only. The sweep's own runtime
# is a real defect and it is FILED rather than fixed here (see the close), because fixing it means
# giving the sweep a self-bound, which is a different change with a different blast radius.
#
# ── everything below this line is the §2d rationale, unchanged, and still true ────────────────────
# A cloud session finishing has no way to reach this box: no pane, no pid, no transcript, and the
# VM has no route home except the git remote it cloned from. So SOMETHING local has to notice, land
# the result and wake the originator — and it cannot be the originator, because a goal-armed session
# may not hold a backgrounded watcher at all (Claude Code skips /goal evaluation while any
# non-terminal background Bash exists, and hooks/validate-bash.sh denies the park outright). This
# job is loaded, runs every 300 s, and is not a session, which is exactly the shape that gap needs.
#
# ABOVE THE nothing-new EARLY EXIT, and now above everything else, for a reason that only sharpened:
# a finished cloud session produces NO page and NO alarm — it is silent by construction — so wiring
# the return below that gate would run it only on sweeps that already had other news, i.e. never on
# the quiet fleet where the work is actually sitting.
#
# 🚨 THE BOUND MUST FIT A LAND, AND 240 s DID NOT. This shipped at 240 s "to stay under the 300 s
# cadence", which sounded disciplined and was exactly backwards: `ship-land` runs the full gate and
# takes minutes (592 s worst case on record), so the bound cut a healthy land at 240 s and the
# return path filed the SIGTERM as a gate refusal — a bound smaller than what it bounds can only
# convict (memory: exoneration-bound-must-fit-what-it-bounds). It is now 900 s, sized to the thing
# it actually bounds. Overlap is not the hazard the old comment imagined: launchd does not stack a
# second instance of a running job, and the pass is single-flight (lock, exit 4) and idempotent, so
# a long land simply means fewer sweeps while it runs. The return path also now abstains on
# 124/137/143 rather than convicting, so even a cut leaves no false artifact.
#
# 🚨 AND THE PASS MUST FIT THE BOUND, WHICH IS THE OTHER HALF AND WAS MISSING (2026-09-01).
# A bound that fits one land is still useless if the pass cannot reach its first land. Timed live:
# `cc-cloud list --json --state` cost 210 s over 583 declarations, `poll` a second walk of the same
# shape, `handle()` a 0.409 s control-plane verify per returnable session, and the Background QoS
# band taxes all of it ×1.47 — ~675 s of the 900 s consumed as FIXED cost, before one land. And it
# was a COST CURVE, not a constant: the store grows 20-80 declarations a day and nothing ever
# removed one, so any bound sized today expires within the week. `--limit` (with a persisted cursor,
# newest-first) plus cc-cloud's new `--only` scoping makes the fixed cost O(the working set) instead
# of O(every declaration ever created). The deferral is JOURNALLED by the callee, never silent — a
# bounded pass that says nothing about what it skipped reads exactly like a pass that covered
# everything.
#
# rc is CAPTURED, never `|| true`: 0 = the pass completed, 4 = another pass held the lock (normal,
# not a fault), 124 = the bound cut a land mid-flight (the next tick resumes it), anything else is a
# broken rail — and collapsing those into one would make a dead return path read exactly like a
# quiet one, which is the failure this whole block exists to end.
#
# 🚨 ONLY THE DEPLOYED COPY MAY ACT, and this guard was bought at full price. Every other block here
# is a pure read, so running this script from a checkout has always been harmless. This one LANDS
# BRANCHES, MARKS BACKLOG ITEMS DONE AND SPENDS QUOTA — and `tests/autonomy-sweep.bats` executes the
# real sweep once per test, while `postland-verify` runs that suite from a throwaway worktree of the
# landed tree. Measured 2026-08-11, minutes after the wiring landed: FOUR concurrent
# `cloud-return --sweep` passes out of `~/.claude/autonomy/postland/wt-run-54668/`, acting on the
# operator's live declaration store, racing each other for the backlog ledger (one `done` won, the
# others were refused) and re-pinging the originator on every pass.
# The invocation PATH is the discriminator, and it is exact: launchd runs
# `~/.claude/scripts/autonomy-sweep.sh` (the deployed symlink), while a suite or a verifier worktree
# runs the checkout's own path. `$0` is read UNRESOLVED for exactly this reason — resolving it would
# follow the deployed symlink back into the checkout and erase the only difference there is.
# A skipped call is LOGGED with its reason, never silent: "not the deployed copy" and "the tool is
# absent" are different facts, and neither is "the fleet is quiet".
_cloudret="$_SWEEP_DIR/cloud-return.sh"
_cloudret_rc="skipped"
# THE ONE PLACE THIS NUMBER LIVES. It bounds the `timeout` below AND is exported to the child so it
# can pace itself against the same figure; the child derives its single-flight lock TTL from it too.
# It is deliberately NOT raised to make lands fit — this pass shares a 300 s launchd tick with the
# rest of the sweep, so a longer bound makes it a worse neighbour. The repair is the child stopping
# in time, not the caller waiting longer.
_cloudret_bound="${CC_SWEEP_RETURN_BOUND_S:-900}"
case "$_cloudret_bound" in ''|*[!0-9]*) _cloudret_bound=900 ;; esac
_cc_cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"; _cc_cfg="${_cc_cfg%/}"
# 🚨 EXACT PATH, NOT A PREFIX — and the prefix form was defeated by the very harness it was written
# to exclude. Caught in the act 2026-08-17T07:56Z:
#   RUNNING: /Users/chrisren/.claude/autonomy/postland/wt-run-61088/scripts/cloud-return.sh
# holding the live `.return.lock` and sweeping the operator's real declaration store. postland-verify
# mints its throwaway worktrees UNDER the config dir (`$_cc_cfg/autonomy/postland/wt-run-XXXXX/`), so
# a verifier copy's `$0` matches `"$_cc_cfg"/*` exactly as well as the deployed copy's does. The
# discriminator could not discriminate: EVERY postland run of this suite has been landing branches,
# marking backlog rows done and spending quota against live state — which is the same incident the
# comment above records from 2026-08-11 (four concurrent passes out of `wt-run-54668`), never
# actually closed, because the guard that closed it tested a prefix that contains its own harness
# (memory: guard-refusal-fires-on-its-own-harness).
# Two live symptoms were downstream of this and are now explained: the refusal artifacts whose land
# failed on `mkstemp … postland-run.VRdnYH/…` (a verifier's private TMPDIR, reaped when its run
# ended — fixed on the other side in cloud-reconcile too), and the absence of any `cloud-return` row
# in the sweep's own IDL journal while `return.jsonl` filled up: the launchd sweep was not the writer.
# There is exactly ONE deployed path and it is nameable, so name it. `$0` stays UNRESOLVED for the
# reason above — resolving it follows the deployed symlink into the checkout and erases the only
# difference there is.
_cloudret_deployed=0
[ "$0" = "$_cc_cfg/scripts/autonomy-sweep.sh" ] && _cloudret_deployed=1
if [ "$_cloudret_deployed" != 1 ]; then
  _cloudret_rc="skipped-not-deployed"
elif [ -x "$_cloudret" ]; then
  # 🚨 THE BOUND IS A VALUE THIS CALLER OWNS, AND THE CHILD IS TOLD IT.
  # `--limit` is a COUNT; this `timeout` is a DEADLINE. W3 landed the count, it went live, and the
  # pass was STILL SIGKILLed on every tick afterwards (`cloud_return_rc`: 137 at 02:40, 03:17,
  # 04:12, 05:11 and 05:51 on 2026-09-02) — because no count reconciles with a deadline when one
  # taken session can fall through to a full `ship-land` gate measured in minutes. The child now
  # enforces the deadline itself, stopping before it STARTS a unit it cannot afford, which needs it
  # to know the number. Exporting it is the whole point: hardcoding 900 on both sides would put one
  # fact in two places that cannot check each other, and the first change to this bound would leave
  # the child confidently pacing against a budget nobody applies any more.
  # The UNBOUNDED arm exports NOTHING. No `timeout` means no deadline, and a child pacing itself
  # against a killer that does not exist would defer real work for no reason.
  if [ -n "$_tmo" ] && [ -x "$_tmo" ]; then
    CC_RETURN_BOUND_S="$_cloudret_bound" "$_tmo" -k 10 "$_cloudret_bound" bash "$_cloudret" --sweep --limit "${CC_SWEEP_RETURN_LIMIT:-25}" >/dev/null 2>&1
  else bash "$_cloudret" --sweep --limit "${CC_SWEEP_RETURN_LIMIT:-25}" >/dev/null 2>&1; fi
  _cloudret_rc=$?
  # 🚨 THE KILLER CLEANS UP AFTER ITSELF. `timeout -k 10 900` escalates to SIGKILL, and the callee's
  # `trap … EXIT INT TERM` cannot run on one — so a cut pass leaves its single-flight lock directory
  # behind by construction. The callee now reaps a dead holder itself (pid liveness + a TTL sized to
  # this bound), and that is the primary repair; this is the second, independent one, and it belongs
  # HERE because this is the only party that KNOWS a kill happened. rc 137/143 is exactly that
  # knowledge — the caller observing its own child's death signal — and acting on it costs the next
  # tick nothing instead of making it re-derive the fact from a timestamp.
  # It is deliberately narrow: only on 137/143, only the lock this call's child could have held.
  # A lock reaped on any other rc — including 124, where the `-k` grace may still be running the
  # child's own trap — would be a caller stealing from a pass that is still alive.
  case "$_cloudret_rc" in
    137|143)
      _retlock="${CC_CLOUD_STATE:-$_cc_cfg/autonomy/cloud}/.return.lock"
      [ -d "$_retlock" ] && rm -rf "$_retlock" 2>/dev/null
      ;;
  esac
fi
log_idl cloud-return "$(jq -cn --arg c "$_cloudret_rc" \
  '{cloud_return_rc:$c,
    note:"0 = pass completed (per-session outcomes in the cloud return ledger; the pass-scope row records how many of the pending set it took and how many it deferred, and a `pass-deadline` row — a SEPARATE fact — records a pass that stopped starting work because this caller bound it in time, so an early stop can never read as full coverage); 4 = another pass held the lock; 124 = the bound cut the pass, next tick resumes (the return path itself abstains on a cut land rather than filing a refusal); 137/143 = the bound SIGKILLed it and this caller cleared the stranded single-flight lock; skipped = tool absent (NOT clean); skipped-not-deployed = a checkout/suite copy, which may never land, mark done or spend quota"}')"

# ── the REFUSAL LOOP (W3) — immediately after the return pass, and under ITS OWN guard ────────────
# The return pass above is what WRITES `<id>.land-refused`, so routing in the same tick closes the
# circuit at the earliest moment it can be closed: a refusal filed at 12:00 reaches the VM at 12:00
# rather than at 12:05. It is a separate call rather than a step inside cloud-return on purpose —
# detecting a refusal and answering one are different jobs with different blast radii, and the
# return path must stay able to run on a box where nothing may be sent off-box.
#
# 🚨 THE SAME DEPLOYED-COPY DISCRIMINATOR, FOR A STRICTER REASON. cloud-return lands branches and
# marks items done; this SPENDS QUOTA ON A REMOTE MACHINE and hands it a brief it will act on. Four
# concurrent suite copies of the return sweep have already been measured acting on the operator's
# live store (2026-08-11); the same four copies here would have sent four identical refusal briefs
# to a real VM. `$0` is read UNRESOLVED for the reason recorded above — resolving it follows the
# deployed symlink back into the checkout and erases the only difference there is.
# The router is single-flight and idempotent per refusal (keyed on the artifact's own content), so
# a long land simply means fewer routing passes, never a double-send.
_cloudrfz="$_SWEEP_DIR/cloud-refusal-route.sh"
_cloudrfz_rc="skipped"
if [ "$_cloudret_deployed" != 1 ]; then
  _cloudrfz_rc="skipped-not-deployed"
elif [ -x "$_cloudrfz" ]; then
  if [ -n "$_tmo" ] && [ -x "$_tmo" ]; then "$_tmo" -k 10 180 bash "$_cloudrfz" --sweep >/dev/null 2>&1
  else bash "$_cloudrfz" --sweep >/dev/null 2>&1; fi
  _cloudrfz_rc=$?
fi
log_idl cloud-refusal-route "$(jq -cn --arg c "$_cloudrfz_rc" \
  '{cloud_refusal_rc:$c,
    note:"0 = pass completed (per-refusal outcomes in the refusal-route ledger); 4 = another pass held the lock; 124 = the bound cut the pass, next tick resumes (a refusal is idempotent per artifact, so nothing is double-sent); skipped = tool absent (NOT clean); skipped-not-deployed = a checkout/suite copy, which may never send off-box"}')"

# ── the RETIREMENT ARM (W3 A) — the pile's terminal third, on the return cadence ──────────────────
# The return sweep examines a WORKING SET, and the working set was never shrinking. Measured
# 2026-09-04 (docs/research/backlog-zero-2026-09-04/cloud-lane.md §2, §3A): 547 managed declarations,
# 543 pending, +23.5/day in against 1.3 returns/day out — a ~400-day drain horizon over a cursor
# that rotates in ~1.4 days. But 183 of those rows have NO BRANCH ON ORIGIN AT ALL and a further
# ~22% of the branches that do exist are already content-on-trunk: neither can ever produce a
# return, and both were re-read on every rotation forever. `cc-cloud gc` cannot reach them (it
# archives declarations that are ALREADY retired and retires none itself), and
# `scripts/branch-prune-landed.sh` — which deletes exactly the landed branches — has had ZERO
# CALLERS since it was written on 2026-08-19. Both tools existed; nothing ran them.
#
# 🚨 UNDER THE SAME DEPLOYED-COPY GATE, AND FOR THE STRICTER OF THE TWO REASONS. The pruner DELETES
# REMOTE BRANCHES. A suite copy or a postland verifier worktree running this would delete the
# operator's real refs — the 2026-08-11 incident (four concurrent `cloud-return --sweep` passes out
# of `wt-run-54668`) with a worse blast radius. It shares `_cloudret_deployed`, which is an EXACT
# path test for the reason recorded above: the prefix form it replaced admitted its own verifier.
#
# THE PRUNER IS SAFE BY CONSTRUCTION AND THE SWEEP DOES NOT WEAKEN IT. It deletes only branches
# whose every commit is patch-equivalent on the trunk (`git cherry`, never ancestry), holds anything
# younger than CC_PRUNE_MIN_AGE_H, and records every sha before deleting so each deletion is
# restorable with one `git push`. The two things this caller adds are a manifest path OUTSIDE the
# checkout (the default writes into `docs/research/`, and a daily untracked file in the shared
# checkout is a dirty tree every other session then has to reason about) and a bound.
#
# DRY-RUN ON THE FIRST TICK, APPLY AFTERWARDS. The first pass on a box writes its manifest and
# deletes nothing, so the very first thing that exists is the restore record for what the second
# pass will do — a reviewable list before an irreversible batch, keyed on a marker in the cloud
# state dir so a fresh store gets the same courtesy.
_cloudprune_rc="skipped"
_cloudretire_rc="skipped"
_cloudstate_d="${CC_CLOUD_STATE:-$_cc_cfg/autonomy/cloud}"
_prune="$_SWEEP_DIR/branch-prune-landed.sh"
_retire="$_SWEEP_DIR/cloud-retire-terminal.sh"
_prune_repo="${CC_SWEEP_PRUNE_REPO:-$HOME/Development/claude-infrastructure}"
_prune_bound="${CC_SWEEP_PRUNE_BOUND_S:-240}"
case "$_prune_bound" in ''|*[!0-9]*) _prune_bound=240 ;; esac
if [ "$_cloudret_deployed" != 1 ]; then
  _cloudprune_rc="skipped-not-deployed"; _cloudretire_rc="skipped-not-deployed"
else
  _prune_first="$_cloudstate_d/.prune.applied-once"
  # An ARRAY, not an unquoted string: the "apply" mode is the ABSENCE of a flag, and an empty
  # unquoted "$_prune_mode" only works by word-splitting — which shellcheck reads as a defect and
  # a later `set -f` would silently turn into a literal empty argument the pruner rejects (exit 2).
  _prune_flags=(--dry-run)
  _prune_mode=dry
  [ -f "$_prune_first" ] && { _prune_flags=(); _prune_mode=apply; }
  if [ -x "$_prune" ] && [ -d "$_prune_repo/.git" ]; then
    mkdir -p "$_cloudstate_d" 2>/dev/null
    _prune_manifest="$_cloudstate_d/branch-prune-manifest-$(date -u +%Y-%m-%d).tsv"
    if [ -n "$_tmo" ] && [ -x "$_tmo" ]; then
      ( cd "$_prune_repo" && "$_tmo" -k 10 "$_prune_bound" bash "$_prune" ${_prune_flags[@]+"${_prune_flags[@]}"} --manifest "$_prune_manifest" ) >/dev/null 2>&1
    else
      ( cd "$_prune_repo" && bash "$_prune" ${_prune_flags[@]+"${_prune_flags[@]}"} --manifest "$_prune_manifest" ) >/dev/null 2>&1
    fi
    _cloudprune_rc=$?
    # THE MARKER IS WRITTEN ONLY BY A DRY RUN THAT COMPLETED. A cut or a failed first pass leaves it
    # absent, so the next tick dry-runs again rather than promoting itself to a delete on the
    # strength of a pass that never finished (memory: claimed-outcome-vs-checked-outcome).
    if [ "$_prune_mode" = dry ] && [ "$_cloudprune_rc" = 0 ]; then
      printf 'first_dry_run_at=%s\nmanifest=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$_prune_manifest" >"$_prune_first" 2>/dev/null || true
    fi
  elif [ ! -x "$_prune" ]; then _cloudprune_rc="skipped-absent"
  else _cloudprune_rc="skipped-no-repo"
  fi

  # THE RETIRE PASS RUNS SECOND, and the order is load-bearing: the pruner fills each declaration's
  # path set BEFORE it deletes a branch (bin/cc-cloud, ORDERING note), so a branch it removed this
  # tick is already answerable as LANDED by the time this pass reads the head list and calls it
  # `gone`. Reversed, the retire would run against branches the prune is about to delete and learn
  # nothing new for another 300 s.
  if [ -x "$_retire" ]; then
    if [ -n "$_tmo" ] && [ -x "$_tmo" ]; then
      CLOUD_RETIRE_REPO="$_prune_repo" "$_tmo" -k 10 "${CC_SWEEP_RETIRE_BOUND_S:-180}" bash "$_retire" --max "${CC_SWEEP_RETIRE_MAX:-200}" >/dev/null 2>&1
    else
      CLOUD_RETIRE_REPO="$_prune_repo" bash "$_retire" --max "${CC_SWEEP_RETIRE_MAX:-200}" >/dev/null 2>&1
    fi
    _cloudretire_rc=$?
  else _cloudretire_rc="skipped-absent"
  fi
fi
log_idl cloud-retire "$(jq -cn --arg p "$_cloudprune_rc" --arg r "$_cloudretire_rc" \
  '{branch_prune_rc:$p, cloud_retire_rc:$r,
    note:"branch_prune_rc: 0 = pass completed (first tick is a DRY RUN that only writes the manifest; every later tick deletes, and only branches patch-equivalent on the trunk); 1 = at least one delete batch failed, see the manifest; 124/137 = the bound cut it, next tick resumes; skipped-absent = the tool is not deployed; skipped-no-repo = the pruner has no checkout to read; skipped-not-deployed = a checkout/suite copy, which may never delete a remote ref. cloud_retire_rc: 0 = pass completed; 69 = SENSOR FAILED (ls-remote unreadable, or a remote answering with ZERO heads) and NOTHING was retired — never read as an empty remote; 3 = cc-cloud or the repo is missing"}')"

# ── the THRASH RECOVERY ARM (W3 F) — the other built tool with zero callers ───────────────────────
# cc-backlog's reap rule B blocks an item after MAX_THRASH fast claim→reopen pairs, and cc-dispatch
# takes its claim BEFORE it fires and rolls it back whenever it cannot start — a refused fire, a
# brief that would not compose, a worktree that could not be provisioned. Those write the identical
# ledger shape while no worker has been anywhere near the item, so the machine's own self-release
# was recorded as evidence about the ITEM. `blocked` is the OPERATOR-ONLY state and cc-dispatch
# excludes it by construction, so every such block removed real work from the autonomous queue
# permanently: 228 items, 64% of everything blocked, 182 of them never having held a claim for even
# the 90 s window (measured 2026-08-07).
#
# `scripts/thrash-block-recover.sh` is the repair and has had ZERO CALLERS since it was written —
# `grep -rn` finds only comments in bin/cc-backlog. Live churn over the seven days to 2026-09-04:
# 251 block · 176 unblock · 228 claims over 23 distinct ids, a 7.5x reclaim per id.
#
# IT CONVERGES RATHER THAN OSCILLATING, which is why it can sit on a 300 s cadence. `cc-backlog`
# now writes `reopen --self-release` on the dispatcher's own rollback and reap skips those pairs, so
# the population this can act on is the HISTORICAL rows that cannot acquire the flag — a set that
# only shrinks. It also only ever touches an item whose LATEST event is a rule-B block authored by
# cc-backlog-reap: an operator block, a wedged-worker block and a done item are structurally out of
# reach, and an item it unblocks has an unblock as its latest event, so it is not re-acted on.
#
# UNDER THE SAME DEPLOYED-COPY GATE: this WRITES TO THE OPERATOR'S BACKLOG. A verifier worktree
# running it would unblock live rows, which is the 2026-08-11 incident in a different store.
_thrash="$_SWEEP_DIR/thrash-block-recover.sh"
_thrash_rc="skipped"
if [ "$_cloudret_deployed" != 1 ]; then
  _thrash_rc="skipped-not-deployed"
elif [ -x "$_thrash" ]; then
  if [ -n "$_tmo" ] && [ -x "$_tmo" ]; then
    "$_tmo" -k 10 "${CC_SWEEP_THRASH_BOUND_S:-180}" bash "$_thrash" --apply >/dev/null 2>&1
  else
    bash "$_thrash" --apply >/dev/null 2>&1
  fi
  _thrash_rc=$?
else
  _thrash_rc="skipped-absent"
fi
log_idl thrash-recover "$(jq -cn --arg c "$_thrash_rc" \
  '{thrash_recover_rc:$c,
    note:"0 = pass completed (per-item UNBLOCK lines in the pass output; a pass with nothing to recover is also 0); 1 = at least one unblock FAILED and the item is still blocked; 2 = the ledger is unreadable or cc-backlog is not executable; 3 = the RECOVER set exceeded --max, which is a REFUSAL and not a truncation — raise CC_RECOVER_MAX deliberately after reading the dry run; 124/137 = the bound cut it, next tick resumes; skipped-absent = the tool is not deployed; skipped-not-deployed = a checkout/suite copy, which may never write to the backlog"}')"

# ── 0b. D4 — AUTHOR-DEATH JOIN (was §0; §0a now precedes it — see the placement note there) ───────
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
_trigger="$_SWEEP_DIR/backlog-consolidation-trigger.sh"
_ratchet="$_SWEEP_DIR/backlog-ratchet.sh"
_grouping="$_SWEEP_DIR/backlog-grouping-sweep.sh"
# `_SWEEP_DIR`, `_tmo`, `_qos` and `_bounded()` are HOISTED to §0a, above the D4 join, and their
# rationale travelled with them — re-grep `^_tmo=`. They used to be defined here because this was
# the highest block that needed them; §0a is now higher and needs them for the same reason (a
# self-contained bound, because sweep_bounded() and TIMEOUT_BIN are still defined ~500 lines below
# and bash resolves a function only at call time, so calling it up there would exit 127 SILENTLY).
_trig_rc="skipped"; _rat_rc="skipped"; _fold_rc="skipped"; _fold_note="skipped"; _fold_groups=0
# `_fold_applied` defaults to "skipped", NOT to "ok" — the apply arm below runs only on a clean dry
# verdict, and a default of ok would report a write that never happened on every sweep that held back.
_fold_applied="skipped"; _fold_written=0; _fold_apply_rc="skipped"
if [ -x "$_trigger" ]; then _bounded bash "$_trigger" --file >/dev/null 2>&1; _trig_rc=$?; fi
if [ -x "$_ratchet" ]; then _bounded bash "$_ratchet" --assert >/dev/null 2>&1; _rat_rc=$?; fi

# ── THE FOLD CALLER (backlog db81f8b43c31) — DRY-RUN, deliberately ────────────────────────────────
# W3 shipped `--fold [--apply]` and NOTHING invoked it — the third instance of this wave's own defect
# inside one session: `cc-venue` had no caller (W1 wired it), the ratchet was inert (W0 fixed it),
# and the actuator that answers a duplicate pile had none either. W3 correctly FILED rather than
# editing a file it did not own. This is that caller.
#
# WHY DRY-RUN AND NOT `--apply`, even though a fold is append-only and asserts its own conservation.
# The advisory-first discipline W1's measurement vindicated binds harder here, because this arm
# WRITES to the operator's live ledger while `--file` and `--assert` above are pure reads. W1
# measured a 60% would-block rate nobody predicted; the equivalent unknown for the fold is how the
# key behaves over TIME — 18 groups / 46 rows / conservation=ok is ONE snapshot, and the store moves
# under it constantly. A bounded dry run every sweep produces exactly that series for the cost of a
# read.
#
# THE FLIP IS A MEASUREMENT, NOT A DATE: when `fold_conservation` has read `ok` across a run of
# sweeps and `fold_groups` is stable rather than drifting, change `--fold` to `--fold --apply` here.
# `conservation=FAILED` must NEVER be flipped past — it means the key merged across a distinction,
# which is precisely the nine-stranded-worktrees defect W3 found in R6's proposed key.
#
# ── FLIPPED 2026-08-12 (W2, backlog ce1e9d1adab8), AND THE CRITERION IS NOW ENFORCED PER SWEEP ────
# The criterion above was satisfied and no instrument could observe it: the bound was sized in the
# foreground (17.5 s) while this sweep runs in Darwin's Background band (68.1 s), so `--fold` returned
# rc 124 on 10 of 10 recorded runs and `fold_conservation` read `no-verdict` every time. W0 resized
# it; measured after: 5 consecutive dry runs, `conservation=ok` on all five, 19 groups seen / 18 would
# fold / 0 ambiguous, byte-identical across the series. That is the series the flip asked for.
#
# It is implemented as DRY-THEN-APPLY rather than as a bare `--apply`, which costs one extra bounded
# read (~26 s measured) and buys the thing a one-time human flip cannot: **"never flip past a FAILED"
# stops being a rule someone has to remember.** The apply arm runs only when THIS sweep's own dry run
# reported `ok`, so a key that starts merging across a distinction disarms the writer on the very
# sweep that notices, with no marker file and no memory of past runs. A flip enforced by a comment is
# a flip that survives exactly until the next reader (memory: conclusion-must-reach-the-enforcing-store).
#
# THE VERDICT IS PARSED, NOT INFERRED FROM rc: an exit code cannot separate "nothing to fold" from
# "the store moved under the read", and collapsing those is a defect this repo has already shipped
# once (MEMORY.md: claimed-outcome-vs-checked-outcome). `no-verdict` is its own state so a silently
# broken trigger can never read as a clean store.
if [ -x "$_trigger" ]; then
  _fold_out="$(_bounded bash "$_trigger" --fold 2>/dev/null)"; _fold_rc=$?
  case "$_fold_out" in
    *conservation=FAILED*)  _fold_note="FAILED" ;;
    *conservation=unknown*) _fold_note="unknown" ;;
    *conservation=ok*)      _fold_note="ok" ;;
    *)                      _fold_note="no-verdict" ;;
  esac
  _fold_groups="$(printf '%s\n' "$_fold_out" | /usr/bin/grep -cE 'conservation=' 2>/dev/null)"
  case "${_fold_groups:-}" in ''|*[!0-9]*) _fold_groups=0 ;; esac
  # THE APPLY ARM — gated on THIS sweep's own dry verdict, so a FAILED disarms it immediately.
  # `unknown` also holds: it means the store moved under the read, and a writer that cannot tell its
  # own conservation from a sibling's write is a writer that should wait one sweep.
  if [ "$_fold_note" = "ok" ]; then
    _fold_apply_out="$(_bounded bash "$_trigger" --fold --apply 2>/dev/null)"; _fold_apply_rc=$?
    case "$_fold_apply_out" in
      *conservation=FAILED*)  _fold_applied="FAILED" ;;
      *conservation=unknown*) _fold_applied="unknown" ;;
      *conservation=ok*)      _fold_applied="ok" ;;
      *)                      _fold_applied="no-verdict" ;;
    esac
    _fold_written="$(printf '%s\n' "$_fold_apply_out" | /usr/bin/grep -cE 'verdict=linked' 2>/dev/null)"
    case "${_fold_written:-}" in ''|*[!0-9]*) _fold_written=0 ;; esac
  fi
fi

# ── 2b-i-b. THE BACKFILL CALLER (backlog 01edea637633, CONDITION_LEASE P6) — DRY-RUN, deliberately ─
# THE DEFECT THIS CLOSES IS THE PLAN'S OWN, ONE LAYER UP. `docs/plans/CONDITION_LEASE.md` P5 was
# filed because "`link` fires only when a human notices" — SEVEN link records in the ledger's whole
# history, six of them written inside eleven seconds by one hand-driven sweep on 2026-08-08. The
# remedy it shipped is `cc-backlog backfill`, which proposes the joins that sweep would have made.
# Measured on trunk 2026-08-13: `backfill` has ZERO callers — not here, not in a plist, not in a
# script. So the verb built to answer "nothing backfills" was itself backfilled by nothing, and the
# family key reaches the lease exactly as often as before: when a human happens to look. This is
# that caller (memory: feature-durability-mechanism-not-memory).
#
# WHY DRY-RUN, AND WHY THE FOLD'S FLIP CRITERION DOES NOT TRANSFER. The fold above writes unattended
# because it asserts CONSERVATION per run — a machine-checkable statement that the key did not merge
# across a distinction. `backfill` has no such assertion and cannot have one: its key is a scorer
# over a living corpus, and cmd_backfill's own header states the position this caller must not
# quietly overturn — "2 hits in 182 orphans on ONE day's ledger … is evidence for a review queue and
# not for an unattended writer". The asymmetry is what makes a wrong join expensive: `link` feeds
# claim guard (6), so a false join REFUSES a live worker onto work that is not duplicated, and
# nothing downstream reports the move. A missed join costs one duplicate dispatch; a wrong one
# strands real work with no alarm.
#
# THE FLIP IS A MEASUREMENT THIS ARM PRODUCES: when `backfill_proposed` has been small and STABLE
# across a run of sweeps, and the proposals it named were spot-checked as true joins, add `--apply`
# here. `backfill_note` must never read `no-verdict` on the sweep that flips — that state means the
# probe did not answer, not that the store is clean (memory: claimed-outcome-vs-checked-outcome).
#
# IT RUNS EVERY SWEEP because it is one `fold | jq` pass with no per-item forks: 0.43 s measured over
# a 2400-record / 600-item ledger, against the 106 s currency pass below that had to buy an interval
# gate. Sized the way the premise pass had to be — in the band, on a store the size of the real one
# (memory: bound-must-fit-the-band-not-the-bench).
_bf_rc="skipped"; _bf_note="skipped"; _bf_proposed=0; _bf_ambig=0
if [ -n "$BACKLOG" ] && [ -x "$BACKLOG" ]; then
  _bf_out="$(_bounded "$BACKLOG" backfill --json 2>/dev/null)"; _bf_rc=$?
  # PARSED, NEVER INFERRED FROM rc. `backfill` exits 0 on a clean store AND on a store it could not
  # read past a bound, so the exit code cannot separate "nothing to join" from "no answer" — the
  # exact conflation the fold arm above had to unpick. A count that does not parse is `no-verdict`.
  _bf_proposed="$(printf '%s' "$_bf_out" | jq '.proposed  | length' 2>/dev/null)"
  _bf_ambig="$(   printf '%s' "$_bf_out" | jq '.ambiguous | length' 2>/dev/null)"
  case "${_bf_proposed:-}" in
    ''|*[!0-9]*) _bf_proposed=0; _bf_note="no-verdict" ;;
    *)                           _bf_note="ok" ;;
  esac
  case "${_bf_ambig:-}" in ''|*[!0-9]*) _bf_ambig=0 ;; esac
fi

# ── 2b-i-c. THE VENUE RE-DERIVATION — A LABEL MAY NOT OUTLIVE THE RULE THAT MADE IT ──────────────
# THE COMMENT AT THE TOP OF THIS FILE WAS WRONG, AND THIS ARM IS THE CORRECTION. The fold caller
# above says "`cc-venue` had no caller (W1 wired it)". W1 wired the two callers it names in its own
# header — the WRITE-PATH labeller (`cc-backlog add` kicks a decide pass, which labels rows written
# inside a recent window) and the admission-time REPAIR (a void label is re-derived for the item
# about to be admitted). Both are correct and both are keyed on a row being NEW or being NEXT.
# Neither of them ever revisits a row that already carries a label and is not at the head of the
# queue, so nothing in the fleet re-decided a settled label. Measured 2026-08-24 by grep over
# `scripts/ hooks/ ~/Library/LaunchAgents`: `cc-venue run` had ZERO callers of any kind.
#
# WHAT THAT COST, measured the same day. `460211b83` landed the cross-repo eligibility arm at
# 2026-08-23T21:30Z. The six oldest rows in the cloud queue carried `venuePlan=cloud` annotations
# written 2026-08-11 → 2026-08-21 — before that rule existed — and `cc-eligible check` refuses all
# six today. `CLOUD_CEILING` is 6. So those six stale labels held every cloud slot, permanently, and
# the seven rows that CAN run off-box were admitted ZERO times in a day. The queue contradicted its
# own gate and nothing in the system was able to notice, because noticing is exactly the job of the
# pass that did not exist.
#
# IT APPLIES, AND THE ASYMMETRY IS WHY IT MAY. The backfill arm above is dry because a wrong join
# REFUSES a live worker with no alarm; the fold arm applies only behind a per-run conservation
# assertion. This arm needs neither, because the producer already fails closed in the only direction
# that is expensive: a wrong `local` costs nothing (the item claims locally, untouched), while a
# `cloud` label may only be written from a POSITIVE certification, and `bin/cc-venue` refuses to
# write one without `HistoryOracle.certify() == ok` (its own § THE GUARD). The dangerous half is
# already gated inside the actuator, so re-implementing a gate here would be a second predicate that
# can disagree with the first (memory: make-the-actuator-the-arbiter).
#
# IT RUNS ON THE CURRENCY PASS'S CADENCE, NOT EVERY SWEEP, for exactly the premise pass's reason:
# `decide()` re-runs cc-premise per item, so the cost tracks that pass rather than the 0.43 s folds
# beside it. Measured 2026-08-24 on the live store: 21 s for the dry decision over 318 open rows,
# and the WRITES dominate the rest at roughly one `cc-backlog venue` fold per changed row. A
# converged store therefore costs about a dry run; the expensive case is the first pass after a
# rule change, which is precisely the pass that must not be skipped.
#
# A TRUNCATED RUN IS SAFE AND IS NOT A FAILURE. Every row is decided and written independently, so
# rc 124 leaves a prefix of the store re-derived and the remainder exactly as it was — the next pass
# picks them up, and the cost gate inside `run --apply` skips the ones already current. That is why
# the bound is a real ceiling against a hung probe rather than a budget the pass must fit.
#
# THE VERDICT IS PARSED, NEVER INFERRED FROM rc, for the reason the fold arm states: `run` exits 0
# on a store it fully re-derived AND on one where every row was already current, and an exit code
# cannot separate those from a body it could not read. `no-verdict` is its own state.
_venue_rc="skipped"; _venue_note="not-due"; _venue_cloud=0; _venue_local=0
_venue_considered=0; _venue_writefail=0
_cc_venue="$(cd "$_SWEEP_DIR/.." 2>/dev/null && pwd)/bin/cc-venue"
_venue_stamp="${CC_VENUE_PASS_STAMP:-$HOME/.claude/autonomy/venue-pass.stamp}"
_venue_every="${CC_VENUE_PASS_EVERY_S:-21600}"
if [ -x "$_cc_venue" ] && command -v python3 >/dev/null 2>&1; then
  _venue_last=0
  # file_mtime, not the inline `stat -f … || stat -c …` this used to spell: that chain's first
  # operand SUCCEEDS in writing a filesystem block to stdout before failing on GNU, and the digit
  # validator below then folds the whole thing to 0 — which reads as "the stamp is ancient" and
  # fires an interval-gated pass on every tick. The validator was the right guard aimed one step too
  # late (see file_mtime).
  [ -f "$_venue_stamp" ] && _venue_last="$(file_mtime "$_venue_stamp")"
  case "${_venue_last:-}" in ''|*[!0-9]*) _venue_last=0 ;; esac
  _venue_now="$(date +%s)"
  if [ "$((_venue_now - _venue_last))" -ge "$_venue_every" ]; then
    # CLAIM THE STAMP BEFORE THE PASS RUNS, same as the premise pass: a run killed by the bound must
    # cost one interval, never re-fire on the next 5-minute tick into a load spiral.
    mkdir -p "$(dirname "$_venue_stamp")" 2>/dev/null; : > "$_venue_stamp"
    _venue_out="$(CC_SWEEP_BOUND_S="${CC_VENUE_PASS_BOUND_S:-900}" \
                  _bounded python3 "$_cc_venue" run --apply --json 2>/dev/null)"; _venue_rc=$?
    _venue_considered="$(printf '%s' "$_venue_out" | jq '.considered'          2>/dev/null)"
    _venue_cloud="$(     printf '%s' "$_venue_out" | jq '.counts.cloud // 0'   2>/dev/null)"
    _venue_local="$(     printf '%s' "$_venue_out" | jq '.counts.local // 0'   2>/dev/null)"
    _venue_writefail="$( printf '%s' "$_venue_out" | jq '.counts["write-failed"] // 0' 2>/dev/null)"
    case "${_venue_considered:-}" in
      ''|*[!0-9]*) _venue_considered=0
                   if [ "$_venue_rc" = 124 ]; then _venue_note="bound-exceeded"; else _venue_note="no-verdict"; fi ;;
      *)           if [ "${_venue_writefail:-0}" != 0 ]; then _venue_note="write-failed"; else _venue_note="ok"; fi ;;
    esac
    case "${_venue_cloud:-}"     in ''|*[!0-9]*) _venue_cloud=0     ;; esac
    case "${_venue_local:-}"     in ''|*[!0-9]*) _venue_local=0     ;; esac
    case "${_venue_writefail:-}" in ''|*[!0-9]*) _venue_writefail=0 ;; esac
  fi
fi

# ── 2b-ii. THE GROUPING SWEEP (W2, backlog ce1e9d1adab8) — the SEMANTIC half of the same question ──
# The fold above answers "are these rows the same SENTENCE about the same subject", which is narrow by
# design and must stay narrow: its own largest sha-keyed cluster of 14 was nine different stranded
# worktrees. It therefore cannot see the far larger population — rows that are DIFFERENT sentences
# about ONE effort. 424 of 553 live rows carried no master effort when this landed, each one a dispatch
# slot by default. `backlog-grouping-sweep.sh --file` measures that and files ONE condition-keyed row
# when it crosses the floor; it never writes links from here (see its header for the flip criterion).
_grp_rc="skipped"
if [ -x "$_grouping" ]; then _bounded bash "$_grouping" --file >/dev/null 2>&1; _grp_rc=$?; fi

# ── 2b-iii. THE CURRENCY PASS (W1, backlog b585e86ea4e4) — the probes actually RUN ────────────────
# `cc-premise sweep` and `cc-premise screen --all` were built, documented, and invoked by NOTHING on
# this box — the fourth instance of this wave's own defect. What made it worse than the other three:
# `run_falsifier` had exactly ONE call site, the CLAIM path, so a row nobody ever tried to claim had
# never had its probe executed at all. Measured 2026-08-12: 205 of 327 live rows had never been
# claimed. Re-validation was demand-driven, and 63% of the store generated no demand.
#
# ⚠️ IT DOES NOT RUN EVERY SWEEP, and the interval gate is the load-bearing part of this block. This
# script fires at StartInterval 300 — every 5 minutes — and a full pass costs 265.81 s MEASURED at
# utility over 567 rows (see the bound below). Running it every pass would spend a third of this
# box's sweep budget re-asking questions whose answers change on the scale of a landing, and would
# rewrite the stamp file 288 times a day for nothing. CC_PREMISE_PASS_EVERY_S defaults to 6 h, so
# "a currency verdict no older than one sweep" means one CURRENCY sweep — four a day.
#
# THE STAMP IS CLAIMED BEFORE THE PASS RUNS, NOT AFTER. Writing it after would let a pass that dies
# (or is killed by the bound) re-fire on the very next 5-minute tick, and a failing 265 s pass every
# 5 minutes is a self-inflicted load spiral. Claim-then-run means a broken pass costs one interval,
# not the box.
_prem_rc="skipped"; _prem_note="not-due"; _prem_closed=0; _prem_recorded=0
_prem_deferred=0; _prem_pending=0
_premise="$(cd "$_SWEEP_DIR/.." 2>/dev/null && pwd)/bin/cc-premise"
_prem_stamp="${CC_PREMISE_PASS_STAMP:-$HOME/.claude/autonomy/premise-pass.stamp}"
_prem_every="${CC_PREMISE_PASS_EVERY_S:-21600}"
if [ -x "$_premise" ] && command -v python3 >/dev/null 2>&1; then
  _prem_last=0
  [ -f "$_prem_stamp" ] && _prem_last="$(file_mtime "$_prem_stamp")"   # see the venue stamp above
  case "${_prem_last:-}" in ''|*[!0-9]*) _prem_last=0 ;; esac
  _prem_now="$(date +%s)"
  if [ "$((_prem_now - _prem_last))" -ge "$_prem_every" ]; then
    mkdir -p "$(dirname "$_prem_stamp")" 2>/dev/null; : > "$_prem_stamp"
    # 🚨 ITS OWN BOUND, NOT CC_SWEEP_BOUND_S. The shared 180 s bound above is sized for the `--file`
    # and `--assert` reads beside it; this pass is a different order of work entirely.
    #
    # RE-MEASURED 2026-08-16, IN THE BAND, AND THE OLD SIZING WAS STALE — 420 s came from a 106 s
    # measurement taken 2026-08-12 over 564 rows. Same command, same band, four days later:
    #     265.81 s real (user 122.94 · sys 42.63), read-only, 567 non-done rows, 141 probed
    # `/usr/bin/time -p taskpolicy -c utility python3 bin/cc-premise sweep --json`. The cost 2.5x'd in
    # four days, so the "4x the measured cost" headroom the old comment claimed had quietly become
    # ~1.6x — and the FULL production pass is strictly dearer than the read-only one measured here:
    # `--record` adds a batch write and `--close-falsified 5` adds up to 5 re-run probes at
    # FALSIFIER_TIMEOUT_S=20 s apiece. That lands the real pass at the bound, which is exactly what
    # the record shows: 5 production runs ever, 4 of them rc 124 bound-exceeded.
    #
    # WHERE THE TIME ACTUALLY GOES, measured rather than assumed, because it decides the shape of the
    # fix: the whole-store fold is NOT the floor. `cc-backlog list --all --json` over all 2,149 rows
    # runs in 3.30 s at utility. The other ~262 s is the 141 falsifier probes themselves, ~1.9 s each.
    # 1500 s is 5.6x the measured read-only cost and ~3.7x a full pass, on a job that fires every 6 h
    # at utility — so it is a real ceiling against a hung probe (the pathological tail is still
    # 141 x 20 s = ~47 min above it) and not a fixed cost the pass pays every time.
    #
    # THE DURABLE FIX IS SHARDING, AND IT HAS NOW LANDED (backlog d23f3a444984) — see `--limit`
    # below. Because the fixed overhead is only 3.3 s, capping the number of PROBES per pass caps
    # per-run cost outright, so this bound stops needing a re-measurement every time the store grows.
    # The thing that had to be got right first, and the reason the arm was filed rather than written
    # inline here: deferred rows must NOT fold into `unprobed`, which is the coverage ratchet's own
    # input — inflating it would file a coverage-regression row every pass, out of an alarm whose
    # subject never moved (memory: span-must-equal-subject). `sweep` now reports `deferred` as a
    # sibling of `unprobed`, and `--record` merges its shard instead of replacing the snapshot.
    # Re-measure rather than trusting the number above regardless: it has a four-day half-life
    # (memory: published-figure-decays-with-its-source).
    #
    # --record ALWAYS; --close-falsified CAPPED AT 5. A falsified row refuses every claim and nothing
    # closes it, so it is permanently live and permanently unfireable — 20 rows are in that state
    # today. The cap is what keeps a probe-corrupting tree change from emptying the store in one
    # pass, and cc-premise re-asks each row immediately before it closes it (see _close_falsified).
    #
    # --limit 150 IS DELIBERATELY ABOVE TODAY'S POPULATION (141 probe-capable rows on 2026-08-16),
    # so this commit changes NOTHING about today's pass — same rows, same cost, same currency
    # cadence — and starts binding the moment the store grows past it. That is the whole point: the
    # acute problem (rc 124 against a 420 s bound) was already fixed by re-sizing the bound to
    # 1500 s; the CHRONIC one is that a 2.5x-per-four-days probe count reaches 1500 s again in about
    # a week and every re-size buys one more week. A cap of 150 pins per-pass cost at ~285 s
    # permanently, and the growth lands on CURRENCY CADENCE instead — a full cycle stretching from
    # one pass (6 h) to two (12 h) to three (18 h) — which degrades gracefully and visibly
    # (`shard_pending` in the beat) rather than by killing the pass outright at the bound.
    #
    # RAISING THIS IS NOT FREE AND LOWERING IT IS NOT SAFE-BY-DEFAULT. Above ~700 the 1500 s bound
    # binds again; below the population the cycle lengthens, and a cycle longer than the interval
    # between the tree changes a probe answers about makes the stamp report currency it does not
    # have. Re-measure the per-probe cost before moving it in either direction.
    _prem_out="$(CC_SWEEP_BOUND_S="${CC_PREMISE_PASS_BOUND_S:-1500}" \
                 _bounded python3 "$_premise" sweep --json --record \
                   --limit "${CC_PREMISE_PASS_LIMIT:-150}" \
                   --close-falsified "${CC_PREMISE_CLOSE_CAP:-25}" 2>/dev/null)"; _prem_rc=$?
    # THE CAP WAS THE RETIREMENT RATE, AND AT 5 IT WAS BELOW THE INFLOW. Measured over the full
    # retained IDL window (2026-08-26 → 2026-09-04, 33 recorded ticks) this pass ran to completion
    # exactly ONCE — `premise_rows_validated: 43, premise_rows_closed: 5` — and 5 is the cap, not a
    # count: every completing pass closed everything it was allowed to and stopped. Net retirement
    # was 5 rows in 9 days against a pile of 619 live rows, so the arm was structurally incapable of
    # draining a store that grows by ~100 rows a week, however correct each individual verdict was.
    # 25 is sized to the pass, not to a preference: the cap only ever binds on rows whose own probe
    # RE-RAN and RE-ANSWERED "falsified" seconds earlier (bin/cc-premise:2829-2835 re-asks against a
    # store folded in the same call, and SKIPS anything claimed or already closed), so raising it
    # cannot close a row that a re-run would have spared — it can only stop discarding verdicts the
    # pass already paid for. The close itself is ~0.1 s of `cc-backlog done`; the pass's cost is its
    # 150 probes, which CC_PREMISE_PASS_LIMIT bounds and this does not touch.
    _prem_recorded="$(printf '%s' "$_prem_out" | jq -r '.validated_recorded // 0' 2>/dev/null)"
    _prem_closed="$(  printf '%s' "$_prem_out" | jq -r '.closed_falsified   // 0' 2>/dev/null)"
    _prem_note="$(    printf '%s' "$_prem_out" | jq -r '.validated_note     // "unparsed"' 2>/dev/null)"
    # THE SHARD'S TWO NUMBERS, journalled beside the pass's own. `deferred` is what the limit held
    # back and `shard_pending` is what the CYCLE still owes after this pass — read together they say
    # whether currency is keeping up, which is the axis the cap trades cost against. A pass reporting
    # a pending count that never reaches 0 is a cycle longer than the store's own churn, and that is
    # the reading that should move CC_PREMISE_PASS_LIMIT, not the wall-clock.
    _prem_deferred="$(printf '%s' "$_prem_out" | jq -r '.deferred       // 0' 2>/dev/null)"
    _prem_pending="$( printf '%s' "$_prem_out" | jq -r '.shard_pending  // 0' 2>/dev/null)"
    case "${_prem_recorded:-}" in ''|*[!0-9]*) _prem_recorded=0 ;; esac
    case "${_prem_closed:-}"   in ''|*[!0-9]*) _prem_closed=0   ;; esac
    case "${_prem_deferred:-}" in ''|*[!0-9]*) _prem_deferred=0 ;; esac
    case "${_prem_pending:-}"  in ''|*[!0-9]*) _prem_pending=0  ;; esac
    [ -n "$_prem_note" ] || _prem_note="unparsed"
    # rc 124 HERE MEANS THE BOUND WAS WRONG, and it is journalled as its own note rather than folded
    # into "the pass failed" — that collapse is exactly what hid the fold's unreachable criterion for
    # 10 runs. A reader seeing bound-exceeded knows to re-measure the band, not to debug cc-premise.
    [ "$_prem_rc" -eq 124 ] && _prem_note="bound-exceeded"
  fi
fi

# ── 2b-iv. THE RATCHET'S CONSUMER (W1 item 6) ─────────────────────────────────────────────────────
# `ratchet_rc` has been journalled since the ratchet was wired and read RED on every recorded run,
# and the only consequence was a JSON field. An alarm whose sole effect is to be written down is not
# an alarm; it is a log line that happens to be shaped like one.
#
# THE CONSEQUENCE IS A WORK ITEM, and specifically a CONDITION-KEYED one, which is what stops this
# from becoming the other failure mode. A fresh row per red sweep would file 288 rows a day into the
# very store whose growth the wave exists to reverse; `--condition` folds every later filing onto the
# same row (cc-backlog's own dedupe), so a standing regression is ONE standing row.
#
# AND IT CARRIES ITS OWN FALSIFIER, so it retires itself. The probe re-runs `--assert`: the moment
# coverage climbs back to the high-water the row's own re-check exits 0, the currency pass above sees
# `falsified`, and the closer retires it. That is the difference between an alarm with a consumer and
# an alarm with a pager — this one can go away without a human, and can only go away by the condition
# actually clearing.
#
# ONLY rc 1 FILES. rc 0 is healthy and `skipped` means the tool is absent, which is a DIFFERENT
# problem and must not be laundered into a coverage regression (memory:
# new-enum-member-falls-into-fail-closed-default).
#
# THE TITLE CARRIES NO LIVE NUMBER, deliberately. `cmd_add` returns early on a known id, so a
# re-file never UPDATES the row (W2 item 4 measured that exact freeze) — a title reading "coverage
# fell to 45.8%" would be frozen at whatever the first red sweep saw and would go on asserting it
# after the number moved. The standing figures live where they are recomputed: `backlog-ratchet.sh`
# itself, which the falsifier below runs.
#
# `--source backlog-ratchet`, NOT `autonomy-sweep`. The source names WHICH PRODUCER filed the row,
# and `autonomy-sweep` is already taken by the class-B decision-default filer higher up this script.
# Sharing it makes two unrelated producers indistinguishable in the store — and it broke that filer's
# own test on the first run, whose assertion selects `source=="autonomy-sweep"` and suddenly got two
# rows. The sweep is the CALLER of both; the ratchet is the PRODUCER of this one.
_rat_filed="n-a"
if [ "$_rat_rc" = "1" ] && [ -n "$BACKLOG" ] && [ -x "$BACKLOG" ]; then
  if _bounded "$BACKLOG" add \
       --project claude-infrastructure \
       --title "backlog falsifier coverage fell below its high-water mark — rows are being filed that cannot re-check themselves (run backlog-ratchet.sh for today's figures)" \
       --condition "backlog-ratchet-coverage-regression" \
       --source backlog-ratchet \
       --falsifier "bash '$_ratchet' --assert >/dev/null 2>&1" \
       >/dev/null 2>&1
  then _rat_filed="filed"; else _rat_filed="file-failed"; fi
fi

# ── 2b-v. THE DRAIN-CHAIN LIVENESS CHECK (BACKLOG_DRAIN_24_7 §6) ──────────────────────────────────
# THE INVARIANT THIS ACTUATES IS THE PLAN'S OWN ROOT CAUSE. §1.2, measured: the local drain ran nine
# recycles, recycle #9's goal cleared on an effort-scoped condition, and no recycle #10 ever fired.
# The chain stopped at 06:45Z and the only instrument that reported it was the operator, hours later.
# §6 says the chain's liveness is "checked by autonomy-sweep" — this is that check, and until it
# landed the invariant existed in a plan and in no script, test or plist on trunk.
#
# WHY IT LIVES HERE AND NOT IN A PLIST OF ITS OWN. The sweep is already the box's ONE pull-based
# consumer of things that would otherwise write into dirs with no reader, and a detector for "the
# drain is not running" that itself depends on a second standing job has just moved the question one
# level out. The 300 s tick is also the right cadence for a 24 h window: the alarm cannot be late by
# more than one sweep, and it cannot be early because the window is four hundred times the tick.
#
# `--file`, NOT `--assert`, for the same reason the grouping sweep beside it files: a dead chain is
# an UNATTENDED state by construction (06:45Z, nobody watching), so a verdict that only reaches a
# terminal reaches nobody. The row is condition-keyed (`local-drain-chain-dead`) so a chain dead for
# a week is ONE standing row, and it carries `--assert` as its own falsifier so the currency pass
# retires it the moment a recycle fires or a worker takes a lease — the detector for backlog inflow
# must not itself become a generator.
#
# COST: one `cc-backlog list --open --json` fold per sweep, the same order as the backfill arm above
# (0.43 s measured over a 2400-record ledger) and well under the 3.30 s the premise-pass note records
# for the whole-store `list --all` at utility. Bounded like every sibling, so a store that goes slow
# costs one arm and not the sweep.
_drain_rc="skipped"
_drain="$_SWEEP_DIR/drain-chain-assert.sh"
if [ -x "$_drain" ]; then _bounded bash "$_drain" --file >/dev/null 2>&1; _drain_rc=$?; fi

log_idl backlog-health "$(jq -cn --arg t "$_trig_rc" --arg r "$_rat_rc" \
  --arg f "$_fold_rc" --arg fc "$_fold_note" --arg fg "$_fold_groups" \
  --arg fa "$_fold_applied" --arg fw "$_fold_written" --arg g "$_grp_rc" \
  --arg br "$_bf_rc" --arg bn "$_bf_note" --arg bp "$_bf_proposed" --arg ba "$_bf_ambig" \
  --arg pr "$_prem_rc" --arg pn "$_prem_note" --arg pv "$_prem_recorded" \
  --arg pc "$_prem_closed" --arg pd "$_prem_deferred" --arg pp "$_prem_pending" \
  --arg rf "$_rat_filed" --arg dc "$_drain_rc" \
  --arg vr "$_venue_rc" --arg vn "$_venue_note" --arg vc "$_venue_considered" \
  --arg vcl "$_venue_cloud" --arg vlo "$_venue_local" --arg vwf "$_venue_writefail" \
  '{consolidation_trigger_rc:$t, ratchet_rc:$r, ratchet_filed:$rf, drain_chain_rc:$dc,
    fold_rc:$f, fold_conservation:$fc, fold_verdict_lines:($fg|tonumber),
    fold_applied:$fa, fold_links_written:($fw|tonumber), grouping_sweep_rc:$g,
    backfill_rc:$br, backfill_note:$bn, backfill_proposed:($bp|tonumber),
    backfill_ambiguous:($ba|tonumber),
    premise_pass_rc:$pr, premise_pass_note:$pn,
    premise_rows_validated:($pv|tonumber), premise_rows_closed:($pc|tonumber),
    premise_rows_deferred:($pd|tonumber), premise_shard_pending:($pp|tonumber),
    venue_pass_rc:$vr, venue_pass_note:$vn, venue_rows_considered:($vc|tonumber),
    venue_routed_cloud:($vcl|tonumber), venue_routed_local:($vlo|tonumber),
    venue_write_failed:($vwf|tonumber),
    note:"rc 0 = healthy or filed; 1 = ratchet saw coverage FALL; skipped = tool absent (not clean). consolidation_trigger_rc and ratchet_rc 2 = COULD NOT MEASURE, the engine (jq) is absent — those two guards were fail-OPEN until backlog 2366f99e04a7, the same defect the grouping sweep carried for its whole deployed life, and for the ratchet the fail-open was worse than a misreport: its --assert is the stored falsifier of the row it files at :803, and cc-premise reads exit 0 as THE CONDITION IS GONE, so an absent engine RETRACTED the coverage alarm rather than failing to measure it. The rc-1 consumer below is an exact match on 1 and so cannot launder a 2 into a coverage regression; the trigger files its own condition-keyed, send-damped row (backlog-consolidation-engine-absent) from --file, while the ratchet deliberately files nothing because its scheduled mode IS a probe. drain_chain_rc is the BACKLOG_DRAIN_24_7 §6 liveness check and its rc says only whether the CHECK ran (0 = it answered and filed if dead; skipped = no drain-chain-assert.sh on this box) — the VERDICT is never inferred from it, because the check is fail-open by construction and reports alive on an unreadable store, on zero live rows (the success state), and on any live lease. Read the verdict from `drain-chain-assert.sh --json` or from whether row condition=local-drain-chain-dead is open. ratchet_filed is the ratchet rc CONSUMER: a red assert now files ONE condition-keyed, self-falsifying row instead of only being written down here. The fold APPLIES, gated on its own dry verdict: fold_applied is skipped unless fold_conservation read ok this same sweep, so a FAILED or unknown key disarms the writer without anyone remembering to. grouping_sweep_rc 0 = under the ungrouped floor or filed; 2 = COULD NOT MEASURE, the engine (python3 / scripts/backlog-consolidation/group.py) is absent — that guard was fail-OPEN until backlog 70cc9f44040f, so this field read 0 on every tick of the entire deployed life of that mechanism while it folded nothing, and the sweep now files its own condition-keyed row (backlog-grouping-engine-absent, send-damped) rather than leaving the evidence in an rc nobody screens. A non-zero here has never aborted this sweep: no set -e, and the rc is captured rather than propagated. backfill_* is the CONDITION-LEASE family key (cc-backlog backfill), and it is a DRY RUN on purpose: it proposes joins a scorer found over a living corpus, and a wrong join feeds claim guard (6) and REFUSES a live worker onto work that is not duplicated. backfill_proposed is the depth of that review queue, backfill_ambiguous the rows that matched two groups and were deliberately not joined, and backfill_note no-verdict means the probe did not answer this sweep — never that the store is clean. Flip to --apply when proposed is small and stable across a run of sweeps and its named proposals were spot-checked. premise_pass_* is the CURRENCY pass and runs on its OWN cadence (CC_PREMISE_PASS_EVERY_S, default 6h) because it costs 265.81 s measured at utility over 141 probes (2026-08-16) while this sweep fires every 300 s: note not-due = the interval gate held it, bound-exceeded = rc 124 and the 1500 s bound needs re-measuring in the band, read-failed:<why> = the pass aborted fail-open on an unreadable store and SAID SO rather than exiting 0 with an unparseable body, ok = every live row carries a probe verdict against premise_pass sha. premise_rows_closed retires rows a probe just proved dead, which before had no exit at all: falsified refuses every claim and nothing closed them. premise_rows_deferred/premise_shard_pending are the SHARD (--limit, default 150): deferred is what this pass held back and shard_pending what the cycle still owes after it, so a pending count that never reaches 0 means the cycle is longer than the store\u0027s churn and the LIMIT wants raising — not the bound. Deferred rows are deliberately NOT folded into the sweep\u0027s unprobed count, which stays the coverage ratchet\u0027s input and means only \u0027no arm can speak for this row\u0027. venue_pass_* is the VENUE RE-DERIVATION (cc-venue run --apply) and it exists because a venue label could outlive the rule that made it: 460211b83 landed the cross-repo eligibility arm on 2026-08-23T21:30Z and the six oldest venuePlan=cloud rows had been labelled 08-11..08-21, so they held all six cloud slots against a gate that refuses them and the seven genuinely eligible rows were admitted ZERO times in a day. W1 wired cc-venue\u0027s WRITE-PATH and ADMISSION-REPAIR callers, both keyed on a row being NEW or NEXT; nothing re-decided a settled label until this arm, and `cc-venue run` had zero callers of any kind (grep over scripts/ hooks/ LaunchAgents, 2026-08-24). It APPLIES unattended, unlike the backfill arm beside it, because the producer already fails CLOSED in the expensive direction: a wrong `local` costs nothing (the item claims locally, untouched) while a `cloud` label may only be written from a positive certification cc-venue itself refuses to issue without an ok history horizon, so a second gate here could only disagree with the first. It runs on the currency pass\u0027s cadence (CC_VENUE_PASS_EVERY_S, default 6h) because decide() re-runs cc-premise per item: 21 s measured for the dry decision over 318 open rows on 2026-08-24, with the per-row `cc-backlog venue` writes dominating beyond that. venue_pass_note bound-exceeded = rc 124, which is SAFE and NOT a failure -- every row is decided and written independently, so a truncated pass leaves a prefix re-derived and the next pass finishes what it did not reach; no-verdict = the body did not parse, which is never the same as a clean store; write-failed = at least one label could not be written, and venue_write_failed carries the count."}')"

# ── 2c. CONFIG-DIR GUARDRAIL PARITY — same placement, same reason, a third inert tool ─────────────
# scripts/settings-drift-assert.sh has compared the 5 config dirs correctly since the day it landed
# and had ZERO callers for its entire life (measured 2026-08-11, backlog 4ce34a4f703c): absent from
# all five settings.json, and its only named invocation sat in docs/activation/wiring-all.sh, a
# bundle that was never run. Meanwhile the drift it names was real — .claude-next was missing the
# unattended-ask PERMISSION RAIL plus four other hooks. A correct detector nobody calls is
# indistinguishable from no detector, which is the third instance of that exact shape wired in from
# this one block.
#
# WHY HERE AND NOT IN nightly-regression: that job's plist is NOT loaded (`launchctl list` shows no
# com.claude.nightly-regression; its activation script is still in the rotting queue), so wiring the
# checker there would have moved it from one inert home to another while reading like a fix.
# autonomy-sweep runs every 300s under com.chrisren.autonomy-sweep, which IS loaded.
#
# ABOVE THE nothing-new EARLY EXIT, for the reason the block above states: config drift produces no
# pages and no alarms while it accumulates, so a quiet fleet is exactly when it must be measured.
#
# `--file`, not `--assert`: the verdict has to land in a store something already reads. That row is
# condition-keyed and carries its own falsifier, so repeated drifting sweeps update ONE item and it
# closes itself once the dirs agree — this block cannot become a per-sweep item generator.
#
# The rc is captured, never `|| true`: rc 1 (drift, filed) and rc 3 (could not compare) are different
# facts, and collapsing them would let a broken checker journal exactly like a clean fleet.
_drift="$_SWEEP_DIR/settings-drift-assert.sh"
_drift_rc="skipped"
if [ -x "$_drift" ]; then _bounded bash "$_drift" --file >/dev/null 2>&1; _drift_rc=$?; fi
log_idl config-parity "$(jq -cn --arg d "$_drift_rc" \
  '{settings_drift_rc:$d,
    note:"rc 0 = the 5 config dirs agree; 1 = drift, ONE condition-keyed item filed; 3 = could not compare (NOT clean); skipped = tool absent"}')"

# ── 2e. CUSTODY DEATHWATCH — the arm that runs when NOBODY IS HOME ────────────────────────────────
# The cloud return + refusal blocks (now §0a, hoisted to the top of the pass) only ever speak to an
# address the FIRE recorded. Measured 2026-08-23: 1055 of
# cloud-return's 1116 wake attempts resolved to "the declaration names no notify-back target —
# nothing to wake", because a launchd-dispatched fire has no ITERM_SESSION_ID and its cwd is `/`.
# So the news existed 1116 times and reached someone 61 times, and the 175 undischarged cloud debts
# sit in a shard keyed on `/` that no `--cwd .` consumer can see. Separately, a peer killed by
# SIGKILL runs no EXIT trap and no self-close, so the local lane's two discharge routes both miss it
# (panes 377 and 552 are the surviving proof).
#
# This pass closes both by reading the custody store STORE-WIDE and reporting gone/stale peers to an
# address that exists by construction — the originator's inbox when its pane is alive, else ONE
# aggregated `cc-backlog needs` row. It NEVER discharges a debt, so its worst failure is operator
# noise, never a debt closed over live work. Full rationale in the script header.
#
# It carries its OWN deployed-copy guard keyed the same way this file's is, so the call here is
# unconditional and a suite copy is inert on the far side rather than by omission here — one guard,
# in the file that does the writing.
_custdw="$_SWEEP_DIR/custody-deathwatch.sh"
_custdw_rc="skipped"
if [ -x "$_custdw" ]; then
  if [ -n "$_tmo" ] && [ -x "$_tmo" ]; then "$_tmo" -k 10 120 bash "$_custdw" --sweep >/dev/null 2>&1
  else bash "$_custdw" --sweep >/dev/null 2>&1; fi
  _custdw_rc=$?
fi
log_idl custody-deathwatch "$(jq -cn --arg c "$_custdw_rc" \
  '{custody_deathwatch_rc:$c,
    note:"0 = pass completed (per-peer verdicts in ~/.claude/autonomy/custody-deathwatch/deathwatch.jsonl, which also records whether each oracle could run); 124 = the bound cut the pass, next tick resumes (the pass is latched per marker, so nothing is double-reported); skipped = tool absent (NOT clean). A checkout copy self-reports skipped-not-deployed in its own ledger rather than here."}')"

# ── 2f. UNFIRED BRIEFS — a succession that was WRITTEN and never FIRED ────────────────────────────
# backlog 4a11a0ac850a: a lead announced a recycle, wrote the successor brief, and died before
# firing it. Nothing noticed, because the only artifact was a file in /tmp that looks exactly like
# one that WAS fired. scripts/unfired-brief-sweep.sh answers it exactly, now that every fire row
# carries `prompt_file`: a brief whose path appears in no row was never fired.
#
# THIS BLOCK IS THE WHOLE POINT OF THE DETECTOR EXISTING. The failure this repo keeps re-committing
# is the unscheduled watchdog — `wait-contract-lint.sh --sweep` is built, `--selftest` 13/13 GREEN,
# and has NO caller in launchd or in this file, so the flagship strand-detector has never fired in
# production (desk-audit p04 G-P4-2, still open today). Landing another detector without its caller
# would be that defect committed by the change that names it, which is exactly how 2b above got its
# comment. So the caller lands in the same diff as the tool.
#
# ABOVE THE nothing-new EARLY EXIT, for the same reason as 0a/2b/2c and most sharply of all: a lost
# succession is SILENT BY CONSTRUCTION. It produces no pane, no page, no alarm and no ledger row —
# that silence IS the failure — so wiring it below the gate would run it only on sweeps that already
# had other news, i.e. never on the quiet fleet where a dead chain is actually sitting.
#
# PURE READ, so no deployed-copy guard: unlike 0a it lands nothing, marks nothing and spends no
# quota — it stats files and greps a ledger. Running it from a checkout or a verifier worktree is
# harmless, which is the standing rule for every read-only block here.
#
# ALARM BUDGET, measured rather than assumed. The sweep is SELF-ARMING and reports `not-armed` until
# a real fire writes a `prompt_file` row, so it emits zero findings over the 98 briefs currently on
# disk instead of 98 false positives on its first tick. Steady-state it can only fire on a brief
# written inside the ledger's own retention window that no row names — an event that should be rare
# enough to read, and is the event itself rather than a proxy for it.
_unfired="$_SWEEP_DIR/unfired-brief-sweep.sh"
_unfired_json=""
if [ -x "$_unfired" ]; then
  # Bounded like every other probe here, and at `utility` so the Background band's E-core
  # confinement cannot turn a stat-and-grep into a rc-124 non-verdict (memory
  # bound-must-fit-the-band-not-the-bench).
  _unfired_json="$(_bounded bash "$_unfired" --json 2>/dev/null || true)"
fi
# An unparseable or empty result is reported as its own state. "the tool is absent", "the bound cut
# it" and "no briefs are lost" are three different facts, and collapsing them would make a broken
# rail read exactly like a clean fleet — the failure mode this whole section exists to end.
log_idl unfired-briefs "$(printf '%s' "${_unfired_json:-}" | jq -c \
  'if type=="object" then {unfired_verdict:(.verdict//"malformed"),
                           unfired_n:(.counts.unfired//0),
                           unfired_unknowable:(.counts.unknowable_pre_floor//0),
                           unfired_floor:(.floor//null),
                           findings:(.findings//[])}
   else {unfired_verdict:"no-output"} end' 2>/dev/null \
  || printf '{"unfired_verdict":"no-output"}')"

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
# desk IS being run), `on` forces the channel, `auto` (default) probes.
#
# THE BINARY IS RESOLVED ONCE, ABSOLUTELY, AND THROUGH A NAMED SEAM. This file runs from launchd,
# where the PATH is whatever the plist exports and a bare `osascript` is not reachable on it — the
# finding `unattended-path-lint` has carried against this line, and the reason it names
# `bin/cc-kitty-bin` / `bin/cc-claude-bin` as the precedents rather than "add an allowlist entry".
# The old spelling probed `command -v osascript` and posted with a second bare `osascript`, so the
# probe and the post could in principle resolve differently, and the no-channel branch was
# untestable: a suite cannot un-find /usr/bin/osascript through PATH, and stubbing the name is a
# test of the stub. CC_SWEEP_OSASCRIPT replaces that PATH stub with an explicit one — one name, one
# resolution, one override — which is what makes the branch reachable at all.
SWEEP_OSASCRIPT="${CC_SWEEP_OSASCRIPT:-/usr/bin/osascript}"
os_channel_available() {
  case "${CC_SWEEP_OS_CHANNEL:-auto}" in
    off) return 1 ;;
    on)  return 0 ;;
    *)   command -v "$SWEEP_OSASCRIPT" >/dev/null 2>&1 ;;
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
  sweep_bounded 10 "$SWEEP_OSASCRIPT" - "$1" "$2" >/dev/null 2>&1 <<'OSA' || return 1
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
