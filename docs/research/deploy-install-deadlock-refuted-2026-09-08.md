# The deploy/install deadlock described by backlog `991fcb666976` does not exist

**2026-09-08.** Premise check on backlog `991fcb666976`
("ROOT CAUSE of the deploy/install deadlock (b0ee53b5f737): postland-verify is running fine and
never CERTIFYING, because one suite makes every run end in a CUT"), filed 2026-08-25.

## Verdict: refuted on every specific claim, and on its consequence

The item is a 13-day-old snapshot. Its diagnosis names a suite that has not been convicted since
2026-08-27, a terminal state the runner has not produced in 23 of its last 25 verdicts, and a
downstream deadlock that is not happening.

| the item's claim | measured 2026-09-08 |
|---|---|
| `tests/cc-dispatch-venue-only.bats` is the blocking suite | last conviction **2026-08-27T00:09Z**; zero mentions in `runner.log` since — 12 days |
| "one suite makes every run end in a **CUT**" | **23 of the last 25** terminal verdicts are `RED`, not `CUT`. `CUT` fired twice (09-07 08:10, 09-07 17:54) |
| "one suite" | the convicted population is **15+ suites**, rotating, with disjoint consecutive sets |
| `run_s=3123` per run | **`run_s≈11,257`** (3 h 07) across every sweep 09-04 → 09-08 |
| last-green "7 h old across 52 commits" | last-green `24c598bac1c7` is **5 days / 342 commits** stale — worse, not fixed |
| no verdict ⇒ deploy-live degraded ⇒ target behind trunk ⇒ **install.sh refuses** ⇒ copy classes never repaired | **every link is false today** — see below |

## The consequence is what matters, and it is false

The item's justification was that `CLAUDE.md`, `launchd/*.plist`, githooks, `statusline.sh` and
`bin/it2` "are never repaired". Measured:

- `autonomy/postland/deploy-last-advance` = `f66f78152c82` — **trunk's tip**, advanced 2026-09-08.
- `deploy.log`: `install.sh ok (links refreshed, incl. any brand-new tracked file)` and
  `0 un-stamped commit(s) remain above the live tip`.
- `~/.claude/CLAUDE.md` and `~/.claude/statusline.sh` are byte-identical to `origin/main`.
- `~/.claude/bin/it2` is present and current (the item's brief flagged this path as possibly
  unlanded; it exists and was refreshed 2026-09-08T10:19).

install.sh is not refusing. The copy classes are in sync.

**Why the chain never formed:** the degraded advance is a *designed* door, not a failure mode.
`scripts/deploy-live.sh:2116` takes the newest NOT-RED commit under an explicit banner
(`DEGRADED deploy — …; taking the newest NOT-RED commit instead, authorised by $LAG_TRIP`),
bounded by the lag budget and paged to `deploy-degraded-<sha>.page`. It exists precisely so a
stalled verifier cannot strand the live layer, and on this box it is doing that job. The item read
that door as the deadlock's cause when it is the reason there is no deadlock.

## What IS still live is already owned, and is not this item

Non-certification is real (342 commits since last-green) and is **not** load-vs-red confusion on one
suite. It is owned by:

- `32d4d093f78a` — **blocked on an operator decision**, and it holds the measured mechanism:
  C29 meets "A VERDICT SPENDS THE CANDIDATES" (`postland-verify.sh:3211`) on a saturated box, so the
  convicted population becomes a clean **A/B/A/B alternation** — consecutive overlap zero, alternate-run
  overlap total. C29 halves the rate of load-attributable convictions and makes them alternate rather
  than suppressing them; every one still arms bisect + AUTO-REVERT. 53 of 175 consecutive red pairs
  disjoint (30.3%), against C29's own pre-ship 7/34 — **the fingerprint grew after C29 shipped**.
- `docs/research/postland-c29-alternation-2026-09-07.md` — the adjudication, landed 2026-09-07.
- `da18f179ac50` / `4143766d9d8a` — 11 eliminated hypotheses. `4143766d9d8a` specifically eliminates
  the contention reading this item reaches for: `RETRY_QOS` already elevates re-runs to
  `nice -n 5 taskpolicy -c utility`, so a failure surviving 2-of-3 is surviving a *de-contended* re-run.

Reproduced independently today, corroborating the 09-07 doc's `handoff-fire-completion-push 1..11`:
that suite — `CORROBORATED` RED by C29 on 09-08 at 04:01, 10:38 and 13:55 — passes **11/11** standalone,
twice, at load 21: 30.9 s in the normal band and 35.3 s under the corpus's own
`nice -n 19 taskpolicy -c background` clamp. Its conviction rows are stamped **loadavg 200.21** and
**213.49**; the box carried three concurrent bats corpora (one postland, two sibling `ship-land.sh`
gates) while they were minted.

## The generalisable lesson

The item's remedy — "fix at the suite … make `cc-dispatch-venue-only.bats` deterministic under load"
— was aimed at a file that had already stopped being convicted before the item was ever dispatched.
A filed diagnosis names a *population* at the moment of filing; on a rotating population the names
rot faster than the mechanism does. Re-measure the population before adopting a filed row's file list,
and check the row's **consequence** first: this one could have been closed in two reads
(`deploy-last-advance`, and `diff ~/.claude/CLAUDE.md`) without touching the verifier at all.
