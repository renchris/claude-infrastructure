---
name: evolve-skill
description: "Spike: offline A/B evolution of ONE prompt-only skill's SKILL.md body against fixtures, scored by an LLM judge or a gate. Runs on plan quota, not an API key; emits a winning diff for a human to apply, never hot-swaps."
allowed-tools: Read, Write, Edit, Bash, Glob, AskUserQuestion
argument-hint: "<skill-slug> [--gate typecheck|qa] — defaults to LLM-judge scoring"
---

# /evolve-skill — offline skill self-evolution (SPIKE, human-gated)

Improve one **prompt-only** skill by generating + scoring variants offline, then proposing the
winner as a diff. Treat as a throwaway spike on ONE skill first (recommend `pyramid-principle`).
**Never auto-applies** — Claude Code has no skill hot-swap, and our rule is INTEGRATE-never-overwrite.

> Honest framing: this is us *inventing* a loop inspired by GEPA. The hermes-agent
> "self-evolution" repo ships GEPA for *user-supplied* prompts/regex, not on its own skills,
> and its shipped fitness function was bag-of-words overlap. We replace that with a real judge.

## Preconditions
- Target is a **self-contained prompt skill** (no deterministic runtime gate of its own).
- A fixture set at `~/.reso/evolve/<slug>/cases/*.md` (pyramid-principle's is a symlink to this
  repo's `evolve-fixtures/`). A case is a file with both `## input` and `## expected_behavior`; skip
  any other `.md` there, such as the set's `README.md`. If absent, STOP and help author them first
  (cold-start may mine `~/.claude/session-index.db` for representative prompts).
- Size the set before spending. With 15 or more cases, draw a random third as **test**: it is
  scored every round, never shown to the variant generator, and its delta is the result. Below 15
  there is no held-out set, so run every case at 3+ reps and label each result **directional**: a
  gain on cases the generator read is not evidence it generalizes.
- Run every call on `"$(~/.claude/bin/cc-claude-bin)"`, the binary interactive sessions run (the
  `claude` shell function does worktree routing). Not `claude-latest`: it is pinned at 2.1.114, and
  the API refuses `claude-opus-5-5` below 2.1.280. Not `--bare` either: it authenticates only with an
  API key (`ANTHROPIC_API_KEY` or an `apiKeyHelper`), never the plan login, so it either fails or
  bills dollars, and `accounts.json` has `spend.usage_credits_authorized: false`. Isolate the way the
  codex-probe sweeps do (`docs/research/opus55-effort-sweep-2026-09-22/run-arms.sh`):
  `CLAUDE_CONFIG_DIR=<account>`, a neutral `mktemp -d` cwd, and `-p --tools "" --setting-sources ""
  --strict-mcp-config --disable-slash-commands --no-session-persistence --output-format json`. That
  loads no CLAUDE.md, memory, hooks or skills, and it runs on plan quota.
- Record per (case, rep) from each result JSON: `.result` (and the parsed score object for a judge
  call), the `.modelUsage` keys (the served model; stop if it is not the one you asked for), `.usage`,
  `.total_cost_usd` and `.stop_reason`. A call that errors goes to `errors.jsonl` with its reason,
  never into the scores.

## Loop (one hypothesis per round; pass a hard `--max-budget-usd` to every call)
State lives on disk so a resumed session can pick up where this one stopped. `~/.reso/evolve/<slug>/<run>/`
holds `_state.json` (train and test ids, reps, models, efforts, `best`), then `baseline/` and `v1/`,
`v2/`, ... Each holds `results.jsonl` (one row per (case, rep): `prompt_id`, `rep`, `grade`, the
judge's `explanation`, the served `model`, `usage`) and `traces/`; each `vN/` adds `change.md` (the
hypothesis) and `change.patch` (the diff against the live SKILL.md). After each round, rebuild
`report.html` with `shared/evals/report/build-report-lite.mjs` from the claude-api skill (load the
skill to get its directory).
1. **Baseline**: read `~/.claude/skills/<slug>/SKILL.md`; split frontmatter (frozen) from body (mutable).
   Score it at R >= 3 reps. Its rep-to-rep spread on the mean score is the noise floor: a variant
   has to beat the current best by more than that to count.
2. **Generate one variant** per round via one reflective call on the step-3 binary and isolation
   flags, with the generator's pinned `--model` and `--effort`, seeded with the current best body +
   the low-scoring **train** cases' outputs and judge feedback (GEPA reads WHY it failed, not just
   that it did). Never show it a test case. Ask for one change aimed at one failure behavior, stated
   as behavior rather than copied case content, and cut any line that only restates default
   behavior before you score it.
3. **Score** baseline + each variant on every case at R reps, in two calls per (case, rep). The
   generator never sees the rubric, and the judge never sees which variant wrote the output:
   ```
   B="$(~/.claude/bin/cc-claude-bin)"
   ISO=(--tools "" --setting-sources "" --strict-mcp-config --disable-slash-commands
        --no-session-persistence --output-format json --max-budget-usd 2)
   # generate: the variant body rides the system prompt; the case's `## input` is the whole prompt
   (cd "$(mktemp -d)" && CLAUDE_CONFIG_DIR=<account> "$B" -p "${ISO[@]}" \
     --model claude-opus-5-5 --effort high --append-system-prompt "<variant body>" "<case input>")
   # judge: the case's `## input` and `## expected_behavior`, then the generator's `.result` marked
   # as untrusted data (the rubric checks dropped and invented facts against the input)
   (cd "$(mktemp -d)" && CLAUDE_CONFIG_DIR=<account> "$B" -p "${ISO[@]}" \
     --model claude-opus-5 --effort xhigh \
     --json-schema '{"type":"object","properties":{"score":{"type":"number"},"feedback":{"type":"string"}},"required":["score","feedback"]}' \
     "<input + rubric + output>")
   ```
   - Pin `--model` and `--effort` for the whole run (the generator's id is `versions.opus_latest` in
     `~/.claude/model-config.yaml` when the run starts): with neither, the scorer ran on the binary's
     default model, and a 5.5-family launch with no `--effort` runs at MEDIUM whatever `effortLevel`
     says, so scores stopped being comparable across a bump.
   - The judge is `versions.opus_prior` at `effort_defaults.verify_judge`, as in the house sweep
     judges, so no output is graded by the model that wrote it. Tell it not to reward length.
   - Before the first scored pass, run one judge call and confirm the score object comes back
     parsed; then feed the judge an empty output, "I don't know", and a confident answer to a
     different case. All three must score 1-2, or fix the judge prompt first.
   - `--gate typecheck`: additionally shell out to `pnpm tsc --noEmit` in a scratch worktree and
     DISQUALIFY any variant that regresses it (a deterministic gate beats a reward-hackable judge).
   - `--gate qa`: parse the `/qa-commits` digest for new Critical/High; disqualify regressions.
4. **Keep** a variant only if its mean score on **test** (the whole set when there is no split)
   beats the current best by more than the noise floor from step 1, and train did not drop. Train
   up with test flat means it overfit the cases the generator read: revert it. Stop after two
   rounds in a row that do not clear the floor, or after 4 rounds.
5. **Propose**: write the winner to `~/.reso/evolve/<slug>/<run>/`, show the diff vs the live
   SKILL.md, and use **AskUserQuestion** to apply via Edit or discard. NEVER write the skill file
   without approval.

## Report
Lead with the test-score delta, baseline vs winner, each with its interval; train scores are
supporting detail, and with no split the delta is labeled directional. Then per-case scores
(baseline vs variants), the winning diff, and spend: the summed `usage` of every generator and judge
call, failed calls included, with its list-price `total_cost_usd` (this fleet pays it in plan quota,
not dollars). If no variant clears the noise floor, say so and recommend discarding — that is a
valid (and common) outcome.
