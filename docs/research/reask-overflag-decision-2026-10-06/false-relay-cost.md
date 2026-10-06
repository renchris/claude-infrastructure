# E1h slot: what a false relay costs in practice

Worktree `/Users/chrisren/Development/.worktrees/wt-cc-024434-55635` at `ff3e87fb7`. I did **not** run the brief's
`git pull --ff-only`, because my rules forbid any git mutation, so everything below is read from that commit. All files
were opened read-only. No sealed set, key or `tuning-v2.jsonl` was opened, and no prompt text was printed. The
prompt-count script `/tmp/e1h-research/count_prompts.py` prints counts only.

Every number is labelled **measured** (with the command or file it came from) or **estimated** (with the method).

---

## 1. Where the router acts, and how many programs exist now

**Which sessions it acts in**
- The `UserPromptSubmit` hook finds the program by two keys, in order:
  - **Key 1, the working directory.** It runs `rp_resolve_cwd` on the payload's `cwd`.
  - **Key 2, a name in the prompt.** Only if key 1 finds nothing, it runs `rp_resolve_prompt` on the prompt text.
  - There is no third key.
  - Citations: `hooks/research-precognition-nudge.sh:35-41` and `scripts/lib/research-program.sh:18-29`. The
    single-active fallback was deleted under REPORT §10 item 2 (`REPORT.md:1370`).
- Key 2 is a whole-word, case-insensitive match on the slug or any alias (`research-program.sh:152-172`). It works
  from any pane, so a session outside the program's directory is routed for any prompt that names the program.
- `cmd_prompt` routes only while the program's state is in `BLOCKING_STATES`:
  - The states are `certifying`, `certified`, `build-certifying`, `build-certified` and `implementation-signed`
    (`router.py:96`, `kit.py:257-259`).
  - In any other state (`registered`, `closed`, or no program) it clears the session's route and prints nothing
    (`router.py:677-679`). The classifier is not called.
- `cmd_tool` also allows everything when the program is not in a blocking state (`router.py:941-943`).
- The Stop relay check does the same (`router.py:1080`).
- **So the router only works inside a program that is certifying or later.** The range covers the whole Stage 8–9
  build phase, up to `gate.sh close`. That phase is when ordinary build prompts are most frequent.

**What a route record covers**
- The `PreToolUse` hook (`hooks/research-block.sh`, registered on matcher `*` at `~/.claude/settings.json:864-870`)
  sends a tool call to `router.py tool` when either:
  - the cwd resolves to a program, or
  - the session has a route record (`research-block.sh:41-63`).
- `cmd_tool` keys only on `session_id` (`router.py:355-365`).
- Subagents share that id. In-process subagents share their lead's `session_id` (repo note,
  `hooks/backup-before-write.sh:253-254`), and `PreToolUse` fires for a Workflow agent's own tool calls
  (`hooks/unit-gate.sh:8`).
- Nothing in `cmd_tool` reads `agent_id`. **So a session's label applies to every subagent and Workflow agent that
  session is running at the time** (inferred from the code and those two repo notes; I did not test it live).

**Programs registered now** (measured: `jq` on `~/.claude/autonomy/research/programs.json`)
- There is one program: `truememory-2-0`.
  - State: `registered`.
  - Aliases: `TrueMemory 2.0` and `tm2`.
  - `cwd_roots`: `/Users/chrisren/Development/.worktrees/tm2-plan`.
- No program is in a blocking state.
- `~/.claude/autonomy/research/route-state/` holds 0 records (measured: `ls | wc -l`).
- **Today the router does nothing in any session.** No false relay can happen until a program is frozen for
  certification.

## 2. What exactly happens on a false completeness relay

The prompt is ordinary, the classifier calls it `completeness` or `pushback`, and this sequence follows.

1. **Context injection.** The model is told:
   - the prompt is "a COMPLETENESS question" (or PUSHBACK);
   - to relay the certificate state lines VERBATIM, plus at most 3 lines;
   - to name no item, location or row the lines do not carry;
   - "Every tool except `gate.sh --render --program <slug>` is blocked this turn" (`router.py:615-628`).

   The operator's actual request is never answered. The best case is a reply made of certificate lines, perhaps
   with a model line saying it was routed as completeness.

2. **Tool deny.** Every tool call is denied except a bare `gate.sh --render|render --program <slug>` or
   `cc-research verdict <slug>` with no shell separators (`router.py:902-911` and `952-967`). That includes Read,
   Edit, Write, Grep and every Bash command, not just research verbs.

3. **Stop check.** If the model tries to answer the real question anyway, `completion-assert.sh` ARM R
   (`hooks/completion-assert.sh:264-309`, decision in `router.py:1074-1105`) blocks the reply in these cases:
   - it names any file path, `file:line`, back-quoted token, row or check number, or id not in the certificate;
   - it opens with "no" without citing one of the three events;
   - it adds more than 3 lines.

   The model is then told to re-answer with the certificate only. The cap is `COMPLETION_RELAY_MAX` = 2 relay blocks
   (`completion-assert.sh:295`). As written, the count is kept in one file per (config, session, cwd) key, so the cap
   is per session rather than per turn (`:289-298`; read from the code, not tested). **So one false relay can take up
   to 3 model replies, none of which answers the operator.**

4. **How long it lasts.**
   - The label stays until the next **genuine** prompt; `cmd_prompt` overwrites it (`router.py:680-707`).
   - A machine-envelope prompt does not change it: `<task-notification>`, `<teammate-message>`, `[handoff …]`, a
     `HANDOFF-ENGAGE-` brief or `<command-name>` (`router.py:119-122`). When a route record exists,
     `envelope_prompt` returns without touching it (`router.py:729`). That is "a continuation keeps the label of the
     last genuine prompt" (REPORT `:798-799`).
   - A test locks this in: a pushback label survives a later envelope prompt even when the envelope carries
     `--requires-gate` (`tests/research-router.bats:229-236`).
   - **Practical effect.** Suppose a background Agent or Workflow was started on an earlier work-order turn, and the
     operator then sends an ordinary prompt that is falsely relayed:
     - every tool call that agent makes from then on is denied (§1, shared `session_id`);
     - when it finishes, its `<task-notification>` turn runs under the relay label, so its results cannot be acted
       on;
     - this lasts until the operator types again.

     The operator's normal pattern is many background agents per session, so this is likely the biggest cost (an
     estimate from reading the code; I did not measure how often it happens).

5. **What the operator sees.**
   - The router puts a `systemMessage` (operator-visible) only on the third consecutive *fallback*
     (`router.py:714-719`), never on a relay.
   - The route itself goes only into the model's `additionalContext`.
   - `operator-readout.sh` shows pending concerns and the priced menu, not routes (`hooks/operator-readout.sh:587-632`).
   - So the operator learns about the misroute only from a certificate-shaped reply that ignores their prompt.

**Can the operator recover?**
- **By rephrasing.** The next genuine prompt is classified afresh (`router.py:680-707`), and the bad label does not
  carry into it. That is not deterministic.
  - On the tuning set, the shipped union classifier relayed 7 of 42 agreed non-relay rows at least once in 2 reps.
  - 2 of those 7 were relayed in both reps (measured: Python over
    `docs/research/router-classifier-e1g-2026-10-05/tune-2reps.json` arm `union` against
    `tuning-labels-{anthropic,openai}.jsonl`).
  - So re-sending the identical prompt relays it again roughly 2 times in 7 (estimated, n = 7). A reworded prompt
    keeping the same cue is probably similar, but that is not measured.
- **An existing override, which is too strong and undocumented.** Any genuine prompt containing
  `--requires-gate <anything>` is labelled `work-order` without the classifier (`router.py:528-530`, test
  `research-router.bats:189-195`). `work-order` is `ALLOW_ALL` (`router.py:91-94` and `948-949`), so it unlocks every
  tool **including Agent, Workflow and the vendor CLIs**. The regex accepts any slug, not just the program's
  (`router.py:105`). It was built so `handoff-fire.sh` briefs could be labelled (REPORT §10 item 3, `:1371`), not as
  an operator override. As an override it weakens the guard more than recovery needs.
- **Kill switches.** `CC_RESEARCH_BLOCK=0` turns off the tool deny, `CC_RESEARCH_ROUTER=off` turns off routing, and
  `CC_RESEARCH_RELAY_CHECK=0` turns off the Stop check (`router.py:44-48`, `research-block.sh:18`,
  `research-precognition-nudge.sh:27`). They are read only from the environment Claude Code was launched with, so
  using one means relaunching the session. They are not a per-turn recovery.
- **There is no one-turn, scope-limited override today.**

## 3. How often an operator would hit it

**False-relay rate per ordinary prompt** (measured: `reading-v3-2026-10-05.jsonl`, router labels only)
- In stratum `other` (148 counted prompts), the router answered:

  | Router label | Prompts |
  |---|---|
  | completeness | 28 |
  | pushback | 8 |
  | work-order | 34 |
  | other | 47 |
  | research-order | 15 |
  | new-idea | 10 |
  | concern | 6 |

- That is 36 relays. 113 were correct and 35 wrong, so at most 35 relays are false and at least 1 had relay gold.
- False-relay rate in `other`: **≈ 35/148 = 0.24** (Wilson 95% CI 0.18–0.31; estimated from those measured counts).
- The relay-gold stratum totals are from RESEARCH_PROGRAM_BUILD.md E1g. The router-relayed counts are from the same
  reading file. Subtracting gives:
  - regex-matched: 58 relayed − 47 relay-gold relayed = 11 false relays out of 67 non-relay-gold prompts (≈ 0.16);
  - regex-missed: 50 − 24 = 26 out of 155 (≈ 0.17).
- A relay comes back fast: median 0.58 s for the 36 relayed `other` prompts, against 6.2 s for non-relayed ones
  (measured, same file). The cost is the lost turn, not the wait.
- `other` is the population stratum: about 25,000 of the miner's pool, against roughly 430 completeness candidates
  (E1g phase 4). So about **0.2 per ordinary prompt** is the right planning number.

**Prompts per day in program sessions** (measured: `python3 /tmp/e1h-research/count_prompts.py`, counts only)

| Source | Genuine prompts | Detail |
|---|---|---|
| Transcripts with `cwd` under the registered root `tm2-plan` | 0 | plus 10 envelope prompts |
| `history.jsonl` entries with `project` under the registered root | 4 | over 2 days |
| Transcripts with `cwd` under the sibling `tm2-plan-replan` | 37 | 12 sessions, 5 active days (2026-09-29 to 10-03); mean 7.4/day, median 5, max 19; plus 92 envelope prompts |
| Prompts from other cwds that name `tm2`, `TrueMemory 2.0` or `truememory-2-0` (would route by key 2) | 58 | 8 days (2026-09-28 to 10-05); mean 7.2/day, max 13 |
| All of the operator's prompts, every cwd and account | 6,571 | last 30 active days; mean 219/day |

- The `tm2-plan-replan` directory is **not** under the registered root, so the router would not catch it by cwd.
  That is a coverage gap in the registry, separate from this question.

**Expected false relays per day for a certified program** (estimated)
- Program-session prompts multiplied by the 0.20–0.24 false-relay rate.

| Scenario | Prompts/day | False relays/day |
|---|---|---|
| Planning pace seen for TM2 (≈ 7 by cwd + ≈ 7 by name) | ≈ 15 | ≈ 3 |
| Build phase with several build sessions in the root (assumed 40, about a fifth of the operator's daily total) | 40 | ≈ 8–10 |

- Each false relay costs:
  - one turn with no answer, and up to 2 forced Stop-check re-answers;
  - a rephrase, which is relayed again about 2 times in 7;
  - every in-flight background agent in that session stalled until the operator types again.

## 4. Cheaper designs that bound the cost, judged against §4.1–4.2

**What the method is protecting** (REPORT `docs/research/upfront-research-exhaustion-2026-09-30/REPORT.md`)
- **G1. No research starts on a re-ask.** "A re-ask can start research only if the classifier positively mislabels
  it as a work order or a new idea" (`:811-813`). Research verbs are allowed only on `work-order` or `new-idea`
  (`:794-797`).
- **G2. No material is gathered for a new item.** A relay turn denies every tool except the certificate read, "so the
  turn cannot gather material for a new item" (`:800-802`).
- **G3. No model decides.** "Nothing a model thinks during an ask can change it" (§4.4). The relay has "no verbs and
  no menu" (`:815-817`).
- **The method's own cost asymmetry.** "A wrong fallback costs one turn without research tools; a missed completeness
  ask restarts research" (`:783-785`). The method has already moved off fail-closed once: §10 item 3 (`:1371`, built
  at `router.py:629-635` and `1085-1093`) made `unavailable` deny research verbs only, plus a Stop check on any reply
  that opens with a verdict.

**Key fact.** A falsely relayed ordinary prompt would correctly get `other`, which already blocks research verbs
(`router.py:662`, `973-990`). So everything a false relay costs beyond the correct label comes from G2 and the forced
relay text, not from G1. Any fix that drops the false relay to `other`-level rights, and never to `work-order`, keeps
G1 intact.

**(a) The relay turn tells the model "if this was not a completeness question, say so, and the next prompt
proceeds".** Rejected.
- It breaks G3. The actor the guard constrains would decide whether the guard applies, and a model inclined to keep
  researching would say "not a completeness question".
- It also adds a verb to the relay, against `:815-817`.
- The Stop check would count the line as one of the 3 extra lines, so it would not stop it.

**(b) A one-word operator override, scoped to `other`.** Recommended, with the conditions below. The router, not the
model, appends one operator-visible `systemMessage` to every relay turn, and (c) is the same notice. Example:
"routed as completeness by the <fast|careful> call; if it was not, reply `misrouted`." When the next genuine prompt
is exactly the token:
- the router skips the classifier;
- it records `label=other`, `by=override` and `prompt_sha` of the overridden prompt;
- the model is told to answer the *previous* prompt under `other` handling.

Conditions:
- **(i)** The override grants only `other` rights. Research verbs stay denied (`router.py:973-990`), so G1 is
  unchanged. It must never map to `work-order`.
- **(ii)** It is one-shot, accepted only right after a relay turn, and logged and counted as "operator-overridden
  relays" in `operator-readout`, next to the fallback counter (`REPORT.md:785`).
- **(iii)** The Stop check treats an override turn like `unavailable`: a reply that opens with a yes/no verdict is
  still checked as a relay (`router.py:1085-1093`). That keeps §4.4's no-added-items rule for the case where the
  operator overrides a real completeness ask.
- **(iv)** It is a typed operator act inside the session, the same authority class as rephrasing, so G3 holds.

Residual weakness: on a real completeness ask, an operator who overrides gets a turn with Read and Bash available, so
G2 is partly given up for that one turn. The operator chose that, and (iii) still catches a verdict-shaped reply that
adds items. Cost per false relay goes from "a rephrase that is re-relayed about 2 times in 7, plus stalled agents" to
one word and one turn.

**(c) An operator-visible route notice on every relay turn** (`systemMessage`). Recommended regardless.
- It costs nothing against G1–G3: it is a status line, not a menu, which `:815-817` allows as long as the priced menu
  stays in `operator-readout`.
- It removes the hidden part of the cost: today only the model sees the route (`router.py:714-719`).

**(d) A relay label is not carried into machine-envelope continuations.** Recommended.
- On a `<task-notification>`, `<teammate-message>` or `[handoff …]` turn after a relay, use `other` (research verbs
  denied) instead of the relay. Equivalently, the deny should exempt tool calls carrying a subagent `agent_id`, with
  research verbs still denied.
- G1 holds because research verbs stay denied. G2 is barely touched, since the relay reply was already given and
  Stop-checked.
- It follows the precedent §10 item 3 set for fallback labels ("never let a continuation inherit a fallback label",
  `:1371`).
- It needs a REPORT §4.2 text change (`:798-799`), and the test at `research-router.bats:229-236` would flip.

**(e) Narrow the existing `--requires-gate` shortcut.** Accept it in a *genuine* prompt only when the slug equals the
routed program, or map it to `other` there and keep `work-order` for machine envelopes. Today it is an undocumented,
research-unlocking override for any operator who knows the marker (`router.py:105`, `528-530`).

**Not recommended as cheap: a "soft relay"** (treat a relay from only one of the two calls like `unavailable`). It
would keep G1 but give up G2 on exactly the subtly worded asks the careful call was added to catch, and it changes
the recall the E1g union rule earns. That is a classifier redesign, not a cost bound.

**What none of these fixes.** Row 15's `other` ≥ 0.90 floor (REPORT §10 item 11, `:1379`) still fails on v3, and
(b)–(e) do not change any gate row. They lower the cost of each false relay; they do not lower the false-relay rate.
A ruling could cite (b)–(d) as the reason the method can accept a higher false-relay rate, but that would be a change
to row 15's threshold, which only the operator can make.
