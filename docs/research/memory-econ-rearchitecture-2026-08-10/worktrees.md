# Axis D — Worktree lifecycle audit (2026-08-10)

**Verdict.** The janitor is not broken and the gates are not too strict. `com.claude.worktree-gc-infra`
has **`runs = 0`** — launchd has never once executed it — so every sweep this repo has ever had was
hand-fired, and the last one (2026-08-09 22:15:24 → 23:02:56, **47 min 32 s**, 319 removed) was a
human. Where a janitor *does* run, one arm blocks the majority, and it is a **different arm per repo**:
claude-infrastructure is blocked by `dirty` (71 of 118 blocked by that arm ALONE), reso by `unlanded`
(47 of 74 clean-but-never-landed). Of the 87 dirty infra worktrees, **73 are dirty only from one shared
banner/blender asset set** and **38 are provably zero-loss** (every dirty blob already reachable from
`origin/main`). Creation is event-driven; removal is calendar-driven and the calendar never fires.

**Refuted here, deliberately** (see §5): 274 worktrees do **not** hold RAM (110 of 118 have zero open
fds), do **not** slow git (0.02–0.04 s on every op measured), and are **not** a disk-capacity problem
(4.9 TiB free). The memory link is indirect and I say so rather than manufacture it.

---

## 1. Population — fleet census (measured 2026-08-10 00:20–01:05)

| Repo | Worktrees | Disk | Mean | `node_modules` | Dirty | `.git/worktrees` admin | Janitor |
|---|---:|---:|---:|---:|---:|---:|---|
| claude-infrastructure | **120** (118 at census) | 5.82 GB | 50.5 MB | 75 | 87 | 118 dirs / 16 MB | `com.claude.worktree-gc-infra` — **runs = 0** |
| reso-management-app | 74 | **144.18 GB** | 1,995 MB | 72 | 23 | 74 dirs / 29 MB | `gl.reso.worktree-gc` — live, event-driven |
| doc_classifier | 62 | 41.50 GB | 685 MB | 35 | 10 | 62 dirs / 15 MB | **NONE** |
| finance-ai-web-app | 9 | 2.09 GB | 268 MB | 2 | 4 | 9 dirs / 600 KB | none |
| reso-web-app · voiceink · sevenrooms-bridge · whisper.cpp · shadcn-* | 9 | unmeasured | — | — | — | — | none |
| **TOTAL** | **274** | **≥193.6 GB** | — | **184** | **≥124** | **263 dirs / 60.6 MB** | 2 daemons for 9 repos |

Counted with `git worktree list --porcelain | grep -c '^worktree '` minus the primary checkout, per
repo under `~/Development/*/`. 246 of the 274 live under the shared `~/Development/.worktrees`
(shared across 5 repos — `scripts/worktree-gc.sh:14` calls this the highest-severity audit finding).
**9 orphan directories** exist there with no git record; all are empty (0 GB) — a non-issue, reported
because I looked for it.

### claude-infrastructure — full distribution (n=118)

| Dimension | Breakdown |
|---|---|
| Dirty / clean | 87 dirty · 31 clean |
| Dirty composition | 82 tracked-dirty · 5 untracked-only |
| Landed / unlanded | 81 landed · 35 unlanded · 2 detached |
| Cross | landed+dirty **73** · unlanded+clean 21 · unlanded+dirty 14 · landed+clean 8 · detached+clean 2 |
| Branch-tip age | <24 h 19 · 24–72 h 7 · 3–7 d 1 · **7–30 d 89** · >30 d 0 · n/a 2 |
| Live (open fd or claude cwd) | **8 of 118** |
| Gitignored content present | 97 of 118 |
| `.teammate-busy` / missing dir | 0 / 0 |

Source: `/tmp/wt-infra-stats.tsv`, one row per worktree (`git status --porcelain`,
`git log -1 --format=%ct <branch>`, `git cherry origin/main <branch>`, `du -sk`).

---

## 2. Which GC arm blocks — quantified per arm, independently

`scripts/worktree-gc.sh:722-732` is an `elif` chain, so its printed KEEP reason is a **priority-ordered
attribution, not a per-arm count** — a worktree that is both dirty and live only ever reports "dirty".
I therefore evaluated every arm against all 118 independently.

| Arm | Blocks (of 118) | Blocks **ALONE** | Gate |
|---|---:|---:|---|
| `dirty tree` | **87** | **71** | `worktree-gc.sh:726` |
| `unlanded` (`git cherry` patch-id) | 35 | 17 | `:744`, `landed()` at `:374-379` |
| `LIVE` (cc-notify ∪ lsof cwd ∪ registry) | 9 | 2 | `:728-731` |
| idle floor (<30 min tip age) | 9 | 0 | `:742`, `CC_WTGC_IDLE_MIN=30` |
| `CC_WTGC_EXCLUDE` | 3 | 0 | `worktree-gc-infra-run.sh:142` |
| detached HEAD | 2 | 1 | `:732` |
| **already reapable** | **5** | — | — |

**The dirty arm is the whole story here, and 84% of it is one artefact.** Aggregating every dirty path
across all 87:

| Path | Worktrees dirty on it |
|---|---:|
| `assets/demo/recycle-bmo.mp4` | 78 |
| `tools/banner/recycle.py` | 77 |
| `assets/banner/recycle-bmo.svg` | 77 |
| `docs/research/recycle-banner-source-fidelity-2026-07-30.md` | 74 |
| `tools/blender/clawd_bmo.py` + 3 `assets/blender/*.webp` | 28 each |
| `assets/demo/clawd-bmo-orbit.mp4` | 14 |
| everything else (tests, scripts, hooks) | ≤2 each |

- **73 of 87** have a dirty set that is a strict subset of that shared asset list.
- All are **staged** (`A ` in porcelain — in the worktree index, absent from its HEAD), index mtimes
  2026-07-30/31, file mtimes 2026-07-31 14:28, while the asset only landed on `origin/main` on
  2026-08-08 (`b9896b4ea272`). Each worktree HEAD *is* an ancestor of `origin/main`.
- **Producer UNATTRIBUTED.** Ruled out by reading the code: `scripts/lead-deathwatch.sh:69` (uses a
  `mktemp` `GIT_INDEX_FILE`, never the worktree index — clean); reso's warm pool
  (`scripts/worktree-pool.sh` does not exist in this repo, `hooks/worktree-setup.sh:154-156` gates on
  it); `scripts/new-worktree.sh:98` (copies gitignored files, which surface as `!!`, not `A `). Naming
  the producer is genuinely open — see §8.

**The zero-loss test** (content, never count — repo doctrine). Hash every path git reports as changed
and ask whether that blob is in `git ls-tree -r origin/main`:

- **38 of 87 dirty worktrees carry ZERO unique content** — every dirty blob is already on the trunk.
  Removing them cannot lose a byte, and today all 38 are permanent KEEPs.
- 49 carry ≥1 blob not on trunk, but the tail is almost entirely **superseded binary asset revisions**:
  28× `assets/blender/*` + `tools/blender/clawd_bmo.py`, 14× `clawd-bmo-orbit.mp4`, 5× an older
  `recycle-*`. Genuinely unique *code*: 2 worktrees with `scripts/handoff-fire.sh`, ~15 with a single
  `tests/*.bats`. **Real work at risk ≈ 17 worktrees, not 87.**

### The other repos block on a different arm

| Repo | Dominant state | Count |
|---|---|---:|
| reso-management-app | **UNLANDED / clean** | 47 of 74 (+6 unlanded/dirty) · 52 of 74 older than 7 d |
| doc_classifier | UNLANDED/clean 26 · **LANDED/clean 26** (fully reapable, no janitor exists) · landed/dirty 9 · unlanded/dirty 1 |

A single "fix the dirty gate" change therefore helps claude-infrastructure and almost nothing else.
reso needs the **DISPOSE class**, and does not have it: `~/Development/reso-management-app/scripts/worktree-gc.sh`
(23 KB, 2026-07-03) contains **0 occurrences of `dispose`** — it is an older fork predating the class
that `claude-infrastructure/scripts/worktree-gc.sh:30-105` added. doc_classifier's 26 landed+clean
worktrees need nothing but a janitor that runs.

---

## 3. Why the daemons leave them — five causes, in order of size

**C1 — the infra janitor has never been executed by launchd.**
`launchctl print gui/501/com.claude.worktree-gc-infra` → `runs = 0`, `last exit code = (never exited)`,
`state = not running`. It is bootstrapped and enabled; the kill switch
(`~/.claude/autonomy/worktree-gc-infra.disabled`) is absent. `RunAtLoad` is `false` and the only trigger
is `StartCalendarInterval 04:15` (plist :47-52) — **no `WatchPaths`**. The log shows sweeps at
2026-08-06 04:15 (removed 65 / kept 126) and 2026-08-07 04:15 (`verdict=skipped reason=janitor-lock-held`
— its own lock was held by reso's 03:15 sweep, so the one-hour offset the plist header reasons about did
not suffice), then **nothing on 08-08 or 08-09**, then the hand-fired 08-09 22:15 sweep. `runs = 0` dates
the current bootstrap after the last calendar opportunity. A calendar-only trigger on a laptop that
sleeps is a trigger that fires on the machine's schedule, not the work's.

**C2 — the dirty gate cannot see that dirt is content-free** (§2): 71 sole-blocked, 38 provably zero-loss.

**C3 — the DISPOSE class has three oracles and no machine writer.**
`worktree-gc.sh:38-60` will reap abandoned-unlanded work only with A1 (>72 h) + A2 (owner terminal) +
A3 (commits preserved). A2's three oracles are: a `wt-<backlog-id>` folded to `done` (:433), a dead/archived
team for `wt-tm-<m>` (:448), or an explicit human-written warrant (:508). The last sweep's own summary:
**"1 reapable, 8 past the horizon with NO ownership oracle at all, 5 owned-but-not-terminal."** The
warrant writer (`--warrant`, :214-289) exists **for humans only** — nothing on this box has ever produced
one automatically, so the un-ownable residue can only be drained by hand. That is the same
"no operator action required means nothing happens" failure the class was filed against.

**C4 — coverage is per-repo and hardcoded.** Two daemons for nine repos.
`~/.reso/worktree-gc-run.sh:31` hardcodes `REPO=/Users/chrisren/Development/reso-management-app`;
`scripts/worktree-gc-infra-run.sh:22` hardcodes claude-infrastructure. doc_classifier (62 worktrees,
41.5 GB, 26 of them landed and clean) has no janitor at all.

**C5 — nothing removes a worktree at the two events that make it removable.** Grepped
`commands/ship.md`, `scripts/desk-land.sh`, `hooks/session-end.sh`, `hooks/session-deregister.sh`:
`/ship` performs **no** worktree removal (`desk-land.sh:92` removes only the temp worktree it created
itself), and none of the six `SessionEnd` hooks in `~/.claude/settings.json` touches a worktree. Two
event paths *do* exist and work: `bin/cc-reaper:635` (`worktree remove --force` on a dead session, gated
on `work_landed()` and a clean tree at :632 — the same dirty arm as C2) and
`hooks/teammate-auto-shutdown.sh:1237` (teammate teardown).

---

## 4. Creation : removal — the population is rising and creation is structural

| Signal | Measurement |
|---|---|
| Admin-dir birthtimes, infra **survivors** | 07-29: 9 · **07-31: 57** · 08-01: 6 · 08-06: 1 · 08-07: 2 · **08-09: 13** · **08-10: 6 (by 00:30)** |
| doc_classifier survivors | 07-21: 12 · 07-30: 9 · **07-31: 25** |
| Last sweep | 08-09 22:15 removed **319**, kept 108 ⇒ population before it was **427** |
| Since that sweep | 108 → **120** in ~26 h (**+12 net**), and 118 → 120 **during this 40-minute audit** |
| Removal events | 3 sweeps in the log's window (08-06, 08-07 skipped, 08-09 manual) + per-session `cc-reaper` |

Birthtimes undercount creation by construction (they only survive on worktrees that were not reaped),
so the true rate is bounded below by 319 removals in ≤3.5 days ≈ **90/day**.

**Creation is wired to five event producers; removal to one calendar that never fires.**
`scripts/handoff-fire.sh:6138` (`git worktree add "$WT" -b "$WORKTREE" "$BASE"` — one per dispatched
session) · `bin/cc-wave-plan:585` (one per wave item, `wt-<backlog-id>`) · `scripts/new-worktree.sh:90`
(the `~/.zshrc` always-isolate gate — every `claude -w`) · `hooks/worktree-setup.sh` (the
`WorktreeCreate` matcher) · teammate spawns. The global `CLAUDE.md` directive that makes a **dispatched
session the default execution locus for every implementation wave** is, mechanically, the worktree
production function. It has no matching consumption function.

---

## 5. Cost — measured, including three of my own hypotheses that failed

| Claim | Measurement | Verdict |
|---|---|---|
| Disk | 193.6 GB over 262 measured worktrees; reso alone 144 GB @ 2 GB mean | **Real, but not scarce** — `df`: 2.3 TiB used of 7.3 TiB, **4.9 TiB free** |
| `.git/worktrees` admin metadata | 263 dirs, 60.6 MB total | Negligible |
| Git-op slowdown from 118 worktrees | `worktree list --porcelain` 0.04 s · `status` 0.03 s · `branch --list` 0.02 s · `for-each-ref` 0.04 s | **REFUTED** at this scale |
| Hot-path hook cost | `hooks/git-worktree-guard.sh` is on `PreToolUse\|Bash`, but `:41-46` early-exits before any `git worktree list` unless the command matches `worktree remove` / `branch -d` | **REFUTED** |
| Spotlight / `mds_stores` | `mds_stores` RSS **647 MB**; `mdfind -onlyin ~/Development/.worktrees` → **0** hits vs 102,120 in `~/Development` (control proves the instrument works). `.worktrees` is dot-prefixed ⇒ already invisible to Spotlight | **REFUTED for the 246 under `.worktrees`**; the 8 at `~/Development/wt-*` are non-dot and *are* indexed |
| Direct RAM | **8 of 118** infra worktrees have any open fd or claude cwd. 110 hold **zero** resident bytes | **REFUTED — an idle worktree is not a memory consumer** |
| **Sweep cost** | 22:15:24 → 23:02:56 = **47 min 32 s** for 427 worktrees ≈ **6.7 s/worktree**, forking `git status` + `git cherry` per worktree and `lsof` per claude pid, at `Nice 10` / `ProcessType Background` (4–84× tax) | **Real** — and it grows superlinearly with the population it fails to reduce |
| File count | reso 87,068 files/worktree × 74 ≈ **6.4 M** · doc_classifier 19,121 × 62 ≈ **1.2 M** · infra 1,937 × 118 ≈ 229 K ⇒ **≈ 7.9 M files** | Real; feeds fseventsd (15.7 MB) and every editor/watcher that opens one |
| Ref inflation | infra **6,258 refs**: 5,180 `refs/checkpoints/*` + 590 `refs/wip/*` + 483 heads; range 2026-07-11 → 2026-08-10; **nothing prunes them** (producers: `hooks/teammate-checkpoint.sh`, `hooks/lead-crash-watchdog.sh`, `hooks/teammate-auto-shutdown.sh`). Pack 117 MB / 53,746 objects; `maintenance.strategy` **UNSET**. reso: 2,947 refs | **Real** — worktree-lifecycle-generated, un-expired; hand to axis E |

**The honest memory link.** Worktree *count* is not a RAM consumer; worktree *count* is the multiplier on
things that are — a session per live worktree (axis A/G), an editor TS-server + watcher per opened
worktree (axis M), 7.9 M files under fseventsd, and a 47-minute background sweep that itself forks
thousands of `git` processes. The operator's framing ("worktrees left open without event-driven
clean-up") is correct about the *mechanism* and, on this evidence, wrong about the *resource*: fixing it
buys back ~190 GB of disk, kills a 47-min background job, and removes a multiplier — not GB of RAM.

---

## 6. Event-driven redesign — every path named by its triggering EVENT

The reference implementation already exists on this box and is not ours to invent:
`gl.reso.worktree-gc.plist` carries **`WatchPaths → ~/.reso/worktree-gc.wake`** alongside its calendar
arm, and `reso-management-app/.claude/settings.json:131,148` touches that file on **SessionStart** and
**SessionEnd**. Measured live: reso's janitor woke at 23:48:05, 00:15:31 and 00:22:51 — three times in
35 minutes, reaping `wt-cc-232428-26432` one grace-cycle after its session died. That is the whole
pattern; claude-infrastructure has the janitor and lacks the wiring.

| # | Triggering EVENT | Action | EXTENDS (never new) | Grace window |
|---|---|---|---|---|
| **E1** | `WatchPaths` fires on the wake file | run the sweep | `com.claude.worktree-gc-infra.plist` — add a `WatchPaths` array beside the existing `StartCalendarInterval`, byte-for-byte as `gl.reso.worktree-gc.plist:16-19` does | none — this is only the actuator; every gate in `worktree-gc.sh` still binds |
| **E2** | **SessionEnd** | `touch ~/.claude/state/worktree-gc.wake` | `~/.claude/settings.json` `SessionEnd` (already 6 hooks) — one line, exactly reso's `.claude/settings.json:148` | `CC_WTGC_IDLE_MIN=30` already **is** the grace window (`worktree-gc.sh:742`); plus the act-time re-check at `:584-600` |
| **E3** | **`/ship` post-land success** | same `touch` | `commands/ship.md` closing step — the land is the moment `landed()` flips true for that branch | none needed; the branch is on trunk by then |
| **E4** | any dirty-but-content-free tree, at sweep time | **new gate**: a worktree whose entire `status --porcelain` set hashes to blobs all reachable from `$TRUNK` is content-free ⇒ the dirty arm does not apply | `worktree-gc.sh:726` becomes `dirty AND NOT trunk-reachable`. Content check by blob sha, never a count — the repo's own landed-verification doctrine | the existing `git worktree remove` **without** `--force` stays the second gate |
| **E5** | **pane/session death without a land** | `cc-reaper` writes a **dispose warrant** instead of leaving the tree | `worktree-gc.sh --warrant` (`:214-289`) already validates path-exact + sha-pinned + reason-required; `bin/cc-reaper:620-640` already knows the pane died and the tree's state. This gives oracle 3 the machine producer it has never had (cause C3) | A1's 72 h horizon still gates the disposal; the sha pin self-invalidates if work resumes; a LIVE owning team still vetoes (`:563`) |
| **E6** | teammate teardown | already implemented | `hooks/teammate-auto-shutdown.sh:1237` | — |
| **E7** | same wake sweep | expire `refs/checkpoints/*` + `refs/wip/*` past N days | nothing prunes them today; `worktree-gc.sh` `--prune-branches` is the natural sibling. **Hand to axis E (git-maint)** — with `maintenance.strategy` UNSET, these 5,770 refs pin every checkpointed object against gc | age-based, and the reap path never deletes a ref the branch still needs |
| **E8** | repo coverage | make the repo a **list**, not a constant | `scripts/worktree-gc-infra-run.sh:22` is already a single `CC_WTGC_INFRA_REPO` seam — iterate it over `{claude-infrastructure, doc_classifier, finance-ai-web-app, …}`; reso keeps its own daemon | its existing wrapper lock + the shared `CC_WTGC_LOCK` already serialise against reso's sweep |

**Sequencing note.** E1+E2+E3 are the actuator and cost ~4 lines; they change the *when*. E4 and E5 change
the *whether* and are what actually drains the 71+17. Shipping the actuator alone would make a
47-minute no-op run more often — strictly worse. E4 before E1.

---

## 7. Findings — canonical 6-line rows

**Finding: the scheduled janitor has never been executed by launchd**
Evidence: `launchctl print gui/501/com.claude.worktree-gc-infra` → `runs = 0`, `last exit code = (never exited)`; plist has `RunAtLoad false` + `StartCalendarInterval 04:15` only, no `WatchPaths` (`com.claude.worktree-gc-infra.plist:47-55`); the 319-worktree sweep at 08-09 22:15:24 was hand-fired
Cost now: 120 worktrees, 5.82 GB, growing +12 net per 26 h; sweeps happen only when a human remembers
Re-architecture: add `WatchPaths → ~/.claude/state/worktree-gc.wake`, touched at SessionEnd and at `/ship` post-land
Sizing: ~4 lines · effort S · risk low (the calendar arm stays; the wake only actuates gates that already exist)
Existing mechanism: `gl.reso.worktree-gc.plist` + `reso/.claude/settings.json:131,148` — **copy, do not invent**

**Finding: the dirty gate blocks 71 of 118 alone, and 38 of those carry zero unique content**
Evidence: independent per-arm census (dirty 87 / unlanded 35 / live 9 / idle 9 / excluded 3 / detached 2; sole-blocked: dirty 71, unlanded 17, live 2); blob-reachability test against `git ls-tree -r origin/main` → 38 worktrees where every dirty blob is already on trunk; gate at `worktree-gc.sh:726`
Cost now: 71 permanent KEEPs ≈ 3.6 GB; they will never age out, because age is not one of the dirty gate's terms
Re-architecture: dirty ⇒ KEEP only when the dirty set contains a blob **not** reachable from `$TRUNK` (content check, never a count)
Sizing: recovers ≥38 worktrees ≈ 1.9 GB immediately, up to 73 after the shared-asset dirt is cleared at source · effort M · risk low (`worktree remove` without `--force` remains the second gate)
Existing mechanism: `worktree-gc.sh` gate 3 — tighten the predicate, add no new script

**Finding: 73 of 87 dirty worktrees are dirty from one staged asset set, producer unidentified**
Evidence: `assets/demo/recycle-bmo.mp4` staged (`A `) in 78, `tools/banner/recycle.py` 77, `assets/banner/recycle-bmo.svg` 77, `docs/research/recycle-banner-source-fidelity-2026-07-30.md` 74, `tools/blender/*` 28; index mtimes 2026-07-30/31, asset landed on main 2026-08-08 (`b9896b4ea272`); ruled out `lead-deathwatch.sh:69` (temp `GIT_INDEX_FILE`), reso's warm pool (absent here), `new-worktree.sh:98` (produces `!!`, not `A `)
Cost now: it is the sole cause of 60% of the repo's un-reapable population
Re-architecture: E4 makes the *symptom* harmless; the producer still needs naming or it re-emits on the next asset wave
Sizing: unblocks 73 · effort S for E4, **unknown** for the producer · risk low
Existing mechanism: none — this is an open investigation, not a design (see §8)

**Finding: the DISPOSE class has three oracles and no machine writer**
Evidence: `worktree-gc.sh:38-60` (A1/A2/A3), oracles at `:433`, `:448`, `:508`; `--warrant` writer at `:214-289` is human-invoked only; last sweep reported "1 reapable · **8 with NO ownership oracle at all** · 5 owned-but-not-terminal"; reso's own `scripts/worktree-gc.sh` contains **0** occurrences of `dispose`, so its 47 unlanded/clean worktrees are structurally unreachable
Cost now: 17 infra + 47 reso + 26 doc_classifier ≈ 90 worktrees ≈ 100 GB in a permanent-KEEP bucket
Re-architecture: `cc-reaper` writes a sha-pinned warrant when it observes a pane die with work unlanded and the tree clean-of-tracked-changes; A1's 72 h + A3's preservation proof + the live-team veto all still bind
Sizing: drains ~90 worktrees · effort M · **risk MEDIUM — this converts a human-only authorisation into a machine one; flag for an operator decision**
Existing mechanism: `worktree-gc.sh --warrant` (oracle 3) + `bin/cc-reaper:620-640` — connect two things that both already exist

**Finding: two janitors for nine repos; doc_classifier has none**
Evidence: `~/.reso/worktree-gc-run.sh:31` and `scripts/worktree-gc-infra-run.sh:22` each hardcode one repo; doc_classifier holds 62 worktrees / 41.5 GB of which **26 are landed AND clean** — reapable today by a janitor that does not exist
Cost now: 41.5 GB unreachable, plus 9 GB across five small repos
Re-architecture: iterate `CC_WTGC_INFRA_REPO` over a repo list (already a single seam)
Sizing: recovers ~15 GB at once · effort S · risk low (per-repo `CC_WTGC_TRUNK`; the wrapper lock already serialises)
Existing mechanism: `scripts/worktree-gc-infra-run.sh` — parameterise, do not fork

**Finding: 5,770 checkpoint/wip refs, generated by the worktree lifecycle, never expired**
Evidence: `git for-each-ref` → 5,180 `refs/checkpoints/*` + 590 `refs/wip/*` + 483 heads = 6,258 refs (reso 2,947); range 2026-07-11 → 2026-08-10; producers `hooks/teammate-checkpoint.sh`, `hooks/lead-crash-watchdog.sh`, `hooks/teammate-auto-shutdown.sh`; grep for delete/prune/expire over `worktree-gc.sh` + `cc-reaper` + `teammate-checkpoint.sh` → **nothing**; `maintenance.strategy` UNSET
Cost now: every checkpointed tree is pinned against `git gc` — 117 MB pack / 53,746 objects in a shell repo; 255 MB `.git` (reso 1.3 GB)
Re-architecture: age-expire both namespaces on the same wake sweep that reaps worktrees
Sizing: effort S · risk low (a checkpoint older than the abandon horizon has outlived its recovery purpose) · **owner: axis E (git-maint)** — logged here because the lifecycle creates it
Existing mechanism: `worktree-gc.sh --prune-branches` is the natural sibling arm

---

## 8. Adversarial pass — what I checked because a hostile reviewer would ask

1. **"You are attributing a memory bottleneck to something that holds no memory."** Correct, and I
   measured it rather than argue: 110 of 118 worktrees have zero open fds. I refuted my own axis's
   premise in §5 and re-stated the cost as disk + file-count + a 47-min background sweep + a multiplier
   on per-session cost. Anyone reading this axis as "reap worktrees, get RAM back" is misreading it.
2. **"Your per-arm numbers come from an `elif` chain, so they are priority-ordered."** Caught before
   quoting them — §2 evaluates every arm independently against all 118 and reports sole-blocked counts
   separately. The distinction changes the answer: the script's own log attributes 5 to `unlanded`
   where the independent count is 35.
3. **"`mdfind` returning 0 could mean the instrument is blind, not the subject clean."** Ran the
   positive control: 102,120 hits in `~/Development`, 110,531 in `~`. The instrument works; the
   `.worktrees` dot-prefix is the real reason, and it means my Spotlight hypothesis was wrong for 246
   of 274. Reported as a refutation.
4. **"Same-path is not same-content."** The 73-subset figure and the 38-zero-loss figure disagree
   precisely because 28 worktrees hold *superseded revisions* of the blender assets. Both are reported;
   only the 38 is a safety claim.
5. **Race I went looking for and found:** `scripts/handoff-fire.sh:6138` provisions a worktree, and
   `--recycle --worktree` relaunches the *same pane* into a fresh one. A SessionEnd-triggered reap
   could in principle race a recycle. It does not, because the wake only *actuates* a sweep whose
   `IDLE_MIN=30` floor (`:742`) and act-time `recheck_live()` (`:584-600`) both still bind — but the
   design must keep the wake as an actuator and never let it carry a "reap this path" argument.
6. **Orphan directories:** looked for dirs on disk with no git record under `.worktrees` — found 9, all
   empty, 0 GB. Non-finding, reported so nobody re-runs it.

## 9. Blockers and uncertainties (named, not smoothed)

- **The staging producer is unidentified.** Three plausible candidates read and eliminated. Until it is
  named, E4 treats a symptom that can re-emit on the next binary-asset wave.
- **E5 is a safety-model change, not a bug fix.** Auto-writing dispose warrants moves an authorisation
  from human to machine. Three gates survive it (A1 72 h, A3 preservation, live-team veto), but this is
  the one item I would not ship under the Follow-On Gate without an explicit operator call.
- **Why `runs = 0`** — bootstrap timing versus machine sleep is not distinguished. It does not change
  the remedy (a calendar-only trigger is the wrong trigger either way), but the *reason* the calendar
  arm is unreliable is unproven.
- **Not measured:** the 9 worktrees in the five small repos (disk unmeasured); reso's and
  doc_classifier's `du` are single-pass and include `node_modules`, so they are wall-clock disk, not
  unique disk — APFS may share clones.
- **Counts are live and moving.** claude-infrastructure went 118 → 120 during this audit. Re-derive
  before acting; do not quote these numbers as a baseline later (`published-figure-decays`).

---
---

# ADDENDUM — composed with row 11 after the lead's steer (2026-08-10 ~01:30)

**HAZARD-rule compliance** (`docs/plans/WORKTREE_MANAGEMENT_V2.md:33-42`). No invocation of
`scripts/worktree-gc.sh`, `git worktree remove`, `git worktree prune`, or `git branch -d/-D` was made
in either pass of this axis — including no `--dry-run` and no `--help`. `worktree-gc.sh` was read as
text via the Read tool only. Every number below comes from `git worktree list --porcelain`,
`git status`, `git cherry`, `git ls-tree`, `git hash-object`, `git for-each-ref`, `du`, `stat`, `ls`,
`lsof`, `launchctl print`. I also declined to create a throwaway worktree to settle the staging-producer
question (§8), because creating one mutates `.git/worktrees` in a live repo; the question stays open
rather than be answered by a mutation.

## §10 — TODAY's population, re-run with the doc's own methods

| # | Constant | **2026-08-10** | doc (2026-07-30) | Δ |
|---|---|---:|---:|---|
| C20 | registered worktrees of `claude-infrastructure` | **122** | 117 (118 mid-session) | **+5** |
| C21 | directories under `~/Development/.worktrees` | **253** | 199 | **+54** |
| C25 | prunable admin entries | **0** | 0 | — |
| C7 | local branches | **491** | 1,029 | **−538** |
| C1 | `du -sk ~/Development/.worktrees/*` | **186.5 GiB** / 253 dirs | 116.5 GiB / 198 dirs | **+60%** |
| C2 | volume capacity | 7.27 TiB | 7.28 TiB | — |
| C3 | volume free | 4.90 TiB (33% used) | 5.00 TiB (32% used) | — |
| C4 | worktrees as share of volume | **2.50%** | 1.56% | +0.94 pt |
| C5 | free ÷ worktree footprint | **26.3×** | 43.9× | **−40%** |

**Three denominators, all valid, none interchangeable** (memory: `positive-control-the-denominator`,
and the doc's own §1.4 correction). The steer's "558→252" is **C21, directories under `.worktrees`**
— today **253**. My §1 table's 274 was **fleet-wide git-registered linked worktrees across 9 repos**,
measured 00:25 and already stale (infra alone went 118 → 120 → **122** across this session's 90
minutes). C20, C21 and the fleet count answer different questions; label which one before quoting any
of them.

**§1.1's verdict survives; its margin does not.** Disk is still falsified as the binding constraint —
2.50% of the volume, 26.3× headroom. But the footprint grew **60% in 11 days** and the headroom ratio
**fell 40%**. A "killed" cell with a halving margin is a cell with a shelf life, and nothing on this
box is measuring the trend. That is a *new* fact, not a challenge to §1.1: **report the derivative, not
just the level** (memory: `published-figure-decays`).

**C7 halved** because the hand-fired 2026-08-09 22:15 sweep passed `--prune-branches` and deleted 389
landed, worktree-less branches (`~/.claude/logs/worktree-gc-infra.log`, verdict line
`removed=319 disposed=0 kept=108 branches=389 refusals=46`). That is the janitor working exactly as
designed — the one time it ran.

## §11 — Line-number reconciliation: the doc's citations vs the file on trunk today

`scripts/worktree-gc.sh` has grown to **866 lines** since the doc was written; **every §2/§3 citation
has drifted**. Attempt #3 reading `:488` will land somewhere unrelated. Mapping:

| Doc cites | Meaning | **Today** | Still true? |
|---|---|---|---|
| `:488` | the content gate (`status --porcelain`) | **`:726`** | yes |
| `:229-243` | `landed()` patch-equivalence | **`:374-379`** | yes |
| `:426` | A3 durable-ref proof | **`:663`** (`dispose_record`) | yes |
| `:371-377`, `:611-613` | `verify_preserved`, exit 4 | **`:602-608`**, **`:861-864`** | yes |
| `:449`, `:544`, `:585` | never `--force`, never `-D` | **`:687`**, **`:788`**, **`:829`** | yes |
| `:103` | `--prune` is a no-op alias (F-10) | **`:154`** | **yes — unchanged** |
| `:95-100` | no env kill switch (F-11 / AC-7) | **`:128-187`** | **yes — 16 `CC_WTGC_*` seams, none a disable** |
| `:504`, `:513` | unvalidated `IDLE_MIN`/`ABANDON_HOURS` | **`:742`**, **`:751`** | yes |
| `:170` vs `:174` | mutex self-staleness at 60 min (F-9) | **`:319-321`** | yes — **and now measured: the sweep took 47 min 32 s, inside a 60 min window. F-9 is one slow sweep from firing** |
| `:468-472` vs `:484` | prune runs before the exclude loop (F-12) | **`:705-711`** vs **`:722`** | yes |
| `:586` | `--prune-branches` | **`:809-837`** | yes |
| `:13-15`, `:223` | cross-repo scoping "already correct" | **`:13-15`**, **`:368`** | yes |
| `:199-206` / `:190-195` | oracle existence vs function (F-4) | **`:344-347`** / **`:335-339`** | yes |
| `:213`, `:226`, `:361` | exact-match cwd comparisons (F-6) | **`:358`**, **`:371`**, **`:589-595`** | yes |

**Newly present since the doc** (not in §3's table because it did not exist): the entire **ORACLE 3 /
dispose-warrant** subsystem (`:62-86` header, writer `:214-289`, reader `:508-543`) landed
2026-07-30 per its own header (backlog `d9fd066ebd28`). §3/§4 should not be read as covering it.

## §12 — Corrections to inherited claims (each measured by text, today)

| Claim (steer / doc) | Measured | Verdict |
|---|---|---|
| `scripts/worktree-pool.sh` is a phantom, **never existed in history** | `git ls-tree origin/main` → **0** in claude-infrastructure; **absent** on disk | **CONFIRMED for this repo** |
| …therefore the 15 references are dead | **PRESENT** at `~/Development/reso-management-app/scripts/worktree-pool.sh` (it is what `touch`es reso's GC wake at `:235`,`:249`) | **⚠️ DO NOT "clean up" the references.** `hooks/worktree-setup.sh:154` computes `POOL_SH="$REPO/scripts/worktree-pool.sh"` from the **target** repo — correctly true for reso, correctly false for infra. A per-repo conditional, not a broken gate. Deleting the refs breaks reso's warm pool (memory: `sibling-auditors-must-share-the-state-model`) |
| "a permanently-false gate at `handoff-fire.sh:5508`" | **`:5508` is the `CLOUD=1` branch resolving `lib/cloud-create.sh`** — unrelated to worktrees | **line pointer wrong.** The real pool gate is **`handoff-fire.sh:6074-6079`** (`POOL="$REPO/scripts/worktree-pool.sh"` + "POOL OWNERSHIP GATE"), and it is `$REPO`-relative, so same verdict as the row above. Executable refs are exactly **3** (`handoff-fire.sh`, `hooks/worktree-setup.sh`, `bin/cc-wave-plan:579` — a comment); the other 15 are docs and tests |
| `scripts/new-worktree.sh` never existed on any ref (F-13, R-6) | `git ls-tree origin/main` → **blob present**; on disk, header dated **2026-08-05** explaining it was added because `~/.zshrc`'s always-isolate gate required it | **DECAYED — F-13 and R-6 are now FALSE for this file.** Anyone executing R-6 ("correct the cell, don't build the phantom") would be acting on an 11-day-old premise. §7.2's "what DECAYED" list needs this row |
| `scripts/branch-reaper.sh` on trunk but NOT SCHEDULED | trunk blob present; **0** plists reference it, **0** launchctl labels match | **CONFIRMED.** And note the inversion: it defaults to **dry-run** (`:37`), deletes only under `--confirm` (`:38`), and ships `--restore <manifest>` (`:40`) — the *safest* destructive tool on the box is the one nobody scheduled |
| 394 branches unmerged | **285 of 491** carry ≥1 patch not on trunk, by `git cherry` content | **CORRECTED.** 394 is an ancestry/count-style figure; the doc's own C13/C14 shows ancestry over-counts patch-equivalence (1,974 of 2,773 `git cherry` rows were `-`, i.e. already on trunk by content). Use 285 — it is the number the doctrine asks for |
| 116.5 GiB worktree footprint | **186.5 GiB** today, same method | **STALE by 60%.** Verdict unchanged (§10), margin halved |

## §13 — The staleness oracle: why there is no staleness gate, stated as a mechanism

The steer's "no staleness gate anywhere in the file" is right, and the mechanism is sharper than
absence: **there IS an age gate; the dirty arm makes it unreachable.**

`process_record()` is one `if/elif` chain (`:722-732`) whose arms, in order, are: excluded → dir-gone →
locked → `.teammate-busy` → **dirty (`:726`)** → op-in-progress → live-cwd → registry-live → lsof-open →
detached. Only the terminal `else` (`:733`) computes the branch tip (`:735`) and the age (`:741`), and
only from inside that `else` can control reach the 72 h abandon horizon (`:751`) or `dispose_record`
(`:762`).

**Consequence, exact:** a dirty worktree never evaluates its own age, never enters the DISPOSE class,
and can never be reaped by any code path in this file — at any age, forever. Measured: **87 of 118 are
dirty and 71 are blocked by that arm alone**, so ~60% of the population is immortal by construction,
not by policy. The same structure gives the doc's F-7 its bite: `git status` failing reads as clean and
falls *through* the gate, while `git status` succeeding-with-output pins the tree *before* the gate —
the arm is load-bearing in both directions and has no third state.

**The oracle to add — content-based, `git cherry`, never a count.** A worktree's dirt is *material*
only if it contains a blob that is not reachable from the trunk. Formally, for each path P in
`git status --porcelain` (which the repo already extends with `--ignored`, AC-1 MET):

> `material(P) ≡ git hash-object <P> ∉ { git ls-tree -r $TRUNK }`
> `stale(WT) ≡ landed(branch) ∧ ¬∃P. material(P) ∧ age(tip) > floor`

- `landed()` stays exactly as-is (`:374-379`, `git cherry`, patch-equivalence) — §4's R-3 is right that
  the commit-preservation logic is correct and hard-won and must not be rewritten.
- The dirty arm at `:726` changes from `dirty ⇒ KEEP` to `material-dirty ⇒ KEEP`, which moves the age
  computation at `:735-741` **onto the reachable path** for the immaterial majority. That is the whole
  change: one predicate, and staleness becomes evaluable.
- **Measured yield: 38 of the 87 dirty worktrees have NO material path at all** — every dirty blob is
  already on `origin/main`. Removing them cannot lose a byte.
- **This does not weaken F-1 / AC-2 — it strengthens them.** §2's finding is that both nets are blind
  to gitignored content; the material test is *content-reachability*, so a gitignored `.env` or a paid
  generated asset is material by construction (its blob is on no tree) and pins the worktree. Where
  §2 asked the gate to "name what it would destroy", this asks it to *prove there is nothing to name*.
  It sits on the KEEP side of the contested AC-2 adjudication (§7.3) rather than re-opening it.
- **Bounds it must carry:** the trunk ref must resolve or the whole test is vacuous — the F-3 failure
  mode exactly. `material()` must return **UNKNOWN, never false**, when `git ls-tree $TRUNK` fails, and
  UNKNOWN ⇒ KEEP. Same for a non-zero rc from `git status` (F-7) and from `hash-object`.

## §14 — Kill-switch coverage: AC-7 is scoped too narrowly, and points at the wrong actor

Audited by text across every destructive worktree actor on the box:

| Actor | Scheduled? | Destructive verb | Kill switch |
|---|---|---|---|
| `scripts/worktree-gc.sh` | only via wrappers | `worktree remove` (never `--force`), `branch -d` (never `-D`) | **NONE** — 16 `CC_WTGC_*` seams, not one a disable (`:128-187`). Confirms F-11 / AC-7 |
| `scripts/worktree-gc-infra-run.sh` | launchd (`runs = 0`) | wraps the above | ✅ file flag, `:28` `worktree-gc-infra.disabled` |
| `~/.reso/worktree-gc-run.sh` | launchd, **live** | wraps reso's older copy | ✅ file flag, `:38` (2 refs) |
| `hooks/teammate-auto-shutdown.sh` | hook | **`worktree remove --force`** (`:1237`) | ✅ `TEAMMATE_SHUTDOWN_DISABLED=1`, gated at `:58` — **before** the removal |
| **`bin/cc-reaper`** | **launchd, LOADED (`com.chrisren.cc-reaper`, pid 9092)** | **`worktree remove --force`** (`:635`) | 🚨 **NONE.** Its only `_DISABLE` hits are `CC_CLASSIFY_INTERACTIVE_HOLD_DISABLE` (`:42`, `:1073`) — an unrelated interactive-hold feature |

**Two conclusions AC-7 as written does not reach:**

1. **The switch is missing at the only layer all paths share.** Both *scheduled* callers of
   `worktree-gc.sh` are covered by file flags, so the uncovered path is a **direct human invocation** —
   which `hooks/git-worktree-guard.sh` advertises to the operator three times in its own refusal text
   (`:6`, `:40`, `:57`: *"reap it with `bash scripts/worktree-gc.sh --prune`"*). A switch on the
   wrapper cannot stop the invocation the tooling tells the operator to type. `CC_WTGC_DISABLE` in
   `worktree-gc.sh` is therefore correct **and** should be read by the wrappers too, so one variable
   covers every path (the wrapper flags stay — belt and braces on a destructive surface).
2. **AC-7 names the wrong actor as the risk.** `worktree-gc.sh` is the *careful* one: no `--force`, no
   `-D`, git's refusal deliberately retained as a second gate (§2). The actor that is **scheduled AND
   passes `--force`** — the exact flag `worktree-gc.sh` refuses on principle — is **`cc-reaper`**, and
   it has no switch at all. Its own untracked guard (`:632`) is real and good, but it is one gate, in
   one script, with no way to stop it fleet-wide. **Rescope AC-7: `CC_WTGC_DISABLE` for the janitor,
   `CC_REAPER_DISABLE` for the reaper, both honoured before any mutation, both asserted in the suite.**

Also unchanged and worth re-flagging with today's measurement: **F-10 is live at `:154`** — `--prune`
is still `: ;`, a no-op alias for the fully destructive default, and it is still the exact string the
guard hook tells the operator to run.

## §15 — Event edges, revised to compose with row 11

§6's table stands. Three amendments from this pass:

- **E4 is now specified as §13's `material()` predicate**, not "content-free" hand-waving, and it is
  the *first* thing to ship: it is what makes staleness evaluable at all, and every other edge is an
  actuator for a sweep that currently cannot reap 60% of its population.
- **E1's actuator must not carry a target.** The wake file is a signal, never an argument — the sweep
  re-derives its own candidates and re-checks liveness at act time (`:584-600`). This keeps the
  SessionEnd edge from racing `handoff-fire.sh --recycle --worktree`, which provisions at `:6138`.
- **A new edge, E9 — the branch side.** §1.3 is the row's central structural fact: **96.4% of unlanded
  commits have no worktree**, so the durable carrier is the branch ref. `scripts/branch-reaper.sh` is
  on trunk, dry-run by default, `--restore`-capable, and **not scheduled**. Wiring it to the same wake
  file is the highest safety-to-effort edge available — but per §1.3 and F-2 it must apply the same
  content proof (`git cherry`, patch-equivalence) that `landed()` already implements, and per the
  measurement above the population it may touch is **206 of 491** branches (491 total − 285 carrying an
  unlanded patch), not 394.

## §16 — What this addendum does NOT settle

- **The staging producer** (§8) — still unattributed, and I declined the throwaway-worktree experiment
  that would settle it, under the HAZARD rule's spirit (it mutates `.git/worktrees` in a live repo).
  The right venue is the doc's own §1.6 pattern: a throwaway repo under the session scratchpad.
- **Whether `worktree-gc.sh`'s 47 min 32 s sweep can trip F-9's 60-minute mutex-staleness window.**
  47:32 was measured on 427 worktrees; the population is now 122 for this repo but the sweep is
  fleet-shared. One slower sweep and a concurrent pass breaks a live lock. Not tested — untestable
  without pointing the janitor at real worktrees, which the HAZARD rule forbids.
- **AC-4 / AC-5 / AC-6** remain unproven; I found no evidence for an unresolvable-trunk verdict token
  or a degraded-oracle refusal, which matches §7.4's read. §13's UNKNOWN-never-false bound is the same
  shape as AC-4 and should be built once, for both.
