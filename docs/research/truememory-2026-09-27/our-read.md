# OUR READ/RECALL PATH — what actually reaches the model, and how anything else is ever reached

Axis: our read/recall path (claude-infrastructure auto-memory + two-tier lessons). Written 2026-09-27.
Scratch scripts and intermediate data: /tmp/tm-research/scratch/ (reach*.py, cls.py, all14.tsv, orphans.txt,
unreachable.txt, cold_only.txt, registered.tsv).

Labels: **MEASURED** = I ran the command / read the bytes this run. **CLAIMED** = the repo's own comments or docs say
so and I did not re-derive it. **ESTIMATED** = computed by a stated heuristic.

Repo = /Users/chrisren/Development/claude-infrastructure. Store = ~/.claude/projects/-Users-chrisren-Development-claude-infrastructure/memory
(one physical store: ~/.claude-{secondary,tertiary,quaternary}/projects/<slug>/memory are symlinks to it, and
~/.claude-next/projects is a symlink to ~/.claude/projects; same inode 219280171, MEASURED with `readlink`/`stat -f %i`).

---------------------------------------------------------------------------------------------------------

## 0. One-paragraph answer

The read path is **push-everything-within-a-cap at session start, then pure model-initiated pull**. Every session
(main and subagent) gets MEMORY.md (after loader stripping) plus the always-loaded rules files as an `instructions`
attachment. Nothing else from the store reaches the model unless the model itself decides to `Read`/`cat`/`grep` a
file. There is **no relevance-triggered retrieval**: no hook reads a topic file or lesson body and injects it on a
prompt (confirmed by an audit of all 98 registered hooks, §5). The only UserPromptSubmit hook that touches memory
(memory-nudge.sh) injects a **write-side** nudge and budget line, never memory content. The situational rules half,
which the rotor and nudges describe as "loads by default", is in fact **excluded on every account** by
`claudeMdExcludes` (§2.3), so 68 topic files and 127 lesson bodies that are one hop from it are reachable only by
grep. Of 496 topic files, **150 (30%) are one hop from an auto-loaded surface; 192 (39% of files, 34% of bytes) are
not reachable from any auto-loaded surface even following [[wikilinks]] transitively**. In the last 14 days, 31 of
172 main sessions (18%) read at least one topic file and only 66 distinct topic files (13% of the store) were ever
read.

---------------------------------------------------------------------------------------------------------

## 1. What reaches the model at session start (the only push)

### 1.1 MEMORY.md — the index

- Loader behaviour (CLAIMED by the repo, carved from the 2.1.233 bundle): strip YAML frontmatter, strip column-0
  block HTML comments, trim, then truncate at **25,000 UTF-16 code units** or **200 lines**, dropping the TAIL
  (newest lines) and appending a `> WARNING:` line — hooks/lib/memory-index-measure.sh:13-28. Codepoints ≥U+10000
  count 2 — :49-50.
- Repo's own measure of the live index (MEASURED: `. hooks/lib/memory-index-measure.sh; mim_measure_file $M/MEMORY.md`):
  **23,448 units, 151 effective lines** (93.8% of the char cap, 75.5% of the line cap). Raw on disk: 24,702 bytes,
  159 lines (`wc -c -l`); `mim_overhead` = 1,254 (bytes the loader does not count). Oversized entries (>300 units,
  `mim_oversized_lines ... 300`): 0. Index mtime 2026-09-27 15:05.
- Entries: 148 `- [Title](file.md) — hook` bullets, median 155 units, max 272, sum 23,266 (MEASURED, reach2.py).
  Type mix of the 148 hot targets: feedback 80, project 35, reference 33 (MEASURED from topic frontmatter).
- Stripping VERIFIED in practice (MEASURED): the `AutoMem` attachment content in 5 recent transcripts starts
  `# Memory — claude-infrastructure`, contains no `cold tier` comment and no frontmatter. 0 of 172 main sessions in the
  last 14 days carried a `> WARNING` truncation line in their AutoMem attachment.
- The rotor holds it in a band (bin/cc-memory-rotate:243-248, shifted by overhead :318-325): rotate at
  LIMIT-1500 = **23,500 effective units** / 188 lines, target LIMIT-4000 = **21,000** / 168 lines. Current index is
  **52 units under the rotate trigger** (MEASURED arithmetic from the numbers above). archive/.rotate.log (MEASURED,
  read) shows 40+ rotations 2026-08-14 → 2026-09-22 (e.g. `2026-09-22T23:33:21Z moved=15 routed=15 before=24808
  after=22124`).
- Worktrees: the product keys AutoMem on the main worktree. MEASURED: 7 sessions in 2 worktree project dirs
  (`--worktrees-hero-brag`, `--worktrees-wt-pool-8`) loaded the MAIN slug's MEMORY.md although neither dir has a
  `memory` symlink. scripts/worktree-memory-link.sh (header :3-24, dated 2026-07-31) is therefore now redundant for
  the loader (it still matters for anything that resolves memory by cwd slug). Only 14 of 400 worktree project dirs
  carry the symlink (MEASURED bash loop).
- memory-fleet-sweep (MEASURED, report-only run `bash scripts/memory-fleet-sweep.sh`): 34 indexes, 0 over cap,
  0 DARK entries; claude-infrastructure 23448/151 "tight", reso-management-app 22347/103, doc-classifier 20847/64.

### 1.2 The two project rules files

| file | raw bytes | loader units (mim_measure_file) | lines | bullets | loads? |
|---|---|---|---|---|---|
| .claude/rules/agent-operating-lessons.md (resident) | 9,670 | 9,525 | 53 eff / 54 raw | 19 | YES, every session |
| .claude/rules/agent-operating-lessons-situational.md | 68,121 | 64,624 | 208 eff / 215 raw | 189 | **NO on every account** (§2.3) |

(MEASURED `wc -c`, `mim_measure_file`, `grep -c '^- '`.) No `paths:` frontmatter on either (MEASURED grep), so
absent the exclude both would load unconditionally. The resident file itself states a 150k cosmetic / 4 MiB hard
ceiling (agent-operating-lessons.md header; bin/cc-memory-rotate:252-271). The 4 MiB number is CLAIMED and flagged by
the rotor itself as "ENCODED HERE, NOT MEASURED HERE" (bin/cc-memory-rotate:263-269). Rotor WARN cap is 40,000
(:271) and the situational file is already at 64,624 units — over the warn cap, which the rotor deliberately
ignores (:493-506, "WARN, NEVER REFUSE").

### 1.3 Other always-loaded context (not memory, for scale)

MEASURED from `instructions` attachments across the last ~120 transcripts: User `~/.claude-next/CLAUDE.md` (slim
A/B variant, 53-106k chars), `~/.claude/rules/agent-operating-lessons.md` (6,209-6,334 chars, user-level rules),
`~/.claude/rules/00-mission-board.md` (2.3-13.8k), project `.claude/CLAUDE.md` (6,244). The global CLAUDE.md
carries the anti-capture list (CLAUDE.global.md:89-112) — write side, not recall.

### 1.4 Size of the memory push per session (ESTIMATED at ~4 chars/token)

MEMORY.md 23,448 + resident rules 9,525 = ~33.0k chars ≈ **~8.2k tokens** of memory-class context per session,
repeated in every subagent that loads instructions (204/300 sampled subagent transcripts had AutoMem, MEASURED;
the 96 without any instructions attachment look like omitClaudeMd workers).

---------------------------------------------------------------------------------------------------------

## 2. How a topic file or a lesson body is ever reached

### 2.1 Mechanism: only if the model decides to Read it

- No hook injects topic/lesson content (§5). The pointer shapes the model sees:
  - MEMORY.md bullets: relative link `(file.md)`; it resolves because the file sits beside MEMORY.md, and the model
    must know the store path (product system prompt carries it — CLAIMED, not observable in transcripts).
  - Resident rules → docs/lessons: `(../../docs/lessons/<slug>.md)` — 17 real bodies (18 links incl. the
    `<slug>` placeholder; MEASURED grep).
  - Resident rules → topic files: 2 (absolute `~/.claude/projects/.../memory/...` paths; MEASURED).
  - Situational rules → topic files: 41 **bare relative links** `(foo.md)` that resolve to `.claude/rules/foo.md`
    (0 of 41 exist there; 41 of 41 exist in the memory store — MEASURED), plus 22 absolute memory paths. I.e. even
    when that file loaded, 41 of its pointers were broken as written and required the model to guess the store.
  - Topic ↔ topic: `[[slug]]` wikilinks, 1,933 occurrences in 489 files, 1,813 resolving edges, 46 dangling
    (37 distinct targets) (MEASURED reach2.py). Zero markdown `(x.md)` links between topic files.
- The index hook is designed to make the Read unnecessary: resident rules header says the hook must "state the rule
  so a reader can act on it without opening anything" (agent-operating-lessons.md header), and the rotor's
  durability rank treats citation from `.claude/rules` as "live" (bin/cc-memory-rotate:1112-1160).
- No read ledger exists — stated by the rotor: "No read ledger exists — nothing in this repo records which memory
  files a session read" (bin/cc-memory-rotate:103-107). So eviction cannot use usage, and nothing measures recall.

### 2.2 Measured recall behaviour (last 14 days, all four config roots)

Method (MEASURED, with a regex classifier = ESTIMATED precision): 1,426 transcripts modified in 14 days across
~/.claude{,-secondary,-tertiary,-quaternary}/projects/<slug>/ → 58,869 tool_use records (all14.tsv) from 172 main
sessions and 990 subagent transcripts. A "read" = Read tool on the file, or a Bash cat/sed/head/tail/grep/awk naming
it. Includes maintenance reads, so these are UPPER bounds on recall.

| event | main (of 172) | subagent (of 990) |
|---|---|---|
| read ≥1 memory topic file | 31 (18%) | 28 (2.8%) |
| read/grep ≥1 docs/lessons body | 37 (21.5%) | 19 (1.9%) |
| touched the cold archive | 1 | 3 |
| touched the situational rules file | 4 | 8 |
| grep over the memory dir | 2 | 10 |

Distinct topic files read in 14 days: **66 of 496 (13.3%)**; distinct lesson bodies: 68 of 144. Since the
situational exclusion took effect (main sessions starting ≥ 2026-09-25, n=27): 2 touched the situational file,
3 read a topic file, 3 touched docs/lessons. An earlier narrower sample (65 main sessions, 4,246 tool uses, main
slug only) found exactly 1 Read-tool read of a topic file and 0 Read of docs/lessons or the archive.

### 2.3 The situational half does NOT load (contradicts the repo's own prose)

- MEASURED: `jq .claudeMdExcludes` on ~/.claude, ~/.claude-next, -secondary, -tertiary, -quaternary settings.json all
  = `["**/.claude/rules/agent-operating-lessons-situational.md"]` — installed by migrations/0036-rules-situational-exclude.sh:3,25
  (commits cb5f7109c split, e3ab4a25b all-accounts).
- MEASURED in transcripts: situational appeared in `instructions` on 2026-09-24 (6 sessions) and once on 09-25; 10 of
  11 later sessions loaded MEMORY.md + resident but not situational.
- STALE claims that it loads (all still on trunk): bin/cc-memory-rotate:27-29 ("which also loads by default"),
  :522-527 (routing default destination = situational), hooks/memory-nudge.sh:545,560 (the injected NUDGE tells the
  model the situational file "loads by default ... cannot be dropped"), hooks/memory-index-drain.sh:275,284
  (`drained`: "that file loads by default, so the rule still fires unprompted"; `already-cited`: tells the model to
  DELETE the MEMORY.md bullet because the rules file "loads by default"). Only the rotor's create-branch comment
  (:612-613) and commands/compact-memory.md:153-160 acknowledge "some accounts do not load this file; grep it".
- Consequence: every line the rotor ROUTED (routed=1/19/15 on 09-09/09-16/09-22 per .rotate.log and the
  situational file's comments at lines 4, 58, 67, 96, 194) and all 18 demotion pointers (line 13) moved from an
  auto-loaded surface to a grep-only one, while the actuator's verdict text says nothing was demoted. The only
  bridge is one sentence in the resident file: "Before diagnosing a failing test, gate, hook, land or tool, grep that
  file for the symptom."

### 2.4 Cold archive

- archive/MEMORY_ARCHIVE_2026-H2-COLD.md: 70,032 B, 63,751 units, 433 eff lines, 285 bullets / 285 resolving links;
  archive/MEMORY_ARCHIVE_2026-H2.md: 6,814 B, 6,710 units, 16 bullets (MEASURED). Plus 19 pre-compact snapshots
  (MEMORY_INDEX_PRE-COMPACT_*, MEMORY_PRECOMPACT_*) of ~23-29 KB each.
- The pointer to the cold tier in MEMORY.md is itself a block comment (MEMORY.md raw lines 3-10) and is **stripped
  by the loader**: MEASURED `mim_effective_file | grep -c -i 'cold\|archive'` = 0. The model's only visible pointers
  to the archive are 1 mention in the resident rules file and 18 in the (excluded) situational file.
- Cold type mix: project 175, reference 60, feedback 50 (MEASURED).

---------------------------------------------------------------------------------------------------------

## 3. Index-vs-store ratio (the reachability census)

MEASURED by /tmp/tm-research/scratch/reach2.py + reach3.py (partition of 496 topic files, 1,886,010 bytes; median
2,908 B, p90 6,304, max 38,510; frontmatter present on 496/496 with name+description+metadata.type; types project
258 / feedback 135 / reference 103).

| class | files | % files | bytes | how the model gets there |
|---|---|---|---|---|
| A. one hop from auto-loaded (MEMORY.md 148 + resident rules 2) | 150 | 30.2% | 617,657 (32.7%) | Read the linked file |
| B. only via the situational rules file (excluded) | 68 | 13.7% | — | grep situational, then Read |
| C. only in the cold archive | 267 | 53.8% | 1,048,241 (55.6%) | know the archive exists, open it, then Read |
| D. true orphans (no index, no rules, no archive, no inbound [[link]]) | 11 | 2.2% | 28,176 | only a directory listing / grep |

Transitive via [[wikilinks]] from class A: +111 at depth 1, +35 at 2, +7 at 3, +1 at 4 → 304 files (61%) reachable
by link-following from auto-loaded surfaces; **192 files (38.7%), 632,398 bytes (33.5%) are unreachable from any
auto-loaded surface even with unlimited link-following** (unreachable.txt). 139 of the 267 cold-only files are also
outside that closure. 183 files have zero inbound wikilinks. Orphans (orphans.txt) are all 2026-09-08..16 — the
period the index sat at cap — e.g. instrument-must-have-an-as-built-mode.md (0 repo references), others cited 1-8
times from repo files (git grep), so a few are reachable via docs/code rather than memory surfaces.

docs/lessons: 144 bodies, 498,682 B (median 3,257, max 13,876). All 144 are linked from the rules files (0 orphans,
MEASURED comm), but only 17 from the resident file; **127 (88%) are reachable only via the excluded situational
file**. Lesson bodies cross-link to other lessons/memory in 17 of 144 files.

Frontmatter `description:` fields: 496 present, 98,167 chars total, median 178 — **never loaded by anything**
(only visible after a Read). This is a ready-made per-fact retrieval key corpus.

---------------------------------------------------------------------------------------------------------

## 4. File-by-file notes (read path relevance)

- **hooks/lib/memory-index-measure.sh** (182 lines): single measurer; loader emulation :62-77 (frontmatter strip,
  column-0 comment strip skipped entirely if any ``` fence, trim, UTF-16 units, line count); caps env-overridable
  25000/200/300 :81-102; mim_overhead :174-182 warns that raw-vs-effective gap has been mis-filed as a breach 3+
  times (:151-166). Leans to under-strip (safe direction) :41-50.
- **bin/cc-memory-rotate** (1,606 lines): write-side actuator but defines what stays readable. Protection order
  :53-71 (tail guard 15, PINNED, feedback/reference/user type or name prefix, live-pending markers, hubs ≥4 inbound
  [[links]], young <7 d mtime, MIN_KEEP 40); durability rank :73-107, :1143-1160 (0 = `superseded_by:`, 1 = no
  consumer, 2 = cited by name in bin/hooks/scripts/migrations/commands/.claude/rules :1112-1140); "no read ledger"
  :103-107; routing to rules file :26-41, :516-528; drain mode :137-160; verbatim + verify + temp/rename + mkdir
  lock :109-118. Selection uses **citation in code** as the proxy for "load-bearing", never usage.
- **hooks/memory-nudge.sh** (566 lines, UserPromptSubmit, every prompt): runs the rotor when over threshold and,
  on prompt 1 when over cap or every 12th prompt (:46, :496-502), injects `MEMORY INDEX BUDGET (live)` + the
  `MEMORY CHECK` write nudge (:560-565). Contains no memory content. Resolves the index from the session's cwd via
  git-common-dir (:68-100) — so it only ever rotates the open project (memory-fleet-sweep.sh:5-17).
- **hooks/memory-index-drain.sh** (PostToolUse): drains >300-unit index lines to the rules file and injects a
  verdict (:275-290) — stale "loads by default" wording (§2.3).
- **hooks/session-start.sh** (422 lines): **no memory part at all**; its additionalContext is effort warning + MCP
  status (:363-420); renders ~/.claude/rules/00-mission-board.md (:367-412) which then loads NEXT session.
- **hooks/recover-inject.sh** (209 lines): UserPromptSubmit design that injects a limit/crash recovery ledger from
  the transcript tail (:1-45, :204-205). **Not registered** in any account's settings.json (MEASURED jq; docs/parks/
  4236edc78a72.md:15 says migration 0026 is staged, operator-run). Not memory recall either way.
- **hooks/dod-persist.sh** (429 lines, SessionStart + PreCompact): the one existing *re-injection* mechanism —
  re-injects the per-repo frozen DoD/scope file as additionalContext at session start (:6-9), lineage-filtered
  (:201-290); captures `Scope (frozen):` lines at PreCompact by grep, no model (:10-16). Store ~/.claude/autonomy/dod:
  77 files, 744 KB (MEASURED). It is keyed on repo identity, not relevance.
- **scripts/worktree-memory-link.sh** (179 lines): symlinks a worktree's project memory to the primary via
  git-common-dir (:3-24, :88-100). Superseded for the loader by product behaviour (§1.1).
- **scripts/memory-fleet-sweep.sh** (147 lines): report-only census of every index's DARK (tail-dropped) entries
  (:1-33). Ran it: all 0.
- **bin/cc-memory-dropped-token-audit** (236 lines, python): write-side audit that a compaction did not destroy
  hard tokens (code spans, SHAs, numbers, ALL-CAPS) that existed only on the index surface (:1-50). Relevant to
  recall only in that it treats the index hook as a store of facts not guaranteed to be in the body.
- **docs/research/memory-index-premise-refuted-2026-08-24.md**: recurring false "over cap" items came from `wc -c`
  bytes vs loader units (:21-35); the cure was an append-time gate + automatic rotor, not a human pass (:37-57); the
  index was hand-compacted 12 times 2026-07-25..08-06 and re-breached every time (:41-44).

---------------------------------------------------------------------------------------------------------

## 5. "No relevance-triggered retrieval today" — CONFIRMED

MEASURED: extracted every registered hook from ~/.claude/settings.json (98 event/command pairs, registered.tsv;
all four other accounts share the same memory hook set). Live UserPromptSubmit hooks: handed-off-session-guard,
cache-expiry-warning, **memory-nudge**, handoff-intent-nudge, research-precognition-nudge, session-beat, mailbox-drain.
Grep of each for `memory/|MEMORY.md|docs/lessons|agent-operating-lessons`: only memory-nudge.sh matches (26 refs),
and it emits budget + write-nudge text only. Across all registered hooks, the only non-comment memory-path code is
in memory-index-drain.sh (drain verdicts), backup-before-write.sh:50-53 (PreToolUse write gate/backup). No hook
reads a topic file, a lesson body or the archive and emits it as additionalContext. Transcript attachment census over
40 recent sessions: no product attachment type for memory recall exists besides `instructions` (AutoMem/Project/User
files) — no `relevant_memories`/`nested_memory` types observed (MEASURED jq over attachment.type).

Pull tools that exist but are not wired to memory: `~/.claude/bin/claude-search` → ~/Development/claude-session-search
(session transcript search, other repo; docs/plans/MEMORY_KNOWLEDGE_V2.md:254-260). The session-index producer hooks
are in this repo (same plan :256-258). No CLI searches the memory store by relevance.

---------------------------------------------------------------------------------------------------------

## 6. Gaps on this axis (what a TrueMemory-style read path would change)

1. **No query-time retrieval.** Recall = what fits in 23.4k chars chosen by recency+durability rules, plus whatever
   the model happens to open. 70% of topic files and 88% of lesson bodies are not one hop from anything loaded.
   A UserPromptSubmit (or PreToolUse on Bash/Edit) hook doing FTS/BM25 over name+description+hook (98k chars of
   descriptions already exist) and injecting the top-k hooks (not bodies) would be the minimal TrueMemory-shaped
   addition; it must respect the budget lessons (fixed small k, dedupe against what is already in MEMORY.md).
2. **Situational exclusion silently converted "routed" into "demoted".** Rotor/drain/nudge text still tells the
   model it loads. Either retrieval must cover it (it is exactly the "fires on a specific kind of work" set that
   relevance-triggered injection is for) or the prose must be corrected.
3. **No read ledger** (bin/cc-memory-rotate:103-107). Eviction and "is this memory useful" have no usage signal;
   TrueMemory-style access counting/salience would need one. The transcript census here (§2.2) shows it can be
   computed offline from tool_use records.
4. **Cold archive pointer is invisible** (stripped comment). 267 cold-only files (55.6% of store bytes) are
   reachable only by someone who already knows the archive path.
5. **Broken relative links** in the situational file (41/41 resolve only in the memory store).
6. **11 orphans** written while the index was at cap; nothing detects them except /compact-memory's manual E1-E3
   sweep (commands/compact-memory.md:140-170).
7. **Wikilink graph unused at read time**: 1,813 edges, but nothing follows them for the model; hub status only
   protects index lines from eviction (bin/cc-memory-rotate:68).

## 7. Deviations / limits

- A dry-run of cc-memory-rotate on a `cp -Rp` copy of the store under /tmp was **denied by the permission system**;
  I did not retry or work around it. Keep-class counts for the live index are therefore not reported.
- I read (did not modify) ~/.claude*/settings.json (jq) and transcripts to establish hook wiring and load behaviour;
  no config, hook or memory file was written. All writes are under /tmp/tm-research/.
- Transcript read classification is regex-based (cls.py) and counts maintenance reads; treat §2.2 as upper bounds.
