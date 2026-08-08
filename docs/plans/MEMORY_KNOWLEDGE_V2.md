---
status: in-progress
---

# MEMORY & KNOWLEDGE V2 — ground-up rebuild of map row 9

**Scope (frozen):** durable knowledge earned in one session is still READABLE by the next one —
persisted under the anti-capture rules, and reachable within whatever budget the reader actually
loads. Measured, landed, and verified by disk-truth acceptance reads.

**Methodology:** the `ground-up` skill. Exemplars read before designing: `LAND_PIPELINE_V2.md`
(row 1), `SESSION_LIFECYCLE_V2.md` (row 2 — cell falsification done right), `OPERATOR_SURFACE_V2.md`
(row 10 — the alarm-polarity learning, which turned out to be load-bearing here in a sharper form).

**Row 9 standing-constraint cell — RENAMED, not confirmed.** The map cell read *"anti-capture
hygiene; index at read-size limit"*. Both halves are wrong in an instructive way, and the rename is
§2. Six of the eight closed rows on this campaign renamed or killed their cell; this is the seventh.

---

## Phase 0 — orchestration

**Execution locus — attempt #1 (design): L, lead-inline.** Justification: the deliverable was one
design document; there was no implementation wave to dispatch.
**Execution locus — attempt #2 (build, 2026-08-08): L, lead-inline.** Justification: after
reconciliation the remaining build was three files, none shared, totalling ~120 LOC of change; the
brief needed to dispatch it would have been longer than the diff. Read-only research WAS fanned out
(3 concurrent subagents: out-of-band commit reconciliation, cap-constant census, harvest
measurement). Lead context budget: ≤60% at close; succession point = after §7 lands, since
everything of value is then on disk and in commits.

Single-owner build. No teammates: every deliverable below is ≤120 LOC and four of the six touch the
SAME two files (`hooks/memory-nudge.sh`, `commands/compact-memory.md`), so worktree-isolated
teammates would serialise on a shared file and buy nothing — the agent-teams rule exists to
parallelise *disjoint* file ownership, which this row does not have. Phase-1 research WAS fanned out
(4 concurrent read-only subagents: mechanism registration, read-budget denominator, branch graveyard,
anti-capture compliance).

| Build | Files owned | Depends on |
|---|---|---|
| M1 budget oracle | `hooks/lib/memory-budget.sh` (new), `bin/cc-mem-budget` (new) | — |
| M2 nudge → state-driven, 100% reach | `hooks/memory-nudge.sh` | M1 |
| M3 recalibrate the remedy | `commands/compact-memory.md` | M1 |
| M4 harvest field-collapse fix | `hooks/harvest-skill-end.sh` | — |
| M5 anti-capture ruleset correction | `.claude/CLAUDE.md` + live `~/.claude/CLAUDE.md` | Phase 1(a) |
| M6 map row 9 update | `docs/plans/GROUND_UP_REBUILD_MAP.md` | all |

---

## 1. Measured constants (every one derived this session from primary disk truth)

Nothing in this table is quoted from a prior doc, a memory entry, or the payload. Where a
handed-down number existed I re-derived it and say so.

### 1.1 The read budget — the row's central denominator

Established by **controlled experiment**, not by reading the binary and not by inheriting the
"~24.4KB" that both closed backlog items name. Method: a throwaway memory store at a fake project
slug (`-private-tmp-memprobe-row9`, created 01:31, never any real project's store), a 4001-line
index whose every bullet carries a unique `LINEnnnnn` marker, read back by a headless
`--print` session on **2.1.219 — the same binary this session runs** (`ps -o command=` on the parent:
`~/.claude-219/node_modules/.bin/claude`). The marker makes the delivered prefix self-identifying.

| Probe | bytes/line | lines authored | bullets DELIVERED | delivered bytes | which cap bound |
|---|---|---|---|---|---|
| A | 66 | 4001 | **199** | ~13,155 | LINE cap |
| B | 273 | 4001 | **91** | ~24,869 | BYTE cap |
| C | 200 | 4001 | **124** | ~24,817 | BYTE cap |

- **C1 — BYTE CAP = 25,000 bytes.** Probe B brackets it to `[24,869, 25,142)`; probe C to
  `[24,817, 25,017)`. **Intersection `[24,869, 25,017)`** contains exactly one round constant.
- **C2 — LINE CAP = 200 lines** (heading + 199 bullets). Probe A delivered 199 bullets at only
  13.2 KB — half the byte cap — so a second, independent cap bound there.
- **C3 — the caps compose as `min()`**: whichever binds first. A single-cap model cannot explain
  199 vs 91 vs 124.
- **C4 — a truncation WARNING exists and is delivered TO THE MODEL, verbatim:**
  `WARNING: MEMORY.md is 4001 lines and 781.3KB. Only part of it was loaded. Keep index entries to
  one line under ~200 chars; move detail into topic files.` It is invisible to the operator and to
  every mechanism in this repo, but it is **not** invisible to the reader. Any design that claims
  "silent truncation" without this qualifier is wrong.

### 1.2 The live index against those caps

| # | Constant | Value | Source |
|---|---|---|---|
| C5 | live `MEMORY.md` | **22,473 B / 118 lines** | `wc` on `~/.claude/projects/-Users-chrisren-Development-claude-infrastructure/memory/MEMORY.md` |
| C6 | mean index line | **190 B** | C5 |
| C7 | fill vs byte cap | **89.9%** — headroom 2,527 B ≈ **13 entries** | C5 ÷ C1 |
| C8 | fill vs line cap | **59.0%** — headroom 82 lines | C5 ÷ C2 |
| C9 | **which cap binds** | **BYTES**, by a wide margin | C7 > C8 |
| C10 | entries the byte cap admits at 190 B | **131** | C1 ÷ C6 |
| C11 | entries `/compact-memory` waits for | **200** | `commands/compact-memory.md:3` |
| C12 | **silent-drop window** | **69 entries = 34% of the index** | C11 − C10 |
| C13 | `/compact-memory`'s stated byte trigger | `~46KB` = **1.84× the real cap** | `commands/compact-memory.md:3` vs C1 |

**C14 — the index is NOT truncating right now, and the payload's claim that it is, is falsified.**
Verified first-person and independently of the probes: the last line of the file on disk (line 118,
`Positive-control the DENOMINATOR`) is byte-identical to the last line of the memory block injected
into *this* session's context. At 89.9% there is no truncation. The condition is *imminent*, not
*active* — a distinction the two closed backlog items never drew.

**C15 — the store is ONE physical store behind four symlinked layers.**
`~/.claude-{secondary,tertiary,quaternary}/projects/<slug>/memory` are symlinks to
`~/.claude/projects/<slug>/memory` (same inode, verified 322555093). There is no divergence risk
between layers and no mirror to keep in sync — a hazard the payload's "many memory stores" warning
implies but which does not exist for the index itself.

### 1.3 The write side — reach of the only live mechanism

Population: **175 sessions holding a live `nudge-*.count`**, window Jul 28 04:30 → Jul 30 01:21
(~45 h; the hook self-prunes counters at `-mtime +1`). Work proxy: transcript bytes.

| # | Constant | Value |
|---|---|---|
| C16 | sessions submitting **exactly one** prompt | **114 / 175 = 65.1%** |
| C17 | median prompts per session | **1** |
| C18 | sessions ever reaching the fire condition (`count % 12 == 0`) | **12 / 175 = 6.9%** |
| C19 | **sessions the nudge NEVER reaches** | **163 / 175 = 93.1%** |
| C20 | share of all transcript bytes held by the unreached | **294 MB / 372 MB = 79.1%** |
| C21 | total nudges emitted across the whole window | **20** |

**Denominator controlled** (row 13's trap, and the `positive-control-the-denominator` memory):
0 of 175 counter sessions are sidechains/subagents, and the classifier is **not vacuous** — the
`isSidechain` key is present and parsed (`false`) in every transcript sampled, so it could have
fired. **C18 is an UPPER BOUND on reach**: only 175 of 376 in-window transcripts carry a counter at
all, so every uninstrumented session can only lower it.

**C22 — the unreached class is the knowledge-producing class.** The largest unreached sessions, by
first user message: `<teammate-message teammate_id="team-lead">` (33.9 MB, 18.5 MB, 14.9 MB), fired
handoff payloads (`TASK — …`, `[locate] …`; 20.5 MB, 12.5 MB), and slash-command sessions (`/goal`,
23.8 MB). Median session size *rises* monotonically with prompt count (566 KB → 1,455 KB →
4,337 KB), so the unreached are individually smaller — but there are 13.6× as many of them, and they
are the autonomous long-horizon sessions this campaign runs on. **This very session is `count=1`.**

### 1.4 The harvest path

| # | Constant | Value | Source |
|---|---|---|---|
| C23 | gate-passing sessions in the index DB | **855** | `sessions WHERE message_count>=12 AND commands_run<>''` |
| C24 | candidate rows ever logged | **11**, last **2026-07-26** | `~/.claude/skills-pending/_candidates.jsonl` |
| C25 | rows whose `commands_run` contains a `\|` | **794 / 855 = 92.9%** | sqlite count |
| C26 | **skills ever drafted** | **0** | `find ~/.claude/skills-pending -name SKILL.md` |
| C27 | positive control for C26 | **33** `SKILL.md` in `~/.claude/skills` | same finder, different dir |
| C28 | `/evolve-skill` fixture sets | **0** under `~/.reso/evolve` | its own stated precondition |

**C25 is a live parse bug, not a statistic.** `hooks/harvest-skill-end.sh:29` asks sqlite for
`message_count || '|' || commands_run || '|' || files_changed` and then splits it with
`cut -d'|' -f1/-f2/-f3`. `commands_run` is raw shell text — the probed row contains **127** pipe
characters. So `-f2` is a fragment of the first command and `-f3` is the *next* fragment, never the
file list. The corruption is visible in the stored data: `_candidates.jsonl` line 1 has
`"files_changed":" head -30 && echo \"=== worktrees ===\" …"` where the true column holds
`/Users/…/ship.md /Users/…/LIGHTDARK_S4_…md`. Same failure class as
`docs/research/TSV_FIELD_COLLAPSE_2026-07-25.md`, at a call site that research never reached.

---

## 2. The standing-constraint cell — RENAMED

> **Old cell:** "anti-capture hygiene; index at read-size limit"

Both halves fail, for opposite reasons.

**"Index at read-size limit" is a SIZE fact, and size is not the binding failure.** The index sits at
89.9% and has been manually reclaimed at least twice (backlog `f71311d9ad79`, `b0d889846885`, both
`done`). A size fact would be closed by a bigger budget or a smaller index; neither has held, and
both items reopened in a different guise. **What actually binds is a UNIT MISMATCH between two
independently-set numbers:** the reader truncates on **bytes** (25,000); every mechanism that watches
the index watches **lines** (200) — and the one byte number anybody wrote down (`~46KB`) is **1.84×**
the real cap. The remedy therefore reports "half full" (59% of lines) at the exact moment the reader
is at 89.9% of what it will actually load. That is not a threshold that needs raising; it is a
**dial pointing at the wrong quantity**.

**"Anti-capture hygiene" is not the binding constraint either** — see §2.1 once the compliance sample
lands; the write-side defect this session measured is not *what* gets written but *who gets told to
write at all* (C19: 93.1% never asked).

> **RENAMED CELL:** *"the index is a fixed 25,000-byte buffer that silently drops its tail, and
> nothing in the system measures it in the unit that truncates — so the writer's trigger, the
> reader's budget, and the operator's alarm are three numbers set independently, in two different
> units, none of which is the one that binds."*

### 2.1 The inversion

Row 10's ratified learning — *an alarm that always fires and an alarm that cannot fire carry the same
zero bits* — reappears here in **both** polarities at once, which is why the row resisted:

- `hooks/memory-nudge.sh` **always fires** for the 6.9% (every 12th prompt, unconditionally, with a
  fixed string) and **cannot fire** for the 93.1%. Same hook, both failure poles, and its emitted
  string delegates the one measurement that matters — *"If MEMORY.md is past its load warning"* — to
  the model's judgement, having never looked at the file.
- The remedy `/compact-memory` **cannot fire** on the binding condition: its trigger is in the
  non-binding unit and its byte figure is 1.84× too large.

**The structural change: stop treating the index as a document with a size warning, and start
treating it as a BUDGET WITH A LIVE BALANCE that exactly one component computes.** Every surface
reads that balance instead of re-deriving it or hardcoding a number. The write side learns the
balance *before* it writes; the read side can prove whether it was short-changed. If the new design
were the old one with `46KB` changed to `25000`, this section would be a failure — it is not: the
change is that a **measurement exists at all**, in the unit that truncates, with **one** producer.

---

## 3. Failure-mode table

Every mode observed this session, each with the structural answer that dissolves it. A mode without
an answer is an unfinished design.

| # | Observed failure mode | Evidence | Structural answer |
|---|---|---|---|
| F1 | Index tail dropped at load with nothing in the repo measuring it | C1, C4; repo-wide grep for the cap as symbol or number finds only prose | **M1** budget oracle: one implementation of caps + fill + which-binds, in bytes |
| F2 | Remedy calibrated in the wrong unit and 1.84× off | C11, C13 | **M3** recalibrate `/compact-memory` to C1 in bytes, sourcing the number from M1, never restating it |
| F3 | Nudge unreachable for 93.1% of sessions holding 79.1% of the work | C18–C22 | **M2** fire on STATE (budget fill), not on a prompt counter, on an event with 100% reach |
| F4 | Nudge emits a fixed string and never reads its subject | `hooks/memory-nudge.sh:36-43` | **M2** emit the measured balance; no advice the hook has not verified |
| F5 | Truncation invisible to operator and to every mechanism | C4 (model-only warning) | **M1** exposes it as a readable verdict + exit code a board can consume (row 10 owns the board itself — §6) |
| F6 | Harvest candidate records 92.9% corrupt | C25, `_candidates.jsonl` line 1 | **M4** stop delimiter-joining; per-column extraction |
| F7 | Harvest yields 0 skills in 55 days | C24, C26 vs C27 | **M4** surfaces the backlog count; drafting stays human-gated *by policy*, so this is reported, not automated — see §4 R3 |
| F8 | `/evolve-skill` inert by its own precondition | C28 | Documented as inert-by-design (a SPIKE); no build — see §4 R4 |
| F9 | Two backlog items closed for one recurring condition | `f71311d9ad79`, `b0d889846885` both `done` | Dissolved by F1+F2: the condition regenerates because nothing measures it; once measured it is a state, not an incident |
| F10 | Row 9's own map cell cites a CLOSED item as the reason it is open | map row 9 | **M6** corrects the cell |

---

## 4. Rejected alternatives

**R1 — Raise the budget / shrink the index on a schedule.** Rejected: this is what happened twice
already (both backlog items `done`, condition recurring within the hour per the payload). A
one-time reclaim against an unmeasured cap is the whack-a-mole signature memory
`desk-whack-a-mole-means-file-systemic-fix` names. It also cannot work: C1 is imposed by the harness
and is not ours to raise.

**R2 — Autonomous compaction (let a hook trim the index when it is full).** Rejected on the hazard
that governs this whole row: the store is **untracked by any repository** — `git ls-tree -r
origin/main` matches zero paths under any `memory/` directory (positive control:
`commands/compact-memory.md` does match, so the selector works). There is no undo. Memory
`append-only-store-safety-rules` records 1,461 lines destroyed once by exactly this class of
automation. Measurement is safe; automated mutation of an unbacked store is not. **Every mechanism
in this plan is read-only against the store.**

**R3 — Autonomously draft skills to close F7.** Rejected: both `commands/harvest-skill.md` and
`hooks/harvest-skill-end.sh` state in their own headers that the autonomous fork is deliberately
out of scope ("minus the autonomous write … the synthesis stays human-gated"). Overriding a
documented policy decision is not a ground-up rebuild's call. F7 is answered by making the backlog
*visible and uncorrupted*, not by writing skills unattended.

**R4 — Rebuild `/evolve-skill`.** Rejected: it is labelled a SPIKE, has never run, and its
precondition (a fixture set) has never been authored. Rebuilding an unused spike spends the row's
budget on the least-evidenced surface. Recorded as inert-by-design.

**R5 — Put the alarm on the `cc-blockers` board myself.** Rejected as a **seam violation**: the
rulings register assigns `bin/cc-blockers` *alarm predicates* to row 10. M1 therefore ships the
measurement with a parseable verdict token and a documented exit-code contract so row 10 can consume
it; the board row is row 10's to add. Named as a remainder in §6, not built here.

**R6 — Fix `claude-search` / the session index reader.** Out of scope by the payload's binding scope
bound: `~/.claude/bin/claude-search` symlinks into `~/Development/claude-session-search`, a different
repository this campaign's `/ship` cannot land to. **Correction to the payload, though:** the session
index *producer* IS in this repo and IS landable — `hooks/session-index-{start,end,sweep}.sh`,
`hooks/lib/session-index-helpers.sh`, two launchd plists and two bats suites are all on `origin/main`.
Only the reader CLI is foreign. No producer change is needed for this row's DoD; recorded so the next
row does not re-inherit the stronger claim.

**R7 — Move the nudge to `SessionEnd`.** Rejected: `SessionEnd` fires when the session's context is
already gone, so an advisory there reaches nothing that can act on it. `UserPromptSubmit` and
`SessionStart` are the two events whose `additionalContext` reaches a live model; only `SessionStart`
has 100% reach (C19).

---

## 5. Acceptance criteria — as disk-truth reads

Each is a command whose output decides it. No criterion is satisfied by narration.

| AC | Claim | The read that proves it |
|---|---|---|
| AC1 | The caps exist as a **symbol**, not prose, with exactly one producer | `grep -rn 'MEM_INDEX_BYTE_CAP\|MEM_INDEX_LINE_CAP' hooks/ bin/ commands/` returns the lib definition + consumers, and **no** second literal `25000` |
| AC2 | The oracle reports the live balance in the binding unit | `bin/cc-mem-budget --json` emits `bytes`, `byte_cap`, `pct`, `binds`, `headroom_entries` |
| AC3 | The verdict is machine-consumable and fail-soft | `bin/cc-mem-budget; echo $?` → documented codes; with the store absent it exits the "unknown" code, never a false OK |
| AC4 | The nudge reaches a `count==1` session | run the hook with `{"session_id":"…"}` once; stdout contains the budget line (today: silent until prompt 12) |
| AC5 | The nudge reports a measured number, not advice | its `additionalContext` contains the live byte figure and `%` from M1 |
| AC6 | `/compact-memory`'s trigger is in bytes at C1 | `grep -n '25000\|25,000' commands/compact-memory.md` matches; `grep -c '46KB' ` → 0 |
| AC7 | Harvest records carry a real file list | a fresh `_candidates.jsonl` row's `files_changed` starts with `/` and contains no ` && ` |
| AC8 | Every new mechanism has an env kill switch | `grep -n 'CC_MEM_BUDGET' hooks/memory-nudge.sh hooks/lib/memory-budget.sh` |
| AC9 | Nothing this row ships writes to the store | `grep -nE '>|>>|rm |mv |truncate' hooks/lib/memory-budget.sh bin/cc-mem-budget` shows no write to a `memory/` path |
| AC10 | Map row 9 states status, plan link, landed shas, and drops the closed-item citation | `grep -n 'b0d889846885' docs/plans/GROUND_UP_REBUILD_MAP.md` → 0 |

---

## 6. Remainders (named, with owners)

- **R-1 (row 10):** a `cc-blockers` row keyed on `cc-mem-budget`'s verdict, so an over-cap index
  reaches the operator. Predicate ownership is row 10's per the rulings register. M1 ships the
  producer + exit-code contract; the board row is not built here.
- **R-2 (operator, C10-class):** remove the throwaway probe store this session created —
  `rm -rf /private/tmp/memprobe-row9 ~/.claude/projects/-private-tmp-memprobe-row9
  ~/.claude-quaternary/projects/-private-tmp-memprobe-row9`. `rm` is permission-guarded for agents
  here. It is a fake project slug created 01:31 for the cap experiment; it holds no real memory.
- **R-3 (row 3 / comms):** `bin/cc-await-ping` cannot watch a PANE key — it resolves the uuid as a
  session id, finds the registry pid dead, and exits **5** (`the session that armed me is GONE`).
  The coordinator's "arm both keys" instruction is unexecutable with this actuator.
- **R-4 (`claude-session-search` repo):** nothing required by this row, recorded so R6's correction
  is not lost.

---

## 7. Attempt #2 — reconciliation, not rebuild (2026-08-08)

§§1-6 above are attempt #1's design and stay as written. This section records what happened to it.
**The build never ran, and between 2026-07-31 and 2026-08-06 non-campaign sessions shipped most of
it by a different and better route.** The map cell's instruction — *"attempt #2 must RECONCILE, not
rebuild; building `cc-mem-budget` as specced would duplicate a shipped chokepoint gate"* — is
correct, and this attempt obeyed it: **not one line of M1 was built.**

### 7.1 Method note — the first read falsified the second

The dispatch worktree was **800 commits behind `origin/main`**, and `git rev-list --count
origin/main..HEAD` read **0** — because HEAD was an *ancestor*, which that count cannot distinguish
from *equal*. Read that way, every M1 artifact was correctly absent and the row looked untouched.
The falsifier was content, not count: the checkout's live `hooks/memory-nudge.sh` is 10,231 B where
this worktree held the 2,103 B original. This is the repo's own standing rule — *verify by CONTENT,
never by count* — biting on the read that decides whether to build at all.

### 7.2 What actually shipped, against §3's failure modes

| Mode | §3 answer (planned) | What shipped instead | Verdict |
|---|---|---|---|
| F1 | M1 oracle in `bin/cc-mem-budget` | `hooks/lib/memory-index-budget.sh` + `hooks/memory-nudge.sh:81-134` measure live, in bytes | **MET, different shape** |
| F2 | M3 recalibrate the remedy | body of `commands/compact-memory.md` moved to 24,985 B; **frontmatter had not** | **MET this attempt** — `3f3600b4` |
| F3 | M2 fire on state, 100% reach | `memory-nudge.sh:139-145` — over-limit fires at `COUNT==1`; healthy stays periodic | **MET for the alarm** |
| F4 | M2 emit the measured balance | the whole advisory is now computed; nothing fixed remains | **MET** |
| F5 | M1 exposes a consumable verdict | `mib_verdict` — a PreToolUse **refusal**, stronger than a verdict | **EXCEEDED** |
| F6 | M4 per-column extraction | nothing — still `\|`-joined and `cut`-split on trunk | **STILL-OPEN → fixed `25e897fd`** |
| F7 | M4 surfaces the backlog | unchanged; still 0 skills drafted | reported, human-gated by R3 |
| F8 | `/evolve-skill` inert by design | unchanged | inert-by-design, no build |
| F9 | one condition, many items | the nudge now hands over the **condition-keyed** filing form | **MET** |
| F10 | M6 corrects the cell | coordinator did it 2026-08-07 | **MET** |

### 7.3 Acceptance criteria — final disposition

| AC | Verdict | Evidence |
|---|---|---|
| AC1 | **SUPERSEDED** | the symbol is `MEMORY_INDEX_LIMIT`, not `MEM_INDEX_BYTE_CAP`; `hooks/lib/memory-index-budget.sh:104`, `hooks/memory-nudge.sh:78` |
| AC2 | **SUPERSEDED** | no `--json` CLI; the balance is emitted as `additionalContext` by the hook that already runs |
| AC3 | **SUPERSEDED** | the contract is a PreToolUse **deny**, not an exit code; fail-open on every unknown, pinned by 23 tests |
| AC4 | **MET** | ran the hook once at `COUNT==1` against the live store — the alarm is the first thing it prints |
| AC5 | **MET, then sharpened** | it reported a *measured* number that was an *averaged* one; now exact — `1f828fcc` |
| AC6 | **MET this attempt** | `3f3600b4`. Spelling is **24,985**, not AC6's literal `25000` — the shipped mechanisms' number wins over a superseded doc's |
| AC7 | **MET this attempt** | `25e897fd`; proven on a live corrupted row |
| AC8 | **MET** | `MEMORY_INDEX_LIMIT`; `MEMORY_NUDGE_INTERVAL=0` is a total kill switch (test 14) |
| AC9 | **MET** | both mechanisms are read-only against the store; the gate only ever *refuses* |
| AC10 | **MET** | coordinator, 2026-08-07 |

### 7.4 Constants re-derived this session — the cap is not a constant

Every figure below is first-person on **binary 2.1.220** (`ps -o command= -p $PPID` →
`~/.claude-220/…`). Attempt #1 probed **2.1.219**. Re-derived rather than quoted, because
§1's own numbers had decayed.

| # | Constant | Value | How |
|---|---|---|---|
| C29 | live index | **26,415 B / 113 lines / 105 entries** | `wc` (C5 read 22,473 B) |
| C30 | **delivered prefix, this session** | **25,791 B** (through entry 103) | last delivered line vs the file |
| C31 | first entry NOT delivered | entry 104 → would make **26,098 B** | — |
| C32 | **live cap bracket** | **[25,791, 26,098)** | C30/C31 |
| C33 | **C1's bracket does NOT intersect it** | C1 `[24,869, 25,017)` vs C32 | the cap **moved between binary versions** |
| C34 | the tail actually dropped | **exactly 2 entries** | named below |
| C35 | what the alarm claimed | **6** (averaged) → **4** (exact, at the hardcoded limit) → truth **2** | `1f828fcc` closes the first gap |
| C36 | producers of the `24985` default | **2**, agreeing | `memory-nudge.sh:78`, `memory-index-budget.sh:104` |
| C37 | C15 re-verified | one inode **407890046** across `~/.claude` and `~/.claude-tertiary` | `stat -f %i` |

**C34 named, because "silently dropped" should never be an abstraction:** this session did not load
`capture-based-probe-cannot-exercise-a-tty-gated-verb.md` or
`guard-universalization-deletes-a-capability-silently.md`. Both are on disk; neither is in context.
That is the row's whole thesis, observed rather than argued.

**C33 is the finding that outlives this row.** The hook's header states *"Every figure is computed at
runtime: a hardcoded one decays against its subject"* — and `LIMIT=24985` is the one hardcoded figure
in the mechanism, now measurably **~800 B low** on the running binary. The error is in the **safe**
direction (it alarms early, and it refuses writes early), so it was left at 24,985 rather than
re-pinned: re-pinning is R1's whack-a-mole, and it would decay again at 2.1.221. What changed instead
is that **drift can no longer be silent** — `1f828fcc` fails when the two literals diverge or a third
appears — and that the derived figure the operator acts on no longer compounds the constant's error
with an averaging error.

### 7.5 Rejected this attempt

**R8 — Re-pin `LIMIT` to the measured 25,791.** Rejected: n=1 against attempt #1's controlled n=3,
the current value errs safe, and a number re-pinned per binary version is the decay this row exists
to end. Recorded as C33 with the method to re-derive instead.

**R9 — Have the hook read the loader's own self-reported limit.** The loader *does* state its limit
in the reader's own unit (C4: `WARNING: MEMORY.md is 24.8KB (limit: 24.4KB)`), which would make the
constant measured rather than assumed. **Rejected because it is not buildable: that string is
delivered only into the model's context and is persisted nowhere a hook can read.** Verified, not
assumed — across this session's 306 KB transcript, hits for `Only part of it was loaded`, for the
index's own first entry, and for the hook's own `additionalContext` are **0, 0 and 0**. Worth
recording precisely because it is the obviously-right design and it is unavailable.

**R10 — Single-source the limit into the lib.** Rejected: `memory-nudge.sh` would gain a source
dependency that, when unresolvable, fails open *silently* and reads as landed while inert — the trap
`tests/memory-index-budget.bats:259` already pins for the gate. Two literals plus a test that fails
on drift buys the same guarantee with no new runtime failure mode.

### 7.6 Landed this attempt

| sha | What |
|---|---|
| `25e897fd` | harvest field collapse — per-column extraction, `.timeout`, `SESSION_INDEX_DB`; 11 new tests |
| `1f828fcc` | exact dropped-entry count (was averaged); limit-drift guard; 20/20 |
| `3f3600b4` | `/compact-memory` trigger recalibrated to the binding unit |

### 7.7 Why the row does not close on its headline metric

The mechanisms are done; **the index is still over the limit and two entries are still unreadable**
(C34). That is deliberate and not a loose end of this attempt: R2 forbids automated mutation of a
store **no repository tracks**, and the lossy half of the remedy is PROPOSE-ONLY by policy, so
closing the gap is a human-gated act. It is already filed as the standing condition
`memory-index-over-budget` (open: `150c50055e1c`, `7e2df754d0b8`; blocked: `6267e2e3c707`,
`7021e89884df`) — and roughly twenty rows exist for this one condition, which is the re-minting the
nudge's filing form now exists to stop. **No new item was filed for it here.**

### 7.8 Remainders — updated

- **R-1 (row 10)** — unchanged in ownership, but the producer it needs now exists as a PreToolUse
  refusal rather than an exit code. A board row keyed on the live index size is still row 10's.
- **R-2 (operator)** — the throwaway probe store from attempt #1 is **gone**; nothing to remove.
- **R-5 (new, whoever next touches the loader)** — C33: the cap moved between 2.1.219 and 2.1.220.
  Re-derive with the C30/C31 method (compare the last delivered index line against the file) before
  trusting `24985`; it is a floor, not a measurement.
