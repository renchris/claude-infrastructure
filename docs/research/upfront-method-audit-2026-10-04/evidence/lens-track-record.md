# Lens: empirical track record — working notes (auditor, 2026-10-04)

Question: has method v1.1 (`docs/research/upfront-research-exhaustion-2026-09-30/REPORT.md`) ever been run end to end on
a real program, and what does practice (not design) show about meeting the operator's goal of no "one more thing"?

Labels: **measured** = read from a record or command output this session; **modeled** = the method's own simulation;
**asserted** = a doc or agent claim not independently re-derived here.

---

## 0. Bottom line

- The method has **never been run end to end.** The one pilot (`truememory-2-0`) is part-way through Stage 4 of 8,
  with **0 certification rounds** and no certificate. So none of the claims about what happens after signoff (relaying
  the certificate on a re-ask, a 1–4% take-back rate, the tool block) has a single real observation.
- What the pilot does show is mixed, and the evidence is real:
  - (+) Stage 3, contact with the real environment, found concrete defects in a plan that 29 open critique rounds
    (519 verified findings) had not found.
  - (+) The open loop the method replaces demonstrably failed on this same deliverable.
  - (−) The operator rejected the method's main output (16 of 19 decisions handed back at 44–89% conviction) by
    ordering more research, and restated the "as infinitely long as possible" goal minutes later.
  - (−) The cwd-keyed program controls do not cover the panes that actually run the program.
  - (−) The re-ask router fails its gate row.
  - (−) The calibration says the method's own model guarantees at least one material change after signoff.

## 1. Pilot `truememory-2-0`: what stage, how long

Registry: `~/.claude/autonomy/research/programs.json` => one program, `truememory-2-0`, state `registered`,
cwd_roots `[/Users/chrisren/Development/.worktrees/tm2-plan]` (measured).

`bin/cc-research verdict truememory-2-0` => (measured)
```
Research: truememory-2-0 — registered; not certified. Certification rounds counted: 0; trailing quiet rounds: 0.
Pending concerns: 0
Waiting on you since 2026-10-04T04:15:15Z
```

`bin/cc-research budget --program truememory-2-0` => (measured)
```
stage 1: 0.06 d used of 2 d budget (cap 3 d)
stage 2: 0.06 d used of 1.5 d budget (cap 2.25 d)
stage 3: 0.89 d used of 1.5 d budget (cap 2.25 d)
stage 4: 0.26 d used of 3 d budget (cap 4.5 d)
stage 5: 0 d used ...   stage 6: 0 d used ...
```
`bin/cc-research ceiling --program truememory-2-0` => "standard profile ... ceiling about 28 days · elapsed 2.24 d ·
calendar ceiling with your waits about 28.2 days" (measured).

Stage clock, `tm2-plan/docs/research/truememory-2.0-2026-09-28/program/budget.json` (measured):

| Stage | Started | Ended |
|---|---|---|
| 1 | 2026-10-02T03:11Z | 04:36Z |
| 2 | 04:36Z | 05:57Z |
| 3 | 06:26Z | 2026-10-03T03:51Z |
| 4 | 2026-10-04T02:41Z | open |

About 23 h passed between the end of Stage 3 and the start of Stage 4, while the lead held "until you ask" (measured,
lead transcript b671b47e, 2026-10-03T21:50). The intake prefill dates from 2026-10-01 08:35 -0500 (commit a638566f2),
so Stage 1's 0.06 d undercounts the real intake effort (measured: git log).

Timeline of the deliverable, from `tm2-plan` git log (measured):
- 2026-09-27 to 10-01: pre-program research (`frame.json` reference_days 5).
- 2026-09-29 04:56: master plan.
- 2026-09-29 06:15: a commit titled "final critique round fixes", after which 29 more critique rounds followed.
- 2026-10-01 22:12: program registered.
- 2026-10-04 07:07: Stage 4 closed out (0b3b52446).

Stage 4 outcome, `tm2-plan/.../stage4-work/PLAN.md` § Outcome, and the lead's close at 2026-10-04T07:17 (measured):
- 3 decisions ruled by the kit at 90: DR-01, DR-14, DR-19.
- 9 carried as class C: DR-02 55, DR-04 79, DR-05 74, DR-07 66, DR-08 72, DR-09 69, DR-10 89, DR-12 66, DR-18 66.
- 7 class-B defaults that fire 2026-10-06T04:00Z: DR-03 71, DR-06 71, DR-13 71, DR-15 89, DR-16 59, **DR-17 44**,
  DR-20 89.
- Gate: rows 1–3 PASS; rows 4–5 FAIL (asserted by the lead; I did not run `gate.sh run`, which may write records).

Record volume (measured, `wc -l program/*.jsonl`): holes 398 (176 raise, 111 verify, 111 dispose), probes 271,
premises 144, decisions 119, residual 6, known_rows 9, apply-at-build 8.

**Cost (measured, partial lower bound).** I summed message `usage` over 250 transcript files: lead sessions 73a94c12,
2a8ba7e2, 2fc4f157 and b671b47e; stage sessions c0eba2c4 and 7dbd8a7a; slice session 6d1fd029; their `subagents/`
directories; and the fc1/fc2 round dirs. Deduplicated by message id, that is 8,015 assistant messages:
- output tokens 1.37M
- cache-creation 30.6M
- cache-read 1.34B

This excludes OpenAI and Google reviewer reads, the tm2-plan-replan sessions, and the in-flight 81-agent workflow.
REPORT §6.1 prices tokens as "Unmeasured. Roughly 20–40M tokens for lite, 40–80M for standard" (asserted there).

## 2. The open loop this replaces failed on the same deliverable (strength of the diagnosis)

`git log tm2-plan-replan` critique-round records (measured): 29 rounds, 519 verified findings in total. Verified
findings per round:

| Rounds | Verified findings |
|---|---|
| 1–5 | 37, 26, 22, 25, 28 |
| 6–10 | 24, 21, 17, 22, 21 |
| 11–15 | 22, 20, 18, 21, 18 |
| 16–20 | 17, 13, 14, 13, 10 |
| 21–25 | 12, 7, 9, 16, 13 |
| 26–29 | 13, 8, 11, 21 |

There is no convergence to zero. Round 29 (e38fd6984, 2026-10-02 17:00) reads "21 verified, 13 distinct ... open review
loop stopped per decision 1b6654bab64d".

REPORT §10 self-certification of the method's own report (measured, `REPORT.md:1280-1296`):
- Pass 1: 18 unique findings, an estimated 10 unfound.
- Pass 2: 17 unique findings, an estimated 42 unfound.
- 12 of pass 2's 17 findings were born in pass 1's fixes.
- "Not certified."

## 3. Contact before design found what desk review missed (strength)

`program/contact_matrix.json`, 15 cells (measured): 7 clean, 8 findings (K4, K5, K8, K9, K10, K11, K13, K15).
Examples:
- **K10:** the slice tree is red on the Windows 3.12 and macOS 3.12 CI legs (WinError 32; no sqlite-vec on the macOS
  runner).
- **K8:** the pre-push identity gate refuses the plan's noreply identity, so "no tm2 push to renchris/* can pass".
- **K11:** each of 6 hosts delivers its documented hook channel 5/5, but TrueMemory as shipped reaches the model on
  none. kimi-cli discards all hook stdout, the OpenClaw plugin dir is never discovered, Codex hooks are untrusted and
  Hermes hooks lack consent.
- **K13:** forget has a gap on builds without JSON1 (became DR-14).
- **K15:** 13 branch-only files would survive the public projection.

Honesty check: K4 (Claude Code ignores the top-level `additionalContext`) was **already known** before the program.
`git grep hookSpecificOutput 3ec223e32` finds `drafts/prs/PR-014.md:30` and `docs/plans/TRUEMEMORY_2_0.md:2481`
(measured). So K4 is a confirmation, not a discovery. The lead also said, before the K11 runs, that reading host code
already showed Cursor and Gemini fail (b671b47e 2026-10-03T23:41, asserted). So K11's genuinely new parts are the
Kimi, OpenClaw, Codex-trust and Hermes-consent mechanisms.

## 4. Did the operator get "one more thing" anyway? Transcript evidence since 2026-10-01

- **2026-10-04T07:17Z, lead (b671b47e):** "👤 My side is done ... Good to close: yes ... what's left is your 16
  decisions".
- **2026-10-04T07:33Z, operator:** "comprehensive ultracode on each /explain-decisions then come back again in the same
  format with your updated convictions".
- **2026-10-04T07:33Z, lead:** launched about 81 agents ("a researcher, then three skeptics ... then a judge ... followed
  by a completeness critic").
- **07:56Z:** "You've hit your session limit"; **08:07Z:** "Every agent in that run failed on the account's session
  limit; none produced a result"; re-run at 08:08Z on another account (measured).
- **2026-10-04T07:49Z, operator (this audit's parent session d8964eb2):** restated the goal, "as infinitely as long
  ... as physically possible ... not to come back with 'are we complete and perfect' to 'oh, and I forgot, one more
  thing'".

Reading: the method's "carried at timebox" outcome is, to the operator, an incomplete answer. In practice he re-opened
research on every carried decision. That is the operator buying an extension, which the exemption allows only as "a
priced, operator-bought extension" (`~/.claude/rules/10-session-close.md`, Active research program exemption). But it
was bought as an ad hoc fan-out, not through the method's priced menu (`cc-research verdict` lists only `extra-round`
and `reopen`).

The lead's own recommendations were reversed within hours by its own verification:
- **2026-10-03T23:41:** "Only 2 of the 11 open decisions sit on plan lines those rounds changed ... 88% conviction".
- **2026-10-04T03:53:** "The challenge refuted my evidence. Seven decisions ... not two". The K11 login advice went from
  75% to "Reversed ... 90%" (measured, transcript).

So the self-stated convictions are poorly calibrated; the kit's tally-derived 90 rule exists for this reason.

Other completeness asks since 2026-10-01 (about 50; regex over all account transcripts) are routine session closes,
not research-program re-asks. No post-certificate re-ask exists, because no certificate exists.

**The REPORT session (bb231dfd).**
- **2026-10-01T00:47, operator:** "is our research program report itself now 100.00/100.00 complete...?"
- **Answer:** "No, and the report itself says it isn't ... tooling is unbuilt, its numbers are uncalibrated, and the
  pilot hasn't run" (measured).
- Calibration later scored the report as the one plan of 16 whose 95% bound was exceeded: research-report-v1, 23
  realized against a bound of 21.16 (measured, `research-calibration.jsonl`).

## 5. Process escapes inside the pilot

1. **The open loop kept running after the stop ruling.** Rounds 24–29 ran on tm2-plan-replan from 2026-10-01 22:31 to
   2026-10-02 17:00, after the operator's 2026-10-01 ruling and the program's registration at 22:12. They produced 60
   rows that Stage 4 W1 had to fold in. The lead's words: "Rounds 24–29 ran after that by mistake" (b671b47e
   2026-10-03T23:41, measured).
2. **The program controls do not reach the panes that run it.**
   `bash scripts/lib/research-program.sh is-active <dir>` => rc 1 for `~/Development/claude-infrastructure` (the lead,
   pane 83), `tm2-plan-replan` and `tm2-slice`; rc 0 only for `tm2-plan` (measured). `completion-assert.sh:1108` keys
   the D4 exemption on `_ca_rp_active "$CWD"`, and `research-block.sh` keys on the same resolver. Operator messages
   show confusion about leadership: 2026-10-02T03:17 "do we need to consolidate sessions leading TrueMemory 2.0 plan?"
   and 2026-10-03T19:06 "Pane 83 now leads TrueMemory 2.0 alone".
3. **Frame churn.**
   - v1 was signed at 2026-10-02T04:35Z (pin 91c951c).
   - Stage 2 found 4 frame omissions within about 1.4 h (KR-01..04).
   - v2 and v3 were written at 06:05Z and 06:13Z.
   - **v3 was signed only at 2026-10-03T16:48Z** (pin c4a115a; `signoff.jsonl`). Stage 3 (from 06:26Z) therefore ran
     about 34 h on an unsigned frame (measured: git blob hashes against the signoff pins).
   - Stage 4 added DR-13..DR-20 (12 → 20 decisions), which need another re-sign at Stage 5.
   - The frame critique did not decay: fc1 had 52 findings, 27 holes and 22 material; fc2 had 64 findings, 24 holes
     and 18 material (commits 67dcf9b86, b8a5baca0). It stopped at its fixed cap of 2 (`REPORT.md:1049`).
4. **An operator requirement arrived after the first signature.** The second sitting (2026-10-02, after Stage 2) added
   Josh's stacked-PR presentation bar as AM-31 and "I rarely review code myself, always via agent"
   (`intake-answers.md`, commit 200c25431). The method's premise probes surfaced these before design, which is the
   method working, but the intake missed them.
5. **Protocol drift.** REPORT §6.5 says "Nothing else loops. There is no open-ended 'find gaps' loop anywhere after
   the frame critique" (`REPORT.md:1075`). The pilot lead nevertheless ran a completeness critic in the Stage 4
   research wave (`stage4-work/research-wave-1.json` key `critic`) and another in the 81-agent workflow. That critic's
   own output begins: "the SET reached me cut off partway through DR-01 ... Any entries for DR-02 to DR-12 were not
   visible", so it judged a truncated input (measured).

## 6. Instrument and operations failures (measured)

- **P-K4-a** ran logged out and was retracted (2fb99fef5); P-K4-b re-ran it at 2026-10-03T18:45Z.
- **G3, G6 and G7** were "rebuilt from their records after the 07:15Z network outage" (0bf3431c1).
- **P-S4-K11-openclaw** "timed out (exit 124 at 900 s, machine load ~225)" and was re-run as -b (`residual.jsonl`).
- **The 81-agent workflow** failed entirely on a session limit (2026-10-04T07:56–08:07).
- **The lead pane** hit limit-recover on 2026-10-03T03:54, "FAIL A1 — gaps_at_handoff=6".
- **The kit** "reads no residual status (gate rows 11-12), so the discharge is a fold event" (`residual.jsonl` row 3
  note).
- **Live reads** lapse after 72 h; census P6 went stale within a day when outside PR #734 opened on 2026-10-03.
  `apply-at-build.jsonl` holds AAB-live-reads, AAB-critic14-P9 and AAB-critic16-voi (`voi_rank` is unset on every
  decision).

## 7. Calibration study and reference class (retrospective replay, not forward runs)

`docs/research/research-calibration.jsonl`, 16 rows, one review round per plan (measured):
- The point forecast was exceeded on 6/16 plans and the 95% bound on 1/16 (the method's own REPORT).
- Bound ÷ point forecast: median 9.2×, range 7.1–33.2×. Realized ÷ point: median 3.0×.
- realized_missed ≥ 1 on 16/16 plans.
- tm2 row: freeze 3b5af2c22, 185 holes at freeze, realized 151, point 11.67, bound 387.42, front_end_days 0.48.

`research-calibration/REPORT.md:208-215` (modeled): "Any change after signoff" is **1.00** for every profile at the
measured inputs. Desk holes left at signoff: 6.5–21.4. Every profile hits its cap in 98–100% of programs.
§1: "Lite is the default for every size until the false-material rate is below about 0.02 per read."

The pilot nevertheless runs **standard**: `frame.json` profile "standard"; `intake.jsonl` init profile "standard",
dated 2026-10-02T03:11Z, after the calibration of 2026-10-01. `scripts/research-kit/intake.py:436` accepts any of
`kit.PROFILES` with no calibration check (measured).

`docs/research/research-reference-class.jsonl`: 8 greenfield rows, 1–35 research days (measured). None comes from a
program run under the method.

## 8. The re-ask half

`docs/plans/RESEARCH_PROGRAM_BUILD.md:171-175` (asserted there; not re-run here, since evaluation calls vendor CLIs):
"Row 15 FAILS today: fallback 0.96 at load ~295 and 0.51 at load ~45-80 against the 6 s limit; correct labels on `other`
0.12 then 0.62". Migration 0051 has been applied: `~/.claude/autonomy/migrations/applied/0051-research-jobs.json`
exists and five `com.claude.research-*.plist` are in `~/Library/LaunchAgents` (measured). The research hooks are
registered: `jq` over `~/.claude/settings.json` shows PreToolUse `research-block.sh` and UserPromptSubmit
`research-precognition-nudge.sh` (measured).

## 9. Attainability of the goal as stated

- **"Not to come back with one more thing" is unattainable, and the evidence is empirical, not only theoretical.**
  - 16/16 replayed plans had real holes surface later.
  - The method's own model gives P(any material change after signoff) = 1.00 at measured inputs.
  - Evidence perishes while research runs: 72 h TTLs, an upstream PR opened mid-program.
  - Some decisions depend on a third party's preference (Josh, on DR-02/04/05/07) that no research can settle; the
    pilot's answer is to keep several variants built.
- **"As infinitely long as physically possible" is self-limiting.** Longer research means more live reads to re-run
  and more drift in the world, and in the measured loop every fix round breeds holes (fix-born 0.21 per fix; 12 of 17
  findings in pass 2 were fix-born).
- **The strongest attainable version:**
  - every material item that desk research or contact can reach is found before the claim;
  - every remaining unknown is named and dated, with a falsifier;
  - a later change can only be (a) an item already on that named list, (b) a new operator requirement, or (c) a
    change in the world after a dated read.
  - And the answer to "are we complete?" states those three classes rather than "yes".

The method aims at roughly this, but it has not yet demonstrated any of it on a finished program.
