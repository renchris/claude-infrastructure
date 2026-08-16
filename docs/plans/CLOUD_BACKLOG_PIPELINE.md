---
status: complete
---

# CLOUD BACKLOG PIPELINE — cc-backlog drained end-to-end through Anthropic cloud VMs

**Mission.** Turn a proven cloud *arm* into a managed *pipeline*: an open `cc-backlog` item is routed
to a venue, dispatched to a cloud VM, steered two-way while it runs, landed, verified live, and
closed — with no human in the loop and no step that depends on someone remembering to poll.

**The state this plan starts from (measured 2026-08-11, one session, four live cloud round trips).**
The arm works. The pipeline does not exist. Both halves of that sentence are load-bearing and neither
is a guess — every claim below was read off the live control plane or the tree, not inferred.

---

## Phase 0 · Agent Team Orchestration

**EXECUTION LOCUS PER WAVE.** Every implementation wave here is **S — a dispatched handoff session**
(the default; no justification needed). The lead holds ≥50% of its window for deciding *which venue
an item belongs in*, which is the judgment this plan exists to encode and the one thing a worker
cannot be handed.

One deliberate exception, and it is a hard constraint rather than a preference: **W1 (the venue
producer) must NOT be built by a cloud session.** It is the component that decides what runs off-box;
a cloud VM building its own admission rule is a circular dependency, and its 50-commit clone cannot
read the history that justifies the exclusions. W1 is a local dispatched session.

| Wave | Locus | Deliverable | Depends on |
|---|---|---|---|
| **W1 · venue producer** ✅ DONE | S (local) | something labels an item `venue=cloud\|local` against the VM's real constraints | — |
| **W2 · management rails** | S | custody + wake + goal + auto-land for a cloud session | — (parallel with W1) |
| **W3 · refusal loop** ✅ DONE | S (local) | a land refusal routes back to the session that caused it | W2 |
| **W4 · cost A/B** | S | the same brief run local vs cloud, both arms measured | — (parallel) |

W1 and W2 are independent (one decides *what* goes, the other manages *what came back*) and should
fire concurrently. W3 needs W2's return path. W4 is measurement and blocks nothing.

**Lead context budget:** recycle at the seam between waves, never mid-wave. Succession point = after
W1+W2 return and their results are landed and content-verified.

---

## 1 · What is already true (do not re-derive; all of it is landed)

- **The create works.** `cc-offload up --via api` fires a two-call sequence — resolve an
  `anthropic_cloud` environment, then `POST /v1/sessions` with `environment_id` + `config.sources` —
  and REFUSES (exit 5) unless the session reads back with `environment_kind: anthropic_cloud` AND
  exactly one `git_repository` source. Mechanism + why it is a different ENDPOINT rather than a
  missing field: `CLOUD_OBSERVABILITY.md` § 13.3/13.4.
- **The land works, unattended.** `cc-offload land --all` re-authors the VM's commits (the VM commits
  as `noreply@anthropic.com`, which GitHub renders as a permanently unattributed grey user and this
  repo's identity gate refuses on purpose), carries provenance in `Cloud-session:` /
  `Original-commit:` / `Original-branch:` trailers, and self-heals a stale same-name local branch left
  by its own failed attempt. § 13.4/13.5.
- **Four items have gone through it.** `08df84d2`, `e950eccb` (the instrument pair), `355975c5` (the
  wrap-ledger memo), plus the original round-trip testimony. All landed on trunk and content-verified.

🚨 **Verify a cloud land BY CONTENT, never by sha.** The land re-authors, so the sha the VM pushed is
never the sha that lands. A checker written against the pushed sha reads "not landed" on a perfect
land. (`git ls-tree` / `git show origin/main:<path>`, never `merge-base --is-ancestor <pushed-sha>`.)

---

## 2 · The gap, stated exactly

**There is no producer.** `bin/cc-dispatch:470` says it in its own words:

> `cc-backlog claim --venue local|cloud` shipped fully built and fully tested with **ZERO PRODUCERS**.

The dispatcher has the plumbing — `fire_venue`, cloud-ineligibility handling, the `--venue cloud`
actuator, 38 references. Measured 2026-08-11: **0 of 294 open items carry a cloud venue**, and the IDL
records 3 cloud mentions ever. Nothing decides what should run off-box, so nothing does.

That decision is not a lookup. Of four briefs triaged by hand this session, **one was rejected
outright** (`7c6ff16259a0` — it patches `scripts/handoff-fire.sh`, the fleet's own spawn rail, flagged
in its own brief as "strands real work box-wide if wrong", and its premise had gone stale against the
same day's landings) and **one needed 215 commits of history inlined by hand** before a VM could
attempt it. A producer that routed on keywords would have sent both.

**And there is no return path.** A local `handoff-fire` gives the lead a notify-back ping, custody
that blocks a false `✅`, a `--goal` re-judged every turn, and mid-flight steering. A cloud fire gives
an id. Everything else this session did by hand:

| # | Gap | What it cost, concretely | Filed |
|---|---|---|---|
| 1 | no wake on completion | the lead polls, or the work sits done and unnoticed | `4f2eaa26ae83` |
| 2 | no custody | a `✅ SAFE TO CLOSE` is reachable with a cloud session mid-flight — the close-integrity mechanism is blind to cloud work | `4f2eaa26ae83` |
| 3 | no `--goal` | nothing re-judges a cloud session against a measurable end state | `4f2eaa26ae83` |
| 4 | gate refusals do not route back | the memo's land was refused by one lint; nothing told the VM. Diagnosed and hand-sent | `4f2eaa26ae83` |
| 5 | `cc-offload say` refuses on a stale binary | it lacks the `CC_CLAUDE_BIN` default `up` carries — the steering arm was DEAD until pinned by hand | `6ad6ec4121d2` |
| 6 | landed results read ELIGIBLE forever | declarations record `paths=` empty, so every sweep re-attempts finished work | `a435e3987fbf` |

Gaps 1-3 are why fire-and-forget is the only available mode today: **the cloud lane has no return
path into the machinery that manages local work.**

---

## 3 · Constraints a worker must be handed (the VM's own testimony)

From `docs/research/cloud-vm-roundtrip-2026-08-10.md`, written from inside the VM, plus
`docs/research/cloud-vm-shallow-clone-blast-radius-2026-08-11.md`:

- **The clone is SHALLOW — 50 commits.** Any brief whose work walks past that (`git show` on an older
  sha, a merge-base against an old branch, blame through the truncation) fails or quietly answers
  wrong. This is the single biggest determinant of cloud-suitability.
- **No `gh` CLI.** GitHub reaches the VM only through MCP tools scoped to one repository. Anything
  needing a PR is out.
- **A remote-tracking ref is seeded at provision time**, so `git branch -r` listing a branch is NOT
  evidence the remote has it. A push-detector keyed on that ref is a false positive.
- **The machine is a Firecracker microVM**, hostname `vm`, `/home/user`, reclaimed at session end.
  Nothing unpushed survives.
- **`~/.claude` does not exist there.** Every laptop-shaped brief step — `cc-backlog claim`,
  `cc-bats`, `ship-land.sh` — is unavailable; the backlog store is machine-local
  (`$HOME/.claude/autonomy/backlog.jsonl`). Claim locally BEFORE firing; the VM commits and pushes,
  the laptop lands and marks done.

---

## 4 · Cost — what is measured, and the one thing that is not

Per-session usage is readable at `external_metadata.usage` on `GET /v1/code/sessions/<id>`.

| session | task | output | cache read |
|---|---|---|---|
| round trip | write one file | 4,080 | 581K |
| instruments | 2 script fixes + 2 test suites | 50,302 | 7.44M |
| wrap-ledger memo | 1 perf fix, 20 tests, a benchmark | 84,109 | 16.4M |

Cache reads dominate and scale with task complexity — 28× across that range. **Idle is free**, proven
two ways: an 11-hour-idle session's usage is byte-identical across reads, and the *older* session has
8× *less* output than a newer one, so usage cannot be time-based. There is no VM line item at all —
the cost is tokens from the account's Max quota, which is why an account at 100% weekly is the real
ceiling.

✅ **MEASURED 2026-08-11 — cloud does NOT cost more than local for the same task; it costs slightly
less, inside the noise.** Full method, raw per-session numbers, controls and threats:
`docs/research/cloud-local-cost-ab-2026-08-11.md`. The same brief (write one stdlib tool + a unittest
suite, run it green, commit, push) ran n=2 per arm, same account (next3), same model
(`claude-opus-5`), measured on the same four axes — the cloud instrument's
`input/output/cache_read/cache_write` map exactly onto the transcript's
`input/output/cache_read_input/cache_creation_input`:

| arm (mean of 2) | input | output | cache read | cache write | wall |
|---|---|---|---|---|---|
| cloud VM | 24 | 7,423 | 785,160 | 72,557 | 437 s |
| local dispatched session | 21 | 6,829 | 1,087,033 | 88,916 | 410 s |
| **cloud ÷ local** | — | **1.09** | **0.72** | **0.82** | 1.07 |

Price-weighted that is **≈0.81× local**, robust to the cache-write TTL multiplier. **But the spread
within the local arm (877K–1,297K cache read) exceeds the gap between the arms (302K), so the claim
is parity trending cloud-cheaper, not a win** — the experiment can refute "cloud costs much more"
and cannot resolve a difference under ~30%.

🚨 **The a priori case in this section's earlier draft was backwards on both halves, and that is the
finding.** (1) The cold shallow-clone VM is the *lean* arm: the local session's FIRST TURN establishes
~80K cache-write tokens — 89–92% of everything it caches all session — because `~/.claude`, both
`CLAUDE.md`s, the hooks, the memory index and the tool schemas load there and do not exist on the VM,
whose *entire* session cached less than that one turn. What inflates a session is our own laptop
configuration, not the clone. (2) "Does not consume the lead's context" is a property of
**dispatching**, not of the cloud — a fired local session's tokens land in its own window too. What
cloud uniquely spares is this box's CPU, RAM, pane and worktree. **So routing to cloud is a CAPACITY
decision, not a cost one**, and W1's admission rule should turn on the VM's constraints (shallow
clone, no `gh`, no `~/.claude`) rather than on a cost penalty that does not exist at this size.

⚠️ Still unmeasured, and named so it is not assumed away: **task-size sensitivity**. This A/B sits at
the small end of the 28× range in the table above. The local preamble is a FIXED ~80K cost while the
task-driven term grows, so cloud's relative advantage should *shrink* with task size — untested.

---

## 5 · Definition of done

The pipeline is done when an open `cc-backlog` item reaches `done` with **no human action and no lead
polling**, and each of these is demonstrated on a real item, not a fixture:

1. a producer labelled it `venue=cloud` and can articulate why (and correctly refuses an item that
   needs deep history, a PR, or touches the spawn rail)
2. it dispatched to a cloud VM without a hand-written brief
3. custody opened at fire, so a close during its flight is mechanically impossible
4. a goal was armed and evaluated against a measurable end state
5. its completion WOKE the lead rather than being polled for
6. a gate refusal routed back to the session and it amended without a human reading the log
7. it landed, was content-verified on trunk, and the item was marked done
8. the live layer carries the result (landed ≠ live — the `🚀` rung)

**Anti-goal:** a pipeline that dispatches blind. A wrongly-routed item is worse than an unrouted one —
it burns quota, produces a plausible-looking wrong answer against missing history, and reports success.

---

## 6 · W2 — the management rails, built (2026-08-11)

**A cloud fire is now a managed fire.** Rows 1-3 and 5-6 of §2's gap table are closed; row 4 (the
refusal→VM routing loop) is W3 and only its return-side artifact is built here.

| Gap | Closed by | Where the mechanism lives |
|---|---|---|
| 1 · no wake on completion | `scripts/cloud-return.sh` → `cc-notify <pane>` | the launchd sweep, never the originator |
| 2 · no custody | `cc-offload up` → `cc-custody open` at the fire | marker = the session id; discharged only on a content-verified land |
| 3 · no goal | `--goal` / `--goal-probe` on the declaration | evaluated FROM THIS SIDE, never inside the VM |
| 4 · refusals do not route back | *(W3)* — but `<id>.land-refused` is written, and the originator is woken with the failure | the seam, left deliberately |
| 5 · `say` refuses on a stale binary | `c13be247` — both call sites carry the binary default | falsifier retracted |
| 6 · landed results read ELIGIBLE forever | `82bb38f4` + `12819616` — `cc-cloud fill-paths`, called after a land | falsifier retracted |

**The two decisions that were not obvious.**

🚨 **`worker_status: idle` PROVES NOTHING, and the completion rule had to be built around that.**
Measured against the live control plane on 2026-08-11: a session that finished 14 hours earlier and
a session fired **4 minutes** earlier both read `worker_status: idle` / `status_bucket: review_ready`.
Idle is the between-turns state as much as the finished state — structurally the same trap as the
harness's own `idleReason`, which is painted "finished" at every Stop. A return keyed on that flag
alone would cut a live session off mid-flight and land a half-finished branch, which is worse than
never returning. So RETURN-READY is a **conjunction of three independent facts**: the VM has pushed
(cc-cloud's verdict), the worker is not running (the *trigger*), and the pushed sha has been **quiet
for 180 s** — the third being the axis that is independent of the flag, which is the only reason it
carries any weight.

🚨 **The poller cannot be the originator, and this is a hard constraint rather than a preference.**
A goal-armed session may not hold a backgrounded watcher at all: Claude Code skips `/goal` evaluation
while any non-terminal background Bash exists, and `hooks/validate-bash.sh` denies the park outright.
So the poller lives in **launchd** — `scripts/autonomy-sweep.sh` (com.chrisren.autonomy-sweep, loaded,
300 s) calls `cloud-return.sh --sweep`, **above** the nothing-new early exit, because a finished cloud
session produces no page and no alarm and would otherwise be measured only on sweeps that already had
other news. The wake itself rides the same v2 inbox transport a local peer uses.

**The sweep's population is what the sweep armed.** `--sweep` acts only on declarations carrying
`notify_back` or `custody`. Twenty-plus pre-W2 declarations exist on this box, several with pushed,
never-landed branches; sweeping those would be the script deciding unattended that a three-day-old
stranded branch belongs on trunk. `--id` still lands one a person names.

**What is guarded, and what it cost to find.** Every arm that could launder a false completion is
pinned: an unreadable control plane abstains; a lander that reports success while landing nothing is
caught by the content check, with custody and the backlog item both left OPEN over it; a refused land
does not latch, so the next sweep retries. Two defects were found by the suite rather than by reading
— a fill whose missing-tool branch returned 0 *silently* (a caller muting its callee's non-verdict),
and a wiring test that grepped the phrase `nothing-new`, which appears in three comments **above** the
exit it names, so it measured a sentence and convicted a correct call site.

### 6.1 · Demonstrated on two REAL round trips — and the second one is why there were two

| clause (§5) | evidence |
|---|---|
| 3 · custody opens at fire | `cc-custody count --open` = 1 the instant `up` returned, marker = the session id, both runs |
| 4 · a goal armed + evaluated | `goal=` / `goal_probe=` on the declaration; verdict `MET` computed from THIS side, both runs |
| 5 · completion WOKE the originator | `HANDOFF-PING cloud/<id>: LANDED+VERIFIED …` arrived in pane 348's inbox as CONTEXT, un-typed |
| 7 · landed, content-verified, item done | `docs/research/cloud-w2-return-rails-2026-08-11.md` blob `deee981d` on `origin/main`; `e9a745a7ffb9` done; custody 0 |

Run 1 `session_013H8jXq…` (next), run 2 `session_017ga3J7…` (next3). The landed commits are authored
`Chris Ren <ren.chris@outlook.com>` carrying `Cloud-session:` / `Original-commit:` /
`Original-branch:` — the identity wall translated, not weakened.

**Four defects that only a live round trip could produce**, every one of them an instrument reporting
something adjacent to the truth:

1. **The post-hoc fill was self-defeating.** The range is bounded at the merge-base with the trunk,
   so the moment the land succeeds the branch IS on trunk and the range is empty. It refused over a
   branch that had just landed a file. `fill-paths` now splits `--print` (derive while ahead) from
   `--set` (write after), and an already-landed branch NAMES that cause instead of reporting a bare
   emptiness. **The suite missed it because its lander stub never advanced trunk** — a control that
   does not replay the real post-land artifact cannot fail the way production does.
2. **The rail called the DEPLOYED copy of its own sibling.** `cc-cloud` was resolved from the
   declared repo (the shared checkout) and `~/.claude/bin`, which symlinks into it — 8 commits
   behind — so a freshly-landed reconciler got `unknown arg fill-paths`. A rail must call the
   siblings it shipped with, or every fix is hostage to the converger.
3. **A test suite could land a branch.** `tests/autonomy-sweep.bats` runs the real sweep once per
   test and `postland-verify` runs that suite from a throwaway worktree — measured: FOUR concurrent
   `cloud-return --sweep` passes against the operator's LIVE store, racing the backlog ledger and
   re-pinging the originator. Every other block in that sweep is a pure read; this one acts. The
   stanza is now gated on the UNRESOLVED `$0` being the deployed path (resolving it follows the
   symlink back into the checkout and erases the only difference there is).
4. **A land CUT by a bound was filed as a gate REFUSAL.** The 240 s bound — chosen "to stay under
   the 300 s cadence" — killed a healthy land that `ship-land` itself described as
   `verdict=killed signal=SIGTERM … nothing was proven about the tree`, and the return path wrote a
   refusal artifact, woke the originator with "LAND REFUSED", and pointed W3 at a routing job that
   does not exist. A bound smaller than what it bounds can only convict. Now 900 s, with 124/137/143
   and the lander's own killed token abstaining.

⚠️ **A goal probe runs with cwd = the declared repo, which is a working tree somebody else owns.**
Write probes against the trunk ref (`git show origin/main:<path> | grep -q …`), not the working tree:
a bare `grep -q X path` grades whatever happens to be checked out, and grep's exit 2 (no such file) is
indistinguishable here from a real miss — so a probe can read NOT-MET over work that landed perfectly.

---

## 7 · W3 — the refusal loop, built and demonstrated live (2026-08-11)

**§2's gap row 4 is closed: a gate refusal now reaches the machine that caused it.** W2 left the
seam deliberately — it wrote `<id>.land-refused`, woke the originator, and stopped.
`scripts/cloud-refusal-route.sh` is the other half: it reads that marker, decides who can actually
clear the refusal, and sends the gate's OWN verdict text off-box over `cc-offload say`. No second
refusal store, no second wake rail, no re-implementation of the land — `cloud-return`'s next pass
still owns the re-land, so the circuit closes through machinery that already existed.

| Gap | Closed by | Where the mechanism lives |
|---|---|---|
| 4 · refusals do not route back | `scripts/cloud-refusal-route.sh`, called from `autonomy-sweep.sh` one step AFTER the return pass | classification + routing only; the re-land is `cloud-return`'s next pass, unchanged |

**Four rules, and each is a defect this repo had already paid for once.**

1. **A land CUT by a bound is a NON-VERDICT** (`d079576e`). Recorded, never routed, and it spends
   **no cycle** — otherwise a busy box exhausts a session's whole budget without one real refusal
   ever being sent.
2. **The identity wall is BY DESIGN** (§13.4-13.5) and must not enter the loop. The VM cannot change
   who authored its commits, and the re-authoring land already answers it.
3. **Fixable-by-VM is decided by asking whether the gate NAMED one of the VM's own files** — the set
   derived from its own commits by W2's `fill-paths`, never "the most recent session". The search
   runs in that direction on purpose: the naive form scrapes paths out of the verdict and convicts
   `scripts/desk-land.sh`, which the lander's preamble names in every artifact ever written.
4. **The default direction is HOME, never off-box.** A wrong VM route spends quota, hands a
   confident brief to a machine that cannot act on it, and is discovered only by exhausting the
   bound; a wrong originator route costs one ping. Uncertainty routes home.

The cycle counter lives in `<id>.refusal-route`, not in the marker, because `cloud-return` writes
the marker with `>` — a counter inside it would be reset by the very event it bounds and the loop
would run forever reading `cycle 1` (memory: counter-resets-at-the-boundary-the-runaway-crosses).
Bound: **2 VM cycles**, then the originator is woken with the chain PRINTED, never a silent loop
and never a silent give-up. `--chain <id>` renders it on demand; `--classify <file>` is a pure read.

### 7.1 · §5 clause 6, demonstrated on a real round trip

`session_01HEudSuWY9hLk2Y5jqqX7Nr` on next3, branch `claude/fire-20260811T202615Z-68218-1`. The
refusal was INDUCED (the brief asked for a probe suite that reads `$HOME`) but nothing about the
loop was: a real lint, in the real land gate, refused a real push, and the VM fixed it.

| step | evidence, timestamped |
|---|---|
| the VM pushed | `bc46a12` — the memo + `tests/w3-gate-probe.bats` |
| a REAL gate refused | 20:51 · `test-hermeticity-lint: ⛔ 1 new non-hermetic suite(s)` → `✗ ship-land: GATE RED` → `cloud-reconcile` exit 70 → `<id>.land-refused` |
| classified | `arm=vm`, `match=basename:w3-gate-probe.bats` — see the basename finding below |
| routed off-box | 20:45:21 · `cc-offload say` → `verdict=cloud-queued reason=api-ok`, carrying the lint's own LEAK line **and its `Fix:` remedy** |
| **the VM amended** | 20:46:17 (**56 s later**) · `e6c3569` *"fix(tests): fixture $HOME in the w3 gate probe setup"* — the diff is the lint's remedy verbatim: `export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"` |
| the re-land succeeded | `9270197a8` + `67dca77aa` on `origin/main`, re-authored `Chris Ren <ren.chris@outlook.com>` |
| content-verified | `docs/research/cloud-w3-refusal-loop-2026-08-11.md` blob `2c1aeed3` · `tests/w3-gate-probe.bats` blob `71a9c39b` (the FIXED tree) |
| W2's rails closed out | `LANDED+VERIFIED on origin/main · goal: MET · discharged session_01HEudSuWY9hLk2Y5jqqX7Nr` |

**No human read the log.** The only thing a person did between the refusal and the fix was run the
router; the diagnosis, the remedy and the amend were the gate's text and the VM's own work.

Two other live artifacts on this box exercised two more arms on real data rather than fixtures:
W2's `rc=143` artifact classified **`cut`** (recorded, not routed), and its landed sibling
classified **`STALE`**.

### 7.2 · Three defects the hermetic suite could not produce, and the first two are one defect

**A substring match on a bare TOKEN that the tooling also prints as VOCABULARY.** Both were live,
both were invisible to 37 green hermetic cases, and one of them fired on the very first artifact.

1. **`GATE-KILLED`.** `desk-land` surfaces an exit-code LEGEND on every non-zero ship rail —
   `(2 dirty/preflight · … · 9 GATE-KILLED · 75 LOCK-STARVED)` — so the token is in the body of
   every refusal there will ever be. The first real artifact, an ordinary hermeticity RED, was
   classified `cut` and **not routed**: the loop would have been silently inert on precisely the
   event it exists for. Anchored on the emitter, `ship-land: GATE-KILLED`.
2. **`git-identity`.** `ship-land` prints `→ gate: git-identity escape ratchet (…)` as a PROGRESS
   line whenever that arm RUNS, green or red. A bare match would have sent HOME every refusal
   raised by any LATER arm — utc-stamp, self-path, pane-spawn, permission-gate, bats, smoke — i.e.
   most of the gate, while working correctly for the handful that run before it. Never triggered
   live; found by reading the real artifact against the gate's own source. Anchored on
   `gate: git-identity RED`.

The remedy generalises past the two: **the fixtures now TRANSCRIBE the first real artifact** — the
shared `preamble()` carries the git-identity progress line and `desk_tail()` carries the legend — so
all four known traps ride in every body and a regression reds every arm rather than one.

3. **A refusal can be TRUE about a tree the VM has already replaced.** A land takes minutes; a VM
   answering a routed refusal pushes in about one. The second land fetched at bc46a12, the fix
   reached origin at 20:46:17 as e6c3569, and the gate reported bc46a12's lint at 20:51:21 — same
   file, same remedy, already applied. Routing it spends a cycle telling a machine to redo its own
   work, and the second identical message is how a loop teaches its subject that the loop is noise.
   Two guards, because the case has two shapes and each is blind to the other:
   - **SUPERSEDED** — `cloud-return` now records `seen_sha=` (WHICH PUSH the gate judged) in the
     artifact, so it is one comparison against the live sidecar rather than an inference. No cycle
     spent. An artifact without the field is routed rather than held: absence is not evidence.
   - **STALE by the LOCAL RE-AUTHORED REF** — the content arm needs a path set, and that is exactly
     what is missing here: `fill-paths` derives from the branch's range against the trunk, which is
     EMPTY once it lands, and a REFUSED land never wrote `paths=`. So the commonest stale refusal —
     a losing concurrent land whose sibling already put the work on trunk, which is *what actually
     happened* — was invisible to the guard.
     ⚠️ **This is not §1's forbidden check.** That rule is about the sha the VM PUSHED, which never
     lands because `cloud-reconcile` re-authors. `refs/heads/<branch>` in the declared repo is the
     other object: the re-authored range the lander built and pushed, and the same ref `cc-cloud
     fill-paths` uses to name its own already-landed cause.

⚠️ **Two lands ran concurrently on one branch and that is how the work landed at all** — the one
that fetched before the fix went RED, the one that fetched after landed it. It ended well by
luck, not by design, and the losing land's refusal is what defect 3 exists to absorb. Whether
`cloud-return`'s single-flight lock should also bar a second land of the SAME BRANCH is named here
as open rather than assumed away: the lock is per-pass, and the `--id` path a person names bypasses
nothing.

**Coverage:** `tests/cloud-refusal-route.bats`, 46 hermetic cases — every routing arm paired with
the control that must NOT route, over bodies differing only in the axis under test, plus four
structural wiring arms (a hermetic suite cannot see whether anything CALLS the script it tests).

## Status log

- **2026-08-11** — plan opened. Arm proven end-to-end (create + land + 4 items landed); pipeline
  absent. Gaps enumerated from live failures, not speculation; filed `4f2eaa26ae83`,
  `6ad6ec4121d2`, `a435e3987fbf`. Cost measured for the cloud arm; local arm deliberately unmeasured.
  Next: W1 (venue producer, local session) + W2 (management rails) concurrently.
- **2026-08-11 (dispatch)** — W1 fired → pane 347 / next3 / worktree `w1-venue-producer`; W2 fired →
  pane 348 / next2 / worktree `w2-cloud-rails`; W4 fired → pane 349 / next3 / worktree `w4-cost-ab`.
  All three goal-armed (verified from their own transcripts) with custody open against the lead
  (pane 345). W2 owns the three filed gap items; W4 measures §4's open question. W3 holds for W2's
  return path. One fire-lint lesson: a brief that NAMES the notify binary without a resolvable
  target is refused (F3) — reference the rail generically, the fire materializes the trailer.
- **2026-08-11 (close) — BUILT; §5 acceptance 22/22 against live state** (runner output in the
  lead's transcript). W1 landed `30e9b189b`: 48 cloud labels / 254 recorded refusals across 8
  classes on real items; its promoted-bucket audit caught the plan's own rejected brief
  (`7c6ff16259a0` → the `ineligible-offbox-lane` class). The lead's blind 27-item adjudication
  then caught 2 producer mislabels → 3 spellings + 6 lookalike-paired tests landed `c459b9ebc`,
  both items relabeled on the trail — the standing audit is real, run it each wave. W2 landed the
  rails (custody-at-fire · goal on the declaration judged from this side · wake over the v2 inbox
  · auto-land · mark-done), demonstrated on two REAL round trips; falsifiers for `6ad6ec4121d2` /
  `a435e3987fbf` exit 0 on trunk; all three gap items done. W3 landed the refusal loop
  (`3c9511849`…`8bd23b371`): a real hermeticity red routed to the causing VM, which pushed the
  lint's own remedy 56 s later; re-land content-verified; 46/46. W4 measured §4's open question —
  cloud ≈0.81× local price-weighted, parity trending cloud-cheaper, and the a priori case was
  backwards both ways (the local preamble out-caches the VM's whole session; "spares the lead" is
  a property of dispatch, not of cloud — cloud is a CAPACITY choice).
  **Integration findings only the first real fire could produce, all fixed + landed:** the
  dispatcher's cloud leg was the deprecated CLI create — it delivered NO brief (sessions sat
  NOT-STARTED forever) and the follow-up declare OVERWROTE the leg's correct declaration with the
  worktree as branch, so the reconcile watched a branch the VM would never push; and every
  dispatcher fire was born OUTSIDE the sweep's managed population (no custody/notify-back on the
  declaration). Fixes: the cloud actuator is now `cc-offload up --via api` (`04bde65ee`), the
  declare carries item+custody+account+notify-back with custody opened at the fire (`7fa0f1197`),
  and cloud_declare ADOPTS an existing declaration rather than re-declaring (a late re-declare
  would also re-probe the push baseline). Fire #1 (`session_01YcTifmgrKh`, item `38de29ec5e59`)
  is preserved as the forensic stray; its claim self-released clean. Five admission-clogging
  stale items were retired on the actuator's own premise-refuted verdicts — refused-but-open
  items burn the whole admission budget every pass (follow-on class, filed by the machinery's
  own IDL rows). **Operator policy, filed:** the launchd dispatcher runs `CC_FIRE_CLOUD` off, so
  autonomous cloud spend is opt-in — flipping it is the one decision that turns the pipeline's
  cron arm fully on. Landed-not-live tail: lag 16/1h inside the 25/6h budget; W3's added route
  script rides the next converge (`d28f79099ec9`).
- **2026-08-11** — **W4 DONE.** §4's one unmeasured question is measured: the same brief ran n=2 per
  arm (cloud VM vs local dispatched session, same account, same model) and cloud came in at 0.72×
  local cache reads / 0.82× cache writes / 1.09× output — ≈0.81× price-weighted, but inside the
  local arm's own spread, so the verdict is **parity trending cloud-cheaper, scoped to small
  self-contained tasks**. Two a priori claims in the original §4 were refuted by the numbers: the
  cold shallow-clone VM is the LEAN arm (the local preamble alone, ~80K tokens on turn 1, exceeds the
  VM's whole-session cached context), and "spares the lead's context" is a property of dispatching
  rather than of the cloud. Cloud is therefore a CAPACITY choice, not a cost one. Deliverable
  equivalence was controlled, not assumed (all four branches produced the same three files and their
  suites were executed here: 10/9/9/9 tests, all green). Doc:
  `docs/research/cloud-local-cost-ab-2026-08-11.md`. Open follow-on named there: task-size
  sensitivity at the 50K-output end.

- **2026-08-11 — W1 LANDED. §5 clause 1 is met: something decides, and it refuses correctly.**
  `bin/cc-venue` is the producer §2 says shipped with zero of. It writes `venuePlan`/`venueWhy` onto
  open rows; `bin/cc-dispatch` reads the plan at the one seam a fire is composed and appends
  `--cloud` to the argv, so `fire_venue` still derives the label from what actually ran.

  **The decision is four questions, not a lookup.** `bin/cc-eligible` — imported as a module, never
  re-derived, so the report and the claim-time refusal are one code object — answers three of them:
  its spelling classes, a MEASURED history arm, and whether this box can certify at all. The fourth
  is `cc-premise`, re-run at decision time.

  **The measured arm.** A cited sha is reachable iff it resolves AND sits inside the newest 50
  commits of the trunk a VM would clone. A sha that does NOT resolve is deliberately silent — this
  clone is full and the VM's is a subset, so a non-resolving token is a dead pointer or a 12-hex
  backlog id, and convicting on it would refuse most of the store.

  **The guard is keyed on the effect, so the circularity constraint in Phase 0 is mechanical rather
  than remembered.** A grafted clone has every resolvable sha inside its own horizon by
  construction, so the arm would answer REACHABLE to everything. `certify()` returns `shallow` and
  the producer will not mint a cloud label without `ok`. On a VM that fires automatically.

  **Gate fails OPEN, producer fails CLOSED, and both are right.** The gate must never starve a
  claim on a missing file, and a wrong INELIGIBLE only leaves an item where it already is. The
  producer promotes work into a venue where a wrong answer cannot be SEEN, so every uncertainty
  routes local with the reason recorded.

  **What reading the promoted bucket found, which is the result worth carrying forward.** The first
  `cc-venue run` ever printed contained **`7c6ff16259a0` — the brief §2 names as REJECTED
  OUTRIGHT.** It is invisible to every spelling: its span never says handoff-fire, pane or launchd.
  It says "off-box payload", "cc-cloud preflight", "unblock the cloud lane". That produced
  `ineligible-offbox-lane` — *the lane cannot verify a change to itself*, the same circularity
  Phase 0 applies to W1, generalised one step — which also catches `e15a743e12ba`, an item asking to
  edit the venue rule itself. Sixteen further spellings came out of the same read (this kernel's
  signals/jetsam/sysctl, a live daemon tick, the session machinery, CDP). **The anti-goal was
  reachable with the classifier as first written; auditing the output is what closed it, and that
  audit is a standing duty, not a one-time pass.**

  Measured on the live store (302 open): **48 cloud · 254 local across 8 recorded reasons** —
  `ineligible-box` 155, `ineligible-spawn-rail` 24, `ineligible-branch-banking` 25,
  `ineligible-visual` 16, `ineligible-deep-history` 15, `ineligible-offbox-lane` 10,
  `premise-falsified`/`suspect`/`superseded` 9. The GitHub class (`ineligible-github`) is real but
  every member is operator-`blocked`, hence `cc-venue label <id>` for rows `run` skips.

  71 bats cases across `cc-eligible-history` · `cc-backlog-venue-plan` · `cc-venue` ·
  `cc-dispatch-venue`, every refusal paired with a control that must stay eligible.

  **Not done here, and named rather than implied:** W1 is decision-side only. No cloud session was
  created; the round trip is the lead's integration pass after W1+W2. `--cloud` remains
  default-off per box (`CC_FIRE_CLOUD`), and the dispatcher honours a cloud plan only where that
  actuator would accept it — a cloud-labelled item on a box without the opt-in fires LOCALLY and
  the IDL records the unhonoured plan, rather than becoming a fire failure that strands exactly the
  work the producer routed.

- **2026-08-11 — W3 LANDED. §5 clause 6 is met: a gate refusal reached the VM and the VM fixed it,
  with no human reading a log.** Full account in §7. One real cloud session
  (`session_01HEudSuWY9hLk2Y5jqqX7Nr`, next3): a real hermeticity lint refused the land, the
  verdict was classified `arm=vm` and sent over `cc-offload say`, and **56 seconds later** the VM
  pushed the lint's own remedy verbatim. Both files are content-verified on `origin/main`
  (`9270197a8`, `67dca77aa`); `LANDED+VERIFIED · goal MET · custody discharged`.

  **The finding worth carrying forward is that the suite was wrong in a way only a real producer
  could show, twice, in the same way.** 37 green hermetic cases, and the FIRST real artifact was
  misclassified: the classifier matched `GATE-KILLED` and `git-identity` as bare tokens, but
  `desk-land` prints an exit-code LEGEND on every failure and `ship-land` prints
  `→ gate: git-identity escape ratchet` as a PROGRESS line. Both tokens are VOCABULARY, present in
  bodies that mean the opposite. The first would have made the loop silently inert on the exact
  event it exists for; the second would have sent home every refusal raised by any arm after
  git-identity — most of the gate. The fixtures now TRANSCRIBE the real artifact so all four known
  traps ride in every test body (§13.5's lesson, met from the inside one layer up).

  A third defect followed from the timing rather than the text: **a refusal can be TRUE about a
  tree the VM has already replaced.** A land takes minutes, a VM answers in about one, and the
  losing half of a concurrent land filed a refusal naming a file the VM had already fixed. Guarded
  two ways (`seen_sha=` supersession, recorded by `cloud-return`; staleness by the LOCAL
  re-authored ref, which is the one available when a refused land left `paths=` empty).

  Named as open, not assumed away: two lands ran concurrently on one branch and it ended well by
  luck. Whether the return path should bar a second land of the SAME branch is §7.2's open item.

  Coverage: `tests/cloud-refusal-route.bats`, 46 cases. Wiring: `autonomy-sweep.sh` calls the router
  one step AFTER the return pass (which is what files the artifact) and above the nothing-new early
  exit, under the same deployed-copy guard — stricter here, because this one hands a real VM a
  brief it will act on.

---

# NEXT PHASE (2026-08-11) — the migration is LIVE, and three questions it exposed are open

**Status correction: this document's `status: complete` describes the ARM, and the arm is no longer
the whole story.** As of 2026-08-11 the dispatcher runs `CC_FIRE_CLOUD=on` +
`CC_DISPATCH_VENUE_ONLY=cloud` with no pause — cloud-only, by operator directive ("fully migrate
cc-backlog from local spawn to cloud spawn"). What that migration exposed is below, and none of it
is answered.

## What is true today, measured — do not re-derive

| fact | value | how |
|---|---|---|
| dispatcher argv (live) | `CC_FIRE_CLOUD=on CC_DISPATCH_VENUE_ONLY=cloud` | `launchctl print gui/$UID/com.claude.dispatcher` |
| local pane spawns since the pause | **frozen at 191** | `grep -c '→ fired: claude' ~/.claude/logs/dispatch-fires.log` |
| the filter, proven honoured by the DEPLOYED binary | `venue-only=cloud parked 272 of 315 dispatchable item(s)` | one pass with the pause still on; 0 local spawns |
| venue split of the live queue | **45 cloud · 236 local · 31 unlabelled** of 312-315 (it moves) | `cc-backlog list --open --json` folded on `venuePlan` |
| first uncaged pass | **⛔ QUOTA CLIFF — abstained, paged, NO spawn** | `cc-dispatch --once` |
| account state at that cliff | 5h used **1-8%** on all four; weeklies 7-51% | `claude-accounts --readout` |

🚨 **The cliff is the live blocker and it is NOT exhaustion.** A quota cliff fired while every
account sat at 1-8% of its 5-hour window. Either the cliff predicate is wrong, or it is reading
something other than 5h/weekly headroom (Fable? a per-window projection? a stale cache?). **No
dispatcher-driven cloud session has EVER been created** — the 32 cloud declarations on this box are
all hand-driven from the W1-W3 pipeline work. So the cloud arm is armed, filtered, and unproven
end-to-end.

## The three open questions (the successor's brief)

**Q1 · Can cloud reliably drain the backlog — what can it take, what can't it, and WHY?**
Start from the cliff above: until a dispatcher-driven cloud session exists, "cloud is migrated" is a
configuration claim, not a behavioural one. Then the ceiling: `cc-eligible` refuses 236 of 312 rows
by MEASUREMENT, not by keyword — `ineligible-box` 155, `spawn-rail` 24, `branch-banking` 25,
`visual` 16, `deep-history` 15, `offbox-lane` 10. The VM's constraints are the shallow 50-commit
clone, no `gh`, no `~/.claude`, reclaimed at session end (§3). **Which refusal classes are inherent
to a Firecracker VM and which are artefacts of how we provision it?** `deep-history` in particular
looks provisioning-shaped, not physics-shaped. Raising the migrated share means changing what the VM
can REACH — never loosening the predicate, which is §5's anti-goal.

**Q2 · One consolidated track for everything, or two tracks that must not diverge?**
The operator wants "up to date, not stale, most optimally consolidated" — ideally ONE track covering
all work. If cloud can only ever take ~14%, that is two populations with two venues, and the
question becomes how they stay CONSISTENT rather than how they merge. The readiness machinery landed
today is the substrate either way: the admission conjunction (`CC_DISPATCH_READY_GATE`, advisory —
60% would-block, dominated by items that cite no files), the filing-day probe screen
(`cc-premise screen`), and the mechanical fold (`--fold`, dry-run in the sweep). **Does a two-venue
world need two ratchets, or one metric with a venue dimension?**

**Q3 · Cloud continuous, local on a schedule or an explicit switch.**
The operator's constraint is their ~15 concurrent session slots: local dispatch competes with them
for panes, cloud does not (the A/B measured cost at parity — cloud's whole value is that it spares
the box, §4). So: cloud runs continually; local runs on set hours, or when the operator says on/off
(chiefly when they are away). `CC_DISPATCH_VENUE_ONLY` already makes the venue split a config
change (`=cloud` / `=local` / unset), so the lever exists — **what is missing is the SCHEDULER and
the operator switch**, plus the question of whether a time-based window or an explicit toggle is the
right primitive. Note the interlock lesson before touching any of this: a config flip is not live
until the binary that READS it is live.

## The landmine, stated so the successor does not repeat it

**A config flip that BOTH removes a guard and adds a control lands in two different readers.** The
removal (launchd env) takes effect immediately; the control (a new variable the deployed binary must
implement) takes effect only after the live layer converges. Attempted as one step, this fired 2
local panes: `~/.claude/bin/cc-dispatch` is a per-file symlink into the shared checkout, and a shell
program SILENTLY IGNORES an env var it does not implement — there is no arity error. The interlock
now written into `launchd/com.claude.dispatcher.plist` is the general form: land → converge → PROVE
by positive control → only then remove the guard.

---

# ANSWERS (2026-08-11, successor session) — the cliff is named, and cloud has run

## A1 · THE QUOTA CLIFF WAS NEVER ABOUT QUOTA — it was three of four accounts failing a FRESHNESS test

**Root cause, named with the code path.** The cliff record carries its own diagnosis; it was never
read. `~/.claude/autonomy/idl.jsonl` line 77973, the one and only `quota-cliff` record on this box:

```json
{"actor":"cc-wave-plan","action":"wall","verdict":"capacity",
 "detail":"wave of 6 items exceeds capacity (1 accounts, 2 slot(s) total — all capped)",
 "evidence":{"oracle_rc":0,"rank_rc":0,"route_rc":0,"ranked_n":1,
   "accounts":[{"acct":"next","session_pct":4},{"acct":"next4","session_pct":8},
               {"acct":"next3","session_pct":6},{"acct":"next2","session_pct":1}],
   "stderr_excerpt":"claude-accounts: general excluded — next=poll throttled ↻ (cached usage); next4=poll throttled ↻ (cached usage); next2=poll throttled ↻ (cached usage)",
   "reason":"wave-overflow","action":"reduce-wave-size"}}
```

Four accounts, all `state: ok`, all at 1-8% of their 5-hour window. **`ranked_n: 1`.** The chain, in
four steps, each in code:

1. **The exclusion.** `bin/claude-accounts:1086-1088` marks a row `poll_throttled` and sets
   `error = "poll throttled ↻ (cached usage)"` when the OAuth usage endpoint 429s and the row
   inherits its last-good usage. An errored row is excluded from `--route`/`--rank`
   (`bin/claude-accounts:3041`), and the router excludes any row carrying `quota_as_of` — i.e. any
   INHERITED row — *by construction* (`bin/claude-accounts:3925` comment). This is a **data-freshness**
   exclusion. It says nothing about headroom, and the excluded accounts had 92-99% of their window free.
2. **The collapse.** `bin/cc-wave-plan` computes capacity as `ranked_n × per-account allowance`
   (flat `CC_WAVE_MAX_PER_ACCT`=2, widened to 4 for an account the urgency term marks BEHIND). With
   3 of 4 accounts excluded, capacity fell from ~8-10 slots to **2**.
3. **The overflow.** `bin/cc-dispatch` presented a wave of 6 (`CEILING`=6, `free_slots`=6,
   `live_workers`=0). 6 > 2 ⇒ `WALL[capacity]`, exit 4, with `reason: wave-overflow` and
   `action: reduce-wave-size` on the record.
4. **The mislabel.** `bin/cc-dispatch:1760-1764` maps **every** exit 4 to
   `⛔ QUOTA CLIFF — abstained, paged, NO spawn (run /limit-recover)`. cc-wave-plan is deliberately
   trichotomous — it distinguishes `capacity`/`wave-overflow` from a genuine all-capped wall, and
   its own suite pins that discrimination (`bin/cc-wave-plan:939-948`) — and cc-dispatch throws the
   distinction away at the consumer. `/limit-recover` is the wrong operator action for a wave that
   is merely too big; the record's own `action` field already said `reduce-wave-size`.

**The generator was already fixed, one commit before this session started.** `0ffe96995`
(*"the warmer polled tighter than the throttle it warned about"*) found `com.claude.accounts-keepwarm`
polling every 60s against a ~90s endpoint throttle, which kept 3 of 4 accounts permanently throttled
and therefore permanently unrankable. Verified LIVE this session — `launchctl print
gui/$UID/com.claude.accounts-keepwarm` reads `run interval = 180 seconds` and `--max-age 90`, so the
fix is converged, not merely landed. Re-probed after: `cc-wave-plan` ranks **4 accounts / 10 slots**
and places a 10-item wave; it walls only at 12.

**So the cliff is cleared — but the mechanism that produced it is not.** Capacity is
`ranked_n × allowance` while the wave is a fixed `CEILING`=6. At 4 accounts capacity is 8-10 and 6
fits; at 3 accounts it is 6 (exactly at); **at 2 accounts it is 4 and the cliff returns.** One
transient throttle, one logged-out account, one slow poll — and a box with every account nearly
empty pages the operator to run `/limit-recover`. Two bounded fixes, neither of which touches
`cc-eligible`:

- **F1 (consumer).** `cc-dispatch` must read cc-wave-plan's verdict, not just its exit code. On
  `reason: wave-overflow`, re-plan with a wave of `capacity` items instead of abstaining — the tool
  says `reduce-wave-size`; nothing does. Reserve the `QUOTA CLIFF` string and the `/limit-recover`
  directive for the genuinely-capped verdict. (Memory class: *new-enum-member-falls-into-fail-closed-default*
  and *new-nonverdict-state-strands-its-consumers* — this is both.)
- **F2 (planner).** A `poll throttled ↻ (cached usage)` row at `session_pct: 4` is excellent evidence
  of headroom. Excluding it is right for a *route* (pick the best account) and wrong for a *capacity
  count* (how many slots exist at all). Count cached-but-healthy rows toward capacity while still
  preferring fresh rows for placement.

## A2 · THE FIRST DISPATCHER-DRIVEN CLOUD SESSION EXISTS — cloud is now a behavioural claim

Run this session, cloud-only, capped at one spawn:

```
CC_FIRE_CLOUD=on CC_DISPATCH_VENUE_ONLY=cloud CC_DISPATCH_MAX_SPAWN=1 cc-dispatch --once
```

IDL, same pass:

```
{"actor":"cc-dispatch","action":"claimed","detail":"abab60591342: venue=cloud account=next4 — claimed --venue cloud"}
{"actor":"cc-dispatch","action":"fired","detail":"abab60591342 -> next4"}
{"actor":"cc-dispatch","action":"summary","fired":1,"abstained":0,"failed":2,"skipped":3,"admitted":6,"deferred":37}
```

`cc-cloud list` carries the resulting session — `session_01VMwdAbwLif2EDxtkQ39yZz`, branch
`claude/fire-20260812T034126Z-64880-1`. **That is the first cloud session on this box that a
dispatcher created rather than a human**, and the managed wiring is all there:

```
✓ session_01VMwdAbwLif2EDxtkQ39yZz on next4 — anthropic_cloud VM, repo ATTACHED, branch claude/fire-…
  managed: custody OPEN (marker session_01VMwdAbwLif2EDxtkQ39yZz) · wakes 386 on completion · goal: <default: landed by content>
```

🚨 **But state the result exactly, because half the round trip is NOT proven.** At T+15 min
`cc-cloud show` reads:

```
item=abab60591342  account=next4  notify_back=386  custody=session_01VMwdAbwLif2EDxtkQ39yZz
state=NOT-STARTED
detail=no ref after 15m (boot budget 15m)
```

**Proven:** the venue selection, the `--venue cloud` claim, the managed `cc-offload up --via api`
create, and a declaration carrying the REAL branch plus every management field (item, account,
notify-back, custody). **NOT proven:** that the session ever runs its brief. It has pushed no ref and
is past its boot budget.

That matters because it is the *same shape* as the failure `bin/cc-dispatch:1876-1885` attributes to
the DEPRECATED handoff-fire cloud leg — *"DELIVERS NO BRIEF … the session sat NOT-STARTED forever"*
(the fire-#1 forensics session `session_01YcTifmgrKh3KFYuz45Rret`, still `never polled` at 7 h in
today's `cc-cloud list`). This fire went through the **managed** path that was supposed to fix
exactly that, and it is NOT-STARTED anyway. Either the boot budget is simply too tight for a cold VM,
or brief delivery is still not landing on the dispatcher-driven path. **Until one dispatcher-driven
cloud session is observed pushing a ref, "cloud can drain the backlog" remains proven only as far as
session CREATION.** That is a strictly better position than this morning — the cliff is gone and the
actuator fires — but it is not the end-to-end claim, and it should not be written up as one.

One correction to the fear this session started with: the wave-plan's `fire_line` still reads
`--split-right` with a local `--cwd`, which looks like a local pane fire. It is not. cc-wave-plan is
a pure planner emitting the local default; the venue is a **selection between actuators** made later
at `bin/cc-dispatch:1897-1908`, and `--dry-run` returns before that block, so the dry plan
structurally cannot show the cloud actuator. The dry-run output is misleading, not wrong.

One correction to the fear this session started with: the wave-plan's `fire_line` still reads
`--split-right` with a local `--cwd`, which looks like a local pane fire. It is not. cc-wave-plan is
a pure planner emitting the local default; the venue is a **selection between actuators** made later
at `bin/cc-dispatch:1897-1908`, and `--dry-run` returns before that block, so the dry plan
structurally cannot show the cloud actuator. The dry-run output is misleading, not wrong.

### A2a · The measured cloud drain rate is 1 in 3, and the loss is NOT cc-eligible

`fired:1, failed:2` out of 6 admitted. Both failures, verbatim:

```
cc-dispatch: refusing to fire into /Users/chrisren/Development/.worktrees/wt-62599dd76a60 — its HEAD does not contain origin/main (pre-existing worktree, never re-based)
cc-dispatch: refusing to fire into /Users/chrisren/Development/.worktrees/wt-ee1ac85c6ff6 — its HEAD does not contain origin/main (pre-existing worktree, never re-based)
```

`bin/cc-dispatch:2102-2140` provisions a **local** worktree at `--cwd` and then freshness-gates it
(the M2 guard). Both steps run at line ~2102, *after* the venue has already been resolved to `cloud`
at line ~1899 — and a cloud fire never touches that directory. The VM clones from origin; the local
`wt-<id>` tree is irrelevant to it. **Two thirds of this pass's cloud fires died on a staleness check
about a directory the cloud session does not use.**

- **F3.** Skip local worktree provisioning and the M2 freshness gate when `venue = cloud`. This is
  not a loosening of any eligibility predicate — the item was already judged cloud-eligible; the
  guard is simply about the wrong filesystem. Expected effect on this pass: 3 fired instead of 1.

This is the shape the brief predicted for `deep-history` and it is worth stating generally: **the
binding constraint on cloud drain today is what the VM can REACH and what the local dispatcher
insists on checking before letting it go — not the eligibility predicate.**

### A2b · The ceiling: 15.7% today, 20.5% after the one fix worth doing, and a 79.5% hard floor

**Re-derived from the store — and the first re-derivation was itself wrong, in a way worth keeping.**
The obvious command is a `jq` fold over `~/.claude/autonomy/backlog.jsonl`:

```
jq -r 'select(.venuePlan)|.venuePlan' ~/.claude/autonomy/backlog.jsonl | sort | uniq -c
   → 49 cloud · 263 local · "312 total, sums exactly"
```

**That number is an artefact and it must not be quoted.** `backlog.jsonl` is an **append-only event
log — 8,609 records, `.status` null on essentially all of them.** `select(.venuePlan)` therefore
counts *label-write events*, not current rows, and — the load-bearing part — it **structurally cannot
see an unlabelled row at all**, because such a row has no `venuePlan` key to select. That is exactly
why the fold looked so clean: the population it silently dropped is the one Q2 turns on. (Memory
class: *positive-control-the-denominator* — a perfect-looking classifier over the wrong population.)

**The authoritative read is the tool, and it disagrees:**

```
cc-backlog list --open --json | jq 'length'                    → 525 open
… | jq '[.[] | .venuePlan // "UNLABELLED"] | group_by(.) …'    → 45 cloud · 241 local · 239 UNLABELLED
```

and the dispatcher's own journal, this session, for the *dispatchable* subset (project-scoped,
unclaimed): **315 dispatchable · `venue-only=cloud parked 272` · 43 cloud dispatchable.**

| denominator | cloud share |
|---|---|
| 315 dispatchable (the dispatcher's own population) | **43 → 13.7%** |
| 525 open | 45 → 8.6% |
| ~~312 "labelled"~~ | ~~49 → 15.7%~~ — event-log artefact, do not use |

The brief's own "45 cloud · 236 local · 31 unlabelled" is close on cloud and **badly low on
unlabelled**: measured today it is **239 of 525 open rows**, not 31. Its "236 of 312 refused" is not
reproducible from any single read either — the six named refusal counts sum to 245.

**The per-class analysis below is unaffected** — it was produced by importing `bin/cc-eligible` and
calling `assess_full()` per item over the live store (the same code object the claim gate runs,
`bin/cc-venue:104`), and a `cc-eligible sweep --json` reproduces every class within ±4 rows. Only the
venue *fold* and its denominator were wrong.

| venueWhy | n |
|---|---|
| `ineligible-box` | **160** *(brief said 155)* |
| `ineligible-branch-banking` | 25 |
| `ineligible-spawn-rail` | 24 |
| `ineligible-visual` | **19** *(brief said 16)* |
| `ineligible-deep-history` | 15 |
| `ineligible-offbox-lane` | 10 |
| `premise-*` (suspect 4 / falsified 4 / superseded 1) | 9 |
| `ineligible-github` | 1 |

Note also that `eligible` is an *upper bound* on dispatchable: `cc-venue` applies a fourth gate
`cc-eligible` does not — `cc-premise` must return `clear` (`bin/cc-venue:184-193`) — costing 9 more
rows. That is a staleness barrier, not a venue barrier, so it is excluded from the floor.

**Exactly one of the six classes is a provisioning artefact.**

| class | n | verdict | emitted by | fix |
|---|---|---|---|---|
| `ineligible-box` | 160 | **INHERENT** (all six sub-causes) | `bin/cc-eligible:126-210`, verdict `:326` | — |
| `branch-banking` | 25 | INHERENT ×14; provisioning-in-principle ×11, **~1 row real** | `:304-312`, verdict `:328` | push 199 branches to `refs/banked/*` — **not worth it** |
| `spawn-rail` | 24 | **INHERENT** | `:240-256`, verdict `:325` | — the verification *is* a live pane spawn via the it2 API; a Linux microVM has no window server |
| `visual` | 19 | **INHERENT** | `:280-302`, verdict `:327` | — 12 of 19 need an iTerm2 window at a pinned font; the 7 reso rows need Turso creds the VM has no channel for |
| `deep-history` | 15 | **PROVISIONING** ✅ | `DEEP_HISTORY` `:340`, minted in `assess_full` `:656-661` from `HistoryOracle.unreachable()` `:560-590` against `CLOUD_DEPTH=50` `:454` | **`git fetch --deepen 2000` in the VM preamble + lockstep `CLOUD_DEPTH`. Unlocks all 15** |
| `offbox-lane` | 10 | **INHERENT** | `:212-238`, verdict `:324` | — circularity: *"the observer and the subject are the same object"* (`:225-227`) |

`deep-history` is not a keyword — it is the one class the predicate had to **measure** rather than
spell, which is exactly why it is the only one about the VM's *reach* instead of the work's *subject*.
Measured `git rev-list --count <sha>..origin/main` over all 27 cited-unreachable shas: deepest is
1512, so **`--deepen 2000` covers every one** with headroom against a 2,654-commit trunk. A full
`--unshallow` would cost 133 MiB of pack — bytes, against a measured 437 s session. And because
`CLASSES` runs self-referential-first with `DEEP_HISTORY` appended **last** (`:323-330`, `:656-661`),
every one of the 14 live open `deep-history` items has **exactly one class firing** — so the deepen
unlocks all of them and double-refuses none.

**`ineligible-box` (160) is six distinct causes under one label**, and none is provisioning-shaped:
a LIVE Claude Code session's own Stop/PreToolUse events (77 items touching, 38 solo) · terminal +
window server (55 / 23) · the live `~/.claude` layer (49 / 15) · the Darwin kernel — launchd, jetsam,
plists, sysctl (33 / 19) · keychain-held accounts and this disk's installed binaries (28 / 7) ·
generic "this box" (5). **61 items span 2+ groups**, so even a fix to the largest group leaves them
refused for a second reason.

🚨 **The trap inside that: `~/.claude` looks provisionable and must NOT be provisioned.** Most of it
is per-file symlinks into this checkout, so the repo already carries those bytes; the 49 items are
precisely about the parts that are *not* in the repo — whether the symlink farm converged, the real
non-symlinked `CLAUDE.md`, `autonomy/backlog.jsonl`, telemetry, `runner.log`. Mounting a snapshot
hands the VM **a plausible-looking empty version**, which is §5's anti-goal in its purest form, and
the filesystem is reclaimed at session end so anything it converges is gone anyway.

**The second-order win is bigger than the 15 rows, and it is a live correctness problem.** The 49
rows *already dispatching to cloud today* run against a 50-commit graft, where `git blame` attributes
every line to `^e9f9c879`, `log -S` returns 1 commit, `rev-list --count --since=2020` returns 50 —
and this repo's own `|| echo 0` idiom converts eight rc-128 sites into a silent `0`
(`docs/research/cloud-vm-shallow-clone-blast-radius-2026-08-11.md` §3 S1-S7). So the deepen is not
primarily a 15-row unlock; it removes a **silent-wrong-answer surface from every cloud dispatch we
already make**.

⚠️ **Named blocker, and the 15-row unlock is CONDITIONAL until it clears: nobody has run
`git fetch --deepen` inside a cloud VM.** `git push --dry-run` is proven from inside
(`docs/research/cloud-vm-roundtrip-2026-08-10.md:46-50`); a deepen over the same proxy is *inferred*.
The injected credential could be push-scoped, or the proxy could reject a large negotiated fetch.
**Cheapest next experiment: one throwaway cloud session that runs the deepen and prints
`git rev-list --count HEAD` + `git rev-parse --is-shallow-repository`.**

The deepen's interlock, landing as one diff: (1) `git fetch --deepen 2000 origin` as the VM's first
action; (2) the VM prints both assertions and **aborts if the count is below the constant** — a
deepen "does not help at all when the fetch is skipped, fails, or runs after they do"; (3) ONE SSOT —
`CLOUD_DEPTH` (`bin/cc-eligible:454`, overridable via `CC_ELIGIBLE_HISTORY_DEPTH`) reads the same
constant the preamble fetches to. Raising `CLOUD_DEPTH` *without* a verified deepen would mint cloud
labels for work the VM still cannot see: the §5 anti-goal exactly.

| | rows | share of 315 dispatchable |
|---|---|---|
| Reachable today (cloud-planned **and** dispatchable) | **43** | **13.7%** |
| + verified deepen to 2000 + lockstep `CLOUD_DEPTH` | +15 → **58** | **~18%** |
| *+ premise refresh (staleness, not venue — excluded from the floor)* | +9 → 67 | ~21% |
| **HARD FLOOR — cloud can never take this** | **~248 of the labelled refusals** | **~79%** |

*(Row 1 is the dispatcher's own journalled population, which is the only one that predicts behaviour.
Over all 525 open rows the cloud share is 45 → 8.6%, and 239 rows are unlabelled — see A3, where the
unlabelled population is the finding rather than a rounding note. The floor's 248 is a share of the
**labelled** refusals and does not include the unlabelled 239, whose venue is simply unknown.)*

**The generative statement, and it settles Q2's premise.** Four fifths of this backlog is refused
because *the subject of the work is this machine*, and a machine cannot be provisioned into another
machine. There is no second `deep-history` hiding in the other five classes. **If the cloud share is
to rise materially past 20%, it will be because the backlog changes shape — more repo-only work
filed — not because the VM changes shape.**

*(One further measured observation, reported as a finding and NOT as a proposal, because loosening
the predicate is the standing anti-goal: some counts are inflated by spelling collisions — `render`
matching "render GATE-KILLED as its own non-red state", `css` matching the path fragment
`styled-system/{css,jsx,recipes}`, `venue` matching the doc path `docs/research/venue-landing-…` and
a reso feature literally named `provision-venue`. True `visual` is ~15-16 not 19; `offbox-lane` ~8-9
not 10. That is a classifier-PRECISION question with a different risk profile from provisioning, and
per `bin/cc-eligible:25-34` any narrowing must be per-token evidenced and re-audited — a word deleted
on a hunch costs the tap a whole class, and a wrong `eligible` is silent by construction.)*

## A3 · ONE TRACK, ONE RATCHET, VENUE AS A DIMENSION — never two ratchets

**Decision: one metric with a venue dimension.** The question "are we up to date, not stale, optimally
consolidated?" is a question about an ITEM. "Where can this run?" is a question about PLACEMENT. They
are orthogonal, and three measured facts say a venue-keyed ratchet would be actively wrong:

1. **Venue is already a field, not a queue.** `bin/cc-venue:14` writes `venuePlan` + `venueWhy` onto
   open rows in the one `cc-backlog` store; `cc-dispatch` reads it per row at `:1882`. There is no
   second store to keep consistent — a two-ratchet design would *create* the divergence risk the
   operator is trying to avoid, not manage it.
2. **Venue is MUTABLE, and this session moved it.** F3 above reclassifies items between venues by
   changing provisioning, with the items themselves untouched; so does every fix to what the VM can
   reach. A ratchet keyed on venue has a population that shifts under it — the
   *remediation-perturbs-its-own-population* / *discovery-critic-premise-goes-stale* failure. Item
   currency is stable under exactly those changes, which is what makes it the right ratchet key.
3. **The staleness that actually dominates is venue-blind.** This session's live pass measured
   `ready_checked=6 ready_void=6 would_block=100%`, with per-item reasons `no-prior-verdict` and
   `cites-nothing`. "Cites no files" is a property of how the item was *written*. It is identical on
   a Firecracker VM and in a local pane.

**And the venue-keyed design already leaks — far worse than anyone had measured.** The standing
figure was "31 unlabelled of 312". Measured today with the tool rather than a log fold:
**239 of 525 open rows carry NO `venuePlan`** — 46% of the open backlog. The venue filter runs at
step 1a1 (`bin/cc-dispatch:1390-1407`), *before* the decision loop, so the readiness gate's repair
path `ready_relabel()` (`:961-967`) only ever sees the already-filtered set; and the write-path
labeller `venue_label_new()` (`:1243-1259`) is bounded to rows written in the last 900 s **and runs
in decide mode only** (`:1408-1411`), which the 300 s `--once` cron never enters. Net: **those rows
are excluded on every pass, in every venue, forever.**

This is the single strongest argument against two tracks. Under two tracks, nearly half the backlog
belongs to neither and is invisible to both — and no per-venue ratchet can even *see* it, because
having no venue is precisely what excludes it. Under one track they are rows whose venue dimension is
unset: countable, reportable, and drainable the moment the labeller's gap is closed. **The unlabelled
backfill is therefore not housekeeping — it is a prerequisite for any honest consolidation number**,
and every migrated-share percentage published before it lands has a 46% blind spot in its denominator.

**Therefore:**
- **The ratchet counts NOT-READY open items, fleet-wide, venue-blind.** It must fall. This is the
  consolidation metric, and the readiness conjunction landed today (`CC_DISPATCH_READY_GATE`,
  `cc-premise screen`, `--fold`) is already exactly that instrument — it is venue-agnostic by
  construction and should stay that way.
- **Venue is a reporting fold and a routing decision**, never a second ratchet: report
  `open × ready-verdict × venuePlan` as a cube, so "cloud can take 14%" is a *cell*, not a track.
- **`venuePlan = unset` is a first-class value in that cube**, not an absence. A count that silently
  omits 31 rows is the same defect as a filter that matches nothing.
- **Backfill the 31 unlabelled rows** and fix the labeller's decide-mode/900 s bound; this is
  separate work from the venue flip and should not ride on it.

So the answer to "one track or two" is: **the work was never two populations — it is one population
with a placement attribute**, and the ~14% figure is a statement about today's provisioning, not
about the shape of the backlog.

## A4 · CLOUD CONTINUOUS, LOCAL ON A SWITCH THAT A SCHEDULE WRITES — one resolver, not two mechanisms

**Decision: build ONE venue resolver with a precedence ladder, and make the SWITCH the primitive.**

```
explicit operator override (if set and unexpired)  →  time window  →  standing default (cloud)
```

A toggle alone cannot express "while I'm asleep"; a window alone cannot express "I'm stepping out
now". The override carries an **expiry**, so a forgotten `local` cannot silently hold 15 slots for a
week — which is the exact failure the migration exists to prevent.

**The rail: a state file under `~/.claude/autonomy/`, read at pass time — NOT a launchd env.** The
inventory is unambiguous. There is **no time or presence machinery in this repo at all**: zero
time-of-day predicates in any shell or python (every `%H` is timestamp formatting), no `HIDIdleTime` /
`ioreg` / `pmset` read anywhere, and `scripts/caffeinate-floor.sh` pins the box awake 24/7 so "machine
asleep" can never serve as an away proxy. The nearest neighbour is the desk-role FILE
(`bin/cc-classify:52`), which says *which pane is the operator's*, never *whether they are there*. So
whatever is built is the first of its kind, and it should ride the two rails that already exist:

- the **fail-closed flag file** precedent — `bin/cc-config-slot:62-63,84-92`, whose reusable half is
  pairing the file with a `--status` verb so the operator can read the switch without knowing the path;
- the **pass-time conf** precedent — `scripts/dispatch-projects.conf` + `bin/cc-dispatch:249-286`,
  which degrades on a malformed parse toward *narrower* coverage, never a wider blind fire.

A launchd env change is the wrong rail for a thing that flips: it needs a land, a `deploy-live.sh`
converge (measured 534 identical refusals / 91 commits stale in one 2026-08-07 episode), an
`install.sh` copy, and a bootout/bootstrap that `install.sh:727-731` **skips entirely while the job is
executing** — and with a 414-833 s admission tail against a 300 s interval, the dispatcher is often
executing. A file the binary reads costs none of that and takes effect on the next tick.

**Shape:** a `venue_policy()` resolver in `bin/cc-dispatch` and exactly one changed line at `:1390`
(`VENUE_ONLY="${CC_DISPATCH_VENUE_ONLY:-$(venue_policy)}"`) so the plist env keeps precedence as the
emergency override and every existing test still passes; the window in `scripts/dispatch-venue.conf`
(versioned, reviewable); the override in `~/.claude/autonomy/dispatch-venue.json`
(`{"venue","until","by"}`, fail-closed to `cloud` on missing/malformed/expired); and
`cc-dispatch venue <cloud|local|both|auto> [--for 8h]` + `venue --status` as the only surface the
operator touches, validating against the closed set **before** writing. Removing
`export CC_DISPATCH_VENUE_ONLY=cloud` from the plist is the LAST step, not the first — the interlock.

### A4a · The blocking constraint nobody has costed: turning local on STARVES cloud

`CEILING` is one global number and `live_workers()` (`bin/cc-dispatch:438-447`) is the venue-BLIND
`claimed` fold — a cloud worker consumes the same slot as a local one. The S7 ordering key is thrash
ASC → derived rank → oldest ts (`:59-61`), with **no venue term**. With 236 local rows against 45
cloud, a `both` window hands nearly every free slot to local work by pure queue position, and **cloud
drain stops for the duration of the window**.

So "cloud runs continually" is not achievable by adding a local window to today's dispatcher. It needs
one of: a **reserved cloud slot** (a floor of the ceiling that only `venuePlan=cloud` may fill), or a
**venue term in the S7 key**. Neither exists. This is a prerequisite of Q3, not a follow-on — without
it the scheduler delivers "local on a schedule, cloud whenever local is idle", which is not what was
asked for.

Three further properties to accept or design against, none of them blocking:
- **The window gates ADMISSION only.** Workers fired at 06:58 run past a 07:00 close; there is no
  venue-aware drain and `cc-reaper` is a liveness reaper, not a policy one.
- **The boundary is fuzzy by up to ~14 min** — one 300 s tick plus one 414-833 s admission tail.
- **A local window opened while the box is loaded produces churn, not spawns.** `capacity_gate()`
  (`scripts/handoff-fire.sh:3978`, default 2.0 load/core) refuses *after* the claim is taken, so the
  item reopens with a thrash record — and the box measured 2.19 load/core on the day the pause went in.

### A4b · Rejected, on the record

- **Charging `CC_DISPATCH_CEILING` for the operator's panes** — already measured and rejected at
  `bin/cc-dispatch:414-430`: it pinned `free_slots` at 0 permanently and silently. *"Charging dispatch
  for human activity lets the operator silently throttle autonomy to zero."* Venue is the right axis;
  the ceiling is not.
- **A second launchd job on `StartCalendarInterval`** to rewrite the flag — needs a new plist, a
  `fleet.manifest` row and a C10 operator bootstrap, for a clock a job already ticking every 300 s
  computes for free.
- **`launchctl bootout` as the "off" switch** — kills cloud dispatch too, and stops step 1d's
  stale-item retraction. That is exactly what `CC_DISPATCH_VENUE_ONLY` was built to escape.
- **A `$( )` substitution inside the plist's `bash -c` string** — works and is the fastest to ship,
  but the predicate is then untestable by any `.bats` suite and invisible to `cc-dispatch selftest`.

### A4c · Hazards the implementation must respect

- **The interlock (H1).** Land the resolver → converge → PROVE by positive control → only then remove
  the plist guard. The positive control is the same shape as 2026-08-11's: with `=cloud` still
  exported, set the file to `local`, run one pass, assert the IDL carries `venue-only=local parked N
  of M` (`bin/cc-dispatch:1404-1406`). **Absence of that record is the signature of the bleed.**
  Today the live `~/.claude/bin/cc-dispatch` is byte-identical to origin/main's, but the live checkout
  is 2 commits behind — that equality is a fact with a half-life, not a standing property.
- **An unrecognised value is a TOTAL OUTAGE by design** (`:1394-1397` refuses the pass). A resolver
  that can emit `both`, `auto`, `off`, `""`, a trailing newline or a date-formatting slip must map to
  unset/empty and never pass its own vocabulary through. `Cloud` with a capital C is already pinned as
  a refusal case in `tests/cc-dispatch-venue-only.bats:76`.
- **`CC_FIRE_CLOUD=on` must stay set regardless of venue.** `bin/cc-dispatch:1900-1903` fires a
  cloud-planned item **LOCALLY** when the opt-in is absent — removing that export converts cloud plans
  into local spawns, the precise outcome the operator is bounding.
- **Parity lint reds on any hand-edited live plist** (`scripts/launchd-parity-lint.sh`, run bare by
  `nightly-regression.sh`): a plist change must land in the repo *and* reach `~/Library/LaunchAgents`
  through `install.sh`. Header XML comments are exempt.

## A5 · THE BLOCKED PILE IS MOSTLY MACHINE FAILURE, AND THE RE-LAND CLASS IS A SELF-FEEDING LOOP

*Measured 2026-08-16 while driving "zero backlog". Recorded here because the classification is the
expensive part; re-deriving it costs a dozen jq passes and the loop diagnosis costs a failed land.*

**The store is not one pile, it is two, and the smaller one is the drainable one.**

```
1612 done · 305 blocked · 265 open · 1 claimed          net +114 over 8 days (inflow > drain)
```

`blocked` is the OPERATOR-ONLY state and `cc-dispatch` excludes it from the wave by construction, so
those 305 rows are not merely unworked — they are unreachable by the pipeline. **44% of them are
machine failure, not operator work:**

| n | class (grouped on the `needs` text) |
|---|---|
| 77 | `re-land <branch>` — a land that failed, re-filed per ATTEMPT |
| 50 | "the worktree occupancy oracle could not be RESOLVED past the <n>s ceiling" — a sensor timeout |
| 6 | "dead-worker stall after <n> dispatch attempt(s)" |
| 2 | "pre-existing worktree … is behind origin/main" — the A1 class, working as designed |
| ~170 | genuine operator tail, mostly one-offs |

**The 77 re-land rows are only 27 distinct branches** — the row is minted per failed ATTEMPT, not per
unlanded change, so one branch had 12 rows and another 8. Classify by CONTENT before touching any of
them (`git cherry origin/main <ref>`; a subject is intent, the diff is the change):

- **4 branches were already upstream** (patch-id `-`, or 0 ahead) ⇒ 16 rows closed with evidence, no
  work to do. This is the majority of the row count for a minority of the branches.
- **4 branches hold genuinely unlanded commits** — real value, ~1200 insertions, including
  `fix(cc-premise): every non-zero falsifier exit was rendered as "this premise is current"`.
- **18 branches are GONE**, and that is NOT a write-off: the land machinery pins every failed head at
  `refs/land/failed/<ts>-<uuid>-<branch>` — **616 of them exist**. The work is recoverable from the
  pin even when the branch is deleted. Never close a `re-land` row as "branch gone, work lost"
  without looking there (memory: search-branch-graveyard-before-building).

**WHY THE LOOP NEVER ENDS, and it is deterministic rather than flaky.** `claude/fire-20260813T214112Z-31568-1`
(custody v1.1, 489 insertions, stranded since 08-13) re-failed **~11 times on 2026-08-16 alone**. Each
attempt pinned a new `refs/land/failed/…-31568-1` and minted another blocked row. The cause is a gate
doing its job: the commit's own new test replayed its pre-fix control from **`origin/main`**, and
`moving-ref-control-lint` refuses a control that the land itself changes — because that ref advances
past the fix the instant it lands, after which the control compares the fix to itself. So the land
could never succeed, and nothing in the retry could change that. **A re-land row whose branch fails a
DETERMINISTIC gate is an infinite generator: the retry is not a chance, it is a copy.** Fixed in
`2736cb6e5` (literal-sha pin + a marker whose polarity is inverted because the fix is a REMOVAL).

**Three more branches show the same repeated-failure signature today** (`…-40705-1`, `…-84790-1`,
`…-79031-1`): triage each by running the land ONCE and reading the gate, never by re-queueing it.

**The drain order that follows from this:** fix the generator first (a deterministic gate failure
re-mints faster than any closer retires), then close the already-upstream rows in bulk by patch-id,
then land the genuinely-stranded commits, then the 50 sensor-timeout rows. Closing rows ahead of
fixing the generator is pouring water into a bucket whose hole you have measured.

## A6 · THE DRAIN RAN — 115 BLOCKED ROWS RETIRED, AND THE REAL GENERATOR IS UPSTREAM OF ALL OF THEM

*Executed 2026-08-16, the session after A5. Numbers are live reads, not estimates:*
`blocked 279 → 164` · `done 1644 → 1765`. **Every row closed on content evidence; none by fiat.**

### A6.1 · The instrument that made bulk closure honest

`git cherry` was the wrong tool and A5's own advice was too weak. A rebase changes the patch-id, so
`+` means "different bytes", not "not landed" — and **29 of 32 stranded commits read `+` while
being fully present on trunk**. The instrument that works compares CONTENT: for each added line of
length ≥25, ask whether it appears anywhere in `origin/main`'s version of the SAME file, and report
`ABSENT/TOTAL`.

It separates cleanly and it is controlled BOTH ways (a known-upstream commit reads `ABSENT=0`, a
known-stranded one reads `ABSENT=299/313`). Real verdicts cluster at **≤8%** (revision drift — the
change is upstream in a later or differently-spelled revision) or **≥17%** (genuinely stranded).
Nothing landed in between. Script: the session scratchpad's `content-check.sh`; re-derive it, it is
20 lines.

🚨 **A high ratio is a QUESTION, not a verdict.** Two commits read 47% and 100% absent and were
still upstream: `73e2ac8ce` (trunk hoists the producer into a variable — `bodies="$(setup_bodies)"`
then `grep <<< "$bodies"` — where the branch inlined the here-string; the pipe is removed either
way, which is the whole fix) and `94b6fe955` (trunk's `af8be7c93` fixes the same defect with an
external `extract.awk`, strictly better). **Read the trunk commit's diff before convicting.**

⚠️ **Trunk moves under a long analysis.** `606a6ee4d` measured `ABSENT=383/383` and a subject grep
said NOT-ON-TRUNK; twenty minutes later a sibling had landed it byte-identically as `40d574617` and
the same check read `ABSENT=2/266`. **Re-fetch before every verdict**, and treat any figure older
than one land as unread.

### A6.2 · What the 77 re-land rows actually were — 52 closed, ONE needed a land

| n | disposition | evidence |
|---|---|---|
| 42 | already upstream by content | a named trunk sha per branch |
| 9 | the M3 dead-letter store | landed as `71c59d995` (below) |
| 1 | superseded by a better trunk fix | `af8be7c93` |

**The M3 land is the whole A5 thesis in one commit.** `405bcdec3` (408 insertions) had failed ~9
times, always deterministically. `--precheck` — same `run_gate()`, no lock, no ref, ~2 minutes —
named the arm in the first run: `bash-n:hooks/operator-readout.sh`. The cause was not in the logic
the commit adds. Its new comment sits INSIDE the `$( )` that feeds `escalation_unseen_count` and
read *"the store's `.ran` evidence"*. **bash 3.2 does not skip comments when scanning for a command
substitution's closing paren**, so that lone apostrophe opened a quote that swallowed forward to the
next `'` and desynced the parse — surfacing as a syntax error **~260 lines downstream**, at an
unrelated `case` arm's `commit(s)`. That distance is why nine attempts never pointed at the cause.
Reworded, gate green, landed as `71c59d995`.

**Use `--precheck` FIRST, always.** It reads the land gate's own verdict in ~2 minutes without
taking the lock, touching a ref, or writing a `land.log` row. A blind re-land costs 15+ minutes and
returns the same exit 6. *(Generalisable: `bash -n`'s reported line is where the parse DIED, not
where it broke — bisect the file, never trust the line number.)*

### A6.3 · The 50 "occupancy oracle" rows were one missing oracle, and all 50 were answerable

Not a timeout — **NON-COVERAGE, by design**. `owned_wait()` (`bin/cc-backlog:4238`) returns rc 2 for
any `venue != local`, correctly, because a cloud worker has no local worktree. But `claimer_live`
only ever sees the DISPATCHER's spent pid. So for a cloud item **no oracle can speak at all**, the
reap abstains until `unresolvedmax`, and then blocks — permanently, on a row no operator can action.

**The missing oracle already exists.** `bin/cc-cloud` carries a per-session state function
(`list --json --state`), and `cc-dispatch` already writes the join key — it fires
`cc-cloud declare --id <sid> --branch <b> --item <backlog-id>`. **All 49 live rows had a
declaration.** Their verdicts:

| state | n | what it means | disposition taken |
|---|---|---|---|
| LANDED | 19 | content present on origin/main | **closed** — independently re-verified, all 19 `ABSENT=0` |
| STALLED | 19 | pushed a ref, then froze | 9 **closed** (work reached trunk anyway), 10 hold real content |
| NOT-STARTED | 11 | no ref after 1–4d, against a 15m boot budget | **reopened** — a worker that never booted is not an operator gate |

**THE FIX THAT RETIRES THE CLASS** (not yet built — `bin/cc-backlog` has active siblings): in
`owned_wait()`, replace the unconditional `return 2` on a non-local venue with a `cc-cloud` lookup
by `--item`. LANDED/ALIVE ⇒ rc 0 · retired/dark ⇒ rc 1 (a real answer, so the dead-worker reopen
path becomes reachable) · no declaration ⇒ rc 2, abstaining exactly as today. Strictly more
evidence, and it never weakens the fail-closed direction the abstention exists to protect.

### A6.4 · The dominant inflow is upstream of every class above: cloud dispatch delivers 36%

Measured over **all 112** `cc-cloud` declarations — filed as backlog `42ab9ce1a2e7`:

```
40 LANDED (36%) · 32 STALLED (29%) · 32 NOT-STARTED (29%) · 7 ABANDONED · 1 BOOTING
```

**Two of every three dispatches are pure backlog inflow.** The 29% that NOT-START never produce a
ref at all — oldest 203h against a 15m boot budget — and it is **not account-specific** (spans
next2/next3/next4) and **not a push problem** (every one reads `base_probe=ok`, so the branch was
pushed and observable). No closer can outrun this; it is the generator behind A5's generator.
`cc-cloud` records `url=https://claude.ai/code/<sid>` for each — **open three and read what the
session shows before touching the fire path.**

### A6.5 · The blocked tail is 100 rows the agent structurally cannot close

Full triage of the 179 non-re-land, non-oracle blocked rows →
`docs/research/blocked-tail-triage-2026-08-16.md`. **53 closed this session** (38 STALE + 15
duplicates); the STALE verdicts were re-verified independently, not taken on report: all 17 named
deploy-lag shas test ancestor of the live-layer HEAD `8969739161f1`, the shared checkout is 0 ahead
/ 0 dirty TRACKED, pid 43305 is gone, and live kitty windows are `2 82 88 100-120` only, so panes
72/147/431 are absent.

**The residue is a wall, and it should be stated as one:** 100 rows are TRULY-OPERATOR — 34 value
forks, 18 credential/OAuth mints, 16 C10 activations, 11 GUI-only or physical, 10 human contact, 5
permission grants, 5 production deploys with no agent land rail, 1 sudo. **"Zero blocked" is not an
agent-reachable state.** The honest target is *zero rows that are not genuinely the operator's*, and
the 24 rows the triage found MIS-FILED as blocked (agent-doable) are the remaining agent work in
that pile.

### A6.6 · What is left, named

- **8 stalled cloud branches hold real unlanded content and REBASE-CONFLICT** on 2–4 days of drift
  (`d23f3a444984` `b33f424c747b` `c9771c467a91` `6290f0ee6b52` `75869b41c9d9` `04010b4c8074`
  `16a60c2431cc` `6ee23081b34c`, plus `28a2c9cf6a24`). Per-branch conflict resolution — a wave, not
  a sweep. Gate verdicts are cached at `/tmp/gate-batch-results.tsv`.
- **1 gate-red**: `04010b4c8074` → `e4d0d508a`, arm `dead-assertion`.
- **115 of 115 falsifier probes were re-run**; only 2 retracted. **The backlog is not stale — it is
  live work.** Do not plan a drain around finding rot; there is very little.
