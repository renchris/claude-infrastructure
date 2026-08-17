# Upstream knobs layer — measured 2026-08-16

Box: macOS darwin 24.6.0, ~24 live Claude sessions (noisy). Read-only w.r.t. all live config.

## 0. METHOD CORRECTION TO THE BRIEF (load-bearing)

The brief says "Use `node --cpu-prof` if the bundle is plain JS". **It is not JS.**

```
$ cat ~/.claude-versions/current/node_modules/@anthropic-ai/claude-code/package.json
  "version": "2.1.114", "bin": { "claude": "bin/claude.exe" }, "dependencies": {}
  optionalDependencies: @anthropic-ai/claude-code-{darwin-arm64,...}  (8 platform pkgs)
  scripts.postinstall: "node install.cjs"
$ file bin/claude.exe
bin/claude.exe: Mach-O 64-bit executable arm64        # 204,534,752 bytes = 195 MB
$ strings -n 8 bin/claude.exe | grep -m5 -iE 'bun!|Bun v'
Bun v${Bun.version} (html)
$ otool -L bin/claude.exe
  /usr/lib/libicucore.A.dylib, libresolv.9, libc++.1, libSystem.B      # 4 system dylibs only
```

⇒ It is a **Bun single-file compiled executable** (JS + Bun runtime + snapshot linked into one
Mach-O). There is no JS entry file to hand to `node`, no `node_modules` tree to profile, and no
V8. `node --cpu-prof` is structurally inapplicable. `cli-wrapper.cjs` exists ONLY as a fallback
for `--ignore-scripts` installs and is not on this machine's path (postinstall ran; `.bin/claude`
symlinks straight to `bin/claude.exe`).

Consequence for the whole investigation: **there is no upstream code-level knob to profile.**
The only upstream levers are (a) env vars the binary reads, (b) CLI flags, (c) config it loads.

## 1. THE HEADLINE MEASUREMENT — the 1.3s is NOT upstream

Binary vs the operator's launcher wrapper, same box, same minute:

```
$ B=~/.claude-versions/current/node_modules/.bin/claude
$ for i in $(seq 5); do { /usr/bin/time -p $B --version; } 2>&1 | grep real; done
real 0.05 / 0.06 / 0.05 / 0.05 / 0.05      # + a later interleave: 0.06 0.06 0.05 0.06 0.06
$ for i in $(seq 3); do { /usr/bin/time -p $B --help >/dev/null; } 2>&1|grep real; done
real 0.17 / 0.13 / 0.13
$ for i in $(seq 5); do { /usr/bin/time -p ~/bin/claude-latest --version; } 2>&1|grep real; done
real 1.96   <- printed "[claude-latest] 2.1.233 available…" = npm-view cache MISS
real 3.31   <- still cold
real 0.28 / 0.31 / 0.25
$ for i in $(seq 8); do { /usr/bin/time -p ~/bin/claude-latest --version >/dev/null; } 2>&1|grep real; done
real 0.23 0.21 0.21 0.23 0.20 0.21 0.20 0.19
```

| | n | min | median |
|---|---|---|---|
| raw binary `--version` | 10 | **0.05 s** | **0.055 s** |
| raw binary `--help` (full commander tree) | 3 | 0.13 s | 0.13 s |
| `~/bin/claude-latest --version` WARM | 11 | 0.19 s | **0.21 s** |
| `~/bin/claude-latest --version` COLD (npm view) | 2 | 1.96 s | 3.31 s |
| `node -e 0` floor | 3 | 0.02 s | 0.02 s |

⇒ **STALE, correct it: the lead's "1.50 / 1.29 / 1.28 s" for `claude-latest --version` is the
COLD path, not warm.** Warm today is 0.21 s median. The wrapper's 10-min `npm view` cache had
expired for all three of the lead's runs (the tell is the `2.1.233 available` line on stderr,
which prints only on a cache miss). Both numbers matter, but they are different knobs:
warm wrapper overhead = 0.21 − 0.055 = **~0.16 s**; a cache miss = **+1.7 to +3.2 s**.

⇒ **UPSTREAM IS NOT THE 1.3 s.** The vendor binary contributes 0.055 s to `--version`.

## 2. THE UPSTREAM PROFILER — first-party, undocumented, and it works

Decoded out of the binary (`strings -a -n 6 claude.exe`), minified but unambiguous:

```js
tgH = EH(process.env.CLAUDE_CODE_PROFILE_STARTUP)      // EH() = truthy-env test
oG8 = Math.random() < 0.005                            // 0.5% ambient sampling → telemetry
function egH(){ if(rG8) return; rG8=1; eG8();          // eG8 emits tengu_startup_perf
  if(tgH){ let H=tG8(); mkdirSync(dirname(H));
           writeFile(H, iG8(), {flush:true});
           h("Startup profiling report:"); h(iG8()); } }
function tG8(){ return path.join(s6(),"startup-perf",`${sessionId}.txt`) }
yjK = { import_time:["cli_entry","main_tsx_imports_loaded"],
        init_time:["init_function_start","init_function_end"],
        settings_time:["eagerLoadSettings_start","eagerLoadSettings_end"],
        total_time:["cli_entry","main_after_run"] }
```

`CLAUDE_CODE_PROFILE_STARTUP=1` ⇒ writes a **48-checkpoint report** to
`$CLAUDE_CONFIG_DIR/startup-perf/<session-uuid>.txt`. Zero tokens, no network, no prompt.
It does NOT fire on `--version` (that path exits before `egH()`); it fires on any real start,
including one killed at the welcome screen. **Undocumented** — zero web results for the name.

### Measured baseline (throwaway `CLAUDE_CONFIG_DIR`, empty settings, no MCP, no hooks, `/tmp` cwd)

`/tmp/ccup/run.sh baseline /tmp/ccup/cfg` ×3 → **225.3 / 203.7 / 203.0 ms** (median **203.7 ms**)

Largest single gaps in the median report (`/tmp/ccup/last-baseline.txt`):

| checkpoint | Δ | what it is |
|---|---|---|
| `profiler_initialized` | **57.1 ms** | process spawn → first JS. Bun runtime + 195 MB image. RSS already 180 MB. |
| `main_tsx_entry` | **54.7 ms** | the main module graph import |
| `loadSettingsFromDisk_start` | **45.0 ms** | gap after `init_configs_enabled` — pre-settings init |
| `preAction_after_mdm` | 13.6 ms | MDM policy load; heap jumps 0.2 MB → 31.4 MB here |
| `action_after_setup` | 10.6 ms | setup |
| `init_network_configured` | 3.0 ms | |
| `loadSettingsFromDisk_start → _end` | **0.59 ms** | settings parse itself is ~free |

⇒ **~112 ms of the 204 ms is runtime boot + module import**, i.e. irreducible without a vendor
change. Settings *parsing* is not a cost; the 45 ms before it is.

## 3. TTFB / TTI — pty harness, zero tokens (`/tmp/ccup/tui.py`)

Forks a pty, timestamps the first output byte and the first frame containing `for shortcuts`
(the composer hint = interactive), then SIGINTs. Throwaway config, seeded past onboarding +
trust (`/tmp/ccup/mkcfg.sh`; the trust key must be the **realpath** `/private/tmp/...`).

```
$ for i in 1 2 3 4 5; do CLAUDE_CONFIG_DIR=/tmp/ccup/cfg python3 /tmp/ccup/tui.py 30 'for shortcuts' -- $B; done
TTFB=0.240 TTI=0.308 | 0.211/0.268 | 0.217/0.278 | 0.252/0.314 | 0.299/0.435
```

**Upstream floor: TTFB median 0.240 s, TTI median 0.308 s** (n=5). That is the whole vendor cost
of getting a usable composer on this box.

## 4. HOOK EXECUTION SEMANTICS — MEASURED, and it splits BLOCKING from CONCURRENT

### 4a. Hooks do NOT gate the paint

6 distinct SessionStart hooks, each `sleep 3`, timeout 60:

| config | TTI runs | median |
|---|---|---|
| 0 hooks | .308 .268 .278 .314 .435 | **0.308 s** |
| 1 × sleep 3 | .288 .295 .311 | 0.295 s |
| 3 × sleep 3 | .289 .334 .320 | 0.320 s |
| 6 × sleep 3 | .283 .274 .286 | **0.283 s** |

⇒ **CONCURRENT w.r.t. first paint.** 18 hook-seconds move TTI by less than run-to-run noise.

### 4b. …but they DO gate the first turn, and the group cost is MAX not SUM

Zero-token dispatch harness: a local recorder (`/tmp/ccup/fakeapi.py`, 127.0.0.1:8791) logs the
arrival of the first `POST /v1/messages` and answers 400. `ANTHROPIC_BASE_URL` points at it, so
**no request ever reaches Anthropic and no quota is spent.**

| config | dispatch (s) | median |
|---|---|---|
| control (no hooks, no MCP) | .340 .343 .325 | **0.336** |
| 6 × `sleep 3` SessionStart | 3.352 3.625 3.432 | **3.432** |

6 × 3 s serial would be 18 s. Measured **+3.10 s over control** ⇒ **parallel; the group costs the
slowest hook.** This confirms R4's three-way inference with a direct measurement.

### 4c. Identical hook commands are DEDUPED to one execution

```
3 × byte-identical command  → 1 execution
3 × distinct commands       → 3 executions
```

DOCUMENTED upstream (hooks reference: *"All matching hooks run in parallel, and multiple
identical hook commands are deduplicated automatically"*) — and now MEASURED on 2.1.114.

## 5. MCP — the one upstream knob with real headroom

Fake stdio MCP servers (`/tmp/ccup/slowmcp.py`) that log spawn/init-recv/init-resp and sleep
`MCP_DELAY` inside `initialize`.

### 5a. Batching is real and the default is 3 (stdio) / 20 (remote)

Decoded: `u58(){ let H=parseInt(process.env.MCP_SERVER_CONNECTION_BATCH_SIZE||"",10); return H>0?H:3 }`
and `kT5(){ …MCP_REMOTE_SERVER_CONNECTION_BATCH_SIZE… return H>0?H:20 }`.

6 servers × 3 s delay, connect-span from first spawn to last `init_resp`:

| | span |
|---|---|
| `BATCH=1` | **18.199 s** |
| default (3) | **6.095 s** |
| `BATCH=6` | **3.067 s** |
| `MCP_CONNECTION_NONBLOCKING=1` | 6.110 s (unchanged — it does not touch batching) |

Per-server trace at the default proves the mechanism: slow0/1/2 `init_recv` at +0.03 s,
respond at +3.04 s; slow3/4/5 are not even **spawned** until +3.07 s.

### 5b. MCP blocks the first turn, and the non-blocking cap is ~2 s

| config (6 × 3 s stdio) | dispatch (s) | median |
|---|---|---|
| control, no MCP | .340 .343 .325 | 0.336 |
| default | 6.417 7.050 6.401 | **6.417** |
| `MCP_SERVER_CONNECTION_BATCH_SIZE=6` | 3.421 3.408 3.451 | **3.421** |
| `MCP_CONNECTION_NONBLOCKING=1` | 2.337 2.403 2.384 | **2.384** |

⇒ non-blocking imposes a **~2.0 s pre-wait cap** (2.384 − 0.336), matching issue #76239's
description of the ~2 s window. Two community claims are REFUTED for 2.1.114 by this table:
*"by default in Claude Code 2.x all MCP connections are fully asynchronous"* (they are not — the
default blocks the whole batch) and *"Claude Code caps the MCP connection wait at 5 s, adjustable
with `MCP_CONNECT_TIMEOUT_MS`"* (**`MCP_CONNECT_TIMEOUT_MS` does not appear anywhere in the
binary**; the real per-server knob is `MCP_TIMEOUT`, default **30000 ms**).

Issue #26666's *"blocks the input prompt"* is also refuted for paint — see §4a/§5c: the composer
paints in 0.35 s with six 3-second servers attached. It blocks the *turn*, not the prompt.

### 5c. …but on the operator's REAL servers the knob buys ~nothing

`~/.claude.json` user-scope: `motion` (http), `motion-plus` (http), `ms365` (stdio, `npx`).
`~/.claude-tertiary` adds `mac-messages` (stdio).

| set | default (s) | `MCP_CONNECTION_NONBLOCKING=1` (s) |
|---|---|---|
| real 3 (first touch, cold `npx`) | 2.270 1.938 1.830 → **1.938** | 1.855 1.804 1.971 → **1.855** |
| real 4 (warm) | 0.900 0.844 0.819 → **0.844** | 0.857 0.890 1.079 → **0.890** |

Real MCP costs **+0.5 s (warm) to +1.6 s (cold `npx`)** of blocking dispatch, and the cap never
binds because no real server exceeds ~2 s. **The knob is insurance against a hung server, not a
speed-up here.** MEASURED, n=3 each.

## 6. NEGATIVE RESULTS (suspects killed)

| suspect | test | verdict |
|---|---|---|
| 129–207 KB `.claude.json` parse | swapped the throwaway's 0.4 KB file for a 159 KB clone of `~/.claude-tertiary/.claude.json` (371 projects); dispatch .375/.438/.458 vs .635/.404/.392 | **NOT a cost.** Difference is inside noise. |
| `DISABLE_AUTOUPDATER=1` | dispatch .331 .341 .379 vs control .340 .343 .325 | **no effect** — the binary does no blocking update check anyway (R4 agrees). |
| `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1` | .366 .292 .302 | ~40 ms, inside noise. Privacy knob, not a speed knob. |
| `node --cpu-prof` | binary is Bun-compiled Mach-O | **inapplicable** (§0). |

## 7. `--bare`

`--bare` (2.1.114; the flag R4 called `--safe-mode` on 2.1.220) sets `CLAUDE_CODE_SIMPLE=1` and
skips hooks, LSP, plugin sync, attribution, auto-memory, background prefetches, **keychain reads**
and CLAUDE.md discovery. Dispatch .206 .213 .363 → **median 0.213 s vs control 0.336 s**.
On an already-empty config it saves ~0.12 s; against the operator's real config it would also
skip all 15 hooks. **Not adoptable**: it forbids OAuth entirely (`ANTHROPIC_API_KEY` or
`apiKeyHelper` only), so a Max-subscription session cannot use it.

## 8. DEAD ENDS / instrument traps (recorded so nobody repeats them)

- `CLAUDE_CODE_EXIT_AFTER_FIRST_RENDER=1` does **not** make the process exit. Decoded, it only
  makes `Qq6()` return early, skipping post-render prefetch/bedrock-auth work. Named misleadingly.
- The startup-perf file is flushed on the way OUT, so a harness that `ls`es immediately after
  `timeout` kills the pty finds nothing. Needs a ~2 s settle. Cost 4 wasted runs reading
  "NO REPORT".
- A fresh throwaway config stalls on the **theme picker**, then on **workspace trust** — and the
  trust key must be the resolved realpath (`/private/tmp/...`, not `/tmp/...`).
- `env A=1 "$@" timeout 90 claude …` with flags in `"$@"` makes `env` try to *execute* the flag.
  Produced three silent "NO API HIT" rows before it was caught.
- `strings claude.exe` (no `-a`) reads 298 k lines; `strings -a` reads 317 k. Use `-a`.

## 9. DISCLOSURES

- Nothing under `~/.claude*`, `~/.zshrc`, or any hook was written. Reads only.
- `~/.claude.json` and `~/.claude-tertiary/.claude.json` were **copied** to `/tmp/ccup/` to A/B
  parse cost and to extract the `mcpServers` block; deleted at the end of the session.
- The real `ms365` / `mac-messages` / `motion` / `motion-plus` MCP servers were spawned by the
  probes in a throwaway config. All are read-only; no tool was ever called.
- A local HTTP recorder was started on 127.0.0.1:8791 by me and is killed by me. **No process
  I did not start was signalled.**
- Zero `claude -p` probes hit Anthropic: every `-p` run had `ANTHROPIC_BASE_URL` pointed at the
  local recorder, which answers 400. **0 tokens spent.**

## 10. THE KNOB TABLE

Evidence class: **M** = measured here today · **C** = read out of this binary's own code ·
**D** = official docs · **A** = community anecdote (unverified or refuted).

| Knob | What it does | Effect on THIS box | Class | Safe here? |
|---|---|---|---|---|
| `CLAUDE_CODE_PROFILE_STARTUP=1` | writes a 48-checkpoint startup report to `$CLAUDE_CONFIG_DIR/startup-perf/<sid>.txt` + debug log | diagnostic only; adds ~0 | **M**+**C** | **YES** — read-only diagnostic. The single most useful thing found. Undocumented. |
| `MCP_SERVER_CONNECTION_BATCH_SIZE=<n>` | stdio MCP connect batch, **default 3** | 6 slow servers: dispatch 6.42 s → 3.42 s at n=6. On the real 3–4 servers: no gain (already ≤1 batch of 3 + 1) | **M**+**C** | YES, but **~0 gain here** until >3 stdio servers |
| `MCP_REMOTE_SERVER_CONNECTION_BATCH_SIZE=<n>` | http/sse batch, **default 20** | never binds (4 servers) | **C** | YES, pointless here |
| `MCP_CONNECTION_NONBLOCKING=1` | caps the pre-first-turn MCP wait at ~2.0 s instead of awaiting the whole batch | 6 slow servers: 6.42 → 2.38 s. **Real servers: 0.844 → 0.890 s, i.e. nothing** | **M**+**C** | YES — cheap insurance against a hung/`npx`-cold server; not a speed-up. **A**-claim that this is already the 2.x default is REFUTED for 2.1.114 |
| `MCP_TIMEOUT=<ms>` | per-server connect timeout, **default 30000** | not on the happy path | **C**+**D** | YES; lowering it bounds a hung-server tail |
| `MCP_CONNECT_TIMEOUT_MS` | claimed by a blog to cap the wait at 5 s | **does not exist** — zero occurrences in the binary | **A refuted by M** | n/a |
| `--strict-mcp-config` + `--mcp-config '{"mcpServers":{}}'` | drops all MCP for one launch | dispatch 6.42 → 0.34 s in the synthetic case; ~0.5–1.6 s on the real set | **M**+**D** | YES per-launch; loses all MCP tools |
| `ENABLE_CLAUDEAI_MCP_SERVERS=false` | skips the claude.ai connector-registry fetch | R4 measured that fetch at ~640 ms, **non-blocking/parallel** | **C** (code), prior-art timing | YES; expect ~0 wall-clock gain |
| `--bare` / `CLAUDE_CODE_SIMPLE=1` | skips hooks, LSP, plugin sync, auto-memory, prefetch, keychain, CLAUDE.md | dispatch 0.336 → 0.213 s on an empty config | **M**+**D** | **NO** for daily use — forbids OAuth (API key only), so a Max session cannot launch |
| `--setting-sources project,local` | drops user settings ⇒ drops all 15 user SessionStart hooks + statusLine | hooks cost +3.10 s per max-hook-second in dispatch (§4b) | **M** (mechanism), R4 (ablation) | YES per-launch for probes; **NO** as a default (kills the fleet's own machinery) |
| `CLAUDE_CODE_DISABLE_CLAUDE_MDS=1` | skips CLAUDE.md discovery/load entirely | UNMEASURED here (the 62 KB tertiary CLAUDE.md was not in the throwaway) | **C** | NO — would delete every operating rule from context |
| `CLAUDE_CODE_DISABLE_OFFICIAL_MARKETPLACE_AUTOINSTALL=1` | suppresses the Anthropic-marketplace auto-install (observed firing on the throwaway: *"Anthropic marketplace installed"*) | one-shot on a virgin config; already installed in the real dirs ⇒ ~0 | **C** | YES, but ~0 gain |
| `CLAUDE_CODE_SYNC_PLUGIN_INSTALL=1` | makes plugin install **synchronous** — an inverse lever | would ADD blocking time | **C** | **NO — never set** |
| `CLAUDE_CODE_ENABLE_BACKGROUND_PLUGIN_REFRESH=1` | background plugin refresh | not on the paint path | **C** | neutral |
| `CLAUDE_CODE_SLOW_OPERATION_THRESHOLD_MS=<ms>` | logs any sync FS/JSON op slower than the threshold (default `Infinity`) | diagnostic | **C** | YES — read-only diagnostic |
| `CLAUDE_CODE_PERFETTO_TRACE` | Perfetto span tracing of the session | diagnostic, heavier | **C** | YES for a one-off |
| `DISABLE_AUTOUPDATER=1` | no auto-update check | **0** — no blocking update check exists on this path | **M**+**D** | YES (already effectively set) |
| `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1` | Statsig + Sentry + feedback off | ~40 ms, inside noise | **M**+**D** | YES; it is a privacy knob, not a speed knob |
| `DISABLE_TELEMETRY` / `DISABLE_ERROR_REPORTING` / `DISABLE_BUG_COMMAND` | subsets of the above | ~0 | **D** | YES, ~0 gain |
| `MAX_MCP_OUTPUT_TOKENS`, `MCP_TOOL_TIMEOUT`, `BASH_DEFAULT_TIMEOUT_MS` | runtime, not boot | 0 on startup | **C**+**D** | irrelevant to this axis |
| `CLAUDE_CODE_EXIT_AFTER_FIRST_RENDER=1` | despite the name, only skips post-render prefetch/3P-auth. Does **not** exit | did not exit in 25 s | **M**+**C** | do not rely on it |
| `enabledMcpjsonServers` / `disabledMcpjsonServers` (settings.json) | project `.mcp.json` server gating; a project *disable* beats a local *enable* | reso already uses it to keep `chrome-devtools` (267 MB) out | **D** + project CLAUDE.md | YES — already applied |

## 11. PRIOR-ART VERDICT (re-measured today, 2026-08-16, binary 2.1.114)

| Prior claim | Source | Today |
|---|---|---|
| binary `--version` ≈ 70 ms | R4 §1 (on 2.1.220) | **HOLDS, better** — 55 ms median on 2.1.114 |
| `--help` ≈ 160 ms | R4 §1 | **HOLDS** — 130 ms |
| SessionStart hooks BLOCK the turn | R4 §3 (`sleep 25` → +22.5 s) | **HOLDS, now directly measured** — 6 × sleep 3 → dispatch +3.10 s |
| hook group cost = MAX not SUM | R4 §2a (inferred 3 ways) | **HOLDS, now direct** — 6 distinct hooks all start within 6 ms, all end at +3.02 s |
| MCP connects are "parallel, not blocking… leave alone" | R4 §5 | **PARTLY STALE.** They are parallel *in batches of 3*, and they **do block the first turn** (6.42 s vs 0.34 s synthetic; +0.5–1.6 s real). R4's ablation saw only ~1.6 s and called it noise — which is right in magnitude but wrong in mechanism, and it missed both batch knobs. |
| MCP costs "~1.6 s at most" | R4 §3 | **HOLDS numerically** — real set measured +0.5 s warm / +1.6 s cold-`npx` |
| `DISABLE_AUTOUPDATER=1` is honoured | R4 §6 | **HOLDS** |
| settings/permission-rule parse ≈ 300 ms, "trimmable" | R4 §1 | **PARTLY STALE** — `loadSettingsFromDisk` itself is **0.59 ms**; the ~45 ms is pre-settings init and the 300 ms R4 saw came from *rule application*, not parsing. `.claude.json` size is measurably free. |
| hook group max now ~0.24 s after R6 | R4 §R6 | **NOT RE-MEASURED here** (would require running the operator's live hooks, forbidden by the brief's safety rules). Other agents own it. |
| lead's `claude-latest --version` = 1.3 s | this brief | **STALE as "warm"** — that is the npm-view **cache-miss** path. Warm is 0.21 s (n=11). Cold re-measured at 1.96 s and 3.31 s. |
| the 1.3 s is "before any session begins" | this brief | **HOLDS, and it is 96 % non-upstream**: 0.055 s binary + ~0.16 s wrapper warm, or +1.7–3.2 s on a wrapper cache miss. |

## 12. COMMUNITY / ISSUE TRACKER

| Issue | Claim | Status against 2.1.114 measured here |
|---|---|---|
| [#26666 Lazy MCP init](https://github.com/anthropics/claude-code/issues/26666) | "blocks the input prompt until all MCP servers have spawned… 3-10+ s to every session start"; closed as duplicate | **Half wrong, half right.** The *prompt* is not blocked (TTI 0.35 s with six 3 s servers). The *first turn* is (6.42 s). |
| [#76239 non-blocking pre-wait](https://github.com/anthropics/claude-code/issues/76239) | since CLI **2.1.144** the first request no longer waits for stdio MCP; "effective wait window ~2 s" | **Consistent.** 2.1.114 predates it, and here that ~2 s window is exactly what `MCP_CONNECTION_NONBLOCKING=1` buys (2.38 s vs 6.42 s). Upgrading past 2.1.144 would get it by default. |
| [#57932 SessionStart mcp_tool hooks](https://github.com/anthropics/claude-code/issues/57932) | SessionStart hooks fire ~290 ms *before* MCP connects | consistent with the ordering seen here |
| [#83495 MCP connect has no jitter](https://github.com/anthropics/claude-code/issues/83495) | concurrent sessions stampede MCP connect | **directly relevant** — this box runs ~24 concurrent sessions all connecting the same 3–4 servers |
| [#17974 CLI startup 8+ s](https://github.com/anthropics/claude-code/issues/17974), [#18479 (~5 min on 2.1.9)](https://github.com/anthropics/claude-code/issues/18479), [#28267 (60 s hang 2.1.50-52)](https://github.com/anthropics/claude-code/issues/28267) | recurring startup regressions | **historical**; none reproduce on 2.1.114 here |
| [#9542 Windows SessionStart hang](https://github.com/anthropics/claude-code/issues/9542) | hook completes, CC never notices | Windows only |
| [Hooks reference](https://code.claude.com/docs/en/hooks) | "All matching hooks run in parallel, and multiple identical hook commands are deduplicated automatically"; 60 s default timeout | **CONFIRMED by measurement** (§4a-c) |
| Blog: "all MCP connections are fully async in 2.x"; "`MCP_CONNECT_TIMEOUT_MS` caps at 5 s" | secondary sources | **BOTH REFUTED** for 2.1.114 (§5b) |
