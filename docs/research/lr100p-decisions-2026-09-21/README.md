# The two LIMIT_RECOVER spend decisions, re-measured (2026-09-21)

13 agents (10 read-only evidence axes + 3 adversarial lenses), 2.73 M tokens. Every figure below
was measured from disk; the plan's prior numbers were re-derived rather than quoted, and **three of
them did not survive**.

## Verdicts

| decision | shipped | verdict | conviction before → after |
|---|---|---|---|
| 1 — auto-recover unattended | OFF | **keep OFF** | 85% → **93%** |
| 2 — thin-account park vs spend | PARK | **keep PARK** | 80% → **92%** |

Both now clear the 90% bar, so under the Follow-On Gate's F2 protocol they stop being operator
value-forks and become implemented decisions. The implementation in both cases is the shipped
default, i.e. no change to the machine.

## Decision 1 — every stated reason for OFF is refuted, and the answer is still OFF

| the reason on file | what it measures | verdict |
|---|---|---|
| "~30 sessions die at once" | the FLEET SIZE, imported from MACHINE_CAPACITY_V2. **5 restatement sites, 0 measurements.** Measured: 21 cap events / 38 d, clusters median 4 max 8, highest 1-min concurrency 5 | **REFUTED** (4-6× overpriced) |
| spend cascade | mean 0.30-0.52 pp/recovery, worst ever 3.3 pp, **0 of 42 re-limited**. The cited 0.30-1.10 pp/session-hour does not re-derive (fleet 0.177, recovered 0.076) | **REFUTED** |
| failures strand work | 62 transplants, **0 bytes lost**; one destructive verb — a rename performed LAST after a sha-verified copy | **REFUTED** |
| value ≈ 31 min/recovery | wrong milestone. Median **673 min** (11.2 h) until the session actually works again; **43.8% never resume at all** | **UNDERSTATED ~11×** |

**The reason that survives, and it was not on file: the automated lane has never once succeeded.**
0 of 9 detached attempts · 0 of 11 request-lane results exited 0 (3×rc1, 1×rc2, 7×rc4) · **0
`RECOVERED` states in the entire store**. Verified independently at HEAD:
`jq -r .state $(find ~/.reso/limit-recover -name events.jsonl) | grep -c RECOVERED` → `0`.

A second finding removes the lever the plan thought it had: **`lr-ingest-verify` bounds no spend at
all.** rc=1 selects the EXPENSIVE prompt and the relaunch execs either way — it is a cost-TIER
selector, not an admission gate. "Admits a third ⇒ costs a third" was never true of it.

**The panel's best counter, stated because the verdict must survive it:** `PARTIAL` may be an
instrument artefact — 10 of 10 sampled partials GREW 18-102% on the target account, and 13 of 16
carried 35-547 post-transplant assistant turns. If so the lane works ~70% and the 0-for-N is a
VERIFICATION defect. **The verdict is unchanged either way**: a lane whose verification cannot
distinguish success from failure is precisely one not to automate. That robustness is why this sits
at 93% against panel convictions of 86 / 78 / 85.

**Reopen trigger:** one clean drill run (`b4a521c578b7`). It is the packet's own evidence gate and
has been opened **zero** times.

## Decision 2 — the strongest argument for SPEND was an artefact, caught by our own skeptic

A9 reported park costing **median 4.23 h, p75 41.70 h, max 59.38 h**, which dominated everything.
The PREMISE lens indicted it and was right: A9 applied the router's **TARGET**-eligibility predicate
(`recovery-weekly-thin`, `RECOVERY_W_FLOOR=0.10`, `bin/claude-accounts:2057`) to the **SOURCE**
account. That predicate is not on the park path — the poller resumes on `now < reset_epoch` plus
`account_has_headroom` (`lr-reset-poller.sh:415-427`), and **`grep -rn RECOVERY_W_FLOOR
scripts/limit-recover/` returns ZERO hits** (verified at HEAD).

Re-derived from the raw park log (98 events, 2026-07-12 →): **median 3.36 h · p90 10.91 h · max
20.53 h · 0 of 98 over 24 h.** Corroborated three ways — an independent pipeline got
3.42/10.91/20.53, A9's OWN nominal table reads 3.36/10.91/20.53 (its headline quoted the wrong
row), and the all-thin state itself lasted 4.63 h total, so a park inside it cannot cost 41.7 h.

With park costing hours rather than days the trade inverts. Add rarity — all-thin is 0.469% of
8,100 sweeps, ALL on one calendar day — and the annual stake is **2-46 model-hours against ~93,200**.
Re-limit risk is real but 6× non-uniform across the band (0.64%/h at 90-94, 0.00% at 95-97, 3.92% at
98-99), so "under 10% left" is too coarse a predicate to have priced this with.

## Method notes worth keeping

- **A negative that survives its own refutation is the strong kind.** D1's verdict holds under the
  panel's best counter, which is why it outranks the panel's own convictions.
- **The skeptic earned its slot.** One of three adversarial lenses overturned a headline number from
  the evidence phase; without it, decision 2 would have been recommended the other way.
- **Three plan figures did not re-derive** (~30 deaths, 0.30-1.10 pp/session-hour, 2h41m park). Each
  was true of *something* — a fleet size, a different population, a non-all-thin moment — and each
  had been carried forward as though it were true of the decision.
