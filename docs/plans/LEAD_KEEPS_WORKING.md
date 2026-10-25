---
status: complete
---

# Lead keeps working while a decision is open — implementation plan

Scope (frozen): lead-idle-fix — Phase 1: a Dynamic Workflow researches and writes one design doc under docs/research/ (chosen design, rejected rivals and why, test plan) covering (a) keep working on ungated in-scope items, (b) class B for judgment calls with a status-quo course, (c) find an existing ruling before asking, (d) standing operator grants loaded every session (first: Codex cross-vendor review), (e) the close stack refuses a Blocked idle while ungated in-scope work remains, loop scopes included, (f) wake a stalled session itself; Phase 2: implement it with tests that fail without each change, land via project /ship, converge, verify deployed ~/.claude copies by content; no settings-file edits, no weakened gate.

Ruling: operator decision `d610f8473106` (2026-10-24). Incident: `~/.cache/agentsync-bring-back/b13/report/why-the-lead-idled.md`.
Design (the SSOT for every file, line anchor, bound and test): `docs/research/lead-keeps-working-2026-10-24.md`; its §8 is the step table this plan executes.

## Phase 0 — Agent Team Orchestration

**EXECUTION LOCUS PER WAVE**

| Wave | Locus | Tracks (design §8.1 steps) | Why this locus |
|---|---|---|---|
| 1 | **S** (default) | A scope floor (1, 2, 3) · B subject nudge (4) · C decide + grant code (5, 7) | disjoint file sets; each track leads its own Agent Team in its own worktree |
| 2 | ~~**S**~~ → **Workflow** (2026-10-25) | D rule and machine text (6) | planned as S, fired after A and C land, so no loaded sentence names a verb that is not yet on trunk. **Changed:** kitty's remote-control socket answered "broken pipe" (pid 1881 alive), so no pane could open for a dispatched session or a named teammate, and the fire's capacity term hung 40 min on a wedged `ps -o lstart`. D ran as Workflow `wf_f309b42b-d65` (in-process slots, no pane): implementer → fresh-context reviewer → fixer, in worktree `lkw-rule-text`, committing only; the lead lands it after A |
| 3 | **L** | integration: B13 replay suites, red/green receipts, converge check, deployed-copy content check, class-A records, pings | one line of why: it is synthesis of the tracks' receipts, small output, and the goal's proof must surface in the lead's transcript |
| 4 | ~~**S**~~ → **filed** (2026-10-25) | E held-out instruction re-gate (9) | planned as S on the reading that the 2026-10-04 ruling authorized it at the next slim edit. **Corrected:** `INSTRUCTION_BUDGET.md:125-133` records that the 100-run design cannot pass (a perfect tie bounds at −7.1 pp) and the powered 640-run design (≈37-58 weekly pp) needs the operator's go-ahead; no answered packet authorizes it (`cc-memory-search --decisions`). Filed as class B `918de439021b` (default: defer, no run; deadline 2026-10-28T20:00Z; recommendation: run on idle quota, conviction 65). It gates only this wave |

**Lead context budget.** The lead (session `3d1dc252`) holds ≤ 50% of its 1M window for deciding; it reads track
pings and receipts, never track diffs in full. Succession point: at 60%, or at any idle after Wave 2 is fired with
≥ 35%, recycle with this plan as the bridge (`handoff-fire.sh --recycle`).

**Land order.** A lands 1+2 before 3 (consumers read absent fields as today, so each land is safe alone). B is a
no-op until A's floor writes `scope-floor*` IDL rows, so it lands whenever it is green. C's `.ceiling` field makes
A's hold tiers stricter when present and absent folds to "no ceiling", so C and A land in either order. D lands
after A and C. Every track converges its own land (`CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh`).

**Test contention.** cc-bats admits 2 live bats roots under load (`bin/cc-bats:514`); an rc 75 is a deferral, not a
verdict. Every track runs its own direct suites, asserts the `1..N` plan line, and never trusts the land smoke
(it cuts at 900 s or is shed under load; `maps/test-infra.md` §2.2).

## Tracks

| Track | Worktree / branch | Status | Landed shas |
|---|---|---|---|
| A scope floor | `lkw-scope-floor` | **DONE 2026-10-25**, landed + converged, 13 paths content-verified by the lead (diff vs A head empty) | tip `44948733e` (receipts in its body); ledger fields + loop-scope lib, dod-persist capture-loop/hold/done, inflight lib, scope floor + ⛔ mechanical arm |
| B+C subject nudge + decide/grant code | `lkw-nudge-decide` | **DONE 2026-10-25**, landed + converged, 15 paths content-verified by the lead | `476870a58` nudge (test T43) · `65e7af8df` xvendor-review.sh · `cadfaff50` cc-decide `--help`/`--ceiling`/hints + cc-memory-search `--decisions` + anti-deference + gate_sweep `--ceiling program` · `ea8d879cb` operator-readout setup · `94c9b550d` e2e STALL_S 5→60 |
| D rule and machine text | `lkw-rule-text` | **DONE 2026-10-25**, landed + converged, 12 paths content-verified; deployed `~/.claude/rules/10-session-close.md`, `~/.claude/CLAUDE.md` and `~/.claude/CLAUDE.full.md` byte-identical to trunk | `7e123270d` rule and machine text · `14efdf0a3` review fixes |

A receipts (commit `44948733e` body; ping 2026-10-25 07:22): RED on `origin/main` — scope-floor 30/30, C5 5/7 (M3 by
mutant, M5 control), ledger L 26/27 + memo 1/1, dod-persist 11/11, inflight 15/15; MUTANTS — 15 floor/C5, 10 ledger,
5 store, 4 inflight, all red; GREEN — scope-floor 1..31, inflight 1..15, session-continue 1..68, dod-persist 1..64,
ship-floor 1..10, wake-floor 1..54, wrap-ledger-memo 1..30, forks 1..5, wrap-ledger 167/169 (59/60 load flakes, green
isolated). Live after converge: the B13 session reads `LOOP_SRC=own LOOP_OPEN=1 SCOPE_UNGATED=1`. Deviations: no
`--session` flag (the hook env already carries `CLAUDE_CODE_SESSION_ID`), L24 is a control, assignee/teardown abstain
silently, a tsv-pad-lint exemption for inflight.sh, forks parity normalised. Pre-existing reds not ours:
tests/tsv-field-collapse.bats 30, tests/wrap-ledger-research.bats 7 (load).

B+C receipts (its commit bodies hold the detail): RED on the pre-change subject — T43 28/39, xvendor 23/23, cc-decide
new 10/12 (2 negative gates green by design), cc-memory-search 2/2, research-kit-gate 1/1, anti-deference 1/2;
mutants — supervisor 20/20, xvendor 6/6, decide 13/13 red; GREEN — lead-supervisor 1..12, xvendor-review 1..23,
cc-decide 1..88, cc-memory-search 1..21, plus 10 neighbour suites. Live Codex smoke (meter 0%, 3,395 tokens): the
export is readable and a real-HOME file reads "Operation not permitted". Design correction: tests/operator-readout.bats
did NOT already unset the session ids (4 class-C cases went red until `ea8d879cb`). Trunk red not ours:
tests/headless-address-consumers.bats test 9 (red on `3d6d8f85a` too).
| E re-gate | — | filed for the operator as class B `918de439021b` (see Phase 0 wave 4) | |

Learning (2026-10-25): B and C were merged into one session because the fire capacity gate held the box at its
active-session ceiling (8 mid-turn at ~40 load/core) for over 30 min; one session with two disjoint teammate groups
needs one slot. The B+C fire used the gate's one-fire raise (`CC_FIRE_ACTIVE_CEILING=9`) because the firing lead is
counted only while mid-turn and goes idle once the track runs, so the fire swaps the lead's slot for the track's.

## Lead state (2026-10-25 04:20 CDT, at the lead's first recycle)

- **Tracks A and B+C are running, nothing of theirs has landed.** A: 22 commits, final wrap-ledger and forks runs.
  B+C: 5 commits (`b3540f237` supervisor nudge, `c1cd2c92f` cc-decide ceiling/help/hints, `1a92a3bd8` supervisor-e2e
  stall threshold), waiting on its own suite runs. Both report by peer mail to the lead's pane (inbox 272), so a
  recycle of the lead's pane keeps the address. Read a track's state from its worktree
  (`git -C ~/Development/.worktrees/<wt> log origin/main..HEAD`) and transcript, never from a ping alone.
- **Track D's brief is `/tmp/fire-lkw-rule-text.txt`** (durable copy: `.claude/tmp/lkw/` in the `lead-idle-fix` worktree, gitignored) (track-specific head + the shared block `/tmp/lkw/common.txt`).
  Fire it only after A's and B+C's code is on trunk, with `--worktree lkw-rule-text --notify-back <lead pane>`,
  a goal in the same shape as A's, and an account with headroom (check `claude-accounts`). If /tmp was cleared,
  rebuild it from design §3.7, §3.8, §7.6 (operator-readout rows) and §7.7 plus the correction below.
- **Correction track D must carry (measured by B+C, 2026-10-24, step 0):** `codex exec -s read-only` does NOT confine
  reads (a canary under the real HOME was read) and `-s` overrides a permission profile; an outer `sandbox-exec`
  breaks codex. Only a temp `CODEX_HOME` whose `config.toml` sets `default_permissions` to a profile reading the
  export alone, with no `-s`, confines it. So the grant text names `~/.claude/scripts/xvendor-review.sh` and "a
  read-only permission profile confined to the export", never `codex exec -s read-only`; §7.7's token list changes to
  match.
- **Fire capacity:** the box sits at its 8-session active ceiling at 35-90 load/core; a refusal is a throttle (fire when
  `cc_sp_active` from `scripts/lib/spawn-presence.sh` reads ≤ 6 while the lead is idle). See the learning above.
- **Back-channel:** the originator name `agent-context-sync-134` no longer resolves; the live B13 lead is
  `agent-context-sync-271` (pinged at doc-written). Ping it again with the landed shas at the end; the originator's
  final `DONE` ping goes to whichever agentsync lead resolves then (`cc-notify --list | grep agent-context-sync`).
- **Wave 3 (lead):** after D lands: converge; design §7.8 items 1-5 by content; §8.4 records (two class-A packets,
  `cc-backlog needs` for the xvendor-review allow rule); print `git ls-tree origin/main` for every changed file and
  the tracks' red/green/mutant receipts (from their commit bodies: `git log --format=%B origin/main`); then Track E.

## Wave 3 — integration (DONE 2026-10-25)

- Deployed by content (design §7.8): the three instruction copies equal trunk (`diff -q`/`cmp`), one "Standing operator
  grants" section deployed, every new hook/lib/script link resolves into the live checkout byte-identical, the live
  checkout contains `14efdf0a3`, `scripts/deploy-parity-assert.sh` rc 0. All 39 changed files present on
  `origin/main`, live checkout diff-empty on them.
- Live read on the B13 session (`666022fd`): `RUNG=🔧 LOOP_OPEN=1 SCOPE_UNGATED=1` — its open loop now reads as
  unfinished work instead of a valid Blocked close.
- Lead-run receipts after the reboot (load ≈3/core): tests/lead-keeps-working-rules.bats against the pre-change text
  (`d197e9df5`) 1..15 with 11 not ok (6, 8, 14, 15 are labelled preservation/ratchet guards with mutants), on trunk
  1..15 all ok; tests/scope-floor.bats 1..31 ok; tests/xvendor-review.bats 1..23 ok.
- Records: class A `fb8c1c275bb1` (standing cross-vendor grant) and `1b4361a6ca89` (ruling `d610f8473106`
  implemented), both actioned with shas. The design's allow-rule backlog step was dropped: B+C's live review run
  executed unattended in auto mode, so no settings change is needed.
- Track B+C's operator step (`499e02a7dcc5`, "type /goal clear in pane 303") was resolved by the lead's ruling to that
  session, not by the operator.
- Learnings: (1) a goal written for a fired track must not demand that every test be red pre-change when the design
  itself specifies guard tests; it stranded B+C's session until the lead ruled. (2) On a box at 40-90 load/core the
  fire capacity gate and kitty remote control both stall; an in-process Workflow is the pane-free fallback for a
  code track, with a fresh-context reviewer slot standing in for the session's own review.

## Definition of done (per track)

Each track's done: every file its design §8.1 row names is changed as §3 specifies; every new check has a bats test
that is RED on `origin/main`'s subject and green on the change (plus one mutant per new guard), with the receipts in
the commit body; landed through the project-local `/ship`; converged; `git ls-tree origin/main -- <paths>` printed.

The lead's done (Wave 3): design §7.8's deployed-copy checks pass by content; §8.4's two class-A records and the one
`cc-backlog needs` step are filed; the B13 lead and the originator are pinged.
