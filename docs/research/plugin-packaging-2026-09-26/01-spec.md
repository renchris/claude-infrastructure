# Claude plugin spec as of 2026-09-26: what a plugin can contain and where each part runs

**Headline.** A plugin is one folder with an optional `.claude-plugin/plugin.json`. It can carry 15 kinds of component. Only **skills, commands and remote MCP servers** load on all three surfaces (chat, Cowork, Claude Code). **Agents, hooks and local MCP servers** load in Cowork and Claude Code but not in chat. **LSP servers, output styles, themes, `settings`, monitors, workflows, channels, `userConfig` prompts and plugin dependencies** are effectively Claude Code-only. A top-level **`bin/` directory makes claude.ai and Cowork refuse the whole plugin**.

The blog line that plugins "package MCP and skills" describes the cross-surface subset, not the full format.

## Sources

Every source was fetched on 2026-09-26. The `.md` copies used for the line citations are in `/tmp/plugin-pkg-2026-09-26/src/`.

| Tag | URL | Local copy |
|---|---|---|
| PS | https://claude.com/docs/plugins/platform-support | cc_plugins_platform-support.md |
| BLD | https://claude.com/docs/plugins/build | cc_plugins_build.md |
| OV | https://claude.com/docs/plugins/overview | cc_plugins_overview.md |
| PSC | https://claude.com/docs/plugins/pre-submission-checklist | cc_plugins_pre-submission-checklist.md |
| SUB | https://claude.com/docs/plugins/submit | cc_plugins_submit.md |
| CW | https://claude.com/docs/cowork/guide/plugins | cc_cowork_guide_plugins.md |
| OS | https://claude.com/docs/plugins/org-sync | cc_plugins_org-sync.md |
| SKc | https://claude.com/docs/skills/how-to | cc_skills_how-to.md |
| 3P | https://claude.com/docs/third-party/claude-desktop/extensions | cc_third-party_claude-desktop_extensions.md |
| MR | https://code.claude.com/docs/en/plugins/manifest-reference | code_plugins_manifest-reference.md |
| CMP | https://code.claude.com/docs/en/plugins/components | code_plugins_components.md |
| LD | https://code.claude.com/docs/en/plugins/loading | code_plugins_loading.md |
| CR | https://code.claude.com/docs/en/plugins/create | code_plugins_create.md |
| MKT | https://code.claude.com/docs/en/plugins/marketplace-reference | code_plugins_marketplace-reference.md |
| HM | https://code.claude.com/docs/en/plugins/host-marketplace | code_plugins_host-marketplace.md |
| DEP | https://code.claude.com/docs/en/plugins/dependencies | code_plugins_dependencies.md |
| PUB | https://code.claude.com/docs/en/plugins/publish | code_plugins_publish.md |
| CLI | https://code.claude.com/docs/en/plugins/cli-reference | code_plugins_cli-reference.md |
| SK | https://code.claude.com/docs/en/skills | code_skills.md |
| ENV | https://code.claude.com/docs/en/env-vars | code_env-vars.md |
| BLOG | https://claude.com/blog/build-plugins-for-claude (2026-09-25) | (WebFetch summary only) |

**Column meanings in PS:32-40.**
- **Chat** means claude.ai on the web, the desktop app and mobile.
- **Cowork** means Cowork tasks in the desktop app.
- **CC** means Claude Code: the terminal, the IDE extensions and the desktop Code tab.
- "Ignored" means the surface skips that component. "Can't be installed" means the surface refuses the whole plugin (PS:28).

---

## 1. Components by surface

| # | Component | Default location | Manifest key (how it combines with the default) | Chat | Cowork | CC | Substitutions and env vars | Source |
|---|---|---|---|---|---|---|---|---|
| 1 | **Skills** | `skills/<name>/SKILL.md`, or one `SKILL.md` at the plugin root when there is no `skills/` directory | `skills`: path or array of directories. It **adds to** the `skills/` scan, and `"."` means the plugin root | Loads | Loads | Loads | Body: `${CLAUDE_SKILL_DIR}`, `${CLAUDE_PLUGIN_ROOT}`, `${CLAUDE_PLUGIN_DATA}`, `${CLAUDE_PROJECT_DIR}`, `${CLAUDE_SESSION_ID}`, `${CLAUDE_EFFORT}`, `$ARGUMENTS`/`$N`, and non-sensitive `${user_config.KEY}` | PS:32; MR:137,361-364; SK:422-433; MR:443 |
| 2 | **Commands** (legacy form of skills) | `commands/*.md`; a subdirectory adds a `:` segment | `commands`: path, array or object map `{name:{source\|content, description, argumentHint, model, allowedTools}}`. It **replaces** the default scan | Loads **as a skill** that Claude applies when it fits | Loads; the user runs `/plugin:cmd` | Loads | Same as skills | PS:33; MR:138,202-215; CMP "Commands" |
| 3 | **Agents** (subagents) | `agents/**/*.md`; subfolders join the name with `:` | `agents`: `.md` files only, directories not accepted. **Replaces** the default scan | **Ignored** | Loads | Loads | Body: `${CLAUDE_PLUGIN_ROOT}` and similar. Frontmatter keys **`permissionMode`, `hooks`, `mcpServers` and `initialPrompt` are ignored** | PS:34; MR:139; CMP:738-739 |
| 4 | **Hooks** | `hooks/hooks.json`, with a top-level `"hooks"` object shaped like the `hooks` key in settings.json | `hooks`: path, inline object or array. **Merges** with hooks.json | **Ignored** in first-party chat (3P desktop chat does run them, see §7) | Loads | Loads | `${…}` resolves in `command`/`args`. Hook processes get `CLAUDE_PLUGIN_ROOT`, `CLAUDE_PLUGIN_DATA`, `CLAUDE_PROJECT_DIR` and `CLAUDE_PLUGIN_OPTION_<KEY>` | PS:35; MR:140,518; CMP "Hooks" |
| 5 | **Remote MCP server** (`http`/`sse`/`ws` with a fixed URL) | `.mcp.json` | `mcpServers`: path, inline map, `.mcpb`/`.dxt` bundle path or https URL, or an array. **Merges**, and a name declared later wins | Listed on the plugin's **Connectors** tab; works only after the user adds or connects it there | Same as chat | Loads and connects directly | `${…}` resolves in `url`, `headers`, `headersHelper` | PS:36; MR:141,521; OV "Bundled connectors" |
| 6 | **Local MCP server** (stdio command, including `.mcpb`) | `.mcp.json` | same as #5 | **Ignored** (the web UI shows it as "Runs in each session") | Loads **only when the Cowork session runs on the user's computer** | Loads | stdio: `${…}` resolves in `command`/`args`/`env`. The process gets `CLAUDE_PLUGIN_ROOT` and `CLAUDE_PLUGIN_DATA` | PS:37; MR:520 |
| 7 | MCP server whose config uses `${user_config.*}` | — | — | Ignored when the URL contains the reference | **Ignored when a referenced option has no default**, because Cowork never prompts | Loads and prompts for the value | — | PS:38 |
| 8 | **Executables** | `bin/`, which goes on the Bash tool's PATH **after** the user's own entries, so a plugin cannot shadow `git` and similar commands | (no key) | **Can't be installed**: the whole plugin is refused | **Can't be installed** | Loads | — | PS:39; MR:572; CMP:885; OS:107-111 |
| 9 | **LSP servers** | `.lsp.json` (a bare map with no wrapper) | `lspServers`: strict object (`command`, `extensionToLanguage` required, plus `args`, `transport`, `env`, `initializationOptions`, `settings`, `workspaceFolder`, `startupTimeout`, `shutdownTimeout`, `restartOnCrash`, `maxRestarts`, `diagnostics`). **Merges** | Ignored | Ignored | Loads. The plugin does **not** install the server binary; it must be on PATH | PS:40; MR:142, lspServers table; CMP "LSP servers" |
| 10 | **Output styles** | `output-styles/*.md` | `outputStyles`: **replaces** the default | Ignored | Ignored | Loads as `<plugin>:<name>` in `/output-style` | — | PS:40; MR:143; CMP "Themes and output styles" |
| 11 | **Themes** | `themes/*.json` | `experimental.themes` (a top-level `themes` key still loads, with a warning). **Replaces** the default | Ignored | Ignored | Loads, read-only; a user edit is saved as a copy | — | PS:40; MR:146 |
| 12 | **Default settings** | `settings.json` at the plugin root | `settings`. **Only `agent` and `subagentStatusLine` take effect**; every other key is dropped. The file wins over the manifest key, and user settings win over the plugin | Ignored | Ignored | Loads | — | PS:40; MR:134,184; CMP:891 |
| 13 | **Monitors** (background shell process whose stdout becomes notifications) | `monitors/monitors.json` | `experimental.monitors`: path or inline array of `{name, command, description, when: "always"\|"on-skill-invoke:<skill>"}`. **Replaces** the default | Not in the PS table. **Unverified**; reasoning says Ignored | Not in the PS table. **Unverified** | Loads, but **interactive sessions only**: never with `-p`, and not on Bedrock, Google's Agent Platform or Foundry | `${…}` path vars resolve in `command`. **No `CLAUDE_PLUGIN_OPTION_*` and no `${user_config}`** | MR:147,50-80; CMP:989 |
| 14 | **Workflows** (`.js` workflow scripts) | `workflows/` | `workflows`: **replaces** the default | Not in the PS table. **Unverified** | Not in the PS table. **Unverified** | Loads | — | MR:144 |
| 15 | **Channels** (an MCP server that pushes messages into the session) | — | `channels`: array of `{server, displayName, userConfig}` | Not in the PS table. **Unverified**; reasoning says CC-only | Not in the PS table | Loads | the channel's `userConfig` substitutes into the server's `env` | MR:136,199-237 |
| 16 | **userConfig** (install-time prompts and secrets) | — | `userConfig`: `{KEY:{type: string\|number\|boolean\|directory\|file, title, description, required, default, options, multiple, sensitive, min, max}}`, a strict object | No prompt (see row 7) | **Never prompts** | Prompts **only in the interactive `/plugin` UI**. `claude plugin install` takes `--config K=V` instead | `${user_config.KEY}` works in MCP/LSP config, exec-form hook `args`, and skill/agent bodies (non-sensitive values only). `CLAUDE_PLUGIN_OPTION_<KEY>` goes to hook processes | MR:110-197; CMP:1028; PS:38 |
| 17 | **Plugin dependencies** | — | `dependencies`: `"name"`, `"name@mkt"`, or `{name, marketplace, version: semver-range}` | Not listed as supported | Not listed | Loads, with auto-install and prune | — | MR:133,180; DEP:51; BLD:640 ("dependencies between plugins" is a CC-only component) |
| 18 | **Eval cases** | `evals/` | `experimental.evals` | n/a (dev tool) | n/a | used by `claude plugin eval` | — | MR:148 |
| — | `CLAUDE.md` at the plugin root | — | — | not loaded | not loaded | **not loaded as context**; validate warns | — | MR:609; probe §9 |

Notes on the table:
- **Skills in chat.** Chat needs **Code execution and file creation** turned on, because skills run in Claude's sandbox (cc_skills_overview.md:14). In chat the whole skill folder, scripts included, is copied into the code-execution sandbox. `${CLAUDE_SKILL_DIR}` is replaced only in Claude Code and Cowork, so skill text should also use a path relative to `SKILL.md` (SKc:554). Scripts run with whatever that sandbox provides, not the user's machine (SKc:543).
- **Summary on claude.com.** BLD's "Check what each app loads" gives the same split in prose: skills and commands load everywhere, agents and hooks load in Cowork and CC, and `bin/` blocks claude.ai and Cowork.

## 2. `plugin.json` top-level fields (metadata; component keys are in §1)

Only `name` is required, and the manifest itself is optional (MR:28-30,115).
- An **unknown top-level key is stripped** and validate warns.
- An **unknown key inside `userConfig`, `channels`, `lspServers` or `monitors` entries is a hard error**, and the plugin does not load (MR:92-97).

| Field | Rule | Source |
|---|---|---|
| `name` | kebab-case. No spaces, `@`, `:` or path separators. It is the namespace for every component. **The directory additionally requires** ≤64 chars of `[a-z0-9-]`, starting and ending with a letter or digit, and not a reserved word (`claude`, `anthropic`, `official`, `plugin`, `mcp`, `test`) | MR:154-156; PSC:106-108 |
| `displayName` | UI label. A marketplace entry's value overrides it | MR:158-162 |
| `version` | Not checked as semver. **Setting it pins users to that cached copy until the string changes.** Not honoured for `command` sources, claude.ai-hosted marketplaces, or local-directory in-place plugins | MR:164-166 |
| `description`, `author{name,email,url}`, `homepage` (must parse as a URL or the load fails), `repository`, `license` (SPDX), `keywords` | display fields | MR:119-130 |
| `metadata` | free-form and not read. Needs CC ≥ 2.1.222 (validated: 2.1.220 warns "Unknown field", probe §9) | MR:168-170 |
| `defaultEnabled` | default `true`. The marketplace entry overrides it. Once a user has an `enabledPlugins` entry, later changes don't affect them | MR:172-176 |
| `$schema` | ignored | MR:121 |

## 3. `marketplace.json` (`.claude-plugin/marketplace.json` at the repository root)

**Top-level fields** (MKT:24-40).
- Required: `name`, `owner{name,…}`, `plugins[]`.
- Optional: `description`, `version`, `metadata.{description,version,pluginRoot}`, `forceRemoveDeletedPlugins`, `allowCrossMarketplaceDependenciesOn[]`, `renames{old: new|null}`.
- **Reserved names** include the official ones (`claude-plugins-official`, `knowledge-work-plugins`, …), `inline`, `builtin`, `skills-dir`, `synced`, `npm`/`github`/…, and any name starting `claudeai-` (MKT:39-50).

**Plugin entry** (MKT:42-65).
- Required: `name`, `source`.
- Also accepted: `description`, `version`, `category`, `tags`, `strict` (default true), `relevance` (hints for when Claude Code should suggest the plugin), `dependencies`, `defaultEnabled`, `displayName`, `metadata`, `headers`, `headersHelper`, **and every `plugin.json` field**.
- When `plugin.json` is absent, the entry *is* the manifest.
- When `plugin.json` is present:
  - Entry `mcpServers`, `lspServers`, `userConfig` and `channels` **don't apply**.
  - With `strict:true`, the six component fields are appended.
  - With `strict:false` plus any component field, the result is a **conflicting-manifests load failure** (MKT:67-98).
- Entry `hooks` must be inline; the file-path form silently never runs (MKT:76-78).

**Plugin source types** (MKT:100-125). `./relative` · `github{repo,ref,sha}` · `url` (a git repository) · `git-subdir{url,path,ref,sha}` · `npm{package,version,registry}` · `archive{url,sha256}` (≥2.1.224) · `command{command,timeout,mode}` (≥2.1.229; copy or link mode).

**What organization sync accepts** on claude.ai: only `github`, `url`, `git-subdir` or `./relative`, and no bare names under `pluginRoot` (OS:86-98).

**Real-world usage** in the official marketplace (`~/.claude/plugins/marketplaces/claude-plugins-official/.claude-plugin/marketplace.json`, commit db467cc, 2026-09-22):
- 310 entries. Sources: 161 `url`, 97 `git-subdir`, 52 relative.
- Entry keys used: `category` 296, `homepage` 294, `author` 228, `strict` 14, `version` 14, `lspServers` 12, `skills` 3.
- In the plugins vendored in that repository: `skills/` in 18, `commands/` in 14, `.mcp.json` in 14, `agents/` in 8, `hooks/` in 6, `workflows/` in 2.
- Zero use `bin/`, monitors, output-styles, themes, `.lsp.json` files or `settings.json`.
- No `plugin.json` there declares `userConfig`, `dependencies`, `channels` or `settings` (measured by find/grep, 2026-09-26).
- LSP plugins keep their config in the entry and ship no manifest. Our cached `swift-lsp/1.0.0` contains only `README.md` (`~/.claude/plugins/cache/claude-plugins-official/swift-lsp/1.0.0/`).

## 4. Substitution and environment variables

| Variable | Value | Where it resolves | Exported to |
|---|---|---|---|
| `${CLAUDE_PLUGIN_ROOT}` | absolute path of the **installed version dir**. **It changes on every update**, so don't write state there | hook `command`/`args`; monitor `command`; MCP stdio `command`/`args`/`env`; MCP http `url`/`headers`/`headersHelper`; LSP `command`/`args`/`env`/`workspaceFolder`; skill/command/agent bodies | hooks, MCP stdio, LSP, `headersHelper` |
| `${CLAUDE_PLUGIN_DATA}` | `<plugins-root>/data/<id>/`, where `<id>` is `name@marketplace` with other characters replaced by `-`. Created on first reference, **survives updates**, **deleted on the last uninstall** unless `--keep-data` | same fields | hooks, MCP stdio, LSP |
| `${CLAUDE_PROJECT_DIR}` | the project root | same | hooks, LSP |
| `${CLAUDE_SKILL_DIR}` | the skill's own subdirectory, not the plugin root. A text placeholder, **not an env var** | skill body and `allowed-tools` Bash rules | — |
| `${CLAUDE_SESSION_ID}`, `${CLAUDE_EFFORT}`, `$ARGUMENTS`, `$ARGUMENTS[N]`, `$N` | session id, effort level, arguments | skill body | — |
| `${user_config.KEY}` | saved option value | MCP/LSP config, exec-form hook `args`, skill/agent bodies (sensitive values become a placeholder). **Rejected** in shell-form hook `command`, monitor `command` and MCP `headersHelper`, where it is an error | — |
| `CLAUDE_PLUGIN_OPTION_<KEY>` | every option, key uppercased | — | **hook processes only**; not monitors, not `headersHelper` |

Sources: MR:499-535, MR:440-458, SK:422-433, CMP "Reference plugin paths".

- **None of these are in the environment of Bash-tool commands Claude runs**, in the main session or in subagents. Write the `${…}` in the skill body so it is substituted inline (MR:525).
- `<plugins-root>` is `$CLAUDE_CONFIG_DIR/plugins`, overridable with `CLAUDE_CODE_PLUGIN_CACHE_DIR` (ENV:336,406; LD "Find plugins on disk"). The per-account split is confirmed here: this session's `CLAUDE_CONFIG_DIR=~/.claude-quaternary`, and `~/.claude-secondary/plugins/data/` exists separately.

**Other plugin environment variables** (ENV:262-383,449):
- `CLAUDE_CODE_PLUGIN_DIRS`: `:`-separated absolute paths, like `--plugin-dir`, ≥2.1.280. **Ignored if set in project or local settings `env`.**
- `CLAUDE_CODE_PLUGIN_SEED_DIR`, `CLAUDE_CODE_PLUGIN_GIT_TIMEOUT_MS`, `CLAUDE_CODE_PLUGIN_PREFER_HTTPS`, `CLAUDE_CODE_PLUGIN_KEEP_MARKETPLACE_ON_FAILURE`.
- `CLAUDE_CODE_SYNC_PLUGIN_INSTALL`, used with `-p`.
- `FORCE_AUTOUPDATE_PLUGINS`, `CLAUDE_CODE_DISABLE_OFFICIAL_MARKETPLACE_AUTOINSTALL`.
- `CLAUDE_CODE_SAFE_MODE` and `CLAUDE_CODE_SIMPLE` both disable plugins.
- The setting `syncClaudeAiPlugins:false` turns off claude.ai→CC sync.

## 5. Install, update, cache and the live-edit loop (Claude Code)

| How the plugin is loaded | Copied or in place | Live edit? | Source |
|---|---|---|---|
| `--plugin-dir <dir or .zip>` (repeatable; a **folder of plugins** loads each child that has a manifest, ≥2.1.265), `--plugin-url <zip>`, `CLAUDE_CODE_PLUGIN_DIRS` | **In place**; zips are extracted to a temp dir. Session only; nothing is written to settings. ID `<name>@inline` | **Yes.** Edit, then `/reload-plugins` | CR:164-230; CLI:763+ |
| **Skills-dir plugin**: any `~/.claude/skills/<name>/` containing `.claude-plugin/plugin.json` (`claude plugin init` scaffolds one, ≥2.1.157). Project `.claude/skills/<name>/` also works, after the trust dialog | **In place**, auto-loads every session as `<name>@skills-dir` | **Yes.** SKILL.md text is hot-detected; `hooks/`, `.mcp.json`, `agents/` and `output-styles/` need `/reload-plugins` | CR:229-247; SK:133,277 |
| Relative-path plugin in a marketplace **added from a local directory** (`claude plugin marketplace add ./path`) | **In place**. `CLAUDE_PLUGIN_ROOT` is the source dir; the version string is ignored | **Yes.** Takes effect at the next session or `/reload-plugins`, with no version bump. The npm dependency auto-install does **not** run here | LD:177, LD:165, LD:211 |
| `command` source, link mode | in place through links | re-runs once per session | LD:178,331-343 |
| **Every other marketplace plugin** (github/url/git-subdir/npm/archive, or relative inside a git-hosted marketplace) | **Copied** to `cache/<mkt>/<plugin>/<version>/`. **Files outside the plugin dir are not copied** | No. The update needs a computed-version change | LD:179 |
| Synced from claude.ai (`<name>@synced`, stored under `plugins/synced/`) | downloaded at each CC start (≥2.1.273, claude.ai login required) | edit on claude.ai → next start or `/reload-plugins` | LD:89-121 |

**How the version is computed** (LD:255-287):
1. The manifest `version` wins.
2. Otherwise the entry `version`.
3. Otherwise a value derived from the source: the 12-character commit SHA for github/url/git-subdir, the SHA-256 digest for archive, `unknown` for a local non-git directory or npm.
- **The version is never taken from an enclosing git repository such as a git-managed `~/.claude`.**
- Pinning `version` freezes users until the string is bumped. Leaving it unset tracks commits.

**Updates** (LD:311-329; HM symlink section):
- **Timing.** Auto-update runs after the first message plus a random delay of up to 10 minutes.
  - Default **on** for official Anthropic marketplaces and claude.ai-hosted ones.
  - **Off** for `knowledge-work-plugins`, `first-party-plugins` and every third-party marketplace.
- **Old versions.** They get `.orphaned_at` and are deleted **14 days later** (LD:193; seen on disk: `cache/.../security-guidance/2.0.7/.orphaned_at`).
- **Mid-session updates.** Hooks, MCP and LSP keep the old path until `/reload-plugins`. Monitors need a restart.
- **npm dependencies.** They are auto-installed into the cached copy only when `package.json` and an npm/bun lockfile are both present. The install uses `--ignore-scripts`, frozen resolution and a **60 s timeout**, and cannot be disabled (LD:197-253).
- **Symlinks when copying to the cache:**
  - A link inside the plugin is kept as a relative link.
  - A link elsewhere in the same marketplace is dereferenced (copied).
  - A link **outside the marketplace is skipped**.
  - For local-path installs, only links inside the plugin survive (HM:55-63).
- **Paths outside the root.** Any component path escaping the plugin root, including `..` or a backslash on macOS/Linux, is rejected (LD:181-189).

**Cowork / claude.ai updates.**
- These surfaces read from the account, not the machine.
- Marketplace hosts: GitHub/GHE, or public GitLab/Bitbucket. **No local path**, so the only live loop is Claude Code (PS:53).
- Updates arrive via **Check for updates** or **Sync automatically**.
- Cowork **warns before an update overwrites locally edited plugin files** (CW:96).
- Direct upload: **Customize > Plugins > Add > Upload plugin**, as a zip or `.plugin` file (OV "Find and add a plugin").

## 6. Namespacing, versioning, dependencies

**Namespacing** (CMP; SK:396-414):
- Skill `/<plugin>:<dir>`. Frontmatter `name` replaces the last segment.
- **The bare `/name` also works unless another command already has that name** (SK:410).
- Since ≥2.1.246 a `name` already carrying the prefix is not doubled; 2.1.216-2.1.245 doubled it.
- A root `SKILL.md` in a skills-dir plugin is invoked as `/my-tool`, not `/my-tool:my-tool` (CR:247).

**Other namespaced names:**
- Commands: `/<plugin>:<sub>:<file>`.
- Agents: `<plugin>:<subdir>:<name>`, invoked as `@agent-<plugin>:<name>`.
- MCP servers: `plugin:<plugin>:<server>`. Tools: `mcp__plugin_<plugin>_<server>__<tool>`; hook matchers and permission rules must use this full form (CMP:821-822).
- Output styles: `<plugin>:<name>`.
- In chat, the `/` menu shows `plugin-name:skill-name` (OV "Use a plugin").

**Name conflicts between plugins** (LD:345-357). Precedence: managed-settings id > `--plugin-dir`/URL/env (**it silently replaces an installed marketplace plugin of the same manifest name**) > installed marketplace plugin > skills-dir plugin (user beats project) > synced.

**Dependencies** (DEP):
- Semver ranges (`^`, `~`, `>=`, `=`) resolve against **git tags** named `{name}--v{version}`, which `claude plugin tag` creates.
- Pre-releases are excluded unless the range has a `-0` suffix.
- Cross-marketplace dependencies need `allowCrossMarketplaceDependenciesOn` in the root plugin's marketplace.
- Missing dependencies are auto-installed on install or reload. `claude plugin prune` removes orphans.
- A `name` + `dependencies`-only plugin is a valid "bundle" plugin (DEP:56).
- Not documented as working on claude.ai or Cowork (BLD:640).

**Platform restrictions:**
- No per-OS field exists in the manifest. Windows gets forward-slash substitutions, and backslash paths load only on Windows (MR:553; LD:187).
- The per-surface restriction is implicit, derived from the components (PS:42: the portal "derives the surfaces it supports from these same rules and shows them to you").
- Monitors don't run on Bedrock, Google's Agent Platform or Foundry (MR:147).
- Project-scope plugins (repo `.claude/skills/<name>/` plugins) skip `.mcpb` servers and monitors, and need the trust dialog (LD "Plugins shared through a repository").
- Cloud sessions don't load plugins enabled only in user settings or declared in the repository's `.claude/settings.json` (SK:182).

## 7. Surface caveats beyond the table

- **Synced plugins in Claude Code.**
  - A plugin added on claude.ai (including from the directory) reaches Claude Code only as `<name>@synced`. Claude Code's `/plugin` **cannot browse the directory** (PS:56; PUB:148).
  - The blog's "one discovery experience" is claude.ai **Customize > Plugins > Discover** plus sync. CLI installs never travel back to the account (PS:52).
  - In terminal sessions a synced plugin's skills, agents, hooks, MCP and LSP servers all load with marketplace trust (LD:91).
- **Skill frontmatter outside Claude Code.**
  - claude.ai skill uploads and the Skills API accept only `name`, `description`, `license`, `compatibility`, `metadata` and `allowed-tools`. **Any other key is a hard upload error** (`Unexpected key(s) in SKILL.md frontmatter: argument-hint…`) (SK:382-389).
  - Claude Code-only body features (`!` dynamic-context injection, `@` file attachments) don't work in claude.ai chat or the API (SK:392).
  - **Unverified:** whether *plugin* uploads to claude.ai enforce the same six-key rule. The PSC front-matter check (PSC:170) only requires parseable YAML and a text `description`. Treat the rule as a risk.
- **Cowork skill bodies.** In a desktop Cowork session every `!` command line is replaced with the `disableSkillShellExecution` placeholder (SK:266).
- **claude.com skill name rule.** `name` must **match the directory name** and be ≤64 characters of `[a-z0-9-]`. `description` is ≤1,024 characters (SKc:477-478). Claude Code itself allows `name` to differ from the directory.
- **Hooks in chat, first-party vs third-party.**
  - First-party PS says chat **ignores** hooks (PS:35).
  - The third-party Claude Desktop page says chat conversations run plugin hooks on desktop ≥1.52386.0, Cowork runs them, and Code sessions run them from marketplace plugins but **not** from `org-plugins/` (3P:385-391).
  - This is deployment-specific. The PS table governs claude.ai.
- **Cowork gets plugins** by downloading them into "the session's own environment" at session start (LD:93-96). OV says agents and hooks "run commands on your computer" in Cowork and CC.
  - **Reasoning only:** hook scripts in Cowork depend on whatever runtime that session environment has. There is no guarantee that tools on the user's host PATH exist there.

## 8. Hard limits

**claude.ai / Cowork install limits** (PS:54; CW:80-84):
1. 200 MB uncompressed per plugin. 5,000 files per plugin. 200 MB is also the largest **Upload plugin** file.
2. Marketplace repository archive 512 MB. 500 plugins per marketplace. **25 self-added marketplaces** per account per org.
3. The in-app skill viewer previews files ≤1 MB; larger files still work at runtime (CW:86).

**Plugin shape:**

4. A top-level `bin/` makes claude.ai and Cowork refuse the plugin, including via org sync (`Plugin contains a top-level bin/ directory`) (PS:39; OS:107-111). Put executables in `scripts/` and call them as `${CLAUDE_PLUGIN_ROOT}/scripts/x`.
5. Only `plugin.json` may live in `.claude-plugin/`; components placed there don't load (CR "Plugin layout" Warning).
6. Every component path must start with `./`, resolve inside the plugin root and exist. No `..`, no escaping symlinks, no backslashes on Unix (MR "Path rules"; LD:181-189).

**Directory submission** (PSC:74-171; SUB:23,107-119):

7. Checks that **block** submission:
   - `.claude-plugin/plugin.json`, one plugin per submission.
   - A README of ≥40 words (code blocks don't count).
   - A LICENSE file or `license` field.
   - `description`, `author` and `version` set.
   - No `.DS_Store` and similar files.
   - **No symlinks, submodules or LFS pointers** for loaded entries.
   - Exact version pins for `npx`/`uvx` launchers.
   - No credentials anywhere.
   - Remote MCP must be `https://`/`wss://`.
   - In a subfolder repository, hook and MCP commands must use full `${CLAUDE_PLUGIN_ROOT}/…` paths with no other variables, `$(…)` or `-c`.
8. Validation **stops** on:
   - a repository over 50 MiB as archived or over 256 MiB unpacked;
   - ≥10,000 entries;
   - any file over 5 MiB (PSC:96).
9. **Held for a human reviewer** when:
   - a non-image, non-font file is over **256 KiB**;
   - there are over **512 files**;
   - there are binaries (`.pdf`, `.zip`, compiled executables);
   - there are `.mcpb` bundles;
   - pinned-package launchers are used;
   - there are lockfile installs;
   - there are non-shell programs that hooks or MCP run from a subfolder repository;
   - there is minified or compiled code (PSC:130-160,173-183).
10. Directory repositories must be on **github.com**. Private is allowed for validate and submit (with the Claude GitHub App and a source-upload consent) but must be **public to publish**. The submitter needs a paid plan, and on Team or Enterprise an Owner (SUB:23,107-119).
11. `claude-plugins-official` takes no portal submissions (PUB:146).

**Claude Code runtime limits:**

12. Monitors: interactive only; no `userConfig`; they keep running after a mid-session disable (CMP:989-991).
13. LSP: stdout must be protocol only. Headers ≤64 KiB, body ≤32 MiB, or the server is disconnected (CMP "LSP servers").
14. Plugin agents cannot declare their own hooks, MCP servers or `permissionMode` (CMP:739).
15. `settings` honours only `agent` and `subagentStatusLine` (MR:134).
16. Version gates relevant to our pins:
    - `userConfig.options` ≥2.1.271 (**older CC can't load the plugin at all**, MR:172).
    - `metadata` ≥2.1.222; `/config` rows ≥2.1.269; claude.ai sync ≥2.1.273.
    - `CLAUDE_CODE_PLUGIN_DIRS` ≥2.1.280; `--plugin-dir` folder-of-plugins ≥2.1.265.
    - `skills: "."` ≥2.1.221 (use `"./"` for older versions).
    - Validator path checks for outputStyles, LSP, monitors and themes ≥2.1.283.

## 9. Local probes (read-only; nothing installed or enabled)

- **Binaries.**
  - `~/.claude/bin/claude-latest` still resolves to **2.1.114**. It prints "2.1.283 available but not in MANIFEST allow-list", and its `plugin` subcommands lack `init`, `details`, `eval`, `tag` and `prune`.
  - This session runs **2.1.280** (`~/.claude-280/node_modules/.bin/claude`).
  - `plugin --help` on 2.1.280 lists: `details, disable, enable, eval, init|new, install, list, marketplace, prune|autoremove, tag, uninstall, update, validate`.
  - `validate` flags: `--json`, `--strict`.
  - `init --with`: `skills, agents, hooks, mcp, lsp, output-style, channel`.
  - `uninstall` flags: `--keep-data`, `--prune`.
  - `install` flags: `--config k=v`, `-s user|project|local`, `--accept-command`, `-y`.
- **Probe plugin:** `/tmp/plugin-pkg-2026-09-26/probe/probe-plugin`, built by `probe/build.sh`. Every component plus `bin/`, `metadata`, `settings.model`, `userConfig.options`, an agent with `permissionMode`/`hooks`, a root `CLAUDE.md` and an unknown key.
  - **2.1.280 validate:** passes with 2 warnings (unknown `bogusTop`; root CLAUDE.md not loaded).
    - It raised **no warning** for `bin/`, for the dropped `settings.model`, or for the ignored agent `permissionMode`/`hooks`.
    - **The local validator does not tell you about cross-surface incompatibility.** Only the portal and the PS table do.
  - **2.1.220 validate:** **fails** with `userConfig.tone: Unrecognized key: "options"`, and warns `metadata` unknown. This confirms the version gates.
  - `claude --plugin-dir <probe> plugin details probe-plugin` reported:
    - Inventory: Skills (2) `c, hello` (commands are counted as skills), Agents 1, Hooks 1 ("harness-only — no model context cost"), MCP 1, LSP 0.
    - Always-on cost ~34 tok.
    - It does not list bin, monitors, output styles, themes or workflows.
  - `plugin list` showed the probe as `probe-plugin@inline … Status: ✘ disabled`. **`defaultEnabled:false` applies even to `--plugin-dir` loads.**
- **Account plugin state.**
  - `~/.claude/plugins/` holds `cache/ data/ marketplaces/ synced/ installed_plugins.json known_marketplaces.json blocklist.json plugin-catalog-cache.json`.
  - `synced/*/.marketplaces.json` has `"rows": []`, so nothing is synced from claude.ai today.
  - `~/.claude/plugins/installed_plugins.json` records installPaths inside `~/.claude-secondary/plugins/cache/…` (cross-account path bleed; cause not investigated).
  - `security-guidance` 2.0.8 is a hooks-only plugin whose commands are `bash "${CLAUDE_PLUGIN_ROOT}/hooks/sg-python.sh" …`: a real-world example of the shell-form quoting pattern.

## 10. What this means for packaging our `~/.claude` repo (reasoning, based on §1-8)

- **Local census.** 55 skill dirs, 25 commands, 6 agents, and 212 hook `"command"` entries in `~/.claude/settings.json` using absolute `~/.claude/hooks/*.sh` paths.
  - Local skill frontmatter keys: name 53, description 53, allowed-tools 9, argument-hint 2, when_to_use 1, shell 1, disable-model-invocation 1, arguments 1.
  - Those last five are non-spec keys, so the six-key rule would reject them on a claude.ai skill upload.
  - No `~/.claude/skills/*/.claude-plugin/` exists today, so there is no accidental `@skills-dir` loading.
- **Hooks.** They must be rewritten to `"${CLAUDE_PLUGIN_ROOT}"/hooks/x.sh` (shell form, quoted) or exec form with `args`. Anything they read outside the plugin dir disappears once the plugin is copied to the cache. State belongs in `${CLAUDE_PLUGIN_DATA}`.
- **CLIs.** Shipping our bash CLIs via `bin/` makes the plugin Claude Code-only. That is fine for a CC-only plugin, but split it from any plugin meant for claude.ai or Cowork. The alternative is `scripts/` plus `${CLAUDE_PLUGIN_ROOT}` references.
- **Commands and agents.**
  - Commands degrade to auto-invoked skills in chat.
  - Agents are Cowork/CC-only and cannot carry their own hooks, MCP servers or `permissionMode`.
- **Live-edit loop.** The two in-place routes (a local-directory marketplace, or `CLAUDE_CODE_PLUGIN_DIRS`/`--plugin-dir`) give edit → `/reload-plugins` with no version bump or copy.
  - A github-hosted marketplace means cache copies, version or SHA gating, and 14-day orphans.
  - Each `CLAUDE_CONFIG_DIR` account has its own plugins root, so an install happens once per account.

## 11. Discrepancies and open questions

| Item | Status |
|---|---|
| BLOG says CC "specifically" adds "LSPs, commands, hooks, and agents". PS/OV say commands load in chat (as skills), and hooks and agents load in Cowork | Treat the docs table as authoritative; the blog summarises loosely |
| Monitors, workflows, channels and `userConfig` prompts on chat/Cowork | Not listed in PS. The reasoning says they are ignored, except Cowork's `${user_config}` rule (PS:38). Test by uploading to claude.ai before relying on them |
| Whether claude.ai **plugin** upload enforces the six-key skill frontmatter rule (SK:389 covers *skill* uploads) | Unverified. Keep plugin skills that target chat to spec keys only |
| Hooks in chat: first-party ignores them (PS:35) vs third-party desktop runs them (3P:391) | Deployment-specific |
| Cowork hook runtime environment (host vs session VM) | Docs are ambiguous (OV "on your computer" vs LD "session's own environment") |
