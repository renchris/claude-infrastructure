---
name: research-program
description: "Run a no-take-backs research program (method v1.1): intake, signed frame, censuses, contact, decisions, freeze, blind vendor-diverse certification rounds, gate and certificate, over the hand-run kit in scripts/research-kit/."
---

# research-program — the no-take-backs upfront research method, as one protocol

The method is `docs/research/upfront-research-exhaustion-2026-09-30/REPORT.md` (version 1.1, frozen by
the operator's ruling of 2026-10-01; it changes only from measured results, §9 decision 8). This skill
carries the protocol so a session does not reinvent it. Every number, cap and gate row it names lives
in code under `scripts/research-kit/` (records contract: `scripts/research-kit/RECORDS.md`); where this
file and the code disagree, the code wins and this file is the bug.

Updated 2026-10-04 (v1.2): ruling `1bf69e5c1775` overrides the freeze for four named changes (REPORT §9,
"Ruled 2026-10-04"). Two of them change this walk: Stages 3 and 5 end on yield, with decisions below 90
tagged by what blocks them (§12), and Stage 9 certifies the built artifact before "done" (§11). Both
apply only to a frame stamped `method_version` 1.2, which `intake.py init` writes; a frame without the
stamp reads as 1.1 and keeps the eight-stage walk.

**Use it** when the operator starts a greenfield effort and wants research that ends: "100.00/100.00",
"no take-backs", "research everything before we build". **Do not use it** for ordinary research,
for a case-sized question answerable in a day, or when the operator declines either §3.1 ruling.

## The rails (they hold in every stage)

- **The registry is gate.sh's.** `scripts/research-kit/gate.sh` is the only writer of
  `~/.claude/autonomy/research/programs.json`. Never edit it, never write a state by hand.
- **Signatures are the operator's.** Frame, certificate, the one extra round set, reopen, and vetoes go
  only through `cc-signoff`, in the operator's own terminal. It refuses under an agent, and a signature
  an agent wrote reads as VOID to the gate. You print the command; you never run it:
  - `cc-signoff research:<slug>/frame` — after the contract page and a clean frame lint;
  - `cc-signoff research:<slug>/cert` — after `gate.sh run` passes;
  - `cc-signoff research:<slug>/extra-round` — the one extra round set per program (§6.4);
  - `cc-signoff research:<slug>/reopen` — the only way back from `certified` (§5.1);
  - `cc-signoff research:<slug>/veto/<DECISION-ID>` — veto an overrun or below-profile default;
  - `cc-signoff research:<slug>/extend-decision/<DECISION-ID>` — v1.2: the one priced research
    extension on a decision tagged research, at most once per decision (§12.3).
  - `cc-signoff research:<slug>/implementation` — v1.2 (§11, added 2026-10-05): the implementation
    signoff, after `gate.sh built-run`; it pins the newest built certificate by path and hash.
- **Program packets only through `gate.sh file-packet`**, never a bare `cc-decide open`: it adds the
  deliverable repo as `--project` and, for class B, `--default-effect no-change`, and gate row 12 fails
  any program packet without them (§10 item 4). Run `gate.sh sweep --program <slug>` daily in the pilot.
- **The lead writes tallies, never convictions.** `kit.conviction` derives conviction from the stored
  tally (§3.5). A decision record with a typed `conviction` is ignored.
- **Zero is a valid answer** everywhere after the frame critique. Never brief a reviewer, rater or
  critic with a quota.
- **Inside an active program the standing-rule exemption applies** (§3.1 ruling 2, wave A1): refinements
  go to the apply-at-build list, a completeness question is answered by relaying
  `gate.sh --render --program <slug>`, and new ideas park in the next version.

## Before intake: restore every vendor lane

Certification needs three vendor families (Anthropic, OpenAI, Google). Run
`scripts/research-kit/probe-run.sh doctor` first, then `scripts/research-kit/courier.sh preflight`.
Google's lane is the Antigravity CLI, `agy` (the `gemini` CLI is retired for individual accounts). If
its preflight fails on authentication, that is one operator step: run `agy` once in their own terminal
and finish the Google sign-in. Park it before anything else, because the preflight fails on a dead lane.

## Stage 1 — intake and the signed frame (§3.2)

1. **Index, then mine.** `intake.py init` checks `docs/research/INDEX.jsonl` (`research-index.py --check`)
   and says if it is stale. Then a read-only fan-out writes `docs/research/<slug>/intake-mined.md`, every
   claim quoted with a receipt: prior research via the index, plans here and in sibling repos,
   `cc-memory-search`, transcripts including subagent files, `msg` for each named counterparty,
   `cc-decide list --all`, the backlog and mission board, and house rules that act as acceptance. Find
   the topic's owner and require a positive sign of life before a second plan starts.
2. **Register.**
   ```
   scripts/research-kit/intake.py init --program <slug> --root <deliverable repo, absolute> \
     --profile lite --deliverable "<one sentence with numbers>" --intent "<the operator's words>" \
     [--alias "<name the operator uses>"]
   ```
   It registers through `gate.sh register`, writes the frame skeleton (all 33 checklist rows unmapped,
   the three historical question frames unmapped), and starts the stage-1 budget clock. Default profile:
   lite for case-sized work, standard for medium; full only after the calibration run (§9 decision 4).
   Updated 2026-10-04 (v1.2): lite for every size. At measured inputs a wider profile leaves no fewer
   holes after signoff than lite (estimate.py reads the measured set by default), so `intake.py init`
   warns on standard or full with the two simulated figures. Take a wider profile only on the operator's
   word, and record it.
3. **The two rulings come first.** Show them with `intake.py ruling --show`, then record the operator's
   answer verbatim:
   ```
   scripts/research-kit/intake.py ruling --program <slug> --which definition-of-complete --adopt --quote "<words>"
   scripts/research-kit/intake.py ruling --program <slug> --which exemption --adopt --quote "<words>"
   ```
   A `--decline` closes the program: it makes no no-take-backs claim, and ordinary research runs instead.
4. **The interview: one sitting, the 12 questions of §3.2 step 2, each pre-filled from the mining**; the
   operator confirms or corrects. Question 10 must be a number:
   `intake.py set --program <slug> --escape-cost-days N` (refuses "infinite"; start at 3, §9 decision 5).
   Record the mean upstream release gap (`--release-gap-days`) and, if known, the measured research time
   for this project type (`--reference-days`, the §6.3 check).
5. **Fill the frame** (`frame.json`, `acceptance.json`, `decisions.jsonl`, `premises.jsonl`,
   `sources.jsonl`, shapes in RECORDS.md). Turn every superlative into a number with a measured ceiling
   and a negative branch; the lint refuses `perfect|100th|maximal|best|exhaustive|absolute|flawless`
   without a number. Every decision's options include `do-nothing` and `use-what-exists`. Keep 7–10
   decision groups at the top level.
6. **Map the checklist** (`checklist.jsonl` beside this file, FAC-01..FAC-33): each row to a frame row or
   not-applicable with a reason, and each historical frame to a certificate axis or excluded in the
   operator's words:
   ```
   scripts/research-kit/intake.py map --program <slug> --fac FAC-06 --row K-03
   scripts/research-kit/intake.py map --program <slug> --fac FAC-24 --na "no live subject"
   scripts/research-kit/intake.py map --program <slug> --frame "no loose ends" --excluded "<operator words>"
   ```
7. **Vendor preflight, then the frame critique.** `scripts/research-kit/courier.sh preflight --program <slug>`
   (one real call per vendor, model ids recorded). Then exactly 2 frame-critique rounds of 6 blind
   reviewers across at least 3 vendors (`round.sh --kind frame-critique`), with
   `briefs/reviewer.md` scoped to the frame rows. This is the only open-ended "what is missing?" in the
   whole protocol.
8. **Contract page.** `scripts/research-kit/intake.py contract-page --program <slug>` refuses until both
   rulings, the escape cost and a strictly earlier, all-live preflight exist (a dead lane exits 3: pause
   on the operator step, class-B default "continue on two vendors" after 48 h). It writes `CONTRACT.md`,
   pins the responding model ids and the reviewer effort (`reviewer_effort`: Opus xhigh, Fable high,
   OpenAI xhigh), and stores the page's hash in `frame.json`, so the frame signature covers the page.
9. **Lint, then the operator signs.** `intake.py lint --program <slug>` is gate row 1 without the
   signature; `intake.py status --program <slug>` lists what is left. When both are clean, hand the
   operator `cc-signoff research:<slug>/frame`.

## Stages 2–6 — censuses, contact, decisions, acceptance, freeze (§3.3–§3.7)

| Stage | Tool | By hand in the pilot |
|---|---|---|
| 2. Censuses, premises, sources | `probe-run.sh run` records each command; `courier.sh` runs the census reviewer once per population | the second census method, by a different agent; the grids |
| 3. Contact | `probe-run.sh doctor`, then each probe with its negative control | the scheduler-started launchd run under `/bin/bash` 3.2.57 |
| 4. Decisions | decision records with tallies, checked by `gate.sh`; packets via `gate.sh file-packet` | the tally (never a conviction); the frame expansion after each level of rulings |
| 5. Acceptance and skeleton | `probe-run.sh` over each row's known-bad and known-good fixtures | the contact skeleton as build wave 0; the operator's reaction checkpoint |
| 6. Synthesis and freeze | `gate.sh freeze --program <slug>` (registry → `certifying`, the research block turns on) | the integrator, one fresh whole read, the sibling advisory lock |

## Stages 3 and 5 end on yield; decisions below 90 are tagged by what blocks them (§12, method v1.2)

Updated 2026-10-04 (v1.2). Under a 1.2 frame, contact (stage 3) and the build-to-learn skeleton (stage 5)
end on yield, not on the stage clock (§12.1):

- A **counted probe** is one recorded inside the stage that could fail; a probe that could not fail is
  ignored. A **find** is a counted probe the tool ties to a record it produced (a refuted premise, a hole,
  a counted change, a residual or a frame row): tie it with
  `cc-research yield find --program <slug> --probe <P-id> --ref <record id>`. A counted probe that exited
  nonzero with no such record still counts as a find. A **quiet probe** passed and produced no find.
- K is 3 (lite), 4 (standard), 5 (full). Yield is the finds among the last 2K counted probes divided by
  the agent-days those probes took; value of information is yield × `escape_cost_days` (research days
  saved per research day spent).
- The stage **continues** while the last K counted probes are not all quiet, or value of information is
  above 1. It **stops** when the last K are quiet and value of information is at most 1.
  `cc-research yield show --program <slug> --stage N` prints the verdict (exit 0 on stop or ceiling, 1 on
  continue); `cc-research budget end --program <slug> --stage N` refuses to end stage 3 or 5 while the
  rule says continue, and records the stop reason and its numbers when it ends.
- Hard ceilings stay (§6.5): the stage ends regardless at 4 × its stage budget in agent-days or
  60 counted probes, whichever comes first, printed "stopped at the ceiling", and the unworked cells are
  declared residuals (§3.6). The overrun packet at 1.5 × is unchanged; its default "proceed" now means
  keep probing while yield pays, up to the ceiling.

A decision below 90 carries a tag computed from its tally, never typed (§12.2): **research** (a
load-bearing premise is below its level and a probe could raise it, or the flip probe has not run),
**production** (every remaining gap is a residual premise whose reason is production traffic, a tenant
not held, or elapsed time) or **operator** (no factual premise, or every gap is the operator's eye, value
or a private fact). Only production and operator may be defaulted (class B) or carried (class C, set). A
decision tagged research gets more research, up to twice its intake timebox; at that ceiling it converts
as §3.5 says, printed "defaulted at the research ceiling". `cc-research menu` lists one priced extension
per research-tagged decision (§12.3): conviction now, premises below level, the highest conviction an
extension could reach, and its price of one more timebox. The operator buys it with
`cc-signoff research:<slug>/extend-decision/<DECISION-ID>`; it is quoted as a change to that decision's
conviction, never as a yield.

Stage 8 checks both: gate row 18 (yield stop) and row 19 (decision blockers), each PASS as "not
applicable" under a 1.1 frame. The contract page's ceiling already carries the yield ceiling (§12's price:
lite 5.25, standard 12 agent-days) and the Stage 9 budget.

## Stage 7 — certification (§3.8, §3.9)

- Seeds: a seed author from a vendor other than the lead's, briefed with `briefs/seed-author.md`, writes
  seed lines straight into `seed.py plant`. The lead never reads them.
- Rounds: `round.sh --kind certification --round K` fills four slot sets (Opus, frontier, OpenAI, Google)
  with the profile's strategies, every reviewer briefed with `briefs/reviewer.md` verbatim, at the
  frame's `reviewer_effort`; `check-round` voids a reviewer panel run at any other effort.
  `round.sh` refuses past `R_max` (§10 item 17).
- Each finding: a verifier (`briefs/verifier.md`), then raters (`briefs/rater.md`), launched through
  `courier.sh run --role verifier|rater` (never effort-pinned: their CLI's default). Rater 1 is non-Anthropic; rater 2 another vendor; rater 3 the
  third. Ratings follow `RUBRIC.md` and nothing else.
- Fix only material findings, only between rounds, only by integration; refinements go to the
  apply-at-build list. Frame omissions (clause g) go to the frame-delta cycle.
- Stop: `estimate.py forecast --program <slug>` says `dry` (K quiet rounds) or `cap`. The cap round is
  verification-only.
- Rehearsal and the relay test (20 trials, at least one from a pane outside the program's directory).

## Stage 8 — gate, certificate, signoff (§3.10)

`scripts/research-kit/gate.sh run --program <slug>` prints all 16 rows PASS/FAIL/FILED. Every row passes
or is FILED, the certificate is written and the registry goes to `certified`. Hand the operator
`cc-signoff research:<slug>/cert`. From then on a completeness or pushback question is answered by
relaying `gate.sh --render --program <slug>` unchanged, and nothing else.

Updated 2026-10-04 (v1.2): under a 1.2 frame the research gate prints 19 rows, rows 18 and 19 from §12,
and the research certificate splits its forecast before and after implementation signoff, the
build-findable share (0.585, "share assumed") before it (§11).

Build waves fire only through `scripts/handoff-fire.sh --requires-gate <slug> --gate-wave <W>` (§3.10
"Carried rows at build time"). It refuses before any side effect while the registry is not `certified`,
the newest certificate has a FAIL row, a reopen is signed after it, or the wave's closure holds an
unresolved class-C row, a carried set it does not own the narrowing probe of, an open frame-omission
known row, or a wave the sweep descoped. `gate.sh requires --program <slug> --wave <W>` prints the same
verdict without firing. An admitted fire carries the `--requires-gate` work-order marker in its brief.

## Stage 9 — certify the built artifact (§11, method v1.2)

Updated 2026-10-04 (v1.2). Stages 1–8 certify the plan; Stage 9 certifies what was built from it, after
the last build wave and before the operator signs the implementation. It runs only under a 1.2 frame.
The registry goes `certified → build-certifying → build-certified → closed`; both build states are active
for the §3.1 exemption and the §4.2 research block, and the scheduled jobs still visit the program.

1. **Freeze the built snapshot.** `scripts/research-kit/gate.sh built-freeze --program <slug> --artifact
   <abs dir> [--wave W ...]` pins the artifact's HEAD in `built/freeze.json` and sets `build-certifying`.
   Row 20 later checks that the research certificate is signed with no FAIL row and no reopen after it,
   every build wave the frame names is done, and the snapshot equals the artifact's HEAD and the one the
   last counted built round examined.
2. **The four code-native instruments** (`cc-research built …`; records in RECORDS.md "Stage 9 records"):
   - **A failing-test repro for every finding.** `cc-research built finding add --program <slug> --source
     round|mutation|contact|soak --claim "<claim>" --severity material --test-cmd "<cmd>"`. The tool runs
     the command on the snapshot; a finding whose command does not fail is `rejected-no-repro`, counted
     and never material. After the fix, `cc-research built finding fix --program <slug> --id BF-n` re-runs
     it and exits 1 while it still fails (row 21).
   - **Mutation testing of the acceptance harness.** `cc-research built mutate --program <slug>` applies
     each sealed mutant to a copy of the artifact and runs the harness against it. A survivor is a finding
     whose repro is the harness row that kills it, re-run once per survivor. Row 22 needs at least 10
     mutants and one per acceptance row, an unmutated baseline that passed, and 0 survivors; an equivalent
     mutant carries `--equivalent M-n --reason "<why>" --rater <vendor>`. The kill rate is this stage's
     seed catch rate.
   - **An as-built contact re-run.** `cc-research built contact --program <slug> --target <probe id|row id>
     (--negative-control CMD | --no-negative-control REASON)` re-runs every Stage 3 and 5 probe of kind
     skeleton, handed command, dry-run deploy or fault injection, and every acceptance row, with an empty
     `HOME`, `PATH=/usr/bin:/bin` and `/bin/bash` 3.2. The tool records the environment (row 23).
   - **A soak across time boundaries.** `cc-research built soak sample --program <slug>` runs every
     acceptance check once, the as-built way. The scheduled job `cc-research job soak` samples every
     `build-certifying` program hourly once the operator has loaded it (migration 0058). After a fix,
     `cc-research built soak restart --program <slug> --finding BF-n`, at most twice. Row 24 needs at least
     24 hours and 24 samples after the last fix, 0 failing, and every named boundary (by default the hour,
     UTC midnight and local midnight; `frame.json` `soak_boundaries`) crossed, or declared an elapsed-time
     residual with an owner and a date.
3. **Built rounds.** `scripts/research-kit/round.sh run --program <slug> --kind built --round N --plan
   <seeded plan> --brief skills/research-program/briefs/built-reviewer.md`: the same reviewers, vendors,
   strategies and re-run caps as Stage 7, reading the built snapshot beside the plan; this stage's seeds
   are the harness mutants. Each finding goes to a verifier (`briefs/built-verifier.md`: it runs the
   finding's `test_cmd` the as-built way), then raters (`briefs/built-rater.md`: RUBRIC.md, plus "no
   failing test, never material"), through `courier.sh run --role verifier|rater`. Each material finding
   is recorded with `built finding add`. The cap is 3 (lite), 4 (standard), 6 (full) built rounds, and
   the cap round never edits; the rounds stop quiet at the profile's quiet-round count (row 25).
4. **The built gate.** `scripts/research-kit/gate.sh built-run --program <slug>` evaluates rows 20–25
   (rows 1–19 are not re-run). When all pass it writes `built/BUILT-CERT-v<n>` and sets
   `build-certified`. `cc-research built show --program <slug>` summarises the instruments. The built
   certificate states both halves of the forecast: the changes observed before implementation signoff
   against the research certificate's forecast, and the after-signoff forecast from the mutant kill rate.
5. **Caps** (§11, additions to §6.5): a dead or voided built slot 2 re-runs; a mutation re-run once per
   survivor; 2 soak restarts; Stage 9 time 1 (lite), 2 (standard), 3 (full) agent-days, soak elapsed time
   excluded, with the overrun packet at 1.5 ×. Past a cap, open rows become named known rows or dated
   carried rows with defaults. A Stage 9 finding is a counted change against the before-signoff forecast,
   not a take-back.

6. **The implementation signature** (added 2026-10-05, v1.2; §11 "Signing the implementation"). A
   `build-certified` program is not done. Run `cc-research built signoff --program <slug>`: it prints the
   built certificate's lines, the file and hash the signature pins, the signature state, and the
   operator's exact command, `cc-signoff research:<slug>/implementation --evidence <what you read>`. Relay
   that output and stop: the agent never signs, and `cc-signoff` refuses under an agent ancestor (exit 3).
   The operator's command signs and runs `gate.sh built-signed`, which moves the registry
   `build-certified → implementation-signed` (active until close, like the build states). If the operator
   signed some other way, run `scripts/research-kit/gate.sh built-signed --program <slug>` yourself; it
   refuses without a valid signature on the newest built certificate, and names a void or stale one.
   Until then `gate.sh close` refuses, and a wave that follows implementation signoff is fired with
   `handoff-fire.sh --requires-gate <slug> --gate-after-signoff` (`gate.sh requires --after-signoff`),
   which refuses. `gate.sh render` states the signature on the built line. A fix after signoff goes back
   through `built-freeze --refreeze` and `built-run`; the new built certificate needs a new signature.

Then hand the operator the built certificate; signing the implementation is theirs.

## Files beside this one

- `RUBRIC.md` — §3.11 materiality, the only text raters apply.
- `checklist.jsonl` — the 33 frame-axis rows (FAC-01..FAC-33) that gate row 1 requires mapped.
- `briefs/reviewer.md`, `briefs/rater.md`, `briefs/verifier.md`, `briefs/seed-author.md` — frozen; a
  program records their hashes on its certificate.
- `briefs/built-reviewer.md`, `briefs/built-verifier.md`, `briefs/built-rater.md` — v1.2, Stage 9's built
  rounds (§11): every finding carries a failing-test command, run the as-built way.
- Tests: `tests/research-program-intake.bats`, `tests/research-program-briefs.bats`.
