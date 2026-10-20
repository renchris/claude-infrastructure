# B2: a bounded reconciler pass, with slow children off the serial path

Implementation-ready design. Read-only research, 2026-10-20, about 17:30-18:40Z.

**Code citations.** They are to this worktree at `28b25a119`. For every file this design touches it is identical to `main` `6fdf87eca`: `git diff --stat HEAD main -- scripts/limit-recover/ scripts/lib/capacity-admit.sh bin/claude-accounts` => empty.

**Labels.**
- **M** = measured; the command is named.
- **E** = estimated; the method is named.
- **H** = hypothesis.

**Inputs read.**
- `REPORT.md` §1-§8.
- Axis 01 (G4/G5/G7/G9a), axis 02 §4.1 and its skeptic L2, axis 05 G2/G6 and L7, axis 06 §5 and L5-L7.
- `.claude/rules/agent-operating-lessons*.md`.

The lessons applied here:
- "Requested rate ≠ delivered rate" (`:34`): count the passes, never trust a configured cadence.
- "Green in both arms" (`:62`): every new rule gets a mutant.
- "Verify a cure under its load" (`:83`).
- "Freshness is subject-relative" (`:76`).

## 0. Verdict

**BUILD. Conviction 70%.**

**What changed since B2 was ranked.** With the rail at priority 31 (A1, `07ce89a99`) and the incremental census (`6841626b4`), a quiet pass is now about 1 s (§1.1).

**What remains.**
- A child can outlive its own bound by minutes. The post-kill wait in `subprocess.run` is unbounded. Measured at priority 31: four `ps` abstains held their passes 98-193 s against a 90 s budget.
- A cohort pass chains its children serially, with no ceiling: k × (probe + mint + spawn) + 2 × `--place` + pages.
- Nothing records per-phase time. So B3's guarantee has no measured `P_max` to stand on.

**What B2 delivers.**
- A real wall bound on every child.
- Registered-only reaping. This is a precondition for any async child, because today's `waitpid(-1)` turns a refusal into an admit (§3 F2, measured).
- `--place`, the capacity probe and pages off the serial path.
- A pass budget for deferrable work.
- One `recon/passes.jsonl` row per pass, with its phases.

**What B2 does not do.**
- It builds no second decision loop. Async workers never decide and never write a record.
- It builds no fallback placement ranking. That would conflict with §C5 and Decision 3 (§3 F4).
- It does not touch the census walk or record writes. Those belong to 457c166ed9d6 (§8).

## 1. What the pass costs today (the measurement the brief asked for)

### 1.1 Pass cadence since the priority-31 reload (M)

`recon/band.log` gets one line per pass, written by `_band` right after `run_pass` (`__main__.py:1832-1837`). Consecutive lines from one pid therefore measure the pass plus the inter-pass wait.

While these readings were taken, 4 records were open, all `PRE-MOVE/PARKED-REBOOT` (M: python count of `recon/sessions/*.json` with `terminal` null). The readout said `2 cohorts open · 0 moving · 4 waiting`. So the wait was `ACTIVE_S` = 5 s, polled at 1 s (`__main__.py:1846-1847`, `:1768-1780`).

Command: `python3 -I /tmp/b2meas/gaps.py ~/.reso/limit-recover/recon/band.log`, plus the per-pid split.

| Daemon | Era | Gaps | p50 | p90 | p99 | max |
|---|---|---|---|---|---|---|
| pid 4459 | 07:23-16:04Z: priority 31, before `6841626b4` | 2790 | 11 s | 13 s | 20 s | 193 s |
| pid 5233 | 16:04Z onward: priority 31 plus incremental census | 991 | 6 s | 6 s | 12 s | 36 s |

E (gap − 5 s wait): a quiet pass today is about 1 s at p50, about 7 s at p99 and about 31 s at worst. Load at the time of reading was 258.60 / 272.73 / 149.33 over three reads (`sysctl -n vm.loadavg`, M).

### 1.2 The tail is a child that outlives its own bound (M)

The four largest pid-4459 gaps end on the same second as the four `abstain` events of that era:

| band.log line | Gap | `recon/events.jsonl` abstain detail (same t) | ps phase (E: gap − 5 s) | Post-kill wait (E: phase − first-try bound) |
|---|---|---|---|---|
| 67, t=1792482003 | 193 s | `/bin/ps pid=,ppid=,stat=,lstart=,args=: timed out at 32s; ps budget spent` | ≈188 s | ≈156 s |
| 1215, t=1792494382 | 119 s | `… timed out at 30s; ps budget spent` | ≈114 s | ≈84 s |
| 312, t=1792485009 | 115 s | `… timed out at 33s; ps budget spent` | ≈110 s | ≈77 s |
| 272, t=1792484400 | 98 s | `… timed out at 37s; ps budget spent` | ≈93 s | ≈56 s |

**Reading "ps budget spent".** The second try was never started because less than `PS_MIN_CALL_S` (5 s) of the 90 s `PS_BUDGET_S` was left (`observe.py:83-87`, `:136-140`). So the first try's timeout plus its kill took the whole budget and more.

**The mechanism (M).** In CPython 3.9.6, which the plist pins as `/usr/bin/python3` (`com.reso.lr-reconciler.plist:23-42`), `subprocess.run` handles a timeout like this:

```
except TimeoutExpired as exc:
    process.kill()
    ...
    process.wait()
    raise
```

The `process.wait()` has no timeout (M: `/usr/bin/python3 -I -c 'import subprocess,inspect; …getsource(subprocess.run)…'`). A `ps` that is SIGKILLed while stuck in the kernel is not reaped until the kernel lets go. `bin/claude-accounts:822-830` records the same fault at 1,226 s at load 330, and already works around it with a thread joined at `PS_JOIN_S`.

**This answers REPORT §3.3's open question.** Priority 31 does not escape the kernel-side `ps` stall: every row above reads `pri=31 … ok` in `band.log`.

**Red-control reproduction (M).** `/tmp/b2meas/killwait.py` patches `subprocess.Popen` with a child that ignores the kill for 3 s.
- Today's `clock.run_bounded(…, timeout=0.2)` returned after **6.29 s**.
- The fake waits twice: once in `run`'s handler and once in `Popen.__exit__`. A real Popen would wait about 3.2 s. Either way the call is red.

### 1.3 The longest step of the running daemon (M, plus H)

`recon/heartbeat` for pid 5233 reads: `max_step_gap_s` 30.28, `max_step_gap_bound_s` 34.23, `max_step_gap_at` 1792515500 (16:58:20Z).
- No `place` or probe event exists after 12:01Z (`events.jsonl` last row t=1792497667).
- So the 30 s child was a census `ps` read. H: the bound matches `ps_bound()` at load1 ≈ 71 (`observe.py:90-100`).

A slow-but-finishing `ps` at priority 31 is therefore real. That is why B2 does **not** shorten the `ps` bounds (§4 S1.a).

### 1.4 Child latencies at priority 31, now

| Child | Priority 31 | Source |
|---|---|---|
| census `ps -axww … args` | 0.51-0.61 s at load 258-273; 0.16 s at load 149 | M: `/usr/bin/python3` timing, 3 + 1 samples, my shell at PRI 31 (`ps -o pri -p $$` => 31) |
| census `ps -axo pid=,tty=` | 0.94-1.28 s at load 258-273; 0.26 s at load 149 | M, same |
| one merged ps (§4 S1.d) | 0.41 s at load 149 (vs 0.42 s for the two calls) | M: `/tmp/b2meas/merged_ps.py` |
| `kitten @ ls --match id:38` | 0.047-0.084 s | REPORT §3.1 (axis 07 skeptic F1) |
| `cc_capacity_probe` | 2.6-3.9 s at load 181-230 | REPORT §3.1 (axis 05 skeptic S0.3) |
| `claude-accounts --rank general` (proxy for `--place`) | 2.10-8.09 s at load ~225; cold sweep 20 s at load ~215 | `134000efe` message |

### 1.5 What cannot be measured today

- **No per-phase timing exists.**
  - `T.Heartbeat` carries progress and step-gap fields only (`types.py:463-473`).
  - Events are written only on state changes.
  - `band.log` gives pass edges, not phases.
- **No active cohort has run since the reload.** `events.jsonl` rows since 07:23Z: 16 in all (abstain 4, release 3, stale 3, spawn 2, exit 2, not-needed 2), with **0 `place`** and **0 `admit-refused`** (M: python Counter over `events.jsonl` with t ≥ 1792480997). So the cost of a cohort pass at priority 31 is **unmeasured**. §4 S1.c makes it measured from the first cohort onward.
- **Before A1** (axis 02 §4.1, M there):
  - 9 complete passes, median ~8.1 min (4.9-12.8);
  - observe alone 3.8-6.1 min;
  - `--place` 18.7-120.8 s per call (1289 s over 17 calls, 6 at rc 124);
  - probe refusals 31 s apart;
  - failed actuator exits reaped 5.5-6.8 min late.

### 1.6 A cohort pass at priority 31 today (E)

**Method.** Sum the priority-31 child samples in §1.4 over the serial chain in §2, for a 9-member next3-shaped cohort in its first dispatch pass. Assumptions:
- pace burst 6 (`admit.py:51-54`);
- mint cost taken equal to one probe's library source, about 1-3 s (**H**).

**Typical.**
- ps 1.5-2 s;
- kitty 0.1 s;
- 9 composer reads ≈ 1 s;
- `--place` 2 lanes × 2-8 s;
- `--assign-many` 1-4 s;
- 6 admissions × (probe 2.6-3.9 + mint 1-3 + lstart `ps` 0.1-0.5) ≈ 22-45 s;
- pages 0-55 s.

Total ≈ **35-120 s**.

**Tail, every child at its bound** (stall episodes like §1.2):
- ps 80-90 s plus an unbounded kill;
- `--place` 2 × 120 s;
- 6 × (30 + 30 + 40) s;
- pages up to 8 × 55 s in the cohort's life (§2 note).

Total: **well over 10 min, with no ceiling**. This is the case B2 bounds.

## 2. Inventory: every child the loop thread waits on

`run_bounded` (`clock.py:349-361`) is the only `subprocess.run` site. That is enforced by `test_step_per_child.EveryLoopChildIsBounded`.

| Phase | Call site | Child | Bound today | Per pass |
|---|---|---|---|---|
| reap | `__main__.py:1663`, `:1729` → `act.reap_children` (`act.py:394-415`) | none: `poll` + `waitpid(-1)` | — | 2 |
| ps | `observe.observe` `:482` → `read_ps` (`observe.py:156-190`) | 2 × `/bin/ps` | 20-40 s each (`ps_bound`), 2 tries, `PS_BUDGET_S` 90 s; **post-kill wait unbounded** | 1 |
| kitty | `observe.py:496-508` → `kitty_ls` (`:235-253`) | `kitten @ ls` | 5 s | 1 per socket (1 live: `/tmp/kitty-853`, M `ls`) |
| sessions | `observe._sessions` (`:526-639`), `transcript.observe` | none (fs) | — | owned by 457c166ed9d6 |
| census | `_census` → `_read_composer` (`__main__.py:324`, `:693-719`) → `observe.composer_state` (`observe.py:426-452`) | `kitten @ get-text` | 5 s | 1 per limited session in a draft-relevant substate (`:665-690`) |
| derive | `_derive` (`:744-959`) → `plan.unassign` (`plan.py:523-534`) on hop, cohort exit or unplan | `claude-accounts --unassign` | 30 s | rare |
| draft | `_draft_snapshots` (`:581-618`) → `_run_snap` (`:567-578`) | 2 × `bash lr-composer-snapshot.sh` | 20 s each | 1 per HOLD-DRAFT record per attempt |
| plan | `_plan` (`:997-1055`) → `plan.place` (`plan.py:290-355`) | `claude-accounts --place` | `place_timeout`: 30-120 s from load1 (`plan.py:358-364`) | 1 per lane with movers (≤2) |
| own | `_own_and_charge` (`:1058-1082`): `take_ownership` → `_alive` → `store.proc_lstart` (`store.py:525-546`); `plan.assign_many` (`plan.py:499-520`) | `ps -o lstart`; `claude-accounts --assign-many` | 40 s; 30 s | lstart per new owner; **assign every pass** while any phantom is live |
| dispatch | `_dispatch` (`:1218-1327`): `act.hold_claim` → `_argv_of` (`act.py:526-536`) | `ps -o command` | 5 s | per claimed actuation with a holder |
| dispatch | `_admit` (`:1132-1180`) → `BootSlots.acquire` → `_slot_live` (`admit.py:363-388`) | `ps -o lstart` **per existing slot dir, our own included** | 40 s each | up to `limit` (6) per boot |
| dispatch | `Admission.decide` `:310` → `probe` (`admit.py:216-238`) | `bash -c 'source capacity-admit.sh; cc_capacity_probe'` | 30 s | **1 per member** |
| dispatch | `_admit` `:1177-1179` → `mint_token` (`admit.py:243-261`) | `bash -c '… cc_capacity_token_mint'` | 30 s | 1 per admission |
| dispatch | `act.spawn` (`act.py:308-352`) → `lstart_of` = `store.proc_lstart` | `ps -o lstart` | 40 s | 1 per spawn |
| dispatch | `clock.wake_guard_ok` → `sysctl kern.waketime` (`clock.py:137-154`) | `sysctl` | 5 s | 1 |
| report | `_report` (`:1432-1471`) → `Reporter._emit` (`report.py:681-691`) → `default_page` (`:591-602`) | `cc-notify` 10 s, then `lr-page.sh` 45 s (`report.py:34-38`) | 10 + 45 s per page | per latched page |
| report | `requester_mails` (`report.py:855-…`) → `_send_mail` → `cc-notify` | `cc-notify` | 10 s | 1 per requester |
| detached | `start_fresh_sweep` (`plan.py:378-397`); `_provenance` (`__main__.py:511-538`) | Popen, not waited | — | ≤1 per 120 s; 1 per hour |

**Pages in the incident cohort (M).** `recon/cohorts/next3-7d-1792497600.pages.act.json` holds 15 latched keys: open 1, delta 1, age 5, rq 7, close 1. They span 1792463788-1792497217 (9.3 h).

So a cohort's pages are a handful per hour, each up to 55 s on the serial path. Their durations are not recorded anywhere.

## 3. Findings that shape the design

**F1. `run_bounded`'s timeout is not a wall bound (M, §1.2).**
- Cause: `subprocess.run` waits unbounded after its SIGKILL (§1.2).
- Every inline child above inherits this.
- The fix is local to `clock.py`, and the repo already has the pattern in `bin/claude-accounts:822-847`: a thread joined at a bound, and a `ps` that will not die abandoned to it.

**F2. `reap_children`'s `waitpid(-1)` steals the exit status of any child another owner waits on (M).**

Command: `/usr/bin/python3 -I /tmp/b2meas/steal.py`. Output:

```
waitpid(-1) reaped True status 9
Popen.poll() of the async owner now reads 0
control, no theft: poll() reads 9
```

- CPython maps ECHILD to returncode 0 (`subprocess.Popen._internal_poll`).
- Today this is harmless only because every `run_bounded` child is waited inline, on the one loop thread, before the next `reap_children` (`act.py:394-415`, called at `__main__.py:1663`, `:1729`).
- **Once any child outlives the loop step that started it (async `--place`, probe, page), a capacity refusal (rc 9) would read as an admit (rc 0).**
- So registered-only reaping is a hard precondition of S2. It is also why the REPORT's "reap by waitpid/SIGCHLD" is replaced here by polling registered children: a SIGCHLD handler that calls `waitpid(-1)` has the same theft.

**F3. The ps census and the kitty reads must stay inline and fresh.**
- The census joins ps rows to kitty panes by root pid (`observe.py:496-508`, `_sessions` `:526-639`).
- `observe`'s contract: "a missing read that looked like 'no pane' or 'no holder' would plan a move over a live session (invariants 12, 13)" (`observe.py:3-7`). A cached or async pane map is that hazard.
- At priority 31 these reads are 0.05-1.3 s (§1.4).
- B2 therefore gives them a true wall bound (F1), merges the two `ps` calls into one (optional), and nothing more.
- Moving kitty off the *actuator's* critical path is B5's.

**F4. Stale-while-revalidate placement with a fallback ranking (axis 05 G6) is out of scope.**
- `plan.py:3-5`: "`--place` is the ONLY scorer (§C5) … It never picks an account itself".
- `plan.py:13-14`: "Decision 3 ruled wait … no least-thin pick".
- A mover with a past answer naming an account is already PLANNED and so is not a mover (`plan.movers` `:224-230`). A waiting mover's "last answer" is its WAIT, which `keep_waits` already preserves (`plan.py:367-375`).
- So SWR would amount to a second scorer, which needs an operator ruling (B4 or D1 territory).
- B2's async single-flight gives the "never blocks the pass" property without one. This matches axis 05 skeptic L7's own advice: measure `place_s` after A1 before building SWR.

**F5. A boot-slot acquire runs one `ps` per existing slot directory, our own slots included.**
- `_disk_take` (`admit.py:390-420`) calls `_slot_live` for every existing `slot-N`.
- `_slot_live` (`:363-388`) runs `proc_lstart(pid)`, a 40 s-bound `ps`, even when `pid == os.getpid()`.
- Acquiring the 6th slot costs 5 self-`ps` calls. That is cheap at priority 31 but up to 5 × 40 s in a stall.

**F6. `assign_many` runs every pass while any phantom is live** (`__main__.py:1081-1082`).
- The phantom TTL is 1200 s (`plan.py:35`).
- Re-asserting unchanged rows every 3-5 s is a `claude-accounts` start each pass (E: 1-4 s at priority 31, H) for nothing.

**F7. Pages are synchronous.**
- `_once` latches **before** `_emit` (`report.py:693-700`), so an async emit keeps at-most-once.
- Requester mails latch **on the result** (`report.py:862-864`), so they must stay synchronous. They are budgeted instead.

## 4. The design

**Principle.** One decision loop, unchanged in what it decides. A slow child is handled in one of two ways:
- (a) run inline under a wall bound that holds: timeout plus reap grace; or
- (b) run on a worker thread, with the loop consuming the answer when it lands, under stated freshness rules.

Workers run only `plan.place`, `Admission.probe` and the page sinks. They receive copied inputs and never touch `ctx.records`, `store` record files or `transcript`. So the claim/fence discipline the REPORT B2 risk names is untouched. That also addresses axis 02 skeptic L2: B2 splits no loop.

Two stages, each independently landable. Stage 1 has standalone value and produces the measurement. Stage 2 enforces `P_max`.

### Stage 1: bounded

#### S1.a A true wall bound for every inline child

**Change in `scripts/limit-recover/lr_recon/clock.py`.**
- `run_bounded` (`:349-361`) calls a new `_run_reaped` instead of `subprocess.run`.
- `_run_reaped` is `subprocess.run` with one difference: after the timeout's SIGKILL it waits at most `REAP_GRACE_S`, then abandons the child.
- It deliberately does **not** use `with Popen(...)`, whose `__exit__` waits unbounded.

```python
REAP_GRACE_S = 2.0          # after SIGKILL the loop waits this long for the corpse, then abandons it
ORPHAN_PAGE_AT = 16         # this many abandoned children alive at once is paged (once per process)
_ORPHANS: List[Any] = []    # killed, not yet reaped: polled by reap_orphans()
_DETACHED: List[Any] = []   # fire-and-forget children (fresh sweep, provenance), polled the same way
_REG_LOCK = threading.Lock()

def _grace() -> float:
    try:
        return max(0.2, float(os.environ.get("LR_RECON_REAP_GRACE_S", "") or REAP_GRACE_S))
    except ValueError:
        return REAP_GRACE_S

def _abandon(proc: Any) -> None:
    for f in (proc.stdin, proc.stdout, proc.stderr):   # our pipe ends: a stuck child cannot hold them
        if f is not None:
            try: f.close()
            except OSError: pass
    try:
        proc.wait(timeout=_grace())
    except subprocess.TimeoutExpired:
        with _REG_LOCK:
            _ORPHANS.append(proc)

def _run_reaped(*popenargs, input=None, capture_output=False, timeout=None, check=False, **kw):
    if input is not None:
        kw["stdin"] = subprocess.PIPE
    if capture_output:
        kw["stdout"] = kw["stderr"] = subprocess.PIPE
    proc = subprocess.Popen(*popenargs, **kw)
    t0 = time.monotonic()
    try:
        out, err = proc.communicate(input, timeout=timeout)
    except BaseException:          # TimeoutExpired, KeyboardInterrupt, SystemExit: same as run()
        proc.kill()                # Popen.kill polls first: an already-exited child is not signalled
        _abandon(proc)
        raise
    finally:
        _note_child(popenargs[0], time.monotonic() - t0)   # S1.c: per-pass child accounting
    cp = subprocess.CompletedProcess(proc.args, proc.returncode, out, err)
    if check:
        cp.check_returncode()
    return cp

def reap_orphans() -> int:
    with _REG_LOCK:
        n = 0
        for reg in (_ORPHANS, _DETACHED):
            alive = [p for p in reg if p.poll() is None]
            n += len(reg) - len(alive)
            reg[:] = alive
    return n

def detach(proc: Any) -> None:
    with _REG_LOCK:
        _DETACHED.append(proc)

def orphan_count() -> int:
    with _REG_LOCK:
        return len(_ORPHANS)
```

**Effect.**
- Every inline child costs at most `timeout + REAP_GRACE_S`. The `ps` phase costs at most `PS_BUDGET_S` + 2 s, against today's 98-193 s measured and 1,226 s on record.
- The abstain itself is unchanged: "unknown, retry" on the next pass.
- `ps` bounds are **not** shortened: a 30 s `ps` that finished is on record (§1.3).
- Callers are unchanged. `TimeoutExpired` and `CalledProcessError` are raised as before, and the kwargs callers pass (`capture_output`, `text`, `timeout`, `env`, `stdin`, `stdout`, `stderr`, `check`) are supported.

#### S1.b Registered-only reaping, and a loop that wakes on an exit

**`act.py` `reap_children` (`:394-415`).**
- Delete the `os.waitpid(-1, os.WNOHANG)` loop (`:407-415`).
- Keep the `_CHILDREN` poll (`:399-404`), and add `n += clock.reap_orphans()`.
- Docstring: the theft in §3 F2.
- Add:

```python
def any_exited() -> bool:
    """An actuator of ours has exited (poll() reaps it and keeps its code for reap_children)."""
    return any(p.poll() is not None for p in list(_CHILDREN.values()))
```

**Register the two unheld `Popen` sites.**
- `plan.start_fresh_sweep` (`plan.py:388-394`): `proc = popen(...)`, then `clock.detach(proc)` when it has `.poll`.
- `__main__._provenance` (`:529-535`): `clock.detach(subprocess.Popen(...))`.
- `Caffeinate` (`clock.py:364-412`) already holds and polls its child.
- `act.spawn` already registers in `_CHILDREN` (`act.py:333`).

**`__main__.wait_for_change` (`:1768-1780`).**
- Add a parameter `wake: Optional[Callable[[], bool]] = None`.
- Each 1 s tick: `if wake is not None and wake(): return True`.
- `daemon` (`:1844-1849`) passes `lambda: act.any_exited() or _async_landed(ctx)`, where `_async_landed` is false until S2.

**Effect.** The next pass starts within about 1 s of an actuator exit, instead of up to 3-20 s later. It settles the exit (`settle.dead_actuators`, `settle.py:561-565`) and schedules the retry's backoff. The REPORT asked for "a retry follows an exit within seconds".

**Safety net.** The census already sees our zombies. In `_run_pass` after `observe`: for rows with `ppid == os.getpid()` and stat `Z` whose pid is in no registry, write event `unowned-zombie` once per pid. That catches a future unregistered `Popen` site without reintroducing `waitpid(-1)`.

#### S1.c Per-phase pass timing: `recon/passes.jsonl` and heartbeat fields

**New class `PassClock` in `clock.py`** (about 60 LOC). It uses the monotonic clock: on macOS `time.monotonic` does not advance in sleep, so a lid close mid-pass is not pass time. Methods:
- `mark(name)`: close the running phase and open `name`;
- `elapsed()`, `left()`, `over()`;
- `child(name, dur)`;
- `defer(what)`;
- `note(k, v)`;
- `close()`;
- `row(**extra)`.

**Module-level binding**, like `_LOOP` (`clock.py:310-346`):
- `bind_pass(pc)`;
- `phase(name)`, a no-op when unbound or off the bound thread;
- `_note_child(argv0, dur)`, which feeds the bound `PassClock` on the loop thread only.

**`__main__.run_pass` (`:1652-1657`) becomes:**

```python
def run_pass(ctx, force_observe=False):
    pc = clock.PassClock(budget_s=ctx.pass_budget_s if ctx.stage2_on() else 0.0)
    ctx.pass_clock = pc
    clock.bind_pass(pc)
    summary = None
    try:
        with transcript.pass_index(getattr(ctx, "projects", None)):   # 6841626b4: unchanged, outermost
            summary = _run_pass(ctx, force_observe)
        return summary
    finally:
        clock.bind_pass(None)
        _log_pass(ctx, pc, summary)   # passes.jsonl row + heartbeat note (daemon only); never raises
```

**Phase marks** (one line each):
- `observe.observe`: `phase("ps")` at `:481`, `phase("kitty")` after `:489`, `phase("sessions")` before `:509`.
- `_run_pass`:
  - `phase("reap")` at `:1663`;
  - `phase("facts")` before `:1696`;
  - `phase("census")` before `:1698`;
  - `phase("derive")` before `:1702`;
  - `phase("draft")` before `:1703`;
  - `phase("wakes")` before `:1704`;
  - `phase("plan")` before `:1715`;
  - `phase("own")` before `:1719`;
  - `phase("dispatch")` before `:1720`;
  - `phase("report")` before `:1723`;
  - `phase("save")` before `:1725`.
- Abstained passes end at `ps` and are still logged.

**Data format: `recon/passes.jsonl`** (new).
- Written with `store.append_bounded`, `PASSLOG_MAX = 4 << 20`, one `.1` generation (`store.py:588-601`).
- Only the daemon writes it: `ctx.passlog = True` in `daemon()`. `--once` and tests do not.
- One compact row per pass, about 350 B. E: 17k rows a day at 5 s cadence, about 6 MB a day, so the cap holds about 16 h live plus the previous generation.

```json
{"t":1792517834.2,"pid":5233,"dur":1.12,"mode":"act","abstain":"",
 "ph":{"reap":0.0,"ps":0.71,"kitty":0.06,"sessions":0.21,"facts":0.01,"census":0.02,"derive":0.03,
       "draft":0.0,"wakes":0.0,"plan":0.0,"own":0.0,"dispatch":0.01,"report":0.04,"save":0.02},
 "kids":3,"slow":["/bin/ps",0.66],"def":{},"async":{},"orphans":0,
 "open":4,"moving":0,"movers":0,"spawned":0,"l1":258.6}
```

`l1` is telemetry only: no decision reads it (REPORT §5 G1).

**`T.Heartbeat` (`types.py:463-473`).**
- Add flat numeric fields with defaults: `pass_s`, `pass_end`, `max_pass_s`, `max_pass_at`, `orphans`.
- `clock.Heartbeat` gets `note_pass(dur, orphans)` under `self._lock`, and `snapshot()` (`clock.py:237-251`) carries them.
- The watchdog reads keys with greedy `sed 's/.*"KEY":…'` (`lr-recon-watchdog.sh:105-115`). New keys must therefore be flat and must not equal an existing key: `pid`, `lstart`, `progress`, `wall`, `progress_wall`, `step_due`, `child_bound_s`. The five names above satisfy that.

**Orphan page.** When `orphan_count() >= ORPHAN_PAGE_AT`:
- write event `orphan-backlog` once;
- send `rep.daemon_page("ORPHANS", …)` once per process, latched like `band_paged` (`__main__.py:123`, `:541-554`).

#### S1.d Optional: one census `ps` instead of two

**Change in `observe.read_ps` (`:156-190`).**
- One call: `["/bin/ps", "-axww", "-o", "pid=,ppid=,stat=,tty=,lstart=,args="]`.
- Parse with `line.split(None, 9)`: pid, ppid, stat, tty, 5 lstart tokens, args.
- `ttys[pid] = tty` unless `??` or `-`, exactly as `_parse_ttys` (`:114-120`).
- Kill switch: `LR_RECON_PS_MERGED=off`.

**Measured equivalence** (`/tmp/b2meas/merged_ps.py`):
- ttys 247/247 identical;
- proc rows identical except where a process changed between the two snapshots (1552/1576).

**Value.** Small. Time saved was 0.01 s at 15/core (M). The tty call took 0.94-1.28 s at 27/core (M). It halves the census's exposure to the §1.2 stall and makes ttys and procs one snapshot. It is not needed for the bound: land it only if it stays under 30 LOC.

### Stage 2: async, plus a budget (enforces `P_max`)

All of stage 2 sits behind one switch, `Ctx.stage2_on()`:

```python
def stage2_on(self) -> bool:
    return self.async_on and not os.path.exists(self.paths.p("async.off"))
```

- `async_on` is False in `Ctx.__init__` (tests, `--once`). `daemon()` sets it from `LR_RECON_ASYNC` (default `on`).
- The file is read every pass, so the operator can roll stage 2 back without a reload (§10).

#### S2.a `AsyncCall`, the only async primitive

New file `scripts/limit-recover/lr_recon/asynccall.py`, about 60 LOC.

```python
class AsyncCall:
    """fn(*args, **kw) on a daemon thread. The loop polls it and never waits on it longer than
    it asks. Workers only run pure callables on copied inputs; run_bounded inside them is
    thread-safe (declare_child/step are no-ops off the loop thread, clock.py:321-346)."""
    def __init__(self, name, fn, *args, runner=None, **kw):
        self.name, self.meta = name, {}
        self.started_wall, self._t0 = time.time(), time.monotonic()
        self.finished_wall = self.dur = 0.0
        self.value = self.error = None
        self._done = threading.Event()
        (runner or _thread_runner)(self._run, fn, args, kw)
    def _run(self, fn, args, kw):
        try: self.value = fn(*args, **kw)
        except BaseException as e: self.error = e          # never kills the loop
        finally:
            self.dur, self.finished_wall = time.monotonic() - self._t0, time.time()
            self._done.set()
    def done(self) -> bool: return self._done.is_set()
    def wait(self, timeout: float) -> bool:                   # loop thread: declared, then stepped
        if timeout <= 0 or self.done(): return self.done()
        clock.declare_child(timeout)
        try: return self._done.wait(timeout)
        finally: clock.step()
    def result_or(self, default): return self.value if self.done() and self.error is None else default
    def age(self) -> float: return time.time() - self.finished_wall if self.done() else 0.0
```

- `_thread_runner` starts `threading.Thread(daemon=True, name="lr-async-"+name)`.
- `_sync_runner` runs inline. It is used when stage 2 is off, so one code path serves both modes.
- Tests inject a manual runner that completes on command.

#### S2.b `--place`, single-flight per lane, consumed when it lands

**`Ctx` (`__main__.py:93-126`)** adds `self.place_calls: Dict[str, AsyncCall] = {}`.

**`_plan` (`__main__.py:997-1055`), lane loop.** The tail (plan_only filter `:1042-1045`, `plan.apply` `:1046`, `write_plan` `:1047-1054`) is unchanged.

```python
PLACE_INLINE_S = 10.0       # all inline --place waits of one pass together (p90 of the PRI-31 proxy ~8 s)
PLACE_ASYNC_TIMEOUT_S = plan.PLACE_TIMEOUT_MAX_S   # 120 s, fixed: the loop no longer waits on it
PLACE_ANSWER_TTL_S = 120.0  # an answer that landed longer ago than this is re-asked, not applied

mvs = plan.movers(...)                                     # :1001, unchanged
by_sid = {m.sid: m for m in mvs}
inline = min(PLACE_INLINE_S, ctx.pass_clock.left())
for lane in ("general", "fable"):
    step()
    lane_mvs = [m for m in mvs if recs[m.sid].lane == lane]
    if not ctx.stage2_on():
        ...today's synchronous body, :1008-1041, unchanged (incl. place_timeout(load1))...
        continue
    call = ctx.place_calls.get(lane)
    if call is None and lane_mvs:
        call = _start_place(ctx, lane, lane_mvs, snap, now)          # computes kwork here, copies inputs
        t0 = time.monotonic(); call.wait(inline); inline -= time.monotonic() - t0
    if call is None:
        continue
    if not call.done():
        if not call.meta.get("pending_logged"):
            call.meta["pending_logged"] = True
            _event(paths, "place-pending", detail="lane=%s n=%d age=%.0fs" % (lane, call.meta["n"], time.time() - call.started_wall))
        ctx.pass_clock.note("place:" + lane, "pending")
        continue                                                     # movers keep their substate
    del ctx.place_calls[lane]
    got, rc = call.result_or(({sid: T.Placement(acct=None, reason="wait-data") for sid in call.meta["sent"]}, 126))
    got, dropped = _place_fresh(got, call, by_sid, recs, facts)      # §6 rules 1-4
    misses = ctx.place_misses.get(lane, 0) + 1 if rc in plan.TRANSIENT_RC else 0
    ctx.place_misses[lane] = misses
    n_got = len(got)
    got = plan.keep_waits(got, ctx.pre_census, rc, misses)
    _event(paths, "place", detail="lane=%s rc=%d cause=%s n=%d kept=%d misses=%d dur=%.1fs "
           "timeout=%.0fs async=1 age=%.1fs dropped=%d load1=%.0f" % (...))
    if rc == 3 and mode != "observe":
        plan.start_fresh_sweep(paths, now)
    placed.update(got)
    rest = [m for m in lane_mvs if m.sid not in call.meta["sent"]]
    if rest:                                                         # movers that arrived mid-call
        _start_place(ctx, lane, rest, snap, now)                     # no inline wait: next pass consumes
```

`_start_place`:
- builds `kw = plan.kwork(snap, _accounts(ctx.home), now)` only when a call starts;
- creates `AsyncCall("place:"+lane, plan.place, lane, list(lane_mvs), paths.facts, dict(kw), timeout=PLACE_ASYNC_TIMEOUT_S, runner=ctx.runner)`;
- sets `meta = {"sent": {sid: (record_id, attempt)}, "n": len}`.

**The bound.** It is fixed at 120 s, so `place_timeout`'s load term (`plan.py:358-364`) leaves the async path. Axis 06 F4 showed it shrinking to 63-66 s while the work did not. `load1` remains in the event as telemetry.

**Semantics kept.**
- An answer consumed in the same pass, which is the common case at priority 31 (E: 2-8 s under a 10 s inline wait), is applied exactly as today.
- `rc` 124/126 keep the `keep_waits` logic. `misses` now counts calls, not passes.
- A pending call leaves its movers as they were. A fresh DETECTED stays DETECTED, which `_invariant` skips (`__main__.py:1574-1579`). No WAIT_DATA is written for an answer that is still coming.
- "Invariant 16 (rank → assign … one pass)" (`plan.py:10-11`) still holds: the consumed answer is applied and `--assign-many` runs in the same pass's `_own_and_charge`.

#### S2.c The capacity probe, one shared async verdict

**Precondition (M from code).** The probe takes no sid or account (`admit.py:216-231`). Its terms are box-global:
- headroom;
- segments;
- active + in-flight tokens vs R (`capacity-admit.sh:1294-1640`, in-flight term `:1630`).

So one verdict can judge one admission, provided it was taken after the previous admission's token existed.

**Changes in `admit.py` `Admission`** (`:100-129`, `:150-163`, `:243-261`, `:264-333`):

```python
PROBE_INLINE_S = 5.0        # one inline wait for a verdict
PROBE_INLINE_PASS_S = 15.0  # every inline probe wait of one pass together
PROBE_FRESH_S = 20.0        # a verdict that LANDED longer ago than this is not used (wall, at use)

# __init__: self.async_probe=False; self.probe_call=None; self.verdict=None  # (ok, why, started, landed)
#           self.last_admit_wall=0.0; self.inline_left=0.0; self.runner_async=None
def begin_pass(self, left_s): self.inline_left = min(PROBE_INLINE_PASS_S, max(0.0, left_s))
def _land(self):
    c = self.probe_call
    if c is not None and c.done():
        ok, why = c.result_or((False, "probe-error rc=%d" % RC_SPAWN_ERROR))
        self.verdict, self.probe_call = (ok, why, c.started_wall, c.finished_wall), None
def _usable(self):
    v = self.verdict
    return v is not None and v[2] >= self.last_admit_wall and self.wall() - v[3] <= PROBE_FRESH_S
def probe_kick(self):
    self._land()
    if self.restore_r is None or self.probe_call is not None or self._usable():
        return
    self.probe_call = AsyncCall("probe", self.probe, self.restore_r, runner=self.runner_async)
def shared_probe(self):
    """(ok, why) of a verdict that saw every earlier admission, or None: not known yet."""
    self.probe_kick()
    if not self._usable() and self.probe_call is not None and self.inline_left > 0:
        t0 = self.wall(); self.probe_call.wait(min(PROBE_INLINE_S, self.inline_left))
        self.inline_left -= max(0.0, self.wall() - t0); self._land()
    return self.verdict[:2] if self._usable() else None
```

**`decide` changes.**
- Replace `:310` `ok, reason = (False, "restore-r") if over else self.probe(self.restore_r)` with:

```python
if over:
    ok, reason = False, "restore-r"
elif self.async_probe:
    got = self.shared_probe()
    if got is None:
        return False, "probe-pending"    # unknown: no refusal counted, no pace/pacer taken
    ok, reason = got
else:
    ok, reason = self.probe(self.restore_r)
```

- In the admission tail (`:330-333`) add `self.last_admit_wall = self.wall(); self.verdict = None`.
- `mint_token` (`:243-261`) ends with `self.last_admit_wall = max(self.last_admit_wall, self.wall())`. That way a probe started before this token existed is never used.
- `leave_active` (`:150-163`) clears `verdict` and `probe_call`. The thread finishes alone, and its child is reaped by S1.a.

**`__main__._dispatch` (`:1218-1222`).** After `_admission_period`:

```python
adm = ctx.admission
adm.async_probe, adm.runner_async = ctx.stage2_on(), ctx.runner
adm.begin_pass(ctx.pass_clock.left())
if adm.async_probe and any(r.open and r.kind == "limited" and r.phase in ("PRE-MOVE", "RELAUNCHED")
                           for r in ctx.records.values()):
    adm.probe_kick()
```

In the refusal branch (`:1270-1285`), `probe-pending` skips the refusal bookkeeping, so the status line never shows a fake gate (`report.py:177-187`):

```python
if why == "probe-pending":
    ctx.pass_clock.defer("probe-pending")
    continue
```

`_admit` already releases the boot slot on any refusal (`:1173-1174`).

**Semantics kept.**
- One verdict serves at most one admission, and only if it started after the last token. That is today's one-probe-per-member, minus the wait.
- A refusing verdict ("capacity", "probe-timeout", "probe-error") may refuse several members within `PROBE_FRESH_S`. Each still increments `refusals[cohort]` per member, so the drip opens on the same member count as today (axis 06 skeptic L5 caveat).
- A probe that takes 30 s and times out lands as `probe-timeout` and counts exactly as today.
- Not changed here: whether a timeout should count at all (A4 remainder), and skipping the probe while the drip is open (axis 06 F8). Both belong to the admission owner and are superseded by B3's deadline override (§13).

#### S2.d A pass budget for deferrable work

`LR_RECON_PASS_BUDGET_S`, default **60**; `0` turns it off. Set in `daemon()` as `ctx.pass_budget_s`, and 0 when stage 2 is off. "Over" means `pc.elapsed() >= budget`.

**`_dispatch` loop (`:1223-1327`).**
- Before `act.may_actuate`: `if units and ctx.pass_clock.over(): ctx.pass_clock.defer("dispatch"); continue`.
- `units` counts records that passed `may_actuate` this pass, so **at least one dispatch per pass is always allowed** (progress).
- The sort `(kind != limited, detected)` (`:1223-1226`) serves the oldest first, and a deferred record is untouched: no state change, no event.

**`_draft_snapshots` (`:587-593`).** If over: `defer("draft")`, `continue` **before** setting `draft_snap_attempt`, so the snapshot is taken on a later pass.

**`Reporter.requester_mails` (`report.py:855-…`).**
- Gets `self.budget_left: Callable[[], float]`, set by `_report` to `ctx.pass_clock.left`.
- Inside the per-requester send loop: if `budget_left() < NOTIFY_TIMEOUT_S + REAP_GRACE_S`, break. The mail is unlatched, so the next pass retries it (`:862-864`).

**Deliberately not budgeted** (non-deferrable):
- `ps` and kitty: a pass without them must abstain or degrade, as today;
- composer reads: an unread composer makes a limited session a mover (`census.py:236-241`), which changes buckets;
- `_derive`'s rare `unassign`;
- `_own_and_charge`.

**Why no worst-case reserve.** A reserve test (start a unit only if `left ≥` its worst case of about 80 s) would allow one dispatch per pass in normal operation. That would rebuild the one-admission-per-pass brake that A4 removed. The budget is a soft deadline: the overrun is bounded by one unit, and it is logged.

#### S2.e Pages off the loop

**`Reporter` (`report.py:615-625`, `:681-691`).**
- `async_pages` (set by `_report` from `ctx.stage2_on()`).
- A bounded `queue.Queue(maxsize=64)`.
- One daemon thread `lr-pager`, started lazily, that runs `_deliver(pane, text)`. That is today's body of `_emit`, with `failures += 1` under a lock.

**`_emit`:**
- observe mode → `_shadow`, unchanged;
- `async_pages` → `put_nowait`;
- a full queue → deliver inline. A page is never dropped.

**`flush(timeout)`** waits on `unfinished_tasks` up to `timeout`. `daemon()`'s `finally` (`__main__.py:1850-1853`) calls `ctx.reporter.flush(10)`.

**Latching is unchanged.** `_once` saves the latch before `_emit` (`:693-700`). `requester_mails` stays synchronous through `_send_mail` (`:656-669`), because it latches on the result.

#### S2.f `--assign-many` only when the phantom rows change, or every 120 s

**`_own_and_charge` (`__main__.py:1081-1082`):**

```python
rows = plan.phantom_rows(list(ctx.records.values()))
key = tuple(sorted((r["acct"], r["id"], r["w"]) for r in rows))
wall = time.time()
if (not ctx.stage2_on() or key != ctx.assign_key or ctx.assign_rc != 0
        or wall - ctx.assign_at >= plan.PHANTOM_REFRESH_S):
    ctx.assign_rc = plan.assign_many(rows)
    ctx.assign_key, ctx.assign_at = key, wall
```

- Add `PHANTOM_REFRESH_S = 120.0` beside `PHANTOM_TTL_S = 1200` (`plan.py:35`): a 10x margin.
- New placements change the key, so they are always charged in the same pass (invariant 16).
- On a restart the memo is empty, so the first pass assigns.

#### S2.g A boot-slot check never runs `ps` on this daemon itself

In `BootSlots._slot_live` (`admit.py:363-388`), after the pid read:

```python
if pid == os.getpid():
    return not want or want == _self_lstart()
```

`_self_lstart` is a module-level cache of `store.proc_lstart(os.getpid())`, read once, like `act._SELF_LSTART` (`act.py:490-512`). A foreign pid still gets its one `ps` (`cc-lr move` slots).

#### Rig seam (for B1 and the stage-2 rig check)

`tests/rig/fake-claude-accounts.py`: `--place` sleeps `float(os.environ.get("RIG_PLACE_SLEEP_S", "0"))` before answering. This supplies B1's fault "the placer sleeping past its bound" (REPORT §5 step 4).

## 5. Per-phase budgets

| Phase | Wall cap after B2 (per child or per pass) | Priority-31 typical | Deferrable | Enforced by |
|---|---|---|---|---|
| reap | no children (registries only) | ~0 | — | S1.b |
| ps | ≤ `PS_BUDGET_S` 90 + 2 s; a stall abstains | 0.4-1.9 s (M §1.4) | no → abstain | S1.a |
| kitty | ≤ 7 s per socket (1 socket) | 0.05-0.08 s (REPORT §3.1) | no → degrade `kitty:<sock>` | S1.a |
| sessions | unchanged (no children) | ≈0.3-1 s (E: `6841626b4` steady census 2.0-2.6 s incl. ps + kitty) | no | 457c166ed9d6 |
| census (composer) | ≤ 7 s per read | ~0.05-0.2 s each (E: kitty RC) | no (an unread composer changes buckets) | S1.a |
| derive | ≤ 32 s per rare `unassign` | ~0 | no | S1.a |
| draft | ≤ 2 × 22 s per HOLD-DRAFT record | unmeasured | yes | S2.d |
| plan | inline ≤ 10 s per pass; each call ≤ 122 s on its worker | 2-8 s (proxy, §1.4) | yes (async) | S2.b |
| own | `assign` ≤ 32 s, at most once per 120 s unless rows change; `lstart` ≤ 42 s per new owner | 1-4 s (E, H) | no | S1.a, S2.f |
| dispatch | stops starting units once elapsed ≥ 60 s (≥1 per pass); probe inline ≤ 5 s each, ≤ 15 s per pass; mint ≤ 32 s; spawn lstart ≤ 42 s; own slots no `ps` | probe 2.6-3.9 s; mint ~1-3 s (H) | yes | S2.c, S2.d, S2.g |
| report | pages async; mails while `left ≥ 12 s` | — | yes | S2.d, S2.e |
| save | unchanged | small (`6841626b4` batch) | no | 457c166ed9d6 |

**P after B2 (E, sum of caps).**
- **Abstained pass:** ≤ about 92 s.
- **Trusted pass:** ≤ budget 60 s + one dispatch unit + the non-deferrable tail.
  - A dispatch unit is claim `ps` 7 + probe 5 + mint 32 + lstart 42 + foreign slot `ps` ≤ 42 ≈ 130 s, but only when every one of those children is at its bound.
  - So ≈ 200-210 s in a whole-box stall episode, and **seconds to tens of seconds typically**.
- **Today** the trusted pass has no ceiling: §1.2 for one child, §1.6 for a cohort.
- The REPORT's 3-minute `P_max` target holds except in the compound worst case. `passes.jsonl` reports the real distribution, which B3 should use instead of this formula.

## 6. Stale-data rules (the async answers)

| # | Answer | Used only if | Otherwise |
|---|---|---|---|
| 1 | `--place` row for sid S | S is a mover **this pass** and its `(record_id, attempt)` equals the one sent | dropped (closed, PLANNED, hopped, re-attempted); S is re-asked by the next call |
| 2 | `--place` row naming account A | no uncontradicted fact on A has `observed_at` > the call's `started_wall` | dropped: A turned capped or auth-failed after the ask. Any residue becomes TARGET-LIMITED and hops, which is one safe retry (axis 05 K1) |
| 3 | a whole `--place` answer | it landed ≤ `PLACE_ANSWER_TTL_S` (120 s) before consumption (wall, read at use) | all rows dropped and re-asked |
| 4 | `--place` rc 124/126 or worker error | — | `keep_waits` exactly as today; `misses` counts calls |
| 5 | probe verdict | it **started** after the last admission or mint (`last_admit_wall`), it **landed** ≤ 20 s ago (`Admission.wall()` at use), and it has not admitted anyone yet | `probe-pending`: not counted, nothing taken, a new probe is kicked |
| 6 | page | always: the latch is written before the enqueue, as today | — |
| 7 | phantom rows (`assign` memo) | the key is unchanged, the last rc was 0, and < 120 s have passed | `--assign-many` runs |

All comparisons read the wall clock at use, never the pass's `now`. That is B7's rule; the three pass-`now` defects in REPORT §3.4 are the cautionary cases.

**Rule 2 compares like with like.** A fact written in the same pass that started the call is stamped with that pass's `now`, which is earlier than the call's start, and `--place` has already read it. A fact from any later pass is stamped later. "Freshness is subject-relative" (`agent-operating-lessons-situational.md:76`): rules 1-2 key on the subject (this record's attempt, this account's facts), not on the box's clock alone.

## 7. Failure modes under permanent 15-40/core

| Failure | Today | After B2 |
|---|---|---|
| `ps` stuck in the kernel past its bound | The loop blocks through the kill-wait: 56-156 s measured, 1,226 s on record. The watchdog can kill a stalled-progress daemon (condition 4, `lr-recon-watchdog.sh:279-321`) | ≤ bound + 2 s. The child is parked in `_ORPHANS` and reaped when the kernel lets go. The pass abstains ("unknown, retry"). ≥16 parked pages once. The heartbeat, `passes.jsonl` and `orphans` show it |
| The kernel stall persists (minutes) | Every pass stretches | Every pass abstains within about 92 s. Orphans stay bounded at ≤2 per pass and hold no fds (pipes closed) |
| `--place` slow or stuck | The pass blocks ≤ 2 × 120 s; rc 124 → WAIT_DATA after 3 misses | The pass waits ≤ 10 s. The answer is applied when it lands, if fresh (§6). A stuck call ends at 122 s as rc 124, through `keep_waits`. Single-flight means no pile-up |
| The probe takes 30 s or times out | k × 30 s serial per pass | ≤ 15 s inline per pass. The verdict lands and is consumed; a timeout counts toward the drip as today |
| An async child's exit status stolen | n/a (no async) | Impossible: `waitpid(-1)` removed, every `Popen` site registered, an AST test guards new sites |
| A worker raises | n/a | `AsyncCall` stores the error. The consumer treats it as rc 126 (`place`) or `probe-error rc=-1`. The loop never sees an exception |
| The daemon is killed mid-call | Children die with it | Same: workers' children are in the daemon's process group (no `start_new_session` in `run_bounded`). Nothing async is persisted, so a restart re-asks. No record schema change (A6-neutral) |
| A page is latched but the daemon is killed before sending | Possible during the synchronous emit | Possible for a few seconds longer (queue latency). Clean exits flush ≤ 10 s |
| A deferred dispatch starves | n/a | ≥1 unit per pass, oldest-detected first. Deferred records are untouched. Throughput above the pace bucket (1 per 20 s, burst 6) is unchanged |
| A clock jump (lid close) mid-pass | `Clock.tick` shifts deadlines (`clock.py:118-130`) | `PassClock` is monotonic (does not run in sleep), so a sleep does not exhaust the budget. Probe and `place` freshness use wall time, so a sleep makes them stale, which errs to re-asking |
| The kill switch is flipped mid-call | n/a | The in-flight `AsyncCall` objects are dropped on the next pass (`stage2_on()` false → the sync path). Their threads finish and their children are reaped |
| `--once`, the W3 proof | Synchronous | Unchanged: `async_on` is False and no `passes.jsonl` is written |

## 8. The boundary with backlog 457c166ed9d6

**Status (M).** `~/.claude/autonomy/backlog.jsonl` rows for `457c166ed9d6`:
- `claim` by `d5437e68…` at 2026-10-20T13:35:00Z;
- `done` at 14:15:41Z, `evidence: 6841626b4`.

Commit `6841626b4` (2026-10-20 08:52 −05:00, ancestor of `main`, M `git merge-base --is-ancestor`) changed `transcript.ProjectsIndex`, `transcript.pass_index`, `store.save_records`, `Ctx.projects` and `run_pass`.

**457c166ed9d6 owns, and B2 does not change:**
- `transcript.py` entirely: `ProjectsIndex`, `begin_pass`, the `ROLL_PASSES` slice, `recheck`, the realpath cache, `pass_index`, the module global `_ACTIVE` (`transcript.py:300-309`);
- `store.save_records`, `RECORD_REFRESH_S`, `_SAVED` (`store.py:140-142`);
- `Ctx.projects` (`__main__.py:124-126`);
- the census walk cost itself, including `plan.kwork`'s per-session subagent globs if B2's telemetry shows them heavy. Such findings are routed to that owner as a follow-up and are not fixed in B2.

**B2 owns:** child execution and reaping (`clock.run_bounded`, `act.reap_children`, the registries), `AsyncCall`, async `--place`/probe/pages, the pass budget, `PassClock`/`passes.jsonl`/heartbeat pass fields, the exit wake, the `assign` memo and the boot-slot self-check.

**The shared edit surface is `__main__.run_pass`/`_run_pass` (`:1652-1745`).** B2 must:
- keep `with transcript.pass_index(getattr(ctx, "projects", None))` as the outermost wrapper of `_run_pass`;
- keep `store.save_records(paths, list(ctx.records.values()), now)` as the single batch write (`:1728`);
- only add `phase()` marks around them.

**The thread rule.** No B2 worker thread may call `transcript.*` or `store.save_records`: `_ACTIVE` and `_SAVED` are unsynchronized module state. This holds by construction (workers run only `plan.place`, `Admission.probe` and the page sinks) and is checked by an AST test (§9 T15).

**Regression guards B2 must keep green:**
- `lr_recon.tests.test_projects_index` (incl. "the daemon keeps one index");
- `lr_recon.tests.test_store.SaveRecords`.

## 9. Test plan

New file `scripts/limit-recover/lr_recon/tests/test_bounded_pass.py`, plus migrations. Run under the launchd interpreter, as the rule "Deployment interpreter ≠ yours" requires:

```
cd scripts/limit-recover && TMPDIR=/tmp PYTHONDONTWRITEBYTECODE=1 /usr/bin/python3 -m unittest discover -s lr_recon/tests -t .
```

Baseline at HEAD (M): `test_step_per_child`, `test_midpass_progress` and `test_admit` => `Ran 40 tests … OK`, and `git status` is clean.

For each test, the "red before the fix" column says how the control fails on today's code. Where no pre-fix equivalent exists, it names the mutant that must die (rule "Green in both arms").

| # | Test (class.method) | Asserts | Red before the fix / mutant |
|---|---|---|---|
| T1 | `BoundedReap.test_stuck_child_costs_bound_plus_grace` | `subprocess.Popen` patched with a `StuckPopen` whose `wait()` blocks 3 s after `kill()` (and returns at once once `returncode` is set, like a real Popen). `run_bounded(timeout=0.2)` raises `TimeoutExpired` in < 0.2 + `LR_RECON_REAP_GRACE_S`(0.3) + 0.3 s; the proc is in `clock._ORPHANS` | **Red today:** 6.29 s (M, `/tmp/b2meas/killwait.py`) |
| T2 | `BoundedReap.test_real_child_killed_and_reaped` | `run_bounded(["/bin/sleep","5"], timeout=0.3)` raises within 1 s; no orphan left; `ps -p` shows no zombie | positive control (a real kill works) |
| T3 | `BoundedReap.test_orphan_is_reaped_later` | a `StuckPopen` that becomes reapable is gone after `act.reap_children()` | mutant: `reap_orphans` not called → orphan stays |
| T4 | `RegisteredReaping.test_async_owner_keeps_exit_status` | a `Popen(["/bin/sh","-c","exit 9"])` not in `_CHILDREN`; sleep 0.3; `act.reap_children()`; `p.poll() == 9` | **Red today:** `poll()` reads 0 (M, `/tmp/b2meas/steal.py`) |
| T5 | `RegisteredReaping.test_actuator_code_still_kept` | existing `test_act.test_an_actuator_exit_code_survives_other_subprocess_calls` (`test_act.py:276-292`) unchanged and green | equivalence guard |
| T6 | `RegisteredReaping.test_detached_children_are_reaped` | `start_fresh_sweep` / `_provenance` Popen fakes registered and reaped (no zombie) | mutant: drop `detach()` → zombie |
| T7 | `ExitWake.test_wait_returns_on_actuator_exit` | `wait_for_change(…, 5.0, …, wake=act.any_exited)` returns in < 1.5 s after a registered child exits | **Red today:** returns at 5 s (no wake parameter) |
| T8 | `PassLog.test_one_row_per_pass_phases_sum` | a daemon-mode `run_pass` with fakes writes 1 row; `sum(ph) ≈ dur` (±5%); a patched slow `plan.place` is attributed to `plan`; an abstained pass writes a row with `abstain` set and phases ending at `ps` | **Red today:** no `passes.jsonl` |
| T9 | `PassLog.test_heartbeat_keys_are_watchdog_safe` | rendered heartbeat: for each watchdog key, `sed`-equivalent greedy extraction (regex copied from `lr-recon-watchdog.sh:105-108`) returns the same value with and without the new keys | mutant: name a key `"wall"` → the extraction changes |
| T10 | `AsyncPlace.test_slow_place_does_not_hold_the_pass` | stage 2 on, manual runner: `plan.place` never completes; `run_pass` returns with the fake wall advanced ≤ `PLACE_INLINE_S`; movers keep `pre_census` substates; one `place-pending` event; the next pass after completion applies PLANNED | **Red today:** the synchronous `_plan` charges the full 120 s (patched place charging the fake wall, as in `test_midpass_progress.py:177-183`) |
| T11 | `AsyncPlace.test_stale_rows_dropped` (4 cases, §6 rules 1-3) | closed sid / new attempt / target fact newer than the ask / answer older than TTL → not applied | one mutant per rule (remove the check), each must fail its case |
| T12 | `AsyncPlace.test_answer_applied_same_pass_when_fast` | completes within the inline wait → applied in the same pass, `place` event `async=1` | equivalence guard vs the sync path |
| T13 | `SharedProbe.test_slow_probe_does_not_hold_dispatch` | 3 candidates, probe never lands: `_dispatch` waits ≤ `PROBE_INLINE_PASS_S` in total; all 3 get `probe-pending`; `refusals` unchanged; no `admit_refused` written | **Red today:** 3 × probe wall (sync `decide`) |
| T14 | `SharedProbe.test_verdict_rules` | (a) a verdict started before `last_admit_wall` is unused; (b) a verdict admits at most one; (c) a verdict landed > 20 s ago is unused; (d) a refusing verdict counts per member, so the drip opens on the 4th member as today | mutants: drop (a), (b), (c), or count per verdict → each fails |
| T15 | `ThreadRules.test_popen_sites_and_worker_callables` | AST: every `subprocess.Popen` in `lr_recon/*.py` is in `{act.spawn, clock._run_reaped, clock.Caffeinate, plan.start_fresh_sweep, __main__._provenance}`; every `AsyncCall(` target is in `{plan.place, self.probe}` and `Reporter` uses its queue | mutant: add a Popen elsewhere → fails |
| T16 | `DispatchBudget.test_budget_defers_after_first_unit` | fake `PassClock` over after unit 1: unit 2 not dispatched and untouched; at least 1 dispatched even when over at entry | **Red today:** both dispatched |
| T17 | `DispatchBudget.test_draft_snapshot_retried_next_pass` | over → `draft_snap_attempt` not set; next pass under budget takes it | mutant: set before the check → never retried |
| T18 | `AsyncPages.test_pages_do_not_hold_the_pass` | page sink blocks 2 s: `_report` returns < 0.3 s; the sink is called once; the latch is on disk before the call; a full queue delivers inline | **Red today:** `_report` blocks 2 s |
| T19 | `AsyncPages.test_requester_mail_budget` | `budget_left` < 12 → no mail, no latch; next pass sends | mutant: latch before send → mail lost |
| T20 | `AssignMemo.test_assign_only_on_change_or_refresh` | 3 passes same rows → 1 call; new row → call; +120 s → call; rc≠0 → next pass calls | **Red today:** 3 calls |
| T21 | `BootSlot.test_own_slot_no_ps` | acquiring slot 6 with 5 own slots runs 0 `proc_lstart` | **Red today:** 5 calls |
| T22 | `IncidentShape.test_cohort_pass_is_bounded` | fake-wall replay of axis 02 P1/P2: 9 limited movers, `--place` 120 s both lanes, probe 30 s, mint 30 s, 4 pages at 55 s, one `ps` timing out. Stage 2 on → fake pass ≤ 60 + 130 + 15 s; every child gap ≤ bound + grace (the `test_step_per_child` `floor_kill` sampler stays empty) | **Red today:** ≥ 120·2 + 9·30 + 6·30 + 4·55 s ≈ 15 min fake |
| T23 | `Switch.test_async_off_file_restores_today` | `recon/async.off` present → `_plan`/`decide`/`_emit`/`assign` take the sync path; the same fixture yields byte-identical record state to stage 2 off | equivalence guard |

**Migrations (must, not optional).**
- `test_step_per_child.py:101`, `:129`, `:137`, `:149`, `:164` patch `C.subprocess.run`. After S1.a, `run_bounded` no longer calls it, so these patches would **silently stop intercepting**, and `plan.place` in `unit()` would exec the real `claude-accounts`. Retarget them to `mock.patch.object(C, "_run_reaped", …)`.
- `EveryLoopChildIsBounded` (`:186-213`): extend its allowed set to `_run_reaped`, and add T15's Popen-site check beside it.
- `test_midpass_progress` (`:177-183`) builds `M.Ctx` directly, so `async_on` is False and it stays synchronous and unchanged.

**Bats.**
- `tests/lr-recon-watchdog.bats` unchanged and green.
- One new case feeds it a heartbeat carrying the five new keys and asserts the same verdicts.
- Run `bats` serially (rule "A plan line is not a run": `command -v parallel` is empty).

**Rig (B1 consumes it).** `RIG_PLACE_SLEEP_S=150` with the W5 rig (`tests/rig/lr-recon-rig.sh`). Expected:
- with stage 2: `passes.jsonl` max `dur` ≤ 210 s and every mover PLANNED once the answer lands;
- with `async.off`: passes ≥ 2 × 120 s.

That rig run is the end-to-end red/cure pair. The load-level version (15/25/40 per core, band mix) is B1's.

## 10. Rollout, kill switches, operator steps

**Land order.**
1. **Stage 1:** S1.a-c plus optional S1.d. Run the unit suite under `/usr/bin/python3`, `tests/lr-recon-*.bats`, and the rig smoke.
2. **Stage 2:** S2.a-g plus the rig seam. Same suites plus T22 and the rig pair.

Each stage is its own commit. Both are agent-buildable. Neither changes the record schema, a plist or any launchd job.

**Activation (operator, after each landing).** A loaded Python daemon keeps its old modules until restarted, and agents may not restart launchd jobs (`lr-band-reload.sh:2-5`). Restart at a quiet boundary. This waits up to 30 min until the reconciler has no `lr-recon-act` child, then `kickstart -k`, and verifies a new pid with progressing heartbeat. It is also A6(i):

```
bash ~/.reso/limit-recover/design-v2/lr-restart-at-boundary.sh --confirm reconciler
```

**Verify (operator or agent, read-only):**

```
tail -n 3 ~/.reso/limit-recover/recon/passes.jsonl
cat ~/.reso/limit-recover/recon/heartbeat
tail -n 2 ~/.reso/limit-recover/recon/band.log
```

Expect:
- the heartbeat to carry `"pass_s"` and `"orphans":0`;
- `band.log` to keep reading `pri=31 … ok` with the new pid.

During the first cohort, check that no `place` event has `dur` = 120 s with `async=0`, and read the `ph.dispatch` and `ph.plan` distributions.

**Kill switches.**
- **Stage 2 at runtime, no reload.** Takes effect on the next pass. The sync path is today's code:
  - off: `touch ~/.reso/limit-recover/recon/async.off`
  - back on: `rm ~/.reso/limit-recover/recon/async.off`
- **Stage 2 by environment** (plist edit + reload; operator): `LR_RECON_ASYNC=off`, `LR_RECON_PASS_BUDGET_S=0`.
- **Telemetry:** `LR_RECON_PASSLOG=off` (environment).
- **Reap grace tuning:** `LR_RECON_REAP_GRACE_S` (default 2, floor 0.2).
- **Merged ps:** `LR_RECON_PS_MERGED=off`.
- **Full rollback:** revert the stage commit(s), then the restart command above.

**No operator ruling is needed.**
- No gate semantics change: a verdict serves one admission, refusals count per member, `keep_waits` is unchanged.
- No placement policy changes: no fallback scorer.

## 11. Estimated size

E: per-item sum, from comparable landed diffs (`6841626b4`: 539 lines across 5 files).

| Item | Production LOC | Test LOC |
|---|---|---|
| S1.a bounded reap | 55 | 90 |
| S1.b registered reaping, detach sites, exit wake, unowned-zombie event | 45 | 80 |
| S1.c `PassClock`, phase marks, `passes.jsonl`, heartbeat fields, orphan page | 130 | 110 |
| S1.d merged ps (optional) | 25 | 30 |
| S2.a `AsyncCall` + runners | 60 | 40 |
| S2.b async `--place` + `_place_fresh` | 90 | 130 |
| S2.c shared probe | 70 | 110 |
| S2.d pass budget (dispatch, draft, mails) | 30 | 60 |
| S2.e async pages | 55 | 50 |
| S2.f `assign` memo | 20 | 30 |
| S2.g own-slot check | 8 | 15 |
| Ctx/daemon wiring, `async.off`, rig seam | 40 | 25 |
| Test migrations (`test_step_per_child`) | — | 15 |
| **Total** | **≈630** | **≈785** |

Total ≈1,400 lines; stage 1 ≈ 560, stage 2 ≈ 840.

## 12. Dependencies on the other items

| Item | Relation |
|---|---|
| B1-load-harness | **B1 verifies B2** (P distribution at 15/25/40 per core from `passes.jsonl`; red arm `async.off`). It is not a build prerequisite: the unit tests and the rig pair prove the mechanism. B2 supplies the `RIG_PLACE_SLEEP_S` seam |
| B3-deadline-override | **B3 depends on B2.** Its bound uses `P_max`. B2 supplies the enforced budget, the measured distribution and two interfaces B3 may override past `W_soft`: `Admission.verdict`/`probe-pending` and `ctx.place_calls[lane]` with its age |
| A6-restart-safety | Independent. B2 persists nothing and changes no record or claim. Its deploy uses the boundary restart, A6(i). A6(ii)'s re-stamp fix is unaffected |
| B6-telemetry | **Shares** `passes.jsonl`: B6's "log `probe_s` and `place_s`" is satisfied by B2's `place` event `dur` and `passes.jsonl` `async`. B6 should add its runnable-thread and kitty-priority fields to its own file, or read B2's, not open a second per-pass log |
| B7-now-audit | B2 follows B7's rule (wall clock read at use, monotonic for budgets). B7's audit should include B2's new comparisons (§6) |
| B4-cheap-place | Independent and complementary: B4 shrinks each `--place`, B2 stops the loop waiting on it. A fallback ranking (SWR), if ever ruled in, belongs to B4/D1, not B2 |
| B5-kitty-off-critical-path | Independent: B5 is actuator-side (handoff-fire). B2 keeps census kitty reads inline (§3 F3) |
| C2-socket-prompt, C1-credential-flip, G2-self-recovery | Independent. G2 would shrink the reconciler's work. B2's bound still holds |
| A7, D1, D2, B8 | Independent. D2 adds movers, which async `--place` absorbs. B8 (kitty at priority 4) shows up as `kitty:<sock>` degrades, which B2 caps at 7 s |

## 13. Considered and scoped out

- **A stale-while-revalidate placement or fallback ranking** (axis 05 G6). It conflicts with §C5/Decision 3, and the waiting mover's last answer is its WAIT (§3 F4). This needs an operator ruling under B4/D1.
- **Async or cached `ps` census and kitty pane map.** This violates invariants 12/13 (§3 F3).
- **Shortening `ps` bounds.** A slow-but-finishing 30 s `ps` at priority 31 is on record (§1.3). A shorter bound would abstain passes that today succeed, and an abstaining pass decides nothing.
- **RFC 6298 adaptive bounds** (axis 06 L7, WEAKENED). With async waits the bound only sizes a worker's life. Fixed bounds plus bounded reap suffice.
- **A SIGCHLD reaper.** Same theft as `waitpid(-1)` (§3 F2). Registry polling plus the exit wake give the same latency.
- **Skipping the probe while the drip is open; counting `probe-timeout` as no-verdict.** These are admission semantics, the A4 remainder, superseded by B3's deadline override.
- **An in-process `proc_pidinfo` lstart** (`band.py:74-93` shows the ctypes pattern) to remove the per-spawn `ps`. A worthwhile follow-up, but not needed for the bound, and it touches the (pid, lstart) identity contract (§10 #12 in `store.py:530-532`).
- **Multiple decision loops.** Rejected (axis 02 skeptic L2; claim/fence discipline).

## 14. Conviction, risks, open questions

**Conviction 70%** that B2, as specified, bounds every pass at 15-40/core and that the bound is measured.

**Per stage.**
- **S1 (90%).** Each piece fixes a measured defect: §1.2, and §3 F2 as a precondition. S1.c is the missing measurement.
- **S2 (60%).** The mechanisms are sound and semantics-preserving. Their payoff at priority 31 is **unmeasured**: 0 cohort passes since the reload (§1.5). Their strongest justification is that B3's guarantee needs an enforced `P_max`, not a currently measured loss.

**What would move conviction.**
- The first post-S1 cohort's `passes.jsonl`. If `ph.plan` and `ph.dispatch` p99 are a few seconds, S2's value is tail-only.
- B1's arms at 40/core.

**Risks.**
1. Thread or loop races. Mitigation: workers are pure, inputs are copied, results are consumed only on the loop thread, AST guard T15.
2. Leftover `waitpid(-1)`-style theft from a future `Popen` site. Mitigation: T15 plus the `unowned-zombie` event.
3. Silent test bypass from the `subprocess.run` patch migration (§9). Mitigation: the migration is part of S1.a's diff, and T1 proves the new seam.
4. A shared probe verdict admitting on a stale memory reading. Mitigation: rule 5 ("started after the last token", one use, 20 s). Today's per-member probe also cannot see a boot that starts about 10 s after its admission.
5. A page lost on a kill during the queue window. Mitigation: flush on clean exit, and the latch semantics are unchanged.
6. `passes.jsonl` volume. Mitigation: the 4 MiB cap plus one generation (about 16 h).
7. A compound stall can still exceed 3 minutes. Mitigation: bounded at about 210 s (E) and visible.
8. Deploy needs a restart. Mitigation: the boundary restart only.

**Open questions.**
- Q1. The per-phase split of a priority-31 cohort pass. Answered by S1.c on the first cohort.
- Q2. How long does a kernel `ps` stall last at priority 31? `orphans` lifetimes in `passes.jsonl` answer it.
- Q3. Mint latency at priority 31 (H: 1-3 s). The `slow` field answers it.
- Q4. Does `lr-page.sh` really take tens of seconds? S2.e's worker can log the sink duration in the `report-error`/`page` path for B6.

## Appendix: commands run (all read-only; scratch files under `/tmp/b2meas/`)

| Command | Established |
|---|---|
| `git log --oneline -12`; `git log --oneline HEAD..main`; `git diff --stat HEAD main -- scripts/limit-recover/ scripts/lib/capacity-admit.sh bin/claude-accounts` | Base commit; no drift in touched files |
| `git show --stat 6841626b4`; `git merge-base --is-ancestor 6841626b4 main` | The 457c166ed9d6 change and its scope |
| `grep 457c166ed9d6 ~/.claude/autonomy/backlog.jsonl` (python field dump) | Claimed 13:35Z, done 14:15:41Z, evidence `6841626b4` |
| `python3 -I /tmp/b2meas/gaps.py ~/.reso/limit-recover/recon/band.log`, plus a per-pid split | §1.1 table |
| python scan of `recon/events.jsonl` (abstain rows; Counter since t ≥ 1792480997) | §1.2, §1.5 |
| `cat ~/.reso/limit-recover/recon/heartbeat`, `watchdog.state`, `readout.line`, `mode`; `tail -3 restarts.jsonl` | §1.3; daemon pid 5233 started 16:04:56Z, mode `act` |
| `sysctl -n vm.loadavg hw.ncpu` | 258.60, 272.73, 149.33 at the readings; 10 cpus |
| `/usr/bin/python3 -I -c '…inspect.getsource(subprocess.run)…'`; `/usr/bin/python3 -V` (3.9.6) | Unbounded post-kill wait |
| `/usr/bin/python3 -I /tmp/b2meas/killwait.py` | 6.29 s red control |
| `/usr/bin/python3 -I /tmp/b2meas/steal.py` | `waitpid(-1)` theft: `poll()` 0 vs 9 |
| `/usr/bin/python3` ps timing loop (3 samples); `/usr/bin/python3 -I /tmp/b2meas/merged_ps.py` | §1.4; S1.d equivalence |
| python read of `recon/sessions/*.json` (open records); `recon/cohorts/next3-7d-1792497600.pages.act.json` | 4 PARKED-REBOOT; 15 latched pages and mails |
| `ls -la /tmp/kitty-*`; `ps -o pid,pri,command -p $$` | 1 kitty socket; my shell at PRI 31 |
| `cd scripts/limit-recover && TMPDIR=/tmp PYTHONDONTWRITEBYTECODE=1 /usr/bin/python3 -m unittest lr_recon.tests.test_step_per_child lr_recon.tests.test_midpass_progress lr_recon.tests.test_admit` | Baseline 40 OK; `git status` clean |
| `sed`/`grep`/`awk` of `__main__.py`, `clock.py`, `act.py`, `observe.py`, `plan.py`, `admit.py`, `report.py`, `store.py`, `types.py`, `census.py`, `band.py`, `lr-recon-watchdog.sh`, `capacity-admit.sh`, `bin/claude-accounts`, `tests/rig/*` | Every file:line above |

Nothing was typed into a pane, signalled, loaded, unloaded or edited outside this file and `/tmp/b2meas/`.

## Review — efficacy-under-permanent-load

Adversarial review, 2026-10-20 ~18:00-18:40Z, worktree at `28b25a119`. Read-only. My scratch scripts are under `/tmp/b2rev/`. The lens: does B2 bound recovery time at 15-40 per core with every lane at PRI 31, and does any new wait, bound or gate assume that load falls?

**Verdict: NEEDS-CHANGES. Adjusted conviction 50% (design: 70%).**
- Stage 1 holds up and should land.
- Stage 2 bounds the *pass* but, as specified, can leave the *attempt* unbounded. Three of its new constants are fixed wall windows, and each one has to be longer than an interval that grows with load (the pass head):
  - `PROBE_FRESH_S` 20 s;
  - `PLACE_ANSWER_TTL_S` 120 s;
  - the 60 s budget, measured from pass start.

  When a window is shorter than that interval, admission or placement stops. Nothing is counted, so the drip cannot open, and nothing pages.
- §5's P formula also leaves out the per-record children. So "≈210 s compound" is not a cap.

### R.1 What I verified and found to hold

- **The bound reported for a ps timeout is the configured bound, not a measurement.** `"timed out at %.0fs" % t` prints the configured bound `t = min(bound, left)` (`observe.py:136-145`).
  - So when "ps budget spent" follows one try, that try's wall time was at least 85 s against a 30-37 s bound. That leaves 48-55 s or more outside `communicate`'s timeout (E: arithmetic over `observe.py:83-87`, `:136-140`).
  - `/usr/bin/python3 -I /tmp/b2rev/gap_abstain.py` finds the same 4 abstains, at the same t as the four largest pid-4459 gaps (193, 119, 115 and 98 s). §1.2's alignment is confirmed.
- **Cadence now (M, same script).** pid 5233: n=1380, p50 6 s, p90 7 s, p99 17 s, max 36 s. Its p99 has grown from the 12 s that §1.1 reports.
- **F2 (the theft) is confirmed** at `act.py:399-415`. The `_CHILDREN` poll comes first and the `waitpid(-1)` loop second.
- **Rule 2 cannot livelock.** `facts.merge` keeps the first writer's `observed_at` (`facts.py:95-109`), so re-writing the same fact every pass does not re-trigger rule 2.
- **A composer read that fails ("unknown") is bucketed exactly like one never made.** See `census.py:236-241` and `observe.py:450-451`. This matters for R.3 item 4a.
- **Band of worker-thread children (M, my shell, not launchd).** `/usr/bin/python3 -I /tmp/b2rev/thread_band.py` => child from the main thread `pri 31`, child from a worker thread `pri 31`. Re-check this once under the plist.
- **The Popen constructor at load ~215 takes 2-6 ms** (M: `/tmp/b2rev/spawn_time.py`, 10 samples for each of 3 argv). The post-kill attribution in §1.2 is plausible, but it was not measured during a stall.

### R.2 Findings

**F-A (HIGH, S2.c). The shared probe can admit nobody, and the drip cannot rescue it.**

The mechanism, from the design's own S2.c code:
- `probe_kick` runs only at `_dispatch` entry.
- `begin_pass` sets `inline_left = min(15, max(0, pass_clock.left()))`.
- `_usable` requires the verdict to have landed ≤ 20 s before use.
- `probe-pending` returns *before* the refusal bookkeeping (`admit.py:310-316`).

**Case 1, deterministic.**
1. The pass is at or past 60 s elapsed when it enters dispatch, so `inline_left = 0` and nothing is waited inline.
2. Any verdict carried from the previous pass is at least as old as this pass's head (≥ 60 s), so it is unusable.
3. The probe kicked now lands after the loop has finished. By the next dispatch it is again ≥ 60 s old.
4. So every probe-gated candidate reads `probe-pending`, on every pass, for as long as heads stay at 60 s or more.

Today's code probes synchronously at `admit.py:310` and admits or counts within that same pass.

**Case 2, load-coupled.** This is a cohort's straggler: 1-2 candidates with probe latency L above the 5-10 s inline waits.
- The verdict is consumed `head(N+1)` plus the tail after it lands, and it is usable only if that is ≤ 20 s.
- Both the head and L grow with load.

**In both cases nothing escapes.**
- `probe-pending` is never counted toward `DRIP_AFTER` (`admit.py:56`, `:312-316`). So the drip never opens, although it is the module's "bound holds at any load" (`admit.py:22-26`).
- `page_due` is never raised.
- No event is written.
- §7's row "a timeout counts toward the drip as today" is therefore refuted: a verdict counts only if it is consumed within 20 s of landing.

**The regime is real.** Trusted passes over 50 s exist at PRI 31:
- pid 4459 has a 77 s gap and a 57 s gap with no abstain (M: `gap_abstain.py`, top gaps against the abstain list);
- §1.3 records a `ps` of 30 s that finished;
- the ps budget admits about 84 s of tries that finish.

It is rare at today's load without a cohort: pid 5233 has 0 of 1380 gaps ≥ 45 s (M: `/usr/bin/python3 -I /tmp/b2rev/gap_hist.py`). It is **unmeasured** with a cohort and at 40/core. A failure that is rare but total and silent is what the premise forbids.

**F-B (HIGH, S2.b). The 120 s `--place` answer TTL is shorter than the design's own P.**
- §5 estimates P at about 210 s. An answer that lands early in a long pass is more than 120 s old at the next `_plan`, so it is dropped and re-asked. If passes stay long, it is never applied.
- A drop is neither a miss (`misses` counts rc 124/126 only, `plan.py:52`) nor an event that pages.
- Its movers stay DETECTED, which `_invariant` skips (`__main__.py:1574-1577`). So nothing reports them.
- Separately, `_plan` returns before the lane loop when there are no movers (`__main__.py:1001-1003`). A call that has landed is then neither consumed nor cleared.

**F-C (HIGH, S2.d). The 60 s budget is measured from pass start.** When the non-deferrable phases spend it (ps up to about 92 s, composer reads, the place inline wait, own), dispatch drops to one *visit* per pass. Four consequences:
- **Head-of-line blocking.**
  - `units` counts records that passed `may_actuate`.
  - The oldest record comes first (`__main__.py:1223-1226`). If it is refused after that point, it still uses up the unit. The refusals are claim-held (`:1248-1268`), the pacer, boot-slots, or `probe-pending`.
  - So every other record is deferred on every pass for as long as heads stay at 60 s or more.
- **Starvation.** `_draft_snapshots` and `requester_mails` have no per-pass minimum, so they are deferred forever while the pass is over budget.
- **B3.** The guarantee `ceil(k/D)·T_att` (REPORT.md:430) assumes D starts in one pass. One start per pass adds up to (D−1)·P_max, about 5 × 3.5 min (E).
- **Throughput.** Each deferral pays the head again, and the head is what made the pass long. This rebuilds the one-admission-per-pass brake that A4 removed (`admit.py:10-16`), exactly when load is high.

**F-D (MED-HIGH, §5). P is not bounded independently of n.**
- **Composer reads are not budgeted.**
  - One read per limited session that has no open record or sits in `DRAFT_READ_SUBSTATES` (`__main__.py:665-690`, `:693-713`), issued per session at `:324`. Each costs up to 7 s.
  - So n = 20 during a kitty stall costs 140 s in the census alone (E).
- **Per-record `ps` on the serial path:**
  - `_alive` runs `proc_lstart` with a 40 s bound on a foreign claim (`__main__.py:129-130`, `store.py:394`, `:498`). §5 counts the claim check as 7 s (`_argv_of` only).
  - `_disk_take` reads its own lstart once per slot write (`admit.py:415`).
  - **`_own_and_charge` reads its own lstart on every act pass** (`__main__.py:1059-1062`), which §2's inventory misses.
  - `spawn` reads the new child's lstart (`act.py:335`).
- **Effect on the numbers.** A unit's worst case is therefore ≥ 165 s, not ≈130 s (E: §5's sum with `_alive` at 42 s). T22 as specified contains none of these n-dependent terms, so it would pass while the real bound fails.

**F-E (MED, wiring that the design leaves undefined).**
- **`_async_landed` is never defined for stage 2.** If it is level-triggered on "a call is done", then an unconsumed call makes `wait_for_change` return on every tick, giving back-to-back passes at PRI 31 on a box at 21-27/core (M: `sysctl -n vm.loadavg`). Two ways a call stays unconsumed:
  - F-B's early return;
  - a verdict that lands when no candidate is left, so `_land` never runs.
- **`PassClock.left()` with budget 0 is unspecified.** If it returns 0 − elapsed, then the documented rollback knob `LR_RECON_PASS_BUDGET_S=0` zeroes every inline wait and puts the daemon permanently in F-A case 1.

**F-F (LOW-MED, S1.a).**
- **`_run_reaped` bounds only the time after the timeout.** The Popen constructor (fork, then the blocking errpipe read until exec) is still unbounded.
  - The repo's own pattern (`bin/claude-accounts:836-847`, a thread joined at `PS_JOIN_S`) bounds the whole call.
  - The risk is low (constructor 2-6 ms, M above). But §1.2's split between constructor and kill-wait is E, not M.
- **More stuck children during a kernel stall.** With the budget no longer eaten by the kill-wait, `_ps_read`'s second try now starts. So a kernel stall parks 2 `ps` per abstained pass.
  - The process table can absorb that: 1074 of `kern.maxprocperuid` 10666 (M: `sysctl`; `ps -axo user=`).
  - Forking more readers into the same kernel path may prolong the stall (H).

### R.3 Required changes

1. **S2.c: a progress guarantee.**
   - a. Kick the shared probe at pass start, right after `act.reap_children()` (`__main__.py:1663`), whenever a limited PRE-MOVE or RELAUNCHED record is open. Its latency then overlaps the head.
   - b. Let the first probe-gated candidate of each pass that has no usable verdict wait for the in-flight call up to the probe's own bound: 30 s (`admit.py:78-80`) plus `REAP_GRACE_S`. This applies whatever `pass_clock.left()` or `PROBE_INLINE_PASS_S` says. It restores today's "at least one verdict is decided per pass".
   - c. Replace the 20 s landed-age rule with "started ≥ `last_admit_wall` and started ≥ this pass's start". The age is then at most one pass by construction, at any load. A wall cap, if wanted, comes from `passes.jsonl` and is never below the enforced pass cap.
   - d. After K consecutive `probe-pending` passes for a cohort, count one refusal toward `DRIP_AFTER`. Write a `probe-pending` event on the first one, like `place-pending`.
   - e. Tests:
     - **T13b** (fake wall): one candidate, probe L = 25 s, head 30 s → admitted or drip-admitted within ≤ 4 passes. Red on the design as written.
     - **T13c**: over budget at dispatch entry → one verdict reaches `decide`. Red as written.
2. **S2.b: freshness by pass, not by wall.**
   - Drop rule 3's 120 s wall TTL. An answer is applied at the first `_plan` after it lands, so it is at most one pass old by construction. Rules 1-2 carry correctness.
   - Consume landed calls before `if not mvs: return 0` (`__main__.py:1002-1003`).
   - If any drop by age stays, count it as a miss and log it.
   - Test: fake pass of 150 s, place L = 10 s → PLANNED on the next pass. Red as written.
3. **S2.d: a budget that does not throttle admissions.**
   - a. Defer only once `spawned ≥ 1 and over`, counting `n` (`__main__.py:1219`, `:1326`), not visits. Cap past-budget visits (for example at `PACE_BURST`). Test: the oldest record is claim-held every pass and the pass is over budget at entry → the second record still spawns. Red as written.
   - b. Measure the budget over the deferrable phases only, or start its clock at `plan`. A slow census must not, alone, cut admissions to one per pass.
   - c. Give `_draft_snapshots` and `requester_mails` the same "≥1 per pass" minimum. Extend T17 and T19 to five consecutive over-budget passes.
   - d. State the B3 interface: records past `W_soft` are exempt from deferral. Otherwise B3's bound gains a (D−1)·P_max term.
4. **§5: bound the n-dependent terms, or state them.**
   - a. Add a per-pass, per-socket breaker for composer reads. After the first timed-out read on socket S, the remaining reads on S that pass return "unknown" with no child. The buckets are identical to those of a timed-out read (`census.py:236-241`).
   - b. Replace loop-side `ps -o lstart` with an in-process `proc_pidinfo(PROC_PIDTBSDINFO)`, falling back to `ps` when that read fails.
     - M: `/usr/bin/python3 -I /tmp/b2rev/lstart_pidinfo.py` matched `ps -o lstart=` (TZ=UTC) on 40 of 41 user pids, in 0.6 ms for all 41. The one miss returned "", which is where the fallback applies.
     - This removes `act.py:335`, `__main__.py:130`, `admit.py:387` and the self reads from the serial path.
     - At minimum, apply S2.g's `_self_lstart` cache to `__main__.py:1061` and `admit.py:415`.
   - c. Restate §5's unit cost and P with these terms. Extend T22 to n = 20 limited members, with composer reads at their bound and one foreign claim per record.
5. **Wiring.**
   - `_async_landed` is edge-triggered: set when a worker completes, cleared at pass start.
   - `Admission._land()` runs every pass.
   - `PassClock.left()` is +inf when `budget_s == 0`. Add a test that `LR_RECON_PASS_BUDGET_S=0` with stage 2 on keeps the 10 s place and 5 s probe inline waits.
6. **S1.a.**
   - Record the Popen constructor's time (`spawn_s`) separately in `_note_child` and `passes.jsonl`, so §1.2's attribution becomes measured.
   - Use the whole-call thread join (`bin/claude-accounts:836-847`) if `spawn_s` ever shows seconds.
   - While ≥ N orphans of the same `argv0` are alive, skip the in-pass retry: one try per pass. Never block `ps` outright, since a census that never runs recovers nothing.

### R.4 Out of this lens, for the owners

- **A single refusing verdict can now count 3 refusals in one pass**, which opens the drip on one memory reading instead of three. That is the capacity reviewer's call.
- **Two timeouts on the serial path already read as negative verdicts**, against REPORT G2. R.3 item 4b would remove both:
  - `_alive` reads a `ps` timeout as dead, so a live foreign claim is stolen (`store.py:394-396`);
  - an lstart that timed out records `""`, and the actuator then reads as dead (`types.py:626-628`).

## Review — correctness-and-safety

Adversarial review, 2026-10-20 ~18:30-19:30Z, worktree at `28b25a119`. Read-only; my scratch scripts are under `/tmp/b2review/`.

The lens: can B2 strand a recovery, double-move or overcommit an account, lose a draft or a page, split-brain, break an invariant, or break an existing test?

I read the efficacy review above first. Its F-A to F-F are not repeated here; I cross-reference them only where a fix interacts.

**Verdict: NEEDS-CHANGES. Adjusted conviction 45% (design: 70%; efficacy review: 50%).**
- Stage 1 is safe to land once S.3 items 10-11 are folded in.
- Stage 2 as specified has four defects the efficacy review does not cover:
  - a wedged worker silently strands its lane, or every first turn (C1);
  - the "movers that arrived mid-call" call over-places an account (C2);
  - one refusing memory reading opens the drip (C3);
  - latched pages are lost on every restart (C5).

### S.1 Verified and holding

- **Citations.** I re-read about 60 of the design's file:line citations at `28b25a119`, and all match. Examples:
  - `act.py:394-415`;
  - `admit.py:216-238`, `:264-333`, `:363-420`;
  - `plan.py:290-397`, `:499-534`;
  - `report.py:681-700`;
  - `__main__.py:997-1082`, `:1132-1327`, `:1652-1853`;
  - `lr-recon-watchdog.sh:105-116`.

  One slip: `report.py:862-864` is docstring. The latch-on-result code is at `:895-908`.
- **Baseline (M).** `cd scripts/limit-recover && TMPDIR=/tmp PYTHONDONTWRITEBYTECODE=1 /usr/bin/python3 -m unittest discover -s lr_recon/tests -t .` => `Ran 628 tests in 13.846s`, `OK`.
- **F2 reproduced independently (M).** `/usr/bin/python3 -I /tmp/b2review/steal.py` => `waitpid(-1) reaped (98826, 9)` / `owner poll() reads 0` / `control poll() reads 9`.
- **S1.a's mechanics hold (M: `inspect.getsource` under `/usr/bin/python3` 3.9.6).**
  - `run()` does `process.kill(); process.wait()`, and the wait has no timeout.
  - `Popen.send_signal` polls first (bpo-38630), so `_run_reaped` killing an already-exited child is a no-op. That is safe.
- **Registered-only reaping is complete for the package (M).**
  - `grep -n "Popen\|os.system\|posix_spawn\|os.fork\|check_output" lr_recon/*.py` finds only `clock.py:372`, `plan.py:379`, `__main__.py:529` and `act.py:315`, besides `run_bounded`.
  - There is no `preexec_fn` and no `close_fds=False` (grep). So forking from the loop while worker threads run cannot deadlock, and cannot leak a pipe end into another child.
- **Removing `waitpid(-1)` also removes a latent overwrite.** This is a positive side effect.
  - An actuator that exits between the `_CHILDREN` loop and the `waitpid` loop (`act.py:399-415`) gets its real code from `waitpid`.
  - But its Popen's next `poll()` reads 0 (ECHILD), and the end-of-pass reap re-writes `EXIT_CODES[pid] = 0`.
- **`--place` writes nothing.** `apply_assignments` only stamps counts (`bin/claude-accounts:6540`, `:4527-4540`). So abandoning or killing a place call is restart-safe, as §7 says.
- **Rule 1 protects drafts.**
  - HOLD-DRAFT is not a mover (`plan.py:255-267`).
  - The census reads the composer of DETECTED, WAIT_* and PLANNED records before `_plan` (`__main__.py:665-690`, `:324`).
  - HOLD-DRAFT releases only when the census reads no draft (`settle.py:395-404`, `census.py:236-241`).
  - So a stale answer can never put PLANNED over a draft. A deferred snapshot (S2.d) can delay the page's quote, but cannot lose the draft itself.
- **New heartbeat keys are safe.**
  - `types.from_dict` ignores unknown keys (`types.py:184-191`, used by `fence.py:85-94`).
  - The watchdog's regex needs `"KEY":` with its opening quote (`lr-recon-watchdog.sh:107`).
- **§9's migration list is complete.** `test_step_per_child.py` is the only test file that patches `subprocess.run` (M: grep over `lr_recon/tests/`).

### S.2 Findings

**C1 (HIGH, strand; S2.a-c). A wedged worker is never abandoned. Single-flight turns one stuck call into a permanent, silent block.**
- **What is bounded.** `_run_reaped` bounds only the wait on the child. The rest of the worker is unbounded:
  - the Popen constructor's errpipe read (efficacy F-F);
  - `tempfile.mkdtemp` and the movers/kwork writes in `plan.place` (`plan.py:301-308`).
- **Place.**
  - A call that never completes stays in `ctx.place_calls[lane]`. `_start_place` therefore never runs for that lane again (the §S2.b code is `if call is None and lane_mvs`).
  - Its movers stay DETECTED, which `_invariant` skips (`__main__.py:1574-1579`) and which has no max age (`types.py:119-134`).
  - `place-pending` is written once. Nothing pages.
- **Probe.**
  - `probe_kick` starts no probe while `probe_call is not None`, and only `leave_active` clears that.
  - So every probe-gated first turn reads `probe-pending` for as long as the cohort is open, uncounted. Efficacy F-A shows the drip cannot rescue that. Owed prompts are never delivered.
- **Today the same wedge is loud and self-healing.** It blocks the loop, the watchdog convicts it (condition 4), and launchd restarts it. Async makes it quiet and permanent.
- **§7's "a stuck call ends at 122 s"** holds for the child, not for the call.

**C2 (HIGH, overcommit; S2.b). The "movers that arrived mid-call" call starts before the consumed placements are charged.**
- **Order of operations.**
  - In §S2.b, `_start_place(ctx, lane, rest, …)` runs inside the lane loop, right after `placed.update(got)`.
  - `plan.apply` runs after the loop (`__main__.py:1046`).
  - `--assign-many` runs only in `_own_and_charge` (`:1082`).
- **What `--place` sees.**
  - It sizes an account as `KMAX − kwork − phantoms` (`bin/claude-accounts:6516-6517`, `:6565-6583`).
  - Its `placed_w` is per call (`:6640-6641`).
  - The census kwork does not yet count movers that have not moved.
- **So the `rest` call sees the seats the consumed answer just filled as free.**
  - Example (E): account A has 3 free seats. Call 1 places m1-m3 on A. The `rest` call places m4 on A too. That is 4 movers on 3 seats, past KMAX.
  - Today m4 is asked on the next pass, after the charge, and sees 0 free seats.
- This breaks the rank → assign → rank order of invariant 16 (`plan.py:10-11`), which §S2.b says it keeps.

**C3 (HIGH, gate semantics; S2.c). A refusing verdict is reused per member and counted per member, so one memory reading opens the drip.**
- **The mechanism, from the design's own code.**
  - On refusal, `decide` increments `refusals[cohort]` and returns (`admit.py:311-315`). The verdict is cleared only in the admission tail.
  - The next member's `shared_probe` returns the same verdict while it is ≤ 20 s old.
  - Member 4 in the same pass finds `run == DRIP_AFTER` (3, `admit.py:56`) and is admitted as `admit:drip` (`:316-326`).
- **Today** the drip needs 4 independent `cc_capacity_probe` readings.
- **The shape is common.** Four probe-gated candidates in one pass is how a cohort starts: pace burst 6 (`admit.py:51-54`), pacer 3 per account.
- **Effect.** Under real memory pressure, the first dispatch pass of every cohort boots one session on a single refusing reading.
- This contradicts §10's "No gate semantics change", and T14(d) encodes it. The efficacy review deferred it to the capacity owner (R.4). It is a safety regression, so it belongs to this lens.

**C4 (MED-HIGH, cross-process capacity; S2.c). Rule 5 sees only this daemon's own admissions (`last_admit_wall`).**
- The probe's in-flight term counts every caller's tokens (`capacity-admit.sh:1629-1630`). Those tokens are files under `${CC_ADMIT_STATE_DIR:-~/.claude/autonomy/capacity-admit}/tokens` (`:830-832`).
- A verdict up to 20 s old cannot see a token that `cc-lr move`, `handoff-fire` or the dispatcher minted after it started. Under efficacy R.3.1c the verdict can be up to one pass old.
- Today the window is one probe's runtime: 2.6-3.9 s at PRI 31 (§1.4). E: the window grows about 5x to 20x.

**C5 (MED-HIGH, pages; S2.e). Latched pages are lost on every restart, and one wedged sink holds back every page behind it.**
- **No clean exit exists.** §7 says "clean exits flush ≤ 10 s", but `lr_recon` installs no signal handler (M: `grep -rn "signal.signal\|SIGTERM" lr_recon/*.py` => only a regex at `settle.py:82-85`).
  - Two paths end the process without running `daemon()`'s `finally` (`__main__.py:1850-1853`):
    - `launchctl kickstart -k`, which is the deploy path (`lr-restart-at-boundary.sh:41`);
    - the watchdog's `kill -TERM` (`lr-recon-watchdog.sh:75`).
  - Every queued page was already latched by `_once` (`report.py:693-700`), so it is never sent.
- **Ordering.** One FIFO pager, at up to 55 s a page (`report.py:34-38`), puts a SPLIT-BRAIN or ESCALATED page behind every queued MAX-AGE or DELTA page. E: 64 × 55 s ≈ 59 min.
- **A wedged pager.** If the pager wedges in a sink (C1's mechanism), every page waits until the queue fills.
- **Today** a kill loses at most the one page in flight.

**C6 (MED, boot-slot double occupancy; S2.g).**
- **The snippet reads our own live slot as dead.** `return not want or want == _self_lstart()` returns False whenever the cached self read is "". A `ps` timeout returns "" (`store.py:542-546`).
- **Today's code keeps such a slot live:** `not cur` → True (`admit.py:387-388`).
- **What follows.**
  1. `_disk_take` wipes the slot and gives it to a second sid (`admit.py:401-418`).
  2. Two sids now share one directory, and the first `release` removes it (`admit.py:442-454`).
  3. `cc-lr move` then counts one boot fewer than are in flight.
- **A cached "" is never retried.** `act._SELF_LSTART` does retry (`act.py:511-515`).

**C7 (MED, added load; S2.c and efficacy R.3.1a). The probe kick fires for records that never reach `decide`.**
- The kick condition is "any open limited record in PRE-MOVE or RELAUNCHED". That includes WAIT_RESET and WAIT_SLOT records, which wait for hours and never reach `decide` (`act.choose` returns None for them, `act.py:571-576`).
- With `_usable` expiring at 20 s, the result is a fresh `cc_capacity_probe` every ~20-25 s for the whole wait. Each probe is a bash with ~35-40 children (axis 06 L6).
- E: 150-180 probes per hour, about 5,000-7,000 processes per hour, on a box at 15-40 per core, for no decision.
- Not active right now (M): the 4 open records are all `idle PRE-MOVE PARKED-REBOOT`.

**C8 (MED, split-brain; pre-existing, on B2's seam). A timed-out lstart read steals a live driver's claim.**
- **The path.**
  - `_alive` reads a timed-out lstart (`proc_lstart` → "", `store.py:542-543`) as dead (`__main__.py:129-130`).
  - `claim_take` then returns `stolen-dead` over a live foreign driver (`store.py:393-396`).
  - It runs on the serial path through `hold_claim` (`act.py:522`) and `take_ownership` (`store.py:567`).
- **Why it matters.**
  - This is the 3e929a81 double-driver shape the claim exists to prevent (`act.py:499-506`).
  - It reads a timeout we impose as a negative verdict, which the binding premise forbids.
- **B2's part.** B2 neither causes nor worsens it: the bound is still 40 s, and the steal now comes sooner instead of after the kill-wait. But B2 owns this seam (`run_bounded` → `proc_lstart`), and its stated principle ("unknown, retry") is violated here. The efficacy review lists it under R.4.

**C9 (LOW-MED, switch flips; S2).**
- **In-flight calls survive a flip.** §7 says they "are dropped on the next pass", but the §S2.b code only `continue`s into the sync path. `ctx.place_calls`, `adm.probe_call` and `adm.verdict` all survive.
  - After an off → on flip within 120 s, an answer older than the sync path's newer WAIT can be applied to a record that is still a mover. Rule 1 passes, because the attempt is the same.
- **Mixed-mode passes.** `stage2_on()` stats `async.off` on every call (`run_pass`, `_plan`, `_dispatch`, `_report`, `_own_and_charge`). So a flip mid-pass gives a mixed-mode pass.

**C10 (LOW, robustness and existing tests).**
- **False `unowned-zombie` events.** A worker's child that has exited but has not yet been waited on is Z with `ppid == getpid()`. It is in no registry, because in-flight `_run_reaped` processes are not registered.
- **A thread-start failure crashes the pass.** `RuntimeError: can't start new thread`, raised from `AsyncCall.__init__`, propagates out of `_run_pass`.
- **`_note_child` can mask the real exception.** It runs as `_note_child(popenargs[0], …)` inside a `finally`. An `IndexError` there (args passed by keyword) would replace the caller's `TimeoutExpired`.
- **Missing `Ctx` defaults break existing tests.** `Ctx.__init__` must set `pass_clock` (no budget), `place_calls`, the assign memo, `async_on`, `runner` and `passlog`. Otherwise about 25 direct test calls hit AttributeError: `M._plan`, `_dispatch`, `_draft_snapshots` and `_own_and_charge` on `M.Ctx(...)` (M: grep over `lr_recon/tests/`).

**C11 (test power).**
- **T6's mutant can survive** ("drop `detach()` → zombie").
  - CPython's `Popen.__del__` puts a dropped Popen whose child is still running onto `subprocess._active`.
  - `_cleanup()` then reaps it at the next Popen construction (M: `inspect.getsource`).
  - So T6 must make its check with no Popen between the child's exit and the check, or assert registry membership instead.
- **T14(d) asserts C3's behaviour** and must be inverted.

**C12 (LOW, measured; S2.f). The shared ledger's prune can drop rows the phantom memo still counts on.**
- **The prune.** `ASSIGN_PRUNE_LINES` is 400. A prune keeps the newest half and swaps the file with `os.replace` (`bin/claude-accounts:3812`, `:4367-4371`). The memo's rows can be up to 120 s old.
- **Why it matters.** Phantoms are what carry "what this box fired seconds ago" (`:4528-4529`).
- **At today's rate it does not bind.** `~/.claude/logs/account-assignments.jsonl` holds 208 rows over 06:54-17:39Z: 183 from the reconciler and 25 from `handoff-fire` (M: python Counter).
- **A cheap trigger closes it anyway:** re-assert when the ledger's inode has changed since our last write.

### S.3 Required changes

1. **C1: a deadline for every `AsyncCall`.**
   - The deadline is start + the child's bound + `REAP_GRACE_S` + 10 s: place 132 s, probe 42 s, page 67 s.
   - Past it, the loop abandons the call:
     - place goes through `keep_waits` as rc 124;
     - the probe counts as `probe-timeout`, toward the drip, as today.
   - Write an `async-wedged` event (lane or kind, and age), count it in the heartbeat and in `passes.jsonl`, and page once at 3.
   - Test: a manual runner never completes → once the deadline passes, a new call starts, and the record is placed or refused within 2 passes. Red as written.
2. **C2: no same-pass `rest` call.**
   - Delete the same-pass `rest` start. The next pass's `call is None and lane_mvs` path asks mid-call arrivals, and it runs after this pass's `--assign-many`.
   - Test: A has 3 free seats; m1-m3 are consumed onto A and m4 arrives mid-call → no `--place` call is made before `assign_many`. Red as written.
3. **C3: one verdict decides one member.**
   - A verdict decides exactly one member, whether it admits or refuses: clear it on refusal too. The drip then opens after `DRIP_AFTER` independent readings, as today.
   - Invert T14(d): 4 candidates and one refusing verdict → 1 refusal counted, 3 `probe-pending`, no `admit:drip`.
   - This is compatible with efficacy R.3.1b-d (one verdict guaranteed per pass; counted pending passes).
4. **C4: a box-wide token check in `_usable`.**
   - Also require that no file in the tokens dir has an mtime later than the verdict's start. That is one in-process `os.scandir`, with no child.
   - Efficacy R.3.1c (freshness by pass) needs this subject-relative companion.
   - Test: a token appears after the verdict starts → the verdict is not used.
5. **C5: pages survive a restart and a wedged sink.**
   - Make the queue durable, with one of:
     - write each page to `recon/outbox/<t>-<n>.json` before enqueueing it, unlink it after the sink returns, and re-enqueue leftovers at startup (at-least-once: a restart may duplicate a page, never lose one);
     - at minimum, a SIGTERM handler that raises `SystemExit` on the main thread, so `finally: flush(10)` runs inside launchd's exit timeout.
   - Deliver SPLIT-BRAIN, ESCALATED, IMPOSSIBLE, WAKE-FAILED and daemon pages inline, or on a priority lane.
   - Deliver inline when the oldest queued page is more than 67 s old (a wedged pager).
   - Put `pages_queued` in the heartbeat, so the boundary restart can wait for it.
   - Test: enqueue a page, then SIGTERM → the page is sent after restart.
6. **C6: own-slot check.**
   - For our own pid: `me = _self_lstart(); return not want or not me or want == me`.
   - Cache only a non-empty read (the `act.py:511-515` pattern), and reuse the cache at `admit.py:415` and `__main__.py:1061`.
   - T21 gains a case: a failed self read keeps our slot live.
7. **C7: kick only when a decision follows.**
   - Kick only when a record will reach `decide` this pass (`act.choose(...)` is in `FIRST_TURN` and `may_actuate` is ok), or when one read `probe-pending` on the previous pass.
   - The same applies to efficacy R.3.1a's pass-start kick.
   - Test: a cohort waits in WAIT_RESET for 10 passes → 0 probes. Red as written.
8. **C8: an unknown lstart is not a dead holder** (on B2's seam; pre-existing).
   - `proc_lstart` returns a distinct "unknown" on timeout.
   - `_alive` returns True on "unknown". It returns False only when `os.kill(pid, 0)` raises `ProcessLookupError` or the lstart differs.
   - Test: a foreign claim whose lstart read times out → `held`, not `stolen-dead`.
   - If the owner rules this out of B2, file it as a blocker before stage 2. It does not block stage 1.
9. **C9: one mode per pass.**
   - Read `stage2_on()` once per pass into `ctx.s2`.
   - On an on → off edge, clear `ctx.place_calls`, `adm.probe_call` and `adm.verdict`.
   - T23 also flips the switch mid-cohort.
10. **C10: robustness and existing tests.**
    - Register in-flight `_run_reaped` processes (an `_INFLIGHT` set) and leave them out of `unowned-zombie`. Better still, require a zombie to persist for 2 passes.
    - `_thread_runner` catches `RuntimeError` and completes the call with an error.
    - `_note_child` is wrapped so it never raises.
    - `Ctx.__init__` sets every new attribute: `pass_clock = PassClock(0)`, with `left()` = +inf when the budget is 0 (as efficacy R.3.5 also requires).
11. **C11: test power.**
    - Rewrite T6 as described in C11.
    - Every new rule in items 1-7 gets its mutant ("Green in both arms").
12. **C12 (optional).** Add the ledger-inode term to the S2.f memo key, with a T20 case.

### S.4 Commands run (all read-only; scratch files under `/tmp/b2review/`)

| Command | Output used |
|---|---|
| `TMPDIR=/tmp PYTHONDONTWRITEBYTECODE=1 /usr/bin/python3 -m unittest discover -s lr_recon/tests -t .` | `Ran 628 tests in 13.846s`, `OK` |
| `/usr/bin/python3 -I /tmp/b2review/steal.py` | the theft, reproduced (S.1) |
| `/usr/bin/python3 -I -c` with `inspect.getsource` of `subprocess.run`, `Popen.send_signal`, `Popen.__del__` and `_cleanup` | S1.a's mechanics; C11 |
| `/usr/bin/python3 -I /tmp/b2review/probe_model.py` | A model of §S2.c's rules on a fake wall (40 passes each). Head 2-25 s with a 3 s probe: 40 of 40 admitted. Head 25 s with a 12 s probe, or head 65 s: 0 admitted. Confirms efficacy F-A independently |
| python read of the `recon/events.jsonl` abstains, plus `band.log` lines 66-67, 271-272, 311-312 and 1214-1215 | §1.2's alignment confirmed |
| python read of `recon/sessions/*.json` | 4 open records, all `idle PRE-MOVE PARKED-REBOOT`. C7's kick condition is false right now |
| python read of `~/.claude/logs/account-assignments.jsonl` | 208 rows: 183 reconciler, 25 handoff-fire (C12) |
| `grep`/`awk` over `lr_recon/*.py`, `lr_recon/tests/*.py`, `bin/claude-accounts`, `capacity-admit.sh`, `lr-recon-watchdog.sh` and `lr-restart-at-boundary.sh` | every file:line above |

Nothing was typed into a pane, signalled, loaded or edited, apart from this section and the files under `/tmp/b2review/`.
