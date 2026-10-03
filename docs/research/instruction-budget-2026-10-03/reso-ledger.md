# reso-ledger: splitting `.claude/rules/bottle-generation-ledger.md`

Slug: reso-ledger. Read-only investigation. The only files written are under `/tmp/ibudget/`:
this report, `reso-ledger-head.proposed.md` (the proposed always-loaded head) and
`fire_scan.py` (the transcript scanner).
Repo: `/Users/chrisren/Development/reso-management-app` (R below). The ledger is
`R/.claude/rules/bottle-generation-ledger.md` (L below).

## 1. What the file is (measured)

- Size: `wc -c -l L` gives 153,279 bytes and 2,337 lines. `python3 len(read())` gives **151,742 chars**,
  which matches the warning's "151.7k".
- It has no `paths:` frontmatter (line 1 is a markdownlint comment), so it is always loaded as
  Project memory in every session whose cwd is R or one of its worktrees.
- Growth (`git show <c>:L | wc -c` at sampled commits): 7,522 bytes (a9d1eedc3, 09-13), 30,632
  (09-14), 67,671 (09-21), 93,214 (09-22), 112,369 (09-24), 126,966 (09-27), 140,289 (09-28),
  153,279 (9a985f3c3, 09-29). That is about +8.5k/day over 17 days.
- Cadence: `git log --format='%h %ad %s' --date=iso -- L` shows **69 commits from 2026-09-13 to 09-29**.
  Per day: 2, 14, 3, 7, 8, 3, 8, 4, 6, 8, 6. Every one is a `docs(bottles)`/`feat(bottles)` round
  write-up. The last commit is 9a985f3c3, 2026-09-29 20:18 -0500.
- Earlier cost measurement: claude-infrastructure
  `docs/research/token-efficiency-2026-09-23/measure/static-prefix.md:57` measured the file at
  102,885 chars = **43.3k tokens**. At today's 151,742 chars the same ratio gives about
  **64k tokens** (estimated by linear scaling). That is paid at session start, and on every
  post-compaction reload, by every reso session.
- Who actually uses it (measured, by a python scan of top-level `*.jsonl` in every
  `~/.claude*/projects/*` with mtime ≥ 2026-09-13 and the ledger in its loaded instructions):
  **177 main transcripts loaded it, and only 25 of them (14%) made a tool call touching
  bottle generation or review** (patterns `bottle-gen-production|review:bottles|bottle-image-review|bottle-photography|bottle-generation-ledger|bottle-catalog`).
  So about 86% of the sessions paying for it never use it.

### Section map (python heading scan; char counts)

| line | section | chars | class |
| --- | --- | --- | --- |
| 1-6 | title + "Read BEFORE firing" | ~170 | HEAD |
| 7-79 | ▶ WHERE BOTTLE REVIEW STANDS, AND THE NEXT STEP | 4,909 | HEAD (rulings, condensed) + BODY (supply table, 7-step procedure, dated status lines) |
| 80-165 | THE METHOD / ▶ NEXT UP blind queue (09-22 snapshot) | 4,561 | BODY (stale count table; it says itself "RE-DERIVE, never copy") |
| 166-257 | THE QA PASS (09-14) | 6,532 | BODY |
| 258-288 | The metric, and what it forbids | 1,702 | HEAD (one line) + BODY |
| 289-304 | The funnel | 1,015 | BODY |
| 305-340 | The three levers | 2,452 | HEAD (one line: crops not clauses) + BODY |
| 341-364 | Sequencing, Anti-patterns | 1,356 | HEAD (guards) + BODY |
| 365-409 | Where bottle knowledge lives; 09-13 rulings; Rémy closure | 2,364 | HEAD (sign-off ruling) + BODY |
| 410-450 | 🚨 DECLARE THE INPUTS BEFORE EVERY RUN | 2,431 | HEAD (condensed rule) + BODY (example block) |
| 451-473 | The two axes | 831 | HEAD (one line) |
| 474-796 | remy-martin-vsop (99 draws, closed) | 22,520 | BODY (history) |
| 797-1481 | perrier-jouet-belle-epoque (96 draws, closed) | 46,072 | BODY |
| 1482-1735 | perrier-jouet-blanc-de-blancs (76, closed) | 16,525 | BODY |
| 1736-2147 | perrier-jouet-grand-brut (110 draws) | 33,638 | BODY |
| 2148-2256 | moet-nectar-imperial (6 draws, open) | 5,987 | BODY |
| 2257-2332 | PROCESS LEARNINGS 1-9 | 4,808 | BODY (the money-relevant ones are condensed into the head guards) |
| 2333-2337 | How to add a row | 201 | BODY (the head points at it) |

About 145k of the 151.7k chars is per-bottle history and method detail. It is needed at the
moment a session fires, and is noise for the other ~86% of sessions.

### The head is already failing at its one job (measured)

L:9-14 lists `perrier-jouet-grand-brut` as "Still open in the current contract". The same file
records the opposite at L:2115: "✅ RE-BAKED FROM run98, 2026-09-30, on his selection".
`public/bottles/manifest.json` contains the key `perrier-jouet-grand-brut` (python key check).
The ▶ NEXT UP queue (L:82-121) is a 2026-09-22 snapshot. A 2,337-line file whose status lives at
the top and whose writes land at the bottom drifts. The new head has to be short enough to
re-read on every edit, and it should carry commands rather than counts.

## 2. Writers and readers (measured, `git grep -n bottle-generation-ledger` in R, plus grep over `~/.claude/skills` and `~/.claude*/projects/*reso*/memory`)

Writers:

- The only writers are bottle sessions appending rounds (the 69 commits above). The instruction to
  append is in L itself: § "How to add a row" (L:2333) and the "Every row cost real money" framing
  (L:5). No other rule tells agents to write to it.

Readers / pointers. Each must keep resolving after the split.

| pointer | cites | after split |
| --- | --- | --- |
| `R/.claude/rules/bottle-reference-sourcing.md:19,23` | path + "§ WHERE BOTTLE REVIEW STANDS" | valid if the head keeps the path and that heading |
| `R/.claude/skills/bottle-reference-sourcing/SKILL.md:24` | same § | valid (same) |
| `R/.claude/rules/bottle-menu-data.md:177` | path, "read it before firing" | valid (the head points on) |
| `R/.claude/rules/bottle-service.md:18` | path | valid |
| `R/scripts/data/bottle-catalog.ts:286` | "every configuration ever tried… recorded in" | **repoint** to the record file |
| `R/.claude/workflows/bottle-brand-photo-sourcing.js:18` | "§ perrier-jouet-grand-brut" | **repoint** to the record file |
| `R/scripts/data/bottle-image-manifest.json` (15 `reason` strings) | the path, as provenance prose | leave as is (historical data, and the head points on) |
| `~/.claude/projects/-Users-chrisren-Development-reso-management-app/memory/reference-prompt-label-copy-costs-the-camera.md:53` (same file seen via all 4 account dirs) | "§ perrier-jouet-belle-epoque" | repoint (memory, outside git; ~/.claude-next holds a separate real copy) |
| `~/.claude/skills/*` | none (`grep -rln` empty) | n/a |
| claude-infrastructure | only research measurements (`git grep -l`) | n/a |

Nothing else in R's CLAUDE.md, scripts or docs references it.

## 3. How a paid generation is fired, and whether `paths:` could guard it

- There is no `package.json` script for generation. `grep -n bottle package.json` shows only
  `review:bottles*`, `optimize:bottles`, `generate:bottle-*` and `check:bottle-size`. Paid fires are
  direct Bash calls: `pnpm tsx scripts/bottle-gen-production.ts --slug=… [--ref-image=… --ref-image2=… --runs=N]`
  (usage block at `R/scripts/bottle-gen-production.ts:44-60`). The bottle-reference-sourcing skill
  shows the same call (`SKILL.md:641`).
- CC 2.1.284 (from `/tmp/cc284.strings`): `nestedMemoryAttachmentTriggers` is appended to only
  inside FileReadTool's text, image and notebook branches. `dVt()` then turns those triggers into
  `nested_memory` attachments, which is how `paths:` rules load. A Bash `pnpm tsx …`, `sed` or
  `cat` adds no trigger.
- The repo already wrote this down for its own path-scoped bottle rule, at
  `R/scripts/bottle-gen-production.ts:965-969`: *"bottle-reference-sourcing.md is `paths:`-scoped to
  six script files, so it loads when a session EDITS one and never when a session RUNS this. The
  generator is the one artifact every bottle session executes, so the knowledge lives here."*
- Measured, with `python3 /tmp/ibudget/fire_scan.py` over all account transcripts: **24 transcript
  files contain a paid (non-`--dry-run`) `bottle-gen-production.ts` call. Only 8 made a Read/Edit/Write
  of any candidate glob path before the first fire.** The globs tested were the union of the
  existing bottle rules' `paths:` plus `scripts/data/bottle-image-manifest.json` and
  `bottle-photography/**`. Of those 8, 4 matched only through `bottle-photography/**` image reads.
  **16 of 24 fired with no matching Read.** The regex is a heuristic, so that figure is an
  estimate of a measured scan. The live bottle session today (see §6) has made 10 Bash calls,
  0 Read calls and loaded 0 `nested_memory` attachments.
- When a `paths:` rule does trigger, it injects the WHOLE file mid-session as a `nested_memory`
  attachment: about 145k chars (~62k tokens, estimated) at once, on top of the 82k
  `bottle-reference-sourcing.md` that shares the same globs.

**Verdict: a `paths:` rule is the wrong destination for the body.** It cannot see the money path
(Bash), and when it does fire it dumps the full history at once.

## 4. Body destination: options weighed

| option | verdict | evidence |
| --- | --- | --- |
| `docs/bottles/generation-ledger.md` | **reject** | `R/docs/README.md` says "A path that fits nowhere is a missing row in that table, never a new folder". The closed subsystem set is in `R/scripts/lib/docs-rules.ts:29-41` and has no `bottles`. The docs file budget is `DOCS_FILE_BUDGET=180` (`docs/.baseline.env`), and `git ls-files docs \| wc -l` = **190** today. Rule E3 "no new docs file without a deletion" (`docs-rules.ts:204`) is a declared programme rule; today it is exercised only over fixtures (`tests/docs-structure.test.ts`). The filing oracle maps `scripts` to `infra-deploy`, which is a nonsense home for an experiment record. |
| path-scoped rule (`paths:` over `scripts/bottle-gen-*.ts`, `scripts/data/bottle-*`, `scripts/lib/bottle-*`, `scripts/lib/resolve-image-group.ts`, `bottle-photography/**`) | **reject** | §3: misses 16/24 fires and injects ~62k tokens when it does hit. A subfolder of `.claude/rules/` does not escape loading either: CC's `$De()` recurses into rules subdirectories (`if(zt){…$De({rulesDir:Dt…})}` in cc284.strings). |
| `bottle-photography/LEDGER.md` | reject | `bottle-photography` is gitignored (`R/.gitignore:89`, `git ls-files bottle-photography \| wc -l` = 0). It would lose history and every worktree would share a single mutable file. |
| **`.claude/bottles/generation-ledger.md`** | **recommend** | It is tracked, sits outside every CC auto-load location (rules, skills, agents, commands), and is owned by the `.claude` row in `docs/OWNERS.tsv` ("repo machinery: rules, skills…"). It is outside the docs budget. It is markdownlinted by the pre-commit hook (`scripts/hooks/pre-commit:515` excludes only `scripts/`, `.claude/agents\|skills\|commands/`, `docs/research/`), which is the same lint it passes today. It is at the same depth as `.claude/rules/`, so the 3 relative `../../bottle-photography/…` links (`grep -o`) resolve **unchanged**. |

## 5. The proposed always-loaded head

File: `/tmp/ibudget/reso-ledger-head.proposed.md`. Measured at **4,079 chars**
(`python3 len()`), against a 6k target. It stays at the **same path**
(`.claude/rules/bottle-generation-ledger.md`) and keeps the heading
"▶ WHERE BOTTLE REVIEW STANDS, AND THE NEXT STEP", so 5 of the 7 in-repo pointers keep resolving
with zero edits. It carries:

1. A pointer to the record file, plus the rule: open its `## <slug>` and § THE METHOD before any
   non-`--dry-run` fire.
2. Status as **commands to re-derive**, plus one dated line of fact (corrected: grand-brut baked
   run98; the Moët pair still open).
3. The 2026-09-23 ruling that the operator supplies the references and agents do not source them.
4. Five binding rulings: the P(≥1 prod) metric and no grading of losers; label first then
   background at 1306 px; no agent sign-off, a blind rank, and a bake only on his selection;
   inputs declared verbatim before and after (with the ban on "same as last time"); the prompt as
   a fixed budget, with crops rather than clauses.
5. Money guards: never fire an exiled recipe; no new recipe guess first; re-look at an image before
   trusting a verdict; vintage and market check; fire small; `--no-supplement` only for a named
   control arm.
6. The write rule: rounds go to the record file; the head is edited only on a
   bake, sign-off or ruling. A size-cap comment sits at the top.

Everything else moves verbatim to `.claude/bottles/generation-ledger.md`, including the supply
table, the 7-step procedure, the queue, THE METHOD, the per-bottle sections, PROCESS LEARNINGS and
How to add a row. Nothing is summarised away.

Effect (measured char counts, `python3 len()`): reso's always-loaded project files are CLAUDE.md
35,964 + agent-operating-lessons 52,130 + agent-teams 7,828 + ledger 151,742 = **247,664**. After
the split that becomes about 99,999 (−147,663). The per-file warning for the ledger clears. **The
total warning does not clear on this change alone.** 428.1k − 147.7k ≈ 280k is still over 150k,
because of the user-level double load (slim + full ~/.claude/CLAUDE.md, the lead's KEY DEFECT) and
the 52k agent-operating-lessons.md.

## 6. Live state and pickup (measured)

- **A live bottle session exists now:**
  `~/.claude-quaternary/projects/-Users-chrisren-Development--worktrees-wt-cc-142226-72029/389eb846-….jsonl`
  (mtime 2026-10-03 14:36). It is the session that showed this warning: its first prompt at
  19:30Z is this very request. At 19:32Z the operator re-tasked it to "re-up our localhost:3334
  bottle review page… remaining bottles to image source… Studio60". `pgrep -fl bottle-image-review`
  shows pids 14718/14915 serving `--port=3334` from that worktree. It is likely to append to the
  ledger soon ("He is moving on to Moët", L:2125).
- No checkout has the ledger modified. `git -C <wt> status --porcelain -- .claude/rules/` across
  all 40 `git worktree list` entries prints nothing, and `lsof L` is empty. The main checkout at
  2738a13bb is in sync with origin/main, and the ledger's mtime is Sep 29 21:06.
- Copies on disk (`wc -c`): 153,279 in R, reso-qa-runner, wt-pool-2/3/5/7/8,
  wt-cc-141442-81738, wt-cc-142226-72029 and reso-ops-signin. 126,966 in
  reso-management-app-release. 109,406, 104,179 and 80,253 in three older worktrees.
- **`reso-qa-runner`** is a git worktree of R (`.git` = `gitdir: R/.git/worktrees/reso-qa-runner`),
  detached at origin/main. `com.reso.qa-nightly` (launchctl-listed, 04:17 daily,
  `R/scripts/launchd/bin/qa-nightly-run.sh:30-44`) fetches and then runs `reset --hard origin/main`,
  but only when the fetch succeeds and the tree is clean. It picks up a landed change **the next
  night**. Sessions do run there: one 2026-09-21 transcript in that cwd made a paid fire.
- **`reso-management-app-release`** is a worktree, detached and locked, described as a "browse
  mirror — the human-readable checkout of origin/release". `com.claude.browse-mirror`
  (claude-infrastructure `scripts/browse-mirror-sync.sh:67-69`, `FETCH_MIN=600`) holds it at
  **origin/release**, which is **156 commits behind origin/main** (`git rev-list --count`). It picks
  up the change **only when origin/release moves (`/deploy`, the operator's call)**. The same
  daemon holds the root checkout R at origin/main, so R gets the change within ~10 min of landing.
- The other ~37 reso worktrees keep their copy until they rebase. New worktrees from origin/main
  get the fix.
- Landing: R/CLAUDE.md:566-573 says "`/ship` is FREE and agent-driven" (gate lifted 2026-08-02;
  `scripts/land-status.sh` is the live check). Landing costs nothing, so land fast.

## 7. Lint

- None exists. `git grep` over `scripts/`, `.github`, `scripts/hooks/` and `package.json` finds no
  check on `.claude/rules` or CLAUDE.md size. The pre-commit hook runs only markdownlint on
  `.claude/rules/*.md`.
- Without one, the head will regrow. 69 append commits in 17 days is the measured rate at which
  sessions write here.

## 8. Recommendations (ordered)

1. **Split in two commits, landed together in one `/ship`.**
   - (a) `git mv .claude/rules/bottle-generation-ledger.md .claude/bottles/generation-ledger.md`
     as a pure rename, so `git log --follow` keeps all 69 commits of history.
   - (b) Create the head at the old path from `/tmp/ibudget/reso-ledger-head.proposed.md`. In the
     same commit, repoint `scripts/data/bottle-catalog.ts:286` and
     `.claude/workflows/bottle-brand-photo-sourcing.js:18` to the record file, and change the
     record file's top banner to say it is the non-auto-loaded record.
   - Then fix the stale status lines L:9-14 in the record file.
2. **Coordinate with the live bottle session (wt-cc-142226-72029)** before landing. Run
   `git log origin/main -1 -- .claude/rules/bottle-generation-ledger.md` immediately before the
   push. If it moved, re-apply the new rows to the record file rather than to the head. A session
   that later rebases over the split gets a conflict on the old path. The guard in item 3 turns
   that into an instruction instead of a silent re-bloat.
3. **Add a reso size gate**, fired by both the pre-commit hook and a vitest in `pnpm test:unit` so
   that postland-verify enforces it at the trunk sha. The gate checks:
   - every `.claude/rules/**/*.md` WITHOUT `paths:` frontmatter, plus the root CLAUDE.md, against
     a per-file cap;
   - their sum against a total cap;
   - `bottle-generation-ledger.md` against a cap of 6,000.
   Use the repo's own ratchet idiom (`DEBT_BASELINE`, monotone non-increasing) so the
   existing 52k agent-operating-lessons.md is grandfathered but cannot grow. The failure message
   must name the destination: "append run rows to .claude/bottles/generation-ledger.md".
4. **Put the money guard where the money is spent.** Extend `printReferenceLedger`
   (`scripts/bottle-gen-production.ts:971`) so that every invocation, dry or paid, prints the
   head's status line and the slug's EXILED and "Fire this next"/"Strategy" subsections, pulled from
   `.claude/bottles/generation-ledger.md` by `## <slug>` heading. This follows the file's own
   reasoning at :965-969 and covers the 16/24 fires that never Read a rule path.
5. **Do not use `claudeMdExcludes` for this file.** It would strip the money guard along with the
   bulk. Fix it in the repo, and let the browse mirror and the nightly reset carry it to R and
   qa-runner. The release mirror follows on the next `/deploy`.
6. Update the memory pointer in
   `~/.claude/projects/-Users-chrisren-Development-reso-management-app/memory/reference-prompt-label-copy-costs-the-camera.md:53`
   to the record file. Memory is outside git. secondary, tertiary and quaternary symlink to that
   dir (`ls -ld`), but `~/.claude-next/projects/-Users-chrisren-Development-reso-management-app/memory`
   is a **real directory holding its own copy**, so update both.
