# W2 API contract: scripts/lib/wt-tombstone.sh + wt-park.sh (WP-9) and their callers (WP-10..13)

Binding for every W2 teammate. Source of the semantics: DESIGN.md §3.2 (states, pins), §3.4 (events),
§3.5 (restore), note X6 (per-actor, residue, cache, retention). Where this file and DESIGN differ, this file
wins and says why.

## Corrections to DESIGN made here

1. **Ref names.** DESIGN writes `refs/wt-tombstone/<id>` *and* `refs/wt-tombstone/<id>/wip` /
   `/<id>/reflog-<n>`. Git cannot hold both (a ref name cannot be a file and a directory). So every tombstone
   ref lives one level down: `refs/wt-tombstone/<id>/head`, `/<id>/wip`, `/<id>/reflog-<n>`.
2. **Park split.** WP-9 is two files so two teammates can write it in parallel: `wt-tombstone.sh` (core) sources
   `wt-park.sh` (PARK, unpark, pins) at its tail. Callers source only `wt-tombstone.sh`.

## Conventions

- Source with `. "$HOME/.claude/scripts/lib/wt-tombstone.sh"` (or the repo-relative path in tests). bash 3.2 safe.
- Functions never `exit`; they return. rc 0 = done; rc 1 = "no / not applicable"; rc 2 = refused or failed
  (the caller must KEEP the tree). Diagnostics go to stderr, one line, prefixed `wt-tombstone:`.
- Lab env overrides (all default under `$HOME`): `WT_LEDGER` (falls back to `CC_WTGC_DISPOSAL_LOG`), `WT_TOMB_DIR`,
  `WT_STATE_DIR`, `WT_EVENTS_FILE`, `WT_WAKE_FILE`, `WT_PARK_INDEX`, `WT_PARK_ROOT`, `WT_CONFIG_ROOTS`, `WT_NOW`,
  `WT_TRUNK`, plus the pin sources below. Tests set every one to a scratch dir.
- `umask 077` inside any function that writes under `WT_TOMB_DIR`: dir 0700, files 0600.
- Shared helpers already in the skeleton: `wt__now wt__ts wt__json_esc wt__sha1 wt__canon wt__id_new wt__repo_of
  wt__common_dir_of wt__trunk_of wt__ledger_append wt__config_roots wt__slug`.

## Row schema (one JSONL object per line, appended to `$WT_LEDGER` = worktree-disposals.jsonl)

Existing keys stay (`ts event path branch head preserved_at destroyed_ignored`); new keys:
`id actor reason repo trunk landed (true|false|null) sids [] mode (mv|clone|none) preserved ("<id>/residue"|null)
preserved_list [] caches_skipped [] lockfiles {name: sha256} tomb_ref reflog_refs [] logs_head ("<id>/logs-HEAD"|null)
wip_ref checkpoint_ref parked_path branch_tip`. Absent values are JSON `null`, never omitted.
`event` ∈ `worktree-disposed | guard-snapshot | admin-pruned | branch-deleted | worktree-parked | worktree-unparked |
restored | ref-expired | residue-purged | superseded`.

## Core (WP-9a, wt-tombstone.sh)

| Function | Semantics |
|---|---|
| `wt_tombstone <path> <actor> <reason> [--mode mv\|clone] [--wip] [--checkpoint-ref <ref>] [--event <ev>]` | Writes the full record for a tree about to be removed. Default `--mode mv` (background actors, which remove right after); the guard passes `--mode clone` and `--event guard-snapshot`. Steps: resolve repo + trunk; residue = `git status --porcelain --ignored` ignored entries minus caches (cache = on the allowlist below AND `git check-ignore -q`, AND for `node_modules`/`.venv` its lockfile rule passes) minus provisioning copies `cmp`-identical to the main checkout's (`.env*`, `.claude/settings.local.json`); move (`mv`) or clone (`cp -RPc`) residue to `$WT_TOMB_DIR/<id>/residue/<relpath>`; `refs/wt-tombstone/<id>/head` at HEAD unless `merge-base --is-ancestor HEAD <trunk>`; reflog refs (below); copy `<gitdir>/logs/HEAD` to `$WT_TOMB_DIR/<id>/logs-HEAD`; with `--wip` and a dirty tree, a plumbing snapshot (temp index seeded from the real one, `add -A`, `write-tree`, `commit-tree -p HEAD`) to `refs/wt-tombstone/<id>/wip` — nothing in the tree is written; with `--checkpoint-ref R`, the head ref points at R's commit instead and the row records it. Appends the row LAST. Prints `<id>` on stdout, rc 0. Any failed step: undo moved residue (`wt_residue_restore`), rc 2. If `stat -f %d` of tree and `$WT_TOMB_DIR` differ: tar + 50 MB cap, over cap → rc 2 (KEEP). |
| `wt_residue_restore <id> <path>` | Moves a `mv`-ed residue back into the tree (caller's removal was refused by git). rc 0/2. |
| `wt_reflog_refs <worktree-gitdir> <repo> <trunk> <id>` | For each commit in `<gitdir>/logs/HEAD` that `rev-list --stdin --not --branches --tags --remotes` returns and for which `git cherry <trunk> <c> <c>^` prints `+`: `update-ref refs/wt-tombstone/<id>/reflog-<n>`. Prints the refs. A failed update-ref → rc 2. |
| `wt_prune_logged <repo> [prune-args…]` | `git worktree prune --dry-run -v`; per entry: an `admin-pruned` row (path, repo, head + branch from the admin dir's `HEAD`), copy of its `logs/HEAD`, reflog refs; then runs `git -C <repo> worktree prune <args>` unchanged and returns ITS rc. A logging failure never blocks the prune (logged to stderr). |
| `wt_branch_deleted_row <repo> <branch> <sha> <actor> [reason]` | One `branch-deleted` row. |
| `wt_emit_event <ev> <path> [sid]` | One `printf >>` of `{"ev","path","sid","repo","ts"}` to `$WT_EVENTS_FILE` plus `touch $WT_WAKE_FILE`. Never fails the caller (rc 0 always; stderr on error). |
| `wt_tomb_find <path> [--sid S] [--branch B]` | Prints the newest ledger row (JSON) for `path` with event ∈ worktree-disposed/guard-snapshot/admin-pruned whose `sids` contains S or `branch` equals B; with neither flag, path match only. rc 1 if none. Uses `jq` (/usr/bin/jq). |
| `wt_cleanup_period_days` | Max of `.cleanupPeriodDays` over `wt__config_roots` settings.json; a root with no file or key counts 30. |
| `wt_ref_expire <repo>` | Deletes `refs/wt-tombstone/<id>/*` whose row is older than `wt_cleanup_period_days` and has no later `restored` row; writes `ref-expired`. **Never touches residue.** |
| `wt_purge <id> --operator` | Removes `$WT_TOMB_DIR/<id>`; refuses (rc 2) without `--operator`. Writes `residue-purged`. |

Cache allowlist — always regenerable: `.next __pycache__ .ruff_cache .pytest_cache .mypy_cache .turbo .eslintcache
*.tsbuildinfo`; lockfile-gated: `.venv` (`uv sync --check --locked` rc 0, mtimes unchanged), `node_modules`
(pnpm: `node_modules/.pnpm/lock.yaml` cmp `pnpm-lock.yaml`; npm: `npm ls --all` rc 0). Always residue: `.env*
*.db *.sqlite brag-output/ screenshots/ out/ dist/ asset-workspace/ .claude/settings.local.json` (unless cmp-equal
provisioning copy). `WT_LOCKCHECK_TIMEOUT` (default 20 s; the guard passes 3) bounds each lockfile check; a timeout
counts the dir as residue.

## PARK + pins (WP-9b, wt-park.sh)

| Function | Semantics |
|---|---|
| `wt_park <path> <actor> <reason> --arm i\|ii` | Same-volume check (`stat -f %d` of path and `$WT_PARK_ROOT`; differ → rc 2). `git worktree move <path> $WT_PARK_ROOT/<id>`; `git worktree lock --reason "parked <ts> from <path> sids=<…>"`; arm i with HEAD on a branch: `git -C <parked> checkout --detach` (HEAD only). Index file `$WT_PARK_INDEX/<sha1(path)>`, `key=value` lines: `path repo parked branch branch_tip ts id`. Row `worktree-parked`. rc 0 prints parked path. Any failure after the move: move back, rc 2. |
| `wt_parked_lookup <path>` | Prints the index file's `parked=` and `repo=` as `<repo>\t<parked>`; rc 1 if not parked. |
| `wt_unpark <path>` | rc 1 if no index entry. Occupied path: if a dir holding only `.claude-*` / `.next` entries (a NOGIT husk) → `mv` to `<path>.husk-<ts>`; any other content → rc 2. `git worktree unlock`, `git worktree move <parked> <path>`; re-attach if `branch` exists, is checked out nowhere else, and its tip == HEAD (`git checkout <branch>`), else log `reattach=skipped:<reason>`. Removes the index file, row `worktree-unparked`. rc 0. Callers holding a per-repo git lock call it inside the lock. |
| `wt_pinned <path>` | rc 0 + prints `<kind> <detail>` for the first pin found; rc 1 = no pin. Kinds: `crash` (row `class=="CRASH"` in `${WT_CRASH_LOG:-~/.claude/logs/claude-crashes.jsonl}`, ≤7 d, sid ∈ sids of this path, no later SessionStart — read as: the sid's transcript has a record newer than the crash ts), `resume-debt` (`${WT_RESUME_DEBT_DIR:-~/.claude/autonomy/resume-debt}`), `limit-recover` (`${WT_LR_DIR:-~/.reso/limit-recover}/<sid>/` present and not proven), `recycle-failed` (`${WT_RECYCLE_FAILED_DIR}/<sid>.json`), `boot-resume` (`${WT_BOOT_RESUME_DIR}` rows naming the path, not done), `backlog` (an open row in `${WT_BACKLOG:-~/.claude/autonomy/backlog.jsonl}` naming the path), `owner` (`<gitdir>/logs/HEAD` mtime < 60 min). Sids of a path = transcript basenames under every config root's `projects/<slug>*` where slug prefix-matches `wt__slug <path>` — no per-crash-row glob. Every pin expires by the effective cleanupPeriodDays at the latest. Bounded reads only: 7 d tail of the crash log, one listing per store. |
| `wt_newest_transcript_mtime <path>` | Newest `*.jsonl` mtime (epoch) under every root's `projects/<slug>*` (subagent dirs included); empty + rc 1 if none ("unknown, not old"). |
| `wt_recent_file <path> <days>` | rc 0 iff `find <path> -name .git -prune -o -mtime -<days> -print -quit` prints something. |
| `wt_pin_lock_sync <repo> [--observe]` | For each linked worktree of repo: pinned + unlocked → `git worktree lock --reason "cc-pin:<kind> sid=<sid> until=<epoch>"`; locked with a `cc-pin:` reason whose pin is gone or `until` passed → unlock. Never touches other locks. `--observe` logs `would_lock` / `would_unlock` to stderr and changes nothing. Scope (which repos) is the CALLER's (WP-15). |

## Callers (WP-10..13) — what each one calls

- worktree-gc (WP-10): `wt_tombstone … --mode mv` before every remove; `wt_residue_restore` on refused remove;
  `wt_prune_logged` at the prune site; `wt_pinned` as a KEEP gate; `wt_park` for the PARK tiers; `--path` mode.
- cc-reaper (WP-11): `wt_emit_event pane-teardown <path> <sid>` instead of remove.
- teammate-auto-shutdown (WP-12): `wt_pinned`, then `gtimeout 300` `wt_tombstone … --checkpoint-ref refs/wip/<member>/LAST`
  inside the detached subshell; failure/timeout → KEEP. handoff-fire: `wt_pinned` + `wt_tombstone`. guard:
  `gtimeout 6` `wt_tombstone <path> guard-raw <cmd> --mode clone --event guard-snapshot [--wip]`, exit 0 silent / exit 2;
  prune arm → the same logging as `wt_prune_logged` without running the prune (the command runs it).
  branch-prune-landed: `wt_branch_deleted_row` + `wt_emit_event branch-deleted`. Other prune sites: `wt_prune_logged`.
- resume (WP-13): `wt_unpark` first in every launcher; `wt_tomb_find --sid/--branch` for DETACHED restore via
  `cc-wt-restore`; `wt_prune_logged` at reso-resume-one's prune.

## Lab rule (all WPs)

Tests build throwaway repos under `$BATS_TEST_TMPDIR` (bare `origin` + clone + linked worktrees) with every `WT_*`
var and `HOME` pointed into it. Never touch `~/Development`, never run git against a real worktree. A RED case is
proven by running the same test against the unpatched code (`git stash`-free: copy the pre-change file from
`git show origin/main:<path>` into the tmpdir) and recording that it fails.
