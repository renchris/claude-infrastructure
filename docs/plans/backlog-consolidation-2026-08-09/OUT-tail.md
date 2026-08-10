# tail (C-misc + C-machine + C-docs + P-other) — triage vs origin/main @ 51bdb524

Measured 2026-08-09. `origin/main = 51bdb524` (local checkout `c2ccbeb8` is an ancestor — every
`git show` below is against `origin/main`, not the working tree). Live reads used: `launchctl
print-disabled gui/501`, `~/.claude/autonomy/pending-activation/`, `~/.claude*/.claude.json`
GrowthBook caches, `~/Development/.worktrees/`, and the three foreign repos' `next.config` +
installed `node_modules/next/dist/server/config-schema.js`. No suite was run.

## Summary

counts: PRUNE 2 / UPDATE 4 / KEEP 16 / MERGE 1   (= 23)

Three findings outrank the rest and are argued in the master items:

1. **The panic ignition is UNMITIGATED on every Next app on this box that can carry the fix.** All
   three apps with a schema that accepts `experimental.turbopackPluginRuntimeStrategy:
   'workerThreads'` — `agent-build-hackathon`, `reso-qa-runner`, `reso-management-app` — have it
   **NOT SET**, and none opts out of turbopack via `--webpack`. The last-ditch actuator
   (`com.claude.compressor-sentinel`, pid 48326) is armed, but it freezes the horde at the edge of
   death; nothing stops the horde being minted. 4 panics in a week, the most recent today.
2. **Five of my twelve misc items cannot drain for one mechanical reason, and it is not per-item.**
   All five carry `persistent thrash — the worker cannot land`, and all five still own a stale
   worktree under `~/Development/.worktrees/` sitting **50–853 commits behind trunk** (two dirty).
   `69e6519a` (2026-08-08) derives the generator exactly; nothing since has fixed it. There are
   **553** worktrees on disk.
3. **The native read-before-write guard is now OFF on all four accounts, not one** — the inversion
   of item `29d1eba690a3`, and its remedy has never been committed.

## Verdicts

`01edea637633` | KEEP | `docs/plans/CONDITION_LEASE.md` on origin/main still carries frontmatter `status: open`; last touched `d4390e01`. Plan-open driver is valid.
`96fe7b1687a0` | KEEP | Genuinely operator-only (GUI consent: install the Claude GitHub App on `github.com/renchris/claude-infrastructure` via claude.ai/code). Its `needs` is the freshest text in my slice (`2026-08-09T23:34Z`) and matches `61799d76` §11.4 landed today. Nothing agent-side remains.
`d7c413fe823f` | KEEP | `docs/plans/SESSION_LIFECYCLE_V2.md` live on trunk, three commits since the item (`019469bc`, `5d442791`, `682cf32e`). Its `needs` (thrash) is a rail artifact, not the work — see M-tail-2; stale worktree `wt-d7c413fe823f` is **853 behind trunk, 4 files dirty**.
`e09a075539f5` | KEEP | `bin/cc-url-open` still on trunk; only post-item commit is `e7f96efa` (kitty control socket), unrelated to the Dia CDP consent re-pop. Blocker is an operator call on the persistent-CDP-client security envelope vs the dia-agent no-daemonization rule — unchanged.
`bd3a486fa469` | KEEP | `bin/cc-1p-events` present on trunk with `cmd_activation` intact (`:191`, `:328`); the redirect is still un-applied and still self-expiring (~6 h GrowthBook TTL). Diverting this machine's first-party telemetry remains a value call.
`eb8911ec044f` | UPDATE | Half-verified, half-superseded. `~/.claude/autonomy/websetup/next2.linked` **exists** (marker premise TRUE). But the *symptom* it infers from — "falls back to bundle mode" — was re-attributed on 2026-08-09 in `CLOUD_OBSERVABILITY.md` §11.4 (`61799d76`): the create demonstrably took the bundle path because the **GitHub App is not installed on the repo**, and the App install "removes the bundle from the create path entirely". Item should now read: *do NOT re-drive `cloud-websetup-drive.sh --account next2 --force` until `96fe7b1687a0` (App install) is done — the re-link is probably a no-op remedy for a repo-side cause.*
`29d1eba690a3` | UPDATE | **Premise inverted, and it got worse.** (a) The wedge is gone — `~/Development/.worktrees/wt-29d1eba690a3` no longer exists and is not in `git worktree list`, so "live process cwd … (1 proc)" is refuted. (b) The divergence is **no longer next2-only**: `tengu_velvet_mallet_opus_5` reads **true** in `.claude-next` (next), `.claude-secondary` (next2), `.claude-tertiary` (next3) and `.claude-quaternary` (next4) today — the Aug-5 table in the remedy script recorded `next=false next2=TRUE next3=false next4=false`. Default model is `claude-opus-5`, so the guard is skipped on every account, including the one that wrote this report. (c) The remedy **exists and has never landed**: `hooks/lib/read-before-write-parity.sh` (11,259 B, mtime Aug 5) is UNTRACKED in the shared checkout — `git ls-tree origin/main` returns nothing for it, and the only refs are `checkpoint:` commits. Retitle to "the read-before-write guard is OFF fleet-wide; land the parity shim."
`b4f93c9fa73c` | KEEP | No second green producer exists. `git ls-tree origin/main -r .github/` returns exactly one file, `.github/workflows/diagrams.yml` — no CI runs any test subset off-box. The `DEPLOY_LANE_GROUND_UP.md` revisit-trigger the item cites is still the live rationale.
`6053ebd74b52` | PRUNE | Premise refuted by live read. The item's own verification step is `grep -c operator-readout ~/.claude-next/settings.json # expect >=1 (is 0 today)`. It reads **1**. Every config dir that has a `settings.json` — `~/.claude`, `~/.claude-next`, `~/.claude-tertiary` — reads 1; the item's "other 4 config dirs" no longer exist as separate settings roots (`~/.claude-next2/3/4` are ABSENT). `09-operator-readout-activate.sh.done` present since Jul 30.
`97e4d0e74340` | PRUNE | Refuted **in place, by the same plan**. `CONCURRENCY_PROGRAM.md` §S6.3 carries a 2026-08-09 correction directly beneath the paragraph this item quotes: "the 2.2 is an instrument artifact and the pty wall is 3.6× further away than this paragraph says" — `ls /dev/ttys*` also matched the 16 **static legacy** BSD nodes (major 64, since boot, governed by nothing), so 33 was **17 real ptys at 15 sessions = 1.13**, projecting to **~152 of 511 (30%)** at 150 resident and binding at **~509 panes**. "Render, not ptys, is the binding term at 150" (§S6.7). The narrow predicate landed as `scripts/pty-census.sh` + a gauge row in `render-census.sh`. The "unowned by any S6 wave" clause is now correct-and-irrelevant: there is nothing to own.
`2d687628ce46` | KEEP | `docs/plans/GROUND_UP_DISPATCH.md:376` names **this exact id** as the re-arm item, and its 2026-08-07 header block still reads "3 OPEN (6 · 9 · 11)" with rows 9 and 11 marked RECONCILE-FIRST (overtaken out-of-band by `16dfe3b5` / `217ca100`). Both fire loops still dead.
`885cccce4c0f` | KEEP | `scripts/capacity-alarm.sh:255` still says verbatim that re-nouning "needs a per-coalition FOOTPRINT instrument that does not exist yet"; `COAL_WARN/COAL_ALARM` are still `500`/`700` with the "Left AS-IS deliberately" note intact. One thing to fold in as an UPDATE-inside-KEEP: rung **4** did adopt a physical-footprint instrument (`top(1)`'s MEM column, `:641-644`, chosen over `footprint(1)` to avoid a per-pid loop) — that is a candidate instrument the item's "does not exist" clause predates.
`a7460321494d` | KEEP | Both live reads confirm it: `git -C ~/Development/shadcn-pivot-data-table-example config --local --get cc.identity.exempt` → nothing recorded; `user.email` → still `contributors@pivot-table.dev`. Neither branch of the decision has been taken.
`4a4b97a2585e` | KEEP | Precondition re-derived live, exactly as `migrations/0004` re-derives it at consumption. `~/.claude/deathwatch/` holds only the seven 2026-07-15 `--selftest` fixture records; **`watch.tsv` does not exist**. So step 2 still exits 1 with "nothing produces the watch-file". The missing piece is still a PRODUCER, not the launchd job — do not activate.
`b09f54e9e080` | KEEP | Unratified, and the cost is countable: **6 of the 7 migrations on trunk declare `c10`** (only `0001` is `mechanical`). `inertness-generator-2026-08-07.md:363` still reads "has not been ratified, so the runner does not self-authorize it". The one-word promotion diff is still one word.
`1f323187c1e9` | UPDATE | **Remedy landed, symptom alive** — the item's stated fact is refuted while its payload defect is not. Refuted: `10-close-attrib-activate.sh.done` exists (Jul 30 01:32) and `~/.zshrc:498,502` both invoke `$HOME/.claude/bin/cc-close-attrib`, so the shim IS activated. Alive: the newest record in `~/.claude/logs/claude-crashes.jsonl` (`2026-08-09T11:03:39Z`, sid `639fc09b`, CC 2.1.220) still reads `"cause":"abrupt-unknown"`, `"stderr_log":""`, `"exit_code":""`. Retitle to "close-attrib is activated and still yields no attribution — the shim is not the missing piece."
`1e2fdb524533` | KEEP | Verified live, unchanged. `launchctl print-disabled gui/501` → `"com.claude.nightly-regression" => disabled`; `launchctl print gui/501/com.claude.nightly-regression` → *Could not find service*. `22-nightly-regression-activate.sh` is present (mtime Aug 9 16:19) with **no `.done`**. The `launchctl enable` step the item identifies as THE missing one is still missing.
`a50e6ab779e8` | KEEP | `docs/plans/README_HERO_BANNER.md` still churning on trunk (`cf20af92` v8 — "what the three beats were missing"). Its `needs` is the thrash artifact; stale worktree `wt-a50e6ab779e8` exists, **50 behind trunk**, clean. Work is live; the rail is what is stopping it.
`2f12ba8a0e3b` | MERGE | Canonical: **`96fe7b1687a0`**. Same operator act (connect GitHub in the Claude Code web app at claude.ai/code → settings), same symptom (`Bundle upload failed`), same doc (`CLOUD_OBSERVABILITY.md` §6.5/6.7 vs §11.4). `96fe7b1687a0` is 20 h newer and carries the §11.4 evidence this one lacks.
`0e4f795b3a20` | KEEP | **Repo EXISTS** — `~/Development/agent-build-hackathon`, a git repo. Verified uncovered by the audit's own three tests: installed `node_modules/next/dist/server/config-schema.js` **carries** `turbopackPluginRuntimeStrategy` (support is real, not a version guess); `next.config.ts` sets only `experimental.serverActions` — **flag NOT SET**; `scripts.dev = "next dev"` / `scripts.build = "next build"` — **no `--webpack` opt-out**. next 16.2.6. So this app can still mint the horde. Dispatch: the project is **not listed at all** in `scripts/dispatch-projects.conf`, so it is journalled `project-not-dispatched` every pass and can never drain. **Declare it** — `agent-build-hackathon repo=~/Development/agent-build-hackathon` — or accept it as a hand-edit; do NOT drop.
`e951f4b9f6e4` | KEEP | **Repo EXISTS** — `~/Development/lakehouse-lecture`, git, HEAD `236a893`. Genuinely un-agentable: it asks a third party (KPMG) a question whose answer exists in no repo — the item itself says "no booked room window is recorded anywhere in the repo", which I confirmed is the reason, not an oversight. **Do NOT declare the project in dispatch-projects.conf**: dispatching cannot help, because no worker can phone KPMG. This is an operator-only step that should be FILED for the operator readout, not queued.
`71bd004cc416` | UPDATE | **Repo does NOT exist** — there is no `~/Development/reso`. `dispatch-projects.conf` already adjudicates this label: `reso` is a **declared alias** of `reso-management-app`, deliberately kept `skip=` ("One repo, one label" — promoting it would permanently split one repo across two ledger buckets and break the S7 per-project fairness key). **Do not drop, do not declare — migrate**, exactly as its predecessor `333aed941b6b → 0c9d92ba9a0a` was. Two facts the conf did not know: (a) the conf asserts "Verified after: `reso` open=0", and this item was minted on **2026-08-08**, *after* that verification — so the class fix the conf itself files ("validate an explicit `--project` against this file's dispatch set at add time") is **still unlanded and the alias is still minting**; (b) the item's own content is durable and worth keeping — `fbd154346` exists in `reso-management-app` and its subject matches ("W16 — the exit splash, the Zag/flushSync finding"), so the finding is real; only the label is wrong.
`d60fd1f9c375` | KEEP | **Repo EXISTS and is a git work tree** — `~/Development/reso-qa-runner` (`git rev-parse --is-inside-work-tree` → true). Same three-test verification as `0e4f795b3a20`: schema **carries** the option, `next.config.js` **does not set it**, `dev`/`build` are `next dev` / `next build` with **no `--webpack`**. next 16.2.6 ⇒ uncovered ignition source. Dispatch: `dispatch-projects.conf` lists it as `reso-qa-runner skip=no open items (134 historical, all terminal); repo present if promoted` — **that stated reason is now FALSE**; it has this open item, filed today. **Promote `skip=` → `repo=~/Development/reso-qa-runner`.** The conf's own header anticipates exactly this ("Promote by changing `skip=` to `repo=`").

## Master item(s)

Three, and they are disjoint by *surface*, not by topic: M-1 edits foreign repos' configs and reads
kernel/crash state; M-2 edits `bin/cc-dispatch` / `bin/cc-wave-plan` / `scripts/worktree-gc.sh`; M-3
changes nothing an agent may change — it converts operator gates into either one ratification or one
rendered line. No two of them touch a shared file.

---

### M-tail-1 — Remove the panic's ignition from every app on this box that can still mint the horde, and make the next death attributable

**Encompasses:** `0e4f795b3a20`, `d60fd1f9c375`, `1f323187c1e9`
*(cross-slice sibling: the same edit is owed in `reso-management-app` — see Notes.)*

**Why one effort:** one kill chain, two links. `crash-rootcause-2026-08-09.md` §1 measures it end to
end — ignition (a `next-server` v16.2.6 postcss worker pool minting **18→372 procs in 90 s**, peaking
700 procs / 38.9 GB) → compressor **segment** exhaustion at only ~28 % mean fill → the whole CC fleet
sitting in jetsam band 180 so macOS kills a 15 MB Apple daemon instead → watchdogd misses 91–94 s and
`AppleARMWatchdogTimer` panics the box. §7 names the remedy as a **config flag, not an upgrade**
(`process_pool/mod.rs` is byte-identical 16.2.6↔16.2.12; upstream #95108 was bot-closed 30 s after
filing). `1f323187c1e9` is the same chain's other end: when the box dies this way it takes every
session with it, and every one of those sessions writes `cause:"abrupt-unknown"` with an empty
`stderr_log` — which is precisely why the root-cause work needed multi-hour manual traces.

**Impact, argued from evidence:**

- **A panic destroys every live session at once** — 15+ today — and it has happened **4 times in the
  last week, most recently 2026-08-09**. No other item in my slice can cost that much in one event.
- **The mitigation currently in force is last-ditch, not preventive.** `com.claude.compressor-sentinel`
  IS running under launchd (pid 48326) and its parent-breaker is delivered (§7-bis), but it SIGSTOPs a
  cohort that already exists. Swap grew at **457–580 MB/s** in the fatal window; a detector that fires
  inside that window is racing a 26-second ramp. The flag removes the child processes entirely.
- **Coverage today is zero of three.** The audit's own census found "of 76 Next apps under
  `~/Development`, exactly 3 have a schema that carries it (all on 16.2.6), and NONE of the 3 set it."
  I re-verified all three by hand: still none. This effort is 3 one-line config edits.
- **Bounded, named risk** (do not discover it at 3 a.m.): pre-#96592 (unreleased), a failing plugin can
  leak worker **threads** — one V8 heap, not 700 PIDs. That is the trade and it is the right side of it.

**DoD:** `experimental.turbopackPluginRuntimeStrategy: 'workerThreads'` set in
`agent-build-hackathon/next.config.ts`, `reso-qa-runner/next.config.js` and
`reso-management-app/next.config.js` — each landed **through that repo's own rails** (the auditor is
deliberately not a fixer; a cross-repo config edit belongs to the target repo) — `turbopack-worker-cap-audit.sh`
exits 0, and a session-crash record written after the change carries a non-empty `stderr_log` or a
cause other than `abrupt-unknown`.

**Falsifier:**
```
bash ~/Development/claude-infrastructure/scripts/turbopack-worker-cap-audit.sh --quiet && ! tail -20 ~/.claude/logs/claude-crashes.jsonl | grep -q '"cause":"abrupt-unknown"'
```

**First move:** `bash ~/Development/claude-infrastructure/scripts/turbopack-worker-cap-audit.sh --json`
— get the current uncovered set from the instrument rather than from this document, then open
`~/Development/agent-build-hackathon/next.config.ts` (the smallest config of the three, 8 lines) and
make the edit there first.

**Order:** 1. `0e4f795b3a20` (agent-build-hackathon — smallest config, no project rails to negotiate,
proves the flag boots) → 2. reso-management-app sibling (highest exposure: it is the app named in every
one of the three Aug-9 storm waves; goes through reso's `/ship`) → 3. `d60fd1f9c375` (reso-qa-runner —
same config shape as reso, so it is a copy of step 2) → 4. `1f323187c1e9` (attribution; independent of
1–3 and safe to run last, but do not close it as "activated" — it is activated and still blind).

---

### M-tail-2 — Make the autonomous queue able to finish an item: break the re-dispatch trap and the 553 immortal worktrees

**Encompasses:** `a50e6ab779e8`, `d7c413fe823f`, `b4f93c9fa73c`, `885cccce4c0f`, `29d1eba690a3`,
`71bd004cc416`, `2d687628ce46`, `01edea637633`

**Why one effort:** one generator, derived on trunk and never fixed. `69e6519a` (2026-08-08,
"the re-dispatch loop cannot terminate, and every safeguard in it is working as designed") names four
correct mechanisms composing into a trap: `cc-wave-plan:585` derives the worktree path as a **pure
function of the backlog id**, so every re-dispatch targets the same directory; `cc-dispatch:1258` gates
provisioning on `[ ! -d "$wcwd" ]` alone (deliberate, tested at `:1696-1701` — it protects live work);
`worktree-gc.sh:726` KEEPs any dirty tree, so the abandoned one is **immortal**; and
`cc-dispatch:680-684` re-materialises a surviving branch at its old tip, **discarding the `$base` it
fetched one line earlier**. That is why the ledger's verdict is always "the worker cannot land": the
worker is handed a tree hundreds of commits stale, and staleness plus same-hunk contention on a plan
file's one-line row cells is deterministic conflict (`exit 5`).

I measured the trap live, per item:

| item | worktree | commits behind trunk | dirty |
|---|---|---|---|
| `a50e6ab779e8` | `wt-a50e6ab779e8` | 50 | 0 |
| `d7c413fe823f` | `wt-d7c413fe823f` | **853** | **4** |
| `e09a075539f5` | `wt-e09a075539f5` | 50 | 0 |
| `b4f93c9fa73c` | `wt-b4f93c9fa73c` | 276 | 0 |
| `885cccce4c0f` | `wt-885cccce4c0f` | **680** | **9** |

`29d1eba690a3` is the same pathology one stage earlier — its ledger text is a **wedged owned wait past
the 21600 s ceiling** naming `wt-29d1eba690a3` as occupied; that worktree is now gone, and its remedy
(`hooks/lib/read-before-write-parity.sh`) was left **untracked** in the shared checkout rather than
landed. `71bd004cc416` and the two turbopack items fail at the same rail's *other* end — the dispatch
SET rather than the worktree — which is why the conf work belongs here and not in M-1.

**Impact, argued from evidence:**

- **This is the largest retirement lever in my slice: 8 of 20 survivors, and it is not per-item work.**
  Every one of the five thrash rows is a *correct* item that the machine re-attempts and re-fails.
- **The precedent says the blast radius is far wider than my slice.** `bin/cc-backlog:112` records the
  last measurement of the same class: **228** items blocked "persistent thrash", of which **0** would
  still block once self-releases were excluded and **182** never held a claim for even the 90 s window
  — "**64 % of everything blocked in this store got there that way**". That producer defect was fixed
  (`--self-release`); this one — the immortal worktree — was only *derived*.
- **It is compounding on disk right now: 553 worktrees** under `~/Development/.worktrees/`, and
  `worktree-gc.sh` is doing its job by refusing to delete the dirty ones.
- **It touches the enforcing store** (`bin/cc-dispatch`, `bin/cc-wave-plan`, `scripts/worktree-gc.sh`)
  — not docs. Nothing since `69e6519a` has gone near it: the only later commits on those paths are
  `1c3e8e9f` (rc-4 journalling), `5d6cb758` (claim hand-over) and `3dcac1f3` (pipefail).
- **One item here is a live data-integrity exposure, not a scheduling one** (`29d1eba690a3`, below).

**DoD:** a re-dispatched item is provisioned onto a tree at `origin/main` (freshness asserted at
hand-out, per `GROUND_UP_DISPATCH`'s own ruling that routes worktree-freshness to row 11); an abandoned
worktree for a *reopened* item is reclaimable without weakening `worktree-gc`'s dirty-tree KEEP; the
five thrash rows re-enter the wave and at least one lands; `hooks/lib/read-before-write-parity.sh` is
committed; the `reso` alias stops minting (explicit `--project` validated against the dispatch set at
add time) and `71bd004cc416` is migrated to `reso-management-app`.

**Falsifier:**
```
cc-backlog list --all --json | jq -e 'map(select((.needs//"")|test("persistent thrash")))|length==0' >/dev/null && [ "$(ls ~/Development/.worktrees 2>/dev/null | wc -l)" -lt 50 ]
```

**First move:** `git show 69e6519a` and read the four cited line ranges in order
(`cc-wave-plan:585`, `cc-dispatch:1258` + `:1696-1701`, `worktree-gc.sh:726`, `cc-dispatch:680-684`).
The derivation is complete and the repro is already two-armed in that commit message — do **not**
re-derive it; the open question is only which of the four to change, and `cc-dispatch:680-684`
(re-materialising a branch at its old tip while discarding the freshly-fetched `$base`) is the one
whose fix does not weaken a protection someone deliberately built.

**Order:** 1. `29d1eba690a3` **first and out of band** — it is a two-minute commit of a file already
written, and until it lands every session on every account can blind-overwrite a file it never read
(see Notes). → 2. the rail fix itself (`69e6519a`'s four sites) → 3. reclaim the five stale worktrees
and let `a50e6ab779e8` / `d7c413fe823f` / `b4f93c9fa73c` / `885cccce4c0f` re-enter the wave → 4.
`01edea637633` (CONDITION LEASE — the sibling anti-duplication guard in the same dispatcher, and its
plan's Phase 0 explicitly forbids splitting it) → 5. `2d687628ce46` (re-arm the GROUND-UP campaign,
which is only reachable once dispatch terminates; rows 9 and 11 **reconcile-first, do not rebuild**) →
6. `71bd004cc416` (migrate the alias) + the dispatch-set declarations M-1 needs.

---

### M-tail-3 — Collapse nine operator-gated dead ends into one ratification and one rendered line

**Encompasses:** `b09f54e9e080`, `4a4b97a2585e`, `1e2fdb524533`, `96fe7b1687a0` (absorbing
`2f12ba8a0e3b`), `bd3a486fa469`, `eb8911ec044f`, `a7460321494d`, `e951f4b9f6e4`, `e09a075539f5`

**Why one effort:** every one of these is an item the autonomous machine cannot finish because its last
step is a human act — and they are **not all the same kind of human act**, which is exactly the
distinction this effort exists to draw. `b09f54e9e080` is the hub: ratifying the C10 rescope
("operator RUNS every activation" → "operator CAN REVERT any converged migration") converts a named
subset from hand-step-forever into run-at-converge with a **one-word diff** per migration. **Six of the
seven migrations on trunk declare `c10`** (only `0001` is `mechanical`), so one decision moves six
things. What ratification does **not** cover is the genuine residue — a GitHub OAuth consent
(`96fe7b1687a0`), a telemetry-diversion value call (`bd3a486fa469`), a security-envelope call
(`e09a075539f5`), a project-identity call (`a7460321494d`), a question only KPMG can answer
(`e951f4b9f6e4`) — and the job for those is not to run them but to **file** them so
`operator-readout.sh` renders them as one counted line instead of leaving them as invisible `blocked`
rows.

Two members are here for their *shape*, not their gate, and both need saying out loud:

- `4a4b97a2585e` **is not actually operator-gated and must not be activated.** Its blocker is that
  nothing produces `~/.claude/deathwatch/watch.tsv` — I confirmed the directory holds only 2026-07-15
  selftest fixtures. Activating it would arm kqueue on an empty list and heartbeat healthily while
  watching nothing. The work is a **producer**, and it is agent work.
- `1e2fdb524533` **is** operator-gated and the gate is precise: agents are classifier-blocked from
  `launchctl enable`, and `launchctl print-disabled gui/501` still reads
  `"com.claude.nightly-regression" => disabled`. `bootstrap` alone will not run a disabled label.

**Impact, argued from evidence:**

- **One decision retires six migrations' worth of hand-steps.** That ratio is what makes this an effort
  rather than a chore list.
- **It is the documented failure mode of this whole store.** `migrations/README.md` was written to
  abolish `pending-activation/` precisely because it is "an advisory diode where writes always succeed
  and reads are discretionary (38 pending, 11 rotting past 24 h)" — and `migrations/0004`'s own header
  records that the queue was *still* showing 6 un-run and 5 rotting >24 h when it landed. The residue
  reproduced one generation on.
- **The nightly regression has never once run.** Its label has been disabled the entire time; the 8
  entries in `regression.log` were manual runs at working-day times. That is a green-producer the land
  rail does not have — and `b4f93c9fa73c` (M-2) is the *other* missing green producer, which is why
  these two efforts stay separate but should be read together.
- **`96fe7b1687a0` is the single cheapest unblock in the whole slice**: one GUI consent, and it retires
  a duplicate (`2f12ba8a0e3b`) and probably a third item (`eb8911ec044f`) with it.

**DoD:** the C10 rescope is ratified or declined **on the record** (either answer closes
`b09f54e9e080`); every migration whose class the ratification covers is promoted `c10 → mechanical` and
has run at converge; the residue that ratification does not cover is filed via `cc-backlog needs`
(with `--run` where a command exists) so it renders in the `OPERATOR ▸` block; and `4a4b97a2585e` is
re-filed as agent work (build the watch-file producer), not as an activation.

**Falsifier:**
```
! grep -h 'migration-class:' ~/Development/claude-infrastructure/migrations/0*.sh | grep -q c10
```

**First move:** put the ratification to the operator as a **one-sentence value question with no command
to run** — *may a migration that edits `settings.json` or a launchd plist run unattended at converge,
given you can revert any of them?* — and file it as a class-C decision packet so `wrap-ledger.sh`
computes `⛔` from it rather than leaving it in prose. Everything else in this effort is downstream of
that one answer.

**Order:** 1. `b09f54e9e080` (the hub — nothing else here should move first) → 2. promote the
migrations the ratification covers (`0002`, `0003`, `0005`, `0006`, `0007`) → 3. `1e2fdb524533`
(nightly regression: still a genuine `launchctl enable` gate whether or not the rescope passes) → 4.
`96fe7b1687a0` + `2f12ba8a0e3b` (one GUI consent) → 5. `eb8911ec044f` (re-test **after** step 4; it may
be a no-op) → 6. file, do not drive: `bd3a486fa469`, `e09a075539f5`, `a7460321494d`, `e951f4b9f6e4` →
7. `4a4b97a2585e` re-scoped out of this effort into agent work.

---

## Notes for the lead

**1. Land `hooks/lib/read-before-write-parity.sh` before anything else in this report.** It is the one
finding here with a same-day cost. `tengu_velvet_mallet_opus_5` now reads **true** on all four account
config roots (`.claude-next` = next, `.claude-secondary` = next2, `.claude-tertiary` = next3,
`.claude-quaternary` = next4) — on 2026-08-05 it was true on next2 *only*. With `claude-opus-5` as the
default model, Claude Code's native "File has not been read yet" refusal is **skipped fleet-wide**,
which is the exact guard the global CLAUDE.md's CRITICAL File Update Rule depends on. The remedy is
written (11 KB, mtime Aug 5), sits **untracked** in the shared checkout, and appears on trunk nowhere.
It is also a landmine for your merge: it is one of the two untracked files in `git status` at session
start, so any agent doing a `git add -A` sweeps it into an unrelated commit.

**2. My slice's biggest item is cross-cluster, and I do not own its third leg.** M-tail-1 needs the same
one-line edit in **`reso-management-app`**, whose items are in the P-reso cluster. That is the app named
in all three Aug-9 storm waves (`next-server` pid 36923), so it is the highest-exposure of the three and
the one my slice cannot reach. Please make sure whoever holds P-reso is told the flag is **NOT SET**
there — `crash-rootcause-2026-08-09.md` §7 reads "Fix shipped in the installed 16.2.6 … in reso's
next.config", which parses naturally as *done* and is not: "shipped" refers to the option existing in
the installed Next, not to the edit having been made. I verified the config by hand. If the P-reso agent
read only §7 they will have marked it PRUNE.

**3. Two of my items are the same operator act; I merged rather than dropped.** `2f12ba8a0e3b` →
`96fe7b1687a0`. If your other clusters contain a third "connect GitHub / Bundle upload failed" row, it
is the same one.

**4. `885cccce4c0f` is a KEEP that another cluster may hold a rival reading of.** Its subject
(`capacity-alarm.sh` rung 6) is machine-capacity, but the file is shared with rungs 1/4/7, so a
`capacity`-flavoured item elsewhere may propose editing the same header. The item's instruction is
explicit and worth relaying: **do not tune `COAL_WARN`/`COAL_ALARM`** — fixing the units alone would
make the rung fire correctly on a quantity that provably cannot discriminate (996 survived vs 1002
fatal). The one quantity that does separate them is the coalition's total anon footprint (139.50 GiB
fatal vs a 28.18 GiB survived ceiling, 4.95× apart with an empty interval) — but n=1 fatal sample, so
that is an ordering, not a threshold.

**5. Both my PRUNEs were refuted by the subject's own later text, not by my inference.**
`97e4d0e74340` is contradicted by a correction paragraph sitting directly beneath the sentence it
quotes in `CONCURRENCY_PROGRAM.md`; `6053ebd74b52` fails its own stated verification command. If you
are spot-checking my slice adversarially, those two are the cheapest to re-check and the safest to
trust.

**6. Dispatch-set answer, consolidated** (you asked per-item): `agent-build-hackathon` — repo exists,
**declare it** (`repo=~/Development/agent-build-hackathon`). `reso-qa-runner` — repo exists and is a git
work tree, **promote `skip=` → `repo=`**; its recorded skip reason ("no open items") is now false.
`lakehouse-lecture` — repo exists but **do not declare**: no worker can phone KPMG; file it as an
operator step instead. `reso` — repo does **not** exist, and the conf already rules the label an alias
that must stay `skip=` ("one repo, one label"); **migrate the item to `reso-management-app`**, do not
drop it and do not declare `reso`. Nothing in my slice should be dropped for being in an undispatched
project.
