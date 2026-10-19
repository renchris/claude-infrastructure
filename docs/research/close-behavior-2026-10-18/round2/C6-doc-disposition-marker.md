# C6: a machine-readable disposition marker on research recommendations (the doc side)

Round 2, 2026-10-18. Candidate C6 from axis 04 §4, axis 05 P2 and axis 10 §4 (and their skeptic
verdicts). Read-only in the repo: the only repo write is this file. Prototypes, copies and scratch
output live under `/tmp/r2-C6/`. Every number is labelled **[M]** (measured, with the command) or
**[E]** (estimated, with the method). Line numbers are from the worktree at `f12dd4b12`; for every
file this design touches, `git diff HEAD origin/main` is empty except `CLAUDE.global.slim.md`
(1 line), so they hold on trunk too [M: `git diff --stat HEAD origin/main -- <files>`].

Status: in progress (written incrementally).

## 0. Setup facts

- Load during this pass: 103-132 one-minute average at 20:06 CDT [M: `uptime`].
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
have been silent on the incident (§4.1). To catch anything it needs a **presence duty** that does
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
- A typo fixer that starts after the doc landed is excluded by construction (test 2 in §5).
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
| the same with the cache, warm (every later Stop; finished agents' files are immutable) | | **+0.28 to +0.41 s** (0.54-0.62 s → 0.90-1.02 s) | **+0.20 to +0.25 s** |

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
   - The per-Stop cost is small in CPU: +0.03 s on the fast path, +0.20-0.25 s warm (measured).
   - Wall time balloons with load. At load 525-555 the whole ledger took 2.1-3.0 s, against
     1.35-2.24 s with `WRAP_DRIVE=off` (measured).
   - completion-assert is already at its 5 s Stop timeout on 18.1% of runs over 30 days (README
     F29). Any added wall time raises that rate for research sessions after they land.
   - The term's own bound (3 s) **was exceeded inside bats in the utility QoS band at load
     300-500**. Positives then read `DRIVE_SRC=error`, which is fail-open and silent (§6, the first
     batch). Stop hooks run at normal QoS, and there the replay never exceeded the bound in 22 runs
     at load 300-555. Even so, the term can go silent in exactly the overload periods this box
     lives in.
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
