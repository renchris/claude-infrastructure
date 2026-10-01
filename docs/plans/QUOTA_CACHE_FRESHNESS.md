---
status: complete
---
# Quota-cache freshness — plan

Scope (frozen): session startup stays a cache read (fast); the cache is made fresh at the moments it matters (after a reset, at decision points) by a background producer that spends its poll budget by expected information (live sessions per account, known reset times, reset/relogin events), and the readout never presents a pre-reset reading as current.

Research and receipts: `docs/research/quota-cache-freshness-2026-10-01/README.md`.

## Phase 0 — orchestration

- **Execution locus per wave:** W1 = **L** (lead-inline). Why: one file (`bin/claude-accounts`)
  plus one bats suite, and the edits are one coupled path (probe → inherit → exclude → render),
  so a split would put shared hunks on two owners. The machine capacity gate was also refusing
  spawns at intake (`active` term, 3 of 3).
- **Lead context budget:** about 40% to land W1; succession point is after the land and the
  converge. Nothing is planned past W1.
- **Gate:** `cc-bats tests/claude-accounts-freshness.bats tests/claude-accounts-throttle-admit.bats tests/claude-accounts-wire-truth.bats tests/claude-accounts-core.bats`,
  `shellcheck`-free (Python), `python3 -m py_compile bin/claude-accounts`, then project `/ship`.

## W1 — implementation (`bin/claude-accounts`)

| # | Change | Where |
|---|---|---|
| 1 | No in-call retry on HTTP 429 (default 0; `CC_ACCOUNTS_USAGE_429_RETRIES`) | `fetch_usage` |
| 2 | Shared per-account 429 backoff, 180 s → 360 s → 600 s cap, cleared on success; every caller skips the usage poll inside it | new `pollstate` helpers; `probe_account` before `fetch_usage` |
| 3 | Wire substitute on a 429 or backoff when the last reading was near a wall, carried a stored rejection, or a reset was evidenced since | `probe_account` 429 branch |
| 4 | Reset evidence: a passed stamp drops that window's stored rejection; a recorded redemption (`--note-reset ACCT`) after the reading rolls session and weekly; a fresh wire `!= rejected` drops that window's stored rejection | `inherit_lastgood`, new `--note-reset` |
| 5 | Admission: a throttled row with a fresh, non-rejecting wire read routes on the wire's utilizations; a pre-reset Fable figure is blanked | `throttle_admissible` |
| 6 | Keepwarm sweeps now (ignores max-age) when reset evidence is pending for any account | `--keepwarm` |
| 7 | Readout: "reset since this reading (<evidence>)", the wire's live figure on throttled rows, and the backoff deadline instead of "--fresh to retry" | table and markdown alerts |

Not built, with the reason (research Q2): stretching polls for k=0 accounts. The 429 budget is per
token, so that would free nothing for busy accounts, and it would change routing inputs for no
measured gain. The 180 s keepwarm cadence stays.

## Status

- [x] W1 DONE (2026-10-01). Learnings: (1) the first k-vs-429 table was a denominator artifact,
  because the log records successes only near the wall; on the uniformly sampled series k does not predict
  429 (§7), so the at-wall hypothesis was refuted (§6) before anything was built on it. (2) The keepwarm
  "sweep on reset evidence" rule first keyed on any passed stamp, which would have forced a sweep every
  tick for a logged-out account; it now keys on evidence newer than the cache. Tests:
  `tests/claude-accounts-freshness.bats` (7). Shas: `git log --oneline -- bin/claude-accounts`
  on main (the land rebases them).
