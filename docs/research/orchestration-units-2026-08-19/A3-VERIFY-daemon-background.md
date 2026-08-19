# A3-VERIFY — adversarial verification of "daemon / background sessions"

**Date:** 2026-08-19 · **Verifier:** adversarial (refute-by-default) · **Subject:** `A3-daemon-background.md`
**Binary:** `/Users/chrisren/.claude-220/node_modules/@anthropic-ai/claude-code/bin/claude.exe` (2.1.220,
`4073f595…`, 256,908,272 B) — **note:** there is **no `cli.js`** in that package (`ls` → No such file);
every string result below is from the Mach-O `claude.exe`.
**Probes I ran and tore down:** three `claude --bg` jobs (`6f0c39c9`, `8a95f05e`, `608a9940`) + one **fresh
interactive pty session** (`script -q /dev/null claude.exe --permission-mode plan`) — the matched control the
finder said was impossible. Full teardown + verification in §4. No live-fleet process was touched.

---

## 1. VERDICT (≤5 lines)

> **The finder's architecture is right and its economics are wrong.** I reproduced the 5-process tree to
> within 1% (604.6 MB / 54 threads vs its 611.7 / 54) — but its headline "backgrounding costs ~1.9× memory"
> is an artifact of charging a **one-time 300 MB pool to the first job** and comparing a background *tree*
> against a foreground *process* whose own 95.6 MB MCP child it never counted. Measured marginal slope over
> 1→3 concurrent jobs: **+302 MB / +25.5 threads per job**, versus **423 MB / 30 threads** for a real
> in-repo foreground session. **At N≥2, background is at parity or cheaper — and it frees the pane.**
> Two of its load-bearing negatives are false: `state:"done"` does **not** mean "no process" (I held 3 live
> 217–225 MB workers that all reported `done`), and the operator **has** run three concurrently — for 8.6 h.

**Net for the operator's question:** backgrounding **does** buy real relief — but not the relief the finder
described, and it is capped by a defect neither of us liked: a *finished* background job stays resident at
full size for **one hour**, and the only mechanism that would evict it sooner reads **NORMAL at 92% memory**.

---

## 2. Per-claim adjudication

| # | Finder's claim | Verdict |
|---|---|---|
| C1 | 1 bg job = 5 procs / 611.7 MB / 54 threads | **CONFIRMED** (independent instance: 604.6 MB / 54 thr) |
| C2 | Foreground = 1 process / 329.6 MB / 19 threads | **REFUTED** — not 1 process, and not a matched age |
| C3 | **Backgrounding costs MORE (~1.9× mem, ~2× threads)** | **REFUTED** — marginal slope says parity |
| C4 | `state:"done"` + no pid ⇒ 0 live bg; "operator has never run one concurrently" | **REFUTED** (both halves) |
| C5 | Spare pool = exactly 1 | **CONFIRMED** (+ a census hazard the finder missed) |
| C6 | No worker-count cap anywhere | **CONFIRMED** (positive-controlled) |
| C7 | Only gate = macOS VM pressure ≥ CRITICAL, fires too late | **CONFIRMED + upgraded to measurement** |
| C8 | Worker registry gate "hardcoded false" | **PARTIALLY REFUTED** — real string, wrong registry |
| C9 | Our rails are blind to paneless sessions | **CONFIRMED** |
| C10 | `cc-await-ping` orphan survives `claude stop` | **CONFIRMED**, strengthened n=1 → n=3 |
| C11 | `200 50` = COLS × ROWS | **CONFIRMED** |
| C12 | NI=5 but PRI=31 — `nice` does not demote | **CONFIRMED** (control caveat stated) |
| C13 | — (missed) | **NEW:** `tengu_bg_leftarrow_inprocess` defaults **true** |
| C14 | tmux correction to the brief (2 procs, 5 sessions, `pgrep -c` blind) | **CONFIRMED** verbatim |

---

## 3. The numbers, with the command that produced each

### 3.1 Reading A — ONE background job (t ≈ +40 s), reproduces the finder

`/usr/bin/vmmap --summary <pid> | awk -F: '/Physical footprint:/…'` · `/bin/ps -M -p <pid> | tail -n +2 | wc -l`
· `/bin/ps -o ppid=,nice=,pri=,rss=,etime=,state= -p <pid>`

| pid | role | **footprint** | thr | NI | PRI | state |
|---|---|---|---|---|---|---|
| 82213 | `claude.exe daemon run --origin transient` | 113.6 M | 12 | 0 | 31 | `Ss` |
| 82248 | `bg-pty-host … spare/ceb1e128.pty.sock 200 50` | 85.9 M | 7 | 5 | 31 | `SNs` |
| 82286 | `bg-pty-host … spare/d24be9c4.pty.sock 200 50` | 85.6 M | 7 | 5 | 31 | `SNs` |
| 82386 | **WORKER** (claimed spare `ceb1e128`) | **219.7 M** | 19 | 5 | 31 | `SN` |
| 82531 | idle spare (`d24be9c4`) | 99.8 M | 9 | 5 | 31 | `SN` |
| | **TOTAL** | **604.6 M** | **54** | | | |

Finder: 611.7 M / 54 threads / 5 procs. **CONFIRMED — 1.2% apart, different daemon instance.** (MEASURED)

### 3.2 Reading B — THREE concurrent background jobs (the measurement neither of us had)

Fired `6f0c39c9`, `8a95f05e`, `608a9940` with the same trivial prompt. Same instruments.

| pid | role | **footprint** | thr |
|---|---|---|---|
| 82213 | daemon | 117.8 M | 13 |
| 82248 / 82286 / 16331 / 16980 | four `bg-pty-host` | 86.0 / 85.8 / 86.3 / 84.8 M | 7 each |
| 82386 / 82531 / 16424 | **three live WORKERS** | 217.8 / 207.4 / **225.2** M | 18 / 18 / 19 |
| 17215 | the one idle spare | 97.5 M | 9 |
| | **TOTAL (3 jobs)** | **1208.6 M** | **105** |

**The slope — this is what refutes C3:**

| Quantity | Value | Derivation |
|---|---|---|
| **Fixed standing pool** | **300.1 M / 23 thr** | daemon 117.8 + idle spare 97.5 + its pty-host 84.8 |
| **Marginal per bg job** | **302.0 M / 25.5 thr** | (1208.6 − 604.6) / 2 · (105 − 54) / 2 |
| …decomposed | worker ~217 M + pty-host ~86 M | per-row, above |

### 3.3 The foreground comparator the finder got wrong (C2)

| Subject | **footprint** | thr | command |
|---|---|---|---|
| **my FRESH interactive pty session** (82160) | **143.6 M** → 147.0 M @1:45 | 16 → 17 | `sleep 400 \| timeout 380 script -q /dev/null claude.exe --permission-mode plan` |
| finder's comparator 95587, **40 min old** | 327.8 M | 18 | `vmmap --summary 95587` |
| …its `ms-365-mcp-server` child 96013 — **uncounted** | **95.6 M** | 12 | `ps -axo pid,ppid,rss,command \| awk '$2==95587'` |
| **95587 as a TREE** (the like-for-like unit) | **423.4 M** | **30** | sum |

Two independent errors, and they run in **opposite** directions:

- **(a) tree-vs-process.** 95587 is not "1 process": it has an MCP child at 95.6 M / 12 threads, plus
  `caffeinate` and two zsh. **Every** interactive session on this box has one — `ms-365-mcp-server` appeared
  as a child of 95587, 99124, 54762, 55717, 20435, 9576, 69257, 61532, 53709, 43029, and even of the
  `--agent-id A10-hostile-reviewer` subagent 17602. It is configured **user-level**
  (`~/.claude-secondary/settings.json` + `.claude.json`; there is **no** `.mcp.json` in the repo), so it is
  not a repo artifact. This error made foreground look **cheaper**.
- **(b) age.** A fresh interactive session is **143.6 M**, not 329.6 M. The 329.6 is 40 minutes of context,
  not foreground-ness. This error made foreground look **more expensive**.

**Corrected comparison, matched:** bg marginal **302 M / 25.5 thr** vs foreground tree **423 M / 30 thr**.
The bg pty-host tax (~86 M / 7 thr) is very nearly cancelled by the foreground MCP tax (~96 M / 12 thr).
⚠️ **My confound, stated:** both my probes ran in a `/tmp` scratchpad and **neither** spawned an MCP child, so
they are symmetric to each other but do not settle whether a bg worker *in a repo* would spawn one. **UNMEASURED.**

### 3.4 C4 — the screenshot. Both halves refuted, by two different instruments

**(i) "no pid ⇒ no process" is a blind instrument (method rule 5).** The background-job schema has **no pid
field at all**. Enumerating every key of all six `jobs/*/state.json`:

```
['state','detail','tempo','inFlight','fan','tokens','output','children','linkScanOffset','linkScanPath',
 'template','respawnFlags','intent','sessionId','resumeSessionId','daemonShort','cliVersion','cwd',
 'bridgeSessionId','bridgeOutboundOnly','providerEnv','backend','createdAt','updatedAt','firstTerminalAt']
```

`pid`, `workerPid`, `ptyPid` are absent from **every** one. `pid` can only ever be missing.

**Demonstrated, not argued:** with my 3 workers live at 217.8 / 207.4 / 225.2 MB, `claude agents --json --all`
reported all three as `state:"done"` — while `claude daemon status` said, in the same minute:

```
bg workers:   3 running (control.sock), 3 in roster.json
holding this daemon open:
  3 bg workers running (daemon waits for them to settle)
```

⇒ **"N completed" is fully compatible with N full-size live processes.** `done` means *the turn settled*,
not *the process exited*.

**(ii) "the operator has never actually run one concurrently" — REFUTED by his own daemon log:**

```
[2026-07-24T18:41:48.831Z] [bg] bg claimed-spare 6dc23ecb (slash)
[2026-07-24T18:41:48.833Z] [bg] bg spawned      5e4eab69 (spare)
[2026-07-24T18:42:01.749Z] [bg] bg claimed-spare 1ed2634a (spare)
[2026-07-25T03:20:05.461Z] [bg] bg settled 1ed2634a (done)     ←  8.6 h later
[2026-07-25T03:34:04.745Z] [bg] bg settled 6dc23ecb (done)     ←  8.9 h later
[2026-07-26T21:08:08.936Z] [bg] bg settled 5e4eab69 (done)     ←  2.1 DAYS later
```

Three jobs started **within 13 seconds**, all three settled hours-to-days later. That is three concurrent
background sessions running for most of a working day.

**What the three screenshot entries ARE** (the attack brief's question, answered): **three separate
conversations**, each with its own `sessionId`, its own transcript, and — at the time — its own OS process.
Not history entries, not multiplexed in one process.

| job | transcript | bytes | lines |
|---|---|---|---|
| `6dc23ecb` investigate-session-closures | `~/.claude-secondary/projects/-Users-chrisren-Development-claude-infrastructure/6dc23ecb-….jsonl` | 1,270,896 | 517 |
| `5e4eab69` resume danny studio 60 handoff | `…/5e4eab69-….jsonl` | 693,391 | 283 |
| `1ed2634a` opus 5 upgrade handoff | `…/1ed2634a-….jsonl` | 338,415 | 113 |

The finder's *conclusion* for that specific screenshot (0 live at capture time) is still probably right — the
jobs are 3.5 weeks old and `/tmp/cc-daemon-501/` was empty. But the **rule it used to get there is false**,
and it is the rule that answers the operator's question.

### 3.5 C7 — the gate, upgraded from the finder's open question #3 to a measurement

Taken while the box carried ~16 sessions, i.e. **at our actual wedge point**:

```
$ sysctl kern.memorystatus_vm_pressure_level vm.compressor_bytes_used
kern.memorystatus_vm_pressure_level: 1          ← NORMAL
vm.compressor_bytes_used: 8047749440            ← 8.0 GB already compressed
$ top -l 2 -n 0 -s 1 | tail
Load Avg: 16.72, 18.87, 22.70
PhysMem: 59G used (9638M wired, 8615M compressor), 3747M unused
Processes: 1142 total, 7 running, 1135 sleeping, 6392 threads
```

**At 92% memory utilisation with 8 GB in the compressor, CC's sole admission gate reads NORMAL.**
It is provably useless for us. (MEASURED — this closes the finder's open question #3.)

**Refinement the finder missed: the low-mem path is not a refusal.** Strings around `tengu_bg_dispatch_low_mem`:

```
"bg: low memory (macOS memorystatus pressure level "…" MB free) — retiring settled workers before spawning"
"bg: low memory — skipping spare dispatch"
"bg: low memory but sweep anchor is "…"s stale (host slept?) — deferring eager retire to the next sweep tick"
```

It **sheds, then admits**. It declines only the *spare* prewarm. There is no path that rejects the job.

### 3.6 C6 — no worker cap, with positive controls on every negative (method rule 5)

`strings -a claude.exe | grep -cF "<term>"`:

| positive control | hits | | negative candidate | hits |
|---|---|---|---|---|
| `bg-pty-host` | 10 | | `tengu_bg_max` | **0** |
| `tengu_bg_low_mem_mb` | 2 | | `maxWorkers` | **0** |
| `teammateMode` | 22 | | `max_workers` | **0** |
| `kern.memorystatus_vm_pressure_level` | 2 | | `bg_max` | **0** |
| `BackendRegistry` | 21 | | `tengu_bg_concurrency` | **0** |
| `tengu_bg_` (all flags) | 247 (100 distinct) | | `maxConcurrent` | 41 — **none in the bg scheduler** |

All 41 `maxConcurrent` hits inspected individually with a ±260-byte window. Every one is HTTP/2 settings, the
AWS SDK h2 pool, or **the scheduled-tasks worker** — `maxConcurrent: E.number().int().positive().default(1)`
in `runDaemonWorker` / `WORKER_KINDS`. That is the **cloud routines/cron** subsystem, a *different* daemon
worker kind, and **its default concurrency is 1**. Worth flagging to A4 — it is not a bg-job cap.
**C6 CONFIRMED.**

### 3.7 C8 — right string, wrong registry (PARTIALLY REFUTED)

`isDaemonWorkerRegistryEnabled: ()=>ONe` is real, and it sits in an export list beside
`isDaemonServiceInstallEnabled`, `isAgentsFleetEnabled`, `isComposerSidebarEnabled`,
`isPastSessionsExperimentEnabled` — it gates a **daemon-hosted worker registry**, a product feature. It does
**not** gate `<CLAUDE_CONFIG_DIR>/sessions/<PID>.json`, and background workers **do** register there:

```json
{"pid":82386,"sessionId":"6f0c39c9-87f0-4890-8174-658ab4336689","cwd":"…/scratchpad/a3v",
 "procStart":"Wed Aug 19 12:05:35 2026","version":"2.1.220","kind":"bg","entrypoint":"cli",
 "jobId":"6f0c39c9","status":"idle","bridgeSessionId":"session_015t9b1TPSXJhCWHztir1cfS"}
```

Three such rows existed — **exactly one per live worker** — and the unclaimed spare had **none**.
`daemon/roster.json` independently carried `workers: 3`, keyed short-id → **pty-host** pid.

⇒ **CC already publishes a machine-readable live count of background workers in two places**
(`sessions/*.json` filtered on `kind:"bg"`, and `daemon status`'s `bg workers: N running`). The finder's §3
verdict that *nothing in our repo reads them* still stands, and this makes it a cheaper fix than it implied.

### 3.8 C5 — spare pool is 1 (confirmed), but argv cannot tell a spare from a worker (new)

At 3 concurrent jobs: 4 `bg-pty-host`/`bg-spare` pairs = **3 claimed workers + exactly 1 idle spare**.
**CONFIRMED** — my initial suspicion of a 2-deep pool was wrong; the second `bg-spare` at 1 job was the
refill, and by Reading B it had itself been claimed (9 thr / 97.5 M → 18 thr / 207.4 M).

**But the discriminator is not argv.** All four read `claude bg-spare --bg-spare …claim.sock` — the argv
**does not change on claim**. In the finder's instance the worker instead read `--session-id`, so *both*
shapes exist. A census keyed on argv counts a live 217 MB worker as an idle spare. Use **thread count**
(9 idle vs 18–19 live), footprint, or `sessions/<pid>.json`. (Same class as `argv-is-sampling-cwd-is-durable`
and `process-name-is-the-image-not-the-work` in MEMORY.md.)

### 3.9 C9 / C10 — our rails (attack #4), run read-only against 3 live bg workers

| rail | result | verdict |
|---|---|---|
| `bin/cc-where` | rendered `11 panes · 0 off-screen · 4 squeezed under 80 cols`; **zero** of my 3 workers | **BLIND — CONFIRMED** |
| `~/.claude/cc-registry/*.json` | 13 rows; `grep -l -E "6f0c39c9\|8a95f05e\|608a9940"` → **no match** | **BLIND — CONFIRMED** |
| `bin/cc-panes`, `bin/cc-registry` | **do not exist as files** (finder named them; `cc-where/-discover/-reaper/-teardown/-queue` do) | finder's list is loose |
| CC's `sessions/<pid>.json` | **3 rows, `kind:"bg"`, `status:"idle"`** | **sees them — §3.7** |

**C10 CONFIRMED and strengthened to n=3.** All three probes armed
`cc-await-ping <uuid> --timeout 14340 --interval 15` on a **paneless session-UUID**, and all three were
**still alive after `claude stop` reaped their workers** — pids 16892 / 17645 / 83080, still holding a 4-hour
timeout ~13 minutes past worker death. I ended them with `kill -9`. Corroborates backlog **#127**.

⚠️ **Bonus for the wave:** `cc-where` already renders an `OFF-BOX — no screen anywhere; these run in an
Anthropic VM` group (2 Cloud sessions, `kind=offbox`). The schema for *a session that consumes no local
slot* already exists in our tooling — a background worker is the same shape and could reuse it.

### 3.10 C12 / C11 / C13 / C14

- **C12 CONFIRMED with a stated control caveat.** Daemon NI=0 PRI=31; all four children NI=5 **PRI=31**. My
  own fg probe also read NI=5 (inherited from this agent's nice'd shell), so it is *not* a clean negative
  control — but a NI=0 parent spawning NI=5 children establishes CC applies the nice, and PRI never moved.
  Contrast on the same box: our own `taskpolicy -c background` processes read **PRI=4**. CC's bg workers sit
  in the **foreground QoS band** and count fully in the load-average numerator.
- **C11 CONFIRMED**, live argv:
  `claude bg-pty-host --bg-pty-host /tmp/cc-daemon-501/0503d474/spare/ceb1e128.pty.sock 200 50 -- …claude.exe --bg-spare …claim.sock`
- **C13 NEW — the finder missed it.** `tengu_bg_leftarrow_inprocess` defaults **true**:
  `if(Ke("tengu_bg_leftarrow_inprocess",!0))try{return await Spm(_,u,{dispatchDefaults:N,…,originSpawn:L})}catch(U){Re(U)}`
  then falls through to `qUe({args:["agents",…],env:{CLAUDE_AGENTS_SELECT:…}})`. So the "left arrow" agents
  view renders **in-process**, spawning a separate `claude agents` process only on throw. 🚨 **This is a
  DIFFERENT in-process mechanism from the `teammateMode:"in-process"` in the finder's §2.7 — A1/A2 must not
  conflate them.**
- **C14 CONFIRMED verbatim.** 2 tmux processes (24649 ppid=1 server, 8626 client); `tmux list-sessions` →
  **5** sessions (`1`, `dev` attached, `lr-resume-855b332e`, `lr-resume-8843d236`, `lr-resume-8ad3a9d2`). The
  brief's "1 process, 0 servers" was `pgrep -c` (not a macOS BSD pgrep flag, rc=2) reading 0 for every input.

### 3.11 The correction that matters most for the operator's question

The finder called the evictor "the one true ceiling-breaker: N conversations, K live processes, K ≪ N".
**The elasticity is real but LAZY, and in our regime its fast path never fires:**

| ladder rung | trigger | fires for us? |
|---|---|---|
| retire settled worker | idle **1 h** | eventually |
| retire settled worker | idle **60 s** *under CRITICAL pressure* | **never** — §3.5 measured pressure=1 at 92% mem |
| retire **pinned** workers | pressure persists after shedding all unpinned | **never**, same reason |

Measured directly: my three jobs finished their turn, reported `state:"done"`, and **still held
217.8 / 207.4 / 225.2 MB and 18–19 threads each two minutes later**. So a *completed* background job behaves
as **permanently resident for one hour** unless a gate fires that I measured stuck at NORMAL.
⇒ K is driven down by a **wall clock**, not by pressure. That is worse than the finder's reading.

---

## 4. What I tried that did NOT work / could not be measured

1. **Could not exercise the 1-hour retire.** Out of time budget; and I will not induce memory pressure on a
   box at 59 G/64 G to test the 60 s path. The retire *predicate* is read from strings (finder's §2.4); the
   *residency* is what I measured instead (§3.11). **The 1 h retire itself remains UNVERIFIED by execution.**
2. **Could not test a bg worker with MCP.** Both my probes ran in a `/tmp` scratchpad and neither spawned an
   `ms-365-mcp-server`. Symmetric between my two probes, so §3.3's slope is sound — but whether a bg worker
   *in a repo* pays the same ~96 MB / 12-thread MCP tax as a foreground session is **UNMEASURED**, and it is
   the single number that would move the parity verdict either way.
3. **Context is uncontrolled in both directions.** My bg workers ran one trivial turn; my fresh fg probe ran
   zero. 95587 at 40 min was 327.8 M against a fresh 143.6 M — **context is a bigger term than either the
   pty-host tax or the MCP tax**, and no read-only method drives two sessions to a matched token count.
4. **`vmmap` peak vs current.** I quote `Physical footprint:`; `footprint -p 95587` agreed to 0.4 MB
   (328.4 M vs 328 MB), so the instrument is cross-checked. Peak was 358.5 M — I did **not** use peak.
5. **My first snapshot script silently collapsed 9 args into one row** (`printf` mis-fed). Caught because the
   PID column contained the whole pid list. Re-measured with a plain loop. Mentioning it because the broken
   run's `fp=n/a` would have read as "vmmap denied" rather than "my harness is wrong".
6. **`ps %cpu` never used** (method rule 3). Load attributed only from `top -l 2` second sample and thread
   counts; I did **not** attribute the load-average numerator per-process — `gc-cpu-vs-session-ceiling` owns that.

**Probe hygiene — everything I spawned and its teardown.** Three `claude --bg` jobs (`6f0c39c9`, `8a95f05e`,
`608a9940`) in a scratchpad dir, `CLAUDE_CONFIG_DIR=~/.claude-secondary`; one fresh interactive pty session
(82160). Torn down with `claude stop <id>` ×3 → **bg process count 0**; `rm -rf jobs/<id>` ×3;
`rm -f ~/.claude/cc-beats/{6f0c39c9,8a95f05e,608a9940}-*.json`; `kill -9` on the 3 orphaned `cc-await-ping`
watchers and on the fg pty chain. **Verified clean:** `jobs/` = the operator's original 3 + `pins.json`;
`agents --json --all` = the operator's 3 background + 2 real interactive; `daemon status` → `not running`;
`ps | grep <uuids>` → 0; `sessions/*.json` → 2 rows, both real interactive sessions. **No live-fleet process
was killed, stopped, or signalled.**

---

## 5. Open questions for synthesis

1. **Does a bg worker in a repo spawn its own MCP child?** (§4.2) This is the one number that flips §3.3 from
   "parity" to "bg is 20% cheaper" or "bg is 20% dearer". One probe fired with `cwd=` the repo settles it.
2. **A1/A2 crux, now with a hazard attached.** The finder handed over `teammateMode:"in-process"`. I found a
   *second, unrelated* in-process flag (`tengu_bg_leftarrow_inprocess`, default true, §3.10). Whoever settles
   the teammate question must not cite one as evidence for the other. The live counter-evidence still stands:
   `--agent-id A10-hostile-reviewer` is a separate OS process at 472 MB RSS **with its own MCP child (18451)**.
3. **Should we adopt CC's `sessions/<pid>.json` instead of our pane registry?** §3.7 shows it self-GCs, is
   PID-keyed, carries `status` + `waitingFor` + `kind:"bg"` free, and — unlike `cc-where` — *already sees*
   paneless workers. The finder's open question #2 (`CLAUDE_CODE_FORCE_SESSION_PERSISTENCE=1`) is the cheap
   experiment; note our own `cc-where` already models an `offbox` kind that fits the same shape (§3.9).
4. **The scheduled-worker `maxConcurrent: default(1)`** (§3.6) belongs to A4, not A3 — but if cloud
   routines are being counted as ceiling relief anywhere in this wave, that default needs checking.
5. **File `cc-await-ping` orphaning as its own defect, separate from #127.** #127 is "dies with exit 144";
   this is the converse — *refuses to die*, 3/3, on a session UUID that has no pane and never will. Both are
   the same root: the wake path is pane-addressed and the arming path is UUID-addressed.
