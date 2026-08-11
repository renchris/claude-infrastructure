# 08 — Architecture design space for "per-session MCP memory ≈ 0"
**Fleet:** single Mac (M1-class, 64 GB), target 100–150 concurrent Claude Code sessions.
**Binary pinned for every claim below:** `@anthropic-ai/claude-code` **2.1.220**
(`/Users/chrisren/.claude-220/.../bin/claude.exe`, a 256 MB Mach-O arm64 single-file build —
not a greppable `cli.js`; all binary evidence below is `strings -a` over that file).
**Written:** 2026-08-10. Read `§9 Adversarial pass` before trusting `§2`.

---

## 0. Measured ground truth (this box, this hour — not assumed)

| Fact | Value | How measured |
|---|---|---|
| Concurrent sessions right now | **32** session processes | `ps` census, cwd-resolved via `lsof -d cwd` |
| Session RSS | mean **610 MB** (452–812) | `ps -eo rss` |
| Session **physical footprint** | mean **249 MB** (227.7–267.1, n=13) | `vmmap -summary` → `Physical footprint` |
| Sessions in a cwd containing `.mcp.json` | **3 / 32 = 9 %** | `[ -f "$cwd/.mcp.json" ]` per session |
| Live stdio MCP chains | **3** (all `chrome-devtools-mcp`) | `ps`, ppid = a session process |
| Cost of ONE stdio chain (3 procs) | **412.6 / 281.4 / 322.1 MB footprint** (mean **339 MB**); RSS 581/430/141… | `vmmap -summary` per pid |
| — of which the `npm exec` wrapper alone | **116.1 / 70.8 / 117.3 MB** | same; the wrapper does no MCP work |
| Browser the chain lazily launches | **+195 MB footprint** (4 Chrome procs, ppid = the MCP server) | `vmmap` on 27180/31969/31988/32036 |
| Remote HTTP servers per session | **2** (`motion`, `motion-plus`), **0 process bytes** | `~/.claude-secondary/.claude.json` |
| Box | 64 GB; wired 5.7 GB · active 22.5 GB · compressed 1.7 GB · **swap 0.00 M** | `sysctl hw.memsize`, `vm_stat`, `vm.swapusage` |
| Process/fd ceilings | `kern.maxprocperuid=10666`, `maxfiles=491520`; 1,012 procs in use | `sysctl` — **not** the binding constraint |
| LaunchAgents already supervised | **47 plists, ~20 loaded** | `ls ~/Library/LaunchAgents`, `launchctl list` |
| A shared browser endpoint already listens | **Dia on 127.0.0.1:9222** | `lsof -nP -iTCP -sTCP:LISTEN` |

**Premise correction — the config the fleet actually reads.** Every live session runs with
`CLAUDE_CONFIG_DIR=/Users/chrisren/.claude-secondary` (verified with `ps -Eww` on pids 7295 / 6687 /
34548). That file's user scope is `{motion, motion-plus}` **only**, across 387 project entries with
**zero** project-scope local servers. `browsermcp` is configured in `~/.claude.json` — the *default*
config home, which no fleet session opens. So "user-scope browsermcp configured but 0 live" is true
for a reason that changes the migration target: **the levers are (a) `~/.claude-secondary/.claude.json`
and (b) the repo-checked `.mcp.json` files — never `~/.claude.json`.**

**Where the stdio cost actually comes from.** Not user scope: it is **project scope**, checked into the
repo. `reso-management-app/.mcp.json` declares `chrome-devtools` (stdio) + `uidotsh` + `motion` +
`motion-plus`, and **79 `.mcp.json` files exist under `~/Development`** because every worktree inherits
the repo's copy. One file in one repo sets the marginal cost of every session that ever cds into a
reso worktree.

---

## 1. The binding constraint, stated as a number

At the 150-session target:

```
sessions      150 × 249 MB footprint            = 37.4 GB
macOS + wired + non-Claude apps (measured)      ≈ 12–14 GB
                                        -----------------
remaining for ALL MCP, fleet-wide               ≈ 12–14 GB
÷ 150 sessions                                  = 80–93 MB / session
```

**The marginal MCP budget is ~80 MB per session. One of today's stdio chains is 339 MB — 4.2× over —
and 534 MB once its browser launches.** That is the whole problem in one line, and it is why "≈ 0" is
the right goal rather than "smaller". The identical failure is on record upstream on identical
hardware: **GH #45880** — M1 Max, 64 GB, macOS 26.1, CC 2.1.97, *15 sessions × 34 servers → 308 node
processes, 111 GB requested, hardware-watchdog kernel panic*; closed **not planned**, labels
`area:mcp / perf:memory / stale`.

Two consequences the matrix must respect:
1. **Process count is not the ceiling** (10,666 procs/uid available; 150×3 = 450). RAM is. Do not
   design for process hygiene; design for resident bytes.
2. **Any design whose marginal cost is a *process* has already lost**, because the smallest useful
   Node MCP server measured here is 99–186 MB. Only designs whose marginal cost is a *socket* or
   *nothing* clear the bar.

---

## 2. Scored matrix

Grades are **A** (reaches the floor) → **E** (fails at 150). "M" = marginal, per resident session.
Every non-obvious cell is justified in §3.

| # | Architecture | M MB/session | Fixed MB/fleet | First-use latency | Failure blast radius | Cross-session isolation | Ops (what must be supervised) | Context tokens (schemas deferred) | Migration cost from today |
|---|---|---|---|---|---|---|---|---|---|
| **A** | **Zero-MCP** — capability via CLI + skills | **0** (A) | **0** (A) | 0.1–1.3 s per *invocation* (measured `npx` 1.22 s cold-ish; resolved bin ≈0.1 s) (B) | Per-call. One Bash call fails; nothing else notices (A) | Perfect — fresh process per call (A) | Nothing. The CLI must exist and be on PATH (A) | **0** MCP tokens; a skill line ≈15–30 tok if you add one (A) | Per capability: needs a CLI + skill. Browser already has both (`agent-browser`, `dia-agent`) (B) |
| **B** | **Ephemeral on-demand stdio, native** — spawn on first tool use, exit after | 0 idle / 339 MB in use (B) | 0 (A) | ~1.2–1.5 s spawn + handshake (B) | Per-session (A) | Perfect (A) | Nothing new — **but the actuator does not exist** (E) | Same as C (B) | **BLOCKED on 2.1.220** — see §3.B (E) |
| **B2** | **Ephemeral via out-of-band daemon** (`mcp-on-demand` pattern: CLI/skill → local HTTP session manager → stdio child) | **0** (A) | ~50–80 MB router + child only while active (B) | ~1.3–3 s cold, ~0 warm (B) | Router death = all *in-flight* MCP calls; sessions keep running (B) | Per named session; resource-level shared if two sessions name the same server (C) | 1 daemon + port + version pin (B) | **0** — no MCP entry in any config (A) | Adopt/port a ~1-file daemon + one skill (B) |
| **C** | **Always-on shared localhost daemon(s)**, Streamable HTTP, launchd `KeepAlive` | **<1** (socket + few-KB session state) (A) | 50–200 MB **per shared server** (Node); ≈5–20 MB for a Rust gateway (B) | Startup connect is **background/non-blocking by default** (`MCP_CONNECTION_NONBLOCKING`); localhost connect 1–5 ms (A) | **Fleet-wide** — one death removes tools from all 150. Softened: CC auto-reconnects HTTP/SSE 5× with exponential backoff, and tells Claude the tools vanished (C) | Protocol-level per client; **resource-level SHARED** — one browser, one cwd, one OAuth token (D) | plist + port + health + log rotate + version pin + Origin/Host validation (bind 127.0.0.1) (C) | instructions ≤2 KB/server + tool names; measured **≈165 tok for 2 servers** (B) | Edit one `.mcp.json` (`stdio`→`http`) — 79 worktrees inherit — plus build/adopt the daemon (C) |
| **D** | **Socket-activated / idle-exit daemon** — zero resident when unused | **<1** (A) | **0 when idle**, = C in use (A) | **cold 1.3–3 s** on first call after idle (C) | Same as C + cold-start failure modes (C) | Same as C (D) | C **+ the activation shim**; true launchd socket activation needs `launch_activate_socket`, a C API with no Node/Bun binding → shim or a tiny always-on router (D) | Same as C (B) | C + shim (D) |
| **E** | **Remote / vendor-hosted MCP** (incl. the fleet cloud lane) | **0** (A) | **0 local** (A) | network RTT; measured 4 remote servers health-checked in **3.24 s wall, parallel** (B) | Vendor/network outage = fleet-wide; 3 retries at startup, 5 mid-session (C) | Per-account/per-token; genuinely multi-tenant (B) | ≈0 local; token rotation + egress policy (B) | Same as C (B) | Free where a hosted equivalent exists (`motion`, `uidotsh` already prove it); **impossible** for machine-local capability (this Mac's browser, this filesystem) (D) |
| **F** | **Status-quo scoped** — stdio only in the few project dirs that need it | 0 for 91 % of sessions; **339–534 MB** for the rest (D) | 0 (A) | +1.2–1.5 s at session start, background (B) | Per-session (A) | Perfect (A) | Nothing (A) | Same as C (B) | **0 — this is today** (A) |
| **G** | **F + D hybrid** — scoped config, and the scoped server is an idle-exit daemon | <1 (A) | 0 idle (A) | cold 1.3–3 s (C) | Blast radius limited to the *scoped* population (B) | Shared only among the scoped few (C) | C + shim, but one server instead of many (C) | Same as C (B) | C + shim, applied to one entry (C) |
| **H** | **A + shared browser endpoint** — no MCP at all for the dominant capability; browser work goes CLI→CDP against the already-running `127.0.0.1:9222` | **0** (A) | 0 new (the endpoint already runs) (A) | ~0.1–0.5 s CDP attach (A) | Per-call; a browser crash is one call's problem (B) | Tab/context-scoped, not process-scoped — **contention is real but cheap to bound** (C) | Nothing new (A) | **0** (A) | Delete one stanza from `reso-management-app/.mcp.json` (A) |

---

## 3. Cell justifications (only the non-obvious ones)

**A — why 0 tokens is literally 0.** With no MCP entry there is no server, so there is no
`initialize`, no `tools/list`, no server-instructions block and no tool-name list. The only residue is
whatever skill/CLI documentation you choose to add, which is the same cost you would pay anyway.

**B — why native ephemeral stdio is blocked on 2.1.220.** Three findings, all from the pinned binary
and the vendor docs:
- The binary **does** contain an enable/disable/reconnect actuator: `mcp_toggle` ("Enables or disables
  an MCP server"), `mcp_reconnect` ("Reconnects a disconnected or failed MCP server"),
  `sdk_mcp_toggle_server`, `disconnectSdkMcpServer`. But they sit in the **SDK control-request** union
  alongside `stop_task`, `set_cwd`, `reload_skills`, `apply_flag_settings` — i.e. the harness/SDK
  control plane and the `/mcp [reconnect|enable|disable]` slash command, **not a model-callable tool**.
  An in-session agent cannot spawn or reap its own stdio server.
- There is **no lazy flag** for stdio. Upstream feature requests are open and unshipped:
  #26666, #38365, #18497, #13805.
- The one lazy behaviour that exists is **remote-only and newer than this fleet**: the docs' `cached
  2h ago · connects on first use · 5 tools` status. The literal string `connects on first use` is
  **absent from the 2.1.220 binary** (`grep -c` = 0), while `MCP_REMOTE_SERVER_CONNECTION_BATCH_SIZE`
  *is* present — direct evidence that on 2.1.220 remote servers are **connected at startup, in
  batches**, not lazily. ⇒ **Design B is a roadmap bet, not an option today.**

**B2 — the shape that makes ephemerality work anyway.** Move the lifecycle *outside* Claude Code:
the agent calls a CLI, the CLI talks to a small local HTTP session manager, the manager owns the stdio
child. Because Claude Code has no MCP entry, the token cost is exactly zero and the memory cost is
zero when nobody is using it. This is `mfagerlund/mcp-on-demand` (HTTP daemon on 127.0.0.1:9876;
`start` / `call` / `stop`; claims *"0 tokens when not in use"*; documented limits: **no idle timeout**,
manual `stop`, no auto-discovery of tools before `start`, port fixed at 9876).

**C — "background by default" is a measured default, not a hope.** CC docs: *"Other servers connect in
the background by default; set `MCP_CONNECTION_NONBLOCKING=0` to make startup wait for them too."*
The inverse trap is `alwaysLoad: true`, which *"makes startup wait for the server's tools, capped at
the standard 5-second connect timeout"* — never set it in a 150-session fleet.

**C/D — blast radius is softer than it looks, and asymmetric by transport.** CC docs: *"If an HTTP or
SSE server disconnects mid-session, Claude Code automatically reconnects with exponential backoff: up
to five attempts…"*, and the same backoff (3 tries) applies to a failed initial connection. The 2.1.220
binary carries the graceful-degradation strings: *"The following MCP servers have disconnected. Their
instructions above no longer apply"* and *"N deferred tools are no longer available (MCP server
disconnected) … Do not search for them"*, plus the symmetric re-announce on reconnect. **Note the
scope: the auto-reconnect sentence names HTTP and SSE only.** A dead stdio child has no documented
auto-restart — which is an argument *for* the daemon designs, not against them.

**C/D — the isolation grade is D for a reason.** MCP's HTTP session gives you protocol isolation, not
*resource* isolation. The dominant server here proves it: **`chrome-devtools-mcp` binds one Chrome
instance for the process's whole lifetime**; multi-session support inside one server is an open feature
request (**ChromeDevTools/chrome-devtools-mcp #926**). A singleton browser daemon would serialise 150
sessions onto one browser. For that class of server the correct shared design is a **pool of K
instances with checkout/return**, not a singleton — which is a materially bigger build than "run it
once under launchd".

**D — the launchd cell is a real engineering constraint, not a preference.** Apple's on-demand story
is `launch_activate_socket()`, a **C API** (`xpc/launch_activate_socket`); there is no Node/Bun
binding, so a JS MCP server cannot accept launchd's pre-opened socket. Practical options: (i) a tiny
non-Node shim that owns the socket and execs/proxies, (ii) `inetdCompatibility` (one process per
connection — wrong for a shared server), or (iii) give up on socket activation and run a small
always-resident router that spawns/reaps heavy children — which is exactly B2/Docker-MCP-Gateway.

**E — the cloud lane's asymmetry.** CC docs state that in **web sessions**, *"an MCP call to a plugin
server that isn't connected yet … starts the server on demand and waits for it to connect"* — the
on-demand behaviour the local lane lacks. But cloud sessions also *"load project-scoped servers
without asking"* (no approval prompt in `-p`, SDK and cloud runs), which is a posture change worth a
deliberate decision, not a default.

**F — why today's 9 % is not reassuring.** The penetration is a property of *which repo people work
in*, not of policy. Scale the same rule to 150 sessions: 9 % → 13.5 chains ≈ 4.6 GB (survivable);
50 % → 75 chains ≈ 25–40 GB (fails); 100 % → 51–80 GB (kernel panic, per #45880). F is not an
architecture, it is an unbounded variable.

**Context-token column, measured rather than assumed.** Deferral is real and first-party — the 2.1.220
binary's own guidance says *"MCP tool schemas are deferred behind the ToolSearch tool by default: only
the tool name sits in context; the schema is fetched on demand and costs nothing up front"*, and the
docs say *"Only tool names and server instructions load at session start"* with both
*"truncate[d] … at 2KB each"*. Live proof from this very session: two HTTP servers (`motion`,
`motion-plus`) injected an `# MCP Server Instructions` block of ≈640 characters ≈ **165 tokens** —
small, but **not zero**, and it is per session, forever, whether or not a tool is used.

---

## 4. The theoretical floor — what "absolute perfection" is, numerically

**Per resident session, the irreducible cost of having capability X available:**

| Design | Irreducible bytes / session | Irreducible tokens / session | Reaches the floor? |
|---|---|---|---|
| **A / H** (no MCP entry) | **0 B** — no process, no socket, no file descriptor | **0 tok** | **YES — this is the floor** |
| **B2** (out-of-band daemon) | **0 B** resident (the daemon is fleet-fixed, not per session) | **0 tok** | **YES** |
| **C / D / E / G** (an `http` entry, deferral on) | **0 process bytes.** One TCP socket while connected: ~4–8 KB kernel buffers client-side + the daemon's per-client session record (~1–10 KB). Call it **≤20 KB** | **`instructions` + `tool_names`.** Hard-bounded by the 2 KB truncation ⇒ **≤512 tok** for instructions, plus ≈8–12 tok per tool name. Measured real-world: **83 tok/server**. A server that ships **no** `instructions` and is not `alwaysLoad` costs only its names | **NEAR-floor** — 0 bytes, but a small permanent token tax |
| **B / F** (a stdio entry) | **≥99 MB** — the smallest MCP server process measured on this box; 339 MB for the real one; +116 MB if launched through `npx` | Same as C | **NO — off by 10⁴** |

**Three floor statements worth quoting to the lead:**
1. **Zero is achievable and it has a name: no MCP entry.** Every design that keeps an entry in
   `.mcp.json` pays ≥ the instructions+names token tax on all 150 sessions, forever. Only A/B2/H are
   *actually* zero on both axes.
2. **The bytes floor for an `http` entry is a socket, not a process** — ~20 KB against an ~80 MB/session
   budget is 0.025 %. For byte purposes, C/D/E/G are indistinguishable from perfect; they differ only in
   fixed cost, latency, and blast radius.
3. **The token floor is server-authored, so it is negotiable.** A server's `instructions` string is
   *its* choice; the client truncates at 2 KB. If a shared daemon is built in-house, ship an empty or
   one-line `instructions` and the per-session token cost collapses to the tool names alone.

**Fleet-fixed floor** (the number that actually matters once marginal is 0): one Rust gateway
(`agentgateway`, single static binary, no deps) ≈ **5–20 MB**; one Node MCP server ≈ **99–186 MB**
(measured); Docker MCP Gateway adds a container runtime you do not otherwise run. At 150 sessions,
even the worst of these is **≤0.3 % of RAM** — fixed cost is not a real axis on this box; blast radius
and ops are.

---

## 5. Prior art — off-the-shelf vs build

| Thing | What it is | Buy or build | Fit here |
|---|---|---|---|
| **`mfagerlund/mcp-on-demand`** | HTTP session manager on 127.0.0.1:9876; CLI/skill starts a server, calls tools, stops it. *"0 tokens when not in use."* | **Buy/port** (small) | **Best fit for B2/H.** Gaps to close: no idle timeout, manual `stop`, fixed port |
| **`sparfenyuk/mcp-proxy`** | Python bridge both ways; **one process can host many named stdio servers** (`--named-server`, `--named-server-config`) at `/servers/<name>/sse`; OAuth + header auth | **Buy** | Turns any stdio server into the `http` entry C/D need, with N servers in **one** process. Docs are **silent on concurrent-client behaviour and session isolation** — must be measured before trusting with 150 clients |
| **Supergateway** | stdio ⇄ SSE/WS/Streamable HTTP; **v3.3 added concurrent handling for shared stdio-backed deployments** | **Buy** | The explicit multi-client story mcp-proxy lacks |
| **agentgateway** (Linux Foundation, Rust) | Single static binary, zero deps; MCP **multiplexing** — many targets behind one endpoint with tool namespacing | **Buy** | The lowest fixed-cost front door if you end up with several shared servers |
| **MetaMCP** | Docker aggregator; namespaces → endpoints, middleware to filter/rewrite tools, API-key/OAuth, inspector | Buy (heavier) | Useful only if you need per-session *tool subsetting*; 1:1 endpoint↔namespace, no federation |
| **Docker MCP Gateway / Toolkit** | Central proxy; each server in its own container; **on-demand start** (*"if the server isn't already running, starts it as a Docker container"*), credential injection, per-server CPU/memory caps (`--memory-limit 2g`) | Buy — **but** | The only off-the-shelf thing that does D's on-demand *and* enforces memory caps. Cost: a container runtime this box does not otherwise run |
| **microsoft/mcp-gateway** | Reverse proxy, session-aware routing + lifecycle, **Kubernetes** | Skip | Wrong deployment substrate |
| **GH #28860** — *"Share MCP server processes across concurrent Claude Code sessions"* | Exactly this ask, upstream. Proposes a shared daemon per workspace + lazy init with aggressive idle shutdown + per-session MCP profiles. Reporter's numbers: macOS 24 GB, **4 sessions → 42 processes, ~1.9 GB** | **Closed as duplicate** | **Nobody is shipping this for us.** Build or buy |
| **GH #45880** | The 64 GB M1 Max kernel panic (see §1) | **Closed, not planned** | Same conclusion, with a corpse |
| **MCP spec 2026-07-28 (RC)** | SEP-2567 removes `Mcp-Session-Id` and the protocol session; SEP-2575 removes the `initialize` handshake; SEP-2243 adds routable `Mcp-Method`/`Mcp-Name` headers | Watch | Makes a shared daemon *strictly cheaper* — no per-client session state, any request to any replica. Materially improves C/D once clients and servers adopt it |
| **MCP transport security** | Servers **MUST** validate `Origin`, **SHOULD** bind 127.0.0.1 not 0.0.0.0; DNS-rebinding CVEs are real (rmcp GHSA-89vp-x53w-74fx; CVE-2026-11624) | Mandatory reading | Any local daemon we run is a **new unauthenticated local attack surface** — see §9 |

---

## 6. Composition with the fleet's other two levers

The goal names three levers: (i) per-session MCP ≈ 0, (ii) **admission control on active count**,
(iii) **spill overflow to the cloud lane**.

| Design | Effect on **admission control** | Effect on **cloud spill** |
|---|---|---|
| **A / H** | **Improves it.** Per-session cost becomes a single constant (249 MB), so the admission predicate is `N × 249 MB + fixed ≤ budget` — one number, no per-project special-casing | **Composes perfectly.** A cloud session needs no local anything |
| **B2** | Improves it (constant), with one caveat: an *active* MCP session adds a burst the admission controller cannot see unless the daemon reports it | Composes — but the CLI must be reachable from the cloud sandbox, or the capability is local-only by construction |
| **C / D / G** | Improves it (constant marginal), **but adds a second scarce resource**: concurrent *slots* on the shared server (one browser!). Admission must then gate on two dimensions, not one | **DEGRADES it.** A cloud session cannot reach `127.0.0.1`. Spilled sessions need a *different* MCP profile — i.e. two configurations to keep in sync, and a capability cliff at the spill boundary |
| **E** | Improves it (constant, and the cost is off-box entirely) | **Best composition** — identical config works local and cloud; this is the only design where the spill boundary is invisible |
| **F** | **Actively fights it.** Per-session cost depends on the session's *cwd*, so the admission controller must model per-project MCP penetration to predict RAM. This is the single strongest argument against staying put | Neutral |

**The sharp version:** local-daemon designs (C/D/G) buy byte-perfection at the price of making the
cloud lane a second-class citizen. A/H/E keep all three levers orthogonal.

---

## 7. Recommendations

**#1 — H (+A): delete the stdio entry; serve the dominant capability off the browser endpoint that is
already running.** The entire measured problem is one stanza in one file: `chrome-devtools` in
`reso-management-app/.mcp.json`, inherited by 79 worktrees, costing 339 MB of chain plus 195 MB of
browser per session that touches it. There is already a shared, debuggable browser on
`127.0.0.1:9222` (Dia), and the fleet already owns two non-MCP paths to it (`agent-browser` CLI,
`dia-agent` skill). Removing the entry takes marginal memory to a hard **0 B** and marginal context to
a hard **0 tok** — the floor, not an approximation of it — with **zero new daemons, zero new ports,
zero new attack surface, and zero new failure modes**, and it leaves admission control a single
constant and the cloud lane untouched. The residual work is honest and small: confirm the CLI path
covers what the MCP tools were used for (performance traces, network inspection), and keep
`--browserUrl http://127.0.0.1:9222` available for anyone who insists on the MCP shape, since that
flag alone removes the +195 MB per-session browser even if the server process stays.

**#2 — B2 for whatever genuinely needs MCP semantics, with D's idle-exit bolted on.** Some servers
are worth the protocol — the value is `prompts/`, `resources/`, `list_changed`, not just a function
call. For those, do not put them in `.mcp.json` at all: run one out-of-band session manager
(`mcp-on-demand` ported, or `mcp-proxy --named-server-config` fronted by a thin CLI) that owns the
stdio children, and add the idle-exit `mcp-on-demand` is missing (its documented gap). This keeps the
per-session cost at exactly zero bytes and zero tokens — B2 is the *only* daemon design that also
reaches the token floor, because Claude Code never learns the server exists — while the fixed cost
(~50–200 MB) is 0.3 % of the box and is paid once for 150 sessions. Accept its one real weakness
deliberately: an out-of-band daemon is invisible to Claude Code's reconnect logic, so the CLI must
return a legible error and the skill must say what to do with it.

**Deliberately not #1: C.** It is the intuitive answer (one daemon, `http` entries everywhere) and it
is *nearly* free on bytes — but it takes the fleet from "no shared mutable state" to "one browser, one
token, one process shared by 150 sessions", degrades the cloud lane, and still pays a permanent
per-session token tax that A/B2/H do not. Choose it only for a server that is genuinely concurrency-safe
and genuinely needed everywhere.

---

## 8. Free wins that hold under *every* design (do these regardless)

1. **Drop `npx` from any surviving stdio entry.** The `npm exec` wrapper is a resident process costing
   **70.8–117.3 MB of footprint and doing no MCP work** — 21–35 % of a chain. The resolved binary
   exists (`~/.npm/_npx/15c61037b1978c83/node_modules/.bin/chrome-devtools-mcp`); pointing `command` at
   it (or at a pinned local install) removes an entire process per chain. Trade-off: it pins the
   version, which you want anyway at 150 sessions.
2. **Cap the child heap.** `"env": {"NODE_OPTIONS": "--max-old-space-size=256"}` per stdio entry — the
   mitigation #45880 identified as highest-impact and which **is not set anywhere in this fleet's
   config today** (verified). It bounds V8 old-space, not RSS, so it is a guardrail, not a fix.
3. **Never set `alwaysLoad: true`** — it converts a background connect into a startup wait (5 s cap)
   and un-defers every schema.
4. **Leave `MCP_CONNECTION_NONBLOCKING` at its default.** Setting it to `0` makes startup wait for
   every server; at 150 sessions/day of churn that is pure latency.
5. **Treat `.mcp.json` as fleet-wide config, because it is.** One repo file × 79 worktrees. Whatever is
   decided, the enforcement point is that file, not `~/.claude.json` (which the fleet does not read).

---

## 9. Adversarial self-pass — what I got wrong or nearly missed

The brief guessed I would underweight **ops complexity** and **failure blast radius**. I checked both
with tool calls, and on this box the first guess is **wrong in the fleet's favour** while the second is
**worse than I first scored it** — plus three axes nobody named.

1. **Ops complexity is CHEAPER here than the generic case — I was over-penalising C/D.** This machine
   already supervises **47 LaunchAgent plists (~20 loaded)** and ships a `launchd-parity-lint.sh`. The
   marginal cost of one more supervised daemon is a plist and a lint entry, not a new operational
   discipline. I upgraded C/D's ops grade accordingly. What stays expensive is *not* the plist — it is
   version pinning across 150 clients and the pool logic for non-concurrent servers.
2. **Blast radius is worse than "the daemon dies", and the mechanism is resource sharing, not process
   death.** `chrome-devtools-mcp` binds **one** browser per process (upstream #926 is the open request
   to fix this). A singleton daemon therefore serialises 150 sessions onto one browser and produces
   *silent cross-session contamination* (tabs, cookies, navigation) rather than a clean failure. That
   moved C/D's isolation grade to **D** and is the single strongest reason recommendation #1 is not a
   daemon.
3. **A security axis the brief's columns omit entirely.** Every local-daemon design adds an
   **unauthenticated localhost port** reachable by *any* process on this Mac — including an npm
   postinstall in any of the repos these 150 sessions are editing. The MCP spec's own guidance (validate
   `Origin`, bind 127.0.0.1) exists because of live DNS-rebinding CVEs (rmcp GHSA-89vp-x53w-74fx;
   CVE-2026-11624; Playwright-MCP CVE-2025-9611). Today's stdio design has **zero** such surface —
   moving to C/D *creates* a class of risk that A/B2/H do not. Rate this before the byte counts.
4. **A hypothesis I killed rather than repeat: process/fd exhaustion.** I expected the 150-session
   target to hit `kern.maxprocperuid`. It does not — 10,666 allowed, 1,012 in use, `maxfiles` 491,520.
   RAM is the only ceiling; do not let anyone spend design budget on process hygiene.
5. **A premise I overturned.** The brief's "user-scope browsermcp configured but 0 live" is true of
   `~/.claude.json`, which **no fleet session reads** (`CLAUDE_CONFIG_DIR=~/.claude-secondary`,
   verified on three live pids). Had I not checked, every migration estimate in §2 would have pointed
   at the wrong file.
6. **The metric basis matters and the brief's "~340 MB/session" is ambiguous.** RSS says 610 MB/session;
   physical footprint says 249 MB. The 340 MB figure coincides almost exactly with the **MCP chain's**
   footprint (339 MB), not the session's. All arithmetic in §1 uses footprint, because that is what
   macOS charges against memory pressure — if the lead's fleet ceiling was computed at 340 MB/session
   RSS-style, it is wrong in *both* directions and should be re-derived.
7. **Orphan accumulation (#33947) is a real hazard but is not currently firing** — zero `ppid=1` MCP
   processes on this box right now. Worth a watchdog, not a design constraint.

---

## 10. Alternatives considered and ruled out

- **Per-session heap caps as the whole answer** (`--max-old-space-size=256`): bounds V8 old space, not
  RSS; 150 × 256 MB is still 38 GB. A guardrail, never an architecture. Kept as §8.2.
- **`inetdCompatibility` launchd activation**: one process per connection — the opposite of sharing.
- **Kubernetes-shaped gateways** (microsoft/mcp-gateway, AWS AgentCore Gateway): wrong substrate for a
  single Mac.
- **MetaMCP / Docker MCP Toolkit as the default front door**: both drag in a container runtime or a
  multi-tenant control plane to solve a problem that is, on this box, one `.mcp.json` stanza.
- **Waiting for upstream to ship shared/lazy MCP**: #28860 closed duplicate, #45880 closed not-planned,
  #26666 / #38365 / #18497 / #13805 open and unshipped. Not a plan.
- **Tunnelling the local daemon to cloud sessions** (ngrok-style) to fix C/D's spill problem: exports
  an unauthenticated local surface to the internet. Rejected on §9.3 grounds alone.

---

## 11. OPEN — do not treat as settled

- **OPEN (sibling: CC client failure semantics)** — exact 2.1.220 behaviour when a shared daemon is
  *down at session start* vs *dies mid-turn*: I have the docs' stated retry policy (3 startup / 5
  mid-session, HTTP+SSE) and the binary's degradation strings, but no observed run. Also unverified:
  whether `mcp_toggle` is reachable from a hook or only from the SDK control channel.
- **OPEN (sibling: daemon multiplexing)** — whether any candidate server is concurrency-safe at N=150
  clients. `mcp-proxy`'s docs are explicitly silent on concurrent clients and session isolation;
  Supergateway claims it since 3.3 but I did not test it.
- **OPEN (sibling: per-server verdicts)** — which of the fleet's servers have hosted equivalents (lane
  E) and which are irreducibly machine-local.
- **OPEN (mine, cheap to close)** — does 2.1.221+'s `cached … connects on first use` actually eliminate
  the *startup connection* for remote servers, or only the startup *wait*? Confirmed only that the
  string is absent from 2.1.220. If it eliminates the connection, C/D/E get strictly better and the
  binary upgrade becomes part of the design.
- **OPEN** — real cold-start latency of a socket-activated/idle-exited browser daemon under load. My
  1.3–3 s is composed from a measured `npx` boot (1.22 s) plus an unmeasured browser launch.

---

## Sources

- Claude Code MCP reference — transports, scopes, `alwaysLoad`, tool search, reconnect, `cached` status: https://code.claude.com/docs/en/mcp
- Binary evidence: `strings -a /Users/chrisren/.claude-220/node_modules/@anthropic-ai/claude-code/bin/claude.exe` (2.1.220)
- GH anthropics/claude-code **#28860** share MCP processes across sessions (closed, duplicate): https://github.com/anthropics/claude-code/issues/28860
- GH anthropics/claude-code **#45880** concurrent sessions multiply MCP processes → kernel panic (closed, not planned): https://github.com/anthropics/claude-code/issues/45880
- GH anthropics/claude-code lazy-init requests **#26666**, **#38365**, **#18497**, **#13805**
- GH ChromeDevTools/chrome-devtools-mcp **#926** multi-session support: https://github.com/ChromeDevTools/chrome-devtools-mcp/issues/926
- chrome-devtools-mcp (`--browserUrl`, `--isolated`, lazy browser launch): https://github.com/ChromeDevTools/chrome-devtools-mcp
- `mfagerlund/mcp-on-demand`: https://github.com/mfagerlund/mcp-on-demand
- `sparfenyuk/mcp-proxy` (named servers): https://github.com/sparfenyuk/mcp-proxy
- Supergateway (concurrent clients, v3.3): https://www.augmentcode.com/mcp/supergateway-mcp-transport-gateway
- agentgateway MCP multiplexing: https://agentgateway.dev/docs/local/latest/mcp/connect/multiplex/
- MetaMCP: https://github.com/metatool-ai/metamcp
- Docker MCP Gateway (on-demand container start, resource limits): https://docs.docker.com/ai/mcp-catalog-and-toolkit/mcp-gateway/
- microsoft/mcp-gateway: https://github.com/microsoft/mcp-gateway
- MCP 2026-07-28 stateless spec (SEP-2567 / 2575 / 2243): https://blog.modelcontextprotocol.io/posts/2026-07-28-release-candidate/
- MCP transport security / DNS rebinding: https://modelcontextprotocol.io/specification/2025-11-25/basic/transports · https://github.com/modelcontextprotocol/rust-sdk/security/advisories/GHSA-89vp-x53w-74fx
- Apple `launch_activate_socket` (C API, no Node binding): https://developer.apple.com/documentation/xpc/launch_activate_socket
