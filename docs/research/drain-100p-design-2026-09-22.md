# The 100th-percentile local drain — derived from the system model, 2026-09-22

Frontier-tier derivation session (`fire-drain-100p`, pane 511, Fable 5.1). Evidence base:
`docs/research/backlog-drain-audit-2026-09-22/` (README + a1..a8), re-read against the live tree at
`772d005e4` and the live stores at 06:00–07:00Z. Where this document and the audit disagree, the
disagreement is stated and the command that decides it is given. No tracked file other than this one
was written; no `cc-backlog` mutating verb, no fire, no land.

**Method.** Each question was answered from the constraints first (§1), then the code was read to
confirm or refute the derivation. Every claim below carries a `file:line` or a command and its output.
Numbers re-measured this session are marked *(live)*; numbers taken from the audit are cited by file.

---

## 0. Verdict in one paragraph

The local drain is not a throughput problem and never was. It is three separate defects wearing one
name: **(i)** the lane's continuation lives inside the failure domain of the process that fails
(`scripts/drain-recycle-fire.sh:188,377`), so the lane dies silently on every dropped link and stayed
dead 12.3 days; **(ii)** the lane selects `status=="open"` (`bin/cc-dispatch:1921`, `scripts/drain-pick.sh`
header) against a store that is 97% `blocked`, so a perfect lane has 0–2 rows to work — *(live)*
`drain-pick.sh --project all` read `eligible=0` at 06:54Z; and **(iii)** every instrument that should
have said so encodes "I could not judge" on the same channel as "healthy" (§5). The right pipeline is a
**level-triggered supervisor over a durable lane lease** (§3), optimizing **trunk-verified delivery on
the addressable stratum subject to a bounded staleness on the operator's stratum** (§4), with the one
highest-ratio change being to **make the lane's unit of work on a blocked row its PREMISE, not its
WORK** — attach a machine-checkable falsifier through the door that already refuses a lying one, and
let the sweep that already runs every tick retire what has decayed (§7).

---

## 1. The system model — eight constraints, each with its receipt

| # | constraint | receipt |
|---|---|---|
| C1 | A worker is a Claude Code session. It has finite context and **dies without a last act**: the harness auto-clears `/goal` on the context wall and on auth death; 434 of 641 goals were never evaluated once, 238 retired inside a tool call. | `~/.claude/CLAUDE.md` § "The measured goal lifecycle"; `docs/plans/CONTEXT_ECONOMY_V2.md` (7 sessions dead-in-place, 0 rescued) |
| C2 | The chain's successor fire is the **LAST clause of the worker's own goal** and is a `--recycle` (same pane). Any fire from a context that is not the dying pane must be the net-new `--first` shape. | `scripts/drain-recycle-fire.sh:188` ("…recycle #N+1 is FIRED … as the LAST action"); `:373-377` (`--first` ⇒ `--cwd`/`--worktree`; else `--recycle`) |
| C3 | `--recycle` is **exempt** from the capacity gate; a net-new fire runs `capacity_gate()`, which is **unbounded**, at a box that sits at 2.3–2.7 load/core against a 2.0 ceiling. | `scripts/handoff-fire.sh:8934-8935` (`if [ "$RECYCLE" = 0 ]; then capacity_gate \|\| exit 9`); `scripts/lib/capacity-admit.sh:13-37` (why `capacity_gate()` is refuted as a universal term; the bounded alternative); a1 §2.9 (load 23.12/26.69/26.06 on 10 cores) |
| C4 | launchd delivers ~⅓ of requested ticks and never overlaps an instance; the sweep must finish under the reaper's 600 s orphan floor. | a5 §4 (discovery 0.31/h of 1.0; dispatcher 4.02/h of 12); `scripts/autonomy-sweep.sh:363-366,442` |
| C5 | **The lane's state is already durable on disk.** N is the newest `fire-drain-<lane>-recycle<N>.txt`; the lease is a non-cloud claim in `backlog.jsonl` younger than `CC_BACKLOG_STALE_CLAIM_S`; the goal condition is a pure function of (N, since, min, lane, project). | `scripts/drain-chain-assert.sh:237-239` (brief glob), `:395-420` (lease disjunct); `scripts/drain-recycle-fire.sh:188` (`goal_condition()` takes only those five) |
| C6 | **The level is already computed every tick.** `drain-chain-assert.sh --json` returns `verdict dead\|alive` with a `why`, called from the sweep; its rc is journalled and **read by nothing that acts**. | `scripts/autonomy-sweep.sh:543-544` (`_bounded bash "$_drain" --file >/dev/null 2>&1; _drain_rc=$?`); `grep -rln drain_chain_rc tests/ hooks/ bin/ scripts/ docs/plans` → only `tests/autonomy-sweep.bats`, `tests/drain-chain-assert.bats`, the plan |
| C7 | The per-row reconciler exists and works, but pays the admission tail per row and its worker never takes a second row: 1.5 rows/session against the chain's 5.5. | `bin/cc-dispatch:84-85` (admission tail 414–833 s); a8 §4 C6 |
| C8 | The store has **two owners**: `open` is the agent's, `blocked` is the operator's by construction (`needs` files a row born blocked and skips `dispatch_kick`); 222 of 340 blocked rows are `source:needs`. | `bin/cc-backlog:3652-3830` (`cmd_needs` → `add` then `block --needs`); *(live)* `jq -r '.[]\|.source' /tmp/drain100p-blocked.json \| sort \| uniq -c` → `222 needs · 30 (empty) · 7 plan-open …` |

Two facts that changed between the audit's 06:07Z probe and this session's reads, recorded because
they show how fast this subject rots:

- *(live)* **The chain was restarted by hand at 06:51:37Z**, 12.3 days after it died. `stat -f '%Sm'
  ~/.claude/autonomy/fire-drain-infra-recycle333.txt` → `2026-09-22T01:51:37-0500`; the lane worktree
  committed `322783863 2026-09-22T01:53:32-05:00 docs(drain): recycle #333 — closed 2 rows`; and
  `drain-chain-assert.sh --json` now reads `{"verdict":"alive","why":"handover-grace","brief_age_s":190,
  "live_leases":0}`. The restart was a session's act, not a supervisor's — which is §3's whole point.
- *(live)* `drain-pick.sh --project all --top 10` → `eligible=0 shown=0 thrash_held=1` (the audit's one
  eligible re-land row `52e837e8f22d` has since closed). The lane that was restarted has nothing to do
  and cannot meet its own `--min 3` floor.

---

## 2. Where the audit is wrong, or right for the wrong reason

An adversarial reading, because agreement is worth less.

1. **README attributes the 470 rc=1 refusals to "handoff-fire's load gate."** They are the **anchor
   probe**, not `capacity_gate()`: the capacity gate exits **9** (`handoff-fire.sh:8935`), and the IDL
   rows a1 §2.9 quotes verbatim read `anchor probe INCONCLUSIVE (rc=2) — iTerm2 may be busy`, `REFUSED:
   live windows exist but none is agent-owned (rc=4)`, `no pane anchor resolved`. Load is the *cause*
   (iTerm2 is slow to answer), but the *remedy* differs: shedding load does not mint an agent-owned
   window. Any supervisor that fires net-new panes inherits this exact refusal class (C3), so §3 routes
   its fire through the bounded admission library rather than the unbounded gate.
2. **`DRAIN_CIRCUIT_2026-09-01.md` §1.6 forbade a launchd supervisor because "the activation queue is
   11 deep with all 11 past 24 h — any fix that ships as a new activation will rot."** *(live)*
   `bash ~/.claude/hooks/activation-watch.sh --queue` → `1 pending-activation script(s) NOT run … FRESH
   (<24h, 1): 44-jev-batch-activate.sh`. The premise that shaped the no-supervisor decision is false
   today — and it was the wrong argument anyway, because no new activation is needed: the sweep is the
   tick and already computes the verdict (C6).
3. **The five dead instruments are presented as five findings.** They are one generator (§5), and the
   audit's own remedy shape — "fix the glob / fix the string compare / fix the floor" — would patch five
   instances and leave the class open. Evidence the class is larger than five: 60 of 209 scripts emit a
   `verdict=` token (`grep -ln 'verdict=' scripts/*.sh \| wc -l` → 60) and **no script reads them**;
   `ship-land.sh` and `postland-verify.sh` each carry a `cc-backlog add … >/dev/null 2>&1` filing arm
   beside 18 and 15 `exit 0` sites respectively.
4. **`backlog-ratchet` is "unreachably green because the drain's success drove its denominator below
   its floor."** Half right. The floor (`scripts/backlog-ratchet.sh:123`, `CC_RATCHET_MIN_N` = 20; `:385`
   `denominator < floor`) fired because the **denominator is defined to exclude the pile**: `bin/cc-premise:3365-3368`
   skips every row whose status is not `open|claimed` **and every `source=="needs"` row** — i.e. exactly
   the 65% of the pile that has no falsifier. The instrument did not go green because the drain
   succeeded; it went green because its population was drawn around the defect.
5. **a3 says "drain-to-zero = NEVER (+20.45/wk)"; a5 says "on the queue the dispatcher drains it has
   essentially already happened."** Both are true of different populations, and the brief's Q2 is the
   question neither answers: *which population should the objective name?* §4 answers it.
6. **The audit dates the chain's death to 09-09 and its detector's blindness to the done-latched
   condition.** Correct, and the latch is worth one more line: the row `02d53c4b4078` was closed
   **by its own falsifier** — *(live)* `jq 'select(.id=="02d53c4b4078")'` → `2026-09-04 done "falsifier
   passed rc=0 (silent): bash scripts/drain-chain-assert.sh --assert ; the chain is alive — I am recycle
   #301"`. The instrument's retirement path worked perfectly; its **re-arm** path does not exist
   (`bin/cc-backlog:2183`: "Everything above this line returns the id with rc 0 and writes NOTHING").
   That asymmetry — a condition that can retire itself but not re-arm itself — is a second instance of
   §5's generator sitting inside the first.

---

## 3. Q1 — the control topology

### 3.1 Derivation

A 24/7 lane needs three things: a **worker** that does the work, **state** that survives the worker,
and a **supervisor** that reads the state and re-creates the worker. The two failed designs each omit
one:

| design | worker | state | supervisor | how it dies |
|---|---|---|---|---|
| self-relaying chain (Lane B) | ✓ | ✓ on disk (C5) | **the worker itself**, at its last breath (C2) | any link that ends without its last act — C1 says that is the common case — ends the lane silently. Measured: link 332 → 333, 12.3 days dead, restarted by hand (§1). |
| bare launchd timer | ✓ | **none** | ✓ | fires a fresh worker every tick regardless of a live one (duplicates), and cannot know N. |

The chain is **edge-triggered** (the continuation is an event the predecessor must emit); the timer is
**level-triggered** but stateless. The correct shape is level-triggered **over durable state**:

> **A reconciler that, on every tick, reads the lane's level from the store and acts only on the
> DEAD level; a worker that carries no liveness duty; a lease that makes a second fire impossible while
> a first is alive.**

That is not a new idea — it is the Kubernetes-controller shape, and it is what `cc-dispatch` already
is for the per-row unit (C7). What is missing is the same shape one level up, over the **lane**.

### 3.2 The concrete design — nothing new is built, one binding is added

**Sensor (exists):** `scripts/drain-chain-assert.sh --json`, every sweep tick
(`scripts/autonomy-sweep.sh:543-544`). Its four-arm predicate is the right one and is already argued
in `docs/plans/BACKLOG_DRAIN_24_7.md` §6 (`drained ∨ handover-grace ∨ live-lease ∨ progressing`).

**Actuator (the missing binding):** in the sweep, immediately after the sensor:

```
verdict=dead ∧ why ∈ {no-brief-no-lease, stalled, unverifiable}
  ∧ drain-pick eligible ≥ CC_DRAIN_MIN_CLOSED          (else: nothing to do, journal `idle`)
  ∧ cc_capacity_admit drain-lane                         (bounded: after CC_ADMIT_BUDGET refusals ADMIT+PAGE)
  ∧ mkdir autonomy/drain-lane-<lane>.lock succeeds        (idempotency across overlapping ticks)
⇒ drain-recycle-fire.sh --num $((N_newest+1)) --first --lane L --project P --account auto
```

N is read from the newest brief (C5); the fire is the `--first` shape because there is no pane to
recycle (C2); admission goes through `scripts/lib/capacity-admit.sh` rather than `capacity_gate()`
because a supervisor on a recovery path may be *delayed* by load and must never be *permanently
refused* by it (`capacity-admit.sh:31-37`: "a refusal here is bounded by construction"). The lock is
released by the fired worker's first turn (the same `engaged` event `handoff-fire` already journals)
and by a TTL equal to the handover grace.

**Worker (unchanged, minus one duty):** the goal condition keeps everything except the "fire N+1 as the
LAST action" clause. A worker MAY still fire its successor (the `--recycle` fast path is capacity-exempt
and cheaper), but the lane's survival no longer depends on it: if it does, the next tick sees a fresh
brief + live lease and does nothing; if it dies, the next tick fires. **Both paths converge on one
state**, which is the property neither failed design has.

### 3.3 Death detection and recovery bound

| phase | bound | source |
|---|---|---|
| worker wedges or dies | detected when the brief ages past `HANDOVER_GRACE` (900 s) with no lease and no transcript progress inside `PROGRESS_MAX_AGE` (3600 s) | `scripts/drain-chain-assert.sh:241-243` |
| sweep tick | requested 300 s, delivered ~900 s (C4) | a5 §4 |
| fire refused by load | bounded: `CC_ADMIT_BUDGET` (3) consecutive refusals ⇒ admit + page | `capacity-admit.sh:36-37,94` |
| **worst case, wedge → successor fired** | **≈ 1 h + 3 ticks ≈ 1.75 h** | vs **12.3 days** measured |

**Supervisor self-death:** the supervisor is the sweep; the sweep's own liveness is a subject in §5's
verdict ledger, so a sweep that stops ticking pages by *absence of a fresh `drain-chain` verdict*, not by
its own report.

### 3.4 Why it reduces to neither failed design

- Not the chain: the continuation is **outside the worker's failure domain**. A link that dies mid-tool
  call (55% of retired goals, C1) costs at most one recovery bound, never the lane.
- Not the timer: the tick fires **only on the DEAD level** and reads N from the store; a live lease is a
  no-op by construction. The lock makes two overlapping ticks unable to double-fire.
- Not the dispatcher: the unit is the **lane**, not the row, so the admission tail (414–833 s) is paid
  once per link, not once per row, preserving the chain's 5.5 rows/session.

Residual, stated: a worker that is alive but doing nothing useful (the "self-referential" mode
`DRAIN_CIRCUIT_2026-09-01.md` §1.4 measured — 304 trunk commits for 30 closures, all on the pipeline's
own files) is invisible to a liveness supervisor. That is an *objective* failure, and §4's closure floor
(`closed_pre ≥ min`, already in the goal condition at `drain-recycle-fire.sh:188`) is the guard, not the
topology.

---

## 4. Q2 — the objective function

### 4.1 "Drain to zero" names an activity over the wrong population

The pile is `10 open · 340 blocked` (a3 §1; *(live)* `cc-backlog list --blocked --json | jq length` →
340). `cc-dispatch` and `drain-pick` select `open` only. So:

- Over `open`, drain-to-zero is **done**: 2 dispatchable rows at 06:07Z, 0 eligible at 06:54Z *(live)*.
- Over `blocked`, drain-to-zero is **not the lane's verb**: a `blocked` row is closed by the operator
  (`cc-do`) or by a falsifier (`bin/cc-premise:2914`), never by a worker.
- Over `live`, the number is dominated by a stratum the lane cannot touch, growing +45.75/wk (a3 §2.4),
  fed by the Session Close Protocol's own exhaust (`hooks/completion-assert.sh:1278`: "432 of 526 live
  backlog rows exist because a session wrote something down instead of finishing or dropping it").

A goal whose denominator the agent cannot move is a goal that never clears — the same shape
`docs/lessons/a-goal-condition-containing-an-operator-only-act-never-clears.md` records.

### 4.2 What the lane CAN move, and therefore what it should optimize

The store is a ledger of **intent**, and the receipts prove it is load-bearing: 1,576 landed commits
on `origin/main` cite a backlog id, median lag filed→commit 101 h (a8 §1 — rows *drive* commits). The
lane has exactly three levers:

1. **`open` → landed content** (delivery). Measurable: evidence sha is an ancestor of `origin/main`.
2. **`blocked` → adjudicated premise**: retire it if the premise decayed (35.4% of all `done` events
   are retractions, a3 §2.10), or make it cheap for the operator if it holds (a `run` command, a
   `--why-not-now` class, a falsifier). *(live)* coverage today: `run` 158/340, falsifier 31/340,
   class 35/340; **140 rows carry none of the three**; `lastTs` age p50 14.7 d, **183 rows > 14 d**.
3. **Nothing** on genuine decisions: *(live)* 65 of 340 `needs` texts contain "Your call / VALUE CALL /
   policy call / product call / whether". Those are the operator's, and the lane's only correct act is
   to leave them alone.

Therefore:

> **Objective:** maximize *trunk-verified delivery* per unit quota on the addressable stratum,
> **subject to** a bounded staleness on the operator's stratum: no blocked row goes more than T days
> without a machine re-check, and every blocked row carries either a falsifier or a run command.

The constraint clause is what converts "drain the operator's queue" — impossible — into "keep the
operator's queue *honest and cheap*" — the lane's job.

### 4.3 Acceptance criteria that make the answer checkable

| # | criterion | today *(live / audit)* | target | one command |
|---|---|---|---|---|
| A | delivered share of lane closures (evidence sha ∈ ancestors of `origin/main`), rolling 30 d | 31.2% local-drain vs 48.3% session (a8 §6) | ≥ 45% | a7 §9 `evid2.sh` (per-close ancestor test) |
| B | blocked rows with `lastTs` age > 14 d | **183 / 340** | 0 | `jq` over `cc-backlog list --blocked --json` (this session's one-liner in §9) |
| C | blocked rows carrying a falsifier **or** a `run` | 181 / 340 (53%) | ≥ 90% | same store, `(.falsifier//"")!="" or (.run//"")!=""` |
| D | retraction-only closure share, monthly | 0.1% Jul → 7.9% Aug → **12.3% Sep** (a8 §2.5) | non-rising | a8 §2.5 classifier |
| E | closure floor per link: `closed_pre ≥ min` over rows filed OLDER than the link's window | built | keep | `drain-recycle-fire.sh --closure-report` |

B and C are the operator-stratum constraint; A and D are the delivery objective; E is the guard against
the self-referential mode. **A row can be closed by retraction and still fail D** — that is the point:
retraction is honest but it is not the lane's product, and D keeps it from becoming one.

### 4.4 The projection under this objective

The operator closes 92% of what is handed over and still loses ground (a3 §2.8: last 4 weeks filed 528,
closed 488, net +40) — an operator throughput of ~120–130 rows/wk against a blocked inflow of ~144/wk
(20.64/d, a5 §1). If the ~35% that decay are retired by probe rather than by the operator, effective
inflow falls to ~94/wk and the stratum shrinks at ~−30/wk from 340: zero in roughly **11 weeks**, without
the operator reading one row more than today. That is the only drain-to-zero over the whole pile that
the arithmetic supports, and it is the falsifiable projection §7 stakes itself on.

---

## 5. Q3 — the generator behind five silent deaths, and the invariant

### 5.1 The five instances, re-read as one shape

| instrument | true state | what its consumer saw | the projection that lost the bit |
|---|---|---|---|
| `drain-chain-assert.sh --file` | dead for 12.3 d | `exit 0`, every tick, ~1,700 times | `:326-339`: `add … >/dev/null 2>&1 \|\| { …; exit 0; }; exit 0`. And the actuator it calls maps {row appended, done-latched no-op} → rc 0 (`bin/cc-backlog:2183`) |
| `cloud-lane-liveness.sh` | baseline unreachable | `UNKNOWN → exit 3` (`:330`), journalled as `fire_read_rc:"3"` by its **only** caller `scripts/cloud-return-lane.sh:161`; nothing escalates a streak | the third value exists on the channel and is dropped **one hop later** |
| `cc-quota-price` | 625 of 690 buckets dropped | `ABSTAIN` on every window | `:326` `if a["reset"] != b["reset"]: continue` — a permanent abstain carries as many bits as a permanent green (`alarm-polarity-and-attention-budget`) |
| `cc-discover` self-report | 4 real adds | `added 275` | `:101-104` `wc -l` on a store every producer writes — a count that cannot distinguish "mine" from "anyone's" |
| `backlog-ratchet` | coverage unmeasurable | green | `:385` `denominator < floor` ⇒ no high-water ⇒ `--assert` passes; population defined at `cc-premise:3365-3368` to exclude `needs` and non-open rows |

Every one is the same move: an instrument has **three** outcomes — RED, GREEN, CANNOT-SAY — and its
output channel has **two** (an exit code, a count, a boolean), so CANNOT-SAY is *mapped onto whichever
value does not page*. Where a third value survives (`exit 3`, `ABSTAIN`), the **consumer** performs the
same projection one hop later. The generator, stated precisely:

> **A detector's "no verdict" is representable only as one of its verdicts, and the consumer keys on
> the detector's output rather than on the state of the store the verdict should have reached.**

The repo already knows both halves separately — `alarm-must-key-on-the-store-not-the-sensor`,
`claimed-outcome-vs-checked-outcome` ("emit a parseable `verdict=` token"),
`null-result-must-not-use-the-error-channel`, `fail-safe-default-mimics-the-healthy-state` — and has
60 scripts emitting `verdict=` tokens with **no reader**. Knowing the rule per instrument is exactly
what "individually patched" looks like.

### 5.2 The invariant that makes the class unrepresentable

> **I. A detector may not RETURN a verdict; it may only RECORD one.** The record is
> `{subject, verdict ∈ {red, green, abstain}, ts, cadence_s, evidence}` written through one library into
> a durable per-subject store (the newest record per subject; never the rotating IDL — `idl.jsonl`
> retains 3.4 h, a7 §8.3).
>
> **II. Health is defined ONLY as: the newest record for subject S is younger than 2 × cadence_s AND
> says green.** Absent, stale, abstain, and red are all pages, from ONE reader that walks the registry
> of subjects. A detector that stops running, a detector that cannot judge, and a detector that judges
> red are three different messages and one alarm class.
>
> **III. An actuation on RED is itself a subject.** Filing a row, re-arming a condition, firing a
> worker — each records its own verdict, and the verdict is taken by **read-back**, never by rc: "after
> `add`, does a row for this condition fold to `open|blocked`?" A done-latched condition whose falsifier
> currently FAILS is the RED case of the filer, and the correct act is `reopen --force` (the state
> recurred), which `cc-backlog` already spells out in its own stderr at `:2170-2175` and no automated
> filer has ever issued.

Under I–III each of the five becomes impossible to write: `drain-chain-assert` cannot exit 0 on dead
because it does not exit — it records red, and a filing whose read-back finds no live row records a
second red; `cloud-lane-liveness`'s `exit 3` becomes an `abstain` record, and 6 days of abstain is a
page; `cc-quota-price`'s permanent abstain pages after N; `cc-discover`'s "added N" is not a verdict at
all — its subject is *ids returned by `add`*, per `docs/lessons/a-self-report-counting-a-shared-store-counts-every-writer.md`;
`backlog-ratchet` records `abstain` when the denominator is under its floor and the reader pages
instead of reading green.

**What it costs:** one library (~the size of `hooks/lib/session-writes.sh`), one registry file naming
subjects and cadences, one reader arm in the sweep. The 60 existing `verdict=` emitters are already
80% of the way there; the change is to make the *token* a *row* and to give the row a *reader*.

**The one thing the invariant does not cover, said aloud:** a detector whose *predicate* is wrong
(the pre-2026-08-18 "brief younger than 24 h ⇒ alive") records green honestly. Predicate validity is
a red-proof question (`docs/lessons/green-in-both-arms-is-an-equivalence-guard-not-a-red-proof.md`),
not a channel question, and no channel invariant reaches it.

---

## 6. Q4 — claim-then-spawn is the wrong order; the admission design

### 6.1 What the order is today, and what each refusal depends on

`bin/cc-dispatch` claims at `:2870-2871`, warms the worktree at `:3287`, fires at `:3429-3430`, and on a
non-zero fire rolls the claim back with `self_release "$id" spawn-fail` at `:3487`. The refusals that
produced 877 spawn failures (a1 §2.9, n = 877):

| rc | n | cause | depends on the **row**? | depends on the **box**? | deterministic? |
|---|---|---|---|---|---|
| 3 | 385 | payload pane-id lint convicts the brief (the brief embeds the row title verbatim) | **yes** | no | **yes** — same row, same verdict, 374 times in 7 d |
| 1 | 470 | anchor probe inconclusive / no agent-owned window / no anchor | no | **yes** | no — bursty, tracks load |
| 4 | 11 | back-channel lint | yes | no | yes |
| 11 | 1 | fire-cleanup | no | yes | no |

**None of the four depends on the row being leased.** The lease buys nothing that the fire needs and
costs a `claim`+`reopen` pair per attempt — 1,674 ledger records in one 125 h window (a5 §2.2), and
the S7 fairness key that would sink the loop is folded from an IDL that rotates every ~3.4 h
(`bin/cc-dispatch:1162-1166`; a7 §8.3), so 374 failures read as ~13 and the sink only *orders*, never
*excludes*. Meanwhile `drain-pick.sh:86-92` holds the same row at `claims ≥ 5` — two arbiters, one
store, opposite answers (a7 §8.2).

### 6.2 The admission design — reserve before lease, at the actuator

Three moves, in cost order:

**(1) Pass-level preflight, once.** Before any claim, the pass probes the box once: an anchor probe and
a bounded capacity read. Either failing ⇒ the pass admits **zero rows** and journals `pass-refused/<cause>`.
This removes the 470 + 11 + 1 row-independent refusals from the ledger entirely; they were never facts
about rows. Cost: one probe per pass instead of one per row — strictly cheaper.

**(2) Row-level preflight, before the claim.** Compose the brief, then run
`handoff-fire.sh --dry-run --prompt-file <brief>`. The dry run already exists and already runs the payload
gates **"in the SAME ORDER the real fire runs its gates"** in preview mode (`scripts/handoff-fire.sh:12695-12701`;
enforce arms at `:12751,12754`), executing nothing (`:321`). If it refuses, **do not claim**: record
`unfireable/<gate>` on the row in the ledger (a `note` event keyed on the id, not the IDL), and after
K = 3 consecutive `unfireable` verdicts the **actuator** — `cc-backlog claim` — refuses the row, exactly
as it already refuses on a passed falsifier (rc 3) and on `wasDone` (rc 4; `bin/cc-dispatch:1962`,
`:2917`). One arbiter, at the chokepoint (`make-the-actuator-the-arbiter`,
`enforcement-must-live-at-the-chokepoint`). The row is then blocked with class `not-yet-true` and
falsifier = the dry-run command, so it **self-unblocks the day its brief lints clean**.

**(3) Keep self-release, change what the arbiter reads.** `bin/cc-backlog:6449`'s exemption of
`selfRelease` from thrash pairs is correct and stays (it exists because reap rule B blocked 228 rows
on dispatcher rollbacks, `bin/cc-dispatch:1136-1139`). The defect was never the exemption; it was that
the *only* counter anyone read was `claims`. Under (2) the counter that gates admission is
`unfireable`, which a self-release does not touch.

### 6.3 What it costs, honestly

- **Latency:** one `--dry-run` per candidate per pass. `MAX_SPAWN` is 2 (`bin/cc-dispatch:279`), so at
  most two per pass. The payload gates are text lints (sub-second); the anchor probe — the expensive
  term — moves to once per pass under (1). Net: the admission tail (414–833 s) gets *shorter*, because
  a refused candidate no longer reaches `warm_worktree`. *Not measured this session* (a dry run was
  judged too close to a fire for a read-only brief); the bound is the gate cost, not a guess.
- **A TOCTOU residual:** preview passes, enforce fails (iTerm2 state changed in between). That is the
  ~1–2% class of genuine races, not the 82.8% class; it still self-releases as today.
- **One more blocked row per deterministically unfireable item.** `d6d7edef60a3` becomes a blocked row
  carrying its own falsifier — the correct state for "the gate refuses to dispatch the row that
  describes the gate" — instead of 96 claim/reopen pairs a day.
- **Two arbiters collapse to one.** `drain-pick.sh`'s `thrash_held` becomes a display of the actuator's
  verdict rather than an independent rule.

What moves: 805 wasted claims/wk → ~10; ledger growth −~1,600 records/wk of the 2,860 measured
(a5 §2.2: 341–408 rec/day). **Pipeline productivity in delivered rows: ≈ 0.** The 62 rows in the loop
were mostly closed by other closers (only 10 are open today). This is a *cost* fix. It is not §7.

---

## 7. Q5 — the ONE change

### 7.1 The candidates, priced on the same axis

"Productivity gained" = rows moved to a verified terminal state per week; "risk" = blast radius of a
wrong outcome plus landing risk in the rail it touches.

| change | moves | by how much | risk | ratio |
|---|---|---|---|---|
| supervisor over the lane (§3) | restores a lane that closed 397/30 d | **0 today** — `eligible=0` *(live)*; the lane has nothing to pick until §7.2 refills the queue | low–moderate (a runaway spawner if the lease predicate is wrong; bounded by lock + grace) | undefined now; necessary later |
| reserve-before-lease (§6) | −805 wasted claims/wk | delivery ≈ 0 | low | high on cost, ~0 on product |
| close-on-land in `ship-land.sh` | the "landed but row open" redo class | unknown; ≤ 70 of 166 fires re-claimed without disposition (a7 §2) | **moderate** — a bug in the land rail blocks the fleet; trailer misattribution closes the wrong row | medium |
| enforce the readiness gate (`CC_DISPATCH_READY_GATE=enforce`, `bin/cc-dispatch:1354`) | defers the 73% of admissions reading `ready:false` | fewer wasted fires; delivery unknown | could starve a 2-row queue to 0 | unknown |
| widen `dispatch-projects.conf` | +8 open rows addressable | ≤ 8 | firing workers into repos never dispatched (sevenrooms sidecar, device trust) | small |
| **falsifiers on the blocked stratum (below)** | **the 340-row operator pile** | **≈ 120 rows retire (35% × 340) in the first sweep cycle; operator inflow −35% thereafter** | **low**: reversible (`reopen`), and the door refuses a probe that already passes (rc 5) | **highest** |

### 7.2 The change: make the lane's unit of work on a blocked row its PREMISE

> When `drain-pick` returns `eligible=0` — the standing state — the lane's pick function falls through to
> **blocked rows lacking a falsifier** (*(live)* 309 of 340), and the unit of work on such a row is
> **adjudication**, not implementation: read the `needs` text, write the probe that would be true when
> the row is moot, attach it with `cc-backlog falsify <id> --probe "<cmd>"`, attach a `--run` where one
> exists, and touch nothing else. The sweep does the rest.

Why this is one mechanism and not a project — every part already exists and runs:

| part | where | state |
|---|---|---|
| the door | `bin/cc-backlog falsify <id> --probe` — runs the probe **before storing it** and **refuses one that exits 0 against a live row (rc 5)**; a second screen warns if it would also have passed on filing day | built (`bin/cc-backlog:65-79` header) |
| the drain | `bin/cc-premise sweep --record --limit 150 --close-falsified 25`, every sweep tick, iterating **`status != "done"`** — blocked rows included — with a shard cursor so 350 rows are covered across ticks | built and live (`scripts/autonomy-sweep.sh:1486-1490`; `bin/cc-premise:3056`, `:3007-3045`, `:2905-2925`) |
| the closer | `cc-backlog done <id> --evidence "falsifier passed: …"` from the sweep | built (`bin/cc-premise:2914`) |
| the worker | the drain session, idle at `eligible=0` | exists; restarted 06:51Z *(live)* |
| the missing 91% | falsifier coverage on blocked rows: **31 / 340** | **this is the whole change** |

The probes are not exotic. *(live)* Of the 159 blocked rows with neither falsifier nor run, 21 name a
pane, a `session_…` id, a worktree path, or a logged-out account — "pane N exists", "worktree path
exists", "`cc-cloud status <id>` is not landed", "`claude-accounts` reads next as logged-out" are each a
one-line probe. The 36 rows a8 §2.3 classes as pipeline self-debt are of exactly this shape. For the
65 genuine decisions the probe is honest too: "the decision packet `<id>` is still open" (`cc-decide`),
so a ruling retires the row without anyone remembering to.

**What it would move, with the arithmetic shown.** Store-wide, 35.4% of `done` events are premise
retractions (a3 §2.10, n = 3,633), and among rows that *have* a probe the sweep already retires them at
up to 25/tick. If blocked rows decay at the store-wide rate, ≈ 120 of 340 retire within one shard cycle
of attachment; criterion B (`lastTs > 14 d`) drops from 183 toward 0 because every probe run is a
re-check; criterion C rises from 53% to ~100%; and the operator's `cc-do` judgment pile — *(live)*
`cc-do — 2 runnable · 385 judgment` — loses the third that was never theirs to judge. Under §4.4's
projection the blocked stratum then shrinks at ~−30/wk instead of growing at +45/wk.

**Why the ratio is the highest.** It touches **no rail**: no edit to `cc-dispatch`, `handoff-fire`,
`ship-land`, or the sweep. Its only writes are `falsify` events (metadata) and sweep-driven `done`
events that carry the probe's own output as evidence and are reversible with `reopen`. Its worst
outcome — a probe that lies — is screened twice at the door and bounded by the existing
reopen-after-done rate (0.6%, a5 §6.2) as the alarm line.

### 7.3 The measurement that falsifies this recommendation

Run before committing the lane's time to it, on a sample, read-only except for the probes:

```
# 40 blocked rows lacking a falsifier, stratified: 25 source=needs, 10 empty-source, 5 add→block
# attach a probe to each via `cc-backlog falsify <id> --probe …` (each probe is RUN at attach; rc 5 = refused)
# then ONE sweep:
python3 bin/cc-premise sweep --json --record --close-falsified 40 | jq '.closed, .close_skipped'
```

**Refuted if:** fewer than **6 of 40 (15%)** retire — the decay hypothesis is wrong for the blocked
stratum and the change produces metadata, not movement. **Also refuted if**, over the following 30
days, `reopen`-after-falsifier-close exceeds **5%** of such closes — the probes are lying and the door's
two screens are not enough. Either number ends the recommendation; §6's reserve-before-lease becomes the
best remaining ratio, on cost rather than product.

---

## 8. What the current pipeline is structurally unable to do, however well it is tuned

Each row is a property of the design, not of a constant.

| # | cannot… | because | receipt |
|---|---|---|---|
| 1 | survive its own worker's death | the continuation is the worker's last act | `drain-recycle-fire.sh:188,377`; §3 |
| 2 | address 97% of the pile | selection is `status=="open"` | `bin/cc-dispatch:1921`; `drain-pick.sh` header "status=open only" |
| 3 | close a row when its fix lands | `ship-land.sh` never calls `done`; the close is prose in a brief | `grep -c 'cc-backlog done' scripts/ship-land.sh` → 0; `drain-brief.template.md:64` |
| 4 | refuse a row it cannot fire | the lease precedes every preflight; the only counter read is one that self-release does not increment | `bin/cc-dispatch:2870,3287,3430,3487`; `bin/cc-backlog:6449`; §6 |
| 5 | report its own death | the detector's dead arm exits 0 and files into a condition it cannot re-arm | `drain-chain-assert.sh:326-339`; `bin/cc-backlog:2183`; §5 |
| 6 | price itself | the quota converter abstains on every window | `bin/cc-quota-price:326`; a8 §3.1 |
| 7 | tell delivery from retraction | the status vocabulary has no `retracted`; both fold to `done` | `bin/cc-backlog:1598-1604`; a3 §2.9 |
| 8 | keep its own numbers honest | its self-reports count a shared store | `bin/cc-discover:101-104`; a5 §2.2 |

Rows 1, 4, 5 and 8 are cured by §3, §6, §5 and §5 respectively; row 2 by §7 (the lane addresses
premises, not just work); rows 3, 6 and 7 are named here and left as named — each needs its own
measurement before a design, and this brief asked for the pipeline's, not the ledger's.

---

## 9. Uncertainties, with numbers

| claim | conviction | what would move it |
|---|---|---|
| blocked rows decay at the store-wide 35% | **60%** — the rate is measured on rows that *had* probes, which were filed by machines with known oracles; hand-filed operator rows may decay slower | §7.3's 40-row sample |
| a supervisor-fired `--first` link clears admission often enough to matter | **75%** — the dispatcher fired 69 local sessions from the same launchd context in 11 days, so anchors do resolve; the bounded admission library is what turns "sometimes" into "within N ticks" | count `pass-refused/anchor` per day after §3 lands |
| the rc=1 class is the anchor probe, not the capacity gate | **95%** — the IDL text is verbatim and the capacity gate's exit is 9 | `jq 'select(.action=="failed")\|.detail' idl.jsonl \| grep -c 'rc=9'` |
| §5's invariant is implementable in one library without a new activation | **85%** — the sweep already hosts the sensor and the `backlog-health` row; the reader is one arm | the registry's first three subjects going red for a real reason |
| §7 outranks close-on-land | **70%** — close-on-land's magnitude is unmeasured (≤ 70 fires); if it is near 70 it is a real product gain at moderate risk | measure how many `done` rows' evidence sha was on trunk > 1 h before the `done` event |

---

## 10. Commands that produced this session's live numbers

All read-only. `CC_BACKLOG_KICK=off` on every `list`.

```bash
cd /Users/chrisren/Development/.worktrees/drain-100p        # HEAD 772d005e4
ls docs/research/backlog-drain-audit-2026-09-22/            # README + a1..a8

# the chain's shape and its restart
sed -n '186,190p;362,377p' scripts/drain-recycle-fire.sh
stat -f '%Sm %N' -t '%Y-%m-%dT%H:%M:%S%z' ~/.claude/autonomy/fire-drain-infra-recycle33{2,3}.txt
git -C ~/Development/.worktrees/drain/lane-infra log -1 --format='%h %cI %s'
bash scripts/drain-chain-assert.sh --json | jq -c '{verdict,why,live_rows,brief_age_s,live_leases,cloud_leases}'
bash scripts/drain-pick.sh --project all --top 10
ls ~/Library/LaunchAgents | grep -iE 'drain|dispatch|sweep|discover'; ls launchd/
bash ~/.claude/hooks/activation-watch.sh --queue

# the dead-instrument exit paths
sed -n '300,345p' scripts/drain-chain-assert.sh;  sed -n '228,250p' scripts/backlog-flow-assert.sh
sed -n '2135,2200p' bin/cc-backlog                                # done-latched add: rc 0, nothing appended
jq -c 'select(.id=="02d53c4b4078")|{ts,event,evidence:(.evidence//""|.[0:120])}' ~/.claude/autonomy/backlog.jsonl
sed -n '318,335p' bin/cc-quota-price; sed -n '99,105p' bin/cc-discover
grep -n 'CC_RATCHET_MIN_N\|denominator.*floor' scripts/backlog-ratchet.sh; sed -n '3355,3380p' bin/cc-premise
grep -n 'exit 3\|UNKNOWN' scripts/cloud-lane-liveness.sh | tail -3; grep -rn cloud-lane-liveness scripts/ | grep -v '^scripts/cloud-lane-liveness'
sed -n '540,560p' scripts/autonomy-sweep.sh; grep -rln drain_chain_rc tests/ hooks/ bin/ scripts/ docs/plans
grep -ln 'verdict=' scripts/*.sh | wc -l; ls scripts/*.sh | wc -l
grep -ln 'add .*>/dev/null 2>&1' scripts/*.sh | while read f; do echo "$f $(grep -c 'exit 0' "$f")"; done

# claim → warm → fire → self-release, and the preflight that exists
grep -n 'crc=\$?\|warm_worktree "\|self_release "\$id" spawn-fail' bin/cc-dispatch
sed -n '8930,8936p;12695,12702p;12745,12755p' scripts/handoff-fire.sh
sed -n '6435,6470p' bin/cc-backlog; sed -n '86,92p' scripts/drain-pick.sh
sed -n '1,40p' scripts/lib/capacity-admit.sh

# the premise drain reaches blocked rows
sed -n '3056,3060p;3007,3050p;2905,2925p' bin/cc-premise; sed -n '1486,1490p' scripts/autonomy-sweep.sh
sed -n '3652,3660p;3800,3830p' bin/cc-backlog                     # needs: --falsifier optional, coverage warn OFF

# the blocked stratum, live
CC_BACKLOG_KICK=off ~/.claude/bin/cc-backlog list --blocked --json > /tmp/drain100p-blocked.json
jq -r '[.[]|{f:((.falsifier//"")!=""),r:((.run//"")!=""),c:((.whyNotNow//"")!="")}]|group_by(.f,.r,.c)|map({falsifier:.[0].f,run:.[0].r,class:.[0].c,n:length})[]' /tmp/drain100p-blocked.json
jq -r '.[]|.source//"(empty)"' /tmp/drain100p-blocked.json | sort | uniq -c | sort -rn | head -4
jq -r '.[]|(.needs//.title//"")' /tmp/drain100p-blocked.json | grep -ciE 'Your call|VALUE CALL|policy call|product call|whether'   # 65
jq -r '.[]|select(((.falsifier//"")=="") and ((.run//"")==""))|(.needs//.title//"")' /tmp/drain100p-blocked.json \
  | grep -ciE 'pane [0-9]|session_[0-9a-zA-Z]|worktree|cloud session|permission (prompt|grant)|LOGGED OUT|logged out|re-?auth|relogin'  # 21 of 159
jq -r '.[]|.lastTs' /tmp/drain100p-blocked.json | python3 -c 'import sys,datetime as d;n=d.datetime.now(d.timezone.utc);a=sorted((n-d.datetime.fromisoformat(l.strip().replace("Z","+00:00"))).total_seconds()/86400 for l in sys.stdin if l.strip());print(len(a),a[len(a)//2],a[int(len(a)*.9)],sum(x>14 for x in a))'
bin/cc-do --list 2>/dev/null | head -4                             # "cc-do — 2 runnable · 385 judgment"
```
