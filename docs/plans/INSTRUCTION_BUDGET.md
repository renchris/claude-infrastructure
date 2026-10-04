---
status: in-progress
---

# Instruction budget — always-loaded instructions under 120k per session, and kept there

Scope (frozen 2026-10-03): eliminate the over-limit always-loaded instruction load fleet-wide, durably:
(1) remove the double load of the global instructions, (2) bring reso-management-app's always-loaded
rules under budget (bottle ledger, lessons, CLAUDE.md), (3) add a chokepoint guard, land ratchets and a
fleet auditor so the load cannot grow back under 15+ concurrent sessions.

Trigger: a reso session's startup warning — `9 instruction files add up to 428.1k chars, over the
150.0k-char total limit · largest: .claude/rules/bottle-generation-ledger.md (151.7k),
~/.claude/CLAUDE.md (111.6k), ~/.claude-quaternary/CLAUDE.md (57.1k)`.

Research (7 agents, all claims measured or marked inferred): `docs/research/instruction-budget-2026-10-03/`
— `ab-contamination.md`, `default-configdir.md`, `fleet-census.md`, `reso-ledger.md`, `reso-lessons.md`,
`guard-design.md`, `critic.md` (the critic's binary probes overrule the slots where they disagree).

## Phase 0 — Agent Team Orchestration

**Execution locus per wave:** W1 = **S** · W2 = **S** · W3 = **S** (one dispatched session each, fired
in parallel; the three touch disjoint files — W1 and W2 share no file in claude-infrastructure, W3 is
another repo).

**Lead context budget:** the lead (pane that wrote this plan) holds research synthesis only; it fires the
three waves, collects their pings, verifies the end state with the census, and closes. Succession point:
recycle after the waves are fired if fill passes 35% while waiting.

| Wave | Repo | Owns (files) | Lands when |
|---|---|---|---|
| W1 global dedupe | claude-infrastructure | `install.sh`, `bin/cc-instructions-variant`, `lib/config-mirror.zsh`, `migrations/0053-*`, their bats, `.claude/CLAUDE.md` (sync note), deploy-parity tests | gate-green |
| W2 guard + auditor | claude-infrastructure | `hooks/lib/instruction_budget.py`, `config/instruction-budget.json`, `hooks/backup-before-write.sh`, `scripts/ship-land.sh` (one arm), `bin/cc-instruction-budget`, `scripts/autonomy-sweep.sh` (one call), bats | gate-green; enforce flag ON only after W3's ledger split is on reso origin/main |
| W3 reso | reso-management-app | `.claude/rules/*`, `.claude/bottles/generation-ledger.md`, `CLAUDE.md`, reso pre-commit + `scripts/ship-land.sh` run_statics + a vitest | gate-green (reso `/ship` is free, reso CLAUDE.md:566) |

## Measured state (2026-10-03)

| | chars per session |
|---|---|
| global layer today (slim user + full `~/.claude/CLAUDE.md` via ancestor walk + both rules dirs) | 181,485 |
| global layer, pre-0042 shape (full, deduped) | 120,984 |
| global layer, the arm the F1 gate certified (slim only) | 60,501 |
| reso-management-app total (the warning) | 428.1k (CC) / 429,149 (python len) |
| reso always-loaded repo tier (CLAUDE.md 36k + lessons 52.8k + agent-teams 7.9k + ledger 153k) | 247,664 |
| every other repo today | 180.7k–233.6k (all over 150k) |

Binary facts (2.1.284): per-file warning limit = max(40k, window × 5% × 3 chars/token), total =
max(120k, per-file) → 150k/150k on a 1M window, **40k/120k on a 200k window**. Warning only; files over
4 MiB are skipped. The real cost is context tokens on every session start (reso: 133.4k counted tokens).

## Decisions

**D1 — the global double load is a symlink-dedupe regression from migration 0042 (conviction 97%).**
CC records a symlink's resolved target in `processedPaths`; before 0042 each account's `CLAUDE.md` linked
to `~/.claude/CLAUDE.md`, so the ancestor-walk copy was skipped. 0042 re-pointed the links at
`CLAUDE.slim.md`, so since 2026-09-25 every session loads slim + full + full rules. The F1 gate never saw
this: its harness ran under `/tmp` with `claudeMdExcludes` (run.sh:11,62-64).

**D2 — fix shape: canonical file, not excludes (conviction 92%).** `~/.claude/CLAUDE.md` becomes a
regular file holding the selected global variant (slim, per the 0042 all-accounts ruling), the full text
deploys to a non-loaded name (`~/.claude/CLAUDE.full.md`), `~/.claude/rules/` holds only the slim rule
set, and every account's `CLAUDE.md`/`rules` link points back at `~/.claude/CLAUDE.md`/`~/.claude/rules`.
Measured by the critic on 2.1.284, 2.1.278 and 2.1.114: no double load, no `claudeMdExcludes`, no launcher
dependency. Rejected: `claudeMdExcludes` in the shared settings (type-blind — a default-config-dir
session then loads **zero** memory files, measured); a symlinked `~/.claude/CLAUDE.md` (still
double-loads on 2.1.114, and install.sh:1043 reverts it); launcher `--settings` injection (misses
qa-nightly, claude-prev*, bare headless runs).

**D3 — two steps, so the fleet benefits before the operator acts.** Step 1 (agent, via deploy-live):
install.sh deploys the selected variant to `~/.claude/CLAUDE.md` and moves the stale
`~/.claude/rules/agent-operating-lessons.md` out of the loaded rules → slim + slim ≈ 124k. Step 2
(operator, c10): migration 0053 re-points the account links (0042's own documented rollback,
`cc-instructions-variant reset <acct>`) → ≈ 60k.

**D4 — variants become global (conviction 90%).** Accounts are interchangeable (operator ruling
2026-09-23, all-or-none). Any per-account divergence of the `CLAUDE.md` target re-creates the double load,
so `cc-instructions-variant set <acct>` must refuse a target other than `~/.claude/CLAUDE.md`; the
variant is chosen globally, and future A/Bs run only in `/tmp` fixtures.

**D5 — reso ledger: head at a NEW path, body moved (conviction 91%).** Keeping the head at the old path
fails under concurrency (a concurrent append rebases into a conflict whose other side is the whole old
file — critic, two git simulations). `paths:` frontmatter fails: paid fires are Bash
`pnpm tsx scripts/bottle-gen-production.ts` calls, and 16 of 24 paid-fire transcripts read no matching
file first. `docs/` is capped at 180 files. So: `git mv` the ledger to
`.claude/bottles/generation-ledger.md` (pure rename), write the ≤6k head (operator rulings, status, money
guards) at `.claude/rules/bottle-generation-rules.md`, repoint the 7 pointers, add a land-time tombstone
refusing re-creation of the old path, and have `printReferenceLedger` (bottle-gen-production.ts:971) print
the slug's guard sections on every paid fire.

**D6 — reso lessons: compress, do not demote (conviction 85% — recall of demoted hooks is unmeasured).**
Every one of the 76 bullets already links a body; 43 exceed the 420-byte hook budget because evidence was
pasted in. Rewrite each to a ≤350-char rule-stating hook in `- [title](link) — rule` form (all stay
resident), cut `agent-teams.md` to the reso-only delta (it is stale), and remove the sections of reso
`CLAUDE.md` that restate global rules. Target repo tier ≤ 60k.

**D7 — guard: one predicate, four arms (conviction 90%; budgets from the binary's 200k-window floors).**
`hooks/lib/instruction_budget.py` + `config/instruction-budget.json` is the single definition. Arms:
Write/Edit/MultiEdit gate in the already-registered `hooks/backup-before-write.sh` (no settings change);
land ratchet in `scripts/ship-land.sh`; reso's own land check (W3); fleet auditor `bin/cc-instruction-budget`
from `scripts/autonomy-sweep.sh`, which also asserts the D2 invariant (no instruction file loaded twice by
realpath). Budgets: 40k per always-loaded file; per-session tiers user 60k · ancestor 0 · repo 60k;
conditional (`paths:`) rules get their own 40k per-file cap so `paths:` is not an unbudgeted escape. Only
**growth** past budget is refused; shrinking or neutral edits always pass; files already over are
shrink-only. Deny messages name the destination (`.claude/bottles/…`, `docs/lessons/…`, the
situational file), not "add paths:".

## Known issues (not in scope)

- The deployed `CLAUDE.slim.md` (sha d28f…, 57.5k) has drifted from the file the F1 gate certified
  (pin d446…, 53.4k); `cc-instructions-variant status` reports STALE. Re-gating is the operator's call.
  2026-10-04 (claude-api audit, item hillclimb-09): the F1 PASS was also read on the same 20 tasks that
  chose its edits, so it is a train score. The re-gate that settles both is a held-out confirm: 10 new
  frozen tasks (T22-T31, weighted to close honesty, one-command hand-over, refused push, open plan work),
  arms built from the CURRENT slim + close rules vs the full text, 5 reps per arm ABBA under the
  unchanged agg.py rule, plus ~20 round-4 dossiers re-judged blind as a judge-drift anchor; headline =
  held-out delta. Cost ≈ 100 runs ≈ 3-10 weekly pp across 3 accounts, above the no-ask band.
  Detail: `docs/research/claude-api-audit-2026-10-04/REPORT.md` § 3.
- Whether any main session runs on a 200k-window model is unmeasured (haiku appears in 174 transcripts in
  3 days); the 40k per-file budget is chosen so the answer does not matter.

## Waves

### W1 — global dedupe (S)

1. `install.sh` (~L1007-1060): deploy `CLAUDE.global.md` → `~/.claude/CLAUDE.full.md`; deploy the selected
   global variant (registry default `slim`; `full` selects `CLAUDE.global.md`) → `~/.claude/CLAUDE.md` as a
   regular file (never a symlink). Rules: `~/.claude/rules/` contains exactly the selected variant's rule set.
   Move `~/.claude/rules/agent-operating-lessons.md` (a stale doc about rules loading) to a non-loaded path.
2. `bin/cc-instructions-variant`: a global `set slim|full` (records in `~/.claude/instruction-variants`,
   logs to the jsonl); `set <acct> <variant>` refuses any target but `~/.claude/CLAUDE.md`; `status`
   reports a DUPLICATE when any account link resolves elsewhere. `lib/config-mirror.zsh`
   `_cc_instructions_variant_target` follows.
3. `migrations/0053-*.sh` (c10): re-point every account's `CLAUDE.md` → `~/.claude/CLAUDE.md` and
   `rules` → `~/.claude/rules`, `--dry-run` / `--confirm all-accounts`; verify step = the auth-free
   `claude -p /context` probe from a `$HOME` cwd showing no Project row under `~/.claude/` (fallback:
   realpath check). File the run as an operator step (`cc-backlog needs … --class needs-human --run …`).
4. Update every consumer that assumes `~/.claude/CLAUDE.md` is the full text (deploy-parity tests, this
   repo's `.claude/CLAUDE.md` sync note, the slim header pointer). Bats for install + variant + mirror.

### W2 — guard + auditor (S)

Per D7 and `guard-design.md` (file:line plan there) with `critic.md`'s corrections. Enforce flag ships OFF
and flips ON only once reso origin/main no longer has `.claude/rules/bottle-generation-ledger.md`
(`git -C ~/Development/reso-management-app fetch -q && ! git -C … cat-file -e origin/main:.claude/rules/bottle-generation-ledger.md`).
`cc-instruction-budget census|assert|file`; the census must reproduce the 428.1k warning on the pre-change
reso tree (it is the method of `tools/census.py`).

### W3 — reso (S)

Per D5/D6, `reso-ledger.md`, `reso-ledger-head.proposed.md`, `reso-lessons.md`, `reso-lessons-plan.tsv`.
Coordinate with the live bottle session first (it may append rows): re-apply any rows it appended to the
body file. Land a reso size check in pre-commit + `scripts/ship-land.sh` run_statics + a vitest under
`test:unit` (same budgets as D7; tombstone on the old ledger path).

## Acceptance

- `cc-instruction-budget census` (or `tools/census.py`): every repo ≤ 120k after W1 step 2; reso ≤ 120k.
- No instruction file loads twice (auditor assert green; `/context` probe from `$HOME` shows no
  `~/.claude/` Project row after migration 0053).
- A Write growing an always-loaded file past 40k is refused with a message naming the destination.

## Progress

- 2026-10-03 — research complete, plan written (this commit).
- 2026-10-03 — W1 step 1 landed and converged: bea3da8d5 (install.sh: selected variant → `~/.claude/CLAUDE.md`,
  full → `CLAUDE.full.md`, stray rules retired; deploy-parity follows), db0084cda (`cc-instructions-variant`
  global `set`, per-account `set` refused, DUPLICATE in `status`; one mission-board text), 80ef1543c
  (migration 0053, c10, staged), 110c9d393 (docs). Live: `cmp ~/.claude/CLAUDE.md ~/.claude/CLAUDE.slim.md`
  identical, `~/.claude/rules` = board only, 0053 `--dry-run` clean. Step 2 is the operator's: backlog
  `b154e11d31b9` (run 0053). Learned: the config mirror must keep honouring 0042's per-account lines until
  0053 removes them, or every account is re-pointed at the next session start without the operator.
- 2026-10-03 — W2 landed: 2b6e0faaf (predicate `hooks/lib/instruction_budget.py`, `config/instruction-budget.json`,
  `bin/cc-instruction-budget`, Write/Edit gate in backup-before-write.sh above its fast exit), 94ccad0eb (bats:
  gate 12 + auditor/ratchet 10), 6830823be (ship-land ratchet, own-range), 860117bf9 (autonomy-sweep hourly
  `file` + `publish`), 273d08f44 (`enforce: true`, after reso origin/main dropped the old ledger path). Census
  reproduces the 428.1k warning (reso, account cfg: 9 files, 430,996 = 428.1k + ledger growth since). Decided:
  `CLAUDE.global.slim.md` is budgeted as user tier, `CLAUDE.global.md` not at all (D2 deploys it non-loaded);
  a file in the user tier is not also counted as ancestor; `enforce` governs gate and ratchet together. Fixed a
  research-census bug: `paths\s*:` crossed the newline, so a `paths:` YAML list read as a scalar. Not done (not
  in W2's file set): guard-design's Bash-route detector (memory-index-drain.sh), cc-memory-rotate and cc-mission
  render pre-checks. Pre-existing reds, not W2's: autonomy-sweep.bats 50 and 52 fail at e4ade9394 too.
- 2026-10-03 — W3 landed on reso origin/main 5a883b897..d8d193f17: always-loaded repo tier 250,574 → 57,464
  (CLAUDE.md 32.3k · lessons 20.2k, 76/76 hooks kept · `bottle-generation-rules.md` head 4.3k · agent-teams
  0.7k). Ledger `git mv` to `.claude/bottles/generation-ledger.md`, 0 rows lost; the live bottle session's
  next appends went to the body (b863f5883), the old path stays absent. reso size check in pre-commit,
  ship-land run_statics and a vitest, with a tombstone on the old path.
- 2026-10-03 — W4 (follow-on, auditor row 1f0c1b48405b): personal lessons file 54,522 → 11,127 on master
  9cd9239, 34 hooks kept, bodies verbatim in docs/lessons/; `assert --class repo-personal` GREEN.
- 2026-10-03 — follow-on (auditor row 473335c307b2, user tier 60,114 > 60,000): `cc-mission` compact board
  capped at 2,400 chars, rows past it collapse to one "+N more" line (3e870cbc7). Dropped as covered by the
  land ratchets + hourly auditor: W2's Bash-route detector and the cc-memory-rotate pre-check.
- 2026-10-03 — follow-on (auditor row 473335c307b2, `~/.claude/CLAUDE.md` 57,231 > 40,000 per file): the slim
  variant is now two always-loaded files. Its Session Close Protocol moved verbatim to
  `CLAUDE.rules.slim.10-session-close.md` (30,293), which install.sh copies to `~/.claude/rules/10-session-close.md`
  whenever slim is selected (and retires when full is); `CLAUDE.global.slim.md` is 26,939. Decided: split, not
  cut. The loaded text is byte-identical, so the F1-gated wording is untouched and the user tier stays where it
  was (about 59.5k of 60k); cutting 17k of rules to fit one file would be an ungated behavior change, and
  re-gating is the operator's call (Known issues). deploy-parity gained a leg for the rule copy. Any real
  token saving in the user tier still needs a gated slim round.
- Remaining: the operator runs migration 0053 (backlog b154e11d31b9) → global layer ≈ 60k, DUP rows clear.
