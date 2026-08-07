# `migrations/` — registration state that lands in the same diff as its subject

Face 3 of [`docs/research/inertness-generator-2026-08-07.md`](../docs/research/inertness-generator-2026-08-07.md) §3:

> **Activations become migrations.** A registration / plist / settings change is executable,
> idempotent state landed **in the same diff as its subject** and run by the converger at deploy —
> exactly as schema migrations run at deploy rather than from a folder the DBA is supposed to visit.

## Why this directory exists

`docs/activation/pending-activation/` was an **advisory store** (§2.1): writing into it always
succeeded, reading out of it was discretionary. Under sustained production that is a diode — writes
pool, behaviour never changes. Measured 2026-08-07: 38 pending, 11 rotting past 24 h, 8 live-vs-repo
SSOT drifts, re-printed at every session start by an alarm that always fires.

A migration here is on the **enforcing** side: `scripts/deploy-migrations.sh` runs it from
`scripts/deploy-live.sh` at every converge, exactly once, and ledgers the outcome. Nobody has to
visit a folder.

## The contract

One file per migration, `migrations/NNNN-<slug>.sh`, executable, run in **lexical order**.

```bash
#!/bin/bash
# migration-class: mechanical
# <what this does, and the concrete failure it prevents>
set -uo pipefail
…
```

| Header field | Required | Meaning |
|---|---|---|
| `# migration-class:` | **always** | `mechanical` \| `c10`. **There is no default** — see below. |
| `# migration-step:` | `c10` only | One line naming the operator-owned step, filed to `cc-backlog`. |
| `# migration-run:` | `c10`, optional | The exact command the operator pastes. |

### The two classes

- **`mechanical`** — run at converge, unattended. For derived state the converger already owns:
  directory scaffolding, queue mirrors, ledger schema, link classes `install.sh` does not cover.
- **`c10`** — **staged, never run.** The runner files exactly one operator-owned step into
  `cc-backlog needs` (ids are event-keyed, so a re-file on every converge folds onto the *same* id —
  "paged once" is a property of the store, not of a damping window) and records it staged.

`c10` exists because §3's rescope of C10 — *"operator **runs**" becomes "operator **can revert**"* —
is explicitly the one clause the doc says a human must ratify, once. **That ratification has not
happened**, so the runner does not self-authorize it. A migration that touches `settings.json`, a
launchd plist, or credentials declares `c10` and waits for a human.

When the operator does ratify the rescope, promoting a migration is a **one-word diff**: change
`c10` to `mechanical`. The migration body is already written and already idempotent.

### An undeclared class is a hard error, never a default

Both defaults are wrong. Defaulting to `mechanical` means a forgotten declaration on a
settings-touching migration gets run unattended — a C10 breach. Defaulting to `c10` means a
forgotten declaration silently rejoins the hand-queue, which is the inert class this whole mechanism
exists to abolish. So an undeclared migration is recorded **FAILED** with a named culprit and paged,
and `tests/deploy-migrations.bats` asserts every migration in this directory declares a class — it
cannot reach a converge undeclared.

## Rules for writing one

1. **Idempotent by its own construction**, not merely by the ledger. The ledger prevents a re-run;
   an `rm -rf ~/.claude/autonomy` does not. Write it so a second run is a no-op.
2. **Exit 0 = applied (including already-applied).** Any non-zero is a real failure: it stops the
   ordered run, is retried on the next converge with a climbing `attempts` counter, and blocks the
   close protocol's ✅ (`scripts/wrap-ledger.sh` counts `failed/*.json`) until it clears.
3. **Bounded.** The runner caps each migration at `CC_MIGRATION_TIMEOUT_S` (120 s). Do not wait on
   anything unbounded; a converge tick is 600 s.
4. **Back up before you clobber.** The materialise phase keeps a `superseded/<name>.<epoch>` copy;
   do the same for anything you overwrite. Veto-after only works if the prior state survives.
5. **Never write repo-side.** The converger runs against a checkout it must not dirty — a
   `cp live -> repo` recreates a committed file as a local diff the next fast-forward must conflict
   on (`hooks/activation-watch.sh:249`).
6. `$CC_MIGRATION_REPO` and `$CC_MIGRATION_STATE` are exported into every migration; cwd is the repo
   root.

## Operating it

```
scripts/deploy-migrations.sh --status     # applied / pending / failed / staged
scripts/deploy-migrations.sh --dry-run    # decide + print, mutate nothing
scripts/deploy-migrations.sh --selftest   # 22 cases, throwaway tree, no side effects
```

The converger calls it with no arguments (materialise, then migrate) from
`scripts/deploy-live.sh` after `install.sh`.

## What `docs/activation/pending-activation/` is still for

The live queue is now a **derived view** of that directory — materialised on every converge, so the
REPO-ONLY and CONTENT-DRIFT classes are unrepresentable. It survives for the genuinely operator-owned
steps that predate this mechanism. **New** operator-owned wiring should be a `c10` migration instead:
it lands in the same diff as its subject, files itself once into a store a renderer already reads,
and promotes to automatic with a one-word change.
