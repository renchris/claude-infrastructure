---
status: closed
---

# What the fire/handoff/recycle ledger can and cannot answer, and what was instrumented

**2026-08-09.** The census the `/goal` regression earned. Everything below is measured against the
live `~/.claude/logs/handoffs.jsonl` (1012 rows, window `2026-08-07T12:43:01Z → 2026-08-09T05:35:58Z`
= **40.9 h**) and the tree at `feat/fire-telemetry-actionability`. Where a doc's claim and the live
ledger disagree, **the ledger wins and the disagreement is stated**.

---

## The answer, in three lines

1. **Of 17 questions this path has actually been asked, 4 are answerable from the ledger today.**
   Seven are PARTIAL — the query runs but over a population that answers a different question — and
   six were answered by building a store, sweeping a corpus by hand, or getting it wrong twice.
2. **The dominant failure is never a missing guard. It is a producer that emits on one branch and
   nothing on the other**, so the ledger holds a numerator and no denominator. `--goal` had it.
   `--recycle` had it. The capacity gate had it until 2026-07-31, and still has it in a subtler form.
3. **Four instruments landed** (§4). Each closes a gap where a real question was asked and could not
   be answered cheaply; nothing here builds a dashboard.

---

## 1 · Structural facts that decide most of the verdicts

### 1.1 Five emitters, three points in a fire's life

| emitter | when it runs | `class` written |
|---|---|---|
| `emit_gate_admit` → `emit_fire_event` | **pre-fire**, inside `capacity_gate()` | `admitted` |
| `emit_fire_refusal` → `emit_fire_event` | **pre-fire**, at each gate's refusal branch | `refused` |
| `emit_recycle_event` | inside the detached `__recycle` watcher | `recycle-engaged` · `recycle-dead` · `recycle-unverified` |
| `emit_goal_event` | after engagement, inside `arm_goal` | `goal-arm` |
| `emit_handoff_telemetry` | **post-spawn**, once per fire | `handoff` · `self-retire-peer` · `trim` |

### 1.2 The per-fire row's real denominator is "a non-dry, non-recycle fire"

`emit_handoff_telemetry` is reached only inside `if [ "$ENGAGE_VERIFY" = 1 ]` — verified — but
`ENGAGE_VERIFY` is not the binding constraint: it is set for **every** `RECYCLE=0 && DRY=0`
invocation, and the whole spawn+telemetry block sits in the `else` arm of a three-way top-level
branch (`DRY` / `RECYCLE` / everything else).

| fire mode | per-fire row? | any ledger row at all? |
|---|---|---|
| ordinary fire (self-retire default, or `--no-self-retire`) | **YES** | admit + per-fire row |
| `--dry-run` | no — correct, nothing fired | no |
| `--recycle` | **NO** | **before this change: only 2 of ≥6 failure branches**; the capacity gate is skipped entirely, so not even an admit row |
| `self-close` subcommand | **NO** | none here — it writes `~/.claude/logs/close-attrib.jsonl` (165 rows) and `cc-fired/<pane>.json.closedAt` |

Measured: `self-retire-peer` = 136 (97.8% of per-fire rows), `handoff` = 3, `recycle-*` = **0**.

### 1.3 There is no join key between a gate row and its fire

`capacity_gate()` runs before `FIRING_SID` and `CHOSEN` are assigned. By construction:

```
$ jq -r 'select(.class=="admitted")|.basis' handoffs.jsonl | sort | uniq -c
 453 gate-off
 180 measured
# firing_sid null in 633/633 admits; account null in 633/633; capacity refusals 125/125 both-null
```

Every question of the form *"of the fires that were admitted, how many …"* is therefore
**structurally unanswerable**, not merely uninstrumented. Left as-is: moving the gate below the
account choice would change admission semantics, which is row 13's surface, not this scope's.

### 1.4 ⚠ 45% of the refusal population is the test suite, writing into the operator's live ledger

Suites that do not `export HOME` write to the real file. Measured:

```
$ jq -rs '[.[]|select(.class=="refused")]|length as $n
   | [.[]|select(.class=="refused")|select((.detail//"")|test("bats-run|fake:|> 20$|payload 31 chars|malformed back-channel"))]
   | "\(length)/\($n)"' handoffs.jsonl
107/237
```

- 42 `payload-backchannel`, 35 of them with `firing_sid:"fake:DEADBEEF-…"`
- 27 `payload-slash-head`, all `"first line is the slash command /goal (payload 31 chars)"`
- 27 `payload-goal-line`, all `"/goal condition is 30 chars > 20"` — the `GOAL_MAX_CHARS=20` fixture
- 11 `payload-empty`, **11/11** carrying a `bats-run-…` path

**Zero payload-gate refusals in the entire live ledger come from a real fire** — independently
corroborating `goal-in-handoff-2026-08-08.md` §1.1's *"every one is a bats fixture"*, and extending
it from `payload-slash-head` to all 109. On the admit side, `basis:"gate-off"` = 453/633 (71.6%), a
basis only `CC_FIRE_CAPACITY_GATE=off` produces — set by 88 test files and by **no** production
caller.

**The cost, in the exact metric the admit side was built for.** The published ratio query reads:

```
{"admit":632,"refuse":117}          → 84.4% admit
```

Restricted to production-bearing rows (`basis=="measured"` vs capacity refusals): **180/(180+125) =
59.0%**. A **25-point error**, in the metric `MACHINE_CAPACITY_V2` §9.5 already got wrong once (a
"permanent dispatch outage" projected from 13 samples, retracted) and whose *retraction's own
corroboration* had to be retracted too (§9.5.1). Nothing on a row said which population it belonged
to. → **instrumented, §4.2.**

### 1.5 Retention is class-blind, and the window is 1.7 days

Trim: `wc -l > 1200 → tail -1000`, one shared budget across all classes.

| class | rows | rows/day | window under its own budget | actual (shared) |
|---|---|---|---|---|
| `admitted` | 632 | 371 | 2.7 d | **1.70 d** |
| `refused` | 237 | 139 | 7.2 d | **1.70 d** |
| `self-retire-peer` | 136 | 80 | 12.5 d | **1.70 d** |
| `goal-arm` | 4 | 2.4 | 417 d | **1.70 d** |

The per-fire class loses ~7× and `goal-arm` ~245× of their natural windows to admit/refuse volume.
On 2026-08-08 the admit class alone consumed **456 of the 1000-row budget in one day**, and 45% of
refusals are fixtures — so **one heavy test run can evict a day of production fire history**,
silently. This is precisely the "13 samples in one high-variance window" failure the bound was
doubled to fix; the test rows have since re-consumed the increase. `~/.claude/cc-fired/*.json`
retains ~3.3× more fires than the ledger does. → **instrumented, §4.4.**

### 1.6 Schema drift is already live in the window

11 rows written in one 13-minute span on 2026-08-08 carry **no `verdict`/`gate` key** — a mid-land
deployed-copy skew. The documented ratio predicate `select(.gate=="capacity")` silently drops 8 of
125 capacity refusals (6.4%). Noted, not fixed: it is a deploy-skew artefact, not a producer defect.

---

## 2 · The questions actually asked

Harvested from `git log --all -- scripts/handoff-fire.sh`, the in-file incident comments, and every
doc that cites `handoffs.jsonl`. Not a wishlist — each row has a citation.

| # | Question | Asked where |
|---|---|---|
| Q1 | Goal adoption — what fraction of fires carry a `/goal`? | operator, `GOAL_IN_HANDOFF_METHODOLOGY.md`; answered `goal-in-handoff-2026-08-08.md` §1.1 |
| Q2a | Capacity-gate admit/refuse ratio | `MACHINE_CAPACITY_V2` §9.5 / §9.5.1 |
| Q2b | …of the fires admitted, how many fired? | implied by every ratio claim |
| Q3 | Engagement rate (M-1) | `SESSION_LIFECYCLE_V2` §2 |
| Q4 | fire→engaged latency, p95 ≤ 60 s (M-2 / A2) | `SESSION_LIFECYCLE_V2` §2, §7 |
| Q5 | Firing-session attribution (M-3 / F10) | `SESSION_LIFECYCLE_V2` |
| Q6 | Firing-session RSS (M-4 / F11 / A10) | `SESSION_LIFECYCLE_V2` |
| Q7 | "Did this fire open a new window?" — the 174-window regression | `handoff-fire.sh` in-source; `iterm2-freeze-30-sessions-2026-07-30.md` |
| Q8 | Refusal breakdown — is the fleet blocked or just quiet? (F13) | `SESSION_LIFECYCLE_V2` |
| Q9 | Recycle survival — does an armed recycle succeed? | `ARMED_SUCCESSION_LIFECYCLE.md` §1 |
| Q10 | Did a fired peer actually retire? | `ARMED_SUCCESSION_LIFECYCLE.md` §8 |
| Q11 | Did the successor engage after a self-retire? | `SESSION_LIFECYCLE_V2` M-8/M-9 |
| Q12 | Per-account distribution of fires and refusals | implicit in every routing decision |
| Q13 | Is a newly-landed fire path ever exercised? | `terminal-config-30-sessions-decision-2026-07-30.md` |
| Q14 | Who spawned these eight panes? | `CONCURRENCY_PROGRAM.md` |
| Q15 | Did the `/goal` arming actually take? | `68b2e007` |
| Q16 | Was a fire's brief truncated / did it hit a payload gate? | F5 / `payload_pane_id_gate` |
| Q17 | What *time window* is any of the above over? | implied by every rate quoted from this file |

---

## 3 · Verdicts

**YES** = one jq query over the live ledger. **PARTIAL** = answerable for a proper subset, or the
field exists but is null at a measured rate. **NO** = the field or row-class does not exist.

| # | Verdict (before this change) | What was missing / what had to be done instead | Cost when it was asked |
|---|---|---|---|
| Q1 | **NO** | No denominator. The per-fire row had no goal field at all, and `emit_goal_event` is unreachable when `--goal` is absent. Numerator = 4 rows. | a full research session: 1,901 transcripts → 137 provably-fired sessions parsed by hand across five config dirs |
| Q2a | **PARTIAL** | Query runs; population is 71.6% test rows and nothing marks them (§1.4). | one retracted outage claim + a second retraction of its corroboration |
| Q2b | **NO** | No join key; `firing_sid`/`account` null in 633/633 admits (§1.3). | why the ratio cannot be sanity-checked against fire counts |
| Q3 | **YES** | `137/139 = 98.6%` engaged. Caveat: recycles were 0% of the denominator. | low — the ledger working |
| Q4 | **PARTIAL** | Ledger `n=137 p50=25 p95=89`; `cc-fired` `n=434 p50=34 p95=223`. **A2 (p95 ≤ 60 s) FAILS on both**, and the ledger is the *flattering* store because it retains 3.2× fewer fires. Two producers now disagree. | the metric had no producer at all until 2026-07-31 |
| Q5 | **PARTIAL** | Fixed for the per-fire row (`firing_sid` null 0/139); still 100% null on every gate row. Attribution exists exactly where a fire already succeeded. | M-3's 51.8% closed for one class only |
| Q6 | **NO — field exists, 139/139 null** | A10 ("no fabricated zeros") passes, but the question *"at what firing-session RSS"* has never once produced a value. The `watchdog/<sid>.pid` lookup is the unrepaired cause. | none yet — a shipped-inert field. **Filed, not fixed: no question has actually been asked of it.** |
| Q7 | **YES** | `surface` → `118 split-right · 9 window · 7 split-down · 3 bg-tab · 2 tab`; `anchor_intent` null 0/139. The 174-window regression's exact shape is now one line. | previously had to be *inferred from `firing_sid` being null* |
| Q8 | **PARTIAL** | Class works; population is 45% fixtures and 0/109 payload refusals are real (§1.4). | `goal-in-handoff` had to re-check every row's `detail` by hand to prove "the guard is not even being hit" |
| Q9 | **NO — categorically** | `recycle-*` = **0 rows in 1012**. A recycle skips the capacity gate, takes the `elif` arm so never reaches the per-fire row, and the only emitters were the two **failure** branches — the success path emitted nothing before `exit 0`. A pure failure sample with no denominator. | a hand census of TMPDIR watcher logs on a **self-deleting 2-day window** ⇒ "1 of 7 succeeded" |
| Q10 | **PARTIAL — and cheaper than reported** | No terminal class here, but `close-attrib.jsonl` records every self-close (`162 self-close`, verdicts `158 closed · 4 closed-rc67 · 3 STILL-PRESENT`) and joins to the fire row on pane id. Run this session: **120 of 138 engaged fires have a close row, 18 do not (13.0%)** — corroborating the 17.1% the `cc-fired` census reported. Caveat: pane ids are small integers the terminal recycles, so the join degrades over a long window. | the `cc-fired` census had a denominator biased *flatteringly* — `cc-reaper` deletes the record on clean reap, so "the most successful outcome erases its own evidence" |
| Q11 | **PARTIAL** | The fire-side answer is here (`engage_proof`: `113 marker · 24 registry:<uuid> · 2 null`); the close-side oracle writes to `cc-fired`, so a close that aborted on a false negative leaves no row. | 5 → 7 → 11 assignees stranded 4+ h |
| Q12 | **PARTIAL** | Works per-fire (`68 next3 · 34 next2 · 26 next4 · 8 next`); `account` null in 633/633 admits and 81% of refusals. *"Which account is being throttled?"* — the useful form — has no data. | not yet paid; the first question a routing decision asks |
| Q13 | **YES (as a negative)** | *"`handoffs.jsonl` is untouched since 21:39"* was legitimate evidence a landed fix had never executed. Works only because refusals are recorded. | the ledger preventing a false "the fix is holding" |
| Q14 | **NO — out of scope by construction** | *"can only count fires that go through handoff-fire's front door, and this storm went around it."* A new store was built: `pane-spawns.jsonl`, 369 rows, of which **11** are handoff-fire — i.e. this script is 3% of pane creation on the box. | an eight-pane spawn storm with an unidentifiable producer |
| Q15 | **PARTIAL** | Three verdicts, well-modelled, `emit_goal_event` correctly omits `engaged`. But n=4 is not a rate, and with no row when `--goal` is absent it measures the *paste*, never adoption (that is Q1). | none yet — one day old |
| Q16 | **PARTIAL → effectively NO for truncation** | Gate hits are recorded, but 109/109 are fixtures ⇒ production hit-rate is 0 measured events; and **brief truncation is recorded nowhere** — no payload size, char count, hash, or path on any row. | not yet paid. **Filed, not fixed: no question has been asked of it yet.** |
| Q17 | **PARTIAL — and self-deceiving** | Every class reports the same 1.70 d regardless of its own rate, and nothing in a row says which trim generation it survived (§1.5). | `MACHINE_CAPACITY_V2` §9.5's "13 samples in one high-variance window" is exactly this |

---

## 4 · What was instrumented, and why these four

Bound: **the gaps where a real question was asked and could not be answered cheaply.** Ledger rows
only. Q6 and Q16 are real gaps and are deliberately NOT instrumented — no question has yet been
asked of either, and a field added before its question is a field nobody validates.

### 4.1 `goal_requested` on every fire-outcome row — closes Q1

A JSON boolean, never absent, present on the jq-less fallback row too. `FIRE_GOAL` is known at parse
time, so a goal-less fire records a **measured false** — which is exactly the row the ledger lacked.
Plus a fifth goal verdict, **`unreachable`**, when a goal was requested and the fire died before
message 2, naming the branch at the source (`pane-parked` · `pane-wedged` · `never-engaged` ·
`recycle-dead` · `recycle-unverified`) so *could not ask* never collapses into *asked and got no*.

**No nudge on a goal-less fire, deliberately.** 139 fire rows vs 4 goal-arm rows means a warning
would fire on ~97% of fires, nearly all legitimate plain continuations — the same zero bits as an
alarm that never fires, and it trains everyone to read past the next real one. A *rate* can be
checked once, cheaply, and a rate falling 20%→3% is loud in a way 137 unremarkable fires were not.

### 4.2 `under_test` on every row — closes the population half of Q2a and Q8

True ⟺ a bats harness variable was present in the emitting process. It measures the **environment**,
not intent, and the read cannot fail, so `false` is a measurement rather than a default. One
predicate now splits the ledger:

```
jq -rs '[.[]|select(.gate=="capacity" and (.under_test|not))] | group_by(.verdict)
        | map({(.[0].verdict): length}) | add' ~/.claude/logs/handoffs.jsonl
```

Not fixed here: the suites that write to the operator's ledger in the first place. That is test
hygiene across several files, it cannot help retroactively, and marking makes the contamination
countable either way.

### 4.3 `recycle-engaged` + a tri-state `engaged` + `prev_sid` — closes Q9

A successful recycle now emits a row at all. `engaged` is `true` / `false` / **absent**, where absent
is the `recycle-unverified` branch — reached precisely *because* there was nothing to verify
against, so the previous emitter's hard-coded `engaged:false` was publishing a measured negative for
a question never asked, into the numerator of the M-1 engagement rate. `prev_sid` carries the
pre-recycle session id: the `__recycle` re-exec never reaches the `FIRING_SID` assignment, so
`firing_sid` is null there by construction, and a recycle's real identity is
(pane, predecessor → successor).

### 4.4 A `class:"trim"` row — closes Q17

The only data-destroying operation in the file was the only one that wrote nothing. It now records
how many rows of each class were dropped and how far back the survivors reach, written *after* the
`mv` so it survives the trim it describes. Not fixed by raising the bound (the next test day eats
that too) and not by trimming per class (that would have to pick winners); fixed by making the loss
legible, so a rate is quoted with its coverage instead of over an unstated window.

> `head -n "$n"`, never `head -n -1000`. BSD `head` refuses a negative count outright, and this file
> runs on Darwin — the GNU spelling reads correct and would have left the drop-census empty on every
> trim, forever, silently.

---

## 5 · Conflicts between the docs and the live ledger

| Doc claim | Live ledger | Verdict |
|---|---|---|
| `ARMED_SUCCESSION_LIFECYCLE:86` — "1082 rows in three classes" | 1012 rows in five classes | doc is stale (pre-`--goal`); its `grep -c recycle = 0` **still held** |
| `SESSION_LIFECYCLE_V2` M-1 — "139/141 = 98.6%" over 07-24→07-29 | 137/139 = 98.6% over 08-07→08-09 | ratio reproduces on a disjoint window; the population fully rotated out in 11 days |
| `SESSION_LIFECYCLE_V2` A2 — "fire→engaged ≤60 s p95" | ledger p95 = 89 s; `cc-fired` p95 = 223 s | **A2 FAILS on both stores**, and the ledger is the more flattering because it retains 3.2× fewer fires |
| `iterm2-freeze-…:148` — "only 1 record carries `surface:"window"`" | 9 in the current window | both true of their own windows — no rate stated from this file survives a week |
| `goal-in-handoff` §1.1 — "every `payload-slash-head` is a bats fixture" | 27/27 | **confirmed**, and extends to all 109 payload refusals |

---

## 6 · Open

- **Q6 `firing_rss_kb` is shipped-inert** — the field exists, 139/139 null, cause named
  (`watchdog/<sid>.pid` lookup). Not fixed: no question has been asked of it. Filed.
- **Q16 brief truncation is recorded nowhere** — no payload size/hash/path on any row. Filed.
- **Q2b has no join key** and the fix would move the capacity gate below account selection, changing
  admission semantics. Not this scope's.
- **A2 fails on both stores and they disagree by 2.5×.** That is a real finding about the fire path,
  not about its telemetry, and it now has two producers where it once had none.
- **The test suites still write into the operator's live ledger.** `under_test` makes it countable;
  it does not make it stop.
