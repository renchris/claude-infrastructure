# Gap 3: would agents call `cc-memory-search` if the only wiring is a prose line?

Date 2026-09-27. Worker notes for the TrueMemory study. Labels: **MEASURED** means I ran or read it here (the command is named).
**CLAIMED** means another note says so. **ESTIMATED** means the method is stated.
Scratch, scripts and outputs are in `/tmp/tm-research/gap3/`. The ready-to-run A/B is in `/tmp/tm-research/gap3/ab/`.

## 0. Answer

**No. Existing evidence says an instruction-only consumer will leave invocation near zero.** The live A/B was not run (§1).
It is now optional: it would narrow the bound, and it would not change the direction. Two prose "search first" lines already
exist in our instruction set, and both have been measured under the conditions #4's line would face:

| existing prose pull line | where measured | followed | rate (Wilson 95%) |
|---|---|---|---|
| `.claude/rules/agent-operating-lessons.md:33` "Before diagnosing a failing test, gate, hook, land or tool, grep that file for the symptom" (added in `cb5f7109c`, 2026-09-23) | f3 controlled headless replay, exclude arm, bug tasks S01-S05 whose prompt is exactly "tests/X.bats is failing, fix it" | **0/22** | 0% (0-14.9) |
| same line | real sessions 09-24..09-27 with the line resident and a strict `not ok N` tool result, harness runs excluded | **0/32** | 0% (0-10.7) |
| same line, pooled | | **0/54** | 0% (0-6.6) |
| same line | every real session with the line resident (218) | 0 symptom greps; the 9 touches were all authors appending a lesson or documenting the folder | — |
| `CLAUDE.global.md:103` "Anything already indexed — grep `MEMORY.md` first" | real sessions with the rule resident that **created** ≥1 memory topic file with Write (64) | **2/64** ran a term search of MEMORY.md or the store before the first new file | 3.1% (0.9-10.7) |
| same | same, loose: any `ls`/read/grep of the index or memory dir in the 3 calls before the first new file | 12/64 | 18.8% (11.1-30.0) |
| uninstructed pull CLI (`claude-search`, named only in passing at `commands/handoff.md:600`) | all 3,318 main sessions, 30 days | 14 sessions, mostly `which`/`command -v` probes; 1 genuine recall query | 0.42% (0.3-0.7) |

**Consequence for SYNTHESIS.** #4 remains worth building, but as a **substrate**. Its prose wiring does not remedy the
binding problem. The push consumers that bind, **#6 and #10, do not depend on #4** (`SYNTHESIS.md:65,69`), so they need not
wait for it. The dispositions change as set out in §6.

## 1. Why the headless A/B was not run (a precondition failed)

- The in-house harness `docs/research/token-efficiency-2026-09-23/eval/harness/f3/run-f3.sh:69-77` runs
  `CLAUDE_CONFIG_DIR="$CCD"`, which is a **real account config dir** (`GATE.md:626` passes `~/.claude-tertiary ~/.claude-quaternary ~/.claude-next`).
  Every run therefore writes its transcript and session state under `~/.claude*` and fires that account's user hooks.
  MEASURED: the f3 S01 r1 transcript carries 10 `hook_success` attachments.
- No isolated credential exists. MEASURED with `env | grep -iE '^(ANTHROPIC|CLAUDE)'`, names only: no `ANTHROPIC_API_KEY`.
  A fresh `/tmp` config dir would need a keychain login, and `--bare` needs an API key.
- The brief forbids touching `~/.claude` config and stores. My worker rules forbid editing anything under `~/.claude*`.
  So the A/B is **operator-run**. I built it and dry-ran it with the model call stubbed (§5).

## 2. Evidence 1: the controlled replay already ran this A/B for a sibling line (MEASURED)

Command: `/tmp/tm-research/gap3/pullscan.py` over every unique transcript under `~/.claude*/projects/*tokeff*`, deduped by realpath.
That is 1,858 files, 1,801 of them main sessions with at least one tool call (`gap3/tokeff-scan.jsonl`).

- **f3 gate plus targeted re-run.** 89 main transcripts, with arms joined from `eval/f3/runs.jsonl` and `eval/wave2/f3-targeted/runs.jsonl`.
  - S01-S05 are planted bugs that a situational lesson covers exactly. The prompt is "tests/X.bats is failing, fix it".
  - In the **exclude** arm the situational file is not loaded. The only route to it is the resident line 33
    (identical at frozen sha `b8dbe299a`, `git show b8dbe299a:.claude/rules/agent-operating-lessons.md` line 33).
  - Result: exclude arm **0/22** grepped or read the situational file. Control arm 0/22. Lesson bodies: 1/44, control S05 r5,
    which `ls`'d `docs/lessons/a-dead-first-stage-reads-as-a-clean-no-match.md`.
  - This agrees with `GATE.md:526` ("Not one of the 20 exclude runs grepped the file, although the resident half tells them to").
  - The S06 and S08 "pulls" are task artefacts: S06 edits `scripts/lesson-index.sh`, and S08 documents `docs/lessons`.
- **All 1,801 headless eval sessions.** Memory index or topic pulls: **0**. `claude-search` / `cc-memory-*`: **0**.
  Lesson-body touches: 18, all f3 S05/S06/S08 or research worktrees.
  - Caveat: fixture runs have no MEMORY.md. There is no AutoMem entry in the `instructions` attachment, because the fixture
    slug has an empty store, so memory pulls there could only go through absolute paths.

What this does and does not show:
- It **shows** that a resident instruction naming the exact trigger, facing the exact trigger, drew 0 invocations in 22 runs.
- It **does not** separate "ignored the line" from "did not need it". `GATE.md:525` says all 40 bug runs fixed the bug and named
  the root cause without the lesson. Low need is part of the real condition, though. Most memory-relevant moments look like
  this to the model, and that is why the recurrences in `our-usage.md:131` happened with the lesson resident.

## 3. Evidence 2: natural experiments in real sessions (MEASURED)

Command: `/tmp/tm-research/gap3/natexp.py` over the 3,318 deduped main sessions of the 30-day window. The list is rebuilt from
`scan/files3.jsonl`, keeping the longest copy per basename; 4.44 GB were scanned in full. Output: `gap3/nat-all.jsonl`.

### 3a. Line 33, read time (failure → search)
- 218 sessions have the line-33 needle ("grep that file for the symptom") in their `instructions` attachment. All date from 09-24 to 09-27.
- 71 of them have a failing test or gate in a tool result by the loose regex. 58 match strictly on `not ok N` (re-verified by
  re-reading each transcript). Of the 58, 26 are the `/private/tmp` f3 runs and **32 are real** sessions (18 worktree, 14 infra).
- Symptom greps of the situational file: **0/58**.
- Any touch of the situational file across all 218 sessions: 9. By hand, 2 are authors appending a new lesson
  (`5714603f`, `b4096cd5`: `tail -3 …situational.md`) and 7 are f3 S08 runs documenting the folder.
- Caveats:
  - `not ok` includes deliberate TDD reds.
  - Some of the 32 had the situational file loaded, where a grep is redundant (0036 is per account).
  - The window is only 4 days.

### 3b. `CLAUDE.global.md:103`, write time (new memory → search first)
- The proposed #4 consumer **replaces this exact line** ("`cc-memory-search <terms>` first (falls back to grep MEMORY.md)",
  `SYNTHESIS.md:240`). Its measured compliance is therefore the most direct baseline for #4's prose wiring.
- 88 sessions created ≥1 new topic file through the Write tool, detected by the `created successfully` tool result.
  64 of them had the rule needle resident.
- **Strict** (a keyword grep of MEMORY.md or the store before the first new file): **2/64**. Both are hand-audited:
  `ff4a9767` ran `grep -n "accounts" $M/MEMORY.md` one call before, and `f041b7d9` ran `grep -n -i 'ms365' $M/MEMORY.md` two calls before.
  Clause dump: `gap3/A-clauses.tsv`.
- **Loose** (any look at the index or dir within 3 calls before): 12/64. These are mostly `ls …/memory/`, which is a
  filename-level look and not a term search.
- Per file: 125 new files, of which 25 came after any in-session memory search.
- Blind spot: MEMORY.md is resident, so a model can "grep" it mentally. That is invisible here, which makes these figures a
  lower bound. The vitest pair (`our-write.md:184-186`, both copies hot) shows the mental check failing.
- Bash-created files (`cat > …`) are not counted. `SYNTHESIS.md:420` puts that door at about 18%.

### 3c. Base rates for pull CLIs and procedure steps
- `claude-search`: 14/3,318 main sessions (0.42%). It appears in no resident instruction (MEASURED:
  `grep -n claude-search ~/.claude/CLAUDE.md ~/.claude/rules/*.md` returns 0; the repo has only `commands/handoff.md:600` and a helper).
  The hits are mostly `which claude-search` probes. One is a real query ("floor plan layer toggles…").
- `/compact-memory`, which is #4's second consumer (step 7 candidate pairs, `SYNTHESIS.md:241`): at most **12** sessions in 30 days.
  Method: `grep -l '"skill":"compact-memory"|command-name>/compact-memory'` over the 3,318 files, so this is an upper bound.
  Procedure steps are followed well once a procedure runs; the one audited run did invoke `cc-memory-rotate`. But the
  consumer fires about 12 times a month at most.
- `cc-memory-rotate` in 44 sessions is not prose uptake. It comes from rotor and drain development and hook-driven paths.

## 4. Evidence 3: house doctrine already says advisories do not bind (MEASURED reads)
- `hooks/memory-index-drain.sh:34-35`: "Detection without an actuator is worth zero here, and that is measured, not asserted:
  the advisory has been correct and ignored for a month."
- `hooks/memory-index-drain.sh:24-29`: memory-nudge's prompt-time advisory is "the DEAD CLASS".
- The infra MEMORY.md:28 index line `enforcement-must-live-at-the-chokepoint.md` (read-only grep of the store).
- Contrast with timing: an injected, event-timed nudge converts 43.4% of sessions against 2.4% un-nudged (`our-usage.md:74-78`, CLAIMED
  there and confounded by session length). Residency works when the resident text **states the rule** (the timeout-wrap rate fell
  about 15x, `our-usage.md:108`). A resident line that says "go look elsewhere" is followed about 0% of the time (§2, §3a).

**ESTIMATED prior for #4's prose line.** Take 0-10% invocation at its trigger. Method: the pooled Wilson upper bounds of the two
analogous lines (0/54 → ≤6.6% at read time; 2/64 → ≤10.7% for a strict search at write time).
- One factor could raise it: a **named, novel CLI** may be more salient than "grep that file".
- One factor lowers it: the #4 line sits in a user CLAUDE.md of about 40.8k tokens (`GATE.md:507`), not in the 3.7k resident rules.
- The A/B in §5 prices the first factor.

## 5. The A/B, ready to run (operator-run; NOT executed)

Files in `/tmp/tm-research/gap3/ab/`:
- `run-ab.sh <line|noline> <task> <rep> <config-dir>`. Derived from `run-f3.sh`: the same frozen fixture (`/tmp/tokeff-f3/snap.git`),
  the same `sandbox-guard.sh`, no MCP, and a scrubbed pane env. Additions:
  - a **frozen store copy** per run at `$RUN/mem`, loaded through `--settings {"autoMemoryDirectory": …}`.
    flagSettings is honoured: `vK()` scans `["policySettings","flagSettings",…,"userSettings"]` (`_cc_strings.txt`, grep `autoMemoryDirectory;if(s!=null)`).
    Every write lands in the copy, and the before and after sha manifests catch duplicates;
  - the prototype `cc-memory-search` on PATH **in both arms**;
  - **one line** planted after line 33 of the fixture's resident rules in the `line` arm only.
- `cc-memory-search`: a stdlib FTS5 prototype over the store, `archive/` and `docs/lessons`. It logs each call to `$CCMS_LOG`.
  Smoke test: the core.bare query ranks `worktree-ops-can-bare-the-shared-checkout.md` #2 in 0.88 s wall.
- `tasks.tsv`, 12 tasks:
  - R01-R06: read-time symptom questions with a stored gold. R04 and R06 golds are **resident** hooks and act as a no-need control.
  - W01-W06: "save this lesson". W01-W03 delete the **newer** twin of a real duplicate pair from the copy (nohup, pipefail,
    predicate) so that the old twin is the only prior copy. W04-W06 restate an existing rule.
- `score.py <runs-root> <config-dirs…>`. It reports per arm: cc-memory-search invoked, any memory search, gold read, and for
  write tasks **duplicate created vs gold edited**. The last is the harm outcome, not just uptake.
- Dry run (MEASURED, `CLAUDE_BIN=/usr/bin/true`): both arms build. The arm diff is `+2` lines in the rules file only. The W01
  twin is removed from both the files and MEMORY.md. `settings.json` carries `autoMemoryDirectory`, and `score.py` runs.
  The dry dir is `/tmp/tm-research/gap3/ab-dry/`; my `rm` of it was refused by the permission layer and it was left in place.

**Pre-registered rule** (`score.py` header):
- line-arm invocation ≥30% with one-sided Fisher p<0.05 → the prose consumer counts;
- below 10% → substrate only;
- between the two → extend to 30 per arm.

**Power** (MEASURED by simulation, 4,000 draws, baseline 2%). At 20 per arm, detection probability is 0.91 for a true 40%,
0.67 for 30% and 0.30 for 20%. At 12 tasks × 2 reps × 2 arms = 48 runs, the cost is about $41-52 (ESTIMATED from GATE.md's
$0.854-1.079 per f3 run).

## 6. What changes in SYNTHESIS.md

1. **#4 derived-fts5-memory-search.** Keep build-now, but **re-scope it to substrate**: the CLI, one shared scorer, invocation logging
   (already planned, `SYNTHESIS.md:243`), and #5's eval arm.
   - Drop the claim that shipping the prose consumers (`SYNTHESIS.md:238-242`) addresses the 2% consult rate.
   - The `CLAUDE.global.md:103` rewording is XS and harmless, so keep it, but book no uptake for it.
   - Rewording `.claude/rules/…:33` gains nothing measurable (0/218).
   - Conviction as the **lead remedy**: 78 → about 60. Conviction as **substrate**: about 72.
   - Add a 30-day read of its own invocation log. If it is invoked in fewer than 5% of sessions that hit a failing test or write
     a new memory file, stop listing any prose line as a consumer.
2. **Wave order.** #6 (symptom recall at the emitters and on tool output) and #10 (write-time neighbour advisory) are the push
   consumers for the two moments measured above: failure-time and write-time. Neither depends on #4 (`SYNTHESIS.md:65,69`).
   Move them **into Wave B beside #4**, not after it. #10 is the real write-time consumer that `CLAUDE.global.md:103` never was:
   2/64 compliance against the IDF top-1 twin found in 8/8 directions (`SYNTHESIS.md:408-409`).
3. **#23 and native `memorySelector` prefetch** are the only **read-time** push paths that use a search substrate
   (`SYNTHESIS.md:617-619`). If `tengu_moth_copse` flips on, #23 steps aside, and #4's remaining consumers are #5, #16 (about 12
   compact-memory runs a month at most) and manual use. #4 stays justified by #5 and #16 at S-M cost, but it is not the binding-problem lead.
4. **Verdict line §1.1.** Keep "a lexical search index over the whole store". Add that the binding problem is closed by **push at
   the moment of need** (#6, #10, #23/native), with #4 as their shared index. That is the real lever measured here, and it matches the
   drain's own "actuate, don't advise" doctrine.
5. **#9 visible-cold-tier-pointer** is also a prose pull line ("Grep here before concluding a rule is absent"). By the same evidence
   expect about 0-5% uptake. Its value is truthfulness (the count and the path), not recall. Efficacy was already 58
   (`SYNTHESIS.md:393`), and conviction 74 → about 68 unless the A/B shows a named pointer works.

## 7. Threats to validity
- The f3 tasks are low-need: the model knew every fix. The natural sessions have no control arm, and the line-33 window is 4 days.
- Needle-based residency misses reworded copies. The classifier counts clause-leading verbs only, so a `python3 - <<EOF` pull is missed
  (`our-usage.md:198`).
- The write-time rate cannot see a mental check against the resident MEMORY.md.
- None of this measures a **named new CLI with a crisp trigger**. That residual is exactly what §5 would settle.
