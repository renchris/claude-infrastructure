---
axis: A6 — the quota / account wall. Which orchestration unit spends WHOSE budget?
date: 2026-08-19
status: DERIVED — 5-hour meter re-fitted from deduped transcripts (R²=0.974, n=23 windows);
        billing attribution proven at the process + filesystem level; saturation record extracted
headline: >
  A subagent, an Agent-Teams teammate and a Dynamic-Workflow agent are all structurally UNROUTABLE —
  each inherits its parent's CLAUDE_CONFIG_DIR (measured in the live process env) and writes into the
  parent account's own transcript store, so every token it burns lands on ONE of the four 5-hour /
  weekly meters. Only a dispatched handoff session can be launched on a different account. On a
  single five-hour window quota does NOT bind before hardware (an account supports ~10-20
  continuously-working Opus units vs the ~15 hardware ceiling); on the WEEK it binds first and has
  already bound — all four accounts have touched 85-100% weekly inside the last 9 days, and next3
  hit 100% of its five-hour window five times, once for 212 minutes at k=36.
load_bearing_claim: >
  Fleet quota is not a bigger version of the machine ceiling. It is a DIFFERENT ceiling on a
  DIFFERENT axis: the box limits how many units exist at once, the weekly meter limits how much
  those units may EMIT over 7 days. Process engineering that lifts 15 → 40 concurrent sessions
  raises the burn rate against an unchanged weekly allowance, so it converts a capacity win into an
  earlier wall unless the extra units are spread across accounts — and fan-out units cannot be.
---

## 1. Verdict (≤5 lines)

1. **Every in-session unit bills the parent's account.** MEASURED: an `--agent-id` process carries
   `CLAUDE_CONFIG_DIR=/Users/chrisren/.claude-tertiary` (= `next3`) inherited from its parent, holds
   its OWN TLS socket to the Anthropic API, and its transcript is written into that account's store.
   Subagents, teammates and Workflow agents are therefore **unroutable**; only `handoff-fire` sessions
   are.
2. **The 5-hour meter is not what usually stops us.** Re-fitted from deduped transcripts: 100 pp of a
   five-hour window buys **12.6 M Opus-5 output tokens or 53.9 M cache-creation tokens**; cache-READ is
   free. That is ~10-20 continuously-working units per account — *above* the ~15 hardware ceiling.
3. **The WEEKLY meter is the real wall, and it is already binding.** `next` 91%, `next2` 92%, `next4`
   85%, `next3` **100%** observed in the last 9 days. Sustained duty cycle allowed: **21-29%**, i.e.
   **~2-6 continuously-working units per account, 8-23 fleet-wide** — *below* the hardware ceiling.
4. **Fan-out concentrates that burn 4× harder than dispatch.** The same 8 units of work cost the same
   total pp either way; 8-on-one-account charges all of it to one 100-pp meter, 8-over-four charges
   25% to each of four. Measured saturation: `next3` 08-18 00:30Z hit **100 pp inside one window**, and
   **68% of the output that got it there came from Agent-Teams agents**.
5. **So the answer to the operator's question changes on the time horizon, not on the unit.** For a
   burst, break the process ceiling and quota will not stop you. For anything that runs for days,
   quota binds first and *no amount of process engineering moves it* — the only lever is spreading
   across accounts, which is exactly the lever a subagent/teammate/Workflow agent does not have.

---

## 2. The numbers, with the command that produced each

### 2.0 The live account readout, VERBATIM

`/Users/chrisren/.claude/bin/claude-accounts --readout` — note the brief's `bash <path>` form is
wrong: the file is `#!/usr/bin/env python3`, and running it under `bash` produces a garbage docstring
dump plus a crash from an unrelated pnpm-global CC 2.0.5 (`TypeError: B.allowedTools is not iterable`).
Invoke it directly.

```
| account | live | 5h used | 5h resets | weekly used | Fable used | weekly resets | login expires |
|---|---|---|---|---|---|---|---|
| **next** ➤ᶠ | 2 | 3% | Wed 07:29 (in 2.8h) | 52% | 21% | Sat 20:59 (in 3d 16h) | Tue Sep 15 15:44 (in 27d 11h) |
| next4 | 3 | 4% | Wed 09:19 (in 4.6h) | 26% | 15% | Sun 01:59 (in 3d 21h) | Sat Sep 12 23:02 (in 24d 18h) |
| next3 | 9 | 23% | Wed 07:00 (in 2.3h) | 11% | 0% | Tue Aug 25 05:00 (in 6d) | Thu Sep 03 10:27 (in 15d 5h) |
| **next2** ➤ ← you | 5 | 5% | Wed 08:49 (in 4.1h) | 29% | 0% | Sat 03:59 (in 2d 23h) | Mon Sep 07 04:28 (in 18d 23h) |

➤ desk (bare `claude`) → **next2** — earliest weekly reset among 5h-safe accounts · weekly ↻ 2d 23h · 5h 5% · safe set · sticky
➤ general → **next2** · ➤ fable → **next**
weekly burn (1.00× = lands exactly at the 100% wall): next2 burn 0.50× → ~50% by reset, needs 24%/d over 2d (recent 16%/d) · next burn 1.10× → ~110% by reset ⚠ WALL, needs 13%/d over 3d (recent 2%/d) · next4 burn 0.58× → ~58% by reset, needs 19%/d over 3d (recent 4%/d) · next3 burn 0.78× → ~78% by reset, needs 15%/d over 6d (recent 16%/d)
Fable window: **permanent** (no expiry).

**Agent backends beyond Claude** — registry `~/.claude/providers.json`

| backend | routable | version | auth | plan | bills outside it? | model pinned |
|---|---|---|---|---|---|---|
| Codex CLI | ✅ | codex-cli 0.147.0 | ok | ChatGPT Plus | no | gpt-5.6-sol @ xhigh ✓proven |
| Pi · Codex backend | ✅ | 0.84.1 | ok | ChatGPT Plus | no | gpt-5.6-sol ✓proven |
| Pi · Claude backend | ⊘ skipped | 0.84.1 | credentials_not_configured | Claude Pro/Max (auth works, usage does NOT draw on the plan) | 🚨 **YES** | — |
| Antigravity | ⊘ skipped | 1.107.0 | ok | UNKNOWN | UNKNOWN | — |
| Gemini CLI | ⊘ skipped | 0.29.5 | ok | UNKNOWN | UNKNOWN | gemini-3-pro-preview ⚠unproven |
| Grok CLI | ⊘ skipped | not installed | — | UNKNOWN | 🚨 **YES** | — |
- ⊘ `pi-claude` — COST GATE FAIL — bills per token outside the Max plan
- ⊘ `antigravity` — NOT AN AGENT BACKEND — the binary is the VS Code editor launcher, no non-interactive mode
- ⊘ `gemini` — DEFERRED — plan tier UNKNOWN, so the cost gate cannot clear it
- ⊘ `grok` — COST GATE FAIL — API-key-only, and we hold no xAI plan

➤ non-Claude backends ready now: **2 of 2 routable** (6 known)
- 🚨 rows marked **YES** bill OUTSIDE a plan we hold — not wired, by policy (`accounts.json spend.usage_credits_authorized=false`)
```

Reading it: `next` is the only account on a wall trajectory (1.10× burn), `next3` carries the fan-out
load right now (9 live sessions, 13 working, 23% of its 5-hour window with 2.3 h to reset), and there
are **two non-Claude backends already routable** — the only units in this whole wave that consume
neither a Claude slot nor a Claude meter.

---

### 2.1 BILLING ATTRIBUTION PER UNIT — MEASURED

| unit | own OS process? | account it bills | how proven |
|---|---|---|---|
| dispatched session (`handoff-fire --account`) | yes | **whichever account was chosen at launch** | launcher sets `CLAUDE_CONFIG_DIR`; `accounts.json` maps it to the keychain item |
| Agent-Teams teammate / research subagent (`--agent-id`) | yes | **the PARENT's account, always** | env + transcript location, below |
| Dynamic-Workflow agent | (see A1-A5) | **the PARENT's account, always** | transcript location, below |
| classic `Task`-tool sidechain | no separate process observed | **the PARENT's account** | sidechain records live inside the parent's own `.jsonl` |

**Proof 1 — the agent process inherits the parent's account identity.**

```
$ ps -E -ww -p 8435 -o command= | tr ' ' '\n' | grep -iE 'CLAUDE|CONFIG_DIR|ANTHROPIC|API_KEY|OAUTH'
/Users/chrisren/.claude-220/node_modules/@anthropic-ai/claude-code/bin/claude.exe
CLAUDE_CODE_EAGER_FLUSH=1
CLAUDE_CODE_NO_FLICKER=1
CC_PANE_CMD_DIR=/Users/chrisren/.claude/run/kitty-pane-cmd
CLAUDECODE=1
CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
CLAUDE_CONFIG_DIR=/Users/chrisren/.claude-tertiary
```

pid 8435 is `claude.exe --agent-id A9-prior-art@session-84bde2e9 --agent-name A9-prior-art
--team-name session-84bde2e9 --parent-session-id 84bde2e9-… --agent-type deep-research`. Its
`CLAUDE_CONFIG_DIR` is `~/.claude-tertiary`, which `accounts.json` maps to **`next3`**:

```
$ python3 -c "…json.load(open('accounts.json'))…"
next  | ~/.claude-next       | launcher= claude  | aliases= ['claude']
next4 | ~/.claude-quaternary | launcher= claude4
next3 | ~/.claude-tertiary   | launcher= claude3
next2 | ~/.claude-secondary  | launcher= claude2
```

There is **no `ANTHROPIC_API_KEY` and no separate OAuth material in the agent's env** — it resolves
credentials the same way `claude-accounts` documents (keychain item
`Claude Code-credentials-<sha256(realpath(config_dir))[:8]>`), i.e. from the parent's config dir.

**Proof 2 — the agent talks to Anthropic itself, on the parent's token.**

```
$ lsof -p 8435 | grep -iE 'claude|keychain' | awk '{print $4, $9}' | sort -u
12u 192.168.0.181:57640->160.79.104.10:https
13u [2600:8802:705:8100:…]:57647->[2607:6bc0::10]:https
cwd /Users/chrisren/Development/.worktrees/wt-pool-8
txt /Users/chrisren/.claude-220/…/bin/claude.exe
```

So it is not proxying through the parent — it holds its own HTTPS connection, and the only identity
available to it is the parent's.

**Proof 3 — its usage lands in the parent ACCOUNT's records, in a separate SESSION file.**

```
$ ls /Users/chrisren/.claude-tertiary/projects/-Users-chrisren-Development--worktrees-wt-pool-8/
84bde2e9-…jsonl      ← the parent session
478a8a2f-…jsonl      ← A7-single-user   (agentName set, teamName=session-84bde2e9, isSidechain=false)
2c597e9c-…jsonl  38d58223-…jsonl  ec263daf-…jsonl  f6b26ee7-…jsonl  …  (one per agent)
```

Each agent record carries `agentName` + `teamName` + full `message.usage`. **Workflow** agents are
filed one level deeper, still inside the parent account's store:

```
$ grep -rl '"isSidechain":true' …/wt-pool-8/
…/f9d4b4ee-…/subagents/workflows/wf_477e043f-09b/agent-a8ce02bfc0e62ea81.jsonl   (+4 more)
```

**Consequence.** The 5-hour / weekly meters are per OAuth account. A unit that cannot choose its
config dir cannot choose its meter. **Routing is a property of the launch, and only a dispatched
session has a launch.**

---

### 2.2 THE INSTRUMENT — and the trap that would have doubled every number

```
$ python3 burn2.py   # walks 4 stores, 60 h, dedupes on message.id
raw assistant usage records (60h): 48326  duplicates removed: 24152 (50.0%)  unique: 24174
```

**Exactly 2.00× inflation** if you sum lines instead of deduping on `message.id` (repo memory
`transcript-lines-repeat-one-billed-response` says 2-3×; measured here it is 2.00 at fleet scale).
Every figure below is deduped.

Instrument controls run:

| control | result |
|---|---|
| are the 4 stores really disjoint? | `~/.claude-next/projects` is a **symlink** to `~/.claude/projects` — so there are **4** stores (`next`=`~/.claude`), not 5. A naive `find ~/.claude-next -name '*.jsonl'` returns **0** and reads as "next never ran". |
| cross-store duplicate transcripts (would mis-attribute) | 145 / 6,876 rel-paths = **2.1%** overall, **1 / 405 = 0.2%** in the last 60 h. Negligible. |
| is `sidechain-subagent = 0` a blind instrument? | POSITIVE CONTROL: `grep '"isSidechain":true'` over recent files → **114 files inside `/subagents/`, 29 outside**. The string is findable. Re-counted with the *record's own timestamp*: **0** classic sidechain assistant records in the last 60 h — the 29 outside-files are older records in recently-appended files. Genuine absence, not blindness. |

---

### 2.3 THE 5-HOUR EXCHANGE RATE, RE-FITTED FROM DEDUPED DATA (my own measurement)

Joined `~/.claude/logs/account-utilization.jsonl` (7,641 rows, 4 accounts, ~6.8 min cadence) against
the deduped hourly token burn, bucketed into each account's real 5-hour windows
(`session_reset_at − 5 h`). Fit set = windows with ≥4.0 h of sample coverage, `0 < pp < 100`
(saturated windows are censored and excluded), no Fable.

```
5-HOUR METER FIT (deduped tokens, cache_read forced 0 per the 2026-08-16 meter experiment):
  opus OUTPUT      = 7.93 pp per 1M tokens   -> 1 pp = 126,115 output tokens; 100 pp = 12.61M output tokens
  opus CACHE-CREAT = 1.85 pp per 1M tokens   -> 1 pp = 539,145 cc tokens;     100 pp = 53.91M cc tokens
  out:cc ratio = 4.3   R^2 = 0.974   n=23   RMSE=1.73 pp  sd(y)=10.74
```

Cross-check against the prior repo fit (`docs/research/usage-telemetry-100p-2026-08-16/exchange-rate.md`,
finding #12, A1's raw 5-hour bucket): `opus_out 9.2747`, `opus_cc 1.0353`, `opus_cr 0.0000`, R²=0.54.
Mine agrees on output within 15% and on cache-read exactly (zero), but puts cache-creation **1.8×
higher**. Both agree the sign structure is `output ≫ cache-creation ≫ cache-read ≈ 0`. Mine has the
better fit (R² 0.974 vs 0.54) and is built on deduped tokens, which A1's was not.

**Cache-read is confirmed free.** `cache_read` spans 0 → 735 M tokens across the fit windows, a 3-order
range; a model that omits it entirely still explains 97.4% of the variance. A charged term could not
hide in that.

Full window table (48 windows, 60 h, 4 accounts — `pred` = my fitted model):

```
acct   window start      cov   pp  pred   opus_out    opus_cc |  main_out teams_out wfagent_out
next   08-17 09:50Z      4.7   31  26.4  1,294,499  8,677,066 |   202,050 1,092,612           0
next   08-17 14:50Z      4.9   50  52.9  1,285,364 23,016,421 |   313,369   962,093       9,902
next   08-17 19:50Z      4.8  100 145.4    538,991 76,088,087 |   336,849   202,142           0   <-- WALL
next2  08-17 01:00Z      4.8   30  25.6    318,453 12,462,998 |   216,217         0     102,236
next2  08-18 19:50Z      4.8   18  19.8  1,121,564  5,884,519 | 1,084,147    12,205      25,212
next3  08-17 04:30Z      4.8   46  28.3  1,320,737  9,632,484 | 1,079,965   523,380      35,360
next3  08-17 09:30Z      4.9   19  19.3  1,184,555  5,344,169 |   510,138   674,417           0
next3  08-18 00:30Z      4.9  100 112.6  2,666,126 49,306,423 |   858,360 1,807,766           0   <-- WALL
next3  08-19 09:00Z      2.8   23  13.7    638,602  4,657,290 |   358,739   279,863           0   <-- live now
next4  08-18 02:50Z      4.9   20  12.4    355,053  5,182,442 |   270,029         0      90,800
  (…39 more rows, all four accounts, in scratchpad windows.json)
```

**Two windows hit the 5-hour wall inside 60 hours**, and in the worse of the two (`next3` 08-18 00:30Z)
**68% of the output that saturated the meter was `teams-agent` output** (1.81 M of 2.67 M).

---

### 2.4 WHAT EACH UNIT COSTS, IN 5-HOUR PERCENTAGE POINTS

**Live Agent-Teams wave on `next3`** (window 09:00Z→11:50Z today, 11 agents of `--agent-type
deep-research`, still running at time of measurement):

```
team|agent                                  resp       out  cache_creat    cache_read  5h-pp
session-84bde2e9|A7-single-user               39    40,381      178,190     5,184,756   0.65
session-84bde2e9|A1-client-lifetime           54    39,631      195,884     7,452,311   0.68
session-84bde2e9|A5-concurrent-wrongness      30    33,246      203,562     4,618,494   0.64
session-84bde2e9|A6-retention                 31    30,442      170,994     4,208,519   0.56
session-84bde2e9|A2-replicache-semantics      35    27,149      158,920     4,387,118   0.51
session-84bde2e9|A4-referential-deps          36    26,909      175,533     5,071,658   0.54
session-84bde2e9|A3-server-preconditions      29    26,807      190,015     3,996,692   0.56
session-84bde2e9|A8-callsite-inventory        27    23,248      198,011     4,154,616   0.55
session-84bde2e9|A9-prior-art                 32    17,094      143,122     3,431,022   0.40
session-84bde2e9|A11-redteam-widening         13     7,914      115,431     1,243,019   0.28
session-84bde2e9|A10-hostile-reviewer         10     6,497       91,956       816,846   0.22
TOTAL agents                                                                            5.58
main-session in the same window                                                         8.0
                                                        meter read 23 pp at 11:44:30Z  (model 13.6)
```

**Dynamic-Workflow agents, 2,704 completed runs across 159 workflows, 4 accounts:**

```
  per-agent 5h-pp cost:  p10=0.088  med=0.213  p90=0.478  p99=1.239  max=3.175  mean=0.268
  per-agent output tok:  med=230    p90=8,681   max=75,007
  per-agent cache-creat: med=109,507  p90=228,529  max=1,670,054
  => a 100-pp 5h window buys ~373 MEAN workflow-agent runs, ~469 MEDIAN, ~209 p90 runs
```

**The median Workflow agent emits 230 tokens and pays 109 K cache-creation to boot.** Its quota cost
is ~95% *arrival tax*, not work — the resident-context load (CLAUDE.md, memory index, tool schemas,
MCP rosters) that the 2026-08-16 meter experiment priced at 46 K cc for a trivial `claude -p`. A
fan-out unit therefore has a **fixed quota entry fee** that a long-running session amortises and a
short agent does not.

**Whole workflows, ranked by 5-hour cost:**

```
  acct   workflow             agents  peak  span_h   5h-pp   pp/h
  next2  wf_e16552fc-ae6          58     8    7.75    39.6    5.1
  next3  wf_0f8a38e6-82f         229    48    7.20    39.1    5.4
  next   wf_96b0397f-c1d          63     8    2.63    35.8   13.6
  next2  wf_cbe444c1-0de          38     8    7.37    23.3    3.2
  next2  wf_b28a9960-949          30     8    1.91    21.4   11.2
  next   wf_edda7d3d-3d8          62     8    1.80    19.8   11.0
```

One 229-agent workflow costs **39 pp — 39% of an entire account's five-hour allowance.**

---

### 2.5 CONCURRENCY vs THROUGHPUT — the operator's "50-200 agents fine"

Measured per-minute active-agent counts (a minute counts an agent if it emitted an assistant response
in it — a response is an instant, so this cannot inflate the way a first-to-last span can):

```
--- next3 wf_0f8a38e6-82f: agents=229  minutes-with-activity=54
    ACTIVE AGENTS PER MINUTE: max=50  p95=49  median=40  mean=34.15
--- next3 wf_d20aadf6-502:  agents=83   max=16  p95=14  median=10
--- next  wf_96b0397f-c1d:  agents=63   max=10  p95=9   median=7
--- next2 wf_e16552fc-ae6:  agents=58   max=8   p95=7   median=2
```

Across all 159 workflows: **agents/workflow max 229, median 12; peak concurrent max 48, median 7.**
158 of 159 workflows peak at ≤8 — but the one exception is real and sustained: **50 agents emitting in
the same wall-clock minute, median 40, for 54 minutes.** So "Workflows run 50-200 agents" is *partly*
throughput (229 total) and *partly* genuine concurrency (50 at once) — and the 50-wide case cost 39 pp
against one account.

---

### 2.6 A STRUCTURAL DIFFERENCE NOBODY IN THIS REPO HAS RECORDED: CACHE TTL

```
=== CACHE-CREATION TTL SPLIT, last 60h, deduped on message.id ===
class                     resp          cc_1h          cc_5m  1h share          out
main-session            13,273    159,431,596              0    100.0%   10,185,143
teams-agent              6,955     67,688,913              0    100.0%    5,254,034
workflow-agent           3,918              0     33,453,816      0.0%      474,693
```

**Perfect separation.** Sessions and Agent-Teams agents write **1-hour-TTL** cache; Dynamic-Workflow
agents write **5-minute-TTL** cache. On Anthropic's list schedule a 1 h cache write is 2.0× base input
and a 5 m write is 1.25× — a **1.6× price difference per cache-creation token**, applied to the token
class that dominates a fan-out unit's cost.

This is a candidate mechanism for the largest residual in my fit: the two windows that under-predict
worst (`next3` 08-17 04:30Z pred 28.3 / obs 46; `next3` 08-19 09:00Z pred 13.7 / obs 23) are the two
most `teams-agent`-heavy windows in the set. A single cache-creation coefficient cannot be right for
both classes if their TTLs differ. **Flagged for the verifier — this is inferred from list pricing,
not measured against the meter**, and it would need a decorrelation experiment of the kind the
2026-08-16 meter experiment ran.

---

### 2.7 THE ARITHMETIC THE AXIS ASKS FOR

*8 concurrent agents on ONE account vs 8 dispatched sessions across FOUR.*

The total quota cost is **identical** — same model, same work, same tokens. What changes is the
denominator each point is charged against:

| shape | pp drawn | charged against | fraction of the wall consumed |
|---|---|---|---|
| 8 Agent-Teams agents, 1 account, 15 min | 4.1 pp (measured: 11 agents = 5.58 pp) | one 100-pp meter | **4.1%** |
| 8 Agent-Teams agents, 1 account, 2 h | ~33 pp (extrapolated at the measured 16 pp/h for 8-wide) | one 100-pp meter | **33%** |
| 8 Workflow agents, 1 account, one round | 2.1 pp (8 × 0.268 mean) | one 100-pp meter | **2.1%** |
| a whole 8-wide workflow | 12-40 pp (measured range) | one 100-pp meter | **12-40%** |
| 8 dispatched sessions, 4 accounts | same total pp | **four** 100-pp meters, 2 sessions each | **¼ of the above, per account** |

**Spreading is a pure 4× win on the quota axis and costs nothing** — the work is the same, the tokens
are the same, only the exposure per meter changes. And it is available to exactly one unit.

---

### 2.8 MAXIMUM SUSTAINABLE CONCURRENT AGENT COUNT — the verdict this axis owns

Three independent derivations of the burn rate of one **continuously-working** Opus-5 unit:

| method | pp/h per working unit |
|---|---|
| live Agent-Teams wave (0.51 pp mean per agent over ~15 min) | ~2.0 |
| whole-workflow rate ÷ peak concurrency (3.2-16.4 pp/h at 6-8 wide) | 0.4-2.0 |
| least-squares through origin of Δ5h-pp/h against `k_work`, 690 intervals | 0.97 (biased low: the meter is integer-quantised, so most 6-min intervals read Δ0) |

Band: **1.0-2.0 pp/h per continuously-working unit.** Each account releases 20 pp/h (100 pp per 5 h).

| horizon | per account | fleet (4 accounts) | vs the ~15 hardware ceiling |
|---|---|---|---|
| **BURST** — one 5-hour window at full duty | **10-20** working units | **40-80** | quota is LOOSER; hardware binds first |
| **SUSTAINED** — a full week at that duty | **2-6** working units | **8-23** | quota is TIGHTER; **quota binds first** |

The sustained row uses the weekly:5-hour allowance ratio measured in
`exchange-rate.md` finding #13 (weekly ≈ 7.2-9.8 five-hour allowances, spread over the 33.6 five-hour
windows in a week ⇒ **21-29% duty cycle**).

**And the sustained row is not a projection — it is the observed record.** Maximum `weekly_pct` seen
per account over the log's 9 days:

```
  next   weekly max=91%   current=53%
  next4  weekly max=85%   current=26%
  next3  weekly max=100%  current=11%
  next2  weekly max=92%   current=29%
```

Five-hour saturation events (`session_pct ≥ 90`), with live-session counts at the time:

```
  next   08-17 23:20Z -> 00:45Z   85 min  peak=100%  k=4      k_work=0-4
  next3  08-10 08:44Z -> 12:16Z  212 min  peak=100%  k=36     k_work=n/a
  next3  08-16 23:14Z -> 00:59Z  104 min  peak=100%  k=5-10   k_work=1-10
  next3  08-18 04:45Z -> 05:26Z   40 min  peak=100%  k=12-14  k_work=0-10
  next3  08-18 07:54Z -> 10:27Z  153 min  peak=100%  k=7-9    k_work=0-3
share of samples at >=90% of the 5-hour window:
  next 14/1901 = 0.7%   next4 0/1874 = 0.0%   next3 74/1902 = 3.9%   next2 0/1908 = 0.0%
```

Fleet duty cycle actually run over the last 60 h: **612 pp-equivalent consumed of 4,800 pp available
(12 windows × 4 accounts) = 12.8%** — i.e. the fleet already sits about half-way to the sustainable
weekly duty cycle, with all four accounts having touched 85-100% weekly inside 9 days.

**Class attribution of that 612 pp:**

```
  main-session         resp=13,313  out= 10,212,302  cc= 159,812,916  ->  377.4 pp  (62%)
  teams-agent          resp= 6,950  out=  5,250,949  cc=  67,681,598  ->  167.2 pp  (27%)
  workflow-agent       resp= 3,911  out=    467,955  cc=  34,439,494  ->   67.6 pp  (11%)
  sidechain-subagent   resp=     0                                    ->    0.0 pp
```

**38% of everything this fleet spends is already spent by unroutable units.**

**Which binds first — the answer that changes the operator's decision.**
*Hardware limits how many units EXIST at once. Quota limits how much they may EMIT over seven days.*
Those are different ceilings on different axes, and lifting the first without the second is not
neutral — it is harmful: raising 15 → 40 concurrent sessions raises the burn rate against an
**unchanged** weekly allowance, so the weekly wall arrives ~2.7× sooner. The only lever that moves the
weekly ceiling is spreading across accounts (or the two already-routable non-Claude backends), and
subagents / teammates / Workflow agents structurally cannot pull it.

---

## 3. What I tried that did NOT work, or could not be measured

1. **`bash /Users/chrisren/.claude/bin/claude-accounts --readout` (as the brief specifies) is wrong**
   and fails loudly-but-confusingly. The file is `#!/usr/bin/env python3`; under `bash` it emits its
   own docstring as commands (`accounts.json: command not found`) and drags in an unrelated
   pnpm-global CC 2.0.5 crash. Run it directly. **Correct the brief for other axes.**
2. **The `--json` readout does not carry the 5-hour/weekly *dollars*.** `limit_dollars` /
   `used_dollars` / `remaining_dollars` exist in the raw API payload and are `null` on Max, so the
   meter's face value is unobservable and everything here is percentage-denominated.
3. **The utilization log's `session_reset_at` varies in its microseconds sample-to-sample**, so keying
   5-hour windows on the raw string fragments 534 rows into 1,806 one-row "windows". Truncate to the
   minute. This silently produced a first, wrong window table before I caught it.
4. **`k_work` is too noisy an instrument for a per-session burn rate.** 224 of 914 intervals have
   `k_work=0` yet nonzero burn, the median Δpp is 0 at nearly every `k_work` (integer quantisation at
   1 pp = 126 K output tokens), and `k_work` occasionally reads `None`. The regression through origin
   (0.97 pp/h) is a *lower* bound only; I used it as the floor of a band, not as the estimate.
5. **I did not decorrelate the 1 h vs 5 m cache-TTL price.** The separation between classes is perfect
   (100% / 0%), which means observational data can *never* identify the two coefficients separately —
   class and TTL are collinear. Settling it needs a deliberate experiment (run the same workload once
   as a teammate and once as a Workflow agent on an idle account), which I judged outside a read-only
   axis. **This is the single largest open number in this file.**
6. **I spawned no probe sessions.** No `claude -p`, no fires, no teardown, nothing killed or stopped.
   Everything above is `ps`/`lsof`/log/transcript reads plus one direct invocation of the read-only
   `claude-accounts` dashboard (which does issue 4 live usage GETs — it is the sanctioned path and was
   already cache-warm).
7. **`~/.claude-next/projects` is a symlink to `~/.claude/projects`.** A per-store `find` reports 0
   transcripts for `next` and reads as "this account never ran". Any axis walking the four stores must
   treat `~/.claude` as `next`'s store.
8. **Cross-store duplicate transcripts exist (2.1% all-time).** 65 files appear in both `next` and
   `next3`, 63 in both `next2` and `next3`. In the 60-hour window it is 1 file, so it does not move my
   numbers — but a longer-horizon attribution study must dedupe on rel-path across stores as well as
   on `message.id` within one.

---

## 4. Open questions for the verifier

1. **Does a 1-hour cache write really cost 1.6× a 5-minute one against the Max meter?** §2.6 shows a
   perfect class/TTL separation; §2.3 shows the two worst residuals are the two most agent-heavy
   windows. If the answer is yes, an Agent-Teams teammate is *quota-more-expensive per identical token*
   than a Workflow agent, and my single cache-creation coefficient understates teams fan-out. Test: one
   idle account, same prompt, once as a teammate and once as a Workflow agent.
2. **Is `session_pct` a hard 5-hour bucket or a rolling window?** `next3` 08-18 05:30Z read 100 pp on
   a window whose own burn predicts 10.4 — consistent with carry-over from the saturated 00:30 window.
   If it is rolling, my window-bucketed fit slightly mis-attributes burn at boundaries (it would not
   change the sign or order of magnitude of any conclusion here).
3. **`next3` accounts for 74 of the 88 fleet-wide 5-hour saturation samples.** Is that because it is
   where fan-out is routed (its `k_work=13` today, vs 1-2 elsewhere), or because the router
   `kmax-concurrency`-excludes it once busy and so never relieves it? `route_reasons` for next3 today
   is `kmax-concurrency` on all three lanes — it is excluded from *new* routing while carrying the
   heaviest load. Worth checking whether that is the intended behaviour.
4. **Both non-Claude routable backends (Codex CLI, Pi·Codex) consume neither a Claude pane nor a
   Claude meter.** No axis in this wave owns them. If the operator's real question is "what breaks the
   ceiling", a unit that draws on a *different vendor's* quota is the only one that breaks BOTH
   ceilings at once, and it is already `✅ routable`.
5. **My out:cc ratio is 4.3; A1's was 9.0 (5-hour) and 12.2 (weekly).** Both fits agree cache-read is
   zero and output dominates, but the cc weight differs ~1.8×. Mine is deduped and fits far better
   (R² 0.974 vs 0.54); A1's is not deduped. Someone should decide which the repo carries forward — the
   `USAGE_TELEMETRY_100P` plan currently quotes A1's.
