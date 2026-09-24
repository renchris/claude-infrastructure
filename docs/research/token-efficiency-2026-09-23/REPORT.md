# Token-efficiency pass on the Claude Code harness — report (2026-09-23)

Scope (frozen): token-efficiency pass on this Claude Code harness (the `~/.claude` layer this repo deploys):
map the harness and measure a baseline by source and billing type, rank the opportunities, make the safe direct
changes, put the rest behind flags or in proposals, and report. Spec: `SPEC.md`.

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
  for workflow and research agents (12.8%) and the slim instructions arm (≈8% per account on the arm).
- **Pilot eval (offline, blind-judged, n = 2 per arm per item):** the slim instructions arm cost **24% less per task**
  ($0.573 vs $0.755; 31% less on the meter proxy) with the same success (12/12 both) and compliance (54/56 both);
  the `workflow-lean` worker started 13× smaller (5.3k vs 70.5k tokens), cost 29.5% less per run and was correct
  6/6 vs 5/6. Too small to prove parity; the full offline gate in `TEST_PLAN.md` comes before any account switch.

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
| 1 | Lean worker type for workflow and research agents (`omitClaudeMd`, no Skill/Agent/MCP tools) | agents | $4,169 (12.8%) | med | FLAG | **built**: `agents/workflow-lean.md`, opt-in per slot |
| 2 | Cache breakpoint after the setup attachments | CC binary | $890-1,210 (2.7-3.7%) | low | PROPOSE (upstream) | proposed; flag-level workaround described |
| 3 | Slim global CLAUDE.md (−54% tokens) | memory | $2,036 (6.3%) | med | FLAG | **built**: `CLAUDE.global.slim.md` + per-account switch |
| 4 | Project rules split: resident core + situational half (−88% resident) | memory | $1,639 (5.0%) | med | FLAG | **built**: default-neutral split + staged migration 0036 |
| 5 | Prompt suggestion off (forced on by our env) | settings | ≤$745 outside the total | low | PROPOSE (operator set it on purpose) | proposed |
| 6 | Idle keepalive for main threads | binary | ≥$549 (1.7%) | low | PROPOSE | proposed |
| 7 | Skill listing fits its budget, every own skill described | listings | $442 (1.4%) | low | FLAG (revert toggle) | **done** |
| 8 | Watcher terms inside the 1h cache TTL (3600/14400 s → 3300 s) | our scripts | $345 (1.1%) | low | DIRECT | **done** |
| 9 | Rules essay out of the always-loaded set | memory | $339 (1.0%) | low | FLAG | **built**: absent from the slim arm's `rules.slim/` |
| 10 | Slim project `.claude/CLAUDE.md` (−51%) | memory | $304 (0.9%) | low | FLAG | drafted (`audit/C6.project-claudemd.slim.md`), not wired |
| 11 | Mission board compact render (−82%) | memory | $253 (0.8%) | low | FLAG | **built**: flag file / env, and always on in the slim arm |
| 12 | Large non-read Bash output to a file | tool results | ≤$453 (1.4%) | med | PROPOSE | proposed (no user-space hook) |
| 13 | `/goal` empty-turn notice | hooks | $207 (0.6%) | low | PROPOSE | proposed |
| 14 | Hook text trims (FORKED list, empty one-liners; stale forwards, DoD lineage) | hooks | $206 (0.6%) | low | DIRECT + FLAG | **done / built** |
| 15 | Agents background long commands | agent prompt | $298 (0.9%) | low-med | FLAG | in `workflow-lean.md`; not added to the default agents |
| 16 | `bashOutputMaxChars: 16000` | settings | ~$172 net | med | FLAG | proposed (settings change) |
| 17 | session-continue re-block suppression | Stop hook | $294 (0.9%) | med | FLAG | proposed |
| 18 | `total_tokens_reminder` | vendor internal | ≤$263 (0.8%) | med | — | identified (`tengu_lapis_anchor`, a padded 15M countdown, likely an anti-early-stop signal): **keep** |
| 19 | Two lines for recurring tool errors (`sleep N; cmd` refusal, Edit-after-Bash-read) | instructions | $104-138 | low | FLAG | **in the slim variant** |
| 20 | WAKE FLOOR armed mechanically | Stop hook | $100 (0.3%) | low | FLAG | proposed |
| 21 | ms365 scoped out of the user MCP config | MCP | ~$200 (0.6%) | med | FLAG | proposed (operator ruling: email-images rule) |
| 22 | Stop reason sent twice (upstream) | binary | $92 | low | PROPOSE | proposed |
| 23 | Narrow allow rules for recurring denied shapes | permissions | $66-104 | low | PROPOSE | proposed (operator-owned) |
| 24 | Recurring tool-error fixes in our code | hooks, skills | $72-87 | low | DIRECT | **partly done** (blocked delivery filename); `validate-bash.sh` narrowing proposed |
| 25 | Claude Docs connector off (0 calls) | connectors | $69 | low | FLAG | proposed (account setting) |
| 26 | Stop reasons ≤ 200 chars | Stop hooks | $113 | med | FLAG | proposed |
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
| `feat(instructions): per-account A/B arm for CLAUDE.md variants` + `… the slim arm also swaps rules/ …` | `cc-instructions-variant set <account> slim` | the registry is empty until an account is switched |
| `feat(instructions): CLAUDE.global.slim.md …` | the slim arm's CLAUDE.md (40,374 → 18,546 tokens) | inert until an account is switched |
| `feat(cc-mission): compact board render behind a flag …` | `~/.claude/autonomy/customer/render-compact` or `CC_MISSION_COMPACT=1`; always compact in `rules.slim/` | byte-identical when off |
| `feat(agents): workflow-lean …` (+ fixup: operating contract) | `agentType: 'workflow-lean'` per workflow slot / Agent call | nothing passes it yet |
| project rules split (commit: rules split) | migration `0036-rules-situational-exclude.sh` (c10, operator-run) adds a `claudeMdExcludes` glob for one account | both halves load by default: same lessons as before |
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
hit rate, hook denies, code survival), the stop rule and the rollback, with a crossover design because accounts are
routed by headroom rather than at random.

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
- **Not measured:** latency; the goal evaluator's real cache behaviour; turns per agent under `workflow-lean` at
  scale; quality under any flag beyond the pilot (the online A/B is the operator's switch).
- **Earlier price fits used first-record output** (`cc-quota-price` before this pass, and the output weight hardcoded
  in `scripts/meter-experiment/analyse.py`): re-fit when the quota-price fit has positive-delta buckets (it abstains
  today).
- **Not wired in this pass:** the slim project `.claude/CLAUDE.md` (no per-account mechanism without a settings
  change), `validate-bash.sh` false-positive narrowing (a guard change with false-negative risk for ~0.2%), the Stop-hook
  items (13, 17, 20, 26), and every PROPOSE row. The upstream items (setup breakpoint, double Stop reason) need
  Anthropic.
