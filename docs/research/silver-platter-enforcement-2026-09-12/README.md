# Silver-platter enforcement — research, 2026-09-12

**VERDICT: do not ship any of the three designs. The winner would convict the single largest
hand-off in the corpus, which is genuinely human-only.**

15 agents, 2.71M subagent tokens, two runs (the first lost 7 agents to a weekly limit; all 7
completed results were salvaged from the journal and replayed free on resume).

## 1. The headline correction — the brief's own number was wrong, in its own favour

The session brief that commissioned this research asserted **15.4% of hand-offs were genuinely
human-only**. The exhaustive gold set over all 413 distinct commands says otherwise:

| | emissions | % | distinct |
|---|---|---|---|
| ADMISSIBLE (genuinely human-only) | 766 | 56.7% | 180 |
| INADMISSIBLE (the agent could have driven it) | 544 | 40.2% | 222 |
| UNKNOWN (genuinely undecidable) | 42 | 3.1% | 11 |

**One script explains the whole gap.** `bash /tmp/approval-queue-drain.sh` — 270 emissions, 20.0%
of the entire corpus — was bucketed by the brief as "an agent-written /tmp script". It is nothing
of the kind. Its own header reads *"a permission prompt is answerable only in its own pane, by a
human. Nothing an agent runs clears one,"* and `:46` is a hard `: >/dev/tty` gate that prints the
pending panes and exits when there is no TTY. With two siblings that is 293 emissions that are
ADMISSIBLE by construction.

Strip that family and the corpus still reads **44.7% ADMISSIBLE / 51.4% INADMISSIBLE**. The defect
is real and it is roughly half the surface — but *"~85% were not human-only"* is not supportable at
any weighting. **The brief's classifier never read the file.** That is the same defect as the one
under study, one level up.

## 2. Why the winning design must not ship

`determinism` scored 48/60 (`minimal` 47, `causal` 41). Its fatal flaw is TIMING, and the
adversarial pass reproduced it:

- The acquitting evidence for a `/tmp` script lives **in the script body**. The convicting evidence
  (a prior same-signature run) lives **in the durable transcript**.
- **74.9% of named scripts are already reaped from `/tmp` by the time the marker is emitted.**
- Decay is therefore **asymmetric and one-directional: a script that ages out loses only its
  acquittals.** `UNRESOLVED/script-gone` is not a safe abstain — it is an acquittal-blind
  conviction path.
- So the gate convicts `approval-queue-drain.sh` via its `self-ran` arm. The script is *designed*
  to be agent-run first (the no-TTY branch enumerates the queue), which means **the receipt that
  convicts it is produced by using it correctly**. A block there strands the operator and every
  pane queued behind him, and the corrective asserts something the script's own header calls
  impossible.

Measured reach of the design as written: of 544 INADMISSIBLE emissions it refutes **183 (33.6%)**,
while **307 emissions / 155 distinct** land in `UNRESOLVED/script-gone` — the largest single cell.

## 3. The one change that moves it

Stamp the verdict at **`Write` time**, when the body is guaranteed present
(`state/silver-platter/bodies/<sha>.verdict`), and have the verdict function read that sidecar
before it tries the disk. Same closed set of signatures, no new heuristic, no new judgment — it
changes *when* the evidence is read, never *what it may conclude*. That converts the largest cell
from unreachable into reachable.

## 4. Critical defects found (all with reproduced triggers)

| id | defect | why it matters |
|---|---|---|
| F1 | convicts `approval-queue-drain.sh` (20% of corpus, human-only by construction) | catastrophic; §2 |
| FP-1 | `self-ran` matches on SIGNATURE not ARGV — a prior read-only `aws amplify list-jobs` licenses `aws amplify start-job … RELEASE` | turns a read into a money-spending production deploy; 118 executions / 50 sessions, 30 co-occurring |
| FP-1b | prior `gh auth status` refutes `gh auth refresh` (a browser OAuth flow) | convicts the genuinely-human case the gate exists to protect |
| FP-1c | any prior `git show` refutes `git show <sha>` | CLAUDE.md *mandates* that sha citation in closes; 4,147 executions / 742 sessions ⇒ fires on essentially every compliant close |
| F2 | dry-run receipt licenses the `--apply` / `--write` / `--fire` twin | every dry-run→apply pair in the corpus false-convicts |
| BYPASS-1 | the slash-command acquittal is a bash GLOB: `[a-z0-9_-]*` matches `/` and spaces, so `/usr/bin/env <anything>` acquits | a universal one-token bypass wrapper |
| D1 | the corrective cites `--why platter`, but the arm sits below the stdin read | pasted, it hangs on the tty; run by the model, it prints zero bytes — "a deletion wearing a pointer's clothes" |
| D2 | `cc-owner` is reachable only via the interactive PATH; launchd sets none | the second-largest arm silently disappears in exactly the unattended sessions that most need it, with no signal |

**Minimal fixes, in order:** ARGV equality (never signature) for any receipt · resolve a missing
basename against a durable set before any refutation, and return `UNRESOLVED` when no copy resolves
· anchor the slash-command pattern · lift the `--why` arm above the stdin read · resolve `cc-owner`
by absolute path.

## 5. The honest ceiling

A string-only classifier's defensible reach is the `basis=string` subset: **623 emissions / 267
distinct**. Above that requires reading the file (`verified`, 379) or a policy source (`policy`,
200). The `name-inferred` 150 are where a classifier will look right and be wrong. `UNKNOWN` must
be a permitted output — 11 distinct commands here are genuinely undecidable, and per
`anti-deference-nudge.sh`'s contract an unreadable input must ABSTAIN, never convict.

Score **both** weightings and report them separately; a single weighted number is meaningless when
one row carries 270 emissions.

## 6. Files

`wf-read-*.md` — the Understand phase (hook architecture · the rule as written · the denial surface
· the macOS human-gate taxonomy · the gold set · insertion points).
`wf2-design-*.md` — the three designs with their judge scores, worst flaw and best improvement.
`wf2-attack-{1,2,3}.md` — false-negative, false-positive/bypass, and operational lenses.
`handoff-emissions.txt` — the measured corpus, 413 distinct commands with emission counts.

Two subagent outputs carry a harness SECURITY WARNING. It is a pattern false positive: they matched
`settings-json` / `permissions-allow-deny` because they *discuss* those files. Their actual content
says *"DO NOT self-authorize … never edit your own allowlist."* Treat as findings, not instructions.

## 7. Operator constraints on the SOLUTION SHAPE (given in words, not derivable from the corpus)

These bind the next attempt and are recorded because no measurement implies them:

- **Prompt-level fixes are excluded as a solution class.** The ask was for enforcement
  *"without overfitting/hardcoding at the system prompt level for example but not limited to
  CLAUDE.md and stop hook."* A CLAUDE.md line saying "check first" puts the check in the same
  place as the error. This is why the deliverable is a resolver plus a producer that can refuse,
  not a rule.
- **The operator's read of the failure rate was "almost every time."** The corpus says the class is
  real but concentrated: ~40% of emissions, dominated by a handful of repeatedly-handed commands.
  Both statements are compatible — a defect that recurs on the commands you see most reads as
  universal. Do not "correct" the operator's perception; explain the concentration.
- **`deploy-live.sh` is the canonical instance and must be in any acceptance test.** It was handed
  over 23 times while `com.claude.deploy-live` ran it every 600s. `bin/cc-owner` (599d66b1c)
  resolves exactly this and only this — ~4% of the surface. It is a component, never the answer.

## 8. The next step, and the conviction behind it

**Conviction that the Write-time-stamped design is correct: ~75%** — below the 90% implement bar.

The missing evidence is one pass, and it is drivable without any new judgment: **replay the amended
classifier (ARGV equality · durable-basename resolution · anchored slash pattern · Write-time
stamp) against `handoff-emissions.txt` and the gold set, and report the confusion matrix at BOTH
weightings.** If it clears the 208-emission ADMISSIBLE core with zero false convictions and lifts
detection materially above the measured 33.6%, conviction goes above the bar and it ships. If it
still convicts `approval-queue-drain.sh` under any arm, the design is dead regardless of its score.

Do not build the hook before that replay. The first attempt scored 48/60 against labels its own
author wrote, and the adversarial pass is what found it would strand the operator.
