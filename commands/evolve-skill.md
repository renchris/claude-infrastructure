---
name: evolve-skill
description: SPIKE — GEPA/DSPy-style offline A/B evolution of ONE prompt-only skill's SKILL.md body against a small fixture set, scored by an LLM-judge or a deterministic gate. API-only (~$2-10/run), no GPU. Emits a winning diff for human apply — NEVER hot-swaps. Hermes self-evolution analog (Hermes does not actually run this on its own skills).
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
- A fixture set of 3-5 cases at `~/.reso/evolve/<slug>/cases/*.md`, each with `## input` +
  `## expected_behavior`. If absent, STOP and help author them first (cold-start may mine
  `~/.claude/session-index.db` for representative prompts).
- Use the binary `claude-latest` directly (the `claude` shell function does worktree routing).
  Flags verified on 2.1.114: `--bare --print --output-format json --append-system-prompt <body>`
  `--json-schema <s> --max-budget-usd <n> --model <m>`. `--bare` skips hooks/auto-memory/CLAUDE.md
  → clean A/B isolation.

## Loop (cap 2-3 generations; pass a hard `--max-budget-usd` to every call)
1. **Baseline**: read `~/.claude/skills/<slug>/SKILL.md`; split frontmatter (frozen) from body (mutable).
2. **Generate <=2 variants** of the body via one reflective `claude-latest -p` call seeded with the
   baseline body + the failing/low-scoring cases (GEPA reads WHY it failed, not just that it did).
3. **Score** baseline + each variant on every case:
   ```
   claude-latest -p --bare --output-format json \
     --append-system-prompt "<variant body>" \
     --json-schema '{"type":"object","properties":{"score":{"type":"number"},"feedback":{"type":"string"}},"required":["score","feedback"]}' \
     --max-budget-usd 2 "<case input>"
   ```
   - `--gate typecheck`: additionally shell out to `pnpm tsc --noEmit` in a scratch worktree and
     DISQUALIFY any variant that regresses it (a deterministic gate beats a reward-hackable judge).
   - `--gate qa`: parse the `/qa-commits` digest for new Critical/High; disqualify regressions.
4. **Keep** a variant only if its aggregate score STRICTLY beats baseline across >=2 reruns
   (kills noise-driven mutation; LLM scoring is non-deterministic).
5. **Propose**: write the winner to `~/.reso/evolve/<slug>/<run>/`, show the diff vs the live
   SKILL.md, and use **AskUserQuestion** to apply via Edit or discard. NEVER write the skill file
   without approval.

## Report
Per-case scores (baseline vs variants), the winning diff, total $ spent, and a keep/discard
recommendation. If no variant strictly beats baseline, say so — that is a valid (and common) outcome.
