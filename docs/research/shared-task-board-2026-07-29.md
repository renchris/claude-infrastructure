# Shared task board across the four accounts — investigation + design

**Date:** 2026-07-29 · **Verdict:** CAN (natively, no forks) and SHOULD (the split state is
actively broken, not merely un-built) · **Status:** built, tested, committed on
`feat/shared-task-board`; one operator activation staged.

The subject is Claude Code's **built-in task list** — the `15 tasks (11 done, 3 in progress,
1 open)` panel — not `cc-backlog` (the desk's own ledger, already shared via
`~/.claude/autonomy/backlog.jsonl`).

---

## 1. How the feature actually works

| Fact | Evidence |
|---|---|
| A board lives at `$CLAUDE_CONFIG_DIR/tasks/<listId>/` | `1.json … N.json` + `_summary.json` + `.highwatermark` + `.lock` |
| The board id comes from `CLAUDE_CODE_TASK_LIST_ID` | present in the 2.1.219 binary's env table; set by every `~/.zshrc` launcher |
| Unset ⇒ a per-session throwaway board | `session-<8hex>` dirs: 181/209/221/166 across the four stores |
| Ids allocate as `max(existing)+1` | created 36-39 against ids 21-35; `.highwatermark` stayed 20 |
| `_summary.json` is a lazily-written **cache** | read 15 tasks while 19 were on disk — this is the number the panel header shows |

**Two independent conditions must both hold for two sessions to share a board:** the same
`listId`, *and* config dirs whose `tasks/` resolve to the same directory. Before this change only
account 1 satisfied the second.

## 2. Probes — measured, not assumed

| Probe | Result |
|---|---|
| **P1** a new session reads an existing shared board from disk | **PASS** |
| **P2** two sessions creating tasks on one board concurrently | **PASS** — both survived, distinct ids; the store is lock-serialised |
| **P3** account-3 session, *same* `CLAUDE_CODE_TASK_LIST_ID=claude-infrastructure-main` | wrote id 20 into `~/.claude-tertiary/tasks/` — **invisible** to the account-1 session on the same name |

P2 is what licenses widening the sharing key: concurrency was proven safe before it was relied on.
P3 is the defect, end to end.

## 3. Why it was broken

`lib/config-mirror.zsh` listed `tasks` + `tasks-index.json` in `_CC_ISOLATE` for accounts 2/3/4 —
swept into the "session/usage/identity state" bucket with transcripts and usage counters. That is a
**mis-classification**: a task board is *work* state, not *account* state; the four accounts are
quota pools for one operator, not four people.

Compounding it, `_cc_tlid` in `~/.zshrc` keyed the board on `<repo>-<branch>`. Under this fleet's
mandatory worktree isolation every concurrent writer gets its own branch, so the branch component
handed every session a *private* board.

**Measured damage:**

- `claude-infrastructure-main` existed as **four divergent boards** — 15 / 0 / 3 / 23 tasks.
- Ids collided carrying different work: id 21 = "Triage machine lag" in `~/.claude`,
  "Audit session-close mechanisms" in `~/.claude-quaternary`.
- **14 boards** populated in an account store while their canonical twin sat empty.
- **550 of 580** canonical board dirs empty, 373 of them project-keyed — the task hooks hardcoded
  `~/.claude/tasks`, so for three of four accounts the index, the `_current` symlink and the desk's
  cross-project rollup pointed at boards Claude Code never wrote to.

Nothing failed loudly anywhere in that list. That is the through-line: every symptom was silent.

## 4. Design

| Decision | Rationale |
|---|---|
| **Un-isolate `tasks` / `tasks-index.json`** | The mirror's own model is "share everything except genuine per-account state". Work state is not per-account. |
| **Key on repo identity, not repo+branch** (operator decision) | One board per project across every account, branch and worktree. Linked worktrees resolve via `--git-common-dir`; `--show-toplevel` would re-fragment per worktree. |
| **Collision broken by `tasks-index.json` ownership, incumbent wins** | Two same-basename repos would otherwise silently share a board. An established board is never renamed out from under itself. |
| **`cc-tlid` fail-soft, never empty** | It runs in the launcher hot path; an empty id silently un-shares the fleet with no error. There is no non-zero exit that omits the id. |
| **Merge is additive / idempotent / never touches a source** | At k=3/3/1/3 live sessions a refuse-if-live guard could **never fire** — the classic gate that exists but cannot run. Safety comes from the write discipline instead. |
| **Content merge strictly before linkage convert** | `--convert` is `mv -f <dir> <dir>.premirror-bak` — correct for a config file, catastrophic for 245/251/186 boards. |
| **`--collapse-keys` opt-in and separate** | Folding branch-keyed boards needs weaker, git-resolved attribution; a board whose project directory is gone is left alone and named, never guessed at. |

### Why the merge is a program, not `cp -r`

1. **Ids collide and mean different things** → every incoming task is renumbered above the target's
   watermark; nothing is ever written to an id that exists.
2. **Renumbering breaks `blocks`/`blockedBy`** → every reference is remapped through the same
   old→new table. An unresolvable reference is dropped **and reported** — silently keeping it is
   worse than losing it, because it still looks valid.
3. **The obvious path is the lossy one** → see the convert ordering above.

## 5. What was built

| Artifact | Role |
|---|---|
| `bin/cc-tlid` | the sharing key — repo identity, worktree→primary, collision-safe, fail-soft |
| `bin/cc-task-store` | `plan` / `merge` / `verify` / `rebuild-summary`; renumber + dep-remap + dedupe + backup + no-loss verify |
| `lib/config-mirror.zsh` | now version-controlled; `tasks` un-isolated, migration order documented |
| `install.sh` | links `lib/*.zsh` (it linked `hooks/lib/` but not `lib/`) |
| `hooks/lib/task-helpers.sh` + 2 hooks | resolve the store from the running session's config dir |
| `tests/cc-tlid.bats` (10) · `tests/cc-task-store.bats` (16) · `tests/config-mirror-isolate.bats` (6) | 32 tests, RED-proofed |

**Two bugs the tests caught in my own tools**, both of the silent class this work is about:

- the allocator did not thread state across moves, so account-3 and account-4 both planned ids
  40,41,42 for one board (the overwrite guard would have caught it — but a plan the operator
  approves has to be right *before* the guard fires);
- provenance recorded `"tasks"` (the store dir) instead of the account, i.e. provenance that could
  not answer the only question it exists to answer.

A third was in the test harness: `select(.!="")` in a jq fixture emits **nothing** for the empty
case, so every dependency-free fixture was a zero-byte file and four tests passed vacuously.

## 6. Migration state

`cc-task-store plan` (read-only, current): **236 tasks across 31 boards** to merge, 0 duplicates,
652 boards already consistent. Staged as
`docs/activation/pending-activation/15-shared-task-board-activate.sh` — five idempotent steps in a
load-bearing order, dry-run by default, refusing the convert for any account with a live session.
Steps 4-5 are C10 (mutate live config dirs / edit `~/.zshrc`), so the operator runs it.

## 7. Known limits

- **Running sessions keep the board they resolved at launch.** The id is fixed at process start, so
  the collapse takes effect for *new* sessions. Existing panes are unaffected until restarted.
- **`_summary.json` staleness is upstream behaviour.** `rebuild-summary` repairs it on demand; the
  panel header can still drift between Claude Code's own writes.
- **Teammates and subagents get agent-scoped boards** (`…-agent-<id>`) — untouched here, and
  arguably correct, but it means a teammate's tasks are not on the project board.
- **`--collapse-keys` cannot attribute a board whose project directory is gone.** Those are
  reported, not guessed.
