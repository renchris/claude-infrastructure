# B1: the land-time steps that run outside `ship-land.sh`'s own body

**Scope.** This covers the steps `scripts/ship-land.sh` hands off to other files: `scripts/ship-reconcile.sh`, `scripts/cc-sem.sh`, `scripts/lib/land-tools.sh`, `scripts/land-lock.sh`, and the `git push` step's `scripts/hooks/pre-push`, which is a land-time step outside the body too. For each step it records what the step does, what it costs, what it contends on, and whether one dedicated lander could run it for many branches.

**Sources.**
- All files were read at `origin/main` 108be1a7b (2026-09-23), using `git show`.
- Timing data comes from `~/.reso/land.log`: 1,880 rows, of which 159 are v3 rows (v3 started 2026-09-14). The 7-day window is 2026-09-16T05:09Z to 2026-09-23T05:09Z: 111 attempts and 125 rounds.
- Lane occupancy comes from `~/.reso/load.jsonl*` (the load sampler writes one row every 10 s).
- Where it says *empirical*, the number was measured or read from the log. Where it says *theoretical*, it comes from reading the code and has not been observed.

---

## 0. The five findings that matter most

1. **The false "exit 6 commit already upstream" message is printed by `ship-reconcile.sh:247-259` (the text is at :249).** It fires whenever a rebase or cherry-pick has *started* and then stopped with no conflicted files. The code never checks the cause it names.
   - **On the rebase path the named cause cannot happen.** A non-interactive `git rebase` drops already-upstream commits before it starts, and drops commits that become empty (`--empty=drop` is the default; git-rebase(1), git 2.54). So every exit 6 on the rebase path is wrongly attributed.
   - **The unit's case, reconstructed.** land.log row 1856, branch `sec-w6-w4a4-notify`, 2026-09-23T03:28:27Z, exit 6. That row has `fail_stage:null`, `tsc_s:null` and `reconcile_s:2`, so it was a reconcile stop logged as `statics-red`.
   - The worktree's HEAD reflog, read before the worktree was reaped at about 05:16Z, shows the sequence: `rebase (start)` onto d7f723f38 at 03:28:30Z, then 2 picks, then `rebase (abort)` at 03:28:31Z. At 03:28:52Z the same 4 commits rebased onto the same d7f723f38 **cleanly**.
   - A merge of the same commits onto the same base gives the same result every time, so the stop had a passing environmental cause, not a conflict. The most likely cause is index.lock contention in the middle of the sequence. The 09-04 fix (exit 7) covers only a lock that is present *before* the rebase starts.
2. **Reconcile exit codes pass straight through and collide with ship-land's own exit contract** (`ship-land.sh:843`).
   - Reconcile 6 is logged as `statics-red` (`:186`), and the `/ship` table (`ship.md:68`) says "statics red".
   - Reconcile 7 ("never started, safe to retry") is logged as `escalation-parked` (`:187`), and the `/ship` table (`ship.md:69`) says "destructive migration PARKED — operator decision". An agent following the table would escalate a passing lock to the operator.
   - Reconcile 5 (a hand-written DML migration) is logged as `rebase-conflict`.
3. **40% of `push-rejected` (exit 9) rows are really lost races, misclassified.** In the 7-day window, 6 of 15 exit-9 push tails read `[remote rejected] HEAD -> main (cannot lock ref 'refs/heads/main': is at X but expected Y)`.
   - That is GitHub's server-side compare-and-swap loss. `git push` takes the remote sha from the ref advertisement *before* the pre-push hook runs, and the hook runs the full suite, so the pushes took 156–266 s.
   - `ship-land.sh:889-892` matches only `non-fast-forward | fetch first | Updates were rejected`. These pushes therefore take the terminal exit 9 ("NOT by a race … Re-running reproduces this", `:909-912`), which is false, instead of a CAS retry.
   - The 7-day waste: 19 rounds lost to CAS (rc 99), costing 9,598 s, plus these 6 terminal losses, costing 3,012 s.
4. **The land's suite is admitted through `cc-sem reso-land` (K=1), but the push's pre-push hook runs a second, full suite in a different lane.** The hook calls `pnpm test:unit`, which runs `cc-sem general -- vitest run` (full suite, `package.json:126`, `pre-push:130-150`).
   - The two do not share slots: the land's union suite uses `reso-land` (K=1), the hook uses `general` (K=3).
   - K=1 therefore bounds only about half of a code land's test CPU. At the observed peak of 4 concurrent landers, the box can run 1 union suite plus up to 3 full suites.
   - The hook's queue wait is hidden inside `push_s` (p50 167 s on code lands). A full `general` lane shows up as a push timeout (exit 12, `PUSH_TIMEOUT` default 120 s), not as cc-sem's exit 10.
5. **`cc-sem`'s memory floor does nothing.**
   - At `cc-sem.sh:271`, `memory_ok "${floor}" || true` discards the result. Admission is the `mkdir` at `:228` and never consults memory.
   - `design:gate` and `test:e2e` pass `--memory-floor 8` (`package.json:99-100`) with no effect. `ship-land` passes no floor.

---

## 1. Step table

Most of a land's time sits in steps S14–S16. The cost column is empirical unless marked *theoretical*. The 7-day land.log p50/p90 values are per round.

| # | Step | file:line | What it does | Cost | Shared resource / contention | Central lander safe? | Notes |
|---|---|---|---|---|---|---|---|
| S1 | land-tools materialise | `land-tools.sh:140-202` (called `ship-land.sh:288-292`) | Resolves `origin/main:scripts`. Reuses `~/.reso/land-tools.d/<scripts-tree>` if its guard passes (touches it, rewrites the marker if the source commit differs). Otherwise runs `git archive <sha> scripts \| tar -x` into a mktemp dir, writes the marker, guards, `rm -rf target`, then `mv tmp target`. | Reuse path is about 10–15 git forks, measured at 0.01–0.05 s each at load 155–211 (`git archive` of scripts/ = 13.3 MB in 0.056 s; floor `git log -1 -- paths` 0.010 s; guard's 4 forks 0.043 s). Fresh path adds tar extraction of about 545 files / 13.6 MB (*estimated* 0.2–1 s). 13 fresh targets in 24 h; store is 173 MB. | Box-global `~/.reso/land-tools.d`. Race R1 (see §4). | **Yes, and simpler**: one converge per trunk advance, which removes R1 and R2. | GC at `:198-199` deletes targets unused for 24 h, excluding its own target. |
| S2 | land-tools guard ×2 | `land-tools.sh:77-119` (materialise + `:228`) | For pre-commit and pre-push: present, executable, 5 sibling dependencies readable, and bytes equal the blob at the source rev. Returns 20/21/22/23. | ~0.05 s × 2 (measured primitives). | Reads the symlinked canon. Can fail 23 if a sibling swapped the canon to another tree in between (R2). | Yes. | |
| S3 | canon symlink swap | `land-tools.sh:181-195` | Points `~/.reso/land-tools` at the target: `ln -s` then `perl rename()` (atomic). | µs–ms. | **Box-global symlink read by every worktree's git hooks.** The last writer wins (R2). | Yes (single writer). | Currently points at b7908c426. |
| S4 | assert `core.hooksPath` | `land-tools.sh:205-216` | Reads the setting; if it is not the canon path, runs `git config core.hooksPath <canon>`, re-reads, and returns 24 on failure. | 1 fork, or 3 on a repair. | **Shared `.git/config`** (all ~37 reso worktrees). Writing takes `config.lock`. Any stale checkout's `pnpm install` can revert it (C1, `:19-20`). | With-change: the lander can own it, but sessions' commits still read it. | Currently canonical (`~/.reso/land-tools/scripts/hooks`). |
| S5 | re-exec from trunk's copy | `ship-land.sh:297-303` | Runs `exec bash $LAND_TOOLS/scripts/ship-land.sh`. The whole preamble runs again (`:41-292`): `ps -A`, `git status`, **a second `git fetch`**, a second converge. | Duplicates the preamble. One fetch has a network floor of 0.75 s (`ls-remote` measured). Only the post-exec half is visible in land.log (unaccounted time p50 3 s, p90 6.5 s); the pre-exec half is **never logged**. | Network and `refs/remotes/origin/main` (a shared ref lock). | **Obsolete**: the lander runs its own pinned tooling. | Only **ship-land.sh itself** gets pinned; see §4 on branch-copy leakage. |
| S6 | reconcile preflight | `ship-reconcile.sh:44-73` | Refuses main or a detached HEAD. Clears an "armed sequencer" and restores from the backup. Refuses a dirty tree. Requires `origin/main`. | `git status` scan (per worktree; not measured). | Per-worktree index. `git status` takes `index.lock` opportunistically. | With-change. | **The armed-sequencer check at `:57-58` never fires in a linked worktree.** It tests the literal path `${GIT_DIR:-.git}/sequencer`, but `.git` is a *file* there, so the check can never see the state. `handle_conflict` itself uses `--git-path` correctly (`:206-213`). The test (`ship-reconcile-conflict.test.ts:132`) uses a plain `git init` repo and never arms a sequencer. |
| S7 | reconcile fetch | `ship-reconcile.sh:78` | `git fetch origin main`; on failure, warns and reconciles onto the last-known ref. | 0.75 s network floor; `reconcile_s` p50 1, p90 2, max 22 (n=124). | Shared ref `refs/remotes/origin/main` (lock); FETCH_HEAD is per-worktree. **At least 4 fetches per land**: `:277` ×2 (re-exec), reconcile per round, `content_verify` `:753`, plus the backoff `:930`. | Yes: one fetcher instead of N. | *Theoretical*: a lost ref-lock race inside `content_verify` returns 1, producing exit 8 "content-verify FAILED" on a land that succeeded. Not seen in v3 rows. |
| S8 | classify + strategy | `ship-reconcile.sh:148-172` | Checks whether the branch is already on origin/main (exit 0). Computes the merge-base; lists migrations *origin* added (`THEIR_MIGS`) and migrations *I* added; sets `DRIZZLE_TOUCHED` if either side touched `drizzle/` (then `-c rerere.enabled=false`). **Strategy: `THEIR_MIGS` empty → rebase; otherwise → reset + cherry-pick.** | Pure reads, ms. | Object store (read). | Yes. | |
| S9 | backup ref | `ship-reconcile.sh:182-195`; also `ship-land.sh:814-816`, deleted at `:877` | Creates `backup/<branch>-preship`; never overwrites an existing one. | 1 fork. | Common ref store. 11 backups currently linger. | With-change: the lander works on a scratch ref and never rewrites the session's branch, so the backup becomes moot. | |
| S10 | rebase, or reset + cherry-pick | `ship-reconcile.sh:282-294` | Rebase: `git [-c rerere.enabled=false] rebase origin/main`. Cherry-pick: `RANGE=rev-list --reverse origin/main..HEAD`, then `reset --hard origin/main`, then `cherry-pick $RANGE`. The output is captured in `OP_OUTPUT`. | Seconds (part of `reconcile_s`). | **Per-worktree `index.lock`**, contended by any optional-lock `git status` in that worktree (§2.4). **Shared rr-cache** (`.git/rr-cache`, 199 entries, none newer than 7 d). **Global `rerere.autoupdate=true`.** | With-change: a dedicated worktree removes lock interference; pass `-c rerere.autoupdate=false`; the range must drop already-landed patches (§6). | Rewrites the **session's own branch in place** today. |
| S11 | `handle_conflict` | `ship-reconcile.sh:202-280` | Sorts a failed operation: not started → 7; started with no conflicted paths → **6 ("already upstream")**; non-migration conflict → 2; migration-only conflict → resolver, then `--continue` (→ 3 on failure). Aborts and restores the branch on every STOP. | ms. | As S10. | **No for exit 2** (a real conflict needs its owner). The rest is yes. | §2 has the full exit map. |
| S12 | `resolve_migration_collision` | `ship-reconcile.sh:83-145` | Adopts origin's `drizzle/migrations/`, deletes my colliding SQL and snapshot, `rm sqlite.db`, runs `pnpm generate` and `pnpm generate:schema-ddl`. Guards: DML → 5, DROP → 3, DDL body differs → 3. | Not in land.log (inside `reconcile_s`, max 22 s). *Estimated* 5–20 s (drizzle-kit + tsx). | Per-worktree `sqlite.db`, `drizzle/`. | With-change: needs a toolchain in the lander worktree; exits 3 and 5 hand back to the owner. | |
| S13 | `migrate:lint` + `db:migrate` | `ship-reconcile.sh:297-311` | Runs when either side has migrations. Lint rc 1 → 4 (rc 2 = warnings, passes). `db:migrate` failure → 4. | Rare (5 drizzle attempts in 7 d). | Per-worktree `sqlite.db`. | Yes. | |
| S14 | `cc-sem reso-land` admission | `ship-land.sh:547-548`, `:562-564` → `cc-sem.sh:212-274` | K=1 `mkdir` slot at `~/.cc-sem/reso-land/slot-1`. Polls every 1 s. Reaps only a holder proven dead. Refuses with exit 10 after 300 s. | `sem_wait_s` p50 0, **p90 148**, max 267 (n=72). A wait greater than 0 on 31 of 74 rounds (42%). 3 exit-10s in 7 d. | Box-global lane (`~/.cc-sem`). Held 8.7% of 09-22 samples; **65.6%** of the samples in 05:00–05:10Z today (load 245). | **Subsumed**: the lander is the serializer. | No FIFO order and no fairness (§3). |
| S15 | `mem-leash` | `ship-land.sh:272-275`, `:564` → `mem-leash.sh` | Runs the suite in its own process group. Samples tree RSS every 5 s. At the ceiling (25% of RAM, minimum 4 GB) it sends SIGSTOP, then kills; exit 71 is treated as a non-verdict and **lands anyway** (`ship-land.sh:595-596`). | One `ps` every 5 s. | Box memory. | Yes, unchanged. | |
| S16 | `git push` → pre-push hook | `ship-land.sh:869` → `pre-push:43-48` (`land_tools_base_preflight`), `:101-111` audit-ci, `:118-122` bottle size, **`:130-150` full `pnpm test:unit` (`cc-sem general`)**, `:404-408` design gate deferred, `:529-560` docs:gate (always) | Every gate runs inside the push, **with the ssh connection and the advertised remote sha held for the hook's whole run**. | **`push_s` p50 167, p90 251, max 557** on code lands (n=64); p50 4, p90 27 without a suite. | **The `general` lane (K=3) is shared** with `next build` (`package.json:72`), `design:gate`, `test:e2e`, and every session's `test:unit`. **Server-side race on `refs/heads/main`** during the hook. | With-change: a sole pusher ends the server-side race; the full suite should be moved into statics or honoured by token. | 6 of 15 exit-9s in 7 d were the pre-push *full* suite failing after the land had passed statics, i.e. escapes from the union selector or flakes under load. |
| S17 | `land-lock.sh` (drizzle only) | `ship-land.sh:952-965` → `land-lock.sh:89-143` | `mkdir` mutex `~/.reso/landing.lock.d` around a re-entered **whole `do_land`** (every round). | 5 holds in 7 d, all one branch; wait 0; **hold 333–2,377 s**. | Box-global lock dir; writes a second land.log row per drizzle land (`:57-60`). | **Subsumed** (§5). | The 2,377 s hold was a 5-round CAS exhaustion (exit 8): the mutex does not stop code lands winning the push race. |

**Serial service time.** This is the input for sizing a central lander. It covers a landed attempt's final round, excluding queue waits (7 d):
- Code lands: p50 366 s, p90 469 s (n=31).
- Non-code lands: p50 14 s, p90 70 s (n=45).
- Peak concurrent attempts: 4. When the lane is busy, 1 lander is running 54% of the time, 2 for 22%, 3 for 18% and 4 for 6%.

---

## 2. `ship-reconcile.sh`

### 2.1 How the strategy is chosen (`:148-166`)
- Origin already an ancestor of HEAD → exit 0, no reconcile (`:148-151`).
- `THEIR_MIGS` = migration SQL files **added on origin** since the merge-base (`:154`).
  - Empty → `rebase origin/main`.
  - Non-empty → `reset --hard origin/main` and `cherry-pick BASE..HEAD` (`:287-293`).
- The stated reason (`:16-18`, and `ship-land.sh:833-836`) is that a rebase "would drop origin's concurrent migration via the `_journal.json` merge=union driver". No test in the files read verifies this. Both paths are 3-way merges against the same base, so this claim is recorded as *stated, not verified here*.
- ship-land runs the reconcile **in full every round** so the strategy is re-chosen against the live head each time (`ship-land.sh:833-836`).

### 2.2 How `_journal.json` merge=union is handled
- `.gitattributes:11-12` sets `merge=union` on `drizzle/migrations/meta/_journal.json` and `_checksums.json`. The file itself calls this a backstop: union merging can emit invalid JSON (`:4-9`).
- A real index collision shows up as an add/add conflict on the per-migration snapshot. The resolver (`:83-145`) takes origin's whole set and regenerates my delta at the next index, so checksums and the journal are contiguous by construction. It then lints (`:297-311`).
- Rerere is disabled for drizzle-touching ranges (`:156-160`, "P10").

### 2.3 Every exit code, and how it surfaces downstream
Reconcile's exit code becomes ship-land's exit code unchanged (`ship-land.sh:843`).

| rc | Cause | file:line | land.log `exit_class` | `/ship` table says | Correct downstream meaning |
|---|---|---|---|---|---|
| 0 | Already on top / dry-run / reconciled | `:150`, `:176`, `:313` | n/a | n/a | |
| 1 | On main, detached HEAD, dirty tree, no origin/main, `reset --hard` failed, or resolver found no side / could not adopt | `:46-47`, `:71`, `:73`, `:289`, `:93`, `:110` | `other-1` | none | |
| 2 | Non-migration conflict | `:261-269` | reconcile-stop | ✔ (`ship.md:65`) | ✔ |
| 3 | `generate` / `schema-ddl` failed, no regen produced, DROP in regen, DDL differs, `--continue` failed | `:118-140`, `:277-278` | ddl-mismatch | not listed | |
| 4 | `migrate:lint` rc ∉ {0,2}, or `db:migrate` failed | `:305-310` | migrate-gate | ✔ | ✔ |
| 5 | Hand-written DML migration collides | `:97-103` | **rebase-conflict** ✗ | "rebase conflict" ✗ | Hand-renumber the DML |
| 6 | Started, then stopped with **no conflicted paths** | `:247-259` | **statics-red** ✗ | "statics red" ✗ | Mid-sequence stop, cause unknown |
| 7 | Git refused the operation before it started (e.g. `index.lock`) | `:227-236` | **escalation-parked** ✗ | "**destructive migration PARKED — operator decision**" ✗ | Passing failure, safe to retry |
| 64 | Unknown argument | `:41` | usage | none | |

### 2.4 The "already upstream" message: where it comes from and when it is false
- **Source.** `:249` prints "Cause: one of your commits is already upstream, so the pick went empty…" inside the rc-6 branch. That branch is taken when `unmerged` is empty and `started=1`, where `started` means a `rebase-merge/`, `rebase-apply/`, `CHERRY_PICK_HEAD` or `sequencer/` exists (`:209-214`). No other file prints the phrase (grepped the whole tree).
- **The message is false whenever the operation stopped for any other reason:**
  1. **Any exit 6 on the rebase path.** Rebase drops already-upstream commits and ones that become empty by default (git-rebase(1), 2.54: "`drop` … This is the default behavior"; clean cherry-picks are "dropped as a preliminary step"). *Empirical doc read; the conclusion follows directly.*
  2. **A passing `index.lock` in the middle of the sequence.** The `never started` branch catches only a lock present at start. Once `rebase-merge/` exists, a failed lock on pick N lands in rc 6. This is **the observed case** (§0.1).
     - Code that takes optional locks in session worktrees: `~/.claude/statusline.sh:309` (`git status --porcelain=v2` on every refresh); infra `bin/cc-husk-sweep:259`, `hooks/operator-readout.sh:1475`, `hooks/teammate-checkpoint.sh:294`, `hooks/waiting-recycle.sh:1136`. None of them pass `--no-optional-locks`.
     - Which one collided on 09-23 is **not recorded**: land.log keeps no reconcile output.
  3. **`rerere.autoupdate=true`** (global git config). A recorded resolution replays *and is staged*, so the operation stops with zero conflicted paths and lands in rc 6 when the right move is `--continue`. The rr-cache is shared across all worktrees (`--git-path rr-cache` resolves to the common dir). Rerere is only disabled for drizzle ranges. This path is *theoretical*: no rr-cache entries are newer than 7 d.
  4. Cherry-pick path only: a commit that was empty from the start (`--allow-empty` markers fail cherry-pick by default), or a merge commit in `RANGE` without `-m`. *Theoretical.*
- **When it is true.** The cherry-pick path hits a commit that has become empty, which the fixture test `ship-reconcile-conflict.test.ts:97-115` covers.
- **Test gap.** `:144-206` arms `index.lock` *before* the reconcile, so it tests exit 7 only. No test covers a lock mid-sequence or a stop staged by rerere.
- **History.** This is the second occurrence. The first was the 2026-08-19 W1a report quoted at `:217-223`, which produced the rc-7 split. The same wrong attribution survives in the rc-6 branch.

---

## 3. `cc-sem.sh`

- **Lanes and slot counts** (`:86-101`):

| Lane | K | Wait before refusal | Env overrides |
|---|---|---|---|
| `reso-land` | 1 | 300 s | `CC_SEM_K_RESO_LAND`, `CC_SEM_WAIT_RESO_LAND` |
| `reso-verify` | 1 | 1,800 s | `CC_SEM_K_RESO_VERIFY`, `CC_SEM_WAIT_RESO_VERIFY` |
| `general` | 3 | 900 s | `CC_SEM_K_GENERAL`, `CC_SEM_WAIT_GENERAL` |

  Lanes are separate slot directories, so `general` cannot starve `reso-land`; that isolation is the only fairness between lanes.
- **Callers** (grep of origin/main):
  - `ship-land.sh:547-548` → `reso-land` (the union suite).
  - `package.json`: `test:unit` `:126`, `build` `:72`, `design:gate` `:99` and `test:e2e` `:100` → `general`.
  - The header's "W0 SHIPS THIS WITH NO CALLERS" (`:8-10`) is stale.
- **Memory floor: has no effect.** `free_gb`/`memory_ok` (`:163-182`) is called at `:271` as `memory_ok … || true`, after every slot was found full. Its result is discarded, and the next loop pass admits on `mkdir` alone (`:228`). The comment "Below the memory floor we KEEP WAITING" (`:270`) is not what the code does.
- **Queue discipline.** Each waiter polls on its own: try `mkdir slot-1..K` (`:226-248`), check for dead holders to reap (`:250-259`), `sleep 1`. There is **no ticket, no FIFO and no aging**. The first waiter to wake after a release wins, so a 299-s waiter can lose to a newcomer and hit exit 10 at 300 s.
  - *Theoretical*; land.log does not record queue position. The 3 exit-10s in 7 d can't be told apart from simple overload.
- **Liveness.** The recorded pid is cc-sem's own bash (the job is a plain child, `:241-246`). A slot is taken over only if `kill -0` fails or a recorded start time mismatches (`:122-130`). Reaping is a `rename` followed by a group kill checked against the recorded identity (`:133-157`). There is no TTL.
- **Race window (theoretical).** A slot directory with no `pid` file yet is treated as dead immediately (`:125`). The winner's `mkdir` (an external command) and its pid write (`:233`) straddle a scheduler gap, while the loser checks right after its own failed `mkdir`. land-lock has a 5-s grace for exactly this case (`land-lock.sh:94-98`); cc-sem has none.
  - Check against the data: I rebuilt the 77 admitted `reso-land` suite intervals from land.log and found **0 overlaps longer than 20 s**. The race has not been observed.
- **What `CC_SEM_WAIT_S` measures.**
  - Whole seconds (`date +%s`) from `t0` (`:224`) to just after the slot's six metadata files are written (`:233-239`). `t0` is set after argument parsing, the no-op ladder and the lane's `mkdir -p`.
  - It includes every 1-s poll, any reap, and 2 `ps` forks. It excludes cc-sem's own startup.
  - ship-land records it through a wrapper file (`ship-land.sh:563`, `:566`) and subtracts it to get `suite_s` (`:572`).
  - Caveat: `sem_wait_s = 0` means *either* admitted immediately *or* admission bypassed (non-Darwin, no `~/.reso`, `CC_SEM=off`, re-entrant, or no cc-sem in the tree), because the wrapper writes `${CC_SEM_WAIT_S:-0}`. `null` means the wrapper never ran (refused, or failed to start). The comment at `ship-land.sh:160` ("null = no admission") is imprecise.
- **Does pre-push `pnpm test:unit` compete with land suites for slots? Not for the same slots, but it still hurts.**
  - It is the `general` lane (`package.json:126`), and ship-land holds no class at push time, so `CC_SEM_HELD` does not let it pass through and it always takes a `general` slot.
  - It is a **full** `vitest run`, running right after the land's union suite; that is about half of `push_s`.
  - Its wait is bounded by `PUSH_TIMEOUT` (120 s by default; callers evidently raise it, since the observed `push_s` goes up to 557).
  - It shares `general` with `next build`, `design:gate`, `test:e2e` and every session's tests.
  - Occupancy: `general` had 3 of 3 slots held in 0.1% of 09-22 samples and 3.3% of today's 05:00–05:10Z samples; `reso-land` was held 8.7% and 65.6% respectively.
  - The land suite itself runs `pnpm exec vitest related` (`ship-land.sh:564`), not `test:unit`, so there is no nested `general` acquire inside the `reso-land` slot.

---

## 4. `land-tools.sh`: cost per land, and races between concurrent landers

- **Cost per land** (empirical primitives, at load 155–211):
  - Reuse path: about 10–15 git forks plus 2 `find` calls, roughly 0.1–0.3 s. Fresh path: adds `git archive` (0.056 s for 13.3 MB) plus extracting about 545 files (*estimated* ≤1 s).
  - Fresh builds: 13 per 24 h (13 targets present; GC at 24 h; 173 MB store).
  - **It runs twice per land** because of the re-exec, together with a second `git fetch` (0.75 s network floor). Against a code land's 366-s p50 this is negligible; the real cost is the duplicated network fetch and the unlogged pre-exec half.
- **R1: a concurrent fresh build can delete a sibling's live target** (*theoretical*; no nested `.tmp.*` found in the store).
  - The fallback branch (`:159`) is taken when the target was *absent* at `:150`. The comment at `:174` claims the `rm -rf "${target}"` is "only reached when an existing target FAILED the guard", but it also runs when a sibling renamed the same tree into place between `:150` and `:174`, so it deletes that sibling's live, canonical target.
  - Until `:175` puts it back, `~/.reso/land-tools/scripts/hooks` does not exist. Git then runs **no hooks, silently** (`:32-33`) for any commit or push on the box. The sibling's own guard at `:228` can fail with 20–23.
  - Also, BSD `mv tmp target` onto an existing directory *nests* the source inside it rather than failing, so the "lost the rename race" fallback at `:175-179` is unreachable in the directory-exists case.
- **R2: the canon can go backwards, and the hook bytes are not pinned** (*theoretical*).
  - Two landers converging on different trunk shas each swap the symlink; the last rename wins. The newer lander's guard of the canon (`:228`) fails with 23 if the hook blobs differ.
  - More broadly, git resolves `core.hooksPath` through the symlink **at hook run time**. The push therefore runs whatever tree the *most recent* converge installed, not the pinned `LAND_TOOLS`.
  - The pin covers the ship-land re-exec and the floor check in `land_tools_base_preflight` (`:244-246`), not the hook bytes. land.log's `hooks_tree` records `HEAD:scripts/hooks`, not the bytes that actually ran.
- **R3: config write** (`:209`). This takes `.git/config.lock`, and a stale checkout's install can revert the setting at any time. Low risk.
- **Branch-copy leakage** (empirical code read). The re-exec pins only `ship-land.sh`. In round 1, these all run the **session branch's pre-reconcile copy**:
  - `ship-reconcile.sh` (`ship-land.sh:840`, relative path);
  - `land-tools.sh` (`:290`, sourced from `REPO_ROOT`, before and again after the exec);
  - `cc-sem.sh` (`:547`);
  - `mem-leash.sh` (`:273`);
  - `land-lock.sh` (`:959`).

  A branch cut before a fix runs the old code; for example, a branch older than 09-04 would still have the empty-pick path that returns success. So the comment's claim that "trunk's lane gates the land" (`:295`) is false for these steps. A central lander fixes this by construction.

---

## 5. `land-lock.sh`: what is in force, and how a lander absorbs it
- **In force** (W3a):
  - **No TTL.** `LAND_LOCK_TTL` is no longer read (`:34-35`).
  - A holder is treated as dead only if `kill -0` fails or its recorded start time provably differs (`:77-86`). The one remaining age read is a 5-s grace for a lock directory that has no pid yet (`:94-98`).
  - Taking over a dead lock means `mv` to `.reap.$$`, `rm -rf`, `mkdir` (`:102-106`). It does **not** kill the dead holder's group, so `ship-reconcile.sh:50-52`, which says "the landing lock's reap kills a wedged holder's whole process group", is stale.
  - Waits up to 3,600 s, polling every 2 s, then exits 75 (`:47-48`, `:113-122`).
  - Writes a v1 row to land.log on release (`:128-134`), which gives the log **two rows per drizzle land**.
  - *Theoretical* check-then-act gap: two waiters can judge the same dead holder, one takes over and re-acquires, and the other's `mv` then renames the *new* live lock.
- **Observed** (7 d): 5 acquisitions, all by `sec-w6-w4a7b-deaction`, wait 0, holds 333/649/670/727/2,377 s. It serializes only drizzle lands against each other; code lands keep racing it on CAS, as the 5-round exit 8 shows.
- **Under a central lander.** One lander that reconciles, gates and pushes one branch at a time makes the `_journal.json` index collision a **reconcile-time** event, which the resolver in S12 already handles deterministically, rather than a race. The mutex, its log row and the `--__locked-land` re-entry (`ship-land.sh:952-972`) become redundant. This holds only if the lander is the **only** pusher to `main`; `LAND_LANE=v1` (`ship-land.sh:81-85`) and hand-run `git push` break that.

---

## 6. What a central lander must change
Everything below is *theoretical* design reading, grounded in the steps above.
1. **Work on a lander-owned scratch ref or detached HEAD, and never rewrite the session's branch.**
   - Consequence: sessions keep their pre-land commits.
   - On the rebase path, patch-identical commits are dropped harmlessly.
   - On the **cherry-pick path**, replaying already-landed commits produces genuine empty picks (a *true* rc 6). Use `cherry-pick --empty=drop` or build `RANGE` from `rev-list --cherry-pick --right-only origin/main...HEAD`.
2. **Give the lander its own worktree** that no statusline, sweeper or hook runs `git status` in. This removes the mid-sequence `index.lock` stop (§2.4-2). Run git with `-c rerere.autoupdate=false`, or disable rerere, to close §2.4-3.
3. **Fix the sequencer-recovery check to use `git rev-parse --git-path`.** The literal `.git` check (`ship-reconcile.sh:57-58`) is dead in a linked worktree, and a long-lived lander will need crash recovery.
4. **Hand back rather than block** on rc 2 (conflict), 5 (DML) and 3 (DDL mismatch): these need the owning session.
5. **Decide the pre-push full suite.** Today it runs inside the push window, and that window both causes the server-side CAS loss and hides `general`-lane waits. Options: move it into the lander's statics before the push, or honour the presubmit token (W3b, unwired). Dropping it has a measured cost of 6 rejections in 7 d.
6. **Fix `ship-land.sh:889-892` either way:** add `*"cannot lock ref"*` / `*"but expected"*` to the CAS pattern. **Split the exit codes:** reconcile 6/7 must not reuse ship-land 6/7.

---

## 7. Alternatives considered and ruled out
- **"The 09-23 exit 6 was a real empty pick."** Ruled out. The same 4 commits rebased cleanly onto the same base 21 s later, and rebase cannot stop on an empty pick in any case.
- **"It was a rerere-staged conflict."** Ruled out for this case: the same merge would have recurred 21 s later. It stays a live path in general.
- **"Pre-push `test:unit` competes for the `reso-land` slot."** Ruled out: different lane directory and no nested acquire. The competition is for CPU and for `general` slots.
- **"cc-sem's K=1 lane has let two land suites run at once."** Not observed: 0 overlaps longer than 20 s across 77 rebuilt intervals.
- **"land-tools cost is significant per land."** Ruled out: sub-second primitives. The duplicated fetch and preamble matter more, and even those are small against 366 s.

## 8. Blockers and uncertainties
- **The git error text for the 09-23 false exit 6 cannot be recovered.** The v3 row has no reconcile-output field, and the worktree (with its HEAD reflog) was reaped around 05:16Z. The reflog lines quoted in §0.1 are the only surviving copy; the branch reflog in the common dir survives.
- The pre-exec half of the preamble (the first fetch and converge) is never timed: `ts_start` is taken after the exec.
- The resolver's cost (S12) is unmeasured; `reconcile_s` has a maximum of 22 s but no field of its own.
- The claim that "rebase would drop origin's migration" (`ship-reconcile.sh:16-18`) was not verified.
- Which process held `index.lock` at 03:28:31Z is not recorded; the candidates are listed in §2.4.

## 9. Adversarial pass (what was checked, and what it changed)
- **Is rerere autoupdate actually on?** Checked: set globally (`rerere.enabled=true`, `rerere.autoupdate=true`), and the rr-cache is shared (199 entries, none newer than 7 d). This moved the rerere path from assumed to live-but-latent.
- **Does double admission really happen in cc-sem?** Rebuilt the `reso-land` intervals from land.log: none found. The empty-pid race is downgraded to theoretical.
- **Is the drizzle mutex actually contended?** 7-d rows: wait 0 on all 5. Found instead that it held for 2,377 s while losing 5 CAS rounds to code lands. This reframed land-lock as "serializes the wrong set".
- **Did content-verify's fetch ever falsely fail?** No exit 8 with push rc 0 in any v3 row; kept as theoretical.
- **Are the exit-code collisions ever hit?** Exit 6 yes (1 of the 9 "statics-red" rows in 7 d). Reconcile 7 and 5 have not been hit in v3.
