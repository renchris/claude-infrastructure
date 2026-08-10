# Axis E — Git maintenance & repo health across the fleet
Measured 2026-08-10 00:20–01:05 local, M1 Max 64 GB / 10 core, uptime 20 h (boot Sun Aug 9 04:18).
**All measurements taken at `load average 143.23 87.37 57.24`** — absolute wall-times are inflated;
every timing below is `min of 5–7 runs` (least-noise estimator) and every comparison is
within-subject (same repo, same op, different binary) so the *ratios* survive the load.
Read-only throughout: no fleet config changed, no gc/maintenance/prune run on any fleet repo.
Two controlled experiments ran in throwaway `/tmp` repos with `GIT_CONFIG_GLOBAL` redirected to a
temp file; `~/.gitconfig` verified untouched afterwards.

---

## Verdict in one line

**The one repo enrolled in `git maintenance` is the only unhealthy repo in the fleet, and it is
unhealthy *because* it is enrolled** — enrollment switched off git's own self-healing
(`maintenance.auto=false`), handed the job to two launchd timers, and a crashed run on **Aug 5
00:16** left a zero-byte lock that has silently no-op'd every maintenance run for 5.5 days.
Cost: **1,352 MB `.git`, 11,660 loose objects, 22 packs** in `reso-management-app`, against
**254 MB / 87 / 4** in the busier, *unenrolled* `claude-infrastructure`.

**And git is not the memory bottleneck.** Measured max-RSS per git operation is **4.5–9.6 MB**;
at 15 concurrent sessions the entire steady-state git population is ≲ 150 MB of transient RSS.
The git-shaped memory risks that *are* real are two, and both are latent rather than current:
an unbounded detached `gc` (10 threads, no `pack.windowMemory` cap) and `core.fsmonitor`, which is
**per-worktree** and would spawn up to 253 daemons × 5.3 MB in `claude-infrastructure` alone.

---

## 1. Per-repo health table

`.git` sizes in MB (`du -sm`), object counts from `git count-objects -v`, all read 2026-08-10 00:2x.

| Repo | `.git` | loose obj | loose KB | packs | pack KB | prune-pack/garbage | wt meta | reflog files / KB | packed-refs B | refs | commit-graph | midx |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| claude-infrastructure | 254 | 87 | 464 | 4 | 120,056 | 0 / 0 | 119 | 485 / 1,444 | 534,126 | 6,212 | split-chain **fresh 00:33** | **fresh 00:25** |
| reso-management-app | **1,352** | **11,660** | **142,180** | **22** | 1,163,005 | **97 / 1** | 74 | 662 / 3,140 | 230,976 | 2,939 | split-chain **STALE Aug 4 23:48** | **STALE Aug 4 00:24** |
| doc_classifier | 72 | 1,260 | 8,136 | 6 | 41,888 | 0 / 0 | 62 | 78 / 340 | 51,864 | 646 | split-chain | yes |
| finance-ai-web-app | 34 | **5,513** | 26,488 | **0** | 0 | 0 / 0 | 9 | 14 / 244 | 0 | — | **none** | **none** |
| reso-web-app | 56 | 602 | 3,348 | 2 | 52,551 | 0 / 0 | 3 | 14 / 48 | 1,234 | — | split-chain | yes |
| sevenrooms-bridge | 1 | 100 | 432 | 0 | 0 | 0 / 0 | 2 | 5 / 20 | 0 | — | none | none |
| voiceink | 14 | 0 | 0 | 3 | 12,382 | 0 / 0 | 2 | 135 / 192 | 18,130 | — | split-chain | yes |
| whisper.cpp | 43 | 0 | 0 | 2 | 41,303 | 0 / 0 | 1 | 9 / 36 | 9,170 | — | split-chain | yes |

| Repo | maintenance enrolled | `maintenance.auto` | `maintenance.strategy` | `gc.auto` | `core.hooksPath` | live hooks | fsmonitor | untrackedCache | splitIndex |
|---|---|---|---|---|---|---|---|---|---|
| claude-infrastructure | **no** | unset (=true) | unset | 6700 (default) | unset → `.git/hooks` | commit-msg · pre-commit · pre-merge-commit · pre-push | unset | unset | unset |
| reso-management-app | **YES** (only) | **false** | **incremental** | **0** | `scripts/hooks` | commit-msg · post-checkout · post-commit · post-merge · pre-commit · pre-merge-commit · pre-push | unset | unset | unset |
| doc_classifier | no | unset | unset | 6700 | `.githooks` | pre-commit · pre-merge-commit · pre-push | unset | unset | unset |
| finance-ai-web-app | no | unset | unset | 6700 | `.husky/_` | pre-commit · pre-merge-commit · pre-push | unset | unset | unset |
| reso-web-app | no | unset | unset | 6700 | unset | pre-commit · pre-merge-commit · pre-push | unset | unset | unset |
| sevenrooms-bridge | no | unset | unset | 6700 | unset | **none** (14 `.sample` only) | unset | unset | unset |
| voiceink | no | unset | unset | 6700 | unset | pre-commit · pre-merge-commit · pre-push | unset | unset | unset |
| whisper.cpp | no | unset | unset | 6700 | unset | **none** (14 `.sample` only) | unset | unset | unset |

`~/.gitconfig` `[maintenance] repo` holds exactly one entry:
`/Users/chrisren/Development/reso-management-app`
(`git config --show-origin --get-all maintenance.repo` → `file:/Users/chrisren/.gitconfig`).
No XDG `~/.config/git/config`, no `GIT_CONFIG_GLOBAL`, system config is `credential.helper=osxkeychain` only.

`extensions.worktreeConfig` is unset everywhere — so **every setting in `.git/config` applies to all
linked worktrees of that repo**. This is the single most important constraint on every
recommendation below.

---

## 2. Findings

### F1 — A stale `maintenance.lock` has silently disabled all maintenance in the enrolled repo for 5.5 days

**Finding:** `reso-management-app/.git/objects/maintenance.lock` (git's maintenance lock lives at
`<objectdir>/maintenance.lock`, not `.git/maintenance.lock`) is a **0-byte file dated 2026-08-05
00:16** with **no holding process** (`lsof` → empty). Git skips a maintenance run it cannot lock, so
~130 scheduled runs since have done nothing, and launchd reports `last exit code = 0` for all of them.

**Evidence:**
- `stat` → `2026-08-05 00:16 (size 0)`; `lsof …/maintenance.lock` → no output.
- **00:16 is the `org.git-scm.git.daily` plist's exact minute** (`<key>Hour</key>0 <key>Minute</key>16`), and Aug 5 is day-of-month 5, inside that plist's `Day 1..6` range. So the daily run of Aug 5 took the lock, began `incremental-repack` on a 1.2 GB object store, and never released it.
- Last maintenance artifacts in the repo: `loose-*.pack` born **Aug 4 23:48**, `commit-graphs/commit-graph-chain` **Aug 4 23:48**, `multi-pack-index` **Aug 4 00:24** — i.e. the last *hourly* run before the Aug 5 00:16 crash. Nothing since.
- The hourly job **is firing**: `launchctl print gui/$UID/org.git-scm.git.hourly` → `runs = 20`, `last exit code = 0` (20 runs in 20 h of uptime ≈ hourly). Firing and doing nothing.
- Loose objects by creation date confirm the freeze: Aug 4 = 102, **Aug 5 = 725, Aug 6 = 2,764, Aug 7 = 5,446, Aug 8 = 809, Aug 9 = 1,154, Aug 10 = 659** — nothing packed after the lock appeared.
- No other repo in the fleet holds this lock (censused all 8).

**Cost now:** `.git` = **1,352 MB** vs 254 MB for the busier claude-infrastructure. 11,660 loose
objects = 142 MB in ~11.6 k separate inodes; 22 packs (every pack's `.idx` is opened and mmap'd by
every ref/object lookup); `prune-packable: 97`, `garbage: 1`. Disk, inodes and `git status`
latency (32 ms vs 17 ms in CI) — **not RAM**.

**Re-architecture:** delete the lock, then make lock-staleness self-healing rather than silent —
git has no lock TTL, so the pre-flight belongs in whatever runs maintenance.

**Sizing:** one `rm`; a single maintenance cycle should reclaim ≈ 100 MB and ~11.6 k inodes.
effort XS · risk low (verified no holder). The *detector* is effort S.

**Existing mechanism:** `org.git-scm.git.{hourly,daily,weekly}` LaunchAgents — **extend** with a
staleness pre-flight; do not add a new job.

```
# 1. verified stale (0 bytes, 5.5 d old, no lsof holder) — remove it:
rm /Users/chrisren/Development/reso-management-app/.git/objects/maintenance.lock
```

### F2 — The `daily` launchd job can only fire on the 1st–6th of a month (git writes `Day` where it means `Weekday`)

**Finding:** `git maintenance start` generates `<key>Day</key><integer>1..6</integer>` for the daily
job. launchd's `Day` is **day of month**; the key for weekday is `Weekday`. So the "daily" job runs
on the 1st–6th only — ~6 days in 31 — and the two tasks that consolidate packs
(`incremental-repack`, `pack-refs`) are on that schedule.

**Evidence:**
- `~/Library/LaunchAgents/org.git-scm.git.daily.plist` — six `<dict>` entries, `Day` 1–6, `Hour` 0, `Minute` 16.
- `launchctl print gui/$UID/org.git-scm.git.daily` → **`runs = 0`, `last exit code = (never exited)`** since the Aug 9 04:18 boot.
- **Discriminating test:** today is **Monday 2026-08-10**. Under *weekday* semantics `Day 1` = Monday → the job would have fired at 00:16, ~15 min before the reading, and `runs` would be ≥ 1. It is 0. Under *day-of-month* semantics Aug 10 ∉ {1..6} → no fire. Day-of-month wins.
- Corroboration: F1's lock is dated **Aug 5** 00:16 — day-of-month 5, inside `Day 1..6`. The daily job demonstrably ran that day and has not run since.
- The `weekly` plist uses `Day 0`, which is not a valid day-of-month; `runs = 1` (first `00:24` after boot, i.e. Aug 10 00:24) suggests launchd ignores the out-of-range key and runs it *every* day. Reported as observation, not asserted mechanism.

**Cost now:** in reso, `incremental-repack` and `pack-refs` are reachable ≈ 6 days/month even
without the lock — which is why 22 packs accumulated *before* Aug 5 as well.

**Re-architecture:** stop relying on the generated calendar. Either rewrite the plist keys, or —
better, see F3 — stop using launchd-scheduled maintenance for these repos at all.

**Sizing:** effort XS if patching the plist; risk low. Note the fix is **not durable**: a future
`git maintenance start`/`register` regenerates the plist and reverts it.

**Existing mechanism:** the three `org.git-scm.git.*` plists.

```
# make the daily job actually daily (launchd: Weekday, not Day) — then reload:
/usr/libexec/PlistBuddy -c 'Print' ~/Library/LaunchAgents/org.git-scm.git.daily.plist   # inspect first
```

### F3 — Enrollment is what broke the enrolled repo: `git maintenance register` turns off git's own self-healing (measured, with control)

**Finding:** Unenrolled repos maintain themselves. `git commit` invokes `git maintenance run --auto`,
which runs the `commit-graph` (and, with ≥2 packs, `incremental-repack`) task once its auto-condition
is met. `git maintenance register` writes **`maintenance.auto=false`** into the repo, which **deletes
that path entirely** — the repo then depends wholly on the launchd timers that F1 and F2 disabled.

**Evidence — positive/negative control pair, throwaway `/tmp` repos, `GIT_CONFIG_GLOBAL` redirected:**
- **Positive:** fresh repo, 150 commits (> the commit-graph task's 100-commit auto threshold), **no explicit `gc` or `maintenance` ever run** → `.git/objects/info/commit-graphs/commit-graph-chain` + one `graph-*.graph` layer appear. Auto-maintenance fired on its own.
- **Negative control:** identical repo, identical 150 commits, only difference `maintenance.auto=false` → `.git/objects/info/` **empty**, no commit-graph at all.
- **What `register` writes** (measured, real `~/.gitconfig` verified unchanged afterwards): local `maintenance.auto=false` + `maintenance.strategy=incremental`; global `maintenance.repo += <path>`. It does **not** write `gc.auto=0` — reso's `gc.auto=0` came from somewhere else, so reso has *three* independent self-healing paths off: `maintenance.auto=false`, `gc.auto=0`, and `strategy=incremental` (which disables the `gc` task in scheduled runs too).
- **Separately measured:** plain `git gc` writes a **non-split** `objects/info/commit-graph` and **no** midx. claude-infrastructure has a **split chain + midx** and no in-tree caller (grepped the whole repo, `~/.claude/{scripts,hooks}`, `~/bin`, `~/.local/bin`) — which is the auto-maintenance signature, not the `gc` signature. This is how CI stays at 87 loose objects / 4 packs with zero configuration.

**Cost now:** the fleet's healthiest repos are the ones nobody configured. The naive remediation —
"enroll everything in `git maintenance`" — would propagate reso's failure mode to seven more repos,
including the 119-worktree claude-infrastructure.

**Re-architecture:** **un-enroll reso and let auto-maintenance do the job**, matching the seven repos
that work. Keep `gc.auto` non-zero so the heavy path stays reachable. Reserve scheduled maintenance
for a repo that demonstrably needs `prefetch` (a background `git fetch`), and if kept, fix F2 first.

**Sizing:** recovers ~1.1 GB of `.git` in reso after the first cycle; removes 3 launchd timers ×
22 fires/day from the wake budget if fully un-enrolled. effort S · risk low-medium (reverts to git's
default behaviour, which the other 7 repos already run).

**Existing mechanism:** git's built-in auto-maintenance — nothing to build.

```
# un-enroll reso and restore git's own self-healing (do this AFTER the F1 rm):
git -C ~/Development/reso-management-app maintenance unregister && git -C ~/Development/reso-management-app config --unset maintenance.auto && git -C ~/Development/reso-management-app config --unset maintenance.strategy && git -C ~/Development/reso-management-app config --unset gc.auto
```

### F4 — `finance-ai-web-app` is ~2 files away from firing an unbounded, detached, 10-thread `gc`

**Finding:** git's auto-gc loose-object test is a heuristic: it counts entries in `objects/17` and
fires when that count > `gc.auto / 256` (= 26.2, so **27**). `finance-ai-web-app` has **25**. It has
**0 packs**, so the fire will be a *full* initial repack; `gc.autoDetach` defaults true, so it runs
detached and unattended; `pack.threads` defaults to **ncpu = 10**; `pack.windowMemory` defaults to
**0 = unlimited**.

**Evidence:** per-repo `ls .git/objects/17 | wc -l` → CI 0, reso 47 (`gc.auto=0`, disarmed),
doc_classifier 1, **finance-ai-web-app 25**, all others 0. `gc.auto` unset (=6700) in all seven
unenrolled repos. `sysctl -n hw.ncpu` = 10.

**Cost now:** zero today — no repo currently satisfies the condition. But this is the one git-shaped
mechanism that can allocate GBs and 10 cores with no warning, and it fires from an ordinary
`git commit` inside a hook, during a wave, on a box already measured at load 143.

**Re-architecture:** bound the heavy path globally rather than disabling it (disabling it is exactly
what made reso fat). `pack.windowMemory` caps per-thread delta window; `pack.threads` keeps a
background repack off every core.

**Sizing:** prevents an unbounded multi-GB / 10-core spike; costs a slower repack. effort XS ·
risk low. Global scope is correct here — it is a *bound*, not a behaviour change.

**Existing mechanism:** none — this is a new global bound.

```
# bound every future repack/gc fleet-wide (memory + core ceiling, keeps auto-gc enabled):
git config --global pack.windowMemory 256m && git config --global pack.threads 4
```

### F5 — Every git call in the shell layer is PATH-resolved, and under launchd that resolves to Apple Git 2.50.1 — 2.9× slower

**Finding:** `hooks/` and `scripts/` contain **501 bare `git ` invocations and 0 absolute-path
git invocations**. 20 of 22 `com.claude.*` LaunchAgents specify no `PATH`, so they inherit
launchd's `/usr/bin:/bin:/usr/sbin:/sbin` — where `git` is `/usr/bin/git` = **Apple Git 2.50.1**,
not the Homebrew `/opt/homebrew/bin/git` 2.54.0 the interactive shell uses.

**Evidence:**
- `grep -rhoE '(^|[^/a-zA-Z_.$-])git ' hooks scripts --include='*.sh' | wc -l` → **501**; same grep for `/opt/homebrew/bin/git|/usr/bin/git` → **0**.
- `env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin sh -c 'git --version'` → **`git version 2.50.1 (Apple Git-155)`**.
- Only `com.claude.team-orphan-reaper` sets an explicit `PATH` (`/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin`). At least `com.claude.lead-supervisor`, `gl.reso.csp-smoke`, `gl.reso.worktree-gc` run scripts containing bare `git` under the inherited PATH (the plist→script extractor under-counts wrapper-invoked jobs, so this is a floor, not a census).
- **Live proof it happens:** during measurement, `ps` caught `/opt/homebrew/bin/timeout -k 5 15 git -C …/claude-infrastructure status --porcelain` whose child was `/Applications/Xcode.app/Contents/Developer/usr/bin/git -C … status --porcelain` — homebrew `timeout` called by absolute path, `git` resolved by PATH to Apple's.

**Cost now (same repo, same op, min of 7):**

| op (claude-infrastructure) | Homebrew 2.54.0 | Apple 2.50.1 | ratio |
|---|---|---|---|
| `rev-parse --git-dir` | **6.7 ms** | **19.2 ms** | 2.9× |
| `status --porcelain` | 18.6 ms | 30.0 ms | 1.6× |
| `for-each-ref` | 11.7 ms | 27.3 ms | 2.3× |

`/usr/bin/git` is a shim that resolves the active developer dir and execs Xcode's git — most of the
12.5 ms delta on the cheapest call is that resolution, i.e. it is paid **per invocation** and does
not amortise. Max-RSS is unaffected (7.1 MB Apple vs 7.8 MB Homebrew).

**Re-architecture:** set an explicit `PATH` in every LaunchAgent plist that shells out (the
`team-orphan-reaper` plist is the in-repo precedent to copy). Do **not** hardcode
`/opt/homebrew/bin/git` at 501 call sites.

**Sizing:** ~12 ms saved per daemon git call; on the order of 2–3× fewer concurrently-resident git
processes for the same call rate. Real but modest — a latency/CPU win, not a memory win.
effort S · risk low.

**Existing mechanism:** `launchd/com.claude.team-orphan-reaper.plist` already carries the correct
`EnvironmentVariables:PATH` — replicate it.

```
# see which of our jobs lack an explicit PATH (read-only census before editing plists):
for p in ~/Library/LaunchAgents/com.claude.*.plist; do /usr/libexec/PlistBuddy -c 'Print :EnvironmentVariables:PATH' "$p" >/dev/null 2>&1 || echo "no PATH: $(basename $p)"; done
```

### F6 — 5,138 Claude Code checkpoint refs in one repo; bounded, but they are 83% of the ref graph

**Finding:** `refs/checkpoints/**` holds **5,138 refs in claude-infrastructure** (83% of its 6,212
refs) and **2,005 in reso-management-app** (68% of 2,939). They are written by Claude Code's
checkpointing at ~1 per 10–20 s per active session. They *are* bounded — but they pin every
checkpointed tree and blob against pruning for the life of the window.

**Evidence:** `for-each-ref 'refs/checkpoints/**'` → 5,138 / 2,005. Newest three in CI:
`20260810T073754Z`, `073801Z`, `073822Z` — 7 s and 21 s apart, i.e. live right now. Oldest
**2026-07-11**, newest **2026-08-10** → a **30-day** span; at ~171/day × 30 d ≈ 5,130 ≈ the 5,138
measured, so the window is self-consistent. Per-namespace histogram shows **11 namespaces at
exactly 50** refs plus one at 101 → a per-namespace cap around 50 as well.

**Cost now:** `packed-refs` = **534,126 B / 6,193 lines** in CI. Measured effect on ref-reading:
`for-each-ref` 11.7 ms in CI vs 8 ms in the 1-worktree whisper.cpp — **≈ 4 ms for 6,212 refs**.
`rev-parse HEAD` is 6.7 ms and does not read them all. So the *read* cost is small and bounded.
The real cost is object retention: nothing reachable from a checkpoint can ever be pruned, which is
a floor under `.git` size in both repos.

**Re-architecture:** none proposed. Two caps already exist (30-day, ~50-per-namespace) and both are
Claude Code's, not ours. Flagged so no other axis double-counts it as unbounded growth.

**Sizing:** n/a — this is a *bounded* mechanism. Do not "fix" it.

**Existing mechanism:** Claude Code's own checkpoint retention.

### F7 — Three unmanaged, unpruned stores inside `.git` that no maintenance task touches

**Finding:** `rr-cache`, `lost-found` and `cursor/crepe` together hold **114 MB in
claude-infrastructure and 40 MB in reso**, and none of them is reached by any scheduled task.

**Evidence:** `du -sm .git/*` →
CI: `objects` 121 MB, **`cursor` 56 MB**, **`lost-found` 35 MB**, **`rr-cache` 23 MB**, `worktrees` 17 MB, `logs` 2 MB, `filter-repo` 2 MB.
reso: `objects` 1,281 MB, `worktrees` 29 MB, **`rr-cache` 16 MB**, **`lost-found` 12 MB**, `cursor` 12 MB, `logs` 4 MB.
`rr-cache` entry counts: **184** (CI) / **170** (reso). `.git/cursor/crepe/<sha>/{metadata.json,index.bin,postings.bin}` — Cursor's semantic index, not git's.

- `rerere.enabled=true` + `rerere.autoupdate=true` are set **globally** in `~/.gitconfig`, so every
  repo accumulates rr-cache entries. `git rerere gc` runs **only as part of `git gc`** — and in reso
  `gc` is disabled by all three paths (F3), so **reso's rr-cache can never be pruned**. This is a
  second, independent consequence of the enrollment decision.
- `lost-found` is residue from past `git fsck --lost-found` runs. Nothing creates or removes it on a
  schedule; it is dead weight.

**Cost now:** 154 MB of disk fleet-wide, zero RAM. Also inflates every `du .git` reading, which is
how "reso's `.git` is 1.35 GB" gets mis-attributed to objects when 40 MB of it is not.

**Re-architecture:** un-enrolling reso (F3) restores `git gc`, which prunes `rr-cache` for free.
`lost-found` is a manual one-time delete. `.git/cursor` is Cursor's — leave it, but exclude it from
any `.git`-size instrumentation.

**Sizing:** ~47 MB immediate (`lost-found` in both repos), ~16 MB more once reso's gc runs again.
effort XS · risk low (`lost-found` is by definition already-unreachable objects git dumped there).

**Existing mechanism:** `git gc`'s built-in `rerere gc` — re-enable it via F3, don't rebuild it.

### F8 — Worktree metadata is clean; there are zero prunable worktrees

**Finding:** Contrary to the expectation embedded in the brief, `.git/worktrees` holds **no stale
entries** in any repo checked. The worktree problem (axis D) is live directories, not git metadata.

**Evidence:** `git worktree list --porcelain | grep -c '^prunable'` → **0** for
claude-infrastructure, reso-management-app and doc_classifier. Metadata dirs vs live list:
CI 119 vs 120 (incl. main), reso 74 vs 75, doc_classifier 62 vs 63 — every metadata dir has a live
worktree. `.git/worktrees` totals 16.8 MB (CI) / 29.5 MB (reso) / 15.3 MB (doc_classifier), i.e.
**~142 KB per worktree**, almost all of it the per-worktree `index`, which is read only by that
worktree's own git calls.

**Cost now:** negligible, and `git worktree prune` would be a no-op.

**Re-architecture:** none. Explicitly **do not** add a `worktree prune` step — it would fire on
nothing. Hand the real problem (live worktree directories, `~/Development/.worktrees` = 252 entries)
to axis D.

**Sizing:** n/a — negative finding, recorded so axis D is not asked to solve a metadata problem.

---

## 3. Direct answers to the brief's key questions

### (a) Enrollment, schedules, and whether the logs show success
**One repo enrolled** — `reso-management-app`, the only value of `maintenance.repo` in `~/.gitconfig`.
Under `maintenance.strategy=incremental` plus reso's explicit overrides, the schedule tiers run:

| tier | launchd fires | tasks it would run in reso | actually runs? |
|---|---|---|---|
| hourly (`:48`) | yes — `runs = 20` in 20 h | `prefetch`, `loose-objects` (explicit hourly), `commit-graph` (strategy default) | **no work done since Aug 4 23:48** — blocked by the stale lock (F1) |
| daily (`00:16`) | **never** — `runs = 0`, "never exited" | `incremental-repack` (strategy default), `pack-refs` (explicit daily) | **structurally unreachable** — plist fires only on the 1st–6th (F2) |
| weekly (`00:24`) | `runs = 1` | none (reso moved `pack-refs` to daily) | fires, no-op |

**There are no logs.** None of the three plists sets `StandardOutPath`/`StandardErrorPath`, so
git's own `warning: lock file … exists, skipping maintenance` goes to a closed fd. launchd reports
`last exit code = 0` for the hourly job while it accomplishes nothing — the failure is invisible by
construction, which is why it survived 5.5 days. *(Verified the plumbing is not at fault:
`git for-each-repo --config=maintenance.repo -- rev-parse --git-dir` resolves correctly, and
`git ls-remote origin HEAD` succeeds, both under a reproduced `env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin HOME=…`
launchd environment.)*

**Which repos need enrollment: none.** F3's control pair shows the unenrolled repos self-maintain.
The correct move is to un-enroll the one that is enrolled.

### (b) Object health, and does worktree metadata tax every hook's git call? — **No, measurably not**
Object health is in §1. On the timing question, the answer refutes the premise. Min-of-7,
Homebrew git 2.54.0, under load 143:

| op | CI main (119 wt, 6,212 refs, 254 MB) | CI linked worktree | reso (74 wt, 1.35 GB) | whisper.cpp (1 wt, 43 MB) |
|---|---|---|---|---|
| `rev-parse --git-dir` | 7 ms | 10 ms | 7 ms | **8 ms** |
| `rev-parse HEAD` | 8 ms | 10 ms | 7 ms | 8 ms |
| `symbolic-ref --short HEAD` | 7 ms | 11 ms | 9 ms | 8 ms |
| `status --porcelain` | 17 ms | 18 ms | 32 ms | **18 ms** |
| `for-each-ref` (all) | 11 ms | 14 ms | 14 ms | 8 ms |
| `log --oneline -1` | 11 ms | 11 ms | 10 ms | 8 ms |
| `worktree list` (120 entries) | 50 ms | — | — | — |

**The floor is ~7–8 ms for *any* git command in *any* repo, and the lean repo is not faster.** That
floor is process startup, not repo state. 119 worktrees and 6,212 refs buy ~3 ms on the ref-scanning
ops and **nothing** on the ops hooks actually use (`rev-parse`, `symbolic-ref`). reso's 32 ms
`status` tracks its 3,887-entry index and larger tree, not its worktree count. The only op that
scales with worktree count is `git worktree list` at 50 ms — and it is called from 21 sites.

**Therefore: the hook layer's git bill is dominated by *how many times* git is forked, not by repo
fatness.** That number is axis F's to produce; this axis supplies the per-call constants
(7 ms Homebrew / 19 ms Apple; 4.5–9.6 MB max RSS) and one multiplier: **111 git call sites across 89
hook files, 349 across 161 script files.**

### (c) fsmonitor at this scale — **do not enable it**
- `git fsmonitor--daemon` is **per-working-tree**, not per-repo: its IPC socket lives at
  `$GIT_DIR/fsmonitor--daemon.ipc`, and for a linked worktree `$GIT_DIR` is `.git/worktrees/<name>`.
- `core.fsmonitor` lives in `.git/config`, which — with `extensions.worktreeConfig` unset everywhere
  — **is shared by every linked worktree**. Setting it once on claude-infrastructure arms it for all
  119; fleet-wide it arms ~280.
- **Measured daemon cost: 5.3 MB RSS** (started in a throwaway `/tmp` repo, stopped immediately).
  280 × 5.3 MB ≈ **1.5 GB of new resident memory**, plus 280 long-lived processes and 280 FSEvents
  streams, on the exact 64 GB box this investigation is trying to unload.
- **And there is nothing to buy.** fsmonitor accelerates the untracked-file scan in `git status`,
  measured at 17–18 ms in claude-infrastructure. The hooks' hot calls are `rev-parse`/`symbolic-ref`,
  which fsmonitor does not touch at all.
- Zero `fsmonitor--daemon` processes are running now (`ps -Ao command | grep fsmonitor` → empty).

**Recommendation per repo class:** `core.fsmonitor` **unset everywhere** — including reso, whose
32 ms `status` is the only case with a plausible payoff and still does not justify 74 daemons.
The safe adjacent lever is `core.untrackedCache`, which stores its state in the **per-worktree
index** (`UNTR` extension) and starts no process — but at a 17 ms baseline the win is ≲ 5 ms, so it
is filed as *available, not recommended*. If it is ever wanted, it must be armed per worktree
(`git update-index --untracked-cache`), never by a shared `.git/config` key.

### (d) Repo-local hooks census
- **`core.hooksPath` is set in 3 of 8 repos**: reso → `scripts/hooks`, doc_classifier → `.githooks`,
  finance-ai-web-app → `.husky/_`. The other five use `.git/hooks`.
- **`init.templateDir = ~/.git-template`** seeds 4 hooks into every new clone/init:
  `pre-commit`, `pre-merge-commit` (191 lines each), `pre-push` (130), `commit-msg` (30). These are
  the `cc-git-identity-gate` and the AI-trailer rejector — the response to the Aug 5 identity
  incident documented in `~/.git-template/hooks/pre-commit:6-14`. **Note the interaction:** in the
  3 repos that set `core.hooksPath`, `.git/hooks` is bypassed entirely, so a template-seeded hook
  there is inert unless it was also copied into the configured path. reso's `scripts/hooks` does
  carry `pre-commit`/`pre-push`/`commit-msg`; doc_classifier's `.githooks` and
  finance-ai-web-app's `.husky/_` carry only `pre-commit`/`pre-merge-commit`/`pre-push`.
- **Dead sample-bait:** **13–14 `.sample` files per repo, ~110 fleet-wide**, all inert. Two repos
  (`sevenrooms-bridge`, `whisper.cpp`) have *only* samples — no live hook, no identity gate.
- **What is missing, and the honest verdict on each:**
  - `post-checkout` hygiene — exists in reso only. **Not recommended**: it would fire on every
    worktree creation and every branch switch across ~280 worktrees, adding forks to the hottest path
    to solve a problem F8 shows does not exist (0 prunable worktrees).
  - `pre-auto-gc` — this is the one worth having, and it is **not the "block gc" hook people reach
    for**. A `pre-auto-gc` returning non-zero *cancels* auto-gc, which is precisely how reso got fat.
    Its correct use here is a **stale-lock reaper** (F1) that then exits 0.
  - `post-merge` worktree-prune trigger — **not recommended**, same reason as `post-checkout`.

### (e) Safety against our layout
Every recommendation above was checked against the two constraints that bind this repo:
- **`.git/config` is shared by all linked worktrees** (`extensions.worktreeConfig` unset fleet-wide).
  This is why F4's bound is placed in `--global` (a uniform ceiling, safe to share) and why fsmonitor
  and untrackedCache are rejected/deferred (per-worktree resources armed by a shared switch).
- **The per-file-symlink live layer** (`.claude/CLAUDE.md`: most of `skills/ hooks/ bin/ scripts/`
  are per-file symlinks into this checkout). Nothing recommended here writes into the checkout's
  tracked tree or touches the symlink layer: F1 is an `rm` of an untracked lock inside `.git/`,
  F3/F4 are `git config` calls, F5 edits `~/Library/LaunchAgents` plists. **No recommendation
  requires a commit, a land, or a `deploy-live` fast-forward** — so none of them is exposed to the
  landed-≠-live gap (global `CLAUDE.md` § `🚀` rung).
- **Never commit/land in the shared checkout** (`.claude/CLAUDE.md`) — not engaged; this axis writes
  exactly one file, this report, in `/tmp`.
- **Concurrent-session index sharing** — F1's `rm` and F3's `config --unset` are safe under
  concurrency (the lock has no holder; `git config` locks `.git/config` itself). F3 should not be run
  while a reso session is mid-`/ship`.

---

## 4. Adversarial self-pass

Run before composing; each item investigated with real calls, and two of them changed the report.

1. **"You concluded git is not a memory problem from four commands' max-RSS."** Held up, and it
   is the load-bearing negative result: 4.5 MB (`rev-parse HEAD`) → 9.6 MB (reso `status`), with
   Apple git *cheaper* on RSS (7.1 MB) than Homebrew (7.8 MB). Even 15 sessions × several concurrent
   git calls is ≲ 150 MB transient. Only **5** git-family processes existed at the instant sampled,
   under load 143. Git's RAM footprint does not participate in the 15-session ceiling. The two
   exceptions are named as F4 (unbounded detached repack) and (c) (fsmonitor), both *latent*.
2. **"Packfile mmap / page cache."** Considered and dismissed with a reason: packs are mmap'd by
   inode, so 15 sessions touching reso's 1.1 GB pack share **one** page-cache copy, and it is
   reclaimable. Worst case fleet-wide is ~1.4 GB of shared, evictable page cache — not 15×.
3. **"Your `refs/prefetch` inference was wrong."** It was, and I corrected it. I first read
   `%(committerdate:relative)` = "6 days ago" as *prefetch stopped 6 days ago*; that field is the
   **commit's** date, not the ref's write time, and it proves nothing about the fetch. Removing that
   false corroborator is what forced the search that found the actual lock (F1). Recording the
   error because the wrong version was *more* persuasive than the right one.
4. **"You blamed a Homebrew git upgrade for the Aug 5 freeze."** Tested and refuted: Homebrew git
   2.54.0 was installed **2026-06-03 12:56** (`INSTALL_RECEIPT.json`, `stat /opt/homebrew/bin/git`),
   two months before the freeze. The LWCR/code-signing hypothesis suggested by
   `launchctl print`'s `needs LWCR update` on the daily job is a **consequence** of that job never
   having run, not a cause. Dropped.
5. **"Disk full."** Checked, not the cause: `/System/Volumes/Data` is 33% used, 4.9 TiB free,
   53 G inodes free. Also checked and excluded: object-dir permissions (`drwxr-xr-x`, owner
   `chrisren`), `.keep` files blocking repack (0), other stray `.git` locks (only
   `reso-writer.lock`, dated 2026-06-03, a separate reso-local mechanism).
6. **"Is the lock actually stale, or is a real run in flight?"** `lsof` on the lock returns no
   holder; the file is 0 bytes and 5.5 days old. The `rm` in F1 is conditioned on that check, and
   the check is stated so it can be re-run before acting.
7. **"You never proved `git gc` isn't the thing writing CI's commit-graph."** Proved it: a
   throwaway repo with 40 commits + an explicit `git gc` produced a **non-split**
   `objects/info/commit-graph` and **no** midx. CI has a split chain and a midx. Different writer —
   which is what led to the F3 control pair.
8. **"You assumed worktree metadata was bloat."** Measured instead, and it is not: 0 prunable
   entries in all three big repos. Recorded as F8 so the fleet's real worktree problem is not
   mis-routed to a git-metadata fix.

---

## 5. Open items — named, with the exact diagnostic, not run here

1. **Why the hourly job produced nothing between Aug 5 and now is *attributed* to the stale lock but
   not *traced*.** The temporal fit is exact (lock at Aug 5 00:16 = the daily plist's minute; last
   artifacts Aug 4 23:48) and no rival hypothesis survived §4, but the confirming trace is a
   mutating run and was therefore not executed. One command settles it, after the `rm`:
   `GIT_TRACE2_EVENT=/tmp/maint.json git -C ~/Development/reso-management-app maintenance run --schedule=hourly`
2. **The identity of claude-infrastructure's commit-graph/midx writer is inferred, not observed.**
   F3's control pair proves auto-maintenance *can* produce exactly this signature and that
   `maintenance.auto=false` suppresses it; no in-tree, live-layer or `~/bin` caller exists. But I did
   not catch the write in the act. `fs_usage -w -f filesystem | grep commit-graph` would.
3. **The launchd-job→git-caller census is a floor, not a complete list** (F5): the plist→script
   extractor only follows `ProgramArguments` entries ending in `.sh`/`.zsh`/`.py`, so
   wrapper-invoked jobs are under-counted.
4. **`git maintenance start` regenerates the daily plist**, reverting any F2 fix. If reso is
   un-enrolled per F3 this is moot; if scheduled maintenance is kept anywhere, the plist fix needs an
   assertion that survives regeneration.

---

## 6. The one command, if only one thing is done

The stale lock is the whole of the current damage, it has no holder, and removing it costs nothing:

```
rm /Users/chrisren/Development/reso-management-app/.git/objects/maintenance.lock
```

F3 (un-enroll) is the durable fix and should follow; F4 (`pack.windowMemory`/`pack.threads`) is the
only item on this axis that reduces a *memory* risk rather than a disk or latency one.

---

# Part II — Design: maintenance for the multi-worktree shared store under load
*(Added 2026-08-10 01:1x in response to the lead's steer. Part I above is unchanged.)*

## 7. The steer's premise is refuted — and the implied action would cause the harm

`docs/research/scaling-bottlenecks-2026-08-09.md:35` (row 3, "Fleet-self-imposed caps") states:
**"git shared store crosses `gc.auto` (6700 loose) within hours at 15×"**, binding at *hours*.
Measured live tonight at the exact load that claim describes (15+ sessions, load 143), it is wrong on
**mechanism** and on **magnitude**, and the correction inverts the recommendation.

**Wrong mechanism.** git's auto-gc never compares anything to 6,700 loose objects. `too_many_loose_objects()`
counts entries in **`objects/17` only** and fires when that count exceeds `gc.auto / 256` = **26**.
claude-infrastructure's `objects/17` held **1 entry** at peak. The store is ~26× from the trigger,
not "hours" from it.

**Wrong magnitude, and not monotone.** claude-infrastructure's loose-object count across 45 minutes
of live 15× load:

| time | loose objects | packs | reader |
|---|---|---|---|
| 00:22 | 67 | 3 | this axis |
| 00:52 | 87 | 3 | this axis |
| ~00:58 | **42** | — | the lead |
| 01:05 | 426 | **4** | this axis |

It **cycles** — it does not climb. The drop to 42 and the appearance of a 4th pack
(`pack-153d35a1ce9acef…`, absent at 00:31) between the readings is auto-maintenance packing the
store; `multi-pack-index` rewritten **00:34**, `commit-graphs/commit-graph-chain` **00:55**. The
shared store is not approaching a wall — it is running a working self-correcting loop, and the two
readings that looked like disagreement are two points on its sawtooth.

**The inversion.** The steer reads "not enrolled + nothing scheduling maintenance" as the gap. But
§F3 measured that **`git maintenance register` writes `maintenance.auto=false`**, and the negative
control (150 commits, `maintenance.auto=false`, zero maintenance artifacts) shows that key is exactly
the switch that stops the loop above. **Enrolling claude-infrastructure the ordinary way would
disable the mechanism currently keeping it at 42–426 loose objects, and make the prior wave's
prediction come true for the first time.** reso-management-app is the worked example of precisely
that: enrolled, `maintenance.auto=false`, **11,660 loose / 22 packs / 1,352 MB**.

Recommendation to the lead: **correct row 3 of `scaling-bottlenecks-2026-08-09.md`** — the git clause
should read *"git shared store: NOT a wall while `maintenance.auto` is on (measured cycling 42→426
loose at 15×, trigger is `objects/17` > 26, currently 1); becomes a wall within days if the repo is
ever enrolled via `git maintenance register`."*

## 8. What the shared store actually risks at 15× — one silent, permanent failure

Not `gc.auto`. The single point of failure is **`<objectdir>/maintenance.lock`: no TTL, no
observability, and one instance shared by every worktree.**

- claude-infrastructure's 120 worktrees share **one** object store, **one** `.git/config`, **one**
  maintenance lock (`extensions.worktreeConfig` unset ⇒ no per-worktree config anywhere in the fleet).
- Every worktree's `git commit` fires `git maintenance run --auto` against that shared store. Git
  serializes them on the lock and the losers skip silently — which is correct, and is the design
  working.
- **But any holder killed mid-run leaves the lock behind, and every subsequent run on the box becomes
  a permanent silent no-op.** The failure has no log (no plist sets `StandardOutPath`; git's
  `warning: lock file … exists, skipping maintenance` goes to a closed fd), no non-zero exit, and no
  alarm.
- claude-infrastructure has **~30× more concurrent maintenance-triggering writers than reso**
  (120 worktrees × 15 sessions vs 74 worktrees at far lower session density), and its sessions are
  killed routinely — pane close, `/handoff`, crash, reboot, the compressor OOM path. **It is at
  strictly higher risk of reso's failure than reso was.**
- Measured cost when it happens, from reso: **5.5 days undetected → 11,660 loose objects, 22 packs,
  +1.1 GB.** Nothing detected it; this audit did.

**So the design's center is a lock reaper and a liveness signal — not enrollment.**

## 9. The architecture — three layers, each with the store it lands in

| Layer | What | Lands in | Status |
|---|---|---|---|
| **L1** | Keep the self-correcting loop | per-repo `.git/config` (`maintenance.auto` **absent**, `maintenance.strategy` **absent**, `gc.auto` **non-zero**) | already true in 7/8 repos — **assert, don't change** |
| **L2** | Reap the stale maintenance lock | a periodic script; the lock file is `<repo>/.git/objects/maintenance.lock` | **missing — this is the real gap** |
| **L3** | Add only what `--auto` cannot do: `prefetch`, `pack-refs`, scheduled `incremental-repack` | per-repo `.git/config` task keys + `~/.gitconfig` `maintenance.repo` | partially wrong today (reso only, via the harmful path) |

### L3's enrollment command must NOT be `git maintenance register`

`register` does two separable things: it appends to global `maintenance.repo` **and** writes
`maintenance.auto=false` + `maintenance.strategy=incremental` locally. Only the first is wanted.
Do the first directly:

```
git config --global --add maintenance.repo /Users/chrisren/Development/claude-infrastructure
```

**Verified composition** (scratch repo, 150 commits + 3 branches, no explicit maintenance run):
setting per-task `maintenance.<task>.enabled/schedule` while leaving `maintenance.strategy` unset —
- auto-maintenance **keeps working** (commit-graph chain written on commit) ✓
- `gc` **stays default-enabled** (no strategy to disable it) ✓
- tasks with no auto-condition (`pack-refs`, `prefetch`) are **skipped under `--auto`** — `packed-refs`
  was absent after 150 commits ✓ — **so enabling `prefetch` does not cause a network fetch per commit.**
  This was the one hazard capable of making the recommendation worse than the status quo at 15×; it
  is measured closed.

### Per-repo L3 commands

**claude-infrastructure** (120 worktrees · 6,212 refs · 46 loose refs · `packed-refs` 534 KB · 4 packs).
Wants `pack-refs` most (the ref graph is the one thing genuinely large here), `incremental-repack`
on a schedule so pack count cannot drift, `prefetch` to collapse the fetch stampede at 15×:

```
git -C ~/Development/claude-infrastructure config maintenance.prefetch.enabled true && git -C ~/Development/claude-infrastructure config maintenance.prefetch.schedule hourly && git -C ~/Development/claude-infrastructure config maintenance.commit-graph.enabled true && git -C ~/Development/claude-infrastructure config maintenance.commit-graph.schedule hourly && git -C ~/Development/claude-infrastructure config maintenance.incremental-repack.enabled true && git -C ~/Development/claude-infrastructure config maintenance.incremental-repack.schedule daily && git -C ~/Development/claude-infrastructure config maintenance.pack-refs.enabled true && git -C ~/Development/claude-infrastructure config maintenance.pack-refs.schedule daily && git config --global --add maintenance.repo /Users/chrisren/Development/claude-infrastructure
```

**reso-management-app** — must be *un*-enrolled first (§F3), then re-enrolled the safe way. The
`--unset`s are what restore the loop; the `--add` re-grants scheduling without it:

```
git -C ~/Development/reso-management-app maintenance unregister; git -C ~/Development/reso-management-app config --unset maintenance.auto; git -C ~/Development/reso-management-app config --unset maintenance.strategy; git -C ~/Development/reso-management-app config --unset gc.auto; git -C ~/Development/reso-management-app config maintenance.prefetch.enabled true; git -C ~/Development/reso-management-app config maintenance.prefetch.schedule hourly; git -C ~/Development/reso-management-app config maintenance.commit-graph.enabled true; git -C ~/Development/reso-management-app config maintenance.commit-graph.schedule hourly; git -C ~/Development/reso-management-app config maintenance.incremental-repack.enabled true; git -C ~/Development/reso-management-app config maintenance.incremental-repack.schedule daily; git -C ~/Development/reso-management-app config maintenance.pack-refs.enabled true; git -C ~/Development/reso-management-app config maintenance.pack-refs.schedule daily; git config --global --add maintenance.repo /Users/chrisren/Development/reso-management-app
```

**doc_classifier** (62 worktrees · 646 refs · 6 packs · 1,260 loose) — same shape, lighter; skip
`prefetch` (low fetch traffic):

```
git -C ~/Development/doc_classifier config maintenance.commit-graph.enabled true && git -C ~/Development/doc_classifier config maintenance.commit-graph.schedule hourly && git -C ~/Development/doc_classifier config maintenance.incremental-repack.enabled true && git -C ~/Development/doc_classifier config maintenance.incremental-repack.schedule daily && git config --global --add maintenance.repo /Users/chrisren/Development/doc_classifier
```

**finance-ai-web-app** (5,513 loose · **0 packs** · no commit-graph · no midx) — the only repo whose
object store has never been packed at all, and the §F4 auto-gc candidate. Scheduling
`incremental-repack` gives it a first pack on a controlled schedule instead of via a surprise
detached full `gc`:

```
git -C ~/Development/finance-ai-web-app config maintenance.incremental-repack.enabled true && git -C ~/Development/finance-ai-web-app config maintenance.incremental-repack.schedule daily && git -C ~/Development/finance-ai-web-app config maintenance.loose-objects.enabled true && git -C ~/Development/finance-ai-web-app config maintenance.loose-objects.schedule daily && git config --global --add maintenance.repo /Users/chrisren/Development/finance-ai-web-app
```

**reso-web-app · voiceink · whisper.cpp · sevenrooms-bridge** — **no change**. 1–3 worktrees, 0–602
loose objects, commit-graph and midx already present in three of them. Enrolling them adds launchd
work for no measured problem.

> **L3 is worthless until §F2 is fixed.** All four `incremental-repack`/`pack-refs` schedules above
> are `daily`, and the daily launchd job fires only on the 1st–6th of a month. Sequence the plist fix
> **before** these commands, or set those two tasks to `hourly` instead.

## 10. L2 — the stale-lock reaper (the actual missing mechanism)

Must be **safe** (never remove a lock a live run holds), **cheap** (it will run often), and hosted
where `git maintenance start` cannot revert it — which rules out the `org.git-scm.git.*` plists,
since git regenerates them.

Safe predicate, measured against tonight's real instance: **age > 2 h AND no `lsof` holder**. reso's
was 0 bytes, 5.5 days old, no holder; a genuine `incremental-repack` on the 1.2 GB store finishes far
inside 2 h.

```
for r in ~/Development/claude-infrastructure ~/Development/reso-management-app ~/Development/doc_classifier ~/Development/finance-ai-web-app; do L="$r/.git/objects/maintenance.lock"; [ -e "$L" ] && [ -z "$(lsof -t "$L" 2>/dev/null)" ] && [ -n "$(find "$L" -mmin +120 2>/dev/null)" ] && rm -f "$L" && echo "reaped stale maintenance lock: $r"; done
```

**Host it by extending an existing periodic job, not by adding one** — the fleet already carries 30
LaunchAgents and axis B is costing them. Selection criterion for the host: already periodic at ≥
hourly, already shells out to git, and is not itself regenerated by a vendor tool.
`com.claude.postland-verify` and `com.claude.worktree-gc-infra` both fit; **axis B owns the final
pick**, since only it has the full cadence/cost inventory. Do not create `com.claude.git-maint`.

**And give the failure a voice.** The reason this cost 5.5 days is that a skipped maintenance run is
indistinguishable from a successful one. The reaper should emit a structured verdict token its
consumer can parse (`verdict=reaped|clean|held`) rather than relying on exit status — the fleet's own
`claimed-outcome-vs-checked-outcome` rule, and the same defect class as
`git for-each-repo` returning 0 for 130 consecutive no-ops.

## 11. The missing git hooks — and the exec-assessment inode constraint

The lead's constraint (per-file symlinks are load-bearing; one inode assessed once box-wide —
`11-prior-art.md:61`) **is being violated by the git-hook layer today.**

**Measured:** `init.templateDir = ~/.git-template` seeds hooks as **regular file copies**, not
symlinks (`-rwxr-xr-x`, 11,477 B). Each repo therefore holds its own inode, and they have **drifted**:

| repo | `.git/hooks/pre-commit` | state |
|---|---|---|
| `~/.git-template` (source) | 11,477 B, Aug 8 13:38 | current |
| claude-infrastructure | 11,477 B, Aug 8 13:38 | current |
| doc_classifier | **10,905 B**, Aug 8 04:12 | **stale revision** |
| voiceink | **10,905 B**, Aug 8 04:13 | **stale revision** |
| reso-management-app | **3,997 B, Jan 14 2026** | **stale AND inert** — `core.hooksPath=scripts/hooks` bypasses `.git/hooks` entirely |

So the `cc-git-identity-gate` — which exists *because* of the Aug-5 identity incident that put 710
unattributable commits into this repo (`~/.git-template/hooks/pre-commit:6-14`) — is a **different
version in 2 of 4 sampled repos and completely bypassed in a third**. Up to **8 repos × 4 hooks = 32
inodes** where 4 would do, each needing its own exec assessment.

**Fix: one inode per hook, symlinked, so drift is structurally impossible and the box assesses each
hook once.** For a repo using `.git/hooks` (verify the target path against
`scripts/git-identity-assert.sh`, which owns the install and recognises its own marker):

```
for r in doc_classifier voiceink reso-web-app finance-ai-web-app; do for h in pre-commit pre-merge-commit pre-push commit-msg; do ln -sfn ~/.git-template/hooks/$h ~/Development/$r/.git/hooks/$h; done; done
```

Two caveats that must be honoured before running it:
- **`core.hooksPath` wins.** `doc_classifier` (`.githooks`), `finance-ai-web-app` (`.husky/_`) and
  `reso` (`scripts/hooks`) bypass `.git/hooks`, so for those three the symlink must land in the
  configured directory instead — and for `finance-ai-web-app`, husky owns that directory and will
  overwrite it on `npm install`. Those are per-repo decisions, not a loop.
- **`~/.git-template/hooks/*` is not itself in the checkout** — it is a copy too. The full fix points
  the template files at the checkout inode as well, which is `scripts/git-identity-assert.sh`'s job,
  not a bare `ln`.

**The hook that is genuinely missing is not `post-checkout` or `post-merge`.** §F8 measured **0
prunable worktrees** in all three big repos, so a worktree-prune trigger would fire on nothing while
adding a fork to the hottest path across 280 worktrees. And `pre-auto-gc` is a trap: it *cancels*
auto-gc when non-zero, which is the reso failure mode wearing a hook's clothes. **The missing
mechanism is L2, and it is a periodic reaper, not a hook** — because the lock must be cleared even
when nobody is committing, which is exactly the state reso was in.

## 12. Landing table — every recommendation, and the store it lands in

| # | Action | Lands in | Reverted by | Risk |
|---|---|---|---|---|
| F1 | `rm …/reso…/.git/objects/maintenance.lock` | untracked file in `.git/objects/` | nothing | low — verified no holder |
| F3 | `maintenance unregister` + 3 `--unset` | reso `.git/config` + `~/.gitconfig` | `git maintenance register` | low — restores the 7-repo default |
| F4 | `pack.windowMemory 256m`, `pack.threads 4` | `~/.gitconfig` (global bound) | nothing | low |
| F2 | `Day`→`Weekday` in the daily plist | `~/Library/LaunchAgents/org.git-scm.git.daily.plist` | **`git maintenance start`** | low, **not durable** |
| F5 | explicit `PATH` in LaunchAgents | `~/Library/LaunchAgents/com.claude.*.plist` | nothing | low |
| L2 | stale-lock reaper | an existing periodic script (axis B picks the host) | nothing | low |
| L3 | per-task keys + `--add maintenance.repo` | per-repo `.git/config` + `~/.gitconfig` | `git maintenance register` | low — composition measured |
| §11 | hook symlinks | `.git/hooks/` or `core.hooksPath` dir | `npm install` (husky repos only) | medium — read `scripts/git-identity-assert.sh` first |

**None of these touches the checkout's tracked tree, requires a commit, or needs a `deploy-live`
fast-forward** — so no recommendation on this axis is exposed to the landed-≠-live gap.

## 13. Ordering — F1 and L2 first, L3 last

1. **F1** `rm` the stale lock — the only current damage, and L3 does nothing until it is gone.
2. **L2** the reaper — before L3, so re-enrolment cannot recreate a silent 5-day outage.
3. **F4** the global `pack.*` bound — before any repack runs at scale.
4. **F2** the plist `Day`→`Weekday` — L3's `daily` schedules are inert without it.
5. **F3 / L3** un-enrol reso, then per-repo task keys + `--add maintenance.repo`.
6. **F5 / §11** the PATH and hook-inode cleanups — independent, any time.
