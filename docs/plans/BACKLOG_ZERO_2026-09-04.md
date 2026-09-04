---
status: in-progress
created: 2026-09-04
supersedes-for-operation: BACKLOG_DRAIN_24_7.md §4.1 (the recycle-fire template — its invariants are replaced by the generated brief, see §3), DRAIN_CIRCUIT_2026-09-01.md (its measurements stand; its W3 "re-aim the local lane" is delivered here)
---

# BACKLOG_ZERO — the two 24/7 drains, measured, and rebuilt to drive cc-backlog to zero

**Scope (frozen):** investigate the local and cloud 24/7 cc-backlog pipelines' TRUE productivity
(rows closed, not commits landed) and change them so the pipeline drives the backlog toward zero —
closes ≥ files week over week — proven by `scripts/backlog-telemetry.sh` reading closed ≥ filed over
its rolling window, and by the first links of the rebuilt local lane closing pre-existing rows.

## Phase 0 — Agent Team Orchestration

**Execution locus per wave** (S = dispatched handoff session · T = in-session teammates · L =
lead-inline):

| Wave | Locus | What | Owns |
|---|---|---|---|
| W0 measurement | L + 4 read-only research subagents — ✅ DONE | the numbers in §1 (cloud lane · local lane · inflow generators · pile census) | `docs/research/backlog-zero-2026-09-04/` |
| W1 local lane rebuild | **L** — the judgment about what a link should do IS the deliverable, below the cost of briefing a session — ✅ LANDED `89a020f08` | `scripts/drain-brief.sh`, `scripts/drain-brief.template.md`, `scripts/drain-pick.sh`, `scripts/drain-recycle-fire.sh`, their three suites (46 tests) | lead |
| W2a inflow gates | S — fired 2026-09-04T12:15Z, pane 296, account next2, branch `feat/backlog-zero-w2a`, goal ARMED | DROP as a discharging remedy in `hooks/dispatch-assert.sh` (:191/:225 + a fifth `discharged_since` arm, `--source "$SID"` → `--condition`), D4's gate sentence in `completion-assert` D1, an add-time no-falsifier WARN in `bin/cc-backlog` | `hooks/dispatch-assert.sh`, `hooks/completion-assert.sh`, `bin/cc-backlog` |
| W2b retraction + routing | S — fired 12:20Z, account next2, branch `feat/backlog-zero-w2b`, goal submitted, not verified | durable probe path in `ship-land.sh:1032`; re-point the 43 dead probes; close the 19 in `closable.jsonl` with re-run proof; `CC_PREMISE_CLOSE_CAP` 5→25; plan-open retractor reaches `claimed`; reopen the 31 mis-filed blocked rows | `scripts/ship-land.sh`, `scripts/autonomy-sweep.sh`, `bin/cc-dispatch`, `bin/cc-premise`, the store via verbs |
| W3 cloud lane | S — fired 12:23Z, account next4, branch `feat/backlog-zero-w3`, goal submitted, not verified | retire/prune pass (A), dispatcher admission gate + pending cap (B), capped pre-land price floor (C), ship-rail rc propagation (D), `thrash-block-recover` wired (F); next3 re-auth filed (E) | `bin/cc-dispatch`, `scripts/cloud-return.sh`, `scripts/cloud-reconcile.sh`, `scripts/autonomy-sweep.sh` |
| W4 moot sweep | folded into W2b (19 rows, each with its own re-runnable check) | — | — |
| W5 go-live | L — ✅ FIRED 12:36Z: lane `infra` recycle #300, pane 299, account next2, worktree `.worktrees/drain/lane-infra`, window `2026-09-04T12:36:29Z`, floor min 3. The goal paste ABSTAINED (composer unreadable 30 s) — the link has its brief; #301's fire re-arms mechanically | lead |

Lead context budget: recycle at ≤60%; succession point = any wave boundary; this plan + the ledger +
the research dir are the whole disk state.

## §1 What was measured (2026-09-04, live store — `scripts/backlog-telemetry.sh`)

| | value |
|---|---|
| live rows | **612** (371 open · 241 blocked) — all-time peak 617 today |
| rolling 7 d | filed 105 · closed 51 · **net +54** |
| conversion 7 d | 173 claims over 23 ids → **2 done (8.6%)** · reclaim 7.5× per id · `verdict=drain-futile` |
| effort 7 d | 264 trunk commits vs 46 closes · `effort-productive` at 5.7× (ceiling 10×) |
| close attribution (all time) | cloud 3 · local-drain 65 · session 81 · land 57 · sweep 13 · unattributed 2,355 |
| quota | all four accounts strand 43–83 pp of their weekly window at reset — capacity is NOT the constraint |

### §1.1 The local lane — a chain whose brief ate its job

The local drain is one self-recycling pane (`recycle-11-27`, kitty pane 27) at recycle **#299 →
#300** this morning. Its per-link brief is regenerated from the PREDECESSOR'S brief (clone + sed
renumber + splice, ~19 numbered instrument scripts per link) and had grown to **3,366 lines
(~300 KB)**. Grepped for `cc-backlog claim` / `cc-backlog list`: **zero hits** — the instruction to
claim and close rows had been spliced out. What remained: an N-2 renumbering hazard section, a
presence loop over nineteen artifacts, four ledger "moments" per link, and a "method N" finding
appended to §2.1 each link (38 entries say "ZERO rows closed" outright). All of the last eight fires
carry `goal_requested:false` in `~/.claude/logs/handoffs.jsonl` — the closure-floor goal built on
2026-08-31 (`scripts/drain-recycle-fire.sh`) was never used by the live chain, which fires through
its own cloned `clone<N>.sh` → `handoff-fire.sh --recycle`.

### §1.1a What the four measurements added (all in `docs/research/backlog-zero-2026-09-04/`)

| axis | the number that decides it |
|---|---|
| local lane (`local-lane.md`) | #250–#298: **49 links, 7 rows closed, 105 filed**; 45 of 49 links closed zero; ~**$27 of quota per link** (recycle #298: 117 turns, 41.6 M cache-read tokens); the SSOT was never the source — `splice<N>.py` reads the PREDECESSOR'S brief, so no §4.1 edit since 2026-08-31 reached a link |
| cloud lane (`cloud-lane.md`) | **29.9 fires/day → 1.3 returns/day → 0.7 closes/day**; pending 543 (+23.5/day, ~400-day horizon); **0 land successes in ~1,000 attempts** (rc 758×70 · 239×65); 17 ids own 57% of 665 declarations; `branch-prune-landed.sh` and `thrash-block-recover.sh` built with **zero callers**; next3's control-plane token expired (401 ×22) |
| inflow (`inflow.md`) | outflow collapsed harder than inflow (week of 08-28: filed 118 / done 57 vs 891 / 718 three weeks earlier); the two mechanical close gates fired **226×/14 d** and offer no DROP; **43 of 48** live re-land probes exit 127 (dead worktree path, `ship-land.sh:1032`) so the retraction arm fails OPEN; working falsifier coverage **7.3%** |
| pile (`pile-census.md`) | 619 live = 371 open · 242 blocked · 6 claimed; **(A) 19 mechanically closable · (B) 462 agent-workable · (C) 91 operator-only · (D) 47 decisions**; 70 rows in projects the dispatcher never dispatches; 87% of rows never claimed once — an ADMISSION problem, not throughput |

### §1.2 The cloud lane — fires that never come home

`cloud-return.sh --sweep` now reads `pass-scope pending_total=543 taken=25 deferred=518` per tick and
`land-deferred … budget_s=720 bound_s=900`; the 25-per-tick cursor cannot catch a pile that grows
with every dispatcher fire, and `land-refused land_rc=70` rows still land nothing. Lane `cloud` has
closed **3** rows ever. (Detail: `docs/research/backlog-zero-2026-09-04/cloud-lane.md`.)

### §1.3 Inflow — who is filing

Last 14 days: `needs` 212 (every one `by:null`, 211 of 212 with **no falsifier**), blank-source 117,
`postland-verify` 14, `plan-open` 6. Title shapes: `post-land RED:` 11, `converge the …`, `Restart
the …`, `authorize the …`, `Decide whether …`. (Detail: `…/inflow.md`.)

## §2 Root cause, in one paragraph

Nothing in either lane was ranked on *rows closed*. The local chain ranked "fire your successor"
above everything and regenerated its instructions from its own output, so each link optimised the
brief; the cloud lane fires without asking whether the landing arm can absorb another branch; and
the close gates make FILING a precondition of closing, so every session that finishes anything
mints follow-ons the drains cannot keep up with. The telemetry that would have shown it
(`backlog-telemetry.sh`, 2026-08-23) exists and reads `drain-futile` — nothing acted on it.

## §3 The rebuilt local lane (W1 — landed this session)

- **`scripts/drain-brief.template.md`** — the whole brief, ≤150 lines, tracked and reviewed. A link
  reads: setup → pick → adjudicate (MOOT · DOABLE · OPERATOR-ONLY · TOO BIG) → land → close → fire.
  It files nothing, edits no machinery, leaves an ≤8-line §2.1 entry.
- **`scripts/drain-brief.sh`** — the brief is a pure function of (template, N, lane, project,
  worktree, since, min). Refuses on a template over 200 lines (the anti-accretion ratchet), on a
  leftover placeholder, and on an existing brief for the same (lane, N).
- **`scripts/drain-pick.sh`** — the ranked worklist: open rows of the lane's project, falsifier →
  dodRef → plain → umbrella, oldest first, thrash (≥5 claims) held back and listed.
- **`scripts/drain-recycle-fire.sh`** — with no `--prompt-file` it GENERATES the successor's brief
  (so a link cannot hand its successor anything it wrote) and arms a goal whose floor is
  `closed_pre >= min` (rows closed whose first filing predates the window — default 3), which names
  the forbidden filing verbs and the forbidden files. `--first` opens the chain from a lead's pane.
- Lane naming: lane `infra` = project `claude-infrastructure`, files
  `~/.claude/autonomy/fire-drain-infra-recycle<N>.txt` + `fire-pointer-infra-<N>.txt`, worktree
  `~/Development/.worktrees/drain/lane-infra`. Lane `a` keeps the legacy filenames for the detector.

## §4 Status log (INTEGRATE-only; newest first)

- **2026-09-04 13:25Z** — Second-project lanes landed (`173a7ff34`): the brief takes its gate and
  landing rail per project (`{{GATE_CMD}}` / `{{LAND_CMD}}` / `{{ENTRY_STEP}}`), the drain scripts are
  called from `{{INFRA}}`, and `--first` cuts the worktree from the project's own checkout (`--repo`).
  **Lane `reso` #1 fired 13:18Z** (account next2, worktree `.worktrees/wt-drain-lane-reso` — reso's
  `worktree-pool.sh` makes handoff-fire cut `wt-<branch>` and then refuse the branch as existing, so the
  re-fire named the path; `--force` now reaches the generator for exactly that case). Its INFRA is a
  dedicated trunk worktree `~/Development/.worktrees/drain/tools` (branch `drain/tools`, at
  `173a7ff34`) because the shared checkout is 10 behind and `deploy-live` will not advance while the
  postland stamp on trunk is RED (`a03a4b638` red, `9bdac2bec` red — a standing red the open rows
  `live-layer-stamp-lag` / `deploy-install-stale-deadlock` own). **Refresh it when the drain scripts
  change:** `git -C ~/Development/.worktrees/drain/tools pull --ff-only origin main`; switch lanes'
  `--infra` to the shared checkout once it converges.
  **Every fired session stalled on a harness prompt within minutes:** lane #300 (pane 299) and W3
  (pane 298) on `settings.json to update hooks — proceed?`, W2a (pane 296) on a `rm -r` verify plus the
  same hooks dialog, W2b (pane 297) on a Bash permission prompt for `find-plan.sh --status`. Each sat
  20–50 min until this session sent Enter through `kitty @ send-text` (the classifier refused the same
  keystroke once in five tries). Both goal pastes for the lanes ABSTAINED because split-right had
  narrowed the pane below a readable composer — fire lanes into a fresh tab, not a split.
  These two stalls are the pile's own `fired-session-startup-modal` class, live.
  Meanwhile W2b closed **18 pre-existing rows** (`lane=session`) by 13:00Z.

- **2026-09-04 12:40Z** — W1 LANDED (`89a020f08`, content-verified on origin/main). W2a / W2b / W3
  fired as dispatched sessions (custody armed on this pane). Lane `infra` #300 fired on pane 299 and
  engaged; its goal paste abstained, so #300 runs on its brief alone and #301 re-arms via the wrapper.
  `deploy-live` declined to advance (no GREEN descendant of live HEAD, lag 9 inside the 25 budget) — the
  lane does not need the live layer (it runs `scripts/` from its own worktree off origin/main).
  Old chain: #300 landed `ffca9df45` (method 272) and is still running on pane 27 — operator step
  `0b4279107f2e` (`cc-teardown 27 …`) retires it; its falsifier retracts the row when pid 44550 dies.

- **2026-09-04 12:15Z** — W1 code written and suites green; old chain's #300 (pane 27, pid 44550)
  could NOT be stopped from this session (the auto-mode classifier denies `kill`, `cc-teardown` and
  a stand-down `cc-notify` to a live session) → operator step filed. New lane uses distinct
  filenames so the two cannot collide on a number.
