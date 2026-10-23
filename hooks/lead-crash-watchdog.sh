#!/bin/bash
# lead-crash-watchdog.sh — SessionStart hook that spawns a detached watchdog
# daemon per claude session. If the lead process dies while it has an active
# team, the watchdog:
#   1. Appends a shutdown_request envelope to each teammate inbox
#   2. Writes a CRASH_REPORT.md in the team dir
#   3. Fires a macOS notification + terminal bell
#
# This prevents the routines-v1 scenario from repeating: lead died mid-session,
# 3 teammates blocked on permission prompts, no recovery signal.
#
# Kill switch: export LEAD_CRASH_WATCHDOG_DISABLED=1
#
# Exit: always 0 (hook must never block session startup).

set -euo pipefail
# shellcheck disable=SC1091  # #! helpers run via their interpreter, not by path (kalloc leak; plan KALLOC_TRIGGER_ELIMINATION W4)
if [ -f "${BASH_SOURCE[0]%/*}/../scripts/lib/cc-run.sh" ]; then . "${BASH_SOURCE[0]%/*}/../scripts/lib/cc-run.sh"; else cc_argv() { CC_ARGV=("$1"); }; cc_run() { "$@"; }; fi

# ── THE ARM FILE IS READ HERE, NOT BY THE CALLER'S SHELL (backlog 159c2211b0f2) ──────────────────
# The operator's recorded arming lives in ~/.claude/autonomy/watchdog.env (LCW_ORPHAN_CLOSE=1). Until
# this block, only ~/.zshrc sourced it, so the arm reached a session launched from an interactive zsh
# and nothing else — a launchd job, a `claude -p` cron, any non-zsh provenance ran DISARMED while the
# file on disk said armed. Sourcing it here makes the file the single source of truth for every
# launch path. An explicit LCW_* value already in the environment WINS (a test pin, a one-off
# override): those are snapshotted before the source and restored after it. Fail-soft: a missing,
# unreadable or broken file leaves the environment as it was — this hook must never block startup.
# Seam: LCW_WATCHDOG_ENV (default $HOME/.claude/autonomy/watchdog.env; set-but-EMPTY disables).
if [ -n "${LCW_WATCHDOG_ENV+set}" ]; then _lcw_envf="$LCW_WATCHDOG_ENV"
else _lcw_envf="$HOME/.claude/autonomy/watchdog.env"; fi
if [ -n "$_lcw_envf" ] && [ -f "$_lcw_envf" ] && [ -r "$_lcw_envf" ]; then
  _lcw_pre="$(declare -px 2>/dev/null | grep -E '^declare -x LCW_[A-Za-z0-9_]*=' || true)"
  # shellcheck source=/dev/null
  . "$_lcw_envf" >/dev/null 2>&1 || true
  [ -n "$_lcw_pre" ] && eval "$_lcw_pre"
  unset _lcw_pre
fi
unset _lcw_envf

# Bound the OS-notification fork (machine-wide iTerm2/AppleEvent wedge, 2026-07-26). This one
# targets NotificationCenter rather than iTerm2, so it is not the root cause — but it is an
# AppleEvent fork inside an automated path, and an unbounded one turns a best-effort page into a
# stalled hook. Every call site here is already best-effort (`|| true`), so a cut costs at most
# one missed notification and never a wrong verdict. timeout(1) is resolved by ABSOLUTE PATH as
# well as PATH — hooks and launchd jobs run without Homebrew on PATH, where coreutils installs it.
# No timeout(1) ⇒ run unbounded rather than lose notifications entirely.
# Seams: LCW_OSA_TIMEOUT_S · LCW_OSA_TIMEOUT_BIN (set-but-EMPTY disables verbatim).
LCW_OSA_TIMEOUT_S="${LCW_OSA_TIMEOUT_S:-5}"
if [ -n "${LCW_OSA_TIMEOUT_BIN+set}" ]; then
  LCW_OSA_TB="${LCW_OSA_TIMEOUT_BIN}"
else
  LCW_OSA_TB=""
  for _c in "$(command -v timeout 2>/dev/null || true)" "$(command -v gtimeout 2>/dev/null || true)" \
            /opt/homebrew/bin/timeout /usr/local/bin/timeout \
            /opt/homebrew/bin/gtimeout /usr/local/bin/gtimeout; do
    [ -n "$_c" ] && [ -x "$_c" ] && { LCW_OSA_TB="$_c"; break; }
  done
fi
lcw_osa() {
  if [ -z "$LCW_OSA_TB" ] || [ ! -x "$LCW_OSA_TB" ]; then "$@"; return $?; fi
  "$LCW_OSA_TB" -k 3 "$LCW_OSA_TIMEOUT_S" "$@"
}

# lcw_bounded <secs> cmd… — run an external command under the timeout binary resolved above.
#
# WHY a second entry point rather than reusing lcw_osa: the DEATH path's calls need their OWN
# budgets, and they are not best-effort pages. A notification can be cut at 5s and cost one missed
# banner; the transcript reader that recovers an assignee's only surviving report cannot. Sharing
# one constant would either strangle the harvest or leave the notification unbounded.
#
# The death path is the one place in this file where an unbounded call is unrecoverable: the daemon
# is already the last thing running for a session that just died, nothing supervises IT, and a hang
# here strands every teammate the crash handler exists to notify. Two of its calls read data whose
# size is not ours to bound — a transcript "runs to hundreds of MB" (last_assistant_text) and
# cc-teardown drives AppleEvents into iTerm2, the documented machine-wide wedge surface.
# Same degradation contract as lcw_osa: no timeout(1) ⇒ run unbounded rather than lose the call.
lcw_bounded() {
  local s="$1"; shift
  declare -F cc_argv >/dev/null && { cc_argv "$1"; shift; set -- "${CC_ARGV[@]}" "$@"; }   # #! via its interpreter (cc-run.sh)
  if [ -z "$LCW_OSA_TB" ] || [ ! -x "$LCW_OSA_TB" ]; then "$@"; return $?; fi
  "$LCW_OSA_TB" -k 3 "$s" "$@"
}


if [[ "${LEAD_CRASH_WATCHDOG_DISABLED:-0}" == "1" ]]; then
  exit 0
fi

readonly WATCHDOG_DIR="$HOME/.claude/watchdog"
readonly LOG_FILE="$HOME/.claude/logs/lead-crash-watchdog.log"

# ── THE DEATH PAGE (2026-08-25, RECYCLE_SIGTERM_INCIDENT). This watchdog had the RIGHT verdict —
# `class=CRASH cause=external-sigterm` for session d075006b, 25 s after the kill — and the operator
# was never told. Two independent reasons, and the fix has to close BOTH:
#
#   1. The only alert on this path is an `osascript display notification`, which is transient: it
#      lands in Notification Center, is dismissed by the next one, and is gone by the time anybody
#      reads the pane. It also carries eight characters of sid and nothing about what was LOST.
#   2. The structured branch that does more — CRASH_REPORT.md, shutdown_requests, the bell on
#      /dev/tty — is reached only when the dead lead OWNED A TEAM. A lead running a Dynamic
#      Workflow owns no team (workflow agents are in-process subagents, not team members), so the
#      loudest case on this box takes the `no teams affected` early-return and stops.
#
# A SIGTERM'd `claude` also leaves its parent shell alive, so the pane renders EXACTLY like a
# deliberate `/exit` — same "Resume this session with:" line, same prompt. There is no pixel on
# screen that distinguishes a killed session from a closed one. The operator cannot be expected to
# infer the difference; something has to say it.
#
# So: page a LIVE SIBLING through the fleet's own durable transport (`cc-notify`), which appends to
# an inbox the target drains at its next safe boundary. Durable beats transient — an inbox line
# survives until it is read, and `--role` re-resolves the address at SEND time so a recycled pane
# is followed rather than paged into the void (cc-notify's own guidance for automated pagers).
#
# 🚨 POLARITY — this fires on CRASH ONLY, never on RECYCLE. An alarm that fires at every session
# close carries exactly as many bits as one that never fires (MEMORY.md alarm-polarity). Deliberate
# recycles are the overwhelming majority of deaths in claude-crashes.jsonl (28 of 32 rows on the
# incident day); paging on those would train the operator to ignore the channel that matters.
#
# FAIL-OPEN, BOUNDED, AND NEVER THE CAUSE OF A SECOND FAILURE: the pager is bounded by timeout(1),
# every step is `|| true`, and a missing/failing pager degrades to a log line — the pre-fix
# behaviour — rather than delaying or breaking the death handler it hangs off.
#
# THE DESTINATION IS cc-desk-page, NOT `cc-notify --role desk` (2026-09-30, husk-panes root cause 6).
# The bare role page failed rc=3 on EVERY death: no ~/.claude/cc-roles/desk file exists, so cc-notify
# had no address and the page reached nobody. cc-desk-page tries the desk rung and, when no live desk
# takes it, the operator's Notification Center / phone — a ladder whose last rung needs no role file.
# Exit 0 = delivered on some channel. An explicit CC_DEATH_PAGER override whose basename is cc-notify
# keeps the old `--role` call shape (see surface_death); any other pager gets cc-desk-page's.
# Seams: CC_DEATH_PAGE=0 (kill switch) · CC_DEATH_PAGER (stub the transport) · CC_DEATH_PAGE_ROLE.
CC_DEATH_PAGE="${CC_DEATH_PAGE:-1}"
CC_DEATH_PAGE_ROLE="${CC_DEATH_PAGE_ROLE:-desk}"
CC_DEATH_PAGER="${CC_DEATH_PAGER:-$HOME/.claude/bin/cc-desk-page}"
CC_DEATH_PAGE_TIMEOUT_S="${CC_DEATH_PAGE_TIMEOUT_S:-10}"

mkdir -p "$WATCHDOG_DIR" "$(dirname "$LOG_FILE")" 2>/dev/null || true

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE" 2>/dev/null || true
}

# ── death classification helpers (top-level so the daemon subshell inherits them,
#    and so `lead-crash-watchdog.sh --classify <sid>` is unit-testable) ───────────
# A pid death with the pid-file still present is EITHER a deliberate self-recycle
# (handoff-fire --recycle / self-close kills the pane with no clean SessionEnd) OR a
# genuine crash (jetsam OOM, abort, external kill). kill -0 cannot tell them apart, so
# thousands of "LEAD CRASH" lines accumulated conflating both. This separates them from
# disk truth and, on a real crash, attributes the cause. Bias: unsure ⇒ CRASH (a hidden
# crash is worse than a spurious alert).
find_transcript() {
  local sid="$1" base hit
  # account roots are env-overridable for tests (default: the 4 live account dirs)
  local bases="${CC_ACCOUNT_BASES:-$HOME/.claude $HOME/.claude-secondary $HOME/.claude-tertiary $HOME/.claude-quaternary}"
  # shellcheck disable=SC2086  # intentional word-split over space-separated bases
  for base in $bases; do
    # shellcheck disable=SC2012  # glob-ls + head -1 is deliberate (fixed sid-keyed pattern, no exotic names)
    hit=$(ls "$base"/projects/*/"$sid"*.jsonl 2>/dev/null | head -1)
    [[ -n "$hit" ]] && { printf '%s' "$hit"; return 0; }
  done
  return 1
}

# ── close-record join (bin/cc-close-attrib) ─────────────────────────────────────────────
# The launcher's exec-wrapper writes ~/.claude/logs/close-records/<pid>-<epoch>.json on exit
# with the binary's REAL exit_code/signal. Keyed by the SAME pid the watchdog sees as the dead
# lead (PPID of SessionStart), it turns an "abrupt-unknown" GUESS into an attributed FACT.
#
# KEYED ON PID + START TIME, not pid alone (2026-09-30, husk-panes root cause 6). The newest
# `<pid>-*.json` for a pid is whoever last held that pid — and macOS reuses pids — so a lead that
# launched WITHOUT the wrapper (every Agent-Teams member does) joined a STRANGER's record and read its
# exit code as its own. So when the lead's start is known (LEAD_START_EPOCH, captured at registration)
# a record counts only if its `started_at` lies within LCW_CLOSE_JOIN_TOL_S of it; none does ⇒ rc 1,
# the ladder's no-record path. The wrapper stamps START_EPOCH before it execs the binary, so a genuine
# record trails the lead's own start by well under a second. `started_at` unreadable ⇒ the filename's
# epoch, which is the same START_EPOCH (bin/cc-close-attrib names the file `${rpid}-${START_EPOCH}`).
# Unknown start (an old daemon, the --classify/--close-fields entrypoints) ⇒ the pid-only join, as
# before; handle_crash logs when the death it records was joined that way.
# Seams: CC_LEAD_START_EPOCH · LCW_CLOSE_JOIN_TOL_S (5).
LEAD_START_EPOCH="${CC_LEAD_START_EPOCH:-}"
find_close_record() {
  local pid="$1" dir="${CC_CLOSE_RECORDS_DIR:-$HOME/.claude/logs/close-records}"
  local want="${LEAD_START_EPOCH:-}" tol="${LCW_CLOSE_JOIN_TOL_S:-5}" f st ep d
  [[ -n "$pid" ]] || return 1
  case "$want" in
    ''|*[!0-9]*)
      # shellcheck disable=SC2012  # ls -1t is deliberate (newest-first mtime on a fixed pid pattern)
      ls -1t "$dir/${pid}-"*.json 2>/dev/null | head -1
      return ;;
  esac
  for f in "$dir/${pid}-"*.json; do
    [[ -f "$f" ]] || continue
    st=$(close_record_field "$f" started_at) || st=""
    ep=""
    # BSD date first (this fleet is Darwin), GNU as the fallback; TZ pinned — the stamp is UTC.
    [[ -n "$st" ]] && ep=$(TZ=UTC date -j -f '%Y-%m-%dT%H:%M:%SZ' "$st" +%s 2>/dev/null \
                           || date -u -d "$st" +%s 2>/dev/null || true)
    case "$ep" in ''|*[!0-9]*) ep="${f##*-}"; ep="${ep%.json}" ;; esac
    case "$ep" in ''|*[!0-9]*) continue ;; esac
    d=$(( ep > want ? ep - want : want - ep ))
    if (( d <= tol )); then printf '%s\n' "$f"; return 0; fi
  done
  return 1
}

# Read one scalar field from a close-record without requiring jq (matches "key":123 or "key":"v").
#
# ON THE MISSING-KEY PATH, which two of this file's newer callers now take (`record_state` is absent
# from all 1,831 records written before 2026-09-08, and `ended_at` from every hand-written fixture):
# the grep exits 1, pipefail promotes it, and `v=$(…)` therefore carries rc 1 under this file's
# `set -e`. That is deliberately NOT guarded with `|| true`. Measured 2026-09-08 by removing the
# guard and re-running the whole suite: every call site here reaches this helper from either an `if`
# CONDITION (record_is_orphaned) or a command substitution feeding an assignment
# (resolve_death_epoch), and `set -e` is suspended in both — the abort has no reachable call site, so
# a guard against it would be defensive code with no control that can fail. A future BARE-STATEMENT
# call would be the one shape that aborts; add the guard then, with a test that goes red without it.
close_record_field() {
  local f="$1" key="$2" v
  [[ -f "$f" ]] || return 0
  v=$(grep -oE "\"$key\":(\"[^\"]*\"|[0-9]+)" "$f" 2>/dev/null | head -1)
  v=${v#*:}; v=${v#\"}; v=${v%\"}
  printf '%s' "$v"
}

# record_is_orphaned <record-path> → 0 iff the record is OPEN and the wrapper that owns it is GONE.
#
# bin/cc-close-attrib now pre-registers its record as `"record_state":"open"` the moment the child
# pid is known and overwrites it `"closed"` on its exit path. An `open` record that outlives its
# wrapper is therefore a POSITIVE fact — the wrapper was running and was destroyed before it could
# reach write_record — and that is the whole content of the claim. It says nothing about WHAT killed
# it, deliberately: a guessed cause is worse than the catch-all, which at least advertises that it
# does not know.
#
# The liveness half is what keeps it a fact instead of a race. The wrapper writes its record BEFORE
# it exits, so "wrapper gone" implies "write_record already ran, or was prevented from running".
# While the wrapper is still alive we are inside the millisecond window between the child's death
# and the record's close, so we ABSTAIN and the ladder falls through exactly as before — a false
# CRASH pages, and this arm must never manufacture one. `ppid` in the record is the wrapper's own
# $$; a reused pid reads ALIVE and also abstains, which is the safe direction.
#
# Residual, stated rather than hidden: if write_record itself failed (a full disk, a printf error)
# the record stays open and this reads `killed-before-report` for a session that in fact exited.
# Every step in that writer is tmp+mv guarded, so the case is vanishingly rare, and the claim it
# produces — "no exit status was ever recorded" — is still true of it.
record_is_orphaned() {
  local f="$1" st wp
  [[ -f "$f" ]] || return 1
  st=$(close_record_field "$f" record_state)
  [[ "$st" == "open" ]] || return 1
  wp=$(close_record_field "$f" ppid)
  case "$wp" in ''|*[!0-9]*) return 1 ;; esac    # unreadable owner ⇒ never claim
  if kill -0 "$wp" 2>/dev/null; then return 1; fi
  return 0
}

# marker_owns_sid <marker-file> <sid> → 0 iff this teardown marker is evidence about THIS session.
#
# A marker body carries the sid it was written FOR. That matters only on the pane-keyed lookup: an
# in-place `handoff-fire --recycle` keeps the SAME pane and registers a NEW session on it, so for up
# to the 30-min freshness window the pane carries the PREDECESSOR's marker while the registry row
# already resolves to the SUCCESSOR. Accepting it blind classifies a GENUINE crash of the successor
# as a deliberate teardown — a SILENT miss, strictly worse than the false CRASH this ladder exists to
# prevent (a false CRASH pages; a false RECYCLE is swallowed). So a marker naming a DIFFERENT
# non-empty sid is not evidence here.
#
# An EMPTY sid is the legitimate pane-only case and is still ACCEPTED: the real self-close path blanks
# SESSION_ID and the writer's registry recovery can miss, which is exactly the 2026-07-23 incident
# shape — rejecting it would regress that fix. Unreadable/absent field ⇒ empty ⇒ accepted (fail-open,
# matching this ladder's bias: never invent a crash).
marker_owns_sid() {
  local f="$1" want="$2" got
  [[ -f "$f" ]] || return 1
  got=$(grep -oE '"sid":"[^"]*"' "$f" 2>/dev/null | head -1)
  got=${got#*:}; got=${got#\"}; got=${got%\"}
  [[ -z "$got" || "$got" == "$want" ]]
}

# retired_by_desk <sid> <pid> → 0 iff this death is a SANCTIONED cc-teardown retirement.
#
# THE DEFECT THIS CLOSES (backlog 6f4573454230, measured 2026-09-07). cc-teardown collects a peer —
# work landed and content-verified, custody returned — then kills it: `kill -TERM`, and `kill -KILL`
# when the binary outlives TERM_GRACE_S. The SIGKILL leg makes the close-record read exit 137, and
# arm 0 below maps 137 to `killed-oom-or-force` and RETURNS, three arms above the deliberate-teardown
# marker that would have exonerated it. Live: pane 499 printed `verdict=TEARDOWN reason_kind=done
# exit=0` at 04:57:21Z and its own watchdog paged `killed-oom-or-force, exit 137, signal 9` at
# 04:57:51Z — over a marker naming that exact sid, written 30 s earlier.
#
# Two harms, and the second is why an exit-code-only fix is not enough: the page prescribes
# `cc-husk-sweep --resume`, which would RESTART a session whose work is already on trunk; and every
# desk teardown inflates the `killed-oom-or-force` population in claude-crashes.jsonl — the dataset
# 24d1208e8 rebuilt hours earlier to make causes trustworthy. Four panes were retired on 2026-09-07
# alone.
#
# WHY THIS READS THE TEARDOWN MARKER AND NOT THE CLOSE-RECORD. The close-record is written by the
# VICTIM's own launcher wrapper (bin/cc-close-attrib), which overwrites that exact path at its exit;
# a killer writing its intent there would either be clobbered by the wrapper's closed record or
# clobber it, and it would conflate two provenances — one process's OBSERVATION of a signal
# (`sig_reached_wrapper`, the wrapper's own trap) with another process's DECLARATION of intent. The
# teardown-marker store is already the "a killer declared this" store: contract v1, a 30-min
# freshness window, a documented reader (this file), and a GC. So cc-teardown gained a third KEY in
# that same store — its pid — and nothing else moved.
#
# THREE GUARDS keep this from absolving a real kill. (1) `mode":"teardown"` — only cc-teardown ever
# writes it (bin/cc-teardown:253); handoff-fire's own modes are untouched and still classify exactly
# as they did. (2) marker_owns_sid — a marker naming a DIFFERENT session is not evidence about this
# one, which is also what makes the pid key safe against pid reuse. (3) the 30-min freshness window,
# shared with arms 1.5/1.6.
#
# The pid key is preferred and the sid key is accepted: they are written by the same statement, and
# accepting the sid key means this fix attributes correctly for retirements whose marker predates the
# converge of the new cc-teardown — including the incident above, whose sid-keyed marker is on disk.
retired_by_desk() {
  local sid="$1" pid="${2:-}" tdir key f
  tdir="${CC_TEARDOWN_DIR:-$HOME/.claude/watchdog/teardown}"
  for key in "$pid" "$sid"; do
    [[ -n "$key" ]] || continue
    f="$tdir/$key.json"
    # `grep . >/dev/null`, never `grep -q .`: under pipefail an early-exiting consumer SIGPIPEs its
    # producer, so the pipeline can read FALSE on the very input it matched (arm 1.6 carries the same note).
    find "$tdir" -maxdepth 1 -name "$key.json" -mmin -30 2>/dev/null | grep . >/dev/null || continue
    grep -q '"mode":"teardown"' "$f" 2>/dev/null || continue
    marker_owns_sid "$f" "$sid" || continue
    return 0
  done
  return 1
}

# teammate_facts <transcript> → TEAMMATE<TAB>NAME<TAB>TEAM<TAB>SHUTDOWN   (1/0, strings, 1/0)
#
# THE DEFECT THIS CLOSES (2026-09-30, husk-panes root cause 6). An Agent-Teams member that exits
# after its lead's shutdown_request is a RETIREMENT — its work already went to the lead — but this file
# had no teammate arm: five such panes (33, 57-60) were painted "Resume it here", inviting the operator
# to restart a finished member outside its team. Members launch without cc-close-attrib, so there is
# no close record to say otherwise.
#
# TEAMMATE comes from registration when it could be read (LEAD_AGENT_ID: the lead's own argv carries
# `--agent-id <n>@<team> --agent-name <n> --team-name <team>`, read by hooks/lib/agent-identity.sh),
# else from the transcript, whose member records carry `"teamName"` AND `"agentName"` — a lead's
# records carry neither, so requiring both keeps a lead from reading as its own member.
# SHUTDOWN is a USER record holding a `<teammate-message>` whose JSON says
# `"type":"shutdown_request"`, addressed to this member (`"requestId":"shutdown-…@<name>"`). Matching
# the bare word is not enough: every member's instructions attachment and brief mention
# shutdown_request in prose, which is exactly the contamination root cause 7 found in the close reader.
# One streaming pass, bounded like last_assistant_text. Unreadable ⇒ `0 - - 0 - 0` (not a teammate).
#
# Output is TEAMMATE<TAB>NAME<TAB>TEAM<TAB>SHUTDOWN<TAB>SOURCE<TAB>MIDTASK. SOURCE is `own` (the request
# reached the member's transcript), `lead-request` / `lead-taskstop` (the LEAD's transcript), or `-`.
# MIDTASK=1 only on a lead source whose member died with a tool call still open.
#
# THE LEAD-SIDE SOURCE (2026-10-10, docs/research/teammate-teardown-verdict-2026-10-10/REPORT.md).
# The member-transcript record is necessary-but-late: a shutdown_request reaches a member only at its
# next turn boundary, so a BUSY member that is TaskStopped and then SIGTERMed never records it — and
# TaskStop alone records nothing on the member's side at all. Measured over claude-crashes.jsonl: 28
# lead-ordered teardowns painted CRASH/abrupt-unknown (cvf-docs, pane 200, was one), 20 of them
# TaskStop-only; 5 of the 28 were a bare kill with no successful order, and stay CRASH by design. The lead's own transcript holds the order in HARNESS-written form a member cannot
# author: the SendMessage result's toolUseResult {success, request_id shutdown-…@<name>, target}, and a
# TaskStop result {task_type: in_process_teammate} joined to `input.task_id == <name>` by tool_use_id.
# Guards: the lead transcript is resolved from the team (config leadSessionId, else the
# `session-<sid8>` name); a record carrying teamName/agentName is a member's, never the lead's; the
# ORDER's timestamp (the TaskStop tool_use — its result lands just after the member's exit flush)
# must postdate the member's first record (a re-spawned namesake) and fall within 600 s before the
# member's last write (+2 s), so a lead that TaskStops a member it found already dead absolves nothing.
# A shutdown_request alone proves only that it was SENT, so it counts just for a member that died
# between turns and never answered approve:false. Jetsam outranks all of this, as it outranks the
# member-side source. Skeptic review + fleet replay: REPORT.md § Skeptic (23 of 28 rescued, 0 of 80
# no-order teammate crashes flipped).
teammate_facts() {
  local t="${1:-}" out=""
  if [[ -n "$t" && -f "$t" ]]; then
    out=$(lcw_bounded "${LCW_REPORT_READ_TIMEOUT_S:-30}" "${LCW_PYTHON_BIN:-python3}" - "$t" "${LEAD_AGENT_ID:-}" "${2:-}" <<'PY' 2>/dev/null || true
import json, re, sys
argv_id = sys.argv[2] if len(sys.argv) > 2 else ""
name = argv_id.split("@", 1)[0] if "@" in argv_id else ""
team = argv_id.split("@", 1)[1] if "@" in argv_id else ""
is_team = bool(name)
rids = []
try:
    with open(sys.argv[1], "r", errors="replace") as fh:
        for line in fh:
            if '"teamName"' not in line and "shutdown_request" not in line:
                continue
            try:
                rec = json.loads(line)
            except Exception:
                continue
            if rec.get("teamName") and rec.get("agentName"):
                is_team = True
                name = name or rec["agentName"]
                team = team or rec["teamName"]
            msg = rec.get("message") or {}
            if rec.get("type") != "user" or msg.get("role") != "user":
                continue
            c = msg.get("content")
            if isinstance(c, list):
                c = "\n".join(b.get("text", "") for b in c if isinstance(b, dict) and b.get("type") == "text")
            if not isinstance(c, str) or "<teammate-message" not in c or '"type":"shutdown_request"' not in c:
                continue
            m = re.search(r'"requestId":"([^"]*)"', c)
            rids.append(m.group(1) if m else "")
except Exception:
    pass
shut = any((not r) or (not name) or r.endswith("@" + name) for r in rids)
source = "own" if (is_team and shut) else "-"
mid = 0
def emit():
    sys.stdout.write("%d\t%s\t%s\t%d\t%s\t%d\n" % (1 if is_team else 0, name or "-", team or "-",
                     1 if (is_team and shut) else 0, source, mid))
    sys.stdout.flush()
# Identity first, flushed: if the lead read below is cut by the bound, the caller still has the
# member-side facts (it takes the LAST line), instead of losing the teammate identity with the rest.
emit()
if is_team and not shut and name and team and team != "-":
    import glob, os
    from datetime import datetime
    def ep(ts):
        try:
            return datetime.fromisoformat(str(ts).replace("Z", "+00:00")).timestamp()
        except Exception:
            return None
    # The member's own facts: when it started (a same-name member spawned EARLIER is not this one),
    # whether it refused a shutdown (approve:false), and whether a tool call was still open at death.
    first = None; refused = False; pending = set()
    try:
        with open(sys.argv[1], "r", errors="replace") as fh:
            for line in fh:
                try:
                    rec = json.loads(line)
                except Exception:
                    continue
                if first is None and rec.get("timestamp"):
                    first = ep(rec["timestamp"])
                msg = rec.get("message") or {}
                c = msg.get("content") if isinstance(msg, dict) else None
                if not isinstance(c, list):
                    continue
                for b in c:
                    if not isinstance(b, dict):
                        continue
                    if b.get("type") == "tool_use":
                        pending.add(b.get("id"))
                        inp = b.get("input") or {}
                        m = inp.get("message") if isinstance(inp, dict) else None
                        if isinstance(m, dict) and m.get("type") == "shutdown_response" and m.get("approve") is False:
                            refused = True
                    elif b.get("type") == "tool_result":
                        pending.discard(b.get("tool_use_id"))
    except Exception:
        first = None
    # The anchor is the member's LAST WRITE: a crash stops writing at death, while a member its lead
    # stopped flushes its exit 0.3-0.7 s AFTER the order (measured, 20 of 26 rows; max 260 s). A caller's
    # death epoch can only pull it earlier. The ORDER (the TaskStop tool_use, not its result, which lands
    # just after that flush) must fall in [anchor - window, anchor + 2 s] and after the member's first
    # record — so a lead that stops a member it found already dead, or an order to an earlier same-name
    # member, absolves nothing.
    try:
        anchor = os.stat(sys.argv[1]).st_mtime
    except Exception:
        anchor = None
    if len(sys.argv) > 3 and sys.argv[3].isdigit() and anchor is not None:
        anchor = min(anchor, float(sys.argv[3]))
    win = float(os.environ.get("LCW_LEAD_TEARDOWN_WINDOW_S") or 600)
    bases = (os.environ.get("CC_ACCOUNT_BASES") or " ".join(os.path.expanduser(p) for p in
             ("~/.claude", "~/.claude-secondary", "~/.claude-tertiary", "~/.claude-quaternary"))).split()
    lead_tx = None
    for b in bases:  # the team config names its lead exactly, whatever the team is called
        try:
            lsid = json.load(open(os.path.join(b, "teams", team, "config.json"))).get("leadSessionId") or ""
        except Exception:
            lsid = ""
        if lsid:
            near = os.path.join(os.path.dirname(sys.argv[1]), lsid + ".jsonl")
            hits = [near] if os.path.isfile(near) else glob.glob(os.path.join(b, "projects", "*", lsid + ".jsonl"))
            if hits:
                lead_tx = hits[0]; break
    sid8 = team[len("session-"):] if team.startswith("session-") else ""
    if lead_tx is None and len(sid8) == 8:  # the team dir is gone: its name is session-<lead sid8>
        near = sorted(glob.glob(os.path.join(os.path.dirname(sys.argv[1]), sid8 + "*.jsonl")))
        if near:
            lead_tx = near[0]
        else:
            for b in bases:
                hits = sorted(glob.glob(os.path.join(b, "projects", "*", sid8 + "*.jsonl")))
                if hits:
                    lead_tx = hits[0]; break
    if first is not None and anchor is not None and lead_tx:
        def inwin(t):
            return t is not None and t >= first and anchor - win <= t <= anchor + 2
        stops = {}; got = ""; asked = False
        try:
            with open(lead_tx, "r", errors="replace") as fh:
                for line in fh:
                    if name not in line and "in_process_teammate" not in line:
                        continue
                    try:
                        rec = json.loads(line)
                    except Exception:
                        continue
                    if rec.get("teamName") or rec.get("agentName"):
                        continue  # a member's record is never its lead's order
                    t = ep(rec.get("timestamp"))
                    msg = rec.get("message") or {}
                    c = msg.get("content") if isinstance(msg, dict) else None
                    if rec.get("type") == "assistant" and isinstance(c, list):
                        for b in c:
                            if isinstance(b, dict) and b.get("type") == "tool_use" and b.get("name") == "TaskStop" \
                               and (b.get("input") or {}).get("task_id") in (name, name + "@" + team):
                                stops[b.get("id")] = t   # the ORDER's time
                    if rec.get("type") != "user":
                        continue
                    r = rec.get("toolUseResult")
                    if not isinstance(r, dict):
                        continue
                    # (a) TaskStop of this member, joined by tool_use_id; a failed stop is a tool_use_error
                    #     string, and a same-named background task has another task_type
                    if r.get("task_type") == "in_process_teammate" and isinstance(c, list):
                        for b in c:
                            if isinstance(b, dict) and b.get("type") == "tool_result" and inwin(stops.get(b.get("tool_use_id"))):
                                got = "lead-taskstop"
                    # (b) SendMessage shutdown_request, as the HARNESS recorded its delivery to the inbox
                    if r.get("success") is True and str(r.get("request_id", "")).startswith("shutdown-") \
                       and str(r.get("request_id", "")).endswith("@" + name) and r.get("target", name) == name and inwin(t):
                        asked = True
        except Exception:
            got = ""; asked = False
        # A request alone proves it was SENT, not that it ended this member: it counts only for a member
        # that died between turns (no open tool call) and never refused. A TaskStop is the lead ending it.
        if not got and asked and not pending and not refused:
            got = "lead-request"
        if got:
            shut = True; source = got; mid = 1 if pending else 0
            emit()
PY
)
    out="${out%$'\n'}"; out="${out##*$'\n'}"   # the LAST complete line: the lead read may upgrade the first
  fi
  [[ -n "$out" ]] || out=$'0\t-\t-\t0\t-\t0'
  printf '%s' "$out"
}
retired_teammate() { # $1=transcript $2=death epoch (optional) → 0 iff a teammate its lead retired (either source)
  local f is shut
  f=$(teammate_facts "${1:-}" "${2:-}")
  IFS=$'\t' read -r is _ _ shut _ <<< "$f" || true
  [[ "$is" == 1 && "$shut" == 1 ]]
}

# EXIT<TAB>SIGNAL<TAB>RECORD_PATH<TAB>VERSION for a pid's newest close-record (empty if none).
# Used by handle_crash to enrich the crash row AND by the --close-fields test entrypoint.
close_record_summary() {
  local pid="$1" cr
  [[ -n "$pid" ]] || return 0
  cr=$(find_close_record "$pid") || return 0
  [[ -n "$cr" ]] || return 0
  printf '%s\t%s\t%s\t%s' \
    "$(close_record_field "$cr" exit_code)" \
    "$(close_record_field "$cr" signal)" \
    "$cr" \
    "$(close_record_field "$cr" version)"
}

# exit code → CLASS<TAB>CAUSE (ground truth). Non-numeric/absent ⇒ return 1 (no override).
#   0/130/143 (SIGINT/SIGTERM) = clean-exit · 137 (SIGKILL) = killed-oom-or-force ·
# 137 IS STILL MAPPED HERE, and deliberately: this function answers "what does the exit code alone
# say", and 137 alone says SIGKILL/OOM. Whether a sanctioned retirement EXPLAINS that SIGKILL is a
# different question, asked by the CALLER (classify_death arm 0, via retired_by_desk) against
# evidence this function is not given. Moving 137 out of the map the way 143 was moved would have
# been the wrong shape: it would make every un-retired force-kill fall through to the ladder and
# land as `abrupt-unknown`, losing the real signal the brief requires be preserved.
#   139 (SIGSEGV) = binary-crash · any other nonzero = error-exit.
# 143 (SIGTERM) is DELIBERATELY not here. It used to sit in the clean-exit arm beside 0 and 130,
# which made every externally-killed session self-certify as a voluntary one — the incident of
# 2026-08-09, where three sessions were killed by one stray `pkill` and this rung classified all
# three RECYCLE/clean-exit at the ladder's FIRST step, before any evidence was consulted.
# SIGTERM is CATCHABLE and Claude Code catches it: it runs SessionEnd and prints its ordinary resume
# banner, so a kill and an `/exit` are byte-identical on screen AND in the exit code. 0 and 130 are
# different — nothing external produces them (130 is the operator's own Ctrl-C).
# So 143 returns 1 = "unmapped", and the caller falls through to the ladder, where the teardown
# marker decides: cc-teardown TERMs, but writes its marker unconditionally first (bin/cc-teardown
# :275), so a SANCTIONED TERM still reads RECYCLE and only an unattributed one reads CRASH.
map_exit_class() {
  case "$1" in
    143)          return 1 ;;
    0|130)        printf 'RECYCLE\tclean-exit' ;;
    137)          printf 'CRASH\tkilled-oom-or-force' ;;
    139)          printf 'CRASH\tbinary-crash' ;;
    ''|*[!0-9]*)  return 1 ;;
    *)            printf 'CRASH\terror-exit' ;;
  esac
}

# ── jetsam attribution, anchored to the DEATH — not to "now" (audit 2026-07-22, root cause 4) ─────────
# The check used to be `find … -mmin -6`, i.e. "was any JetsamEvent written in the last 6 minutes OF
# NOW". On the LIVE path now ≈ the death, so it read correctly. On `cc-crash-report --backfill`, which
# re-classifies up to 90 HISTORICAL deaths, "now" is whenever the report happens to run — so the same
# expression answered a question about the present for every death in the past:
#   · one unrelated jetsam kill in the last 6 minutes relabelled EVERY backfilled death jetsam-oom,
#     deliberate recycles included — and jetsam OUTRANKS the recycle evidence, so those flips are
#     silent and total (the recycle text is never even consulted);
#   · a death 3 days ago that WAS jetsam-killed could never match, because its report is long past
#     any now-relative window.
# The window is now two-sided around the death, which is what the documented contract ("a JetsamEvent
# within ~6 min of death", cc-crash-report:15) always claimed: a report is written AT or shortly after
# the kill, while the watchdog notices up to one 30s poll late, so the truth can fall on either side.
JETSAM_WINDOW_S="${CC_JETSAM_WINDOW_S:-360}"     # ±6 min, the interval the old -mmin -6 approximated
jetsam_near_death() { # $1=death epoch → 0 iff a JetsamEvent report lies within ±JETSAM_WINDOW_S of it
  local death="$1" f mt d out
  case "$death" in ''|*[!0-9]*) return 1 ;; esac   # unparseable death ⇒ do not claim jetsam (never invent a cause)
  local jdirs="${CC_JETSAM_DIRS:-/Library/Logs/DiagnosticReports $HOME/Library/Logs/DiagnosticReports}"
  # BOUNDED: DiagnosticReports is a system dir this crash path does not control. Reuse the timeout
  # binary already resolved at the top of this file; absent ⇒ unbounded, as everywhere else here.
  # The window is applied in bash rather than by find: BSD find REJECTS `-newermt @epoch` ("Can't parse
  # date/time"), the same trap lead-supervisor.sh records, and a two-sided window needs two references
  # anyway. `-mmin` cannot express "near an arbitrary past instant" at all.
  # shellcheck disable=SC2086  # intentional word-split over space-separated dirs (matches the old call)
  if [[ -n "$LCW_OSA_TB" && -x "$LCW_OSA_TB" ]]; then
    out=$("$LCW_OSA_TB" -k 3 "${LCW_JETSAM_SCAN_TIMEOUT_S:-10}" find $jdirs -name 'JetsamEvent-*.ips' -print 2>/dev/null || true)
  else
    out=$(find $jdirs -name 'JetsamEvent-*.ips' -print 2>/dev/null || true)
  fi
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    mt=$(stat -f%m "$f" 2>/dev/null || stat -c%Y "$f" 2>/dev/null || echo 0)   # BSD stat, then GNU fallback
    case "$mt" in ''|*[!0-9]*) continue ;; esac
    d=$(( mt > death ? mt - death : death - mt ))
    # explicit `if`, never `[[ … ]] && return`: a non-final [[ ]] in an && list is errexit-EXEMPT, so a
    # false compare would silently fall through instead of continuing the loop (the dead-assertion class)
    if [[ "$d" -le "$JETSAM_WINDOW_S" ]]; then return 0; fi
  done <<< "$out"
  return 1
}

# ── a HUP is not a clean exit until something says the terminal survived (incident 2026-10-15) ──────
# When kitty segfaulted at 05:01:34Z it SIGHUPed every pane; 18 Claude sessions caught the HUP, ran
# SessionEnd and exited 0, so their close-records read `exit_code 0` + `sig_reached_wrapper HUP`, and
# step 0's exit-code map filed 17 of the 18 as RECYCLE/clean-exit. But an ordinary ⌘W also HUPs its
# pane, so a HUP alone proves nothing either way. What separates them is CORROBORATION: a terminal
# death HUPs many panes in the same second, and kitty leaves a crash report. So:
#   · >= LCW_HUP_SIBLINGS_MIN (2) OTHER HUP records ending within ±LCW_HUP_SIBLING_WINDOW_S (15) of
#     this one, or a kitty crash report within ±JETSAM_WINDOW_S (6 min) of the death ⇒ terminal-died;
#   · neither ⇒ the caller files a silent pane-hangup.
# The close-records dir holds thousands of files, so siblings are pre-filtered by MTIME (a record is
# written at its ended_at) inside one bounded find+stat, and only those near the death are opened.
# The crash-report scan is the jetsam scan's shape, same dirs and same bound. Real names on this
# fleet are `kitty-YYYY-MM-DD-HHMMSS.ips`; `kitty.*.ips` is matched as well.
# Seams: CC_CLOSE_RECORDS_DIR · CC_JETSAM_DIRS · LCW_HUP_SIBLINGS_MIN · LCW_HUP_SIBLING_WINDOW_S.
utc_stamp_epoch() { # $1=YYYY-MM-DDTHH:MM:SSZ → epoch on stdout, nothing if unparseable
  [[ -n "${1:-}" ]] || return 0
  TZ=UTC date -j -f '%Y-%m-%dT%H:%M:%SZ' "$1" +%s 2>/dev/null || date -u -d "$1" +%s 2>/dev/null || true
}

# hup_corroboration <record-path> <death-epoch> → rc 0 + the evidence as text iff corroborated
hup_corroboration() {
  local rec="$1" death="$2" anchor dir out mt f sib n=0 d
  local win="${LCW_HUP_SIBLING_WINDOW_S:-15}" need="${LCW_HUP_SIBLINGS_MIN:-2}"
  local pre=$(( ${LCW_HUP_SIBLING_WINDOW_S:-15} + 120 ))   # mtime slack: record write vs its ended_at
  anchor=$(utc_stamp_epoch "$(close_record_field "$rec" ended_at)")
  case "$anchor" in ''|*[!0-9]*) anchor="$death" ;; esac
  case "$anchor" in ''|*[!0-9]*) return 1 ;; esac
  dir="${CC_CLOSE_RECORDS_DIR:-$HOME/.claude/logs/close-records}"
  if [[ -n "$LCW_OSA_TB" && -x "$LCW_OSA_TB" ]]; then
    out=$("$LCW_OSA_TB" -k 3 "${LCW_JETSAM_SCAN_TIMEOUT_S:-10}" find "$dir" -maxdepth 1 -name '*.json' -exec stat -f '%m %N' {} + 2>/dev/null || true)
  else
    out=$(find "$dir" -maxdepth 1 -name '*.json' -exec stat -f '%m %N' {} + 2>/dev/null || true)
  fi
  while IFS= read -r f; do
    mt="${f%% *}"; f="${f#* }"
    case "$mt" in ''|*[!0-9]*) continue ;; esac
    [[ "$f" != "$rec" ]] || continue
    d=$(( mt > anchor ? mt - anchor : anchor - mt ))
    if [[ "$d" -gt "$pre" ]]; then continue; fi
    if [[ "$(close_record_field "$f" sig_reached_wrapper)" != "HUP" ]]; then continue; fi
    sib=$(utc_stamp_epoch "$(close_record_field "$f" ended_at)")
    case "$sib" in ''|*[!0-9]*) continue ;; esac
    d=$(( sib > anchor ? sib - anchor : anchor - sib ))
    if [[ "$d" -le "$win" ]]; then n=$(( n + 1 )); fi
  done <<< "$out"
  if [[ "$n" -ge "$need" ]]; then printf '%s sibling HUPs within %ss' "$n" "$win"; return 0; fi
  case "$death" in ''|*[!0-9]*) return 1 ;; esac
  local jdirs="${CC_JETSAM_DIRS:-/Library/Logs/DiagnosticReports $HOME/Library/Logs/DiagnosticReports}"
  # shellcheck disable=SC2086  # intentional word-split over space-separated dirs (as jetsam_near_death)
  if [[ -n "$LCW_OSA_TB" && -x "$LCW_OSA_TB" ]]; then
    out=$("$LCW_OSA_TB" -k 3 "${LCW_JETSAM_SCAN_TIMEOUT_S:-10}" find $jdirs \( -name 'kitty-*.ips' -o -name 'kitty.*.ips' \) -print 2>/dev/null || true)
  else
    out=$(find $jdirs \( -name 'kitty-*.ips' -o -name 'kitty.*.ips' \) -print 2>/dev/null || true)
  fi
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    mt=$(stat -f%m "$f" 2>/dev/null || stat -c%Y "$f" 2>/dev/null || echo 0)
    case "$mt" in ''|*[!0-9]*) continue ;; esac
    d=$(( mt > death ? mt - death : death - mt ))
    if [[ "$d" -le "$JETSAM_WINDOW_S" ]]; then printf 'a kitty crash report (%s)' "${f##*/}"; return 0; fi
  done <<< "$out"
  return 1
}

# ── when did this session die? — the anchor jetsam attribution is judged against ────────────────────
# Deliberately NOT parsed from the watchdog log: the daemon writes its "LEAD CRASH detected" lines with a
# bare `echo` into an already-redirected stdout, so — unlike the hook's log() lines — they carry NO
# timestamp at all. A parser keyed on one would match 0 of the 3064 historical detections and turn
# backfill into a silent no-op that still printed a confident summary.
#
# Disk evidence instead, most precise first:
#   1. the close-record's `ended_at` — written by the exec-wrapper at the moment it reaped the binary.
#      This is the exact death instant, not a proxy. (NOT the epoch in the FILE NAME: that is the
#      session's START — see the block below, which this line used to get wrong.)
#   2. the transcript mtime — its last write is the last thing the session did before dying. Available
#      for essentially every historical death, which is what backfill needs.
#   3. now — the LIVE daemon's answer. It detects within one 30s poll, far inside a ±6-min window, and
#      it must not be "corrected" to a transcript mtime: a session idle for hours before being killed has
#      an old transcript but died just now, and anchoring to the mtime would MISS its real jetsam report.
# So the live path (no argument) keeps using now, and backfill asks for `auto` to walk 1→2→3.
resolve_death_epoch() { # $1=sid  $2=pid  → epoch on stdout
  local sid="$1" pid="${2:-}" cr ep t mt
  if [[ -n "$pid" ]]; then
    cr=$(find_close_record "$pid") || cr=""
    if [[ -n "$cr" ]]; then
      # 🚨 THE FILENAME EPOCH IS THE SESSION'S **START**, NOT ITS DEATH (corrected 2026-09-08).
      # This block used to read `<pid>-<epoch>.json` and call it "the exact death instant, not a
      # proxy". bin/cc-close-attrib names the file `${rpid}-${START_EPOCH}.json` — START_EPOCH is
      # taken before the binary is even exec'd — so the anchor was the session's BIRTH. Measured
      # over the 1,831 live close-records carrying both stamps, the median session lives 43.5 min
      # and 87.7% live longer than the ±6-min jetsam window this epoch feeds, so the anchor missed
      # its window for the large majority of backfilled deaths. (One sample: pid 5148, filename
      # epoch 2026-09-08T00:04:10Z, actual death 02:02:57Z — off by 1h58m.)
      # The record's own `ended_at` IS the death instant, so read that instead. An OPEN record has
      # no `ended_at` by construction — we genuinely do not know when it ended — and correctly falls
      # through to the transcript mtime below rather than asserting its start time as its death.
      ep=$(close_record_field "$cr" ended_at)
      if [[ -n "$ep" ]]; then
        # BSD date first (this fleet is Darwin), GNU as the portable fallback; TZ pinned because
        # both parse the naked stamp in LOCAL time otherwise and the stamp is UTC.
        ep=$(TZ=UTC date -j -f '%Y-%m-%dT%H:%M:%SZ' "$ep" +%s 2>/dev/null \
             || date -u -d "$ep" +%s 2>/dev/null || true)
        case "$ep" in ''|*[!0-9]*) ep="" ;; esac
        [[ -n "$ep" ]] && { printf '%s' "$ep"; return 0; }
      fi
    fi
  fi
  t=$(find_transcript "$sid" 2>/dev/null || true)
  if [[ -n "$t" && -f "$t" ]]; then
    mt=$(stat -f%m "$t" 2>/dev/null || stat -c%Y "$t" 2>/dev/null || echo "")
    case "$mt" in ''|*[!0-9]*) mt="" ;; esac
    [[ -n "$mt" ]] && { printf '%s' "$mt"; return 0; }
  fi
  date +%s
}

# ── WHO ENDED THIS SESSION, WHEN IT WAS NOT ITSELF (husk-panes-2026-10-22 F7c) ─────────────────────
# Two deaths the ladder below misread on 2026-10-22, both from one misdirected self-close:
#   · lead 666022fd was closed by ANOTHER session typing /exit into its pane (pane-keys.jsonl rows
#     from sid 570d3917) and was logged RECYCLE clean-exit with no page — the one real loss of the
#     day produced no signal. A typed /exit ends with exit 0 and a self-close teardown marker, so
#     every arm below absolves it.
#   · that other session was a headless `claude -p --resume` (registered tty=none, inside the lead's
#     pane), and its ordinary end, with no close record, was paged as suspected-oom-large-context.
# The typer is judged by its OWN registration: a session that types /exit into a pane while it has
# no pane of its own (tty=none) or is registered IN that very pane is nested inside its victim. A
# legitimate remote retire (a firer closing its peer) comes from a session with its own pane and
# tty, and is not this arm's business — so this under-reports rather than paging every retire.
# Seams: CC_PANE_KEYS_LOG · CC_CLOSED_BY_OTHER_WINDOW_S (180).
last_registration() { # $1=sid → "<tty> <pane>" from its newest `registered session=` line, or nothing
  local line
  line=$(grep -F "registered session=$1 " "$LOG_FILE" 2>/dev/null | tail -1) || true
  [[ -n "$line" ]] || return 0
  printf '%s %s' "$(sed -n 's/.* tty=\([^ ]*\).*/\1/p' <<<"$line")" "$(sed -n 's/.* pane=\([^ ]*\).*/\1/p' <<<"$line")"
}
closed_by_other() { # $1=sid $2=death epoch → prints the typer's sid iff a nested session typed /exit into this pane
  local sid="$1" death="$2" reg pane keys win typer ttyq paneq ep row
  reg=$(last_registration "$sid"); pane="${reg#* }"
  [[ "$pane" =~ ^[0-9]+$ ]] || return 1
  keys="${CC_PANE_KEYS_LOG:-$HOME/.claude/logs/pane-keys.jsonl}"
  [[ -f "$keys" ]] || return 1
  win="${CC_CLOSED_BY_OTHER_WINDOW_S:-180}"
  while IFS=$'\t' read -r typer ep; do
    [[ -n "$typer" && "$typer" != "$sid" && "$ep" =~ ^[0-9]+$ ]] || continue
    (( ep <= death + 5 && ep >= death - win )) || continue
    row=$(last_registration "$typer"); ttyq="${row%% *}"; paneq="${row#* }"
    if [[ "$ttyq" == none || "$paneq" == "$pane" ]]; then printf '%s' "$typer"; return 0; fi
  done < <(grep -F "\"pane\":\"$pane\"" "$keys" 2>/dev/null | grep -F '/exit' \
             | jq -r 'def cell(ph): (if . == null then "" else . end) | tostring
                                    | gsub("[\\t\\r\\n]"; " ") | if . == "" then ph else . end;
                      select((.head40 // "") | test("^(\u001b\\[200~)?/exit"))
                      | [(.sid | cell("-")), ((.ts // "") | (try fromdateiso8601 catch 0) | tostring)] | @tsv' 2>/dev/null | tail -20)
  return 1
}

classify_death() {
  # prints: CLASS<TAB>CAUSE<TAB>transcript_kb<TAB>records   (CLASS = RECYCLE|CRASH)
  # $3 = when this session died, for jetsam attribution: an EPOCH, the literal `auto` (derive from disk —
  # what cc-crash-report --backfill passes, since its deaths are historical), or omitted ⇒ NOW, which is
  # correct for the live daemon and is what every pre-existing caller gets unchanged.
  local sid="$1" pid="${2:-}" death="${3:-}" t body kb=0 recs=0 ec="" cr_open=""
  if [[ "$death" == "auto" ]]; then death=$(resolve_death_epoch "$sid" "$pid"); fi
  case "$death" in ''|*[!0-9]*) death=$(date +%s) ;; esac
  # -1) CLOSED BY ANOTHER SESSION outranks even the close record: a typed /exit ends with exit 0 and
  #     looks clean to every arm below (lead 666022fd, 2026-10-22). See closed_by_other.
  if closed_by_other "$sid" "$death" >/dev/null; then
    t=$(find_transcript "$sid" 2>/dev/null || true)
    if [[ -n "$t" ]]; then kb=$(( $(stat -f%z "$t" 2>/dev/null || echo 0) / 1024 )); recs=$(wc -l < "$t" 2>/dev/null | tr -d ' '); fi
    printf 'CRASH\tclosed-by-other-session\t%s\t%s' "${kb:-0}" "${recs:-0}"; return 0
  fi
  # 0) CLOSE-RECORD FIRST — per-pid ground truth OUTRANKS every heuristic below (incl. jetsam:
  #    137 already IS the SIGKILL/OOM case; a clean exit for THIS pid is clean even if some other
  #    process tripped a JetsamEvent). Absent record ⇒ fall through to the existing ladder.
  if [[ -n "$pid" ]]; then
    local cr cls
    cr=$(find_close_record "$pid") || cr=""
    if [[ -n "$cr" ]]; then
      ec=$(close_record_field "$cr" exit_code)
      # A HUP-reached record does not self-certify through the exit-code map (see hup_corroboration):
      # 0/130 and 129 (the HUP's own exit) are what a hung-up pane exits with, whether ⌘W or a dead
      # terminal sent it. 143/137/139 keep their own meaning. The relabels below apply unchanged.
      local hup_ok=1
      if [[ "$(close_record_field "$cr" sig_reached_wrapper)" == "HUP" ]]; then
        case "$ec" in 0|129|130) hup_ok=0 ;; esac
      fi
      if [[ "$hup_ok" -eq 0 ]]; then
        if hup_corroboration "$cr" "$death" >/dev/null; then cls=$'CRASH\tterminal-died'
        else cls=$'RECYCLE\tpane-hangup'; fi
      fi
      if [[ "$hup_ok" -eq 0 ]] || cls=$(map_exit_class "$ec"); then
        # …but a CRASH class here is a claim about a SIGNAL, and a signal cannot tell a deliberate
        # retirement from an OOM kill. cc-teardown's SIGKILL leg produced exit 137 for a session that
        # was collected, landed and returned — see retired_by_desk for the incident. A sanctioned
        # retirement therefore OVERRIDES the exit-code map, and only for the classes that would page:
        # a retired session that exited 0 is already `clean-exit`, which is both true and silent.
        # JETSAM STILL OUTRANKS IT, exactly as it outranks arms 1.5/1.6 — "a kill mid-teardown is
        # still a kill" — so a real OOM that beats the retirement to the process keeps its own name.
        if [[ "$cls" == CRASH* ]] && ! jetsam_near_death "$death" && retired_by_desk "$sid" "$pid"; then
          cls=$'RECYCLE\tretired-by-desk'
        fi
        t=$(find_transcript "$sid" 2>/dev/null || true)
        # A teammate its lead shut down is retired whatever its exit code says (see teammate_facts):
        # a clean exit is relabelled so the pane verdict says "close it", a signal is not a crash.
        # Jetsam still outranks, as above.
        if [[ "$cls" != *retired-by-desk ]] && ! jetsam_near_death "$death" && retired_teammate "$t" "$death"; then
          cls=$'RECYCLE\tretired-teammate'
        fi
        if [[ -n "$t" ]]; then
          kb=$(( $(stat -f%z "$t" 2>/dev/null || echo 0) / 1024 ))
          recs=$(wc -l < "$t" 2>/dev/null | tr -d ' ')
        fi
        printf '%s\t%s\t%s' "$cls" "${kb:-0}" "${recs:-0}"; return 0
      fi
      # No usable exit code. If the record is OPEN and its wrapper is gone, remember that — arm 3
      # turns it into an attributed cause. It is NOT decided here: an open record must not outrank
      # jetsam or a deliberate teardown (a kill that lands mid-recycle is still a recycle's ending,
      # and a false CRASH pages), so it only ever refines what would otherwise be the catch-all.
      if record_is_orphaned "$cr"; then cr_open="$cr"; fi
    fi
  fi
  t=$(find_transcript "$sid") || { printf 'CRASH\tno-transcript\t0\t0'; return 0; }
  kb=$(( $(stat -f%z "$t" 2>/dev/null || echo 0) / 1024 ))
  recs=$(wc -l < "$t" 2>/dev/null | tr -d ' ')
  # 1) JETSAM FIRST — a JetsamEvent report within ~6 min OF THIS DEATH is an unambiguous system OOM
  #    kill and OUTRANKS any recycle text (a kill mid-recycle is still a kill). Because it outranks
  #    everything, a mis-anchored window is not a mild inaccuracy: it silently overwrites good evidence.
  if jetsam_near_death "$death"; then
    printf 'CRASH\tjetsam-oom\t%s\t%s' "${kb:-0}" "${recs:-0}"; return 0
  fi
  # 1.4) RETIRED TEAMMATE — a team member that exited after its lead's shutdown_request (see
  #      teammate_facts). The structured request in its own transcript, else its LEAD's recorded
  #      shutdown_request/TaskStop of it, is the evidence; it outranks the markers and prose below.
  if retired_teammate "$t" "$death"; then
    printf 'RECYCLE\tretired-teammate\t%s\t%s' "${kb:-0}" "${recs:-0}"; return 0
  fi
  # 1.5) DELIBERATE TEARDOWN — a fresh marker handoff-fire.sh writes the moment a session
  #      CHOOSES to recycle/self-close: the durable structured signal that supersedes the
  #      brittle prose-grep below (incident 2026-07-23: a real self-close read as a false
  #      CRASH). Keyed by session id, else pane uuid (resolved via the registry). Fresh =
  #      mtime <30 min. Jetsam (above) still outranks — a kill mid-teardown is still a kill.
  local tdir="${CC_TEARDOWN_DIR:-$HOME/.claude/watchdog/teardown}"
  local reg_dir="${CC_REGISTRY_DIR:-$HOME/.claude/cc-registry}"
  # Both start EMPTY, never merely declared: arm 1.6 below reads "$pane" on the path where the
  # registry lookup found nothing, and a bare `local pane` leaves it UNSET, which is a fatal
  # unbound-variable under this script's `set -u`. That aborted classify_death for every death
  # whose sid the registry cannot resolve — the ordinary case, and the one arm 1.6 exists to serve.
  local reg_hit="" pane=""
  if find "$tdir" -maxdepth 1 -name "$sid.json" -mmin -30 2>/dev/null | grep -q .; then
    printf 'RECYCLE\tdeliberate-teardown\t%s\t%s' "${kb:-0}" "${recs:-0}"; return 0
  fi
  # registry row is pretty-printed ("session_id": "<sid>" — note the space); match it
  # whitespace-tolerantly. head -1 + `|| true`: a no-match grep must not trip set -e/pipefail
  # (classify_death runs bare at the --classify entrypoint, not in an || context).
  reg_hit=$(grep -lE "\"session_id\":[[:space:]]*\"$sid\"" "$reg_dir"/*.json 2>/dev/null | head -1) || true
  if [[ -n "$reg_hit" ]]; then
    pane=$(basename "$reg_hit" .json)
    # marker_owns_sid: an in-place --recycle leaves the PREDECESSOR's marker on a pane the registry
    # now resolves to the SUCCESSOR — a marker naming a different session must not absolve this one.
    if find "$tdir" -maxdepth 1 -name "$pane.json" -mmin -30 2>/dev/null | grep -q . \
       && marker_owns_sid "$tdir/$pane.json" "$sid"; then
      printf 'RECYCLE\tdeliberate-teardown\t%s\t%s' "${kb:-0}" "${recs:-0}"; return 0
    fi
  fi
  # 1.6) HANDOFF-LOG PANE RECOVERY — the arm above is UNREACHABLE for the exact case the pane-keyed
  #      marker exists to cover. The registry is SINGLE-SLOT PER PANE, so an in-place `--recycle`
  #      OVERWRITES the dead session's row with the SUCCESSOR's the moment the successor registers,
  #      destroying the only sid→pane mapping arm 1.5 has. Both arms then need a sid that nothing
  #      still maps: 1.5a keys the marker FILENAME on it, 1.5b keys the registry lookup on it.
  #      Measured 2026-08-25 on the real classify_death with isolated stores — one variable moved,
  #      the registry owner, marker byte-identical in both cells:
  #        pane-keyed marker, empty sid, registry→PREDECESSOR ⇒ RECYCLE/deliberate-teardown
  #        pane-keyed marker, empty sid, registry→SUCCESSOR   ⇒ CRASH/abrupt-unknown
  #      So the EMPTY SID is not the cause and marker_owns_sid's fail-open is working as documented
  #      (:126-129); the lost sid→pane mapping is. ~/.claude/logs/handoffs.jsonl is APPEND-ONLY and
  #      its `recycle-engaged` rows carry prev_sid + target_pane — the same fact, durably. Measured
  #      over the live log: 158/158 prev_sid values UUID-shaped, 158 distinct, 0 resolving to more
  #      than one pane. (`firing_sid` is NOT usable here despite its name: 0 of 270 are UUID-shaped,
  #      it holds a PANE id.)
  #      This is a RECOVERY, not a widening: it is keyed on the DEAD sid itself, so it can never
  #      reach a marker belonging to another session, and marker_owns_sid still guards what it finds.
  if [[ -z "$pane" ]]; then
    local hlog="${CC_HANDOFF_LOG:-$HOME/.claude/logs/handoffs.jsonl}"
    local hrow want
    want="\"prev_sid\":\"$sid\""
    if [[ -f "$hlog" ]]; then
      # newest row wins; `|| true` because a no-match grep must not trip set -e/pipefail here
      hrow=$(grep -F "$want" "$hlog" 2>/dev/null | tail -1) || true
      if [[ -n "${hrow:-}" ]]; then
        pane=$(printf '%s' "$hrow" | grep -oE '"target_pane":"[^"]*"' | head -1) || true
        pane=${pane#*:}; pane=${pane#\"}; pane=${pane%\"}
      fi
    fi
    # `grep . >/dev/null`, NOT `grep -q .`: under `set -o pipefail` an early-exiting consumer
    # SIGPIPEs its producer, so the pipeline can read FALSE on the very input it just matched.
    # (The two arms above predate the pipefail ratchet and are grandfathered at their current count;
    # this arm is new, so it uses the drained form.)
    if [[ -n "$pane" ]] \
       && find "$tdir" -maxdepth 1 -name "$pane.json" -mmin -30 2>/dev/null | grep . >/dev/null \
       && marker_owns_sid "$tdir/$pane.json" "$sid"; then
      printf 'RECYCLE\tdeliberate-teardown\t%s\t%s' "${kb:-0}" "${recs:-0}"; return 0
    fi
  fi
  # 2) DELIBERATE RECYCLE — the disposition/self-close phrases and the successor-brief
  #    text a session emits when it CHOOSES to recycle (incl. the brief written into the
  #    trailing last-prompt record). Bare "handoff-fire"/"self-close" are excluded —
  #    infra-dev sessions discuss them without firing, which would mask a real crash.
  body=$(tail -c 16000 "$t" 2>/dev/null || true)
  # DRAINED, never `grep -q`: $body is a 16,000-byte tail — a quarter of the 64 KiB pipe buffer and
  # the largest feed of the thirteen — and inversion misreads a deliberate self-close as a CRASH.
  if printf '%s' "$body" | grep -iE 'DISPOSITION: *CLOSE|Firing as the last action|the recycle IS the continuation|retiring this pane|becomes the successor|a recycle keeps|recycle keeps (this|the) pane|recycled at [0-9]+%|— recycled|Context Stewardship free-win' >/dev/null; then
    printf 'RECYCLE\tdeliberate-self-close\t%s\t%s' "${kb:-0}" "${recs:-0}"; return 0
  fi
  # 2.5) HEADLESS END — a session registered with no tty is a `claude -p` run whose CALLER sees its
  #      exit directly; with no close record there is no evidence of a crash, and the transcript-size
  #      guess below paged an ordinary headless end as suspected-oom-large-context (2026-10-22).
  if [[ -z "$cr_open" ]] && [[ -z "$(find_close_record "$pid" 2>/dev/null || true)" ]]; then
    local reg_now; reg_now=$(last_registration "$sid")
    if [[ "${reg_now%% *}" == none ]]; then
      printf 'RECYCLE\theadless-ended\t%s\t%s' "${kb:-0}" "${recs:-0}"; return 0
    fi
  fi
  # 3) otherwise a genuine but un-attributed crash (large context ⇒ likely OOM)
  local cause="abrupt-unknown"
  [[ "${kb:-0}" -gt 4096 ]] && cause="suspected-oom-large-context"
  # …and if the close record said 143, the cause is not unknown at all: something sent SIGTERM and
  # left no teardown marker. Naming it is what makes the row actionable — `abrupt-unknown` reads as
  # "we have no idea", while external-sigterm says WHICH question to ask (who sent it).
  [[ "$ec" == "143" ]] && cause="external-sigterm"
  # …and an ORPHANED OPEN RECORD outranks both guesses above, because it is not a guess. `abrupt-
  # unknown` and `suspected-oom-large-context` are both inferences from what is MISSING (no record;
  # a big transcript); this one is read off a file the wrapper wrote while it was alive. It answers
  # a different question from `external-sigterm` — that arm needs an exit code, which an open record
  # by construction does not have — so the two can never contend.
  [[ -n "$cr_open" ]] && cause="killed-before-report"
  printf 'CRASH\t%s\t%s\t%s' "$cause" "${kb:-0}" "${recs:-0}"
}

# GC the teardown marker(s) for a session. Called ONLY from the owner-guarded pidfile-rm
# blocks below — we just deleted OUR pid's pidfile, so the recycle/self-close is fully handled
# and the marker has served its purpose. Removes the sid-keyed marker and, if cheaply resolvable
# via the session registry, its pane-keyed alias. Never call elsewhere: a stale marker is
# harmless (30-min freshness window), but deleting one mid-recycle could unmask a real crash.
gc_teardown_marker() {
  local sid="$1" pid="${2:-}"
  local tdir="${CC_TEARDOWN_DIR:-$HOME/.claude/watchdog/teardown}"
  local reg_dir="${CC_REGISTRY_DIR:-$HOME/.claude/cc-registry}"
  local reg_hit pane
  rm -f "$tdir/$sid.json" 2>/dev/null || true
  # …and the pid-keyed marker cc-teardown now writes (bin/cc-teardown write_teardown_marker). It is
  # collected here rather than left to the freshness window for the same reason as the two above:
  # this store has no sweeper, and a key that is only ever written accumulates one file per
  # retirement forever. The pid is the one this death was handled FOR, so this can never reach a
  # marker written for a live session that later reused the number.
  if [[ -n "$pid" ]]; then rm -f "$tdir/$pid.json" 2>/dev/null || true; fi
  reg_hit=$(grep -lE "\"session_id\":[[:space:]]*\"$sid\"" "$reg_dir"/*.json 2>/dev/null | head -1) || true
  [[ -n "$reg_hit" ]] || return 0
  pane=$(basename "$reg_hit" .json)
  rm -f "$tdir/$pane.json" 2>/dev/null || true
}

# ── ASSIGNEE HARVEST (leg a) ─────────────────────────────────────────────────────
# HARVEST BEFORE TEARDOWN. When the lead dies, its assignees' final reports exist in exactly one
# place: their own transcript JSONL on disk. They are NOT in any inbox and never will be — a
# named assignee's final text is "the return to lead", and the lead only ever receives
# `idle_notification {idleReason: available}`; the report itself is never delivered as a message
# (memory: wave-report-harvest-from-disk, measured across a full 16-agent wave). A crashed lead
# cannot receive even that. So the ONLY correct source is disk truth, and the ONLY correct
# ordering is harvest-then-teardown: cc-teardown closes the pane, and a closed pane's session is
# gone — a report not harvested first is a report lost. Observed 2026-07-26 on team
# session-a3f68174: 8 assignees, every final report reachable only by hand-digging transcripts.
#
# member_transcript <name> <cwd> → path of the assignee's transcript, or empty.
# TWO ordered strategies, both keyed on disk truth, never on a notification:
#   1. CWD-SLUG (cheap, targeted). CC stores a session's transcript under
#      <account>/projects/<cwd-with-slashes-turned-to-dashes>/<sessionId>.jsonl, and a team member
#      carries its own `.cwd`. That maps straight to the directory to search, so this never walks
#      the 5638-session corpus. Within it, the file is disambiguated by `"agentName":"<name>"` —
#      several assignees can share one worktree (measured: wt-pool-3 held sq-a1 and sq-c1).
#   2. BOUNDED MACHINE-WIDE (fallback) for an assignee whose cwd was force-removed by the dying
#      lead — exactly the observed incident — so the slug dir may not resolve. Time-capped, and a
#      cap that expires yields NO path: it ABSTAINS rather than guessing a wrong transcript.
# NEWEST wins: an assignee that was re-fired has more than one transcript and only the last one
# carries its final report.
#
# Returns empty for BOTH "proven absent" and "could not look" — the CALLER distinguishes them
# (see harvest_member), because a missing transcript is a real outcome (bsm-schema, joined
# 2026-06-07: worktree and transcript both long rotated away) while an unreadable probe is not.
LCW_ACCOUNT_BASES_DEFAULT="$HOME/.claude $HOME/.claude-secondary $HOME/.claude-tertiary $HOME/.claude-quaternary"
member_transcript() {
  local name="$1" cwd="${2:-}" base slug d hit newest="" bases
  bases="${CC_ACCOUNT_BASES:-$LCW_ACCOUNT_BASES_DEFAULT}"
  [[ -n "$name" ]] || return 0
  # 1 — cwd-slug dirs. Both the raw cwd and its PHYSICAL resolution are tried: the transcript dir
  # is named from the cwd CC recorded, and a worktree reached through a symlinked parent records
  # differently than `pwd -P` reports. Trying both only ever ADDS a candidate.
  if [[ -n "$cwd" ]]; then
    local pcwd; pcwd=$(cd "$cwd" 2>/dev/null && pwd -P 2>/dev/null) || pcwd=""
    # SLUG ENCODING: CC replaces BOTH '/' and '.' with '-'. The dot matters here and is easy to
    # miss — every dispatch worktree lives under `.worktrees`, which encodes to `--worktrees`, so a
    # slash-only slug resolves NOTHING for exactly the paths this harvest runs against. Measured
    # against a real assignee (sq-c1-registers, wt-pool-3): slash-only → no match, slash+dot →
    # the transcript. A detector that silently finds nothing looks identical to "no report exists"
    # (memory: effect-read-predicate-red-proof — positive-control every detector).
    local dcwd="${cwd//\//-}" dpcwd="${pcwd//\//-}"
    for base in $bases; do
      for slug in "${dcwd//./-}" "${dpcwd//./-}"; do
        [[ -n "$slug" ]] || continue
        d="$base/projects/$slug"
        [[ -d "$d" ]] || continue
        while IFS= read -r hit; do
          [[ -n "$hit" ]] || continue
          if [[ -z "$newest" || "$hit" -nt "$newest" ]]; then newest="$hit"; fi
        # BOUNDED for the same reason as the strategy-2 fallback below: one project dir holds every
        # transcript for that cwd, so this grep's cost is set by the corpus, not by us. Strategy 2
        # was bounded and this one was not, which left the cheaper-looking path as the unbounded one.
        done < <(lcw_bounded "${LCW_HARVEST_SCAN_TIMEOUT_S:-20}" grep -l "\"agentName\":\"$name\"" "$d"/*.jsonl 2>/dev/null || true)
      done
    done
  fi
  [[ -n "$newest" ]] && { printf '%s\n' "$newest"; return 0; }
  # 2 — bounded machine-wide fallback (the lead force-removed the cwd). BOUNDED: this grep walks
  # every account's project corpus, and an unbounded walk inside a crash path would hang the
  # watchdog exactly when it is most needed (memory: bounding-external-calls). A cut yields no
  # path ⇒ abstain, never a wrong one.
  #
  # Seam: LCW_HARVEST_FALLBACK — UNSET ⇒ fallback runs. SET, including set to EMPTY ⇒ honored
  # verbatim, so `LCW_HARVEST_FALLBACK=` genuinely disables the corpus walk. `${VAR:-}` cannot tell
  # unset from set-empty, and a seam that cannot turn a thing OFF is not a seam (memory:
  # claimed-outcome-vs-checked-outcome). This also lets strategy 1 be tested in ISOLATION — without
  # it the fallback silently rescues a broken slug encoding and the dot-encoding bug looks fixed.
  if [[ -n "${LCW_HARVEST_FALLBACK+set}" && -z "${LCW_HARVEST_FALLBACK}" ]]; then return 0; fi
  local roots=() found
  for base in $bases; do [[ -d "$base/projects" ]] && roots+=("$base/projects"); done
  [[ ${#roots[@]} -gt 0 ]] || return 0
  if [[ -n "$LCW_OSA_TB" && -x "$LCW_OSA_TB" ]]; then
    found=$("$LCW_OSA_TB" -k 5 "${LCW_HARVEST_SCAN_TIMEOUT_S:-20}" \
      grep -rl --include='*.jsonl' "\"agentName\":\"$name\"" "${roots[@]}" 2>/dev/null || true)
  else
    found=$(grep -rl --include='*.jsonl' "\"agentName\":\"$name\"" "${roots[@]}" 2>/dev/null || true)
  fi
  while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    if [[ -z "$newest" || "$hit" -nt "$newest" ]]; then newest="$hit"; fi
  done <<< "$found"
  [[ -n "$newest" ]] && printf '%s\n' "$newest"
  return 0
}

# last_assistant_text <transcript> — the assignee's FINAL report: the last assistant message's
# joined text blocks. One streaming pass in python3 (a transcript runs to hundreds of MB and must
# never be slurped). Prints nothing when the file holds no assistant text.
#
# Why the LAST assistant record and not a tail-grep: a mid-run harvest catches interim narration
# rather than the report (measured 442 chars mid-run vs 16,152 final), and tool_use/thinking
# blocks carry no `.text`, so only `content[].text` on `message.role=="assistant"` is joined.
last_assistant_text() {
  local t="$1"
  [[ -n "$t" && -f "$t" ]] || return 0
  # BOUNDED: this streams a transcript whose size is not ours to bound (hundreds of MB), on the
  # death path, in the process that is the last thing running for the dead session. A cut costs one
  # assignee's report text; a hang costs every teammate the crash handler exists to notify.
  lcw_bounded "${LCW_REPORT_READ_TIMEOUT_S:-30}" "${LCW_PYTHON_BIN:-python3}" - "$t" <<'PY' 2>/dev/null || true
import json, sys
last = ""
try:
    with open(sys.argv[1], "r", errors="replace") as fh:
        for line in fh:
            line = line.strip()
            if not line or '"assistant"' not in line:
                continue
            try:
                rec = json.loads(line)
            except Exception:
                continue
            msg = rec.get("message") or {}
            if msg.get("role") != "assistant":
                continue
            content = msg.get("content")
            if isinstance(content, str):
                text = content
            elif isinstance(content, list):
                text = "\n".join(
                    b.get("text", "") for b in content
                    if isinstance(b, dict) and b.get("type") == "text" and b.get("text")
                )
            else:
                continue
            if text.strip():
                last = text
except Exception:
    pass
sys.stdout.write(last)
PY
}

# harvest_team_reports <team_dir> <sid> — leg (a). Enumerate the team's assignees from
# config.json and write each one's final report out of its transcript into <team_dir>/HARVEST/.
#
# RUNS BEFORE ANY TEARDOWN, and that ordering is the whole point: cc-teardown closes the pane and
# kills the process, and a closed pane cannot be harvested. Harvest is also strictly
# non-destructive — it only ever creates files under <team_dir>/HARVEST/ — so it is safe to run
# unconditionally on a positive death verdict, and it is what makes the close leg safe to run at
# all (the report is already on disk before anything is reaped).
#
# Emits status.tsv: member <TAB> paneId <TAB> state <TAB> bytes <TAB> transcript. THREE states,
# because "no report" has two different causes and only one of them is a real outcome:
#   HARVESTED     report text recovered and written.
#   EMPTY         transcript found, but it holds no assistant text (assignee died before its
#                 first turn) — a real, proven outcome.
#   NO-TRANSCRIPT no transcript resolved: either genuinely rotated away (bsm-schema, joined
#                 2026-06-07) or the probe could not look. NOT proof a report never existed.
# Leg (b) reads this file and closes ONLY panes whose row is HARVESTED or EMPTY — a
# NO-TRANSCRIPT member is never torn down, because tearing it down would destroy the last place
# its report could still be found.
harvest_team_reports() {
  local team_dir="$1" sid="$2"
  local cfg="$team_dir/config.json"
  [[ -f "$cfg" ]] || { echo "[watchdog $sid] harvest: no config.json in $team_dir"; return 0; }
  local hdir="$team_dir/HARVEST"
  mkdir -p "$hdir" 2>/dev/null || true
  local status="$hdir/status.tsv"
  : > "$status" 2>/dev/null || true

  local n_h=0 n_e=0 n_n=0 name pane cwd
  while IFS=$'\t' read -r name pane cwd; do
    [[ -n "$name" ]] || continue
    [[ "$name" == "team-lead" ]] && continue
    [[ "$pane" == "-" ]] && pane=""      # '-' is jq's placeholder for absent (see the query above)
    [[ "$cwd"  == "-" ]] && cwd=""
    local tpath report_file text bytes=0 state
    tpath=$(member_transcript "$name" "$cwd" 2>/dev/null || true)
    if [[ -z "$tpath" ]]; then
      state="NO-TRANSCRIPT"; n_n=$((n_n + 1))
    else
      text=$(last_assistant_text "$tpath" 2>/dev/null || true)
      if [[ -n "$text" ]]; then
        report_file="$hdir/$name.md"
        {
          echo "# Final report — $name"
          echo
          echo "- **Team**: $(basename "$team_dir")"
          echo "- **Lead session**: $sid (crashed)"
          echo "- **Pane**: ${pane:-?}"
          echo "- **Worktree (cwd)**: ${cwd:-?}"
          echo "- **Transcript**: $tpath"
          echo "- **Harvested**: $(date '+%Y-%m-%d %H:%M:%S') — from DISK TRUTH (last assistant"
          echo "  message in the transcript), never from a notification: a named assignee's final"
          echo "  text is never delivered as a message, and this lead crashed before it could"
          echo "  receive even an idle notification."
          echo
          echo "---"
          echo
          printf '%s\n' "$text"
        } > "$report_file" 2>/dev/null || true
        bytes=$(wc -c < "$report_file" 2>/dev/null | tr -d ' ') || bytes=0
        state="HARVESTED"; n_h=$((n_h + 1))
      else
        state="EMPTY"; n_e=$((n_e + 1))
      fi
    fi
    # '-' placeholders, never an EMPTY field: `IFS=$'\t' read` COALESCES consecutive whitespace-IFS
    # runs (tab included), so an in-process member with no pane would emit two adjacent tabs, drop
    # the empty column and shift every later field LEFT — the reader would see state="HARVESTED" as
    # the PANE and try to tear it down. Caught by test (ix).
    printf '%s\t%s\t%s\t%s\t%s\n' "$name" "${pane:--}" "$state" "${bytes:-0}" "${tpath:--}" \
      >> "$status" 2>/dev/null || true
    echo "[watchdog $sid] harvest $name → $state (${bytes:-0}B)"
  # jq emits '-' for an absent/empty field rather than "" for the SAME reason the writer below does:
  # `IFS=$'\t' read` coalesces adjacent tabs, so a member with no tmuxPaneId (an in-process
  # assignee) would have its CWD read as its PANE and handed to cc-teardown as a teardown target.
  # Caught by test (ix-b) asserting the producer's literal emission.
  done < <(jq -r '.members[]? | select(.name != "team-lead")
                  | [ .name,
                      ((.tmuxPaneId // "") | if . == "" then "-" else . end),
                      ((.cwd        // "") | if . == "" then "-" else . end) ] | @tsv' \
                 "$cfg" 2>/dev/null || true)

  echo "[watchdog $sid] harvest complete: $n_h harvested, $n_e empty, $n_n no-transcript → $hdir"
  return 0
}

# close_orphaned_panes <team_dir> <sid> — leg (b). Close each orphaned assignee's pane through
# bin/cc-teardown, never raw it2/osascript: only cc-teardown re-observes both legs and treats a
# surviving pane as FAIL LOUD rather than a false success (a close that returns 0 is not a closed
# pane). Observed cost of not doing this: 8 assignees alive holding 3.4GB after their lead died.
#
# STRUCTURAL PRECONDITION — harvest first. This reads leg (a)'s status.tsv and refuses outright
# when it is missing: no harvest ⇒ no teardown, because a closed pane cannot be harvested. A
# NO-TRANSCRIPT member is NEVER closed either — its pane is the last place its report could still
# be found, and "we could not look" is not "there was nothing there".
#
# DEFAULT OFF — armed only by LCW_ORPHAN_CLOSE=1. cc-teardown's own header bars wiring it RAW into
# any hook/settings/launchd (that fires it with no gate in front = C10); cc-reaper is the one
# sanctioned PRE-GATED autonomous caller. This watchdog is spawned FROM a SessionStart hook, so
# arming an automatic pane-killer here by default is precisely the wiring that rule forbids — and
# a newly-wired MUTATING step defaults OFF regardless (memory: append-only-store-safety-rules).
# Arming is therefore an operator step, staged in autonomy/pending-activation/.
#
# UNARMED IS NOT SILENT. The enumeration, the eligibility gate and the plan all still run and are
# logged and written to close-plan.tsv, so the un-reaped panes are visible and countable instead
# of the feature looking done while abstaining ~100% of the time (memory:
# feature-durability-mechanism-not-memory — a built feature must FAIL LOUD when inert).
close_orphaned_panes() {
  local team_dir="$1" sid="$2"
  local hdir="$team_dir/HARVEST" status="$team_dir/HARVEST/status.tsv"
  if [[ ! -f "$status" ]]; then
    echo "[watchdog $sid] close: REFUSE — no HARVEST/status.tsv (harvest never ran); a closed pane cannot be harvested"
    return 0
  fi
  local armed=0
  [[ "${LCW_ORPHAN_CLOSE:-0}" == "1" ]] && armed=1
  # Seam: LCW_TEARDOWN_BIN — UNSET ⇒ resolve one. SET, including set to EMPTY ⇒ honored verbatim, so
  # `LCW_TEARDOWN_BIN=` genuinely disables the actuator. `${VAR:-}` cannot tell unset from set-empty
  # (memory: claimed-outcome-vs-checked-outcome), and here that gap is not cosmetic: a `${VAR:-}`
  # read falls through to `command -v cc-teardown`, which resolves the operator's REAL
  # ~/.claude/bin/cc-teardown — so a caller intending to DISABLE the actuator would instead fire it
  # at live panes. Caught by test (xii) doing exactly that.
  local tdbin
  if [[ -n "${LCW_TEARDOWN_BIN+set}" ]]; then
    tdbin="$LCW_TEARDOWN_BIN"
  else
    tdbin=$(command -v cc-teardown 2>/dev/null || true)
    [[ -n "$tdbin" ]] || { [[ -x "$HOME/.claude/bin/cc-teardown" ]] && tdbin="$HOME/.claude/bin/cc-teardown"; }
  fi
  local plan="$hdir/close-plan.tsv"; : > "$plan" 2>/dev/null || true
  local n_elig=0 n_skip=0 n_ok=0 n_defer=0 n_refuse=0 n_fail=0 n_unres=0 n_indet=0
  local member pane state bytes tpath

  while IFS=$'\t' read -r member pane state bytes tpath; do
    [[ -n "$member" ]] || continue
    # '-' is the writer's placeholder for an absent value (see harvest_team_reports: an EMPTY TSV
    # field would be coalesced away by `read` and shift every later column left).
    [[ "$pane"  == "-" ]] && pane=""
    [[ "$tpath" == "-" ]] && tpath=""
    # Not a closable pane: the lead's own sentinel, or an in-process assignee with no pane.
    if [[ -z "$pane" || "$pane" == "leader" ]]; then
      echo "[watchdog $sid] close: skip $member (no pane / in-process)"
      n_skip=$((n_skip + 1)); continue
    fi
    # NEVER close what was not harvested — the pane is the last place the report survives.
    if [[ "$state" == "NO-TRANSCRIPT" ]]; then
      echo "[watchdog $sid] close: SKIP $member pane=$pane — NO-TRANSCRIPT (report unrecovered; refusing to destroy the last copy)"
      printf '%s\t%s\t%s\t%s\n' "$member" "$pane" "SKIP-UNHARVESTED" "" >> "$plan" 2>/dev/null || true
      n_skip=$((n_skip + 1)); continue
    fi
    n_elig=$((n_elig + 1))
    # POSITIVE done-evidence, derived — never inferred from silence. Names the death evidence and
    # the harvest that already happened, so cc-teardown's gate is judging facts, not a claim.
    local ev="lead-crash-watchdog: lead session $sid DEAD (positive evidence: watchdog pid failed kill -0); assignee '$member' orphaned with no lead to report to; final report HARVESTED to $hdir/$member.md (${bytes:-0}B, state=$state) from $tpath BEFORE teardown"
    if (( armed )) && [[ -n "$tdbin" ]]; then
      local trc=0 tout=""
      # --assignee-of: an assignee pane has NO session-registry row (134/134 measured across every
      # team dir on this machine), so a bare call could only ever come back REFUSE unknown-target —
      # which the rc==2 arm below counted as a *trusted* policy refusal. That made this whole leg a
      # 100%-abstain no-op: built, tested, landed, incapable of closing one pane. The flag lets
      # cc-teardown re-prove the target from positive it2 + argv evidence instead.
      # --assignee-sid: leg (a) already resolved this member's transcript, and the file is named
      # <sid>.jsonl — so we can hand cc-teardown the assignee's OWN session id. Without it the
      # operator-adoption belt silently no-ops (find_transcript "" returns nothing), i.e. a safety
      # gate would be BYPASSED rather than passed. Supply the identity; keep the gate armed.
      local asid=""
      [[ -n "$tpath" ]] && { asid="$(basename "$tpath")"; asid="${asid%.jsonl}"; }
      # Captured, not discarded: the outcome has to be CHECKED, not claimed. rc 2 alone cannot
      # distinguish "a safety gate declined" from "the actuator could not even SEE the target"
      # (memory: claimed-outcome-vs-checked-outcome — parse a structured reason token).
      # BOUNDED: cc-teardown drives AppleEvents into iTerm2 — the documented machine-wide wedge
      # surface this file's own osascript bound was added for (2026-07-26) — and it is called once
      # PER orphaned pane, so an unbounded hang here stalls the teardown of every later member too.
      tout=$(lcw_bounded "${LCW_TEARDOWN_TIMEOUT_S:-60}" "$tdbin" "$pane" --done-evidence "$ev" \
               --assignee-of "$sid" ${asid:+--assignee-sid "$asid"} 2>&1) || trc=$?
      case "$trc" in
        0)  n_ok=$((n_ok + 1));     echo "[watchdog $sid] close: $member pane=$pane TORN DOWN + effect-verified (rc 0)" ;;
        10) n_defer=$((n_defer + 1)); echo "[watchdog $sid] close: $member pane=$pane DEFER — cc-teardown's gate says work-unsafe (rc 10); left alone" ;;
        2)  # UNRESOLVED is NOT a policy refusal — it means our own resolution wiring is blind, the
            # exact failure that made this leg inert. It must never be absorbed into the trusted
            # refuse bucket (memory: feature-durability-mechanism-not-memory / named-failure).
            #
            # Keyed on cc-teardown's VERDICT TOKEN — `verdict=<D> reason_kind=<k> exit=<n> …`, one
            # line per decision, emitted by its record() so no branch can omit it. Prose is not a
            # protocol: this arm used to substring-match message text, which meant a reworded
            # refusal silently changed which bucket a pane landed in. The token is the contract.
            local trk=""
            if [[ "$tout" =~ verdict=[A-Z-]+[[:space:]]+reason_kind=([a-z-]+) ]]; then
              trk="${BASH_REMATCH[1]}"
            elif [[ "$tout" =~ reason_kind=([a-z-]+) ]]; then
              # PRE-TOKEN FALLBACK. Both files are symlinks into one checkout and land together, so
              # skew should not arise — but `command -v cc-teardown` can resolve a copy this repo
              # does not control, and an older one prints reason_kind only inside its prose. Without
              # this arm that skew would silently demote every blind outcome into the trusted refuse
              # bucket: quieter, and quiet is the wrong direction for a wiring failure.
              trk="${BASH_REMATCH[1]}"
            fi
            case "$trk" in
              # "the actuator could not SEE the target" — a wiring/load problem, retryable, and NOT
              # a verdict any safety gate reached.
              unknown-target|assignee-unproven|target-not-a-pane-uuid|absence-uncorroborated)
                n_unres=$((n_unres + 1))
                echo "[watchdog $sid] close: $member pane=$pane UNRESOLVED ($trk) — cc-teardown could not SEE this pane (not a safety verdict; the close leg is BLIND here): ${tout##*cc-teardown: }" ;;
              # A POSITIVE finding, not a blind spot: the pane looked absent to iTerm2 but still hosts
              # live processes. Counted with UNRESOLVED because the outcome is the same — still
              # running, no gate judged it — and named separately because the cause is the opposite.
              absence-contradicted)
                n_unres=$((n_unres + 1))
                echo "[watchdog $sid] close: $member pane=$pane STILL OCCUPIED — the pane is NOT gone; iTerm2 omitted it but its processes are alive: ${tout##*cc-teardown: }" ;;
              *)
                n_refuse=$((n_refuse + 1)); echo "[watchdog $sid] close: $member pane=$pane REFUSE${trk:+ ($trk)} (rc 2); left alone" ;;
            esac ;;
        5)  n_fail=$((n_fail + 1)); echo "[watchdog $sid] close: $member pane=$pane FAIL LOUD — acted but the pane SURVIVED (rc 5)" ;;
        6)  # INDETERMINATE — the process is gone but cc-teardown could not READ the pane's fate (blind
            # or cut enumerator). Distinct from rc 5 BY CONSTRUCTION: 5 is the definite claim "the pane
            # survived", and this leg is armed (LCW_ORPHAN_CLOSE=1) and autonomous, so counting "I could
            # not see" as a survivor would have it log failures on successful reaps and escalate on them.
            # Not n_unres either — that bucket's summary says "STILL RUNNING and no gate judged them";
            # here a gate DID judge and the process IS dead. Own counter, own words.
            n_indet=$((n_indet + 1))
            echo "[watchdog $sid] close: $member pane=$pane INDETERMINATE — process gone, pane fate UNREADABLE (rc 6); NOT a survivor claim, re-observe before acting" ;;
        124) # The bound above CUT the call — timeout(1)'s own rc, not cc-teardown's. A THIRD state:
             # we have NO verdict at all, and the pane may or may not have been acted on. It must not
             # land in n_fail ("acted, pane survived" — a claim we cannot make) nor in n_refuse ("a
             # gate declined" — nothing declined). Counted with the UNRESOLVED bucket, whose meaning
             # is exactly "no safety gate judged this pane and it is still running", and named
             # distinctly in the line so the cause is not lost.
             n_unres=$((n_unres + 1))
             echo "[watchdog $sid] close: $member pane=$pane NO-VERDICT — cc-teardown exceeded ${LCW_TEARDOWN_TIMEOUT_S:-60}s and was cut (rc 124); pane state UNKNOWN, left alone" ;;
        *)  n_fail=$((n_fail + 1)); echo "[watchdog $sid] close: $member pane=$pane cc-teardown rc=$trc (unexpected); left alone" ;;
      esac
      printf '%s\t%s\t%s\t%s\n' "$member" "$pane" "rc=$trc" "$ev" >> "$plan" 2>/dev/null || true
    else
      local why="unarmed"; [[ -n "$tdbin" ]] || why="cc-teardown-unavailable"
      echo "[watchdog $sid] close: WOULD-CLOSE $member pane=$pane ($why — set LCW_ORPHAN_CLOSE=1 to arm)"
      printf '%s\t%s\t%s\t%s\n' "$member" "$pane" "WOULD-CLOSE($why)" "$ev" >> "$plan" 2>/dev/null || true
    fi
  done < "$status"

  if (( armed )); then
    echo "[watchdog $sid] close complete: $n_ok torn down, $n_defer defer, $n_refuse refuse, $n_unres UNRESOLVED, $n_indet INDETERMINATE, $n_fail FAIL, $n_skip skipped"
    # A leg that resolved NOTHING is not a leg that had nothing to do. Say so at the same volume as
    # a failure, so inertness can never again read as a clean run (this is the signal whose absence
    # let 100%-abstain look like success for three days).
    if (( n_unres > 0 )); then
      echo "[watchdog $sid] close BLIND: $n_unres of $n_elig eligible pane(s) could not be resolved by cc-teardown — these assignees are STILL RUNNING and no safety gate judged them; this is a wiring failure, not a verdict"
    fi
  else
    echo "[watchdog $sid] close UNARMED: $n_elig orphaned pane(s) left RUNNING, $n_skip skipped — plan in $plan (arm: LCW_ORPHAN_CLOSE=1)"
  fi
  return 0
}

# Test/debug entrypoints for the two team-level legs (both are top-level for the same reason the
# classify helpers are: the daemon subshell inherits them AND they stay unit-testable).
if [[ "${1:-}" == "--harvest-team" ]]; then
  harvest_team_reports "${2:-}" "${3:-}"; exit 0
fi
if [[ "${1:-}" == "--close-panes" ]]; then
  close_orphaned_panes "${2:-}" "${3:-}"; exit 0
fi

# Test/debug entrypoint: resolve+print one member's harvested report (name, cwd).
if [[ "${1:-}" == "--harvest-member" ]]; then
  _t=$(member_transcript "${2:-}" "${3:-}")
  [[ -n "$_t" ]] || { echo "NO-TRANSCRIPT"; exit 0; }
  echo "TRANSCRIPT $_t"; last_assistant_text "$_t"; echo; exit 0
fi

# Test/debug entrypoint (CC never passes args to this SessionStart hook): classify a
# session id (+ optional pid, to join its close-record) and exit, without spawning the
# daemon or reading stdin.
# ── death_loss_facts <sid> <transcript-path> ────────────────────────────────────────────────────
# Emits `goal=<live|none|unknown>\twf=<N|?>` — the two facts that make an external death URGENT
# rather than merely notable, and the two the incident's page had to invent from scratch.
#
# The goal answer comes from hooks/lib/goal-state.sh — the ONE arbiter for the goal_status record
# dictionary. Re-deriving `met`/`failed`/`sentinel` here is exactly how two readers of the same
# records start disagreeing (MEMORY.md make-the-actuator-the-arbiter), and this reader has no claim
# to a second opinion. Unreadable ⇒ `unknown`, never `none`: `none` is the POSITIVE finding "this
# session never armed a goal", and a read that did not happen must not launder into it
# (the same absence-vs-zero split wrap-ledger.sh draws at its GOAL_SRC="error").
death_loss_facts() {
  local sid="$1" tpath="${2:-}" goal="unknown" wf="?" lib tsv state wfdir
  if [[ -n "$tpath" && -f "$tpath" ]]; then
    lib="$(dirname "${BASH_SOURCE[0]}")/lib/goal-state.sh"
    [[ -f "$lib" ]] || lib="$HOME/.claude/hooks/lib/goal-state.sh"
    if [[ -f "$lib" ]]; then
      # `timeout` takes a COMMAND, not a shell function, so the read runs in a child that sources
      # the lib itself. Single quotes are the point: $1/$2 are the CHILD's positional parameters,
      # so no value is ever re-parsed as script text.
      # shellcheck disable=SC2016  # the single quotes are the POINT: $1/$2 are the CHILD's
      # positional parameters, passed as arguments, so no value is ever re-parsed as script text.
      # Same idiom and same rationale as scripts/wrap-ledger.sh's call into this lib.
      tsv=$(lcw_bounded "${LCW_PROBE_TIMEOUT_S:-5}" bash -c '. "$1"; goal_liveness "$2"' _ "$lib" "$tpath" 2>/dev/null || true)
      state=$(printf '%s' "$tsv" | cut -f1)
      # The vocabulary is READ OUT OF THE LIB (goal-state.sh:99 — `failed` / `cleared` / `live`),
      # not guessed. Guessing it cost a red test here: the obvious spelling for an achieved goal is
      # "met", the lib emits "cleared", and a `*)`-arm default would have silently rendered every
      # achieved goal as "unknown" — a fail-open that looks like data.
      case "$state" in
        live)            goal="live" ;;
        cleared|failed)  goal="none" ;;
        *)
          # The lib returns rc 1 for BOTH "unreadable" and "no goal was ever armed", so its silence
          # cannot separate them. Use its own cheap pre-filter to do it: a readable transcript with
          # no goal_status attachment anywhere is the POSITIVE finding "never armed one".
          if grep -q 'goal_status' "$tpath" 2>/dev/null; then goal="unknown"; else goal="none"; fi ;;
      esac
    fi
    # In-flight Dynamic Workflows. Their agents are IN-PROCESS, so every one of them died with the
    # lead — this count is the size of the loss, and it is the fact the team-scan branch structurally
    # cannot see (a workflow is not a team, which is why the incident took the early return).
    wfdir="$(dirname "$tpath")/$sid/subagents/workflows"
    if [[ -d "$wfdir" ]]; then
      wf=$(find "$wfdir" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
      case "$wf" in ''|*[!0-9]*) wf="?" ;; esac
    else
      wf=0
    fi
  fi
  printf '%s\t%s\n' "$goal" "$wf"
}

# ── death_page_line <sid> <pid> <cause> <exit> <signal> <transcript> ────────────────────────────
# The page itself: ONE line, because cc-notify collapses newlines to keep its cursor counting
# messages rather than physical lines. It leads with the fact that changes what the operator does —
# a session was KILLED, it did not exit — then the loss, then where to read the rest. The sid is
# given in full: an 8-char prefix is not greppable against a transcript path, and the incident's
# notification proved that the hard way.
death_page_line() {
  local sid="$1" pid="$2" cause="$3" ec="${4:-}" sig="${5:-}" tpath="${6:-}" facts goal wf what
  facts=$(death_loss_facts "$sid" "$tpath")
  goal=$(printf '%s' "$facts" | cut -f1)
  wf=$(printf '%s' "$facts" | cut -f2)
  case "$cause" in
    external-sigterm) what="was KILLED by an external SIGTERM (exit ${ec:-143}, signal ${sig:-15}) — it did NOT exit" ;;
    jetsam-oom)       what="was KILLED by the OOM killer (jetsam)" ;;
    # The evidence is re-read rather than passed: the record and its ended_at are all it needs.
    terminal-died)
      local hcr hev
      hcr=$(find_close_record "$pid" 2>/dev/null) || hcr=""
      hev=$(hup_corroboration "$hcr" "$(utc_stamp_epoch "$(close_record_field "$hcr" ended_at)")" 2>/dev/null) || hev=""
      what="died with its terminal — kitty went away and SIGHUPed every pane (${hev:-sibling HUP deaths or a kitty crash report}) — it did NOT exit on its own" ;;
    # NOT a crash: cc-teardown collected this session and then killed it. The page exists only so a
    # reader who reaches this line by another route is told that, and told not to resume it.
    retired-by-desk)  what="was RETIRED deliberately by cc-teardown after its work was collected — this is NOT a crash" ;;
    retired-teammate) what="was a teammate SHUT DOWN by its lead, its work already handed to the lead — this is NOT a crash" ;;
    # The one thing this cause DOES say is that the launcher wrapper was alive and was destroyed
    # with it, so the exit status was never written — which is why no exit code appears here.
    closed-by-other-session)
      local cbo; cbo=$(closed_by_other "$sid" "$(date +%s)" 2>/dev/null || true)
      [[ -n "$cbo" ]] || cbo=$(closed_by_other "$sid" "$(resolve_death_epoch "$sid" "$pid" 2>/dev/null)" 2>/dev/null || true)
      what="was CLOSED by another session (${cbo:0:8}) that typed /exit into its pane from inside it — it did NOT choose to exit" ;;
    killed-before-report) what="was DESTROYED before its launcher could record an exit status (its close-record is still open) — it did NOT exit" ;;
    *)                what="died abruptly (cause: $cause${ec:+, exit $ec}${sig:+, signal $sig})" ;;
  esac
  # THE RECOVERY CLAUSE IS PER-CAUSE, because for one cause it is ACTIVELY WRONG. A `retired-by-desk`
  # death is a cc-teardown retirement: its work was landed and content-verified and its custody row
  # returned BEFORE the kill, so `cc-husk-sweep --resume` would restart a finished session in a
  # worktree and duplicate completed work. A page that prescribes a harmful action is worse than
  # silence, so this cause names no recovery command at all.
  #
  # A retirement is also classified RECYCLE (classify_death arm 0), and surface_death pages only
  # CRASH — so on the live path this line is never even built. It is written anyway because
  # death_page_line is reachable independently (the --surface-death entrypoint, and any future
  # caller), and a page shape that CAN emit `--resume` for a retired session is a loaded gun whether
  # or not today's single caller pulls it.
  local recover="Its pane is still open at a live shell and looks EXACTLY like a clean /exit, so nothing on screen says this happened. Recover with cc-husk-sweep --resume (it resolves the session AND its account; the pane's own printed claude --resume line uses the default account and cannot see another store's transcript)."
  case "$cause" in
    retired-by-desk) recover="Its pane was closed by that retirement and its work was landed before the kill — there is NOTHING to recover here and it must NOT be resumed." ;;
    closed-by-other-session) recover="Its pane is gone with it. Resume it in a pane of its own with its account's launcher (cc-find ${sid:0:8} names the store): <launcher> --resume $sid. Not cc-husk-sweep: its registry row may already name another session's pane." ;;
    retired-teammate) recover="Its lead ordered this end (shutdown_request or TaskStop) — there is nothing to recover or re-spawn. Close its pane." ;;
  esac
  # THE EVIDENCE CLAUSE IS CONDITIONAL, because the close-record it names is frequently ABSENT and
  # naming it unconditionally sends the reader to an empty path. Measured 2026-09-08 09:24 (backlog
  # 501824eda094): four sessions died abrupt-unknown in 72 seconds (pids 67534, 1143, 28582, 64734)
  # and the page cited a close-record for each; the store was healthy — 1,870 records, newest minutes
  # old — and held ZERO records for all four. A reader who follows the path finds nothing and cannot
  # tell an absent record from a wrong path, which are opposite diagnoses. The absence is itself the
  # finding: no record means the process died before its launcher wrapper could write one, which
  # CONFIRMS an abrupt death rather than leaving it unexplained. So the page states which of the two
  # it is, and when a record DOES exist it names the resolved file rather than a glob. Both
  # paths are ABSOLUTE ($HOME-expanded): a tilde does not expand inside quotes (SC2088), and an
  # absolute path is what the reader can paste — which is the whole point of the clause.
  local crec ev
  crec=$(find_close_record "$pid" 2>/dev/null || true)
  if [[ -n "$crec" && -f "$crec" ]]; then
    ev="$HOME/.claude/logs/claude-crashes.jsonl (pid $pid) + $crec"
  else
    ev="$HOME/.claude/logs/claude-crashes.jsonl (pid $pid). NO close record was written for pid $pid — the process died before its launcher wrapper could record one; that absence is the finding, not a bad path."
  fi
  printf 'SESSION DEATH — %s %s. Lost: /goal=%s, in-flight workflow dir(s)=%s. %s Evidence: %s\n' \
    "$sid" "$what" "$goal" "$wf" "$recover" "$ev"
}

# ── surface_death <sid> <pid> <class> <cause> [transcript] ──────────────────────────────────────
# Deliver the page. Returns 0 = delivered, 1 = suppressed by polarity/kill-switch, 2 = the transport
# failed (which is LOGGED — a pager that silently fails is the same defect one layer down; MEMORY.md
# fail-loud-into-a-log-nobody-reads is about where that log goes, and this one goes to the same file
# the verdict does, so a delivery failure is at least joinable to the death it belongs to).
surface_death() {
  local sid="$1" pid="$2" class="$3" cause="$4" tpath="${5:-}" line rc=0 dest
  [[ "${CC_DEATH_PAGE:-1}" == "1" ]] || { log "[watchdog $sid] death page SUPPRESSED (CC_DEATH_PAGE=0)"; return 1; }
  # POLARITY: a deliberate recycle is not news. See the block comment at the top of this file.
  [[ "$class" == "CRASH" ]] || return 1
  line=$(death_page_line "$sid" "$pid" "$cause" "${6:-}" "${7:-}" "$tpath")
  if [[ ! -x "$CC_DEATH_PAGER" ]]; then
    log "[watchdog $sid] death page UNDELIVERED — no pager at $CC_DEATH_PAGER: $line"
    return 2
  fi
  # Two call shapes, chosen by the pager's NAME: cc-desk-page takes `--source` and no role (it owns
  # its own ladder); an explicit cc-notify override keeps the role address it always had.
  if [[ "${CC_DEATH_PAGER##*/}" == cc-notify ]]; then
    dest="role=$CC_DEATH_PAGE_ROLE"
    lcw_bounded "${CC_DEATH_PAGE_TIMEOUT_S:-10}" "$CC_DEATH_PAGER" --role "$CC_DEATH_PAGE_ROLE" "$line" >/dev/null 2>&1 || rc=$?
  else
    # Its desk rung is bounded at HALF of ours: its own default (25 s) outlives this 10 s bound, which
    # would cut a hung desk rung before the operator rung — the one that needs no role file — ran.
    dest="${CC_DEATH_PAGER##*/}"
    CC_DESK_PAGE_TIMEOUT_S="${CC_DESK_PAGE_TIMEOUT_S:-$(( ${CC_DEATH_PAGE_TIMEOUT_S:-10} / 2 ))}" \
      lcw_bounded "${CC_DEATH_PAGE_TIMEOUT_S:-10}" "$CC_DEATH_PAGER" --source lead-crash-watchdog "$line" >/dev/null 2>&1 || rc=$?
  fi
  # THE VICTIM MAY BE THE PAGE'S ONLY RECIPIENT (2026-09-08, desk 88e2c2b1). role=desk resolves to a
  # PANE, and when the dead session is that pane, cc-notify appends the page to a dead inbox and
  # returns 0 — "DELIVERED", to nobody. The supervisor then records it as "no live desk" and folds it
  # into a one-word digest. So a desk death also goes to the liveness-free channel, naming the one
  # command that puts a desk back. Seam: CC_DEATH_OSA_BIN stands in for osascript.
  if pane_is_desk "$LEAD_PANE"; then
    lcw_osa "${CC_DEATH_OSA_BIN:-osascript}" -e "display notification \"The DESK itself died — session ${sid:0:8} in pane ${LEAD_PANE} (${cause}). Nothing pages a dead desk. Restore it: cc-husk-sweep --resume --pane ${LEAD_PANE}\" with title \"Claude DESK DOWN\" sound name \"Basso\"" >/dev/null 2>&1 || true
    log "[watchdog $sid] death page was addressed to $dest, but the VICTIM IS THE DESK (pane $LEAD_PANE) — it sits in a dead inbox; escalated to Notification Center with the restore command"
  fi
  if [[ "$rc" -eq 0 ]]; then
    log "[watchdog $sid] death page DELIVERED to $dest: $line"
    return 0
  fi
  log "[watchdog $sid] death page FAILED (rc=$rc) to $dest: $line"
  return 2
}

# ── THE PANE VERDICT — painted where the operator actually looks (2026-09-08, desk 88e2c2b1) ──────
# WHAT FAILED. The desk (pane 330, sid 88e2c2b1) was SIGTERMed from outside at 22:47:36Z while idle.
# This watchdog classified it correctly 30 s later (class=CRASH cause=external-sigterm), built the
# death page — and addressed it to role=desk, i.e. to the victim (see surface_death). The only
# surface the operator looked at was the pane, and the pane showed Claude Code's ordinary `Resume
# this session with:` line over a live shell prompt — byte-identical to a clean /exit, to a
# self-close whose pane close failed, and to a recycle that never relaunched. Three hours later the
# operator had to ask which one it was.
#
# THE RULE. A dead session's verdict is painted INTO THE PANE, after the shell prompt has come back,
# addressed to no role at all. The pane's tty is a character device this daemon can write by path
# (crw--w---- chrisren tty) with no terminal API, no kitty socket and no iTerm2 cookie — so the
# launchd-context blindness that let cc-reaper kill a session but never close its pane (41d08635a)
# cannot reach a write(2) to /dev/ttysNNN. Writing to the OUTPUT side of a tty types nothing into
# the shell; the OSC-2 title escape rides along so the tab is labelled until the next prompt.
#
# WHAT IT SAYS, by class:
#   CRASH (external-sigterm / jetsam / killed-before-report / …): "NOT A CLEAN EXIT — KILLED", the
#     cause, the work state of its cwd, and ONE resume line with the PINNED launcher — the bare
#     `claude --resume` line Claude printed uses the default account and cannot see a transcript
#     that lives under another account's store (cc-husk-sweep's header records that incident).
#   RECYCLE/clean-exit whose pane SURVIVED with nothing relaunched (a /exit, or a self-close
#     --terminal whose it2 close failed): "✓ <sid8> ended cleanly · closing in 20s" — the other
#     half of the ambiguity, so a finished session's leftover pane is never read as a kill.
#   retired-by-desk whose pane survived: "✓ <sid8> retired by desk · closing in 20s".
#   A session limit-recover MOVED (pane_lr_facts, any class): "✗ <sid8> moved <src>→<dst>, relaunch
#     failed" over "▶ cc-lr recover <sid8>" and one queued request when no LIVE copy runs (STRANDED),
#     or "✓ <sid8> moved, runs in pane N" when cc-find shows one (K6) — never "ended cleanly".
#   A recycle/resume that DID relaunch, or a pane that closed: NOTHING — the pane already says it.
# Every "closing in" is painted only after cc-pane-close --dry-run agrees (paint_pane_verdict).
#
# WHEN. Only after the pane has SETTLED: a recycle types /exit and the relaunch line within seconds
# of each other, and a self-close closes the pane right after the exit. The verdict waits up to
# CC_PANE_VERDICT_SETTLE_S (45 s) for either, and paints only over a tty whose remaining processes
# are all shells — never over a new claude, never over a running command.
#
# Seams: CC_PANE_VERDICT=0 (kill switch) · CC_PANE_VERDICT_DEV (stands in for /dev) ·
# CC_PANE_VERDICT_TTY_PROCS (a file standing in for `ps -t <tty> -o stat=,command=`) ·
# CC_PANE_VERDICT_SETTLE_S · CC_SESSIONS_LOG · CC_ROLES_DIR · CC_DEATH_OSA_BIN (stands in for
# osascript) · CC_PANE_VERDICT_{TTY,PANE,CFG,CWD} — the registration-time facts, for the
# --pane-verdict entrypoint and a one-off repaint of a pane whose daemon predates this arm.
PANE_VERDICT_SETTLE_S="${CC_PANE_VERDICT_SETTLE_S:-45}"
PANE_VERDICT_DEV="${CC_PANE_VERDICT_DEV:-/dev}"
LEAD_TTY="${CC_PANE_VERDICT_TTY:-}"      # overwritten at registration from `ps -o tty= -p <lead>`
LEAD_PANE="${CC_PANE_VERDICT_PANE:-}"    # …from CC_PANE_ID / KITTY_WINDOW_ID / ITERM_SESSION_ID
LEAD_CFG="${CC_PANE_VERDICT_CFG:-}"      # …from CLAUDE_CONFIG_DIR (names the pinned launcher)
LEAD_CWD="${CC_PANE_VERDICT_CWD:-}"      # …from the hook's $PWD (the session's working dir)
LEAD_AGENT_ID="${CC_PANE_VERDICT_AGENT_ID:-}"  # …from the lead's argv: `<name>@<team>` iff an Agent-Teams member

pane_launcher_for_cfg() { # $1=config dir → the launcher pinned to that account's store
  case "${1##*/}" in
    .claude-secondary)  printf 'claude2' ;;
    .claude-tertiary)   printf 'claude3' ;;
    .claude-quaternary) printf 'claude4' ;;
    *)                  printf 'claude' ;;
  esac
}
pane_is_desk() { # $1=pane → 0 iff the desk role pointer names this pane
  local d
  d=$(head -1 "${CC_ROLES_DIR:-$HOME/.claude/cc-roles}/desk" 2>/dev/null | tr -d ' \n\r')
  [[ -n "${1:-}" && -n "$d" && "$d" == "$1" ]]
}
pane_tty_procs() { # $1=tty → "<stat> <command>" for every process still attached to that tty
  if [[ -n "${CC_PANE_VERDICT_TTY_PROCS:-}" ]]; then cat "$CC_PANE_VERDICT_TTY_PROCS" 2>/dev/null; return 0; fi
  lcw_bounded "${LCW_PROBE_TIMEOUT_S:-5}" /bin/ps -t "$1" -o stat=,command= 2>/dev/null || true
}
# "Is the pane at a bare prompt?" is a question about the tty's FOREGROUND process group, and the
# kernel answers it directly: ps marks every member with `+` in STAT. Only those are judged — every
# foreground process must be a shell. Background residents of the tty are not "something running
# there": the prompt's own gitstatusd (powerlevel10k / oh-my-zsh, ppid = the shell, or 1 once its
# shell died) sits on every zsh pane on this machine, and the prior rule — EVERY attached process
# must be named like a shell — refused 31 of 33 panes that settled at a prompt (2026-09-09..22,
# lead-crash-watchdog.log), including the incident pane 503 / ttys006 on 2026-09-22. A name
# allowlist over all residents enumerates examples; the foreground group is the class.
# No `+` anywhere means the probe could not see the group (it always can on a live tty): judge
# every line, i.e. the old conservative rule, so a blind probe never reads as a bare prompt.
pane_procs_are_shells() { # stdin = "<stat> <command>" lines → 0 iff the foreground group is only shells
  awk '{ st[NR]=$1; c=$2; sub(/^-/, "", c); n=split(c, p, "/"); cmd[NR]=p[n]; if ($1 ~ /\+/) fg=1 }
       END { if (NR == 0) exit 1
             for (i = 1; i <= NR; i++) {
               if (fg && st[i] !~ /\+/) continue
               if (cmd[i] !~ /^(zsh|bash|sh|fish|login)$/) exit 1 }
             exit 0 }'
}
pane_verdict_settle() { # $1=tty → closed | relaunched | shell | unknown  (waits for the pane to settle)
  local tty="$1" waited=0 procs
  while :; do
    [[ -e "$PANE_VERDICT_DEV/$tty" ]] || { printf 'closed'; return 0; }
    procs=$(pane_tty_procs "$tty")
    if [[ "$procs" =~ node_modules/\.bin/claude ]] || [[ "$procs" =~ (^|/|[[:space:]])claude(\.exe)?([[:space:]]|$) ]]; then
      printf 'relaunched'; return 0
    fi
    (( waited >= PANE_VERDICT_SETTLE_S )) && break
    sleep 5; waited=$(( waited + 5 ))
  done
  [[ -e "$PANE_VERDICT_DEV/$tty" ]] || { printf 'closed'; return 0; }
  procs=$(pane_tty_procs "$tty")
  [[ -n "$procs" ]] || { printf 'unknown'; return 0; }
  if printf '%s\n' "$procs" | pane_procs_are_shells; then printf 'shell'; else printf 'unknown'; fi
}
pane_work_state() { # $1=cwd → clean | dirty:N | unlanded:N | -   (git facts, never the session's word)
  local cwd="$1" dirty ahead
  { [[ -n "$cwd" && -d "$cwd" ]] && git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1; } || { printf -- '-'; return 0; }
  dirty=$(git -C "$cwd" status --porcelain 2>/dev/null | wc -l | tr -d ' ' || true)
  [[ "$dirty" == 0 ]] || { printf 'dirty:%s' "$dirty"; return 0; }
  ahead=$(git -C "$cwd" rev-list --count origin/main..HEAD 2>/dev/null || echo "")
  case "$ahead" in ''|*[!0-9]*|0) printf 'clean' ;; *) printf 'unlanded:%s' "$ahead" ;; esac
}
# ASSISTANT TEXT ONLY (2026-09-30, husk-panes root cause 7). This used to grep the whole JSONL, and
# in a session that never wrote a close the last match came from the CLAUDE.md instructions
# attachment ("An honest `Good to close: no …`"), so every such pane read `no`. A streaming pass in
# the style of last_assistant_text: records whose type or message.role is assistant, content[].text
# joined, the last `Good to close: yes|no`. No assistant close ⇒ "-", not a fault.
pane_last_close() { # $1=transcript → yes | no | -   (the last "Good to close:" the session wrote)
  local c=""
  [[ -n "${1:-}" && -f "$1" ]] || { printf -- '-'; return 0; }
  c=$(lcw_bounded "${LCW_REPORT_READ_TIMEOUT_S:-30}" "${LCW_PYTHON_BIN:-python3}" - "$1" <<'PY' 2>/dev/null || true
import json, re, sys
last = ""
pat = re.compile(r"Good to close: (yes|no)\b")
try:
    with open(sys.argv[1], "r", errors="replace") as fh:
        for line in fh:
            if "Good to close: " not in line or '"assistant"' not in line:
                continue
            try:
                rec = json.loads(line)
            except Exception:
                continue
            msg = rec.get("message") or {}
            if rec.get("type") != "assistant" and msg.get("role") != "assistant":
                continue
            content = msg.get("content")
            if isinstance(content, list):
                content = "\n".join(b.get("text", "") for b in content
                                    if isinstance(b, dict) and b.get("type") == "text")
            if not isinstance(content, str):
                continue
            hits = pat.findall(content)
            if hits:
                last = hits[-1]
except Exception:
    pass
sys.stdout.write(last)
PY
)
  printf '%s' "${c:--}"
}
pane_end_reason() { # $1=sid → the SessionEnd reason session-end.sh logged, or -
  local f="${CC_SESSIONS_LOG:-$HOME/.claude/logs/sessions.log}" r
  [[ -f "$f" ]] || { printf -- '-'; return 0; }
  r=$(LC_ALL=C grep -a "Session ended sid=$1 " "$f" 2>/dev/null | tail -1 | sed -n 's/.*reason=\([A-Za-z0-9._-]*\).*/\1/p' || true)
  printf '%s' "${r:--}"
}
pane_custody_fact() { # $1=tpath → lib/pane-custody.sh's TSV line for LEAD_PANE, or nothing
  # A killed lead whose originator collected its work must not be offered --resume: that re-arms its
  # /goal over finished work (docs/research/husk-triage-2026-10-01.md § Gaps, item 2 — pane 55). The
  # lib is found the way bin/cc-pane-runner finds pane-recycle-pending.sh: checkout sibling, else the
  # live layer. No lib, no pane or no row ⇒ nothing, and the banner stays as it was.
  local self lib="" c
  [[ -n "${LEAD_PANE:-}" ]] || return 0
  self="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")"
  for c in "$(dirname "$self")/../lib/pane-custody.sh" "$HOME/.claude/lib/pane-custody.sh"; do
    [[ -r "$c" ]] && { lib="$c"; break; }
  done
  [[ -n "$lib" ]] || return 0
  # shellcheck source=/dev/null  # resolved at run time (checkout, else the live layer)
  . "$lib" 2>/dev/null || return 0
  declare -F cc_pane_custody >/dev/null 2>&1 || return 0
  # The session's first record dates it, so a row from an earlier tenant of this reused pane id is
  # ignored; an undatable transcript passes 0 and gets the weaker, pane-only match.
  cc_pane_custody "$LEAD_PANE" "$(cc_transcript_start_epoch "$1")" 2>/dev/null || true
}
# ── A SESSION LIMIT-RECOVER MOVED IS NOT A CLEAN EXIT (lr-wake 2026-10-18, REPORT §4 Wave F, RC4) ────
# Overnight a move's /exit read as RECYCLE/clean-exit and this arm painted "✅ CLOSED CLEANLY … safe to
# close" over pane 332, 28 s after lr had recorded STRANDED, with `claude4 --resume` for a session
# whose transcript lived on another account. The death class cannot see a move; lr's own records can,
# so they are joined here before any banner is chosen:
#   · <sid>.HANDOFF.json in the registration's store — the durable tombstone; handed_off_to names the
#     store holding the full transcript (a same-store tombstone is a --mark, never a move);
#   · locks/<sid>.lock — the transient split-brain lock, whose "to" says the same;
#   · the newest bundle's verdict row (<LR_STATE_DIR>/<sid>/bundle-*/events.jsonl, state STRANDED);
#   · faults/<sid>.json — whose claim.by names the claiming store when nothing above does.
# Per K6 the pane is closed only when cc-find shows a LIVE copy elsewhere (MOVED); a move with no LIVE
# copy is STRANDED: painted as such and queued once for lr's poller (requests/<sid>.cc-lr.json, deduped
# against parked/, runs/by-sid/ and requests/ as lr-fire-resume does), never offered a hand resume.
# Seams: LR_STATE_DIR · CC_FIND_BIN · LCW_LR_FACT_MAX_AGE_S (21600: how old a bundle verdict or fault
# may be and still speak) · CC_PANE_LR_ENQUEUE=off (paint only).
pane_acct_for_cfg() { # $1=config dir → next | next2 | next3 | next4
  case "${1%/}" in
    *.claude-secondary)  printf 'next2' ;;
    *.claude-tertiary)   printf 'next3' ;;
    *.claude-quaternary) printf 'next4' ;;
    *)                   printf 'next' ;;
  esac
}
pane_same_store() { # $1 $2 = config dirs → 0 iff one store (compared by projects/, as lr_config_dirs keys it)
  local a b
  a=$(cd "$1/projects" 2>/dev/null && pwd -P || true); [[ -n "$a" ]] || a="$1/projects"
  b=$(cd "$2/projects" 2>/dev/null && pwd -P || true); [[ -n "$b" ]] || b="$2/projects"
  [[ "$a" == "$b" ]]
}
pane_handed_off_to() { # $1=sid $2=cfg → the OTHER store its tombstone names, when that store holds the sid
  local tomb to f
  for tomb in "$2"/projects/*/"$1".HANDOFF.json; do
    [[ -f "$tomb" ]] || continue
    to=$(sed -n '/"handed_off_to":"/{s/.*"handed_off_to":"\([^"]*\)".*/\1/p;q;}' "$tomb" 2>/dev/null || true)
    [[ -n "$to" ]] || continue
    pane_same_store "$to" "$2" && continue
    for f in "$to"/projects/*/"$1".jsonl; do [[ -f "$f" ]] && { printf '%s' "$to"; return 0; }; done
  done
  return 1
}
pane_full_cfg() { # $1=sid $2=cfg → the store holding the FULL transcript: each tombstone hop followed (≤4)
  local cfg="$2" hop=0 to
  while (( hop < 4 )) && to=$(pane_handed_off_to "$1" "$cfg"); do cfg="$to"; hop=$(( hop + 1 )); done
  printf '%s' "$cfg"
}
pane_find_live() { # $1=sid → the pane of a LIVE copy cc-find shows outside LEAD_PANE ("?" when unpaned), or nothing
  local self bin
  self="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")"
  bin="${CC_FIND_BIN:-$(dirname "$self")/../bin/cc-find}"
  [[ -x "$bin" ]] || bin="$HOME/.claude/bin/cc-find"
  [[ -x "$bin" ]] || return 0
  { lcw_bounded "${LCW_PROBE_TIMEOUT_S:-15}" "$bin" "${1:0:8}" </dev/null 2>/dev/null || true; } \
    | awk -F'\t' -v s="$1" -v me="${LEAD_PANE:-}" '$1 == s && $6 == "LIVE" && $2 != me { print ($2 == "" ? "?" : $2); exit }'
}
pane_lr_facts() { # $1=sid → sets LRF_STATE (stranded | moved-live | empty) LRF_SRC LRF_DST LRF_DST_CFG LRF_LIVE_PANE LRF_FACTS
  local sid="$1" st="${LR_STATE_DIR:-$HOME/.reso/limit-recover}" max="${LCW_LR_FACT_MAX_AGE_S:-21600}"
  local now dst="" to ev row vstate vts detail by fs
  LRF_STATE=""; LRF_SRC=""; LRF_DST=""; LRF_DST_CFG=""; LRF_LIVE_PANE=""; LRF_FACTS=""
  [[ -n "$sid" && -n "${LEAD_CFG:-}" ]] || return 0
  now=$(date +%s)
  to=$(pane_full_cfg "$sid" "$LEAD_CFG")
  if ! pane_same_store "$to" "$LEAD_CFG"; then dst="$to"; LRF_FACTS="tombstone"; fi
  if [[ -z "$dst" && -f "$st/locks/$sid.lock" ]]; then
    to=$(sed -n '/"to":"/{s/.*"to":"\([^"]*\)".*/\1/p;q;}' "$st/locks/$sid.lock" 2>/dev/null || true)
    if [[ -n "$to" ]] && ! pane_same_store "$to" "$LEAD_CFG"; then dst="$to"; LRF_FACTS="lock"; fi
  fi
  ev=$(find "$st/$sid" -maxdepth 2 -path '*/bundle-*/events.jsonl' 2>/dev/null | LC_ALL=C sort | tail -1 || true)
  if [[ -n "$ev" ]]; then
    row=$(jq -c 'select(.stage == "verdict")' "$ev" 2>/dev/null | tail -1 || true)
    vstate=$(jq -r '.state // empty' <<<"$row" 2>/dev/null || true)
    vts=$(jq -r '.ts // empty | sub("\\.[0-9]+Z$"; "Z") | (try fromdateiso8601 catch empty) | floor' <<<"$row" 2>/dev/null || true)
    if [[ "$vstate" == STRANDED && "$vts" =~ ^[0-9]+$ ]] && (( now - vts <= max )); then
      LRF_FACTS="${LRF_FACTS:+$LRF_FACTS+}bundle"
      if [[ -z "$dst" ]]; then
        detail=$(jq -r '.detail // empty' <<<"$row" 2>/dev/null || true)
        dst=$(sed -n 's/.*now lives under \([^ ,]*\).*/\1/p' <<<"$detail" | head -1 || true)
      fi
    fi
  fi
  if [[ -f "$st/faults/$sid.json" ]]; then
    fs=$(jq -r '.first_seen // 0 | floor' "$st/faults/$sid.json" 2>/dev/null || echo 0)
    if [[ "$fs" =~ ^[0-9]+$ ]] && (( now - fs <= max )); then
      LRF_FACTS="${LRF_FACTS:+$LRF_FACTS+}fault"
      by=$(jq -r '.claim.by // empty' "$st/faults/$sid.json" 2>/dev/null || true)
      if [[ -z "$dst" && -n "$by" ]] && ! pane_same_store "$by" "$LEAD_CFG"; then dst="$by"; fi
    fi
  fi
  # A fault alone is a claim, not a move: a tombstone, the lock or a STRANDED verdict must speak.
  case "$LRF_FACTS" in *tombstone*|*lock*|*bundle*) ;; *) LRF_FACTS=""; return 0 ;; esac
  LRF_SRC=$(pane_acct_for_cfg "$LEAD_CFG"); LRF_DST_CFG="$dst"
  LRF_DST="?"; [[ -z "$dst" ]] || LRF_DST=$(pane_acct_for_cfg "$dst")
  LRF_LIVE_PANE=$(pane_find_live "$sid")
  if [[ -n "$LRF_LIVE_PANE" ]]; then LRF_STATE=moved-live; else LRF_STATE=stranded; fi
  return 0
}
pane_lr_enqueue() { # $1=sid $2=target cfg → one status sentence; writes requests/<sid>.cc-lr.json at most once
  local sid="$1" cfg="${2:-}" st="${LR_STATE_DIR:-$HOME/.reso/limit-recover}" f req tmp
  [[ "${CC_PANE_LR_ENQUEUE:-on}" != off ]] || { printf 'Not queued (CC_PANE_LR_ENQUEUE=off).'; return 0; }
  [[ ! -f "$st/parked/$sid.json" ]] || { printf 'limit-recover already holds it (a parked record).'; return 0; }
  for f in "$st/requests/$sid"*.json; do
    [[ -f "$f" ]] && { printf 'Queued for the limit-recover poller (requests/%s).' "${f##*/}"; return 0; }
  done
  [[ ! -e "$st/runs/by-sid/$sid.active" ]] || { printf 'limit-recover already holds it (a run claim).'; return 0; }
  req="$st/requests/$sid.cc-lr.json"; tmp="$st/requests/.$sid.cc-lr.$$.tmp"
  if mkdir -p "$st/requests" 2>/dev/null \
     && jq -nc --arg sid "$sid" --argjson at "$(date +%s)" --arg pane "${LEAD_PANE:-}" --arg cfg "$cfg" \
          --arg acct "$( [[ -n "$cfg" ]] && pane_acct_for_cfg "$cfg" )" --arg cwd "${LEAD_CWD:-}" \
          '{sid:$sid, at:$at, requested_by:"lead-crash-watchdog", mode:"recover", cause:"stranded", pane:$pane}
           + (if $cfg != "" then {config_dir:$cfg, account:$acct} else {} end)
           + (if $cwd != "" then {cwd:$cwd} else {} end)' > "$tmp" 2>/dev/null \
     && mv -f "$tmp" "$req" 2>/dev/null; then
    log "[watchdog $sid] STRANDED — queued requests/${req##*/} for the limit-recover poller"
    printf 'Queued for the limit-recover poller (requests/%s).' "${req##*/}"
  else
    rm -f "$tmp" 2>/dev/null || true
    printf 'NOT queued (could not write %s) — run the command above.' "$req"
  fi
}
# THE VERDICT IS ONE LINE (lr-wake 2026-10-18, RC8; g-message-design.md §5.3 E). Each row is drawn
# by lib/cc-say.sh: answer first, ≤ 56 cells, at most one `▶`, no rules and no full paths. A dirty
# or unlanded working dir adds ONE amber row; a teammate, or a session another pane holds custody
# of, adds one ⚠ row naming who to tell. Everything else — the cause's exit and signal, the work
# state, the last close verdict, the pinned resume line, custody facts — goes to the pane-say log
# (cc_say_detail), never to the terminal.
#
# _lcw_say_load — the shared renderer, found in this hook's own checkout through its symlink, else
# the live layer; rc 1 when neither exists. Lazy: only a paint pays for the source.
_lcw_say_load() {
  command -v cc_say >/dev/null 2>&1 && return 0
  local s="${BASH_SOURCE[0]}" t sd c
  while [[ -L "$s" ]]; do
    t="$(readlink "$s" 2>/dev/null)" || break
    case "$t" in /*) s="$t" ;; *) s="$(dirname "$s")/$t" ;; esac
  done
  sd="$(cd "$(dirname "$s")" 2>/dev/null && pwd)" || sd=""
  for c in "${sd:+$sd/../lib/cc-say.sh}" "${HOME:-}/.claude/lib/cc-say.sh"; do
    # shellcheck source=/dev/null  # runtime-resolved: checkout sibling, else the live layer
    [[ -n "$c" && -r "$c" ]] && { . "$c" 2>/dev/null || true; break; }
  done
  command -v cc_say >/dev/null 2>&1
}
# _lcw_say KIND VERDICT [FACT] [ACTION] — one verdict row on STDOUT (the verdict is captured by
# `$(...)`), in colour: the target is the pane's tty written by path, which no isatty test can see.
# `sid` is the caller's local (bash scoping), stamped on the log record. A plain stand-in without it.
_lcw_say() {
  if _lcw_say_load; then
    CC_SAY_TOOL=lead-crash-watchdog CC_SAY_FD=1 CC_SAY_COLOR=1 CC_SAY_WIDTH=56 \
      CC_SAY_SID="${sid:-}" CC_SAY_PANE="${LEAD_PANE:-}" cc_say "$@"
  else
    local g="─"
    case "$1" in ok) g="✓" ;; fail) g="✗" ;; warn) g="⚠" ;; esac
    printf '%s %s%s%s\n' "$g" "$2" "${3:+ · $3}" "${4:+ · ▶ $4}"
  fi
}
_lcw_say_detail() { # VERDICT DETAIL → the pane-say log only; prints nothing
  _lcw_say_load || return 0
  CC_SAY_TOOL=lead-crash-watchdog CC_SAY_SID="${sid:-}" CC_SAY_PANE="${LEAD_PANE:-}" cc_say_detail "$@"
}
# The row builders below write pane_verdict_text's locals (bash scoping): `body`, and `headline`
# (the first row's plain text, for the daemon log).
_pv_add() { # KIND VERDICT [FACT] [ACTION]
  local out; out=$(_lcw_say "$@")
  if [[ -z "$body" ]]; then body="$out"; else body="$body"$'\n'"$out"; fi
  [[ -n "$headline" ]] || headline="$2${3:+ · $3}"
}
_pv_work_row() { # the ONE amber row for a dirty or unlanded working dir, else nothing
  local what="uncommitted" b="${LEAD_CWD:-?}"
  case "$work" in dirty:*) ;; unlanded:*) what="unlanded" ;; *) return 0 ;; esac
  _pv_add warn "$what work in ${b##*/}"
}
# A TEAMMATE IS NOT RESUMABLE (root cause 6): resumed outside its team it is a stray session with no
# lead to report to, and its lead re-spawns members itself. So no teammate verdict offers --resume —
# this row names the lead instead. Its team is `session-<lead sid8>`.
_pv_tm_row() {
  _pv_add warn "$nm not resumable" "tell its lead ${tm_team#session-}"
  detail="$detail · teammate $tm_name is not resumable outside its team: tell its lead (session ${tm_team#session-}) — the lead re-spawns members"
}
_pv_out() { # the caller's verdict in paint_pane_verdict's framing; its detail goes to the log
  _lcw_say_detail "$headline" "$detail (painted $when)"
  # Line 1 also carries the CONTRACT state for cc-pane-verdict (F5), after the title, \x1f-separated
  # so an empty field stays empty: state, owner pane, moved-to pane, stranded, unsaved count.
  printf '%s\t%s\x1f%s\x1f%s\x1f%s\x1f%s\x1f%s\n\n%s\n' "$headline" "$title" "${pvs:-CANTTELL}" "${pvo:-}" "${pvm:-}" "${pvx:-0}" "${pvu:-}" "$body"
}
pane_verdict_text() { # $1=sid $2=class $3=cause $4=exit $5=sig $6=tpath → line 1: headline<TAB>title; then a blank line and the block
  local sid="$1" class="$2" cause="$3" ec="${4:-}" sig="${5:-}" tpath="${6:-}"
  local launcher work close reason when role="" headline="" title="" body="" detail="" resume
  local tm tm_is tm_name tm_team tm_src tm_mid full_cfg f s8 pane closing nm
  local pvs="" pvo="" pvm="" pvx=0 pvu=""   # the CONTRACT state (synthesis.md § CONTRACT), see _pv_out
  # The resume hint names the launcher of the store holding the FULL transcript (each HANDOFF.json hop
  # followed), never the registration's store: that printed `claude4` for a session living on next2.
  full_cfg="$LEAD_CFG"; [[ -z "$LEAD_CFG" ]] || full_cfg=$(pane_full_cfg "$sid" "$LEAD_CFG")
  launcher=$(pane_launcher_for_cfg "$full_cfg")
  if [[ "$full_cfg" != "$LEAD_CFG" ]]; then
    for f in "$full_cfg"/projects/*/"$sid".jsonl; do [[ -f "$f" ]] && { tpath="$f"; break; }; done
  fi
  work=$(pane_work_state "$LEAD_CWD"); close=$(pane_last_close "$tpath"); reason=$(pane_end_reason "$sid")
  when=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  s8="${sid:0:8}"; pane="${LEAD_PANE:-<pane>}"
  pane_is_desk "$LEAD_PANE" && role=" (desk)"
  resume="nocorrect CC_ACCOUNT_PINNED=1 $launcher --resume $sid"
  # The promise a closable verdict makes, and the phrase paint_pane_verdict hands the pane to the
  # closer on: a countdown only when cc-pane-close will be called, else the operator's instruction.
  closing="safe to close"
  if [[ "${CC_PANE_VERDICT_CLOSE:-on}" != off && "${LEAD_PANE:-}" =~ ^[0-9]+$ ]] && pane_closer_bin >/dev/null; then
    closing="closing in ${CC_PANE_VERDICT_CLOSE_GRACE_S:-20}s"
  fi
  _lcw_say_load || true
  tm=$(teammate_facts "$tpath")
  IFS=$'\t' read -r tm_is tm_name tm_team _ tm_src tm_mid <<< "$tm" || true
  nm="$tm_name"; (( ${#nm} <= 12 )) || nm="${nm:0:11}…"
  # LR FACTS FIRST (pane_lr_facts): a moved session's banner says where it went, whatever the death
  # class read. A teammate keeps its own banner — its lead owns it, not limit-recover.
  LRF_STATE=""
  [[ "$tm_is" == 1 ]] || pane_lr_facts "$sid"
  case "$LRF_STATE" in
    stranded)
      # `cc-lr recover`, not `lr-fleet --one`: lr-fleet is not on PATH, so the painted command did not
      # run when pasted; cc-lr recover drives the same lr-fleet --one behind its guards.
      title="✗ stranded $s8"; pvs=RESUME; pvx=1
      _pv_add fail "$s8 moved ${LRF_SRC}→${LRF_DST}, relaunch failed" "" "cc-lr recover $s8"
      detail="$(pane_lr_enqueue "$sid" "$LRF_DST_CFG") Its full transcript is on $LRF_DST ($launcher); no copy runs anywhere · work in ${LEAD_CWD:-?}: $work · last close verdict: $close · lr facts: $LRF_FACTS"
      _pv_out
      return 0 ;;
    moved-live)
      title="✅ moved $s8"; pvs=DONE; pvm="$LRF_LIVE_PANE"
      _pv_add ok "$s8 moved, runs in pane $LRF_LIVE_PANE" "$closing"
      detail="moved ${LRF_SRC}→${LRF_DST} and runs in pane $LRF_LIVE_PANE. Do NOT resume it here — a second copy would split it."
      _pv_out
      return 0 ;;
  esac
  case "$class:$cause" in
    RECYCLE:retired-teammate)
      # No re-spawn advice here: the lead ORDERED this end, so there is nothing to re-spawn. The two
      # sources differ in what they prove: `own` means the member received the request (its work went
      # to the lead); a lead source proves the order, not the member's state — so a member that died
      # with a tool call open is said to have been stopped MID-TASK, and the pane is NOT auto-closed
      # (the countdown is the closer's trigger), because the warning is the point of the paint.
      title="✅ retired $s8"; pvs=DONE
      if [[ "${tm_src:-own}" == lead-* ]]; then
        local how="TaskStop"; [[ "$tm_src" == lead-request ]] && how="shutdown_request"
        detail="teammate $tm_name (session $s8) was stopped by its lead ($how); this was not a crash"
        if [[ "${tm_mid:-0}" == 1 ]]; then
          title="⚠ retired mid-task $s8"; pvs=CANTTELL
          _pv_add warn "$nm retired mid-task by lead" "$how"
          _pv_add warn "check its worktree for uncommitted work"
          detail="$detail. It was stopped MID-TASK (a tool call never returned): check its worktree before its lead (session ${tm_team#session-}) removes it. Nothing to resume."
        else
          _pv_add ok "$nm retired by its lead" "$closing"
          detail="$detail. Nothing to resume."
        fi
      else
        _pv_add ok "$nm retired by its lead" "$closing"
        detail="teammate $tm_name (session $s8) was shut down by its lead; its work went to the lead. Nothing to resume."
      fi ;;
    RECYCLE:retired-by-desk)
      title="✅ retired $s8"; pvs=DONE
      _pv_add ok "$s8 retired by desk" "$closing"
      detail="session $s8${role} was retired by the desk after its work was collected; the pane close that should have followed did not happen. Do NOT resume it — its work was landed before the retirement." ;;
    RECYCLE:*)
      title="✅ closed $s8"; pvs=DONE
      case "$work" in dirty:*|unlanded:*) pvs=CANTTELL ;; esac
      detail="exited on its own (reason: $reason); nothing relaunched here · work in ${LEAD_CWD:-?}: $work · last close verdict: $close"
      case "$work" in
        dirty:*|unlanded:*) _pv_add ok "$s8${role} ended cleanly" ;;
        *) _pv_add ok "$s8${role} ended cleanly" "$closing" ;;
      esac
      _pv_work_row
      if [[ "$tm_is" == 1 ]]; then _pv_tm_row; else detail="$detail · reopen: $resume"; fi ;;
    *)
      # CUSTODY, for a lead only (a teammate's row already names its lead). This paint happens ONCE,
      # at death, and a discharge usually arrives later — so an OPEN row names the owner instead of
      # offering a resume, and the sweep (which reads custody live) is the place to decide.
      local cust="" c_state="" c_slug="" c_kind="" c_ts="" c_op=""
      [[ "$tm_is" == 1 ]] || cust=$(pane_custody_fact "$tpath")
      IFS=$'\t' read -r c_state c_slug c_kind c_ts c_op <<< "$cust" || true
      detail="cause: ${cause}${ec:+ (exit $ec}${sig:+, signal $sig}${ec:+)} · work in ${LEAD_CWD:-?}: $work · last close verdict: $close"
      if [[ "$c_state" == collected ]]; then
        title="✅ collected $s8"; pvs=DONE
        _pv_add ok "$s8 work collected by pane $c_op" "do not resume" "cc-husk-sweep --pane $pane"
        detail="$detail · killed here; its originator (pane $c_op) collected its work: custody $c_slug: $c_kind at $c_ts. A resume would re-arm its /goal over finished work."
      else
        title="⛔ KILLED $s8"; pvs=RESUME
        case "$work" in dirty:*) pvu="${work#dirty:}" ;; esac
        # The pinned resume line (~85 cells) never fits a 56-cell row, so the row's ▶ is the triage
        # command and the resume line goes to the log.
        _pv_add fail "$s8${role} killed ($cause)" "" "cc-husk-sweep --pane $pane"
        if [[ "$c_state" == open ]]; then
          pvs=OWNED; pvo="$c_op"
          _pv_add warn "pane $c_op holds custody of its work" "tell it"
          detail="$detail · not yours to resume: its originator (pane $c_op) holds custody of this work ($c_slug, opened $c_ts)"
        elif [[ "$tm_is" != 1 ]]; then
          detail="$detail · resume: $resume (the exit text's bare \`claude --resume\` is the WRONG launcher for this account's store)"
        fi
      fi
      _pv_work_row
      [[ "$tm_is" != 1 ]] || { _pv_tm_row; pvs=CANTTELL; } ;;
  esac
  _pv_out
}
paint_pane_verdict() { # $1=sid $2=pid $3=class $4=cause $5=exit $6=sig $7=tpath — ALWAYS returns 0
  local sid="$1" class="${3:-}" cause="${4:-}" ec="${5:-}" sig="${6:-}" tpath="${7:-}" tty state out headline title block
  [[ "${CC_PANE_VERDICT:-1}" == "1" ]] || { log "[watchdog $sid] pane verdict SUPPRESSED (CC_PANE_VERDICT=0)"; return 0; }
  tty="$LEAD_TTY"
  [[ -n "$tty" ]] || { log "[watchdog $sid] pane verdict SKIPPED — no tty was recorded at registration (headless lead, or a daemon that predates this arm)"; return 0; }
  state=$(pane_verdict_settle "$tty")
  case "$state" in
    closed)     log "[watchdog $sid] pane verdict NOT PAINTED — the pane closed ($tty is gone), which already says it"; return 0 ;;
    relaunched) log "[watchdog $sid] pane verdict NOT PAINTED — a new claude took $tty (recycle or resume); nothing to add"; return 0 ;;
    unknown)    log "[watchdog $sid] pane verdict NOT PAINTED — $tty is not at a bare shell prompt (something else is running there); refusing to write over it"; return 0 ;;
  esac
  out=$(pane_verdict_text "$sid" "$class" "$cause" "$ec" "$sig" "$tpath")
  # first line = headline<TAB>title; the block follows a blank line. Parameter expansion, not
  # `| head -1`: this file runs under pipefail, and a producer cut off by head reads as a failure.
  local first meta pvs pvo pvm pvx pvu pvg=safe
  first="${out%%$'\n'*}"; headline="${first%%$'\t'*}"; title="${first#*$'\t'}"
  meta="${title#*$'\x1f'}"; title="${title%%$'\x1f'*}"
  IFS=$'\x1f' read -r pvs pvo pvm pvx pvu <<< "$meta" || true
  block="${out#*$'\n'}"; block="${block#$'\n'}"
  # THE CLOSER DECIDES BEFORE THE PAINT (lr-wake 2026-10-18, RC4). A row promising "closing in Ns"
  # over a pane the closer then refuses is a second false verdict, so a closable row is painted only
  # after cc-pane-close --dry-run agrees; when it refuses, a ⚠ triage row replaces the promise (its
  # reason goes to the log), and the phrase the close trigger keys on is gone with it.
  local kept="" line nb=""
  case "$block" in *"closing in "*|*"safe to close"*)
    if ! kept=$(pane_close_predicate "$sid"); then
      _lcw_say_load || true
      # THE REFUSAL HAS A REASON, AND THE TITLE FOLLOWS IT (husk-panes-2026-10-22 F5 interim). Pane 42
      # read "✅ closed" over "ended, reason unknown" while the closer's reason was on record: kitty
      # did not answer. A refusal about the CLOSE ITSELF (remote control down, the fullscreen guard)
      # means the session is done and only the act failed; anything else is "can't tell".
      local r1 r2
      case "$kept" in
        *"remote control is down"*)
          pvs=DONE; pvg=unreadable
          title="✓ done ${sid:0:8}"; r1=$(_lcw_say ok "${sid:0:8} finished" "nothing to resume")
          r2=$(_lcw_say wait "kitty didn't answer" "closes when it does") ;;
        *"fullscreen guard"*)
          pvs=DONE; pvg=fullscreen
          title="✓ done ${sid:0:8}"; r1=$(_lcw_say ok "${sid:0:8} finished" "nothing to resume")
          r2=$(_lcw_say warn "last pane of a fullscreen window" "⌘W closes it") ;;
        *)
          pvs=CANTTELL
          title="◆ check ${sid:0:8}"; r2=""
          r1=$(_lcw_say judge "can't tell if ${sid:0:8} finished" "" "cc-husk-sweep --pane ${LEAD_PANE:-<pane>}") ;;
      esac
      while IFS= read -r line; do
        case "$line" in *"closing in "*|*"safe to close"*)
          line="$r1"; [[ -z "$r2" ]] || line="$line"$'\n'"$r2" ;;
        esac
        if [[ -z "$nb" ]]; then nb="$line"; else nb="$nb"$'\n'"$line"; fi
      done <<< "$block"
      block="$nb"
      _lcw_say_detail "${sid:0:8} pane kept" "Nothing runs here, but the closer keeps this pane: $kept."
      log "[watchdog $sid] pane verdict: the closer keeps pane ${LEAD_PANE:-?} ($kept) — painted without the safe-to-close line"
    fi ;;
  esac
  # THE ONE WRITER (F5): cc-pane-verdict paints the contract state and repaints only on a change; the
  # block above stays the fallback (tool missing, or CC_PANE_VERDICT_TOOL=off) and the close trigger.
  local pvbin="" pva=()
  if [[ "${CC_PANE_VERDICT_TOOL:-on}" != off && "${LEAD_PANE:-}" =~ ^[0-9]+$ ]]; then
    pvbin="$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")")/../bin/cc-pane-verdict"
    [[ -x "$pvbin" ]] || pvbin="$HOME/.claude/bin/cc-pane-verdict"
    [[ -x "$pvbin" ]] || pvbin=""
  fi
  pva=(--pane "${LEAD_PANE:-}" --sid "$sid" --state "${pvs:-CANTTELL}" --guard "$pvg" --tty "$PANE_VERDICT_DEV/$tty")
  [[ -z "$pvo" ]] || pva+=(--owner "$pvo")
  [[ -z "$pvm" ]] || pva+=(--moved-to "$pvm")
  [[ "$pvx" != 1 ]] || pva+=(--stranded)
  [[ -z "$pvu" ]] || pva+=(--unsaved "$pvu")
  if [[ -n "$pvbin" ]] && cc_run "$pvbin" "${pva[@]}" >/dev/null 2>&1; then
    log "[watchdog $sid] pane verdict PAINTED by cc-pane-verdict on $tty (pane ${LEAD_PANE:-?}): ${pvs:-CANTTELL}"
  elif { printf '\n%s\n' "$block"; printf '\033]2;%s\007' "$title"; } > "$PANE_VERDICT_DEV/$tty" 2>/dev/null; then
    log "[watchdog $sid] pane verdict PAINTED on $tty (pane ${LEAD_PANE:-?}): $headline"
  else
    log "[watchdog $sid] pane verdict WRITE FAILED on $tty (pane ${LEAD_PANE:-?}): $headline"
  fi
  pane_husk_row "$sid" "$class" "$tty" "$kept"
  case "$block" in *"closing in "*|*"safe to close"*) pane_verdict_close "$sid" "$tty" ;; esac
  return 0
}
# ── A KEPT PANE IS A DURABLE ROW (husk-panes-2026-10-22 F3) ───────────────────────────────────────
# Everything above happens ONCE, at death: the close below is one attempt, and the crash and refusal
# paths make none. Pane 42's one close was refused at 03:08Z while kitty was deaf and never retried;
# pane 85's crash paint made no attempt at all, and its custody return at 23:14Z triggered nothing.
# So every paint over a pane left at a bare shell also writes a `husk` row, and
# scripts/pane-close-retry.sh retries cc-pane-close on it each tick (and on a custody discharge) until
# the pane closes or is taken over. Written BEFORE the grace close: if that close works, the drainer
# finds the pane gone and drops the row. CC_PANE_VERDICT_CLOSE=off keeps panes on purpose: no row.
pane_husk_row() { # $1=sid $2=class $3=tty $4=the closer's refusal, or empty — ALWAYS returns 0
  local q c reason
  [[ "${CC_PANE_VERDICT_CLOSE:-on}" != off && "${LEAD_PANE:-}" =~ ^[0-9]+$ ]] || return 0
  q=""
  for c in "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")")/../scripts/lib/pane-close-queue.sh" \
           "$HOME/.claude/scripts/lib/pane-close-queue.sh"; do
    [[ -r "$c" ]] && { q="$c"; break; }
  done
  [[ -n "$q" ]] || { log "[watchdog $1] husk row NOT WRITTEN — pane-close-queue.sh not found"; return 0; }
  if [[ -n "$4" ]]; then reason=closer-refused
  elif [[ "$2" == RECYCLE ]]; then reason=ended
  else reason=crash; fi
  # shellcheck source=/dev/null  # runtime-resolved: checkout sibling, else the live layer
  if ( . "$q" && pcq_add husk "$LEAD_PANE" reason="$reason" sid="$1" kitty_pid="${KITTY_PID:-}" \
         kitty_sock="${KITTY_LISTEN_ON:-}" tty="$PANE_VERDICT_DEV/$3" producer=lead-crash-watchdog ${4:+"refusal=$4"} ) >/dev/null 2>&1; then
    log "[watchdog $1] husk row written for pane $LEAD_PANE (reason $reason) — pane-close-retry owns its close from here"
  else
    log "[watchdog $1] husk row NOT WRITTEN for pane $LEAD_PANE (pcq_add failed)"
  fi
  return 0
}
# ── A PANE THAT HOLDS NOTHING IS CLOSED, NOT LABELLED (2026-10-01) ──────────────────────────────────
# The banner above told the operator "safe to close (Ctrl-D)" and stopped there, and nothing else
# ever closed such a pane: cc-husk-sweep only resumes, bin/cc-pane-close only runs when called. The
# operator then had to find and close them by hand (pane 1, "✅ closed bf6674d6", 2026-10-01), against
# the standing ruling of that day that agents close the operator's local kitty panes with no human in
# the loop (settings.json autoMode environment, "Local terminal panes"). So the three verdicts whose
# banner says the pane holds nothing — a clean exit with clean, landed work, a desk retirement, a
# retired teammate — hand the pane to cc-pane-close after a short grace. The closer re-proves every
# fact itself and fails closed (identity by this daemon's registration line, nothing live in the
# window, the session's own `Good to close: yes` or a teammate/custody ruling, no uncommitted work),
# so this adds a trigger, not a judgment. The banner stays: if the closer refuses, it is still right.
# Kill switch CC_PANE_VERDICT_CLOSE=off · CC_PANE_VERDICT_CLOSE_GRACE_S (20) · CC_PANE_CLOSE_BIN.
pane_closer_bin() { # → cc-pane-close's path, or rc 1
  local bin
  bin="${CC_PANE_CLOSE_BIN:-$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")")/../bin/cc-pane-close}"
  [[ -x "$bin" ]] || bin="$HOME/.claude/bin/cc-pane-close"
  [[ -x "$bin" ]] || return 1
  printf '%s' "$bin"
}
# rc 0 = the closer would close LEAD_PANE now (or no automatic close applies, so the banner stands as
# the operator's instruction); rc 1 = it refuses, with its reason on stdout.
pane_close_predicate() { # $1=sid
  local bin out rc=0 why
  [[ "${CC_PANE_VERDICT_CLOSE:-on}" != off && "${LEAD_PANE:-}" =~ ^[0-9]+$ ]] || return 0
  bin=$(pane_closer_bin) || return 0
  # stderr is kept (husk-panes round 2, FX1): it carries the guard's and it2's own words, and a
  # refusal with no REFUSED line used to reach the log as a bare "answered rc N".
  out=$(lcw_bounded 60 "$bin" --pane "$LEAD_PANE" --dry-run 2>&1 </dev/null) || rc=$?
  (( rc == 0 )) && return 0
  why=$(sed -n 's/.*REFUSED — //p' <<<"$out" | head -1 || true)
  [[ -n "$why" ]] || why=$(sed -n '/[^[:space:]]/{p;q;}' <<<"$out" || true)
  printf '%s' "${why:-cc-pane-close --dry-run answered rc $rc}"
  return 1
}
pane_verdict_close() { # $1=sid $2=tty — ALWAYS returns 0; the close verdict goes to the log
  local sid="$1" tty="$2" bin rc=0 out procs
  [[ "${CC_PANE_VERDICT_CLOSE:-on}" != off ]] || { log "[watchdog $sid] pane close SUPPRESSED (CC_PANE_VERDICT_CLOSE=off)"; return 0; }
  [[ "${LEAD_PANE:-}" =~ ^[0-9]+$ ]] || { log "[watchdog $sid] pane close SKIPPED — pane id '${LEAD_PANE:-}' is not a kitty window id"; return 0; }
  bin=$(pane_closer_bin) || { log "[watchdog $sid] pane close SKIPPED — cc-pane-close not found"; return 0; }
  sleep "${CC_PANE_VERDICT_CLOSE_GRACE_S:-20}"
  # Re-read after the grace: the operator may have started something in the pane meanwhile.
  [[ -e "$PANE_VERDICT_DEV/$tty" ]] || { log "[watchdog $sid] pane close NOT NEEDED — $tty closed during the grace"; return 0; }
  procs=$(pane_tty_procs "$tty")
  if [[ -z "$procs" ]] || ! printf '%s\n' "$procs" | pane_procs_are_shells; then
    log "[watchdog $sid] pane close NOT ATTEMPTED — $tty is no longer at a bare shell after the grace"; return 0
  fi
  out=$(cc_run "$bin" --pane "$LEAD_PANE" 2>&1 </dev/null) || rc=$?
  log "[watchdog $sid] pane close of ${LEAD_PANE} via cc-pane-close rc=$rc: ${out//$'\n'/ }"
  return 0
}

# Debug/test entrypoint: build + deliver a death page. Prints the page line on stdout so a test can
# assert CONTENT without a live transport, and still runs the delivery so the transport is covered.
if [[ "${1:-}" == "--surface-death" ]]; then
  death_page_line "${2:-}" "${3:-}" "${5:-}" "${6:-}" "${7:-}" "${8:-}"
  surface_death "${2:-}" "${3:-}" "${4:-}" "${5:-}" "${8:-}" "${6:-}" "${7:-}" >/dev/null 2>&1 || true
  exit 0
fi
# Debug/test/repaint entrypoint: the pane verdict for a death, with the pane facts taken from
# CC_PANE_VERDICT_{TTY,PANE,CFG,CWD}. Prints the verdict block on stdout so a test can assert
# CONTENT, then paints it (through the CC_PANE_VERDICT_DEV seam, or for real). Also the one-off
# repaint for a pane whose daemon predates this arm — the incident pane itself was repainted with it.
#   --pane-verdict <sid> <pid> <class> <cause> <exit> <sig> <transcript>
if [[ "${1:-}" == "--pane-verdict" ]]; then
  pane_verdict_text "${2:-}" "${4:-}" "${5:-}" "${6:-}" "${7:-}" "${8:-}" | tail -n +2
  paint_pane_verdict "${2:-}" "${3:-}" "${4:-}" "${5:-}" "${6:-}" "${7:-}" "${8:-}"
  exit 0
fi

if [[ "${1:-}" == "--classify" ]]; then
  # $4 = death epoch (optional; omitted ⇒ now). cc-crash-report --backfill passes the timestamp of the
  # watchdog-log line that recorded the death, so a historical death is judged against ITS OWN moment.
  classify_death "${2:-}" "${3:-}" "${4:-}"; echo; exit 0
fi
# Debug/test entrypoint: print a pid's close-record enrichment (EXIT<TAB>SIGNAL<TAB>PATH<TAB>VERSION).
if [[ "${1:-}" == "--close-fields" ]]; then
  close_record_summary "${2:-}"; echo; exit 0
fi

# Parse hook JSON stdin
INPUT=$(cat 2>/dev/null || echo '{}')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo '')
LEAD_PID="${PPID:-$$}"

if [[ -z "$SESSION_ID" ]]; then
  log "no session_id from hook input — using PID $LEAD_PID as key"
  SESSION_ID="pid-$LEAD_PID"
fi

# ── SINGLE-INSTANCE GUARD (audit 2026-07-22 root cause 4, S1) ─────────────────────────────────────
# SessionStart fires on startup AND resume AND clear AND compact, and this hook spawned a daemon
# UNCONDITIONALLY on every one of them. Nothing retired the previous incarnation, so a long-lived pane
# accumulated watchers over its life — all polling the same lead pid, all independently entitled to
# declare its death. That is the count inflation the audit measured in the watchdog log: 3064 "LEAD
# CRASH detected" lines over 2597 distinct pids, one pid recorded 19 times. Per-death consequences
# multiply with it — a duplicated ledger row, a duplicated shutdown_request into every teammate inbox,
# a duplicated teardown of the same panes.
#
# The guard needs both halves of the question, because "a daemon already exists for this sid" has two
# opposite answers:
#   · SAME lead pid  ⇒ a genuine duplicate SessionStart (resume/clear/compact inside one process).
#                      The incumbent is watching the right pid. SKIP — spawning again adds a watcher,
#                      never coverage.
#   · DIFFERENT pid  ⇒ the sid moved to a NEW process. The incumbent is now watching a pid that is gone
#                      (or, worse, RECYCLED to an unrelated process, which reads as alive forever), so
#                      it would either declare a CRASH for a session that is alive or never fire again.
#                      RETIRE it, then spawn fresh. Skipping here would leave the live session unwatched.
#
# Identity is {pid, start-time}, never a bare kill -0: the OS recycles pids, and a recycled pid reads as
# a live daemon — which would make this guard silently skip spawning and leave a session with NO watcher
# at all (strictly worse than the duplication it exists to prevent). Same discipline as the pid-identity
# checks in lead-supervisor.sh and cc-teardown's teardown pin.
DAEMON_FILE="$WATCHDOG_DIR/$SESSION_ID.daemon"
daemon_alive() { # $1=daemon-file → 0 iff it records a LIVE process that is still the one we recorded
  local f="$1" dpid dstart cur
  [[ -f "$f" ]] || return 1
  IFS=$'\t' read -r dpid dstart < "$f" 2>/dev/null || return 1
  case "$dpid" in ''|*[!0-9]*) return 1 ;; esac
  kill -0 "$dpid" 2>/dev/null || return 1
  cur=$(ps -o lstart= -p "$dpid" 2>/dev/null | tr -s ' ' | sed 's/^ *//;s/ *$//')
  [[ -n "$cur" && -n "$dstart" && "$cur" == "$dstart" ]]
}
# PREV_LEAD must be read BEFORE the pidfile is rewritten below — it is the only record of which process
# the incumbent daemon is actually watching.
PREV_LEAD=$(cat "$WATCHDOG_DIR/$SESSION_ID.pid" 2>/dev/null || true)
if daemon_alive "$DAEMON_FILE"; then
  if [[ -n "$PREV_LEAD" && "$PREV_LEAD" == "$LEAD_PID" ]]; then
    log "watchdog ALREADY RUNNING for session=$SESSION_ID pid=$LEAD_PID — duplicate SessionStart, not spawning a second daemon"
    exit 0
  fi
  # sid re-registered under a new process ⇒ the incumbent is stale. Kill by the VERIFIED identity only,
  # so a recycled pid can never make this signal a stranger.
  IFS=$'\t' read -r _stale_pid _ < "$DAEMON_FILE" 2>/dev/null || _stale_pid=""
  if [[ -n "$_stale_pid" ]]; then
    kill "$_stale_pid" 2>/dev/null || true
    log "retired stale watchdog daemon pid=$_stale_pid for session=$SESSION_ID (was watching lead ${PREV_LEAD:-<none>}, now $LEAD_PID)"
  fi
fi

# Record session→PID mapping for orphan-reaper to consult
echo "$LEAD_PID" > "$WATCHDOG_DIR/$SESSION_ID.pid"
echo "$SESSION_ID" > "$WATCHDOG_DIR/$SESSION_ID.id"
# The lead's TTY, pane, config dir and cwd — captured NOW, by value, for the pane verdict (see
# paint_pane_verdict). The daemon inherits them; nothing can re-derive them after the death: the
# registry row is gone by then (session-end.sh deletes it) and `ps` cannot answer for a dead pid.
# A seam already set (a test, or a one-off repaint) wins over the live reading.
LEAD_TTY="${CC_PANE_VERDICT_TTY:-$(ps -o tty= -p "$LEAD_PID" 2>/dev/null | tr -d ' ')}"
case "$LEAD_TTY" in ttys[0-9]*) ;; *) LEAD_TTY="" ;; esac
# CC_PANE_ID WINS (see LEAD_PANE below), so the compat id is consulted only when it is unset.
# The guard is on THIS line deliberately: it makes the precedence structural rather than a
# `cc-pane-id-lint:allow` exemption, so tests/cc-pane.bats keeps watching this line for a
# genuine bare read added later. The hoist itself is unavoidable — bash cannot apply `##*:`
# to a defaulted expansion inline.
_lcw_isid=""; [ -n "${CC_PANE_ID:-}" ] || _lcw_isid="${ITERM_SESSION_ID:-}"
LEAD_PANE="${CC_PANE_VERDICT_PANE:-${CC_PANE_ID:-${KITTY_WINDOW_ID:-${_lcw_isid##*:}}}}"
LEAD_CFG="${CC_PANE_VERDICT_CFG:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}}"
LEAD_CWD="${CC_PANE_VERDICT_CWD:-$PWD}"
# Is the lead an Agent-Teams MEMBER? Its own argv says so (the three-flag, self-consistent conjunction
# hooks/lib/agent-identity.sh reads), and argv is unreadable once it is dead — so it is captured here,
# by value, like the facts above. One hop: LEAD_PID itself, never an ancestor. Unreadable ⇒ empty, and
# teammate_facts falls back to the transcript's own teamName/agentName at death time.
if [[ -z "$LEAD_AGENT_ID" ]]; then
  _lcw_ail="$(dirname "${BASH_SOURCE[0]}")/lib/agent-identity.sh"
  [[ -f "$_lcw_ail" ]] || _lcw_ail="$HOME/.claude/hooks/lib/agent-identity.sh"
  if [[ -f "$_lcw_ail" ]]; then
    # shellcheck source=/dev/null  # resolved at run time (checkout, else the live layer)
    . "$_lcw_ail" 2>/dev/null || true
    if declare -F agent_assignee_argv >/dev/null 2>&1; then
      LEAD_AGENT_ID=$(CC_WF_START_PID="$LEAD_PID" CC_WF_MAX_HOPS=1 agent_assignee_argv 2>/dev/null || true)
    fi
  fi
  unset _lcw_ail
fi
log "registered session=$SESSION_ID pid=$LEAD_PID tty=${LEAD_TTY:-none} pane=${LEAD_PANE:-none}${LEAD_AGENT_ID:+ teammate=$LEAD_AGENT_ID}"

# The lead's start-time, read BEFORE the daemon is spawned and handed to it BY VALUE. It must not be
# re-derived from disk later: $SESSION_ID.pid records only the pid, and a later SessionStart
# overwrites it — so a daemon reading it back could pin itself to a successor it never watched.
# Unreadable ⇒ empty ⇒ lead_alive degrades to bare pid liveness (see its header).
LEAD_START=$(ps -o lstart= -p "$LEAD_PID" 2>/dev/null | tr -s ' ' | sed 's/^ *//;s/ *$//')
# …and the same instant as an EPOCH, for the close-record join (find_close_record). Read and parsed in
# ONE locale (C) and one TZ, because `ps -o lstart=` renders through LC_TIME and TZ. Unparseable ⇒
# empty ⇒ the pid-only join, which handle_crash logs.
if [[ -z "$LEAD_START_EPOCH" ]]; then
  LEAD_START_EPOCH=$(LC_ALL=C ps -o lstart= -p "$LEAD_PID" 2>/dev/null | tr -s ' ' | sed 's/^ *//;s/ *$//' \
                     | { IFS= read -r _l || true; [[ -n "${_l:-}" ]] && LC_ALL=C date -j -f '%a %b %d %T %Y' "$_l" +%s 2>/dev/null; } || true)
  case "$LEAD_START_EPOCH" in *[!0-9]*) LEAD_START_EPOCH="" ;; esac
fi

# ── The parent must survive its own bookkeeping window (2026-07-29) ────────────────────────────────
# From the `&` below until the .daemon file and the spawn log line are written, this PARENT holds the
# only record of the daemon it just created. It had no HUP trap — only the daemon subshell did — and
# a SessionStart hook runs in the dying pane's process group, so a pane teardown inside that window
# killed the parent while the disowned daemon (which ignores HUP) lived on. The result is a daemon
# named by NO .daemon file and NO log line: the single-instance guard cannot see it to retire it, and
# nothing else knows it exists. Measured before this change: 14 of 63 live daemons untracked, oldest
# 1d15h, and 0 "retired stale watchdog" lines across 3864 spawns.
#
# Placed HERE, not at the top of the file, and never removed: everything above this point is either
# instant or the `INPUT=$(cat)` stdin read, and making THAT unkillable would trade a lost record for
# a wedged hook. What follows is one ps, one printf and one log line, so the window this covers is
# bounded by construction.
trap '' HUP

# Spawn detached watchdog daemon. Uses setsid + nohup + disown to survive
# the hook process exit; daemon itself polls the lead's {pid, start-time} every 30s.
(
  # Self-contained daemon. Exits cleanly when:
  #   (a) lead PID gone AND any owned team handled, or
  #   (b) the pid file is removed (session ended cleanly)

  exec </dev/null >>"$LOG_FILE" 2>&1
  trap '' HUP

  # lead_alive <pid> <lstart-at-spawn> → 0 iff the pid is live AND is still the process this daemon
  # was born watching.
  #
  # THE WEDGE THIS CLOSES. The check here used to be a bare `kill -0 "$pid"`, which answers only
  # "some process holds this pid" — and macOS recycles pids. Once the lead died and its pid was
  # reused, the answer flipped back to ALIVE permanently, so NEITHER of this loop's exit conditions
  # could ever become true again and the daemon polled forever. Measured on this machine
  # 2026-07-29: 63 live daemons, 14 of them named by no .daemon file, oldest 1d15h, against 157
  # spawns and ZERO exits of EITHER kind logged that day (0 "pid file gone", 0 "LEAD CRASH
  # detected") — the whole population had stopped being able to finish.
  #
  # The remedy is the {pid, start-time} identity this very file already uses on the DAEMON
  # (daemon_alive, above) and cc-reaper uses on its sweep lock (lock_holder_alive) — it was simply
  # never applied to the SUBJECT being watched. lstart is the pin because it is the one process
  # attribute a recycled pid cannot inherit.
  #
  # Detection stays within one poll interval of the death: the instant the lead exits, `kill -0`
  # fails as it always did. The pin only decides the case where the pid was REUSED between two
  # polls, which is precisely where the old check went permanently wrong.
  #
  # Unreadable lstart at spawn ⇒ stored empty ⇒ fall back to bare pid liveness. That is today's
  # behaviour and it keeps the bias this file states everywhere — never invent a crash — while the
  # SUPERSEDED exit below still bounds that case. Same fail-open shape as lock_holder_alive.
  # → 0 ALIVE · 1 DEAD (positive evidence) · 2 IDENTITY-LOST (ambiguous — never a crash)
  #
  # The third state is not fastidiousness, it is required. `ps -o lstart=` renders the start time
  # through the CURRENT timezone, verified on this machine against one live pid: 00:53 local, 07:53
  # under TZ=UTC, 16:53 under TZ=Asia/Tokyo. So a DST transition changes the rendered string for a
  # process that never restarted, and a pin compared as a plain string stops matching a perfectly
  # healthy lead. Reading that as death would call handle_crash against a LIVE team — a
  # shutdown_request into every teammate inbox, a CRASH_REPORT.md, and pane teardown where armed —
  # twice a year, on every daemon at once. Inventing a crash is the one thing this file says
  # everywhere it must never do, and it is strictly worse than the wedge being fixed here: a missed
  # exit costs an idle process, a false crash destroys working teams.
  #
  # So a mismatch alone is never fatal. It is corroborated first: a pid RECYCLED to some unrelated
  # process is no longer a claude binary, which is positive evidence of death; a pid that still IS a
  # claude binary cannot be told apart from a re-rendered clock, so it returns 2 and the caller
  # decides without claiming anything.
  lead_alive() {
    local p="$1" want="$2" cur cmd
    kill -0 "$p" 2>/dev/null || return 1          # gone — unambiguous
    [[ -n "$want" ]] || return 0                  # never pinned ⇒ bare liveness is all we have
    cur=$(ps -o lstart= -p "$p" 2>/dev/null | tr -s ' ' | sed 's/^ *//;s/ *$//')
    [[ -n "$cur" ]] || return 1
    [[ "$cur" == "$want" ]] && return 0
    cmd=$(ps -o command= -p "$p" 2>/dev/null)
    case "$cmd" in *claude.exe*|*node_modules/.bin/claude*) return 2 ;; esac
    return 1                                      # recycled to a stranger — the wedge, positively
  }

  local_watchdog() {
    local pid="$1" sid="$2" start="${3:-}"
    local pid_file="$WATCHDOG_DIR/$sid.pid" holder lrc cur repins=0

    while :; do
      # PID FILE GONE — which is NOT, on its own, evidence of a clean shutdown.
      #
      # It used to `return 0` here unconditionally, and that single line made this whole daemon
      # blind to the commonest unexpected death there is. hooks/session-end.sh:32 removes
      # $WATCHDOG_DIR/<sid>.pid on ANY exit, and SessionEnd RUNS ON A CAUGHT SIGTERM — so an
      # externally-killed session deleted its own pidfile on the way out, this check sat first in
      # the poll loop and won the race against the death check below, and the daemon left before
      # ever reaching the crash ladder. Every TERMed session laundered itself into "clean shutdown
      # elsewhere"; the watchdog could only ever fire on a death where SessionEnd did NOT run
      # (SIGKILL, panic). Measured 2026-08-09: three sessions killed by one stray `pkill`, three
      # watchdogs, three "pid file gone — exit", zero alarms.
      #
      # The discriminator already existed one function away. So: only the LIVE process is a clean
      # shutdown elsewhere (someone removed the file, the session is fine). A process that is GONE
      # goes to handle_crash, which classifies before it acts — a sanctioned teardown has a marker
      # and lands RECYCLE (ledger row only, no team teardown; handle_crash acts iff class=CRASH),
      # and an unattributed death lands CRASH, which is the alarm this file exists to raise.
      # lead_alive's ambiguous state 2 (pin mismatch, still a claude binary) stays quiet: never
      # invent a crash — a missed exit costs an idle process, a false crash destroys working teams.
      if [[ ! -f "$pid_file" ]]; then
        local plrc=0; lead_alive "$pid" "$start" || plrc=$?
        if (( plrc == 1 )); then
          echo "[watchdog $sid] pid file gone AND lead pid=$pid is gone — classifying, not assuming"
          handle_crash "$pid" "$sid"
        else
          echo "[watchdog $sid] pid file gone, lead still alive — exit"
        fi
        return 0
      fi
      # SUPERSEDED — the pidfile is keyed by sid and only THIS sid's SessionStart rewrites it, so a
      # different pid in it means the sid re-registered under a new process and a newer daemon owns
      # the watch. The spawn guard above already treats exactly that condition as "the incumbent is
      # stale" and kills it — but it can only reach daemons whose .daemon file was written, and 0
      # "retired stale watchdog" lines across 3864 spawns say it never has. Self-retirement needs no
      # bookkeeping and so cannot be lost the way that record can: the superseded daemon reads one
      # file it already knows the path of and leaves.
      holder=$(cat "$pid_file" 2>/dev/null || true)
      if [[ -n "$holder" && "$holder" != "$pid" ]]; then
        echo "[watchdog $sid] SUPERSEDED — pidfile holds $holder, not our lead $pid — exit"
        return 0
      fi
      # lead process gone = crash detected. `|| lrc=$?` keeps the non-zero returns out of errexit's
      # reach — a bare `lead_alive …` here would abort the daemon on state 1 before it could handle
      # the very death it just detected.
      lrc=0; lead_alive "$pid" "$start" || lrc=$?
      if (( lrc == 1 )); then
        echo "[watchdog $sid] LEAD CRASH detected pid=$pid"
        handle_crash "$pid" "$sid"
        return 0
      elif (( lrc == 2 )); then
        # The pin no longer matches, but the pid is still a claude process AND the SUPERSEDED check
        # above already proved this sid's pidfile still names THIS pid — only that sid's own
        # SessionStart rewrites it. Under those two facts the overwhelmingly likely reading is a
        # re-rendered start time (DST/TZ), not a recycle, so the watch continues on a fresh pin
        # rather than either claiming a crash or abandoning a live session.
        #
        # BOUNDED AT 2: a pid recycled into an unrelated claude session lands here too, and an
        # unbounded re-pin would quietly restore exactly the immortality this change removes. Two
        # re-pins covers a clock that moved; a third means the identity is genuinely gone, and we
        # leave without claiming a death we cannot evidence.
        repins=$((repins + 1))
        if (( repins > 2 )); then
          echo "[watchdog $sid] IDENTITY LOST — pid=$pid stopped matching its start-time pin after $((repins - 1)) re-pin(s); refusing to claim a crash we cannot prove — exit"
          return 0
        fi
        cur=$(ps -o lstart= -p "$pid" 2>/dev/null | tr -s ' ' | sed 's/^ *//;s/ *$//')
        echo "[watchdog $sid] re-pinning lead $pid: start-time now '$cur' (was '$start') — still a claude process, still this sid's pidfile holder"
        start="$cur"
      fi
      sleep 30
    done
  }

  CRASH_JSONL="$HOME/.claude/logs/claude-crashes.jsonl"

  handle_crash() {
    local pid="$1" sid="$2"
    local affected_team_dirs=()

    # ── ONE handler per death (belt to the single-instance guard's braces) ──
    # The guard above stops watchers ACCUMULATING; this stops two that already coexist from both
    # processing one death. The existing pid-equality pidfile removal at the end of this function
    # already de-dupes SEQUENTIAL handlers (a later daemon finds no pidfile and takes its clean-exit
    # branch), but it removes the pidfile only AFTER team handling — so two daemons waking inside that
    # window both proceed, and the death is recorded twice, the shutdown_requests injected twice, the
    # same panes torn down twice. mkdir is the atomic claim; the loser says so and returns without
    # duplicating anything. Keyed by sid AND pid so a later, genuinely different death still claims.
    local claim="$WATCHDOG_DIR/$sid.death-$pid.d" claim_mtime claim_age
    if ! mkdir "$claim" 2>/dev/null; then
      # A claim older than 10 min means its holder died mid-handling (same stale-reclaim idiom as the
      # inbox lock below); reclaim it so a crash is never left permanently unhandled by a dead handler.
      claim_mtime=$(stat -f%m "$claim" 2>/dev/null || echo 0)
      claim_age=$(( $(date +%s) - ${claim_mtime:-0} ))
      if [[ "${claim_mtime:-0}" -gt 0 && "$claim_age" -ge 600 ]]; then
        echo "[watchdog $sid] reclaiming a stale death-claim for pid=$pid (holder gone ${claim_age}s)"
      else
        echo "[watchdog $sid] death of pid=$pid already claimed by another handler — not duplicating"
        return 0
      fi
    fi

    # Classify the death + snapshot cause BEFORE team handling, so solo AND team
    # deaths land in the structured crash ledger honestly (classify_death + find_transcript
    # are defined at top level and inherited by this subshell).
    local _cls class cause kb recs mem_free concurrent
    _cls=$(classify_death "$sid" "$pid")
    class=$(printf '%s' "$_cls" | cut -f1)
    cause=$(printf '%s' "$_cls" | cut -f2)
    kb=$(printf '%s' "$_cls" | cut -f3)
    recs=$(printf '%s' "$_cls" | cut -f4)
    # BOUNDED (both probes): these are diagnostic ENRICHMENT fields on the crash row. memory_pressure
    # queries the VM subsystem and `ps aux` walks the whole process table — precisely the two things
    # that are slowest under the memory/CPU exhaustion that caused the crash being recorded. Neither
    # is worth delaying the shutdown_requests for; an empty field is honest, a hang is not.
    mem_free=$(lcw_bounded "${LCW_PROBE_TIMEOUT_S:-5}" /usr/bin/memory_pressure 2>/dev/null | awk -F'[: ]+' '/free percentage/{print $(NF)}' | tr -d '%' || true)
    # pgrep -x, never `ps aux | grep` (changed 2026-08-07): the full-table walk is O(every
    # process × argv) and under exactly the overload a crash burst creates it ran 10-30s — with
    # ~49 daemons that was ~20 CONCURRENT full scans feeding the load they were measuring
    # (load-781 incident). -x matches the COMM field exactly, so it can never match a brief in
    # some session's argv (the pgrep -f trap) and costs milliseconds. claude.exe is the bun
    # binary's comm; bare `claude` covers a directly-named binary. A node-RUN binary (comm=node)
    # is no longer counted — acceptable: this is a diagnostic enrichment field on the crash row,
    # not a verdict, and the whole eval-track fleet's comm is claude.exe. `|| true` keeps a
    # zero-match rc from tripping `set -e`, exactly as the old grep -c needed.
    concurrent=$({ lcw_bounded "${LCW_PROBE_TIMEOUT_S:-5}" /usr/bin/pgrep -x 'claude\.exe' 2>/dev/null; \
                   lcw_bounded "${LCW_PROBE_TIMEOUT_S:-5}" /usr/bin/pgrep -x 'claude' 2>/dev/null; } | sort -u | wc -l | tr -d ' ' || true)
    # claude_version — THE decisive field: the crash rate is version-correlated (a regression
    # onset at 2.1.207: 2.1.183=0.02% → 2.1.207=4.76% → 2.1.215=1.56%, all mid-Bash in-process
    # deaths, NOT transcript size). Read from the transcript tail (every record carries it), cheap.
    local cver="?" tpath sterr=""
    tpath=$(find_transcript "$sid" 2>/dev/null || true)
    [[ -n "$tpath" ]] && cver=$(tail -c 65536 "$tpath" 2>/dev/null | grep -oE '"version":"[0-9]+\.[0-9]+\.[0-9]+"' | tail -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "?")
    # stderr_log — join to the launcher's per-pid stderr capture (names the exact mechanism).
    # shellcheck disable=SC2012  # ls -1t is deliberate (newest-first mtime order on our own fixed pattern)
    sterr=$(ls -1t "$HOME/.claude/logs/stderr/"*"-${pid}.log" 2>/dev/null | head -1 || true)
    # close-record enrichment (bin/cc-close-attrib): the per-pid exit_code/signal/version + the
    # path to the (secret-safe) stderr_tail. exit_code/signal are the decisive attribution fields;
    # when the transcript never carried a version, the close-record's fills the "?".
    local cr_summary cr_exit="" cr_sig="" cr_path="" cr_ver=""
    cr_summary=$(close_record_summary "$pid")
    if [[ -n "$cr_summary" ]]; then
      cr_exit=$(printf '%s' "$cr_summary" | cut -f1)
      cr_sig=$(printf '%s' "$cr_summary" | cut -f2)
      cr_path=$(printf '%s' "$cr_summary" | cut -f3)
      cr_ver=$(printf '%s' "$cr_summary" | cut -f4)
      [[ "$cver" == "?" && -n "$cr_ver" ]] && cver="$cr_ver"
      # A pid-only join can name a STRANGER's record (pid reuse) — say so beside the death it joined.
      [[ -n "$LEAD_START_EPOCH" ]] || log "[watchdog $sid] close-record join was PID-ONLY (lead start time unknown): $cr_path"
    fi
    printf '{"ts":"%s","sid":"%s","pid":%s,"class":"%s","cause":"%s","claude_version":"%s","transcript_kb":%s,"records":%s,"mem_free_pct":"%s","concurrent_claude":%s,"stderr_log":"%s","exit_code":"%s","signal":"%s","stderr_tail_path":"%s","version":"%s"}\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$sid" "${pid:-0}" "$class" "$cause" "${cver:-?}" "${kb:-0}" "${recs:-0}" "${mem_free:-?}" "${concurrent:-0}" "${sterr:-}" "${cr_exit:-}" "${cr_sig:-}" "${cr_path:-}" "${cr_ver:-}" \
      >> "$CRASH_JSONL" 2>/dev/null || true
    echo "[watchdog $sid] death class=$class cause=$cause (${kb}KB/${recs}recs mem_free=${mem_free:-?}% concurrent=${concurrent})"
    # A deliberate recycle is not a crash — only alert on a genuine crash.
    if [[ "$class" == "CRASH" ]]; then
      lcw_osa osascript -e "display notification \"Session ${sid:0:8} crashed — ${cause}. See claude-crashes.jsonl\" with title \"Claude Crash\" sound name \"Basso\"" 2>/dev/null || true
    fi
    # The pane verdict, for EVERY class — a clean exit whose pane survived is exactly the other half
    # of the ambiguity (see paint_pane_verdict). Backgrounded: it waits up to 45 s for the pane to
    # settle, and the team legs below must not wait behind it. It logs its own outcome.
    ( paint_pane_verdict "$sid" "$pid" "$class" "$cause" "${cr_exit:-}" "${cr_sig:-}" "$tpath" ) </dev/null >/dev/null 2>&1 &

    # THE DEATH PAGE — deliberately placed HERE, above the team scan, not inside it. This is the
    # whole fix: the incident's session reached the `no teams affected` early-return below and
    # stopped, because a Dynamic Workflow's agents are in-process subagents and own no team config.
    # A durable page must not be reachable only through the branch that structurally cannot see the
    # loudest case. Best-effort by construction — see the block comment at the top of this file.
    surface_death "$sid" "$pid" "$class" "$cause" "$tpath" "${cr_exit:-}" "${cr_sig:-}" || true

    # Which teams had this session as lead? Scan ALL team roots — CC writes
    # $CLAUDE_CONFIG_DIR/teams/<team>/, so *2/*3-launcher leads (claude-next2 /
    # claude-fable2 → ~/.claude-secondary; claude-next3 / claude-fable3 →
    # ~/.claude-tertiary) keep their team state only under that account's teams/
    # (memory: teammate-shutdown-secondary-config-dir-2026-06-09). The dir each
    # config was FOUND in is carried through — never re-derived from a root.
    for team_config in "$HOME/.claude/teams"/*/config.json "$HOME/.claude-secondary/teams"/*/config.json "$HOME/.claude-tertiary/teams"/*/config.json; do
      [[ -f "$team_config" ]] || continue
      local team_dir
      team_dir=$(dirname "$team_config")
      local team_name
      team_name=$(basename "$team_dir")
      [[ "$team_name" == "_archive" ]] && continue
      local lead_sid
      lead_sid=$(jq -r '.leadSessionId // empty' "$team_config" 2>/dev/null)
      if [[ "$lead_sid" == "$sid" ]]; then
        affected_team_dirs+=("$team_dir")
      fi
    done

    if [[ ${#affected_team_dirs[@]} -eq 0 ]]; then
      echo "[watchdog $sid] crash — no teams affected (lead had no active team)"
      # rm-race guard: only reap the pidfile if it still holds OUR pid — a resume/re-fire may have
      # overwritten it with the successor incarnation's LIVE pid, and deleting that silently disarms
      # a live session (frontier finding: 125 proven cross-incarnation disarms).
      if [[ "$(cat "$WATCHDOG_DIR/$sid.pid" 2>/dev/null)" == "$pid" ]]; then
        rm -f "$WATCHDOG_DIR/$sid.pid" "$WATCHDOG_DIR/$sid.id" "$WATCHDOG_DIR/$sid.daemon"
        gc_teardown_marker "$sid" "$pid" || true
      fi
      rmdir "$claim" 2>/dev/null || true      # release the death-claim (never leave a dir per death)
      return 0
    fi

    echo "[watchdog $sid] crash affects ${#affected_team_dirs[@]} team(s): ${affected_team_dirs[*]}"

    # ORDER IS LOAD-BEARING: harvest (a) → shutdown_request → close panes (b). cc-teardown kills
    # the process and closes the pane, and a closed pane cannot be harvested — so the reports come
    # off disk FIRST, unconditionally, and only then is anything reaped.
    for team_dir in "${affected_team_dirs[@]}"; do
      write_crash_report "$team_dir" "$pid" "$sid"
      harvest_team_reports "$team_dir" "$sid"
      send_shutdown_requests "$team_dir" "$sid"
      close_orphaned_panes "$team_dir" "$sid"
    done

    lcw_osa osascript -e "display notification \"Lead crashed. ${#affected_team_dirs[@]} team(s) affected. See CRASH_REPORT.md\" with title \"Claude Code Watchdog\" sound name \"Basso\"" 2>/dev/null || true
    printf '\a' >/dev/tty 2>/dev/null || true

    # rm-race guard (see above): never delete a pidfile a successor incarnation now owns.
    if [[ "$(cat "$WATCHDOG_DIR/$sid.pid" 2>/dev/null)" == "$pid" ]]; then
      rm -f "$WATCHDOG_DIR/$sid.pid" "$WATCHDOG_DIR/$sid.id" "$WATCHDOG_DIR/$sid.daemon"
      gc_teardown_marker "$sid" "$pid" || true
    fi
    rmdir "$claim" 2>/dev/null || true        # release the death-claim (never leave a dir per death)
  }


  write_crash_report() {
    local team_dir="$1" pid="$2" sid="$3"
    local team_name
    team_name=$(basename "$team_dir")
    local team_root
    team_root=$(dirname "$team_dir")
    local report="$team_dir/CRASH_REPORT.md"

    {
      echo "# Lead Crash Report"
      echo ""
      echo "- **Team**: $team_name"
      echo "- **Lead PID**: $pid (dead at $(date '+%Y-%m-%d %H:%M:%S'))"
      echo "- **Lead session**: $sid"
      echo ""
      echo "## Members"
      jq -r '.members[] | "- \(.name) (agentId=\(.agentId), cwd=\(.cwd // "?"))"' \
        "$team_dir/config.json" 2>/dev/null || echo "- (unable to parse config.json)"
      echo ""
      echo "## Last 5 inbox messages per member"
      for inbox in "$team_dir/inboxes"/*.json; do
        [[ -f "$inbox" ]] || continue
        local member
        member=$(basename "$inbox" .json)
        [[ "$member" == "team-lead" ]] && continue
        echo ""
        echo "### $member"
        jq -r '.[-5:] | .[] | "- [\(.timestamp // "?")] from=\(.from // "?"): \(.summary // (.text | tostring | .[0:200]))"' \
          "$inbox" 2>/dev/null || echo "(unable to parse)"
      done
      echo ""
      echo "## Harvested assignee reports"
      echo ""
      echo "Final reports are recovered from DISK TRUTH (each assignee's transcript) into"
      echo "\`$team_dir/HARVEST/\` — one \`<member>.md\` per assignee, plus \`status.tsv\`."
      echo "They are NOT in any inbox: a named assignee's final text is never delivered as a"
      echo "message, so the transcript is the only place it exists. Read these BEFORE respawning —"
      echo "finished work must never be re-run."
      echo ""
      echo "## Recovery"
      echo ""
      echo "1. Start a new claude session. Do NOT \`claude --resume\`."
      echo "2. Archive this team dir: \`mv $team_dir $team_root/_archive/$team_name-\$(date +%s)\`"
      echo "3. Respawn from disk truth: \`python3 ~/.claude/scripts/limit-recover/lr-audit.py --team $team_name --salvage-dir /tmp/lr-salvage-$team_name\` — VERBATIM respawn briefs land in salvage/teams/$team_name/<member>.json (.respawn_call). Read deliverables already on disk first (never re-run finished work); course-change respawns via \`cc-respawn\`."
      echo "4. Check teammate worktrees for uncommitted work: \`git reflog refs/checkpoints/<member>/\` (if teammate-checkpoint.sh was active)."
      echo ""
    } > "$report"

    echo "[watchdog] wrote $report"
  }

  send_shutdown_requests() {
    local team_dir="$1" sid="$2"

    for inbox in "$team_dir/inboxes"/*.json; do
      [[ -f "$inbox" ]] || continue
      local member
      member=$(basename "$inbox" .json)
      [[ "$member" == "team-lead" ]] && continue

      local envelope
      envelope=$(jq -n \
        --arg from "watchdog" \
        --arg text "{\"type\":\"shutdown_request\",\"reason\":\"lead crashed — see CRASH_REPORT.md\"}" \
        --arg summary "LEAD CRASH — shutting down" \
        --arg ts "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)" \
        '{from:$from, text:$text, summary:$summary, timestamp:$ts, read:false}')

      # Append to inbox array. jq read-modify-write is NOT atomic, and team-orphan-reaper.sh
      # appends to the SAME inbox under the SAME lock name ("$inbox.lock.d") — an unguarded
      # race drops one append. mkdir is atomic → use it as the mutex: acquire ≤2s (20×0.1s);
      # a lock dir older than 10s ⇒ a crashed holder, reclaim it; on give-up append lock-free
      # (a duplicate shutdown_request is harmless, a hung watchdog is not). rmdir after mv.
      local lockd="$inbox.lock.d" have_lock=0 i lock_age lock_mtime now_s
      for (( i=0; i<20; i++ )); do
        if mkdir "$lockd" 2>/dev/null; then have_lock=1; break; fi
        lock_mtime=$(stat -f%m "$lockd" 2>/dev/null || echo 0)
        now_s=$(date +%s)
        lock_age=$(( now_s - lock_mtime ))
        if (( lock_mtime > 0 && lock_age >= 10 )); then
          rmdir "$lockd" 2>/dev/null || true   # stale holder — reclaim on the next iteration
        fi
        sleep 0.1
      done

      local tmp
      tmp=$(mktemp)
      if jq --argjson env "$envelope" '. += [$env]' "$inbox" > "$tmp" 2>/dev/null; then
        mv "$tmp" "$inbox"
        echo "[watchdog] shutdown_request → $member"
      else
        rm -f "$tmp"
        echo "[watchdog] WARN: failed to inject shutdown_request for $member"
      fi
      if (( have_lock )); then rmdir "$lockd" 2>/dev/null || true; fi
    done
  }

  local_watchdog "$LEAD_PID" "$SESSION_ID" "$LEAD_START"
) </dev/null >/dev/null 2>&1 &
WATCHDOG_PID=$!
disown

# Record the daemon's {pid, start-time} so the next SessionStart can tell a live incumbent from a
# recycled pid. Written by the PARENT (the subshell cannot portably read its own lstart before doing
# work) and best-effort: an unwritable file degrades to today's behaviour — a duplicate spawn — never
# to a missing watcher. If lstart is unreadable the identity is left unverifiable, which daemon_alive
# treats as NOT alive: it re-spawns rather than risk skipping and leaving a session unwatched.
WATCHDOG_START=$(ps -o lstart= -p "$WATCHDOG_PID" 2>/dev/null | tr -s ' ' | sed 's/^ *//;s/ *$//')
printf '%s\t%s\n' "$WATCHDOG_PID" "$WATCHDOG_START" > "$DAEMON_FILE" 2>/dev/null || true

log "spawned watchdog daemon pid=$WATCHDOG_PID for session=$SESSION_ID pid=$LEAD_PID"
exit 0
