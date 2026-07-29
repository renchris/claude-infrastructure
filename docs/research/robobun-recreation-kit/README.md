# robobun recreation kit

Runnable scaffolding for a proactive GitHub agent account, derived from the reverse-engineering in
`../robobun-architecture-2026-07-28.md`. Read §6 (Corrections) and §0 (lead-run experiments) of that
doc before using any of this.

**What is copied vs invented.** The repo-side rails (`repo-rails/`) are near-verbatim from
`oven-sh/bun`, which publishes them. The orchestrator (`orchestrator/`, `worker/`) is **not** public
and is reconstructed from observable behaviour — every file says which it is.

## Order of operations

| # | Step | File | Notes |
|---|---|---|---|
| 1 | Repo rails first | `repo-rails/` | Do this before any agent runs. Prose alone does not constrain a model; the deny-hook does. |
| 2 | Author identity | `00-identity-setup.sh` | Plain User + fine-grained PAT + SSH **signing** key. Never grant merge rights. |
| 3 | Reviewer identity | — | Install `github.com/apps/claude`. Do **not** build one. Author≠reviewer or review is self-graded. |
| 4 | Queue | `orchestrator/schema.sql`, `token.ts` | Note the `lease` columns — see §0.1, Bun appears to lack this. |
| 5 | Task generators | `orchestrator/enqueue-reactive.sh` | Reactive stream is easy; the self-directed stream is the hard, private part. |
| 6 | Worker | `worker/run.sh` | One work item, start to finish. |
| 7 | **The gate** | `worker/gate.sh` | The load-bearing mechanism. Do not skip it. Everything else is downstream. |
| 8 | PR mechanics | `worker/open-pr.sh` | Evidence block is harness-written, never model-written. |

## The one thing not to skip

A PR ships only if the harness can prove **the test fails without the fix and passes with it** — by
replaying the pristine pre-fix tree from git, not a hand-edited approximation. If it cannot prove
that, it publishes a **structured abstention** from a closed vocabulary (`gate/abstention-reasons.txt`).
There is no third path. That is the whole anti-slop mechanism.
