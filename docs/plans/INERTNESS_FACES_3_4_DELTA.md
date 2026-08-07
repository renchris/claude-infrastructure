---
status: complete
---

# Inertness faces 3–4 — the delta after a duplicate dispatch

**Read this before touching faces 3–4 again.** The work is essentially DONE on trunk; this file
exists so nobody rebuilds it a third time.

## What happened

`cc-backlog` dispatched the same work **twice**: `97f16b6709fa` (this session) and
`6078392359ac` (a sibling). Both built faces 3 and 4 of
`docs/research/inertness-generator-2026-08-07.md` §3, in parallel, without either knowing.

The sibling landed first, and its implementation is on trunk as §10 of the research doc:

| Face | Sibling's landed artifact |
|---|---|
| 3 | `scripts/deploy-migrations.sh` (PHASE 1 materialise every converge + PHASE 2 one-shot migrations), `migrations/0001-migrations-ledger-scaffold.sh`, `migrations/0002-curl-gate-scope-registration.sh`, `migrations/README.md`, `tests/deploy-migrations.bats`, wired into `scripts/deploy-live.sh` via `CC_DEPLOY_MIGRATIONS` |
| 4 | the **`🚀`** rung in `scripts/wrap-ledger.sh` (`LIVE`, `LIVE_SRC`, `LIVE_LAG`, `MIG_FAILED`), rendered by `hooks/operator-readout.sh` |

**This session's parallel build was DISCARDED, not merged** — it is preserved on branch
`superseded/wt-97f16b6709fa-duplicate` (10 commits, 114 tests green) purely as an audit trail. Do
not resurrect it. Two places where the sibling's design is genuinely better, and why:

1. **The rung is BUDGETED.** Theirs fires only on a *breach* of `WRAP_LIVE_BUDGET_COMMITS` (25) /
   `WRAP_LIVE_BUDGET_MIN` (60); lag inside the budget is a normal `✅` carrying a note. This
   session's `🚚` fired on any lag at all, which would have fired at nearly every close in the
   minutes after a land — an alarm that always fires carries no bits.
2. **The applicability gate is `remote.origin.url` byte-equality**, not `--git-common-dir`. Simpler,
   and it correctly covers a *clone* of the live repo as well as a linked worktree.

One place this session's independent derivation added something the sibling's did not have, and it
is the reason this file is not just an obituary → see below.

## The delta this session landed

Faces 3–4 reached the ledger but **not every enforcing store**. Verified against `origin/main`
before writing a line — `operator-readout.sh` already had `🚀` (9 matches), so that was NOT a gap
and nothing was written there:

1. **`hooks/completion-assert.sh` — the false-done guard was never taught the rung.** Every term in
   its contradiction arm read a fact about a *git ref*: dirty, unlanded-content, DoD remainder. So a
   close saying `✅ Complete & live on trunk` passed cleanly with `DIRTY=0 UNLANDED=0 REMAINDER=0`
   while the live layer was past its converge budget and still running the old bytes. **The guard
   built to catch a false done was structurally blind to the largest false-done class in this repo.**
   That is the generator's own §2.1 partition missing a member: this hook enforces nothing about the
   machine, yet it decides what a session may *call* done — so a conclusion could reach the ledger
   and still not reach the guard, which is how eight correct analyses each closed green.
   It **consumes the ledger's `RUNG=🚀` verdict rather than re-deriving breach** (the budget
   predicate is `wrap-ledger`'s; two auditors over one population with no shared state model is the
   shape that lets this bug class survive). `LIVE_SRC=behind` is deliberately NOT sufficient —
   inside the budget that is the normal state for the first minutes after a land.

2. **`CLAUDE.md` — the resident policy did not carry the rung its own ledger computes.** The ladder
   read `⛔ > 📤 > 🔧 > 📦 > 👤 > ✅` while `wrap-ledger.sh` had been emitting `🚀` since the
   sibling's land. Two oracles disagreeing, in the one file every session reads.

## What is deliberately NOT done

- Faces 1–2 remain the deploy lane's (`docs/plans/DEPLOY_LANE_GROUND_UP.md` T0–T3).
- The C10 rescope §3 calls *"the one clause a human must ratify"* is still unratified, and the
  sibling's runner honors that: a `c10`-class migration is staged and filed, never executed.

## The second delta — the rung reached the ledger's RENDERERS but not its ROUTERS (2026-08-07)

Re-ran the check this file's own lesson prescribes (`git ls-tree origin/main` for the named
artifacts, **at land time**) before writing anything: both items above are on trunk, and
`~/.claude/CLAUDE.md` (a real file, not a symlink) carries them too. The gap was one store further
out. `wrap-ledger.sh` can emit five rungs; the docs that tell a session what to **do** with one had
drifted from the script that produces it:

| Store | State found | Why it was load-bearing |
|---|---|---|
| `commands/wrap.md` | ladder read `⛔ > 📤 > 🔧 > 📦 > ✅`, and "if the ledger says 🔧 or 📦, the work is not done" | the **pull-path renderer** — the surface an agent runs *on purpose* to check itself. `🚀` matched neither term, so it fell through as done: **fail-OPEN**. Verified empirically that `🚀` *is* computed on this path (it needs the live checkout's git state + the migrations ledger, no session id — unlike `👤`, which the file already documents as unreachable here) |
| `commands/ship.md` §8 | "emit `✅ Complete & live on trunk` when `origin/<trunk>..HEAD == 0`" | minted the governing line from a **count**, bypassing the only thing that computes `🚀` |
| `.claude/commands/ship.md` | "`📦 → ✅` is earned at the land" | correct *inside* the budget — deliberately so, nobody should hang on the 600s converger — but silent on the breach, in the one repo where landed and running diverge |

### The guard, so the next rung cannot drift

Adding `🚀` was one edit to the producer and five to its consumers, made by hand, a session apart —
which is exactly why four landed and one did not. `tests/wrap-ledger.bats` §10 now derives the rung
set from `RUNG="…"` **in the producer itself** (never a hand-kept list) and asserts every emitted
rung reaches both ladders.

It lives in the *producer's* suite deliberately: `gate-select.sh`'s `naming()` maps a changed
`scripts/X.sh` to `tests/X.bats`, so the guard is **guaranteed selected by the only edit that can
create this drift**. A standalone `tests/rung-ladder-parity.bats` would have ridden clause (e)'s
token match instead and been inert exactly when it mattered. The other direction is covered too —
`CLAUDE.md` and `commands/*.md` are index files (`gate-select.sh:174`) ⇒ FULL.

Three properties keep it from being decoration: the extractor is pinned to the **set** (5 rungs by
name), so a silently-empty extraction cannot pass vacuously; the ladder anchor must match **exactly
one** line per doc, so it cannot go green about the wrong subject; and both mutation controls —
dropping `🚀` from a **copy of the real doc**, not an approximation — go red. The assertion is
emitted ⊆ documented, not equality: `⛔`/`📤` are model-state overlays the script never emits.

**Status flipped to `complete` here for a reason.** `find-plan.sh:53` treats `in-progress` as OPEN,
so this doc left as-is would have re-emitted the item and bought a **third** dispatch of the very
work whose duplicate dispatch it exists to record.

## The generalisable lesson

**Two sessions each did correct, verified, adversarially-tested work, and one of them was pure
waste.** The wasted one was not detectably wasted at any point before the land — the rebase conflict
was the first signal, ~4 hours in. The cheap check that would have caught it exists and was skipped:
`git ls-tree origin/main` for the artifact names the plan intends to create, re-run **at land time
as well as at plan time**, because trunk moves under a long build. That is the
`fork-cost-proxies-and-mid-session-siblings` scar (*"a sibling landed this item's answer
MID-SESSION ⇒ re-sweep at LAND time"*) recurring with a whole session as the unit of loss rather
than one item. The dispatcher issuing one work-item under two ids is the upstream cause and is worth
its own fix.
