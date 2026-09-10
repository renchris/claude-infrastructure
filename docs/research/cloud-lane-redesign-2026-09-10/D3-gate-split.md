# D3 — Pricing the SPLIT design's LOCAL half

**Verdict up front, and it inverts the brief's premise.** The bats smoke is **not** the land's
dominant cost and has not been for a month. Over 217 single-round successful local lands since
2026-09-01 (`~/.claude/land.log`, `gate_arms_s`/`smoke_s` fields): **p50 total 722 s = arms 312 s +
statics 0 s + smoke 0 s + outside-gate 334 s.** A VM that absorbed **100 % of the hermetic bats
partition** would move the median land by **zero seconds**, because the median land runs no smoke at
all. In aggregate over the same population the smoke is **5.5 %** of land wall time and the ratchet
arms are **52.0 %**. The briefed split targets the small term.

Second finding: **the off-box producer has emitted 0 greens since 2026-08-13** — 28 days — and the
2026-09-10 bash-3.2 fix (`ec3f7c0f8`, landed 19:47 Z) **has not been exercised by a single fold**;
the newest fold started 18:25 Z. There is nothing to trust yet even if a trust path existed.

Third: **no trust path exists in the land path, and a tree-sha-keyed one is structurally
unreachable pre-land.** Only two files in the tree read the off-box store —
`scripts/offbox-green-pull.sh` (its producer) and `scripts/deploy-live.sh` (the T1H **deploy** tier).
`ship-land.sh` and `postland-verify.sh` read neither.

---

## (i) Partition table

`bash scripts/offbox-partition.sh lint` → `clean — 654 suites = 613 partition + 41 excluded
(3 host, 38 off-box)` (rc 0, measured this session).

| | count | share | off-box runtime | share |
|---|---|---|---|---|
| all `tests/*.bats` | **654** | 100 % | — | — |
| in the hermetic partition (VM-runnable) | **613** | 93.7 % | **7,116 s** | **68.2 %** |
| excluded — `host-suites.manifest` | 3 | 0.5 % | (inside the 3,312 s) | — |
| excluded — `offbox-excluded.manifest` | 38 | 5.8 % | (inside the 3,312 s) | — |
| **excluded, total** | **41** | **6.3 %** | **3,312 s** | **31.8 %** |

Runtime measured from the shard TSVs of **census run 34484868431** (the one run in the window that
executes the excluded suites too; `secs` column, `scripts/offbox-run.sh:224`). Per-suite mean:
partition **11.8 s**, excluded **80.8 s** — the excluded set is **6.8× more expensive per suite**.
⚠️ **31.8 % is a LOWER bound**: 8 of the 41 hit the 300 s `CC_OFFBOX_SUITE_BOUND_S` ceiling and were
recorded *at* the bound, not at their real cost (`cc-reaper` 306 s, `test-hermeticity-lint` 301 s,
`deploy-parity-live` 301 s, `postland-verify` 300 s, `postland-verify-passfloor` 300 s,
`cc-await-ping` 300 s, `unattended-path-lint` 300 s, plus `worktree-gc-infra` 254 s).

**Exclusion reasons, grouped** (line numbers = the entry's line in
`scripts/offbox-excluded.manifest`; the manifest's own section headings):

| reason group | n | entries |
|---|---|---|
| terminal-emulator surface (drives/asserts a live iTerm2/kitty) | 3 | `it2-wrapper`:70 · `iterm2-appname-lint`:78 · `handoff-selfclose-kitty-identity`:80 |
| launchd / Darwin QoS / sysctl | 5 | `capacity-alarm-launchd-path`:85 · `capacity-admit`:90 · `idle-slope-sweep`:92 · `qos-rewrite`:94 · `boot-resume`:96 |
| the operator's live state — sessions, panes, inbox, dispatch, accounts | 7 | `operator-readout`:118 · `cc-inbox-guard`:120 · `cc-reconcile`:122 · `cc-dispatch-v2`:124 · `session-index-sweep`:126 · `session-index-end-first-prompt`:128 · `handoff-fire-completion-push`:130 |
| host toolchain assumptions (runner ships no tmux/kitty/pnpm/yarn/uv) | 3 | `python-deps`:135 · `unattended-path-lint`:150 · `subshell-cleanup-lint`:152 |
| 2nd seeding — suites the truncated shards had been hiding | 6 | `handoff-selfclose-pane-identity`:162 · `handoff-fire-capacity-gate`:168 · `session-register-reclaim`:170 · `cc-await-ping`:172 · `qos-chokepoint`:174 · `suggest-filter`:176 |
| 3rd seeding — the steady-state case | 5 | `account-fact-derivation`:189 · `compressor-sentinel`:191 · `pool-floor`:193 · `rotate-autonomy-logs`:195 · `worktree-gc-infra`:214 |
| **the land and verify machinery itself** | 4 | `ship-land`:283 · `postland-verify-bisect-bound`:285 · `postland-verify`:289 · `postland-verify-passfloor`:306 |
| 5th seeding 2026-09-05 | 4 | `cc-resume-field-order`:339 · `pipefail-sigpipe-lint`:346 · `capacity-alarm`:353 · `cc-reaper`:360 |
| 6th seeding 2026-09-08 (23 folds) | 1 | `bats-assert-liveness`:386 |
| `host-suites.manifest` — live-deployed-layer + whole-tree meta-lint wrappers | 3 | `deploy-parity-live` · `test-hermeticity-lint` · `test-walltime-lint` |

🚨 **The load-bearing row is "the land and verify machinery itself."** Four of the seven
most-expensive excluded suites are `ship-land` / `postland-verify*`. A land that *changes the
lander* selects exactly those as its direct set — so the class of land most worth de-risking is the
one a VM pre-run cannot cover at all.

---

## (ii) ship-land gate composition

Stage order is the order `run_gate` executes; time share is the **aggregate** over 423 successful
local lands since 2026-09-01 (`land.log`, exit 0, `stage=land`, branch not `claude/*`).

| # | stage | what it asserts | needs the box? | measured share |
|---|---|---|---|---|
| 0 | `$HOME` isolation (APFS clone of `~/.claude` etc.) | bats mutations cannot reach the live `~/` | **YES** — clones the live layer; fails open to it (`:1885`) | inside `gate_s`, not separately timed |
| 1 | **statics** — shellcheck · `bash -n` · `py_compile` | shell/py parse + lint on changed files | no | `gate_statics_s` **0.1 %** (p50 **1 s**) — retired by the blob-sha memo (`scripts/lib/gate-memo.sh`) |
| 2 | test-hermeticity ratchet (own-scope) `:3150` | no new suite runs against ambient state | no — scans repo text only (verified: only `$HOME` refs are patterns + a selftest scratch dir) | ↓ |
| 3 | wall-clock time-bomb `:3191` | no future absolute date in a fixture | no | ↓ |
| 4 | AF_UNIX absolute-bind `:3222` | no 104-byte `sun_path` bomb | no | ↓ |
| 5 | moving-ref control `:3263` | no control replayed from an advancing ref | no | ↓ |
| 6 | git-identity escape `:3306` | no fixture identity can reach the caller's repo | no | ↓ |
| 7 | UTC timestamp-contract `:3363` | no literal `Z` from a local clock | no | ↓ |
| 8 | pipefail/SIGPIPE `:3419` | no early-exit pipe consumer reading FALSE | no | ↓ |
| 9 | bats dead-assertion `:3486` | no assertion errexit cannot reach | no | ↓ |
| 10 | script-dir resolution `:3576` | no repo root from an unresolved `$0` | no | ↓ |
| 11 | pane-spawn coverage `:3623` | no spawn site leaving no row | no | ↓ |
| 12 | bare-name binaries on unattended paths `:3707` | launchd targets resolve | **no** — reads `"$ROOT"/launchd/*.plist`, the **repo** SSOT (`:1433`, `:1705`, `:1749`), not `~/Library/LaunchAgents` | ↓ |
| 13 | unbounded permission gates `:3773` | no guard-refusal on an actuation path | no | ↓ |
| 14 | chromium-bundle `:3820` | no screenshot path launching the app bundle | no | ↓ |
| 15 | TSV field-collapse `:3882` | no IFS=tab reader over a padless producer | no | ↓ |
| 16 | `.bats` shellcheck `:3955` | no shellcheck finding on a line this land wrote | no | ↓ |
| 17 | unguarded-kill `:4008` | no kill silencing stderr but not status | no | ↓ |
| 18 | `@test`-name eval `:4053` | no test name a shell expansion deletes | no | ↓ |
| 19 | loaded-but-untracked `:4097` | no harness-loaded path git neither tracks nor ignores | no | ↓ |
| 20 | **off-box ADMISSION** `:4128-4169` | a suite this land ADDS is green off-box (runs it under the producer's 300 s bound) | no | ↓ |
| | **stages 2-20 = `gate_arms_s`** | | | **52.0 %** (p50 **549 s** all-rounds · **312 s** single-round) |
| 21 | **smoke** — `GATE_SELECT --direct`, host-suite filter `:2128`, load shed `CC_GATE_MAX_LOAD` `:2302`, budget `SHIP_LAND_SMOKE_BUDGET_S` `:2324`, exoneration re-runs `:2575-2786` | the direct suites of this diff pass | **YES** — bats against the cloned `~/`; **structurally banned under the mutex** (`:2160` `none-locked`) | **5.5 %** (p50 **0 s**) |
| 22 | outside the gate — land-lock queue · in-lock re-fetch · rebase · push · stranded sweep | — | **YES** (lock is per-box) | **25.3 %** (p50 **334 s** single-round) |

**Why the arms are box-independent** — every one of the 19 lints is a scan over **repo text**. The
`$HOME` / `launchctl` / `osascript` hits in them are (a) fixture strings inside their own
`--selftest` bodies or (b) grep patterns. The one that looked box-bound,
`unattended-path-lint.sh`, reads the plists out of `$ROOT/launchd/`. Empirical, comment-stripped
grep across all 16 arm lints: zero runtime reads of `~/.claude`, `launchctl`, `sysctl` or panes.

⚠️ **Do NOT price an arm by running it bare.** `scripts/lib/gate-memo.sh:366-369`:
*"measured bare, bats-shellcheck-lint is 50.5 s and looks like the biggest target in the gate;
measured through `own_run` as ship-land actually calls it, it is 0.07 s."* This report therefore
prices the arms only from `land.log`'s `gate_arms_s`, never from a standalone run.

---

## (iii) Land-cost split from real land logs

**The logs the brief pointed at cannot do this; `land.log` can.** Of the 80
`~/.claude/autonomy/cloud/*.land-refused` transcripts, only **8** contain any `→ gate:` line and
**none** carries per-stage timing — the deepest they go is `gate: smoke — 28 direct suite(s),
≤900 s total`. The 54 `*.land-cost` sidecars hold one total each and **18 of the 54 are `floor`
markers, not measurements** (`scripts/cloud-return.sh:753` writes `BOUND_S − elapsed` capped at the
global price when a land is **cut**; its own comment: *"a floor records 'at least this much' about a
land that was CUT … a lower bound on an unknown, not an observation of it"*).

The real instrument is **`attest_land`** (`scripts/ship-land.sh:713-758`), one JSON line per land
into `~/.claude/land.log` carrying `total_s · gate_s · gate_arms_s · gate_statics_s · smoke_s ·
smoke_n · smoke · gate_rounds · red · tree · base`. **9,852 rows, 0 unparsed; 3,846 carry the
timing fields; 3,066 are terminal (`stage=land`), 1,228 exit 0.** Window
2026-08-11T09:34 Z → 2026-09-10T20:11 Z. Per-row arithmetic checks out:
`gate_s − (statics+arms+smoke)` is **≥ 0 on 3,066/3,066 rows** (p50 4 s of loop overhead), so the
three sub-fields are a genuine partition of `gate_s`.

### The split (aggregate seconds and p50)

| population | n | p50 total | p50 gate | p50 arms | p50 smoke | p50 outside-gate | AGG arms | AGG smoke | AGG outside |
|---|---|---|---|---|---|---|---|---|---|
| all terminal lands (all outcomes) | 3,066 | 302 s | 176 s | 124 s | 0 s | 12 s | 52.8 % | 15.9 % | 19.6 % |
| all successful (exit 0) | 1,228 | 526 s | 287 s | 167 s | 0 s | 229 s | 45.4 % | 12.2 % | 28.8 % |
| **successful local, since 09-01** | **423** | **1,082 s** | 714 s | **549 s** | **0 s** | 368 s | **52.0 %** | **5.5 %** | 25.3 % |
| **↳ single-round only (`gate_rounds=1`)** | **217** | **722 s** | 388 s | **312 s** | **0 s** | **334 s** | 49.9 % | 10.9 % | 37.5 % |
| successful, smoke actually RAN | 553 | 613 s | 378 s | 165 s | **120 s** | — | 35.2 % | 30.2 % | — |
| successful **cloud** (`claude/*`), all time | 73 | 444 s | 232 s | 167 s | 0 s | — | 36.4 % | 28.5 % | 29.0 % |
| all cloud lands (any exit) | 1,135 | 29 s | 0 s | 0 s | 0 s | — | **80.2 %** | 7.8 % | 8.1 % |

**Where §A9's "700-3,900 s" comes from and what it is.** `docs/plans/CLOUD_BACKLOG_PIPELINE.md`
§A9.2 M2 measured *cloud* lands in the darwinbg band: *"36 of 40 attempted lands exit 143 … the 4
that completed ran 974 · 1,783 · 3,063 · 3,856 s."* Reproduced: the 5 successful cloud lands since
09-01 read p50 **1,935 s**, p75 **3,856 s**. That band is **not** the general land cost — its
exit distribution is 562 × exit 5 (merge-tree conflict precheck) + 319 × exit 143 (cut by the
sweep bound) + 170 × exit 6 (gate red) against only **73 exit 0 ever**. n=5 is not a basis for a
projection; use the 423-row local population.

### Two terms not in the brief's model

1. **Re-gating is 53 % of the arms bill.** Since 09-01, arms total 434,264 s; if each land ran the
   arms once it would be 205,196 s. `gate_rounds` distribution: 217×1, 87×2, 37×3, 86×4. Cause is
   the optimistic-round livelock (`STALE GATE` → release lock → re-gate) already in the repo memory.
   A VM cannot remove this: the arms must judge the **rebased** tree.
2. **The land-lock queue.** `land.log` lock events: `acquired.wait_s` since 09-01 **p50 284 s, p90
   719 s, max 1,700 s** (n=204). Joined to their land rows on branch (n=92 — the contended subset),
   lock wait is p50 **304 s** = 35 % of that subset's p50 748 s outside-gate. Purely a per-box
   concurrency cost; a VM touches none of it. (Attribution caveat: the join only reaches 22 % of
   lands, and that subset's outside-gate is 2.2× the single-round median, so I cannot decompose the
   334 s single-round outside-gate cleanly — the lock is a **material but not fully attributed**
   share of it.)

### Why the arms grew 2.8×

`scripts/lib/gate-memo.sh:16-19` measured the arms at **~112 s** (2026-08-10) and **~135 s**
(2026-08-13, `:361`), with `test-hermeticity` alone 30.7 s → 46.0 s. Today's single-round p50 is
**312 s**. Two accountable factors, empirical: the corpus went ~405 → **654** suites (1.6×;
405 from `ship-land.sh:4135`'s 2026-08-12 note) and the arm count went 15 → **19** (1.27×).
1.6 × 1.27 = 2.0× against an observed 2.8×; the residual is box load, not adjudicated here.

---

## (iv) What fraction a VM-side green could replace, and whether a trust path exists

### The replaceable fraction

| what a VM absorbs | resulting p50 (from 722 s) | Δ |
|---|---|---|
| **the hermetic bats partition (the briefed split)** | **722 s** | **0 s** — the median land's `smoke_s` is already 0 |
| the smoke on the 45 % of lands where it runs | 613 → 493 s on that subset | −120 s p50, −30.2 % aggregate **on that subset only** |
| smoke + **all 19 arms** (not briefed; see soundness below) | **410 s** | −312 s |
| the above + the land-lock queue and fetch/rebase/push | **76 s** | −646 s |

**Why the median is 0.** Of 423 successful local lands since 09-01, `smoke` state was:
`green` 116 · `none-locked` 99 · `none-undecided` 70 · `none-nodirect` 69 · `partial` 55 ·
`skipped` 14. So **252 of 423 (60 %) ran no smoke at all**, for four structurally different
reasons — the land came through the in-lock fallback lane where *"bats is structurally banned under
the mutex"* (`:2160`), `gate-select` answered `FULL` (its fail-closed abstention), zero direct
suites mapped (lint-only land), or the load shed fired.

**Independent confirmation from the selector.** Ran `scripts/gate-select.sh --direct <sha>~1..<sha>`
over the last **40 trunk commits** (read-only): 3 → `FULL`; of the 37 that listed, **10 (27 %)
selected zero suites**. Of the 27 non-empty sets: **18 (67 %) are wholly inside the partition** and
**9 (33 %) contain at least one box-bound suite** — so a VM pre-run could fully cover the smoke for
**~49 % of commits** (67 % × 73 %). By suite count 336/370 = **90.8 %** of selected suites are
VM-runnable. The box-bound suites that got picked, by frequency: `operator-readout` (4),
`pipefail-sigpipe-lint` (4), `cc-reaper` (3), `test-hermeticity-lint` (3), `iterm2-appname-lint` (3),
`ship-land` (2), `postland-verify*`…

### Does a trust path exist? No.

Grepped `scripts/`, `bin/`, `hooks/` for the store: **exactly two consumers** —
`scripts/offbox-green-pull.sh` (the producer's puller) and `scripts/deploy-live.sh`.
`ship-land.sh` reads `postland/stamps` (`:1542`, `:1606`) and `postland/flakes.jsonl` and **never
`postland/offbox`**. `postland-verify.sh` mentions `offbox` only in a comment about JSON escaping
(`:841`). The one live trust rule is `deploy-live.sh:2073-2098`'s **T1H tier** —
`is_offbox_green()` (`:845`) requires **both** `verdict:"green"` **and** `scope:"offbox-hermetic"`,
in a separate directory, deliberately never in `stamps/` (`offbox-green-pull.sh:13-20`: a subset
green in `stamps/` *"would become a T1 deploy target with no code change and nothing to review"*).
That is a **deploy** decision, not a **land** decision, and it is post-land by construction.

### 🚨 A tree-sha-keyed stamp cannot hit a pre-land gate

Measured: **428 of 428** distinct trees gated by successful lands since 09-01 are also trees on
`origin/main` — because ship-land attests **after** the rebase and then pushes. That tree therefore
first exists on trunk *at the moment of the land*. The producer runs on a **schedule against
`main`'s tip**, so it can only judge that tree **afterwards**, and only if a fold happens to catch
it. Overlap of the 4 off-box-stamped trees with the 428 gated trees: **0**. With `origin/main`
trees in the last 20 days: **0**.

Coverage arithmetic, measured, not quoted from a cron:

| day | delivered scheduled runs | trunk commits | tree coverage |
|---|---|---|---|
| 09-05 | 9 | 42 | 21.4 % |
| 09-06 | 9 | 16 | 56.2 % |
| 09-07 | 6 | 90 | 6.7 % |
| 09-08 | 7 | 152 | 4.6 % |
| 09-09 | 7 | 140 | 5.0 % |
| 09-10 | 6 | 94 | 6.4 % |

Run wall time p50 **25.0 min**, p90 34.5 min, max 48.3 min (198 completed scheduled runs) — so a
green arrives 2-6 commits stale even when it arrives.

### What it would actually take

- **A tree-sha stamp: dead on arrival.** ~5-7 % of trunk trees are judged and none of them is a
  pre-rebase land tree. The key is wrong, not the plumbing.
- **A per-suite, per-blob-sha memo is the shape that works, and the repo has already priced it.**
  `gate-memo.sh:353-357`: *"What WOULD reach the target is per-file memoization INSIDE each lint's
  scan loop … That needs a file-locality proof per lint … and touches ~15 gate scripts."* Status
  `:359-364`: **started, one lint done** — `test-hermeticity-lint.sh` memoizes per suite with a
  checker-id carrying its read set (`HERM_READSET`; pinned by `tests/herm-suite-memo.bats`), taking
  46.0 s → 10.4 s fixed + 0.069 s/suite.
- **The arm-level key the spec asked for is measured-insufficient and stays rejected.**
  `gate-memo.sh:337-351`: keying an arm on (lint blob + scanned-set state) lets a re-round skip it
  only when the sibling's delta missed that arm's population — true for **35-46 % of lands per arm**,
  27 % whole-tree — *and* the population declaration is **not a superset today** (two
  counter-examples found by reading the lints: `unattended-path-lint` also judges `settings.json`
  which its pathspec omits; `pipefail`'s pathspec lists `docs/*`). Keying on a non-superset is a
  stale-verdict generator.
- **A ratchet already exists in the right direction, aimed the other way.** The `offbox-admission`
  arm (`ship-land.sh:4128`) makes an author prove a **newly added** suite green off-box before
  landing it. That is the producer's *growth* side. Nothing consumes the producer's *output* on the
  land path.

---

## (v) `hermetic` workflow delivered runs since 2026-09-10T00:00 Z

Counted events (`gh run list --workflow hermetic.yml --limit 200 --json
databaseId,createdAt,updatedAt,conclusion,event,status,headBranch,headSha`), never a cron:

| day | event | run conclusion | n |
|---|---|---|---|
| 2026-09-10 | `schedule` | `success` | **5** |
| 2026-09-10 | `schedule` | `failure` | **1** |
| | | **total delivered** | **6** |

🚨 **`success` on the RUN is not a green, and this is the trap.** The only publisher of a green is
the `verdict` job (`hermetic.yml:452-460`, `if: needs.fold.outputs.verdict == 'green'`), which
`offbox-green-pull.sh` reads by check-run name (`JOB_NAME="${CC_OFFBOX_JOB:-verdict}"`). A skipped
job leaves the **run** at `success` — this is documented in the workflow itself from probe runs
31913525656/31913525664: *"a job skipped by an `if:` on a needs-output → check-run
`completed:skipped`, RUN `success`"*, and *"`skipped` is not `success`"*. Job-level read of all
five successes:

| run | started | `fold` | `verdict` | fold JSON |
|---|---|---|---|---|
| 34420334700 | 00:13 Z | success | **skipped** | 590 suites, 582 green, **8 red** |
| 34438126852 | 04:41 Z | — | **skipped** | `suite (1)` **failed** ⇒ run failure |
| 34462014127 | 09:41 Z | success | **skipped** | 601 suites, 588 green, **13 red** |
| 34484868431 | 13:47 Z | success | **skipped** | **645** suites (census), 594 green, 47 red, 4 non-verdict |
| 34488874963 | 14:24 Z | success | **skipped** | 604 suites, 587 green, **16 red**, 1 nv |
| 34514270238 | 18:25 Z | success | **skipped** | 606 suites, 588 green, **17 red**, 1 nv, `run_s` 7,454 |

**Has any green occurred post-fix? No — and no fold has yet contained the fix.** `ec3f7c0f8`
(*"fix(mcp-ssot-wire): one apostrophe…"*) is an ancestor of `origin/main`, committed
**2026-09-10T14:47:10−05:00 = 19:47 Z**. Every one of the 13 folds since 09-09T00:00 Z — including
all six on 09-10 — has a head sha that **does not contain it** (`git merge-base --is-ancestor`
checked per run). The `docs/research/offbox-deterministic-floor-2026-09-10.md` §7 limit is exactly
right and still open: *"The fix is verified locally, not off-box. The next scheduled fold whose head
contains it is the proof."*

**Last green in the store: 2026-08-13.** `~/.claude/autonomy/postland/offbox/` holds **4** stamps,
all `verdict:green scope:offbox-hermetic`, timestamped 2026-08-10T09:50 Z, 08-13T02:04 Z,
08-13T03:44 Z, 08-13T12:22 Z. **28 days with no new T1H fuel.**

**The remaining deterministic reds (post-fix-attempt, pre-fix-delivery).** Intersection of the four
*partition* folds on 09-10 (excluding the census) — red in 4/4:

- `tests/idl-record-size.bats`
- `tests/lr-reset-poller-inplace.bats`
- `tests/mcp-no-inherit.bats` ← cured by `ec3f7c0f8`, unproven off-box
- `tests/mcp-ssot-wire.bats` ← cured by `ec3f7c0f8`, unproven off-box

Red in 3/4: `capacity-alarm-chronic`, `cc-jetsam-exec`, `cc-read-twitter`, `runner-stdin-immunity`,
`session-index-history-gapfill`, `validate-bash-differential`. Red in 2/4: the five
`install-*` suites (`fleet-activation`, `resident-reload`, `stale-refusal`,
`templatedir-home-guard`, `worktree-refusal`) + `typed-send-lint` — all appearing together at
14:24 Z, the "five together at fold 11" shape §6 of the 09-10 doc names. Union across the four
folds: **24 distinct suites**. Red count climbs monotonically through the day (8 → 13 → 16 → 17) as
the corpus grows — the *"new suites land red off-box and stay red, and nothing tells their author
the producer just went red"* admission gap.

**So even with the apostrophe fix delivered, expect the next floor, not a green** — 2 of the 4/4
core are cured, 2 are not, and 6 more sit at 3/4.

*Uncertainty named:* run 34484868431 started 13:47 Z but folded 645 suites including 41 excluded
ones, i.e. it ran as a **census** although the census cron is `43 9 * * *`. Most likely a
~4 h-delayed delivery of the 09:43 tick (the delivery table shows GitHub throttling hard since
08-27), but I did not confirm it — `gh run list` does not expose `github.event.schedule`.

---

## (vi) Verdict — can the box's per-land cost drop below ~200 s?

**Under the SPLIT design as briefed: no, and not by a single second.** The briefed VM half absorbs
the hermetic bats partition; the median land's bats bill is already **0 s**, and the aggregate bats
bill is **5.5 %** of land wall time. The floor arithmetic from 217 real single-round successful
local lands:

```
today                                              p50  722 s
− VM absorbs 100 % of the smoke  (briefed)         p50  722 s   Δ 0
− VM absorbs smoke + all 19 arms (not briefed)     p50  410 s   Δ −312 s
− also removes the land-lock queue + push          p50   76 s   Δ −646 s
```

**~200 s is reachable only by attacking two things the split does not name**, in this order:

1. **The 19 ratchet arms (52.0 % of land wall time, p50 312 s single-round / 549 s all-rounds).**
   They are pure repo-text scans and are box-independent — so they *could* be moved or memoized. The
   repo has already done the analysis and it points at **per-file memoization inside each lint's
   scan loop**, not at an off-box run: an arm-level key is measured-insufficient (35-46 %) and
   currently **unsound** (two lints read outside their declared pathspec). Cost: a file-locality
   proof per lint across ~15 gate scripts; 1 of 15 done (`test-hermeticity`, 46.0 s → 10.4 s + memo).
   Off-boxing them instead runs into the same key problem *plus* the tree-sha problem below.
2. **The optimistic-round re-gate (53 % of the arms bill) and the land-lock queue (`wait_s` p50
   284 s, p90 719 s).** Both are per-box concurrency, not verification. Nothing off-box reaches
   them. `SHIP_LAND_GATE_ROUNDS=0` + a raised `LAND_LOCK_WAIT` is the existing lever (already in the
   repo memory as the 3 h-livelock cure), and it comes with its own hazard — those knobs are plain
   env vars that bats subprocesses inherit, scrubbed only in worktrees cut after
   `ship-land.sh:1995`.

**What it costs to get a VM-side green trusted at all** — three prerequisites, none of which is the
partition:

| prerequisite | state today | cost |
|---|---|---|
| the producer emits a green | **0 greens in 28 days**; 2 of the 4/4 deterministic core cured but **unproven off-box**; 6 more at 3/4; the admission gap (`hermetic.yml`'s intended bill) keeps re-seeding it | ordinary agent work on the remaining reds; the `offbox-admission` arm already exists to stop new ones |
| a key that can match a pre-land tree | **impossible with tree-sha**: 0/428 overlap; producer covers 4.6-9.9 % of trunk trees/day at p50 25 min wall | switch to per-suite blob-sha (the memo shape) — the tree-sha door does not open |
| a consumer on the land path | **none**: `ship-land.sh` and `postland-verify.sh` read no off-box store; the only reader is `deploy-live.sh`'s T1H | a new consumer + a trust rule + a ratchet; and the reader must be **narrower** than T1H, because a partition green cannot acquit the direct suites it excludes |

**Cheapest genuinely-available win, if a VM half is built anyway:** aim it at
**`postland-verify.sh`**, not at `ship-land.sh`. The on-box verifier's `run_s` is **p50 2,825 s,
p90 11,273 s, max 69,363 s** over 597 stamps, with **86 greens / 597** all-time and **9 / 70** since
09-01 — an order of magnitude more wall time than any land, and it already runs the *whole* corpus
against a tree that **is** on trunk, which is exactly the tree the producer judges. That is the one
place the key actually lines up.

---

## Adversarial pass — the strongest cases against trusting a VM green

**A1 · The partition is a subset, and it is a 68/32 subset by runtime, not 94/6 by count.** A green
over 613 of 654 suites acquits **68.2 %** of the corpus's off-box runtime and is silent on the other
**31.8 %** — a lower bound, since 8 of the 41 excluded suites were recorded *at* the 300 s bound.
The excluded set is 6.8× more expensive per suite and contains `ship-land`, `postland-verify`,
`postland-verify-passfloor`, `postland-verify-bisect-bound`, `test-hermeticity-lint`,
`test-walltime-lint` — the verification machinery itself. **33 % of trunk commits with a non-empty
direct set select at least one box-bound suite** (measured over 40 commits), so a third of the lands
that would use a VM green cannot be fully covered by one. `scripts/offbox-partition.sh:44-50` states
this as doctrine: *"a subset that cannot see the machine-coupled failures has no standing to CONVICT
a tree, only to acquit the part it actually ran."*

**A2 · The brief's stated bash hazard is REFUTED for this producer, but a real OS-divergence axis
survives.** The brief supposed *"a suite green on Linux/bash 5 can be red on macOS/bash 3.2."*
Measured: the `suite` jobs run **`macos-latest`** and the tool-inventory step reports
`GNU bash, version 3.2.57(1)-release (arm64-apple-darwin25)` — **byte-identical major/minor/patch to
this box's `/bin/bash` 3.2.57 (arm64-apple-darwin24)**, with bats pinned to the on-box 1.13.0
(`hermetic.yml:148-155`). `hermetic.yml:14-21` chose macOS deliberately for exactly this reason
(*"312 are plausible on macOS against 224 on Linux… the 88-suite gap is not machine-coupling, it is
BSD userland"*). Only the `partition` and `fold` jobs are `ubuntu-latest`, and neither runs a suite.
**What does diverge:** macOS **26.6.2** on the runner vs **15.7.9** on the box (eleven major
versions), the runner installs GNU `timeout`/`gdate` through a per-job shim while deliberately
withholding GNU `sed`/`date`/`stat` (62 suites depend on the BSD spellings), and shellcheck is
**unpinned** on the runner (0.11.0 today) against whatever the box has. So the divergence is
OS-version and toolchain, not bash-version — and the 09-10 doc's own root cause is the opposite
direction from the brief's fear: the *box* was the permissive environment (brew bash 5.3 first on
PATH) and the *runner* was the strict one.

**A3 · Runner-vs-box timing does not scale linearly, so a VM's "it passed in 40 s" says little
about the box.** `hermetic.yml:107-115`, measured on run 31570936250 across six suites: short suites
run **1.25-1.67× slower** on the runner (`spawn-lineage` 5 s/3 s) while long ones are **at parity or
faster** (`cc-reaper` 117 s runner / 158 s box; `terminal-bench` 113 s / 115 s) — *"the ratio inverts
exactly where a bound is decided."* A VM green therefore cannot be read as evidence about the box's
timing-sensitive suites, which is precisely the class the box's own gate keeps re-running (the
1-of-3 exoneration ladder, `ship-land.sh:2575-2786`).

**A4 · The producer's green is a claim about a tree nobody lands.** Quantified in (iv): 0/428
overlap, 4.6-9.9 % daily tree coverage, p50 25 min run wall. This is the strongest single argument,
because it is structural rather than statistical — no amount of repair to the failing suites changes
it. A "trust the VM" design keyed on tree sha would sit at ~0 % hit rate forever and read as
working.

**A5 · The verdict channel is a silent-skip, and the aggregate hides it.** 196 of 200 runs report
`conclusion: success` while the `verdict` job — the only publisher — is `skipped` on every one I
checked. Anyone measuring the producer's health by run conclusion reads 98 % healthy over a
producer that has emitted nothing for 28 days. The design chose that vocabulary on purpose
(`hermetic.yml:425-449`: `skipped` was the only way GitHub offers to say "nothing" without emailing
the operator 22×/day), and the cost is that the *aggregate* signal is now inverted from the *member*
signal. Any consumer must read the check-run by name, as `offbox-green-pull.sh` does.

**A6 · Even a perfect, trusted, always-fresh VM green leaves the box above 200 s.** 722 − 0 = 722 s
under the briefed split; 410 s under the maximal version. The binding constraints are the arms and
the lock queue, and both are box-local by construction. Concluding "the split gets us under 200 s"
would require the arms to move — which the repo's own `gate-memo.sh` analysis rejects at the
arm-key granularity for soundness reasons, independent of where the arm runs.

---

## Blockers / uncertainties named

- **Attribution of the 334 s single-round outside-gate term is incomplete.** The land-lock join
  reaches only 92 of 423 lands (the contended subset), whose outside-gate is 2.2× the single-round
  median. Lock wait is p50 304 s = 35 % of *that* subset's outside-gate; the split of the
  single-round 334 s across queue / fetch / rebase / push / stranded-sweep is **not measured** —
  `land.log` has no field for it.
- **The 2.8× arms growth is only 2.0× accounted for** (corpus 1.6× × arm count 1.27×). The residual
  is presumably box load; `land.log` carries `loadavg` on exactly **1** of 9,852 rows, so it cannot
  be tested from the store.
- **The 09-10 fix is untested off-box.** Every claim about the *post-fix* red set in this report is
  about the pre-fix corpus; the next fold is the instrument. Two of the four 4/4 deterministic suites
  are the ones the fix cures.
- **Run 34484868431 ran as a census 4 h off its cron slot** — believed a delayed delivery, not
  confirmed (`gh run list` does not expose `github.event.schedule`).
- **`gh run download` of the two artifact sets is the only write this session made** (into
  `$S/work-D3/{shards,census}/`); the repo, plists, live `~/.claude` layer, the workflow and every
  store are untouched, and no workflow run was triggered.

### Alternatives considered and ruled out

| alternative | ruled out because |
|---|---|
| time the arm lints standalone to price them | `gate-memo.sh:366-369` measured this as **wrong by 700×** for own-scope arms (bats-shellcheck 50.5 s bare / 0.07 s through `own_run`). Priced from `land.log` instead. |
| use `*.land-cost` sidecars as the land price | 18 of 54 are `floor` markers — a lower bound on a **cut**, not an observation (`cloud-return.sh:722-753`). And they carry one total, no stage split. |
| use the `.land-refused` transcripts for the stage split | only 8 of 80 carry `→ gate:` lines and none carries timing. |
| project the land cost from §A9's 700-3,900 s | that is the **cloud/darwinbg** band (73 successful lands ever, 5 since 09-01, dominated by exit 5 / exit 143). Used the 423-row local population and reported the cloud band separately. |
| read producer health from `gh run list` conclusions | 196/200 `success` over a producer with 0 greens — the `verdict` job is `skipped`, and a skipped job leaves the run green (A5). |
| propose a tree-sha off-box stamp consumer in `ship-land.sh` | 0/428 tree overlap; structurally unreachable pre-rebase (A4). |
| propose an arm-level (lint blob + scanned set) key | already measured at 35-46 % hit and currently **unsound** — two lints read outside their declared pathspec (`gate-memo.sh:337-351`). |
