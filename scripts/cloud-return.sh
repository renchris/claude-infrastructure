#!/usr/bin/env bash
# cloud-return.sh — THE RETURN PATH for a cloud fire (CLOUD_BACKLOG_PIPELINE.md W2, §5 clauses 3-5
# and the land/mark-done arm of 7).
#
#   scripts/cloud-return.sh --sweep [--dry-run]              every MANAGED declaration, one pass
#   scripts/cloud-return.sh --id <session-id> [--dry-run]     one session
#
# WHY THIS EXISTS. A local `handoff-fire` gives its originator four things: a notify-back ping when
# the peer finishes, a custody debt that makes `✅ SAFE TO CLOSE` mechanically unreachable while the
# peer is in flight, a `--goal` re-judged against a measurable end state, and an auto-land. A cloud
# fire gave an id. Everything else was hand-work — the lead polled `cc-offload ls`, or the work sat
# finished and unnoticed (CLOUD_BACKLOG_PIPELINE.md §2 rows 1-4). This script is the missing half:
# it detects completion, lands the result, verifies it BY CONTENT, judges the goal, settles the
# backlog item — `done`, or `block` when the VM landed a park saying the next step is the
# operator's (step 8) — discharges custody, and WAKES the originator.
#
# ── THE ORIGINATOR MUST NOT BE THE POLLER, and that is a hard design constraint ──────────────────
# A goal-armed session CANNOT hold a backgrounded watcher: Claude Code skips /goal evaluation while
# any non-terminal background Bash exists, and hooks/validate-bash.sh DENIES the park outright
# (memory: goal-stop-hook-vs-task-registry). So the poller has to live somewhere else entirely.
# It lives in launchd — `scripts/autonomy-sweep.sh` (com.chrisren.autonomy-sweep, loaded, 300 s)
# calls `--sweep` — and it reaches the originator over the SAME v2 inbox transport a local peer
# uses: cc-notify APPENDS to ~/.claude/mailbox/<uuid>.md, which wakes an armed watcher instantly and
# otherwise lands at the originator's next turn boundary. Nothing is ever typed into a composer, and
# no session polls anything.
#
# ── COMPLETION IS A CONJUNCTION, BECAUSE `idle` PROVES NOTHING ON ITS OWN ────────────────────────
# Measured 2026-08-11 against the live control plane: a session that finished 14 h ago and a session
# fired 4 MINUTES earlier BOTH read `worker_status: idle` / `status_bucket: review_ready`. Idle is
# the between-turns state as much as the finished state — the identical shape as the harness's own
# `idleReason`, which is painted "finished" at every Stop (memory: shutdown-request-is-not-an-
# actuator: idle TRIGGERS, never PROVES). Landing on that alone would cut a session off mid-flight
# and land a half-finished branch, which is worse than never returning at all.
# So RETURN-READY is three independent facts, and the third is the one that carries the weight:
#   1. the VM has PUSHED — cc-cloud's state function says a ref exists and moved off its fire-time
#      baseline (ALIVE / STALLED / ABANDONED; LANDED means it is already home).
#   2. the control plane says the worker is not running — the TRIGGER. Unreadable ⇒ UNKNOWN ⇒
#      abstain, never "probably done" (a sensor that could not run is not a verdict).
#   3. the pushed sha has been QUIET for CC_RETURN_QUIET_S (default 180 s), measured from
#      cc-cloud's own `.seen` sidecar. A session that is merely between turns pushes again; one
#      that is finished does not. This is the axis that is INDEPENDENT of the idle flag, which is
#      the whole reason it is here (memory: proxy-must-be-independent-of-what-it-supplements).
#
# ── THE SWEEP'S POPULATION IS WHAT THE SWEEP ARMED ──────────────────────────────────────────────
# `--sweep` acts ONLY on declarations carrying the W2 management fields (`notify_back` or
# `custody`). Every pre-W2 declaration — 20+ on this box, several with pushed, never-landed
# branches — was fired with nobody promising to land it, and sweeping those up would mean this
# script deciding unattended that a stranded branch from three days ago belongs on trunk. `--id`
# lands one by name (a person named it). The admission rule is an OPT-IN recorded at fire time, for
# the same reason cloud-reconcile refuses undeclared branches by default.
#
# ── WHAT IT DOES NOT DO ─────────────────────────────────────────────────────────────────────────
# It does not re-implement the land (scripts/cloud-reconcile.sh → desk-land → ship-land own that,
# with the landing lock, the identity re-author, the gate and the content-verify), it does not
# re-derive a state (bin/cc-cloud is the arbiter), and it does not route a REFUSAL back to the VM —
# that is W3. On a refusal it records the artifact W3 will consume (`<id>.land-refused`), wakes the
# originator with the failure, and leaves custody OPEN, because an un-landed result is exactly the
# state custody exists to keep from reading as done.
#
# EXITS: 0 the pass completed (per-session outcomes are on stdout and in the ledger) · 2 usage ·
#   3 a precondition is missing (no cc-cloud, no jq) · 4 the lock is held by a live pass.
#   A per-session failure is REPORTED, never fatal to the pass — one bad session must not strand
#   every other one behind it.
#
# Env seams (the suite overrides all of them; nothing here touches the real fleet under test):
#   CC_CLOUD_STATE · CC_RETURN_QUIET_S · CC_RETURN_CLOUD_BIN · CC_RETURN_NOTIFY_BIN ·
#   CC_RETURN_CUSTODY_BIN · CC_RETURN_BACKLOG_BIN · CC_RETURN_RECONCILE_BIN · CC_RETURN_STATUS_BIN
#   (the control-plane sensor: <bin> --account A --verify ID → json on stdout) · CC_RETURN_GIT_BIN ·
#   CC_RETURN_NOW (epoch override) · CC_RETURN_LEDGER
#
# bash 3.2-safe.
set -uo pipefail

SELF="$0"; while [ -L "$SELF" ]; do _t="$(readlink "$SELF")"; case "$_t" in /*) SELF="$_t" ;; *) SELF="$(dirname "$SELF")/$_t" ;; esac; done
ROOT="$(cd "$(dirname "$SELF")/.." && pwd -P)"

STATE="${CC_CLOUD_STATE:-$HOME/.claude/autonomy/cloud}"
QUIET_S="${CC_RETURN_QUIET_S:-180}"
GIT_BIN="${CC_RETURN_GIT_BIN:-git}"
LEDGER="${CC_RETURN_LEDGER:-$STATE/return.jsonl}"

resolve() { # <override> <name> <fallback-path…>
  local ov="$1" name="$2"; shift 2
  [ -n "$ov" ] && { printf '%s' "$ov"; return 0; }
  local c
  for c in "$@" "$(command -v "$name" 2>/dev/null || true)"; do
    [ -n "$c" ] && [ -x "$c" ] && { printf '%s' "$c"; return 0; }
  done
  return 0
}
CLOUD_BIN="$(resolve "${CC_RETURN_CLOUD_BIN:-}" cc-cloud "$ROOT/bin/cc-cloud" "$HOME/.claude/bin/cc-cloud")"
NOTIFY_BIN="$(resolve "${CC_RETURN_NOTIFY_BIN:-}" cc-notify "$ROOT/bin/cc-notify" "$HOME/.claude/bin/cc-notify")"
CUSTODY_BIN="$(resolve "${CC_RETURN_CUSTODY_BIN:-}" cc-custody "$ROOT/bin/cc-custody" "$HOME/.claude/bin/cc-custody")"
BACKLOG_BIN="$(resolve "${CC_RETURN_BACKLOG_BIN:-}" cc-backlog "$ROOT/bin/cc-backlog" "$HOME/.claude/bin/cc-backlog")"
RECONCILE_BIN="${CC_RETURN_RECONCILE_BIN:-$ROOT/scripts/cloud-reconcile.sh}"
STATUS_BIN="${CC_RETURN_STATUS_BIN:-$ROOT/scripts/cloud-create-api.py}"

MODE="" ONE="" DRY=0
# THE PER-TICK BOUND. Default 25, not unlimited, because the failure this fixes is a pass that could
# never finish: measured 2026-09-01, `--sweep` over 466 managed declarations spent ~675 s of its
# caller's 900 s bound on FIXED cost before attempting a single land, and was SIGKILLed every time
# (`cloud_return_rc` timeline: 137, 4, 4, 4, 4, 4, 137, 137, 137 — no success since 2026-08-24).
# An unbounded default would leave that true for anyone who forgets the flag, so the safe value is
# the default and `--limit 0` is the explicit opt-out. `--id` is unaffected: a person named one.
LIMIT="${CC_RETURN_LIMIT:-25}"
while [ $# -gt 0 ]; do
  case "$1" in
    --sweep) MODE=sweep; shift ;;
    --id) MODE=one; ONE="${2:-}"; shift 2 ;;
    --id=*) MODE=one; ONE="${1#--id=}"; shift ;;
    --limit) LIMIT="${2:-}"; shift 2 ;;
    --limit=*) LIMIT="${1#--limit=}"; shift ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) sed -n '2,40p' "$SELF" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "cloud-return: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
[ -n "$MODE" ] || { echo "cloud-return: pass --sweep or --id <session-id>" >&2; exit 2; }
case "$LIMIT" in ''|*[!0-9]*) echo "cloud-return: --limit wants a non-negative integer (0 = unbounded)" >&2; exit 2 ;; esac
[ -n "$CLOUD_BIN" ] || { echo "cloud-return: cc-cloud not found — the declaration store is unreadable" >&2; exit 3; }
command -v jq >/dev/null 2>&1 || { echo "cloud-return: jq required" >&2; exit 3; }

now() { if [ -n "${CC_RETURN_NOW:-}" ]; then printf '%s' "$CC_RETURN_NOW"; else date +%s; fi; }
say() { printf '%s\n' "$*"; }
warn() { printf '%s\n' "cloud-return: $*" >&2; }

# The ledger is append-only evidence, one row per session per pass. It is what makes "the ping was
# sent" and "the ping could not be sent" different facts afterwards — a `|| true` on the notify
# would erase exactly that distinction (memory: claimed-outcome-vs-checked-outcome).
ledger() { # <id> <outcome> <detail-json-object>
  mkdir -p "$(dirname "$LEDGER")" 2>/dev/null || return 0
  jq -cn --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg id "$1" --arg out "$2" --argjson d "$3" \
    '{ts:$ts, id:$id, outcome:$out} + $d' >>"$LEDGER" 2>/dev/null || true
}

# ── single flight ────────────────────────────────────────────────────────────────────────────────
# A land can outlast the 300 s sweep cadence, so two passes CAN overlap. The lock is a directory
# (atomic on every filesystem this runs on) with an age-based reap: a pass killed by its caller's
# timeout must not wedge the rail forever, which is the failure mode a lockfile without a reaper has.
#
# 🚨 THE AGE REAP ALONE WAS THE SECOND KILL IN THE CHAIN, AND IT COST TWELVE TICKS PER INCIDENT.
# The trap below is `EXIT INT TERM` — none of which run on SIGKILL — and this caller bounds the pass
# with `timeout -k 10 900`, whose `-k` is precisely a SIGKILL. So every cut pass left the lock
# directory behind by construction, and a 3600 s reap window against a 300 s cadence meant the next
# ~12 ticks all exited 4 without doing one unit of work. That is the run of `4`s in the caller's own
# journal (`cloud_return_rc`: 137, 4, 4, 4, 4, 4, 137, …) — the kill is the event, and the eleven
# following non-events are this window.
#
# TWO REPAIRS, AND THE FIRST IS THE REAL ONE.
#
# (1) ASK WHETHER THE HOLDER IS ALIVE. The lock already recorded its holder's pid and nothing ever
#     read it. A pid that no longer exists is a DEAD holder — a fact, available immediately, that no
#     amount of waiting improves — so the reap is instant and the SIGKILL costs zero ticks instead
#     of twelve. Pid reuse is the standing objection and it is handled rather than hoped away: a
#     LIVE pid still has to satisfy the age window below, so a recycled pid can at worst restore the
#     old timeout behaviour, never steal from a running pass.
#
# (2) SIZE THE WINDOW TO THE CALLER'S BOUND, NOT TO A ROUND NUMBER. 3600 s was never derived from
#     anything this script does. The pass is bounded by its caller at 900 s (+10 s for the `-k`
#     grace), so a genuinely-running pass CANNOT exceed that; anything older is dead whatever its
#     pid says. `CC_RETURN_LOCK_TTL_S` defaults to 1200 s — the caller's bound plus a third — which
#     is narrower than 3600 s, not wider. Narrowing matters: the instruction here was explicitly not
#     to widen the window to where a genuinely concurrent pass could be stolen from, and a
#     pid-liveness check plus a bound-derived TTL is the shape that reaps faster while stealing
#     less. A caller that bounds differently sets the env var; hardcoding its number here would be
#     this repo's resident-rule-restates-a-perishable-fact defect in a lock.
LOCK="$STATE/.return.lock"
LOCK_TTL_S="${CC_RETURN_LOCK_TTL_S:-1200}"
case "$LOCK_TTL_S" in ''|*[!0-9]*) LOCK_TTL_S=1200 ;; esac
lock_acquire() {
  mkdir -p "$STATE" 2>/dev/null || return 1
  if mkdir "$LOCK" 2>/dev/null; then printf '%s\n' "$$" >"$LOCK/pid" 2>/dev/null; return 0; fi
  local age start pid why=""
  start="$(cat "$LOCK/at" 2>/dev/null)"; case "$start" in ''|*[!0-9]*) start=0 ;; esac
  age=$(( $(now) - start ))
  pid="$(cat "$LOCK/pid" 2>/dev/null | head -1)"; case "$pid" in ''|*[!0-9]*) pid="" ;; esac
  # A holder we can PROVE is gone is reaped now. `kill -0` is the liveness question and nothing
  # else: rc 0 = alive, anything else = not ours to wait for. An UNREADABLE pid is deliberately not
  # treated as dead — that is a miss, not an absence, and it falls through to the age window, which
  # is the arm that can still decide it (memory: lookup-miss-is-not-absence).
  if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
    why="its holder (pid $pid) is gone — a killed pass runs no EXIT trap"
  elif [ "$start" -gt 0 ] && [ "$age" -lt "$LOCK_TTL_S" ]; then
    return 1
  else
    why="it has been held for ${age}s, past the ${LOCK_TTL_S}s window"
  fi
  warn "reaping the lock: $why"
  rm -rf "$LOCK" 2>/dev/null
  mkdir "$LOCK" 2>/dev/null || return 1
  printf '%s\n' "$$" >"$LOCK/pid" 2>/dev/null
  return 0
}
# shellcheck disable=SC2329
#   Invoked from the EXIT/INT/TERM trap below, which shellcheck cannot see — it is not dead.
lock_release() { rm -rf "$LOCK" 2>/dev/null || true; }

# ── the control-plane sensor ─────────────────────────────────────────────────────────────────────
# Returns the worker_status in WS_STATUS, rc 0. rc 2 = COULD NOT LOOK, which is never read as "done"
# (the one rule the whole cloud subsystem is organised around). The account is required: a session
# id is scoped to the account that created it, and the wrong account's read is indistinguishable
# from a deleted session (bin/cc-offload's `open` carries the same warning).
#
# 🚨 IT ANSWERS THROUGH GLOBALS, NOT STDOUT, AND THAT IS THE WHOLE POINT OF THE 2026-08-17 REWRITE.
# The first cut returned the status on stdout, so its caller wrote `ws="$(worker_status …)"` — a
# COMMAND SUBSTITUTION, i.e. a subshell. Any diagnostic this function set would have died with that
# subshell, which is why the failure could only ever be recorded as the bare, unactionable
# `{"why":"control plane unreadable"}`: 384 such rows on this box, not one naming a cause. Stdout is
# the only channel a subshell preserves and it was already spoken for by the answer, so the answer
# had to move off it before the diagnosis could exist at all.
#
# The callee was muted twice over. `2>/dev/null` threw the status bin's own words away — and those
# words are the diagnosis, because cloud-create-api.py's `die()` prints exactly which precondition
# failed (`keychain item 'X' unreadable (rc N) — try /relogin`, `account 'X' not in accounts.json`,
# an HTTP status). rc was discarded too, and rc 127 (python3 not on the daemon's PATH) is a wholly
# different repair from rc 3 (a locked keychain) which is a wholly different repair from rc 1 (a 401
# on an expired grant). One caller's `2>/dev/null` erased the difference between all three
# (memory: callers-dependency-probe-mutes-the-callees-non-verdict).
WS_STATUS="" WS_ERR="" WS_RC=""
worker_status() { # <account> <id> → 0 + WS_STATUS · 2 cannot look (WS_ERR/WS_RC carry why)
  local acct="$1" id="$2" out rc errf
  WS_STATUS="" WS_ERR="" WS_RC=""
  [ -n "$acct" ] || { WS_ERR="the declaration records no account, and a session id is only readable through the account that created it"; WS_RC="no-account"; return 2; }
  [ -f "$STATUS_BIN" ] || { WS_ERR="the status bin is absent at $STATUS_BIN"; WS_RC="no-status-bin"; return 2; }
  errf="$(mktemp -t ccret-ws.XXXXXX 2>/dev/null || printf '/tmp/ccret-ws.%s' "$$")"
  out="$(python3 "$STATUS_BIN" --account "$acct" --verify "$id" 2>"$errf")"; rc=$?
  WS_RC="$rc"
  # Sanitised and bounded: this string goes into a jq --arg and then into an append-only ledger, so
  # a stray newline or control byte must not be able to shape the row it is evidence in.
  WS_ERR="$(tr '\n\t' '  ' <"$errf" 2>/dev/null | tr -cd '\40-\176' | tail -c 300)"
  rm -f "$errf" 2>/dev/null || true
  if [ -z "$out" ]; then
    # --verify exits 5 when the ACCEPTANCE PAIR fails, which is a statement about how the session
    # was created and not about whether it is running. If it printed a record, read the record —
    # so only an EMPTY record is a non-verdict, whatever the rc was.
    [ -n "$WS_ERR" ] || WS_ERR="the status bin exited $rc and printed nothing on either stream"
    return 2
  fi
  WS_STATUS="$(printf '%s' "$out" | jq -r '.worker_status // empty' 2>/dev/null)"
  WS_ERR=""
  return 0
}

# ── goal evaluation, from THIS side ──────────────────────────────────────────────────────────────
# A cloud VM cannot run our hooks, so a `/goal` in the VM would be unreadable here and a goal keyed
# on the VM's own prose would be unfalsifiable. The end state is therefore always something this box
# can measure: the landed-by-content verdict by default, or an explicit probe (exit 0 = MET) that
# the fire recorded. Same shape as a backlog falsifier, deliberately — one idiom for "the check that
# decides", not two.
#
# 🚨 A PROBE RUNS WITH cwd = THE DECLARED REPO, WHICH IS A WORKING TREE SOMEBODY ELSE OWNS. The
# shared checkout sits on whatever branch its last session left it on, so a probe written as
# `grep -q X docs/thing.md` grades a file that may not be checked out at all — and grep's exit 2
# ("no such file") is indistinguishable here from exit 1 ("not there"), so a probe can read NOT-MET
# over work that landed perfectly. Write probes against the TRUNK REF —
# `git show origin/main:docs/thing.md | grep -q X` — which is the same ref the content-verify uses
# and the only thing about this box that a cloud land actually changes.
GOAL_DETAIL=""
goal_verdict() { # <repo> <goal-probe> <landed:0|1> → 0 MET · 1 NOT MET · 2 could not judge
  local repo="$1" probe="$2" landed_ok="$3" rc=0
  GOAL_DETAIL=""
  if [ -z "$probe" ]; then
    GOAL_DETAIL="the default end state — the declared paths are content-present on trunk"
    [ "$landed_ok" = 0 ] && return 0 || return 1
  fi
  local tmo; tmo="$(command -v timeout 2>/dev/null || command -v gtimeout 2>/dev/null || true)"
  if [ -n "$tmo" ]; then ( cd "${repo:-$ROOT}" && "$tmo" -k 5 120 bash -c "$probe" ) >/dev/null 2>&1; rc=$?
  else ( cd "${repo:-$ROOT}" && bash -c "$probe" ) >/dev/null 2>&1; rc=$?; fi
  case "$rc" in
    0) GOAL_DETAIL="the recorded goal probe exited 0"; return 0 ;;
    124|137) GOAL_DETAIL="the goal probe TIMED OUT — that is 'could not judge', never 'not met'"; return 2 ;;
    *) GOAL_DETAIL="the recorded goal probe exited $rc"; return 1 ;;
  esac
}

# ── the wake ─────────────────────────────────────────────────────────────────────────────────────
# One line, in the same HANDOFF-PING shape a fired local peer uses, so the originator's mailbox
# reader needs no new case. The cc-notify VERDICT is captured and recorded: "wake-path armed" (the
# watcher takes it in seconds), "NO watcher armed" (next turn boundary) and "mailbox only" (the
# target is gone) are three different outcomes and an originator that never woke deserves to be
# distinguishable afterwards from one that woke late.
WAKE_DETAIL=""
wake() { # <notify-back-uuid> <message> → 0 sent · 1 not sent · 3 no target
  local target="$1" msg="$2" out rc
  WAKE_DETAIL=""
  [ -n "$target" ] || { WAKE_DETAIL="the declaration names no notify-back target — nothing to wake"; return 3; }
  [ -n "$NOTIFY_BIN" ] || { WAKE_DETAIL="cc-notify not found on this box"; return 1; }
  out="$("$NOTIFY_BIN" "$target" "$msg" 2>&1)"; rc=$?
  WAKE_DETAIL="$(printf '%s' "$out" | tr '\n' ' ' | cut -c1-240)"
  [ "$rc" -eq 0 ] || return 1
  return 0
}

# ── one session ──────────────────────────────────────────────────────────────────────────────────
# Reads its facts from ONE call to the arbiter (`cc-cloud list --json --state`) rather than opening
# the declaration with a second parser — this store has one reader and it is cc-cloud.
handle() { # <row-json> → prints outcome lines
  local row="$1"
  local id branch acct state repo trunk paths nb goal probe custody item url
  id="$(printf '%s' "$row" | jq -r '.id')"
  branch="$(printf '%s' "$row" | jq -r '.branch // ""')"
  acct="$(printf '%s' "$row" | jq -r '.account // ""')"
  state="$(printf '%s' "$row" | jq -r '.state // "UNKNOWN"')"
  repo="$(printf '%s' "$row" | jq -r '.repo // ""')"
  trunk="$(printf '%s' "$row" | jq -r '.trunk // ""')"; [ -n "$trunk" ] || trunk="origin/main"
  paths="$(printf '%s' "$row" | jq -r '.paths // ""')"
  nb="$(printf '%s' "$row" | jq -r '.notify_back // ""')"
  goal="$(printf '%s' "$row" | jq -r '.goal // ""')"
  probe="$(printf '%s' "$row" | jq -r '.goal_probe // ""')"
  custody="$(printf '%s' "$row" | jq -r '.custody // ""')"
  item="$(printf '%s' "$row" | jq -r '.item_id // ""')"
  url="$(printf '%s' "$row" | jq -r '.url // ""')"

  # LATCHED. The ping fires once per session, ever: an originator re-woken every 300 s about work it
  # already collected is an alarm that always fires, which carries the same zero bits as one that
  # never does (memory: alarm-polarity-and-attention-budget).
  if [ -f "$STATE/$id.returned" ]; then say "· $id — already returned ($(sed -n 's/^outcome=//p' "$STATE/$id.returned" | head -1))"; return 0; fi

  # 1. HAS IT PUSHED? cc-cloud's verdict, adopted verbatim.
  case "$state" in
    UNKNOWN)     say "? $id — cc-cloud could not measure it; abstaining (a sensor that could not run is not a verdict)"
                 ledger "$id" abstain '{"why":"state UNKNOWN"}'; return 0 ;;
    BOOTING)     say "· $id — BOOTING, nothing pushed yet"; return 0 ;;
    NOT-STARTED) say "· $id — NOT-STARTED (cc-cloud already rows this); nothing to return"; return 0 ;;
    LANDED|ALIVE|STALLED|ABANDONED) ;;
    *)           say "· $id — state $state is not a return state"; return 0 ;;
  esac

  # 2. IS THE WORKER STILL RUNNING? The trigger, and only the trigger.
  # Called BARE — never `$(worker_status …)`. The diagnosis it sets lives in globals, and a command
  # substitution would run it in a subshell and discard every one of them (see the sensor above).
  local ws wrc=0
  worker_status "$acct" "$id" || wrc=$?
  ws="$WS_STATUS"
  if [ "$wrc" -ne 0 ]; then
    say "? $id — the control plane could not be read (account '${acct:-unset}', rc ${WS_RC:-?}: ${WS_ERR:-no diagnostic}); abstaining rather than guessing it is finished"
    ledger "$id" abstain "$(jq -cn --arg e "$WS_ERR" --arg r "$WS_RC" --arg a "$acct" \
      '{why:"control plane unreadable", err:$e, rc:$r, account:$a}')"
    return 0
  fi
  case "$ws" in
    working|running|in_progress|busy)
      say "· $id — worker_status=$ws; still running"
      ledger "$id" waiting "$(jq -cn --arg w "$ws" '{worker_status:$w}')"; return 0 ;;
  esac

  # 3. HAS THE PUSH GONE QUIET? The independent axis — `idle` is also the between-turns state, so
  # without this a session mid-flight would be landed half-finished.
  local seen_sha seen_since quiet_for
  seen_sha="$(sed -n 's/^sha=//p' "$STATE/$id.seen" 2>/dev/null | head -1)"
  seen_since="$(sed -n 's/^since=//p' "$STATE/$id.seen" 2>/dev/null | head -1)"
  case "$seen_since" in ''|*[!0-9]*) seen_since="" ;; esac
  if [ "$state" != LANDED ]; then
    if [ -z "$seen_sha" ] || [ -z "$seen_since" ]; then
      say "· $id — no push history yet (cc-cloud poll writes it); waiting for a quiet window"
      ledger "$id" waiting '{"why":"no sidecar history"}'; return 0
    fi
    quiet_for=$(( $(now) - seen_since )); [ "$quiet_for" -lt 0 ] && quiet_for=0
    if [ "$quiet_for" -lt "$QUIET_S" ]; then
      say "· $id — pushed ${quiet_for}s ago; needs ${QUIET_S}s quiet before it counts as finished"
      ledger "$id" waiting "$(jq -cn --arg q "$quiet_for" '{quiet_for_s:($q|tonumber)}')"; return 0
    fi
  fi

  if [ "$DRY" = 1 ]; then
    say "→ $id — RETURN-READY (worker=$ws, quiet, branch $branch). Dry run: nothing landed."
    ledger "$id" dry-run "$(jq -cn --arg b "$branch" '{branch:$b}')"; return 0
  fi

  # 3b. A REFUSAL ALREADY EARNED ON THIS EXACT SHA IS NOT RE-EARNED EVERY 300 s.
  #
  # The lander's refusals are FINDINGS ABOUT THE TREE, and desk-land says so in its own words —
  # "NOT retrying blindly … 9 and 75 are statements about the MACHINE, not findings about the tree:
  # those two ARE the retryable ones". Everything else (2 dirty · 3 escalation-PARK · 5 rebase-
  # conflict · 6 gate-red · 7 push non-ff · 8 verify-fail) is a fact about a branch that has not
  # moved, so re-running it produces the identical verdict — and this sweep ran it again anyway on
  # the next 300 s tick, forever.
  #
  # Measured 2026-08-25 on the live ledger: 980 land-refused rows over 45 distinct sessions —
  # rc 70 ×741, rc 65 ×236 — with 93 attempts against ONE session, and 19 of the 45 branches no
  # longer on origin at all. Each attempt re-fetched, re-authored, re-rebased and left a rebase in
  # progress; the recorded rerere preimages are conflicts nobody ever resolved. The verdicts were
  # right every single time. The waste was asking again.
  #
  # THE ARTIFACT ALREADY CARRIED THE ANSWER. The refusal file this code writes below has recorded
  # `seen_sha=` since it was introduced — the branch head the verdict was earned against — and
  # nothing ever read it back. That is this repo's own recurring shape (detection ships, actuation
  # waits), and the fix is the read, not a new store.
  #
  # WHY THIS CANNOT LATCH SHUT, which is the failure mode a skip like this must not have:
  #   * the key is the BRANCH HEAD. The moment the VM pushes again, `seen_sha` differs and the next
  #     pass lands normally — the natural falsifier, and it needs no expiry, no TTL and no sweeper.
  #   * a land-CUT is not a refusal and files no artifact (see the bound/SIGTERM arm below), so a
  #     killed land is still resumed on the next tick exactly as before.
  #   * CC_RETURN_RETRY_REFUSED=1 forces one full re-attempt, for the case this key cannot see: a
  #     rebase conflict is a function of the branch AND of trunk, so a human or a wave that has
  #     resolved the conflict re-runs with it set. Keying on trunk instead would re-open the loop,
  #     because trunk moves many times a day and every move would re-ask all 45.
  if [ "$state" != LANDED ] && [ "${CC_RETURN_RETRY_REFUSED:-0}" != 1 ] && [ -n "$seen_sha" ]; then
    local prior_sha prior_rc
    prior_sha="$(sed -n 's/^seen_sha=//p' "$STATE/$id.land-refused" 2>/dev/null | head -1)"
    prior_rc="$(sed -n 's/^rc=//p' "$STATE/$id.land-refused" 2>/dev/null | head -1)"
    if [ -n "$prior_sha" ] && [ "$prior_sha" = "$seen_sha" ]; then
      say "· $id — already REFUSED (exit ${prior_rc:-?}) on this exact branch head; not re-asking until it moves. Artifact: $STATE/$id.land-refused · force with CC_RETURN_RETRY_REFUSED=1"
      ledger "$id" land-refused-cached "$(jq -cn --arg b "$branch" --arg rc "${prior_rc:-}" --arg s "$seen_sha" \
        '{branch:$b, prior_rc:$rc, seen_sha:$s, note:"verdict already earned on this head — skipped, not re-run"}')"
      return 0
    fi
  fi

  # 4. LAND. Delegated whole — the lock, the identity re-author, the gate and the content-verify all
  # live in the sanctioned lander and re-implementing any of them here would be a second, weaker
  # envelope.
  local land_out land_rc=0
  if [ "$state" != LANDED ]; then
    say "→ $id — landing $branch via $(basename "$RECONCILE_BIN")"
    land_out="$(CONFIRM=1 "$RECONCILE_BIN" --land "$branch" 2>&1)"; land_rc=$?
    printf '%s\n' "$land_out" | sed 's/^/    /'

    # 🚨 A LAND THAT WAS KILLED IS A NON-VERDICT, NOT A REFUSAL — measured 2026-08-11 on the second
    # live round trip, and it is this repo's own lesson met from the inside: a bound smaller than
    # what it bounds can only ever CONVICT (memory: exoneration-bound-must-fit-what-it-bounds).
    # The sweep's timeout cut a perfectly healthy land at 240 s; ship-land said so in its own words
    # — `verdict=killed signal=SIGTERM … it did not fail a gate and nothing was proven about the
    # tree` — and this code filed a `land-refused` artifact, woke the originator with "LAND REFUSED"
    # and pointed W3 at a routing job that does not exist. Nothing was wrong with the branch.
    # 124/137/143 are the three ways a bound reaches a process (timeout's own code, SIGKILL, SIGTERM)
    # and ship-land's killed token corroborates from the other side; either is enough to abstain.
    case "$land_rc" in
      124|137|143) land_rc=-1 ;;
    esac
    case "$land_out" in *"verdict=killed"*) land_rc=-1 ;; esac
    if [ "$land_rc" -eq -1 ]; then
      say "? $id — the land was CUT by a bound, not refused: nothing was proven about the branch, and no artifact is filed. The next pass resumes it."
      ledger "$id" land-cut "$(jq -cn --arg b "$branch" '{branch:$b, note:"killed from outside (bound/SIGTERM) — a non-verdict, never a gate refusal"}')"
      return 0
    fi

    # 🚨 NOTHING TO LAND IS NOT A REFUSAL, AND IT IS NOT A RETURN (CLOUD_OBSERVABILITY.md §16).
    # 66 is the lander saying the branch carries no content against trunk: the VM pushed its branch
    # as §4.1's absence contract requires — which is what makes it visible here at all instead of
    # reading C1 NOT-STARTED — and then committed no work to it.
    #
    # This arm exists because the contract MOVES those sessions across this script's own boundary.
    # An un-pushed VM is NOT-STARTED and returns at step 1 with "nothing to return"; a boot-pinged
    # one is ALIVE/STALLED and arrives HERE, at the land. Without this arm it would take the
    # refusal path: an artifact latched to the branch head, a LAND REFUSED wake to the originator,
    # and custody left open — all three about a branch with nothing wrong with it. Falling through
    # to the success path would be worse: content-verify over a path set nobody can derive, then
    # `done_unsettled` cycling every 300 s.
    #
    # No artifact and no wake, so this stays exactly as quiet as the NOT-STARTED case it replaces.
    # The row keeps whatever cc-cloud says about it (STALLED once the sidecar has history), which
    # is the honest verdict and a strictly better one than NOT-STARTED: the session DID boot, and
    # `cc-cloud inbox --id <id>` can read what it asked before it stopped.
    if [ "$land_rc" -eq 66 ]; then
      say "· $id — booted and pushed $branch, but its commits carry no content: nothing to return. Read what it was doing with: cc-cloud inbox --id $id"
      ledger "$id" nothing-to-land "$(jq -cn --arg b "$branch" '{branch:$b, note:"branch carries no content against trunk (boot ping only) — a non-verdict, never a gate refusal"}')"
      return 0
    fi
    if [ "$land_rc" -ne 0 ]; then
      # THE W3 SEAM. A refusal is recorded as an artifact with everything the routing loop will
      # need, the originator is woken WITH the failure, and custody stays OPEN — an un-landed result
      # is precisely the state custody exists to keep from reading as done.
      # 🚨 `seen_sha=` IS THE SUBJECT OF THE VERDICT, and without it a refusal cannot be dated
      # against the branch. A land takes minutes; a VM answering a routed refusal pushes in about
      # one. Measured 2026-08-11 on the first W3 round trip: this land fetched at 20:44 (branch at
      # bc46a12), the VM's fix landed on origin at 20:46:17 (e6c3569), and the gate reported the
      # OLD tree's lint at 20:51:21. The refusal is true about a tree that no longer exists, and
      # W3's router would have spent a cycle telling the VM to fix what it had already fixed.
      # Recording which push the gate actually judged makes supersession decidable in one
      # comparison, and it costs a variable that is already in scope.
      { printf 'id=%s\nbranch=%s\nrc=%s\nat=%s\nseen_sha=%s\n--\n' "$id" "$branch" "$land_rc" "$(now)" "$seen_sha"
        printf '%s\n' "$land_out"; } >"$STATE/$id.land-refused" 2>/dev/null
      say "✗ $id — the land REFUSED (exit $land_rc). Recorded at $STATE/$id.land-refused; custody stays OPEN."
      wake "$nb" "HANDOFF-PING cloud/$id: LAND REFUSED (exit $land_rc) on $branch — the work is pushed but NOT on trunk. Refusal artifact: $STATE/$id.land-refused · session: $url"
      ledger "$id" land-refused "$(jq -cn --arg b "$branch" --arg rc "$land_rc" --arg w "$WAKE_DETAIL" \
        '{branch:$b, land_rc:($rc|tonumber), wake:$w}')"
      return 0
    fi
  fi

  # 5. FILL THE PATH SET from the VM's own commits, now that the lander has fetched the branch —
  # without it `landed()` can never assert anything and the result reads ELIGIBLE forever
  # (backlog a435e3987fbf).
  "$CLOUD_BIN" fill-paths --id "$id" 2>&1 | sed 's/^/    /'
  paths="$(sed -n 's/^paths=//p' "$STATE/$id.decl" 2>/dev/null | head -1)"

  # 6. VERIFY BY CONTENT, never by sha — the land RE-AUTHORS, so the sha the VM pushed is never the
  # sha that lands, and a checker written against it reads "not landed" on a perfect land.
  local landed_ok=1 missing="" p rest
  if [ -n "$paths" ] && [ -n "$repo" ] && [ -d "$repo" ]; then
    landed_ok=0; rest="$paths"
    while [ -n "$rest" ]; do
      case "$rest" in *,*) p="${rest%%,*}"; rest="${rest#*,}" ;; *) p="$rest"; rest="" ;; esac
      [ -n "$p" ] || continue
      if [ -z "$("$GIT_BIN" -C "$repo" ls-tree "$trunk" -- "$p" 2>/dev/null)" ]; then
        landed_ok=1; missing="$missing $p"
      fi
    done
  fi
  if [ "$landed_ok" -eq 0 ]; then say "✓ $id — content-verified on $trunk: $paths"
  else say "✗ $id — NOT content-verified on $trunk (missing:${missing:- everything — no path set})"; fi

  # 7. THE GOAL, judged from this side.
  local grc=0; goal_verdict "$repo" "$probe" "$landed_ok" || grc=$?
  local gword; case "$grc" in 0) gword=MET ;; 1) gword=NOT-MET ;; *) gword=UNJUDGED ;; esac
  say "  goal: $gword — ${goal:-<default: landed by content>} ($GOAL_DETAIL)"

  # 8. SETTLE THE ITEM — the laptop's job; the VM cannot reach the backlog store at all.
  # Only a real backlog id is treated as one: `item` is free text by contract, and a 12-hex id is
  # the store's own shape, so a title never gets passed to `done` as if it were a key.
  # `done_unsettled` is a SEPARATE fact from done_note's prose, because the latch below branches on
  # it — and a latch that greps English is the same defect one layer up.
  #
  # 🚨 THERE ARE TWO TERMINAL DISPOSITIONS, AND ONLY ONE OF THEM USED TO EXIST HERE. `done` is the
  # right one for work the VM finished. The other is a row the VM CANNOT finish because the next
  # step is the operator's — a key, a `launchctl` read, a GUI action. The dispatch brief tells the
  # worker to park those with `cc-backlog block <id> --needs "…"`, and that verb cannot reach the
  # store from a cloud VM: it answers `unknown id`, returns 3 and writes nothing. So the park was
  # inert exactly where it was needed, the row stayed `open`, and the next pass re-dispatched it —
  # backlog f85fce7c26f5, ten dispatches, ten branches, one unchanged operator-gated verdict
  # (docs/research/cloud-land-arm-step-2026-08-25.md §6.6).
  #
  # The VM's one channel is its branch, which is the same conclusion CLOUD_OBSERVABILITY.md §14
  # reached for the close. So a park is a landed file — `docs/parks/<id>.md`, written by
  # `scripts/cloud-park.sh` — and this step reads it and calls `block` instead of `done`. Two
  # properties make that safe to act on unattended:
  #
  #   · it is read from the TRUNK REF, never from the branch or a working tree, so it has passed the
  #     same content-verify (step 6) as everything else this step acts on. A park that did not land
  #     does not park.
  #   · it is honoured only when its last entry's `branch:` is THIS dispatch's branch. The file
  #     outlives the park — once the operator unblocks the row and it is re-dispatched, the file is
  #     still on trunk — and a reader keyed on existence alone would re-block the row on the next
  #     land, forever. The branch test makes a stale entry inert without needing anyone to delete it.
  #
  # THIS IS NO LONGER THE PARK'S ONLY READER, and the reason is a defect in the routing rather than
  # in anything above: this step runs only under `scripts/autonomy-sweep.sh` on the operator's box,
  # which for `f85fce7c26f5` IS the arm the row reports as dark — so its park landed and the wave
  # re-fired it 7 h 11 m later. `bin/cc-eligible` now reads the same file at `claim --venue cloud`
  # and refuses the cloud venue while a landed park is newer than the row's last block/unblock. That
  # is an INTERLOCK, not a second writer: this step is still what makes the transition, and the desk
  # is still the ledger's only writer. Format changes move both readers together —
  # `scripts/cloud-park.sh`'s header owns that contract.
  local done_note="no backlog item recorded" done_unsettled=0 done_err=""
  case "$item" in
    [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f])
      if [ "$landed_ok" -eq 0 ] && [ -n "$BACKLOG_BIN" ]; then
        # 🚨 CAPTURE THE REFUSAL. This call used to be `>/dev/null 2>&1`, and on 2026-08-12 it
        # returned non-zero for item `0b4d4e8a1889` — over a land that WAS content-verified on trunk
        # with custody discharged. The one fact needed to tell policy from contention was destroyed
        # at the call site, so the incident could only be diagnosed afterwards by re-running the
        # verb against a byte copy of the store (rc 0 in 1.96 s ⇒ contention, not policy). A caller
        # must never mute its callee's non-verdict.
        local _derr; _derr="$(mktemp -t ccret-done.XXXXXX 2>/dev/null || printf '/tmp/ccret-done.%s' "$$")"

        # 8a. READ THE PARK, if this dispatch wrote one. `_park`: 0 none · 1 honoured · 2 malformed.
        local _pf="docs/parks/$item.md" _pdoc="" _pbranch="" _pneeds="" _park=0
        if [ -n "$repo" ] && [ -d "$repo" ] \
           && [ -n "$("$GIT_BIN" -C "$repo" ls-tree "$trunk" -- "$_pf" 2>/dev/null)" ]; then
          _pdoc="$("$GIT_BIN" -C "$repo" show "$trunk:$_pf" 2>/dev/null)"
          # the LAST entry of an append-only log — `tail -1`, on both fields, so one dispatch's park
          # never reads through to another's
          _pbranch="$(printf '%s\n' "$_pdoc" | sed -n 's/^branch: *//p' | tail -1)"
          _pneeds="$(printf '%s\n' "$_pdoc" | sed -n 's/^needs: *//p' | tail -1)"
          if [ "$_pbranch" != "$branch" ]; then
            say "  park: $_pf's last entry names ${_pbranch:-<no branch:>}, not $branch — an earlier dispatch's park, not this one's; ignored"
          elif [ -z "$_pneeds" ]; then
            _park=2
          else
            _park=1
          fi
        fi

        if [ "$_park" -eq 2 ]; then
          # A park naming this branch with no step in it must NOT fall through to `done`: the worker
          # said "this is not finished" and the only readable half of that statement is the half
          # that says so. Closing it here would be the loudest possible false completion.
          done_note="REFUSED to settle $item — $_pf names this branch but carries no 'needs:' line, so the park cannot be executed and the row is not done either"
          done_err="malformed park artifact: $_pf"
          done_unsettled=1
        elif [ "$_park" -eq 1 ]; then
          if "$BACKLOG_BIN" block "$item" --needs "$_pneeds" >"$_derr" 2>&1; then
            done_note="PARKED $item on the operator: $_pneeds"
          else
            done_err="$(tr '\n\t' '  ' <"$_derr" 2>/dev/null | tr -cd '\40-\176' | tail -c 300)"
            done_note="could NOT park $item (rc≠0: ${done_err:-no output})"
            done_unsettled=1
          fi
        elif "$BACKLOG_BIN" "done" "$item" --evidence "cloud $id → $trunk: $paths" >"$_derr" 2>&1; then
          done_note="marked $item done"
        else
          done_err="$(tr '\n\t' '  ' <"$_derr" 2>/dev/null | tr -cd '\40-\176' | tail -c 300)"
          done_note="could NOT mark $item done (rc≠0: ${done_err:-no output})"
          done_unsettled=1
        fi
        rm -f "$_derr" 2>/dev/null || true
      else
        done_note="left $item open — the content is not verified on trunk"
      fi ;;
  esac
  say "  backlog: $done_note"

  # 9. DISCHARGE CUSTODY — and only on a verified land. Custody's whole job is to make a close
  # impossible while dispatched work is unreturned; discharging it over an unverified result would
  # delete the one mechanism that would have caught this.
  local cust_note="no custody marker recorded"
  if [ -n "$custody" ] && [ -n "$CUSTODY_BIN" ]; then
    if [ "$landed_ok" -eq 0 ]; then
      if "$CUSTODY_BIN" return "$custody" >/dev/null 2>&1; then cust_note="discharged $custody"
      else cust_note="could NOT discharge $custody"; fi
    else
      cust_note="left $custody OPEN — the result is not verified on trunk"
    fi
  fi
  say "  custody: $cust_note"

  # 10. WAKE THE ORIGINATOR. This is the step the whole script exists for.
  #
  # 🚨 THE WAKE LATCHES SEPARATELY FROM THE RETURN, and it has to (2026-08-12). Two invariants meet
  # here and a single latch cannot serve both: the originator must be woken exactly ONCE ever (an
  # alarm that re-fires every sweep carries no bits), while the backlog close must stay RETRYABLE
  # after a transient refusal. Before the close joined the latch condition below, one marker
  # happened to serve both — and that coincidence is what made a failed close permanent. Splitting
  # them is the fix for both: `.woken` records that the originator has been told, `.returned` records
  # that everything terminal is finished, and a close retry now costs no second ping.
  local verdict_word; [ "$landed_ok" -eq 0 ] && verdict_word="LANDED+VERIFIED" || verdict_word="LANDED-UNVERIFIED"
  local wrc2=0
  if [ -f "$STATE/$id.woken" ]; then
    wrc2=0; say "  wake: already sent for $id — not re-pinging while the close retries"
  else
    wake "$nb" "HANDOFF-PING cloud/$id: $verdict_word on $trunk — paths: ${paths:-none} · goal: $gword · $done_note · $cust_note · session: $url" || wrc2=$?
    case "$wrc2" in
      0) say "  wake: sent → $nb ($WAKE_DETAIL)"; printf 'woken_at=%s\n' "$(now)" >"$STATE/$id.woken" 2>/dev/null ;;
      3) say "  wake: $WAKE_DETAIL"; printf 'woken_at=%s\nnote=no-target\n' "$(now)" >"$STATE/$id.woken" 2>/dev/null ;;
      *) say "  wake: NOT DELIVERED → $nb ($WAKE_DETAIL)" ;;
    esac
  fi

  # LATCH only what actually completed. A pass whose wake failed is left unlatched on purpose, so
  # the next sweep tries again rather than leaving the originator permanently uninformed about work
  # that is already on trunk.
  #
  # 🚨 `done_unsettled` IS PART OF THE LATCH CONDITION (2026-08-12). It was not, and that is how a
  # perfect round trip became permanently unfinished: `session_01CCZcjYGJ…` landed, content-verified,
  # discharged custody, FAILED to close its backlog row, and latched anyway — after which handle()
  # short-circuits at `already returned` on every future sweep, forever. The failure was unretryable
  # BY CONSTRUCTION and recorded in one file nobody reads. A latch must cover every step it is
  # closing out, or the uncovered step is silently one-shot.
  if [ "$landed_ok" -eq 0 ] && [ "$done_unsettled" -eq 0 ] && { [ "$wrc2" -eq 0 ] || [ "$wrc2" -eq 3 ]; }; then
    { printf 'outcome=returned\nat=%s\npaths=%s\ngoal=%s\n' "$(now)" "$paths" "$gword"; } >"$STATE/$id.returned" 2>/dev/null

    # 🚨 RELEASE THE OFF-BOX SLOT — the missing half of the whole pipeline (2026-08-12).
    # `cc-cloud retire` shipped as a verb with ZERO callers: 0 `.retired` markers across 38
    # declarations. `cc-cloud is-offbox` is two file-existence tests with no completion notion, so
    # it answers OFFBOX-LIVE forever, `cc-backlog reap` never reopens the claim, and the dispatcher's
    # ceiling cannot self-heal. Measured consequence: six finished cloud sessions held all six
    # admission slots and the dispatcher fired NOTHING — cloud or local — for 1 h 34 m, with no
    # timeout that would ever end it (`UNRESOLVED_MAX_S` bounds an ABSTAINING oracle; this one
    # answers, confidently and wrongly).
    #
    # Retire is the honest signal here and only here: this branch IS the terminal state — landed,
    # content-verified, row closed, originator informed. Retiring earlier would tell reap that a
    # still-working VM is dead and invite a duplicate peer onto live work, which is the exact
    # false-dead hazard cc-dispatch refuses to reintroduce. Fail-open: a retire that does not stick
    # leaves today's behaviour, never a worse one.
    if [ -n "$CLOUD_BIN" ]; then
      if "$CLOUD_BIN" retire --id "$id" >/dev/null 2>&1; then say "  slot: retired $id — the off-box claim can now be reaped"
      else say "  slot: could NOT retire $id — its claim will keep holding an admission slot"; fi
    fi
  elif [ "$landed_ok" -eq 0 ] && [ "$done_unsettled" -ne 0 ]; then
    # THE RETRY MUST BE BOUNDED, OR THE FIX RE-CREATES THE WEDGE IT REMOVES. Making the latch
    # conditional on the close (above) is right for a TRANSIENT refusal — 2026-08-12's was
    # contention and would have succeeded on the next pass. But a PERMANENT one (a malformed id, a
    # row someone else already closed) would then never latch, never retire, and hold its admission
    # slot exactly as before — the same outage reached by a different road.
    #
    # So: count the attempts in a SIDECAR, never inside `.returned` — that file is written only on
    # the success path, so a counter kept there would be reset by the very event it bounds and the
    # loop would run forever reading "attempt 1" (MEMORY: counter-resets-at-the-boundary-the-runaway
    # -crosses, the same shape W3's refusal cycle counter already paid for).
    #
    # At the bound the work is LANDED and VERIFIED, so the honest disposition is to release the slot
    # and leave the ROW open: an open row is re-dispatchable and visible, a held slot is neither.
    local _cf="$STATE/$id.close-attempts" _n=0
    [ -f "$_cf" ] && _n="$(tr -cd '0-9' <"$_cf" 2>/dev/null || echo 0)"
    _n=$(( ${_n:-0} + 1 )); printf '%s\n' "$_n" >"$_cf" 2>/dev/null || true
    if [ "$_n" -ge "${CC_RETURN_CLOSE_MAX:-3}" ] && [ -n "$CLOUD_BIN" ]; then
      say "  slot: close has failed $_n× (${done_err:-no output}) — retiring $id anyway; the work is on trunk and the ROW stays open, which is re-dispatchable where a held slot is not"
      "$CLOUD_BIN" retire --id "$id" >/dev/null 2>&1 || true
      { printf 'outcome=returned-close-failed\nat=%s\npaths=%s\ngoal=%s\nattempts=%s\nerr=%s\n' \
          "$(now)" "$paths" "$gword" "$_n" "${done_err:-}"; } >"$STATE/$id.returned" 2>/dev/null
    else
      say "  slot: close failed (attempt $_n of ${CC_RETURN_CLOSE_MAX:-3}) — NOT latching, the next sweep retries"
    fi
  fi
  ledger "$id" returned "$(jq -cn --arg b "$branch" --arg p "$paths" --arg g "$gword" \
    --arg l "$landed_ok" --arg w "$WAKE_DETAIL" --arg d "$done_note" --arg c "$cust_note" \
    --arg de "$done_err" \
    '{branch:$b, paths:$p, goal:$g, content_verified:($l=="0"), wake:$w, backlog:$d, custody:$c}
     + (if $de == "" then {} else {backlog_err:$de} end)')"
  return 0
}

# ── the pass ─────────────────────────────────────────────────────────────────────────────────────
# 🚨 THE ADMISSION READ IS DISK-ONLY, AND IT COMES FIRST. `cc-cloud list` without `--state` performs
# no probe at all; `poll` and `--state` each cost a bounded `git ls-remote` PER DECLARATION (20 s
# apiece). The first cut polled before deciding whether it had anything to do, so a box with 40
# historical declarations and ZERO managed ones spent minutes of network per pass — and inside
# tests/autonomy-sweep.bats, which runs the real sweep once per test, that turned a 2-minute suite
# into an unfinishable one. Deciding on disk that there is nothing to do costs one directory read.
lock_acquire || { warn "another pass holds the lock — skipping (this is single-flight by design)"; exit 4; }
printf '%s\n' "$(now)" >"$LOCK/at" 2>/dev/null
trap 'lock_release' EXIT INT TERM

INVENTORY="$("$CLOUD_BIN" list --json 2>/dev/null)"
if [ -z "$INVENTORY" ]; then
  say "(no cloud sessions declared)"
  exit 0
fi

if [ "$MODE" = one ]; then
  WANT="$(printf '%s\n' "$INVENTORY" | jq -c --arg i "$ONE" 'select(.id == $i)' 2>/dev/null | head -1)"
  [ -n "$WANT" ] || { warn "no declaration for '$ONE'"; exit 2; }
else
  # The MANAGED population — see "THE SWEEP'S POPULATION IS WHAT THE SWEEP ARMED" above.
  WANT="$(printf '%s\n' "$INVENTORY" | jq -c 'select(.retired != true)
    | select((.notify_back // "") != "" or (.custody // "") != "")' 2>/dev/null)"
  if [ -z "$WANT" ]; then
    say "(no MANAGED cloud declarations — a fire opts in by recording notify_back/custody at declare time)"
    exit 0
  fi

  # ── THE WORKING SET: still-pending, NEWEST FIRST, cursor-rotated, then bounded ──────────────────
  # Every step here is a DISK read. That placement is the whole point: the admission decision above
  # already costs one directory walk, and deciding WHICH handful to probe has to happen on the same
  # side of the network boundary, or the bound cannot bound anything.
  #
  # 1. DROP WHAT IS ALREADY LATCHED. `handle()`'s first act is to short-circuit on `<id>.returned` —
  #    but it does that AFTER this script has already paid a poll and a state probe for that id.
  #    Filtering here is the same verdict, taken one file-existence check earlier, on the side of the
  #    boundary where it is free.
  # 2. NEWEST FIRST. Staleness compounds rather than merely accumulating: the oldest ELIGIBLE branch
  #    (14 d) hit a rebase conflict on its dry run while recent ones were clean, so an oldest-first
  #    order spends the whole per-tick budget on the branches least likely to land and never reaches
  #    the ones that would (docs/plans/DRAIN_CIRCUIT_2026-09-01.md §2 "Known-clean vs known-conflicting").
  # 3. THE CURSOR, WHICH IS WHY NEWEST-FIRST DOES NOT STARVE THE TAIL. Newest-first plus a fixed
  #    limit would re-examine the same head every tick forever and the older 90% would never be
  #    looked at again — a cap that reads as coverage, which is precisely the failure this whole
  #    change exists to end. The cursor is an offset into the ordered working set, advanced by the
  #    size of each pass and wrapped at the end, so the tail is reached on a later tick rather than
  #    never. It is deliberately an OFFSET and not a remembered id: the set churns underneath it
  #    (new fires prepend, returns drop out), and an offset degrades to "start somewhere else next
  #    time", which is self-healing, where a dangling id would need its own miss-vs-absence rule.
  WANT="$(printf '%s\n' "$WANT" | while IFS= read -r _r; do
      [ -n "$_r" ] || continue
      _i="$(printf '%s' "$_r" | jq -r '.id')"
      [ -f "$STATE/$_i.returned" ] && continue
      printf '%s\n' "$_r"
    done)"
  WANT="$(printf '%s\n' "$WANT" | jq -sc 'map(select(. != null)) | sort_by(.declared_at // 0) | reverse | .[]' 2>/dev/null)"
  if [ -z "$WANT" ]; then
    say "(every MANAGED cloud declaration has already been returned — nothing pending)"
    exit 0
  fi
  TOTAL="$(printf '%s\n' "$WANT" | grep -c . || true)"

  CURSOR_F="$STATE/.return.cursor"
  CURSOR="$(cat "$CURSOR_F" 2>/dev/null | head -1)"; case "$CURSOR" in ''|*[!0-9]*) CURSOR=0 ;; esac
  [ "$CURSOR" -lt "$TOTAL" ] || CURSOR=0

  if [ "$LIMIT" -gt 0 ] && [ "$TOTAL" -gt "$LIMIT" ]; then
    # The offset window, taken with awk rather than `tail -n +K | head -n N`. A window that runs off
    # the end is NOT wrapped around to the head in the same pass: a short final slice simply resets
    # the cursor, so no id is examined twice in one tick and the next tick starts clean at the top.
    #
    # 🚨 awk BECAUSE `head` CLOSES THE PIPE AND `printf` IS STILL WRITING. `head -n 25` exits the
    # moment it has its 25 lines, so the upstream `printf` of all 468 rows takes SIGPIPE and prints
    # `printf: write error: Broken pipe` to stderr — observed on the first live run of this pass.
    # Here it was only noise, because the substitution had already captured what it needed and this
    # script does not run under `set -e`. It is still fixed rather than tolerated: under `pipefail`
    # a truncating consumer makes the pipeline's rc the WRITER's failure, which is exactly how a
    # producer that succeeded gets read as a producer that failed (memory:
    # grep-q-under-pipefail-inverts-the-verdict). awk consumes the whole stream, so nothing closes
    # early and there is no signal to misread.
    WANT="$(printf '%s\n' "$WANT" | awk -v s="$((CURSOR + 1))" -v n="$LIMIT" 'NR >= s && NR < s + n')"
    TAKEN="$(printf '%s\n' "$WANT" | grep -c . || true)"
    NEXT=$((CURSOR + TAKEN)); [ "$NEXT" -lt "$TOTAL" ] || NEXT=0
    DEFERRED=$((TOTAL - TAKEN))
  else
    TAKEN="$TOTAL"; NEXT=0; DEFERRED=0
  fi
  printf '%s\n' "$NEXT" >"$CURSOR_F" 2>/dev/null || true

  # 🚨 NEVER A SILENT CAP. A bounded pass that says nothing about what it skipped reads exactly like
  # a pass that covered everything, and a reader of this ledger would conclude the lane was drained
  # when it had examined 25 of 466. The deferral is therefore a first-class ledger row with the
  # cursor position in it, so "we are working through a backlog" and "there is no backlog" can never
  # be confused for one another (memory: zero-claim-must-name-its-excluded-strata).
  say "cloud-return: $TAKEN of $TOTAL pending managed session(s) this pass (cursor $CURSOR → $NEXT, $DEFERRED deferred, limit ${LIMIT})"
  ledger "-" pass-scope "$(jq -cn --argjson t "$TOTAL" --argjson k "$TAKEN" --argjson d "$DEFERRED" \
    --argjson c "$CURSOR" --argjson n "$NEXT" --argjson l "$LIMIT" \
    '{pending_total:$t, taken:$k, deferred:$d, cursor_from:$c, cursor_to:$n, limit:$l}')"
fi

# Only now — with a non-empty, BOUNDED population — does the network get touched. `poll` is the ONLY
# writer of the push-history sidecar and step 3 cannot decide anything without it; calling the
# owner's mutator is the point, since a local copy of "has this sha moved" would be a second opinion
# about the one fact this rail turns on.
#
# 🚨 BOTH PROBING CALLS ARE SCOPED TO THE WORKING SET, and scoping them is what makes the bound real.
# Unscoped, each of these costs one `ls-remote` PER DECLARATION IN THE STORE — 583 today, +20-80/day
# — so `--limit` would have bounded only the cheap part while the fixed cost went on growing without
# limit underneath it. Timed live 2026-09-01: `list --json --state` 210 s over 583 rows, `poll` a
# second pass of the same shape, ~675 s of a 900 s budget consumed before the first land. `--only`
# makes both O(the working set), which is bounded by construction.
SCOPE="$(printf '%s\n' "$WANT" | jq -r '.id' 2>/dev/null | tr '\n' ',')"
"$CLOUD_BIN" poll --only "$SCOPE" >/dev/null 2>&1 || warn "cc-cloud poll did not complete; quiet windows may read as unmeasured"

ROWS="$("$CLOUD_BIN" list --json --state --only "$SCOPE" 2>/dev/null)"
[ -n "$ROWS" ] || { warn "the state read returned nothing after a non-empty inventory — abstaining"; exit 0; }

# Re-select the same ids from the STATE-bearing rows: the admission decision was made on disk, and
# the verdicts have to come from the arbiter that probes.
IDS="$(printf '%s\n' "$WANT" | jq -r '.id')"
MANAGED="$(printf '%s\n' "$ROWS" | jq -c --argjson want "$(printf '%s\n' "$IDS" | jq -R . | jq -sc .)" \
  'select(.id as $i | $want | index($i))' 2>/dev/null)"
if [ "$MODE" = one ]; then
  ROW="$(printf '%s\n' "$MANAGED" | head -1)"
  [ -n "$ROW" ] || { warn "no state row for '$ONE'"; exit 2; }
  handle "$ROW"
  exit 0
fi
[ -n "$MANAGED" ] || { say "(no MANAGED cloud declarations)"; exit 0; }

N=0
while IFS= read -r ROW; do
  [ -n "$ROW" ] || continue
  N=$((N + 1))
  handle "$ROW"
done <<EOF
$MANAGED
EOF
say "cloud-return: $N managed session(s) examined."
exit 0
