# I — Commit-side population: 499 branches, 256 worktree dirs, and their lifecycle machinery

Measured 2026-08-10 01:20–01:45 PDT, repo `/Users/chrisren/Development/claude-infrastructure`
at `origin/main` = `018381c6` (which advanced to `668ff763` mid-measurement — see §7.1).
Strictly read-only: no `git branch -d`, no `worktree remove`, no writes to any worktree.

**Headline.** The population is not 493 stranded branches. It is **279 branches holding 612 truly
unlanded commits**, of which **192 branches (69%) are `ship/backup-*` rollback refs that the janitor
is FORBIDDEN to prune** (`worktree-gc.sh:643`) and whose only collector is a fail-closed land-time
reap. Raw ahead-count inflates strandedness **5.9×**. The worktree side is the healthier half: 90 of
125 registered worktrees are >7d stale, but only **25 of those hold unlanded work (82 commits)** —
64 are pure residue. And the true ref-store bloat is neither: `refs/checkpoints/` holds **5,175 refs**
against `refs/heads`' 497, minted ~700/day by teammate shutdown, **with no collector anywhere.**

---

## 1. Branch census

| # | Quantity | Value | Command |
|---|---|---|---|
| 1.1 | Local branches | **499** | `git for-each-ref --format='%(refname:short)' refs/heads \| wc -l` |
| 1.2 | Branches with `ahead > 0` vs `origin/main` | **405** | `git for-each-ref --format='%(refname:short)\|%(ahead-behind:origin/main)' refs/heads` (git 2.54 atom) |
| 1.3 | …of those, **truly** unlanded (patch-id unique > 0) | **279** | `git cherry origin/main <br> \| grep -c '^+'` per branch (405 iterations, 22 s) |
| 1.4 | Fully landed by patch-id (`ahead>0`, uniq = 0) | **126** | same |
| 1.5 | Fully landed by reachability (`ahead = 0`) | **94** | 1.1 − 1.2 |
| 1.6 | **Total fully landed = safe to prune on content** | **220** (44%) | 1.4 + 1.5 |
| 1.7 | Sum of raw ahead-counts | **3,614** | `awk` over 1.2 |
| 1.8 | Sum of true unique commits | **612** | `awk` over 1.3 |
| 1.9 | **Ahead-count inflation factor** | **5.9×** | 1.7 / 1.8 |

### 1.1 True-stranded size distribution (the 279)

| unique commits | branches |
|---|---|
| 1 | 210 |
| 2–3 | 30 |
| 4–10 | 31 |
| 11–30 | 8 |
| 31+ | 0 |

**75% of stranded branches hold exactly one commit.** There is no long tail of big lost work; the
population is a mass of single-commit refs. The heaviest is 21 commits (`tm/growth`).

### 1.2 Age distribution — last-commit date, the 279 truly-stranded

| bucket | branches |
|---|---|
| <1d | 57 |
| 1–3d | 113 |
| 4–7d | 38 |
| 8–14d | 46 |
| 15d+ | 25 |

Command: `awk -F'|' -v now=$(date +%s) '$3>0{age=int((now-$4)/86400); …}' ` over the cherry census.
**61% of stranded work is under 4 days old** — i.e. mostly in-flight, not abandoned. The 71 items
older than 7 days are the real backlog.

### 1.3 Age distribution — ALL 499 branches (for contrast)

| bucket | branches |
|---|---|
| <1d | 104 |
| 1–3d | 165 |
| 4–7d | 64 |
| 8–14d | 129 |
| 15–30d | 37 |
| 30d+ | 0 |

Nothing on this repo is older than 30 days. The population is entirely churn from the last month.

### 1.4 Base staleness — how far behind `origin/main` each branch was cut

| behind origin/main | branches |
|---|---|
| 0 (on tip) | 1 |
| 1–50 | 48 |
| 51–200 | 75 |
| 201–500 | 162 |
| 501–1000 | 114 |
| 1001+ | 99 |

This is the task-board #68 "stale shared-checkout base" class, quantified: **375 of 499 branches
(75%) were cut from a base ≥200 commits behind trunk.** At the measured landing rate (§7.1: 69
pushes / 144 commits in 24 h) a base 500 behind is ~3.5 days old at cut time. A branch this far
behind cannot `--ff-only` merge and must rebase — which is precisely what mints the sha-divergence
in §1.6.

### 1.5 Top 20 by TRUE unique commits

| uniq | raw ahead | age | branch |
|---|---|---|---|
| 21 | 49 | 14d | `tm/growth` |
| 20 | 55 | 15d | `preland-backup-infra` |
| 20 | 55 | 15d | `fix/infra-perfection` |
| 19 | 19 | 21d | `feat/board-runnable-commands` |
| 17 | 17 | 2d | `deskless` |
| 14 | 38 | 15d | `tm/gates` |
| 14 | 14 | 21d | `feat/autonomy-100` |
| 11 | 29 | 15d | `tm/hygiene` |
| 9 | 456 | 0d | `wt-8532922cce46` |
| 9 | 455 | 8d | `fix/accounts-eval-bin-resolver` |
| 9 | 23 | 15d | `tm/hooks` |
| 9 | 9 | 2d | `superseded/wt-97f16b6709fa-duplicate` |
| 9 | 9 | 2d | `ship/backup-f51aae84` |
| 9 | 9 | 0d | `fix/close-integrity` |
| 8 | 455 | 8d | `wt-e06ba316a1aa` |
| 8 | 455 | 8d | `wt-dda10a298842` |
| 8 | 455 | 8d | `wt-26a9362990cb` |
| 8 | 8 | 15d | `wt-02ba4e52389a` |
| 8 | 8 | 9d | `terminal-arm-land` |
| 7 | 9 | 15d | `park/gc-session-index` |

Command: `awk -F'|' '$3>0{printf "%5d %5d %s\n",$3,$2,$1}' /tmp/land100-cherry.txt | sort -rn | head -20`

### 1.6 The 5 outliers at 455-ahead are a REBASE-LAND ARTIFACT, not lost work

`wt-8532922cce46`, `wt-e06ba316a1aa`, `wt-dda10a298842`, `wt-26a9362990cb`,
`fix/accounts-eval-bin-resolver` all read 455–456 ahead / 1,150 behind, merge-base `638fba76`
(2026-07-29). Measured: **447 of 456 are patch-equivalent to `origin/main`** (`git cherry` → 447 `-`,
9 `+`). Proof of the mechanism, one sample:

```
subject : fix(cc-wait): a delivered wake and an orphaned watcher both reported as a missed deadline
on main : ea14dc09  2026-07-31 13:01:33 -0700
on branch: f3c50f72  2026-07-31 13:01:33 -0700   ← identical date+subject, DIFFERENT sha
```

`origin/main` was never force-pushed (reflog shows only `update by push` fast-forwards). The
divergence is the **rebase-land flow minting new shas for every landed commit**: a ref that captured
pre-land shas stays permanently sha-divergent while being content-identical. This is the same
generator `scripts/ship-backup-reap.sh:6-13` documents for the backup namespace.

**Consequence for any exposure metric: `rev-list --count origin/main..<br>` is unusable at this
repo's landing rate.** It over-reports by 5.9× in aggregate and by 50× on these five.

### 1.7 Name taxonomy — where the population comes from

| prefix | all branches | truly stranded |
|---|---|---|
| `ship/backup-*` | **272 (54%)** | **192 (69%)** |
| `wt-<hex12>` | 83 | 18 |
| `<bare>` | 31 | ~16 |
| `fix/*` | 27 | 15 |
| `feat/*` | 27 | 9 |
| `tm/*` | 8 | 8 |
| `docs/*` | 8 | 4 |
| `backup/*` | 8 | 6 |
| `gu13c/*` | 6 | 4 |
| everything else (13 prefixes) | 29 | ~7 |

**The branch population is majority rollback refs.** See §3.3 for why nothing collects them.

---

## 2. Worktree census

| # | Quantity | Value | Command |
|---|---|---|---|
| 2.1 | Registered worktrees (this repo) | **125** | `git worktree list \| wc -l` |
| 2.2 | …under the shared root `~/Development/.worktrees` | **111** | `git worktree list --porcelain \| sed -n 's#^worktree ##p' \| grep -c '^…/.worktrees/'` |
| 2.3 | **Total dirs in the shared root (all repos)** | **256** | `find ~/Development/.worktrees -mindepth 1 -maxdepth 1 \| wc -l` |
| 2.4 | …attributable to claude-infrastructure | 110 | `.git` gitdir prefix per dir |
| 2.5 | …to reso-management-app | 71 | same |
| 2.6 | …to doc_classifier | 60 | same |
| 2.7 | …to reso-web-app / sevenrooms-bridge | 3 / 2 | same |
| 2.8 | **…with NO `.git` file at all — owned by nobody** | **9** | `[ -e "$d/.git" ] \|\| echo` |
| 2.9 | Registered path that does not exist on disk | 1 (`~/Development/_worktrees/wt-goal-oob`) | `comm -23` reg vs dirs |
| 2.10 | `.git/worktrees/` metadata dirs | 124 | `ls .git/worktrees \| wc -l` |
| 2.11 | Per-worktree metadata footprint | 18 MB | `du -sh .git/worktrees` |
| 2.12 | `.git` total | 258 MB | `du -sh .git` |
| 2.13 | Mean claude-infrastructure worktree size (n=6 sample) | **46.5 MB** → ~5 GiB for 111 | `du -sk` per dir |

Reso's `wt-pool-1` alone is **4.58 GB** (`du -sk` = 4,575,640 KB) — node_modules. Disk is dominated
by the foreign repos, and per `docs/plans/GROUND_UP_REBUILD_MAP.md:27` the volume is 7.28 TiB, so
**disk is not the binding resource** on the commit side.

### 2.1 Worktree HEAD staleness

| last-commit age | worktrees |
|---|---|
| <1d | 26 |
| 1–3d | 9 |
| 4–7d | 0 |
| 8–14d | **86** |
| 15–30d | 4 |
| **>7d total** | **90 of 125 (72%)** |

Command: per-worktree `git -C "$p" log -1 --format=%ct`, bucketed.

### 2.2 …but staleness ≠ stranded work — the sharpest number in this report

Of the **90 worktrees >7d stale**, cross-referenced against the patch-id census:

| | count |
|---|---|
| hold **truly unlanded** commits | **25** |
| fully landed — **pure residue** | **64** |
| total unlanded commits held across all 25 | **82** |

Command: for each stale worktree's branch, `git cherry origin/main "$br" | grep -c '^+'`.

**64 stale worktrees are removable on content today and are being kept by a rule that cannot see
it** — see §3.2. Oldest live examples: `permission-beacon` (21d, `feat/permission-pending-beacon`),
`wt-6cab0ab3cb2f` / `wt-63929c8d6072` / `wt-02ba4e52389a` (15d), `wt-tmux-isid` (14d, and it sits
*outside* the shared root at `~/Development/wt-tmux-isid`, so it is invisible to the population
count the ceiling binds).

### 2.3 The 9 unowned directories — invisible to every janitor

`bs-tableside-font` (2026-08-08) · `chore` (07-28) · `feat` (08-09) · `fix` (08-09) ·
`investigate` (08-09) · `wt-1a226422cb37` (08-08) · `wt-cc-010754-47727` (06-15) ·
`wt-cc-233935-83744` (06-18) · `wt-cc-234200-24894` (08-02).

`worktree-gc.sh` iterates `git worktree list --porcelain` (`:715 process_record`), so a directory
with no `.git` pointer is **structurally unreachable** by the janitor — it is not KEPT, it is
never considered. It counts toward `population()` (the ceiling's numerator, `worktree-gc-infra-run.sh:97-103`)
and toward nothing that can act. Four of them (`chore`, `feat`, `fix`, `investigate`) are the
generic-name collision class that `handoff-fire.sh:6100-6111` refuses to fire into.

---

## 3. Lifecycle mechanism, at HEAD (file:line)

### 3.1 The janitor and its cron

| element | value |
|---|---|
| Script | `scripts/worktree-gc.sh` — 865 lines, 49,297 B, last touched 2026-08-09 16:14 |
| Wrapper / cron entry | `scripts/worktree-gc-infra-run.sh` — 386 lines, 24,221 B, 2026-08-10 00:51 |
| Registration | `launchd/com.claude.worktree-gc-infra.plist` → `~/Library/LaunchAgents/…` |
| Cadence | `StartCalendarInterval` **04:15 daily**, `RunAtLoad false`, `ProcessType Background`, `Nice 10`, `LowPriorityIO` |
| Load state | **loaded** (`launchctl list` → `com.claude.worktree-gc-infra`, last exit `0`) |
| Sibling | `gl.reso.worktree-gc` at 03:15 (also loaded) — the 1 h offset is deliberate (plist comment: shared `CC_WTGC_LOCK` default) |
| Flags passed | `--prune-branches` only (`worktree-gc-infra-run.sh:334,336`). **`--dispose-abandoned` is NOT passed.** |
| Kill switch | `~/.claude/autonomy/worktree-gc-infra.disabled` (absent) — wrapper-level only; `worktree-gc.sh` itself still has none (GROUND_UP_REBUILD_MAP row 11 AC-7, still open) |
| Live-layer status | `~/.claude/scripts/worktree-gc*.sh` are **symlinks into the checkout**; both content-hashes equal `origin/main`'s. The HEAD code IS the running code. |
| Last recorded sweep | `2026-08-09 22:15:24 verdict=ok observe=0 removed=319 disposed=0 kept=108 branches=389 refusals=46 rc=0` (`~/.claude/autonomy/worktree-gc-infra.last`) |
| Live `--assert` (run by me) | `population=256 (ours=111 foreign=145) ceiling=150 last_verdict_age_h=2` → **OK bounded and fresh**, exit 0 |

Retry/lock discipline: bounded backoff `LOCK_RETRIES=3 × LOCK_BACKOFF=120s`, retried **only** on the
`another pass holds` string (`:340`) — every other rc falls straight through, so the loop cannot
become a storm.

### 3.2 The KEEP ladder — why 64 landed-content worktrees survive

`scripts/worktree-gc.sh:723-731`, first match wins:

```
:724  locked worktree
:725  .teammate-busy marker present
:726  dirty tree (removal would need --force ⇒ data loss)   ← the one that binds
:727  a git operation is parked here (rebase/merge/cherry-pick/bisect)
:728  LIVE — a registered session / running claude is cwd'd here
:729  LIVE — live-session-registry PID still alive
:730  lsof shows an open fd under the path
```

`:726` keeps **any** tree with non-empty `git status --porcelain`. `worktree-gc.sh` contains
exactly **one** occurrence of `rev-list --count|merge-base|is-ancestor` across 865 lines, and it is
inside `landed()` (`:374`) — used for BRANCH pruning, not for the worktree KEEP decision. So a
worktree that is dirty **because it was abandoned mid-fire** is protected by the safeguard meant to
protect work in progress. `GROUND_UP_REBUILD_MAP.md:27` records this firing on a live session's own
worktree, twice (`~/.claude/logs/worktree-gc-infra.log:1373`, `:1611`).

This is the mechanism behind §2.2's 64: they are content-landed, they are dirty, and the KEEP rule
never asks the second question.

The janitor does surface them — last sweep's tail:
- 1 abandoned-unlanded worktree reapable, *"pass `--dispose-abandoned` to reap them"* — **and the cron does not pass it**;
- 8 unlanded worktrees past the 72 h horizon with **no ownership oracle at all**;
- 5 unlanded past 72 h whose owner is provably NOT terminal (parked work, correctly kept).

Ownership oracles that CAN terminate a worktree: `owner_terminal()` `:545` — backlog item folds to
`done` (`item_terminal` `:433`), owning team concluded (`team_terminal` `:448`), or an explicit
path-exact sha-current warrant (`warrant_terminal` `:508`, file `~/.claude/autonomy/worktree-warrants.tsv`,
731 B, last written 2026-07-31).

### 3.3 `ship/backup-*` — 272 refs, minted per land, structurally uncollectable by the janitor

- **Producer:** `scripts/ship-land.sh:2344` — `SHIP_LAND_BACKUP_REF="ship/backup-$(git rev-parse --short HEAD)"`, written before every land as the rollback point.
- **Only collector:** `scripts/ship-backup-reap.sh`, invoked at `ship-land.sh:2224` with `|| true`, gated on `SHIP_BACKUP_REAP != off`. Predicate is **content**, not patch-id: for every path the ref's own commits touched, that path must be byte-identical on `LANDED_HEAD`. Any uncertainty ⇒ KEEP (`:38` — *"45 of the 739 hold at least one path absent from trunk"*).
- **No retrospective sweep, deliberately** (`ship-backup-reap.sh:161`): against a drifted `origin/main` the same predicate misclassifies 437 of 739 as "content differs", because siblings touch the paths. Verified live — I ran the predicate on `ship/backup-019b8af7`: 5 paths, 2 (`scripts/compressor-sentinel.sh`, `scripts/worktree-gc-infra-run.sh`) now differ from `origin/main` purely from sibling churn. A retrospective sweep would leak it forever.
- **The janitor cannot help:** `worktree-gc.sh:640-647 protected_branch()` returns 0 for `ship/backup-*|backup/*|*-prerebase-backup`. `--prune-branches` runs every night and can never touch them.

**Measured leak rate.** 69 `update by push` entries on `origin/main` in the last 24 h (144 commits);
73 `ship/backup-*` refs whose tip is <24 h old. Not a clean ratio (a push can carry several commits,
and tip-date is the work's date, not the ref's creation date), but the order is unambiguous: **the
land path mints backup refs at roughly the rate it lands, and the reap discharges only about half.**

### 3.4 `refs/checkpoints/` (5,175) and `refs/wip/` (600) — the real ref-store term, with NO collector

> **ERRATUM 2026-08-10 — this section's headline is WRONG; see the ERRATUM block in
> `../land-architecture-100p-2026-08-10.md` §2.I.** A bounded collector has existed since
> 2026-08-06 (`hooks/teammate-checkpoint.sh:153-248`: floor 3 / per-member cap 50 / age 14d,
> batched via `update-ref --stdin`) and demonstrably runs. **The "Collector: none found" bullet
> below is refuted by the grep it itself cites** — its `CHECKPOINT_RETAIN` pattern, re-run verbatim
> over `hooks/`, hits `teammate-checkpoint.sh:45`; the two `update-ref -d` patterns miss only
> because deletion goes through a batched `--stdin` transaction. The store is bounded (cap binds:
> 12 members at exactly 50, none above); the true residual is 65 dead members' ~180
> floor-immortal refs, ≈3.2%. §3.5's loose-object pressure is likewise moot at HEAD (513, not
> 1,832). Everything else in this lane stands, including that these refs are load-bearing.

`.git/packed-refs` is 541,094 B / 6,281 lines. Namespace breakdown
(`grep -o 'refs/[a-z]*/' .git/packed-refs | sort | uniq -c`):

| namespace | refs |
|---|---|
| `refs/checkpoints/` | **5,175** |
| `refs/wip/` | 600 |
| `refs/heads/` | 497 |
| `refs/tags/` `refs/remotes/` `refs/backup/` `refs/proposals/` | 2 / 2 / 2 / 1 |

- **Producer:** `hooks/teammate-auto-shutdown.sh:7-8` — every teammate shutdown preserves tracked + untracked work to `refs/checkpoints/<member>/<ts>` and `refs/wip/<member>/LAST` via plumbing.
- **Shape:** `refs/checkpoints/<member-hex12>/<YYYYMMDDTHHMMSSZ>` — **timestamped, so monotone-add per member.** `refs/wip/<member>/LAST` is bounded at one per member, hence 600 vs 5,175.
- **Daily mint rate:** 953 (08-07), 703 (08-08), 668 (08-09), 193 so far on 08-10.
- **Collector: none found.** Grep for `update-ref -d.*checkpoints`, `prune.*checkpoints`, `CHECKPOINT_RETAIN`, `reap.*checkpoint` across `scripts/ hooks/ bin/` returns only (a) `scripts/reaper-e2e.sh:129`, a test's own cleanup of its fixture ref, and (b) `scripts/reap-guard.sh:109` / `:198`, which **read** the refs as an existence oracle. `worktree-gc.sh --prune-branches` operates on `refs/heads` only. Nothing deletes a checkpoint ref.

**Consumers of these refs read them as a work-preservation oracle** (`reap-guard.sh:109`), so they
are load-bearing and must not be bulk-deleted — the gap is that no *retention policy* exists at all.
At ~700/day this namespace passes 10,000 refs inside two weeks.

### 3.5 `git gc` pressure

```
gc.auto            UNSET  → git default 6700 loose objects
count-objects -v   count: 1832   in-pack: 55051   packs: 4   size-pack: 123380 (120 MB)
                   garbage: 0    size-garbage: 0
```

1,832 loose = **27% of the auto-gc threshold**. `docs/research/scaling-bottlenecks-2026-08-09/08-platform-terms.md:47`
measured 692 at 10 sessions on 2026-08-09; **it has 2.6×'d in one day.** Crossing 6700 makes every
session's next write attempt a gc over a 120 MB pack. The `garbage: 0` line also retires that doc's
"anomaly found in passing" (`.git/worktrees/wt-crash-rootcause-2026-08-09/refs` malformed) —
**CHANGED, now clean.**

---

## 4. What provisioning a worktree costs today (steps enumerated, not timed)

Three provisioning paths exist. Only path A is `handoff-fire.sh`'s.

**A. `handoff-fire.sh --worktree` cold path** (`scripts/handoff-fire.sh:6071-6176`)

1. `:6074-6078` resolve `POOL="$REPO/scripts/worktree-pool.sh"`; eligible only if executable **and** `BASE == origin/main` **and** `$REPO_GITDIR` non-empty.
2. `:6088-6098` **pool ownership gate** — walk every `$WTROOT/wt-pool-*`, compare `hf_git_owner` to `$REPO_GITDIR`; any foreign slot ⇒ `POOL_ELIGIBLE=0`, refuse the pool, warn, fall to cold.
3. `:6099-6112` if `$WT` already exists: ownership check, refuse loudly on foreign, else `WT_SETUP=existing`.
4. `:6137` **`git -C "$REPO" fetch origin -q`** — a network round trip on every cold fire; failure only warns and bases off the last-fetched ref (this is the stale-base entry point).
5. `:6138` `git worktree add "$WT" -b "$WORKTREE" "$BASE"` — writes `.git/worktrees/<name>/` (~145 KB observed mean) and a new `refs/heads` entry.
6. `:6141` arm `fire_cleanup` (cold only — an `existing` tree is never removed by this fire).
7. `:6142` `cp "$REPO/.env.local" "$WT/.env.local" && chmod 600` if present.
8. `:6150` build `WT_INSTALL` — a **lockfile-detected** dep install chain (pnpm/bun/npm/yarn/uv/poetry/pipenv/go/cargo, else skip). claude-infrastructure has no lockfile ⇒ this is a no-op echo here; it is the expensive step in reso.
9. `:6169-6172` `mktemp` → `mv` to add `.sh` → write + `chmod +x` a deps script. **Written to a file, never inline**: zsh `setopt CORRECT` (operator's `~/.zshrc:53`) hangs on unknown command words at *read* time (2026-07-29 incident); BSD `mktemp` substitutes only a trailing `XXXXXX`, so the mint-then-suffix order is load-bearing.
10. `:6173` final `CMD = cd "$WT" && bash "$WT_DEPS" ; <launcher> "$(cat $QP)"` — `;` not `&&`, so a failed install still launches.
11. `:6193-6202` `LAUNCH_DIR="$WT"` → pre-trust the dir so the session does not stall at the trust dialog.

**Steady-state cost per cold fire: 1 network fetch · 1 `worktree add` (new ref + new `.git/worktrees` entry) · 1 secret copy · 1 tempfile · ~46 MB of checkout.** The fetch is the only one that scales with the *fleet*; the rest are per-fire constants.

**B. `scripts/new-worktree.sh`** — the contract `~/.zshrc:_cc_route_check()` depends on. Steps:
`:67` `git check-ref-format refs/heads/<name>` · `:79` `mkdir -p "$(dirname "$dest")"` · `:87` verify `$base`, fall back to `main` · `:90` `git worktree add -b "$branch" "$dest" "$base"` · `:97-98` copy a fixed set of gitignored files. **This is the population driver at launch time**: every `claude` launch in this repo that routes through the gate mints a worktree. Its header (`:4-11`) states the gate previously fell through to `return 0`, launching sessions in the shared checkout — the condition `.claude/CLAUDE.md` forbids and §6.2 shows is live again for 8 of 15 sessions.

**C. `hooks/worktree-setup.sh`** — the `WorktreeCreate` provisioner for `claude -w`; its cold rung calls `new-worktree.sh "$BRANCH" "$WT"` (two-arg form, added 2026-08-05 for slashed names).

**Naming evidence for who mints what:** 110 `wt-<hex12>` dirs (handoff-fire) · 48 `wt-cc-*` dirs (launcher route-check) · 0 bare `cc-*` · 10 `wt-pool-*` (reso).

---

## 5. Warm pool — status: **BUILT, but not for this repo. Prose-only here.**

| element | status |
|---|---|
| `reso-management-app/scripts/worktree-pool.sh` | **EXISTS**, 14,071 B, executable, dated 2026-07-03 |
| `claude-infrastructure/scripts/worktree-pool.sh` | **ABSENT** |
| Pool slot dirs `~/Development/.worktrees/wt-pool-{1..10}` | **10 exist** — all with gitdir under `reso-management-app` |
| `pool/slot-*` branches in claude-infrastructure | **0** |
| `docs/ground-up-payloads/row11-worktree-warmpool.md` | 230 lines — a **dispatch payload (a brief to a session)**, not a design doc; branch-only artifact context |
| `gu-worktree-warmpool-b` (tip `217ca100`) | Phase 1 doc **rescued to trunk** via `cherry-pick -x` → `docs/plans/WORKTREE_MANAGEMENT_V2.md` (confirmed on `origin/main` by `git ls-tree`) |
| `WORKTREE_MANAGEMENT_V2.md:281-283` **R-d** | *"Warm-pool semantics: `wt-pool-3`, `wt-pool-7` exist on disk (3.71/3.88 GiB) but the pool build logic lives in `scripts/handoff-fire.sh`"* — **open remainder** |

**What it changes about provisioning cost, and why claude-infrastructure gets none of it.**
A claimed slot is *already provisioned* — `WT_SETUP="pool"` at `:6123` carries the comment *"fully
provisioned — no in-pane install needed"*, and the `CMD` at `:6175` drops the deps script entirely.
It converts steps 4–10 above into one `worktree-pool.sh claim`. But `POOL="$REPO/scripts/worktree-pool.sh"`
(`:6074`) does not exist for this repo ⇒ `POOL_ELIGIBLE=0` at the first test — and even if it did,
the ownership gate at `:6088-6098` would refuse, because **all ten slots are reso's**. I verified
`wt-pool-1/2/3` gitdirs directly. **Every claude-infrastructure `--worktree` fire takes the cold
path, unconditionally.** The gate exists because on 2026-07-24 `claim` handed a claude-infrastructure
fire a reso path without complaint (`:6082-6084`).

Slot lifecycle note (`:5952-5984`): there is **no `release` verb**. A slot is returned only by
`fire_cleanup` re-`switch -C pool/slot-N` when a fire never lands a pane; a fire that *does* land
consumes the slot until the pool replenishes. Two of ten slots are currently on session branches
(`wt-pool-1` → `cc-225947-27025`, `wt-pool-3` → `cc-181314-53823`), one on `pool/slot-2`.

---

## 6. The two verify-at-HEAD verdicts

### 6.1 ea58210f — the janitor's population-tripling blindness

**Verdict: PARTIALLY REMEDIED (`ea58210f`, landed and live). The three in-file failure modes are
closed. The fourth — the janitor not running at all — is now RECORDED but still reaches no
consumer.**

Landed: `git merge-base --is-ancestor ea58210f origin/main` → yes. Live: `~/.claude/scripts/worktree-gc-infra-run.sh`
is a symlink into the checkout and its sha256 equals `origin/main`'s. Diff: +429 / −6 across the
script and `tests/worktree-gc-infra.bats` (214 new test lines).

What is genuinely closed:

| 2026-08-0N failure | remedy at HEAD | verdict |
|---|---|---|
| `verdict=ok removed=65 kept=126` reported what the janitor SAID | `verdict()` `:175-198` now stamps `pop`/`pop_owned`/`pop_foreign`/`ceiling` on **every** row incl. failure rows; the sweep arm adds `pop_before`/`pop_after`/`pop_delta` (`:374-376`) | **REMEDIED** |
| swept, exited 0, count still over — indistinguishable from healthy | `verdict over-ceiling 3` (`:378-379`), judged on `pop_owned` not `pop` | **REMEDIED** |
| 2026-08-08 died mid-sweep, silently (lock+pid, no verdict) | `:251-257` reads the stale lock's pid **before** the self-heal clears it, emitting `prev=died-mid-sweep prev_pid=… prev_started=…` | **REMEDIED** |
| 2026-08-09 the box panicked in the window — no row at all | `:242-245` emits `missed_windows_h=<n>` on the **next** row | **RECORDED ONLY** |

The residual, stated precisely. The 2026-08-09 window is observable *only from the last row's age*,
and the only thing that reads age is `--assert` (`:208-224`, exit 3 on breach or `last_verdict_age_h > STALE_H=48`).
**`--assert` has zero callers.** Repo-wide grep for `worktree-gc-infra-run.sh … --assert` outside the
file itself: 0 hits. The two files that mention the script at all are `scripts/unattended-path-lint.sh:244`
(a PATH-lint allowlist entry) and `scripts/devserver-census.sh:145` (a prose citation). Neither
`scripts/wrap-ledger.sh` nor `hooks/operator-readout.sh` references worktrees at all. `verdict()`
writes to `$LAST` and `$LOG` and exits — the wrapper contains **zero** `cc-notify`/`cc-backlog` calls
(`grep -c` = 0), unlike `worktree-gc.sh` itself which does use `CC_NOTIFY_BIN` (`:335`), but only to
*read* the live-session list as a liveness oracle.

So the shape of the original defect survives one level up: the commit's own rationale (*"all inside
this already-scheduled file — a new launchd job is a C10 step and would rot in the pending-activation
queue"*) is a deliberate, documented scope choice, and within that scope it is correct and complete.
But a rung that only fires when the script runs cannot report the script not running, and the one
rung that can (`--assert`) is a probe with no consumer — the *conclusion-must-reach-the-enforcing-store*
shape. **Could the tripling recur? Yes — if the box misses ≥2 windows, the population grows unbounded
and nothing outside the script will say so until a human runs `--assert`.**

Two secondary facts that matter to the lead's synthesis:
- The apparent "no row since the fix" is **schedule, not failure**: `RunAtLoad false`, the box booted 2026-08-09 04:18 (after that day's 04:15), and it is now 01:27 on 08-10 — the next fire is 04:15 today. `launchctl print` reads `runs = 0` / `last exit code = (never exited)` for exactly this reason. There has been **zero scheduled opportunity** since boot; the 2026-08-09 22:15 sweep was hand-run.
- The ceiling is currently **not** breached and the polarity is right: `pop_owned=111 ≤ ceiling=150`, while `pop=256` (145 foreign) is reported and deliberately not alarmed on. Population grew **246 → 256 in ~3 h** after the sweep (~4/h). At that rate `pop_owned` reaches 150 in roughly ten hours of fleet activity — i.e. the ceiling is live-relevant within one day, not hypothetical.

### 6.2 Ref-lock contention / fetch storms tied to population size

**Verdict: HOLDS — and it is worse on the live term than when first measured.**

The claim under test is `docs/research/scaling-bottlenecks-2026-08-09/08-platform-terms.md:53`:
*"The `cannot lock ref 'HEAD'` class is mis-attributed to worktree count. In a LINKED worktree,
`HEAD` lives at `.git/worktrees/<name>/HEAD` — per-worktree, not shared. That failure requires 2+
sessions in the SAME checkout."*

Re-verified at HEAD:

| check | result |
|---|---|
| `HEAD` is per-worktree | **confirmed structurally** — `.git/worktrees/acct-routing-urgency/HEAD` → `ref: refs/heads/feat/acct-routing-urgency`; `.git/worktrees/banner-feedback/HEAD` → `ref: refs/heads/banner/feedback-round` |
| `*.lock` remnants anywhere under `.git` | **0** (`find .git -name '*.lock' \| wc -l`) |
| `cannot lock ref` / `index.lock` in `~/.claude/logs/` | **0 genuine occurrences.** All grep hits are the doc sentence above quoted into `bash-commands.log` / `bash-execution.log`, plus my own probe commands echoing themselves |
| `cannot lock ref` / `lock contention` in last 400 trunk commit subjects | **0** |
| `origin/main` reflog | 433 entries, **all `update by push` fast-forwards** — no forced update, no failed-lock trace |

So: **population size is not producing ref-lock contention, and there is no fetch-storm evidence in
any log.** The mis-attribution holds.

**But the doctrine term the doc named as the real cause has degraded 4×.** Measured live, anchored on
argv position (`ps -axo pid,command`, basename of `$2` ∈ {`claude`,`claude-latest`,`cc`}), then each
pid's cwd via `lsof -a -p <pid> -d cwd -Fn`:

| | value |
|---|---|
| Real CC sessions | **15** |
| …cwd'd in the **shared checkout** `/Users/chrisren/Development/claude-infrastructure` | **8 (53%)** |
| …cwd'd in a worktree | 6 |
| …elsewhere | 1 |

The doc measured *2 of 10* on 2026-08-09. It is now *8 of 15*. Every one of those 8 is in direct
violation of `.claude/CLAUDE.md` § "Never commit or land in the shared checkout", and they are the
only population that can produce `cannot lock ref 'HEAD'` — as well as the `git commit` index-sweep
and the `deploy-live.sh --ff-only` refusal that `new-worktree.sh:9-11` documents.

**Positive control on the denominator** (per the known `pgrep -f` inflation class): the naive
`ps -axo command | grep -c '[c]laude'` reads **233**. Anchoring on argv position gives **15** — a
**15.5× inflation**. Any figure in this report about "sessions" uses the anchored count.

---

## 7. Adversarial pass — what I checked because a hostile reviewer would ask

**7.1 "Your `origin/main` moved under you."** It did: `018381c6` at 01:20 → `668ff763` by 01:29,
five pushes inside nine minutes. Every ahead/behind and `git cherry` number in §1 was computed
against a single `for-each-ref` snapshot taken at 01:21, so the census is internally consistent;
absolute counts drift upward by roughly **69 pushes / 144 commits per 24 h** (`git reflog show origin/main --since='24 hours ago' | grep -c 'update by push'`;
`git log origin/main --since='24 hours ago' --oneline | wc -l`). 55 commits landed in the three
hours before measurement. Treat every branch count here as ±1 day.

**7.2 "You assumed `ahead > 0` means stranded."** I did not — that is §1.3, and it is the single
largest correction in this report (5.9×). But the correction has its own limit, stated in §8.

**7.3 "You measured branches and ignored the ref store."** That turned out to be the finding: §3.4.
`refs/heads` is 8% of `packed-refs`. A remediation aimed only at branches would leave 92% of the ref
store untouched.

**7.4 "Is the janitor's ceiling even the right quantity?"** It binds `pop_owned` (111) against a
`pop` of 256, and 145 of those 256 belong to reso/doc_classifier with their own reaper. The commit
comment `:70-81` says this distinction was *found by the first sweep, not by design* — an earlier
ceiling on the total reported BREACH on a box whose janitor had just worked perfectly. The polarity
is now right. The gap it leaves is §2.3's 9 unowned dirs: they inflate `pop`, no janitor can reach
them, and the ceiling that *would* act ignores them by construction.

**7.5 "You said the pool doesn't apply — did you check the DRY path?"** Yes: `:6113-6114`,
`DRY=1` sets `WT_SETUP="pool"` on eligibility alone, without running the ownership walk's `claim`.
So a `--dry-run` fire from claude-infrastructure would *report* `pool` where a real fire takes
`cold` — only if `worktree-pool.sh` existed for this repo, which it does not. Not currently live;
noted because it is a latent report/reality divergence in the same file.

**7.6 "Is `--dispose-abandoned` a bug or a gate?"** A deliberate gate. The cron passes only
`--prune-branches` (`:334,336`); the janitor's own tail line tells a human to pass the other flag.
Combined with §3.2 this means: **nothing on this box automatically removes an abandoned worktree.**
Removal of the 64 landed-content stale worktrees requires either an operator flag or an ownership
oracle (backlog `done` / team teardown / an explicit warrant).

---

## 8. Limits — what this report does NOT establish

- **Patch-id is not content.** §1.3's 279 is a patch-id measure. `ship-backup-reap.sh:14-19` argues the *correct* predicate is per-path content equality against the head that was content-verified onto trunk, and `:29-31` measures that the same predicate against a drifted `origin/main` misclassifies **437 of 739**. So §1.3 both over- and under-counts: it over-counts refs whose content landed with a revised diff, and it can under-count a branch whose commits are patch-equivalent but whose *tree* differs. **Content-verifying all 499 branches is out of scope and was not done.** Only two branches were content-probed (`wt-8532922cce46`, `ship/backup-019b8af7`).
- **`git cherry` was run against a moving trunk.** Between the first branch (01:22) and the last (01:22:22) the trunk was stable; between the census and the stale-worktree cross-check (§2.2, 01:41) it advanced. The 25/64 split is therefore ±2.
- **Worktree "age" is last-commit date, not last-touch.** A worktree actively read-from but not committed-to reads stale. The janitor's own liveness oracles (`lsof`, the session registry, `cc-notify --list`) are the correct instrument for "in use", and I did not run them per-path.
- **Disk is a 6-worktree sample** (mean 46.5 MB → ~5 GiB projected for 111). A full `du` over the shared root timed out at 120 s. `GROUND_UP_REBUILD_MAP.md:27` has an independent figure — 116.5 GiB across 198 dirs — and explicitly falsifies disk as the binding constraint (7.28 TiB volume).
- **Latency coupling to the land lock is out of scope by brief.** §7.1's 69 pushes/24 h and §3.3's mint rate are supplied as inputs to that computation; I did not do it.
- **`launchctl print runs = 0`** means "since this load", not "ever". Historical runs are in `~/.claude/logs/worktree-gc-infra.log` (100,767 B, self-trimmed to 2,000 lines at `verdict()` `:194-196`) — so the log itself is **not** a durable long-horizon record, and any question about sweep history before ~2,000 rows ago is unanswerable from it.

---

## Appendix — reproduction artifacts

| file | contents |
|---|---|
| `/tmp/land100-ab.txt` | 499 rows: `branch\|ahead behind\|committerdate-unix\|date\|sha` |
| `/tmp/land100-cherry.txt` | 405 rows: `branch\|raw-ahead\|patch-id-unique\|committerdate-unix` |
| `/tmp/land100-wtage.txt` | 125 rows: `last-commit-unix\|branch\|worktree-path` |
| `/tmp/land100-wtstranded.txt` | 89 rows: `branch\|unique-commits` for worktrees >7d stale |
| `/tmp/land100-cc.txt` | 15 rows: argv-anchored live CC session pids |
