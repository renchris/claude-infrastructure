# 04 — MCP spawn semantics: WHEN a session pays for a server, and which sessions inherit which

Measured 2026-08-10 on this box. Docs line numbers `[S] docs Lnnn` index the fetched markdown of
<https://code.claude.com/docs/en/mcp>, persisted at
`~/.claude-secondary/projects/-Users-chrisren-Development-claude-infrastructure/bcf19573-f5e7-4416-9d43-25fa66be1711/tool-results/toolu_019UuL4tT7wn35fytyL4pbs2.txt`. Every claim below is either **[M]easured** (probe command + log
excerpt given) or **[S]tated** (vendor docs, quoted with line number from the fetched page). No
claim is carried from memory.

---

## 1. Verdict table

| Binary | Server scope / transport | Process spawned when? | `tools/list` when? | Reaped at CLI exit? | Evidence |
|---|---|---|---|---|---|
| **2.1.220** (fleet default, `~/.claude-220/…/claude`) | stdio via `--mcp-config` | **EAGER — 550–670 ms after launch, before the first model turn** | **EAGER — same 20 ms window as connect** | **YES** — SIGINT → +102 ms SIGTERM → SIGKILL | [M] Runs A/B/C/D/G |
| **2.1.220** | stdio via repo `.mcp.json` | **EAGER** (both approved *and* unapproved, in `-p`) | EAGER | YES | [M] Runs E/E2 |
| **2.1.220** | HTTP / SSE (`motion`, `motion-plus`, claude.ai connector) | connects at startup; **no local process at all** | at startup | n/a | [M] Run E init event; [S] docs L344 |
| **2.1.114** (`~/.claude-versions/2.1.114/…`) | stdio via `--mcp-config` | **EAGER — 822 ms after launch** | EAGER | YES (SIGINT) | [M] Run H |
| **2.1.221+** (not installed here) | HTTP/SSE **only** | **LAZY** — tool list served from a discovery cache, connect deferred to first tool call | from cache | n/a | [S] docs L198 |

**Headline:** on every binary this fleet runs, a **stdio** MCP server in scope is a process that
starts within ~0.6 s of session launch, completes `initialize` + `tools/list` immediately, lives for
the whole session, and is force-killed on exit. There is no lazy path for stdio on 2.1.114 or
2.1.220. The **only** laziness the vendor has shipped is for *remote* servers and it lands in
**2.1.221 — exactly one version above the fleet's pin**.

---

## 2. The browsermcp paradox, resolved (it was never about eager vs lazy)

The tension in the brief — *user-scope stdio `browsermcp` is configured, yet zero browsermcp
processes are live* — is a **config-dir** fact, not a spawn-semantics fact.

```
$ python3 -c "json… .claude.json → mcpServers keys"          # [M]
/Users/chrisren/.claude.json              user-scope: ['browsermcp', 'motion', 'motion-plus']
/Users/chrisren/.claude-next/.claude.json user-scope: ['motion', 'motion-plus']
/Users/chrisren/.claude-secondary/…       user-scope: ['motion', 'motion-plus']
/Users/chrisren/.claude-tertiary/…        user-scope: ['motion', 'motion-plus']
/Users/chrisren/.claude-quaternary/…      user-scope: ['motion', 'motion-plus']
```

`browsermcp` (and the `reso-upgrade-dependencies` local-scope `browsermcp`, and the
`reso-management-app` local-scope `chrome-devtools`) exist **only in `~/.claude.json`** — the
`.claude.json` of the *bare default* config dir `~/.claude`. Every fleet session launches with
`CLAUDE_CONFIG_DIR=~/.claude-{next,secondary,tertiary,quaternary}`, and each of those dirs has its
**own** `.claude.json` whose user scope is `motion` + `motion-plus` — **both `type: "http"`, so
neither is ever a local process.** browsermcp is therefore structurally out of scope for every
session the fleet actually runs. Zero processes is the *expected* result under eager spawn.

**Corollary worth carrying:** `~/.claude.json` is not "the" MCP config. `CLAUDE_CONFIG_DIR` selects
*which* `.claude.json` is user+local scope. Reading `~/.claude.json` to answer "what does my session
load" is reading the wrong file for 100% of this fleet's sessions.

### What the live chrome-devtools processes actually prove

```
$ ps -Ao pid,ppid,etime,command | rg 'chrome-devtools-mcp|claude'     # [M], 2026-08-10 23:0x
34548 34171 36:52  …/claude-220/node_modules/.bin/claude --permission-mode auto …
36921 34548 36:49  npm exec chrome-devtools-mcp@latest --isolated
48346 36921 36:41  chrome-devtools-mcp
88196 88074 23:45:16 …/claude … ;  88728 88196 23:45:15 npm exec chrome-devtools-mcp@latest --isolated
 6687  6570 11:37:50 …/claude … ;   7217  6687 11:37:49 npm exec chrome-devtools-mcp@latest --isolated
```

Three independent sessions, each with **exactly one** MCP tree, and in every case the child's
`etime` is **within 1–3 s of the parent session's own etime**. That is eager spawn observed in
*interactive* sessions (my probes are all `-p`), running 36 minutes to 24 hours, i.e. the server
persists for session lifetime and is not per-tool-use. [M]

Their argv is `chrome-devtools-mcp@latest --isolated`, which matches **reso's repo `.mcp.json`**
(`{"command":"npx","args":["chrome-devtools-mcp@latest","--isolated"]}`) and **not** the local-scope
entry in `~/.claude.json` (`--channel=stable --viewport=1440x900`). So the live processes come from
the project-file scope, gated by `enableAllProjectMcpServers: true` in
`reso-management-app/.claude/settings.local.json`. [M]

---

## 3. Probe harness (all files under `/tmp/mcp-probe/`, nothing else touched)

- `fake_mcp.py` — well-behaved stdio server. Appends `{t,tag,ev,…}` NDJSON to a log on **START**
  (pid/ppid/argv/cwd), on every **RECV** (method, id, params), on every **SENT**, on **SIGNAL**, and
  on **STDIN_EOF**. Answers `initialize` (echoing the client's `protocolVersion`), `tools/list`
  (one tool `probe_ping`), `tools/call` (returns `PROBE-PONG`), `ping`; `-32601` otherwise.
- `fake_hang.py` — spawns, logs, and **never answers `initialize`**.
- `fake_stubborn.py` — speaks MCP correctly but **ignores SIGINT/SIGTERM/SIGHUP** and survives stdin
  EOF (self-exits at 300 s so it cannot leak).
- Isolation: `--mcp-config <file> --strict-mcp-config`, cwd `/tmp/mcp-probe/proj`. Both flags exist
  on 2.1.220 and on 2.1.114 (`--help` grep count 3 and 1 respectively). [M]
- **Auth constraint that shaped the design:** the keychain item is
  `"Claude Code-credentials-" + sha256(NFC(config_dir))[:8]` (`bin/claude-accounts:265-267`), so a
  scratch `CLAUDE_CONFIG_DIR` has **no credentials** and cannot run `-p` at all. Probes therefore
  use a real config dir; `--strict-mcp-config` is what keeps the real servers out.
- **Free probe channel:** `~/.claude-tertiary` = account `next3`, weekly-**LIMITED** (100%). Its API
  requests are rejected with `cost=0` **after startup has fully completed and emitted its `init`
  event** — so every startup-only question was answered at zero spend. Paid runs: 3 (B, F, G),
  total **$0.257**.

---

## 4. Measured runs

### Run A — eager or lazy? (prompt never mentions the tool)

```
T0_cli_launch=06:15:24.696378
{"t":"06:15:28.244262","tag":"runA","ev":"START","pid":5140,"ppid":98972,"argv":["--probe-arg-A"],"cwd":"/private/tmp/mcp-probe/proj"}
{"t":"06:15:28.245169","ev":"RECV","method":"initialize","id":0,  params:{"protocolVersion":"2025-11-25","clientInfo":{"name":"claude-code","version":"2.1.220"}}}
{"t":"06:15:28.255812","ev":"RECV","method":"tools/list","id":1}
{"t":"06:15:34.182101","ev":"SIGNAL","sig":2}
T1_cli_exit=06:15:35.363299
```
Prompt was `reply with exactly: ok`. The server started, was initialized and **listed** anyway.
(3.5 s offset here includes the CLI's 3 s "no stdin data" wait; later runs use `< /dev/null` and
land at 550–670 ms: B 550, C 590, D 614, G 663, H 822 ms.) The stream's `init` event:

```
system/init  mcp_servers=[{"name":"probe","status":"connected"}]  tools=25 incl. 'ToolSearch','mcp__probe__probe_ping'
```
→ **connected before the first model turn.** (The turn itself was rejected: weekly limit, cost 0.)

### Run B — the same server, prompt requires the tool  *(paid, $0.0605)*

```
T0=06:17:11.635098
06:17:12.185173 START pid=23426          ← +550 ms, with < /dev/null
06:17:12.186     RECV initialize
06:17:12.196     RECV tools/list          ← startup
06:17:21.982     RECV tools/call {"name":"probe_ping","arguments":{"note":"x"}}   ← +10 s, when the model used it
06:17:25.420     SIGNAL sig=2
T1=06:17:26.444679
```
**This is the discriminator.** `initialize` + `tools/list` are startup events; only `tools/call`
tracks use. Lazy-connect is excluded: a lazy client would have had nothing to spawn until 06:17:21.

### Run C — server that never answers `initialize` (does startup block?)

```
T0=06:18:52.435449
06:18:53.025161 START pid=48145                    ← +590 ms: spawn does NOT depend on handshake success
06:18:53.025501 RECV_IGNORED initialize id=0
06:18:59.437036 STDIN_EOF                          ← client closed the pipe; NO signal was sent
T1=06:18:59.464028
system/init  mcp_servers=[{"name":"hangs","status":"pending"}]  tools=29, no mcp__hangs__* present
```
**Startup does not block on a hung server.** The session reached its model turn with the server
still mid-`initialize`, reported as `pending`, and simply had no tools from it. Note the fleet sets
`MCP_TIMEOUT=30000` in `settings.json` — that 30 s is a *connect deadline*, not a startup barrier;
the session had already proceeded 6 s earlier.
Teardown for a *pending* server is **EOF-only**, not a signal — different code path from Run B's
SIGINT. [M]

### Run D — server that ignores SIGINT/SIGTERM (does CC leak it?)

```
06:19:30.625699 START pid=2746
06:19:36.863248 SIGNAL_IGNORED sig=2      ← SIGINT
06:19:36.965571 SIGNAL_IGNORED sig=15     ← SIGTERM, +102 ms
T1_cli_exit=06:19:39.306620
$ ps … | rg fake_stubborn   →  (no row)
```
No further log line and the process is gone ⇒ **SIGKILL** (the only signal it could not log).
**Escalation ladder: SIGINT → +~100 ms SIGTERM → SIGKILL.** CC does not leak a wedged stdio server
at exit. A leaked MCP process in this fleet therefore indicts a *crashed/OOM-killed* session (no
teardown ran), never an orderly exit.

### Runs E / E2 — `.mcp.json` approval gating, and the headless bypass

`/tmp/mcp-probe/proj2/.mcp.json` declares two servers pointing at the same fake script:
`browsermcp` (**is** in `~/.claude-tertiary/settings.json` `enabledMcpjsonServers:["browsermcp","agent-browser"]`)
and `probe` (**is not**). No `--mcp-config`, no `--strict-mcp-config`.

```
headless   $ claude -p 'reply with exactly: ok' …
  spawn log: START tag=E-browsermcp-APPROVED   pid 62712
             START tag=E-probe-UNAPPROVED      pid 62718      ← BOTH spawned
  init: [motion connected, motion-plus connected, browsermcp connected, probe CONNECTED,
         "claude.ai uidotsh" needs-auth]
  tools: mcp__browsermcp__probe_ping, mcp__probe__probe_ping, 5× motion…   (39 total)

non -p   $ claude mcp list          (same cwd, same config dir)
  browsermcp: … --as-browsermcp - ✔ Connected
  probe:      … --as-probe      - ⏸ Pending approval (run `claude` to approve)
```

Run **E2** repeats E *without* `--no-session-persistence`: both still spawn ⇒ the bypass is
`-p`/headless itself, not the persistence flag. And nothing was recorded as approved —
`~/.claude-tertiary/.claude.json` afterwards shows
`/private/tmp/mcp-probe/proj2 → {"enabledMcpjsonServers":[],"disabledMcpjsonServers":[],"hasTrustDialogAccepted":false}`. [M]

The vendor documents exactly this, docs L436: *"`claude -p` runs, Agent SDK sessions, and cloud
sessions can't show that prompt: Claude Code loads project-scoped servers there without asking. To
keep a server out anyway, add it to `disabledMcpjsonServers`, which blocks it in every mode, or
exclude project settings entirely with `--setting-sources`."* [S]

**Operational consequence for this fleet:** every `-p`/SDK/handoff-fired headless session in a repo
carrying a `.mcp.json` starts **every stdio server in that file**, approval list irrelevant. The
only blocking control is `disabledMcpjsonServers` or `--setting-sources`.

### Run G — does a SUBAGENT get its own MCP process?  *(paid, $0.1289)*

```
spawn log for the WHOLE run — exactly ONE process:
06:23:27.815204 START pid=21390 ppid=20390
06:23:28.206411 RECV tools/list          ← session startup
06:23:45.891566 RECV tools/call          ← issued by the SUBAGENT
06:23:50.293243 SIGNAL sig=2

transcript:
  A[parent] tool_use Agent {"subagent_type":"general-purpose", …}
  A[sub=toolu_01KL2…] tool_use ToolSearch {"query":"select:mcp__probe__probe_ping"}
  A[sub=toolu_01KL2…] tool_use mcp__probe__probe_ping {"note":"sub"}
  U[sub=toolu_01KL2…] tool_result "PROBE-PONG"
```
**In-process subagents share the parent session's single MCP client and single server process.** No
second spawn, no second `initialize`. There is **no per-subagent stdio memory multiplier**.
(Run F was the same probe with the decoy `TaskCreate` tools left in scope; haiku picked the
task-tracking tool and never spawned an agent — $0.068 spent, no evidence. Recorded so the cost is
attributable.)

### Run H — cross-version parity on 2.1.114

```
binary_version=2.1.114 (Claude Code)   has_mcp_config_flag=3   has_strict_flag=1
T0=06:25:07.375537
06:25:08.197347 START pid=85801                 ← +822 ms
06:25:08.197774 RECV initialize
06:25:08.205981 RECV tools/list                 ← startup, prompt never mentioned the tool
06:25:13.848628 SIGNAL sig=2
init: mcp_servers=[{"name":"probe","status":"connected"}]  tools=31 incl. ToolSearch + mcp__probe__probe_ping
```
**2.1.114 is eager too — measured, not stated.** (`~/.claude-versions/2.1.114/node_modules/.bin/claude`;
`~/.claude-versions/current` symlinks to it. The dirs `~/.claude-183` and `~/.claude-219` are
mislabelled — they hold 2.1.215 and 2.1.219 respectively. Real version ladder available on this box:
2.1.113, 2.1.114, 2.1.156, 2.1.161, 2.1.170, 2.1.183, 2.1.215, 2.1.219, 2.1.220.)

---

## 5. Scope rules — which sessions inherit which servers

**Five sources, in this precedence order** (docs L449-457 [S], verbatim: *"When the same server is
defined in more than one place, Claude Code connects to it once, using the definition from the
highest-precedence source. The entire server entry from that source is used; fields are not merged
across scopes."*):

| # | Source | Stored in | Loads in | Fleet status here |
|---|---|---|---|---|
| 1 | **Local** scope | `$CLAUDE_CONFIG_DIR/.claude.json` → `projects[<cwd>].mcpServers` | that one project dir only | only in `~/.claude.json`: reso→chrome-devtools, reso-upgrade-dependencies→browsermcp — **invisible to every `.claude-*` session** [M] |
| 2 | **Project** scope | `<repo>/.mcp.json` | that repo, **gated by approval** | reso: uidotsh(http), chrome-devtools(stdio), motion, motion-plus. claude-infrastructure: **no `.mcp.json`** [M] |
| 3 | **User** scope | `$CLAUDE_CONFIG_DIR/.claude.json` top-level `mcpServers` | all projects | all four account dirs: `motion`, `motion-plus` — both `http` [M] |
| 4 | **Plugin**-provided | plugin `.mcp.json` / `plugin.json` | wherever the plugin is enabled | `enabledPlugins = {"swift-lsp@claude-plugins-official": false}` → none [M] |
| 5 | **claude.ai connectors** | the logged-in claude.ai account | **every project, every cwd** | `claude.ai uidotsh` appears in a `/tmp` scratch project with `status: needs-auth` [M] |

Duplicate matching: scopes 1-3 match **by name**; plugins and connectors match **by endpoint**
(docs L457 [S]).

**Approval, and the two gates on it:**
- `.mcp.json` servers need approval. Unapproved → `⏸ Pending approval (run \`claude\` to approve)`
  in `claude mcp list` / `mcp get`; rejected → `✘ Rejected (see disabledMcpjsonServers in settings)`
  (docs L178 [S], reproduced verbatim in Run E's `mcp list` [M]).
- Approval is granted by `enabledMcpjsonServers` (per-name) or `enableAllProjectMcpServers` (all) in
  a settings file — **but as of v2.1.196 those are ignored in an untrusted folder**: a settings file
  checked into the repo cannot approve its own servers until you run `claude` there and accept the
  workspace trust dialog (docs L184 [S]). An untracked `.claude/settings.local.json` likewise needs
  a trust dialog since v2.1.207 — *except* when the folder is your own config home
  (`$CLAUDE_CONFIG_DIR`'s dir) (docs L192 [S]).
- **`-p` ignores the whole approval question** (docs L436 [S] + Runs E/E2 [M]).

**Timeouts the fleet has already pinned** (`settings.json .env` in every account dir [M]):
`MCP_TIMEOUT=30000` (server *startup*/connect deadline, docs L266 [S]) and `MCP_TOOL_TIMEOUT=60000`
(per-tool-call wall clock). Idle-abort for a silent tool call defaults to **30 min for stdio**,
5 min for remote (docs L276, v2.1.203+ [S]).

**Stdio servers are never auto-reconnected** — docs L245 [S]: *"If an HTTP or SSE server disconnects
mid-session, Claude Code automatically reconnects with exponential backoff… Stdio servers are local
processes and are not reconnected automatically."* A stdio server that dies mid-session is gone for
that session; its tools remain listed from the startup `tools/list` but calls fail.

---

## 6. Does ToolSearch deferral change the PROCESS? No — only tokens. (brief Q5)

Measured in Run B and reproduced in Run G:

```
system/init tools[25] = [… 'ToolSearch', 'mcp__probe__probe_ping']       ← NAME is present up-front
A tool_use ToolSearch {"query":"select:mcp__probe__probe_ping"}          ← model must fetch the SCHEMA
U tool_result [{"type":"tool_reference","tool_name":"mcp__probe__probe_ping"}]
A tool_use mcp__probe__probe_ping {"note":"x"}                           ← only now does tools/call go out
```

- The **name** is in the up-front tool list; the **schema** is deferred behind `ToolSearch`. This
  fires with a **single** MCP tool present — it is not a many-tools threshold.
- Deferral is **not MCP-specific**: in Run G the model had to `ToolSearch select:Task` for a
  *built-in* tool too (and got back `Agent` — the registered name differs from the documented one).
- **Timing proves independence:** `tools/list` went out at 06:17:12.196; the first `ToolSearch` was
  at ~06:17:21. The client had already paid for the process, the handshake, and the **full** tool
  list ~10 s before the model asked for one schema.

**So deferral saves context tokens only. It saves no RAM, no fork, no npx download, no startup
latency.** A "deferred" MCP tool is a fully-spawned, fully-listed server whose schema simply is not
in the prompt yet. Any memory-reduction plan built on deferral is built on the wrong lever.

Corollary observed in Run E: when a connected server exposes resources, three extra built-ins
appear — `ListMcpResourcesTool`, `ReadMcpResourceTool`, `ReadMcpResourceDirTool` (39 tools vs 29
with no MCP servers). Connecting servers adds built-in tool surface, not just their own tools. [M]

---

## 7. What a server actually costs (for the memory question this wave is asking)

```
$ ps -Ao pid,ppid,rss,etime …                                   # [M] RSS in KB
tree under 36921 (npm exec + chrome-devtools-mcp + telemetry watchdog): 264,368 KB
tree under 88728: 94,960 KB      tree under 7217: 394,112 KB
session claude.exe 6687: 840,144 KB · 34548: 759,584 KB · 88196: 771,712 KB
```
One stdio MCP server tree = **95–394 MB RSS, i.e. 12–50% of the claude.exe session that owns it**,
held for the session's entire life (one has been up 24 h). Three such trees are live right now. Note
each is *three* processes: the `npm exec` wrapper never execs away, so an `npx`-launched server costs
a supervisor + the server + (for chrome-devtools) a telemetry watchdog.

---

## 8. Adversarial pass

Three things a hostile reviewer would press on, and what I did about each:

1. **"Your fake server's own behaviour could be creating the eager result."** Refuted three ways:
   (a) Run C's server never completed `initialize` and was still spawned at +590 ms with the session
   proceeding past it; (b) Run D's server ignored the shutdown signals and the spawn/list timings
   were identical; (c) the real client accepted the handshake as-is (`protocolVersion 2025-11-25`,
   `clientInfo claude-code 2.1.220`) and an independent code path — `claude mcp list`'s health
   check — spawned it too. Spawn precedes and is independent of handshake outcome.
2. **"`-p` headless is not what the fleet runs."** True, and it turned out to matter for *approval*
   (§4 Runs E/E2) but not for eagerness: the three live **interactive** chrome-devtools trees each
   start within 1–3 s of their parent session (§2), which is the same eager signature. Also
   re-measured on a second binary (2.1.114) rather than assuming version stability.
3. **"You only tested in-process subagents — teammates are separate OS processes."** Correct, and
   this is my one **named gap**. `claude.exe --agent-id …` teammates *are* separate processes
   (verified: pid 57084 is a child of session 56153). Whether such a process opens its **own** stdio
   MCP connections is **UNMEASURED** — both teammates live on this box right now run in
   `claude-infrastructure` / a worktree of it, which has **no `.mcp.json` and only `http` user-scope
   servers**, so their lack of MCP children proves nothing. Deciding it needs one paid run that
   fires a teammate inside a repo with a stdio `.mcp.json`. If teammates *do* connect
   independently, the §7 figure multiplies by the teammate count and that is the single biggest
   open memory risk in this wave.

Two further gaps I could not close and will not paper over:
- **A slow-but-succeeding server.** I proved startup does not block on a server that *never*
  answers. I did **not** measure whether a server answering at, say, 8 s delays the first model
  turn. `MCP_TIMEOUT=30000` is the documented ceiling.
- **`/mcp`-driven runtime reconnect.** Interactive-only; not reachable from a headless probe.

---

## 9. Perishable facts, flagged as such

- 🚨 **2.1.221 changes the answer for remote servers.** docs L198 [S]: *"a remote (HTTP or SSE)
  server you've used before can show a `cached` status such as `cached 2h ago · connects on first
  use · 5 tools`. Claude Code loaded the server's tool list from a previous session instead of
  connecting at startup, and it connects the server the first time Claude calls one of its tools…
  To make every server connect at startup instead, set `MCP_DISCOVERY_CACHE=0`. The discovery cache
  and its `cached` status require Claude Code v2.1.221 or later."* The fleet is pinned at **2.1.220**
  — one version below. **Nothing in that text extends to stdio**, so the stdio verdict should be
  re-measured, not assumed, on any binary bump.
- The keychain-service derivation (`sha256(config_dir)[:8]`) is quoted from
  `bin/claude-accounts:265-267`, which itself labels it "CC 2.1.183" behaviour. It held on 2.1.220
  in practice (a scratch config dir had no auth) but is a vendor-internal detail.
- Version-dir names on this box lie (`~/.claude-183` holds 2.1.215). Always `--version` the binary.

---

## 10. Side effects of this investigation (full disclosure)

- `~/.claude-tertiary/.claude.json` and `~/.claude-quaternary/.claude.json` gained ordinary project
  entries for `/private/tmp/mcp-probe/proj` and `…/proj2` (`mcpServers:{}`, `hasTrustDialogAccepted:false`).
  Additive, `/tmp`-keyed, left in place deliberately — hand-editing a live `.claude.json` while
  other sessions write it is the larger risk.
- The tertiary/quaternary config dirs' SessionStart/Stop **hooks did run** on each probe (15
  `hook_started` events visible in Run A's stream). No probe wrote a tracked file or committed.
- 3 paid API calls, **$0.257 total**, all `claude-haiku-4-5-20251001`. Everything else ran free on
  the weekly-limited `next3` account.
- All probe artifacts live in `/tmp/mcp-probe/` (scripts, configs, spawn logs, `run*.jsonl`
  transcripts) and can be re-run: `bash /tmp/mcp-probe/run{A,C,D,E,E2,H}.sh` are free on a
  quota-exhausted account; `runB.sh` / `runG.sh` cost ~$0.06 / ~$0.13.

---

## 11. What this means for the wave's design question

1. **Deferral is the wrong lever.** It moves tokens, not processes (§6). To cut MCP memory you must
   cut *scope*, not schema visibility.
2. **Scope is per-config-dir, and the fleet already wins by accident** (§2): four account dirs carry
   only `http` servers, so almost no session pays a local process. The exposure is concentrated in
   repos with a stdio `.mcp.json` — today that is `reso-management-app` alone.
3. **The headless bypass is the sharp edge** (§4 E/E2): a fired handoff session in reso starts
   `chrome-devtools-mcp` unconditionally, whether or not that session will ever open a browser.
   `disabledMcpjsonServers` is the only mode-independent control, and `--setting-sources` /
   `--strict-mcp-config` are the per-fire ones.
4. **Exit is clean; crashes are not.** Orderly exits SIGKILL their servers (§4 D). Any orphan MCP
   process found in the wild is evidence of a session that died without teardown.
