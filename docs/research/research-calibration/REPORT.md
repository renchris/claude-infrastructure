# Calibration study: the research method replayed on 16 held-out plans

Wave A3 of `docs/plans/RESEARCH_PROGRAM_BUILD.md` (REPORT §8 item 14). Run 2026-10-01, read-only on every plan and
transcript. One row per plan: `docs/research/research-calibration.jsonl`. Code, briefs and per-plan evidence sit beside
this file in `docs/research/research-calibration/`. REPORT below means
`docs/research/upfront-research-exhaustion-2026-09-30/REPORT.md`.

This repo is public, and the raw per-plan evidence quotes private repositories, so it lives in the operator's private
store: `$CC_PRIVATE_DIR/docs/research/research-calibration-2026-10-01/` (history reconstructions, reviewer findings,
triage, rater and adjudication records, seeds, transcript timing, run notes). `evidence/PRIVATE_MANIFEST.json` lists
every file there with its sha256. Below, `evidence/history/`, `evidence/findings/`, `evidence/triage/`,
`evidence/adjudicate/`, `evidence/raters/`, `evidence/seeds/` and `evidence/timing.json` name files in that store;
every other `evidence/` path is in this repo.

## 1. The answer

The method's arithmetic holds, but two of its inputs are far worse than assumed, and both are about triage, not
reviewer count:

- **False material calls: about 1.1 per reviewer-read, not 0.01.** After the full triage (blind verifier, three
  raters, reproduced consequence), 89 of the 129 items that matched no known hole were, by the plan's own later
  history, either false (17) or real but not material (72). Counting only the false ones, 0.22 per read. At either
  rate no round is ever quiet: every profile runs to its hard cap in 93–100% of programs.
- **Rater downgrades: about 0.2, not 0.05.** One real hole in five that a reviewer found was rated below material.
  Those surface later, and they are the main reason the desk residual at signoff rises from §3.12's 1.4–2.7 holes to
  6.5–7.6 (20 holes at freeze).

Everything else measured close to REPORT's stress values: fix-born 0.21 per fix (assumed 0.1), omissions 58% of holes
(assumed 30%), invisible share 0.12 (assumed 0.05, priced up to 0.2), holes at freeze a median of 21 after an audit
(assumed 10–20). The printed 95% bound still holds at measured inputs (exceeded in at most 2.2% of simulated programs;
1 of 16 plans in the replay), because it widens with everything that goes wrong; the typical-case forecast is exceeded
in 22–38% of programs at base inputs and 6 of 16 plans in the replay.

**Decision 4 is settled for its Full half and refined for its Standard half.** Full's precondition, fewer than 1
false alarm per 100 reviewer-reads and OpenAI and Google each sustaining 6 reviewers a round, fails on every term:
false alarms are 22–113 times the threshold, OpenAI on ChatGPT Plus walled after 15 reviewer-reads, and Google was not
testable. At measured inputs, wider review buys nothing: Standard leaves 6.45 desk holes against Lite's 6.66, and
Full 7.58, because every false finding that is "fixed" breeds new holes at the fix-born rate. Lite is the default for
every size until the false-material rate is below about 0.02 per read.

## 2. What was replayed

**Plans (n = 16, all usable).** Every candidate had a freeze sha with evidence and at least 2 known later material
holes with receipts: 9 from claude-infrastructure (LIMIT_RECOVER_100P, LIMIT_DETECT_100P, HOOK_SURFACE_100P,
RESO_LATENCY_100P, RESO_SECURITY_100P, LAND_PIPELINE_V2, MACHINE_CAPACITY_V2, LIMIT_RECOVER_FLEET_V2, and REPORT v1
itself), 3 from reso-management-app (TENANT_PROVISIONING_100P, LAND_SHIP_V2, DEVICE_ENROLLMENT_BUILD), and one each
from voiceink (LATENCY_WILLOW_PARITY), sevenrooms-bridge (LAPTOP_INDEPENDENCE), agent-context-sync (CONTRACTS.md)
and the TrueMemory 2.0 plan at its round-1 sha `3b5af2c22`. Plan size at freeze: 90 to 3,290 lines, median about
420; 3 to 31 decisions.

**Known later holes.** One read-only analyst per plan reconstructed the freeze and every material hole that surfaced
after it, from the plan's own post-freeze diffs, ledgers, critique records and commit bodies (`evidence/history/`).
Each hole carries how it was found (desk review, build, probe, operator, world moved), where its evidence sat at the
freeze, whether it is an omission, and whether a post-freeze fix wrote it. 435 holes are listed (40 at most per plan;
TM2's counts are complete but its list is capped). **Audit:** a second agent tried to refute 64 of the 435 (15%, four
per plan at fixed positions, `evidence/audit-sample.json`); 50 of 64 (78%) survived as real, material and present at
the freeze. Holes-at-freeze counts below are deflated by 0.78.

**Held out.** For each plan, the 32-row frame axis checklist (SYNTHESIS §3.5) and the escape library (the 129
desk-findable ledger rows) were rebuilt without that plan's ledger rows, by project and by cited id, before anything
was replayed (`build_heldout.py`, `evidence/heldout/`). The rebuild removed 0 to 25 ledger rows per plan and 0 to 2
checklist rows (VoiceInk lost FAC-02 and FAC-03, TM2 FAC-21, agent-context-sync FAC-15).

**Bundles.** Each reviewer saw only a directory exported with `git archive` at the freeze sha: the plan, the paths it
cited, and (full-context slots) the held-out checklist; no later commit, ledger or critique record. Four seeds per
plan (one omission operator, three commission operators), written by OpenAI from that plan's held-out escape library,
were planted in the bundle copy; all 64 anchored verbatim and applied (`evidence/seeds/`).

**One certification round per plan, Lite profile, two vendors.** Slot sets: Opus 5.5 (full context, plan only); the
frontier slots filled by Opus 5.5 (§3.8's "reduced diversity" composition); OpenAI (`codex exec -s read-only`,
gpt-5.6-sol at high, model pinned and confirmed per run). Google was not run: the provider registry marks the Gemini
CLI's plan and billing unknown and inspecting its auth was refused, so no paid call was risked. The brief is §3.8's,
with zero findings stated as correct (`briefs/reviewer.md`). Then a deduplication adjudicator; a verifier blind to who
and how many raised each item; rater 1 OpenAI, rater 2 Anthropic, rater 3 a fresh OpenAI process on the 82
disagreements (§3.8's two-vendor rule); a scorer that matched items to known holes and seeds only after rating; and,
for every material item that matched nothing, an adjudicator reading the plan's later history (§4.1). Anthropic
reviewers ran as lean workers that load no resident rules; an integrity check over every tool call voided any slot
that read outside its bundle (none did). 64 Anthropic and 15 OpenAI reviewer-reads: 79 reads, 688 raw findings, 332
distinct items.

**What the replay cannot do.** It runs one round, not a program. No fix is applied, so the fix-born rate comes from
history; and "missed in one round" cannot be told apart from "invisible to every round" (§4.4).

## 3. Measured inputs

| Input | §3.12 assumed (base / stress) | Measured | n | Field |
|---|---|---|---|---|
| False material calls per reviewer-read, after triage | 0.01 / 0.02 | **1.13**; 0.22 counting only claims history shows false | 79 reads, 16 plans | `fpp`, `false_alarms` |
| Rater downgrade of real holes | 0.05 / 0.10 | **0.22** on known holes (21 of 94); 0.17 on seeds (7 of 42) | 136 items | `q_counts`, `q_seeds` |
| Omission share of holes at freeze | 0.3 / 0.5 | **0.58** | 16 plans | `omit_plan_mean` |
| Invisible share | 0.05 / 0.10 (priced to 0.2) | **0.12**, bracket 0.02–0.34 | 16 plans | `u_plan_mean`, `u_lo_*`, `u_hi_*` |
| Fix-born rate per applied fix | 0.1 | **0.21** plan median (0.06–0.40); 0.18 pooled without TM2; 0.40 TM2 | 16 plans, 602 fixes | `fixborn_rate`, `b_pooled_ex_tm2` |
| Holes at freeze | 10, 20, 60 | **median 20.6** after the audit (middle half 15–27; TM2 145) | 16 plans | `holes_at_freeze_audited` |
| Frontier slots on Opus vs Opus (same strategy) | rho 1.0 | phi **0.62**; model fit rho 0.5 | 17 pairs | `evidence/fit.json` |
| Cross-vendor correlation (same strategy) | sd_f 1.0 | phi **0.51**; model fit sd_f 1.5, sd_d 2.5 | 9 pairs, 8 plans | `evidence/fit.json` |
| Per-read recall on desk-findable known holes | — | 0.22 full context, 0.11 plan only | 160 holes | `evidence/fit.json` |
| Seeds caught and rated material in one round | — | 0.55 (35 of 64) | 64 seeds | `seed_recall` |
| Quota per Lite round | unmeasured | 0.36 weekly pp on Anthropic (0.05 per read + 0.16 triage); OpenAI 70k tokens per read | 79 reads | `evidence/price.json` |
| Typical-case forecast exceeded | not reported | 22–38% (model, base inputs); 6 of 16 plans (replay) | 16 plans | `point_exceeded` |
| 95% bound exceeded | 1–4% | ≤ 2.2% (model, measured inputs); 1 of 16 plans (replay) | 16 plans | `bound_exceeded` |
| Re-ask router recall (gate row 15) | 0.95 assumed | pending: wave B1 has not built it | — | — |

## 4. Findings

### 4.1 False material calls: the stop rule cannot fire
No reviewer returned zero findings; reads raised 4 to 19 each (688 over 79). The verifier confirmed 295 of 332 items,
and the three raters passed 237 as material. 108 of those matched a known hole or a seed. The other 129 went to an
adjudicator that read the plan's post-freeze history (`evidence/adjudicate/`): 40 real and material, 72 real but not
material, 17 false, 0 undetermined. A blind control of 31 known-real holes mixed into its lists came back 30 real
and material, 1 real but not material, 0 false. So 89 false material calls survived triage: 1.13 per read; 0.22 per
read if "real but not material" is forgiven. Both vendors contribute about equally (on the 8 plans with both, false
material calls per read: Opus 2.0–2.6, OpenAI 1.6–2.3, counting each read that raised the item).

The second reviewer's own re-check is not a usable filter: rater 1 "refuted" 43% of the items that match known,
history-proven holes, about as often as it refuted unmatched ones (36%). Its refutation means "not provable from the
bundle's text", not "false".

Caveat that cuts in the method's favor: these plans had no signed frame, so a finding could not be rejected for
naming no frame row (§3.11's first condition). Most of the 72 "real but not material" calls are the kind that rule
would remove. The measured rate is therefore an upper estimate for a framed program, but the gap to 0.01 is
two orders of magnitude.

### 4.2 Fix-born rate: about 0.2 per fix, and 0.4 under an open loop
Fix-born holes per applied post-freeze fix, from history: plan median 0.21 (range 0.06–0.40); pooled over the 15
plans other than TM2, 58 of 319 = 0.18. TM2's open critique loop, which integrated every verified finding and added a
checker rule per recurring class, ran at 113 of 283 = 0.40 by its own ledger and up to about 0.6 by cited-span blame
(`~/.cache/rescomp-rebuild/tm2-loop-introspection.md` §2). REPORT v1's own two certification passes ran at 7 of 19
= 0.37. History counts only fix-born holes that surfaced, so these are lower bounds. The method's controls (material
only fixes, one consistency read, no new machinery) target the TM2 mechanism, so 0.2 is the expected rate and 0.4 its
failure mode.

### 4.3 Holes at freeze: about 21, inside the "strong front end" band
Known at-freeze holes plus the 40 real material holes the replay found that history never recorded, deflated by the
audit's 0.78: median 20.6, middle half 15–27, TM2 145. These plans had no method front end, so the band §3.12 calls
"strong" (10–20) is what ordinary planning here already produces; a weak front end in §3.12's sense (60) appeared
only once.

### 4.4 Invisible share: 0.12, bracketed 0.02–0.34
Of the known at-freeze holes no reviewer caught, history says a non-desk detector (building, probing, production, the
operator) found them later. One round cannot separate "invisible to every reviewer" from "hard, found in a later
round", so the share is bracketed by where the evidence sat at the freeze, per plan mean: 0.02 for evidence that did
not yet exist; 0.12 for evidence outside the bundle or not yet existing, found by a non-desk detector, and missed by
every reviewer; 0.34 for every non-desk-found hole the round missed. The point sits between REPORT's stress value and
its `u_hi` of 0.2; the upper bracket passes `u_hi`.

Desk review in one round found 27% of the holes history attributes to building and 30% of those attributed to probes,
against 35% of those a desk reader found later: much of what contact found was findable at the desk.

### 4.5 Omissions: 58% of holes at freeze
Per plan mean. One round caught 28% of omission holes against 37% of commission holes.

### 4.6 Rater downgrades: 0.2
Of the reviewer items that matched a known hole and that the verifier confirmed, 21 of 94 ended below material under
the 2-of-3 rule; of seed-matched items, 7 of 42. Some history holes are not material (the audit kept 78%), so the
known-hole figure is an upper estimate; the seed figure, 0.17, is the cleaner one. Both are well above 0.05.

### 4.7 Reviewer correlation
Over the 160 known holes a desk reader found later with the evidence in the plan or repo at the freeze, a detection
matrix per reviewer slot gives phi on the same strategy: Opus against Opus in the frontier slots 0.62 (17 pairs);
Opus against OpenAI 0.51 (9 pairs). Per-read recall: full context 0.22, plan only 0.11. Fitting cert_sim's detection
model to these four numbers (`fit_detection.py`, `evidence/fit.json`, residual 0.42 against the default's miss of all
four) needs a wider spread of hole difficulty than the default (`sd_d` 2.5 against 1.2), a large share of holes no
slot reaches in one round (0.6), frontier-slot correlation `rho` 0.5 and family spread `sd_f` 1.5. Read: reviewers
agree mostly because most holes are hard for all of them; a second Opus slot adds less than an independent slot but
not nothing, and only somewhat less than an OpenAI slot.

### 4.8 Quota and vendor load
- **Anthropic:** 0.05 weekly pp per reviewer-read at the fitted price list (`cc-quota-price --json --since 7d`,
  2026-10-01: 0.254 pp per million cache-creation tokens, 1.29 per million output; cache reads bounded at 0.049 and
  left out). Triage cost 0.16 pp per plan-round (adjudication 0.02, verification 0.09, rating 0.04, scoring 0.01).
  A Lite round on two vendors therefore costs about 0.36 pp of one account's weekly quota; Standard about 0.6 and
  Full about 0.8 by the same per-read rate. The study's workflows cost about 10 pp in all.
- **OpenAI on ChatGPT Plus:** 70,238 tokens per reviewer-read. The lane hit its usage limit after 31 jobs and
  1,621,093 tokens in one window (16 seed authors plus 15 reviewer-reads) and refused for about 4.5 hours, so 17
  OpenAI reviewer slots never ran and OpenAI coverage is 8 of 16 plans. The rater pass after the reset used
  1.16M tokens. Plus does not sustain 6 OpenAI reviewers a round across more than a few programs a window.
- **Google:** not run (§2).

### 4.9 The typical-case forecast
In the model at base inputs, the desk point forecast is exceeded in 22–38% of programs (the 95% bound in 1–4%), the
figure §10 item 5 left open. In the replay, the one-round ratio estimator on 4 seeds was exceeded by the desk holes
it missed on 6 of 16 plans, its 95% bound on 1 (REPORT v1 itself: 22 missed against a bound of 21).

### 4.10 Stage budgets and the reference class
The method's stages 1–6 have never run, so nothing here measures their budgets; Lite's 4.25 days and Full's 17 stay
labeled assumptions. What history measures is the research the 16 plans actually had before their freeze (one
transcript miner per plan, `evidence/timing.json`): median 0.2 calendar days and 6 active hours, 13 of 16 under a
day, the longest 8.2 days (agent-context-sync, 30 active hours). Lite's typical 6.5 days is about 30 times that
median, far past §6.3's 3x line.

### 4.11 Seed counts against plan length
At §3.9's limit of 1 seed per 25 plan lines, the median plan (about 420 lines) carries 16 seeds; only 3 of 16 plans
could carry Lite's 40. At base inputs, 16 seeds leave the residuals unchanged and widen the printed 95% bound (at 20
holes: Lite 7 to 10, Standard 5 to 8, Full 5 to 7), while the bound is exceeded in at most 3.2% of programs
(`evidence/sim/sim-base-scap16.out`).

### 4.12 Other checks
- Re-ask router recall: pending; wave B1 has not built the router (it waits on A2).
- `--setting-sources local` holds on the pinned current binary (2.1.114): with it, a probe answered NO to "is the
  mission board in your context"; without it, YES.

## 5. The model re-run (REPORT §3.12)

`calib_sim.py` is `profile_sim.py`'s program with the point-forecast rate added; its `--control` reproduces all nine
base rows of `profile_sim.out` exactly. Measured inputs: u 0.12, q 0.2, omit 0.58, b 0.2, 20 holes at freeze, false
material 0.22 (claims history shows false) and 1.13 (all false material calls). Receipts: `evidence/sim/`.

| Profile, 20 holes, measured inputs | Rounds (typical / 90th) | Hit the cap | Desk left | Invisible left | Any change after signoff | 95% bound exceeded | Point forecast exceeded |
|---|---|---|---|---|---|---|---|
| Lite, false 0.22 | 6 / 6 | 98% | 6.7 | 3.0 | 1.00 | 0.2% | 14% |
| Standard, false 0.22 | 10 / 10 | 100% | 6.5 | 3.7 | 1.00 | 0.0% | 3% |
| Full, false 0.22 | 14 / 14 | 100% | 7.6 | 4.7 | 1.00 | 0.0% | 0% |
| Lite, false 1.13 | 6 / 6 | 100% | 9.4 | 3.9 | 1.00 | 0.0% | 1% |
| Standard, false 1.13 | 10 / 10 | 100% | 13.5 | 7.3 | 1.00 | 0.0% | 0% |
| Full, false 1.13 | 14 / 14 | 100% | 21.4 | 12.6 | 1.00 | 0.0% | 0% |

The two-vendor composition (what was run) differs from the four-vendor one by at most about 1 desk hole at false
0.22 (up to 3 at 1.13, where fewer reads mean fewer false fixes). The fitted
detection model gives the same picture (Lite 7.5, Standard 7.4, Full 8.8 desk holes left at false 0.22).

**What each input costs** (Standard, 20 holes, restoring REPORT's base value one input at a time,
`evidence/sim/sim-attr-*.out`):

| Inputs | Desk left | Hit the cap |
|---|---|---|
| All measured (false material 0.22) | 6.45 | 100% |
| False material back to 0.01 | 4.79 | 27% |
| and downgrades back to 0.05 | 1.82 | 36% |
| and omissions back to 0.3 | 1.68 | 25% |
| and fix-born back to 0.1 | 1.50 | 20% |

The false-material rate decides whether the stop rule ever fires (at 0.02 per read the cap is hit in 38–55% of
programs, at 0.05 in 76–90%, at 0.1 in 87–100%); the downgrade rate decides most of what is left at signoff. Fix-born
at the measured 0.2 costs little once those two are fixed; at 0.5 it does (b rows below).

**Fix-born sensitivity at REPORT's base inputs** (the rows §3.12 said were not run; `evidence/sim/sim-base-bsweep.out`):

| 20 holes, base inputs | b = 0.1 | b = 0.3 | b = 0.5 |
|---|---|---|---|
| Lite: rounds, hit the cap, desk left, 95% bound exceeded | 6/6, 48%, 2.69, 4.2% | 6/6, 68%, 3.24, 2.6% | 6/6, 89%, 4.24, 6.0% |
| Standard | 8/10, 23%, 1.57, 3.2% | 9/10, 34%, 2.07, 3.0% | 10/10, 55%, 2.58, 3.6% |
| Full | 8/14, 10%, 1.35, 1.4% | 10/14, 17%, 1.63, 1.8% | 11/14, 27%, 2.26, 3.2% |

## 6. What follows, and what this wave changed

**Edits to REPORT.md** (priced, named sections only; each cites the field it rests on): §3.9 seed counts (§4.11),
§3.12 measured inputs, fix-born rows and the point-forecast rate (§5), §6.1's Full precondition, stage budgets and
tokens (§4.8, §4.10), and decision 4's conviction (§1).

**Not changed, because it is outside this wave's edit scope:** the triage itself. The measurements say the lever is
the materiality triage (§3.8 verification and rating, §3.11), not width, depth or seeds: the stop rule needs false
material calls near 0.02 per read or below and downgrades near 0.05. Candidate changes for whoever owns the method:
reject any finding that names no signed frame row before it reaches a rater; rate against the frame row's acceptance
criterion rather than open materiality; and count "real but not material" as a refinement at the verifier, never at
the raters. Each is testable on this replay's records (`evidence/adjudicate/` holds the ground truth for 160 items).

**Still uncalibrated:** the router (B1), Google as a vendor, the Fable composition, stage budgets, and anything
multi-round. A certificate should keep printing "uncalibrated": 16 replayed plans are not 16 programs that ran the
method.

## 7. Limits

- One round per plan. Recall, correlation and false alarms are single-round measurements; multi-round behavior is
  simulated.
- Known later holes are what history surfaced, a lower bound on what was there; the list is 78% precise by audit.
- Two vendors; OpenAI on 8 plans; Google untested; frontier slots on Opus.
- No signed frame, so §3.11's frame-row condition could not filter findings (§4.1).
- The history analysts, verifier, rater 2, scorer, auditor and adjudicator are one model (Opus 5.5); the controls in
  §4.1 and the audit in §2 are the checks on them.
