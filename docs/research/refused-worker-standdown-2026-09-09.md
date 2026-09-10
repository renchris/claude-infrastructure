# A refused duplicate worker DOES stand down — cc-backlog `b03eb3f28845`, REFUTED

**Verdict: the item's premise does not hold at trunk, and the remedy its title implies is refuted by
cost.** Filed 2026-08-07 as *"a worker refused by the claim lease keeps RUNNING: 15 clones alive in
one worktree, deadlocked on each other's dirty files, burning quota (worker-claim-gate stops the
WRITE, nothing stops the SESSION)"*. Measured 2026-09-09 over the whole surviving transcript corpus
(2,818 transcripts, 4 config roots):

| the item's claim | measured | instrument |
|---|---|---|
| 15 clones alive in one worktree | **max 3**, all-time, over 138 dispatch worktrees / 204 sessions | simultaneously-active-minute sweep |
| deadlocked on each other's dirty files | **0** post-refusal writes ever succeeded (11/11 refusals) | `tool_use` paired to its `tool_result` |
| the session keeps running | median **2.4 min / 6 tool calls** after the refusal; 8 of 11 stood down inside 11 min | first delivered deny → last record |

## Why the session stops, when the plan said a message cannot

`S4.1` sited the gate at the write because *"a mailbox stand-down needs a turn boundary a session deep
in a tool loop never reaches"* (`GROUND_UP_DISPATCH.md:615-628`, the dead-letter shape). That
reasoning is correct and it also explains the outcome nobody predicted: **a `PreToolUse` deny IS a
turn boundary, by construction.** The refusal is not mailed to the session — it is returned as the
`tool_result` of the call the session just made, so the model reads it inside the loop it is deep in.
The three consumers (`check-edit-boundary.sh` on Write/Edit, `agent-teams-enforce.sh` on Agent,
`validate-bash.sh` on pane-spawn Bash) therefore deliver a message the mailbox never could. Nothing
mechanical stops the process, and nothing needs to.

## The one long post-refusal run is a session that was RIGHT to continue

`0edc7e64` (wt-`f526558625b0`) ran **1,079 min / 126 tool calls** after its refusal — 20× every other
case, and the whole of the item's residual harm. It is not a duplicate. Its refusal was the
`done-latched` arm on a **pane spawn**, raised because another host had marked the item done while
this session was still landing its own work; its post-refusal tool calls are `ship-land.sh`,
`deploy-live.sh`, `wrap-ledger.sh`, `cc-backlog needs` — the land, and it wrote nothing. It spawned no
pane, so the refusal was honoured; only the *stand down and retire* half was ignored, correctly.

**That is what refutes the obvious remedy.** Denying every tool to a convicted session (the one
actuator that would "stop the SESSION", and the only one available without a C10 settings change,
since `validate-bash.sh` is already registered on `PreToolUse|Bash`) would have bricked an 18-hour
legitimate land and delivered nothing: the harm it would prevent is a median of 6 tool calls. Same
inversion `worker-claim-gate.sh` already records for the refusal budget — the unsafe direction is not
the one the parallel suggests.

## Instrument notes — two contamination traps, both hit here

1. **`grep 'DUPLICATE WORKER'` over transcripts answers 67; the true population is 11.** 41 hits are
   sessions whose cwd is not a dispatch worktree at all (the gate cannot refuse them — it keys on
   `wt-<12 lowercase hex>`), and 14 are sessions that merely **read the hook source**, so the string
   arrives in a `tool_result` as the output of a `cat`. The session writing this document is one of
   them. Same shape as `pgrep-f-matches-agent-briefs` and *census matches itself*: the predicate must
   be that the `tool_result` **starts with** `DUPLICATE WORKER`, i.e. is the deny as delivered.
2. **A `tool_use` record is an ATTEMPT, not a write.** Counting Write/Edit `tool_use` blocks made two
   duplicate pairs look like both sessions wrote (`16319f4234a3` 11 and 2; `7e2df754d0b8` 1 and 12).
   Pairing each to its `tool_result` inverts it: the lease holder's writes all landed (11/11, 12/12)
   and the duplicate's were all denied (2/2, 1/1). **The gate works, verified by content.**

## The control arm — because "max 3" is otherwise unfalsifiable

The incident worktrees are gone (`wt-191d4d056c98`, `wt-149789b69fc4`, `wt-23eccae755a9`: 0
transcripts), so there is no pre/post arm and none can be reconstructed. The instrument is instead
positive-controlled on a population that CAN exhibit the harm: the same sweep reports **32**
simultaneously-active sessions in one project dir, 14 in `claude-infrastructure`, 12 in `wt-pool-8`.
It counts far past 15. Restricted to the population the lease governs it reports 3. So the bound is a
property of the population, not a ceiling of the measurement.

**Honest residual:** the corpus is perishable, so this cannot speak to 2026-08-07 itself — it speaks
to every dispatch worktree that has existed since. Re-derive rather than quote (`published-figure-decays-with-its-source`):

```
rg -l 'DUPLICATE WORKER' ~/.claude*/projects/*/*.jsonl        # then apply trap 1's predicate
```
