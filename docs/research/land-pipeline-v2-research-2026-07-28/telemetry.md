SendMessage is not available in this subagent context (only WebFetch/WebSearch are deferred) — report returns inline.

# Landing-pipeline measurement — claude-infrastructure, 2026-07-28

**Read-only. No repo file written; no process killed.** Scratch: `…/e891e080-…/scratchpad/{timeruns.sh,timeruns.txt}`.

## 0. Two blockers you must apply to every number below

| # | Blocker | Evidence |
|---|---|---|
| B1 | **`land.log` is two different logs interleaved.** 447 lines are `land-lock.sh` telemetry `{ts,repo,branch,wait_s,hold_s,exit,pid}` (one per *wrapped locked child*); 341 are `ship-land.sh` attestations `{ts,tool:"ship-land",sid,verify,sweep,esc_scan,exit[,head,base,tree,gate_scope,selected_n]}` (one per *invocation outcome*). Their `exit` fields are **different code spaces**. Mixing them is the single easiest way to get this wrong. | key census over all 788 lines; `scripts/land-lock.sh:73-76` (`logline`), `scripts/ship-land.sh:239-250` (`attest_land`) |
| B2 | **Gate-REDs were invisible in `land.log` before `2026-07-26T00:09:49Z`.** The first line carrying `gate_scope`/`selected_n` and the first `exit:6` line are the **same timestamp** — attestation-on-red arrived with `e34a7ea1` ("attestation fields", 2026-07-25 16:42 −0700 = 23:42Z), 27 min earlier. `ship-land.sh:930-935` says so verbatim: *"Post-fix gate-REDs were invisible in land.log (only the locked phase attested), leaving flake-rate / gate-health claims without a denominator."* | min-ts scan; `git log -S` on `scripts/ship-land.sh` |

⇒ The **only valid red-rate denominator** is the 33.0 h window `2026-07-26T00:09:49Z → 2026-07-27T09:10:30Z`. Pre-window "0 reds in 124 attempts" is an artifact, not a fact.

---

## 1. `~/.claude/land.log` — 14 days (`2026-07-14T00Z` → log end `2026-07-27T09:10:30Z`)

Log spans `2026-07-11T09:30:58Z … 2026-07-27T09:10:30Z`, 788 lines, 194,098 B, 0 malformed. Whole file parsed (not tailed — it is small).

### 1.1 Lands/day (ship-land attestations, `exit:0`)

| Date (UTC) | attempts | landed(0) | red(6) | park(3) | distinct sids attempting | distinct sids **landing** | lands/landing-sid |
|---|---|---|---|---|---|---|---|
| 07-19 | 68 | 68 | 0* | 0 | 54 | 54 | 1.26 |
| 07-20 | 19 | 16 | 0* | 3 | 16 | 15 | 1.07 |
| 07-21 | 3 | 3 | 0* | 0 | 1 | 1 | 3.00 |
| 07-23 | 9 | 6 | 0* | 3 | 3 | 2 | 3.00 |
| 07-24 | 4 | 4 | 0* | 0 | 4 | 4 | 1.00 |
| 07-25 | 21 | 19 | 0* | 2 | 13 | 11 | 1.73 |
| 07-26 | 152 | 46 | **105** | 1 | 58 | 36 | 1.28 |
| 07-27 | 65 | 18 | **46** | 1 | 14 | 11 | 1.64 |

`*` = B2 artifact. **Zero-land calendar days in the 14d span: 7 of 15** (07-14…07-18, 07-22, 07-28).

- 14d totals: **341 attempts → 180 lands (52.8%)** from **157 distinct sids** (131 of which landed; **26 sids attempted and never landed**).
- 12.9 lands/calendar-day · 22.5 lands/active-day · 1.37 lands per landing sid.

### 1.2 Exit-code distribution

**ship-land (n=341, 14d)** — contract at `ship-land.sh:50-54`: `0` landed · `2` preflight · `3` escalation PARK · `4` shared-checkout · `5` rebase conflict · `6` gate red · `7` push non-ff · `8` content-verify failed · `9` GATE-KILLED · `42` internal stale-gate.

| exit | n | % | note |
|---|---|---|---|
| 0 landed | 180 | 52.8% | |
| 3 escalation PARK | 10 | 2.9% | all 10 = `esc_scan:"hit"`, 6 distinct sids |
| 6 gate red | 151 | 44.3% | all after B2 epoch |
| **2,4,5,7,8,9** | **0** | 0% | **never once emitted in 788 lines** |

**`exit 9` (GATE-KILLED) has fired 0 times** in the entire log, despite landing 2026-07-26 09:07Z (`497bd796`) and 62 subsequent attempts. Cuts are instead absorbed upstream by `run_scoped_suite`'s re-run — see §2.

**land-lock (n=443, 14d)** — `exit` = the *wrapped child's* code:

| exit | n | % | meaning |
|---|---|---|---|
| 0 | 230 | 51.9% | locked child pushed + verified |
| 42 | **133** | **30.0%** | STALE-GATE: origin moved during the unlocked gate → full re-gate |
| 6 | 34 | 7.7% | in-lock gate red (fallback / re-gate path) |
| 75 | 19 | 4.3% | `EX_TEMPFAIL` — **lock-wait exhausted at `LAND_LOCK_WAIT`=3600s** (`land-lock.sh:134`) |
| 5 | 10 | 2.3% | rebase conflict |
| 130 / 143 / 127 / 1 | 9 / 2 / 5 / 1 | | SIGINT / SIGTERM / cmd-not-found / misc |

### 1.3 `gate_scope` + `selected_n` (214 lines carry them; all post-B2)

`gate_scope` is **`scoped` on 100% of 214 lines**. `full`/`shadow`: 0. Default comes from `scripts/gate-policy.sh:20` → `SHIP_LAND_GATE_SCOPE_DEFAULT=scoped` (ship-land's own hardcoded default is `full`, `ship-land.sh:144`).

**"scoped" is mostly not scoped.** `SELECTED_N=-1` means "n/a: full/shadow run" (`ship-land.sh:153,726`) — i.e. `gate-select.sh` returned `FULL`:

| | n | % of 214 | land rate | red rate |
|---|---|---|---|---|
| effective **FULL** (`selected_n = -1`) | 132 | **62%** | 6 (**5%**) | 125 (**95%**) |
| actual **subset** (`selected_n ≥ 0`) | 82 | 38% | 56 (**68%**) | 26 (32%) |

Subset sizes: min 0 · p25 4 · **p50 27** · p75 64 · p90 85 · max 102 suites (of 144). Mean 36.1 = **25% of the corpus**. Buckets: 0 suites → 9 runs (lint-only land); 1-10 → 14; 11-30 → 21; 31-60 → 13; **61-102 → 25**.

### 1.4 Other attested fields (14d, n=341)

- `verify`: `ok` 180 / `n/a` 161 — `ok` exactly ⇔ `exit:0`. Zero `FAIL`.
- `sweep`: **`review` 146 · `clean` 34 · `n/a` 161**. **146 of 180 successful lands (81%) closed with a stranded-sweep REVIEW verdict**, every day since 07-19 (07-19 is the only day with any `clean`). Per `scripts/stranded-sweep.sh:16-19` this is by-design ("on a multi-session box exit 1 is the normal state, so it is a prompt, not a verdict") — but it means the signal is 100% saturated and carries zero discriminating information.
- `esc_scan`: `clean` 331 / `hit` 10.
- Newest schema (`gate_wait_s`, `gate_slot`, `loadavg`): **1 line only**, `2026-07-26T12:19:55Z` (`gate_wait_s:0, gate_slot:1, loadavg:"20.06"`). Not yet emitting broadly.

### 1.5 Distinct sids/day · concentration

157 distinct sids over 341 attempts. **Heavily concentrated**: sid `1d559723…` / branch `wt-1a941c28a079` = **66 attempts, 1 land, 65 reds** = 43% of all reds. Removing it from the valid window: 151 attempts, 63 lands (42%), 86 reds (57%) across 67 sids.

Red **trees** dedupe hard too: 151 reds over **85 distinct trees**; 56% of reds landed on a tree already seen red (top repeats 14, 14, 9, 6, 6, 6).

### 1.6 Inter-land arrival gaps (successful lands only)

| metric | value |
|---|---|
| n gaps | 179 |
| median | **1,161 s = 19.4 min** |
| p90 | 4,910 s = 81.8 min |
| p95 | 8,144 s = 135.7 min |
| mean | 4,035 s |
| min / max | 79 s / 197,524 s (54.9 h) |
| gaps ≤ 60 s | **0** |
| gaps ≤ 300 s | 13 |
| gaps > 3600 s | 29 |

All-attempt gaps (n=340): p50 444 s, p90 2,822 s, **14 same-second pairs**.

### 1.7 Clusters (same-minute)

| population | distinct minutes | minutes with >1 | max/min | rows inside multi-minutes |
|---|---|---|---|---|
| all attempts (341) | 290 | 33 | 5 | 84 (25%) |
| **successful lands (180)** | 180 | **0** | **1** | **0 (0%)** |
| gate-reds (151) | 102 | 31 | 5 | **80 (53%)** |

**The mutex is working perfectly: no two lands ever share a minute.** All clustering is on the *unlocked gate* path — 7 same-second groups (5,4,3,3,2,2,2), **all 21 rows are reds**, all on 2026-07-26 03:10–05:31Z.

Peak concurrency: **10 distinct sids attempting within a 30-min window** (2026-07-26T03:19:51Z); **8 within a 10-min window** (03:34:17Z).

---

## 2. `~/.claude/autonomy/postland/flakes.jsonl`

Exists. 26 records, 5,623 B, span `2026-07-26T05:39:51Z → 2026-07-27T05:22:00Z` (**23.7 h only**).

| dimension | values |
|---|---|
| `outcome` | `pass-on-retry` **24** · `1-of-3` **2**. **`cut-not-red` does not appear as an outcome value** — the two labels in use are these. |
| `phase` | `land-gate` 24 · `postland` 2 |
| by file | comms-drain-activate 7 · cc-reaper 5 · cc-inbox-guard 4 · boot-resume/cc-classify/deploy-live/desk-invariant/settings-drift/cc-authbrowser/desk-arm-live/lead-supervisor/bats-assert-liveness/test-hermeticity-lint 1 each (13 distinct files) |
| signal kind | `not ok …` (named test) **10** · signal-kill (`Terminated: 15` / `exit 137`) **6** · `exit 143` **7** · `exit 1`/`exit:0` **3** |

**`loadavg` at cut time** (n=26): min **7.85** · p50 **14.73** · p90 **21.01** · max **37.20** · mean 16.00.
Full series: `19.36, 21.10, 20.92, 19.23, 15.32, 15.32, 15.10, 13.95, 13.95, 13.95, 13.88, 13.58, 14.12, 14.04, 13.42, 16.09, 16.30, 14.36, 14.36, 22.10, 9.29, 15.51, 7.85, 8.42, 37.20, 17.38`.
By outcome: `pass-on-retry` n=24 min 7.85 / median 14.36 / max 37.20 · `1-of-3` n=2 (15.51, 22.10).

**Every load value ≥ 7.85 — i.e. every recorded flake occurred at or above the gate's own admission ceiling `CC_GATE_MAX_LOAD=8`** (`ship-land.sh:312`).

---

## 3. Post-land net — state

| fact | value | how obtained |
|---|---|---|
| stamps count | **24** | `ls ~/.claude/autonomy/postland/stamps/ \| wc -l` |
| newest stamp mtime | `2026-07-27 03:02:43` local — **31.6 h old** at 2026-07-28T17:38Z | `stat`/`ls -lt` |
| oldest stamp | `2026-07-25 19:16:42` | same |
| **verdict contents** | **`red` × 24 / 24. Zero `green` stamps have ever been written.** | JSON parse of all 24 |
| `com.claude.postland-verify` in `launchctl list` | **absent** | `launchctl list \| grep -i -E 'postland\|claude'` → only `com.chrisren.watch-claude-code-2118-hold`, `com.chrisren.restic-claude-archive` |
| domain state | **`"com.claude.postland-verify" => disabled`** | `launchctl print-disabled gui/501` |
| direct query | `Could not find service "com.claude.postland-verify" in domain for user gui: 501` | `launchctl print gui/501/com.claude.postland-verify` |
| plist on disk | present, 1,651 B, mtime Jul 26 15:04, `StartInterval 300`, `RunAtLoad false`, `Nice 10`, `LowPriorityIO true` | `cat` |
| `~/Library/LaunchAgents \| grep -i claude` | 15 files: 13 `com.claude.*` + 2 `com.chrisren.*` | `ls` |
| **all 13 `com.claude.*` jobs** | **every one `=> disabled`**: team-orphan-reaper, nightly-regression, log-rotation, dispatcher, discovery, postland-verify, power-policy-verify, caffeinate-floor, lead-supervisor, session-search-sweep, session-search-backfill, desk-invariant, boot-resume | `launchctl print-disabled gui/501` |
| override db | `/var/db/com.apple.xpc.launchd/disabled.501.plist`, mtime **Jul 27 19:05** (2 min after boot at `Mon Jul 27 19:02:44 2026`) | `ls -la` + `sysctl -n kern.boottime` |

**Consequence chain (all disk-verified):** 0 green stamps ⇒ `postland_net_live()` (`ship-land.sh:266-289`) reaches `[[ "$newest" -gt 0 ]] || return 0` and returns **0 = "not adopted yet, never brick the bootstrap land"** — so the staleness guard has **never** fired and scoped lands are never degraded to FULL by it, even though the net has been red 24/24 and the daemon is disabled. The guard is structurally unable to trip while zero green stamps exist.

### 3.1 `runner.log` (175 lines, `2026-07-26T02:16:42Z → 2026-07-27T10:02:43Z`)

| event | count |
|---|---|
| `RED` verdicts | **24** |
| `GREEN` verdicts | **0** |
| `ADMIT-DEFER` | 76 |
| `ADMIT-PROCEED` (budget 600 s exhausted, started anyway) | **54** |
| `ADMIT ok after Ns` | 21 (Σ 3,638 s) |

**Admission-control overhead ≈ 54 × 600 s + 3,638 s = 36,038 s ≈ 10.0 h** of pure waiting across 32 h of runner life — and 54 of 75 waits ended by *proceeding under load anyway*.

`run_s` per stamp (n=24): min **222 s** · p50 **3,055 s (50.9 min)** · p90 6,826 s · **max 13,248 s (220.8 min)** · mean 3,688 s. `retries`: 0 (×7), 12 (×9), 14 (×6), 16 (×2). `flakes=0` on all 24.

**The same 6 suites fail in 17 of 24 stamps**: `deploy-parity`, `desk-arm-live`, `desk-recycle-durable`, `lr-team-audit`, `session-continue`, `waiting-recycle`. (+`tests/` and `test-hermeticity-lint` in 7; `cc-relogin-status` in 1.) `shellcheck_advisory` 79-107.

---

## 4. Corpus inventory + timed sample

| metric | value | method |
|---|---|---|
| `tests/*.bats` files | **144** | `ls tests/*.bats \| wc -l` |
| total `@test` cases | **2,307** | `grep -ch '^@test' tests/*.bats \| paste -sd+ \| bc` |
| total lines | **30,656** | `wc -l tests/*.bats` |
| static `sleep` seconds | **2,888.5 s (48.1 min)** across 82 `sleep` calls in the corpus | regex sum of `sleep <n>` literals |
| gate parallelism | **sequential, one `bats` process per suite. No `-j`/`--jobs`/`xargs -P` anywhere** in `ship-land.sh` or `postland-verify.sh` | `run_bats_all` (`ship-land.sh`), grep |
| hw | `hw.ncpu=10` · `hw.memsize=68,719,476,736` (64 GiB) · `hw.model=MacBookPro18,2` · Bats 1.13.0 | `sysctl` |

### 4.1 The 6 timed runs — `nice -n 19 timeout 300 bats <file>`, sequential

`vm.loadavg` **before all: `{ 2.94 3.80 3.31 }`** · **after all: `{ 5.52 4.77 3.84 }`**

| suite | lines | @test | **wall s** | rc | ok / not-ok | load pre → post |
|---|---|---|---|---|---|---|
| `handoff-fire-validate.bats` (smallest) | 31 | 3 | **0** | 0 | 3 / 0 | 2.94 → 2.94 |
| `boot-resume-launch.bats` (2nd smallest) | 44 | 5 | **1** | 0 | 5 / 0 | 2.94 → 2.94 |
| `claude-kimi.bats` (median, idx 71) | 151 | 13 | **1** | 0 | 13 / 0 | 2.94 → 2.94 |
| `cc-await-ping.bats` (median, idx 72) | 152 | 14 | **16** | 0 | 14 / 0 | 2.94 → 2.59 |
| `cc-reaper.bats` (2nd largest) | 1,077 | 80 | **160** | 0 | 80 / 0 | 2.59 → 5.60 |
| `ship-land.bats` (largest) | 1,201 | 60 | **79** | 0 | 60 / 0 | 5.60 → 5.52 |
| **sample total** | **2,656** | **175** | **257 s** | all 0 | 175 / 0 | |

### 4.2 Corpus wall-time extrapolation — three independent stratifications

| estimator | sample share | extrapolated corpus wall |
|---|---|---|
| by **lines** | 2,656 / 30,656 = 8.66% | **2,966 s = 49.4 min** |
| by **@test count** | 175 / 2,307 = 7.59% | **3,388 s = 56.5 min** |
| by **static sleep-seconds** | 254.0 / 2,888.5 = 8.79% | **2,923 s = 48.7 min** |
| + per-suite `bats` startup | 0.46 s × 144 | +66 s (repo's own figure: 0.46 s × 126 = 58 s, `ship-land.sh` run_bats_all comment) |

⇒ **~49-57 min at load 3-6, sequential.** Independently corroborated by ground truth: postland `run_s` p50 = **3,055 s = 50.9 min** (n=24, but at load 5.8-96.7 *and* including 12-16 retries + admission waits).

**Wall time is sleep-bound, not CPU-bound**: 2,888.5 s of literal `sleep` = **~94-99% of the whole extrapolated run**, on a 10-core box the gate uses one core at a time. Sleep concentration (top): `postland-verify.bats` 600 s · `cc-authbrowser.bats` 555 s · `cc-notify.bats` 330 s · `it2-wrapper.bats` 306 s · `cc-reaper.bats` 240 s · `desk-invariant.bats` 180 s · `pkill-scope.bats` 165 s. **7 files = 2,376 s = 82% of all corpus sleep.**

---

## 5. Contention surfaces — right now (2026-07-28T17:38Z)

| surface | value | method |
|---|---|---|
| `~/.claude/worktrees` | **path does not exist** (`ls` → 0) | `ls … \| wc -l` |
| `git worktree list` | **49 entries** (48 + main) — **22 `prunable`**, 27 live | `git worktree list` |
| registered under `~/Development/.worktrees/` | 25 | grep of the same |
| **dirs on disk** under `~/Development/.worktrees/` | **107** — i.e. **82 unregistered orphans** | `ls -1d …/*/ \| wc -l` |
| **disk** consumed by `.worktrees` | **107 GB** | `du -sh` |
| live `claude` processes | 7 (31 matches incl. children) | `ps -Ao pid,etime,command \| grep 'claude '` |
| `bats` running | only my own measurement run (now finished) | `pgrep -lf bats` |
| `ship-land.sh` running | **none** | `pgrep -lf ship-land` |
| **land-lock dir** | resolves to `/tmp/land-lock-3cca03ed6835` — **does not exist on disk**; no `land-lock*` anywhere under `/private/tmp` | `scripts/land-lock.sh --print-lock-dir`; `find /private/tmp -maxdepth 1 -name 'land-lock*'` |
| lock holder / age | **n/a — no lock dir, no holder** | as above |
| boot | `Mon Jul 27 19:02:44 2026` (up 15 h 39 m); oldest `/private/tmp` entries Jul 27 19:04 ⇒ `/private/tmp` cleared at boot | `sysctl -n kern.boottime`, `uptime` |
| current load | `5.22 4.17 3.50` | `uptime` |

**The pipeline has been idle for 32.5 h** — last `land.log` line `2026-07-27T09:10:30Z`, last postland verdict `2026-07-27T10:02:43Z`, and a reboot at 19:02 local wiped the lock dir and left every `com.claude.*` job disabled.

---

## 6. Durations — what the log does and does not carry

**No duration field exists on ship-land lines.** Schema is `ts,tool,repo,branch,sid,verify,sweep,esc_scan,exit,head,base,tree,gate_scope,selected_n` (+`gate_wait_s,gate_slot,loadavg` on exactly 1 line). `land-lock` lines **do** carry two real durations.

### 6.1 `land-lock` `wait_s` / `hold_s` (14d, n=443)

| | n | min | p50 | p90 | p95 | max | mean | **Σ** |
|---|---|---|---|---|---|---|---|---|
| `wait_s` (queue) | 443 | 0 | **0** | 1,960 | 3,191 | 7,386 | 453 | **55.7 h** |
| `hold_s` (in-lock) | 443 | 0 | **79** | 682 | 1,135 | 6,771 | 282 | **34.7 h** |

By exit — the shape that matters:

| exit | n | `wait_s` p50 / p90 / max | `hold_s` p50 / p90 / max | Σ wait | Σ hold |
|---|---|---|---|---|---|
| **0** landed | 230 | 0 / 221 / 2,010 | **228 / 968 / 6,771** | 5.5 h | **26.3 h** |
| **42** stale-gate | 133 | 2 / 2,265 / **7,386** | **1 / 1 / 2** | **26.4 h** | 79 s |
| **75** starved | 19 | **3,600 / 3,601 / 3,601** | 0 | **19.0 h** | 0 |
| **6** in-lock red | 34 | 0 / 360 / 5,944 | 544 / 2,085 / 3,239 | 2.9 h | 7.6 h |
| 5 conflict | 10 | 0 / 850 / 2,450 | 1 / 1 / 1 | 1.0 h | 6 s |

**26.4 h of queue-wait bought exactly 79 s of work** (exit 42), plus 19.0 h burned hitting the 3600 s starvation ceiling. **45.4 of 55.7 total wait-hours (81%) ended in a non-outcome.**

### 6.2 Before / after the 2026-07-25 "gate runs unlocked" fix

| | n | `wait_s` p50/p90/max | `hold_s` p50/p90/max | exits |
|---|---|---|---|---|
| **before 07-25** | 187 | 0 / 221 / 1,223 | **299 / 678 / 1,180** | 0:144, 5:9, 6:23, 130:9, 1:1, 127:1 |
| **on/after 07-25** | 256 | 0 / **2,968** / **7,386** | **1 / 976 / 6,771** | 0:86, **42:133**, **75:19**, 6:11, 5:1, 127:4, 143:2 |

The fix did what it claimed for the median in-lock hold (**299 s → 1 s**), and created two entirely new failure populations that did not exist before it: **exit 42 (0 → 133)** and **exit 75 (0 → 19)**. p90 queue wait went **221 s → 2,968 s (13.4×)**.

### 6.3 Unlocked-gate duration, derived (the number the schema doesn't record)

For every `exit:42` → next `land-lock` line on the same `(repo,branch)`: `gate_est = Δts − wait_s(next) − hold_s(next)` = re-rebase + one **unlocked full/scoped gate**. n=127 transitions:

**min 0 s · p25 1,029 s · p50 1,555 s (25.9 min) · p75 2,760 s · p90 3,418 s (57.0 min) · max 9,486 s (158.1 min) · mean 1,913 s**

### 6.4 Same-sid consecutive attempt gaps (attempt duration + operator/agent think time)

47 of 157 sids made >1 attempt; n=184 transitions.

| preceded by | n | p50 | p90 | min | max |
|---|---|---|---|---|---|
| all | 184 | 720 s | 8,520 s | — | 98,045 s |
| exit 0 | 53 | 1,101 s (18.4 m) | 14,078 s | 7 s | 98,045 s |
| **exit 6** | 126 | **565 s (9.4 m)** | 7,364 s (122.7 m) | 7 s | 34,052 s |
| exit 3 | 5 | 1,546 s | 5,081 s | 328 s | 7,402 s |
| same-branch | 144 | 642 s | 7,270 s | — | — |

### 6.5 `exit:9` / `exit:6` — past week vs earlier

- **`exit:9` = 0 occurrences, whole log.**
- **`exit:6` = 0 before `2026-07-26T00:09:49Z`, 151 after** — B2 instrumentation boundary, not a behavior change.
- Last 200 lines (`2026-07-26T19:24:39Z → 2026-07-27T09:10:30Z`): ship-land `0:31, 3:1, 6:89`; land-lock `0:31, 6:2, 42:45, 127:1`.

**Valid-window rates (33.0 h, 2026-07-26T00:09:49Z → 2026-07-27T09:10:30Z):** 217 attempts · 64 lands (**29%**) · 151 gate-reds (**70%**) · 2 parks · 0 killed · 68 distinct sids · 62 distinct branches · **6.6 attempts/h, 1.9 lands/h (≈47 lands/day-equivalent)**.

---

## 7. Adversarial pass — what a hostile reviewer would have caught

| Challenge | Resolution |
|---|---|
| *"44% red rate is a regression"* | **No** — it is B2 instrumentation arriving. Only the 33 h post-epoch window has a denominator. |
| *"scoped gate reduces gate cost"* | **62% of scoped runs are effective-FULL** (`selected_n=-1`) and those are **95% red**; subset runs are **68% green**. The tier that fails is the tier that doesn't narrow. |
| *"151 reds = 151 broken trees"* | 85 distinct trees; 56% are repeats; one sid/branch contributes 43% of all reds. Excluding it: 57% red across 67 sids. |
| *"the lock is the bottleneck"* | Lands never collide (0 same-minute lands in 180). Median `hold_s` is **1 s** post-fix. The bottleneck moved to unlocked-gate wall time (p50 25.9 min) and to the 30% stale-gate re-round tax. |
| *"my 6-suite sample is line-biased; wall time is sleep-bound"* | Verified and re-stratified: sample = 8.66% of lines, 7.59% of tests, **8.79% of static sleep-seconds** — three estimators converge at 49-57 min, and match the independent postland `run_s` p50 of 50.9 min. |
| *"maybe the gate runs suites in parallel"* | **No.** `run_bats_all` loops `for _f in tests/*.bats` sequentially; zero `-j`/`--jobs`/`xargs -P` in the gate path. 10 cores, 1 used. |
| *"postland is a working safety net"* | **0 green stamps ever; daemon `disabled`; 24/24 red on the same 6 suites; ~10 h of admission wait in 32 h.** And `postland_net_live()` cannot trip its own staleness guard while zero green stamps exist. |
| *"sweep=review is a signal"* | 146/180 (81%) of *successful* lands emit it; only 07-19 ever produced `clean`. Saturated ⇒ non-discriminating by construction (`stranded-sweep.sh:16-19` documents this). |
| *"exit 9 protects against machine-cut false reds"* | It has **never fired**. The 6 signal-kills + 7 `exit 143` in `flakes.jsonl` were all absorbed as `pass-on-retry` one level below. |

## 8. Named blockers / uncertainties

- `flakes.jsonl` covers **23.7 h only** (26 records). No 14-day flake history exists to compare against.
- The `outcome` vocabulary in `flakes.jsonl` is `pass-on-retry` / `1-of-3` — **`cut-not-red` is not an emitted value**; if that label is expected, its producer is not writing.
- Pre-2026-07-26 land.log carries **no** `head/base/tree/gate_scope/selected_n` (127 of 341 ship-land lines) — those attempts are not replayable.
- 180 lands but only **62** carry a `tree` field ⇒ land-level tree provenance exists for 34% of the window.
- `gate_wait_s`/`gate_slot`/`loadavg` exist on **1** line — admission telemetry is effectively not in `land.log`.
- Load during my timed runs (2.9→5.6) is **far below** the 13-37 range in which every real gate red and every recorded flake occurred; my 49-57 min figure is a **best-case floor**.
- Whether the 13 `com.claude.*` jobs were *ever* loaded cannot be determined from disk — the override plist was rewritten at boot (Jul 27 19:05) and carries no history.