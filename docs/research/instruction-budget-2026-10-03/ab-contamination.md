# ab-contamination: does production receive the slim arm that the F1 gate measured?

**Answer: no.** Since migration 0042 (account links re-pointed 2026-09-25 11:50, from the symlink mtimes in `ls -la ~/.claude-*/CLAUDE.md`), every session whose cwd is under /Users/chrisren loads slim + full + full rules together. That combination was never gated. It costs more than the full instructions did before the migration. The gate's "-34% cost, non-inferior quality" verdict covers an arm production has never run.

## 1. What the gate measured (static read, all measured from files)

- Runner: `docs/research/token-efficiency-2026-09-23/eval/harness/run.sh`.
  - The cwd is `$FX="$G/runs/<task>/r<rep>/fx"` with `G=${GATE_ROOT:-/tmp/tokeff-gate}` (run.sh:11, 21, 51, 94). Every GATE_ROOT recorded in GATE.md is a `/tmp/tokeff-*` path (GATE.md:404-469, 626-637). That cwd is outside $HOME, so the ancestor walk never reached `/Users/chrisren/.claude`.
  - Config dir: `CLAUDE_CONFIG_DIR="$CCD"`, a real account dir (run.sh:106). Accounts next3, next4 and next (GATE.md method section).
  - It also excluded `$CCD/CLAUDE.md`, `$HOME/.claude/CLAUDE.md`, `$HOME/.claude/rules/00-mission-board.md` and `$HOME/.claude/rules/agent-operating-lessons.md` through `claudeMdExcludes` (run.sh:62-64). The arm's frozen files were copied into `$FX/.claude/` as project memory (run.sh:54-56).
  - So each arm contained only its own files. full = full CLAUDE.md + board + lessons. slim = slim CLAUDE.md + compact board.
- `measure-context.sh:13-21` checked the arms in `$G/context/...` (/tmp) under the same excludes, so it could not have seen the production composition either.
- Gated sizes:
  - Round-4 arms (`eval/round4/arms-MANIFEST.sha256`): full CLAUDE.md sha cecd5a0c… = 106,508 chars (`git show 59c228e90:CLAUDE.global.md`). Slim CLAUDE.md sha d446c60e… = 53,442 chars (`git show d570ed0bf:CLAUDE.global.slim.md`).
  - /context memory as recorded in GATE.md: full 48.2k/48.7k tokens, slim 19.6k/20.1k (GATE.md:22, 203).
- Migration 0042 rests on a false premise (migrations/0042-slim-claude-md-all-accounts.sh:10-11). It says ~/.claude/CLAUDE.md is reached only through each account's symlink. It does not account for the ancestor walk. Its verify line (:5) checks only the symlink targets.

## 2. Why pre-migration loaded the full file only once (measured + binary read)

- Binary 2.1.284 (/tmp/cc284.strings, at offset ~20456431), functions `ket`/`mY`:
  - `ket` skips a path whose normalised form is already in `processedPaths`.
  - `mY` adds the symlink's resolved target to `processedPaths` (`if(ge){let Ee=Gp(Y);if(r.has(Ee))return[];r.add(Ee)}`).
- Before 0042, each account's CLAUDE.md was a symlink to ~/.claude/CLAUDE.md. The user load therefore recorded `/Users/chrisren/.claude/CLAUDE.md` as processed, and the ancestor project load of that same path was skipped. The same applied to rules, because the account `rules` was a symlink to ~/.claude/rules.
- 0042 re-pointed the links to CLAUDE.slim.md and rules.slim. The resolved paths stopped matching, so the dedupe stopped firing.
- Empirical check, probe c8: a scratch config dir `/tmp/ibudget/ccd-premig` with CLAUDE.md pointing to ~/.claude/CLAUDE.md and rules pointing to ~/.claude/rules. `/context` from the home scratch dir lists User rows only. There is no Project row for ~/.claude/CLAUDE.md.
- Historical evidence: `measure/static-prefix.md:50-59` (2.1.280, pre-migration, cwd = claude-infrastructure and reso) also has no Project row for ~/.claude/CLAUDE.md.

## 3. Sentinel probes (8 runs, binary 2.1.284, `--model haiku`, CLAUDE_CONFIG_DIR=~/.claude-quaternary)

Each sentinel asks the model to recall content that is not in the prompt.

| Sentinel | What it asks for | Where it lives |
|---|---|---|
| FULL | backlog id `4e6a51df2a84` | ~/.claude/CLAUDE.md:713 only (grep shows it is absent from slim and rules.slim) |
| SLIM | completion "loaded under an A/B test" | CLAUDE.slim.md only (`grep -c` gives 0 in the full file) |
| RULES | `RULESLOAD-OK-A7F3` | ~/.claude/rules/agent-operating-lessons.md only |
| NEG | `NEGCTRL-Q7ZK-UNWRITTEN` | nowhere (grep found it in no file) |

Probe setup:
- Prompt in /tmp/ibudget/prompt.txt, runner in /tmp/ibudget/probe.sh.
- Flags: `--tools ""`, no MCP, pane environment variables unset.
- Outputs in /tmp/ibudget/*.out.

| # | cwd | settings | FULL | SLIM | RULES | NEG |
|---|---|---|---|---|---|---|
| p1 | ~/Development/.worktrees/ibudget-probe | default | invalid (`--max-turns 1` hit, no answer) | | | |
| p2 | same | default | **4e6a51df2a84** | **loaded under an A/B test** | **RULESLOAD-OK-A7F3** | no |
| p3 | same | `claudeMdExcludes: [/Users/chrisren/.claude/CLAUDE.md, /Users/chrisren/.claude/rules/**]` | NONE | yes | NONE | no |
| p4 | /tmp/ibudget/probe-tmpcwd | default | NONE | yes | NONE | no |

`/context` "Memory files" tables (counted tokens):

| # | cwd / settings | Rows | Total |
|---|---|---|---|
| c5 | home scratch dir, default | User slim 15.3k, User rules.slim board 905, **Project ~/.claude/CLAUDE.md 31.9k**, **Project ~/.claude/rules/00-mission-board.md 905** (the board again), **Project ~/.claude/rules/agent-operating-lessons.md 1.8k** | **50.8k** |
| c6 | home scratch dir, with the excludes | User slim 15.3k, User board 905 | **16.2k** |
| c7 | reso-management-app, default | the 5 rows from c5 + reso CLAUDE.md 10.5k + ledger 48.6k + reso lessons 14.7k + agent-teams 2.3k (= the 9 files in the startup warning) | **133.4k** |
| c8 | pre-migration-shaped scratch config dir (unauthenticated, so the counts are estimates) | User CLAUDE.md 27.9k + User board + User lessons; no Project ~/.claude/CLAUDE.md | 30.3k |

Two more findings from these runs:
- c6 still omits `agent-operating-lessons-situational.md`. c8 has no settings.json and loads it. So `--settings` claudeMdExcludes were merged with the shared settings.json excludes, not substituted for them. This is inferred from the two runs.
- The exclude did not touch the account's User slim file, because the matcher sees the path ~/.claude-quaternary/CLAUDE.md (p3, c6).

## 4. Per-session global instruction load (chars measured with python `len(open().read())`)

| Composition | Files | Chars | Tokens |
|---|---|---|---|
| **Production today** (any cwd under ~) | slim 57,545 + board 2,956 + full 111,752 + board 2,956 + lessons 6,276 | **181,485** | 50.8k (c5, counted) |
| Gated slim arm | slim 53,442 + compact board | about 55-57k | 19.6-20.1k (GATE.md) |
| Gated slim arm, today's files | slim 57,545 + board 2,956 | 60,501 | 16.2k (c6) |
| Pre-migration shape, today's files | full 111,752 + board 2,956 + lessons 6,276 | 120,984 | about 34.6k (c5 row sum, estimated) |
| Gated full arm | full 106,508 + full board + lessons | | 48.2-48.7k (GATE.md; the old board was 13.9k chars) |

What this means:
- Production carries **+50% chars and about +47% tokens** compared with pre-migration (estimated from the counted rows). That is the reverse of the -34% the gate certified.
- Compared with the slim arm, production is **3.0x the chars**.
- The global layer alone (181.5k) is over the 150k total-instructions limit, so every home-cwd session warns, in any repo.
- For reso: 181,485 + 247,664 (reso CLAUDE.md 35,964 + ledger 151,742 + lessons 52,130 + agent-teams 7,828) = 429,149 chars. The warning reported 428.1k; the gap of about 1k is probably HTML-comment stripping (inferred).
- With the ancestor excluded, reso drops to 308,165 chars. That is still over the limit because of reso's own files, a separate problem.

## 5. Does the gate verdict apply to production?

**No, for two independent reasons.**

1. **Composition.** Production runs a union arm, slim + full + full rules. It is a superset of the full arm's content, plus a second, reworded copy of most rules, plus the mission board twice.
   - Cost: measured higher than pre-migration, not 34% lower.
   - Quality: never measured. It contains all the full-arm rules, but with paraphrased duplicates whose wording differs. Whether those conflict is untested (inferred risk).
2. **File drift.** The deployed slim file is no longer the gated file.
   - `shasum` gives d28f899a… against PIN d446c60e… The size is 57,545 chars against the gated 53,442.
   - It has been edited 6 times since the gate (`git log -- CLAUDE.global.slim.md`: d362886 through 49d1535).
   - `cc-instructions-variant status` reports `CLAUDE.slim.md: STALE`.
   - 0042's own pin rule says an ungated variant does not ship. The pin is checked only at apply time.

## 6. Durable-fix notes (scope: what the evidence supports)

- **Measured to work:** `claudeMdExcludes` = [`/Users/chrisren/.claude/CLAUDE.md`, `/Users/chrisren/.claude/rules/**`] removes exactly the three ancestor rows and leaves the account's slim User memory intact (p3, c6). Putting it in the shared ~/.claude/settings.json would reach all four accounts.
  - **Caveat (binary read):** the matcher is type-blind across User, Project and Local. A session started with CLAUDE_CONFIG_DIR unset (default ~/.claude: crons, launchd jobs, a bare `claude`) has User memory at exactly `/Users/chrisren/.claude/CLAUDE.md` and would load no global instructions.
  - Likewise, after `cc-instructions-variant reset <acct>`, that account's rules resolve to ~/.claude/rules. c8 shows User rows reported at the resolved path, so a reset account may lose its rules (inferred; test before relying on it).
- **Alternative that restores the original invariant:** make ~/.claude/CLAUDE.md (and ~/.claude/rules) resolve to the same file as every account's link. The realpath dedupe in `mY` then suppresses the ancestor copy.
  - This needs install.sh to stop `cp`-ing over ~/.claude/CLAUDE.md. If it kept doing so, the copy would follow a symlink and overwrite the variant file.
- **Regression test:** an auth-free `/context` probe catches this whole class of defect. c8 showed `claude -p /context` works with an unauthenticated scratch config dir. Run it from a cwd under $HOME and assert that no memory file appears twice by content and that no Project row is under ~/.claude/.
  - The gate's own `measure-context.sh` should add a production-shaped run (home cwd, no excludes) as a third row.

## Evidence index

- Probe outputs: /tmp/ibudget/p1-home-default.out, p2-home-default.out, p3-home-excludes.out, p4-tmp-default.out, c5-home-default.out, c6-home-excludes.out, c7-reso-default.out, c8-premig-symlink.out (plus the matching .err files).
- Probe prompt and runner: /tmp/ibudget/prompt.txt, /tmp/ibudget/probe.sh. Pre-migration scratch config dir: /tmp/ibudget/ccd-premig.
- Scratch cwd created as the brief asked: /Users/chrisren/Development/.worktrees/ibudget-probe (empty, not a git repo).
- Side effect: probes p2-p4 and c5-c7 wrote normal session transcripts under ~/.claude-quaternary/projects/ (inherent to running `claude`). c8's state went to /tmp/ibudget/ccd-premig.
