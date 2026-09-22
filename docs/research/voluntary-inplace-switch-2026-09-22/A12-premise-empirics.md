# A12 — is the premise TRUE? Empirics for a voluntary in-place account switch

**VERDICT: PREMISE FAILS — but not on the ground A10 chose, and A10's cost half is refuted by two
orders of magnitude.**

Residence costs nothing (A10 is right about that, and the check it named returns 3.9%, not 0). The
premise fails on a fact neither side raised: **for 86.6% of the weekly quota this fleet stranded in
six weeks, there was no donor account to move work FROM** — every account was stranding at the same
time. Relocation is arithmetically incapable of capturing strand when the whole fleet is
demand-starved, and that is what this fleet mostly is. The entire relocation-addressable population
over six weeks is **66 bursts worth ~35.5 pp**, against **257–335 pp** stranded — and the perishable
account already had a **median of 5–6 live sessions sitting on it, 80.6–87.1% of the time**.

| the claim | verdict | the number |
|---|---|---|
| An idle session on a just-reset account costs something | **FAILS** | quota moves only with tokens; an idle pane emits none. Residency is not the scarce input — see §3 |
| A10's settling check ("idle at T-6h, then >50k tokens") is ~zero | **HOLDS, loosely** | 17 / 435 = **3.9%** (§2). Not zero, but every one of the 17 was *already on* the expiring account |
| A10 #2: the move "spends the perishable quota on nothing", cost scales with fill | **REFUTED** | a transplant costs **0.109 pp** median, **0.315 pp** at the largest transcript observed (§5) |
| Moving would have captured destroyed quota | **FAILS AT SCALE** | ceiling **≤45 pp of 335** (13.4%); observed **35.5 pp / 6 weeks** ≈ 1.5% of fleet weekly capacity (§4, §6) |
| A10 #4: "healthy and idle" is unobservable | **HOLDS, measured** | **46.9%** of post-idle bursts are woken by a signal bound to that session (task-notification / teammate / hook) — the "idle" session was waiting on its own children (§4) |
| A10 #5: no hysteresis ⇒ churn | **HOLDS, measured** | the most-perishable account changes every **6.5 h**; median dwell **1.3 h**; **44%** of leadership runs last < 1 h (§7) |

---

## §1 Instruments and coverage — state this before quoting any rate

| instrument | span | size | known defect |
|---|---|---|---|
| `~/.claude/logs/account-utilization.jsonl` | 2026-08-10T05:58 → 2026-09-22T16:36 | 33,102 rows, **0 unparseable** | 328 rows carry a NULL `weekly_reset_at` (next3 99 · next2 135 · next 22 · next4 72) and are dropped, not imputed |
| transcripts, 4 stores | **earliest event 2026-08-14T05:55:05** → 2026-09-22T16:41 | 8,896 files → 8,582 with ≥1 timestamped record → **2,341 parent sessions**, 1,184,817 events | `~/.claude-next/projects` is a **symlink to `~/.claude/projects`** — one store, not two. Nested `<project>/<sid>/**` files are subagent sidechains and are folded into their parent |
| token usage | same | 347,284 billing records after dedupe | **53.0% of raw usage records are repeats** (391,856 dropped on `message.id`). Undeduped sums are ~2.1× too high — the defect `bin/cc-quota-price` exists to hold |
| price list | re-derived 2026-09-22 | `cache_creation 0.336 pp/Mtok` · `input 878.196 pp/Mtok` · `output 0.000 (fitted)` · `cache_read ≤0.049 (bounded)` | R² 0.663, rel-RMSE 0.898, 62/99 buckets. **Blended** (opus-5 88%, fable-5.1 11%) |

**Coverage bound that governs everything below:** transcripts begin 2026-08-14, so the weekly window
ending 2026-08-11 has none, and windows ending 08-15/08-16 have < 48 h of session history preceding
them. 19 of 24 windows have a full 7-day transcript history. `cleanupPeriodDays: 365`
(`~/.claude/settings.json:1298`) is recent; it did not retroactively restore anything.

**Price-list calibration check, run because the `input` coefficient looks absurd on its face**
(1,139 input tokens = 1 pp): fleet totals over the corpus are cache_creation 2.347 G, input 1.741 M,
output 176.7 M, cache_read 81.19 G. The two-term model predicts **2,317 pp** against **2,065 pp**
actually consumed across 24 windows — **+12%**, acceptable. `cache_creation` alone predicts 789 pp,
**2.6× low**. So the `input` term is functioning as a per-request charge, not a per-token one; it is
kept, and every pp figure below is ±~12% at the fleet level and worse per-item.

```bash
bin/cc-quota-price                 # re-derive the price list (it changes; never re-quote it)
python3 scripts/desk-strand-replay.py | sed -n '1,30p'   # the repo's own reset/strand reader
```

## §2 (a) A10's own settling check — run

Definition used, deliberately generous to the proposal: a session on account A is *eligible* at
T−6 h if its last transcript event is ≥30 min before T−6 h (idle) and ≤24 h before it (so the pane
plausibly still exists); it *resumes* if it emits any event in (T−6 h, T]; it is *substantial* if it
moves >50 k **deduped new** tokens (input + cache_creation + output) in that window.

| acct | window end (UTC) | strand pp | k live @T−6h | idle-eligible | resumed | >50k new | new tokens |
|---|---|---:|---:|---:|---:|---:|---:|
| next2 | 2026-08-15T10:59 | 8 | 1 | 0 | 0 | 0 | 0 |
| next | 2026-08-16T03:59 | 9 | 2 | 1 | 1 | 1 | 1,681,515 |
| next4 | 2026-08-16T09:00 | 15 | 3 | 0 | 0 | 0 | 0 |
| next3 | 2026-08-18T12:00 | 2 | 5 | 3 | 3 | 2 | 2,211,350 |
| next2 | 2026-08-22T11:00 | 0 | 8 | 58 | 1 | 1 | 1,623,659 |
| next | 2026-08-23T04:00 | 1 | 1 | 1 | 1 | 1 | 678,796 |
| next4 | 2026-08-23T09:00 | 8 | 7 | 59 | 5 | 5 | 23,393,277 |
| next3 | 2026-08-25T12:00 | 6 | 6 | 48 | 0 | 0 | 0 |
| next2 | 2026-08-29T11:00 | 0 | 4 | 14 | 2 | 0 | 0 |
| next | 2026-08-30T03:59 | 0 | 1 | 3 | 0 | 0 | 0 |
| next3 | 2026-09-01T12:00 | 36 | 3 | 14 | 0 | 0 | 0 |
| next2 | 2026-09-05T10:59 | 51 | 9 | 35 | 4 | 3 | 3,402,276 |
| next | 2026-09-06T04:00 | 69 | – | 13 | 3 | 3 | 13,963,302 |
| next4 | 2026-09-06T08:59 | 79 | 6 | 9 | 0 | 0 | 0 |
| next3 | 2026-09-08T12:00 | 51 | – | 93 | 1 | 1 | 2,545,538 |
| next2 | 2026-09-12T10:59 | 0 | 1 | 10 | 0 | 0 | 0 |
| next | 2026-09-13T04:00 | 0 | 0 | 5 | 0 | 0 | 0 |
| next4 | 2026-09-13T08:59 | 0 | 3 | 19 | 0 | 0 | 0 |
| next3 | 2026-09-15T11:59 | 0 | 4 | 5 | 0 | 0 | 0 |
| next2 | 2026-09-19T11:00 | 0 | 0 | 0 | 0 | 0 | 0 |
| next | 2026-09-20T04:00 | 0 | – | 11 | 0 | 0 | 0 |
| next4 | 2026-09-20T09:00 | 0 | 1 | 16 | 0 | 0 | 0 |
| next3 | 2026-09-22T12:00 | 0 | 4 | 18 | 0 | 0 | 0 |
| | **TOTAL** | | | **435** | **21** | **17** | **49,499,713** |

**Answer to (a): 17 of 435 = 3.9%.** A10 predicted "near-zero ⇒ zero capture" and gets 3.9%, which
is small but is not the zero it asserted. **The finding that matters is the sign of the
correlation, and it is backwards for the proposal**: the four windows with the largest strand
(next3 36 pp, next2 51 pp, next 69 pp, next4 79 pp) produced **0, 3, 3 and 0** substantial
resumptions in their final six hours, while `next4`'s 8 pp window produced 5. Idle sessions do not
turn into work more often when quota is about to expire; the expiry is invisible to whatever
actually schedules the work (mostly a human).

Every one of the 17 was already **on** the expiring account. Relocating them would have moved that
work *off* the perishable account.

## §3 (b) Which account does resumed work land on — and is the perishable one empty?

Ranking accounts at each burst's resume instant by the router's own general-lane score
(`w_rem / T²`, `bin/claude-accounts:3509` `score_general`; auth-bad accounts excluded):

| rank of the burst's own account | bursts | share | new tokens | share |
|---|---:|---:|---:|---:|
| 1 (most perishable) | 567 | 39.4% | 396.7 M | 36.9% |
| 2 | 356 | 24.7% | 218.0 M | 20.3% |
| 3 | 269 | 18.7% | 287.2 M | 26.7% |
| 4 (freshest) | 248 | 17.2% | 174.5 M | 16.2% |

**60.6% of substantial post-idle work lands on an account that is not the most perishable.** That is
the proposal's strongest evidence, and it is real: the operator types into whichever pane is in
front of them, and pane ↔ account is arbitrary with respect to perishability.

**But the perishable account is not waiting empty.** Over the 438 h in which the most-perishable
*healthy* account was one that would go on to strand:

| state of that account | 10-min bins | share |
|---|---:|---:|
| occupied, ≥1 session working | 1,000 | 38.0% |
| **occupied, every session idle** | **1,120** | **42.6%** |
| no live session at all | 511 | 19.4% |

median live `k` on that account = **6**, mean 5.12.

`k` is derived from a `CLAUDE_CONFIG_DIR` env scan and counts children, so it can overcount.
**Cross-check with no `k` at all** — occupancy from transcript events straddling the instant:
working 45.5% · **live but idle 41.6%** · none 12.9%, median **5** live sessions. The cross-check
moves occupancy *up*, to 87.1%.

**So the mechanism the proposal proposes has already happened, continuously, by accident.** In
80.6–87.1% of the time that the perishable account is stranding, one or more sessions are already
resident on it, and 42% of the time every one of them is idle. Adding another idle body to a queue
of five idle bodies captures nothing. The scarce input is *work*, and moving a pane does not create
any.

## §4 (c) The counterfactual, and whether the work was genuinely continuation

What the first user record after each of 1,551 qualifying gaps actually was:

| what woke the session | bursts | share | new tokens | share |
|---|---:|---:|---:|---:|
| `<task-notification>` (its own background task finished) | 648 | 41.8% | 341.7 M | 30.4% |
| human: substantive new prompt | 387 | 25.0% | 364.4 M | 32.4% |
| human: short check-in (`(checking in)`, `(Re-connected to internet, continue)`) | 365 | 23.5% | 226.0 M | 20.1% |
| human: explicit continuation | 73 | 4.7% | 103.8 M | 9.2% |
| `isMeta` hook continue (`Continue from where you left off.`) | 43 | 2.8% | 81.0 M | 7.2% |
| `<teammate-message>` (shutdown_request / idle_notification) | 35 | 2.3% | 8.5 M | 0.8% |

**Two readings, both load-bearing:**

1. **Continuation dominates, which supports the proposal's context argument.** ~75% of bursts by
   count are a continuation of something the session already held — a background task it spawned, a
   lead's message addressed to it, an operator check-in on work in flight. A fresh session on
   another account cannot receive a `task-notification` addressed to a tool-use id in a dead
   process, cannot answer a `shutdown_request` sent to its `--agent-id`, and does not hold the
   frozen scope the check-in refers to. A10 #1's "it could simply have been started on the target
   account directly" is **false for ~75% of this population**.

2. **…and exactly that continuation disqualifies the session from the gate.** 46.9% of bursts (38.4%
   of tokens) are woken by a signal bound to the session — the session was **waiting on its own
   children**, not healthy-idle. This is A10 #4, and the rate is not marginal, it is half.

**The shipped verb does not deliver the context argument either.** A11 correctly identifies
`recycle_repick()` as already-landed, but `--recycle` is *EXIT + RELAUNCH* into a prompt-file brief
(`scripts/handoff-fire.sh:~185 "--recycle … EXIT + RELAUNCH — never /clear + queued payload"`) — a
**fresh context**. The only context-preserving in-place move is the transplant's RESUME MODE
(`--recycle --transplanted-source --resume-launcher F --resume-cfg DIR`,
`scripts/handoff-fire.sh:174, 9684-9689`), which relaunches the session's own uuid under the target
config dir. That rail is gated on a quota limit — `bin/cc-lr:178-205` refuses a non-LIMITED session
in as many words: *"These rails admit a QUOTA limit only."* So the proposal's value and the shipped
verb are not the same object: **A11's "already exists" is true of the account re-pick and false of
the context preservation.**

### The addressable population, as a funnel

Each stage is a condition a move would have to satisfy to be a *net* gain, not a transfer.

| stage | bursts | new tokens | pp (price list) |
|---|---:|---:|---:|
| all bursts (idle ≥30 min, then >50 k new tokens) | 1,440 | 1,076 M | 652.5 |
| idle gap ≥ 1 h (the cache is cold in place anyway — §5) | 1,202 | 803 M | 487.0 |
| woken by a HUMAN (not a signal bound to the session) | 613 | 467 M | 312.0 |
| its own account was **not** the most perishable | 358 | 268 M | 177.2 |
| the most-perishable account eventually **stranded** | 131 | 116 M | 63.3 |
| its own account ended that window at **100%** (so removing the work strands nothing there) | **66** | **71.3 M** | **35.5** |

That last condition is the one A10 #1 is really about and never states: **a move is a transfer, not
a gain, unless the source account was demand-saturated.** It is also *hindsight* — at decision time
you cannot know the source will reach 100%. 35.5 pp is therefore an **upper bound under perfect
foresight**, over six weeks: **~5.9 pp/week against a fleet capacity of 400 pp/week = 1.5%.**

The 66 survivors' first messages are, verbatim, ordinary operator asks typed into whatever pane was
in front of him — *"Provide URL(s) for visual sign-off"* · *"Check the AZ quote in ms365 email"* ·
*"It's Monday August 24th 2:15pm PST. Let's take action, concisely layout our todos."* ·
*"100% complete and good to close?"*. 43 of the 152 bursts meeting the quota conditions sat in
`~/Development/claude-infrastructure`, 18 in `~/Development/personal`, 15 in `sevenrooms-bridge`.
**This is an information problem wearing a relocation problem's clothes**: the operator does not
know which pane is on which account. Labelling the pane is a strictly cheaper remedy than moving
the session, and it is not in scope here — but it is the finding.

## §5 (d) What a move costs — A10 #2 is refuted

`cache_creation.ephemeral_1h_input_tokens` is what this fleet actually uses, so the prompt cache
TTL is **1 hour**, not 5 minutes. Measuring the FIRST assistant turn after a gap, over 6,806
gap-resumptions:

| gap before the turn | n | median cold-share `cc/(cc+cr)` | median cache_creation | median cache_read |
|---|---:|---:|---:|---:|
| 5 min – 1 h | 5,468 | **0.3%** | 918 | 297,334 |
| 1 – 6 h | 1,067 | **93.7%** | 323,476 | 21,965 |
| 6 – 24 h | 253 | **93.3%** | 276,043 | 21,965 |
| > 24 h | 18 | **94.7%** | 338,357 | 21,965 |

**For any session idle longer than 1 h, the cache-cold re-ingest A10 prices as the cost of the move
is already paid IN PLACE on the next turn.** The move's *incremental* cost is one extra full prefix
ingest — the one performed at move time, which a later resume would have performed anyway.

Prefix size at resume: p50 **315,631** · p90 **561,985** · p99 **752,206** · max **937,184** tokens.

| transcript size | cache_creation cost | pp at 0.336 pp/Mtok |
|---|---:|---:|
| median | 323,476 | **0.109 pp** |
| p99 | 752,206 | **0.253 pp** |
| largest observed | 937,184 | **0.315 pp** |

**At what size does the move cost more than it could capture?** Against the median capturable event
(0.54 pp of burst value among the 66 survivors) the break-even transcript is ~1.6 M tokens —
**above the 1 M context window**, i.e. unreachable. A10 #2's "cost scales with fill — worst for
exactly the sessions worth moving" is directionally true and **quantitatively wrong by ~2 orders of
magnitude**. The cost of a move is not the reason to refuse one.

Two caveats kept rather than buried: a `--resume` that never takes a turn may cost **zero** (no API
call until the first turn), so 0.109 pp is an upper bound; and the moved session lands on the
target's **5-hour** window, which this analysis does not price at all (§8).

## §6 (e) What fraction of strand is even attributable to idle sessions?

**Almost none — because for most stranded quota there was no donor account.**

This repo's own reader (`python3 scripts/desk-strand-replay.py`) sees 25 resets and **257 pp**
stranded; my independent window-segmentation sees 24 completed windows and **335 pp**. The
difference is the 2026-09-01 → 09-08 cycle, where the reader detects that the weekly meter **zeroed
mid-window** and correctly reports `>=` floors (next2 ≥73%, next ≥62%, next4 ≥47%, next3 ≥62%),
while a naive max-over-window reads 49/31/21/49. **Use 257 pp; my 335 pp over-reads that cycle.**
Either way that one cycle is 192–286 pp — **74.7–85.4% of all six weeks of strand** — and in it
**all four accounts stranded simultaneously**: zero account-hours at 100%, and **zero weekly-limit
refusals anywhere in the fleet between 09-01 and 09-08**.

Donor availability, measured as other-account hours at `weekly_pct ≥ 100` in each stranded window's
final 72 h:

| stranded window | strand pp | donor-hours (any other account walled) |
|---|---:|---:|
| next2 2026-08-15 | 8 | 0.0 |
| next 2026-08-16 | 9 | 0.0 |
| next4 2026-08-16 | 15 | 0.0 |
| next3 2026-08-18 | 2 | 0.0 |
| next 2026-08-23 | 1 | 2.7 |
| next4 2026-08-23 | 8 | 2.7 |
| next3 2026-08-25 | 6 | 0.0 |
| next3 2026-09-01 | 36 | 30.7 |
| next2 2026-09-05 | 51 | 0.0 |
| next 2026-09-06 | 69 | 0.0 |
| next4 2026-09-06 | 79 | 0.0 |
| next3 2026-09-08 | 51 | 0.0 |
| **no donor at all** | **290 (86.6%)** | |
| **some donor existed** | **45 (13.4%)** | |

**≤45 pp of 335 pp was ever relocation-addressable**, and the funnel in §4 independently lands at
**35.5 pp** — two instruments converging on the same order.

**The cause of the strand is demand, not distribution.** Deduped new tokens moved per weekly window:

| | mean new tokens in the window |
|---|---:|
| windows that reset at 100% (n=12 with full coverage) | **142.4 M** |
| windows that stranded (n=7 with full coverage) | **85.6 M** |

`corr(strand_pp, new_tokens_in_window) = −0.602` over n=19 fully-covered windows. A stranding week
is a week in which the fleet did ~40% less work — on **every** account at once. There is nothing to
relocate from.

**The other tail is the same story inverted.** 12 of 24 windows ended at exactly 100%, for **221.8
account-hours walled**, and transcripts carry **126 genuine weekly-limit API refusals**
(`"model":"<synthetic>"` records reading `You've hit your weekly limit · resets …`): 08-29 (3),
09-12 (68), 09-14 (4), 09-15 (1), 09-19 (36), 09-22 (14). On 09-12 and 09-19 **all four accounts
ended their windows at 100%** — so the refused work had no recipient either. This fleet oscillates
between *nobody is working* and *everybody is walled*; the middle state the proposal needs —
one account walled while another strands — is the 13.4% minority.

## §7 Adversarial pass — three checks I had not planned, all run

1. **Churn (A10 #5), settled.** Over 952 h at 10-min resolution the most-perishable healthy account
   changes **147 times = one every 6.5 h**. Median dwell on one leader **1.3 h**; **44% of
   leadership runs last under 1 h**; p10 is 0.00 h. A mover triggered on the live ranking would, 44%
   of the time, be chasing a target that stops being the target before the resume happens. A10 #5
   holds and needs hysteresis on the order of hours, not minutes.

2. **Is `k` inflating my occupancy claim?** It could — `k` counts every process carrying the account's
   `CLAUDE_CONFIG_DIR` (`bin/claude-accounts:560, 644-646`), children included. Re-ran §3 with `k`
   deleted entirely, using only transcript events straddling the instant: occupancy rose from 80.6%
   to **87.1%** and the median live count fell only from 6 to 5. The conclusion survives its own
   instrument being removed.

3. **Is the 2026-09-01→09-08 mega-strand real, or an instrument artifact?** Partly artifact: the
   shipped reader flags the meter zeroing mid-window and floors the four accounts at 47–73% used
   rather than the 21–49% the raw meter shows. I adopted the reader's numbers. That cycle also
   carries 22–36 h/window of `auth != ok`. **The verdict does not turn on it**: even taking the
   reader's lower strand, that cycle has zero donor-hours and zero limit refusals, so its
   relocation capture is 0 under either reading.

## §8 Residuals — what this data cannot reach

| question | status | instrument that would settle it |
|---|---|---|
| Would a transplant survive an in-flight background task? 41.8% of resumptions arrive as a `task-notification` naming a `tool_use_id` in the old process | **UNDECIDABLE** | a single deliberate transplant of a session holding a live `run_in_background` task, then read whether the notification is delivered. Nothing in the corpus is such a move |
| The 5-hour window cost of landing on the target | **UNDECIDABLE** | `session_pct` on the target at move time is in the util log, but there are **no historical voluntary moves** to join against. Needs a prospective arm |
| Would the refused work on a walled account actually have been *done* elsewhere, or merely deferred? | **UNDECIDABLE** | the 126 refusal records prove demand was refused; nothing records whether it was retried, re-routed or abandoned. A `cc-limited` disposition field, written at refusal |
| Does a moved pane *create* demand (operator sees it, uses it)? | **UNDECIDABLE** | only a randomized arm — A10 #7 is right to demand one |
| Ranking fidelity | **APPROXIMATE** | I reimplemented `w_rem/T²` and omitted `_soft`, `_cliff_factor` and `_excluded` (auth only). Re-run against `claude-accounts --rank general --json` sampled live to remove this |
| Windows before 2026-08-14 | **NO COVERAGE** | transcript retention. Nothing restores it |
| Per-item pp precision | **±12% at fleet scale, worse per item** | the price fit is R² 0.663 / rel-RMSE 0.898 on 62 buckets; `cc-quota-price --bucket-h` with more cycles |

## §9 Re-derivation

Every number above is reproducible from two stores and no cached artifact. The repo's own readers first:

```bash
bin/cc-quota-price                                   # §1 price list  (re-derive, never re-quote)
python3 scripts/desk-strand-replay.py                # §6 resets + strand, with the mid-window-zero floors
bin/claude-accounts --rank general --json            # §3 the live ranking this analysis approximates
```

The bespoke passes (write to `/tmp`, read nothing else):

```bash
# 1. index every transcript in all four stores -> one jsonl of (acct, parent-session, events, usage)
#    keep message.id: 53% of usage records are repeats and must be deduped on it.
#    ~8,900 files / 2.16 M lines / ~85 s.
python3 - <<'PY' > /tmp/idx.jsonl
import json,glob,os,datetime as dt
ST={"next":"~/.claude","next2":"~/.claude-secondary","next3":"~/.claude-tertiary","next4":"~/.claude-quaternary"}
for a,r in ST.items():
    root=os.path.expanduser(r)+"/projects"
    for p in glob.glob(root+"/**/*.jsonl",recursive=True):
        ev=[];tok=[];sid=None
        for line in open(p,errors="replace"):
            if '"timestamp"' not in line: continue
            try: x=json.loads(line)
            except Exception: continue
            ts=x.get("timestamp");
            if not ts: continue
            e=int(dt.datetime.fromisoformat(ts.replace("Z","+00:00")).timestamp())
            sid=sid or x.get("sessionId"); t=x.get("type")
            if t=="assistant":
                u=(x.get("message") or {}).get("usage") or {}
                ev.append([e,"a"]); tok.append([e,u.get("input_tokens",0),u.get("cache_creation_input_tokens",0),
                    u.get("cache_read_input_tokens",0),u.get("output_tokens",0),(x.get("message") or {}).get("id","")])
            elif t in("user","system"): ev.append([e,"m" if x.get("isMeta") else t[0]])
        if not ev: continue
        rel=os.path.relpath(p,root).split(os.sep)
        print(json.dumps(dict(acct=a,path=p,depth=len(rel),parent=rel[1] if len(rel)>2 else (sid or rel[-1][:-6]),
              sid=sid,ev=sorted(ev),tok=sorted(tok))))
PY

# 2. weekly windows + strand, from the utilization log, segmenting on weekly_reset_at (1 h tolerance).
#    A genuine rollover moves that stamp ~7 d; it also JITTERS sub-second, so never compare by equality.
python3 - <<'PY'
import json,collections,datetime as dt
E=lambda s: dt.datetime.fromisoformat(s).timestamp()
R=collections.defaultdict(list)
for l in open(dt.os.path.expanduser("~/.claude/logs/account-utilization.jsonl")):
    r=json.loads(l)
    if r.get("weekly_reset_at"): R[r["acct"]].append(r)
for a,rs in R.items():
    rs.sort(key=lambda r:r["ts"]); cur=None
    for r in rs:
        res=E(r["weekly_reset_at"])
        if cur is None or abs(res-cur[0])>3600:
            if cur: print(f"{a:6} {dt.datetime.utcfromtimestamp(cur[0]).isoformat()[:16]} n={cur[1]:5} max%={cur[2]:3} strand={100-cur[2]}")
            cur=[res,0,0]
        cur[1]+=1; cur[2]=max(cur[2],r["weekly_pct"])
PY

# 3. genuine weekly-limit API refusals (NOT prose about weekly limits — the fleet's own docs
#    match that phrase ~12k times). The error is a synthetic-model assistant record.
rg --no-filename -g '*.jsonl' '"model":"<synthetic>".*hit your weekly limit' \
   ~/.claude/projects ~/.claude-secondary/projects ~/.claude-tertiary/projects ~/.claude-quaternary/projects \
 | rg -o '"timestamp":"[0-9-]{10}' | sort | uniq -c
```

§2 / §3 / §4 / §5 / §6 / §7 each take `/tmp/idx.jsonl` plus the utilization log; the passes are
described precisely enough above to rebuild (idle threshold 30 min · dormancy cut-off 24 h · burst =
activity between gaps ≥30 min · substantial = >50 k deduped `input+cache_creation+output` ·
ranking = `(100−weekly_pct)/hours_to_reset²` over auth-ok accounts).

---

## What this means for the proposal, stated once

The move is **cheap** (0.1–0.3 pp), the mechanics are **sound** (A11 is right that the rails exist),
and the continuation value is **real** (~75% of post-idle work is continuation a fresh session
cannot reproduce — A10 #1 is wrong there). What it lacks is a **market**: for 86.6% of stranded
quota there was no saturated account to move work from, the perishable account already holds a
median of five live sessions 87% of the time, and the whole six-week addressable population is 66
events worth ~35.5 pp under perfect foresight — **1.5% of fleet weekly capacity**, against a churn
rate that flips the target inside an hour 44% of the time.

The one finding worth carrying forward is not a mover at all: **60.6% of substantial post-idle work
lands on a non-perishable account because the operator types into whichever pane is in front of him
and cannot see which account that pane is on.** That is addressable by labelling, not by moving.
