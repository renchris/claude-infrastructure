# guard-design — a chokepoint that stops always-loaded instruction growth from coming back

Slug: guard-design. Read-only investigation, 2026-10-03. Worktree: /Users/chrisren/Development/.worktrees/wt-cc-143021-71044 (W below).
The only files written are this report and the prototype /tmp/ibudget/guard-design-proto.py (a loader emulator I used to measure, and the seed for the auditor).

## 0. Bottom line

The repo already has the right pattern, built for MEMORY.md: a PreToolUse gate that judges the projected size of a Write/Edit/MultiEdit and refuses only growth, a PostToolUse stat-detector that catches the same file growing through Bash or any other route, a land-time ratchet, and a launchd-driven assert that files one condition-keyed backlog row. The instruction-file problem needs that same four-layer stack, built on one Python predicate:

| Layer | Host (already registered, zero settings change) | Catches |
|---|---|---|
| L1 gate (brake) | `hooks/backup-before-write.sh`, PreToolUse Write\|Edit\|MultiEdit | every tool-path write, new files, `paths:` removal, `@import` additions |
| L2 detector (Bash, python, cp) | `hooks/memory-index-drain.sh`, PostToolUse Bash\|Write\|Edit\|MultiEdit | writes from any route in a session, at the next tool call |
| L3 land ratchet | `scripts/ship-land.sh` (claude-infra) + reso's own `scripts/ship-land.sh` / `scripts/hooks/pre-commit` | anything committed: machine writers, humans, stale-hook sessions |
| L4 fleet auditor | new `bin/cc-instruction-budget`, run from `scripts/autonomy-sweep.sh` (300 s, loaded) | the real per-session total, including the ancestor defect, untracked `CLAUDE.local.md`, settings drift |

Machine writers that do not go through tools (`cc-memory-rotate` route_flush, `cc-mission render`, `install.sh`) call the same predicate before they write.

## 1. Measured state (why this is needed)

- Emulator fidelity. `python3 /tmp/ibudget/guard-design-proto.py ~/.claude-quaternary ~/Development/reso-management-app` => `files=9 total=429181 ... total_warning=YES per_file_warnings=1`. The startup warning said "9 instruction files add up to 428.1k". The file count matches exactly and the total is within 0.25%. Per-file: ledger 151,801 (warning: 151.7k), `~/.claude/CLAUDE.md` 111,862 (111.6k), quaternary CLAUDE.md 57,588 (57.1k). Measured.
- Fleet population. From `~/.claude/logs/instructions-loaded.log` (session_start rows since 2026-10-02), grouped by session and re-measured at today's sizes: 123 sessions, median 197,398 chars, p90 239,851, max 429,181, and 116 of 123 over 150k. Measured with an inline python over the log. Inferred caveat: sizes are taken now, not at load time.
- The ancestor defect at fleet scale. Same log since 2026-10-02: `Project /Users/chrisren/.claude/CLAUDE.md` 124 rows, `Project ~/.claude/rules/agent-operating-lessons.md` 124, `Project ~/.claude/rules/00-mission-board.md` 124. Since 2026-09-26 there are zero `User` rows for `/Users/chrisren/.claude/CLAUDE.md` (the User rows are next 329, quaternary 328, tertiary 192, secondary 95). So no logged session uses `~/.claude` as its config dir. Measured.
- Ledger growth rate. Size at commits (`git show <sha>:.claude/rules/bottle-generation-ledger.md | wc -c`): 12,911 B (2026-09-14), then 69,079 (09-21), 119,710 (09-24), 153,279 (09-29). Created 2026-09-13 (a9d1eedc3). That is about 9.4 KB/day over 15 days. Measured.
- Project tier per repo (always-loaded files only; emulator `parse` over ~/Development/*): reso-management-app 247,688 (4 files; ledger 151,801), reso-qa-runner 247,688, reso-management-app-release 221,482, claude-infrastructure 89,537 raw (but 73,562 of that is `agent-operating-lessons-situational.md`, which `claudeMdExcludes` drops, leaving about 16k effective), personal 53,421 (agent-operating-lessons.md 51,879), all other repos ≤ 30,083. 21 repos have any always-loaded project file. Measured.
- No global git hooks. `git config --global core.hooksPath` => rc 1 (unset). `init.templatedir=/Users/chrisren/.git-template` holds the git-identity gate (pre-commit, pre-merge-commit, pre-push, commit-msg). Local `core.hooksPath` overrides exist: reso family ×5 → `~/.reso/land-tools/scripts/hooks`, plus several `.husky`/`.githooks` repos. Measured by a loop over ~/Development/*/.git.

## 2. Loader facts used (read from the 2.1.284 binary, /tmp/cc284.strings)

- `hVe(e)= max(40000, round(window*0.05*u_(e)))`, `iRn= max(120000, hVe)` (lead-verified). New, measured by me: the total trigger `ixt` sums only the files at or under the per-file limit (`n.reduce((h,b)=>b.content.length>r.limitChars?h:h+b.content.length,0)<=r.totalLimitChars`), but the displayed total includes every file. Files counted have types User/Project/Local/Managed (`Ibe`). `<auto-memory-index>` and managed-settings pseudo-files are excluded (`gVe`).
- The content measured is `cet` → `lRn`: YAML frontmatter is stripped, then `vbe` strips block HTML comments (lexer html tokens starting `<!--`). `.content.length` counts UTF-16 units. There is no trim. `hooks/lib/memory-index-measure.sh:64-78` (`mim_strip_frontmatter`, `mim_strip_block_comments`, `mim_units`) already implements this with a safe under-strip. Reuse it minus `mim_trim`.
- `paths:` semantics (`lRn`): no `paths` key means unconditional. Each glob has a trailing `/**` sliced off and empties are dropped. If the list is empty or every entry is `**`, the file is unconditional. Otherwise it is conditional and `$De(...conditionalRule:false)` filters it out of the session_start set (`Je.push(...In.filter(Jn=>g?Jn.globs:!Jn.globs))`).
- Per-dir walk (`VLn`): `<D>/CLAUDE.md`, `<D>/.claude/CLAUDE.md` (Project), `<D>/CLAUDE.local.md` (Local), `<D>/.claude/rules/**` unconditional (Project), for each ancestor D of cwd. User = `$CFG/CLAUDE.md` + `$CFG/rules/**` (includeExternal). `@path` imports are followed up to depth 5 (`_Rn=5`, `yRn` skips code/codespan). Files over 4 MiB are skipped (`Z8`). `claudeMdExcludes` applies to User/Project/Local and is type-blind (`yet`). `AGENTS.md` is only probed (`vRn` returns a boolean) and not loaded. That last point is inferred from the call site.

## 3. Q1 — the zero-settings-change host for the Write/Edit/MultiEdit guard

Registered (`jq '.hooks.PreToolUse' ~/.claude/settings.json`): matcher `Write|Edit|MultiEdit` → `backup-before-write.sh` (timeout 10), `check-edit-boundary.sh` (10), `plan-agent-teams-default.sh` (5), plus a second block `workflow-script-edit-allow.sh`. Both candidate hooks are symlinks into the shared checkout (`ls -la ~/.claude/hooks/backup-before-write.sh` → claude-infrastructure/hooks/...). Edits therefore go live at trunk fast-forward.

Recommended host: `hooks/backup-before-write.sh` (316 lines).
- It already hosts the one size-refusing gate on this matcher: the MEMORY INDEX BUDGET block, W/hooks/backup-before-write.sh:146-188. Its own header gives the C10 rationale for living here (lines 150-163: "already wired … needs no settings.json edit (C10) and cannot become a pending-activation"). The lib-resolution idiom (deref first, then `${CLAUDE_CONFIG_DIR}/hooks/lib`) is at lines 165-167. The deny emitter, which sets `EMITTED=1` so the EXIT trap `_bbw_rewrite_only` (lines 76-82) does not double-emit, is at 176-187.
- The projection semantics to mirror (Write = content; Edit = literal first or all replacement; MultiEdit = sequential) are in `_MIB_JQ_PROJECT`, W/hooks/lib/memory-index-budget.sh:84-102. The "refuse only growth past the limit; shrink and neutral always allowed" invariant is argued at :22-33. This gate is the same invariant applied to a different file class.
- Placement trap: the hook fast-exits at W/hooks/backup-before-write.sh:142-144 (`[ ! -f "$FILE" ] && exit 0`). The MIB gate sits after that exit, so it never judges file creation. Creating a new `.claude/rules/x.md` is a primary growth route, so the new arm must go between line 140 (the `esac` closing the neighbours case) and line 142. This is the "24b lesson" W/hooks/check-edit-boundary.sh:80-82 cites: a gate placed after an early return is escaped in the common case.
- Tests for this host: `tests/memory-index-budget.bats` (37 `@test`). It covers lib-level arithmetic, the shrink asymmetry from an over-limit fixture (108-140), measure-unit pins (144-188), projection (211-247), fail-open (266-293), host e2e (308-322) and the symlinked-host inert-lib trap (324-341). Also `tests/hook-jq-abstain.bats` (8, includes this hook and check-edit-boundary), `tests/memory-path-canon.bats` (the CANON_TI rewrite that a deny must not clobber), `tests/mem-neighbours.bats`, `tests/read-before-write-parity.bats`, `tests/backup-*.bats`.

Alternative host: `hooks/check-edit-boundary.sh` (196 lines). It is deny-capable and sources a lib before its early exit (worker-claim gate, lines 91-118, before `[ ! -f "$STATE_FILE" ] && exit 0` at 121). Insertion would be at 118/120. Tests: `tests/worker-claim-gate-coverage.bats` (26), `tests/worker-claim-gate.bats`. Not preferred: it has no projection machinery, and its purpose is boundary and lease enforcement.

## 4. Q2 — predicate and budgets

### 4.1 Predicate: `is_always_loaded(path, cfg)`

Normalize first: make the path absolute against the payload `.cwd`, collapse `//` and `/./`, and resolve symlinked parents the way `_bbw_phys` (W/hooks/backup-before-write.sh:39-47) does. The leaf may not exist.

A file is an always-loaded instruction file when one of the following holds and it is not excluded by `claudeMdExcludes` from the shared `~/.claude/settings.json` (reuse `rules_file_loads`, W/hooks/lib/rules-loaded.sh:21; it reports loads, excluded or unknown, and unknown counts as loads, which is the conservative direction):
1. basename is `CLAUDE.md` directly in a dir D, or `D/.claude/CLAUDE.md`, or `CLAUDE.local.md`. Nested-subdir CLAUDE.md files (lazily loaded through `nested_traversal`) get the per-file budget only; they are not in the session-start tier.
2. `D/.claude/rules/**/*.md` whose post-projection frontmatter has no effective `paths` key: key absent, list empty after the `/**`-trim, or every entry `**`. A `paths: "**"` file is always-loaded.
3. User tier: `$CFG/CLAUDE.md`, `$CFG/rules/**/*.md` for every config dir (`~/.claude`, `~/.claude-{next,secondary,tertiary,quaternary}`; derive from accounts.json, never hardcode) and their symlink targets (`~/.claude/CLAUDE.slim.md`, `~/.claude/rules.slim/**`).
4. Deploy sources, mapped to their deployed tier: claude-infrastructure `CLAUDE.global.md` → `~/.claude/CLAUDE.md` (install.sh:1042-1044) and `CLAUDE.global.*.md` → `~/.claude/CLAUDE.<variant>.md` (install.sh:1050-1055). These do not match by name, so the mapping must be explicit, in config/instruction-budget.json.
5. Reachability set: any realpath reached from 1-4 through `@import` (depth < 5, outside code) or through a symlink inside a rules dir. The guard cannot compute this per write without a walk, so the L4 auditor publishes it to `~/.claude/state/instruction-budget/loaded-set.txt` (one realpath per line). The hook pre-screen reads that with a builtin `read -d ''` (no fork) and does a `case` match.

Measure: `effective = strip_frontmatter → strip_column0_block_comments (skip if a ``` fence exists) ; units = UTF-16 code units`. That is the MIM defs at memory-index-measure.sh:64-78 without `mim_trim`. Under-strip only makes the measure larger (the safe direction).

### 4.2 Verdict (the MIB asymmetry, per file AND per tier)

```
cur_f, new_f = effective(file now), effective(projected)      # 0 when absent or conditional
cur_t, new_t = tier_sum(now), tier_sum(projected incl. imports) # tier of the written file
DENY iff (new_f > PER_FILE and new_f > cur_f) or (new_t > TIER[tier] and new_t > cur_t)
```
- Writes that shrink or stay the same size are always allowed, even when the file or tier is already over budget. That covers moving a body out, adding `paths:`, and one-in-one-out edits. So the gate can never block the fix for its own condition (memory-index-budget.sh:25-33).
- A Write that adds `paths:` makes `new_f = 0` for the always-loaded tier, which is a shrink, so it is allowed. Removing `paths:` (or setting it to `**`) means `cur = 0` and `new = full`, which is growth and is judged. A new file has `cur = 0` and is judged.
- An Edit that adds `@docs/big.md` is growth through the import: `new_t` includes the import's effective size. This is the route a name-only predicate misses.
- Tier is local to the write (User / Ancestor / Repo). This avoids "attribution by reachability", the polarity scripts/rules-hook-budget-lint.sh:26-37 measured as wrong. A repo edit is never refused because the global file is fat; the session-wide sum belongs to the L4 auditor.
- Fail open on every error: no python3, unparseable JSON, unreadable file, timeout. Log an IDL row with disposition `abstained`, the way `_bbw_nlog` does (lines 101-110), so the question "was this write gated?" has an answer.
- No agent-reachable env bypass. The git-identity gate documents why an env override is a one-line total bypass (W/scripts/git-identity-assert.sh:42-57; seams sealed behind `CC_GIT_IDENTITY_TEST=1`). Seal the same way: env budget overrides are honoured only under `CC_IB_TEST=1`. The production override is a reviewed, landed `config/instruction-budget.json` with per-path ceilings that may only be lowered.

### 4.3 Budgets (grounded in the formula and today's sizes)

| Window | per-file `hVe` | total `iRn` |
|---|---|---|
| 200k (e.g. 200k-context subagents/teammates) | max(40000, 30000) = **40,000** | **120,000** |
| 1M (lead sessions; the warning showed 150.0k) | 150,000 | 150,000 |

Recommendation: budget to the lowest window, so the same files never warn on any model the fleet runs, and leave 30k headroom under 1M for conditional and nested loads during a session.

| Budget | Value | Today (measured) | Effect |
|---|---|---|---|
| PER_FILE (any always-loaded file) | 40,000 | slim global 57,882 B / 57,588 u; reso agent-operating-lessons 52,090; personal 51,879; ledger 151,801 | those four are frozen to shrink-or-neutral until under 40k |
| TIER user (`$CFG` CLAUDE.md + rules) | 60,000 | 57,588 + 2,882 = 60,470 | at budget; the board render must stay small |
| TIER ancestor (Project files in dirs strictly above the repo root, e.g. `~/.claude/CLAUDE.md`, `~/.claude/rules/*`, `~/Development/.claude/rules/*`) | 0 | 111,862 + 2,882 + 6,279 = 121,023 | any growth refused; the auditor files the defect until the exclude migration lands |
| TIER repo (Project + Local files at or under the repo root) | 60,000 | reso 247,688; claude-infra ~16k effective; personal 53,421 | reso frozen; the ledger must go conditional or move to docs/ |
| SESSION total (auditor only) | 120,000 (= user + ancestor + repo) | median 197,398; 116/123 sessions > 150k | the auditor files a row until it holds |

These numbers are value calls that belong to the operator. The mechanism does not depend on them; they live in one config file.

## 5. Q3 — Bash-route writes, git hooks, the land gate

- Do not gate Bash in validate-bash.sh. The repo has already argued and settled this for MEMORY.md. W/hooks/memory-index-drain.sh:9-20 says a PreToolUse matcher on a Bash command string is "a denylist over spellings … `>>"$m"`, `tee -a`, `python3 -c`, a heredoc and a `sed -i` are others". The detector instead looks at the file: whatever wrote it, the mtime and size moved. validate-bash's `_wbw_hit` write pre-screen (W/hooks/validate-bash.sh:644-689) is a cost filter for the worker-lease gate and cannot project a post-write size.
- L2 host with zero settings change: `hooks/memory-index-drain.sh` (394 lines), registered PostToolUse `Bash|Write|Edit|MultiEdit` (`jq -c '.hooks.PostToolUse[]' ~/.claude/settings.json`). Its structure is exactly what is needed: builtin stdin read (53), jq guard (55), cwd (57), CFG (60), an mtime+size stamp gate (`_mid_stat` 109-117, the stamp key 120-131 with the bash-3.2 `${k: -120}` trap at 120-127), and a single emitter at 391-393. Caveat: line 101 `LOC=$(mil_locate "$CWD") || exit 0` leaves any session in a repo without a MEMORY.md, and 88-89 exit if the MIM libs are missing. The instruction arm must therefore run between 60 and 81, and its message must leave through the single emitter, with an EXIT trap for the early-exit paths. That is the backup-before-write `_bbw_out`/`_bbw_rewrite_only` pattern (lines 66-82).
  - Arm behaviour: for the repo root of `.cwd`, run one `stat -f '%m %z'` over the always-loaded set (≤ 15 files) and compare with a per-(session_id, repo) stamp. On first sight, record and stay silent. On change with `tool_name == Bash` and growth past budget (same predicate as the gate, invoked as `cc-instruction-budget verdict --observed`), emit 🚨 context naming the file, before→after, the budget and the remedies. When `tool_name` is not Bash, or the command does not mention the file or `.claude/rules`/`CLAUDE`, treat it as unattributed: concurrent sessions share checkouts, so record an IDL row and do not tell this session it did something it didn't.
- Is a pre-commit or land check needed? Yes, as the brake for what L1/L2 cannot attribute or see: machine writers (cc-memory-rotate `>>` at W/bin/cc-memory-rotate:736, cc-mission render, install.sh `cp`), sessions running stale hooks, humans, cloud lanes.
  - claude-infrastructure: add an arm in W/scripts/ship-land.sh beside the rules lint arm (3800-3840). Reuse `selftest_ok` (3379), `arm_nonverdict`, `gate_red`. Own-range semantics: compare the effective size at merge-base with HEAD, per file and per repo tier, and refuse only if the range grew something that ends over budget. That attribution is correct where rules-hook-budget-lint's refusal of whole-file ceilings (its header, lines 26-30) was right to be wary.
  - reso: reso owns its own `scripts/ship-land.sh` and `scripts/hooks/pre-commit` (it sets `core.hooksPath` to `~/.reso/land-tools/scripts/hooks`, which is a snapshot of reso at a sha: `ls -la ~/.reso/land-tools` → `land-tools.d/c9797a18…`; selected in reso `scripts/prepare-cached.sh:51`). Add one call next to `STAGED_MD_FILES` (land-tools copy, pre-commit:25 and :510) to `~/.claude/bin/cc-instruction-budget range --staged`, failing open if the binary is absent. The change lands in the reso repo through reso's own pipeline.
- Global git hooks: none. Do not introduce `git config --global core.hooksPath`. When it is set, git ignores `.git/hooks`, which would silently disarm the identity gate that `scripts/git-identity-assert.sh install` (W:139-170) deploys into each repo's `.git/hooks`. Repos with a local hooksPath (reso ×5, husky, .githooks) would override it anyway. `~/.git-template` only seeds new clones. Do not graft this check onto `githooks/pre-commit`: that is a security gate with sealed seams, and its `--check` mode is the sweep's arbiter (git-identity-assert.sh:16-20).

## 6. Q4 — fleet auditor `bin/cc-instruction-budget`

One Python file. The predicate lives in `hooks/lib/instruction_budget.py`, which is what L1, L2, L3, the rotor and this CLI all call: "one predicate, not two" (git-identity-assert.sh:16-20; the MIM lib header). Deployment comes free through existing globs: install.sh:340 links `hooks/lib/*.py`, and the `cc-*` bin glob lives in the PATH-tools section (~install.sh:1080). The hook resolves the lib through the dereferenced self-path anyway.

Subcommands:
- `measure <file>`: effective units and whether the file is conditional.
- `session --config-dir D --cwd C [--window N] [--json]`: emulates the loader (§2) and prints per-file type and units, per-tier sums, `hVe`/`iRn` for the window, and whether the startup warning would fire (with `ixt`'s rule that over-per-file files are left out of the trigger sum). The prototype /tmp/ibudget/guard-design-proto.py reproduces today's warning (§1); it runs in 66 ms for the reso pair (`time python3 …` → 0.066 total, measured).
- `verdict` (stdin = the PreToolUse payload): `{allow}` or the deny JSON. Used by L1 and L2 (`--observed`).
- `range <gitrange>|--staged [--repo R]`: the L3 ratchet. rc 0 clean, 1 refuse, 2 non-verdict.
- `census [--since 24h]`: the observed population, i.e. `~/.claude/logs/instructions-loaded.log` session_start rows grouped by sid (written by `hooks/instructions-loaded.sh:99-101`, InstructionsLoaded matcher `session_start`). Plus the predicted population: emulate every (config dir from accounts.json) × (distinct repo root seen in the log). Prediction catches a breach before a session hits it.
- `assert` (rc 0 clean / 1 breach / 3 non-verdict) and `file`. `file` copies W/scripts/settings-drift-assert.sh:233-276: `cc-backlog add --project <owner-project> --source cc-instruction-budget --condition instruction-budget-<tier>[-<repo>] --falsifier "cc-instruction-budget assert --tier <tier> [--repo R]" --title "<live numbers + remedy>"`. Condition-keyed means one row per breach class, updated in place rather than one per sweep. The falsifier closes the row by itself when the breach clears. A non-verdict files nothing and claims nothing (settings-drift-assert.sh:226-238). Owners: `user` and `ancestor` tiers go to claude-infrastructure; `repo` breaches go to the repo's project (reso-management-app for the ledger).
- `publish`: writes `~/.claude/state/instruction-budget/loaded-set.txt`, the reachability set from §4.1 item 5, for the L1 pre-screen.
- `selftest`: required by `selftest_ok` in the land gate. It runs the classic RED and GREEN fixtures.

Where it runs: in W/scripts/autonomy-sweep.sh, directly after the settings-drift block (516-521). That puts it above the nothing-new early exit, for the reason given at 507-514 (drift produces no alarms while it accumulates). Call it as `_bounded bash … file`, and capture rc rather than appending `|| true`. Add an hourly cooldown stamp, because breaches move at session timescale and L1/L2 cover individual writes. The job is launchd `com.chrisren.autonomy-sweep` (300 s, loaded; documented at autonomy-sweep.sh:502-505). Also run `publish` on every sweep (cheap) so the L1 reachability set stays fresh.

## 7. File-level implementation plan

| # | File | Change | Lines |
|---|---|---|---|
| 1 | NEW `hooks/lib/instruction_budget.py` | predicate (§4.1), measure (port MIM defs memory-index-measure.sh:64-78 without trim), projection (port `_MIB_JQ_PROJECT` memory-index-budget.sh:84-102), loader emulator (seed: /tmp/ibudget/guard-design-proto.py), tier sums, verdict, deny text, sealed env seams | new |
| 2 | NEW `config/instruction-budget.json` | `per_file:40000, tiers:{user:60000, ancestor:0, repo:60000}, session:120000, deploy_sources:{CLAUDE.global.md:~/.claude/CLAUDE.md, CLAUDE.global.slim.md:~/.claude/CLAUDE.slim.md}, ceilings:{}` | new |
| 3 | NEW `bin/cc-instruction-budget` | CLI from §6 | new |
| 4 | `hooks/backup-before-write.sh` | new `=== INSTRUCTION BUDGET ===` block between 140 and 142. Forkless `case "$FILE"` pre-screen (`*/CLAUDE.md`, `*/CLAUDE.local.md`, `*/.claude/rules/*.md`, `*/.claude*/CLAUDE*.md`, `*/rules.slim/*.md`, `*/CLAUDE.global*.md`, relative spellings, and a loaded-set.txt match). Then lib resolution as at 165-167, a bounded `python3 … verdict`, and the deny emitter as at 176-187 (`EMITTED=1`). | insert at 141 |
| 5 | `hooks/memory-index-drain.sh` | L2 arm between 60 and 81. Turn the single emitter at 391-393 into `_mid_emit` that merges `IB_CTX`+`CTX`, plus an EXIT trap so early exits at 88/89/101/103/119 still deliver `IB_CTX` | 60-81, 391-393 |
| 6 | `bin/cc-memory-rotate` | `rules_cap_reason` (598-616): when the dest loads (`rules_file_loads`) and is unconditional, and the projected effective size is over PER_FILE and growing, echo `dest-over-instruction-budget`. Ordinary rotation already degrades to cold on a route error (1727-1739). Drain mode exits 2 at 888-889, which keeps the line, and the MIB gate holds. On this machine the default dest (situational) is excluded, so the default path is a no-op. | 598-616 |
| 7 | `bin/cc-mission` | `render` (BOARD, line 63) asserts the rendered size is ≤ its ceiling, or truncates with a pointer | ~63, render fn |
| 8 | `scripts/ship-land.sh` | L3 arm after the rules lint arm (3808-3840), same `selftest_ok`/`arm_nonverdict`/`gate_red` shape, `cc-instruction-budget range "$range"` | after 3840 |
| 9 | `scripts/autonomy-sweep.sh` | L4 block after 516-521 (`file` + `publish`, hourly stamp, `log_idl`) | after 521 |
| 10 | reso-management-app `scripts/hooks/pre-commit` + `scripts/ship-land.sh` | call `~/.claude/bin/cc-instruction-budget range --staged` / `range "$range"`, fail-open if absent | reso repo, separate land |
| 11 | NEW `tests/instruction-budget.bats` | modeled on memory-index-budget.bats. Predicate: each name, nested, `paths:` absent/empty/`**`/`src/**`. Measure: frontmatter, column-0 comment, fence exception, em-dash = 1, astral = 2. Projection: Write, Edit, replace_all, MultiEdit. Asymmetry: shrink and neutral on an over-budget file; growth refused; new file over budget refused; adding `paths:` allowed; removing `paths:` judged. A sibling pushing the repo tier over is refused; an excluded file is not counted; `@import` growth is refused. Fail-open: no python3, malformed input. Host e2e through a symlink. A Write that creates a new rules file is judged (pins the pre-142 placement). Env overrides ignored without `CC_IB_TEST=1`. | new |
| 12 | NEW `tests/cc-instruction-budget.bats` | Emulator fixtures: an ancestor `.claude/CLAUDE.md` counted as Project (the defect), symlink dedupe, the `ixt` over-per-file exclusion, window formula 200k→40k/120k and 1M→150k/150k. Census from a fixture log. `file` uses `--condition` and `--falsifier` with a stub `CC_BACKLOG_BIN` (pattern settings-drift-assert.sh:140-174). `range` own-range attribution. `selftest`. | new |
| 13 | `tests/memory-index-drain.bats` (36 tests) + `tests/hook-jq-abstain.bats` (8) | add: the arm fires with no MEMORY.md (pins the pre-101 placement), unattributed sibling growth stays silent, abstains without python3/jq | extend |

Rollout order: 1-3 + 11-12, then 4 (the gate; its deny names the cure), then 5, then 8-9, then 6-7, then 10 in reso. Every step is mechanical: no settings.json edit and no c10 migration. The separate fix for the ancestor defect (a `claudeMdExcludes` entry) is a settings change, so it is an operator-run c10 migration (migrations/README.md). Once it lands, the ancestor tier drops to zero and the auditor's row closes itself.

## 8. Risks

- Live-workflow wedge: the bottle workflow appends to the 151.8k ledger roughly every few hours (69 commits). After step 4, any growth is refused. The cure is a single allowed Write that adds `paths:` frontmatter or moves the ledger to docs/. The deny text must state that cure first. Do not roll out step 4 before the reso owner knows.
- Concurrent attribution in L2: shared checkouts mean a stamp can see a sibling's write. This is mitigated by per-session stamps plus Bash-command mention matching. Anything ambiguous is logged and not told to the session.
- Emulator drift across CC versions: the census uses observed InstructionsLoaded rows as ground truth, and the emulator is only for prediction. Pin the version in `selftest` and re-carve on upgrade (the MIM lib's version-boundary note, memory-index-measure.sh:37-41, is the precedent).
