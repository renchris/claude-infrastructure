---
axis: skeptic-utilization — adversarial review of A2 (utilization)
target: docs/research/usage-telemetry-100p-2026-08-16/utilization.md
date: 2026-08-16
verdict: SURVIVES-NARROWED (load-bearing claim) / REFUTED (headline)
---

## Verdict

**The load-bearing claim SURVIVES-NARROWED. The headline is REFUTED.**

The clock-artifact half of the load-bearing claim is not merely defensible — it is **confirmed by
an independent instrument the agent never found**, and confirmed more precisely than the agent
could. But the claim's unstated premise — that the fleet has weekly headroom worth chasing — is
false, and the headline built on it inverts.

**The four most recent COMPLETE weekly windows finished at 91% / 85% / 92% / 100%.** That is
**368 of 400 percentage-points = 92% of the fleet's weekly allowance consumed**, measured on
Anthropic's own meter, sampled 1,257 times per account over six days. One account (`next3`) sat at
**exactly 100% for 11.2 hours** before its reset. There is no utilization crisis to solve. The
premise of axis A2 was an artifact, and so is its answer: the venue filter cannot be "THE BINDING
CONSTRAINT" on a resource the fleet already spends 92% of.

The recommendation set is therefore inverted in effect. **R1 and R5 would consume 26-74× the
entire remaining weekly headroom**, exhausting every window in 1.5-2 days and leaving the fleet
walled for 4-5 days a week. Under the operator's absolute rule those are quality-destroying, not
quality-neutral, and are marked REJECT regardless of throughput.

---

## The instrument the axis missed

`~/.claude/logs/account-utilization.jsonl` — **5,029 samples, 4 accounts, 2026-08-10T05:58 →
08-16T10:48, 1.4 MB, unrotated.** Written by `bin/claude-accounts` itself
(`record_utilization`, :2242-2300) on every live sweep; read back by `_util_tail`/`apply_burn`
(:1704-1774) — *the very function that produces the `burn_wk_ppd` field sitting in the JSON row the
artifact quotes*. Each record carries `ts · acct · session_pct · weekly_pct · fable_pct ·
session_reset_at · weekly_reset_at · k · k_work`.

This is a per-account quota time series with 6 days of depth at ~7-minute granularity. The artifact
reconstructed the same quantities from **7.3 GB of transcripts over several hours**, and then
abstained on the question the store answers directly.

The orchestrator's brief said "no usage TIME-SERIES store was found on disk (searched `~/.claude`
for `*usage*`/`*quota*`)". The file is named `account-utilization.jsonl` — it contains neither
token. The agent inherited that miss, but it also cites `bin/claude-accounts:1835-1849` and
`:1900-1930` in F16/F20 — i.e. it read within ~60 lines of `_util_tail` and did not follow
`burn_wk_ppd` to its source. F21's positive control (20 sibling `com.claude.*` launchd jobs at exit
0) controls the **launchd** population, not the **store** population; it cannot license "no usage
time-series exists".

---

## Reproductions

### 1. The window starts — CONFIRMED, by a better instrument (F1)

Live read, mine, 2026-08-16T10:53:15Z (`bin/claude-accounts --json`, `cached:false`):

| acct | weekly_pct | weekly_reset_at | ⇒ start (−7d) | age |
|---|---|---|---|---|
| next | 3 | 2026-08-23T03:59:59 | 2026-08-16T03:59 | 6.9 h |
| next4 | 4 | 2026-08-23T08:59:59 | 2026-08-16T08:59 | 1.9 h |
| next3 | 21 | 2026-08-18T12:00:00 | 2026-08-11T12:00 | 118.9 h |
| next2 | 1 | 2026-08-22T11:00:00 | 2026-08-15T11:00 | 23.9 h |

Reproduces the artifact's F1 exactly (its 10:22Z read; +31 min of drift, and `next3` 18→21% because
this very research wave is burning it).

The agent's own falsifier #1 was *"my whole premise correction rests on `weekly_reset_at − 7d` being
the window's true start… test: sample every 5 minutes for two weeks"*. **That sample already
exists.** The store contains the roll events:

```
next   ROLL @2026-08-16T04:04:54: reset 2026-08-16T04:00 -> 2026-08-23T04:00 | weekly_pct 91 -> 1
next4  ROLL @2026-08-16T09:04:38: reset 2026-08-16T09:00 -> 2026-08-23T09:00 | weekly_pct 85 -> 1
next2  ROLL @2026-08-15T18:50:42: reset 2026-08-15T11:00 -> 2026-08-22T11:00 | weekly_pct 92 -> 0
next3  ROLL @2026-08-11T17:56:27: reset 2026-08-11T12:00 -> 2026-08-18T12:00 | weekly_pct 100 -> 0
```

Every roll advances the anchor by **exactly 7d** (4/4), and each rolls at the derived timestamp. The
back-projection method is validated — for one window per account. Deeper back-projection remains
ASSUMED, as the artifact honestly said.

### 2. The premise underneath — REFUTED

The same roll records give the **terminal reading of each just-ended window**: `next` **91%**,
`next4` **85%**, `next2` **92%**, `next3` **100%**.

The axis question was "why are 3 of 4 weekly windows at 1-3% with 6+ days left?" The complete answer
is not "the dispatcher parks work"; it is **"because they just rolled after finishing at 85-100%."**

Hourly trajectory (last sample per hour, `weekly_pct`), showing the plateau-then-roll shape and what
was actually happening on the two "collapse" days:

```
hourUTC        next  next4  next3  next2
2026-08-13T17    58     51     11     89
2026-08-14T09    75     54     12     90
2026-08-14T23    82     55     13     91
2026-08-15T10    85     56     13     92   <- next2 plateaued 2 days awaiting its 11:00 reset
2026-08-15T11    85     56     13      0   <- next2 rolls
2026-08-16T03    91     67     16      0   <- next rolls at 04:00
2026-08-16T08    3      85     16      0   <- next4 rolls at 09:00
2026-08-16T10    3       4     21      1
```

On 08-14/08-15 — the two days the artifact calls a collapse — `next` was at 82-91%, `next2` at
89-92% and flat, `next3` recovering from a 100% wall. **Three of four accounts were at the top of
their windows.** That is a quota state, not a work-admission defect.

### 3. F4 (the burn collapse) — REPRODUCES on an independent instrument

Meter-native fleet daily burn (sum of within-window positive `weekly_pct` deltas, all 4 accounts),
converted at the calibration in §4:

| date | pp | ⇒ M weighted @1.43 | artifact's transcript figure |
|---|---|---|---|
| 08-10 | 68 | 97.2 | 123.3 |
| 08-11 | 84 | 120.1 | 106.0 |
| 08-12 | 32 | 45.8 | 47.0 |
| 08-13 | 36 | 51.5 | 70.2 |
| 08-14 | 30 | 42.9 | 32.0 |
| 08-15 | 14 | 20.0 | 17.8 |

Same shape, same collapse, same magnitude on the low days. **F4 is credited** — and it
cross-validates the artifact's dedup pipeline against a source it never touched. Only the *cause* is
wrong.

### 4. F8's abstention was forced by its own bad calibration — REFUTED

The artifact calibrated tokens-per-percent on a **4% integer reading** (`next4`) and a **partial
in-flight window** (`next3`, 18%), got 0.862 M weighted tokens/1% ⇒ cap ≈ 86 M, then abstained
because 15 of 19 historical weeks exceeded it (92-191%, mean 125%).

The store supplies far better anchors: **complete windows terminating at 91% and 92%** (±0.55%
quantization). I scanned each account's own just-ended window, deduped by `message.id`, weighted
`in+out+cache_creation` with Fable ×2 — the artifact's exact metric:

| account | window | files | records (pre-dedup / dup frac / kept) | weighted | terminal pct | ⇒ M per 1% | ⇒ 100% cap |
|---|---|---|---|---|---|---|---|
| next | 08-09T04:00 → 08-16T04:00 | 375 | 34,714 / 0.544 / 15,845 | **130.1 M** | 91% | **1.430** | **143.0 M** |
| next2 | 08-08T11:00 → 08-15T11:00 | 335 | 38,573 / 0.542 / 17,662 | **164.0 M** | 92% | **1.782** | **178.2 M** |

The artifact's 0.862 M/% is **1.7-2.1× too low**. At the corrected cap the "125% mean" contradiction
largely dissolves (a 191%-of-86M week = 164 M = 92-115% of the real cap — which is exactly what
`next2`'s meter says). **F8's abstention is unnecessary; the cap is recoverable and is ~143-178 M
weighted tokens per account-week.** This is the low-precision-anchor error the repo has had to
withdraw before, in a new dress.

Two credits fall out of the same scan: `next2`'s 164.0 M reproduces the artifact's "best week
164.1 M" to **0.06%**, and the dup fraction reproduces F9 (0.542-0.544 vs its 0.568-0.571). **F9 and
the aggregation pipeline are sound.**

Caveat, stated as the artifact would: cloud usage bills the same meter and writes no local
transcript, so these token totals are **lower bounds** and the M-token cap is a floor. The
percentage-based argument is unaffected — it is meter-native.

### 5. F3's "invisible usage" — REFUTED by bucket arithmetic

F3 inferred that `next2`'s 4% 5h reading with zero local records implies usage invisible to
transcripts, and made it the direct evidence for falsifier #2.

Measuring the bucket ratio from the store (accumulated within-window positive deltas, whole span):

| acct | Σd_session | Σd_weekly | weekly_cap / 5h_cap |
|---|---|---|---|
| next | 412 pp (n=232) | 82 pp (n=77) | 5.0 |
| next4 | 451 pp (n=251) | 83 pp (n=78) | 5.4 |
| next3 | 275 pp (n=112) | 56 pp (n=40) | 4.9 |
| next2 | 411 pp (n=247) | 83 pp (n=82) | 5.0 |

Four independent accounts agree at **4.9-5.4**. A 4% 5h reading is therefore **0.7-0.8% of weekly**
— which rounds to the 0% then 1% the store actually shows. **No invisible usage is implied.** (Cloud
usage may well exist; F3 simply is not evidence of it, and falsifier #2 loses its only direct
signature.)

This also corrects **F7**: the artifact inferred weekly ≈ 3.5 full 5h windows from one noisy account;
the measured value is **5.0**. Direction survives, magnitude was 30% low, and its evidence base (n=1,
±12-50% quantization) was far weaker than it graded itself.

### 6. F5 SURVIVES, F6 REFUTED — the string was right, the inference was not

I attacked F5 directly and it held. Scanning 3,351 transcripts (mtime ≥ 08-01) for the **bare**
string `usage limit reached` — deliberately weaker than the artifact's `usage limit reached\|<epoch>`
regex — returns 30 hits. **All 27 pre-wave hits are meta**: agents grepping for the string, bats
fixtures (`capable_stub 'Error: usage limit reached for this account'`), a CHANGELOG line, and prior
art from 2026-08-10 reaching the same verdict. The 08-16 hits are this research wave quoting itself.
**Zero real limit events. F5 is correct and is credited.**

But **F6's inference — "capacity ≥ the best week observed… a *floor*, because no observed week is
known to have touched its ceiling" — is refuted:**

```
next3 samples at weekly_pct == 100: n=100, from 2026-08-11T00:48:38 to 2026-08-11T11:59:03
 => sat AT the weekly ceiling for 11.2 hours before its reset
```

A ceiling was touched and held for half a day. The transcript scan is **structurally blind to it**:
`score_general = w_rem / T²` (`bin/claude-accounts:1849`) is zero when weekly headroom is zero, so
nothing is routed to a walled account and no refusal is ever transcribed. F5's positive control
proved the *scanner* works; it did not establish that a real ceiling contact could appear in that
corpus at all. It cannot. (Repo memory: *a null from a blind instrument is not absence*.)

Consequence: `best week observed` is not a floor. `next2`'s best week (164.1 M) was a **92%** window
— 8% from the ceiling. `next3`'s best (145.2 M) was its **100%** window — the ceiling exactly, and
consistent with `next`'s independently measured 143.0 M cap.

### 7. The dispatcher findings — REPRODUCE, but the label is wrong

| claim | my check | result |
|---|---|---|
| `venue-only=cloud parked …` × 742 | `for f in ~/.claude/autonomy/idl.jsonl*; do gzcat/cat; done \| grep -c` | **743** ✓ |
| parked 254 of 261 | `grep -ho "parked [0-9]* of [0-9]*"` → 255/262 … 259/265 | ✓ (drifts with queue) |
| `CC_DISPATCH_VENUE_ONLY=cloud` in plist | `grep -i VENUE ~/Library/LaunchAgents/com.claude.dispatcher.plist` | ✓ |
| dispatcher last exit 3 | `launchctl list` → `61833 3 com.claude.dispatcher` | ✓ |
| `com.claude.auth-timeseries` exit 126 | `launchctl list` → `- 126` | ✓ |
| 571 open rows / 268 open / 300 blocked / 65 cloud | `cc-backlog list --open --json` → 570 / 268 / 298 / 61 cloud | ✓ (drift) |

F11-F13 and F10 are **MEASURED and reproduce**. What does not survive is the label
"⛔ THE BINDING CONSTRAINT". You cannot be constrained out of a resource you already spent 92% of.
The venue filter is a real defect on a *work-throughput* axis; it is not the answer to A2.

---

## Per-recommendation verdicts

| # | Verdict | Why |
|---|---|---|
| **R1** unpark the venue filter | **REJECT as scoped** | Its own stated effect — **+7-20 M weighted tok/h = +168-480 M/day** — is **26-74× the entire remaining fleet weekly headroom** (8 pp/account-week ≈ 46 M/week ≈ 6.5 M/day). Applied, it exhausts all four weekly windows in ~1.5-2 days and leaves the fleet walled 4-5 days a week. `next3` already demonstrated that state for 11.2 h. A weekly wall is **unrecoverable within the window**, kills in-flight work (the repo ships a whole `limit-recover` skill for it), and is a *quality* event — so the operator's absolute rule forces REJECT, not a trade. Quality risk is **HIGH**, not LOW. Salvage: unparking may still be right as a throughput fix, but only paired with a weekly-pace governor, and it is not an A2 action. |
| **R2** fix the dispatcher stalls (`rc=6` pass abort, pass-level in-flight lock) | **KEEP** | Pure liveness. Numbers reproduce (743 parked records; exit 3 confirmed). Consumes no quota it would not otherwise consume, changes no output. Quality risk **NONE** stands. |
| **R3** raise `CC_WAVE_MAX_PER_ACCT` | **NARROW** | Keep only the *urgency-scaled* half. Concentrating on the earliest-deadline account is right **this week** for `next3` (21% with 49 h left). Raising the floor fleet-wide spends headroom three freshly-rolled accounts do not have. Never a raised constant; a deadline-conditioned one. |
| **R4** route the fan-out across accounts | **NARROW — its justification is refuted** | "22 of 25 on `next3` … `next2` is idle capacity a spread wave would consume immediately" is backwards. `next3` needs **38.6 %/day** over 49 h; `next2` needs 16.5 %/day over 144 h. Concentrating on `next3` is **EDF-correct**, and spreading away from it makes the one genuine stranding case worse. Keep the mechanism (a wave should not inherit a credential blindly); reverse the motive — spread for 5h-window relief and `next3` overflow, not to "consume idle capacity". |
| **R5** 24/7 self-recycling local lane | **REJECT** | Explicitly targets **62.5 → ~125 M/day**, i.e. ~200% of the measured weekly ceiling (~620 M/week fleet). Guarantees the weekly wall by mid-week, every week, on every account. Same absolute-rule reasoning as R1. Quality risk **HIGH**, not LOW. |
| **R6** fix `auth-timeseries` and "start recording the quota series" | **NARROW — premise false** | A quota series has been recording for 6 days: `~/.claude/logs/account-utilization.jsonl`, 5,029 rows, written by `claude-accounts` itself. The action is (a) **query the store that exists**, (b) confirm retention (unrotated, 1.4 MB — fine), (c) only then ask what `auth-timeseries` adds. The launchd job's exit 126 is real and worth fixing; the *justification* ("no usage time series exists", "turns a 3-hour forensic reconstruction into a query") is refuted — the query was already available. |
| **R7** stop optimising against the 5h window | **NARROW** | Direction confirmed and improved: weekly:5h = **5.0** measured on 4 accounts (n=77-82 deltas each), not the 3.5 inferred from one 4%-integer reading. But the corollary inverts: the weekly is binding **and 92% spent**, so relaxing the 5h floor without a weekly governor only accelerates arrival at the unrecoverable wall. Relax the 5h floor **only when weekly pace is behind** — which is what the W2 ramp already does. |
| **R8** close the `next4` `kmax-concurrency` stranding | **KEEP — promote to #1** | This is where the remaining prize actually lives: 8-15 pp/account-week ≈ 46-86 M/week fleet. `next4` finished **lowest of the four (85%)** and sprinted **29 pp in its final 13 h** (56% @08-15T20 → 85% @08-16T08:58) — the signature of an endgame exclusion costing it the top ~15 pp. Quality risk LOW stands, and it is the only recommendation whose size matches the measured headroom. |

**One action nobody proposed, and it is this week's:** `next3` is at 21% with 49 h left and needs
**38.6 %/day** against a demonstrated per-account daily maximum of **33 pp** (its own 08-10). It is
the single live stranding event in the fleet, and the correct response is to *concentrate* on it
(the opposite of R4 as written) and to let the W2 endgame ramp run — both `next` (33 pp in 52 h) and
`next4` (29 pp in 13 h) show the ramp delivers.

---

## What survives the attack

1. **F1 — the clock artifact.** Correct, and now proven at the roll events rather than derived. The
   agent asked the right question of a premise everyone else accepted.
2. **F4 — the burn collapse.** Reproduces on an instrument it never used. Real, dated, and correctly
   sized.
3. **F5 — zero real usage-limit strings.** Held under a *weaker* regex over 3,351 files. Its
   conclusion about the corpus is right; only the capacity inference drawn from it (F6) fails.
4. **F9 — the 54-60% duplicate rate and the dedup discipline.** Reproduced at 0.542/0.544, and its
   `next2` weekly total reproduces mine to 0.06%. The pipeline is trustworthy.
5. **F10-F13, F21(partial) — the dispatcher and launchd census.** Every one reproduces, including
   the 742/743 record count and exit 126. Excellent forensic work on the wrong axis.
6. **F2 — `next3` is the one stranding account.** Survives, narrowed: real, but a mid-window
   reading against a demonstrated endgame ramp, not a settled loss.
7. **The abstention discipline.** F8 abstained rather than imputing a cap. That was the right call
   *given its anchors*; the fault is the anchors, not the abstention.

## What would falsify MY verdict

1. **`weekly_pct` display-capped at 100.** If the meter saturates below the true ceiling, `next3`'s
   11.2 h at 100 is not a ceiling contact and F6 stands. Test: drive one account to 100 and check
   whether the CLI refuses at the same instant the meter reads 100.
2. **n=4 account-windows.** The 92%-consumed figure rests on exactly one complete window per
   account — 100% of what a 6-day store can support, but four data points. If earlier windows ran at
   40-60%, the fleet's steady state is underused and R1/R5 regain headroom. Test: retain the store
   for 4 weeks (it already does the work; nothing needs building).
3. **Large cloud usage.** If a big share of the meter is cloud, my token-per-percent anchors
   understate the cap — which would make the *M-token* headroom larger while leaving the
   percentage-native 92% untouched. It cannot rescue R1/R5, which are sized in percentages of the
   same meter.
4. **A per-account cap that moves.** `next` 143 M vs `next2` 178 M is a 25% spread I did not resolve.
   If caps differ that much, per-account pacing needs per-account calibration and my fleet ceiling
   (~620 M/week) is soft.
