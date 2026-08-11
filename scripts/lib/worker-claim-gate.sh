#!/usr/bin/env bash
# worker-claim-gate.sh — carry a REFUSED claim into the refused worker's BEHAVIOUR.
#
# ── THE DEFECT, MEASURED ───────────────────────────────────────────────────────────────────────
# 2026-08-07, item `191d4d056c98`: eight sessions came up in ONE worktree
# (`.worktrees/wt-191d4d056c98`). `cc-dispatch` fired exactly ONCE (IDL `action:"fired"` at
# 10:40:16Z); one session reclaimed the lease at 10:41:25Z; the other seven each logged
#
#     {"hook":"session-register","disposition":"noop","reason":"incumbent live","item":"191d4d056c98"}
#
# at 10:41:46–10:44:27Z — and then each did the whole item anyway.
#
# The ledger was never wrong. `cc-backlog`'s lease held perfectly and refused all seven. What was
# missing is a CONSUMER. Census over the executable tree at the time (bin/ hooks/ scripts/ tests/
# commands/) found `noop-live-claimer` in exactly three places:
#
#     bin/cc-backlog:1034            the PRODUCER — prints the verdict
#     hooks/session-register.sh:220  writes ONE IDL line, returns 0
#     tests/{cc-backlog,session-register-reclaim}.bats  assert the string appears
#
# Zero consumers that ACT. The refusal reached a journal and stopped there, which is the definition
# of advisory (memory `conclusion-must-reach-the-enforcing-store`: behaviour reads ENFORCING stores;
# a journal is behind a diode). `tests/session-register-reclaim.bats:184` is even NAMED "a second
# session in the worktree stands down" while asserting only that the LEDGER was not stolen — the
# test name asserted a behaviour the code did not have, and it was green the whole time.
#
# ── WHY THIS IS NOT ANOTHER MESSAGE ────────────────────────────────────────────────────────────
# The obvious fix — tell the duplicate to stand down — is ALREADY REFUTED IN THIS REPO and must not
# be quietly re-committed. `docs/plans/GROUND_UP_DISPATCH.md:615-628` records the live attempt: a
# duplicate lead was sent a stand-down, and
#
#   > It has **not drained** the stand-down (`~/.claude/mailbox/A7DA7EFB….seen` = none). It is deep
#   > in an autonomous tool loop, and mailbox drain needs a turn boundary — the dead-letter shape of
#   > `cc-backlog a98084b79b2c`, hit live for the third time today.
#
# A message needs a turn boundary; a duplicate deep in a tool loop has none. The same passage names
# where the damage actually lands, and it is the reason this gate sits where it sits:
#
#   > **The collision becomes real when either starts writing `docs/plans/DAEMON_FLEET_V2.md`.**
#
# So: enforce at the WRITE, mechanically, with no turn boundary and no cooperation required.
#
# ── WHY NOT AT SessionStart, WHERE THE REFUSAL IS ALREADY KNOWN ────────────────────────────────
# Because SessionStart provably cannot stop anything. On the pinned binary (2.1.114) its output
# schema is `additionalContext` · `sessionTitle` · `watchPaths` · `reloadSkills` · `systemMessage` ·
# `terminalSequence`. `{"continue":false}` has no effect there, `{"decision":"block"}` is not a
# valid field, and exit 2 prints stderr and lets the session proceed. `hooks/session-register.sh`
# is therefore structurally incapable of being the enforcement point no matter what it learns — it
# stays the DETECTOR, and this library is the ACTUATOR.
#
# ── WHY IT RIDES AN ALREADY-REGISTERED HOOK ────────────────────────────────────────────────────
# Same reasoning `64a7d1fa` used to put the Agent-tool capacity term inside `agent-teams-enforce.sh`
# rather than a new hook: a new hook file needs a `settings.json` entry, which is C10 operator-only,
# which means the pending-activation queue — where scripts have been rotting >24 h unrun. A gate
# that ships inert is the generator documented on 2026-08-07. `check-edit-boundary.sh` is already
# registered on `PreToolUse | Write|Edit|MultiEdit`, i.e. exactly the event where the repo's own
# incident log says the collision becomes real.
#
# ── WHY THERE IS NO REFUSAL BUDGET, AND WHY THAT IS NOT A §9 VIOLATION ─────────────────────────
# `scripts/lib/capacity-admit.sh` carries `CC_ADMIT_BUDGET`: after N consecutive refusals it ADMITS
# and pages, because §9's law says no gate on an actuation path may be unbounded. Copying that shape
# here would be a CATEGORY ERROR, and a future reader will want to — so this says why not.
#
# A capacity refusal denies a TRANSIENT MACHINE STATE that the refusal itself cannot lower (§12.2:
# ~2.4 unsheddable cores), so an unbounded one converts "the box is busy" into "the box never
# recovers". A duplicate-worker refusal denies a FACT — another live process holds this lease — and
# admitting on budget expiry does not release a stuck recovery path, it MINTS THE SECOND WORKER this
# file exists to prevent. The unsafe direction is inverted between the two gates.
#
# §9 is satisfied, by a bound that already exists and is not ours to duplicate:
#   · the incumbent dies      ⇒ the next evaluation reclaims and ADMITS (re-evaluated every TTL)
#   · the claim ages out      ⇒ `cc-backlog reap` past LIVE_CLAIM_MAX_S releases it
#   · the operator/agent      ⇒ CC_WCLAIM_GATE=off
#   · the refused worker      ⇒ is told to self-close, so it does not sit spinning on the refusal
# The bound lives in the LEASE, which is the thing that actually knows when the fact stops being
# true. A second bound layered here could only ever disagree with it (memory
# `make-the-actuator-the-arbiter`).
#
# ── THE ACTUATOR IS THE ARBITER ────────────────────────────────────────────────────────────────
# This gate never re-implements `claimer_live`. It calls `cc-backlog reclaim` — the same atomic
# primitive `hooks/session-register.sh` calls, from the same identity — and branches on its
# documented `verdict=` contract (bin/cc-backlog:983-986). Consequences that fall out for free:
# whoever reclaims first owns the item and everyone else is refused, with no second arbitration
# surface to race; a stale marker cannot brick a session, because there is no marker — every
# uncached evaluation asks the ledger; and the incumbent's own path is CHEAP, because
# `verdict=noop-already-ours` returns at bin/cc-backlog:1013, twenty lines BEFORE the oracle fork at
# :1034. Only a non-owner pays for `claimer_live`, and a non-owner is either a duplicate (worth it)
# or a worker whose claim is stale (pays once, then owns it).
#
# ── Caller contract ────────────────────────────────────────────────────────────────────────────
#   . scripts/lib/worker-claim-gate.sh
#   cc_worker_claim_admit <caller> <cwd> [what]   → 0 = ADMIT, 9 = REFUSE
#       <caller>  short stable id, [A-Za-z0-9._-] only. Keys the admit cache. An unusable id is
#                 fail-OPEN (recorded): a gate must not convict on its own bad wiring.
#       <cwd>     the directory that identifies the work. `wt-<12 lowercase hex>` ⇒ a dispatch
#                 worktree, anything else ⇒ not our population, admit.
#       [what]    free text naming the act, carried into the record and the refusal sentence.
#   cc_worker_claim_reason  → the human sentence for the last evaluation.
#   cc_worker_claim_item    → the item id the last evaluation resolved, or "".
#   cc_worker_claim_holder  → the incumbent identity from the last REFUSE, or "".
#
# ── ONE DELIBERATE DEVIATION FROM capacity-admit's "every path records" RULE ────────────────────
# capacity-admit emits a row on EVERY return because its callers are rare spawn events. This gate's
# caller is EVERY Write/Edit in EVERY session on the box, and the overwhelming majority are not in a
# dispatch worktree at all. A row per write would flood the IDL that `cc-idl` and `cc-audit` read,
# and an alarm that always fires carries the same zero bits as one that cannot (memory
# `alarm-polarity-and-attention-budget`). So the NOT-A-WORKER branch is silent AND forkless — the
# same call that `hooks/session-register.sh:175-192` makes for the same reason, by pure parameter
# expansion with zero forks. Every branch INSIDE the dispatch-worktree population still records.
#
# Env: CC_WCLAIM_GATE(on) · CC_WCLAIM_TTL_S(60) · CC_WCLAIM_TIMEOUT_S(30) · CC_WCLAIM_BACKLOG_BIN ·
#      CC_WCLAIM_STATE_DIR · CC_WCLAIM_IDL · CC_WCLAIM_HOST · CC_WCLAIM_PID
# Pure definitions only — safe to source under `set -u`. bash 3.2-safe, BSD+GNU portable, no eval.

CC_WCLAIM_REASON=""
CC_WCLAIM_ITEM=""
CC_WCLAIM_HOLDER=""
cc_worker_claim_reason() { printf '%s' "$CC_WCLAIM_REASON"; }
cc_worker_claim_item()   { printf '%s' "$CC_WCLAIM_ITEM"; }
cc_worker_claim_holder() { printf '%s' "$CC_WCLAIM_HOLDER"; }

# ── record ONE row into the IDL ────────────────────────────────────────────────────────────────
# Same store and the same `gate:` discriminator shape capacity-admit uses, so `cc-idl` can select
# admissions across every gated path with ONE predicate rather than two hand-written asymmetric
# ones. Carried on BOTH verdicts for exactly that reason (§9.5.1's population defect).
#
# SELF-CONTAINED ON PURPOSE — it must NOT source hooks/lib/idl-log.sh: that lib defines a global
# `log_idl`, and a library that silently overwrites its caller's telemetry writer to install a gate
# is a worse defect than the ungated write. What idl-log.sh protects is the INVARIANT, not the
# function: jq-encode EVERY field, because ONE malformed line aborts the `jq -rs` slurp in cc-audit,
# which then reads as "no records" and flips an abstain alarm green. Honoured here by construction
# (`jq -cn --arg` only) — no jq, no row, never a raw append.
_cc_wclaim_emit() { # $1=verdict admit|refuse  $2=basis  $3=caller  $4=what  $5=detail  [$6=item] [$7=holder]
  local idl ts
  idl="${CC_WCLAIM_IDL:-$HOME/.claude/autonomy/idl.jsonl}"
  command -v jq >/dev/null 2>&1 || return 0
  mkdir -p "$(dirname "$idl")" 2>/dev/null || true
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo '?')"
  jq -cn --arg ts "$ts" --arg disp "$( [ "$1" = admit ] && echo admitted || echo refused )" \
         --arg v "$1" --arg b "$2" --arg c "$3" --arg w "$4" --arg d "$5" \
         --arg item "${6:-}" --arg holder "${7:-}" --arg sid "${CC_WCLAIM_SID:-?}" \
    '{ts:$ts,hook:"worker-claim-gate",sid:$sid,disposition:$disp,reason:"duplicate-worker",
      gate:"worker-claim-gate",verdict:$v,basis:$b,caller:$c,what:$w,detail:$d}
     + (if $item   == "" then {} else {item:$item}     end)
     + (if $holder == "" then {} else {holder:$holder} end)' >> "$idl" 2>/dev/null || true
  return 0
}

# ── the worker identity ────────────────────────────────────────────────────────────────────────
# `<host>-<durable claude ancestor pid>` — and it MUST equal what hooks/session-register.sh writes,
# byte for byte. cc-backlog's `claimer_live` only takes its cheap `kill -0` path when the claimant
# string matches "$host-$pid" (bin/cc-backlog:1307-1312); a mismatch falls through to the registry,
# which does not list a pid-shaped claimer and would answer PROVEN NOT-LIVE — a false death that
# turns this gate into a claim-stealer. The two derivations are DUPLICATED rather than shared
# because session-register.sh is a hot SessionStart hook whose structure is load-bearing; they are
# pinned equal by test instead, which is the same treatment the capacity ceilings get in
# tests/capacity-admit-parity.bats (a value changed on one side goes RED instead of drifting).
#
# NOT $PPID: the hook runs under a /bin/sh shim that exits immediately, so $PPID is dead within
# seconds and useless as a liveness handle (the teammate-lifecycle $PPID lesson).
_cc_wclaim_ancestor_pid() {
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

# ── cc-backlog resolution ──────────────────────────────────────────────────────────────────────
# CC_WCLAIM_BACKLOG_BIN — UNSET ⇒ resolve one. SET, including set to EMPTY ⇒ honored verbatim, so
# `CC_WCLAIM_BACKLOG_BIN=` genuinely turns the gate off at the source. `${VAR:-}` cannot tell unset
# from set-empty, and a seam that cannot turn a thing off is not a seam (the house pattern —
# cc-backlog's own CC_BACKLOG_LSOF_BIN, session-register's SESSION_REGISTER_BACKLOG_BIN).
_cc_wclaim_backlog_bin() {
  if [ -n "${CC_WCLAIM_BACKLOG_BIN+set}" ]; then printf '%s' "$CC_WCLAIM_BACKLOG_BIN"; return 0; fi
  local c
  for c in "$HOME/.claude/bin/cc-backlog" "$(command -v cc-backlog 2>/dev/null || true)"; do
    [ -n "$c" ] && [ -x "$c" ] && { printf '%s' "$c"; return 0; }
  done
  printf ''
}

# ── the DONE holder ────────────────────────────────────────────────────────────────────────────
# Who last held a DONE-latched item. Printed empty when it cannot be established — and every caller
# treats empty as ADMIT, never as "not the holder", because an unreadable oracle is not evidence
# (memory `lookup-miss-is-not-absence`; the same rule the unparsed-reclaim arm already follows).
#
# WHY THIS COSTS A FORK AND WHY THAT IS ACCEPTABLE. `cc-backlog` has no single-item read, so this is
# the whole-ledger fold. It is paid ONLY on the `status=done` branch, which is off the hot path by
# construction: an open item never reaches here, and a done item is the case we are about to refuse.
# The finisher's own admit is cached like any other, so a session tidying up after its own `done`
# pays it once per TTL, not per write.
_cc_wclaim_item_holder() { # $1=bin $2=item → holder identity, or empty
  local out cap="${CC_WCLAIM_TIMEOUT_S:-30}"
  case "$cap" in ''|*[!0-9]*) cap=30 ;; esac
  if command -v timeout >/dev/null 2>&1; then
    out="$(timeout "$cap" "$1" list --all --json 2>/dev/null || true)"
  else
    out="$("$1" list --all --json 2>/dev/null || true)"
  fi
  [ -n "$out" ] || { printf ''; return 0; }
  printf '%s' "$out" | jq -r --arg id "$2" '
      [ .[]? | select(.id == $id) | .by // "" ] | first // ""
    ' 2>/dev/null || printf ''
}

# ── the ADMIT cache ────────────────────────────────────────────────────────────────────────────
# POSITIVE only: an admit is cached for CC_WCLAIM_TTL_S, a refusal NEVER is. That asymmetry is the
# whole self-healing property — the moment the incumbent dies, the next write re-asks the ledger,
# reclaims, and proceeds; whereas a cached refusal would keep convicting a session whose grounds had
# already dissolved (memory `parked-blocker-obsoleted-by-later-fix`).
#
# The epoch is written INTO the file rather than read from its mtime: `stat -f %m` (BSD) and
# `stat -c %Y` (GNU) disagree, and a portability probe on a per-write hot path buys nothing.
# The key carries the identity, so a recycled pane with a new pid cannot inherit a stale admit.
_cc_wclaim_cache_file() { # $1=caller $2=item $3=identity → path, or empty when unusable
  local dir="${CC_WCLAIM_STATE_DIR:-$HOME/.claude/autonomy/worker-claim-gate}" key
  case "$1" in ''|*[!A-Za-z0-9._-]*) return 0 ;; esac
  key="$2.$3"
  case "$key" in ''|*[!A-Za-z0-9._-]*) return 0 ;; esac
  mkdir -p "$dir" 2>/dev/null || return 0
  printf '%s/%s.%s.admit' "$dir" "$1" "$key"
}

_cc_wclaim_cache_fresh() { # $1=file $2=ttl → 0 fresh / 1 stale-or-absent
  # `stamped`, never `then`: `then` is a shell keyword, and `local then` is SC1010 — the exact
  # warning the landing gate named on 07f9707c. It parses, so only the linter catches it.
  local stamped now
  [ -n "$1" ] && [ -f "$1" ] || return 1
  stamped="$(cat "$1" 2>/dev/null || echo '')"
  case "$stamped" in ''|*[!0-9]*) return 1 ;; esac
  now="$(date +%s 2>/dev/null || echo 0)"
  case "$now" in ''|*[!0-9]*) return 1 ;; esac
  [ "$((now - stamped))" -lt "$2" ] && [ "$((now - stamped))" -ge 0 ]
}

# ── the gate ───────────────────────────────────────────────────────────────────────────────────
cc_worker_claim_admit() { # $1=caller $2=cwd $3=what → 0 admit / 9 refuse
  local caller="${1:-unknown}" cwd="${2:-}" what="${3:-write}"
  local base item bin host pid ident ttl cap cfile out detail

  CC_WCLAIM_REASON=""; CC_WCLAIM_ITEM=""; CC_WCLAIM_HOLDER=""

  # NOT-A-WORKER: zero forks, no record. See the header — this is the hot path for every session on
  # the box, and it must cost nothing. Parameter expansion only, never `basename`.
  [ -n "$cwd" ] || return 0
  base="${cwd%/}"; base="${base##*/}"
  case "$base" in wt-*) item="${base#wt-}" ;; *) return 0 ;; esac
  case "$item" in *[!0-9a-f]*|'') return 0 ;; esac    # ids are 12 lowercase hex — `wt-pool-7` is not one
  [ "${#item}" -eq 12 ] || return 0
  CC_WCLAIM_ITEM="$item"

  # From here down we are inside the dispatch-worker population, and every branch records.
  if [ "${CC_WCLAIM_GATE:-on}" = off ]; then
    CC_WCLAIM_REASON="worker-claim-gate: OFF (CC_WCLAIM_GATE=off) — claim not consulted"
    _cc_wclaim_emit admit gate-off "$caller" "$what" "CC_WCLAIM_GATE=off" "$item"; return 0
  fi

  command -v jq >/dev/null 2>&1 || {
    CC_WCLAIM_REASON="worker-claim-gate: jq absent -> ADMIT (fail-open)"
    return 0; }   # no jq ⇒ no record either; _cc_wclaim_emit is a no-op without it

  bin="$(_cc_wclaim_backlog_bin)"
  if [ -z "$bin" ] || [ ! -x "$bin" ]; then
    CC_WCLAIM_REASON="worker-claim-gate: cc-backlog not resolvable (${bin:-<none>}) -> ADMIT (fail-open)"
    _cc_wclaim_emit admit fail-open "$caller" "$what" "cc-backlog not resolvable: ${bin:-<none>}" "$item"
    return 0
  fi

  host="${CC_WCLAIM_HOST:-$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo localhost)}"
  pid="${CC_WCLAIM_PID:-$(_cc_wclaim_ancestor_pid)}"
  if [ -z "$pid" ] || ! [ "$pid" -gt 1 ] 2>/dev/null; then
    CC_WCLAIM_REASON="worker-claim-gate: no claude ancestor pid -> ADMIT (fail-open)"
    _cc_wclaim_emit admit fail-open "$caller" "$what" "no claude ancestor pid" "$item"
    return 0
  fi
  ident="$host-$pid"

  ttl="${CC_WCLAIM_TTL_S:-60}"; case "$ttl" in ''|*[!0-9]*) ttl=60 ;; esac
  cfile="$(_cc_wclaim_cache_file "$caller" "$item" "$ident")"
  if _cc_wclaim_cache_fresh "$cfile" "$ttl"; then
    CC_WCLAIM_REASON="worker-claim-gate: ADMIT (cached, <${ttl}s) — $ident owns $item"
    return 0                                  # deliberately silent: one row per TTL, not per write
  fi

  # THE REAL CALL. Bounded, but the bound is a backstop against a wedged fork, not a latency budget:
  # an idle-calibrated timeout is an off switch under exactly the contention where duplicate workers
  # appear (memory `actuator-must-see-the-target-population`, and the measured reason
  # session-register raised its own cap to 120s). A timeout here is fail-OPEN and recorded.
  cap="${CC_WCLAIM_TIMEOUT_S:-30}"; case "$cap" in ''|*[!0-9]*) cap=30 ;; esac
  if command -v timeout >/dev/null 2>&1; then
    out="$(timeout "$cap" "$bin" reclaim "$item" --by "$ident" 2>&1)"
  else
    out="$("$bin" reclaim "$item" --by "$ident" 2>&1)"
  fi

  case "$out" in
    *verdict=noop-live-claimer*)
      # THE REFUSAL, now load-bearing. Holder is parsed for the message only; the VERDICT is the
      # ledger's, never ours (`is held by <who>, which is LIVE`).
      CC_WCLAIM_HOLDER="$(printf '%s' "$out" | sed -n 's/.*is held by \([^,]*\), which is LIVE.*/\1/p' | head -1)"
      detail="$item is held by ${CC_WCLAIM_HOLDER:-another live session}; this session is $ident"
      CC_WCLAIM_REASON="worker-claim-gate: REFUSING $what — $detail"
      _cc_wclaim_emit refuse measured "$caller" "$what" "$detail" "$item" "$CC_WCLAIM_HOLDER"
      return 9 ;;
    *verdict=noop-live-worktree*)
      # THE SAME REFUSAL, reached by the second oracle. The incumbent's `<host>-<pid>` is a spent
      # SHELL, but another session's process tree is cwd'd in this item's worktree, so the ledger
      # kept the lease where it was (bin/cc-backlog `foreign_wait`, backlog f61c1eaaba05).
      #
      # ITS OWN ARM, NOT THE `*)` FALLBACK — and the fallback is why this is load-bearing rather
      # than cosmetic. `*)` here is fail-OPEN by design (an unreadable oracle is not evidence of a
      # duplicate), so a new refusal spelling left unhandled would be silently upgraded into an
      # ADMIT: the ledger would refuse the re-key and this gate would wave the duplicate through
      # anyway, which is strictly worse than never having added the oracle (memory:
      # new-nonverdict-state-strands-its-consumers).
      #
      # The §9 bound argument above carries over unchanged, term for term: the occupying tree exits
      # ⇒ the next evaluation reclaims and ADMITS; the claim ages past LIVE_CLAIM_MAX_S ⇒ `reap`
      # releases it; CC_WCLAIM_GATE=off; and the refused worker is told to self-close rather than
      # spin. No second bound is minted here.
      CC_WCLAIM_HOLDER="$(printf '%s' "$out" | sed -n 's/.*is held by \([^,]*\), whose process is gone.*/\1/p' | head -1)"
      detail="$item's worktree is held by another live session (lease recorded to ${CC_WCLAIM_HOLDER:-an earlier worker}); this session is $ident"
      CC_WCLAIM_REASON="worker-claim-gate: REFUSING $what — $detail"
      _cc_wclaim_emit refuse measured "$caller" "$what" "$detail" "$item" "$CC_WCLAIM_HOLDER"
      return 9 ;;
    *verdict=reclaimed*|*verdict=noop-already-ours*)
      [ -n "$cfile" ] && printf '%s\n' "$(date +%s 2>/dev/null || echo 0)" > "$cfile" 2>/dev/null || true
      CC_WCLAIM_REASON="worker-claim-gate: ADMIT — $ident holds the claim on $item"
      _cc_wclaim_emit admit measured "$caller" "$what" "claim held by this session ($ident)" "$item"
      return 0 ;;
    *verdict=noop-status*)
      # THREE-VALUED, not two. This arm used to admit open / done / blocked alike, reasoning that
      # "`cc-dispatch` owns whether an item may be worked, and a done-latch refusal is its rc 4,
      # taken before any spawn." That premise held only for workers dispatch SPAWNED. Measured
      # 2026-08-07 on item 149789b69fc4: dispatch fired exactly ONCE, and the population arrived by
      # Agent-tool fan-out instead — 224 spawns over 3 generations, which never consults dispatch and
      # so never meets its rc 4. Those workers reached a DONE item, read "not claimed", and were
      # admitted: 6 rows, basis=no-claim, every one a duplicate. Across the gate's whole lifetime it
      # had recorded 21 admits and zero refusals.
      #
      # So DONE gets its own arm. OPEN and BLOCKED keep the old behaviour verbatim — there is no
      # lease to conflict with and taking one is not this gate's job.
      case "$out" in
        *status=done*)
          # The finisher is NOT a duplicate. A worker that completed the item and is now committing
          # or tidying must not be locked out of its own work — that would clog exactly the commit
          # path this gate exists to protect. The ledger's `by` carries forward through `done`, so
          # it names the session that held it. Unreadable ⇒ ADMIT (fail-open), never a refusal built
          # on a lookup we could not perform.
          CC_WCLAIM_HOLDER="$(_cc_wclaim_item_holder "$bin" "$item")"
          if [ -z "$CC_WCLAIM_HOLDER" ]; then
            CC_WCLAIM_REASON="worker-claim-gate: ADMIT (fail-open) — $item is done but its holder is unreadable"
            _cc_wclaim_emit admit fail-open "$caller" "$what" "done item, holder unreadable" "$item"
            return 0
          fi
          if [ "$CC_WCLAIM_HOLDER" = "$ident" ]; then
            [ -n "$cfile" ] && printf '%s\n' "$(date +%s 2>/dev/null || echo 0)" > "$cfile" 2>/dev/null || true
            CC_WCLAIM_REASON="worker-claim-gate: ADMIT — $ident is the session that completed $item"
            _cc_wclaim_emit admit measured "$caller" "$what" "finisher of a done item ($ident)" "$item"
            return 0
          fi
          detail="$item is DONE (completed by $CC_WCLAIM_HOLDER); this session is $ident"
          CC_WCLAIM_REASON="worker-claim-gate: REFUSING $what — $detail. The work is finished; STAND DOWN rather than redo it. If you believe it is genuinely unfinished, reopen it deliberately (cc-backlog reopen $item) instead of writing over a closed item."
          _cc_wclaim_emit refuse done-latched "$caller" "$what" "$detail" "$item" "$CC_WCLAIM_HOLDER"
          return 9 ;;
      esac
      [ -n "$cfile" ] && printf '%s\n' "$(date +%s 2>/dev/null || echo 0)" > "$cfile" 2>/dev/null || true
      CC_WCLAIM_REASON="worker-claim-gate: ADMIT — $item carries no claim to conflict with"
      _cc_wclaim_emit admit no-claim "$caller" "$what" "item not in claimed state" "$item"
      return 0 ;;
    *verdict=unknown-id*)
      # A `wt-<12hex>` directory whose id is in no ledger. Not a dispatch worktree in any meaningful
      # sense; admit and cache so a hand-made path does not pay the fork on every write.
      [ -n "$cfile" ] && printf '%s\n' "$(date +%s 2>/dev/null || echo 0)" > "$cfile" 2>/dev/null || true
      CC_WCLAIM_REASON="worker-claim-gate: ADMIT — $item is in no ledger"
      _cc_wclaim_emit admit unknown-id "$caller" "$what" "id not present in the backlog" "$item"
      return 0 ;;
    *)
      # UNPARSED — including the timeout's empty output. Fail OPEN and NAME the cause rather than
      # reporting a verdict we did not get: a gate that convicts on its own bad wiring is the
      # anti-pattern capacity-admit calls out by name, and an unreadable oracle is not evidence of a
      # duplicate (memory `lookup-miss-is-not-absence`).
      detail="unparsed reclaim output: ${out%%$'\n'*}"
      CC_WCLAIM_REASON="worker-claim-gate: ADMIT (fail-open) — $detail"
      _cc_wclaim_emit admit fail-open "$caller" "$what" "$detail" "$item"
      return 0 ;;
  esac
}
