# FR-12 — Workspace & Git-Concurrency: what is FRONTIER-HARD

Axis 12 of 13, frontier-discovery wave, 2026-07-20. READ-ONLY (no git mutations, no lands,
no worktree create/remove). Delta-mandate vs `desk-audit-2026-07-18/p09-ship-land.md` +
`p10-substrate.md` + landing-safety memory + `git log --since=2026-07-18` (144 commits).

**Headline:** the landing rail is now *solved engineering* — every P9 task row (T-P9-1..8)
shipped and is verifiable in code. What remains frontier-hard has moved one layer down, to
the **deploy model**: the machine-wide live layer is a bag of 152 per-file symlinks pointing
at a shared checkout's *working tree*, so "what version is live" has no answer. Both failure
directions are live simultaneously **right now** — 6 landed commits undeployed, and 1
uncommitted edit that has silently disabled a hook machine-wide.

---

## 1. Concurrency model as-of-today (file:line)

### 1.1 Topology (measured, not assumed)

| Fact | Evidence |
|---|---|
| 35 registered worktrees of this repo; 25 under `/private/tmp/wt-*`, 10 under `~/Development/.worktrees/` | `git worktree list` |
| 2 `prunable` (gitdir points to non-existent location) | `git worktree list --porcelain` → `wt-ccteardown`, `wt-comms-safety`; both branches have 0 unlanded → no loss this time |
| **13 registered sessions cwd'd in the SHARED checkout** (22 claude procs incl. children) | `cc-sessions --json`; `lsof -d cwd` |
| 176 local branches, **115 of them `ship/backup-*`** | `git for-each-ref refs/heads/` |
| `wt-pool-1..10` + `wt-cc-*` are **reso-management-app**, NOT this repo | `.git` file → `gitdir: …/reso-management-app/.git/worktrees/…` |
| git 2.54.0; `rerere.enabled=true` globally | `git --version`; `git config --global` |

The brief's premise that this repo runs a worktree *pool* is false. `scripts/worktree-pool.sh`
**does not exist in this repo, on any branch, in any commit** (`git log --all --diff-filter=A`
empty; per-branch `ls-tree` sweep empty). `scripts/handoff-fire.sh:1382-1392` references it, so
`POOL_ELIGIBLE` is permanently 0 and the pool-claim path is **unreachable dead code**. Every
infra worktree takes the cold path (`handoff-fire.sh:1394-1398`) or `hooks/worktree-setup.sh:76-82`
("Generic repo" fallthrough — plain `git worktree add`, no provisioning, **no reaper**).
`scripts/worktree-gc.sh` is still absent here (G-P9-8, open since 07-18) though
`hooks/git-worktree-guard.sh:40,57` still tells operators to run it.

### 1.2 Landing rail — what actually closed since 07-18

All ten P9 requirements are now **code, not prose**:

- `scripts/land-lock.sh:42-48` — mutex keyed on `--git-common-dir`, stripping `/worktrees/<n>`
  and `/.git`. G-P9-1 **closed**; two worktrees of one repo now collide on one mutex.
- Reap rule `land-lock.sh:88-107` — a **live** holder pid is never reaped even past TTL
  (deliberate divergence from reso; a wedged wait is cheaper than a dropped commit).
- `scripts/ship-land.sh` — the whole pipeline as one fail-closed script: shared-checkout
  refusal (`:302-316`, exit 4), dirty-tree refusal (`:319-323`), escalation-scan → decision
  packet PARK (`:338-348`, exit 3), lock → last-moment fetch → rebase → gate → push →
  content-verify → bounded auto-retry + `rebase --abort` rollback (`:222-265`) → sweep →
  self-attesting `land.log` (`:104-110`).
- `scripts/land-verify.sh:52-74` — per-path `ls-tree`-present **and** `git diff` empty, with
  correct deletion semantics. This is a *stronger* check than stranded-sweep and does close
  G-P9-7 **for the lander's own paths**.
- `hooks/ship-rail-push-allow.sh` — allow-only, anchored to exactly
  `git push origin HEAD:<safe-branch>`, force/compound/other-remote deferred.

**Empirical load** (`~/.claude/land.log`, 222 entries, 75 from `ship-land`):

| Metric | Value |
|---|---|
| Lands that **queued behind the lock** (`wait_s>0`) | 28 (~13%) |
| Max wait / max hold | 672s / **532s** |
| Exit codes | 0×190, gate-RED×13, rebase-conflict×9, PARK×3, 130×5, 127×1 |
| `verify` field | ok×72, n/a×3 — **content-verify is real and passing** |
| `sweep` field | **review×38 / clean×34** |

The lock is load-bearing (13% contention) and the gate holds it up to ~9 min — landing is a
serialized ~9-min-worst-case critical section across all N sessions.

### 1.3 Races that remain

| Race | Status | Evidence |
|---|---|---|
| Concurrent lands | **CLOSED** | correct `--git-common-dir` key; 28 observed queues |
| Sweep-vs-land | **CLOSED** | sweep runs inside the locked child (`ship-land.sh:268`) |
| Pool assignment | **N/A here** | no pool; reso's is correctly locked (below) |
| Index sharing | **OPEN, unenforced** | 13 sessions in one checkout; `p13-behavioral.md:41` R11 enforcement = "**NONE**" |
| Shared-checkout *writes* | **OPEN** | `ship-land` refuses to *land* there; nothing refuses to *write* there. Grep of `hooks/*.sh` for a shared-checkout write guard → only `task-quality-gate.sh` mentions the path |
| Unserialized `fetch` storm | **OPEN** | `handoff-fire.sh:1395` fetches per cold fire, `stranded-sweep.sh:52` fetches; **no single-flight stamp** (reso solved this exact `refs/remotes/origin/main.lock` storm at `worktree-pool.sh:82-101`) |
| Worktree teardown destroying uncommitted work | **OPEN, unhookable** | see FR-2 |

---

## 2. Ranked frontier rows

### FR-12-A — The live layer has no version identity (deploy model)

| | |
|---|---|
| **Problem** | `~/.claude` and `~/.claude-next` are real dirs containing **152 + 72 per-file symlinks** into `~/Development/claude-infrastructure`. The deploy pointer is therefore the shared checkout's *working tree*: live code = `{HEAD}` ∪ `{uncommitted edits}`, where HEAD lags `origin/main` by an unbounded amount. There is no generation, no manifest, no atomic switch, no rollback, and no way to ask "what is running?" |
| **Evidence** | `ls -l ~/.claude/hooks/*.sh` → symlinks into the checkout. **Under-deploy:** `git rev-list --count HEAD..origin/main` = **6**; of those, 6 live-symlinked targets are stale, incl. `scripts/lead-supervisor.sh` (a `KeepAlive` launchd daemon, `p10-substrate.md:12`) whose landed fix `7fe3468` ("recycled/hung pids no longer STALL?-escalate forever") is **not running**. **Over-deploy:** `hooks/teammate-auto-shutdown.sh` is dirty with `old mode 100755 / new mode 100644` — the exec bit is stripped. `settings.json:895` (both dirs) invokes it as a bare path `~/.claude/hooks/teammate-auto-shutdown.sh`, so the shell cannot exec it. `ls -lL` on both live paths confirms `-rw-r--r--`. Its own log (`:80` → `~/.claude/logs/teammate-lifecycle.log`) has been silent since Jul 19 16:50 while a sibling hook's `teammate-checkpoint.log` is live at Jul 20 00:52. **A 16-line uncommitted edit in one checkout disabled a reaper hook across every session and both config dirs, with zero signal.** |
| **Why default-tier insufficient** | The default tier reaches for a guard ("never leave the shared checkout off main" — literally G-P10-4's fix sketch). That guard would not have caught *any* of the above: we are on `main`, on a clean branch, and the breakage is (i) an uncommitted mode change and (ii) a 6-commit lag. The real problem is that a *development affordance* (edit-and-it's-instantly-live, which the whole desk loop depends on for iteration speed) and a *production property* (a versioned, atomically-switched, rollback-able runtime) are being served by the same mechanism. Resolving that tension without destroying the ergonomics is a design problem, not a check. |
| **Solution shape** | Split the two roles. A content-addressed release dir (`~/.claude/releases/<sha>/`) built from a **git object** (`git archive origin/main`), never a worktree; `~/.claude/{hooks,bin,scripts}` becomes ONE symlink to `~/.claude/current`; deploy = `ln -sfn releases/<sha> current.new && mv -Tf` (atomic rename, running processes keep their inode — exactly reso's `worktree-pool.sh:148,158` idiom, already proven in-house). Add a `DEV_OVERLAY` dir that shadows specific files for iteration, so the ergonomics survive explicitly instead of implicitly. Gate the switch on the same shellcheck+bats gate `ship-land.sh:126-156` already runs, plus an **exec-bit assertion** (nothing currently checks it: grep for a mode gate in `scripts/*.sh` returns only test fixtures). Emit a `live-generation` file so `cc-board`/`/wrap` can report deploy lag as a first-class state alongside 📦/✅. |
| **Confidence** | **HIGH** on the defect (two independent live instances, both measured). **MEDIUM** on the shape — the dev-overlay/atomic-release split is the obvious answer, but which files must stay hot-editable for the desk loop to remain usable is genuinely unknown and is the part worth frontier effort. |

### FR-12-B — Worktree teardown is unhookable; the guard is blind to the destroying path

| | |
|---|---|
| **Problem** | The harness owns worktree *removal* and will delete a worktree containing uncommitted work when an agent exits after a lock-contended `git commit`. Every defense this repo has sits on the wrong side of that boundary. |
| **Evidence** | `settings.json` registers **`WorktreeCreate` only** — the full hook-event list from both config dirs contains no `WorktreeRemove`. `hooks/git-worktree-guard.sh` is `PreToolUse(Bash)` (`:29-32` matches only `git worktree remove` / `git branch -d\|-D` command strings) → it can only see *Bash-tool* deletions, never the harness's internal teardown. The path is reachable here: `agents/schema-migration.md:5` declares `isolation: worktree`. Upstream [GH #55724](https://github.com/anthropics/claude-code/issues/55724) documents the exact chain — parallel agents → `.git` lock contention → commit fails → agent exits → **auto-cleanup destroys the work**; [GH #34645](https://github.com/anthropics/claude-code/issues/34645) documents the `config.lock` race that starts it. Aggravating local factor: nothing serializes worktree creation or fetches here (§1.3), and 2 worktrees are already `prunable`. |
| **Why default-tier insufficient** | Default-tier hardens what it can hook, and this repo already did that well (`git-worktree-guard.sh` is a good hook). The insight required is that the *guard is on the wrong side of the trust boundary* — the destroying actor is the harness, which does not route through PreToolUse. No amount of hook hardening closes it. The house rule "prefer manual `claude -w` over `isolation: worktree`" is a *behavioral* mitigation for a mechanism defect, and one agent definition already violates it. |
| **Solution shape** | Durability must be established **outside** the harness's lifecycle. Options worth panel effort: (a) a per-worktree pre-exit commit daemon (auto-`git stash create` → a `refs/wip/<worktree>` ref every N seconds; refs survive worktree deletion, unlike the working tree); (b) `git worktree lock` on every provisioned worktree at `worktree-setup.sh` time, released only by an explicit reaper — `lock` is respected by `git worktree remove` without `--force`; (c) serialize creation + retry-with-backoff on `config.lock` at the `WorktreeCreate` hook (the hook fires *before* the race, so it is the one place we do own). (b)+(c) are cheap and mostly settled; (a) is the interesting one because it makes work-loss structurally impossible rather than merely unlikely. |
| **Confidence** | **HIGH** that the guard is blind (hook-event list is dispositive). **MEDIUM** on live blast radius — I found no evidence of an actual destruction event in this repo; the 2 `prunable` worktrees lost nothing. |

### FR-12-C — Landing verification is decidable, unwired, and its noise is self-generated

| | |
|---|---|
| **Problem** | `stranded-sweep.sh --mine <sid>` was built (T-P9-4) precisely to convert the sweep's human-judgment REVIEW into a machine-decidable pass/fail — the audit called it "**the crux that makes G3 liftable**" (`p09:154`). **It is not wired.** And the sweep's false-positive population is manufactured by the lander itself. |
| **Evidence** | `ship-land.sh:268` — `sweep_out="$("$STRANDED_SWEEP" "$TRUNK" 2>&1)"`, no `--mine`, despite `CLAUDE_CODE_SESSION_ID` being in scope 160 lines earlier (`:108`). Same on `origin/main` (`git show origin/main:scripts/ship-land.sh` → identical line). Consequence: `land.log` shows **`sweep=review` 38 vs `clean` 34 — the undecidable state is the majority outcome**. Noise source: `ship-land.sh:357` mints `ship/backup-<sha>` on every land and **nothing prunes it** (`scripts/prune-backups.sh` has zero matches for `ship/backup` or `refs/heads`) → 115 backup branches. A read-only replay of the sweep's own predicate over them finds **20 stranded-class commits**, incl. `ship/backup-1a27b1d` carrying 57 unlanded. So: the safety mechanism feeds the noise source of the verification mechanism, which is why verification is undecidable, which is why landing cannot be fully autonomous. A closed loop. Divergence bonus: `scripts/desk-land.sh`'s own header advertises "ownership-decidable stranded-sweep" as part of ship-land's envelope — a property the code does not have. |
| **Why default-tier insufficient** | The wiring fix is one flag and is *not* frontier. The frontier question is the one the brief actually asks: **can landing-verification be structurally complete rather than disciplinary?** Today verification is a *scan over global mutable branch state* whose cost and false-positive rate grow monotonically with successful lands — an architecture that cannot converge. Structural completeness means the drop-detection is a property of the land transaction itself (e.g. every land writes an immutable `refs/landed/<sid>/<sha>` attestation carrying the verified path-set + trunk sha, so "was my content dropped" is answered by comparing two refs, in O(1), with no branch scan and no peer WIP in the sample space). `land-verify.sh` is already 90% of the primitive; it just isn't *recorded*. |
| **Solution shape** | (i) wire `--mine "${CLAUDE_CODE_SESSION_ID}"` at `:268` — trivial; (ii) prune `ship/backup-*` older than N days / already patch-equivalent on trunk, in `prune-backups.sh`; (iii) the frontier piece: promote `land-verify` from a transient check to a durable **landing attestation ref**, and re-verify attestations (not branches) on a schedule — verification becomes append-only and convergent. |
| **Confidence** | **HIGH** — every number here is measured from `land.log` and a read-only replay of the sweep predicate. |

### FR-12-D — "One worktree per writer" is a rule about the future, enforced by nothing

| | |
|---|---|
| **Problem** | The global rule keys on *write footprint* ("a session that writes a tracked plan/doc IS a writer"), but a session's write footprint is unknown at session start — which is the only moment a worktree can be cheaply assigned. So the rule is structurally unenforceable at decision time. Result: **13 registered sessions share one index**, and at least one has already written a tracked file without committing it (FR-12-A). |
| **Evidence** | `cc-sessions --json` → 13 with `cwd=~/Development/claude-infrastructure`. `p13-behavioral.md:41` R11 independently scores enforcement of the worktree-for-2+-writers *decision* as "**NONE**". `.claude/CLAUDE.md` documents the cost empirically: incident `dfacccd` (5 files) silently rebase-dropped by a sibling land, `rev-list origin/main..HEAD` reading 0 while the files were absent. |
| **Why default-tier insufficient** | The default answer is "always worktree" — which the global CLAUDE.md already rejected with specific, correct reasons (cold rebuild cost, gitignored-state divergence, `/tmp` litter, wrong-dir mistakes). The genuinely hard version is a **late-binding** model: start every session in the shared checkout read-only, and *promote* it to a worktree at the moment of first tracked write, transparently. That is the design worth frontier effort, and it is exactly what a warm pool (FR-12-E, settled) makes affordable — promotion costs a claim, not a build. |
| **Confidence** | **MEDIUM-HIGH** on the gap (measured + independently flagged in p13). **LOW-MEDIUM** on late-binding feasibility — mid-session cwd migration under a live harness is unproven and may simply not be possible without a session restart. That uncertainty is the frontier part. |

---

## 3. NOT-frontier → routing

| Item | Why not frontier | Route |
|---|---|---|
| **Worktree pool for this repo** | Already solved in-house. `reso-management-app/scripts/worktree-pool.sh` has a global `ensure` mutex + **per-slot `mkdir`-atomic claim locks with dead-holder self-heal** (`:63-80,222-234`), a **single-flight fetch stamp** collapsing the `refs/remotes/origin/main.lock` storm to ~1 fetch/15s (`:82-101`), atomic self-update via `mv` (`:148-160`), and unclaimed-slot drift self-heal (`:118-134`). Port it. | Agent Teams, ~1 teammate |
| **jj workspaces "when unblocked"** | **The premise is wrong — it is not blocked.** [GH #27466](https://github.com/anthropics/claude-code/issues/27466) is a narrow bug: jj colocated repos present as detached HEAD, and `git worktree add` needs `-b` there. Meanwhile ≥4 community plugins already delegate `--worktree` → `jj workspace` via **`WorktreeCreate`/`WorktreeRemove` hooks** — and this repo *already owns* `hooks/worktree-setup.sh` on that exact event. jj is an available, unexercised port, not a blocked one. | Timeboxed spike; re-file if the spike surfaces something |
| **Wire `--mine`** | One flag at `ship-land.sh:268` | backlog, P1 |
| **Prune `ship/backup-*`** | 115 refs, `prune-backups.sh` doesn't touch refs | backlog, P2 |
| **Single-flight fetch here** | Copy `worktree-pool.sh:82-101` | with the pool port |
| **`scripts/worktree-gc.sh` absent** | G-P9-8, open since 07-18; guard hook still points at it | backlog, P2 |
| **`worktree-setup.sh` timeout drift** | `.claude` 180s vs `.claude-next` 30s for the same hook — a cold non-pooled build can exceed 30s → silent worktree-create failure on next-account sessions. Instance of G-P10-7. | operator settings script |
| **Semantic-conflict merge design (brief q.c)** | **Near-empty for THIS repo.** No migrations, no tracked lockfiles; 5 tracked JSON files, 3 of which are fixtures/templates. The shared append-stores that matter (`~/.claude/autonomy/backlog.jsonl`, `idl.jsonl`, `decisions/*.json`) are **untracked runtime state** — never merged, so worktree isolation is irrelevant to them; their concurrency risk is concurrent-append, a different axis. reso is where the ordered-artifact class is real, and reso already mitigates it (`worktree-pool.sh:127-132` shasums `_journal.json` before/after and drops the local DB on drift). | de-prioritize for this axis; hand the append-store concurrency question to the telemetry axis |

---

## 4. Could-not-determine

- **Whether `teammate-auto-shutdown.sh` had work to do during its silence.** Firmly established: it is non-executable and invoked bare, so it *cannot* run now. Its log has been silent since Jul 19 16:50 while the exec bit was stripped at 23:51 — I did **not** establish that the silence before 23:51 was caused by the strip (per the "read the transcript before asserting WHY" rule, indirect signals show WHAT, not WHY). Needs a transcript read to attribute.
- **Actual write footprint of the 13 shared-checkout sessions.** Only one dirty tracked file is observable; the other 12 may be genuinely read-only (research/desk) and therefore rule-compliant. Determining this needs per-session transcript inspection.
- **Whether git 2.54 changed the `#34645` `config.lock` race profile.** The upstream reports predate this version; not re-tested here (and re-testing requires worktree creation, which the brief forbids).
- **Whether the 130-exit lands in `land.log` (5) are signal-kills mid-hold or the `land-lock.sh:124` `CODE=130` default leaking.** Flagged as an open question in `p09:210`; still open, still not load-bearing.
- **Not a leak (ruled out):** 34 `.git/worktrees/` admin dirs vs 35 `git worktree list` entries — the main worktree has no admin dir. Expected, not a discrepancy.

---

## 5. Adversarial self-pass

- *"You asserted a pool exists because the brief said so."* → Falsified it instead: `worktree-pool.sh` is absent from every branch and every commit here; the `wt-pool-*` dirs are **reso's**, proven by their `.git` gitdir pointers. The brief's map was wrong and the dead-code reference at `handoff-fire.sh:1382` is the residue.
- *"You claimed the lock works because the header says so."* → Read the key derivation (`:42-48`) **and** measured contention independently: 28 queued lands, max wait 672s. The 07-18 audit's own critique (bats overrides `LAND_LOCK_DIR`, so keying is untested) still stands — the keying is correct by inspection, not by test.
- *"Is jj actually blocked, or did you inherit that from the brief?"* → Checked upstream. Inherited and **wrong**; corrected in §3 with the actual bug scope and the existing hook-based workarounds.
- *"You only looked at races you were told about."* → Found two unlisted: the unserialized fetch storm (reso documented and fixed it; this repo has neither), and the `WorktreeRemove`-hook absence that makes FR-12-B unhookable.
- *"53% `review` — did you check whether `--mine` is wired before calling it a gap?"* → Checked both `HEAD` and `origin/main`. Unwired in both. Also found `desk-land.sh` claiming the property in prose.
- *"Semantic conflicts were a whole question and you de-prioritized them."* → Verified the tracked-file inventory first (5 JSON, mostly fixtures; no migrations; no tracked lockfiles) rather than assuming. The class is real for reso and near-empty here; saying so is the finding.
