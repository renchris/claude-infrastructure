# reso-lessons: reso-management-app's always-loaded files (CLAUDE.md, lessons, agent-teams)

Scope: the three always-loaded reso files apart from the ledger. Everything here was done read-only.
Reso checkout: HEAD `2738a13bb`, detached and equal to `origin/main`. Evidence: `git diff --stat HEAD origin/main -- CLAUDE.md .claude/rules` returned nothing.
reso-qa-runner (`2738a13bb`) and reso-management-app-release (`9b64eaf24`) are clones of the same remote and have byte-identical copies of all three files (`wc -c`). A trunk fix reaches all three once they update. There are 40 worktrees (`git worktree list | wc -l`), and each keeps its old bytes until it rebases.

Supporting data:
- `/tmp/ibudget/reso-lessons-bullets.tsv`: one row per lesson bullet with line, chars, body target and body size.
- `/tmp/ibudget/reso-lessons-plan.tsv`: one row per bullet with the proposed tier and body status.
- `/tmp/ibudget/reso-lessons-overlap.txt`: 6-word-shingle overlap with the global files.

## 0. Reconciling the startup warning

I took python `len()` of the 9 files that load in a reso session (measured):

| file | chars |
|---|---|
| reso `.claude/rules/bottle-generation-ledger.md` | 151,742 |
| `~/.claude/CLAUDE.md` (full, loaded as PROJECT memory by the ancestor walk) | 111,752 |
| `~/.claude-quaternary/CLAUDE.md` (= CLAUDE.slim.md) | 57,545 |
| reso `.claude/rules/agent-operating-lessons.md` | 52,130 |
| reso `CLAUDE.md` | 35,964 |
| reso `.claude/rules/agent-teams.md` | 7,828 |
| `~/.claude/rules/agent-operating-lessons.md` | 6,276 |
| `~/.claude/rules/00-mission-board.md` | 2,956 |
| `~/.claude-quaternary/rules/00-mission-board.md` | 2,956 |
| **total** | **429,149** |

The warning said 428.1k across 9 files. The file count matches and the ~1k gap is consistent with edits made since. That last point is inferred.
**The three files in scope total 95,922 chars**, which is 22% of the load. The ledger is a separate question.

## 1. agent-operating-lessons.md: measured

Measured with a python parse of lines starting `- `:

- 52,130 chars / 52,798 bytes. 76 bullets in 4 sections:

  | section | bullets | chars |
  |---|---|---|
  | Verification & evidence | 38 | 29,406 |
  | Fires/recycles | 15 | 6,413 |
  | Environment | 10 | 4,826 |
  | Memory/landing | 13 | 9,945 |

  Bullets make up 50,590 chars and non-bullet text 1,465.
- Chars per bullet: mean 666, median 622, max 2,056 (line 115).
  - 47 bullets are over 350 chars, 43 over 420 (the infra lint's default `RULES_HOOK_BUDGET=420`, counted in bytes), 41 over 600 and 18 over 1,000.
- **76 of 76 bullets already point at a body.** The pointer is `→ \`name.md\`` and every target exists in `~/.claude/projects/-Users-chrisren-Development-reso-management-app/memory/` (`os.path.exists`: 76/76).
  - So reso already has the two tiers by structure. The failure is the same one infra had on 2026-09-17: evidence was pasted into the hook, and nothing enforces the limit.
- **The evidence is mostly in the bodies already.** For the 43 bullets over 420 bytes, I took each bullet's distinctive tokens (code spans, numbers, capitalised identifiers) and checked whether they appear in its linked body:
  - 36 bullets (36,181 chars) are mostly covered (≥35%) and can be cut to hooks without losing evidence.
  - **7 bullets (7,462 chars) are orphans**: lines 45, 61, 94, 96, 97, 99, 116. Their evidence exists nowhere except the bullet. Spot-checks:
    - `grep -c 'failures\|moet'` on the environmental-refusal body => 0, so line 61's workflow-dead-agents lesson is not in its own body.
    - `grep -c 'ref-image2\|secondRef'` on the declared-capability body => 0.

    These need a body written before the bullet is cut.
- **Shared bodies.** One body file serves several separate lessons:
  - `reference-bottle-photography-per-bottle-pipeline.md`: 9 bullets.
  - `reference-an-environmental-refusal-filed-as-a-verdict-is-permanent.md`: 4.
  - `reference-the-land-path-skips-its-own-test-gate.md`: 3.
  - `reference-a-declared-capability-can-be-a-no-op.md`: 2.

  The infra lint's DUPLICATE arm refuses this shape (`scripts/rules-hook-budget-lint.sh:140-152`).
- **Dead text.** Line 35 (1,013 chars) is struck through and marked SUPERSEDED 2026-09-22 (commit `bb3cf85b4`). Its two "…and the SAME gate" siblings (36, 37) repeat the same body.
- **Domain bullets in an "unscoped" file.** 10 bullets are about bottle image generation only: 42, 43, 44, 46, 59, 62, 64, 65, 66, 115, totalling 13,754 chars, 26% of the file.
  - Measured on remy-martin-vsop, titos and so on. Mostly committed on 2026-09-12/13 (`git log -- .claude/rules/agent-operating-lessons.md`).
  - The file's own header says the lessons are unscoped because "they bear on any work here, not on one surface". These 10 contradict that.
  - The repo already has a path-scoped home for them: `.claude/rules/bottle-reference-sourcing.md`, `paths: scripts/bottle-gen-*.ts …`.
- **Stale header.** Lines 14-20 say `~/.claude/rules/` is "measured dead". `~/.claude/rules/agent-operating-lessons.md:1-9` says the opposite ("THIS DIRECTORY LOADS EVERYWHERE … CORRECTED 2026-09-03"), and the lead's finding agrees.
- **Duplication with global and reso CLAUDE.md is small.**
  - Verbatim: 6-shingle overlap with `~/.claude/CLAUDE.md` is 0.0%, CLAUDE.slim.md 0.0%, `~/.claude/rules` 0.2%, reso CLAUDE.md 0.0% (overlap.txt).
  - By topic (judged by targeted grep and reading), 4 bullets restate rules held elsewhere:
    - 70 "fire, don't offer" vs slim `CLAUDE.slim.md:372` and the Follow-On Gate.
    - 112 "▶ Run this only for what you cannot run" vs Manual-Command Delivery (`CLAUDE.slim.md:376-395`).
    - 90 "project disable beats local enable" vs reso `CLAUDE.md:525-528`. This is an internal duplicate.
    - 30 two-dot range vs reso CLAUDE.md § Local main is a lagging cache. Partial.

  So dedup is a minor lever. **Bullet length is the main one.**

## 2. reso CLAUDE.md: measured sections and duplication

35,964 chars. Measured sizes (python, by heading) and the duplicate or move each one has:

| lines | section | chars | finding |
|---|---|---|---|
| 24-40 | Agent Teams (Default…) | 1,125 | Same rule as global `~/.claude/CLAUDE.md:173` and `CLAUDE.slim.md:72`. It is also restated at `.claude/rules/agent-teams.md` and Critical Rules Reinforcement #0, so one rule appears 4 times. Stale versions (2.1.114/2.1.183; live is 2.1.284). Contradicts global: global makes a **dispatched session** the default for an implementation wave. |
| 41-56 | Concurrent Sessions — Worktree Isolation | 1,311 | About half restates global `CLAUDE.md:349-368` (frozen lockfile, never symlink node_modules, rerere, `.worktreeinclude`, serialize migrations). Reso-only: `enableGlobalVirtualStore`, `drizzle/db.db` WAL, `_journal.json idx`, `new-worktree.sh`. |
| 57-86 | Local `main` is a LAGGING CACHE | 1,772 | The rule plus the `git show` block is about 600 chars. The rest is the 2026-08-05 incident story, which belongs in a body. |
| 87-101 / 587-end | Critical Rules + Critical Rules Reinforcement | 762 + 2,565 | The reinforcement repeats Critical Rules 1,2,7,8 (items 1-4), Agent Teams (item 0), and global research-subagent "no cap" (item 6, cf. `CLAUDE.md:286-290`). New content: only item 5 (TOCTOU ownership) and item 7 (Path F `min_machines_running`). |
| 135-286 | Engineering Principles | 7,186 | About 4.6k is generic, not about reso (Fix Observed / Systemic / Decision Framework / Absolute Best / Reconciling). Body already exists at `docs/reference/ENGINEERING_PRINCIPLES_BACKGROUND.md` (3,513 bytes). Zero-Latency Navigation (1.7k) and Direct Imports (0.8k) are reso-specific. |
| 286-335 | Security Rules | 2,194 | 31% 5-shingle overlap with path-scoped `.claude/rules/api-security.md` (`paths: src/app/actions/**, src/app/api/**`). |
| 397-443 | Pusher / Batch | 1,373 + 506 | Batch: 21% overlap with `replicache.md`. Both are candidates for path-scoping. |
| 443-461 | Quick Commands & Infrastructure | 3,722 | The Placement-policy bullet (about 1.6k) is tenant-provisioning-only. Its comparison already lives in `docs/auth-tenancy/README.md`. |
| 467-513 | UI Design with ui.sh + Panda | 2,534 | Scoped by its own text to `src/app/(preview)/**` + `src/components/ui/**`, so it is a path-scoped rule (sibling of `design-surfaces.md`). |
| 513-547 | Browser Verification (opt-in) | 2,270 | The recipe is about 500 chars. "Why it was flipped" plus the 11/11 coverage is evidence. Duplicates lessons line 90. |
| 547-587 | Session Close (reso gate-map) | 3,202 | Reso-specific, but about 1.2k is the 2026-08-02 history of the /ship gate being lifted. |

Verbatim overlap with the global files is near 0 (max 5.1% full / 1.7% slim, on Agent Teams). The duplication is restated **rules**, not copied text, so a shingle or exact-match lint cannot find it.

## 3. agent-teams.md: measured

7,828 chars, no `paths:`, comment at line 2 says it "loads unconditionally every session".

- 11.1% 6-shingle overlap with the global `~/.claude/skills/agent-teams/**/*.md` (34,006 chars, loaded on demand).
- The skill already carries this file's named incidents: `validators-p0`, `tp-assignee`, "Brief Discipline", "Per-Teammate Effort" (`grep` => True for each; "Teammate Sizing" heading False).
- Stale content:
  - It points at `~/.claude/rules/agent-teams.md`, which does not exist (`ls ~/.claude/rules` shows only 00-mission-board.md and agent-operating-lessons.md).
  - It names the allowlist model `claude-opus-4-8` and runtimes 2.1.114/2.1.170/2.1.183.
- Effective reso-specific delta: estimated at under 1k, by reading.

## 4. The infra convention, and whether it works on reso as-is

- **Convention.** The header of claude-infrastructure `.claude/rules/agent-operating-lessons.md` (worktree copy) sets two tiers:
  - ONE hook of ≤ ~350 chars per lesson, linking `../../docs/lessons/<slug>.md`.
  - The body, unbounded, in that `docs/lessons/` file.
- **Infra files.** Resident file 9,871 B. A situational half, `agent-operating-lessons-situational.md`, is 78,013 B. New lessons go to the situational half, and a resident add needs `RULES_RESIDENT_ADD_OK=1`.
- **Lint.** `scripts/rules-hook-budget-lint.sh` has these arms: BODYLESS `](.)`, OVER-BUDGET (bytes, `BUDGET=${RULES_HOOK_BUDGET:-420}`, `:72`), DUPLICATE link target, BROKEN link, a cross-file duplicate arm, and RESIDENT-ADD.
  - It is own-scoped by `--own-range` and exits 2 on a non-verdict.
  - It resolves bare `x.md` links in the memory store (`store_dir`, `:92-102`).
- **Land wiring.** `scripts/ship-land.sh:3807-3841`:
  - It arms only when the land's diff touches `.claude/rules/*.md`.
  - It runs `--selftest` first, then runs the lint once per changed file with `--file <f> --own-range "$range"`.
  - Results: rc 2 → `arm_nonverdict`, rc 1 → `gate_red rules-hook-budget`.
- **Loading.** The situational half does not load on this machine because the shared settings carry `claudeMdExcludes: ["**/.claude/rules/agent-operating-lessons-situational.md"]` (migration 0036; read from `~/.claude/settings.json` and `~/.claude-quaternary/settings.json`). **That glob already matches any repo**, so a reso file with that exact name is excluded automatically.
- **Rotor.** `bin/cc-memory-rotate:626-640` routes lessons by default to `$CLAUDE_PROJECT_DIR/.claude/rules/agent-operating-lessons-situational.md` and creates the file if missing (`:722-728`). In a reso session it would therefore create the reso situational file under the canonical name. Using that name lines reso up with the rotor too.

**Measured: the lint does not run on reso as-is.**
`bash rules-hook-budget-lint.sh --file .claude/rules/agent-operating-lessons.md` (cwd reso) => `NON-VERDICT — parsed 0 bullets … the anchor no longer matches the file`, rc=2.
- Cause: it counts only `- [..](..)` bullets (`:121-122`), and reso uses `- text → \`name.md\``.
- Its memory-store resolution would work for reso. `store_dir` derives `-Users-chrisren-Development-reso-management-app` from the main repo root, and all 76 targets exist there.

**Bodies cannot go in `docs/lessons/` in reso.** Reso's docs programme forbids it:
- `scripts/lib/docs-rules.ts:70`: `DOCS_FILE_BUDGET = 180`. `docs/.baseline.env` has `DOCS_FILE_BUDGET=180`, `DOCS_TARGET=157`. `git ls-files docs | wc -l` => 190 total; the acceptance check subtracts named survivors.
- `:204-216`: E3 "add-requires-delete". Every new `docs/` file needs a `docs/` deletion in the same change.

So 70+ per-lesson files under `docs/` are blocked twice. The body tier must stay outside `docs/`. Options:
- **(a) The memory store**: the status quo. It works across all worktrees and accounts and the infra lint already resolves it. Downside: not in git, so not reviewable or versioned.
- **(b) `.claude/lessons/<slug>.md` in the repo.** Not loaded by CC, not counted by the docs gate, and owned via the `.claude` row of `docs/OWNERS.tsv:29` (infra-deploy).

Recommendation: **(b)**, so bodies land in the same commit as their hooks and get reviewed.

## 5. Proposed transformation and achievable sizes

These are estimates: hook = min(current length, 350) per bullet, and section savings judged from the measured section sizes.

**agent-operating-lessons.md: 52.1k → about 8.2k resident.**

| tier | bullets | current chars | as ≤350 hooks | loads |
|---|---|---|---|---|
| resident (fires on any reso work): 24-34, 52, 70-76, 78, 80, 81, 88-90, 92, 105-107, 109, 110, 112, 116 | 33 | 8,598 | ~6,985 (+ ~1.2k rewritten header) | every session |
| situational: 38-40, 45, 48-51, 53, 54, 56, 57, 61, 63, 77, 79, 82-84, 91, 93, 94, 96, 97, 99, 103, 108, 111, 113, 114, plus 35+36+37 merged into one hook | 31 | 28,238 | ~10,679 | excluded by the existing global glob; grep on demand |
| bottle-only: 42, 43, 44, 46, 59, 62, 64, 65, 66, 115 | 10 | 13,754 | ~3,500 | path-scoped (append as hooks to `bottle-reference-sourcing.md`, or a new file with the same `paths:`) |

Body work:
- 7 orphan bullets need bodies written first (7.5k of evidence).
- The 4 multi-lesson bodies need splitting, or the bullets need distinct anchors, to satisfy DUPLICATE.
- 36 long bullets are covered by their bodies and become hook rewrites.
- Rewrite the header to state the convention, and drop the stale "~/.claude/rules is dead" paragraph.

**CLAUDE.md: 36.0k → about 18k.** Estimated savings in kilochars:
- Agent Teams → 2-line pointer: 0.8.
- Concurrent Sessions → reso-only 4 bullets: 0.7.
- Lagging-cache story → body: 1.2.
- Fold Reinforcement items 5 and 7 into Critical Rules and delete the section: 2.0.
- Generic Engineering Principles → `ENGINEERING_PRINCIPLES_BACKGROUND.md` with a 5-line summary: 3.5.
- Placement policy → `docs/auth-tenancy/README.md`: 1.6.
- ui.sh → path-scoped rule: 2.2.
- Browser "why" → body: 1.7.
- Session Close history → body: 1.2.
- Security detail → `api-security.md`: 1.2.
- Pusher/Batch → `replicache.md`: 1.0.
- Drizzle detail that duplicates Critical Rules and `migrations.md`: 0.8.

Total ≈ 17.9k.

**agent-teams.md: 7.8k → 0 to 1k.** Delete it, or cut it to the reso-only delta. The global agent-teams skill holds the rest and loads on demand.

**Net for the three files: 95.9k → about 27k chars/session**, a saving of about 69k chars (≈17-23k tokens at 3-4 chars/token).
On its own this does not bring reso under the 150k total. The ledger (151.7k) and the ancestor-walk double load of the full global file (111.8k) are the dominant terms, and other workers cover those.

## 6. Where a budget lint can run in reso (measured inventory)

- **No `.husky`.** `core.hooksPath` = `/Users/chrisren/.reso/land-tools/scripts/hooks`, an absolute copy. `cmp` against `scripts/hooks/pre-commit` and `pre-push` => identical.
  - `pre-commit` (`scripts/hooks/pre-commit:509-542`) already runs markdownlint on staged `.md` files. A staged-`.claude/rules/*.md` budget check fits here as the fast tier.
  - `pre-push:650` already runs `pnpm docs:gate --assert-push`.
- **`scripts/ship-land.sh`** (1,240 lines, reso's own lander). `run_statics()` at `:815` is where the keyed gates run (typecheck, suite, migrate:lint at `:865`). A keyed `.claude/rules/*.md` arm with own-range, mirroring infra `ship-land.sh:3807-3841`, fits there.
- **The un-bypassable tier.** `scripts/lib/docs-rules.ts:1-24` documents the pattern: pure rule functions plus `tests/docs-structure.test.ts` inside `pnpm test:unit`, which `scripts/postland-verify.sh` runs in a fresh worktree at the trunk SHA.
  - It exists because 82% of checkouts carried stale hooks.
  - A `tests/rules-hook-budget.test.ts` would give the same guarantee.
- **package.json** has `lint:md`, `docs:gate`, `migrate:lint`, but no rules-budget script. `pnpm ship` is a bare push plus deploy-status; `/ship` uses `scripts/ship-land.sh` per `.claude/commands/ship.md`.
- **CI** (`.github/workflows`): diagrams, fabricated-menu, security-scan, soketi CVE, tenant-drift. None of them is a land gate.

## 7. Things to watch

- The infra lint budget counts **bytes**, not chars. `🚨` is 4 bytes, and 45 of reso's 76 bullets contain it (`grep -c '^- .*🚨'` => 45).
- A per-file lint does not catch duplicated rules between CLAUDE.md and global. They are restated, not copied (≈0% shingle overlap), so preventing them is a review or design matter, not a lint matter.
- The 40 reso worktrees keep their old bytes until they rebase. The win reaches a session only once its worktree carries the trunk commit.
