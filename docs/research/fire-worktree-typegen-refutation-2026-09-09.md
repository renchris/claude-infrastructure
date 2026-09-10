# The fire path's missing `next typegen` — REFUTED (cc-backlog c0a5a968c79d)

**Verdict: the cited defect no longer produces the cited effect.** `handoff-fire.sh` still contains
no `typegen` step, and it does not need one: reso's `prepare` lifecycle now covers every route into
a checkout, including the cold-fire chain. Measured end-to-end on 2026-09-09, both arms.

## What the item claimed (filed 2026-08-21, observed by W5-B on pane 516)

> handoff-fire.sh provisions a worktree without `pnpm exec next typegen`, so every fired reso
> session starts with a red typecheck (8x TS2307 'cannot find module *.jpg').

The mechanism was real and is still real: `next-env.d.ts` is gitignored (reso `.gitignore:54`),
untracked on `origin/main`, and is the only file declaring the ambient image modules (via
`/// <reference types="next/image-types/global" />`). Eight tracked imports depend on it, all in
`src/app/(preview)/preview/heat/_data/photos.ts:39-46` — matching the item's reported "8x TS2307"
exactly.

## The measurement

A throwaway worktree cut from `origin/main`, then the **verbatim** cold-fire chain
(`scripts/handoff-fire.sh` `WT_INSTALL`, pnpm branch): `CI=true pnpm install --frozen-lockfile`.

| arm | `next-env.d.ts` | `tsc --noEmit` | TS2307 |
|---|---|---|---|
| after the cold-fire chain | written | rc 0 | **0** |
| control — same tree, file removed | absent | rc 2 | **8** |

The control is what makes the green informative: the instrument does see the red, and it sees
exactly the 8 errors the item named.

## Why it is discharged, and by what

Not by a change to `handoff-fire.sh`. The cure is in **reso**:

- `3a7f620df` (2026-08-05) added `next typegen` to `scripts/prepare-cached.sh` — but behind the
  codegen **cache-hit** path, so a cache hit skipped it. This is precisely why the item's
  2026-08-21 observation was real despite the fix predating it.
- `62d3515fb` (2026-09-04) moved it into an unconditional `ensure_next_env()`, called at
  `prepare-cached.sh:131` after both the cache-hit and full paths.

`prepare-cached.sh` is wired as the pnpm `prepare` lifecycle script (`package.json:15`), and
**`prepare` does run under `CI=true pnpm install --frozen-lockfile`** — verified directly on
pnpm 11.11.0 with a minimal fixture, not inferred. So the cold-fire chain gets typegen for free.

## Why `handoff-fire.sh` should NOT grow a typegen step

`WT_INSTALL` is deliberately package-manager-detected and framework-agnostic; its own comment
records the incident where hardcoding `pnpm install` broke every non-Node project. Adding
`next typegen` there would re-introduce framework knowledge into the generic fire path to
duplicate a guarantee the target repo already makes at its own chokepoint — the wrong side of
"enforce at the chokepoint".

## The residual, which is a DIFFERENT defect (re-filed)

The item's *effect* is still reachable, by another route and for a bigger reason. The pool path
(`WT_SETUP=pool`) is the fast path a reso fire prefers, and `cmd_claim` in reso's
`scripts/worktree-pool.sh` **provisions nothing** by design (start-latency R6, 2026-08-12) — no
install, no `prepare`. It hands back whatever `ensure` left.

Measured 2026-09-09 21:35, `~/.reso/worktree-pool.log`: slots 2, 3, 5, 7 and 8 fail to provision on
**every** ensure cycle — `pnpm install failed`, then `ERR_PNPM_RECURSIVE_EXEC_FIRST_FAIL … panda
ENOENT`. Five of ten slots sat at trunk with **no `node_modules` and no `next-env.d.ts`**, and a
claim's pass 1 takes a slot precisely because it is at trunk.

Two things this exposes, both worth fixing in reso, neither in this repo:

1. `prepare-cached.sh:131` — `run_full || { set_hooks_path; exit 1; }` exits **before**
   `ensure_next_env`. `next-env.d.ts` does not depend on panda codegen, so a codegen failure
   needlessly also costs the typecheck instrument.
2. `worktree-pool.sh:223,243,311` — the install runs `>/dev/null 2>&1`, so the actual failure is
   discarded and only the downstream `panda ENOENT` survives into the log. The failure does **not**
   reproduce interactively: the same command in slot 2 succeeded in 14s and left both
   `node_modules` and `next-env.d.ts`. It is launchd-context-specific, and undiagnosable until the
   output is captured.

## Instrument notes

- `git worktree add`/`remove` against the shared reso checkout was run with `core.bare` asserted
  before and after (`false` both times) — see memory `worktree-ops-can-bare-the-shared-checkout`.
- Slot 2 was repaired as a side effect of reproducing the failure and now holds both artifacts.
