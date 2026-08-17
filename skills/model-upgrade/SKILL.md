---
name: model-upgrade
description: Streamlined runbook for moving the toolchain to a new Claude model — or off one when access ends. Use when Anthropic ships a model ("upgrade to Opus 4.9", "Fable 5 released"), when a plan-access window opens/closes ("we lost Fable access", "downgrade"), or when claude-lint-models flags stale refs / an expired frontier window. Covers doc/config reference sweeps, the dynamic model ladder, and the launcher-track procedure. NOT for app-code SDK migrations (reso has no Anthropic SDK; for SDK code use /claude-api migrate).
allowed-tools: Read, Edit, Write, Bash, AskUserQuestion, Skill
---

# model-upgrade — model-reference upgrade/downgrade runbook

**Step -1 (always):** invoke the `claude-api` skill first for authoritative model IDs,
pricing, and capability facts. Never answer model facts from memory.

**Step 0 — classify the event.** Three distinct cases; misclassifying is THE failure mode:

| Case | Signature | Example |
|---|---|---|
| **A. Lateral** | New model REPLACES same-family prior | Opus 4.7 → 4.8; Sonnet 4.6 → 4.7 |
| **B. Tier-insertion** | New tier ABOVE the ladder; old top STAYS in service | Fable 5 above Opus 4.8 (2026-06-09) |
| **C. Downgrade / window-end** | Access to top tier lapses; fall back | a FUTURE tier lapses (Fable 5 is now PERMANENT — Max/Team-Premium inclusion at 50% of limits from 2026-07-20, `frontier_access.permanent: true`, so it no longer applies) |

A blind literal sweep is correct ONLY for Case A. Case B is "add alongside" (per
claude-api migration guide Step 1 Bucket 2) — rewriting `opus → fable` would
de-tier Opus references that must stay Opus.

## SSOT map

| File | Job |
|---|---|
| `~/.claude/model-config.yaml` | versions (latest/prior per family: frontier/opus/sonnet/haiku), `frontier_access` window, `pricing_per_mtok`, role ladder, effort defaults, deprecations |
| `~/bin/claude-bump-models` | literal-ID sweep over classified files (`--apply`, `--check`, `--from-to OLD NEW`) |
| `~/.claude/scripts/claude-lint-models.sh` | stale-ref lint (`--all`) + frontier-window expiry check (fails when window lapsed but `active: true`) |
| `~/.claude/model-classification.json` | `update` = auto-sweepable; `preserve` = historical, never touch; `review` = mixed prose/citations — THIS skill walks them by hand |
| `~/.zshrc` | launcher tracks (see Appendix) — runtime model selection, separate from doc refs |

**Known blind spot:** the sweep/lint match full IDs (`claude-opus-4-7`) only. Prose
forms ("Opus 4.7", "Opus-tier") live in `review` files and need judgment — that's
why they're not in `update`.

## Case A — Lateral bump

1. `model-config.yaml`: set `<family>_prior` = old latest, `<family>_latest` = new ID.
   Update `pricing_per_mtok` + `deprecations` from claude-api skill facts.
2. `claude-bump-models` (dry-run) → review the pair list → `--apply`.
3. `claude-lint-models.sh --all` → must be green.
4. Walk every `review`-classified file: fix prose refs ("Opus 4.7" → "Opus 4.8")
   **except** historical citations (benchmarks "Opus 4.6 76% at 1M", incident records
   "GH #52522 Opus 4.7 auto-compact", provenance lines "--model claude-opus-4-8").
   Test: does the sentence claim "what we use NOW" (update) or "what happened THEN" (preserve)?
5. Project-side files: edit in the session worktree + commit (never edit the primary
   checkout directly — note `claude-bump-models --apply` DOES edit the primary checkout's
   working tree, leaving uncommitted changes there; surface that to the user).
6. Launcher tracks usually unchanged (auto-mode picks the model). Check
   `auto_mode_allowlist` — new models lag ~2 weeks before entering Max-plan auto mode.

## Case B — Tier-insertion (new top tier)

1. `model-config.yaml`: set `frontier_latest`; fill `frontier_access` (model, tracks,
   source, start, end, `active: true`, fallback). Add pricing row. Update roles that
   should ride the new tier (`lead_default`, `research_adversarial`, `workflow_judge`,
   `eval_judge`) — teammate roles stay on the auto-mode-allowlisted model. Agent
   Teams run BOTH launcher tracks (eval-track teams empirically fine since 2.1.156);
   the teammate gate is `auto_mode_allowlist` in the SSOT, not the track — once the
   new tier is verified to hold auto mode (one test spawn; `claude auto-mode config`
   does NOT print allowModels), append it to `non_firstParty_max` and the
   enforce-hook follows automatically.
2. **Write all doc references conditionally** so the downgrade needs zero doc edits:
   > "frontier: <Model> via call-time `model: "<alias>"` override while
   > `frontier_access.active` AND on the <track> track; otherwise <fallback>"
3. Canonical reference list (the Fable 5 set — re-walk these for any future insertion):
   - `~/.claude/rules/research-subagents.md` — § Cost Asymmetry calibrated-cost line,
     § Per-Subagent Depth frontier block + type-mix pin + tier-picking trigger +
     Explore/deep-research routing bullet, § Synthesis Bottleneck lead-context line
   - `~/.claude/commands/research.md` — type-mix table + footnote
   - `~/.claude/agents/deep-research.md` + `deep-research-sonnet.md` — descriptions only
   - `~/.claude/model-config.yaml` — roles/comments
   - project `.claude/commands/project-pass.md`, `docs/research/CONTEXT_EXHAUSTION_GUARDRAILS.md`
4. **Agent frontmatter stays a family alias (`model: opus`)** — definitions are shared
   by both launcher tracks; the new tier exists only where its CC version runs. The
   upgrade is always a call-time `model` override (Agent tool: `"fable"`; Workflow
   `agent()` opts.model) from a lead that has checked `frontier_access`.
5. Launcher: bump the EVAL track only (Appendix). NEVER the stable track.
6. Verify (below) + write a memory entry with the window end date.

## Case C — Downgrade / window-end

Because Case B wrote conditional references, this is config-only:

1. `model-config.yaml`: `frontier_access.active: false` (leave the block — historical
   record + reusable for the next window).
2. `~/.zshrc`: remove `--model <id>` from the eval-track function (2 refs, ~lines
   306/310); keep the version pin unless also rolling back CC.
3. Roles: conditional roles auto-degrade via `fallback` — no edit. If any doc hard-pinned
   the frontier ID outside the conditional pattern: `claude-bump-models --from-to
   claude-fable-5 claude-opus-4-8` (dry-run first).
4. `claude-lint-models.sh --all` → expiry warning clears (active is false).
5. Memory: note the window closed + actual end date.

## Verification (every case)

```bash
yq -e '.versions' ~/.claude/model-config.yaml >/dev/null && echo yaml-ok
claude-bump-models            # dry-run: expect 0 pending
~/.claude/scripts/claude-lint-models.sh --all
rg -n 'claude-(fable|opus|sonnet|haiku)-[0-9]|Opus 4\.[0-9]|Fable [0-9]' \
  ~/.claude/rules ~/.claude/commands ~/.claude/agents ~/.claude/model-config.yaml
claude-next --version 2>/dev/null   # eval track launches on expected CC + model
```

## Appendix — launcher tracks (runtime, distinct from doc refs)

- **Stable** `claude`/`cc` → `claude-latest` → `~/.claude-versions/current` (held
  2.1.114; Agent Teams track). **NEVER bump for a new model.** MANIFEST default-deny.
- **Eval** `claude-next`/`cc-next` → hardcoded `~/.claude-<NNN>/node_modules/.bin/claude`
  in `~/.zshrc` (two path refs + header comment). New-model procedure:
  `npm install --prefix ~/.claude-<NNN> @anthropic-ai/claude-code@<ver>` → repoint both
  refs → add/remove `--model <id>` → `source ~/.zshrc`. Keep prior `~/.claude-<NNN>`
  dirs as rollback. "Upgrade Claude Code to model X" ALWAYS means this track.
- `~/.claude-next/{CLAUDE.md,rules,settings.json}` symlink to `~/.claude/` — knowledge
  edits propagate to both tracks automatically; that's why frontmatter must stay
  track-safe (point 4 of Case B).

## Invariants

1. Never pin a model the stable track doesn't know (settings.json is shared via symlink).
2. Never rewrite historical citations, benchmarks, incident records, or provenance lines.
3. Frontier docs are conditional-by-construction; if you catch yourself writing a bare
   "use Fable 5" without the window condition, rewrite it.
4. Model facts come from the claude-api skill, not memory.
5. `claude-bump-models --apply` mutates the PRIMARY checkout working tree — project-side
   fixes go through a session worktree + commit instead.
6. **Rolling CC back off the eval track (2.1.170 → stable 2.1.114) silently drops the
   Fable-5 long-horizon harness** — the autonomous-loop preamble, the "check your last
   paragraph before ending the turn" early-stop instruction, and the `SendUserMessage`
   verbatim tool all live in the 2.1.170 binary, not 2.1.114. A model-only downgrade
   (Case C, window-end) keeps the version pin and is unaffected; a CC-VERSION rollback is
   what loses them. After any CC-version rollback, re-verify that autonomous /loop,
   /frontier-run, and /schedule workflows still self-terminate and report correctly.
