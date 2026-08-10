# C — Prior art: queued / async / delegated landing machinery already in claude-infrastructure

Measured 2026-08-10 ~01:20 PT, read-only. Reference points: local `main` = `d52c3a94`;
`origin/main` = `37a87cd4` (2026-08-10 01:15). Everything below is content-verified against
`origin/main` via `git ls-tree`, never by commit count.

## Headline

**A delegated lander, a serialized multi-branch lander, a single-writer async daemon with a real
on-disk `queue` file, a bounded admission library, and a launchd-ticked work dispatcher ALL EXIST
and are LIVE.** What does **not** exist is a *land queue*: no store, no dir, no flag, no scheduler
that accepts "land this later" and drains it. The gap is one hop, not a subsystem.

Two repo documents pre-emptively rule on building one:
- `docs/plans/LAND_PIPELINE_V2.md:616-620` (`status: complete`) — **§8 Rejected alternatives**:
  *"Speculative merge-queue (Zuul/bors batching): solves throughput but keeps latency ≥ corpus-time
  (fails R1) and keeps N-corpora concurrency (fails the load reality). Post-land + revert dominates
  on a single box with a trusted-author fleet."*
- `docs/research/concurrency-census-2026-08-07.md:242-244,257-261` (landed `af78df7d`) —
  *"The overnight autonomy already exists and is starved, not missing… Building a new queue would
  be building the second one."* and a **"Do not rebuild what exists"** section naming
  `cc-backlog` / `cc-queue` / `cc-dispatch` as *"the sanctioned store, queue and dispatcher."*

## Inventory

| Artifact | What it does | Callers / consumers (name-verified) | Status | Last touched |
|---|---|---|---|---|
| `scripts/desk-land.sh` (196 L) | **The delegated lander.** Lands *another* worktree's branch on a session's behalf: resolves a live worktree for `--branch`, or mints a **throwaway** worktree off the branch tip (`:147-155`), fail-closed pre-checks (`:159-176`), then hands the actual land to `ship-land.sh` **verbatim exit code** (`:183-196`). Classifier-bypass is structural, not a trick (`:30-37`). Explicitly **SYNCHRONOUS by design** (`:39-46`) — the header argues *against* "fire a lander session": a fired lander must clear its own classifier, costs quota, and adds engagement/account/focus race modes. It says *"The desk may background the single `handoff-fire.sh land …` Bash call when it wants the land to be non-blocking."* | `scripts/handoff-fire.sh:4410-4412` (`if [ "${1:-}" = "land" ]` → `exec "$HF_DIR/desk-land.sh"`) · `scripts/cloud-reconcile.sh:78` (`LAND_BIN` default) · `tests/desk-land.bats` (18 tests) | **landed** `3fd9d7fe` (feat), `9f8475de`, `fa4fbcd6` (exit-code docs); blob `564aad07` on `origin/main`. **LIVE** (`~/.claude/scripts/desk-land.sh` → symlink into checkout) | 2026-07-26 06:50 |
| `scripts/cloud-reconcile.sh` (336 L) | **The serialized multi-branch lander.** Discovery + eligibility + **serialization**, landing nothing itself. Lists remote `claude/*` branches, classifies against the `cc-cloud` declaration store (`ELIGIBLE`/`LANDED`/`RETIRED`/`NO-DECL`, `:186-213`), fetches each to a local head (`:224-226`, deliberately non-forced), **orders smallest-diff-first** (`:311-313`), lands each via `desk-land.sh` (`:234-243`), and **continues past a per-branch failure** rather than stranding the queue behind one bad branch (`:324-329`). Landedness decided **BY CONTENT** (`ls-tree`, `:135-149`). Sensor failure ≠ empty (`exit 69`, `:51-53,246`). **DEFAULT-OFF: `--land`/`--all` refuse without `CONFIRM=1`** (`:260-261`). | `bin/cc-offload:74,504-522` (`cc-offload land` → `RECONCILE_BIN`) · `tests/cloud-reconcile.bats` | **landed** `f0fa1bc6` (2026-08-08 03:47); blob `47534c88` on `origin/main`. Branch `cloud-g6-reconcile` (`c8b2b446`) is ahead-by-1 but **file content is identical to main** (`git diff origin/main cloud-g6-reconcile -- scripts/cloud-reconcile.sh` = empty) ⇒ stale branch, not unlanded work. **LIVE** (symlink) | 2026-08-08 03:57 |
| `scripts/ship-land.sh` (2386 L) | The one sanctioned synchronous rail. Post-`LAND_PIPELINE_V2`: **corpus-free fast lane** — optimistic gate rounds *outside* the lock (`SHIP_LAND_GATE_ROUNDS`, default 3, `:22,118`), statics-only in-lock re-gate (`:38-42`), `IN_LAND_LOCK=1` structurally bans any suite inside the mutex (`:42,560-563,981`). Flags are **only** `--trunk`, `--dry-run` (`:5`) — **no `--queue`, `--defer`, `--async`, `--background`.** | `/ship` (`commands/ship.md`) · `desk-land.sh:175` · `postland-verify.sh:494` (auto-revert's **only** pusher) | landed; **LIVE** (symlink) | current |
| `scripts/land-lock.sh` | **Machine-wide landing serializer, repo-keyed** on the *shared* git dir (`--git-common-dir`, not `--show-toplevel` — so all worktrees of one repo collide on ONE mutex). pid+**lstart** liveness (a bare `kill -0` is fooled by pid recycling). `LAND_LOCK_WAIT` default 3600s, `LAND_LOCK_TTL` 1200s. One JSON line per land to `~/.claude/land.log` `{ts,repo,branch,wait_s,hold_s,exit,pid}`. Kill switch `LAND_SERIALIZE=off`. | ship-land (in-process); `stranded-sweep.sh:112` recommends it in its recovery recipe | landed; **LIVE** (symlink) | current |
| `scripts/postland-verify.sh` | **The single-writer async daemon, and the one existing on-disk queue.** launchd `com.claude.postland-verify`, `StartInterval` **300 s**, cmd `postland-verify.sh --run-if-needed`. Owns the full-suite verdict; mutex "shape copied from land-lock.sh" (`:695`); fresh disposable worktree per run; **auto-revert PUSHES a revert to origin/main on a single verdict** via `ship-land.sh` (`:494-515`) — i.e. an autonomous, daemon-driven writer to trunk already exists. | `ship-land.sh:2243-2255` writes `$HOME/.claude/autonomy/postland/queue` (one landed head) then detaches the verifier via `start_new_session=True`; launchd tick is the backstop | landed; **LIVE**; launchd job **loaded** (`launchctl list` → `com.claude.postland-verify`) | current |
| `~/.claude/autonomy/postland/queue` | **The only "queue" file in the landing path.** Single line = landed head. Read at 01:24 today: `018381c62daf5b511eb090e645a69eb5b200580b`. Producer = `ship-land.sh:2251`; consumer = `postland-verify.sh`. Not a work queue — a hand-off pointer. | ship-land ↔ postland-verify | live (untracked runtime state) | 2026-08-10 01:24 |
| `bin/cc-dispatch` (2028 L) | **The launchd-ticked work dispatcher** — the closest architectural prior art to a queued lander, and it is explicit that it is not one: *"It does NOT land work itself — the spawned session's lead lands via the existing ship-land rails"* (`:5-6`). Carries every primitive a land queue would need: **DECISION/ADMISSION split** (decision = pure read over the whole backlog every pass, costs no quota; admission = the only capacity-bound step), `free_slots = max(0, CEILING − live_workers)` with `live_workers` = the ledger's `claimed` fold (never a session count), **`CC_DISPATCH_CEILING` default 6**, **UNKNOWN ≠ 0 ≠ cliff** (unresolvable oracle admits AT MOST 1), **order = thrash-count ASCENDING then oldest** so a repeatedly-failing item sinks instead of starving the head, and a **`mkdir` SINGLETON pinned by `pid|lstart`** that gates ADMISSION ONLY — *"skip-the-ADMISSION, never queue: a queueing lock is how a pass that outruns its interval becomes five concurrent passes."* | launchd `com.claude.dispatcher`, `StartInterval` **300 s**, `CC_DISPATCH_PROJECT="claude-infrastructure"`, `exec $HOME/.claude/bin/cc-dispatch --once` | landed; **LIVE** (symlink); launchd job **loaded** (pid 74086) | current |
| `scripts/lib/capacity-admit.sh` (418 L) | **Bounded admission term** for the spawn paths `handoff-fire.sh:capacity_gate()` misses. The load-bearing design law it encodes: *"No gate on an actuation path may be unbounded. Every affirmative-permission predicate must carry a finite budget whose expiry converts the standing state into an EVENT."* After `CC_ADMIT_BUDGET` consecutive refusals the next evaluation **ADMITS** with `basis:"budget-expired"` and pages. Counter resets on any admit. | `scripts/handoff-fire.sh:3431-3437,3517-3578,3653` · `tests/capacity-admit-coverage.bats` (cases 26-27 pin the two literals) | **landed** `38e2513b` (2026-08-07) | 2026-08-07 |
| `scripts/stranded-sweep.sh` (134 L) | **REPORTS ONLY — lands nothing.** Detects commits stranded on *local* branches (content-based: `git cherry` `+`, not SHA-reachable, AND every changed path absent from trunk). Two modes: default review-not-fail (exit 1 = REVIEW; on a multi-session box exit 1 is the normal state) and `--mine <sid>` (machine-decidable own-drop, via `Session-Id:`/`Land-Session:` trailers). Output is **printed recovery recipes for a human** (`:108-113`). Structurally blind to remote-only branches — `:66` iterates `refs/heads/` only (this is why `cloud-reconcile.sh` exists; it says so at `:13-15`). | invoked inside ship-land's land flow (`sweep_out`/`sweep_field`, `ship-land.sh:~2235`); `--mine` is the T-P9-4 auto-land crux | landed; **LIVE** (symlink) | 2026-07-18 16:20 |
| `bin/cc-queue` (577 L) | ❗ **NOT a landing queue — a red herring by name.** It is the operator's blocked-agent **permission queue**: one row per agent, blocked first, read-only over four disk sources (beacon/telemetry/registry/transcript). `--attach` is its ONE action and it only moves the operator's focus. Three-state world (dir ABSENT = hook never ran = INERT ≠ empty). Measured 0.39 s for 1000 rows. | `hooks/cc-permission-beacon.sh` (producer) · operator | **landed**, last touched `71e96bcb` (2026-08-07 16:23); blob `25227145` on `origin/main`. Branch **`feat/cc-queue` is FULLY CONTAINED in `origin/main`** (`git merge-base --is-ancestor` ⇒ true) — the worktree `/Users/chrisren/Development/wt-cc-queue` @ `085b7017` (2026-07-31) is **stale, nothing unlanded there**. `docs/plans/TERMINAL_AGNOSTIC_L3_L4.md:145` records "P4 — the queue (T4) — ✅ DONE, landed on origin/main 2026-07-31" | 2026-08-07 16:28 |
| `bin/cc-reconcile` (310 L) | ❗ **NOT landing — session-REGISTRY anti-entropy.** Backfills/heals `cc-registry` rows for live panes so the reaper is never blind. Additive + stale-heal, never deletes a live-pid row. | `cc-reaper` self-check; `tests/proc-identity` | landed (`7a6a7fe8` latest) | 2026-07-26 12:39 |
| `scripts/lead-reconciler.sh` (215 L) | ❗ **NOT landing — teammate-liveness three-way roster reconciler** (harness tasks × cc-registry × disk telemetry); persistent pairwise divergence pages. | **NONE in a live path.** `tests/lead-reconciler.bats`; `tests/cc-fleet.bats:624-635` asserts it is *"staged OUT of the manifest"*. Plist exists **only** at `launchd/staged/com.claude.lead-reconciler.plist` — **not loaded** (`launchctl list` has no such label). `docs/research/desk-audit-2026-07-18/p05-supervision.md:24,98` — *"NOT RUNNING + NOT INVOKED"*, gap G-P5-3, still open. | **built + tested but DEAD in runtime** — single commit `2c2766ec` | 2026-07-15 08:31 |
| `bin/cc-offload` (614 L) / `bin/cc-cloud` (809 L) | The off-box execution arm: `cc-offload land [--all]` → `cloud-reconcile.sh`. Composition-only, owns no state, re-derives no verdict (`:19-29`). Its `say` verb reports **QUEUED, never delivered** — an explicitly-modelled queue-ack-vs-read-receipt distinction worth reusing. | operator; `handoff-fire.sh --cloud` for the `up` verb | landed; `bin/cc-cloud` last `3dcac1f3` (2026-08-09), `cc-offload` `d52c3a94` (2026-08-10 01:04, local main) | today |

## Ad-hoc prior art — the pattern hand-rolled twice, untracked, and never generalized

Both live in `~/.claude/autonomy/`, are **NOT in the repo** (`git log --all --diff-filter=A` finds
no add for either), and are one-off disposable scripts with a hard 4 h deadline:

- `deploy-when-green.sh` — polls `postland-verify.sh status` every 180 s for a `last-green` != a
  hardcoded `BASELINE=34e725d629ca`, then runs `deploy-live.sh` once. *"Wait for a verdict, then act."*
- `deferred-fire-deploy-lane.sh` — a fire was refused by `handoff-fire.sh`'s capacity gate at
  2026-08-07T00:06Z (load 92.35 / 10 cores = 9.23 vs a 2.0 ceiling); this loops on `vm.loadavg`,
  re-fires the SAME command when load/core ≤ 2.0, **never overrides the gate**, backs off 300 s on
  refusal, gives up loudly at 4 h.

**This is the strongest evidence for the lead's thesis**: the "defer the expensive act until the
machine is quiet, retry under the same gate, bound it, fail loudly" shape has been *needed and
hand-written at least twice* and has never become a tracked primitive. A queued lander is that
script, generalized — not a new subsystem.

## The already-filed items (do not re-file)

| id | status | why it matters |
|---|---|---|
| `e91937f897cc` | **open** | *"ship-land gates BEFORE taking the land-lock, so N concurrent landers each run the full ~1400-test suite in parallel and OOM/SIGTERM each other… Consider gating under a shared slot/semaphore, or a concurrency cap, so the expensive phase is serialized too."* Measured: 6 worktrees landing at once, 14 concurrent /Users/chrisren/.claude/bin/cc-bats suites, five deaths with **zero test failures** (Killed:9 / Terminated:15 / exit 143-144). ⚠ **ITS PREMISE IS STALE — verify before citing.** `LAND_PIPELINE_V2` (`status: complete`) inverted exactly this: the land lane now carries only O(diff) statics + a ≤120 s skippable smoke, `IN_LAND_LOCK=1` structurally bans suites in the mutex (`ship-land.sh:38-42,560-563`), and the full-suite claim moved to `postland-verify.sh`. The item's own `needs` is a thrash auto-block, not an investigation. |
| `35de32d78364` | blocked | *"SWEEP the 164 distinct stranded patches onto trunk"* — 164 distinct patch-ids across 36 branches, precondition-first then smallest-diff-first ordering. Plan: `docs/research/STRANDED_EXPOSURE_2026-07-26.md`. **This is a bulk-land sweep already designed and never executed**, blocked behind two unlanded preconditions (`a0718a5d78b3`, `f8e40b4c577d`). |
| `02ba4e52389a` | blocked | The canonical land-contention casualty: branch complete/clean/rebased, 8 atomic commits, shellcheck clean; `ship-land.sh` run 4× and SIGTERM-killed mid-gate every time. Its own remedy names the trigger a queue would automate: *"when the machine is quiet (`pgrep -f bats-exec-file` returns few/none), run ship-land.sh."* |
| `1b00d62958a6` | open | MASTER M2 — *"nothing fires until it is provably current, provably unclaimed, and lands in a provably fresh tree"*; chokepoint `bin/cc-premise` called from the `cc-backlog claim` guard. Overlaps any land-queue admission predicate. |
| `ce2bf742216d` | open (reso) | *"handoff fire queue re-fires a track whose branch was pruned after it landed — completion is keyed on fire exit code, not a landed sha."* The exact idempotency bug a land queue must not repeat: **key completion on a content-verified landed sha, never on an actuator's exit code.** |
| `4abcbbbbc997` | open (reso) | *"Retry the BSM land on a QUIET machine"* — a second manual instance of the deferred-land pattern. |

`cc-backlog` already models the whole lifecycle a land queue needs: `open → claimed → blocked →
open` with a **thrash counter** whose window resets at the latest `block`/`unblock` (`bin/cc-backlog:2328-2335`)
— it fixed the exact bug where *"unblock never survives cc-reaper"* (dispatcher starvation).
`:2425` is the auto-block message; **`blocked` requires a manual `cc-backlog unblock`** — there is
**no** auto-unblock sweeper anywhere in `bin/`, `scripts/`, `hooks/` (grep-verified; every hit is a
message telling a human to run it).

## Graveyard — designed but never landed

- `refs/heads/rescue/concurrency-census-2026-08-07` (`a914feff`, 2026-08-07) — **stale, not
  unlanded.** The doc IS on `origin/main` (`af78df7d`, blob `7750ef64`); branch diff for that file
  is empty.
- `refs/heads/cloud-g6-reconcile` (`c8b2b446`) — same: ahead-by-1 commit, **zero content delta** for
  `scripts/cloud-reconcile.sh`.
- `refs/heads/feat/cc-queue` (`085b7017`) — **fully contained in `origin/main`.**
- `launchd/staged/com.claude.lead-reconciler.plist` — the one genuine *built-but-never-scheduled*
  artifact in this space (see table). Precedent: a plist can sit in `launchd/staged/` indefinitely,
  and the fleet coverage lint globs `launchd/*.plist` so it **cannot** catch it (this exact blindness
  kept `com.claude.relogin` unscheduled and unreported from 2026-07-26 — recorded at
  `docs/plans/GROUND_UP_REBUILD_MAP.md` row 7).
- No branch, commit, or file anywhere named `land-queue` / `land_queue` / `pending-land` /
  `landq` (grep over the whole tree, `git log --all --diff-filter=A` over `bin|scripts|hooks`).
  The complete added-file set in this space is: `cc-dispatch`, `cc-queue`, `cc-reconcile`,
  `cloud-reconcile.sh`, `desk-land.sh`, `land-lock.sh`, `land-verify.sh`, `lead-reconciler.sh`,
  `postland-verify.sh`, `ship-land.sh`, `stranded-sweep.sh`, `autonomy-sweep.sh`,
  `dispatch-acceptance.sh`, `dispatch-projects.conf`.

## Adversarial self-pass — three things I nearly got wrong

1. **"`bin/cc-queue` is the land queue."** False, and the name is the whole trap. It is a
   permission-block board. Read `bin/cc-queue:1-25`. Anyone skimming the file list will assume
   otherwise.
2. **"`desk-land.sh` is a fired async lander."** False. It is delegated but **synchronous on
   purpose**, and `:39-46` argues the async form is *worse* (a fired lander re-enters the very
   classifier gate the design exists to bypass; plus quota, engagement race, account routing,
   focus-steal, cold-fire autosubmit). Any async design must answer that paragraph, not ignore it.
   The sanctioned async escape it *does* name is one line: background the single
   `handoff-fire.sh land …` Bash call.
3. **"Nothing autonomous writes to trunk today."** False — `postland-verify.sh`'s auto-revert
   pushes a revert to `origin/main` on a **single** verdict, unattended, on a 300 s launchd tick
   (`:494-515`, `LAND_PIPELINE_V2.md:672`). A queued lander is therefore not a new trust boundary;
   it is a second writer through the same rail. It has also **mis-fired**: `postland-verify.sh:1555`
   records auto_revert landing a revert of `e80c85aa` (a correct, unrelated `cc-queue` fix) as
   `f323b427`, restoring a permanent red — and `12549d8b` is the re-land. Design the queue's
   idempotency against that incident.

## Uncertainties / freshness caveats (re-check at synthesis)

- **`scripts/handoff-fire.sh` is being edited right now.** Worktree
  `.worktrees/close-integrity` (branch `fix/close-integrity`, tip **`412e1159`, 2026-08-10 01:20:52**)
  has `scripts/handoff-fire.sh` in its `origin/main...HEAD` diff. The `land` dispatch I cite at
  `:4410-4412` is on `main`/`d52c3a94`; re-verify the line numbers after that branch lands.
  (`.worktrees/kitty-parity` @ `344888a6` is 2026-08-01 and touches the frontapp transport, not
  landing.)
- Local `main` (`d52c3a94`) is **behind** `origin/main` (`37a87cd4`); every "landed" claim above was
  taken against `origin/main` by `ls-tree`/`merge-base`, not against the working tree.
- The backlog counts in `concurrency-census-2026-08-07.md` §8 (323 blocked / 8 open / 205 citing
  land-failure) were measured 2026-08-07. **Today's live read is 342 total items** — the census
  figures are 3 days old; re-derive rather than quote (this repo's own rule: a published figure
  decays with its source).
- I did not price `cc-dispatch`'s IDL journal for how often a dispatched worker actually fails to
  land vs. fails to spawn; `bin/cc-backlog:2425` conflates both into one thrash message
  (*"spawn-fail / land-conflict rebase-exit-5"*), so the 205-item "cites land-failure" figure is an
  **upper bound** on land-caused blocks, not a measurement of them. Naming this rather than
  resolving it — it needs an IDL fold the lead may want as its own axis.
