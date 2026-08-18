# Repo-keyed DoD crosstalk — the fix needs an identity this tree does not record

Row `4de3d0f9c0e1` (master-session-lifecycle), "review #10b". Investigated 2026-08-18.

**Verdict: the defect is REAL and reproduced; the remedy is NOT buildable from state this tree
records.** This is filed as the design question rather than shipped as a read-side heuristic,
because every rule buildable today either keeps the crosstalk or re-breaks the worktree hop that
`hooks/lib/dod-path.sh` exists to make work.

## 1. The red proof

Two worktrees of one repo, both freezing their own scope. `tests/dod-path.bats` cases 7–8, gated
off by default (they are red on purpose):

```
$ CC_DOD_CROSSTALK_REDPROOF=1 bats tests/dod-path.bats
1..9
not ok 7 CROSSTALK: wave B's REMAINDER counts ONLY its own frozen items, not a concurrent wave A's
# wave B summed a concurrent sibling's boxes: REMAINDER=2 (want REMAINDER=1)
not ok 8 CROSSTALK: a concurrent wave A's frozen scope is not injected into wave B as binding
# wave B was handed a concurrent sibling's scope as binding
```

The axis is pinned inert on the legacy side — neither worktree has a legacy path-hash file, so both
observations come from the repo-key store alone. Case 1 in the same file (the succession hop) stays
green throughout: **the two behaviours are one mechanism observed from two sides.**

## 2. Live blast radius, measured

| Fact | Value |
|---|---|
| worktrees of this repo sharing one scope file | **101** (`git worktree list`) |
| captures in `~/.claude/autonomy/dod/repo-86523465733a9afe.md` | **15** distinct frozen scopes, 2026-08-10 → 08-16 |
| unchecked `- [ ]` boxes in that file | **0** |

**Corrected measurement — the row's two halves are not equally live.** The REMAINDER-inflation half
is *latent*: real in the mechanism (case 7), but zero live captures carry checkboxes, so nothing is
currently being red-runged by it. The **injection half is active every session**: `dod-persist.sh`
SessionStart `cat`s the whole file, so a session in any of those 101 worktrees is handed all 15
waves' contracts under the frame *"Every 'Scope (frozen):' line below is binding … do NOT narrow
scope or declare done until ALL of it is met."*

## 3. Why no read-side rule fixes it

The reader would have to separate *a wave from its own successor*. Every discriminator available:

| Candidate | Why it fails |
|---|---|
| key on git toplevel | exactly the pre-W3 scheme the lib was built to replace — reds case 1 |
| key on branch | a recycle to a fresh worktree off origin/main is a NEW branch, so predecessor ≠ successor — reds case 1 the same way |
| writer liveness (inherit only a dead wave's scope) | the recommended pattern **fires the successor before the predecessor exits** (`MEMORY.md` → *Fire the recycle first*), so the predecessor is alive at the successor's SessionStart and the successor would exclude its own inheritance — reds case 1 |
| recency / last-writer-wins | `get` already does this; REMAINDER *sums*, and recency cannot tell a sibling's newer capture from a parent's |

## 4. The two things that would have to exist first

1. **Per-capture provenance.** `persist_dod` (`hooks/dod-persist.sh:82-93`) records the writing cwd
   only in the file HEADER — i.e. for the *first* writer. Each capture block is `## <ts> (<label>)`
   and carries no worktree, session id or wave. **No reader can attribute a capture to a wave**,
   so no read-side rule has an input to key on, however clever.

2. **A lineage token.** The nearest existing record is the fired-peer stamp
   (`scripts/handoff-fire.sh` `mark_fired_peer`, schema 2), and it does not close the gap twice
   over:
   - it records `cwd` (the fired session's OWN) and `firedBy` (the firing **pane id**) — never the
     firing session's cwd, which is the edge a worktree-scoped store needs;
   - it is written only when `WANT_SELF_RETIRE=1`, and `handoff-fire.sh:7358` reads
     `[ "$SELF_RETIRE" = 1 ] && [ "$RECYCLE" = 0 ] && WANT_SELF_RETIRE=1` — **so `--recycle`, which
     CLAUDE.md names the DEFAULT succession ("Reach for Recycle first"), writes no stamp at all.**

   `~/.claude/logs/handoffs.jsonl` is written for every fire but carries `firing_sid` / `prev_sid` /
   `target_pane` — session and pane ids, never a cwd pair, and never the fired session's own id.

So the lineage edge *predecessor-worktree → successor-worktree* is recorded **nowhere**, and least
of all on the path that carries most successions.

## 5. Recommendation

Sequenced, because (1) is a precondition for any version of (2):

1. **Stamp provenance at capture** — add the writing toplevel (and session id when known) to each
   `## <ts>` block in `persist_dod`. Strictly additive, INTEGRATE-safe, changes no reader today.
2. **Mint a lineage token on the succession paths**, `--recycle` included, recording the *firing
   cwd* alongside the fired cwd — then a reader can inherit along the lineage and exclude everything
   else. Only at that point do cases 7–8 become fixable; unskip them there.

**Adjacent finding, separate row.** Independent of wave identity, SessionStart injects the file's
*entire* monotone history as binding — 15 contracts today, unbounded tomorrow. Even a legitimate
successor inheriting from a legitimate predecessor is handed every scope the repo ever froze. That
is a bounding question about the injection, not about identity, and is fixable on its own.
