# Exhaust, then proceed: method v1.3 for the no-take-backs research program

Status: in progress (2026-10-16). Dispatched by the TrueMemory 2.0 program lead (pane research-kit-22).

Scope (frozen): (1) this report finds, with receipts, every place the method (REPORT.md v1.1/1.2,
`docs/research/upfront-research-exhaustion-2026-09-30/`), the skill (`skills/research-program/SKILL.md` + briefs) and
the kit (`scripts/research-kit/`) can leave a program waiting on elapsed time, a future date, data accrual, a third
party, or an all-or-nothing gate row; (2) a designed method change, v1.3, that turns each such wait into "proceed with
a FILED row" (owner, due, closing probe, re-check at build, falsifier) without weakening any evidence standard (a
sealed read stays honest; a signature stays the operator's; nothing measured is claimed before it is measured);
(3) the kit, skill and REPORT changes built red-first, landed and live; (4) a hand-off note for the TrueMemory 2.0
lead listing exactly what to run on truememory-2-0 under v1.3 (this session does not edit its records).

## The ruling: the operator's words (2026-10-16, verbatim)

These are the receipt for every change below.

1. "All engines go, no idling or waiting on timestamps in the future: we have to drive through the 100.00/100.00
   complete 100th percentile research, then ... plan, then ... implementation, with all the resources we have across
   our four /accounts of usage. In-action and non-decisions and non-movement and idling is not an option. We have to
   research exhaustive perfection for what is in our physical grasp and then proceed. Do not wait on hypotheticals of
   impossible reach."
2. "we want to ensure that moves forward not only here but upon new uses and work as well; not to research and then
   park and idle spinning our wheels; we have to research exhaustively until we cant no more and then instead of
   stopping we need to proceed"
3. "Can't forever keep moving goal posts"
4. "Always and and improve on new information. but we really want upfront exhaustive research and work rather than
   iterative research, move goal post, repeat, and never complete" (relayed by the program lead, 2026-10-16 09:08).

## 1. The answer

The method already proceeds past most waits: decisions convert at their due date and descope only their own closure
(§5.6), a stage overrun files a "proceed unless you veto" packet and keeps working (§6.5), residuals and not-yet-true
premises are FILED with owners (§3.10 rows 4 and 11), and change control after signoff pauses only the closure of an
escape (§5.3). Six places still park a whole program, or lose the finish line:

1. **Gate row 15 is all-or-nothing on data accrual.** It reads a sealed set or FAILs, and one FAIL row withholds the
   certificate. On truememory-2-0 every other row passes or is FILED, and the certificate waits on a held-out set that
   accrues from about 2026-11-04 to 2026-11-24, plus a 7-day cap (W-01).
2. **Filed dues are calendar guesses.** A not-yet-true filing's `due` is a date; past it, row 4 fails. The six
   truememory-2-0 filings were re-dated the same day because their dates assumed a build start the certificate gate
   made impossible (W-03).
3. **Stage 9 is version-gated.** A program whose frame predates method 1.2 can never certify its build, so its
   ~205 forecast after-signoff changes have no counted home (W-04, W-10).
4. **A dead vendor lane pauses the program with no actuator.** The contract page says "pauses on one operator step …
   the default fires after 48 h", but no code files that default or records the degraded frame (W-05).
5. **One-shot spends have no practice path,** except the relay record since ecf9b962d: the sealed read cannot be
   rehearsed, so a program waits rather than risk it (W-06).
6. **Nothing at intake looks for these waits.** Each truememory-2-0 wait surfaced late: the held-out accrual at the
   certifying run, the due-date clash at filing, the one-shot relay at rehearsal, the dead rater lane at rating (W-07).

Method v1.3 turns each into "proceed with a FILED row": an owner, a due keyed to an event (a wave start or the
certificate's issue), a closing probe, a re-check at build, and a falsifier. Row 15 becomes a scheduled read that
gates only the waves that depend on the router. Dues key on events. Stage 9 can be adopted by a running program on
the operator's signature. A pre-signature dead lane proceeds on two vendors under the frame signature. The sealed read
gets an uncounted practice run. Intake maps five new checklist rows that front-load every wait. No evidence standard
moves: the sealed read keeps every guard it has, every signature stays the operator's, and a FILED row never prints as
PASS (§3).

## 2. Findings: every place a program can wait

### 2.1 How this was researched, and its limit

The brief planned one multi-agent workflow per phase with adversarial skeptics. That could not run: this session was
fired by the truememory-2-0 lead with a brief naming the program, so the re-ask router labeled it a program session
(`by: envelope`, label `other`; `scripts/research-kit/router.py:20-25`), and the research block denies Agent, Task,
Workflow and `handoff-fire.sh` while that program certifies (`router.py:1681-1686`). The block was not worked around.
Every receipt below was read first-hand in one context, and each finding was checked against the code path that
would let the program proceed (the skeptic question "does it already proceed?"). Finding W-15 records this limit as a
wait of its own.

### 2.2 The census

Kinds: accrual, elapsed time, calendar due, third party, all-or-nothing row, one-shot spend, load, version gate.
"Proceeds today" means the program keeps working while the wait runs.

| ID | Wait | Kind | Receipt | Proceeds today? | v1.3 disposition |
|---|---|---|---|---|---|
| W-01 | Row 15 reads a sealed held-out set or FAILs; a stratum `--await`ing a fresh set makes `evaluate` refuse, so the certificate waits for the set to accrue | accrual, all-or-nothing | `lib/gate_rows_b.py:476-521`; `heldout.py:62-76`; ruling `915d7fb98b7f` (`docs/research/reask-row15-rulings-final-2026-10-08/REPORT.md:140-160`); TM2 lead notes 2026-10-16 12:51Z | No | Scheduled read, FILED (§3.1) |
| W-02 | The read starts only at 1-min load ≤ 40 within a 4 h start cap, 12 h total | load | `heldout.py:70-74` | No (spends nothing; row FAILs) | Kept as the read's condition; the scheduled read absorbs the retry (§3.1) |
| W-03 | A not-yet-true filing's `due` is a calendar date; row 4 FAILs once it passes | calendar due | `lib/cli_records.py:466`; `lib/gate_rows_a.py:326-327`; kit `40158a730` (refile) | Yes, until the date | Event-keyed dues (§3.2) |
| W-04 | Stage 9 refuses a frame without `method_version` ≥ 1.2 | version gate | `lib/built.py:37`; `lib/gate_built.py:91`; TM2 `frame.json` has no `method_version` | No path at all | Signed adoption (§3.3) |
| W-05 | A dead lane at the contract page "pauses on one operator step"; the 48 h default has no actuator, and `degraded` is written only by hand into `frame.json` | third party, elapsed | `intake.py:471-478`; `lib/kit.py:174` (unused); readers `lib/round.py:114-306`, `lib/gate_rows_b.py:378` | No | Degrade before signature, under the frame signature (§3.4) |
| W-06 | The sealed read is one-shot (two reads per stratum, a FAIL final) with no practice run; rater slots have 3 attempts | one-shot spend | `heldout.py:62-76`; lead notes 09:29Z-10:02Z (H-RH-2 rater 2 spent 3/3 on an `agy` sandbox defect) | Partly (relay practice, ecf9b962d; lost-slot rule, 56f1c3a07) | Practice rule; `gate.sh read --practice` (§3.5) |
| W-07 | No intake row asks for accruals, third parties, one-shot spends, event keys or version-gated stages | late discovery | `skills/research-program/checklist.jsonl` (FAC-01..33); TM2 lead notes 2026-10-16 (four late finds) | n/a | FAC-34..38 for 1.3 frames; the certificate counts late filings (§3.6) |
| W-08 | A scheduled component needs a scheduler-started launchd run, with no residual path; loading the job is an operator migration | third party, elapsed | `lib/gate_rows_a.py:556-566` | No | Front-loaded by FAC-37 (§3.6); built only as a census row |
| W-09 | Stage 9's soak needs 24 h and 24 samples after the last fix | elapsed | `lib/gate_rows_built.py:332-397`; `lib/kit.py:189-191` | No | Unchanged in v1.3; filed as the next change (§4) |
| W-10 | Rounds stop at R_max with 0 quiet rounds; TM2's forecast is ~205 changes after signoff | finish line | `lib/gate_rows_b.py:605-632` (row 17 passes at the cap); TM2 lead notes 12:47Z | Yes (cap passes) | Stage 9 adoption counts them as changes, not take-backs (§3.3) |
| W-11 | Stage overrun: class B "proceed" with a 24 h veto window | elapsed | `lib/gate_sweep.py:183-205`; `lib/cli_core.py:464-467` | **Yes**: the model to generalize | Kept |
| W-12 | A class-C decision waits until its due date, then converts to class B and descopes its closure | third party, calendar | `lib/gate_sweep.py` docstring step 2; REPORT §5.6 | Yes, outside the closure | Kept; event keys allowed |
| W-13 | Freshness: a re-check within 24 h of the gate; credentials valid for the build window + 7 days | elapsed | `lib/gate_rows_b.py:151-178` | Yes: in grasp (re-run the probe; renewer probe) | Kept |
| W-14 | Change control after signoff: an escape pauses only its closure; frame omissions gate only theirs | third party | REPORT §5.3-§5.4 | Yes | Kept |
| W-15 | A lead-fired session working on the method itself inherits the program's research block | third party | `router.py:20-25`, `:1681-1686`; this session's route record | No (operator kill switch only) | Operator decision filed (§4) |
| W-16 | The rehearsal relay: one record and one re-test | one-shot spend | `lib/gate_rows_b.py:450-474` ("relay unstable" still passes) | Yes, with practice | Kept |
| W-17 | A third read of a stratum, a reopen, an extension, the implementation | signature | `scripts/lib/operator_sign.py:56-69` | Signature stays the operator's | Kept |

Two TM2 waits are not method defects: the operator's open class-C packets (§5.6 already bounds them), and the 1-min
load above 400 on 2026-10-16 (`uptime` at 09:09), which W-02's bound already handles.

## 3. Method v1.3: exhaust, then proceed

**The rule.** Before a stage ends, work every route in physical grasp until none is left. What only time, accrual or
a third party can settle becomes a FILED row with five parts: an **owner**, a **due keyed to an event**, a **closing
probe**, a **re-check at build** (`gate.sh requires` refuses only the waves that rest on it), and a **falsifier** (the
command whose exit 0 makes the row moot). A FILED row prints as FILED, never as PASS, and is carried on the
certificate. A wait that cannot be made into such a row without weakening an evidence standard stays a wait, but it
is found and scheduled at intake (§3.6), so it never surprises.

### 3.1 Row 15 becomes a scheduled read

When a stratum of the router's instrument awaits a fresh set (`heldout.py instrument --await`), the read is not in
grasp: no route makes the data exist sooner. The lead then files a scheduled read:

```
cc-research read file --program P --row 15 --awaits "<what accrues>" --owner "<who>" \
  --due cert+7d --falsifier "<cmd: exit 0 once the read is recorded>" [--blocks-wave W ...] --why "<…>"
```

It refuses while every stratum is pinned (the read is in grasp: run it). With a live filing, row 15 prints FILED
(awaits, owner, due, the waves it blocks) and decrypts nothing. The certificate issues with row 15 carried. When the
set is ready, `gate.sh read --program P --row 15 --consent-sealed-read` spends the read through the same
`heldout.evaluate` call, and records PASS or FAIL in `scheduled-reads.jsonl`. `gate.sh requires` refuses the filing's
waves until a PASS is recorded, and a FAIL keeps them refused.

**Does it keep the read honest?** Each guard of the read, and what v1.3 does to it:

| Guard (source) | v1.3 |
|---|---|
| Unseen items, sealed once (`heldout.py:24-31`) | Unchanged: the same set, sealed by the same verb |
| Read consent per run (`a7fd5e2ee7c8` guard 1) | Unchanged: `gate.sh read` needs `--consent-sealed-read` |
| A real router command, not `off` | Unchanged: the same `evaluate` call |
| Only after every other row passed in the same run | Replaced by its purpose: the newest certificate exists, carries no FAIL row and row 15 FILED, and no reopen is signed after it. A read is never spent while the certificate cannot issue |
| Every stratum pinned | Unchanged: the read refuses while any stratum awaits |
| At most two reads per stratum; a third needs a signature | Unchanged |
| Real-load figures on record; load bound 40; caps | Unchanged |
| A FAIL is final for the items read | Unchanged, and the dependent waves stay refused |

What changes is what the certificate claims. It says row 15 is FILED with a scheduled read, not that the router
passed. Ruling `915d7fb98b7f` keeps its meaning: "if everything else the TrueMemory 2.0 certificate needs is ready
first, wait at most 7 days, then read v5 as it stands". Everything else being ready is now the certificate's issue,
so the 7-day cap is `--due cert+7d`.

**The residual risk, stated.** Until the read, the router's recall on subtle re-asks and pushback is unmeasured on
fresh data. A missed relay that is labeled `other` still denies every research verb (`router.py:1641-1686`), so the
exposure is a re-ask labeled work-order or new-idea during the build. The certificate prints the row as FILED, so the
claim and the exposure are both visible. Conviction that this keeps the read honest: 90 (two guards were re-derived
from their purpose, not copied; the rest are the same code path).

### 3.2 Dues keyed to events

A due may be a date or an event spec, `<event>+<N>d`, where the event is a build wave's start (`W1+30d`) or the
certificate's issue (`cert+7d`). A wave starts when `gate.sh requires --program P --wave W --start` admits it, which
appends one row to `waves.jsonl`; `handoff-fire.sh --requires-gate` passes `--start`. Until its event happens, a keyed
due is pending and never past; after, it resolves to the event plus N days. `premise file` and `read file` accept
both forms. Dates stay legal, and the method says to prefer events.

### 3.3 A running program can adopt Stage 9

`cc-signoff research:<slug>/adopt/stage9 --because "<why>"`, run by the operator, lets a program whose frame predates
1.2 run Stage 9 (`built-freeze`, `built-run`, the implementation signature) without editing `frame.json` (which would
void the frame signature and the last round's snapshot). Rows 18 and 19, which judge stages 3 and 5 as they ran, stay
1.2-only: a program cannot re-run its past. A Stage 9 finding is then a counted change against the forecast, not a
take-back (§11), which is the home W-10's ~205 forecast changes lacked.

### 3.4 A pre-signature dead lane proceeds on two vendors

`intake.py set --program P --degraded "two vendors" --restore-probe P-…` records the degraded frame before the
signature, refusing unless the newest preflight has exactly one dead lane and at least one recorded probe tried to
restore it (exhaust first). The contract page then renders, with "degraded: two vendors" on it, and the operator's
frame signature is the acceptance. There is no 48-hour pause. A lane that dies after the signature still voids the
rounds it touches (row 13); that case is unchanged (§4).

### 3.5 Every one-shot spend gets an uncounted practice path

| One-shot spend | Practice path |
|---|---|
| Rehearsal relay record and re-test | `cc-research rehearse trial --practice` (ecf9b962d) |
| Sealed held-out read (row 15) | `gate.sh read --program P --row 15 --practice` (new): every precondition of the read, and the router over the clear tuning prompts, decrypting nothing and logging no read |
| Rater and reviewer slot attempts | `courier.sh preflight` (lane liveness); the lost-slot rule (56f1c3a07) records a slot whose every outcome agrees |
| Stage 9 soak restarts, mutation re-runs | Not one-shot in the same sense: each is a re-run of a measurement, capped |

### 3.6 Front-load the waits at intake

A frame stamped 1.3 must map five more checklist rows (gate row 1), so every wait is named at intake with its filing:

- FAC-34: every data accrual a gate row or build wave needs (a sealed set, samples, trials), with its expected date
  and its filed row.
- FAC-35: every third party whose act a row needs (an operator signature or answer, an upstream merge or release, a
  counterparty, a vendor lane), with the routes tried and its filed row.
- FAC-36: every one-shot spend (a sealed read, a counted record, a re-test, an attempt budget), with its practice path.
- FAC-37: every elapsed-time check or scheduled component (a soak, a freshness window, a scheduler-started run), with
  the wave that runs it.
- FAC-38: every filed due keyed to an event (a wave start or the certificate's issue), not a calendar guess.

The certificate prints how many FILED rows were filed after the freeze: each is a wait the intake missed, and the
count is the front-loading's own measure.

## 4. Not changed in v1.3, and why

- **W-09, the soak.** Converting it into a FILED row would let `close` follow a soak that has not finished; keeping
  `close` behind the soak is the honest form, and that is a change to Stage 9's states. It is filed as the next change,
  not built here.
- **W-05 after the signature.** A lane that dies mid-certification voids its rounds (row 13). Proceeding there would
  count a two-vendor round under a three-vendor signature, which only the operator can accept.
- **W-15, the block on method work.** Changing which sessions the research block covers is a change to a guard. It is
  filed as an operator decision with the options measured.
