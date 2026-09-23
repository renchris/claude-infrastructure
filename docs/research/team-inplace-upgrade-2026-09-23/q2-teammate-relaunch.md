# Q2 — Can a pane-backed TEAMMATE be relaunched in place on a newer binary and rejoin its team?

**Verdict (measured from the 2.1.280 binary + 2.1.260 parity + a live team; the relaunch itself was NOT run — forbidden by brief, so this is ~85% conviction, not a witnessed success):**
1. **YES, by construction.** `--resume <sid>` and the four team flags do not conflict. The resume adopts the SAME session id, and the team identity comes entirely from argv plus files keyed by NAME. Nothing in config.json records the teammate's session id or process.
2. **The env is not optional:** without `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` (or the argv sniff `--agent-teams`), every team flag is **silently ignored** (`if(so()){…setDynamicTeamContext…}`), and the process runs as a plain session that never polls its inbox. `CLAUDE_CONFIG_DIR` must also equal the lead's, because the teams dir is `$CLAUDE_CONFIG_DIR/teams`.
3. **Messages survive the gap:** SendMessage writes `teams/<team>/inboxes/<name>.json` with no liveness check. The relaunched poller (every 1000 ms, keyed on `--agent-name`) reads every entry with `read:false`, so everything written while the teammate was down is delivered — **including any stale `shutdown_request`, which it will act on at once.**
4. **Relaunch in the SAME pane.** `tmuxPaneId`/`backendType` are written ONLY by the lead at spawn. On shutdown the teammate reads its own `tmuxPaneId` from config.json and the lead kills that pane id. A new pane would leave the OLD pane id recorded, and a later shutdown would kill the wrong window. `cc-pane-runner` falls back to a login shell in the same pane after exit, so the same pane is available.
5. **Precondition: the member row must still exist in config.json, looked up by name.** It is removed only when the lead processes a `shutdown_approved` or kills the task via TaskStop. With the row gone, the resume path skips the Stop-hook (idle notifications), and lead-side SendMessage by name returns `not_reachable` once the lead has also dropped the teammate from its in-memory map.
6. **Cross-version is safe:** lead on 2.1.260 with the teammate on 2.1.280 speaks the identical mailbox protocol (`msgV:1`, same entry schema), gate, argv shape and env builder. Our own rails currently REFUSE teammates (`scripts/handoff-fire.sh:2346`, `scripts/limit-recover/lr-upgrade.sh:305`), and that gate is what would have to open.

---

## Evidence (binary = `~/.claude-280/…/bin/claude.exe` unless noted; offsets are byte offsets)

### 1. How each flag is consumed

- **Option registration** (@186393493): all hidden (`.hideHelp()`):
  `--agent-id <id>` "Teammate agent ID", `--agent-name <name>`, `--team-name <name>`, `--agent-color <color>`, `--plan-mode-required`, `--parent-session-id <id>` "Parent session ID for analytics correlation", `--teammate-mode <mode>`, `--agent-type <type>` "Custom agent type for this teammate".
- **Startup consumption** (@186050924):
  ```
  let Pe=Fu(u);if(Pe.parentSessionId)Won().setCliParentSessionId?.(Pe.parentSessionId);Xxr(Pe.agentId);
  if(so()){rt=Pe;let j=Pe.agentId||Pe.agentName||Pe.teamName,V=Pe.agentId&&Pe.agentName&&Pe.teamName;
   if(j&&!V)return on("Error: --agent-id, --agent-name, and --team-name must all be provided together");
   if(Pe.agentId&&Pe.agentName&&Pe.teamName)Won().setDynamicTeamContext?.({agentId,agentName,teamName,color:Pe.agentColor,planModeRequired,parentSessionId})
   if(Pe.teammateMode)…}
  ```
  The only validation is that all three flags come together. **No check that the team or member exists** at parse time.
- **The gate `so()`** (@176829115, identical in 2.1.260 as `zr()` @160134319):
  `function t(){return process.argv.includes("--agent-teams")} function so(){if(!a.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS&&!t())return!1;if(!x("tengu_amber_flint",!0))return!1;return!0}`.
  `--agent-teams` is only an argv sniff. It is NOT in the registered option set, so use the env var, as the lead does.
- `--agent-type`: used only when no main-thread agent is already set (`SU(sn.activeAgents,rt.agentType)` @186071590). On resume, `mDt` also restores the transcript's `agent-setting` row (`"agentSetting":"general-purpose"`).
- When the team flags are present, `TEAMMATE_SYSTEM_PROMPT_ADDENDUM` is appended to the system prompt (@186055589). A relaunch keeps the teammate framing.
- **Team file reads at startup:** `computeInitialTeamContext` (@185990439) reads `teams/<team>/config.json` for `leadAgentId`. If the file is missing it logs an error and continues. `[TeammateInit] P3` (@196574950) reads the file for `teamAllowedPaths` and registers the Stop hook, which sends the idle notification and sets `isActive=false`. A missing file means an early return with no hook.
- **What the teammate writes to config.json:** only `isActive`, by NAME (`setMemberActive`/`xEt` @177177479). It writes `true` at each turn start (`if(so()){…xEt(qo,Fo,!0,pt)}` @197602588) and `false` in the Stop hook (@196574950) and on failure (@196576421). Also `mode` via `syncTeammateMode`. **It never writes `tmuxPaneId`, `backendType`, `sessionId` or `cwd`.** Only the lead's spawn `j()` (@201077209) sets `tmuxPaneId`/`backendType`.
- The config.json member schema, measured across 446 team dirs under `~/.claude*/teams/`: `agentId,name,agentType,color,model,prompt,planModeRequired,joinedAt,tmuxPaneId,cwd,subscriptions,backendType,isActive`. **There is no `sessionId` field on any member**, so the teammate↔sid binding lives only in the transcript (user rows carry `"agentName":"dep-test","teamName":"session-164e9134"`, e.g. `~/.claude-tertiary/projects/-Users-chrisren-Development--worktrees-wt-pool-3/3e70a9be-….jsonl`).

### 2. `--resume` compatibility and the session id

- No code rejects `--resume` together with `--agent-id`. The only session-flag refusal is `--session-id` with `--resume` unless `--fork-session` is also given, so do not pass `--session-id`.
- `mDt` → `hSe(sessionIdOverride??e.sessionId, forkSession)` (@184346542): `if(n)return{adoptedSessionId:null,effectiveFork:!0}; … if(G8t(e,i))return{adoptedSessionId:e,effectiveFork:!1}`. **With no fork, the resumed teammate adopts and keeps writing `<sid>.jsonl`.**
- **The resume path re-binds the team from the transcript** (`A3` @196576421, runs only `if(so())`): if the first loaded message carries `teamName`+`agentName`, it runs `initializeTeammateContextFromSession` (`e0r` @185991008). That rebuilds `teamContext` from config.json and looks up the member **by name** (`Member ${p} not found in team ${u} - may have been removed` if absent). It then runs `P3` with that member's `agentId`. Otherwise it falls back to the CLI `dynamicTeamContext`.
- **The CLI flags are still mandatory on resume.** The inbox identity is `pXe(){…if(Aa())return{kind:"teammate",agentName:Lm()}…}`, and `Aa()` = `dynamicTeamContext.agentId&&teamName`, which only the CLI flags set. Without them, `kI()` treats the session as a lead (`if(!t)return!0`), `LY` returns `undefined` (the roster is empty), and **nothing is polled.**
- `DHe()` disables persistence only for `CLAUDE_CODE_CHILD_SESSION && !Aa()`, so a flagged teammate persists normally.

### 3. Message receipt

- Inbox path `IO(e,n)` (@176968888): `Te(ODe(),sx(team),"inboxes")/<sx(agentName)>.json`, where `ODe()=join(CLAUDE_CONFIG_DIR ?? ~/.claude,"teams")` (@170270601). **It is keyed by agent NAME, not by id or session.**
- Unread = `filter(g=>!g.read)` (`readUnreadMessages` @176971350). Entry schema, measured: `{from,text,timestamp,msgV,msg_id,type,read[,summary,color]}`.
- Poller `Bpe` (@197707345): `RZt=1000` ms timer, runs `readUnreadMessages(LY(identity))` and then `markMessagesAsRead`. On a mark failure the messages "stay unread and are retried next poll".
- **The sender does no liveness check:** SendMessage `ut()` (@200503491 −7000) resolves the name against the lead's in-memory `teamContext.teammates`, else against the config.json roster, then calls `dy(T,…)` to append to the inbox. So messages accumulate while the teammate is down and are picked up on relaunch.
- ⚠ **Live example of the stale-shutdown hazard:** `~/.claude-tertiary/teams/session-164e9134/inboxes/dep-test.json[0]` is an unread `shutdown_request`. A relaunched `dep-test` would process that shutdown on its first poll.

### 4. Pane / backend identity

- The lead records `tmuxPaneId` + `backendType` via `j(i,A,{tmuxPaneId:h,backendType})` right after creating the pane (@201079432). It also holds the id in its in-memory `teamContext.teammates[agentId].tmuxPaneId` and its task registry.
- **SendMessage does not use the pane id at all**; delivery is file-only.
- **Shutdown does use it:** the teammate's `handleShutdownApproval` (`ft` @200503491) reads `members.find(agentId===self).tmuxPaneId/backendType` from config.json and puts them in `shutdown_approved`. The lead (@197720920) kills `zo.paneId` only if it equals its in-memory `tmuxPaneId`. So:
  - **Same pane: fully consistent.**
  - **New pane:** both sides still name the OLD id, so the lead kills the old window and leaves the new one orphaned.
- Live: teammate pid 92051 has env `KITTY_WINDOW_ID=545`, `ITERM_SESSION_ID=w0t0p0:545`, and config.json has `"tmuxPaneId":"545","backendType":"iterm2"`, i.e. the kitty id seen through our it2 shim. Its parent is `cc-pane-runner`, which after the command exits runs `exec "${SHELL:-/bin/zsh}" -l -i` (bin/cc-pane-runner:83 and header). **The pane survives `/exit` as a login shell** whose `.zshrc` re-synthesizes `ITERM_SESSION_ID`.
- Nothing on the lead side watches pane or process liveness for pane teammates. The lead's task entry simply stays "running" across the relaunch.

### 5. Env the lead injects (exact)

Spawn command (@201079432, iTerm2/kitty backend; the tmux backend is identical):
```
cd <cwd> && env <G()> <V()> --agent-id <name@team> --agent-name <name> --team-name <team>
  --agent-color <color> --parent-session-id <lead K()> [--plan-mode-required] [--agent-type <t>] <z()>
```
- `G()` (@201073700; 2.1.260 identical @175409021): always `CLAUDECODE=1 CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`. It also passes through **only if set and non-empty in the lead's env**: `CLAUDE_CODE_USE_{BEDROCK,VERTEX,FOUNDRY,ANTHROPIC_AWS,ANTHROPIC_GOOGLE_CLOUD,MANTLE,GATEWAY}`, `ANTHROPIC_AWS_*`, `ANTHROPIC_GOOGLE_CLOUD_*`, `GOOGLE_CLOUD_PROJECT`, `AWS_*` (BEARER_TOKEN_BEDROCK, REGION, DEFAULT_REGION, PROFILE, CONFIG_FILE, SHARED_CREDENTIALS_FILE), `ANTHROPIC_BEDROCK_*`, `CLAUDE_CODE_AUTO_MODE_SERVER`, `CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS`, `CLAUDE_CODE_SUBAGENT_MODEL[_FORCE]`, **`ANTHROPIC_BASE_URL`, `CLAUDE_CONFIG_DIR`**, `CLAUDE_CODE_REMOTE[_MEMORY_DIR]`, `HTTP(S)_PROXY`/`NO_PROXY` (both cases), the CA-bundle vars (`SSL_CERT_FILE, NODE_EXTRA_CA_CERTS, REQUESTS_CA_BUNDLE, CURL_CA_BUNDLE, CLOUDSDK_CORE_CUSTOM_CA_CERTS_FILE, HTTPLIB2_CA_CERTS, AWS_CA_BUNDLE, DENO_CERT, CARGO_HTTP_CAINFO, PIP_CERT, GIT_SSL_CAINFO, GRPC_DEFAULT_SSL_ROOTS_FILE_PATH, NIX_SSL_CERT_FILE, HEX_CACERTS_PATH`), `UV_NATIVE_TLS, DENO_TLS_CA_STORE`, `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC, CLAUDE_CODE_PROVIDER_MANAGED_BY_HOST, DISABLE_ERROR_REPORTING, DISABLE_GROWTHBOOK, DISABLE_TELEMETRY, DO_NOT_TRACK`, and `CLAUDE_SECURESTORAGE_CONFIG_DIR`.
- `V()`: the lead's own binary (`gp({pinToCurrentBinary:!0})`), unless **`CLAUDE_CODE_TEAMMATE_COMMAND`** is set in the lead's env. That is also a lever for making a lead spawn FUTURE teammates on a newer binary.
- `z()`: permission flag (`--dangerously-skip-permissions` | `--permission-mode acceptEdits|auto`), `--model`, `--effort`, `--settings <lead's>`, `--plugin-dir*`, `--plugin-url`, `--project-config-root`, `--chrome/--no-chrome`, `--restricted`, each only if the lead has it. There is no MCP flag and no prompt: **the initial prompt goes into the inbox before launch.**
- **Measured live** (pid 92051, `ps eww`, filtered to claude/team vars): `CLAUDECODE=1 CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 CLAUDE_CONFIG_DIR=/Users/chrisren/.claude-tertiary`, plus the pane's own `KITTY_WINDOW_ID/ITERM_SESSION_ID`. Argv: `…/.claude-260/…/claude.exe --agent-id refute-reversals@session-164e9134 --agent-name refute-reversals --team-name session-164e9134 --agent-color cyan --parent-session-id 164e9134-0e50-4e01-9783-c0d8536c7272 --agent-type general-purpose --permission-mode auto --effort high --model claude-opus-5`.

---

## Recommended relaunch (typed into the SAME pane's fallback shell after the teammate has exited at rest)

```bash
cd "<member.cwd>" && env CLAUDECODE=1 CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 \
  CLAUDE_CONFIG_DIR="<lead's CLAUDE_CONFIG_DIR, e.g. /Users/chrisren/.claude-tertiary>" \
  [every other G() var present in the old teammate's env, copied verbatim] \
  /Users/chrisren/.claude-280/node_modules/@anthropic-ai/claude-code/bin/claude.exe \
  --resume <teammate sid> \
  --agent-id <name>@session-<sid8> --agent-name <name> --team-name session-<sid8> \
  --agent-color <member.color> --parent-session-id <lead sid> --agent-type <member.agentType> \
  [--plan-mode-required  if member.planModeRequired] \
  --permission-mode auto --effort high --model claude-opus-5-5
```
- Take `--agent-color` and `--agent-type` from the member row (or from the old argv); do not hardcode them. Capture the old argv and env (`ps -o args=`, `ps eww`) BEFORE the exit, since after the exit they are gone.
- Find the teammate sid from the transcript, not from config.json: the `<cfg>/projects/*/*.jsonl` file whose user rows carry `"agentName":"<name>"` AND `"teamName":"<team>"` (measured: dep-test → `3e70a9be-1486-4010-a974-fefafceec626`).

**Gates before firing (all read-only):**
- (a) The member row exists by name in `teams/<team>/config.json`.
- (b) The inbox holds no unread `shutdown_request`. If it does, the teammate is being retired, so do not relaunch it.
- (c) The transcript is at rest, and the old pid has exited.
- (d) The pane id is unchanged.

**Residual:** if the LEAD has also restarted, its in-memory roster starts empty, so SendMessage falls back to the config.json roster and still delivers. Shutdown pane-kill, however, will not fire, because the lead has no in-memory pane id to match against.
