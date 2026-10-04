# Lens: as-specified vs as-built vs live (2026-10-04)

Auditor: one of nine. Read-only on everything except this file. Paths are relative to
`/Users/chrisren/Development/.worktrees/wt-cc-024434-55635` unless absolute. Shared checkout
`~/Development/claude-infrastructure` = `main` at `13b27133f`, 0 behind `origin/main`
(`git rev-list --count HEAD..origin/main` => 0), so the live symlink farm runs trunk code.

Number labels: **measured** (a command I ran this session), **asserted** (a doc or record says
so and I could not re-run it without spending vendor quota), **code-read** (a fact read from source).

## 0. Live state receipts

| Fact | Receipt | Label |
|---|---|---|
| Research block registered, matcher `*` | `~/.claude/settings.json:862-868` (`"matcher": "*"`, `research-block.sh`, timeout 5) | measured |
| Router hook timeout 10 s | `~/.claude/settings.json:976-977` | measured |
| All four account dirs share that settings file | `~/.claude-{next,secondary,tertiary,quaternary}/settings.json -> ~/.claude/settings.json` (readlink) | measured |
| Migration 0050 applied | `~/.claude/autonomy/migrations/applied/0050-research-block-registration.json` exists | measured |
| Migration 0051 applied, 5 jobs loaded | `applied/0051-research-jobs.json`; `launchctl list \| grep research` => 5 labels, last exit 0 | measured |
| The jobs run and do nothing | `~/.claude/logs/research-sweep.out.log` => `job sweep: no program in certifying\|certified` (hourly, last 2026-10-04 03:07); freshness/triage/drift same; market (weekly Mon 08:00) has not fired yet | measured |
| Exemption text live | `grep -c 'Active research program exemption'` => `~/.claude/CLAUDE.md:1`, `~/.claude/rules/10-session-close.md:4`, `~/.claude/CLAUDE.full.md:4`; account CLAUDE.md and rules are symlinks to these | measured |
| Registry | `~/.claude/autonomy/research/programs.json`: one program `truememory-2-0`, state `registered`, `cwd_roots` = [`.../tm2-plan`] only | measured |
| Pilot progress | tm2 records: stages 1-3 ended, stage 4 started 2026-10-04T02:41Z (`budget.json`); 119 decision rows, 398 hole rows, 8 apply-at-build rows; frame signed twice (`signoff.jsonl`, 2026-10-02 and 2026-10-03, `claude_ancestor:false`) | measured |
| Verdict | `cc-research verdict truememory-2-0` => `registered; not certified. Certification rounds counted: 0` | measured |
| Block hook latency | 3 runs of `~/.claude/hooks/research-block.sh` on a tm2 cwd, Agent tool => `real 0.15/0.14/0.14 s` at load ~83, rc 0, no output (allows: registered) | measured |
| Row 15 decision | `~/.claude/autonomy/decisions/4bf73c4e55d5.json`: class C, **open** since 2026-10-02T00:44Z, conviction 65, receipt = the plan doc (no measurement file) | measured (the packet); the fallback rates inside it are asserted |

## 1. §8 build list, item by item

| # | Built? where | Live? | Gap vs REPORT |
|---|---|---|---|
| 1 | evidence dir exists | n/a | none |
| 2 | `agents/deep-research.md:187`, `agents/research-decomposition-critic.md:38` "zero is a valid answer" | symlinked | none found |
| 3 | rules (live copies above); `hooks/completion-assert.sh:1088` `_ca_rp_active`, keyed on registry cwd (`scripts/lib/research-program.sh`) | yes | keyed on `cwd_roots`, which holds ONE root (`lib/gate.py:114-118` `cwd_roots=[a.root]`); no verb adds a root. See finding F2 |
| 4 | `scripts/lib/operator_sign.py`, `bin/cc-signoff research:` | yes (signoff.jsonl rows carry provenance) | none found |
| 5 | `hooks/research-precognition-nudge.sh:27-45`, `scripts/research-kit/router.py` | registered, but routes only in `certifying\|certified` (`router.py:72`, nudge `:43`) | classifier fails gate row 15 (F1) |
| 6 | `hooks/research-block.sh`, `router.py cmd_tool:514-600`, `completion-assert.sh:264-305` ARM R | registered (0050 applied) | fallback label `unavailable` turns off the all-tool deny AND the relay check (F1); relay check capped at 2 per session (`completion-assert.sh:295`) |
| 7 | `scripts/research-kit/` (all seven + router, heldout, intake) | symlinked under `~/.claude/scripts/research-kit/` | certificate render static (F3); no per-area take-back test (F6) |
| 8 | `skills/research-program/`, `commands/research-program.md`, `intake.py` | yes | intake accepts any profile; calibrated decision 4 "lite for every size" not surfaced; pilot runs `standard` (F8) |
| 9 | `bin/cc-research` over `lib/cli*.py` | `~/.claude/bin/cc-research` symlink | none found at this depth |
| 10 | `lib/cli_probe.py` | yes | none found |
| 11 | `scripts/research-kit/workflows/*.workflow.js`, `lib/cli_cert.py` | yes | trial cwd orchestrated, not enforced (stated in its header) |
| 12 | `lib/cli_jobs.py`, `jobs/research-job.sh`, 5 plists | loaded | every job filters to `ACTIVE = ("certifying","certified")` (`cli_jobs.py:44`, `:74-79`), so the due-date sweep does not run during stage 4, when class-B defaults fall due (F4) |
| 13 | `scripts/wrap-ledger.sh:183-189`, `operator-readout.sh:608,1836`, `commands/are-we-done.md:21,60`, `handoff-fire.sh:11797-11863` | live (`wrap-ledger.sh --machine` prints `SCOPE=`, `RESEARCH_PROGRAM=`) | `--requires-gate` only labels the fired session's FIRST prompt; it does not register that worktree (F2) |
| 14 | `docs/research/research-calibration/REPORT.md`, `.jsonl` (16 rows) | n/a | measured the stop rule cannot fire (F5) |
| 15 | `docs/research/research-reference-class.jsonl`, `cli_refclass.py` | yes | certificate prints a hard-coded "Calibration: no programs observed yet (uncalibrated)" (`lib/gate_cert.py:228`) whatever the log holds |

## 2. §10 open items (17), item by item

| # | Status as built | Receipt |
|---|---|---|
| 1 certifying state, block on at freeze | built | `router.py:72` `BLOCKING_STATES`; `gate_cert.py` freeze; suites research-kit-registry, research-router |
| 2 no single-active fallback | built | nudge `:15-17,38-39`; `research-program.sh:22-26` |
| 3 classifier-unavailable distinct, kill switch | built as specified — and that is the problem: see F1 | `router.py:70,74,296-301,333-372,564` |
| 4 sweep applies class-B defaults, converts class-C | built (`lib/gate_sweep.py:1-20`), scheduled only for certifying/certified | F4 |
| 5 1-4% wording | text fixed in §1 | REPORT.md:35 |
| 6 per-area take-back vs total-only sim | **open**: REPORT.md:899 still says "the total and per area"; `grep -rn area scripts/research-kit/lib/*.py estimate.py` => nothing | F6 |
| 7 row 11 method-created reason classes | built | `lib/gate_rows_b.py:29-31` (`depth-cap`, `stage-budget-exhausted`, `stub-validated`), rendered FILED |
| 8 allow route for contract-listed activities | built | `lib/activities.py:22`, `router.py` `[activity:<id>]` |
| 9 frame-omission row default after cap | built | `gate_sweep.py` step 3; `gate_requires.py` reads live known rows |
| 10 exemption keyed on registry | built (option 1) | but single root: F2 |
| 11 row 15 floor on other-labels, fallback ceiling | built | `heldout.py:50-56` (`MIN_OTHER_CORRECT 0.90`, `MAX_FALLBACK 0.10`) |
| 12 stratified held-out frame | built | `heldout.py:37-38`; but strata tiny: plan reports recall `14/14 · 3/3 · 1/1` (asserted, RESEARCH_PROGRAM_BUILD.md:174) |
| 13 sealed set | built | `~/.claude/autonomy/research/router-heldout/sealed.enc` (60,495 B, 0600), tuning.jsonl beside it |
| 14 §7 range 0.7-2.7, §1 "6-10 in 10" | **open**: REPORT.md:1104 still "0.7–1.6", REPORT.md:35 still "6–9 in 10" | grep |
| 15 dedupe "20 of 73" | **open**: REPORT.md:91 and :1131 still "20 (27%)" | grep |
| 16 numeric front-end-return trigger | **open**: REPORT.md:966 still "well above"; no code implements a front-end return at all (`grep -rn 'design.point\|front.end' lib/*.py` => nothing) | grep |
| 17 caps in code | built (`cc-research budget`, `kit.CAPS`) | plan :280-281 |

Items 6, 14, 15 and 16 are open in the frozen text. The build plan's frozen scope line says "with every §10 open
item closed by a failing planted-input test" (RESEARCH_PROGRAM_BUILD.md:8-10) and marks every wave DONE; four
document items are not closed, and none of them has a test.

## 3. Gate row 15, confirmed

- Row 15 = `heldout.evaluate(CC_RESEARCH_ROUTER)` (`lib/gate_rows_b.py:343-353`). `gate.sh run` writes a certificate
  and sets `certified` only when every row is PASS or FILED (`lib/gate.py:139-151`). No waiver path
  (`grep -n 'waive\|SKIP' gate.py gate_rows_b.py` => nothing). **So while row 15 fails, no program on this machine can
  be certified, and `handoff-fire.sh --requires-gate` refuses every build wave** (`gate_requires.py`: refuses unless
  `certified`). code-read.
- Its reading (asserted, plan :172-177, packet 4bf73c4e55d5): fallback 0.96 at load ~295, 0.51 at load ~45-80,
  6 s limit; `other` correct-label 0.12 then 0.62; cause: cold `claude -p` startup 2-5 s. I did not re-run it:
  `heldout.evaluate` calls the live classifier once per sealed item (~69 haiku calls), which spends vendor quota.
  No stored output of that reading exists (`git show --stat 157fd5ca8` touches only the plan doc).
- Today's load: `uptime` => 68-83 (10 cores) throughout this session, i.e. the high-fallback regime.
- The fix decision is open 2 days with no default and no deadline (packet fields empty).
- **What it means for live protection (code-read).** §4.1 specifies: fallback => treated as completeness => every
  tool but the certificate read is denied. As built (§10 item 3's change), fallback => label `unavailable`
  (`router.py:358-360`) => only research verbs denied (`router.py:536-570`, `:563`), other tools allowed, and the Stop relay
  check returns 0 unless the label is in `RELAYED` (`router.py:638-641`). The model gets only an advisory
  "If the prompt asks whether the work is complete, relay these lines verbatim" (`router.py:296-301`).
  At the measured 51-96% fallback, that advisory is the only layer on most re-asks.
- **The evaluator credits what the live router does not do.** `heldout.evaluate` scores a fallback as
  `completeness` (`heldout.py:217-219`), so recall in the completeness strata is satisfied by timeouts; live, a
  timeout is `unavailable`, which is not relayed and not Stop-checked. Even at a fallback rate under the 0.10 ceiling,
  row 15's recall overstates the enforced protection by up to that rate.
- **The classifier model's floor.** `~/.claude/model-config.yaml:140` `haiku_latest: claude-haiku-4-5  # retires NOT
  SOONER than 2026-10-15`; the classifier resolves it at call time (`router.py:205-221`). After retirement every call
  errors => 100% `unavailable`, silently except the after-3-in-a-row systemMessage (`router.py:365`). asserted (config
  comment).

## 4. Findings detail

F1 (critical) — re-ask protection is mostly not in force when it is on, and off in every state the pilot is in now.
See §3. Also: router and block engage only in `certifying|certified` (`router.py:72`); tm2 is `registered`, so
today every completeness ask in tm2-plan gets no routing, no block, no relay check; the only layer is the
standing-rule exemption text plus completion-assert's D4 abstain. The relay check's matcher is lexical
(`router.py:580-600` ITEM/TOKENS regexes, plus a >3-extra-lines count): a one-line prose addition with no path,
id, backticks or the listed phrases ("Also worth adding retry handling to sync.") passes. code-read.

F2 (major) — program identity is one directory. `cwd_roots=[a.root]` (`gate.py:116`), no add-root verb. Measured:
`research-program.sh resolve` => `truememory-2-0 registered` for tm2-plan, empty for tm2-plan-replan (critique round
29 commit 2026-10-02), tm2-slice, tm2-k3, tm2-base. Build waves are S-locus dispatched sessions in their own
worktrees; `--requires-gate` adds only a marker to the first prompt (`handoff-fire.sh:13860-13863`), which resolves
by slug for that one prompt (`research-program.sh:149-166`, per-prompt). So the exemption ("from intake through
build") and the block do not apply in build-wave sessions: the standing F1 "nothing left on the table" rule runs
there, which is the generator of "one more thing" during build.

F3 (major) — the relayed certificate cannot change after signoff. `lines_for` (`gate_cert.py:190-230`) renders the
snapshot taken at `write_certificate`, with literals `take-backs 0` (:213), "Calibration: no programs observed yet
(uncalibrated)" (:228) and "this answer unchanged since <issued>". Only `gate.sh run` writes a certificate
(`gate.py:150`). §4.3 specifies "After signoff: N material change(s)", "Scheduled checks … last freshness run",
"Built 0/58 · Live –"; none is rendered. §4.4's three events (escape, freshness flip, accepted change) therefore
never reach the lines the model is forced to relay, and the relay check demands a "no" cite one of them.

F4 (major) — the due-date sweep skips the stage where defaults fall due. `cli_jobs.py:44,74-79`. Live: seven tm2
class-B packets due 2026-10-06T04:00Z (`b44e73a345c2`, `57518ae1b3f9`, `eced8121c3c7`, `0118907dca69`,
`8a7a95962f1e`, `e22f4a9044b1`, `c81e1d1859b9`), program `registered`. The hourly sweep will log "no program in
certifying|certified" past their deadlines; applying them is a hand step nobody is scheduled to run.

F5 (major, irreducible as measured) — the stop rule cannot fire at measured inputs (calibration REPORT §1: false
material ~1.1 per read vs 0.01 assumed; every profile to its hard cap). So "3 quiet rounds" is unreachable; the
certificate will always read "stopped at the round cap", and the forecast, not a quiet streak, is the honest promise.

F6 (minor) — §10 items 6, 14, 15, 16 open in the frozen text, no per-area take-back code, no front-end-return code.

F7 (minor) — apply-at-build list has no contract: absent from `scripts/research-kit/RECORDS.md` (grep -i apply =>
nothing), no writer verb, no gate row, no consumer at build start; tm2 writes `apply-at-build.jsonl` by hand
(8 rows, `status: open`). It is the sink the exemption sends every refinement to.

F8 (minor) — intake accepts any `--profile` (`intake.py:436`), with no reference to calibrated decision 4 (REPORT §9
row 4: lite for every size; standard "not supported at measured inputs"). The pilot frame says `standard`
(`frame.json`, `intake-answers.md:43`, operator-answered).

F9 (minor) — research index stale: `research-index.py --check` => "18 entry(ies) missing".

Strength S1 — the wave-1/2 surface is real and live: hooks registered in the one shared settings file, both
migrations applied, jobs loaded, rules live, signing provenance recorded with `claude_ancestor:false`, block hook
costs 0.15 s at load 83, and a real pilot is running on it (4 stages, 119 decision rows).

## 5. Bats suites

The first pass this session was a cc-bats DEFERRAL for all 30 suites (`cc-bats: REFUSED — 2 concurrent bats
execution root(s) … AND 1-min load/core at or above 2.0`, no plan line, 0 ok / 0 not ok, so no verdict). A retry
loop through cc-bats (never bypassed) was admitted after 52 tries (~26 min), then ran all 30 in this worktree
(`bats --tap tests/<suite>.bats`, TAP in `/tmp/lens-asbuilt-bats/`). measured:

| suite | plan | ok | not ok |
|---|---|---|---|
| research-router | 1..23 | 23 | 0 |
| research-relay-check | 1..15 | 15 | 0 |
| research-router-heldout | 1..9 | 9 | 0 |
| research-kit-registry | 1..5 | 5 | 0 |
| research-program-lib | 1..8 | 8 | 0 |
| research-program-exemption-rules | 1..4 | 4 | 0 |
| migration-0050-research-block | 1..6 | 6 | 0 |
| research-jobs | 1..12 | 12 | 0 |
| research-kit-sweep | 1..13 | 13 | 0 |
| research-kit-requires | 1..17 | 17 | 0 |
| research-kit-gate | 1..44 | 44 | 0 |
| operator-sign | 1..13 | 13 | 0 |
| cc-research-core | 1..22 | 22 | 0 |
| cc-research-records | 1..10 | 10 | 0 |
| cc-research-cert | 1..17 | 17 | 0 |
| cc-research-probe | 1..11 | 11 | 0 |
| cc-research-refclass | 1..8 | 8 | 0 |
| research-kit-heldout | 1..6 | 6 | 0 |
| research-kit-courier | 1..15 | 15 | 0 |
| research-kit-round | 1..15 | 15 | 0 |
| research-kit-seed | 1..9 | 9 | 0 |
| research-kit-estimate | 1..6 | 6 | 0 |
| research-kit-index | 1..3 | 3 | 0 |
| research-kit-probe | 1..10 | 10 | 0 |
| research-program-intake | 1..15 | 15 | 0 |
| research-program-briefs | 1..9 | 9 | 0 |
| research-zero-allowed-prompts | 1..4 | 4 | 0 |
| wrap-ledger-research | 1..11 | 11 | 0 |
| operator-readout-research | 1..9 | 9 | 0 |
| self-certifying-close | 1..23 | 23 | 0 |
| **total, 30 suites** | | **372** | **0** |

What green means here: every suite is fixture-driven. The router suites drive the classifier through the
`CC_RESEARCH_CLASSIFIER` test seam (`router.py:44`, `:225-227`), so **no suite exercises the live haiku classifier or
its latency**: 372/372 green and row 15 FAIL are consistent. The suites prove the decision tables; they do not prove
the protection is in force.

## 6. Context that bears on whether the goal is attainable (measured from the decision store)

- `5b0e951268c4` (2026-09-30): TrueMemory 2.0 critique rounds 1-9 found 37, 26, 22, 17, 14, 22, 17, 11, 14 verified
  gaps: flat at 11-14.
- `db91216410a8` (2026-10-01, vetoed): 15 rounds, ~300 fixes, still 8-14 distinct gaps a round.
- `fcf2361dafcb` (2026-10-01, vetoed): 17 rounds, ~370 fixes, plan 2,165 -> 3,231 lines, still 8-14 a round.
- `tm2-plan-replan` HEAD `e38fd6984` (2026-10-02): "critique round 29 record (21 verified, 13 distinct)".
Together with the calibration (stop rule never fires, F5), this is direct in-environment evidence that more desk
review of one frozen plan does not converge to zero: each round's fixes create the next round's holes. The literal
goal ("never 'one more thing'") is attainable only as a bounded promise: 100% of a signed frame, plus a printed,
counted forecast of after-signoff changes, enforced at the moment of the re-ask. That is what the method claims;
the enforcement half is what is not in force today (F1-F4).
