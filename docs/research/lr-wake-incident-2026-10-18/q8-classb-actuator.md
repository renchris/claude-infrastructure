# Q8: why the class-B defaults did not fire at 05:00Z

Answer to REPORT.md §5 Q8. This was a read-only investigation. Code citations are at 2a636f1b8 (this worktree). That commit is byte-identical to `main` and to the deployed checkout `~/Development/claude-infrastructure`, which `~/.claude/scripts/autonomy-sweep.sh` and `~/.claude/bin/cc-decide` symlink to.

## Answer

**It is a bug, not a design choice. Conviction: 95%.**

- **The design says the default fires at the deadline:**
  - `bin/cc-decide:15-17`: "the default FIRES at the deadline (async early-veto, never a sync approval)".
  - `docs/plans/ORCHESTRATOR_DESK_24X7_PLAN.md:88` lists it as an acceptance criterion: "class-B default fires at veto_deadline".
  - No document calls the veto window advisory.
- **What actually happened.** The actuator is loaded and it ran. It is starved by where it sits in the sweep.
  - Between 05:00Z and 17:13Z, `com.chrisren.autonomy-sweep` started **40 ticks**.
  - **39 of them ended themselves early**, at the self-bound (`sweep_yield`, 400 s), *before* the checkpoint `2-expire-sweep`. That checkpoint guards the class-B actuator (`scripts/autonomy-sweep.sh:1185-1233`).
  - The first phase alone (strand rung, config parity and cloud return) cost **307–1373 s, median 695 s**, against the whole 400 s budget.
- **The 17:13Z firing was not done by hand. The actuator did it, 12 h 13 min late.**
  - The tick that launchd started at about 17:06:21Z reached `2-expire-sweep` at `cumulative_s: 399`. That is **one second** under the bound.
  - In that tick, `cc-decide expire-sweep` moved all three packets to `expired-actioned` at 17:13:00–02Z.
  - REPORT.md:415 ("actioned by hand at 17:13Z") should be corrected.
- **The code already admits this.** `scripts/autonomy-sweep.sh:574-577`: "§2, §2b, §2b-i..vi, §2e, §2f and §3 are STILL starved … Hoisting one block cures one block; the general repair … is filed."
  - The filed item, `36ce331197ce`, was closed automatically on 2026-09-17 by a falsifier that tests a *different* arm (`unfired-briefs` rows). It was closed on a proxy reading, and §2 stayed starved.
- **This is not a one-off.**
  - The same starvation delayed `103f40b25f01` by 7.6 h on 10-11/12: 18 self-bounds before §2 in that window.
  - The packet store shows fire lags of 2.6 h, 4.6 h, 7.6 h and 3.1 h on earlier packets.
- **Impact on 10-18 was cosmetic only.** All three defaults were `default_effect: "no-change"`, so firing them actuates nothing.
  - The damage was the 12 h false "auto-fire ≤24h" readout, and a desk that was never told.
  - A `change` default would have had its backlog item delayed by the same 12 h.

## Evidence

### 1. The actuator, and how it is scheduled

| Piece | Where | What it does |
|---|---|---|
| The verb | `bin/cc-decide:499-526` (`cmd_expire_sweep`), dispatched at `:535` | Takes each packet with class B, status open and `veto_deadline < now`, and changes its status to `expired-actioned`. Logs one IDL row per packet (`:523`). Prints `fired\t<id>\t<proj>\t<effect>\t<default>`. Executes nothing itself. |
| The caller and actuator | `scripts/autonomy-sweep.sh:1185` (`sweep_yield 2-expire-sweep`), then `:1187-1233` | Reads the `fired` lines. For `change` defaults it runs `cc-backlog add --dod-ref decision:<id>`. For `no-change` defaults it only counts them. |
| The scheduler | `~/Library/LaunchAgents/com.chrisren.autonomy-sweep.plist` (identical to `launchd/com.chrisren.autonomy-sweep.plist`, `diff` rc 0) | `StartInterval 300`, `RunAtLoad false`. Runs `taskpolicy -c utility ~/.claude/scripts/autonomy-sweep.sh`. |
| The gate that starves it | `scripts/autonomy-sweep.sh:378-380`, `:423-451` | `SWEEP_SELF_BOUND_S=400`. At each checkpoint, if `now - T0 >= 400`, it logs `self-bound {stopped_before}` and exits 0. The phases are always run in the same order, so anything below the cut never runs. |

Nothing else fires class-B defaults. `scripts/ship-land.sh:650` only mentions expire-sweep in a comment. All other hits are tests.

```
$ launchctl list | grep -i -E "decide|autonomy"
68219	0	com.chrisren.autonomy-sweep
$ launchctl print gui/501/com.chrisren.autonomy-sweep
	state = running · runs = 2034 · last exit code = 0 · run interval = 300 seconds
```

### 2. The packets

```
$ jq … ~/.claude/autonomy/decisions/{46676a666732,716598eca43f,de3b237d964e}.json
id            class status            veto_deadline         default     default_effect  resolved
46676a666732  B     expired-actioned  2026-10-18T05:00:00Z  "no change" no-change       2026-10-18T17:13:00Z
716598eca43f  B     expired-actioned  2026-10-18T05:00:00Z  "no change" no-change       2026-10-18T17:13:00Z
de3b237d964e  B     expired-actioned  2026-10-18T05:00:00Z  "no change" no-change       2026-10-18T17:13:00Z
```

- All three were created at 2026-10-11T05:02:44Z by session c8e66cb3. Each cites the receipt `docs/research/proactive-parallel-ops-2026-10-11/REPORT.md`.
- `expired-actioned` is the status that only `cmd_expire_sweep` writes (`bin/cc-decide:519`). The `action` verb writes `actioned`.
- The file mtimes are 12:13 CDT, which is 17:13Z.

### 3. The IDL around 17:13Z: the launchd tick fired them

The tick ends at `~/.claude/autonomy/idl.jsonl:14642-14644` (rows abbreviated):

```
17:01:21Z autonomy-sweep self-bound  stopped_before=2-expire-sweep elapsed_s=426   ← previous tick: 26 s too late
17:06:29Z autonomy-sweep config-parity                                          ← next launchd tick (+~300 s)
17:12:33Z autonomy-sweep phase 0b-author-death-join → next 1-collect…  cumulative_s=372
17:13:00Z autonomy-sweep phase 1-collect-pages-alarms → next 2-expire-sweep cumulative_s=399   ← 1 s under 400
17:13:00Z cc-decide expire-sweep id=46676a666732 status=expired-actioned
17:13:01Z cc-decide expire-sweep id=716598eca43f status=expired-actioned
17:13:02Z cc-decide expire-sweep id=de3b237d964e status=expired-actioned
17:13:26Z autonomy-sweep phase 2-expire-sweep elapsed_s=26 fired_defaults=3 fired_nochange=3
17:13:26Z autonomy-sweep self-bound  stopped_before=2b-backlog-health elapsed_s=425
```

- The packets' `resolved` timestamp equals the start of the expire-sweep (`now` is computed once, at `bin/cc-decide:501`).
- The tick that fired them ended itself again before §3, the summary and desk notify. **The desk was never told about the three fires.**

### 4. The overnight window: 39 of 40 ticks stopped before the actuator

The live IDL was rotated at 12:16Z, so the window spans `idl.jsonl.20261018T105203Z.gz` and `idl.jsonl`:

```
$ (gzcat idl.jsonl.20261018T105203Z.gz; cat idl.jsonl) | jq -r 'select(.tool=="autonomy-sweep" and .ts>="2026-10-18T05:00:00Z" and .ts<"2026-10-18T17:13:00Z") | .disposition+" "+(.stopped_before//"")' | grep -E "^(config-parity|self-bound)" | sort | uniq -c
  40 config-parity                          ← one per tick start
  29 self-bound 0b-author-death-join
   9 self-bound 1-collect-pages-alarms
   1 self-bound 2-expire-sweep              ← 17:01:21Z, 26 s too late
phase-0 cost (strand+config-parity+cloud-return): n=40 min=307 median=695 max=1373 s
```

- From 04:01Z to 07:30Z, every tick spent 446–1373 s in phase 0 alone and stopped at the very first checkpoint.
- No tick was killed by the reaper. Every one ended itself, which is the self-bound's documented, intended behaviour (`:442-446`). The bound is correct. The *order* is the defect.

**An earlier episode with the same mechanism** (`idl.jsonl.20261013T023256Z.gz`, window from 10-11T23:38Z, when `103f40b25f01` fell due, to 10-12T07:17Z, when it fired):
`12 × 0b-author-death-join, 5 × 1-collect-pages-alarms, 1 × 2-expire-sweep`. It fired at 07:16:46Z, a 7.6 h lag.

**Fire lags across the store** (packet `resolved` minus `veto_deadline`, for packets in `expired-actioned`):

| Lag | Packets |
|---|---|
| Under 10 min | 10-06 ×4, 10-15 |
| 1.2 h | 10-09 |
| 1.5 h | 10-13 |
| 2.6 h | 10-07 |
| 3.1 h | 10-13 |
| 4.6 h | 10-11 |
| 7.6 h | 10-11/12 |
| 12.2 h | 10-18 ×3 |

The lag follows the box load, not the 300 s cadence.

### 5. It is known, and the fix was closed on a proxy

- `scripts/autonomy-sweep.sh:540-577` records the 09-08 starvation: zero lower-half runs per day.
  - It hoisted config-parity alone.
  - It says in so many words that §2 remains starved and "the general repair … is filed".
- That filed item is `36ce331197ce` in `~/.claude/autonomy/backlog.jsonl` (09-09: "§2, §2b(+i..vi), §2e, §2f and §3 … are all starved").
  - It was closed on 09-17T15:18Z by `cc-premise sweep --close-falsified`.
  - The falsifier only checks that an `unfired-briefs` row exists in the last 24 h. One lucky lower-half tick per day satisfies it, so it cannot detect the expire-sweep being starved for 12 h.
  - No open backlog row covers this.

### 6. What the readout shows

`hooks/operator-readout.sh:1366-1374` selects open class-B packets with `veto_deadline <= NOW+24h`.

- A deadline that has already passed satisfies that test, so an overdue packet is rendered as "auto-fire ≤24h (earliest 2026-10-18T05:00:00Z)".
- That string kept showing from 05:00Z to 17:13Z.
- This is the readout half, g-message-design Q2. It is a separate defect from the actuator, but it is why the starvation stayed invisible.

### Cost of hoisting (measured read-only)

- The expiry predicate was run over all 622 live packets, one `jq` each, the same per-file work as `cmd_expire_sweep`'s scan. It took **5.8 s wall at load 93/76/70 on 10 cores** (14:23 CDT).
- In the live 17:13 tick, all of §2, including the open-decision loop at `:1235-1245`, took 26 s.
- So hoisting §2 costs about 1–4% of the median phase 0.
- I also tried timing `cc-decide expire-sweep` itself against a /tmp copy of the store. The auto-mode classifier refused it, and I did not try another route.

## Fix spec

**Root cause.** `scripts/autonomy-sweep.sh:1185` puts the class-B actuator behind three checkpoints. Above them, phase 0 costs more than the whole 400 s self-bound whenever the box is loaded: median 695 s on 10-18. A fixed phase order plus a tick that ends itself means §2 runs only on the occasional tick that comes in under budget. The 09-09 header (`:574-577`) diagnosed this and fixed only config-parity.

**Minimal fix (one script plus its suite).** Hoist §2 to run directly after `strand_rung` (`:536`), before §0a-i and §0a. This is the same move, with the same argument, as the strand rung (4cfd06143) and config-parity (`:540-572`).

1. `scripts/autonomy-sweep.sh`:
   - Move the body of `:1187-1233` (the `if [ -n "$DECIDE" ]; then … done < <("$DECIDE" expire-sweep …); fi` loop) into a function `class_b_actuate`.
   - Call it on the line after `strand_rung` (`:536`).
   - Bound the producer: `done < <(_bounded "$DECIDE" expire-sweep 2>/dev/null || true)`. `_bounded` (`:341`) is already defined above that point. Under it, the expire-sweep keeps the 400 + 180 < 600 arithmetic (`:362-366`) and adds at most 180 s to phase 0, typically about 6 s.
   - Everything it needs is defined above `:536`: `DECIDE` (`:183`), `BACKLOG` (`:184`), the counters `fired_defaults` and `fired_nochange` (`:214`), and `_bounded`. The counters still feed `total_new` at `:1247` when the tick gets that far.
   - Leave `sweep_yield 2-expire-sweep` at `:1185` as a phase label, or rename it to `2-open-decisions`. The open-decision surfacing loop (`:1235-1245`) stays where it is: it is a reader, not an actuator.
   - Update the header (`:18`, `:574-577`) to say that §2 is hoisted, and the label `SWEEP_CP_PHASE` (`:419`) to include `0-classb-actuate`.
   - The move is idempotent. `cmd_expire_sweep` changes a packet's status exactly once, so a later full tick finds nothing to fire and adds no second backlog item.
2. `tests/autonomy-sweep.bats`: add the cases below.

**Test that goes red on trunk.** It uses the existing helper `truncated_tick` (`tests/autonomy-sweep.bats:2204`), which simulates the live 10-18 tick: T0 is 5000 s in the past, so the run stops at the first checkpoint.

```bash
@test "class-B actuator · an overdue default FIRES even when the tick dies at its FIRST checkpoint" {
  id=$(bash "$CC_DECIDE_BIN" open --class B --what "overdue default under a starved tick" \
        --conviction 60 --receipt "x => y" --default "continue on next2" \
        --deadline "2000-01-01T00:00:00Z")
  truncated_tick
  [ "$status" -eq 0 ]
  # cut where 29 of 39 live ticks were cut on 2026-10-18 — nothing below the first checkpoint ran
  [ "$(jq -r 'select(.disposition=="self-bound")|.stopped_before' "$CC_IDL" | tail -1)" = "0b-author-death-join" ]
  # THE PROPERTY: the default fired anyway, and its work item exists
  [ "$(jq -r .status "$CC_DECISIONS_DIR/$id.json")" = "expired-actioned" ]
  jq -e --arg id "$id" 'select(.verb=="expire-sweep" and .id==$id)' "$CC_IDL" >/dev/null
  run bash "$CC_BACKLOG_BIN" list --open
  echo "$output" | grep -q "class-B default fired: continue on next2"
}

@test "class-B actuator CONTROL · a future-deadline packet stays open on a truncated tick, and a later full tick adds no second item" {
  fut=$(bash "$CC_DECIDE_BIN" open --class B --what "not yet due" --conviction 60 --receipt "x => y" \
         --default "park" --deadline "2099-01-01T00:00:00Z")
  od=$(bash "$CC_DECIDE_BIN" open --class B --what "due" --conviction 60 --receipt "x => y" \
         --default "do the thing" --deadline "2000-01-01T00:00:00Z")
  truncated_tick
  [ "$(jq -r .status "$CC_DECISIONS_DIR/$fut.json")" = "open" ]
  run "${SWEEP_TO[@]}" bash "$SWEEP"          # full tick
  [ "$status" -eq 0 ]
  [ "$(bash "$CC_BACKLOG_BIN" list --open | grep -c 'class-B default fired: do the thing')" -eq 1 ]
}
```

- **On trunk:** `truncated_tick` exits at `sweep_yield 0b-author-death-join` (`:1035`). §2 never runs, so `.status` stays `open` and case 1 fails at the `expired-actioned` assertion.
- **After the hoist:** case 1 passes. Case 2 shows that the hoist neither fires early nor double-fires.
- **Optional third case,** a negative control: re-run case 1 against a build that keeps §2 in its old place, as `build_preorder_mutant` (`:1924`) does for config-parity. It proves the order itself is the delta. Per the repo's test-audit rules, add it only if the reviewer wants the mutant pattern repeated.

**Companion fixes, not part of the minimal fix:**

- **The readout (owned by g Q2).** At `hooks/operator-readout.sh:1366-1374`, split the predicate at `epoch_to_iso "$NOW"`.
  - A packet with `veto_deadline < now` renders as `N class-B default(s) OVERDUE since <ts> · the actuator has not run`.
  - Only `now <= deadline <= now+24h` renders as "auto-fire ≤24h".
- **Re-file the general starvation repair.** §2b, §2e, §2f and §3, the desk notify, are still behind the same wall. The 17:13 tick stopped before §3, so even a fired default is never reported.
  - Re-file `36ce331197ce` with a falsifier that checks every starved arm, for example "no `self-bound` row with `stopped_before` ≤ `3-summary-and-notify` for 24 h". The current one checks a single arm.
  - Or move §3's summary into a hoisted rung, as was done for strand.

## Adversarial pass (gaps checked)

- **"Someone ran it by hand at 17:13."** Ruled out.
  - The expire-sweep rows sit between two of that tick's `phase` rows.
  - The tick started at about 17:06:21Z, which is the previous self-bound (17:01:21Z) plus the 300 s `StartInterval`.
  - `config-parity`, about 4 s into the run, is at 17:06:29Z.
- **"Another actuator should have fired them."** None exists. A repo-wide grep for `expire-sweep` finds only `bin/cc-decide`, `scripts/autonomy-sweep.sh`, tests, docs, and a comment in `ship-land.sh:650`.
- **"The job was not loaded or not running."** It is loaded and `running`, with `runs = 2034` and `last exit code = 0`. It started 40 ticks in the window.
- **"The packets were malformed, so the predicate skipped them."** They have class B, status open, a non-empty `veto_deadline`, and a deadline before now. The first tick that reached §2 fired all three at once.
- **"The veto window is advisory by design."** No document says so. `commands/limit-recover.md:554-556` is a different pattern: the agent proceeds on the default immediately and the packet is the trail. It does not make the deadline-firing of ordinary packets optional.
- **The remaining 5% of doubt.** Someone could argue that "fires at the deadline" means "at the first tick that reaches §2", making the latency acceptable. Two things contradict that: the self-bound's own note (`:442-446`) treats always-the-same `stopped_before` as a defect to fix, and the 09-09 header names §2 as starved.
