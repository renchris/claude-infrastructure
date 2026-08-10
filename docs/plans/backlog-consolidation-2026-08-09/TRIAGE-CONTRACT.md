# Backlog cluster triage — shared contract

You are triaging one disjoint slice of a 460-item work backlog against **today's actual repository
state**. Today is **2026-08-09**. Items were filed over the last ~6 weeks; many assert facts that
have since decayed. Your job is to decide, per item, whether it is still true — and then to fold the
survivors into ONE long-horizon master effort.

## Hard constraints

- **READ-ONLY.** Do not edit any file in any repo. Do not run `cc-backlog` mutating verbs
  (`add`/`done`/`block`/`reopen`/`claim`). Do not commit, push, or land. The lead applies every
  mutation after synthesis — 10 agents mutating one JSONL store concurrently would corrupt it.
- **The machine is under load** (4 kernel watchdog panics in the last week, 15+ live sessions).
  **Do NOT run test suites, builds, installs, or anything long.** Verification is git reads, file
  reads, and grep. A `bats` run is forbidden; `git log` on the test file is the substitute.
- Primary repo: `/Users/chrisren/Development/claude-infrastructure` (trunk = `origin/main`).
  Work from a read-only stance; never `cd` into a worktree and mutate it.

## Per-item verdict — the procedure

Each item's `title` field IS its full body (there is no separate description field). Items cite
anchors: shas, file paths, test names, symptom strings, and other 12-hex item ids. Use them.

For each item, run the cheapest check that could **refute** it, in this order:

1. **Cited sha** — `git cat-file -t <sha>` / `git merge-base --is-ancestor <sha> origin/main`.
   A sha that is now an ancestor of trunk means the described state has probably moved on.
2. **Cited path** — does it still exist at that path on `origin/main`
   (`git ls-tree origin/main -- <path>`)? Moved/renamed/deleted is strong decay evidence.
3. **Subject churn** — `git log --oneline origin/main --since=<item's lastTs> -- <cited path>`.
   Commits touching the subject AFTER the item was filed are the single best staleness signal.
   Read those commit messages; one of them may literally be the fix.
4. **Symptom grep** — grep the current tree for the defect the item describes. If the guard,
   the fix, or the invariant is already present, the item is dead.
5. **Cross-references** — if the title names another 12-hex id, look that item up in the store
   (`cc-backlog list --all --json | jq '.[]|select(.id=="<id>")'`) and read the relation.

Then assign exactly one verdict:

| verdict | meaning |
|---|---|
| `PRUNE` | dead — already fixed, superseded, duplicate, or its premise is refuted. Cite the evidence (a sha, a path, a landed commit subject). |
| `UPDATE` | the core work is live but the item's stated facts/remedy are stale. Say what changed and what the item should now say. |
| `KEEP` | premise verified still true today. Say what you checked. |
| `MERGE` | subsumed by another item in your slice or by your master item. Name the canonical id. |

**A `PRUNE` needs positive evidence.** "I could not find the file" when you could not run the check
is `KEEP` with a note, never `PRUNE` — an unread premise is "I could not tell", not "it is finished".

## The master item — the actual deliverable

Fold every `KEEP` + `UPDATE` in your slice into **one** long-horizon master effort (at most three,
and only if genuinely disjoint — justify each extra one). This is not a list; it is a single
coherent effort a fresh session could drive for many hours, written against today's tree.

Each master item needs:

- **Title** — one line, states the outcome, not the category.
- **Encompasses** — the exact item ids it absorbs.
- **Why this is one effort** — the shared root cause or shared surface. If you cannot name one,
  you have a list, not a master item; split or say so.
- **Impact, argued from evidence** — what it unblocks. Strongest signals: does it block the land
  rail (making trunk red blocks *every* land), how many other items does closing it retire, is it a
  recurring condition, does it touch an enforcing store (`settings.json`, hooks, launchd, `bin/`).
- **DoD** — the finished, verified, landed state.
- **Falsifier** — ONE shell command whose exit 0 means "this whole effort is no longer needed".
  This is load-bearing: it is how the item re-validates itself at fire time weeks from now.
- **First move** — the concrete opening step for the session that picks this up.
- **Ordering within the effort** — the sub-steps in dependency order, ids attached.

## Output

Write ONE markdown file to the absolute path given in your task line. Nothing else is delivered —
your prose in chat is invisible. Structure:

```
# <cluster> — triage vs origin/main @ <sha you measured>

## Summary
counts: PRUNE n / UPDATE n / KEEP n / MERGE n   (must sum to your slice size)

## Verdicts
<12-hex id> | PRUNE | <evidence: sha, path, or landed commit subject>
...one line per item, every item in your slice, no omissions...

## Master item(s)
### M-<cluster>-1 — <title>
Encompasses: <ids>
Why one effort: ...
Impact: ...
DoD: ...
Falsifier: `<command>`
First move: ...
Order: 1. <id> ... 2. <id> ...

## Notes for the lead
<anything that changes how the lead should merge this with other clusters — cross-cluster
duplicates you spotted, an item that belongs in someone else's slice, a landmine>
```

Every item id in your input must appear exactly once in `## Verdicts`. That is the completeness
check the lead will run.
