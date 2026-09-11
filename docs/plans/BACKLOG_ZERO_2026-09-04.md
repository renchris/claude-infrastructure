---
status: complete
created: 2026-09-04
closed: 2026-09-07
closed-evidence: docs/research/backlog-zero-close-2026-09-07.md (§7 below)
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

- **2026-09-08 — the "hooks-update approval modal" does not exist; the dialog is OUR OWN HOOK, and
  the 16:50Z disposition below is REFUTED.** Row `8ea3acef7d64` was filed as an undocumented dialog
  with no supported pre-approval whose fix was upstream and operator-owned (file the missing-docs
  question with Anthropic; test a `settings.local.json` placement). Read out of the shipping binary
  (`mHr` in 2.1.220, `Re` in 2.1.260) the observed screen is the ORDINARY tool-permission prompt
  raised by a PreToolUse hook that returned `permissionDecision:"ask"`, in three parts:
  reasonString `` Hook ${hookName} requires confirmation for this ${toolType} ${dim("[settings]")} ``,
  configString `` ${lBS(hookSource)} to update hooks `` (`lBS`: `plugin*`→`plugin hooks.json`,
  `skill*`→`SKILL.md`, else `settings.json`), and `AW`'s default question `Do you want to proceed?`.
  So `settings.json to update hooks` is the binary naming WHERE THE HOOK IS DECLARED — a pointer at
  this repo — not an approval of a settings change, and the emitters are ours: four `warn` sites in
  `hooks/validate-bash.sh` (`git reset --hard`, `git clean -x/-X`, two `rm -r`) and seven `ask`
  returns in `hooks/curl-gate.py`. The 16:40Z entry's own measurement corroborates it rather than the
  filed cause: W2a stalled on "a `rm -r` verify plus the same hooks dialog" — one emitter, one
  dialog. The five account `settings.json` rewrites at 13:50:44–13:51:31Z are a true metric beside a
  wrong cause (memory: `wrong-cause-corroborated-by-true-metric`); nothing in this dialog reads a
  settings file's mtime. **Not acted on, because it is the refuted half:** no upstream report, no
  `settings.local.json` test.
  **What that leaves, and what landed.** The symptom stands and is live. The harm the row names —
  the engagement detector reading a stalled pane as never-engaged, and INC-4 then minting a
  duplicate — was a GAP IN OUR OWN ENUMERATION: `hooks/lib/pane-modal.sh` listed only the MCP and
  workspace-trust dialogs, so `pane_wedge_reason` returned 1, `verify_engagement` fell past its
  WEDGED gate, and the INC-4 recovery pasted the whole brief into a pane whose dialog consumes those
  bytes as single-key answers. A third class `tool-permission-modal` now names it, so the fire
  returns 4 instead of 1: the resend is skipped, custody stays open and the goal is armed
  (`engage_rc_consequence` 4:custody / 4:goal), and the operator gets a remedy pointing at
  `validate-bash.sh` rather than at Anthropic. The fragments are the question and the refusal option,
  not the reasonString or configString, because those two carry a variable prefix the column-0 anchor
  refuses and are not contiguous literals the anti-rot arm could pin. **Still a REPORTER** — nothing
  answers the prompt; the reverted keystroke sweeper stays reverted. The suite's `modal_fragments`
  now derives from `compgen -v` over `CC_MODAL_*_{HEADER,OPTION}` instead of naming four variables,
  which is what its own header always promised (memory:
  `checker-population-rests-on-an-untested-belief`).
  **Open, and deliberately not driven here:** an `ask` is unanswerable by a fired peer, so those
  eleven emitters still hang an unattended session until a human presses Enter. Whether they should
  return `deny` (stricter, and it unblocks) for an unattended peer is a policy fork, not a defect —
  decision packet filed rather than guessed.

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

## §6 The blocked floor — a parking state with a cheap entrance and no scheduled exit (2026-09-06, frontier session `blocked-floor`, pane 338)

**Mandate:** the local lane drains the OPEN half and not the BLOCKED half — `backlog-telemetry.sh` read open
299 → 239 while blocked went 248 → 253 (09-04 → 09-06), 252 of 491 LIVE, flat. This section names what
holds a row in `blocked`, what was changed at the producer, and the number that moved.

### §6.1 What leaves `blocked`, measured — and the three candidates discarded

`blocked` is a state no lane reads, by construction: cc-dispatch excludes it (`bin/cc-backlog:767`),
`scripts/drain-pick.sh:80` selects `status == "open"` only (`:103` prints the rule), and the drain brief
tells a link *"If it is already blocked, do not touch it"* (`scripts/drain-brief.template.md:54`). A row
leaves only by `unblock`, by `done`, or by a passing falsifier. Folding the store sequentially, 180 rows
went blocked → done in the 14 days to 09-06: **64 `lane=land`** (ship-land's own *auto-retracted at
filing* — rows dead on arrival), **62 `lane=session`** (hand adjudication), 21 `local-drain`, **7
`sweep`**, 26 unattributed. So the one AUTOMATED exit is `cc-premise sweep --close-falsified 25`
(`scripts/autonomy-sweep.sh:1193-1196`, every 6 h at `taskpolicy -c utility`), and:

- it returned **rc 124 `bound-exceeded` on 5 of its last 7 runs** (IDL: 09-04 06:55Z and 14:20Z, 09-05
  01:57Z, 14:55Z, 22:07Z) and closed **5 rows since 09-03**; the stamp is touched BEFORE the pass
  (`:1192`), so a cut pass also postpones the next one by 6 h;
- it could not have moved the floor anyway: **194 of 252** blocked rows carry no probe of any arm
  (`cc-premise coverage`: probeable 231 · covered 39), and of the **54** blocked rows stamped in
  `backlog-validated.json`, 50 read `clear`, 4 `suspect`, **0 `falsified`** — where a premise IS re-checked
  it holds. *"The blocker premise is never re-checked"* is true and is not the lever.

Discarded with evidence: **reap churn** — 305 reap blocks / 311 reap unblocks in 14 d are the cloud lane's
*"a LIVE off-box worker (cc-cloud reads ALIVE) still holds…"* cycle (283 of 305) and net to zero; **0 of
the 252** live blocked rows were last blocked by the reap — all 252 by external callers. **Close
attribution 15.1%** — an all-time figure: the `lane` field first appears on a `done` at
2026-08-23T09:23Z, and **234 of 247** dones since 09-03 carry one. Not a live defect.

### §6.2 The generator: `needs` is the quiet door, and a machine walked agent work through it

Inflow into `blocked` in the same 14 days: **213 born-blocked adds** (`source=needs`) — **113 from ONE
call site, `scripts/ship-land.sh:1000`** (`land_failure_inbox`, the *"re-land <branch>: ship-land could not
complete and its author's pane may be gone"* row), against **100 from every session combined**. On the
live store: **48 of the 252** blocked rows were re-land rows, **47 with commits genuinely absent from
trunk** (`git cherry origin/main <ref>` prints `+`), all 48 keyed into `master-operator-gated` at filing
(`bin/cc-backlog:909`); **37 rc=6** (gate RED — author-fixable, `ship-land.sh:47`), 8 rc=5 (rebase
conflict), 3 SIGTERM. For **22** the branch was gone locally AND on origin, so the stored
`git checkout <branch>` failed at its first token; 5 sat in a live worktree. `MASTER_OPERATOR_GATED.md` O1
had adjudicated this exact class as `master-stranded-work` on 2026-08-17 — for two rows, by hand, and
*"named the retry storm, not diagnosed"* — while the producer kept minting; its DoD was met at 26 members
and the group held 176 today.

**Why that verb, and what selected for it.** `add` kicks `cc-dispatch --decide` (`bin/cc-backlog:6336` →
`dispatch_kick` `:6313`, a possible spawn); `needs` does not (`:778`). `add` could not carry a command —
`run` rode ONLY the block record (`:1174` fold, `:2744` writer). And a `needs` row never counts against its
filer: the ledger's FILED_MINE exempts any row with a `condition` (`scripts/wrap-ledger.sh:780`) and every
`needs` row is auto-keyed into the operator group at filing. The cheapest verb for the filer was the most
expensive for the pile, and a producer inside a failing land — the box loaded, the fire gate refusing —
reaches for the door that neither spawns nor haunts it. The hooks point sessions at the same door
(`hooks/completion-assert.sh:1096`, `drain-brief.template.md:54`). Same shape elsewhere on this box: reap
rule B (a load spike → `blocked`, 64% of the pile in August, `bin/cc-backlog:296-306`) and a venue label
outliving its rule (`cc-venue run`, zero callers until 08-24) — each a parking state with a cheap
entrance and no scheduled exit.

### §6.3 Why `cc-do <backlog-id>` closed zero

No surface renders it for a backlog row. `hooks/operator-readout.sh:1093` renders the class command as
`cc-backlog list --blocked` — a LISTING — and the 4+ arm (`:1118`) collapses the pile to one counted line
and never prints the `▶ <run>` rows it built at `:712`; `bin/cc-do` keeps `backlog --blocked` JUDGMENT by
design (its header), so only the typed `cc-do <id>` runs one, and nothing names it. The operator never
runs `cc-backlog`: of 687 `unblock` events all-time, 331 are sessions, 311 the reap, 0 by hand. And 48 of
the 118 `--run` rows were the machine's, not the operator's — 22 of those could not run at all.

### §6.4 Found on the way: the fold is a bash loop, and it is where the premise pass's bound went

`cc-backlog list --all --json` = **22.85 s** on the 17,005-line store (load avg 132). `valid_records`
(`bin/cc-backlog:1072`) tagged every line in ONE jq (0.09 s) and then walked the tagged stream in a bash
`while read` — **17.5 s**. Every verb folds at least once; the premise pass folds per candidate `done`
(60 s timeout each) and per `validated --batch` — which is how a 1,500 s bound at utility QoS ran out.
Rewritten as two jq passes (records to stdout; a census — line count + malformed line NUMBERS — to
stderr), every pinned message intact (`tests/cc-backlog.bats` P5/malformed 6/6): **2.50 s**. A whole-store
dry `cc-premise sweep --json` at `taskpolicy -c utility` on that fold: **877.7 s real / 185.9 s user** —
inside the bound the scheduled pass had breached five times running.

### §6.5 What landed — every edit to an existing script, no new machinery

- **`bin/cc-backlog`** — `add --run "<cmd>"` (on the add record; on a known live member, an `update`
  carrying `run` when it differs; the fold already carried `run` from any record). `valid_records`:
  bash read-loop → two jq passes (§6.4).
- **`scripts/ship-land.sh` `land_failure_inbox`** — the re-land row is filed **OPEN** (`add --title …
  --source needs --run … --why-not-now …`), never through `needs`; `--source needs` is KEPT because it is
  half the id and the id is the dedupe (a new source would mint a sibling beside every row already in the
  store on the branch's next attempt); `CC_BACKLOG_KICK=off` so a worker is never fired onto a branch its
  author is still retrying — the drain lane picks the row on its own cadence (tier 0 falsifier, oldest
  first). The stored command now survives a deleted branch (`git checkout -q <branch> || git checkout -q
  -B <branch> <pinned ref>`). A cc-backlog that predates `add --run` (exit 2, empty id — the LIVE binary on
  this change's first day) falls back to the legacy `needs` form, so a failed land is never unrecorded.
- **The live rows, re-keyed through the verbs** (append-only, `--by blocked-floor-1a78a148`): **49
  unblocked** (47 from the snapshot + 2 the still-live old producer filed at 03:43Z and 03:52Z while this
  session worked) → `link --condition master-stranded-work --force` → `add … --run "<fixed>" --why-not-now`
  (folds as an `update`); **1 closed MOOT** by content (`git cherry` empty). The fold reads all 49 as
  `status=open · condition=master-stranded-work · run fixed · whyNotNow set`.
- **Tests** — `tests/cc-backlog-add-update.bats` +3 (`--run` stored / update on change / no-op when
  unchanged); `tests/ship-land.bats` +2 (re-land from the pinned ref after `branch -D`; legacy-binary
  fallback), the first P4 case now asserts *no block record, `run` and `whyNotNow` on the add, source
  kept*, the N-sandboxes case counts records per id (an open row's second attempt is an `update`, not a
  second title), and the suite's `setup()` pins `CC_BACKLOG_BIN` to THIS tree's binary — unset, every P4
  case executed the LIVE `cc-backlog` and ten went red for a reason no diff here could reach (memory:
  unfixtured-sensor-executes-the-deployed-subject). Green: add-update 21/21 · needs 25/25 · cc-backlog
  P5/malformed 6/6 · ship-land `P4 inbox` 16/16. Red-proof on the pre-fix `bin/cc-backlog` +
  `scripts/ship-land.sh` (scratch copy, new tests): **5 of 7 red** — the two that pass pre-fix are controls
  by design (the legacy fallback IS the old path; the one-row identity was never the change).

### §6.6 Measurement (baseline 2026-09-06T03:32Z; after 03:57Z — all from `backlog-telemetry.sh` NOW)

| figure | before → after | reads it back |
|---|---|---|
| **blocked** | **252 → 204** | `backlog-telemetry.sh` NOW line |
| open / LIVE | 237 → 284 / 489 → 488 | same |
| re-land rows in `blocked` | 48 → 0 | `cc-backlog list --blocked --json \| jq '[.[]\|select((.needs//"")\|startswith("re-land "))]\|length'` |
| `drain-pick.sh` top 8 | all re-land, tier 0, 13–19 d old | `bash scripts/drain-pick.sh` |
| one fold | 22.85 s → 2.50 s | `time cc-backlog list --all --json >/dev/null` |
| dry premise pass, whole store, utility QoS | (bound-exceeded ×5) → 877.7 s | IDL `premise_pass_note` on the next scheduled pass after deploy |
| re-land rows born OPEN since the deploy | 0 (pre-deploy) | `jq -c 'select(.event=="add" and .source=="needs" and (.title\|startswith("re-land ")) and (.run//"")!="")' ~/.claude/autonomy/backlog.jsonl \| wc -l` |
| closes on the 49 re-keyed ids | 0 at 04:10Z | `jq -r 'select(.event=="done")\|.id' ~/.claude/autonomy/backlog.jsonl \| grep -cFf <(cut -f1 <the migrate table>)` — the drain lane's next links |

**Movement vs noise:** the 48-row drop is a RE-CLASSIFICATION and says so; the productive signal is (1)
`blocked` no longer re-filling from `ship-land.sh` (the first row above), (2) `done` events on the 49 ids
by `lane=local-drain` — the picker ranks them 1–8 today, so the next links will hit them first — and (3)
the next scheduled premise pass reading `ok`. LIVE alone cannot show any of it (±70/day).

**Dropped, not filed** (one line each): the other 156 blocked rows (100 session-filed in 14 d) — each is a
hand adjudication and where a probe exists the premise holds; a `cc-do --backlog` batch for the ~70
operator-runnable rows (O2's residue) — an operator surface whose number moves only when he acts, so it is
named here and left for a session with that mandate; the recurrence brake lives only in `needs`
(`bin/cc-backlog:3147`) — `add` dedupes by identity, which the stable title already guarantees.

### §6.7 First live read (2026-09-06T05:20Z, before the deploy)

- **The drain lane is eating the former floor.** 7 of the 49 re-keyed ids closed within 100 minutes of
  the re-key — 6 by `lane=local-drain` links between 05:08Z and 05:15Z (`ec2614142185`, `5318d2fe2692`,
  `ed20da9f2023`, `7a5eb14ee6fa`, `1614bb6a55d0`, `4ba12dfcd30e`), each adjudicated MOOT by content
  ("main is a strict SUPERSET of the ref …"), and 1 by a session. Before the re-key the drain had closed
  **0** of these rows in 19 days, because the picker could not see them.
- **The old producer kept minting until the deploy** — 3 more born-blocked re-land rows at 04:18Z,
  04:41Z and 05:04Z (the LIVE `ship-land.sh` still called `needs`), re-keyed by the same script
  (52 unblocked in all; a 53rd — this session's own gate-red attempt, `406d69cfdad8` — closed by content once the branch landed). One of the three was this session's own gate-red land attempt, filed through
  the NEW producer's legacy fallback because the LIVE `cc-backlog` refused `add --run` — the fallback
  path proven on the real store the same hour its test was written.
- `backlog-telemetry.sh` NOW at 05:19Z: **open=278 blocked=206 LIVE=484** (03:32Z: 237 / 252 / 489).

- **LANDED, NOT LIVE (06:04Z).** `ship-land.sh` landed the four commits as **`3c2d73c4c`** on origin/main (rebased twice
  under sibling lands; statics + ratchets green; smoke cut at its 900 s budget after 49 of the 136 direct suites — the
  post-land verifier is the net; 5 paths content-verified; stranded-sweep clean). `bash scripts/deploy-live.sh` then
  REFUSED, verbatim: *"waiting — no GREEN tree is a DESCENDANT of live HEAD 0c4bdedb4fef (the newest one, 24c598bac1c7,
  is BEHIND it — deploying that would report a deploy that never happened); lag 12 commit(s) / 1h39m, inside the degrade
  budget (25 / 6h) — no advance, and none is due yet"*. Every post-land stamp since 09-03 is `red` (the five newest:
  run_s 11,152–11,595, retries 18–26 — flakes under load, not this diff), so the enforcing store still runs the OLD
  `cc-backlog` and `ship-land.sh`: the old producer keeps filing born-blocked re-land rows until the converger's
  DEGRADED advance (`deploy-live.sh:1820`, "the newest NOT-RED commit, authorised by" 25 commits behind trunk or 6 h
  since the live commit's author time — 04:23Z ⇒ **10:23Z at the latest**). The session stays up to run it and prove
  `git hash-object ~/.claude/<f> == git rev-parse origin/main:<f>` for both files; the proof lines are appended below
  when they exist, never asserted before.

- **10:24Z — the degrade window opened and the converger was REFUSED by the shared checkout itself.**
  `deploy-live.sh`: *"DEGRADED deploy — … taking the newest NOT-RED commit instead, authorised by 6h02m since
  the live commit was authored (budget 6h)"* → *"REFUSED — git merge --ff-only 16cf74b19c1e FAILED in
  /Users/chrisren/Development/claude-infrastructure with all THREE named causes ruled out … GIT SAID: fatal:
  this operation must be run in a work tree"*. `core.bare` on the shared checkout reads **true** (`.git/config`
  mtime 08:43Z; `git worktree list` annotates the toplevel `(bare)`), the state memory
  `worktree-ops-can-bare-the-shared-checkout` records as a `git worktree add/remove` side effect (GH #34645 /
  #48927). The last store event before the flip is the OLD live `ship-land.sh` re-blocking re-land row
  `e3ce43bead25` at 08:39Z during a sibling's land — the very worktree cycle the re-land command runs in the
  shared checkout. `deploy-live.sh:554` ships the remedy as an operator `--run` for culprit
  `checkout-not-a-worktree`; this session's attempt to run it was refused by the auto-mode classifier
  (a config write on the shared checkout), so it is the operator's one command:
  `git -C /Users/chrisren/Development/claude-infrastructure config --unset core.bare && bash /Users/chrisren/Development/claude-infrastructure/scripts/deploy-live.sh --auto`.
  Until it runs, the live layer executes the pre-fix `cc-backlog` and `ship-land.sh` (both symlinks resolve
  into that checkout at 0c4bdedb4), and the old producer keeps filing born-blocked re-land rows.

- **LIVE — proven 2026-09-06T23:33Z.** The shared checkout was a work tree again when this pane thawed (its
  `core.bare` repaired by another actor between 10:26Z and 23:31Z — this session's own attempt was refused by
  the auto-mode classifier), and `deploy-live.sh` reads *"at trunk tip 8a40cd3fa667 — nothing above the live
  layer to deploy"*. Byte proof (`git hash-object ~/.claude/<f>` vs `git rev-parse origin/main:<f>`), verbatim:

  ```
  bin/cc-backlog         live=cd276bc355426866dfe8affdd6510a0120f9c2d1 trunk=cd276bc355426866dfe8affdd6510a0120f9c2d1 MATCH
  scripts/ship-land.sh   live=72c578625489d8b27357e72c449ebccbbfe9991d trunk=72c578625489d8b27357e72c449ebccbbfe9991d MATCH
  ```

  `backlog-telemetry.sh` NOW at 23:45Z: **open=290 blocked=216 claimed=0 LIVE=506** (baseline 03:32Z:
  237 / 252 / 489). **Re-land rows in `blocked`: 0** (48 at baseline). Closes on the re-keyed ids since the
  re-key: **8** (6 `lane=local-drain`, 2 `session`). Born-OPEN re-land rows on the live bytes: 0 so far — no
  land has failed on the new producer yet, which is the right zero. **Residual, named:** sessions run
  `scripts/ship-land.sh` from their OWN worktree's copy, so a worktree cut before `3c2d73c4c` keeps the old
  producer until it is recreated from trunk — one such row (`89e87a2f4450`, 23:43Z, session `cd80e372`) was
  filed in the old add+block shape and re-keyed here; drain links are fresh worktrees off origin/main each
  recycle and carry the fix. The blocked count itself drifted 204 → 216 across the day from session
  `needs` and re-blocks by stale worktrees, which is the population this section leaves to hand
  adjudication; the class this session owned reads 0.

## §7 CLOSE — DONE (adjudicated against trunk tip `902ac519f`, 2026-09-07, off-box cloud fire on row `64c150ba2a8e`)

**The frontmatter was the stale thing.** This plan read `in-progress` with 24 of 24 sections
scanning `PENDING`, while all **20** commits it cites are ancestors of `origin/main` and every
mechanism §3/§5/§6 describes is present in trunk *content*. Full adjudication, per-sha and
per-mechanism: **`docs/research/backlog-zero-close-2026-09-07.md`**.

The sections scan `PENDING` for a parser reason, not a work reason: `plan-phase-scan.sh` reads `DONE`
or a commit hash **in the heading**, which measurement and status-log headings do not carry. Nothing
in §1–§6 names remaining work.

| half of the mandate | state | evidence |
|---|---|---|
| local 24/7 drain | **delivered, live** | W1 `89a020f08` → W5's self-perpetuating chain (§4 17:20Z) → §5's close floor `c46af65b7` → §6's blocked-floor producer `3c2d73c4c`, byte-proven live 2026-09-06T23:33Z (§6.7) |
| cloud 24/7 drain | **delivered; ongoing ownership delegated** | W3's five commits are ancestors of trunk; `docs/plans/CLOUD_BACKLOG_PIPELINE.md` reads `status: complete`, and its §A9.5 records the deployed retire pass settling 299 of 331 declarations at 2026-09-07T05:30–06:20Z |
| the frozen scope's proof (`closed ≥ filed`) | **met when last read; not re-readable off-box** | §5.1 (09-05T03:47Z, rolling 7 d filed 137 / closed 205 / **net −68**) and §6.7 (09-06T23:45Z, 8 closes on the re-keyed ids, re-land rows in `blocked` 48 → 0) |

**Why `complete` rather than "open until the metric is re-read."** A metric holding is a continuing
measurement, not a task. LIVE rose 489 → 506 across 09-06 and this box (a cloud VM) cannot read the
store, so the number is not re-read here — but a plan kept open until a number stays good forever is
exactly the *"parking state with a cheap entrance and no scheduled exit"* §6.2 named as the
generator. The desk's re-read is `bash scripts/backlog-telemetry.sh`; a reversal is a new mandate,
not an unfinished section of this one.

The flip is mechanism, not bookkeeping: `find-plan.sh` `list_open` skips `complete|superseded`
(:108), so this plan stops minting new `plan-open` rows, and clause (a) of the stored falsifier
(`plan-phase-scan.sh --falsify` → `find-plan.sh --status`) now returns `FALSIFIED`, retracting row
`64c150ba2a8e` on its next premise re-run.

### §7.1 Two corrections this close makes to the sections above

- **§5.5's forward pointer is RETRACTED, not deferred.** It leaves *"re-keying that falsifier on the
  branch's patch-ids"* as where the amend case *"lives"*. The falsifier it would re-key **is**
  `scripts/land-content-verify.sh`, whose header records patch-id as measured unfit for this exact
  job: *"`git cherry` (patch-id) — wrong in BOTH directions: it cleared 3 refs that still held
  residue, and convicted `0a131da73` whose every path was blob-identical to trunk."* The re-key would
  trade a bounded false-*strand* for a documented false-*clear*, and a false clear here is the
  failure the oracle exists to prevent (*"actioning four of them would have REVERTED trunk"*). The
  amend case is a design limit of a content-superset oracle with a named cost — **3 rows in 167
  (1.8%)**, below the ±70/day noise — reachable by neither rescue arm (SUPERSEDED needs trunk to have
  once carried the ref's whole-file blob; RELOCATED needs trunk to be a multiset superset of its
  lines). Not an open task with a known fix.

- **§5.5's `45 genuinely unlanded` and §6.2's `47` are patch-id-derived upper bounds, not content
  verdicts.** Both were measured with `git cherry origin/main <ref>` — the instrument the paragraph
  above documents as wrong in both directions. **The §6 re-key was safe anyway, and the reason is the
  direction:** it moved rows `blocked → open`, the *preserving* direction, so the next drain link
  re-adjudicated each by content (§6.7: 6 closed MOOT reasoning *"main is a strict SUPERSET of the
  ref"*). Had that instrument been used to **close** them, its documented false-clear rate would have
  stranded real work silently. The content verdict for any single row is
  `bash scripts/land-content-verify.sh <ref> --no-fetch`.
