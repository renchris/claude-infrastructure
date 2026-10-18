# Axis 06: transcript census of closes

Every number below is **measured**. Each one names the script that produced it: `/tmp/close-census/census.py` (the streaming extractor, run as `python3 -I`), `/tmp/close-census/analyze2.py` (classification and episodes), or an ad-hoc `python3 -I` query over `/tmp/close-census/analyzed.json`. Conviction percentages are my estimates.

## 1. Answer first

- A `Good to close: yes` close usually has an empty follow-on: 66% read `none` or have no follow-on clause.
- 34.0% of yes closes do carry a non-empty `follow-on:` (494/1452).
- Only 4.5% (65/1452) use explicit "undriven" vocabulary such as waves, not started, next step or remaining.
- The **disguised** form is as common as the explicit one. 118/1452 yes closes (8.1%) write `follow-on: none` and then go on to name work. 61 of those name a next step, a plan item, a wave or remaining items, for example `none. The next step is the renewer build (wave I2a in the plan)`.
- The template's follow-on slot, `<filed ids|none>`, has no value for "unfiled, drivable work". Agents therefore write `none` plus prose, or free prose, under a YES.
- Pushback after a close is mostly indirect. Literal objections ("why", "not done", "you said") are rare: 6.0% after a yes and 8.2% after a no. The common responses are re-asking for the verdict and asking for a re-summary.
  - After a final **yes** that was the last thing the operator saw, the operator's next message re-asks "good to close? / are we done?" in **26.6%** of cases (106/399). After a final **no**, the rate is 6.6% (21/316).
  - 22.1% of replies after a yes ask for an SCQA or concise re-summary.
- Yes closes that name unfiled work draw more drive-demands than clean ones. The demands are "proceed", "conviction %", "research now", "self-recycle", "drive us", "idle".
  - Named-work yes closes (`other-named-noid` + `undriven-*`): 11/66, 16.7%.
  - `none` / `filed-ids` closes: 20/283, 7.1%.
  - The incident's class, `undriven-named-noid`, drew 3/6. The sample is small.
- `❌ Good to close: no` closes outnumber yes closes 2341 to 1452. 54% of them are followed by at least one Stop-hook feedback before any human reply. Close loops are real: 165 episodes held 5 or more closes before a human message, 65 held 10 or more, and the maximum was 58 consecutive closes.

## 2. Corpus and method

- **Files.** `~/.claude*/projects/*/*.jsonl` with mtime under 30 days, excluding `subagents/`. The script found 7236 files and streamed 2,247,911 lines; 1 line over 5 MB was skipped (measured: census.py `stats`).
  - `~/.claude-next/projects` is a symlink to `~/.claude/projects` (measured: `ls -la`). The `.claude-next` paths below are therefore `~/.claude` sessions.
  - Duplicate closes (same message uuid or timestamp plus text) were dropped: 1568 duplicates. These come from transcripts copied between config dirs by limit-recover and the symlink.
- **Close detection.** These are line-anchored, so a mention quoted inside prose does not count:
  - `yes`: `^[\s>*_#-]*(✅)?\**Good to close:\**\s*yes`.
  - `no`: the same pattern with `no`.
  - `safe-cert`: `✅ SAFE TO CLOSE`. There were 0 assistant-text hits; the certificate is printed by `operator-readout.sh`, not written by the agent.
  - `check-lead`: text starting with `✅` with no verdict (32 hits).
- **Scope.** The analysis covers non-`/private/tmp` projects: 3825 closes. Another 1818 closes in `-private-tmp-*` probe and trial sessions (hookdec trials and similar) are excluded.
- **Follow-on clause.** This is the text after `follow-on:` up to the end of the line. Classes (analyze2.py `cls`):
  - `none`: starts with none/nothing, has no undriven keyword, and is under 60 characters.
  - `filed-ids`: has an id (12-hex backlog/decision id, a backticked dotted or hyphenated token, or a short sha) and no undriven keyword.
  - `undriven-named+id` / `undriven-named-noid`: contains an undriven keyword: waves, next step, haven't started, not yet, remaining, could, would, recommend, TODO, later, pending, should, worth, optional, follow-up.
  - `other-named-noid`: prose with no id and no keyword.
  - `absent`: no `follow-on:` clause at all.
- **Next real user message.** The first `type:user` message after the close that is not `isMeta`, not a tool_result, and does not start with `<`, `[Request interrupted`, `[limit-recover]`, `[Workflow harness`, `Caveat:`, or machine prefixes. The machine prefixes are `[operator-ruling`, `[crash recovery]`, `kitty was restarted`, `Another Claude session sent`, `OPUS\d+-UPGRADE`, `In-place upgrade:` and `N background agents were stopped`.
  - `(Checking in)` is kept because it is operator-typed (`hooks/validate-bash.sh:211`).
  - Stop-hook feedback seen before the reply is counted separately.
- **Episodes.** Closes are grouped by (file, next human message). Pushback rates are computed only where the close was the **last assistant text** before the reply. That leaves 399 yes episodes and 316 no episodes.
- **Reply classes.** These are regexes in analyze2.py `R`:
  - `continue`: continue, proceed, drive, do it, implement, exhaustive, self-recycle, recommendations, next wave, finish, enact.
  - `challenge`: why, not done, you said, didn't, should have, detrimental, wrong, worried, `where?`, `me?`, incomplete, stopped, idle.
  - `re-ask-close`: good to close, are we done, done here, `complete?`, 100%, what's left.
  - `re-explain`: SCQA, pyramid, concise, recap, explain, clarify.
  - `checking-in`.
  - `brief-broad`: the brief's own word list, including bare "no" and "still".

## 3. Results

### 3.1 Close-level counts (non-tmp; analyze2.py)

| | n | files | non-empty follow-on | undriven-named | `none` + named work | verdict on text line 0 | ≥1 Stop-hook feedback before reply |
|---|---|---|---|---|---|---|---|
| `✅ Good to close: yes` | 1452 | 600 | 494 (34.0%) | 65 (4.5%) | 118 (8.1%), 61 name next/plan/remaining | 334 (23.0%) | 363 (25.0%) |
| `❌ Good to close: no` | 2341 | 352 | 102 (4.4%) | 6 (0.3%) | n/a | 630 (26.9%) | 1265 (54.0%) |
| `✅` lead without verdict | 32 | 27 | 0 | 0 | n/a | n/a | 8 |

Notes:
- **Follow-on classes for yes closes.** `none` 732, `filed-ids` 282, `absent` 226, `other-named-noid` 147, `undriven-named+id` 42, `undriven-named-noid` 23.
- **Undriven words outside the clause.** 208/1452 yes closes (14.3%) carry undriven vocabulary somewhere in the body ("haven't started", "next step", "wave", "what I'd do"…).
- **The yes verdict often follows a ✅ rung line.**
  - 986/1452 yes closes have the verdict on text line 1, not line 0.
  - On those, line 0 is a rung line: 696 `✅ …` (for example "✅ Complete & landed"), 165 `👤`, 49 `🔧`, 34 `⛔`.
  - So in most yes closes the first glyph the operator reads is a ✅ "done" before any follow-on. The verdict-first share rose from 15/702 in September to 319/750 in October (measured: ad-hoc query, verdict_line_idx by month).

### 3.2 Pushback on the next human message (episode-level, close was the last assistant text)

Final close = **yes** (n=399):

| follow-on class | n | continue | challenge | re-ask-close | re-explain | brief-broad |
|---|---|---|---|---|---|---|
| absent | 50 | 14.0% | 4.0% | 18.0% | 26.0% | 12.0% |
| none | 204 | 9.8% | 6.4% | **32.4%** | 20.6% | 12.3% |
| filed-ids | 79 | 3.8% | 2.5% | 22.8% | 22.8% | 7.6% |
| undriven-named+id | 16 | 18.8% | 0% | 31.2% | 18.8% | 0% |
| undriven-named-noid | 6 | **66.7%** | 33.3% | 16.7% | 50.0% | 50.0% |
| other-named-noid | 44 | 13.6% | 11.4% | 15.9% | 20.5% | 15.9% |
| ALL yes | 399 | 10.8% | 6.0% | **26.6%** | 22.1% | 11.8% |

Final close = **no** (n=316): continue 14.9%, challenge 8.2%, re-ask-close **6.6%**, re-explain 17.7%, checking-in 8.5%, brief-broad 17.7%.

Drive-demand replies are those matching conviction, exhaustive research, research now, your recommendations, proceed with, self-recycle, explain-decisions, drive us/this, or idle (ad-hoc query):
- After a yes: 39/399 (9.8%). By class: none 16/204, filed-ids 4/79, absent 8/50, other-named-noid 7/44, undriven-named+id 1/16, undriven-named-noid 3/6.
- After a no: 52/316 (16.5%).

How to read these numbers:
- **Re-asks after a yes.** The operator re-asks the close question after a yes 4x as often as after a no. Of those 106 re-asks, 75 are the exact text `Good to close?`, and the median gap is 850 s (ad-hoc query).
  - So this is mostly a return-to-pane re-check, not an instant reaction. Either the YES is not trusted or legible, or it is a habit.
  - Conviction that it measures a legibility or trust gap: 55%.
- **Named-work closes draw drive-demands.** Clauses that name work without an id draw drive-demands at about 2x to 7x the rate of clean closes. The n is small (6 to 66), so conviction is 65%.

### 3.3 Re-close loops

- There are 1583 episodes. 165 have 5 or more closes before a human message, 65 have 10 or more, and the maximum is 58 (analyze2.py episodes).
- The top five are all ❌ chains. Example: `~/.claude-quaternary/projects/-Users-chrisren-Development-agent-context-sync/b351c528-577d-4dbd-9b4e-f64e80d675e9.jsonl`, 58 `no` closes ending at L2434, then the operator wrote `(Done, continue)`.
- These are Stop-hook re-fire and re-close cycles while waiting. They are out of this axis's core question, but they put a ceiling on how much more Stop-hook nagging can help.

## 4. Ten quoted examples (path, line, snippet, next human reply)

1. **The incident.** `~/.claude-secondary/projects/-Users-chrisren-Development--worktrees-wt-cc-004752-67086/5759497b-3947-4fd7-9d8b-e095bf134dbf.jsonl` L643. Close: "✅ Good to close: yes. Nothing of mine is open. Follow-on: the implementation waves in README §5 haven't started, because this pass was research only." Reply L654: "This whole behavior worries me. Please conduct a dedicated research handoff session for our behavior to continue exhaustively…"
2. **"None I can drive", answered with a demand for research.** `~/.claude-quaternary/projects/-Users-chrisren-Development--worktrees-wt-pool-3/240fe753-e322-49b8-90c7-4ab427dc376f.jsonl` L3481. Follow-on: "none I can drive. The five remaining items each wait on something outside this session:". Reply L3495: "…explain each decision, your recommendation, and your conviction %. If exhaustive research moves your conviction one way or another, do so now."
3. **"None filed", then the operator finds the session idle.** `~/.claude/projects/-Users-chrisren-Development--worktrees-mv-p2-meeting-page/cc7f64a7-27a7-4772-b3d7-9f4109e4a9b6.jsonl` L955. Follow-on: "none filed (the plan section lists the items for P1, P3 and the field check)." Reply L960: "Investigate why … you said "Next, I'll close this session's pane, since nothing is left open" but we are still here open and idle."
4. **Design calls named but not driven.** `~/.claude/projects/-Users-chrisren-Development--worktrees-lr-detect-w4/2f6e7e93-209e-46fc-80e8-14b95ceefc03.jsonl` L2234. Follow-on: "two items named below, neither driveable without an owner's design call." Reply L2252: "For each itemized decision/step, what is your recommendation and conviction percentage? If exhaustive research moves your conviction one way or another, exhaustively research now."
5. **Owner unclear.** `~/.claude-quaternary/projects/-Users-chrisren-Development--worktrees-wt-cc-000146-45877/f7351f3b-b0cc-4f8f-9110-42a891cd9ab0.jsonl` L1353. Follow-on: "one pane is left to move once its window is out of fullscreen; the heartbeat fix (kitty window 37) is still working." Reply L1363: "\"Still yours: - Kitty window 8 is waiting for your permission…\" Where? Drive us."
6. **An unstarted build hidden behind "none filed".** `~/.claude-secondary/projects/-Users-chrisren-Development-agent-context-sync/99b5cd2f-9d0f-4ceb-85db-a194bd4743c1.jsonl` L225. Follow-on: "none filed (the build is not started and needs the four rulings listed at the end)."
7. **Open program work hidden behind "none filed".** `~/.claude-secondary/projects/-Users-chrisren-Development-claude-infrastructure/893204d3-a298-48d9-8df1-081be573d441.jsonl` L1078. Follow-on: "none filed. The program's next stage (acceptance, freeze, certification) and its 13 open build-list rows live in the program records, not in this pane." Reply L1084: "So short and concise SCQA where are with the TrueMemory 2.0 research, the TrueMemory 2.0 plan, and th TrueMemory 2.0 implementation".
8. **The next wave named, with no fire.** `~/.claude-tertiary/projects/-Users-chrisren-Development--worktrees-wt-cc-143333-63422/7f533f05-91fa-42d0-89ef-cd7976c423d5.jsonl` L1159. "Good to close: yes — nothing of mine is open; follow-on: Wave 1 of that plan (W0 · W1 · W5) is the next fire, for a fresh lead session in `wt-lr-detect-100p` — not this one…" Reply L1166: "Are we 100.00/100.00 correct and complete … deployed and live now?"
9. **"None" plus a named next step.** `~/.claude-quaternary/projects/-Users-chrisren-Development-sevenrooms-bridge/4bd14fd9-721b-4941-9d8b-35a3c429f801.jsonl` L803. "Good to close: yes — nothing of mine is open; follow-on: none. The next step is the renewer build (wave I2a in the plan); its first step repeats your two requests from AWS."
10. **A held item, then the operator asks whether the session is idle.** `~/.claude-quaternary/projects/-Users-chrisren-Development--worktrees-wt-pool-3/240fe753-e322-49b8-90c7-4ab427dc376f.jsonl` L2814. Follow-on: "the Playwright 1.63 upgrade, still held for the Floor-tab fix I described earlier." Reply L2822: "Are you working or are you idling; is there any manual steps from us that you're blocked and waiting on?"
11. **A clean yes, re-asked anyway.** `~/.claude/projects/-Users-chrisren-Development-claude-infrastructure/6e8a1fd6-dee6-4a4e-822d-32339b1476f5.jsonl` L521. "Good to close: yes — nothing of mine is open; follow-on: none." Reply L534: "Good to close?"
12. **A ❌ no for comparison: the operator grants the drive.** `~/.claude/projects/-Users-chrisren-Development--worktrees-wt-pool-3/3d42fa49-ba13-4ab9-bf11-34501082324d.jsonl` L1478. "Good to close: no — the re-verify that unblocks `/deploy` is running in this pane, and closing it kills that." Reply L1485: "You have my good to go to /deploy … want you to continue to drive this without me".

## 5. Root causes this census supports

1. **The follow-on slot has no value for unfiled drivable work (80%).**
   - Template: `hooks/lib/close-shape.sh:179` `follow-on: <filed ids, each expanded in plain English|none>`.
   - Rule: `CLAUDE.rules.slim.10-session-close.md:22` gives the same two values.
   - What agents do instead, measured:
     - 118 yes closes write `none` + prose, 61 of which name next/plan/remaining work.
     - 147 write prose with no id.
     - 65 use explicit undriven words.
   - In total, 234/1452 (16.1%) yes closes carry more than 15 characters of follow-on prose with no 12-hex id.
2. **The rules route qualifications into the YES's trailing clause, and D6 checks shape, not content (75%).**
   - `CLAUDE.rules.slim.10-session-close.md:146`: "A qualification goes in S2's `follow-on:` clause, beside the assertion".
   - Line 22: "naming what remains is no hedge".
   - Line 156: "omit S6 and let S2's `follow-on:` clause cover it".
   - The census shows yes closes with named work drew more drive-demands than clean ones (16.7% vs 7.1%), and the incident class drew 3/6.
3. **A ✅ reads as done before the follow-on is reached (60%).**
   - 986/1452 yes closes put the verdict on line 1, after a ✅/👤 rung line; 696 of them open with `✅`.
   - The yes line itself also carries ✅ (`close-shape.sh:179` "led by the verdict's own glyph — ✅ on a yes").
   - The operator re-asks the close question after 26.6% of yes closes, against 6.6% after no closes.
4. **Stop hooks are not where the operator's signal goes (70%).**
   - 25% of yes closes and 54% of no closes already had at least one Stop-hook feedback before the human replied.
   - Re-close loops reach 58 closes. More Stop-hook arms on close text would add to an already noisy channel unless they fire only on a narrow content condition.

## 6. Fix candidates

1. **Make "named but unfiled, unowned work" a no (completion-assert D6 content arm).**
   - Change the template slot to `follow-on: none | <ids, each expanded>`, and make D6 (`hooks/completion-assert.sh`, `hooks/lib/close-shape.sh`) fail a `✅ Good to close: yes` when the clause is not `none` or ids. That covers `none.` plus more prose, and prose with no 12-hex id and no named owner session or pane.
   - The block reason tells the agent to drive it, file it (`cc-backlog add` / `cc-decide open --class C`), or answer `❌ Good to close: no — <item + owner>`.
   - It stays silent on `none`, on id-only clauses, on a park marker (`parked`, `until YYYY-MM-DD`, `held on purpose`) and on an owner hand-off.
   - Estimated firing rate: 161/1452 yes closes (11.1%), from the ad-hoc query `prose>15 chars, no 12-hex id, no owner/park marker`. Every hit is a close the agent can fix in one turn.
   - Conviction 75%.
2. **Rule text: swap the "qualification goes in follow-on" sentence for its inverse, at net-zero size.**
   - Replace `CLAUDE.rules.slim.10-session-close.md:146`'s last sentence with: "Work you can drive is never a qualification: drive it, file it, or answer no." It is about the same length.
   - Cut the matching clause at line 156 ("when nothing is, omit S6 and let S2's `follow-on:` clause cover it" → "when nothing is, omit S6").
   - Conviction 65%.
3. **Stop stacking ✅ on top of a yes that carries follow-on.**
   - When the clause is non-`none` (ids filed), use a neutral glyph or none on the verdict line (`Good to close: yes — …; follow-on: <ids>`), and keep ✅ only for `follow-on: none`.
   - Change in `hooks/lib/close-shape.sh:179` and the D6 `line-1-rung` check.
   - It never fires as an alarm; it only changes rendering.
   - Conviction 50%. It is aimed at the 26.6% re-ask rate, but the census cannot prove that link.

## 7. Limits

- Classes are regex heuristics.
  - `should` and `would` inside a decision's quoted question inflate `undriven-named+id`. For example, the `05490056dd9f` "should desk routing rank…" decision is filed, not undriven.
  - `none` versus `none` + prose depends on a 30- or 60-character threshold.
- The "next human message" can be an operator macro. `short and concise SCQA the outcome…` recurs in 51 files, so re-explain counts partly reflect habit.
- Pushback n for the incident class is 6. Treat its 66.7% as anecdote, not a rate.
- No transcript or repo file was modified. The scripts and outputs are in `/tmp/close-census/`: `census.py`, `analyze2.py`, `out.json`, `analyzed.json` and `undriven_yes.txt`.
