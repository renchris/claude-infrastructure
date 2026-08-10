---
status: open
---

# What makes a good `/goal` condition, and why `--goal` has to be the DEFAULT

**2026-08-09.** Continues `docs/research/goal-in-handoff-2026-08-08.md` (status: closed), which
answered *how* a fire can carry a goal and built the `--goal` two-message path. That doc's own § 6
left the question this one answers: the mechanism shipped, and **nothing made anyone use it**.

The operator's ask, verbatim:

> research Anthropic's best practice for what constitutes as the best /goal prompt, ensure that our
> /handoff makes it clear to use /goal when it's appropriate to, with the best /goal prompt from
> best practices. Currently, the vast majority of /handoff does not include a --goal /goal unless
> verbalized even though this should be the default for almost all newly created and initial
> prompted sessions.

**Scope (frozen):** establish what constitutes the best `/goal` condition (from the shipping harness
and from Anthropic's published guidance, not from taste); make `--goal` the documented DEFAULT for
new-task fires with that template baked in; land the mechanism that makes the default stick.

---

## 1 · Why adoption is 3%, and it is not a discipline failure

`--goal` landed 2026-08-08 with a validated flag, a read-back oracle, a ledger class, and 18 tests.
Adoption did not move. The cause is mechanical and it is one line long:

**Not one of the six canonical `handoff-fire.sh` invocations in `commands/handoff.md` carries
`--goal`.** The three in § Autonomous fire item 5 (`:393-402`) and the three in the wave recipe
(`:428-433`) are the blocks an agent constructing a fire actually copies. `--goal` exists only in
prose, inside a sub-bullet of item 1 — a section about *what goes in the payload*, which is the one
place the goal explicitly must not go.

This is the `spec-named-mechanism-may-be-prose-only` shape with the polarity reversed: the mechanism
is real and the *recipe* is what is missing. A flag documented only in prose beside a recipe that
omits it is, for a copying producer, indistinguishable from a flag that does not exist.

The prior doc measured the drop (20.0% → 3.0%) and correctly attributed it to the 2026-07-31
slash-head refusal removing the only route producers had. It then built the new route. What it did
not do — and could not, in the same turn — is put the new route where producers look.

---

## 2 · What a goal condition actually has to be, from the harness's own words

Primary evidence, first-hand: this session was itself started with `/goal`, so its transcript carries
the harness's injection verbatim. This is what Claude Code tells the receiving model when a goal is
set:

> `Goal set: <condition>`
>
> A session-scoped Stop hook is now active with condition: "`<condition>`". Briefly acknowledge the
> goal, then immediately start (or continue) working toward it — treat the condition itself as your
> directive and do not pause to ask the user what to do. The hook will block stopping until the
> condition holds. It auto-clears once the condition is met — do not tell the user to run
> `/goal clear` after success; that's only for clearing a goal early.

Three properties of a good condition fall straight out of that text, and they are the whole design:

1. **The condition plays two roles at once.** It is the model's *directive* ("treat the condition
   itself as your directive") **and** the *predicate a Stop hook judges* ("blocks stopping until the
   condition holds"). A condition that reads well as one and badly as the other is a bad condition.
   An instruction with no observable end state never lets the session stop; a bare predicate with no
   verb gives a fresh context nothing to do.
2. **It must be reachable by the session alone.** "do not pause to ask the user what to do" — a
   condition whose satisfaction requires an operator decision is self-contradicting: the directive
   forbids asking, and the predicate cannot go true without an answer.
3. **It must be able to become true, observably.** "auto-clears once the condition is met" is the
   only exit. A condition with no terminal state is a session that cannot close.

*(Rules sourced from the shipping binary's evaluation path and from Anthropic's published guidance
are in § 4 — the section below this one records the mechanism facts that constrain any template.)*

---

## 3 · The constraints any template must respect

Carried forward from `goal-in-handoff-2026-08-08.md` § 2 (measured, not re-derived here):

| Constraint | Consequence for the condition |
|---|---|
| Hard cap **4000 chars** on the condition | It is a pointer, never the brief. Message 1 has no cap. |
| Must be **one line** | The arming paste submits at the first CR; a newline strands the rest. |
| Must not **start with `/`** | It is pasted as `/goal <condition>`; a leading slash re-dispatches. |
| **Dies with its session** | Every recycle needs it re-armed, or a long chain silently drops it. |
| No native `--goal` **CLI flag** exists | Verified 2026-08-09 against the 2.1.220 binary: no such option string. The two-message paste path is the only route. |

---

## 4 · The ruleset

### 4.0 The headline: it is documented, and we were not following it

**`/goal` has an official Anthropic page — <https://code.claude.com/docs/en/goal> — whose normative
section is titled *"Write an effective condition"*.** Nobody in this repo had read it. Every previous
statement here about how to phrase a condition was ours, and the one we shipped fails Anthropic's own
test (§ 1, § 5).

### 4.1 Anthropic's three-part recipe (the source of truth for shape)

> "A condition that holds up across many turns usually has: **One measurable end state**: a test
> result, a build exit code, a file count, an empty queue • **A stated check**: how Claude should
> prove it, such as `npm test` exits 0 or `git status` is clean • **Constraints that matter**:
> anything that must not change on the way there, such as no other test file is modified"
> — <https://code.claude.com/docs/en/goal>

Two more from the same page: the cap is **4,000 characters**, and a long run is bounded **inside the
condition text** (`or stop after 20 turns`) because there is no flag for it.

The doctrine behind it is Anthropic's own, from the Claude Code best-practices page: *"Claude stops
when the work looks done. Without a check it can run, 'looks done' is the only signal available, and
you become the verification loop."* — and it names `/goal` as the session-scoped tier of that check.
Anthropic's guidance bundled **inside the binary** says the same thing and gives the analogue:
long-horizon runs want *"the full task specification up front"*, and `/goal` is the Claude Code
surface for it, paralleling a Managed-Agents **Outcome with a gradeable rubric**.

### 4.2 Why the "stated check" is the load-bearing part — the judge, measured

The published reason is *"It doesn't run commands or read files independently."* The binary says
exactly how far that goes. The Stop-hook judge's own system prompt (2.1.220, verbatim):

> You are evaluating a stop-condition hook in Claude Code. Read the conversation transcript
> carefully, then judge whether the user-provided condition is satisfied. […] Always include a
> "reason" field, **quoting specific text from the transcript** whenever possible. **If the transcript
> does not contain clear evidence that the condition is satisfied, return `{"ok": false, "reason":
> "insufficient evidence in transcript"}`.**

…and the user message wrapping it: *"Based on the conversation transcript above, has the following
stopping condition been satisfied? **Answer based on transcript evidence only.**"*

It is called with `tools:[]` and `thinkingConfig:{type:"disabled"}`, on the small-fast model (Haiku
by default). Four consequences, and they are the whole authoring discipline:

| # | Rule | Because |
|---|---|---|
| **R1** | The evidence must be **text the session PRINTED**. | `tools:[]` — no file read, no git, no CI. A criterion true on disk but never printed is unjudgeable. |
| **R2** | Name a **quotable artifact string** (`0 failures`, `exit 0`, a sha), not a state of affairs. | A pass must quote the satisfying text. |
| **R3** | **Fail-closed on ambiguity.** Vague ⇒ blocked, never passed. | The default verdict is hard-coded `insufficient evidence in transcript`. |
| **R4** | The proof must be **recent**. | The transcript is truncated to ~50% of the *evaluator's* window, most-recent-kept, with a banner telling the judge to answer *insufficient evidence* if the proof may be in the omitted prefix. Evidence printed at turn 3 of a long run is gone. |

### 4.3 Two failure modes of a bad condition, and they are not the same

- **Self-contradictory / genuinely unachievable** → the judge may return `{"ok":false,
  "impossible":true}`, which **clears the goal and marks it failed** (`tengu_goal_failed`). A real
  escape hatch. The judge is explicitly told not to take the assistant's word for it: *"the assistant
  claiming the goal is impossible is evidence, not proof."*
- **Merely vague** → no such mercy. It block-loops until `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` (default
  **8**) and then the turn ends regardless. The goal neither clears nor is met; it just stops
  mattering.

**Corollary a template must respect:** a condition satisfiable *by assertion* is satisfiable by
assertion. Nothing in the judge's prompt tells it to discount the agent's claim that the goal IS met
— only its claim that the goal is impossible. So "the work is complete" passes trivially and buys
nothing. That is the mechanical reason the *check* clause, not the objective clause, is what makes a
goal do work.

### 4.4 A rule found nowhere in any doc: no `$` in the condition

The condition string is run through the slash-command **variable substituter** before the judge sees
it, with the hook-input JSON as the argument vector — so `$ARGUMENTS`, `$1`, `$2` inside a condition
are **silently rewritten**. Write `npm test exits 0`; never `$(npm test)`.

### 4.5 Opus 5 modifiers — one cuts, one adds

From Anthropic's Opus 5 prompting guide, both directly applicable to condition text:

- **CUT verification language.** *"If your prompt contains explicit verification instructions […]
  remove them: instructions like these cause over-verification on Claude Opus 5."* A condition should
  name the check, not instruct the model to double-check.
- **ADD scope constraints.** *"Claude Opus 5 can also expand the scope of a task […] For narrow
  tasks, constrain scope explicitly."* This is precisely the recipe's third slot — *constraints that
  matter* earns its place on this model rather than being optional politeness.

### 4.6 Lifetime — three facts that decide where `--goal` must be re-passed

| Event | Goal survives? | Evidence |
|---|---|---|
| **`/compact`** | **Yes, structurally** — the hook lives in app state, not the message array. But the set-time injection is gone; after a compaction the only surviving assertion of the condition is the block-feedback line `Stop hook feedback:\n[<condition>]: <reason>`. | No compaction site touches `activeGoal` or the hook registry (negative search, ±1200 B windows). |
| **Session `--resume`** | **Yes** — `restoreGoalFromTranscript` scans the persisted transcript backwards for the last `goal_status` attachment and re-registers the hook (`tengu_goal_restored_on_resume`). Iterations reset to 0; the injection is not re-sent. | Called from both the resume and crash-respawn paths. |
| **`--recycle` (new session id)** | **No.** | Measured 2026-08-08: successor carries zero `goal_status`. |

This **corrects** the producer census's open question: `boot-resume` and `lr-fire-resume`, which
resume the SAME session id, do **not** need re-arming. Only a new-session-id succession does.

## 5 · The canonical template

```
--goal '<measurable end state> — proven by <the command the session runs and prints>; do not <constraint>; full brief in the prompt above, DoD at <path>'
```

Slot by slot: **end state** = R1/R2's quotable artifact · **proven by** = Anthropic's "stated check",
and the clause that stops the goal being satisfiable by assertion (§ 4.3) · **do not** = "constraints
that matter", which Opus 5 upgrades from optional to load-bearing (§ 4.5) · **pointer tail** = ~60
chars that orient a fresh context, and the only part our old template had.

Worked examples, from real work in this repo:

```
--goal 'tests/handoff-goal-arm.bats is green and the change is landed on origin/main — proven by
        printing the bats summary with 0 failures and `git ls-tree origin/main -- commands/handoff.md`;
        do not weaken check_slash_head; full brief in the prompt above, DoD at docs/plans/GOAL_IN_HANDOFF_METHODOLOGY.md'

--goal 'every fire template in the repo carries --goal — proven by printing
        `grep -rL -- "--goal" <the template list>` with empty output; do not touch scripts/handoff-fire.sh;
        full brief in the prompt above'

--goal 'the three rival designs are scored against the named criteria with one recommendation — proven
        by pasting the scored table into the transcript; do not implement anything; or stop after 20 turns'
```

Note the third: a research track's end state is **a printed artifact**, which is exactly what R1
wants. Research goals are not harder than build goals — they are easier, because the deliverable is
already text in the transcript.

## 6 · When a goal is NOT appropriate

Four exceptions, one test — **no reachable end state ⇒ no goal**:

1. **Standing-role sessions** — the desk (`desk-invariant.sh` respawns). "Hold the desk role" can
   never become true, so the hook would refuse every stop until the block cap.
2. **`--cloud` fires** — no local pane composer, so `arm_goal` can only abstain.
3. **Throwaway harness measurement** — `cc-upgrade-gate` spawns, `scripts/cloud-*-probe.sh`. The
   objective belongs to the operator running the probe.
4. **Sessions whose only "done" is an operator decision** — the goal's own directive is *"do not
   pause to ask the user what to do"*, so such a condition is self-contradicting at set time.

⚠️ **`--probe` is NOT an exception.** On `handoff-fire.sh` it liveness-probes the *account* before
firing; it is ordinary work. Nor is a plain continuation: a recycle mints a new session id (§ 4.6).

## 7 · The inertness threat — measured, and it does not block this

`hooks/goal-inert-watch.sh` documents that CC de-registers the goal's Stop hook whenever the task
registry holds non-terminal background work, and that this box arms `cc-await-ping --timeout 14400`
as a background Bash in every session. The deferral is **confirmed verbatim in the running binary**.
The strong reading — "an armed goal is inert by default here" — is **refuted**:

- **47 of 86 armed goals (55%) produced at least one real evaluation** (765 transcripts;
  `attachment.type=="goal_status"`, non-sentinel records). 45% zero-eval is an *upper* bound on
  inertness, since a session that ended before reaching a Stop also reads zero.
- **4 of 12 live sessions (33%)** held a deferring `local_bash` at census time — bursty, not constant.
- The watcher also dies early in practice (exit 144, external group-SIGTERM), and a `failed` status is
  terminal, which releases the goal.
- **The set-time injection is untouched by the deferral** — it fires before any Stop. Even a fully
  deferred goal delivers its main behavioural push; only block-until-true, auto-clear, and iteration
  accounting are lost.

So a default `/goal` is worth shipping **with** a companion fix rather than instead of one. Two
findings filed rather than fixed here, both outside this scope:

- **The companion fix already exists.** An `asyncRewake` hook's child is never registered in
  `taskRegistry`, so arming the watcher from `hooks/mailbox-wake-arm.sh` keeps the wake path *and*
  lets goals evaluate. It is written, tested, and one staged migration (`0007`) from live. This is a
  code reading, not a live A/B — prove it by experiment before relying on it.
- **`hooks/goal-inert-watch.sh` has never fired and structurally cannot** — deployed as a symlink but
  registered in no `settings.json`; its registration sits in staged migration `0005`, unapplied. Its
  damp store holds 1,424 entries and 0 matching `goal`.
- **A third blind spot in that hook, newly found:** `cip()` filters through `Gw()`, which drops every
  task with `isBackgrounded===false`, while CC's own `Tio`/`_We` read `taskRegistry.all()` unfiltered.
  So a **foreground** subagent or bash defers the goal while appearing nowhere in `background_tasks` —
  the hook's population is a strict subset of the predicate's, and it can under-report.

## 8 · What landed

| Commit | Change |
|---|---|
| `facb0fcb` | `--goal` becomes the default across every copyable fire template: the six recipes in `commands/handoff.md`, the two hooks that inject a fire template into model context (`plan-agent-teams-default.sh`, `validate-plan-structure.sh`), `skills/plan-{conventions,update}/SKILL.md`, and `CLAUDE.md`'s locus-S recipe. Item 1 rewritten around Anthropic's three-part recipe, the four judge-derived rules, and the exclusion list. |

**Deliberately NOT changed:** the no-nudge decision in `scripts/handoff-fire.sh`. A "you forgot
`--goal`" warning would have fired on ~97% of fires; the operator directive changed the *norm*, not
the alarm's polarity, and the ledger's `goal_requested` rate remains the detector. Re-check with the
two queries in `commands/handoff.md` § item 1 — the honest denominator is the field-carrying rows
(60 at the time of writing), not the ledger's full 142.
