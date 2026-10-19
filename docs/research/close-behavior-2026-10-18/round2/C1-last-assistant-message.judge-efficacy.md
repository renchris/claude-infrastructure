# C1 judge: efficacy lens

Round 2, 2026-10-18. Adversarial judge for `C1-last-assistant-message.md`. The lens is **efficacy**:
1. Would C1 have changed the 2026-10-18 outcome, meaning the waves get driven or the close leads with what remains?
2. Is gaming cheaper than driving as a way to comply?
3. Does C1 fire at a Stop that actually runs, given the timeouts, caps and gates?

I worked read-only. Scratch went to `/tmp/r2-C1-judge-eff/`. I read the designer's census at `/tmp/r2-C1/replay/` but did not
re-run it. Each number below is labelled measured (with the script or source) or estimated (with the method).

**Verdict: below 90 on efficacy.** C1 is a sound correctness precondition. I found independent evidence for the race
that is stronger than the design's own. But C1 would not have changed the incident, and there is a measured reason for that. Its
projected population gain is also overstated, because the closes it newly reveals land on the slow path, where
about a third of Stops die at the 5-s timeout.

## 1. Would C1 have changed the incident outcome? No

### 1.1 The terminal close (T:643, 14:27:47Z): capped either way

- **Measured.** IDL rows for sid `5759497b`, completion-assert, read from
  `~/.claude/autonomy/idl.jsonl{.20261018T105203Z.gz,}` with `python3 -I`:
  - 13:18:16Z `no-close-tell`;
  - 13:18:34Z, 13:19:02Z and 13:19:40Z `fired`, each `arm:ledger class:assert` with facts "1 commit(s) YOU wrote are
    committed-but-unlanded";
  - 14:19:08Z `no-close-tell`;
  - 14:27:50Z `capped:3>=3 suppressed_arm:handoff rung:✅`.
- **Measured, with the exact gate** (`bash /tmp/r2-C1/scripts/gate.sh`, which is hook lines 355-397) on the incident's text
  records:

  | Record | Gate result |
  |---|---|
  | T:300 | pass |
  | T:306 | pass |
  | T:329 | pass |
  | T:377 | **no-close-tell** |
  | T:643 | pass |

- **Deduced from the latch.** The latch is at `completion-assert.sh:1617-1618`: a hash that already fired gives
  `latched-already-fired`.
  - The 13:19:40Z fire was the Stop whose final is T:377. T:377 fails the gate, so the hook read T:329.
  - T:329 cannot have been fired on before, so the 13:19:02Z Stop (final T:329) must have read T:306.
  - By the same step, the 13:18:34Z Stop (final T:306) read T:300.
  - The 13:18:16Z Stop (final T:300, which passes the gate) logged `no-close-tell`, so it read the text before T:300.
  - So **four Stops in a row in the incident session judged the previous message.** That is independent, non-statistical
    confirmation of the race, and it is stronger than the design's 6/6 replay because it uses only the live hook's own state.
  - The 14:19:08Z Stop also fits a stale read: its final, T:630 "🔧 Landing the synthesis commit…", passes the gate, and
    the hook logged `no-close-tell`.
- **What C1 does to the cap.** With C1, each of the three ledger fires moves one Stop earlier (on T:300, T:306 and T:329).
  T:377 abstains. T:630 becomes a **fourth** gate-passing, ledger-contradicted Stop that draws on `assert`.
  - The assert budget is still spent long before 14:27:47Z. C1 makes cap starvation at the terminal close more certain,
    not less.
  - This assumes the agent's replies would not have changed. They could have, but the session had four gate-passing
    landedness Stops against a cap of 3.
- Even uncapped, D1 matched the settings.json "needs your hand" item, not the README §5 waves (README R3), and no arm
  matches the waves (R2). **C1 cannot reach the incident's close.** The designer says the same in §6. I confirm it with
  a stronger argument than the design gives.

### 1.2 rs05 (06:04, "Investigating the load now" and then a stop): almost certainly killed, or D1 cannot tell

- With C1, the hook reads the payload, rs05's final passes the gate, and the hook goes on to the ledger and backlog reads.
  - **Measured** (`stops.jsonl`): the incident session's gate-passing Stop one minute earlier (rs04, 06:03:11) ran 5,687 ms
    and left no IDL row. The 06:08:20 Stop took 5,781 ms even on the fast path. rs05's own text says the load was
    "about 519 on 10 cores".
  - **Measured fleet-wide**, both-pass Stops (`python3 -I` over `/tmp/r2-C1/replay/stops.jsonl`): between 06:00 and
    06:59Z on 10-18, **9 of 13 left no IDL row**, each with `ca_ms` between 5,089 and 5,652. The 4 survivors ran
    4.3-4.5 s, and 3 of them were capped. Across 05:00-06:59Z the count is 13 of 18.
- D1 fires only if `cc-backlog list --blocked --json` affirmatively returns an array with nothing filed for the session.
  On a timeout or a non-zero rc it does not fire (`completion-assert.sh:78-80`, `:1239-1240`). At that load the 10 MB fold
  has a 5-s bound inside a 5-s hook.
- The sandbox D1 fire (design §2.1) used a `[]` backlog stub at no load. **Estimated:** the chance the live rs05 Stop
  would have completed with a D1 block is ≤25%, from the 9/13 kill rate and then the backlog-read failure.
- Even when it fires, D1's remedy is "file each operator-only step (`cc-backlog needs`) … then re-close". Filing is the
  cheapest compliance. It does not say "you announced 'Investigating the load now' and stopped".

### 1.3 rs04 (06:03, killed at 5,687 ms) and anti-deference

- rs04 is unchanged. The scan C1 removes costs 0.10-0.13 s (design §4), against a 687 ms overrun.
- anti-deference logged `no-tell` on every incident-session Stop in the census (measured). Its `TELLS` matches none of
  the incident messages (axis 07 S0, README R2), so payload-sourcing changes nothing there.

**Net for the incident (estimated, by combining §1.1-1.3): about 5% chance that C1 alone changes any Stop outcome in session
`5759497b`, and about 0% that it changes the terminal close or gets the waves driven.**

## 2. Does it fire at a Stop that actually runs? Often not, on completion-assert

C1 does not change the hook's runtime path for a given message. It changes **which** message is judged. The 278 misses
it recovers all move from the fast `no-close-tell` exit onto the ledger and backlog slow path.

**Measured**, over the same 7,847-Stop census (`python3 -I` over `/tmp/r2-C1/replay/stops.jsonl` with
`analyze.gate`, pre-gate abstains excluded), split by the gate verdict on the final (gf) and on the stale view (gs):

| Group (by gate verdict) | n | no IDL row | `ca_ms` ≥ 5,000 (of those with a duration) | p50 `ca_ms` |
|---|---|---|---|---|
| both views pass (the hook certainly reached the slow path) | 801 | **271 (33.8%)** | 280 of 671 (41.7%) | 4,112 |
| both views fail (the hook certainly exited at the gate) | 4,665 | 6 (0.1%) | 27 of 4,656 (0.6%) | 800 |
| final passes, stale fails (where C1 changes the path) | 1,491 | 413 (27.7%) | 425 of 1,310 (32.4%) | 2,565 |

- The daily rate in the both-pass group runs from 9% (10-15) to 63% (10-11), and is 25% on 10-18 (measured).
- Live past-gate rows: p50 2,402 ms, p90 4,292 ms, p99 5,175 ms, against a 5-s timeout (measured).

Consequences:
- **The projected gain shrinks by about a third (estimated).** Correcting the design's "≈63 new fires" for the slow-path
  kill rate gives 278 × (1 − 0.338) × 0.228 ≈ **42**. The 22.8% fire rate already includes caps, because it comes from
  Stops that left a row, but it leaves out kills.
- **Caps (measured, IDL plus `cases.json`).**
  - Of the 278 misses, 60 came after the session's assert budget was already spent. A final-read that falls to
    `assert` would only log `capped`.
  - Of the other 218, 46 are in sessions that later log an assert `capped:` row. In those sessions a new C1 fire brings
    the cap one Stop earlier, which is the R3 starvation mechanism that silenced the incident's close.
  - So C1 makes C2 (per-fact latch or class split) **more** necessary. It does not substitute for it.
- **anti-deference** has no slow path. Incident-session runs took 395-1,283 ms, with one 5,782 ms outlier under the
  06:08 load (measured). C1's gain there does run, but it is tiny: 2 of 7 Stops in 7.5 days (design §2.2).
- **The "19 wrong-target blocks removed" overstates the benefit (measured, `cases.json` joined to the previous Stop).**
  - 10 of the 19 re-judged the previous Stop's final, and 9 judged an intra-turn text. The incident's 13:19:40Z fire is
    one of them: it convicted T:329, which no earlier Stop had judged.
  - With C1, such a fire mostly **moves to the earlier Stop** rather than vanishing. The benefit is correct attribution,
    not 19 fewer blocks.

## 3. Is gaming cheaper than driving?

- C1 adds no arm, no message and no new demand, so it opens **no new gaming route**. This is its strongest
  efficacy property.
- It inherits the routes of the arms it now feeds. In each case, the cheapest compliance:
  - Ledger landedness: `/ship`, which is real driving.
  - D1: file a `cc-backlog needs` row and re-close.
  - D4: lists `DROPPED` as a legitimate disposition. A one-line drop is cheaper than driving, and on rs13 the
    operator wanted the work driven ("can WE get our sessions going now").
  - D6: a line-1 rewrite, by design; rs01 is a legitimate value fork.
  - anti-deference: the remedy is "DRIVE it now … or name the ONE specific irreducible blocker"
    (`anti-deference-nudge.sh:637`), but a rephrase without the tell gets a new hash and passes.
- For the incident shape (✅ yes plus undriven follow-on prose), no arm matches, so C1 yields neither gaming nor driving.
- The efficacy of the newly visible fires is therefore exactly the precision of today's arms, which C1 leaves
  unmeasured (design §8.2).

## 4. What holds

- **Mechanism, ≥95%.** The binary read is spot-checked: offset 195,022,749 shows
  `{...Se,hook_event_name:"Stop",stop_hook_active:s,last_assistant_message:_e,...ke}`. `ry` is
  `findLast(type==="assistant")`, and `FLUSH_INTERVAL_MS=100` is at 196,608,143 (measured, `python3 -I` seek-read of
  `claude.exe`). The §1.1 latch deduction adds live proof.
- **Timing cannot discriminate the two reads.** Hook start, estimated as the summary `ts` minus the maximum hook
  `durationMs`, minus the final record `ts`, has p50 0.06 s for final reads (n=1,449) against 0.10 s for stale reads
  (n=369) (measured). The design's ±0.5 s caveat stands. The latch deduction is the better evidence.
- **Patch and tests.** The TAP files in `/tmp/r2-C1/bats/` show 1..185, 1..61, 1..8, 1..8 and 1..9, all ok. The new
  suite is 1..6 all ok on the patched copy and 3 not ok on the baseline (tests 1, 2 and 5). I read these files and did
  not re-run them.
- **Sound to land as a correctness precondition.** It is cheap, silent without the key, and makes the remaining 20% of
  Stops behave like the 80% that already read the right message.

## 5. What would make an efficacy claim honest

1. In the design and in README F10, state that C1 changes neither the incident's terminal close nor, with high
   probability, rs05. Use the latch deduction and the 9/13 slow-path kill rate. Present C1 as a precondition, not as a
   close-behavior fix at >90.
2. Correct the projection to about 42 new fires, by applying the measured 33.8% slow-path kill rate. Pair C1 with F12
   (text-only arms before the ledger), or a share of its gain dies at the timeout.
3. Sequence it with C2. Of the misses, 60 were already capped, and 46 more sit in sessions that later cap. Measure on a
   replay how many terminal closes would reach `capped` earlier under C1.
4. Hand-label at least 30 of the newly visible fires (sandbox replay of the patched hook on the 278 finals) before
   claiming net-positive outcomes rather than net-positive correctness.
5. Rewrite the "19 wrong-target blocks removed" as re-attribution: 10 re-judged the previous Stop's final, 9 judged an
   intra-turn text.
