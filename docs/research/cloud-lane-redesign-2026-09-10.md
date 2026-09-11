---
status: measured
date: 2026-09-10
scope: frontier research campaign (Fable 5.1, max effort) — retire / repair / redesign the 24/7 cloud backlog lane
---

# Cloud backlog lane — retire, repair, or redesign? (2026-09-10)

CONVICTION: RETIRE — 70% (harvest the 10 landable units first; the three follow-ons in §8 stand regardless; the class-C packet in §8 carries REPAIR-narrow as the live alternative)

**The operator's question was whether a productive cloud pipeline is a technical impossibility. It is not.**
The lane's 12.8% yield is a set of named, small landing-arm defects plus a latency architecture, and a
replay of every stranded branch against the trunk that existed at its own push shows **90% would have
landed an hour after the push** (§3.1). Repaired, the lane lands at roughly a third of local's quota cost
per row (§4.2). What the campaign refutes is not the lane's *feasibility* but its *purpose*: the plan
defines it as a capacity valve, and both halves of that valve are measured absent — cloud sessions draw
the **same** Max quota as local ones (vendor-stated and reproduced at p = 6.5e-06, §4.1), and machine
capacity **does not bind** the local dispatcher at all (0 refusals over 297 fire attempts, §4.3). What
binds the fleet today is the 5-hour quota cutoff, a blind account router, dead iTerm2 pane anchors and
admitted-but-unplaced rows — none of which a VM relieves, and two of which a cloud fire worsens by taking
the same router slot and burning the same meter. Against that, the lane has consumed 10% of every closed
backlog row and 5% of trunk commits since August as its own maintenance, 68% of its docs output is a
report about its own mis-dispatch, and it carries a trust boundary (131 remote-authored commits
re-authored as the operator). The residual 30% is the operator's call, and the devil's advocate (§7)
earned it: the maintenance figure is one-sided (genuine lane-machinery rows are 2.9%, not 10%), a
repaired arm plus a denylist correction would offer 4–10 rows/day rather than 2 with no widening of the
VM's scope, and quota headroom with a dark local lane was observed at the last weekly resets. Whether a
pane-free venue at 0.8× token cost is worth keeping when the box that must land its output is the thing
already short of time is filed as a class-C decision with REPAIR-narrow as the live alternative (§8).

Every number below has a receipt: the twelve subagent reports and the lead's own measurements are landed
beside this file under `docs/research/cloud-lane-redesign-2026-09-10/`, each naming the command it ran.
Read-only throughout: no cloud session fired, no backlog row claimed, closed or unblocked, no plist edited.

---

## 1 · The frame, corrected — three denominators loaded the dice

| what the brief carried | what it divides by | the corrected reading |
|---|---|---|
| "23 of 353 rows eligible off-box = 6.5%" | all non-done rows, **88% of which are operator-blocked** | over the 36 agent-drainable rows (32 open + 4 claimed) the classifier admits 7 = 19%; under a split design 7 (19%) with no config change, 13 (36%) after cross-repo attach — `A1-reach-stratum.md` |
| "12.8% yield" (88 landings / 688 fires) | fires, 82% of which were re-fires of 51 items | per **item** 77 of 160 declared items carry land evidence = 48%; the true landed population by trunk trailer is **108 of 692 declarations = 15.6%** (26 landed sessions appear in neither store) — `D1-hostile-reviewer.md`, `D2-what-landed.md` §1.3 |
| "the pile" (352 rows) as the thing to drain | a stock that is 80% the operator's | the agent-drainable stratum went 352 → 32 in eight days and none of it is over 30 days old; the backlog is a **flow** of ~40-55 adds/day, and the local lane already closes ~100 rows/day around the clock with no dead hours — `A-drain-rates.md` §5, `B-local-pipeline.md` §6 |

The lane's own plan does not price it as a drain. `docs/plans/CLOUD_BACKLOG_PIPELINE.md` §4: *"routing to
cloud is a CAPACITY decision, not a cost one."* So the decisive questions are the two the brief listed
third: does cloud add quota, and does the box run out of machine capacity. §4 answers both.

---

## 2 · Number 1 — REACH under a split design

Split = the VM implements, runs the hermetic test partition, pushes; this Mac verifies live state and lands.

| population | n | split-reachable | Wilson 95% CI | today's classifier admits | receipt |
|---|---:|---:|---|---:|---|
| the agent-drainable **stock** (open + claimed, read row by row, no sampling) | 36 | 7 (19%) with no config change · 13 (36%) after per-item repo attach + `gh` | 10–35% · 22–53% | 7 (19%) — **3 of the 7 are false admits**: plan-advance rows about this box's own drain machinery, two of them held by live cloud workers right now | `A1-reach-stratum.md` |
| the real-fix **flow**, last 30 days (seed 20260910, n=60 of 647) | 60 | **36 (60.0%)** · 75.0% once the landing arm's own `re-land <branch>` duplicates are excluded · ≤51.7% both implementable and self-provable off-box | 47.4–71.4% · 61.2–85.1% | 66 of 646 = **10.2%**; the classifier is **62.5% false-negative over its refusals** (35 of 56) and right on only 4 of the 60 | `A2-reach-flow.md` |

Why stock and flow disagree: the stock is what the local lane left behind — enriched for re-lands, box
investigations and not-yet-true preconditions. The flow is what a 24/7 lane would actually be offered.
`ineligible-box` is 54% of the flow and **20 of its 27 sampled rows are split-reachable**: the classifier
refuses on the word "box" where the box is needed only to verify.

Pricing the four configuration changes (`A3-config-pricing.md`, each re-derived by `cc-eligible why` on
all 126 rows in the four classes):

| change | verified | rows unlocked (open / claimed / blocked) | agent-drainable yield | cost |
|---|---|---|---|---|
| `gh` in the VM | **already true** — docs: *"Utilities: git, gh, jq, yq…"*, `gh` reads `GH_TOKEN` automatically; `bin/cc-eligible:456`'s "no gh CLI off-box" is false | 0 / 0 / 1 | 0 | 0.5 h to correct the class |
| full-depth clone | **already run inside a real VM** — landed commit `26af2dc3b` body: *"Checkout arrived shallow at depth 50 and was unshallowed first"*; refutes §A2b's blocker | 2 / 0 / 2 — both open rows already worked off-box | 0–2 | 1–2 h (`CLOUD_DEPTH` + an abort interlock) |
| attach the item's own repo | control plane returns 200 for reso, doc_classifier, sevenrooms-bridge, pivot-table-library (negative control 404); `renchris/personal` has no repo; docs: *"`--cloud` works with a single repository at a time"* | 9 / 0 / 58 — 7 of the 9 open are phone calls and payments | **4** (all sevenrooms-bridge) | 6–10 h |
| headless browser + dev server | no browser in the docs' tool table; environment config is GUI-only | 0 / 0 / 3 | 0 — seeded sample **6 of 6 refuted** (cookie, passkey, aesthetic ruling, unlanded branch, sign-off, false-positive token) | ≥12 h, unbounded |

**Reach is not the constraint.** The flow is wide (60%); the classifier is the narrow thing, and it is a
spelling denylist that its own header says cannot acquit. A fifth failure mode spans all four changes:
*eligible ≠ drained* — both open deep-history rows were already worked by cloud sessions, their branches
and verdict artifacts exist, and the ledger never moved. Adding supply to a lane whose return path is the
bottleneck converts configuration spend into more un-returned branches.

---

## 3 · Number 2 — YIELD: the 12.8% is a fixable landing arm, and the fix is small

### 3.1 The stranded branches, replayed (`B1-stranded-branches.md`)

430 `claude/fire-*` refs on origin; 381 ahead of trunk; they resolve to **87 distinct items**, 274 of
them on items with 8+ sibling branches (one item fired 33 times). For every branch, `git merge-tree
--write-tree <trunk sha that existed at push+Δ> <ref>` plus the item's first `done` transition:

| land attempted at | trunk commits gained (median) | conflict | superseded | **landable** |
|---|---:|---:|---:|---:|
| the push itself | 0 | 3.1% | 3.7% | **93.4%** |
| **+ 1 hour** | 2 | 6.3% | 3.9% | **90.0%** |
| + 6 hours | 13 | 9.2% | 5.0% | 86.9% |
| + 24 hours | 46 | 25.2% | 8.9% | 69.3% |
| + 7 days | 311 | 60.9% | 32.3% | 28.1% |
| today (actual) | 900 | 74.0% | 85.8% | **5.5%** |

The `conflict` and `superseded` retire verdicts are both effects of elapsed time. The observed median lag
from a branch's last push to the *first land-shaped event of any kind* is **207 h (8.6 days)**; 2.9% got
one within an hour; 106 of 381 never received one at all. The lane lost to the desk, not to itself: of
327 `done` records on superseded items, 1 names a sibling cloud branch; 81% cite a local session.
Hot files are a multiplier, not the mechanism (files trunk never touched: 0% conflict at push; the hottest
stratum: 10% at push, 71–81% at the observed lag). Sibling multiplicity is the accelerant (the 8+-sibling
stratum is 86% conflicted at the same age; 6% at +1 h).

**Landable now: 20 branches carrying novel content across 10 distinct units of work** (4 docs-only, 16
code); seven of the 20 are duplicate fires on one item (`1f6208064577`, pick one). Cross-checked with a
second instrument (`git apply --3way --check`), 19 of 21 agree.

### 3.2 The refusals, autopsied (`B2-refusal-autopsy.md`)

The 1,016 `land-refused` events are **80 branch heads asked 12.7× each**; the head-keyed cache
(`d3e207b61`, 2026-08-25) closed that loop (attempts per refused session 16.1 → 1.0). By distinct cause:

| cause | rc | state | verdict |
|---|---|---|---|
| re-authoring failed on a reaped `TMPDIR` | 70 | **cured** `33cf5df17` 2026-08-17 — 0 recurrences, 46 successful re-authors after | — |
| commit-msg refusal of the VM's AI-attribution trailer block | 70 | **live, 5 of 5 cases are a reconciler bug**: `strip_trailer_block()` (`cloud-reconcile.sh:495-533`) demands the block be *exactly* the final paragraph; a `(cherry picked from …)` line or adjacent prose defeats it, and the refusal then blames the VM | fixable, ~10 lines |
| rebase conflict | 5 | by design; the `merge-tree` pre-check (`7d72371ca`) prices it in ~1 s | — |
| branch gone from the remote | 65 | by design (retired VM); mis-framed to the originator as "LAND REFUSED" | cosmetic |
| `git ls-remote` sensor failure **latched by the refusal cache** | 69 | **live defect**: `cloud-return.sh:797` exempts only desk-land's 9 and 75; a session refused rc 69 on 09-09 has emitted `land-refused-cached` every pass since and can never move | fixable, ~3 lines |
| `arm=stale` routing (630 of 675 routing events, "routed to nobody") | — | **a defect, the largest**: `stale_resolved()` ARM 2 (`cloud-refusal-route.sh:395-402`) tests file **presence** on trunk, not content, so every edit-only branch reads as already-landed and bypasses classification; ≥358 of 630 (57%) were wrong, ≈479 (76%) estimated | fixable, one predicate |
| `routed-originator` logged on undelivered sends | — | 273 of 313 rows are `no-such-target`; the dedupe store is skipped on failure so one refusal re-sent 97 times | fixable, ~2 lines |

Today's dominant abstention is a seventh cause the brief did not name: **13 of 19 sessions examined
since 09-08 pushed with `paths=` empty**, which `cloud-reconcile.sh:171` returns 1 on and `:848` skips
(`D1-hostile-reviewer.md`); the fix is parked on a ruling about landing content nobody declared.

### 3.3 The return arm as a throughput system (`B3-return-arm-throughput.md`)

**Capacity-starved, not input-starved.** Thirteen branches sit RETURN-READY right now, all thirteen
`git merge-tree` clean, while **25 of 25 completed land invocations since 09-08 terminate `exit:143
verify:"killed"`** — cut by the lane's own 5,400 s bound (`land.log` holds 36 rows on `claude/*` in the
window: 25 × 143, 10 × 42 STALE-GATE rounds that are not separate invocations, 1 × −1). Delivered: **0.5 lands/day over 09-01..09-10, 0.0 over the last
three days**; the only post-09-08 `Cloud-session:` commit on trunk (`140c2889b`) was landed by a local
session adopting the branch, not by the arm. Two instrument corrections: `returned` rows are paperwork
for already-landed content, not a land count (35 in September against 5 completed `ship-land`
invocations on `claude/*`), and a pass SIGKILLed inside the lander writes no row at all, so
`return.jsonl` shows 0 `land-cut` while `land.log` shows 25 kills.

Why a land is expensive, and it is not the VM: `desk-land.sh:148` mints a fresh `git worktree add` per
attempt, so every ratchet memo is cold — arms p50 **870 s** with a 37.5% chance of exceeding 3,500 s
(n=64), against **340 s** and 1.1% in a warm session worktree (n=740). Statics are ~4 s and smoke is
never reached (`smoke:"none-unreached"` on 21 of 30); **the pre-runnable fraction of a land is ~0.1%**,
because the cost is whole-tree ratchets over *trunk*, which the VM's tree is not. Then the livelock:
13 `exit:42 STALE-GATE` rows on `claude/*` and every one is followed by a 143 — trunk's median
inter-commit gap is 431 s, a cloud round costs 1,800–5,300 s, so P(a round survives) ≈ 4%. The price
gate that should defer such lands is inert (`.return.land_cost` is 110,231 s old against a 21,600 s TTL
and reads 0). Ceiling at the actual bound and cadence: 12 lands/day; delivered 0. The sweep offers ~71
spawns/day and 83% exit on a held lock. A push-triggered spawn would buy nothing: arrival is 7.3
branches/day against a 24/day capacity at p50 cost — the arm is arrival-limited once it can complete a
land at all.

Ranked repairs (each measured, none touching the VM): **R1** land in a warm reused worktree
(`desk-land.sh:151` already names `--worktree`; arms 870 → 340 s; 0 → 12–24 lands/day) · **R2**
`SHIP_LAND_GATE_ROUNDS=0` + a raised `LAND_LOCK_WAIT`, ending the 42 → 143 pattern (20% of
invocations; the vars leak into bats and `ship-land.sh:1995`'s scrub is per-worktree) · **R3** add
`69` to the `9|75` non-verdict exemption (one line; a STALLED VM is permanently latched out today) ·
**R4** remove the outer bound on the land (the repo's own rule: never wrap `/ship` in your own timeout)
— sequenced after R1/R2 · **R5** classify every row before landing (10–11 of 14 admitted sessions are
never examined per pass) · **R6** the answer pass has never completed (4 of 4 at rc 124).

### 3.4 What repair would yield

Post-cure the dispatcher fires ~2 cloud sessions/day (the already-declared gate, `124c4da06`, cut
re-fires from 4.27 to 1.00 per item and fires from ~30/day). A repaired arm — R1–R4 above, the trailer
stripper, the stale predicate, the `paths=` fill, and a VM-side `git fetch && git rebase origin/main`
before the final push — has a measured capacity of 12–24 lands/day against 7.3 arrivals/day and would
land on the order of **90% of pushes** (the +1 h replay row). That is roughly **2 landed rows/day at
today's fire rate**, bounded by supply (§2), not by the arm. The repair is days, not weeks; none of it
touches the VM. **The number that decides between repair and retire is therefore not technical: the
arm can be made to work, and what it would then deliver is two rows a day.**

---

## 4 · Number 3 — ECONOMICS: what cloud buys that local cannot

### 4.1 Same quota pool (`C1-quota-pool.md`)

Vendor-stated: `code.claude.com/docs/en/claude-code-on-the-web` § Limitations — *"Claude Code on the web
shares rate limits with all other Claude and Claude Code usage within your account… There is no separate
compute charge for the cloud VM."* Binding on us because `scripts/cloud-create-api.py:175-210` creates
the session with the account's own keychain OAuth token and `organizationUuid` — the same identity as the
local binary. Reproduced independently: on 55 hours where the firing account had zero interactive
sessions and zero transcript activity, a cloud fire moved that account's server-side weekly meter in
**14 of 55** hours against **0 of 65** matched control hours (Fisher one-sided p = 6.5e-06), replicated
on two accounts, with a ±3/±7-day placebo returning 0 of 35 and a dose-response of +0.14 pp per fire
across three concurrency strata. No cloud-shaped bucket has ever appeared in the usage payload. Two arms
could not be run and are named as such (terminal-state error text is too terse; no idle-hour follow-up
sends exist).

Consequence: **cloud adds zero quota.** At today's readout (next 100% LIMITED, next2 95%, next4 75%,
next3 51%, all four on pace to fill their window; fleet burn +130 pp in 20 h) a cloud fire displaces
local work — and the fire rail already refuses an off-box fire when `claude-accounts --route general`
returns nothing (`handoff-fire.sh:5867-5875`), so the lever disarms itself exactly when reached for.

### 4.2 Cost per landed row (`C2-cost-per-landed-row.md`)

Cloud usage read from `external_metadata.usage` on 44 declared sessions (98% strata coverage, seed
20260910); local from 15 dispatched transcripts found by their `HANDOFF-ENGAGE-` marker across 2,656
transcripts, subagent sidecars included. Price-weighted at Opus 5 list as an equivalence, never a bill.

| | per fire (mean / median) | fires per landed row | per landed row (mean / median) |
|---|---|---:|---|
| cloud | $5.63 / $4.67 | 7.78 (692 ÷ 89) | **$43.80 / $36.30** |
| local dispatched | $21.38 / $12.33 | 1.48 (566 ÷ 382) | **$31.67 / $18.27** |

On medians cloud costs **1.2–2.05× local per landed row** (the direction is invariant across a 16-cell
sensitivity grid on medians, and flips on means). The whole gap is conversion: per fire cloud is cheaper
even after discounting the selection effect (cloud gets pre-screened easier work; matched code landings
run 0.91× local, reproducing the 08-11 A/B's 0.81×). Waste is not full price — a superseded session
costs 0.48× a landing — but a conflicting one costs **1.22×**: the full task, pushed, then refused.
Docs-only cloud landings cost $4.49 against $12.74 for code. **At the post-gate re-fire rate with
landings restored, the same data puts cloud at $5–6 per landed row against local's $18** — the case for
repair, stated at its strongest.

### 4.3 What binds the local lane (`C3-local-refusals.md`)

The 755 `capacity-admit` evaluations in the window are keyed on `hook`, not `tool`, which is why an
earlier census found none. Over 09-01 → 09-10:

| candidate constraint | binds? | evidence |
|---|---|---|
| machine capacity (load / headroom / segments) | **no** — 0 rc-9 refusals over 297 real dispatcher fire attempts; last load refusal of a dispatcher fire 2026-08-10; `headroom` fired 0 times | `capacity-admit` rows; fire rc |
| `active ≤ 8` mid-turn sessions | binds **other lanes only** (Agent tool, lr-fleet, boot-resume: 163 of 176 refusals), never `cc-dispatch`, and is bounded (47 budget-expired releases) | same |
| dispatcher ceiling 12 | dead since 09-04 (all 1,185 `at-ceiling` rows are 09-02..04) | `cc-dispatch` rows |
| weekly quota | binds on one account (`next` 100%) | readout |
| **5-hour cutoff `S_CUT = 0.85`** | **the binding term today**: 14:28–16:17Z three accounts at `session_pct 100` ⇒ `ranked_n = 1` ⇒ 2 wave slots against 5–8-item waves; 8 consecutive `wave-overflow` walls | `cc-wave-plan` rows |
| the router itself | the largest wall class: 145 of 185 walls are `oracle-timeout` / `rank-data-unavailable`; 464 `simulated keychain explosion` tracebacks from a test fixture in the production accounts log | `claude-accounts.log` |
| dead iTerm2 pane anchor | **binds 09-07 → 09-10**: 69 of 297 fire attempts = 23.2% rc 1 | `cc-dispatch failed` |
| admitted-but-never-placed | rising: 665 rows, 70 → 158/day; a typical pass reads `admitted:10 fired:2 unplaced:7`; 285 of 320 passes on 09-10 fired nothing | `cc-dispatch unplaced` |

A cloud fire takes one of the same 2–8 wave slots by construction (it routes through the identical
`claude-accounts --route general` call) — **50% of the whole wave** at today's `ranked_n = 1` — and its
burn feeds the same `S_CUT` that emptied the ranked set. What cloud does buy is capacity-neutral: it
needs no pane and no `active` slot. Those two constraints are local-lane wiring defects (the anchor
refusal is a fail-safe against firing into a random window; the unplaced rows are the wave planner
yielding nothing), each cheaper to fix directly than to route around through a VM.

---

## 5 · What the lane has actually landed, and what it has cost

**Landed** (`D2-what-landed.md`): 108 sessions with content on trunk (26 more than either store knows —
the census is code-biased against itself). Of 82 resolved landings: 44% docs-only, 55% code-bearing
(median code diff 304 lines / 4 files, max 1,083). **Zero reverts and zero re-lands across all 112
landed shas** — the work the VM does is sound. Push → land latency on successes: median 17.9 h, p90 114 h.
38% of landed items would be refused by today's classifier, mostly by arms the lane's own venue reports
caused to exist. Never landed: a single commit in reso-management-app or doc_classifier — zero `claude/*`
branches were ever pushed to either remote; the 13 cross-repo items produced only venue essays and 109
reopen events. 19 of 28 close failures are `cc-backlog done: unknown id` — the ledger lives outside the
repo the VM receives.

**But the largest docs output is the lane documenting its own mis-dispatch**: of 38 docs-only landings,
17 are venue/eligibility self-reports and 9 are "the cure was already on trunk before this row fired"
disproofs — 68% of docs output is a report on the dispatcher, not work on the item.

**Cost** (`LEAD-notes.md`, corrected by `W2-devils-advocate.md` §ii): backlog rows mentioning the cloud
lane — done 313 of 3,118 (10.0%), blocked 27 of 260 (10.4%), open 5 of 31 — but that regex is one-sided:
of 273 done rows matching `cloud`, 146 carry it only in evidence or source, 61 of those cite a cloud
session as the row's *closing* evidence (lane output booked as cost), and 20 are auto-minted
`re-land claude/fire-*` rows, the SIGKILL defect's own symptom. **Genuine lane-machinery rows: 89 =
2.9%.** Trunk commits since 2026-08-01 touching lane files: 157 of 3,049 (5.1%), 8–56 per week; on the
same file set maintenance commits (110) roughly equal landed cloud commits (131), and 51% of the
maintenance sits in the W32–33 build-out. Lane code and tests: 20,167 lines. Forward maintenance is not
measurable from this window (§10) and is not spent as if it were. Every cloud
return is a full `ship-land` gate on this box (non-floor median 344 s, max 3,977 s) behind the same
land lock every local session waits on. And 131 `Cloud-session:` commits sit on trunk re-authored as
the operator: the identity gate refuses `noreply@anthropic.com` on purpose, `cloud-inbox.py` refuses
VM-composed commands as remote code execution, and every widening of the VM's reach (repos, `gh`, a
browser) widens an unreviewed remote author's reach.

---

## 6 · The three options in plain English, with their measured outcomes

**RETIRE — stop firing cloud sessions; harvest what is landable; keep nothing that only the lane
needs.** Measured outcome: no loss of drain throughput today (the agent stratum is 32 rows, the local
lane closes ~100/day and converts 89% of claims); ten units of landable work collected once; the 31
blocked rows about the lane's machinery become moot; 20K lines and ~26 commits/week of maintenance stop;
the trust boundary closes; the land lock stops carrying cloud returns. **It must be sequenced, or it
strands work** (`W2-red-team.md`): the dispatcher's already-declared gate (`bin/cc-dispatch:2103-2127`)
drops every cloud-planned item that holds an unlanded declaration *before* its local fallback
(`:2759-2762`) and has no TTL, so if the retire/return passes stop first, the six open/claimed rows
currently held by the 14 unretired declarations (`1f6208064577`, `badb132df232`, `c18e7ea9e6b1`,
`9f8a985115a9`, `64c150ba2a8e`, `1dd6fbb6766c`) never fire in either lane. Order: settle the 14
declarations (retire or return) and disable the six-hourly `cc-venue` relabel pass
(`autonomy-sweep.sh:1311-1328`), then remove `CC_FIRE_CLOUD=on` from the two plist argv by a staged
migration (the opt-in is not agent-editable; four cloud sessions fired today under it), then abandon
the 133 open cloud custody debts with a reason, and keep `bin/cc-cloud` plus the declaration store
read-only so `is-offbox` consumers and the one `live-cloud-worker` block (`2a65b9bf722d`) still resolve. Cost: forgo a pane-free venue and
a ~10–20% per-session token saving on the rows it would take; forgo the option value when quota has
headroom and the local lane cannot fire — a conjunction that WAS observed (09-05/06: the dispatcher fired
zero and three accounts then reset at 21–49%, ≈2–2.5 account-weeks stranded; 09-08/09: 50 pane-anchor
failures at weekly 16–24%). On both occasions the cloud lane fired nothing either, so what stranded the
quota was the dispatcher, which follow-on 2 addresses without a VM.

**REPAIR — fix the landing arm, and (narrow variant) correct the classifier's denylist without widening
the VM's scope.** Measured outcome: the seven named defects are days of work and would lift conversion
from ~15% toward the replay's 90%. At the classifier's ~2 fires/day that is ~2 landed rows/day; at the
pre-gate offer rate (4.7 items/day) it is ~4/day; with the denylist's 62.5% false-negative corrected
(30 of 36 split-reachable flow rows need no config change) it is ~10/day — all at $5–6 each on the
quota meter against local's $18 (`W2-devils-advocate.md` §ii). It keeps the lane's machinery, the
router-slot displacement when quota binds, and the trust boundary, and adds no quota. It is the right
move if the operator values a pane-free venue and stranded-quota conversion above those costs.

**REDESIGN — change what the VM does.** The brief's split (VM implements + hermetic tests, box verifies +
lands) is reachable for 60% of the real-fix flow and the VM's work is sound, but its cost premise is
refuted: the VM cannot pre-run any useful part of a land (statics + smoke are ~0.1% of the wall; the
cost is whole-tree ratchets over trunk, §3.3), so every VM push still costs the box a full gate behind
the same land lock. It also widens the trust boundary and inherits the split's measured failure mode: a cloud-claimed "real fix" is 3.7× likelier to be a docs artifact or to have no
traceable commit (48% vs 13%), because an unverified VM has a cheaper way to satisfy the ledger than
fixing anything. The narrow variant — VMs take only verdict-shaped rows (one cold file, a new
`docs/research/*.md`, landed within six hours: the profile of every landing that worked) — removes the
conflict class and the trust concern, but local research subagents do the same work at the same quota
with no lane to maintain; the VM's only edge there is a pane it does not need.

---

## 7 · Adversarial pass

**Hostile reviewer, frontier tier, before the memo existed** (`D1-hostile-reviewer.md`): the plan calls
the lane a capacity valve while the brief priced it as a drain, and nobody measured demand for a valve
(seven eligible rows against ~100 local closes/day: "a perfect arm lands a week of local output, once");
both headline denominators were loaded (per-item yield 48%); the strongest case for REPAIR is that the
lane delivers (131 trailer commits, 5.1% of trunk, 10 this week) and the fire collapse is downstream of
the return arm; the strongest case for REDESIGN is the VM's one structural edge, no iTerm2 pane, against
the local lane's binding wiring defect. Three dimensions the brief omitted — demand, contention on the
box's serialized land resource, and the trust boundary — all cut toward RETIRE and are folded in above.

**Devil's advocate, frontier tier, against the RETIRE draft** (`W2-devils-advocate.md`): three
accounting corrections, all accepted and folded in — the 10% maintenance figure was one-sided (genuine
lane-machinery rows are 89 = 2.9%; maintenance commits 110 against 131 landed, half in the build-out),
"two rows a day" was the classifier's admit rate rather than repair's capacity (4/day at the pre-gate
offer rate, ~10/day with the denylist corrected and no scope widening — an option the draft never
priced), and quota headroom with a dark local lane was observed at the last resets (202–253 pp stranded,
09-05/06). Its verdict: 80 → 70, not below, because the lane fired nothing on those days either — the
stranding indicts the dispatcher, which follow-on 2 addresses without a VM. The packet carries
REPAIR-narrow as it recommended.

**Red team, frontier tier, hunting where RETIRE fails** (`W2-red-team.md`): one HIGH-severity,
unmitigated failure the draft did not name — the already-declared gate strands six open rows if the
retire pass stops before the declarations are settled — now the sequencing in §6; five lower ones
(cc-venue relabelling, the opt-in living in plist argv, the `live-cloud-worker` block needing the cloud
oracle, 133 open custody debts, `is-offbox` liveness consumers), each with its mitigation named there.
Two factual corrections applied: the rows the draft called "moot" were 31 blocked + 4 open, and the 4
open are work *held by* the lane, not work about it; "25 of 25" holds only with STALE-GATE rounds
excluded. No other repo depends on the lane (0 files, 0 `claude/*` heads on their remotes).

**Negative space, lead inline** — three dimensions not explored and why: (1) cloud VMs as hosts for
research *waves* (the `active ≤ 8` term refused 163 Agent-tool spawns in ten days) — not a redesign of
this lane, because a subagent's report must return to a lead's context on this box; a different product;
(2) the outcome value of the 55% code landings — asserted by zero reverts, not measured, because no
store records what a landed fix was later worth; (3) the operator's own preference for keeping a venue
they asked about — a value, not a measurement, and the reason the number is 70 and not 90.

---

## 8 · Decision

Conviction is **70% for RETIRE**, below the 90% bar at which this session would implement, and the
research is exhausted — every remaining uncertainty (§10) is either structurally unmeasurable from this
window or a value the operator holds. Filed as class-C decision packet **`663522aa67b1`** ("retire,
repair, or redesign the 24/7 cloud backlog lane"), conviction 70, receipt this memo, recommendation
`retire`, with three priced options: **retire** (the sequenced shutdown in §6 — settle 14
declarations, disable the relabel pass, plist migration, harvest, abandon custody, keep the store
read-only), **repair-narrow** (R1–R4 + trailer stripper + stale predicate + `paths=` fill + the
denylist correction, no scope widening; 4–10 landed rows/day at $5–6), and **redesign-split** (refuted
on cost and on the cheap-satisfaction failure mode; not recommended). `cc-decide list --open` shows
it; the operator rules with `cc-decide action 663522aa67b1 --evidence <ref>` or `cc-decide veto`.

Nothing in this memo was actuated: no cloud session fired, no row claimed, closed or unblocked, no
plist touched. The harvest in follow-on 1 is agent work under this repo's standing-land authorization
and is the one thing that should happen before the ruling, because the ten units are landable now and
decay at the rate §3.1 measures (69% at one day, 28% at seven).

### The three follow-ons that stand whatever the operator rules

1. **Harvest the ten landable units now** (§3.1 list, `B1-stranded-branches.md` §v): one branch of the
   seven for `1f6208064577`, plus `9f8a985115a9`, `8e67a1fa2d40`, `64c150ba2a8e`, `badb132df232`,
   `2a65b9bf722d`, and the one-file `model-config.yaml` diff on `9ce3c6350e2f` if the operator lifts its
   block. The trailer-stripper fix (§3.2, ~10 lines) is a prerequisite for the code branches; the docs
   branches land today. Cost: one desk session.
2. **Fix the local lane where it actually binds** (§4.3): the pane-anchor refusal (23% of fire attempts
   since 09-07), the wave planner's admitted-but-unplaced rows (158/day and rising), the router's
   `oracle-timeout` / `rank-data-unavailable` walls, and the test fixture writing `simulated keychain
   explosion` into the production accounts log. None of these is a cloud question; all of them are what
   "the box is capacity-bound" turned out to mean.

3. **Do not build an off-box gate; memoize the ratchets** (`D3-gate-split.md`). The lead's own
   hypothesis — move the land gate onto GitHub Actions, the one off-box resource that draws no Max
   quota — is refuted by the gate's composition. Over 217 single-round successful local lands since
   09-01: p50 total 722 s = 19 ratchet arms 312 s + statics 0 s + smoke 0 s + outside-gate 334 s (land-lock
   wait p50 284 s); 60% of lands run no smoke at all, and the arms are pure repo-text scans that must run
   on the rebased tree. No consumer of an off-box stamp exists, and a tree-sha key is structurally dead
   (0 of 428 gated trees overlap any stamped tree, because ship-land attests after the rebase while the
   producer judges `main`'s tip). The hermetic partition is 93.7% of suites by count but 68% by measured
   runtime, and the 32% it excludes contains the four priciest suites (`ship-land`, `postland-verify*`).
   The producer itself has 0 greens in 28 days; the 09-10 bash-3.2 fix has not yet been in any fold. The
   repo already priced the real lever at `gate-memo.sh:337-364`: per-suite blob-sha memoization inside
   each lint, 1 of ~15 lints done. If any VM half is ever built, aim it at `postland-verify.sh`
   (run p50 2,825 s, 9 greens of 70 stamps since 09-01), whose tree is on trunk — the one place a key
   lines up.

### Outcome of the three follow-ons — executed 2026-09-11, appended, nothing above rewritten

**Follow-on 1 — harvested in full, 7 landed shas, nothing skipped.** The trailer-stripper prereq
landed first (`e49308b92`): the cut is now the lines githooks/commit-msg itself NAMES (it greps with
`-n`), so position stopped being the property and all five shapes in §3.2 clear. Then `9465e0119`
(unit 1, router), `50e6bb075` (2), `1a5a79ae4` (3), `a702c9517` (4), `2d17544d7` (5), `36859c6e0`
(6). Unit 7 `9ce3c6350e2f` needed no judgment call after all — `land-content-verify` returns rc 0,
its content is already on trunk, so the operator's block is moot. Units 8-10 are disposable as §(v)
of `B1-stranded-branches.md` says, and that was checked rather than taken: a `probe=B2-VERIFY-BURST`
receipt `.txt` and two toy probes (`wordfreq.py`, `rangefmt.py`), absent from trunk by design.

⚠️ **Unit 6's blocker was true when measured and false two hours later, which is the reusable part.**
At the first pass `claude/fire-20260910T185102Z-27906-1` was held by a live `desk-land` (pid 79623,
running 3 h 32 m), so it was named-blocked rather than landed — landing over a live lander forks it.
Re-checked later the pid was gone, the worktree was still there, and the content was still off
trunk: the land had died without landing. Adopted and landed as `36859c6e0`. **Re-measure a blocker
before inheriting it** — a stranded lander and a working one look identical from the branch.

**Follow-on 2 — three of four landed; the fourth is blocked on the operator.**
- `5a983031a` — the 665 `unplaced` rows were a MISLABEL, not a placement bug: of 658 rows over 156
  passes, **0** had a free planner slot (417 were `WALL[unknown]`, 140 capacity re-plan surplus, 92
  placed-then-cut by `cc-dispatch MAX_SPAWN=2`, 9 `WALL[capped]`). Each row now carries its cause.
- `4d7a65d70` — `oracle-timeout` was NOT a bound that needed raising. 83/83 walls had a successful
  sweep ≤488 s old at call start (p50 238 s), inside `claude-accounts`' own 600 s `cache_grace_s`;
  the planner read with a 90 s TTL, re-swept at background QoS, and `timeout(1)` killed the sweep
  before `cache_write`. Fixed by passing `--max-age <SSOT cache_grace_s>`; the 20 s bound is
  unchanged. `rank-data-unavailable` was 5/6 fleet-wide concurrency-unmeasured, already cured by
  unit 1 — no planner change.
- `5fcb13211` — the `simulated keychain explosion` fixture leak. 🚨 **The FACT is confirmed and the
  TENSE is wrong, and §7 of `C3-local-refusals.md` should be read with this beside it.** 982 lines
  carrying that string do sit in `~/.claude/logs/claude-accounts.log`, but their last write is
  **2026-08-10T00:38Z — 32 days before this memo** — and the full 94-case core suite run against the
  pre-fix binary moved the real log by **0 lines**. So "a TEST fixture writing into the production
  accounts log", present tense, describes a residue, not a flow, and the 145 lost wave-plan passes
  belong to the two walls above. What WAS still live is structural and is what the commit fixes:
  `LOG_PATH` had no env override at all, so the six suites that redirect it by assigning
  `ca.LOG_PATH` fix every in-process case and **cannot reach a child** — `run "$CA_BIN" …`
  re-imports the module in a process where that assignment never happened.
- **Defect A, the pane-anchor refusal, is NOT fixed and is the one thing left.** Dispatched to its
  own session, which found a lead worth recording and then stalled on a permission prompt holding an
  uncommitted `scripts/handoff-fire.sh` change plus a new `tests/handoff-fire-split-bound.bats`.
  The lead: `d7b85c39c` landed **2026-09-07** — *"fix(it2-kitty): a missing `-s` was a silent rc 1,
  indistinguishable from an unreadable pane"* — the exact day rc=1 goes 0 → 5 → 35. If that holds,
  the alarm is firing CORRECTLY on a defect that pre-dates it and was previously silent, the cause
  is upstream in what id is passed to `it2 session split -s`, and reverting the alarm is the wrong
  answer. Filed for the operator as backlog `e04168383cd6`.

**Follow-on 3 — dispatched and in flight**, per-suite blob-sha memoization inside each ratchet lint,
`gate-memo.sh:337-364` as the pattern. No off-box gate was built; `D3-gate-split.md` stands.

---

## 9 · Receipts and reproduction

Reports (this campaign, landed beside this file under `docs/research/cloud-lane-redesign-2026-09-10/`):
`A1-reach-stratum.md` · `A2-reach-flow.md` · `A3-config-pricing.md` · `B1-stranded-branches.md` ·
`B2-refusal-autopsy.md` · `B3-return-arm-throughput.md` · `C1-quota-pool.md` ·
`C2-cost-per-landed-row.md` · `C3-local-refusals.md` · `D1-hostile-reviewer.md` · `D2-what-landed.md` ·
`D3-gate-split.md` · `W2-devils-advocate.md` · `W2-red-team.md` · `LEAD-notes.md`. The four inputs the
campaign was given, unchanged:
`~/.reso/research/cloud-lane-2026-09-10/{A-drain-rates,B-local-pipeline,C-cloud-pipeline,D-backlog-floor}.md`.

Commands behind the load-bearing numbers (all read-only):

```
bin/cc-eligible sweep --json                                   # 22 eligible of 296 non-done
bin/cc-backlog list --open --json | jq 'group_by(.status)|map({s:.[0].status,n:length})'   # 32 open · 4 claimed · 260 blocked
git ls-remote --heads origin 'claude/fire-*' | wc -l           # 430; 381 ahead of trunk by merge-base
git merge-tree --write-tree <trunk-at-push+Δ> <ref>            # per branch, 7 offsets — B1 §iv
git log origin/main --grep='Cloud-session:' --format=%H | wc -l # 131 re-authored VM commits on trunk
jq -R -c 'fromjson? // empty | select(.hook=="capacity-admit")' ~/.claude/autonomy/idl.jsonl | wc -l   # 755
cat ~/.claude/autonomy/cloud/*.refusal-route | jq -r .arm | sort | uniq -c                            # stale 630
python3 $S/work-C1/corr.py                                     # Fisher p = 6.5e-06 (script in C1)
```

## 10 · Limits

- The flow-reach figure (60%) is one reader's a/b verdicts on n=60; clustering on re-land rows makes
  the effective n ≈ 54. The stock figure is a census, not a sample.
- Cloud usage covers 44 of 692 sessions; 3 returned no usage object; whether `external_metadata.usage`
  includes VM-side subagents is unverifiable.
- The quota natural experiment is fitted on idle-account hours, which the router selects for; the
  vendor sentence, not the fit, is the primary evidence.
- Capacity history before 09-09 for `capacity_gate()` is destroyed by a 1,000-row trim; the headline
  rests on fire exit codes, which survive.
- "Landable" in §3.1 covers the merge step; rc 70 is live, so 20 is an upper bound on a latency-only
  repair.
- The maintenance figures are historical and include the lane's build-out; forward maintenance is
  not measurable from this window.
