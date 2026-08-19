# A1-VERIFY — adversarial verification of the process taxonomy

*Verifier ran 2026-08-19 12:00–12:10 UTC, same box, same binary (2.1.220), **independently chosen
commands** (no finder command line reused). Labels: **MEASURED** = I ran it · **INFERRED** =
derived · **QUOTED** = read from binary/config. Read-only on the live fleet: nothing killed,
stopped, or torn down. Probes I spawned are itemised in §5.*

---

## 1. VERDICT (≤5 lines)

**The finder's taxonomy survives the attack — every load-bearing claim CONFIRMED, several
strengthened — but its three self-declared gaps are all now closed against it, and one is a
correction that changes the answer.** (a) The workflow cap is **exactly 8**, which I proved by
**queueing** (the finder could only prove ≥8). (b) Its top open question Q1 resolves the *opposite*
way to its fear: an **unnamed `Agent()` creates no pane and no process** (0/7 vs 11/11 control).
(c) Its worked example understates its own headline — the real event was **11 simultaneous named
teammates, not 8**, and the pane is a **`teammateMode:"iterm2"` config choice, not a product
requirement**. Its memory method is sound (I proved `SM=PRV`), but **86% of a session's footprint is
private GPU (`IOAccelerator`), not JS heap** — a term no axis in this wave has.

---

## 2. CLAIM-BY-CLAIM VERDICT

| # | Finder's claim | Verdict |
|---|---|---|
| C1 | `Agent({name})` ⇒ separate OS process + own pane + tty + MCP + SessionStart hook | **CONFIRMED**, with a material refinement — the pane is a *configured backend*, not intrinsic (§3.4) |
| C2 | Workflow `agent()` ⇒ no process, no pane, no tty, no MCP, no session id | **CONFIRMED** (§3.1) |
| C3 | "50–200 fine" = concurrency cap 8, call cap 1000 | **CONFIRMED and UPGRADED** — finder proved ≥8; I prove **==8** by observed queueing (§3.1) |
| C4 | Attribution: the `--agent-id` process comes from the `name`-bearing Agent call | **CONFIRMED** by an instrument the finder did not use — tool-call ts vs `ps -o lstart`, TZ-pinned, 1 s match (§3.3) |
| C5 | `Xq_=min(16,max(2,ncpu−2))`=8 · `Zq_=50` · `QSd=1000` | **CONFIRMED behaviourally** (§3.1). I did not re-derive the constants from bytes; the live queueing is the stronger evidence and agrees. |
| C6 | Footprint, not RSS-sum; RSS overstates 1.3–2.3× | **CONFIRMED**, and the *method* independently validated — `SM=PRV` proves the footprint is private, so it really is marginal (§3.5) |
| C7 | "8 named agents = 144 threads / 8 procs / 8 panes / 8 MCP servers" | **PARTIALLY REFUTED** — presented inside a MEASURED block but it is arithmetic (INFERRED), the measured thread count is **18** not 18–19, and the real event was **11**, not 8 (§3.2) |
| C8 | Named agents: "no cap found (11 spawned, 0 queued)" | **CONFIRMED and STRENGTHENED** — max simultaneous **11**, measured from the agents' own transcripts, not from one `ps` sample (§3.2) |
| C9 | 297 bash-hook rows from 8 agents under ONE session id | **NOT RE-DERIVED** — consistent with C2, but I did not verify it; do not treat as verified. |
| C10 | Named agents inherit the lead's `CLAUDE_CONFIG_DIR` (account) | **CONFIRMED** by an independent route — all 11 agent transcripts are written into `~/.claude-tertiary/projects/…`, the lead's store (§3.2) |
| C11 | daemon / `--bg-pty-host` / bg `--session-id` "ALL GONE — could not measure" | **REFUTED as a standing fact** — 1 daemon + 4 pty-hosts are live *now*, and they are a **leak from sibling agent A3's probe, which reported tearing them down** (§3.6) |
| C12 | "Pane accounting does not close: 13 kitty panes vs 19 claude ttys" | **RESOLVED, not a mystery** — iTerm2 **and** kitty **and** 2 tmux servers are all running at once (§3.7) |
| C13 | Instrument caveat: `grep -c -- '--agent-id'` reads 4 not 3 (grep's own argv) | **PARTIALLY REFUTED — understated.** Real inflation is **+2**, and the second source is the *tool-call shell's own argv*. A token that exists nowhere reads **3** (§3.8) |
| C14 | Q1 (load-bearing): does a bare `Agent({})` with no name make a process + pane? UNKNOWN | **ANSWERED — NO** (§3.9). The finder's feared inversion of "subagents are cheap" does **not** happen. |

---

## 3. THE NUMBERS, WITH THE COMMAND THAT PRODUCED EACH

### 3.1 The workflow cap is exactly 8 — proved by QUEUEING (the finder could not)

The finder's own run demanded exactly 8, so it could only bound the cap below. **This wave is 13
agents against a cap of 8**, so the queue is observable. Reading my *own* workflow's journal:

```bash
SD=~/.claude-secondary/projects/-Users-chrisren-Development-claude-infrastructure/\
f285654f-850c-4ada-96b5-407c5c01ccf0/subagents/workflows/wf_06556f35-03a
# first/last event timestamp per agent-*.jsonl, then a sweep-line max-overlap
```

| agent | first event | last event |
|---|---|---|
| aa12c94dcf8b | 11:43:46.862Z | 12:02:28.565Z |
| a7fe16360660 | 11:43:46.937Z | 12:07:40.595Z |
| a95cde75cdc9 | 11:43:46.973Z | **11:58:47.543Z** |
| af19ece376f9 | 11:43:47.051Z | 12:02:48.422Z |
| a05016d8159a | 11:43:47.485Z | **12:00:26.244Z**  ← *the finder* |
| af1b440504cc | 11:43:47.908Z | 12:08:36.078Z |
| afb3d26a0df4 | 11:43:48.294Z | **11:59:14.024Z** |
| add28d6fd931 | 11:43:48.978Z | 12:02:14.122Z |
| a3a0dad7637f | **11:58:53.574Z** ← +6.0 s after a95cde ended | 12:09:33.846Z |
| a268cd0f449d | **11:59:19.769Z** ← +5.7 s after afb3d26 ended | 12:09:26.905Z |
| a419c12079d7 | **12:00:30.526Z** ← +4.3 s after a05016d ended | 12:09:35.465Z |
| a8eb3dde381b | 12:02:18.273Z | 12:09:22.217Z |

```
MAX SIMULTANEOUS = 8   at 2026-08-19T11:43:48.978Z     (sweep line over 12 intervals)
```

**MEASURED.** Eight start inside 2.1 s; agents 9–12 each start **4–6 s after a predecessor
finishes**. That is a semaphore releasing a slot, not a coincidence. `min(16, max(2, 10−2)) = 8`
is therefore confirmed *behaviourally* on a run whose demand exceeded it — and no agent was dropped,
so the excess **queues**. I am `a419c12079d7`: I took the finder's slot 4.3 s after it exited.

### 3.2 The named-teammate path has NO concurrency governor — and the real number is 11, not 8

The finder sampled `ps` and saw 3 (MACHINE FACTS saw 8 an hour earlier). Neither is max-simultaneous.
I computed it from the agents' own transcripts, which is not sampling-limited:

```bash
D=~/.claude-tertiary/projects/-Users-chrisren-Development--worktrees-wt-pool-8
# per *.jsonl (excluding the lead 84bde2e9): first/last timestamp + agentName/teamName, sweep line
```

```
agent transcripts found: 11   (A1-client-lifetime … A11-redteam-widening, all team=session-84bde2e9)
MAX SIMULTANEOUS named teammates: 11   at 2026-08-19T11:31:53.738Z
```

**MEASURED.** All eleven were alive at once — 11 OS processes, 11 panes, 11 MCP servers, on a box
whose ceiling is ~15 *sessions*. The finder's "8 named agents = 144 threads / 8 panes" projection is
**INFERRED arithmetic understating the observed event by 37%**. Corrected, measured basis:

```bash
ps -M -p 17602 | tail -n +2 | wc -l     # 18   (named agent A10, live)
ps -M -p 55717 | tail -n +2 | wc -l     # 18   (fresh session, 11:38)
ps -M -p  9576 | tail -n +2 | wc -l     # 19   (session)
ps -M -p 99124 | tail -n +2 | wc -l     # 30   (my parent, hosting 8 workflow agents)
```

⇒ a named agent is **18 threads**, not 18–19 (19 was a *session*). Eleven named agents =
**198 threads / 11 processes / 11 panes / 11 MCP servers ≈ 4.2 GB** (§3.5 for the per-unit figure).

Account inheritance (C10) confirmed by a route the finder did not use: **all 11 agent transcripts
are written into the LEAD's account store**, `~/.claude-tertiary/projects/…`, carrying
`teamName: session-84bde2e9`. Eleven extra conversations billed to one account that our router
counts as one.

### 3.3 Attribution, done the way the brief asked: tool-call timestamp vs process `lstart`

I re-read the lead transcript myself (independent parser) and pinned TZ on both sides.

```bash
TZ=UTC ps -axww -o pid=,lstart= | grep '^ *17602'
#   17602 Wed 19 Aug 11:31:38 2026
# lead transcript, tool_use blocks named Agent/Task:
#   2026-08-19T11:31:37.266Z  Agent  name=A10-hostile-reviewer  type=deep-research
```

**1-second match.** And the shape is exact across the whole set:

```
total Agent/Task tool_use in lead transcript: 11 — every one carries `name` + subagent_type=deep-research
11:29:41.263Z A1 · 11:29:53.972Z A2 · 11:30:05.972Z A3 · 11:30:18.736Z A4 · 11:30:33.653Z A5
11:30:45.619Z A6 · 11:30:59.097Z A7 · 11:31:11.912Z A8 · 11:31:24.560Z A9 · 11:31:37.266Z A10
11:31:49.548Z A11
```

Against our pane ledger (`~/.claude/logs/pane-spawns.jsonl`, filtered `ppid_comm=="claude"`, today):

```
11:29:42Z pane=382 · 11:29:55Z 383 · 11:30:07Z 384 · 11:30:19Z 385 · 11:30:34Z 386 · 11:30:46Z 387
11:31:00Z 389 · 11:31:12Z 390 · 11:31:25Z 391 · 11:31:38Z 392 · 11:31:50Z 393        (11 rows)
```

Eleven calls → eleven panes → eleven processes, each within 1–2 s. **MEASURED. Attribution is not
inferred from the name.** (Pane 388 is skipped: that is my own parent session's pane.)

### 3.4 REFINEMENT the finder missed: the pane is a CONFIG CHOICE, not a product requirement

The finder wrote that the pane is "a *requirement of the product's Agent-Teams backend*". That is
too strong, and the counter-evidence is in the operator's own settings:

```bash
python3 -c "import json;print(json.load(open('$f')).get('teammateMode','<absent>'))"
#  ~/.claude/settings.json            -> iterm2
#  ~/.claude-secondary/settings.json  -> iterm2
#  ~/.claude-tertiary/settings.json   -> iterm2
#  ~/.claude-quaternary/settings.json -> iterm2
```

And from the binary (**QUOTED**, `re.finditer` over `bin/claude.exe`):

```js
function w0s(e=a1t){ w("[BackendRegistry] Marking in-process fallback as active"), e.inProcessFallbackActive=!0 }
function Lrn(e=a1t){ if(_n()) return w("[BackendRegistry] isInProcessEnabled: true (non-interactive session)"), !0; … }
// enum values present verbatim:  "in-process" | "tmux" | "iterm2"
// "[BackendRegistry] isInProcessEnabled: true (fallback after pane backend unavailable)"
// "teammateMode is set to \"iterm2\" but this session is not running inside iTerm2. …"
```

Counts (positive-controlled — `cc-pane-runner` is OUR file and correctly reads **0**):

| string | hits in `claude.exe` |
|---|---|
| `cc-pane-runner` | **0** ← control: our wrapper is unknown to the binary |
| `teammateMode` | 35 |
| `ITermBackend` | 40 |
| `TmuxBackend` | 32 |
| `in-process` | 115 |
| `--agent-id` | 19 |
| `osascript` | 33 |
| `iTerm` | 200 |

**⇒ The finder is right against A8** (A8 hypothesised "the pane may be our integration"): CC's own
`ITermBackend` drives the split via the `it2` CLI, and `bin/cc-pane-runner`'s header documents CC
typing the launch command into the pane — our shim only redirects *which terminal*, never *whether a
pane*. **But there is a real `in-process` teammate backend**, auto-selected for non-interactive
sessions and as a fallback. So the correct statement is: *the pane is a property of the configured
`teammateMode`, which is `iterm2` on all four accounts here* — which makes it a **removable** cost,
and that is a live lever for the synthesis that the finder's wording forecloses.

### 3.5 Memory: the finder's method survives, but the composition is not what anyone thinks

**Attack: did it sum RSS?** No — it used `footprint -p`, and I verified the instrument is right for
the job rather than taking its word.

```bash
/usr/bin/footprint -p 17602 | tail -25      # named agent A10
#   0 B   152 MB   0 B   1   __BUN
#   0 B    32 MB   0 B 305   __TEXT
#  280 MB 186 MB  37 MB 2198 TOTAL          phys_footprint: 280 MB
```

`__BUN` (152 MB) + `__TEXT` (32 MB) sit in the **Clean** column, are file-backed, and are excluded
from `phys_footprint` — so the 184 MB of shared binary is counted **once system-wide**, not 17
times. The finder's method-rule-2 compliance is real.

**Is the remaining 280 MB actually marginal (private), or shared with the parent?** The brief asked
this specifically. Decisive test — region sharing mode and addresses:

```bash
/usr/bin/vmmap 17602 | grep -i IOAccelerator
#  IOAccelerator  3fa2fc00000-3fa37c00000 [128.0M 42.5M 38.4M 20.1M] rw-/rwx SM=PRV
/usr/bin/vmmap 55717 | grep -i IOAccelerator
#  IOAccelerator  221bc400000-221c4400000 [128.0M 22.8M 19.5M 15.7M] rw-/rwx SM=PRV
/usr/bin/vmmap 17602 | grep '^shared memory'
#  shared memory  80K  64K  64K … (64 KB total)
```

**`SM=PRV`, at completely different base addresses per process, with only 64 KB of shared dirty
memory in the whole process.** These are separately `exec`'d processes, not forks — there is no COW
heap to share. **⇒ the footprint IS the marginal cost. Attack #1 fails to refute.**

**But the composition is new and load-bearing:**

```bash
/usr/bin/footprint -p 17602 | head -14
#   Dirty   Clean  Reclaimable  Regions  Category
#  241 MB     0 B     36 MB       12     IOAccelerator     ← 86% of a 280 MB footprint
#   15 MB     0 B     16 KB        3     JS JIT generated code
# 7088 KB     0 B     16 KB       32     JS VM Gigacage
/usr/bin/footprint -p 55717 | head -14
#  194 MB     0 B     27 MB       12     IOAccelerator     ← 87% of a 223 MB footprint
```

| pid | class | threads | **phys_footprint** | of which IOAccelerator | JS heap-ish |
|---|---|---|---|---|---|
| 17602 | named teammate A10 (live) | 18 | **280 MB** | 241 MB (86%) | ~34 MB |
| 55717 | session, 25 min old | 18 | **223 MB** | 194 MB (87%) | ~29 MB |
| 9576 | session, 26 min old | 19 | **224 MB** | — | — |
| 99124 | session hosting 8 workflow agents | **30** | **360 MB** | — | — |
| 60323 | session, 5 days old | 28 | **449 MB** | — | — |
| 82213 | `daemon run` (no terminal) | — | **118 MB** | 102 MB (86%) | ~9 MB |
| 16331 | `bg-pty-host` (no terminal) | — | **86 MB** | 78 MB (91%) | ~5 MB |
| 18451 | named agent's own MCP server | — | **102 MB** | — | — |
| 56471 / 99719 | sessions' MCP servers | — | **103 / 101 MB** | — | — |

`ps -M -p <pid> | tail -n +2 | wc -l` for threads; `/usr/bin/footprint -p <pid>` for the rest.

**Marginal cost of one named teammate = 280 MB (process) + 102 MB (its own MCP server) ≈ 382 MB.**
That lands inside the finder's 375–395 MB band — **CONFIRMED by a second instrument path**. Eleven
of them ≈ **4.2 GB**.

**The correction for the synthesis:** ~86% of every claude.exe's footprint is private
`IOAccelerator` (GPU) allocation in 128 MB granules, and it grows with the process's role
(78 MB pty-host → 102 MB daemon → 194 MB session → 241 MB busy teammate). The JS heap is ~30 MB.
Any capacity model in this repo that reasons about "conversation length" as the memory driver is
modelling the 13% term. I did **not** determine *why* a TUI binary allocates GPU memory — see §6 Q2.

### 3.6 The finder's "could not measure" class is live NOW — and it is a sibling agent's leak

```bash
ps -axww -o pid=,ppid=,rss=,args= > /tmp/v_f.txt      # file first — see §3.8
grep 'claude.exe daemon run' /tmp/v_f.txt
# 82213  1  326080  …/claude.exe daemon run --origin transient --spawned-by
#   {"label":"claude --bg","cwd":"/private/tmp/claude-501/…/f285654f-…/scratchpad/a3v","pid":82151}
grep 'bg-pty-host /tmp/cc-daemon' /tmp/v_f.txt | wc -l    # 4  (+1 self-match, see §3.8)
ls /tmp/cc-daemon-501/0503d474/spare/                     # 87840c5d · 9c1e05e9 · ceb1e128 · d24be9c4
```

**MEASURED.** One daemon + **four** `bg-pty-host` spares, ppid-chained to `…/scratchpad/a3v` — the
scratchpad of sibling axis **A3**, which reported *"PROBE HYGIENE: … Torn down via claude stop + rm
job dir … Verified: … daemon status = not running"*. It is running. Two consequences:

- The finder's C11 is a **timing artefact, not absence** — but its instinct (§5.1) was right and its
  refusal to publish a footprint was correct.
- **A3's claim "Spare pool = exactly 1 (`if(kXe||uRr||_Xo)return`)" is contradicted by four live
  spares under one daemon.** Not my axis; flagged for synthesis. Cost of the leak, measured:
  118 + 4×86 ≈ **462 MB** sitting on the box right now.

I did **not** kill it (method rule 4). It is the operator's / A3's to reap.

### 3.7 The pane-accounting "mystery" (finder §5.6 / Q6) — resolved, not open

```bash
ps -axo pid=,comm= | grep -Ei 'iTerm|kitty|tmux'
#   587 /Applications/kitty.app/Contents/MacOS/kitty
#  6805 /Applications/iTerm.app/Contents/MacOS/iTerm2
#  7891 …/iTerm2/iTermServer-3.6.11
#  8626 tmux      24649 tmux
kitten @ ls | …                         # os_windows 3  tabs 3  panes 11
grep -cE '\.bin/claude$|bin/claude\.exe$' /tmp/v_comm.txt      # 18 claude processes
```

**MEASURED.** kitty owns 11 panes; **iTerm2 is running simultaneously** (with its server), plus two
tmux servers. The books were never going to close against kitty alone. Any pane-based ceiling model
in this repo must enumerate **all three** terminal hosts.

### 3.8 INSTRUMENT REFUTATION — every `ps | grep -c` count in this wave is inflated

The finder noticed grep's own argv and put the inflation at +1. It is **+2**, and the second source
is worse because it is invisible:

```bash
for tok in ZZZ-does-not-exist QQQ-also-absent; do
  piped=$(ps -axww -o args= | grep -c "$tok")
  ps -axww -o args= > /tmp/v_ctl.txt; filed=$(grep -c "$tok" /tmp/v_ctl.txt)
  echo "$tok piped=$piped file=$filed"
done
# ZZZ-does-not-exist  piped=3  file=1
# QQQ-also-absent     piped=3  file=1
```

**A token that exists nowhere on the machine reads 3.** Mechanism: a Bash tool call runs the *whole
script* as one `zsh -c '<script>'`, so **every pattern you type is in the tool shell's own argv** —
the repo's own `pgrep-f-matches-agent-briefs` lesson, one level closer to home. The grep and a
subshell supply the rest. Consequence on the real pattern:

```
--agent-id :  piped=6   file=5   anchored 'claude\.exe --agent-id' in file = 1
```

**⇒ Redirect `ps` to a file, then grep the file, and anchor on `claude.exe --agent-id`.** Treat every
naked `ps | grep -c` figure in this wave — including the finder's "3 throughout my sampling window" —
as unverified until re-derived. (My own 90-sample sampler is unaffected: it runs from a *file*,
`/tmp/v_sampler.sh`, so no pattern appears in its argv, and its escaped pattern `claude\.exe` does not
match the grep's own rendered argv. Its constant `agentid=1` is the genuinely-live A10/17602, verified
alive at 12:09 by `ps -p 17602`.)

### 3.9 Q1 — ANSWERED. A bare `Agent({})` with no name takes NO pane and NO process

The finder called this "the single most load-bearing gap" and feared our N=12 research default was a
12-pane, 4.5 GB event. It is not. Two independent measurements:

**(a) Historical, zero-cost, with a perfect control.** Every Agent/Task `tool_use` today across all
four stores, split by whether `input.name` is present, cross-joined against the pane ledger in a
±1-minute window:

```
TODAY: named Agent calls = 11 · unnamed Agent calls = 7 · pane splits (ppid_comm=claude) = 11

unnamed 2026-08-19T00:50:25.316Z sess=1a5c250b type=Explore          panesplits_in_window=0
unnamed 2026-08-19T00:54:19.288Z sess=21834177 type=general-purpose  panesplits_in_window=0
unnamed 2026-08-19T00:54:34.821Z sess=21834177 type=general-purpose  panesplits_in_window=0
unnamed 2026-08-19T00:54:53.617Z sess=21834177 type=general-purpose  panesplits_in_window=0
unnamed 2026-08-19T01:29:03.598Z sess=22442b3e type=Explore          panesplits_in_window=0
unnamed 2026-08-19T08:37:01.849Z sess=a172aeb9 type=Explore          panesplits_in_window=0
unnamed 2026-08-19T12:05:08.949Z sess=ed96f7ef type=general-purpose  panesplits_in_window=0
  -> unnamed calls WITH a coincident pane split: 0 ; WITHOUT: 7
CONTROL (same test, named calls):
  -> named calls WITH a coincident pane split: 11 ; WITHOUT: 0
```

**Perfect discrimination, 11/11 vs 0/7.** Six of the seven unnamed calls were in ordinary
*interactive* sessions, so this is not an artefact of headless mode. Unnamed calls carry
`['description','prompt','run_in_background','subagent_type']` — no `name`, no `team-name`.

**(b) A live probe.** I ran exactly one bounded headless session instructed to make one unnamed
Agent call, while a 10-second sampler watched for `claude.exe --agent-id`:

```bash
timeout 200 …/.bin/claude -p 'Call the Agent tool EXACTLY ONCE … Do NOT pass a name parameter.' \
    --allowedTools Agent Task Bash --output-format json      # rc=0, session ed96f7ef, num_turns 2
```

The transcript confirms the call landed (`ed96f7ef`, 12:05:08.949Z, `subagent_type=general-purpose`,
no `name`). The `--agent-id` count never moved off 1 (= the pre-existing A10) across the whole
12:04:48 → 12:07:48 window.

⚠️ **Honest limit on (b) alone:** headless is non-interactive, and the binary contains
`isInProcessEnabled: true (non-interactive session)` (§3.4) — so a headless run would go in-process
*regardless* of naming. **(b) is confounded; (a) is not**, and (a) carries the control. The verdict
rests on (a).

**⇒ Our research-subagent default of N=12 is safe. The pane cost belongs to the `name` parameter —
i.e. to Agent Teams — not to subagents.**

### 3.10 Attack #4 — the selection blind spot is far worse than a `p_comm` mismatch

The brief asked what a naive `grep claude` misses. I built the claude-attributable set by **ancestry**
(walk every process's ppid chain to a claude-comm root) and diffed it against the naive set:

```bash
ps -axww -o pid=,ppid=,rss=,tt=,comm= > /tmp/v_comm.txt
ps -axww -o pid=,args=                > /tmp/v_args.txt
# python: descendants of every claude-comm root, minus {argv~claude ∪ comm~claude}
```

```
total processes on box:                              1150
claude-attributable BY ANCESTRY:                      128
caught by naive `ps|grep -i claude` (comm OR argv):    61
MISSED by naive grep:                                  67   = 52%
missed, by p_comm: node×14  sleep×14  bash×9  (bash)×7  caffeinate×5  head×3  (git)×3
                   (sleep)×2  zsh×2  grep×2  timeout×1  ms-365-mcp-server×1  uv×1  python×1  (awk)×1
missed RSS total: 1289 MB   (RSS = upper bound, double-counts — do not treat as memory)
```

**MEASURED.** Findings the finder did not have:

- **Every per-session MCP server is missed.** `node /Users/chrisren/Library/Application Support/fnm/aliases/default/bin/ms-365-mcp-server` contains no `claude` in argv *or* comm. There are **13 of them** — one per session **and one per named teammate** (18451 ⟵ 17602 confirms the teammate gets its own) — at **101–103 MB footprint each ≈ 1.3 GB**. A census keyed on the string "claude" is blind to the second-largest Claude-caused memory class on the box.
- **7 processes have a parenthesised `p_comm` (`(bash)`, `(git)`, `(sleep)`, `(awk)`)** — exiting/zombie, argv unreadable. Invisible to *any* argv-based instrument, in both directions.
- The finder's own §5.7 top-CPU reading (`grep` at 50–56%) sits in this missed set — the load numerator is dominated by processes a claude-name census cannot see, which is the same conclusion `gc-cpu-vs-session-ceiling-2026-08-18` reached from the other side.

**Rule for the synthesis: attribute by ancestry, never by name.**

---

## 4. WHERE I AGREE THE FINDER WAS SIMPLY RIGHT

Stated plainly so the confirmations are not lost in the corrections: the two-execution-model split is
real and correctly assigned; `Agent({name})` really is a full session in everything but the label;
Workflow `agent()` really is heap inside the parent; "50–200" really is throughput and not
concurrency; and the memory instrument choice was correct and I could not break it. The finder also
flagged its own three gaps accurately enough that all three were closable — which is why this
verification could go as far as it did.

---

## 5. WHAT I TRIED THAT DID **NOT** WORK

1. **The paired arrival differential FAILED on this box — I am not reporting a number from it.**
   I sampled `vm_stat` every 4 s across a headless probe's arrival (3 PRE / 40 MID / 3 POST). Pages
   `active+wired+compressor` went 2,447,554 (PRE) → 2,552,638 (peak) → 2,550,185 (POST). The Δ **did
   not return to baseline after the probe exited**, so the drift of 16 sibling sessions is larger than
   the signal. Quoting "+430 MB" from that would have been fabrication. This independently reproduces
   A8's negative result. **The per-process `footprint` + `SM=PRV` proof (§3.5) is what the marginal
   claim rests on instead.**
2. **The live Q1 probe is confounded** and I say so in §3.9 rather than banking it: headless forces
   `isInProcessEnabled: true (non-interactive session)`. Answering Q1 properly *in an interactive
   session* needs an interactive session, which I cannot create (`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1`
   — I am depth 1 and can spawn nothing). The historical control in §3.9(a) is what carries it.
3. **Small-n on the unnamed population.** Only 7 unnamed Agent calls exist today. The pane ledger goes
   back to `2026-08-07T19:50:25Z` (2,521 rows), so a multi-day version of §3.9(a) is available and
   would strengthen 0/7 considerably. I ran the one-day version; a longer one is §6 Q1.
4. **I did not re-derive the binary constants** (`Xq_`, `Zq_`, `QSd`) from bytes. The live queueing in
   §3.1 tests the same proposition against the running system and is strictly better evidence for the
   operator's question, so I spent the budget there. If synthesis needs the constants themselves, they
   remain single-sourced from A1/A4 — mark accordingly.
5. **I did not verify C9** (297 bash-hook rows under one session id). Consistent with C2 but unchecked.

**Probes I spawned, and their disposition:** one background sampler (`/tmp/v_sampler.sh`, 90 × 10 s,
pure `ps`/`sysctl` reads — expired on its own); one bounded headless probe wrapper
(`/tmp/v_probe.sh`) which ran **exactly one** `timeout 200 claude -p …` (session `ed96f7ef`, rc 0,
exited; cost $1.60 — noted because it is not free); `vmmap`/`footprint`/`ps` reads throughout.
**I killed nothing, stopped nothing, and tore down no fleet process** — including A3's leaked daemon,
which I deliberately left running and reported instead.

---

## 6. OPEN QUESTIONS FOR THE NEXT VERIFIER / SYNTHESIS

**Q1 (cheap, strengthens the headline).** Re-run §3.9(a) over the **full pane-ledger window**
(2026-08-07 → now, 2,521 rows) instead of one day. If unnamed-vs-pane stays 0/N over hundreds of
calls with the named control at N/N, the "the `name` parameter is what costs a pane" claim becomes
unassailable. Probe: the same joiner, with the date filter removed.

**Q2 (largest unexplained term in the whole wave).** **Why does a terminal-UI binary hold 78–241 MB
of private `IOAccelerator`?** It is 86–91% of every claude.exe footprint, it is present even in
`bg-pty-host` processes that have no terminal at all, and it scales with role. If it is a per-process
Metal heap that could be disabled or shrunk, it is the single biggest memory lever on the box —
bigger than any orchestration-unit choice. Probe: `sudo fs_usage`/`ktrace` on IOAccelerator opens
during a cold `claude` start; or diff footprint composition with `CLAUDE_CODE_*` rendering/telemetry
flags off; or check whether an older install (`~/.claude-156`) shows the same composition.

**Q3 (changes the recommendation).** Does `teammateMode: "in-process"` (or `"tmux"`) actually work
for named teammates on 2.1.220, and what does a teammate cost under it? All four accounts are pinned
to `iterm2` (§3.4), and the binary carries a real in-process backend plus a fallback path. If
in-process teammates work, the pane cost is a **setting**, and the operator's whole "every subagent
takes a slot" problem has a one-line fix. Probe: flip one account's `teammateMode`, fire a 2-teammate
wave, and re-run §3.9(a)'s joiner + `ps -o lstart` against it.

**Q4 (hygiene, has a named owner).** A3's `claude --bg` probe leaked 1 daemon + **4** `bg-pty-host`
spares (462 MB) that are still running, and its "spare pool = exactly 1" reading disagrees with the
live count of 4. Someone should reap it and re-read the spare-pool logic.

**Q5 (accounting, for the ceiling model).** Named teammates get their own pane *and* their own MCP
server *and* their own SessionStart hook, but inherit the lead's account — so an 11-teammate wave is
**11 panes + 11 processes + 11 MCP servers + 12 conversations on one account**, while the router's
`KMAX=8` counts **one**. Is `KMAX` already being breached in practice? Cross-check
`claude-accounts --readout` (invoke directly — it is `#!/usr/bin/env python3`, per A6) against a
per-`CLAUDE_CONFIG_DIR` process census during a live wave.
