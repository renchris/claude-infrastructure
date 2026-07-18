# P14 — Orchestrator-Desk Task/Plan Ledger

**Verdict up front:** The desk **CANNOT** answer "what is ALL open work?" from disk truth.
There is no enumerator over open work — only two disjoint per-namespace stores (an
ExitPlanMode plan sink that is now empty + rotting, and a session-scoped task store that
surfaces exactly ONE globally-most-recent list). **Net-positive progress is measured by
nothing** — every telemetry asset meters cost/quota/liveness, none meters work-value.

Goals: **a** = enumerate ALL open work (durable, queryable, non-rotting) · **b** = measure
net-positive (value produced vs spend) · **c** = survive handoffs/session churn without rot.

Empirical (read/ran) unless tagged [inferred]. Repo hooks are **byte-identical** to
`~/.claude/hooks` (`diff -q` clean) — analysis applies verbatim at runtime; `~/.claude` is
NOT a symlink but its hook files are copies-in-sync.

---

## 1. Inventory

| Asset | Role | Wiring | Depends on | Verified by | Goal | Gap |
|---|---|---|---|---|---|---|
| `~/.claude/plans/` | ExitPlanMode plan sink (canonical store the index keys on) | native plan-mode writes | — | `find … -type f` = **0 files** | a | G-P14-1 |
| `.claude-plans/` (repo root) | project-filtered plan view | `setup-plan-symlinks.sh` SessionStart | `~/.claude/plans` | only `_all→~/.claude/plans` symlink; **0 `.md`** | a | G-P14-1 |
| `.claude-plans/_all` | symlink → global plan store | `setup-plan-symlinks.sh:16-22` | `~/.claude/plans` | `readlink`→empty dir | a | G-P14-1 |
| `docs/plans/*.md` | **real** hand-authored plans (5 here, **482** across ~/Dev) | plan-conventions skill convention | — | `ls`; `find … docs/plans` = 482 | a | G-P14-2 |
| `~/.claude/plans-index.json` | plan→project index | `plan-index-update.sh` PostToolUse | `~/.claude/plans` writes only | 360 plans, **`generated:2026-06-03`** (6wk stale), all phantom | a | G-P14-1,3 |
| `plan-index-update.sh` | index a plan on write | PostToolUse Write/Edit | file under `$HOME/.claude/plans/*.md` (`:9-10`) | reads `:10 case` — docs/plans never matches | a | G-P14-2 |
| `setup-plan-symlinks.sh` | emit "Plans: N" + rebuild symlinks | SessionStart | `~/.claude/plans`, `.claude-plans` | `:39-43` counts both → **"Plans: 0 …(0 total)"** | a | G-P14-1 |
| `migrate-plans-index.sh` | rebuild index from transcripts | **MANUAL — 0 settings.json refs** | session JSONLs | `grep -c`=0 in settings | a,c | G-P14-3 |
| `find-plan.sh` | resolve plan **name→content** | on-demand CLI | name arg | `:44-67` name-lookup, NOT enumeration | a | G-P14-4 |
| `current-session-plan.sh` | resolve THIS session's plan | on-demand CLI | sidecar/transcript | L1 pin + L2 scan (`:117` matches docs/plans) | c | — |
| `plan-pin-session.sh` | O(1) L1 pin on ExitPlanMode | PostToolUse ExitPlanMode | `~/.claude/plans/*.md` only (`:34`) | docs/plans plans **never pinnable** | c | G-P14-5 |
| `plan-version-commit.sh` | version plans → MANIFEST+git | PostToolUse Write/Edit | matches docs/plans (`:28-29`) | MANIFEST.jsonl **3064** rows / **512** names | c | audit-only |
| `validate-plan-structure.sh` | warn if Phase 0 missing | PostToolUse | matches docs/plans (`:20-24`) | `:1-3` **exit 0 always (non-blocking)** | c | G-P14-6 |
| `~/.claude/tasks/<id>/` | native TaskCreate store (per-task `N.json`+`_summary.json`) | native Task* tools | — | 440 dirs under `_all` | a | — |
| `.claude-tasks/` | project task view + `TASKS.md` | `setup-task-symlinks.sh` SessionStart | `~/.claude/tasks`, index | `_current→session-7cc029c2` (**foreign**) | a | G-P14-7 |
| `find_active_list()` | pick active list = **global most-recent mtime** | called by all task hooks | `~/.claude/tasks/*` | `task-helpers.sh:9-25` — no project filter | a | G-P14-7 |
| `~/.claude/tasks-index.json` | taskList→project map | `setup/mutation/completed` hooks | `CLAUDE_CODE_TASK_LIST_ID` | 303 lists; claude-infra lists **tc=0** | a | G-P14-7 |
| `task-mutation-index.sh` | regen summary+TASKS.md on task write | PostToolUse TaskCreate\|Update | `find_active_list` | picks global-most-recent (`:12`) | a | G-P14-7 |
| `task-completed-index.sh` | regen on TaskCompleted | TaskCompleted | `.active-list-id`/detect | `:14-26` | a | G-P14-7 |
| `task-quality-gate.sh` | typecheck gate on completion | TaskCompleted | teammate worktree | `:25` **team tasks only**; standalone ungated | b | G-P14-8 |
| `TASKS.md` | human-readable active list | generated | `_summary.json` | shows foreign reso/doc_classifier tasks | a,c | G-P14-7 |
| `bin/cc-board` | all-sessions glance | `watch` / on-demand | `/tmp/cc-telemetry`+accounts | ctx% × quota × stall — **no value axis** | b | G-P14-9 |
| `statusline.sh` | per-turn context% export | statusline render | payload context_window | input-token % only (cost) | b | G-P14-9 |
| `scripts/telemetry-e2e.sh` | **test** guard for telemetry-v2 | manual/CI | statusline/cc-* | `:1-8` regression guard, not accounting | b | — |
| `claude-search` (`sessions.db`,`session-index.db`) | retrospective transcript FTS (incl `session_tasks`,`session_teams`,`session_git_ops`) | on-demand CLI | ~/.claude JSONLs | schema grep; keyed by session, frozen at index | a | G-P14-10 |

---

## 2. Mechanism

### 2a. Two disjoint plan namespaces (root cause of "Plans: 0")
- **Namespace P1 — ExitPlanMode sink** `~/.claude/plans/*.md` (adjective-noun names +
  `-agent-<hash>.md` sub-plans). This is the ONLY namespace the index machinery keys on:
  `plan-index-update.sh:9-10` matches `"$HOME/.claude/plans"/*.md` exclusively;
  `plan-pin-session.sh:34` searches only there; `setup-plan-symlinks.sh:4,39` counts only
  there (TOTAL) + `.claude-plans/*.md` (FILTERED).
- **Namespace P2 — hand-authored** `docs/plans/*.md` (the plan-conventions convention; where
  ALL 5 claude-infra plans + 482 repo-wide plans actually live). `find-plan.sh:44-56` lists
  it as resolution source #5, and `validate-`/`plan-version-commit.sh` fire on it — but
  **nothing indexes or enumerates it.**
- The two never meet. `~/.claude/plans/` currently holds **0 files** [inferred: cleared/moved
  post-2026-06-03], so `plans-index.json` (360 plans, `generated:2026-06-03`) is **360 phantom
  entries**; the 482 live plans are **entirely absent** from every index.

### 2b. Task store — session/global scoped, not project scoped
Native `TaskCreate/Update/Completed` write `~/.claude/tasks/<listId>/N.json` + `_summary.json`
(`task-helpers.sh:28-60` regenerates summary: counts pending/in_progress/completed).
`find_active_list()` (`task-helpers.sh:9-25`) picks **the directory whose newest `[0-9]*.json`
has the greatest mtime — GLOBALLY, no project filter**. `setup-task-symlinks.sh:98-118` writes
that pick into `.claude-tasks/{_current,.active-list-id}` and renders `TASKS.md`. Consequence:
claude-infra's `TASKS.md` currently shows `session-7cc029c2` — doc_classifier/reso pipeline
work (`supplier_resolver`, `B06 RegistrySet`, `cli.py:294-336 RunContext`), **"NOT IN INDEX"**
of tasks-index.json — because that list was globally-most-recent when the hook last ran.

### 2c. The exact query path for "ALL open work" — RAN LIVE (read-only)
| What a fresh desk session actually sees at SessionStart | Emitter | Live result |
|---|---|---|
| Plan count | `setup-plan-symlinks.sh:43` | **"Plans: 0 for claude-infrastructure (0 total)"** |
| Task surface | `setup-task-symlinks.sh:128-134` | one list = `session-7cc029c2` (foreign project) |

Live reconciliation vs reality:
- Plans on disk: **5** (`docs/plans/` here) / **482** (`~/Development/*/docs/plans`) — **0** visible to the desk.
- Task lists with open (pending+in_progress) tasks across `~/.claude/tasks`: **22** — only **1** surfaced, and it's the wrong project's.
- **No enumerator exists.** `find-plan.sh` resolves name→content (not a list). Only
  `commands/ship.md` matched an "open work" grep — it ships current work, doesn't enumerate.
  → **A fresh session must reconstruct "what remains" from its own rotting context** — the exact
  mechanism behind FM1 (premature-done): told "0 plans", it re-judges completeness from empty.

### 2d. Lifecycle & rot
create (ExitPlanMode → P1, or hand-write → P2) → update (Edit; `plan-version-commit.sh` audits
both namespaces to MANIFEST.jsonl+git) → complete (**no state transition exists** — completion
is prose "COMPLETE"/"SHIPPED" in docs/plans, unparseable; the 5 plans have **0 checkboxes, no
frontmatter status**) → archive (**none**). A plan silently rots the instant its authoring
session dies: no index row (P2), no completion flag, no orphan sweep. Tasks rot symmetrically —
a completed list lingers in the 440-dir store; `find_active_list` can resurrect a stale foreign
list as "active" in any project.

---

## 3. Gaps

| ID | file:line | FM | Sev | Failure scenario | Fix sketch |
|---|---|---|---|---|---|
| G-P14-1 | `setup-plan-symlinks.sh:39-43`; `~/.claude/plans`=empty | FM1 | **P0** | SessionStart tells every desk session "Plans: 0 (0 total)" while 5–482 real plans exist → fresh session re-judges completeness from empty context, declares done | Count `docs/plans/*.md` (+ `.claude-plans/`) in FILTERED/TOTAL; or emit open-plan rollup from a real index |
| G-P14-2 | `plan-index-update.sh:9-10` | FM1 | **P0** | `docs/plans/` writes are NEVER indexed (case matches `~/.claude/plans` only) → the durable plan namespace is invisible to all tooling | Add `*/docs/plans/*.md` + `*/.claude-plans/*.md` to the index case; store project via cwd |
| G-P14-3 | `migrate-plans-index.sh` (0 settings refs); index `generated:2026-06-03` | none | P1 | Only auto-updater keys on empty P1, so index froze 6wk ago w/ 360 phantom plans; rebuild is manual & nobody runs it | Wire a SessionStart/cron reconcile that rebuilds from `docs/plans` truth + prunes missing files |
| G-P14-4 | `find-plan.sh:44-67` | FM1 | P1 | Resolver, not enumerator — there is no "list all open plans" verb anywhere | Add `find-plan.sh --list-open` scanning all plan dirs, parsing status |
| G-P14-5 | `plan-pin-session.sh:34` | none | P2 | docs/plans plans can't get an L1 pin (SHA loop scans `~/.claude/plans` only) → per-session resolution falls to slower L2 transcript scan | Extend pin search to docs/plans / `.claude-plans` |
| G-P14-6 | `validate-plan-structure.sh:1-3,51` | FM1 | P1 | Only WARNS (exit 0) about Phase 0; enforces **nothing** about completeness/status → a plan can be "done" in prose, open in reality, forever | Add a status-schema linter (frontmatter `status:` required); optionally block on malformed |
| G-P14-7 | `task-helpers.sh:9-25`; `setup-task-symlinks.sh:98` | FM1 | **P0** | `find_active_list` is GLOBAL most-recent → claude-infra `TASKS.md` shows a foreign project's tasks; a desk asking "my open tasks?" gets the wrong list; 22 open lists never rolled up | Filter `find_active_list` by `CLAUDE_PROJECT_DIR` via tasks-index; add an all-projects open rollup |
| G-P14-8 | `task-quality-gate.sh:25` | FM1 | P1 | Standalone (non-team) task completion is ungated — a task marks done with no verify | Run a lightweight gate (or require verify evidence) for standalone completes |
| G-P14-9 | `cc-board` hdr; `statusline.sh:4-6`; no matching asset | none (b) | **P0(b)** | **Nothing measures net-positive.** All telemetry = cost/quota/stall. No tasks-closed, commits-landed, or value-per-cycle metric exists or is even planned | Add a value ledger: per-session Δ(tasks completed)+Δ(commits landed) joined to token/quota spend in cc-board |
| G-P14-10 | `claude-search` schema (`session_tasks`) | none | P2 | Indexes tasks retrospectively per-session (frozen at index time), FTS-searchable — mistakable for a live ledger; it is not authoritative for current open state | Document as history-only; don't route "what's open" through it |

---

## 4. Task candidates

| ID | Action | Acceptance criterion | Depends-on |
|---|---|---|---|
| T-P14-1 | Make `plan-index-update.sh` index `docs/plans/` + `.claude-plans/` (project via cwd) | New `docs/plans/*.md` write appears in `plans-index.json` with correct projectName | — |
| T-P14-2 | Fix `setup-plan-symlinks.sh` count to include `docs/plans` | Session in claude-infra reports "Plans: 5" not 0 | T-P14-1 |
| T-P14-3 | Add `find-plan.sh --list-open` cross-project enumerator w/ status parse | Command lists every plan with open/unknown status across all projects | plan status schema |
| T-P14-4 | Define + lint a plan `status:` frontmatter schema (open/in-progress/complete) | `validate-plan-structure.sh` flags a plan missing `status:`; enumerator can classify | — |
| T-P14-5 | Project-scope `find_active_list` (filter by CLAUDE_PROJECT_DIR) + all-projects open rollup | claude-infra `TASKS.md` shows only its lists; a `--all-open` verb lists the 22 | tasks-index project map |
| T-P14-6 | Auto-reconcile plans-index on SessionStart (rebuild from disk truth, prune phantoms) | Index `generated` ≤ 1 session old; 0 phantom entries | T-P14-1 |
| T-P14-7 | Build a net-positive value ledger (tasks-closed + commits-landed per session ÷ spend) | cc-board gains a VALUE column; a session can read its own net contribution | statusline telemetry |
| T-P14-8 | Gate standalone task completion (verify evidence or lightweight check) | `task-quality-gate.sh` no longer early-exits for non-team tasks | — |

---

## 5. Cross-beat dependencies
- **FM1 beat**: G-P14-1/2/7 are the *ledger* half of premature-done — "what remains" is not
  disk-truth, so FM1's completeness re-judgment starts from a false zero. Fixing FM1 detection
  without fixing the ledger leaves the root substrate rotted.
- **Handoff beat**: `current-session-plan.sh` (L1/L2) is the per-session bridge; G-P14-5 (no
  docs/plans pin) weakens handoff plan-resolution. `TASKS.md` is the intended handoff artifact
  but G-P14-7 makes it untrustworthy across projects.
- **Net-positive / autonomy beat**: G-P14-9 blocks any "is the desk making progress?" signal —
  the autonomy loop can churn tokens with zero value visibility.
- **Session-index beat**: claude-search (`session-index.db`, 4937 sessions) is the retrospective
  half; a live ledger (this beat) + retrospective search are complementary, not substitutes.

## 6. Adversarial self-pass
- *"Is `session-7cc029c2` actually foreign?"* — Confirmed: `tasks-index.json` returns **NOT IN
  INDEX**; `_summary.json` content = doc_classifier pipeline (`cli.py:294-336`, `RunContext`,
  `supplier_resolver`). The surfaced active list isn't even project-mapped — pure global-mtime pick.
- *"Any work-value metric hiding in bin/?"* — Exhaustive `bin/` scan: `cc-classify` (session
  **state** OK/DUE/LIMIT/DEAD/STALL) + `claude-kimi` (cost launcher) matched a broad regex but
  neither computes value-produced. cc-board/cc-context/statusline/telemetry all meter cost+state.
  Verdict "no net-positive accounting" holds; not even planned (SESSION_AUTONOMY_PLAN's only hit
  is a prose "57 COMMITS LANDED" completion note).
- *"Does anything besides the 2 hooks surface open work at SessionStart?"* — No: statusline has
  no plan/task field; only `setup-plan-symlinks.sh` + `setup-task-symlinks.sh` emit counts, and
  both are broken/misleading for claude-infra.
- *"Is `current-session-plan.sh` also broken by empty P1?"* — No: L2 (`:117`) matches
  `/docs/plans/`, so per-session resolution still works; only the aggregate count + L1 pin break.
  (Prevents over-claiming total blindness.)

## 7. Uncertainties
- **WHY `~/.claude/plans` is empty** — empirical: 0 files now; index says 360 as of 2026-06-03.
  [inferred] the sink was cleared/archived post-Jun-3 without index regen; exact event/date not
  established (didn't scan backups). Doesn't change the verdict (the index rots regardless).
- **claude-search `session_tasks` row count/freshness** — not queried live (a `sqlite3` batch was
  blocked by a schema-guard matching a table-definition keyword in my grep string). Schema
  presence is confirmed; its retrospective nature is structural (per-session snapshots), so a live
  count wouldn't change the "history-only, not a live ledger" conclusion.
- **Goal b/c labels** are my inference from the beat brief (a is user-given verbatim); if the
  desk defines b/c differently, the goal column mapping shifts but the gaps don't.
