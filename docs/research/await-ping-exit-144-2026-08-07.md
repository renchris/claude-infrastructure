# `cc-await-ping` exit 144 is an external process-GROUP SIGTERM — not SIGURG, and not a 25-minute reap

**Date:** 2026-08-07 · **Binary:** CC 2.1.220 (`~/.claude-220/…/bin/claude.exe`, a Bun single-file
executable) · **Machine:** Darwin 24.6.0 arm64
**Scope (frozen):** confirm-or-refute the reported ~25-minute death of a `run_in_background`
`cc-await-ping`, with a positive test that names the cause; then land the durable fix so an idle
session's wake path cannot silently expire.
**Investigates:** cc-backlog item `26a9362990cb` ·
**Related:** `docs/research/mechanical-wake-asyncrewake-2026-07-29.md` (the `asyncRewake` path that
would replace the voluntary Bash arm) · `docs/research/wake-on-ping-2026-07-26.md` ·
`hooks/session-continue.sh` § WAKE FLOOR

## Verdict

**The bound is refuted and the signal was misread. No re-arming supervisor is warranted.**

The item's three load-bearing claims each fail against measurement:

1. **"Exit 144 = 128+16 = SIGURG."** No. `144` is the harness's *synthesized sentinel* for "the child
   was killed by SIGTERM". The arithmetic agreement with macOS signal 16 is a coincidence — and a
   costly one, because SIGURG's default disposition is **ignore**, so a bash script cannot die from it
   and the premise was self-refuting from the start.
2. **"It dies at ~25 min."** No. Measured 2026-08-07 19:54 PDT: **9 live real watchers on this
   machine, aged 49 min to 2h51m** (median ~1h42m) — every one of them past the claimed bound, and
   the oldest by nearly 7×. A controlled arm fired for this investigation was still healthy at
   **27m45s** when it was retired deliberately. There is no ~25-minute expiry.
3. **"Most likely the harness's own background-task reaping."** No — excluded from the harness's own
   source, twice over (§3). Every harness-initiated kill reports a *different* code by construction.

What 144 actually means: **something outside the harness SIGTERMed the task's process group.** The
repo contains no process-group kill site, so those two historical deaths came from outside these
scripts. Their specific sender is **not recoverable** — see §5, which says so rather than guessing.

## 1. What 144 is (harness source)

The class that owns a spawned shell resolves its result through two disjoint paths:

```js
// the child's real exit event: (code, signal)
#E(e,t){ let r = e!==null&&e!==void 0 ? e : t==="SIGTERM" ? 144 : 1; this.#T(r) }

// every harness-initiated kill
#A(e){ this.#e="killed"; let t=this.#o?.pid;
       if(this.#T(e??wio), !t||t<=1) return …;      // ← resolves FIRST, with its OWN code
       let r=BDt(t,"SIGTERM"); …  process.kill(-t,"SIGKILL") … }
#T(e){ if(this.#f) this.#f(e), this.#f=null }        // ← first resolution wins
```

`144` is emitted **only** by `#E`, and only when the child exited with `code===null, signal==="SIGTERM"`.
`#A` (timeout, cap, abort, pressure reap, interrupt) always calls `#T` with its own sentinel *before*
signalling, so its later SIGTERM lands on an already-resolved promise and is discarded.

**Therefore a 144 is proof the SIGTERM came from outside the harness's kill paths.** The same file
shows the sentinel family this belongs to — e.g. `{code:145, stderr:"Command aborted before execution"}` —
confirming the 14x range is synthesized status, not `128+signal`.

## 2. Positive test — reproduced in situ, with a discriminating control

The harness's child is the **zsh wrapper**, not the watcher, so *which process* takes the signal
decides the reported code. Two live background tasks, one signal each:

| Experiment | Target | Harness reported |
|---|---|---|
| A | inner process only (`kill -TERM 9716`) | **143** — zsh's own `128+15` exit status |
| B | whole process group (`kill -TERM -9413`) | **144** — the reported signature ✅ |

An `SA_SIGINFO` recorder in the group captured the sender: `sig=15 si_pid=68962 si_uid=501 si_code=0`
— the killing shell, exactly. The instrument works and would name a real culprit if one recurred.

**Reproduction recipe (30 seconds):** arm any `run_in_background` Bash task, then
`kill -TERM -<pgid>` its group. 144 every time; `kill -TERM <pid>` of the inner process gives 143.

## 3. Why harness reaping is excluded

Both harness reapers were located in the bundle, and neither can produce this:

- **Time cap.** `o.background(u,{capMs: WPd(s)})` where `function WPd(e){ if(e===void 0) return; return
  Bd(process.env.CLAUDE_SUBAGENT_BG_SHELL_MAX_MS)||Ney }` and `e` is the **agentId**. For a
  main-session task `agentId===undefined` ⇒ `capMs` is `undefined` ⇒ **no timer is ever set**. Only
  *subagent*-owned background shells are time-capped. This alone refutes a fixed ~25-minute bound.
- **Memory-pressure reap.** `VPd` registers `process.on("memoryPressure", …)` → `task_local_shell_pressure_reap`,
  and it registers *only* when `agentId===undefined` — i.e. it is the main session's reaper. But it
  reports through `nFs(…,"killed",…)`, whose text is `"<desc>" was stopped`, **not** `failed with exit
  code N`. The operator saw an exit code, so it was not this.

## 4. Two live risks found on the way (neither caused this)

- **The memory-pressure reaper is real and it targets exactly the wake path.** Under macOS memory
  pressure it kills main-session background tasks — and on a box running ~16 concurrent sessions that
  is not hypothetical. Lever if it ever bites: `CLAUDE_CODE_DISABLE_BG_SHELL_PRESSURE_REAP=1`.
  **Not set here, deliberately** — there is no evidence it has fired, and configuring against an
  unobserved cause is how a speculative remedy outlives the bug it imagined.
- **`cc-reaper`'s garbage arm TERMs live processes** (`garbage: 4 candidates, 4 TERMed (REAP)`, several
  times today). `cc-await-ping` is whitelisted, and the arm logged **zero** activity in the incident
  window (07:00–09:00Z 2026-08-07), so it is exonerated here. It also kills a single positive pid, not
  a group, so it cannot produce a 144 at all.

## 5. What is NOT established

The **specific sender** of the two historical group-SIGTERMs. `cc-reaper` logged nothing in that
window, the repo has no group-kill site, and neither death left a record naming a killer. Two
instances, no surviving evidence — so this doc names the *class* of cause (external group TERM) and
stops there. Anyone who sees another 144 should capture the sender directly with the recorder in §2
rather than re-deriving from the exit code, which cannot identify a sender.

Worth noting against the "the session never learns" half of the report: the item's own timeline —
watcher #1 died 00:36, **watcher #2 armed 01:00** — is evidence the session *did* learn and *did*
re-arm. Measured here twice: a task death delivers its completion notification immediately, and
`wake_floor` (`hooks/session-continue.sh`) clears its attempt budget on every Stop that observes the
session armed, so the next unarmed Stop blocks and demands a fresh arm. The recovery loop is intact.

## 6. Correction landed with this doc

`bin/cc-await-ping`'s owner-guard comment asserted, as **verified** fact, that "a legitimate
`run_in_background` arm has its launching shell exit immediately, so a healthy watcher's ppid becomes
1". On CC 2.1.220 that is **false**: 9/9 live watchers have a live `/bin/zsh -c source <snapshot> …`
parent. The guard's *conclusion* (never key liveness on ppid) survives — ppid is simply unreliable in
both directions now — but a stale "(verified)" in the tree is a trap for the next reader, so the
comment records both the original measurement and today's.

## Lesson

**An exit code is a claim about a status word, not about a signal.** Reading `144` as `128+16` produced
a signal name (`SIGURG`) whose own default disposition made the story impossible — and that
contradiction was visible without running anything. When a runtime synthesizes status codes, decode
them against *that runtime's* table before doing arithmetic on them. The same misreading also picked
the wrong suspect: it sent the investigation at "harness reaping" for a value the harness emits only
when something *else* did the killing.
