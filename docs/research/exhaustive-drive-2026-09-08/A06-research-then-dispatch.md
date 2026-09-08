# A06 — Mechanizing research → conviction → dispatch

Wave: exhaustive-drive, 2026-09-08T21:45Z. Read-only. Every number below carries the command that
produced it and the population it counts. **measured** = I ran it. **inferred** = I did not.

---

## 1. THE ANSWER

**The conviction protocol that landed today gated the two doors nobody uses and left the door that
carries 65% of the traffic wide open.** `cc-backlog needs "<step>"` files a row **already blocked**,
requires no impossibility class, no conviction, no receipt and no options — and 143 of the 220 live
blocked rows came through it (measured). `wrap-ledger.sh`'s `UNCONVICTED_ROWS` keys on
`.whyNotNow | startswith("needs-human")`; **219 of 220 blocked rows carry no `whyNotNow` at all**
(measured), so the new gate is structurally unreachable over 99.5% of the population it was built
for. Sixteen of those rows are hand-verified decisions with no runnable command, median age ~21
days, and eight of the sixteen are questions a research session could settle.

**Second finding, and it inverts the brief's premise.** The parked pile is not *unresearched*. 37 of
220 blocked rows carry a `RE-VERIFIED` / `RE-MEASURED` / `PREMISE CORRECTED` stamp (measured); the
house already runs `cc-premise` re-validation at claim time. What is missing is not research — it is
the **edge from a researched row back to a dispatchable one**. `cc-dispatch`'s fire predicate is
`status=="open"` and nothing else (bin/cc-dispatch:1853-1859, measured); a blocked row is invisible
to every automated lane forever. Rows are re-measured monthly and re-parked monthly.

**Third: capacity is measurably not the constraint.** 903 fires were admitted in the 17 h to
21:45Z today; 46 were refused and **zero** of the refusals were capacity (43 `payload`, 3
`subagents`) — measured from `~/.claude/logs/handoffs.jsonl`. Researching every one of the 96
candidate rows at one dispatched session each costs ≈84 pp of weekly quota against the ~167 pp
(≈1.7 account-weeks) this fleet measured itself **stranding** in a single cycle on 2026-09-05.

**Fourth: the Workflow tool is available and is not the blocker.** Its enablement predicate in
2.1.260 carries no session-kind term, and 248 of the 251 transcripts since 2026-09-01 that record
their tool set were offered it (98.8%, measured). 21 sessions invoked it (48 invocations); 4 of the
21 ran inside `~/Development/.worktrees/wt-*` including two warm-pool slots — so a **dispatched
session both has and uses it**. Adoption, not availability, is the gap.

---

## 2. WHAT IS ON DISK TODAY — the pipeline, end to end

| Stage | Tool | Gate | Verdict |
|---|---|---|---|
| file agent work | `cc-backlog add` | `--why-not-now` closed set (4 classes) when present; optional otherwise | works |
| file a value call | `cc-backlog add --why-not-now "needs-human: …"` | **REFUSES** without `--conviction N --receipt R`; refuses N>90 (bin/cc-backlog:1778-1806) | works — **1 live row uses it** |
| file an operator step | `cc-backlog needs "<step>"` | **nothing.** No class, no conviction, no receipt (bin/cc-backlog:3370-3410) | **the hole** |
| file a decision packet | `cc-decide open --class C` | **REFUSES** without conviction + receipt + ≥2 options (bin/cc-decide:26-38) | works — **2 of 31 open packets carry them** |
| Stop-side catch | `wrap-ledger.sh` `UNCONVICTED_MINE` → 🔧 | population = `whyNotNow startswith needs-human` ∪ open class-C packets (scripts/wrap-ledger.sh:823-834, 896-905) | **blind to 219/220 blocked rows** |
| Stop-side contradiction | `hooks/completion-assert.sh:584` consumes `UNCONV` | same population | inherits the same blindness |
| research | `/research`, `commands/research.md`, `research-subagents` skill | fans out N=10 subagents; **writes nothing back to any row** | no edge in, no edge out |
| dispatch | `cc-dispatch` | `status=="open"` ONLY | blocked rows never fire |
| re-validate a premise | `cc-premise check/contract/sweep` | runs at claim time; **advises, does not refuse** | works, and is the design precedent |

**There is no verb anywhere that fires research from a row.** `grep -rlE 'cc-research|research-fire|--research' bin/ scripts/ commands/ hooks/` → 0 files (measured).
**`cc-dispatch`'s composed worker brief says nothing about conviction**: `grep -niE 'conviction|research exhaustively|90%|needs-human' bin/cc-dispatch` → 0 hits (measured).

---

## 3. CENSUS

### 3a. The live population

```
bin/cc-backlog list --open --json | jq length        → 355
bin/cc-backlog list --blocked --json | jq length     → 220
```

⚠️ **`list --open` means "not done", not "open".** Its 355 rows fold to **126 open · 9 claimed ·
220 blocked** (`jq '[.[].status]|group_by(.)'`, measured). The blocked set is a strict subset of the
`--open` output, so the two files overlap by 220 and a naive concatenation double-counts. Any
research verb must select on `.status`, never on the flag name.

| status | n | age p50 | p90 | max |
|---|---:|---:|---:|---:|
| blocked | 220 | **20.9 d** | 36.2 d | 50.8 d |
| open | 126 | 14.7 d | 27.3 d | 49.2 d |
| claimed | 9 | 4.8 d | 26.9 d | 26.9 d |

(ages from `.firstTs` against 2026-09-08T21:45Z; measured.)

### 3b. Conviction / receipt coverage — zero, everywhere

```
jq '[.[]|select((.conviction//null)!=null)]|length'  → 0  (of 355 live rows)
jq '[.[]|select((.receipt//"")!="")]|length'         → 0  (of 355 live rows)
```

Open decision packets (`~/.claude/autonomy/decisions/*.json`, `status` folded, `created` field):
**31 with a parseable timestamp** (6 more have none), age **p50 13.5 d · p90 50.6 d · max 51.9 d**.
Of those 31: **29 carry no conviction · 29 no receipt · 13 have zero options** (measured). The 2 that
carry them were filed today by the protocol's own landing session.

Packets that *do* resolve, resolve fast — **n=81 terminal packets, latency p50 0.08 d, class-C p50
0.12 d** (measured from `created`→`resolved`). The distribution is bimodal: a packet the operator
sees in-session is answered in ~3 h; a packet they do not sits for 2–7 weeks. **There is no middle.**

### 3c. Why-not-now class distribution

| class | live rows |
|---|---:|
| (absent) | 345 open-fold + 219 blocked |
| `not-yet-true` | 3 |
| `needs-human` | 3 open + 1 blocked |
| free prose (pre-validation legacy) | 4 |

```
jq '[.[]|{s:.status,w:(if ((.whyNotNow//"")=="") then "no-why" else "why" end)}]|group_by(...)'
  219 blocked|no-why      1 blocked|why
  120 open|no-why         6 open|why
    6 claimed|no-why      3 claimed|why
```

### 3d. The `needs` door

```
jq '[.[]|select((.source//"")|startswith("needs"))]|length'                         → 151
jq '[.[]|select(.status=="blocked" and ((.source//"")|startswith("needs")))]|length'→ 143   (65% of blocked)
jq '… startswith("needs") and ((.whyNotNow//"")=="")' → 150 of 151
```

**Post-epoch traffic** (`.ts >= 2026-09-08T17:00:00Z`, the conviction epoch, 4 h 45 m of live use):
11 rows filed, **7 of them blocked, 7/7 through `needs`, 0/7 carrying a conviction** (measured).

I hand-read all seven. **Do not read this as laundering** — 3 are genuinely physical/observational
("call Atomic Auto Spa and ask whether they towel-dry", "name the Polestar's paint colour", "say what
you watched The Pits do"), 2 are pane/permission steps only a human can perform, 2 are re-land steps
that carry a `--run`. The `needs` door is being used correctly *today*. The finding is structural,
not behavioural: **nothing distinguishes those seven from a decision, and 16 older rows prove the
door accepts decisions.**

### 3e. Research-shaped census — top 15, hand-read

Strong lexicon (`decide whether|whether to|whether the|investigat|open question|ratif|unknown|root cause`)
over the deduped 355: **54 rows — 33 blocked, 18 open, 3 claimed** (measured). Precision on that set
was not hand-verified; treat it as an upper bound.

The tight number is the one below. Of the 220 blocked rows, **131 carry no `--run`** — i.e. no
command the operator can paste. Of those 131, **151 `needs`-sourced rows intersected with
decision-language** yields **29 decision-shaped rows, 16 of them with no runnable command**. I
hand-read all sixteen: **16/16 are genuinely decisions** (full population, not a sample).

| # | id | filed | the question | research can settle it? |
|---|---|---|---|---|
| 1 | `1a4e292830ae` | 08-09 | admit on ACTIVE CONCURRENCY vs load; compressor-SEGMENT vs free-bytes memory floor | **yes** — it is a measurement |
| 2 | `b235198a915f` | 08-04 | delete `/preview/row-alignment` (you asked) vs keep it — 7 property tests drive it | **yes** — enumerate the tests' coverage |
| 3 | `408427e74888` | 08-11 | `~/.claude/CLAUDE.md` vs `claude-infrastructure/CLAUDE.md` diverge; which is authoritative | **yes** — diff + git history settles it |
| 4 | `0645905e3d92` | 08-17 | keep the Enso DEMO venue at all (never provisioned, no DB/DNS/app) | **yes** — usage census |
| 5 | `491aeddbd912` | 08-18 | add axe target-size + `axeContrastFloor` to 3 floor-plan gate entries | **yes** — gate-coverage arithmetic |
| 6 | `baee45d1c27a` | 08-20 | VRT blind to equal-luminance recolours (pixelmatch Y 0.5053 vs chroma) | **yes** — threshold engineering |
| 7 | `b19974f7ba82` | 08-24 | add `$defaults` to `autoMode.soft_deny` — restores 35 dropped safety rules | **yes → then a C10 migration** |
| 8 | `2fa274cbeb00` | 09-08 | live layer 26 commits behind; deploy-live refuses on the dirty shared checkout | **yes** — and it is drivable work |
| 9 | `158d53aaa3b1` | 08-02 | ratify the armed-succession lifecycle (kill-by-pid on rails that retire live panes) | no — C10 ratification |
| 10 | `bb6edb17d992` | 09-06 | standing permission rule for a dispatched session's own worktree | no — self-mod, explicitly |
| 11 | `38b79edd0e90` | 08-10 | composition ruling by eye (clawd/moon 428 px off centre) | no — taste |
| 12 | `a7460321494d` | 08-08 | is `contributors@pivot-table.dev` deliberate identity or a leak | no — operator knowledge |
| 13 | `ebc271e7f303` | 08-14 | switch Cursor to update-on-relaunch | no — preference |
| 14 | `1c5837ed3d34` | 08-03 | which Harbour menu to seed (HARBOUR_2026 vs SHORTLIST) | no — client fact |
| 15 | `d29e0d9dd4cb` | 08-21 | ask Turso: does a 7th group hard-refuse or bill as overage | no — external party |
| 16 | `e951f4b9f6e4` | 08-07 | confirm with KPMG whether "6 hours" includes lunch | no — external party |

**8 of 16 are research-settleable, median filing 2026-08-17/18 ≈ 21 days ago** (measured).

### 3f. The wider stratum, with its interval stated

Of the 131 no-run blocked rows, **96 carry none of the operator-only markers**
(`OPERATOR|VALUE CALL|C10|sudo|credential|login|token|password|browser|GUI|by eye|authoriz|permission prompt|ratif`).
I hand-read a systematic sample of **20** (every 5th):

| verdict | n/20 |
|---|---:|
| research-settleable or agent-drivable | 10 |
| genuinely human-only (physical · money · credential · external party · product taste) | 7 |
| C10 self-mod — agent stages the migration, operator runs it | 3 |

Point estimate **≈48 of 96**, but the binomial 95% CI on 10/20 is **[27%, 73%]**, i.e. **26–70
rows**. Do not quote 48 as a fact. The tight number is §3e's 8-of-16.

**The C10 stratum matters and research cannot touch it.** Roughly 15% of the parked pile is a
*policy ceiling*, not a knowledge gap: the agent may not edit `settings.json`, `~/.zshrc`, or a
LaunchAgent, so no amount of conviction changes who runs it. Any proposal that promises to drain the
blocked pile by researching it is overclaiming by about that fraction.

---

## 4. IS THE WORKFLOW TOOL AVAILABLE? (method b)

### 4a. What the binary says

The tool is literally named `Workflow` (`/Users/chrisren/.claude-260/…/claude.exe`, mmap scan):

```
// Version: 2.1.260
var Gc="Workflow";  …  userFacingName(){return"Workflow"}
…,"WebSearch","WebBrowser","Agent","Task","Workflow","Skill","CronCreate",…
```

Enablement (verbatim from the binary):

```js
function ECe(){ return a.CLAUDE_CODE_DISABLE_WORKFLOWS || gw()?.settings.disableWorkflows===!0 }
function Xwt(){ return Pt("allow_workflows") }
function vc(){ if(ECe())return!1; if(!Xwt())return!1;
               let{available:r,defaultOn:e}=o(); if(!r)return!1;
               return gw()?.settings.enableWorkflows ?? e }
```

with `o()` reading `CLAUDE_CODE_WORKFLOWS` (tri-state) and the statsig gate `tengu_workflows_enabled`.

**Five terms, and not one of them is a session kind.** No print-mode term, no headless term, no
subagent-depth term. Availability is decided by: an env var, a settings key, an **account
entitlement** (`allow_workflows`), and a remote gate. (inferred from code — the negative claim
"there is no session-kind term" is a claim about *this* predicate, not about the whole tool-list
assembly, which I did not audit.)

Related env surface, for whoever tunes it: `CLAUDE_CODE_WORKFLOW_SIZE_WARNING_AGENTS`,
`CLAUDE_CODE_WORKFLOW_SIZE_WARNING_TOKENS`, `CLAUDE_CODE_WORKFLOW_PREFIX_STAGGER_MS`,
`CLAUDE_CODE_WORKFLOW_LAUNCH_SHA256`, `CLAUDE_CODE_WORKFLOW_PROMPT_PROVENANCE`.

### 4b. What the corpus says (measured)

Population: every `*.jsonl` under the four deduped roots (`~/.claude`, `-secondary`, `-tertiary`,
`-quaternary`; `~/.claude-next` is a symlink into one of them) with mtime ≥ 2026-09-01 = **1,494
files**.

🚨 **Instrument note, and it cost me three false zeroes.** macOS `xargs` has **no `-a` flag**, and
`grep -F "\"name\":\"X\""` inside a single-quoted `bash -c` keeps the backslashes literally. Both
produced a clean `0` with exit status 0. The positive control that caught it: the same pipeline over
`"name":"Bash"`, which must be non-zero. Working form:

```bash
printf '"name":"Workflow","input"\n' > /tmp/pat.txt
cat files.nul | xargs -0 -n 100 -P 6 /usr/bin/grep -l -F -f /tmp/pat.txt | wc -l
```

| measurement | n |
|---|---:|
| files since 2026-09-01 | 1,494 |
| files recording a tool-**definition** block (`"name":"Bash","description"`) — the observable denominator | 251 |
| …of those, **offered `Workflow`** | **248 (98.8%)** |
| files with a real `Workflow` **invocation** (`"name":"Workflow","input"`) | **21** |
| total Workflow invocations | **48** |
| files with a real `Agent` invocation | 38 |

Of the 21 invoking sessions: 10 in `claude-infrastructure`, 4 in `personal`, and **4 under
`~/Development/.worktrees/wt-*` — including `wt-pool-7` and `wt-pool-8`, the warm pool
`handoff-fire.sh --worktree` claims.** So **a dispatched session both has and uses the Workflow
tool** (measured, n=4).

Cross-check from prior landed work (`docs/research/workflows-vs-teams-2026-08-20.md` §2, quoted from
the bundle): a workflow `agent()` gets `tools:["*"]` **denied `SendUserMessage` · `Agent` ·
`Workflow`** — so workflows do not nest, and a subagent (this one) is not offered it either.

### 4c. What I did NOT measure

**Headless `claude -p`.** The predicate carries no print-mode term, but I did not run the probe and
the tool list is assembled elsewhere. The probe, for whoever wants it (one command, costs one small
turn on one account):

```
CLAUDE_CONFIG_DIR=~/.claude-quaternary claude -p 'Reply with only the exact names of your available tools, comma-separated.'
```

`Workflow` present ⇒ headless has it. Absent ⇒ the filter is outside `vc()`.

---

## 5. THE DESIGN — `cc-backlog research <id>`

Four house rules constrain this, and each has a scar behind it:

1. **Never classify by prose shape.** `bin/cc-decide`'s own docblock: *"grepping a path out of prose
   is exactly the shape-classifier that must not be built… classify by the producer's literal
   emission, never by shape."* Lead-measured: the 'decision' vocabulary runs 30% precision, which is
   why no hook matches it. **The producer declares; nothing infers.**
2. **Enforce at the chokepoint, on the EFFECT, not on the verb spelling.** `cc-backlog`'s own
   `unblock`/`reopen`/`block`-over-done history: three spellings of one effect, guarded one at a time,
   out-run each time (memory: `denylist-enumerates-spellings-not-the-class`).
3. **Run at CONSUMPTION, not as a sweep.** `cc-premise`: *"A one-time review goes stale the moment it
   finishes — that decay is precisely what produced the pile it would be reviewing."*
4. **The enforcing store for a worker is its BRIEF, not an exit code** (`cc-premise` again). Landed
   prose in a plan changes nothing (memory: `conclusion-must-reach-the-enforcing-store`).

### 5a. The verb

```
cc-backlog research <id> [--venue local|cloud] [--dry-run]
```

1. Selects on `.status` (`blocked` or `open`), never on a flag name (§3a).
2. Takes a **lease**, exactly as `claim` does — a new fold state `researching`, with the same
   liveness oracle and the same condition-sibling refusal. Without it, two sweeps double-fire.
3. Composes a **read-only** brief from the row: `title` + `needs` + `dodRef` + any `falsifier` + the
   `cc-premise contract` block the dispatcher already emits.
4. Fires it through the existing rail:
   `handoff-fire.sh --prompt-file … --goal '<the row's question> answered with a stated conviction — proven by `cc-backlog conviction <id>` printing a number and a receipt path; do not edit source; do not file a new row'`.
   No new dispatch machinery.
5. Its **only** definition of done is one new verb:

```
cc-backlog conviction <id> --conviction N --receipt PATH|"<cmd> => <output>" [--option "label::outcome" …]
```

   Today `conviction`/`receipt` can only ride an `add` or an `update` (bin/cc-backlog:1695-1700,
   2032-2052). They cannot be attached to an existing row at all, which is why a researched row has
   nowhere to put its answer. This verb is the missing write.

6. **The dispatch edge, and it is the whole trick.** On return:
   - `N > 90` ⇒ `unblock` the row. It folds to `open`, and **`open` is already `cc-dispatch`'s fire
     predicate** — so the implementation wave fires itself with zero new code. This is the single
     missing edge in the entire pipeline.
   - `N ≤ 90` ⇒ the row stays blocked but now carries the number, the receipt path and ≥2 measured
     options, so `wrap-ledger` renders a real 👤 and `cc-do --list` can show the operator a decision
     they can answer in one word instead of a paragraph they must re-derive.

**Failure direction:** errs toward *spending quota on rows research cannot move* (the C10 stratum,
§3f — ~15% of the pile). Bound it: refuse `research` on a row whose `--kind` (below) is
`sudo|physical|gui|credential|money`, and cap fires per sweep. It must NOT err toward silence — a
research verb that abstains when unsure re-creates the pile it exists to drain.

### 5b. The gate that makes it happen — one change, three arms

**Arm 1 — a required closed-set `--kind` on `cc-backlog needs`.** The set:
`sudo | physical | gui | credential | external-info | pane | money`. This is a producer declaration
in the exact idiom `--venue` and `--why-not-now` already use, not a prose classifier. **A decision
has no spelling in the set**, so it cannot be filed through this door; the refusal message names the
two legal alternatives (`add --why-not-now "needs-human: …" --conviction --receipt`, or
`research <id>`). All 7 post-epoch rows and all 3 physical rows in §3d map cleanly onto a kind, so
the set is wide enough for live traffic.

*Failure direction: friction.* Every legitimate operator step now needs one more flag, and a caller
that cannot find its kind may file **nothing at all** — silent loss, which is strictly worse than an
extra row. Mitigations: keep the set wide, allow `--kind other --why "<one line>"` as an escape that
is *recorded and counted* rather than refused, and make the refusal message name the alternative
verb. Errs noisy; that is the correct side here.

**Arm 2 — widen `UNCONVICTED_ROWS`'s population.** Today:
`.whyNotNow startswith "needs-human"` — reachable by **1 live row of 220**. Change to: *every
`blocked` row this session filed (`.filedBy == $SID`, `.ts >= epoch`) that carries no `receipt`*,
**minus** rows whose `--kind` is in Arm 1's set. One `jq` predicate in
`scripts/wrap-ledger.sh:823-834`; `hooks/completion-assert.sh:584` consumes `UNCONV` unchanged.

*Failure direction: nagging.* Without Arm 1's exemption this convicts a session that correctly files
"call the car wash" — so **Arm 1 and Arm 2 are one change, not two, and Arm 2 must not ship first.**
A gate that fires on a legitimate close is the failure this wave exists to find: it trains the model
to route around the store entirely, and the un-filed case (§5d) is already the blind spot.

**Arm 3 — one paragraph in `cc-dispatch`'s composed brief.** Measured: zero conviction language
there today. Add: *"If you would hand this row back as the operator's, spend a research session
first. The row's exit is `cc-backlog conviction <id> --conviction N --receipt R`. N > 90 means
implement it, not file it."*

*Failure direction: inertness.* A brief clause is advice, and this repo has measured that landed
prose changes nothing. It is the cheapest arm and the weakest. Ship it **with** Arms 1–2, never
instead of them.

### 5c. The Stop-side term for "recommends without a receipt" (the A02 shape-4 relative)

Name: **`RECOMMENDED_UNRESEARCHED`**. It is Arm 2 under a different label, and it must be
**store-keyed, not prose-keyed** — the prose form ("I recommend X; your call") is exactly the
vocabulary the conviction census measured at 30% precision and deliberately left unmatched. Rung:
the filer's own **🔧**, same rank as `FILED_MINE` — never 👤 (it is not theirs yet) and never ⛔ (it
is not a decision yet; it is a question nobody researched). Fail-open like every sibling.

### 5d. The gap the protocol cannot close, stated as a limit

**Every arm keys on a store. A session that researches nothing and files nothing is invisible to all
of them.** It says "this needs more investigation" in prose, closes ✅, and no sensor — not
`completion-assert`, not `wrap-ledger`, not `anti-deference-nudge` — has an object to read. The
only available non-prose discriminator would be "did this session run any tool over the subject it
named", which is not computable at Stop from the transcript at the sizes involved (lead-measured:
`completion-assert` already takes 4.14 s on a 69 MB transcript against a 5 s timeout, and the corpus
holds 230 MB files).

**Honest verdict: the unfiled case cannot be mechanized from the Stop side. It can only be
starved** — by making `research <id>` cheaper than filing, so filing becomes the natural move, and
then gating the filed path. Do not build a prose detector for it; this house has burned that fixture
before.

---

## 6. COST MODEL (method e)

### 6a. What a wave costs — measured house constants

From `docs/research/workflows-vs-teams-2026-08-20.md` §3c (measured on this box; **pp** = percentage
points of one account's weekly quota):

| N tasks | N teammates | N-agent workflow | N dispatched sessions |
|---:|---|---|---|
| 2 | 3.02 pp | 4.67 pp | 5.31 pp |
| 5 | 6.17 pp | 10.30 pp | 8.41 pp |
| **12** | **16.20 pp** | **26.11 pp** | **16.65 pp** |

Per-unit worker-side: teammate **0.873 pp/task**, workflow agent **1.699 pp/task**, dispatched
session **0.875 pp/task**. A workflow's premium is **1.5–1.7×**, not the folk 6×.

**So: one dispatched research session per row ≈ 0.875 pp + the lead's brief.** Researching all 96
candidate no-run blocked rows ≈ **84 pp ≈ 0.84 account-weeks**. The eight hand-verified
research-settleable decisions (§3e) ≈ **7 pp**.

### 6b. What the wait costs

| | measured |
|---|---|
| blocked rows | 220, age **p50 20.9 d · p90 36.2 d** |
| open decision packets | 31 dated, age **p50 13.5 d · p90 50.6 d · max 51.9 d** |
| packets that DO resolve | n=81, latency **p50 0.08 d** (class C **0.12 d**) |
| the 8 research-settleable decisions | median filed **2026-08-17/18 ≈ 21 d ago** |
| a research session's wall clock | **32 min** at 40–80K output; **73 min** at 80–150K (measured median lifetimes, workflows-vs-teams §3d) |

**Ratio: ~30–75 minutes of compute against a p50 wait of 20.9 days (≈500 h) — 400–1000×.**

### 6c. Where the quota comes from

- **Stranding, measured:** ~167 pp (≈1.7 account-weeks) stranded in one cycle on 2026-09-05
  (`scripts/desk-strand-replay.py`, cited in the global `CLAUDE.md` FILED rule) against ~5 pp/window
  through August. Weekly quota does not roll over. **The entire backlog's research bill (84 pp) is
  about half of what one cycle already throws away.**
- **Admission, measured today:** 903 fires admitted in the 17 h to 21:45Z; 46 refused — **43
  `payload`, 3 `subagents`, 0 capacity** (`jq` over `~/.claude/logs/handoffs.jsonl`, which itself
  holds only 2026-09-08T04:48Z onward — it is rotated, like the IDL, so this is a 17-hour census, not
  a 30-day one).

**Conclusion: the constraint is not quota and not admission. It is that no verb exists to spend
them on a blocked row.**

---

## 7. ADVERSARIAL PASS

Three things a hostile reviewer would say, and what I found when I checked.

**"The pile is unresearched, so your whole framing is backwards."** Checked, and the reviewer is
half right in a way that strengthens the finding: 37 of 220 blocked rows carry a `RE-VERIFIED` /
`RE-MEASURED` / `PREMISE CORRECTED` stamp, several dated 2026-08-18 (a mass re-verification sweep).
The rows are researched **repeatedly** and re-parked each time. The defect is the missing
blocked→open edge, not missing research. This is why the recommendation is a *dispatch* edge, not a
*research* mandate.

**"Research cannot move the C10 rows, so you are overclaiming."** Correct, and quantified: 3 of 20
in the systematic sample are C10 self-mod, where the ceiling is policy, not knowledge (`autoMode.soft_deny`
denies "Self-Modification" and "Unauthorized Persistence" by construction). ~15% of the pile is
permanently research-proof. Stated in §3f rather than buried.

**"Your 96-row stratum is a lexical artifact."** Partly. The marker-based filter is crude and I did
not hand-verify the 54-row strong-lexicon set at all. That is why the load-bearing number in this
report is §3e's **16 rows hand-read in full, 16/16 precision on 'is a decision', 8/16 research-
settleable** — a complete population, not a sample — and why §3f carries its binomial interval
[26, 70] rather than a point estimate.

**Fourth thing, which I nearly shipped as a finding.** My first three corpus scans returned `0` for
`Workflow`, `Agent` **and** `Bash`. Two independent instrument bugs (macOS `xargs` has no `-a`;
backslash-escaped patterns inside a single-quoted `bash -c` are literal). Had I not run the `Bash`
positive control I would have reported "the Workflow tool is never used in this fleet" — the exact
inverse of the measured 21 sessions / 48 invocations. Memory rule `positive-control-the-denominator`,
paid for again.

---

## 8. OPEN QUESTIONS, EACH WITH ITS PROBE

| # | question | probe |
|---|---|---|
| 1 | Is `Workflow` offered in headless `claude -p`? | `CLAUDE_CONFIG_DIR=~/.claude-quaternary claude -p 'Reply with only the exact names of your available tool s, comma-separated.'` — grep for `Workflow` |
| 2 | Which of the 220 blocked rows would a research session actually move? | run `research` on the 8 in §3e first; measure how many reach N>90 |
| 3 | Does `Pt("allow_workflows")` vary by account? | run probe 1 against all four `CLAUDE_CONFIG_DIR`s |
| 4 | What fraction of the 96-row stratum is research-settleable? | hand-read all 96 (I read 20); ~2 h of one session |
| 5 | Does the `--kind` closed set cover live traffic without an `other` escape? | replay the last 151 `needs` rows against the set and count misses |

---

## 9. PROVENANCE

Read-only. Nothing was spawned, killed, closed, edited or configured; the only file written is this
one. Sources read: `bin/cc-backlog` (6,725 L), `bin/cc-decide` (459 L), `bin/cc-dispatch`,
`bin/cc-premise`, `bin/cc-roles`, `scripts/wrap-ledger.sh:599-905,1752-1760,1998-2012`,
`scripts/handoff-fire.sh:1-80`, `hooks/completion-assert.sh:34-98,568-584`, `commands/research.md`,
`docs/research/workflows-vs-teams-2026-08-20.md`. Stores read: `~/.claude/autonomy/backlog.jsonl`
(via `cc-backlog list --json`), `~/.claude/autonomy/decisions/*.json` (190 files),
`~/.claude/logs/handoffs.jsonl` (1,027 rows), the four transcript roots (1,494 files since
2026-09-01), and `~/.claude-260/…/claude.exe` (mmap, read-only).
