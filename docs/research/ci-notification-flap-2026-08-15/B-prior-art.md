# B — Prior art: what was already tried against the "[renchris/claude-infrastructure] Run failed:" symptom

Axis: archaeology only. No solution proposed here.

## 0. Headline finding

**Task #157 is marked `completed`, but its own scope ("fix the repository so those classes stop
failing — landed") is NOT met for the `hermetic` workflow.** It IS met for the `diagrams` workflow
(genuinely fixed, durable — 15/15 recent runs green). The completion record for `hermetic` is
evidence of root-caused *test* defects, not evidence of the *notification symptom stopping* — and
measured against GitHub's own run history, the symptom never stopped:

- `hermetic` workflow-wide history since birth (2026-08-11): **96 failure / 3 success / 1 cancelled
  out of 100 recorded runs** (`gh run list --workflow hermetic.yml --limit 100 --json conclusion`).
- The only 3 successes ever are clustered on one day: **2026-08-13T01:46:29Z, 02:45:42Z,
  11:58:06Z** (runs 31658765932, 31661809706, 31697852580).
- **55 consecutive failures since that last success**, through the run in progress at the time of
  this research (31912550182, started 2026-08-15T22:35:54Z).
- Every failure's job breakdown is identical in shape: all 10 `suite (N)` shards `success`, only
  `verdict` fails (verified directly on run 31909790008). This is **the workflow working as
  designed**, not an infra fault — see §3.

## 1. Task #157 — full record and its own internal admission

`/Users/chrisren/.claude/tasks/claude-infrastructure-main/157.json`, status `completed`, file mtime
`2026-08-12T18:12:05Z` (UTC; `stat -f` local `Aug 12 11:12:05` PDT).

**That mtime lands 50 seconds after the task's own "IN FLIGHT" run was dispatched** (run
31626383663, `createdAt: 2026-08-12T18:11:15Z`) — i.e. #157 was flipped to `completed` while its
own cited confirmatory run was still queued/running, not after reading its result. That run's
actual conclusion was `failure`. The task's own text hedges this explicitly:

> "IN FLIGHT: hermetic run 31626383663 on current trunk — the first tree carrying every
> correction."

No later edit updated the record with that run's outcome, and the first real green (08-13
01:46:29Z) came **~7.5 hours after** the completion timestamp — so the completion was asserted
*before* any observed green, on the strength of root-cause analysis + local reproduction, not on a
CI verdict. This is not itself dishonest (the description is unusually rigorous about caveats —
see below) but it is the mechanism by which "completed" and "still red" coexist.

**CLASS 1 (diagrams, 56/97 of the original emails) — closed and durable, verified.** Cause:
`6a55cdf4d` (2026-08-11, "docs(land-arch): two figures published in two directions...") published a
re-measured land-lock figure into the README's mermaid fence without updating
`assets/diagrams/parallel-lanes.mmd`; the diagrams-check's own cure would have overwritten the
newer figure and reported a false success. Re-verified now: `gh run list --workflow diagrams.yml
--limit 15` → 15/15 `success`.

**CLASS 2 (hermetic, 41/97 of the original emails) — NOT closed, by the task's own words.** The
description names three residual reds at closing time:
- `lr-resume-answer-width` — **the task author's own first fix was inert** (`03b7a50c7`, C-locale
  byte-split diagnosis correct, cure vacuous: bash 3.2 doesn't re-run `setlocale()` on a for-loop
  binding, only on a plain assignment — corrected in `4ed74ee9c`, re-proven under the harness's
  actual env `env -i … LC_ALL=C`, no `LANG`).
- `autonomy-sweep` — attributed as "STALE, cured by a sibling's `7df8cb7e2` after that sha" — not a
  fix #157 made.
- `boundary-handoff` — **stated as "the one genuinely open item"**, filed as backlog `7f8bb9f43035`
  with an unresolved chain to instrument, explicitly "does not reproduce here… a blind fix would be
  a guess." This item was still open (no `done` event) as of this research.

So even by #157's own internal accounting, hermetic closed with one *known, unfixed, filed* red.

## 2. Everything that happened AFTER #157 closed (the part its own record could not see)

Traced via `~/.claude/autonomy/backlog.jsonl` (rows linked under condition
`master-verification-integrity`) and `gh run` history. This is the fuller arc #157's completion
evidence never captured:

| Date/time (UTC) | Event | sha / run | Mechanism |
|---|---|---|---|
| 08-12 10:06 | `8efd655b0fe1` filed | — | shard-cancellation hole: a runner shutdown signal kills a matrix shard mid-run, `if: always()` doesn't survive a cancelled job, 41 suites vanish from evidence silently |
| 08-12 10:24 | `4674ca4ff` lands | fix(offbox) | fold now reads `unreported` as its own state, ranked above `red`; a cut fold can no longer publish a false red — but the underlying cancellation cause is untouched |
| 08-13 07:29 | `9183cbf21772` closed | run 31586181611 | first FULL-COVERAGE hermetic verdict (404/404, unreported 0) — genuinely 3 reds, not a cut: `autonomy-sweep`, `lr-resume-answer-width` (3 cases), `boundary-handoff` |
| 08-13 07:29 | `05ff1e5fabc0` filed | — | harvests those 3 reds as CI-only / not reproducing on desk |
| 08-13 01:46–11:58 | **3 green runs** | 31658765932, 31661809706, 31697852580 | the only sustained green window ever observed |
| (window ends) | new class surfaces | — | `unattended-path-lint.bats` becomes deterministically red every run |
| 08-15 20:44 | `6a7eb069e703` filed | — | **still open**: `cc-close-attrib.bats` case 1 red 3-of-12 hermetic runs (race in a `>(tee)` process-substitution status read), green on desk, green in the other 9 — explicitly NOT manifest-excluded ("3-of-12 is a race, not a machine fact") |
| 08-15 20:49 | `05ff1e5fabc0` closed | `cf4160fa7` | the 3 CI-only reds are **retracted** (absent from all 12 folds 31877495900..31904202657 — genuine greenness) AND the class had **moved** to `unattended-path-lint.bats`, red 12/12 off-box, green 18/18 on desk — cause: the runner image lacks tmux/kitty/pnpm/yarn/uv on PATH, the desk resolves all five. Manifest-excluded WITH measurement. |
| 08-15 20:50 | `8efd655b0fe1` closed | `910f53fcb` | shard-cancellation root cause found and fixed: `bin/cc-reaper`'s sweep TERM'd its own ancestor (the runner service `runsvc.sh`) because the garbage-process heuristic matched a launchd-parented bash aged ≥600s — exactly the shape of a fresh GH Actions macOS runner. Fix: never signal an ancestor of the sweep itself; reaper suites now pin their garbage-PS fixtures. |
| 08-15 22:xx | run in progress | 31912550182 | outcome not yet known at time of writing |

**Reading this arc plainly: every closed item was correctly diagnosed and correctly fixed — but new
members kept joining the failing set faster than old ones left it**, and one (`6a7eb069e703`,
cc-close-attrib race) is *still open* as of this research. The workflow has not logged two
consecutive green runs since 08-13, let alone reached a stable green baseline.

## 3. Why the emails cannot stop even with the test corpus fully green — read from the workflow file

`.github/workflows/hermetic.yml`, full read (403 lines). Design summary:

- **Purpose** (lines 3-28): a second, off-box "green producer" for the machine-independent subset
  of the test corpus (`scripts/offbox-partition.sh`), because the on-box verifier only produces
  ~0.17 greens/day. It never gates a land — `/ship` never reads it (line 13).
- **Consumers**: exactly one, `scripts/offbox-green-pull.sh`, which reads the `verdict` job's
  conclusion through `gh api repos/$nwo/commits/$sha/check-runs` (see §4). Its own header states:
  "It is BINARY on purpose: this producer may emit a green or emit nothing" (lines 386-388).
- **The `verdict` job's last step, "the conclusion IS the verdict"** (lines 383-403), is a
  **deliberate, load-bearing design choice, present since the workflow's FIRST commit
  (`c93389772`, 2026-08-09/10)** — verified via `git show c93389772 -- .github/workflows/hermetic.yml`:
  the `exit 1` on non-green is original, not a regression introduced later. It exits 1 whenever the
  fold's own verdict isn't literally `"green"` — no distinction between `red` (a real failing
  suite) and `cut` (a shard died, no verdict at all). The comment at lines 10-13 states the INTENT
  precisely: *"a non-green here is never written anywhere the deploy lane reads as a red."* That
  claim is true of the deploy lane (§4) — it says nothing about GitHub's own native
  Actions-failure-email notification, which fires on **the same job conclusion** this design
  deliberately makes binary and easy to trip.
- **The noise is explicitly named as an accepted cost, not a bug**, lines 23-28: *"Because a new
  suite lands INSIDE the partition by default, a genuinely machine-coupled new suite reds this
  workflow on the land that adds it. That is the intended bill... a check that is red on every
  commit carries the same zero bits as one that cannot fire."* The `census` job (daily cron) is the
  design's own answer to a *rotting exclusion list*, not to notification volume — it does not touch
  the fact that the HOURLY partition run keeps failing while a new red is un-triaged.
- **Cadence**: hourly (`cron: '17 * * * *'`), chosen so the on-box `deploy-live.sh` gets a fresh
  candidate ~24×/day (lines 30-41) — i.e. by design this workflow runs, and can fail, **24 times a
  day**, every day, indefinitely. At 96% observed failure rate, that is ~23 failure notifications a
  day from this one workflow alone if GitHub email-notifies on every failed run for a watched repo.
- **No commit in this workflow's 10-commit history (`git log --follow -- .github/workflows/hermetic.yml`)
  ever touches notification behavior** — no `continue-on-error`, no split of "informational red" from
  "hard failure", no workflow-level opt-out. The list, oldest→newest: `c93389772` (birth),
  `c430543c4`, `e9b038790`, `39d78645c`, `3b9132547`, `77656a65d`, `06703a88c`, `33a8f41a8`,
  `4674ca4ff`, `13f09023d`. All are either building the partition/sharding or improving the fold's
  discrimination (red vs cut vs unreported) — none change what happens to GitHub-side notification
  when the job concludes `failure`.

**Conclusion of this section: the architecture makes the notification symptom and the workflow's
own stated correctness goal (a truthful non-gating acquittal signal) the SAME bit.** Any real,
un-triaged red or race — and the corpus is large enough (426 suites, hourly, against a ~63
commits/day trunk) that one is close to guaranteed at any given hour — reproduces the "Run failed"
email by construction, independent of whether the underlying test defect is real, stale, or a
known-benign race already filed and intentionally left unexcluded (as `6a7eb069e703` is, on
purpose — the manifest's own contract requires a *machine-coupling measurement*, not just
intermittency, to exclude a suite).

## 4. Consumer-map verification (the "never blocks a land" claim)

Grepped every `*.sh`/`*.py` in the repo for `check-runs`, `offbox-green-pull`, `offbox_green_pull`:
**the only caller of the GitHub check-runs API for this workflow's conclusion is
`scripts/offbox-green-pull.sh` itself** (no other consumer exists). Traced forward:

- `scripts/offbox-green-pull.sh` (263 lines, read in full): `check_conclusion()` (lines 85-99) maps
  `completed:success` → writes a stamp; anything else (`failure`, `pending`, `none`) → **writes
  nothing** (`*) : ;;   # failure ⇒ write NOTHING. This producer may acquit; it may not convict.`,
  line 146). Verified by its own selftest P2 ("a failure writes NOTHING") — ran conceptually via
  code read, not re-executed here (read-only research). Stamps land in
  `~/.claude/autonomy/postland/offbox/`, **never** in the on-box `stamps/` directory the deploy
  gate actually reads (explicit design note lines 14-22, to prevent a subset green being mistaken
  for a full-corpus green).
- `scripts/deploy-live.sh` reads that `offbox/` store only at line 1292, gated by
  `is_offbox_green()` (line 617) which additionally requires `scope:"offbox-hermetic"` — and only
  feeds the **T1H** tier (a bonus fast-path, never used to block or convict). Grep confirms no other
  file in `scripts/`, `hooks/`, or `bin/` touches `check-runs`, `offbox-verdict`, or the `hermetic`
  workflow's conclusion in any gating capacity.

**The "never blocks a land / never read as a red by the deploy lane" claim is VERIFIED TRUE by
code**, not just by comment. The entire notification symptom is therefore orthogonal to every
internal consumer this repo has — it is purely GitHub's own account/repo-level Actions-notification
delivery reacting to the `verdict` job's binary conclusion, which is a channel #157 and every
descendant fix never touched.

## 5. Other tasks/board items on this symptom

Full board sweep (`~/.claude/tasks/claude-infrastructure-main/*.json`, ~150 files) for
hermetic/offbox/notification/green-pull/workflow-failure hits: **112, 116, 119, 120, 121, 124, 127,
150, 157, 28, 30, 35, 54, 55, 59, 63, 66, 73, 74, 88, 98**. Read all subjects; only two are
substantively on-topic:

- **#157** — this record (above).
- **#124**, `pending`: "Corpus lint: no suite executing a terminal-aware script may inherit a live
  KITTY_WINDOW_ID" — a generalization of a *different* hermeticity class (terminal-state leakage
  into /Users/chrisren/.claude/bin/cc-bats suites), proposing a lint rather than touching the `hermetic` workflow or notification
  path. Adjacent vocabulary ("hermetic", "the class"), not the same symptom.

The rest (`112, 116, 119, 120, 121, 127, 150, 28, 30, 54, 55, 59, 63, 66, 73, 74, 88, 98`) are false
positives on `notify`/`CI ` substring matches — they are about `cc-notify` (the internal cross-session
mail/desk notification substrate), git-identity, gate-contention, or unrelated infra; none reference
GitHub Actions email or the `hermetic`/`diagrams` workflows. Confirmed by reading each subject +
status directly.

**`git log --all --oneline --grep=` sweep for `notification`/`notify`** turned up zero commits about
GitHub Actions email consolidation — every hit is `cc-notify` (internal mail), `idle_notification`
(Claude Code's own hook), or QoS `notify-only` signals. The vocabulary "consolidate CI notifications"
exists only in task #157's title; no commit message, plan doc, or research doc anywhere in the repo
uses it. `docs/plans/` and `docs/research/` grepped for hermetic/offbox/notification: the substantive
design doc is `docs/plans/DEPLOY_LANE_GROUND_UP.md` §1.5-§1.9 (the `hermetic`/`offbox` architecture's
own design record) — read its relevant sections; **it documents WHY the workflow is a binary
green-or-nothing producer and WHY that's safe for the deploy lane, but contains no section on GitHub
notification volume or email consolidation.** The gap this task is investigating was never
architecturally addressed anywhere in this repo's history — only the underlying test-corpus
correctness was.

## 6. Answering the CRITICAL QUESTION directly

**Was #157 closed against a different notification source, leaving hermetic untouched?** No — it
correctly targeted BOTH sources (diagrams + hermetic) and diagrams is genuinely, durably fixed.

**Did it address hermetic and regress?** Not quite "regress" — more precisely: **it closed hermetic
on inferential/partial evidence (one known-open red filed as a follow-up, completion timestamped
before its own cited confirmatory run finished) and the underlying test corpus then continued to
produce a steady trickle of NEW machine-coupled/racy reds** (shard-cancellation → fixed 08-15;
unattended-path-lint → excluded 08-15; cc-close-attrib race → still open). Each individual defect
found was real and each fix was correctly evidenced — but the **workflow's own architecture makes
the GitHub-native failure notification and "any one of 426 suites has an un-triaged red this hour"
the same event**, and with an hourly cadence against a fast-moving trunk, that is a near-permanent
state, not a bug that a fixed set of root causes retires. The one 10.5-hour green window
(2026-08-13T01:46–11:58Z, 3 runs) is the only period the symptom was ever actually absent, and #157
was already marked `completed` for ~7.5 hours before it started.

**Unevidenced-completion check**: #157 does have real evidence (it is not a blank completion) but
that evidence never included an observed green `hermetic` run, and its own text names the item that
would have contradicted "done" (`boundary-handoff`, "the one genuinely open item") — filed rather
than resolved. That is the finding: **completion was declared on convergence of diagnosis, not on
observed cessation of the notification symptom**, and the symptom (verified via `gh run list`) has
in fact continued at ~96% failure rate in the 55 runs since the only green window closed.

## Sources / shas referenced

Tasks: `~/.claude/tasks/claude-infrastructure-main/157.json`, `124.json`.
Backlog rows (`~/.claude/autonomy/backlog.jsonl`): `8efd655b0fe1`, `9183cbf21772`, `7f8bb9f43035`,
`05ff1e5fabc0`, `6a7eb069e703`.
Commits: `6a55cdf4d` (diagrams fix), `c93389772` (hermetic.yml birth), `4674ca4ff` (fold unreported
ranking), `03b7a50c7`/`4ed74ee9c` (locale fix + its own inert-first-attempt), `7df8cb7e2`
(autonomy-sweep, sibling fix), `cf4160fa7` (unattended-path-lint manifest exclusion),
`910f53fcb` (reaper self-ancestor fix).
Workflow runs: 31626383663, 31586181611, 31658765932, 31661809706, 31697852580 (the only 3 greens),
31909790008 (representative current failure, verdict artifact
`{"verdict":"red","suites":426,"expected":426,"green":425,"red":1,"failing":["tests/cc-close-attrib.bats"]}`),
31912550182 (in progress at research time).
Files read in full: `.github/workflows/hermetic.yml` (403 lines), `scripts/offbox-green-pull.sh`
(263 lines); `scripts/deploy-live.sh` read at lines 94-95, 613-628, 1292.
