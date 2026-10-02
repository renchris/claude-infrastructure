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
| 4 | Reset evidence: a passed stamp drops that window's stored rejection; a recorded redemption (a manual reset-recording flag) after the reading rolls session and weekly; a fresh wire `!= rejected` drops that window's stored rejection. *Superseded 2026-10-01 by W2: the flag, its event store and its reader are removed; the read detects a banked reset on its own.* | `inherit_lastgood`, new flag (removed in W2) |
| 5 | Admission: a throttled row with a fresh, non-rejecting wire read routes on the wire's utilizations; a pre-reset Fable figure is blanked | `throttle_admissible` |
| 6 | Keepwarm sweeps now (ignores max-age) when reset evidence is pending for any account | `--keepwarm` |
| 7 | Readout: "reset since this reading (<evidence>)", the wire's live figure on throttled rows, and the backoff deadline instead of "--fresh to retry" | table and markdown alerts |

Not built, with the reason (research Q2): stretching polls for k=0 accounts. The 429 budget is per
token, so that would free nothing for busy accounts, and it would change routing inputs for no
measured gain. The 180 s keepwarm cadence stays.

## W2 — reset detection with no flag, plus telemetry (`bin/claude-accounts`)

Scope (frozen): claude-accounts detects any limit reset (natural or banked /limit-reset) with NO flag and no human or agent action; the reset-recording flag and every instruction to run it are removed; every reset correction is logged as telemetry, with a report that shows whether detection has been fast.

Operator rulings (2026-10-01): the agent drives everything, never the human; no flag, it must just
work with or without a reset (a reset is rare); include telemetry so a look back shows whether it
has been working optimally.

- **Execution locus:** **L** (lead-inline). Why: one file plus one bats suite, the same coupled
  probe → inherit → collect path as W1.
- **Why the flag was redundant.** A capped account's last reading is >= 90%, so a 429-throttled
  usage poll always fires the wire substitute (`wire_substitute_wanted`, `WIRE_SUBSTITUTE_PCT`), and
  a fresh wire verdict that no longer rejects drops the stored rejection and takes the lower figure
  as the reset evidence (`apply_wire_substitute`). An unthrottled poll reads the post-reset figure
  directly. Neither needs anyone to record anything. The wire stays one ~25-token call per
  throttled near-wall account per sweep (unchanged).

| # | Change | Where |
|---|---|---|
| 1 | Removed the reset-recording flag, its writer, its `.events.jsonl` sidecar reader and its usage text; stamps are now the only stored reset evidence | `_reset_evidence_items`, `main` |
| 2 | `watch_resets`: per sweep, a window reading >= 99% arms a watch (sidecar `.resetwatch.json`, flock'd); a later reading < 90% appends one line to `~/.claude/logs/quota-reset-detect.jsonl` and clears the watch, so one reset logs once. Only readings this sweep took count (fresh usage, or a wire substitute), never an inherited figure | new block after `apply_wire_substitute`; called at the end of `collect` |
| 3 | Event fields: `ts acct window(5h\|7d) kind(scheduled\|unscheduled) stale_since detected_at lag_s channel(usage\|wire) throttled_polls_between wire_attempts_between` plus `from_pct to_pct reset_at`. Scheduled lag counts from the stamp; unscheduled lag is an upper bound from the last >= 99 reading, because the redemption moment is not observable locally | `watch_resets` |
| 4 | `claude-accounts --reset-report [--days N]`: one row per event, then `summary:` count and median/max lag per kind × channel. File read only, dispatched before `get_data` | `reset_report`, `main` |
| 5 | Instructions removed: `/limit-recover` now says a banked reset needs no action; research README annotated | `commands/limit-recover.md`, research README |
| 6 | Test F-6 replaced: a 429 usage read plus an HTTP 200 wire read (7d 0, allowed) routes and reads 0 with no flag, logs exactly one `unscheduled/wire` event, does not re-log, and a scheduled 5h reset logs `scheduled/usage` with lag from the stamp; `--reset-report` summarises both | `tests/claude-accounts-freshness.bats` |

Constraints held: no network call on session startup (the watcher is a file write inside the
sweep; the report is a file read); unknown stays refused (F-4, F-5 unchanged); no settings or
permission edits.

## Status

- [x] W1 DONE (2026-10-01). Learnings: (1) the first k-vs-429 table was a denominator artifact,
  because the log records successes only near the wall; on the uniformly sampled series k does not predict
  429 (§7), so the at-wall hypothesis was refuted (§6) before anything was built on it. (2) The keepwarm
  "sweep on reset evidence" rule first keyed on any passed stamp, which would have forced a sweep every
  tick for a logged-out account; it now keys on evidence newer than the cache. Tests:
  `tests/claude-accounts-freshness.bats` (7). Shas: `git log --oneline -- bin/claude-accounts`
  on main (the land rebases them).
- [x] W2 DONE (2026-10-01): no-flag reset detection verified by a stubbed throttled-usage +
  wire test (F-6), reset telemetry and `--reset-report`. The live server behavior of the wire
  during a usage throttle is still unmeasured; the first real banked reset will appear in the
  report as an `unscheduled/wire` row and settles it.
