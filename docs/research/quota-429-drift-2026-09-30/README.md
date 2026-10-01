# Quota drift across a 429 poll-throttle — can routing trust the last-good read?

Backlog row `1c20dc1e92db`. On HTTP 429 from `/api/oauth/usage`, `claude-accounts` marks the row
`poll_throttled`, inherits the last-good percents for display, and `_excluded` returned the row's
`error`, so routing dropped an account that had a good read from seconds earlier. A 429 here is a
poll throttle and never a usage cap; a real cap comes back as HTTP 200 with percent≈100.

## Method

`measure.py` (in this directory, re-runnable):

- **Throttle events:** `~/.claude/logs/claude-accounts.log` lines `probe <acct>: 429 poll-throttled`.
- **Good reads:** `~/.claude/logs/account-utilization.jsonl` rows with `stale == false`. A throttled
  or errored row is written with `stale == true`, so these are genuine live reads.
- For each event `(acct, t)`: P is the last good read before `t`, N is the first good read after it,
  and `a = t − P.ts`. Drift is the largest `|N − P|` in percentage points over the session, weekly
  and Fable meters. A meter whose reset stamp fell between P and N is skipped, because that change
  is a window reset, not drift.
- The interval from P to N is `a` plus the gap after `t`, so it is longer than the age the router
  actually relies on at `t`. Drift is therefore **over-stated**: the bound is conservative.

## Result (2026-09-30, 1,643 events, all measurable)

| age of last-good read | n | p50 pp | p90 pp | p99 pp | cumulative n (≤ upper) | cumulative p90 pp |
|---|---|---|---|---|---|---|
| ≤90s | 28 | 0 | 2 | 5 | 28 | 2 |
| 90–300s | 102 | 0 | 3 | 8 | 130 | 3 |
| 300–600s | 113 | 0 | 2 | 100 | 243 | 3 |
| 600–900s | 120 | 0 | 3 | 7 | 363 | 3 |
| 900–1800s | 293 | 0 | 1 | 100 | 656 | 2 |
| 1800–3600s | 356 | 0 | 1 | 100 | 1012 | 2 |
| >3600s | 631 | 0 | 2 | 100 | 1643 | 2 |

**p90 drift at the cache TTL (`cache_ttl_s` = 90 s): 2 pp, n = 28.**

## Decision

The decision rule: if p90 drift is under 5 pp at the TTL, admit throttled accounts within the TTL.
At 2 pp it passes, so the admitted bound is **90 s**. Longer bounds also measure under 5 pp at p90,
but the rule stops at the TTL. The 100 pp p99 tails beyond 300 s are why: those are accounts that
hit a wall, or were relogged, between reads. Widening the bound means admitting more of those cases.

## What shipped

- `inherit_lastgood` records `lastgood_age_s`. The admission recomputes the age from `quota_as_of`
  at decision time, so a cached row that has aged since the sweep is not admitted on a stale age.
- `_throttle_admitted` lets a throttled row through `_excluded` when its inherited read is
  ≤ `CLAUDE_ACCOUNTS_THROTTLE_ADMIT_S` old (default 90; set it to 0 to turn admission off) and its
  session and weekly percents are present. Every other exclusion still runs on the inherited
  percents.
- The wire is deliberately not inherited, because a stale `allowed` would read as a fresh fact.
  A **rejected** verdict from the last good sweep is now stored in the ledger (`wire_rejects`), and
  it blocks admission. Replaying it can only refuse an account, never admit one.
- Each admission logs one line, `route <acct>: throttle-admitted …`, to
  `~/.claude/logs/claude-accounts.log`, so admissions can be counted later.
- `bin/cc-wave-plan` takes capacity from `--rank general`, so admitted rows count there with no
  change. Its `--json` wall classifier runs only when the ranking is empty.

Tests: `tests/claude-accounts-throttle-admit.bats`.
