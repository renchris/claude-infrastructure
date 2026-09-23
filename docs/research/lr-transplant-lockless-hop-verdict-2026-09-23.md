# Verdict — cc-backlog `ac7bdd4b2f9d`: lock-less second hop erases the first hop (ALREADY CURED)

**Item:** `lr-transplant.sh:218-231` — a lock-less second hop erases the FIRST hop from custody,
so a twice-moved session loses its provenance (VOLUNTARY_ACCOUNT_SWITCH.md §9).

**Verdict: CURED on trunk by `3255edb576a8fb520f3617f66d2396d98951b628`** —
`fix(lr-transplant): a lock-less second hop keeps the first hop in custody`. Close the row on
that sha; no code change was made in this session.

## What was run (cloud VM, 2026-09-23)

| step | command | result |
|---|---|---|
| deepen | `git rev-parse --is-shallow-repository` → `true`; `git fetch --unshallow` | full history |
| trunk lag | `git rev-list --count HEAD..origin/main` | `0` — this tree IS trunk |
| dispatcher vintage | `git rev-parse origin/main:bin/cc-dispatch` | `dc9130372d63…` = the brief's blob — the dispatcher that fired this session IS trunk |
| ancestry | `git merge-base --is-ancestor 3255edb5 origin/main` | rc 0 |
| suite on trunk | `bats tests/lr-transplant.bats` | plan `1..32`, 0 `not ok` |
| red proof | subject replaced by `git show 3255edb5^:scripts/limit-recover/lr-transplant.sh`, same suite | `not ok 29` (RED PROOF — lock-less 2nd hop keeps first hop) and `not ok 30` (lock-less 3rd hop walks to origin); all else ok |

The subject was restored afterwards (`git status` clean). bats and rsync were installed on the VM
to run this; both are present on the desk.

## Evidence the cure matches the item

- `scripts/limit-recover/lr-transplant.sh` on trunk carries the arm
  `A LOCK-LESS HOP (cc-backlog ac7bdd4b2f9d, VOLUNTARY_ACCOUNT_SWITCH §9)`: with no lock, it walks
  `<sid>.HANDOFF.json` tombstones backwards across `LR_CONFIG_DIRS`, prepends each proven
  predecessor, takes `ts_first` from the origin tombstone, stops on an ambiguous or revisited
  predecessor, and marks the record `custody_from:"tombstones"`.
- `docs/plans/VOLUNTARY_ACCOUNT_SWITCH.md` §9 row for this item already reads **DRIVEN 2026-09-23**.
- Tests 29–32 in `tests/lr-transplant.bats` (red proof, 3rd hop, ambiguity guard, first-hop
  equivalence guard). The two red proofs die on the pre-fix subject, so they have power; 31 and 32
  are equivalence guards and pass in both arms by design.

## Residual

Landed is not live: whether the desk's `~/.claude` has converged past `3255edb5` is a deploy-layer
fact this VM cannot see (`scripts/deploy-live.sh` status on the desk answers it).
