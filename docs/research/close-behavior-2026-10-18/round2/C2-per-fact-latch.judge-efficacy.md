# C2 judge: efficacy lens

Round 2, 2026-10-18 (written 2026-10-19 local night). This is the adversarial judge for `C2-per-fact-latch.md`. The lens is **efficacy**:
1. Would C2 have changed the 2026-10-18 outcome, meaning the §5 waves get driven or the close leads with what remains?
2. Is gaming cheaper than driving as a way to comply?
3. Does C2 fire at a Stop that actually runs, given the timeouts, caps and gates?

I worked read-only in the repo. Scratch went to `/tmp/r2-C2-judge-eff/`: `bin/replay.sh`, `bin/probe.sh`, `bin/probe3.sh`,
`silenced.py`, `negscan.py`, `forkcost.sh` and `keyfid.py`. Every hook run used the designer's `/tmp/r2-C2/{base,final}` trees,
with every state seam pointed under my directory. `diff -q` shows the base hook is byte-identical to this worktree's
`hooks/completion-assert.sh`. Each number is labelled measured (with its source) or estimated (with its method).

**Verdict: below 90 on efficacy.**
- **Conviction that C2, as designed, is effective enough to clear 90% on this lens: 5.**
- C2 is a sound noise fix. Its ⛔ guard is a real fix for constraint 2.
- On this incident, C2's effect is about zero, and possibly slightly negative:
  - it removes the one block in the session that turned a stated park into a drive;
  - the block it unmasks at the terminal close asks the agent to file something, not to drive anything.
- The report's "necessary but not sufficient" framing is half wrong. Every round-2 follow-on arm already avoids the
  `assert` budget, so C2 is not necessary either.

## 1. Would C2 have changed the incident outcome? No

### 1.1 The terminal close gets D1's filing demand, which names nothing in §5

- **Measured, by replay** (`bash /tmp/r2-C2-judge-eff/bin/replay.sh base|final`, using the designer's four transcript texts and
  the live rungs: 📦 one unlanded commit for Stops 1-3, ✅ all-zero for Stop 4).

  | Stop | base | final |
  |---|---|---|
  | 1 | fired ledger 1/3 | fired ledger 1/3 |
  | 2 | fired ledger 2/3 | `latched-same-fact` |
  | 3 | fired ledger 3/3 | `latched-same-fact` |
  | 4 | `capped:3>=3`, `suppressed_arm:handoff`, rung ✅ | fired **handoff** 2/3 |

  This matches the designer's §5.4 and the live IDL row at 14:27:50Z, which I re-read in
  `idl.jsonl.20261018T105203Z.gz` + `idl.jsonl`.
- **What the Stop 4 block says** (measured: `stop4-reason.txt`, the same text as `completion-assert.sh:1650`):
  "An operator-only step is not an escape hatch … If you can run it, run it now … File each operator-only step —
  `cc-backlog needs "<step>" --class needs-human …` — then re-close: the rung line reads 👤 …".
  It does not mention the follow-on clause, README §5, the waves or "drive".
- **The cheapest compliance is one `cc-backlog needs` call for the settings.json timeout, then a 👤 re-close.**
  - That step is operator-only by policy (constraint 3), so filing it is the correct answer to D1. It is not gaming.
  - The re-close would lead with the operator's step, not with the six drivable waves.
  - The `follow-on:` clause passes every arm unchanged. That is axis 02 RC1, replay B `ledger-clean`.
- **Estimated** (from the block text and the arm map): about 5% that this block alone gets a §5 wave driven or moved to the
  lead. The only route is the agent reading "if you can run it, run it now" more broadly than the block's own object.

### 1.2 In the incident session, C2 removes the one block that drove

Measured by reading the transcript. The transcript is `~/.claude-secondary/…/5759497b-….jsonl`, and the IDL comes from the same two files.

| ts (Z) | event |
|---|---|
| 13:18:32 | close: "I'm holding the land on purpose … I'll ship once, after the workflow finishes" |
| 13:18:34 | completion-assert ledger fire 1/3 |
| 13:18:59 | close: "This isn't done, and I'm not claiming it is. The work is still running." (the park, restated) |
| 13:19:02 | completion-assert ledger fire 2/3. Every other Stop hook abstained: session-continue `ship-floor-latched`, anti-deference `no-tell`, dispatch-assert `no-assistant-text`. operator-readout `steps-surfaced` is a readout, which never reaches the agent (README R9). |
| 13:19:09-13:19:33 | `git status`, reads `ship.md`, `git worktree add … 5094a913e`, `bash scripts/ship-land.sh` |
| 13:19:44-13:20:42 | the land gate goes red on two research scripts; the agent fixes them (`87a5169a1`) |

- Under C2 the 13:19:02Z Stop is `latched-same-fact`. This is measured by replay, and it holds whichever message the live hook
  read, because the facts and the session-continue sha `5094a913e…` are identical at all three Stops. The turn then ends
  on the restated park.
- So **the only block in the session that converted a stated park into a drive is the one C2 silences.**
- The designer counts it: it is the 1 in the 1/27 of §3. The designer books it as "only moved a land the agent had already promised".
  Measured against the operator's complaint ("There is no net positive if research is done but its not enacted on"),
  though, it is the incident's own theme. Repeat pressure drove once here, and K=1 removes exactly that.
- Estimated: the land would probably still have happened after the workflow, once a new commit re-armed the ship floor.
  So the cost is latency, not loss. But that makes the benefit side of C2 in this session about zero, too.

### 1.3 "Necessary" does not hold: the follow-on arms do not draw on `assert`

- C3 claims its own class, `followon` (`COMPLETION_FOLLOWON_MAX`, `C3-followon-store-discharge.md:84`).
- C6 claims its own class, `undriven`. It ships a test named "drive-state STARVATION: three 📦 fires spend the assert cap; the
  terminal undriven close STILL fires" (`C6-doc-disposition-marker.md:388,1332`).
- README F13 requires its fire "including when `assert` is pre-capped at 3/3". F17 says "in **its own class**, not `assert`". §6
  rejects "any new arm in the shared `assert` budget".
- So no candidate that could drive §5 needs C2 to reach the terminal close.
- C2's own reach on the R3 mechanism is small. Of the 41 recovered fires (measured: `python3 -I` over the designer's
  `sim-head-k1-blocked.jsonl`), 33 are the pure ledger arm. Only 3 are prose-only terminal-close fires (2 `handoff`, 1
  `hedge`), and one of those is the incident's mis-aimed D1.

**Net for the incident (estimated, from §1.1-1.3):**
- about 0-5% that C2 changes whether §5 is driven or led with;
- a small negative on landing latency, from 1.2.

## 2. Does it fire at a Stop that actually runs? Yes. The latency cost is negligible

- **Timeout.** completion-assert is registered at `timeout: 5` (measured: `jq '.hooks.Stop' ~/.claude/settings.json`, read-only).
- **The incident's terminal Stop ran.** completion-assert took **3,350 ms** (measured: the `stop_hook_summary` at
  14:27:57.597Z in the transcript).
  - At that Stop, `contra=0` (rung ✅, `facts:""`), so `FKEY` is empty and C2 adds no fork. It adds only the fire tail.
  - Replay at load about 290: base 1.76 s (capped) against final 1.86 s (fired). That is a single run each, so it is noisy.
  - Estimated: about 3.45 s live, which fits inside 5 s.
- **Fact-key cost on the contradiction path.** `git rev-parse` + `sed` + `shasum`, 10 runs at load average 270: median about
  0.06 s, max 0.12 s (measured: `bash /tmp/r2-C2-judge-eff/forkcost.sh`).
  - In the C1 judge's census (`/tmp/r2-C1/replay/stops.jsonl`), 2 of the 462 cap-stage Stops that have a duration sit in [4,880, 5,000) ms.
  - Estimated: at most 0.4% of contradiction Stops would be pushed past the timeout.
- **What C2 cannot see.** 733 Stops in that census left no completion-assert row, and 730 of them ran ≥ 5,000 ms (measured). That
  is the slow-path kill, and neither the cap replay nor C2 reaches it. The C3 judge measured a 48% kill rate on YES closes. The
  incident's terminal Stop was not among the killed, which is why C2's one incident effect is real.

## 3. Is gaming cheaper than driving?

- **C2 adds no demand, so it opens no new route to a block.**
  - What it changes is the price of *ignoring* a valid ledger conviction: one block per (fact, HEAD), down from three.
  - Probe P3 (measured: `bin/probe.sh`, 📦 ledger, one HEAD) runs "Everything requested is done." and then the bare re-assertion
    "✅ Good to close: yes. Everything is landed and live; nothing of mine is open.":
    - base: fired 1/3, 2/3, 3/3;
    - final: fired 1/3, then `latched-same-fact` twice.
  - With the ship floor, an unlanded sha now carries 2 blocks in total, down from 4.
- **The measured cost of that route is small.** I read the 130 fires the design silences, using `silenced.py` over the designer's dump.
  - 90 are worded as a park or wait.
  - 17 are neither park-worded nor led by a rung or verdict. I read every line 1. They are status reports, other
    sessions' dirt, or conversation, for example "Yes, it is still there: I just checked the database".
  - The 4 ✅-led closes are all "dirty tree (89-90 files), authorship UNRESOLVED" in a shared repo where the dirt belonged
    to other sessions (99e83151; e7659abe ×2). Those are false positives that the latch rightly silences.
  - So beyond the incident's fire #2, I found no silenced true positive. This is a hand-read of line 1 only, so it is estimated.
- **The ⛔ guard accepts the glyph anywhere on the rung line, including inside a denial.**
  - Probe P3b (measured: `bin/probe3.sh`, ledger BLOCKED=1, RUNG=⛔) closes with "✅ All done and landed — no ⛔ decisions are open.":
    - base: fired `ledger`;
    - final: `ledger-clean:exonerated:blocked-rung-stated`.
  - A close that denies the open decision is exonerated as though it had stated it. The designer's tests cover a ⛔ on the rung
    line and a ⛔ below it, but not this case.
  - Frequency (measured: `negscan.py` over the designer's 14-day `transcripts.txt`, then a hand-read):
    - 1,473 assistant texts carry ⛔ on the rung line;
    - 8 match a negation shape;
    - all 8 are genuine "⛔ No change: …" leads.
  - So the route exists but has no real use yet. It is cheaper than surfacing the decision once an agent learns it.
- Probe P1 is "✅ Good to close: yes. Nothing of mine is open." with "⛔ 1 decision … waits on your ruling" on line 2. Final
  exonerates it. The decision is surfaced on the rung line, so I count this as acceptable, not gaming.

## 4. What holds

- **The mechanism reproduces exactly.** Both replays and all three probes behave as the report predicts.
- **Silenced repeats are close to useless.** The designer measured 1 of 27 same-HEAD repeats preceding a ship, and my reading
  of the silenced set found no other true positive. So C2 is a real reduction in noise, and it makes
  completion-assert follow the ship floor's own per-HEAD discipline.
- **The ⛔ guard is a genuine constraint-2 fix,** but its count needs one clarification. "27 → 0" counts BLOCKED clauses.
  It does not count blocks. Of the 27 fires (measured, on the dump):
  - 18 abstain;
  - 7 still fire on another ledger fact;
  - 2 are latched.
- **None of this is continuation.** C2 changes how many times the same thing is said, not what is said. On this lens
  it does not move the operator's loss.

## 5. Fidelity gap in the 345 → 256 estimate

The design's key is digit-folded facts plus HEAD. The replay used that key only where session-continue logged a sha within
±5 s, which is only ever on ship-floor records. Everywhere else it fell back to byte-exact facts with no HEAD. Measured with
`keyfid.py` over the designer's `events.jsonl` + `sc14.jsonl`:
- 313 of 818 ledger-bearing events got the design's key. All of them are unlanded facts.
- **505 (62%) used the fallback.** That covers every blocked (120), custody (236) and dirty (74) event, plus 66 unlanded events.
- Folding digits latches more (for example, "89 files" against "90 files" on one HEAD). Adding HEAD latches less (across commits).
- The direction of the error is unknown, so "345 → 256" and "41 recovered" are estimates of a *different* key for most of the population.

## 6. What would make the efficacy claim honest

1. **Drop "necessary".** C3, C6 and F17 each claim their own class, and README §6 forbids new arms in `assert`. C2 is not on
   the critical path of any fix that could drive §5.
2. **State the incident effect plainly.** C2 removes the 13:19:02Z block, the session's only conversion of a park into a drive
   (separate-worktree land, 13:19:33Z). It also unmasks D1's filing demand at the terminal close. Net effect on the
   incident: about zero.
3. **Reframe C2 in README F11 as noise and constraint-2 hygiene,** not as a continuation fix.
4. **Consider landing the ⛔ guard on its own.** It is independent of the latch, and the designer scores it at 95 alone. Anchor it on ⛔ as the
   rung token (the first glyph of the rung line), or add a negated-glyph test and document the route.
5. **Re-run the cap replay with the design's own key** (HEAD recovered from the transcript's git calls), or label the 62% fallback
   in §2.2 and §7.
6. **Restate "27 → 0" as BLOCKED clauses,** and give the block counts: 18 abstain, 7 still fire, 2 latched.
