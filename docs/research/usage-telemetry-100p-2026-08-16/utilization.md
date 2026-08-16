---
axis: A2 — Utilization (why 3 of 4 weekly windows read 1-3% with 6+ days left)
status: measured
date: 2026-08-16
headline: The 1-3% readings are an artifact of sampling three weekly windows that reset 1.4-23.4 hours ago; the real, measurable defect is that the autonomous dispatcher has parked 254 of 261 dispatchable items behind a cloud-only venue filter since 2026-08-11 and fires ~17 sessions/day, and fleet burn fell to 38% then 21% of its own demonstrated daily capacity on 08-14/08-15.
load_bearing_claim: Three of the four weekly windows in the live readout began within the last 24 hours (next 6.4h ago, next4 1.4h ago, next2 23.4h ago), so their 1-4% readings measure hours of elapsed window, not a week of underuse; only next3 (118.4h into 168h at 18%) is genuinely stranding quota.
---

## Headline

**The premise is mostly a clock artifact, and the one real defect is a venue filter, not a quota
problem.** Read live at 2026-08-16T10:22Z, three of the four weekly windows had *just started*:
`next` 6.4h in, `next4` 1.4h in, `next2` 23.4h in (derived from each row's own
`weekly_reset_at` minus 7d). A window 1.4 hours old reading 4% is running at **4.8× the pace
needed** to finish at 100%, not behind it. Only `next3` is genuinely stranding: 118.4h into a
168h window at 18%, burning **0.131 M weighted tok/h against its own trailing-4-week mean of
0.685** — 0.19×. Even a full return to its historical pace for the remaining 49.6h leaves that
week at 49.5M against its own best week of 145.2M, i.e. **~34% of what that account has already
proven it can consume.**

Underneath the artifact there *is* a real utilization collapse, and it is dated. Fleet daily burn
ran a 34-day median of **62.5M weighted tokens/day** and then fell to **32.0M (08-14)** and
**17.8M (08-15)** — 38% and 21% of the **≥84.0 M/day** floor the fleet has itself demonstrated
(sum of each account's best observed week ÷ 7, and a *floor* because the corpus contains **zero**
limit-hit events, so no observed week is known to have touched its ceiling). The binding
constraint is **work admission, not quota and not the machine**: the L4 dispatcher runs ~670
passes/day, admits ~1,000 items/day, and **fires 17**, while emitting
`venue-only=cloud parked 254 of 261 dispatchable item(s)` on every pass since the 2026-08-11
cloud-only migration. 582,000 defer decisions in 5 days, 0 of them for quota.

And the 5h-vs-weekly arithmetic reframes the target: **at the intensity `next4` is running right
now, one account's entire weekly allowance is gone in ~35 hours, while its 5h window would top out
at ~78% and never hit the 5h wall.** The weekly binds ~4.8× before the 5h does. 100% weekly is
physically reachable at a ~10% duty cycle — the ceiling is nowhere near the 5h cap.

---

## Findings

| # | Claim | Evidence (command / file:line / number + denominator) | Grade | Coverage |
|---|---|---|---|---|
| F1 | **3 of the 4 "underused" weekly windows began within 24h.** `next` 6.4h in, `next4` 1.4h in, `next2` 23.4h in, `next3` 118.4h in. A 1.4h-old window at 4% is *ahead* of pace. | `bin/claude-accounts --json` → `weekly_reset_at` minus 7d, vs now=2026-08-16T10:22Z (derived from `next.session_reset_at 13:29:59` − `session_reset_h 3.116`). next 08-16T03:59, next4 08-16T08:59, next2 08-15T11:00, next3 08-11T12:00. | **MEASURED** | 4/4 accounts, live API read, `cached:true` age 64s |
| F2 | **Only `next3` is stranding.** Current-window rate 0.131 M/h vs its own trailing-4-week mean 0.685 M/h = **0.19×**, with 49.6h left and 82% headroom. | Deduped transcript aggregation, weighted `in+out+cc` (Fable ×2). Script: scratchpad `extract2.py` + rate analysis. | **MEASURED** | 6,980 transcripts / 4 accounts / 2026-07-11→08-16, 100% of the local corpus |
| F3 | **`next2` has burned essentially nothing for 23.4h**: 0.051 M weighted tokens vs a trailing mean of 0.806 M/h — **0.002×**. Its 5h window nonetheless reads 4% with **zero** local transcript records in that window, so some of its usage is invisible to transcripts. | Same aggregation; `--route interactive` names `next2` with `k_work=0`. | **MEASURED** (burn) / **INFERRED** (invisible usage) | 100% of local corpus; cloud + web usage not covered — see Method |
| F4 | **Fleet burn collapsed on 08-14/08-15.** Daily weighted totals: 08-10 123.3M · 08-11 106.0M · 08-12 47.0M · 08-13 70.2M · **08-14 32.0M** · **08-15 17.8M** · 08-16 50.2M (partial, 10.4h). 34-day median 62.5M, mean 61.1M, max 175.5M. | Deduped per-day aggregation over the whole corpus. | **MEASURED** | 34 complete days |
| F5 | **The fleet has never hit a usage limit in the recorded corpus.** The canonical machine string `usage limit reached\|<epoch>` occurs **0** times across 6,980 transcripts. **Positive control:** the same scan finds 25 `rate_limit_error` records (next 4, next2 11, next3 9, next4 1) and 3 `limit reached … resets` prose matches. | scratchpad `lim2.py`, 4 regexes over every `.jsonl` byte. | **MEASURED** | 6,980/6,980 files |
| F6 | **Consequence of F5: capacity ≥ the best week observed.** Per-account best complete weeks (M weighted): next 149.4 · next4 129.2 · next3 145.2 · next2 164.1 → fleet **≥587.9 M/week = ≥84.0 M/day**. Fleet median day is therefore **≤74%** of a demonstrated floor. | Same aggregation, 19 complete account-weeks. | **MEASURED** (totals) / **INFERRED** (as a capacity floor) | 19 account-weeks |
| F7 | **The weekly cap binds ~4.8× before the 5h cap.** `next4` burned 4% of weekly in 1.4h ⇒ full weekly ≈ **35h** at that intensity; the same intensity puts its 5h window at 61% after 3.9h ⇒ a full 5h window ends at ~78%, never touching the wall. 33.6 five-hour windows fit in a week; **~3.5 of them at full burn exhaust the weekly** ⇒ duty cycle needed = **~10%**. | Live `--json`: next4 `session_pct 61 / session_reset_h 1.116`, `weekly_pct 4 / weekly_reset_h 166.6`. Cross-checked against transcript tokens in both windows (14.36M in the 5h window, 3.43M in the weekly window). | **MEASURED** (the two live readings) / **INFERRED** (extrapolation to a full window) | 1 account, the only one with a high-precision (61%) reading |
| F8 | **The absolute cap is NOT recoverable and I abstain on it.** Calibration is internally excellent — `next3` and `next4` independently give 0.862M and 0.857M weighted tokens per 1% weekly (0.7% apart) ⇒ cap ≈ 86M. But 15 of 19 complete historical weeks exceed that (92-191%, fleet mean 125%) with **zero** limit hits (F5). Every candidate metric is refuted the same way: `in+out+cc` 191%, cost-weighted-with-cache-reads 144%, all-raw 138%, output-only 161%. Model mix does not explain it (the 191% week is 100% opus-5, same as the calibration windows). | 6-metric consistency test, scratchpad; model-mix table per weekly window. | **MEASURED** (the contradiction) / **ABSTAIN** (the cap) | 19 account-weeks × 6 metrics |
| F9 | **57-60% of transcript usage records are duplicates by `message.id`** (next 0.568, next2 0.569, next3 0.601, next4 0.571 of 164,910 / 165,937 / 190,035 / 157,151 records). Any figure not deduped is ~2.3× inflated. Prior art already said so and was not followed: `docs/research/cloud-local-cost-ab-2026-08-11.md:1` ("summed over the transcript, **once per `message.id`**"). | scratchpad `extract2.py` dup counters. | **MEASURED** | 678,033 records, 100% of corpus |
| F10 | **Work supply is NOT the constraint.** 571 open backlog rows: **268 `open`** (235 with no operator step) + 300 `blocked` (the *operator-only* state, excluded from waves by construction) + 3 claimed. | `bin/cc-backlog list --open --json` → 571 rows; status/venue/needs breakdown. `bin/cc-backlog:86,636` (block = operator-only, cc-dispatch excludes it). | **MEASURED** | full store, 10,588 ledger lines / 2,153 ids |
| F11 | **⛔ THE BINDING CONSTRAINT: the dispatcher parks 97% of its own queue.** IDL carries `venue-only=cloud parked 254 of 261 dispatchable item(s) — they carry a different venuePlan or none, and will NOT fire while this filter is set` — **742 times**. Only **65 of 571** open rows are `venue: cloud`. | `~/.claude/autonomy/idl.jsonl*` (18 files) grep for `cc-dispatch`; `~/Library/LaunchAgents/com.claude.dispatcher.plist` → `CC_DISPATCH_VENUE_ONLY=cloud` (migrated 2026-08-11, operator directive). | **MEASURED** | 5 days of IDL (2026-08-11T21:42 → 08-16T10:43) |
| F12 | **The dispatcher fires ~17 sessions/day against ~1,000 admissions/day.** 5 days: 3,369 passes · **76 fired** · 5,264 admitted · 1,068-1,928 skipped/day · **582,000 deferred**. Defer reasons: `pass-in-flight` 376,484 (63%) · `capacity` 93,967 (16%) · `cluster-sibling` 87,889 (15%) · `at-ceiling` 23,186 (4%). **Zero** quota-cliff defers. | IDL `action:"summary"` + `action:"decision"` aggregation. | **MEASURED** | 3,369 passes / 595,082 decisions |
| F13 | **Failures are rising:** dispatcher `failed` per day 7 · 20 · 16 · 16 · **96** · **136** (08-11..08-16). Last run exited 3: `cc-dispatch: wave-plan returned non-cliff rc=6 — refusing to fire blind`; `launchctl list com.claude.dispatcher` → `LastExitStatus 768` (= exit 3). Also live: 3× `refusing to fire into <worktree> — its HEAD does not contain origin/main`. | `/tmp/claude-dispatcher.stderr.log`; `bin/cc-dispatch:145` (exit 3 = config-fail LOUD); `bin/cc-wave-plan:59` (rc 6 = unknown). | **MEASURED** | 5 days |
| F14 | **The machine is not the ceiling.** Live now: **12** claude sessions (24 procs). Ceilings: `KMAX`=8 active/account (32 fleet), `KMAX_RESIDENT`=40/account (160 fleet), memory ceiling **~50 sessions** (57.2 GB), OS ceilings <10% utilised. `cc-dispatch` logged `free_slots: 12, ceiling: 12, live_workers: 0`. | `ps`; `accounts.json` router block; `docs/plans/MACHINE_CAPACITY_V2.md:64,71,276`. | **MEASURED** | live + plan citations |
| F15 | **Residency ≠ burn, and the fleet is running ~half the clock.** Only **427 of 888** (day,hour) cells carry >1M weighted burn = **48%**; median **12 active hours/day** (p10 = 4, max 23). But it is *not* an operator-hours problem: **42.5%** of all burn falls in 23:00-07:00 local, which is 33% of the clock. | Hour-of-day profile over 37 local days, deduped. | **MEASURED** | 37 days |
| F16 | **Routing is EDF-correct and is not the fault.** `score_general = w_rem / T**γ`, γ=2 (`bin/claude-accounts:1849`) — deadline-dominant. Live: `--route general` → `next3` (49.6h to reset, the nearest deadline) rc 0; `--route interactive` → `next2`. All three lanes answer. | `bin/claude-accounts --route {general,interactive,fable}`; `bin/claude-accounts:1835-1849`. | **MEASURED** | live |
| F17 | **But the account is fixed at process launch, so nothing can re-route mid-session** — the credential is keyed to `CLAUDE_CONFIG_DIR`, set by the launcher (`~/.zshrc:173-181`, `scripts/handoff-fire.sh:6602`). A 13-subagent research wave therefore lands entirely on one account: **22 of the 25** transcripts written in the last 10 minutes are `next3` — the account with the nearest deadline *and* the highest utilisation. | `ps -eo` config-dir census; transcript-mtime census. | **MEASURED** | live |
| F18 | **Wave throughput is capped at 8 items.** `CC_WAVE_MAX_PER_ACCT` default **2** items/account/wave × 4 accounts. | `bin/cc-wave-plan` PLACEMENT section. | **MEASURED** | code read |
| F19 | **Cloud draws on the SAME per-account Max weekly quota — it is machine capacity, not quota capacity.** "the cost is tokens from the account's Max quota … there is no VM line item"; the A/B ran `--account next3` on both arms precisely to control the quota axis. Cloud costs **0.81×** local price-weighted (parity within noise). 103 cloud sessions declared. | `docs/plans/CLOUD_BACKLOG_PIPELINE.md:133`; `docs/research/cloud-local-cost-ab-2026-08-11.md:40,81`; `ls ~/.claude/autonomy/cloud/*.decl` → 103. | **MEASURED** | prior art + file count |
| F20 | **Prior art already measured the endgame stranding at 8-17pp per account-week** — `next` demoted at 0.14 headroom with 11.1h to reset, 0/112 sweeps on target, 9pp then 17pp gone; `next2` 0.09 with 7.9h left, 8pp; `next4` 15pp stranded to `kmax-concurrency` (an *exclusion*, not a tier — still unfixed). Fixed today by the `DESK_W_FLOOR_FULL_H=24` ramp. | `bin/claude-accounts:1900-1930` (`desk_w_floor_at` docstring); `accounts.json` `_desk_w2`. Measured over 1,251 sweeps / 5 weekly resets. | **MEASURED** (by prior art, cited not re-derived) | 1,251 sweeps |
| F21 | **No usage time-series exists — and the job meant to build one is dead.** `com.claude.auth-timeseries` `LastExitStatus 126` (not-executable/permission), no store on disk, and its activation script still sits in `~/.claude/autonomy/pending-activation/35-auth-timeseries-activate.sh`. **Positive control:** the same `launchctl list` shows 20 sibling `com.claude.*` jobs with exit 0. | `launchctl list \| grep claude`; `find ~/.claude -name '*timeseries*'` → only two log files + the pending-activation script. | **MEASURED** | live |

---

## Method

**Corpus.** Four real config dirs, deduped by realpath first (`~/.claude-next/projects` is a symlink
to `~/.claude/projects`; `~/.claude-next{2,3,4}/projects` are empty and are not the accounts —
`accounts.json` maps next2/next3/next4 to `~/.claude-secondary`/`-tertiary`/`-quaternary`).
Final set: **6,980 `.jsonl` files, 7.3 GB, 2026-07-11T09 → 2026-08-16T10**, i.e. **100% of the
local transcript corpus, not a sample.** Streamed with byte-level regexes (6 threads, 21s);
`ProcessPoolExecutor` is blocked in this sandbox, threads are not.

**Dedup (the load-bearing method step).** First pass, un-deduped, produced weekly totals of
300-470M weighted tokens and a fleet utilisation of 142% — impossible. The cause is F9: **57-60%
of usage records repeat by `message.id`** (resumes/forks re-append prior turns). All figures in
this document are from the deduped extraction (`extract2.py`), keeping the first occurrence of each
`msg_*` id per account. 892 records (0.13%) carry no `msg_` id and are counted once each.

**Metric.** `in + out + cache_creation` per record, model-price-weighted (Fable ×2, everything else
×1). Cache reads are excluded from the primary metric and tested separately. This is a *proxy*, not
Anthropic's meter — see F8.

**Calibration.** Each account's live `weekly_pct` / `session_pct` was divided by the deduped tokens
in that exact window (minute granularity, windows derived from each row's own `*_reset_at`). `next3`
(18%, 118h of signal) and `next4` (4%) agree to 0.7% on weekly tokens-per-percent; `next4`'s 61% 5h
reading is the highest-precision number available (±0.8% relative vs ±12-17% on a 3-4% reading).

**What I could not measure, and why.**

- **The absolute weekly cap — ABSTAINED (F8).** Six candidate metrics were tested; every one is
  refuted by historical weeks exceeding the implied cap while zero limit hits exist. Either the
  allowance was larger before ~2026-08-10 or the metering changed. No on-disk time series can
  settle it (F21). I report ratios and floors instead of a cap.
- **Cloud and web usage — NOT COVERED.** 103 cloud sessions ran through `cc-offload`; their usage
  bills the same account weekly quota (F19) but writes **no local transcript**. Every
  transcript-derived total is therefore a lower bound, and `next2`'s 4% 5h reading with zero local
  records (F3) is direct evidence the gap is nonzero.
- **Historical weekly-window anchors — ASSUMED fixed.** Windows were back-projected as
  `weekly_reset_at − 7d·k`. If an account's anchor ever moved, older windows are misaligned. Effect
  on F2/F4/F6 is small (they use rates and daily totals); effect on F8's 125% is unknown and is one
  of the two live hypotheses for that contradiction.
- **`weekly_pct` precision.** The API returns integers. At 1-4% the quantization error is 12-50%
  relative, which is why `next` (3%) is discarded as a calibration source and `next3`/`next4` are
  not.

**Commands of record.** `bin/claude-accounts --json` · `--route {general,interactive,fable}` ·
`bin/cc-backlog list --open --json` · `bin/cc-wave-plan` · `launchctl list | grep claude` ·
IDL aggregation over `~/.claude/autonomy/idl.jsonl*` (18 files) · scratchpad `extract2.py`,
`lim2.py` at
`/private/tmp/claude-501/-Users-chrisren-Development-claude-infrastructure/9f151488-422a-4e69-8da2-af8239d5bf1d/scratchpad/`.

---

## Recommendations

Ordered by expected effect on utilisation. Every one is quota-neutral to output quality: none of
them changes *what* a session does, only *whether and where* it runs.

| # | Action | Expected effect (quantified) | Quality risk | Effort |
|---|---|---|---|---|
| R1 | **Lift `CC_DISPATCH_VENUE_ONLY=cloud` to a preference, not a filter** — route `venue: local` rows to local panes when the box is under `KMAX_RESIDENT` and cloud when it is not. One line in `com.claude.dispatcher.plist` + the venue selection in `cc-dispatch`. | Unparks **254 of 261** dispatchable items (F11). Even at the current fire rate this raises the eligible pool 37×; at 12 free slots (F14) and ~2.5 M weighted tok/h per working session (F7's `next4` rate), **+3-8 concurrent workers ⇒ +7-20 M weighted tok/h**, which alone covers the ≥84 M/day floor. | **LOW** — local is the *original* venue and the better-instrumented one; the cloud migration was for box-load relief, and the box is at 12/50 (F14). Keep the cloud path for `venue: cloud` rows. | S |
| R2 | **Fix the two dispatcher stalls**: `wave-plan rc=6` (fail-closed → exit 3, whole pass lost) and `pass-in-flight` (63% of 582K defers). Give rc=6 a bounded retry with a distinct disposition instead of aborting the pass; make the in-flight lock cover only the claim, not the whole pass. | `pass-in-flight` is 376,484 of 582,000 defers (F12). Failures went 16→96→136/day (F13). Removing the pass-level abort plausibly **doubles the 17/day fire rate** without touching any ceiling. | **NONE** — it is a liveness fix; the claim lease still serialises the only thing that must be. | M |
| R3 | **Raise `CC_WAVE_MAX_PER_ACCT` from 2 and make it urgency-scaled**, so a wave can concentrate on the account whose window expires first. Today a whole wave is capped at 8 items across 4 accounts (F18) while `score_general` correctly identifies the EDF account (F16). | The scorer already knows the answer; the cap discards it. On today's state that is the difference between placing 8 items and placing the ~50 the queue can support. | **LOW** — the 5h wall self-heals in ≤5h and has three escapes; the weekly wall is the unrecoverable one and this moves *toward* draining it. | S |
| R4 | **Route the fan-out, not just the session.** A research/teammate wave inherits the lead's account because the credential is fixed at launch (F17) — 22 of 25 live transcripts are on one account. Where a wave is fired as *dispatched sessions* (`handoff-fire.sh --account`), spread it with `--rank general` instead of inheriting. | Converts one account's burn into four. On today's readout `next2` is at 0.002× its historical rate (F3) with 144.6h of runway — it is idle capacity a spread wave would consume immediately. | **NONE** — same model, same effort, same brief; only the credential differs. | S |
| R5 | **Cover the other half of the clock.** 48% of (day,hour) cells carry burn; median 12 active hours/day (F15). A self-recycling local lane (`handoff-fire.sh --recycle`) chained off the dispatcher would keep workers alive through the 12 idle hours. | Doubling active-hour coverage at the current mean intensity takes fleet burn from **62.5 → ~125 M/day**, i.e. from ≤74% to at/above the demonstrated ≥84 M/day floor. | **LOW** — recycles are already the sanctioned succession path; the risk is unattended work quality, bounded by the existing `/goal` + close-integrity rails. | M |
| R6 | **Fix `com.claude.auth-timeseries` (exit 126) and start recording the quota series.** Every finding in this document had to be reconstructed from transcripts because no usage time series exists (F21); the activation script is already written and parked. | Turns the entire A2 question from a 3-hour forensic reconstruction into a query. Directly resolves F8's abstention within one week of samples. | **NONE** — read-only job, 12 keychain reads + one `ps` per 5-min tick, no network. | S |
| R7 | **Do NOT optimise against the 5h window.** F7 shows the weekly binds ~4.8× earlier; a 5h-safety floor that throttles burn is protecting against a wall that a 24/7 drain would not reach. Re-read `DESK_5H_FLOOR=0.60`, which `accounts.json` itself flags as "sized by ARGUMENT, not by measurement". | Removes a throttle whose measured benefit is 0/324 sweeps, on the axis that is *not* binding. | **LOW** — a 5h wall self-heals in ≤5h; the guard's own docstring says the weekly wall is the unrecoverable one. | S |
| R8 | **Close the 15pp `next4` `kmax-concurrency` stranding** that `accounts.json` `_desk_w2` explicitly names as the residual its W2 ramp does *not* fix — an exclusion rather than a tier, so the account disappears from the candidate set entirely instead of ranking last. | 15pp/account-week on the worst case; prior art measured 8-17pp of endgame stranding (F20). | **LOW** | S |

---

## What would falsify my headline

1. **A weekly-window anchor that is not fixed.** My whole premise correction (F1) rests on
   `weekly_reset_at − 7d` being the window's true start. If Anthropic re-anchors a weekly window on
   first use after an idle period, then `next2`'s window may have started earlier than 08-15T11:00
   and its 1% would be genuine underuse over a longer span. **Test:** sample `weekly_reset_at` every
   5 minutes for two weeks (R6) and check whether the anchor is stationary.
2. **Substantial usage outside local transcripts.** If cloud/web/headless usage is a large fraction
   of the real burn, F2/F4/F6 all understate utilisation and the "collapse" on 08-14/08-15 may be a
   venue shift, not a drop. `next2`'s 4% 5h reading with **zero** local records (F3) is exactly this
   signature. **Test:** sum `external_metadata.usage` over `GET /v1/code/sessions/<id>` for the 103
   declared cloud sessions and add it to the per-account daily series.
3. **A weekly cap materially larger than 86M weighted tokens.** F8's contradiction is unresolved.
   If the cap is ~165M+ (the level implied by historical weeks under a no-limit-hit constraint),
   then F7's "~35 hours to exhaust a weekly" becomes ~70 hours, the required duty cycle roughly
   doubles, and R1's headroom claim weakens (though it stays directionally right). **Test:** drive
   one account deliberately to 40-60% weekly in a single measured window and re-derive
   tokens-per-percent at low quantization error.
4. **Dispatcher fires being irrelevant to burn.** The dispatcher fires 17/day (F12) while the fleet
   ran 62.5M/day — so most historical burn came from operator-initiated and handoff-fired sessions,
   not from the dispatcher. If a fired dispatcher worker consumes far less than a typical session,
   unparking 254 items buys less than R1 claims. **Test:** join IDL `fired` records to the resulting
   transcripts and measure weighted tokens per dispatched worker against the fleet mean.
5. **The 08-14/08-15 dip being an ordinary trough.** The 34-day series has other low days (07-15 at
   0.9M, 07-28 at 11.2M). Two consecutive low days is weak evidence of a regime change. **Test:**
   re-read the daily series in 5 days; if the median has recovered to ~62M without any of R1-R5, the
   collapse was a trough and F4's framing (not F11's mechanism) is what falls.
