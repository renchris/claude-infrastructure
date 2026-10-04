# Prompt audit — shard skills-a

**Scope:** skills/ entries 1-12 alphabetically: account-relogin, agent-browser (+LICENSE, not prompt text), agent-teams, autonomous-authenticated-web-access, beautiful-mermaid-docs, browsermcp, cc-upgrade (SKILL.md + audit/feature/gate/holds/keying/model/utilize.md), cc-upgrade-gate, cc-version-audit, codex-security (SKILL.md only; vendor/codex-security/ is vendored Apache-2.0 verbatim and marked do-not-edit — skipped), coding-standards, corpus-to-skill. 19 files read.
**Target model:** Opus 5.5 (claude-opus-5-5), the model that reads these skills; no file pins its own model.
**Method:** prompt-audit.md Steps 0-6; provenance by git blame / git log -S; every stale-fact claim checked against repo files (hooks, scripts, model-config.yaml, docs/README-reference.md, tests). Read-only; nothing applied.

## Summary

The highest-impact problems are all in **agent-teams/SKILL.md**, loaded before every teammate spawn: (1) its Shutdown Protocol tells the lead to run `killall -9 tmux` to close a pane, which kills every tmux session on the machine on an iTerm2-backed fleet; (2) it promises the TeammateIdle hook means 'no orphaned panes', which its own vendor-contract section, the reap-alarm test and global CLAUDE.md all refute; (3) its runtime and allowlist facts name deleted launchers (`claude-previous`, `~/.claude-219`) and superseded teammate ids (`claude-opus-4-8`/`claude-fable-5`) while the SSOT routes `claude-opus-5-5` via the `opus` alias. Several sections also carry a claim plus a later retraction instead of a fixed claim (TaskStop, effort, model override).

Smaller: browsermcp and agent-browser still frame the live tool as a 'fallback' to a server retired 2026-08-11, and browsermcp's history section opens with a live imperative to use it; account-relogin's description duplicates /relogin's; coding-standards carries a relocation note.

Counts: Group 1 (dated text) 6 · Group 2 (brittle config: stale facts, conflicts, triggers) 18 · Group 3 (descriptions/trigger) counted in Group 2 (2) · Group 4 not applicable (no request-building code in shard) · cost-lever 1. Flag-only: 1.

**Clean / not flagged:** cc-upgrade (all 8 files — recently consolidated 2026-09-28, names no current version outside holds.md by design); cc-upgrade-gate and cc-version-audit stubs (disable-model-invocation, 6 days into their stated one-cycle life); beautiful-mermaid-docs (dated facts are pinned to an exact-pinned package version with a re-check command); codex-security adapter; corpus-to-skill. Pressure language in account-relogin Hard rules and the agent-teams Shutdown Protocol guards live-session/credential constraints and was kept. Redundant-but-agreeing copies of the 'isolation:/cwd: beside name: demotes' rule (3 copies) are working redundancy (keep-list 8).

## Findings

### skills-a-01 — skills/agent-teams/SKILL.md:470 (high, string-replace)
- **Pattern:** Group 2 volatile specifics (stale fact) + keep-list 3 (fragile op needs an exact, correct command)
- **Why:** The only manual pane-close instruction in the Shutdown Protocol is `killall -9 tmux`, a 2026-06-06-era line (git log -S). It is wrong three ways that this repo itself shows: the pane backend is iTerm2 (it2 / it2-kitty shim), not tmux; `killall` kills every tmux session on the machine, not one pane; and 'agent stays until timeout' contradicts the same file's vendor contract section 1 (no idle timeout exists in the binary). The correct per-pane close is already described at lines 309-312 and in hooks/teammate-auto-shutdown.sh.
- **Impact:** Removes a destructive, machine-wide command from a teardown recipe the model follows under pressure; replaces it with the exact per-pane close the hook itself uses.
- **Old:**
```
5. Kill iTerm2 pane manually if needed: `killall -9 tmux` (pane dies; agent stays until timeout)
```
- **New:**
```
5. Close a pane that outlived its agent by its recorded id: the member's `tmuxPaneId` in the team `config.json`, closed with `it2 session close -f -s <id>` (iTerm2) or `tmux kill-pane -t <id>` (tmux). Never `killall tmux`: it kills every tmux session on the machine, and no idle timeout ever ends the agent (vendor contract § 1).
```

### skills-a-02 — skills/agent-teams/SKILL.md:292 (high, string-replace)
- **Pattern:** Group 2 instruction files that contradict each other (internal + global CLAUDE.md) / stale fact
- **Why:** 'TeammateIdle hook auto-shuts down idle teammates ... No orphaned panes — teammates terminate immediately when they finish work' (2026-07-17) is contradicted by the same file's newer vendor contract section 1 (2026-09-19: idle is not done, only the lead ends a teammate), by the 2026-08-26 measurement in this file (idle members survived 20-40 min), by tests/teammate-reap-alarm.bats (which exists because this path closed zero panes for nine days unnoticed), and by the global CLAUDE.md ('A teammate ends only when its lead ends it'). A model that believes the hook reaps will skip the Shutdown Protocol.
- **Impact:** Stops a false guarantee that licenses skipping teammate teardown (the orphaned-pane failure this repo has measured repeatedly).
- **Old:**
```
**TeammateIdle hook auto-shuts down idle teammates** (`~/.claude/hooks/teammate-auto-shutdown.sh`).
No orphaned panes — teammates terminate immediately when they finish work.
```
- **New:**
```
**The TeammateIdle hook is a backstop, not the teardown** (`~/.claude/hooks/teammate-auto-shutdown.sh`).
It checkpoints an idle teammate's work and closes its pane once the tree is clean (or after 3 defers).
Idle is not done (vendor contract § 1 below), and this path once closed zero panes for nine days
unnoticed (`tests/teammate-reap-alarm.bats`), so the lead still ends every teammate through the
Shutdown Protocol.
```

### skills-a-03 — skills/agent-teams/SKILL.md:314 (high, string-replace)
- **Pattern:** Group 2 volatile specifics — claim the repository contradicts
- **Why:** The skill says a TeammateIdle hook 'runs LEAD-side as lead-claude → /bin/sh -c → bash'. hooks/teammate-auto-shutdown.sh was corrected on 2026-09-19 (RC-7): 'this hook runs INSIDE THE TEAMMATE, not on the lead' — 2,070 of 2,083 PPID-forensic lines in teammate-lifecycle.log show the teammate's own claude.exe as the ancestor. The skill copy was never updated (blame: 2026-07-17).
- **Impact:** Aligns the skill's mechanism with the hook's measured locus, so a model debugging pane closes reasons from the right process tree.
- **Old:**
```
   a TeammateIdle hook runs LEAD-side as `lead-claude → /bin/sh -c → bash`, so
   `$PPID` is the already-dead `/bin/sh` shim — the backgrounded kill hit a
   PID-RECYCLED process (the lead or an unrelated shell). Targeting the recorded
   pane id is deterministic.
```
- **New:**
```
   a TeammateIdle hook runs inside the TEAMMATE's own Stop pass as
   `teammate-claude → /bin/sh -c → bash`, so `$PPID` is that member's already-dead
   `/bin/sh` shim — the backgrounded kill hit a PID-RECYCLED process (an unrelated
   shell or session). Targeting the recorded pane id is deterministic.
```

### skills-a-04 — skills/agent-teams/SKILL.md:12 (high, string-replace)
- **Pattern:** Group 2 volatile specifics (version pins, deleted launcher names) + 1d migration-relative phrasing
- **Why:** The runtime block pins the fleet at 'claude / cc → CC 2.1.219, the ~/.claude-219 binary' and the stable track at 'claude-previous / cc-previous'. docs/README-reference.md records the fleet on 2.1.280 since 2026-09-22 (holds.md indexes a 2.1.284 row) and says the claude-previous*, claude-next* and claude-opus5* names were DELETED in the 2026-08-01 consolidation; the legacy track is `claude-prev`/`cc-prev` (cc-upgrade/audit.md, zshrc-snippet.sh). cc-upgrade's own rule (resident-policy-must-not-restate-perishable-facts) is to name the command that reads the version, not the version.
- **Impact:** Removes three dead launcher names and two stale version pins from a skill loaded before every teammate spawn; points at the live reader instead.
- **Old:**
```
**Two tracks, and BOTH are teams runtimes — they differ only in the team API surface:**
- **Stable** (`claude-previous` / `cc-previous` → CC **2.1.114**, deliberately pinned; these were
  named `claude` / `cc` before the 2026-07-31 entrypoint consolidation): exposes the classic
  **`TeamCreate` / `TeamDelete`** tools that this file's examples use.
- **Eval** (`claude` / `cc` → CC **2.1.219**, the `~/.claude-219` binary; `claude-next` and
  `claude-opus5` are back-compat shims onto the same body): on **2.1.178+**, which
  **removed `TeamCreate` / `TeamDelete`** for an **implicit-team model** — you spawn teammates by
  calling the **`Agent` tool with `name:`** (the runtime forms the team implicitly at STARTUP; the
  `TeamCreate`/`TeamDelete` *tools* simply don't exist). Agent Teams are ENABLED here
  (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`) and **validated working on 2.1.183** (verified
  2026-06-20). The earlier "183 is deliberately not a teams runtime / needs doc-migration first"
  framing is **superseded**. Stable 2.1.114 stays pinned — by *choice*, not by a teams gap.
```
- **New:**
```
**Two tracks, and BOTH are teams runtimes — they differ only in the team API surface.** Read the
versions live (`cc-claude-bin --explain` for the fleet pin); this file names none as current.
- **Fleet** (`claude` / `cc` and every account variant): 2.1.178+, which **removed `TeamCreate` /
  `TeamDelete`** for an **implicit-team model** — you spawn teammates by calling the **`Agent` tool
  with `name:`** (the runtime forms the team implicitly at STARTUP; the `TeamCreate`/`TeamDelete`
  *tools* simply don't exist). Agent Teams are ENABLED here (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`).
  Every instruction below uses this surface.
- **Legacy** (`claude-prev` / `cc-prev` → CC **2.1.114**, deliberately pinned — by *choice*, not by
  a teams gap): exposes the classic **`TeamCreate` / `TeamDelete`** tools.
```

### skills-a-05 — skills/agent-teams/SKILL.md:29 (high, string-replace)
- **Pattern:** Group 2 volatile specifics + History narrative
- **Why:** The '`claude --version` lies' paragraph explains the trap through a dated chain (pre-/post-2026-07-31 consolidation, ~/.claude-219 → 2.1.219, '.claude-183 ⟹ eval/2.1.183', claude-previous) that no longer matches any launcher. The rule itself is live and is stated version-free in cc-upgrade/audit.md Step 0 (2026-09-28), which also ranks `ps -o command= -p $PPID` as the most authoritative reading — a source this paragraph lists last without that ranking.
- **Impact:** Keeps the trap and the detection order, drops four dead identifiers; consistent with cc-upgrade/audit.md Step 0.
- **Old:**
```
The wrong number is not even stable: before the 2026-07-31 entrypoint consolidation `claude`
resolved the stable pin (`~/.claude-versions/current` → 2.1.114) and under-reported inside an
eval-track session; it now resolves the consolidated eval launcher (`~/.claude-219` → 2.1.219)
and **over**-reports inside a stable session. `claude-previous` / `cc-previous` are the stable
2.1.114 names. Identify the actual session by: the `AI_AGENT` env
(`claude-code_2-1-XXX_agent`), `CLAUDE_CODE_EXECPATH` (`.../.claude-183/...` ⟹ eval/2.1.183), the
parent process command, or **tool availability**
```
- **New:**
```
It reports the CURRENT `~/.zshrc` pin, so a pane started before a repoint, or a legacy `claude-prev`
session, gets the wrong number. Identify the actual session by: the parent process command
(`ps -o command= -p $PPID` — the most authoritative), `CLAUDE_CODE_EXECPATH`
(`.../.claude-<NNN>/...`), the `AI_AGENT` env (`claude-code_2-1-XXX_agent`), or **tool availability**
```

### skills-a-06 — skills/agent-teams/SKILL.md:39 (high, string-replace)
- **Pattern:** Group 2 volatile specifics — claim the SSOT contradicts; 1a pressure (MUST) on a stale value
- **Why:** 'The teammate `model` MUST be on the Max auto-mode allowlist (`claude-opus-4-8` / `claude-fable-5`)' names two ids, neither of which is the current teammate model. model-config.yaml auto_mode_allowlist.non_firstParty_max is [claude-opus-4-8, claude-opus-5, claude-opus-5-5, claude-fable-5, claude-fable-5-1], and roles.default_teammate (flipped 2026-09-22) says spawn with the alias `model: opus`. A model reading the skill literally would pin Opus 4.8 or Fable 5. Also 'When on the eval track' names a track that no longer exists under that name.
- **Impact:** Every teammate spawn reads this; it now routes to the SSOT key and the alias the SSOT prescribes instead of two superseded ids.
- **Old:**
```
**When on the eval track:** read every `TeamCreate` / `TeamDelete` example below as the *2.1.114*
surface — do the equivalent via `Agent({ name, model, … })` to spawn + `shutdown_request`
to each teammate to tear down (there is no `TeamDelete` call). The teammate `model` MUST be on the
Max auto-mode allowlist (`claude-opus-4-8` / `claude-fable-5`); a bare background subagent is
hard-blocked from writing code, and `sonnet` silent-demotes to acceptEdits + breaks parallelism
(see `feedback-agent-team-models.md`).
```
- **New:**
```
**On the fleet track:** read any `TeamCreate` / `TeamDelete` mention below as the *2.1.114*
surface — do the equivalent via `Agent({ name, model, … })` to spawn + `shutdown_request`
to each teammate to tear down (there is no `TeamDelete` call). The teammate `model` must be on the
SSOT's `auto_mode_allowlist.non_firstParty_max` (`~/.claude/model-config.yaml`); spawn with the
alias `model: opus` (`roles.default_teammate`). A bare background subagent is
hard-blocked from writing code, and `sonnet` silent-demotes to acceptEdits + breaks parallelism
(see `feedback-agent-team-models.md`).
```

### skills-a-07 — skills/agent-teams/SKILL.md:230 (high, string-replace)
- **Pattern:** Group 2 volatile specifics — claim the SSOT contradicts
- **Why:** Second copy of the stale two-id allowlist ('allowlist: claude-opus-4-8 / claude-fable-5'); the SSOT list has five ids and the routed teammate model is claude-opus-5-5. Same fix as skills-a-06: name the key, not the ids.
- **Impact:** Removes the second stale allowlist copy so the two sections cannot disagree again on the next model bump.
- **Old:**
```
above). Assignees honor `model` (allowlist: `claude-opus-4-8` / `claude-fable-5`).
```
- **New:**
```
above). Assignees honor `model` (allowlist: `auto_mode_allowlist.non_firstParty_max` in the SSOT).
```

### skills-a-09 — skills/agent-teams/SKILL.md:267 (high, string-replace)
- **Pattern:** Group 2 stale facts inside one file (checklist count, dead tool names, completion signal the vendor contract refutes)
- **Why:** The Lifecycle list says 'verify all 6 boxes' but the Pre-Spawn Checklist has 7 (the coding-conventions box was added later); 'TeamCreate' and 'TeamDelete' are not callable on the fleet runtime; and 'lead monitors via TaskList + completion notifications' contradicts vendor contract section 1 (the green 'finished' line fires at every turn boundary) and the SendMessage-only return documented at line 75-79.
- **Impact:** A six-line lifecycle that is now executable on the fleet runtime and no longer treats idle notifications as completion.
- **Old:**
```
2. **Pre-spawn checklist** — verify all 6 boxes (above)
3. **Setup** — Create worktrees manually, TeamCreate, spawn teammates
4. **Execute** — Teammates work, lead monitors via TaskList + completion notifications
5. **Merge** — Sequential cherry-pick for schema-touching work; git merge for independent work
6. **Cleanup** — `shutdown_request` to each teammate, remove worktrees, TeamDelete
```
- **New:**
```
2. **Pre-spawn checklist** — verify every box (above)
3. **Setup** — Create worktrees manually, then spawn each teammate with `Agent({ name, … })`, its worktree path in the brief
4. **Execute** — Teammates work and report via `SendMessage`; lead monitors via TaskList (an idle notification is not completion)
5. **Merge** — Sequential cherry-pick for schema-touching work; git merge for independent work
6. **Cleanup** — harvest reports, run the Shutdown Protocol below (`shutdown_request` → `TaskStop` → ps-verify), then remove worktrees
```

### skills-a-10 — skills/agent-teams/SKILL.md:199 (high, string-replace)
- **Pattern:** 1d patch accretion / migration-relative + Group 2 stale fact (instruction the repo says no longer binds)
- **Why:** The section opens by telling the lead to run set-teammate-effort.sh and closes with 'Run it during Setup ... BEFORE spawn', with a SUPERSEDED callout wedged between them. scripts/set-teammate-effort.sh's own header (2026-09-22) says that on every binary this fleet runs the pane builder passes --effort <lead's level>, which outranks the file, so 'this script does not change it'; model-config.yaml roles.default_teammate says the same. Two of the three paragraphs are imperatives for a mechanism that is dead; the model must reconcile them on every teammate spawn.
- **Impact:** Replaces ~22 lines of contradictory instruction with the one current rule (members inherit the lead's effort; fire a session at the rung) — removes a no-op setup step from every wave.
- **Old:**
```
## Per-Teammate Effort (2026-06-11 — binary-verified mechanism)

Teammate panes launch fresh `claude` processes that re-resolve their worktree's
`.claude/settings.local.json` — the lead's live effort is NOT forwarded. So per-member
effort IS settable, at worktree setup time:

```bash
~/.claude/scripts/set-teammate-effort.sh <worktree> low|medium|high|xhigh
```

> ⚠️ **SUPERSEDED on 2.1.220+, re-read on the 2.1.280 binary 2026-09-22.** The teammate pane
> builder now pushes `--effort <lead's live level>` onto every member's command line (this skill
> already records it for 2.1.220 below), and a CLI flag outranks the worktree settings file this
> script writes. So a member runs at its LEAD's effort, and the script no longer sets it. For a
> different rung, fire that wave's session at the rung (`handoff-fire.sh --effort medium`).
> Opus 5.5 rungs are in `effort_defaults.opus55_*`: anchored-brief coding medium, ambiguous
> multi-file high. The paragraph below is the 2.1.170-era record.

Run it during Setup (after worktree creation, BEFORE spawn). Defaults per SSOT
`effort_defaults`: mechanical/routine → `high`; judgment-dense or `teammate_frontier`
(Fable) members → `xhigh`. Without an override, panes resolve the user-settings floor
(xhigh). `max` is settings-inexpressible (schema cap) — the script rejects it.
```
- **New:**
```
## Per-Teammate Effort

A teammate runs at its LEAD's effort: on 2.1.220+ the pane builder puts `--effort <lead's live
level>` on every member's command line, and that flag outranks any worktree settings file. There is
no per-member override. To run a wave at another rung, fire that wave's own session at it
(`handoff-fire.sh --effort medium`); Opus 5.5 rungs are in `effort_defaults.opus55_*`
(anchored-brief coding medium, ambiguous multi-file high). `scripts/set-teammate-effort.sh` still
writes the worktree file but does not bind on any binary this fleet runs; its header keeps the
2.1.170-era mechanism.
```

### skills-a-18 — skills/browsermcp/SKILL.md:17 (high, string-replace)
- **Pattern:** 1d fossil — imperative for a retired tool inside the skill loaded when browser tools are missing
- **Why:** The historical section opens with the live-reading imperative 'Use BrowserMCP (not Playwright) for browser automation:' followed by an install recipe (`claude mcp add browsermcp ...`). The skill's trigger is exactly the moment a model is confused about browser tools, and the commit that retired the server (47cc3f279) kept this section only as history. Re-framing the lead-in keeps the history and stops it reading as an instruction.
- **Impact:** Prevents a confused session from re-adding a retired port-9009 singleton server; history is preserved.
- **Old:**
```
Use BrowserMCP (not Playwright) for browser automation:
```
- **New:**
```
How the retired server was shaped — none of it is callable or installable now; do not re-add it:
```

### skills-a-19 — skills/browsermcp/SKILL.md:56 (high, string-replace)
- **Pattern:** 1d migration-relative phrasing ('fallback' to a tool that no longer exists)
- **Why:** '### agent-browser (CLI Fallback) / When BrowserMCP unavailable, use agent-browser' frames the only live path as a fallback conditional on a server that is always unavailable (banner line 6; global CLAUDE.md § Browser automation names agent-browser as the tool). It also sits structurally under the '## BrowserMCP (historical ...)' heading.
- **Impact:** The live recipe is presented as the live recipe, outside the historical section.
- **Old:**
```
### agent-browser (CLI Fallback)

When BrowserMCP unavailable, use `agent-browser`:
```
- **New:**
```
## agent-browser (the live path)

Use the `agent-browser` CLI:
```

### skills-a-21 — skills/agent-browser/SKILL.md:3 (high, string-replace)
- **Pattern:** Group 2/3 trigger text conditioned on a retired tool
- **Why:** The description (rides in every request's skill listing) says 'use it when BrowserMCP or other browser MCP tools are unavailable'. BrowserMCP was retired 2026-08-11 and the global CLAUDE.md makes agent-browser the default browser tool, so the condition is always true and only adds doubt about whether some other tool should be preferred. Replaced with the one routing fact that distinguishes it (--cdp to a logged-in browser). 205 chars, under the 250-char listing limit (tests/skill-listing-budget.bats).
- **Impact:** Clearer routing in every session's skill listing; same length.
- **Old:**
```
The live browser tool; use it when BrowserMCP or other browser MCP tools are unavailable.
```
- **New:**
```
The live browser tool; --cdp attaches to an already-running, logged-in browser.
```

### skills-a-22 — skills/agent-browser/SKILL.md:122 (high, string-replace)
- **Pattern:** 1d fossil
- **Why:** 'BrowserMCP unavailable but need existing browser control' — the condition is permanent.
- **Impact:** Removes a reference to a retired tool from the CDP decision list.
- **Old:**
```
- BrowserMCP unavailable but need existing browser control
```
- **New:**
```
- Need control of a browser that is already running
```

### skills-a-08 — skills/agent-teams/SKILL.md:98 (medium, string-replace)
- **Pattern:** Group 2 conflicting instruction files (skill vs global CLAUDE.md) + stale API name
- **Why:** The decision table routes 2+ code tasks to 'Agent Teams (TeamCreate + worktrees)'. TeamCreate does not exist on the fleet runtime (this file, lines 16-21), and the global CLAUDE.md (§ Agent Teams and parallel work, newer) makes a dispatched /handoff session the default locus for an implementation wave, with in-session teammates inside it. The table is the first routing rule a lead reads and it names a tool the lead cannot call.
- **Impact:** The decision rule now names the callable spawn shape and the global default locus, removing a dead tool name from the first table a lead consults.
- **Old:**
```
| Writes/modifies code (2+ tasks) | Agent Teams (TeamCreate + worktrees) |
```
- **New:**
```
| Writes/modifies code (2+ tasks) | Agent Teams: `Agent({ name })` teammates, each in its own worktree — inside the wave's dispatched session by default (CLAUDE.md § Agent Teams and parallel work) |
```

### skills-a-11 — skills/agent-teams/SKILL.md:253 (medium, string-replace)
- **Pattern:** Group 2 contradiction inside one file (older passage vs newer correction) + history narrative + volatile pin
- **Why:** This 2026-07-17/09-04 paragraph ends 'Never trust a bare-subagent model: override to take effect' and pins 'the live launcher claude is 2.1.260'. The newer 2026-08-03 correction 15 lines above (binary-extracted) says both shapes READ the call-time model and fall back only when the id fails the allowlist — so the rule to check is allowlist + registration, not 'never trust'. The fleet is past 2.1.260, and claude-fable-5-1 is now on the allowlist, so research-subagents' call-time model: "fable" is valid where the binary registers it. The 'This sentence used to say...' clause is archaeology.
- **Impact:** Resolves an internal contradiction about whether call-time model overrides work, so frontier research slots are not needlessly rerouted through teammates.
- **Old:**
```
⚠️ This **corrects** the **research-subagents** skill (`~/.claude/skills/research-subagents/SKILL.md`; the old `~/.claude/rules/` location no longer exists), which reads as if
`model: "fable"` on a bare `deep-research` subagent runs on Fable. That holds (if ever)
ONLY on a CC build that registers the frontier model id (≥ 2.1.170; the live launcher
`claude` is 2.1.260) — NOT universally, and NOT on the pinned legacy 2.1.114 path. ⚠️ This
sentence used to say "ONLY on the claude-next eval track", which consolidation v2 deleted:
gate on the BINARY VERSION, which a session can check, never on a launcher name that no
longer exists. Where the override does not take effect, route
non-session-model work through an assignee, or hand off to the desk's external
2-way orchestration (which spawns independent model-pinned CC instances outside the
internal subagent system). Never trust a bare-subagent `model:` override to take effect.
```
- **New:**
```
So the **research-subagents** skill's call-time `model: "fable"` on a bare `deep-research`
subagent runs on Fable only where the binary registers the frontier id (`cc-model-registered
<id>`) and the id passes the allowlist; on the pinned legacy 2.1.114 path it does not. Gate on the
binary and the allowlist, which a session can check, never on a launcher name. Where the override
does not take effect, route non-session-model work through an assignee, or hand off to the desk's
external 2-way orchestration (which spawns independent model-pinned CC instances outside the
internal subagent system). Confirm an override by the spawn's `modelUsage`, not by the call.
```

### skills-a-12 — skills/agent-teams/SKILL.md:390 (medium, string-replace)
- **Pattern:** 1d patch accretion — a later section says 'one sentence just above this one is wrong' instead of fixing it
- **Why:** Line 390 asserts '`TaskStop` is the authoritative actuator'; vendor contract item 3 (2026-09-19, binary read) is headed 'CORRECTION — TaskStop is not the authoritative actuator, and the sentence above overstates it', and the intro at 397-399 flags it again. The model reads both and must reconcile. Fixing the sentence in place lets the correction header and the intro clause go (skills-a-13, skills-a-14; apply the three together).
- **Impact:** One consistent teardown rule (request → TaskStop → ps-verify) instead of a claim plus two downstream retractions.
- **Old:**
```
dies), but it is a request; **`TaskStop` is the authoritative actuator**. A sent request is never a
teardown.
```
- **New:**
```
dies), but it is a request; escalate to `TaskStop`, then ps-verify (vendor contract § 3 below: `TaskStop`
removes the pane and member row but may leave the process). A sent request is never a teardown.
```

### skills-a-13 — skills/agent-teams/SKILL.md:420 (medium, string-replace)
- **Pattern:** 1d patch accretion (companion to skills-a-12)
- **Why:** Once skills-a-12 fixes line 390, the 'CORRECTION ... the sentence above overstates it' header points at a sentence that no longer says that. Restate it as the fact it carries.
- **Impact:** Keeps vendor contract item 3's content; removes a dangling retraction.
- **Plan:** Apply only together with skills-a-12.
- **Old:**
```
**3. CORRECTION — `TaskStop` is not "the authoritative actuator", and the sentence above overstates
it.**
```
- **New:**
```
**3. `TaskStop` removes the pane, not necessarily the process.**
```

### skills-a-14 — skills/agent-teams/SKILL.md:398 (medium, string-replace)
- **Pattern:** 1d patch accretion (companion to skills-a-12)
- **Why:** Same dangling retraction in the vendor-contract intro.
- **Impact:** Removes a pointer to a sentence skills-a-12 fixes.
- **Plan:** Apply only together with skills-a-12.
- **Old:**
```
built, because three of the beliefs the fleet operates on are not in the product, and one sentence
just above this one is wrong.
```
- **New:**
```
built, because three of the beliefs the fleet operates on are not in the product.
```

### skills-a-15 — skills/agent-teams/SKILL.md:493 (medium, string-replace)
- **Pattern:** Group 2 volatile specifics (version-keyed branches) — fleet case listed second and under a stale version
- **Why:** The hang recipe leads with the legacy '(stable 2.1.114)' TeamDelete case and gives the fleet case as 'On the 2.1.183 implicit-team model ... send shutdown_request; if it hangs, kill the pane'. The fleet runs the implicit-team runtime on a much newer binary, and this file's own Shutdown Protocol (steps 3-4) already prescribes TaskStop → pgrep → kill -TERM after a silent shutdown_request. The hang line skips the ps-verify step that the vendor contract says is the only real verdict.
- **Impact:** The hang path matches the Shutdown Protocol and leads with the runtime actually in service.
- **Old:**
```
**If teammate hangs**: (stable 2.1.114) GitHub #31788 — `TeamDelete` can block permanently. Kill pane, manually remove `~/.claude/teams/<team-name>`. Checkpoint refs survive in the worktree's `.git/` — run `git for-each-ref refs/wip/<member>/LAST` to recover. On the 2.1.183 implicit-team model there is no `TeamDelete` — send `shutdown_request`; if it hangs, kill the pane + `git worktree remove`.
```
- **New:**
```
**If teammate hangs**: on the fleet's implicit-team runtime there is no `TeamDelete` — run the Shutdown Protocol above (`shutdown_request` → `TaskStop` → `pgrep -f "agent-id <name>@"` → `kill -TERM <pid>`), then `git worktree remove`. Checkpoint refs survive in the worktree's `.git/` — run `git for-each-ref refs/wip/<member>/LAST` to recover. Legacy 2.1.114 only: GitHub #31788 — `TeamDelete` can block permanently; kill the pane and remove `~/.claude/teams/<team-name>` by hand.
```

### skills-a-16 — skills/agent-teams/SKILL.md:138 (medium, string-replace)
- **Pattern:** cost-optimization / prompt-caching — rationale misstates how a brief is billed
- **Why:** Rule 1's reason ('Each brief line is processed at uncached rate') is wrong after the first turn: a teammate's brief is the first user message of its session, written to the prompt cache once and then read from cache (0.1x base input) on every later turn (prompt-caching.md). The real cost is context occupancy for the whole run, which is what the 'Why an Assignee' section says actually crashes teammates. The 150-line cap itself is hook-enforced (agent-teams-enforce.sh) and stays; only the reason is corrected.
- **Impact:** Correct cost model in the one rule that sizes every teammate brief; no behavior change to the cap.
- **Old:**
```
Each brief line is processed at uncached rate. 250-line brief = ~5K tokens before any
work. 100-line brief = ~2K. Cap brief at 150 lines.
```
- **New:**
```
A 250-line brief is ~5K tokens of the teammate's context before any work, held (and re-read from
cache) for its whole run; 100 lines is ~2K. Cap brief at 150 lines.
```

### skills-a-17 — skills/agent-teams/SKILL.md:197 (medium, string-replace)
- **Pattern:** 1d migration-relative phrasing
- **Why:** 'Brief length (NEW)' is a diff marker against an older table the model never saw.
- **Impact:** Trivial; removes a phantom-alternative marker.
- **Old:**
```
| Brief length (NEW) | ≤150 lines |
```
- **New:**
```
| Brief length | ≤150 lines |
```

### skills-a-20 — skills/browsermcp/SKILL.md:72 (medium, string-replace)
- **Pattern:** structure (companion to skills-a-19)
- **Why:** After skills-a-19 promotes agent-browser to a level-2 heading, the Vercel knowledge-skill index would nest under it; it is its own topic (global CLAUDE.md says this skill indexes those two skills).
- **Impact:** Heading hierarchy matches content.
- **Plan:** Apply together with skills-a-19.
- **Old:**
```
### Vercel Agent Skills (Knowledge-Based)
```
- **New:**
```
## Vercel Agent Skills (Knowledge-Based)
```

### skills-a-23 — skills/account-relogin/SKILL.md:3 (medium, string-replace)
- **Pattern:** Group 2 trigger-case overlap / Group 3 near-duplicate entries
- **Why:** account-relogin's description is near-identical to the /relogin command's ('Re-authenticate a logged-out Claude Max account ... headless refresh grant ... unattended OAuth in its own auth-browser profile'), and both trigger on logged-out / token-invalid. commands/relogin.md says the skill is 'the reference for the manual and fallback paths' and the skill body itself says 'Try the automated ladder FIRST: cc-relogin'. With equal descriptions the model can load the 9 KB runbook instead of running /relogin. The rewrite routes by intent. 216 chars.
- **Impact:** Routes the common case to the executable /relogin and the runbook only to its fallback cases; avoids loading ~2.4K tokens of runbook when one command suffices.
- **Old:**
```
Re-authenticate a logged-out Claude Max account (next/next2/next3/next4): headless refresh grant first, then unattended OAuth in its own auth-browser profile, then the Outlook email-code fallback. Use on logged-out, token-invalid or \"Not logged in\".
```
- **New:**
```
Manual and fallback runbook behind /relogin (cc-relogin) for a logged-out Claude Max account: the email-code leg when cc-relogin exits 6, the hand-driven Dia OAuth route, and what each phase does. Run /relogin first.
```

### skills-a-24 — skills/autonomous-authenticated-web-access/SKILL.md:46 (medium, operator-decision)
- **Pattern:** Group 2 conflicting instruction files where one side is a safety rule — flag only
- **Why:** The skill says a curl-egress gate 'that inspects Bash commands starting with curl does not fire on a script invocation — this is the sanctioned operator-script path, not a bypass'. The global CLAUDE.md says a refusal is an answer and must not be re-issued 'through another path'. hooks/curl-gate-scope.sh fronts a curl-gate.py scoped to one project (reso-management-app), so in most repos nothing fires either way; but where it does, this line teaches routing around the gate's matcher. Per the guide, a conflict that touches a prohibition is flagged, not rewritten; a proposed wording is given for the operator.
- **Impact:** Removes a sentence that reads as gate-evasion guidance; the script-for-repeatability advice stays.
- **Plan:** Operator decides whether the script path is a sanctioned exemption from curl-gate (then say so in the gate, not the skill) or whether the skill should stop describing the matcher gap. Proposed text given.
- **Old:**
```
A curl-egress gate that inspects Bash
  commands *starting with* `curl` does not fire on a script invocation — this is the
  sanctioned operator-script path, not a bypass (the calls are still read-only and the
  token is user-authorized). It also makes the pull atomic, logged, and re-runnable.
```
- **New:**
```
It makes the pull atomic, logged, and re-runnable.
  If a hook refuses a call, that refusal stands; do not re-route the same call through a script.
```

### skills-a-25 — skills/coding-standards/SKILL.md:6 (medium, string-replace)
- **Pattern:** 1d migration-relative phrasing
- **Why:** '## Code Style & Stack Conventions (relocated from global CLAUDE.md)' is a note about where the text used to live (2026-07-17 relocation); the model never saw the old location. It is also a level-2 heading with no level-1 above it.
- **Impact:** Trivial; removes a provenance aside from a skill teammates are told to embed.
- **Old:**
```
## Code Style & Stack Conventions (relocated from global CLAUDE.md)
```
- **New:**
```
# Code Style & Stack Conventions
```

## Not proposed (report only)

- browsermcp: deleting the whole historical BrowserMCP section (lines 15-54) is defensible under 'history narratives', but commit 47cc3f279 deliberately kept it and tests/deploy-parity.bats:1745 cites it; skills-a-18 neutralises the live-reading imperative instead.
- autonomous-authenticated-web-access 'Do NOT' list restates techniques 1-4 — a deliberate end recap (keep-list 10).
- coding-standards `bun.lockb → bun` omits Bun 1.2's text `bun.lock`; low, model infers.
- account-relogin Phase 2b 'its token cache currently covers ONE mailbox' is a perishable 'currently' fact; unverifiable from the repo (outside-project path).