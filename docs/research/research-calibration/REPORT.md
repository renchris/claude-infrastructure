# Calibration study: the research method replayed on 16 held-out plans

Wave A3 of `docs/plans/RESEARCH_PROGRAM_BUILD.md` (REPORT §8 item 14). Run 2026-10-01, read-only on every plan and
transcript. One row per plan: `docs/research/research-calibration.jsonl`. Code, briefs and per-plan evidence sit beside
this file in `docs/research/research-calibration/`. REPORT below means
`docs/research/upfront-research-exhaustion-2026-09-30/REPORT.md`.

## 1. The answer

PENDING

## 2. What was replayed

**Plans (n = 16, all usable).** Every candidate had a freeze sha with evidence and at least 2 known later material
holes with receipts: 9 from claude-infrastructure (LIMIT_RECOVER_100P, LIMIT_DETECT_100P, HOOK_SURFACE_100P,
RESO_LATENCY_100P, RESO_SECURITY_100P, LAND_PIPELINE_V2, MACHINE_CAPACITY_V2, LIMIT_RECOVER_FLEET_V2, and REPORT v1
itself), 3 from reso-management-app (TENANT_PROVISIONING_100P, LAND_SHIP_V2, DEVICE_ENROLLMENT_BUILD), and one each
from voiceink (LATENCY_WILLOW_PARITY), sevenrooms-bridge (LAPTOP_INDEPENDENCE), agent-context-sync (CONTRACTS.md)
and the TrueMemory 2.0 plan at its round-1 sha `3b5af2c22`. Plan size at freeze: 90 to 3,290 lines, median about
420; 3 to 31 decisions.

**Known later holes.** One read-only analyst per plan reconstructed the freeze and every material hole that
surfaced after it, from the plan's own post-freeze diffs, ledgers, critique records and commit bodies
(`research-calibration/evidence/history/`). Each hole carries how it was found (desk review, build, probe, operator,
world moved), where its evidence sat at the freeze, whether it is an omission, and whether a post-freeze fix wrote
it. 435 holes are listed (40 maximum per plan; TM2's counts are complete but its list is capped). **Audit:** a
second read-only agent tried to refute 64 of the 435 (15%, four per plan, deterministic positions). 50 of 64 (78%)
survived as real, material and present at the freeze; the rest were mostly real but not material under §3.11, or
written after the freeze. Every count below that uses holes at freeze is reported raw and deflated by 0.78.

**Held out.** For each plan, the 32-row frame axis checklist (SYNTHESIS §3.5) and the escape library (the 129
desk-findable ledger rows) were rebuilt without that plan's own ledger rows (by project and by cited id) before
anything was replayed (`build_heldout.py`). The rebuild removed 0 to 25 ledger rows per plan and 0 to 2 checklist
rows (VoiceInk lost FAC-02 and FAC-03, TM2 lost FAC-21, agent-context-sync lost FAC-15).

**Bundles.** Each plan's reviewers saw only a directory exported with `git archive` at the freeze sha: the plan, the
paths it cited, and (full-context slots) the held-out checklist. No later commit, ledger or critique record was in
it. Four seeds per plan (one omission operator, three commission operators), written by OpenAI from that plan's
held-out escape library, were planted in the bundle copy; all 64 anchored verbatim and applied.

**One certification round per plan, Lite profile.** Lite's four slot sets: Opus 5.5 (full context, plan only); the
frontier slots, filled by Opus 5.5 (the "reduced diversity" composition §3.8 and §6.6 name); OpenAI
(`codex exec -s read-only`, gpt-5.6-sol at high, pinned and confirmed per run); Google not run (below). The brief is
REPORT §3.8's, with zero findings stated as a correct outcome (`research-calibration/briefs/reviewer.md`). Then: one
deduplication adjudicator; a verifier blind to who and how many raised each item; rater 1 OpenAI, rater 2 Anthropic,
rater 3 a fresh OpenAI process on disagreements (the §3.8 two-vendor rule); a scorer that matched items to the known
holes and seeds only after rating. Anthropic reviewers ran as lean workers that load no resident rules; an integrity
check over every tool call voided any slot that read outside its bundle (none did). 64 Anthropic and 15 OpenAI
reviewer-reads completed: 79 reads, 348 distinct items.

**What the replay cannot do.** It runs one round, not a program: no fixes are applied, so the fix-born rate comes
from history, and "missed in one round" cannot be told apart from "invisible to every round" (§4.3).

## 3. Measured inputs (n = 16 plans unless stated)

PENDING TABLE

## 4. Findings, one per measured input

### 4.1 False alarms
PENDING

### 4.2 Fix-born rate: about 0.2 per fix, twice the assumed 0.1, and 0.4 under an open loop
Fix-born holes per applied post-freeze fix, from history: plan median 0.21; pooled over the 15 plans other than
TM2, 58 of 319 = 0.18. TM2's open critique loop, which integrated every verified finding and added a checker rule
for each recurring class, ran at 113 of 283 = 0.40 by its own ledger convention and up to about 0.6 by cited-span
blame (`/Users/chrisren/.cache/rescomp-rebuild/tm2-loop-introspection.md` §2). REPORT v1's own two certification
passes ran at 7 of 19 = 0.37. History counts only fix-born holes that later surfaced, so these are lower bounds.
The method's controls (material-only fixes, one consistency read, no new machinery during certification) target
exactly the TM2 mechanism, so 0.2 is the expected rate under the method and 0.4 its failure mode.

### 4.3 Holes at freeze: 16 typical after the audit, inside the "strong front end" band
PENDING (adds replay-found material)

### 4.4 Invisible share
Of the known at-freeze holes that no reviewer caught in the round, history says a non-desk detector (building,
probing, production, the operator) found them later. A single round cannot separate "invisible to every reviewer"
from "hard, and found in a later round", so the share is bracketed by where the evidence sat at the freeze, per
plan mean:
- lower bound 0.02: evidence that did not yet exist at the freeze;
- point 0.13: evidence outside the bundle (transcripts, vendor pages, live systems) or not yet existing, found by a
  non-desk detector, and missed by every reviewer;
- upper bound 0.38: every non-desk-found hole the round missed.
REPORT assumes 0.05 (base), 0.10 (stress) and prices the invisible part up to `u_hi` = 0.2. The point measurement,
0.13, sits between stress and `u_hi`; the upper bound passes `u_hi`.

Desk review in one round also found 27% of the holes history attributes to building and 30% of those attributed to
probes, against 35% of those a desk reader found later: much of what was found by contact was findable at the desk.

### 4.5 Omissions: 56% of holes at freeze, not 30%
Per plan mean 0.56. One round caught 28% of omission holes against 37% of commission holes. REPORT's base uses 0.3
and stress 0.5.

### 4.6 Rater downgrade share
PENDING

### 4.7 Reviewer correlation
Over the known desk-findable holes (evidence in the plan or the repo at the freeze, found later by a desk reader;
160 holes), a detection matrix per reviewer slot gives phi between slots on the same strategy:
- Opus against Opus in the frontier slots: 0.62 (17 pairs). The model's `rho` = 1.0 treats them as one detector.
- Opus against OpenAI: 0.51 (9 pairs, the 8 plans with OpenAI coverage).
Per-read recall on those holes: full context 0.22, plan only 0.11. Fitting cert_sim's detection model to these four
moments (`fit_detection.py`) needs a much wider spread of hole difficulty than the default (`sd_d` 2.5 against 1.2)
and a large share of holes that no slot reaches in a round (0.6); the frontier-slot correlation fits at `rho` = 0.5
and the family spread at `sd_f` = 1.5. Read: the reviewers agree mostly because most holes are hard for all of
them, not because two vendors share blind spots item by item. A second Opus slot adds less than the model's
independent-slot arithmetic credits, and only somewhat less than an OpenAI slot does.

### 4.8 Quota per round
- Anthropic: one reviewer-read cost 0.05 weekly-quota points (pp) at the fitted price list
  (`cc-quota-price --json --since 7d`, 2026-10-01: 0.254 pp per million cache-creation tokens, 1.29 per million
  output, cache reads bounded at 0.049 and left out). Lite's 4 Anthropic reads plus triage (adjudication,
  verification, rater 2, scoring) cost about PENDING pp per round; a full Lite round with the frontier slots on Fable
  would draw those 2 reads at roughly 2–5x.
- OpenAI on ChatGPT Plus: 70,238 tokens per reviewer-read. **The lane hit its usage limit** after 31 jobs and
  1,621,093 tokens in one window (16 seed authors plus 15 reviewer-reads), and refused for about 4.5 hours
  ("try again at 7:26 AM"). 17 OpenAI reviewer slots therefore did not run, and OpenAI coverage is 8 of 16 plans.
  Plus cannot sustain the Lite composition across more than about 8 plans in one window, let alone 6 reviewers a
  round per §6.1's Full precondition.
- Google: not run. The provider registry marks the Gemini CLI's plan and billing UNKNOWN, and inspecting its auth was
  refused, so no paid call was risked. Every result here is the two-vendor composition.

### 4.9 Point-forecast exceedance
PENDING

### 4.10 Stage budgets and the reference class
The method's stages 1–6 have never run, so no history measures their budgets; Lite's 4.25 days and Full's 17 days
stay labeled assumptions. What history does measure is the research time these 16 plans actually took before their
freeze (one transcript miner per plan, `evidence/timing.json`): median 0.2 calendar days and 6 active hours; 13 of 16
under 1 day; the longest 8.2 days (agent-context-sync, 30 active hours). Lite's typical 6.5 days is about 30 times the
median, far past §6.3's 3x line for this project type.

### 4.11 Re-ask router recall
Pending: wave B1's router does not exist yet (B1 waits on A2). Gate row 15 stays an assumed input.

### 4.12 `--setting-sources local`
Holds on the pinned current binary (2.1.114): with the flag, a probe answered NO to "is the mission board in your
context"; without it, YES.

## 5. The model re-run (§3.12)

PENDING

## 6. Edits made to REPORT.md

PENDING

## 7. Limits

- One round per plan. Recall, correlation and false alarms are single-round measurements; the stop rule's
  multi-round behavior is simulated, not observed.
- Known later holes are what history surfaced, a lower bound on what was there; the audit shows the list itself is
  78% precise.
- Two vendors, and OpenAI on 8 plans only (lane walled). Google untested.
- The frontier slots ran on Opus, so the Fable composition's diversity is not measured.
- One verifier and two raters per item; the reviewers were told material only, and no reviewer returned zero
  findings (4 to 19 per slot).
- History analysts, verifier, rater 2, scorer and auditor are all one model (Opus 5.5).
