# How "complete" is asserted in claude-infrastructure — audit for the research-convergence problem

Scope: `commands/are-we-done.md`, `commands/wrap.md`, `hooks/completion-assert.sh`, `scripts/wrap-ledger.sh`,
`hooks/dod-persist.sh`, `bin/cc-decide`, the Follow-On Gate in `CLAUDE.global.md` / `CLAUDE.global.slim.md`,
and the research stop rule in `skills/research-subagents/SKILL.md`. All paths are relative to
`/Users/chrisren/Development/claude-infrastructure` unless absolute. Read-only; nothing was edited.

## Answer first

When the operator asks "are we 100.00/100.00 complete?", the persisted ledger answers only **git and
session state** (dirty, landed, live, custody, filed operator steps). It has no representation of the
**quality or coverage of a research/plan artifact**, so for a research or planning phase the ledger reads
`✅` (or `⛔ sign-off`) and says nothing about the question actually asked. The substantive answer is
therefore produced by a **fresh, open-ended critique** at the moment of asking. Four rules then make "no,
one more thing" the only rule-compliant answer whenever the model can imagine any further check:

1. no definition of materiality exists (the one use of "immaterial" is undefined);
2. the Follow-On Gate treats "100th-percentile completeness; nothing left on the table" as the
   net-positive test, so every conceivable refinement passes it;
3. the close rules forbid both a hedged yes and an offer, and demand that any named item be driven;
4. the research stop rule's negative-space trigger promotes any unexplored dimension unless the operator
   explicitly excluded it at intake, which an "absolute perfection" intake never does.

No mechanism distinguishes **frame expansion** (the operator or the model widened the question) from a
**miss inside the frame** (the prior research should have caught it). `Scope (grown)` records growth
with no cause field, and no consumer reads it. Nothing compares today's verdict with the prior "yes".

## 1. What the close procedure actually computes

### 1.1 `/are-we-done` = git/custody state, not work-product state
- `commands/are-we-done.md:19-24` reads only `wrap-ledger.sh`, `--goal`, `operator-readout.sh`,
  `cc-custody`, `cc-sessions`.
- `commands/are-we-done.md:52-55`: `yes` requires "rung ✅ · clean tree · landed by content · gates
  green THIS turn · frozen-DoD remainder 0 · custody clean". Every term is a repository or session fact.
- `commands/are-we-done.md:70-72` defines "exhaustively" as "landed by content, gates green this turn,
  DoD remainder 0, custody clean, nothing filed against this session". **"Exhaustive" is operationalized
  as a git property, not a research property.**

### 1.2 `/wrap` rungs: nothing measures research completeness
- `commands/wrap.md:69-77` (rung table): 🔧 = dirty ∨ gate stale ∨ DoD remainder > 0; ✅ = clean ∧
  landed ∧ remainder 0.
- `commands/wrap.md:147` (file line 147, "Never emit ✅ from memory… If it reports no durable DoD,
  completeness is unverifiable — freeze one") states the intent, but see 1.4: the ledger still emits ✅.

### 1.3 The "frozen DoD remainder" is a checkbox count, and almost no DoD has checkboxes
- `scripts/wrap-ledger.sh:570`: "Frozen-DoD remainder (unchecked "- [ ]" items)".
- `scripts/wrap-ledger.sh:616-623`: REMAINDER = `grep -cE '^[[:space:]]*[-*][[:space:]]+\[[[:space:]]\]'`.
- `hooks/dod-persist.sh:106`: "wrap-ledger REMAINDER counts `- [ ]` boxes only".
- The producer captures only **one prose line**: `hooks/dod-persist.sh:76-86` (`grep -aoE 'Scope \(frozen\):.*'`).
- Live store measurement (`~/.claude/autonomy/dod/*.md`, 2026-09-30): **76 files, 326 `Scope (frozen)`
  lines, 38 checkbox lines in total, and only 4 of 76 files carry any checkbox.** This repo's own
  store (`repo-86523465733a9afe.md`) has 63 frozen scopes and **0** boxes. Median frozen-scope length
  is 407 chars (max 3,680).
- Consequence: **REMAINDER is structurally 0 for almost every task.** "Diff against the frozen
  contract" (`CLAUDE.global.md:555-557`) has no mechanical implementation. The model re-reads a prose
  sentence and judges again, which is exactly the "fresh re-judgment" that line forbids.

### 1.4 An absent DoD still yields ✅
- `scripts/wrap-ledger.sh:2286-2288`: `elif [ "$DOD" = "absent" ]; then RUNG="✅"; READOUT="✅ Clean &
  landed — but NO durable DoD to confirm scope…"`.
- This contradicts `CLAUDE.global.slim.md:259` ("No findable scope is an unknown, not a ✅") and
  `commands/wrap.md` ("freeze one rather than asserting a bare ✅").
- Seen live: every close in the VoiceInk quota-plan loop opened "✅ Clean & landed — but NO durable DoD
  to confirm scope" (`~/.claude-quaternary/projects/-Users-chrisren-Development-voiceink/ba08cab8-….jsonl`,
  2026-09-14T19:08:58, 19:28:54, 19:45:53, 21:2x).

### 1.5 The DoD that does get injected is often someone else's
- `hooks/dod-persist.sh:130-153`: lineage filtering was added because "7 of 8 injected contracts were
  unrelated" (measure/hooks.md §4).
- Seen live: the VoiceInk latency-plan session (`~/.claude-secondary/projects/-Users-chrisren-Development-claude-infrastructure/989f6dbf-….jsonl`)
  started at 2026-09-27T20:19 with an injected `Scope (frozen): kitty begin-window-drag — PHASE 1
  RESEARCH COMPLETE…`, an unrelated task. Its real scope (an implementation *outcome*, "≤1.5 s p50 /
  ≤3 s p90…") was written only into the plan doc through tool calls at 21:40 and 06:13, and it lived in
  another repo (`~/Development/voiceink`) that the ledger for this cwd never reads.

### 1.6 `completion-assert.sh` is one-directional: it blocks false-done and never questions false-not-done
- Fire predicate: `hooks/completion-assert.sh:13-19`, `(done_assertion ∨ deference_tell) ∧
  ledger-contradiction ∧ ¬genuine`. The contradiction is `dirty ∨ unlanded ∨ DoD-remainder>0 ∨ 🚀 ∨ ⛔`.
- The done-matcher `CLOSE` (`:250`) is broad, but everything behind it is a ledger fact. A "No, one
  check remains" answer triggers **nothing**. Every arm penalizes asserting done (or asserting it
  badly). No arm penalizes re-opening something already declared done.
- D3 (`:255-256`, `:974`, reason at `:1276`) catches a verdict and its retraction **within line 1 of
  one message**. It does not look across turns, so "yes" at turn N followed by "no" at turn N+1 is
  invisible to it.
- D4 (reason at `:1278`) blocks naming remaining work and then offering it: "the operator's standing
  ruling is that the answer is always yes… DRIVEN… DROPPED… BLOCKED". So once the model names any item
  it must drive it, which makes the next answer "no, running it now".

## 2. Is there any definition of materiality?

**No.** The complete inventory:

| Where | Text | Defined? |
|---|---|---|
| `CLAUDE.global.md:857` | "if it is immaterial it does not appear in line 1 at all" | no; about line-1 placement only |
| `hooks/completion-assert.sh:1276` | "if it is immaterial, leave it out of line 1 entirely" | no |
| `hooks/lib/why-tier.sh:89` | same sentence | no |
| `CLAUDE.global.md:616-618` (F1) | net-positive = "100th-percentile completeness; nothing left on the table; time-zero" | the opposite of a threshold: every non-zero improvement qualifies |
| `CLAUDE.global.md:619` (F2) / `bin/cc-decide:88-98, 206-226` | the 90% conviction rule | applies to **decisions**, not to completeness; "research exhaustively" is never defined and has no terminal condition except "still ≤90 → hand to operator" |
| `commands/explain-decisions.md:6` | "If exhaustive research moves your conviction one way or another, exhaustively research now." | the trigger is *any* movement, not a material one |

`grep -rliE 'materiality|materially'` over commands/hooks/skills/agents/CLAUDE.global.md finds only
incidental uses (`commands/research.md:85`, pricing; `bin/cc-teardown:753`). There is no severity
scale, no "would this change a decision or the implementation?" test, and no numeric threshold at the
close.

The only **refinement vs new-dimension** distinction in the repo is scoped to spawning inside a single
research wave, not to the close question:
- `skills/research-subagents/SKILL.md:599`: "stop tool calls when next call would surface refinement of
  evidence already gathered, not a new dimension".
- `skills/research-subagents/SKILL.md:766-777` (OASIS): "Adversarial null: … returns refinements only,
  no new axis"; "Sublinear tail … next subagent's expected gain < ε (0.5 unique findings)";
  "Falsifiability: would the opposite flip my conclusion? — if no, stop". Criterion 4 is the nearest
  thing to a materiality test in the repo, and it is used only to stop spawning subagents.
- `agents/deep-research.md:97,176`: same saturation rule, per subagent.

## 3. Is there a mechanism that separates frame expansion from a miss inside the frame?

**No.**
- `Scope (grown): +<item>` (`CLAUDE.global.md:569, 627`; captured by `hooks/dod-persist.sh:13-16,
  88-96`) records **that** scope grew, as free text with no cause field (operator-widened / agent-missed /
  newly-discoverable / refinement).
- No consumer reads it. `grep 'grown'` in `scripts/wrap-ledger.sh`, `hooks/completion-assert.sh`,
  `hooks/operator-readout.sh`, `bin/cc-decide` and `bin/cc-backlog` returns nothing. REMAINDER ignores it.
- Only 3 `Scope (grown)` lines exist in this repo's live DoD store, against 63 frozen scopes. Growth is
  mostly never recorded at all.
- No store keeps a verdict history ("at T the answer was yes, on frame F, with evidence E"), so a later
  "no" can never be classed as a take-back.
- The research rule actively turns misses into frame growth: `skills/research-subagents/SKILL.md:796-802`
  (negative-space trigger, "List 3 dimensions I am NOT exploring… If any reason is 'I forgot' or **'not
  obviously relevant'** → promote into scope… If the reason is 'explicitly out of scope per user
  intake' → cite the user's words"), repeated for Wave 2 at `:822-830`. The instrument always yields 3
  candidates. The only exit is an explicit exclusion in intake, and an "absolute perfection, exhaustive"
  intake excludes nothing.

## 4. What the transcripts show (corroboration)

Method: `/tmp/rescomp/internal/ca_scan.py` over the 111 transcripts containing `100.00/100.00`
(`/tmp/rescomp/internal/ca-files.txt`) extracts genuine human prompts matching the completeness
question, plus the session's final text before the next human prompt. Output:
`/tmp/rescomp/internal/ca-pairs3.txt` (60 unique prompts, 2026-08-23 → 2026-09-30). The classifier is
crude; the cases below were read by hand.

**Pattern A: the question itself launches a fresh critique, and the critique finds something.**
- 2026-08-23T17:51, Oxlint (`…wt-pool-4/39e7380e`): "Let me not answer that from optimism. Checking the
  thing most likely to be silently missing" → "No… Four honest gaps".
- 2026-08-23T08:45, FLOOR_PLAN (`…wt-pool-5/d41563e3`): "This deserves a real audit, not an assertion."
- 2026-09-22T05:39 (`…/2825e1e5`): "Honest answer requires a re-read for internal consistency, not
  just a recap." That came after the same session closed at 2026-09-21T17:55 with "✅ Complete & live on
  trunk… Good to close: yes".
- 2026-09-28T05:25:47 → 05:26:16 (`…/989f6dbf`): the SCQA said "Conviction: 90% that it runs without
  re-planning… blocked on your plan sign-off". 29 seconds later, asked "have we exhausted our research…?",
  the answer was "No, not yet. One check remains… nobody has re-read the finished document end to end.
  I'm running that fresh-eyes consistency review now." **The check did not exist until the question
  was asked.**

**Pattern B: repeated asking, each answer reopened.** VoiceInk quota plan (`ba08cab8`, 2026-09-14):
- 18:40 `⛔ Blocked on your sign-off — … implementation plan … is finished.`
- 19:02 "Have you exhaustively researched…?" → verification pass: "corrected my own work twice… Seven
  further defects surfaced".
- 19:25 "Do you deem it 100.00/100.00…? If so, I approve" → "No… I told you the plan was done. You asked
  if it was exhaustive; pushing on that found a hole… **That is not the shape of a converging
  process.**" A third pass followed: "New findings per pass: **10 → 7 → 2**… a fourth pass would be
  expected to… find near zero… **it's ready**. Not perfect."
- 21:26, same question → "Since you last asked, the plan gained two more defects… still no. But
  there's one mechanical check left".
The only stop signal used (the 10 → 7 → 2 yield curve) was invented ad hoc in the reply. No rule
defines it for plan review, and no store keeps it, so the next session could not reuse it.

**Pattern C: the answer is "no" because the frame is not reachable by research.**
- 2026-09-22T19:52 (`…/2825e1e5`): "No. Same verdict… the remaining gap is not something more work here
  can close… **the second pass found sixteen the first had missed**" (five tenant-only measurements, a
  GUI probe, "a design, not a running system").
- 2026-09-24T05:02 (`…/0612873d`): "yes for this session, no to '100/100 implementation'. There's no
  implementation yet."
- 2026-09-26T20:19 (sevenrooms `ac0f0123`): "No… about 93 of 100… **The frozen scope (research, then
  recommend) is complete**", which answers the question against a frame larger than the frozen scope.
- 2026-09-20T09:07 (`…/7f533f05`): "'Safe to close' described my session's state, not the job".

**Pattern D: an item that the prior "done" missed inside its own frame.**
- 2026-09-27T23:53 (`…/989f6dbf`): "The plan has one real gap: it drops the research's 'warm connection'
  fix (60–110 ms…)". A research finding had been lost on the way from research to plan, a true miss
  inside the frame. The same reply then said "the plan is complete, but it is not 100% certain".
- 2026-09-22T19:53 (`…/2825e1e5`), once the operator narrowed the frame to "what we can do NOT being on
  the corporate Mac": "three things still drivable on this Mac that I had let sit as the operator's".

Patterns A–D are four different causes (fresh-critique generator, missing convergence rule,
research-irreducible frame, genuine miss). The system records all four identically, as "No".

## 5. The exact gaps (numbered for the synthesis)

- **G1. No research-phase ledger.** Nothing persisted represents a research or plan artifact's coverage
  (questions, axes, findings, known residuals, verdict). The ledger answers git; the model answers
  quality from scratch. (`are-we-done.md:52-55,70-72`; `wrap.md:69-77`)
- **G2. The DoD is prose, and REMAINDER counts checkboxes that are almost never written.** 4/76 DoD files
  carry boxes; this repo has 63 scopes and 0 boxes. The "diff against the frozen contract, never a fresh
  re-judgment" (`CLAUDE.global.md:555-557`) cannot be executed mechanically. (`wrap-ledger.sh:570,616-623`;
  `dod-persist.sh:76-86,106`)
- **G3. An absent DoD reads ✅.** (`wrap-ledger.sh:2286-2288`, against `CLAUDE.global.slim.md:259`)
- **G4. No materiality definition.** The only mention is undefined (`CLAUDE.global.md:857`,
  `completion-assert.sh:1276`, `why-tier.sh:89`). F1's value set (`CLAUDE.global.md:616-618`) makes
  every refinement net-positive.
- **G5. No frame-expansion vs in-frame-miss classification.** `Scope (grown)` has no cause field and no
  reader (`dod-persist.sh:88-96`; zero hits in the ledger, assert, readout, decide and backlog).
- **G6. No verdict history and no take-back detector.** D3 is line-1, single-message only
  (`completion-assert.sh:255-256,974`). Nothing records "declared complete at T on frame F", so a
  reopen costs nothing and teaches nothing.
- **G7. Asymmetric enforcement.** Every Stop arm guards against a premature "done"; none guards against
  an unbounded "not done". Combined with D4 ("the answer is always yes", `:1278`) and the ban on
  hedging (D3), the only compliant reply to "are we 100.00?", whenever any further check is imaginable,
  is "No, running X now".
- **G8. The research stop rule is a hole generator at the close.** The negative-space trigger always
  lists 3 and promotes "not obviously relevant" (`research-subagents/SKILL.md:796-802,822-830`). OASIS's
  materiality-like test (criterion 4, `:774-775`) and the sublinear-tail test (`:773`) apply only to
  spawning within a wave, never to the "are we done?" question, and nothing persists the discovery curve
  across sessions.
- **G9. The conviction rule has no ceiling for completeness.** F2/`cc-decide` (`CLAUDE.global.md:619`;
  `cc-decide:88-98,206-226`) prices decisions, not coverage. "Research exhaustively" is undefined, and
  `explain-decisions.md:6` triggers more research on *any* conviction movement.
- **G10. The frame is unbounded at intake.** "100.00/100.00… absolute perfection" is never translated
  into finite, enumerated acceptance criteria. Research-irreducible items (tenant-only measurements,
  compile/run-time defects: pattern C) are never declared out of the research phase's frame, so the
  research phase can never close by construction.
- **G11. DoD crosstalk and cwd-keying.** The injected contract is often unrelated (`dod-persist.sh:130-153`;
  seen in 989f6dbf), and a plan living in another repo is invisible to the ledger for the session's cwd.

## 6. What the gaps imply for the fix (for the synthesis stage; not implemented)

The evidence points to a close for a research phase that is computed against a **frozen, enumerated
frame**: a question and axis list, finite acceptance criteria and a declared residual set (what only
implementation or measurement can resolve). The close also needs a **persisted verdict history**; every
later finding is typed as `in-frame miss | frame expansion | refinement | research-irreducible`, and
only an in-frame miss above a stated materiality bar reopens the verdict. A discovery-yield curve per
pass (the 10 → 7 → 2 the VoiceInk session derived ad hoc) would supply the stop rule. It would also
supply the self-audit the operator is really asking for: an in-frame-miss count per phase, which
measures the research methodology rather than restarting it.

## Artifacts
- `/tmp/rescomp/internal/ca_scan.py`: transcript scanner (final version)
- `/tmp/rescomp/internal/ca-files.txt`: 111 transcripts containing `100.00/100.00`
- `/tmp/rescomp/internal/ca-rows3.json`, `/tmp/rescomp/internal/ca-pairs3.txt`: prompt / final-answer pairs
- `/tmp/rescomp/internal/sess-ba08cab8.txt`, `/tmp/rescomp/internal/sess-989f6dbf.txt`: extracted turn text of the two loop exemplars
