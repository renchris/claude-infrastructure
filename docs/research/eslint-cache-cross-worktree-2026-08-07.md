# S2b — sharing reso's ESLint cache across worktrees is impossible, and the blocker is one field

**Date:** 2026-08-07 · **Backlog:** `216f429128a2` · **DoD:** `docs/plans/CONCURRENCY_PROGRAM.md`
§S2b (branch `concurrency-program`, commit `93d7e10b` — not on trunk)

S2b asks to *"stop N worktrees paying N cold full-tree lints"* and prescribes **"share the cache,
or scope the gate to changed files."** Both halves were tested against the live repo. The first is
**refuted twice over**; the second is **already done**. What follows is the disproof, so the next
worker does not build the thing that cannot work.

## The premise is true, and the cost is larger than filed

`reso-management-app` lints with `eslint src/ lib/ replicache/ --cache --cache-location
.eslintcache`. `--cache-location` is *relative*, so it resolves per-cwd and every worktree keeps its
own. Same worktree, same tree, identical verdict (1001 warnings, 0 errors):

| | wall | peak RSS |
| --- | --- | --- |
| cold | **229.8 s** | **3.32 GB** |
| warm (0 changed files) | **2.5 s** | **485 MB** |

92× wall, 6.8× memory. The item filed ~2.4 GB; measured peak is **3.32 GB**. The gap is the whole
cost of the lint: it is type-aware (`airbnb({typescript})` + `@typescript-eslint/no-unnecessary-
condition`), so a cache *miss* builds a TypeScript program and a cache *hit* skips the file before
the parser is reached. Census the same day: **78 reso worktrees, 2 holding an `.eslintcache`.**

## Refutation 1 — one shared cache file amortises nothing

ESLint keys cache entries on the **absolute** file path. From a real worktree cache:

```text
"/Users/chrisren/Development/.worktrees/wt-cc-001759-77337/src/app/.../AdminShell.tsx"
```

Point every worktree at one `--cache-location` and you get N disjoint key-spaces in one file: zero
hits, N × ~1 MB of growth, and — because `file-entry-cache` rewrites the *whole* file at exit with
no locking — two concurrent lints silently clobber each other. Strictly worse than today.

## Refutation 2 — translating the paths does not work either, and this is the load-bearing one

The obvious repair is to *translate* rather than share: copy a warm cache into a fresh worktree,
rewriting the absolute-path prefix. That was built and it works structurally — 1098 entries, 2196
string rewrites (entry keys **plus** the `filePath` recorded inside each stored result, which a
cache hit replays verbatim), zero donor paths surviving. **ESLint still ignored every entry.**

Measured on `src/lib` in a second worktree, so the numbers are a like-for-like comparison:

| | wall |
| --- | --- |
| cold, no cache | 63.3 s |
| **seeded with a path-translated cache** | **55.4 s** ← no better than cold |
| natively warm (same worktree's own cache) | 7.1 s |

The cause is `hashOfConfig`, which ESLint checks alongside the content hash:

```js
// eslint/lib/cli-engine/lint-result-cache.js
hash(`${pkg.version}_${nodeVersion}_${stringify(config)}`)
```

It hashes the **entire resolved config**, and reso's resolved config contains an absolute path:

```text
.languageOptions.parserOptions.tsconfigRootDir = /Users/chrisren/Development/.worktrees/<name>
```

Donor `1gudcqg` vs target `1s7andp` — every entry rejected. The two resolved configs are **89 KB
and byte-identical after normalising the worktree root**, with **exactly one** absolute-path
occurrence, so the cached results are *semantically* valid across worktrees. ESLint simply cannot
know that.

**And the field cannot be removed.** Rewriting the config to `airbnb({typescript: true})` — dropping
the explicit `tsconfigRootDir: import.meta.dirname` — leaves the path in place: the preset injects
it either way, defaulting to `process.cwd()`, which *is* the worktree.

The one remaining move would be to rewrite `hashOfConfig` during the translation. **Do not.** That
forges the token ESLint uses to decide validity, and it cannot be made safe: the hash is *per
config-group*, reso's config has ~6 `files:` blocks, and mapping each cached file to its group means
resolving the globs by hand. Get it wrong and ESLint serves a result computed under a *different*
config — a false green in the landing gate. The safety property of the translate approach was that
ESLint independently re-validates every entry; forging the hash is precisely the act of removing it.

## The other prescription is already implemented

"Scope the gate to changed files" is done. `scripts/hooks/pre-commit` lints **staged files only**
(`echo "${STAGED_JS_TS_FILES}" | xargs pnpm eslint`) and escalates to a full `pnpm lint` only when
`eslint.config.*` itself is staged — where a full run is *correct*, and where the cache could not
have helped anyway, since a config change moves `hashOfConfig` and invalidates every entry by design.
The surviving full-tree callers are `scripts/release-fly.sh` (deploy), that config-change branch, and
`pnpm validate`. All three are deliberately whole-tree. There is no CI lint. So the residual "N cold
lints" is agents running `pnpm lint` by hand in fresh worktrees — more than the commit gate asks for.

## What is actually still available

- **A fresh worktree cannot be warmed.** Given the above, its first full lint costs 230 s / 3.3 GB,
  and no cache mechanism reaches it. Reducing N means running *fewer* full-tree lints in fresh
  worktrees, not warming them — the staged-file gate is already the sanctioned path.
- **`--cache-strategy content` is worth having on its own merits**, and is committed on reso branch
  `fix/eslint-cache-content-strategy` (one line). It does **not** enable cross-worktree reuse —
  `hashOfConfig` still blocks that — but it changes invalidation from `(size, mtime)` to a content
  hash, so a rewrite that produces identical bytes stops discarding the cache. Measured on `src/lib`:
  after `touch`, metadata re-lints at **29.7 s** where the entry is still valid at **6.6 s**. That
  case is live in the pool — `refresh_slot` runs `git checkout -- .` and `prepare-cached.sh`
  regenerates codegen, both of which rewrite files. (`git reset --hard` alone does **not** churn
  mtimes of unchanged files — verified — so the pool refresh is not itself the leak.)
- **Serialising concurrent full-tree lints** remains untouched and is the one lever aimed at the
  harm actually filed ("two concurrent runs at ~2.4 GB each"). Two of these at once is 6.6 GB of
  pure re-computation. `bin/cc-bats` already implements exactly this admission shape for the bats
  corpus (concurrent-root ceiling + 1-min-load-per-core, refusing with an explicit *deferral, not a
  test result*); that idiom is the thing to reuse rather than reinvent. It needs a reso-side change
  to route `pnpm lint` through it, and landing in reso spends a real deploy — so it is an operator
  decision, not an autonomous one.

## Ten-second test for any other repo

Cross-worktree ESLint cache reuse is possible **iff the resolved config contains no absolute path**:

```bash
npx eslint --print-config <any-linted-file> | grep -c "$PWD"   # 0 ⇒ reuse is possible
```

reso returns 1, and that single occurrence is the whole blocker.

## Landing-cost note (measured, not remembered)

Checked live because the two written sources disagree. Amplify `main` has **`enableAutoBuild:
false`** (`aws amplify get-branch`), so the global `CLAUDE.md` claim that reso's `/ship` became free
is *half* right. But Path F is live: webhook `reso-deploy.fly.dev/webhook` is **active** on `push`,
and `infrastructure/reso-deploy/server.ts:284` gates on `payload.ref !== 'refs/heads/main'` — i.e. it
**accepts** main and ships LAX+SIN. reso's own `CLAUDE.md` line 420 is correct on the Fly half and
stale on the Amplify half; the global file's "Path F filtering `refs/heads/release`" is **false**.
**Landing in reso still spends money.**
