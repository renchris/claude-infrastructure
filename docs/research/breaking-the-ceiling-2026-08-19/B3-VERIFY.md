# B3-VERIFY — adversarial re-measurement of the 20.19 ambient load

**Verifier:** independent instrument, two fresh census windows + the gate's own telemetry.
**Date:** 2026-08-19 13:33–13:50 UTC · **Box:** MacBookPro18,2 M1 Max, `hw.ncpu`=10, 64 GiB, CC 2.1.220
**Subject:** `docs/research/breaking-the-ceiling-2026-08-19/B3-ambient-load.md`
**Posture:** REFUTE by default. Nothing killed, stopped, torn down or reconfigured; no
`settings.json` / `.claude.json` / `accounts.json` read for write or modified.

---

## 1 · Verdict

1. **B3's conclusions mostly survive; its two headline mechanisms do not.** The 20.19 is correctly
   retired — but for a different reason than B3 gives, because B3's refutation contains a **unit
   error** (§3 C1).
2. **The recommendation is mis-targeted by ~40×.** B3 prices `cc-backlog` at 17.5% of the box and
   then prescribes caching **the Stop-hook call sites**. Measured over 750 samples in two windows,
   the Stop path is **2.0% / 2.6% of `cc-backlog`** — **0.6% / 1.1% of the box**. **89%** of it is
   two launchd daemons, `cc-dispatch` (66–68%) and `cc-discover` (20–23%).
3. **The prize is not 1.2 extra fires/day; it is zero.** The gate is BOUNDED
   (`CC_FIRE_ADMIT_BUDGET`=1): **all 19 refusals in 8.6 days were followed by an admit**, three of
   them in the *same second* via `budget-expired`. The gate has never permanently lost a fire. It
   costs latency, not throughput.
4. **B3's own "dynamics control FAILS" is refuted, and this is the durable methodological fix.**
   `corr(load1, raw census)` = **−0.005**; `corr(load1, EWMA₆₀(census))` = **+0.842** (peak +0.853 at
   5-sample lag, 6.8 time constants). Every prior wave, including B3 and
   `gc-cpu-vs-session-ceiling-2026-08-18`, correlated an *instantaneous* census against a *60 s
   EWMA* and read the resulting null as "the census cannot predict load". It can.
5. **What is stable is the ABSOLUTE, not the share** — the opposite of B3's closing claim.
   `cc-backlog` = **6.64 / 7.34 / 7.41** threads across three independent windows (±5%), while its
   *share* moved **17.5% → 29.9% → 43.3%** (2.5×). Quote threads, never percentages.

---

## 2 · The numbers, with the command behind each

### 2a · Instrument (disclosed)

Per-sample, per-pid runnable(`R`)+uninterruptible(`U`) thread counts joined to a full ppid/argv
ancestry taken in the same sample, plus `vm.loadavg`. **Per-sample granularity is the point** — it is
the only way to get a variance and a standard error on the attribution, which B3 does not report.

```sh
# per sample: sysctl -n vm.loadavg ; ps -axM ; ps -axo pid=,ppid=,args=
scratchpad/v3/census.sh <run> <n> <interval>     # runA n=420 @0.8s ; runB n=330 @0.8s
scratchpad/v3/an2.py <run>                       # ancestry walk → class + caller attribution
```
My own instrument measures **0.024 / 0.018 threads** (0.1%) and is classified `X` and excluded.
I also ran **11** `cc-backlog list` timing calls inside the windows (§2e); against a natural rate of
**32 cc-backlog invocations/minute** that is ~2% contamination, and it lands *inside* the SESSION
bucket — so the Stop-path figure below is an **over**-estimate, not an under-estimate.

### 2b · Load is not a level — and 20.19 is the box's own p90

| quantity | value | command |
|---|---|---|
| load1 over 10.3 min (62 samples, 10 s apart) | mean **27.24** sd 3.67 · **min 21.30 max 36.79 — a 15.5-point swing inside 10 min** | `sysctl -n vm.loadavg` loop → `load.tsv` |
| load1 runA (7.6 min) | 26.25 ± 3.36, range 21.30–36.97 | census `ld.tsv` |
| load1 runB (5.8 min) | 21.43 ± 3.11, range 16.47–30.55 | census `ld.tsv` |
| **load1 across 8.6 days, 220 production gate evaluations** | min **4.66** · p25 **9.44** · **p50 13.12** · p75 17.44 · **p90 20.41** · max **118.95** | `jq -r 'select(.gate=="capacity" and (.under_test//false)==false)\|.detail' ~/.claude/logs/handoffs.jsonl` |

**The single most decision-relevant line here:** *20.19 sits at the box's own **90th percentile**.*
Calling it "the ambient" calls the p90 the baseline. MEASURED.

### 2c · Class attribution, two windows — absolutes stable, shares not

| class | runA (n=420, load 26.25) | runB (n=330, load 21.43) | B3 (n=240, load 34.56) |
|---|---:|---:|---:|
| **B1 our automation** | **10.564 thr / 43.0%** | **9.633 thr / 56.4%** | 9.817 thr / 25.9% |
| A1 macOS / third party | 6.605 / 26.9% | 2.164 / 12.7% | 12.733 / 33.6% |
| ? unattributable | 4.317 / 17.6% | 3.788 / 22.2% | 4.117 / 10.9% |
| **C Claude** | **2.005 / 8.2%** | **0.852 / 5.0%** | 4.804 / 12.7% |
| A3 Dia | 0.412 / 1.7% | 0.273 / 1.6% | 1.454 / 3.8% |
| B2 terminal | 0.479 / 1.9% | 0.200 / 1.2% | 1.504 / 4.0% |
| **TOTAL census (R+U thr)** | **24.586** | **17.094** | 37.875 |
| load/census ratio | 1.068 | 1.254 | 0.913 |

B1's **absolute** is 9.6–10.6 threads in all three windows (±5%); its **share** is 25.9–56.4% (2.2×).
Claude's absolute is the volatile one (0.85–4.80). SE on every B1 row ≤ 0.20 (n≥330).

### 2d · Who actually calls `cc-backlog` — the finding that moves the recommendation

| caller | runA thr | % of cc-backlog | runB thr | % of cc-backlog |
|---|---:|---:|---:|---:|
| **daemon `cc-dispatch --decide`** | **4.857** | **66.2%** | **5.036** | **68.0%** |
| daemon `cc-discover --once` | 1.683 | 22.9% | 1.494 | 20.2% |
| daemon `postland-verify` (bats) | 0.433 | 5.9% | 0.327 | 4.4% |
| daemon `cc-reaper` | 0.200 | 2.7% | 0.315 | 4.3% |
| **SESSION Stop / tool path** | **0.148** | **2.0%** | **0.191** | **2.6%** |
| other/bash | 0.019 | 0.3% | 0.045 | 0.6% |
| **TOTAL `cc-backlog`** | **7.340** | | **7.409** | |

Isolating the *hook* forms alone (`hooks/../bin/cc-backlog list --blocked/--open --json`, incl. the
`timeout 5` wrapper) gives **17 thread-samples over 420 = 0.040 thr = 0.16% of the box.**

**Our own daemons, by root (runA, n=420, box total 24.586 thr):**

| daemon | thr | % of box | present |
|---|---:|---:|---:|
| **`cc-dispatch`** | **6.055** | **24.6%** | **420/420** |
| `cc-discover` | 1.750 | 7.1% | 345/420 |
| `cc-reaper` | 0.936 | 3.8% | 257/420 |
| `autonomy-sweep` | 0.698 | 2.8% | 258/420 |
| `deploy-live` · `teammate-reap-alarm` · `cc-await-ping` · `capacity-alarm` · `postland-verify` · `lead-crash-watchdog` · `lead-supervisor` | 0.953 | 3.9% | — |
| **TOTAL our launchd daemons** | **10.393** | **42.3%** | |

**Duty cycle: `cc-dispatch --decide`, `cc-discover`, `cc-reaper`, `autonomy-sweep`, `find-plan.sh`,
`postland-verify` are each alive in 420/420 samples** — 100% duty over 7.6 min. `cc-dispatch` has
`StartInterval 300`, so **a single pass outlives its own interval**; the observed ancestry is
`cc-dispatch ← cc-dispatch ← cc-dispatch ← launchd`, three deep.

**Volume:** **245 distinct `cc-backlog` PIDs in 7.6 min = 32/min**, 135 of them under `cc-dispatch`.
At the measured **4.32 CPU-s** per call that is **1,058 CPU-s in 456 s of wall = 2.3 cores held
continuously** by store folds.

**The loop, from source.** `bin/cc-backlog:5236-5266` § *S5 KICK-ON-WRITE*: every successful `add`
spawns a detached `cc-dispatch --decide` behind a **30 s** debounce. `cc-dispatch` itself runs
`cc-backlog add --title advance …` (4 distinct such invocations observed in-census) and `cc-discover`
runs `cc-backlog add` in a loop (`bin/cc-dispatch:1302-1303` says so). Writes beget passes beget
writes; the 300 s timer is documented as the *backstop*, not the driver.

### 2e · The fold, re-timed — and the `rc=124` claim

```sh
/usr/bin/time -p  ~/.claude/bin/cc-backlog list --blocked --json   # x3
timeout 5         ~/.claude/bin/cc-backlog list --blocked --json   # x8, load recorded per call
```

| | B3 | mine |
|---|---|---|
| wall | 5.81–7.54 s | **3.15–3.80 s (mean 3.44), 11 runs, load 19.43–26.90** |
| CPU | 4.38 CPU-s | **4.32 CPU-s** (user 1.92 + sys 2.40) — replicates |
| under shipped `timeout 5` | **rc=124, 3/3** | **rc=0, 11/11** |
| store | 4.2 MB / 12,314 rows | 4,201,749 B / **12,317** rows, **341 B/row** |
| append rate | 9–29/h | **2–39/h** (median ~15/h ⇒ a cache bust every ~4 min) |
| `jq` sites in `cc-backlog` | 137 | 137 |
| live `blg_list_cached` cache files | 52 | 52 |

Wall time shows **no trend across load 19.4–26.9**. The breach is real in B3's band (34.6–46.4) but
is **intermittent and load-dependent**, not the permanent dead oracle claimed.

### 2f · The gate — what it evaluates, and what it has actually done

| fact | value | source |
|---|---|---|
| `capacity_gate()` terms | **load + headroom only** | `scripts/handoff-fire.sh:4368`, term at :4470-4490 |
| `cc_capacity_admit` terms | **load + headroom + segments(50%) + active(ceiling 8) + reserve** | `scripts/lib/capacity-admit.sh:584/603/667/708` |
| load term already OFF on the Agent-tool path | **yes, verbatim** `CC_ADMIT_LOAD_TERM=off` | `hooks/agent-teams-enforce.sh:214` |
| live `cc_sp_active` at load 26.88 | **4** of ceiling 8 ⇒ ADMIT, while load says REFUSE | `. scripts/lib/spawn-presence.sh; cc_sp_active` |
| **the refusal is BOUNDED** | `CC_FIRE_ADMIT_BUDGET` default **1**; 2nd consecutive refusal ADMITS + pages | `scripts/handoff-fire.sh:4332-4366` |
| production evaluations carrying a load reading | **220** (198 measured admits + 19 refused + **3 `budget-expired`**) — not 232 | `jq` over `handoffs.jsonl` |
| over ceiling | **22 / 220 = 10.00%** (B3: 9.48%) | same |
| **refusals followed by an admit** | **19 of 19.** 3 at **+0 s** (budget-expired), 11 within 1.1–36.6 min, 5 within ≤8.3 h with no fire attempted between | timestamp join over `handoffs.jsonl` |

**Method A re-derived and reproduced exactly** (subtract X from every reading, n=220):

| shed | 0 | 2 | 4 | **6** | 8 |
|---|---:|---:|---:|---:|---:|
| still > 20.0 | **22** | **15** | **12** | **11** | **7** |

Identical to B3's table. The *arithmetic* is sound; the *interpretation* is not — see C11.

---

## 3 · CONFIRMED / REFUTED / UNPROVEN, per claim

| # | B3 claim | verdict |
|---|---|---|
| **C1** | "The ×1.553 is not reproduced by any window (0.913/1.077/1.235) ⇒ 20.19 inherits ~55% inflation" | **REFUTED as stated — UNIT ERROR; conclusion survives.** A8-marginal-cost.md:148-149 fits **runnable PROCESSES**: "18.654 R-procs at mean load 28.96 ⇒ 1.553". B3's 0.913/1.077/1.235 are **THREAD** factors. Mine, same data both ways: **load/R-procs = 1.300**, load/R-threads = **1.158**. Re-deriving with a *proc* factor I measured: 13.000 × 1.300 = **16.9** — still under 20.0, so **20.19 is still retired**, but the error is 19%, not 55%. Note A8 itself already flagged it at :314 as a "single-point fit" needing re-derivation at loads 10/20/40. |
| **C2** | "Ambient is a moment, not a property (8.35–46.39 in a day)" | **CONFIRMED and understated.** 15.5-point swing inside 10 minutes; 4.66–118.95 over 8.6 days; **20.19 = the box's own p90**. |
| **C3** | "Three-way split: A 33.6% / B1 25.9% / C 12.7%" | **UNPROVEN as a ranking of shares; ORDERING confirmed.** B1 > C by ≥5× in all three windows, but B1's share moved 25.9 → 43.0 → 56.4%. Shares are not a stable object. |
| **C4** | "`cc-backlog` = 6.642 thr, 1.4× the Claude fleet; not a bursty artifact" | **CONFIRMED, replicated twice.** 7.340 (SE 0.128, 419/420) and 7.409 (SE 0.188, 330/330). The variance attack fails — it is continuous, not bursty. It is **3.7× / 8.7×** the whole Claude class in my two windows. |
| **C5** | "`jq` is the largest single image, 4.550 thr = 2.9× `claude.exe`" | **UNPROVEN.** My instrument attributes by owner, not by image; I did not build an image-level ranking. Not load-bearing for any decision. |
| **C6** | "**Six** Stop hooks resolve+invoke `wrap-ledger.sh`" | **REFUTED — five.** `hooks/dod-persist.sh` mentions it only in comments (:20,:28,:33,:106,:123). Non-comment invocation: `anti-deference-nudge:250`, `boundary-handoff:383`, `completion-assert:194`, `operator-readout:517,1135`, `session-continue:737,845`. |
| **C7** | "The cache exists only in `operator-readout.sh`; **2 uncached Stop-path callers**; N=2 folds per Stop" | **CONFIRMED on the fact, REFUTED on the consequence.** `blg_list_cached` is indeed only in `operator-readout.sh` (:138, :467, :496) — but `wrap-ledger.sh` has **its own per-Stop-event memo** (`_wl_cache_serve`/`_wl_cache_store`, :287-375), transcript-keyed with a single-flight lock, and it wraps the whole machine-mode body **including `count_operator_steps()` at :956**. So the five hook callers share **ONE** fold per Stop event. And `completion-assert.sh:611` is gated at :602 behind a **handoff-phrase match** (`grep -iqE "$CA_HANDOFF"`), so it does not fire on an ordinary turn. Real N per Stop ≈ **1**, not 2. |
| **C8** | "`timeout 5` breached ⇒ **rc=124, 3/3** ⇒ D1 oracle dead fail-open, still billed" | **REFUTED as a permanent state; CONFIRMED as an intermittent load-dependent one.** 11/11 rc=0 at load 19.4–26.9, wall 3.15–3.80 s. CPU 4.32 vs their 4.38 — that half replicates exactly. **NEW, and worse than B3 says:** `wrap-ledger.sh count_operator_steps()` uses the *same* 5 s bound (`_bounded "${WRAP_BACKLOG_TIMEOUT_S:-5}"`, :654-668) and degrades to `YOURS=0 / YOURS_SRC=error` — so a breach kills the **👤 rung** as well as D1. Two oracles, one bound. |
| **C9** | "Gate mis-keyed; `capacity-admit` already ships `segments`+`active` and already turns load OFF on the Agent-tool path" | **CONFIRMED verbatim** (§2f). |
| **C10** | "19 refusals; 22 of 232 = 9.48%" | **CONFIRMED on counts, REFUTED on the denominator.** 220 production rows carry a load reading, not 232 ⇒ **10.00%**. All 19 refusal loads reproduce to the decimal. |
| **C11** | "Method A/B agree: 22→11 / 19→10 ⇒ **≈1.2 extra fires/day**" | **Arithmetic CONFIRMED (my re-derivation is identical). Conclusion REFUTED.** The gate is **bounded**: `CC_FIRE_ADMIT_BUDGET`=1, so the second consecutive refusal admits and pages. **All 19 refusals were followed by an admit — 3 at +0 s.** In 8.6 days **not one fire was permanently lost.** The lever removes **delay**, not refusal. "1.2 extra fires/day" counts delays as losses. |
| **C12** | "Honest ceiling: shedding *all* non-Claude load buys ≤22 fires in 9 days; **the gate is not the ~15 wall**" | **CONFIRMED — and stronger given C11:** the ceiling is 22 *un-delayed* fires, not 22 extra ones. |
| **C13** | "5–7 s of dead wall-clock at **every turn-end of every session** ⇒ 5.6–11% throughput tax ⇒ ≈0.4–0.7 working sessions recovered; recommendation #1 = extend `blg_list_cached` to the two Stop-path callers" | **REFUTED — the largest error in the file.** The Stop path is **2.0% / 2.6% of `cc-backlog`** (0.6% / 1.1% of the box; hook forms alone **0.16%**), replicated in two windows. **89%** is `cc-dispatch` + `cc-discover`, two launchd daemons at **100% duty**. The prescribed fix reaches ~1/40th of the cost it is priced at. The per-turn tax is also bounded at **5 s by the timeout**, shared by **one** memoised computation, not 5–7 s × N. |
| **C14** | *(not in B3)* the mechanism | **NEW.** Our launchd daemons = **10.393 thr = 42.3% of the box**; `cc-dispatch` alone **6.055 = 24.6%**, alive 420/420 despite a 300 s timer. **245 `cc-backlog` invocations in 7.6 min = 2.3 cores held continuously.** Driven by a write→kick→write loop (`cc-backlog:5236` § S5 KICK-ON-WRITE, 30 s debounce). |
| **C15** | "gitstatusd/caffeinate/speech/sleep = 0.0000; Dia 1.454; process count is not load" | **CONFIRMED in substance.** None appears in either of my top-14 tables; Dia 0.412 / 0.273 (1.6–1.7%) — same order, both immaterial. |
| **C16** | "DYNAMICS control FAILS/UNDECIDED — the correlation is negative and uninformative" | **REFUTED.** `corr(load1, raw R-procs)` = **−0.005** (reproducing B3's and `gc-cpu-…-08-18`:84's null), but `corr(load1, EWMA₆₀(R-procs))` = **+0.842**, peak **+0.853** at 5-sample lag, over **6.8 time constants**. The null was an instrument mismatch — an instantaneous census correlated against a 60 s EWMA. Per-sample `load/R-procs` = **1.400 ± 0.393 (CV 28%)**, which *is* the real reason not to quote single-point absolutes. |
| **C17** | "Do NOT subtract ambient from the load term — it is stale within hours and the measurement enters its own population" | **CONFIRMED and reinforced** (p90 finding + the 15.5-point 10-minute swing). |
| **C18** | "What IS stable is the share" | **REFUTED.** Absolutes are stable (`cc-backlog` 6.64/7.34/7.41; B1 9.82/10.56/9.63); shares are not (17.5→29.9→43.3%; 25.9→43.0→56.4%). |

---

## 4 · Reduction safety — every proposal with its named cost

| # | reduction | measured prize | **what breaks** | verdict |
|---|---|---|---|---|
| 1 | **Index the fold inside `bin/cc-backlog`** (not in a hook wrapper) — the store is append-only, so an offset index is exact | reaches **~7.4 thr / 30–43% of census**, i.e. the whole `cc-backlog` block including the 89% daemon share | Nothing functionally. Only `compact` rewrites the store, so the index needs one invalidation hook there. Medium effort. | **DO — this is the real recommendation** |
| 2 | Extend `blg_list_cached` to `wrap-ledger.sh` + `completion-assert.sh:611` (B3's #1) | **0.6–1.1% of the box** | Nothing. Cheap and correct — but it is **not the prize**; do not fund it as one. | DO, price honestly |
| 3 | **Disable the write-kick** (`CC_BACKLOG_KICK=off`) as a one-line experiment | removes the write→pass→write loop; `cc-dispatch` should drop from 100% duty toward its 300 s timer | **NAMED:** dispatch latency rises to at most the 300 s backstop, which `cc-backlog:5238-5240` documents as the thing that *guarantees* the bound. Reversible, one env var. | **DO FIRST — cheapest discriminating test** |
| 4 | Raise / remove `timeout 5` on the two backlog reads | restores D1 **and** the 👤 rung under load | **NAMED:** the bound exists so a wedged store read cannot hold a session's close open (`wrap-ledger.sh:652-655`). Raising it trades oracle liveness for close latency. Correct order: make the fold fast (1) **first**, then the bound never binds. | DO AFTER 1 |
| 5 | `cc-backlog compact` (12,317 rows / 4.2 MB, doubled since last research) | proportional to rows retired | **NAMED:** compaction is the one non-append operation — it invalidates the `(mtime,size)` cache key by design and a concurrent reader can fold a file being rewritten. Serialize it; do not run it under a live wave. | DO, serialized |
| 6 | Lengthen `cc-dispatch`'s `StartInterval` | **zero** | Does nothing: a pass already outlives 300 s, and the kick path bypasses the timer entirely. | **DON'T — refuted** |
| 7 | Kill `gitstatusd` (18 live) | **0.000 thr** | Breaks the shell prompt's git segment. | **DON'T** |
| 8 | Quit Dia | 0.27–1.45 thr (1.6–3.8%) | **NAMED:** breaks the `dia-agent` / `autonomous-authenticated-web-access` CDP paths; global CLAUDE.md § Browser Automation directs agents to attach `chrome-devtools-mcp` to a *running* Dia/Chrome. | **DON'T** |
| 9 | Switch terminal iTerm2 → kitty | 0.18–0.44 thr | Already done — **every session ancestry in both censuses roots at `kitty`**. Nothing left to win. | N/A |
| 10 | **Turn the load term OFF in `capacity_gate()`** (B3's #2) | at most 22 un-delayed fires in 9 days | **NAMED and material:** the load term is the *only* term that can see saturation which is neither Claude, nor memory, nor compressor — exactly the 42% of the box that is our own daemons. Replacing it with `active`(8)+`segments`(50%)+`headroom`(4 GB) makes the gate structurally blind to the biggest thing on the machine. Given C11 (nothing was ever lost), the status quo costs ~19 delays in 8.6 days. | **DOWNGRADE to optional** — fix the daemons, then re-measure |

---

## 5 · What I could NOT measure, and why

1. **`kernel_task`** — 740 threads, invisible to `ps -axM`. Same blind spot as B3. Sits inside the
   load/census ratio residue (1.068–1.254). Needs `sudo`/`dtrace`; not run on the live fleet.
2. **The unattributable residue — 17.6% / 22.2%, larger than B3's 10.9%.** Processes that exited
   between the thread pass and the ancestry pass (~0.15 s). I added a global pid-map fallback and it
   is still this large, which means B3's 10.9% is optimistic and **their B1 floor is even more of a
   floor than they state**. Resolving it needs `dtrace proc:::exec-success`.
3. **Whether the 5 s bound breaches at load 34–46.** I never saw load ≥ 31 during a timing run;
   11/11 passed at 19.4–26.9. I did not manufacture load on a live fleet to force it. B3's rc=124 is
   therefore **unrefuted at their load band** — only refuted as a permanent property.
4. **How many folds a real Stop event costs end-to-end.** Executing Stop hooks writes live state
   (rule 4). I read the memo and the phrase gate from source and infer N≈1; I did not run one.
5. **Whether disabling the write-kick actually drops `cc-dispatch` duty.** That is a config change to
   live autonomy; out of scope for a read-only verifier. It is proposal #3 above precisely because it
   is the one-variable experiment nobody has run.
6. **Image-level ranking** (B3's `jq` = 4.550 claim). My instrument attributes by owner.
7. **Instrument in its own population, disclosed:** census 0.024/0.018 thr; 11 `cc-backlog` timing
   calls (~2% of the natural 32/min rate) which inflate the SESSION bucket — the direction that makes
   my key finding *conservative*.

---

## 6 · The decision this verification changes

**Three changes to what B3 hands the wave.**

1. **Re-aim the fix.** B3's headline is right — `cc-backlog` is ~7 runnable threads and the largest
   single work class on this box, ~5× the whole Claude fleet. But its **caller is not the Stop path**
   (2.0–2.6%), it is `cc-dispatch` + `cc-discover` (89%) in a write→kick→write loop at **100% duty**.
   Fix the fold **inside `cc-backlog`**, and turn off the kick as a one-line test. Caching the two
   Stop-hook sites is correct and cheap — and buys **0.6–1.1% of the box**, not 17.5%.
2. **Withdraw the gate prize entirely.** `CC_FIRE_ADMIT_BUDGET`=1 means every refusal releases on the
   next attempt, and telemetry shows **19/19 refusals followed by an admit, 3 at +0 s.** The gate has
   cost this fleet **zero fires in 8.6 days.** Any wave conclusion that spends effort on the gate is
   spending it on a latency bug, and the file should say so. B3's own §3 caveat ("the gate is not the
   wall") is right; its §1.5 headline ("≈1.2 extra fires/day") contradicts it.
3. **Change the unit of every future claim.** Report **threads**, not shares — absolutes replicate to
   ±5% across three windows while shares move 2.5×. And when correlating a census against load,
   **EWMA₆₀-match the census first**: the raw correlation is −0.005 and the matched one is +0.842, so
   every "the control fails" verdict in this line of research (B3 §2b,
   `gc-cpu-vs-session-ceiling-2026-08-18`:84) was an instrument artifact, not a finding.

**For the operator's actual question (>15 concurrent session-equivalents):** this axis returns a
**BOX** lever that is **SUSTAINED** and costs **zero quota** — roughly **2.3 cores** currently held by
our own autonomy loop folding a 4.2 MB JSONL 32 times a minute. It does not touch B4's quota wall
(9.4 sustainable working units), and it is not the ~15 ceiling. It is, however, the largest single
recoverable block on this machine, and it is ours.
