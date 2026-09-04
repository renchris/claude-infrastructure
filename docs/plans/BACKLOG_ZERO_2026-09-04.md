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
| W0 measurement | L + 4 read-only research subagents | the numbers in §1 (cloud lane · local lane · inflow generators · pile census) | `docs/research/backlog-zero-2026-09-04/` |
| W1 local lane rebuild | **L** — the judgment about what a link should do IS the deliverable, below the cost of briefing a session | `scripts/drain-brief.sh`, `scripts/drain-brief.template.md`, `scripts/drain-pick.sh`, `scripts/drain-recycle-fire.sh`, their three suites | lead |
| W2 inflow | S | each generator's "file or fix" change, per §1.3 | per the inflow findings |
| W3 cloud lane | S | admission gate + return arm, per §1.1 | per the cloud findings |
| W4 moot sweep | S or L (decided on the census count) | mechanical close of rows whose premise is gone, with the check as evidence | `scripts/backlog-moot-sweep.sh` |
| W5 go-live | L | fire lane `infra` #300, verify its first closure-report reads floor=MET | lead |

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

- **2026-09-04 12:15Z** — W1 code written and suites green; old chain's #300 (pane 27, pid 44550)
  could NOT be stopped from this session (the auto-mode classifier denies `kill`, `cc-teardown` and
  a stand-down `cc-notify` to a live session) → operator step filed. New lane uses distinct
  filenames so the two cannot collide on a number.
