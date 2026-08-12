# recon-wave — one long-running lead vs. one session per item

READ-ONLY recon, 2026-08-12. Every number re-derived this session from disk/transcripts; nothing
quoted from a plan without re-measuring (published figures in this repo decay within days).

---

## 0. THE HEADLINE THE BRIEF DID NOT ASK FOR BUT DECIDES THE QUESTION

The one-session-per-item model was **measured and switched off yesterday**.
`25f369292` (2026-08-11 16:33) — *"chore(dispatcher): pause to DECIDE-ONLY — 189 worker panes a day
against an operator budget of ~15"*. Its body, verbatim measurements:

- **189 panes fired in one day.** Box at **2.19 load/core against handoff-fire's own 2.0 ceiling**,
  which REFUSED that session's own fire — *"the dispatcher had become a competitor to the operator
  for a ~15-session budget."*
- Verified by effect: one pass under the exact launchd argv produced **0 spawns and 306 journalled
  decisions**.

Corroborated independently in `~/.claude/logs/handoffs.jsonl`: fires admitted per day
**381 (08-09) · 263 (08-10) · 136 (08-11) · 2 (08-12)**, with **39 / 74 / 25** refusals.
The operator's ask is not a preference — it is the remedy already in flight.

---

## 1. MACHINERY MAP

### BUILT-PROVEN (live, with disk evidence of it working)

| Component | What it does | Evidence |
|---|---|---|
| `bin/cc-wave-plan` (1104 ln) | **NOT a roadmap tool.** Quota-aware *placement*: `[{id,slot}] → {account,model,effort,fire_line}` or a trichotomous wall (4 capped / 5 auth / 6 unknown). Never fires. | Header `bin/cc-wave-plan:1-52`; wired at `bin/cc-dispatch:1754` via `CC_DISPATCH_WAVEPLAN_BIN`; live IDL rows `action=fired` as recently as `2026-08-12T07:15:21Z` |
| `cc-dispatch` decision/admission split | Decision is a pure read over the whole backlog; admission is the only capacity-bound step | `AUTONOMY_DISPATCH_V2.md` §1 "The inversion"; live IDL `cc-dispatch decision` rows at `2026-08-12T08:49:28Z` |
| `handoff-fire.sh --recycle` | Same-pane fresh context succession | **14/14 `recycle-engaged` rows, 0 dead, 0 unverified**, 2026-08-09→08-12 (`~/.claude/logs/handoffs.jsonl`) |
| Goal inheritance across recycle | `inherit_recycle_goal()` re-arms the predecessor's live `/goal` on the successor | `scripts/handoff-fire.sh:3778-3800`; test `tests/handoff-goal-arm.bats:305` |
| `cc-custody` (CLOSE_INTEGRITY W2) | Fire with `--notify-back` records a DEBT on the firing cwd; peer's close discharges it | live store shows 10 open→return pairs 08-10/08-11; **1 open debt** (`fire-d56a874d9441`, 08-11T21:32) |
| Custody wake floor | An originator with open custody is mechanically **kept wakeable and blocked from a silent close** | `hooks/session-continue.sh:470,520` — *"idling deaf is how a wave gets abandoned"*; cites the generator: **62 stranded commits, 5 wave-day spikes** |
| `hooks/lib/dod-path.sh` | Frozen DoD keyed on **repo identity** (sha of `remote.origin.url`), not toplevel path — survives the worktree hop | file header: the pre-fix defect was *"the RECOMMENDED long-horizon pattern — wave N+1 on a fresh worktree — landed every successor on a BLANK scope contract"*; **64 unaggregated per-path files at measurement** |
| `bin/cc-tlid` | ONE shared task board per **repo identity** across worktrees + all 4 accounts | header; residue it replaced: **373 empty project-keyed boards** |
| `cc-backlog --condition` re-keying + `--fold` | A wave becomes a condition-keyed row; recurrences UPDATE instead of MINT | `BACKLOG_CONSOLIDATION_2026-08-09.md` § W3: **18 groups / 46 live rows, every group exactly one worktree, ZERO cross-subject merges**; R7 brake: **172 live needs rows, 46 recurrences in 18 groups = 28 rows that would not exist** |
| Machine capacity gate | Refuses a fire above 2.0 load/core, `--recycle` exempt (`scripts/handoff-fire.sh:5929`) | refused the READINESS W1 fire at **21.89 load / 10 cores = 2.19/core** |

### BUILT-UNPROVEN (code + unit tests exist; no live non-dry-run instance found)

| Component | Gap |
|---|---|
| **`--recycle --worktree NAME` (relocating recycle)** | Landed `6507f5179` (2026-08-08), tested `tests/handoff-recycle-relocate.bats:59,80`. Searched `~/.claude/logs/bash-execution.log` + `bash-commands.log` + all transcripts: the **only** `--recycle --worktree` invocation on record carries `--probe --follow --dry-run`. The 14 live recycle rows do not record the reloc flag, so **the pattern CLAUDE.md now calls the default long-horizon succession has never been observed executing for real.** |
| `CC_DISPATCH_VENUE_ONLY` | `8e179c429` (08-11). Interlocked: `launchd/com.claude.dispatcher.plist:20-32` — DECIDE_ONLY must stay on *until the deployed binary honours it*; the flip alone fired 2 local panes because `~/.claude/bin/cc-dispatch` is a per-file symlink trailing origin/main |
| Readiness gate enforce-mode | `CC_DISPATCH_READY_GATE` ships **advisory**; measured would-block **100% → 60%** across two passes, i.e. enforcing today blocks 3 admissions in 5 (`BACKLOG_CONSOLIDATION_2026-08-09.md` § W1) |

### SPEC-ONLY / DEAD

| Item | Status |
|---|---|
| **`GROUND_UP_DISPATCH.md` standing COORDINATOR** — *"1 COORDINATOR (the recycled successor of e891e080, standing) + up to 2 concurrent REBUILD sessions"* | **The closest precedent to the operator's ask, and it DIED.** 2026-08-07 diagnosis: *"the campaign died because its continuation lived in a coordinator's memory."* 2026-08-11 entry opens: *"Run from a dispatch worker, no coordinator in existence."* status frontmatter still `open`. |
| `SESSION_SPRAWL_CONSOLIDATION_PLAN.md` | DONE 2026-07-21, but it is about *crash-recovery* sprawl (14 sessions resurrected on one repo, 8.8 GB RSS), not wave orchestration. Same direction (one session per worktree), different subsystem. |
| A wave-roadmap *tool* | **Does not exist.** No component consumes a plan file's Phase-0 wave table. The only machine-readable roadmap surface is `cc-backlog` rows with `--condition` + `dodRef` pointing at the plan doc. |

---

## 2. RUNTIME — the live binary and the correct spawn API

**Version: CC 2.1.220.** Evidence chain (a launcher `--version` reports the launcher's track, so this
is read off the running process):

```
ps -o command= -p $PPID
→ /Users/chrisren/.claude-220/node_modules/@anthropic-ai/claude-code/bin/claude.exe \
  --agent-id recon-wave@session-ebbd173a --agent-name recon-wave --team-name session-ebbd173a \
  --agent-type deep-research --permission-mode auto --effort xhigh --model opus
package.json → "version": "2.1.220"
```

**Spawn API: `Agent({ name: … })`. `team_name` is DEAD.** Three independent confirmations:

1. **The live tool schema** (this subagent's own Agent-tool definition, i.e. read out of the running
   binary): `team_name` — *"Deprecated; ignored. The session has a single implicit team."*
   `mode` — *"Deprecated; ignored."* The live parameter set is
   `{name, subagent_type, model, isolation, run_in_background, prompt, description}`.
2. **Binary grep**: `rg -a 'team_name' claude.exe` → **4 hits**; `TeamCreate` / `TeamDelete` → **0**.
3. **My own argv**: the lead spawned me with `name:` only, and the runtime *assigned*
   `--team-name session-ebbd173a` itself — the implicit-team behaviour `skills/agent-teams/SKILL.md:321-327`
   documents (*"`name:` is the switch, not `team_name`"*).

`skills/agent-teams/SKILL.md:50-51` already says this (binary-extracted 2026-08-03) and is correct.
**The global CLAUDE.md § Agent Teams Reinforcement is STALE**: it still says
*"spawn via `Agent({ name, team_name, model })`"* and describes 2.1.183. Harmless (the arg is
ignored) but it is a resident rule restating a perishable fact.

Live model/window (13 `/tmp/cc-telemetry/*.json` files, all agreeing):
`claude-opus-5`, **window = 1,000,000**, effort `high`. So the 400K working-ceiling guidance is a
quality judgment about a 1M window, not a hard limit.

---

## 3. LONGEVITY — measured, 7,035 transcripts across 5 config dirs

### Multi-day sessions ALREADY EXIST. Calendar time is not the binding constraint.

| sessionId | span | **ACTIVE** (gaps capped 30 min) | records | peak ctx | how it ended |
|---|---|---|---|---|---|
| `21e6752c` | **80.44 h (3.4 days)** | 5.46 h | 1160 | 436 K | OAuth 401 — *Please run /login* |
| `57342265` | 69.70 h (2.9 d) | 8.85 h | 2197 | 780 K | **weekly limit** |
| `7b016dfc` | 59.80 h (2.5 d) | 11.06 h | 995 | 277 K | 529 Overloaded |
| `c64feb3d` | 53.30 h (2.2 d) | 12.96 h | 2000 | 625 K | clean |
| **`076a1186`** | 43.92 h (1.8 d) | **19.42 h** | **3413** | **976,626** | **`Prompt is too long`** |
| `a28e8b9c` | 17.65 h | 7.51 h | 1882 | 905 K | clean — **12 named teammates**, 2 pinned `model:"fable"` |

Fleet distribution over 3,413 non-agent transcripts: span **p50 0.40 h · p90 4.60 h · p99 25.93 h ·
max 311.6 h** (that 311 h outlier holds 68 records — an idle resume, not work). **282 exceed 6 h.**
Peak-context distribution: **p50 185 K · p90 422 K · p99 752 K · max 976,626**; 2,188 files pass
150 K, 374 pass 400 K, **18 pass 800 K**.

### Top 3 measured killers (distinct sessions; "terminal" = no assistant turn after)

| class | events | sessions | **terminal** | lethality |
|---|---|---|---|---|
| TRANSIENT (529 Overloaded, ECONNRESET, stalls) | 229 | 105 | 28 | 27 % |
| **AUTH** (`Not logged in`, OAuth expired) | 75 | 63 | **26** | 41 % |
| **LIMIT_weekly** | 64 | 30 | **19** | 63 % |
| LIMIT_5h | 42 | 19 | 2 | 11 % — survivable |
| LIMIT_spend | 20 | 13 | 2 | 15 % |
| **CTX_CEILING (`Prompt is too long`)** | 8 | **5** | **5** | **100 %** |

**The context ceiling is the only 100 %-fatal class, and it selects for exactly the session we are
trying to build.** 4 of the 5 were long claude-infrastructure leads (7.4 h / 9.7 h / 12.4 h /
**43.9 h**; 1057–3413 records). None had ever compacted.

### Compaction is not a safety net (re-derived)

**203 `compact_boundary` records across 72 files. Every `compactMetadata.trigger` value on disk is
`"manual"` (27 occurrences). Zero `auto`.** This re-derivation differs from
`CONTEXT_ECONOMY_V2.md`'s published "39/39 manual" — the conclusion holds, the count has moved.
Corollary: **`/compact` crashing teammates (GH #49593) is a near-zero risk in this fleet because
nobody compacts** — and that is precisely why the ceiling is a wall.

### The fan-out pattern that reaches the wall fastest

Leads since 2026-07-25, transcript >300 KB, ≥0.5 h active:

| lead pattern | n | median PEAK ctx | median active |
|---|---|---|---|
| ≥3 **named teammates** | 132 | **458 K** | 2.33 h |
| ≥2 dispatched `handoff-fire` sessions, 0 teammates | 305 | **289 K** | 1.45 h |
| inline, no fan-out | 401 | **224 K** | 0.94 h |

⚠️ **Honest limit on this table.** I first computed peak÷active-hours as a "burn rate" and it came
out flat (196 K / 213 K / 224 K per hour) — that is an aggregate ÷ N, not a marginal, and it is
confounded by session length. **The load-bearing number is PEAK, and teammate-leads reach 1.6× the
peak of dispatch-leads while running 1.6× longer.** Direction supports CLAUDE.md's claim that
dispatched sessions protect the lead's window; it does not isolate the mechanism.

---

## 4. SUCCESSION — can a lead recycle mid-wave and keep driving?

**Yes for plain `--recycle`; the *relocating* variant is unproven; the roadmap must live in a
store, not in the lead.**

- **Plain recycle works, measured.** 14/14 `recycle-engaged`, 0 failures, 2026-08-09→08-12
  (`~/.claude/logs/handoffs.jsonl`). Before 2026-08-09 this was *unobservable* —
  `scripts/handoff-fire.sh:638-646`: *"1012 rows spanning 41 h carry ZERO recycle rows of any class,
  while `--recycle` is the commonest succession on this box."* The prior hand-census verdict was
  **1-of-7** (`docs/proposals/ARMED_SUCCESSION_LIFECYCLE.md` §1). **The instrument is 3 days old.**
- **A recycle chain is directly observable.** `recycle-engaged prev_sid=e5d3628d, pane 29,
  2026-08-11T09:15:52Z` → session `b7444e35` first record `09:15:40Z`. Pane 113 recycled twice
  (01:19 and 04:25 on 08-11) — a ≥3-generation chain in one pane.
- **The goal survives.** `inherit_recycle_goal()` re-arms the predecessor's live `/goal` on the
  successor (`handoff-fire.sh:3778-3800`), with pre-arm re-validation and `CC_RECYCLE_GOAL_INHERIT=0`
  opt-out. Note `handoff-fire.sh:3647`: *"a goal set by ANY route dies with its session"* — the
  inheritance is what closes that.
- **The frozen DoD survives the worktree hop** since `hooks/lib/dod-path.sh` (repo-identity keying,
  dual-read migration, zero rewrites).
- **The originator cannot silently abandon the wave.** Open custody folds into the ledger as 🔧, makes
  the ✅ certificate mechanically unreachable, and arms the wake floor
  (`hooks/session-continue.sh:470-520`).
- ❌ **The gap: `--recycle --worktree` has no live instance.** Only a `--dry-run` on record. Since
  "wave N+1 on a fresh worktree off origin/main" is the exact pattern this feature exists to serve,
  a multi-day lead's *first* relocating recycle would be its production debut.

### The generator that actually killed the last long-horizon campaign

`GROUND_UP_DISPATCH.md` § Wave log 2026-08-11 names it three times in one session, one layer apart
each time — **a correction landed in a place its reader never reads**:

1. runbook → coordinator: *"a runbook paragraph binds a successor who is never spawned"*
2. wave-log → payload: *"`handoff-fire` submits the payload file as the fired session's first
   prompt — a worker reads the payload, never the runbook that discusses it"*
3. trunk → checkout: every `dodRef` is an absolute path into the SHARED CHECKOUT, held by the
   fail-closed deploy autopilot at the last GREEN commit. Measured minutes after the land:
   **checkout 17 commits behind origin/main**, `grep -c "STEP -1 — RECONCILE"` at the dodRef path
   returned **0** while the identical path on trunk returned **1**.

And the store-based cure has its own width limit: *"A store-based continuation is only as wide as its
generator's input predicate."* The `plan-open` generator takes an **open plan doc** as input, so row 6
— the campaign's only row with no plan doc — was structurally unreachable, *"and no amount of
coordinator discipline would have changed that."*

**Direct implication for the ask:** a wave roadmap written in a plan file binds nothing unless (a) the
wave rows are also filed in `cc-backlog` with a `--condition` key, and (b) the *fired brief itself*
carries the operative instruction — because the worker reads the brief, and the checkout it resolves
paths against lags trunk.

---

## 5. A REAL EXECUTED EXAMPLE — READINESS, 2026-08-11

`docs/plans/BACKLOG_CONSOLIDATION_2026-08-09.md` § READINESS. Phase 0 declares **EXECUTION LOCUS PER
WAVE** exactly as `plan-conventions` requires:

| Wave | Declared locus | Deliverable | Landed |
|---|---|---|---|
| W0 · the instrument | **L** (lead-inline) | ratchet: dispatchable denominator + floor guard | `c61ee7147` 16:09 |
| W1 · the conjunction | **S** (dispatched) | `readyAt` + admission-seam gate, advisory-first | `eca80713d`+`5ac7990d9` 16:52-53 |
| W2 · the second screen | **S** | filing-day discrimination + retro-scan | `295f6240a` 17:05 |
| W3 · act, and brake | **S** | condition-fold actuator + `needs` brake | `8f1726cfb` 17:32 |

**How execution actually tracked** (all times local; sessions verified by grepping commit subjects
across all transcripts):

- Plan written `a0a80f2b7` 16:09. W0 inline. Lead = `b7444e35` — **8.35 h span, 861 records, peak
  432 K ctx, 0 compactions, 14 Agent spawns ALL UNNAMED** (research subagents: 10× `general-purpose`
  falsifier-backfill fired in a 32-second burst at 09:21, then 4 adversarial reviewers). **Zero named
  teammates.** That lead was itself born from a recycle 12 s earlier.
- W1's first fire FAILED twice — the cold-worktree autosubmit race left pane 393 task-less, and the
  warm re-fire was refused by the capacity gate at 2.19 load/core. The three waves were converted to
  **condition-keyed backlog rows** (`d73a772a8468` / `0e8a10c501af` / `df003b95630b`) with durable
  briefs committed at `docs/plans/readiness-2026-08-11/` — *"a filed row pointing into /tmp is this
  wave's own defect."*
- **They then ran as declared.** Three separate worktree sessions:
  `readiness-w1/161ad682` (544 recs, 308 K peak, 23:22→00:27 UTC, self-closed via
  `handoff-fire.sh self-close --terminal`), `readiness-w2/ae6c57ed` (333 recs, 206 K),
  `readiness-w3/8bf055e3` (563 recs, 276 K). **Each worker ended at ≤31 % of a 1M window.**
- **All four waves landed inside ~1 h 23 min.** No wave-session hit an API error of any class.

**What tracking looked like in the doc — and this is the part worth copying.** Every wave's return
section *refutes part of its own brief*, in the plan, with the measurement:

- W1: *"THE MEASUREMENT IS THE DELIVERABLE, AND IT REFUTES THE OBVIOUS NEXT STEP"* — would-block
  100 % → 60 %; **6 of 10 verdicts are `cites-nothing`, not staleness**; the plan's own "219
  unlabelled" figure re-measured to **312 open+claimed / 281 with venuePlan / 31 without** and was
  retired. *"Third time this document's figures have decayed under it: re-derive, never quote."*
- W2: the wave's brief named **three** anti-coverage items and **one was innocent**; the false
  conviction came from the instrument the plan itself prescribed.
- W3: *"R6 as written is wrong, and the error is mine"* — the trigger's normalisation key masks
  `[0-9a-f]{7,40}` → `<sha>`, which erases the discriminator when the sha IS the subject. Its
  largest "cluster" of 14 rows was **nine different stranded worktrees**; folding them would have
  **refused dispatch on all nine**. Generalised law: *"a key that is sound for COUNTING a shape is
  not thereby safe for ACTING on it."*

---

## 6. ADVERSARIAL PASS — what a hostile reviewer says I missed

1. **"You measured killers, not the ones that matter for a lead that never dies."** Checked. Over a
   multi-day horizon the *silent* failure is **landed ≠ live**: `~/.claude` is reached by per-file
   symlinks into the shared checkout, which the fail-closed autopilot holds at the last GREEN commit.
   Measured now: **checkout 7 commits behind origin/main** (inside the 25-commit budget) — but the
   ADD case gets **no budget at all** (a landed diff that adds a file is *absent*, and every
   `[ -f x ] && . x` consumer silently skips). A lead that lands its own tooling over days will keep
   running old bytes. The interlock in `launchd/com.claude.dispatcher.plist:20-32` is a live instance:
   the VENUE_ONLY config flip alone fired 2 local panes because the deployed binary had never heard
   of the variable.
2. **"You assumed the ceiling is 1M."** Verified from live telemetry, not from the model id: 13/13
   sessions report `window: 1000000` on `claude-opus-5`. CLAUDE.md's warning that the fleet spans
   both 200 K and 1 M is *currently* not binding — but the denominator lives in
   `/tmp/cc-telemetry/*.json`, which is wiped on reboot, so this fact has a half-life.
3. **"Teammates crash on `/compact` — you dismissed it."** I re-derived it instead: 203
   `compact_boundary` records, **every trigger `manual`, zero `auto`**. The risk is real but
   unexercised; the *reason* it is unexercised is that this fleet drains by recycle rather than
   compacting, which is the same discipline that makes the ceiling terminal.
4. **"Your teammate-vs-dispatch context claim is a rate."** Retracted mid-analysis — see §3. Peak
   context is the honest discriminator; burn-per-hour is an aggregate ÷ N.
5. **Not checked, named as a gap:** whether 6 concurrent teammates + a multi-day lead can coexist
   with the 2.0-load/core capacity gate on a 10-core box under sustained load (the READINESS refusal
   at 2.19 and the GROUND_UP entry's *"ambient load was 14.23 against the runbook's own `< 10` cadence
   guard"* both say this is the binding physical constraint, but I did not measure teammate load
   contribution directly).

---

## 7. WHAT THIS MEANS FOR THE ASK (synthesis, not new evidence)

- **Calendar days are already achievable** (80 h observed). The budget that actually runs out is
  **cumulative context**: the fleet's hard stop is a 100 %-fatal `Prompt is too long`, and the single
  most-worked session in the fleet (19.4 active hours, 3,413 records) hit it at **976,626 tokens**.
- **The lead therefore cannot be the roadmap's memory.** That is the exact failure `GROUND_UP_DISPATCH`
  already measured and named. The roadmap must be (a) the plan file for humans, (b) `cc-backlog`
  condition-keyed rows for the dispatcher, and (c) restated *inside each fired brief*, because a
  worker reads the brief and nothing else.
- **The succession rail is real but 3 days old and one variant is unproven.** 14/14 recycles engaged;
  goal + DoD both survive; `--recycle --worktree` has never run for real.
- **Teammates raise the lead's peak context 1.6× versus dispatched sessions** (458 K vs 289 K median
  peak) — so for a multi-day lead, teammates belong *inside* a dispatched wave session, not on the
  standing lead. That is what READINESS actually did, and all three of its wave sessions ended below
  31 % of the window.
