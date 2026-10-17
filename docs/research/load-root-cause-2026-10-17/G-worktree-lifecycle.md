# Axis G: event-driven worktree lifecycle that never deletes something that will be needed later

Measured 2026-10-17, 02:20 to 02:50 CDT, read-only. I removed, pruned, locked and signalled nothing. I ran no reaper, not even
with `--dry-run`, as `docs/plans/WORKTREE_MANAGEMENT_V2.md:33-42` (HAZARD RULE) requires. Every number below is tagged
**[M]** (measured, with the command named in §9) or **[E]** (estimated, with the method named).

---

## 0. Verdict

1. **Worktrees are not a measurable driver of the current load average.** Of 92 dev processes (node, Python, esbuild and
   similar), 37 run with a cwd inside `~/Development/.worktrees`. 36 of those 37 are in LIVE worktrees. The other one is
   a 5 MB node at 0.0% CPU in a pool slot [M]. Idle worktrees hold no CPU or RAM. The janitors themselves cost about
   370 s/day: the nightly row reads `elapsed=370s` [M]. On disk the footprint is 156 GB, which is 2.1% of a 7.28 TiB
   volume that still has 3.71 TiB free [M, `df -k`]. So the lifecycle problem is a **correctness and toil problem, not a
   load problem**. The load-relevant parts are small:
   (a) every clean worktree gets a full file-tree `find` walk on every sweep, including `node_modules` and `.venv` (§4 D6).
   (b) The reactive "prune old worktrees" sessions are full Claude sessions that run git and du sweeps by hand. About 10
       top-level transcripts since 2026-08-25 match that phrasing [E, phrase match].
2. **The real root cause is structural.** Seven independent actors remove worktrees, and only two of them write a
   tombstone. The tombstone they write has no `repo` field. The resume path does not restore a reaped worktree: it runs
   `mkdir -p`, which gives an **empty** directory (`lib/cc-resume-shell.sh:138-155`). The removers are therefore forced
   into one of two failures:
   - **Too conservative.** 96 unlanded and 67 dirty or untracked worktrees are kept forever. 32 "unowned" ones are
     waiting on a hand-written warrant every night: `verdict=stranded-over-ceiling` on each of the last 4 nights [M].
   - **Too eager.** 147 transcripts active within the last 7 days point at a cwd that no longer exists [M]. For 62 of
     them nothing recorded what was there.
3. **What makes event-driven pruning safe is reversibility, not more gates.** If every removal writes a complete
   tombstone, and every resume path restores from it (`git worktree add` from branch or sha, plus the preserved
   non-cache ignored files), then "this might be referenced later" stops being a reason to keep a checkout. The events
   can then fire minutes after a session ends instead of waiting for the 04:15 backstop or a human warrant.

---

## 1. Census: who owns `~/Development/.worktrees`, and in what state [M]

### 1.1 Ownership

There are 325 top-level entries [M: `ls -1 | wc -l`]. Resolving each one's `.git` file gives:

| Owner | Top-level dirs | Registered under `.worktrees` (porcelain) | Local branches |
|---|---|---|---|
| claude-infrastructure | 133 | 139 (3 locked, 12 detached) | **3,448** |
| doc_classifier | 62 | 62 | 77 |
| reso-management-app | 35 | 35 (5 locked, 16 detached) | 208 |
| reso-web-app | 17 | 17 | 25 |
| lakehouse-lecture | 12 | 12 | 26 |
| sevenrooms-bridge | 8 | 8 | 10 |
| agent-context-sync | (nested under `b13/`) | 7 | 34 |
| personal | 6 | 6 | 7 |
| voiceink, reso-landing-app, 4 single-repo owners, 1 clone | 13 | 6 | n/a |
| **NOGIT** (not a worktree) | **26** | n/a | n/a |

`prunable` is 0 for every repo [M]. Some of the 26 NOGIT dirs are parents of slashed names (`fix/`, `feat/`, `docs/`).
Others are husks that hold only `.next/`, `.claude-plans/` or `.claude-tasks/`: `wt-cc-233935-83744`,
`wt-cc-010754-47727`, `wt-cc-234200-24894`, `bs-tableside-font`. A husk with only `.claude-*` content is what a session
start leaves in an **empty directory recreated by the resume path** (§4 D2), or what a dev server leaves when it
rewrites `.next/` after a removal [E, from the contents; no process attribution available after the fact].

### 1.2 State of the 291 registered worktrees

| State (exclusive, first match wins) | n | Tip age <1d / 1-3d / 3-7d / 7-30d / >30d |
|---|---|---|
| LIVE (live claude cwd per lsof, or a row in `~/.reso/live-sessions`) | 16 | 12 / 1 / 3 / 0 / 0 |
| UNLANDED (`git cherry <origin/HEAD> HEAD` has a `+`) | 96, carrying **1,640** `+` patches | 7 / 0 / 6 / 26 / 57 |
| DIRTY-landed (tracked changes, nothing unlanded) | 46 | 2 / 1 / 0 / 2 / 41 |
| UNTRACKED-landed (only `??` files) | 21 | 0 / 0 / 0 / 1 / 20 |
| LANDED-CLEAN | 112 | 38 / 0 / 3 / 16 / 55 |

Caveats:
- "Landed" is measured against each repo's `origin/HEAD` **without a fetch**, because a fetch writes refs. A stale
  remote-tracking ref biases the result toward UNLANDED. That is the safe direction, and it is F-3 in the plan.
- The 1,640 count is a per-worktree sum. It is not deduplicated by patch-id, so read it as an upper bound
  (plan §1.2 measured a 2.3x duplication factor).

**LANDED-CLEAN by repo and age:**

| Repo | Ages | Collector |
|---|---|---|
| claude-infrastructure | <1d 33, 3-7d 3, 7-30d 3, >30d 3 | Nightly 04:15. The 33 younger than a day are the land-then-wait-for-04:15 gap. |
| doc_classifier | >30d 25, 7-30d 1 | none |
| reso-web-app | >30d 12, 7-30d 1, <1d 2 | none |
| lakehouse-lecture | >30d 10 | none |
| sevenrooms-bridge | >30d 4, 7-30d 4 | none |
| reso-management-app | 7-30d 5 | reso's own wake-driven janitor |
| personal | 7-30d 2 | none |
| reso-landing-app | >30d 1 | none |

So **184 of the dirs (`pop_foreign=184` on the 2026-10-16 nightly row) belong to repos with no collector, except for
reso's 35**. That explains why the population is permanently "over ceiling".

### 1.3 Disk: 15 sampled dirs [M: `du -sk`, per dir and per cache subdir, `gtimeout 60` each]

| Sample | Total | Reproducible caches (`node_modules`, `.venv`, `.next`) | Cache share |
|---|---|---|---|
| 6 LANDED-CLEAN | 3.78 GiB | 2.41 GiB | 64% (the outlier `wt-pool-7` is 2.57 GiB, 83% caches) |
| 4 UNLANDED | 2.23 GiB | 1.49 GiB | 67% (`wt-35cae65a8d2d` is 0.84 GiB, with `.venv` alone at 0.54 GiB) |
| 4 DIRTY | 0.69 GiB | 0.51 GiB | 74% |
| 1 LIVE | 0.26 GiB | 0 | n/a |
| **All 15** | **6.97 GiB** | **4.40 GiB** | **63%** (52% excluding the pool slot) |

Prevalence across all 291 [M, census]: `node_modules` in 166, `.venv` in 63, `.next` in 19.
- An infra checkout is about 9,018 tracked files [M: `git ls-files | wc -l`] plus about 2,600 files in `node_modules`
  [M: `find -type f | wc -l`, 1 sample].
- A doc_classifier `.venv` is about 14,291 files [M, 1 sample].

**Reclaimable estimates [E]:**
- DETACH of the 112 LANDED-CLEAN at the measured mean of 156 GB / 291 ≈ 0.54 GB each comes to about **60 GB**. The
  plausible range is 28-74 GB, using the sample mean with and without the pool outlier.
- DEHYDRATE (caches only) of the 142 DIRTY and UNLANDED trees older than 7 d, at the sampled 67-74% cache share of
  about 0.5 GB, comes to about **45-50 GB**.

None of this space is needed: 3.71 TiB are free.

### 1.4 "Referenced later": the resume dependency [M]

- **Gone cwds.** Across the 4 primary config roots, 231 worktree-keyed project dirs have a transcript modified in the
  last 7 d, and **154 of them (67%) record a `cwd` that no longer exists**: 147 unique paths. Method: newest jsonl's
  first `"cwd"`, then `[ -d ]`.
  - **85 of the 147 have a tombstone** in `~/.claude/autonomy/worktree-disposals.jsonl`.
  - **0 of those 85 branches still exist.** `--prune-branches` deleted them after the landed removal.
  - **70 of the 85 heads still resolve**, all of them ancestors of `origin/main`. So a restore by **sha** works where a
    restore by branch, which is what `reso-resume-one` attempts, cannot.
  - **62 have no tombstone.** 68 of the gone paths are agent-context-sync `b13/<round>-<lane>` lanes (r3 through r12,
    lane-a through f), whose branches are all deleted (`show-ref` returns n for 68/68) and for which no tombstone exists.
    I found no code in either repo that removes them (`git grep 'worktree (remove|prune)'` in agent-context-sync returns
    0), so a lead or a hand removed them with raw git: the reactive pattern the operator describes.
- **Existing worktrees with resumable transcripts.** Of the 291 worktrees that still exist, 118 have a transcript
  project dir. By state:

  | State | <1d | 1-7d | 7-30d | >30d | none |
  |---|---|---|---|---|---|
  | LANDED-CLEAN | 36 | 3 | 7 | 18 | 48 |
  | UNLANDED | 1 | 6 | 10 | 6 | 73 |
  | DIRTY | 2 | 0 | 1 | 12 | 52 |

  So most LANDED-CLEAN trees younger than a day have a session that could be resumed within the harness's 30-day
  `cleanupPeriodDays` (`scripts/cc-gc.sh:27-35`). Today the nightly removal turns each of those into an empty-dir resume.
- **Plan citations.** Only 29 distinct worktree names are cited by path in `~/.claude/plans` and `docs/plans`, and 7 of
  those still exist [M: `rg -o 'Development/\.worktrees/…'`]. As a "referenced later" signal, plan citation is real but
  small.

### 1.5 The ledger as a tombstone store [M]

`worktree-disposals.jsonl` has 637 rows: 622 from `actor` worktree-gc and 15 from cc-reaper.
- Fields: `ts, path, branch, head, unlanded_patches, patch_shas, owner_item, owner_proof, idle_hours, preserved_at,
  verified, destroyed_ignored, actor`.
- **None of the 637 rows has a `repo` field.**

What the ignored content it records shows was destroyed:

| Ignored path | Times destroyed | Note |
|---|---|---|
| `*/__pycache__/` | 908 | regenerable |
| `.claude-tasks/` | 471 | symlinks into the task store (plan §9.2) |
| `node_modules/` | 445 | regenerable |
| `.ruff_cache` | 170 | regenerable |
| `.claude/settings.local.json` | **87** | per-worktree permission grants |
| `brag-output/` | **5** | generated output |
| `.env.local` | **3** | |
| `sqlite.db` | **3** | |
| `*.sqlite` research DBs | **4** | |
| `screenshots/` | **1** | |

So the "record, don't gate" policy (`scripts/worktree-gc.sh:1285-1293`) did destroy content that cannot be recreated:
at least 3 env files, 3 local DBs and 5 generated-output dirs.

### 1.6 Timeliness [M]

- Disposals per day, 2026-10-03 to 10-16: 11, 19, 40, 26, 5, 11, 18, 14, 16, 58, 15, 7, 5, 11.
- The nightly population was 294 → 284 on 10-16. It reached 325 dirs by 02:46 on 10-17, a net gain of about 41 in
  22.5 h.
- The nightly row (`~/.claude/autonomy/worktree-gc-infra.last`) read `verdict=stranded-over-ceiling removed=11 kept=105
  refusals=135 pop_owned=100 pop_foreign=184 unowned=32 stranded_branches=53 rc=3`.
- KEEP reasons on that sweep:

  | KEEP reason | n |
  |---|---|
  | dirty, `assets/banner/recycle-bmo.svg` absent from origin/main (one fleet artifact, as in plan §9.1) | 30 |
  | unlanded, no owning backlog item | about 26 |
  | detached HEAD | 9 |
  | LIVE | 8 |
  | parked `out/` dirs | 3 |
  | locked-and-gone records | 3 |

---

## 2. What already exists: the actor inventory

| # | Actor | Trigger | Removal | Tombstone? | Repo scope |
|---|---|---|---|---|---|
| A1 | `scripts/worktree-gc.sh`, via `scripts/worktree-gc-infra-run.sh` | launchd `com.claude.worktree-gc-infra`, **04:15 calendar only**. No WatchPaths [M: plist dump]. | `git worktree remove` without `--force`; branch `-d`; `worktree prune` (:1112) | yes, `log_disposal` (:1000-1020), no `repo` | **one repo**: `REPO=` at `worktree-gc-infra-run.sh:22` |
| A2 | reso `scripts/launchd/bin/worktree-gc-run.sh` | launchd `gl.reso.worktree-gc`: 03:15 **plus `WatchPaths ~/.reso/worktree-gc.wake`**. reso's `.claude/settings.json:140` (SessionStart) and `:162` (SessionEnd) touch the wake file, and so does `worktree-pool.sh:592,629`. 60 s debounce, two-strike grace. | in-repo janitor | reso's own log | reso only |
| A3 | `bin/cc-reaper` `worktree_cleanup` (:1756-1822) | launchd every 300 s, **after a confirmed pane teardown**. This is already event-driven. | `git worktree remove` without `--force` (:1814), per-sweep bound | yes, `log_worktree_disposal` (:1824), no `repo` | any `*/.worktrees/*` |
| A4 | `hooks/teammate-auto-shutdown.sh:1559-1564` | teammate idle → close | **`--force`** | **no** | any |
| A5 | `scripts/handoff-fire.sh:16609` fire-cleanup | failed fire | **`--force`** | **no** | any |
| A6 | `scripts/cloud-reconcile.sh:357` | reconcile | **`--force`** | **no** | any |
| A7 | `scripts/ship-land.sh:1108`, `scripts/desk-land.sh:92` | temp land trees | `--force` on its own mktemp trees | no (not needed: temp, never a session cwd) | n/a |
| A8 | `scripts/cc-gc.sh:448` "worktrees" EXEC delegate | launchd `com.claude.cc-gc`, every 6 h | calls A1 | n/a | n/a: **red on 171/171 runs** (§4 D3) |
| A9 | manual raw git (b13 lanes, "prune old worktrees" sessions) | a human or a lead noticing | anything | **no** | any |

Supporting pieces that already exist:
- Liveness registry: `hooks/live-session-registry.sh`, registered on SessionStart and removed on SessionEnd at :47-56.
- Guard: `hooks/git-worktree-guard.sh` blocks a raw `worktree remove` while the tree is live, and a branch `-D` while a
  worktree exists (:64, :142).
- The resume chain:
  - `bin/cc-resume-resolve` reports `cwd_exists=0`.
  - `lib/cc-resume-shell.sh` `_cc_resume_pin`, called from `~/.zshrc:172,475`.
  - `bin/reso-resume-one:439-495` recreates from the **branch**, finding the repo through the `.git/worktrees/<n>/gitdir`
    back-reference.
  - `scripts/boot-resume*.sh` reaches reso-resume-one through `boot-resume-launch.sh:203`.

**Prior design.** `docs/research/memory-econ-rearchitecture-2026-08-10/worktrees.md` §6 and §15 already proposed edges
E1 to E9. Their status today, from reading the files:

| Edge | What it is | Status |
|---|---|---|
| E1 | infra WatchPaths | **not built** (plist has no WatchPaths) |
| E2 | global SessionEnd touch | **not built** (no `worktree-gc.wake` in hooks, scripts, bin, launchd or commands) |
| E3 | `/ship` touch | **not built** |
| E4 | landed-dirt class | **built** (plan §9), and switched on 2026-09-30 (`worktree-gc-infra-run.sh:463-473`) |
| E5 | cc-reaper writes warrants | **not built**: the only "warrant" hits in cc-reaper (:257, :274) are about desk pages |
| E8 | repo list | **not built** |
| E9 | branch-reaper scheduled | **not built** (no plist references it) |

So the event plumbing was designed two months ago, and only the content-proof edge shipped. Section 5 does not repeat
that design. It adds the part §6 lacked: **reversibility (tombstone plus restore)**, which is what lets the events be
aggressive without being premature.

What WORKTREE_MANAGEMENT_V2 built vs left open:
- **Met:** AC-1, AC-3, AC-7, AC-8, and R-a through R-d closed or rescoped.
- **Still open:** AC-4, AC-5, AC-6, F-9 (lock heartbeat), and the AC-2 adjudication (§7.3, §8.4).
- It never addressed:
  - coverage of the other repos (it is single-repo by construction, `worktree-gc.sh:13-15`);
  - the resume dependency;
  - the five removers that write no tombstone;
  - triggering by events.

---

## 3. Root-cause chain

1. A removal leaves no complete, repo-qualified record of path, repo, branch, head and preserved content (A4, A5, A6
   and A9 leave nothing; A1 and A3 leave rows with no `repo`). Then:
2. → Nothing can restore from it. The resume path makes an empty dir (`lib/cc-resume-shell.sh:151`). `reso-resume-one`
   needs a **branch** that `--prune-branches` has already deleted (0/85, §1.4), and needs a `.git/worktrees` back-reference
   that `git worktree remove` and `worktree prune` (`worktree-gc.sh:1112`) delete.
3. → So every removal is effectively irreversible, and safe actors must demand owner-terminal proof or a manual warrant
   (`worktree-gc.sh:42-90`).
4. → So 163 non-live trees that are unlanded, dirty or untracked are kept indefinitely, 32 unowned ones need a human
   every night, and 184 foreign-repo trees have no actor at all.
5. → So the population drifts until someone notices, and then cleans up by hand (A9), which makes it worse:
   no tombstones (the 68 b13 lanes).

The **events** are not the missing piece. A2 and A3 already prove event triggers work on this box. The missing piece is
the **reversibility** that would make it safe to act on those events.

---

## 4. Defects found (each with file:line and evidence)

**D1. Five of the seven removers write no tombstone, and the two that do omit `repo`.**
- Sites: `hooks/teammate-auto-shutdown.sh:1562`, `scripts/handoff-fire.sh:16609`, `scripts/cloud-reconcile.sh:357`;
  ledger rows from `worktree-gc.sh:1015` and `bin/cc-reaper:1824`.
- Evidence: 0 of 637 rows carry `repo` [M]. 15 of 85 tombstoned heads do not resolve in the infra repo [M], which is
  consistent with cc-reaper rows from other repos with no way to tell which.

**D2. Resuming into a reaped worktree creates an EMPTY directory.**
- `lib/cc-resume-shell.sh:138-155`: `mkdir -p "$_cwd"`, then a warning that the working tree does not resume.
- The session is then running in a directory that has no git, no files and no branch. It also leaves a NOGIT husk under
  `.worktrees` that no collector will ever enumerate, because `worktree-gc.sh:13-15` reads porcelain only.
- `bin/cc-resume-resolve` already outputs `cwd_exists=0`, so the decision point is in place. It just has no restore
  source to call.

**D3. cc-gc's worktree adapter is inverted: dead on its schedule, destructive in its "dry-run".**
- `scripts/cc-gc.sh:380` passes `--apply` to `worktree-gc.sh`, which rejects unknown flags with exit 2
  (`worktree-gc.sh:182-185`). `cc-gc.out.log` shows `worktrees EXEC red … delegate rc=2` on **171 of 171** runs [M].
- Without `--apply` (cc-gc's documented default "DRY-RUN BY DEFAULT", `cc-gc.sh:36`), line 381 calls `worktree-gc.sh`
  with **no arguments**. That is the janitor's **destructive default** (`worktree-gc.sh:93`, "remove reapable
  worktrees").
- So an operator who types `cc-gc.sh` to look at things would trigger a real sweep.
- Its own design rule (EXEC vs ASSERT, `cc-gc.sh:10-24`) says a store whose owner already exists, here
  `worktree-gc-infra`, should be ASSERT.

**D4. Only one repo is collected.**
- `scripts/worktree-gc-infra-run.sh:22` hardcodes the infra repo.
- 184 foreign dirs, including 63 LANDED-CLEAN trees older than 7 d in doc_classifier, reso-web-app, lakehouse-lecture
  and sevenrooms-bridge, have no actor except A3, which acts only on a pane teardown.

**D5. No event wakes the infra janitor.**
- Neither the plist nor `~/.claude/settings.json` SessionEnd (7 hooks, none touching a wake file) nor the
  `ship-land.sh` land row (`attest_land`, :737-785) signals it.
- Result: 33 infra LANDED-CLEAN trees sat younger than a day, waiting for 04:15 [M].

**D6. The gate order makes every sweep walk the whole tree of worktrees whose verdict is already KEEP.**
- `recently_active` (`worktree-gc.sh:616-628`) is `find "$path" -path .git -prune -o -type f -mmin -30`. That walks
  `node_modules` and `.venv` (2.6k to 14k or more files each).
- `process_record` evaluates it at about :1139, **before** the age floor and the `landed` and owner checks (about
  :1153-1177). So each of about 54 infra worktrees that are clean but unlanded (KEEP regardless) pays a full walk on
  every pass, and an unchanged population is re-walked every night.
- Moving the decisive KEEPs (idle floor, unlanded with no owner-terminal and no warrant) ahead of `recently_active`
  produces **the identical removal set** with fewer walks. A KEEP is an OR, so the order in which KEEP gates run cannot
  change which trees reach removal. Only the reason printed for a tree that is kept changes.

**D7. Native `git worktree prune` (`worktree-gc.sh:1109-1112`) deletes the admin entries of crashed or rm'd worktrees.**
Those entries are the only back-reference `reso-resume-one:411-415` uses to find a reaped tree's repo. Prune destroys
the evidence without recording it.

**D8. A crash-class death does not pin its worktree.**
- `hooks/lead-crash-watchdog.sh:2201-2203` appends `class=CRASH` to `~/.claude/logs/claude-crashes.jsonl` (5,860 rows)
  with no `cwd` and no pin.
- A crashed session is the one most likely to be resumed (boot-resume, limit-recover). Its worktree can still be
  removed by A3 once its tree is clean.

---

## 5. Design: event-driven, tiered, reversible

### 5.1 Tiers and exact predicates

The common gates **G-live** (all must pass) are the existing oracles, unchanged:
- `is_live_cwd`, `registry_live` (:503), `session_registry_occupied` and `session_occupancy_keep` (:559-600),
  `op_in_progress` (:755);
- not `locked`, not `.teammate-busy`, not in `CC_WTGC_EXCLUDE`;
- plus an act-time `recheck_live` (:951).

| Tier | Entry predicate (all must hold) | Action | Reversal |
|---|---|---|---|
| **ACTIVE** | default | none | n/a |
| **DEHYDRATED** (optional, P2) | G-live; tip and newest transcript for this cwd both ≥ 7 d; each target dir is (a) in the allowlist `node_modules .venv .next __pycache__ .ruff_cache .mypy_cache .pytest_cache .turbo .eslintcache *.tsbuildinfo`, (b) `git check-ignore -q` true, and (c) reproducible from a lockfile present in the tree (`package-lock.json`, `pnpm-lock.yaml`, `yarn.lock` → node_modules; `uv.lock`, `requirements*.txt` → .venv; `.next` and the caches always). **Never** an arbitrary ignored path: `.env*`, `*.db`, `*.sqlite`, `brag-output/`, `screenshots/`, `out/`, `dist/` and `.claude/settings.local.json` are not on the allowlist. | Delete the allowlisted dirs. Write `$(git rev-parse --git-dir)/dehydrated` listing what was removed and the lockfile hashes. | The provisioning step reinstalls them: reso SessionStart `pnpm install` (reso `.claude/settings.json:125`), or `hooks/worktree-setup.sh` / `scripts/new-worktree.sh` |
| **DETACHED** | G-live, plus every one of the following:<br>• tracked tree clean, or `dirt_landed` (:655) true;<br>• **no untracked non-ignored files**;<br>• ignored inventory = allowlisted caches + **preserved residue ≤ 50 MB**. Anything over 50 MB means KEEP and report;<br>• no pin (§5.3);<br>• then one of three timing conditions:<br>(i) **landed** (`landed()` :630): grace ≥ 30 min after the last SessionEnd or registry removal for this cwd, and no transcript write for 30 min;<br>(ii) **unlanded**: tip ≥ 7 d **and** newest transcript for this cwd ≥ 7 d **and** the branch ref resolves to HEAD (A3 proof, `durable_refs` :751). No warrant or owner proof needed, because nothing is lost;<br>(iii) **detached HEAD**: as (ii), and a `refs/wt-tombstone/<id>` ref is created at HEAD first. | Write the tombstone (§5.2) **before** removal. Tar the non-cache ignored residue into the tombstone dir. Then `git worktree remove` without `--force`. Verify after: the ref still at the sha (`verify_preserved` :990). | `cc-wt-restore <path>`: `git worktree add` from branch, else `-b <branch> <head>`, else `--detach <head>`. Then untar the residue and kick provisioning. **Seconds** for git [E: 9k-file checkout]; dependency install is lazy. |
| **ARCHIVED** | DETACHED ≥ 30 d **and** the branch is about to be deleted by `--prune-branches` or `branch-reaper.sh` **and** unlanded patches > 0 | `git bundle create <tombstone>/<id>.bundle <branch>`, so the commits survive after the ref is deleted. A landed branch needs no bundle: its head is on trunk, as the 70/85 resolvable heads show. | `git fetch <bundle> <branch>`, then as DETACHED |

**Why DETACH without a warrant is not premature.** The DISPOSE class requires owner-terminal proof (A2,
`worktree-gc.sh:42-62`) because disposal used to be effectively permanent for anything outside the branch:
- ignored content was destroyed;
- the repo could not be identified afterwards;
- resume got an empty dir.

The tiers above remove all three sources of loss:
- non-cache ignored content is preserved in the tombstone;
- the repo is recorded at removal;
- restore is real.

The remaining risk is the "lead owns it remotely" case (`docs/lessons/a-cwd-census-cannot-see-a-worktrees-owner.md`).
The lesson's own rule is "recency beats presence", and the 7 d tip and transcript floor on the unlanded arm is a
recency proof. Even if a remote lead does touch it after that, the worst case is one failed `git -C` and one restore
call. Nothing is lost.

### 5.2 Tombstone record

Append-only JSONL at `~/.claude/autonomy/worktree-tombstones.jsonl`, one row per removal. Content goes under
`~/.claude/autonomy/worktree-tombstones/<id>/`.

```
{"ts","event":"worktree-detached|worktree-disposed|admin-pruned|branch-deleted",
 "actor","reason","repo":"<abs main worktree from git rev-parse --git-common-dir>",
 "path","branch","head","upstream","trunk","landed":true|false,"unlanded_patch_ids":[…],
 "sids":[<sessions whose transcript cwd == path, from cc-registry / registry rows>],
 "preserved":"<id>/ignored.tgz|null","preserved_list":[…],"dehydrated":[…],
 "lockfiles":{"package-lock.json":"<sha256>",…},"bundle":null|"<id>.bundle"}
```

- Implement it once, as `scripts/lib/wt-tombstone.sh` (`wt_tombstone <path> <actor> <reason>`). Every remover calls it
  **before** its `worktree remove`.
- Extend the existing `log_disposal` (:1000) and `log_worktree_disposal` (`cc-reaper:1824`) rather than adding a third
  ledger. The cc-reaper comment at :1825-1829 already argues for one ledger, so the new fields and the `branch-deleted`
  and `admin-pruned` events go into `worktree-disposals.jsonl` itself.
- **branch-deleted** rows come from `--prune-branches` and `scripts/branch-reaper.sh`. They make sure a restore knows to
  use the sha.
- **admin-pruned** rows come from `worktree-gc.sh:1112`, which reads `worktree prune --dry-run -v` first; this closes
  D7.

### 5.3 "Still referenced later": signals, where each comes from, and the effect

| Signal | Source (exists today) | Effect |
|---|---|---|
| Unlanded commits | `landed()` :630, `unlanded_set` :744 | DETACH only via arm (ii); ARCHIVE before the branch is deleted |
| Untracked non-ignored files | `git status --porcelain` `??` | **KEEP**. These are the one thing a tombstone does not carry (they could be large or important). Report them. |
| Non-cache ignored files | `ignored_inventory` :856 | Preserved in the tombstone (≤ 50 MB), else KEEP. This settles the AC-2 dispute (plan §7.3): neither KEEP-inert nor destroy. |
| Live or occupied session | G-live oracles | KEEP |
| Resumable transcript (cwd == path, mtime < 30 d) | `bin/cc-resume-resolve` logic (transcript `cwd`) | **No longer a KEEP reason once restore exists**. It only sets the grace window (arm (i) 30 min, arm (ii) 7 d). Before P0-2 ships, keep the current behaviour. |
| Crash-class death | `hooks/lead-crash-watchdog.sh:2201` | **PIN**: `git worktree lock --reason "crash-resume-pending sid=<sid> <ts>"`. Every actor already honours locks: gate 2, `:1125`; a single `--force` cannot remove a locked tree. Unpin on a later SessionEnd of a resume of that sid. |
| Open backlog item or plan doc naming the path | `cc-backlog`, `docs/plans`, `~/.claude/plans` (29 names, 7 existing) | PIN while the item is open (low volume) |
| `.teammate-busy`, `CC_WTGC_EXCLUDE`, locks | already honoured | KEEP |

### 5.4 Events: who emits them, and the exact site

All of these only **enqueue**. The wake file is a signal, never an argument (memory-econ §15: the janitor re-derives
and re-checks liveness at act time). Each one appends `{"ev","path","sid","repo","ts"}` to
`~/.claude/state/wt-events.jsonl` and touches `~/.claude/state/worktree-gc.wake`.

| Event | Emit site | What it enqueues |
|---|---|---|
| **SessionEnd** | `hooks/live-session-registry.sh:47-56` (the SessionEnd branch already has `cwd`, `sid` and the reason in the payload) | the cwd → evaluate arm (i) after 30 min of grace |
| **Land via /ship** | `scripts/ship-land.sh` `attest_land` :737-785, after the `printf >> land.log` at :777, when `$4 == 0` and stage is `land` | `REPO_ROOT` (the author worktree) → becomes landed; arm (i) once its session ends. The rule "ship owns the tree" (`.claude/rules/agent-operating-lessons.md:37`) forbids removal *during* ship, and the 30 min grace plus G-live covers that. |
| **Pane teardown** | `bin/cc-reaper:2672` (`worktree_cleanup`) | Already acts. Change it to call `wt_tombstone` and route a clean-but-unlanded tree into the event queue instead of leaving it. |
| **Teammate shutdown** | `hooks/teammate-auto-shutdown.sh:1559-1564` | Replace `remove --force` with `wt_tombstone` + `remove` (no force: the work is already checkpointed above, per its own comment at :1535) |
| **Crash classified** | `hooks/lead-crash-watchdog.sh:2201-2203` | When `class == CRASH`, resolve cwd from the transcript of `$sid` (same lookup as :153) and PIN it |
| **Branch merged on fetch** | `worktree-gc-infra-run.sh` fetch stage (`FETCH_BOUND`, :31); reso's wrapper likewise | After a successful fetch, enqueue every worktree whose branch moved from unlanded to landed (one `git cherry` per *changed* upstream, not per tree) |
| **PR merged (GitHub)** | `scripts/branch-prune-landed.sh` (remote-branch deletion journal `branch-prune-deleted.tsv`) | Each journal append enqueues the local worktree of that branch, if any |
| **Daily backstop** | existing 04:15 calendar plus 03:15 reso | Full sweep, multi-repo (P1-4b). It only catches what events missed. |
| **Wake actuator** | `launchd/com.claude.worktree-gc-infra.plist` (repo copy) plus the live plist: add `WatchPaths` as in `gl.reso.worktree-gc.plist` | **operator step** (launchctl bootout and bootstrap) |

When woken, the wrapper drains `wt-events.jsonl` and evaluates **only the named paths**, which is O(events). Today it
re-walks about 290 trees. The 60 s debounce plus the singleton lock (as in reso's wrapper,
`worktree-gc-run.sh:47-66`) bounds bursts.

### 5.5 Recreating automatically on resume

`SessionStart(source=resume)` is **too late**. Claude Code resolves the transcript from
`$CLAUDE_CONFIG_DIR/projects/<slug(cwd)>/` before any hook runs, and the cwd must exist before that
(`bin/cc-resume-resolve:5-14`, measured 2026-08-02 there; hooks doc: `resume` is a SessionStart *matcher*, which fires
inside an already-started session). So restoration belongs in the **launchers**:

1. `bin/cc-resume-resolve`: when `cwd_exists=0`, look up the newest tombstone for that path and emit
   `tomb_repo=`, `tomb_branch=`, `tomb_head=` and `tomb_preserved=`. Add these as new keys; that is backward compatible,
   since readers select by key.
2. `lib/cc-resume-shell.sh:138-155`: replace `mkdir -p` with `cc-wt-restore "$_cwd"`, a new `bin/` script that does the
   restore described in the DETACHED row. Fall back to today's `mkdir -p` only when no tombstone exists.
3. `bin/reso-resume-one:439-495`: `resolve_repo` consults the tombstone first, then its back-reference scan; the
   recreate step uses the sha when the branch is gone (0/85 branches survive, 70/85 heads resolve).
4. `scripts/boot-resume-launch.sh:247` already skips `--cwd` for a missing dir. Once reso-resume-one restores the tree,
   that branch is no longer taken.
5. Optional: `hooks/git-worktree-guard.sh` already parses Bash commands on PreToolUse. On a `cd` or `git -C` into a
   tombstoned path it could print the one-line `cc-wt-restore` hint. It must not auto-run it, because the hook fires on
   every Bash call and must stay a single stat.

### 5.6 Why none of this slows a session (the operator's constraint)

- **No session waits on any of it.**
  - Event emits are one `printf >>` and one `touch`, in hooks that already run.
  - The janitor runs under its own launchd job, as today.
- **Total machine work goes down.**
  - It evaluates named paths instead of re-walking about 290 trees, and fixing D6 removes full-tree `find` walks for
    trees that are KEEP anyway.
  - The 4 failing cc-gc runs a day (D3) disappear.
  - The reactive hand-cleanup sessions (§0) have nothing left to do.
- **Resume gets faster and more correct.** A real worktree replaces an empty directory. Today a session resumed after a
  reap has no files, and its user has to rebuild the tree by hand (`limit-recover`), which is strictly more work.
- **Restore cost lands only on a resume of a detached tree.** That costs seconds of `git worktree add` [E]. Dependency
  reinstall is lazy and comes from warm stores (pnpm and uv hardlink or clone from cache) [E]. DEHYDRATE, the only tier
  that adds install work to a later resume, is limited to trees idle ≥ 7 d and is P2. Disk is not binding (3.71 TiB free),
  so it is optional.

---

## 6. Rejected options

| Option | Why rejected |
|---|---|
| Lower `CC_WTGC_IDLE_MIN` or `ABANDON_HOURS`, or run the nightly sweep more often | Changes *when* but not *whether*. It re-walks an unchanged population (D6) and, with no tombstone and no restore, adds premature-deletion risk. memory-econ §6's sequencing note made the same point. |
| KEEP any tree that has ignored content (AC-2 as written) | `worktree-gc.sh:1290-1292` and `tests/worktree-gc.bats:776`: 64 of 86 trees carry ignored content, so the oracle would become inert. Superseded by **preserve in the tombstone**. |
| Keep "record, don't gate" as it is | Measured loss: `.env.local` 3, `sqlite.db` 3, `brag-output/` 5, `.claude/settings.local.json` 87 (§1.5) |
| Keep the checkout while any transcript of it is resumable (30 d) | Nothing would leave within 30 d. 36 of the LANDED-CLEAN trees younger than a day have such transcripts. This is the right *pre-restore* behaviour and the wrong end state. |
| Use the `WorktreeRemove` hook as the event | Fires only for worktrees a `WorktreeCreate` hook made (hooks doc). Issue reports say it never fires at exit on 2.1.201 and 2.1.214 (claudeissues #74708, #78978). Registering it suppresses the `/exit` keep-or-remove picker (#57378, #58432). Not proven on 2.1.293; SessionEnd is the reliable edge. |
| Restore in a `SessionStart(resume)` hook | Too late: the cwd must exist before the transcript loads (§5.5) |
| Glob `~/Development/.worktrees/*` to cover other repos | Forbidden by `worktree-gc.sh:13-15` (shared across repos). Coverage of other repos goes through each repo's own `git worktree list --porcelain` (P1-4b). |
| `--force` everywhere for uniformity | Throws away git's second gate (plan R-2). The opposite is recommended: drop `--force` from A4, A5 and A6. |
| Delete NOGIT husks automatically | They are not git-registered, so no oracle can name what they hold. Out of scope for an automatic actor; report only. |
| A shared worker pool or QoS for the janitor | Not applicable: the janitor is not on the load path (§0). The plist already applies `taskpolicy -c utility`. |

---

## 7. Verification recipes (all in a throwaway repo, per HAZARD RULE §0)

1. Make the scratch repo: `git init "$SCRATCH/lab"`, commit, add a fake `origin` as a second bare repo, and push main.
   Then add worktrees with these states:
   - landed-clean;
   - unlanded (1 commit);
   - dirty;
   - ignored-only, holding `node_modules/x` **and** `.env.local`;
   - detached;
   - locked.
2. Tombstone: run the patched janitor with `CC_WTGC_REPO=$SCRATCH/lab` and
   `CC_WTGC_DISPOSAL_LOG=$SCRATCH/ledger.jsonl`. Assert:
   - every removed path has a row with `repo == $SCRATCH/lab`;
   - `preserved_list` contains `.env.local` and not `node_modules`;
   - the locked tree and the dirty tree are KEEP.
3. Restore: delete the branch with `branch -d` after landing, then run `cc-wt-restore <path>`. Assert:
   - `git -C <path> rev-parse HEAD == tomb.head`;
   - `.env.local` is byte-identical;
   - `node_modules` is absent (lazy).

   RED-prove it by running the same recipe against today's `lib/cc-resume-shell.sh`. It must produce an empty dir.
4. D6 equivalence: run the pre-fix and post-fix janitor in `--dry-run` over the same 50-tree lab. Assert identical
   REMOVE and DISPOSE sets (`diff` of sorted path lists), and fewer `find` invocations (PATH shim counting `find` calls).
5. D3: `CC_GC_WORKTREE_BIN=<stub that records argv> bash scripts/cc-gc.sh --store worktrees` and the same with `--apply`.
   Assert the stub never receives `--apply` and that the non-apply run gets `--dry-run`, or that the store is ASSERT.
6. Events: feed `hooks/live-session-registry.sh` a SessionEnd JSON with `cwd` set to a lab worktree and a fixtured
   `$HOME`. Assert one line in `wt-events.jsonl` and an updated wake mtime. Then run the woken wrapper and assert it
   evaluated only that path.

---

## 8. Open questions

- Whether Spotlight indexes `.worktrees` today: **could not determine**. `mdfind -count -onlyin` returned 0 even for the
  positive control `~/Downloads`, so the instrument failed its control. memory-econ §5 measured it excluded on
  2026-08-10, and `.worktrees/.metadata_never_index` exists (dated 2026-08-19).
- Does `WorktreeRemove` fire on 2.1.293? Not tested (it would need a live `claude -w` exit).
- Resume rate of reaped sessions: no launcher logs a `cwd_exists=0` resume (the warning goes to the tty only,
  `lib/cc-resume-shell.sh:152`). Add an IDL line to measure it.
- Who removed the 68 b13 lanes (no tombstone, no code in either repo)? Probably a wave lead with raw git. The teardown
  of the next b13 round should call `wt_tombstone`.
- Restore wall time under load: `git worktree add` on a 9k-file tree is estimated, not measured. Measure it in the
  throwaway lab.
- 26 NOGIT husks and the 3 "locked-and-gone" records: who created each one cannot be recovered after the fact.

---

## 9. Commands used (all read-only, bounded)

- Ownership: for each `~/Development/.worktrees/*/`, `sed -n 's/^gitdir: //p' $d/.git`, then `sort | uniq -c`.
- Per repo: `gtimeout 20 git -C <repo> worktree list --porcelain` (counts of `worktree`, `prunable`, `locked`,
  `detached`) and `for-each-ref refs/heads | wc -l`.
- State census: `/tmp/g-wtcensus/census.sh`. Per worktree:
  - `git log -1 --format=%ct`;
  - `gtimeout 20 git status --porcelain` (dirty = non-`??` lines, untracked = `??`);
  - `gtimeout 20 git cherry <origin/HEAD> HEAD | grep -c '^+'`;
  - `[ -d node_modules|.venv|.next ]`;
  - membership in `~/.reso/live-sessions`.

  291 rows, all with `st_rc=0`.
- Live cwds: `ps -Ao pid=,comm=` filtered to basename `claude`/`claude.exe`, then `lsof -a -p <pid> -d cwd -Fn`
  (29 distinct cwds).
- Dev processes: `ps -Ao pid,pcpu,rss,comm` filtered to node, Python, esbuild and similar (92), then `lsof -a -p -d cwd`.
- Disk: `gtimeout 60 du -sk` on 15 sampled dirs and their cache subdirs; `git status --porcelain --ignored | grep -c '^!!'`.
- Transcripts:
  - `find <root>/projects -maxdepth 1 -name '*-Development--worktrees-*' -mtime -7`;
  - newest `*.jsonl`, `head -c 200000 | grep -m1 -o '"cwd":"…"'`, then `[ -d ]`;
  - existing-worktree slug lookup with `re.sub('[^A-Za-z0-9]','-',path)`.
- Ledgers:
  - `worktree-disposals.jsonl`, parsed with `python3 -I` (schema, actors, per-day counts, `destroyed_ignored` histogram);
  - `git cat-file -e <head>^{commit}` and `merge-base --is-ancestor <head> origin/main` for 85 tombstoned heads;
  - `show-ref --verify refs/heads/<branch>`.
- Schedules: `plutil -convert json` on `gl.reso.worktree-gc`, `com.claude.worktree-gc-infra`, `com.claude.cc-gc` and
  `com.chrisren.cc-reaper`; `launchctl list | grep`.
- Logs:
  - `~/.claude/autonomy/worktree-gc-infra.last`;
  - KEEP-reason histogram from the last nightly block of `~/.claude/logs/worktree-gc-infra.log`;
  - `grep -c 'worktrees      EXEC   red' ~/.claude/logs/cc-gc.out.log` returned 171, out of 171 total
    `worktrees      EXEC` lines;
  - `~/.reso/worktree-gc.last`.
- Reactive sessions: `gtimeout 90 rg -l -i -m1 'prune old worktrees|…'` over the 4 project roots, then excluding this
  workflow and subagents (10 left).
- Volume: `df -k /Users/chrisren`; `sysctl kern.num_vnodes kern.maxvnodes` (263168/263168).
