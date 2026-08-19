# B1 — The in-process teammate, measured (lever L5)

**Date:** 2026-08-19 · **Box:** MacBookPro18,2 (M1 Max, hw.ncpu=10, 64 GiB) · **Binary:** Claude Code
2.1.220 (`~/.claude-220/node_modules/@anthropic-ai/claude-code/bin/claude.exe`, 256,908,272 bytes)
**Method:** binary read (Bun SEA — the JS source IS embedded, not just a string table) + **5 live probe
sessions**, one of which spawned **four concurrent named teammates** under `--teammate-mode in-process`.
Labels: **MEASURED · INFERRED · QUOTED · REFUTED**. Builds on
[`orchestration-units-2026-08-19.md`](../orchestration-units-2026-08-19.md) (commit `4a3bd3373`) —
nothing settled there is re-derived here.

---

## 1. VERDICT

**`in-process` is a first-class, documented, CLI-overridable setting — not a fallback trick — and it
buys a ~42× memory reduction per teammate for zero quota relief and one silent accounting break.**

- **MEASURED:** 4 named Agent-Teams teammates ran concurrently inside ONE `claude.exe`. **0 new
  processes, 0 new panes, 0 new MCP servers, +1 thread total, +36 MB peak (≈9 MB each)** — against
  the settled **382 MB / 18 threads / 1 pane / 1 MCP server** for a paned teammate.
- **MEASURED:** they are *real* teammates — roster members with `backendType:"in-process"`, own model,
  own prompt; they ran tools, wrote files, and reported through team messaging (`Teammate @t4 finished`).
- 🚨 **MEASURED:** every one of their tool calls is logged under **the LEAD's session id**. Four
  teammates read as one session to every session-keyed sensor we own. The pane-keyed rails
  (`cc-mail`, `assignee-pane-residency.sh`, `cc-where`) do not *fail* — they **filter the teammate out
  and stay green**, which is the worst polarity.
- **This is a BOX lever, not a QUOTA lever** (rule 7). Four in-process teammates are still four
  conversations billed to one account. The 9.4-sustainable-working-units ceiling is untouched.
- **DANGEROUS AS-IS:** `handleSpawn` reaches the in-process branch *before* backend detection and it
  still never calls `takeConcurrencySlot`. Removing the pane removes the only thing that was
  physically rate-limiting an uncapped spawn primitive.

---

## 2. NUMBERS

### 2.1 What `teammateMode` legally is (binary read)

| Fact | Value | Command / anchor |
|---|---|---|
| Legal values (settings schema description) | **`tmux` · `iterm2` · `in-process` · `auto`** | `LC_ALL=C grep -a -o -b 'How spawned teammates execute (tmux, iterm2, in-process, auto)' claude.exe` → **@77748048**, @226849944 |
| CLI override exists | **`--teammate-mode <mode>`** | `LC_ALL=C grep -a -o -b 'How to spawn teammates: "tmux", "iterm2", "in-process", or "auto"' claude.exe` → **@150375152**, @246548508 |
| Product DEFAULT | **`in-process`** | `LC_ALL=C grep -a -o -b 'var nrn="in-process"' claude.exe` → **@232656323**; exported as `DEFAULT_TEAMMATE_MODE:()=>nrn` @232655773 |
| `/config` panel offers only 2 of the 4 | label `Teammate mode`, values `iterm2` \| `in-process` | strings idx 179592-179602 (`strings -a -n 6`); `tmux` is settings/CLI-only |
| Our fleet pins the non-default | `"teammateMode": "iterm2"` in **2 of 2** live config dirs read | `grep -n teammateMode ~/.claude/settings.json ~/.claude-secondary/settings.json` → `:1110`, `:1066` |
| `--teammate-mode` is honoured only when swarms are on | needs `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` **or** `--agent-teams` in argv, **and** gate `tengu_amber_flint` | `function ZD_(){return process.argv.includes("--agent-teams")}` / `function mc(){if(!Z.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS&&!ZD_())return!1;if(!Ke("tengu_amber_flint",!0))return!1;return!0}` — our `settings.json:6` sets the env var to `"1"` |

**So the answer to "setting or trick" is: setting.** `in-process` is an explicit, documented enum
member AND the product default AND reachable per-invocation. The fallback path exists *in addition*.

**The resolver, read verbatim out of the binary** (`isInProcessEnabled`, minified `Lrn`):

```js
function Lrn(e=a1t){
  if(_n())              return log("...true (non-interactive session)"), !0;   // headless ⇒ ALWAYS
  let t=gP_(), r;                                                              // t = teammateMode
  if(t==="in-process")            r=!0;
  else if(t==="tmux"||t==="iterm2") r=!1;
  else {                                                                       // "auto" / unset
    if(e.inProcessFallbackActive) return !0;
    r = !Bdo() && !wpe();                                                      // !insideTmux && !inITerm2
  }
  return r;
}
```

and the dispatcher, which reaches it **before** any backend detection:

```js
function qW_(e,t,r){                       // handleSpawn
  ...
  if(Lrn()) return ivd(e,t);               // ⇒ handleSpawnInProcess         @234645526
  try{ await Prn() }                       // detectAndGetBackend
  catch(o){ if(KMt()!=="auto") throw o;     // explicit iterm2/tmux ⇒ HARD FAIL, no fallback
            ... w0s(); return ivd(e,t) }    // "auto" ⇒ fall back in-process
  ...
}
```

Two consequences that are not obvious from the strings alone:

1. **`_n()` (non-interactive) short-circuits everything.** `ZSi(!r)` with
   `r = kind==="non-interactive" || VlT(argv)`. **Every `claude -p` session on this box already
   spawns in-process teammates**, whatever `teammateMode` says. INFERRED from source; not separately
   probed because §2.2 found a prior blocker (below).
2. **`auto` is not "prefer panes".** With `teammateMode` unset and no tmux/iTerm2 detected, `auto`
   resolves to in-process silently.

### 2.2 The headless run does NOT exercise this path (a trap, and a finding)

| Probe | Setup | Result |
|---|---|---|
| **P1** | `claude -p --teammate-mode in-process` + `Agent({name:"probeA"})` | rc 0, teammate did the work — **but the tool returned the *async subagent* shape** (`Async agent launched … agentId: … output_file: …`), not `{teammate_id, tmux_pane_id}`. `SendMessage` shutdown_request landed in a **phantom inbox** at `teams/default/inboxes/probeA.json` that nothing ever read. |

Root cause, read out of the Agent tool's own `call()`:

```js
let b = mc() ? _.teamContext : void 0;
...
if (b && i && !L && !s && !a) { ...cvd(...)... }   // i = the `name` parameter
```

**`teamContext` is initialised at interactive startup, not in `-p`.** MEASURED: the headless session
`5e90e64a` created **no** `~/.claude-secondary/teams/session-*` directory; every interactive probe did.
So in a headless session **`name:` is silently ignored and the call degrades to an ordinary subagent** —
and `SendMessage` will happily create an inbox for a teammate that does not exist. Any plan that
proposes "dispatch headless sessions that run Agent-Teams waves" must first settle this.

### 2.3 The real thing: interactive, `--teammate-mode in-process`

Driver: `python3 pty.openpty()` + `subprocess` (macOS `script -q` refuses — `tcgetattr/ioctl:
Operation not supported on socket` when the caller's stdin is not a tty), `TERM=xterm-256color`,
`KITTY_*`/`ITERM_SESSION_ID` stripped from the child env, `--permission-mode acceptEdits`.

**P4 — one teammate.** Roster written by the binary
(`~/.claude-secondary/teams/session-973415c9/config.json`, now archived to `teams/_archive/B1probe-*`):

```json
{"agentId":"probeB@session-973415c9","name":"probeB","color":"blue",
 "tmuxPaneId":"in-process","backendType":"in-process","model":"claude-opus-5",
 "agentType":"general-purpose","prompt":"Use the Write tool to create …"}
```
…and the lead itself: `{"name":"team-lead","tmuxPaneId":"leader","backendType":"in-process"}`.
It **worked**: `/tmp/cc-probe-b1/teammateB.txt` contains `INPROC_TEAMMATE_B_OK`, written by the
teammate's own Write tool.

**P5 — four concurrent teammates**, `name="t1".."t4"` in one message. Sampler:
`/usr/bin/footprint -p <lead pid>` (physical footprint — never summed RSS), `ps -M <pid>` for threads,
`pgrep -P <pid>` for children, `ps -Ao comm= | grep -c 'claude-220.*claude'`, kitty `@ ls` window count.

| t (UTC) | event | `phys_footprint` | threads | lead children | `claude.exe` procs | kitty windows |
|---|---|---|---|---|---|---|
| 13:40:16 | lead session up | — | — | — | — | 10 |
| 13:40:19 | **pre-spawn baseline** | **228 MB** | **18** | 3 | 19 | 10 |
| 13:40:24–28 | t1,t2,t3,t4 join (roster `joinedAt`) | — | — | — | — | — |
| 13:40:29 | 4 alive | 250 MB | 16 | 3 | 18 | 10 |
| **13:40:33** | **4 alive, peak** | **262 MB** | 17 | 3 | **18** | **10** |
| 13:40:36–43 | 4 alive, plateau | 252→239 MB | 19 | 3–4 | 18 | 10 |
| 13:42:39 | all four finished | **229 MB** | 18 | 2 | 18 | 10 |

**Derived marginal cost of ONE in-process teammate (paired arrival differential on the SAME pid):**

| Metric | in-process (MEASURED here) | paned `Agent({name})` (settled §2) | ratio |
|---|---|---|---|
| **physical footprint, peak** | **(262−228)/4 = +9.0 MB** | 280 MB proc + 102 MB MCP = **382 MB** | **42×** |
| physical footprint, plateau | (240−228)/4 = **+3.0 MB** | 382 MB | 127× |
| footprint after completion | **fully reclaimed** (229 ≈ 228 MB) | pane + proc persist until torn down | — |
| **threads** | **+1 total for 4 ⇒ +0.25 each** | **18** | **72×** |
| OS processes | **0** | 1 (`claude.exe --agent-id`) | — |
| panes / ttys | **0** (kitty window count flat at 10 across all 5 probes) | 1 + 1 tty | — |
| MCP servers | **0** — `ms-365-mcp-server` count constant at 16 through P4's whole teammate lifetime | 1 (≈102 MB) | — |
| SessionStart hooks | **0** — no new session id ever appeared | full lifecycle incl. SessionStart | — |

### 2.4 Does it still WORK as a teammate?

| Capability | Verdict | Evidence |
|---|---|---|
| receives its brief | **YES** | roster `prompt` field carries the verbatim brief |
| runs tools | **YES** | `teammateB.txt` written; `wc -l …/CLAUDE.md` at 13:40:27/28 in `bash-commands.log` |
| honours per-teammate `model:` | **YES** | roster `"model":"claude-opus-5"` on all 4 |
| reports back / team messaging | **YES** | TUI: `› Message from @t2`, `⏺ Teammate @t4 finished`, `t2 and t3 both returned LINES=773` |
| concurrency | **≥4 simultaneous**, no cap hit | all four `joinedAt` inside 4 s, all alive together |
| `shutdown_request` tears it down | **YES (source), delivery MEASURED** | `[SendMessage] In-process teammate <id> approving shutdown - signaling abort` → `[SendMessage] Aborted controller for in-process teammate` (strings idx 174296-174301). P1 proved SendMessage delivers; the abort itself was not observed live |
| own MCP servers | **NO** | §2.3 |
| own SessionStart hooks | **NO** | §2.3 |
| own transcript | **NO** — see §3 | our own harvester wrote `probeB in-process NO-TRANSCRIPT 0 -` |

### 2.5 Concurrency: still uncapped, and now *more* so

`handleSpawnInProcess` (`ivd`) calls `Fko` → `Mko(… countedTowardSessionSpawnCap:!0 …)`. Inside the
runner: `if(!y && !g) C.incrementTotalAgentSpawns()` — with `g=true` the runner skips it, i.e. the
**lifetime** counter (`CLAUDE_CODE_MAX_SUBAGENTS_PER_SESSION`) is charged once on the teammate branch.
Neither the teammate branch nor `PW_` ever calls `U()` / `takeConcurrencySlot()` — confirming the
settled finding for the third backend, from the third backend's own code. **`CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS`
does not bind a named teammate in any mode.**

---

## 3. WHAT BREAKS IN OUR RAILS

Every row below is code-anchored. "Silent" = the rail returns success/green while the teammate is
invisible; that is strictly worse than a refusal.

| Rail | Keyed on | Behaviour with an in-process teammate | Failure mode |
|---|---|---|---|
| **`scripts/assignee-pane-residency.sh`** | `tmuxPaneId` matching `^[0-9]+$` (line **189**) | `tmuxPaneId:"in-process"` fails the filter ⇒ the member is **dropped from the census**. Header line 15-16 already says only an INTEGER is a kitty window. | 🚨 **SILENT** — reports a healthy, complete residency over a roster it did not fully read |
| **the mailbox (`bin/cc-mail`)** | `~/.claude/mailbox/<recipient-paneUUID>.md` (line **19**), `--pane <uuid\|name>` | No pane UUID exists. Peer mail is **unaddressable**; a `--pane` read returns an empty box. | 🚨 **SILENT** — an empty inbox is indistinguishable from "no mail" |
| **`bin/cc-teardown`** | resolves via `cc-sessions --all --json`, then kills a pid and closes an it2/kitty pane | No registry row, no pid, no pane ⇒ **exit 2 REFUSE (unknown target)** with a `verdict=` token | **LOUD** — and harmless: an in-process teammate dies with its lead, so teardown is never needed |
| **`bin/cc-reaper`** | live panes / sessions; `enumerated ≈ live-panes` self-check | Never enumerates them, so the self-check stays consistent | benign — but it also means a **runaway in-process fan-out is un-reapable except by killing the lead** |
| **`bin/cc-where`** | kitty/it2 window geometry | Cannot answer "where is @t3" — the honest answer is "inside pane N, as its lead" | **SILENT** (the question stops being well-formed) |
| **crash / limit-recover harvest** | per-assignee **transcript** | MEASURED on my own probe: `HARVEST/status.tsv` = `probeB in-process NO-TRANSCRIPT 0 -`; `close-plan.tsv` = `probeB in-process SKIP-UNHARVESTED`. An in-process teammate has no transcript of its own; its work exists only inside the lead's. | 🚨 **SILENT-ish** — it prints a token, but the disposition is *skip*, i.e. **a lead crash loses every in-process teammate's report** |
| **`hooks/agent-teams-enforce.sh` — SPAWN GENERATION CAP** | *"generation is read from an environment stamp this machine wrote when your pane was created"* (line 481-482) | No pane ⇒ no stamp ⇒ the lineage ladder cannot advance | 🚨 **SILENT** — the cap that exists because one fan-out reached **224 spawns / 167 sessions in ~38 min** and ignited kernel watchdog panics becomes **inert for the very unit that has no other cap** |
| **`hooks/agent-teams-enforce.sh` — MACHINE CAPACITY / depth / per-session budget** | hook input + harness `spawnDepth` + session-scoped counters | Still fire (PreToolUse on `Agent` is upstream of the backend choice) | **works** — these three are the only surviving brakes |
| **`bin/cc-custody`** | the **firing cwd** of a `--notify-back` fire | Unaffected — custody is about dispatched sessions, not teammates | no change |
| **the 6-concurrent-teammate rule** | prose only (`skills/agent-teams/SKILL.md:317`, one hit repo-wide) | Unenforced before, unenforced after | no change — but the physical brake that made 6 *feel* like a limit is gone |
| **`k` / `k_work` / router `KMAX`** | per-session census | 4 teammates read as **1** | 🚨 **SILENT** — and this is the *quota-relevant* one: the router will under-count real burn by the teammate multiple |

**The one MEASURED line that carries this section.** `~/.claude/logs/bash-commands.log`:

```
[2026-08-19T13:40:27Z] [865210e0-0f61-4df5-9a90-5b7c7559e4d0] wc -l /Users/chrisren/Development/claude-infrastructure/CLAUDE.md
[2026-08-19T13:40:28Z] [865210e0-0f61-4df5-9a90-5b7c7559e4d0] wc -l < /Users/chrisren/Development/claude-infrastructure/CLAUDE.md
```

Those are t1..t4's tool calls. `865210e0` is **the lead**. Not one row names a teammate.

---

## 4. WHAT I COULD NOT MEASURE, AND WHY

1. **The `iterm2` control was not re-run.** Running it interactively from this environment would have
   split a **live operator pane** (`wpe()` is true here — the repo exports `ITERM_SESSION_ID` even under
   kitty). Rule 4 forbids touching the live fleet, so the paned-teammate numbers are **QUOTED from the
   settled research** (382 MB / 18 threads / own pane / own MCP), not re-derived.
2. **`shutdown_request` abort was not observed live.** P1 proved delivery; P4/P5's leads were SIGKILLed
   by my own bound before a shutdown round-trip. The abort path is read out of the source
   (`abortController` registered in `Fko`, `signal.addEventListener("abort", …)` in `lvd`) — **INFERRED**.
3. **Runnable-thread (load) cost of an in-process teammate mid-turn is UNMEASURED.** `top -l 2` second
   sample was not taken during the 4-teammate window; the thread count (+1 for 4) bounds it but does
   not give R-procs. This is the number that decides whether L5 also relieves the **load gate**, which
   the settled research names as the *first* wall (~4-8 mid-turn) — so it is the single most valuable
   follow-up on this axis.
4. **Ceiling on concurrent in-process teammates is UNKNOWN.** I proved ≥4. Nothing in the code caps it;
   the practical limit is the lead's own context window and event loop, neither of which I stressed.
5. **`--teammate-mode` was never tested against a *managed/policy* settings block.** Strings show a
   `config_teammate_blocked` telemetry key (idx 179607), so an enterprise policy can evidently refuse
   the change. Irrelevant here (no MDM), but it means the flag is not unconditionally available.
6. **Two interactive dialogs blocked automation and had to be driven blind** (folder-trust, then
   bypass-permissions). Any productionised in-process lane launched from a script must pre-satisfy
   both or it hangs forever with no output — my first two probe attempts died exactly there.

**Probe residue, cleaned:** 4 probe team dirs moved to `~/.claude-secondary/teams/_archive/B1probe-*`;
the phantom `teams/default/inboxes/probeA.json` archived; the 2 `cc-await-ping` watchers my probe
sessions armed (`80428`, `96884`) terminated. No live pane, session or process was touched.

---

## 5. THE DECISION THIS AXIS OWNS

**Is "keep Agent Teams, drop the pane" a real option?** — **Yes, and it is a one-word config change or
a one-flag launch.** At what cost:

| | |
|---|---|
| **What it buys** | **~373 MB and ~17.75 threads per teammate**, plus one pane and one tty. On the settled wall order (load < quota ≈26 resident panes < terminal ~30 < memory ~70), it **removes the terminal wall entirely for teammates** and pushes the memory wall out ~42×. A 6-teammate wave falls from **~2.3 GB + 6 panes + 108 threads** to **~54 MB + 0 panes + ~1.5 threads**. |
| **What it does NOT buy** | **Nothing on quota.** Four in-process teammates are four billed conversations on one account (§1, rule 7). The **9.4 sustainable working units** figure is unchanged, and the router's `k_work` will now *under*-count real burn by the teammate multiple — so this lever, adopted naively, makes the quota wall arrive *sooner than the instruments say*. |
| **BURST or SUSTAINED** | **BURST only.** It raises the number of units the box can hold at one instant. It does not raise the 24/7 token rate by a single percent. |
| **Is it dangerous** | **Yes, and specifically because of the pane.** The pane was never a feature — but it was the *de-facto* concurrency brake and the *sole* substrate of the lineage generation stamp. `takeConcurrencySlot` is skipped by all three backends, so the only surviving brakes on a named-teammate fan-out are our own three PreToolUse gates (machine-capacity, depth, per-session budget). The generation cap — added after **224 spawns / 167 sessions / kernel panic** — reads its generation from *"an environment stamp this machine wrote when your pane was created"* and is therefore **structurally inert** in this mode. |

**Recommendation for the ranking table:** L5 is a **high-yield, low-effort BOX lever with one blocking
prerequisite**. It should NOT be adopted as a settings-file flip (`teammateMode: "in-process"` in the
five config dirs) until the generation stamp is re-keyed off something that survives the pane's
absence — the lead's own agent id / spawn lineage in the harness, which the in-process path *does*
carry (`identity.parentSessionId`, `depth: HI(a.agentContext)`), rather than an env var written by
`cc-pane spawn`. Until then, use the **per-invocation `--teammate-mode in-process`** on named,
bounded waves only, and accept that those waves are invisible to `cc-where`, `cc-mail`, residency and
crash-harvest.

**The cheapest concrete next probe** (and it changes the ranking): take a `top -l 2` second sample
during a 6-teammate in-process wave and attribute R-procs to the single lead pid. If in-process
teammates are load-cheap as well as memory-cheap, L5 moves the *first* wall, not the third — and then
it is the highest-yield lever on the board. If they are load-neutral (same API-blocked-then-burst
profile as a paned teammate), L5 only converts a memory/terminal problem into a load problem and its
ranking drops behind whatever lever addresses the load gate.

---

## 6. REPRODUCTION

```bash
# 1. The enum, the default, the flag — all three, from the binary
B=~/.claude-220/node_modules/@anthropic-ai/claude-code/bin/claude.exe
LC_ALL=C grep -a -o -b 'How spawned teammates execute (tmux, iterm2, in-process, auto)' "$B"
LC_ALL=C grep -a -o -b 'How to spawn teammates: "tmux", "iterm2", "in-process", or "auto"' "$B"
LC_ALL=C grep -a -o -b 'var nrn="in-process"' "$B"          # DEFAULT_TEAMMATE_MODE
LC_ALL=C grep -a -o -b 'if(Lrn())return ivd(e,t)' "$B"      # in-process checked BEFORE backend detect

# 2. The live probe (interactive pty; -p will NOT exercise the teammate path — §2.2)
#    scratchpad/pty_run.py + fpsample.sh, prompt3.txt = four Agent({name}) calls in one message
CLAUDE_CONFIG_DIR=~/.claude-secondary CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 \
  claude --teammate-mode in-process --model claude-opus-5 --permission-mode acceptEdits "<prompt>"

# 3. The proof it was a real teammate and not a subagent
python3 -c 'import json;d=json.load(open("<CONFIG_DIR>/teams/session-<sid8>/config.json"));
print([(m["name"],m.get("tmuxPaneId"),m.get("backendType")) for m in d["members"]])'
#   → [('team-lead','leader','in-process'), ('t1','in-process','in-process'), … ]

# 4. The accounting break, in one grep
grep -a '<lead-session-uuid>' ~/.claude/logs/bash-commands.log   # every teammate's tools, under the LEAD
```
