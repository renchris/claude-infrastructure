# Slot F: signals from the decision and backlog stores, measured against hand labels

**Answer first.** None of the four candidate store-side signals is good enough to set the close rung by itself. Precision ranges from 0.17 to 0.62 and recall from 0.14 to 0.36 (strict scoring, n=91 hand-labelled turns).

- **The incident turn fired s2, s3 and s4. It did not fire s1.** A research turn that only *reads* the packet store is invisible to the existing ⛔ term. That term counts only open class-C packets *this* session filed (`scripts/wrap-ledger.sh:1343-1346`, `:1483-1521`).
- **Two measured traps:**
  - (a) s4's "zero commits" clause removes the textbook cases. Research turns commit and land their own `docs/research` report, as T306 and T756 did.
  - (b) s3 (writes outside git) is mostly noise: handoff briefs, commit messages and helper scripts in /tmp.
- **The best cheap combination is a disjunction, not a conjunction:** s6 ∨ s7 (strict P=0.59, R=0.59; lenient P=0.77, R=0.63).
  - s7 = a research-shaped workflow turn that edited no code.
  - s6 = the prompt invoked /explain-decisions.
- **Within the population that matters,** the turns whose close already claims ✅ or "Good to close: yes", s7 ∨ s2c recalled 5 of 5 strict positives at P=0.33 (n=45). s2c = read the packet store and edited no code.
- **The estimated bulk of positives fires no store-side signal at all.** Q&A-style analysis ends in proposals in prose (estimated ~66–77%, wide CI). A mechanical signal can only be a *floor*. The final-text and plan-state signals (other slots) must carry the rest.

## 1. Corpus (measured)

Script: `/tmp/rpic-F/extract.py`. Log: `/tmp/rpic-F/corpus.log`.

| step | count | how |
|---|---|---|
| top-level `*.jsonl`, mtime < 14 d, 6 stores (raw glob) | 1925 | `glob ~/<store>/projects/*/*.jsonl` |
| after realpath dedupe | 1541 | `~/.claude-next/projects -> ~/.claude/projects` is a symlink (`ls -ld` ⇒ `lrwxr-xr-x … .claude-next/projects -> /Users/chrisren/.claude/projects`). The raw glob double-counted 384 files |
| after session-uuid dedupe (keep largest) | 1537 | the same uuid appears in 2 stores after a limit-recover move |
| fired peers excluded (`handoff-fire engagement marker` in first user message) | 391 | |
| no user prompt | 21 | |
| origin sessions | 1125 | |
| **CAP applied: 400 sessions** | 400 | `random.seed(20261018)`; incident session `74728043` force-included |
| turns | 1040 | turn = real user prompt → next real user prompt |

- **What counts as a real prompt.** A real user prompt is a `type:user`, non-sidechain, non-`isMeta`, non-tool_result record. Records starting `<task-notification>`, `Stop hook feedback`, `Another Claude session sent a message`, `<local-command-stdout>` or `[Request interrupted` are excluded. A slash-command `isMeta` expansion is attached to its prompt. The turn's final text is the last non-empty assistant text block of the main thread.
- **Population caveat (measured).** 191 of the 1040 turns start with `<teammate-message` and 128 are frozen-brief worker prompts (`# … brief`, `Blind reader`, `Judge`). Agent-team teammates and `claude -p` workers carry no handoff-fire marker, so the brief's "origin" filter keeps them. They are almost all NEG, which inflates TN.

## 2. Signals as implemented

All are per turn, main thread only:

- **s1:** a packet in `~/.claude/autonomy/decisions/*.json` with `session_sid == <session uuid>` and `created` inside the turn window, OR a successful `cc-decide open` Bash call. Store: 623 packets, 299 distinct sids (59 open, 425 actioned, 102 expired-actioned, 36 vetoed, 1 without status). The packet count was 628 at session start, so a compaction ran during measurement.
- **s2:** a Bash command matching `cc-decide\s+(list|show)` or `autonomy/decisions`, or a Read of a decisions file.
- **s3:** a Write to `/tmp/**`, `/private/tmp/**` or `/var/folders/**`, or a Write to `*/docs/research/**` that is not tracked now (`git -C <dir> ls-files --error-unmatch`).
  - Measured tracked check: 35 tracked, 3 missing (worktree removed), 0 untracked. **The docs/research half of s3 never fired on a still-existing untracked file. s3 is effectively "/tmp write."**
  - s3 path kinds: `tmp` 289 paths, `missing` 3.
- **s4:** (≥1 `Workflow` tool_use OR ≥2 `Agent`/`Task` spawns whose `subagent_type` matches `deep-research|workflow-lean|explore|research`) AND no successful `git commit` in the turn.
  - Commit success = Bash containing `git commit`, `is_error` false, and output without `nothing to commit|fatal:|error:|hook…fail`.
  - My first detector (a `[branch sha]` regex) found 3 commits; the corrected one found 239. Many commits run `-q` and are followed by `git log --oneline`.
- **Supplementary signals** (the brief's slot covers the decision and backlog stores):
  - s5 = successful `cc-backlog add|needs`.
  - s3md = an s3 path ending `.md`.
  - s4nc = s4 without the no-commit clause.
  - s6 = prompt contains `explain-decisions`.
  - s7 = s4nc AND zero main-thread Edit/Write to non-doc paths. Doc = `*.md`, `/docs/research/`, `/docs/plans/`, `/.claude-plans/`, `/research/`.
  - s2c = s2 AND zero non-doc edits.
  - s7 and s2c were computed only for labelled turns, by `/tmp/rpic-F/s7.py`, so the sample was not redrawn.

**Population firing counts (measured, 1040 turns, `/tmp/rpic-F/metrics.out`):**

| signal | turns |
|---|---|
| s1 | 42 |
| s2 | 59 |
| s3 | 148 |
| s4 | 36 |
| s5 | 43 |
| s3md | 8 |
| s4nc | 85 |
| s6 | 31 |
| s2∧s4nc | 14 |
| commit | 239 |
| any of s1–s4 | 239 |

## 3. Ground truth

**Labels.** POS = the turn's research or analysis produced actionable items the operator or a later implementation must act on, and this turn did not implement them. NEG = Q&A, status, no actionable output, or the turn implemented the work. A third label, **MIX**, marks a turn that implemented part of the work but whose own research left new decisions or implementation for the operator. MIX is scored both ways:

- **STRICT:** MIX counts as NEG, following the brief's "or it implemented".
- **LENIENT:** MIX counts as POS.

**Sample** (`/tmp/rpic-F/sample.py`, seed 7, `/tmp/rpic-F/sample.json`), 91 turns:

- 40 by simple random sampling (SRS) from the 239 turns where any of s1–s4 fired
- 35 by SRS from the 801 turns where none fired
- an oversample so that s1 and s4 each have ≥12 labelled turns: 8 for s1, 7 for s4
- the incident turn, T1

**Labels:** `/tmp/rpic-F/labels.tsv`, one line each with confidence and a one-line reason. Counts: 22 POS, 5 MIX, 64 NEG. 3 of the POS labels are low confidence: T165, T258, T407.

**Second set:** `/tmp/rpic-F/labels_ok.tsv`, 45 turns from the ✅-close sub-population (§5).

**Labelling uncertainty (honest):**

- One labeller (this agent), no second rater, no kappa.
- Labels were read from the prompt's first 500 chars and the final's last ~1000 chars. Spot reads of full turns were done for T232, T138, T714, T385 and T754 (`/tmp/rpic-F/turntexts.py`, `turncmds.py`).
- Interim turns ("workflow still running, I'll implement when it reports": T550, T835, T407) were labelled POS. A reviewer could call them in-progress NEG.
- Operator-action handoffs that were not research (staged `/tmp` scripts: T54, T654) were labelled NEG, because the 👤 rung already exists for them.

## 4. Results on the main sample (n=91)

Unweighted counts are TP/FP/FN/TN. The weighted columns use only the two SRS strata, with weights 239/40 = 5.97 and 801/35 = 22.89. They are very noisy (some cells hold 1–3 turns).

| signal | STRICT TP/FP/FN/TN | P | R | wP | wR | LENIENT TP/FP/FN/TN | P | R |
|---|---|---|---|---|---|---|---|---|
| s1 packets opened | 3/10/19/59 | 0.23 | 0.14 | 0.00 | 0.00 | 8/5/19/59 | 0.62 | 0.30 |
| s2 packets read | 3/10/19/59 | 0.23 | 0.14 | 0.29 | 0.06 | 7/6/20/58 | 0.54 | 0.26 |
| s3 writes outside git | 6/30/16/39 | 0.17 | 0.27 | 0.10 | 0.09 | 11/25/16/39 | 0.31 | 0.41 |
| s4 research fan-out, no commit | 8/5/14/64 | 0.62 | 0.36 | 0.60 | 0.09 | 8/5/19/59 | 0.62 | 0.30 |
| s5 backlog add | 1/4/21/65 | 0.20 | 0.05 | 0.50 | 0.03 | 3/2/24/62 | 0.60 | 0.11 |
| s3md | 2/0/20/69 | 1.00 | 0.09 | | | 2/0/25/64 | 1.00 | 0.07 |
| s4nc | 11/11/11/58 | 0.50 | 0.50 | 0.68 | 0.31 | 15/7/12/57 | 0.68 | 0.56 |
| s6 explain-decisions | 4/2/18/67 | 0.67 | 0.18 | 1.00 | 0.25 | 6/0/21/64 | 1.00 | 0.22 |
| s7 research-only fan-out | 11/8/11/61 | 0.58 | 0.50 | | | 14/5/13/59 | 0.74 | 0.52 |
| s2c | 3/9/19/60 | 0.25 | 0.14 | | | 6/6/21/58 | 0.50 | 0.22 |

Wilson 95% CIs (`/tmp/rpic-F/extra.py`):

- s4 precision: 8/13 → [0.36, 0.82]
- s6 lenient precision: 6/6 → [0.61, 1.00]
- POS rate in the unfired SRS stratum: 7/35 → [0.10, 0.36]; with high/med labels only, 4/35 → [0.05, 0.26]

**Best two-signal conjunctions (AND):**

- **STRICT:**
  - s3∧s4: 3/0/19/69, P=1.00, R=0.14.
  - s6∧¬commit: 3/0/19/69, P=1.00, R=0.14.
  - s4∧¬commit is just s4.
- **LENIENT:**
  - s3∧s4nc: 7/1/20/63, P=0.88, R=0.26.
  - s2∧s4nc: 4/0/23/64, P=1.00, R=0.15. This is the incident-shaped conjunction. It fires on 14 of 1040 turns, but strict precision is 1/4 (CI [0.05, 0.70]) because its other hits are MIX.
- Every AND buys precision with recall ≤ 0.26.

**Best two-signal disjunctions (OR):**

- s6∨s7: STRICT 13/9/9/60, P=0.59, R=0.59. LENIENT 17/5/10/59, P=0.77, R=0.63.
- s4nc∨s6: STRICT P=0.54, R=0.59. LENIENT P=0.71, R=0.63. Weighted lenient wP=0.80, wR=0.46.

**False positives, STRICT, with why they fired:**

- **s1** (10 FPs):
  - T3, T560, T581, T784: status or dispatch turns that re-filed or relayed a packet.
  - T75: /handoff dispatch.
  - T188, T232, T322, T523, T786: MIX; the session implemented and *also* filed class-C packets. These closes already led with ⛔ (27 of 40 s1-store turns have ⛔/Blocked in the final).
- **s2** (10 FPs):
  - T3, T75, T233, T482, T784, T1031: status turns. Packet reads happen on every check-in that re-lists open decisions.
  - T188, T232, T322, T523: MIX.
- **s3** (30 FPs, 83% of s3 firings):
  - Teammates writing helper scripts or commit messages: T33, T46, T108, T229, T399, T492, T598, T848, T879.
  - Handoff and recycle briefs (`/tmp/fire-*.txt`): T75, T242, T426, T491, T581, T610, T662, T688, T1027.
  - Eval workers writing `answers.json`: T500, T858, T968.
  - Operator scripts: T54, T654.
  - Implemented-and-landed turns: T863, T622.
  - MIX: T188, T232, T322, T523, T786.
- **s4** (5 FPs), all Workflow uses that were not research:
  - T31: crash-recovery recycle.
  - T381: building the disk tool.
  - T387: implementation lane.
  - T486: a `WF_OK` smoke test.
  - T599: film render.
- **s7** (8 FPs):
  - T31, T387, T486, T560: status or smoke-test workflows.
  - T622: a wave lead whose workers did the code.
  - T232, T523, T786: MIX.
  - The structural blind spot: code edited by workflow or teammate workers is invisible to main-thread edit counting.

**False negatives of s2∨s4, STRICT** (12 of 22 positives):

- s4's no-commit clause suppressed research that committed its report:
  - T714: /explain-decisions via Workflow; research copied into a repo and committed.
  - T611: redesign spec committed.
  - T618: copy deck committed.
- /explain-decisions served from a report rather than the store: T138 (read REPORT.md, never `cc-decide`).
- Investigation write-up in /tmp, no fan-out: T68.
- Prose-only analysis with a proposal and no store or agent footprint: T165, T385, T407, T754; T258 (s4nc only).
- Bug triage dispatched to another pane: T73.
- Design round with a packet filed (s1 only): T578.

**Incident turn T1.** It fired s2, s3 (`/tmp/xd/g99.md`; the report went to `/tmp/xd/REPORT.md`), s4 (9 × `workflow-lean`, 0 commits), s4nc, s6, s7 and s2c. It did not fire s1 (0 packets created in the window) or s5.

## 5. The population where the signal decides the outcome: turns whose close already claims ✅

A signal only changes behaviour when the ledger would otherwise read ✅. The selector `Good to close: yes|✅ Complete & live|✅ Complete and live|✅ Clean & landed` in the final's last 3000 chars matches 98 of 1040 turns. That is a lower bound, because the window truncates long finals (`/tmp/rpic-F/okset.py`).

- 30 of the 98 fire any of s1–s4, s4nc or s6. All 30 were labelled, plus 15 SRS of the 68 unfired.
- Strict positives: 5. Lenient positives: 9.

**Strict positives:**

- **T756.** Its close reads "✅ Good to close: yes. … Follow-on: the implementation waves in README §5 haven't started, because this pass was research only." This is the textbook case.
- **T306.** It closes "follow-on: none" while its body says "Waiting on you: write a name next to each job title…".
- **T53, T26, T580.** Line 1 reads "✅ Complete & live" over pending decision research or design picks.

| signal (STRICT, n=45) | TP/FP/FN/TN | P | R |
|---|---|---|---|
| s1 | 0/1/5/39 | 0.00 | 0.00 |
| s2 | 2/8/3/32 | 0.20 | 0.40 |
| s3 | 0/17/5/23 | 0.00 | 0.00 |
| s4 | 1/1/4/39 | 0.50 | 0.20 |
| s4nc | 3/9/2/31 | 0.25 | 0.60 |
| s7 | 3/5/2/35 | 0.38 | 0.60 |
| s2c | 2/5/3/35 | 0.29 | 0.40 |
| **s7∨s2c** | **5/10/0/30** | **0.33** | **1.00** |

LENIENT best: s2∨s7, 7/11/2/25, P=0.39, R=0.78.

Unfired SRS: 0 of 15 strict positives (Wilson upper bound ≈ 0.20, so ≤ ~14 of the 68 unfired).

FPs of s7 here are lead sessions whose waves landed code (T160, T669, T805), a read-only evaluation that rightly concluded "not now" (T488), and housing analysis with its follow-on filed (T698).

## 6. What this means for the design (inferred from the measurements above)

1. **s1 is already consumed** for class C by the ⛔ term (`wrap-ledger.sh:1483-1521`, `jq select(.session_sid == $sid)`). Of the 40 s1-store turns, 38 include a class-C packet and 5 a class-B packet; 27 of the 40 finals already lead with ⛔ or Blocked. Adding s1 as a new signal is redundant. The incident's gap is packets read or re-recommended, never filed.
2. **The no-commit clause in s4 is the wrong discriminator.** In this house a research turn commits and lands its report (T306, T756, T714, T611, T618). The working discriminator is *what* changed, not *whether* something did. Docs-only changes (`docs/research/**`, plans, `*.md`) mean research; code changes mean implementation. s7 approximates this from main-thread edits. The exact version is the commit's `git diff --name-only` path classes, which `wrap-ledger.sh` can compute from git (sibling slot A/B territory).
3. **s3 should be dropped** as a primary signal. On the main sample its precision is 0.17 strict, and 83% of firings are briefs, scripts and commit messages. On the ✅ subset it caught 0 positives. If it is kept, keep only the `.md` artifact form (s3md: P=1.00, R=0.09).
4. **s2 alone fires on every check-in that re-lists decisions.** It is useful only in a conjunction or as s2c. Its value is narrow: the incident shape, where a turn re-researched packets with conviction and filed nothing. s6 (an explicit /explain-decisions invocation) is the cleanest proxy for that shape: P = 1.00 lenient, 6/6, CI [0.61, 1.00].
5. **A mechanical store signal is a floor, not a classifier.** Positive prevalence in the unfired stratum is ~20% (CI [0.10, 0.36]); those are prose proposals with no store or agent footprint (T165, T385, T407, T754). Per the house rule "classify by the producer's literal emission, never by shape" (`cc-decide --help`, the subject_project rationale), the robust producer-side fix is for the research turn to *declare* its pending implementation. Examples: a `cc-backlog add --run` or a class-B/C packet carrying `--receipt docs/research/...`, or a plan row. The ledger can then count that declaration with `filedBy == $SID`, as it already does for needs-human rows. In this sample s5 (backlog add) fired in 1 strict positive only, so today's producers rarely declare. That makes it a protocol change, not a sensor change.

## 7. Scripts and artifacts (all under /tmp/rpic-F/)

| file | role |
|---|---|
| `extract.py` | corpus and per-turn signals → `turns.jsonl`, `corpus.log` |
| `stats.py` | firing counts and incident-turn check |
| `commitprobe.py` | shows why the first commit detector failed |
| `sample.py` | stratified sample → `sample.json`, `sample_dump.txt` |
| `labels.tsv` | 91 labels: label, confidence, reason |
| `okset.py` | ✅-close sub-population → `okset.json`, `okset_dump.txt` |
| `labels_ok.tsv` | 45 labels |
| `s7.py` | s7/s2c for labelled tids → `s7_out.json` |
| `metrics.py` → `metrics.out` | main tables, conjunctions and disjunctions, FP/FN lists |
| `metrics2.py` → `metrics2.out` | s7/s2c and ✅-subset tables |
| `extra.py` | Wilson CIs, s1 class breakdown, ✅-claim cross-tab |
| `turntexts.py`, `turncmds.py` | full-turn spot reads |

Nothing in the repo or any live store was written. Only read-only verbs were used: `cc-decide --help`, `cc-backlog --help`, and direct JSON reads of the stores.
