# Method v1.2 dry walk, intake to the Stage 9 certificate (wave E3c, 2026-10-04)

Recorded by `bash tests/fixtures/research-kit/walk_v12.sh <scratch dir>` (exit 0); `tests/research-kit-v12-walk.bats` re-runs it. Fixture HOME, registry and records under the scratch dir, a stub courier, no vendor call, no live pilot. Paths are shortened: `<W>` is the scratch dir, repo paths are relative. The soak loop prints hours 1, 2, 24 and 25 of its 25 runs.

```text

## Part A — stage 1 by intake.py on a fresh program (REPORT.md §3.2)
$ scripts/research-kit/intake.py init --program walk --root <W>/walk-repo --profile lite --deliverable a daemon that loses 0 writes in 1000 trials --intent make it solid
research index STALE: regenerate it in a claude-infrastructure worktree with `scripts/research-kit/research-index.py` before mining (§3.2 step 1)
registered walk roots=['<W>/walk-repo'] aliases=[]
frame skeleton: <W>/walk-repo/docs/research/walk/frame.json
$ scripts/research-kit/intake.py ruling --program walk --which definition-of-complete --adopt --quote adopt it
recorded definition_of_complete
$ scripts/research-kit/intake.py ruling --program walk --which exemption --adopt --quote adopt it too
recorded exemption
$ scripts/research-kit/intake.py set --program walk --escape-cost-days 3
set
$ scripts/research-kit/intake.py contract-page --program walk
contract page: <W>/walk-repo/docs/research/walk/CONTRACT.md
frame.json method_version: 1.2
$ sed -n "/^## Profile/,/^## Your escape/p" CONTRACT.md
## Profile: lite

- Reviewers per round 8 (2 per slot set), quiet rounds to stop 2, hard cap 6 rounds, original seeds 40.
- Stages 1–6 budget 4.25 agent-days; typical total about 6.5 days; ceiling (every loop at its cap) about 12 days (§6.1). Only you can exceed it, through the signing tool.
- Method v1.2 yield ceiling: up to 3 extra stage budgets on each of stages 3 and 5, 5.25 agent-days (§12). Contact and the skeleton stop on yield, never past it.
- Stage 9 (built-artifact certification): 1 agent-day budget, 1.5 at the §6.5 overrun line (§11), with up to 3 built rounds; plus at least 24 hours of soak, elapsed time outside this ceiling.
- **ceiling with the v1.2 additions about 18.75 days (12 + 5.25 + 1.5)**. Only you can exceed it, through the signing tool.
- Forecast at the design point (10 holes at freeze), at the measured inputs (method v1.2; research-calibration REPORT §3): rounds 6 typical / 6 at the 90th percentile, the round cap reached in 100.0% of simulated programs; desk-detectable left 6.83, invisible left 2.6; chance of at least one material change after signoff 1.0; chance the 95% bound is exceeded 0.0%. Model output.
- Contrast, the pre-calibration assumed inputs (what this page stated before v1.2): desk-detectable left 1.43, invisible left 0.59, chance of at least one material change after signoff 0.84.

## Your escape cost
$ bin/cc-research ceiling --program walk
Typical total about 6.5 days; ceiling (every loop at its cap) about 18.75 days (lite profile, §6.1, plus the v1.2 yield ceiling 5.25 d and Stage 9 1.5 d) · elapsed 0 d
Waiting on you since nothing open · calendar ceiling with your waits about 18.75 days

## Part A — stage 3 ends on yield, not on the clock (REPORT.md §12.1)
$ bin/cc-research budget start --program walk --stage 3
stage 3 started at 2026-10-05T04:47:08Z
$ bin/cc-research probe --program walk --id P-1 --kind skeleton --negative-control false -- /bin/bash -c exit 1
P-1 kind=skeleton exit=1 n=1 level=E0
$ bin/cc-research yield show --program walk --stage 3
stage 3: keep probing · 0 quiet in a row of 3 needed · 1 finds in the last 6 probes, 24 per day × escape cost 3 d = 72 (keep going above 1) · 1 probes, 0 d of a 3 d ceiling
(exit 1)
$ bin/cc-research budget end --program walk --stage 3
cc-research: stage 3 cannot end yet — stage 3: keep probing · 0 quiet in a row of 3 needed · 1 finds in the last 6 probes, 24 per day × escape cost 3 d = 72 (keep going above 1) · 1 probes, 0 d of a 3 d ceiling. It ends when the last 3 probes are quiet and that product is at most 1, or at the ceiling (§12.1)
(exit 2)
$ bin/cc-research probe --program walk --id P-2 --kind skeleton --negative-control false -- /bin/bash -c true
P-2 kind=skeleton exit=0 n=1 level=E5
$ bin/cc-research probe --program walk --id P-3 --kind skeleton --negative-control false -- /bin/bash -c true
P-3 kind=skeleton exit=0 n=1 level=E5
$ bin/cc-research probe --program walk --id P-4 --kind skeleton --negative-control false -- /bin/bash -c true
P-4 kind=skeleton exit=0 n=1 level=E5
$ bin/cc-research probe --program walk --id P-5 --kind skeleton --negative-control false -- /bin/bash -c true
P-5 kind=skeleton exit=0 n=1 level=E5
$ bin/cc-research probe --program walk --id P-6 --kind skeleton --negative-control false -- /bin/bash -c true
P-6 kind=skeleton exit=0 n=1 level=E5
$ bin/cc-research probe --program walk --id P-7 --kind skeleton --negative-control false -- /bin/bash -c true
P-7 kind=skeleton exit=0 n=1 level=E5
$ bin/cc-research yield show --program walk --stage 3
stage 3: stop: the stage is quiet · 6 quiet in a row of 3 needed · 0 finds in the last 6 probes, 0 per day × escape cost 3 d = 0 (keep going above 1) · 7 probes, 0.146 d of a 3 d ceiling
$ bin/cc-research budget end --program walk --stage 3
stage 3 ended at 2026-10-05T08:17:08Z

## Part B — fixture: the known-good program demo at a signed research certificate (stages 2-8)
registry: demo certified, frame method_version 1.2, research certificate CERT-v1 signed

## Stage 9.1 — freeze the built snapshot (gate.sh built-freeze)
$ scripts/research-kit/gate.sh built-freeze --program demo --artifact <W>/artifact --wave B1 --wave B2
BUILT-FROZEN demo at 0d82d40a039f; registry -> build-certifying

## Stage 9.2 — a finding is material only with a failing test the tool ran
$ bin/cc-research built finding add --program demo --source contact --severity material --claim daemon.sh runs without set -u, so a typo'd variable expands to nothing --test-cmd grep -qx 'set -u' daemon.sh
BF-1: material open
$ bin/cc-research built finding fix --program demo --id BF-1
BF-1: still failing, stays open
(exit 1)
$ bin/cc-research built finding add --program demo --source round --severity material --claim the retry might be slow
BF-2: material rejected-no-repro — no failing test on the built snapshot, so it is not material (§11)
-- the fix lands as a new commit; the snapshot is re-frozen on it
$ scripts/research-kit/gate.sh built-freeze --program demo --artifact <W>/artifact --wave B1 --wave B2 --refreeze
BUILT-FROZEN demo at 8eb3693befe6; registry -> build-certifying
$ bin/cc-research built finding fix --program demo --id BF-1
BF-1: fixed, its repro passes

## Stage 9.3 — mutation testing of the acceptance harness, mutants as seeds
$ bin/cc-research built mutate --program demo
mutants: 10 killed, 0 survived, kill rate 1.0

## Stage 9.4 — as-built contact: empty HOME, PATH=/usr/bin:/bin, /bin/bash 3.2
$ bin/cc-research built contact --program demo --target P-3 --negative-control test -f missing.sh
BC-1: P-3 exit 0 under HOME=<empty> PATH=/usr/bin:/bin /bin/bash 3.2.57(1)-release
$ bin/cc-research built contact --program demo --target AM-1 --negative-control grep -q "echo ok" /dev/null
BC-2: AM-1 exit 0 under HOME=<empty> PATH=/usr/bin:/bin /bin/bash 3.2.57(1)-release

## Stage 9.5 — the soak: cc-research job soak, hourly for 25 hours (what com.claude.research-soak runs)
[2026-10-05T05:47:08Z] $ cc-research job soak → job soak demo: ok — 1 sample(s), all pass
[2026-10-05T06:47:08Z] $ cc-research job soak → job soak demo: ok — 1 sample(s), all pass
  … hours 3-23 …
[2026-10-06T04:47:08Z] $ cc-research job soak → job soak demo: ok — 1 sample(s), all pass
[2026-10-06T05:47:08Z] $ cc-research job soak → job soak demo: ok — 1 sample(s), all pass

## Stage 9.6 — built rounds over the snapshot (stub courier; briefs/built-reviewer.md)
$ scripts/research-kit/round.sh run --program demo --kind built --round 1 --plan <W>/repo/docs/research/demo/PLAN.md --brief skills/research-program/briefs/built-reviewer.md
round b1: 8 slots, lanes {'anthropic': 'live', 'frontier': 'live', 'google': 'live', 'openai': 'live'}, counted=True
$ scripts/research-kit/round.sh close --program demo --round b1
round b1 closed: new material 0, seeds caught 0, quiet=True
$ scripts/research-kit/round.sh run --program demo --kind built --round 2 --plan <W>/repo/docs/research/demo/PLAN.md --brief skills/research-program/briefs/built-reviewer.md
round b2: 8 slots, lanes {'anthropic': 'live', 'frontier': 'live', 'google': 'live', 'openai': 'live'}, counted=True
$ scripts/research-kit/round.sh close --program demo --round b2
round b2 closed: new material 0, seeds caught 0, quiet=True

## Stage 9.7 — the built gate: rows 20-25, the certificate
$ bin/cc-research built show --program demo
built demo at 8eb3693befe65232ef5f9603af0c299df34e1a13: findings 0 open, 1 fixed, 1 without a repro · mutants 10 killed, 0 survived · 2 contact runs · 25 soak samples
$ scripts/research-kit/gate.sh built-run --program demo
20. Built snapshot           PASS
      snapshot 8eb3693befe6; 2 build wave(s) named, all recorded done
21. Repro                    PASS
      1 material finding(s), all fixed and re-run green; 1 rejected-no-repro
22. Harness mutation         PASS
      kill rate 10/10 = 100%; 0 equivalent, 0 invalid
23. As-built contact         PASS
      1 as-built probe(s) and 1 acceptance row(s) run as built
24. Soak                     PASS
      25 sample(s) over 24.0h after 0 restart(s)
25. Built rounds             PASS
      stop quiet after 2 counted built round(s) of 3
BUILD-CERTIFIED demo: <W>/repo/docs/research/demo/built/BUILT-CERT-v1.json
$ cat built/BUILT-CERT-v1.md
Built: demo built certificate version 1, issued 2026-10-06T05:47:08Z on snapshot 8eb3693befe65232ef5f9603af0c299df34e1a13 (research CERT-v1)
Before implementation signoff: 1 material change observed (forecast about 3.8)
After implementation signoff: forecast about 0.2; at most 3 at 95% (mutant kill rate 10 of 10, lower bound 0.72; build-findable share 0.585, share assumed)
Findings: 1 material, 1 fixed, 1 rejected for no failing test
$ scripts/research-kit/gate.sh render --program demo
Research: demo version 1. CERTIFIED Oct 05 (lite profile; stopped after 2 quiet rounds)
Signed frame: 100.00% closed. 1/1 decisions · 1/1 populations enumerated two ways · 1/1 checks shown to fail first · 1/1 premises at required level · 1/1 sources
After signoff: 0 material changes (0 escapes; forecast about 6.5; at most 11 at 95%, of which about 0.5 is invisible to any reviewer, share assumed)
Split: before implementation signoff about 3.8 · after implementation signoff about 2.7 (at most 11 at 95%); build-findable share 0.585, share assumed
Decisions: 1 ruled at 90%+ · 0 ruled by you · 0 decided by default · 0 carried
Next version: 0 ideas parked · Frame defects 0 · Unasked intent 0
Residuals: 1 declared (elapsed-time 1)
Scheduled checks: 1 production or elapsed-time check with owner and date (next due 2026-11-01)
Live – · Calibration: none measured (uncalibrated)
Fingerprint: certified under m, rules r, memory x · this answer unchanged since 2026-10-05T04:47:08Z
Built: certified 2026-10-06T05:47:08Z (BUILT-CERT-v1)

## Walk end: demo is build-certified
```

## Continued 2026-10-05 (wave E3d): the implementation signature

The walk no longer ends at build-certified. After the render above (whose built line now ends
"· implementation not signed"), it goes on through §11 "Signing the implementation": the agent renders, the gate
refuses unsigned, a signature attempted under a process named claude is refused, and the fixture signer
(`tests/fixtures/research-kit/fixture_signer.py`: `bin/cc-signoff` itself with an operator's ancestry, on the
fixture store only) signs. Recorded by the same command, exit 0; the suite is now 1..11. No real signature was made.

```text
registry: demo build-certified

## Stage 9.8 — the implementation signature: the agent renders it, only the operator signs (§11)
$ bin/cc-research built signoff --program demo
Built: demo built certificate version 1, issued 2026-10-06T06:34:49Z on snapshot b392d5dd692b567dd9469cf1969905c90e650cd9 (research CERT-v1)
Before implementation signoff: 1 material change observed (forecast about 3.8)
After implementation signoff: forecast about 0.2; at most 3 at 95% (mutant kill rate 10 of 10, lower bound 0.72; build-findable share 0.585, share assumed)
Findings: 1 material, 1 fixed, 1 rejected for no failing test
Signing pins built/BUILT-CERT-v1.json = ea9ee7a437daba32ca39cd2a99f01d953f085128 (one changed byte voids the signature)
Read before signing: <W>/repo/docs/research/demo/built/BUILT-CERT-v1.md
Implementation: not signed
Operator, to sign this in your own terminal (an agent is refused):
  cc-signoff research:demo/implementation --evidence <what you read>
-- unsigned, a build-certified program is not done
$ scripts/research-kit/gate.sh built-signed --program demo
gate.sh: built-signed refused: BUILT-CERT-v1 carries no operator signature. The operator signs it in their own terminal: cc-signoff research:demo/implementation --evidence <what you read>
(exit 2)
$ scripts/research-kit/gate.sh close --program demo
gate.sh: close refused: demo is build-certified and BUILT-CERT-v1 carries no operator signature. The operator signs it in their own terminal: cc-signoff research:demo/implementation --evidence <what you read>
(exit 2)
$ scripts/research-kit/gate.sh requires --program demo --after-signoff
REFUSED demo every wave:
  - this wave follows implementation signoff and the registry state is 'build-certified': BUILT-CERT-v1 carries no operator signature. The operator signs it in their own terminal: cc-signoff research:demo/implementation --evidence <what you read>
  - no --wave given, so every block counts: pass the wave id to scope to its closure
(exit 1)
-- an agent signs: cc-signoff under a process whose name is claude
$ claude-agent-shell -c "bin/cc-signoff research:demo/implementation --evidence built/BUILT-CERT-v1.md"
REFUSED — this signing tool is descended from a claude process (<W>/claude-agent-shell at depth 1).
A signature is the operator's, made in his own terminal after looking at the
artifact. An agent may prepare it and stop there.

  Operator, to sign this:  cc-signoff research:demo/implementation --evidence <what you read>
(exit 3)
implementation signatures on file: 0 · registry: demo build-certified
-- the operator signs: bin/cc-signoff by the fixture signer (an operator's ancestry, fixture store only)
$ tests/fixtures/research-kit/fixture_signer.py research:demo/implementation --evidence built/BUILT-CERT-v1.md
SIGNED research:demo/implementation
  pinned built/BUILT-CERT-v1.json = ea9ee7a437daba32ca39cd2a99f01d953f085128 — one changed byte voids this signature
  IMPLEMENTATION-SIGNED demo: BUILT-CERT-v1 signed by the operator 2026-10-05T05:35:06Z; registry -> implementation-signed
implementation signatures on file: 1 · registry: demo implementation-signed
$ scripts/research-kit/gate.sh render --program demo
Research: demo version 1. CERTIFIED Oct 05 (lite profile; stopped after 2 quiet rounds)
Signed frame: 100.00% closed. 1/1 decisions · 1/1 populations enumerated two ways · 1/1 checks shown to fail first · 1/1 premises at required level · 1/1 sources
After signoff: 0 material changes (0 escapes; forecast about 6.5; at most 11 at 95%, of which about 0.5 is invisible to any reviewer, share assumed)
Split: before implementation signoff about 3.8 · after implementation signoff about 2.7 (at most 11 at 95%); build-findable share 0.585, share assumed
Decisions: 1 ruled at 90%+ · 0 ruled by you · 0 decided by default · 0 carried
Next version: 0 ideas parked · Frame defects 0 · Unasked intent 0
Residuals: 1 declared (elapsed-time 1)
Scheduled checks: 1 production or elapsed-time check with owner and date (next due 2026-11-01)
Live – · Calibration: none measured (uncalibrated)
Fingerprint: certified under m, rules r, memory x · this answer unchanged since 2026-10-05T05:34:49Z
Built: certified 2026-10-06T06:34:49Z (BUILT-CERT-v1) · implementation signed by the operator 2026-10-05T05:35:06Z
$ scripts/research-kit/gate.sh requires --program demo --after-signoff
CLEAR demo every wave: CERT-v1 carries nothing that blocks it
$ scripts/research-kit/gate.sh close --program demo
closed demo

## Walk end: demo is closed, by way of implementation-signed
```
