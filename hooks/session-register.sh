#!/bin/bash
# session-register.sh — SessionStart hook for the cross-session comms feature.
#
# Records this iTerm2 pane in an account-agnostic registry so ANY session (any
# account / config-dir) can resolve a friendly name → iTerm2 pane UUID and ping
# it with `cc-notify` (the it2 keystroke transport). Paired with
# session-deregister.sh (SessionEnd) and the `cc-sessions` lister.
#
# Registry dir: $HOME/.claude/cc-registry/<paneUUID>.json  — FIXED $HOME/.claude,
#   NOT $CLAUDE_CONFIG_DIR: the whole point is CROSS-account addressing (a next2
#   session must resolve a next session's name), and per-account config dirs are
#   isolated. Deliberately NOT ~/.claude/sessions/ — that dir is Claude Code's
#   OWN per-account <pid>.json session registry plus this repo's <sid>.plan pins
#   (hooks/plan-pin-session.sh); layering a third schema there would be fragile.
#   See docs/plans/TWO_WAY_SESSION_COMMS_PLAN.md.
#
# Entry: {paneUUID, name, cwd, account, pid, startedAt}. Name defaults to
#   <cwd-basename>-<short-uuid>; override with CC_SESSION_NAME.
#
# Fail-safe: never blocks the session (always exit 0). Needs jq + a valid
#   $ITERM_SESSION_ID (an iTerm2 pane). bash 3.2-safe.
set -uo pipefail

input=$(cat 2>/dev/null)

# --- FAIL-OPEN CONTRACT (P8-GO condition 1) ----------------------------------------------------
# This runs on EVERY session start, on every account. A registration spine that can block, delay,
# or kill a startup inverts its own purpose — so ALL work happens inside register(), under a HARD
# timeout, and this hook ALWAYS exits 0 no matter what happens inside. Registration is best-effort
# BY CONSTRUCTION: a missing row degrades the board (one session we cannot see); it must never cost
# a session. Typical cost is <100ms (2 jq + a few ps); the cap only bites if something hangs.
#
# The cap was 3s, calibrated against that <100ms typical cost. Measured 2026-07-29 at loadavg 33 and
# again at 53, register() exceeded it and was kill -9'd — so the machine states that produce the most
# sessions are exactly the ones that silently stop registering them (memory:
# actuator-must-see-the-target-population — an idle-calibrated timeout is an off switch under load).
# The lost row is not cosmetic: cc-notify cannot address the pane, cc-board reads the session as
# absent, and cc-backlog's `claimer_live` answers PROVEN NOT-LIVE for any session-keyed claim it holds
# — a false death. Raised to 20s, which is still a hard cap: it only ever bites work that genuinely
# takes that long, and the alternative outcome in that state is a missing row, which is strictly worse
# than a slow one.
P8_TIMEOUT="${P8_REGISTER_TIMEOUT:-20}"

# claude_ancestor_pid → the durable `claude` process pid above this hook, else $PPID.
# NOT $PPID itself: the hook runs under a /bin/sh shim that exits immediately (the teammate-lifecycle
# $PPID lesson), so $PPID is dead within seconds and useless as a liveness handle.
#
# Called ONCE, into $CPID below, and read by both consumers — the registry row cc-sessions checks with
# `kill -0`, and the worker-keyed backlog claim. Two reasons it must not be called twice: the walk
# costs up to 24 `ps` forks, which at the loadavg 30-50 this machine actually runs at is seconds of
# wall clock inside a session-start hook (measured 2026-07-29: two walks pushed register() past its
# own cap and the registry row was silently lost); and cc-sessions and cc-backlog must agree on WHO
# the worker is, which one derivation guarantees by construction.
claude_ancestor_pid() {
  local walk="$PPID" found="" i=0 c
  while [ -n "$walk" ] && [ "$walk" -gt 1 ] 2>/dev/null && [ "$i" -lt 12 ]; do
    c=$(ps -o comm= -p "$walk" 2>/dev/null); c="${c##*/}"
    case "$c" in claude|claude.exe|claude-*) found="$walk"; break ;; esac
    walk=$(ps -o ppid= -p "$walk" 2>/dev/null | tr -d ' ')
    i=$((i + 1))
  done
  [ -n "$found" ] || found="$PPID"
  printf '%s' "$found"
}

CPID="$(claude_ancestor_pid)"

# pid_is_strict_ancestor <pid> → 0 iff <pid> is an ancestor of $CPID, i.e. strictly ABOVE our own
# claude process. This is the tenancy proof the write gate below needs, and it is a live kernel fact
# rather than an inference: a nested `claude` got the pane id by INHERITING it from the process that
# owns the pane, so the row's owner being our ancestor IS the statement "this row is not ours".
#
# WHY NOT the cheaper "the incumbent pid is live and is a claude" test: that convicts on pid REUSE
# (a stale row whose pid the kernel recycled onto an unrelated claude would refuse a legitimate new
# tenant forever) and on pane REUSE (handoff-fire --recycle relaunches the same pane; any overlap
# between the outgoing and incoming process would refuse the incoming row and leave the pane holding
# a row that is about to become a corpse — the exact failure this gate exists to prevent, re-created
# by the gate). Ancestry has neither hazard: a recycled pid is not our ancestor, and a relaunched
# tenant is never a descendant of the one it replaced.
#
# One `ps` per hop, bounded at 16 (measured production depth is 4-6: hook sh → child claude → the
# tool's shell → parent claude). Called ONLY from the contested path — a row that exists, names a
# live pid, and that pid is not ours — so the overwhelmingly common session start pays zero forks.
pid_is_strict_ancestor() {
  local target="${1:-}" walk i=0
  case "$target" in ''|*[!0-9]*) return 1 ;; esac
  walk=$(ps -o ppid= -p "$CPID" 2>/dev/null | tr -d ' ')
  while [ -n "$walk" ] && [ "$walk" -gt 1 ] 2>/dev/null && [ "$i" -lt 16 ]; do
    [ "$walk" = "$target" ] && return 0
    walk=$(ps -o ppid= -p "$walk" 2>/dev/null | tr -d ' ')
    i=$((i + 1))
  done
  return 1
}

register() {
command -v jq >/dev/null 2>&1 || return 0

# Pane UUID from $ITERM_SESSION_ID (strip the "wNtNpN:" prefix → bare UUID the
# it2 shim addresses). No pane / not a UUID → nothing to register.
pane="${CC_PANE_ID:-${ITERM_SESSION_ID:-}}"; pane="${pane##*:}"
case "$pane" in
  ''|*[!0-9A-Fa-f-]*) return 0 ;;
esac

cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$cwd" ] && cwd="$PWD"

# session_id — THE JOIN KEY (P8). Telemetry is keyed by session_id; the registry was keyed only by
# paneUUID, so the two could not be joined and cc-board had no way to notice a registered session
# that NEVER produced telemetry. That join is the whole spawn-death detector: registry row + no
# telemetry ever = a pane that came up and never rendered (D8 trigger 1), which the telemetry-spined
# board renders as ABSENCE — and absence is silent.
sid=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)

acct=$(basename "${CLAUDE_CONFIG_DIR:-$HOME/.claude}" | sed 's/^\.//')
short="${pane%%-*}"
name="${CC_SESSION_NAME:-$(basename "$cwd")-$short}"

cpid="$CPID"

started=$(( $(date +%s) * 1000 ))
reg_dir="${CC_REGISTRY_DIR:-$HOME/.claude/cc-registry}"
mkdir -p "$reg_dir" 2>/dev/null || return 0

# ── TENANCY GATE (write side) — the mirror of session-deregister.sh's remove-side gate ─────────
# A pane id is not a tenancy, and it is INHERITED: every child process of the pane's session carries
# CC_PANE_ID/ITERM_SESSION_ID, so any nested `claude` that fires a SessionStart — a `claude -p`
# probe, an upgrade-gate check, a script that shells out to the CLI — reached this line holding the
# LIVE pane's id and, until this gate, wrote its OWN pid and session_id over the tenant's row.
#
# Measured 2026-08-08, deployed hook + fixtured CC_REGISTRY_DIR, one `claude -p` fired from inside a
# live session: the row for pane 841 went from (pid 82949, PARENT-SID-0001) to (pid 38739, the
# child's sid) and pid 38739 was dead by the time the probe returned — a DEAD-PID CORPSE on a pane
# whose own claude was alive throughout. The child never even reached the model (it exited on "Not
# logged in"), so the trigger is not cost-gated: firing the CLI at all is enough. Consequence chain:
# cc-sessions hides a dead-pid row from the addressing view, so cc-notify cannot reach the pane,
# cc-board reads it absent, and cc-backlog's `claimer_live` answers PROVEN NOT-LIVE for any claim the
# pane holds — a false death, for up to CC_REG_RETAIN_H until cc-reconcile heals it.
#
# This is the SAME hazard session-deregister.sh:12-32 documents from the removal side (the `claude
# mcp list` phantom, 2026-08-05, docs/research/registry-row-removal-2026-08-05.md). That fix proved
# tenancy before REMOVING; 64b655be additionally `env -u`'d the one known caller. Neither reaches
# this side: `env -u` is a per-callsite denylist that only ever names the probes someone has already
# found, and the write had no gate at all. So prove tenancy here too, on the same asymmetry — a
# refused write leaves the pane addressable under its true tenant, while a wrongly-allowed one
# erases a live pane from the fleet's only cross-account addressing table.
#
# Fail-OPEN on everything unprovable (no row, unreadable row, no pid, pid dead, pid not ours and not
# our ancestor): those all take the write, exactly as before this gate existed.
row="$reg_dir/$pane.json"
if [ -f "$row" ]; then
  inc=$(jq -r '.pid // empty' "$row" 2>/dev/null)
  case "$inc" in ''|*[!0-9]*) inc="" ;; esac
  if [ -n "$inc" ] && [ "$inc" != "$cpid" ] && kill -0 "$inc" 2>/dev/null \
     && pid_is_strict_ancestor "$inc"; then
    # Journalled, because a guard that no-ops silently cannot be told apart from one that is inert
    # (memory: claimed-outcome-vs-checked-outcome). `refused` is a NEW disposition token; cc-digest
    # and cc-discover bucket anything that is not "abstained" as fired, which is what this is — the
    # gate ran and acted.
    reclaim_idl refused "pane $pane held by live ancestor pid $inc — nested session, not the tenant"
    return 0
  fi
fi

# Atomic write (tmp + mv) so a concurrent cc-sessions read never sees a partial file.
tmp="$reg_dir/.$pane.$$.tmp"
if jq -n --arg paneUUID "$pane" --arg name "$name" --arg cwd "$cwd" \
        --arg account "$acct" --arg sessionId "$sid" \
        --argjson pid "$cpid" --argjson startedAt "$started" \
      '{paneUUID:$paneUUID, name:$name, cwd:$cwd, account:$account, pid:$pid,
        startedAt:$startedAt, session_id:(if $sessionId=="" then null else $sessionId end)}' \
      > "$tmp" 2>/dev/null; then
  mv -f "$tmp" "$reg_dir/$pane.json" 2>/dev/null || rm -f "$tmp" 2>/dev/null
else
  rm -f "$tmp" 2>/dev/null
fi
return 0
}

# ── WORKER-KEYED BACKLOG CLAIM (backlog a13fb1d41044) ──────────────────────────────────────────
# cc-dispatch claims a backlog item with `--by <host>-$$` — its OWN pid — and then exits, so within
# seconds the ledger's claim names a dead process. Past cc-backlog's stale gate `claimer_live` is
# therefore false BY CONSTRUCTION for every dispatched item, and the dead-worker sweep degrades to an
# age-only heuristic: a live 91-minute worker gets its item reopened (→ a second peer onto live work),
# a worker that died at minute 5 strands its claim for 85. cc-dispatch cannot fix it at the source —
# the session it is about to spawn has no identity yet.
#
# This is the other side of that seam: the worker re-keys the claim to ITSELF, at SessionStart, from
# inside the worktree that identifies the item. The bug was never the `<host>-<pid>` FORM, only WHOSE
# pid — so this reuses `claimer_live`'s existing `kill -0` path verbatim and adds no new resolution
# surface. `cc-backlog reclaim` carries the guards (claimed-only, idempotent, refuses to steal a
# provably-live claim) and prints a `verdict=` token; every outcome is journalled to the IDL, because
# a silent no-op cannot be told apart from an inert mechanism.
#
# WHY IT LIVES IN THIS HOOK rather than its own: SessionStart hooks are registered in settings.json,
# which is C10 operator-only — a new hook file would ship STAGED and INERT until someone ran an
# activation script (the standing pending-activation backlog is the evidence that "staged" means
# "never"). This hook is already registered on every account, and it already derives both inputs the
# re-key needs (the session's cwd and the durable claude pid). It runs DETACHED, so registering the
# pane — the primary duty — is never starved by it, and neither is the session start.
#
# Deliberately at process START, not at model "engagement": the pid is authoritative from the instant
# the process exists, and a pane that comes up but never engages (the cold-worktree auto-submit race)
# must still be reapable — its live pid is now bounded by cc-backlog's LIVE_CLAIM_MAX_S ceiling.
RECLAIM_IDL="${SESSION_REGISTER_IDL:-$HOME/.claude/autonomy/idl.jsonl}"

# Derived HERE rather than beside the reclaim invocation at the foot of the file: register() also
# journals now (the tenancy gate), and it runs BEFORE that point — a later assignment would have left
# every gate record stamped with the `?` sid fallback, i.e. unattributable to the session that was
# refused, which is the one thing the record is for.
RECLAIM_SID=$(printf '%s' "$input" | jq -r '.session_id // "?"' 2>/dev/null || echo '?')

reclaim_idl() { # $1=disposition $2=reason [$3=item id] [$4=basis]
  mkdir -p "$(dirname "$RECLAIM_IDL")" 2>/dev/null || true
  local ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo '?')"
  # jq-encode every field (house rule): one malformed line aborts cc-audit's `jq -rs` slurp.
  jq -cn --arg ts "$ts" --arg sid "${RECLAIM_SID:-?}" --arg disp "$1" --arg reason "$2" \
         --arg item "${3:-}" --arg basis "${4:-}" \
    '{ts:$ts,hook:"session-register",sid:$sid,disposition:$disp,reason:$reason}
     + (if $item  != "" then {item:$item}   else {} end)
     + (if $basis != "" then {basis:$basis} else {} end)' \
    >> "$RECLAIM_IDL" 2>/dev/null || true
}

# _resolve_backlog_bin → path to cc-backlog, or "" (rc 0). Then the live bin dir, then PATH — a
# SessionStart hook's PATH is the user's, but never assume ~/.claude/bin is on it.
#
# Seam: SESSION_REGISTER_BACKLOG_BIN — UNSET ⇒ resolve one. SET, including set to EMPTY ⇒ honored
# verbatim, so `SESSION_REGISTER_BACKLOG_BIN=` genuinely turns the re-key OFF. `${VAR:-}` cannot tell
# unset from set-empty, and a seam that cannot turn a thing off is not a seam (the house pattern —
# cc-backlog's CC_BACKLOG_LSOF_BIN). A set-but-broken path resolves to itself and is caught by the
# caller's `-x` gate, which abstains NAMING the cause rather than reporting an unparsed verdict.
_resolve_backlog_bin() {
  if [ -n "${SESSION_REGISTER_BACKLOG_BIN+set}" ]; then printf '%s' "$SESSION_REGISTER_BACKLOG_BIN"; return 0; fi
  local c
  for c in "$HOME/.claude/bin/cc-backlog" "$(command -v cc-backlog 2>/dev/null || true)"; do
    [ -n "$c" ] && [ -x "$c" ] && { printf '%s' "$c"; return 0; }
  done
  printf ''
}

reclaim_worker_item() {
  command -v jq >/dev/null 2>&1 || return 0

  local cwd base item bin host pid out
  cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
  [ -z "$cwd" ] && cwd="$PWD"

  # DISPATCH-WORKTREE GATE. cc-wave-plan fires every worker with `--cwd $WTROOT/wt-<id>`, so the item
  # id is in the cwd — the one handle the worker inherits for free. Anything else is not a dispatched
  # worker and must not touch the ledger at all: no id, no fork, no IDL line (this hook runs on EVERY
  # session start on every account, and the overwhelming majority are not workers).
  #
  # Parameter expansion, not `basename`: this gate runs on every session start, and the whole reason
  # the ancestor walk had to be de-duplicated was fork cost at loadavg 30-50. The cheapest correct
  # path for the overwhelmingly common not-a-worker case is zero forks.
  base="${cwd%/}"; base="${base##*/}"
  case "$base" in
    wt-*) item="${base#wt-}" ;;
    *) return 0 ;;
  esac
  case "$item" in
    *[!0-9a-f]*|'') return 0 ;;                 # ids are 12 lowercase hex — `wt-pool-7` is not one
  esac
  [ "${#item}" -eq 12 ] || return 0

  bin="$(_resolve_backlog_bin)"
  [ -n "$bin" ] && [ -x "$bin" ] || { reclaim_idl abstained "cc-backlog not resolvable: ${bin:-<none>}" "$item"; return 0; }

  # The identity: <host>-<durable claude pid>. The host derivation MUST match cc-backlog's
  # claimer_live byte-for-byte — it only takes the `kill -0` path when `$by` equals "$host-$pid", and
  # a mismatch falls through to the registry, which does not list a pid-shaped claimer and would
  # answer PROVEN NOT-LIVE. That round trip (this writer → that reader) is asserted by test, not by
  # inspection (memory: output-must-round-trip-into-input).
  host="$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo localhost)"
  pid="$CPID"
  [ -n "$pid" ] && [ "$pid" -gt 1 ] 2>/dev/null || { reclaim_idl abstained "no claude ancestor pid" "$item"; return 0; }

  # BOUNDED, but generously: this is a backstop against a wedged fork lingering forever, NOT a
  # latency budget — nothing waits on it (see the detached invocation below). A tight cap here would
  # be an idle-calibrated timeout, i.e. an off switch under exactly the contention where claim
  # liveness matters most (memory: actuator-must-see-the-target-population). Measured: at loadavg 33
  # a single `cc-backlog reclaim` (3 jq passes over the ledger) took multiple seconds.
  local cap="${SESSION_REGISTER_RECLAIM_TIMEOUT:-120}"
  if command -v timeout >/dev/null 2>&1; then
    out="$(timeout "$cap" "$bin" reclaim "$item" --by "$host-$pid" 2>&1)"
  else
    out="$("$bin" reclaim "$item" --by "$host-$pid" 2>&1)"
  fi
  case "$out" in
    # ORDER IS LOAD-BEARING: `case` takes the FIRST match, so the hand-over arm must precede the
    # generic reclaimed arm below — the marker rides INSIDE a `verdict=reclaimed` line, so the
    # generic glob matches it too and would swallow it if it came first.
    #
    # Recorded with a distinct `basis` rather than a distinct disposition, because the DISPOSITION is
    # the same fact (this worker now holds the claim) and the existing consumers select on it. What
    # the basis buys is a countable answer to "did the dispatcher deadlock get cured, or did it just
    # not happen this time?" — without it those two emit identical rows and the fix is unfalsifiable
    # in production (memory: claimed-outcome-vs-checked-outcome). The rate the item asked for is then
    #   jq 'select(.basis=="dispatcher hand-over")'  vs  'select(.reason=="incumbent live")'
    *verdict=reclaimed*\[dispatcher\ hand-over\]*)
                                  reclaim_idl reclaimed "$host-$pid" "$item" "dispatcher hand-over" ;;
    *verdict=reclaimed*)          reclaim_idl reclaimed        "$host-$pid" "$item" ;;
    *verdict=noop-already-ours*)  reclaim_idl noop             "already ours" "$item" ;;
    *verdict=noop-status*)        reclaim_idl noop             "not claimed" "$item" ;;
    *verdict=noop-live-claimer*)  reclaim_idl noop             "incumbent live" "$item" ;;
    # The incumbent's PID is spent but its WORKTREE is not — another session's process tree occupies
    # wt-<item>, so the lease stays where it is (bin/cc-backlog `foreign_wait`). Its own arm rather
    # than the `*)` fallback: unparsed is a wiring fault and this is a measured verdict, and the two
    # must stay countable apart or the guard is unfalsifiable in production (memory:
    # claimed-outcome-vs-checked-outcome).
    *verdict=noop-live-worktree*) reclaim_idl noop             "worktree held by another session" "$item" ;;
    *verdict=unknown-id*)         return 0 ;;                  # a wt-<hex> dir that is not an item
    *)                            reclaim_idl abstained        "unparsed: ${out%%$'\n'*}" "$item" ;;
  esac
  return 0
}

# Hard timeout + unconditional exit 0. `wait` on a killed worker returns non-zero; we swallow it.
register >/dev/null 2>&1 &
_w=$!
( sleep "$P8_TIMEOUT"; kill -9 "$_w" 2>/dev/null ) >/dev/null 2>&1 &
_k=$!
wait "$_w" >/dev/null 2>&1
kill -9 "$_k" >/dev/null 2>&1
wait "$_k" >/dev/null 2>&1

# DETACHED, not waited on. The registration above is waited on because cc-sessions must be able to
# address this pane immediately; the re-key has no such consumer — reap reads it minutes to hours
# later — so making the session wait buys nothing and costs the one thing this hook must never spend.
#
# It is deliberately NOT the wait+kill pattern above. That shape needs a latency budget, and any
# budget small enough to protect a session start is one the work itself exceeds under load: measured
# at loadavg 33, an 8s cap killed the re-key before it landed, which is a feature that switches
# ITSELF OFF exactly when contention makes correct claim liveness matter most (memory:
# actuator-must-see-the-target-population — an idle-calibrated timeout is an off switch under load).
# Detaching removes the trade entirely: the session waits 0s, and the work runs to completion under
# its own generous internal cap.
#
# SESSION_REGISTER_RECLAIM_WAIT=1 runs it in the foreground instead. That seam exists for the test
# suite, which needs the effect to be observable at a deterministic point — including the negative
# cases, where a poll cannot prove that nothing was written. It is NOT the production path, so the
# suite also carries one case that fires WITHOUT it and polls for the durable record, so the detached
# shape shipped here is itself covered.
if [ -n "${SESSION_REGISTER_RECLAIM_WAIT:-}" ]; then
  reclaim_worker_item >/dev/null 2>&1
else
  # EVERY inherited descriptor is dropped, not just stdout/stderr: a detached child that keeps its
  # parent's fds open holds the pipe open too, so a caller reading this hook's output to EOF waits on
  # a process that has nothing to say and may outlive the session start by minutes. stdin is already
  # spent (`input=$(cat)` at the top) and fd 3 is the one bats hands every hook — a background job
  # that inherits it makes bats report a phantom `not ok` beside the real `ok`, and the landing gate's
  # verdict is `grep -c '^not ok'`, so one fabricated line refuses a push that earned no failure
  # (memory: bats-background-job-fabricates-not-ok). `3>&-` on an unopened fd 3 is a silent no-op, so
  # this is safe in every caller.
  ( reclaim_worker_item >/dev/null 2>&1 <&- 3>&- & ) >/dev/null 2>&1 <&- 3>&- &
fi
exit 0
