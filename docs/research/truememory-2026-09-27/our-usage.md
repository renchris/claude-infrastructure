# Axis: how much our memory is used in practice, measured from transcripts (last 30 days)

Window: records with `timestamp >= 2026-08-28T00:00` (30 days before 2026-09-27), in transcript files with mtime within 30 days.
Everything below is **MEASURED** from transcripts or files unless it is labelled **ESTIMATED**/**CLAIMED**.
Nothing was edited outside /tmp/tm-research. No memory store, ~/.claude config, hook or repo file was touched.

## 0. Method (reproducible)

| step | artifact | what it does |
|---|---|---|
| scan | `/tmp/tm-research/scan3.py` (the reads/writes/hits logic is the same as `scan2.py`; scan3 adds phrase-based residency needles) | streams every `~/.claude/projects/*/*.jsonl`, `~/.claude-tertiary/...`, `~/.claude-quaternary/...` plus `*/subagents/**.jsonl` line by line, cheap substring prefilter before `json.loads`, 4 worker processes (`nice -n 10 python3 scan3.py 4`). One summary row per transcript is written to `/tmp/tm-research/scan/files3.jsonl`. |
| volume | `scan3.log`: `DONE 7881 bytes 10032254401` | **7,881 transcript files, 10.03 GB, all of them scanned (no sampling).** |
| config dirs | `ls -la ~/.claude-next/` | `~/.claude-next/projects -> /Users/chrisren/.claude/projects` (whole-dir symlink), so it is not scanned twice. Only 3 physical project dirs exist. |
| dedupe | `an2.py`/`an3.py` | 566 files are the same session basename in two config dirs (transplants). Only the longest copy is kept. |
| rates | `an2.py` -> `an2.out` | read, write, resident and nudge rates |
| re-learning | `an3.py` -> `an3.out` plus `relearning-hits.tsv` (345 rows, one per hit, with evidence) | per-lesson symptom recurrences |
| corrections | `prompts.py` -> `prompts-typed.jsonl` (2,650 prompts); `corrections-all.tsv`, `corrections-short.txt` | operator-correction phrases |

**Populations (measured, an2.out §A):** 7,678 files had at least one in-window record, and 7,112 remained after dedupe:
- **3,318 main sessions** and 3,794 subagent transcripts.
- Only **917 main sessions (27.6%) contain a typed human prompt** (`origin.kind=="human"` and `promptSource=="typed"`). The other ~2,400 are dispatched, headless or brief-only sessions: drain lanes, handoff fires, `-p` evals, and `/private/tmp` harness runs.
- 2,122 strict typed prompts in total. Of those, **1,508 are operator-like**: under 1,500 chars and not starting with `[locate]`, `You are`, `TASK`, `Continue`, `Fresh context`, `CONTINUATION`, `#` or `<pasted`. The long ones are recycle or dispatch briefs that pass the "typed" filter.
- Main sessions by project kind: other 2,249 (mostly `/private/tmp*` harness runs, `personal`, `mac-bootstrap` and others), worktree 817, claude-infrastructure 249.

**Classifying a Bash command** (`classify_bash` in scan2/scan3): the command is split into clauses on newline, `;`, `&&`, `||`, `|`, `$(` and backtick. For each mention of a memory, lesson-body or rules path, the clause is classed as follows:
- **write**: a `>`/`>>`/`tee` target, `sed -i`, or a `tee`/`mv`/`cp`/`rm`/`cc-memory-rotate`/`touch`/`ln` verb.
- **grep**: the clause starts with `grep`/`egrep`/`rg`.
- **read**: the clause starts with `cat`, `head`, `tail`, `sed`, `less`, `awk`, `wc`, `nl`, `diff`, `cut`, `sort` or `jq`.
- **other**: anything else, e.g. `git add`, `ls`, or the path quoted in a brief.

The Read, Grep, Glob, Write, Edit and MultiEdit tools are classed by their `file_path`/`path` input.
Path categories: `mem_index` is `…/memory/MEMORY.md`, `mem_topic` is `…/memory/*.md`, `mem_archive` is `…/memory/archive*`, `lesson_body` is `docs/lessons/*.md`, and `lesson_rules` is `rules/agent-operating-lessons*.md`.

**"Pure consult"** means a read or grep of a topic file, lesson body or archive file that the same session did not also write. It is the closest proxy for "a session retrieved a stored memory to inform its work".

Sanity check on the Read tool counts, run independently with `grep -ho '"name":"Read","input":{"file_path":"…(docs/lessons|/memory/)…'` over all 30-day main jsonl: 1 Read of a lesson body and 67 Reads of memory paths (raw, not deduped). This agrees with the scan.

## 1. Retrieval: how often sessions read a memory topic file or a lesson body (an2.out §B)

| population | n | mem_topic read | lesson_body read | archive read | rules-file grep ("grep that file for the symptom") | **pure consult** |
|---|---|---|---|---|---|---|
| main sessions | 3,318 | 70 (2.1%), 124 events | 32 (1.0%), 44 events | 1 (0.03%) | 74 (2.2%) | **65 (2.0%)** |
| main with a typed human prompt | 917 | 62 (6.8%) | 25 (2.7%) | 1 | 69 (7.5%) | **51 (5.6%)** |
| main, cwd claude-infrastructure | 249 | 13 (5.2%) | 10 (4.0%) | 0 | 25 (10.0%) | 10 (4.0%) |
| main, cwd a worktree | 817 | 32 (3.9%) | 14 (1.7%) | 1 | 41 (5.0%) | 32 (3.9%) |
| main, other cwd | 2,249 | 25 (1.1%) | 8 (0.4%) | 0 | 8 (0.4%) | 23 (1.0%) |
| subagents | 3,794 | 48 (1.3%) | 9 (0.2%) | 6 | 22 (0.6%) | 62 (1.6%) |

**How much of each store gets read at all** (an ad-hoc script over files3.jsonl, counting distinct basenames read by a session that did not write them):
- claude-infrastructure memory store: 496 topic files, 134 modified in the window. **25 distinct files (5.0%) were read at all in 30 days**, across 36 session-reads.
- reso-management-app store: 837 topic files. **57 (6.8%) were read.**
- `docs/lessons/`: 144 bodies (all 144 have mtime in the window because of the 09-17 split). **18 (12.5%) were read by a non-author**, in 22 sessions.
- Cold archive `MEMORY_ARCHIVE_2026-H2-COLD.md` (171 rules per MEMORY.md's header comment): **1 main-session read and 6 subagent reads in 30 days.** In practice a demoted rule is unreachable.
- The Read *tool* was used on a lesson body **once** in 30 days. Every other lesson-body read was `cat`, `head` or `sed` via Bash.

**Resident, always-injected memory** (the `instructions` attachment, measured per main session, an2.out §D):
- 2,756 sessions carry the attachment. The mean total instruction text per session is **141,668 chars** (median 126,214); **ESTIMATED** ~35K tokens at 4 chars/token.
- MEMORY.md (the `AutoMem` entry) is non-empty in only **1,011 of 2,756 sessions (36.7%)**. The mean is 6,733 chars; claude-infrastructure's is 22,514 chars.
- Lessons-rules files (`agent-operating-lessons*.md`, project plus global) average **21,967 chars per session**.
- The situational rules file (`agent-operating-lessons-situational.md`, 189 hooks) is **not** in the sample claude-infra `instructions` list (8 files: CLAUDE.md x2, rules.slim, 00-mission-board, global agent-operating-lessons, project .claude/CLAUDE.md, project agent-operating-lessons.md, AutoMem). The note says it is not loaded in that sample session, and gives no mechanism.

**Reading of §1:** the system's utility is almost entirely **resident injection** (MEMORY.md plus the rules hooks, loaded unprompted). **On-demand retrieval of the long tail is rare**: 2.0% of all sessions, or 5.6% of human-driven ones, ever open a stored topic or lesson body. About 95% of the 496-file infra store is never read in a month.

## 2. Capture: how often sessions write memory files (an2.out §B, §E)

| population | any memory/lesson write (topic, index, body or rules; tool or bash write-verb) | mem_topic write | mem_index write | lesson_body write | lesson_rules write |
|---|---|---|---|---|---|
| main 3,318 | **225 (6.8%)** | 116 sessions / 181 events | 35 / 60 | 51 / 81 | 99 / 228 |
| main with human 917 | **203 (22.1%)** | 108 / 173 | 35 / 60 | 37 / 66 | 99 / 228 |
| main claude-infra 249 | 47 (18.9%) | 19 | 9 | 18 | 27 |
| subagents 3,794 | 11 (0.3%) | 1 | 9 | 0 | 3 |

- **Writes outnumber consults.** For topic files, 116 sessions wrote and 70 read (181 write events against 124 read events). Across all categories, 225 sessions wrote memory and 65 ever pure-consulted it. **The store grows about 3.5x faster than it is read (measured session ratio 225/65).**
- **Nudge conversion** (`hooks/memory-nudge.sh`, marker `MEMORY CHECK (periodic)` in `hook_additional_context`):
  - 286 main sessions received 582 nudges in total.
  - **124 of them (43.4%) wrote a memory, lesson or rules file after the first nudge.**
  - Of the 3,032 sessions with no nudge, 74 (2.4%) wrote one.
  - Confounded: the nudge fires every 12 prompts, so only long, human-driven sessions get one.
- **Write friction** (Write/Edit tool_results on `/memory/` paths that returned an error, 19 events):
  - 15 are `File has not been read yet` / `modified since read`, mostly on `MEMORY.md` (read-before-write guard).
  - 1 is `MEMORY INDEX WRITE REFUSED … 1063 chars over its read limit` (2026-09-04, wt-pool-8).
  - 1 is the 09-27 symlink-probe prompt.
  - One apparent duplicate (`worktree-ops-can-bare…`, session 2c6c3a09, 2026-09-06T05:00) was checked by hand. The agent ran a dedupe `cat` first and then Edited, so it was **not** a re-learn.

## 3. Re-learning: do lessons' symptoms recur after the lesson exists? (an3.out, relearning-hits.tsv)

**Method.** 16 lessons were chosen, each with a distinctive, machine-observable signal. A signal is one of:
- `sym`: a literal string in a **Bash tool_result**.
- `cmd`: a regex at the start of a Bash command clause. This is the mistake the lesson forbids.
- `content`: a regex in the new content of a Write/Edit to a non-.md file.
- `att`: an attachment type.
- `memerr`: an error on a Write/Edit to a memory path.

Exclusions:
- Bash commands that touch `docs/lessons`, `.claude/rules`, `/memory`, `MEMORY`, `.jsonl`, `git log/show/diff/grep`, `rg`, `strings`, `tool-results` or `docs/research|plans`. This stops a session that is *reading about* a lesson from counting as hitting it.
- Output lines that contain a lesson slug, a grep `N:` prefix, or `disable=`.
- Heredoc commands, for `cmd` kinds.

**Effective-from** = the lesson date + 1 day. The date is taken from `git log --diff-filter=A` on the body, or from `git log -S"<hook text>"` on `.claude/rules/`, or from the date in the body.

For every session hitting a signal after that date, three flags are recorded:
- **resident**: a phrase from the lesson's hook or slug appears in that session's `instructions`/`nested_memory` attachment. For subagents, the parent's is used. Phrase needles are used because before 2026-09-17 the rules bullets had no slug.
- **touched-before**: the slug or phrase appears in a Read/Bash path or command, or in any tool_result, at or before the first hit.
- **touched-any**: the same, at any time in the session.

| # | lesson (effective from) | signal | events after / sessions after (main/sub) | resident | touched before hit | events in window **before** the lesson | hand-verified reading |
|---|---|---|---|---|---|---|---|
| 1 | never-wrap-ship-in-your-own-timeout (09-09) | cmd `timeout N … ship-land.sh` | 37 / 17 (17/0) | 7 | 0 | 117 | Split by repo (ad-hoc script): **claude-infra real lands wrapped: before 72 events / 38 sessions in 12 days, after 5 / 4 in 19 days (ESTIMATED 15x lower session rate).** Hand-checked after-sessions: a11fe2dc (cwd fde-endpoint-business-case, landing claude-infra, **hook NOT resident**, killed at `verdict=killed … TIMEOUT is in our OWN ancestry`, 2026-09-17T04:59) and 3222585b (**hook resident**, `timeout 3000 bash scripts/ship-land.sh`, 09-18). **2 confirmed recurrences, 2 ambiguous (command truncated).** The 25 reso events use reso's own, softer rule (reso `.claude/rules/agent-operating-lessons.md:97`) and are excluded. |
| 2 | a-gate-refusal-is-not-a-gate-result (09-09) | sym `this is a DEFERRAL, not a test result` | 174 / 137 (117/20) | 123 | 6 | 48 | The environment shows the symptom constantly (137 sessions). The misread itself (`bats … \| grep '^(ok\|not ok)'` then trusting zero lines) matched **0 times before and after**, so the harm is not measurable by regex. Here the resident hook is doing the job. |
| 3 | never-write-a-tracked-file-while-ship-is-in-flight (09-09) | sym `cannot rebase: You have unstaged changes` | 2 / 2 | 0 | 0 | 2 | wt-32d4d093 2026-09-09T05:05 is a real ship-land output: **1 recurrence the day after the lesson, not resident**. The 09-25 wt-pool-3 hit is a manual rebase in reso, not in scope. |
| 4 | census-matches-itself (09-10) | cmd `ps … \| awk -v x=… index($0 \| $0~` | 0 / 0 | – | – | 0 | No signal. The regex is narrow; the first, broader regex caught 183 field-compare `awk '$2==p'` uses, which are not the bug. |
| 5 | in-process-agent-stops-at-100-turns (09-17) | att `max_turns_reached` | 0 | – | – | 13 | All 13 fall between 09-05 and 09-10 (`/private/tmp` workflows, wt-ptuf2, prec2), and there were none from 09-11. **The drop predates the lesson**, so the lesson gets no credit. |
| 6 | the-deployment-interpreter-is-not-the-one-on-your-path (09-20) | sym ``syntax error near unexpected token `;;'`` | 0 | – | – | 2 | No recurrence. |
| 7 | the-land-gate-is-admission-exempt (09-20) | cmd `until/while … bats-roots` | 0 | – | – | 0 | No signal. |
| 8 | bash-32-counts-parens-inside-a-heredoc (09-21) | symre `\.sh: line N: unexpected EOF while looking for matching` | 3 / 3 | 2 | 1 | 19 | Two are the lesson's own investigation (09-21T00:00/00:22). One is a wt-pool-5 /tmp quoting error, a different cause. **0 true recurrences.** |
| 9 | a-landed-verdict-is-not-a-tested-verdict (09-21) | sym `behaviorally UNGATED` | 22 / 17 (12/5) | 17 | 0 | 22 | About 8 are source or doc reads (`sed -n … ship-land.sh`, `cat ship.md`). About 9 sessions got a real shed-smoke land. Whether they then ran their suites themselves was **not measured**. 17/17 had the hook resident. |
| 10 | soft-reset-onto-a-moved-ref (09-21) | cmd `git reset --soft origin/` | 0 | – | – | 1 | The single "before" hit is 2026-09-17T23:29 in wt-rules-tiering. It is **an earlier unnoticed instance of the same mistake, 3 days before the lesson's incident**. |
| 11 | tab-is-ifs-whitespace (09-22) | cmd `IFS=$'\t' read` | 43 / 20 (4/16) | 4 | 0 | 72 | This is a risk pattern, not a confirmed bug. 16 of the 20 sessions are subagents; about 4 main sessions are reso bottle-photography Bash loops, where the rule is **not resident**. |
| 11b | same | content (Write/Edit, non-.md) | 20 / 16 | 7 | 0 | 10 | Re-introduced into claude-infra scripts after the lesson: `scripts/limit-recover/lr-fleet.sh` (09-23, **the lesson's origin file**), `lr-upgrade.sh`, `bin/cc-lr`, `hooks/escalation-watch.sh`, `scripts/hero-film-render.sh`. Plus 10 writes by the controlled eval `tokeff-f3/runs/S01-tsv-empty-cell/*` (see below). |
| 12 | a-gates-invocation-is-part-of-its-contract (09-22) | cmd `shellcheck -x \| -S warning` | 10 / 9 (6/3) | 1 | 0 | 384 | Every after-hit, checked by hand, is in **another repo** (reso, ntts, or a /tmp script), where the claude-infra gate does not apply. **0 in-scope recurrences.** The 384 before-events show how strong the habit the lesson overrides is. |
| 13 | symlinked-auto-memory-dir-prompts-on-every-write (09-25) | memerr | 1 / 1 | 0 | 0 | 18 | The one after-hit is a deliberate probe (`/private/tmp/memprobe`, 09-27). The before-events are mostly read-before-write errors (see §2), not symlink prompts. Inconclusive. |
| 14 | symlinked-store-invisible-to-find (09-11) | cmd `find ~/.claude-next/projects` without -H/-L | 1 / 1 | 0 | 0 | 3 | The after-hit (mac-bootstrap, 09-15) starts at a *subdirectory*, so it is a false positive. **But this very research run hit the lesson's exact symptom**: `find ~/.claude-next/projects -name '*.jsonl' -mtime -30 \| wc -l` returned **0** while the store is the 2,222-file `~/.claude/projects`. The lesson was not in this worker's context: `omitClaudeMd`, and the memory lives in claude-infra's store. |
| 15 | worktree-ops-can-bare-the-shared-checkout (09-05) | sym `fatal: this operation must be run in a work tree` | 22 / 20 (16/4) | 11 | 2 | 0 | **The strongest re-learning evidence.** The symptom recurred fleet-wide on 09-05, 09-06, 09-08 and 09-14. Several sessions re-diagnosed it from scratch: `git rev-parse --is-bare-repository` / `config core.bare` probes at 09-06T11:10 cloud-drain-floor and 09-08T22:09 wt-9002948e, and `env \| grep GIT_ … is-bare` at 09-06T14:45 sevenrooms-bridge (not resident). Only **2 of 20** had touched the memory before hitting the symptom, and 9 of 20 did not have it resident. |
| 16 | hermetic-in-stubs-not-in-interpreter (07-27) | symre `^1..0$` in Bash output | 4 / 3 | 3 | 1 | – | 3 sessions saw a zero-test bats plan. Whether they treated it as a pass was not measured. |

**Totals over all 16 lessons and signal kinds** (an3.out `Counter`):
- 251 session-hits after the effective date.
- 179 (71%) had the lesson's hook **resident**.
- **10 (4.0%) had actively touched the lesson (a read/grep of its body or hook text) before the hit**, and 17 (6.8%) at any time in the session.

**Adjudicated to confirmed recurrences of the forbidden mistake after the lesson existed** (hand-verified): never-wrap-ship 2 sessions (+2 ambiguous), never-write-tracked 1, worktree-ops-can-bare about 4 re-diagnoses, tab-is-ifs 5 claude-infra script writes (risk pattern). **Every confirmed recurrence came from a session that did not open the lesson.** Half had it resident and ignored it (3222585b; wt-9002948e). The other half were **outside the lesson's project scope**: a session in `fde-endpoint-business-case` landing claude-infra, a sevenrooms-bridge session diagnosing claude-infra's checkout, and this `omitClaudeMd` worker.

**Before and after, where there is enough data:** the claude-infra timeout-wrap rate fell from ~3.2 to ~0.2 sessions/day (ESTIMATED from the counts above). For the other lessons, the in-window "before" counts are either too small, or the drop predates the lesson (max_turns).

**Existing in-house instrument found:** `docs/research/token-efficiency-2026-09-23/eval/harness/f3/tasks/S01-tsv-empty-cell/` plus `/private/tmp/tokeff-f3/runs/S01-tsv-empty-cell/r*/`. It is a controlled replay that measures whether an agent re-introduces the TSV bug with and without the rules. Its runs are among the 11b content hits. Its verdict was not read here, as that is outside this axis. It is the right harness for an A/B test of any TrueMemory-style recall.

## 4. Operator corrections as a proxy for memory misses (prompts-typed.jsonl, corrections-*.{tsv,txt})

- Narrow regex set (`i told you`, `we already`, `remember`, `as i said`, `how many times`, `you keep`, `same mistake`, `forgot`, `last time`, `again`) on 2,122 strict typed prompts:
  - again 59
  - last_time 13
  - remember 6
  - you_keep 4
  - we_already 3
  - same_mistake 1
  - i_told_you 0
  - how_many_times 0
  - **82 prompts in total, 27 with a non-"again" tag.** Most long ones are dispatch briefs using "again" in the sense of "re-run".
- Extended regex (it adds `before|like normal|every time|flip-flop|regress|lost the|keep forgetting|I asked this|used to|still doesn't`) on **1,508 operator-like prompts**: 110 matches, all read by hand (`corrections-short.txt`).
- **Hand classification, cross-session memory misses** (the operator re-supplies or complains about something a prior session knew): **10 incidents in 30 days**:
  - #10/#11 (08-29, personal): "improve our memory/skill/docs for you to fully read our WhatsApp thread … next time"; "i feel like youre not reading our memory/notes at all".
  - #13 (08-29): "i swear that was the one thing that helped last time".
  - #47 (09-12, reso): "do our own manual Google images download curation again like normal".
  - #48 (09-12): "how can we have this instead of keep forgetting every single time?"
  - #66/#67 (09-16, kitty): "we lost the click title to drag again … flip flopping … for the past two days". This became the 09-17 OPERATOR RULING lesson.
  - #78 (09-21, personal): "like we did before with our other wifi channels at our past visited cafes". Then #83 asks for a runbook.
  - #88 (09-22): "check our git history … I feel like we used it 2-3 times".
  - #106 (09-26, reso): "I asked this before with a Dynamic Workflow about a week ago … got no actionable work/results back … Can we retrieve that research".
  - #110 (09-27, this task): "(we may have done this before)". **Measured answer:** no mention of TrueMemory or buildingjoshbetter in `docs/`, `.claude-plans/`, `commands/`, any memory store, or any retained transcript except today's. Transcript retention only reaches back to 2026-08-19 (oldest file measured with `ls -tr`), so an older investigation could not be ruled in or out from transcripts.
- **Standing rules or preferences restated by the operator** (a softer miss): 4:
  - #29 "Remember commands given to a user is something that you can't run"
  - #58 "remember to not jump into implementation until we sign off"
  - #70 "Remember: Pyramid Principles…"
  - #79 "Remember: we aren't signed off on a bottle until we have human sourced the images".
- In-session repetitions (context, not memory: #2, #50, #52), "try again" retries and briefs were excluded.
- **Result:** 14 memory-miss prompts out of 1,508 operator-like prompts (0.9%), in about 12 sessions out of 917 human-driven sessions (1.3%). **ESTIMATED** as a lower bound: the regex only catches misses the operator voices, and dispatched sessions have no operator to voice them. The misses cluster in **personal / episodic / procedural** content (moving, cafes, image-curation process, prior research outputs), not in engineering rules.

## 5. What this says about the gap a TrueMemory-style retrieval would close

Code facts are **MEASURED by reading /tmp/truememory-src**. Effect sizes are **ESTIMATED**.

1. **Retrieval is the gap, not capture.**
   - Measured: capture 6.8% / 22.1% of sessions; consult 2.0% / 5.6%.
   - Measured: 95% of the infra store and 87.5% of lesson bodies go unread in a month.
   - Measured: the cold archive is read about once a month.
   - Every confirmed recurrence in §3 was a session that never opened the lesson.
   - An automatic, relevance-ranked recall would target exactly this. So would any retrieval that does not depend on the agent choosing to `cat` a file.
2. **The trigger mismatch matters.**
   - Our re-learning signals arrive in **tool outputs, mid-turn** (Bash stderr/stdout). The operator's typed words are not where they show up.
   - Only 27.6% of sessions contain a typed human prompt at all.
   - TrueMemory's recall fires on `SessionStart`, `UserPromptSubmit`, `SessionEnd` and `PreCompact` only (`truememory/ingest/cli.py:853-856`). There is no PostToolUse hook anywhere in the tree (grep for `PostToolUse` found none).
   - Its UserPromptSubmit auto-recall has further gates: prompt length 10–500 chars, and it must match a question regex (`user_prompt_submit.py:624-629`, `_RECALL_RE` at :125). The "max" intensity searches every prompt with limit 10 (:544-620).
   - SessionStart recall uses 5 fixed personal-assistant queries ("user preferences…", "personal facts…", "recent decisions…", "corrections…", "relationships…", `session_start.py:1019-1025 (list at :1020-1024)`) plus directives. It does not use the cwd or the task.
   - Transcript ingestion drops all-tool_result turns (`truememory/ingest/transcript.py:251-254`).
   - **ESTIMATED:** as shipped, TrueMemory would close the §4 personal/episodic misses (about 10 per month). It would close almost none of the §3 engineering re-learning, because its triggers never see the symptom text. A PostToolUse(Bash) symptom→lesson matcher over our existing hooks and bodies is the missing piece.
3. **Scope leakage is a measured failure mode.**
   - Lessons live per repo (claude-infra rules and store) but are needed wherever the *tool* runs. Examples: claude-infra landed from the fde-endpoint cwd; sevenrooms-bridge diagnosing claude-infra's core.bare; reso Bash loops using `IFS=$'\t' read`; this omitClaudeMd worker hitting the symlinked-find trap.
   - A user-global index keyed on the tool or symptom, rather than on the cwd, would reach these sessions.
4. **Residency is a working mechanism, and it is expensive.**
   - The timeout-wrap rate fell about 15x once the hook was resident.
   - The DEFERRAL symptom appeared in 137 sessions with the hook resident in 123.
   - The cost is ~22K chars of lesson hooks and a mean 142K chars of total instructions per session. MEMORY.md is present in only 36.7% of sessions.
   - Retrieval would let hooks be demoted from resident to recalled without losing them. The archive tier shows that demotion without retrieval equals deletion (1 read in 30 days).
5. **Nudged capture works; unprompted capture barely happens.** Sessions write memory 43.4% of the time after a nudge and 2.4% without one (confounded). TrueMemory's SessionEnd auto-extraction would replace the nudge for long sessions. Our anti-capture rule (no transient errors, one-offs, lucky paths, unverified negatives or duplicates) would need to be ported into its extraction prompt or salience gate.

## 6. Caveats

- Signals for "read" and "consult" undercount any consult done through a subagent brief that pastes lesson text, and any that happens inside `python3 - <<EOF` heredocs (classed as other).
- The `resident` flag relies on hook phrase needles. A reworded hook would be missed.
- The before/after comparison in §3 has no control arm. Other simultaneous changes (brief templates, ship-land changes) are possible confounders.
- The correction proxy only sees what the operator voices, and only 917 sessions have an operator. It is a lower bound.
- `archive/nowhere.py` in the consult list is a path false positive (a non-memory `/memory/` path). It affects 3 events and no conclusion.
