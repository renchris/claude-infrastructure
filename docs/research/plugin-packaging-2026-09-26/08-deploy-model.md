# 08 — Should claude-infrastructure's OWN ~/.claude deployment become a plugin?

**Verdict: STAY on the symlink farm + deploy-live.sh + migrations. Do not move wholesale, and no partial move pays for itself today.** Of the two plugin modes, in-place (a local-directory marketplace) gives the same live-edit behaviour and adds nothing. Cached (a GitHub or git marketplace) adds one real thing, an atomic, versioned activation point. But it splits versions between plugin hooks and the `~/.claude`-anchored libs, bins and scripts, which must stay symlinked either way. In both modes every skill and agent gets a new name. Plugin `hooks.json` also turns "landing code" into "activating a hook", and the repo's C10 governance explicitly has not ratified that change.

Evidence base: repo at `7dd2e1035`; live binary 2.1.280 (`cc-claude-bin --explain`); docs at code.claude.com (`/docs/en/plugin-marketplaces`, `/docs/en/plugins/loading`, `/docs/en/plugins/components`, `/docs/en/hooks`, `/docs/en/skills`); plugin CLI `--help` on 2.1.280. No marketplace was added and nothing was installed.

---

## Key answers (brief §4)

**(a) Local directory marketplace: copied or referenced in place?** In place, for relative-path plugins.
- Docs (loading § "In-place and copied plugins"): *"Relative-path plugins in a marketplace you added from a local directory: the plugin loads in place from its path inside the marketplace folder. Your edits to the source directory take effect at the next session start or `/reload-plugins`, and you don't need to increase the version."* `CLAUDE_PLUGIN_ROOT` points at the source directory.
- Docs (plugin-marketplaces § "Test an edit to a plugin"): these are the same semantics. *"People who install from your hosted marketplace get a copy in the plugin cache instead."*
- Docs (loading § "Find plugins on disk"): *"A marketplace added from a local `file` or `directory` source has no copy [under marketplaces/], and its `installLocation` … is the path you gave."*
- Versioning becomes inert: *"A plugin loaded in place from a local-directory marketplace loads its current source files at every session start, whatever its version string says."*
- **So the live-edit loop is mostly preserved, with one small regression.** Hook script bodies are exec'd from the source path, so edits to them stay live. SKILL.md text stays live-watched. Changes to `hooks/hooks.json` registrations, `agents/` and MCP need `/reload-plugins` or a new session (skills doc § "Live change detection"). Today, hook registrations in settings.json are picked up live by the settings file watcher (hooks doc).
- Other in-place routes: `--plugin-dir`, `CLAUDE_CODE_PLUGIN_DIRS` (loads as `@inline`), and skills-directory plugins (`~/.claude/skills/<name>/.claude-plugin/plugin.json` → `<name>@skills-dir`; `claude plugin init` has scaffolded this since 2.1.157, per `~/.claude/cache/changelog.md:3172`). All three are *"never copied."*

**(b) Overrides, duplicates and namespacing.**
- Plugin skills never override user skills. They sit in a separate namespace, so **both load**:
  - `/<plugin>:<dir>` for skills (components § Skills).
  - `<plugin>:<name>` for agents (components § Agents).
- Hooks do not dedupe across the plugin boundary: *"If you define the same handler in more than one settings file, it runs once. A plugin's or skill's copy of the same handler stays separate"* (hooks doc). A partial move that leaves the settings.json entry in place **double-fires** every moved hook, for example validate-bash or the Stop hooks.
- These places depend on bare names and would break or need rewrites:
  - `hooks/agent-teams-enforce.sh:620` (`deep-research|deep-research-sonnet|Explore|frontier-derivation`) and `:687` (`…|research-decomposition-critic`) case-match on bare `subagent_type`.
  - `scripts/tokeff-lean-readout.sh:66` matches `agent_type == "workflow-lean"`.
  - The live allow rules `Skill(agent-browser)` and `Skill(less-permission-prompts)` would have to become `Skill(<plugin>:agent-browser)` (skills doc § permission rules).
  - 167 files in hooks/, scripts/ and bin/ mention slash names such as `/ship`, `/wrap`, `/handoff` and `/recover`.
  - Those names are also the operator's muscle memory.
- Name-conflict precedence *between plugins* (loading § "Name conflicts"): `--plugin-dir` > installed marketplace > skills-dir > synced. That precedence does not apply between a plugin and user-level skills.

**(c) Is plugin state per CLAUDE_CONFIG_DIR?** By design yes, but this fleet deliberately shares it.
- Plugins root is `<config dir>/plugins` unless `CLAUDE_CODE_PLUGIN_CACHE_DIR` is set (loading § "Find plugins on disk"). Proof: `~/.claude/plugins/installed_plugins.json` records `installPath: /Users/chrisren/.claude-secondary/plugins/cache/claude-plugins-official/security-guidance/2.0.8`, a path written through the installing account's alias.
- All four account dirs symlink `plugins → ~/.claude/plugins` (`ls -la ~/.claude-{next,secondary,tertiary,quaternary}/plugins`), created by `lib/config-mirror.zsh`, whose isolate set (`:38-42`) does not include `plugins`. So one install serves all four accounts.
- **Enablement is not shared the same way.** It lives in `settings.json` `enabledPlugins`, and `claude plugin marketplace add` writes `extraKnownMarketplaces` into the *invoking* dir's user settings (loading § "Check which stage…").
  - Today `~/.claude-secondary/settings.json` is a symlink to `~/.claude/settings.json`.
  - `~/.claude-next/settings.json` and `~/.claude-quaternary/settings.json` are real files; quaternary differs at byte 43,202. Migration 0037 was meant to unify them (`migrations/README.md` rule 7).
  - So a plugin enable or disable would diverge per account, which is exactly the drift class `cc-settings-parity` exists to catch.
- Isolation hazard: `plugins/synced/` holds claude.ai-synced plugins, which are per claude.ai account (loading § "Plugins synced from claude.ai"). The shared `plugins/` dir already mixes four accounts' sync state. This is pre-existing and independent of this decision, but it is an unexamined consequence of the mirror.

**(d) What the tests and parity auditors assume.**
- Corpus: 759 bats files and 15,752 `@test` (grep count). 51 files invoke `install.sh`. 54 reference `~/.claude/{skills,hooks,agents,commands}` or `CC_CLAUDE_DIR`. 126 use `readlink`, `-L` or `ln -s`.
- `scripts/deploy-parity-assert.sh:531-600` derives a want-list from `git ls-files -- hooks commands scripts bin skills agents lib vendor …`. It demands `want=1` for `hooks/*.sh|*.py`, `hooks/lib/*.sh`, `commands/*.md`, `agents/*.md` and `skills/**`, and emits `MISSING: ln -sf <src> <dest>` for each gap.
- `scripts/deploy-live.sh:1500` (`link_refresh`) consumes exactly that line shape to self-heal.
- `tests/deploy-parity.bats:236` pins "all seven install.sh-linked classes are asserted", and `:715` pins "every SYMLINK class install.sh globs is asserted — one RED per class".
- Moving any class into a plugin means changing install.sh, the assert, link_refresh, `deploy-link-parity.sh` (its STRAY leg reads `config/live-only.manifest`) and those tests in one diff. Otherwise the auditors convict the live layer for obeying the new design. The repo has paid for that exact failure before (`config/live-only.manifest:16-17`, "sibling-auditors-must-share-the-state-model").

---

## Mechanism comparison

| Axis | Today: symlink farm + deploy-live.sh + migrations | Plugin, in place (local-dir marketplace or `CLAUDE_CODE_PLUGIN_DIRS`) | Plugin, cached (GitHub or git marketplace) |
|---|---|---|---|
| **Live-edit loop** | Per-file symlinks into the primary checkout (`install.sh:198-217` `link_file`). Hook bodies are read at exec. Skills are live-watched (skills doc). Settings hooks are file-watched (hooks doc). Every checkout mutation is instantly live (`deploy-live.sh:66-67`: "~/.claude is per-file symlinks, so every land does"). | Same for hook bodies and SKILL.md. `hooks.json`, agents and MCP need `/reload-plugins` or restart (skills doc § live change; marketplaces § Test an edit). Slight regression. | **Lost.** A copy lives in `cache/<mkt>/<plugin>/<version>/`, and edits reach sessions only after `claude plugin update` ("restart required to apply", CLI help) plus reload. |
| **Update** | `deploy-live.sh` fast-forwards to a stamped target through tiers T1/T1H/T2/T3 (`:55-80`), then runs `install.sh` (idempotent) and `deploy-migrations.sh`. The launchd converger runs every 600 s (`migrations/README.md` rule 3). | Nothing to update, because the source is live. The version string is ignored (loading § Versions). | Version resolution is manifest `version` > entry `version` > source SHA (12 chars) (loading § "How Claude Code computes the version"). Auto-update is **off** by default for non-Anthropic marketplaces. |
| **Rollback** | None built in. The script "never rolls back" (`deploy-live.sh:99,1230`); rollback is an operator `git` decision. | Same as today: git. | Pin the entry's `ref` or `sha` and update. The previous version dir gets `.orphaned_at` and is removed 14 days later, so running sessions keep the old copy (loading § Cleanup). **This is the one structural gain.** |
| **Gating / tests before activation** | The gate is on the ff target (green stamp by tree SHA, `deploy-live.sh:47`). `install.sh` refuses a worktree or behind-trunk source (`install.sh:38-132`). The gate is porous by construction: any write to the checkout is live. | No gate. Identical porosity. | A real gate: nothing activates until an explicit `plugin update`, which deploy-live could issue only on green. But the gate covers only the plugin half (next row). |
| **Version coherence** | One tree: hooks, `hooks/lib`, scripts and bin all resolve into the same checkout. | Coherent, because both halves point into the same checkout. | **Split.** Hooks would run from `cache/<sha>/` while sourcing `"${CC_CLAUDE_DIR:-$HOME/.claude}/hooks/lib/…"`: 61 `$HOME/.claude/` refs and 47 `${CC_CLAUDE_DIR:-$HOME/.claude}` refs across 34 hook files. 47 hook files call `cc-*` bins that stay symlinked to the checkout. Mixed-version hook + lib is a new failure class. |
| **Per-account config dirs** | `config-mirror.zsh` symlinks all but the isolate set. `install.sh --config-dir` preserves mirror links (`install.sh:247-285`). | Shared through the `plugins/` mirror link. `enabledPlugins` and `extraKnownMarketplaces` must be present in each forked settings.json (next and quaternary are real files today). | Same as in place, plus a cache shared by all four accounts. |
| **settings.json hook registration** | 78-hook template (`settings-templates/settings.example.json`) additively merged (`install.sh:1215-1320`). The live file has 105 hooks, all `type: command`: 94 by `~/.claude/hooks` path, 8 by absolute `/Users/...` path. 26 of 45 migrations touch `.hooks`, 14 of them hooks-only. | `hooks/hooks.json` in settings shape, registered on load (components § Hooks). Could absorb about 14-26 registration migrations. Double-fires during any overlap with settings entries (hooks doc dedupe rule). | Same as in place. |
| **Governance (C10)** | 44 of 45 migrations are `c10`: staged, never auto-run, because settings.json is operator-owned. The rescope "operator runs → operator can revert" is **unratified** (`migrations/README.md` § The two classes). | A landed `hooks.json` edit activates at the next session start. Hook activation escapes C10 unless the plugin *enable* itself is the c10 step, and that step runs once, not per hook. | Activation is bound to `plugin update`, which could be made c10, but then every hook change waits on the operator: today's inert-queue problem at a coarser grain. |
| **Hook ordering** | The template claims the Stop "chain order matters" (`settings.example.json:447`; `install.sh:1267`). | No change. Per the docs, **all matching hooks already run in parallel**, so the claimed order is not honoured by the harness today either (separate finding, below). | Same. |
| **Permissions / env / statusLine** | settings.json: deny/ask union (allow excluded by design, `install.sh:1219-1231`), 9 env keys, and `statusLine` → `~/.claude/statusline.sh`. | **Cannot move.** Plugin `settings.json` honours only `agent` and `subagentStatusLine`; *"every other key is dropped"* (components § Default settings). | Same. |
| **Names** | Bare: `/ship`, `deep-research`, `Skill(agent-browser)`. | `/<plugin>:ship`, `<plugin>:deep-research` (components § Skills, § Agents). 2+ hook case-arms, 1 readout script, 2 allow rules and 167 prose-bearing files are affected. | Same. |
| **Agents** | 5 agents. Fields used: `model`, `omitClaudeMd`, `maxTurns`, `tools`. | Every one of those fields is supported in plugin agents. The ignored fields (`permissionMode`, `hooks`, `mcpServers`, `initialPrompt`) are unused here, so no loss beyond the rename. | Same. |
| **State dirs** | Hooks write under `${CC_CLAUDE_DIR:-$HOME/.claude}/…` (autonomy, cc-registry, tasks). The mirror shares or isolates these per account. | Unchanged unless moved. `${CLAUDE_PLUGIN_DATA}` = `~/.claude/plugins/data/<id>/`, **deleted on uninstall** unless `--keep-data` (CLI help; components § path vars). | `${CLAUDE_PLUGIN_ROOT}` changes on every version: *"Don't write state there."* |
| **Migrations** | `scripts/deploy-migrations.sh` runs them at converge: ledgered, lexical order, `migration-verify` oracles. | The hooks-only subset could collapse. launchd (17), env (3), permissions and the other settings keys stay. The mechanism survives. | Same. |
| **Uninstall** | No uninstaller. `orphan_prune` removes only already-dead links (`deploy-live.sh:1453`). | `claude plugin uninstall` / `marketplace remove` (the latter uninstalls its plugins). Clean, but only for the plugin-carried share. | Same. |
| **Surface a plugin cannot carry** | n/a | `bin/` (122 files): plugin `bin/` is on the **Bash tool's** PATH only, *after* the user PATH (components § Executables), not on zsh or launchd PATH. `scripts/` (348), `lib/` (21, sourced by `~/.zshrc`), launchd plists, `CLAUDE.md` (*"Claude Code doesn't load a CLAUDE.md at the plugin root"*), statusline, and the 16 live-only skills (`ls ~/.claude/skills` 55 vs repo 39). | Same. |
| **Binary coupling** | Symlinks are binary-agnostic. | Plugin loading semantics keep moving: `--plugin-dir` folders in 2.1.265, command sources in 2.1.229, skills-dir init in 2.1.157, plus a string of plugin-hook fixes ("silently dropped when two plugins use the same `${CLAUDE_PLUGIN_ROOT}` template", "WorktreeCreate plugin hooks silently ignored", "uninstalled plugin hooks continuing to fire"; `~/.claude/cache/changelog.md:4783,5247,5276`). The fleet pins binaries (`claude-latest` stays on 2.1.114; the live panes run 2.1.280), so plugin behaviour becomes one more cc-upgrade-gate axis. | Same. |
| **Tests / auditors** | 15,752 tests; the parity assert and link_refresh are built on the `ln -sf` model. | Requires a coordinated re-model of install.sh, the assert, link_refresh, link-parity, `deploy-parity.bats:236,715` and 51 install-invoking suites. | Same, plus new "cache version == green SHA" assertions. |

---

## Verdict

**Stay.** The deploy spine should not move, and no partial move clears its own cost today.

**Strongest reason to move.** A cached, SHA-pinned plugin is the only mechanism here that gives **atomic, versioned activation with old-version retention**.
- Today, `~/.claude` is live from whatever bytes sit in the checkout. deploy-live.sh's own header concedes that every land advances the live layer outside the green gate (`deploy-live.sh:66-67`).
- `plugin update` issued only on a green stamp, with a 14-day orphan window for running sessions, would close that hole for whatever the plugin carries.
- A `hooks.json` shipped in the same diff as its hook would also do natively what the migrations system does by hand: "registration state that lands in the same diff as its subject" (`migrations/README.md` § 1).

**Strongest reason to stay.** Neither mode delivers that gain without a larger loss.
- **In place** has no gate at all. It is the symlink farm with every skill and agent renamed (`/infra:ship`, `infra:deep-research`) and hook registration moved out of the file-watched settings.json.
- **Cached** gates only the prompt, hook and agent half. The hooks it gates source libs and call 122 `cc-*` tools and 348 scripts that must stay symlinked into the checkout, because plugin `bin/` is not on zsh or launchd PATH and plugins cannot carry permissions, env, statusLine, CLAUDE.md or launchd. That trades today's single-tree coherence for a new mixed-version failure class.
- Both modes keep install.sh, deploy-live.sh and most migrations. The result is **two** deploy mechanisms plus an auditor re-model across 51+ suites.
- Both modes let a landed `hooks.json` activate hooks without the c10 step the operator has deliberately not delegated.

**Ruled out:**
- *Whole-repo plugin.* The repo root already has plugin-shaped `skills/`, `commands/`, `agents/` and `hooks/`. But root `bin/` would put 122 tools on the Bash-tool PATH a second time, and the non-carriable surface keeps install.sh alive anyway.
- *Skills-dir plugin* (`~/.claude/skills/<x>/.claude-plugin`). It is in place, so no gating gain, and its skills get namespaced too.
- *`CLAUDE_CODE_PLUGIN_DIRS` / `--plugin-dir` pointing at the checkout.* In place again, with the highest shadowing precedence (loading § Name conflicts). Untested whether a settings `env` value is read early enough; a `~/.zshrc` export would be.
- *Converting the vendored content only* (`vendor/codex-security`, `vendor/uidotsh`). Plausible later, since it is third-party, wholesale-replaced and already dir-symlinked (`install.sh:888-911`). But it has no `.claude-plugin/` today, and moving it changes its skill names for no gating benefit.

**If the gating gap is what matters**, fix it inside the current model. deploy-live.sh could deploy from a green-SHA **snapshot directory** (for example a `git worktree` at the stamped tree that `install.sh` targets) instead of from the mutable primary checkout. That delivers the cached-plugin property (atomic, versioned, old tree retained) for *all* surfaces, bin and scripts included, with no renames and no C10 bypass. This direction is inferred and has not been tested. Note that `install.sh:38-107` currently refuses linked-worktree sources, and why: the refusal would need a deliberate carve-out for an immutable, GC-exempt snapshot.

---

## Adversarial pass (integrated above; residuals listed)

- **"Plugin hooks lose the Stop-chain order."** Checked and wrong in both directions. The hooks doc says *"All matching hooks run in parallel,"* so the ordering that `settings.example.json:447` and `install.sh:1267` call load-bearing is not honoured by the harness today either. Ordering is therefore not a differentiator. It is a **separate latent finding for the repo**: a correctness claim resting on an order the runtime does not guarantee.
- **"Local marketplace = copy, so live edit dies."** Checked: false for relative-path entries in a local-dir marketplace (loading § In-place). It is true only for GitHub, git and remote sources.
- **"Plugin state is isolated per account, so four installs are needed."** Checked: the fleet already shares `plugins/` through mirror links. The real per-account hazard is `enabledPlugins` in the forked settings.json files (next and quaternary are real files today).
- **Residual unknowns (not tested, per the brief's no-install boundary):**
  - Whether a skills-dir entry that is itself a *symlink* into the repo loads, or trips "symlink that leads outside the plugin" (loading § Paths that escape).
  - Whether CC's own writes to settings.json (`plugin enable`, `marketplace add`) replace a symlinked settings.json with a real file. Both forked accounts' files carry a 01:21 mtime today, which suggests something rewrites them.
  - The exact plugin-root path when `CLAUDE_CONFIG_DIR` is set (inferred from the `installPath` evidence, not from docs text).
