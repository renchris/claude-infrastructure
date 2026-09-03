---
status: open
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

Work: add `log_idl`/`abstain` calls to every exit path of `wake_floor` (`session-continue.sh:416-697`)
and wire `hooks/lib/idl-log.sh` into `goal-inert-watch.sh` (which does not call `idl_init` at all —
check this first; it may be a larger change than one line).

⚠️ **Check before landing:** any consumer that counts IDL rows or asserts the ABSENCE of these hooks.
`mechanical-assignee 1` proves new reasons do show up in production immediately.

### W2 · `0f4147dcb20b` — goal-inert-watch cannot see "stopped evaluating" — **DRIVABLE after W1**

Gate 2 (`goal-inert-watch.sh:120-128`) requires the LAST `goal_status` attachment to still be the arm
sentinel with `met:false`. A goal that evaluated once then went inert writes a non-sentinel last
record ⇒ the hook abstains forever. It detects only *never-evaluated-since-arming*, never
*stopped-evaluating* — the failure it exists for.

**The threshold is NOT a new value choice.** Gate 3b already ships one: *≥2 real typed user turns
since the arm sentinel* (`:137-153`, and `:35-38` explains why 2 and not 1 — a single interrupt must
not fire it). Re-anchor the same threshold on the newest evaluation rather than on the arm sentinel.

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

**Frequency, measured honestly:** only **3 of 2,542** typed operator messages (≤4 KB, command bodies
excluded) carry a kill phrase. An earlier count of 183 was inflated by `/ship` command text — police
that denominator. So this is *rare but silent*, and it is a deliberate operator override: low
frequency, high stakes.

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

### W6 · `d8147be371cd` — agent-report recovery — **CLOSE IT; NOT BUILDABLE AS SPECIFIED**

Measured in the originating session's own transcript: **13 Agent tool_use calls, and every single
`tool_result` is only the spawn ack** (`"Spawned successfully… agent_id: <name>@session-<lead-sid>"`).
There is no second `tool_result` carrying a report. The report was never going to arrive — this is
fire-and-forget by design in this runtime, not a dropped delivery.

And `agent_id` is `name@lead-session`, which contains **no transcript uuid**, so `cc-agent-report <name>`
cannot resolve its target. Yesterday's recovery worked by mtime proximity + content matching, which is
a heuristic, not a mapping.

**The real remedy already exists and is already documented.** The `research-subagents` skill's field 7
is a *mandatory Delivery contract*: name the absolute artifact path each subagent writes, "because a
subagent's prose is invisible and only a file is delivered". This wave proved it — every brief named an
output path and every report arrived. The defect was non-compliance, not a missing tool.

**Disposition: `cc-backlog done` with that reasoning.** Optionally strengthen the skill's wording from
"should" to a refusal, but do not build the tool.

---

## Definition of done

- W1–W5 each: red-proven (a control that is green on both branches AND an arm that moves), suite green,
  `shellcheck -x` clean, landed via the project-local `/ship`, backlog row `done`.
- W6: row closed by evidence with the reasoning recorded.
- No claim of a fixed defect without a test that distinguishes the branches — the standing lesson from
  `c18a55c09`, where "not reproducible here" was written after a probe structurally incapable of
  reproducing it.
