# measure-mcp-servers.md — MCP layer of the `claude` cold start

Axis: **mcp-servers**. Measured 2026-08-16 on the operator's macOS box (Darwin 24.6.0, arm64)
under normal fleet load (~24 live sessions). Every number below carries the exact command.

READ-ONLY throughout: no config edited, no process killed.

---

## 1. Registration inventory (dumped, not recalled)

### Project scope — `/Users/chrisren/Development/.worktrees/wt-cc-143835-83020/.mcp.json`

```json
{
  "mcpServers": {
    "uidotsh":         { "url": "https://ui.sh/mcp?token=<REDACTED>", "type": "http" },
    "chrome-devtools": { "command": "bash", "args": ["scripts/mcp/chrome-devtools-mcp.sh"] },
    "motion":          { "url": "https://mcp.motion.dev",      "type": "http" },
    "motion-plus":     { "url": "https://mcp.motion.dev/plus", "type": "http" }
  }
}
```

reso `.claude/settings.json`:
```
enabledMcpjsonServers  = ['uidotsh', 'motion', 'motion-plus']
disabledMcpjsonServers = ['chrome-devtools']
```
=> chrome-devtools is the ONLY stdio server in the project file and it is disabled. Confirmed
the deliberate ~267 MB saving documented in reso CLAUDE.md.

### User scope — `mcpServers` in each `<CONFIG_DIR>/.claude.json`

| config dir | motion | motion-plus | ms365 | mac-messages |
|---|---|---|---|---|
| `~/.claude.json` (129 KB) | http | http | **stdio `npx -y @softeria/ms-365-mcp-server@latest`** | — |
| `~/.claude/.claude.json` (69 KB) | http | http | stdio (fnm bin) | **stdio `uvx mac-messages-mcp`** |
| `~/.claude-tertiary` (184 KB) | http | http | stdio (fnm bin) | stdio `uvx` |
| `~/.claude-next` (175 KB) | http | http | stdio (fnm bin) | — |
| `~/.claude-quaternary` (185 KB) | http | http | stdio (fnm bin) | stdio `uvx` |
| `~/.claude-secondary` (205 KB) | http | http | stdio (fnm bin) | stdio `uvx` |

Command produced this:
```bash
for d in ~/.claude.json ~/.claude/.claude.json ~/.claude-tertiary/.claude.json \
         ~/.claude-next/.claude.json ~/.claude-quaternary/.claude.json ~/.claude-secondary/.claude.json; do
  python3 -c "import json;d=json.load(open('$d'));print(list(d.get('mcpServers',{}).keys()))"
done
```

**Finding R-1: `~/.claude.json` (the DEFAULT config dir, 129 KB) registers ms365 as
`npx -y @softeria/ms-365-mcp-server@latest`** — an `@latest` npx spawn, i.e. a registry
round-trip on every cold spawn unless npx's cache short-circuits. Every other config dir
points at the resolved fnm binary. See §3 for the measured delta.

**Finding R-2: motion + motion-plus are registered TWICE** for any session whose cwd is reso —
once user-scope in `.claude.json`, once project-scope in `.mcp.json`. Dedup behaviour is
CC-internal; the observed connect count in this session's SessionStart banner is one each.


---

## 2. Per-server transport + measured handshake cost

Environment for §2–§4: config dir `~/.claude-tertiary`, cwd the reso worktree above,
`uptime` → `load averages: 24.43 22.96 21.68` at start of measurement.

### 2a. stdio servers — direct spawn + JSON-RPC `initialize` + `tools/list`

Harness `scratchpad/mcp/stdio_probe.py`: spawns the exact registered command with
`start_new_session=True`, writes `initialize`, then `notifications/initialized` +
`tools/list`, times each, reads parent RSS, SIGTERMs its own (separate) process group.

> Dead end worth recording: v1 of the harness called `os.killpg(os.getpgid(p.pid), SIGTERM)`
> **without** `start_new_session=True` — the child shares the caller's pgid, so the probe
> killed its own shell (exit 144). Fixed by giving the child its own session.

```bash
python3 stdio_probe.py ms365 "/Users/chrisren/Library/Application Support/fnm/aliases/default/bin/ms-365-mcp-server"   # x4
python3 stdio_probe.py mac-messages uvx mac-messages-mcp                                                               # x4
```

Raw:

```
{"label":"ms365","t_initialize_s":0.3978,"t_tools_list_s":0.4378,"n_tools":188,"rss_kb_parent":183520}
{"label":"ms365","t_initialize_s":0.3545,"t_tools_list_s":0.4046,"n_tools":188,"rss_kb_parent":184512}
{"label":"ms365","t_initialize_s":0.3463,"t_tools_list_s":0.3891,"n_tools":188,"rss_kb_parent":179104}
{"label":"ms365","t_initialize_s":0.3491,"t_tools_list_s":0.3901,"n_tools":188,"rss_kb_parent":190576}
{"label":"mac-messages","t_initialize_s":1.1703,"t_tools_list_s":1.1717,"n_tools":11,"rss_kb_parent":66320}
{"label":"mac-messages","t_initialize_s":0.3384,"t_tools_list_s":0.3396,"n_tools":11,"rss_kb_parent":50112}
{"label":"mac-messages","t_initialize_s":0.3895,"t_tools_list_s":0.3906,"n_tools":11,"rss_kb_parent":50160}
{"label":"mac-messages","t_initialize_s":0.3453,"t_tools_list_s":0.3465,"n_tools":11,"rss_kb_parent":50816}
```

| server | min | **median t_initialize** | tools exposed | tools/list adds |
|---|---|---|---|---|
| **ms365** (node, fnm bin) | 0.346 | **0.351 s** | **188** | ~40 ms |
| **mac-messages** (uvx→python) | 0.338 | **0.367 s** warm / **1.170 s** cold | 11 | ~1 ms |

mac-messages' 1.170 s first run is a **cold `uv` archive resolution**; subsequent runs hit
`~/.cache/uv/archive-v0/…`. Two cache generations are live on the box
(`tNRral8tkl_0g6BW`, `ZuFMFY0ABGa2bvrf`), so a `uvx` version bump re-pays ~1.2 s once.

R-1 addendum (measured, not inferred): the fnm-bin form used by the five real config dirs
costs **0.35 s**. The `npx -y …@latest` form in the legacy `~/.claude.json` was NOT measured
(no session uses that dir today) → **UNKNOWN**, but it necessarily adds an npm resolution
step the fnm form does not have.

### 2b. http servers — DNS / TCP / TLS / MCP `initialize`

Harness `scratchpad/mcp/http_probe2.py`: separate `getaddrinfo`, bare `create_connection`,
`wrap_socket`, then a **fresh-connection** POST of a real MCP `initialize` (so the
`initialize_post_s` column is the full connect+TLS+RPC a client actually pays).

> Two dead ends: (1) python.org 3.11 has no system CA bundle → `CERTIFICATE_VERIFY_FAILED`;
> fixed with `certifi.where()`. (2) With python's default User-Agent all three edges return
> **403 Forbidden** (bot rule). `User-Agent: node` gets real responses. A naive "is the MCP
> endpoint up" curl check would therefore read as broken.

```bash
python3 http_probe2.py motion      https://mcp.motion.dev
python3 http_probe2.py motion-plus https://mcp.motion.dev/plus
python3 http_probe2.py uidotsh     'https://ui.sh/mcp?token=<REDACTED>'
```

Raw (3 rounds):

```
motion       dns .0038 tcp .0374 tls .0516 init .1492 http 200  serverInfo.name=motion
motion-plus  dns .0041 tcp .0459 tls .0507 init .1305 http 401  Unauthorized
uidotsh      dns .0034 tcp .0221 tls .0404 init .4164 http 200  tools+resources
motion       dns .0034 tcp .0244 tls .1891 init .1280 http 200
motion-plus  dns .0038 tcp .0262 tls .0536 init .1085 http 401
uidotsh      dns .0041 tcp .0282 tls .0607 init .3428 http 200
motion       dns .0034 tcp .0434 tls .0688 init .1103 http 200
motion-plus  dns .0043 tcp .0418 tls .0445 init .1177 http 401
uidotsh      dns .0038 tcp .0323 tls .0508 init .4005 http 200
```

| server | dns | tcp | tls | initialize POST ×3 | **median** | result |
|---|---|---|---|---|---|---|
| motion | 3.4–3.8 ms | 24–43 ms | 52–189 ms | .149/.128/.110 | **0.128 s** | 200 |
| motion-plus | 3.8–4.3 ms | 26–46 ms | 44–54 ms | .131/.109/.118 | **0.118 s** | **401** (probe has no OAuth) |
| uidotsh | 3.4–4.1 ms | 22–32 ms | 40–61 ms | .416/.343/.401 | **0.401 s** | 200 |

**uidotsh is ~3× the slowest HTTP server** and is the only one registered *solely*
project-scope.

---

## 3. Fleet memory — the multiplier the operator asked about

```bash
ps -Ao rss,pid,args | grep 'ms-365-mcp-server'            | grep -v grep | awk '{s+=$1;n++} END{print n, s/1024}'
ps -Ao rss,pid,args | grep 'uv tool uvx mac-messages-mcp' | grep -v grep | awk '{s+=$1;n++} END{print n, s/1024}'
ps -Ao rss,pid,args | grep 'bin/mac-messages-mcp' | grep -v 'uv tool' | grep -v grep | awk '{s+=$1;n++} END{print n, s/1024}'
```

| process class | n live | total RSS | mean | range |
|---|---|---|---|---|
| `node ms-365-mcp-server` | **17** | **1332 MB** | 78 MB | 45 → 138 MB |
| `uv tool uvx mac-messages-mcp` (supervisor) | 12 | 263 MB | 22 MB | 17 → 48 MB |
| `python … mac-messages-mcp` (real server) | 12 | 300 MB | 25 MB | 11 → 59 MB |
| **MCP stdio total** | **41 procs** | **≈1.90 GB** | | |
| `claude` binaries (scale reference) | 28 | 8.75 GB | 313 MB | |

**Finding M-1 — mac-messages costs TWO processes per session.** `uv tool uvx` stays resident
as a supervisor beside the python child it spawned. 47 MB/session for an 11-tool server, and
12 idle `uv` supervisors whose only job is holding a pipe.

**Finding M-2 — ms365 RSS grows monotonically with session age.** The 8 youngest processes
sit at 45–46 MB; the oldest (7 h 41 m elapsed) is at 138 MB. Per-PID:
`45.3 45.3 45.5 45.9 46.3 46.3 46.4 46.4 | 81.4 87.9 97.7 101.2 101.6 108.6 113.7 135.0 138.3`.

**Finding M-3 — memory is NOT the system-wide cause of slowness. Refuted.**

```bash
sysctl -n hw.memsize   # 68719476736  → 64 GB
memory_pressure | tail # System-wide memory free percentage: 78%
sysctl vm.swapusage    # total = 0.00M  used = 0.00M  free = 0.00M
uptime                 # load averages: 24.43 22.96 21.68
```

Zero swap, 78 % free. 1.9 GB of MCP servers on a 64 GB box causes no paging. The contended
resource is **CPU** (load ~24 on the sampled box), not RAM. The MCP layer's system-wide cost
is real but it is ~3 % of RAM and cannot be the mechanism behind a slow prompt.

---

## 4. Prior-art re-check — R4-cc-latency.md (measured 2026-08-11)

| R4 claim | verdict today |
|---|---|
| "MCP configs resolve **207 ms**, blocking" | not re-derived here → **UNKNOWN** (needs a fresh `--debug-file` run; see §5) |
| "MCP HTTP connects 191/385/386 ms, **not blocking** (parallel)" | **HOLDS** — my out-of-band handshakes are 128/118/401 ms, same order; uidotsh is still the slow one (~400 ms) |
| "MCP costs ~1.6 s at most, largely parallel. Not the bottleneck." | **HOLDS in direction**; but R4's own ablation (`--strict-mcp-config`: 10.80 s vs 12.44 s) was *inside its own noise*, so it never established a number. §5 supersedes it. |
| R4 enumerates only **motion / motion-plus / uidotsh** as connecting | **STALE** — 5 servers connect today. R4's run logged no stdio transport at all. |
| "`session-start.sh` shells a second `claude` CLI for `mcp list`, 2.52 s" | R4's own addendum says fixed (`1d03837c`, SWR cache, 2.03 → 0.036 s). Re-verified in §5. |

---

## 5. THE DECISIVE QUESTION — does MCP block the usable prompt? **NO.**

### 5a. Zero-token A/B under a pty (binary 2.1.220, the fleet's dominant binary)

Two arms differing in **exactly one flag value**: the `--mcp-config` file. Same throwaway
config dir (no user hooks → the 15-hook layer is excluded by construction), same empty cwd,
same binary. Harness `/tmp/ptyboot.py` (a sibling axis-agent's, reused): `pty.fork`, timestamp
every output chunk, SIGINT+SIGKILL at DEADLINE. **Zero tokens — the throwaway dir has no
credentials, so no API call is ever made.**

Setup dead end worth recording: a bare throwaway `CLAUDE_CONFIG_DIR` **stalls on the
trust-folder modal** ("Is this a project you created or one you trust?") and never paints a
prompt — the boot probe then measures the modal, not startup. Fix: seed
`projects["<cwd>"].hasTrustDialogAccepted=true` **for the `/private/tmp/...` realpath too**
(macOS `/tmp` is a symlink; the `/tmp/...` key alone is not enough).

```bash
cd /tmp/mcpprobe/work
export CLAUDE_CONFIG_DIR=/tmp/mcpprobe/cfg2
B=~/.claude-220/node_modules/.bin/claude
DEADLINE=25 MARKERS='? for shortcuts|MCP server' python3 /tmp/ptyboot.py "$B" \
  --setting-sources project --strict-mcp-config --mcp-config /tmp/mcpprobe/all5.json   # x3
# ...and the same with /tmp/mcpprobe/none.json  ({"mcpServers":{}})                     # x3
```

Raw:

```
all5 run1  first_byte=0.317  "? for shortcuts"=0.422  "MCP server"=0.491
all5 run2  first_byte=0.356  "? for shortcuts"=0.504  "MCP server"=0.558
all5 run3  first_byte=0.360  "? for shortcuts"=0.496  "MCP server"=0.545
none run1  first_byte=0.365  "? for shortcuts"=0.449  (no MCP line)
none run2  first_byte=0.356  "? for shortcuts"=0.449  (no MCP line)
none run3  first_byte=0.389  "? for shortcuts"=0.476  (no MCP line)
```

| arm | time-to-first-byte min/median | **time-to-usable-prompt min/median** |
|---|---|---|
| **5 MCP servers** | 0.317 / 0.356 s | 0.422 / **0.496 s** |
| **0 MCP servers** | 0.356 / 0.365 s | 0.449 / **0.449 s** |

**Δ median = +47 ms. Δ min = −27 ms (the MCP arm is *faster* on its best run).**
Five MCP servers — including two `stdio` spawns — cost **nothing measurable** on the path to
a usable prompt. This is **CONCURRENT**, not BLOCKING.

### 5b. Mechanism — the debug log names the one awaited step and the parallel rest

```bash
DEADLINE=22 python3 /tmp/ptyboot.py "$B" --setting-sources project \
  --strict-mcp-config --mcp-config /tmp/mcpprobe/all5.json --debug-file /tmp/mcpprobe/dbg.log -d mcp
```

t0 = first debug line `22:34:13.465`. Prompt usable in this run at **+0.661 s**.

| event | abs | Δ from t0 | duration reported |
|---|---|---|---|
| `[STARTUP] Loading MCP configs...` | 13.607 | +0.142 | |
| **`[STARTUP] MCP configs resolved in 0ms (awaited at +70ms)`** | 13.677 | +0.212 | **0 ms — the ONLY awaited MCP step** |
| `ms365: Starting connection with timeout of 30000ms` | 13.723 | +0.258 | |
| `mac-messages: Starting connection…` | 13.751 | +0.286 | |
| `motion` / `uidotsh`: HTTP transport init | 13.757 | +0.292 | |
| **`motion-plus: Skipping connection (cached needs-auth)`** | 13.757 | +0.292 | **0 ms — never dials** |
| **prompt usable (`? for shortcuts`)** | — | **+0.661** | — |
| `motion: Successfully connected (transport: http) in 255ms` | 14.012 | +0.547 | 255 ms |
| `uidotsh: Successfully connected (transport: http) in 446ms` | 14.203 | +0.738 | 446 ms |
| `ms365: Successfully connected (transport: stdio) in 971ms` | 14.667 | +1.202 | 971 ms |
| `mac-messages: Successfully connected (transport: stdio) in 1120ms` | 14.871 | +1.406 | 1120 ms |

Two of the four connects **complete after the prompt is already usable** (+1.202 s and
+1.406 s vs a prompt at +0.661 s). Per-server connect timeout is **30 000 ms** and it does
not gate the prompt — a wedged server delays *tool availability* for up to 30 s, never the
prompt. That is the structural answer.

`mac-messages` also emits a pydantic `IncompleteFieldDefinitionWarning` on stderr at connect —
logged `[ERROR]`, harmless, but it is noise on every session's MCP error channel.

### 5c. Same probe against the operator's REAL config dir

`CLAUDE_CONFIG_DIR=~/.claude-tertiary`, cwd = the real reso worktree, `--setting-sources project`
(so the 15 user SessionStart hooks — a different axis, and the one with side effects — do not
fire; reso's own 4 project hooks do, and R4 prices them at 0.02 s).

```bash
DEADLINE=20 CLAUDE_CONFIG_DIR=/Users/chrisren/.claude-tertiary python3 /tmp/ptyboot.py \
  "$B" --setting-sources project --debug-file /tmp/mcpprobe/real$i.log -d mcp     # i=1,2,3
```

| run | MCP configs resolved | awaited at | motion | uidotsh | motion-plus | prompt usable |
|---|---|---|---|---|---|---|
| 1 | 86 ms | +565 ms | 514 ms | 709 ms | 1190 ms | 1.307 s |
| 2 | 109 ms | +616 ms | 283 ms | 463 ms | 403 ms | 1.194 s |
| 3 | 79 ms | +525 ms | 317 ms | 437 ms | 652 ms | 1.086 s |
| **median** | **86 ms** | +565 ms | 317 ms | 463 ms | 652 ms | **1.194 s** |

- **86 ms is the whole blocking contribution of this layer** — and even that resolves before
  its own await point (`resolved in 86ms`, `awaited at +565ms`), so its *marginal* cost on the
  critical path is between 0 and 86 ms. This supersedes R4's 207 ms with a fresher number.
- `motion-plus` **does** connect here (the real dir holds its OAuth token) — 403–1190 ms,
  the slowest and jitteriest of the three. Under the token-less throwaway dir it is skipped
  outright, which is why it costs 0 there.
- **`ms365` and `mac-messages` did NOT appear in this run.** `--setting-sources project` drops
  user scope, and those two are registered **only** user-scope. That is itself the cleanest
  proof of where each server comes from: motion / motion-plus / uidotsh resolved from the
  project `.mcp.json`; ms365 + mac-messages are purely user-scope.
- Prompt-usable is 1.194 s here vs 0.449 s in the throwaway dir — a **+0.75 s** delta owned by
  the 184 KB `.claude.json` + skills + project settings, **not** by MCP (§5a controls for it).

### 5d. Is anything the operator does in the first 30 s blocked?

**No.** Prompt live at 0.45 s (clean) / 1.19 s (real config); the last MCP server is callable
at ~1.4 s. The exposure window between "can type" and "all tools callable" is ~0.2–0.8 s, far
shorter than the time to type a prompt. And the product does not wait even then: this
session's own SessionStart banner reads *"The following MCP servers are still connecting —
their tools are not yet available but will appear shortly: mac-messages, motion, motion-plus,
ms365, uidotsh"*, i.e. the first turn is dispatched with the model told the tools are pending.
**CONFIRMED non-blocking, by A/B, by debug timeline, and by the product's own banner.**

---

## 6. Usage frequency — which servers earn their place

The deferral decision needs demand, not just cost. Counted **actual invocations**
(`"name":"mcp__<server>__`, i.e. a `tool_use` block — NOT a mere mention, which would
false-positive on every transcript that merely lists the deferred tool names).

```bash
files=$(find ~/.claude*/projects -name '*.jsonl' -mtime -30)
for s in ms365 mac-messages motion-plus motion uidotsh chrome-devtools; do
  echo "$files" | xargs -P 8 -n 200 grep -l "\"name\":\"mcp__${s}__" | wc -l
  echo "$files" | xargs -P 8 -n 200 grep -o "\"name\":\"mcp__${s}__" | wc -l
done
```

**n = 6 686 transcripts, 30 days.**

| server | transcripts with ≥1 call | share | total calls | tools exposed |
|---|---|---|---|---|
| chrome-devtools *(already disabled in reso)* | **160** | **2.39 %** | **5 617** | ~26 |
| motion | 71 | 1.06 % | 225 | 2 |
| motion-plus | 55 | 0.82 % | 111 | 3 |
| **ms365** | 15 | **0.22 %** | 166 | **188** |
| uidotsh | 7 | 0.10 % | 27 | 1 |
| **mac-messages** | **0** | **0.00 %** | **0** | 11 |

**Finding U-1 — the disabled server is the most-used one.** chrome-devtools was switched off
to save ~267 MB and it is, by a factor of 2–25, the most-invoked MCP server in the fleet
(5 617 calls / 30 d). reso's CLAUDE.md justified the flip with "3.2 % of transcripts / 2 384
calls"; re-measured across all config dirs today it is 2.39 % / 5 617 calls — the *rate* claim
still roughly holds, the *volume* has more than doubled. The flip was defensible on RAM; it
was made against the single highest-demand server.

**Finding U-2 — mac-messages has ZERO invocations in 30 days**, while costing **two resident
processes and ~47 MB in each of 12 live sessions**. It is registered in four of the six config
dirs. The operator's own global CLAUDE.md routes message queries through the **`msg` CLI**, not
this server — so the zero is structural, not a sampling artefact.

**Finding U-3 — ms365 is the worst cost/benefit by a wide margin.** 0.22 % of transcripts,
**188 tools** (more than every other MCP server combined, ×5), 78 MB mean RSS rising to 138 MB
with age, ×17 live processes = 1.33 GB, and the slowest stdio connect after mac-messages. Its
dominant cost is not latency at all — it is **188 tool definitions in the tool surface**.

---

## 7. Verdict for this axis

**The MCP server layer contributes ~86 ms (median, and possibly 0) to the BLOCKING critical
path, and is otherwise entirely CONCURRENT. It is not the cause of the slow cold start, and no
amount of MCP pruning will fix one.** The A/B is unambiguous: 5 servers vs 0 servers moves
time-to-usable-prompt by +47 ms median / −27 ms on minimums — inside this box's noise at
load 24.

What the layer *does* cost, and what is worth acting on:

| # | Item | Cost | Class | Worth deferring? |
|---|---|---|---|---|
| 1 | **mac-messages** | 2 procs + 47 MB × 12 sessions = **563 MB**, 1120 ms connect, 11 tools, **0 calls/30 d** | CONCURRENT | **YES — remove outright.** Pure loss. The `msg` CLI already owns this job. |
| 2 | **ms365** | **188 tools**, 1.33 GB across 17 procs, RSS grows 45→138 MB with age, 971 ms connect, 0.22 % use | CONCURRENT | **YES — opt-in, same pattern as chrome-devtools.** The tool-surface cost is the real one. |
| 3 | **chrome-devtools** (already opt-in) | 2.39 % use / 5 617 calls — **the most-used server** | n/a | **RECONSIDER the flip.** 267 MB on a 64 GB box with 0 swap buys back the highest-demand tool surface. |
| 4 | duplicate motion/motion-plus registration (user + project) | config debt, no measured latency | — | tidy, not urgent |
| 5 | `~/.claude.json` ms365 as `npx -y …@latest` | unmeasured registry round-trip per spawn | UNKNOWN | fix if that dir is ever used |
| 6 | uidotsh | slowest HTTP (401 ms), 1 tool, 0.10 % use | CONCURRENT | low priority; it is project-scoped and free at boot |

**Memory is not the system-wide culprit.** 1.90 GB of MCP servers, 8.75 GB of claude binaries,
on 64 GB with **0.00 MB swap and 78 % free**. Load average 24 says the contended resource is
CPU. Killing every MCP server on the box would return 1.9 GB of unpressured RAM and would not
make one session start faster.

### Prior-art ledger

| claim | source | verdict |
|---|---|---|
| MCP HTTP connects are parallel / non-blocking | R4 §1 | **HOLDS** — now proven by A/B, not just inferred |
| MCP configs resolve 207 ms, blocking | R4 §1 row 5 | **STALE number, claim holds** — re-measured **86 ms** median in the real config dir, 0 ms in a minimal one |
| "MCP costs ~1.6 s at most" (ablation 10.80 vs 12.44 s) | R4 §3 | **SUPERSEDED** — that ablation was inside its own noise. The controlled A/B here gives **≈0 ms**, not 1.6 s |
| R4 lists only motion / motion-plus / uidotsh connecting | R4 §1 row 6 | **STALE** — 5 servers connect today; R4 logged no stdio transport |
| `session-start.sh` `claude mcp list` costs 2.52 s | R4 §5 | fixed per R4's own addendum (`1d03837c`, SWR, → 0.036 s); not re-derived here → belongs to the hooks axis |
| chrome-devtools disabled: "3.2 % of transcripts, 2 384 calls / 30 d" | reso CLAUDE.md | **rate roughly holds (2.39 %), volume more than doubled (5 617)** — and it is the fleet's most-used MCP server |

### UNKNOWNs (not estimated)

- Cost of the `npx -y @softeria/ms-365-mcp-server@latest` form in the legacy `~/.claude.json` —
  no live session uses that dir, so it was never spawned.
- Whether `[STARTUP] MCP configs resolved` overlaps the awaited path fully (marginal cost 0)
  or partially (up to 86 ms). The log reports duration and await point, not their overlap.
- Per-server *token* cost of tool definitions in the system prompt (188 ms365 tools is clearly
  the dominant term, but the byte/token count was not measured here).
- Behaviour of the whole layer on binary **2.1.114** (`~/.claude-versions/current`, what the
  `claude-latest` wrapper execs). All §5 numbers are **2.1.220**, which is what 38 of the 42
  live claude processes actually run.

---

## 8. Exact registration line numbers (for whoever acts on §7)

```bash
grep -n 'uidotsh\|chrome-devtools\|motion' .mcp.json
grep -n 'McpjsonServers' .claude/settings.json
python3 -c "s=open('/Users/chrisren/.claude-tertiary/.claude.json').read()
for k in ['\"ms365\"','\"mac-messages\"','\"motion-plus\"']:
    i=s.find(k); print(k,'line',s[:i].count(chr(10))+1)"
```

| server | file | line |
|---|---|---|
| uidotsh | `<reso>/.mcp.json` | 3 |
| chrome-devtools | `<reso>/.mcp.json` | 7 |
| motion | `<reso>/.mcp.json` | 11 |
| motion-plus | `<reso>/.mcp.json` | 15 |
| `enabledMcpjsonServers` | `<reso>/.claude/settings.json` | 2 |
| `disabledMcpjsonServers: ["chrome-devtools"]` | `<reso>/.claude/settings.json` | **169** |
| motion-plus (user) | `~/.claude-tertiary/.claude.json` | 4687 |
| ms365 (user) | `~/.claude-tertiary/.claude.json` | 4691 |
| mac-messages (user) | `~/.claude-tertiary/.claude.json` | 4697 |

⚠️ Provenance note: an earlier draft of this file asserted that reso's settings.json has **no**
`disabledMcpjsonServers` key and that the gate is the `enabledMcpjsonServers` allowlist alone.
That was wrong — it came from a `head -80` read that truncated before **line 169**, where the
key does exist. The overwrite-guard hook caught it. Both keys are present; both point the same
way for chrome-devtools. Lesson: `grep -n '<key>'`, never `head -N`, to assert a key's absence.

**No side effects from this axis' probes.** All boot probes ran under a throwaway
`CLAUDE_CONFIG_DIR` or `--setting-sources project`; the 15 user SessionStart hooks
(`mailbox-wake-arm`, `session-register`, `dod-persist`) never fired. Post-probe orphan sweep
(`ps -Ao pid,ppid,... | awk '$2==1'`) found **zero** orphaned MCP processes; the MCP process
count rising 17→21 during the session traces to a live `blocked-tail-triage` teammate pane
(ppid 90711), not to these probes.
