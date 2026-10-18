# Axis 10: detector design and false-positive measurement (2026-10-18)

Goal: a deterministic check that answers "this session left drivable follow-on undriven" and stays
silent when nothing drivable remains. This study was read-only. The prototypes are in
`/tmp/detector-proto/` (not in the repo): `classify.py` (v2 heuristic), `classify3.py` (v3 heuristic),
`verify.py` (git-log audit), `signals_bc.py`, `signals_c2.py`, `refine_b.py` (final-message signals),
and `drive_check.py` (the exact checker for the proposed convention). Raw outputs are in
`/tmp/detector-proto/out/`.

## 0. Answer

1. **A heuristic content classifier (signal A as briefed) cannot be the gate.** Over the corpus
   (55 research READMEs and 122 plans), the conviction-gated mode flags only 2-3 docs besides the
   incident doc, and every one of them is a false positive. The loose mode flags 22-49 docs, and
   in a hand-audited sample of 15 flags only 1 was a true positive (6.7%). The cause is structural.
   The corpus records "driven" in a *separate* ledger that names the row id (task tables, status
   logs, "what landed" tables, header Status lines), not on the row itself, and free-text status
   words ("dropped", "live", "fixed") appear inside design prose. Both mislead any parser.
   The heuristic does flag the incident doc in every configuration (measured).
2. **An exact check needs a marker on the row.** The proposed convention: one `Drive state` column
   per actionable table, with a closed vocabulary (`driven <sha>` / `fired <session>` /
   `filed <id>` / `operator <id>` / `decision <id>` / `parked <condition>` / `dropped <why>` /
   `rejected <why>`). Against it, `drive_check.py` is exact on the fixtures (§4): empty cells flag,
   a fully marked table is silent (rc 0, no output), and a bad sha or a park with no condition is
   flagged when it verifies against the stores.
3. **Session scoping already exists.** `hooks/lib/session-writes.sh` reads the main transcript
   plus `<session>/subagents/**` (`:74-81`, `:198-210`). In the incident, the README was written by
   a Dynamic-Workflow agent
   (`~/.claude-secondary/projects/…/5759497b…/subagents/workflows/wf_7c1e0d3e-19e/`), and the lead
   only `git add`ed it through Bash. The oracle still sees it (measured: the README `Write` is in a
   secondary-store workflow agent file). The lead's own transcript has no Write or Edit of it
   (measured: the grep of `"name":"Write"…file_path` finds only INCIDENT.md and two /tmp prompt
   files).
4. **Signals B and C are useful only as advisories.** Raw B (a done-verdict whose follow-on clause
   is non-empty) fires on 25 of 1,240 turn-final messages in 470 transcripts. Only 1 of the 25 is
   the incident-class defect; most are operator steps or conditional parks. Refining by owner, park
   and decision leaves 6, and 1-2 of those are true. C (a numbered self-plan with no tool after
   it) and C′ (a "should we…?" turn answered yes with no mutating tool) fire 2 and 3 times. Both
   catch the incident's earlier instances, and C′ has 1 false positive in 3.

## 1. Corpus survey: what markers the docs use today

Corpus: `docs/research/*/README.md` (55 files) and `docs/plans/*.md` (122 files) [measured: `ls … | wc -l`].
Research output also lives in 25 `docs/research/*/REPORT.md` and 374 flat `docs/research/*.md` files
[measured], which matters for scoping (§5).

Number of docs containing each marker (R = research READMEs, P = plans) [measured: one `grep -lE` per pattern]:

| Marker (regex) | R (of 55) | P (of 122) |
|---|---|---|
| heading `Wave N` | 2 | 7 |
| heading implementation / waves / rollout / phases | 1 | 44 |
| heading recommend… | 1 | 7 |
| heading next steps / follow-on / remaining / TODO | 2 | 9 |
| table column `Conv.` / `Conviction` / `Confidence` | 7 | 5 |
| prose `NN% conviction` / `conviction NN` | 5 | 18 |
| table column `Status` | 1 | 13 |
| word `landed` | 22 | 118 |
| `✅` | 2 | 51 |
| `DONE` | 2 | 89 |
| backticked 7-12 hex sha | 31 | 117 |
| open checkbox `- [ ]` | 0 | 1 |
| `Scope (frozen)` | 3 | 89 |
| `**Status**:` line | 2 | 29 |

Observations:

- Plans carry a document-level YAML `status:` (open / in-progress / complete / superseded). For new
  plans it is enforced by `hooks/validate-plan-structure.sh:6,37,78` and read by
  `scripts/find-plan.sh:40-55` (`--list-open`). Census [measured: `head -12 | grep -m1 ^status:`]: 66 complete,
  30 open, 23 in-progress, 2 superseded, 1 done. That is a document verdict, not a per-row one, and
  it goes stale. `docs/plans/LIMIT_DETECT_100P.md:2` reads `status: open`, yet its status log
  `:587-640` records W0, W1, W2a/b and W5 landed. Nothing reads it at Stop time.
- Research READMEs follow no convention. 1 of 55 has a frontmatter `status:` (grok-wiki-audit) and 2
  have a `Status:` line. Headings are free-form (`## Answer`, `## Results`, `## Verdicts`). The
  startup-hooks README is the only research README with `### Wave N` headings.
- Where a per-row status exists, it is free text in a `Status` cell (13 plans), e.g.
  `docs/plans/LOAD_ROOT_CAUSE_2026_10_17.md:35`, `docs/plans/HANDOFF_HIGH_VALUE_CAPTURE.md:20`.
- Most of the corpus records "this row was driven" somewhere other than the row, in a separate
  ledger that names the row id:
  - a task table: `docs/plans/NONLIMIT_RESUME_LADDER.md:65` (`T10 | W3-R1 — land … | DONE 2026-09-17 | … c50a363b1`), covering the recommendation row at `:880`;
  - a later landing table: `:899` (`R1 | … | LANDED | c50a363b1`);
  - a dated status log: `docs/plans/LIMIT_DETECT_100P.md:587-640` ("W0 is DONE — `b3f320fc5`");
  - a "What landed, by spec item" table: `docs/research/kitty-crash-2026-10-15/README.md:435-447`;
  - a header Status line: `Status (2026-10-15, phase 2): the guard and every caller landed at fb3edd4ff` (`kitty-crash…/README.md:7`).
- One research README marks status on the row the way a checker needs:
  `docs/research/opus55-utilization-2026-09-22/README.md:232-275` ("1. ✅ **… — DONE 2026-09-22** (landed
  `501e4490e` …)"). One report already has a column named `Drive`, but there it holds an id
  (`D1`…`D10`), not a state: `docs/research/lr-reliability-telemetry-speed-2026-10-10/REPORT.md:13`.
- The incident doc has neither form. Its §2 ranked rows (`startup-hooks-2026-10-18/README.md:29-75`) carry
  `Conv.` but no status. Its §5 wave units (`:159-222`) carry neither conviction nor status, and point back
  to §2 rows by `#N` (`1.2 Event name (#3)`, `:164`).

## 2. Prototype heuristic classifier (signal A) and its false-positive rate

### 2.1 Design

`classify.py` (v2) works in four steps:
1. It splits a doc by heading. A section is an action section when its heading matches
   implementation / waves / phase N / next steps / follow-on / recommend / remaining / fix
   candidates / …, and is not a reject / drop-ledger / open-questions / status-log / appendix heading.
2. Items are the table rows, list items, and `Wave N` paragraphs inside action sections.
3. An item's conviction comes from, in order: its own `Conv.` cell; prose (`NN% conviction`); or
   inheritance through `#N` from any table that has both an id column and a conviction column. That
   is how §5 `1.2 Event name (#3)` gets 95 from §2 row 3.
4. "Done" is either a loose word list (`landed`, `done`, `dropped`, `live`, sha, `c10`, …) or a
   strong token list (`✅`, `DONE`, `LANDED`, backticked sha, `filed`, `fired`, `rejected`, `c10`, …).
   A table `Status` cell, when one exists, is the only place status is read.

A doc flags when at least one item is not done and, in strict mode, has conviction ≥ N.
Docs whose frontmatter status is complete or superseded are suppressed.

`classify3.py` (v3) adds five changes. Nested bullets fold into their parent. A heading carrying a
done marker marks its whole section done. A table counts only when its header names an action column.
Ids (`#3`, `R1`, `W2a`, `T10`, `1.2`) are joined across the doc, so a row is done when any other line
naming its id carries a strong done token. Paragraphs are never items.

### 2.2 Incident doc (must flag)

[measured: `python3 -I classify.py|classify3.py … docs/research/startup-hooks-2026-10-18/README.md`]

| Config | Flags? | Undriven items (line, conv) |
|---|---|---|
| v2 strict ≥90, loose or strong done | yes | (33, 95) §2 #3 mailbox-drain; (164, 95) §5 1.2 |
| v2 strict ≥85, strong done | yes | 12 items: 31, 32, 33, 35, 36, 45, 163, 164, 192, 199, 201, 213 |
| v2 strict ≥85, loose done | yes | 9 items. Loose words in design prose ("partial output is **dropped**", "goal-inert … **live**") wrongly cleared #2 and #6 |
| v3 strict ≥90 | yes | (33, 95), (164, 95) |
| v3 strict ≥85, id-join | yes | 8 items. The id-join cleared 163, 192, 199 and 213 because `#1`, `1.1` etc. appear on other lines that hold a done token: a false negative |

The doc flags in every configuration. The ≥90 threshold catches only the 95% bug fix. The waves at
85-88 need ≥85.

### 2.3 Corpus (176 docs other than the incident doc)

[measured: `classify.py` / `classify3.py` over `docs/research/*/README.md docs/plans/*.md`; summaries in
`/tmp/detector-proto/out/c3-summary.txt` and the v2 task output]

| Config | Docs with items | Flagged (incl. incident) | Suppressed by doc status |
|---|---|---|---|
| v2 strict ≥90 (loose or strong done) | 98 | 4 | 0 |
| v2 strict ≥85 | 98 | 4-5 | 0-1 |
| v2 loose (any unmarked item) | 98 | 50 | 42-45 |
| v3 strict ≥90, id-join | 54 | 3 | 0 |
| v3 strict ≥90, no id-join | 54 | 4 | 0 |
| v3 loose, id-join | 54 | 23 | 16 |

### 2.4 Hand audit of 15 flagged docs

The sample is all 3 v2-strict corpus flags plus 12 v2-loose flags (6 research, 6 plans, chosen
alphabetically spread). Truth was checked with `git log` on the files the items name, the doc's own
status records, and the backlog ledger [measured: `verify.py`, `git log`, and `grep` over
`~/.claude/autonomy/backlog.jsonl`].

| # | Doc (flagged lines) | Verdict | Evidence |
|---|---|---|---|
| 1 | plans/LIMIT_DETECT_100P.md :197, :549-559 (conv 92-95) | FP | §11 amendments bind the waves (`:540`). Status log `:587-640`: W0 `b3f320fc5`, W1 `5d45af7f6`, W2a+b `d2c712d07`, "Amendments #2, #4, #10 and #12 ARE present". `05f8e2a09` "test(cc-limited): rows 16-22, one per § 11 amendment". :197 is a design statement, not an item |
| 2 | plans/LIMIT_RECOVER_FLEET_V2.md :427-428 rulings (90%) | FP | `:541` "Ruled 2026-09-30: off (90%) … the fix is the page channel"; `:711` "W6d (reconciler, page channel, rig): `6cd769a08` …" |
| 3 | plans/NONLIMIT_RESUME_LADDER.md :880 R1 (92%) | FP | `:65` T10 "DONE 2026-09-17 … `c50a363b1`"; `:899` "R1 … LANDED `c50a363b1`". v3 id-join clears it |
| 4 | research/kitty-crash-2026-10-15 :42-46 fix list | FP | `:7` "the guard and every caller landed at `fb3edd4ff`"; `:435-447` what-landed table covers refocus, action log and watchdog; `43e9b1447` fix(watchdog) HUP; `:415` detachable holder "dropped here" |
| 5 | research/limit-recover-zero-memory :99-106 | FP | A before/after measurement table under "W1 result" (heading matched `W\d`) |
| 6 | research/opus55-utilization :241-266 | FP | Nested sub-bullets of ✅ items were split off as items. Item 5 was later driven (`docs/research/sonnet55-utilization-2026-09-28/`, `haiku55-upgrade-2026-10-07/`). Item 4 is an operator settings migration |
| 7 | research/router-classifier-e1h :7-31 | FP | An artifact file list. The title "Wave E1h" matched `wave` |
| 8 | research/session-upgrader-2026-10-08 :183-189 | FP | "Remaining risks": residual caveats, not work |
| 9 | research/union-alpha-drain :506-509 | FP | A measurement table under "THE STRONGEST REMAINING JOB…" |
| 10 | plans/LR_INPLACE_IMMEDIACY.md :50-80 | **TP (partial)** | "New work (not yet assigned)" `:67`. The keystroke-free resume relaunch design (`:78`) and the rescue-verb husk gap (`:80`) have no drive record in the doc and 0 backlog hits (`grep -c 'husk shell\|keystroke-free\|rescue verb' backlog.jsonl` = 0). Others were driven: band `6459508f5`/`17962edb6`; load hold filed `600709c5fe4b` (`:96-97`); (a)-(d) assigned to the W2 owners `:98-104` |
| 11 | plans/kitty-deadlock-recovery-2026-10-01.md :39-43 | FP | The section heading `:35` says "— DONE (record; fixes carried into W3)" |
| 12 | plans/START_LATENCY_ROUTER.md :101-114 W1 list | FP | W1 landed: `bin/claude-accounts:161` implements `--max-wait`; last commit `a4e3b4d3f` "follow-on 2 is DONE" |
| 13 | plans/MASTER_FLEET_FOOTPRINT.md :103 | FP | A ruling's rationale bullet |
| 14 | plans/LOAD_AND_PROMPT_HOOK_TIMEOUTS.md :50-82 | FP | `Scope (frozen)` lines and a baseline table under "Wave 4" |
| 15 | plans/MCP_CONFIG_SSOT.md :109-122 | FP | Wave-1 research questions; `02f5f4a5f` "status log — wave 2 landed" |

**Precision on the corpus sample: 1/15 = 6.7%** [measured: hand labels above]. In conviction-gated
mode it is 0/3 (v2) and 0/2 (v3) [measured]. v3 loses the one true positive: LR_INPLACE no longer
flags, because its "New work" list sits under a `W2 — …` heading that v3 no longer treats as
actionable [measured: v3 loose output]. So tightening the heuristic trades recall for precision
without reaching an exact check.

**False-positive classes.**
- (a) Status is kept in a separate ledger keyed by row id: 4 of 14. Id-join fixes some, but it
  causes false negatives on the incident doc (§2.2).
- (b) A section is misclassified from its heading (measurement tables, residual risks, file lists,
  scope lines): 7 of 14.
- (c) Prose done-words are inside the row (loose mode only): 2 of 14.
- (d) A record section is marked DONE in its heading: 1 of 14.

**Exposure, as an upper bound.** The check runs only on docs the current session wrote. In the last
7 days, 63 commits touched 9 distinct corpus docs [measured: `git log --since=2026-10-11 … | sort -u | wc -l`].
LIMIT_DETECT_100P and LIMIT_RECOVER_FLEET_V2 (the two v3-strict false positives) had 18 and 32 commits
in 30 days [measured]. So a heuristic gate would fire on every session that touched them, which is
alarm-polarity failure for exactly the long-lived plans that sessions edit most. Estimate: with v3
strict, roughly 50 false Stops per month from those two files alone (one per touching commit,
assuming one session per commit).

## 3. Final-message signals B and C (measured over 470 transcripts)

Corpus: main transcripts in `~/.claude*/projects`, mtime < 4 days, > 50 kB, excluding `-private-*`
slugs. That is 470 files, 913 MB, and 1,240 turn-final assistant messages [measured: `signals_bc.py`,
summary `/tmp/detector-proto/out/bc-summary.txt`].

| Signal | Hits | TP (incident-class: drivable work riding a done verdict, or a stop before step 1) | Notes |
|---|---|---|---|
| B raw: line-1 done verdict + follow-on clause not none | 25 | 1 sure (#217, the incident) + 1 arguable (#137, a filed agent investigation `0ab4aa480455`) | 21 are operator steps ("is yours", "approve … when you're ready"), conditional parks ("once load is back above 300", "waits until kitty answers"), decisions, or fired sessions |
| B refined (`refine_b.py`: drop owner / park / fired / decision clauses) | 6 | 1-2 | Survivors include #268 (an operator money step, filed), #339 (a personal operator step), #1224 (an operator allow-list step) and #75 (empty clause from a regex miss). The owner is named outside the clause, so prose parsing stays noisy |
| C: numbered plan under "What I'd do / next steps / in order" with no tool after it | 2 | 1 (incident 06:03:01, "What I'd do, in order" with step 1 ">90% sure") | The other is a personal web-troubleshooting reply |
| C90: C with a step at ≥90% | 1 | 1 | Same incident message |
| C′: operator "should we / can we …?" turn, final message recommends yes, turn made no mutating tool call (`signals_c2.py`) | 3 | 2 (incident 06:02:17 "Yes, but keep it narrow", 06:03:14 "Yes to both … build the skill by running the investigation") | 1 FP: "can we preview a recipe" answered with a preview table, which was the requested deliverable |

Incident transcript checks [measured]. On the secondary-store part: B fires on the 14:27:47 close
(`✅ Good to close: yes. … Follow-on: the implementation waves in README §5 haven't started, because
this pass was research only.`). On the quaternary-store part (`….jsonl.handed-off`): C/C90 fire on
06:03:01, and C′ fires on 06:02:17 and 06:03:14. Earlier instance 1 (the "about 70% sure" reply) is
caught by none of B, C or C′.

Verdict: B parses prose that the agent controls, and the failing close looks the same as the good
ones (an operator step and an undriven wave both read "Follow-on: …"). Its precision is 4-8%
[measured: 1-2/25]. C′ is cheap and precise on this small sample, with 2/3 [measured], but low-volume
(3 per 470 transcripts). It is fit for a one-shot advisory nudge, not a block.

## 4. The exact convention, and the checker against it

### 4.1 Convention

Every doc that lists drivable work (research synthesis README/REPORT/DESIGN, plans) carries
exactly one table with a header cell `Drive state`. Other tables refer to its rows by id, so §2
and §5 of the incident doc would not both need the column. The cell holds one token:

| Token | Meaning | Mechanically verifiable against |
|---|---|---|
| `driven <sha>` | landed | `git merge-base --is-ancestor <sha> origin/main` |
| `fired <session/pane/worktree>` | a dispatched session owns it | handoff-fire record (the incident's own 20:05 `handoff-fire.sh --worktree startup-hooks-impl` would read `fired startup-hooks-impl`) |
| `filed <backlog-id>` | agent work handed to the backlog | id present in `~/.claude/autonomy/backlog.jsonl` (FILED_MINE then judges whether it carries a why-not-now) |
| `operator <backlog-id>` | operator-only step (c10, credential), filed | same ledger; feeds the 👤 rung |
| `decision <packet-id>` | a class-C fork filed with `cc-decide open --class C` | `~/.claude/autonomy/decisions/<id>.json` exists (`bin/cc-decide:9,76`) |
| `parked <condition>` | deliberate stated park | ≥3 words of condition ("until W2c lands") |
| `dropped <why>` / `rejected <why>` | not doing it | ≥2 words of reason |

Anything else (empty, `open`, `todo`, free text) is undriven. The vocabulary maps onto the ledger's
existing rungs (⛔ decision, 👤 operator, 📦/🔧 filed), so it adds no new state model.

### 4.2 Checker (`/tmp/detector-proto/drive_check.py`, 150 lines)

Fixtures are the incident §2 table (38 rows) with a `Drive state` column added
[measured: `python3 -I drive_check.py --verify --repo . fixtures/*.md`]:

| Fixture | rc | Output lines |
|---|---|---|
| all cells empty | 1 | 38 (`UNDRIVEN …:31 1 — no drive state` …) |
| all cells filled (`driven 1e7461db7`, `operator 75b041426dba`, `fired startup-hooks-impl`) | 0 | 0 (silent) |
| one cell left empty (row 5) | 1 | 1 |
| `driven deadbeef1`, `parked later` | 1 | 2 (`sha not on origin/main`, `park names no condition`) |

Runtime: 0.21 s wall / 0.03 s user on the full fixture with `--verify`, at load > 100 [measured: `/usr/bin/time -p`].
The checker fails open: an unreadable backlog or decision store never creates a finding, matching
`wrap-ledger.sh`'s rule for BLOCKED, YOURS and FILED (`scripts/wrap-ledger.sh:1343-1347`).

`--lint` mode (the heuristic, used only as a write-time nudge): 77 corpus docs have an action
section but no `Drive state` table (11 research, 66 plans) [measured: `drive_check.py --lint`
over the corpus]. The incident README reports `UNMARKED`.

### 4.3 Where it plugs in (no settings.json edit)

- **Close-time (exact):** a new `wrap-ledger.sh` term, `DRIVE_UNDRIVEN_MINE`. It counts undriven
  `Drive state` rows in files from `session_writes_paths` (`hooks/lib/session-writes.sh`). That
  oracle covers subagent and workflow writes, which is the incident's path. Rank it 🔧, the same
  rank as FILED_MINE and UNCONVICTED, following the precedent at `scripts/wrap-ledger.sh:1349-1371,1372-1388`.
  Readout example: `🔧 Undriven follow-on: 9 rows in startup-hooks README §2 carry no drive state:
  drive, fire, file, or park each`. A ✅ is unreachable while the count > 0. That is the mechanism the
  incident lacked ("`wrap-ledger.sh` computed ✅ from git state alone", INCIDENT.md).
- **Row ownership, to avoid convicting a session for another lead's rows:** count a row only if
  its line is in this session's added lines. Those are the `git diff` of commits made in this
  worktree since session start (the worktree HEAD reflog lists them: `b13e43872 …: commit: docs(research):
  startup hooks — ranked synthesis`, measured via `git reflog`), plus the uncommitted diff. A long
  shared plan (`LIMIT_RECOVER_FLEET_V2.md`, 32 commits in 30 days) then cannot make an editing
  session own another lead's rows.
- **Write-time (heuristic, non-blocking):** extend `hooks/validate-plan-structure.sh` (PostToolUse;
  its path filter lives in the script at `:63-70`, and the registration is a generic file-edit
  matcher, `settings-templates/settings.example.json:193`). Add `docs/research/*/{README,REPORT,DESIGN}.md`
  and emit `⚠️ DRIVE STATE: <doc> lists actions but has no Drive state table` when `--lint` says
  UNMARKED. Heuristic false positives here cost one ignored warning, not a loop.
- **Turn-time advisory (C′):** one `additionalContext` line from the existing Stop-chain. It fires
  only when the operator's prompt asked "should we/can we …", the reply recommends yes, and the turn
  made no mutating tool call. Fire once per turn and never block.

### 4.4 Cost of adoption (estimated)

| Item | Estimate | Method |
|---|---|---|
| Author cost per new synthesis doc | 1 column, 10-40 cells; about 1-2 min of agent time; about 300-800 output tokens | incident §2 has 38 rows [measured]; ~20 tokens per cell |
| Upkeep per driven row | 1 Edit of one cell (~150 tokens) at land/fire/file time | one Edit call |
| New docs per week that would carry the table | ~5-8 | 8 README/REPORT plus 5 plans added in the last 7 days [measured: `git log --since=2026-10-11 --diff-filter=A`]; not all list work |
| Legacy migration | none required | the check only reads docs the session writes; the 77 UNMARKED legacy docs get the write-time warning only when next edited |
| Code | `drive_check` logic as a `wrap-ledger.sh` term (~80 lines of bash+jq, or the 150-line python called bounded) plus bats; the validate-plan-structure path extension is ~15 lines | prototype size |
| Close-time latency | ≤0.2 s per touched doc | measured 0.21 s wall at load > 100; it runs only when session_writes contains a doc with a `Drive state` header (a grep), otherwise 0 |
| Resident instruction budget | net 0 | the vocabulary is taught by the checker's own 🔧 readout and by the write-time warning (precedent: `validate-plan-structure.sh:78` teaches `status:` values in its message). See the rule-text cut in §6 |

## 5. Always-firing and override risks

- **Silent when nothing is drivable:** the check yields 0 when the session wrote no doc with a
  `Drive state` table, or when every row has a token. A research-only session can clear it without
  implementing anything, by marking rows `fired <impl-session>` or `filed <id>`. That is exactly what
  the incident session did at 20:05 (`handoff-fire.sh … --worktree startup-hooks-impl`, transcript
  2026-10-18T20:05:13). So the check forces a disposition, not an implementation.
- **Real operator decisions are not blocked:** `decision <id>` and `operator <id>` are terminal
  states for this term. They surface through the existing ⛔ and 👤 rungs.
- **Deliberate parks are not blocked:** `parked <condition>` is terminal. The ≥3-word rule stops
  a bare `parked` from becoming an escape hatch.
- **Remaining escape:** a session that writes action rows without the column. The write-time lint
  catches this heuristically, but it is non-blocking. Escalating it to blocking for new docs, the way
  the `status:` gate does (`validate-plan-structure.sh:78`), would close the escape at the price of
  the lint's false positives (§2.4 classes b-d) on new docs only.
- **Coverage gap:** a doc written only through Bash (`cat >`, `sed -i`) is invisible to session-writes
  (`hooks/lib/session-writes.sh:39-45`). The reflog-commit path covers it once the doc is committed.
  A session that resumes across config stores loses the earlier store's subagent dir: in the
  incident, the quaternary part's `subagents/` holds A7 writes, and the README write was in the
  secondary part.

## 6. Rule-text change with a matching cut (net zero)

- Add to `CLAUDE.rules.slim.10-session-close.md` § Follow-On Gate (~30 words): "A doc that lists
  drivable work carries one `Drive state` column; an empty cell is your loose end, and research-only
  scope does not exempt it: drive, fire, file, decide, park with its condition, or drop."
- Cut ~30 words from `:191`, "Offering researched, in-scope remaining work ("say the word and I'll
  pick up either") is a defect; the Follow-On Gate already settled it." Its content is restated by
  `:99` (E0 "run the Follow-On Gate on each item and drive the passes … before yielding"), and the
  new term enforces it mechanically.

## 7. Conviction summary

- 90%: heuristic signal A is unfit as a gate (corpus precision 1/15; strict mode 0/3).
- 85%: the `Drive state` convention plus a session-scoped wrap-ledger 🔧 term is exact and silent when
  everything has a disposition (fixtures measured; integration not built).
- 80%: session-writes.sh scoping catches the incident doc (README Write found in the secondary
  workflow-agent transcript; not run through the library itself).
- 70%: a write-time lint on research docs fires inside Dynamic-Workflow agents. Not measured here:
  it depends on PostToolUse hooks running in workflow agents.
- 75%: C′ is precise enough for a one-shot advisory (2/3, n = 3).
- 90%: B as a prose parser is unfit for gating (1-2/25).

## Skeptic verdicts

(Skeptic pass for axis 10, 2026-10-18. This pass was read-only apart from this appended section.
Each re-check names its command. Probes of `drive_check.py` used process substitution
(`<(printf …)`), so no file was written. Load during the pass was 340-517 (measured: `uptime`).)

### Root causes

**RC1. Driven-ness lives in a separate id-keyed ledger, and no heuristic can replace a row marker.
Weakened, 75%.**
- Every cited line re-reads as stated (measured: `sed -n`).
  - `NONLIMIT_RESUME_LADDER.md:65` reads T10 "DONE 2026-09-17 … `c50a363b1`". `:880` is R1 at 92%,
    and `:899` reads R1 "LANDED `c50a363b1`".
  - `LIMIT_DETECT_100P.md:2` reads `status: open`, while `:594-595` says "status reconciled …
    four waves had landed".
  - The kitty-crash README has the summary at `:7` and "What landed, by spec item" at `:435-447`.
  - The incident README has `Conv.` and no status in §2 (`:29-75`), and neither in §5 (`:155-222`).
- One part fails. "So `wrap-ledger.sh` falls back to git state alone" does not describe the code.
  The ladder already reads four non-git stores:
  - REMAINDER counts unchecked `- [ ]` DoD items (`scripts/wrap-ledger.sh:896-931`, rung at `:2514-2515`).
  - FILED_MINE, UNCONVICTED and BLOCKED read the backlog and decision stores (`:1343-1391`, `:2563-2570`).

  The incident printed ✅ because the waves were in none of those stores: the DoD said research
  only, and nothing was filed. The axis never weighs its new on-doc store against routing the
  waves into a store the ladder already counts (`Scope (grown)` checkboxes into REMAINDER, or
  backlog rows into FILED_MINE).

**RC2. Prose done-words and action-shaped headings defeat word-based detection. Confirmed, 85%.**
- The incident README has "A killed child's partial output is **dropped** and named" at `:32` and
  "clears it when the goal is **live**" at `:36`.
- The headings read as cited: `## W1 result: before and after` (zero-memory README `:93`),
  `# Wave E1h: …` (router-classifier-e1h `:1`) and `## 6. Remaining risks` (session-upgrader `:181`).
- This explains why the heuristic fails. It has no bearing on the exact check.

**RC3. The scope must include subagent and workflow transcripts. Confirmed, 88%.**
- The lead's secondary transcript (measured: `jq` over its tool_use records) holds these file edits:
  - three Writes: INCIDENT.md, `/tmp/fire-startup-hooks-impl.txt` and `/tmp/fire-close-behavior.txt`;
  - two Edits to `startup-hooks…/a2-memmirror-scan.zsh` and `a8_exec_cost.sh`. The axis's "only"
    leaves these out, which does not matter here.
- The README edits are in `subagents/workflows/wf_7c1e0d3e-19e/`: 1 Write and 1 Edit in
  `agent-a2bfc6f1444ab842c.jsonl`, and 29 Edits in `agent-a6f0ebc90467839e7.jsonl`.
- The lead ran `git add` at `2026-10-18T14:18:54Z`, and the close came at `14:27:47Z`.
- I replayed `_sw_paths`' session-scope `jq` filter over the main file plus the 38 subagent files
  that `_sw_subagent_files` finds (`hooks/lib/session-writes.sh:206-210`). It returns 51 paths,
  including the README, in 0.41 s at load ~450 (measured). That is inside `SESSION_WRITES_TIMEOUT_S=5`.

**RC4. Signal B is not discriminative. Confirmed, 85%.**
- I read the first 150 characters of all 25 B hits in `out/bc-fleet.json`. Each one except the
  incident's names an owner ("is yours", "your call", "waiting on you"), a 12-hex store id, a
  fired session or a load or park condition. One hit was cut off before its clause.
- The rate of pushback in the next prompt after a B hit is 3/25. The base rate is 365/1,240
  (`out/bc-summary.txt`). The axis did not report this, and it supports the conclusion that most
  B closes are not defects.

### Fix candidates

**F1. `Drive state` column plus a `DRIVE_UNDRIVEN_MINE` 🔧 term. Weakened, 60%.**

What holds up:
- **It can be built at the cited insertion point.** FILED_MINE and UNCONVICTED rank inside the
  ✅-eligible branch (`wrap-ledger.sh:2563-2570`), so a sibling term there makes ✅ unreachable.
  `session-writes.sh` is already sourced in a child shell (`:1757-1772`). `tests/wrap-ledger.bats`
  (140 tests) pins no full machine-key list.
- **It does not block an operator decision or a park.** `decision`, `operator` and `parked` are
  terminal states for the term.
- **The fixtures reproduce** (measured: `drive_check.py --verify`). Empty gives 38 lines with rc 1.
  Fully marked gives 0 lines with rc 0. One cell left gives 1 line. The bad fixture gives 2.

What fails:
1. **The incident's own reason clears it.** I probed a 7-row table through `<(printf …)` (measured).
   These cells all passed silently:
   - `dropped research only`
   - `parked until a later implementation pass`
   - `rejected out of scope`
   - `fired nobody-ever-fired-this`

   `drive_check.py:43-92` has no `fired` branch, although §4.1 says the token is "mechanically
   verifiable against" a handoff-fire record. So the term forces a label, not a drive. The
   operator's complaint ("no net positive if research is done but its not enacted on") survives
   a table full of `parked` cells. Three hardenings would close this:
   - check `fired` against cc-custody, which the ladder already reads (`:2534-2542`);
   - make `parked` point at a backlog row that carries a `--condition` falsifier, not free text;
   - name the counts of parked and dropped rows on line 1 of the close.
2. **It fires on work that has landed.** `ship-land` rebases. This worktree's reflog shows
   `b13e43872 … commit: … ranked synthesis` (09:18:55) re-picked as `1e7461db7` six seconds later.
   `git merge-base --is-ancestor b13e43872 origin/main` gives rc 1, and for `1e7461db7` it gives
   rc 0 (measured). A `driven <sha>` cell written at commit time, which is the natural moment,
   reads "sha not on origin/main" forever. The probe row `driven b13e43872` was flagged exactly
   that way. The fix is to verify by patch-id or subject (`git cherry`), or to accept ancestry of
   the local HEAD and leave landedness to UNLANDED.
3. **Reflog row ownership is the refuted "worktree-implies-mine" rule.** `session-writes.sh:56-72`
   records it as refuted: two concurrent sessions in one linked worktree, measured 2026-08-20. A
   sibling session's commit to the same doc would convict this session. The exact per-session
   source is the session's own Write `content` and Edit `new_string`, including subagents. The
   oracle already parses that stream.
4. **The latency is understated.** The 0.21 s figure comes from the fixture with only one `driven`
   row. At load ~340 (measured: `/usr/bin/time -p`):
   - 38 `driven` rows took 1.63 s;
   - 38 `filed` rows took 1.45 s, because `verify()` re-reads the 10.9 MB backlog once per row.

   The "otherwise 0" precondition still has to call `session_writes_paths` (0.41 s here, measured).
   The verifies need batching (one `rev-list` and one backlog read), and the term should run only
   in the ✅-eligible branch.
5. **It ignores the Active research program exemption.** That exemption is operator ruling
   `83adb541ea19` (`CLAUDE.rules.slim.10-session-close.md:74-80`). Inside a program, residuals are
   not open work, refinements go to the apply-at-build list, and the offer arm abstains. The term
   must abstain when `research-program.sh is-active` exits 0, or accept an `apply-at-build`
   token. The axis never mentions programs (measured: `grep -n -i program` finds no hit in §0-§7).
6. **It is not shown to work on the incident.** With no table the term is silent, and the incident
   README had no table. Coverage depends on F2, whose firing inside workflow agents is unmeasured,
   or on a change to the synthesis contract that the axis does not propose.

**F2. Write-time lint in `validate-plan-structure.sh`. Weakened, 50%.**
- **The literal insertion point is wrong.** Adding research paths to the `case` at `:64-70` sets
  `IS_PLAN` and `IS_AUTHORED`. That routes research READMEs into the blocking status gate
  (`:73-79`, exit 2 for a new file with no `status:`), and 54 of 55 research READMEs have no
  frontmatter status (axis §1). The check needs its own branch ahead of the `case`. `:60` also
  requires the `case` to "match backup-before-write.sh exactly".
- **It would fire on every edit.** Transcripts modified in the last 4 days hold 544
  Write/Edit/MultiEdit calls on `docs/plans/*.md` and `docs/research/*/{README,REPORT,DESIGN}.md`,
  across 49 docs. One DESIGN.md had 260 and the incident README 31 (measured: `grep -o` over
  `~/.claude*/projects`; an upper bound, because mirror stores may double-count). Without a
  per-(session, file) latch, the warning repeats on each edit.
- **It flags finished docs.** `--lint` prints UNMARKED for kitty-crash (fully landed, audit #4) and
  for opus55, the one corpus doc that marks status per row (measured).
- **It must merge with the existing message.** `tests/validate-plan-structure.bats:120-131` pins
  exactly one JSON object per run, so on plans the new text must join the existing
  `additionalContext`.
- **The registration claim holds.** Live `~/.claude/settings.json` registers it on PostToolUse
  with matcher `Write|Edit|MultiEdit` (measured: python json read). No settings edit is needed.

**F3. Rule-text change billed as net-zero. Refuted, 15%.**
- **It is not net zero.** The cut sentence is 22 words and 138 characters. The added text is 35
  words and 203 characters (measured: `wc -wc`). That is a net gain of 13 words and 65 characters.
- **The test suite contradicts the cut.** `tests/research-program-exemption-rules.bats:37` runs
  `grep -F 'Offering researched, in-scope remaining work' "$S" | grep -q 'is not an offer'`, which
  pins the sentence being cut. `:29` also pins the full variant's "**Offering is the defect**"
  paragraph, which the fix leaves alone.
- **`:99` does not restate the cut sentence.** E0 covers read-only turns only. `:180` ("'say the
  word' is not a disposition") covers part of it. The anti-offer sentence is the rule closest to
  the incident's earlier instances 2-3 ("What I'd do, in order", then stop). Cutting it trades one
  rule for another in the same failure class.
- **It edits the slim variant only.** `CLAUDE.global.md` § Session Close Protocol is untouched,
  although tests pin both variants.

**F4. One-shot advisory for "should we X?" (C′). Weakened, 40%.**
- **"Never a block, one `additionalContext` line" is not a channel that exists at Stop.**
  `CLAUDE.global.md:507-516` (measured 2026-08-08) states that Stop `additionalContext` forces a
  turn and adds to the same block counter, and that `systemMessage` never reaches the model. C′ is
  therefore a one-shot forced turn, which is a bounded block.
- **It was tuned on the incident.** `signals_c2_base.py` found 1 C′ in 10 should-we turns
  (`out/c2-summary.txt`). Widening Q (multiline) and REC (`both\b`, which matches "Yes to both")
  raised that to 3 in 13 (`c2-summary2.txt`). Both true positives come from one session. The
  no-mutation conjunct filtered nothing: all 3 recommend-yes turns had `mut=0` (`out/c2-fleet2.json`).
- **The axis misses its natural home.** `hooks/anti-deference-nudge.sh` is an existing Stop hook
  with a one-shot hash latch, the `ANTIDEF_MAX=3` cap, a genuine-ask carve-out and an IDL row
  (`:12-48`). The axis never mentions it. C′ must also abstain inside an active research program,
  as the offer arm does (rules `:77`).
- **It could force a turn over an operator decision.** "Should we X?" can be a request for an
  opinion on a value fork, which needs the `hard_genuine` carve-out.

### Measurements

| Measurement | Verdict | Re-check |
|---|---|---|
| Corpus 55 R / 122 P / 25 REPORT / 374 flat | confirmed | `ls … \| wc -l`: 55/122/25/374 |
| Status census 66/30/23/2/1 | confirmed | `head -12 \| grep -m1 ^status:`: identical |
| Marker prevalence | confirmed (regex-sensitive) | `landed` 22/118, ✅ 2/51 and `Scope (frozen)` 3/89 match exactly. My regex variants give Conv 6/3 (axis 7/5), Status 1/9 (1/13) and DONE 4/90 (2/89) |
| Incident flagged in every config | confirmed | `classify3.py --mode strict --min 90`: undriven=2; `--min 85`: undriven=8 |
| Corpus flag counts | confirmed (v3) | `out/c3-summary.txt` matches 3/4/23/24. v2 not re-run |
| Hand audit 1/15 | confirmed, small n | #3, #4, #5, #7, #8 and #10 re-read. The #10 items post-date the related Oct 10-11 landings (`git log`), so the TP stands |
| FP classes 4/7/2/1 | confirmed | follows from the labels |
| Churn 63 commits / 9 docs; 18 and 32 | confirmed | `git log --since`: identical |
| Signal B 25 hits, 1-2 TP | confirmed | 25 hits read, as in RC4 |
| C / C90 / C′ counts | weakened | counts reproduce, but C′ was tuned between two runs (1 → 3 hits) and both TPs are one session |
| `drive_check` fixtures and 0.21 s | weakened | rc and line counts reproduce. The timing holds for 1 verified row only: 38 verified rows take 1.45-1.63 s at load ~340 |
| Lint: 77 docs (11 R, 66 P) | confirmed | re-run: 66 plans + 11 research. The set includes finished docs |
| README write is in a workflow-agent transcript | confirmed | as in RC3 |
| Adoption cost | confirmed as an estimate, latency row refuted | the 8 + 5 new docs reproduce. "Otherwise 0" ignores the 0.41 s `session_writes_paths` precondition |

§2.4's "~50 false Stops per month" estimate (not in the summary) assumes the heuristic runs
without the row-ownership scoping that F1 gets. So it overstates the heuristic's exposure. The
verdict that a heuristic cannot gate still holds on precision alone.

### Missed by the axis

- **Existing stores the ladder already counts.** REMAINDER, FILED_MINE and CUSTODY could carry
  the waves with no new on-doc store. For example, a ≥85% row is appended as a `Scope (grown)`
  checkbox, or filed with `--why-not-now`. The axis does not compare these.
- **`anti-deference-nudge.sh`.** Its "done assertion contradicted by the live ledger" arm would
  block the incident's "Good to close: yes" for free once any ledger term reads 🔧. That makes F1
  and the existing hook complementary, which the axis does not say.
- **The Active research program exemption** (operator ruling `83adb541ea19`) binds both F1 and F4.
- **The synthesis contract** in `skills/research-subagents/SKILL.md` and `commands/research.md` is
  an insertion point outside the resident budget. It would put the `Drive state` table into
  synthesis docs as they are written, with no reliance on a PostToolUse lint inside workflow agents.
- **Rebased shas.** `ship-land` rebases, so any sha-bearing token must be verified by patch
  equivalence, not by ancestry.
- **Parks never re-measure.** A free-text `parked` cell is terminal with no re-arm. The backlog's
  `--condition` falsifier rows already re-measure a park.
- **A B refinement worth testing as an advisory only.** In the first 150 characters of the 25
  hits, a follow-on clause with neither an owner phrase nor a store id singled out only the
  incident (one clause was cut off), and the agent writes this prose itself.
