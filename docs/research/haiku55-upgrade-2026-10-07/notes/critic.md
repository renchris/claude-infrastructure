# Completeness critic: Haiku 5.5 / Claude Code 2.1.293 run (2026-10-07)

Read-only pass over `notes/` (22 files), `pack/`, `gate/`, `UPGRADE.md`, and the seven rule files in
`skills/cc-upgrade/`. Nothing was edited except this file. How each number was obtained is labeled
*measured* (command named) or *derived* (reasoning named). Small read-only checks were run to make
each gap exact: `jq` over the fact and gate JSON, `grep`/`sed` over `pack/`, a Python `mmap.find`
over both binaries (JS region, byte offset above 150,000,000), and `gh issue view` on eight issue
numbers. No model was run.

## 1. Covered

**Fact base (measured: `jq` counts over the eight facts/verify pairs).** 912 reader facts
(745 card, 167 vendor pages); 894 confirmed, 18 corrected, 0 refuted; 169 facts added by verifiers.

**Pages.** Every card page from 8 to 139 carries at least one fact with that page number, and pages
140-144 (the HLE blocklist appendix) are covered by range facts c130-88..91 (measured: `jq -r
'.[].page'` per file). No page in 8-144 is unread.

**Figures.** `pack/figs` holds 90 files. Every page that has a figure file also has chart-kind
facts (measured: figure page numbers against `select(.kind=="chart")`). A caption-versus-file
cross-check found no chart that exists only as vector art: the only caption pages without a file
are p058 (Transcript 6.1.3.A, text) and p133 (a text reference to the figure on p134). Three pairs
are byte-identical (measured: `md5 -r`): 073-036 = 073-038, 073-037 = 073-041, 094-058 = 094-059.

What is weak is traceability, not coverage. Only the p055-075 reader and three facts in p076-094
name figure files; 62 of 90 files are never cited by filename (measured: `grep -o 'fig-NNN-NNN'`
over `notes/`). The one reader who did name files mapped five of six wrong on p73 (verifier
correction c55-115). The 62, with the count of chart-kind reader facts on that page in parentheses:

- Cover, outside 8-144: fig-001-000, fig-001-001 (2048 x 230 px wordmarks, measured with `sips`).
- p008-029: fig-013-002 (2), fig-015-003 (4), fig-016-004 (3), fig-017-005 (3), fig-018-006 (3),
  fig-020-007 (3), fig-025-008 (3), fig-027-009 (1), fig-028-010 (2), fig-029-011 (2).
- p030-054: fig-033-012 (11), fig-041-013 and fig-041-014 (2 for the page), fig-042-015 (1),
  fig-050-016 (3), fig-050-017 (blank white image, viewed; nothing to read).
- p076-094: fig-078-043 (1), fig-079-044 (2), fig-080-045 and fig-080-046 (4), fig-081-047 (1),
  fig-082-048 (5), fig-083-049 (2), fig-085-051 (3), fig-086-052 (2), fig-087-053 (3),
  fig-088-054 (3), fig-090-055 (4), fig-091-056 (1, a transcript image), fig-093-057 (4),
  fig-094-060 and fig-094-061 (6 for the page; c76-108 identifies them by number in its claim text).
- p095-110: fig-098-062 and fig-098-063 (6), fig-099-064 (4), fig-101-065 (5), fig-102-066 (4),
  fig-103-067 (4), fig-106-068 (5), fig-108-069 (4), fig-110-070 (5).
- p111-129: fig-113-071 (8), fig-114-072 (6), fig-119-073 (6), fig-120-074 (6), fig-121-075 (7),
  fig-123-076 (7), fig-124-077 (1), fig-125-078 (5), fig-126-079 (1), fig-127-080 (4),
  fig-128-081 (1), fig-129-082 (5).
- p130-144: fig-130-083 (7), fig-132-084 and fig-132-085 (5), fig-134-086 (11), fig-135-087 (1),
  fig-136-088 (1), fig-137-089 (7).

Pages with a single chart fact (27, 42, 78, 81, 91, 124, 126, 128, 135, 136) are data-labeled bar
charts or a transcript, so one fact can carry them. No re-read is owed for coverage.

**Decision questions the notes do answer.**

| Question | Answer in the notes | Where |
|---|---|---|
| Coding by effort | FrontierCode Main and Extended, all five rungs, for Haiku 5.5, Sonnet 5.5, Opus 5.5 and Fable 5.1. Haiku 5.5 at max (46.4% Main) is below Sonnet 5.5 at high (about 49.3%) and below every Opus 5.5 rung. No Haiku 4.5 result exists. Every other coding benchmark is max-only. | c111-21..39, v111-01..04 (p113-114) |
| Agentic search by effort | HLE with tools, DRACO and WANDR, all five rungs, three 5.5 models plus one Haiku 4.5 point each. WANDR is the steep one: 3.5% at low, 12.9% at medium, 37.3% at high. | c111-64..96 (p119-123) |
| Long context | One number per model on ProgramBench (Haiku 5.5 82.0%, Sonnet 5.5 79.7%, Opus 5.5 91.2%), effort not stated, no curve by context length. | c111-57..59 (p117) |
| Honesty about completion | Audit "False completion claims" 1.89, worst of the four 5.x models (Opus 5.5 1.48), far better than Haiku 4.5 (4.85). Silent use of a leaked answer 17.3% against 1.6% for Haiku 4.5. Vendor guide: at low and medium effort it sometimes reports a code change as done without running a check. | c55-70..78, v55-12 (p65-66); c76-44..46 (p83); d-77..82 |
| Prompt injection | Gray Swan IPI at k=15: 7.1% against 83.2% for Haiku 4.5; coding 0.2%, tool use 4.0%, GUI 24.4%. Shade coding 0.08% of attempts, 6 of 40 scenarios. Audit "Complying with prompt injections" 1.56 against 4.08. | c30-70..99, v30-01..05 (p47-53); c55-53 (p62) |
| API breaking changes | Five: manual thinking budget, non-default sampling parameters, assistant prefill, the old computer-use tool, thinking blocks after edited history. Plus classifier refusals with no server-side fallback, and a tokenizer that counts about 30% more tokens. | d-105..132 |
| Haiku alias per binary (baked table) | 2.1.284: `haiku` is `claude-haiku-4-5` everywhere. 2.1.293: `claude-haiku-5-5` on first party, 4.5 on seven other providers. Agent tool enum cannot name a version. | bin293-probes sections 2 and 7 |
| Effort accepted or rejected | Client: 2.1.293 excludes `claude-haiku-4-5` from effort by name and sends none; `claude-haiku-5-5` carries `effort`, `xhigh_effort`, `max_effort`. CLI: gate check #4 accepted all five rungs for `claude-haiku-5-5` (measured, gate JSON). API: `claude-haiku-5-5` is in the effort page's supported list and `claude-haiku-4-5` is not. | bin293-probes section 3; gate-293-haiku55-3acct.json; dv-12 |

**Joins the notes did not make (each closes an item another note lists as open).**

- census-haiku section 7 lists the dated API id, price, cache-read multiplier, window, output cap
  and retirement floor as not determined. The vendor facts settle all six: there is no dated id
  (d-03, d-04), $0.10/$0.50 up to 100K prompt tokens and $0.50/$2.50 above (d-17, d-18), standard
  0.1x cache read so no `CR_MULT` entry (d-29), 1M window and 128K output (d-07, d-08), floor
  October 7, 2027 (d-136).
- cc293-axis2 asks which model small/fast background calls use. bin293-probes section 2 answers:
  the same resolver, so Haiku 5.5 on first party, except four helper calls pinned to Haiku 4.5.
- census D3/R7 and cc293-axis2 (line 70) ask whether Haiku 5.5 holds auto mode. Gate check #3
  passed under `claude-haiku-5-5` as the session model (measured, gate JSON), and the card ran it
  under auto mode in Cowork (c30-100..102). That covers Haiku 5.5 as a lead, not as a teammate; see
  contradiction C2.
- cc293-axis2 asks whether the `--cloud` flag still exists. The string is in the 2.1.293 argument table
  (7 hits against 5 in 2.1.284, measured: `mmap.find` for `"--cloud`). The send itself is unprobed.
- All eight adversary issue numbers spot-checked exist, are OPEN, and carry the quoted titles
  (measured: `gh issue view` for #99949, #99950, #99965, #99833, #100065, #100005, #100117, #100013).

## 2. Gaps (each answerable by a targeted re-read)

Ranked by how much the answer could change the decision.

**G1. Is there a client-side off switch for the per-agent token budget, and which spawn surfaces
carry it?** cc293-adversary R2 rates it BLOCKER and says no setting or environment variable disables
it. The code quoted in bin293-probes section 1 reads the environment variable before the server
flag and returns no budget for a non-positive value, and attaches the budget only to Agent-tool
launch and resume, not to Workflow `agent()` or in-process teammates. Nobody stated the consequence.
If it holds, the last standing blocker on the binary move becomes one staged `env` line.
Look at: `~/.claude-293/node_modules/@anthropic-ai/claude-code/bin/claude.exe`, functions `sQe`,
`SWt`, `dZn` near byte 194076564 and `Gpn` near 199939862; strings `CLAUDE_CODE_RIPPLING_TULIP`
(3 hits in 2.1.293, 0 in 2.1.284, measured), `CLAUDE_CODE_STREAMED_BUMBLEBEE`, `tengu_calm_mochi`;
the reminder-mode resolver `bWt` (what yields `off` or `padded-countdown`).

**G2. On 2.1.284, can the server-served model catalog already repoint `haiku`, and what does
2.1.284 send when handed the raw id `claude-haiku-5-5`?** census-haiku (lines 110-113) says the old
binary "can only resolve to Haiku 4.5". bin293-probes (lines 132-146) shows a served-catalog
override ahead of the baked table in both builds and lists both questions as not traced
(lines 386-387). If the alias can move server-side, holding the binary does not hold the model,
and the old client would call Haiku 5.5 with Haiku 4.5 request shapes. It also sizes the
split-fleet hazard in model.md Case A step 0b and the `shutil.which("claude")` call at
`scripts/research-kit/router.py:364`.
Look at: `~/.claude-284/.../claude.exe` near bytes 180087586 and 180079291 (the `ga("haiku")`
override and what it validates), and the unknown-model branches for effort and thinking near
180126499 (search `includes("haiku")`, `haiku45`).

**G3. What effort does a Haiku 5.5 subagent run at when nothing pins it?** Three statements
disagree. The vendor page says medium is the default "in Claude Code" (pack/effort.md:342).
bin293-probes section 3 says a subagent inherits the session effort, which on this fleet is the
launcher's explicit `--effort high` (gate check #5 evidence), or xhigh under `claude-x`. cc293-axis1
(line 85) calls the effort landmine no longer safe; cc293-axis3 (line 143) says it stands.
census-haiku (lines 274-277) cites `model-config.yaml:267-269` that top-level `effortLevel` is
ignored for 5.5-generation ids, while bin293-probes says it is the fallback under `inherit`. The
binary reading is marked "inferred from minified code". The role by effort table cannot be written
until this is one statement.
Look at: 2.1.293 binary near byte 187910400 (`Vw(`, `lc(`, `settingsEffortTable`), near 199939862
(`subagentEffort:ly(r,i,e.effort??Mh(s))`), near 199975991 (Agent `effort` schema);
`model-config.yaml:267-270` and `:439-441`; `~/.zshrc:74-90` and `:196`. Fleet fact checked here:
`CLAUDE_CODE_EFFORT_LEVEL` is unset by policy (`~/.zshrc:90`), so the new Agent `effort` parameter
stays in the schema (measured: `grep`).

**G4. The announcement's accuracy-versus-cost charts were never read.** The pack holds only the
text layer; the four charts are `[]` placeholders at `pack/announcement.txt:74-110` and `:217-224`
(verifier correction d-153). Two have no counterpart in the card: Terminal-Bench 4.0 (the card gives
max effort only, 39.2% against Sonnet 5.5 70.6%, p115) and GDPval-AA v2.1 (the card gives max and
medium only, p131). Terminal-Bench 4.0 runs in Claude Code `--bare`, so it is the closest vendor
evidence for a code-writing teammate below max effort.
Look at: https://www.anthropic.com/claude-haiku-5-5, the image or data assets behind the four
"Accuracy vs. cost" charts.

**G5. What does 2.1.293 change in the prompt and the request for `claude-haiku-5-5` beyond the
id?** bin293-probes lists eleven capability flags and read one (`haiku_5_5_early_stopping_guidance`).
Unread: `lean_prompt` (by its name, a different system prompt for Haiku 5.5 agents; not confirmed),
`mid_conv_tool_change`, and what `rejects_disabled_thinking` does to side queries. The vendor says
thinking can be disabled at high effort or below (pack/effort.md:344) while the client marks it as
never disabled. The quoted helper `Aye` suggests (inferred, not traced) that small/fast helper calls
then run with thinking on, and those calls move to Haiku 5.5 fleet-wide at the binary flip whatever
roles are chosen. The vendor's fixes for early stopping and unverified "done" (pack/prompting.md
lines 77-96) may or may not already be injected by the binary.
Look at: 2.1.293 binary, strings `"lean_prompt"`, `whenToUseLean` (near 192341917), `CLo` (near
194093455), callers of `Yw(` and `Aye(` (near 186794300-186795544).

**G6. Does 2.1.293's native read-before-write guard cover `claude-haiku-5-5`?** Asked by
cc293-axis2 (line 14) and census-haiku D1, answered by nobody. It is the holds.md landmine "Write
may overwrite an unread file", and it gates any code-writing role.
Look at: 2.1.293 binary near byte 185332785 ("File has not been read yet. Read it first before
writing", measured offset) and the model predicate around it;
`hooks/lib/read-before-write-parity.sh:165-186`; `tests/read-before-write-parity.bats:147,177-185`.

**G7. Background Bash deadline for a one-shot `claude -p`: 10 minutes or 30?** See contradiction C4.
Also unread: which session kinds count as not interactive (`--bg`, daemon, a Workflow agent inside
an interactive pane) and whether `BASH_DEFAULT_TIMEOUT_MS` is a usable lever.
Look at: 2.1.293 binary, `uoe=600000` (1 hit; 0 in 2.1.284, measured), `OVt(`, `JJ()`,
`singleShotPrintSession`, `uz(` near bytes 191288733 and 184518574, `disableBackgroundDeadline`
near 227269654; `pack/cc-changelog.md` lines 763, 461, 81; callers
`scripts/handoff-fire.sh:13853`, `scripts/meter-experiment/run.sh:65,72`.

**G8. How does 2.1.293 deliver hook output and harness reminders to Haiku 5.5?** The prompting
guide says Haiku 5.5 is trained to treat text arriving inside a `tool_result`, or as a system
message right after one, as untrusted and may ignore it (pack/prompting.md:98-104). The fleet
steers subagents through exactly that channel (hook `additionalContext`, mailbox drain, reminders).
No note connects the two; cc293-axis3 rates the one related changelog line (126) NEUTRAL.
Look at: `pack/prompting.md:98-104`; 2.1.293 binary, strings `additionalContext`,
`system-reminder`, `mid_conv`; `pack/cc-changelog.md` line 126.

Smaller, one command or one page each:

- **G9.** No note quotes the latest MANIFEST `REVISIT` row, which holds.md calls the source of truth
  over its own index. Look at `~/.claude-versions/MANIFEST.jsonl` with the reader in holds.md section 1.
- **G10.** No note records the npm publish time of 2.1.293 (audit.md Step 4 wants age since
  publish). The notes say "hours old" and "one day old"; the binary's build time is
  2026-10-07T06:36:42Z. Run `npm view @anthropic-ai/claude-code time --json`.
- **G11.** Plan inclusion is NOT STATED anywhere in the pack (d-164, d-165). Two pages were not
  fetched: the Help Center article linked at `pack/announcement.txt:230` and the Claude Code model
  configuration page. Record NOT STATED per gate.md if they are silent.
- **G12.** holds.md asks for a per-server MCP comparison with the 2.1.284 run. Gate check #13
  lists the seven connected servers in `.checks[12].detail`; no 2.1.284 artifact is in this run
  directory to compare against.
- **G13.** The SSOT pricing row is a two-element `[input, output]` pair (model.md forbids changing
  the arity), and Haiku 5.5 has two price sets split at 100K prompt tokens (`pack/pricing.md:34-35`).
  census-haiku P1 says "add a row" without saying which set; the lower one underprices long prompts
  by 5x.

## 3. Contradictions

**C1. Gate verdict.** cc293-adversary R1 (written 17:16) rates the binary move BLOCKER on a RED
gate: account `next3` failed check #2 for `claude-haiku-5-5`. `UPGRADE.md` (17:28) records that
`next3` is logged out, failed the same check under Opus 5.5, and that both models read GREEN on the
three logged-in accounts (measured: 14 pass, 0 fail, 1 skip in each `-3acct` JSON). R1 is
superseded. What survives: `next3`'s entitlement to Haiku 5.5 is unproven.

**C2. What checks #7 to #9 prove.** cc293-adversary (line 76) says the gate "shows no demotion in a
subagent, teammate, or workflow run". The probes do not test Haiku as a worker.
`lib/cc-upgrade-gate/check07_teams.sh:17` asks a Haiku 5.5 lead to spawn a teammate with
`model opus`; its `modelUsage` shows `claude-haiku-5-5` plus `claude-opus-5-5` (measured, gate
JSON). Checks #8 and #9 spawn unpinned agents that inherit the lead. The Opus 5.5 run shows only
`claude-opus-5-5` in all three. So no probe ran an Opus lead spawning `model: "haiku"`, the only
way this fleet uses Haiku, and none ran a Haiku 5.5 teammate. census-haiku D3 adds that
`hooks/agent-teams-enforce.sh:66-83` denies a Haiku teammate today because no Haiku id is on
`auto_mode_allowlist.non_firstParty_max`.

**C3. Per-agent token budget.** cc293-adversary R2: BLOCKER, unconfigurable, subagents stop and are
respawned for hours. bin293-probes section 1: advisory only, nothing stops or truncates, an
environment variable is read first, Workflow agents and teammates do not receive it. cc293-axis2
(lines 87-90) says no candidate binary was on disk and warns a silent budget "would truncate" long
runs; the binary was at `~/.claude-293` and three other notes read it. The upstream reports are
consistent with a model that winds down when shown a countdown, not with client enforcement. Hit
counts differ by method only: 2 (`grep -c`, lines), 3 (`mmap.find`), and 6 on 2.1.291 in holds.md.

**C4. Background Bash cap.** Changelog line 763 and four notes say the default is 30 minutes for
`-p`. bin293-probes section 6 reads 10 minutes for a single-shot print session and 30 minutes for
other headless sessions; `uoe=600000` is in 2.1.293 and absent from 2.1.284 (measured). cc293-axis2
says a 3300-second `cc-await-ping` arm in `-p` is cut at 1800 seconds; by the binary it is 600.
cc293-adversary R4 says there is no supported way out; bin293-probes shows the per-call `timeout`
(up to 2 hours) and `BASH_DEFAULT_TIMEOUT_MS`.

**C5. Haiku alias.** cc293-axis1, cc293-axis2 and the adversary say the alias moves "the moment the
binary flips"; census-haiku says 2.1.284 can only resolve it to 4.5. bin293-probes shows a
server-served override in both builds that nobody traced. See G2.

**C6. Effort.** See G3. Two axes rate the same holds.md landmine in opposite directions, and two
notes describe the settings fallback differently.

**C7. Thinking.** bin293-probes says Haiku 5.5 thinking "cannot be turned off"; the vendor says
`disabled` is accepted at high effort or below (d-42). Both are true at different layers. The
consequence is that the cheapest API configuration (thinking off, low effort) cannot be expressed
through Claude Code, so a high-volume extraction or classification slot priced from API numbers
will read low.

**C8. Urgency.** census-haiku E1 treats October 15, 2026 as the date probes start failing. The
deprecations page lists Haiku 4.5 as Active with no deprecation entry, and promises at least 60
days' notice before retirement (`pack/model-deprecations.md:36`, `:91`; dv-01). Derived: with no
notice issued by October 7, retirement cannot fall inside the next 60 days.

**C9. Comparator names.** The card calls the frontier comparator "Mythos 5.1" in the alignment
sections and "Fable 5.1" elsewhere (c55-127, v30-09, c76-51). The vendor pages list
`claude-fable-5-1` and `claude-mythos-5-1` as separate ids (dv-04, d-29, d-44). Card numbers
labeled Mythos 5.1 are not shown to describe the fleet's Fable 5.1 tier.

**C10. Adversary scope.** The adversary read changelog lines 3-160 (2.1.291 to 2.1.293); the three
axes read 3-815. Its list of "features that remove a limit" has no rows for 2.1.285 to 2.1.290.

**Verifier corrections that move a headline.**

- c55-36: the audit's effort level is not stated; the reader's "not tied to one effort level" was
  an inference. Every audit honesty number therefore has an unknown rung, and the card's own
  reviewer says alignment results differ by effort (c55-27, c55-31).
- d-153: three by-effort charts in the announcement, not four; the Terminal-Bench 4.0 chart is a
  separate price illustration. None is in the pack (G4).
- c111-96: on WANDR, Sonnet 5.5 passes Haiku 5.5 at about $1.5 per task and Opus 5.5 not until
  about $3, not both at $2.
- c111-47: the widest Haiku-to-Sonnet coding gap is Terminal-Bench-Science (39.3 points), not
  Terminal-Bench 4.0 (31.4).
- c111-29: Opus 5.5 is not the top FrontierCode series at every rung.
- c55-43: Haiku 5.5 is third-worst of five on overall misaligned behavior, not second-worst.
- c130-10: "OfficeQA does not test retrieval" was the reader's inference, not the card's statement.

**Audit claims rated BLOCKER or CAUTION without a changelog line or issue number.** R1 (local gate
only; now superseded, C1). cc293-axis1's Haiku 5.5 registry row and spawn-ceiling row rest on binary
strings and on changelog silence, which is the holds.md rule. cc293-axis3's top caution on line 443
(a `*` or empty matcher "counted as matching failed" would block every tool call) is a hypothesis;
gate checks #3 and #11 ran tool turns on 2.1.293 against the real account config directories
(`lib/cc-upgrade-gate/common.sh:42-52` sets only `CLAUDE_CONFIG_DIR`), which argues against it but
was not cited. Every other rated row carries a line or an issue number.

## 4. holds.md items still owed

| Item | State after this run |
|---|---|
| Held-open issues (#84974, #85264, #85015, #84224, #85154, inbox cluster, #97888, #97763, #97687, #99353, #99130, #99932) | All answered with `gh` states by axis 1, axis 3 or the adversary. One fixed; none newly discharged. |
| Per-agent token budget "must be probed" | Code read done; off switch and scope not stated (G1); live effect unprobed. |
| Background Bash cap | Text and binary disagree (C4, G7). |
| Restyled permission prompts | `tests/pane-modal.bats` 25 of 25 on the 2.1.293 track (cc293-axis3); live stacked capture not done. |
| Per-server MCP comparison | Not done (G12). |
| Write may overwrite an unread file | Hook not verified on 2.1.293; native set for Haiku 5.5 unread (G6). |
| Symlink-following cleanup | No line found; canary not run. |
| `-p` with `--mcp-config` first turn | Reopened by changelog line 123; probe not run. |
| AskUserQuestion idle timeout | Still unset in every launcher (cc293-axis3). |
| Re-pricing fan-outs when the retrieval model moves (audit.md) | No note re-prices the retrieval fan-out for the new tokenizer, the 100K price step, thinking on, and inherited effort. |
| Latest MANIFEST `REVISIT` row; publish age | Not in any note (G9, G10). |

## 5. Needs a live run

None of these can be settled by reading.

1. An Opus 5.5 lead on 2.1.293 spawning `Agent({model: "haiku"})`: the model id and the effort in
   the subagent's own transcript, at lead effort high and xhigh, with and without the Agent `effort`
   parameter and agent frontmatter `effort:`. This is the fleet's real shape and no gate probe ran it.
2. `--model haiku` on 2.1.284 today and on 2.1.293, per account, reading `modelUsage` (alias target,
   and the silent same-tier fallback from changelog line 596).
3. Log in `next3` and re-run gate check #2 for `claude-haiku-5-5`.
4. Per account and lead model: does the Agent tool description carry "has a budget of", does a
   subagent see a countdown, and does a worker that needs more than N tokens finish.
5. Quota draw per token for Haiku 5.5 against Haiku 4.5 on one Max account, including prompts
   over 100K tokens and thinking at each rung.
6. An effort sweep per candidate role on the frozen corpus with equal tools: retrieval (file:line
   accuracy) at low, medium and high against Haiku 4.5 and Sonnet 5.5; mechanical code edits;
   extraction and classification; verifier and judge agreement.
7. Long context: retrieval accuracy at about 100K, 300K and 1M tokens by rung. The card has one
   ProgramBench number with no rung.
8. Honesty in this harness: how often a low or medium Haiku 5.5 worker reports done without a check
   or stops early under the fleet's long system prompt, with and without the vendor's verification
   paragraph.
9. Prompt injection at low and medium effort: a planted instruction in a file and in a fetched
   page read by a retrieval subagent (the card's injection tests state no rung), and whether
   hook-injected guidance is still obeyed.
10. A Haiku 5.5 subagent inheriting xhigh: check for the empty final reply the guide warns about.
11. One-shot `-p` with a background command: when it is stopped, with and without an explicit
    `timeout`; the same in a `--bg` session.
12. A Haiku teammate through the fleet's own `agent-teams-enforce.sh`, and auto mode holding for it.
13. The owed 2.1.293 behavior probes from cc293-axis3: `*` and empty hook matchers, rewriting and
    allowing hooks under auto, `backup-before-write.sh` on an unread file, two stacked permission
    prompts in a live pane, a revoked-token turn, per-server MCP parity, the symlink cleanup canary,
    and an edit of the settings symlink target.
14. `-p --resume` prompt-cache cost on 2.1.284 against 2.1.293; resume of a 2.1.284-born session
    through `lr-upgrade.sh`; the `cc-notify --cloud` send.
