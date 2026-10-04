# Lens: goal fit — working notes (auditor, 2026-10-04)

Question: is the method (REPORT v1.1 + kit + pilot) the best attainable way to meet the operator's literal goal,
"not to come back with 'are we complete and perfect' to 'oh, and I forgot, one more thing'", given unbounded
time/token/cost/effort?

Paths: `R` = `docs/research/upfront-research-exhaustion-2026-09-30/REPORT.md`; `C` =
`docs/research/research-calibration/REPORT.md`; `TM2` =
`~/Development/.worktrees/tm2-plan/docs/research/truememory-2.0-2026-09-28/program/`. Labels: **measured** (from data),
**modeled** (simulation), **asserted** (stated, no measurement).

## 0. Bottom line

- At the method's own measured inputs, a program should expect about **10 material changes after signoff**, with
  P(at least one) = **1.00** for every profile (modeled on measured inputs: `C:208-215`;
  `research-calibration/evidence/sim/sim-main-fa022.out` lines 7 and 9: lite N0=20 desk 6.66 + invisible 3.00,
  standard desk 6.45 + invisible 3.65, `P(any) 1.00`). That is incompatible with the goal's literal wording.
- Most of that number is **not forced**. Over 70% of the desk part comes from triage quality and a change-control
  choice, and a review-only extension the method never modeled would cut most of the rest (§3, §4 below).
- What is forced: certifying zero (Link 2003; n ≥ 0.95N), a positive invisible share (measured 0.12, bracket
  0.02–0.34), world drift that grows with calendar time, and the harm of fix-and-review loops at the measured
  fix-born rate. So the strongest attainable version of the goal is: **zero undisclosed, desk-findable or
  machine-probe-able changes after signoff. Every other post-signoff change maps to a row named at signoff, and the
  unnamed forecast is confined to the invisible share plus drift.**
- The operator ruled on the method (decision packet `83adb541ea19`, resolved `2026-10-01T06:07:33Z`) about 7 hours
  **before** the calibration that falsified its headline numbers landed (`21a585908`/`72ee29cbc`,
  `2026-10-01T08:11:22-05:00` = 13:11Z). The live pilot's contract page still shows those pre-calibration numbers.

## 1. Receipts for the headline numbers

| Claim | Value | Label | Receipt |
|---|---|---|---|
| §1 headline: post-signoff change | "about 6–9 in 10 with a strong front end" | modeled, pre-calibration | `R:35` |
| Same at measured inputs | P(any) 1.00, every profile | modeled at measured inputs | `sim-main-fa022.out:7,9`; `C:210-212` |
| Desk + invisible residual, lite/std, N0=20 | 6.66+3.00 / 6.45+3.65 | modeled | same |
| At all false calls (1.13/read) | lite 9.4+3.9, std 13.5+7.3, full 21.4+12.6 | modeled | `C:213-215` |
| Stop rule fires? | cap hit 98–100% | modeled | `C:23`, `R:704-706` |
| Estimator used by intake | `BASE = dict(u=0.05, fpp=0.01, q=0.05, omit=0.3, ...)`, `FIX_BORN 0.1` | code | `scripts/research-kit/estimate.py:36-38` |
| Intake's forecast call | `estimate.py simulate --profile P --n0 design_holes` (no measured regime) | code | `scripts/research-kit/intake.py:287-296` |
| Ran it this session | `estimate.py simulate --profile standard --n0 20 --reps 300` ⇒ `desk_left 1.57, invisible_left 1.08, p_any 0.87` | command | this session |
| TM2 contract page | "standard … desk-detectable left 1.57, invisible left 1.12 … chance of at least one material change after signoff 0.87" | live record | `TM2/CONTRACT.md` (rendered 2026-10-02T06:12:59Z) |
| TM2 frame signatures | 2026-10-02T04:35:55Z and v3 2026-10-03T16:48:46Z | live record | `~/.claude/autonomy/research/truememory-2-0/signoff.jsonl` |
| Ruling time | resolved 2026-10-01T06:07:33Z, "Proceed as you recommend with all" | live record | `~/.claude/autonomy/decisions/83adb541ea19.json` |
| Calibration land | 2026-10-01T13:11:22Z | git | `git log -1 --format=%cI 72ee29cbc` |

So the definition-of-complete ruling (R §9 decision 1, 88%) and the pilot's frame signatures were both given against
a forecast of about 1.5–2.7 residual holes and "6–9 in 10". The measured version is about 10 holes and 10 in 10.
§1 (`R:35-37`) and §7 (`R:1104`, "0.7–1.6 per program") were never updated. §1 also still says "the only things that
shrink that number are a better front end and earlier contact", yet the calibration says triage is the largest
lever (`C:221-234`).

The pilot also runs **standard** (`TM2/frame.json` `profile: standard`; `TM2/intake-answers.md` row 11), against the
calibrated decision 4 ("lite for every size", 92%, `R:1175`). At measured inputs, standard leaves the same desk
residual as lite (6.45 vs 6.66) at twice the reads. Modeled this session, it also breeds about 10 fix-born holes per
program against lite's 4.6 (see §3).

## 2. Each tradeoff: forced, chosen or unsupported

| Tradeoff | Where | Verdict | Why (receipt) | Under unbounded spend |
|---|---|---|---|---|
| "Complete" = 100% of a signed frame + a forecast | `R:185-198` | **Forced in kind; chosen in size** | Certifying zero needs n ≥ 0.95N (`evidence/external/stopping-rules.md:75`); 3,654 seeds all caught at F=60 (`evidence/design/stopping_model.out:12`); shared blind spots are not identifiable (Link 2003, `evidence/external/unseen-estimation.md:110-112`). But the definition accepts any residual size: "100.00%" can sit beside about 10 expected changes | Keep the frame definition; put the expected post-signoff count on line 1 and drive it down (§4) |
| Round hard caps 6/10/14 | `scripts/research-kit/lib/kit.py:119-150`; `R:972-974` | **Forced only for fix-and-review rounds** | Each false call that gets fixed breeds holes at b≈0.2 (`C:123-131`), so width and depth make the residual worse (`C:37-39`). The model fixes every false positive (`estimate.py:205-216`) | Keep the cap on *fixing*. Lift it for *review-only* rounds, which breed nothing (§3) |
| Cap round verification-only | `R:520-524` | Forced (it protects the freeze) | Fix-born | Keep |
| Lite default | `R:1175`, `R:991` | **Forced conditionally**: true only while false calls stay above about 0.02/read | `C:232-234` | It flips if triage is fixed. The pilot ignores it anyway |
| Finite escape cost (decision 5) | `R:241-242`, `intake.py:258-268` | Logic forced (Dalal–Mallows: the optimal residual is f/(cμ) > 0 for finite c, and "stop never" as c→∞; `stopping-rules.md:77`); **implementation decorative** | `escape_cost_days` is set, printed and checked for presence, and **read by nothing else**: `grep -rn escape_cost scripts/research-kit bin/cc-research` ⇒ only `intake.py:179,274,304,362,419`. TM2 took the report's default of 3 days | Make it the dial that sets ceilings, timeboxes and the review-only stop (value-of-information, VOI) |
| Frame critique exactly 2 rounds | `kit.py` `CAPS["frame_critique_rounds"]: 2`; `R:1049` | **Chosen; the pilot contradicts it** | TM2 fc1: 22 material, fc2: 18 material (`TM2/holes.jsonl`, tallied this session). The ratio 0.82 is above the method's own divergence threshold of 0.7 (`R:526-529`). Omissions are 58% of holes (`C:91`) and are born in the frame | Add review-only frame rounds until one is quiet, or print a Chao1 estimate at signing |
| Desk review of the method capped at 2 passes; method frozen (decision 8) | `R:4-8`, `R:1179` | **Chosen; it now blocks a measured fix** | Self-certification: Chao1 still-unfound rose from about 10 to about 42 (`R:1282-1283`); 12 of 17 pass-2 finds were fix-born (`R:1292-1294`), which justifies stopping *desk* review. But "change only named sections from measured results" (profile table, caps, seed counts, `R:1143-1145`) left out triage, and the calibration says triage is the lever: "Not changed, because it is outside this wave's edit scope: the triage itself" (`C:250-255`). No brief, rubric or triage commit since `0fb32f503` (`git log -- skills/research-program/briefs skills/research-program/RUBRIC.md scripts/research-kit/lib/cli_records.py`) | Treat triage as a named, measured section and change it from the replay's ground truth |
| Decision timeboxes, then class-B defaults | `R:390-395`, `R:1047` | **Chosen** for rows not blocked by the operator or production | TM2 stage 4: 3 decisions ruled at 90 by the agent, 9 carried class C at 55–89, 7 class B defaults at 44–89 due 2026-10-06 (`tm2-plan/.../stage4-work/PLAN.md:96-99`). The receipt wording "research exhausted at timebox" (`R:204-206`) describes the timebox running out, not the research | Default only rows whose blocker is operator-only or production-only; keep probing the rest |
| Contact cells inside the stage budget; the excess declared as build residual | `R:422-423` | **Chosen** | Contact is the only lever on the invisible part (`R:1105`). Desk review in one round found only 27% of build-found and 30% of probe-found holes (`C:146-147`) | Lift it: a throwaway spike or prototype build as a pre-signoff instrument |
| Frame expansion 2 levels; census reviewer once; reaction checkpoint once; frame-delta cycle once; take-back once per area; extra round set 1 | `R:1044-1072` | **Chosen** (asserted caps; none measured) | No receipt beyond loop-avoidance | Lift where review-only; keep where the step edits the frame |
| New ideas park in the next version | `R:856-871` | **Forced and goal-compatible** | 94 of 532 prompts (17.7%) introduced a new idea, about 1.6 per active day (`R:101-106`); the operator keeps a "blocks this version" override | Keep |
| No research on a re-ask (tool block, relay check) | `R:778-803`, `R:844-850` | **Forced** (more spend there is harmful) | A neutral review of a correct artifact still flags issues at ≥ 88%; "Are you sure?" flips answers 46% of the time (`evidence/external/llm-failure-modes.md:11,35,46`) | Keep |
| Pinned detectors; no post-freeze frontier sweep (Appendix B break 8) | `R:469-471`, `R:1216` | **Chosen**: trades detection for a cleaner bound | The rationale is the validity of the bound ("breaches the bound"), not outcomes | Allow a review-only, edit-free sweep by a new detector before build start, its finds printed as named known rows |

## 3. Modeled this session: what the residual is made of, and what review-only rounds buy

Method: I reimplemented `estimate.py` `program()` (`scripts/research-kit/estimate.py:151-253`) using its own
`new_item`, `detect` and `poisson`, at the calibration's measured inputs (`evidence/sim/p-main-fa022.json`: u 0.12,
fpp 0.22, q 0.2, omit 0.58, b 0.2, surf_blind 0.5), N0 = 20, 400 reps, seed 7. I split the desk residual into
holes no reviewer found ("undet") and real holes found but downgraded by raters ("deferred", which the model
counts as escapes, `estimate.py:241`). Then I added M **verification-only** rounds after the cap: detect and name,
never fix, so no fix-born holes. The script went to stdout only. Cross-check: standard undet + deferred = 6.31,
against the calibration's 6.45; raw blind 3.56 against 3.65.

| Profile / inputs | undet | deferred | invisible (surfaced) | named by extra review-only rounds | fix-born holes per program |
|---|---|---|---|---|---|
| lite, measured | 2.83 | 3.75 | 1.47 | — | 4.56 |
| lite, measured, +4 review-only | 1.71 | 3.95 | 1.49 | 0.97 | 4.57 |
| lite, measured, +12 review-only | 0.80 | 4.20 | 1.43 | 1.71 | 4.71 |
| lite, triage fixed (fpp 0.02, q 0.05) | 2.75 | 0.82 | 1.44 | — | 3.39 |
| lite, triage fixed, +4 review-only | 1.53 | 0.92 | 1.38 | 1.15 | 3.52 |
| lite, triage fixed, N0=10 | 1.51 | 0.49 | 0.75 | — | 1.78 |
| standard, measured | 1.21 | 5.10 | 1.78 | — | 10.24 |
| standard, measured, +12 review-only | 0.35 | 5.14 | 1.87 | 0.72 | 10.11 |
| standard, triage fixed | 0.89 | 1.03 | 1.48 | — | 4.63 |
| standard, triage fixed, N0=10 | 0.49 | 0.55 | 0.83 | — | 2.41 |

Readings (all modeled):
1. **57% (lite) to 81% (standard) of the measured desk residual is "deferred"**: real holes that a reviewer found
   and a rater rated below material. They sit in the method's own refinement and apply-at-build records at signoff.
   They surface later as "one more thing" only because they are filed as refinements. This is the cheapest part to
   eliminate: re-adjudicate the whole refinement list against reproduced consequences before signoff. The
   calibration's history-informed adjudicator found 40 real material holes among 129 unmatched items (`C:107-110`),
   and its blind control came back 30 of 31 (`C:109-110`).
2. **Review-only rounds lower the undetected desk residual monotonically, with zero fix-born cost.** Lite falls
   2.83 → 1.71 (+4 rounds) → 0.80 (+12); standard falls 1.21 → 0.35. At 0.36 weekly-quota points per lite round
   (`C:98`), +12 rounds cost about 4.3 points (modeled from measured price). So `R:989-991` ("a higher cap would not
   help") holds for fix rounds only. And `R:1036-1039` ("no further desk review can lower this; only contact or
   building can") describes the printed **bound**, not the holes left.
3. Once triage and front end are both fixed, the undisclosed remainder is about 1.5 undetected + 0.75 invisible at
   N0=10 for lite. That is the scale of the attainable floor before contact work. Contact (§2, contact row) is what
   attacks the invisible part.
4. The fix-born count tracks the reader count (standard 10.2 against lite 4.6 at measured inputs). That is the
   reason the pilot's standard profile is the wrong choice at current triage.

## 4. Is "most programs expect ≥ 1 material change after signoff (6–9 in 10)" compatible with the goal?

No. And the measured version is worse: 10 in 10, about 10 changes (§1). The goal's literal reading ("no one more
thing") would need zero changes after signoff of any kind. That is physically unattainable for three measured
reasons:
- **Invisible share > 0.** It is 0.12 (bracket 0.02–0.34, `C:91,138-144`); by Link 2003 it is not even estimable
  from overlap.
- **The world moves faster than research.** TM2's upstream release gap is 3 days, giving a 0.99 chance of a release
  during the program (`TM2/CONTRACT.md`; `R:1014-1016` formula). Trunk took 40–231 commits a day (`R:941-943`).
  Drift caused 8 of 200 historical holes, 4 of them unforeseeable (`R:1108`). **Calendar time is the one input where
  more makes the outcome worse**, so "as infinitely long (in time)" defeats itself. Buy effort as parallelism, not
  as wall clock.
- **Operator intent changes**: 1.6 new ideas per active day (`R:101-106`), which the method rightly parks.

The strongest attainable version, and what moves the number toward it, in measured order of leverage:
1. Fix triage, which the calibration measured as the biggest lever: desk 6.45 → 1.82 with fpp 0.01 and q 0.05
   (`C:221-230`). The calibration names three concrete candidate changes, each testable on the existing ground
   truth for 160 items (`C:252-255`). None is built.
2. Re-adjudicate every refinement before signoff (§3 reading 1). This turns most of the deferred residual into named
   rows.
3. Review-only rounds past the fix cap, plus a pre-build review-only sweep by any new model, both naming instead of
   editing (§3 reading 2).
4. Lower the holes at freeze with the front end. Halving N0 halves both parts (`R:668-670`). The method's own front
   end is still unmeasured: the calibration's N0 of about 21 came from plans that had no method front end (`C:132-136`).
5. Lift the contact budget: spike-build the riskiest slices before signoff. This is the only lever on the invisible
   share.
6. Re-word the promise: line 1 should carry "N named rows to apply at build, M unnamed expected (invisible + drift)",
   not "100.00%".

## 5. Strengths that fit the goal

- The diagnosis of *why* "one more thing" recurs is measured and attacked at its causes. Prompts with a gap quota
  ("Find 2-3 gaps" and similar) were removed (`R:84-92`; wave A1, `RESEARCH_PROGRAM_BUILD.md:40-49`). Research is
  denied on re-asks: 95.7% of completeness asks called tools (`R:89-92`). The tool block and router are registered
  live: `jq … ~/.claude/settings.json` ⇒ `~/.claude/hooks/research-block.sh` on PreToolUse, and the nudge hook on
  UserPromptSubmit with timeout 10. `launchctl list` shows the five research jobs loaded.
- Caps that must stay, even with unbounded spend, are correctly identified: fix-and-review loops (TM2's open loop
  ran at b = 0.40, `C:125-128`); per-ask research; open critique loops (23, 21, 24, 28 new blockers per round, none
  repeated, `R:93-96`).
- Only the operator can exceed a ceiling, through reopen, the extra round set or a veto (`R:1001-1002`), so the caps
  do not override his authority.
- Caveat: the relay check (`R:844-850`) can satisfy the goal's *letter* by muting replies, not by making the plan
  complete. The "material changes, any cause" counter (`R:897-899`) is what keeps that honest, and its printed
  forecast is the stale one. Also, gate row 15 reads FAIL today (fallback rate 0.96 under heavy load and 0.51 under
  moderate load, against a 6 s limit; `RESEARCH_PROGRAM_BUILD.md:168-176`), so no certificate can be issued until
  the router's latency is fixed.

## 6. Commands run this session (all read-only)

- `python3 estimate.py simulate --profile standard --n0 20 --reps 300` ⇒ `desk_left 1.57 … p_any 0.87`
- The §3 reimplementation (stdin script, no file written) ⇒ the table in §3
- `grep -rn escape_cost scripts/research-kit bin/cc-research` ⇒ intake.py only
- TM2 tallies over `holes.jsonl` and `decisions.jsonl` (stdin Python)
- `git log -1 --format=%cI 72ee29cbc`; `cat ~/.claude/autonomy/decisions/83adb541ea19.json`
- `jq` over `~/.claude/settings.json`; `launchctl list | grep research`
