# C6: a machine-readable disposition marker on research recommendations (the doc side)

Round 2, 2026-10-18. Candidate C6 from axis 04 §4, axis 05 P2 and axis 10 §4 (and their skeptic
verdicts). Read-only in the repo: the only repo write is this file. Prototypes, copies and scratch
output live under `/tmp/r2-C6/`. Every number is labelled **[M]** (measured, with the command) or
**[E]** (estimated, with the method). Line numbers are from the worktree at `f12dd4b12`; for every
file this design touches, `git diff HEAD origin/main` is empty except `CLAUDE.global.slim.md`
(1 line), so they hold on trunk too [M: `git diff --stat HEAD origin/main -- <files>`].

Status: complete (written incrementally; §6 has the test results, §8 the verdict, Appendix A the prototype).

## 0. Setup facts

- Load during this pass: one-minute average 103-132 at 20:06 CDT, rising to 290-570 between 20:30 and 21:50 [M: `uptime`, sampled with every timing run].
- The incident's synthesis doc, `docs/research/startup-hooks-2026-10-18/README.md`, was written by
  workflow agent `agent-a2bfc6f1444ab842c` (meta `description: "synthesize"`, phase `Synthesize`)
  and amended by `agent-a6f0ebc90467839e7` (`amend`, phase `Close gaps`) under
  `~/.claude-secondary/projects/-Users-chrisren-Development--worktrees-wt-cc-004752-67086/5759497b-…/subagents/workflows/wf_7c1e0d3e-19e/`
  [M: `cat agent-*.meta.json`].

## 1. The key question first: does an opt-in convention catch anything?

**Not through the skills or templates.** The incident never passed through them, and neither do most
research syntheses.

- **The incident session loaded no research skill.** The only mentions of `research-subagents` in
  either half of its transcript are skill-listing text. It made no `Skill` call for it, and there is
  no `/research` command record [M: `jq` over the `tool_use` records of the quaternary
  `.jsonl.handed-off` and the secondary `.jsonl`, plus `grep -o '.{150}research-subagents.{100}'`].
- **The synthesis contract was written inline by the lead**, in the workflow script
  `…/5759497b-…/workflows/scripts/startup-hooks-research-wf_7c1e0d3e-19e.js:157-173`:
  `## PRODUCE ${OUT}/README.md … 5. **Implementation waves** — ordered, each a self-contained unit …`.
  Neither `skills/research-subagents/SKILL.md` (982 lines) nor `commands/research.md` (105 lines)
  says anything about how the synthesis doc is structured. Both govern the worker briefs
  [M: `grep -n -i -E 'synth|README|wave|recommend|implement|status' …`].
- **Fleet census, 14 days.** I scanned 9,681 transcripts (8,071 of them subagent files, 13.5 GB) for
  `Write`, `Edit` and `MultiEdit` calls on `docs/(research|plans)/**.md`
  [M: `/tmp/r2-C6/scan_writes.sh` (rg) → `writes14.txt`, 1,985 records; aggregated by
  `py/agg.py` and `py/loaded.py`]:
  - 54 sessions wrote a research synthesis doc (`docs/research/<dir>/{README,REPORT,SYNTHESIS,DESIGN}.md`).
  - **5-7 of the 54 (9-13%) loaded `research-subagents` or `research-program` in any form**: a Skill
    call, a launch text, or a Read of the SKILL.md. 0 used the `/research` command.
  - **33 of the 54 (61%) used the Workflow tool.** There the synthesis prompt is whatever the lead
    wrote into the script.

  So a convention placed in the skill, the command or a template reaches **at most 13%** of
  synthesis writers [M], and **0%** of the incident.
- **Two channels do reach every synthesis writer** with no resident budget:
  - **The close itself.** The ledger runs at every Stop.
  - **PostToolUse on Write|Edit|MultiEdit**, which already runs inside workflow agents. In
    workflow-agent transcripts modified in the last 3 days there are 518 `PostToolUse:Write` and
    117 `PostToolUse:Edit` hook records across 115 files. The hook's `additionalContext` is rendered
    to the agent as a `<system-reminder>`. One example is
    `wf_e5c966e2-643/agent-a47ee34a2a4a5eae2.jsonl`: post-file-edit.sh's "PostToolUse hook modified
    … after your edit" reminder [M: `xargs grep -l '"hookEvent":"PostToolUse"'` over the 2,377
    workflow-agent files with mtime < 3 d, then `jq` over one of them]. This answers the "70%:
    a write-time lint fires inside Dynamic-Workflow agents. Not measured" line in axis 10 §7.
    PostToolUse hooks do run there, and their context reaches the agent.

**Consequence for the design.** A convention that only *counts* marked rows is opt-in, so it would
have been silent on the incident (§3.1). To catch anything it needs a **presence duty** that does
not depend on any template, and that duty must be exact, not heuristic: *a synthesis doc this
session added must carry a drive-state declaration.* The whole design below turns on that one
step from "count the markers" to "an added synthesis doc with no marker is itself the loose end".
The question it raises is whether a presence duty is quiet enough. §3 and §4 measure that.

## 2. The design: an exact convention, a presence duty, and ownership by "wrote ∧ added since start"

### 2.1 The convention (parsed by `scripts/lib/drive-state.awk`; the prototype is at `/tmp/r2-C6/mut/scripts/lib/drive-state.awk`)

A doc declares its drive state in one of two ways:

- **A table column.** A GFM table whose header has a cell reading exactly `Drive state`
  (case-insensitive, `**` stripped) holds one token per body row.
- **A doc line.** A column-0 line `Drive state: <token>[ — note]` is the doc's default. It fills
  empty cells, and it is the whole declaration when the doc has no Drive state table. One line is
  enough for the common case: fire one implementing session for the whole doc, then write
  `Drive state: fired startup-hooks-impl`.

Tokens. The first word decides, and anything else is OPEN, so a typo cannot clear a row:

| Token | Meaning | Verified against (one batch read per store) |
|---|---|---|
| `to drive` | open; the default when a synthesis is written | always OPEN |
| `driven <sha>` | committed | `git cat-file --batch-check '<sha>^{commit}'`: the object exists. **Not** ancestry of trunk: ship-land's rebase re-mints shas (axis 10 skeptic F1.2), and landedness is `UNLANDED`'s question |
| `fired <slug>` | a dispatched session owns it | slug (or `fire-<slug>`) in `cc-custody list --json`. The existing custody arm keeps 🔧 until it returns |
| `filed <id>` / `operator <id>` / `parked <id>` | a backlog row: agent work / operator step / a park with a falsifier | the 12-hex id is present in `$CC_BACKLOG_FILE`. FILED_MINE and 👤 then judge the row itself |
| `decision <id>` | a class-C packet | `$CC_DECISIONS_DIR/<id>.json` exists. ⛔ governs it |
| `dropped: <why>` | not doing it (at least 2 words of reason) | counted in `DRIVE_DROPPED` and named. Not OPEN, **except** on a row the doc's own `Conv.` cell ranks ≥ 90 |
| `none` | doc line only: the doc recommends nothing | OPEN if the doc has any table with a `Conv.`/`Conviction`/`Confidence` column |

**The single content check reads the doc's own structure, not its prose.** A row the doc itself
ranks at 90 or above cannot be `dropped`, because the resident rule is "every item at 90%+
conviction driven" (`CLAUDE.rules.slim.10-session-close.md:189`). A doc that has a ranked table
cannot declare `none`. Fenced code blocks are skipped, so a doc that quotes the convention (like
this one) is not declared by the quote.

### 2.2 Ownership: the session wrote the doc, and a commit made since the session began added it

> owner(doc) ⇔ `session_writes_paths(tp)` lists it (the existing SSOT oracle: main transcript plus
> every `subagents/**/*.jsonl`, Write|Edit|MultiEdit|NotebookEdit)
> ∧ a commit this worktree made or picked **since the session's first stamped record** added it.

The rule is checked in two layers:

- **Layer 1 (git, cheap, a prefilter only).** Take the reflog's `commit:`, `rebase (pick):`,
  `cherry-pick` and `merge` entries newer than the session start, then
  `git show --diff-filter=A --name-only -- 'docs/*.md'`. When nothing was added, nothing is read
  from the transcript at all.
- **Layer 2 (exact).** The session's own Write or Edit records name the doc.

Why each half is there:

- **It answers axis 05 skeptic P2(c)** ("a typo fix makes the session own every old wave"). A
  session that started after the doc landed never owns it, however much it edits the doc. The
  census shows how much this matters: in 14 days 20 sessions created a synthesis doc, while
  another **34** only edited synthesis docs that already existed. Examples are kitty-crash's README
  (5 sessions) and upfront-research-exhaustion's REPORT (6), mostly status updates by implementing
  sessions [M: `scan_created.sh` → `created14.txt`, 503 creation results; `py/created.py`].
- **It answers axis 10 skeptic F1.3** (reflog ownership is the refuted worktree-implies-mine
  rule). The reflog only narrows the candidates. Layer 2, the session's own records, decides. A
  doc another session landed in the same worktree, which this session never wrote, is not owned
  (test 3).
- **Mentions are not writes.** A Bash result that names the path creates no tool_use (test 5).
- **Why not "created"?** §3.4 measures it. The creation join covers only 50% of landed synthesis
  docs, against 79% for this rule, and 0 of 34 docs had two qualifying sessions.

### 2.3 Scope of the presence duty

- **UNMARKED is exact on path, not on content.** It applies only to research **synthesis** docs the
  session owns: `docs/research/<dir>/{README,REPORT,SYNTHESIS,DESIGN}.md`. Axis and slot
  reports (`docs/research/<dir>/A1-….md`) and deeper paths carry no duty (test 6).
- **Any owned doc under `docs/` that carries a declaration** counts toward `DRIVE_OPEN`, plans
  included. The convention is opt-in there.
- **Plans are left out of the duty on purpose.** They already carry an enforced frontmatter
  `status:` (`hooks/validate-plan-structure.sh`), and 22 were created in 14 days [M]. They are a
  named residual (§7).

## 3. Incident replay (measured, end to end, on copies)

**Set-up.** `/tmp/r2-C6/replay/`:
- A bare origin plus a clone holding the incident README, committed and pushed. This is the
  ✅-eligible path the incident was on.
- A copy of the incident's secondary transcript, **truncated at the close record**: line 643,
  `2026-10-18T14:27:47.478Z`, "✅ Good to close: yes. Nothing of mine is open. Follow-on: …".
- Copies of its 38 workflow-agent files.
- In every copy the worktree path was rewritten to the replay clone (`sed`).
- Every store seam is pointed into the sandbox: `CC_BACKLOG_BIN`, `CC_DECIDE_BIN`,
  `WRAP_LIVE_REPO`, `COMPLETION_STATE_DIR`, `COMPLETION_IDL`, `CC_IDL`, `TMPDIR` and the rest
  (`replay/ledger.sh`, `replay/ca.sh`).
- The live stores are only read: the backlog file, by grep, and `cc-custody list`.

### 3.1 The convention as an opt-in count only (no presence duty)

The incident README carries no `Drive state` table and no `Drive state:` line, so a counting-only
term reads **0 rows and stays silent**. `drive-state.awk` with `synth=0` on
`fx/incident-original.md` prints nothing [M]. **This is the answer to the brief's key question:
opt-in alone catches nothing in the incident**, and the skill/template route reaches at most 13% of
synthesis writers (§1).

### 3.2 With the presence duty (the design)

| Run | RUNG | Key facts | Source |
|---|---|---|---|
| Unmodified ledger (`/tmp/r2-C6/repo`, the control copy) | **✅** | `READOUT=✅ Clean & landed — completeness UNKNOWN …` (the sandbox has no DoD store; the live incident read "Complete & landed", also ✅) | [M] `replay/ledger.sh keep on /tmp/r2-C6/repo/scripts/wrap-ledger.sh` |
| Mutant ledger, `WRAP_DRIVE=off` | ✅ | `DRIVE_SRC=n-a` | [M] `replay/ledger.sh keep off` |
| **Mutant ledger** | **🔧** | `DRIVE_UNMARKED=1`, `DRIVE_DOCS=docs/research/startup-hooks-2026-10-18/README.md (no Drive state declaration)`, `DRIVE_SRC=WRAP_SESSION_ID` | [M] `replay/ledger.sh keep on` |

The creation was found **only through the workflow agent's transcript**:
`agent-a2bfc6f1444ab842c.jsonl`, the `synthesize` agent, Write `toolu_01C5R1rQWUvPk84igNiY93Ys`.
The lead's own transcript has no Write of the README.

**completion-assert, the delivery channel, at the incident's own budget state.** I seeded the latch
file with three `assert` lines. That is the state the real IDL shows at 14:27:50Z,
`capped:3>=3, suppressed_arm: handoff, rung ✅`, after the three 📦 fires at 13:18-13:19Z. I enabled
the D1 handoff arm with a `cc-backlog` stub that returns `[]`, as the live store did for this
session.

| Hook | IDL record | Source |
|---|---|---|
| Unmodified (`/tmp/r2-C6/repo/hooks/completion-assert.sh`) | `abstained · capped:3>=3 · class assert · rung ✅`. **This reproduces the incident's real IDL row** | [M] `CA_CCB=replay/ccb-empty replay/ca.sh <ctl hook> ctl-d1 capped` |
| Unmodified, D1 off (absent backlog) | `abstained · ledger-clean` | [M] `replay/ca.sh <ctl hook> ctl-capped capped` |
| **Mutant** | **`fired · false-done · arm ledger+handoff · class undriven · rung 🔧 · 1/2`**, with the block reason naming `docs/research/startup-hooks-2026-10-18/README.md` | [M] `CA_CCB=… replay/ca.sh <mut hook> mut-d1 capped` |

So on the incident's real transcript, README and budget state, the design turns the silent capped
✅ into a delivered block. The agent's own `wrap-ledger.sh --machine | grep '^READOUT'`, which it
ran at 14:27:32Z in the incident, would have read 🔧.

All three rows were re-run on the final code (21:2x). Mutant: `fired · ledger+handoff ·
undriven 1/2`. Control: `abstained · capped:3>=3 · rung ✅`.

**The bounded sequence, continued on the same replay** [M: same `ca.sh` state dir; a new
assistant record appended each time, so the hash latch does not hide it]:

1. The incident close fires: `undriven 1/2`, UNMARKED.
2. The agent adds the column with every row `to drive` (the `incident-todrive` variant, committed)
   and closes "Good to close: yes …" again. It fires: `undriven 2/2`, arm `ledger`, with 38 rows
   open.
3. A third undriven close is **silent**: `abstained capped:undriven:2>=2`. The rung stays 🔧.

Enforcement is two forced turns, then the READOUT alone.

### 3.3 The convention once applied: fixtures of the incident README

All rows below are from `drive-state.awk` with `synth=1` [M: `fx/*.md`, built by adding a
`Drive state` column to the 38-row §2 table].

| Fixture | Parser output | What it shows |
|---|---|---|
| original | `UNMARKED` | presence duty fires |
| every row `to drive` (what a taught synthesis writes) | 38 × `OPEN to-drive` | the six waves' rows count until driven |
| the 20:05 fix-up the session actually did (one fired session, c10 rows `operator`, conviction < 70 `dropped`) | 14 DROPPED, 6 VERIFY bl, 18 VERIFY slug | `fired fire-startup-hooks-impl` verifies against the live custody store (the slug is there [M: `cc-custody list --json`]) |
| one doc line `Drive state: fired fire-startup-hooks-impl — …` | 1 VERIFY slug | the one-line cure for "fired a session for the whole doc" |
| laundered: every row `dropped: research only` | 37 DROPPED + **1 OPEN `dropped-at-conviction-95`** | #3 (mailbox-drain, 95%) cannot be dropped |
| laundered: `Drive state: none — this pass was research only` | **OPEN `none-over-a-ranked-table`** | the one-line laundering is refused |
| laundered: `Drive state: dropped: this pass was research only` | **OPEN `dropped-at-conviction-95`** | same |
| a probe doc with `Drive state: none` and an unranked table | `OK none` | the honest "recommends nothing" stays silent |

### 3.4 Ownership coverage: why the rule is "wrote ∧ added since start", not "created"

I first built ownership as **creation**: a Write whose own result is `File created successfully at:`,
joined on the id (`session_created_paths`, prototype in `/tmp/r2-C6/mut/hooks/lib/session-writes.sh`).
On the incident it is exact. On the fleet it covers only half the synthesis docs:

- **34** synthesis docs were added to trunk in 14 days. A creation record exists in the local
  transcript corpus for only **17 (50%)** of them [M: `git log origin/main --since='14 days ago'
  --diff-filter=A` vs `created14.txt`; `py/coverage.py`].
- One measured reason is a harness rule. Claude Code 2.1.293 refuses a **subagent's** Write to
  `REPORT*|SUMMARY*|FINDINGS*|ANALYSIS*.md` with "Subagents should return findings as text, not
  write report files" (`tengu_subagent_md_report_blocked`)
  [M: `rg -a` over `~/.claude-293/…/bin/claude.exe`]. A REPORT.md synthesis therefore comes back
  as text and the lead writes it, often through Bash. lr-wake-incident is one case: the workflow
  agent's Write was refused at 18:57:54Z and the lead wrote the file another way, then edited it.
  README.md is not blocked, which is why the incident's README was a Write.
- The other misses: Bash redirects and python writes (6), and no local writing record at all (7)
  [M: `scan_missed.sh` + `py/missed.py`, a rough classifier].

**The rule the prototype now uses:**

> owner(doc) ⇔ `session_writes_paths` (the existing SSOT oracle, subagents included) lists the doc
> ∧ a commit this worktree made or picked since the session's first stamped record **added** it.

The second clause is the git reflog: `commit:` / `rebase (pick):` entries newer than the session
start, then `git show --diff-filter=A`. ship-land's rebase writes the landed sha into the reflog as
`rebase (pick)`. This worktree's reflog shows `b13e43872 commit:` and then `1e7461db7 rebase (pick):`
for the incident README [M: `git reflog --date=iso`].

Measured on the 14-day census:

- Coverage rises to **27 of 34 (79%)**: docs with at least one session that wrote them and started
  before they were added [M: `py/coowners.py`].
- **No doc had two qualifying sessions.** The distribution is 27 docs with exactly one and 7 with
  none [M]. The co-tenant false-ownership case (a second session that started before the add and
  edited the doc) never occurred in 14 days.
- A typo fixer that starts after the doc landed is excluded by construction (test 2, §6).
- It **reuses** `session_writes_paths` instead of adding a second reader, as constraint 6 asks.
  Bash-only creations with no later Edit remain a named residual (7 of 34).

### 3.5 Cost on the ledger (latency-sensitive)

A/B runs of the full mutant ledger on the replay, `WRAP_DRIVE=on` against `off`, alternating, at
load average 300-330 on 10 cores [M: `replay/ledger.sh keep on|off`, `/usr/bin/time -p`]:

| Path | When it runs | Δ real | Δ CPU (user+sys) |
|---|---|---|---|
| any rung other than ✅-eligible | dirty, unlanded, ⛔ | 0: the term is not called (`DRIVE_SRC=skip`, test 16) | 0 |
| ✅-eligible, **no** doc added by this worktree since the session began (most Stops) | git reflog + one `head`/`grep`/`date` | **+0.0 to +0.2 s** (0.42-0.60 s → 0.52-0.71 s) | **+0.03 s** |
| ✅-eligible, a synthesis/declared doc was added (research sessions after landing), **uncached** | + one `session_writes_paths` over main + 38 subagent files (30 MB) | **+0.5 to +0.8 s** (0.47-0.67 s → 1.02-1.50 s) | **+0.43 s** |
| the same **with the per-file (size, mtime) cache** (the design): cold first Stop | | +0.7 s (0.48 → 1.19 s) | +0.48 s |
| the same with the cache, warm (every later Stop; finished agents' files are immutable) | | **+0.28 to +0.41 s** (0.54-0.62 s → 0.90-1.02 s) | **+0.17 to +0.22 s** |

The cache by itself, on the incident transcript set [M: `session_writes_paths` with and without
`SESSION_WRITES_CACHE_DIR`, load 316]:

- uncached: 0.39 s real, 0.31 s CPU;
- cached, cold: 0.42 s real;
- cached, warm: **0.08 s real, 0.04-0.06 s CPU**;
- output byte-identical, 48 paths each (`diff` empty).

The remaining warm delta in the ledger is fork overhead: the child bash, sourcing the lib, the git
reflog and show, and the parser. The cache's first shape was a per-file `stat`/`shasum` loop, and
it measured **slower** than no cache (2.2-2.6 s real at load 300). The fork count matters more than
the bytes. The shape that works uses one `stat`, one `jq` and two `awk` for the whole file set.

At load 525-555 the whole ledger took 2.09-2.47 s on, against 1.35-2.24 s off [M]. That delta is
within the noise at that load.

**Size distribution behind the slow path** [M: `py/sizes.py`, `py/sizes2.py` over the 14-day list]:

- All sessions: per-session transcript bytes (main plus subagents) are p50 0.81 MB, p90 7.5 MB,
  p95 19 MB and p99 148 MB.
- The 20 doc-creating sessions: 2.0-106 MB, median ≈ 11 MB.
- **Estimated** uncached CPU at 0.27 s per 32 MB: under 0.1 s for half of them, 0.43 s for the
  incident's 51 MB (both stores), 0.89 s for the largest (106 MB). The estimate is linear in bytes.

The term runs in a bounded child (`WRAP_DRIVE_TIMEOUT_S`, default 3 s), and a timeout reads
`DRIVE_SRC=error`, count 0 (fail-open; test 17). **Risk:** without the cache, a mega research
session (> ~100 MB) at load 300 could hit the bound on every ✅-eligible Stop, adding up to 3 s each
time and never firing. The cache is therefore part of the design, not an optional extra (§5,
items 10-12).

## 4. Always-firing, ownership and the constraints

| Constraint | How the design meets it | Evidence |
|---|---|---|
| (1) silent when nothing drivable remains | `DRIVE_OPEN` is exact by declaration and is 0 once every row holds a verified token. The term is never computed off the ✅-eligible path, nor in a session that added no doc since it began (`DRIVE_SRC=skip`, or the git fast path). **One honest exception:** a synthesis the session wrote that *recommends nothing* still owes one line, `Drive state: none — <why>`, before its close is ✅. That is a declaration duty that fires once per doc, not a standing alarm. | Fleet duty population, estimated: about 20-27 owning sessions per 14 days (≈1.4-1.9 a day), from the creation census and the 27-of-34 coverage. About 5 of the 16 in-repo docs created in 14 days have no action heading [E: heading grep, `created_docs.txt` loop], so ≈0.5 "recommends nothing" fires a day fleet-wide, each cured once by one line. Capped at 2 forced turns a session (`COMPLETION_UNDRIVEN_MAX`) |
| (2) never blocks a ⛔ or a stated park | ⛔ is computed first and governs (`:2505`), so the term reads `skip` (test 18). A park is `parked <backlog-id>` (a falsifier or why-not-now row) or `decision <id>`, both verified against their stores. An operator's own "don't implement" becomes a `parked` row that quotes them. **Cost:** a ≥90% row cannot simply be `dropped`; the park needs one store write. | tests 9, 18; `dropped-at-conviction-95` fixture |
| (3) no settings.json edit | All three channels already run at Stop: wrap-ledger inside completion-assert, session-continue and operator-readout. | live `settings.json` Stop list [M: `jq '.hooks.Stop'`] |
| (4) resident budget not grown | **Zero resident text added.** The vocabulary is taught where it is needed: by the 🔧 READOUT, by the completion-assert reason, and (optionally) by the on-demand research skill and command. | no edit to `CLAUDE.rules.slim.10-session-close.md` or `CLAUDE.global.slim.md` |
| (5) hands off the six owned files | None of them is touched. | file list in §5 |
| (6) one matcher per concept | One parser (`scripts/lib/drive-state.awk`), read only by the ledger. completion-assert **consumes** `DRIVE_*` keys and derives nothing. Ownership reuses `session_writes_paths`, whose new cache shares the single tool list (`_SW_WRITE_TOOLS`) with the streaming reader. `close-shape.sh` is untouched. | §5 |

**Precision, ownership.**
- Over the 14-day census no synthesis doc had two qualifying owner sessions (0 of 34) [M].
- A session that only edits a doc that landed before it began never owns that doc (test 2).
- A doc landed in the same worktree by a session that never wrote it is not owned either (test 3).
- A mention in a Bash result is not a write (test 5).

**Backfill: none required.** The duty only starts for docs added after an owning session began,
so no existing doc can ever fire. The size of an *optional* backfill [M: `py/convtables.py` over
`git ls-files 'docs/research/*/{README,REPORT,SYNTHESIS,DESIGN}.md'` at depth 1]:
- 85 tracked synthesis docs, none of which carries a declaration today;
- 18 of them have a ranked (`Conv.`/`Conviction`) table, 24 tables in all;
- none of those tables sits under a reject/drop heading, so the `none-over-a-ranked-table` refusal
  has no measured false-positive class;
- 13 docs hold 50 rows at ≥ 90.

Those 50 rows are the legacy debt the term will never see. Surfacing them would be a separate
drive task, not this term.

**Interactions with the other Stop hooks** (I read the code; none of these was run):
- **anti-deference-nudge does not double-fire.** Its false-done arm's contradiction is
  `dirty ∨ unlanded ∨ remainder>0`. It reads `RUNG` only to record it, never to decide
  (`hooks/anti-deference-nudge.sh:511-519`). So a 🔧 from this term triggers no second block. That
  corrects axis 10's "Missed" note, which said the arm "would block … for free once any ledger term
  reads 🔧".
- **session-continue cannot loop on it.** Its mechanical 🔧 arm fires only on the session's own
  dirty files (axis 04 §5).
- **operator-readout drops the certificate.** Both of its ✅ SAFE TO CLOSE paths need `RUNG=✅`
  (axis 04 §4.6), so the certificate disappears without any new code.

**Recall.**
- **79%** of synthesis docs landed in 14 days have a session the term would see [M].
- The other 21% were created only by Bash with no later Edit, or have no local writing record.
  This residue sits in the safe direction (silence).
- Through the skill or template route alone, recall would be at most 13% of synthesis writers, and
  0 on the incident [M, §1].

## 5. Exact diff points

Line numbers are on trunk (`f12dd4b12`; `git diff f12dd4b12 HEAD -- scripts hooks tests` is empty
at `72a18b575`). The full prototype diff is Appendix A. It is a copy of `/tmp/r2-C6/mut` against
`/tmp/r2-C6/repo` and does not survive a reboot (axis 10's prototype was lost exactly that way), so
it is reproduced here.

**`scripts/lib/drive-state.awk`** (new, about 110 lines): the parser in §2.1. It skips fences, finds
`Drive state` and `Conv.` columns by exact header text, and emits UNMARKED / OPEN / DROPPED / OK /
VERIFY records. BSD-awk-safe: multi-line inputs travel through `ENVIRON`, never `-v`, because
`-v` cannot carry a newline in BSD awk (measured: "newline in string").

**`scripts/wrap-ledger.sh`**

| # | Where | What |
|---|---|---|
| 1 | header `:25`, `:30` | 🔧 gains `∨ an undriven recommendation in a doc this session added (DRIVE_OPEN ∨ DRIVE_UNMARKED)`; ✅ gains `∧ none owed` |
| 2 | env seams `:197-206` | `WRAP_DRIVE · WRAP_DRIVE_TIMEOUT_S · WRAP_DRIVE_CACHE_DIR · SESSION_WRITES_LIB · CC_BACKLOG_FILE · CC_DECISIONS_DIR` |
| 3 | memo key, after `:640` | `_wl_k="$_wl_k\|${WRAP_DRIVE:-}\|${SESSION_WRITES_LIB:-}\|${CC_BACKLOG_FILE:-}\|${CC_DECISIONS_DIR:-}"` |
| 4 | before `:1452` (§ DRAIN FLOOR) | § DRIVE STATE: state `DRIVE_OPEN=0 DRIVE_UNMARKED=0 DRIVE_DROPPED=0 DRIVE_DOCS="" DRIVE_SRC=skip`; `count_drive_state()` (research-program abstain, transcript, session start from the first stamped record, **layer 1** `git reflog` → `git show --diff-filter=A`, **layer 2** `session_writes_paths` in a bounded child with the cache dir, parse, verify, count); `_drive_verify()` (one `git cat-file --batch-check`, one `grep -F -f -` over the backlog file, one `cc-custody list --json`, one stat per decision id; an unreadable store convicts nothing) |
| 5 | `:2549`, after `count_resident_members` | `count_drive_state` |
| 6 | between `:2574` and `:2575` | `elif [ "$DRIVE_OPEN" -gt 0 ] \|\| [ "$DRIVE_UNMARKED" -gt 0 ]; then RUNG="🔧"; READOUT=…` with two readouts (OPEN: "N recommendation row(s) in doc(s) you created are not driven (…): drive each now, or fire … file … decide …, then write the row's Drive state … 'Research only' is not a disposition."; UNMARKED: "… carries no Drive state. Add a `Drive state` column … or `Drive state: none — <why>` …") |
| 7 | `emit_machine`, after `:2799` | `DRIVE_OPEN= DRIVE_UNMARKED= DRIVE_DROPPED= DRIVE_DOCS= DRIVE_SRC=`. These come after line 17, so the BUSY splice (`:2747`) is untouched |
| 8 | `emit_full`, after `:2830` | `Drive state:    <n> open · <m> undeclared · <k> dropped — <docs>`, or `none owed`, or `not checked (<src>)`. **Not in the prototype**; this is a display line only |
| 9 | `_drive_verify` | bare-shellcheck clean: `printf '%s\n' "$shas" \| sed 's/$/^{commit}/'`, `printf '%s\n' "$ids"`, no unused locals. Measured: `shellcheck` with no flags (the land gate's invocation) gives **0** findings on all three edited scripts |

**`hooks/lib/session-writes.sh`**

| # | Where | What |
|---|---|---|
| 10 | before `:213` (`# _sw_paths`) | `_SW_WRITE_TOOLS='^(Write\|Edit\|MultiEdit\|NotebookEdit)$'` (the one tool list) and `_sw_paths_session_cached()`: one `stat` over the file set, the stale set against `<cache>/<sha16(tp)>`, one `jq` over stale files tagged by `input_filename`, and one `awk` that merges, rewrites the cache and prints |
| 11 | `_sw_paths`, before `local -a srcs` (`:233`) | `if [ "$turn" != true ] && [ -n "${SESSION_WRITES_CACHE_DIR:-}" ]; then out="$(_sw_paths_session_cached "$tp")"; rc=$?; …; return "$rc"; fi`. **Opt-in**, so every existing caller's behavior is byte-identical |
| 12 | `:262`, `:272` | `jq … --arg tools "$_SW_WRITE_TOOLS"` and `select(.name\|test($tools))`. The streaming reader and the cache share one list |

**`hooks/completion-assert.sh`**

| # | Where | What |
|---|---|---|
| 13 | after `:1043` (the FILEDM pair), before `:1045` | read `DRIVE_OPEN` / `DRIVE_UNMARKED` / `DRIVE_DOCS` through `lfield`, digit-guarded. Build `_ca_drive_facts` (the OPEN text, else the UNMARKED text), then `contra=1; facts+=…` |
| 14 | `:1608`, class selection | a fifth class, `undriven`, checked first: `if [ -n "$_ca_drive_facts" ] && [ "$facts" = "${_ca_drive_facts%; }" ]; then CLASS=undriven; CLASS_MAX="${COMPLETION_UNDRIVEN_MAX:-2}"; elif …` (the existing chain). It is claimed only when the drive facts are the only ledger facts; other arms' sentences still ride along |
| 15 | before `:1649` | `[ "$CLASS" = undriven ] && reason="Completion-assert: your close reads as done, but ${facts}. A research doc's recommendations are this session's work the moment the doc lands, and 'research only' is not a disposition. Drive each now …, or hand it to an owner with a record (fired <slug> / filed <id> / decision <id>; an operator's own 'do not implement' is a parked <id> row quoting them), write that into the doc's Drive state, then re-close."` This replaces the generic ledger sentence, which talks about /ship and the live layer |
| 16 | header `:87-89`, seams `:95-105` | document `undriven` = `COMPLETION_UNDRIVEN_MAX` (default 2) |

**Optional and non-enforcing.** None of these is needed for the measured behaviour.

- `skills/research-subagents/SKILL.md` § synthesis contract (`:534-560`) and `commands/research.md`:
  one sentence, "the synthesis's recommendation table carries a `Drive state` column, `to drive`
  until each row is driven, fired, filed or decided". Both files load on demand, not resident.
  They reach ≤13% of synthesis writers, so they are a courtesy, not coverage.
- `hooks/operator-readout.sh` 🔧 `parts` (`:1323-1329`): a `parts` term that names the doc. It is
  shown to the operator only.
- The F18 write-time nudge in `validate-plan-structure.sh`. It would cut the UNMARKED fires, but
  it needs a per-(session, file) latch, its own branch ahead of the `:64-70` case, and a merge into
  the single JSON object (`tests/validate-plan-structure.bats:120-131`). It is not part of this
  design.

## 6. Tests: written, and run on the prototype

**How they were run.** `cc-bats` refused every run with rc 75: "2 concurrent bats execution
root(s) … AND 1-min load/core at or above 2.0". That is a deferral, not a result. So, as the brief
allows, each suite ran under the real bats-core
(`taskpolicy -c utility /opt/homebrew/opt/bats-core/bin/bats --tap <file>`), serially, from a
script file, on the scratch copies.

Load was 290-570 throughout. At that load one wrap-ledger test takes about 1-4 minutes, so the full
140-test `wrap-ledger.bats` and 185-test `completion-assert.bats` were **not** run end to end. They
were run as the subsets below. The unmutated control copy did pass 20/20 of the first
`wrap-ledger.bats` tests and 32/32 of `session-writes.bats` before I stopped it to free load.

| Suite (on `/tmp/r2-C6/mut` unless noted) | Plan line | ok | not ok | rc |
|---|---|---|---|---|
| `tests/wrap-ledger-drive-state.bats` (new, 18 tests) | `1..18` | 18 | 0 | 0 |
| `tests/completion-assert-drive-state.bats` (new, 6) | `1..6` | 6 | 0 | 0 |
| `tests/session-writes-cache.bats` (new, 4) | `1..4` | 4 | 0 | — |
| `tests/session-writes.bats` (existing, with the lib refactor) | `1..32` | 32 | 0 | 0 |
| `tests/completion-assert.bats -f 'CAP SPLIT\|FILED\|filed'` (existing subset) | `1..7` | 7 | 0 | 0 |
| `tests/wrap-ledger.bats -f 'FILED\|filed\|parity\|glyph\|why-not-now\|condition-keyed\|ANOTHER session'` (existing subset: the 👤/FILED quartet, lineage, the class-C other-session control and the three rung-parity tests) | `1..18` | 18 | 0 | 0 |
| control `/tmp/r2-C6/repo`: `session-writes.bats` | `1..32` | 32 | 0 | — |
| control `/tmp/r2-C6/repo`: `wrap-ledger.bats` (stopped at 20) | `1..140` | 20 | 0 | stopped |

**Disclosure.** The existing subset includes "class-C filed by a DIFFERENT session". It runs the
repo's real `bin/cc-decide open`, but under the suite's own `CC_DECISIONS_DIR=$BATS_TEST_TMPDIR/decisions`
and `CC_IDL` fixture, so no live store was written. My new ⛔ test uses a stub instead.

**A failure mode found and fixed while running them.** In the first batch the positives failed with
`DRIVE_SRC=error`. Under the utility QoS band at load 300-500, the term's bounded child overran its
3 s default. It was the bound, not the logic: the same test passes with a 30 s bound, and a
diagnostic run printed `DRIVE_SRC=WRAP_SESSION_ID` and `RUNG=🔧`. The suite now pins
`WRAP_DRIVE_TIMEOUT_S=30` in setup, and test 17 pins the expiry itself
(`WRAP_DRIVE_TIMEOUT_S=0.01` gives `DRIVE_SRC=error` and RUNG ✅). The first batch also ran while I
was still editing the code. Its results are discarded, and every number in the table above comes
from runs on frozen code.

What the 18 drive-state tests pin, by number:
- Positives:
  - 1: UNMARKED on the incident shape.
  - 4: an owner seen only through a workflow agent's file.
  - 7: `to drive` rows are counted.
  - 9: a fake sha, a never-minted id and a bare `parked` each stay OPEN.
  - 11: `dropped` at 95 stays OPEN.
  - 12: `none` over a ranked table stays OPEN.
  - 13: a fenced quote is not a declaration.
- Controls:
  - 2: a doc that predates the session.
  - 3: another session's doc that this session never wrote.
  - 5: a mention is not a write.
  - 6: an axis doc carries no duty.
  - 8: a fully disposed and verified doc reads ✅.
  - 10: a rebased-away sha still verifies.
  - 12b: an honest `none` reads ✅.
- Ranking:
  - 14: the term outranks 👤.
  - 18: ⛔ governs.
- Fail-open:
  - 15: no transcript, or the kill switch.
  - 16: not computed off the ✅-eligible path.
  - 17: the bound expires.

The six completion-assert tests pin:
- 1-2: the incident close fires, class `undriven`, naming the doc.
- 3: the same close over a clean ledger reads clean.
- 4: **starvation**. Three real 📦 fires spend `assert` and the fourth close reads `capped:3>=3`;
  the undriven close still fires. This is the incident's 13:18-14:27Z sequence, live.
- 5: the undriven cap is hard.
- 6: beside another ledger fact the fire stays class `assert`, so no existing case changes class.

## 7. Residual risks, ranked by what they cost the conviction

1. **Laundering below the 90 line.** `dropped: research only` on a row the doc ranks below 90 is
   accepted and counted in `DRIVE_DROPPED`. In the incident fixture, 37 of 38 rows could be
   laundered that way, and only #3 (95%) stays OPEN, so 🔧 survives [M]. The block text names
   "research only is not a disposition", and the doc then shows the laundering in writing, in a
   landed file. **Unmeasured:** how often a blocked agent drives, fires or files rather than
   launders. The incident agent fired a session (`handoff-fire.sh … startup-hooks-impl`, 20:05Z)
   the first time anyone confronted it. That is one data point, not a rate. **Estimated 75-85%**
   drive/fire/file. The basis is that one data point plus the forced-turn compliance the existing
   classes rely on; no fleet rate was measured.
2. **Latency under extreme load.**
   - The per-Stop cost is small in CPU: +0.03 s on the fast path, +0.17-0.22 s warm (measured).
   - Wall time balloons with load. At load 525-555 the whole ledger took 2.1-3.0 s, against
     1.35-2.24 s with `WRAP_DRIVE=off` (measured).
   - completion-assert is already at its 5 s Stop timeout on 18.1% of runs over 30 days (README
     F29). Any added wall time raises that rate for research sessions after they land.
   - The term's own bound (3 s) **was exceeded inside bats in the utility QoS band at load
     300-500**. Positives then read `DRIVE_SRC=error`, which is fail-open and silent (§6, the first
     batch). Stop hooks run at normal QoS, and there no replay run exceeded the bound: more than 20
     `on` runs at load 300-555 [M: `replay/ledger.sh`, `DRIVE_SRC` printed each time]. Even so, the
     term can go silent in exactly the overload periods this box lives in.
3. **Recall: 79%.** Docs created only by Bash or python with no later Edit, or written on another
   machine (the cloud fire path), are invisible: 7 of 34 in 14 days [M]. This is the safe
   direction, but it is a miss.
4. **The presence duty fires on docs that recommend nothing.** About 0.5 a day fleet-wide [E].
   Each costs one forced turn and one line, and the `none` escape is refused only for docs with a
   ranked table.
5. **Cache staleness.** The per-file key is (size, mtime-seconds). A same-second rewrite to the
   identical size would serve stale records. Transcripts are append-only, so this needs a non-append
   rewrite, which the harness does not do [E: JSONL append-only].
6. **Opt-in on plans.** `docs/plans/*.md` carry no presence duty, 22 created in 14 days [M].
   A plan's waves are caught only when it carries a declaration.
7. **Bounded enforcement.** Two `undriven` fires per session (cap 2, latched per message hash).
   A third undriven close passes, with the READOUT still 🔧. By design completion-assert never
   loops, so a determined agent can outlast it.

## 8. Verdict and conviction (post-measurement)

**C6 as briefed, an opt-in count, does not catch the incident.** The incident README had no marker.
The skill/template route reaches 0% of the incident and at most 13% of synthesis writers [M]. As
briefed, C6 cannot clear 90%.

**C6 with the presence duty (this design) does catch it.** On the incident's own transcript, README
and capped `assert` budget:
- the ledger reads 🔧 instead of ✅;
- completion-assert delivers a block (`undriven 1/2`) where the unmodified hook abstained
  `capped:3>=3` [M, §3.2];
- the bounded follow-up behaves as designed: 2/2, then silent [M].

The design meets constraints (2), (3), (4), (5) and (6) outright. It meets (1) except for a measured,
bounded duty: one line on a synthesis that recommends nothing, about 0.5 a day fleet-wide [E].

Conviction parts:

| Claim | Conviction | Basis |
|---|---|---|
| It flags the incident class when the doc's owner closes | 95 | measured replay (§3.2) + tests 1, 4, 7 |
| It stays silent for non-owners and old docs | 92 | 0/34 double owners [M]; tests 2, 3, 5, 6 |
| Laundering of the one-line and ≥90 kinds is refused | 95 | fixtures + tests 11, 12 |
| Its latency is acceptable | 80 | fast path +0.03 s CPU, warm slow path +0.17-0.22 s CPU [M]; but wall time at load 500+ and completion-assert's existing 18% ≥5 s rate are real exposure |
| Recall over research closes | 79% of docs [M] | Bash-only creations are invisible |
| A blocked agent then enacts or hands off with a record, rather than laundering rows below 90 | 75-85 [E] | one incident data point; not measured |

**Overall conviction that this design is correct, safe and net-positive to build: 87%.** **That is
below the 90 bar.** The gap is not the mechanism; that much is measured. Two parts are not:

1. **Behaviour.** No measurement shows what a blocked agent does with rows below 90.
2. **Overload.** No live measurement shows how the term behaves at load 500+, where it can go
   silent or push completion-assert past its 5 s timeout.

Conviction that it **eliminates** the incident class is lower, about 65% [E]: recall 0.79 × an
enact rate of about 0.8, plus the overload silence.

**What would take it over 90 with measured evidence.** Neither step needs a settings edit or
resident text.

1. **Land it in shadow first.** `WRAP_DRIVE=shadow` computes and emits `DRIVE_*`, and writes one
   IDL row per computed Stop: `drive_open`, `drive_unmarked`, `drive_src` and the elapsed
   milliseconds. The rung arm and the completion-assert term ignore it. The diff adds about two
   lines (`case` on `shadow` at the arm, and in completion-assert's read) plus one IDL append.
   **This part is not prototyped.**
   - Run it for 7 days, then flip to `on` only if all four hold:
     - (a) a hand audit of every would-fire finds ≥ 95% truly the session's own undriven
       recommendations;
     - (b) "recommends nothing" fires are ≤ 1 a day;
     - (c) `DRIVE_SRC=error` is ≤ 5% of computed runs;
     - (d) completion-assert's p95 duration moves ≤ 0.3 s on ✅-eligible Stops.
   - Landing the shadow form alone I hold at about 90%: it is pure measurement, and its only cost
     is the latency in §3.5.
2. **A behaviour probe** on a sandbox copy of the incident transcript (a resumed copy under a /tmp
   `CLAUDE_CONFIG_DIR`, never the live session), with the undriven block injected, n ≥ 5. Count
   how often the agent drives, fires or files, against how often it writes `dropped:` on rows
   below 90. This pass did not run it: it spawns model sessions, which is outside a read-only
   worker's remit.

**Operator-only steps:** none for the design itself. Landing it is an ordinary `/ship` of
`scripts/`, `hooks/` and `tests/`, with no `settings.json` change.

## Appendix A. Prototype diff (reproducible after a reboot)

Generated with `diff -u` between `/tmp/r2-C6/repo` (the unmodified copy at `f12dd4b12`) and the
prototype. The tests ran against `/tmp/r2-C6/mut`. The text below is `/tmp/r2-C6/clean`, which
differs from `mut` only in comments (9 lines in `wrap-ledger.sh`) and in having the abandoned
`session_created_paths` reader (§3.4) removed from `session-writes.sh`. Nothing calls that reader
in `mut` either. The new test files copy their parent suites' `setup()` and helpers verbatim, so
only the new parts are shown here; the copied line ranges are named.

### A.1 `scripts/wrap-ledger.sh`

```diff
--- a/scripts/wrap-ledger.sh	2026-10-18 20:13:26
+++ b/scripts/wrap-ledger.sh	2026-10-18 21:26:19
@@ -638,6 +638,7 @@
     _wl_k="$_wl_k|${WRAP_LIVE_REPO:-}|${WRAP_LIVE_BUDGET_COMMITS:-}|${WRAP_LIVE_BUDGET_MIN:-}"
     _wl_k="$_wl_k|${CC_MIGRATIONS_STATE:-}|${WRAP_LAND_INFLIGHT_LIB:-}"
     _wl_k="$_wl_k|${WRAP_RESEARCH:-}|${CC_RESEARCH_BIN:-}|${CC_RESEARCH_REGISTRY:-}"
+    _wl_k="$_wl_k|${WRAP_DRIVE:-}|${SESSION_WRITES_LIB:-}|${CC_BACKLOG_FILE:-}|${CC_DECISIONS_DIR:-}"
     # WRAP_BUSY joins the key (2026-10-04): session-continue asks with WRAP_BUSY=off to skip the
     # process-table scan, and a BUSY-less ledger served to a BUSY reader (operator-readout, notify,
     # cc-classify) would read BUSY_STATE=UNKNOWN for a session that is working.
@@ -1449,6 +1450,145 @@
   esac
 }
 
+# ── DRIVE STATE — recommendations a doc THIS SESSION ADDED leaves undriven (the 🔧 arm) ──────────
+# docs/research/close-behavior-2026-10-18/round2/C6-doc-disposition-marker.md. The incident: a
+# session landed a research README whose §5 listed six drivable implementation waves, closed
+# "✅ Good to close: yes … the waves haven't started, because this pass was research only", and this
+# ledger said ✅ fifteen seconds earlier because none of its inputs carried "a doc you wrote
+# recommends work nobody drove". Heading heuristics cannot be that input (axis 10 §2: precision
+# 1/15), so the input is an EXACT on-doc convention, parsed by scripts/lib/drive-state.awk:
+#   · a `Drive state` table column (one token per recommendation row) and/or a column-0 line
+#     `Drive state: <token>`; tokens to drive · driven <sha> · fired <slug> · filed|operator|parked
+#     <id> · decision <id> · dropped: <why> · none.
+#   · DRIVE_OPEN    rows that are `to drive`, empty, malformed, or whose sha/id/slug does not verify;
+#   · DRIVE_UNMARKED research SYNTHESIS docs (docs/research/<dir>/{README,REPORT,SYNTHESIS,DESIGN}.md)
+#     the session added with NO declaration — the presence duty that makes the convention reach
+#     sessions that never loaded a template (13% of synthesis writers did, measured).
+# OWNERSHIP = the session WROTE the doc (session-writes.sh session_writes_paths, subagents included)
+# AND a commit this worktree made since the session began ADDED it: a session that edits an old doc
+# never inherits its rows (measured 14 d: 0 docs with two qualifying sessions). ⛔ is computed first
+# and outranks this; a stated park is `parked <backlog-id>` (a falsifier row) or `decision <id>`; an
+# active research program
+# abstains (its residuals are not open work — the Follow-On Gate exemption, ruling 83adb541ea19).
+# Fail-OPEN in every direction, like FILED_MINE: no transcript, no lib, a timeout, an unreadable
+# store ⇒ count 0 with DRIVE_SRC saying why. Computed only on the ✅-eligible path.
+DRIVE_OPEN=0; DRIVE_UNMARKED=0; DRIVE_DROPPED=0; DRIVE_DOCS=""; DRIVE_SRC="skip"
+count_drive_state() {
+  case "${WRAP_DRIVE:-on}" in off|0|no|OFF|NO) DRIVE_SRC="n-a"; return 0 ;; esac
+  local tp sw_lib awkf top start se shas cands c keep written rc docs d rel synth recs vf
+  if [ "$RESEARCH_PROGRAM" = none ] && [ "$MODE" != machine ] && [ "$MODE" != full ]; then
+    compute_research >/dev/null 2>&1 || true
+  fi
+  [ "$RESEARCH_PROGRAM" = none ] || { DRIVE_SRC="n-a"; return 0; }
+  tp="${TRANSCRIPT_FLAG:-${WRAP_TRANSCRIPT:-}}"
+  [ -z "$tp" ] && [ -n "$SID" ] && tp="$(_wl_find_transcript "$SID" 2>/dev/null)" || true
+  [ -n "$tp" ] && [ -f "$tp" ] || { DRIVE_SRC="none"; return 0; }
+  sw_lib="${SESSION_WRITES_LIB:-$WL_SELF_DIR/../hooks/lib/session-writes.sh}"
+  [ -f "$sw_lib" ] || sw_lib="$HOME/.claude/hooks/lib/session-writes.sh"
+  awkf="$WL_SELF_DIR/lib/drive-state.awk"
+  [ -f "$awkf" ] || awkf="$HOME/.claude/scripts/lib/drive-state.awk"
+  [ -f "$sw_lib" ] && [ -f "$awkf" ] || { DRIVE_SRC="error"; return 0; }
+  top="$(git rev-parse --show-toplevel 2>/dev/null)" && top="$(cd "$top" && pwd -P)" || { DRIVE_SRC="error"; return 0; }
+  # When the session began: its transcript's first stamped record (the harness writes one per record).
+  start="$(head -c 262144 "$tp" 2>/dev/null | grep -m1 -o '"timestamp":"[0-9T:.-]*Z"' | cut -d'"' -f4)"
+  se="$(date -j -u -f '%Y-%m-%dT%H:%M:%S' "${start%%.*}" +%s 2>/dev/null || date -u -d "$start" +%s 2>/dev/null)" || se=""
+  case "$se" in ''|*[!0-9]*) DRIVE_SRC="error"; return 0 ;; esac
+  # LAYER 1, git and cheap: docs ADDED by commits this worktree made or picked (ship-land's rebase
+  # writes `rebase (pick)` with the landed sha) since the session began. A prefilter only — a linked
+  # worktree is not single-tenant (session-writes.sh § worktree-implies-mine), so layer 2 decides.
+  shas="$(git reflog --date=unix --format='%gd %H %gs' HEAD 2>/dev/null \
+          | awk -v s="$se" '{ t = $1; gsub(/[^0-9]/, "", t); if (t + 0 >= s && $3 ~ /^(commit|rebase|cherry-pick|merge)/) print $2 }' | sort -u)"
+  [ -n "$shas" ] || { DRIVE_SRC="$SID_SRC"; return 0; }
+  # shellcheck disable=SC2086   # one sha per word, by construction
+  cands="$(git show --diff-filter=A --name-only --format= $shas -- 'docs/*.md' 2>/dev/null | sort -u)"
+  keep=""
+  while IFS= read -r c; do
+    [ -n "$c" ] && [ -f "$top/$c" ] || continue
+    case "$c" in
+      docs/research/*/*/*) ;;
+      docs/research/*/README.md|docs/research/*/REPORT.md|docs/research/*/SYNTHESIS.md|docs/research/*/DESIGN.md) keep="$keep$top/$c
+"; continue ;;
+    esac
+    grep -q -i -E '^Drive state:|\|[[:space:]]*Drive state[[:space:]]*\|' "$top/$c" 2>/dev/null && keep="$keep$top/$c
+"
+  done <<EOF2
+$cands
+EOF2
+  [ -n "$keep" ] || { DRIVE_SRC="$SID_SRC"; return 0; }
+  # LAYER 2, exact: THIS session wrote the doc (session-writes.sh, subagents/** included). In a CHILD,
+  # as for the resident term: session-writes defines names four other hooks also define.
+  # shellcheck disable=SC2016   # the child's own positional parameters
+  # The per-file (size, mtime) cache (session-writes.sh _sw_paths_session_cached): finished agents'
+  # files are immutable, so only the main transcript is re-read after the first Stop.
+  written="$(SESSION_WRITES_CACHE_DIR="${WRAP_DRIVE_CACHE_DIR:-${TMPDIR:-/tmp}/cc-session-writes.${UID:-0}}" \
+             _bounded "${WRAP_DRIVE_TIMEOUT_S:-3}" bash -c \
+    '. "$1" 2>/dev/null || exit 2; o="$(session_writes_paths "$2")"; r=$?; [ "$r" -eq 0 ] || exit "$r"
+     _sw_canon_lines "$o"; printf "%s" "$_SW_CANON"' _ "$sw_lib" "$tp" 2>/dev/null)"; rc=$?
+  case "$rc" in
+    0) ;;
+    1) DRIVE_SRC="$SID_SRC"; return 0 ;;      # wrote nothing — counted zero
+    *) DRIVE_SRC="error"; return 0 ;;         # cannot tell (incl. the bound) — never a rung
+  esac
+  docs=""
+  while IFS= read -r d; do
+    [ -n "$d" ] || continue
+    printf '%s\n' "$written" | grep -qxF "$d" || continue
+    rel="${d#"$top"/}"; synth=0
+    case "$rel" in docs/research/*/*/*) ;; docs/research/*/README.md|docs/research/*/REPORT.md|docs/research/*/SYNTHESIS.md|docs/research/*/DESIGN.md) synth=1 ;; esac
+    docs="${docs}$(awk -v doc="$rel" -v synth="$synth" -f "$awkf" "$d" 2>/dev/null)
+"
+  done <<EOF2
+$keep
+EOF2
+  recs="$(printf '%s' "$docs" | grep -v '^$' || true)"
+  [ -n "$recs" ] || { DRIVE_SRC="$SID_SRC"; return 0; }
+  vf="$(_drive_verify "$recs")"
+  DRIVE_UNMARKED="$(printf '%s\n' "$vf" | grep -c '^UNMARKED' | tr -d ' ')"
+  DRIVE_OPEN="$(printf '%s\n' "$vf" | grep -c '^OPEN' | tr -d ' ')"
+  DRIVE_DROPPED="$(printf '%s\n' "$vf" | grep -c '^DROPPED' | tr -d ' ')"
+  DRIVE_DOCS="$(printf '%s\n' "$vf" | awk -F'\t' '$1=="UNMARKED"{u[$2]=1; o[$2]+=0} $1=="OPEN"{o[$2]++}
+      END { n=0; for (d in o) if (o[d]>0 || u[d]) { n++; if (n<=3) s=s (s?", ":"") d (u[d] ? " (no Drive state declaration)" : " (" o[d] " open)") }
+            if (n>3) s=s " +" (n-3); print s }')"
+  DRIVE_SRC="$SID_SRC"
+}
+
+# _drive_verify <records> — the VERIFY records become OK or OPEN, each store read ONCE for the batch.
+# A sha must name a commit object in this repo (`git cat-file`): ancestry of trunk is UNLANDED's
+# question, and ship-land's rebase re-mints every sha, so a pre-rebase sha written at commit time
+# stays valid (axis 10 skeptic F1.2). An unreadable store verifies nothing and convicts nothing.
+_drive_verify() {
+  local recs="$1" shas ids decs slugs miss_sha="" have_bl="" have_slug="" bl cbin dd
+  shas="$(printf '%s\n' "$recs" | awk -F'\t' '$1=="VERIFY" && $4=="sha" {print $5}' | sort -u)"
+  ids="$(printf '%s\n' "$recs" | awk -F'\t' '$1=="VERIFY" && $4=="bl" {print $5}' | sort -u)"
+  decs="$(printf '%s\n' "$recs" | awk -F'\t' '$1=="VERIFY" && $4=="dec" {print $5}' | sort -u)"
+  slugs="$(printf '%s\n' "$recs" | awk -F'\t' '$1=="VERIFY" && $4=="slug" {print $5}' | sort -u)"
+  [ -n "$shas" ] && miss_sha="$(printf '%s\n' "$shas" | sed 's/$/^{commit}/' | git cat-file --batch-check 2>/dev/null \
+                                | awk '$2=="missing"{sub(/\^\{commit\}$/,"",$1); print $1}')"
+  bl="${CC_BACKLOG_FILE:-$HOME/.claude/autonomy/backlog.jsonl}"
+  if [ -n "$ids" ]; then
+    if [ -r "$bl" ]; then have_bl="$(printf '%s\n' "$ids" | grep -o -F -f - "$bl" 2>/dev/null | sort -u)"; else have_bl="$ids"; fi
+  fi
+  dd="${CC_DECISIONS_DIR:-$HOME/.claude/autonomy/decisions}"
+  if [ -n "$slugs" ]; then
+    cbin="${CC_CUSTODY_BIN:-}"
+    [ -n "$cbin" ] || for cbin in "$WL_SELF_DIR/../bin/cc-custody" "$HOME/.claude/bin/cc-custody"; do [ -x "$cbin" ] && break; cbin=""; done
+    if [ -n "$cbin" ] && have_slug="$(_bounded "${WRAP_CUSTODY_TIMEOUT_S:-5}" "$cbin" list --json 2>/dev/null \
+                                      | jq -r '.[] | (.slug // empty)' 2>/dev/null)" && [ -n "$have_slug" ]; then :
+    else have_slug="$slugs"; fi
+  fi
+  printf '%s\n' "$recs" | _DV_MS="$miss_sha" _DV_HB="$have_bl" _DV_HS="$have_slug" _DV_DS="$decs" awk -F'\t' -v dd="$dd" '
+    BEGIN { ms=ENVIRON["_DV_MS"]; hb=ENVIRON["_DV_HB"]; hs=ENVIRON["_DV_HS"]; ds=ENVIRON["_DV_DS"]   # -v cannot carry a newline (BSD awk)
+            n=split(ms,a,"\n"); for(i=1;i<=n;i++) if(a[i]!="") MS[a[i]]=1
+            n=split(hb,a,"\n"); for(i=1;i<=n;i++) if(a[i]!="") HB[a[i]]=1
+            n=split(hs,a,"\n"); for(i=1;i<=n;i++) if(a[i]!="") HS[a[i]]=1
+            n=split(ds,a,"\n"); for(i=1;i<=n;i++) if(a[i]!="") { f=dd "/" a[i] ".json"; if ((getline x < f) >= 0) HD[a[i]]=1; close(f) } }
+    $1!="VERIFY" { print; next }
+    $4=="sha"  { if ($5 in MS) print "OPEN\t" $2 "\t" $3 "\tsha-not-a-commit-here"; else print "OK\t" $2 "\t" $3 "\tdriven"; next }
+    $4=="bl"   { if ($5 in HB) print "OK\t" $2 "\t" $3 "\tfiled"; else print "OPEN\t" $2 "\t" $3 "\tid-not-in-backlog"; next }
+    $4=="dec"  { if ($5 in HD) print "OK\t" $2 "\t" $3 "\tdecision"; else print "OPEN\t" $2 "\t" $3 "\tno-such-decision"; next }
+    $4=="slug" { if (($5 in HS) || (("fire-" $5) in HS)) print "OK\t" $2 "\t" $3 "\tfired"; else print "OPEN\t" $2 "\t" $3 "\tslug-not-in-custody"; next }'
+}
+
 # ── THE DRAIN FLOOR (2026-09-05, BACKLOG_ZERO §5.5 — the generator's other half) ─────────────────
 # CLOSE_FLOOR=1 ⇒ this session's CURRENT CONTRACT is about the backlog (DRAIN_SCOPE) and it has
 # closed NO row (CLOSED_MINE=0) — so the ✅-shaped certificate is withheld and the rung is 🔧.
@@ -2547,6 +2687,7 @@
   compute_close_floor
   sum_unconvicted
   count_resident_members
+  count_drive_state
   if [ "$RESIDENT_MINE" -gt 0 ]; then
     # RANKED BESIDE THE CUSTODY ARM ABOVE, and one step below it, for the reason custody gives:
     # both name work that is NOT in this tree, so neither can be seen by DIRTY/REMAINDER/UNLANDED,
@@ -2572,6 +2713,17 @@
     # Same rank as filed-undriven, for the same reason: a backlog-scoped session that closed no row
     # has not done the thing it was sent to do, whatever it landed. Machinery is not a close.
     RUNG="🔧"; READOUT="🔧 Loose ends — your frozen scope is about the backlog and this session has closed NO row (CLOSED_MINE=0); machinery is not a close. Pick one: \`$HOME/.claude/scripts/drain-pick.sh --project <this project>\`, drive or adjudicate it (MOOT · DOABLE · OPERATOR-ONLY), then \`cc-backlog done <id> --evidence …\` — or close honestly on 'Good to close: no'."
+  elif [ "$DRIVE_OPEN" -gt 0 ] || [ "$DRIVE_UNMARKED" -gt 0 ]; then
+    # Same rank as filed-undriven and one step below it (§ DRIVE STATE): a recommendation a doc you
+    # created names, that nothing drove, filed, fired or decided, is your open work — and "research
+    # only" is not a disposition. Below FILED/UNCONVICTED/FLOOR, which name a store row with an
+    # exact cure; above no-trunk, 🚀 and 👤, which all assert "my side is done".
+    RUNG="🔧"
+    if [ "$DRIVE_OPEN" -gt 0 ]; then
+      READOUT="🔧 Loose ends — ${DRIVE_OPEN} recommendation row(s) in doc(s) you created are not driven (${DRIVE_DOCS}): drive each now, or fire a session (handoff-fire.sh), file it (cc-backlog add --why-not-now …) or open the decision (cc-decide open --class C …), then write the row's Drive state (driven <sha> | fired <slug> | filed <id> | decision <id> | dropped: <why>). \"Research only\" is not a disposition."
+    else
+      READOUT="🔧 Loose ends — ${DRIVE_DOCS}: a research synthesis you created carries no Drive state. Add a \`Drive state\` column to its recommendation table (\`to drive\` until each row is driven, fired, filed or decided), or the line \`Drive state: none — <why>\` if it recommends nothing."
+    fi
   elif [ -z "$TRUNK" ]; then
     # No trunk resolved ⇒ UNLANDED=0 is a DEFAULT, not a measurement: nothing was ever compared, so
     # every arm below that says "landed" would be asserting a fact this run never read. This rung
@@ -2797,6 +2949,11 @@
   printf 'DRAIN_SCOPE=%s\n' "$DRAIN_SCOPE"
   printf 'CLOSE_FLOOR=%s\n' "$CLOSE_FLOOR"
   printf 'CLOSE_FLOOR_SRC=%s\n' "$CLOSE_FLOOR_SRC"
+  printf 'DRIVE_OPEN=%s\n' "$DRIVE_OPEN"
+  printf 'DRIVE_UNMARKED=%s\n' "$DRIVE_UNMARKED"
+  printf 'DRIVE_DROPPED=%s\n' "$DRIVE_DROPPED"
+  printf 'DRIVE_DOCS=%s\n' "$DRIVE_DOCS"
+  printf 'DRIVE_SRC=%s\n' "$DRIVE_SRC"
   printf 'BLOCKED=%s\n' "$BLOCKED"
   printf 'BLOCKED_SRC=%s\n' "$BLOCKED_SRC"
   printf 'GOAL_SRC=%s\n' "$GOAL_SRC"
```

### A.2 `hooks/completion-assert.sh`

```diff
--- a/hooks/completion-assert.sh	2026-10-18 20:13:26
+++ b/hooks/completion-assert.sh	2026-10-18 21:26:19
@@ -1041,6 +1041,25 @@
 # done-claim lands); never re-derive.
 FILEDM="$(lfield FILED_MINE)"; case "$FILEDM" in ''|*[!0-9]*) FILEDM=0 ;; esac
 [ "$FILEDM" -gt 0 ] && { contra=1; facts="${facts}${FILEDM} backlog row(s) YOU filed this session are still open with no stated reason you could not drive them (cc-backlog list --open --json | jq '.[]|select(.filedBy==\"${SID}\")') — drive each and \`cc-backlog done <id> --evidence …\`, drop it (\`done --evidence \"dropped: <why>\"\`), or hand it off by re-running the same add with \`--why-not-now \"needs-credential|needs-human|not-yet-true|no-capacity: <detail>\"\`; a row is not a disposition; "; }
+
+
+# DRIVE STATE (round 2 C6, docs/research/close-behavior-2026-10-18/round2/C6-doc-disposition-marker.md)
+# — a done-claim over recommendations a doc THIS session created names and nothing drove, filed,
+# fired or decided, or over a research synthesis it created with no Drive state at all. The incident
+# close ("✅ Good to close: yes … the implementation waves in README §5 haven't started, because this
+# pass was research only") reached this hook at `capped:3>=3`: three 📦 fires an hour earlier had
+# spent the `assert` budget. So these facts claim their OWN class (`undriven`, below) whenever they
+# are the only ledger facts. CONSUME the ledger's counts (computed on the ✅-eligible path); never
+# re-derive.
+DRIVEO="$(lfield DRIVE_OPEN)";     case "$DRIVEO" in ''|*[!0-9]*) DRIVEO=0 ;; esac
+DRIVEU="$(lfield DRIVE_UNMARKED)"; case "$DRIVEU" in ''|*[!0-9]*) DRIVEU=0 ;; esac
+_ca_drive_facts=""
+if [ "$DRIVEO" -gt 0 ]; then
+  _ca_drive_facts="${DRIVEO} recommendation row(s) in doc(s) YOU created are not driven ($(lfield DRIVE_DOCS)) — \"research only\" is not a disposition: drive each now, or fire a session (handoff-fire.sh), file it (cc-backlog add --why-not-now …) or open the decision (cc-decide open --class C …), then write the row's Drive state (driven <sha> | fired <slug> | filed <id> | decision <id> | dropped: <why>); "
+elif [ "$DRIVEU" -gt 0 ]; then
+  _ca_drive_facts="a research synthesis YOU created carries no Drive state ($(lfield DRIVE_DOCS)): add a \`Drive state\` column to its recommendation table (\`to drive\` until each row is driven, fired, filed or decided), or the line \`Drive state: none — <why>\` if it recommends nothing; "
+fi
+[ -n "$_ca_drive_facts" ] && { contra=1; facts="${facts}${_ca_drive_facts}"; }
 
 # UNCONVICTED (2026-09-08, THE CONVICTION PROTOCOL — docs/research/conviction-close-2026-09-08.md) —
 # a done-claim over an ask of the operator that carries no NUMBER and no RECEIPT: a needs-human row
@@ -1606,7 +1625,11 @@
 # close this demand exists for would arrive capped. Claimed ONLY when verdict-first is D6's sole
 # token and no conviction arm fired; every other case keeps the class it has today.
 CLASS=assert; CLASS_MAX="$MAX"
-if [ "$d6" -eq 1 ] && [ "$_d6_missing" = "verdict-first" ] \
+# `undriven` is a FIFTH class: claimed when the drive-state facts are the ONLY ledger facts (any other
+# arm's sentence still rides along, but its budget is not spent), for the starvation reason above.
+if [ -n "$_ca_drive_facts" ] && [ "$facts" = "${_ca_drive_facts%; }" ]
+then CLASS=undriven; CLASS_MAX="${COMPLETION_UNDRIVEN_MAX:-2}"
+elif [ "$d6" -eq 1 ] && [ "$_d6_missing" = "verdict-first" ] \
    && [ "$d1" -eq 0 ] && [ "$d2" -eq 0 ] && [ "$d3" -eq 0 ] && [ "$d4" -eq 0 ] && [ "$d5" -eq 0 ]
 then CLASS=verdict; CLASS_MAX="${COMPLETION_VERDICT_MAX:-2}"
 elif [ "$d6" -eq 1 ]; then CLASS=shape; CLASS_MAX="${COMPLETION_SHAPE_MAX:-2}"
@@ -1646,6 +1669,9 @@
 # one; it qualifies this group's own "📦 ⇒ /ship it" remedy and must therefore sit inside it.
 reason=""
 [ "$contra" -eq 1 ] && reason="Completion-assert: your close reads as done/complete, but the LIVE ledger contradicts it — ${facts}. Ship/land of verified net-positive work is DRIVABLE (not a genuine blocker), and so is converging the live layer. Re-answer by DRIVING the remainder to done (📦 ⇒ /ship it; 🚀 landed-but-not-live ⇒ run the converger named above, then re-read; finish the open items; commit with explicit paths) — or name the ONE irreducible blocker (credential / sudo / destructive-migration / external-info only the operator has).${_ca_ushare}"
+# The undriven class gets its own ledger sentence: the generic one above speaks of /ship and the live
+# layer, which name nothing this close can do. Only the facts and the cure for THIS demand.
+[ "$CLASS" = undriven ] && reason="Completion-assert: your close reads as done, but ${facts}. A research doc's recommendations are this session's work the moment the doc lands, and 'research only' is not a disposition. Drive each now (at 90%+ conviction there is no question to ask), or hand it to an owner with a record (fired <slug> / filed <id> / decision <id>; an operator's own 'do not implement' is a parked <id> row quoting them), write that into the doc's Drive state, then re-close."
 [ "$d3" -eq 1 ] && reason="${reason:+$reason }Your line 1 both asserts and withdraws a verdict, so the operator has to ask a follow-up to learn which it is. Pick the ONE rung that actually governs — if something is parked or is the operator's, that IS the rung (📦 / 👤); if it is immaterial, leave it out entirely. Line 1 answers 'is it safe to close?' once, with no qualifier: a conditional yes (yes if…, yes once…, yes but…) is a no until the condition holds, so answer no and name the condition. A plain no that names what remains is not a hedge."
 [ "$d1" -eq 1 ] && reason="${reason:+$reason }An operator-only step is not an escape hatch from work you could have done: file it only if you genuinely cannot (a credential, sudo, a GUI, or a value judgment that is theirs). If you can run it, run it now. Your close hands the operator work in prose, so the operator-readout block cannot render it and it stays buried in a paragraph. File each operator-only step — \`cc-backlog needs \"<step>\" --class needs-human [--run \"<exact command>\"]\` — then re-close: the rung line reads 👤 when steps are yours, and the steps come from the rendered block, not your prose."
 [ "$d4" -eq 1 ] && reason="${reason:+$reason }Your close names remaining work and then offers it instead of driving it — the operator's standing ruling is that the answer is always yes, so the question costs a round-trip and yields nothing. Every open item resolves to exactly one of three dispositions, never a fourth: DRIVEN (you do it now), DROPPED (you name it in one line and let it go), or BLOCKED on a genuine operator-only gate (credential / sudo / destructive migration / a real value fork), which then IS your line-1 rung. FILING IS THE EXCEPTION, NOT A CO-EQUAL CHOICE — measured 2026-08-25, 432 of 526 live backlog rows (82.1%) exist because a session wrote something down instead of finishing or dropping it, which is the single largest reason the backlog does not drain. Mint a row ONLY if you can answer all three: why THIS session could not do it ('out of scope' is not a reason), why it will still be true after a p90 of 9.3 days in the queue (ideally a \`--falsifier\` so it self-retracts), and who it is for (\`cc-backlog needs\` operator-only, \`cc-backlog add --why-not-now \"needs-credential|needs-human|not-yet-true|no-capacity: <detail>\"\` agent work — an add WITHOUT it stays YOUR loose end in the ledger). Cannot answer all three ⇒ DROP IT. 'Say the word' is not a disposition. Drive it, drop it, or justify the file — then re-close."
```

### A.3 `hooks/lib/session-writes.sh`

```diff
--- a/hooks/lib/session-writes.sh	2026-10-18 20:13:26
+++ b/hooks/lib/session-writes.sh	2026-10-18 21:26:03
@@ -208,6 +208,49 @@
   d="${tp%.jsonl}/subagents"
   [ -d "$d" ] || return 0
   find -H "$d" -type f -name '*.jsonl' -print0 2>/dev/null
+}
+
+# The file-edit tool list, ONCE, for both the streaming reader and the cached one below (the two may
+# never diverge: a reader that recognised three of the four tools would fail in the loud direction).
+_SW_WRITE_TOOLS='^(Write|Edit|MultiEdit|NotebookEdit)$'
+
+# _sw_paths_session_cached <transcript_path> — SESSION scope through a per-file (size, mtime) cache.
+#   Opt-in: _sw_paths uses it only when SESSION_WRITES_CACHE_DIR is set (scripts/wrap-ledger.sh § DRIVE
+#   STATE sets it). Same answer as the streaming read, same three states. Why: a finished subagent's
+#   file never changes again, so after the first Stop only the main transcript and still-running
+#   agents are re-read — the incident's 38 workflow-agent files are 93% of its 32 MB. Fork budget is
+#   fixed (one stat, one jq, two awk): a per-file stat/shasum loop measured SLOWER than no cache.
+_sw_paths_session_cached() {
+  local tp="$1" cdir="$SESSION_WRITES_CACHE_DIR" cf stats stale out rc _sf
+  local -a srcs=("$tp") todo=()
+  while IFS= read -r -d '' _sf; do srcs+=("$_sf"); done < <(_sw_subagent_files "$tp")
+  cf=""; mkdir -p "$cdir" 2>/dev/null && cf="$cdir/$(printf '%s' "$tp" | shasum 2>/dev/null | cut -c1-16)"
+  stats="$(stat -f '%z:%m%t%N' "${srcs[@]}" 2>/dev/null || stat -c '%s:%Y	%n' "${srcs[@]}" 2>/dev/null)" || return 2
+  stale="$(printf '%s\n' "$stats" | awk -F'\t' -v cf="$cf" '
+      BEGIN { if (cf != "") while ((getline l < cf) > 0) { split(l, a, "\t"); if (a[1] == "F") K[a[2]] = a[3] } }
+      NF == 2 { if (!($2 in K) || K[$2] != $1) print $2 }')"
+  while IFS= read -r _sf; do [ -n "$_sf" ] && todo+=("$_sf"); done <<< "$stale"
+  out=""
+  if [ "${#todo[@]}" -gt 0 ]; then
+    # shellcheck disable=SC2016   # jq bindings, not shell expansions
+    out="$(_sw_bounded "${SESSION_WRITES_TIMEOUT_S:-5}" jq -rn --arg tools "$_SW_WRITE_TOOLS" '
+        inputs as $r | input_filename as $f | select($r.type == "assistant")
+        | $r.message.content[]? | select(.type == "tool_use") | select(.name | test($tools))
+        | (.input.file_path // .input.notebook_path // empty) | select(. != "") | ["R", $f, .] | @tsv
+      ' "${todo[@]}" 2>/dev/null)"; rc=$?
+    [ "$rc" -eq 0 ] || return 2
+  fi
+  out="$(printf '%s\n' "$stats" | _SWC_STALE="$stale" _SWC_NEW="$out" awk -F'\t' -v cf="$cf" '
+      BEGIN { n = split(ENVIRON["_SWC_STALE"], s, "\n"); for (i = 1; i <= n; i++) if (s[i] != "") ST[s[i]] = 1
+              if (cf != "") while ((getline l < cf) > 0) { split(l, a, "\t"); if (a[1] == "R" && !(a[2] in ST)) REC[++nr] = l }
+              n = split(ENVIRON["_SWC_NEW"], s, "\n"); for (i = 1; i <= n; i++) if (s[i] != "") REC[++nr] = s[i] }
+      NF == 2 { F[++nf] = "F\t" $2 "\t" $1 }
+      END { if (cf != "") { tmp = cf ".tmp"; for (i = 1; i <= nf; i++) print F[i] > tmp
+                            for (i = 1; i <= nr; i++) print REC[i] > tmp; close(tmp); system("mv -f \"" tmp "\" \"" cf "\" 2>/dev/null") }
+            for (i = 1; i <= nr; i++) { split(REC[i], a, "\t"); print a[3] } }' | sort -u)"
+  [ -n "$out" ] || return 1
+  printf '%s\n' "$out"
+  return 0
 }
 
 # _sw_paths <transcript_path> <true|false turn-bounded>
@@ -232,6 +275,11 @@
   # SESSION scope reads the subagent transcripts too; TURN scope reads the main chain only, because
   # a turn boundary is a position in the MAIN file and the subagent files are separate streams with
   # no shared order. A turn-scoped miss withholds the close certificate, the safe direction there.
+  if [ "$turn" != true ] && [ -n "${SESSION_WRITES_CACHE_DIR:-}" ]; then
+    out="$(_sw_paths_session_cached "$tp")"; rc=$?
+    [ "$rc" -eq 0 ] && printf '%s\n' "$out"
+    return "$rc"
+  fi
   local -a srcs=("$tp")
   local _sf
   if [ "$turn" != true ]; then
@@ -260,7 +308,7 @@
   # `--argjson turn`), so shell expansion is exactly what must NOT happen. ship-land runs
   # `shellcheck` bare, where an info is a hard RED, so this is load-bearing rather than tidy.
   # shellcheck disable=SC2016
-  out="$(_sw_bounded "${SESSION_WRITES_TIMEOUT_S:-5}" jq -rn --argjson turn "$turn" '
+  out="$(_sw_bounded "${SESSION_WRITES_TIMEOUT_S:-5}" jq -rn --argjson turn "$turn" --arg tools "$_SW_WRITE_TOOLS" '
       reduce inputs as $r ([];
         if $turn and ($r.type=="user") and ($r.isSidechain != true)
            and ( (($r.message.content|type) != "array")
@@ -269,7 +317,7 @@
         elif $r.type=="assistant"
         then . + [ $r.message.content[]?
                    | select(.type=="tool_use")
-                   | select(.name|test("^(Write|Edit|MultiEdit|NotebookEdit)$"))
+                   | select(.name|test($tools))
                    | (.input.file_path // .input.notebook_path // empty)
                    | select(. != "") ]
         else . end)
```

### A.4 `scripts/lib/drive-state.awk` (new)

```awk
# drive-state.awk — parse the Drive state convention out of ONE markdown doc (prototype, round 2 C6).
#
# Usage: awk -v doc=<repo-relative path> -v synth=<1|0> -f drive-state.awk <file>
#   synth=1 ⇒ the doc is a research synthesis doc (docs/research/<dir>/{README,REPORT,SYNTHESIS,DESIGN}.md)
#   and carries the PRESENCE duty: no declaration at all ⇒ one UNMARKED record.
#
# THE CONVENTION (exact; nothing here reads headings or prose):
#   · a GFM table whose header row has a cell reading exactly `Drive state` (case-insensitive,
#     `**` stripped) — one token per body row, in that column;
#   · and/or a column-0 doc line `Drive state: <token>[ — note]` — the doc's default, used for an
#     empty cell, and the whole declaration when the doc has no Drive state table.
#   Tokens (first word decides; anything else is OPEN, so a typo cannot clear a row):
#     to drive · driven <sha7-40> · fired <slug> · filed|operator|parked <id12> · decision <id12>
#     · dropped: <reason of >= 2 words> · none (doc line only: the doc recommends nothing)
#   The doc's OWN conviction column is the one content check, and it is structural, not prose:
#     · `dropped` on a row whose Conv./Conviction cell is >= 90 stays OPEN (rule: every 90%+ item
#       is driven), and a doc-level `dropped` stays OPEN when any ranked row is >= 90;
#     · a doc-level `none` stays OPEN when the doc has a table with a conviction column — a doc
#       that ranks changes cannot declare that it recommends nothing.
#   Fenced code blocks are skipped, so a doc QUOTING the convention (this study) is not parsed.
#
# Output, one record per line, tab-separated:
#   UNMARKED <doc>
#   OPEN     <doc> <line> <why>
#   DROPPED  <doc> <line>
#   OK       <doc> <line> none
#   VERIFY   <doc> <line> <sha|bl|dec|slug> <arg>     (the caller batch-verifies; a miss ⇒ OPEN)
function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
function ncells(line, arr,   s) {
  s = line; gsub(/\\\|/, "\001", s)          # an escaped \| inside a cell is not a column break
  sub(/^[ \t]*\|/, "", s); sub(/\|[ \t]*$/, "", s)
  return split(s, arr, /\|/)
}
function hnorm(s) { s = tolower(trim(s)); gsub(/\*\*/, "", s); return trim(s) }
function convof(s,   m) {                  # first 2-3 digit integer in the cell, or -1
  if (match(s, /[0-9][0-9][0-9]?/)) { m = substr(s, RSTART, RLENGTH) + 0; if (m <= 100) return m }
  return -1
}
function classify(tok, ln, conv, isdoc,   w, rest, n, parts) {
  tok = trim(tok); gsub(/`/, "", tok); gsub(/\*\*/, "", tok)
  if (tok == "") {
    if (doctok != "" && tolower(doctok) != "none") return classify(doctok, ln, conv, 0)
    print "OPEN\t" doc "\t" ln "\tno-drive-state"; return
  }
  w = tolower(tok); sub(/[ \t].*$/, "", w)
  rest = tok; sub(/^[^ \t]+[ \t]*/, "", rest); rest = trim(rest)
  if (tolower(tok) ~ /^to drive([ \t]|$)/) { print "OPEN\t" doc "\t" ln "\tto-drive"; return }
  if (w == "none") {
    if (!isdoc) { print "OPEN\t" doc "\t" ln "\tnone-in-a-row"; return }
    if (ranked) { print "OPEN\t" doc "\t" ln "\tnone-over-a-ranked-table"; return }
    print "OK\t" doc "\t" ln "\tnone"; return
  }
  if (w == "dropped:" || w == "dropped") {
    sub(/^:[ \t]*/, "", rest); n = split(rest, parts, /[ \t]+/)
    if (n < 2) { print "OPEN\t" doc "\t" ln "\tdropped-without-reason"; return }
    if (conv >= 90) { print "OPEN\t" doc "\t" ln "\tdropped-at-conviction-" conv; return }
    print "DROPPED\t" doc "\t" ln; return
  }
  sub(/[ \t].*$/, "", rest)   # the argument is ONE word; a note may follow it
  if (w == "driven") {
    if (rest ~ /^[0-9a-f]+$/ && length(rest) >= 7 && length(rest) <= 40) { print "VERIFY\t" doc "\t" ln "\tsha\t" rest; return }
    print "OPEN\t" doc "\t" ln "\tdriven-without-sha"; return
  }
  if (w == "filed" || w == "operator" || w == "parked") {
    if (rest ~ /^[0-9a-f]+$/ && length(rest) == 12) { print "VERIFY\t" doc "\t" ln "\tbl\t" rest; return }
    print "OPEN\t" doc "\t" ln "\t" w "-without-id"; return
  }
  if (w == "decision") {
    if (rest ~ /^[0-9a-f]+$/ && length(rest) == 12) { print "VERIFY\t" doc "\t" ln "\tdec\t" rest; return }
    print "OPEN\t" doc "\t" ln "\tdecision-without-id"; return
  }
  if (w == "fired") {
    if (rest ~ /^[A-Za-z0-9][A-Za-z0-9._-]*$/) { print "VERIFY\t" doc "\t" ln "\tslug\t" rest; return }
    print "OPEN\t" doc "\t" ln "\tfired-without-slug"; return
  }
  print "OPEN\t" doc "\t" ln "\tunknown-token"
}
BEGIN { infence = 0; intab = 0; col = 0; ccol = 0; hdr = ""; hdrln = 0; tables = 0
        doctok = ""; doclnno = 0; nrows = 0; ranked = 0; maxconv = -1 }
/^[ \t]*(```|~~~)/ { infence = !infence; intab = 0; next }
infence { next }
/^Drive state:[ \t]*/ {
  t = $0; sub(/^Drive state:[ \t]*/, "", t); sub(/[ \t]+(—|--).*$/, "", t)
  doctok = trim(t); doclnno = NR; next
}
/^[ \t]*\|/ {
  if (intab) {                          # a body row of the current table
    if ($0 ~ /^[ \t]*\|[ \t:|-]+\|?[ \t]*$/) next
    n = ncells($0, c); cv = (ccol > 0 && ccol <= n) ? convof(c[ccol]) : -1
    if (cv > maxconv) maxconv = cv
    if (col > 0) ROWS[++nrows] = NR "\t" ((col <= n) ? c[col] : "") "\t" cv
    next
  }
  if (hdr != "" && NR == hdrln + 1 && $0 ~ /^[ \t]*\|[ \t:|-]+\|?[ \t]*$/) {
    n = ncells(hdr, h); col = 0; ccol = 0
    for (i = 1; i <= n; i++) {
      x = hnorm(h[i])
      if (x == "drive state") col = i
      if (x ~ /^(conv\.?|conviction|confidence)( \(%\))?$/) ccol = i
    }
    if (col > 0) tables++
    if (ccol > 0) ranked = 1
    intab = 1; hdr = ""; next
  }
  hdr = $0; hdrln = NR; next
}
{ intab = 0; col = 0; ccol = 0; hdr = "" }
END {
  if (tables == 0 && doctok == "") { if (synth == 1) print "UNMARKED\t" doc; exit }
  for (r = 1; r <= nrows; r++) { split(ROWS[r], rr, "\t"); classify(rr[2], rr[1], rr[3] + 0, 0) }
  if (tables == 0) classify(doctok, doclnno, maxconv, 1)
}
```

### A.5 `tests/wrap-ledger-drive-state.bats` (new; `setup()` = `tests/wrap-ledger.bats:10-81` verbatim (its closing brace dropped), then the lines below)

```bash
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"; : > "$CC_BACKLOG_FILE"
  export WRAP_RESEARCH=off
  export WRAP_DRIVE_CACHE_DIR="$BATS_TEST_TMPDIR/swc"   # the per-file session-writes cache, hermetic
  # The term's own bound (default 3 s) is not under test here, and a gate run in the utility band at
  # load 300-500 measured over it (DRIVE_SRC=error on the positives); the FAIL-OPEN case pins the bound.
  export WRAP_DRIVE_TIMEOUT_S=30
  # The transcript lives OUTSIDE WRAP_PROJECT_ROOTS, so the no-transcript case cannot rediscover it.
  TP="$BATS_TEST_TMPDIR/tx/$SID.jsonl"; mkdir -p "${TP%/*}"; : > "$TP"
  tx_start "$(( $(date +%s) - 3600 ))"     # the session began an hour ago (its first stamped record)
  TOP="$(pwd -P)"
}

field() { printf '%s' "$1" | grep -E "^$2=" | head -1 | cut -d= -f2-; }
ok_state() {
  local dod="$BATS_TEST_TMPDIR/dod-ok.md"
  printf -- '- [x] item one\n- [x] item two\n' > "$dod"
  export WRAP_DOD_FILE="$dod"
  git rev-parse HEAD > "$(git rev-parse --git-common-dir)/gate-green"
}
# The session's first stamped record — the term reads "when did this session begin" from it.
tx_start() { jq -nc --arg t "$(date -u -r "$1" +%Y-%m-%dT%H:%M:%S.000Z 2>/dev/null || date -u -d "@$1" +%Y-%m-%dT%H:%M:%S.000Z)" \
               '{type:"user",timestamp:$t,message:{content:"start"}}' > "$TP"; }
# A Write tool_use and ITS OWN tool_result, joined on id ($3 = the result text's verb).
tx_write() {  # $1=file  $2=abs path  $3=created|updated  $4=id
  local res
  if [ "$3" = created ]; then res="File created successfully at: $2"; else res="The file $2 has been updated successfully."; fi
  jq -nc --arg id "$4" --arg p "$2" '{type:"assistant",message:{content:[{type:"tool_use",id:$id,name:"Write",input:{file_path:$p,content:"x"}}]}}' >> "$1"
  jq -nc --arg id "$4" --arg r "$res" '{type:"user",message:{content:[{type:"tool_result",tool_use_id:$id,content:$r}]}}' >> "$1"
}
# Land a doc on trunk (clean + landed = the ✅-eligible path this term lives on).
land_doc() {  # $1=repo-relative path  stdin=content
  mkdir -p "$(dirname "$1")"; cat > "$1"; git add "$1"; git commit -q -m "doc $1"; git push -q origin main
}
RECS='| # | Change | Conv. | Drive state |
|---|---|---|---|
| 1 | fix the event name | 95 | to drive |
| 2 | dispatcher v2 | 88 | to drive |
| 3 | token cuts | 85 | to drive |'

# ── THE INCIDENT SHAPE: a research synthesis this session created, with no declaration ──
@test "drive-state: a synthesis README this session CREATED with no Drive state ⇒ 🔧, DRIVE_UNMARKED=1" {
  ok_state; export WRAP_SESSION_ID="$SID" WRAP_TRANSCRIPT="$TP"
  printf '# Study\n\n## 5. Implementation waves\n\n%s\n' "$(printf '%s\n' "$RECS" | sed 's/ Drive state |/|/; s/ to drive |//; s/---|$//')" | land_doc docs/research/s-2026/README.md
  tx_write "$TP" "$TOP/docs/research/s-2026/README.md" created t1
  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" RUNG)" = "🔧" ]
  [ "$(field "$output" DRIVE_UNMARKED)" = "1" ]
  [ "$(field "$output" DRIVE_SRC)" != "error" ]
  printf '%s' "$(field "$output" READOUT)" | grep -q 'carries no Drive state'
  printf '%s' "$(field "$output" DRIVE_DOCS)" | grep -q 'docs/research/s-2026/README.md'
}

@test "drive-state CONTROL: the same README, landed BEFORE this session began and only edited by it ⇒ ✅" {
  ok_state; export WRAP_SESSION_ID="$SID" WRAP_TRANSCRIPT="$TP"
  printf '# Study\n\n## 5. Implementation waves\n\n- wave 1\n' | land_doc docs/research/s-2026/README.md
  tx_start "$(( $(date +%s) + 120 ))"      # this session began after the doc landed: an old doc
  tx_write "$TP" "$TOP/docs/research/s-2026/README.md" updated t1
  run bash "$LEDGER" --machine
  [ "$(field "$output" RUNG)" = "✅" ]
  [ "$(field "$output" DRIVE_UNMARKED)" = "0" ]
}

@test "drive-state: a doc another session landed in this worktree, which this session never wrote ⇒ ✅" {
  ok_state; export WRAP_SESSION_ID="$SID" WRAP_TRANSCRIPT="$TP"
  printf '# Study\n\n- wave 1\n' | land_doc docs/research/s-2026/README.md
  tx_write "$TP" "$TOP/docs/research/other-2026/notes.md" created t1
  run bash "$LEDGER" --machine
  [ "$(field "$output" RUNG)" = "✅" ]
  [ "$(field "$output" DRIVE_UNMARKED)" = "0" ]
}

@test "drive-state: a creation recorded ONLY in a workflow agent's transcript still counts (subagents/**)" {
  ok_state; export WRAP_SESSION_ID="$SID" WRAP_TRANSCRIPT="$TP"
  printf '# Study\n\n- wave 1\n' | land_doc docs/research/s-2026/REPORT.md
  sub="${TP%.jsonl}/subagents/workflows/wf_1/agent-a1.jsonl"; mkdir -p "${sub%/*}"
  tx_write "$sub" "$TOP/docs/research/s-2026/REPORT.md" created w1
  run bash "$LEDGER" --machine
  [ "$(field "$output" RUNG)" = "🔧" ]
  [ "$(field "$output" DRIVE_UNMARKED)" = "1" ]
}

@test "drive-state: a MENTION of the doc (a Bash result naming it) is not a write ⇒ ✅" {
  ok_state; export WRAP_SESSION_ID="$SID" WRAP_TRANSCRIPT="$TP"
  printf '# Study\n\n- wave 1\n' | land_doc docs/research/s-2026/README.md
  jq -nc '{type:"assistant",message:{content:[{type:"tool_use",id:"b1",name:"Bash",input:{command:"grep …"}}]}}' >> "$TP"
  jq -nc --arg r "File created successfully at: $TOP/docs/research/s-2026/README.md" \
     '{type:"user",message:{content:[{type:"tool_result",tool_use_id:"b1",content:$r}]}}' >> "$TP"
  run bash "$LEDGER" --machine
  [ "$(field "$output" RUNG)" = "✅" ]
  [ "$(field "$output" DRIVE_UNMARKED)" = "0" ]
}

@test "drive-state: an axis/slot doc (not a synthesis) with no declaration carries no duty ⇒ ✅" {
  ok_state; export WRAP_SESSION_ID="$SID" WRAP_TRANSCRIPT="$TP"
  printf '# Axis 1\n\n## Recommendations\n\n- do X\n' | land_doc docs/research/s-2026/A1-census.md
  tx_write "$TP" "$TOP/docs/research/s-2026/A1-census.md" created t1
  run bash "$LEDGER" --machine
  [ "$(field "$output" RUNG)" = "✅" ]
}

# ── THE CONVENTION APPLIED: rows count until each carries a verified disposition ──
@test "drive-state: three 'to drive' rows ⇒ 🔧, DRIVE_OPEN=3, the readout names the doc" {
  ok_state; export WRAP_SESSION_ID="$SID" WRAP_TRANSCRIPT="$TP"
  printf '# Study\n\n%s\n' "$RECS" | land_doc docs/research/s-2026/README.md
  tx_write "$TP" "$TOP/docs/research/s-2026/README.md" created t1
  run bash "$LEDGER" --machine
  [ "$(field "$output" RUNG)" = "🔧" ]
  [ "$(field "$output" DRIVE_OPEN)" = "3" ]
  printf '%s' "$(field "$output" READOUT)" | grep -q 'Research only'
}

@test "drive-state CONTROL: every row disposed and verified (sha, backlog id, dropped) ⇒ ✅, DRIVE_DROPPED=1" {
  ok_state; export WRAP_SESSION_ID="$SID" WRAP_TRANSCRIPT="$TP"
  sha="$(git rev-parse --short=9 HEAD)"
  printf '{"id":"abcdef123456","status":"open"}\n' >> "$CC_BACKLOG_FILE"
  printf '# Study\n\n%s\n' "$RECS" | sed "s/| 95 | to drive |/| 95 | driven $sha |/; s/| 88 | to drive |/| 88 | filed abcdef123456 |/; s/| 85 | to drive |/| 85 | dropped: superseded by row 2 |/" \
    | land_doc docs/research/s-2026/README.md
  tx_write "$TP" "$TOP/docs/research/s-2026/README.md" created t1
  run bash "$LEDGER" --machine
  [ "$(field "$output" DRIVE_OPEN)" = "0" ]
  [ "$(field "$output" DRIVE_DROPPED)" = "1" ]
  [ "$(field "$output" RUNG)" = "✅" ]
}

@test "drive-state: a fake sha, an id the backlog never minted, a bare 'parked' ⇒ each stays OPEN" {
  ok_state; export WRAP_SESSION_ID="$SID" WRAP_TRANSCRIPT="$TP"
  printf '# Study\n\n%s\n' "$RECS" | sed "s/| 95 | to drive |/| 95 | driven deadbeef1 |/; s/| 88 | to drive |/| 88 | filed 0123456789ab |/; s/| 85 | to drive |/| 85 | parked later |/" \
    | land_doc docs/research/s-2026/README.md
  tx_write "$TP" "$TOP/docs/research/s-2026/README.md" created t1
  run bash "$LEDGER" --machine
  [ "$(field "$output" DRIVE_OPEN)" = "3" ]
  [ "$(field "$output" RUNG)" = "🔧" ]
}

@test "drive-state: a REBASED-AWAY sha (an object here, not on trunk) still verifies — landedness is UNLANDED's" {
  ok_state; export WRAP_SESSION_ID="$SID" WRAP_TRANSCRIPT="$TP"
  git checkout -q -b side; echo s > s.txt; git add s.txt; git commit -q -m side; old="$(git rev-parse --short=9 HEAD)"
  git checkout -q main
  printf '# Study\n\n%s\n' "$RECS" | sed "s/| 95 | to drive |/| 95 | driven $old |/; s/| 88 | to drive |/| 88 | dropped: folded into row 1 |/; s/| 85 | to drive |/| 85 | dropped: folded into row 1 |/" \
    | land_doc docs/research/s-2026/README.md
  tx_write "$TP" "$TOP/docs/research/s-2026/README.md" created t1
  run bash "$LEDGER" --machine
  [ "$(field "$output" DRIVE_OPEN)" = "0" ]
  [ "$(field "$output" RUNG)" = "✅" ]
}

# ── LAUNDERING: the doc's own conviction column is the one content check ──
@test "drive-state: 'dropped' on a row the doc ranks at 95 stays OPEN (every 90%+ item is driven)" {
  ok_state; export WRAP_SESSION_ID="$SID" WRAP_TRANSCRIPT="$TP"
  printf '# Study\n\n%s\n' "$RECS" | sed 's/| to drive |/| dropped: research only |/' | land_doc docs/research/s-2026/README.md
  tx_write "$TP" "$TOP/docs/research/s-2026/README.md" created t1
  run bash "$LEDGER" --machine
  [ "$(field "$output" DRIVE_OPEN)" = "1" ]
  [ "$(field "$output" DRIVE_DROPPED)" = "2" ]
  [ "$(field "$output" RUNG)" = "🔧" ]
}

@test "drive-state: 'Drive state: none' over a ranked table stays OPEN; over a doc that ranks nothing ⇒ ✅" {
  ok_state; export WRAP_SESSION_ID="$SID" WRAP_TRANSCRIPT="$TP"
  printf '# Study\n\nDrive state: none — research only\n\n%s\n' "$(printf '%s\n' "$RECS" | sed 's/ Drive state |/|/; s/ to drive |//; s/---|$//')" \
    | land_doc docs/research/s-2026/README.md
  tx_write "$TP" "$TOP/docs/research/s-2026/README.md" created t1
  run bash "$LEDGER" --machine
  [ "$(field "$output" RUNG)" = "🔧" ]
  [ "$(field "$output" DRIVE_OPEN)" = "1" ]
  printf '# Probe\n\nDrive state: none — a measurement; it recommends no change\n\n| metric | value |\n|---|---|\n| p50 | 3 s |\n' \
    | land_doc docs/research/p-2026/REPORT.md
  tx_write "$TP" "$TOP/docs/research/p-2026/REPORT.md" created t2
  git rm -q docs/research/s-2026/README.md; git commit -q -m rm; git push -q origin main
  run bash "$LEDGER" --machine
  [ "$(field "$output" DRIVE_OPEN)" = "0" ]
  [ "$(field "$output" RUNG)" = "✅" ]
}

@test "drive-state: a doc QUOTING the convention inside a code fence is not declared by the quote" {
  ok_state; export WRAP_SESSION_ID="$SID" WRAP_TRANSCRIPT="$TP"
  printf '# Study\n\n```\nDrive state: none\n```\n\n- wave 1\n' | land_doc docs/research/s-2026/README.md
  tx_write "$TP" "$TOP/docs/research/s-2026/README.md" created t1
  run bash "$LEDGER" --machine
  [ "$(field "$output" DRIVE_UNMARKED)" = "1" ]
}

# ── RANKING: ⛔ and the store-row arms govern; 👤 and ✅ never certify over an undriven doc ──
mk_backlog_stub2() {
  local out="$BATS_TEST_TMPDIR/cc-backlog-stub2"
  { printf '#!/usr/bin/env bash\n'
    printf 'case "$*" in *--all*) printf "%%s\\\\n" '"'"'%s'"'"' ;; *) printf "%%s\\\\n" '"'"'%s'"'"' ;; esac\n' "$1" "$2"
  } > "$out"
  chmod +x "$out"; printf '%s' "$out"
}
blocked_json() {
  printf '[{"id":"B-77","project":"claude-infrastructure","title":"%s","status":"blocked","needs":"%s","run":"launchctl bootstrap gui/501 ~/Library/LaunchAgents/x.plist","session":"%s"}]' \
    "activate the dispatcher plist" "load the plist (operator-only)" "$1"
}
@test "drive-state OUTRANKS 👤: my filed operator step alone ⇒ 👤; beside an undriven doc I created ⇒ 🔧" {
  ok_state; export WRAP_SESSION_ID="$SID" WRAP_TRANSCRIPT="$TP"
  CC_BACKLOG_BIN="$(mk_backlog_stub2 '[]' "$(blocked_json "$SID")")"; export CC_BACKLOG_BIN
  run bash "$LEDGER" --machine
  [ "$(field "$output" RUNG)" = "👤" ]
  printf '# Study\n\n%s\n' "$RECS" | land_doc docs/research/s-2026/README.md
  tx_write "$TP" "$TOP/docs/research/s-2026/README.md" created t1
  run bash "$LEDGER" --machine
  [ "$(field "$output" RUNG)" = "🔧" ]
  [ "$(field "$output" YOURS)" = "1" ]
}

# ── FAIL-OPEN: an unresolvable sensor never manufactures a rung ──
@test "drive-state FAIL-OPEN: no transcript ⇒ DRIVE_SRC=none; WRAP_DRIVE=off ⇒ n-a; neither is a 🔧" {
  ok_state; export WRAP_SESSION_ID="$SID"
  printf '# Study\n\n- wave 1\n' | land_doc docs/research/s-2026/README.md
  run bash "$LEDGER" --machine
  [ "$(field "$output" DRIVE_SRC)" = "none" ]
  [ "$(field "$output" RUNG)" = "✅" ]
  export WRAP_TRANSCRIPT="$TP"; tx_write "$TP" "$TOP/docs/research/s-2026/README.md" created t1
  WRAP_DRIVE=off run bash "$LEDGER" --machine
  [ "$(field "$output" DRIVE_SRC)" = "n-a" ]
  [ "$(field "$output" RUNG)" = "✅" ]
}

@test "drive-state: computed only on the ✅-eligible path (a dirty tree reads DRIVE_SRC=skip)" {
  ok_state; export WRAP_SESSION_ID="$SID" WRAP_TRANSCRIPT="$TP"
  printf '# Study\n\n- wave 1\n' | land_doc docs/research/s-2026/README.md
  tx_write "$TP" "$TOP/docs/research/s-2026/README.md" created t1
  echo dirt >> base.txt
  run bash "$LEDGER" --machine
  [ "$(field "$output" RUNG)" = "🔧" ]
  [ "$(field "$output" DRIVE_SRC)" = "skip" ]
}

@test "drive-state FAIL-OPEN: the term's bound expiring ⇒ DRIVE_SRC=error, never a 🔧" {
  ok_state; export WRAP_SESSION_ID="$SID" WRAP_TRANSCRIPT="$TP"
  printf '# Study\n\n- wave 1\n' | land_doc docs/research/s-2026/README.md
  tx_write "$TP" "$TOP/docs/research/s-2026/README.md" created t1
  WRAP_DRIVE_TIMEOUT_S=0.01 run bash "$LEDGER" --machine
  [ "$(field "$output" DRIVE_SRC)" = "error" ]
  [ "$(field "$output" RUNG)" = "✅" ]
}

@test "drive-state: ⛔ still governs — a convicted class-C packet beside an undriven doc ⇒ ⛔, term skipped" {
  ok_state; export WRAP_SESSION_ID="$SID" WRAP_TRANSCRIPT="$TP"
  printf '# Study\n\n- wave 1\n' | land_doc docs/research/s-2026/README.md
  tx_write "$TP" "$TOP/docs/research/s-2026/README.md" created t1
  stub="$BATS_TEST_TMPDIR/cc-decide-stub"
  printf '#!/usr/bin/env bash\nprintf %%s %q\n' "[{\"id\":\"abcdefabcdef\",\"class\":\"C\",\"status\":\"open\",\"session_sid\":\"$SID\",\"question\":\"q\",\"conviction\":90,\"receipt\":\"r\"}]" > "$stub"; chmod +x "$stub"
  export CC_DECIDE_BIN="$stub"
  run bash "$LEDGER" --machine
  [ "$(field "$output" RUNG)" = "⛔" ]
  [ "$(field "$output" DRIVE_SRC)" = "skip" ]
}
```

### A.6 `tests/completion-assert-drive-state.bats` (new; lines 1-161 = `tests/completion-assert.bats:1-161`, then `mkledger` = `:1145-1152`, then the lines below)

```bash
# ── DRIVE STATE (round 2 C6) — the ledger's DRIVE_OPEN / DRIVE_UNMARKED reach the done-claim ──
# The incident close, verbatim (transcript 5759497b, 14:27:47Z).
INCIDENT_CLOSE='✅ Good to close: yes. Nothing of mine is open. Follow-on: the implementation waves in README §5 haven'"'"'t started, because this pass was research only.'
CA_DRIVE_BASE=(DIRTY=0 DIRTY_N=0 UNLANDED=0 AHEAD=0 REMAINDER=0 TRUNK=origin/main BLOCKED=0)

@test "drive-state: the incident close over DRIVE_UNMARKED=1 ⇒ FIRE, class undriven, names the doc" {
  WRAP_LEDGER_BIN="$(mkledger dr1 "${CA_DRIVE_BASE[@]}" RUNG=🔧 DRIVE_OPEN=0 DRIVE_UNMARKED=1 \
     'DRIVE_DOCS=docs/research/startup-hooks-2026-10-18/README.md (no Drive state declaration)')"; export WRAP_LEDGER_BIN
  run run_ca "$(mkfix "$INCIDENT_CLOSE")" "$BATS_TEST_TMPDIR" "dr-1"
  [ "$status" -eq 0 ]; fired "$output"
  printf '%s' "$output" | /usr/bin/grep -q 'carries no Drive state'
  printf '%s' "$output" | /usr/bin/grep -q 'startup-hooks-2026-10-18/README.md'
  /usr/bin/grep -q '"class":"undriven"' "$COMPLETION_IDL"
}

@test "drive-state: DRIVE_OPEN=6 ⇒ FIRE naming 'research only is not a disposition'" {
  WRAP_LEDGER_BIN="$(mkledger dr2 "${CA_DRIVE_BASE[@]}" RUNG=🔧 DRIVE_OPEN=6 DRIVE_UNMARKED=0 \
     'DRIVE_DOCS=docs/research/s/README.md (6 open)')"; export WRAP_LEDGER_BIN
  run run_ca "$(mkfix "$INCIDENT_CLOSE")" "$BATS_TEST_TMPDIR" "dr-2"
  [ "$status" -eq 0 ]; fired "$output"
  printf '%s' "$output" | /usr/bin/grep -q 'is not a disposition'
  printf '%s' "$output" | /usr/bin/grep -q '6 recommendation row(s)'
}

@test "drive-state CONTROL: the same close over DRIVE_OPEN=0 DRIVE_UNMARKED=0 and RUNG=✅ ⇒ no ledger fire" {
  WRAP_LEDGER_BIN="$(mkledger dr3 "${CA_DRIVE_BASE[@]}" RUNG=✅ DRIVE_OPEN=0 DRIVE_UNMARKED=0)"; export WRAP_LEDGER_BIN
  run run_ca "$(mkfix "✅ Good to close: yes. Nothing of mine is open.")" "$BATS_TEST_TMPDIR" "dr-3"
  [ "$status" -eq 0 ]
  ! /usr/bin/grep -q '"class":"undriven"' "$COMPLETION_IDL"
  ! printf '%s' "$output" | /usr/bin/grep -q 'Drive state'
}

@test "drive-state STARVATION: three 📦 fires spend the assert cap; the terminal undriven close STILL fires" {
  export COMPLETION_MAX=3
  local w; w="$(mkrepo_unlanded dr4)"
  unset WRAP_LEDGER_BIN    # the REAL ledger on an unlanded tree: the incident's 13:18-13:19Z 📦 fires
  run run_ca "$(mkfix "Everything is done.")" "$w" "dr-4"; fired "$output"
  run run_ca "$(mkfix "All complete, nothing left to do.")" "$w" "dr-4"; fired "$output"
  run run_ca "$(mkfix "Finished — that was the main ask.")" "$w" "dr-4"; fired "$output"
  run run_ca "$(mkfix "Done, truly done.")" "$w" "dr-4"; [ -z "$output" ]   # assert spent (the 14:27:50Z state)
  /usr/bin/grep -q '"reason":"capped:3>=3"' "$COMPLETION_IDL"
  WRAP_LEDGER_BIN="$(mkledger dr4d "${CA_DRIVE_BASE[@]}" RUNG=🔧 DRIVE_OPEN=0 DRIVE_UNMARKED=1 'DRIVE_DOCS=docs/research/s/README.md (no Drive state declaration)')"; export WRAP_LEDGER_BIN
  run run_ca "$(mkfix "$INCIDENT_CLOSE")" "$w" "dr-4"
  [ "$status" -eq 0 ]; fired "$output"
  /usr/bin/grep -q '"class":"undriven"' "$COMPLETION_IDL"
}

@test "drive-state: the undriven budget is itself a HARD cap (COMPLETION_UNDRIVEN_MAX)" {
  export COMPLETION_UNDRIVEN_MAX=1
  WRAP_LEDGER_BIN="$(mkledger dr5 "${CA_DRIVE_BASE[@]}" RUNG=🔧 DRIVE_OPEN=2 DRIVE_UNMARKED=0 'DRIVE_DOCS=d (2 open)')"; export WRAP_LEDGER_BIN
  run run_ca "$(mkfix "$INCIDENT_CLOSE")" "$BATS_TEST_TMPDIR" "dr-5"; fired "$output"
  run run_ca "$(mkfix "✅ Good to close: yes — all done.")" "$BATS_TEST_TMPDIR" "dr-5"; [ -z "$output" ]
  /usr/bin/grep -q '"reason":"capped:undriven:1>=1"' "$COMPLETION_IDL"
}

@test "drive-state: beside ANOTHER ledger fact the fire keeps the assert class (no existing case changes class)" {
  WRAP_LEDGER_BIN="$(mkledger dr6 "${CA_DRIVE_BASE[@]}" RUNG=🔧 FILED_MINE=1 DRIVE_OPEN=1 DRIVE_UNMARKED=0 'DRIVE_DOCS=d (1 open)')"; export WRAP_LEDGER_BIN
  run run_ca "$(mkfix "$INCIDENT_CLOSE")" "$BATS_TEST_TMPDIR" "dr-6"
  [ "$status" -eq 0 ]; fired "$output"
  /usr/bin/grep -q '"class":"assert"' "$COMPLETION_IDL"
}
```

### A.7 `tests/session-writes-cache.bats` (new; `setup`/`tx` = `tests/session-writes.bats:37-70`, `_sub_tx` = `:249-253`, then the tests below)

```bash
@test "CACHE parity: the cached session scope equals the streaming one (main + subagent), cold and warm" {
  mkdir -p "$W"; t="$(tx "$BATS_TEST_TMPDIR/s.jsonl" "$W/a.ts" "$W/b.md")"
  _sub_tx "$t" "workflows/wf_1" "$W/c.md"
  plain="$(bash -c '. "$1"; session_writes_paths "$2"' _ "$LIB" "$t")"
  cold="$(SESSION_WRITES_CACHE_DIR="$BATS_TEST_TMPDIR/c" bash -c '. "$1"; session_writes_paths "$2"' _ "$LIB" "$t")"
  warm="$(SESSION_WRITES_CACHE_DIR="$BATS_TEST_TMPDIR/c" bash -c '. "$1"; session_writes_paths "$2"' _ "$LIB" "$t")"
  [ -n "$plain" ]; [ "$plain" = "$cold" ]; [ "$plain" = "$warm" ]
  [ "$(printf '%s\n' "$warm" | grep -c .)" -eq 3 ]
}

@test "CACHE invalidation: a transcript that GREW is re-read (a new write appears)" {
  mkdir -p "$W"; t="$(tx "$BATS_TEST_TMPDIR/s.jsonl" "$W/a.ts")"
  SESSION_WRITES_CACHE_DIR="$BATS_TEST_TMPDIR/c" bash -c '. "$1"; session_writes_paths "$2"' _ "$LIB" "$t" >/dev/null
  printf '%s\n' "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"tool_use\",\"name\":\"Write\",\"input\":{\"file_path\":\"$W/new.md\"}}]}}" >> "$t"
  out="$(SESSION_WRITES_CACHE_DIR="$BATS_TEST_TMPDIR/c" bash -c '. "$1"; session_writes_paths "$2"' _ "$LIB" "$t")"
  printf '%s\n' "$out" | grep -qxF "$W/new.md"
}

@test "CACHE three states: none stays rc 1, an absent transcript stays rc 2 (never 'none')" {
  t="$(tx "$BATS_TEST_TMPDIR/ro.jsonl")"
  run env SESSION_WRITES_CACHE_DIR="$BATS_TEST_TMPDIR/c" bash -c '. "$1"; session_writes_paths "$2"' _ "$LIB" "$t"
  [ "$status" -eq 1 ]
  run env SESSION_WRITES_CACHE_DIR="$BATS_TEST_TMPDIR/c" bash -c '. "$1"; session_writes_paths "$2"' _ "$LIB" "$BATS_TEST_TMPDIR/absent.jsonl"
  [ "$status" -eq 2 ]
}

@test "CACHE is opt-in: with SESSION_WRITES_CACHE_DIR unset nothing is written anywhere" {
  mkdir -p "$W"; t="$(tx "$BATS_TEST_TMPDIR/s.jsonl" "$W/a.ts")"
  export TMPDIR="$BATS_TEST_TMPDIR/tmp"; mkdir -p "$TMPDIR"
  bash -c '. "$1"; session_writes_paths "$2"' _ "$LIB" "$t" >/dev/null
  [ -z "$(ls -A "$TMPDIR")" ]
}
```
