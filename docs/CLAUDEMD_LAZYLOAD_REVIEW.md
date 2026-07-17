# Global Knowledge-Layer Lazy-Load Restructure — Operator Review

**Branch:** `feat/claudemd-lazyload`  ·  **Status:** committed, NOT deployed, NOT shipped — awaiting your approval of the resident-core diff.

## TL;DR

The always-resident global knowledge layer (re-read every turn by every one of 20-100 concurrent
agents) is cut **1516 → 290 lines (−80%), 90.9KB → 21.9KB (−75%)** — **~17K tokens reclaimed per
turn, per agent** — with **zero knowledge deletion** (proven mechanically) and **zero core-behavior
change** (every behavior-critical directive stays resident; only execution *detail* moved to
lazy-load skills that load on a proven trigger).

| Resident surface | Before | After |
|---|---|---|
| `~/.claude/CLAUDE.md` | 562 lines | **290 lines** |
| `~/.claude/rules/agent-teams.md` | 182 lines | 0 (→ skill) |
| `~/.claude/rules/research-subagents.md` | 772 lines | 0 (→ skill) |
| **TOTAL resident / turn** | **1516 lines / 90.9KB** | **290 lines / 21.9KB** |

The win is not quota — it is **context-window headroom** (later rot/compaction) and **adherence** (a
rule the model can hold, loaded sharply-when-relevant, is followed more reliably than one buried in a
1500-line always-on prompt).

## HOW TO REVIEW (the resident-core diff — please eyeball this)

```bash
cd /tmp/wt-claudemd-lazyload
git diff 5b814ac -- CLAUDE.md        # the resident core: before (562) → after (290)
git show HEAD:CLAUDE.md              # the full lean resident core as it will ship
git log --oneline origin/main..HEAD  # 5 commits (baseline → skills → restructure → triggers → harden)
git show --stat origin/main..HEAD    # everything that changed
```

The baseline commit `5b814ac` is the exact current live resident surface, committed as the before-state.

## What STAYED resident (verbatim) — the sacred core + pre-cognition invariants

**Sacred (never moved, byte-exact):** Rule Priority Legend · Git Commit Messages/Workflow/Safety ·
AI Guidelines · File Update / OVERWRITE-GUARD · Memory Hygiene / anti-capture · Concurrent-Sessions
worktree isolation · **Session Close Protocol** (all escalation surfaces — auth/session, destructive
migration, nav pattern, DB timeout — are embedded here and stay resident).

**Pre-cognition invariant + pointer (kept resident so behavior holds even before a skill loads):**
Agent Teams Reinforcement (the DEFAULT rule + 6-box pre-spawn checklist + max-6/shutdown_request ops) ·
Research Subagents Reinforcement (decompose-before-count, default N, no-cap) · a compact Frontier-routing
invariant (opt-in / delta-only / never-routine / bounded-autonomous-escalation).

## What MOVED to lazy-load skills (full detail behind a proven trigger)

| Skill (lazy) | lines | Relocated from | Trigger |
|---|---|---|---|
| `research-subagents` | 772 | rules/research-subagents.md (byte-identical) | `/research` invokes it · **Agent-spawn hook** injects pointer on research spawns · resident invariant carries the core |
| `agent-teams` | 243 | rules/agent-teams.md (byte-identical) + folded-in Teammate-Lifecycle block | **Agent-spawn hook** injects pointer on every `team_name` spawn · resident invariant carries the core |
| `coding-standards` | 63 | CLAUDE.md Stack + TS/JS + Python + File-Naming | description-match (authoring/review code) · resident pointer names the core rules |
| `browsermcp` | 72 | CLAUDE.md BrowserMCP + agent-browser + Vercel | description-match (browser automation) · resident pointer keeps "BrowserMCP not Playwright" |
| `frontier-routing` | 53 | CLAUDE.md Frontier Tier Routing (the 5 standing duties) | **SessionStart hook** injects status every session · resident compact invariant |
| `plan-conventions` | 44 | CLAUDE.md Plan Document Conventions | **backup-before-write hook** injects on plan-file edits · resident pointer keeps Phase-0 |
| `manual-command-delivery` | 23 | CLAUDE.md Manual-Command Delivery | description-match · **resident pointer states the full core rule** |

## REGRESSION EVIDENCE (this is the part that earns the acceptance bar)

**1. Zero knowledge deletion — mechanically proven.** A coverage script checks every content line of
the original resident surface against the union of (final CLAUDE.md ∪ all skill bodies): **551 lines
checked, 5 unmatched — and all 5 are file-path pointers I deliberately rewrote to name the skills**
(e.g. `~/.claude/rules/research-subagents.md` → "the research-subagents skill"). No knowledge line is
lost. The two big rule files are byte-identical in their skills (verified).

**2. Deterministic hook triggers — proven by payload injection (auth-free).** The two high-stakes moves
do not rely on fuzzy description-match. `hooks/agent-teams-enforce.sh` (PreToolUse on *every* Agent
spawn) now injects the skill pointer: `team_name` spawn → agent-teams skill; research spawn →
research-subagents skill. Tested by piping sample tool payloads — pointers fire correctly AND the
existing DENY/nudge logic is intact (bg-impl still denied, off-allowlist model still denied, Explore
still silent). `/research` now invokes the research-subagents skill directly.

**3. Graceful-degradation safety property.** Every resident pointer carries the *core directive*, not
just "see skill X". So a trigger-miss degrades to "core-only", never "absent". Example: the
manual-command-delivery pointer states the whole rule; coding-standards names strict-mode /
explicit-return-types / no-render-functions; research keeps decompose-before-count + default N.

**4. Adversarial review (3 independent fresh-eyes reviewers, findings applied).** Verdict:
*"No move is HIGH-risk; every CRITICAL destructive-surface rule stayed fully resident."* Fixes applied:
restored max-6-concurrent + structured-`shutdown_request` to resident (the one CRITICAL section moved
wholesale); restored the "not Playwright" steer; sharpened 6 skill descriptions to cut spurious-fire
and disambiguate collisions with existing skills (plan-update, agent-browser).

**5. Valid-YAML frontmatter.** All 7 skill descriptions converted to folded block scalars
(`description: >-`) so the `": "` in "Triggers:/Rules:/SSOT:" parses under strict YAML — else a strict
loader would silently skip the skills. (Matches your `resume-sessions` pattern.)

## OPEN DECISIONS FOR YOU (flagged, not acted on)

1. **Deploy path.** `install.sh` deploys hooks/commands/skills (symlink) but **not** CLAUDE.md or
   rules/ (both hand-maintained live). Post-approval deploy therefore needs an explicit CLAUDE.md copy
   + rules removal (script ready at `/tmp/deploy-claudemd-lazyload.sh`). **Want me to also extend
   install.sh to deploy CLAUDE.md + rules/, making the repo the true source (kills the live-vs-repo
   drift)?** Separate change; your call.
2. **Union-preserved "Never commit or land in the shared checkout" para.** It lives in the repo
   CLAUDE.md (project-specific to claude-infrastructure) but not in live-global. I kept it (zero loss).
   If you don't want it in the *global* live deploy, say so and I'll scope it out of the live copy.
3. **coding-standards for teammate-authored code.** Teammates write most code but get the agent-teams
   pointer, not coding-standards, and run heads-down on briefs. The 6 conventions are 💡PREFERRED /
   lint-caught and named in the resident pointer, but not enforced in teammate context. Consider adding
   them to the teammate brief template (out of scope here).
4. **research-subagents pre-cognition.** The resident invariant carries the anti-under-spawn core; the
   Agent-spawn hook fires *at* the spawn (slightly late for count-choice). Optional hardening: a
   UserPromptSubmit hook matching research-intent. Not done (invariant suffices); your call.
5. **`rules/research-subagents.md` is gitignored** by `~/.gitignore_global` line 6 `RESEARCH-*.md`
   (accidental macOS case-insensitive match). The skill is tracked fine; the accidental ignore is a
   pre-existing global-config wart worth a one-line fix sometime.

## DEPLOY PLAN (post-approval only — I will NOT self-land the knowledge layer)

1. `/ship` this branch → origin/main (locks, rebases, gates, content-verifies).
2. Update the main checkout to origin/main so the live hook/command symlinks reflect the new content.
3. Run `/tmp/deploy-claudemd-lazyload.sh`: `cp` restructured CLAUDE.md → `~/.claude/CLAUDE.md`; remove
   `~/.claude/rules/{agent-teams,research-subagents}.md`; `install.sh` to symlink the 7 new skills live.
   All 5 config dirs pick it up automatically (they symlink `CLAUDE.md`/`rules`/`skills` → `~/.claude/`).
4. Smoke-check: a fresh session loads 290-line CLAUDE.md, empty rules/, 7 new skills in the list.
