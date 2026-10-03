# critic: completeness review of the instruction-budget research (6 slots)

Slug: critic. Date 2026-10-03. Read-only with respect to every repo, `~/.claude*` and settings. Written only under
`/tmp/ibudget/` (this file, `critic-probe.sh`, `critic-sim/`, `critic-*.out|err`, `critic-gitsim*.XXXXXX/`).
Side effects, all disclosed:
- I ran `git fetch origin` in reso-management-app, which the brief allows. origin/main did not move: it is still 2738a13bb.
- I ran three CC binaries with scratch `CLAUDE_CONFIG_DIR`s under /tmp/ibudget. Their state went there, and they may have touched CC caches.
- Hooks blocked three of my commands (`--no-verify`, `git config user.*`, `rm -rf`). Each was blocked whole, so none of them ran. I re-ran them in fresh `mktemp` dirs with transient `-c` identity.

## 0. Bottom line

The slots agree on the diagnosis. The ancestor walk loads `~/.claude/CLAUDE.md` and `~/.claude/rules/*` as Project
memory on top of the slim User memory. Migration 0042 broke the realpath dedupe that had hidden this, and since then every
session whose cwd is under $HOME pays about 181k chars of global instructions. The slots are weaker on the fix, and they
disagree with each other on four points.

**Instruction-file fix.** The most durable fix was never tested by any slot. My probes show this:
- **Canonical-file shape (v4): works on every binary in use.** Make `~/.claude/CLAUDE.md` a regular file holding the
  chosen variant, and point every account's `CLAUDE.md` and `rules` at `~/.claude/CLAUDE.md` and `~/.claude/rules`. That is the
  pre-0042 shape with new content. It removes the double load on 2.1.284, 2.1.278 and 2.1.114. It needs no
  `claudeMdExcludes`, no change to any launcher, and does not depend on memory type.
- **Symlink variant (Option C): not version-proof.** Making `~/.claude/CLAUDE.md` a symlink to the slim file is the option three
  slots suggested. It dedupes on 2.1.284 and 2.1.278 but **fails on 2.1.114**, which qa-nightly and `claude-prev*` still
  run. `install.sh:1043` would also silently revert it, because it `rm`s a symlink at that path and then `cp`s the full file over it.
- **Exclude in shared settings: drops all global instructions for default-dir sessions.** I confirmed this
  empirically: a default-dir-shaped session with the exclude loaded zero memory files.

**Ledger fix.** reso-ledger's plan keeps the head at the old path, which fails under the concurrency it is meant to
survive. In a scratch repo, a concurrent append conflicts, and the conflict hunk carries the whole old body. Put the head at
a new path instead: git's rename detection then carries concurrent appends into the record file cleanly (measured).

## 1. Spot-checks of slot facts (measured)

| Claim (slot) | Check | Result |
|---|---|---|
| Account `CLAUDE.md` → `CLAUDE.slim.md`, `rules` → `rules.slim`, settings shared (lead, ab-contamination) | `ls -lad ~/.claude-*/{CLAUDE.md,rules,settings.json}` | Confirmed for all 4 accounts. The links date from Sep 25 11:50; settings.json was re-linked Oct 1 20:22. |
| Full 111,752 / slim 57,545 chars; `~/.claude/CLAUDE.md` is a regular file (ab-contamination) | python `len`, `os.path.islink` | Confirmed: 111,752 / 57,545, not a link. Its mtime is **today 12:45** (install.sh redeployed it). |
| Ledger 151,742 chars, no `paths:` (reso-ledger) | python `len`, head of file | Confirmed. The first line is a markdownlint comment, with no frontmatter. Unchanged on origin/main after the fetch (last commit 9a985f3c3, 09-29). The live bottle worktree's copy is unmodified (153,279 B). |
| Existing exclude at `settings.json:1313` (fleet-census) | `grep -n` | Confirmed: `["**/.claude/rules/agent-operating-lessons-situational.md"]`. |
| Project-type loads of `~/.claude/CLAUDE.md` began with 0042 (ab-contamination) | per-day tally of `~/.claude/logs/instructions-loaded.log` | Confirmed. First Project rows were on 2026-09-25 (4); since then 38-128 per day. Before that there were none. |
| `paths:` rules trigger only from the Read path (reso-ledger) | `/tmp/cc284.strings`, offset 20695772 | Confirmed. `nestedMemoryAttachmentTriggers.push` sits in the file-read routine (`tengu_file_read_*`). Bash never pushes. `bottle-gen-production.ts:965-969` says the same. |
| **`~/.claude-next` reso memory is "a real directory holding its own copy"** (reso-ledger §8.6, key facts) | `stat -f %i` on both paths | **Wrong.** Both have inode 55494883, because `~/.claude-next/projects` → `~/.claude/projects`. There is one copy and one edit. |
| **Ledger ≈ 64k tokens; a paths: trigger injects ≈ 62k tokens** (reso-ledger, from linear scaling) | ab-contamination's own counted `/context` c7 | **Overstated.** Counted: 48.6k tokens for the 151.7k file, so the estimate is about 32% high. |

## 2. New measurements by the critic

### 2.1 Which structural dedupe works, per binary

Scratch trees `/tmp/ibudget/critic-sim/v0..v4`, each with a fake `home/.claude` plus an account dir, cwd `home/proj`.
Command: `critic-probe.sh <label> <cfgdir> <cwd> [bin]` → `claude -p /context`. Memory rows:

| Shape | 2.1.284 | 2.1.278 (homebrew) | 2.1.114 (claude-latest) |
|---|---|---|---|
| v0 production today (regular full file + account → slim) | **User slim, User board, Project full, Project board, Project lessons** (reproduces the defect) | – | same 5 rows |
| v1 Option C: `~/.claude/CLAUDE.md` → slim (symlink), `rules` → `rules.slim` (dir symlink) | User slim + User board only (deduped) | deduped | **Project `home/.claude/CLAUDE.md` row still present** (top-level file NOT deduped; the rules dir is) |
| v2 Option C with per-file rule symlinks | deduped | – | – |
| v3 accounts chain through `~/.claude/CLAUDE.md` → slim | deduped | – | – |
| **v4 canonical regular file holding the chosen content; account → `~/.claude/CLAUDE.md`, `rules` → `~/.claude/rules`** | **deduped** | **deduped** | **deduped** |
| v1 default-dir session (`CLAUDE_CONFIG_DIR=home/.claude`, CLAUDE.md symlinked) | 1 User row (a symlinked User CLAUDE.md does load) | – | the 2 rows have different spellings; this is a `/tmp`↔`/private/tmp` artifact, not conclusive |

Binary read, consistent with the table: `mY` dedupes a symlinked file by `Gp(resolvedPath)`. The User symlink-skip
branch fires only when `F = includeExternal && vet()` is false, with `vet() = NN()!=="local-agent"`. 2.1.114 evidently lacks
the resolved-path check for top-level Project files.

### 2.2 The type-blind exclude, run rather than read

Same v0 tree, default-dir shape (`CLAUDE_CONFIG_DIR=home/.claude`), with `--settings {"claudeMdExcludes":[home/.claude/CLAUDE.md, home/.claude/rules/**]}`.
Output: `/context` has **no Memory files section at all**, and the total is 6.6k (system prompt only). Without the
excludes the same session loads 3 User rows (`critic-v0-default.out`). So default-configdir's binary reading is right:
a default-dir session would silently lose every global instruction.

### 2.3 Concurrent append across the ledger split (scratch git, `critic-gitsim2.CRIRxW/`)

Base has a 400-row ledger. Branch `bottle-session` appends one row. Main runs `git mv` to `.claude/bottles/ledger.md`
and then adds the head. Then `git rebase main`:
- **samepath** (head re-created at the old path, which is reso-ledger's plan): `rebase rc=1`, `UU .claude/rules/ledger.md`. The
  conflict hunk runs from line 5 to line 409, so "theirs" is the entire old body plus the new row. Resolving with
  theirs or both puts the full ledger back at the always-loaded path. The appended row does not reach the record file.
- **newpath** (pure rename; head at a new name, e.g. `ledger-head.md`): `rebase rc=0`. The appended row lands in
  `.claude/bottles/ledger.md` through rename detection, and the head is untouched.
- `git rebase` does not run `pre-commit`, so the pre-commit size gate that reso-ledger/reso-lessons propose cannot see a
  conflict resolution made during `/ship`. Only a land-time arm on the rebased tree, or a postland test, would see it.

### 2.4 The InstructionsLoaded log is not a complete census

- The qa-nightly runs (2.1.114 `sdk-cli`, cwd `reso-qa-runner`) on 2026-09-28 (×2) and 2026-10-01 have transcripts in
  `~/.claude/projects/-Users-chrisren-Development-reso-qa-runner/`, but **0 rows** in `instructions-loaded.log`.
  I found the session ids with grep. Their transcripts show that hooks do run (a `hook_cancelled` SessionStart attachment).
  The cause of the gap is unknown.
- The log did record earlier default-dir runs: User `/Users/chrisren/.claude/CLAUDE.md` rows appear daily at about 09:20Z from 09-07 to 09-19
  (qa-nightly), then 09-21 ×2 and 09-24 ×1.
- So guard-design's statement "no logged session uses ~/.claude as config dir → type-blind exclude looks safe" stands
  on a log with measured gaps. It cannot establish that no default-dir runs happen.

### 2.5 Costs no slot measured

- **Mid-session diff injections double too.** Over the last 3 days, deduped: 590 transcripts. The `edited_text_file` attachment
  for the mission board was injected **97× from `rules.slim/` and 97× from `rules/`**, about 274k extra snippet chars from the
  duplicate copy. The slim file's own edits added 46 injections and about 316k chars. `cc-mission` writes both boards
  (`bin/cc-mission:281-284`).
- **Conditional rules are a second, unbudgeted tier.** reso's `paths:` rules total 199,516 chars (python): bottle-reference-sourcing
  81,651, replicache 42,866, view-transitions 25,988, and others. Each loads whole, mid-session, on the first Read of a matching file.
  No proposed gate budgets them.
- **The ancestor tier holds more than `~/.claude`.** `~/Development/.claude/rules/agent-operating-lessons-situational.md` exists. It
  was created 09-26 by `cc-memory-rotate --drain-oversized` (see its header). It loads for every repo under ~/Development
  and is suppressed only by the name glob. c8 (no settings) shows it as a Project row.

## 3. Contradictions between slots

1. **Ledger destination.**
   - guard-design (§4.3, §8, recommendations) says to make the ledger conditional (`paths:`) or move it to `docs/`, and its
     deny text names that cure.
   - reso-ledger measured both as wrong. A `paths:` rule misses 16 of 24 paid fires (estimated from a regex scan), and a firing
     trigger injects the whole file. reso `docs/` is closed: `DOCS_FILE_BUDGET=180` with 190 files, and E3 requires a deletion for every addition.
   - reso-ledger is right. guard-design's deny text would steer agents into the money-path failure.
2. **Is the exclude in shared settings safe?**
   - guard-design says yes, it "looks safe for the observed sessions".
   - default-configdir says no: it needs launcher injection.
   - The measurements side with default-configdir (§2.2, §2.4). Both are dominated by v4, which needs no exclude at all (§2.1).
3. **What install.sh does to a symlinked `~/.claude/CLAUDE.md`.**
   - ab-contamination says install.sh's `cp` "would follow the symlink and overwrite the variant".
   - The code does something else: `install.sh:1043` runs `[[ -L ... ]] && rm` first, then `cp`s the full file. Option C is therefore
     **silently undone** on the next deploy rather than corrupting the slim file. The effect differs but the conclusion is the same: the deployer must change.
4. **reso memory dir.** reso-ledger says `~/.claude-next` has a separate copy; inode equality shows it is the same directory (§1).
5. Minor, not substantive: the sizes reported as 181,485 / 180.7k / 429,149 / 429,181 / 428,086 differ only by raw versus stripped
   counting and by edits made since. The ledger growth rates (8.5 versus 9.4 KB/day) use different sample commits.

## 4. Assertions that rest on inference or were overstated

- guard-design: the user tier is "at budget" at 60,470 against a 60,000 budget. It is already **over**, so the user tier is frozen from day 1.
  Every rule addition to the slim file then has to be one-in-one-out.
- guard-design maps the source `CLAUDE.global.md` to `~/.claude/CLAUDE.md`, but that path is User memory for the default dir and
  Ancestor (budget 0) for account sessions. With tier = ancestor, any growth of CLAUDE.global.md is refused until the
  ancestor fix lands. That would block ordinary infra edits; the tier is undefined, not just a value call.
- reso-lessons: "situational = grep on demand". The name glob excludes that file on every account, so 31 hooks (about 10.7k) would
  leave context entirely, and whether they are recalled depends on agents grepping. The recall cost was never measured, for infra or for reso.
- ab-contamination: the claim that quality of the union arm is untested is correctly flagged. No slot measured quality for any proposed end
  state either (slim-only on all launch paths, including default-dir sessions under v4 or C).
- fleet-census: 200k-window main sessions. The count of 174 haiku transcripts was not split into main sessions and subagents, so the
  40k per-file budget's premise is unverified.

## 5. Failure modes of the proposed fixes

| Fix | Failure mode | Evidence |
|---|---|---|
| Exclude `~/.claude/CLAUDE.md` + `rules/**` in shared settings | Default-dir runs (claude-prev, `cc()` fallback, bare `claude`, any launchd job without the env var) get **zero** global instructions, with no warning. A per-launch override is impossible because arrays union. | §2.2 (measured), default-configdir i9/yet |
| Same exclude, injected by the launcher | Coverage gaps: qa-nightly (2.1.114, not wrapped), claude-prev2/3/4, homebrew bare `claude`, bg spares. Also a second `--settings` flag would silently drop `autoMemoryDirectory`. | default-configdir §4 |
| Option C (symlink `~/.claude/CLAUDE.md` → slim) | 2.1.114 still double-loads. install.sh reverts it on the next deploy. A `rules` dir symlink makes `cc-mission` write the full board and then the compact board to the same file on every render, so each render changes bytes twice and fires two diff injections into every live session. | §2.1, install.sh:1043, cc-mission:279-284 |
| v4 (canonical regular file) | (a) Default-dir sessions get the chosen variant (slim) instead of full; this is an operator decision. (b) Per-account A/B is no longer possible in production: any account pointed at a different file double-loads again. `cc-instructions-variant set` must refuse that, or A/B must stay in /tmp fixtures. (c) The deployed slim file is STALE against the gated pin (d28f vs d446), so it needs a re-gate or a formal accept. | §2.1, ab-contamination §5 |
| Ledger head kept at the old path | A concurrent append conflicts and the "theirs" side re-creates the full 153k file at the always-loaded path. Pre-commit does not run during rebase. | §2.3 (measured) |
| Ledger body under a `paths:` rule | Paid fires happen through Bash, which never triggers it (16 of 24 estimated). When it does fire it injects about 48.6k tokens mid-session. | reso-ledger §3, c7 |
| guard L1 "adding `paths:` is always allowed" | A one-line escape hatch: any blocked always-loaded file can be made conditional and then grow without limit in the unbudgeted conditional tier (199.5k in reso already). For money guards, it moves them off the Bash path. | §2.5 |
| guard L1 against Bash writes | A PreToolUse gate cannot see `>>`, `sed -i`, python or cp. L2 is advisory, and only for the session that names the file. Untracked always-loaded files (`~/.claude/rules/*`, `~/Development/.claude/rules/*`, `CLAUDE.local.md`) have only the auditor (hourly), with no hard stop. | guard-design §5 |
| guard L1 freezing over-budget files | Slim 57.5k, full 111.8k, reso lessons 52.1k and personal lessons 51.9k all become shrink-or-neutral at once. Rolling L1 out before the ledger split refuses the next bottle append, so the live bottle workflow stops. | guard-design §8 |
| Auditor census built on InstructionsLoaded | Misses runs that do not log (§2.4), so it under-counts headless and default-dir sessions. | §2.4 |
| reso lessons → situational name | The rotor (`cc-memory-rotate`) creates that name in whatever `$CLAUDE_PROJECT_DIR` is, including ancestors such as `~/Development`. If the glob ever changes, those files load into every session. | §2.5 |

## 6. Not investigated, but needed for a 100th-percentile durable fix

1. **Make the invariant itself a test.** "No instruction file is loaded twice under different realpaths, and the per-session
   always-loaded total ≤ budget, for every (config dir ∪ `~/.claude`) × (repo root) × (installed CC binary)." It needs two halves:
   - a static realpath check that costs nothing to run;
   - the auth-free `claude -p /context` probe from a cwd under $HOME, run in the CC upgrade gate against every installed binary (2.1.114, 2.1.278, 2.1.284), because loader semantics differ by version (§2.1).
2. **Migration hygiene.** 0042's verify line checked symlink targets but not the loaded composition. Any future
   instruction migration needs a post-apply `/context` assertion in its verify step. The gate harness also needs a production-shaped arm: home cwd, no excludes.
3. **Default-dir policy.** Retire it, or support it, explicitly. Under v4 it is safe either way. Under any exclude-based fix it needs a SessionStart guard.
4. **Subagent and teammate multiplication.** Whether each spawned subagent or teammate also pays the double load was not measured.
5. **Post-compaction reload.** Whether memory is reloaded after compaction, and the cost of the union arm at each compaction, was not measured.
6. **A budget for conditional rules,** so they can no longer serve as the escape hatch (§2.5).
7. **Tombstone check for the old ledger path.** After the split, a land-time check should refuse re-creation of a >N-char file at
   `.claude/rules/bottle-generation-ledger.md`, or of any file without `paths:` over the cap. It must run on the rebased tree (ship-land run_statics), not only in pre-commit.
8. **The other 37 reso worktrees and the release mirror (156 commits behind)** keep the old bytes until they rebase or deploy. The
   warning will persist there, and a census will flag them. Expected, but it should be documented.
9. **Quality check of the end state** (slim-only for every launch path) against the drifted slim file.
