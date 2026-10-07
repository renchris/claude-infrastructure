# B3 — Claude Code changelog (cloud/remote/scheduled/headless) and the installed binary

Date of all reads: 2026-10-06. Sources:
- CHANGELOG: https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md, fetched 2026-10-06, saved at `/tmp/cloud-blog-eval/CHANGELOG.md` (8497 lines; newest header `## 2.1.292`). "L<n>" below is the line number in that saved copy.
- npm registry `@anthropic-ai/claude-code` (dist-tags and publish times, `curl https://registry.npmjs.org/@anthropic-ai/claude-code`, 2026-10-06).
- Binaries run with `--version` / `--help` only; plus `strings` over the 2.1.284 and 2.1.291 executables (read-only). Saved: `help-284.txt`, `help-homebrew-291.txt`, `strings-284.txt` in `/tmp/cloud-blog-eval/` (the 2.1.291 strings dump was a scratch file and was deleted after the option diff; regenerate with `strings -n 6` on the Homebrew binary).
- Repo (read-only): `skills/cc-upgrade/holds.md`, `~/.claude-versions/MANIFEST.jsonl`, `model-config.yaml`, `bin/cc-claude-bin`.

Labels: **measured** = I ran the named command; **documented** = a primary source states it; **inferred** = my reasoning.

---

## 0. Headline

- Nothing in 2.1.281–2.1.292 adds a new cloud *dispatch verb*. `--cloud`, `--teleport`, `--environment`, `-p ... --cloud <id>` all exist already in the pinned 2.1.284 (and in 2.1.260/2.1.280). The band is almost entirely **reliability fixes to cloud sessions and routines**, plus two behaviour changes that bite a headless dispatcher (background-command time limit; `gh api` host refusal).
- The cloud rows of the changelog have **never been audited** by cc-upgrade: the 2.1.281–284 audit filed them as "NEUTRAL: out of scope ... not referenced by our config", and `holds.md` contains zero cloud/routine/teleport verdicts.
- `holds.md` says "Target 2.1.289". The changelog since then shows 2.1.289 still carries a 2.1.288 regression (session's last messages lost on quit), fixed only in 2.1.291; and 2.1.290 introduced a cloud regression (dropped permission answers), also fixed in 2.1.291. For a cloud lane the first clean candidate is **2.1.291 or 2.1.292**, not 2.1.289 (inferred from fix placement; ungated).

---

## 1. What version did we run before 2.1.284?

| Fact | Evidence | Label |
|---|---|---|
| Fleet pin today is `~/.claude-284/node_modules/.bin/claude`, reports `2.1.284 (Claude Code)` | `~/.zshrc:502` (`local _bin="$HOME/.claude-284/..."`); `$HOME/.claude-284/node_modules/.bin/claude --version` | measured |
| Prior fleet pin was **2.1.280** (2026-09-22 to 2026-09-28) | MANIFEST row 2.1.284, 2026-09-28T20:06:52Z: "FLEET PIN ADVANCES 2.1.280 -> 2.1.284 via docs/activation/pending-activation/47-sonnet55-cc284-activate.sh"; `model-config.yaml:105` "CLEARED 2026-09-22: launcher repointed to 2.1.280" | documented |
| Before that: **2.1.260** (running since 2026-09-03), before that 2.1.220 (staged 2026-08-01) | MANIFEST rows 2.1.260 (2026-09-08) and 2.1.220 (2026-08-01); dirs `~/.claude-219/-220/-260/-280/-284` exist | documented + measured (`ls -d ~/.claude-2*`) |
| A **second, unpinned** `claude` sits on PATH: `/opt/homebrew/bin/claude` = **2.1.291**, symlink dated Oct 6 01:32 | `/opt/homebrew/bin/claude --version` | measured |
| `bin/cc-claude-bin` falls back to PATH `claude` only at rung 4 (after `$CC_CLAUDE_BIN`, zshrc `_bin=`, newest `~/.claude-NNN`, `claude-latest`) | `bin/cc-claude-bin` header, ORDER block | documented |
| `~/.local/share/claude/versions` does not exist; no native-installer build on this box | `ls` | measured |
| A third stale launcher `/Users/chrisren/Library/pnpm/claude` points at `@anthropic-ai/claude-code@2.0.5` | `head` of the wrapper | measured |

So band (a) = **2.1.281–2.1.284** (the prior-pin delta). Band (b) = **2.1.285–2.1.292**.

### Release timeline (npm publish time, measured via registry JSON 2026-10-06)

| Version | Published (UTC) | Note |
|---|---|---|
| 2.1.280 | 2026-09-22 15:44 | prior pin |
| 2.1.281 | 2026-09-23 17:01 | |
| 2.1.282 | 2026-09-24 15:56 | |
| 2.1.283 | 2026-09-25 18:46 | |
| 2.1.284 | 2026-09-28 17:11 | **current fleet pin** |
| 2.1.285 | 2026-09-29 17:32 | npm dist-tag `stable` |
| 2.1.286 | 2026-09-30 17:14 | |
| 2.1.287 | 2026-10-01 16:59 | |
| 2.1.288 | 2026-10-02 18:30 | |
| 2.1.289 | 2026-10-03 20:12 | holds.md's named target |
| 2.1.290 | 2026-10-05 18:12 | |
| 2.1.291 | 2026-10-06 03:32 | on PATH via Homebrew |
| 2.1.292 | 2026-10-06 17:10 | npm `latest` and `next`; ~hours old at this read |

npm dist-tags: `{'stable': '2.1.285', 'latest': '2.1.292', 'next': '2.1.292'}`. Note `stable` = 2.1.285, the release holds.md says never to run (30-min background cap in every session).

---

## 2. What the installed binary accepts (measured)

### 2.1 `--help` of the pinned 2.1.284 (`/tmp/cloud-blog-eval/help-284.txt`)

| Flag / command | Present in `--help`? | Help text (verbatim) |
|---|---|---|
| `--cloud [description\|session_id\|url]` | **yes** (help-284.txt:70) | "Create a cloud session with the given description, or attach to an existing one by session ID or claude.ai/code URL" |
| `--remote` | **no** in `--help`; **hidden alias in the binary** | strings: `new is("--remote [description\|session_id\|url]","Deprecated alias for --cloud").hideHelp()` |
| `--teleport [session]` | **yes** (help-284.txt:251) | "Resume a teleport session, optionally specify session ID" |
| `--environment <environment_id>` | **yes** (help-284.txt:89) | "Create a new cloud session that runs on the given self-hosted environment (ccpool_...)." |
| `--remote-control [name]` | yes (:189) | "Start an interactive session with Remote Control enabled (optionally named)" — a different feature (local session driven from the app), not a cloud VM |
| `--bg, --background` | yes (:33) | "Start the session in the background and return immediately. Prints the id that `claude attach`, `logs`, `stop` and `rm` take; `claude agents` lists them. With --resume <session-id>, continues that session in the background under the same ID, or starts a copy and says so when the session is already running" |
| `--from-pr [value]` | yes (:114) | "Resume a session linked to a PR by PR number/URL, or open interactive picker with optional search term" |
| Subcommands | `agents`, `attach <id>`, `logs <id>`, `stop\|kill <id>`, `rm <id>`, `respawn [id]`, `ultrareview`, `setup-token`, `auth`, `mcp`, `plugin`, `project`, `doctor`, `gateway`, `import`, `install`, `update` | No `routine`, `schedule`, `cloud`, `trigger` or `teleport` subcommand exists. |
| `claude agents --json` | yes (`agents --help`) | "Print active sessions (interactive and background) as a JSON array and exit (for scripting; does not require a TTY)"; `--all` "With --json: also include completed background sessions" — local background sessions only; nothing in the help says it lists cloud sessions |
| `claude ultrareview` | yes | "Run a cloud-hosted multi-agent code review of the current branch (or a PR number / base branch) and print the findings"; `--json`, `--post`, `--timeout <minutes>` (default 45) |

### 2.2 Hidden cloud options in the 2.1.284 binary (measured: regex over `strings-284.txt` for commander option definitions; all carry `.hideHelp()`)

| Hidden option | Description string (verbatim) | Dispatcher relevance |
|---|---|---|
| `--ref <ref>` | "Branch, tag, or SHA to check out in the remote session; defaults to local current branch. Requires --cloud or --environment." | pin the base a cloud row starts from instead of the caller's current branch |
| `--on-branch <branch>` | "Work directly on <branch> in the remote session (checkout and push to it). On self-hosted environments this includes pushing to the default branch when it is not protected — use GitHub branch protection to restrict. Mutually exclusive with --ref. Requires --cloud or --environment." | makes the session push to a named branch rather than a fresh `claude/...` branch; contradicts the blog digest's "each task gets a new branch" as an absolute |
| `--forward-home-settings <true\|false>` | "Whether this launch sends this machine's settings (CLAUDE.md, rules, output styles, preferences, portable permission rules) into the cloud session it creates or attaches to: false = not this launch; true = yes for this launch, standing in for the machine's stored choice (not saved). Requires --cloud or --environment." | the digest says "personal ~/.claude does not travel"; the binary has an opt-in that forwards part of it. Unprobed. |
| `--correlation-id <id>` | "Opaque id echoed back to the environment orchestrator on the work order (requires --environment)." | self-hosted environments only |
| `--pool <pool_id>` | "Deprecated alias for --environment" | |
| `--attach-serve <session_id>` | "Attach a serve-only helper to a bound cloud session (spawned by the desktop app; not for interactive use)." | not for us |
| `--routine` | appears in the launcher's argv allow-list next to `--bg`/`--background`, and `--project-config-root` help says ".claude config trees (commands, agents, skills, workflows, routines, output-styles; --routine is refused with this flag)"; `**/.claude/routines/.state/` is in the runtime git-exclude list | a **local** routine concept (`.claude/routines/`) exists in the binary behind a gate; no help text; unprobed |

Error strings in 2.1.284 that define the argv grammar (measured, strings):
- `Error: --cloud requires a description. Usage: claude --cloud "your task description"`
- `Error: Attaching to an existing cloud session is not enabled for your account.` (attach is account-gated)
- `Error: --environment does not support --output-format stream-json`
- `Error: --environment cannot be combined with --resume, --continue, or --teleport`
- `Error: --ref sets the base for a new cloud session; it cannot be combined with --cloud <session_id|url>`
- `Error: --on-branch and --ref both set the cloud session's base branch; pass one or the other`
- internal flag names `cloudPrintEnabled`, `isCloudAttach`, `cloudSessionsByDefault`, `cloudDefault` exist (print-mode cloud is a gated capability, consistent with the repo's validated `claude -p "<msg>" --cloud <id> --output-format json`, `bin/cc-notify:120,737`).

### 2.3 Other blog-named surface, checked in 2.1.284 strings (measured, `grep -c` on `strings-284.txt`)

| Blog item | In 2.1.284? | Evidence |
|---|---|---|
| `CLAUDE_CODE_REMOTE` | yes, 193 occurrences; siblings `CLAUDE_CODE_REMOTE_SESSION_ID` (66), `CLAUDE_CODE_REMOTE_ENVIRONMENT_TYPE` (14), `CLAUDE_CODE_REMOTE_MEMORY_DIR` (12), `CLAUDE_CODE_REMOTE_SESSION_ORIGIN` (4) | strings count |
| `Claude-Session` commit trailer | yes; controlled by `attribution.sessionUrl`: "Whether to append the claude.ai session link to commits and PRs created from web or Remote Control sessions (default: true). Set to false to omit the Claude-Session trailer and PR-body link." | strings; settings schema text |
| `/claim-credit` | yes, registered as a command (`"claim-credit":"action"`, `KOt="claim-credit"`) | strings (3 hits) |
| `/autofix-pr`, `/web-setup`, `/teleport`, `RemoteTrigger` | yes (15 / 29 / present / 5 hits) | strings |
| `/schedule`, `/remote-env` | named as CLI commands by the changelog (2.1.285 L653, L642; 2.1.292 L34) | documented |

The CHANGELOG never announces `--cloud` (grep `--cloud` over all 8497 lines: zero hits) nor `Claude-Session` nor `/claim-credit` nor `CLAUDE_CODE_REMOTE`. The rename is visible only at 2.1.274 L1608: "Changed the `/status` GitHub line to read "Cloud sessions", and `/web-setup`, `/ultrareview`, and teleport messages to say "cloud session" instead of "Claude Code on the web"". **The changelog is therefore not a complete instrument for cloud flags; the binary is.**

### 2.4 Across installed versions (measured, `--help | grep`)

| Binary | `--cloud` | `--environment` | `--teleport` | `--bg` |
|---|---|---|---|---|
| `~/.claude-220` (2.1.220) | not in help (repo: "present-but-hidden", `bin/cc-notify:133`) | no | not in help | yes |
| `~/.claude-260` (2.1.260) | yes | yes | yes | yes |
| `~/.claude-280` (2.1.280) | yes | yes | yes | yes |
| `~/.claude-284` (2.1.284) | yes | yes | yes | yes |
| `/opt/homebrew/bin/claude` (2.1.291) | yes | yes | yes | yes |

### 2.5 2.1.284 vs 2.1.291 help diff (measured, `diff help-284.txt help-homebrew-291.txt`)

- 2.1.291 adds `--desktop` ("Open in the Claude Desktop app instead of the terminal (with --continue or --resume <id> to pick the session)").
- 2.1.291 `attach <id|name>` / `logs <id|name>`: "Part of the session name works too".
- 2.1.291 replaces subcommand `project` (whose only child was `purge`) with top-level `purge [options] [path]`.
- 2.1.291 `--help` no longer lists `--client-data-url`.
- Option-definition diff over both `strings` dumps (151 vs 154 definitions): the only additions are plugin options (`--data-size`, `--replace`, `--values-stdin`); **no cloud option was added, removed, or reworded between 2.1.284 and 2.1.291**. Cloud CLI grammar is unchanged across band (b) up to 2.1.291. (2.1.292 binary not installed here; not checked.)

---

## 3. Reading rule for the changelog rows (inferred)

Three kinds of row, which differ in whether our local pin gates them:

| Row shape | Where the change lives | Does our 2.1.284 pin gate it? |
|---|---|---|
| Prefixed `[Cloud sessions]` / `[Claude Code on the web]` | the claude.ai/code web product and its backend | **No** — arrives regardless of our pin (inferred from the prefix convention; the changelog does not state deployment mechanics) |
| Unprefixed "Fixed cloud sessions ..." about container restarts, transcripts, workers | the Claude Code process running **inside the cloud VM** | **Probably no** — depends on the version the cloud image runs, which we do not choose (inferred; unverified which version a cloud VM runs) |
| Rows naming `claude --cloud`, `/teleport`, `/remote-env`, `/autofix-pr`, `/schedule`, `claude -p`, `--bg`, `claude agents` | the local CLI | **Yes** |

Consequence: most of the cloud reliability fixes below already benefit the cloud lane without an upgrade; the upgrade question reduces to the short "local CLI" lists in 4.1 and 5.1.

---

## 4. Band (a): 2.1.281 – 2.1.284 (prior pin 2.1.280 → current pin). Already on the box.

### 4.1 Local-CLI rows relevant to a dispatcher

| Ver | L | Verbatim | Why it matters |
|---|---|---|---|
| 2.1.281 | 1074 | "Fixed `--input-format stream-json` sessions (Agent SDK, VS Code extension) and scheduled cloud sessions failing every turn with an error when an earlier assistant message had plain-string content" | scheduled cloud sessions could fail every turn before this |
| 2.1.281 | 1076 | "Fixed headless sessions with host-side (SDK) MCP servers stalling on the first message when the host stops responding mid-handshake; remote sessions now wait a few seconds at most" | first-turn stall in headless fires |
| 2.1.281 | 1075 | "Fixed non-interactive sessions (`-p`, Agent SDK) failing on the next turn after the directory they were started in was deleted mid-session" | worktree-removal race in `-p` |
| 2.1.281 | 1058 | "Fixed a turn that could retry indefinitely, ignoring `--max-turns`, when the model alternated unparseable tool calls and output-limit truncation" | runaway bound on unattended runs |
| 2.1.281 | 1085 | "Fixed `claude --bg` starting a background session, and running its project hooks, in a directory that had not passed the workspace trust prompt; it now asks for trust first, or exits when not run interactively" | `--bg` from a daemon in an untrusted dir now exits |
| 2.1.281 | 1086 | "Fixed `--setting-sources` (and SDK `settingSources`) not being forwarded to spawned sessions: teammates, `/bg`, `claude agents` sessions and `--worktree --tmux` now start with the parent's restriction" | spawned sessions inherit the restriction |
| 2.1.281 | 1093 | "Fixed scheduled tasks and `/loop` wakeups being fired again every second when their delivery failed, which could make Claude Code exit at the end of a turn" | local scheduler storm |
| 2.1.281 | 1184 | "Changed the dangerous `rm` prompt in `--dangerously-skip-permissions` and auto mode to wait 2 minutes for an answer, then deny the command with a rewrite hint so unattended sessions keep going (`CLAUDE_CODE_DISABLE_DANGEROUS_RM_TIMEOUT=1` turns this off)" | unattended sessions no longer hang on `rm`; already carried as a holds.md caution |
| 2.1.281 | 1187 | "Changed self-hosted runners to pass system prompts to Claude Code as private files instead of command-line text ... a wrapper or `command` hook that appends `--system-prompt` or `--append-system-prompt` must switch to `--system-prompt-file` or `--append-system-prompt-file`" | only if self-hosted runners are ever used |
| 2.1.281 | 1052 | "Added `"attribution": false` in `settings.json` to hide all commit and PR attribution; older CLI versions skip a settings file that holds it, so keep the object form in files shared across versions" | settings shared with a cloud VM on a different version: use the object form (`sessionUrl` lives in this block) |
| 2.1.281 | 1159 | "Improved `--agents` to accept the path to a JSON file (with `-p`) as well as inline JSON, and to allow an empty `prompt`" | headless argv size |
| 2.1.282 | 965 | "Fixed more cases of continued or resumed sessions (`--continue`, `--resume`) re-sending earlier messages in a changed form, which could make the API drop Claude's earlier reasoning" | resume fidelity |
| 2.1.282 | 977 | "Fixed a command approved on a restored permission prompt running twice when a remote session's worker restarted" | double-execution in remote sessions |
| 2.1.283 | 922 | "Improved startup: `claude -p` and Claude Code Remote no longer load the interactive UI, and the auto-mode classifier's rules and the Artifact tool load on first use instead of at launch" | faster headless fires |
| 2.1.283 | 868 | "Added `path` to `--plugin-dir` load-failure entries in the stream-json `system/init` `plugin_errors`, naming the directory that did not load" | headless diagnostics |
| 2.1.284 | 771 | "Fixed a session whose model is unavailable, with no fallback model left, showing a bare "is currently unavailable" message (or "Something went wrong" in cloud sessions) instead of the model-unavailable notice and its Learn more link" | failure text a watcher may key on changed |
| 2.1.284 | 826 | "Changed `/recap` to decline with a short notice when it arrives relayed from a chat thread (your own included) or from a routine or webhook; typed in the terminal, the Claude apps, Remote Control, `-p` or an SDK host, it runs as before" | a routine prompt cannot invoke `/recap` |
| 2.1.284 | 820 | "Changed interactive terminal and VS Code sessions to start in auto mode when no permission mode is configured, on every plan and provider; `permissions.defaultMode` still overrides it" | default flip; fleet pins `auto` already |

### 4.2 Server-side / in-VM rows (arrive without our pin; inferred per §3)

| Ver | L | Verbatim | Why it matters |
|---|---|---|---|
| 2.1.280 | 1283 | "Fixed cloud and self-hosted runner sessions failing with "Authentication failed" after waiting out a long overload during which the session's access token was rotated" | long-running cloud rows |
| 2.1.280 | 1329 | "[Claude Code on the web] Fixed a routine that resumes an existing session running with its old prompt and name when it was edited moments before the scheduled run started" | edit-then-fire race on routines |
| 2.1.280 | 1327 | "[Claude Code on the web] Changed the admin Routines on/off setting to live under Admin settings → Capabilities → Remote sessions" | where the switch is |
| 2.1.281 | 1091 | "Fixed cloud sessions not telling Claude about background agents that finished just before a worker restart" | lost subagent results in a cloud VM |
| 2.1.281 | 1092 | "Fixed scheduled routine and notification turns in remote sessions not receiving turn-start notices (newly available tools, MCP changes, date, todos) until after the first tool call" | routine turns lacked date/tool context |
| 2.1.281 | 1090 | "Fixed remote sessions staying on "needs approval" with a stale prompt after a permission prompt and a sandbox network-access prompt overlapped and both were answered" | a cloud row stuck in needs-approval |
| 2.1.281 | 1207 | "[Claude Code on the web] Fixed routines with a GitHub trigger for a pull request being converted to draft never firing; they now start a run when the pull request is converted" | confirms GitHub PR-event triggers exist as a primary-source fact |
| 2.1.281 | 1208 | "[Claude Code on the web] Fixed cloud sessions on a repository that isn't hosted on GitHub showing a Create PR button that could never work; the button is now hidden there" | non-GitHub hosts are supported for sessions |
| 2.1.282 | 1029 | "[Cloud sessions] Added Claude GitHub App status to Settings › Connectors › GitHub: whether the app is installed and reachable for your account, plus steps to connect, install or reconnect" | observable precondition for auto-fix/triggers |
| 2.1.282 | 1031 | "[Cloud sessions] Added attaching a repository from a different GitHub owner, such as a fork's upstream, to a running cloud session that already has one, including sessions started from Slack" | multi-repo sessions |
| 2.1.282 | 1032 | "[Cloud sessions] Fixed the next run time shown for an hourly routine being 30 minutes off for people in half-hour-offset time zones such as India" | confirms hourly routines |
| 2.1.283 | 945 | "[Cloud sessions] Fixed cloud sessions occasionally redoing an already-finished step, such as posting a duplicate comment or push, after recovering from a server-side restart" | **duplicate side effects** after a restart: a dispatcher's idempotency guard was load-bearing before 2026-09-25 |
| 2.1.283 | 946 | "[Cloud sessions] Changed new routine schedules to default to a few minutes past the hour, with a note that routines set exactly on the hour can start several minutes late" | **on-the-hour routines start late**; do not design an exact-time contract around a schedule trigger |
| 2.1.283 | 944 | "[Cloud sessions] Improved adding a repository to a running cloud session: a private repository your GitHub account can read but not push to now attaches for reading" | read-only attach |
| 2.1.283 | 894 / 2.1.285 L646 | first-words latency in cloud sessions, regressed in 283, fixed in 285 | cosmetic |

---

## 5. Band (b): 2.1.285 – 2.1.292 (not on the fleet pin)

### 5.1 Local-CLI rows — these are what an upgrade would buy or cost

| Ver | L | Verbatim | Why it matters |
|---|---|---|---|
| 2.1.285 | 704 | "Changed background Bash and PowerShell commands to stop after a time limit (their `timeout` with `run_in_background`, default 30 min, max 2 h); Claude is notified when one is stopped" | **COST**: any background Bash waiter over 30 min is cut (holds.md: the 3300 s `cc-await-ping` arm) |
| 2.1.288 | 402 | "Changed the background command time limit to apply only in unattended sessions (`-p`, Agent SDK, CI, cloud); terminal, desktop app and VS Code sessions have no limit" | the cap **stays** for exactly the dispatcher's surfaces: `-p` fires and cloud VMs. A cloud row cannot hold a background command past 30 min default / 2 h max. Applies inside cloud VMs regardless of our pin (inferred, §3). |
| 2.1.292 | 22 | "Fixed one-shot `claude -p` and Agent SDK runs stopping a background command 5 seconds after the final result, and one-shot `claude -p` runs dropping a scheduled wakeup; both are now waited for" | `-p` fires that start background work lose it on ≤2.1.291 |
| 2.1.285 | 642 | "Fixed cloud session creation and `/remote-env` reading only the newest 20 of an account's environments" | **on 2.1.284, `claude --cloud` sees only the newest 20 environments** — a named/default environment older than the 20 newest is invisible to the dispatcher (bites only if the account has >20) |
| 2.1.285 | 653 | "Fixed `/autofix-pr` and `/schedule` saying the Claude GitHub App is not installed on a repository whose install status had not been checked yet" | false "not installed" from `/autofix-pr` and `/schedule` on 2.1.284 |
| 2.1.285 | 634 | "Fixed SSH passphrase and new-host prompts from worktree and `/teleport` fetches taking over the terminal; these fetches now fail fast instead of asking" | unattended teleport no longer hangs on an SSH prompt |
| 2.1.285 | 699 | "Improved `/resume` and `claude --resume` on a session that is running in the background: they now open that session instead of refusing, and a prompt given with `claude --resume <id> "prompt"` is sent to it as its next turn" | a scriptable way to send a turn to a running local background session |
| 2.1.285 | 636 | "Fixed `claude -p --permission-prompt-tool`: a background subagent's permission request now goes to the prompt tool instead of being auto-denied" | headless permission routing |
| 2.1.285 | 626 | "Fixed `claude -p` with `CLAUDE_CODE_FORK_SUBAGENT=1`: a subagent's own Agent call now runs in the foreground, so the subagent gets the child's result" | |
| 2.1.285 | 673 | "Fixed `CLAUDE_CODE_RESUME_INTERRUPTED_TURN` re-running a turn that had ended at `--max-turns`" | |
| 2.1.285 | 710 | "Changed `claude -p` and Python Agent SDK sessions on third-party providers or with telemetry off to start in auto mode when no permission mode is configured, like interactive sessions; `--permission-mode` still overrides it" | default flip for `-p`; fleet has `DISABLE_AUTOUPDATER`/telemetry settings worth checking against this |
| 2.1.285 | 712 | "Changed the MCP server name `widgets` to be reserved in cloud sessions and on self-hosted runners: your own server under it, or a close spelling such as `widgets_`, no longer loads, so rename it" | a repo `.mcp.json` server named `widgets` silently stops loading in the cloud |
| 2.1.285 | 750 | "[Cloud sessions] Changed `MCP_DISCOVERY_CACHE=1`, when set in your cloud environment's variables rather than a settings file, to reuse your connectors' tool lists after a session restart; other MCP servers are no longer cached and connect at startup" | an environment-variable knob for cloud restart latency |
| 2.1.285 | 620 / 625 | "Added `CLAUDE_CODE_DISABLE_WEB_FETCH`..."; "Added `CLAUDE_CODE_NONSTREAMING_TIMEOUT_RETRIES` environment variable to cap re-sends of a non-streaming fallback request that timed out" | unattended retry bound |
| 2.1.286 | 532 | "Fixed `claude --resume` and `--continue` sometimes losing every turn after a batch of parallel tool calls when the earlier session crashed or was killed" | resume after a kill |
| 2.1.286 | 558 | "Fixed Workflow tool subagents being restarted from their original prompt when a connection stalled for a few minutes mid-response" | |
| 2.1.287 | 461 | "Fixed a revoked claude.ai login showing a generic `API Error: 401` instead of "OAuth token revoked"; in `-p` mode the error now starts with "Failed to authenticate"" | **text a watcher greps changes** (holds.md already flags `MASTER_ACCOUNT_FACTS.md:141-142`) |
| 2.1.287 | 437 | "Fixed `claude -p` and SDK sessions repeating a model fallback on every later message after the model was switched while a reply was running" | |
| 2.1.287 | 492 / 476 | "Improved MCP startup in headless mode: a remote server whose first connect fails transiently is now retried without waiting for the slowest server to finish connecting"; "Fixed headless sessions reporting an MCP server as needing authentication after one refused call, even though later calls succeed" | headless MCP reliability |
| 2.1.287 | 499 | "Changed replies from `claude agents` to arrive as queued messages; slash commands other than `/stop` sent while a turn is running now run when it ends" | changes message-injection semantics for local background sessions |
| 2.1.288 | 361 | "Fixed unattended sessions (`CLAUDE_CODE_RETRY_WATCHDOG`) retrying for hours after a very long response stream failed; Claude Code now streams again, and gives up after three timeouts" | hours-long silent retry on ≤2.1.287 |
| 2.1.288 | 366 | "Fixed headless (`-p` / SDK) sessions occasionally ignoring SIGTERM when a supervisor such as `timeout` or systemd sends SIGCONT alongside it" | a `timeout`-wrapped `-p` fire may not die on ≤2.1.287 |
| 2.1.288 | 359 | "Fixed permission asks that ended unanswered, in `-p` or on an interrupted turn, emitting no `tool_decision` event" | observability |
| 2.1.288 | 337 / 338 | "Fixed `--resume` sometimes dropping files and other context that a compaction had just restored"; "Fixed a resumed session sometimes not saving the last response of a turn, so that the next `--resume` showed the prompt unanswered" | |
| 2.1.290 | 125 | "Fixed headless `--json-schema` runs exiting non-zero with `is_error: true` on a `success` result when the connection dropped after the structured output was already delivered" | a dispatcher keying on exit code misreads a success on ≤2.1.289 |
| 2.1.290 | 169 | "Fixed `claude --teleport` and `/teleport` deleting the files in a folder that had replaced a tracked file of the same name when you chose to stash: the stash is now refused, and says why" | **data loss in teleport on ≤2.1.289** |
| 2.1.290 | 236 | "Improved the error shown when a cloud session is started without a claude.ai sign-in: it now names `claude auth login` and /login and no longer blames API-key authentication" | error text a dispatcher may parse |
| 2.1.290 | 265 | "Changed the built-in `gh api` in cloud sessions: a host other than github.com set in `GH_HOST` or `GH_REPO` is now refused (use `--hostname` or a full URL), and stderr notes requests to other hosts" | behaviour change inside the VM |
| 2.1.290 | 267 | "Self-hosted runners: Changed `claude --environment <id>` to create its session through the current Sessions API; printed and JSON session ids keep their session_… form" | id format stable |
| 2.1.290 | 199 | "Fixed artifact operations failing in a Claude Code run started from inside a cloud session (for example `claude -p` run from the Bash tool)" | primary-source confirmation that nested `claude -p` inside a cloud session is a supported shape |
| 2.1.290 | 123 / 124 | scheduled tasks not coming back on resume after compaction; scheduled tasks never firing after a `/background` hand-off, recurring ones firing an extra run on every resume/respawn/fork | local `/loop` correctness |
| 2.1.290 | 254 / 259 | "Changed background sessions whose scheduled task is gone: they now move to Completed about 20 seconds later..."; "Changed background sessions waiting on a scheduled wakeup (`/loop`): they are now left running through updates and low memory..." | local background lifecycle |
| 2.1.290 | 191 | "Fixed background agents failing with "Agent stalled" and Workflow tool subagents restarting from their prompt when a Mac woke from sleep" | a 24/7 Mac host |
| 2.1.291 | 100 | "Fixed a regression in 2.1.290 where cloud sessions could drop answers to permission prompts" | **never run 2.1.290 for cloud** |
| 2.1.291 | 101 | "Fixed a regression in 2.1.288 where the last messages of a session could be lost when quitting" | **2.1.288 and 2.1.289 both carry this** (inferred: 2.1.289's 29 rows, L296-325, contain no such fix) |
| 2.1.292 | 34 | "Fixed `/remote-env` replacing your saved default environment when you pressed Enter right away..." | default environment could be silently changed |
| 2.1.292 | 24 / 25 | saved scheduled tasks created after `/resume`/`/branch`/`/clear` never firing; "Fixed a background session's `/loop` silently stopping when the session's process restarted (for example after a crash), because its pending wakeup was lost" | local scheduler |
| 2.1.292 | 64 | "Improved startup of `claude -p` and SDK sessions: the first turn no longer waits for HTTP and SSE MCP servers to answer `resources/list`" | |
| 2.1.292 | 7 | "Added `CLAUDE_CODE_OVERLOADED_RETRY_BASE_DELAY_MS` environment variable to set a longer base delay for the backoff when retrying an overloaded (529) request" | fleet-wide backoff knob for a 24/7 drain |
| 2.1.292 | 29 | "Fixed the usage limit alert repeating once per background agent when agents failed on a limit that had already stopped the main conversation" | |

### 5.2 Cloud-session / routine rows (server-side or in-VM; inferred not gated by our pin, §3)

| Ver | L | Verbatim | Why it matters |
|---|---|---|---|
| 2.1.285 | 629 | "Fixed cloud sessions that restarted after their conversation was compacted refusing the next update to an artifact the session had already read or published" | |
| 2.1.285 | 749 | "[Cloud sessions] Fixed Run now on a routine showing internal error text when the run is refused before it starts; it now shows the same explanation as the routine's failure notification" | a routine run can be **refused before it starts** (caps) |
| 2.1.286 | 608 | "[Cloud sessions] Fixed routine runs whose cloud session never started showing as Succeeded in the Runs pane, the routine's page and the sidebar; they now show as Failed" | **before 2026-09-30 a routine "Succeeded" status could mean the session never started**; routine status alone was not proof of work |
| 2.1.286 | 610 | "[Cloud sessions] Changed a routine's page to read "Due" with the scheduled time, instead of a next run time in the past, when a scheduled run is late and hasn't started" | scheduled runs can be late |
| 2.1.286 | 534 | "Fixed cloud sessions with very large histories never waking up because the container was stopped while the transcript was still loading" | long cloud rows could not be reopened |
| 2.1.286 | 605 | "[Cloud sessions] Fixed an answered question card or approved tool call getting no reply when the session had gone idle after Claude sent a message" | stuck-after-approval |
| 2.1.286 | 606 | "[Cloud sessions] Fixed clearing an organization environment's setup script in admin settings leaving new cloud sessions still running the old script" | setup-script cache staleness (org environments) |
| 2.1.287 | 470 | "Fixed SessionStart hooks from synced plugins not running in new cloud sessions" | the blog's `SessionStart` + `CLAUDE_CODE_REMOTE` pattern was broken for plugin-provided hooks before this; repo `.claude/settings.json` hooks are not named in the row |
| 2.1.287 | 473 | "Fixed repositories added mid-session in cloud and SDK sessions not loading their skills and plugins, and loading CLAUDE.md late, after Claude changed directory" | |
| 2.1.287 | 466 | "Fixed cloud sessions sometimes losing the earlier conversation when the session restarted while it was being compacted" | context loss on restart |
| 2.1.287 | 519 | "[Cloud sessions] Fixed occasional failures to fetch from or push to GitHub when GitHub briefly refused a newly issued access token" | **push failures from a cloud VM**: a row that "finished" without a pushed branch was a known failure shape before 2026-10-01 |
| 2.1.287 | 472 / 488 | file-send timeout 30→35 s; "an upload that fails on a timeout, a network error or a 502, 503 or 504 is now retried once" | |
| 2.1.288 | 329 | "Added a built-in `gh api` to cloud sessions whose image has no GitHub CLI, and fixed the built-in sending control characters from file names, jq filters or GitHub errors to the terminal" | `gh` is **not guaranteed** in the cloud image; a built-in `gh api` (REST) stands in. A brief that says "run `gh pr create`" may not work; `gh api` does. |
| 2.1.288 | 396 | "Improved cloud sessions: a new conversation's first turn no longer waits for a stdio MCP server whose config sets `alwaysLoad: false`" | `.mcp.json` knob for cloud first-turn latency |
| 2.1.288 | 344 / 367 | restarted cloud sessions replying with / restoring a model the server or the org's enforced list refuses | |
| 2.1.288 | 412 | "[Cloud sessions] Fixed pressing Stop while a self-hosted runner was still starting not cancelling the queued message, which could then run once the runner was up" | |
| 2.1.290 | 186 | "Fixed cloud sessions staying asleep after a container restart lost a pending `/loop` wakeup or scheduled task; Claude is now told and can schedule it again" | in-session scheduling did not survive a container restart |
| 2.1.290 | 196 | "Fixed a plan written in plan mode being lost when a cloud session's container restarted before the plan was presented" | |
| 2.1.290 | 279 | "[Cloud sessions] Fixed turning off prompt suggestions through a cloud environment's environment variables having no effect in new cloud sessions" | confirms environment variables configure Claude Code inside the VM |
| 2.1.290 | 282 | "[Cloud sessions] Fixed an unarchived cloud session looking as if Claude were still working until you sent another message" | status misread |
| 2.1.292 | 44 | "Fixed a cloud session showing a turn that never ended when its worker was stopped just as the turn finished" | a poller waiting for turn-end could wait forever |
| 2.1.292 | 45 | "Fixed cloud sessions with a large transcript sometimes asking for a permission again after it was approved" | |
| 2.1.292 | 46 | "Fixed scheduled tasks and other queued notifications being lost in cloud sessions when a message was retried or edited while Claude was reading them" | |
| 2.1.292 | 72 | "Improved cloud sessions after a restart: Claude is now told which stopped background agents it can resume by id" | |
| 2.1.292 | 79 | "Changed scheduled and Run now routine runs to publish a new artifact only you can see without asking for approval; artifacts that request connectors or other access still ask" | a routine can now emit a private artifact unattended (a report channel that needs no push) |
| 2.1.292 | 81 | "[Cloud sessions] Fixed routine runs occasionally staying listed as running for hours after they had finished" | **routine run status is unreliable as a completion signal** as late as 2026-10-06 |
| 2.1.292 | 82 | "[Cloud sessions] Fixed editing or duplicating a routine turning off its push notifications when the routine had no saved notification setting" | |
| 2.1.292 | 84 | "[Cloud sessions] Fixed approval prompts offering "Always allow" for connector tools that an organization set to require approval; the choice had no effect" | |

### 5.3 Pattern across both bands (inferred from the rows above)

- **Container/worker restart is the dominant failure class**: 15+ rows across 2.1.280–2.1.292 are "after the container/worker restarted" (duplicate step L945, lost plan L196, lost wakeup L186, lost conversation L466, never-ending turn L44, re-asked permission L45, command run twice L977). Three releases in the last week still fix it. For a dispatcher this means: treat a cloud row's side effects as at-least-once, and its "turn finished" / "routine succeeded" signals as advisory; key completion on a pushed ref, not on session or routine status.
- **Routine status was wrong in both directions within the last 7 days**: "Succeeded" when the session never started (fixed 2.1.286, L608) and "running for hours after they had finished" (fixed 2.1.292, L81).
- **Permission prompts exist in cloud sessions** and have been dropped/stale/re-asked (L1090, L605, L100, L45). An unattended cloud row needs a permission posture that never asks.

---

## 6. What `skills/cc-upgrade/holds.md` has already assessed

`holds.md` (92 lines, last touched 2026-10-04, commits `43cefd9c5`, `216a7aa75`) contains **no** row on `--cloud`, `--remote`, teleport, routines, `/schedule`, RemoteTrigger, cloud environments, `CLAUDE_CODE_REMOTE`, `/autofix-pr`, or session trailers (`grep -i` over `skills/cc-upgrade/*.md`: one hit, `audit.md:181`, which only asks that autonomous `/loop`, `/frontier-run` and `/schedule` "still self-terminate and report").

Items it did assess that touch a headless/background dispatcher:

| holds.md item | Line | Its decision | Changelog status at 2026-10-06 |
|---|---|---|---|
| 2.1.285 background Bash 30-min cap; narrowed in 2.1.288 | holds.md:49-52 | "Target 2.1.289; never 2.1.285–2.1.287" | Confirmed by L704 and L402. **Addendum:** the cap persists for `-p`, SDK, CI and cloud at every later version (L402), so the cloud lane and `-p` fires keep it whatever the pin. |
| 2.1.287 drops earlier thinking on `--resume` of a ≤2.1.286 session | holds.md:51-52 | avoid 2.1.287; hits `lr-upgrade.sh` relaunch | not re-read here |
| 2.1.287 revoked-login text → "OAuth token revoked" | holds.md:53-55 | re-key the reopen trigger on `authentication_failed` | confirmed verbatim at L461; `-p` variant "Failed to authenticate" is an additional string the note does not name |
| Restyled permission prompts 2.1.286–287 | holds.md:56-58 | run `tests/pane-modal.bats` on the candidate | n/a to cloud |
| "Shared agents" is not a feature (2.1.289) | holds.md:60-64 | no cap loosened | n/a |
| #99353 `allowed-tools` dropped (2.1.289) | holds.md:65-68 | check fleet skills | 2.1.292 L18 fixes a *related* `allowed-tools` case ("coming back in a later turn when you leave auto mode or plan mode"); whether it closes #99353 is unverified |
| Background-daemon regression window | holds.md:84 | "BLOCKER until the LAST fix in the cluster" | **The cluster is still open**: 2.1.290 has 12+ background-session/`claude agents` fixes and 2.1.292 adds more (L24, L25). By this rule the band has not settled. |
| `-p` + `--mcp-config` not connected before first turn (fixed 2.1.221) | holds.md:91 | matters for headless fires | superseded on 2.1.284; further headless MCP fixes at L476, L492, L540, L64 |
| Subagent cap removed 2.1.224; depth env the sole bound | holds.md:70-75, 88 | keep `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1` | no row in 2.1.285–292 restores a spawn cap (grep of band for cap/ceiling/depth: none relevant). Whether that env var reaches a cloud VM is a cloud-environment-variable question, unprobed. |
| Native cross-session messaging | holds.md:89 | "ASSESS, do not silently adopt" | 2.1.285 L699 (`claude --resume <id> "prompt"` to a running background session) and 2.1.287 L499 extend the native path |

Other audit records:
- MANIFEST row 2.1.224 (2026-08-12) was requested "on its OWN merits, NOT for --cloud" — the one place `--cloud` is named in the version ledger, and it explicitly excludes it.
- The 2.1.281–284 audit notes mark cloud rows out of scope: `docs/research/sonnet55-utilization-2026-09-28/notes/cc284-teams.md:5` "(...gateway, plugin, artifact and cloud rows) is NEUTRAL: out of scope for the axis and not referenced by our config"; `cc284-hooks.md:80` "Items not listed (UI/vim/keybindings, VSCode, Claude Tag, cloud, gateway, plugin, artifact) are NEUTRAL for this axis"; `cc284-workflows.md:5` likewise. That "not referenced by our config" claim is stale against the tree: `bin/cc-dispatch:813`, `bin/cc-notify:737`, `bin/cc-cloud:89` all use `--cloud`.
- `docs/research/claude-code-mods-2026-10-03/REPORT-289.md` (the 285–289 pre-audit) has no cloud/routine/teleport line (grep: only the background-cap rows :114, :158).
- No MANIFEST row exists for 2.1.285–2.1.292 (last row 2.1.284, 2026-09-28; 35 rows total).

---

## 7. Lead's blog digest vs. these two sources

Only what the changelog or the binary can speak to; everything else in the digest is outside this worker's sources.

| Digest claim | Changelog / binary | Verdict |
|---|---|---|
| `claude --cloud "task"` | help-284.txt:70; error string `Usage: claude --cloud "your task description"` | corroborated (measured) |
| `claude --teleport [session-id]`, `/teleport` | help-284.txt:251; L169, L634 | corroborated |
| `claude -p "follow-up" --cloud <session-id>` | `--cloud` accepts `session_id|url`; internal flag `cloudPrintEnabled`; attach is account-gated ("Attaching to an existing cloud session is not enabled for your account.") | corroborated in grammar; gate status per account unprobed |
| `/web-setup`, `/autofix-pr`, `/schedule` | L1684, L653 | corroborated as CLI commands |
| `/claim-credit` | command registered in 2.1.284 strings | corroborated (exists); terms unverifiable here |
| `/tp` alias for `/teleport` | not searched for | not checked |
| SessionStart hook + `CLAUDE_CODE_REMOTE` | env var in binary (193 hits); L470 fixed SessionStart for *synced plugin* hooks in cloud | corroborated that both exist; exact value semantics not read |
| Setup script, cached | L606 ("organization environment's setup script"), L1339 ("failed cloud environment setup script") | existence corroborated; 5-min / 7-day / root figures not in changelog |
| Environment variables | L279, L750 | corroborated |
| Routines: schedule, GitHub triggers, hourly | L1207 (GitHub PR trigger), L1032 (hourly), L946 (schedules), L826 ("routine or webhook") | corroborated; "hourly minimum" and caps not in changelog |
| Cloud commits carry a `Claude-Session` trailer | settings text: `attribution.sessionUrl` "... omit the Claude-Session trailer and PR-body link"; applies to "web or Remote Control sessions" | corroborated, and it is switchable |
| "Each task gets a new branch" | hidden `--on-branch <branch>` works directly on a named branch; `--ref` sets the base | default plausible; not absolute |
| "Personal ~/.claude does not travel" | hidden `--forward-home-settings <true|false>` forwards "CLAUDE.md, rules, output styles, preferences, portable permission rules" | default plausible; an opt-in exists in 2.1.284 |
| GitHub App needed for auto-fix/triggers | L653 names the App for `/autofix-pr` and `/schedule`; L1029 App status page | corroborated |
| VM size, network levels, 200 threads/day, credit amounts/dates | no changelog or binary evidence read | not determinable from these sources |

---

## 8. Alternatives considered

- **Treating band (a) as 2.1.261–2.1.284** (from the pin before 2.1.280). Ruled out as the primary split: the brief asks for "our previous version", which the MANIFEST gives as 2.1.280. Cloud-keyword hits for 2.1.243–2.1.280 are noted in §2.3 and §4.2 only where they establish a primitive (2.1.274 rename; 2.1.280 token rotation, routine edit race).
- **Using the changelog as the instrument for cloud flags.** Ruled out: `--cloud` has zero changelog hits; the binary's option table is the only primary source, and it shows five hidden cloud options.
- **Reading holds.md's "Target 2.1.289" as current.** Ruled out by L100/L101 (2.1.291 fixes regressions from 2.1.288 and 2.1.290).
- **Assuming a pin bump is needed to get the cloud fixes.** Ruled out as a default by the row-prefix reading in §3, but that reading is inference: which Claude Code version a cloud VM runs was not measured.

## 9. Adversarial pass — where this report could be wrong

- §3 (server-side vs local) is the load-bearing inference and is **unverified**. If cloud VMs ran the *caller's* version, every unprefixed cloud fix in §5.2 would be gated on the pin. No source read here settles it; a single observational read of the version line in an existing cloud session transcript would.
- The hidden-option table is from `strings` regex over a minified bundle. Descriptions are verbatim, but *reachability* (feature gates such as `cloudPrintEnabled`, "not enabled for your account") is unprobed; a hidden flag may be refused at runtime.
- "2.1.289 carries the 2.1.288 last-messages regression" is inferred from the fix appearing only in 2.1.291; the changelog does not list affected versions.
- The 2.1.292 binary was not installed, so §2.5's "cloud grammar unchanged" stops at 2.1.291.
- Keyword greps (two passes, ~290 rows read of ~1220 lines in 2.1.281–2.1.292) can miss a relevant row phrased without any keyword. The band was not read line by line.
- `[Claude Tag]` (Slack), `[Code Review]`, Cowork, VS Code and self-hosted-runner rows were excluded as not part of a CLI-dispatched cloud lane, except where they establish a primitive.

## 10. Gaps

- Which Claude Code version runs inside a cloud VM, and whether it tracks `latest`, `stable` (2.1.285), or the caller.
- Whether `--ref`, `--on-branch`, `--forward-home-settings` are accepted for this account at runtime (describe-only; not run).
- Whether `--routine` / `.claude/routines/` is a usable local feature on 2.1.284 (gated; no help text).
- Whether `claude agents --json` lists cloud sessions.
- GitHub issue state for cloud regressions against 2.1.290–2.1.292 (no tracker sweep run; holds.md requires one before any advance).
- Blog specifics with no changelog/binary trace: VM size, snapshot cadence, network levels, routine caps, 200 threads/day, credit terms.
