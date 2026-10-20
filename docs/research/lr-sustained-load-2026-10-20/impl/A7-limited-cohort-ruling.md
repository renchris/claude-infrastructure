# A7: a session that turns limited while another lane has it queued — decision packet and build design

Item: A7-limited-cohort-ruling. Author: worker agent, 2026-10-20, read-only research. Code cites are
to this worktree at `28b25a119`; `git diff --stat 28b25a119 main -- scripts/limit-recover bin/cc-lr
scripts/handoff-fire.sh scripts/lib` is empty, so every line number also holds on `main` (`6fdf87eca`).

**Labels.** *Measured* = read from a named file or command (the command is given). *Estimated* = derived,
method named. *Hypothesis* = not verified. Every live read was read-only; the only things written were
scratch files under `/tmp/a7/` and this file. One deviation is recorded in §13.

---

## 0. Bottom line

- **The operator has already ruled.** At **2026-10-20T17:10:31Z** the operator typed
  `touch ~/.reso/limit-recover/recon/autorecover.on`.
  - Measured: session transcript `fd47f3fe-9ffa-4903-be38-68698c21853e.jsonl` row 593, a `<bash-input>` user record. Also
    `stat -f %SB ~/.reso/limit-recover/recon/autorecover.on` => `2026-10-20T12:10:32-0500`.
  - The lead session closed backlog row `be52a4c8a99f` (the D1.14 step) at 17:11:02Z.
  - The global `autorecover.on` has existed since 2026-09-29.
  - So `zero_human()` (`lr_recon/__main__.py:225-231`) now reads true. Every hook-origin and census-origin limited record is
    re-derived as acting (not plan-only) at its next upsert (`census.py:345-349`, `:459`).
  - Panes 20/30 would now be driven by the reconciler with no human. The D1.9 question this item asked is answered.
- **What the ruling leaves open, and this design builds:**
  - Today the reconciler and the reset poller **both** drive the same capped session hands-off. Only a first-come run
    claim arbitrates between them.
  - That race is measured to cost 11-18 min on panes 20/30, and the run claim is the only thing between it and a double
    driver: before Wave G it produced a PARTIAL half-move on pane 20 (10-18).
  - The move lane can still sit on a now-limited session for up to 600 s.
  - The status label lies for plan-only records.
  - The documented off switch can strand a half-done move.
- **Verdict: BUILD.** The recommended option needs no further operator act. Overall conviction is **70%** (per part in §5).

## 1. What happened to panes 20 and 30 (measured)

| Time (Z) | Lane | Event | Source |
|---|---|---|---|
| 02:48:13 | move lane | idle batch requested by hand from pane 35; the workers hold `runs/by-sid/<sid>.active` | `02-timeline-forensics.md` §3.7; `lr-move-batch.sh:247` |
| 03:00-03:34 | move lane | batches 1 and 2 sit in the 20/core load wait (since removed by wave 2, `05829eeb7`) | 02 §3.7 |
| 03:13:21 / 03:19:58 | — | 3e929a81 (pane 20) and 3d1d988a (pane 30) hit the next3 weekly cap; the hook writes `requests/<sid>.json` | 02 §3.7 |
| 03:15:54 / 03:23:43 | reconciler | hook-origin records are created `plan_only: true`, because `recon/autorecover.on` was then absent; placements naming an account are dropped (`__main__.py:1043-1045`) | 10 X2 |
| 03:20:04-08 | poller | `RUN-CLAIM-HELD … pid 7621 / 91151` then `REQUEST-IN-FLIGHT … kept for re-check` (it defers to the move workers' claims) | `poller.log:233750-233755` |
| 03:34:29-36 | move lane | `NOTMOVED became-limited … Recover it: cc-lr recover <sid8>`, addressed to a human | 02 §3.7; `lr-move-worker.sh:201` |
| 03:43 → | reconciler | records sit `PRE-MOVE/WAIT_DATA`; `cc-lr status` says "next: the reconciler retries", which is false for a plan-only record | 10 X2; `report.py:176` |
| 04:10:36 / 04:10:46 | poller | next tick (ticks then ran ~50 min apart at priority 20). Two dispatches: `HELD:unreachable` and `PARKED` (router rc=3). Verdicts "on disk only" (`cc-notify: role 'desk' is not set`) | `poller.log:233937-233942`; `fleet/one-20261020T0410*/verdict.txt` |
| 04:38:45 | operator | `refire … by=cc-lr` promotes both records to cc-lr origin (acting) | `recon/events.jsonl` |
| 04:42:05 / 04:45:00 | poller | second dispatches take the run claims (attempts 2/3 and 1/3 after a refund) | `poller.log:234106-234114` |
| 04:53:18-52 | reconciler | both placed; `own … held` then `claim-held … pid 86745/79488 (a bash lane) drives it; no token minted` | `recon/events.jsonl` |
| 05:04:09 / 05:06:22 | poller | both poller runs end `PARKED` (router `--max-wait expired`, 34-42 s per try) | `fleet/one-20261020T0442*`, `…T0445*/results.tsv` |
| 05:05:49 / 05:11:51 | reconciler | `own … stolen-dead`, then spawns R | `recon/events.jsonl` (file order; see the caveat below) |
| 05:17:02 / 05:28:08 | reconciler | `R rc=0`, `r-in-place … live in its own window … on next after R`: 2 of 2 recovered | `recon/events.jsonl`; `recon/launch.log` |

Caveat on event times: a `spawn` row's `t` is the pass's `now`. It can therefore read earlier than an `own` row written
before it in the same file (05:00:49 printed after 05:05:49). That is the B7 pass-scoped-`now` class. The ordering
above follows file order.

**What "each lane thought the other owned them" really was.** Each lane deferred to another for its own reason:

- The move lane deferred to a human: its text said "cc-lr recover".
- The poller deferred to the move lane's run claim, then waited for a tick 50 min away.
- The reconciler was plan-only, but printed that it would retry.

Since then:

- wave 2 removed the load wait;
- wave 1 put the poller at priority 31 (ticks now every ~10.7 min, below);
- the operator's 17:10Z touch removed the plan-only state.

The two residues are the **race** between the two hands-off lanes, and the move lane's **slot and draft waits**.

## 2. The zero-human ruling and the fence, as they stand

- **D1.9** (`docs/plans/LIMIT_RECOVER_FLEET_V2.md:143`, `:476`, `:531`; `LIMIT_RECOVER_FLEET_V2_ARCHITECTURE.md:877`):
  - `~/.reso/limit-recover/autorecover.on` is "the single zero-human switch" for the legacy lanes (the poller's hook
    requests and `reroute_parked`, `lr-reset-poller.sh:1660`, `:2464`).
  - The reconciler acts on a non-cc-lr record only when its own `recon/autorecover.on` also exists. The operator
    creates that file "after the first attended reconciler cohort closes clean" (D1.14). No daemon creates either.
- **State now** (measured: `ls -la`/`stat` at 17:37Z):

  | file | state |
  |---|---|
  | `autorecover.on` | present since 2026-09-29 |
  | `recon/autorecover.on` | present since 17:10:32Z |
  | `recon.on` | present |
  | `recon/mode` | `act` |

  `LR_IDLE_FANOUT` is unset: the reconciler plist has no `EnvironmentVariables` (`grep -c EnvironmentVariables` => 0),
  and `census.py:281` defaults to off. So in practice the hands-off scope is **limited** sessions, not idle fan-out.
- **No burst followed the flip.** `tail recon/events.jsonl` => the last row is `t=1792497667` (12:01:07Z). The only open
  records are 4 stale idle fan-out `PARKED-REBOOT` records from early October, which `may_actuate` refuses anyway
  (`act.py:460-461`).
- **The fence** (`scripts/limit-recover/lr-recon-fence.sh:167-216`):
  - A legacy actor defers only while `recon/owned/<sid>` exists and the heartbeat is fresh.
  - `owned/<sid>` is written only by `_own_and_charge` (`__main__.py:1058-1080`), and only for a non-plan-only record in
    `PLANNED` (`:1065`).
  - So from detection until the reconciler's first placement, the poller's fence reads `verdict=act reason=not-owned`.
    The same holds for a record that goes straight to `WAIT_RESET` (stay) and is never `PLANNED`.
  - Measured live today by the `/tmp` probe in §9: `lr-recon-fence: verdict=act sid=52e35019 reason=not-owned`.
- **The run claim is the only arbiter in that window.** Wave G (`6a5a07063`, 2026-10-19T11:13Z) added `act.hold_claim`
  (`act.py:493-526`). The reconciler mints no token while `runs/by-sid/<sid>.active` names another live driver.
  - Before Wave G, the race produced a half-move on pane 20 itself:
    - poller dispatch 10-18T07:47:47Z ended `PARTIAL rc=4 … transplanted but the relaunch did not verify — source is a
      tombstoned husk` (`fleet/one-20261018T074747Z-3e929a81/verdict.txt`);
    - the reconciler's A spawned at 07:56:43;
    - the record then logged `RECON-DEFECT PRE-MOVE/IN-FLIGHT` every pass for more than 5 h (`recon/events.jsonl`).
  - Since Wave G there is one driver at a time, but whichever lane takes the claim first holds it for its whole run.

## 3. The question, in plain English

> You turned on hands-off recovery for the reconciler at 17:10Z. Now two automatic lanes, the reconciler and the reset
> poller, both try to recover every capped session, and whichever grabs the session first keeps it until its run ends,
> even when that run is the weaker one. **Should the reconciler go first, with the poller stepping in only if the
> reconciler has not moved a session within 10 minutes?** And should the move lane let go of a session the moment it
> turns limited, instead of after its slot or draft wait?

## 4. Options, with measured outcomes

The populations are the October records and runs.

- Commands:
  - `python3 -I /tmp/a7/recs.py` and `recs2.py` (`recon/sessions/*.json` joined with `events.jsonl{,.1}` spawn rows);
  - `python3 -I /tmp/a7/poller.py` (`poller.log` dispatch lines joined with `fleet/one-*/verdict.txt`);
  - `python3 -I /tmp/a7/rspawn.py`.
- `recon/sessions/` keeps only the latest record per sid, so the record counts are lower bounds.

| | Option | What it does | Measured outcome behind it |
|---|---|---|---|
| **O1** | Status quo since 17:10Z | Both lanes act on hook-origin limited sessions; the first to take `runs/by-sid` wins | Poller lane, Oct: 97 dispatches; 30 RECOVERED (31%), 30 PARKED, 8 HELD:unreachable, 9 FAILED, 7 HELD:bg-work, 13 other. Reconciler acting lane, Oct: 39 A/R spawns; 11 rc=0 (A 4, R 7), 20 rc=6. Race cost on 10-20: the poller held both claims 21-22 min on runs that PARKED while the reconciler was placed and refused (`claim-held` 04:53 → 05:05/05:11), so the reconciler waited 12.5 and 18.5 min. 5 of 18 cc-lr reconciler records were closed by "moved there by another recovery path". The poller gives up after 3 dispatches (`lr-reset-poller.sh:1395`, exhausted → page `:1801-1813`). 4 of 4 poller verdicts on 10-20 reached nobody (`role 'desk' is not set`) |
| **O2** | **Reconciler first, poller as a bounded backstop** (recommended) | The poller stands back from a sid for which a live, hands-off reconciler in act mode holds an open, actionable record, for ≤600 s from detection (or from a passed `WAIT_RESET` eta), then acts exactly as today. Plus B, C, D below | Removes the 11-18 min claim block above, and the overlapping post-reset wakes (§6 A, call site 3). Keeps the poller's measured rescue value (hook-origin plan-only records closed with median 17.1 min, n=38) for any record the reconciler fails to place within the bound |
| O3 | Poller first for hook origin | The reconciler waits on hook-origin records; it drives only census-origin and cc-lr records | The poller lane gives up at 3 attempts, which is contrary to the premise's "no giving up for soft reasons" (REPORT §5 G5). It has no seat accounting or wall-clock admission pacing, and its verdicts are unreported. Its per-attempt success (31%) is no better than the reconciler's (11/39 = 28% rc=0), both in the priority-20 era |
| O4 | Undo the 17:10Z touch, and add gap-3 E5 | The reconciler is plan-only again. A census-origin limited record past `W_hard` writes a poller request | Plan-only cost, measured: census-origin plan-only limited records took median 343 min to close (max 3,695; n=9; most of them closed only by their own reset, per gap-3 §2.6). Hook-origin ones were rescued by the poller, median 17.1 min (n=38). This reverses the operator's act of 27 minutes earlier |
| O5 | REPORT A7's first variant | The move worker's `became-limited` auto-runs `cc-lr recover` (origin cc-lr) | Redundant now that the marker is on (the hook request and the census already create an acting record). Worse, cc-lr origin is sticky (`census.py:346-349`), so those sessions would escape the operator's off switch (`rm recon/autorecover.on`). Not recommended |

## 5. Recommendation

**O2, built as four parts.** They are independent, and each has its own kill switch.

| Part | What | Conviction | Why not higher |
|---|---|---|---|
| A | Poller stands back for ≤600 s from a sid the hands-off reconciler holds open | 70% | The PRI-31 reconciler's detect→`PLANNED` latency under cohort load is unmeasured (no cohort since the 07:23Z reload), so the size of the benefit is estimated from one incident. The backstop delay is the cost |
| B | The move worker re-reads the limit inside its slot, draft and idle waits (every 30 s) | 80% | No measured slot-wait instance yet. The 10-20 hold was the load wait, now gone |
| C | `next_action` names plan-only honestly | 90% | Cosmetic. It matters only while a marker is off |
| D | A plan-only flip never strands the reconciler's own half-done move | 55% | The gate refusal is measured (§9 T-D1). Whether `plan_only` really flips mid-move when the marker is deleted is a **hypothesis**, so D ships only if its integration control (T-D2) is red |

---

## 6. Implementation design

### Part A — reconciler first, poller as a bounded backstop (`scripts/limit-recover/lr-reset-poller.sh`)

**A.1 New predicate**, inserted after `lrp_act_done` (`lr-reset-poller.sh:180`). It uses the fence library already sourced at
`:166-173` (`_lr_recon_root`, `lr_recon_live`) and jq, as the poller already does at `:2543`. It is bash 3.2-safe: no
`case`+`continue` inside `$( )`, and here-strings are fine in 3.2.

```bash
# ── RECONCILER FIRST, POLLER AS A BOUNDED BACKSTOP (A7, lr-sustained-load 2026-10-20) ────────────
# With hands-off recovery on (autorecover.on AND recon/autorecover.on; the operator created the second
# 2026-10-20T17:10:31Z), a live reconciler in act mode drives every limited session it holds an open
# record for. Its fence (owned/<sid>) starts only at PLANNED, so until then this lane and the reconciler
# raced for runs/by-sid: on 2026-10-20 two poller runs on 3e929a81/3d1d988a held the claims 21-22 min and
# PARKED (router rc=3) while the reconciler, placed, logged claim-held from 04:53. This lane now leaves
# such a sid alone for LR_POLLER_RECON_FIRST_S (600) from the record's detection (or from a WAIT_RESET
# eta once that has passed), then acts exactly as before: the fence and the run claim still arbitrate.
# A hook request the reconciler has not ingested yet gets LR_POLLER_RECON_INGEST_S (180).
# Off: $STATE/recon-first.off (takes effect next tick) or LR_POLLER_RECON_FIRST=off.
# Any read that fails ⇒ act as before (our own failure is "unknown", never a reason to hold a session).
LRP_RF_N=0; LRP_RF_SIDS=""
lrp_rf_note() { LRP_RF_N=$(( LRP_RF_N + 1 )); (( ${#LRP_RF_SIDS} < 72 )) && LRP_RF_SIDS="${LRP_RF_SIDS:+$LRP_RF_SIDS,}${1:0:8}"; return 0; }
lrp_recon_first() { # $1=sid $2=request file or "" → rc 0 DEFER this tick · rc 1 act as before
  local sid="$1" rq="${2:-}" root rec row term po esc pane org det eta now t0 g ing at both=0
  [[ "${LR_POLLER_RECON_FIRST:-on}" != off && ! -e "$STATE/recon-first.off" ]] || return 1
  (( LRP_FENCE )) || return 1
  root="$(_lr_recon_root)"
  [[ "$(tr -d '[:space:]' < "$root/mode" 2>/dev/null)" == act ]] || return 1
  lr_recon_live || return 1
  [[ -e "$STATE/autorecover.on" && -e "$root/autorecover.on" ]] && both=1
  g="${LR_POLLER_RECON_FIRST_S:-600}";   [[ "$g" =~ ^[0-9]+$ ]] || g=600
  ing="${LR_POLLER_RECON_INGEST_S:-180}"; [[ "$ing" =~ ^[0-9]+$ ]] || ing=180
  now="$(date +%s)"; rec="$root/sessions/$sid.json"
  if [[ ! -f "$rec" ]]; then                       # not ingested yet: hands-off scope only
    (( both )) && [[ -n "$rq" && -f "$rq" ]] || return 1
    at="$(jq -r '(.at // empty) | floor' "$rq" 2>/dev/null || true)"
    [[ "$at" =~ ^[0-9]+$ ]] || at="$(stat -f %m "$rq" 2>/dev/null || echo 0)"
    (( now - at < ing )) || return 1
    lrp_rf_note "$sid"; return 0
  fi
  row="$(jq -r '[(.terminal == null), (.plan_only == false), ((.escalated // false) | not), (.pane != null),
                 (.origin // ""), ((.timeline.detected // 0) | floor),
                 (if .substate == "WAIT_RESET" then ((.wait.eta // 0) | floor) else 0 end)]
                | map(tostring) | join(" ")' "$rec" 2>/dev/null)" || return 1
  read -r term po esc pane org det eta <<< "$row"
  [[ "$term $po $esc $pane" == "true true true true" ]] || return 1
  [[ "$org" == cc-lr ]] || (( both )) || return 1   # a stale non-cc-lr record after the switch is pulled
  [[ "$det" =~ ^[0-9]+$ && "$eta" =~ ^[0-9]+$ ]] || return 1
  t0="$det"; (( eta > t0 && now >= eta )) && t0="$eta"
  (( now - t0 < g )) || return 1
  lrp_rf_note "$sid"; return 0
}
```

The record fields the predicate reads are compact JSON written by `store.atomic_write_json` (`store.py:48-49`, `:82`;
tmp + rename, so a reader never sees half a file). They are `terminal`, `plan_only`, `escalated`, `pane`, `origin`,
`timeline.detected`, `substate` and `wait.eta` (`types.py:716-790`).

**A.2 Call sites.** Three places; nothing else changes.

1. **The hook request loop**, before `# ── STAY NEAR THE RESET` (`:1748`). This is after the drain-time stale revalidation
   (`:1627-1646`, so a recovered session's request still retires), after the `autorecover.on` gate (`:1660`), and after
   the shape and mode checks. It also comes before the post-reset wake (`:1769-1787`) and the per-account cap (`:1788`),
   so a deferred request spends no cap, no attempt and no claim:
   ```bash
     if (( _rq_hook == 1 )) && [[ -z "$_rq_husk" ]] && lrp_recon_first "$_rq_sid" "$_rq"; then
       continue   # the reconciler drives it this tick; the next tick re-asks
     fi
   ```
   A stranded husk (`_rq_husk`) is excluded on purpose: the reconciler opens no record for one (`__main__.py:256-259`).
2. **`reroute_parked`**, after the held-lead check (`:2465-2468`) and before the reset-stay check:
   `lrp_recon_first "$sid" "" && return 0`.
3. **§2 nudge arm**, immediately before `lrp_may_act "$sid" nudge || continue` (`:2814`):
   `lrp_recon_first "$sid" "" && continue`.
   - This closes the post-reset double wake. The reconciler's `WAIT_RESET` wake types C at eta + 120 + 0-60 s
     (`__main__.py:402-428`, `admit.py:88-94`). The poller's wake is at reset + 120 + 0-89 s (`:1771`), and §2's nudge
     comes at the first tick after the reset once the account has headroom (`:2808-2814`). Today only the run claim serializes them: the second wake can type into a session the first just
     started (**hypothesis**; no measured double-continue found in the 10-18 window I read).
   - Not added at the §2 **resume** arm (`:2867`). A session with no live pane is the poller's to respawn; the
     reconciler's in-place wake cannot type into a pane that does not exist.

**A.3 One summary line per tick**, next to `REROUTE-HELD` before `exit 0` (`:2959-2962`):
```bash
if (( LRP_RF_N > 0 )); then
  log "RECON-FIRST $LRP_RF_N limited session(s) left to the live hands-off reconciler, up to ${LR_POLLER_RECON_FIRST_S:-600}s each (sids: $LRP_RF_SIDS); this lane backs each one up after that"
fi
```

### Part B — the move lane lets go the moment a session turns limited (`scripts/limit-recover/lr-move-worker.sh`)

**B.1 Move the limit read above the first wait.** `limited_now` and `limited_stop` are defined at `:192-201`, but the W2
idle-wait loop runs at `:143-187`, so it cannot call them. Move both definitions to just after `aborted()` (`:134`), add the
re-check, and leave the existing call sites (`:202`, `:384`, `:448`) as they are:

```bash
limited_stop() {
  local next="Recover it: cc-lr recover ${SID:0:8}"
  # Hands-off on (both markers, recon.on): the hook's request and the reconciler's census already own it.
  if [ -e "$STATE/autorecover.on" ] && [ -e "${LR_RECON_ROOT:-$STATE/recon}/autorecover.on" ] && [ -e "$STATE/recon.on" ]; then
    next="Hands-off recovery is on, so the reconciler recovers it; watch it: cc-lr status ${SID:0:8}"
  fi
  finish NOTMOVED "became-limited: its last record is now a limit error, so it owes a turn this lane does not type; nothing touched. $next"
}
_mw_limit_at=$SECONDS
limit_recheck() { # every LR_MOVE_LIMIT_RECHECK_S (30) inside a wait: a limited session is released at once
  [ "${LR_MOVE_LIMIT_RECHECK:-on}" != off ] || return 0
  local every="${LR_MOVE_LIMIT_RECHECK_S:-30}"
  case "$every" in ''|*[!0-9]*) every=30 ;; esac
  [ $(( SECONDS - _mw_limit_at )) -ge "$every" ] || return 0
  _mw_limit_at=$SECONDS
  limited_now && limited_stop
}
```

**B.2 Calls.** Add `limit_recheck` right after `intent_recheck` in three loops:

- the W2 idle-wait loop (`:150`);
- `draft_gate` (`:274`);
- the W3 slot loop (`:378`).

`finish` already releases the claim, the slot and the `.slotwait` marker on every path (`:64-81`, trap `:83`).
`lr-move-lib.sh:309-311`'s summary parser picks the first `cc-lr <verb> …` from the reason. With hands-off on, the
requester's mail then reads `cc-lr status <sid8>` instead of telling them to act.

### Part C — honest status for a plan-only record (`scripts/limit-recover/lr_recon/report.py`)

Insert after the escalated branch (`report.py:160-161`), ahead of the `WAIT…` branch that prints "the reconciler
retries" (`:175-176`):

```python
    if rec.plan_only:
        # A7: nothing in this daemon retries a plan-only record (act.may_actuate refuses it); saying so
        # is the difference between an operator waiting and an operator acting (3e929a81, 2026-10-20).
        return (
            "plan-only: hands-off recovery is off for the reconciler (recon/autorecover.on absent), "
            "so it does not retry this; the poller lane moves it if autorecover.on is set, or run "
            "cc-lr recover %s" % rec.sid[:8]
        )
```

### Part D — the off switch never strands the reconciler's own half-done move (`scripts/limit-recover/lr_recon/act.py`)

**Ship only if T-D2 is red.** The operator was told that deleting `recon/autorecover.on` turns hands-off recovery off
(transcript `fd47f3fe`, 17:11:18Z). Here is why that could strand a move:

- `upsert` → `merge_origin` re-derives `plan_only` on every pass for a record whose session buckets into a record type
  (`__main__.py:344-373`, `census.py:345-349`).
- `may_actuate` then refuses **every** actuator, completion ones included (`act.py:456-457`). Measured at HEAD (§9 T-D1):
  B on an EXITED own move, R on an IN-FLIGHT one and C on a RELAUNCHED one all return `(False, 'plan-only')`.
- **Hypothesis:** a session in `TRANSPLANTED` (source still alive with its limit tail) re-buckets LIMITED, so pulling the
  switch then leaves a transplanted-but-never-relaunched session.

```python
def own_move_in_flight(rec: T.Record) -> bool:
    """A move THIS reconciler spawned (close.move_attempt, stamped at __main__._dispatch) and has not finished:
    past PRE-MOVE, or IN-FLIGHT in its relaunch gap. The zero-human switch stops new moves; it never strands
    one half done. A plan-only IN-FLIGHT record moved by another lane has no move_attempt and stays refused."""
    return rec.close.get("move_attempt") is not None and (
        rec.phase != "PRE-MOVE" or rec.substate == "IN-FLIGHT"
    )
...
    if rec.plan_only and not own_move_in_flight(rec):      # was: if rec.plan_only:
        return False, "plan-only"
```

`close.move_attempt` is stamped only when the reconciler spawns A, A-husk, B or R (`__main__.py:1312-1313`) and is never
cleared. A failed attempt back in `PRE-MOVE/PLANNED` therefore stays refused, so "no new moves" holds. Every other gate
still applies, including `hold_claim`.

## 7. Data and format changes

- **No schema change.** Part A reads existing record fields (it is read-only on the reconciler's tree).
- **New poller log lines:** `RECON-FIRST <n> … (sids: …)`, one per tick.
- **New optional switch file:** `~/.reso/limit-recover/recon-first.off`. Absent is the default (on).
- **New environment knobs:**
  - `LR_POLLER_RECON_FIRST` (on), `LR_POLLER_RECON_FIRST_S` (600), `LR_POLLER_RECON_INGEST_S` (180);
  - `LR_MOVE_LIMIT_RECHECK` (on), `LR_MOVE_LIMIT_RECHECK_S` (30).
- **Changed text:**
  - `became-limited` reasons when hands-off is on (the class token `became-limited:` is unchanged, so `lr-move-lib.sh`'s
    class parser is unaffected);
  - `next_action` for plan-only records.
- No new files on the live layer. `~/.claude/scripts/limit-recover/lr-reset-poller.sh` and `lr-move-worker.sh` are
  symlinks into the main checkout (measured, `ls -la`), so no `install.sh` link is needed.

## 8. Failure modes under permanent 15-40/core

None of the new gates reads load. Every bound is wall-clock.

| # | Failure | Handling |
|---|---|---|
| F1 | The reconciler is alive but never places the record (placer rc=124 every pass, `WAIT_SLOT` forever) | The poller defers ≤600 s from detection, then acts as today. Worst-case added rescue delay is ≈ 600 s + one poller tick. Measured tick spacing is 10.7 min (`grep 'TICK start' poller.log`, 13:30-17:41Z), so ≈ 21 min (estimated: sum) |
| F2 | The heartbeat goes stale under load | `lr_recon_live` is false, so the poller acts at once, as today. Measured now: `max_step_gap_s 30.3` in `recon/heartbeat`, pass gaps median 9.0 s / p90 13 s / max 36 s over 6 h at load1 198 (19.8/core) (`band.log` intervals; `sysctl vm.loadavg`). The fresh window is 180 s |
| F3 | jq or stat fails or is slow | `|| return 1`: act as before. Our own failure is "unknown", never a hold |
| F4 | A record is read mid-write | Writes are atomic (tmp + rename, `store.py:60-82`) |
| F5 | The reconciler runs under a lower `--mode` cap than `recon/mode` | It defers for nothing for ≤600 s, then backstops. The heartbeat carries no mode, so this is accepted; noted as risk R2 |
| F6 | The operator deletes `recon/autorecover.on` mid-cohort | Next tick, `both=0`, so the poller stops deferring hook-origin sids. Next reconciler pass, `plan_only` turns true, so no new reconciler moves. Part D lets the reconciler's own in-flight moves finish. The run claim covers the hand-over |
| F7 | Its `WAIT_RESET` wake fails (`wake_failed`) | The poller's backstop wake comes at eta + 600 s (+ tick) instead of eta + 120-210 s |
| F8 | A dead session (no pane) | `.pane == null` gives no deferral; the §2 resume arm is not wrapped |
| F9 | A request from a hook that fired before the reconciler ingests it | Deferred ≤180 s. Pass cadence is measured at 9-36 s, so ingest normally lands well inside that |
| F10 | The move worker's limit re-read is slow | One `tail -c 128K` + python per 30 s per waiting worker (`lr-lib.sh:174-199`). If the read fails, `limited_now` is false and the wait continues; there is no false stop |
| F11 | A deferral would exhaust the request | A deferral spends no attempt (`rq_record_attempt` is not reached) and takes no claim |

## 9. Test plan (a red-before control for every behaviour change)

**Measured red-before for Part A, already run.**

- File `/tmp/a7/redprobe/a7-recon-first-red.bats`, run as `TMPDIR=/tmp/a7/bt2 bats …`. It is hermetic: HOME is the test
  dir, lr-fleet, launchctl and osascript are stubbed, and the poller is run under `/bin/bash` 3.2. Output `/tmp/a7/bt2.out`:
  - `1..2`
  - `not ok 1 [post-fix expectation; RED at HEAD] …`, which printed:
    - `DISPATCHED: --one 52e35019-… --target auto --from-daemon --detach`
    - `lr-recon-fence: verdict=act sid=52e35019 reason=not-owned`
  - `ok 2 CONTROL: recon marker absent: the poller dispatches as before`
- So today the poller races a live hands-off reconciler that holds an open record 60 s old.

**Measured red-before for Parts C and D (gate), already run** (`python3 -B -s /tmp/a7/probe/p4.py|p5.py <worktree>/scripts/limit-recover`):

- `next_action` for a plan-only `WAIT_DATA` record returns `the reconciler retries`.
- `may_actuate` returns `(False, 'plan-only')` for B on EXITED, R on IN-FLIGHT and C on RELAUNCHED own moves, and for
  both controls.

**To build:**

| ID | Suite | Case | Before | After |
|---|---|---|---|---|
| T-A1 | new `tests/lr-reset-poller-recon-first.bats` (fixtures copied from `lr-reset-poller-requests.bats:21-104`, `:478-485`, `:539-545`, plus a `handsoff_live` helper as in the probe) | hands-off, live, open record detected 60 s ago: no `--one`, request stays, `attempts` unchanged, one `RECON-FIRST 1` line | RED (measured) | green |
| T-A2 | same | CONTROL, recon marker absent: dispatched | green | green |
| T-A3 | same | backstop: detected 700 s ago: dispatched | green | green (proves the bound) |
| T-A4 | same | heartbeat 3600 s old: dispatched | green | green |
| T-A5 | same | record terminal / `plan_only:true` / `escalated:true` / `pane:null` / mode `observe`: dispatched (5 sub-cases) | green | green |
| T-A6 | same | no record, request `at` now−30: deferred; `at` now−400: dispatched | RED / green | green / green |
| T-A7 | same | post-reset wake (`wake_rq`) with an open `WAIT_RESET` record, eta now−120: nothing typed; eta now−900: typed | RED / green | green / green |
| T-A8 | same | `reroute_parked` (`park_future` from `lr-recon-fence-callsites-poller.bats:151-157`) with an open record: no reroute dispatch | RED | green |
| T-A9 | same | §2 nudge (`park_ready` + `live_row`, `:158-176`) with an open `WAIT_RESET` record whose eta is 60 s past: nothing typed | RED | green |
| T-A10 | same | `LR_POLLER_RECON_FIRST=off`, and separately `recon-first.off`: dispatched | green | green |
| T-A11 | same | 3 deferred sids: exactly one `RECON-FIRST 3` line | RED | green |
| T-A12 | same | every tick runs `/bin/bash "$POLLER"` (the launchd interpreter, `com.reso.lr-reset-poller.plist` ProgramArguments) | — | — |
| T-B1 | `tests/lr-move-worker.bats` new 26 (template: test 21, `:373-393`) | one slot held, `LR_MOVE_SLOT_WAIT_S=45`, `LR_MOVE_LIMIT_RECHECK_S=0`; `await_stage slot-wait`; `limit_tail`: NOTMOVED `became-limited:` in seconds, never invoked, claim gone | RED (`slot-wait:` after 45 s) | green |
| T-B2 | same, new 27 | the same inside `draft_gate` (a `draft` row whose box keeps changing) | RED (`HELD:draft` at the wait end) | green |
| T-B3 | same, new 28 | the W2 idle wait under `WORKER_BASH=/bin/bash`: proves the moved definitions resolve before W2 (a "command not found" there is the failure) | RED | green |
| T-B4 | same, new 29 | hands-off markers + `recon.on` under `LR_STATE_DIR`: the reason contains `the reconciler recovers it` and `cc-lr status <sid8>`. Test 16 (`:276-283`) unchanged: no markers gives `cc-lr recover` | RED | green |
| T-C1 | `lr_recon/tests/test_report.py` | plan-only `WAIT_DATA`: `next_action` contains `plan-only` and `cc-lr recover 3e929a81`. CONTROL `plan_only=False`: `the reconciler retries` | RED (measured) | green |
| T-D1 | `lr_recon/tests/test_act.py` | the p5 matrix: own EXITED/B, IN-FLIGHT/R and RELAUNCHED/C pass the plan-only gate. CONTROLS fresh `PLANNED`/A, and another lane's IN-FLIGHT with no `move_attempt`, still return `plan-only` | RED (measured) | green |
| T-D2 | `lr_recon/tests/test_main.py` (harness `_flags`/`_pass`, `:700-722`) | an own move in `TRANSPLANTED` (close.move_attempt=1, `plan_only=False`, session still LIMITED on the source); `_flags(autorecover=True, recon_marker=False)`; one act pass: assert that the record's `plan_only` became True **and** that the row-12 A re-drive was refused `plan-only` | **Decides D:** RED, so ship D; GREEN, so the hazard is not reachable and D is dropped | — |

Suites that must stay green, with their `1..N` plan lines asserted (rule: a gate refusal is not a result):

- `lr-reset-poller-requests.bats`, `lr-recon-fence-callsites-poller.bats`, `lr-reset-poller-reroute.bats`,
  `lr-reset-poller-reroute-cap*.bats`, `lr-reset-poller-inplace.bats`, `lr-reset-poller-bash32.bats`;
- `lr-autorecover-drill.bats`, `lr-move-worker.bats`, `lr-move-worker-retry.bats`, `lr-move-summary-casualty.bats`;
- `python3 -m unittest discover lr_recon/tests`.

None of their fixtures creates `recon/autorecover.on` together with a fresh heartbeat (`grep -l` over `tests/`), so
Part A is inert in them.

## 10. Rollout, kill switches, operator steps

1. **Build.** Parts A, B and C, plus D only if T-D2 is red, go in one branch with the tests above. Land through `/ship`
   unwrapped, then run the touched suites yourself: a LANDED verdict is not a tested one.
2. **Live.**
   - **Parts A and B** take effect at the poller's next tick and the next move worker. Both are symlinked from the main
     checkout and launchd starts the poller fresh every 600 s (`StartInterval 600`), so there is no reload and no operator act.
   - **Parts C and D** load at the reconciler's next restart. Per A6, do not restart mid-cohort. The operator, or a session
     the operator asks, runs at a quiet moment:
     `~/.reso/limit-recover/design-v2/lr-restart-at-boundary.sh --confirm reconciler`.
     It waits until no `lr-recon-act` child is running, then kickstarts and verifies a new pid and a progressing heartbeat.
3. **Verify at the next wall**, which will be the first hands-off cohort:
   - `poller.log` has `RECON-FIRST` lines, and no `REQUEST <sid> — dispatching` for a sid within 600 s of its record's detection;
   - `recon/events.jsonl` has no `claim-held … (a bash lane)` for those sids;
   - `cc-lr status --cohort <id>` reaches ENGAGED;
   - `RECON-FIRST` sids that later appear in `REQUEST … dispatching` are the backstop working, so count them.
4. **Kill switches**, each taking effect without a reload:
   - Part A: `touch ~/.reso/limit-recover/recon-first.off` (next tick).
   - Part B: `LR_MOVE_LIMIT_RECHECK=off` in the move batch's environment.
   - The whole hands-off scope: `rm ~/.reso/limit-recover/recon/autorecover.on`. This is the operator's documented switch;
     Part A stops deferring non-cc-lr sids at once.
   - Rollback: revert the commit. There is no state migration to undo.
5. **Operator steps required before the build:** none. The ruling was made at 17:10:31Z.

## 11. Estimated size

Estimated by counting the sketches above and the fixture reuse.

| Part | Code (LOC) | Tests (LOC) |
|---|---|---|
| A | ~55 | ~170 |
| B | ~20 | ~60 |
| C | ~8 | ~20 |
| D | ~15 | ~60 |
| **Total** | **~100** | **~310** |

The total is about **400 LOC**.

## 12. Dependencies on the other items

None is a hard prerequisite. The soft links:

| Item | Link |
|---|---|
| B3-deadline-override | Keep `LR_POLLER_RECON_FIRST_S` ≥ B3's `W_soft` (+ `P_max`). Otherwise the poller's backstop fires in the same minute as the reconciler's deadline lane, and the run claim then decides by chance. With `W_soft`=600, 600 is acceptable; raise to ~780 if B3 lands `P_max`=3 min |
| B1-load-harness | Its fault matrix already lists "a member that turns limited while queued in the move lane" (REPORT §5 step 4). That is this item's end-to-end case under load |
| A6-restart-safety | Parts C and D load only at a reconciler restart; use the boundary script, never mid-cohort |
| G2-self-recovery | A third hands-off actor. When built, it must take its sid's run claim before acting, and the A predicate must defer to a live self-worker. Gap-2 already proposes skipping the hook's ARM 2 while self-recover is on |
| D2-warning-band-shedding | A consumer: shedding idle sessions through the move lane makes "turned limited while queued" more frequent ("2 of the 4 idle sessions here started turns and walled", REPORT §4 D2), so Part B is effectively its prerequisite |
| B6-telemetry | `RECON-FIRST` counts and backstop hand-overs are telemetry B6 can graph |
| B2-bounded-pass | The 180 s ingest grace assumes the passes measured today (9-36 s). If B2 is not built and passes stretch to minutes, raise `LR_POLLER_RECON_INGEST_S` |
| Others (B4, B5, B7, B8, C1, C2, D1) | No interaction |

## 13. Deviations and caveats

- **Deviation.** I ran one `launchctl print gui/$(id -u)/com.reso.lr-reconciler | grep -i -E 'LR_IDLE|LR_RECON'`. It is a
  read-only query, but the brief said never to run launchctl. It changed nothing. The same fact was then re-read from the
  plist file (`grep -c EnvironmentVariables` => 0).
- **Scratch writes.** All were under `/tmp/a7/`:
  - analysis scripts;
  - the red-before probe and its bats temp tree under `TMPDIR=/tmp/a7/bt2`;
  - `tempfile` dirs from p5.

  The probe's poller ran with `HOME` inside that tree, with stubbed lr-fleet, launchctl and osascript.
- **Confounding.** The October lane comparison mixes eras: both lanes ran at priority 20, and the reconciler's records are
  the hard cohorts (10-13, 10-18, 10-20). It supports "neither lane is clearly better per attempt" and nothing stronger.
- **The first hands-off cohort has not happened yet.** D1.13 asked for a review of the first real unattended move. Part A
  changes the poller just before it, so keep `recon-first.off` at hand.

## Review — efficacy-under-permanent-load

Reviewer: adversarial worker, 2026-10-20, read-only. The question: at 15-40/core, with every lane at PRI 31, does this
design bound recovery time? Does any new wait, bound or gate assume that load falls?

The only writes were under `/tmp/a7rev/` (a re-run of the author's probe, plus a predicate simulation) and this section.

**Verdict: NEEDS-CHANGES. Adjusted conviction: 55%** (was 70%).

- No new gate reads load. Part A's predicate reads only `recon/mode`, the two markers, the heartbeat, the record and
  the request's mtime. Part B adds a bounded transcript read and no wait.
- Part A has two problems:
  - It can defer **without bound** for one population.
  - Its claimed benefit is not shown for the incident it cites.
- Parts B, C and D are sound under this lens.

### What I verified (holds)

- **The red probe reproduces.** `TMPDIR=/tmp/a7rev/bt bats /tmp/a7/redprobe/a7-recon-first-red.bats` => `not ok 1 …
  DISPATCHED: --one 52e35019… lr-recon-fence: verdict=act sid=52e35019 reason=not-owned` and `ok 2 CONTROL`.
- **Cited lines match HEAD 28b25a119:**
  - poller `:166-180`, `:1660`, `:1748`, `:1769-1787`, `:1788`, `:1798`, `:2465-2468`, `:2814`;
  - fence `:167-216`, `lr_recon_live` `:319-330`;
  - `__main__.py:225-231`, `:1043-1045`, `:1058-1080`, `:402-438`;
  - `census.py:345-349`, `:440`;
  - `act.py:456-461`, `:493-526`;
  - worker `:134`, `:150`, `:192-202`, `:274`, `:378`, `:384`, `:448`;
  - `report.py:160-176`.
- **`timeline.detected` is write-once per record:**
  - it is set only in `new_record` (`census.py:440`); `upsert` of an open record never touches it (`census.py:459-481`);
  - a closed record is not reopened for the same death (`__main__.py:315`, `census.handled_death`).
  - So the DETECTED/WAIT_SLOT/WAIT_DATA branch of A is bounded at det+g+one tick.
- **After PLANNED the poller is fenced for the record's whole life.**
  - `owned/<sid>` and the run claim are released only at terminal (`__main__.py:1546-1557`).
  - So A only matters before the first placement, and for WAIT_RESET records, which are never owned.
- **Tick spacing** (measured: `grep 'TICK start' poller.log | tail -40` intervals) is median 643 s, max 829 s. That
  matches the 10.7 min in F1.

### Refutations and gaps

**R1 (HIGH): the WAIT_RESET branch re-arms, so the backstop is not bounded by g.**

- How the re-arm works:
  - `plan.movers` re-offers a passed limited WAIT_RESET every `REOFFER_AFTER_S` = 900 s (`plan.py:205`, `:233-242`).
  - `plan.apply` turns `--place`'s "stay" into `wait.eta = now` (`plan.py:427-432`). `settle.py:1100-1107` does the
    same.
  - So a stay record's eta moves forward every ~930 s, and each move restarts A's `t0 = eta` window.
- `wake_failed` makes this worse:
  - The reconciler never retypes a record carrying it (`__main__.py:430`; `settle.py:174-176`, "paged once and never
    retyped").
  - rc 2, "the composer could not be read", is a load-shaped failure.
  - So the reconciler has stopped driving the session, while the poller keeps deferring to it.
- Simulation (estimated): the design's function, verbatim, under `/bin/bash` 3.2 (`/tmp/a7rev/pred/t.sh`), with ticks
  every 643 s over 2 h and the eta re-placed every 930 s:
  - `g=600 => defer=7 act=5`;
  - `g=930 => defer=12 act=0` (never acts).
- Consequences:
  - F7's "eta + 600 s (+ tick)" is false for this population.
  - §12 advises raising g to ~780 for B3, and `g` has no upper clamp (`[[ "$g" =~ ^[0-9]+$ ]]` only). That walks the knob
    toward the unbounded case.
- It is a hypothesis that the live placer returns "stay" repeatedly for a still-limited session after its reset. The
  code path allows it.

**R2 (HIGH): the cited benefit does not follow from the design.**

- The 10-20 dispatches would not have been deferred:
  - 3d1d988a was detected 03:23:43Z and dispatched 04:42:05Z (78 min later).
  - 3e929a81 was detected 03:15:54Z and dispatched 04:45:01Z (89 min later).
  - Both had been plan-only until the `refire by=cc-lr` at 04:38:45Z (`events.jsonl` t=1792471125).
  - With `t0 = detected`, the predicate returns act. Simulated case P => `ACT`.
- More generally, A helps only when detect→PLANNED is under g. Measured
  (`recon/sessions/*.json`, `timeline.planned - timeline.detected`, acting cc-lr records, PRI-20 era):
  - Planning took more than 600 s in **3 of 7 cohorts**: 1329 s, 2142 s (WAIT_SLOT) and 5730 s (HOLD-BGWORK).
  - The other four took 69-474 s.
- At PRI 31 this latency is unmeasured: `grep '"ev":"place"' events.jsonl` has 0 rows after 07:23Z. In the PRI-20 era,
  places at load1 ≥ 150 were 15 of 48 rc=124, with a median of 71.9 s against a 120 s cap (`plan.py:55`, `:358-364`).
- So "Removes the 11-18 min claim block" (§4 O2) is unsupported. The honest claim: it removes the race only when the
  reconciler places within g.

**R3 (MED): the backstop brings back the claim block exactly where it fires.**

- After g the poller dispatches lr-fleet, which holds `runs/by-sid` for its whole run.
- While that claim is held, the reconciler cannot even write `owned/<sid>`: `take_ownership` takes the claim first and
  writes nothing on `held` (`store.py:567-569`).
- Measured on 10-20 (`fleet/one-20261020T044205Z-3d1d988a`):
  - the run started 04:42:05;
  - `rank.timing` shows its first router call at 05:00:51 (rc 3 after 34 s), then 05:01:34 (rc 3 after 42 s);
  - it ended PARKED at 05:04:09, and the reconciler had been placed since 04:53.
- The backstop fires only when the reconciler is slow to place, which under load means a slow router. lr-fleet asks
  the same router. So the backstop is likely the weaker driver, and it holds the claim. (That was PRI 20; it is a
  hypothesis that it holds at PRI 31.)

**R4 (MED): the deferral keeps going for records the reconciler will not drive.**

- A `PARKED-REBOOT` limited record is refused by `may_actuate` (`act.py:460-461`) but passes the predicate.
- So does a `wake_failed` record (R1).

**R5 (LOW): smaller defects.**

- **F2's freshness evidence comes from passes with no cohort.** In a cohort, one step can hold a 120 s `--place`, so
  the margin to the 180 s fence is about 60 s. When it fails, A fails open, which is safe.
- **F3 is wrong that a slow read leads to act.** There is no timeout, so a slow jq just blocks.
- **The tick does per-sid forks.** `lr_recon_live`, `sysctl` and `tr` run for every sid. That lengthens the tick,
  which sets the backstop's period.
- **T-A6 tests a field real requests do not have.** It uses `.at`, but `stop-failure-marker.sh:516-523` writes `ts`
  and no `at`, so the real path is `stat -f %m`.
- **An empty `.origin` makes `read` mis-split the row.** It fails open (simulated case E => `ACT`).
- **§12 contradicts itself.** It says "≥ W_soft + P_max" and then "600 is acceptable".
- **Parts C and D may never load.** `lr-restart-at-boundary.sh:30-36` gives up after 30 min mid-act, so under
  continuous cohorts they can wait indefinitely. They are not on the recovery path; just do not tie A or B to that
  restart.

### Required changes

1. **Make A's clock owned by the poller and write-once.**
   - The poller stamps `$STATE/recon-first/<sid>` (with `set -C`) on the first tick it would defer an actionable record,
     and a second stamp on the first tick that sees a passed eta.
   - It defers only while `now - stamp < g`. It never reads a newer `wait.eta` after stamping.
   - It clears the stamps when the request or parked record retires.
   - This bounds deferral to at most 2·g plus a tick per incident, whatever the reconciler rewrites. It also gives a
     promoted (plan-only → acting) record a fresh window (R1, R2).
   - Clamp `g` (and `ing`) to at most 900 in code.
2. **Exclude records the reconciler has stopped driving:**
   - `(.close.wake_failed // "") != ""`;
   - `.substate == "PARKED-REBOOT"`;
   - and, to be safe, `.kind != "limited"` (R4).
3. **Restate §0, §4 O2 and §5 A.**
   - The 10-20 race would not have been deferred.
   - Benefit exists only while detect→PLANNED < g. In the PRI-20 era that failed in 3 of 7 cohorts.
   - Add the PRI-31 detect→PLANNED distribution to the rollout §10.3 verify step, or to B1's harness, as the acceptance
     number for g.
4. **Bound the backstop's claim block (R3). Either:**
   - (a) under `--from-daemon`, `lr-fleet --one` re-reads `recon/sessions/<sid>.json` just before its router call. If
     the record is open, acting and PLANNED with a `target_acct`, it ends PARKED ("reconciler placed"), which
     `rq_refund_park` already refunds; or
   - (b) the doc states this as a residual, and §10.3 counts backstop runs with their claim-hold wall and PARKED rate,
     with `recon-first.off` as the response.
5. **Add tests:**
   - T-A13: a stay re-offer loop (eta rewritten every 930 s) yields a total deferral of at most 2·g from the first stamp;
   - T-A14: `wake_failed` → dispatched;
   - T-A15: `PARKED-REBOOT` → dispatched;
   - T-A16: `g=5000` is clamped;
   - T-A17: a promoted record gets one fresh bounded window.
   - Rewrite T-A6 to use a hook-shaped request with no `.at` and a set mtime.
6. **Compute the per-tick constants once per tick:** mode, `both`, and `lr_recon_live`.
7. **Make the jq row mis-split-proof:** `@tsv`, or a non-empty placeholder for origin.
8. **Fix the §12 B3 guidance.**
   - With change 1, g only trades backstop latency.
   - Without change 1, g must stay below `REOFFER_AFTER_S`.
9. **Correct the F2 and F3 wording.**

### Parts B, C and D under this lens

- **B is sound.**
  - `limit_recheck` adds no wait. It runs one bounded `tail -c 128K` + python per 30 s per waiting worker
    (`lr-lib.sh:174-199`), and only shortens claim holds.
  - Nit: the summary's "up to 600 s" understates the case. W2's budget is `until_idle_s` (`:143`), and the draft wait is
    `max(UNTIL, 600)` (`:256`). W2 already exits for a limited session that reads at rest, so this is wording only.
- **C and D** have no load interaction.

## Review — correctness-and-safety

Reviewer: an adversarial worker agent, 2026-10-20. The review was read-only.

- **Lens.** Could A7, as designed, strand a session, double-drive one, lose a draft, split-brain, or break an invariant or
  an existing test?
- **Code.** Every cite was re-read in this worktree at `28b25a119`.
- **Scratch writes.** All are under `/tmp/a7review/`: a verbatim copy of the Part A sketch (`sketch.sh`) and a case runner
  (`run-cases.sh`). Nothing live was touched.

**Verdict: NEEDS-CHANGES. Adjusted conviction 55%** (the design says 70%).

- Part A's direction is right. It only removes poller actions, so it cannot add a second driver.
- **Part A.** As specified, it leaves the measured race open for any sid that has been recovered before, and that
  includes the incident sid itself.
- **Part C.** As placed, it would make a live status line false.
- **Part D.** It targets the smaller of two strands behind the off switch, and it misses the larger one.

### R.1 What holds (verified)

- **Cites.** These resolve at HEAD, give or take a line:
  - `zero_human` `__main__.py:225-231`; `merge_origin` `census.py:345-349`; the upsert re-derive at `:459`;
  - `_own_and_charge` at `:1058`, with the PLANNED-only gate at `:1065`; the placement drop at `:1042-1045`;
  - fence `not-owned` at `lr-recon-fence.sh:185`; `hold_claim` at `act.py:493-523`; the plan-only gate at `act.py:456`;
  - `close.move_attempt` is stamped only at `__main__.py:1313`, read only at `:1291` and `settle.py:910`, and never
    cleared (grep);
  - the poller anchors `:1660`, `:1748`, `:1769-1787`, `:1788`, `:1798`, `:2465`, `:2814`, `:2867`, `:2960-2962`;
  - the move-worker anchors `:134`, `:143-187`, `:192-202`, `:274`, `:376-381`, `:384`, `:448`.
- **The red-befores reproduce.**
  - `python3 -B -s /tmp/a7/probe/p5.py <wt>/scripts/limit-recover` => all five `(False, 'plan-only')`.
  - `p4.py` => `the reconciler retries` for both `plan_only` values.
  - `/tmp/a7/bt2.out` shows `not ok 1` with `DISPATCHED: --one 52e35019…` and `reason=not-owned`, and `ok 2`.
- **Part A cannot double-drive.**
  - Every call site sits before `lrp_may_act`, `run_claim_take` and `rq_record_attempt` (`lr-reset-poller.sh:1798`,
    `:1816`, `:1886`). A deferral therefore takes no launch lock, no run claim and no attempt, and writes nothing.
  - At the backstop instant the arbiter is still Wave G. `take_ownership` takes the run claim *before* it writes
    `owned/<sid>` (`store.py:567-573`), and `hold_claim` refuses while the poller holds the claim.
- **No draft risk.**
  - No part types into a composer or clears one.
  - Part B's new exits fire inside wait loops, before any `cc_tui_clear` (the clears are at `lr-move-worker.sh:247` and
    `:283`, both after the `draft_gate` loop).
  - `finish` releases the claim, the slot and `.slotwait` on every path (`:64-81`, trap `:83`).
- **The sketch is clean.**
  - `/bin/bash -n /tmp/a7review/sketch.sh` under bash 3.2.57 => it parses.
  - `shellcheck /tmp/a7review/sketch.sh` (0.11.0, run bare as the land gate runs it) => no findings.
- **Existing suites stay inert.**
  - No `tests/*.bats` writes `recon/autorecover.on` (grep => none).
  - The only poller suite that writes a recon record writes a terminal one (`lr-reset-poller-reroute-cap-clear.bats:26`).
  - `lr_recon/tests/test_report.py`'s `rec()` defaults `plan_only=False` (`:26-40`), so Part C does not move its asserts.
- **The stay rules agree.** The census `STAY` (15 min, `census.py:243`) equals the poller's `RQ_STAY_S` (900 s).

### R.2 Defects

**F-A1 (blocking).** The ingest grace covers only a sid with *no* record file. A sid recovered before goes straight to
"act", and so the race survives. The chain:

- Measured: `recon/sessions/` keeps terminal records for up to 20 days. A python read of the live dir gave 138 records,
  134 terminal, with terminal age median 14.7 d and max 20.0 d.
- So for a repeat-capped sid, `[[ ! -f "$rec" ]]` is false, and the predicate reads `.terminal == null` as false and
  returns 1 (act).
- Measured: 22 of 157 reconciler record_ids (14%) were opened over an existing file for the same sid (`events.jsonl{,.1}`,
  grouped by sid). One of them is **3e929a81 (pane 20)**, which has records `next2-7d…` (10-17), `next4-7d…` (10-18) and
  `next3-7d…` (10-20).
- The window is the common case, not a corner:
  - the hook kickstarts the poller the moment it writes a request (`hooks/stop-failure-marker.sh:548-551`);
  - measured, the request loop is reached 0-62 s after `TICK start` (awk over `poller.log`);
  - the reconciler ingests on its next pass, measured at 9-36 s.
- Measured with `/bin/bash /tmp/a7review/run-cases.sh`:
  - case 1, no record file and a fresh request: rc 0 (defer);
  - case 2, an earlier death's terminal record on file and the same fresh request: **rc 1 (act now)**.
- **Fix.** Apply the ingest grace whenever there is no *open* record and the request is newer than the record. Use
  `terminal.at` < the request's own time, or `.close.death` differing from the request's `death_uuid`. Add this as test
  T-A6b.

**F-A2.** Anchor the bound on the request as well as the record.

- `t0` comes only from `timeline.detected` or the eta. A record that closes and reopens gets a fresh `detected`
  (`census.py:440`).
- Hypothesis, not observed: if a sid's records churn faster than 600 s, the poller defers every tick and the bound never
  ends.
- **Fix.** For call site 1, use `t0 = min(record t0, the request's time)`. The hook writes `ts` (ISO) once per death
  (`stop-failure-marker.sh:516-523`, latched per `death_uuid` at `:495-498`), and `rq_update`'s jq rewrites keep it. Then
  "every hook request is dispatched within `LR_POLLER_RECON_FIRST_S` + one tick of its death" holds by construction, which
  is the premise's guarantee.

**F-A3.** The fixtures do not match the production request.

- The probe writes `"at":$NOW` (`/tmp/a7/redprobe/a7-recon-first-red.bats`, `hook_rq`). The hook never writes `at`: its
  keys are `sid … ts … death_uuid` (`stop-failure-marker.sh:521-524`).
- In production the sketch's `.at` read is therefore dead, and the no-record branch always runs on `stat -f %m`.
- **Fix.** T-A1 and T-A6 must write the hook's real shape and age the file with `touch -t`. Otherwise the 400-s case
  passes on a field production never has.

**F-A4.** The mode read leaks to stderr.

- `tr … < "$root/mode" 2>/dev/null` applies the `<` before `2>/dev/null`, so a missing or unreadable `mode` prints to the
  poller's stderr.
- Measured on my first run: `sketch.sh: line 14: /tmp/x/recon/mode: Not a directory`.
- **Fix.** Use `{ tr -d '[:space:]' < "$root/mode"; } 2>/dev/null`, the brace form the hook itself calls load-bearing
  (`stop-failure-marker.sh:512-515`).

**F-A5.** Scope the predicate to what the reconciler will actually drive.

- Add `.kind == "limited"`.
- Refuse `.substate == "PARKED-REBOOT"`; `may_actuate` refuses it (`act.py:460`).
- Take the eta for `HELD:team` as well as `WAIT_RESET`. These are the reconciler's `WAKE_SUBSTATES`
  (`__main__.py:405`), so the §2 nudge for a held lead would otherwise not get the eta window.
- At call site 1, require `_rq_by == stop-failure-marker`. A `stranded-husk` request whose revalidation returns rc 1
  (not husk) reaches the no-record branch for a sid the reconciler deliberately never ingests (`__main__.py:256-259`).

**F-A6.** The summary line can lie or go missing.

- **Dedupe by sid.** One sid can be deferred at both call site 1 and call site 3 in one tick (a hook request plus a
  parked record), so T-A11's count assertion is fragile.
- **Log the request-lane count beside `RECON-OWNED` (`:1911-1913`).** The end-of-tick line at `:2960` is skipped by the
  `exit 0` at `:2379` (lr-select missing).

**F-B1 (Part B, cost under permanent load).** Cache the transcript path that `limited_now` resolves.

- F10's "one tail + python per 30 s" holds only on the cwd-slug fast path.
- A miss globs `"$SRC_CFG"/projects/*/` (`lr-move-worker.sh:198`), about 18,200 dirs (test 16b's own comment). The
  recheck repeats that up to 20 times in a 600 s wait, per waiting worker.

**F-B2.** "The reconciler recovers it" is a promise, and it should be checked before it is printed.

- Also require `recon/mode` = `act` and `lr_recon_live`. The fence lib is already sourced at `:43`.
- Otherwise keep `cc-lr recover`. That is the same lie class Part C fixes.

**F-B3 (advisory).** One `limited_now` read right before W5, after `intent_ok` at `:394`. The window from slot to
actuator still has no read, and Part B is the natural place to close it.

**F-C1 (blocking for C).** The insertion point overrides `_NEXT` (`report.py:163`).

- Measured: a plan-only fan-out `PARKED-REBOOT` record's `next_action` today is `boot-resume relaunches it in resume
  mode; in page mode, by hand`.
- With C inserted after the escalated branch, it would instead say "hands-off recovery is off (recon/autorecover.on
  absent) … the poller lane moves it … or run cc-lr recover".
- That is false three times over for the 4 live open records:
  - the marker has been present since 17:10Z; those records are stale because `merge_origin` runs only on upsert;
  - boot-resume owns them;
  - idle records are not the poller's.
- `test_report.py:362-369` pins the current text only because its fixture is `plan_only=False`.
- **Fix:**
  - put C after the `_NEXT` lookup and the `HELD:team` branch, limited to `kind == "limited"`;
  - do not assert that the marker is absent (say "opened while hands-off recovery was off");
  - when Part D ships, word an own-move-in-flight record as "finishing its own move, then stops".

**F-D1 (blocking for the off-switch claim; the defect predates A7 but is inside its scope).** The plan-only flip strands
every PLANNED record, not only half-done moves. The code path:

- `owned/<sid>` and the run claim are released only for **terminal** records (`_release_terminal`, `__main__.py:1545-1558`).
- `_own_and_charge` skips plan-only records (`:1065`).
- `PHASE_DEADLINE_S` is defined at `types.py:140` and read nowhere (grep over `scripts/limit-recover` => that one line).

What follows when the operator deletes `recon/autorecover.on` mid-cohort:

- Every record in `PRE-MOVE/PLANNED`, or in any state D still refuses, keeps both `owned/<sid>` and the claim.
- The poller's fence reads `heartbeat-fresh` and defers.
- `run_claim_take` sees a live `lr-reconciler` holder.
- So no lane drives the session until its own reset closes the record. F6's "the run claim covers the hand-over" is false
  for these records.
- Measured: the code path. Hypothesis: how long the strand lasts.

**Fix.** Add a hand-over step. An open `plan_only` record that is not `own_move_in_flight` and holds `owned/<sid>` for its
own record_id releases the fence and the claim, with a `release plan-only` event. New test T-D3: a PLANNED record holds
`owned/<sid>`; the marker is removed; after one act pass, `owned/<sid>` and the claim are gone, and the bash fence reads
`not-owned`.

**F-D2.** `own_move_in_flight` is too broad.

- `phase != "PRE-MOVE"` also admits:
  - `TARGET-LIMITED`, whose action is `A` (`phase.py:93`), i.e. a hop, a *new* move from the target (`settle.new_attempt`,
    `settle.py:586-626`);
  - the `live_watcher` case, where `_derive` skips the hop branch and leaves `A` in `ctx.actions` (`__main__.py:931-941`,
    `:868`).
- **Fix:**
  - use an explicit (phase, actuator) allowlist: TRANSPLANTED/A or R (the row-12 re-drive to the same target),
    EXITED/B, HUSK-RETIRED/A-husk or UNCONFIRM, RELAUNCHED/C, TARGET-TRANSIENT/C-retry, PANE-GONE/R, PRE-MOVE IN-FLIGHT/R;
  - require `close.move_attempt == rec.attempt`, not `is not None`;
  - add TARGET-LIMITED/A and TARGET-AUTH as refused controls in T-D1.

**F-D3.** T-D2 tests one phase, and a green result there would wrongly drop D.

- A `RELAUNCHED/UNPROMPTED` session still sits on its copied limit tail. It therefore buckets LIMITED
  (`census.py:183`, `:247`), is upserted, and flips plan-only.
- **Fix.** Make T-D2 a matrix over TRANSPLANTED, RELAUNCHED/UNPROMPTED, PRE-MOVE IN-FLIGHT and PLANNED (the last one is
  F-D1's case). Ship D if any case is red.

**Note for the rollout text (§10).** With D, `recon/autorecover.on` means "no new moves", not "stop". The hard stop stays
`recon.on` or `recon/mode`, which `may_actuate` checks before plan-only (`act.py:453-455`). Say so wherever the operator is
told how to turn hands-off off.

### R.3 Residual risks accepted (no change required)

- **A second wake at the backstop edge.**
  - The poller's §2 nudge can still type at eta + 600 s into a session whose reconciler C turn has no assistant record
    yet. `nudge_in_place`'s guard is `lr_engaged_after` (`lr-reset-poller.sh:1173`).
  - This predates A7, and A7 shrinks it.
- **Tail members of a large cohort.**
  - Members still unplaced at 600 s race exactly as today, so the claim arbitrates.
  - Placement is the only latency that counts here: admission pacing runs after `owned/<sid>` is written, so the fence
    covers it.
- **Fork cost.** About 9 forks per deferred sid per tick (`lr_recon_live` is re-run per sid). Optional: compute `mode`,
  `live` and `both` once per tick.
