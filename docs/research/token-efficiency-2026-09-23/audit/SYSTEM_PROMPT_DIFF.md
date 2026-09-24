# System prompt diff: keep, rewrite, delete or move, line by line

This is the line-level record behind the slim always-loaded instruction files. Every row names a span of the original file, its label, the reason code and, where one exists, the hook, script or tool that already enforces it and where the content now lives. Rows are copied verbatim from the per-chunk label files (after each chunk's verify and fix pass); notes that sit below the tables stay in those files and are linked per chunk.

Labels: KEEP (unchanged), REWRITE (same rule, plain description, emphasis removed), DELETE (history, duplicate, default model behaviour, or covered by a tool; the full text stays in the reference `~/Development/claude-infrastructure/CLAUDE.global.md`), MOVE (to a skill, command, hook message or doc that loads when needed). For `.claude/rules/agent-operating-lessons.md` the lesson bullets use RESIDENT (stays always-loaded) and INDEX (one line in the proposed `docs/lessons/INDEX.md`). NEW marks a line added in the slim text with no original. Sizes: characters (`len`) and bytes (`wc -c`); line numbers refer to the original file named in each section heading.

## Summary

| Source file | Chunk | Original chars / bytes | Slim chars / bytes | Rows by label |
|---|---|---|---|---|
| `CLAUDE.global.md` 1-159 | C1 | 11,169 / 11,278 | 6,372 / 6,372 | KEEP 5, REWRITE 34, DELETE 12, MOVE 5 |
| `CLAUDE.global.md` 160-331 | C2 | 12,906 / 13,026 | 7,041 / 7,056 | KEEP 10, REWRITE 30, DELETE 3, MOVE 1 |
| `CLAUDE.global.md` 332-451 | C3 | 18,806 / 19,047 | 8,845 / 8,852 | KEEP 12, REWRITE 39, DELETE 10, MOVE 3 |
| `CLAUDE.global.md` 452-805 | C4 | 33,843 / 34,480 | 13,921 / 14,095 | KEEP 31, REWRITE 49, DELETE 21, MOVE 4 |
| `CLAUDE.global.md` 806-1061 | C5 | 24,845 / 25,281 | 12,006 / 12,110 | KEEP 32, REWRITE 57, DELETE 27, NEW 1 |
| `CLAUDE.global.md` 1062-1077 | C6 part 1 | 3,709 / 3,751 | 2,375 / 2,380 | KEEP 7, REWRITE 10, DELETE 6 |
| `CLAUDE.global.md` total | C1-C6 part 1, assembled | 105,278 / 106,863 | 50,575 / 50,867 (`CLAUDE.global.slim.md`, incl. 2-line header and assembly edits) | KEEP 97, REWRITE 219, DELETE 79, MOVE 13, NEW 1 |
| `~/.claude/rules/agent-operating-lessons.md` | C6 part 2 | 6,276 / 6,334 | 0 / 0 (removed; text relocated verbatim) | DELETE 18, MOVE 3 |
| `~/.claude/rules/00-mission-board.md` | C6 part 3 | 13,884 / 13,998 | about 2,400 / 2,418 (compact render, today's rows) | render-format change, no line table (see section 3) |
| `.claude/CLAUDE.md` (this repo) | C6 part 4 | 6,245 / 6,289 | 3,026 / 3,036 | KEEP 10, REWRITE 11, DELETE 10 |
| `.claude/rules/agent-operating-lessons.md` (this repo) | C7 | 74,078 / 74,780 | 7,511 / 7,567 | KEEP 1, REWRITE 7, DELETE 13, MOVE 1, RESIDENT 19, INDEX 185 |

Measured token counts for every pair are in `README.md` (token table).

## 1. `CLAUDE.global.md` → `CLAUDE.global.slim.md`

### Totals by original section

Row counts are assigned by each row's first line number; a chunk boundary can split a section (Session Close Protocol spans C4 and C5).

| Original section | Lines | Original chars | Rows by label |
|---|---|---|---|
| (file preamble: title, priority legend) | 1-2 | 32 | — |
| Rule Priority Legend | 3-11 | 299 | DELETE 5 |
| Code Style & Stack | 12-55 | 3,693 | KEEP 3, REWRITE 12, DELETE 2, MOVE 1 |
| AI Guidelines | 56-116 | 3,696 | REWRITE 16, DELETE 2, MOVE 4 |
| Browser Automation | 117-122 | 916 | KEEP 1, REWRITE 2, DELETE 1 |
| Personal Message History | 123-128 | 740 | REWRITE 1, DELETE 1 |
| Email — reading a message means reading its IMAGES, by default | 129-159 | 1,793 | KEEP 1, REWRITE 3, DELETE 1 |
| Agent Teams Reinforcement (All Projects) | 160-272 | 8,781 | KEEP 4, REWRITE 21, DELETE 1 |
| Research Subagents Reinforcement (All Projects) | 273-309 | 2,591 | KEEP 2, REWRITE 5, DELETE 2, MOVE 1 |
| Shared Task List (All Projects) | 310-331 | 1,534 | KEEP 4, REWRITE 4 |
| Frontier Tier Routing | 332-335 | 6,743 | KEEP 4, REWRITE 15, DELETE 3, MOVE 1 |
| Concurrent Sessions — Worktree Isolation (All Projects) | 336-355 | 2,492 | KEEP 4, REWRITE 6, DELETE 2 |
| Context Stewardship (All Projects) | 356-400 | 3,283 | KEEP 2, REWRITE 7 |
| Communication Discipline (All Projects) | 401-451 | 6,288 | KEEP 2, REWRITE 11, DELETE 5, MOVE 2 |
| Session Close Protocol (All Projects) | 452-1061 | 58,688 | KEEP 63, REWRITE 106, DELETE 48, MOVE 4 |
| Manual-Command Delivery | 1062-1077 | 3,709 | KEEP 7, REWRITE 10, DELETE 6 |

### C1: lines 1-159

Source: `C1.labels.md`; verify report `C1.verify.md`.

| lines | opening words (<= 8) | label | reason code | enforced-by | destination |
|---|---|---|---|---|---|
| 5 | CRITICAL - Breaking causes production issues | DELETE | default-behavior | — | full file § Rule Priority Legend. The legend only decodes emoji markers, and the slim text uses none. |
| 6 | IMPORTANT - Breaking causes significant rework | DELETE | default-behavior | — | full file § Rule Priority Legend |
| 7 | PREFERRED - Style preference, improves quality | DELETE | default-behavior | — | full file § Rule Priority Legend |
| 8 | INFO - Context/background, not actionable | DELETE | default-behavior | — | full file § Rule Priority Legend |
| 10, 121, 127, 158 | `---` separators | DELETE | default-behavior | — | — (layout only) |
| 14 | Primary stack + language/style/file-naming conventions | MOVE | situational | — | Skill coding-standards. Its SKILL.md was checked and covers every listed item: the stack, lockfile-chosen package manager, TS strict mode, explicit return types, interfaces vs types, named exports, Server Components by default, no render functions, and the naming rules. The slim text keeps a one-line pointer that names the stacks, because this session's skill listing shows `coding-standards` with its description dropped, so the pointer is the only load trigger. "Git rules below stay always-resident" is deleted as meta. |
| 18 | Lowercase start (except proper nouns) | KEEP | env-fact | — | Slim § Git, merged into one commit-message line. Checked: `githooks/commit-msg` only rejects AI trailers and does not enforce style. |
| 19 | No redundant verbs: `feat: authentication` | KEEP | env-fact | — | Slim § Git, commit-message line |
| 20 | Conventional Commits: feat, fix, docs, style... | KEEP | env-fact | — | Slim § Git, commit-message line |
| 24-25 | Commit proactively — one atomic commit per | REWRITE | env-fact | — | Slim § Git "Commits" bullet 1. This is the operator's process, and it overrides the Bash tool's default "commit only when the user asks", so it stays. |
| 25-28 | Landing goes through /ship on the | DELETE | duplicate | — | Duplicate of line 50 (kept in slim § Git "Safety") and of the Session Close Protocol ship-policy table |
| 30-32 | One commit per logical task. Each task/phase/fix | REWRITE | env-fact | — | Slim § Git "Commits" bullets 1-2. The `git diff > /tmp/stash.patch` procedure is kept verbatim. |
| 33-35 | Isolate mixed-change files. When a file contains | REWRITE | env-fact | — | Slim § Git "Commits" bullet 3 |
| 36-38 | Fixup when amending an existing commit. Use | REWRITE | env-fact | — | Slim § Git "Commits" bullet 4 |
| 39-41 | Autosquash without interaction. When fixup commits exist | REWRITE | env-fact | — | Slim § Git "Commits" bullet 4. `GIT_EDITOR=true git rebase --autosquash <base>` kept verbatim. |
| 42-43 | Scope check. Before staging, run git diff | REWRITE | env-fact | — | Slim § Git "Commits" bullet 2, merged with item 1. This overlaps Session Close G4 (task-clean commits); the procedure is kept here and G4 keeps the gate. |
| 47-48 | Never use --no-verify to bypass pre-commit hooks | REWRITE | env-fact | validate-bash.sh:1055 denies `--no-verify` (argv-aware); :1068 denies `git commit -n` | Slim § Git "Safety". One-line definition. |
| 49 | Never force push to main/master | REWRITE | env-fact | Partial: settings.json `permissions.deny` has `Bash(git push --force:*)` and `Bash(git push -f:*)`, and `autoMode.soft_deny` has "Git Destructive". The deny is prefix-only, so `git push origin main --force` is not matched, which is why the line stays. | Slim § Git "Safety", merged with line 51 |
| 50 | Landing goes through /ship, per § Session | REWRITE | mode-rule | Partial: settings.json `permissions.ask` has `Bash(git push:*)`, so a bare push prompts. ship-rail-push-allow.sh auto-allows only `git push origin HEAD:<branch>`. | Slim § Git "Safety" bullet 1, with the agent as actor ("You run `/ship` by default"); pointer names Session Close Protocol § Ship policy (C4 heading `### Ship policy`, confirmed). The "(Revised 2026-07-31 ...)" clause is DELETE/history → full file § Git Safety. |
| 51 | Never run destructive commands (hard reset, force | REWRITE | env-fact | Partial: settings.json `permissions.ask` has `Bash(git reset --hard:*)`; validate-bash.sh:1666 warns | Slim § Git "Safety" bullet 3. Scope kept at destructive commands generally, not only git (fix after verify R18). |
| 52 | Never run interactive git commands (rebase -i | DELETE | tool-dup | — | Duplicates the Bash tool description: "Interactive flags (`-i`, e.g. `git rebase -i`, `git add -i`) are not supported in this environment." |
| 53 | Never run git clean with -x or | REWRITE | env-fact | settings.json `permissions.deny` has `Bash(git clean:*)`, which denies every `git clean`; validate-bash.sh:1672 warns on `-x`/`-X` | Slim § Git "Safety" bullet 4. The reason (gitignored files hold paid generated assets) stays, because it also bears on other deletions. |
| 54 | Never git add -f gitignored directories | REWRITE | env-fact | validate-bash.sh:1044-1048 denies `git add -f`/`--force` | Slim § Git "Safety" bullet 5 |
| 58 | Check for existing patterns before making changes | DELETE | default-behavior | — | — |
| 59 | Look for project-level CLAUDE.md | REWRITE | env-fact | — | Slim § Working rules, rewritten as "a repo outside the cwd's directory tree: read its CLAUDE.md; it is not loaded automatically" (the earlier "only the cwd's CLAUDE.md loads" was inaccurate: parent-dir files load at launch, subtree files on read). The in-tree case is automatic, so that half is default-behavior. The rewritten half duplicates the Session Close ship-policy note "A project CLAUDE.md loads ONLY when the session cwd is that project"; one of the two chunks should drop it. |
| 60 | Run linters before commits (use project's package | REWRITE | env-fact | — | Slim § Working rules |
| 64 | INTEGRATE new content into existing files — NEVER | REWRITE | quirk-fix | backup-before-write.sh (PreToolUse Write). Advisory, not a deny: it injects "OVERWRITE GUARD ... INTEGRATE new content ... Use Edit" | Slim § Updating existing files |
| 66-67 | This rule applies to ALL file types | REWRITE | quirk-fix | — | Slim § Updating existing files (file-type list kept). "Lead agent AND every subagent" is deleted as default-behavior, since this file is loaded in every context. |
| 71 | Update a section / Edit / Always | REWRITE | quirk-fix | backup-before-write.sh | Slim § Updating existing files, as one sentence |
| 72 | Add a new section / Edit / Append | REWRITE | quirk-fix | — | Slim § Updating existing files |
| 73 | Full rewrite / NEVER / Do not use | REWRITE | quirk-fix | backup-before-write.sh | Slim § Updating existing files ("Write only to create a file") |
| 74 | Restructure / Ask user first / Propose | REWRITE | mode-rule | — | Slim § Updating existing files ("propose a restructure and get approval") |
| 76-77 | If you see the PreToolUse warning OVERWRITE | MOVE | tool-dup | backup-before-write.sh | Hook message. backup-before-write.sh:191 prints "OVERWRITE GUARD: ... Use Edit for targeted changes instead of Write ... Restore if overwritten: ~/.claude/scripts/restore-file.sh <file>". The slim text names the hook and says what it prints. |
| 78-80 | code block: ~/.claude/scripts/restore-file.sh /path/... | MOVE | tool-dup | backup-before-write.sh | Hook message (same line 191 prints the exact restore command). Checked: `~/.claude/scripts/restore-file.sh` exists and is a symlink to `scripts/restore-file.sh`. |
| 82-84 | Why this is CRITICAL: Plan files, research | REWRITE | quirk-fix | — | Slim § Updating existing files, cut to the clause "which accumulate decisions across sessions". "This has happened multiple times" is DELETE/history → full file § File Update Rule. |
| 86-87 | Recovery: All Write operations to existing files | MOVE | tool-dup | backup-before-write.sh | Hook message, which prints `Backup saved to <path>`. The slim text keeps one clause naming the hook. |
| 91-93 | When writing memory (a MEMORY.md index | REWRITE | quirk-fix | memory-nudge.sh (UserPromptSubmit, periodic) prints the same skip list; this is a reminder, not enforcement | Slim § Memory |
| 95 | Transient errors — a flake, a one-off | REWRITE | quirk-fix | — | Slim § Memory, skip list |
| 96-97 | Environment-specific one-offs — a path/port/state true | REWRITE | quirk-fix | — | Slim § Memory, skip list |
| 98 | Lucky paths — "X worked once" with no | REWRITE | quirk-fix | — | Slim § Memory, skip list: "worked once with no reason to think it generalizes" |
| 99-102 | Negative tool-claims — "tool Y can't do | REWRITE | quirk-fix | — | Slim § Memory, skip list. The rule and "verify first; a wrapper, flag or version usually explains it" are kept. The `claude --version` live example is DELETE/history → full file § Memory Hygiene. |
| 103-104 | Anything already indexed — grep MEMORY.md first | REWRITE | quirk-fix | — | Slim § Memory |
| 106-108 | Capture instead: reusable rules, durable decisions | REWRITE | quirk-fix | — | Slim § Memory (the capture list, plus a one-clause why: a transient failure recorded as a rule becomes a permanent refusal) |
| 108-111 | (Adapted from hermes-agent agent/background_review.py ...) | DELETE | history | — | Full file § Memory Hygiene. The trailing "/compact-memory, /harvest-skill, memory-nudge.sh embed this list" is tool-dup: checked that commands/harvest-skill.md:24-25 and memory-nudge.sh:536 carry the list. |
| 115 | Plan/design/roadmap docs accumulate decisions across sessions | MOVE | situational | backup-before-write.sh:95 injects PLAN UPDATE RULES (Phase 0, execution locus S/T/L, lead context budget and succession point, never-delete) on any Write/Edit under docs/plans/, .claude-plans/, ~/.claude/plans/ | Skill plan-conventions. Checked that SKILL.md covers INTEGRATE, compact/expand, Phase 0 (lines 35-51) and execution locus (line 83ff). The slim pointer says when to load it and names Phase 0 as the trigger. The S-default wording also duplicates the Agent Teams Reinforcement section. |
| 119 (sentence 1) | Browser automation — navigate / click / fill | REWRITE | env-fact | — | Slim § Browser automation |
| 119 (parenthetical) | (retired 2026-08-11: 0 invocations / 3,504 | DELETE | history | — | Full file § Browser Automation. The browsermcp SKILL.md banner carries the same record. |
| 119 (sentence 2) | Setup/tools/troubleshooting (or on "No such tool | REWRITE | env-fact | — | Slim § Browser automation, as a pointer to the browsermcp skill. The pointer also names react-best-practices and vercel-design-guidelines as knowledge skills it indexes (browsermcp SKILL.md:79-80), since the skill listing shows those names without descriptions. "Read its mcp__browsermcp__* sections as history" is tool-dup (the browsermcp SKILL.md opens with the retirement banner). |
| 119 (sentence 3) | When a task needs the richer MCP | KEEP | env-fact | — | Slim § Browser automation. `chrome-devtools-mcp --browserUrl` and the dia-agent / autonomous-authenticated-web-access skills are kept verbatim. |
| 125 (core) | The operator's entire iPhone message history — | REWRITE | env-fact | — | Slim § Personal message history. Coverage "June 2016 to the present with no gap (`msg stats` shows coverage)" is kept, because top-level `msg --help` is stale and describes a 2024-12 to 2026-08 gap the third (16e) store fills. The `msg` command, its four subcommands, the source path, the read-only / never-merge / never-write-to-`chat.db`-or-`MobileSync/` rule and the runbook path are all kept. |
| 125 (count, flags) | 213,995 messages ... --rank BM25, --raw | DELETE | tool-dup | — | `msg --help` and `msg search --help` print `--rank`, `--raw`, `--like`, `--current` and the store list. The message count is a perishable figure → full file § Personal Message History. |
| 131-136 | Whenever you read an email (any mcp__ms365__* | REWRITE | env-fact | Partial: mail-images-auto.sh (PostToolUse, matcher `mcp__ms365__get-mail-message.*`) auto-extracts and prints the image paths. It deliberately skips list reads. It is registered only in `~/.claude/settings.json`, not in the -secondary/-tertiary/-quaternary/-next account dirs that carry most sessions, so the slim text conditions on the hook's output ("if the hook already printed image paths, Read those; otherwise run cc-mail-images") rather than assuming it fired. | Slim § Email images |
| 138-140 | code block: cc-mail-images --search "<subject fragment>" | KEEP | env-fact | — | Slim § Email images (verbatim) |
| 142-144 | Then Read the image files it writes | REWRITE | env-fact | — | Slim § Email images, with the reason clause "extraction alone puts nothing in context" |
| 146-149 | Why this is a standing rule rather | DELETE | history | — | Full file § Email (operator ruling 2026-09-20) |
| 151-156 | Three objections are already handled — do not | REWRITE | env-fact | — | Slim § Email images, cut to the facts: trackers filtered, inline parts stay local, its own cached token over stdio so it works when the ms365 MCP link is down, and the skip condition. "Do not re-raise them" and the CONNECTION_CLOSED measurement are DELETE/history. |

### C2: lines 160-331

Source: `C2.labels.md`; verify report `C2.verify.md`.

| lines | opening words (<= 8) | label | reason code | enforced-by | destination |
|---|---|---|---|---|---|
| 160 | ## Agent Teams Reinforcement (All Projects) | REWRITE | mode-rule | — | Heading renamed "Agent Teams and parallel work (All Projects)"; "Reinforcement" carries nothing. No hook or test matches the heading text (grepped hooks, scripts, bin, tests). |
| 162-167 | Agent Teams are the DEFAULT for all | REWRITE | mode-rule | agent-teams-enforce.sh (denies a background implementation subagent; denies off-allowlist teammate models) | Rule kept as the "within a session, 2+ files → teammates" and "unnamed subagents never write code" bullets. Spawn-API/runtime detail moves to the agent-teams skill § Runtime assumption (confirmed). `Agent({ name, team_name, model: opus\|fable-5 })` is stale: the skill says `team_name` does not exist on 2.1.220, and the hook measured 0 of 1,251 calls carrying it, so the slim text shows `Agent({ name, … })`. "With worktree isolation" is restated as "each in its own worktree; never pass `isolation:` or `cwd:` beside `name:`", because the skill (:59-62, :362, :432) says either one silently demotes the spawn to a plain subagent (fix pass, verifier R1). The MUST and capitals are removed. |
| 169-175 | PARALLELIZE BY DEFAULT — and this rule | REWRITE | quirk-fix | — | Kept: fan out clean opportunities unasked, in one message; definition of a clean opportunity; the lead keeps only synthesis and owned files. Deleted: directive date, quote, and "waiting is the defect" exhortation (history). The "outranks any runtime instruction" claim is narrowed in row 243-249. |
| 177-186 | Parallelism has TWO units, and the | REWRITE | mode-rule | — | Kept: an implementation wave or phase defaults to a dispatched session, one per phase; the lead keeps ≥50% of its window. The why-it-matters argument is also in the plan-conventions skill § Execution locus ("Whose context pays" column, "Why S is the default"), so the slim text keeps one clause of it. |
| 188-194 | scripts/handoff-fire.sh --prompt-file /tmp/fire-<phase>.txt | KEEP | env-fact | handoff-fire.sh check_goal_arm (format of --goal) | Command lines are verbatim. The comment "ONLY IF NO /goal IS LIVE IN *THIS* PANE — see the 🚨 below" is reworded to "Only if no /goal is live in this pane:". |
| 196-202 | That last line is CONDITIONAL — omit | REWRITE | quirk-fix | validate-bash.sh LIVE-/goal guard (denies a backgrounded park while a /goal is live) | Kept as one bullet: when to omit the line, the one-sentence mechanism, and that the hook denies it. Deleted: the registry-restore detail and the "2 h / ~12 turns / 0 evaluations" measurement (history; kept in docs/research/goal-in-handoff-2026-08-08.md). |
| 202-208 | You are not deaf without the watcher | REWRITE | mode-rule | validate-bash.sh (refusal lists the same levers, but only when a park is attempted) | One sentence in the omit-line bullet: the goal keeps you taking turns, `mailbox-drain` delivers peer mail at each turn boundary, `mailbox-wake-arm` wakes an idle session. Kept resident because an agent that follows the slim never triggers the refusal (fix pass, verifier R9). "migration 0007" and the binary-reading provenance are dropped. |
| 210-217 | `--goal` is part of that recipe, not | REWRITE | mode-rule | handoff-fire.sh check_goal_arm (format only: single line, no leading slash, ≤4000 chars) | Kept: the three parts of a condition; the evaluator is tool-less and sees only surfaced prose or tool_result, so the check must be surfaced, usually as a command the session runs and prints (fix pass, verifier R11); an activity-shaped condition never clears; pointer to commands/handoff.md § Autonomous fire item 1 (template and four exceptions confirmed at :270). Deleted: the directive date and the Anthropic docs URL (history). |
| 219-225 | The measured goal lifecycle — and why | REWRITE | env-fact | — | Kept: `--recycle` inherits the live goal (`inherit_recycle_goal`, `CC_RECYCLE_GOAL_INHERIT=0` opts out) and `--resume` restores it. Deleted: the "this replaces … half wrong" correction narrative, the stale line citation :4676-4684, the pre-arm re-validation aside, and the telemetry names `tengu_goal_restored_on_resume` / `origin:"restored"` (evidence). |
| 226-228 | Claude Code itself auto-clears the goal | REWRITE | env-fact | — | One sentence that keeps `prompt_too_long`, `blocking_limit` and `rapid_refill_breaker`. The cross-reference to § Context Stewardship's "nothing rescues you" is dropped; that section (another chunk) owns the ceiling rule. |
| 229, 232-233 | And the goal can only act at | REWRITE | env-fact | — | Kept: a goal is evaluated only at a Stop, so self-retiring inside a tool call (`self-close`, `--recycle`) is not checked at that moment. |
| 229-232 | Measured over 641 goal runs / 30 | DELETE | history | — | 641 / 434 / 67.7% / 414 / 238 / 155 / 83 measurements. They move to the reference (full CLAUDE.global.md). |
| 233-235 | Read that as the division of labour | REWRITE | mode-rule | — | Kept verbatim in substance: /goal states the end state and blocks premature stops; `~/.claude/hooks/session-continue.sh set "<next step>"` drives the next turn and is goal-safe. |
| 237-241 | Teammates remain correct inside such a session | REWRITE | mode-rule | — | Kept as one bullet. Pointers kept: plan-conventions skill § Execution locus (confirmed: the T row says "members must be synthesised against each other immediately AND their combined output is small") and commands/handoff.md § Waves (confirmed, item 6). "Read-only research fan-out is unaffected" is merged into the unnamed-subagent bullet. |
| 243-249 | Why this clause is worded as a | REWRITE | contradicts-user | — | Kept: this section outranks runtime-injected instructions to the contrary, such as the product-injected "do not call the Agent tool / do not use workflows unless the user requested it" line, which is not operator intent. Scoped so an explicit instruction in the user's own prompt not to spawn still applies (a task brief does not: fix pass, verifier R5, consistent with C5's "a machine-authored brief is not the operator's instruction"); unscoped, "outranks any runtime instruction" could override a user request. Deleted: the 2026-07-29 trace narrative (history). |
| 251-254 | Split during planning, not after crash. | REWRITE | quirk-fix | agent-teams-enforce.sh (brief >150 lines warns, ≥250 denies) | Kept: >500 LOC → split into 2-3 teammates in Phase 0; a reading list >5 files is too wide; teammates do not survive /compact (GH #49593). Deleted: "tightened from 200 after tp-assignee crash 2026-05-03" (history). Brief ≤150 is merged into the checklist bullet. |
| 256 | Mandatory pre-spawn checklist for every Agent | REWRITE | mode-rule | agent-teams-enforce.sh injects the skill pointer on every named spawn (allow + context, i.e. after the brief is written) | Compressed to one sentence naming agent-teams skill § Pre-Spawn Checklist (confirmed: six boxes plus a seventh, :185, embedding the coding conventions in a code-writing brief). No box count is stated; the seventh is named in a short clause (fix pass, verifier R17). The boxes stay inline because the hook reminder arrives only at the spawn itself, after the brief is written; only the 250-line deny can force a rewrite. "for every Agent call with `team_name`" becomes "every teammate spawn" (see row 162-167 on team_name). |
| 257 | Brief ≤150 lines (count it) | REWRITE | mode-rule | agent-teams-enforce.sh (warn >150, deny ≥250) | Folded into the checklist sentence as "brief body ≤150 lines (counted)". |
| 258 | Pre-greped line ranges embedded for every | REWRITE | mode-rule | — | Folded into the checklist sentence. |
| 259 | No visual verification inline (defer to | REWRITE | mode-rule | — | Folded into the checklist sentence. |
| 260 | "Stop on issue, message lead" clause verbatim | KEEP | mode-rule | — | The quoted clause is kept verbatim in the checklist sentence. |
| 261 | Multi-phase = explicit checkpoint or split | REWRITE | mode-rule | — | Folded into the checklist sentence. |
| 262 | No "investigate" / "explore" / "audit" language | KEEP | mode-rule | — | Folded into the checklist sentence, words kept verbatim. |
| 264 | Teammate ops (agent actions — not hook-enforced) | REWRITE | mode-rule | — (at close, scripts/wrap-ledger.sh RESIDENT_MINE flags still-running members; see § Session Close Protocol) | Kept: max 6 concurrent; end each teammate with a structured `shutdown_request`; plain text does not close panes. Partly duplicates § Session Close Protocol's resident-member rule (another chunk) and the agent-teams skill (:342, :457-458). |
| 266-269 | Full decision table, runtime detection, the | REWRITE | tool-dup | agent-teams-enforce.sh points to the skill on every named spawn | Reduced to a one-line pointer that says when to load the agent-teams skill (before spawning a teammate; fix pass, verifier R19). The content list repeats the skill's own description, and the "previously resident here" note is history. |
| 271 | --- | KEEP | — | — | Section separator. |
| 273 | ## Research Subagents Reinforcement (All Projects) | REWRITE | mode-rule | — | Heading renamed "Research subagents (All Projects)". |
| 275-277 | Research subagents (no `team_name`, fire-and-forget) are | REWRITE | mode-rule | advisory: research-precognition-nudge.sh and agent-teams-enforce.sh both print "Default N=10 (band 8-12)" | Kept: unnamed, fire-and-forget; no parallelism cap; decomposition sets the count; N=10 (band 8–12). "Teammates write code, subagents never do" duplicates row 162-167 and is merged there. |
| 277-280 | the 12 this line carried until 2026-09-09 | DELETE | history | — | The 12→10 history is dropped. The derivation (40% at N=10 vs 64% at N=20) is in the research-subagents skill (:84-86, confirmed), and the sensitivity-table pointer is folded into the skill pointer. |
| 280-282 | Use the custom `deep-research` subagent (`~/.claude/agents/deep-research.md`) | KEEP | env-fact | — | Compact form. |
| 282-290 | nested fan-out is off — and WE | REWRITE | env-fact | harness subagent_depth_cap (via the env var) + agent-teams-enforce.sh SPAWN DEPTH CAP (`CC_SPAWN_MAX_DEPTH`) | Kept: `~/.zshrc:484` exports `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1` deliberately; subagents cannot nest; keep it, because depth is the only runaway bound since 2.1.224. Deleted: the binary spawn-gate quote and the "this corrects the prior…" narrative (history; kept in agents/deep-research.md Regression notes :118-121). |
| 291 | Use `Explore` for fast terminal codebase lookups. | DELETE | tool-dup | — | The Explore agent type's description already says this. Routing lives in the research-subagents skill § "`Explore` vs `deep-research` vs `general-purpose`" (:587, confirmed). |
| 293-299 | Venue rule for the fan-out itself | REWRITE | mode-rule | — | Kept: a read-only fan-out of about 8+ same-shaped, self-verifying units runs as a Dynamic Workflow, with the reason in one parenthesis; implementation waves stay dispatched sessions. Deleted: provenance, ratification date, and the A06 cost aside (history). It stays resident because the research-subagents skill does not carry it (grepped). |
| 301-302 | Per-subagent depth target: 150-250K tokens, hard | MOVE | situational | — | research-subagents skill (:516 "Target 150-250K on exploration; hard cap 500K", :561-568, confirmed). The numbers stay inside the pointer line. "The prior 500-800K range…" is history and is deleted. |
| 302-306 | See the research-subagents skill for the | REWRITE | tool-dup | advisory: research-precognition-nudge.sh (UserPromptSubmit) and agent-teams-enforce.sh inject the skill pointer on research-shaped prompts and briefs | Now a one-line pointer saying when to load the skill (before a research wave). "adversarial sampling (15-20%)" keeps its threshold (fix pass, verifier R26). The content list is shortened because it repeats the skill description. |
| 308 | --- | KEEP | — | — | Section separator. |
| 310 | ## Shared Task List (All Projects) | KEEP | mode-rule | — | Heading kept, sentence-cased. |
| 312-314 | Two or more open work items in | REWRITE | mode-rule | — | Kept as a constraint with its one-clause reason. The ⚠️ and bold are removed. |
| 314-318 | The tools are `TaskCreate` / `TaskUpdate` / | REWRITE | env-fact | — | Kept: the tool names, the store path `$CLAUDE_CONFIG_DIR/tasks/<CLAUDE_CODE_TASK_LIST_ID>/` shared across the four accounts via symlinks, and `bin/cc-tlid`. |
| 318-321 | The supporting wiring is already registered and | REWRITE | env-fact | task-quality-gate.sh (TaskCompleted: runs typecheck in the teammate's worktree and rejects on failure) | Kept: the quality gate, as a one-line definition. Deleted: the names of setup-task-symlinks.sh and task-mutation-index.sh; the agent never acts on them. |
| 323-326 | The tools are gated behind `CLAUDE_CODE_ENABLE_TODO_TOOLS=1` | REWRITE | env-fact | — | Kept: the env var gate, and that the migration is the operator's to run. Corrected: the migration is `migrations/0023-todo-tools-and-task-hooks.sh`, not "0022" (0022 is mitl-decider-shadow). Deleted: the A/B measurement, GrowthBook note and "wave W1f" (history). Also dropped "unset in all five config dirs today", which goes stale; the slim text says "when the tools are absent". |
| 326-328 | Until it lands, the plan document's own | KEEP | mode-rule | — | Reworded to trigger on tool absence, a fact the session can observe, not on migration state. The "never licence to hold the set in your head" clause duplicates row 312-314. |
| 328 | Do not touch `CLAUDE_CODE_ENABLE_TASKS`: that one is | KEEP | env-fact | — | Verbatim in substance. |
| 330 | --- | KEEP | — | — | Section separator. |

### C3: lines 332-451

Source: `C3.labels.md`; verify report `C3.verify.md`.

| lines | opening words (<= 8) | label | reason code | enforced-by | destination |
|---|---|---|---|---|---|
| 332 | ## Frontier Tier Routing | KEEP | env-fact | — | slim heading |
| 334a | Default model = Opus 5.5 @ effort | KEEP | env-fact | — | slim ¶1 (SSOT key + launcher flags verbatim) |
| 334b | The rung is per use case | REWRITE | mode-rule | — | slim ¶1; bold removed; evidence path `docs/research/opus55-utilization-2026-09-22/` → reference § Frontier Tier Routing |
| 334c | Pin the ALIAS opus by hand | REWRITE | quirk-fix | — | slim ¶1 (caps removed) |
| 334d | (Was Opus 5 until 2026-09-22 | DELETE | history | — | reference § Frontier Tier Routing |
| 334e | The frontier tier (currently Fable 5.1) is | REWRITE | mode-rule | — | slim ¶2. Partly duplicated by the frontier-routing skill description in the skill listing; kept as a single clause because the ladder below depends on it |
| 334f | F2 leaves a below-90%-conviction decision two | REWRITE | mode-rule | — | slim ¶2 ("before asking the operator ... escalate the model") |
| 334g | Fire the ladder when all three | REWRITE | mode-rule | — | slim ¶2 bullets T-a/T-b/T-c; `claude-accounts` kept |
| 334h | The ladder is three same-pane recycles | REWRITE | env-fact | — | slim ¶3 (fixed: stage 1 is the document, then two same-pane recycles); command `handoff-fire.sh --recycle --model claude-fable-5-1 --effort xhigh --prompt-file <stage-1 doc>` and `--model opus` verbatim; the "(the SSOT's Opus on a fresh fire ...)" aside deleted as tool internals |
| 334i | Fable writes DOCUMENTS, never edits | REWRITE | quirk-fix | partial: `backup-before-write.sh` OVERWRITE GUARD (backs up and warns on overwrite, does not deny) | slim ¶3 |
| 334j | The lead MAY run on it | REWRITE | mode-rule | — | slim ¶3 ("lead runs on Fable only at stage 2"); premise story ("prompt-cache cost ... contradicted 52 times") → reference § Frontier Tier Routing |
| 334k | R3 — whether the ladder fires | REWRITE | mode-rule | — | slim ¶3 ("a session chooses the ladder; not automatic", with the § W3.6 pointer). The 72% conviction, the nine refutations and the missing control arm → reference |
| 334l | That delta has narrowed sharply | DELETE | history | — | reference § Frontier Tier Routing (price-parity narrative, $/MTok figures) |
| 334m | Dollars are the wrong currency anyway | REWRITE | env-fact | — | slim ¶4 (quota, not dollars; 50% sub-cap; `frontier.coupling: 0.5`; 2-5x draw). Fixed: `accounts.json` `spend.usage_credits_authorized=false` / `frontier.credits_authorized=false` kept as the checkable premise; 2-5x cites `docs/research/opus55-effort-sweep-2026-09-22/` with "re-measure before quoting" |
| 334n | THAT is why the lead never | REWRITE | mode-rule | — | slim ¶4 ("an escalation names the specific blind spot it targets"); "lead never runs on it" is a duplicate of 334j |
| 334o | At MATCHED effort rung Fable 5.1 | REWRITE | mode-rule | — | slim ¶4 (fixed: "escalate for a different model's blind spots, not for a stronger model"); benchmark comparisons, research paths and the "Supersedes ... §D6" note → reference |
| 334p | Because the human never model-switches | REWRITE | mode-rule | `hooks/frontier-spawn-gate.sh` (Agent matcher live; refuses at `max_fable_spawns_per_session`) | slim ¶5; hook path and budget key verbatim |
| 334q | The session arm is LANDED | REWRITE | env-fact | `frontier-spawn-gate.sh` session arm is inert until `migrations/0029` is run (verified: not on the Bash matcher) | slim ¶5; `jq` check kept verbatim. Fixed: the c10 clause is kept ("edits settings.json (class c10) and is the operator's to run") so the precondition does not read as drivable |
| 334r | Why this is stated rather than | DELETE | history | — | reference § Frontier Tier Routing (52 lead sessions / 4,117 transcripts) |
| 334s | A blocked spawn = PARK, never | KEEP | mode-rule | `hooks/frontier-spawn-gate.sh` (its refusal says "Do NOT retry ... park") | slim ¶5, one clause |
| 334t | Kill-switch: CC_LADDER=off | REWRITE | mode-rule | none found (no reader in hooks/scripts/bin) | slim ¶3 ("If `CC_LADDER=off` is set, do not fire it") |
| 334u | Surfaces: capture holes with /frontier-hole | MOVE | tool-dup | `frontier-spawn-gate.sh` caps `/frontier-run` panel spawns | frontier-routing skill: SKILL.md duties 2, 3 and 5 cover `/frontier-hole`, inline ≤2 panelists, batch at wrap-up with ≥2 OPEN holes, `/frontier-campaign`; its description in the skill listing repeats them. Pointer in slim ¶6 keeps the three command names and (fixed) states when to load the skill: choosing a tier for a spawn, a wall that might warrant escalation, wrap-up with open holes |
| 334v | The full discipline — the 5 | KEEP | env-fact | — | slim ¶6 (skill pointer + ledger path). SSOT path already stated in ¶1 (duplicate) |
| 336 | ## Concurrent Sessions — Worktree Isolation | KEEP | env-fact | — | slim heading |
| 338-340 | Multiple Claude Code sessions on ONE | REWRITE | env-fact | — | slim, one sentence; "Observed repeatedly" deleted (history) |
| 342 | Rule — CONDITIONAL, not "always" | DELETE | history | — | reference § Concurrent Sessions (rationale for not always using worktrees); the rule itself is the three bullets |
| 344 | Single session → work in the | KEEP | mode-rule | — | slim bullet |
| 345 | Read-only sessions (research, audit, status | REWRITE | mode-rule | — | slim bullet |
| 346 | 2+ concurrent WRITER sessions → each | KEEP | env-fact | — | slim bullet; `claude -w <name>` / `--worktree` / `--tmux` verbatim |
| 348 | Fresh-worktree setup (gitignored files are | REWRITE | env-fact | — | slim ¶ (pnpm-layout rationale and "collides silently" dropped; `pnpm install --frozen-lockfile`, `.worktreeinclude` (fixed: "on newer Claude Code versions"), `scripts/new-worktree.sh` verbatim) |
| 350 | Merge back: rebase-onto-default + --ff-only | REWRITE | env-fact | — | slim ¶ |
| 352a | Caveats: prefer manual claude -w | REWRITE | quirk-fix | — | slim ¶; GH issue numbers (#34645, #48927) → reference § Concurrent Sessions |
| 352b | Never run git restore . / | REWRITE | mode-rule | — | slim ¶ |
| 352c | jj workspaces are architecturally better but | DELETE | history | — | reference § Concurrent Sessions (not operative; "revisit later") |
| 354 | --- | KEEP | env-fact | — | section separator, as in the source |
| 356 | ## Context Stewardship (All Projects) | KEEP | env-fact | — | slim heading |
| 358-360 | Context is a budget with three | REWRITE | mode-rule | `waiting-recycle.sh` / `boundary-handoff.sh` (advisory) | slim lead-in; `cc-context` kept |
| 362-364 | Idle (just waiting/watching) at ≥~35% | REWRITE | mode-rule | `boundary-handoff.sh` "⟳ FREE WIN" advisory; `waiting-recycle.sh` (desk) | slim bullet; thresholds 35% / 25% kept |
| 365-368 | Valuable in-flight state (a live | REWRITE | mode-rule | `waiting-recycle.sh` "⟳ CONTEXT PAUSE-POINT PLANNING"; `boundary-handoff.sh` "⚑ ... do NOT cut it" | slim bullet; ~50% and dod-persist kept |
| 369-371 | Heavy build / high 2-way volume | REWRITE | mode-rule | `waiting-recycle.sh` forced drain / burn forecast (advisory) | slim bullet; ~75% / ~85% kept. "Rot degrades decisions ..." dropped as rationale |
| 373-381 | The ceiling is a hard REFUSAL | REWRITE | quirk-fix | — | slim ¶ (no auto-compaction; `Prompt is too long` leaves the session dead in place). 39/39 manual compactions, 7 sessions / 10 events, `docs/plans/CONTEXT_ECONOMY_V2.md` → reference § Context Stewardship |
| 383-390 | Every % here is a fraction | REWRITE | env-fact | — | slim ¶ (trust statusline %, absence = unknown, window cannot be imputed from the model id, re-derive with `cc-ctx-audit`). `/tmp/cc-telemetry` coverage figures and the opus-4-8 window story → reference |
| 392-397 | Deterministic rails back this judgment (claude-infrastructure): | REWRITE | mode-rule | `hooks/waiting-recycle.sh`, `hooks/boundary-handoff.sh` | slim ¶ ("act on the first `⟳`/`⚑`"). Mechanism list (S6 hold, burn forecast) is in the hooks' own messages; design-doc pointers → reference |
| 399 | --- | KEEP | env-fact | — | section separator |
| 401 | ## Communication Discipline (All Projects) | KEEP | env-fact | — | slim heading |
| 403-406 | Opus 5 runs long by default | DELETE | history | — | reference § Communication Discipline (Opus 5 rationale; notes the levers were never re-measured on Opus 5.5) |
| 408-416 | THESE RULES ARE TUNED TO OPUS | REWRITE | mode-rule | — | slim closing ¶ (on a frontier-model session: read for intent, tables and lists allowed, do not compress past readability). Vendor quotes and delta-list provenance → reference |
| 417-421 | Two further 5.1 deltas bind on | REWRITE | quirk-fix | — | slim closing ¶ (fixed: at xhigh, "quiet alone is not evidence of a stall; check the pane before concluding either way"); `fable51_capability_sensitive` re-sweep history → reference |
| 421-423 | whole-file rewrites for small edits, which | DELETE | duplicate | `backup-before-write.sh` OVERWRITE GUARD | duplicate of 334i ("Fable writes documents and never edits") and § File Update Rule |
| 425-426 | Chat. Focused and brief. Spend the | REWRITE | mode-rule | — | slim bullet. "Lead with the answer" part duplicates `<tone_preference>` at the end of the file |
| 427-433 | Brevity governs YOUR prose, never a | REWRITE | quirk-fix | — | slim bullet; the three renderer names kept. "Defect the renderer was built to prevent ... a dropped column" rationale → reference. Overlaps § Session Close Protocol "Relay, never paraphrase" (outside C3) |
| 434-436 | Mid-task narration. One sentence before the | REWRITE | mode-rule | — | slim bullet. Candidate for the A/B: spec §7 suggests removing mid-turn messaging instructions, and "outcome first" duplicates `<tone_preference>` |
| 437-439 | Files you write (plans, docs, reports | REWRITE | quirk-fix | — | slim bullet |
| 440-444a | Never add verification you were not | REWRITE | quirk-fix | — | slim bullet ("verify when the task's risk calls for it, not as ceremony"; teammate-review exception kept). "burns tokens for no quality gain" dropped: a token-conservation reason (spec Trap 1) |
| 444b-449 | This bans CEREMONY, never RESEARCH. A | REWRITE | mode-rule | — | slim bullet, one sentence ("below 90% conviction it is required"). Narrative on why the misreading matters → reference |
| 450a | Messages you DRAFT for him to | MOVE | situational | — | outbound-drafting skill: SKILL.md §1 one message one job, §2 read the thread first and cut answered questions, §3 anchor don't open, §5/§7 no invented justification; it auto-loads before any draft. Pointer kept in slim bullet |
| 450b | NO COMPOSE-AND-SEND, AND THIS IS | REWRITE | mode-rule | `hooks/enforce-email-formatting.py` denies all four tools (RECIPE rule 0) | slim bullet, one clause; four tool names verbatim |
| 450c | send-draft-message is now ALLOWED, but | REWRITE | mode-rule | `hooks/enforce-email-formatting.py` (RECIPE rule 0b; refuses the send in the composing turn) | slim bullet ("say the draft is in Drafts and ready, and stop") |
| 450d | The turn boundary is a GENUINE | MOVE | situational | `hooks/enforce-email-formatting.py` (implements the turn-boundary logic; comment l.21-33) | hook refusal + RECIPE rule 0b; mechanism detail, not an agent rule |
| 450e | Fails CLOSED on unreadable evidence, so | DELETE | history | same hook | reference § Communication Discipline (design rationale) |
| 450f | A Graph send is irreversible (Outlook's | DELETE | history | same hook | RECIPE rule 0 already says "immediate and irreversible"; rationale → reference |
| 450g | Second email trap, NOT fully mechanical | REWRITE | env-fact | partial: `enforce-email-formatting.py` denies an alias the mailbox does not own and injects RECIPE rule 5 (derive the alias from the thread) | slim bullet (alias must match thread; both addresses verbatim; fixed: hook rejects an alias the mailbox does not own but cannot check thread match; recipe arrives at first mail call and with every refusal) |
| 450h | Rationale + evidence → claude-infrastructure/docs/research/email-guardrails-2026-08-25.md | DELETE | history | — | reference § Communication Discipline |
| 451 | (blank) | KEEP | — | — | — |

### C4: lines 452-805

Source: `C4.labels.md`; verify report `C4.verify.md`.

| lines | opening words (<= 8) | label | reason code | enforced-by | destination |
|---|---|---|---|---|---|
| 452 | ## Session Close Protocol (All Projects) | KEEP | mode-rule | — | slim heading (Git Safety cites "§ Session Close Protocol's ship policy") |
| 454-456 | Drive in-scope work to a finished | REWRITE | mode-rule | completion-assert.sh (false-done arm) | slim ¶1, emphasis removed; "landed per the ship policy" (fix: bare "landed" contradicted the money-repo offer row) |
| 456-458 | Mechanism = this rule + a /wrap | REWRITE | env-fact | — | slim ¶1: "Stop hooks check facts only, never scope" |
| 459-468 | (Corrected 2026-08-08, measured on 2.1.220 | MOVE | situational | — | REF (Stop-hook field semantics, `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`); one-line pointer "before writing or debugging a Stop hook" |
| 468-471 | What DOES run at Stop is | REWRITE | env-fact | completion-assert.sh, operator-readout.sh | slim ¶1 |
| 473-475 | Three of those Stop arms make | DELETE | history | — | REF (operator crux 2026-08-01); replaced by subheading "Stop-hook arms" |
| 477-482 | The close certificate. On a WRITE | REWRITE | env-fact | operator-readout.sh (Stop, systemMessage) | slim bullet 1 (string `✅ SAFE TO CLOSE — nothing of mine is open` verbatim) |
| 483-489 | Mechanical 🔧. session-continue.sh no longer waits | REWRITE | env-fact | session-continue.sh mechanical_arm (block reason names `session-continue.sh clear`) | slim bullet 2; "no longer"/"now a mechanism failure" history dropped; the `CC_MECH_MAX × CLAUDE_CONTINUE_MAX` bound dropped as duplicate of CLAUDE.global.md:1025-1026 (Auto-continue actuation; C5.slim:85 keeps both identifiers) |
| 490-494 | The floors + the origin close | DELETE | history | — | REF (CLOSE_INTEGRITY recon measurements) |
| 495-498 | (1) The SHIP FLOOR (session-continue.sh) | REWRITE | env-fact | session-continue.sh ship floor (`CC_SHIP_FLOOR_MAX`, `session_unlanded_mine`; reason text prints the policy) | slim bullet 3; exemption list (sibling commits, assignee, terminating, kill-switch) dropped as tool-dup: it describes the hook's own gating and changes no agent action |
| 499-504 | (2) CUSTODY (bin/cc-custody): a fire | REWRITE | mode-rule | wrap-ledger.sh CUSTODY_OPEN → 🔧 readout (prints return/abandon verbs); completion-assert.sh | slim bullet 4 |
| 505-511 | (3) THE ORIGIN CLOSE CONTRACT (completion-assert D6 | REWRITE | mode-rule | completion-assert.sh D6 via hooks/lib/close-shape.sh (reason prints template); D3 for hedging | slim bullet 5; `line-1-rung` and both `Good to close:` forms verbatim |
| 511-512 | Put the verdict on the SECOND | KEEP | mode-rule | completion-assert.sh D6 reason text | slim bullet 5 ("on line 2") |
| 512-515 | Complication: / Solution: / Outcome: are NO | DELETE | duplicate | — | same rule at CLAUDE.global.md:856 (C5, slot S2); also history (W3 2026-08-23) |
| 516-517 | Latched + capped with the other | REWRITE | mode-rule | completion-assert.sh | slim bullet 5 (exemptions kept) |
| 517-519 | The frozen DoD now survives the | DELETE | history | hooks/lib/dod-path.sh | REF (mechanism description; no agent action) |
| 521-525 | A RESIDENT MEMBER IS YOUR LOOSE | DELETE | history | — | REF (RC-2 fleet measurements); rule kept in next rows |
| 525-531 | So scripts/wrap-ledger.sh now computes RESIDENT_MINE | REWRITE | env-fact | wrap-ledger.sh RESIDENT_MINE → 🔧 readout (prints the shutdown procedure) | slim "Resident teammates" ¶; pgrep/three-flag implementation detail dropped; "their dirty files in a shared cwd are yours to commit, only the lead can" restored (fix) |
| 531-532 | Send each resident a shutdown_request | KEEP | mode-rule | wrap-ledger.sh readout | slim "Resident teammates" ¶ |
| 532-535 | It is a CHECK and nothing | REWRITE | mode-rule | — | slim "Resident teammates" ¶ (`WRAP_RESIDENT=off` verbatim) |
| 537-540 | Freeze the DoD at intake. | REWRITE | mode-rule | dod-persist.sh captures `Scope (frozen):` (persistence, not a block) | slim ¶ "Freeze the DoD" |
| 542 | Disposition by end-state (a turn | KEEP | mode-rule | — | slim subheading + "judge per task" |
| 544-545 | table header End-state / Action | KEEP | mode-rule | — | slim table |
| 546 | Read-only / advisory / research | REWRITE | mode-rule | — | slim table row |
| 547 | In-scope: unwritten / unverified / uncommitted | REWRITE | mode-rule | session-continue.sh (mechanical 🔧) | slim table row; "≥2 code tasks → Agent Teams" dropped as duplicate of § Agent Teams Reinforcement (restated once in the 🔧 bullet) |
| 548 | In-scope: gate ran red | REWRITE | mode-rule | — | slim table row; "never bypass the hook" dropped, duplicate of § Git Safety (--no-verify) |
| 549 | Committed, not pushed/landed | REWRITE | duplicate | — | slim row points at Ship policy (policy stated once there) |
| 550 | Needs a decision (destructive migration | KEEP | mode-rule | — | slim table row |
| 551 | Out-of-scope discovery | REWRITE | mode-rule | — | slim row; "any FAIL → name + backlog" contradicted the Follow-On Gate's newer "drop it unless FILED test" (line 609-611) — slim uses the newer rule |
| 552 | Genuinely complete | KEEP | mode-rule | completion-assert.sh D3 (hedge) | slim table row |
| 553 | Context / budget exhausted, work remains | REWRITE | mode-rule | — | slim row; points at context dispositions (Recycle first) |
| 555 | Auto-continue is permitted IFF all | REWRITE | mode-rule | — | slim G-list intro |
| 556 | G1 inside the frozen-or-grown DoD | KEEP | mode-rule | — | slim G1 |
| 557 | G2 touches no escalation surface | KEEP | mode-rule | — | slim G2 (G2 is cited by F3 and other sections) |
| 558 | G3 the action is local | REWRITE | mode-rule | — | slim G3; "never force-push" dropped as duplicate of § Git Safety |
| 559 | G4 the commit is task-clean | KEEP | mode-rule | — | slim G4 |
| 560 | Honor explicit pauses ("stop here" | KEEP | mode-rule | — | slim |
| 562-564 | Ship policy — land by default | DELETE | history | — | REF (operator directive 2026-07-31, supersession note) |
| 564-566 | A verified commit sitting on a | REWRITE | mode-rule | session-continue.sh ship floor | slim Ship policy one-line premise |
| 568-569 | table header Repo / On 📦 | KEEP | mode-rule | — | slim table (Why column dropped) |
| 570 | every repo, by default | KEEP | mode-rule | session-continue.sh ship floor | slim table row |
| 571 | a repo whose OWN CLAUDE.md says | KEEP | mode-rule | — | slim table row |
| 573-578 | This table names NO repo, deliberately | REWRITE | mode-rule | — | slim ¶ (read target repo's CLAUDE.md + status tool; project CLAUDE.md loads only by cwd) |
| 580-590 | (Rewritten 2026-08-05. The prior version | DELETE | history | — | REF (reso LAND_SHIP_V2 incident) |
| 592-594 | Both paths still require G1/G2/G4 | KEEP | mode-rule | /ship (ship-land.sh refuses red/dirty) | slim ¶ |
| 596-598 | Follow-On Gate — "net-positive → just do | REWRITE | mode-rule | — | slim "Follow-On Gate" intro; directive date dropped |
| 598-600 | F1 net-positive under the operator's | KEEP | mode-rule | — | slim F1 |
| 600-601 | F2 well-researched — grounded in THIS | KEEP | mode-rule | — | slim F2 (F2 is cited by Frontier Tier Routing and Communication Discipline) |
| 601 | And a decision carries a NUMBER | REWRITE | mode-rule | — | slim F2 (90% rule; operator quote reduced to the rule; fix: "at or below 90%" + "above 90% there is nothing to ask: implement", matching the tools' N > 90 refusal) |
| 601 | This is mechanical, not prose: cc-backlog | REWRITE | mode-rule | bin/cc-backlog + bin/cc-decide refuse; wrap-ledger.sh UNCONVICTED_MINE → 🔧 | slim F2; argument forms verbatim |
| 601 | Why a number: on 2026-09-08 a | DELETE | history | — | REF (conviction-close incident + 30-day counts) |
| 602-604 | F3 same safety envelope — G2 | KEEP | mode-rule | — | slim F3 |
| 604-605 | F4 bounded — each item gets | KEEP | mode-rule | — | slim F4 |
| 605-606 | runaway bound = the kill-switch (CLAUDE_CONTINUE_MAX | DELETE | duplicate | — | same fact at CLAUDE.global.md:1019-1031 (Auto-continue actuation, C5/C6) |
| 606-608 | Bounded means SCOPED, never DEFERRED | REWRITE | mode-rule | — | slim F4 |
| 608-612 | On PASS: append Scope (grown) | REWRITE | mode-rule | dod-persist.sh captures `Scope (grown):` | slim ¶ after F-list; `Scope (grown): +<item>` verbatim |
| 612-613 | Asking the user to re-affirm | REWRITE | quirk-fix | anti-deference-nudge.sh (Stop, lexical tells); completion-assert.sh D4 | slim ¶ |
| 613-615 | The kill-switch ("just do X" | KEEP | mode-rule | — | slim ¶ (kill-switch defined at CLAUDE.global.md:1042) |
| 617-620 | "Done this turn" — assert with | REWRITE | mode-rule | completion-assert.sh (ledger contradiction) | slim "Asserting done" ¶1 |
| 620-622 | Otherwise hedge with the clearing verb | KEEP | mode-rule | — | slim "Asserting done" ¶1, examples verbatim |
| 624-626 | The readout — emit at every | REWRITE | mode-rule | completion-assert.sh D6 line-1-rung | slim "The readout" intro; priority order verbatim; fix: "built from … READOUT as slot S1 describes" (was "relayed", contradicting C5 S1) |
| 628-629 | table header State / disposition row | REWRITE | tool-dup | — | slim converts to glyph list |
| 630 | ⛔ Blocked | KEEP | mode-rule | wrap-ledger.sh (computes ⛔ from filed class-C packets) | slim list; readout string verbatim (model-composed) |
| 631 | 📤 Handoff | KEEP | mode-rule | — | slim list; readout string verbatim (model-composed, ledger cannot derive) |
| 632 | 🔧 Loose ends | REWRITE | tool-dup | wrap-ledger.sh renders READOUT | slim list (condition kept, literal text rendered by ledger) |
| 633 | 📦 Parked | REWRITE | tool-dup | wrap-ledger.sh renders READOUT | slim list |
| 634 | 🚀 Landed, not live | REWRITE | tool-dup | wrap-ledger.sh renders READOUT | slim list |
| 635 | 👤 Yours | REWRITE | tool-dup | wrap-ledger.sh renders READOUT | slim list |
| 636 | ✅ Live | REWRITE | tool-dup | wrap-ledger.sh renders READOUT | slim list |
| 637 | E0 read-only (no tracked writes) — rule | KEEP | quirk-fix | none (row states no arm catches it) | slim list E0; rule kept in full |
| 637 | Nothing on this box catches it | DELETE | history | — | REF (evidence: which arms miss E0, 96% no-tell) |
| 639 | 📦 vs ✅ (committed ≠ landed) is | DELETE | duplicate | — | rung definitions in slim list carry the split |
| 640-645 | 🚀 vs ✅ is the third | DELETE | history | — | REF (inertness-generator measurements) |
| 645-650 | 🚀 is budgeted, not absolute … converger refuses | REWRITE | mode-rule | wrap-ledger.sh | slim 🚀 list item + 🚀 action bullet |
| 650-652 | Computed by scripts/wrap-ledger.sh (LIVE, LIVE_SRC | DELETE | tool-dup | — | commands/wrap.md § "Read the rung, then act on it" lists LIVE_SRC/LIVE_LAG/LIVE_ADDS/MIG_FAILED |
| 653-662 | But the budget is an EDIT's | MOVE | situational | wrap-ledger.sh (LIVE_ADDS > 0 breaches at lag 1) | `~/.claude/commands/wrap.md` § "Read the rung, then act on it" (confirmed: table row 🚀 + ¶ "An ADD is not budgeted at all … breaches at lag 1"); pointer in slim 🚀 item, absolute path (fix) |
| 663-673 | …and it breaches at a lag | DELETE (+1 clause KEEP) | history / env-fact | wrap-ledger.sh (deploy-last-advance base) | REF (ledger internals); the auditor-of-record clause kept in the slim 🚀 item: `scripts/deploy-parity-assert.sh` audits a new deployed top-level (fix) |
| 674-676 | 👤 vs ✅ is the second one | DELETE | history | — | REF (2026-08-01 incident) |
| 676-679 | 👤 counts only steps THIS SESSION | REWRITE | mode-rule | wrap-ledger.sh YOURS / operator-readout.sh ◆ line | slim 👤 list item |
| 680 | Mixed turn → show the worst-open | DELETE | duplicate | — | same rule at line 625 ("Pick the worst-open rung"), kept once in slim |
| 682-683 | Only ⛔, and 📦 in a | KEEP | mode-rule | — | slim "What each rung requires" intro |
| 685-688 | 🔧 never yields. Ending a turn | REWRITE | mode-rule | session-continue.sh (mechanical arm) | slim bullet; "defect, not a status report" → constraint |
| 689-696 | …but 🔧 you did not CAUSE | REWRITE | quirk-fix | — | slim bullet; claude-infra v2 postland example generalised |
| 697-702 | 📦 auto-/ships wherever the target repo's | DELETE | duplicate | — | Ship policy table (slim) + history (reso hardcode note) |
| 703-706 | 🚀 auto-converges, then re-reads the | REWRITE | mode-rule | session-continue.sh ship floor (🚀 arm) | slim 🚀 bullet (`bash <repo>/scripts/deploy-live.sh`, `cc-backlog needs` verbatim) |
| 707-710 | Context is a CLOSE-TIME decision | REWRITE | mode-rule | — | slim context bullet (fill thresholds stay in § Context Stewardship) |
| 712-713 | table header Test / Action | KEEP | mode-rule | — | slim table |
| 714 | ♻️ Recycle | REWRITE | env-fact | — | slim table row; flags verbatim |
| 715 | 🔀 Switch in place | KEEP | env-fact | — | slim table row |
| 716 | 📤 Handoff | KEEP | env-fact | — | slim table row (`Skill(handoff)`) |
| 717 | ⏸ Hold | KEEP | mode-rule | — | slim table row |
| 719-724 | The Hold test, stated so it | REWRITE | mode-rule | — | slim "Hold test" ¶ |
| 726-736 | "It needs a fresh worktree" is NOT | MOVE | history | — | `~/.claude/commands/handoff.md` ~l.437-450 (confirmed: recycle into a worktree, "Recycle first; spawn a new pane only for … a different model"); one-line rule + pointer in slim, absolute path, trigger "when choosing between recycle and handoff for a new worktree or account" (fix) |
| 738-748 | "It needs a different ACCOUNT" is NOT | MOVE | history | — | `~/.claude/commands/handoff.md` l.441-450 (confirmed: account half, `--recycle --account`, `cc-lr switch`); same slim line |
| 750-753 | Fresh context ⇒ RECYCLE. handoff-fire.sh --recycle --account | DELETE | duplicate | — | covered by slim Recycle row; cited line numbers are stale (recycle_repick is now handoff-fire.sh:9767, not :9436) |
| 754-756 | Context preserved ⇒ cc-lr switch | DELETE | duplicate | — | same content as Switch-in-place row (715) |
| 758-760 | Do not restore the old wording | REWRITE | mode-rule | — | slim: "If an account change is refused, read the refusal and fix the verb or the gate it names" |
| 761-767 | ✅ is a safe-to-close assertion | REWRITE | mode-rule | completion-assert.sh; wrap-ledger.sh (🚀/👤 computed) | slim "Asserting done" ¶2; "gates green this turn" and "DoD remainder 0" dropped as duplicates of lines 617-620 (slim ¶1, which ¶2 extends with "additionally") |
| 767-770 | Where a background verifier owns the | REWRITE | quirk-fix | — | slim "Asserting done" ¶2 (claude-infra v2 named → generic) |
| 772-777 | The close message — a relay | REWRITE | mode-rule | — | slim "The close message" ¶1 |
| 779 | THE ADMISSIBILITY RULE — this replaces | DELETE | history | — | "replaces the word cap" is history; rule kept in next row |
| 781-784 | A line may appear only if | KEEP | mode-rule | — | slim admissibility ¶ (emphasis removed) |
| 786-796 | Why the cap went (2026-08-23) | DELETE | history | — | REF (998-close correlation study) |
| 798-802 | Spend the slots by DROPPING items | REWRITE | quirk-fix | — | slim ¶; Anthropic quote reduced to the rule |
| 803-804 | Skip, by name: root-cause narrative | KEEP | mode-rule | — | slim ¶; "em-dash tangents" restored (fix) |

### C5: lines 806-1061

Source: `C5.labels.md`; verify report `C5.verify.md`.

| lines | opening words (<= 8) | label | reason code | enforced-by | destination |
|---|---|---|---|---|---|
| 806 | ### The six slots, in this order | REWRITE | mode-rule | — | slim: heading + "Omit a slot that has nothing to say; never pad one." |
| 808-809 | table header: Slot / The one fact | REWRITE | mode-rule | — | slim table header (bold removed, columns renamed) |
| 810 | S1 STATE — line 1 | REWRITE | mode-rule | completion-assert.sh D6 `line-1-rung` (origin, ✅/👤) | slim table row |
| 811 | S2 VERDICT — line 2 `Good to close:` | KEEP | mode-rule | completion-assert.sh D6 `good-to-close-verdict` | slim table row, `Good to close: yes\|no — …` verbatim |
| 812 | S3 ACT — line 3 `▶ Run this:` | KEEP | mode-rule | completion-assert.sh D7 (rung 👤) | slim table row, marker verbatim |
| 813 | S4 OUTCOME | REWRITE | mode-rule | — | slim table row (emphasis removed) |
| 814 | S5 EVIDENCE | REWRITE | mode-rule | — | slim table row |
| 815 | S6 WAITING | REWRITE | mode-rule | — | slim table row |
| 817 | S1–S3 are the three lines they scan | REWRITE | mode-rule | — | slim: "S4–S6 are at most three supporting lines" |
| 817 | (Ch 6 p. 78) | DELETE | history | — | reference |
| 817-820 | The order is arithmetic, not taste | REWRITE | mode-rule | completion-assert.sh D7 via close-shape.sh `close_act_missing` (`CC_ACT_WINDOW` default 3) | slim: one sentence keeping `CC_ACT_WINDOW`=3; "verified by executing close_act_missing" dropped as history |
| 822-825 | S1 — STATE. The renderer owns | REWRITE | env-fact | completion-assert.sh D6 line-1-rung | slim S1 paragraph: `scripts/wrap-ledger.sh --machine`, `READOUT`, shape, copy glyph + state clause |
| 825-829 | Do not render line 1 whole | DELETE | history | — | reference (Minto idea-vs-category explanation; the operative part survives in the count-expansion sentence) |
| 829-832 | Where the rendered tail is a count | REWRITE | mode-rule | — | slim S1: partition the count; `operator-readout.sh:818-819` line cite dropped; `⛔` keeps `BLOCKED_WHAT` |
| 834 | ONE rung, UNHEDGED — banned at DOCUMENT scale | REWRITE | quirk-fix | completion-assert.sh D3 (line 1 only; document-scale half is unenforced) | slim: "Line 1 carries one rung… nothing later in the close withdraws it" |
| 835-838 | "Yes — with one thing still parked" | DELETE | history | — | reference (two incident closes) |
| 838-841 | If something is parked or is theirs | REWRITE | quirk-fix | completion-assert.sh D3 reason carries the same text | slim: parked/theirs IS the rung; qualification goes in S2 `follow-on:` |
| 841-844 | It must carry an idea, not a category | REWRITE | quirk-fix | — | slim: folded into the line-1 sentence with the `12 runnable now, 195 need your call` example; Minto citation deleted |
| 846 | S2 — VERDICT. `Good to close:` on line 2 | KEEP | mode-rule | completion-assert.sh D6 | slim S2 |
| 846-850 | This line is not derivable from the rung: 613 closes | DELETE | history | completion-assert.sh D6 reason restates the key numbers | reference; slim keeps "The rung does not imply it" |
| 850-855 | Position is the whole failure | DELETE | history | — | reference; slim keeps "a rendered `✅ SAFE TO CLOSE` certificate does not replace it" |
| 855-856 | An honest `Good to close: no — …` satisfies | KEEP | mode-rule | completion-assert.sh D6 | slim S2 |
| 856-861 | Complication/Solution/Outcome are no longer required | REWRITE | mode-rule | — | slim: optional, write only when it adds; stats and "recap prompt" aside deleted (history) |
| 863 | S3 — ACT. Its own line, third, at most one | KEEP | mode-rule | completion-assert.sh D7 | slim S3 |
| 863-866 | The one position claim with a measured effect | DELETE | history | close-shape.sh `close_act_reason` prints the 35%/9%/4% figures | reference; slim keeps "never welded into a sentence or into line 1" |
| 866-868 | Action before argument (Ch 5 pp. 65-66) | REWRITE | quirk-fix | — | slim S3 second sentence (citation removed) |
| 870-872 | S4 — OUTCOME. State the goal | REWRITE | mode-rule | — | slim S4; the "So, where are we" anecdote deleted (history) |
| 874-876 | S5 — EVIDENCE. The receipt that makes | REWRITE | mode-rule | — | slim S5; "45 of 50 commits carry a body" deleted (history) |
| 877-879 | But only if you name the sha | KEEP | quirk-fix | — | slim S5: `git merge-base --is-ancestor <sha> origin/main` verbatim |
| 881-884 | S6 — WAITING. Named, never counted | REWRITE | quirk-fix | — | slim S6; the two quoted closes deleted (history) |
| 884-886 | The machine's standing pile is the opposite case | KEEP | env-fact | operator-readout.sh renders the `◆` line in `OPERATOR ▸` | slim S6 |
| 886-889 | Saying what is theirs is the only protective feature | REWRITE | mode-rule | — | slim S6: never dropped (`/wrap` cannot recover it); omit when nothing is theirs; −6.9pp stat deleted |
| 891 | Every identifier is expanded at first use | REWRITE | quirk-fix | — | slim identifier paragraph (unenforced; kept in full) |
| 892-894 | The largest measured effect on this surface | DELETE | history | — | reference (49.2% vs 33.6%, p=0.0001) |
| 894-898 | A close made its blocking question G-A | REWRITE | quirk-fix | — | slim: compressed to one inline example of stating the decision instead of the label |
| 898-902 | unexpanded tokens (M8 · S1 · R1/R2) | REWRITE | quirk-fix | — | slim: expand session-internal tokens, or delete an id that means nothing to the reader (plan-section label; git log and the plan hold it); filed-id gloss example kept verbatim (fix 2026-09-23: original delete trigger restored) |
| 902-905 | the label doing the answer's job | REWRITE | quirk-fix | — | slim: "A label is never the subject of a line"; Minto citation deleted |
| 907-908 | Corollary — a decision you are holding IS the rung | KEEP | mode-rule | bin/cc-decide refuses; wrap-ledger.sh computes ⛔ | slim: imperative + timing restored ("File a decision you are holding the moment you have it; filing is what makes it the ⛔ rung"); `cc-decide open --class C --what … --conviction N --receipt R --option … --option …` verbatim |
| 908 | and a class-B packet … carries the same | REWRITE | mode-rule | bin/cc-decide:239 refuses class B without them | slim |
| 908 | (extended 2026-09-08 by packet aa19d7b7a693: 19 of 19) | DELETE | history | — | reference |
| 908 | the F2 number rule: a class-C open without the number | REWRITE | duplicate | bin/cc-decide:222; wrap-ledger.sh `UNCONVICTED_MINE` | partial duplicate of Follow-On Gate F2 (CLAUDE.global.md:601, chunk C4); slim keeps one clause naming the refusal and `UNCONVICTED_MINE` |
| 909-912 | `wrap-ledger.sh` then computes `⛔` | REWRITE | env-fact | scripts/wrap-ledger.sh `BLOCKED` | slim |
| 912-914 | (`⛔` is also the safest rung measured) | DELETE | history | — | reference |
| 916 | ### Where the dropped detail goes — VETO | REWRITE | mode-rule | — | slim heading "Where dropped detail goes" + one-line rule |
| 918-919 | table header: Detail dropped / Its store | REWRITE | env-fact | — | slim table header |
| 920 | governing state (rung · dirty · gate…) | REWRITE | env-fact | — | slim row; "8 lines / 100 words" size note deleted |
| 921 | operator-owned actions and decisions | KEEP | env-fact | — | slim row, store paths and three read-back commands verbatim |
| 922 | why the work was done, what changed | KEEP | env-fact | — | slim row |
| 923 | design decisions, rejected approaches | KEEP | env-fact | — | slim row |
| 924 | reasoning, dead ends, synthesis never committed | KEEP | env-fact | — | slim row |
| 926-928 | `/wrap --full` is NOT the narrative tier | REWRITE | env-fact | — | slim: "`/wrap --full` is repository state only, and no command reads a session's own narrative back"; "96 entries in bin/" deleted |
| 928-932 | The precedent is on trunk (48 of 58 Stop-hook) | DELETE | history | — | reference (`docs/plans/STOPHOOK_MESSAGE_TIERING.md`, row 1031594b6327) |
| 932-934 | If the detail is not committed and not in a doc | KEEP | mode-rule | — | slim, compact |
| 936-938 | Acceptance — (1) The 30-second test | REWRITE | mode-rule | — | slim acceptance (1); Minto page citations deleted |
| 938-941 | (2) It fits one 24-row pane | REWRITE | mode-rule | — | slim acceptance (2); "46.2% overflow" and "word cap" aside deleted (history) |
| 943 | Three dispositions, never a fourth. "Say the word" | REWRITE | mode-rule | completion-assert.sh D4 | slim heading "### Three dispositions" (kept as the anchor that CLAUDE.global.md:610 (Follow-On Gate F4) cites) + one line |
| 945-946 | table header: Disposition / What it looks like | REWRITE | mode-rule | — | slim: converted to a bullet list (the FILED cell is a paragraph, not a cell) |
| 947 | DRIVEN — you did it this turn | KEEP | mode-rule | — | slim bullet |
| 948 | FILED — the EXCEPTION, burden of proof | REWRITE | mode-rule | completion-assert.sh D4 reason restates the burden | slim FILED bullet lead |
| 948 | (a) why not now — a named IMPOSSIBILITY; four classes | KEEP | mode-rule | bin/cc-backlog add refuses other classes (message lists all four and the reasons-vs-impossibilities text); measures `no-capacity`; requires conviction on `needs-human` | slim (a), class names and flags verbatim |
| 948 | Anything else ⇒ DRIVE it… "Out of scope" are reasons | REWRITE | mode-rule | bin/cc-backlog refusal text | slim (a), compact |
| 948 | Capacity is the test this rule never asked (2026-09-05) | DELETE | history | — | reference (tenant-schema incident, 167pp strand figure) |
| 948 | unused weekly quota is decaying inventory | REWRITE | mode-rule | — | slim: "Unused weekly quota does not roll over, so idle accounts are capacity." |
| 948 | (`scripts/desk-strand-replay.py`; /accounts weekly column understates) | REWRITE | mode-rule | — | slim FILED (a): one clause "judge capacity from the strand nowcast (`scripts/desk-strand-replay.py`), not the `/accounts` weekly percentage" (fix 2026-09-23: was a MOVE whose pointer did not name capacity judgments) |
| 948 | (b) why it will still be true | REWRITE | mode-rule | — | slim (b): "p90 of about 9 days" range kept, `--falsifier` verbatim |
| 948 | (c) who it is for — `cc-backlog needs` | KEEP | env-fact | scripts/wrap-ledger.sh `FILED_MINE` | slim (c), `cc-backlog needs "<step>"`, `--run`, `cc-do <id>`, `cc-backlog add --why-not-now` verbatim |
| 948 | Cannot answer all three ⇒ DROP IT | KEEP | mode-rule | — | slim |
| 948 | An unanswerable row is noise; filing is the defect | DELETE | duplicate | — | restates the FILED lead in the same bullet |
| 948 | When you do file, the STANDING pile renders | KEEP | env-fact | operator-readout.sh | slim |
| 949 | BLOCKED — a genuine operator-only gate | KEEP | mode-rule | wrap-ledger.sh ⛔ | slim BLOCKED bullet |
| 949 | One exception, and it is the TERMINAL one | REWRITE | mode-rule | — | slim: exhaustion close itemizes only the decisions this session drove to the wall, one line each (sentence, conviction, options) (fix 2026-09-23: scope restored) |
| 949 | "the one decision you need" describes… plural is expected | DELETE | duplicate | — | explains the exception just stated; `BLOCKED` count noted in the corollary paragraph |
| 949 | § The close message S6 already binds the same way | DELETE | duplicate | — | S6 paragraph in this chunk |
| 949 | The counted `◆` line still owns the STANDING pile | KEEP | env-fact | operator-readout.sh | slim |
| 951-953 | Offering is the defect (operator ruling 2026-08-01) | REWRITE | quirk-fix | completion-assert.sh D4 | slim, one paragraph; ruling date and quote deleted (history) |
| 954 | Drive it, or drop it — filing is the exception | KEEP | mode-rule | completion-assert.sh D4 | slim |
| 954 | (That sentence read "Drive it, or file it" until 2026-09-05) | DELETE | history | — | reference |
| 954 | And they should never have to ask "good to close?" | DELETE | duplicate | — | S2 in this chunk |
| 956-960 | Operator-owned steps are FILED, never prosed | REWRITE | mode-rule | completion-assert.sh D1 (blocks a close that hands work over in prose with no filed row for this session) | slim paragraph |
| 960-962 | The test for filing rather than doing is strict | KEEP | mode-rule | completion-assert.sh D1 reason carries the same list | slim, plus "(a value judgment goes through `cc-decide open`, not `cc-backlog needs`)" so the list does not route decisions to `cc-backlog needs` |
| 964 | ONE COMMAND, never a list — MEASURED | REWRITE | mode-rule | — | slim heading "Handing over a command" + "exactly one thing to select and paste" |
| 964-965 | Relay, never paraphrase: reproduce any rendered block | DELETE | duplicate | — | Communication Discipline, CLAUDE.global.md:427-431 ("reproduce it verbatim, in full") and the close-message admissibility rule (a) RENDERED in chunk C4 |
| 966-968 | Their words: "I had to comb through" | DELETE | history | — | reference |
| 968 | The form that works in this TUI, screenshot-verified | DELETE | history | — | reference |
| 970-974 | code block: ▶ Run this: / `<the one command>` | KEEP | env-fact | completion-assert.sh D2/D7; close-shape.sh `close_act_template` prints the same form | slim code block with the blank line kept (the screenshot-verified form, commit 2536ff30a; D7 counts non-blank lines); arrow annotation dropped |
| 976-978 | A marker line of its own; three properties | REWRITE | env-fact | completion-assert.sh D2 reason restates the properties | slim: "on its own line… inline-code span alone on its line" |
| 979-981 | Do NOT use a ```bash fence | REWRITE | quirk-fix | completion-assert.sh D2 reason | slim: "not a ```bash fence (renders plain white)" |
| 981-983 | Do NOT use a blockquote; `$` prefix | REWRITE | quirk-fix | completion-assert.sh D2 reason (blockquote); `$` prefix unenforced | slim |
| 983-985 | (Generalisable lesson: a rendering claim) | DELETE | history | — | reference |
| 987-988 | Multiple runnable steps collapse to `cc-do` | KEEP | env-fact | — | slim, `cc-do --list`, `cc-do <stem>` verbatim |
| 988-990 | `cc-do --list` is 317 lines / 6,845 words | REWRITE | mode-rule | — | slim keeps only "show it only as the collapsed `▶ cc-do [N runnable]` row"; size figures deleted |
| 990 | Judgment items are counted, not itemized | KEEP | mode-rule | — | slim |
| 991-993 | Every command shown carries a run verdict | REWRITE | quirk-fix | completion-assert.sh D2 reason ("one you would then tell them to ignore must not appear") | slim |
| 993-994 | (One close showed a command… "Ignore the command") | DELETE | history | — | reference |
| 995-997 | Reference-only commands stay in inline backticks | KEEP | mode-rule | — | slim |
| 998-1003 | The marker is LITERAL, payload EXECUTABLE AS TYPED | REWRITE | quirk-fix | — (close-shape.sh matches any `▶`, so the verb is not enforced; placeholders are D5) | slim: marker literal, no other verb, `cursor <path>` |
| 1003-1005 | (Measured 2026-08-25: `▶ Open this:` over a bare doc path) | DELETE | history | — | reference |
| 1006 | Opt-in detail (`/wrap --full` / on request) | REWRITE | tool-dup | scripts/wrap-ledger.sh --full renders it (wrap-ledger.sh:17, :2255; commands/wrap.md:148) | slim: one sentence pointing at `scripts/wrap-ledger.sh --full` |
| 1008-1017 | code block: SESSION LEDGER template | DELETE | tool-dup | scripts/wrap-ledger.sh --full prints this block | the renderer; field list stays in the reference |
| 1019-1022 | Auto-continue actuation (🔧 only). arm / clear | KEEP | env-fact | hooks/session-continue.sh (Stop, settings.json:994) | slim heading kept (CLAUDE.global.md:606, Follow-On Gate F4, cites "§ Auto-continue actuation"); `set` / `clear` commands verbatim |
| 1022-1023 | A Stop hook actuates it (`decision:block`) | REWRITE | env-fact | hooks/session-continue.sh | slim: "a Stop hook then feeds that step back" |
| 1023-1024 | Nothing here bounds a compliant chain | REWRITE | mode-rule | — | slim: one sentence |
| 1024-1029 | `CLAUDE_CONTINUE_MAX` (default 8) … 0 trips in 11 days … `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` | REWRITE | duplicate | — | `CC_MECH_MAX × CLAUDE_CONTINUE_MAX` is in Session Close (CLAUDE.global.md:486) and F4 (:605-606); `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` in the Session Close intro (:465); measurements deleted (history); slim keeps `CLAUDE_CONTINUE_MAX` (default 8) bounds only the mechanical arm as `CC_MECH_MAX × CLAUDE_CONTINUE_MAX`, and `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` catches only a text-only wedge (fix 2026-09-23: C4.slim also dropped them, so no slim carried them) |
| 1029-1031 | For this operator's goal an unbounded driver is DESIRED | DELETE | history | — | reference (explains why the missing bound is not a defect) |
| 1031-1033 | The real stop conditions are the kill-switch | KEEP | mode-rule | — | slim |
| 1033-1034 | This is the cross-turn arm; within a turn keep working | REWRITE | mode-rule | — | slim last sentence |
| 1036-1039 | The single `→ Next` verb may be auto-fired | REWRITE | mode-rule | — | slim; partial duplicate of the ship-policy table (Session Close part 1, chunk C4), kept because it names the auto-fire verb set |
| 1039-1040 | Per-project gate names… `/wrap` computes the ledger | REWRITE | env-fact | — | slim keeps the project `CLAUDE.md` "Session Close" pointer; "`/wrap` computes the ledger" deleted as duplicate of the dropped-detail table |
| 1042-1043 | Kill-switch: any per-prompt "…and stop" | KEEP | mode-rule | hooks/session-continue.sh clears the sentinel; hooks/completion-assert.sh `CA_KILL_RE` abstains | slim "### Kill-switch", phrases verbatim |
| 1045-1046 | It must be the OPERATOR's per-prompt instruction | KEEP | mode-rule | — (see uncertain: the hooks treat non-meta fire/recycle briefs as disarming) | slim |
| 1046-1050 | Measured 2026-09-08 over ~1,500 transcripts | DELETE | history | — | reference |
| 1050-1052 | `completion-assert.sh` reads the LAST non-meta user record | REWRITE | env-fact | hooks/completion-assert.sh `ca_last_user_msg` | slim: folded into the reason clause of the next rule |
| 1052-1055 | (Live impact is currently small — 1 abstain in 530) | DELETE | history | — | reference |
| 1055-1056 | Never write a kill phrase into a brief | KEEP | quirk-fix | — | slim |
| 1056-1058 | the one house template that carries one today | DELETE | history | — | reference (`agents/deep-research-sonnet.md`:31 carries "and stop") |
| 1060 | --- | KEEP | mode-rule | — | slim, section separator before § Manual-Command Delivery |
| (new) | The measurements and incidents behind the close rules | — | — | — | slim pointer line to the reference § Session Close Protocol (covers all history deletions) |

### C6 part 1: lines 1062-1077

Source: `C6.labels.md` § Part 1; verify report `C6.verify.md`.

| lines | opening words (<= 8) | label | reason code | enforced-by | destination |
|---|---|---|---|---|---|
| 1062 | ## Manual-Command Delivery | KEEP | mode-rule | — | slim heading, text unchanged (cited by `bin/cc-cannot:104`, `scripts/cloud-answer.py:63`, `scripts/worktree-gc.sh:1501`) |
| 1064 s1 | A hand-off is a PROGRAM, not a | REWRITE | mode-rule | partial: `hooks/handoff-claim-assert.sh` (Stop) blocks a `▶ Run this:` command the agent can run itself: "Hand-off claim REFUTED — you handed the operator a command you can run yourself" | slim ¶1; full rule in skill `manual-command-delivery` (SKILL.md ¶1-2) |
| 1064 s2 | Making the human the runtime is the | DELETE | duplicate | — | restates s1; skill ¶1 |
| 1064 s3 | (Rewritten 2026-08-25. The old text — | DELETE | history | — | skill § "What this superseded"; reference `CLAUDE.global.md` § Manual-Command Delivery |
| 1066 s1 | Sort steps by BLAST RADIUS, never by | REWRITE | mode-rule | — | slim bullet 1; skill § Sort steps by BLAST RADIUS |
| 1066 s2 | Reversible ⇒ driven silently. Irreversible / production-mutating | REWRITE | mode-rule | — | slim bullet 1 |
| 1066 s3 | and the same consent must also be | REWRITE | quirk-fix | — | slim bullet 2 (`!` has no stdin: env fact) |
| 1066 s3 tail | (measured 2026-09-23, reso `rotate-soketi-key.sh`, fixed | DELETE | history | — | skill § Sort steps (same measurement) |
| 1066 s4 | A block bought a human READING that | DELETE | history | — | skill § Sort steps ("A block bought a human READING…") |
| 1066 s5 | A permission prompt is already a per-command | REWRITE | mode-rule | — | slim bullet 3; skill § Permission-blocked ≠ classifier-blocked |
| 1066 s6 | NEVER script your own authorization — no | REWRITE | quirk-fix | partial: `~/.claude/settings.json` autoMode `soft_deny` "Self-Modification" (covers the agent's own settings edits, not a handed-over file) | slim bullet 4; skill § NEVER script your own authorization |
| 1066 s7 | The READ half is yours, though, and | REWRITE | env-fact | — | slim bullet 5 (`bin/cc-permission-audit`, `CONFIRM=1`, `--prune` kept verbatim; what it reports, redundant or shadowed allow rules, kept as the cue to reach for it) |
| 1066 s8 | three independent arms refuse an agent-side allowlist | DELETE | history | `~/.claude/settings.json` autoMode `soft_deny` "Self-Modification" | enforcement narrative; reference |
| 1066 s9 | Read its numbers with its own caveat | DELETE | tool-dup | `bin/cc-permission-audit:182-186` prints its own NOTE when `approved 0` and unknown > 0 | — |
| 1066 s10 | Verdicts fail closed: an exit code, or | REWRITE | quirk-fix | — | slim bullet 6; skill § Verdicts fail closed |
| 1066 s11 | If the residue is a decision, there | KEEP | mode-rule | — | slim bullet 7 |
| 1066 s12 | Full rule → the manual-command-delivery skill | REWRITE | situational | — | slim pointer line, now says when to load it |
| 1068 | `---` | KEEP | — | — | separator |
| 1070-1072 | `<!-- Deliberately the LAST thing in this` | KEEP | history | loader strips HTML comments, so 0 context tokens (measured: a comment-only memory file yields no `/context` row) | maintainer note kept verbatim |
| 1074 | `<tone_preference>` | KEEP | quirk-fix | — | slim |
| 1075 | Keep it concise. Lead with the answer | KEEP | quirk-fix | — | slim (user preference; restates § Communication Discipline at the end on purpose) |
| 1076 | Hand over ONE command, never a list | REWRITE | quirk-fix | — | slim; capitals removed; restates § Communication Discipline "ONE COMMAND" by design |
| 1077 | `</tone_preference>` | KEEP | — | — | slim |

### Assembly-stage edits (cross-chunk coherence pass)

Applied to `CLAUDE.global.slim.md` after concatenation; the per-chunk `*.slim.md` files are unchanged.

| slim location | label | reason code | change |
|---|---|---|---|
| lines 1-2 (header) | NEW | env-fact | Two-line header: this is the slim variant under A/B; the full text and rationale stay at `~/Development/claude-infrastructure/CLAUDE.global.md`, read the matching section when a rule seems to lack context. |
| Git, Safety bullet 1 | REWRITE | duplicate | Dropped C1's restatement of when to run or only offer `/ship`; the bullet now points to Session Close Protocol, Ship policy, which states it once. |
| Git, Safety bullet 3 | REWRITE | duplicate | Merged C1's two force-push sentences (C1 fix pass flagged them as redundant): never to main/master; elsewhere only on explicit request. |
| Ship policy ¶2 | DELETE | duplicate + inaccurate | Removed "A project CLAUDE.md loads only when the session cwd is that project" (C1 verify: parent-directory CLAUDE.md files also load); now points to Working rules, which carries the corrected wording once. |
| Agent Teams, Where implementation runs | REWRITE | pointer | `commands/handoff.md` § Waves and § Autonomous fire item 1 → `~/.claude/commands/handoff.md` § Autonomous fire, item 6 (Waves) / item 1 (resolves from any repo; there is no heading named Waves). |
| Communication Discipline, Files you write | REWRITE | emphasis | `INTEGRATE-never-overwrite` → "Integrating rather than overwriting (Updating existing files)". |
| Communication Discipline, Verification | REWRITE | contradiction | "below 90% conviction" → "at or below 90%" to match Follow-On Gate F2 as fixed in C4 (the tools refuse only N > 90). |
| Context Stewardship, three bullets | REWRITE | contradiction | "`/handoff` now / at its natural end / before about 75%" → "recycle or hand off", with a pointer to the context table under Session Close Protocol, which says to reach for recycle first. |
| Disposition table, decision row; Follow-On Gate PASS/FAIL line | REWRITE | emphasis | `STOP-ASK` → "stop and ask". |
| Disposition table, context-exhausted row | REWRITE | pointer | "(context dispositions below)" → "(context table under What each rung requires)". |
| The readout, ⛔ bullet | DELETE | duplicate | Dropped "A filed class-C packet makes the ledger compute ⛔"; the six-slots decision paragraph states it with the full command. |
| The six slots, decision paragraph | DELETE | duplicate | Dropped the `cc-decide` refusal and `UNCONVICTED_MINE` sentence, stated once under Follow-On Gate F2; replaced by "both follow the F2 number rule". |
| The six slots, S2 | REWRITE | duplicate | The two `Good to close:` forms are given once, under Origin close contract (the D6 arm's matched strings); S2 now refers to them and keeps only placement. |
| Auto-continue actuation, `→ Next` | REWRITE | duplicate | "(every repo, unless the target repo's own CLAUDE.md says landing spends money, where it stays an offer)" → "as the ship policy allows". |
| Auto-continue actuation | REWRITE | emphasis | `<the ONE next step>` → `<the one next step>`. |

## 2. `~/.claude/rules/agent-operating-lessons.md` (C6 part 2): removed from the always-loaded directory

Verdict from `C6.rules-essay.md`: nothing in it changes what an agent does in a normal session. The file leaves `~/.claude/rules/`, its text moves verbatim to `docs/lessons/user-rules-dir-loads-in-every-invocation-mode.md` (staged at `audit/C6.staged/docs/lessons/`), and it has no replacement text. Precondition: fix the stale `hooks/memory-nudge.sh` hint in the same change.

| lines | opening words (<= 8) | label | reason code | enforced-by | destination |
|---|---|---|---|---|---|
| 1 | THIS DIRECTORY LOADS EVERYWHERE — interactively AND | DELETE | history | — | lesson doc (below); fact already in `bin/cc-mission:16-21` |
| 3 | `<!-- load-check sentinel: RULESLOAD-OK-A7F3` | DELETE | history | — | broken instrument, see Finding 1 (0 context tokens: the loader strips HTML comments) |
| 5-7 | CORRECTED 2026-09-03. The headline below said | DELETE | history | — | lesson doc |
| 9-13 | The evidence is this file itself | DELETE | history | — | lesson doc |
| 15-18 | invocation / `~/.claude/rules/*.md` table | DELETE | duplicate | — | `bin/cc-mission:16-21`; lesson doc |
| 20-27 | SECOND CORRECTION, 2026-09-09: the headless arm | DELETE | history | — | lesson doc |
| 29-32 | Why this matters more than a doc | DELETE | history | — | `bin/cc-mission:16-21` states the carrier fact |
| 34-41 | AND MY OWN FIRST CORRECTION WAS ALSO | DELETE | history | — | lesson doc; Finding 1 supplies the cause it left open |
| 43-48 | The shape to recognise, three times now | MOVE | situational | — | staged lesson doc (stated as its opening rule). Scope narrows, accepted: the resident copy that remains is `.claude/rules/agent-operating-lessons.md:110` ("Probe the OLD binary too"), which loads only in claude-infrastructure sessions, not in every repo. Accepted because it is one investigation-method lesson among ~120 in that file with no case for global residence over the others; the global file keeps the related "a refusal bounds the TOOL, never the world" |
| 50-56 | Why the original conclusion was wrong | DELETE | history | — | lesson doc; the cited memory lives in reso's memory dir (`reference-a-refusal-bounds-the-tool-not-the-world.md`) |
| 58-61 | The decision rule below — "`NONE` ⇒ | DELETE | history | — | lesson doc |
| 63-66 | Consequence for content: an interactive session | DELETE | history | — | superseded by line 18 of the same file (headless loads too) |
| 68 | `---` | DELETE | history | — | — |
| 70-71 | The ORIGINAL record, preserved verbatim below | DELETE | history | — | lesson doc |
| 73-81 | The probe, with a positive control | DELETE | history | — | lesson doc |
| 83-87 | Re-check in one command from any | DELETE | history | — | broken by construction, Finding 1 |
| 89-90 | `NONE` ⇒ still dead, leave this | DELETE | history | — | stale: contradicted by lines 18-27 of the same file |
| 92 | Where the content went | DELETE | history | — | — |
| 94-97 | The 28 agent-operating lessons this file | MOVE | situational | — | staged lesson doc § Where the reso lessons live; reso's `.claude/rules/agent-operating-lessons.md` loads itself in reso sessions (present on reso `origin/main`) |
| 99-100 | For cross-repo reach, symlink that file | MOVE | situational | — | staged lesson doc § Where the reso lessons live (the symlink recipe); its "do not re-add content here" clause is false since 2026-09-09 and is not carried forward |
| 102 | Full record: reso `docs/plans/MEMORY_ARCHITECTURE_SPLIT.md` §5 | DELETE | history | — | dead pointer: that file was deleted on reso `origin/main` in ece6ed407 |

## 3. `~/.claude/rules/00-mission-board.md` (C6 part 3): compact render behind a flag

This file is generated by `bin/cc-mission render`, so the change is to the renderer, not to lines. Full detail, the unified diff and the new test are in `C6.mission-board.md`.

| Element of the full render | Disposition in compact mode | Where the full text is |
|---|---|---|
| Banner with emoji alarm and capitalised "outrank" rule | REWRITE: one plain intro paragraph restating the four rules (outrank infra work; work the top row or say why not; agents stop at `awaiting-signoff`; NEEDS-SOURCE means draft the ask) | — |
| Each row's full `next` essay (the bulk of the 13,998 bytes) | MOVE: one line per row, headline = optional `headline` field (≤200 chars) or the first 200 chars of `next` | `cc-mission next` (top row in full), `cc-mission show <id>` (any row) |
| "What to do with this" footer | REWRITE: folded into the intro, plus "read a row in full before acting on it" | — |
| No-stale branch | KEEP (already one line) | — |

Flag: file `~/.claude/autonomy/customer/render-compact`, override `CC_MISSION_COMPACT=1|0`. Flag off is byte-identical to today's output (verified with `cmp`).

## 4. `.claude/CLAUDE.md` (C6 part 4)

| lines | opening words (<= 8) | label | reason code | enforced-by | destination |
|---|---|---|---|---|---|
| 1 | # claude-infrastructure — Project Memory | KEEP | env-fact | — | slim |
| 3-5 | Project-only rules for THIS repo. Loaded as | DELETE | default-behavior | — | the harness already labels this file as project instructions; the scoping rationale is for maintainers (git history) |
| 7 | ## Never commit or land in the | KEEP | mode-rule | — | slim |
| 9-10 s1 | `~/Development/claude-infrastructure` is the symlink source for | KEEP | env-fact | — | slim |
| 10-12 s2 | Committing there risks (a) landing onto a | DELETE | history | partial: `hooks/validate-bash.sh` SHARED-COMMIT-ARM (:1425) denies a plain `git commit` in the shared checkout, but passes any command containing `<<` (heredoc messages) and has kill switch `CC_SHARED_COMMIT_GATE=off`, so the slim text does not claim enforcement | git history of this file |
| 12-14 s3 | incident 2026-07-11: `dfacccd` (limit-recover skill, 5 | DELETE | history | — | git history of this file |
| 14-15 s4 | Always work in a dedicated worktree, commit | REWRITE | mode-rule | partial: `hooks/validate-bash.sh` SHARED-COMMIT-ARM (:1425; heredoc commits pass) | slim |
| 15-16 s5 | Verify landings by CONTENT (`git ls-tree origin/main | KEEP | quirk-fix | — | slim; overlaps `CLAUDE.global.md` § Session Close Protocol ("verified BY CONTENT"), kept because the incident class is this repo's |
| 18 | ## Standing-land authorization (this repo only) | KEEP | mode-rule | — | slim heading |
| 20-22 s1 | In THIS repo, work that is complete | REWRITE | duplicate | — | slim one line; the global ship policy (`CLAUDE.global.md` § Session Close Protocol) already defaults to auto-`/ship` in every repo |
| 22-23 s2 | (operator standing directive 2026-07-18: identified net-positive | DELETE | history | — | git history |
| 23-25 s3 | Why scoped here: parked commits leave the | DELETE | duplicate | — | the converge section states the symlink-farm fact |
| 25-27 s4 | The authorization is exclusively for the fail-closed | REWRITE | mode-rule | partial: `hooks/ship-rail-push-allow.sh` auto-allows only the non-force `git push origin HEAD:<branch>` land shape; other pushes hit the `Bash(git push:*)` ask | slim ("never a bare `git push`"); the parenthetical `/ship` feature list is tool-dup (`.claude/commands/ship.md`) |
| 27 s5 | Global Git Safety is unchanged for every | DELETE | default-behavior | — | this file loads only in this repo |
| 28-30 s6 | After landing, sync the non-symlinked live copies | REWRITE | env-fact | — | slim converge bullet 3: names every copy class (`CLAUDE.global.md` → `~/.claude/CLAUDE.md`, `githooks/`, `launchd/*.plist`, `statusline.sh`, `bin/it2-wrapper` → `bin/it2`; `scripts/deploy-live.sh:1310-1311`); check the live copy after the converge and apply the edit by hand when the converge did not advance to your commit (refused, "already deployed", or an older not-RED target) |
| 32 | ## Standing-converge authorization (this repo only) | KEEP | mode-rule | — | slim heading, text unchanged (cited by `.claude/settings.json` `_why_converge` and `scripts/deploy-live.sh:30`) |
| 34-38 | Landing is the second-to-last step, not | REWRITE | mode-rule | — | slim |
| 40-42 | `CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh` | KEEP | env-fact | `.claude/settings.json:53-54` allow rule matches this exact string | slim, verbatim |
| 44 s1 | Never `--force`, and the difference is not | REWRITE | mode-rule | — (not mechanically blocked) | slim bullet 1 |
| 44-47 s2 | `--force` takes trunk's tip regardless of RED | REWRITE | env-fact | — | slim ¶ after the code block and bullet 1 |
| 47-50 s3 | Both leave the live tree unstamped, so | DELETE | history | — | `scripts/deploy-live.sh` header (lines 14-44) |
| 50-51 s4 | `--force` stays the OPERATOR's escape hatch, for | KEEP | mode-rule | — | slim bullet 1 |
| 53-57 | Not covered, because none of it is | REWRITE | mode-rule | `hooks/validate-bash.sh` FF-GATE: "Ungated advance of the SHARED CHECKOUT blocked" (:1432; the text's `:1352` citation is stale) | slim bullet 2, cites the hook by name, not line |
| 59-66 | Why it is safe to let the | DELETE | history | — | `.claude/settings.json` `_why_converge`; `scripts/deploy-live.sh` header; slim pointer bullet 4 |
| 68-69 s1 | The paired permission rule lives in `.claude/settings.json` | REWRITE | env-fact | `.claude/settings.json:53-54` (two exact spellings: relative and absolute script path) | slim: the two spellings, "an agent may not otherwise alter the gating and then deploy", and the refusal fallback (bare `bash scripts/deploy-live.sh`, which waits out the lag budget, or surface as `⛔`) from `scripts/deploy-live.sh:32-44` |
| 69-76 s2 | Measured 2026-09-15 as a 2x2, one | DELETE | history | — | `scripts/deploy-live.sh:32-44` holds the 2x2 table; `_why_converge` holds the grant |
| 78 | ## The global instructions live at `CLAUDE.global.md` | KEEP | mode-rule | — | slim heading |
| 80-81 | The SSOT for `~/.claude/CLAUDE.md` is `CLAUDE.global.md` | KEEP | env-fact | — | slim |
| 81-84 | Do not create or restore a root | REWRITE | mode-rule | `tests/deploy-parity.bats:1852` ("SSOT: … NOT at a root CLAUDE.md"); `scripts/loaded-untracked-lint.sh` goes red on an untracked root `CLAUDE.md` | slim |
| 84-86 s1 | Nothing diverges when that happens, so no | DELETE | history | — | `tests/deploy-parity.bats:1842-1852` comment |
| 86 s2 | THIS file is the project-only memory | REWRITE | mode-rule | — | slim last sentence: `.claude/CLAUDE.md` is project-only memory, not a duplicate; keep it (guards against deleting it by analogy with the root file) |

## 5. `.claude/rules/agent-operating-lessons.md` (C7): resident, index or delete

207 lessons: 19 RESIDENT (stay always-loaded, each rewritten to state its rule), 185 INDEX (one line each in the proposed `docs/lessons/INDEX.md`, full content in `C7.index.md`), 3 lessons DELETE as duplicates; the other header and comment rows are KEEP/REWRITE/DELETE/MOVE. The resident bar: the lesson applies to most sessions in this repo, or it prevents a costly silent mistake a session would not think to look up. The slim file tells the reader when to grep the index.

Resident lessons (original line numbers): 50, 66, 72, 77, 83, 100, 129, 154, 155, 165, 180, 191, 210, 211, 212, 215, 223, 228, 229.

| lines | opening words (<= 8) | label | reason code | enforced-by | destination |
|---|---|---|---|---|---|
| 1 | # Always-loaded project rules | KEEP | env-fact | none | slim heading |
| 3 | <!-- HOW TO ADD A LESSON HERE — | DELETE | duplicate | none | restated by the adding-a-lesson paragraph of the slim header |
| 5-8 | This file is injected into EVERY session in | REWRITE | history | none | slim header sentence 1 (loads into every session); the 190,960-char / 89.5% / 121-rule figures are history |
| 10 | The convention, and it is the whole budget | REWRITE | mode-rule | none | slim header, adding-a-lesson paragraph |
| 12 | / tier / what lives there / budget | REWRITE | mode-rule | none | table header folded into the adding-a-lesson paragraph |
| 13 | /---/---/---/ | DELETE | default-behavior | none | table separator row |
| 14 | / this file / ONE hook per lesson | REWRITE | mode-rule | scripts/rules-hook-budget-lint.sh (420-byte default via `wc -c`, RULES_HOOK_BUDGET) | slim header: bullet states its rule; "rewrite a bullet to fit rather than truncating it"; budget named as the lint's 420 bytes (fixed after verify) |
| 15 | / docs/lessons/<slug>.md / the full body: the incident, | REWRITE | mode-rule | none | slim header: body goes to docs/lessons/<slug>.md |
| 17-20 | So a new lesson is TWO writes: the | REWRITE | mode-rule | scripts/rules-hook-budget-lint.sh, run by scripts/ship-land.sh:3594 (refuses bodyless `.` links, over-budget and duplicate-target bullets) | slim header; the two-write rule now targets docs/lessons/INDEX.md; the slim also names hooks/memory-nudge.sh, hooks/lib/memory-index-budget.sh, bin/cc-memory-rotate and hooks/memory-index-drain.sh, which still route rules here, and applies the resident bar to their lines (fixed after verify F1/F6; companion edits to those messages listed in C7.verify.md § Fixes applied) |
| 22-25 | Why the hook may not degrade into a | REWRITE | mode-rule | none | slim header: 'A bullet states its rule, not a topic label'; the worked example moves with the reference copy |
| 27-31 | The two ceilings on this file are NOT | MOVE | situational | bin/cc-memory-rotate MEMORY_RULES_HARD_CAP=4194304 (refuses routing at the hard cap) | C7.index.md header (docs/lessons/INDEX.md); slim pointer: "A size warning on this file: see the ceilings note at the top of docs/lessons/INDEX.md" (added after verify) |
| 34 | <!-- routed 2026-09-06T02:52:09Z by cc-memory-rotate: 5 index line(s) | DELETE | history | none | cc-memory-rotate routing record; the routed rules themselves are indexed |
| 35 | Append atomicity ends at the buffer — a | INDEX | situational | none | docs/lessons/INDEX.md § Shell and scripting -> docs/lessons/append-atomicity-ends-at-the-stdio-buffer.md |
| 36 | Release ≠ !trip — a release rule that | INDEX | situational | none | docs/lessons/INDEX.md § Detectors, alarms and state -> mem/release-predicate-must-not-negate-the-trip.md |
| 37 | Loud into a dead log — fail-loud into | INDEX | situational | none | docs/lessons/INDEX.md § Detectors, alarms and state -> mem/fail-loud-into-a-log-nobody-reads-is-silent.md |
| 38 | Fail-safe mimics healthy — a fail-safe default matching | INDEX | situational | none | docs/lessons/INDEX.md § Detectors, alarms and state -> mem/fail-safe-default-mimics-the-healthy-state.md |
| 39 | Closures ≠ value — 40-55% of closures were | INDEX | situational | none | docs/lessons/INDEX.md § Measurement and evidence -> mem/closure-count-is-not-value-delivered.md |
| 40 | Oracle reads the viewport — a render table | INDEX | situational | none | docs/lessons/INDEX.md § Tests, fixtures and controls -> mem/screen-oracle-is-only-true-at-its-measured-geometry.md |
| 41 | 2026-09-09 · MEMORY.md index is at its hard | INDEX | situational | none | docs/lessons/INDEX.md § Sessions, fires, panes and permissions -> mem/dead-session-verdict-belongs-in-the-pane.md |
| 43 | <!-- demotion pointers written 2026-09-06T02:52:10Z by cc-memory-rotate: 18 | DELETE | history | none | cc-memory-rotate demotion record; archive path already recorded in memory/archive |
| 44 | demoted 2026-09-06 from MEMORY.md to MEMORY_ARCHIVE_2026-H2-COLD.md; the rule | INDEX | situational | none | docs/lessons/INDEX.md § Detectors, alarms and state -> mem/orphanhood-is-not-a-discriminating-signal.md |
| 45 | demoted 2026-09-06 from MEMORY.md to MEMORY_ARCHIVE_2026-H2-COLD.md; the rule | INDEX | situational | none | docs/lessons/INDEX.md § Tests, fixtures and controls -> mem/harness-default-collapses-the-states-under-test.md |
| 46 | demoted 2026-09-06 from MEMORY.md to MEMORY_ARCHIVE_2026-H2-COLD.md; the rule | INDEX | situational | none | docs/lessons/INDEX.md § Vendors, APIs and binaries -> mem/changelog-and-tracker-are-different-populations.md |
| 47 | demoted 2026-09-06 from MEMORY.md to MEMORY_ARCHIVE_2026-H2-COLD.md; the rule | INDEX | situational | none | docs/lessons/INDEX.md § Shell and scripting -> mem/config-flip-is-not-a-shell-flip.md |
| 48 | demoted 2026-09-06 from MEMORY.md to MEMORY_ARCHIVE_2026-H2-COLD.md; the rule | INDEX | situational | none | docs/lessons/INDEX.md § Shell and scripting -> mem/c-locale-turns-character-ops-into-byte-ops.md |
| 49 | demoted 2026-09-06 from MEMORY.md to MEMORY_ARCHIVE_2026-H2-COLD.md; the rule | INDEX | situational | none | docs/lessons/INDEX.md § Backlog rows, falsifiers and stranded work -> mem/falsifier-polarity-inverted-under-no-run.md |
| 50 | demoted 2026-09-06 from MEMORY.md to MEMORY_ARCHIVE_2026-H2-COLD.md; the rule | RESIDENT | unobserved-guard | none | C7.slim.md § Landing, shared worktrees and destructive actions (promoted after verify F3: irreversible deletion; body stays at its mem path) |
| 51 | demoted 2026-09-06 from MEMORY.md to MEMORY_ARCHIVE_2026-H2-COLD.md; the rule | INDEX | situational | none | docs/lessons/INDEX.md § Shell and scripting -> mem/greedy-anchor-matches-the-longer-token.md |
| 52 | demoted 2026-09-06 from MEMORY.md to MEMORY_ARCHIVE_2026-H2-COLD.md; the rule | INDEX | situational | none | docs/lessons/INDEX.md § Detectors, alarms and state -> mem/null-result-must-not-use-the-error-channel.md |
| 53 | demoted 2026-09-06 from MEMORY.md to MEMORY_ARCHIVE_2026-H2-COLD.md; the rule | INDEX | situational | none | docs/lessons/INDEX.md § Measurement and evidence -> mem/force-decorrelation-when-the-fit-cannot.md |
| 54 | demoted 2026-09-06 from MEMORY.md to MEMORY_ARCHIVE_2026-H2-COLD.md; the rule | INDEX | situational | none | docs/lessons/INDEX.md § Backlog rows, falsifiers and stranded work -> mem/work-item-next-step-inherits-its-stores-half-life.md |
| 55 | demoted 2026-09-06 from MEMORY.md to MEMORY_ARCHIVE_2026-H2-COLD.md; the rule | INDEX | situational | none | docs/lessons/INDEX.md § Shell and scripting -> mem/recursive-grep-cannot-walk-the-symlink-layer.md |
| 56 | demoted 2026-09-06 from MEMORY.md to MEMORY_ARCHIVE_2026-H2-COLD.md; the rule | INDEX | situational | none | docs/lessons/INDEX.md § Tests, fixtures and controls -> mem/negated-assertion-dead-unless-final.md |
| 57 | demoted 2026-09-06 from MEMORY.md to MEMORY_ARCHIVE_2026-H2-COLD.md; the rule | INDEX | situational | none | docs/lessons/INDEX.md § Tests, fixtures and controls -> mem/file-hash-is-not-pixel-content.md |
| 58 | demoted 2026-09-06 from MEMORY.md to MEMORY_ARCHIVE_2026-H2-COLD.md; the rule | INDEX | situational | none | docs/lessons/INDEX.md § Shell and scripting -> mem/absent-range-endpoint-selects-everything.md |
| 59 | demoted 2026-09-06 from MEMORY.md to MEMORY_ARCHIVE_2026-H2-COLD.md; the rule | INDEX | situational | none | docs/lessons/INDEX.md § Land, /ship, gates and the live layer -> mem/gate-scope-from-git-diff-is-blind-to-untracked.md |
| 60 | demoted 2026-09-06 from MEMORY.md to MEMORY_ARCHIVE_2026-H2-COLD.md; the rule | INDEX | situational | none | docs/lessons/INDEX.md § Land, /ship, gates and the live layer -> mem/cited-sha-may-not-survive-the-land.md |
| 61 | demoted 2026-09-06 from MEMORY.md to MEMORY_ARCHIVE_2026-H2-COLD.md; the rule | INDEX | situational | none | docs/lessons/INDEX.md § Processes, liveness and time -> mem/process-start-time-renders-in-ambient-timezone.md |
| 62 | Stub quoting fails open — a JSON fixture | INDEX | situational | none | docs/lessons/INDEX.md § Tests, fixtures and controls -> mem/fixture-stub-cannot-carry-an-apostrophe.md |
| 63 | 2026-09-08 · MEMORY.md index is at its hard | INDEX | situational | none | docs/lessons/INDEX.md § Detectors, alarms and state -> mem/checker-population-rests-on-an-untested-belief.md |
| 64 | Dialog names its config file — a dialog | INDEX | situational | none | docs/lessons/INDEX.md § Sessions, fires, panes and permissions -> mem/dialog-names-its-config-file-not-its-subject.md |
| 65 | Requested rate ≠ delivered rate — a cadence | INDEX | situational | none | docs/lessons/INDEX.md § Measurement and evidence -> docs/lessons/requested-rate-is-not-delivered-rate.md |
| 66 | Never wrap /ship in your own timeout — | RESIDENT | env-fact | none | C7.slim.md § Landing and shared worktrees (rewritten) |
| 67 | Cause refuted ≠ effect discharged — an item | INDEX | situational | none | docs/lessons/INDEX.md § Backlog rows, falsifiers and stranded work -> docs/lessons/cause-refuted-effect-discharged.md |
| 68 | 2026-09-08 · MEMORY.md is at its hard cap, | INDEX | situational | none | docs/lessons/INDEX.md § Measurement and evidence -> mem/subject-reads-its-own-path-and-its-own-output.md |
| 69 | Correction inherits the burden — Refuting an OBJECTION | INDEX | situational | none | docs/lessons/INDEX.md § Measurement and evidence -> docs/lessons/correction-inherits-the-claim-s-burden.md |
| 70 | Size refuted ≠ decision flipped — Re-measuring a | INDEX | situational | none | docs/lessons/INDEX.md § Measurement and evidence -> docs/lessons/size-refuted-decision-flipped.md |
| 71 | Gate must ease with evidence — for any | INDEX | situational | none | docs/lessons/INDEX.md § Measurement and evidence -> docs/lessons/gate-must-ease-with-evidence.md |
| 72 | Ship owns the tree — between firing /ship | RESIDENT | env-fact | none | C7.slim.md § Landing, shared worktrees and destructive actions (rewritten; general half "before deleting any directory, check which process was launched from it" restored after verify) |
| 73 | Fixture shape hides address bugs — when a | INDEX | situational | none | docs/lessons/INDEX.md § Tests, fixtures and controls -> docs/lessons/fixture-shape-hides-address-bugs.md |
| 74 | Census matches itself — a hand-rolled ps / | INDEX | situational | none | docs/lessons/INDEX.md § Processes, liveness and time -> docs/lessons/census-matches-itself.md |
| 75 | Launcher runs the live layer — a generated | INDEX | situational | none | docs/lessons/INDEX.md § Land, /ship, gates and the live layer -> docs/lessons/launcher-runs-the-live-layer.md |
| 76 | One-armed adjudication only convicts — asymmetric evidence can | INDEX | situational | none | docs/lessons/INDEX.md § Measurement and evidence -> docs/lessons/one-armed-adjudication-only-convicts.md |
| 77 | Gate refusal ≠ gate result — A gate | RESIDENT | env-fact | none | C7.slim.md § Landing and shared worktrees (rewritten) |
| 78 | DoD can demand what the cure removed — | INDEX | situational | none | docs/lessons/INDEX.md § Docs, corpora and plans -> docs/lessons/dod-can-demand-what-the-cure-removed.md |
| 79 | Inner bound starves the tail — when a | INDEX | situational | none | docs/lessons/INDEX.md § Detectors, alarms and state -> docs/lessons/inner-bound-outer-bound-starves-the-tail.md |
| 80 | Driver CPU ≠ pipeline progress — a shell | INDEX | situational | none | docs/lessons/INDEX.md § Processes, liveness and time -> docs/lessons/a-driver-shell-s-own-cpu-is-not-its-pipeline-s-progress.md |
| 82 | 2026-09-09 · six topic files were reachable from | DELETE | history | none | orphan-rescue narrative; its six nested lessons are labelled individually (L83-L88) |
| 83 | narrated-verdict-is-indistinguishable-from-a-computed-one.md — a conclusion you echo into a | RESIDENT | quirk-fix | none | C7.slim.md § Reasoning (rewritten); links its mem path, an exception the slim header now states |
| 84 | aggregate-correlation-refutes-the-obvious-cause.md — the postland reds look load-caused and | INDEX | situational | none | docs/lessons/INDEX.md § Measurement and evidence -> mem/aggregate-correlation-refutes-the-obvious-cause.md |
| 85 | fixture-identifier-shape-collapses-two-spaces.md — a fixture giving two disjoint production | DELETE | duplicate | none | same rule as L73 [Fixture shape hides address bugs]; its memory file is kept as a second link on L73's index line |
| 86 | predicate-refusal-is-not-a-negative.md — a predicate that REFUSES (wrong operand | DELETE | duplicate | none | same rule as MEMORY.md entry [Error exit = false] (predicate-error-exit-is-indistinguishable-from-false.md) |
| 87 | recheck-reads-the-line-not-its-operands.md — re-verifying a cited file:line does not | INDEX | situational | none | docs/lessons/INDEX.md § Measurement and evidence -> mem/recheck-reads-the-line-not-its-operands.md |
| 88 | transplanted-session-loses-dispatch-identity.md — a session transplanted or resumed into | DELETE | duplicate | none | same memory file and rule as L257 [Transplant loses dispatch identity] |
| 89 | Ratchet culprit is in its output — every | INDEX | situational | none | docs/lessons/INDEX.md § Land, /ship, gates and the live layer -> docs/lessons/a-ratchet-s-culprit-is-in-its-output-not-in-the-range.md |
| 90 | Empty vs no-surface — an emptiness gate over | INDEX | situational | none | docs/lessons/INDEX.md § Detectors, alarms and state -> docs/lessons/empty-vs-no-surface.md |
| 92 | <!-- routed 2026-09-09T13:08:59Z by cc-memory-rotate: 1 index line(s) | DELETE | history | none | cc-memory-rotate routing record |
| 93 | <!-- …and that line is NOT re-added here: | DELETE | history | bin/cc-memory-rotate route_veto already-cited | restore note for L40; the veto is in the rotor |
| 94 | Two runs may be one curve — two | INDEX | situational | none | docs/lessons/INDEX.md § Measurement and evidence -> docs/lessons/two-runs-disagreeing-may-be-one-curve.md |
| 95 | Optimistic round vs contention — A validate-unlocked/commit-locked retry | INDEX | situational | none | docs/lessons/INDEX.md § Land, /ship, gates and the live layer -> docs/lessons/optimistic-round-cannot-outrun-its-contention.md |
| 96 | Green in both arms — A case passing | INDEX | situational | none | docs/lessons/INDEX.md § Tests, fixtures and controls -> docs/lessons/green-in-both-arms-is-an-equivalence-guard-not-a-red-proof.md |
| 97 | Never-engaged is mostly false — a fire reporting | INDEX | situational | none | docs/lessons/INDEX.md § Sessions, fires, panes and permissions -> docs/lessons/a-never-engaged-verdict-is-mostly-false-and-its-real-cost-is-the.md |
| 98 | As-specified ≠ as-built — when an implementation deliberately | INDEX | situational | none | docs/lessons/INDEX.md § Measurement and evidence -> docs/lessons/as-specified-as-built.md |
| 99 | A deny is a turn boundary — a | INDEX | situational | none | docs/lessons/INDEX.md § Sessions, fires, panes and permissions -> docs/lessons/a-deny-is-the-turn-boundary-a-message-lacks.md |
| 100 | Empty selector is a universal selector — VAR=x | RESIDENT | quirk-fix | none | C7.slim.md § Landing, shared worktrees and destructive actions (promoted after verify F3: a kill loop over an empty selector is irreversible) |
| 102 | <!-- routed 2026-09-09T13:08:59Z by cc-memory-rotate: 1 index line(s) | DELETE | history | none | cc-memory-rotate routing record |
| 103 | Two producers, different cadences — A fresh beside | INDEX | situational | none | docs/lessons/INDEX.md § Detectors, alarms and state -> docs/lessons/two-producers-one-moment-different-cadences.md |
| 104 | Symlinked $0 splits siblings — A script invoked | INDEX | situational | none | docs/lessons/INDEX.md § Shell and scripting -> docs/lessons/symlinked-0-splits-sibling-sources.md |
| 105 | Shared-checkout commit blocks the fleet — A commit | INDEX | situational | hooks/validate-bash.sh:1425 denies `git commit` in the shared checkout (the rescue remains situational) | docs/lessons/INDEX.md § Land, /ship, gates and the live layer -> docs/lessons/shared-checkout-commit-blocks-the-fleet-and-skipped-the-gate.md |
| 106 | Mid-turn brief loses identity — fired-peer status is | INDEX | situational | none | docs/lessons/INDEX.md § Sessions, fires, panes and permissions -> docs/lessons/a-mid-turn-brief-is-invisible-to-the-fired-peer-detector.md |
| 107 | Closed vocabulary swallows a value — when you | INDEX | situational | none | docs/lessons/INDEX.md § Detectors, alarms and state -> docs/lessons/closed-vocabulary-swallows-an-unrecognized-value.md |
| 108 | A count in the title is a population | INDEX | situational | none | docs/lessons/INDEX.md § Backlog rows, falsifiers and stranded work -> docs/lessons/a-count-in-the-title-is-a-population-and-a-population-disposes-i.md |
| 109 | Bisect the test, not the suite — a | INDEX | situational | none | docs/lessons/INDEX.md § Measurement and evidence -> docs/lessons/a-bisect-s-predicate-must-be-the-convicted-test-not-its-suite.md |
| 110 | Probe the OLD binary too — a disagreement | INDEX | situational | none | docs/lessons/INDEX.md § Vendors, APIs and binaries -> docs/lessons/re-run-the-probe-on-the-old-binary-too.md |
| 111 | Freshness is subject-relative — Compare a liveness heartbeat | INDEX | situational | none | docs/lessons/INDEX.md § Detectors, alarms and state -> docs/lessons/freshness-is-relative-to-the-subject-not-the-clock.md |
| 112 | Reader must prove delivery — A consumer advancing | INDEX | situational | none | docs/lessons/INDEX.md § Detectors, alarms and state -> docs/lessons/a-reader-that-cannot-prove-delivery-must-not-consume.md |
| 113 | One dead class is not the last — | INDEX | situational | none | docs/lessons/INDEX.md § Tests, fixtures and controls -> docs/lessons/one-dead-assertion-class-found-is-not-the-last-one.md |
| 114 | Retiring ≠ recovering — retiring a cohort frees | INDEX | situational | none | docs/lessons/INDEX.md § Backlog rows, falsifiers and stranded work -> docs/lessons/retiring-a-population-is-not-recovering-its-work.md (reached via the slim pointer's "bulk-retire" trigger, added after verify F3) |
| 115 | Classify a quota fault by its error — | INDEX | situational | none | docs/lessons/INDEX.md § Vendors, APIs and binaries -> docs/lessons/a-quota-fault-is-classified-by-its-error-never-by-what-it-spent.md |
| 116 | Blocker isn't the standard — when two tools | INDEX | situational | none | docs/lessons/INDEX.md § Detectors, alarms and state -> docs/lessons/the-blocking-gate-was-stricter-than-the-repo-s-own-verifier.md |
| 117 | Aggregate control misses a per-member zero — a | INDEX | situational | none | docs/lessons/INDEX.md § Tests, fixtures and controls -> docs/lessons/aggregate-control-cannot-see-a-per-member-zero.md |
| 118 | Verify a cure under its load — A | INDEX | situational | none | docs/lessons/INDEX.md § Tests, fixtures and controls -> docs/lessons/a-cure-is-verified-only-under-the-load-that-caused-it.md |
| 119 | Pre-existing red is a claim — A branch's | INDEX | situational | none | docs/lessons/INDEX.md § Land, /ship, gates and the live layer -> docs/lessons/a-pre-existing-red-is-a-claim-not-a-measurement.md |
| 120 | Gate surface is not its traffic — a | INDEX | situational | none | docs/lessons/INDEX.md § Detectors, alarms and state -> docs/lessons/a-gate-s-surface-is-not-its-traffic.md |
| 121 | Cache key carrying a checkout path — a | INDEX | situational | none | docs/lessons/INDEX.md § Detectors, alarms and state -> docs/lessons/a-cache-key-carrying-a-checkout-path-never-carries.md |
| 122 | Dead first stage reads as no match — | INDEX | situational | none | docs/lessons/INDEX.md § Shell and scripting -> docs/lessons/a-dead-first-stage-reads-as-a-clean-no-match.md |
| 123 | Digit-guard zeroes the count — BSD wc -l | INDEX | situational | none | docs/lessons/INDEX.md § Shell and scripting -> docs/lessons/a-digit-guard-destroys-the-value-it-is-hardening.md |
| 124 | Allow rule cannot silence a hook — a | INDEX | situational | none | docs/lessons/INDEX.md § Sessions, fires, panes and permissions -> docs/lessons/an-allow-rule-cannot-silence-a-hook-s-ask.md |
| 125 | Ranker may price decay — A score that | INDEX | situational | none | docs/lessons/INDEX.md § Detectors, alarms and state -> docs/lessons/a-ranker-preferring-less-headroom-may-be-pricing-decay-not-headr.md |
| 127 | Witness tests the SET first — A detector | INDEX | situational | none | docs/lessons/INDEX.md § Detectors, alarms and state -> docs/lessons/witness-must-test-the-set-before-the-order.md |
| 128 | Closure rests on its premises — a "there | INDEX | situational | none | docs/lessons/INDEX.md § Measurement and evidence -> docs/lessons/closure-measured.md |
| 129 | In-process agent caps at 100 turns — an | RESIDENT | env-fact | none | C7.slim.md § Briefs, goals and filed rows (rewritten) |
| 132 | <!-- routed 2026-09-16T03:14:11Z by cc-memory-rotate: 19 index line(s) | DELETE | history | none | cc-memory-rotate routing record |
| 133 | Display ≠ decision — last-good rescued the DISPLAY, | INDEX | situational | none | docs/lessons/INDEX.md § Detectors, alarms and state -> mem/degraded-path-restores-display-not-the-decision.md |
| 134 | One dir ≠ installed — 3 dirs symlink | INDEX | situational | none | docs/lessons/INDEX.md § Land, /ship, gates and the live layer -> mem/install-verified-in-one-config-dir-is-not-installed.md |
| 135 | SSOT dies at the splicer — a chain | INDEX | situational | none | docs/lessons/INDEX.md § Backlog rows, falsifiers and stranded work -> mem/ssot-edit-dies-when-the-regeneration-path-reads-the-predecessor.md |
| 136 | Render vs predicate — a floored value feeding | INDEX | situational | none | docs/lessons/INDEX.md § Detectors, alarms and state -> mem/rendering-transform-feeding-a-predicate.md |
| 137 | Worktree bares the checkout — worktree add/remove can | INDEX | situational | scripts/deploy-live.sh:1672 heals core.bare=true on the shared checkout | docs/lessons/INDEX.md § Land, /ship, gates and the live layer -> mem/worktree-ops-can-bare-the-shared-checkout.md |
| 138 | Alarm names wrong producer — its remedy line | INDEX | situational | none | docs/lessons/INDEX.md § Detectors, alarms and state -> mem/alarm-attribution-names-the-wrong-producer.md |
| 139 | Cheap entrance, no exit — a state no | INDEX | situational | none | docs/lessons/INDEX.md § Backlog rows, falsifiers and stranded work -> mem/parking-state-cheap-entrance-no-exit.md |
| 140 | Reachable ≠ caused — ship-land blames the lander | INDEX | situational | none | docs/lessons/INDEX.md § Land, /ship, gates and the live layer -> mem/gate-attributes-by-reachability-not-causation.md |
| 141 | Rail fix is per-worktree — sessions run their | INDEX | situational | none | docs/lessons/INDEX.md § Land, /ship, gates and the live layer -> mem/rail-fix-propagates-per-worktree.md |
| 142 | Registration needs version — a -x guard passes | INDEX | situational | none | docs/lessons/INDEX.md § Land, /ship, gates and the live layer -> mem/registration-precondition-must-assert-version-not-executability.md |
| 143 | Recovery needs hysteresis — one healthy sample re-arming | INDEX | situational | none | docs/lessons/INDEX.md § Detectors, alarms and state -> mem/recovery-path-must-be-hysteretic.md |
| 144 | Name enlists you — a gate globbing *redproof* | INDEX | situational | none | docs/lessons/INDEX.md § Tests, fixtures and controls -> mem/filename-glob-conscripts-into-a-sibling-gate.md |
| 145 | Burst vs aggregate — a daily rate hides | INDEX | situational | none | docs/lessons/INDEX.md § Measurement and evidence -> mem/aggregate-window-averages-the-burst-away.md |
| 146 | Clean ≠ never worked — a dark peer | INDEX | situational | none | docs/lessons/INDEX.md § Sessions, fires, panes and permissions -> mem/clean-worktree-cannot-distinguish-never-worked-from-landed.md |
| 147 | Presence ≠ content — 3 arms enforced one | INDEX | situational | none | docs/lessons/INDEX.md § Detectors, alarms and state -> mem/gate-on-presence-is-cleared-by-any-string.md |
| 148 | Empty join key — approved 0 of 3,763 | INDEX | situational | none | docs/lessons/INDEX.md § Measurement and evidence -> mem/join-key-never-populated-makes-a-rule-unreachable.md |
| 149 | Helper position bounds reach — a helper defined | INDEX | situational | none | docs/lessons/INDEX.md § Shell and scripting -> mem/helper-position-bounds-a-fixs-reach.md |
| 150 | Fire verdict ≠ peer state — a FIRE | INDEX | situational | none | docs/lessons/INDEX.md § Sessions, fires, panes and permissions -> mem/dispatcher-verdict-is-not-the-fired-sessions-state.md |
| 151 | Runner states its gaps — a harness may | INDEX | situational | none | docs/lessons/INDEX.md § Tests, fixtures and controls -> mem/harness-reports-its-own-incompleteness.md |
| 152 | Bisect the band, never divide the deltas — | INDEX | situational | none | docs/lessons/INDEX.md § Measurement and evidence -> docs/lessons/bisect-the-band-never-divide-the-deltas.md |
| 153 | Bundle verify reads its own repo — bundle | INDEX | situational | none | docs/lessons/INDEX.md § Land, /ship, gates and the live layer -> docs/lessons/bundle-verify-passes-on-a-bundle-that-cannot-be-cloned.md |
| 154 | Subagent cannot answer a prompt — a subagent | RESIDENT | env-fact | none | C7.slim.md § Briefs, goals and filed rows (rewritten) |
| 155 | Probe writes into a live session — "Read-only" | RESIDENT | quirk-fix | none | C7.slim.md § Briefs, goals and filed rows (rewritten) |
| 156 | Perishable input sets urgency — Schedule position is | INDEX | situational | none | docs/lessons/INDEX.md § Backlog rows, falsifiers and stranded work -> docs/lessons/perishable-input-is-what-makes-a-wave-urgent.md |
| 157 | Insertions break line citations — inserting lines into | INDEX | situational | none | docs/lessons/INDEX.md § Docs, corpora and plans -> docs/lessons/a-record-correction-wave-breaks-the-record.md |
| 158 | Formatter sized by the vendored tree — a | INDEX | situational | none | docs/lessons/INDEX.md § Land, /ship, gates and the live layer -> docs/lessons/a-whole-tree-formatter-is-sized-by-the-vendored-tree-not-by-your.md |
| 159 | A stale pid is re-aimed, not defused — | INDEX | situational | none | docs/lessons/INDEX.md § Processes, liveness and time -> docs/lessons/a-stale-pid-does-not-decay-into-harmlessness-it-decays-into-a-gu.md |
| 160 | The screen is global — a sandbox holds | INDEX | situational | none | docs/lessons/INDEX.md § Sessions, fires, panes and permissions -> docs/lessons/a-synthetic-input-event-has-no-sandbox-the-screen-is-global.md |
| 161 | Crash-dump memory fields are derived — a dump's | INDEX | situational | none | docs/lessons/INDEX.md § Processes, liveness and time -> docs/lessons/a-crash-dump-s-memory-fields-are-derived-check-their-arithmetic.md |
| 162 | Binary-only names your layer — "This needs a | INDEX | situational | none | docs/lessons/INDEX.md § Vendors, APIs and binaries -> docs/lessons/binary-only-is-a-property-of-the-layer-you-looked-at.md |
| 163 | Clean nulls can be one conjunction — When | INDEX | situational | none | docs/lessons/INDEX.md § Measurement and evidence -> docs/lessons/clean-nulls-can-be-one-conjunction.md |
| 164 | Anchor on the killing event — a triage | INDEX | situational | none | docs/lessons/INDEX.md § Processes, liveness and time -> docs/lessons/a-crash-anchor-must-be-the-event-that-killed-the-subject-not-the.md |
| 165 | Draggable pane title is primary — OPERATOR RULING, | RESIDENT | mode-rule | none | C7.slim.md § Standing operator rulings (promoted after verify F4: standing prohibition, no hook enforces it) |
| 166 | Kill the leaf, not the wrapper — a | INDEX | situational | none | docs/lessons/INDEX.md § Processes, liveness and time -> docs/lessons/kill-the-leaf-not-the-wrapper-and-the-orphan-keeps-blocking.md |
| 167 | 0 bytes is not death — for any | INDEX | situational | none | docs/lessons/INDEX.md § Processes, liveness and time -> docs/lessons/a-0-byte-output-file-is-not-a-dead-process-it-is-a-process-that.md |
| 168 | A filed row carries the burden — a | INDEX | situational | none | docs/lessons/INDEX.md § Backlog rows, falsifiers and stranded work -> docs/lessons/a-row-you-file-carries-the-same-burden-as-a-row-you-drive-and-on.md |
| 169 | Enumerate the generator's copies — When the generator | INDEX | situational | none | docs/lessons/INDEX.md § Backlog rows, falsifiers and stranded work -> docs/lessons/a-generator-fix-needs-its-population-enumerated-and-the-incident.md |
| 171 | Clause splitter claims every separator — A guard | INDEX | situational | none | docs/lessons/INDEX.md § Shell and scripting -> docs/lessons/a-clause-splitter-is-a-claim-about-every-separator-the-shell-has.md |
| 172 | Hardcoded pid is no constant — a fixture's | INDEX | situational | none | docs/lessons/INDEX.md § Tests, fixtures and controls -> docs/lessons/a-fixture-s-pid-range-is-a-claim-about-a-shared-wrapping-namespa.md |
| 173 | Superseded ≠ stranded — a re-land row's falsifier | INDEX | situational | none | docs/lessons/INDEX.md § Backlog rows, falsifiers and stranded work -> docs/lessons/superseded-stranded-and-the-falsifier-cannot-tell-them-apart.md |
| 174 | Falsifier inherits its store — a self-retracting work | INDEX | situational | none | docs/lessons/INDEX.md § Backlog rows, falsifiers and stranded work -> docs/lessons/a-falsifier-resting-on-a-frozen-pointer-is-inert-and-inertness-r.md |
| 175 | Re-dispatch indicts the dispatcher — a row that | INDEX | situational | none | docs/lessons/INDEX.md § Backlog rows, falsifiers and stranded work -> docs/lessons/a-re-dispatch-loop-is-evidence-about-the-dispatcher-not-about-th.md |
| 176 | Forward acquittal cannot reach the row — postland | INDEX | situational | none | docs/lessons/INDEX.md § Land, /ship, gates and the live layer -> docs/lessons/a-conviction-and-its-forward-acquittal-live-in-two-stores-and-on.md |
| 177 | Overflow surface needs a tier — a relief | INDEX | situational | none | docs/lessons/INDEX.md § Detectors, alarms and state -> docs/lessons/overflow-surface-with-no-tier-below-it.md |
| 178 | Unrun arm goes in the verdict — when | INDEX | situational | none | docs/lessons/INDEX.md § Measurement and evidence -> docs/lessons/a-probe-s-unrun-arm-belongs-in-the-verdict-line.md |
| 179 | Cost premise is per-ARM — before filing a | INDEX | situational | none | docs/lessons/INDEX.md § Vendors, APIs and binaries -> docs/lessons/a-cost-premise-is-per-arm-and-is-usually-false.md |
| 180 | Arming ≠ mootness — a --falsifier field means | RESIDENT | env-fact | cc-backlog closes a row when its falsifier exits 0 (the mechanism, not a guard) | C7.slim.md § Briefs, goals and filed rows (rewritten) |
| 181 | Appended redirect binds to the fallback — a | INDEX | situational | none | docs/lessons/INDEX.md § Tests, fixtures and controls -> docs/lessons/an-appended-redirect-binds-only-to-the-fallback.md |
| 182 | Falsifier keyed on a symbol — a probe | INDEX | situational | none | docs/lessons/INDEX.md § Processes, liveness and time -> docs/lessons/a-falsifier-keyed-on-a-symbol-name-is-blind-to-the-stripped-build.md |
| 183 | Crippled credential can't price — a zero-limit key | INDEX | situational | none | docs/lessons/INDEX.md § Vendors, APIs and binaries -> docs/lessons/zero-limit-credential-cannot-measure-free.md |
| 184 | Red on your file ≠ red on your | INDEX | situational | none | docs/lessons/INDEX.md § Land, /ship, gates and the live layer -> docs/lessons/gate-red-on-a-file-your-diff-touches-is-not-a-red-on-your-diff.md |
| 185 | Hermeticity ends at the third tool — a | INDEX | situational | none | docs/lessons/INDEX.md § Tests, fixtures and controls -> docs/lessons/a-fixture-s-hermeticity-ends-where-its-subject-spawns-a-third-tool.md |
| 186 | Counter lag transplants the delta — an async | INDEX | situational | none | docs/lessons/INDEX.md § Measurement and evidence -> docs/lessons/eventually-consistent-counter-transplants-the-delta.md |
| 187 | Distillation drops the dispatch table — porting a | INDEX | situational | none | docs/lessons/INDEX.md § Docs, corpora and plans -> docs/lessons/distillation-drops-what-the-tool-dispatches-on.md |
| 188 | Wrapper renames your timeout — a client that | INDEX | situational | none | docs/lessons/INDEX.md § Vendors, APIs and binaries -> docs/lessons/a-wrapper-renames-your-own-timeout-into-a-foreign-fault.md |
| 189 | Free price ≠ free throughput — a promo | INDEX | situational | none | docs/lessons/INDEX.md § Vendors, APIs and binaries -> docs/lessons/free-pricing-is-not-free-throughput.md |
| 190 | Read-only surface holds no state — a checkout | INDEX | situational | none | docs/lessons/INDEX.md § Land, /ship, gates and the live layer -> docs/lessons/a-read-only-surface-must-not-be-able-to-hold-state.md |
| 191 | Deployment interpreter ≠ yours — #!/usr/bin/env bash resolves | RESIDENT | env-fact | none (scripts/bash32-parse-lint.sh covers parse errors only) | C7.slim.md § Landing, shared worktrees and destructive actions (rewritten; CI restored after verify) |
| 192 | Summed ps%CPU ≠ utilization — ps pcpu is | INDEX | situational | none | docs/lessons/INDEX.md § Processes, liveness and time -> docs/lessons/summed-per-process-cpu-is-not-system-utilization.md |
| 193 | Two modes n hours apart is a timezone | INDEX | situational | none | docs/lessons/INDEX.md § Measurement and evidence -> docs/lessons/two-modes-n-hours-apart-is-a-timezone.md |
| 194 | Cold fire duplicates under load — a load-scaled | INDEX | situational | none | docs/lessons/INDEX.md § Sessions, fires, panes and permissions -> docs/lessons/cold-fire-under-load-duplicates-the-session.md |
| 195 | Partial evaluation reads as complete — a past | INDEX | situational | none | docs/lessons/INDEX.md § Measurement and evidence -> docs/lessons/a-prior-partial-evaluation-reads-as-a-completed-one.md |
| 196 | Gate names a different suite each run — | INDEX | situational | none | docs/lessons/INDEX.md § Land, /ship, gates and the live layer -> docs/lessons/a-phase-budget-cut-names-a-different-suite-each-run.md |
| 197 | Land gate is admission-exempt — ship-land runs its | INDEX | situational | none | docs/lessons/INDEX.md § Land, /ship, gates and the live layer -> docs/lessons/the-land-gate-is-admission-exempt.md |
| 198 | Non-interactive shell cannot spawn a teammate — CC | INDEX | situational | none | docs/lessons/INDEX.md § Sessions, fires, panes and permissions -> docs/lessons/a-non-interactive-shell-cannot-spawn-a-named-teammate.md |
| 199 | Engaged ≠ running — a fresh non-error assistant | INDEX | situational | none | docs/lessons/INDEX.md § Sessions, fires, panes and permissions -> docs/lessons/engaged-is-not-running.md |
| 200 | Imported threshold can be unreachable — a threshold | INDEX | situational | none | docs/lessons/INDEX.md § Tests, fixtures and controls -> docs/lessons/an-imported-threshold-can-sit-above-the-model-s-output-range.md |
| 201 | Keep-both on appended blocks — two sides APPENDING | INDEX | situational | none | docs/lessons/INDEX.md § Land, /ship, gates and the live layer -> docs/lessons/keep-both-on-appended-blocks-leaves-the-first-unterminated.md |
| 202 | Lead can't exit unattended — /exit on a | INDEX | situational | none | docs/lessons/INDEX.md § Sessions, fires, panes and permissions -> docs/lessons/a-lead-with-live-teammates-cannot-exit-unattended.md |
| 203 | Remote pane identity is the target's — an | INDEX | situational | none | docs/lessons/INDEX.md § Sessions, fires, panes and permissions -> docs/lessons/remote-pane-identity-is-the-targets-not-the-drivers.md |
| 204 | Control arm ≠ deliverable — ship-land mints a | INDEX | situational | none | docs/lessons/INDEX.md § Land, /ship, gates and the live layer -> docs/lessons/control-arm-is-not-a-deliverable.md |
| 205 | Red may belong to the box — a | INDEX | situational | none | docs/lessons/INDEX.md § Land, /ship, gates and the live layer -> docs/lessons/a-suite-red-can-belong-to-the-box-not-the-branch.md |
| 206 | Own-scope gate misses a counted pin — a | INDEX | situational | none | docs/lessons/INDEX.md § Land, /ship, gates and the live layer -> docs/lessons/own-scope-gate-is-blind-to-a-counted-pin-elsewhere.md |
| 207 | Nth source un-seals old fixtures — giving a | INDEX | situational | none | docs/lessons/INDEX.md § Tests, fixtures and controls -> docs/lessons/nth-fallback-source-un-seals-old-fixtures.md |
| 208 | Clean+landed ≠ nothing in hand — an advisory | INDEX | situational | none | docs/lessons/INDEX.md § Sessions, fires, panes and permissions -> docs/lessons/git-clean-is-not-nothing-in-hand.md |
| 209 | Escape legality is the consumer's call — a | INDEX | situational | none | docs/lessons/INDEX.md § Shell and scripting -> docs/lessons/a-locale-pin-protects-only-the-process-that-sets-it.md |
| 210 | Soft reset onto a moved ref reverts — | RESIDENT | quirk-fix | none | C7.slim.md § Landing and shared worktrees (rewritten) |
| 211 | Landed ≠ tested — ship-land SHEDS its smoke | RESIDENT | env-fact | none | C7.slim.md § Landing and shared worktrees (rewritten) |
| 212 | Own records ≠ the world — three negative | RESIDENT | quirk-fix | none | C7.slim.md § Reasoning (rewritten) |
| 213 | Two causes, one rc — when a client | INDEX | situational | none | docs/lessons/INDEX.md § Processes, liveness and time -> docs/lessons/two-causes-one-rc-ask-a-lower-layer.md |
| 214 | Remedy inherits the standing property — a transient | INDEX | situational | none | docs/lessons/INDEX.md § Processes, liveness and time -> docs/lessons/a-transient-fault-is-explained-by-whatever-was-standing.md |
| 215 | Turn adjacency ≠ elapsed time — a model | RESIDENT | quirk-fix | none | C7.slim.md § Reasoning (rewritten) |
| 216 | Poll period charged as a floor — while | INDEX | situational | none | docs/lessons/INDEX.md § Processes, liveness and time -> docs/lessons/poll-period-charged-as-a-cost-floor.md |
| 217 | bash 3.2 counts parens in a heredoc — | INDEX | situational | scripts/bash32-parse-lint.sh via tests/bash32-parse-lint.bats | docs/lessons/INDEX.md § Shell and scripting -> docs/lessons/bash-32-counts-parens-inside-a-heredoc-it-never-runs.md |
| 218 | Control anchors on source text — a test | INDEX | situational | none | docs/lessons/INDEX.md § Tests, fixtures and controls -> docs/lessons/a-mutation-control-anchors-on-the-subjects-source-text.md |
| 219 | Alarm describes its tier — a status tool | INDEX | situational | none | docs/lessons/INDEX.md § Land, /ship, gates and the live layer -> docs/lessons/an-alarm-describes-the-tier-it-measures-not-the-whole-ladder.md |
| 220 | Correction must cover every spelling — a budget | INDEX | situational | none | docs/lessons/INDEX.md § Measurement and evidence -> docs/lessons/a-path-length-correction-must-cover-every-spelling.md |
| 221 | Mirroring ≠ using — fetching, measuring and wrapping | INDEX | situational | none | docs/lessons/INDEX.md § Docs, corpora and plans -> docs/lessons/mirroring-a-corpus-is-not-using-it.md |
| 222 | "Only these" hides artifacts — "use ONLY these | INDEX | situational | none | docs/lessons/INDEX.md § Docs, corpora and plans -> docs/lessons/a-spec-that-forbids-invention-names-artifacts-a-crawl-will-miss.md |
| 223 | Census misses the owner — a wave lead | RESIDENT | env-fact | none | C7.slim.md § Landing and shared worktrees (rewritten) |
| 224 | Empty TSV cells vanish — TAB is IFS | INDEX | situational | none | docs/lessons/INDEX.md § Shell and scripting -> docs/lessons/tab-is-ifs-whitespace-so-empty-tsv-cells-vanish.md |
| 225 | Ratchet cures one verb — a ratchet's SCOPE | INDEX | situational | none | docs/lessons/INDEX.md § Tests, fixtures and controls -> docs/lessons/a-ratchet-cures-one-verb-of-a-two-verb-class.md |
| 226 | Saturated rubric ranked nothing — a question returning | INDEX | situational | none | docs/lessons/INDEX.md § Measurement and evidence -> docs/lessons/a-rubric-that-saturates-has-not-ranked-anything.md |
| 227 | Mock output is indistinguishable — a run against | INDEX | situational | none | docs/lessons/INDEX.md § Tests, fixtures and controls -> docs/lessons/a-test-double-s-output-is-indistinguishable-in-a-shared-store.md |
| 228 | Unreachable goal never clears — a /goal conjunct | RESIDENT | env-fact | none | C7.slim.md § Briefs, goals and filed rows (rewritten) |
| 229 | Gate invocation is contract — the land gate | RESIDENT | env-fact | none | C7.slim.md § Landing, shared worktrees and destructive actions (rewritten; "grep a gate for its literal command before checking locally" and ship-land.sh:3258 restored after verify) |
| 230 | shift N past the end wedges — shift | INDEX | situational | none | docs/lessons/INDEX.md § Shell and scripting -> docs/lessons/shift-n-past-the-end-is-a-no-op-that-wedges-an-argv-loop.md |
| 232 | Shebang-less stub seals only bash — bash runs | INDEX | situational | none | docs/lessons/INDEX.md § Tests, fixtures and controls -> docs/lessons/a-shebang-less-stub-seals-only-the-shell-arm.md |
| 233 | Verdict keyed off-trunk — a verdict store keyed | INDEX | situational | none | docs/lessons/INDEX.md § Land, /ship, gates and the live layer -> docs/lessons/verdict-store-keyed-on-shas-the-subject-never-carried.md |
| 234 | Self-report counts every writer — a before/after delta | INDEX | situational | none | docs/lessons/INDEX.md § Measurement and evidence -> docs/lessons/a-self-report-counting-a-shared-store-counts-every-writer.md |
| 235 | Integration manufactures contradictions — review fixes applied as | INDEX | situational | none | docs/lessons/INDEX.md § Docs, corpora and plans -> docs/lessons/integrating-review-findings-by-local-edits-manufactures-contradictions.md |
| 236 | systemMessage accepts SGR — the harness paints a | INDEX | situational | none | docs/lessons/INDEX.md § Sessions, fires, panes and permissions -> docs/lessons/sessionstart-systemmessage-accepts-sgr.md |
| 237 | Scraped URL excludes control chars — \S matches | INDEX | situational | none | docs/lessons/INDEX.md § Shell and scripting -> docs/lessons/scraped-url-must-exclude-control-characters.md |
| 238 | Door cannot admit the already-satisfied — a gate | INDEX | situational | none | docs/lessons/INDEX.md § Backlog rows, falsifiers and stranded work -> docs/lessons/a-validate-on-attach-door-cannot-admit-the-already-satisfied.md |
| 239 | Retry budget counts sends — a retry budget | INDEX | situational | none | docs/lessons/INDEX.md § Detectors, alarms and state -> docs/lessons/retry-budget-counts-actions-not-looks.md |
| 240 | Directive ≠ endpoint — a framework directive's reach | INDEX | situational | none | docs/lessons/INDEX.md § Measurement and evidence -> docs/lessons/directive-implies-endpoint-is-a-build-graph-claim.md |
| 242 | <!-- routed 2026-09-22T23:33:21Z by cc-memory-rotate: 15 index line(s) | DELETE | history | none | cc-memory-rotate routing record |
| 243 | Remedies don't compose — a case failing TWO | INDEX | situational | none | docs/lessons/INDEX.md § Detectors, alarms and state -> mem/remedial-classes-may-not-compose.md |
| 244 | Clear must match occurrence — clearing on the | INDEX | situational | none | docs/lessons/INDEX.md § Detectors, alarms and state -> mem/resolution-signal-must-match-the-occurrence.md |
| 245 | Cure races its cause — a repair sharing | INDEX | situational | none | docs/lessons/INDEX.md § Detectors, alarms and state -> mem/self-repair-shares-a-lock-with-the-fault.md |
| 246 | Process count ≠ work count — ps/grep -c | INDEX | situational | none | docs/lessons/INDEX.md § Processes, liveness and time -> mem/process-count-is-not-a-count-of-the-work.md |
| 247 | Absent ≠ deleted — a file missing from | INDEX | situational | none | docs/lessons/INDEX.md § Backlog rows, falsifiers and stranded work -> mem/absent-from-trunk-has-two-opposite-causes.md |
| 248 | Rename defeats superset — disjoint symbol sets read | INDEX | situational | none | docs/lessons/INDEX.md § Backlog rows, falsifiers and stranded work -> mem/identifier-superset-test-is-defeated-by-a-rename.md |
| 249 | Sweep-hosted actuator — a 65-min unit in a | INDEX | situational | none | docs/lessons/INDEX.md § Detectors, alarms and state -> mem/sweep-hosted-actuator-cannot-exceed-its-tick.md |
| 250 | Stale tree fakes drift — a checker reading | INDEX | situational | none | docs/lessons/INDEX.md § Detectors, alarms and state -> mem/drift-checker-indicts-its-own-tree.md (remedy corrected after verify to the body's: state the behind-count, read `git show origin/main:<path>`) |
| 251 | Marker adjacency — code wedged between a gate_bounded:/noqa-class | INDEX | situational | none | docs/lessons/INDEX.md § Tests, fixtures and controls -> mem/marker-adjacency-is-part-of-its-meaning.md |
| 252 | Ref may be pre-fix — "lines only in | INDEX | situational | none | docs/lessons/INDEX.md § Backlog rows, falsifiers and stranded work -> mem/stranded-ref-may-be-the-pre-fix-form.md |
| 253 | Env can falsify a precondition — a red-proof | INDEX | situational | none | docs/lessons/INDEX.md § Tests, fixtures and controls -> mem/environment-falsifiable-precondition-must-skip.md |
| 254 | Re-run the falsification — a design that falsified | INDEX | situational | none | docs/lessons/INDEX.md § Tests, fixtures and controls -> mem/composed-remedy-must-rerun-the-original-falsification.md |
| 255 | Symlinked store invisible — BSD find skips a | INDEX | situational | none | docs/lessons/INDEX.md § Shell and scripting -> mem/symlinked-store-invisible-to-find.md |
| 256 | Disjoint all-or-nothing — two proofs each over ALL | INDEX | situational | none | docs/lessons/INDEX.md § Measurement and evidence -> mem/all-or-nothing-proofs-over-disjoint-halves.md |
| 257 | Transplant loses dispatch identity — a resumed/transplanted pane | INDEX | situational | none | docs/lessons/INDEX.md § Sessions, fires, panes and permissions -> mem/transplanted-session-loses-dispatch-identity.md |
| 258 | Unexercised session decays — a logged-in surface only | INDEX | situational | none | docs/lessons/INDEX.md § Sessions, fires, panes and permissions -> docs/lessons/an-unexercised-session-decays-route-through-the-one-the-human-uses.md |

## What moved where

| Destination | What it now holds (from which chunk) | Loaded when |
|---|---|---|
| `~/Development/claude-infrastructure/CLAUDE.global.md` (the full file, unchanged) | Every DELETE row whose destination reads "reference", "REF" or "full file": history, incidents, measurements, price and benchmark narrative, Stop-hook output-field semantics (C1-C6) | On demand; the slim header and pointers in Session Close Protocol say when |
| skill coding-standards | Stack, language, style and naming conventions (C1) | Writing or reviewing code in those stacks |
| skill plan-conventions | Plan-document conventions, Phase 0, execution locus (C1, C2) | Creating or editing a plan, design or roadmap doc |
| hook `backup-before-write.sh` message | OVERWRITE GUARD text, backup path, `restore-file.sh` command (C1) | On a Write to an existing file |
| skill agent-teams | Spawn API by runtime, pre-spawn checklist detail, sizing, lifecycle, shutdown, crash recovery (C2) | Before spawning a teammate |
| skill research-subagents | Depth target, decomposition artifact, brief fields, OASIS stop, synthesis rules (C2) | Before a research wave |
| hook `validate-bash.sh` refusal | "Not deaf without the watcher" detail for a backgrounded park under a live goal (C2) | On the refused call; one sentence also kept inline |
| `~/.claude/commands/handoff.md` | Goal template and exceptions, waves, recycle into a new worktree or account (C2, C4) | Firing a session; choosing recycle vs handoff |
| skill frontier-routing | `/frontier-hole`, `/frontier-run`, `/frontier-campaign`, standing duties, per-slot routing (C3) | Choosing a model tier, hitting a wall, wrap-up with open holes |
| skill outbound-drafting; hook `enforce-email-formatting.py` recipe | Drafting rules for messages the operator sends; ms365 turn-boundary mechanics (C3) | Before a draft; at the first mail call and on each refusal |
| `~/.claude/commands/wrap.md` § Read the rung, then act on it | LIVE_ADDS: an added file gets no converge budget (C4) | When a 🚀 needs reading |
| skill manual-command-delivery | The full hand-off rule and its history (C6 part 1) | Before asking the user to run anything |
| `docs/lessons/user-rules-dir-loads-in-every-invocation-mode.md` (staged in `audit/C6.staged/`) | The rules essay, verbatim, plus its one general lesson (C6 part 2) | On demand |
| `cc-mission next` / `cc-mission show <id>` | Each mission-board row's full `next` text (C6 part 3) | Before acting on a row |
| `scripts/deploy-live.sh` header; `.claude/settings.json` `_why_converge` | Converge rationale and the permission measurements (C6 part 4) | When changing the converge rules |
| `docs/lessons/INDEX.md` (proposed; content in `C7.index.md`) | 185 lesson lines grouped by topic, plus the rules-file ceilings note (C7) | Before diagnosing a failing test, gate, hook, land or fired session, or designing a detector, fixture, gate or measurement (the slim file lists the triggers) |
