# C3 — What actually refuses a LOCAL-lane spawn, 2026-09-01 → 09-10

Read-only. Every number is a command that was run. Nothing was fired, claimed, or written outside
`$S/work-C3/` and this file.

---

## HEADLINE

**Machine capacity refuses ~nothing on the dispatcher's path, and has not for a month.** Across
**297 real dispatcher fire attempts** in the window (`~/.claude/logs/dispatch-fires.log`, block
headers `===== <ts> item= account= rc= pid= =====`, fixture-replay blocks excluded — see §6.9,
and cross-validated at **297 vs the IDL's 292** `fired`+`failed` rows), `handoff-fire`'s
`capacity_gate()` returned **rc 9 exactly ZERO times** — every day, all ten days. The 135
`capacity gate: REFUSING a net-new fire — load …/core > ceiling 2.0/core` lines in that log are
**all dated 2026-08-07 → 08-10**, outside the window.

**What binds NOW is account ELIGIBILITY at the wave planner, and its dominant term today is the
5-hour session cutoff, not the weekly.** For ~2 hours today (14:28–16:17Z) `ranked_n` fell to **1**
because three of four accounts sat at `session_pct 100` against `S_CUT = 0.85`. The planner then
offers `1 account × 2 slots = 2` against waves of **5–8 items**, and the residue lands as
`unplaced` — **158 rows today, the highest of the ten days**.

**The second binding term is the pane anchor** — **69 of 297 real fire attempts (23.2%) exited
rc 1**, 55 of the 80 `failed` rows naming a dead iTerm2 ring pane and 13 more refusing to mint a
fresh window. Entirely concentrated 09-07 → 09-10 (0 before).

**The capacity-admit gate DOES bind — but not on this lane.** 176 non-probe refusals, **142 of them
on the `active` term** (sessions mid-turn > 8) and 21 on `reserve-active`. Its callers are
`agent-tool`, `lr-fleet`, `boot-resume-launch`, `lr-fire-resume` — **never `cc-dispatch`**. And the
refusal is bounded: **47 `budget-expired` admits** show the 3-refusal budget releasing the spawn.
It delays; it does not cap.

---

## 0. WHERE THE RECORDS ARE — the lead's census missed them because the field is `hook`, not `tool`

| Store | Selector | Rows in window | What it answers |
|---|---|---|---|
| `~/.claude/autonomy/idl.jsonl` + 8 rotated `.gz` | **`.hook == "capacity-admit"`** (also `.gate == "capacity-admit"`) | **755** | capacity-admit verdicts, by term |
| same | `.actor == "cc-dispatch"` | 501,641 | dispatcher decisions/summaries |
| same | `.actor == "cc-wave-plan"` | 352 | placement walls (quota / routing) |
| `~/.claude/logs/handoffs.jsonl` | `.gate == "capacity"` | 487 (**377 `under_test`**) | `capacity_gate()` verdicts — **only 09-09T07:19 onward** |
| `~/.claude/logs/dispatch-fires.log` | `===== …` block headers | 3,140 blocks (**297 real**) | the fire's own stderr + **its rc** |
| `~/.claude/logs/account-utilization.jsonl` | per-sweep rows | — | weekly/session % per account |
| `~/.claude/logs/account-assignments.jsonl` | — | 212 (**only 09-08 onward**) | which account each fire got |

`_cc_admit_emit` (`scripts/lib/capacity-admit.sh:395-430`) writes `{hook:"capacity-admit", gate:
"capacity-admit", verdict, basis, caller, what, detail, term?, presence?, reserve?, terms?, blind?}`
to `${CC_ADMIT_IDL:-$HOME/.claude/autonomy/idl.jsonl}` (`:397`). **There is no `tool` key on the
row** — that is why a `tool==` census returned nothing.

`idl.jsonl.chain*` is a `<seq>\t<sha256>` hash sidecar, not data. Excluded.

**Parse failures: 2**, both in `idl.jsonl.20260907T055617Z.gz` — the two halves of one record split
at the 4,096 B stdio boundary (the known append-atomicity class). 0 elsewhere. Dedupe on
`(ts, line[:200])` across overlapping rotations removed 69 dispatcher + 2 capacity-admit rows.

---

## 1. PER-DAY TABLE

### 1a. Capacity — `capacity-admit` (IDL) and `capacity_gate()` (fire rc)

`probe` rows are non-binding by construction (`basis:"probe"`, detail *"probe — budget
untouched"*), so they are held out of the refusal column and shown separately.

| day | admits | **refusals by term** (non-probe) | probe (non-binding) | `capacity_gate` rc=9 |
|---|---|---|---|---|
| 09-01 | 15 | — | 0 | **0** |
| 09-02 | 50 | — | 0 | **0** |
| 09-03 | 13 | — | 0 | **0** |
| 09-04 | 37 | — | 0 | **0** |
| 09-05 | 45 | 11 — active 10 · load 1 | 0 | **0** |
| 09-06 | 16 | 20 — active 20 | 0 | **0** |
| 09-07 | 11 | 1 — active 1 | 0 | **0** |
| 09-08 | 33 | 38 — active 31 · load 5 · reserve-active 2 | 0 | **0** |
| 09-09 | 27 | 62 — active 59 · load 3 | 1 | **0** |
| 09-10 | 49 | 44 — active 21 · reserve-active 12 · segments 9 · load 2 | **282** | **0** |
| **Σ** | **296** | **176** — active 142 · reserve-active 21 · load 11 · **segments 9** · headroom **0** | 283 | **0** |

- **The `active` term binds, and it is the only term that binds materially**: 142 + 21 =
  **163 of 176** (92.6%).
- **`headroom` (4 GB) fired 0 times in 176 refusals** — unchanged from its historical record.
- **`segments` (50%) fired 9 times**, all `boot-resume-launch` on 09-10 at *"compressor segments 99%
  of limit"* — i.e. the boot storm, which is exactly the case the term was added for.
- **`load` (2.0/core) fired 11 times**, none of them on the dispatcher path (`lr-fire-resume` 11).
- ⚠️ **The 09-10 probe surge is partly OUR OWN**: 69 of 283 probes carry `caller:
  "cloud-lane-campaign"` — this research wave's own campaign, dated today. 211 are `lr-fleet`.
  Observer effect; do not read the 09-10 refusal spike as machine state.

### 1b. Quota / account routing — `cc-wave-plan` walls

| day | placements fired | **wave-overflow** (slots < items) | **capped** (no headroom) | **unknown** (router blind) |
|---|---|---|---|---|
| 09-01 | 15 | 0 | 0 | 62 |
| 09-02 | 16 | 0 | 0 | 4 |
| 09-03 | 23 | 0 | 0 | 17 |
| 09-04 | 26 | 0 | 0 | 17 |
| 09-05 | 0 | 0 | 0 | 0 |
| 09-06 | 0 | 0 | **1** | 0 |
| 09-07 | 21 | 9 | 0 | 15 |
| 09-08 | 12 | 8 | 0 | 11 |
| 09-09 | 8 | 3 | **1** | 12 |
| 09-10 | **46** | **18** | 0 | 7 |
| **Σ** | **167** | **38** | **2** | **145** |

- **145 of 185 walls (78%) are the ROUTER BLIND, not quota**: `evidence.reason` is
  `oracle-timeout` (99) or `rank-data-unavailable` (46), i.e.
  `claude-accounts --rank general exceeded the 20s bound` / `exited rc=3`. Corroborated in
  `~/.claude/logs/claude-accounts.log`: **2,045** `working_concurrency: walk exceeded budget_s=5.0`,
  **615** `concurrency: ps UNAVAILABLE (TimeoutExpired)`, ~250 `read_creds …keychain-error
  path=timeout`, 462 `probe next*: poll-throttled`.
- **The 2 `capped` walls are NOT quota exhaustion.** Their own evidence contradicts the message: on
  09-06 all four accounts read `session_pct 26/30/11/-` and `weekly_pct 27/9/5/-`; on 09-09,
  `k=0` on all four with weekly 24/20/16. `rank_rc=2` with a healthy fleet ⇒ an exclusion other
  than headroom emptied the set.
- **38 `wave-overflow` walls are the real quota/routing refusal**, and 18 of them are today.

### 1c. Pane anchors, unplaced, claimed — `cc-dispatch`

| day | fired | claimed | **failed** | pane-anchor share of failed | window-mint | **unplaced** | at-ceiling |
|---|---|---|---|---|---|---|---|
| 09-01 | 18 | 19 | 1 | 0 | 0 | 70 | 0 |
| 09-02 | 26 | 26 | 0 | 0 | 0 | 9 | 30 |
| 09-03 | 32 | 32 | 0 | 0 | 0 | 47 | 23 |
| 09-04 | 31 | 32 | 2 | 0 | 0 | 82 | **1,132** |
| 09-05 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| 09-06 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| 09-07 | 15 | 5 | 8 | **5** | 0 | 79 | 0 |
| 09-08 | 20 | 0 | 36 | **23** | 12 | 106 | 0 |
| 09-09 | 10 | 1 | 18 | **14** | 1 | 114 | 0 |
| 09-10 | **60** | 4 | 15 | **13** | 0 | **158** | 0 |
| **Σ** | **212** | **119** | **80** | **55** | **13** | **665** | **1,185** |

Fire-log rc, **real blocks only** (the rc is in the block header and is **not** truncatable, unlike
the stderr body). Fixture-replay items removed per §6.9; the row totals agree with the IDL's own
`fired`+`failed` count to within 1.7 %:

| day | 09-01 | 09-02 | 09-03 | 09-04 | 09-05 | 09-06 | 09-07 | 09-08 | 09-09 | 09-10 | Σ |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **real blocks** | 20 | 26 | 32 | 32 | 1 | 1 | 24 | 56 | 27 | 78 | **297** |
| rc=0 | 19 | 26 | 32 | 31 | 1 | 1 | 17 | 20 | 11 | 62 | **220** |
| **rc=1** (pane anchor) | 0 | 0 | 0 | 0 | 0 | 0 | 5 | 35 | 15 | 14 | **69** |
| rc=2/3/4/11 (other) | 1 | 0 | 0 | 1 | 0 | 0 | 2 | 1 | 1 | 2 | 8 |
| **rc=9** (capacity) | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | **0** |
| IDL `fired`+`failed` (control) | 19 | 26 | 32 | 33 | 0 | 0 | 23 | 56 | 28 | 75 | **292** |

**rc=1 is 69 of 297 = 23.2 % of every real fire attempt in the window, and 0 of them before 09-07.**

> **CORRECTED 2026-09-11 (fire-pane-anchor, landed with `tests/handoff-fire-split-bound.bats`) — the
> count stands, the diagnosis does not.** (1) *"0 before 09-07"* is a property of this doc's window,
> not of the defect: `dispatch-fires.log` holds 7 identical refusals on 08-07..08-11. (2) The anchors
> were **not** gone: 535, 643 and 672 each took successful splits hours after the fire that called
> them gone, and a kitty window id is never reused within one kitty process. (3) What actually
> failed: `it2_split` bounded a whole `it2-kitty session split` run with the 10 s one-IPC-round-trip
> `HF_TIMEOUT_S`, around a kitty launch it2-kitty itself bounds at 15 s. The outer bound killed
> splits kitty had already completed; the pane was running the predelivered brief, and the 0.8 s
> retry launched a second — fires 4b0095d1ee73, 6a5a218fd9a8 and 9d1c8dadf1f8 each left **two
> transcripts 12–16 s apart under ONE engagement marker** after printing "Nothing was launched".
> So these rows are not lost capacity alone: some are duplicate sessions. `d7b85c39c` (same day)
> touched only `session focus|read` and is not implicated. The §2 "Pane anchor" row should be read
> through this note.

---

## 2. "WHAT BINDS NOW" — verdict with one evidence line per candidate

| candidate | verdict | evidence |
|---|---|---|
| **Machine capacity (load / headroom / segments)** | **DOES NOT BIND** | 0 of **297** real dispatcher fires exited rc 9 in 10 days; the load term's last refusal of a dispatcher fire was **2026-08-10**; `headroom` 0/176 refusals ever in the window |
| **capacity-admit `active` ceiling (≤8 mid-turn)** | **BINDS — on the Agent-tool + recovery paths only, and BOUNDED** | 163 of 176 refusals; callers `agent-tool` 321 / `lr-fleet` 214 / `boot-resume-launch` 111 / `lr-fire-resume` 36 rows, **`cc-dispatch` 0**; 47 `budget-expired` admits prove the 3-refusal bound releasing the spawn |
| **Dispatcher ceiling (12 claimed workers)** | **DOES NOT BIND since 09-04** | `at-ceiling` = 1,185 rows, **all on 09-02/03/04**; 0 since. On 348,789 `defer reason=capacity` rows `live_workers` never once reached 12 (max observed 11), and `free_slots ≤ 2` on only 1,530 of them (0.44%) |
| **`defer reason=capacity` (348,789 rows)** | **NOT A REFUSAL** | queue arithmetic: ~5–10 dispatchable rows against 12 slots ⇒ the surplus defers every pass by construction; `free_slots` modal value is 9–10 |
| **Quota — weekly exhaustion** | **BINDS TODAY, on exactly ONE account** | `WEEKLY_FLOOR = 0.005` ⇒ excluded at ≥99.5%. `next` reads **weekly 100%** (reset 09-13T04:00). `next2` 95%, `next3` 51%, `next4` 75% are all **inside** the floor and are NOT weekly-excluded |
| **Quota — 5-hour session cutoff (`S_CUT = 0.85`)** | **THE DOMINANT BINDING TERM TODAY** | 14:28–16:17Z: `next:s100 next4:s100 next3:s100 next2:s1` ⇒ `ranked_n=1`, wave capacity **2 slots** against 5–8-item waves, 8 consecutive `wave-overflow` walls |
| **Account routing INSTRUMENT (router blind)** | **BINDS, and is the largest single wall class** | 145 of 185 walls: `oracle-timeout` 99 + `rank-data-unavailable` 46. Each is `action: retry-next-pass`, so it costs a whole pass |
| **Pane anchor (dead iTerm2 ring pane)** | **BINDS, 09-07 → 09-10** | 55 of 80 `failed` rows name *"ring pane N not found in iTerm2 (settled + retried) anchor gone; NOT firing into a random window"*; + 13 *"REFUSING to mint a fresh window"*; **69 of 297 real fire attempts (23.2 %) exited rc 1**, 0 of them before 09-07 |
| **Admitted-but-never-placed** | **BINDS, and is rising** — ⚠️ **REFUTED as a placement term 2026-09-11, see §8**: it is a LABEL over four other terms, not a term of its own | 665 `action:unplaced` rows, every one *"the wave planner placed no slot for it and no arm refused it — re-admitted next pass"*; 70 → 158/day, worst on 09-10 |

**One-line verdict:** *the local lane is capped by ACCOUNT ELIGIBILITY (5h cutoff → `ranked_n` → 2
slots/wave) and by PANE ANCHORS — not by the box, and not by weekly quota except on `next`.*

---

## 3. PER-TERM CEILINGS ACTUALLY IN FORCE (read from the deployed live copies)

Both live paths are **per-file symlinks into the SHARED CHECKOUT**
`~/Development/claude-infrastructure`, not into this worktree:

| live path | → target | vs this worktree |
|---|---|---|
| `~/.claude/scripts/lib/capacity-admit.sh` | `…/claude-infrastructure/scripts/lib/capacity-admit.sh` | **IDENTICAL** |
| `~/.claude/scripts/handoff-fire.sh` | `…/claude-infrastructure/scripts/handoff-fire.sh` | **DIFFERS, 13 lines — the LIVE copy is AHEAD.** It carries a tombstone-dedup fix (`readlink -f` on `.HANDOFF.json` paths, so a `~/.claude-next/projects` symlink is not counted twice) that this branch does not have. Not a capacity difference; flagged so nobody reads the live layer as stale here. |

Values in force (live `capacity-admit.sh`, no override found in `~/.zshrc`, `settings*.json`, or the
dispatcher plist's real `ProgramArguments`):

| term | env knob | ceiling | line | fired (10 d) |
|---|---|---|---|---|
| load | `CC_ADMIT_MAX_LOAD_PER_CORE` → `CC_HW_DEFAULT_MAX_LOAD_PER_CORE` | **2.0 / core** | `:161`, `:580` | 11 |
| headroom | `CC_ADMIT_MIN_HEADROOM_GB` → `CC_HW_DEFAULT_MIN_HEADROOM_GB` | **4 GB** | `:162`, `:666` | **0** |
| segments | `CC_ADMIT_MAX_SEGMENT_PCT` | **50 %** | `:711` | 9 |
| active | `CC_ADMIT_ACTIVE_CEILING` | **8 mid-turn sessions** | `:782` | 142 |
| reserve | `CC_ADMIT_ACTIVE_RESERVE` | **1** (⇒ effective 7 when the operator is present) | `:835` | 21 |
| budget | `CC_ADMIT_BUDGET` | **3 consecutive refusals**, then admit + page | `:581` | 47 releases |

`capacity_gate()` in the live `handoff-fire.sh` expands the SAME constants —
`CC_FIRE_MAX_LOAD_PER_CORE:-$CC_HW_DEFAULT_MAX_LOAD_PER_CORE` (`:5972`),
`CC_FIRE_MIN_HEADROOM_GB` (`:6077`), `CC_FIRE_MAX_SEGMENT_PCT:-${CC_ADMIT_MAX_SEGMENT_PCT:-50}`
(`:6120`), `CC_FIRE_ACTIVE_CEILING:-${CC_ADMIT_ACTIVE_CEILING:-8}` (`:6165`). **No drift.**

Router constants, `~/.claude/accounts.json` → `~/Development/claude-infrastructure/accounts.json`:

| constant | value | effect |
|---|---|---|
| `S_CUT` | **0.85** | `session_pct ≥ 85` ⇒ `5h-cutoff` exclusion — **the term that fired today** |
| `WEEKLY_FLOOR` | **0.005** | `weekly-exhausted` only at ≥99.5% (≥97.5% with credits) |
| `KMAX` | **8** | `kmax-concurrency` exclusion; also `cc-wave-plan`'s urgency bound |
| `KMAX_RESIDENT` | 40 | resident cap (pane-charged rows) |
| `CC_WAVE_MAX_PER_ACCT` | **2** | flat per-wave slots per account (`bin/cc-wave-plan:70`) |
| `CC_WAVE_MAX_PER_ACCT_URGENT` | **4**, bounded by `KMAX − k_eff` | widening only for a BEHIND account (`:77`) |
| `CC_DISPATCH_CEILING` | **12** (binary default; not set in the plist) | claimed-worker ceiling |

---

## 4. THE FOUR KEY QUESTIONS

**(i) How many spawn evaluations did capacity-admit refuse, by term — and did `active` ever bind?**
**176 non-probe refusals** of 472 non-probe evaluations = **37.3%**. By term: `active` **142**,
`reserve-active` **21**, `load` **11**, `segments` **9**, `headroom` **0**. **`active` binds and is
the dominant term** — *"8 sessions mid-turn + 1 > active ceiling 8"*, *"13 sessions mid-turn + 1 >
active ceiling 8 · operator present"*. It has bound on every day since 09-05. But it is a **delay,
not a cap**: 47 refusals were released by the 3-refusal budget (`basis:"budget-expired"`), and none
of its callers is the dispatcher.

**(ii) Fires lost to quota/routing vs pane anchors vs capacity.**

| cause | count (10 d) | store |
|---|---|---|
| **capacity (box)** | **0** | 0 × rc 9 over **297** real fire blocks |
| **pane anchor** | **69 of 297 real fire attempts = 23.2 %** (rc 1); of the 80 `failed` rows, **55** name a dead ring pane and **13** refuse to mint a window | `cc-dispatch action=failed` + fire-log header rc |
| **quota / routing wall (whole wave)** | **38** wave-overflow + **2** capped | `cc-wave-plan action=wall` |
| **routing INSTRUMENT blind (whole pass)** | **145** | `cc-wave-plan`, `oracle-timeout` / `rank-data-unavailable` |
| **admitted, never placed** | **665** | `cc-dispatch action=unplaced` |

Pane anchors beat capacity **69 : 0** on hard failures. Placement (quota/routing/planner) beats both
by an order of magnitude on rows lost: **665 unplaced**.

**(iii) Is throughput limited by a refusal at all, or by supply?** **Neither purely — it is limited
by SLOTS, which is a routing term.** Supply is **34 open rows** (fold of
`~/.claude/autonomy/backlog.jsonl`: 3,412 distinct ids → 3,117 done, 261 blocked, **34 open**;
matches the lead's 32 within the fold's tolerance). Per pass the dispatcher admits a mean of
**5.42** rows (max 10 on 09-10). The wave planner then offers **2–8 slots**. On 09-10, **285 of 320
passes fired ZERO**, and a representative pass reads
`admitted:10 fired:2 unplaced:7 deferred:10` — i.e. **7 of 10 admitted rows got no slot**.
Supply is not the cap (34 open > any wave), and no refusal is the cap; **the per-account per-wave
allowance is**, and it collapses when `ranked_n` collapses.

Throughput figures, with their denominators stated because they differ 5×:
- dispatcher `action=fired`: **212 / 10 d = 21.2/day** (but 0 on 09-05 and 09-06; 60 on 09-10)
- dispatcher `action=claimed`: **119 / 10 d = 11.9/day** — this is the ~13/day figure
- all `handoff-fire` account assignments (any caller, not just the dispatcher): **193 / 2.6 d =
  74/day** (`account-assignments.jsonl`, which only starts 09-08)

**(iv) If cloud sessions draw the same Max pool, does a cloud fire displace a local one? YES —
and under the pool the code assumes, the additive capacity is ZERO.** See §5.

---

## 5. ADDITIVE CAPACITY UNDER BOTH QUOTA HYPOTHESES

Today's readout, from `account-utilization.jsonl` (last row per account, 20:28Z):

| acct | weekly | 5h session | fable | k | weekly reset | h to reset | today's weekly burn (00→20Z) |
|---|---|---|---|---|---|---|---|
| next | **100 %** | 80 % | 100 % | 4 | 09-13T04:00 | ~55.5 | 42 → 100 = **+58 pp** |
| next2 | **95 %** | 1 % | 70 % | 2 | 09-12T11:00 | ~38.5 | 85 → 95 = **+10 pp** |
| next4 | **75 %** | 56 % | 78 % | 6 | 09-13T09:00 | ~60.5 | 38 → 75 = **+37 pp** |
| next3 | **51 %** | 10 % | 68 % | 6 | 09-15T12:00 | ~111.5 | 26 → 51 = **+25 pp** |

(The brief's `next4 73 %` is a same-hour reading; the 20:28Z row says 75. The 09-10 hourly series is
in `$S/work-C3/`.)

Fleet burn **+130 pp in 20 h = 1.56 account-weeks/day**. Headroom to the next reset: **0 + 5 + 25 +
49 = 79 pp**. At each account's own measured rate, all four run dry **before** their resets —
`next2` ~10 h of burn against 38.5 h, `next4` ~13.5 h against 60.5 h, `next3` ~39 h against 111.5 h
— so the projected **forced-idle time is ≈ 203 account-hours over the next ~4.6 days**, `next` alone
contributing 55.5 h. *"On pace to fill the window"* is exactly right, and the consequence is
recurring stretches with `ranked_n ∈ {0,1}`.

### Hypothesis A — cloud draws the SAME account pool (the mechanism-supported default)

**Additive capacity: ZERO. A cloud fire DISPLACES a local one, twice over.**

1. **Same credential.** `scripts/cloud-create-api.py` POSTs `/v1/code/sessions` with
   `Authorization: Bearer <the account's OWN keychain OAuth access token>` (`:176-195`, `:214-225`)
   — the same OAuth identity whose `/api/oauth/usage` drives `weekly_pct`. Tokens burned by the VM
   bill that account.
2. **Same router, same slot.** The cloud gate does not evaluate the box at all; it substitutes
   `claude-accounts --route general` (`scripts/handoff-fire.sh:5849`), the *identical* call
   `cc-wave-plan` ranks with. Its own words at `:5861`: *"A cloud fire is priced in ACCOUNT rate
   limit, and that is the only instrument that reads it."* So a cloud fire consumes one of the
   **2–8 wave slots** by construction. At today's 14:28–16:17Z state (`ranked_n=1`, 2 slots), a
   single cloud fire takes **50 % of the whole wave**.
3. **Second-order.** Cloud burn lowers `w_rem` and raises `session_pct`, which is the input to the
   `S_CUT = 0.85` exclusion that already emptied the ranked set for two hours today. Cloud fires
   would make `ranked_n` collapse *sooner and for longer*.

Under A the honest statement is: **a cloud lane buys ZERO additional Claude-quota throughput. What
it can buy is orthogonal — it removes the pane-anchor class (69 hard failures = 23.2 % of all real fire attempts) and the
box's `active ≤ 8` ceiling (163 refusals), neither of which is quota.** That is a real but
*capacity-neutral* win, and it should be argued on those two numbers, not on quota.

### Hypothesis B — cloud draws a SEPARATE pool

**Additive capacity: up to ~203 account-hours of currently-forced idleness over the next 4.6 days,
converted into working time — but the SHIPPED GATE CANNOT COLLECT IT.**

Because `capacity_gate()`'s cloud branch refuses on `--route general` returning `none`/rc≠0
(`:5867-5875`, `emit_fire_refusal cloud-account-policy`), a cloud fire is refused **for a quota
exclusion that, ex hypothesi, does not apply to it**. Under B the gate is wrong in the direction
that costs the most: it goes hardest to refuse exactly when local quota is exhausted, which is
precisely when the separate pool would be worth the most. **Under B the code change is mandatory,
not optional.**

### Which is true — UNRESOLVED, and it is cheaply testable

- **For A:** same OAuth bearer, same `usage_endpoint`, and the repo's own settled position at
  `handoff-fire.sh:5820-5861` (the whole cloud-gate design rests on it).
- **For B:** nothing. I found **no measurement anywhere in the repo** testing whether a cloud VM's
  tokens move `weekly_pct` — `docs/research/cloud-vm-roundtrip-2026-08-10.md` contains zero hits for
  `quota|rate.limit|weekly|5h|usage`.
- **No natural experiment exists in the window**: `cloud capacity gate` appears **1 time in 35 days**
  of `dispatch-fires.log` and **0 times** in 09-01…09-10, so the dispatcher fired essentially no
  cloud sessions and nothing can be attributed.
- **The discriminating test (one command, not run here — out of my read-only boundary):** pick the
  account with the *most* idle headroom and *no* live local session (today: `next3`, weekly 51 %,
  session 10 %), read `/api/oauth/usage` for it, fire ONE cloud session, let it run a bounded brief,
  re-read. A moved `weekly_pct`/`session_pct` with no local session on that account is A; a flat one
  is B. Positive control: the same read across a known-local fire on the same account.

---

## 6. ADVERSARIAL PASS — what I checked because it would have inverted the answer

1. **Split every ratio on `basis` and `blind`, as the gate's own header demands.**
   - **`fail-open` admits: 0** of 296. The IDL population is not contaminated by dead-probe admits,
     so the 37.3 % refusal rate is real.
   - **Blind admits: 20 of 296 = 6.8 %**, every one `blind: active`, every one from
     `boot-resume-launch` (18) or `lr-fire-resume` (2), **all on 09-01 → 09-07 and none after**.
   - `basis` on admits: `headroom-only` 159 (the Agent-tool path runs with the load term off —
     `terms: "headroom,segments,active"` on 321 rows), `measured` 90, `budget-expired` 47.
   - **The `active` term was BLIND on the dispatcher's fires on 09-07/09-08**: `capacity gate:
     active term BLIND (instrument unreadable) — noted, not fatal` appears on **17 of 17** gate-line
     blocks on 09-07 and **56 of 56** on 09-08, collapsing to 4 of 25 (09-09) and **2 of 72**
     (09-10). That is the subshell defect `handoff-fire.sh:5928-5951` documents, and its cure
     landing mid-window. **Consequence: any `active`-term claim about the dispatcher path before
     09-09 is unmeasured, not zero.** My headline does not rest on it — it rests on `rc`.
2. **`handoffs.jsonl` is 74 % test data AND is trimmed.** 377 of 487 `gate:"capacity"` rows carry
   `under_test:true` — every single `gate-off` row is a bats suite pinning
   `CC_FIRE_CAPACITY_GATE=off`. Counting them would have produced *"the capacity gate is disabled on
   77 % of fires"*, which is false. Production population: **101 measured admits + 2 budget-expired
   + 7 refusals**, all 7 on `active`. Separately, 5 `class:"trim"` rows show the ledger is capped at
   a 1,000-row suffix and has already dropped **61 refusals and 946 admits** — so **09-01 → 09-08
   `capacity_gate` history is unrecoverable from this store**. That gap is why §1a's rc=9 column
   comes from the fire log, whose header rc survives.
3. **My own first date attribution of the fire log was WRONG and would have shipped.** Anchoring on
   *any* ISO date in the text attributed 114 load refusals to "2026-08-07" and showed capacity
   ADMITs ending on 08-12 — because fire **briefs quote dates in prose**. The block header
   `===== <ts> item= account= rc= pid= =====` (`bin/cc-dispatch:690-691`) is the only sound anchor.
   Same family as the argv-census class: the instrument matched its own payload.
4. **78 % of the fire-log blocks in the window are NOT the dispatcher.** 2,435 of 3,139 are
   postland/fixture runs (`~/.claude/autonomy/postland/wt-run-82718/bin/cc-dispatch`, items `i1`,
   `i7`, rc=127 from a missing temp stub). Not excluding them would have made 09-04 read as 1,025
   fires.
5. **Is `capacity-admit` even on the local lane?** Checked, and the answer changes the whole
   framing: its callers are `agent-tool` 321 · `lr-fleet` 214 · `boot-resume-launch` 111 ·
   `cloud-lane-campaign` 70 · `lr-fire-resume` 36 · other 3 — **`cc-dispatch` never appears**. The
   dispatcher's fires are gated by `capacity_gate()` only. So *"capacity refuses 176 spawns"* and
   *"capacity refuses 0 local-lane fires"* are both true and are about different populations.
6. **The `capped` walls say "no account has general headroom" while their evidence shows a healthy
   fleet.** Both instances (09-06, 09-09) carry `rank_rc=2` with every account under 30 % weekly and
   under 62 % session. The message names quota; the data refutes it. Treated as an unexplained
   exclusion, **not** counted as quota exhaustion.
7. **The dispatcher's 348,789 `defer reason=capacity` rows are not refusals** and reading them as
   such would invert the verdict. `free_slots` modal 9–10; `live_workers` never observed at the
   ceiling of 12; `free_slots ≤ 2` on 0.44 % of them.
8. **This wave is in its own data.** 69 `cloud-lane-campaign` probe rows dated today. Held out.
9. 🚨 **A FIXTURE REPLAY USING REAL-LOOKING HEX ITEM IDS defeated my first real/fixture filter, and
   I shipped a wrong number for one draft.** My first pass excluded only `i\d+` items and postland
   body text, leaving **704 "real" blocks** and a headline class of **138 `rc=7` "pane→tty resolver
   CANNOT TELL"** failures. Every one of those 278 rc=7 blocks was fixture: 140 carry item `i1`, and
   the rest carry `723d9e9cff68` and `7d5ccfd3f67b` — each appearing **exactly 69 times**, all on
   `next3`, all with the identical one-line body. **The tell that broke it open is a control I
   already had**: 09-05 and 09-06 recorded `sum_fired: 0` in the IDL, yet the log showed 48 and 30
   "real" blocks on those days — a day with zero fires cannot have thirty fire attempts. Corrected
   filter = repetition count ≥ 20 (plus `i\d+`), giving **297 real blocks against the IDL's 292
   `fired`+`failed`** — a 1.7 % gap fully explained by `fire_log_keep` only running when the fire
   captured stderr. **`rc=7` is now 0 in the real population and is retracted entirely**; `exit 7`
   occurs exactly once in `handoff-fire.sh` (`:7708`) and is the *self-close* resolver, never a fire.
   The rc=9 = 0 claim is unaffected — it was 0 across fixture and real alike.

---

## 7. BLOCKERS AND UNCERTAINTIES

- **`capacity_gate()` history before 09-09 is destroyed** (1,000-row trim). Reconstructed only via
  the fire log's header rc, which is sound for *refused/not-refused* but carries no term attribution
  and no admit basis. There is no way to say which term admitted a 09-01 fire.
- **The fire log truncates each block to `tail -c 8192`** (`bin/cc-dispatch:693`), and the gate lines
  are printed FIRST. The absence of `capacity gate:` lines on 09-01 → 09-06 is therefore *ambiguous*
  — truncation or silence — and must not be read as "the gate did not run". The rc column is
  unaffected.
- **Why `ranked_n=2` at 20:11Z when three accounts look eligible** (`next2` w95/s1, `next4` w69/s21,
  `next3` w50/s6) is unresolved. Candidate exclusions in `_excluded` (`bin/claude-accounts:2975-3003`)
  are `5h-cutoff`, `concurrency-unmeasured`, `kmax-concurrency`, `cliff drain`. Resolving it needs a
  live `claude-accounts --rank general --explain`, which perturbs the router cache and can time out
  at 20 s — out of my read-only boundary.
- **`account-assignments.jsonl` starts 09-08** and **`handoffs.jsonl` starts 09-09**, so both
  per-account and per-gate history is 2–3 days deep, not 10.
- **The routing instrument is unhealthy and that is itself a finding, not just noise**: 2,045
  concurrency-walk budget overruns, 615 `ps UNAVAILABLE`, ~250 keychain timeouts, and **464
  tracebacks reading `RuntimeError: simulated keychain explosion` — a TEST fixture writing into the
  production accounts log.** 145 wave-plan passes were lost to this. Not in my scope to fix; flagged.
- **Cloud quota-pool hypothesis is UNRESOLVED and cannot be resolved from this box's history** —
  no cloud fires in the window, no measurement in the repo. §5 gives the discriminating test.

---

## 8. CORRECTIONS — 2026-09-11 (the wave planner's two walls, measured and fixed)

### 8a. "Admitted-but-never-placed" is a label, not a binding term

The row's own reason text was the whole evidence for §2's verdict, and it was never tested. The
question that separates a placement bug from queue arithmetic is whether the planner had a FREE
slot when the row went unplaced. Each of the **658** `action:unplaced` rows still in the IDL
(**156 passes**, 2026-09-01..11) was joined to the wave planner's own records inside its pass
window `[pass-id start, summary ts]`:

| rows | passes | what actually let the row go |
|---|---|---|
| **417** | 88 | a `WALL[unknown]` refused the whole wave — the account oracle timed out (§8b) |
| **140** | 31 | surplus past the `capacity=<n>` a `WALL[capacity]` reported, cut by the dispatcher's re-plan |
| **92** | 36 | the planner **placed** them; the spawn loop stopped at `MAX_SPAWN=2` (a per-pass cap, `bin/cc-dispatch:169-172`) |
| **9** | 1 | a `WALL[capped]` refused the wave |

**Zero** were a free planner slot left unused, so there was no placement bug. The fixed reason
text was false for all four classes, and it hid the dominant one (the oracle wall, 63%). The fix
makes each arm name its cause on the row (`cause` ∈ `wall-<verdict>` · `capacity-surplus` ·
`spawn-cap` · `not-placed` · `unattributed`) and adds `unplaced_by_cause` to the pass summary, so
this census is now one jq read. The ceilings are named, not changed: `MAX_SPAWN=2` is deliberate.
Note what that does to §4(iii)'s *"the per-account per-wave allowance is"* the cap: on 36 passes
the planner placed more than the dispatcher would ever spawn, so for those passes the binding term
was `MAX_SPAWN`, not the planner's allowance.

### 8b. The router-oracle wall was the READ, not the bound

Re-measured from the IDL (09-01..11): **83 `oracle-timeout`** (60 on `--rank`, 22 on cc-route after
a successful rank, 1 on `--json`) and **6 `rank-data-unavailable`** — fewer than §1b's 99 + 46
because the pre-09-01 rotation behind §1b's 09-01 column (62 unknown that day) is no longer on disk.

- **Runtime at the dispatcher's own QoS** (`/usr/sbin/taskpolicy -c background`, the planner's call
  order, 5 rounds spaced past the 90s TTL): cold `--json` sweep **3.8–5.1 s**, warm `--rank` /
  `cc-route` **1.3–2.3 s**. The 20 s bound is not tight on a quiet box; the walls are loaded moments.
- **What fills the 20 s** (45 s before each wall vs the 160 placed passes as control): `ps` census
  timeout **14% vs 0%**, usage-fetch failure **14% vs 0%**, heal **0% vs 0%**, keychain timeout
  **0% vs 0%**, nothing logged at all **54%**. No single account's probe blocks the rest.
- **What decides it:** at **83 of 83** walls a successful sweep had completed ≤ **488 s** before the
  call began (p50 238 s, p90 375 s) — inside claude-accounts' own `cache_grace_s` (600 s). The
  planner read with the 90 s TTL, re-swept, and timeout(1) killed a sweep that therefore never
  wrote the cache: 51 of the 60 rank walls had lost their `--json` snapshot the same way.
- **Fix:** the planner reads with `--max-age <cache_grace_s>` (SSOT, default 600) on both reads and
  passes it to cc-route's inner `--route`. The bound is unchanged. Kill switch
  `CC_WAVE_ORACLE_MAX_AGE_S=0`.
- **`rank-data-unavailable`:** 5 of 6 were `concurrency-unmeasured` on all four accounts (a starved
  `ps`), cured at the producer by `9465e0119`; the 6th was a genuine all-account `no data (http
  None)`, where `retry-next-pass` stays correct. No planner change.
