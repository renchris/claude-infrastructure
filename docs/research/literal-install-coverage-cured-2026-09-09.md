# LITERAL INSTALL COVERAGE was already cured on trunk — verdict for backlog 8e67a1fa2d40

**Date:** 2026-09-09 · **Session:** off-box cloud VM, branch `claude/fire-20260909T004425Z-75839-1`
**Row:** `8e67a1fa2d40` — "post-land RED: tests/deploy-parity.bats::LITERAL INSTALL COVERAGE: every
install.sh singleton deploy source is CLAIMED or EXPLICITLY DECLARED @ c68525b6e948"

## Verdict

**CURED, not by me.** The red the row names was fixed on trunk by **`b5f8fc683fe3ba5f48a1938b3795e755a9f15714`**
(2026-09-08 15:34 −0500, *"fix(deploy-parity): claim mcp-servers.json as a root SSOT — the MCP SSOT
landed uncovered and reds trunk"*), with a follow-on for the ninth literal in
**`2a54f1416baba821de5d3f400c89309dad229003`** (2026-09-08 17:49 −0500). Both are ancestors of
`origin/main`:

```
git merge-base --is-ancestor b5f8fc68 origin/main   # rc 0
git merge-base --is-ancestor 2a54f141 origin/main   # rc 0
```

`b5f8fc68`'s own commit body cites backlog **`b0ee53b5f737`**, so `8e67a1fa2d40` is a **duplicate
row for the same red** — two rows minted for one failure, and the second was dispatched after the
first had already landed its cure. No code was written for this row; writing any would have risked
the revert hazard the brief names (`cc-backlog 6110fc45141e`).

## What I actually ran

The checkout arrived **shallow at depth 50** (`git rev-parse --is-shallow-repository` → `true`);
`git fetch --unshallow` first, so every trunk read below answers from real history rather than from
inside a 50-commit horizon. After that, `git rev-list --count HEAD..origin/main` = **0** — this tree
*is* trunk.

### 1. Reproduced the RED at the cited sha

Extracted install.sh's literal deploy sources and executed `deploy-parity-assert.sh`'s own `case`
block, both taken from `c68525b6e948`, with the catch-all tagged `__DEFAULT__` exactly as the bats
arm does:

```
accounts.json                            0|
bin/claude-accounts                      0|
bin/dia-cdp-launch.sh                    0|
bin/it2-wrapper                          0|
githooks/pre-commit                      0|
mcp-servers.json                         0|__DEFAULT__      <-- the RED
model-config.yaml                        1|root SSOT (link)
providers.json                           1|root SSOT (link)
statusline.sh                            0|
```

One source, `mcp-servers.json`, reaching the reasonless default — the single line the row reports.

### 2. Same derivation against trunk today

```
accounts.json                            0|
bin/claude-accounts                      0|
bin/dia-cdp-launch.sh                    0|
bin/it2-wrapper                          0|
githooks/pre-commit                      0|
mcp-servers.json                         1|root SSOT (link)   <-- cured by b5f8fc68
model-config.yaml                        1|root SSOT (link)
providers.json                           1|root SSOT (link)
statusline.sh                            0|
templates/model-classification.json      0|                   <-- declared by 2a54f141
```

Ten literals now (up from nine — `templates/model-classification.json` arrived with `42d611d3`),
zero reaching the default.

### 3. Ran the real suite

`bats` is not installed on this VM, so `bats-core` was cloned into the scratchpad and run against
the repo unmodified:

```
bats tests/deploy-parity.bats -f "LITERAL INSTALL COVERAGE"
  1..2
  ok 1 LITERAL INSTALL COVERAGE: every install.sh singleton deploy source is CLAIMED or EXPLICITLY DECLARED
  ok 2 LITERAL INSTALL COVERAGE fire test: deleting a literal-install arm puts its source back on the default

bats tests/deploy-parity.bats
  105 ok · 0 not-ok
```

Matching `b5f8fc68`'s own gate line (`1..105, 105 ok, 0 not-ok`) exactly.

## Dispatcher vintage

`git rev-parse origin/main:bin/cc-dispatch` → `b4e8edb92e176248264267cd7a9a7cb04cfb1cbe`, **EQUAL**
to the blob that composed this brief. The dispatcher that fired this session *is* trunk, so nothing
here is a landed-not-live convergence artefact — the duplicate row is a backlog-minting fact, not a
deploy-layer one.

## The generalisable bit

A post-land RED row records a *failure observed at a sha*, and the sha is the only thing in it that
ages. Between minting and dispatch, two commits cured this one; the row's own text stayed true about
`c68525b6e948` forever and false about trunk within nineteen hours. The brief's FIRST STEP rule —
read what the item cites on **trunk**, never in your own tree — is what separated "reproduce it" from
"re-derive a cure that already landed", and the shallow-clone deepening is what kept
`--is-ancestor` from answering `1` for *"I cannot see that far"* on a commit that was plainly there.

Second, smaller: the row that got the fix (`b0ee53b5f737`) and the row that got dispatched
(`8e67a1fa2d40`) describe the identical failing test name at the identical sha. Nothing dedupes a
post-land RED against an open row for the same suite, so one red can mint N rows and N−1 of them are
dispatched into an already-green trunk.
