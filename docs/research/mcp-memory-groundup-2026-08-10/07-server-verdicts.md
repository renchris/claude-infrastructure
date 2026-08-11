# 07 — Per-server verdicts: browsermcp & chrome-devtools-mcp

Measured 2026-08-10 on this host. Every claim below is labelled **MEASURED** (a command run
here, cited with its output) or **STATED** (vendor doc/source, cited with URL or file path).
Transcript evidence is filename/count only — no transcript content was read.

---

## VERDICT 1 — browsermcp (`@browsermcp/mcp`): **ELIMINATE from user scope**

Not "daemonize", not "ephemeral". Remove the entry from `~/.claude.json` top-level
`mcpServers`. Three independent lines of evidence converge, and the architectural one is
decisive on its own.

### Evidence table

| # | Finding | Class | Source |
|---|---|---|---|
| B1 | **Zero tool invocations across 3,504 transcripts.** `rg -l '"name":"mcp__browsermcp'` over `~/.claude/projects` + `~/.claude-secondary/projects` → **0 files**. The same pattern returns 73 for chrome-devtools and 52 for motion, so the pattern is validated, not vacuous. | MEASURED | `rg -l --no-messages -g '*.jsonl' '"name":"mcp__browsermcp' …` → 0 |
| B2 | Broad name sweep `'"name":"mcp__[a-z0-9_-]*browser[a-z0-9_-]*"'` → **no matches at all**. No aliased/renamed variant is hiding the usage. | MEASURED | same run |
| B3 | **The server starts fine and is never called.** 62 `mcp-logs-browsermcp` dirs, all non-empty; 19 × `Connection established with capabilities: {"hasTools":true,…"serverVersion":{"name":"Browser MCP","version":"0.1.3"}}`; handshake 2.0–4.4 s each. It pays full spawn cost, registers 13 tools, and is then dead weight. | MEASURED | `~/Library/Caches/claude-cli-nodejs/*/mcp-logs-browsermcp/*.txt` |
| B4 | **Upstream abandoned ~16 months.** npm `dist-tags.latest = 0.1.3`, published **2025-04-11**. Only four releases ever (0.1.0 → 0.1.3, all inside 6 days of Apr 2025). `@latest` is therefore a frozen pin resolving to a 2025 artifact. | MEASURED | `curl -s https://registry.npmjs.org/@browsermcp/mcp` |
| B5 | **Per-session spawning is architecturally WRONG, not merely costly** — see below. | MEASURED (source) | `~/.npm-cache/_npx/6ddf87659f2ad8a4/node_modules/@browsermcp/mcp/dist/index.js` |
| B6 | It sits in **user scope** (`~/.claude.json` top-level `mcpServers`), so it is offered to *every* session on the primary account. The secondary account (`~/.claude-secondary/.claude.json`) has only motion/motion-plus. | MEASURED | config dump |

### B5 in full — the one-port, last-writer-wins defect

From the shipped `dist/index.js` (v0.1.3), verbatim:

```js
var mcpConfig = { defaultWsPort: 9009, errors: { noConnectedTab: "No tab is connected" } };

async function createWebSocketServer(port = mcpConfig.defaultWsPort) {
  killProcessOnPort(port);                       // <-- unconditional
  while (await isPortInUse(port)) { await wait(100); }
  return new WebSocketServer({ port });
}

function killProcessOnPort(port) { … execSync(`lsof -ti:${port} | xargs kill -9`); … }
```

and the connection handler:

```js
const wss = await createWebSocketServer();
wss.on("connection", (websocket) => {
  if (context.hasWs()) { context.ws.close(); }   // single _ws slot, last wins
  context.ws = websocket;
});
```

Three consequences, all mechanical:

1. **The port is a hardcoded singleton (9009) with no override.** There is no port flag on the
   CLI surface — `program.version(…).name(…).action(…)` takes no options.
2. **Every new server instance `kill -9`s the incumbent.** `killProcessOnPort` runs
   unconditionally at startup, *before* any in-use check. So server N+1 does not fail to bind,
   does not fall back, and does not warn — it executes `lsof -ti:9009 | xargs kill -9` and kills
   server N. In an N-session fleet the only live browsermcp is the most recently started one, and
   every older session's tool silently points at a dead socket.
3. **Even within one server, one tab wins.** `context` holds a single `_ws`; a second extension
   connection closes the first. One server ↔ one tab, by construction.

This is why "one per session" cannot be fixed by tuning. The `kill -9` is also a blast-radius
hazard: it kills *whatever* holds 9009, not just a sibling browsermcp.

### B7 — adversarial: does rare-but-critical use exist? **No, and the near-misses are explained**

The hostile reading is "0 invocations just means your grep is wrong, or the window is short."
Both were tested:

| Challenge | Test | Result |
|---|---|---|
| History window too short to conclude "never" | mtime span of all 3,504 `.jsonl` | **2026-07-11 → 2026-08-10.** Oldest = p05 = 2026-07-11. The claim is therefore scoped: *zero invocations in 30 days across 3,504 sessions*, **not** all-time. Still decisive for a user-scope entry. |
| 18 files *do* mention `browser_snapshot`/`browser_navigate` | sample the match context | **All 18 are tool-name lists, not calls**: permission allowlists (`"mcp__browsermcp__browser_snapshot",`), the `browsermcp` SKILL.md tool table (`… - Get page accessibility tree`), and settings.json dumps. 15 of 18 sit in `claude-infrastructure` — sessions auditing the config, like this one. Zero are `tool_use`. |
| One file contains `No connection to browser extension` | locate + date it | `claude-infrastructure`, mtime **2026-08-10 22:53** — today, inside this audit wave, and that exact string is a literal in the `dist/index.js` this wave read. Self-referential; not usage. |

**Project dirs with genuine browsermcp use: none.** There is no rare-but-critical case to protect.

### B8 — replacement reality: what capability is actually lost?

browsermcp's only differentiated capability is *drive my real, already-logged-in Chrome via an
extension, reusing live cookies/auth*. That is already served twice over, by paths this fleet
uses and documents:

| Path | Covers the warm-session capability? | Evidence |
|---|---|---|
| `agent-browser --cdp 9222` | **Yes.** Skill states CDP mode is for "access to logged-in sessions (cookies, auth state)". Globally installed, `agent-browser@0.27.1`, native darwin-arm64 binary. **67 transcripts** invoke it via Bash. | `skills/agent-browser/SKILL.md:101-121`; `npm ls -g`; `rg -l '"command":"[^"]*agent-browser'` → 67 |
| `chrome-devtools-mcp --autoConnect` / `--browserUrl` | **Yes**, and it is the *documented primary* for the warm-browser case here. The `dia-agent` 100p recipe is `dia-cdp-launch.sh supervise 3600` → `chrome-devtools-mcp --browserUrl http://127.0.0.1:9222` or `agent-browser --cdp 9222`. | `skills/dia-agent/SKILL.md:14-22, 50-53, 67-73` |
| `autonomous-authenticated-web-access` skill | Owns the 3-tier access model (API token > clean-profile CDP > warm real-browser CDP) that supersedes the extension approach entirely. | skill description |

**Named capability lost by removing browsermcp: none.** The extension pairing is strictly worse
than CDP here — it needs a manual per-tab "Connect" click (`noConnectionMessage` in source), caps
at one tab, and its server cannot coexist with a sibling.

**Recommended action:** delete the `browsermcp` key from `~/.claude.json` `mcpServers`. Then
stale-clean the summoners: `enabledMcpjsonServers` lists `browsermcp` in
`~/.claude/settings.json:424-425`, `~/.claude-secondary/settings.json:424-425`, and four project
`settings.local.json` files (`personal`, `taxes-2026`, `technical-analysis`,
`reso-management-app:500-501`); one project still declares it outright
(`~/.claude.json` → `projects["…/reso-upgrade-dependencies"]`).

---

## VERDICT 2 — chrome-devtools-mcp: **KEEP-SCOPED** (project `.mcp.json` + `--isolated`) — fix the wrapper, not the lifecycle

Do **not** eliminate: it is the fleet's live browser-verification stack and usage is hot. Do
**not** daemonize-shared: stdio is 1:1 and the vendor's own profile lock forbids it. The real
savings are the npx wrapper (a whole extra node process per session) and 1.3 GB of dead profile.

### Evidence table

| # | Finding | Class | Source |
|---|---|---|---|
| C1 | **Heavily used and accelerating.** 73 transcripts invoked it — **53 in the last 7 days**, 20 at 8–30 d, 0 older. **2,384 total tool calls.** | MEASURED | `rg` invocation sweep + mtime bucketing |
| C2 | Call mix is verification-shaped: `evaluate_script` 1205 · `navigate_page` 341 · `take_screenshot` 316 · `new_page` 171 · `emulate` 114 · `select_page` 65 · `resize_page` 58 · `list_pages` 39 · `take_snapshot` 25 · `list_console_messages` 17 · `click` 14 · rest ≤5. | MEASURED | `rg -o '"name":"mcp__chrome-devtools__[a-z_]*"' \| uniq -c` |
| C3 | Config is **project-scoped via `.mcp.json`**, replicated across ~20 worktrees + `reso-management-app` + `reso-qa-runner`, mostly `npx chrome-devtools-mcp@latest --isolated`. Correct scope already. | MEASURED | `find ~/Development -maxdepth 3 -name .mcp.json` |
| C4 | **Config conflict to fix.** `~/.claude.json` → `projects["…/reso-management-app"].mcpServers.chrome-devtools` declares `--channel=stable --viewport=1440x900` (**no `--isolated`**), while that repo's own `.mcp.json` declares `--isolated` (no channel/viewport). Two competing definitions of one server name. | MEASURED | config dump vs `reso-management-app/.mcp.json` |
| C5 | Two worktrees route through a wrapper script instead (`bash scripts/mcp/chrome-devtools-mcp.sh`) — `wt-cc-224824-17983`, `wt-cc-005159-55873`. | MEASURED | `.mcp.json` dump |
| C6 | Version churn is fast: 1.1.0 (2026-05-26) → **1.7.0 (2026-08-10, today)**, 8 releases in 11 weeks. `@latest` live-tracks, and **two versions are running side by side right now** (1.6.0 and 1.7.0). | MEASURED | npm registry + `--app-version` in live argv |

### The 3-process chain — roles identified

Read straight off live argv (MEASURED, `ps -eo pid,ppid,rss,etime,args`):

| # | Process | Role | Why it exists |
|---|---|---|---|
| 1 | `npm exec chrome-devtools-mcp@latest --isolated` | **npm CLI wrapper.** A full node process running npm's `cli.js`. Resolves `@latest`, spawns the real bin as a child, then **blocks for the child's lifetime holding the stdio pipe** between Claude Code and the server. | Pure `npx` artifact — contributes nothing at runtime. |
| 2 | `chrome-devtools-mcp` | **The actual MCP server** (argv0 rewritten to the bin name). Owns the CDP connection and the tool handlers. | The only process doing the work. |
| 3 | `node …/chrome-devtools-mcp/build/src/telemetry/watchdog/main.js --parent-pid=<N> --app-version=<V> --os-type=2` | **Telemetry watchdog.** Vendor-shipped child that watches the server's pid to flush usage telemetry on exit/crash. `--parent-pid` names its server exactly, so chain attribution is unambiguous. | Analytics plumbing, not function. Suppressible via the usage-statistics / `--no-performance-crux` flags the server itself banners on stderr. |

### Per-chain census (MEASURED, full descendant trees)

| Chain root | Session / cwd | Age | Ver | Procs | Chrome? | Total RSS |
|---|---|---|---|---|---|---|
| 88728 | kitty pane, claude pid 88196 | 23 h 29 m | 1.6.0 | 3 | **no** | **142 MB** (45.4 + 47.3 + 49.3) |
| 36921 | claude pid 34548 | 20 m | 1.7.0 | 3 | **no** | **412 MB** (104.2 + 154.0 + 153.9) |
| 7217 | `wt-w2-provisioning-console`, claude pid 6687 | 11 h 21 m | 1.7.0 | **7** | **YES** | **1,012 MB** (147.0 + 237.9 + 158.7 + Chrome 230.8 + helpers 107.9/79.0/50.7) |
| | | | | **13** | | **1,566 MB total** |

**A launched Chrome tree DOES hang under the server** — decisively: `Google Chrome` pid **27180
has ppid 14014**, the chain-B `chrome-devtools-mcp`. Four Chrome processes, **468 MB**, are the
server's own descendants. For the census sibling: **attribute Chrome to the MCP chain that
parented it, or the fleet's MCP footprint reads ~45 % low.**

### The 4× spread: the brief's framing is refuted — it is ACTIVITY, not age

The brief reads "the 11h-old chain is 4× the 23h-old one," implying time-driven growth. Measured,
that inverts: **the OLDEST chain (23 h 29 m) is the SMALLEST at 142 MB** — and it runs 1.6.0, the
version with the *known* leak. The 20-minute-old chain is already 2.9× larger than it.

The actual variable is whether the server ever launched/attached a browser and did work:

- No browser ever launched ⇒ ~142 MB, flat, indefinitely (chain 88728, 23 h).
- Browser launched + real verification traffic ⇒ 1,012 MB in 11 h (chain 7217).

Vendor issues corroborate exactly this mechanism (STATED — `github.com/ChromeDevTools/chrome-devtools-mcp`):

| Issue | State | Substance |
|---|---|---|
| **#2431** | CLOSED 2026-07-28 | "Memory leak on 1.6.0: main-isolate old space grows **~13 MiB/min per active session**." Growth "**strictly correlated with activity; plateaus when idle**." Cyclic heap-limit OOMs after ~3 h under heavy multi-session use. |
| **#2456** | CLOSED 2026-08-01 | "RSS grows unbounded in `--browserUrl` mode while live heap stays flat" — V8 never returns freed pages to the OS; heap limit sized from system RAM; concurrent sessions exhaust the host. |
| **#2291** | **OPEN** 2026-07-03 | Leak under sustained screencast + `evaluate_script`; heap → ~4 GB, SIGABRT. Time-to-crash shrinks with load (2.7 d → 12.7 h → 3.9 h). |
| #2421 / #2440 / #2448 | CLOSED | `take_screenshot` leaks an `ElementHandle` per call when `uid` is given; `drag` leaks on failed target lookup; heap-snapshot worker leaked on load failure. |

Two bite this fleet directly: `evaluate_script` is **1205 of 2384 calls (51 %)** and
`take_screenshot` is 316 — precisely the #2291 and #2421 load shapes. **#2291 is still open.**

**Mitigation that follows from the evidence, not from taste:** the ratchet is per-server-lifetime
and activity-proportional, so the fix is *recycling*, not resizing — a long-lived session doing
heavy browser verification should let its chrome-devtools server be restarted; idle sessions cost
~142 MB and can be left alone. Pin off `@latest` to a version at or past the #2431 fix rather
than live-tracking (C6): today's chains already straddle 1.6.0 and 1.7.0.

### Why NOT daemonize-shared

| Constraint | Source |
|---|---|
| Transport is **stdio** — one pipe, one client. Sharing needs an HTTP/SSE shim (supergateway / mcp-proxy). No HTTP transport flag on the server. | Config `"type": "stdio"`; CLI surface |
| The default persistent profile takes an exclusive lock: "**Only one browser can use it at a time.**" N sessions on one shared profile serialise or fail. | STATED — vendor README |
| The vendor's own concurrency guidance is *not* one shared server: `--experimentalPageIdRouting` **plus** `--isolated` "to ensure each independent session has its own temporary profile" — isolation is the sanctioned answer. | STATED — vendor README |
| The leak is per-session-activity (#2431). A shared daemon **concentrates** every session's ~13 MiB/min into one heap, converting a per-session ratchet into a single fleet-wide OOM. | STATED — #2431 / #2456 |

`--isolated` is already the right call and `.mcp.json` project scope is already the right scope.
**What is measurably wrong is the wrapper and the disk, not the lifecycle.**

### The npx wrapper — MEASURED overhead

| Metric | `npx chrome-devtools-mcp@latest` | `node …/build/src/index.js` | Delta |
|---|---|---|---|
| Startup (3 runs, `--version`) | 1.12 / 1.09 / 1.13 s | 0.30 / 0.29 / 0.29 s | **≈ 0.82 s, 3.8× slower** |
| Peak RSS of the run itself | 182,484,992 B | 180,617,216 B | ~1.8 MB — negligible |
| **Resident processes per server** | **2** (wrapper + server) | **1** | **wrapper eliminated** |
| Wrapper RSS observed live | **45.4 / 104.2 / 147.0 MB** | — | **~296 MB across 3 chains today** |

The wrapper is not resident because of a bug — it is `npm exec` doing its normal job: it spawns
the bin as a child and waits, because it must own the stdio pipe and reap the child. So the cost
is unavoidable *while using npx* and vanishes entirely with a direct invocation. Peak RSS being
near-identical is the honest caveat: **npx costs a whole extra process and ~0.8 s, not a bigger
server.** At ~20 `.mcp.json` sites, the resident-process count is the number that matters.

**Version-pinning tradeoff.** `npx …@latest` re-checks the registry on every spawn (most of the
0.82 s) and silently rolls versions mid-fleet — today's live chains run 1.6.0 *and* 1.7.0, so two
sessions carry different leak profiles. A global install (`npm i -g chrome-devtools-mcp@1.7.0`)
plus `command: "chrome-devtools-mcp"` in `.mcp.json` buys back the 0.82 s, removes the wrapper
process, and makes the version deliberate. Cost: upgrades become manual — which, with #2291 open
and the leak version-specific, is a feature.

### Disk

| Item | Size | Note |
|---|---|---|
| `~/.cache/chrome-devtools-mcp/chrome-profile` | **1.3 GB** | The *persistent* profile — **bypassed by `--isolated`**, last modified **2026-06-05**. Dead weight ~9 weeks. Only reachable by a config lacking `--isolated` (i.e. C4). |
| `$TMPDIR/puppeteer_dev_chrome_profile-*` | 103 MB + 92 MB (n=2) | The live `--isolated` profiles. Vendor states these auto-clean on browser close; 2 present, consistent with one browser-attached chain plus one residue. |

### Adjacent finding (for the census sibling, not this verdict)

Three **orphaned** npx-wrapper MCP processes at ppid 1, from a sibling research lab, totalling
**579 MB**: `supergateway` ×2 (211.7 MB, 184.5 MB) and `mcp-proxy@latest` (182.4 MB), all
`--stdio node /tmp/mcpres/lab/fake-server.mjs`, ages 2–5 h. Same wrapper-residency mechanism;
they survived their parent and nothing reaps them.

---

## Usage-frequency table (MEASURED — counts only, no content)

Corpus: **3,504** `.jsonl` transcripts (1,644 in `~/.claude/projects`, 1,854 in
`~/.claude-secondary/projects`). **Window: 2026-07-11 → 2026-08-10 (30 days).** "Invoked" = the
file contains a `tool_use` whose `name` field starts with the server prefix. "Mentioned" = the
string appears anywhere (tool listings, allowlists, skill text, prose).

| Server | Mentioned | **Invoked** | ≤7 d | 8–30 d | 31–90 d | >90 d | Total calls |
|---|---|---|---|---|---|---|---|
| `mcp__chrome-devtools__*` | 505 | **73** | 53 | 20 | 0 | 0 | **2,384** |
| `mcp__motion__*` | 962 | **52** | 43 | 9 | 0 | 0 | — |
| `mcp__browsermcp__*` | 2,788 | **0** | 0 | 0 | 0 | 0 | **0** |
| `mcp__playwright__*` | — | **0** | — | — | — | — | 0 |
| `agent-browser` (Bash CLI) | — | **67 files** | — | — | — | — | — |

The mention/invoke ratio is itself the finding: **browsermcp is mentioned in 2,788 files and
called in none.** Those mentions are its tool list being injected into sessions — a per-session
context tax of 13 tool schemas in exchange for zero calls.

**Project dirs that invoked chrome-devtools** (top): `wt-cc-223740-82148` 22 · `wt-pool-1` 12 ·
`reso-management-app` 6 · `wt-cc-225106-82355` 4 · `wt-cc-152400-19682` 4 · `wt-pool-8` 3 · then
17 dirs at 1–2 each (worktrees + `reso-launch-film` + two `/tmp/bottle-*`). Concentrated in reso
browser-verification work, exactly as the skills stack predicts.

---

## Summary

| Server | Verdict | One-line basis |
|---|---|---|
| **browsermcp** | **ELIMINATE** (drop from `~/.claude.json` user scope) | 0 calls in 30 d / 3,504 sessions; upstream frozen since 2025-04-11; hardcoded port 9009 where each new instance `kill -9`s the incumbent, so per-session spawning is architecturally invalid; capability fully covered by `agent-browser --cdp` and `chrome-devtools-mcp --autoConnect`. |
| **chrome-devtools-mcp** | **KEEP-SCOPED** — project `.mcp.json` + `--isolated`, lifecycle unchanged | 2,384 calls, 53 of 73 invoking sessions inside 7 days; stdio + exclusive profile lock rule out a shared daemon; the vendor's own concurrency answer is `--isolated`. Fix the wrapper (drop npx → −1 process/session, −0.82 s), pin off `@latest`, reclaim 1.3 GB, reconcile the duplicate `--isolated`-less config. |

## Blockers / uncertainties (named)

1. **The "zero" is a 30-day claim, not all-time.** Transcript retention begins 2026-07-11; older
   history is gone. A browsermcp call before then cannot be excluded by this evidence. It would
   not change the verdict (B4 abandonment + B5 architecture stand alone), but the claim should not
   be overstated as "never".
2. **Chain 36921's 412 MB at 20 minutes is unexplained** by the browser-attachment model — no
   Chrome, yet 2.9× the idle 23 h chain. Most likely a browser was launched and closed, or
   `--isolated` teardown left heap behind (cf. #2456: V8 does not return freed pages). Not
   resolvable without heap instrumentation, which is outside the observe-only boundary.
3. **The single `No connection to browser extension` hit is dated today** and is consistent with
   this audit wave reading the dist source. Distinguishing "quoted by the audit" from "a real
   failed attempt today" needs transcript content, which the brief forbids. Treated as
   non-evidence in both directions.
4. **Wrapper-script chains not measured.** Two worktrees route via
   `bash scripts/mcp/chrome-devtools-mcp.sh`; none was live during the census, so whether that
   path also leaves a resident wrapper is unverified.
5. `--help` on the installed 1.7.0 returned no output in this harness, so the CLI flag table is
   **STATED** from the vendor README, not measured locally. Flag *behaviour* (`--isolated` →
   `puppeteer_dev_chrome_profile-*` temp dirs, persistent profile untouched since Jun 5) **is**
   measured and corroborates it.
