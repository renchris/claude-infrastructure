# B3 — The cloud RETURN arm as a throughput system

Measured 2026-09-10T20:00–20:45Z. Read-only. Every number below is a count over a named store or a
`file:line`; theoretical extrapolations are labelled THEORETICAL.

## Verdict in one line

The arm is **capacity-starved, not input-starved**: 13 branches sit RETURN-READY and **all 13 are
`git merge-tree` CLEAN**, while **25 of 25 land invocations since 09-08 were SIGKILLed by the lane's
own 5,400 s bound** — 0 completed. The land never finishes because its dominant cost term
(`gate_arms_s`, ~100% of the wall) runs **2.6× the box median and exceeds 3,500 s 34× as often**
in the *fresh per-attempt worktree* desk-land mints, and because the unlocked optimistic gate round
(1,800–5,300 s) is longer than trunk's inter-commit gap (median 431 s) so it is invalidated ~96% of
the time and re-rounds straight into the bound.

---

## Instruments, coverage, parse failures

| Store | Rows | Parse failures | Coverage |
|---|---|---|---|
| `~/.claude/autonomy/idl.jsonl` | 115,980 | **0** | live file starts **2026-09-09T13:57:06Z** (rotated; 9 `.gz` archives) |
| + archives `…20260908T082141Z.gz`, `…20260909T135330Z.gz` | 226 lane rows total | **0** | 2026-09-07 → now |
| `~/.claude/autonomy/cloud/return.jsonl` | 3,035 | **0** | not rotated; Aug → now. The continuous instrument. |
| `~/.claude/land.log` | 9,852 (5,552 `tool:"ship-land"`) | **0** | 2026-07-11 → now |
| `bash scripts/cloud-reconcile.sh --list` | 431 rows | — | run live, rc 0 |

**Instrument warning 1 — `returned` is NOT a land count.** Sept has **35** `outcome:"returned"` rows
against **5** completed `ship-land` invocations on `claude/*` branches. Most `returned` rows are the
`state == LANDED` path (`cloud-return.sh:548` region): the branch was already on trunk and the arm
collected the paperwork (wake, custody, backlog, content-verify). Any throughput claim built on
`returned` overstates delivery ~7×.

**Instrument warning 2 — `return.jsonl` systematically undercounts land ATTEMPTS.** A pass SIGKILLed
inside the `RECONCILE_BIN` command substitution (`cloud-return.sh:756`) writes no per-session row at
all: the `land-cut` arm at `:781` is *below* the call that dies. Hence **0 `land-cut` rows on
09-08..09-10 while 25 lands were attempted and killed.** `land.log` is the only complete instrument
for attempts, because ship-land writes its own attestation row from inside its own kill path.

**Instrument warning 3 — the lane script is 4 days old.** `scripts/cloud-return-lane.sh` landed
`7d72371ca` 2026-09-07T00:18. Lane journal rows do not exist before 09-07 by construction; the
09-01..09-06 passes ran inline in `autonomy-sweep.sh`.

---

## (i) Delivered lands per day, pass count, pass rc mix — 09-01..09-10

`returned` = the arm's own delivery record. `exit-0 lands` = `land.log` `tool:"ship-land"`,
`branch` starting `claude/`, terminal `exit:0` (grouped by the per-attempt repo dir, which carries
the invoking pid and so uniquely identifies one `RECONCILE_BIN` call).

| day | passes¹ | admitted² | sessions examined³ | land invocations⁴ | **exit-0 lands** | `returned` rows |
|---|---|---|---|---|---|---|
| 09-01 | 3 | 75 | 61 | 6 | **1** | 0 |
| 09-02 | 14 | 350 | 21 | 18 | **0** | 7 |
| 09-03 | 16 | 400 | 22 | 10 | **0** | 1 |
| 09-04 | 20 | 500 | 184 | 13 | **0** | 16 |
| 09-05 | 20 | 497 | 107 | 18 | **0** | 3 |
| 09-06 | 9 | 225 | 105 | 5 | **1** | 1 |
| 09-07 | 12 | 252 | 97 | 10 | **3** | 7 |
| 09-08 | 12 | 219 | 12 | 9 | **0** | 0 |
| 09-09 | 13 | 163 | 35 | 5 | **0** | 0 |
| 09-10 | 13 | 151 | 33 | 11 | **0** | 0 |
| **Σ** | 132 | 2,832 | 677 | **105** | **5** | **35** |

¹ `outcome:"pass-scope"` rows. ² `taken` field — `deferred` was **0 on every pass in the window**,
so the `--limit 25` never bound. ³ per-session ledger rows with a real id. ⁴ distinct
`/private/tmp/.desk-land-<branch>-<pid>` dirs in `land.log`.

**Delivered lands/day = 0.5 over the 10-day window; 0.0 over the last 3 days.**

### Lane pass rc mix (from 09-07, when the lane began journaling)

| day | `cloud_return_rc` 0 | 137 (SIGKILL at bound) | 4 (lock held) | total spawns | **real cycles** |
|---|---|---|---|---|---|
| 09-07 | 5 | 5 | 7 | 17 | 10 |
| 09-08 | 0 | 12 | 34 | 46 | 12 |
| 09-09 | 3 | 9 | 30 | 42 | 12 |
| 09-10 | 1 | 11 | 59 | **71** | **12** |

**83% of offered ticks on 09-10 hit a held lane lock and did nothing.** The lane is running flat out
at exactly 12 cycles/day and discarding 59 spawns. That single row settles question (iv) — see below.

Sibling passes in the same cycle: `cloud_retire_rc` 0 ×38 (elapsed 5–259 s, median ~110 s), 124 ×6,
137 ×2. `cloud_answer_rc` **124 in 4 of 4** — the answer pass has never once completed; it burns
300 s of every cycle and emits no tally line.

---

## (ii) Land-cost distribution, gate vs local-only

### Per-invocation cumulative wall (`total_s` of the terminal row; T0 is inherited across rounds, `ship-land.sh:1384`)

| population | n | p50 | p90 | max | min |
|---|---|---|---|---|---|
| **COMPLETED** cloud lands (exit 0), Sept | 5 | **1,935 s** | 9,797 s | 13,757 s | 926 s |
| **KILLED** cloud lands (143/137/124), Sept | 57 inv / 67 rows | 723 s | 5,224 s | 5,316 s | 12 s |
| rebase-conflict (exit 5) — pre-checked away since `3b'` | 40 | 14 s | 48 s | 157 s | 3 s |
| gate-red (exit 6) | 4 | 670 s | 2,957 s | 3,880 s | 495 s |
| box-wide exit-0 lands since 09-08 (all branches) | 228 | 1,754 s | 4,534 s | 14,955 s | — |

### The gate / local split — this is the load-bearing measurement

| term | COMPLETED cloud lands (n=5) | KILLED cloud lands since 09-08 (n=30) |
|---|---|---|
| `gate_s` / `total_s` | 67.6 – 98.0% | **97.0 – 99.9%** (p50 0.90 over all Sept rows) |
| `gate_arms_s` (15 whole-tree ratchets) | 571 – 2,471 s | **arms/total p50 = 1.00, p90 = 1.00** |
| `gate_statics_s` (shellcheck · `bash -n` · `py_compile`) | 0 – 5 s | **p50 = 0.0000, p90 = 0.0000** of total (absolute p50 = 4 s) |
| `smoke_s` (bats smoke) | 0 – 12,111 s | **0** — `smoke:"none-unreached"` on 21 of 30 rows |
| **local-only** (`total_s − gate_s`: fetch, identity re-author, rebase, lock, push, content-verify) | 279 – 1,024 s (median **298 s**) | median **23 s** (the land dies before reaching them) |

**Answer to key question (ii): the part a VM could pre-run is 0.0–0.1% of a cloud land's wall.**
`gate_statics_s` p50 is 1 s over all Sept cloud rows; smoke never runs at all. The dominant term is
`gate_arms_s`, and the arms are whole-tree ratchets over **trunk's** state, not the branch's — trunk
took **302 commits in 47.3 h (153/day)**, so a VM-side pre-run is invalidated before it can be used.
**Off-box gate pre-run is ruled out on evidence, not on principle.**

### Why the cloud land's arms are expensive — the `gate_rounds=1` control

Comparing only first rounds, excluding the cheap exit-5 rows (apples to apples):

| repo location | n | arms p50 | arms p90 | max | P(arms ≥ 3,500 s) |
|---|---|---|---|---|---|
| session worktree `~/Development/.worktrees/*` | 740 | **340 s** | 615 s | 16,683 s | **1.1%** |
| desk-land per-attempt tree `/private/tmp/.desk-land-*` | 64 | **870 s** | 5,193 s | 5,283 s | **37.5%** |

`desk-land.sh:148` mints `$WTROOT/.desk-land-<branch>-$$` — a **fresh `git worktree add` per
attempt**, removed after (`:176`). Every cloud land therefore pays a cold checkout and runs 15
whole-tree ratchets against a page cache nothing has warmed. The p50 is **not censored** (half the
population is below 870 s), so the 2.6× median gap is a real reading, not a survivorship artifact.

**Named confound:** the `/private/tmp/.desk-land-*` bucket contains **129 of 129 `claude/*` rows and
nothing else**, so this data cannot separate *tree warmth* from *cloud branch identity*. The
`gate_rounds=1` median comparison is the strongest available control; it is not an A/B. Falsifier:
run one cloud land with `desk-land --worktree <a warm worktree>` and read `gate_arms_s`.

### The bound wall is visible as a cluster, not a distribution

13 of 30 cloud rows since 09-08 have `total_s ∈ [5,100, 5,450]`: 5,110 · 5,160 · 5,169 · 5,175 ·
5,177 · 5,188 · 5,221 · 5,222 · 5,227 · 5,246 · 5,290 · 5,305 · 5,316. A cluster on an exact cap
boundary is the signature of a bound, not of the work.

---

## (iii) The arithmetic ceiling

**Measured cycle structure.** return (bounded 5,400 s, `+10 s` kill grace ⇒ observed 5,410–5,417
when cut) + retire (~110 s median) + answer (300 s, always cut) ≈ **5,820 s ≈ 97 min**. Measured
**12 real cycles/day** on each of 09-08, 09-09, 09-10 (12 × 5,820 = 69,840 s = 19.4 h).

**Measured fixed pre-land cost F ≈ 190 s** (lane `took=5,411` against ship-land `total_s=5,221` on
the 09-10T19:46 cycle). At a working set of 11–14 the pass reaches the first land within ~3 minutes;
the 675 s figure the header cites was measured at a 466-declaration population that no longer exists.

`BUDGET_S = BOUND_S × 80% = 4,320 s` (`cloud-return.sh:170`). Landing time per cycle = 4,320 − 190 =
**4,130 s**.

### THEORETICAL — lands/day for one serialized lane

| land cost C | lands/cycle | cycle wall | cycles/day | **lands/day** |
|---|---|---|---|---|
| 344 s (`<id>.land-cost` median, 36 non-floor values) | 11 | 4,384 s | 19.7 | **11–14** (population-capped) |
| 926 s (cheapest completed cloud land) | 4 | 4,304 s | 20.1 | **80** |
| **1,935 s (p50 completed cloud land)** | 2 | 4,470 s | 19.3 | **38.7** |
| 1,754 s (box-wide exit-0 p50) | 2 | 4,108 s | 21.0 | **42.1** |
| 4,534 s (box-wide exit-0 **p90**) | **0** — `land_res ≥ BUDGET_S` ⇒ `fits_bound=false`, never started | 5,820 s | 14.8 | **0** |
| 9,797 s (**p90** completed cloud land) | **0** — same | 5,820 s | 14.8 | **0** |

**At the 5,400 s bound with the measured pass cadence (12 real cycles/day) and the head-of-line
behaviour that actually occurs (one land started per cycle): ceiling = 12 lands/day. Delivered = 0.**

**The cliff.** Any land priced ≥ 4,320 s is *never started* (`land-deferred`, `fits_bound=false`);
any land that *runs* past ~5,210 s is SIGKILLed. Since the completed-cloud-land distribution has
p50 1,935 and p90 9,797, **roughly 30–40% of the cost distribution is structurally unlandable at
this bound.**

**The price gate is currently inert and is not what is stopping it.** `.return.land_cost` holds
`1788962701 54` — written 2026-09-09T14:05:01Z, now **110,231 s old against `COST_TTL_S=21,600`**
(`cloud-return.sh:202`), so `cost_read` returns 0, `land_res` floors at `LAND_RESERVE_S=120`, and
every land reads as affordable. Hence **zero `land-deferred` rows since 09-08**. The kill is the
binding constraint, not the price.

---

## (iv) "Why zero since 09-08" — verdict: CUT BY BOUND, compounded by a stale-gate livelock

**Verdict: cut by bound. Not population exhaustion, not cached refusal, not price deferral, not lock
contention.** Each alternative was tested and refuted:

| candidate | evidence AGAINST |
|---|---|
| population exhausted | 11–21 pending admitted **every** pass, `deferred:0` on all 38 passes since 09-08. 13 ELIGIBLE branches, **all merge-tree CLEAN**, all with a live `cc-cloud` state (11 STALLED, 2 ALIVE). |
| all cached-refused | only **2** branches ever hit the cache in the window: `claude/fire-20260907T063702Z-97029-1` (rc 6, 21 hits — retired 09-10T16:09) and `…20260909T004425Z-75839-1` (rc 69, 9 hits). 30 cached rows over 3 days, 2 distinct branches. |
| cut by bound | **25 of 25 invocations terminate `exit:143` `verify:"killed"`**; `selected_n:-1` (gate never reached suite selection) on 21 of 30 rows; lane rows `137 ×12/09-08, ×9/09-09, ×11/09-10` at elapsed 5,410–5,417 s. ✅ |
| deferred by price | **0 `land-deferred` rows since 09-08** (the price file is TTL-expired; see above). |
| lock contention | 5 `claude/*` land-lock `release` rows since 09-08: `wait_s` 0,0,0,1,0 · `hold_s` 2,4,2,4,2. Box-wide `wait_s` p50 0, p90 363, max 1,700. |

### The compounding mechanism — the exit-42 stale-gate livelock, quantified

`ship-land.sh:4496` releases the lock and re-rounds when `origin/main` moves during the **unlocked**
optimistic gate. Observed on `claude/*`: 13 exit-42 rows in Sept, 5 since 09-09, and **every one is
followed by a 143** — 42 @ 1,802 s → 143 @ 5,316 s; 42 @ 4,726 → 143 @ 5,222; 42 @ 3,644 → 143 @
5,175; 42 @ 3,835 → 143 @ 5,177; 42 @ 2,057 → 143 @ 5,169.

Trunk cadence over the same 47.3 h: **302 commits, median gap 431 s, p90 1,163 s, p99 3,713 s; only
11 of 301 gaps ≥ 1,800 s and 2 ≥ 5,400 s.** A cloud gate round costs 1,800–5,300 s, so
**P(a round survives un-invalidated) ≈ 4%**. Box-wide the rail absorbs this — 453 exit-42 rows
against 228 exit-0 since 09-08, i.e. ~2 invalidated rounds per success, and **32% of successful lands
needed 4 rounds** — because an ordinary session's `/ship` carries no external timeout. The cloud
land is killed on its second round, every time, so it can never reach the rounds-exhausted fallback
that saves every other land on this box. This is exactly the shape already on record in this repo's
memory as *"Optimistic round cannot outrun its contention"*, met from inside a bound.

### Adversarial check — is "zero" a journal artifact?

**No.** Requested cross-check run: `git log origin/main --since=2026-09-08 --grep='Cloud-session:'`
returns exactly **1** commit — `140c2889b feat(cloud-lane): the retire census was a string…`. It was
**not landed by the lane**: `land.log:9749` shows it as `head` of a land from
`repo:/Users/chrisren/Development/.worktrees/wt-b622f1a6fdfc`, `branch:"wt-b622f1a6fdfc"`,
`sid:aa434080…`, `exit:0`, `total_s:4303`, `gate_rounds:4`, at 2026-09-10T15:50:24Z — a **local
session's own worktree**, i.e. a human/agent adopting cloud-originated work and landing it through
the ordinary rail. 09-01..09-07 carries 15 such trailers. So the zero is real and there is a
**second, undocumented delivery path (adoption) that is currently outperforming the arm**.

Second artifact check: the arm's own ledger shows `abstain why:"state UNKNOWN"` ×40 since 09-08,
which could have read as "the sessions are unmeasurable". Refuted live —
`bin/cc-cloud list --json --state --only <the 13 ids>` returns a real state for **13 of 13**
(11 STALLED, 2 ALIVE). Those abstains are transient control-plane read failures under load, not a
standing block.

---

## (v) RETURN-READY inventory, right now

13 ELIGIBLE of 431 declarations (417 RETIRED, 1 header row). **All 13 are managed** (`notify_back`
and `custody` both set), so all 13 are inside `--sweep`'s admission rule. `git merge-tree
--write-tree origin/main origin/<branch>` run on each:

| branch (`claude/fire-` stripped) | merge-tree | ahead | behind | cherry `+` | cached refusal | quiet for | cc-cloud state |
|---|---|---|---|---|---|---|---|
| 20260901T183237Z-34341-1 | **CLEAN** | 1 | 740 | 1 | none | 6.8 d | STALLED |
| 20260902T052138Z-77815-1 | **CLEAN** | 1 | 710 | 1 | none | 6.9 d | STALLED |
| 20260903T083656Z-91310-1 | **CLEAN** | 1 | 678 | 1 | none | 6.9 d | STALLED |
| 20260903T164436Z-45303-1 | **CLEAN** | 1 | 676 | 1 | none | 5.6 d | STALLED |
| 20260903T235525Z-18437-1 | **CLEAN** | 1 | 628 | 1 | none | 5.6 d | STALLED |
| 20260904T105305Z-58678-1 | **CLEAN** | 2 | 598 | 2 | none | 5.6 d | STALLED |
| 20260904T170832Z-32559-1 | **CLEAN** | 1 | 573 | 1 | none | 5.6 d | STALLED |
| 20260907T062706Z-17724-1 | **CLEAN** | 1 | 461 | 1 | none | 3.5 d | STALLED |
| 20260907T063547Z-45873-1 | **CLEAN** | 1 | 460 | 1 | none | 3.5 d | STALLED |
| 20260909T004425Z-75839-1 | **CLEAN** | 1 | 278 | 1 | **rc 69, HIT** | 1.7 d | STALLED |
| 20260910T123101Z-19701-1 | **CLEAN** | 1 | 52 | 1 | none | 7.7 h | STALLED |
| 20260910T185102Z-27906-1 | **CLEAN** | 1 | 14 | 1 | none | 35 min | ALIVE |
| 20260910T200055Z-43095-1 | CLEAN (0 ahead) | 0 | 2 | 0 | none | 35 min | ALIVE (running) |

**12 landable branches, 0 conflicts, 1 permanently latched out.** The first 7 all carry
`item=1f6208064577` — one backlog item holding seven branches.

**Head-of-line blocking is what the arm is actually doing.** Ordering is newest-first
(`cloud-return.sh:1130` `sort_by(.declared_at) | reverse`), so the pass descends to the newest
ELIGIBLE branch and lands *that*. Verbatim, every cycle since 09-10T12:55, from
`~/.claude/logs/cloud-return-lane.log`:

```
cloud-return: 14 of 14 pending managed session(s) this pass (cursor 0 → 0, 0 deferred, limit 25)
· session_01QqJ3UhznNmncs2Jo8McnHd — worker_status=running; still running
· session_01Kqn3SaXdAvzUwPdaeGc3v5 — pushed 111s ago; needs 180s quiet
? session_01C31A8kxF7VTGstdBNZQiUg — cc-cloud could not measure it; abstaining
→ session_01MvTEDYFpHHXEQ48MzPmJax — landing claude/fire-20260910T123101Z-19701-1 via cloud-reconcile.sh
[5,411 s later] Killed: 9 … return pass rc=137 took=5411s — cut by the lane bound (5400s)
```

Four of fourteen admitted sessions examined; **the other ten are never touched.** Consistent with the
table above: 33 per-session rows across 13 passes on 09-10 (≈2.5 per pass out of 11–14 admitted).

### The permanent latch — a real, unbounded defect

`session_01G8BdNzxaQUQ99BSQByUqna` is cached out on `rc=69`, whose own artifact reads:

> `!! cloud-reconcile: SENSOR FAILED — could not read 'origin' (git ls-remote). This is 'cannot look',
> NOT 'nothing to land'`

`cloud-reconcile.sh:82` classifies 69 as **SENSOR FAILED — never read as absence**, i.e. the same
class as 9 GATE-KILLED / 75 LOCK-STARVED, which `cloud-return.sh:~800` deliberately exempts from the
cache (`case "$land_rc" in 9|75)`). **69 is missing from that arm.** Because the cache keys on the
branch head and the VM is STALLED (it will never push again), `seen_sha` can never move — so the
"cannot latch shut" property the code's own comment claims is false for this class. 9 cached rows in
3 days; branch is CLEAN and 1 commit ahead.

---

## (vi) Ranked engineering changes

| # | change | expected effect | cost | evidence |
|---|---|---|---|---|
| **R1** | **Land in a warm, reused worktree** instead of `git worktree add` per attempt. `desk-land.sh:151` already names the flag (`--worktree`). | `gate_arms_s` p50 870 → ~340 s; P(arms ≥ 3,500 s) 37.5% → 1.1%. Lands/day **0 → 12** (tick-capped) or **~24** at 2 lands/cycle. **The single highest-leverage change.** | one persistent worktree + a reset between lands + one flag on the desk-land call. Race risk low (lane is single-flight). | `gate_rounds=1` control table above |
| **R2** | **Stop re-proving under contention** on the lane's land: `SHIP_LAND_GATE_ROUNDS=0` + raised `LAND_LOCK_WAIT`. | eliminates the 42→143 pattern (5 of 25 recent invocations, 20%); land wall becomes lock-wait (p50 0 s, p90 363 s, max 1,700 s) + statics-only in-lock re-gate (statics p50 1 s). | 2 env vars. **HAZARD:** they are inherited by bats subprocesses and `tests/ship-land.bats` asserts the behaviour they change; `ship-land.sh:1995` `env -u`s both, **but ship-land.sh is a per-worktree file** — read the scrub in the copy that will execute. | 13 exit-42 rows; trunk gap histogram (11/301 ≥ 1,800 s) |
| **R3** | **Do not cache a refusal that is not a finding about the tree** — add `69` to the `9\|75` exemption arm. | +1 branch immediately; closes an unbounded class (any transient `ls-remote` blip permanently strands a clean branch of a retired VM). | **1 line** + a fixture. | `session_01G8BdNzxaQUQ99BSQByUqna.land-refused` rc 69; `cloud-reconcile.sh:82` |
| **R4** | **Remove the outer bound on the LAND** (keep it on the pass's non-landing work); let ship-land self-bound, per this repo's own *"never wrap /ship in your own timeout"*. Make the lane's `LOCK_TTL` dynamic. | alone (without R1/R2): lands complete at 1,935–13,757 s ⇒ ~4–8/day, but cycles stretch to ~4 h so paperwork starves further. **Do this after R1/R2, not before.** | lock TTL becomes dynamic; cc-reaper already exempts the argv. | 25/25 exit-143; the [5,100, 5,450] cluster |
| **R5** | **Do the free dispositions before the expensive one** — classify all admitted rows, then land. | 10–11 sessions per pass currently never examined would get supersede / custody / wake / retire-eligibility every pass instead of never. The retire pass's own header claims this ordering benefit and the return pass's death defeats it. | ~20 lines in the loop at `cloud-return.sh:1220`; no change to the lander. | 33 rows over 13 passes vs 151 admitted, 09-10 |
| **R6** | **Fix or evict the answer pass** — 4 of 4 `cloud_answer_rc` are 124 at 300–301 s. It has never completed and never printed a tally. | recovers 300 s of every 5,820 s cycle (5.2%) and makes the pass's function exist at all. | one number, or a separate launchd job. | `answer_rc_124: 4` of 4 |

### Ruled out, with the reason

- **Have the VM pre-run the gate.** The pre-runnable fraction (`gate_statics_s` + `smoke_s`) is
  **0.0–0.1%** of a cloud land's wall. The dominant term is whole-tree ratchets over **trunk**, which
  moves 153 commits/day, so any VM-side result is stale before it is used.
- **Push webhook / 60 s poll.** See (iv) below — buys 0 lands/day.
- **Raise `--limit`.** `deferred:0` on all 38 passes since 09-08; the limit has never bound.
- **Raise `CC_RETURN_QUIET_S` / relax RETURN-READY.** Only 3 `waiting` rows since 09-08; the
  conjunction is not the gate.

---

## Answer to key question (iv) — push-trigger instead of sweep tick

**Delivered rate change: zero. Latency change: ~8 minutes per branch.**

On 09-10 the sweep offered the lane **71 spawns and 59 (83%) exited rc 4 — the lane lock was already
held.** The lane consumes 12 cycles/day and is offered ~71. A webhook or 60 s poll raises the offer
to ~1,440/day; every additional one exits 4. The trigger cadence is **already 6× over-supplied.**

THEORETICAL, both regimes:
- **Current bound, p50 cost (1,935 s):** 12 cycles/day × 2 lands = 24 lands/day capacity. Arrival
  over 09-01..09-10 was **73 distinct branches reaching the lander in 10 days = 7.3/day** (and cloud
  fires themselves have collapsed: 20–32/day on 09-01..09-04 → 5, 0, 0, 1, 4 on 09-07..09-10).
  Capacity 24 > arrival 7.3, so **all 73 branches would have landed** — arrival-limited, not
  trigger-limited.
- **Push-triggered + p50 cost:** 73 lands × 1,935 s = 39.2 h of lane time inside a 240 h window.
  Same answer, reached sooner.

So the honest statement is: **at every measured arrival rate the trigger is slack. The binding
constraints are the land's cost and the bound that kills it.** A webhook would reduce mean
RETURN-READY→attempt latency from ~8.7 min (half the 17.4 min mean inter-spawn interval) to ~30 s —
~10 h of aggregate latency over the window, and not one extra land.

---

## Named uncertainties / blockers

1. **One pass ran 2.36× its bound and was not cut.** `idl.jsonl` 2026-09-09T22:19:58Z:
   `{"cloud_return_rc":"0","elapsed_s":12745,"bound_s":5400,"load1":32.86}`. The obvious explanation
   (`$TMO` empty because `timeout` is `/opt/homebrew/bin` only and absent from launchd's stock PATH —
   verified: `env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin sh -c 'command -v timeout'` ⇒ ABSENT) is
   **refuted for the deployed path**: `autonomy-sweep.sh:227-247` records that the plist interposes
   `/bin/zsh -lc`, a login shell that sources `~/.zprofile:1` → `brew shellenv`, and 45 of 46 passes
   *were* cut at exactly 5,410 s. Unexplained. Falsifier: add `timeout_bin` to the lane's
   `cloud-return` row and read one week.
2. **The tree-warmth cause is not A/B-separated.** `/private/tmp/.desk-land-*` contains 129 of 129
   `claude/*` rows and nothing else, so *cold tree* and *cloud branch* are confounded. R1 is ranked
   first on a median comparison at matched `gate_rounds=1`, which is the strongest available control
   but is not an experiment. One `desk-land --worktree` run settles it.
3. **`gate_arms_s` has no per-arm breakdown.** `ship-land.sh:708` accumulates one scalar; there is no
   arms log. Which of the 15 ratchets dominates in a cold tree is unmeasurable from disk today.
4. **The sweep tick rate I measured (~71 spawns/day on 09-10, one per ~17.4 min) differs from the
   ~28/day the brief cites** from `~/.reso/research/cloud-lane-2026-09-10/B-local-pipeline.md §2b`.
   Mine is a count of lane-authored `cloud-return` rows (rc 4 + real cycles) and is corroborated by
   the sweep's per-tick `config-parity` (62) and `self-bound` (63) dispositions on 09-10. Both may be
   right about different days or different definitions; I report mine and flag the disagreement
   rather than reconciling it.
5. **`idl.jsonl` rotates.** Any lane census must union the live file with `idl.jsonl.*.gz` or it
   silently starts on 09-09. The archives I read (`…20260908T082141Z`, `…20260909T135330Z`) cover
   09-07 onward; earlier archives were not opened because the lane script did not exist before
   09-07T00:18 (`7d72371ca`).
6. **A second delivery path exists and is undocumented in the lane's model:** local sessions adopting
   cloud branches and landing them from their own worktree (15 `Cloud-session:` trailers on trunk
   09-01..09-07, 1 since). Any "cloud work delivered" metric that reads only `return.jsonl` misses it.
