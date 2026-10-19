# Slot G: signals from the prompt and close text (p1 to p4)

**Answer first.** The close text is where the signal lives. The prompt is not.

- **p2 strict (`p2s`)** fires when the close carries a recommendation, conviction or % marker AND also says "nothing of mine is open / read-only / follow-on: none / nothing to do". It caught **4 of 4** hand-labelled misreported closes (✅ while research-born work waits), incident included.
  - In-sample precision for misreport: **4/12**.
  - It fires on **47 of 1877 turns (2.5%)** in 39 of 347 sessions (measured, `eval.py`).
- **p1, the research-intent prompt regex,** is nearly useless here.
  - Recall is **1/15**.
  - **67 of its 90 fires** match only the `/research` alternative, i.e. a path like `docs/research/` inside a recycled successor brief.
  - It does not fire on the incident prompt (`/explain-decisions`).
- **p3 (no `Scope (frozen):` line + tool count)** reduces to "tool count". `Scope (frozen):` is absent from 1591 of 1877 turns (85%).
- **p4 (≥3 actionable list items, no commit)** mostly fires on status recaps. 10 of its 30 fires are recap prompts.
- **Best conjunction:** `(p2s OR p4) AND tools≥3`.
  - Against the state ground truth: in-sample TP 10 / FP 5 / FN 5 / TN 70, so P 0.67 and R 0.67.
  - Against the misreport ground truth: R 4/4 with 11 FP.
  - The `tools≥3` threshold was chosen after looking at the FPs. Treat it as unvalidated.
- **Alarm inflation on pure status questions is low.**
  - Of 57 "Good to close?"-class prompts, p2s fires on 4 (7.0%) and p4 on 0.
  - 3 of those 4 are ✅ closes that still list older, research-born decisions with recommendations under the verdict line. That is arguably the same harm, not noise.
- **Biggest measurement trap:** **158 of 1877 final texts are short watcher heartbeats** ("Still quiet, the watcher is re-armed").
  - Any close-text signal reads the heartbeat and misses the real close.
  - A second real instance of this exact complaint (2026-10-09, "So we completed research but we didnt implement?") is invisible to every signal for this reason, and also because its real close only said "the five decisions in the report".

All numbers below are **measured** unless marked *estimated*. Scripts are in `/tmp/rpic-G/`.

---

## 1. Corpus (measured, `/tmp/rpic-G/build.py` → `/tmp/rpic-G/corpus.final.log`)

| step | count | how |
|---|---|---|
| top-level `*.jsonl`, mtime < 14 d, 6 stores, after excluding transcripts named in any `~/.claude*/cc-fired/*.json` `.transcript` (812 stamp transcripts) | 1588 | `glob ~/<store>/projects/*/*.jsonl`; 336 excluded by stamp |
| session-uuid dedupe (keep largest copy) | 1257 | 331 copies folded. limit-recover copies a transcript into another store under the same uuid, and `~/.claude-next/projects` is a symlink to `~/.claude/projects` (slot F §1). |
| shuffled with `random.seed(18)`; incident `74728043` force-included first | all 1257 drawn | |
| skipped: non-`cli` entrypoint (`claude -p` / sdk workers) | 581 | `entrypoint` field present and never `cli` |
| skipped: no genuine human prompt (incl. agent-team teammates whose every prompt is `<teammate-message>`) | 210 | |
| skipped: inbound `HANDOFF-ENGAGE-` marker in the first prompt (fired peer, `hooks/lib/origin-identity.sh:220-230`) | 115 | |
| skipped: teammate, first user record `<teammate-message` | 1 | |
| **origin sessions kept** | **350** (347 contribute turns) | **CAP 400 was NOT reached**: the whole 14-day origin-interactive population is 350, so this is a census, not a sample |
| **turns** | **1877** | |

- **Turn definition.** A turn runs from one genuine human prompt to the next. The turn's final text is the last non-empty main-thread assistant text block. A genuine prompt is one of these:
  - a `type:user`, non-`isMeta`, non-sidechain, non-tool_result record;
  - an `attachment.queued_command` with `commandMode:"prompt"`. 292 turns start this way: mid-turn typed prompts, which exist only as attachments.
- **Machine prompts excluded** (regex in `build.py` `MACHINE`): `<task-notification>`, `Another Claude session sent a message`, `Stop hook feedback`, `<local-command-`, `Caveat:`, `[Request interrupted`, bash-mode records, compaction continuations, `<teammate-message`, `<agent-message`.
  - A slash command is reconstructed as `/<name> <args>`, which is what the UserPromptSubmit hook sees. Its `isMeta` expansion is kept separately for labelling.
- **Difference from slot F.** F kept `claude -p` workers and teammates (its own §1 caveat: 191 + 128 such turns, almost all NEG). G excludes them, so the TN pool here is genuine operator turns.
- **Two iterations were discarded, both logged.**
  - Run 1 had no teammate exclusion and no uuid dedupe. It had 239 duplicate turn keys and 56 agent/teammate-message prompts (measured).
  - Labels from earlier draws were reused by `(sid8, ts)` key.

## 2. Signal definitions (exact)

- **p1, research-intent prompt.** This is an exact replica of `hooks/research-precognition-nudge.sh:78-85`: the `<task-notification>` early exit, then the `INTENT` ERE with `grep -qiE`, which matches line by line.
  - **Verified identical on every turn.** `/tmp/rpic-G/verify_p1.py` runs the real hook from the worktree with `CC_RESEARCH_ROUTER=off` and HOME set to a scratch dir. Result: `agree 1877 disagree 0`.
  - The router branch (`:27-71`) is out of scope. It only applies to research-program sessions and replaces the nudge.
- **p2 (loose).** The final text matches `REC` = `recommend|conviction|\b\d{1,3}\s?%|\bshould\b|next step` (or has ≥3 table rows) AND `NOTHING` = `nothing (left |more |else )?to do|nothing (of mine )?is open|read[- ]only|no repo (was )?changed?|follow-on: none|no (code |file |repo )?changes? (were |was )?(made|needed)|nothing to (commit|ship|land)`.
- **p2s (strict).** Same, but `REC_STRICT` = `recommend|conviction|\b\d{1,3}\s?%`. This drops "should", "next step" and tables.
- **p3_T.** No `Scope (frozen):` line anywhere in the session up to and including the turn (the `hooks/dod-persist.sh:78` convention) AND main-thread tool_use count ≥ T, for T ∈ {10, 20, 40, 80}.
- **p4.** The final text has ≥3 list items (`-`, `*`, `•`, `N.`/`N)` or a non-separator table row) whose body starts with an imperative verb (a 70-verb list in `signals.py`) or contains a 12-hex id with ≥1 letter and ≥1 digit. AND the turn ran no `git commit`, `git push`, `git merge`, `ship-land`, `/ship` or `cc-land` (Bash) and no `Skill: ship|land`.
- **status (narrow), the alarm-inflation class.** The prompt is ≤200 chars and matches `/accounts|/status|are we done|is it done|what's the state|status?$|where are we|what's left|anything left/open|good to close|can I close|safe to close|…` (`signals.py` `STATUS`). This gives 57 turns (list in `/tmp/rpic-G/status.out`). By inspection, 55 of the 57 are close or status asks. The 2 strays are "Refer back to our conversation with Ash … Pull anything else" and "Anything else for us to explore …".
- **recap (broad).** status, OR a prompt ≤400 chars matching `SCQA|outcome of the session|current steps|where we are|roadmap|todos|checking in|/are-we-done|what's next|working or idling|follow-on|loose ends`. This gives 196 turns.

**What the `NOTHING` arm really matches** (measured over the 47 p2s fires, `/tmp/rpic-G/p2parts.py`):

| phrase | p2s fires |
|---|---|
| `nothing of mine is open` | 27 |
| `read-only` | 13 |
| `follow-on: none` | 12 |
| `nothing to do` | 7 |

- The first and third are the mandated yes-verdict wording of the close template, `hooks/lib/close-shape.sh:179`: `Good to close: <yes — nothing of mine is open; follow-on: …>`.
- "nothing to do" is the ✅ rung readout at `scripts/wrap-ledger.sh:2492`.
- So **p2s ≈ "the close verdict is yes / ✅" AND "the close carries a recommendation or conviction %"**. REC tokens: `%` 41, `recommend` 25, `conviction` 8. 23 of the 47 fires have line 1 starting with ✅.

## 3. Ground truth (hand labels)

**Rule (fixed before scoring, applied to every row).** A turn is **POSITIVE** iff all three hold:
- (a) the turn itself ran an investigation (≥1 read/search/agent/workflow tool producing findings);
- (b) its findings end in ≥1 concrete next action that the turn did not complete. The action can be an agent implementation, a filed or asked operator decision with a recommendation, or an operator to-do the research recommends;
- (c) the recommended action is not inaction.

A turn is **NEGATIVE** for any of these:
- a build/implementation turn;
- research still in flight;
- a 0-tool or 1-tool recap of pending items that predate the turn;
- a verdict of "don't do it";
- recommendations already implemented in the turn;
- informational Q&A.

**Second truth `gt_mis`.** POSITIVE AND the close leads with a done/✅/yes verdict that hides the pending work. This is the incident's harm.

**Sample.** The corpus is split into strata by priority S (status) > A (p2) > B (p4) > C (p1) > D (p3_20) > E (none):

| stratum | S | A | B | C | D | E |
|---|---|---|---|---|---|---|
| corpus size | 57 | 66 | 27 | 80 | 274 | 1373 |
| hand-labelled | 14 | 16 | 14 | 14 | 14 | 18 |

- That is **90 labelled turns** (`/tmp/rpic-G/sample.json`; labels with one-line reasons in `/tmp/rpic-G/labels.tsv`, 112 rows including 22 extra rows from discarded draws).
- **Method caveat.** Within a stratum, turns already labelled in earlier random draws (same definitions, pre-dedupe corpus) were taken first, then filled at random (`sample.py`). The bias is mild but nonzero.
- **Weights.** Each sampled turn stands for S 4.1, A 4.1, B 1.9, C 5.7, D 19.6 or E 76.3 corpus turns. Weighted figures are *estimates*. The E weight means **one** E positive is worth 76 turns, so weighted recall has very wide error bars. In-sample figures are the primary result.

**Positives: 15 of 90 in-sample; weighted estimate ≈142 of 1877 (7.6%).** **gt_mis: 4 of 90; weighted estimate ≈16 of 1877 (0.9%).**

| sid8 ts | mis | p1 | p2 | p2s | p3_20 | p4 | why |
|---|---|---|---|---|---|---|---|
| 74728043 10-19T02:15 | **Y** | . | ✓ | ✓ | ✓ | ✓ | INCIDENT: 9-agent re-check, 56 decisions pending, close ✅ "nothing to do" |
| 978fd287 10-06T03:07 | **Y** | . | ✓ | ✓ | ✓ | . | "SCQA … and /explain-decisions": 2 decisions with recommendations (reboot today), line 1 ✅ yes |
| 99b5cd2f 10-07T01:55 | **Y** | . | ✓ | ✓ | . | . | 17-file investigation; "build not started, needs 4 rulings" yet ✅ "follow-on: none filed" |
| 99b5cd2f 10-07T03:10 | **Y** | . | ✓ | ✓ | . | . | 12-report teardown feeding that build; ✅ "repo untouched; follow-on none" |
| 6cad6b17 10-12T01:03 | N | . | ✓ | ✓ | ✓ | . | apartment research → 2 operator calls, named on line 1 |
| e7659abe 10-16T03:49 | N | . | ✓ | ✓ | . | . | landlord research → 3 checks for Saturday |
| c5cd1b06 10-04T06:39 | N | . | ✓ | ✓ | . | . | 17-agent audit → ranked fixes not built |
| 5759497b 10-18T06:03 | N | . | . | . | . | ✓ | recommends building a load skill |
| 6defb493 10-10T16:22 | N | . | . | . | . | ✓ | /explain-decisions: deploy-now etc., "no, not done" |
| 404651b1 10-05T23:14 | N | . | . | . | ✓ | ✓ | found a reconciler defect → ⛔ fix-now decision |
| 05af12f0 10-12T22:09 | N | . | . | . | . | ✓ | 9-agent research → "register in TX this week" |
| e52f1f63 10-19T02:38 | N | ✓ | . | . | . | . | kitty switch never ran → ⛔ decision |
| 5dd11e6c 10-12T17:07 | N | . | . | . | ✓ | . | cert round 2 found 13 problems → ⛔ decision 72% |
| 92928fee 10-10T04:44 | N | . | . | . | ✓ | . | status Q; 23-tool diagnosis → restart pending an operator Ctrl-U |
| 6defb493 10-10T00:19 | N | . | . | . | . | . | operator: "So we completed research but we didnt implement?" → 3 builds recommended |

## 4. Precision and recall (measured in-sample; *estimated* stratum-weighted in brackets), `/tmp/rpic-G/eval.py` → `/tmp/rpic-G/eval.out`

### vs `gt` (state: research-born action pending), 15 positives of 90

| signal | TP | FP | FN | TN | P | R | [wP / wR] |
|---|---|---|---|---|---|---|---|
| p1 | 1 | 16 | 14 | 59 | 0.06 | 0.07 | [0.06 / 0.04] |
| p2 | 7 | 11 | 8 | 64 | 0.39 | 0.47 | [0.39 / 0.20] |
| **p2s** | 7 | 5 | 8 | 70 | **0.58** | 0.47 | [0.58 / 0.20] |
| p3_10 | 8 | 21 | 7 | 54 | 0.28 | 0.53 | [0.10 / 0.34] |
| p3_20 | 6 | 17 | 9 | 58 | 0.26 | 0.40 | [0.12 / 0.27] |
| p3_40 | 0 | 13 | 15 | 62 | 0.00 | 0.00 | |
| p3_80 | 0 | 6 | 15 | 69 | 0.00 | 0.00 | |
| p4 | 5 | 11 | 10 | 64 | 0.31 | 0.33 | [0.34 / 0.08] |
| p2s ∧ p3_20 | 3 | 0 | 12 | 75 | 1.00 | 0.20 | |
| p2s ∨ p4 | 11 | 16 | 4 | 59 | 0.41 | 0.73 | [0.45 / 0.26] |
| (p2s ∨ p4) ∧ ¬status | 11 | 15 | 4 | 60 | 0.42 | 0.73 | |
| **(p2s ∨ p4) ∧ tools≥3** † | **10** | **5** | **5** | **70** | **0.67** | **0.67** | [0.73 / 0.23] |
| p2s ∧ tools≥3 † | 6 | 1 | 9 | 74 | 0.86 | 0.40 | |
| (p2s ∨ p4) ∧ ¬recap | 9 | 7 | 6 | 68 | 0.56 | 0.60 | |

† The `tools≥3` threshold was picked after seeing that 0-to-2-tool recaps were the FPs. It is post-hoc, so re-validate it on fresh labels.

### vs `gt_mis` (harm: ✅ or yes close hides research-born work), 4 positives of 90

| signal | TP | FP | FN | TN | P | R |
|---|---|---|---|---|---|---|
| p1 | 0 | 17 | 4 | 69 | 0.00 | 0.00 |
| p2 | 4 | 14 | 0 | 72 | 0.22 | 1.00 |
| **p2s** | **4** | **8** | **0** | **78** | **0.33** | **1.00** |
| p2s ∧ ¬status | 4 | 7 | 0 | 79 | 0.36 | 1.00 |
| p2s ∧ tools≥3 † | 4 | 3 | 0 | 83 | 0.57 | 1.00 |
| p2s ∧ ¬commit | 3 | 4 | 1 | 82 | 0.43 | 0.75 |
| p3_20 | 2 | 21 | 2 | 65 | 0.09 | 0.50 |
| p4 | 1 | 15 | 3 | 71 | 0.06 | 0.25 |
| (p2s ∨ p4) ∧ ¬recap | 3 | 13 | 1 | 73 | 0.19 | 0.75 |

Reading the two tables together:
- **Every p2s miss against `gt` is a positive whose close already said "not done" (⛔ / ❌ / "no").** That is 8 of 8 FNs with mis=N. So p2s misses only closes that already surface the pending work. Against the harm, recall is 4/4.
- **`¬commit` costs recall.** 978fd287 committed in the same turn as its research, and its close still hid two decisions.
- **`¬recap` also costs recall.** The prompt "SCQA the outcome … and /explain-decisions" is both a recap and a research trigger.
- **`¬status` (narrow) costs nothing** in-sample.

### Corpus fire rates (measured, all 1877 turns / 347 sessions)

| signal | turns | % | sessions |
|---|---|---|---|
| p1 | 90 | 4.8% | 74 |
| p2 | 73 | 3.9% | 50 |
| p2s | 47 | 2.5% | 39 |
| p3_20 | 320 | 17.0% | 162 |
| p4 | 30 | 1.6% | 22 |
| p2s ∨ p4 | 76 | 4.0% | 51 |
| p2s ∧ tools≥3 | 35 | 1.9% | 31 |
| (p2s ∨ p4) ∧ tools≥3 | 48 | 2.6% | 38 |
| p2s ∧ ¬commit ∧ ¬status | 22 | 1.2% | 19 |

## 5. False positives, with why (in-sample, vs `gt`)

**p2s (5 FP):**
- f583a3fd 10-19T01:54 (status Q): restates a decision from an earlier turn.
- abe1d338 10-19T01:55 `/are-we-done`: nothing open. `%` and "recommend" appear in "nothing to recommend or rate".
- 58d3640a 10-12T09:38 `/limit-recover`: nothing to re-run. The `%` comes from quota percentages.
- 756b68c8 10-18T04:15: research verdict "isn't worth it, 88% conviction". The action is inaction.
- d8964eb2 10-04T21:14: 0-tool recap that leads with ⛔. Accurate.

**p2 adds 6 more FPs:**
- 978fd287 10-06T05:37 "Good to close?": ✅ yes while a reboot decision from an earlier turn waits.
- 1f572e53 10-07 "(Checking in)": decisions with defaults filed.
- 8a4396f0 10-09 "(Checking in…)": earlier decisions.
- 46a0fdc8 10-07T20:32: research workflow still running.
- f583a3fd 10-19T02:03: recommendation implemented and landed.
- 3bd7aa3b 10-09: successor idle.

**Note on the stale-pending closes.** 978fd287 05:37, 1f572e53 and 8a4396f0 are ✅ closes with research-born operator decisions listed *below* the verdict line. They are FP under this slot's "this turn's research" rule, but they are the *same harm shape* as the incident. Whether they are FP depends on whether the contract is "this turn's research" or "any pending research-born action of this session". The second reading turns 3 of p2's 11 FPs into TPs.

**p4 (11 FP):** almost all are recaps of items that predate the turn.
- "short and concise SCQA the outcome …" ×4 (6261c2ab ×2, 9fd1dbab, e131c8d2)
- "what are our current steps and decisions" (58d3640a)
- "Present our todos" (05af12f0, 26 items)
- a roadmap status (6207f5b4)
- "what is the audit exactly" (eedec145)
- 2 successor pickups waiting on the operator (14233392, d41d9684)
- a still-running workflow plan (46a0fdc8)

**p1 (16 FP):**
- **13 are recycled successor or program briefs** ("You are the … research program LEAD", `[locate] cd …`, "Goal set: …", "Continue the … wave"). They match only because of a `docs/research/…` path (`/research` alternative) or a "fan-out" mention.
- The other 3 are a still-running research launch (6069b9d3), an unsettled investigation (98e6f890), and a handoff dispatch (44091255).
- **Corpus-wide: 67 of 90 p1 fires match only `/research`, and 68 of 90 fire on prompts over 1000 chars** (`status.py`). That is a defect in the nudge's own regex, independent of this question: the path alternative fires on any brief that cites `docs/research/`.

**p3_20 (17 FP):** build or implementation loops and waiting leads. Examples: "Proceed with all recommendations" (d41d9684, 6defb493), "Goal set: …" build waves, image-ranking loops, watcher heartbeats. **12 of the 17 committed.** Tool count measures effort, not research.

## 6. Alarm inflation on pure status questions (measured, full corpus)

| signal | fires on status (57) | share of its fires that are status | fires on recap (196) | share that are recap |
|---|---|---|---|---|
| p1 | 0 (0%) | 0/90 | 0 (0%) | 0/90 |
| p2 | 7 (12.3%) | 7/73 = 9.6% | 14 (7.1%) | 14/73 = 19.2% |
| **p2s** | **4 (7.0%)** | 4/47 = 8.5% | 7 (3.6%) | 7/47 = 14.9% |
| p3_20 | 3 (5.3%) | 3/320 | 28 (14.3%) | 28/320 = 8.8% |
| p4 | **0 (0%)** | 0/30 | 10 (5.1%) | **10/30 = 33.3%** |
| p2s ∨ p4 | 4 (7.0%) | 4/76 = 5.3% | 17 (8.7%) | 17/76 = 22.4% |

- The 57 status prompts break down as:
  - "Good to close?"-led: 36
  - `/accounts`: 8
  - "SCQA the outcome … are we done / good to close?": 8
  - other: 5 (2 of them not status asks; see §2)
- Of the 21 *labelled* status turns, 1 is POSITIVE: 92928fee, a 23-tool diagnosis behind "are we good to close this pane?".
  - So status prompts are not reliably NEG.
  - Of the 36 labelled recap turns, 3 are POSITIVE: 978fd287 (incident shape), 92928fee and 404651b1.
- **The inflation risk is concentrated in p4 and in recaps rather than in "Good to close?".**
  - p2s fires on 4 of 57 status turns, and 3 of those are the stale-pending ✅ shape above.
  - `/accounts` never trips p2s, even though its readout is full of `%`, because its text has no `NOTHING` phrase.
  - p4 is the only signal for which a third of its fires are recap or roll-call answers.

## 7. The incident turn and a second instance

- **Incident 74728043 02:15 `/explain-decisions`.**
  - p1 = false. The typed prompt `/explain-decisions` matches nothing, and the expansion's "exhaustively research now" also misses `research (the|how|…)`.
  - p2 = p2s = true ("conviction", "%", "nothing of mine is open", "nothing to do").
  - p3_20 = true (36 tools, 9 Agent spawns, no `Scope (frozen):`).
  - p4 = true (13 actionable items, no commit).
- **Second instance, 6defb493, 2026-10-09T23:15.** The prompt was "How did our telemetry session do, did that finish…?".
  - The substantive close (23:16:27Z) said: "It finished … closed its own pane … *Still yours: the five time-on-screen decisions in the report*". The research had run in a dispatched peer, which self-closed "since nothing was meant to continue".
  - The turn's *final* text was a heartbeat, "Still quiet, and the inbox watcher is running again. Nothing has changed."
  - The operator's next prompt was **"So we completed research but we didnt implement?"**.
  - **No signal fires, on either the heartbeat or the substantive text.** The substantive text scores rec=false, rec_strict=false, nothing=false, 0 actionable items. Close-text markers cannot see research done by a peer and only *referenced* ("five decisions in the report").
- **Heartbeat finals (measured).** 482 of 1877 final texts are under 200 chars, and 158 are short watcher or "still quiet" heartbeats. A close-text signal must read the turn's last *substantive* close (for example the last text ≥300 chars, or the text D6 evaluated), not the last text.

## 8. Limits of this measurement

- **Small sample.** 90 labels with 15 / 4 positives. The gt_mis recall of 4/4 has a 95% Clopper–Pearson lower bound of about 0.40 (*estimated*, standard formula).
- **One labeller,** with no second rater. The rule in §3 is the contract, and the borderline calls are named in `labels.tsv` (operator-action research such as e7659abe and 05af12f0 22:09, and status diagnoses such as 92928fee).
- **p2/p4 read only the final text.** p3 reads only main-thread tools; subagent tool use is not counted.
- **Turn splitting.** Queued mid-turn prompts split turns (292 turns). An alternative segmentation would merge them.
- **p4's verb list and id regex are hand-made.** "Time-on-screen module" (6defb493 00:19) is not a verb, which is one reason that positive is missed.

## 9. Files

| file | what |
|---|---|
| `/tmp/rpic-G/build.py` | corpus + turn segmentation + p1 replica → `turns.jsonl`, `corpus.log` (`corpus.final.log` is the run used) |
| `/tmp/rpic-G/verify_p1.py` → `verify_p1.out` | real-hook equivalence check (`agree 1877 disagree 0`) |
| `/tmp/rpic-G/signals.py` | p2/p2s/p3_T/p4/status → `sig.jsonl` |
| `/tmp/rpic-G/sample.py` → `sample.json`, `tolabel.txt` | stratified draw |
| `/tmp/rpic-G/labels.tsv` | hand labels: sid8, ts, P/N, mis Y/N, reason |
| `/tmp/rpic-G/eval.py` → `eval.out` | confusion tables, FP/FN lists, weighted estimates |
| `/tmp/rpic-G/status.py` → `status.out` | status/recap inflation, p1 match-source breakdown, heartbeat counts |
| `/tmp/rpic-G/p2parts.py` | which NOTHING/REC phrases drive p2s |
