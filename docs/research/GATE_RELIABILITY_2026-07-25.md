# Gate Reliability — the non-queued landing gate for a deploy-free repo (2026-07-25)

**Status: RESEARCH COMPLETE — architecture recommended, implementation plan below.**
Produced by a 10-subagent research wave (R1 impact-map · R2 false-skip adversarial · R3 flake
census · R4 runtime profile · R5 telemetry forensics · R6 deploy mechanism · R7 ecosystem
prior art · R8 async safety net · R9 policy surface · R10 red-team), each finding cited
inline as [Rn]. Builds ON `docs/research/land-gate-serialization-2026-07-25.md` (the CAS
fix) — this doc addresses the two failure modes that SURVIVED it: load-flake false-REDs and
the exit-42 re-gate storm.

**TL;DR** — the incident night sat at λG = 0.93, the livelock knee: gate duration (~17 min)
equaled the mean inter-land gap, so 62.5% of completed gates were thrown away and one 2-commit
landing took 20h25m [R5]. The full suite per land is a deploy gate without a deploy: the live
`~/.claude` layer is the SHARED CHECKOUT's working tree (per-file symlinks), advanced only by
a manual, operator-only `git pull --ff-only` — trunk itself deploys nowhere [R6]. The fix is
the industry-standard shape (Google TAP / Meta / Chromium CQ — none run the full suite
pre-merge [R7]): a CHANGED-SCOPE landing gate (empirically 100% recall on 237/237 historical
coupling pairs, median land 15 min → ~4 min [R1]), a flake-exoneration retry ladder, a
POST-LAND async full-suite net with tree-hash green stamps + bisect attribution + backlog
remediation [R8], and a green-stamp-gated deploy step [R6] — with `gate-green` remaining
full-suite-only so no downstream consumer is lied to [R9], and reso's deploy-gated pipeline
untouched (isolation proven four ways [R9]).

## 1. Problem — what the CAS fix did and did not solve

The 2026-07-25 CAS fix moved the full gate outside the machine-wide lock. Live telemetry
(`~/.claude/land.log`) confirms the lock itself is now cheap: CAS fast-path holds are 14–30s.
What survived — same night, disk-verifiable:

- **Exit-42 storm (livelock by re-gating).** Each optimistic round runs the FULL suite
  (~117 bats files, ~1579 tests, ~15 min). Any sibling land during those 15 min invalidates
  the round (CAS stale → exit 42 → full re-gate). Observed 2026-07-25:
  `fix/reaper-dryrun-no-lock` burned rounds at 20:37 → 20:52 → 21:10 and landed only via the
  guaranteed-progress fallback at 21:27 — **holding the lock 1052s** (the full suite, in-lock,
  the exact pre-fix behavior the fallback deliberately reinstates under sustained contention).
  `relogin-design2` was still cycling 42s at 21:40 and 22:03. Earlier, an old-code land held
  the lock **6771s** (1.9h) at 03:34.
- **Load-flake false-REDs.** Concurrent unlocked gates raise machine load (load avg 13–19
  observed) and suite-run frequency; timing-sensitive tests (integer-second deadline math,
  fixture deadlines of 1s) intermittently RED the whole gate on work that didn't touch them
  (the `lead-supervisor` T22b class — one instance root-fixed same-day, the CLASS remains).
  A gate-RED (exit 6) costs a full round plus a human/agent re-run; combined with the 42
  storm, a trivial 2-commit landing was blocked for hours.

The livelock arithmetic, fitted to the full log [R5]: with gate duration G and sibling-land
arrival rate λ, P(round invalidated) = 1 − e^(−λG). G was measured three independent ways at
**1044 s** (pre-fix in-lock holds; post-fix 42→outcome deltas; test-count × per-test cost).
The incident-night burst ran at λ = 3.21–3.38 lands/hour → **λG = 0.93, the livelock knee**
(mean inter-land gap ≈ gate duration). Predicted invalidation 60.6% vs observed **62.5%** —
a 3% model error. Consequences at that λ:

| G | P(invalidated) | E[wall]/land | P(rounds exhaust → in-lock fallback) |
|---|---|---|---|
| 1044 s (today) | 62.5% | **46.4 min** | 24.4% |
| 300 s | 24.5% | 6.6 min | 1.5% |
| 60 s (scoped) | 5.5% | 1.1 min | 0.02% |
| 30 s (scoped) | 2.8% | 0.5 min | ~0% |

Robust to demand doubling (λ=6.8/h: G=60 → 10.7%). **The variable that matters is G** — the
CAS loop and the lock need no change at all [R5]. Measured cost of the status quo over the
34 h incident window: **63 full-gate runs → 24 pushes; 39 gates (11.3 machine-hours) pure
waste**; the U2 landing (two ~40-line safety fixes) took **20 h 25 m and ≥6 full gates**;
max lock-queue wait hit 2777 s = 77% of the 3600 s hard-fail ceiling [R5].

Additional telemetry defects found while measuring [R5, R8]: the unlocked gate-RED path
exits 6 **without attesting** (post-fix gate-REDs are invisible — no denominator exists for
any flake-rate claim), `land.log` records no commit SHA (attribution impossible), and 51 of
166 lock lines have no ship-land attestation (3 pushes bypassed the pipeline entirely in the
window). The `Session-Id:` trailer convention is near-dead (4 of last 60 trunk commits).

## 2. The architectural insight — deploy-gated vs deploy-free repos

reso-management-app deploys to AWS Amplify + Fly.io on push-to-main. A red trunk there IS a
broken production deploy; a heavyweight pre-push gate + serialized landings are justified —
**nothing in this design touches reso.**

claude-infrastructure deploys NOWHERE in that sense. It is the source repo for local
`~/.claude` tooling. The only races to serialize are the git push fast-forward window
(seconds) and the 2026-07-11 content-drop class — both already covered by the CAS lock +
land-verify. The full-suite pre-push gate is a *deploy gate without a deploy*: it buys
"trunk is fully green at every commit" at the price of 15-minute rounds, false-RED flakes,
and O(N²) re-gating under concurrency. For this repo the honest requirements are:

1. A landing must never push syntactically broken or lint-red shell/python (fast, per-file,
   already exists: shellcheck + bash -n + py_compile on changed files).
2. A landing must not break the tools it TOUCHES (changed-scope tests).
3. The repo must converge to fully-green FAST and LOUDLY when a landing breaks something
   it didn't touch (async full suite + attribution + paging — the deploy-gate moved to
   where the deploy actually is: consumption of trunk by the live machine).
4. Two landers must not drop each other's commits (CAS lock — unchanged).

**The verified deploy dataflow [R6]** — there is no deploy step; the gap is real and it cuts
the OTHER way:

- `~/.claude/{hooks,scripts,commands,skills}/*`, `~/.claude/bin/cc-*` are **per-file
  symlinks into the shared checkout** (hooks 59/60 symlinked, scripts 71/71; 176 links
  total) — `install.sh:89-96,102-105,148-155,193-201,256-259`. The live layer is the shared
  checkout's WORKING TREE, not `origin/main`.
- The only "deploy" is a **manual, operator-only** `git -C ~/Development/claude-infrastructure
  pull --ff-only`, prompted by `hooks/operator-readout.sh:113`; an agent running it is
  classifier-HARD-BLOCKED (memory `deploy-lag-checkout-behind-origin.md`). Nothing automates
  it; the live layer was 2 commits behind trunk at research time — two landed, gated-green
  *safety fixes* sitting inert.
- So **a red trunk does not auto-break the machine**; it breaks it at the next manual pull.
  And symmetrically: today's full-suite land gate does NOT protect the live layer from
  anything the pull drags in later — the protection point and the risk point are misaligned.
- What a red trunk DOES hit immediately [R6]: new worktrees are cut from `origin/main`
  (`bin/cc-dispatch:92`, `scripts/handoff-fire.sh:202`), so sessions started in the window
  run red pipeline code; and every subsequent land's gate goes red on the composed tree —
  safety holds, throughput stops (self-limiting, fleet-blocking).
- Second channel: `install.sh` copies (CLAUDE.md, statusline, plists + launchctl reload) —
  in parity today. Out of ANY gate's reach: 3 untracked live-only hooks (`curl-gate.py`,
  `keychain-guard.sh`, `enforce-email-formatting.py`), stale `~/.claude-{next,secondary,…}`
  script copies (18/55 stale, incl. a pre-CAS `ship-land.sh`), and long-running daemons
  holding pre-deploy code (lead-supervisor uptime 2d6h at research time).

This is the architectural resolution: **move the full-suite guarantee from the land step
(where it gates nothing physical and costs livelock) to the deploy step (where the live
machine actually consumes trunk)** — a green stamp per tree SHA, produced asynchronously
after each land, that the deploy fast-forward refuses to advance past [R6, R8].

## 3. Findings

### 3.1 Test-impact mapping is FEASIBLE-CONSERVATIVE — the prior rejection is refuted by measurement [R1, R2]

The prior doc rejected changed-path selection with "tests read docs too; no map is
conservatively sufficient." Measured [R1]: 117 suites contain **317 literal repo-path
references (137 unique files); zero suites construct a doc path dynamically**. Exactly 9
real prose/config files are read by suites, every one via a literal string — prose coupling
is the *most* greppable part of the map, not the blocker. Naming convention alone covers
92.3% of suites; the 9 unnamed suites are integration suites that name their SUTs inline.

The proposed rule (7 clauses [R1 §6]): literal-path grep (comments INCLUDED — load-bearing:
`lead-supervisor.bats` names its e2e only in a comment) ∪ transitive exec/source closure
**to fixpoint** ∪ package-dir ∪ basename-token with a 5-word stoplist ∪ naming-convention ∪
install-glob membership (pre-existing paths only) ∪ **fail-closed FULL triggers**: hub files
(8), any unmapped changed file, any `*/lib/*` change (R2's condition — a `^lib/`-only match
misses 2/3 of shared-helper changes), any deletion/rename, any new file.

Empirical validation [R1]:
- **Recall 237/237 (100%)** on every developer-attested (source, suite) co-change pair in
  551 commits of history; 26/26 on the non-obvious pairs.
- 50-land simulation: median land **8 suites · 31 s**; fixpoint-closure worst case p90
  ~589 s; exactly 1 of 50 lands degenerates to FULL. Time-skip 65.5% at fixpoint (82.6% at
  depth-2 — but depth-2 silently drops ~45 real 3-hop couplings, e.g. `lead-supervisor →
  cc-notify → push-send.sh`; **take fixpoint**).
- The FULL-trigger allowlist is 24/390 files (6.2%) — auditable in review.

Adversarial hunt [R2] — the one empirically PROVEN false-skip: `hooks/lib/cc-interactive.sh`
→ `tests/cc-classify.bats` (zero suites name it; a realistic one-line mutation flipped the
suite red; it guards the reaper against killing live operator conversations). Caught by
either the closure (via `bin/cc-classify`'s literal source line) or the `*/lib/*`→FULL
fallback — both are in the rule. R2's remaining conditions, all adopted: **fail-closed empty
selection** (a selector bug must produce FULL, never zero — this repo's own written law),
selection set recorded in `land.log`, deletions/renames → FULL (0.8% of commits — free),
directory-membership rule for `install-wire-hooks`-style globs, a RED-proof for the selector
in the CAS suite, and the async backstop running in a fresh checkout with retry-before-page.
Historical evidence favors the map: in 500 commits, R2 found **zero** incidents of "change in
X reddened suite of Y" without a textual link; the recurring gate-RED class is load-flake,
not cross-coupling.

Residual risk classes that survive the rule [R1 §5]: deep-transitive edges are closed by
fixpoint; unresolvable relative `source` paths (the `$LIB_DIR` shape — 1 latent case, 3
rescued by fallback literals); **cross-suite host-state pollution (R3/hermeticity — the one
risk that GROWS with skip rate**, see §3.2); the trunk-greenness induction now needs the
async full-suite re-base [§3.7]; and the co-change oracle proves author-attested coupling,
not execution coupling — the settling experiment is a mutation sweep, which the async net's
shadow evidence supersedes in practice (§4, S2).

### 3.2 Flake census — sleep is NOT the problem; hermeticity and cross-session kills are [R3, R4]

- Measured full sweep at load 16–40: **1615 s (26.9 min), 117 suites** [R3]; independent R4
  run: 1710 s. The "~15 min" figure is low-load; the suite is ~1.8–2.5× load-elastic. The
  suite is **CPU-cheap (32% CPU — 9 CPU-min)**: 97% of wall is fork/exec of shell tools
  under CPU oversubscription, NOT sleeps — true blocking sleep totals **≈45 s** (the 588 s
  of literal `sleep` is almost all backgrounded PID-holder fixtures) [R3, R8].
- Concentration: `cc-reaper.bats` alone = 628 s = **37%** of the suite (85 full-script
  spawns, 5 real git repos per test × 78 tests); top-5 = 54%; the 65 suites under 5 s total
  141 s [R4]. `lead-supervisor.bats` re-runs the identical 59-check e2e **5×** and greps
  different strings — a `setup_file()` hoist cuts 78 s → ~16 s [R4].
- Second-boundary races: the documented class is root-fixed where found (same-sweep guard +
  forcing knobs), but **one NEW unfiled instance was RED-proved**: `cc-reaper.bats:975`
  "UNSTAMPED fresh lock" races a 5 s stamp-grace against wall-clock [R3].
- **The reproduced flake class this session is EXTERNAL SIGTERM, not timing**: three
  independent full-suite runs each lost exactly one test to `Terminated: 15` at a line that
  cannot fail (`cc-backlog:415` [R3], `cc-reaper` test 12 [R4], `cc-inbox-guard:36` [R8]) —
  all green in isolation. At least one killer was identified: a peer research session ran
  machine-wide `pkill -f 'bats-exec-test'` mid-afternoon [R6 confession]; `reaper-e2e.sh:24`
  carries the same pattern. **On a multi-session box, broad `pkill -f` patterns are a
  first-class gate-flake root cause.** No `BATS_TEST_TIMEOUT` exists anywhere, so bats never
  sends it.
- Hermeticity: only 6/117 suites export a fixture `HOME`; 10 set no isolation at all;
  **live leakage confirmed** (404 `bats-run` lines in the real `~/.claude/autonomy/idl.jsonl`
  from `session-continue.bats`) [R3]. Live launchd daemons (reaper, lead-supervisor,
  dispatcher) mutate the same `~/.claude/autonomy/*` the unpinned suites touch — daemon
  contention is a standing flake axis [R3]. R4's static audit found the *write* paths mostly
  sandboxed and zero suites running git against the real worktree; the empirical 4-way
  parallel probe surfaced exactly one new timing flake with a one-line fix
  (`land-lock.bats:59` unguarded `kill`) [R4]. Net: subset-vs-full verdict equivalence needs
  a **hermeticity lint** (fixture HOME + state-dir override per suite) — R1's precondition 3.
- Historical flake ledger: 9 root-fixed incidents, four reusable patterns (start-relative
  deltas, forcing seams, same-sweep guards, fixture isolation + pollution GC) [R3].
- Quarantine recommendation [R3]: Tier A (proven load-flakes, never safety-critical):
  `cc-backlog`, `lead-supervisor`, `handoff-fire-completion-push`, `cc-await-ping`,
  `fire-engagement`. Under changed-scope selection the "quarantine" question mostly
  dissolves — those suites simply stop gating *unrelated* landings; they still gate their
  own SUTs and still run in the async net.

### 3.3 Suite runtime profile — sharding facts [R4]

Sum-of-individual-files ≈ full-run + **1%** (0.147 s/file bats overhead) — running bats
per-file or in shards is effectively free, which unlocks: failed-FILE re-runs as the retry
primitive, per-file selection, and shard parallelism via N background `bats` processes
(**no GNU parallel needed**; `bats --jobs` without it executes 0 tests and only warns — a
silent no-op gate to guard against [R3 #10]). 4-shard makespan is pinned at 10.5 min by
`cc-reaper.bats` alone; splitting that one file yields ~6.5 min balanced. Realized parallel
speedup on a loaded box: ~1.7×, not 4×. 17 files hard-code fixed `/tmp` paths; exactly one
is a real write-collision site (`lr-reset-poller.bats:274-279`) — fix before any always-on
parallelism [R7, R8].

### 3.4 Telemetry forensics — quantified in §1 [R5]

Additional structural findings: the nightly full-suite regression job has been **RED for 7
consecutive nights (7→8→9 failing checks, growing), has never once been green, and its page
has NEVER been delivered** — `autonomy-sweep` dedups pages by path-hash with a 7-day TTL, so
the fixed `nightly-regression.page` key was surfaced once and swallowed; it is the only one
of ~195 page keys with no `.notified` sibling [R5, R8]. Its wall time ballooned 7 min →
9.5 h under fleet load (launchd Nice 10). Root cause of the chronic red: its check-set mixes
tree-pure checks with **designed-RED** (`premortem-gate.sh`: "Red here is not a bug — it is
the bar") and **live-state** checks (`claude-lint-models.sh`, `never-stuck-gate.sh` live) —
its verdict is not a function of a tree [R6, R8]. **The async safety net this design depends
on therefore does not currently exist in working form — building it is a precondition, not
an optimization** [R5 §6].

### 3.5 Deploy mechanism + green-stamp — covered in §2 [R6]

Smallest-change green-stamp chain [R6]: (1) `attest_land()` gains `head`/`base`/`tree` SHA
fields (values already in scope); (2) new `scripts/deploy-live.sh` — fetch, walk back from
`origin/main` to the newest green-stamped ancestor, `git merge --ff-only <that SHA>`, then
`./install.sh` (idempotent — also closes the known "new files never get linked" gap K26);
refuses + pages on no-stamp; (3) `operator-readout.sh:113` emits `deploy-live.sh` instead of
the raw pull. C10 constraint: the deploy stays operator-actuated; the stamp makes the
operator's one command *safe*, not automatic. Optional hardening: point worktree creation at
the stamped ref (`CC_DISPATCH_WT_BASE`, `handoff-fire.sh --base` — both already
parameterized).

### 3.6 Ecosystem prior art — the industry shape [R7]

**No serious org runs the full suite pre-merge.** Google TAP: deliberately-unsound fast
presubmit + async post-submit batched runs + culprit-finding + auto-rollback ("you can
accept some loss of coverage on presubmit… accept some number of rollbacks"). Meta:
ML-selected presubmit at ChangeRecall 99.9%, caught by an every-few-hours full run on
master. Chromium CQ: curated lossy builder set, **exoneration triple** (with-patch → retry
same config → without-patch; fail only if red-with AND green-without), retry rationale:
"retries increase the probability a flaky test lands sublinearly, but mitigate its impact on
unrelated CLs exponentially." Bazel: `--cache_test_results=auto` (never cache a red; never
cache `external`-tagged non-hermetic tests) — the memoization semantics to copy verbatim.
Zuul: AIMD concurrency window. Uber SubmitQueue: the formal proof that a serial full-gate
queue is unscalable.

bats-core 1.13.0 facts verified against the installed binary [R7, R4]:
`BATS_TEST_RETRIES` exists (since 1.5.0) but the **env var is clobbered** by
`bats-exec-file:10` — only `setup_file()`/`setup()` can set it, so a wrapper that re-runs
failed FILES is the cheapest global retry (and per-file overhead is 0.147 s). A
retried-then-passing test reports as a plain `ok` — **retry accounting must be built or
retries become flake blindness**. `--filter-status failed` exists (needs pre-existing
run-logs dir). `--filter-tags` is the native quarantine selector. `-j` requires GNU parallel
(absent; the `rush` on PATH is pnpm's — wrong binary).

### 3.7 The post-land async net — full design ready to implement [R8]

Key decisions (all evidence-anchored):
- **Trigger = both**: ship-land post-push detached spawn (`setsid` via the proven `detach()`
  pattern — `nohup`+`disown` is reaped by the harness's process-group SIGKILL,
  `handoff-fire.sh:283-298`) + a launchd 300 s poll backstop. One idempotent verb:
  `postland-verify.sh --run-if-needed`.
- **Dedup content-addressed on the TREE** (`rev-parse <sha>^{tree}`), stamps in
  `~/.claude/autonomy/postland/stamps/<tree>.json`. A revert to a previously-green tree is
  instantly known-green.
- **Supersession: requeue, never cancel** — a finished intermediate stamp permanently
  shrinks every future culprit set (the free bisect anchor). Single-slot queue = "current
  tip"; worst-case detection 2×suite ≈ 56 min in a burst, typical ≤ 28 min.
- **Dedicated persistent worktree** `~/Development/.worktrees/ci-postland` — never the
  shared checkout (that would DEPLOY the untested SHA — 176 live symlinks), never `/tmp`
  (macOS 3-day prune), created once (parallel `worktree add` has a config.lock race).
- **Runs exactly the landing gate's check-set widened to whole-tree** — never the nightly's
  live-state/designed-red checks (that mix is what rotted the nightly).
- **Retry ladder**: failed file re-run alone ×2, fresh private TMPDIR; fails ≥2/3 ⇒
  REPRODUCIBLE (bisect + page); 1/3 ⇒ flake-ledger entry (with loadavg + concurrent-lander
  count — a root-cause corpus), verdict GREEN-WITH-FLAKES, no page. 3rd ledger entry for the
  same test in 14 days auto-files a de-flake backlog item.
- **Bisect before paging**: `git bisect run bats tests/<failing-file>` over
  `last-green..red` — log2(k) runs of ONE file (~minutes); exit 125 = skip contract. Every
  page names one culprit commit.
- **Remediation = the live actuator loop**: `cc-backlog add` with the culprit SHA in the
  title (content-keyed ids + the `wasDone` latch otherwise swallow recurrences — a live bug
  that explains why two July-19 gate-red fixes are red again with no new item) →
  `cc-dispatch` spawns a fixer session. Deploy stays blocked (last-green not advanced).
  Auto-revert: designed but **default off** (single-culprit ∧ no escalation surface ∧
  revert-tree already stamped ∧ explicit env).
- **Pages**: state-keyed filenames (`postland-red-<culprit-sha12>.page`) — never a fixed key
  (the nightly's fixed key is why its page was swallowed); author session notified directly
  if live; `page-damp` fingerprint on state, not clock.
- **Inertness guard (blind-check law)**: nightly asserts "every trunk commit in the last
  24 h has a stamp" else RED "post-land net INERT"; per-run IDL `fired|abstained` records.
- Page volume estimate: ~7 runs/day, **≈1 page/day majority-real** with the ladder (vs ~6/day
  unusable without it) [R8 §6].

### 3.8 Policy surface + reso non-regression [R9]

- `/ship` dispatch is fully per-repo: infra's project `ship.md` → `scripts/ship-land.sh`
  (repo-local; reso has no such file); reso's `ship.md` → its own forked `land-lock.sh`
  (disjoint lock path `~/.reso/landing.lock.d`, disjoint log) + `ship-reconcile.sh` + its
  own git hooks. **Zero shared files, mutexes, markers, or logs** between the two rails;
  the one syntactic bridge (`desk-land.sh --repo`) hard-refuses a repo without
  `scripts/ship-land.sh` (exit 65). Isolation proven four independent ways [R9 §6].
- **Policy knob**: committed `scripts/gate-policy.sh` sourced by ship-land with
  env-over-file precedence (`SHIP_LAND_GATE_SCOPE` env > policy file > hardcoded `full`).
  Committed → reviewed in the same commit as the code; shell → self-gated by shellcheck;
  absent file → `full`. Rejected: prose-only env docs (no setter exists today), gitignored
  settings.local.json, user-level settings env (leaks cross-repo), machine-level YAML SSOT
  (not per-repo, needs a parser).
- **`gate-green` must remain FULL-suite-only** (option (a)): its three consumers
  (`boundary-handoff.sh` — "never advise handoff on an UNPROVEN-green tree",
  `wrap-ledger.sh` rungs, `operator-readout.sh` close block) all assume full-suite meaning;
  a scoped gate stamping it would make the handoff advisory lie. A scoped land leaves it
  stale/absent — readers degrade correctly to 🔧. Enforced by default
  `SHIP_LAND_GATE_SCOPE_MARK=full-only`. (The async net's green stamp is the NEW full-green
  signal; `postland-verify.sh` may additionally stamp `gate-green` when its full run passes
  at that HEAD.)
- Kill switches (all runtime-read in function bodies, matching the existing idiom):
  `SHIP_LAND_GATE_SCOPE=full` (instant byte-identical revert), `SHIP_LAND_GATE_POLICY=/dev/null`,
  `POSTLAND_VERIFY=off`, plus the unchanged `SHIP_LAND_GATE_ROUNDS/VERIFY_RETRIES/LAND_SERIALIZE`.
  Unrecognized scope value ⇒ LOUD non-zero exit, never a silent fallback.
- Caller contract: exits 2–8 keep their meanings; 42 stays internal; **64–66 are reserved by
  `desk-land.sh`** — no new ship-land exit may use them. No launchd job calls ship-land
  directly.

### 3.9 Red-team verdicts + lead dispositions [R10]

R10 attacked the candidate as a system (20 findings, F1–F20). Adopted into the plan:

- **F4 → M1 (must-fix, adopted): union-scope the CAS stale re-gate.** A scoped re-gate on
  round ≥2 sees only OUR diff — but the round exists because a SIBLING landed; its delta is
  the tree's only novelty and is by construction outside our scope, hollowing out the very
  loop the 2026-07-25 fix built. Fix: selection input on re-rounds =
  `union(GATE_BASE..HEAD, FIRST_BASE..GATE_BASE)` — one extra `git diff`. In T1/T2 contracts.
- **F5 (already covered):** renames → FULL via `--name-status` R-detection (belt: unknown
  status ⇒ FULL added).
- **F6 (already covered, verified stricter):** R10's zero-selection example (`lib/
  cc-upgrade-gate/check*.sh`, 709 LOC selecting nothing under a naive rule) hits BOTH the
  `*/lib/*`→FULL trigger and the package-dir clause here; new files → FULL; zero-selection
  code file → FULL.
- **F7 → M2 (adopted in lint form): anti-rot map lint.** Instead of 117 `# gate-scope:`
  declared headers (declaration-over-inference — deferred as backlog), `gate-select.sh lint`
  asserts every suite is reachable from ≥1 source file; ship-land runs it before EVERY scoped
  selection and falls back to FULL on lint red (fail-closed, ~2 s; R10 itself verified
  0/117 unreachable today, so it lands green).
- **F8–F11 (REJECTED with rationale — the one deliberate divergence): flake exoneration
  stays, bounded.** R10's premise for F8 ("every executed suite is in-scope") does not hold
  against this design's `--direct` distinction: scoped selection includes closure/package/
  token-selected suites that are NOT direct suites of the diff, and only those are
  exonerable; a direct suite that passes-on-retry is still RED. Pure always-RED-on-flake
  re-creates the exact U2 pathology (a 20 h block on an unrelated load-flake) this work
  exists to kill, and tonight's reproduced flake class was EXTERNAL SIGTERM (cross-session
  `pkill -f`), not product races. The laundering risk R10 correctly names (F9: a real
  sibling-interaction race misread as flake in the FULL-fallback path) is bounded by the
  postland net re-running the full suite on the composed tree ≤~30 min later and paging
  reproducible REDs. Every exoneration is ledgered with its signal; threshold-3-in-14-days
  auto-files a de-flake item; the fix-at-root doctrine stands — exoneration changes WHO is
  blocked, not WHETHER the defect is pursued.
- **F12/F13 (adopted):** the nightly's RED was unactionable because `run_check` discards all
  output — its page names checks with zero detail. Fix in-train: pages carry failing
  `not ok` lines + culprit + re-run command (both the new postland pager and the nightly).
- **F14 (already resolved in design):** requeue-not-cancel single-slot semantics [R8 §2.4].
- **F15/F16 (adopted):** runner worktree outside `/tmp` and outside session-reaper paths;
  stamps carry an env fingerprint (bats/cc/load) since outcomes aren't a pure tree function.
- **F17 (adopted): absence-is-loud via the landing rail itself** — scoped mode degrades to
  FULL with a loud warning when the newest green stamp is older than 24 h (net-inert ⇒
  landings slow down visibly instead of silently outrunning a dead net); plus the nightly
  inertness check (B4). Kill switch `POSTLAND_STALENESS_GUARD=off`.
- **F18 (already chosen):** suite-granularity bisect; forward-fix (backlog item + page) over
  auto-revert; auto-revert stays off.
- **F19 (accepted risk, backlogged):** priority inversion — a FULL-trigger lander under fast
  scoped siblings exhausts rounds more often and ends in the in-lock fallback (bounded,
  terminates; today's norm as worst case). FIFO land-intent ticket (~15 lines in land-lock)
  backlogged rather than complicating the mutex in v1.
- **F20 (accepted, mitigated):** the runner adds load → `nice 10` + LowPriorityIO + single
  in-flight run + single-slot queue.
- **R10's counter-proposal** ("fix `cc-reaper.bats` [25–37% of the suite] + GNU parallel +
  `bats -j 8` ⇒ ~5-min full gates; keep the invariant") — partially adopted: the
  lead-supervisor hoist and cc-reaper hardening are in-train (T6), the full `cc-reaper.bats`
  split is backlogged, and parallelism stays backlogged behind the /tmp-collision fixes
  because concurrent full suites are themselves the flake manufacturer (R10's own F20;
  measured 1.7× realized speedup, not 4×). A 5-min full gate still sits at 24% invalidation
  at burst λ (§1 table, G=300) — better, not sufficient; and it does nothing for false-RED
  flake exposure, which scales with tests-run-per-land.

## 4. Recommended architecture — "land scoped, verify async, deploy stamped"

The invariant swap, stated honestly: today's invariant is *"trunk is full-suite-green at
every commit, proven pre-push"* — bought at 46 min expected wall per land at burst, 62%
gate waste, and false-RED exposure proportional to 1,579 tests × rounds. The new invariant
set:

- **I1 (unchanged):** no lander can drop another's commits — CAS lock + content-verify,
  untouched.
- **I2 (unchanged):** nothing lands with red lint/syntax on changed files, or with a red
  suite among those mapped to the change (fail-closed selection, 100% measured recall).
- **I3 (new, replaces "trunk always full-green"):** every trunk tree is full-suite-verified
  within ≤ ~28 min (typ.) of landing; a reproducible RED pages with a bisected culprit and
  files remediation work; recurrence cannot be silently swallowed.
- **I4 (new, STRONGER than today for the live machine):** the live `~/.claude` layer only
  ever advances to a full-suite-green-stamped tree — a guarantee that does not exist today
  (the manual pull is unconditional).

Ranked by (reliability gain × implementation risk):

| # | Component | Gain | Risk | Verdict |
|---|---|---|---|---|
| S1 | **Post-land async net** (`postland-verify.sh` + stamps + bisect + backlog + pages) [R8 design] | Replaces a 7-nights-RED, never-delivered nightly signal with a per-land, attributed, damped one | Purely additive; separate mutex; own worktree | **Build — precondition for S2's flip** |
| S2 | **Changed-scope landing gate** (`gate-select.sh` + `run_gate` scoped mode + `gate-policy.sh`) [R1 rule + R2 conditions] | Kills the livelock (λG 0.93 → ~0.03) AND ~88% of flake exposure on unrelated lands; median land 15 min → seconds-to-4 min | The invariant swap; mitigated by fail-closed FULL triggers, S1 net, instant `SHIP_LAND_GATE_SCOPE=full` kill switch, `gate-green` untouched | **Build; default `scoped` in `gate-policy.sh`** |
| S3 | **Green-stamp-gated deploy** (`deploy-live.sh` + attest tree SHA + readout emit) [R6 design] | Live layer provably never runs an unverified tree (better than status quo) | 3 small edits + 1 new script; operator keeps actuation (C10) | **Build** |
| S4 | **Flake root-fixes + hermeticity ratchet** (land-lock.bats:59, lead-supervisor hoist, CC_IDL pin, lr-reset-poller /tmp, cc-reaper stamp-grace seam, hermeticity lint) [R3/R4] | Removes every reproduced/documented flake from the landing path; stops live-state leakage | One-line-to-small fixes, each independently green | **Build** |
| S5 | In-gate flake exoneration (failed FILE re-run once, fresh TMPDIR; out-of-scope pass-on-retry ⇒ ledgered flake + green; in-scope ⇒ RED) [R7 Chromium + R8 ladder] | Converts load-flakes from land-blockers into ledger entries with accounting | Small; accounting mandatory (bats hides retries) | **Build (inside S2)** |
| — | bats shard-parallelism, cc-reaper.bats split, AIMD window, auto-revert, Chromium without-patch leg, nightly tree/drift full split, worktree-from-stamped-ref | Real but secondary once G collapses | various | **Backlog** (each obsoleted ~10× by S2 or gated on S4's /tmp fixes) |

**Continuous validation replaces a one-time mutation sweep:** every postland RED is checked
against the land.log `selected` field of the culprit land — a failing suite that was NOT
selected at land time is a **measured false-skip**, auto-ledgered. The selector's soundness
is thereby monitored forever on real workload, not sampled once [supersedes R1's mutation-
sweep suggestion].

**Why reso keeps its gate:** reso deploys on push (Amplify + Fly); its trunk IS its deploy
artifact, so pre-push full gating is load-bearing there. This design changes only
claude-infrastructure files (`scripts/ship-land.sh`, new infra-local scripts, infra tests,
infra `ship.md`); the isolation proof is §3.8 / [R9 §6] — no shared file, mutex, marker, or
log, and the change stays producer-side.

## 5. Implementation plan

### Phase 0 — Agent Team orchestration (mandatory)

Team: `gate-reliability` · lead = this session (worktree `/private/tmp/wt-gate-reliability`,
branch `fix/gate-reliability` off `origin/main`). One spawn wave; contracts frozen in briefs
so teammates run in parallel; merge into the lead branch in dependency order; single landing
train via the project-local `/ship`.

| TM | Deliverable | New/edited files | Est. LOC | Depends on |
|---|---|---|---|---|
| **T1 selector** (xhigh) | The selection engine + its RED-proof suite | NEW `scripts/gate-select.sh`; NEW `tests/gate-select.bats` | ~350 | — (CLI contract frozen below) |
| **T2 ship-land integration** (xhigh) | Policy file; `run_gate` modes full/scoped/shadow; in-gate flake exoneration + ledger; attestation fields (`head`,`base`,`tree`,`gate_scope`,`selected_n`) + unlocked exit-6 attest; gate-green full-only guard; postland detached spawn | EDIT `scripts/ship-land.sh`; NEW `scripts/gate-policy.sh`; EDIT `tests/ship-land.bats`, `tests/land-gate-cas.bats` (selector RED-proof) | ~280 | T1 contract, T3 verb contract |
| **T3 postland runner** (high) | The async net runner + plist, per [R8 §8] | NEW `scripts/postland-verify.sh`; NEW `launchd/com.claude.postland-verify.plist` | ~400 | — (verb contract frozen below) |
| **T4 postland tests** (high) | RED-proof suite for T3 against the frozen contract | NEW `tests/postland-verify.bats` | ~330 | T3 contract |
| **T5 deploy stamp** (high) | Stamp-gated deploy + nightly inertness guard | NEW `scripts/deploy-live.sh`; EDIT `hooks/operator-readout.sh` (1 line); EDIT `scripts/nightly-regression.sh` (B4 check); NEW `tests/deploy-live.bats`; EDIT `scripts/rotate-autonomy-logs.sh` (register postland logs) | ~300 | S1 stamp layout (frozen) |
| **T6 flake fixes** (high) | The S4 set | EDIT `tests/land-lock.bats` (:59 `\|\| true`); EDIT `tests/lead-supervisor.bats` (setup_file hoist); EDIT `tests/session-continue.bats` (CC_IDL in setup); EDIT `tests/lr-reset-poller.bats` (/tmp → TMPDIR); EDIT `bin/cc-reaper` + `tests/cc-reaper.bats` (CC_REAPER_NOW stamp-grace seam + forcing test); NEW `scripts/test-hermeticity-lint.sh` + bats (ratchet: allowlist may only shrink) | ~300 | — |

**Frozen contracts (verbatim in briefs):**
- `gate-select.sh <base>..<head>` → stdout: newline-separated `tests/*.bats` paths, or the
  single token `FULL`, or nothing (provably-inert change, e.g. docs-only). Exit 0 always on
  success; any internal error ⇒ prints `FULL` (fail-closed) and exits 0; `--explain` adds a
  reason per line on stderr. Clauses per §3.1. Map cached per tree-hash under
  `$(git rev-parse --git-common-dir)/gate-select-cache/`.
- `postland-verify.sh` verbs: `--run-if-needed` · `--run <sha>` · `bisect <file> <good>
  <bad>` · `is-green <sha>` (exit 0/1) · `status` · `--selftest`. State under
  `~/.claude/autonomy/postland/` (`stamps/<tree>.json`, `last-green`, `queue`, `run.lock.d/`,
  `flakes.jsonl`, `runner.log`). Stamp JSON fields per [R8 §2.2]. Kill switch
  `POSTLAND_VERIFY=off` read at run time.
- Exit-code law: ship-land exits 2–8 unchanged; 42 internal; **64–66 forbidden** (desk-land
  reserves them).
- `gate-green` is written ONLY on a full-suite-green HEAD (mode full/shadow, or
  postland-verify's green full run at that HEAD).

Merge order: T1 → T2 (T2's bats need `gate-select.sh` present); T3 → T4 (tests import the
runner); T5, T6 independent. Gate + land as ONE train from the lead worktree via the
project-local `/ship` — this final land pays today's full gate once; every later land uses
the new pipeline.

### Rollout / kill switches

1. Land the train. `gate-policy.sh` ships `SHIP_LAND_GATE_SCOPE_DEFAULT=scoped` — the flip
   is in the same train as its safety net (the net's spawn path is live from the first
   post-land; the launchd poll backstop needs the operator to load
   `com.claude.postland-verify.plist` — staged as a pending-activation step, C10).
2. Instant reverts, all runtime: `SHIP_LAND_GATE_SCOPE=full` (env, per-invocation) or edit
   `gate-policy.sh` (one committed line); `POSTLAND_VERIFY=off`; deploy falls back to the
   raw pull if `deploy-live.sh` is bypassed (it only ever *adds* a refusal).
3. Watch: land.log `gate_scope`/`selected_n` fields; `postland/flakes.jsonl`; the false-skip
   ledger (postland RED ∧ suite ∉ selected). Any measured false-skip ⇒ tighten the rule (add
   the missing clause) — the map is code, reviewed like code.

### Implementation record (2026-07-25, same session)

All six teammates delivered; branches squash-merged onto `fix/gate-reliability` in
dependency order. Notables from the build:

- **The hermeticity ratchet caught its first two leaks at merge time** — the two NEW suites
  (`gate-select.bats`, `deploy-live.bats`), written by teammates who never saw the lint.
  Fixed lead-side (fixture `HOME` in setup()); lint clean at 121 suites, 109 grandfathered.
- **bats 1.13.0 swallows mid-body `[[ ]]` failures** (T1, probed): a failing `[[ ]]` that is
  not the test's last command does NOT fail the test — `false` and `[ ]` do. Assertions in
  this repo's 19K-line bats corpus can be silently decorative; T1's suites use `has()`/
  `lacks()` helper functions and reason-level `--explain` assertions instead, and
  mutation-tested all selection rules RED-proof (removed each rule; confirmed its test reds).
- **End-to-end dry-run validation**: with the merged pipeline, `ship-land.sh --dry-run` on
  this very train resolved scope=scoped (policy file), ran the map lint green (0/118
  unreachable, 0.5 s), and the selector returned `FULL <- added-unmapped:docs/activation/
  pending-activation/09-postland-verify-activate.sh` — the train that installs scoped gating
  correctly full-gates itself (new files are a fail-closed FULL trigger).
- The union-scope re-gate (M1) is derived from the range at all three gate call sites
  (`FIRST_BASE..range-base` as the sibling delta), so the stale-42 path, the in-lock
  fallback, and the post-drop re-gate all get it structurally.
- Live-IDL leakage fix measured: 294 fixture-sid rows had leaked into the real
  `autonomy/idl.jsonl`; after the `CC_IDL` pin a full suite run adds zero.
- **Cross-teammate seam caught at merge**: the staleness guard first matched stamp files
  named `*green*`, but the runner stamps `<tree>.json` with the verdict INSIDE — the guard
  would silently never fire (fail-open). Repointed at `last-green`'s mtime (touched on every
  green full verdict), which also upgrades the semantics: a trunk red for >24 h now degrades
  scoped landing to FULL even while the runner itself is alive.
- **Contract-first testing vindicated**: T4 wrote the runner's 14-test RED-proof suite
  against the frozen contract, in a worktree where the runner did not exist (verified 11/14
  fail against a do-nothing stub); on first contact with T3's real runner: 14/14 green.

### Out of scope (backlogged, with owners-when-picked-up)

bats shard-parallelism (blocked on the remaining /tmp literals); `cc-reaper.bats` 4-way
split; auto-revert enablement; Chromium without-patch exoneration leg; nightly tree/drift
full split (B4 inertness check IS in scope); `CC_DISPATCH_WT_BASE`/`handoff-fire --base` →
stamped-ref worktrees; bringing the 3 untracked live hooks into git; narrowing
`reaper-e2e.sh:24`'s machine-wide `pkill -f` pattern (cross-session gate-killer class,
§3.2); reviving the Session-Id trailer convention (superseded by land.log `head`+`sid`).
