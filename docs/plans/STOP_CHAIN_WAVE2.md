---
status: complete
---

# STOP_CHAIN_WAVE2 — driving the six filed Stop-chain defects to completion

**Scope (frozen):** drive to landed+green every one of the six Stop-chain defects filed by the
2026-09-02 MECE audit that research has proven drivable, and close by evidence the ones that are not.

Origin: the 2026-09-02 Stop-hook MECE audit (12 hooks read; reports in
`docs/research/stop-chain-wave2-2026-09-03/`). Two of that audit's six were fixed and landed the same
day (`ef7de427d`: kill-switch reach + mechanical_arm exemption; `299e4d563`: the multi-line reader in
completion-assert). This plan drives the remaining four plus two discovered since.

**Why this plan exists at all.** The operator's question was whether the workflow files more than it
solves. Measured: the backlog is at break-even (1,070 added / 1,046 closed over 21 days; 82% closed
lifetime) — so it is NOT growing. But 284 open rows have never had an event after `add`. Filing costs
one command; fixing costs a worktree and a gate. At equilibrium that asymmetry decides *which* rows
close, and the structural ones never do. This plan is the counter-move: research each filed row to
conviction, then drive rather than defer.

---

## Phase 0 — Orchestration

**EXECUTION LOCUS PER WAVE: L (lead-inline).** Justification: every item is a ≤1-file edit plus its
bats suite in ONE repo, the items share two files (`session-continue.sh`, `completion-assert.sh`), and
W1→W2 has a hard data dependency (below). Fan-out would serialise on the same files and pay merge cost
for no parallelism. The research that WAS parallelisable is already done (5 agents, reports carried
into `docs/research/stop-chain-wave2-2026-09-03/`).

**Lead context budget:** succeed at ≤60% fill; recycle at the wave boundary, never mid-wave.

**Wave order is dependency-driven, not size-driven:**

| Wave | Item | Depends on | Why this order |
|---|---|---|---|
| W1 | `61a3b40d8695` — IDL blind spots | — | **Must be first.** `goal-inert-watch` has written **0** IDL records in 978,400; `session-continue`'s 323 records contain **no** `wake-floor` reason. Until both log, W2 is unmeasurable. |
| W2 | `0f4147dcb20b` — goal-inert-watch detects only never-evaluated | W1 | Needs W1's telemetry to show whether the hook ever fires at all. |
| W3 | `c9c3445be29d` — session-continue's multi-line reader | — | Independent. One hunk, four call sites. |
| W4 | `79e2b74796af` — double-block guard | — | Independent of W1-W3; touches completion-assert. |
| W5 | `a9ede190ee3b` — custody attribution | — | Largest. Do last so a recycle boundary falls cleanly before it. |
| W6 | `d8147be371cd` — agent-report recovery | — | **CLOSE, do not build** (§6). |

---

## The six, with the evidence that settles each

### W1 · `61a3b40d8695` — two Stop arms write no IDL — **DRIVABLE, CONFIRMED**

Measured over **978,400 IDL records across 17 files** (current + 16 rotations):

```
goal-inert-watch          0 records, ever
session-continue        323 records — reasons: cli-clear 72, continue 71, mechanical-budget 55,
                        cli-set 51, mechanical-dirty 41, ship-floor 24, sid-mismatch 8,
                        mechanical-assignee 1   ← NO wake-floor reason of any kind
```

So both halves of the filed claim are true, and the consequence is real: for these two arms
"abstained" and "never ran" are byte-identical, which is the B-3 ambiguity `boundary-handoff.sh:17-19`
exists to remove.

Work: add `log_idl`/`abstain` calls to the decision-bearing exit paths of `wake_floor`
(`session-continue.sh:416-697` — **13 exit paths / 15 dispositions** enumerated) and wire
`hooks/lib/idl-log.sh` into `goal-inert-watch.sh` (`_gi_abstain` at `:92` is a bare `exit 0`, **10 call
sites**; it does not call `idl_init` at all).

**THREE THINGS THE FILED ITEM DID NOT ANTICIPATE** (measured; they change the work):

1. **It is THREE arms, not two — `ship_floor` has the same defect**: 17 exits, logs 1.
2. 🚨 **The wake_floor gap is not an oversight, it is a LANDED DECISION, and one test pins it.**
   `session-continue.sh:53-57` deliberately forbids logging the disarmed steady state, and
   `tests/session-continue-telemetry.bats:75-78` asserts `idl_count -eq 0` on **exactly the path the
   floors run on**. Naively adding logging REVERSES a landed decision and turns that test red — a
   red an implementer would misread as their own regression.
   **The volume premise behind it is now measurably weak** (~30 fleet Stops/day against 63k IDL
   rows/day), so the cure is not to argue the reversal: **log only the 9 decision-bearing exits and
   re-scope that test** to the steady-state path it was actually protecting. That avoids the reversal
   entirely and is the recommended option.
3. **For `goal-inert-watch` the risk is the reason VOCABULARY, not row counts.** Logging *enrols* a
   hook currently absent from every consumer table. `idl-abstain-alarm` (the only wired pager)
   defaults unlisted reasons to DORMANT, so it stays green **provided the new tokens avoid its blind
   set** — check that set before choosing reason strings. `cc-audit` would alarm but has no automated
   caller and already alarms on three hooks today. `hooks/desk-brief-inject.sh:25-35` is the landed
   precedent for exactly this enrolment.

⚠️ **Check before landing:** any consumer that counts IDL rows or asserts the ABSENCE of these hooks.
`mechanical-assignee 1` proves new reasons show up in production immediately.

🚨 **SHIP W1's goal-inert half AND W2 IN ONE DIFF.** The W2 gate relaxation *changes which exit paths
exist*, so wiring IDL first and relaxing second would log a path set that the next commit deletes.
Split W1 instead along the file boundary: `session-continue.sh` (wake_floor + ship_floor) is its own
commit; `goal-inert-watch.sh` logging ships together with its W2 relaxation.

### W2 · `0f4147dcb20b` — goal-inert-watch cannot see "stopped evaluating" — **DRIVABLE after W1**

Gate 2 (`goal-inert-watch.sh:120-128`) requires the LAST `goal_status` attachment to still be the arm
sentinel with `met:false`. A goal that evaluated once then went inert writes a non-sentinel last
record ⇒ the hook abstains forever. It detects only *never-evaluated-since-arming*, never
*stopped-evaluating* — the failure it exists for.

**The threshold is NOT a new value choice.** Gate 3b already ships one: *≥2 real typed user turns
since the arm sentinel* (`:137-153`, and `:35-38` explains why 2 and not 1 — a single interrupt must
not fire it). Re-anchor the same threshold on the newest evaluation rather than on the arm sentinel.
**Wall-clock age would be wrong** — an idle session accrues age without accruing turns.

**QUANTIFIED, so this is not a theoretical gap.** Over **1,511 `goal_status` attachments across 626
transcripts / all four account roots**: sentinel and evaluation records are cleanly distinguishable
(`sentinel` appears only on arm/clear, `reason` only on evaluations, **zero ambiguous records**), and
evaluations are timestamped on the **envelope, not the attachment** — read the envelope. Measured
blind spot: **25 windows where a live goal went ≥2 turns unevaluated with a non-sentinel newest
record — 12.6% of all inert windows are invisible to the hook today.**

**The remedy is a one-predicate swap, and the primitive already exists.** `hooks/lib/goal-state.sh`
ships `goal_live_condition` — exactly the needed relaxation — and `goal_liveness`, which already
returns the evaluation count and epoch. **`goal-inert-watch.sh` sources neither and hand-rolls a
near-copy of both.** Use the lib rather than editing the copy; that is also what makes the IDL wiring
in W1 tractable, since the lib's exit paths are already named.

### W3 · `c9c3445be29d` — session-continue's reader is blind to multi-line — **DRIVABLE, REPRODUCED**

`last_user_msg()` (`:190-201`) is byte-identical to the pre-fix `ca_last_user_msg`: `jq -r … | tail -1`
takes the last LINE, not the last RECORD. Reference fix already landed in `c18a55c09` (`jq -c` +
decode). **One hunk repairs four call sites**: wake floor `:656`, mechanical arm `:745`, ship floor
`:889`, armed path `:997`.

Reproduced end-to-end with a 3-arm discriminator (driver preserved at
`docs/research/stop-chain-wave2-2026-09-03/reader.md` §2):

```
CONTROL   single-line, phrase is whole message : ALLOWED  (expect ALLOWED)
SUBJECT-A phrase on line 1, 5 lines after      : BLOCKED  (expect ALLOWED — THE BUG)
SUBJECT-B phrase on the LAST line              : ALLOWED  (expect ALLOWED)
```

Six short lines is enough — **no size needed**. Every existing kill-switch test uses a single-line
message, which is why this survived.

🚨 **DO NOT port the `grep -q` half of `c18a55c09`.** That defect required `set -o pipefail`;
`session-continue.sh` sets **no shell options at all** (`grep -n 'pipefail'` → no match), so the
inversion provably cannot occur here and no test could distinguish the branches. Copying the drain is
harmless, but claiming it fixes a second bug would repeat exactly the error `c18a55c09`'s own body
documents.

**Frequency, measured over 6,244 transcripts / 5 roots / 45 days / 14,779 main-session user messages:**
64.8% of messages are multi-line (27.3% for operator-typed prose alone). Of 607 kill-phrase-bearing
messages the current reader misses **97.5%** — but read the misses before believing the number: 423 are
the `/ship` command body, 94 `/limit-recover`, and the rest are fire briefs with incidental phrasing.
**The only two genuine operator kill messages in 45 days were one-liners, and both were caught.**
Observed harm is therefore **0/2** — n=2 bounds nothing. This is a **latent defect with a fully live
mechanism**, not a demonstrated incident. Say it that way in the commit; do not inflate it.

🚨 **THE CONSEQUENCE THAT MUST BE NAMED — AND IT IS ALREADY LIVE ON TRUNK.**
Post-fix, **592 messages begin matching that did not before, and the biggest class is `/ship` itself**:
`commands/ship.md:42` contains the words *"stop here"*. So a corrected reader means **typing `/ship`
trips the kill switch and disarms the floors for that turn.**

**This is not hypothetical and it is not W3's to introduce — `299e4d563` already shipped it.** The
completion-assert kill-switch landed yesterday reads the same command body, so **on trunk today,
running `/ship` suppresses completion-assert for that turn** — i.e. the close gate is weakest on
exactly the turn that lands code. That consequence was not named in `299e4d563`'s commit body. It
should have been.

**The remedy is better than either current state, and it is evidence-determined:** the kill-switch
reader should **skip slash-command expansions** — they are command *bodies*, not operator prose, and
they are mechanically identifiable (`<command-name>` marker; the same exclusion made this plan's own
frequency measurement honest, taking 183 apparent hits down to 3 real ones). That removes the
false-positive class at its root, restores the close gate during `/ship`, and leaves the genuine
override working.

**Do this as part of W3, and back-apply it to `completion-assert.sh`** so the two readers stay one
spelling — the same two-oracles rule that governs W5.

### W4 · `79e2b74796af` — the double-block — **DRIVABLE; the shape is settled by evidence**

**The premise is NOT refuted — it is measured.** Over the retained IDL window (2026-08-25 → 09-03),
against a denominator of **1,335** completion-assert Stop evaluations:

```
same-Stop double-fires (session-continue fired + completion-assert fired, same sid, ≤1s) : 33  (2.5%)
completion-assert arm in ALL 33                                                          : false-done (33/33)
session-continue arm                                                                     : continue 22 · ship-floor 11
```

The harness does **not** short-circuit — `hooks/hook-chain.sh:78` states it as contract
(*"every member always runs… the harness runs every hook in a matcher group even when one blocks"*),
and the IDL proves it (hook #6 wrote a record after hook #4 fired).

**What the model actually receives** — sid `3c60afff`, 2026-09-02T00:38:27, two separate messages
0.77 s apart, both about the same uncommitted file:

```
00:38:27.213Z  🔧 Loose ends remain — … 1 file(s) you edited THIS TURN still uncommitted …
00:38:27.980Z  Completion-assert: your close reads as done/complete, but the LIVE ledger contradicts
               it — dirty tree — 1 file(s) YOU edited are uncommitted …
```

⚠️ **A fleet grep of 2,177 Stop-feedback messages found ZERO naming two hooks — because they arrive as
TWO MESSAGES, not one.** Do not re-run that search and conclude the bug is absent; it measures what the
operator sees, not what fires.

**THE SHAPE, determined by evidence:** suppress **only** completion-assert's ledger/contra arm when
session-continue has already blocked on the same ledger facts — **keep D1–D7 (the shape arms)**.
Justification: 33/33 co-fires are the `false-done` arm and **zero** involve a shape arm, so a full
yield (mirroring boundary-handoff) would buy nothing extra and would silently drop close-shape
corrections. Reuse `hooks/lib/continue-sentinel.sh` (`continue_sentinel_for "$cwd"`) exactly as
`boundary-handoff.sh:415-428` does, including its lib-unavailable fallback (skip, never wrongly
suppress).

### W5 · `a9ede190ee3b` — custody attribution — **DRIVABLE, NO OPERATOR DECISION**

Full analysis: `docs/research/stop-chain-wave2-2026-09-03/custody.md`.

Three consumers of `CUSTODY_OPEN` (`wrap-ledger.sh:1367/1257/1261/1442`, `operator-readout.sh:815-822`,
`completion-assert.sh:549-550`) use the cwd-keyed unattributed count; `session-continue.sh:542-577`
re-derives it pane-attributed. **No fourth consumer of the field exists.**

**The crux — an unattributable row — is already answered on trunk, twice, in writing:**
`bin/cc-custody:35-38` (POLARITY: over-count rather than silently drop, *chosen deliberately*),
`bin/cc-custody:44-46` (same rule for TTL), and `session-continue.sh:537-541` applies it to this exact
question — *"an unattributable row still counts, and the message HEDGES"*, pinned by
`tests/wake-floor.bats:584`. So: **`theirs` is dropped, `unk` is KEPT.** Porting a landed decision, not
making one.

Measured, so the unattributable class is not hypothetical: **441 open rows store-wide, 117 (26.5%)
carry neither `originatorPane` nor `notifyBack`** — all `cc-offload` cloud fires from a context with no
`ITERM_SESSION_ID`. This repo's own cwd key currently reads **0**, so the defect is **LATENT here** —
real by construction, not blocking a close today.

**Two traps that must not be discovered late:**
1. `CUSTODY_SRC` is a documented three-state oracle rendered at `wrap-ledger.sh:1441-1447` and cited in
   `docs/plans/CLOSE_INTEGRITY_2026-08-10.md:99,103`. Adding a `pane` state means updating the header,
   the `--full` case, AND that plan doc.
2. **The ledger memo key (`wrap-ledger.sh:376-381`) carries no pane id.** A *resumed* session keeps its
   transcript but gets a renumbered pane (memory `resumed-session-loses-terminal-identity`), so a
   pane-dependent count could be served under a stale identity. **The pane id must join `_wl_k`.**

**Tests that will break, and the fix:** `tests/wrap-ledger.bats:1763/1774/1784` and
`tests/completion-assert.bats:1142` stub `cc-custody` with argument-blind one-liners (`echo 2`,
`echo 0`). Replace with the `cust_shim` pattern that `tests/wake-floor.bats:526-541` already ships —
`list --json` replays an array and `count` answers `jq length` **from that same array**, so the shim
cannot disagree with itself. `tests/operator-readout.bats` is safe (it stubs the ledger, not the CLI).

### W6 · `d8147be371cd` — agent-report recovery — **CLOSE AS DUPLICATE; THE TOOL SHIPPED 25 DAYS AGO**

🚨 **This section was wrong when first written, and the correction is the most valuable finding in the
plan. Read the correction, not the original claim.**

**What I first wrote (WRONG, kept per INTEGRATE-never-overwrite):** *"13 Agent tool_use calls and every
tool_result is only a spawn ack… the report was never going to arrive… `agent_id` carries no transcript
uuid, so the tool cannot resolve its target… not buildable as specified."*

**What is actually true, measured:**

1. **It is not a defect at all — it is the `name:` parameter.** Over **341 Agent calls / 21 days /
   both transcript roots**: calls passing `name:` delivered a report **0 / 207**; calls WITHOUT `name:`
   delivered ≥500 chars **117 / 118 = 99.2%**. Passing `name:` makes the call a **teammate** spawn,
   whose contract has no return value; an unnamed call is a subagent, which returns normally. One input
   field decides it deterministically. Every one of my 13 calls passed `name:`.
2. **The mapping IS derivable.** `~/.claude*/teams/session-<lead-sid>/config.json` stores each member's
   name plus its VERBATIM prompt, and the member's transcript opens with that same prompt — an exact
   byte join, name → prompt → transcript.
3. **`bin/cc-agent-harvest` ALREADY EXISTS.** 342 lines, landed **`5e9ef347c` on 2026-08-09**,
   symlinked live into `~/.claude/bin/`, `tests/cc-agent-harvest.bats` **8/8 green**. Run against this
   very team it resolved all 8 members by name and harvested the three wave-2 reports I believed lost
   (readout2 20,189 chars · sidefx2 11,352 · blockers2 584). It refuses ambiguous joins with exit 3,
   having shipped a false attribution once on a prefix join.
4. **Also refuted:** "sends to already-dead agents return success" — the one clean instance
   (`stop-blockers`) returned `success:false, "No agent named … is reachable"`. I misread my own output.

**THE ONE REAL GAP, and it is ~10 minutes:** `grep -rn "cc-agent-harvest" skills/ commands/ hooks/
CLAUDE.md` → **zero matches**. The doctrine is documented three times — `skills/agent-teams/SKILL.md:75-80`,
`skills/research-subagents/SKILL.md:225-241` and `:253-256` (that last one is the manual recovery recipe,
written a month before I re-derived it by hand) — and **not one of them names the tool that does it.**
Fix = one pointer line in each of those two skills.

**Why this matters more than the row it closes.** The operator's question was whether this workflow
files more than it solves. Here it filed a row to build something that had been on disk, tested and
live, for 25 days — because a shipped tool nobody references is indistinguishable from a tool that does
not exist. That is a discoverability failure, and it is a strictly worse failure mode than a backlog
that grows.

**Disposition:** `cc-backlog done d8147be371cd` as duplicate-and-partially-refuted, then land the two
pointer lines. Do **not** build anything.

**Sequencing rule discovered with it:** the name→transcript join key is DESTROYED by shutdown — an
approved-shutdown member is removed from `config.json` and its transcript becomes permanently
unreachable by name (measured: `context2`, 638 KB, and the four operator-cancelled `stop-*` members).
**Harvest BEFORE teardown, never after.**

---

---

## OUTCOME — all six closed 2026-09-03 (INTEGRATE: the sections above are the plan as written;
## this section is what implementing it MEASURED, including where the plan was wrong)

| Wave | Row | Landed | Suites |
|---|---|---|---|
| W3 | `c9c3445be29d` | `bf6385171` | session-continue 32/32 |
| W1 (session-continue half) | `61a3b40d8695` | `4993f2b55` | telemetry 12/12 |
| W4 | `79e2b74796af` | `1416abc10` | completion-assert 121/121 |
| W1 (goal-inert half) + W2 | `0f4147dcb20b` | `8be512f22` | goal-inert-watch 28/28 |
| W6 | `d8147be371cd` | `ad4748584` | docs only |
| W5 | `a9ede190ee3b` | `a7b6d51bd` | wrap-ledger 97/97 · memo 24/24 |

⚠️ **W5 and W6's shas were corrected 2026-09-04 — as first written they resolved to nothing.** The
table originally cited `efe703403` (W6) and `5ecff6f14` (W5); neither is an object in this
repository at all, on any ref. Both changes ARE on trunk — verified by content, not by claim
(`git grep 'cc-agent-harvest --session' origin/main -- skills/`, `git grep 'CUSTODY_SRC="pane"'
origin/main -- scripts/wrap-ledger.sh`) — under `ad4748584` and `a7b6d51bd`, both asserted with
`git merge-base --is-ancestor <sha> origin/main`. The other four rows' shas were correct as
written. **The lesson is the one §W6 already teaches, applied to this table:** an evidence pointer
nothing can resolve is indistinguishable from evidence that does not exist, and a reader checking
this plan's DoD ("landed via the project-local `/ship`") would have found two of six waves
unverifiable. Cite a sha only after it answers `git merge-base --is-ancestor`.

### Four things the plan did not anticipate, each of which changed the work

1. **W1 — the wake floor's FIRE was silent too, not just its abstentions.** The plan (and the filed
   row) framed this as missing telemetry on *abstain* paths. Probed against trunk with a pane
   identity present and no sentinel armed, the hook emitted `{decision:"block"}` and wrote **zero**
   IDL rows. The single loudest disposition the hook has was indistinguishable from never running.
2. **W1 — the test that pinned the gap was measuring something else, and its verdict was
   PANE-DEPENDENT.** `tests/session-continue-telemetry.bats` never pinned `ITERM_SESSION_ID`, so
   `_ouid` was whatever pane ran bats: under a stripped environment the floors return early at the
   `_ouid` guard, under a real pane they run to completion and the wake floor BLOCKS. Both produced
   the same green from different paths, and neither was the "disarmed steady state" the test is
   named after. Re-scoped to the sentinel contract it was written for, and the pane is now pinned.
3. **W4 — the prescribed guard shape covers only 22 of the 33 co-fires.** §W4 said to reuse
   `continue_sentinel_for "$cwd"` as `boundary-handoff.sh:415-428` does. Measured while
   implementing: session-continue's two FLOORS run *exclusively* on the branch where that sentinel
   does NOT exist (`if [ ! -f "$f" ]`), so a sentinel-only guard leaves the 11 `ship-floor` co-fires
   live. Keying on the ship floor's sidecar fails the other way — it is latched per HEAD-sha, so it
   would silence completion-assert for every later Stop on that sha, when a done-claim is exactly
   what should still be caught. **Shipped instead: a per-Stop marker** written when session-continue
   blocks and cleared by it at the top of every Stop. Because session-continue is chain position 4
   and completion-assert position 6 (`settings.json` — configuration, not a timing sample), its
   presence means "on THIS Stop" with no wall-clock window. A TTL was rejected: it fails CLOSED
   (wrongly suppressing) on two fast Stops.
4. **W5 — the argument-blind stubs would have passed VACUOUSLY, not failed.** §W5 predicted
   `tests/wrap-ledger.bats` would BREAK on the attributed reader. It would not have: `echo 2`
   answers `count` and `list --json` identically, jq fails on `2`, and the reader falls through to
   its unattributed path — so the suite stays green while never exercising the new arm. The danger
   was a silent vacuous pass, not a red.

### One gate red, and it was real

`scripts/tsv-pad-lint.sh` refused the goal-inert land: the new `IFS=$'\t' read` of `goal_liveness`'s
output carried no padding def and no exemption. Discharged by reviewed exemption (`d691234e5`) —
every non-last cell of that producer is a literal or a `|tostring` number, and the only
empty-reachable cell is the goal condition, which is LAST. **Found while discharging it:**
`scripts/wrap-ledger.sh` reads the same producer with the identical line at `:648` and was already
exempt, but that entry's argument described only `count_blocking_decisions` — the goal read had been
riding a reason that does not mention it. Argument widened to discharge both readers explicitly.

### W6's real finding, restated because it outlives the row

The row asked to BUILD `cc-agent-harvest`. It had been on disk, tested and live, for **25 days**
(`5e9ef347c`). `grep -rn "cc-agent-harvest" skills/ commands/ CLAUDE.md` returned **0** — the
doctrine is taught in three places and none named the tool. A shipped tool nothing references is
indistinguishable from one that does not exist, and that is a strictly worse failure than a backlog
that grows. Pointers landed in `efe703403`, both carrying the sequencing rule that makes the tool
useless if missed: **harvest BEFORE teardown** — an approved shutdown removes the member from
`config.json` and the name → prompt → transcript join dies with it.

---

## Definition of done

- W1–W5 each: red-proven (a control that is green on both branches AND an arm that moves), suite green,
  `shellcheck -x` clean, landed via the project-local `/ship`, backlog row `done`.
- W6: row closed by evidence with the reasoning recorded.
- No claim of a fixed defect without a test that distinguishes the branches — the standing lesson from
  `c18a55c09`, where "not reproducible here" was written after a probe structurally incapable of
  reproducing it.
