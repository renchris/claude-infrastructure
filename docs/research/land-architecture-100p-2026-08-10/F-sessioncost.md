# F-sessioncost — what a land COSTS the landing session under contention

**Date:** 2026-08-10 · **Repo:** `~/Development/claude-infrastructure` (read-only pass) ·
**Evidence:** code at file:line · `~/.claude/land.log` (2,929 rows, 2026-07-11→2026-08-10) ·
live process/lock sampling at 08:29–08:30Z.

---

## VERDICT (four answers, up front)

| Q | Answer |
|---|---|
| (a) What `/ship` does on a busy lock | **Blocks in-process.** `land-lock.sh:129-138` is a `until try_acquire; do sleep 2; done` foreground poll, bounded by `LAND_LOCK_WAIT` (default **3600s**), then `exit 75`. There is **no waiter, no queue, no FIFO**. `commands/ship.md` (both global and project-local) has **no retry loop, no waiter-arm, no end-turn instruction** — the model just holds the tool call. |
| (b) Economics of the wait | The **TURN** is held open; the **SESSION** is not blocked (a `run_in_background` shell frees it); context burn is small but real (~1 queue line / 30s + one gate transcript per round). **Nothing forces the session to hold for the land** — no Stop hook blocks on 📦. Three hooks *pressure* it, none *executes* it. |
| (c) Close-time auto-ship chain | **No hook fires `/ship`.** Zero of the 12 registered Stop hooks and zero of the 26 launchd jobs land. Auto-ship is 100% model-driven prose (CLAUDE.md § "📦 outside reso auto-`/ship`s"). On lock-busy every close hook is **blind** — they read git refs only, so the ledger says 📦 while a land is mid-flight, and there is **no dedup guard in ship-land.sh** against firing a second one. |
| (d) Enqueue-and-close | **NO such path exists today.** `stranded-sweep.sh` detects and prints recipes, never lands. `desk-land.sh` is synchronous by design. `cc-queue` is the blocked-agent board, not a land queue. `cc-offload land` is cloud-branch reconcile. The *only* asynchronous rail is the generic backlog→dispatcher loop (`cc-backlog add` → `com.claude.dispatcher`, ≤300s), which costs a whole session's model quota to perform a mechanical push and has no land-shaped brief composer. |

---

## §1 — The itemized cost model

### 1.1 The three costs are NOT the same cost

| Cost | Bound | Who pays | Mechanism |
|---|---|---|---|
| **TURN held open** | Harness Bash-tool timeout (default 120s; 600s max) — **shorter than the wait bound (3600s) by 6×** | the turn | A foreground `scripts/ship-land.sh` under real contention **cannot finish inside a foreground tool call.** In-repo corroboration of the 2-min default: `docs/research/cmux-external-control-2026-07-31.md:387` ("hung until killed at the 2 min tool timeout"). This is why the operator saw *"3 shells still running"* — the only workable shape is `run_in_background`. |
| **SESSION blocked** | zero, if backgrounded | nobody | A `run_in_background` land returns the turn immediately; its completion notification re-enters the session later. Live proof: pid 82031 runs with **PPID 1** while its session (`8a41189c`, cwd `.worktrees/wt-bc50117059ac`) is alive and idle. |
| **PANE occupied** | until the land's process group dies | the pane | The land is a descendant of the harness. `docs/research/await-ping-exit-144-2026-08-07.md:43-46` quotes the harness source: every harness-initiated kill does `process.kill(-t,"SIGKILL")` on the **process group**. `scripts/handoff-fire.sh:1303-1311` records the measured consequence: *"nohup+disown is NOT enough … a nohup'd child shares that pgid, so the watcher dies instantly: 0-byte log, no error"* — only `setsid`/`start_new_session` survives. **A backgrounded land is therefore killable by the very `/exit` that a recycle types.** |

### 1.2 Wall-clock: the dominant term is NOT lock wait

`land.log` measured, successful-ship episodes (grouped per repo+branch, ≤30 min gap), **August 2026, n=368**:

| Metric | p50 | p90 | p99 | max |
|---|---|---|---|---|
| Episode span (first land-lock call → land) | **106 s** | **991 s** | **4,677 s** | **6,107 s** (1h42m) |
| Sum of logged lock **wait** across the episode | **0 s** | 1 s | — | 300 s |
| land-lock invocations per episode ("rounds") | 2 | 5 | — | 24 |

**367 of 368 successful August ships took ≥2 land-lock invocations.** The extra invocations are `exit 42` — the CAS stale-gate signal (`scripts/ship-land.sh:2364-2367`): a sibling landed mid-gate, the lock is released, and the outer loop **re-runs the unlocked gate**. Cost per invalidation ≈ one full gate. Today's worst: `m3-fleet-footprint` 6 rounds / **4,521 s**; `goal-default-handoff` 9 rounds / 2,371 s; `scale-150` 10 rounds / 2,045 s.

**Conclusion: contention bills the session as gate re-runs (livelock-by-invalidation), not as lock queueing.** The 1h8m turn in the operator's example is the signature of round churn, not of the 3600s wait bound.

### 1.3 …but `land.log` systematically under-reports waiting

`land-lock.sh:144-147` logs **only in the `release` EXIT trap** (plus the timeout path at :133). An in-progress wait has no row. Measured live at 08:30:02Z:

- `/tmp/land-lock-3cca03ed6835/lock.d` mtime **01:27:34 PDT** = held **2m28s** by `wt-bc50117059ac`, pid **82031**.
- pid 82031 `etime` = **20m01s** ⇒ **it spent ~17m33s in the acquire poll loop before acquiring.**
- That 17m33s is **15× larger than the largest wait `land.log` recorded for all of today (70 s)** and was invisible to the log at the moment it was happening.

⇒ Every wait percentile in §1.2 is **survivor-biased**. Treat `wait_p95 = 3600` (all-time) as the honest tail and `wait_p50 = 95s` (all-time, 384 non-zero waits) as the honest middle; the August figures describe the lands that *got through*.

### 1.4 Context burn while queued

| Source | Rate | file:line |
|---|---|---|
| `→ land-lock: queued behind <branch> (pid N) — Ns…` | **1 line / 30 s** (~90 B) → ~120 lines / 3600 s wait | `scripts/land-lock.sh:136` |
| Full gate transcript | **once per round** (shellcheck + `bash -n` + py_compile + 2 ratchets + ≤120 s smoke) | `scripts/ship-land.sh:981-1470` |
| Acquire/release banners | 1 each | `scripts/land-lock.sh:150-152` |

Foreground ⇒ all of it lands in the `tool_result`. Backgrounded ⇒ paid only on `BashOutput` read. **The waiting itself is cheap; the round churn is what is expensive**, because each round re-emits a whole gate.

### 1.5 Exit-code costs the session must distinguish

`.claude/commands/ship.md:106-108` + `scripts/desk-land.sh:48-63`: `0` landed · `2` dirty · `3` escalation-PARK · `4` shared-checkout · `5` rebase-conflict · `6` gate-red · `7` non-ff · `8` verify-fail · `9` GATE-KILLED · **`75` LOCK-STARVED**. `9` and `75` are statements about the **machine** ⇒ retryable; everything else is a finding ⇒ never blind-retry.

**All 19 `exit 75` events in 2,929 rows are from a single day: 2026-07-26** (v1 era, 3600–3601 s waits). Zero since v2. `.claude/commands/ship.md:108` claims the v2 hold is "84-302s across 230 successful lands with 0s wait" — §1.3 above **refutes the "0s wait" half** as a live claim.

---

## §2 — Waiter mechanism (there is no land waiter)

Full sweep of `bin/ hooks/ scripts/ commands/` for `waiter|await|cc-await|notify`:

| Component | file:line | Is it a land waiter? |
|---|---|---|
| `land-lock.sh` acquire loop | `scripts/land-lock.sh:127-138` | **This IS the wait** — in-process, 2 s poll, no queue file, no fairness. The lock dir holds only `pid`/`lstart`/`branch` (`:84-90`), so **queue depth and position are not observable** — "queued behind three peer sessions" cannot be read from the lock. |
| `bin/cc-await-ping` | — | Waits for **inbox mail**, not a lock. Unrelated to landing. |
| `bin/cc-wait` | `bin/cc-wait:1-41` | The durable wait-*contract* primitive (waiter/waitee/deadline/on-timeout, refuses a deadline-less wait at `:109-110`). **Never wired to a land.** |
| `scripts/handoff-fire.sh --notify-back` + `cc-await-ping` | `docs/research/phase-execution-locus-2026-08-07.md:43-47` | Session-completion loop, not a land loop. |
| `scripts/wait-contract-lint.sh`, `scripts/wait-safety-gate.sh` | — | Lint/guard over `cc-wait` contracts. No land coupling. |

**Nothing anywhere arms a waiter on the landing lock.** The operator's *"Waiter armed for when it clears"* describes a **hand-rolled** arrangement (a backgrounded shell plus, at most, a `cc-await-ping` armed for unrelated inbox mail) — it is not a repo mechanism, and no code guarantees it fires or that the land is re-attempted.

### 2.1 The nearest thing to a documented recipe — and it is unsafe

`cc-backlog` item `3c6bf04ba842` (live, `blocked`) prescribes verbatim:

```
LAND_LOCK_WAIT=14400 nohup bash -c 'bash scripts/ship-land.sh > /tmp/sl-3c6b.log 2>&1; echo $? > /tmp/sl-3c6b.rc' &
```

Two defects: (i) **`nohup` is exactly what `scripts/handoff-fire.sh:1303-1311` measured as insufficient** against the harness group-SIGKILL; (ii) a 4× `LAND_LOCK_WAIT` extends the un-logged blind window of §1.3 to 4 hours. The item also records the failure this recipe exists for: *"2 further attempts died rc=75 = land-lock queue timeout, NOT gate-red."*

---

## §3 — The close-time auto-ship chain

**Registered Stop hooks** (identical in `~/.claude/settings.json` and `~/.claude-tertiary/settings.json`): `notify.sh complete` · `cache-expiry-tracker` · `teammate-checkpoint` · `session-continue` · `anti-deference-nudge` · `completion-assert` · `dispatch-assert` · `boundary-handoff` · `operator-readout` · `session-beat stop` · `goal-inert-watch` · `cc-permission-beacon clear`. **None runs `ship-land.sh`.** Launchd (26 jobs in `launchd/`) — grep for `ship-land|desk-land|land-lock` returns **zero**.

| Hook | What it does on 📦 | On lock-busy |
|---|---|---|
| `scripts/wrap-ledger.sh:494-495` | `UNLANDED=1 ⇒ RUNG=📦`, readout `"/ship to land it (else lost)"`. `UNLANDED` = `git rev-list --count TRUNK..HEAD > 0 ∨ git cherry '+'` (`:194-201`) | **Blind.** A land mid-flight has not moved the ref, so the ledger reads 📦 exactly as if nothing were running. |
| `hooks/completion-assert.sh:358-360` | On a done-assertion, `contra=1`, `"N commit(s) committed-but-unlanded (/ship to land)"` ⇒ **blocks the close** | Blind — same ref read. A session whose land is queued **cannot honestly assert done**, and gets convicted if it tries. |
| `hooks/anti-deference-nudge.sh:203, 258-263, 317` | `drivable = clean ∧ unlanded` ⇒ a "say the word and I'll ship" close **fires** as deference; `"Ship/land of clean committed work is DRIVABLE — /ship it, don't park it."` | Blind. Pressures a **second** `/ship`. |
| `hooks/operator-readout.sh:18, 433-435` | Fire predicate includes `RUNG=📦`; renders `"📦 parked — N commit(s) on <branch> unlanded (<shas>) → /ship"` | Blind. |
| `hooks/session-continue.sh:585` (mechanical 🔧) | Fires **only** on *uncommitted files this session wrote* — **not** on unlanded commits | Does **not** force a hold for a land. |

**Two consequences.**

1. **Nothing mechanically holds the turn for the land.** The hold is entirely the model obeying CLAUDE.md's *"📦 outside reso auto-`/ship`s, then re-reads the ledger — the turn closes on the landed state."*
2. **Double-fire hazard is unguarded.** `scripts/ship-land.sh` has **no singleton/in-flight check** (grep: no `pgrep`, no lockfile-of-its-own, no "already landing"). Ledger 📦 + nudge pressure + a backgrounded land already running ⇒ a second `ship-land.sh` on the **same worktree**, i.e. two concurrent `git rebase` on one index.

### 3.1 One further per-close tax

`hooks/session-continue.sh:444-462` — the **WAKE FLOOR** `decision:"block"`s a close when no `cc-await-ping` is armed. So a session parking a backgrounded land also pays a forced extra turn to arm an inbox watcher (bounded by `CC_WAKE_FLOOR_MAX` / `CC_WAKE_FLOOR_TTL_S`, `:335-338`), unless it is an assignee or is marked terminating (`:377-400`).

---

## §4 — Enqueue-and-close verdict: **does not exist; nothing "guarantees" a land**

| Candidate | Verdict | Evidence |
|---|---|---|
| `scripts/stranded-sweep.sh` | **Detector only.** Prints `git cherry-pick` + "then gate … and land via scripts/land-lock.sh" as *prose recipes*; exit 1 = REVIEW | `:104-113`, `:120-128` |
| `scripts/desk-land.sh` | **Synchronous by design**, and says so: *"WHY SYNCHRONOUS … deterministic + zero model-quota cost … fewer failure modes than a fired session"* | `:39-46` |
| `bin/cc-queue` | Not a land queue — the operator's blocked-agent board over the permission beacon | `bin/cc-queue:2-24` |
| `bin/cc-offload land` | Cloud-branch reconcile (`scripts/cloud-reconcile.sh`), unrelated to the local lock | `bin/cc-offload:9,24` |
| `scripts/postland-verify.sh` queue | **Post**-land: `ship-land.sh:2252` writes the landed head to `$pdir/queue` for the verifier. Consumes a land, never produces one | `scripts/ship-land.sh:2243-2252` |
| `bin/cc-discover` | Emits no unlanded/stranded work candidate at all (grep `unlanded|stranded|ship|land` ⇒ 0 hits) | — |
| **`cc-backlog add` → `com.claude.dispatcher`** | **The only asynchronous rail that exists.** Live (`launchctl list`), `StartInterval 300`, write-kicked; fires a session per non-blocked open item | `launchd/com.claude.dispatcher.plist`, `bin/cc-dispatch:47-50` |

**What stops the dispatcher rail being the default:**
1. **No land-shaped brief composer.** The only composer is backlog-item-shaped (`bin/cc-dispatch:1088-1097`, per `docs/research/phase-execution-locus-2026-08-07.md:50-52`).
2. **It spends a whole model session** on a purely mechanical push — the exact cost `desk-land.sh:39-46` rejected.
3. **It is not a guarantee.** A dispatched session inherits the same lock, the same round churn, and can itself die; nothing re-queues on its failure.
4. **The observed practice is the opposite**: real blocked lands are parked as `needs:` prose telling a *future reader* to run `ship-land.sh` by hand (item `3c6bf04ba842`; item `6cab0ab3cb2f`: *"just run 'cd … && ./scripts/ship-land.sh'"*). That is a note, not an enqueue.

---

## §5 — Task-board **#127** (`cc-await-ping` exit 144 — "the armed wake path silently disarms")

Board id confirmed: `docs/research/phase-execution-locus-2026-08-07.md:58` — *"Already tracked as task #54 (make the wake path MECHANICAL) and **#127 (`cc-await-ping` exit 144)**."*

**Verdict: SPLIT — the event is CONFIRMED and live; the causal story and the word "silently" are REFUTED; the sender is UNVERIFIABLE.**

| Sub-claim | Verdict | Evidence |
|---|---|---|
| 144 happens, and it kills the armed wake path | **CONFIRMED, and current** | `cc-backlog` item `b38279c10c55` (open): *"3 fresh exit-144s in one session (2026-08-09, tasks bh5b43qkt/bpdam2zbc/bgk1gm5kf), each after the arming line and nothing else"* — i.e. **yesterday**. |
| 144 = "dies" from `128+16 ⇒ SIGURG`, or a ~25-min expiry | **REFUTED** | `docs/research/await-ping-exit-144-2026-08-07.md:15-31`: 144 is the harness's **synthesized sentinel** for "child killed by SIGTERM" (source quoted at `:38-46`); SIGURG's default disposition is *ignore*, so bash cannot die from it; 9 live watchers measured aged 49 min–2h51m. Also encoded in the subject: `bin/cc-await-ping:38-47`, `:243-246` (measured `kill -TERM <pid>` → 143; `kill -TERM -<pgid>` → **144**). |
| **"silently disarms"** | **REFUTED as of `e186b255`** | `bin/cc-await-ping:285-294` `_sig_verdict` traps TERM/HUP/INT and, before exiting `128+sig`: (1) `_unbeat` clears the `.watching` marker so nothing advertises a dead wake path (`:227`, `:287`); (2) `_wake_down_notice` (`:274-283`) appends a **`WAKE-PATH-DOWN`** line straight into the watched inbox, deliberately unfiltered by the drain's noise grep (`:271-272`); (3) stderr carries `verdict=killed signal=SIG… uuid=…` (`:289`). `hooks/mailbox-drain.sh` then surfaces it as `📬 peer mail` + an operator-visible `systemMessage` (`:261-265`). |
| "the session never learns / needs a re-arming supervisor" | **REFUTED** | `await-ping-exit-144-2026-08-07.md:99-105`: the item's own timeline shows watcher #1 died 00:36, **watcher #2 armed 01:00**; `hooks/session-continue.sh` WAKE FLOOR blocks the next unarmed Stop (`:444-462`). Doc verdict line: *"No re-arming supervisor is warranted."* |
| The **sender** of the group-SIGTERM | **UNVERIFIABLE** (open) | `await-ping-exit-144-2026-08-07.md:88-93` names two untested suspects (macOS bg-shell pressure reaper; `cc-reaper`'s garbage arm — exonerated for the specific window) and `:96-99` states the sender is not recoverable from an exit code. Tracked as `b38279c10c55`. |

**⚠ Caveat the board should carry:** the guard that makes 144 loud is itself **red on trunk under full-suite order** — `cc-backlog` item `087db20c3a24`: `tests/cc-await-ping.bats` *"G10: HUP is handled the same way"* fails only in full-suite order (10/10 pass filtered; test-order pollution, subject exonerated by A/B). So the "not silent" property is **landed but not regression-protected**.

**Relevance to lands:** 144 is a *pgid* death. The same harness kill path (`process.kill(-t,"SIGKILL")`, doc `:43-46`) is what a backgrounded `ship-land.sh` sits behind. **A land backgrounded in the harness is exposed to exactly the failure #127 documents** — and unlike `cc-await-ping`, `ship-land.sh` installs **no signal trap** (`docs/research/LANDING_GATE_ROOT_CAUSE_2026-07-26.md:21`: *"ship-land.sh installs no signal trap … so it can never record its own signal death"*), so a killed land is **genuinely silent**.

---

## §6 — Adversarial pass (three things I initially assumed and had to check)

1. **"Queued behind three peers" is not a readable state.** The lock is a bare `mkdir` mutex with **no FIFO fairness** (`.claude/commands/ship.md:108`, `scripts/land-lock.sh:95-125`) and stores only one holder's `pid`/`lstart`/`branch`. Depth and position are unobservable; a session reporting "three peers" inferred it from `ps`, not from the lock. Corollary: **wait time is not proportional to depth** — an unlucky waiter can starve while holders rotate.
2. **The in-lock invariant holds in KIND but not in TIME.** v2's rule is "nothing heavy may EVER enter the lock" (`scripts/ship-land.sh:978-982`, structurally enforced via `IN_LAND_LOCK=1`). Live at 08:29Z the holder's in-lock child was `scripts/pipefail-sigpipe-lint.sh` — correct, statics-only, the rounds-exhausted fallback (`ship-land.sh:2376`) — but running at **nice 5 / PRI 31 under load 34.69 on 10 cores (3.47/core)**. Statics-only bounds the *class* of work, not its *wall time* under fleet load. The published "84-302s" hold ceiling is a **bench figure, not a band figure**.
3. **`land-lock.sh <not-a-command>` takes the machine-wide mutex.** 23 `land.log` rows carry `exit 127` — an agent guessing a subcommand (observed live this session: another pane running `bash land-lock.sh status`). Harmless in hold (`hold_s=0` for all 23) but **one of them waited 2,777 s** for the mutex to run a command that does not exist. The documented pure read is `--print-lock-dir` (`scripts/land-lock.sh:54-59`); `status` is not a verb and is silently treated as the payload to serialize.

---

## §7 — Uncertainties, stated

- **Harness Bash-tool timeout numbers** (120 s default / 600 s max) are the only figures here **not** sourced from this repo; in-repo corroboration for the 2-min default is `docs/research/cmux-external-control-2026-07-31.md:387`. If the real ceiling is higher, §1.1's "a foreground land cannot finish" weakens to "usually cannot".
- **Episode grouping in §1.2** (same repo+branch, ≤30 min gap) can merge two separate `/ship` runs into one "episode", inflating high round counts. Span p50/p90 are robust; the 14/19/20/24-round tail probably contains re-runs.
- **Whether any session has ever used the backlog→dispatcher rail for a land** is unestablished — I found the mechanism and its gaps, no instance of it being used that way.
- **The live 17m33s wait (§1.3)** is one sample. It refutes "0s wait" as universal; it does not establish a rate.
- **Whether a second concurrent `/ship` on one worktree actually corrupts** (vs merely erroring on `index.lock` / "rebase in progress") was **not tested** — the repo is read-only for this pass. What is established is that no guard prevents it being attempted.
