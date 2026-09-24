# Test plan for the flagged changes

Every flagged change below ships **off**. This file says how to turn each one on for a test, what to
measure, when to stop, and how to turn it off. Baseline and weights: `BASELINE.md`. Ranked list and
estimates: `OPPORTUNITIES.md`.

## Metrics (all flags)

| | Metric | Instrument |
|---|---|---|
| Primary | Cost per completed task: $ per session tree at list weights **and** on the meter proxy (cache writes + output + uncached; cache reads ≈ 0 on the plan meter, `BASELINE.md` § Weights) | `bin/cc-token-ledger` (per task, `--by-arm` for the instructions arm) |
| Guardrail | Task success signals: the operator's next message moves on vs reports a problem or re-asks ("Good to close?", "what is X"); `completion-assert` verdicts; close-contract failures (D3/D6 blocks) | transcripts; `completion-assert` log |
| Guardrail | Turns (responses) per task and per agent | `cc-token-ledger` |
| Guardrail | Tool-call error rate, per tool, per class | `cc-token-ledger`; `measure/tool-errors.md` method |
| Guardrail | Cache hit rate, rewrites after a miss | `cc-token-ledger --task` write classes |
| Guardrail | Hook denies and forced Stop turns per task | transcripts (`hook_blocking_error`, meta Stop feedback) |
| Guardrail (code) | Agent-written code that survives: commits later reverted or fixed within 7 days | `git log` on the repos touched |

**Ship rule.** A flag stays on only if the primary metric drops and no guardrail regresses beyond noise. Record
null and negative results in this directory. Accounts are routed by quota headroom, not at random, so every
online test below uses a crossover (the arm moves to a second account for a second window) rather than one
fixed treatment account.

## F1. Slim instructions arm (rank 3, plus ranks 9 and 11 for the slim arm)

What changes for an account on the arm: `CLAUDE.md` → `~/.claude/CLAUDE.slim.md` (40,374 → 18,546 tokens),
and `rules/` → `~/.claude/rules.slim/` (the compact mission board, 5,456 → ~961 tokens, and no rules essay,
−2,402). Per context on every account: 48,232 → ~19.5k tokens (−59.6%; `audit/README.md`).

1. **Offline gate first** (no live account touched). Fixed task set drawn from real usage and phrased the way the
   operator writes (short, ambiguous): a feature plus commit, a bug fix, a plan-doc edit, an operator step that
   needs sudo, a read-only question, an outbound draft; later extend to 20 tasks. Each task runs in a scratch git
   repo under both arms with `claude -p`, where each arm excludes the user memory files for that run
   (`--settings '{"claudeMdExcludes":["$CLAUDE_CONFIG_DIR/CLAUDE.md", "~/.claude/rules/…"]}'`) and loads its
   variant as project memory, so the arms differ only in content. A blind judge scores each run against the task
   rubric; compare success, rule compliance, tokens and $ per task, turns, tool errors. The pilot results are in
   `eval/` when run. Do not start the online test if success or compliance drops.
2. **Online A/B**: `cc-instructions-variant set next3 slim`. Window 1: 7 days, next3 on slim, the other accounts
   on the full file. Window 2: `reset next3`, `set next4 slim`, 7 days. Readout: `cc-token-ledger --by-arm
   --since 14d` (arms are labelled by the `instructions` attachment content and the switch log).
3. **Watch items** specific to this flag: close-contract compliance (the slim text keeps every hook-matched
   string, but a literal model may weigh a shorter rule differently); `commit as you go` vs the Bash tool's built-in
   "commit only when asked" (unchanged from the full file, but now more prominent); STALE variants: run
   `cc-instructions-variant status` after any edit to `CLAUDE.global.md` and re-derive the changed sections.
4. **Stop**: any guardrail regression beyond noise, or an operator report of a rule being ignored.
5. **Roll back**: `cc-instructions-variant reset <account>` (new sessions only; running sessions keep what they
   loaded).

## F2. Lean worker agent type `workflow-lean` (rank 1)

What changes: a Workflow `agent()` slot or Agent call that passes `agentType: 'workflow-lean'` gets no memory
files, no skill/agent listings, no MCP tools. Measured first request 4,810 vs 70,531 tokens for `general-purpose`
on the same brief (scratch session).

1. **Offline A/B**: run the same workflow scripts twice, alternating `agentType` (default vs `workflow-lean`), on
   read-only, self-contained briefs (research, measurement, extraction, review). Compare $ per run on both
   weightings, turns per agent, StructuredOutput first-try validity (4.2% invalid today), the script's own
   verifier or judge pass rate, and findings quality scored blind. Break-even: turns per agent may rise ~60%
   before the saving disappears (`OPPORTUNITIES.md` § 4).
2. **Online**: workflow scripts and research briefs opt in per slot. Readout by agent type with
   `cc-token-ledger`.
3. **Not for**: code-writing agents, anything that commits, lands, hands off or closes (they need the operator's
   rules), or briefs that rely on a skill.
4. **Roll back**: stop passing `agentType`; `git rm agents/workflow-lean.md`.

## F3. Project rules split (rank 4)

What changes: `.claude/rules/agent-operating-lessons.md` keeps the header and the resident lessons; the
situational lessons move verbatim to `.claude/rules/agent-operating-lessons-situational.md`. By default both load,
so nothing changes. The flag excludes the situational file per account.

1. **Turn on**: run migration `migrations/0036-*` for one account (class c10, operator-run; it adds a
   `claudeMdExcludes` glob to that account's `settings.json`). Crossover as in F1, but only sessions started in
   claude-infrastructure are in scope.
2. **Watch**: repeats of mistakes a situational lesson covers (grep the transcripts for the lesson's symptom); how
   often sessions grep the situational file when they hit a failure (the resident pointer tells them to).
3. **Roll back**: remove the glob from that `settings.json` (the migration's verify line names it).

## F4. Mission board compact render, all accounts (rank 11)

The slim arm already gets the compact board through `rules.slim/`. For every account at once:
`touch ~/.claude/autonomy/customer/render-compact` (or `CC_MISSION_COMPACT=1`); byte-identical output when off.
Watch that sessions still work the top row or say why not (the compact render keeps that instruction and the
`cc-mission next` / `cc-mission show <id>` pointers). Set each row's `headline` (`cc-mission touch --headline`)
before turning it on, so rows are summarised by their owners rather than cut at 200 chars. Roll back: remove the
flag file.

## F5. Skill and agent descriptions (rank 7)

All own skills fit the 30,000-char listing budget again. Guardrail: Skill tool calls per main session (17.4% of
main sessions today) and slash-command use must not drop; check that each skill still triggers on the phrases in
real prompts (`measure/listings.md` has the usage evidence). Roll back: `git revert` the description commit.

## F6. Hook text flags (rank 14)

- `CC_DRAIN_STALE_FORWARD_H=<hours>`: forwarded peer mail older than that arrives as a one-line summary with a path.
  Watch missed-mail signals (`cc-notify reason=`, `cc-inbox-guard` pages).
- `CC_DOD_LINEAGE_ONLY=1`: the SessionStart frozen-DoD context carries only this session's own lineage. Watch
  `completion-assert` false-dones and scope complaints after a recycle or handoff.
Turn each on in the settings env of one account (a settings change: stage it as a migration), compare against the
others, roll back by removing the env line.

## Proposals only (no flag built; each needs an operator decision or an upstream change)

| Item | Test when adopted |
|---|---|
| Prompt suggestion off (`CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=true` is set on purpose) | one account off for 7 days; side-request $ from `cc-token-ledger --side-requests`; the operator's UX judgment |
| `bashOutputMaxChars: 16000` | per-account A/B: $ per task, turns, follow-up reads of the persisted file within 3 turns |
| session-continue re-block suppression; WAKE FLOOR armed mechanically; Stop reasons ≤200 chars; `/goal` empty-turn notice | per hook: forced turns per context, repeat share; guardrails: sessions idling on 🔧 work, missed peer mail |
| ms365 scoped out of the user MCP config; Claude Docs connector off | operator ruling first (the email-images rule depends on ms365) |
| Setup breakpoint after the memory/listing attachments (upstream) or the `--append-subagent-system-prompt-file` workaround | first-request cache-read share of sibling agents (13.2% today) |
| Idle keepalive for main threads (needs a no-op request mechanism) | long-gap rewrites per window |
| Cheaper model or lower effort for mechanical Workflow slots | whole-tree $ per run and judged quality, slot by slot |
