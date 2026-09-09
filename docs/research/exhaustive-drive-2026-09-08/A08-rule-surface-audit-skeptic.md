# A08 skeptic — re-run of the rule-surface audit's numbers and mechanisms

Read-only. Wave exhaustive-drive 2026-09-08. Every number below was re-run by this skeptic unless
marked *lead-measured* or *axis-claimed*. `timeout` does not exist in this shell; every long command
used `/opt/homebrew/bin/gtimeout`.

## Anchors — do the cited file:lines exist?

| Citation | Result |
|---|---|
| CLAUDE.md:532 E0 row · :577 `📦-in-reso` · :470 `names NO repo` · :854 `Judgment items are counted, not itemized` · :813 `the one decision you need` · :898 kill-switch · :358-359 verification ban · :228 `Default N=12` · :907 `NEVER script your own authorization` | **all hold** (`sed -n Np CLAUDE.md`) |
| CLAUDE.md:174 `PARALLELIZE BY DEFAULT` | **wrong line** — it is :138 |
| CLAUDE.md:236 research depth 150-250K | **wrong line** — it is :242 |
| completion-assert.sh:161 `CA_KILL_RE` · :180-182 "all 9 are fire/recycle briefs … SHOULD disarm" · :186 last non-meta reader | hold |
| session-continue.sh:1019-1023 `session_writes_paths` gate | holds — but it is the SHIP floor only (`:1010-1023`); the mechanical arm gates on `mechanical-dirty` (:944) and the wake floor on pending mail |
| operator-readout.sh:1416-1418 cites E0 | holds (:1416 "(E0)") |
| worktree CLAUDE.md vs ~/.claude/CLAUDE.md | byte-identical, 918 lines / 84,249 B; live copy is a regular file |

## Kill-switch census — re-run (population: all `*.jsonl` under the four project roots, mtime ≥ 2026-09-01, realpath-deduped; non-meta user records with non-empty text)

Script: scratchpad `a08/killscan.sh` (jq per file, regex = `CA_KILL_RE` verbatim, applied to the `@json` form of the full text).

| | axis-claimed | skeptic re-run |
|---|---|---|
| transcripts | 1,489 | **1,599** (population grew during the wave) |
| non-meta user messages | 3,182 | **3,347** |
| regex matches | 29 | **38** |
| `isSidechain == true` | 15 | **27** — and **all 27 live in `…/subagents/agent-*.jsonl` files** |
| `isSidechain != true` (main transcript) | 14 | **11** |
| genuine operator stop orders | 3 (`Count to N and stop.`) | **3** — identical strings |

The 11 main-file matches, hand-read (sample = population): 3 `Count to N and stop.` probes · 2 `<task-notification>` · 4 `<teammate-message>` · 2 fire/recycle briefs (`You are the SUCCESSOR of session 53f08288`, `Continue HOOK_SURFACE_100P`). Machine-authored share among records the hook CAN read: **8/11**, not 26/29 — the 27 subagent-brief matches are in files `completion-assert.sh` never opens (`$TP` is the main transcript; the hook filters `isMeta`, not `isSidechain`, and does not need to).

**Live impact, measured on the IDL** (`jq -rc 'select(.hook) | select((.reason//"")|test("kill"))'` over `~/.claude/autonomy/idl.jsonl`, 54,256 lines, span 08:22Z → 23:29Z): `completion-assert kill-switch` **1** abstain out of **530** evaluations; `session-continue ship-floor-kill-switch` **1** out of 826. `abstain "kill-switch"` sits at completion-assert.sh:205, BEFORE `no-assistant-text` (:225) and the close-tell arms, so it is evaluated on every Stop that reaches the hook. So the "one `and stop` disarms the close gate for the session's whole life" mechanism is real but fired on **0.19% of live Stops today**. The census of messages is not the census of disarmed Stops.

Also: `agents/deep-research-sonnet.md:30` contains "and stop." — an agent definition, which lands in a subagent's system prompt, not a user record; irrelevant to the hook but it is the one house template carrying a kill phrase (`grep -rn` over commands/handoff.md, scripts/handoff-fire.sh, agents/*.md, agent-teams + research-subagents SKILL.md → this single hit).

## IDL blind shares — re-run (single store: the five `~/.claude*/autonomy/idl.jsonl` are one file, identical size/mtime)

`jq -r 'select(.hook)|.hook' | sort | uniq -c` and `[.hook,.reason]`:

| hook | evals | dominant abstain | share | axis-claimed |
|---|---|---|---|---|
| anti-deference-nudge | 554 | no-tell 533 | **96.2%** | 96.3% |
| completion-assert | 530 | no-close-tell 376 | **70.9%** | 71.4% |
| operator-readout | 411 | continue-armed 216 | **52.6%** | 60.7% (drifted as the day's mix changed) |

Holds. anti-deference fired: opaque-identifier 13 · false-done 2 · deference 2 · category-not-idea 2.

## Mechanism checks per recommendation

- **E1.** `anti-deference-nudge.sh` sources only `lib/idl-log.sh` and `lib/agent-identity.sh` — no `session-writes` gate — so it DOES run on read-only turns and its `CATEGORY_TELLS` (:170, "N items … are yours / need your call") and `TELLS` (:154) see exactly the shape E1 describes when it carries a tell. "No arm on the box can see the case" is overstated: no arm sees an E0 close that names work WITHOUT a lexical tell. The "~300 closes/30 d are this shape" link is inferred — `conviction-close-2026-09-08.md` contains no read-only/E0 stratification (`grep -in 'read-only|E0|no tracked writes'` → 0 relevant hits).
- **E3.** CLAUDE.md:679 and :745 (**S6 — WAITING. Named, never counted** … "each item NAMED in plain English") already mandate itemising what THIS session created; :854 sits inside the `cc-do` paragraph about RUNNABLE steps and the machine's standing pile. `wrap-ledger.sh:741-766` computes `BLOCKED` as a COUNT of open class-C packets (plural supported); `close-shape.sh` has no decision-count check (`grep -n '⛔|decision'` → comments only). The "direct contradiction" is largely a misread of :854's scope; the residue is :813's wording "the one decision you need". `CATEGORY_TELLS` fires on a counted header ("three decisions need your call"), so an E3 clause that itemises but keeps a count line would trip a live hook.
- **E4.** `grep -l -F 'verification you were not asked'` over the **610** main-transcript files in the population → **0** files. No agent quoted or cited :358 in 8 days; the C4 conflict is inferred, never observed.
- **E5.** Hooks registered: task-mutation-index (:585), setup-task-symlinks (:656), task-quality-gate under `TaskCompleted` (:1041) — hold. `CLAUDE_CODE_TASK_LIST_ID` exported by `~/.zshrc:173,175,498,501` via `bin/cc-tlid` — holds. Store in use: 44 task JSON files written since 09-01, 18 since 09-07, 991 list dirs. Backlog row `ebe84950e98a` (the tool-availability gate) went **`done` at 2026-09-08T22:14:32Z**, mid-wave, with no note — the premise "tools not offered" is still true for this session (no Task* tool in its list) but the row the axis cites as evidence is closed.
- **E6.** `git log -S'📦-in-reso' -- CLAUDE.md` → introduced `a321f15ab` 2026-08-01; `:470` rewrite `65b6290a7` 2026-08-05 missed it. Holds exactly as claimed.
- **E7.** `git log -S'N=10' -- CLAUDE.md` → empty (CLAUDE.md never said 10); `skills/research-subagents/SKILL.md` and `hooks/research-precognition-nudge.sh` have said `N=10 (band 8-12)` since `90e003f2f`/`a0f80ff8a` 2026-07-17. Two numbers have coexisted ~7 weeks. Which is right is unmeasured on both sides.
- **E8.** `grep -rn cc-permission-audit CLAUDE.md .claude/CLAUDE.md commands/*.md skills/*/SKILL.md` → 0 — holds. But `hooks/cc-permission-beacon.sh:109-141` records that the tool HAS been run and returned `approved 0 · unknown 3359` over 3,763 prompts — "an artifact of the instrument" (the PermissionRequest `tool_use_id` is always empty; memory rule *join-key-never-populated*), and the tool "can only ever report an UPPER bound … cannot see what auto mode's classifier silently approved". Backlog `78b76e1a8311` last event `venue` 2026-09-01, `7d5d083cb7b0` `block` 2026-08-18 — open, but "never run" is false.
- **Step 3 / Dynamic Workflows.** `grep -rli 'dynamic workflow' skills commands` → research-subagents SKILL.md:565 (model pinning), cc-upgrade-gate SKILL.md:71 (a probe), limit-recover, handoff — none an authorization; the axis's "only two authorizations" holds. The Workflow tool is not in this session's offered tool list (measured: absent from the deferred-tools listing).

## What the axis missed

1. Its kill-switch population was the wrong one for the hook it indicts: 27 of its matches are in subagent files the hook never reads. The right denominator — live Stops — gives 1/530.
2. It never measured how often the kill-switch actually disarmed anything; the IDL had the number in one `jq`.
3. It did not reconcile the lead-measured gap (901 closes vs 469 anti-deference evaluations) — the hooks' own timeouts (lead-measured completion-assert 4.14 s at 69 MB vs a 5 s budget) are a second blindness source the IDL cannot record, so "blind share" is a floor, not the number.
4. It read six rule surfaces but not the ones that are also injected into context: `~/.claude/rules/agent-operating-lessons.md`, `.claude/rules/*.md`, and the UserPromptSubmit nudges (`memory-nudge.sh`, `handoff-intent-nudge.sh`, `research-precognition-nudge.sh`) — the N=10/N=12 clash is the one it caught; it did not census the others for contradictions.
5. It classified S6 as prose-only and then proposed E3 as a NEW exception that S6 already states.
6. It did not check whether the Task tools' gating row was still open (closed 22:14Z) or whether the Workflow tool is offered at all before proposing rules that name them.
