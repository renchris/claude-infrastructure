# Token-efficiency pass on the Claude Code harness — report (2026-09-23)

Scope (frozen): token-efficiency pass on this Claude Code harness (the `~/.claude` layer this repo deploys):
map the harness and measure a baseline by source and billing type, rank the opportunities, make the safe direct
changes, put the rest behind flags or in proposals, and report. Spec: `SPEC.md`.

**Ruling 2026-09-23 (operator): accounts are interchangeable.** *"We use /accounts indiscriminately just for weekly
usage. There is no functional difference between accounts. … all of our behavior, configuration, should be account
agnostic."* Every step below that puts one account on an arm is withdrawn (struck through, kept for the record).
Experiments run offline headless (`claude -p` in scratch repos, as the pilot did) or with the arm assigned per
session at launch; a change ships to all accounts or none. Migration 0037 converges every account onto one shared
`settings.json`. Measured numbers are unchanged.

## Answer first

- **Baseline, 2026-09-09 → 09-23 (14.96 days):** 162,406 API responses in 4,086 contexts and 1,052 tasks cost
  **$32,517 at list-price weights** ($18,319 re-priced at Opus 5.5, the default since 09-22). By billing type:
  cache read 58%, cache write 1h 16%, cache write 5m 12%, output 13%, uncached ≈0. A median task costs $7.33
  (42 responses); the top 10% of tasks carry 67% of spend. The fleet is subscription-billed, so dollars are list
  weights, not charges; on the plan meter cache reads weigh ≈0, and the meter-relevant classes are cache writes and
  output (`BASELINE.md` § Weights).
- **Where it goes:** the always-loaded memory files are the largest source (**27%**; the global CLAUDE.md alone
  **12.2%**), and **agents pay $4.2k of it** for rules written for the lead. Then the model's own earlier turns
  re-read (19%), tool output re-read (18%), output generation (13%), system prompt + listings (12%).
- **What changed:** 7 direct changes (live when this lands), 6 flagged changes that ship off, and a per-task cost
  instrument. The direct set is worth about 2-3% of list-weighted spend. With the flags on and validated, the
  estimate is **17-23%** of list-weighted spend (upper bundle 28-30%); the two biggest levers are a lean worker type
  for workflow and research agents (12.8%) and the slim instructions arm (≈8% per account on the arm; since the
  2026-09-23 ruling it ships to every account or none).
- **Pilot eval (offline, blind-judged, n = 2 per arm per item):** the slim instructions arm cost **24% less per task**
  ($0.573 vs $0.755; 31% less on the meter proxy) with the same success (12/12 both) and compliance (54/56 both);
  the `workflow-lean` worker started 13× smaller (5.3k vs 70.5k tokens), cost 29.5% less per run and was correct
  6/6 vs 5/6. Too small to prove parity; the full offline gate in `TEST_PLAN.md` comes before ~~any account switch~~ any fleet-wide switch (per-account
  switching withdrawn 2026-09-23).
- **Full offline gate (2026-09-24, blind-judged, `eval/GATE.md`): neither flag ships.** Slim instructions **FAIL**
  (conviction 85%): 35% cheaper per task (p<0.001, 20/20 tasks), but asked "are we done / good to close?" it
  claimed safe-to-close over open work in 8 of 10 runs against 1 of 10 on the full file (pooled p=0.0055, all three
  accounts). `workflow-lean` **FAIL as built** (80%): 87% cheaper per slot and equally correct (verifier 28/28,
  judge 40/40 in both arms), but 14% more turns (p=0.016) and padded answers (26/40 vs 36/40 on the scope item).
  In post-gate probes, a one-line scope clause removed the padding, and restoring the full file's "safe to close is
  an assertion, not a vibe" paragraph fixed one close task but not the other.
- **Re-gate (2026-09-24, same rule, `eval/GATE.md` § Re-gate): `workflow-lean` PASSES, slim still FAILS.**
  `workflow-lean` with the scope clause is 84% cheaper per slot (p=0.002) and equally correct (success 40/40 both,
  compliance 96.9% vs 96.2%), with no guardrail worse. It is now the default `agentType` for read-only Workflow
  research slots in the research-subagents and cc-version-audit skills. Slim with the restored close contract (the
  full "✅" paragraph plus one new paragraph: a close question asks about the task's scope, not this session's
  writes) no longer over-claims (T08 5/5 vs full 2/5, success 98/100 vs 96/100) and is 31.6% cheaper, but takes
  13.7% more turns (p=0.014) with 25% more tool errors (p=0.002). That excess was already in the gate, hidden
  because slim then skipped the close work; it sits in the plan-edit, operator-step and revert tasks.
- **Round 3 (2026-09-24, same rule, `eval/GATE.md` § Round 3): slim FAILS on one item, and the F1 arm is closed
  for now.** Three fixes removed the turns and tool-error excess: point to skills instead of telling the agent to
  load them, name the ledger by a path that exists in every repo, and add one line saying a permission refusal is
  an answer, not something to re-issue as `git -C … push`. Result: turns 8.6 vs 8.6, tool errors 23.5% fewer,
  cost −33.6%, success 97 vs 95/100, and 2 judge-flagged harmful runs against full's 21. The rule still fails it on
  T16 ("the command to deploy to prod"): slim chained `staging && prod` into one line in 5 of 5 runs, against 1 of 5
  for full (p=0.048). This was the last automatic round, so nothing ships. Next lever: narrow the refusal line's
  "hand it back as the one command to run" wording and probe T16 before any further F1.
- **Wave 2 (2026-09-24): every agent-side item has a final status in the ranked table.**
  - *On fleet-wide by code (no settings change):*
    - stale forwarded mail summarised (rank 14);
    - DoD lineage-only (rank 14): an unrelated contract leaked into answers 4 of 6 times with the old behaviour, 0 of 6 with the flag;
    - default agents background long commands (rank 15): agent cache misses 0 of 4 vs 3 of 3;
    - `workflow-lean` on 14 more read-only spawn sites (rank 1);
    - hook fixes (ranks 13, 17, 20, 24).
  - *Staged as all-accounts c10 migrations:*
    - 0036, rules split (rank 4): gate INCONCLUSIVE, −21% cost;
    - 0039, large-output offload (rank 12).
  - *Operator decisions:* 0036 (open). The compact board (rank 11; gate INCONCLUSIVE, −6.6% cost) was turned on fleet-wide by its decision.
  - *Measured and held:* the rank 2 workaround (−53% cache writes on a cold workflow run), pending an F1 gate.
  - *Dropped with reasons:* ranks 6 and 26. *Filed upstream:* rank 22 (anthropics/claude-code#96909).
  - The 7-day realized `workflow-lean` saving reports itself here after 2026-10-01 (§ 6).

## 1. Harness map and baseline

Full detail: `BASELINE.md` (harness map, reconciled table, per-tool table), measured by eight axis reports in
`measure/` over a 1 GB transcript extract that matches the census of record within 0.001% on every input class.

**What this layer controls.** Claude Code 2.1.280 assembles requests as tools → system → messages, with one cache
breakpoint on the system block and one on the last message. Memory files, the skill listing, deferred tool names,
MCP instructions and hook context all ride in the **first user message with no breakpoint after them**, so every
new context (main session, subagent, workflow agent) re-writes the whole setup prefix: sibling workflow agents
share only the ~10-19k system+tools block (13.2% of first-request tokens came from cache). Main threads write at
the 1h TTL (2× input), agents at 5m (1.25×). The layer controls the content of every memory file, listing and
hook, `claudeMdExcludes`, agent `omitClaudeMd` and `tools:`, TTL settings, and our own scripts; it cannot move the
breakpoint or change built-in tool schemas.

**Cost by source × billing type** (list $, 14.96 d; `BASELINE.md` § (b) has every row):

| Source | Write $ | Re-read $ | Output $ | Total $ | % |
|---|---:|---:|---:|---:|---:|
| Memory files (global CLAUDE.md 12.2%, project files 10.8%, MEMORY.md 2.3%, global rules 2.0%, re-attach 0.6%) | 2,936 | 6,133 | – | 9,069 | 27.9% |
| The model's own turns re-read (Bash commands 8.2%, retained thinking 7.8%, other inputs 2.9%) | 2,055 | 4,105 | – | 6,164 | 19.0% |
| Tool output re-read (file reads 8.2%, command output 6.8%, search/web 3.3%) | 2,142 | 3,805 | – | 5,948 | 18.3% |
| Output generated (tool calls 6.4%, thinking 6.3%, text 0.6%) | – | – | 4,309 | 4,309 | 13.3% |
| System prompt + tools, listings (skills 3.4%) | 1,059 | 2,978 | – | 4,036 | 12.4% |
| Hooks, harness notices, user messages, returns, carry-over, residual | 1,003 | 1,985 | – | 2,993 | 9.2% |
| **Total** | **9,195** | **19,006** | **4,309** | **32,517** | 100% |
| Side requests not in any transcript (prompt suggestion, away summary, titles, goal evaluator, classifier), ESTIMATED | | | | +884 | +2.7% |

Cross-cutting drivers inside those rows: worker contexts (subagents + workflow agents) 39.3%; Stop-hook forced turns
11.1%; cache rewrites after a miss 10.2% (main threads idle > 1h alone 6.5%); tool errors incl. recovery 3.6%.

**Static tokens per request:** main ≈116k (35% of a mean 331k-token request), subagent ≈103k, workflow agent ≈103k.
Headless `/context`: 64.1k from `/tmp`, 103.7k in this repo, 159.6k in reso. **Cache hit rate** 97.4% (main
98.3%). **Turns per task:** mean 154 responses, median 42, p90 303. **Per tool:** Bash is 84% of calls (2.6% errors,
most of them informational non-zero exits); Edit 4.7% errors (79 of 109 read-first errors hit files read via Bash);
Agent 18.4% errors (mostly capacity-admit refusals); per-tool reach and classes in `measure/tool-errors.md`.

## 2. Ranked changes

Ranked by standalone saving ÷ risk (`OPPORTUNITIES.md` has all 26 with method, validation, rollback and overlaps).
Savings are list $ per 14.96 days and % of the $32,517 fleet; **status** is what this pass did.

| # | Change | Layer | Saving (own, %) | Risk | Category | Status |
|---:|---|---|---:|---|---|---|
| 1 | Lean worker type for workflow and research agents (`omitClaudeMd`, no Skill/Agent/MCP tools) | agents | $4,169 (12.8%) | med | FLAG | **built**: `agents/workflow-lean.md`, opt-in per slot · **offline gate FAIL as built 2026-09-24** (padding, +14% turns); ~~re-gate with a scope clause~~ **re-gate PASS 2026-09-24** with the scope clause in the agent (−84% per slot, no guardrail worse); default `agentType` for read-only Workflow research slots (research-subagents slot table, cc-version-audit Step 3) · **wider adoption 2026-09-24**: 14 more read-only, self-contained spawn sites switched (outlook-cleanup, codex-security sweeps and validation, frontier-campaign red-team, model-upgrade, ground-up, repo-wiki, agent-teams, cc-version-audit subagent path, research-subagents synthesis/adversarial/Fable/mid-tier, deep-research nested); code-writing, landing, closing and replay slots, and the operator-owned CLAUDE.md venue rule, unchanged · **realized-savings readout reports itself**: `scripts/tokeff-lean-readout.sh` (on `cc-token-ledger --by-agent-type`, eval traffic excluded) estimates the 7-day saving from 2026-09-24 as lean spend × (1/0.156 − 1); a not-yet-true backlog row's falsifier runs it on or after 2026-10-01, appends the number to § 6 below and lands it; row "7-day realized workflow-lean saving" (442803e68915) |
| 2 | Cache breakpoint after the setup attachments | CC binary | $890-1,210 (2.7-3.7%) | low | PROPOSE (upstream) | proposed; flag-level workaround described · **workaround built and measured 2026-09-24, not switched on** (conviction 85%; `eval/wave2/r2-breakpoint.md`): memory appended to the system prompt cut a cold 3-slot workflow run's cache writes 274k → 128k (−53%, `cc-token-ledger --task`), later siblings 64k → 15k; Agent-tool subagents already share the ~70k setup on 2.1.280, and `workflow-lean` removes most of it for read-only slots. Switching on moves every session's instructions into the system role, so it waits on an F1 quality gate plus a c10 `claudeMdExcludes` for all accounts |
| 3 | Slim global CLAUDE.md (−54% tokens) | memory | $2,036 (6.3%) | med | FLAG | **built**: `CLAUDE.global.slim.md` + ~~per-account switch~~ (withdrawn 2026-09-23: offline gate, then all accounts or none) · **offline gate FAIL 2026-09-24** (false safe-to-close, 8/10 vs 1/10); ships to no account · **re-gate FAIL 2026-09-24**: close contract restored (no over-claim, −31.6% cost), but +13.7% turns and +25% tool errors, from non-close tasks the gate had masked; next, bisect those · **round 3 FAIL 2026-09-24, closed for now**: turns and tool errors fixed (8.6 vs 8.6, errors −23.5%, cost −33.6%), but T16 "one command, not a list" 0/5 vs 4/5 (p=0.048); ships to no account; next lever: narrow the refusal line and probe T16 |
| 4 | Project rules split: resident core + situational half (−88% resident) | memory | $1,639 (5.0%) | med | FLAG | **built**: default-neutral split + staged migration 0036 · **0036 rewritten 2026-09-24** for the shared `settings.json` (writes `~/.claude/settings.json` once, i.e. ALL accounts; refuses unless every account is linked; its per-account arm was a defect after 0037) · **offline gate 2026-09-24: INCONCLUSIVE** (`eval/GATE.md` § F3): −20.9% $/run (p=0.008), success 32/32 both, no guardrail significantly worse, CI lower bounds miss the 5 pp margin (no reachable n certifies 100% vs 100%); a targeted re-run refuted the one harm signal (bare push 2/12 vs 6/12, pooled 11/28 vs 10/28); conviction 80% it is harmless · **staged for the operator**: all-accounts c10 `bash ~/Development/claude-infrastructure/migrations/0036-rules-situational-exclude.sh`, decision "stop loading the situational lessons in every session?" (05017df3f093) |
| 5 | Prompt suggestion off (forced on by our env) | settings | ≤$745 outside the total | low | PROPOSE (operator set it on purpose) | proposed |
| 6 | Idle keepalive for main threads | binary | ≥$549 (1.7%) | low | PROPOSE | proposed · **dropped 2026-09-24**: the user-space half is rank 8 (watcher terms inside the 1h TTL, shipped); a true keepalive needs a no-op cache-touch request the binary does not expose, and waking the model instead injects a turn into idle sessions |
| 7 | Skill listing fits its budget, every own skill described | listings | $442 (1.4%) | low | FLAG (revert toggle) | **done** |
| 8 | Watcher terms inside the 1h cache TTL (3600/14400 s → 3300 s) | our scripts | $345 (1.1%) | low | DIRECT | **done** |
| 9 | Rules essay out of the always-loaded set | memory | $339 (1.0%) | low | FLAG | **built**: absent from the slim arm's `rules.slim/` |
| 10 | Slim project `.claude/CLAUDE.md` (−51%) | memory | $304 (0.9%) | low | FLAG | drafted (`audit/C6.project-claudemd.slim.md`), not wired |
| 11 | Mission board compact render (−82%) | memory | $253 (0.8%) | low | FLAG | **built**: flag file / env, and always on in the slim arm · **offline gate 2026-09-24: INCONCLUSIVE** (`eval/GATE.md` § F4): −6.6% $/run (p=0.031), no guardrail worse, "what should I work on next?" 5/5 vs 5/5; CI lower bounds miss the margin at 23 runs/arm. Turning it on is agent-side (flag file or code default), but shipping past a non-PASS is the operator's call: decision "turn on the compact board for every session now?" (5f446152ffd2), conviction 85% for shipping · **ON fleet-wide 2026-09-24 (02:59Z)**: the decision was actioned and the flag file `~/.claude/autonomy/customer/render-compact` exists, so every session on every account renders the compact board; `rm` that file (or `CC_MISSION_COMPACT=0`) reverts it |
| 12 | Large non-read Bash output to a file | tool results | ≤$453 (1.4%) | med | PROPOSE | proposed (no user-space hook) · **built and gated 2026-09-24, staged for all accounts** (conviction 82%; `eval/wave2/r12-offload.md`): 2.1.280 exposes `updatedToolOutput`, so `hooks/bash-output-offload.sh` saves a >8k-char non-read Bash result to a file and returns head, tail, failure lines and the path; gate 12/12 vs 12/12 success, fired 3 times with no loss (the agent read the saved file for the hidden fact). Needs a settings entry: c10 `bash ~/Development/claude-infrastructure/migrations/0039-bash-output-offload.sh --confirm settings.json` |
| 13 | `/goal` empty-turn notice | hooks | $207 (0.6%) | low | PROPOSE | proposed · **landed 2026-09-24** (`d731852ee`): goal-inert-watch prints one operator notice recommending `/goal clear` after 3 goal-forced turns in a row that wrote nothing, once per streak, never a block |
| 14 | Hook text trims (FORKED list, empty one-liners; stale forwards, DoD lineage) | hooks | $206 (0.6%) | low | DIRECT + FLAG | **done / built** · **stale forwards ON fleet-wide 2026-09-24** (code default 24 h, agent-side, no settings change; conviction 88%): replay over all 918 inboxes (`eval/harness/drain-stale-replay.py`) found 78.7% of forwarded lines delivered >24 h late (median 174 h), almost all expired machine pages; each keeps a grep to its full text; `CC_DRAIN_STALE_FORWARD_H=0` restores verbatim · **DoD lineage-only ON fleet-wide 2026-09-24** (code default, agent-side; conviction 91%): offline probe, 24 blind-judged runs (`eval/wave2/dod-lineage-probe.md`): the old frame dragged a pooled worktree's unrelated contract into 4 of 6 answers, lineage-only 0 of 6, success 11/12 vs 12/12 (the miss is T10's baseline), −7% $/run, −9% turns; `CC_DOD_LINEAGE_ONLY=0` restores the old frame |
| 15 | Agents background long commands | agent prompt | $298 (0.9%) | low-med | FLAG | in `workflow-lean.md`; not added to the default agents · **shipped to the default agents 2026-09-24** (deep-research, deep-research-sonnet, frontier-derivation; workflow-lean's line now says to wait in ≤270 s slices): 92% of agent misses after a 5-60 min gap follow one foreground Bash call >270 s (478/518, 187 of them wait loops after a background launch); probe (`eval/wave2/r15-probe.md`): 0 of 4 misses vs 3 of 3, subagent cache writes −47%, tree −17%, correct 7/7; conviction 88% |
| 16 | `bashOutputMaxChars: 16000` | settings | ~$172 net | med | FLAG | proposed (settings change) |
| 17 | session-continue re-block suppression | Stop hook | $294 (0.9%) | med | FLAG | proposed · **landed 2026-09-24, low-risk half** (`c8dbbc7b5`, `8eba42aac`): no byte-identical 🔧 re-block after a forced turn that wrote nothing; a first block, a changed reason or any write still blocks. The 'wait that already has a waker' half is not built (a misclassified wait would stop autonomous driving) |
| 18 | `total_tokens_reminder` | vendor internal | ≤$263 (0.8%) | med | — | identified (`tengu_lapis_anchor`, a padded 15M countdown, likely an anti-early-stop signal): **keep** |
| 19 | Two lines for recurring tool errors (`sleep N; cmd` refusal, Edit-after-Bash-read) | instructions | $104-138 | low | FLAG | **in the slim variant** |
| 20 | WAKE FLOOR armed mechanically | Stop hook | $100 (0.3%) | low | FLAG | proposed · **landed 2026-09-24** (`0e29e7333`): the wake floor stands down when the Stop asyncRewake arm (mailbox-wake-arm) is registered, instead of blocking the model to arm a watcher |
| 21 | ms365 scoped out of the user MCP config | MCP | ~$200 (0.6%) | med | FLAG | proposed (operator ruling: email-images rule) |
| 22 | Stop reason sent twice (upstream) | binary | $92 | low | PROPOSE | proposed · **filed upstream 2026-09-24**: anthropics/claude-code#96909 (re-verified on 2.1.280: both the meta message and the `hook_blocking_error` attachment carry the reason) |
| 23 | Narrow allow rules for recurring denied shapes | permissions | $66-104 | low | PROPOSE | proposed (operator-owned) |
| 24 | Recurring tool-error fixes in our code | hooks, skills | $72-87 | low | DIRECT | **partly done** (blocked delivery filename); `validate-bash.sh` narrowing proposed · **landed 2026-09-24** by the wave-2 hooks session: validate-bash deny rules match the command with heredoc bodies and quoted literals stripped, keeping a raw match for `sh -c`/`bash -c`/`eval` (`e200e35ed`, `6128f9279`, `2106cb885`); curl-gate judges an untokenisable command per curl segment instead of denying it whole (`edaaa897d`); a capacity refusal says how many refusals remain before it admits (`153d46b22`) |
| 25 | Claude Docs connector off (0 calls) | connectors | $69 | low | FLAG | proposed (account setting) |
| 26 | Stop reasons ≤ 200 chars | Stop hooks | $113 | med | FLAG | proposed · **dropped 2026-09-24**: the long reasons are the close-contract repairs, and every offline gate showed close answers are where quality breaks (F1: 8/10 false closes when the close text was cut); #96909 would remove the duplicated half with no text change |
| T1-T4 | Telemetry: census output fix, per-task ledger, side-request accounting, TTL guard | instruments | $0 (prerequisite) | – | DIRECT | **done** |
| P1-P3 | Cheaper worker model / lower effort for mechanical slots; Fable confinement | models | sensitivities only | med-high | PROPOSE | proposed |

Verified keep-as-is (null results, `OPPORTUNITIES.md` N1-N6): the 1h main / 5m agent TTL split (flipping either way
costs +$1.2-2.8k @5.5); retained thinking (reasoning continuity); sparse Read line numbers ($27: files are read through
Bash); ANSI and format stripping ($192 in total); shorter subagent returns (0.3%).

## 3. Changes made

All on branch `feat/token-efficiency-2026-09-23`, each its own commit (cited by subject: the land rebases these
branch shas). Tests are bats unless noted; every new check carries a mutation or red control.

**Direct — live when landed**

| Commit | What | Measured basis | Verified |
|---|---|---|---|
| `fix(cc-mission): rewrite the board only when its bytes change` | Date stamp instead of minute; skip the write on unchanged bytes | 546 `edited_text_file` injections / 3.79M chars into live sessions in 14 d | `cc-mission-render-stable` |
| `fix(cc-await-ping): watcher terms land inside the 1h prompt-cache TTL` | Idle-scoped default 3600 → 3300 s; every advisory's `--timeout 14400` → 3300 | 116 timeout wakes into full re-writes, mean 390k tokens | `cc-await-ping` 116/116, `wake-floor` 49/49, `mailbox-drain`, `completion-assert` 138/138 |
| `fix(research-subagents): delivery files never start with report/summary/findings/analysis` | Field-7 template and the hook's repair message avoid the names 2.1.280 refuses | 19 refused subagent writes, content then returned inline | agent-teams suites 82/82 |
| `fix(listings): every own skill and command fits the listing budget …` | 55 description fields ≤ 250 chars; 63/63 own entries described | listing needed 48,406 of 30,000 chars; 23 own skills had no description | `skill-listing-budget` 5/5 |
| `fix(cc-quota-price): output from the final record …` | Census output = final record per message | output read 46% low (75.4M vs 139.7M) | selftest 19/19, bats 17/17 |
| `feat(cc-token-ledger): price-weighted cost per task …` | The per-task instrument: by billing type, context type, arm; side requests; TTL guard | replays the census window exactly on responses and every input class | 28/28 |
| hook text trims (see the rules-split / hook commits) | FORKED list → count + 5 names; empty SessionStart one-liners dropped | 18 KB → < 1 KB per session in forked accounts | `config-mirror-assert`, `session-index-start-context` |

**Flagged — ship off; the switch and the rollback are in `TEST_PLAN.md`**

| Commit | Flag | Off by default because |
|---|---|---|
| `feat(instructions): per-account A/B arm for CLAUDE.md variants` + `… the slim arm also swaps rules/ …` | ~~`cc-instructions-variant set <account> slim`~~ (withdrawn 2026-09-23 for production; the tool stays for throwaway/offline config dirs or a fleet-wide switch) | the registry is empty until an account is switched |
| `feat(instructions): CLAUDE.global.slim.md …` | the slim arm's CLAUDE.md (40,374 → 18,546 tokens) | inert until ~~an account is~~ all accounts are switched |
| `feat(cc-mission): compact board render behind a flag …` | `~/.claude/autonomy/customer/render-compact` or `CC_MISSION_COMPACT=1`; always compact in `rules.slim/` | byte-identical when off |
| `feat(agents): workflow-lean …` (+ fixup: operating contract) | `agentType: 'workflow-lean'` per workflow slot / Agent call | nothing passes it yet |
| project rules split (commit: rules split) | migration `0036-rules-situational-exclude.sh` (c10, operator-run) adds a `claudeMdExcludes` glob ~~for one account~~ (withdrawn 2026-09-23: for all accounts or none; one shared `settings.json` after 0037) | both halves load by default: same lessons as before |
| hook trims (commit: hook text) | `CC_DRAIN_STALE_FORWARD_H`, `CC_DOD_LINEAGE_ONLY` | unset = today's output (flag-off byte-identity tested) |

### System prompt diff (keep / rewrite / delete / move for each line)

The per-line table is `audit/SYSTEM_PROMPT_DIFF.md` (147 KB): one row per paragraph, bullet, table row or code
block of every always-loaded instruction file, with its label, reason code (env-fact · quirk-fix · mode-rule ·
default-behavior · unobserved-guard · tool-dup · history · duplicate · contradicts-user · situational), the hook or
skill that enforces it, and where moved content went. Each chunk was checked by an adversarial verifier that listed
every operative rule and its verdict (65 violations, 63 fixed in the text, 1 rejected with reason, 1 outside the
chunk); `audit/C*.verify.md`.

| Source | Original → slim (tokens) | Rows by label | Main reason codes |
|---|---|---|---|
| `CLAUDE.global.md` → `CLAUDE.global.slim.md` | 40,374 → 18,546 (−54%) | KEEP 97 · REWRITE 219 · DELETE 79 · MOVE 13 · NEW 1 | REWRITE: emphasis and exhortation into definitions (all 🚨/CRITICAL/MUST gone; hook-matched glyphs and strings kept verbatim); DELETE: history, dates, measurement narratives, duplicates; MOVE: situational detail to skills, hook messages, or the full file as on-demand reference |
| `~/.claude/rules/agent-operating-lessons.md` (rules-loading essay) | 2,402 → 0 on the slim arm | DELETE 18 · MOVE 3 | history of whether `rules/` loads; no operative rule |
| `~/.claude/rules/00-mission-board.md` | 5,456 → 961 (compact) | render change | the board's instruction and pointers kept; row essays behind `cc-mission show <id>` |
| `.claude/rules/agent-operating-lessons.md` (this repo) | 27,857 → 3.7k resident + 24.6k situational (default loads both) | RESIDENT 19 · INDEX 185 (kept verbatim in the situational half) · duplicates 3 (kept) | lessons that fire in any session stay resident; the rest are grep-able by symptom |
| `.claude/CLAUDE.md` (this repo) | 2,373 → 1,168 (drafted) | KEEP 10 · REWRITE 11 · DELETE 10 | not wired to a flag in this pass |

By section, the Session Close Protocol dominates: 58,688 of 105,278 chars (KEEP 63, REWRITE 106, DELETE 48, MOVE 4).
The full text stays the SSOT and the on-demand reference; the slim file records the hash it was derived from, and
`cc-instructions-variant status` reports STALE when the full file changes after that.

## 4. Test plan and pilot

`TEST_PLAN.md` gives, for every flag: how to turn it on, the primary metric (cost per task on both weightings, from
`cc-token-ledger`), the guardrails (success signals, re-asks, close-contract failures, turns per task, tool errors,
hit rate, hook denies, code survival), the stop rule and the rollback, ~~with a crossover design because accounts are
routed by headroom rather than at random~~. Withdrawn 2026-09-23: the offline headless gate is the go/no-go, any
online arm is assigned per session at launch, and the ship flips all accounts at once.

**Pilot (offline, blind-judged):** full detail in `eval/PILOT.md`; keys, metrics, dossiers and the aggregation
script in `eval/raw/`.

- *Design.* Six tasks shaped like real use (a feature plus commit, a bug fix, an operator step that needs sudo, a
  plan-doc edit, a read-only question, a text draft), each run twice per arm in fresh scratch repos with `claude -p`
  (Opus 5.5, effort high, auto mode, all hooks live). Both arms excluded the user memory files for the run and
  loaded their variant as project memory, so they differed only in content: full 48.2k memory tokens (CLAUDE.md,
  full board, rules essay) vs slim 19.6k (slim CLAUDE.md, compact board). Three read-only research briefs ran twice
  with a `general-purpose` worker and twice with `workflow-lean`. A judge that never saw the arm keys scored every
  run against a per-task rubric and re-checked outcomes itself.
- *Instructions arm.* Success 12/12 in both arms; compliance 54/56 in both; cost per task $0.573 slim vs $0.755
  full (−24%), −31% on the meter proxy. The one task where slim cost more (T2, +9.8%) traced to a `__pycache__`
  artifact the fixture builder left in every copy. Where the arms behaved differently the slim runs were not worse:
  both slim runs of the sudo task gated the install behind `--confirm <target>`, neither full run did.
- *Worker type.* `workflow-lean` first request 5.3k vs 70.5k tokens, 69% fewer subagent tokens, 29.5% lower parent
  cost, the same number of responses, correct 6/6 vs 5/6. Post-land check: a Workflow `agent()` slot with
  `agentType: 'workflow-lean'` and a `schema` returned a valid structured result in a fresh session, first request
  5,149 tokens (a default workflow agent writes ~130k). A session already running when the type lands picks it up
  with a lag: in this session a Workflow call right after the converge failed with "agent type not found", and the
  type appeared in the session's agent list some minutes later. Re-check the agent list before relying on it.
- *Limits.* n = 2 per arm per item: the quality differences are within noise, and the cost difference is a pilot
  estimate. Next is the full offline gate (F1: 20 tasks × ≥5 runs per arm; F2: 10+ briefs), with fixtures that start
  clean, a private TMPDIR per run, and auto-mode push refusals recorded as their own outcome (they hit both arms).

**Full offline gate (2026-09-24):** full detail in `eval/GATE.md`; the harness is in `eval/harness/` and can be
re-run, with raw data in `eval/gate/`. The pass/fail rule was fixed in `harness/agg.py` before any result was read.
- *Slim instructions (F1), 200 runs: 20 tasks, 5 runs per arm each, ABBA order, three accounts. FAIL.* The cost
  held up ($0.493 vs $0.763, −35.4%, −37.0% on the meter proxy). Success (94/100 vs 98/100) and overall compliance
  (95.4% vs 97.1%) were not significantly different. Asked "are we 100% complete and ready to close?" (T10), 4 of 5
  slim runs checked only git and the ledger, never opened the plan, and answered "Good to close: yes" over an open
  wave. All 5 full runs found it. T08 (dirty tree) showed the same over-claim. The failing slim runs were also the
  cheapest, so part of the saving is work not done.
- *`workflow-lean` (F2), 80 slots: 10 briefs, 4 per arm each, run as a Workflow. FAIL as built.* Cost per slot
  $0.089 vs $0.675 (−86.8%), the same correctness on every check the test could verify, and no writes outside
  OUTDIR. The guardrails it failed were turns per agent (5.5 vs 4.8) and padded answers.
- *Post-gate probes, not part of either verdict.* Restoring the full file's "✅ is a safe-to-close assertion"
  paragraph fixed T08 but not T10; the rest of the difference can be bisected with `harness/build-probe-arm.py`.
  A one-line scope clause in the lean brief removed the padding at the same cost.
- *What this decides.* Under the 2026-09-23 ruling this gate replaces the per-account online A/B. The slim
  instructions ship to no account, and `workflow-lean` stays opt-in and unused by default.

**Re-gate (2026-09-24):** both flags were repaired and re-run under the unchanged rule; detail in `eval/GATE.md`
§ Re-gate, raw data in `eval/regate/`.
- *`workflow-lean` (F2), 80 slots. PASS.* The scope clause is now in `agents/workflow-lean.md`. Cost per slot
  $0.109 vs $0.697 (−84.4%), verifier 28/28 and judge 40/40 in both arms, and padding 35/40 vs 36/40 (the gate had
  26/40). Turns +19.5% is not significant (p=0.125). A first re-run failed on tool errors, 32 of 33 of them an `ls`
  of an OUTDIR the gate had pre-created by an unrecorded step. `f2/setup.sh` now records that step, and the second
  run is the verdict. It is the default `agentType` for read-only Workflow research slots in the research-subagents
  skill's slot table and cc-version-audit Step 3. Code-writing, landing and closing slots keep the default subagent.
- *Slim instructions (F1), 200 runs. FAIL.* A bisect found that none of the passages the gate named restores the
  plan-status task (T10), and that even the whole full file misses it 2 times in 5. The shipped fix is the full "✅ is a
  safe-to-close assertion" paragraph plus one new paragraph saying a close question asks about the task's scope, not
  this session's writes. It scored 5/5 on both close tasks in the bisect. In the full re-run the close failure is gone
  (success 98/100 vs 96/100, compliance 97.1% both) at −31.6% cost. The rule still fails it on turns (+13.7%, p=0.014)
  and tool errors (+24.6%, p=0.002). That excess sits in non-close tasks (plan edit, operator step, revert) and was
  already present in the gate, where skipped close work offset it. Next step: bisect those tasks the same way, then
  re-run F1.
- *What this decides.* `workflow-lean` is the default for read-only Workflow slots; the slim instructions still ship
  to no account, so nothing is staged for the operator.

**Round 3 (2026-09-24):** F1 only, under the unchanged rule; detail in `eval/GATE.md` § Round 3, raw data in
`eval/round3/`.
- *Bisect.* The re-gate's slim transcripts showed three causes. Slim told the agent to load two skills that full only
  points to (T03: 4/5 slim runs loaded one, 0/5 full). Slim named the ledger as `scripts/wrap-ledger.sh`, and about 26
  of its 43 non-zero exits were probes for that path. And slim re-issued a push the permission check had refused,
  splitting it or re-running it through `git -C`, until one got through (T04, T12, T19). Probe arms at 5 runs per task
  ($27.60) restored full's pointer wording, used the ledger path `~/.claude/scripts/wrap-ledger.sh`, and added one
  Safety line saying a permission refusal is an answer. Together they brought T04 from 20.6 to 14.2 turns (full
  11.8), T12 from 15.4 to 10.2 (full 11.8) and T19 from 8.2 to 6.6 (full 5.6). All three are in
  `CLAUDE.global.slim.md` (`7140cd89b`).
- *Slim instructions (F1), 200 runs. FAIL on one item.* Turns 8.6 vs 8.6 (p=0.62), tool errors 1.2 vs 1.5 (23.5%
  fewer, p=0.014), cost $0.506 vs $0.763 (−33.6%, lower on 20/20 tasks), success 97/100 vs 95/100, compliance 95.8% vs
  97.3% (CI lower bound −4.0 pp against the −5 pp margin). The judges flagged 2 slim runs and 21 full runs for pushing
  past an approval prompt. The one significant harm is T16, "whats the command to deploy this to prod": all 5 slim runs
  handed over `make deploy ENV=staging && make deploy ENV=prod` as one line, and 4 of 5 full runs gave the prod
  command alone (p=0.048). Conviction that this is a real regression is 70%: it is the smallest p a 5-vs-5 cell can
  reach, the item was 3/5 for slim in both earlier gates, and the new line's "hand it back as the one command to
  run" is a plausible cause.
- *What this decides.* This was the last automatic round. The F1 arm is closed for now, the slim instructions ship to
  no account, and no migration is staged. The next lever, not started: narrow that wording, then probe T16 alongside
  T04, T12 and T19 before any further full F1.

## 5. Gaps

- **Plan-meter weights are bounded, not measured per class.** Cache reads are ≤¼ of list weight and plausibly 0;
  every saving is shown at list weight and on a meter proxy (writes + output).
- **Side requests** (prompt suggestion, away summary, titles, goal evaluator, auto-mode classifier) never reach a
  transcript; they are estimated from Claude Code's per-session cost-state minus transcript usage (≈$884 per window),
  and the classifier's share is not separable.
- **Output is imputed** for 11.1% of responses (2.1.280 agent transcripts rarely record the final usage); totals
  ±3%, per-task figures for agent-heavy trees are noisy.
- **No tokenizer on transcripts**: splits inside measured deltas use fitted chars-per-token ratios (2.2-2.7).
- **Time-based microcompact** (server flag) may clear old tool results at request build; if active, re-read costs of
  old tool output are overstated.
- **Not measured:** latency; the goal evaluator's real cache behaviour; quality under any flag beyond the pilot and
  the 2026-09-24 offline gate (the online A/B is the operator's switch; since 2026-09-23 it is
  per session, never per account).
- **Earlier price fits used first-record output** (`cc-quota-price` before this pass, and the output weight hardcoded
  in `scripts/meter-experiment/analyse.py`): re-fit when the quota-price fit has positive-delta buckets (it abstains
  today).
- **Not wired in this pass:** the slim project `.claude/CLAUDE.md` (no per-account mechanism without a settings
  change; after the 2026-09-23 ruling none is wanted — it would be tested offline and shipped to all accounts or none), `validate-bash.sh` false-positive narrowing (a guard change with false-negative risk for ~0.2%), the Stop-hook
  items (13, 17, 20, 26), and every PROPOSE row. The upstream items (setup breakpoint, double Stop reason) need
  Anthropic.
