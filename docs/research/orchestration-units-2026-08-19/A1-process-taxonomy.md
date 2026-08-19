# A1 — The live process taxonomy: what OS object each orchestration unit creates

*Measured 2026-08-19 11:43–11:55 UTC on MacBookPro18,2 (M1 Max, hw.ncpu=10, 64 GiB), Claude Code
2.1.220. Every number below carries the command that produced it. Labels: **MEASURED** = I ran it
this session · **INFERRED** = derived from a measurement · **QUOTED** = read out of the binary/doc.*

---

## 1. VERDICT (≤5 lines)

**The operator is right about one orchestration unit and wrong about the other two — and the unit
that *does* take a pane is the one our docs call "Agent Teams", not "subagents" generically.**

1. A **named** agent — `Agent({ name: "A9-prior-art", subagent_type: "deep-research" })` — becomes a
   **separate OS process** (`claude.exe --agent-id …`), **in its own kitty pane with its own tty**,
   **with its own MCP server**, **its own SessionStart hooks**, ~19 threads and **276–295 MB physical
   footprint**. It is a full session in everything but name. HYPOTHESIS **CONFIRMED** for this unit.
2. A **Workflow agent** (`agent()` inside a `Workflow` script — what I am) is **NOT a process, NOT a
   pane, NOT a tty, NOT an MCP client, NOT a session id**. It runs *inside the parent session's node
   process*. Eight of us added **+12 threads** to one process. HYPOTHESIS **REFUTED** for this unit.
3. Workflows "run 50–200 agents fine" because the cap is on **concurrency (8 here)**, not on
   **calls (1000)**. Both numbers read out of the binary — §4.

---

## 2. THE TAXONOMY — every Claude-related process class alive on this box

Census: `ps -Ao pid,ppid,rss,tt,etime,args | grep -i claude | grep -v 'grep -'` → **162 rows**
(MEASURED, 11:43:53Z). Classified by argv shape:

| # | Class (argv shape) | count | own OS proc | own tty/pane | MCP servers | hooks | threads | footprint |
|---|---|---|---|---|---|---|---|---|
| a | `…/node_modules/.bin/claude <flags>` — full session | 13 | yes | yes (s001…s034) | 1 child each | yes (SessionStart + Pre/PostToolUse) | 18 idle / 28–30 busy | **205 / 336 / 448 MB** |
| b | `claude.exe --agent-id <name>@session-<id>` — **named teammate** | 3 (8 earlier) | **yes** | **yes** (s027/s030/s032, kitty panes 391/392/393) | **1 child each** | **yes** (own `mailbox-wake-arm.sh`) | 18–19 | **276 / 281 / 295 MB** |
| b′ | **Workflow agent** (`agentType:"workflow-subagent"`) | 8 concurrent | **NO** | **NO** | **NO** (shares parent's) | Pre/PostToolUse **yes**, SessionStart **no** | +12 total for all 8 | heap-only, not separable |
| c | `claude.exe daemon run --origin…` | **0 right now** | — | — | — | — | — | see §5 (could not measure) |
| d | `claude.exe --bg-pty-host <sock>` | **0 right now** | — | — | — | — | — | see §5 |
| e | `claude.exe --session-id <uuid>` child of a bg-pty-host | **0 right now** | — | — | — | — | — | see §5 |
| f | shell wrappers (`cc-close-attrib`, `mailbox-wake-arm.sh`, `cc-await-ping`, hooks, tool-call `zsh -c`) | 141 | yes (transient) | mostly `??` | no | n/a | 1 | **mean 2.4 MB RSS, 333 MB total** |
| g | per-session MCP server (`node …/ms-365-mcp-server`) | 1 per session **and per named agent** | yes | no | — | no | — | **98–101 MB footprint** (47–79 MB RSS) |
| h | `bin/cc-pane-runner` (OUR script — the pane a named agent lands in) | 4 | yes | yes | no | no | 1 | ~1 MB |

### 2a. Class (b) — what `--agent-id` actually is, resolved end to end

Full argv (`ps -p 8435 -o args= | tr ' ' '\n'`, MEASURED):

```
claude.exe --agent-id A9-prior-art@session-84bde2e9  --agent-name A9-prior-art
           --team-name session-84bde2e9  --agent-color blue
           --parent-session-id 84bde2e9-bd00-4f1e-af05-1763ee55def6
           --agent-type deep-research  --permission-mode auto  --effort high
           --settings /private/var/…/cc-mcp-decision-off-…-wt-pool-8.json  --model opus
```

**Which orchestration unit creates it — resolved by ppid chain + transcript, not by name.**

```
ps -p 7723 -o pid,ppid,tty,args=
 7723  7696 ttys027  /bin/bash …/claude-infrastructure/bin/cc-pane-runner
ps -p 7696 -o args=
 /usr/bin/login -f -l -p chrisren kitten run-shell --shell /bin/zsh -l -i -c 'exec "$CC_PANE_RUNNER"'
   --cwd=/Users/chrisren/Development/.worktrees/wt-pool-8
```

i.e. `claude.exe --agent-id` ← `cc-pane-runner` ← `kitten run-shell` ← kitty (pid 587). The pane is
real; the process is a grandchild of the terminal, **not** of the lead session.

The lead is session `84bde2e9` (config dir `~/.claude-tertiary`, worktree `wt-pool-8`). Its transcript
(`~/.claude-tertiary/projects/-Users-chrisren-Development--worktrees-wt-pool-8/84bde2e9-….jsonl`)
contains **11 `Agent` tool calls, every one carrying `name` + `subagent_type:"deep-research"`**
(MEASURED, python json scan):

```
11:29:41Z Agent A1-client-lifetime      deep-research
11:29:53Z Agent A2-replicache-semantics deep-research
… one every ~12 s …
11:31:49Z Agent A11-redteam-widening    deep-research
```

And **our own pane-spawn ledger closes the loop** — `~/.claude/logs/pane-spawns.jsonl`, MEASURED:

```
{"ts":"2026-08-19T11:31:25Z","surface":"split","backend":"kitty","caller":"it2-kitty",
 "ppid":54762,"ppid_comm":"claude","pane":"391", …}
{"ts":"2026-08-19T11:31:38Z", … "pane":"392"}
{"ts":"2026-08-19T11:31:50Z", … "pane":"393"}
```

`ppid_comm:"claude"` — **the Claude Code session process itself called `it2-kitty split`**, at the
same three timestamps as the A9/A10/A11 `Agent` tool calls. This is Claude Code's own
ITermBackend/TmuxBackend teammate path (`cc-pane-runner`'s header documents it); the pane is a
*requirement of the product's Agent-Teams backend*, not an artefact of our wrapper.

**⇒ CONCLUSION (MEASURED): `Agent({name})` ⇒ 1 OS process + 1 terminal pane + 1 tty + 1 MCP server +
1 SessionStart hook. That is one slot, by any accounting.**

**⇒ NOT MEASURED THIS SESSION:** whether a *bare* `Agent({})` with **no** `name` also produces
`--agent-id`. No unnamed background subagent was alive to sample. See §6 Q1 — this is the single
most load-bearing gap in my axis and A2/A5 should close it with a direct probe.

### 2b. Class (b′) — the Workflow agent, established by self-measurement

I am a Workflow agent. My own ppid chain (MEASURED, `ps -p $$` then walking ppid):

```
23044 zsh -c <my tool call>
99124 …/node_modules/.bin/claude --permission-mode auto --model claude-opus-5 --effort high   ← RSS 707 MB
99091 bash …/.claude/bin/cc-close-attrib …
83977 /bin/zsh -l
  587 /Applications/kitty.app/Contents/MacOS/kitty
```

**There is no `claude.exe --agent-id` anywhere in my ancestry.** My tool calls are children of the
*parent session's* node process. Children of 99124 at one instant (MEASURED):

```
ps -Ao pid,ppid,rss,etime,args | awk '$2==99124'
14499 zsh -c …   43496 zsh -c …   61811 zsh -c …      ← three concurrent agents' Bash calls
99727 mailbox-wake-arm.sh   13664 caffeinate -i -t 300
99719 node …/ms-365-mcp-server                        ← ONE MCP server, shared by all 8 of us
```

My environment (`env | grep -i claude`, MEASURED) settles identity:

```
CLAUDE_CODE_SESSION_ID=f285654f-850c-4ada-96b5-407c5c01ccf0   ← the PARENT's session id
CLAUDE_CODE_CHILD_SESSION=1
CLAUDE_PID=99124                                              ← the PARENT's pid
CLAUDE_CONFIG_DIR=/Users/chrisren/.claude-secondary
ITERM_SESSION_ID=w0t0p0:388   KITTY_WINDOW_ID=388             ← the PARENT's pane
CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1
```

A Workflow agent has **no session id of its own, no pid of its own, no pane of its own**. Its
transcript is a plain file, not a session:
`…/f285654f-…/subagents/workflows/wf_06556f35-03a/agent-<id>.jsonl`, each with
`{"agentType":"workflow-subagent","spawnDepth":1}` (MEASURED, `cat *.meta.json`).

---

## 3. THE NUMBERS TABLE (footprint, not RSS-sum)

Per method rule 2, all memory figures are `/usr/bin/footprint -p <pid>` **physical footprint**, which
excludes the shared `__BUN` (152 MB) and `__TEXT` (32 MB) mappings that make RSS double-count.

| pid | class | RSS (KB) | **phys_footprint** | peak | RSS/footprint | threads | children | fds |
|---|---|---|---|---|---|---|---|---|
| 8435 | named agent A9 | 563 136 | **295 MB** | 311 MB | 1.91× | 19 | 3 | 28 |
| 17602 | named agent A10 | 467 472 | **281 MB** | 299 MB | 1.71× | 18 | 2 | 28 |
| 28505 | named agent A11 | 519 808 | **276 MB** | 344 MB | 1.93× | 18 | 2 | 28 |
| 99124 | full session (mine, running 8 workflow agents) | 756 448 | **336→372 MB** | 406 MB | 2.25× | **30** | 10 | 51 |
| 60323 | full session, 5-day-old, idle | 577 056 | **448 MB** | 508 MB | 1.29× | 28 | 1 | — |
| 55717 | full session, 6 min old | 444 240 | **205 MB** | 229 MB | 2.17× | **18** | 2 | — |
| 9576 | full session, 7 min old | 387 472 | — | — | — | **18** | 2 | — |
| 9453 | MCP server of agent 8435 | 47 280 | **98 MB** | — | 2.12× | — | — | — |
| 99719 | MCP server of session 99124 | 79 536 | **101 MB** | — | 1.30× | — | — | — |

Commands: `/usr/bin/footprint -p <pid> | grep -E 'phys_footprint|TOTAL'` ·
`ps -M -p <pid> | wc -l` (minus header) · `ps -Ao ppid= | awk '$1==P' | wc -l` · `lsof -p <pid> | wc -l`.

**Read this table three ways:**

- **RSS overstates by 1.3–2.3×**, non-uniformly. Summing the 16 claude TUI RSS values gives ~8.4 GB;
  the honest footprint sum is ~4.6 GB. Any capacity model built on RSS-sum is inflated ~1.8×.
- **A named agent is 0.85–1.4× a full session**, plus its own 98 MB MCP server. Marginal cost of one
  named teammate ≈ **375–395 MB** physical. It is not a discount unit.
- **A Workflow agent's marginal cost is heap inside an existing process.** Eight of them took session
  99124 from the 18-thread idle baseline (measured on 55717 and 9576, both fresh sessions) to **30
  threads** — **+12 threads for 8 agents**. Eight *named* agents would be **8 × 18 = 144 threads in 8
  processes with 8 panes and 8 MCP servers**. That is the whole finding in one comparison.

### 3a. Do agent processes inherit the parent's account?

MEASURED, `ps -Ewww -p 8435 | tr ' ' '\n' | grep -iE 'CONFIG_DIR|ITERM|KITTY'`:

```
CLAUDE_CONFIG_DIR=/Users/chrisren/.claude-tertiary     ← the LEAD's config dir (tertiary account)
ITERM_SESSION_ID=w0t0p0:391                            ← its OWN pane, not the lead's
KITTY_WINDOW_ID=391
```

vs my parent session 99124: `CLAUDE_CONFIG_DIR=/Users/chrisren/.claude-secondary`,
`KITTY_WINDOW_ID=388`.

**Named agents inherit the lead's `CLAUDE_CONFIG_DIR` — hence the lead's OAuth/account and quota —
but get their OWN pane identity.** So: **billed to the lead's account, addressable as a separate
pane, counted by any pane-keyed rail as a separate session.** That combination is exactly what makes
them invisible-until-they-aren't to our accounting: our per-account router (`KMAX=8`) sees one
account holding 1 + N agents, while our pane census sees N+1 panes.

### 3b. Do they run hooks?

MEASURED — mapping every live `mailbox-wake-arm.sh` (a SessionStart hook) to its parent:

```
ps -Ao pid,ppid,args= | grep mailbox-wake-arm | while read pid ppid; do ps -p $ppid -o args=; done
hook  9505 <- 8435  : claude.exe --agent-…        ← named agent HAS its own SessionStart hook
hook 18461 <- 17602 : claude.exe --agent-…
hook 29381 <- 28505 : claude.exe --agent-…
hook 99727 <- 99124 : .bin/claude --permission…   ← my parent session: exactly ONE, for the session
```

**Named agent ⇒ full hook lifecycle, including SessionStart.**
**Workflow agents ⇒ no SessionStart hook** (one per *process*, and 8 of us share one process).

But Workflow agents **do** fire PreToolUse/PostToolUse hooks — and they all report the **parent's**
session id:

```
grep -c "f285654f-850c-4ada-96b5-407c5c01ccf0" ~/.claude/logs/bash-commands.log
297
```

297 Bash-hook rows under ONE session id, from 8 different agents. **Every per-session sensor we own
sees eight agents as one session.** That is a capacity-accounting blind spot, and it is the opposite
polarity to the named-agent one.

---

## 4. THE SELF-EXPERIMENT — the Workflow cap, confirmed twice

### 4a. From the run itself (MEASURED)

My workflow's own journal, `…/subagents/workflows/wf_06556f35-03a/journal.jsonl`:

```
8 lines, all {"type":"started","key":"v2:…","agentId":"…"}
```

Agent-file first/last timestamps (`head -1`/`tail -1` of each `agent-*.jsonl`, MEASURED):

| agent | first event | last event |
|---|---|---|
| aa12c94dcf8b82bda | 11:43:46.862Z | 11:47:28Z |
| a7fe16360660e9152 | 11:43:46.937Z | 11:46:44Z |
| a95cde75cdc9e7199 | 11:43:46.973Z | 11:47:05Z |
| af19ece376f99ed67 | 11:43:47.051Z | 11:47:41Z |
| a05016d8159aa38c4 | 11:43:47.485Z | 11:47:44Z |
| af1b440504cccde5d | 11:43:47.908Z | 11:47:29Z |
| afb3d26a0df4f6ff1 | 11:43:48.294Z | 11:47:46Z |
| add28d6fd93130ed1 | 11:43:48.978Z | 11:47:46Z |

**All 8 started inside 2.1 seconds — true concurrency, zero queueing.** The workflow script declared
`VERIFIED` (4 axes) + `PLAIN` (4 axes) = exactly 8 in the first `Promise.all`. **My demand equalled
the cap, so this run alone cannot prove the cap IS 8** — it proves ≥8. Hence 4b.

Concurrency of the *tool calls* those 8 agents issue, sampled every 5 s
(`ps -Ao ppid= | awk '$1==99124' | wc -l`): **max 15 simultaneous children of one session process**.

### 4b. From the binary — the cap expression, QUOTED

`claude.exe` is a 256.9 MB Bun-compiled binary (`bin/claude.exe`; there is **no `cli.js`** in
2.1.220 — a grep for it returns "No such file", which is why a naive bundle grep reads as absence).
Searching the binary bytes with python:

```python
data = open('/Users/chrisren/.claude-220/node_modules/@anthropic-ai/claude-code/bin/claude.exe','rb').read()
# positive control first: data.count(b'workflow-subagent') == 2, b'--agent-id' == 19, b'daemon run' == 17
```

Found, verbatim:

```js
function Xq_(e){ return Math.min(16, Math.max(2, e-2)) }
…
JSd = require("os"), XSd = require("util");
Qq_ = Xq_(JSd.cpus().length),
ej_ = `Workflow agent() call cap reached (${QSd}). This usually means a loop using budget.remaining()
       never terminates because no token budget was set — remaining() returns Infinity when
       budget.total is null. Add a hard iteration cap to the loop, or pass a token budget.`
…
var JSd, XSd, Qq_, Zq_ = 50, QSd = 1000, ej_, ZSd, eTd, KSd = 400,
    tj_ = `You are a subagent spawned by a workflow orchestration script. …`
…
let B = CB(Qq_, K), j = CB(Zq_, re);      // two limiters built from the two constants
```

**⇒ `Qq_ = Math.min(16, Math.max(2, os.cpus().length − 2))`. On hw.ncpu=10 ⇒ min(16, max(2, 8)) = 8.**
The documented `min(16, cpu_cores − 2)` is **CONFIRMED**, with the extra floor `max(2, …)` the doc
omits. `tj_` is the exact system prompt I am running under — a positive control that I found the
right code path, not a lookalike.

**⇒ `QSd = 1000` is a TOTAL `agent()` CALL cap per workflow run, not a concurrency cap.**
**⇒ `Zq_ = 50` is a second, larger limiter (`CB(Zq_, re)`) on a different queue** — I did not identify
which. Flagged for the verifier (§6 Q3).

### 4c. This is the whole "50–200 agents fine" answer

> **A workflow may CALL `agent()` 1000 times; it may only RUN 8 of them at once.**

That is throughput, not concurrency (method rule 6). A 200-agent workflow is 25 sequential batches of
8 — it never puts more than 8 agents' worth of inference load, and **zero extra processes/panes**, on
the box. The operator's observation ("workflows run 50–200 fine") and their hypothesis
("every subagent takes a slot") are both true statements about **different units**.

### 4d. Are workflow agents distinguishable from named agents in `ps`?

**Yes, trivially and asymmetrically: named agents appear in `ps`; workflow agents do not appear at
all.** There is no process to distinguish. A workflow agent's only `ps` footprint is a transient
`zsh -c` tool shell whose ppid is the parent session — indistinguishable from the parent session's
own tool calls. `ps` is structurally blind to Workflow parallelism (MEASURED: `ps | grep -c
'\-\-agent-id'` read **3** throughout my whole 9-minute sampling window while 8 agents were running).

⚠️ **Instrument caveat I hit and corrected:** `ps -Ao args= | grep -c -- '--agent-id'` returns **4**,
not 3 — `grep`'s own argv contains the pattern. Always anchor on `claude.exe --agent-id`.

---

## 5. WHAT I TRIED THAT DID **NOT** WORK / COULD NOT BE MEASURED

1. **Classes (c) daemon, (d) bg-pty-host, (e) backgrounded `--session-id` conversation — ALL GONE.**
   The MACHINE FACTS list them live (pids 59451 etc.). At 11:43:53Z and continuously to 11:55Z:
   `ps -Ao args= | grep -E 'daemon run|bg-pty-host'` → **0 rows**. `/tmp/cc-daemon-501/` exists,
   mtime 04:40 local, and is **empty — no `.pty.sock` under it**. Positive control that my pattern
   *could* have matched: the binary contains `b'daemon run'` ×17 and `b'bg-pty-host'` ×12, and the
   MACHINE FACTS observed them ~1 h earlier. **⇒ These are real classes that had already exited.
   I could not measure their footprint, pty, MCP or hook behaviour. A4/A5 must cover them.**
2. **My first census was a blind instrument and I nearly published its null.** The T0 dump was
   `ps … | grep -i claude | head -100` — `head` truncated it, and a later `grep -c 'claude.exe'` on
   that file returned **0**. Zero `claude.exe` on a box that provably had 16. Method rule 5 in the
   flesh; the fix was to re-run without `head`.
3. **`grep -a -o -E '.{260}…'` on the 256 MB binary fails** — BSD grep: `invalid repetition count(s)`
   — and when it *does* accept a smaller count it pegs a core at ~55 % for minutes (it showed up as
   the top CPU consumer in my own `top -l 2`). Use python `re.finditer` over `open(...,'rb').read()`.
   I killed my own runaway grep (pid 8781) and nothing else.
4. **Marginal in-process cost of ONE workflow agent is not separable.** Session 99124's footprint
   moved 336 → 372 MB over 6 minutes while 8 agents ran, but a 5-day idle session reads 448 MB and a
   6-minute-old one 205 MB — conversation length dominates. The *thread* delta (+12 for 8 agents vs
   an 18-thread baseline measured on two fresh sessions) is the cleanest separable signal I got. A
   paired arrival differential across a workflow start/stop would settle it; I did not have a clean
   start boundary to sample (the workflow was already running when I began).
5. **`ps -Ewww` env inspection worked** for both agent and session pids (macOS permits it for
   own-uid). No `/proc` needed. Environments are truncated by `ps` at some length — I only extracted
   the four variables I needed, so I cannot claim the env is otherwise identical.
6. **Pane accounting does not close.** `kitten @ ls` reports **3 OS windows / 3 tabs / 13 panes**,
   but 16 claude TUI processes hold **19 distinct ttys** (s001 s002 s004 s005 s006 s007 s008 s010
   s014 s019 s024 s026 s027 s029 s030 s031 s032 s033 s034). So ≥3 claude TUIs are on ptys kitty does
   not own (iTerm2? `expect`? — 3 `expect` processes are live). I did not resolve this and it
   matters for any pane-based ceiling model.
7. **Load-average attribution (method rule 3).** `top -l 2 -n 15 -o cpu` second sample, 11:52:07Z:
   `Load Avg: 29.23, 30.45, 31.03`, `1121 processes / 6045 threads / 21 running`,
   `PhysMem: 52G used (9483M wired, 9624M compressor), 10G unused`. The top six CPU consumers were
   **`grep` at 50–56 % each** (research agents' own probes, mine among them); the highest `claude.exe`
   was **9.6 %**, then 5.2 %, 5.2 %. This corroborates `gc-cpu-vs-session-ceiling-2026-08-18`
   (claude.exe ≈ 4.7 % of the numerator) — **the load numerator is agents' tool-call forks, not the
   TUI processes.** Note 9.6 GB in the compressor with 0 swap: memory is closer to the wall than the
   MACHINE FACTS' "~71 % free" suggests, and that reading is ~1 h stale.

---

## 6. OPEN QUESTIONS FOR THE VERIFIER (ranked, each with its probe)

**Q1 (load-bearing).** Does a **bare `Agent({})` with no `name`** — the "background research
subagent" our CLAUDE.md mandates for read-only fan-out — produce a `claude.exe --agent-id` process
and a pane, or does it run in-process like a Workflow agent? **I could not measure it: no unnamed
subagent was alive.** Every `--agent-id` process I sampled came from a call that *did* pass `name`
(11/11 in session 84bde2e9's transcript). If unnamed subagents are also processes, our
research-subagent default of **N=12** is a 12-pane, ~4.5 GB event, and the whole "subagents are
cheap" premise inverts. **Probe:** in a scratch session, `Agent({ prompt: "sleep 90; echo hi" })`
with no `name`, then `ps -Ao args= | grep 'claude.exe --agent-id'` and `kitten @ ls | jq` before and
after. Repeat with `name` set as the positive control.

**Q2.** What are classes (c)/(d)/(e) — `daemon run`, `--bg-pty-host`, and the `--session-id` child of
a bg-pty-host? They existed an hour before I looked and were gone when I did. Are they per-session,
per-box, or per-backgrounded-Bash? **Probe:** run one `Bash(run_in_background:true)` in a scratch
session and watch for a `--bg-pty-host` to appear; `lsof -p` it for its socket and children.

**Q3.** `Zq_ = 50` builds a second limiter `CB(Zq_, re)` alongside the agent limiter `CB(Qq_, K)`.
What queue does it govern — tool calls per agent? phases? `parallel()` closures? If it caps something
per-agent at 50, it is a second, undocumented ceiling. **Probe:** grep the binary for the `re`
callback bound at that site and for `getAgentCount` / `budget.remaining` call sites.

**Q4.** Is the named agent's pane a *hard requirement* of Claude Code's Agent-Teams backend, or only
of the iTerm2/kitty backend? `cc-pane-runner`'s header quotes a `TmuxBackend.sendCommandToPane →
tmux respawn-pane -k` path. If a headless backend exists, named teammates could shed the pane while
keeping the process. **Probe:** grep the binary for `respawn-pane`, `ITermBackend`, `TmuxBackend` and
for any `--agent-id` spawn path that does not go through a terminal split.

**Q5.** Our per-account router uses `KMAX=8` *active per account*. Named agents inherit
`CLAUDE_CONFIG_DIR` from the lead (MEASURED, §3a) — so a lead that spawns 11 named agents puts **12
concurrent conversations on one account's quota** while the router counts one. Is that already
breaking `KMAX`, or does the router count panes? **Probe:** `claude-accounts --readout` during a
live 11-teammate wave, cross-checked against `ps` per config dir.

**Q6.** The pane/tty accounting does not reconcile (§5.6): 13 kitty panes, 19 claude ttys. **Probe:**
`lsof -p <pid> | grep -E 'ttys0'` per claude TUI pid, joined against `kitten @ ls` pane→tty mapping,
and check whether the 3 live `expect` processes own the difference.

---

## 7. WHAT THIS AXIS HANDS THE SYNTHESIS

| unit | OS process | pane/tty | MCP | hooks | marginal footprint | governed by | visible to our pane rails? |
|---|---|---|---|---|---|---|---|
| Named `Agent({name})` teammate | **1** | **1 + 1** | **1 (98 MB)** | full, incl. SessionStart | **~375–395 MB** | no cap found (11 spawned, 0 queued) | **yes** — it IS a pane |
| Workflow `agent()` | 0 | 0 | 0 | tool hooks only, under the **parent's** session id | heap + ~1.5 threads | **`min(16, max(2, ncpu−2))` = 8 concurrent · 1000 total calls** | **no** — invisible to every pane- and session-keyed sensor |
| Full session (`.bin/claude`) | 1 | 1 + 1 | 1 (101 MB) | full | 205–448 MB + 101 MB | our `CC_FIRE_MAX_LOAD_PER_CORE` + `KMAX` | yes |
| bare `Agent({})` subagent | **UNKNOWN — Q1** | UNKNOWN | UNKNOWN | UNKNOWN | UNKNOWN | UNKNOWN | UNKNOWN |
| daemon / bg-pty-host / bg `--session-id` | UNKNOWN — Q2 (absent at measurement time) | | | | | | |

**The one sentence for the operator:** *your ~15-slot ceiling is spent by anything that becomes a
`claude.exe` process with a pane — which named teammates do and Workflow agents do not; a Workflow
buys you 8 concurrent reasoners for the price of one process's heap, and the "200 agents" number you
saw was 25 batches of 8, not 200 at once.*
