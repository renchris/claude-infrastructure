---
status: in-progress
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
| 2 | **S** | D rule and machine text (6) | fired after A and C land, so no loaded sentence names a verb that is not yet on trunk |
| 3 | **L** | integration: B13 replay suites, red/green receipts, converge check, deployed-copy content check, class-A records, pings | one line of why: it is synthesis of the tracks' receipts, small output, and the goal's proof must surface in the lead's transcript |
| 4 | **S** | E held-out instruction re-gate (9) | operator ruled 2026-10-04 to run it at the next slim edit (`docs/plans/INSTRUCTION_BUDGET.md:127`); it measures the converged slim text |

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
| A scope floor | `lkw-scope-floor` | fired 2026-10-24 (next3, pane 297) | |
| B+C subject nudge + decide/grant code | `lkw-nudge-decide` | **DONE 2026-10-25**, landed + converged, 15 paths content-verified by the lead | `476870a58` nudge (test T43) · `65e7af8df` xvendor-review.sh · `cadfaff50` cc-decide `--help`/`--ceiling`/hints + cc-memory-search `--decisions` + anti-deference + gate_sweep `--ceiling program` · `ea8d879cb` operator-readout setup · `94c9b550d` e2e STALL_S 5→60 |

B+C receipts (its commit bodies hold the detail): RED on the pre-change subject — T43 28/39, xvendor 23/23, cc-decide
new 10/12 (2 negative gates green by design), cc-memory-search 2/2, research-kit-gate 1/1, anti-deference 1/2;
mutants — supervisor 20/20, xvendor 6/6, decide 13/13 red; GREEN — lead-supervisor 1..12, xvendor-review 1..23,
cc-decide 1..88, cc-memory-search 1..21, plus 10 neighbour suites. Live Codex smoke (meter 0%, 3,395 tokens): the
export is readable and a real-HOME file reads "Operation not permitted". Design correction: tests/operator-readout.bats
did NOT already unset the session ids (4 class-C cases went red until `ea8d879cb`). Trunk red not ours:
tests/headless-address-consumers.bats test 9 (red on `3d6d8f85a` too).
| D rule text | `lkw-rule-text` | pending (fires after A, B+C) | |
| E re-gate | `lkw-regate` | pending (fires after D) | |

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

## Definition of done (per track)

Each track's done: every file its design §8.1 row names is changed as §3 specifies; every new check has a bats test
that is RED on `origin/main`'s subject and green on the change (plus one mutant per new guard), with the receipts in
the commit body; landed through the project-local `/ship`; converged; `git ls-tree origin/main -- <paths>` printed.

The lead's done (Wave 3): design §7.8's deployed-copy checks pass by content; §8.4's two class-A records and the one
`cc-backlog needs` step are filed; the B13 lead and the originator are pinged.
