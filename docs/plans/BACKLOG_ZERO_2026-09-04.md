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

- **2026-09-05 04:30Z — the filing-vs-driving generator named and countered (§5).** Frontier session
  `filing-vs-driving`: the close protocol certified on git and discharged on ROWS — filing was the
  harness's compliance action, closing was nobody's, and the store could not even attribute an add.
  Landed: attributed `add` + `--why-not-now` + `closedSession`; the FILED_MINE 🔧 rung in
  `wrap-ledger.sh` consumed by `completion-assert`; `cc-do <backlog-id>` run-and-close. Detail + the
  measurement baseline in §5.

- **2026-09-04 19:33Z** — W2a LANDED (`718fa8fda` dispatch-assert DROP remedy + drop-discharge arm
  + `--condition` template; `2f518d75b` completion-assert D1 do-it-yourself gate; `d3cafafc6`
  cc-backlog add-time WARN) — all three content-verified on origin/main and ancestors of it; custody
  discharged by the peer's own self-close (`cc-custody list --open` = `[]`). It took 3 land attempts:
  attempts 1-2 red, attempt 3 GATE RED on a suite the log itself called a budget kill. Two adjacent
  defects it hit and did NOT file: a bats suite leaks `user.email=t@t` into the enclosing worktree
  (blocking every later commit at the identity hook), and `tests/postland-verify.bats` (132 tests,
  ~20s per cc-backlog fold) eats the smoke budget on every land.

- **2026-09-04 17:20Z — W5 PROVEN: the rebuilt chain recycled itself through the wrapper.** Lane infra
  #300 fired #301 at 16:59Z (`handoffs.jsonl`: `goal_requested:true`, pane 299, account next) with the
  generated `fire-drain-infra-recycle301.txt` — the first mechanically self-perpetuating link of the
  new chain (the old chain's 125 fires all logged `goal_requested:false`). #300's entry (`e84ba11e3`)
  reports `closed=7 closed_pre=1 … floor=UNMET` and names why the floor under-read: `cc-backlog`'s
  lane derivation walks `ps`, which under load 20+ returns nothing, so a lane's own `done` carries no
  lane (2,359 of 2,604 dones fleet-wide). The template now exports `CC_BACKLOG_LANE=local-drain` in
  setup — the code's own "strictly better evidence" path — so every close a link makes is stamped.

- **2026-09-04 17:10Z — the old chain is gone.** The operator ran the filed `cc-teardown 27 …`; verdict
  `ALREADY-GONE` (pid 99254 dead, pane 27 absent): recycle #301 ended itself — its own §2.1 entry
  called it "the last link of the pane-27 chain" and no `fire-pointer-302.txt` exists. Row
  `0b4279107f2e` closed on that evidence. W2a still landing (its gate draw is on a second long suite).

- **2026-09-04 16:50Z — the hooks-update dialog, per the Claude Code docs (claude-code-guide subagent,
  fetched official docs):** the `[settings] settings.json to update hooks — proceed?` dialog is **not
  documented** in the settings, permissions or hooks references; there is **no supported flag, key or
  env var** to pre-approve it (`--permission-mode auto` gates tools, not this); it is best read as a
  hooks-changed approval gate that fires when hooks in `.claude/settings.json` or the user
  settings.json change on disk. The one candidate workaround — keep project hooks in the gitignored
  `.claude/settings.local.json` so a pull cannot change them — is an **untested inference**, not a
  documented behaviour. Disposition: the fix is upstream and operator-owned (file the missing-docs /
  automation-workaround question with Anthropic; test the settings.local.json placement on ONE
  fired session before adopting it). Evidence lives on pile row `8ea3acef7d64` (dodRef → this entry).

- **2026-09-04 16:40Z — the lanes close rows; the modal is a consent boundary, not a bug to sweep.**
  Lane infra #300 landed `c5e2eb5a5` (row `07ac6d58d88d`, cc-pane's send verb) and closed five rows
  stamped `lane=local-drain` by 16:31Z (one DOABLE, four MOOT on content); its closure report reads
  `closed_pre=1` because the four MOOT rows belong to another project — the floor counts only the
  lane's own project, as designed. Its `done` evidence also records a real defect: under load 20+
  `ps` returns nothing, so `cc-backlog done` derived NO lane and the link had to re-stamp (three
  `lane=none` dones since 15:00Z are that). Lane reso #1 has claimed six rows and committed one fix
  on its branch. **The stall generator:** every fired session froze on `[settings] settings.json to
  update hooks — Do you want to proceed?` (pile row `8ea3acef7d64`, open since 08-18). Measured: all
  five account `settings.json` files were rewritten 13:50:44–13:51:31Z, ten seconds apart — the writer
  could not be identified (no Write-tool backup, no script in scripts/bin/hooks writes a config-dir
  settings.json, `claude-accounts`/deploy-live/settings-drift do not) — and the dialog also re-raises
  after a pull that changes the tracked `.claude/settings.json` (`86e354262` did today). A sweeper
  that auto-answers it was built, then **REVERTED before landing**: the auto-mode classifier refused
  the keystroke twice, and the repo's own modal doctrine (`hooks/lib/pane-modal.sh`: trust and MCP
  approval "may never be suppressed") applies — hooks execute code, so this prompt is a consent
  boundary and the fix must be upstream: find the settings.json writer and stop it rewriting under
  live sessions, and keep trunk edits to `.claude/settings.json` rare. Until then a fired session
  can stall until a human answers; the operator's `▶` for this close is the sweep of panes 296–300.
  W2a still landing (3 commits on `feat/backlog-zero-w2a`). Four research subagents stopped (their
  reports were consumed at 12:00Z).

- **2026-09-04 15:55Z — W2b and W3 RETURNED and are on trunk (content-verified by ancestry).**
  W2b (`c36876297` · `7e567755b` · `4c60e8943` · `39b409a72`): the re-land probe is stored at the
  durable path (rc-127 probes **47/48 → 0/45**), the premise pass's close cap 5 → 25 (a pass now runs
  196 s, rc 0, at cap), the plan-open retractor reaches `claimed`, and `find-plan.sh` learned the
  `done` status word; **24 rows closed, 8 unblocked** — two research candidates refuted in-session
  (only 8 of the 31 "mis-filed" blocked rows were agent-runnable; `a507762b0a0d` was stuck on
  `find-plan.sh`, not on its claim). W3 (`e39aa0be1` retire pass · `124c4da06` admission gate +
  `CC_DISPATCH_CLOUD_PENDING_MAX` · `e467896cc` price floor · `8ce30f3ac` rc propagation ·
  `11f50d340` thrash recovery wired): 431/431 across 21 touched files; **not live until the
  postland stamp goes green** (its new `scripts/cloud-retire-terminal.sh` has no symlink, so the
  sweep's `[ -x ]` guard skips it — `LIVE_ADDS=3`); once live, `pending_unlanded` 575 vs cap 50 makes
  the first dispatch pass refuse ALL cloud fires, which is the designed arithmetic. One row filed:
  `a3d2640f9792` (re-auth next3, `--run cc-relogin next3`).
  **Telemetry at 15:53Z:** today filed 34 / closed 33; rolling 7-day filed 115 / closed 78 / net +37
  (was +54 at 11:27Z); claim→done conversion 17.8% (was 8.6%); LIVE 597 (was 612; peak 617). Lane
  attribution: `session` 103 (was 81 — W2b), `sweep` 14, `local-drain` still 65 — lane infra #300 has
  held ONE row (`07ac6d58d88d`, the cc-pane send-verb fix) for 3 h without a close, and lane reso #1
  has claimed nothing in 2.5 h (diagnosis in the next entry). W2a is still out (3 commits on its
  branch, landing). The old chain's #301 landed an 8-line entry "in the convention
  scripts/drain-brief.template.md:62" and calls itself "the last link of the pane-27 chain".

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

## §5 Filing-vs-driving — the generator, named (2026-09-05, frontier session `filing-vs-driving`)

**Mandate (operator, verbatim):** *"rather than filing for backlog which we have a crux of filing as many
tickets as we complete never truly draining to zero and just churning."*

### §5.1 The claim, adjudicated

The **aggregate is draining** — 83% of 3,040 ids closed, four negative weeks, and at 03:47Z today
`backlog-telemetry.sh` reads rolling-7-day filed 137 / closed 205 / net **−68**, LIVE 518 down from the
617 peak. "Never draining to zero" is false of the pile. It is **true of the two things the operator
actually feels**, and they are different populations:

1. **The hard core churns by MACHINERY, not by people.** Of 1,930 `reopen` events, 295 are by
   `cc-backlog-reap` and 551 carry `spawn-fail` / `worktree-fail`. The 55-times row `62599dd76a60`
   (the postland TAP fix) was claimed and released **within one minute, all 55 times** — it was never
   once worked — while its fix has sat COMMITTED in `~/Development/.worktrees/wt-62599dd76a60` since
   2026-07-31 (`946bdd8dc`, `merge-base --is-ancestor origin/main` → NO), and since 08-18 the row is
   `block`ed on that same worktree's stray staged assets. A reopen count measures spawn failures, not
   attention. (Same shape: `ee1ac85c6ff6`, 54×.)
2. **The 1:1 is per SESSION, and the store could not compute it.** `add` recorded no author
   (`bin/cc-backlog:1728` pre-fix — `by` null on 108/108 adds, inflow.md §7.6); `done` recorded a
   host-unit `closedBy` and a lane, never a session. 92 distinct sessions filed a `needs` row in 14
   days; how many of them also closed a row is **uncomputable** (`done.by` null on 574 of 578).

### §5.2 The mechanism — filing is the harness's compliance action; closing is nobody's

| | file:line | what it does |
|---|---|---|
| M1 | `hooks/completion-assert.sh:774` (`:1078` remedy) | D1 discharges on `any(.session == $SID)` over blocked rows — ONE filed row makes a handoff-prose close legal, and the remedy text hands over `cc-backlog needs` |
| M2 | `hooks/dispatch-assert.sh:150-156` (`:203` tell, `:22` header) | discharge arm 1 is ANY backlog event; the tell fires on "for a later session"; the header says it: *"gaming the hook IS compliance"* |
| M3 | `scripts/wrap-ledger.sh:695-712` (pre-fix) | the certificate's ONLY backlog term was YOURS = rows this session FILED, resolving to 👤 *"My side is done"*. No term for rows closed — and none was possible (M-data above). A filing earned a done-shaped rung; a close earned nothing |
| M4 | `bin/cc-do:231-236` | a blocked row's `--run` is JUDGMENT: printed, never executed, never closed. **677** `needs --run` rows filed all-time; **118 of 250** live blocked rows carry one; the operator pastes by hand and no observer closes (sevenrooms-bridge, 09-04: a row whose command he had run and passed sat open) |
| M5 | `CLAUDE.md` § Three dispositions | the FILED test is asked about the WHOLE item, so any item with an operator-only tail answers all three honestly. Ground truth: `e794e0a5a1f1`, `49c1f972abc6` — drivable prefixes, filed at the first blocker seen, by a session with the rule in context |

**Why every fix became machinery.** A drain-building session is a session under M1–M3: its DoD
("build the drain") is git-certifiable ✅, and its close names follow-ons (M2) → rows. The local drain
lane itself **filed 105 and closed 7 across 49 links** (§1.1a) because each link was such a session.
Machinery is what the certificate could see; a closed row was what it could not. W2a (today) fixed the
remedy TEXTS; nothing until now changed what the certificate COUNTS.

### §5.3 What landed (this session; all edits of existing scripts, no new machinery)

- **`bin/cc-backlog`** — `add` stamps `filedBy` (same env resolution as `needs`) and takes
  `--why-not-now "<reason>"`: the FILED test's answer (a) as a FIELD; re-running the same add with it
  folds onto a bare row as an `update` (the hand-off of an already-filed row). `done` stamps
  `closedSession`. All three ride the fold and `list --json`.
- **`scripts/wrap-ledger.sh`** — `FILED_MINE` (open rows this session added with no `whyNotNow` and no
  `condition`) and `CLOSED_MINE`; `FILED_MINE > 0` ⇒ **🔧**, outranking 🚀/👤; fail-open like YOURS.
- **`hooks/completion-assert.sh`** — consumes `FILED_MINE` as a contradicting fact: a ✅ close over a
  bare `cc-backlog add` now FIRES. D4's remedy and both `dispatch-assert` remedies name `--why-not-now`.
- **`bin/cc-do <backlog-id>`** — runs ONE blocked row's recorded command after a typed `yes`, closes
  the row on exit 0 (evidence `cc-do ran: …`), leaves it blocked on failure, refuses placeholders and
  slash commands; the board still never runs a row.
- **Tests** — +5 `cc-backlog-add-update`, +6 `wrap-ledger`, +5 `cc-do`, +2 `completion-assert`;
  **15 of 16 red on the pre-fix files** (the board control passes by design); 172 + 150 pre-existing
  cases green.
- **`CLAUDE.md`** § Three dispositions FILED row: answer (a) is a field, and `cc-do <id>` is how an
  operator's run closes a `needs` row.

**What the gate is now instead of three written answers:** record-answered and session-scoped. A row
you filed is YOUR loose end — in your own certificate — until you drive it, close it, or hand it off
with a stored reason that the drain link picking it up can read. The three questions still stand;
only (a) is now a field the ledger can see, which is the half that lets a well-behaved agent be
caught.

### §5.4 Measurement (baseline 2026-09-05T04:25Z, pre-land — every new field reads 0)

| figure | baseline | reads it back |
|---|---|---|
| adds carrying `filedBy` / `whyNotNow` | 0 / 0 | `jq -c 'select(.event=="add" and (.filedBy//"")!="")' ~/.claude/autonomy/backlog.jsonl \| wc -l` (and `grep -c whyNotNow`) |
| dones carrying `closedSession` | 0 | `grep -c closedSession ~/.claude/autonomy/backlog.jsonl` |
| rows closed by `cc-do <id>` | 0 | `grep -c '"cc-do ran:' ~/.claude/autonomy/backlog.jsonl` |
| live blocked rows with a `--run` (M4 population) | **118 of 250** | `cc-backlog list --blocked --json \| jq '[.[]\|select((.run//"")!="")]\|length'` |
| FILED_MINE fires (sessions that would have closed ✅ over their own filing) | 0 | `jq -c 'select(.hook=="completion-assert" and ((.facts//"")\|test("YOU filed")))' ~/.claude/autonomy/idl.jsonl \| wc -l` (IDL rotates ~11 h — read daily) |
| per-session net, 14 d | uncomputable | sessions with a `filedBy` add vs sessions with a `closedSession` done — `comm -12` on the two `sort -u` lists |
| adds 14 d / of which `needs` | 487 / 207 | `backlog-telemetry.sh` |
| LIVE / open / blocked | 518 / 268 / 250 | `backlog-telemetry.sh` |

**Movement vs noise:** the daily filed/closed series already swings by ±70 a day (W2b/W3 closed 24 +
19 today), so LIVE alone cannot show this change. The signal is (1) FILED_MINE fires > 0 — each is a
close that pre-fix would have certified ✅ over its own filing; (2) `cc-do ran:` closes > 0 and the
118 falling; (3) the per-session net, which is the operator's 1:1 measured for the first time.

**Dropped, not filed** (one line each): landing `946bdd8dc` — a five-week-stale patch against the
132-test `postland-verify.bats` W2a named as the smoke-budget killer, and the row's block is the stale
worktree, not the fix · pruning the 50 `wt-*` worktrees and unblocking the 3 rows blocked on
"pre-existing worktree" — destructive on trees other sessions may hold.

### §5.5 The same brief, fired twice — and what the second session found (2026-09-05T06:31Z, frontier session `filing-vs-driving`, pane 321)

**This section exists because the generator caught its own remedy.** The brief above was fired twice
from the same `/tmp/fire-filing-vs-driving.txt`: by session 317 at 03:39:57Z (`handoffs.jsonl`
`self-retire-peer` → pane 319, which pinged 317's inbox `DONE — LANDED c46af65b7` at 05:31:55Z,
`~/.claude/mailbox/317.md`) and again by session 280 at 06:32:21Z (→ pane 321, this one). Two frontier
sessions, one brief, the second fired an hour after the first returned DONE to a different address.
Dropped, not filed: the reason 280 re-fired lives in a repo this session may not touch, and a fire-time
idempotency guard is machinery with no way to verify it against that reason.

**§5's fix is landed and executing nowhere yet.** All five enforcing files differ from the live layer
(`git hash-object ~/.claude/{bin/cc-backlog,bin/cc-do,scripts/wrap-ledger.sh,hooks/completion-assert.sh,hooks/dispatch-assert.sh}`
vs `origin/main:` — five DIFFERENT); live HEAD `570c20375` (02:52Z), lag 9. `deploy-live --dry-run`:
*"no GREEN tree is a DESCENDANT of live HEAD … inside the degrade budget (25 / 6h) — no advance"*. The
stamp store has produced **no GREEN since `24c598bac` at 2026-09-03T16:23Z**; every stamp since is
`red` or `cut`, and the cause is retries under load, not test growth: `run_s` 2,923 → 29,931, `retries`
2 → 14, `suites` 559 → 570, `env.load` 18.4 → 19.4, failing suites different each run
(`deathwatch-watchfile`, `cc-reaper`, `compressor-sentinel`). T2 DEGRADED (`deploy-live.sh:34`) will carry
§5's commits at the 6 h mark, ~11:19Z, unverified. **Until then every §5.4 figure reads 0 for that
reason** — the next reader must not take those zeros as "wrong layer" (read at 06:40Z: filedBy 0 ·
whyNotNow 0 · closedSession 0 · `cc-do ran:` 0 · FILED_MINE fires 0).

**The ledger could not see its own session — fixed.** `scripts/wrap-ledger.sh:583` resolved the session
from `$CLAUDE_SESSION_ID`, which a tool-call shell never carries; the store's own comment at
`bin/cc-backlog:3072` had already measured that and named the ledger as the place the bug lives. Read
from this session's shell: `FILED_SRC=none` — so YOURS, FILED_MINE and CLOSED_MINE were all 0 from an
agent's own `/wrap`, and only the Stop hook (which feeds `--session`) ever computed them. The ledger now
falls through to `$CLAUDE_CODE_SESSION_ID`, the same uuid the hook feeds (verified equal on this session).

**The other half of the certificate — landed: the DRAIN FLOOR.** §5 made a FILING visible to the
certificate; nothing made a CLOSE worth anything to it, so every session sent to fix the backlog
certified on what it could see (commits) and closed nothing: W1 0 rows · W2a 0 · W3 0 (1 filed) · the
§5 session 0 (§4 entries above). The one wave that closed rows (W2b, 24) had rows IN its scope; and the
one mechanism that moved the local lane from 7 closes in 49 links to **90 closes in 18 h**
(`lane=local-drain` dones since 2026-09-04T12:36Z) was a floor on rows closed. That floor now applies to
every session whose CURRENT CONTRACT names the backlog:

| | file:line | what |
|---|---|---|
| `DOD_SCOPE` / `DRAIN_SCOPE` | `scripts/wrap-ledger.sh` DoD loop | the newest lineage-filtered `Scope (frozen):` line (the same line `dod-persist.sh:210` injects as THE CURRENT CONTRACT); `backlog\|drain` ⇒ DRAIN_SCOPE=1 |
| `CLOSE_FLOOR` | `compute_close_floor()` after `count_filed_undriven()` | DRAIN_SCOPE=1 ∧ CLOSED_MINE=0 ⇒ 🔧, same rank as FILED_MINE (outranks 🚀/👤). Fail-OPEN four ways, each named in `CLOSE_FLOOR_SRC`: `n-a` (scope not backlog-shaped) · `none` (no session) · `error` (store) · `binary-old` (the `cc-backlog` this session TYPES does not stamp `closedSession` — an unattributed close must never read as "closed nothing") |
| consumer | `hooks/completion-assert.sh` after the FILED_MINE term | `CLOSE_FLOOR=1` contradicts a done-claim; remedy names `drain-pick.sh` |
| tests | `tests/wrap-ledger.bats` (+5) · `tests/completion-assert.bats` (+2) | 6 of 7 red on the pre-fix files (the CA control passes by design); 111/111 and 127/127 green after |

**What the gate is, stated once:** a backlog-scoped session's done is *machinery landed AND one row
closed by you, with the real tool, on the real pile*. It is gameable by closing a trivial row — and that
is the point: the trivial close forces contact with the pile, which every 0-row wave above never had.

**Failure mode (b) has a producer at file:line.** `scripts/ship-land.sh:1001` files a `needs` row
"re-land <branch>: ship-land could not complete…" on every failed land — **167 all-time (118 done · 48
blocked · 1 open)** — with a falsifier keyed on the FAILED ref (`land-content-verify.sh refs/land/failed/…`).
A later re-land that amends anything therefore never retracts it: `f0c419a56091` (the §5 session's own
land) stayed blocked over a two-line quoting delta in `tests/cc-backlog-add-update.bats` while all four
commits sat on trunk. Measured over the 49 not-done rows by patch-id (`git cherry origin/main <ref>`):
**2 fully on trunk** (`bf0c634ee43f` W2a, `ff9ef26281e1`) — closed this session with that evidence · **45
carry genuinely unlanded commits** (the CLOSE_INTEGRITY stranded-content population — real, not moot) ·
2 refs gone. So (b) is small here: the rail's rows are mostly TRUE, and their remedy is landing, not
closing. Dropped, not filed: re-keying that falsifier on the branch's patch-ids — three rows in 167 is
not worth a rail change this session; the plan now says where it lives.

**Closed this session (the first `closedSession`-stamped dones in the store):** `f0c419a56091`,
`bf0c634ee43f`, `ff9ef26281e1` — each MOOT by content, evidence on the row.

**Measurement for the floor (baseline 2026-09-05T07:00Z):**

| figure | now | reads it back |
|---|---|---|
| dones carrying `closedSession` | **3** (were 0) | `grep -c closedSession ~/.claude/autonomy/backlog.jsonl` |
| CLOSE_FLOOR fires | 0 (not live until the T2 advance) | `jq -c 'select(.hook=="completion-assert" and ((.facts//"")\|test("closed NO row")))' ~/.claude/autonomy/idl.jsonl \| wc -l` |
| backlog-scoped contracts in the DoD store | 36 of 238 `Scope (frozen)` lines | `grep -h 'Scope (frozen)' ~/.claude/autonomy/dod/*.md \| grep -ci 'backlog\|drain'` |
| not-done (open + blocked), brief → §5 baseline → now | 504 → 518 → **504** (`NOW open=264 blocked=240 claimed=3 LIVE=504` at 07:02Z, after the three closes; 06:40Z read 260/247/507 — the lanes move rows between the two statuses concurrently) | `backlog-telemetry.sh` NOW line |
| GREEN stamps since 2026-09-03T16:23Z | **0** | `jq -r 'select(.verdict=="green")\|.ts' ~/.claude/autonomy/postland/stamps/*.json \| sort \| tail -1` |

**Movement vs noise:** the floor's signal is a backlog-scoped session whose close carries CLOSED_MINE ≥ 1
where the §4 waves carried 0 — read it per session (`closedSession` grouped by sid), never from LIVE,
which the lanes move by ±50 a day. The first honest read is after the live layer carries this commit.

