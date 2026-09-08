# What reaps a live session's background Bash — backlog `95fcadde830e`, population (C)

**THE ANSWER: a macOS `memoryPressure` handler that Claude Code installs per background Bash task,
inside the arming session's own process.** It is not a lifetime cap, not a Stop-hook teardown, and
not turn-boundary reaping — the three hypotheses the row named. All three are refuted below.

The row's population (C) is *"an ALIVE session kills its OWN Bash-tool-armed watcher mid-life and
goes silently deaf"*, measured 2026-08-24T22:08Z on pane 102: SIGTERM at `elapsed=770s` of a
`14400s` budget, `si_pid=7485` verified alive with the right cwd. Every observable in that sentence
is what this mechanism produces by construction.

Read out of the compiled Bun binary, the same technique as
`docs/research/goal-in-handoff-2026-08-08.md` § "The code, read out of the binary". Offsets are for
these builds and will move.

## The code

`~/.claude-220/…/bin/claude.exe` — the arm `VPd` @235581845, installed by the background-bash
launcher `Hft` @235582266:

```js
function VPd(e,t,r,n,o,i){                       // i = agentId
  Zse(i,`bash:${e}`,r);
  let s;
  if(i===void 0 && !_n() && !Z.CLAUDE_CODE_DISABLE_BG_SHELL_PRESSURE_REAP){
    let a=()=>{
      let l=r.get(e);
      if(l?.status!=="running"||l.notified||Date.now()-ON()<Fey||yEi()||_We(r.all()))return;
      be("task_local_shell_pressure_reap"),
      nFs(e,t,"killed",void 0,r,n,o,i),          // ← the kill
      l$e(e,r)
    };
    process.on("memoryPressure",a); s=()=>process.off("memoryPressure",a)
  }
  return ()=>{ s?.(), i6(i,`bash:${e}`,r) }
}
…
let p = a!=="monitor" ? VPd(u,n,l,i,a,s) : void 0;   // a = kind
```

The kill runs `#A()` → `BDt(pid,"SIGTERM")` → `process.kill(-pid,"SIGTERM")`: a **process-group
SIGTERM issued by the arming `claude` process itself**, which is exactly the `sig=15
si_pid=<the live session>` the row recorded.

`kind==="monitor"` tasks never get the handler at all.

### The live build widened it

`~/.claude-260/…/bin/claude.exe`, function `i7n` **@164630427** — same body, two deltas.

⚠️ Minified names are reused across unrelated functions: `grep -aob 'function i7n'` returns **two**
offsets in this build, and the first (@160313919) is a keybindings file-watcher. Take the second.
Verify any offset by reading its first 200 bytes before citing it.

```js
if(!ke() && !a.CLAUDE_CODE_DISABLE_BG_SHELL_PRESSURE_REAP){    // ← agentId guard GONE
  …Xut(e,n,"killed",void 0,r,o,d,f,void 0,void 0,"memory_pressure")…   // ← reason now carried
```

The `agentId===void 0` scope guard is **removed in 2.1.260**, so the reaper now covers subagent
background shells too, and the kill carries the literal reason `"memory_pressure"`.

| | 2.1.220 (the build the events were measured on) | 2.1.260 (live) |
| --- | --- | --- |
| pressure reaper | present, main-session tasks only | present, **all** non-`monitor` tasks |
| `CLAUDE_CODE_DISABLE_BG_SHELL_PRESSURE_REAP` | honoured | honoured |
| `background()` lifetime cap | `capMs: WPd(agentId)` | **removed** |
| output-file swap watchdog | absent | present (see below) |

## The three named hypotheses, refuted

1. **A task-registry lifetime cap.** In 2.1.220 a cap does exist, but
   `WPd(e){ if(e===void 0) return; return Bd(process.env.CLAUDE_SUBAGENT_BG_SHELL_MAX_MS)||Ney }`
   returns `undefined` when `agentId` is undefined — i.e. **a main-session background Bash gets no
   cap at all**, and the env var is named for subagents. In 2.1.260 `background()` takes no `capMs`
   and the whole cap is gone. Sibling row `9046fbbdc74e` reached the same verdict from the other
   side (three of four identical watchers ran the full 14400 s); this is the mechanism behind it.
2. **A Stop-hook teardown that does not restore.** The Stop-path deferral
   (`goal-in-handoff-2026-08-08.md`) removes and re-adds the *goal hook*, in a `finally`. It never
   touches the task. It cannot kill a watcher.
3. **Turn-boundary reaping.** No turn-boundary path signals a `backgrounded` task. `Kdt()` — the
   only sweep over live shell commands — is guarded `if(e.status==="running")`, which a backgrounded
   task is not.

**Why the elapsed bands never overlap and never will.** Elapsed-at-death is simply *time until the
next `memoryPressure` event that clears the guards*. There is no number to find. 770 s and 7516 s
are the same mechanism sampled twice, and the guards (`l.notified`, the `Date.now()-ON()<Fey`
recency floor, `yEi()`, `_We(r.all())`) are what select **one** of several concurrent watchers while
its siblings run their full term.

## Reproduced in-session, with an A/B

2.1.260 carries a second (C)-shaped killer worth recording because it is deterministic and so is
testable, where memory pressure is not: `qHe#E()` (@161106853) polls every **5 s** (`ngr=5000`) for
any task with `stdoutToFile`, and its guard is `(this.#e==="running"||this.#e==="backgrounded")` —
unlike the timeout and abort arms, which `background()` clears via `#k()`. It calls `gSt` → `AY`,
which *validates* the task's own `.output` file, and any `taskOutputSwapRefused` rethrow lands in
`#b(yZ)` — the same group SIGTERM.

Run on this session (2.1.260), pid 54124, both tasks armed with `run_in_background`:

| | Action on the task's `.output` file | Result |
| --- | --- | --- |
| control | none | ran; ticking; `nlink=1` |
| swap | replace at same path, new inode | **survives** (≥16 s) — the identity check is TOCTOU-scoped, not "same file since start" |
| **absence** | `rm` the file | **survives** (≥12 s) — `gSt` maps ENOENT to size 0 |
| **validation failure** | `ln` it (nlink 1→2) | **process group dead in ~3 s**, harness reported `status: killed` |

So the trigger is the file failing *validation*, never merely being *absent* — which retires the
obvious reading of the harness's own hint, `"another Claude Code process in the same project deleted
it during startup cleanup"`. A delete is survivable; a hardlink, a symlink swap, a `chmod 000`, or a
directory swap is not (`b()` call sites: `not a regular nlink-1 file`, `output symlink was
re-pointed`, `output file identity changed`, `open refused a swapped leaf (…)`, `tasks dir moved or
linked`, `output no longer measurable (EACCES|EPERM)`). The size arm is **5 GB** (`fNe`), so it is
irrelevant to a watcher.

The tasks dir is `<tmp-root>/<project-slug>/<session-uuid>/tasks/` — session-scoped, under a
**shared project root**. `scripts/scratchpad-reaper.sh` and `bin/cc-reaper` both operate on that
tree; neither hardlinks or swaps, and deletion is survivable, so **no fleet actor is presently
implicated**. Stated so the next session does not re-suspect them.

## A discriminator, newly verified

Both shapes were produced in this session and they are distinguishable at the harness surface:

| Observation | Means |
| --- | --- |
| `status: killed` | **the harness itself** killed it — pressure reaper, swap watchdog, TaskStop |
| exit code `144` | an **external** process-group TERM (verified: `kill -TERM -<pgid>` from a sibling shell) |

This confirms the header claim at `bin/cc-await-ping:104-110` from the other direction, and it is the
cheapest first read on any future corpse: a live-session self-kill reads `killed`, never `144`.

## Incidence

Over the 4 account transcript roots, `*.jsonl` modified in the last 30 days (denominator **6,043**;
positive control: this session's own transcript is in the returned set):

- **345** carry a killed background-task notification
- of those, **42** follow a `TaskStop`/`KillShell` the session issued
- **303 do not** — the session never asked
- **294** of those 303 were sessions arming a `cc-await-ping` watcher

⚠️ **303 is an upper bound on (C), not a measurement of it.** A recycle-exit teardown (population B)
also lands in "did not ask", and the notification records no reason, so the transcript cannot
separate them. What the number does establish is scale: involuntary background-task death touches
~5% of all sessions in a month, and it lands on the wake path in 97% of those.

## The cure, and why it is not taken here

`CLAUDE_CODE_DISABLE_BG_SHELL_PRESSURE_REAP` is read by both builds and removes the handler
outright. It is a one-line env change and it would end population (C).

It is **not** applied by this row, because it trades away a memory-relief mechanism for the whole
box — 51 live `claude` processes on 64 GB at the time of writing — and that is a value call with a
real downside, so it fails Follow-On Gate F1. Filed as a decision packet rather than driven. The
argument for taking it: what the reaper reclaims is background *bash* tasks, ~10 MB each for a
watcher, while the sessions themselves hold the actual memory — so the relief is a rounding error
against the cost of a permanently deaf session.

## Limits

- The 2026-08-24 and 2026-08-26 events cannot be attributed to a specific pressure event now: the
  store is reboot-ephemeral and the kill reason was not carried in 2.1.220.
- `Fey`/`hYo` (the recency floor), `yEi()` and `The()` were not resolved to values; they affect
  *which* task a pressure event selects, not *whether* the mechanism is the cause.
- The reproduction proves the swap watchdog directly. The pressure reaper is established from the
  code plus the elimination of every alternative, not from a triggered `memoryPressure` event.
