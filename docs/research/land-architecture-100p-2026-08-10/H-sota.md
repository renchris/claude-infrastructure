# H-sota — Industry landing architectures → this fleet

Worker H. 2026-08-10. Scope: known-good high-rate trunk-landing architectures, which invariants
transfer to a 15-session single-machine shared-object-store fleet, and 3 concrete candidate
architectures for this machine.

**Headline, stated first because it reorders the whole question:** the industry's central lever —
batching, to amortise expensive CI — has **no purchase here**, and the fleet's measured landing
pathology is not concurrency control at all. `stranded-sweep.sh` costs **55.8 s** and runs **inside
the machine-wide land mutex** on every successful land, while `land-verify.sh` — the thing the lock
actually exists for — costs **0.485 s**. Measured v2 success-path lock hold is a **median 87 s**
against a design comment claiming "a 5-15 s hold"; **0 of 1021 v2 lands held the lock for 6-15 s**.
Roughly two-thirds of the mutex is a read-only housekeeping scan that is `O(branch refs)` — i.e. the
critical section *grows with fleet size*, which is the textbook convoy generator. Everything below
is downstream of that.

---

## 1. Invariant table per system

Empirical = cited to a primary doc/paper. Column "single-writer?" means *one serialised actor
advances trunk*; "speculation?" means *test state N+k before N is known good*.

| System | Single-writer? | Batching? | Speculation? | Conflict handling | Failure feedback path | Source |
|---|---|---|---|---|---|---|
| **bors / bors-ng** (the "Not Rocket Science Rule") | Yes — one bot merges; staging branch is the only writer | Yes — N PRs merged onto a staging branch, tested as one unit | No (the batch *is* the proposed future trunk, not a state ahead of it) | Batch fails ⇒ **bisect**: split in two, requeue both halves | Comment posted back on the PR; author re-runs `bors r+` | [bors-ng](https://github.com/bors-ng/bors-ng), [matklad](https://matklad.github.io/2023/06/18/GitHub-merge-queue.html), [Graphite history](https://graphite.com/blog/bors-google-tap-merge-queue) |
| **rust-lang bors rollup** | Yes | Yes, **opt-in per PR** — `rollup` sets priority −1; rollups merge together only when no normal PR is queued | No | Same bisect model; rollup explicitly reserved for low-risk changes (doc fixes) | PR comment | [Rust Forge](https://forge.rust-lang.org/infra/docs/bors.html), [internals.rust-lang.org](https://internals.rust-lang.org/t/batched-merge-rollup-feature-has-landed-on-bors/1019) |
| **GitHub merge queue** | Yes — the queue owns the merge | Yes — configurable max group size; `gh-readonly-queue/<base>` temp branches | **Yes** — tests A on main, B on main+A, C on main+A+B; `build concurrency` (1-100) caps dispatched `merge_group` webhooks | Group fails ⇒ dequeue the culprit / bisect the group; PR leaves the queue | GitHub UI + PR state; author must requeue | [GitHub Docs](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-a-merge-queue) |
| **Zuul (dependent pipeline)** | Yes — the gate pipeline merges | Implicitly: each item is tested *with* everything ahead of it | **Yes, canonically** — "assume all jobs will succeed and test in parallel"; jobs for E run on main+A+B+C+D | Failure ⇒ **gate reset**: the failing change is ejected, everything behind it discards results and re-tests without it | Vote/comment back to the Gerrit/GitHub change | [Zuul gating](https://zuul-ci.org/docs/zuul/latest/gating.html) |
| **Zuul window (flow control)** | — | — | — | — | — | TCP-style: window starts at 20, **+1 per success, halved on failure**, per project queue, so one flaky queue cannot degrade others (same doc) |
| **Uber SubmitQueue** | Yes — "illusion of a single queue"; actual commits to HEAD are strictly serialised | No (speculation instead) | **Yes, predictive** — a binary *speculation tree* annotated with success probabilities; logistic regression at **97 % accuracy**; the planner runs the most promising branches and *kills* unscheduled builds | Conflict domain = **build targets** (Merkle-style target hashes); independent changes commute and run in parallel. A failing change is removed and the tree recomputed | Change ejected from the queue; author notified | [EuroSys'19 paper](https://dl.acm.org/doi/10.1145/3302424.3303970), [Morning Paper](https://blog.acolyer.org/2019/04/18/keeping-master-green-at-scale/) |
| — outcome | iOS mainline was green **52 %** of the time before; green continuously after; turnaround **1.2× a perfect oracle** with n workers for n changes/hour | | | | | same |
| **Google TAP** | **No — TAP is not a trunk gate.** Presubmit (a fast subset) gates submit; TAP is *postsubmit* | **Yes — "milestones"**, a cut every **~45 min at peak**, bundling consecutive commits; affected targets run only at their **latest** affecting CL | No | A failing batch is **split into individual changes and re-run in isolation**, plus a developer-facing binary-search culprit tool | Breakage reported after the fact; trunk has a **"true head" and a separate "green head"**; releases are cut from green head | [Memon et al., ICSE-SEIP'17](https://research.google.com/pubs/archive/45861.pdf), [SWE at Google ch.23](https://abseil.io/resources/swe-book/html/ch23.html) |
| — numbers | 13 K projects, 800 K builds + 150 M test runs/day; 50 K+ changes/day; a commit ~every second; affected sets as large as **4.2 M** targets; observed delays **up to 9 h**; only **1.23 %** of executions ever find a real breakage; PASS:FAIL 99:1; presubmit-pass ⇒ **95 %+** postsubmit pass | | | | | same |
| **Kubernetes Prow/Tide** | Yes — one controller, one bot token, dozens of orgs | Yes — batch pools per org/repo/branch; falls back to serial merge when no batch result is ready | Partial (a batch is an optimistic future state) | PRs filtered out on failed job / pending check / **merge conflict** / invalid merge method; must be tested against the **most recent base commit** | GitHub status back on the PR | [Tide docs](https://docs.prow.k8s.io/docs/components/core/tide/) |
| **GitLab merge trains** | Yes — the train head merges | The train is a chain of cumulative speculative pipelines | **Yes** — each MR's pipeline includes every MR ahead of it | Failure ⇒ MR removed from the train and **new pipelines started for everything queued behind it**; redundant pipelines auto-cancelled on reconstruction | MR widget; documented failure mode where the **MR becomes unactionable** after a failed train pipeline | [GitLab docs](https://docs.gitlab.com/ci/pipelines/merge_trains/), [issue #474527](https://gitlab.com/gitlab-org/gitlab/-/issues/474527) |
| **Gerrit (+ gerrit-queue)** | Server-side submit; `gerrit-queue` adds a single-writer daemon | No | No | `Rebase Always` creates a new patchset even when ff is possible; content merge optional. gerrit-queue tracks **one `wipChain` across runs** precisely so two chains never rebase onto one HEAD | CI verdict on the change; **on failure the wipChain is simply discarded** — the README documents no kickback path and no author-absent handling | [Gerrit project config](https://gerrit.cloudera.org/Documentation/project-configuration.html), [gerrit-queue](https://github.com/tweag/gerrit-queue) |
| **Meta (Sapling/Mononoke)** | Yes — **server-side push-rebase**: the server rebases your push onto the current bookmark | not public | not public | The rebase happens server-side, so the client never races the bookmark | Sandcastle CI / Landcastle deploy; land-blocking specifics not public | [Sapling announcement](https://engineering.fb.com/2022/11/15/open-source/sapling-source-control-scalable/), [Sapling scale docs](https://sapling-scm.com/docs/scale/overview/) — *thin: Meta's land-queue internals are not publicly documented; directional only* |
| **Mergify** | Yes | Yes — `batch_size: {min,max}` is **dynamic**: small while quiet, grown toward max only when the queue backs up | Yes — `max_parallel_checks` speculative batches | A failed batch is **binary-searched** for the culprit, which is removed; bisection *frequency* is published as the tuning signal (frequent ⇒ batch too large) | Queue state + PR; dequeue | [Performance](https://docs.mergify.com/merge-queue/performance/), [dynamic batch size](https://docs.mergify.com/changelog/2026-06-19-dynamic-merge-queue-batch-size/), [batch bisection stats](https://docs.mergify.com/changelog/2026-03-12-batch-bisection-statistics-api/) |
| — **RCV theorem** | Pick two of **Reliability · Cost · Velocity**. R+V = speculative parallel (wastes CI). R+C = sequential (low throughput). V+C = batching (risks hidden failures) | | | | | same |
| **Aviator MergeQueue** | Yes | Yes, plus an optimistic parallel mode | Yes | **A single failure resets the entire optimistic queue** — mitigated by splitting into disjoint queues keyed on *affected targets*, so a failure stays local | Dequeue + notify | [Aviator monorepo blog](https://www.aviator.co/blog/merge-queues-for-large-monorepos/) |

### Cross-system invariants that actually recur

1. **One writer to trunk.** Every system, without exception. Not a performance choice — it is the
   definition of the not-rocket-science rule.
2. **Trunk state is validated against the state it will actually have at land time,** never against
   the state the author branched from (Tide: "most recent base commit"; GitHub: main+A+B; Zuul: the
   whole chain ahead).
3. **Batching is a CI-amortisation device and its price is attribution.** Every batching system pays
   with bisection or ejection machinery. TAP, which batches hardest (45-minute milestones), is
   exactly the system that **gave up the green-trunk invariant** and split "true head" from "green
   head".
4. **Speculation is an alternative to batching, not a complement,** and its price is wasted compute:
   Zuul discards everything behind a failure, SubmitQueue kills unscheduled builds, Aviator's
   optimistic queue resets whole.
5. **Every system has an explicit ejection path.** The failing change leaves the queue and the queue
   keeps moving; none of them let one failure block the writer.
6. **Flow control is real and is TCP-shaped.** Zuul's window (+1 / halve) and Mergify's dynamic
   `{min,max}` are the same idea: batch/window size is a *controlled variable*, never a constant.

---

## 2. Transfer analysis — which invariants survive this constraint set

Measured on this machine, 2026-08-10, unless marked *(reasoned)*.

### 2.1 The economics that justify batching are absent here

| Quantity | Industry premise | This fleet (measured) |
|---|---|---|
| Gate duration | ~30 min (Aviator's own sizing case; TianPan's 30-min merge group) | `smoke_s` **median 0 s**, p90 12 s, p95 120 s, p99 256 s, max 1200 s (n=1126, `~/.claude/land.log`); `gate_scope` is `fast` on **84 %** of lands |
| Test-merge / mergeability probe | one full CI cycle | **`git merge-tree --write-tree`: 21 ms each; 60 branch heads via `--stdin` in 0.193 s** (≈3 ms/merge) — no worktree, no index, no checkout |
| Rebase | worktree checkout + apply | **`git replay --onto`: 24 ms**, worktree untouched (git 2.54.0; note `git replay` self-declares **EXPERIMENTAL**) |
| Fetch cost | network-bound | shared object store; `git fetch origin main` 0.52 s; `ls-remote` RTT 0.42-0.46 s |
| Demand | at or above capacity | **73 lands/day** (v2 era, n=1021 over 14 d), peak day 220 |
| Serialised capacity | the binding constraint | at the measured 87 s success-path hold ⇒ ~990 lands/day ⇒ the fleet runs at **~7 % of its own serialised capacity**; mutex duty cycle **5.6 %** |

**Verdict (empirical): batching does not transfer.** Its entire payoff is amortising a gate that
costs seconds here, against a queue that is ~93 % idle. Batching would save at most ~15 K CPU-seconds
per month of gate time (`sum(smoke_s)` = 15,290 s over 1126 lands) at the price of importing
bisection, ejection, and — fatally — *residency* (§2.3).

**Verdict (empirical): speculation does not transfer either.** Speculation exists to fill a long CI
pipeline with useful work. With a 0-second median gate there is nothing to fill; SubmitQueue's whole
apparatus (speculation tree + logistic-regression predictor) buys back a 30-60 minute build that this
fleet does not have.

### 2.2 What *does* transfer

| Invariant | Transfers? | Why |
|---|---|---|
| Single writer to trunk | **Yes — already present.** `land-lock.sh` keys the mutex on `--git-common-dir`, so all 125 worktrees collide on one lock (`/tmp/land-lock-<hash>/lock.d`) | |
| Validate against the state at land time | **Yes — already present.** ship-land's in-lock CAS (`origin/$TRUNK == GATE_BASE && HEAD == GATE_HEAD`), exit 42 on drift | This is optimistic concurrency control with validate-at-commit — textbook OCC ([Agrawal/Carey/Livny 1987](https://people.eecs.berkeley.edu/~brewer/cs262/ConcControl.pdf)) |
| Explicit ejection path | **Partially — and this is the real gap.** A failed land ejects, but the *notice* goes to stderr in a pane that may no longer exist | |
| Flow control / window | **No.** There is no queue to window; utilisation is 5.6 % | |
| Batch bisection | **No** — nothing to bisect | |
| Culprit granularity = land granularity | **Yes, and it is load-bearing here.** `postland-verify.sh` owns trunk-wide verification **with auto-revert**; a batched land makes an auto-revert punish innocent authors — the coupling TAP escapes only by having a separate culprit-finder and no green-trunk invariant *(reasoned)* | |

### 2.3 The constraint the brief understates: conflict risk is a function of **residency**

The brief's "conflicts are rare (mostly-additive, rerere enabled)" is true **at land time, and only
because the fleet lands fast.** Measured with worktree-free `merge-tree` over `refs/heads`, bucketed
by tip age:

| Branch tip age | already landed | clean merge | conflicting | conflict rate |
|---|---|---|---|---|
| < 6 h | 22 | 15 | 18 | **55 %** |
| 6-24 h | 1 | 10 | 36 | **78 %** |
| 24-72 h | 9 | 12 | 117 | **91 %** |
| 72-168 h | 3 | 4 | 74 | **95 %** |

Top conflicting paths: `scripts/handoff-fire.sh` (38), `docs/plans/CONCURRENCY_PROGRAM.md` (34),
`scripts/postland-verify.sh` (21), `scripts/ship-land.sh`, `scripts/wrap-ledger.sh`,
`docs/plans/CLOUD_OBSERVABILITY.md`. `rr-cache` holds **184 entries** — rerere is doing real work on
repeated conflicts, which is itself evidence the same hunks recur.

Reconciliation with the low *land-time* conflict rate (`exit=5` rebase-conflict rollback: 10/447 in
v1, **0/1021 in v2**): both are true, and one mechanism explains both — **the fleet lands within
minutes of committing, so branches never age into the conflict zone.** 498 branch refs exist across
125 worktrees; most are dead branches that were never going to land.

**Therefore the binding transfer constraint is: any architecture that increases time-from-commit-to-
land converts a ~0 % land-time conflict rate into a 55-91 % one.** That one fact kills batching,
windowing, queue backlog and speculative-tree scheduling for this fleet *independently* of their CI
economics — every one of them is a residency-adding design.

### 2.4 Documented failure modes, mapped

**Sync-lock landing (what the fleet has today).**

| Failure mode | Status here |
|---|---|
| **Starvation / no FIFO.** `land-lock.sh` is a `mkdir` spin-lock with `POLL=2` and `LAND_LOCK_WAIT=3600`; macOS ships **no `flock(1)` binary** and `flock(2)`'s man page specifies no wake ordering — so there is no queue at all, every waiter races each tick | **v1: real and measured** — 19 lands exited 75 (EX_TEMPFAIL) after the full 3600 s wait; max wait 7386 s. **v2: gone** — 0 timeouts, max wait 728 s |
| **Convoying.** A critical section that grows with fleet size | **Live.** `stranded-sweep.sh` is `O(branch refs)`; 498 refs today |
| **Priority inversion** | Not observed; no priority scheme exists |
| **OCC thrash** — abort rate rises with concurrency; Agrawal/Carey/Livny show blocking thrashes past a critical multiprogramming level while OCC survives *when restarts are cheap* | **Present but benign.** `exit=42` stale-gate restarts are **173/1021 (17 %)** of v2 lands, but those acquisitions hold the lock a **median 1 s, max 2 s**. The restart loop is correct and nearly free |
| **The land dies with its author** | **Measured.** v2: 7 × `exit=130` (SIGINT, median hold 99 s) + 19 × `exit=127`; ~2.5 % of lands die by signal/missing-command. `land-lock.sh` runs the lander as a *child it waits on*, so a dead session is a dead land |

**Queue landing (what a redesign would import).**

| Failure mode | Evidence |
|---|---|
| Queue-daemon death ⇒ fleet-wide land stoppage | This machine has the receipts: an agent used `launchctl disable` on **13 labels** on 2026-07-26 and the 07-27 reboot turned it into a total outage; `launchctl list \| grep` maps six real states onto one boolean and puts four broken ones on the healthy side (`memory/daemon-fleet-v2.md`) |
| Stale batches / kickback storms | GitLab: a failed train pipeline starts **new pipelines for everything behind it**, and there is a documented state where the MR becomes unactionable ([#474527](https://gitlab.com/gitlab-org/gitlab/-/issues/474527)); Aviator: "a single failure would reset the entire optimistic queue" |
| Silent daemon decay | launchd's fast-fail throttle stopped scheduling `deploy-live` after 59 failures — **a broken daemon gets quieter with age**, so any detector keyed on complaint volume reads recovery where there is decay |

### 2.5 The measurement that reorders the whole question

v2 lock-hold distribution (n=1021, since 2026-07-28):

```
exit=0   (landed):     n=824  med= 87 s  p90=124 s  max=282 s
exit=42  (stale-gate): n=173  med=  1 s  p90=  1 s  max=  2 s
exit=130 (SIGINT):     n=  7  med= 99 s             max=163 s
hold buckets: 0-5 s 19% | 6-15 s 0% | 16-30 s 5% | 31-60 s 26% | 61-90 s 12% | 91-150 s 35% | >150 s 4%
wait_s: med 0 · p90 81 s · p95 110 s · p99 248 s · max 728 s · 242/1021 waited at all
```

`ship-land.sh:2140-2250` shows what the success path runs inside the mutex: `git push` → `git fetch`
→ `land-verify.sh` → `ship-backup-reap` → **`stranded-sweep.sh`** → postland enqueue. Timed directly:

- `scripts/land-verify.sh` (content-verify — the race window's actual proof): **0.485 s**
- `scripts/stranded-sweep.sh main` (read-only housekeeping scan): **55.8 s**, 512 lines of output
- network terms: push + fetch ≈ 1-1.5 s

So **~56 s of an ~87 s machine-wide mutex is a read-only sweep with nothing to do with the race
window** — in a script whose own header states the lock "covers the race window (a 5-15 s hold),
never a proof", and **0 of 1021 v2 lands landed in that 6-15 s band**. The p99 wait (248 s) and max
wait (728 s) are explained arithmetically by hold × queue depth (peak reconstructed queue depth
**13**, at 2026-07-26 09:42).

---

## 3. Candidate architectures for THIS fleet

Each is a component sketch: **enqueue surface · lander · conflict/red-gate kickback · live-converge
trigger · failure inbox**. Costs are derived from the measurements above.

### Candidate A — "Empty the critical section" (keep the topology, subtract from the lock)

| Component | Design |
|---|---|
| Enqueue surface | **None.** Unchanged: the author's own `/ship` calls `land-lock.sh -- ship-land.sh` |
| Lander | The author's own process under the existing mkdir mutex. Critical section reduced to **fetch-CAS → `git push` → `land-verify.sh`** (measured 0.485 s) ≈ 2 s |
| Moved out of the lock | `stranded-sweep.sh` (55.8 s) and `ship-backup-reap` become post-lock, or fold into `postland-verify.sh` — already an enabled background singleton whose job *is* trunk-wide verification |
| Conflict / red-gate kickback | Unchanged — exit 5/6/7/42 to the live session's stderr |
| Live-converge trigger | Unchanged — `com.claude.deploy-live` (enabled, 300-600 s timer) |
| Failure inbox | **None (unchanged gap)** |

- **Strongest FOR:** pure subtraction against a *measured* 56 s attribution. No new daemon, no new
  `launchctl enable`, no new store, no invariant changed. Critical section 87 s → ~2 s ⇒ serialised
  capacity ~990/day → ~40 000/day, and tail wait falls with it (wait ≈ hold × depth; depth peaks at
  13, so worst-case drain 19 min → ~26 s).
- **Strongest AGAINST:** it does not answer question 4(d) at all. A land still dies with its author
  (7 measured SIGINT deaths in v2), a failed land is still stderr in a pane that may be gone, and the
  only durable trail is a `ship/backup-*` ref that `ship-backup-reap.sh` reaps. It is a performance
  fix wearing an architecture's clothes.

### Candidate B — "Ticket lander on the existing spine" (single-writer daemon + durable inbox)

| Component | Design |
|---|---|
| Enqueue surface | The author pushes a local ref `refs/land/queue/<ts>-<sid>-<branch>` (free, atomic, **outlives the session**) **and** `cc-backlog add --project land --condition land-<branch>` — append-only JSONL, event-keyed idempotent ids, lease/claim semantics, and `cc-backlog add` already **kicks a debounced decision pass** |
| Lander | A new verb on the **already-enabled** `com.claude.dispatcher` spine (`StartInterval 300` + write-kick), *not* a new launchd label. Loop, FIFO by ref timestamp: `merge-tree --write-tree --quiet` probe (3 ms) → `git replay --onto origin/main` (24 ms, worktree-free) → gate the replayed range in one reusable scratch worktree → in-lock CAS → push → advance |
| Conflict / red-gate kickback | Move the ref to `refs/land/failed/<same-name>` (the evidence survives) and file `cc-backlog needs "<branch>: rebase conflict on <paths>" --run "<exact re-land command>"` keyed to the author's session id. `operator-readout.sh` renders it and `wrap-ledger.sh` computes it into the `👤` rung **whether or not the author still exists** |
| Live-converge trigger | The lander calls `scripts/deploy-live.sh` **per land**, not on the 600 s timer — required, because `LIVE_ADDS > 0` breaches at a lag of **1**: a landed diff that ADDS a file has no symlink, so every `[ -f x ] && . x` consumer silently skips |
| Failure inbox | `cc-backlog` (durable JSONL, already rendered at every close) |

- **Strongest FOR:** it is the only candidate that answers 4(d). The land outlives the author, and a
  conflicting or gate-red branch becomes a durable *rendered* row with a runnable remedy instead of
  bytes written to a dead pty. It also converts landing from N racing writers to one FIFO writer at a
  measured cost of ~30 ms per candidate.
- **Strongest AGAINST:** it puts the fleet's entire landing path behind one process on a spine that
  `install.sh:306-315` **boots out and re-bootstraps with no `launchctl enable`, swallowing every
  error**, and that `deploy-live.sh:283` invokes on every autonomous advance (600 s) — so an enabled
  job is bounced mid-work by a routine event and a disabled one can never be recovered by it.
  Combined with the asymmetric classifier boundary (**agents may `disable`/`bootout` but are denied
  `launchctl enable`**), the failure is silent, fleet-wide, and *not self-healable by any agent*.
  Today a wedged lock starves one session; here it stops every session's ability to land.

### Candidate C — "Local trunk advance + async publish" (decouple *landed* from *pushed*)

| Component | Design |
|---|---|
| Enqueue surface | Unchanged (direct call) |
| Lander | Two phases. **Phase 1 — in-lock, local-only, no network:** CAS on local `main` → `git replay --onto main` → `update-ref` → `deploy-live.sh`. Sub-second. **Phase 2 — out-of-lock, async:** a publisher pushes local `main` → `origin`, batched and retried, allowed to lag |
| Conflict / red-gate kickback | Phase 1 rejects to the live session (as today); Phase 2 failures file to `cc-backlog` |
| Live-converge trigger | The same breath as the land — the strongest property of this design |
| Failure inbox | `cc-backlog`, for publish failures only |

- **Strongest FOR:** it removes the network and the remote's ordering from the critical section
  entirely and makes *landed* and *live* the same event, structurally killing the `🚀`/`LIVE_ADDS`
  inertness class (a landed-but-absent file being a silent no-op at every consumer guard).
- **Strongest AGAINST:** it inverts this repo's own durability invariant. The project `CLAUDE.md`
  makes "verify landings **by CONTENT** (`git ls-tree origin/main -- <paths>`), never by count" the
  load-bearing rule after the 2026-07-11 incident in which `dfacccd` (5 new files) was silently
  dropped by a sibling's land while `rev-list origin/main..HEAD` read 0. Candidate C would make `✅`
  assertable before anything reached origin, reopening exactly that class — and a crash between the
  two phases leaves work the ledger calls live that no remote holds.

### Ranking under the operator's own constraints

**B dies first**, and not on its merits: on `launchctl enable` being denied to agents plus the
`install.sh` bounce, which together make its single point of failure both reachable-by-accident and
unrecoverable-by-agent. **C dies second**, on the content-verify-on-origin invariant this repo paid
an incident to learn. **A survives** — and A is where the measured 56 s is.

**The separable insight:** B bundles two things that do not need each other. The *durable failure
inbox* (`refs/land/failed/**` + a `cc-backlog needs` row on every non-zero land exit) needs **no
daemon at all** — the author's own dying process can write both before it exits, and the ledger's
existing renderers surface them afterwards. Recommended composite: **A + B's inbox half** — the 40×
critical-section reduction *and* the close of 4(d), with zero new launchd surface.

### 3.1 Answering 4(d) explicitly — a conflicting / gate-red branch whose author is gone

| Architecture | What happens today / would happen |
|---|---|
| **Today (and A)** | The land is a child of the session process; SIGINT kills it mid-land (7 measured in v2). The exit code and stderr die with the pane. `stranded-sweep --mine` and the `Session-Id:` commit trailer exist, but they are surfaced as "REVIEW, **never auto-recovered**" — and nothing reads them if the session is gone. **Work is not lost (the branch ref survives) but the *notice* is.** |
| **B** | The queue ref and the backlog row are both durable and author-independent. A failed candidate lands in `refs/land/failed/**` with a rendered `👤` row carrying the exact re-land command. Another session — or the dispatcher itself — can claim it. This is the only design where a dead author is a non-event |
| **C** | Same as today for phase 1; phase 2 publish failures are durable because the publisher is not the author's process |

---

## 4. Adversarial self-pass

What I assumed and then had to overturn:

1. **"Batching is the lever."** Refuted by measurement: gate median 0 s, mutex duty cycle 5.6 %,
   capacity ~13× demand. Batching's entire payoff is absent.
2. **"Conflicts are rare, per the brief."** Half-refuted: rare *at land time* (0/1021 in v2) but
   55 %→95 % by branch age 6 h→168 h. The brief's premise is a *consequence of low residency*, not an
   independent property — and that is the fact which kills every residency-adding design.
3. **"The OCC restart loop (17 % exit-42) is the pathology."** Refuted: those acquisitions hold the
   lock a median of **1 s**. The loop is correct and cheap; I was pattern-matching to OCC thrash
   without checking its cost.
4. **"A queue daemon is buildable."** Refuted as a *free* option: agents cannot `launchctl enable`, a
   new label lands disabled, `launchctl print` returns rc=113 with an identical message for disabled
   and not-installed, and this fleet has already had a 13-label blackout.
5. **"The 87 s hold is irreducible work."** Refuted: 55.8 s of it is a read-only sweep, and
   `land-verify.sh` — the only thing that must be in the lock — is 0.485 s.
6. **Axis I initially ignored: revert granularity.** `postland-verify.sh` auto-reverts. Any batching
   design makes the revert unit larger than the authorship unit, so an auto-revert punishes innocent
   authors. TAP escapes this only by having abandoned the green-trunk invariant entirely.
7. **Axis I initially ignored: live-converge coupling.** Any change to land cadence changes the
   `LIVE_ADDS` exposure window, because an ADD breaches at lag 1 while an EDIT rides its symlink.

### Blockers / uncertainties, named

- **`git replay` is EXPERIMENTAL** (its own usage string, git 2.54.0). It ran in 24 ms with the
  worktree untouched, but a lander depending on it depends on an unstable interface.
- **The conflict-by-age table includes dead branches.** 498 refs across 125 worktrees; many will
  never land. The rate is an upper bound on *live* queue conflict risk; the **shape** (monotone in
  age) is the load-bearing part, not the level.
- **The 87 s hold attribution is 56 s confirmed + ~30 s inferred.** push+fetch ≈ 1.5 s and
  land-verify 0.485 s do not account for the remainder; `ship-backup-reap` and the postland enqueue
  are unmeasured. Time the whole in-lock block end-to-end before quoting a specific post-fix number.
- **Meta's land-queue internals are not publicly documented.** That row rests on push-rebase (which
  *is* documented) plus non-authoritative secondary sources for Landcastle/Sandcastle. Do not build
  an argument on it.
- **The v1/v2 split is by date (2026-07-28), not by commit.** If the v2 landing-pipeline rebuild
  landed on a different day the boundary shifts slightly; the qualitative gap (3600 s starvation
  timeouts and 6771 s holds vs none) is far too large to be an artefact of that.
- **`smoke_s` median 0 s partly reflects `smoke=none`/`skipped` on 1009 of 1126 gated lands.** The
  gate is cheap *because it is usually skipped*, not only because it is fast. If gate scope widens,
  the batching calculus changes — though §2.3's residency constraint would still bind.

---

## Sources

- [bors-ng](https://github.com/bors-ng/bors-ng) · [matklad, *GitHub Merge Queue*](https://matklad.github.io/2023/06/18/GitHub-merge-queue.html) · [Graphite, *Not Rocket Science*](https://graphite.com/blog/bors-google-tap-merge-queue) · [Mergify, *Origin Story of Merge Queues*](https://mergify.com/blog/the-origin-story-of-merge-queues)
- [Rust Forge — Bors](https://forge.rust-lang.org/infra/docs/bors.html) · [rust internals — rollup](https://internals.rust-lang.org/t/batched-merge-rollup-feature-has-landed-on-bors/1019)
- [GitHub Docs — Managing a merge queue](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-a-merge-queue)
- [Zuul — Project Gating](https://zuul-ci.org/docs/zuul/latest/gating.html)
- [Ananthanarayanan et al., *Keeping Master Green at Scale*, EuroSys '19](https://dl.acm.org/doi/10.1145/3302424.3303970) · [Morning Paper summary](https://blog.acolyer.org/2019/04/18/keeping-master-green-at-scale/) · [Uber, *Bypassing Large Diffs in SubmitQueue*](https://www.uber.com/blog/bypassing-large-diffs-in-submitqueue/)
- [Memon et al., *Taming Google-Scale Continuous Testing*, ICSE-SEIP '17](https://research.google.com/pubs/archive/45861.pdf) · [*Software Engineering at Google*, ch. 23](https://abseil.io/resources/swe-book/html/ch23.html)
- [Prow/Tide docs](https://docs.prow.k8s.io/docs/components/core/tide/)
- [GitLab — Merge trains](https://docs.gitlab.com/ci/pipelines/merge_trains/) · [GitLab issue #474527](https://gitlab.com/gitlab-org/gitlab/-/issues/474527)
- [Gerrit project configuration](https://gerrit.cloudera.org/Documentation/project-configuration.html) · [tweag/gerrit-queue](https://github.com/tweag/gerrit-queue)
- [Sapling announcement](https://engineering.fb.com/2022/11/15/open-source/sapling-source-control-scalable/) · [Sapling scale docs](https://sapling-scm.com/docs/scale/overview/)
- [Mergify — Performance & the RCV theorem](https://docs.mergify.com/merge-queue/performance/) · [dynamic batch size](https://docs.mergify.com/changelog/2026-06-19-dynamic-merge-queue-batch-size/) · [batch bisection statistics](https://docs.mergify.com/changelog/2026-03-12-batch-bisection-statistics-api/)
- [Aviator — Merge queues for large monorepos](https://www.aviator.co/blog/merge-queues-for-large-monorepos/)
- [Agrawal, Carey, Livny, *Concurrency Control Performance Modeling*, TODS 1987](https://people.eecs.berkeley.edu/~brewer/cs262/ConcControl.pdf)
- [TianPan, *The Merge Queue Is the New Bottleneck* (2026-07-02)](https://tianpan.co/blog/2026-07-02-the-merge-queue-is-the-new-bottleneck) · [Mergify, *State of Merge Queues 2026*](https://mergify.com/reports/state-of-merge-queues-2026)

**Local evidence** (all re-derivable): `~/.claude/land.log` (2934 rows; 1468 lock acquisitions,
2026-07-11 → 2026-08-10) · `scripts/land-lock.sh` · `scripts/ship-land.sh:2079-2250` ·
`scripts/stranded-sweep.sh` · `scripts/land-verify.sh` · `memory/daemon-fleet-v2.md` ·
`launchctl print-disabled gui/$(id -u)` · git 2.54.0 `merge-tree` / `replay` benchmarks run in
`~/Development/claude-infrastructure`.
