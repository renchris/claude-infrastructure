---
status: complete
---

# cc-premise auto-close audit, 2026-09-01 to 2026-09-30

BACKLOG_MASTER W0 ledger-retraction.2 (row `228e30f8adce`). Until this wave, `cc-premise sweep
--close-falsified` closed a row on ONE reading of its stored probe, and a probe that reads runtime
state is a sample (`b7252a3bb015` closed on a one-in-three coin). The fix requires three falsified
readings at least 6 h apart for such probes. This audit re-asks every auto-close made since
2026-09-01 so a row the old rule closed wrongly is reopened.

## Method

Every `done` record whose evidence reads `auto-closed by cc-premise sweep` with a timestamp on or
after 2026-09-01 (119 records). For each, the row's stored probe was classified and re-run with
`bin/cc-premise`'s own `_is_sampled` and `run_falsifier`, i.e. exactly the question the sweep asked.
`derived` rows store no probe (the plan-open falsifier reads the plan's own frontmatter).

## Result

117 upheld, 1 reopened, 1 moot. By probe kind: deterministic 100, sampled 15, derived 4.

The one wrong close is a SAMPLED probe, which is the class the new rule addresses. Of the three
deterministic re-probes that read non-zero, none was a wrong close: two re-land rows whose content is
on trunk or superseded there (a removed worktree path broke one stored probe), and one row a later
filing had already re-blocked.

## Rows

| id | closed | probe kind | re-probe now | verdict |
|---|---|---|---|---|
| `7837dba4e624` | 2026-09-03 | sampled | exit 0 | upheld (probe still reads the condition gone) |
| `89eb366a6132` | 2026-09-03 | sampled | exit 0 | upheld (probe still reads the condition gone) |
| `f6db308ba6e6` | 2026-09-03 | derived | n/a (derived plan falsifier) | upheld (derived: a read of the plan's own frontmatter, not a sample) |
| `675e9c81c884` | 2026-09-03 | derived | n/a (derived plan falsifier) | upheld (derived: a read of the plan's own frontmatter, not a sample) |
| `8a2fb5c057ec` | 2026-09-03 | derived | n/a (derived plan falsifier) | upheld (derived: a read of the plan's own frontmatter, not a sample) |
| `a7f68ea20585` | 2026-09-04 | deterministic | non-zero | upheld — the stored probe names a removed worktree path (exit 127); the live land-content-verify on the same pinned ref exits 0: content on trunk |
| `33cd2ffe965f` | 2026-09-16 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `efd38bbda2b5` | 2026-09-16 | sampled | exit 0 | upheld (probe still reads the condition gone) |
| `d9403b2ac16d` | 2026-09-16 | sampled | exit 0 | upheld (probe still reads the condition gone) |
| `529b169dd19c` | 2026-09-16 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `389d8cd1df4f` | 2026-09-16 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `dbf3ff829fda` | 2026-09-16 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `49fd8f00f5ca` | 2026-09-16 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `171c7c261c51` | 2026-09-16 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `f71618f58356` | 2026-09-16 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `f8250426b1ce` | 2026-09-16 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `dec14f831373` | 2026-09-16 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `8721dd1606fd` | 2026-09-16 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `b0a6f45bb5d5` | 2026-09-16 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `893d83bfa668` | 2026-09-16 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `171d22501745` | 2026-09-16 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `54ef3956c409` | 2026-09-16 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `eedc75389d62` | 2026-09-16 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `24a931de21ab` | 2026-09-16 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `d4ce5efcad8e` | 2026-09-16 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `6e3f8dcf6ac9` | 2026-09-16 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `5b612e3e594d` | 2026-09-16 | sampled | exit 0 | upheld (probe still reads the condition gone) |
| `12ad9204cfbf` | 2026-09-16 | sampled | non-zero | REOPENED — sampled probe (a time-bound bats case) reads red again; the close rested on one sample, so the row returns to the new three-reading rule |
| `05f63af4e918` | 2026-09-16 | deterministic | non-zero | moot — already re-blocked after the auto-close; not done, nothing to reopen |
| `35fc36a7c8a7` | 2026-09-16 | sampled | exit 0 | upheld (probe still reads the condition gone) |
| `05da22d1f0fe` | 2026-09-17 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `77b0f19a4758` | 2026-09-17 | sampled | exit 0 | upheld (probe still reads the condition gone) |
| `f16025dd361c` | 2026-09-17 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `9658be8dfbcc` | 2026-09-17 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `58fd6ad79823` | 2026-09-17 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `9ca983bb9037` | 2026-09-17 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `f91af8d1e275` | 2026-09-17 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `36ce331197ce` | 2026-09-17 | sampled | exit 0 | upheld (probe still reads the condition gone) |
| `ff47b427e83c` | 2026-09-17 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `9d38cdbf2721` | 2026-09-17 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `af44e31d45ea` | 2026-09-17 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `cb0390e5d010` | 2026-09-17 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `7422da64743f` | 2026-09-18 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `76288dac0a24` | 2026-09-18 | sampled | exit 0 | upheld (probe still reads the condition gone) |
| `1192fb8cf6a8` | 2026-09-18 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `e0a8245ff5f6` | 2026-09-18 | sampled | exit 0 | upheld (probe still reads the condition gone) |
| `69158151467f` | 2026-09-19 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `414c608c702b` | 2026-09-19 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `d20fb6d12810` | 2026-09-19 | sampled | exit 0 | upheld (probe still reads the condition gone) |
| `fb9fd2383ff6` | 2026-09-19 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `5ad948b15a1c` | 2026-09-19 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `47d5d670b3df` | 2026-09-19 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `0e5225215967` | 2026-09-19 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `2530b705e9ea` | 2026-09-19 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `24c84bf0b92d` | 2026-09-19 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `7e172f9f165d` | 2026-09-20 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `ecc498dd4836` | 2026-09-20 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `488c6452d904` | 2026-09-20 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `b84eeb18bf41` | 2026-09-20 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `7eb22985f778` | 2026-09-20 | sampled | exit 0 | upheld (probe still reads the condition gone) |
| `25efc0503e7d` | 2026-09-20 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `eacd152021ae` | 2026-09-20 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `7700e2f52188` | 2026-09-20 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `55720aeed505` | 2026-09-21 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `7529e922b83d` | 2026-09-21 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `86eab2ac9e89` | 2026-09-21 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `f8e53952a6f8` | 2026-09-21 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `68df8e426d18` | 2026-09-21 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `e9b6704cebc2` | 2026-09-21 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `911996892e1c` | 2026-09-22 | sampled | exit 0 | upheld (probe still reads the condition gone) |
| `3aac8393d7ba` | 2026-09-22 | derived | n/a (derived plan falsifier) | upheld (derived: a read of the plan's own frontmatter, not a sample) |
| `1d495cbf026d` | 2026-09-23 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `64a22cabc9cc` | 2026-09-23 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `6a1f389519c2` | 2026-09-24 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `8283f6e0c557` | 2026-09-24 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `02e67ee88123` | 2026-09-24 | sampled | exit 0 | upheld (probe still reads the condition gone) |
| `c6cd4963905a` | 2026-09-25 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `85ef1e8bb68d` | 2026-09-25 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `88a99bade9ae` | 2026-09-25 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `484e710c0819` | 2026-09-25 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `c321f0da16f1` | 2026-09-25 | deterministic | non-zero | upheld — the 5 differing paths are binary hero assets that later trunk commits (round 3 renders, 2026-09-26) replaced; superseded, not lost |
| `2d22e50aef74` | 2026-09-25 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `788d58a24d45` | 2026-09-26 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `336bc87d3a35` | 2026-09-27 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `51a0c167b7a6` | 2026-09-27 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `e989a0292f88` | 2026-09-27 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `4381f1c289f5` | 2026-09-27 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `ee0152a3c8fc` | 2026-09-28 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `6a8cce468225` | 2026-09-28 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `f326292e8026` | 2026-09-28 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `5249bf8ee12c` | 2026-09-28 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `3e055da48fb7` | 2026-09-28 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `7881e3984ea5` | 2026-09-28 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `f7ec1fa99590` | 2026-09-28 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `b801a176af8d` | 2026-09-28 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `c78d1c819fad` | 2026-09-28 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `364b36924358` | 2026-09-28 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `b10bf0c28ae8` | 2026-09-28 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `e69b42b9cf62` | 2026-09-29 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `09131adfc7a5` | 2026-09-29 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `8faa241e144c` | 2026-09-29 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `a401846c83c2` | 2026-09-29 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `98da1aa10956` | 2026-09-29 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `a25173de4dd0` | 2026-09-29 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `db1f88f2299f` | 2026-09-29 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `fd92fd5d3775` | 2026-09-29 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `4b93418db977` | 2026-09-29 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `64c5f7080ef6` | 2026-09-29 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `068b1598ca73` | 2026-09-29 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `d3e5c1503b5a` | 2026-09-29 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `8f47270440f2` | 2026-09-29 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `d492bc8aeba3` | 2026-09-29 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `3e0afb056cc8` | 2026-09-29 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `f24a10dda475` | 2026-09-30 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `25d09bc1a246` | 2026-09-30 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `c4e6d470c4a9` | 2026-09-30 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `fb9eb0807a76` | 2026-09-30 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `a135ea059a0a` | 2026-09-30 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
| `edab4f2a6f0d` | 2026-09-30 | deterministic | exit 0 | upheld (probe still reads the condition gone) |
