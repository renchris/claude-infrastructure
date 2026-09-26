# Claude plugin directory vs a self-hosted GitHub marketplace: review, scan and policy requirements

Date: 2026-09-26. Read-only research; nothing submitted. Candidate repo: `github.com/renchris/claude-infrastructure`. The repo figures were measured on local `main` HEAD, a clean tree, which should match the GitHub default branch. Anything marked **[inference]** is not stated in a source.

## Headline

- **Submitting the repo as it stands stops before any report is produced.** The rule is "Keep the repository under 50 MiB as GitHub archives it and under 256 MiB unpacked" ([pre-submission checklist](https://claude.com/docs/plugins/pre-submission-checklist)). The measured `git archive HEAD | gzip` is **151.9 MiB**, mostly `assets/hero/*.mp4` and `*.webp`, and the unpacked tar is **240.5 MiB**. The limit covers the whole repository even when you submit a subfolder. So pointing the portal at a `plugins/<x>` subfolder of this monorepo still fails. You need either a dedicated repo or a tracked tree with about 100 MiB of media removed.
- **A missing LICENSE and an unpinned launcher both block submission. They are not "recommended changes".** The docs mark `License missing` and `Unpinned npx launcher` as **Blocks** ([checklist](https://claude.com/docs/plugins/pre-submission-checklist)). The screenshots described in the brief show them as recommended changes on a version that passed, which contradicts the current docs. **[inference]** Those screenshots are probably illustrative mockups from the launch blog. Trust the docs.
- **The hooks cannot be shipped as they are.** 61 hook files read transcripts or `.jsonl` files, which conflicts with Policy §1.F. Several hooks auto-approve permissions, and the scan looks for "changing Claude's permission settings". `push-critical.sh` POSTs to `api.pushover.net`, which matches the scan category "Sends data to an undisclosed destination". The PreToolUse, PostToolUse and UserPromptSubmit hooks fire on every session with no project gate. The published scan prompt for Anthropic's official marketplace fails exactly that pattern.
- **A skills-only bundle is feasible.** It would take the roughly 14 skills that make no machine-specific references, placed in a new repo with a LICENSE and a README of at least 40 words. That subset fits every file-count, file-size and file-type limit (the whole `skills/`, `commands/` and `agents/` set is 112 text files, the largest 145 KiB). It installs on Chat, Cowork and Claude Code.

## 1. Requirement checklist

**Results key** (definitions from the [checklist](https://claude.com/docs/plugins/pre-submission-checklist)):
- **Blocks**: you cannot submit.
- **Validation stops**: no report is produced.
- **Held**: an Anthropic reviewer must clear the version before it goes live.
- **Warning**: you can submit without fixing it.

The last column assumes the repo is submitted with a plugin folder carved out of it. "Carved skills-only" means a new repo containing only portable skills.

| # | Requirement (result if unmet) | Source | Would claude-infrastructure pass? Why |
|---|---|---|---|
| 1 | Paid plan: Pro, Max, Team or Enterprise. On Team or Enterprise, an Owner or the "Directory" permission is needed. | [publish](https://claude.com/docs/directory/publish) | Yes. The account is on Max. |
| 2 | GitHub repo on github.com; your connected GitHub account can push to it. It can be private during review but must be **public to publish**. | [submit](https://claude.com/docs/plugins/submit) | Yes. The repo is public and owned by the account. |
| 3 | A folder containing `.claude-plugin/plugin.json` (Blocks) | checklist | **No.** No `plugin.json` exists anywhere in the repo, so one must be authored. |
| 4 | One plugin per submission. In a marketplace repo, each plugin folder is validated and submitted separately (Blocks). | checklist; [submit](https://claude.com/docs/plugins/submit) | Yes, if one plugin folder is chosen. |
| 5 | **Repo under 50 MiB as a GitHub archive, under 256 MiB unpacked, fewer than 10,000 files and folders, and each plugin file under 5 MiB** (Validation stops: "Repository too large to validate") | checklist | **No.** Archive is 151.9 MiB. Unpacked is 240.5 MiB, which passes but only just. There are 7,027 files and 740 folders (7,767 in total), which passes. |
| 6 | Every file a hook, MCP command or script uses must be inside the plugin folder. `plugin.json` paths must not point outside it (Blocks). | checklist | **No, for the hooks as they are.** 28 hook scripts `source` code under `lib/` and `hooks/lib`. Skills refer to `~/.claude` and `~/Development` (24 of 38 skill dirs). |
| 7 | Regular files only: no symlinks, submodules or LFS pointers (Blocks where the plugin loads them) | checklist | Yes. The index has 0 symlinks and 0 submodules. `install.sh` creates symlinks at deploy time, but they are not committed. |
| 8 | No `.DS_Store`, `Thumbs.db` or `__MACOSX` in the plugin folder (Blocks) | checklist | Yes. None is tracked. Watch for a macOS `.DS_Store` appearing in any new repo. |
| 9 | Names valid on both Windows and macOS: no colon, no trailing dot, no case-only duplicates (Validation stops) | checklist | Not checked across all 7,027 paths. Low risk for a carved subset. |
| 10 | `.gitattributes` must not use `export-ignore`, `export-subst` or `filter`/LFS (Validation stops) | checklist | Yes. It only uses `merge=union`. |
| 11 | Plugin `name` is kebab-case, 64 characters or fewer, ASCII (Blocks for non-ASCII). It is not a reserved word on its own and must not look official (Blocks). A brand look-alike is Held. | checklist | **Risk.** A name like `claude-infrastructure` could draw "Name matches a known brand" (Held), and a name presenting the plugin as official Blocks. **[inference]** Pick a distinctive name. |
| 12 | Set `description`, `author` and `version` (Warning) | checklist | Needs authoring. |
| 13 | **README of at least 40 words in the plugin folder**; words inside code blocks don't count (Blocks) | checklist | Yes if the plugin is the repo root. A carved subfolder needs its own README. |
| 14 | **`LICENSE` file or a `license` field in `plugin.json`** (Blocks) | checklist | **No.** The repo has no LICENSE. |
| 15 | Non-image files under 256 KiB; 512 files or fewer; text, PNG, JPEG, GIF, WebP and fonts only (Held) | checklist | A carved skills subset passes: 112 files, all text, largest 145 KiB. The whole repo would be Held for `.mp4` files and oversized files. |
| 16 | MCP servers declared as `command`/`args` or `url`, not `.mcpb` or `.dxt` bundles (Held; Blocks if fetched from a URL) | checklist | Not applicable unless MCP servers are added. |
| 17 | Package launchers (`npx`, `uvx`, `bunx` and others) pinned to exact versions, and `uv run` run with `--locked` (Blocks). Even pinned packages are Held ("Runs a pinned npx or uvx package"). | checklist | Not applicable if no launcher. `mcp-servers.json` uses a remote URL for `motion` and an absolute `~/Library/.../ms-365-mcp-server` path, which would fail row 6. |
| 18 | No `.npmrc`, `bunfig.toml` or `uv.toml` pointing at another registry (Blocks with a launcher) | checklist | Not applicable. |
| 19 | A lockfile install (`package.json` plus a lockfile at the plugin root) is always Held | checklist | The repo root has `package.json` and `package-lock.json`, so it would be Held if the root is the plugin folder. |
| 20 | **No real credentials in any file, docs included.** Secrets come through `userConfig` with `sensitive: true` (Blocks). | checklist | Needs a sweep. `accounts.json` sits at the root and holds account metadata. **[inference]** Exclude it from any plugin folder. |
| 21 | **Do not read a credential from the environment (for example `$GITHUB_TOKEN`) and send it to a server** (Held; Blocks via an HTTP hook) | checklist | **Risk.** Five tracked files under `hooks/`, `bin/`, `scripts/` and `lib/` use `security find-generic-password` or `.credentials`. Pushover keys are read by `push-critical.sh`. |
| 22 | `.mcp.json` must be valid, and remote servers `https`/`wss` (Blocks) | checklist | Not applicable, since there is no `.mcp.json`. |
| 23 | A local MCP server is started by running a file with plain arguments, not through a shell, `-c` or `npm run` (Held) | checklist | Not applicable. |
| 24 | **Hook and MCP command paths written in full from `${CLAUDE_PLUGIN_ROOT}`, with no other variables, `$(...)`, globs or `python3 -c`** (Blocks when the plugin is a subfolder) | checklist | **No, for the hooks as they are.** They use `$HOME`, `$(...)`, `jq` and inline Python. 107 of 133 hook files match `python3 -c`, `bash -c`, `node -e` or `jq`. |
| 25 | **Scripts run by hooks must not use launchers or installs. In a subfolder they also must not use shell variables, command substitution or calls to other plugin files** ("Scripts the validator couldn't follow": Held). A non-shell hook such as `.py` in a subfolder is always Held. | checklist | **No.** It would be Held at minimum: 28 hooks source libraries, 6 hooks are `.py`, and command substitution is pervasive. |
| 26 | `hooks/hooks.json` is valid, with a top-level `hooks` object, only documented events and types, and HTTPS on HTTP hooks (Blocks) | checklist | **No.** Hooks are wired through `settings-templates/settings.example.json` (14 event types, about 78 bindings), not `hooks/hooks.json`. A new file would be needed, and events such as `TeammateIdle`, `TaskCompleted` and `WorktreeCreate` must appear in the [hooks reference](https://code.claude.com/docs/en/hooks). |
| 27 | Valid YAML front matter, with `description` as a string (Blocks if it doesn't parse); exact folder and file names such as `SKILL.md` (Blocks) | checklist | Likely passes for skills. Not verified file by file. |
| 28 | **Security scan** (after you submit, on every new commit): "behavior that a plugin doesn't disclose, such as sending data elsewhere, running hidden code, or changing Claude's permission settings". A first submission that fails is **rejected**. Code the scan can't read (compiled, packed, minified) is Held. | checklist § Prepare for the security scan; [submit](https://claude.com/docs/plugins/submit) | **Hooks fail.** See section 2. **Skills: likely pass** once every network or browser action is disclosed in the README. |
| 29 | Policy §1.B: do not evade Claude's guardrails, system instructions or sandbox, or help users do so | [Software Directory Policy](https://support.claude.com/en/articles/13145358-anthropic-software-directory-policy) | **Risk.** `model-permission-decider.py` and the PermissionRequest hooks (3 bindings) auto-decide permissions. `curl-gate`, `validate-bash` and similar guards restrict rather than evade, which is probably acceptable. **[inference]** |
| 30 | Policy §1.D and §1.F: collect only what is needed; **do not query or extract Claude's memory, chat history, conversation summaries or uploaded files** | Policy | **No.** 61 hook files read `transcript_path`, `*.jsonl` or `~/.claude/projects/`. These include memory-index drain, harvest-skill and handoff. |
| 31 | Policy §2.D, §2.F and §2.G: skills must not coerce calls to other tools, must not fetch behavioral instructions from outside sources, and must have no hidden or encoded instructions | Policy | Skills that point to `~/.claude/rules/*.md` or other external files are loading instructions from outside the plugin **[inference]**. Carve those out. |
| 32 | Policy §3.A and §3.B: a privacy policy if the plugin collects data or connects to a remote service; verified contact and support channels | Policy | A skills-only plugin with no data collection needs no privacy policy. A contact email is still required at the portal's Compliance step. |
| 33 | Policy §3.C and §3.G: document how it works and keep it maintained | Policy | README work. |
| 34 | Policy §3.D and §3.E: a test account with sample data, and three or more working example prompts | Policy | Three example prompts are cheap to add to the README. **[inference]** The test-account rule applies to plugins with a backend. |
| 35 | Policy §3.F: you must own or control every endpoint it connects to. **Plugins may connect to any connector approved in the directory.** | Policy | `motion.dev` MCP counts only if it is itself a directory connector. The simplest path is no MCP at all. |
| 36 | Policy §1.E: no IP infringement | Policy | `kpmg-deck` bakes in a corporate brand system. The `LOCAL_ONLY.md` exclusions (for example the Minto derivative) must stay excluded. |
| 37 | Terms: indemnify Anthropic, grant a license to your listing text and branding, and run a security-vulnerability intake | [Directory Terms](https://support.claude.com/en/articles/13145338-anthropic-software-directory-terms) | Acceptance only. A `SECURITY.md` or contact address satisfies the vulnerability-intake clause. **[inference]** |
| 38 | Data-handling questions (personal data, sending to undeclared services, retention, users under 18) and four compliance acknowledgements | [submit](https://claude.com/docs/plugins/submit) | Answerable for a skills-only bundle. |
| 39 | Limits: 10 submissions per organization per 24 hours; one submission per repo+folder; the first organization to submit a folder owns it | [submit](https://claude.com/docs/plugins/submit) | Not a constraint. |
| 40 | **A top-level `bin/` in the plugin folder: "Can't be installed" on Chat and Cowork (the surface refuses the whole plugin)** | [platform-support](https://claude.com/docs/plugins/platform-support) | **No, if the repo root is the plugin.** Root `bin/` holds 121 files, so the plugin would become effectively Claude Code-only. |

## 2. Answers to the key questions

### (a) Automated checks and what the security scan covers

- **Two passes** ([checklist](https://claude.com/docs/plugins/pre-submission-checklist)):
  - **Validate** runs in the submission form on one commit.
  - The **scan** runs after you submit, on every new commit on the tracked branch or tag. It repeats validation and adds the security scan.
- **Check families**, all listed in section 1: repository and folder layout, manifest and name, README and license, files, what the plugin runs and connects to (launchers, registries, credentials, MCP, hook command form), reviewer-always choices, and component syntax.
- **Scan scope in a subfolder:** "the directory reads and scans only that folder" ([submit](https://claude.com/docs/plugins/submit)). Installers receive only the plugin folder.
- **Bash is scanned:**
  - The validator "follows only plain shell scripts" that hooks, MCP or LSP commands, or `` !`…` `` lines run. Non-shell targets, directory-to-interpreter calls and shell scripts that call other files are Held.
  - A script that SKILL.md only *tells Claude to run* is outside the follow check ([checklist](https://claude.com/docs/plugins/pre-submission-checklist) § Choices a reviewer always checks).
  - **[inference]** The security scan itself reads every file, because unreadable code is Held.
- **Network calls:** the scan's named category is "Sends data to an undisclosed destination". Disclosure in the README is required, but "a complete README doesn't make a behavior allowed" (checklist).
- **Best public evidence of the scan's rubric:** Anthropic's official-marketplace CI runs a Claude policy scan, [`.github/policy/prompt.md`](https://github.com/anthropics/claude-plugins-official/blob/main/.github/policy/prompt.md). It fails a plugin when any of the following holds:
  - A **PreToolUse, PostToolUse or UserPromptSubmit hook runs with no project-relevance gate** (`has_broad_scope_hooks`).
  - Any outbound call goes to a host other than the declared MCP servers, unless the README discloses it *and* documents an opt-out (`has_undisclosed_telemetry`).
  - Credentials are read from a keychain, `~/.aws` or `~/.claude/.credentials` and routed to a different service.
  - The description does not match what the hooks, telemetry or data access actually do.

  **[inference]** The directory scan is a separate pipeline, but it very likely applies the same bar. Both cite the same Directory Policy, and the scan category names line up.

### (b) Disallowed or discouraged content

| Content | Status | Source |
|---|---|---|
| Hooks that block or modify tool calls | Not banned by name. Hooks are an accepted component. Ungated tool and prompt hooks fail the official-marketplace rubric. Changing permission settings is a scan category. | [publish](https://claude.com/docs/directory/publish), [checklist](https://claude.com/docs/plugins/pre-submission-checklist), [official prompt](https://github.com/anthropics/claude-plugins-official/blob/main/.github/policy/prompt.md) |
| Telemetry | Must be disclosed. Default-on telemetry without disclosure and an opt-out fails (official rubric). Policy §1.D: "must not collect extraneous conversation data, even for logging purposes." | Policy; official prompt |
| Reading chat history, memory or transcripts | Prohibited (§1.F) | Policy |
| Credential handling | Secrets never in files; use `userConfig` with `sensitive: true`. Reading environment credentials and sending them on is Held, and Blocks via an HTTP hook. | checklist |
| OS-specific scripts | **No rule bans them.** **[inference]** They become de facto unusable outside macOS. Cowork runs tools inside a "Cowork workspace VM" with an egress allowlist (`coworkEgressAllowedHosts`) ([Cowork changelog](https://claude.com/docs/cowork/changelog)), where `osascript`, `launchctl` and `security` are presumably absent. Policy §2.B requires that descriptions "precisely match actual functionality", so declare macOS-only in the README. |
| Obfuscated, minified or encoded code or instructions | Held (code) or prohibited (§2.G, instructions) | checklist; Policy |
| Instructions fetched from outside at run time | Prohibited (§2.F) | Policy |
| Money movement; AI image, video or audio generation; ads | Unsupported use cases (§4) | Policy |
| Brand look-alike names, forks reusing an upstream name | Held | checklist |

### (c) Own repo or a monorepo subfolder?

- **A subfolder is allowed.** The portal has a "Plugin path (optional)" field. "The repository doesn't have to be dedicated to the plugin… the directory reads and scans only that folder" ([submit](https://claude.com/docs/plugins/submit)).
- **A marketplace repo is allowed.** "In a marketplace repository with several plugins, validate and submit each plugin folder on its own" ([checklist](https://claude.com/docs/plugins/pre-submission-checklist)). The same folder can be listed in your own `.claude-plugin/marketplace.json` too.
- **The catches:**
  1. The size and count limits apply to the **whole repository**. That alone rules out this monorepo at 151.9 MiB.
  2. When the plugin is a subfolder, the hook and MCP command-form rule tightens from Held to **Blocks** (row 24).
  3. In a subfolder, scripts the validator can't follow are always Held. The docs' own advice is to "keep the plugin at the root of its own repository".
- **Verdict:** use a dedicated repo, for example `renchris/<name>-skills`, with the plugin at the root. You can still add a `marketplace.json` with `"source": "./"` so one repo serves both channels ([CC publish](https://code.claude.com/docs/en/plugins/publish)).

### (d) Accepted components, and how unsupported ones are treated

- **The directory accepts** "skills, commands, agents, hooks, and MCP server references" in a bundle ([publish](https://claude.com/docs/directory/publish)). LSPs, output styles, `settings`, `bin/` and `userConfig` prompts are Claude Code-only.
- **Skills cannot be submitted alone.** "Skills aren't a submission type on their own. Put them in a bundle." MCPB and desktop extensions are no longer accepted as listings ([publish](https://claude.com/docs/directory/publish)).
- **Per-surface behavior** ([platform-support](https://claude.com/docs/plugins/platform-support)):
  - **Chat:** skills load and commands load as skills. Agents, hooks, local MCP, LSP and settings are **silently ignored**.
  - **Cowork:** skills, commands, agents, hooks and local MCP load, with local MCP only when the session runs on your computer.
  - **Claude Code:** loads everything.
  - A top-level `bin/` makes Chat and Cowork **refuse the whole plugin**. `${user_config.*}` MCP entries are ignored on Chat (when in the URL) and on Cowork (when there is no default).
  - "The portal derives the surfaces it supports from these same rules and shows them to you before you submit." The listed surfaces can be changed later on the Settings tab ([after-publishing](https://claude.com/docs/connectors/building/after-publishing)).
- **Directory installs reach Claude Code via account sync** as `<name>@synced`. Skills, agents, hooks, MCP and LSP load "with the same trust as a marketplace plugin" ([loading](https://code.claude.com/docs/en/plugins/loading#synced-plugins)). The directory is **not** browsable in `/plugin` ([platform-support](https://claude.com/docs/plugins/platform-support)).

## 3. Directory vs a self-hosted GitHub marketplace

| Dimension | Anthropic directory (portal) | Self-hosted GitHub marketplace (`.claude-plugin/marketplace.json`) |
|---|---|---|
| Reach and discovery | **Discover** tab in Customize > Plugins on claude.ai, desktop, mobile and Cowork, for Pro, Max, Team and Enterprise. Team and Enterprise Owners can remove the directory as a source. Also syncs into Claude Code as `@synced`. The listing gets search. ([publish](https://claude.com/docs/directory/publish), [platform-support](https://claude.com/docs/plugins/platform-support)) | No discovery; users must know the repo. Claude Code: `claude plugin marketplace add owner/repo`, then `install name@mkt` ([CC publish](https://code.claude.com/docs/en/plugins/publish)). **Also works on claude.ai and Cowork** via Add > Add marketplace (GitHub, GHE, public GitLab or Bitbucket; up to 25 self-added marketplaces per account), and those plugins sync to Claude Code too ([plugins overview](https://claude.com/docs/plugins/overview)). |
| Review | Automated validation plus a security scan on **every version**, and **human review of a new listing**. Held findings need a reviewer. A failed first scan means rejection. Policy and Terms bind the listing, and review continues after listing. ([publish](https://claude.com/docs/directory/publish), [checklist](https://claude.com/docs/plugins/pre-submission-checklist)) | None. Users see a warning that Anthropic's review "doesn't cover a plugin you add from a marketplace URL… add those only from sources you trust" ([overview](https://claude.com/docs/plugins/overview)). Hooks, bash, macOS-only code and transcript access are all unconstrained. Only `claude plugin validate` syntax checks and reserved marketplace names apply ([marketplace-reference](https://code.claude.com/docs/en/plugins/marketplace-reference)). |
| Hard requirements | LICENSE, README of 40 or more words, repo under 50 MiB as an archive, public repo to publish, paid plan, name rules | `marketplace.json` plus `plugin.json`. No license, size or README gate. Claude.ai plugin limits are 5,000 files and 200 MB. |
| Analytics | **Usage** tab covering up to 90 days, exportable as CSV. **Reach**: installs, active accounts and retention, with installs by surface and by source. **Versions**: share on each version. **Components**: runs of each skill, command, agent, hook and MCP. **Quality**: load errors by Claude Code version, plus MCP calls, error rate and latency. **Funnel**: views, install clicks, installs. Data is refreshed daily in UTC. ([after-publishing](https://claude.com/docs/connectors/building/after-publishing)) | **None for the author.** "Claude Code doesn't report a plugin's usage back to its author." Only an organization admin's OpenTelemetry or Analytics API gives figures, and only for their own fleet ([CC measure](https://code.claude.com/docs/en/plugins/measure)). GitHub stars and clones are the only proxy. |
| Update flow | Push to the tracked branch or tag. A webhook or scheduled check picks it up, every commit is re-scanned, and it is published per the publish setting. The default is that **a reviewer publishes each version**; auto-publish can be granted. A failing or held version leaves the last published version live. A failed security scan makes later versions wait for a reviewer. Bump `version`. ([submit](https://claude.com/docs/plugins/submit)) | Push. Users get it with `claude plugin update` or with auto-update, which is **off by default** for third-party marketplaces. Claude.ai gets it via "Check for updates" or "Sync automatically". Bump `version` or omit it so the commit SHA is used. ([CC publish](https://code.claude.com/docs/en/plugins/publish), [overview](https://claude.com/docs/plugins/overview)) |
| Surfaces | Chat, Cowork and Claude Code, filtered by which components each supports. The portal shows the derived surfaces, and listed surfaces are editable. | Same component rules per surface, since they are enforced by the client and not the channel ([platform-support](https://claude.com/docs/plugins/platform-support)). |
| Speed to first user | Review time "isn't fixed" ([submission-status](https://claude.com/docs/directory/submission-status)) | Immediate once `marketplace.json` is pushed |
| Removal | Delist and Relist are requests; installed copies stop updating and may be removed | Delete the entry, or use a `renames` map |
| Anthropic's official marketplace (`claude-plugins-official`) | Not reachable via the portal. "ask [an Anthropic partner contact] about an official-marketplace listing" ([CC publish](https://code.claude.com/docs/en/plugins/publish)) | Not applicable |

## 4. Recommended shape (inference, grounded in the rows above)

1. **Self-hosted marketplace for the full infrastructure.**
   - This covers the hooks, `bin/`, launchd jobs and multi-account tooling.
   - It is the only channel where transcript-reading, permission-deciding, macOS-only, ungated hooks are acceptable.
   - It can live in the current repo with a root `.claude-plugin/marketplace.json`. Still add a LICENSE.
2. **Directory listing only for a carved, portable skills bundle, in a new repo.**
   - Candidates are the skills that make no machine-specific references: `agent-browser`, `autonomous-authenticated-web-access`, `coding-standards`, `demo-recording`, `dia-agent`, `grok-wiki-cli`, `grok-wiki-custom`, `ground-up`, `manual-command-delivery`, `plan-conventions`, `read-twitter`, `repo-wiki`, `self-explaining-artifact` and `video-understanding`.
   - Include no hooks, no `bin/` and no MCP.
   - Add a LICENSE, a disclosure README with three example prompts, and a distinctive name.
   - Before including them, check `dia-agent` (drives the operator's logged-in browser and reads cookies) and `autonomous-authenticated-web-access`. The official rubric flags browser cookie and login-store access routed across services. Disclose it or drop them.
3. Run `claude plugin validate --strict`, then the portal **Validate**. It can run without submitting, and on a public repo it does not need GitHub connected ([submit](https://claude.com/docs/plugins/submit)).

## 5. Adversarial pass: gaps probed and what they changed

- **"The subfolder route avoids the size limit."** Refuted. The checklist phrases the limit as a limit on "the repository". Measuring the archive (151.9 MiB) turned this into the main blocker.
- **"The screenshot says the license is only recommended, so it's optional."** Refuted by the checklist, where `License missing` is Blocks. Recorded as a discrepancy rather than resolved. **[unknown]** Whether the live portal's severity differs from the docs.
- **"The directory scan is unknown, so the hooks might pass."** The published official-marketplace scan prompt gives a concrete rubric that fails ungated tool and prompt hooks. Policy §1.F independently rules out transcript reads. Both point the same way.
- **"Cowork will run the bash hooks."** Only partly. Cowork loads hooks, but runs tools in a workspace VM with egress allowlists (Cowork changelog). **[inference]** macOS binaries are unavailable there.
- **Not verified:**
  - Case-collision and colon checks across all 7,027 paths.
  - Per-skill YAML front-matter validity.
  - The directory scan's exact prompt, which is not public.
  - Whether `TeammateIdle`, `TaskCompleted` and `WorktreeCreate` are accepted in plugin `hooks.json`.
