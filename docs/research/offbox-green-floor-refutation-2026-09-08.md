# The off-box green rate was projected against a cadence that does not exist, and the residual is a flow

**Row:** backlog `763522029afd` — *"measure the post-cure green rate, then decide whether the
residual tail needs a mechanism … If the measured rate is still 0 after folds accumulate on the
cured trunk, the only remaining lever is a semantic fork that is the operator's: may an
acquittal-only producer count a suite that passes on an in-run re-run as GREEN?"* Filed
2026-09-08T17:47Z off `docs/research/offbox-green-floor-2026-09-08.md`.

**The finding, stated first:** the row's cure is real and its arithmetic is not. Two independent
premises fail, and they fail in the direction that makes the row's proposed fork premature. The
schedule the projection is denominated in delivers **7.32 folds/day, not 24** — so the headline
"~1 green/day" is **~0.32/day**, against the on-box producer's 0.17/day, a factor of 1.9 rather
than 6. And the residual is not the bounded tail the row inherited: in the only post-cure scheduled
fold, **none of the six failing suites is one of the twenty named**, and **three of the six are red
on both legs at trunk tip** — genuinely broken, deterministic, repairable. Per-suite repair has a
population. It was measured empty because it was measured against the wrong set.

## What exists to measure, and what does not

The cure landed `9fa1f0899` (committed 2026-09-08T15:02Z). Exactly **two** hermetic runs contain it:

| run | trigger | head | created | verdict job |
|---|---|---|---|---|
| `34256260336` | push | `9fa1f0899` | 2026-09-08T17:18Z | **skipped** |
| `34264240364` | schedule | `c68525b6e` | 2026-09-08T18:38Z | **skipped** |

So the post-cure green rate is **0 of 2**, which is not a rate and the row said as much
(`whyNotNow: not-yet-true … needs >=24 hourly folds`). That part of the row stands. What does not
stand is everything the row derived from the word *hourly*.

## Premise 1 — REFUTED: the schedule is hourly only in the cron line

`.github/workflows/hermetic.yml` sets `cron: '17 * * * *'` and its header reasons from *"one
completed run per hour against the current tip delivers that ~24×/day."* Measured over the **58
scheduled runs** GitHub actually started, 2026-08-31T23:49Z → 2026-09-08T18:38Z:

| | |
|---|---|
| observed folds/day | **7.32** |
| inter-fold gap, median | **3.28 h** |
| inter-fold gap, max | **5.64 h** |

GitHub drops roughly **70%** of the hourly schedule. Nothing in the repo reads the delivered rate;
every number downstream is denominated in the requested one. Consequences, both load-bearing:

- **The projection.** "1 green in 23 folds" was reported as *~1/day* because 23 folds was taken for
  a day. At 7.32 folds/day it is **0.32 greens/day**. The off-box producer's advantage over the
  on-box verifier's 0.17/day is **1.9×**, not ~6× — and 1.9× is inside the range where the whole
  lane's cost is a live question rather than a settled one.
- **The waiting time.** "≥24 folds whose head contains the cure" is **3.3 days**, not one. Three
  workers claimed this row and reopened it within ~90 s each between 19:06Z and 21:21Z; the row as
  written cannot come true for three days, so a dispatch loop keyed on it re-fires against a wall.

## Premise 2 — REFUTED: the residual is not the twenty named suites

Fold `34264240364` (`c68525b6e`), the only post-cure scheduled fold: **571 suites, 564 green, 6 red,
1 non-verdict.**

    failing:     deploy-parity, spawn-presence, cc-gc, mcp-no-inherit, mcp-ssot-wire, memory-index-drain
    non-verdict: peer-owned

The predecessor note named the residual as *"1–5 suites per fold drawn from ~20"* and listed them:
`session-end-gc-lock`, `deploy-link-parity`, `live-session-registry-atomic`, `mailbox-wake-arm`,
`post-tool-batch`, `bash-audit-attrib`, `ttl-lock-owner-token`, `mailbox-session-key`,
`drain-conversion-churn`, `peer-owned`. **The intersection with the observed failing set is empty.**
Only `peer-owned` appears, and as a cut, not a red.

Three of the six were written or modified the same day the fold ran (`mcp-ssot-wire` **added**
2026-09-08; `mcp-no-inherit` and `memory-index-drain` last touched 2026-09-08). That is the
workflow's own documented bill — *"a new suite lands INSIDE the partition by default"* — arriving
at a rate nobody had measured:

| suite churn, last 30 days | |
|---|---|
| suites ADDED | 257 (**8.6/day**) |
| suite edit events | 1,319 (**44/day**) |
| distinct suites touched | 453 of 612 |

At 8.6 admissions/day into a 612-suite partition, the failing set is **re-seeded faster than the
window over which the predecessor's cure-depth table was computed.** That table replayed a *fixed*
corpus against a cure set. The corpus is not fixed. This is why the residual looked bounded at
twenty and is not: twenty was the stationary reading of a flow.

## Premise 3 — REFUTED: per-suite repair has a population, and it is non-empty right now

The predecessor's own two-legged instrument, re-run at trunk tip (`85657f83a`) under the producer's
classifier (`env -i`, empty `$HOME`, `LC_ALL=C`, `TERM=dumb`, real `bats`) — *red on both legs rules
out a machine axis*:

| suite | off-box (fold 34264240364) | this box, trunk tip | verdict |
|---|---|---|---|
| `deploy-parity` | red | **red** (104 ok / 1 notok) | **genuinely broken** |
| `spawn-presence` | red | **red** (30 ok / 1 notok) | **genuinely broken** |
| `memory-index-drain` | red | **red** (22 ok / 1 notok) | **genuinely broken** |
| `cc-gc` | red | green (28/0) | machine-coupled or unstable |
| `mcp-no-inherit` | red | green (21/0) | machine-coupled or unstable |
| `mcp-ssot-wire` | red | green (12/0) | machine-coupled or unstable |

`spawn-presence` is the clearest of the three and shows the shape: case 17, *"P1 PARITY — this
census and capacity-alarm.sh's agree on ONE ps fixture"*, fails on `[ -n "$theirs" ]` at
`tests/spawn-presence.bats:258` — the sibling's pattern extracts empty, so the parity assertion has
nothing to compare. That is a defect in the tree, reproducible on demand, on either machine. It is
not a flake and no retry policy reaches it.

The row states *"there is no known deterministic defect left to fix and per-suite repair may have no
population."* Three are named above, and two of them had already drawn on-box fixes between the fold
and this measurement — `b5f8fc683` (deploy-parity) and `18ed810a7` (memory-index-drain) — **neither
of which cleared the suite.** The sibling row `8fd1919f7769` ("triage per suite: machine-coupled vs
genuinely broken"), which the predecessor thought might have emptied under it, has six members.

## What this does to the fork

The row offers the semantic fork as *the only remaining lever*: may an acquittal-only producer count
a pass-on-retry as GREEN, when `/ship`'s on-box smoke treats pass-on-retry as a finding?

**That question should not go to the operator yet, because the measurement it rests on says the fork
would not have worked.** A retry clears an *unstable* suite. It cannot clear a deterministic one —
re-running `deploy-parity` on an unchanged tree returns red again, by construction. In the only
post-cure fold we have, **three of six reds are deterministic**, so granting the fork in full would
have published nothing for that fold. The fork's premise — that what stands between the producer and
a green is exclusively instability — is false on the only post-cure evidence in existence.

The lever the measurement actually indicates is upstream and needs no semantic ruling: the partition
admits 8.6 new suites/day by default, and a newly-landed suite that is red off-box reds every fold
until someone notices. Nothing today tells the author of a new suite that it just took the producer
red. **That is a mechanism question about admission, not about retries**, and it is ordinary agent
work.

## The honest limits of this note

- **n = 1** post-cure scheduled fold. The disjointness of the failing set from the named twenty is
  suggestive, not settled — but it has a measured mechanism (8.6 admissions/day) and the workflow
  header predicted it in advance, so it is not a coincidence being read as a cause.
- **Three greens on this box do not acquit `cc-gc`, `mcp-no-inherit`, `mcp-ssot-wire`** — one local
  green is a scalar sample of a varying quantity, the same limit the predecessor stated about its
  own nine.
- **The cadence and churn figures are strong** (58 runs over 8 days; 30 days of git history) and do
  not depend on the single fold.
- **`memory-index-drain`'s failing case is not isolated here.** The producer's classifier reports
  22 ok / 1 notok / rc 1 in 39 s, which is the citable verdict; a bare `env -i` reproduction on this
  box stalls after case 18 without emitting a `not ok`, so the two harnesses diverge on this suite
  and the divergence itself is unexplained. Its red/red status rests on the classifier, not on that
  reproduction.
- **Method note.** Both legs used `scripts/offbox-run.sh`, which resolves the REAL `bats` binary
  itself. Ad-hoc reproduction on this box is a trap: the operator's PATH resolves the bare name to
  `~/.claude/bin/cc-bats`, the admission wrapper that CREATES `$HOME/.claude/state/bats-roots.d` and
  so defeats the empty-`$HOME` hermeticity probe the classifier depends on — the hazard
  `offbox-run.sh` documents in its own header, and which this session hit before noticing.
- **The cure itself is not in question.** `typed-send-lint` and `validate-bash-differential`, red
  52/52, are absent from both post-cure folds. The deterministic core is gone. What is refuted is
  the model of what remained after it.

## Disposition

Re-measure the post-cure rate after 2026-09-12 (24 folds at the *delivered* 7.32/day, not the
requested 24/day). Do not put the retry fork to the operator until a post-cure window shows the
failing set is dominated by unstable rather than deterministic suites; on today's evidence it is
not. Repair population: `deploy-parity`, `spawn-presence`, `memory-index-drain`.
