# A2 — REACH UNDER SPLIT, measured against the FLOW of real fixes (30 d)

Population pinned at `PIN=2026-09-10T05:00:00Z`; windows are the 30 / 7 **complete** days before
2026-09-10 (today excluded), exactly as `A-drain-rates.md` A6 defines them.

## HEADLINE — four numbers, each with its qualifier

| | answer |
|---|---|
| **(i) fraction of the 30-day real-fix flow implementable off-box under split** | **60.0 %** (36/60), Wilson 95 % **[47.4 %, 71.4 %]** — and **75.0 %** [61.2 %, 85.1 %] once the ledger's own re-land duplicate inflation is removed |
| **(ii) docs-only share of real fixes** | **10.4 %** by union of every cited on-main sha (67/647); 13.0 % by the first cited sha (84/647). A further **10.4 %** (67/647) cite **no resolvable sha at all** |
| **(iii) where today's classifier disagrees** | It admits **10.2 %** (66/646) of the flow against a split reach of 60 %. Disagreement is **overwhelmingly one-directional**: 35 of 60 rows are refusals that a split could have reached (**62.5 % false-negative rate over its refusals**), against 3 admits that a split could NOT reach |
| **(iv) 7 d vs 8-30 d** | **62.5 %** [42.7 %, 78.8 %] vs **58.3 %** [42.2 %, 72.9 %] — no detectable difference; the CIs overlap almost completely. The pile changed SIZE, not SHAPE, on this axis |

Sample: **n = 60**, `random.seed(20260910)`, `random.sample(sorted(f30, key=id), 60)` over the 647
30-day real-fix closures. Verdicts (a/b/c) are mine, one per row, reasons in the table.

**(c) = 0 of 60, by construction, and this is a finding about the question rather than the answer.**
The population is *closures already achieved by an agent*, so "not agent work" cannot appear in it.
`(c)` is only measurable over the OPEN pile (D-backlog-floor's 282 blocked-operator rows), never over
the closed flow. The closest case is row 37 (`b20eb0842304`) — the operator ran `git config --unset
core.bare` — and even that is agent-able: row 32's landed guard now does it automatically.

## POPULATION RECONCILIATION — the classifier reproduces exactly

`work-A2/cls3.py` is A5 verbatim; `work-A2/pop.py` re-implements A6's trail walk:

```
lines=19807 parse_fail=0 kept=19425
closures_all=3118  fix_30d=647  fix_7d=233
```

`3118 / 647 / 233` match A-drain §2 and §4 to the row. 647 closures over **646 distinct ids** —
`418628734437` closes twice inside the window (closed → reopened → closed).

## THE 60 ROWS

Columns: `files` from the diffstat of the **first cited sha that is an ancestor of `origin/main`**,
resolved across `claude-infrastructure` (this worktree), `reso-management-app`, `reso-web-app`.
`on main` = `git merge-base --is-ancestor <sha> origin/main`. `—` = no hex token in the evidence
resolved to a commit in any of the three repos.

| # | id | closed | fix sha | on main | files | cc-eligible today | split | reason |
|---|---|---|---|---|---|---|---|---|
| 1 | `0320084e8485` | 2026-08-28 | `2f01695` | yes | code | ineligible-cross-repo | **b** | closure act was a destructive purge of the live reso-web-vitals prod table (credential + operator call); the code half (2f01695) had already landed |
| 2 | `0662b7bef3ec` | 2026-08-23 | — | — | none | ineligible-offbox-lane | **a** | repo code only: provision-venue.ts + drizzle/schema.ts + migration 0089; Mac runs the migration and content-verifies |
| 3 | `19b01f376909` | 2026-08-16 | `1c34268d1` | yes | tests-only | ineligible-box | **b** | subject is a stranded refs/land/failed ref that exists only on this disk; the moving-ref control was readable only from that ref's own commit |
| 4 | `1cc794cbc6c4` | 2026-08-16 | `bfc6aa5bb` | NO | docs-only | ineligible-cross-repo | **a** | deliverable was a docs research note authored BY a cloud VM (bfc6aa5bb, content on trunk) - but it is a verdict artifact, the titled doc_classifier defect was never fixed |
| 5 | `20bba0c6cbe6` | 2026-08-11 | — | — | none | ineligible-box | **b** | the action IS launchctl kickstart of a live daemon on this box; no repo artifact at all |
| 6 | `28a2c9cf6a24` | 2026-08-17 | `e0767c41b` | yes | code | ineligible-deep-history | **a** | word-boundary fix in subshell-cleanup-lint.sh + its mutant control; hermetic (deep-history is a clone-depth knob, not a law) |
| 7 | `29637e6001f1` | 2026-09-04 | `66555d65a` | yes | mixed:tests+code | ineligible-offbox-lane | **a** | TS detectVenueAnchorDrift + 6 tests incl 3 negative controls; hermetic |
| 8 | `33d9b33bbd28` | 2026-08-25 | — | — | none | eligible | **b** | titled work is measuring THIS box's compressor segments (4 kernel panics, 26.6GB); closure evidence names an unrelated deliverable |
| 9 | `3517d2df3dcd` | 2026-08-16 | `1c34268d1` | yes | tests-only | ineligible-box | **b** | re-land family (same action as 19b01f376909) |
| 10 | `3ec6c070f52f` | 2026-08-15 | `b7f771848` | yes | code | ineligible-box | **a** | gate-arm exit-2 handling, bats SIGKILL exit code, assert-liveness fail-closed, 473-suite static scan: all reproducible in a container |
| 11 | `418628734437` | 2026-08-24 | `329fa5504` | yes | tests-only | ineligible-box | **a** | de-flaking a bats arm is a repo edit; the loadavg 11-16 re-measurement is exactly the Mac's verify half |
| 12 | `46eb9be14249` | 2026-08-11 | `223179a8` | yes | mixed:docs+tests+code | eligible | **b** | ADVERSARIAL FLIP: the landed diff ships gate-red-census.sh (430 new lines) whose 4 denominator traps were found by reading 3,272 live lines of $HOME/.claude/land.log |
| 13 | `4a7762ca46c0` | 2026-08-19 | `aa0ce5cbf` | yes | mixed:tests+code | ineligible-box | **a** | PATH-hardening at the top of assignee-pane-residency.sh + bats |
| 14 | `4c2e3349200d` | 2026-09-04 | `a3b015eff` | yes | code | ineligible-box | **a** | one JSON file (.claude/settings.json timeouts); the pnpm-guard precondition probe is hermetic (build a partial tree) |
| 15 | `4de3d0f9c0e1` | 2026-08-18 | `a40f5dca3` | yes | docs-only | ineligible-branch-banking | **a** | dod-path repo-identity keying + tests/dod-path.bats case 7 |
| 16 | `53fbb78f1b99` | 2026-08-16 | `1c34268d1` | yes | tests-only | ineligible-box | **b** | re-land family |
| 17 | `5bf8aaaf2f5c` | 2026-08-11 | `48cd2cb27` | yes | mixed:tests+code | ineligible-spawn-rail | **a** | set -e / not-sent branch in handoff-fire.sh + tests/announce-before-retire.bats; live fire is the verify half |
| 18 | `5e2b6e4e756d` | 2026-09-04 | `1d503250b` | yes | code | ineligible-cross-repo | **a** | wire verify-live-headers.sh into deploy-release.sh; the live header read is the Mac's verify half |
| 19 | `5eab9757624c` | 2026-09-07 | `9880d6fb3` | yes | mixed:tests+code | ineligible-cross-repo | **a** | replicache store-warm code + tests; the dev-rig RSC probe is the verify half |
| 20 | `5fc734347de1` | 2026-09-07 | `14c11b2ec` | yes | mixed:tests+code | ineligible-cross-repo | **b** | deliverable was a LAND REFUSAL decision resting on live main state (TLS/reachability, fly-dfw, insomniacdenver) plus a design:gate render |
| 21 | `65818e38e36b` | 2026-09-06 | `3752083` | yes | code | ineligible-offbox-lane | **b** | cause proved by luminance measurement over 490 captured view-transition frames from a live browser; the CSS edit is steered by that loop |
| 22 | `69e7491d1b54` | 2026-09-05 | `4cf73bb95` | yes | code | ineligible-cross-repo | **a** | an oxlint timing rig + its numbers; a quiet VM is a BETTER host than a saturated Mac for an interleaved A/B |
| 23 | `6a82c9405b9e` | 2026-08-23 | `492c51066` | yes | code | ineligible-box | **a** | unguarded out=$(...) under errexit; the concurrency that exposes it is reproducible in a container |
| 24 | `6ab41e312a13` | 2026-08-12 | `410f920c9` | NO | mixed:docs+tests+code | ineligible-branch-banking | **b** | source material is local-only: commit 410f920c on local branch fix/sigterm-forensics (git branch -a --contains shows no remote) + an untracked ~/.reso/bin/reso-keepalive |
| 25 | `6cb991f4d1f9` | 2026-09-06 | `e26861b79` | yes | code | ineligible-box | **a** | hf_occupancy_gate is shell code against a documented contract; the live fire that proves it is the Mac's half |
| 26 | `6d7ba2fc40a1` | 2026-08-18 | `8ae61e12e81a49e7fa17f476eefaa0b874e3ecb7` | yes | mixed:tests+code | ineligible-offbox-lane | **a** | fold predicate + bats fixture; running the fold over the real ledger is the Mac's verify half |
| 27 | `7176bda11a8d` | 2026-08-12 | — | — | none | ineligible-branch-banking | **a** | one path-resolution fix in handoff-fire.sh; the 835-transcript census is the Mac's half |
| 28 | `73f93732fbdf` | 2026-08-16 | `40d574617` | yes | mixed:docs+code | ineligible-box | **b** | re-land of a local stranded branch (fix/usage-telemetry-100p) |
| 29 | `8418890640cd` | 2026-08-23 | `081fa5502` | yes | code | ineligible-visual | **b** | chevron alignment measured off rendered pixels (2.71px) in a local browser |
| 30 | `8740c03e428c` | 2026-08-23 | `9dfc6c4c7` | yes | mixed:tests+code | ineligible-branch-banking | **a** | postland-verify red_actions per-entry bisect fix + red-proof; hermetic |
| 31 | `87fb953804dc` | 2026-08-16 | `ff96d9289` | yes | mixed:tests+code | ineligible-box | **b** | re-land family (the 38-duplicate one) |
| 32 | `8cb412119579` | 2026-09-09 | `e99dcdf82` | yes | mixed:tests+code | ineligible-box | **a** | the core.bare guard is repo code; a fixture repo with core.bare=true is hermetic |
| 33 | `957301ae6045` | 2026-09-08 | — | — | none | ineligible-box | **b** | re-land, closed by land-content-verify against a local refs/land/failed ref |
| 34 | `9579a3e8acb3` | 2026-08-23 | `792b37b726564dd7490772e4f0024bc9f92135fc` | yes | mixed:docs+tests+code | ineligible-cross-repo | **a** | shared deploy-ref.ts reader + re-keyed commits query + RED-proved discriminating tests |
| 35 | `9bc82b51843e` | 2026-08-11 | `af66a60b` | yes | mixed:tests+code | ineligible-visual | **a** | hooks/boundary-handoff.sh + bats; the "banner" is README text, not a rendered surface |
| 36 | `a617f53461ef` | 2026-09-08 | `b5f8fc683` | yes | code | ineligible-box | **b** | re-land of a local worktree branch (wt-b0ee53b5f737) |
| 37 | `b20eb0842304` | 2026-09-06 | `8a40cd3fa667` | yes | docs-only | ineligible-box | **b** | the repair was git config --unset core.bare on the shared checkout, executed on this box |
| 38 | `b384effb4100` | 2026-09-05 | `17cfa8ae6` | yes | mixed:tests+code | ineligible-box | **a** | CI workflow + check script + pre-commit delegation + tests; entirely in-repo |
| 39 | `b54edfb6da6e` | 2026-09-06 | `966c092f0` | yes | mixed:tests+code | ineligible-visual | **a** | smoke budget derived from direct-suite count; repo code + 4 suites |
| 40 | `bb2495b098b8` | 2026-08-19 | `e1b0bb804` | yes | mixed:docs+tests+code | ineligible-box | **a** | live-only manifest + parity script + tests; running it against ~/.claude is the Mac's half |
| 41 | `bf6c9db48120` | 2026-09-08 | `a48e9024d` | yes | tests-only | ineligible-box | **a** | the guard now inspects the settings.json the dir LOADS; red-proof is a fixture plus git show of the pre-fix artifact |
| 42 | `c0005ffd63d8` | 2026-09-07 | `b4ace833b468b30d21376fb4d6256cf25982be7e` | yes | tests-only | ineligible-spawn-rail | **a** | one bats setup() pin (CC_FIRE_OCCUPANCY=off) |
| 43 | `c53417008eb3` | 2026-08-16 | `1c34268d1` | yes | tests-only | ineligible-box | **b** | re-land family |
| 44 | `c673e7f2b1af` | 2026-09-04 | — | — | none | ineligible-box | **b** | re-land verify against a local ref |
| 45 | `cc89fc8dc765` | 2026-08-11 | `d86418b0` | yes | mixed:docs+tests+code | eligible | **a** | postland pre-plan grace for bats' no-TAP counting pass; bats behaviour is reproducible in a container |
| 46 | `ce5e5310c457` | 2026-09-08 | `f3402d860` | yes | code | ineligible-box | **a** | the artifact is migrations/0022-mitl-decider-shadow.sh (staged class c10, arming stays operator-owned); writing it is repo work |
| 47 | `d159cd41db3d` | 2026-09-08 | `0e1569952` | yes | mixed:docs+tests+code | ineligible-spawn-rail | **b** | the defect is Claude Code's TUI paste placeholder observed in two live fires; no VM has a TUI |
| 48 | `d4fa449e3895` | 2026-08-20 | `ebc0f525` | yes | mixed:tests+code | ineligible-box | **a** | assignee-pane-residency code + bats |
| 49 | `d8c4d1831191` | 2026-09-08 | `b152965b3` | yes | mixed:docs+tests+code | ineligible-box | **b** | re-land |
| 50 | `dc014c6829ac` | 2026-08-18 | `017650872` | yes | mixed:tests+code | ineligible-offbox-lane | **a** | idempotency-key / --project plumbing in desk-land.sh + ship-land.sh + both suites |
| 51 | `e020ebb2b8c7` | 2026-08-16 | `041aaf280` | NO | docs-only | eligible | **b** | diagnosing a crash-looping macOS process (spindump chrome_crashpad_handler) on this Mac; the off-box closure was a docs verdict artifact |
| 52 | `e1c603144edc` | 2026-08-22 | `2f45c78e9` | yes | docs-only | ineligible-branch-banking | **a** | bisect_tip_differential_ok in postland-verify; hermetic (the cited sha 2f45c78e9 is the plan-doc commit, the code landed elsewhere) |
| 53 | `e3a4f4ec6ab9` | 2026-09-06 | `efb142c3b` | yes | mixed:docs+tests+code | ineligible-cross-repo | **a** | credential-transports parse + echo at login + 6 unit tests |
| 54 | `e9c6fd367cde` | 2026-09-08 | `fc34d900d` | yes | code | ineligible-spawn-rail | **a** | the landed lint's annotations are re-derivable by running it against trunk (cited sha fc34d900d touches cc-husk-sweep/handoff-fire.sh, not the titled lint - citation mismatch) |
| 55 | `eff2dcf5a460` | 2026-08-16 | `ff96d9289` | yes | mixed:tests+code | ineligible-box | **b** | re-land family |
| 56 | `f5511dfb87b5` | 2026-09-04 | `613506f06` | yes | code | ineligible-offbox-lane | **a** | delete one dead VENUE_BY_SUBDOMAIN entry + a comment; premise re-verifiable from the repo |
| 57 | `f6ac0fc91e2b` | 2026-09-05 | `09e5c6824` | yes | mixed:tests+code | ineligible-visual | **b** | VRT snapshot drift 187/205px; pixel baselines are a property of the local rendering rig |
| 58 | `ff0b5cf4528b` | 2026-08-14 | `a346b6993` | yes | mixed:tests+code | ineligible-branch-banking | **a** | lr-reset-poller per-sid failure latch + 2 suites |
| 59 | `ff3f38d6eeed` | 2026-08-17 | `d862e80af` | yes | mixed:docs+tests+code | ineligible-box | **a** | lint discriminator moved from command word to ARGUMENT; hermetic |
| 60 | `ff404a5304a8` | 2026-08-16 | `1c34268d1` | yes | tests-only | ineligible-box | **b** | re-land family |

## STATISTICS

### Reach and admit

```
split-reachable (a)            36/60 = 60.0%  [47.4%, 71.4%]
classifier admits, sample       4/60 =  6.7%  [ 2.6%, 15.9%]
classifier admits, FULL 647    66/646 = 10.2% [ 8.1%, 12.8%]
```

The sample's 6.7 % and the population's 10.2 % are consistent (overlapping CIs). The population
figure is the one to quote: it is a census, not a sample. Note it is **higher** than the 6.5 %
`cc-eligible sweep` reports over the OPEN pile — the flow of things that actually get fixed is
slightly more admissible than the pile that does not move.

### 2×2 — classifier admit vs split-reachable (n = 60)

|                 | split = a | split = b | total |
|---|---:|---:|---:|
| **admit = eligible** | 1 | 3 | 4 |
| **admit = refused**  | 35 | 21 | 56 |
| **total** | 36 | 24 | 60 |

- agreement **36.7 %**
- **admit precision 1/4** — three of the four items the classifier would have sent to a VM are
  items a VM cannot do (`33d9b33bbd28`, `46eb9be14249`, `e020ebb2b8c7`). n=4, so treat this as a
  flag, not a rate: Wilson on 1/4 is [4.6 %, 64.1 %].
- **refusal false-negative rate 35/56 = 62.5 %** — this is the load-bearing number. The classifier's
  own header says it can convict and cannot acquit; measured against a split design it *also*
  convicts wrongly, five times in eight.

### Refusal classes over the FULL 647 (census, `bin/cc-eligible why <id> --json`)

| verdict | n | share |
|---|---:|---:|
| `ineligible-box` | 350 | 54.2 % |
| **`eligible`** | **66** | **10.2 %** |
| `ineligible-cross-repo` | 57 | 8.8 % |
| `ineligible-branch-banking` | 47 | 7.3 % |
| `ineligible-offbox-lane` | 43 | 6.7 % |
| `ineligible-spawn-rail` | 26 | 4.0 % |
| `ineligible-deep-history` | 25 | 3.9 % |
| `ineligible-visual` | 23 | 3.6 % |
| `ineligible-parked` | 6 | 0.9 % |
| `ineligible-external-deploy` | 2 | 0.3 % |
| `ineligible-github` | 1 | 0.2 % |

`ineligible-box` at 54.2 % is where the split's whole value sits, and the sample says most of it is
**verify-coupled, not implement-coupled**: 20 of the 27 `ineligible-box` rows in the sample are (a).

### Docs-only share of real fixes (census over 647)

| basis | docs-only | no resolvable sha |
|---|---:|---:|
| first cited on-main sha | 84 (13.0 %) | 67 (10.4 %) |
| **union of every cited on-main sha** | **67 (10.4 %)** | 67 (10.4 %) |
| 7 d window (union) | 24/233 (10.3 %) | 34/233 (14.6 %) |
| 8-30 d window (union) | 43/414 (10.4 %) | 33/414 (8.0 %) |

Stable across windows. So ~1 in 10 "real fixes" is a documentation verdict artifact that lands
trivially, and another ~1 in 10 has no traceable commit at all — combined **~21 %** of the flow is
not a code landing.

### Split reach under the two repo-provisioning regimes

| regime | reachable |
|---|---|
| VM is given the item's own repo | 36/60 = 60.0 % [47.4 %, 71.4 %] |
| **VM is given ONLY `claude-infrastructure`** (today's `cc-cloud`) | **27/60 = 45.0 %** [33.1 %, 57.5 %] |

Repo provisioning is worth **15 pp** of reach and is a `cc-cloud` configuration, not a law.
`docs/research/cloud-vm-reachability-2026-08-23.md` measures the VM's filesystem from inside: one
shallow clone, `ls ..` returns a single entry, `~/Development` does not exist.

**And `cc-eligible`'s `cross-repo` class is partly an artifact of the wrong field.** It keys on the
ledger's `project`, which is derived from the FILING session's cwd. Of the 24 sample rows whose
`project` is not `claude-infrastructure`, **8 landed their fix IN `claude-infrastructure`** — e.g.
`6cb991f4d1f9` (project `reso-management-app`, fix `e26861b79` = `scripts/limit-recover/*`) and
`1cc794cbc6c4` (project `doc_classifier`, fix `bfc6aa5bb` = a `docs/research/` note here). One third
of the cross-repo refusals are mis-addressed rather than out of reach.

## THE DENOMINATOR IS CONTAMINATED, AND BY THE LANDING ARM ITSELF

**110 of 647 (17.0 %) 30-day "real fixes" are `re-land <branch>: ship-land …` rows, and they
resolve to only 36 distinct landing shas.** Three title families alone account for 58 rows:

| rows | family |
|---:|---|
| 38 | `re-land claude/fire-20260812T172113Z-3600-1: ship-land exited 143 (SIGTERM) …` |
| 12 | `re-land claude/fire-20260813T214112Z-31568-1: …` |
| 8 | `re-land claude/fire-20260813T004918Z-40705-1: …` |

Only 6 title-families in the whole 647 have >1 row, and 5 of the 6 are re-lands — 65 rows in
duplicate families. The cause is a fix that is itself IN this sample: row 50 (`dc014c6829ac`,
landed `017650872`) — *"the failure row's identity carried the attempt's sandbox, so every retry
minted a sibling"*: `desk-land.sh` filed from an ephemeral `/private/tmp/.desk-land-<branch>-<PID>`
worktree, so `sha256(project.title.source)` differed on every attempt.

Three consequences, all load-bearing for the lane decision:

1. **12 of my 60 sample rows (20 %) are re-land rows and 0 of 12 are (a)** — the stranded
   `refs/land/failed/<ts>-<branch>` ref exists only on this disk. They are pure (b) by construction.
2. **The correct denominator for "work a VM could take" is ~573, not 647** (647 − 110 + 36 distinct
   actions), an 11.4 % inflation. Reach excluding re-land rows is **75.0 %** [61.2 %, 85.1 %].
3. **Under a split design these rows would largely not exist**, because landing is the Mac's half by
   definition. 17 % of the flow this lane is measured against is an artifact of the arm the split
   removes. Sample distribution supports this being a live-and-recent effect, not history: 4/24 in
   the 7 d window, 8/36 in 8-30 d.

## WHERE THE CLASSIFIER IS WRONG, AND WHY — the five recurring spelling failures

Each of these is a refusal keyed on a WORD whose second meaning the corpus actually uses:

| row | refusal | token | what the word actually meant |
|---|---|---|---|
| `f5511dfb87b5` | `ineligible-offbox-lane` | `venue` | a reso *nightclub venue* (`VENUE_BY_SUBDOMAIN`), not the cloud/local venue field |
| `6d7ba2fc40a1` | `ineligible-offbox-lane` | `venue` | a `cc-backlog` *record field name* appearing in the fold's own trail |
| `b384effb4100` | `ineligible-box` | `hook` | a git `pre-commit` hook inside the repo, not a Claude Code hook |
| `9bc82b51843e` | `ineligible-visual` | `banner` | a README *text* banner |
| `b54edfb6da6e` | `ineligible-visual` | `render` | prose in the item's own body; the diff is `ship-land.sh` + 4 bats suites |

And the two structurally mis-scoped classes:

- **`ineligible-spawn-rail` (4.0 % of flow) is the split's definition, not its obstacle.** Its stated
  reason — *"verified only by a live fire on this box"* — names VERIFICATION. All four sample rows
  (`5bf8aaaf2f5c`, `c0005ffd63d8`, `d159cd41db3d`, `e9c6fd367cde`) are repo edits; three are (a).
  The one genuine (b) is `d159cd41db3d`, whose defect is Claude Code's `[Pasted text #1]` TUI paste
  placeholder observed in two live fires — no VM has a TUI.
- **`ineligible-deep-history` (3.9 %) is a clone-depth knob.** The VM clones shallow at depth 50
  (`git rev-list --count HEAD` → 50, reachability doc). `28a2c9cf6a24` is refused for citing three
  shas outside that window; `--depth 500` dissolves the class.

The three admits that are NOT reachable are the more dangerous direction, because a wrong admit puts
a worker in a VM that cannot do the work and cannot say so:

- `33d9b33bbd28` — *"per-unit compressor-SEGMENT cost is unmeasured for all 7 orchestration units"*
  (26.6 GB, 4 kernel panics). Requires measuring THIS box. Its closure evidence names an entirely
  unrelated deliverable (`scripts/branch-prune-landed.sh`) — a discharge that does not measure its
  own subject.
- `e020ebb2b8c7` — spindump a crash-looping macOS `chrome_crashpad_handler`. Closed off-box by
  `041aaf280`, a `docs/research/cursor-crashpad-2026-08-15.md` note concluding *"the signature was on
  trunk all along — spindump is the wrong instrument"*. A verdict artifact, not the titled fix.
- `46eb9be14249` — flipped by my adversarial pass; see below.

## ADVERSARIAL SELF-PASS — 10 (a) rows re-read as "what live state did the fixer READ?"

One flip, five downgrades, and one instrument correction.

**FLIP: `46eb9be14249` a → b.** Its landed sha `223179a8` ships `scripts/gate-red-census.sh`
(430 new lines) + `tests/gate-red-census.bats` (313). The file's own header states that its four
denominator traps were found by reading the live store — *"All four were measured on the live store
2026-08-11 (3272 lines, 1636 invocations)"*, including *"TWO RECORD TYPES SHARE ONE STORE, AND THE
DISCRIMINATOR YOU REACH FOR FIRST IS WRONG"*. A VM has no `$HOME/.claude/land.log`, would not have
met the trap, and would have shipped a census that reads ~2.8 % of its own denominator. The bats
fixture that makes the suite hermetic was written FROM the live store — so hermetic-after-the-fact is
not hermetic-to-author. All numbers in this report are post-flip.

**DOWNGRADE — `a-unproven`: 5 of the 36 (a) rows land a change whose ONLY proving suite is on this
repo's own off-box-excluded manifest**, and has no hermetic sibling in the same diff:
`3ec6c070f52f` (`tests/ship-land.bats`, `tests/test-hermeticity-lint.bats`), `418628734437` +
`ff3f38d6eeed` (`tests/pipefail-sigpipe-lint.bats`), `8740c03e428c` + `cc89fc8dc765`
(`tests/postland-verify.bats`). These stay (a) — implementable off-box — but the VM cannot go green
on them, so the Mac inherits the whole test loop rather than a verification. Reach that is *both*
off-box-implementable *and* off-box-self-provable is at most **31/60 = 51.7 %**.

**INSTRUMENT CORRECTION.** My first sha extraction excluded all-decimal tokens as "not a sha". Two
real landing shas are all digits — `3752083` (row 21) and `017650872` (row 50) — and one of them
flipped row 50's file class from `docs-only` to `mixed:tests+code`, i.e. the exclusion manufactured a
docs-only artifact out of a 238-line code+test fix. Five of 60 rows changed class under the
permissive regex. Every figure here uses `\b[0-9a-f]{7,40}\b` with no decimal exclusion.

**HINDSIGHT-BIAS CHECK.** My (a) verdicts read the title AND the landed diff; a VM gets the title and
the repo. This corpus files diagnosis-bearing titles — (a) rows' titles have a **median of 414
characters** (min 59). But **6 of 36 (a) rows have titles under 120 chars**, where a VM would get
almost nothing: `1cc794cbc6c4`, `7176bda11a8d`, `9bc82b51843e`, `ce5e5310c457`, `d4fa449e3895`,
`e9c6fd367cde`. Two of those are `advance <plan>` pointers whose scope lives in a plan doc in the
repo, so they survive; the other four are (a) only under the assumption that the VM re-derives the
diagnosis. If all 6 are conceded, reach falls to 30/60 = 50.0 % [37.6 %, 62.4 %].

**COUNTER-CHECK on one (a) I expected to lose.** `7176bda11a8d` (`recycle_engaged` resolved
`$pdir/$sid.jsonl` flat where CC nests one level down) rests on a census of 835 local transcripts —
apparently box-only. But the SIBLING arm in the same function already uses `find "$pdir" -name
'*.jsonl'` (`scripts/handoff-fire.sh` origin/main :2950, :2981) while the broken arm used a flat
path. The inconsistency is visible in-repo without any transcript. Verdict held at (a).

**WHAT A VM ACTUALLY DELIVERS — the measurement I had not planned, and it cuts against the split.**
Splitting the 647 by claim venue (`v_any`, A6's reset-on-claim rule):

| venue | n | docs-only | no resolvable sha | both together |
|---|---:|---:|---:|---:|
| cloud | 62 | 13 (21 %) | 17 (27 %) | **30 (48 %)** |
| local | 163 | 12 (7 %) | 9 (6 %) | **21 (13 %)** |
| unattributed | 422 | — | — | — |

**A cloud-claimed "real fix" is ~3.7× more likely than a local one to be a docs artifact or to have
no traceable commit at all.** That is the empirical signature of a worker that cannot reach the work
and writes a research note instead — and rows 04 and 51 of my sample are two named instances, both
of which the v3 classifier scores `fix` because the evidence says "LANDED" and carries a sha.
Qualifier that keeps this honest: A-drain §3 establishes that every cloud `claim` is a
`role:"dispatcher"` placeholder lease, so "cloud" here means *an item a cloud dispatcher claimed*,
not *a VM did the work*; and n=62 against 422 unattributed. Do not read it as a quality verdict —
read it as the failure mode a split design must defend against, because a VM that cannot verify has
a strictly cheaper way to satisfy the ledger than fixing anything.

## THE HERMETICITY QUESTION, ANSWERED BY A SHIPPED INSTRUMENT RATHER THAN BY ME

My (a) verdicts assume "runs hermetic tests" is achievable. The repo already answers this and I did
not need to reason about it:

```
tests/*.bats on origin/main            654
scripts/host-suites.manifest             3   (assert the DEPLOYED layer)
scripts/offbox-excluded.manifest        38   (machine-coupled; must EARN the exemption with a reason)
partition = 654 − 3 − 38 =             613   = 93.7 % of the corpus
```

`scripts/offbox-partition.sh` computes it as a **set difference** so it is total by construction, and
`.github/workflows/hermetic.yml` runs that partition sharded, hourly-ish, today.

**Two caveats that bound the claim, both real:**

1. **The hermetic runner is `macos-latest`, not Linux.** `hermetic.yml:133` pins the shard job to
   macOS deliberately (bats 1.13.0 pinned "so the verdict must be comparable with the on-box
   verifier's"); only the `partition` job runs on `ubuntu-latest`, and it only lints the partition.
   The cloud VM is Linux (`/home/user/claude-infrastructure`, `HOME=/root`). So 93.7 % is measured
   for *another macOS machine*, and is an **upper bound** for a Linux VM.
2. **The delivered fold rate is 7.32/day, not the 24 the cron line requests**
   (`docs/research/offbox-green-floor-refutation-2026-09-08.md`, 58 scheduled runs measured
   2026-08-31 → 2026-09-08, median gap 3.28 h). Any split-lane throughput projection denominated in
   the cron line is ~3× too optimistic.

## ALTERNATIVES CONSIDERED AND RULED OUT

- **Sampling the OPEN pile instead of the closed flow** — rejected by the brief's premise and it is
  right: the pile is 282/352 blocked-operator rows, so its reach says nothing about what a lane could
  have *delivered*.
- **Using `bin/cc-eligible explain`** — unnecessary. `why <id> --json` works on `done` ids (verified
  on all 647); no refusal to fall back from.
- **Judging file class from the union of all cited shas as primary** — reported both. The union is
  the more honest docs-only estimate (10.4 % vs 13.0 %) because evidence routinely cites a plan-doc
  commit alongside the code one (`e1c603144edc` cites 4 shas; its primary `2f45c78e9` is a 104-line
  `docs/plans/BACKLOG_DRAIN_24_7.md` commit while the code landed elsewhere).
- **Running the bats corpus myself to test hermeticity** — rejected: `cc-bats` refuses at 2
  concurrent roots and a long run would hold a gate slot against a sibling's land, and
  `offbox-partition.sh` + `hermetic.yml` already answer the question with a shipped instrument.
- **Weighting rows by effort/size** — not attempted; the ledger has no effort field and diffstat
  lines are a poor proxy across three repos with different conventions.

## BLOCKERS AND UNCERTAINTIES, NAMED

1. **Clustering breaks the CI's independence assumption.** 12 of 60 sample rows are re-land rows
   collapsing to ~6 distinct actions, so the effective n for the headline is ~54, not 60, and the
   true 95 % interval is slightly wider than [47.4 %, 71.4 %]. The re-land-excluded figure (75.0 %,
   n=48) is the cleaner estimate of reach over distinct work.
2. **My a/b verdicts are one reader's, unaudited.** A-drain measured its own text classifier against
   a hand audit (38/40); this report has no second reader. The 2×2's admit cell is n=4.
3. **`ineligible-box` is 54.2 % of the flow and I sampled only 27 of 350.** The sample says 20/27 are
   (a), which is the single biggest driver of the 60 %. A dedicated stratified pass over that class
   would tighten the headline more than anything else here.
4. **Linux-vs-macOS hermeticity is unmeasured.** 93.7 % is a macOS-runner figure. Nothing in the repo
   has ever run the partition on Linux, so the split's "VM runs hermetic tests" half has no
   Linux-side evidence at all.
5. **Round-trip latency is unmeasured.** Every (a) verdict assumes the Mac's verify half is cheap. It
   is *automatable* for the 30 of 36 (a) rows whose evidence is a content-verification against
   `origin/main` — but a bounce-back cycle (VM implements → Mac verifies red → VM re-implements) is
   not in any store, so the split's real throughput is unknown.
6. **`cc-eligible`'s `project` field is the wrong join key** for the cross-repo class (8 of 24
   non-`claude-infrastructure` rows landed in `claude-infrastructure`), so the 8.8 % cross-repo share
   is an over-count of true out-of-reach by roughly a third.

## REPRODUCTION

All intermediates under
`/private/tmp/claude-501/-Users-chrisren-Development--worktrees-cloud-lane-research/dc4eb0fa-3191-4b17-acc3-c3a1e6050e33/scratchpad/work-A2/`:

| file | what |
|---|---|
| `cls3.py` | A5 verbatim |
| `pop.py` | A6 trail walk + the seeded sample (`seed 20260910`, `n=60`) → `fix30.json`, `sample60.json` |
| `files2.py` output `files2.json` | per-row sha resolution + file class (permissive hex regex) |
| `fullpop2.py` → `fullpop2.json` | the same over all 647 |
| `elig_all.py` → `elig_all.json` | `bin/cc-eligible why <id> --json` census over all 647 |
| `verdicts.tsv` | the 60 split verdicts + reasons (note: `46eb9be14249` is `a` here and flipped to `b` in the stats, per the adversarial pass) |
| `final_stats.txt` | every number in this report |
| `excl.txt` | `offbox-excluded.manifest` + `host-suites.manifest` on origin/main |

Read-only throughout: no ledger write, no cloud declaration touched, no `claim`/`done`/`block`, no
`cc-cloud poll|retire|declare|gc`, no fire, no land.
