# Axis 07: census of "should we …?" and other advisory turns

Slot: transcript census. Read-only, apart from this file and the scratch scripts in `/tmp/should-census/`.
Date: 2026-10-18. Window: transcripts modified in the last 30 days.

## 0. Answer first

- **Most advisory questions do get acted on.** Of 124 matched operator turns, 95 (77%) contained at least
  one write or act tool call before the next operator message. 16 (13%) ended in a recommendation or plan
  with no act. 13 (10%) were answered with nothing to do. (Measured: `census.py`, then `summarize.py`.)
- **The share that stops is higher when the operator literally writes "should we".** In that subset, 11 of
  55 turns (20%) were recommended-and-stopped. (Measured, same scripts.)
- **I read all 16 recommended-and-stopped turns by hand.** 5 are clear defects: drivable work was
  recommended (at up to >90% conviction) and the turn ended. 3 are borderline. 6 were legitimate stops at a
  value fork or on advice the operator acts on personally. 2 are classifier misses where the answer text
  was the deliverable. (Estimated: hand reading, §3.)
- **The mechanical cause is measured.** No Stop hook fired in any of the 16 recommended-and-stopped
  windows, against 32 of 95 acted windows (measured: `census.py` counts `Stop hook feedback` meta rows per
  window). Advisory turns go unseen for two reasons:
  1. `completion-assert.sh` abstains with `no-close-tell` unless the message matches `CLOSE` or a settled
     line 1 (`hooks/completion-assert.sh:394-397`). 14 of the 16 final texts match neither (measured:
     `grep -iqE "$CLOSE"` over the last 1,500 characters of each final text). So the D4 offer arm at
     `:1272-1286` never runs on them.
  2. When D4 does run, its lexicon `CA_OFFER` (`hooks/completion-assert.sh:1280`) matches only 2 of 16
     recommended-and-stopped finals, and **0 of the 42** assistant turns that came right before a short
     operator "yes / proceed / do it" (measured: `gate.py` / inline test). The agents' real permission
     phrasings are "If you agree, I'll …", "If you say yes, I'll …", "Shall I build it …", "Should I build
     this set?", "Reply "go" and I'll …", "Say if you want it added" and "If you want me to drive it, say
     so". None of them are in the lexicon.
- **The round trip this costs is visible.** Over the 30 days there were 42 short operator affirmations
  (≤80 chars, such as "Proceed.", "Yes", "Proceed with your recommendations."). 23 came right after an
  assistant turn carrying a recommendation, and 19 after one ending in a permission ask (12 had both).
  Separately, 25 operator messages contain "proceed with/as your recommendation(s)". That figure includes
  some fired briefs that quote the phrase. (Measured: `affirm.py`, `phrases.py`.)

Conviction that this axis has found a real, mechanically-explained gap: **85%**.

## 1. Method

Scripts are in `/tmp/should-census/`, and all of them were run with `python3 -I`:

- `census.py` scans `~/.claude{,-secondary,-tertiary,-quaternary,-next,-next4}/projects/*/*.jsonl` with
  mtime within 30 days. It skips `subagents` paths and `/projects/-private-*` (tmp test harnesses such as the
  router-labeling runs, which are prompts built by a script). That leaves 3,294 files and 7,254 real
  operator messages, measured.
  - **Real operator message.** `type=user`, not `isMeta`, not `isSidechain`, no `tool_result` block, and text
    that does not start with `<`, `[Request interrupted`, `Caveat:`, `[Workflow harness`,
    `This session is being continued`, `Another Claude session sent a message`, `[limit-recover]`,
    `You are labeling operator prompts` or `Stop hook feedback`.
  - **Match.** `^(should we|should i|do we|can we|would it|is it worth|what do you think|thoughts on|do you recommend)\b`
    (case-insensitive) or containing "should we". 124 matches after de-duplicating copies of the same
    session moved across accounts, keyed on (text[:300], timestamp-to-minute).
  - **Response window.** Every assistant row up to the next real operator message.
  - **ACT tool calls.**
    - Edit, Write, MultiEdit or NotebookEdit to a path outside `/tmp` or `/var/folders`.
    - Agent, Task, Workflow or Skill.
    - An MCP tool whose name carries a write verb.
    - A Bash command that matches an explicit write pattern: a redirect to a non-tmp file, `sed -i`,
      `rm`/`mv`/`cp`/`mkdir`, a git write subcommand, a `gh` create or merge, `cc-backlog`/`cc-decide`
      add/claim/close/open, `handoff-fire`, `ship`, a script run in command position without a read verb,
      an install, `launchctl`/`defaults` writes, or `tmux send-keys`. Single-quoted spans (awk/jq programs)
      are stripped first, and `--help` counts as a read.
  - **Classes.** `acted` means ≥1 act. `recommended-and-stopped` means 0 acts and the final text matches a
    recommendation or plan pattern ("I'd", "I would", "recommend", "What I'd do", numbered steps,
    "next step", "Want me to", "Shall I", "Should I", "if you want", "I can"). `answered-no-action-needed`
    is everything else.
  - **Next-message signal.** Affirmation (`^yes|ok|sure|go|go ahead|do it|proceed|continue|please…`) and
    complaint (`why didn't you|you should have|stop asking|…`).
- `summarize.py` aggregates the census.
- `affirm.py` runs the reverse census. It takes every short (≤80 chars) operator affirmation and inspects
  the assistant text just before it.
- `phrases.py` counts phrases across all 5,137 de-duplicated real operator messages.
- `gate.py` measures candidate hook lexicons against the classes.

Precision checks:
- I hand-checked 12 random `acted` windows with ≤2 acts and found 2 false positives: a `--help` run, since
  fixed, and a `rm -rf /tmp/…; cc-mail-images` fetch (estimated precision ≈83% on low-act windows, and higher
  on windows with more acts).
- A bug in the Bash classifier (`census.sh scripts/…` matched `\bsh\s`) labelled both incident turns as
  `acted`. After the fix, both are `recommended-and-stopped`. That matches INCIDENT.md, which is the method's
  ground truth.

## 2. Counts (measured: `python3 -I /tmp/should-census/summarize.py`)

| Slice | n | acted | recommended-and-stopped | answered-no-action |
|---|---|---|---|---|
| all matches | 124 | 95 (77%) | 16 (13%) | 13 (10%) |
| opening-regex matches | 85 | 68 (80%) | 10 (12%) | 7 (8%) |
| "contains should we" only | 39 | 27 (69%) | 6 (15%) | 6 (15%) |
| text contains "should we" | 55 | 38 (69%) | 11 (20%) | 6 (11%) |
| operator message <800 chars | 115 | 87 (76%) | 16 (14%) | 12 (10%) |

| Signal | acted (95) | rec-and-stopped (16) | answered (13) |
|---|---|---|---|
| Stop hook fired inside the window | 32 | **0** | 2 |
| acted only after a Stop hook fired | 7 | n/a | n/a |
| next operator message present | 74 | 14 | 11 |
| next message matches the affirmation regex | 6 | 2 | 2 |
| next message matches the complaint regex | 0 | 0 | 0 |
| final text matches the `CA_OFFER` lexicon (`completion-assert.sh:1280`) | n/a | 2 | n/a |
| final text carries the `CLOSE` tell (`completion-assert.sh:355`) | n/a | 2 | n/a |

Of the 95 acted windows, 7 acted only after a Stop hook fired. In those, continuation was driven by the
hook, not chosen. In all 7 the hook was a landedness or loose-end arm, not an advisory one (measured: the
`act_pre_hook` field).

**Reverse census** (measured: `python3 -I /tmp/should-census/affirm.py`):
- There were 42 short operator affirmations in 30 days. 23 were preceded by a recommendation and 19 by a
  permission ask; 12 had both.
- `CA_OFFER` matched **0 of 42**.
- The most common wordings: "yes" (7), "continue" (3), "sounds good" (3), and four variants of "proceed with
  / as your recommendation(s)" (7 together).

**Phrase census** (measured: `python3 -I /tmp/should-census/phrases.py`, 5,137 de-duplicated real operator
messages):

| Phrase | Count |
|---|---|
| starts with proceed / yes / go ahead / do it | 53 |
| "proceed with/as your recommendation(s)" | 25 (some are fired briefs that quote it) |
| "don't ask" / "stop asking" variants | 7 (all inside briefs) |
| "enact" / "continue exhaustively" | 2 (the incident's own follow-up and this study's brief) |
| "why didn't you" | 1 |

## 3. Hand classification of the 16 recommended-and-stopped turns (estimated: reading each final text)

| id | Transcript : operator line → final line → next line | Verdict |
|---|---|---|
| rs04 | `~/.claude-secondary/…wt-cc-004752-67086/5759497b-….jsonl` :112 → :121 → :127 | **DEFECT** (incident) |
| rs05 | same file :127 → :167 → :179 | **DEFECT** (incident) |
| rs11 | `~/.claude-tertiary/…reso-landing-design-research/eedf5623-….jsonl` :65 → :91 → :130 | **DEFECT** (announced the next step, then stopped) |
| rs13 | `~/.claude-quaternary/…wt-cc-224434-52011/7b65812a-….jsonl` :311 → :437 → :444 | **DEFECT** |
| rs14 | `~/.claude-quaternary/…wt-cc-212923-58948/4a70830c-….jsonl` :938 → :958 → :964 | **DEFECT** (cost signal "Proceed.") |
| rs03 | `~/.claude-secondary/…wt-cc-205652-27362/e2b41770-….jsonl` :465 → :490 | borderline (account action through the GUI) |
| rs09 | `~/.claude-tertiary/…claude-infrastructure/41eee6a5-….jsonl` :1103 → :1107 | borderline (about 48 sessions of spend; the agent called it "your call" but filed nothing) |
| rs15 | `~/.claude-quaternary/…wt-pool-7/69629b66-….jsonl` :167 → :213 | borderline (85%, but it reverses an operator-requested change) |
| rs00, rs01 | `~/.claude/…reso-landing-design-research/58d3640a-….jsonl` :3359, :3376 | legit value fork (the operator chose the opposite page at :3386, so asking paid) |
| rs02 | `~/.claude-secondary/…claude-infrastructure/e284b030-….jsonl` :111 | legit UX preference fork |
| rs07, rs08 | `~/.claude-secondary/…personal/05af12f0-….jsonl` :686, `…/e7659abe-….jsonl` :681 | legit personal or housing advice the operator acts on |
| rs12 | `~/.claude-tertiary/…wt-cc-022946-79382/f4c84c9d-….jsonl` :2063 | legit ("Recycle at 63%? No. Close the pane instead.") |
| rs06, rs10 | `…wt-pool-7/e7666118-….jsonl` :1556; `…41eee6a5-….jsonl` :1424 | classifier miss: the answer text was the deliverable |

Rates (estimated):
- Clear defects are 5 of 124 advisory turns (4%), or 8 of 124 (6.5%) counting the borderline cases.
- Within recommended-and-stopped, they are 5 of 16 (31%), or 8 of 16 (50%).
- The cost signal shows on 3 of the 5 clear defects, after hand reading of the next message:
  - rs14: "Proceed."
  - rs13: pushback, "can WE get our sessions going now while we research the long-term fix?"
  - rs04: the operator later had to command the recommended work at :179 ("ultracode research the best
    startup hook improvements…").

## 4. Ten quoted examples (transcript path : line)

1. **Incident, step 1 at >90% and stopped.** `~/.claude-secondary/projects/-Users-chrisren-Development--worktrees-wt-cc-004752-67086/5759497b-3947-4fd7-9d8b-e095bf134dbf.jsonl`
   - :112, operator: "Should we investigate in improving our startup hook performance time?"
   - :121, final text: "**What I'd do, in order:** 1. **Log per-child timing.** … It's small and safe, and I'm over 90%
     sure it's worth doing."
   - The window had 0 act tool calls and 0 Stop hook fires. The operator's next turn (:127) was another
     "should we", and :179 had to command the research.
2. **Incident, second instance, same file.**
   - :127, operator: "Should we, in parallel, investigate the current heavy load? … should we make this as
     skill as well"
   - :167, final text: "What the skill would do: 1. Move `rusage-attrib.py` into `bin/` as a real command, with a test.
     … The draft goes to `~/.claude/skills-pending/` …"
   - Nothing was started.
3. **85% recommendation, then "Proceed."** `~/.claude-quaternary/projects/-Users-chrisren-Development--worktrees-wt-cc-212923-58948/4a70830c-c54e-4ee0-b965-175dc9550f8e.jsonl`
   - :938, operator: "Can we make it such a chime doesn't require a privacy permission each time to begin with?"
   - :958, final text: "**I recommend the chime player, at 85% confidence.**"
   - :964, operator: "Proceed."
4. **"Shall I build it", then pushback to act now.** `~/.claude-quaternary/projects/-Users-chrisren-Development--worktrees-wt-cc-224434-52011/7b65812a-6912-4304-8d3d-179a3020844d.jsonl`
   - :311, operator: "Should we improve our peer mail affordance and visibility?"
   - :437, final text: "My confidence in this design is about 80%. … Shall I build it as a separate session?"
   - :444, operator: "can WE get our sessions going now while we research the long-term fix?"
5. **Announced the next step, then ended the turn.** `~/.claude-tertiary/projects/-Users-chrisren-Development-reso-landing-design-research/eedf5623-387c-40fa-93b1-5266751a62b0.jsonl`
   - :65, operator: "Can we do some open creativity … via Nano Banana 2.5?"
   - :91, final text: "Next I'll check which "Nano Banana" model IDs it lists."
   - :130, operator: "Please look into reso-management-app how we call Nano Banana API directly"
6. **Two recommendations at ≥90% routed to the operator as "yours".** `~/.claude-next/projects/-Users-chrisren-Development-claude-infrastructure/d41d9684-9b9f-4c9d-a73c-517a4bdf9885.jsonl`
   - :1126, final text: "Two answers are still yours: 1. … My recommendation is `a`, 92% sure. 2. … My recommendation is
     `watch-then-file`, 90% sure. You can reply `a; watch-then-file`."
   - :1138, operator: "Proceed with all recommendations as they are >=90% conviction."
   - This contradicts the live FILED rule that `needs-human` requires `--conviction N` with N ≤ 90
     (`CLAUDE.rules.slim.10-session-close.md:185`).
7. **"If you say yes, I'll …".** `~/.claude/projects/-Users-chrisren-Development--worktrees-wt-pool-8/498334c2-e6b9-4d84-94b0-bded3f6f76e0.jsonl`
   - :622: "If you say yes, I'll send it both changes as added scope."
   - :628, operator: "Proceed with your recommendations."
8. **"Should I build this set?".** `~/.claude/projects/-Users-chrisren-Development--worktrees-wt-pool-7/6defb493-e229-4318-b0ab-86e7167c39e3.jsonl`
   - :1416: "Should I build this set? The first two items together become one change and the send-at-hide fix
     a second, each started as its own build session."
   - :1421, operator: "Yes, proceed with all recommendation set."
9. **Named remaining work as "not mine", which is the incident's shape.** `~/.claude-secondary/projects/-Users-chrisren-Development-claude-infrastructure/26cd14be-a7a4-422f-b568-cfd4609e0806.jsonl`
   - :1605: "One thing still open and it is not mine to close: the five standing reds … That's the real capacity
     lever whenever you want it picked up."
   - :1622, operator: "Proceed to full completion"
10. **"If you approve 1–3, I'll …".** `~/.claude-secondary/projects/-Users-chrisren-Development-claude-infrastructure/dac96eea-f0c2-4516-8fe6-8a1a32f1e0f2.jsonl`
    - :113: "If you approve 1–3, I'll re-index the 10 files, fix the 4 links, and write the hook and title
      rewrites to a file for you to approve before I apply them."
    - :120, operator: "Proceed with all"

Counter-example, where asking was right: `~/.claude/projects/-Users-chrisren-Development-reso-landing-design-research/58d3640a-a6ed-4686-989c-3e1359b59ae4.jsonl`.
At :3380 the agent offered "If you agree, I'll start with step 1 … for join.reso.gl", and at :3386 the
operator picked the other page ("I feel reso.gl consumer facing one is eaiser to start with"). A fix must
leave a real value fork able to stop.

## 5. Root causes on this axis

1. **Advisory turns are invisible to every Stop arm** (90%).
   - `completion-assert.sh` gates every conviction arm, D4 included, behind a close tell:
     `grep -iqE "$CLOSE"` or a settled line 1, else `abstain "no-close-tell"` (`hooks/completion-assert.sh:394-397`).
     A "What I'd do, in order" answer has no done-verdict.
   - `session-continue.sh` fires on landedness.
   - Measured: 0 Stop hook fires in 16 of 16 recommended-and-stopped windows, and 14 of 16 finals lack a
     `CLOSE` tell.
2. **The offer lexicon does not cover how agents actually ask** (85%). Measured hit rates for `CA_OFFER`
   (`hooks/completion-assert.sh:1280`): 2 of 16 recommended-and-stopped finals, and 0 of 42 turns before an
   operator affirmation. The "offer" in practice is conditional consent: "If you agree / say yes / approve,
   I'll …", "Shall/Should I build …", "Reply "go"", or a plain recommendation with no ask at all (example 1).
3. **The rule text covers the case but nothing enforces it** (75%).
   - E0 already says "A read-only turn that names drivable work is not E0: run the Follow-On Gate on each item
     and drive the passes … before yielding" (`CLAUDE.rules.slim.10-session-close.md:99`).
   - The disposition table's advisory row reads "No ledger, no auto-continue, no readout"
     (`CLAUDE.rules.slim.10-session-close.md:34`; global `CLAUDE.global.md:601`).
   - An agent reading only the table row gets a licence to answer and yield. The 4% clear-defect rate shows
     the rule mostly holds, and that the residual is unenforced.
4. **Recommendations at ≥90% are presented as operator decisions** (65%). In example 6, a 92% and a 90%
   item became "answers still yours", against the N ≤ 90 needs-human ceiling
   (`CLAUDE.rules.slim.10-session-close.md:185`). The ceiling is enforced only by `cc-backlog add`, not in
   prose.

## 6. Fix candidates (with the brief's constraints)

- **F1: an advisory-stop arm in `completion-assert.sh`, evaluated before the `no-close-tell` abstain** (70%).
  - **Fires when:** the turn since the last real operator message made 0 act tool calls (transcript scan;
    `TP` is already read at `:186`), AND the final text carries a first-person plan or recommendation of
    work, AND that recommendation matches an expanded permission or plan lexicon.
  - **Plan patterns:** `What I'd do`, `I recommend`, `My recommendation`, `The move is`, a stated conviction
    ≥85, `Next I'll`.
  - **Permission patterns:** `if you (agree|approve|say (yes|so|go))`, `say (so|if|yes|go)`, `reply "?go`,
    `(shall|should) i (build|start|do|fire|drive|run|send|apply|make)`,
    `do you want (that|this|it) (built|done|…)`, `whenever you want it picked up`.
  - **Abstains on:** `GENUINE` (`:400`), a `⛔` rung or `cc-decide open` this turn, an active research
    program, and the existing per-class one-shot latch and cap.
  - **Measured on this corpus** (`gate.py`): it hits 8 of 16 recommended-and-stopped finals, including 3 of
    5 clear defects (rs04, rs13, rs14), and misses rs05 and rs11. Adding `would do:\s*\n\s*1\.` and
    `Next I'll` covers both, untested. It hits 0 of 13 answered turns, and acted turns are excluded by the
    0-act condition. Its false hits are 2 legitimate forks (rs01, rs02), which the ⛔/cc-decide abstain lets
    stop if they are filed as decisions.
  - **Always-firing risk:** silent whenever the turn acted or no recommendation of work exists. The main
    risk is small preference forks being pushed toward `cc-decide` filings.
- **F2: widen `CA_OFFER` (`hooks/completion-assert.sh:1280`) with the observed conditional-consent forms**
  (75%; risk: low).
  - **Change:** `if you (agree|approve|say (yes|so|go))`, `say (so|if)( you)?`, `reply "?go`,
    `(shall|should) i (build|start|fire|drive|send)`, `whenever you want it picked up`. Leave out
    `your call`, which appears in genuine value forks (rs09, rs15).
  - **Measured:** the current lexicon hits 0 of 42 pre-affirmation turns, and this widening hits 11 of 42.
  - **Risk:** D4's remaining-work-outside-the-offer half still applies (`:1286`), which bounds false fires.
  - **Benefit:** this helps closes only, unless F1 lands too.
- **F3: rule text, a net-zero swap** (60%).
  - **Add** to the E0 bullet (`CLAUDE.rules.slim.10-session-close.md:99`): "A "should we X?" whose answer is
    yes and whose X is drivable is a request: start X's first step this turn; stop only at a ⛔ fork filed
    with `cc-decide open --class C`."
  - **Cut** a matching amount from the advisory row at `:34` by replacing "Work the turn itself named is not
    exempt (see E0 below)." with "(see E0)". Mirror the change in `CLAUDE.global.md:601`.
  - The net change is ≈ +25 words; finding the remaining cut needs a word count before landing.
- **F4: enforce the ≥90 ceiling in prose** (55%).
  - **Change:** an arm or extension that fires when a close or answer lists items as "yours", "your call" or
    "your answer" while stating conviction ≥90 for its own recommendation, with no `cc-decide` filed.
  - **Evidence:** example 6.
  - **Measured volume:** small; 2 of 42 pre-affirmation turns carry a conviction ≥85.
  - **Always-firing risk:** low, because it needs both the number and the "yours" framing.

## 7. Limits

- The window ends at the next real operator message, so a turn the agent continued after the operator went
  away is counted as one window.
- A queued operator message can split a turn (rs06 shows text output with 0 tools in its window).
- The affirmation and complaint regexes under-count. rs13's pushback ("can WE get our sessions going now")
  matched neither, so the cost signal comes from hand reading.
- Under-coverage: questions phrased as "is there any utility to…", "why or why not should we…" or "what
  should we do with…" match only when they contain "should we".

## Skeptic verdicts

Skeptic pass, 2026-10-18. Read-only apart from this appended section. Every re-check below names the command
or file:line it rests on. Scratch checks were inline `python3 -I -` over `/tmp/should-census/out.json`,
`/tmp/should-census/affirm.json`, the cited transcripts, `~/.claude/autonomy/idl.jsonl*` and the hook's own regexes
(pulled from `hooks/completion-assert.sh` with `sed`). No scratch files were written.

### S0. The headline correction: the mechanism in §0/§5.1 is wrong for 4 of the 5 clear defects

The axis tested the finals against `CLOSE` only. The close-tell gate also lets a message through when its
**line 1 matches `CA_SETTLED`** (`hooks/completion-assert.sh:394-397`), and `CA_SETTLED` contains
`^[^A-Za-z]*yes([^a-z]|$)` (`:360`). An answer to "should we X?" that opens "Yes, …" is a close by that test.

- Measured (python + `grep -iqE` with the hook's own `CLOSE`, `CA_SETTLED`, `CA_VERDICT_NO` on the **full**
  final texts, not the 1,500-char tails in `finals/`, 12 of which are truncated at exactly 1,500 chars):
  7 of 16 recommended-and-stopped finals pass the gate (rs01, rs04, rs05, rs09, rs12, rs13, rs14), including
  **4 of the 5 clear defects**. Only rs11 fits the "no-close-tell" story.
- So what actually happened at those Stops? Measured from the transcripts' `stop_hook_summary` rows and the IDL:

| id | completion-assert live result | durationMs (stop_hook_summary) | Evidence |
|---|---|---|---|
| rs04 (incident) | **no IDL record at all**; killed | 5,687 | `5759497b…jsonl:124`; the configured timeout is `"timeout": 5` (`~/.claude/settings.json:1049`). The two no-close-tell Stops either side ran 793 ms (`:109`) and 749 ms (`:176`). |
| rs14 | no IDL record; killed | 5,077 | `4a70830c…jsonl:961` |
| rs05 (incident) | `no-close-tell` at 06:04:16Z | 749 | IDL (`idl.jsonl.20261018T105203Z.gz`). The final record `:167` is stamped 06:04:16.097Z; the text record before it (`:145`) yields no-close-tell on replay; the final itself passes. |
| rs13 | `no-close-tell` at 04:09:04Z | 1,040 | IDL (`idl.jsonl.20261013T023256Z.gz`). The final `:437` passes the gate **and D4's (a)+(b)** on replay (it says "Shall I build it"). `anti-deference-nudge` logged `no-tell` in the same second, though its `TELLS` contains `shall i` (`hooks/anti-deference-nudge.sh:168`). |
| rs11 | not in this IDL window | n/a (no summary row) | the only case the axis's mechanism covers |

  rs01 shows the same pattern as rs05/rs13 (live `no-close-tell` at 17:30:32Z, final passes on replay).
- **Reading.** rs05, rs13 and rs01 are consistent with a Stop hook reading a transcript that does not yet
  hold the final text record. Both hooks take `MSG` from the transcript tail (`hooks/completion-assert.sh:282-285`,
  `hooks/anti-deference-nudge.sh:159-162`). Neither reads the Stop payload's `last_assistant_message`, which a
  prior pass already flagged (`docs/research/claude-code-mods-2026-10-03/REPORT.md:34`: "never read
  `last_assistant_message` … Reading it removes the transcript scan behind the old 74% blind rate").
  Conviction that this race explains rs05/rs13/rs01: 70% (timing plus replay; not reproduced live).
- **Scale of the timeout leg.** Measured over `stop_hook_summary.hookInfos` in the same 3,294 files: 4,426 of
  24,443 completion-assert Stop runs (18.1%) took ≥5,000 ms in 30 days. On 2026-10-18 after 10:53Z it was 17 of
  1,473 (1.2%), so the timeouts cluster in loaded periods, such as the incident's own morning.
- **What the existing arms would have done had they seen the final and finished** (replay, same regexes):
  rs13 → D4 fires (current `CA_OFFER` already matches). rs04 → D3 fires ("Yes, but keep it narrow." is
  `CA_SETTLED`+`CA_RETRACT`), with a close-shape message ("a conditional yes … is a no") that asks for a
  line-1 rewrite, not for step 1 to be driven. rs05 and rs14 → nothing fires.
- **Live arm health** (IDL, 2026-09-28 → 10-18, 13,680 completion-assert records): the D4 `offer` arm fired
  **2 times** (both `ledger+offer`); `no-close-tell` is 10,873 (79%). `anti-deference-nudge` over 15,852 records:
  `deference` fired 24 times; `no-tell` 14,233.

### S1. Root causes

1. **RC1, "no Stop hook looks at advisory turns; they exit at no-close-tell"**: **refuted** as a mechanism
   (adjusted 20%).
   - The 0-of-16 block count is true. But 4 of 5 clear defects pass the gate (S0), and the live losses were a
     5-s timeout kill (rs04, rs14) and a stale `MSG` (rs05, rs13).
   - "No Stop hook looks at advisory turns" is false: `anti-deference-nudge.sh` has no close gate and reads the
     last message for "shall i / want me to / say the word / should i (proceed|do|go)" (`:168`). It was blinded
     on rs13 by the same race.
   - The 0/16 vs 32/95 contrast is partly selection: a window where a hook fired and the agent then acted is
     counted as `acted` (7 such windows).
   - `session-continue.sh` has a sentinel floor, a wake floor (`:618`) and a ship floor (`:1169`). None reads the
     recommendation text, so that half stands.
2. **RC2, "`CA_OFFER` misses how agents ask"**: **confirmed** (75%).
   - Re-measured on full texts: 2 of 16 and 0 of 42. D4 fired twice in 20 days of IDL.
   - It was **not the binding cause for any clear defect**, though. rs13 already matches; rs04, rs05 and rs14
     carry no ask at all.
3. **RC3, "rule covers it, nothing enforces it; the advisory row licenses answer-and-yield"**: **weakened** (55%).
   - The row at `CLAUDE.rules.slim.10-session-close.md:34` already ends "Work the turn itself named is not
     exempt (see E0 below)". `CLAUDE.global.md:601` says "*yield* governs the READOUT, never work the turn itself
     named". So the licence reading is not supported by the text.
   - Enforcement does exist (`anti-deference-nudge`, D4). It failed for the timeout, race and lexicon reasons
     in S0.
   - The 4% defect rate is a lower bound. Acted windows that drove part of the work and then asked were never
     hand-read: 6 of 95 acted finals carry the permission lexicon (`gate.py` GATE), and the act classifier is
     about 83% precise on low-act windows.
4. **RC4, "≥90% recommendations handed over as 'yours'; the ceiling is enforced only in `cc-backlog add`"**:
   **weakened** (45%).
   - The quote is verified (`d41d9684…jsonl:1126`, `:1138`). But only the 92% item breaks the rule. The rule
     lets a ≤90 item go to the operator (`CLAUDE.rules.slim.10-session-close.md:68`: "At or below 90% … hand it
     to the operator"), so the 90% item is allowed.
   - The ceiling is also enforced by `cc-decide open` (`bin/cc-decide:100`, `:211` "past the 90% threshold —
     implement it"), not only by `cc-backlog add`.
   - It rests on one example (n=1). Prose is still unchecked; that part stands.

### S2. Fix candidates

- **F1 (advisory-stop arm before no-close-tell)**: **refuted as specified** (25%).
  - The summary specifies (b) plan **AND** (c) permission ask. `gate.py` measures `GATE or PLAN`, and on
    truncated text (`r['final'][-900:]`).
  - Re-measured on full texts: the AND form hits 4 of 16 (rs01, rs08, rs09, rs15), which is **0 of 5 clear
    defects**. The incident turn rs04 has no ask. The OR form hits 10 of 16 (3 of 5 defects: rs04, rs13, rs14),
    and also the legit stops rs00, rs01, rs02 and rs08, 13 of 95 acted finals, and 21 of 42 pre-affirmation
    turns (AND: 3 of 42).
  - The insertion point is the wrong lever. 4 of 5 defects already pass the gate. An arm that reads `MSG` from
    the transcript inherits the stale-message race (rs05, rs13).
  - It duplicates `anti-deference-nudge.sh`, a gate-free deference arm that already has a latch, a cap and a
    genuine-fork carve-out.
  - **Operator-decision risk.** `GENUINE` (`:400`) matches none of rs00, rs01, rs02 (measured), so F1 would push
    all three to "drive step 1 or file class C". At rs01, "drive step 1" builds join.reso.gl, and the operator
    chose the other page (`58d3640a…:3386`). Class C also needs a conviction, a receipt and two `--option`s
    (`CLAUDE.rules.slim.10-session-close.md:160`), which is heavy for a page-order preference.
  - No test contradicts it: the no-close-tell fixtures at `tests/completion-assert.bats:1180` and
    `tests/completion-assert-forks.bats:93-104` carry no plan. But the forks test pins that path at 0 python3
    and 0 dirname, so F1's act scan must stay in bash/jq.
- **F2 (widen `CA_OFFER` at `:1280`)**: **weakened** (40%).
  - The lexicon as written in the summary hits **8 of 42** pre-affirmation turns, not 11 (measured, full text).
    On the 16 it hits rs01, rs03, rs09 and rs13, so it adds **0** clear defects, because rs13 already matched.
  - Over 7 days of turn finals (1,147, of which 303 pass the gate), widened D4 newly fires on 8 and today's D4 on
    0. This is an upper bound: the quote-stripping is not modelled.
  - Hand-reading those 8 tails, about half are legit forks or operator-owned acts. One of them is
    `58d3640a…:3380`, the very counter-example §4 says must stay able to stop.
  - D4 also runs after the ledger read, inside the slow path that hits the 5-s timeout.
  - The better home is `TELLS` at `hooks/anti-deference-nudge.sh:168`, which has no close gate.
- **F3 (rule-text swap)**: **refuted** (15%).
  - Measured `wc -w`: +34 words added, −9 cut, net **+25**, against the no-net-growth constraint.
  - The cut phrase does not exist in `CLAUDE.global.md` (grep count 0), so "make the same change at :601"
    cannot be applied.
  - The cut removes the row's own "not exempt" clause, which is the text RC3 says agents read.
  - The addition restates `:99` ("A read-only turn that names drivable work is not E0 … drive the passes …
    before yielding"), and the incident agent already had that line.
- **F4 (prose ≥90 ceiling)**: **weakened** (40%).
  - The threshold must be **>90**, not ≥90 (`:68`; `bin/cc-decide:211` refuses only N > 90). As written, it
    would fire on the legitimately handed-over 90% item.
  - It rests on n=1, and the volume is tiny (2 of 42).
  - It is cheap as a text check, but it inherits the stale-message race unless it reads `last_assistant_message`.

### S3. Measurements

- **3,294 files / 7,254 operator messages / 124 matches; class splits; next-message signals**: confirmed.
  `python3 -I /tmp/should-census/summarize.py` reproduces them from `out.json` (the census itself was not
  re-run). Two corrections to how §1 describes the method:
  - The de-dup key in `census.py` is `(sessionId, uuid)`, not `(text[:300], timestamp-to-minute)`.
  - `is_real_user` does **not** exclude "Another Claude session…", "[limit-recover]", "You are labeling…" or
    "Stop hook feedback". The last of these is harmless because those rows are `isMeta:true`.
- **0 of 16 vs 32 of 95 Stop-hook windows**: weakened. The numbers are right, but the inference is not: see
  RC1 for the selection effect and the timeout/race causes.
- **14 of 16 lack `CLOSE`, so no-close-tell**: refuted. 14 of 16 lacking `CLOSE` reproduces on full text, but 7
  of 16 pass the gate through `CA_SETTLED` line 1.
- **`CA_OFFER` 2 of 16 and 0 of 42**: confirmed on full texts.
- **affirm.py 42 / 23 / 19 / 12**: confirmed from `affirm.json` (rec 23, ask 19, both 12).
- **phrases.py counts**: confirmed. A re-run of `python3 -I /tmp/should-census/phrases.py` (read-only) gives 53 /
  25 / 7 / 2 / 1 over 5,140 de-duplicated messages; the axis had 5,137, and the transcripts have grown since.
- **gate.py F1 numbers (8/16, 0/13, 16/42)**: refuted as a measure of F1. It is an OR on truncated text. On full
  text: AND = 4/16, 0/13, 3/42; OR = 10/16, 0/13, 21/42.
- **Hand classification (5 / 3 / 6 / 2)**: weakened, as a lower bound. All 20 quoted snippets were re-checked at
  their cited lines and all 20 match (measured). The verdicts themselves are judgment; I did not re-judge them.
- **Act-classifier precision of about 83%**: weakened. It rests on a 12-sample hand check, not re-run.

### S4. What the axis missed

1. **The 5-s Stop timeout kills completion-assert on its slow path**, as in rs04 and rs14. `settings.json` is
   out of bounds, so the fix is ordering: decide the text-only arms (D3, D4, any advisory arm) before the
   ledger and backlog reads, and emit before the timeout.
2. **The Stop hooks read `MSG` from the transcript tail, which can lag the final record** (rs05, rs13, rs01).
   The fix is to prefer the payload's `.last_assistant_message`, falling back to the transcript, in
   `completion-assert.sh:282-285` and `anti-deference-nudge.sh:159-162`. That alone makes the *existing* D4 catch
   rs13. In a 7-day check of 12 finals that carried a `TELLS` phrase, the live verdicts were 4 fired,
   3 genuine-abstain, 3 `no-tell` and 2 with no record (measured; small n).
3. **`anti-deference-nudge.sh` is the existing gate-free home for permission-ask tells.** Widen its `TELLS`
   (`:168`) rather than adding a completion-assert arm.
4. **"Line 1 = yes, 0 acts this turn" is a cheap, sharper predicate than F1's lexicon.** It catches rs04, rs05,
   rs13 and rs14 (4 of 5 clear defects) plus rs01 (a legit fork) among the 16. It hits 2 of 13 answered turns,
   both legit ("Yes, we should close", "Yes. The slash command just runs `cc-lid`"), and those carry no
   plan/recommendation pattern. Measured on this sample only; n is tiny.
5. **D3 mis-reads an advisory "Yes, but …" as a hedged close verdict** (rs04). The message it would send asks
   for a line-1 rewrite, not for the work to be driven.
