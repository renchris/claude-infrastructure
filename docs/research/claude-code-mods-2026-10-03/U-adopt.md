# U-adopt: what it costs this fleet to run a mod

M = measured, D = documented, I = inferred. Bin289 = /tmp/mods-research/pkg/package/claude, from `npm pack` of the darwin-arm64 2.1.289 package; nothing was installed. Probes ran against scratch HOMEs (/tmp/mods-research/scratch-home-U*).

## Verdict
Running a mod costs one gated binary move plus one way of delivering it. There is no settings.json edit if the plugin path goes in through the launcher's environment. Plugin state is already shared across all four accounts, so every delivery option is one action, not four (M: `ls -la ~/.claude-*/settings.json ~/.claude-*/plugins`. In next, secondary, tertiary and quaternary both are symlinks into ~/.claude.)

## 1. Upgrade 2.1.284 to 2.1.289 or later
- Pin: `cc-claude-bin --explain` resolves to ~/.claude-284 through the `_bin` line at ~/.zshrc:502 (M). npm tags today: stable=2.1.285, latest=next=2.1.289. 2.1.287 was published 2026-10-01T16:59Z and 2.1.289 on 2026-10-03T20:12Z (M: `npm view … dist-tags time`).
- **No HOLD is recorded for 2.1.285 or later.** Grepping the repo and MANIFEST.jsonl for `2.1.28[5-9]` returns nothing (M). The standing REVISIT row is the 2.1.284 one (holds.md reader, M). Its triggers are a spawn-cap fix, or any held issue closing COMPLETED.
- Held issues: #84974, #85264, #85015, #84224, #85764, #97888, #97763 and #97687 are all still OPEN. #85497 closed NOT_PLANNED on 2026-10-03, which does not discharge it (M: `gh issue view`). None of these blocks the move, because the 2.1.284 flip already advanced over them.
- **Gate (owner: agent).** cc-upgrade P2-P8 (SKILL.md §3): CHANGELOG audit; `npm install --prefix ~/.claude-289`; `scripts/cc-upgrade-gate.sh <bin> <opus_latest> next next2 next3 next4`, which runs 15 headless checks where any RED means PARK (gate.md:103-124); an activation script that moves the `_bin` line; a MANIFEST row. A new pin turns the `tests/cc-claude-bin.bats` ratchet red (invariant 5). Adopting a feature also requires a `check16_<feature>.sh` (gate.md:140-145).
- **Operator call.** 2.1.289 is under 1 day old against the ≥7 d churn bar (MANIFEST 2.1.284 row). Overriding that bar is the operator's call, as it was for 2.1.280 and 2.1.284.
- **Take 2.1.289, not 2.1.287** (D, /tmp/mods-research/CHANGELOG.md). It fixes "installed mods not loading in the first session after an upgrade" (L11), "supervised and background sessions ending when a plugin's on-screen handler threw" (L16), and a launch freeze plus an "unrecoverable interface error" caused by plugin UI (L15, L22).
- CHANGELOG risks, 2.1.285 to 2.1.289 (D, CHANGELOG.md line numbers):
  - No spawn cap is restored in L1-463 (M: grep). Keep `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1`.
  - L91 (2.1.288): PreToolUse and PermissionRequest hooks whose matching fails now **block** the call. The fleet has about 98 hooks; gate checks #10 and #11 cover this.
  - L207 (2.1.287): allow rules and allowing hooks now *prompt* for shell writes to the host credentials file. That is a hang risk for unattended relogin tooling, so audit it.
  - L411 and L109: background Bash is killed after 30 min, but only in unattended (`-p`) sessions.
  - L110: the auto-mode classifier ignores a 5.5 `ANTHROPIC_DEFAULT_SONNET_MODEL` pin.
  - L204 (symlink writes wait for a person): low risk, since the repo has 0 committed symlinks (M).
- **There is an early-access path on 2.1.284.** Its binary gates installed-plugin mods behind `CLAUDE_CODE_ENABLE_FUNCTION_HOOKS=1` (M: `strings`). `plugin test` passes with the variable set and fails without it (M: rc 0 vs rc 1; /tmp/mods-research/U-284-test-*.txt). Session loading on 2.1.284 was not measured. Not recommended: it predates GA and lacks the fixes above.

## 2. Plugin install mechanics per account
- **Today (M):** settings.json has `enabledPlugins = {swift-lsp…: false}`, no `extraKnownMarketplaces`, no `disableAllHooks`, and `teammateMode: iterm2`. The only marketplace is `claude-plugins-official`. All four accounts share this state.
- **Repo (M):** there is no `plugins/` or `mods/` directory. install.sh's `vendor/*` dir-symlink leg (install.sh:927-950) is the pattern to copy as `mods/*` → `~/.claude/mods/<name>`. **Do not name it `plugins/`:** `~/.claude/plugins` is Claude Code's own state directory.
- **Three delivery options:**

| Option | settings.json edit? | Notes |
|---|---|---|
| A. `export CLAUDE_CODE_PLUGIN_DIRS=~/.claude/mods/<name>` in the `claude()` launcher, beside the SPAWN_DEPTH export (~/.zshrc:490) | **No** | It is an env var read at preAction (M: strings-289 "preAction: CLAUDE_CODE_PLUGIN_DIRS inline plugins"). A `-p` probe loaded the mod (M, §3). The plugin loads live from its path, with no cache copy and no install record. The zshrc edit goes through the activation-script or zshrc-snippet path. Teammate reach is unverified. |
| B. Put `env.CLAUDE_CODE_PLUGIN_DIRS` in settings.json | **Yes: c10, operator-run** | migrations/README.md:70-77 and rule 7 (write once, through the real path). The binary names this placement itself (M: "in the settings `env` block that sets it"). Reaches every process on the config, including teammates (I). |
| C. Local marketplace (`mods/.claude-plugin/marketplace.json`), then `claude plugin marketplace add` and `plugin install --scope user` | **Yes:** install writes `enabledPlugins` (I: blog Step 6 plus the existing key) → c10 | Copies the plugin into the cache, so each repo change needs `plugin update`. 2.1.289 L10 fixed a stale-copy bug in exactly this path. Installed mods are also gated by the server rollout flag `tengu_plugin_hooks_modules` (M: strings-289 "installed plugins' hooks modules not loaded: rollout flag (… ) is off"). This option has the most moving parts. |

- `claude plugin install` and `marketplace add` were **not** run, as the brief forbids.

## 3. Do mods load in headless runs, teammates and subagents?
- **`claude -p`: yes (M).** A marker mod (/tmp/mods-research/probe/umark) loaded under Bin289 through both `--plugin-dir` and `CLAUDE_CODE_PLUGIN_DIRS`. `session.start` wrote `{"surface":null,"isInteractive":false}` before the run failed with "Not logged in", and the debug log shows `hooks module umark@inline loaded`. In `-p`, UI draws nowhere (D: upstream claude-code.d.ts:9188). Fleet fires are REPL panes started by the launcher (~/.zshrc:504-506), so UI would render there (I).
- **Subagents: yes, in-process.** Events carry `e.agentId` (D: d.ts:156-173; blog L196). The 2.1.288 entry at L57 fixes "a plugin's `tool.call` hook making Bash fail … in subagents that run in a worktree", which implies hooks fire in subagents. Not measured live.
- **Teammates: unverified.** With `teammateMode: iterm2`, teammates are separate processes. Under options B and C they load from the shared config (I). Under option A they load only if the teammate process inherits the variable, which is not determinable from strings. 2.1.289 L21 adds `agent.spawn` for teammates.
- **Mods are switched off by** `--bare`, safe mode, `disableAllHooks`, managed-hooks-only, and (for installed plugins) the rollout flag (M: strings-289:141392-141400, 203800-203806). The fleet uses none of the first four (M: grep).

## 4. Testing inside the bats land gate
- **No auth needed (M).** With an empty scratch HOME and no credentials or keychain item, `plugin validate ./tw` returned rc 0 in 0.22 s and `plugin test ./tw` returned rc 0 in 0.53 s (`/usr/bin/time -p`, two runs; probe at /tmp/mods-research/probe/tw). `validate --strict` exists for CI. On 2.1.284, `test` needs `CLAUDE_CODE_ENABLE_FUNCTION_HOOKS=1`.
- **Hermeticity trap (M).** Loading writes about 752 KB of types into `<plugin>/.claude-plugin/types/`, which ignores itself with `*`. The run also creates `.claude.json` and `backups/` in the config dir. So the bats test must set `HOME` and `CLAUDE_CONFIG_DIR` to `$BATS_TMPDIR` and copy the plugin there. It should resolve its binary through `cc-claude-bin` and SKIP below 2.1.287.

## Adoption checklist

| # | Step | Owner | Blocker? | Evidence |
|---|---|---|---|---|
| 1 | P2 audit of 2.1.285-2.1.289: no recorded HOLD, held issues still open, no cap restored; MANIFEST rows | agent | no | MANIFEST grep (M); gh (M); CHANGELOG L1-463 (D) |
| 2 | Accept the under-7-day age of 2.1.289 against the churn bar | **operator** | **yes (a decision)** | MANIFEST 2.1.284 row precedent |
| 3 | P3 `npm install --prefix ~/.claude-289`, keep `DISABLE_AUTOUPDATER=1` (#84224 open) | agent | no | audit.md; holds.md |
| 4 | Add `lib/cc-upgrade-gate/check16_mods.sh`: a marker mod loads in a `-p` probe and in a spawned teammate; update gate.md count and table | agent | no | gate.md:140-145; tests/cc-upgrade-skill.bats:89 |
| 5 | P4 gate on 4 accounts; GREEN required; teammate load is the open question | agent | **yes if RED** | gate.md:174-178 |
| 6 | P6 activation script moves `_bin` to 289; bump the cc-claude-bin.bats ratchet in the same diff | agent writes; run per gate.md (GREEN satisfies the live test) | no | gate.md:152-166; SKILL.md inv. 5 |
| 7 | Repo `mods/<name>/` (manifest, hooks.json, .mjs, types, tests); install.sh leg modelled on vendor/ | agent (/ship) | no | install.sh:927-950 |
| 8a | Delivery A: `CLAUDE_CODE_PLUGIN_DIRS` export in the launcher | agent writes the activation edit | no (no c10) | strings-289 (M); -p probe (M) |
| 8b | or delivery B or C: settings.json `env`, or `enabledPlugins` plus marketplace | **operator** (c10 migration) | **yes (c10)** | migrations/README.md:70-77 |
| 9 | bats test: `plugin validate --strict` plus `plugin test` under a temp HOME, version-gated | agent | no | §4 (M) |
| 10 | Observe one REPL and one `-p` fire; read `--debug` for "hooks module … loaded" | agent | no | debug log (M) |

**Concerns.** Teammate loading under option A is unmeasured; step 4 must settle it. Mods run unsandboxed (D: announcement). The API "may change between releases" (D: upstream mods/README.md), so re-run step 9 on every bump.

**Deviation.** I ran Bin289 from /tmp (`plugin validate`, `plugin test`, a no-auth `-p` probe) against scratch HOMEs. All were non-interactive and wrote only under /tmp/mods-research.
