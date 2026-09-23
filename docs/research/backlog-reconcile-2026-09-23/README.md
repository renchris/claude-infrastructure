# cc-backlog reconcile — every live row adjudicated against current repo state, 2026-09-23

The operator asked for an end-to-end pass rather than per-row expiry probes: read every live row
against what is actually true on each repository's trunk and on this machine today, then update,
consolidate and prune. This is that pass. Per-row outcomes are in `outcomes.tsv` beside this file;
the evidence each change was applied on is stored in the ledger itself (every `done` record carries
it). This follows `docs/research/drain-100p-q5-pilot-2026-09-22.md`, whose finding shaped the rules.

## Result

| | before | after |
|---|---|---|
| live rows | 310 | **217** |
| blocked on the operator | 298 | **193** |
| open for agents | 12 | **24** |
| blocked rows unchecked for more than 14 days | 183 | **88** |
| rows the drain lane can pick (`drain-pick.sh --project all`) | 0 | **12** |

**167 changes applied:** 54 closed as done, 27 closed as moot, 12 merged as duplicates, 45 text
updates, 13 rows re-worded as plain decisions, and 16 released back to the agent queue. **0 failed.**
Read back through a separate `cc-backlog list --all --json`, every changed row showed the intended
status (0 mismatches) and every rewritten text was visible.

## How

1. **Scout inline.** Exported the live fold (310 rows over 9 projects), fetched all 8 repos once so
   no agent races a fetch lock, and clustered rows into 25 topic batches of at most 16 (condition key
   first, then title-token overlap) so duplicates share an adjudicator.
2. **Adjudicate (25 agents, read-only).** Each read its batch file and gave every row one of seven
   dispositions: CLOSE_DONE · CLOSE_MOOT · MERGE · RELEASE · UPDATE · ESCALATE · KEEP. Evidence had to
   be a command run in that pass against the trunk ref (never the local tree: voiceink was 214 behind,
   reso-qa-runner 32) or against live machine state.
3. **Verify (up to 25 agents, one skeptic per batch).** Every proposed change was re-run and refuted
   where possible: the evidence did not reproduce, it tested something the row merely *mentions*, a
   future date gate, a release of a step that needs a credential, sudo, GUI, physical act or operator
   value call, or an update that drops a constraint. When uncertain: refuse.
4. **Consolidate (2 agents).** A cross-batch duplicate sweep over the survivors, with its own skeptic:
   12 merges proposed, 8 upheld.
5. **Apply (lead, not agents)** via the ledger's own verbs: `done --evidence`, `block --needs`,
   `unblock`. 52 agents in all, 0 errors, 310/310 rows got a verdict.

## The application bar tracks blast radius, not the adjudicator's self-rating

A skeptic that re-ran the evidence and upheld a change is the stronger of the two signals, so the
confidence floor was set by how much each change can hide:

- **close / merge** (hides work from the operator): skeptic upheld **and** confidence ≥ 70
- **update / escalate / release** (rewrites text or returns a row to agents): upheld **and** ≥ 60

The first cut used ≥ 80 for everything and dropped 65 upheld changes; sampled skeptic receipts in
that band were concrete (e.g. re-running `cc-memory-rotate --dry-run` → `verdict=noop size=22276 <
rotate_at 24722`; `jq` over all five `settings.json`). Everything stays reversible with `reopen` or a
re-block. **48 changes the skeptic refused were not applied**, and those rows are unchanged.

**Guards held against both agents:** the three rows the Q5 pilot proved live were barred from any
close. One fired: `981a403a05fa` (an open operator decision on where a failed land files its row)
was proposed for closure and upheld, and the guard kept it open.

## A defect found in the apply step, and fixed

`unblock` changes a row's status and leaves its **title** as it was. The first release of
`13e52feb1472` turned a row titled *"Set TURSO_AUTH_TOKEN_ASHBURN_GROUP…"* into open agent work, but
the adjudicator had established that the credential half was already done: the token is minted into
SSM and seven scripts resolve it at runtime, and what remains is `scripts/db-backup.ts` and
`scripts/check-pitr-status.ts` still reading only `process.env`. A worker reading that title would
see a credential chore and hand it straight back.

The rows' condition keys are **shared group keys** (`master-operator-gated`,
`master-account-facts`), so an `add --condition` retitle would hit the whole group. The dispatcher's
brief composer carries `needs` to the worker (`bin/cc-dispatch:1272`), so the fix was
`block --needs "AGENT WORK … <corrected task>"` then `unblock`. Verified: **16 of 16 released rows read
back OPEN with the corrected task in `needs`.**

**Residual, stated:** `cc-backlog` has no per-row retitle verb for rows in a shared condition group,
so a released row's title still carries its old wording; the current task lives in `needs`.

## What was not done

- **The 193 blocked rows that remain** are what the skeptic could not refute as still-needing-you,
  plus 48 where it refused the proposed change. The 48 are not verified live, only not verified dead.
- **The 12 now-eligible rows are not yet drained.** The lane restarted as recycle #333 on
  2026-09-22 is the consumer. Whether it spawns is subject to the spawn-fail rate recorded in
  `docs/research/backlog-drain-audit-2026-09-22/a7-worker-path.md`.
- **Released rows outside the dispatch set** (personal, sevenrooms-bridge, voiceink) are now
  correctly *open*, but no lane drains those projects.

## Re-derive

```
cc-backlog list --all --json | python3 -c 'import sys,json,collections; print(collections.Counter(r["status"] for r in json.load(sys.stdin)))'
bash scripts/drain-pick.sh --project all --top 30 | grep '^eligible'
```
