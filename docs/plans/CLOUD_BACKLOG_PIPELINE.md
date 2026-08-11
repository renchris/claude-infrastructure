---
status: open
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
| **W3 · refusal loop** | S | a land refusal routes back to the session that caused it | W2 |
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
