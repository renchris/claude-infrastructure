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
  - `cc-signoff research:<slug>/veto/<DECISION-ID>` — veto an overrun or below-profile default.
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
`scripts/research-kit/probe-run.sh doctor` first. If `gemini` reports a login that needs interactive
consent, that is one operator step (an interactive `gemini` login in their own terminal); park it before
anything else, because the vendor preflight at step 6 fails on a dead lane.

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
   pins the responding model ids, and stores the page's hash in `frame.json`, so the frame signature
   covers the page.
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

## Stage 7 — certification (§3.8, §3.9)

- Seeds: a seed author from a vendor other than the lead's, briefed with `briefs/seed-author.md`, writes
  seed lines straight into `seed.py plant`. The lead never reads them.
- Rounds: `round.sh --kind certification --round K` fills four slot sets (Opus, frontier, OpenAI, Google)
  with the profile's strategies, every reviewer briefed with `briefs/reviewer.md` verbatim.
  `round.sh` refuses past `R_max` (§10 item 17).
- Each finding: a verifier (`briefs/verifier.md`), then raters (`briefs/rater.md`), launched through
  `courier.sh run --role verifier|rater`. Rater 1 is non-Anthropic; rater 2 another vendor; rater 3 the
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

Build waves fire only through `scripts/handoff-fire.sh --requires-gate <slug> --gate-wave <W>` (§3.10
"Carried rows at build time"). It refuses before any side effect while the registry is not `certified`,
the newest certificate has a FAIL row, a reopen is signed after it, or the wave's closure holds an
unresolved class-C row, a carried set it does not own the narrowing probe of, an open frame-omission
known row, or a wave the sweep descoped. `gate.sh requires --program <slug> --wave <W>` prints the same
verdict without firing. An admitted fire carries the `--requires-gate` work-order marker in its brief.

## Files beside this one

- `RUBRIC.md` — §3.11 materiality, the only text raters apply.
- `checklist.jsonl` — the 33 frame-axis rows (FAC-01..FAC-33) that gate row 1 requires mapped.
- `briefs/reviewer.md`, `briefs/rater.md`, `briefs/verifier.md`, `briefs/seed-author.md` — frozen; a
  program records their hashes on its certificate.
- Tests: `tests/research-program-intake.bats`, `tests/research-program-briefs.bats`.
