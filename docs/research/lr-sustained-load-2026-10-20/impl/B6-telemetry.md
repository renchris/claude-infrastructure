# B6: telemetry so the next incident is legible (implementation design)

**Verdict: BUILD.** Conviction 80%. Estimated 1,050 LOC: about 560 of code and 490 of tests.
**Hard dependencies:** none. B1, B2 and B3 consume this design (see §11).
**Operator steps:** none are needed to build or land it. Activating it on the running daemon takes a
restart, either the next natural one or an optional quiet-moment reload (§10).

**Labels.** *Measured* means a named command was run read-only on this machine on 2026-10-20 between
17:30Z and 17:50Z, at load1 256-265 on 10 CPUs (25.6-26.5 per core). *Estimated* names its method.
*Hypothesis* is unverified.

**Code citations.** They are to the worktree at `28b25a119`. `git diff --stat 28b25a119 main --
scripts/limit-recover bin/cc-lr` is empty (measured), so the lines are also current `main`
(`6fdf87eca`).

---

## 0. Summary

- **What it is.** One new bounded log, `recon/telemetry.jsonl`, written by the reconciler daemon
  alone, plus one readout, `cc-lr status --rail [--since 1h] [--json]`.
- **What the log records:**
  - per-phase pass timings;
  - a per-child ledger (every `run_bounded` child: count, sum, max and timeouts per label, so
    `probe_s`, `place_s` and `ps_s` come for free);
  - a per-pass count of every gate refusal, by gate and reason, including the four refusal paths
    that are silent today;
  - each record's time in each state, with on-disk dwell that survives a restart;
  - per-record latency stamps: death, detect, first attempt and engaged;
  - actuator wall time;
  - the base priority of every rail process, read through libproc;
  - kitty's task and main-thread priority;
  - a runnable-thread census by **base** priority. That census is the positive control REPORT §5
    step 3 requires beside every reading.
- **What it never does:**
  - No decision reads it. A lint test pins this.
  - It forks nothing. Every read is either in memory or a libproc syscall.
  - It never raises into the loop (a guard, then self-disable after 20 faults).
  - It does not grow the record-write count: the record-side fields change only when the record's
    state changes, and that is when the record is already rewritten.
- **Cost** (measured on this box at ~26 per core, from priority 31):
  - 70 µs of CPU per 552-byte row;
  - 1.5 µs per base-priority read;
  - 10-16 ms of CPU per full-box thread census (4,836-4,848 threads).

  Estimated total: under 0.05% of one core.
- **Why it is worth building.** Measured today, after the band fix:
  - The daemon at priority 31 still abstained 4 times on a 30-37 s `ps` timeout (07:40Z, 08:19Z,
    08:30Z, 11:06Z). Only the failures are visible; the distribution under them is not.
  - Four `cc-dispatch --decide` processes sat at base priority 4 for 33 min to 5 h 42 m.
  - Fifteen of 17 cohort files are rewritten every pass, including cohorts from 2026-10-05.

  The REPORT's own open questions are the same class of gap:
  - "How does a 7-14 min pass split…? The heartbeat has no per-phase timings" (REPORT.md:514);
  - "no base-priority census exists at ≥ 28/core" (gap-4:248);
  - "admit-refused is logged only when its reason changes" (02-timeline-forensics caveats);
  - "Whether P1/P2 admissions were drip or a probe answer cannot be told from disk" (same).

---

## 1. What is on disk today, and what the incident could not answer

| Question an incident asks | Today's artifact | Gap | Evidence |
|---|---|---|---|
| How long was each pass, and where did the time go? | `heartbeat` keeps `max_step_gap_s` (a lifetime max) and `progress`. `band.log` has one line per pass with no duration | No pass start or end, no phase split. Axis 02 bracketed passes "by the last row written in each pass", lower bounds marked `>=` | `clock.py:202-312`; `02-timeline-forensics.md` §7 caveats; REPORT.md:514 |
| How slow is `ps`, `--place` or the probe at the rail's band? | `place` events carry `dur` (`__main__.py:1020-1036`). The probe has no timing (`admit.py:216-238`). `ps` is visible only when it fails (`abstain`) | No distributions. A 37 s `ps` at priority 31 shows up only as an abstain | `tail events.jsonl` => 4 `abstain ps degraded … timed out at 30-37s` after 07:23Z, with `band.log` reading `pri=31 ok` at each (measured) |
| How many times did gate G refuse, for which reason? | `admit-refused` and `claim-held` events are written only when the reason **changes** (`__main__.py:1252,1274`) | Count unknowable. Four refusal paths write **nothing**: `may_actuate` (`__main__.py:1243-1247`, 14 reasons at `act.py:438-479`), C's quiet grace (`:1237-1242`), wake pacer and pane-unseen (`:444-449`), and empty argv (`:1298-1300`) | Axis 02 §7: "a refusal that repeated across passes shows up once"; "cpu brake minutes … inferred from no change in reason plus no spawn" |
| Was an admission a probe answer or a drip? | `_admit` returns `"admit"`/`"admit:drip"` (`admit.py:323-333`), but `_dispatch` drops it on success (`__main__.py:1286`) | Not on disk | Axis 02 F4: "P1 cannot be decided" |
| How long did each record sit in each state? | `close["seen"]` lists states **without times** (`__main__.py:962-971`). Cohort `age_s` is since `wait.since` or detection, not since entering the state (`report.py:252`) | Time in state unknowable after the fact | `report.py:245-278` |
| What is the detect→first-attempt and detect→engaged distribution? | The DoD line gives a p95 only for all-ENGAGED cohorts (`report.py:390-400`). Records keep only the latest per sid | No first-attempt stamp at all, and G (§5) is stated on `t_first` | `python3 -I` over `recon/sessions/*.json` => 12 of 138 records have both `detected` and `engaged`; 2026-10-20 values 4,885-17,481 s (measured) |
| What band were the rail's children in? | `band.log` has the daemon only (`band.py`). The poller logs `ps -o pri` (current, decayed) only on `--move-kick` (`lr-reset-poller.sh:259-262`) | No band for actuators, handoff-fire, move workers or the poller tick | REPORT §3.1 needed six axes of manual `ps -M` sampling |
| What was kitty's band, and the box's band mix? | Nothing | The overnight kitty-at-4 class (B8) and band saturation are unknowable after the fact | gap-4:248 "no base-priority census exists at ≥ 28/core"; axis 04 L6 |
| What killed or restarted the daemon, and in which phase? | `restarts.jsonl` has `{t,pid,lstart}` only (`__main__.py:1796`) | No code identity, no previous phase | REPORT §6 A6: "It is not on disk" |

---

## 2. Design principles (binding on the implementer)

- **P1. Write-only.**
  - No decision in `lr_recon` reads `telemetry.jsonl`, `close["tel"]` or the heartbeat's new keys.
    REPORT §5 G1: "Telemetry may record it."
  - Lint test T11 enforces this.
  - The load average is recorded in `box` and `pass` rows, and read by no gate.
- **P2. Zero forks.**
  - All data comes from what the pass already holds: `snap.procs` from the one `ps` read, the
    records, and child durations measured inside `run_bounded`.
  - Process priorities are read with `proc_pidinfo` syscalls, the `band.py` mechanism.
  - A fork from a loaded box is the cost being diagnosed (REPORT §3.1).
- **P3. One writer.**
  - Only `daemon()` creates a `Telemetry`. It holds the reconciler's flock (`__main__.py:1809-1817`).
  - `--once`, tests and any `Ctx` without `telem` write nothing. The canary and the rig write their
    own roots.
- **P4. Bounded.**
  - Each row is ≤ `LINE_MAX` = 4,096 bytes and goes out in **one** `os.write` on `O_APPEND`
    (`store.append_bounded`, `store.py:588-601`). That covers the "append atomicity ends at the
    buffer" lesson.
  - The file is ≤ 8 MiB plus one `.1` generation.
  - Quiet passes fold into a `quiet` row every 300 s.
- **P5. Guarded.**
  - Every public `Telemetry` method runs inside `_guard`: an exception increments `faults` and
    returns.
  - At 20 faults telemetry turns itself off for the process and writes one `telemetry-off` event
    to `events.jsonl`.
  - A telemetry defect can never stop a pass.
- **P6. Unknown is not ok** (lesson "fail-safe mimics healthy").
  - An unreadable priority is `null` and renders `?`, never `31`.
  - An empty window renders `rail: NO DATA`, never `ok`.
  - A stale log while the heartbeat is fresh renders `rail: NO DATA — telemetry stopped`.
- **P7. Clocks.**
  - Durations use `time.monotonic()`. On macOS it does not advance during sleep, so a lid-close is
    not counted as pass time.
  - Stamps (`t`, `close["tel"].at`, `first`) are wall time **at the write point**, never the
    pass-scoped `now`. That avoids B7's defect class: the pass `now` can be minutes old by the end
    of the pass (REPORT §3.4).
- **P8. Python 3.9.**
  - The daemon runs `/usr/bin/python3` (`com.reso.lr-reconciler.plist` ProgramArguments) =>
    `Python 3.9.6` (measured). The `ps` args of pid 5233 show the Xcode 3.9 framework.
  - `python3` on PATH is 3.11.4 (measured), so the suite must also run under `/usr/bin/python3`
    (rule "Deployment interpreter ≠ yours").
- **P9. Kill switches that need no restart.**
  - `recon/telemetry.off` (a file, checked once per pass) pauses telemetry.
  - `LR_RECON_TELEMETRY=off` (env, read at start) never builds it.
  - `LR_RECON_TELEMETRY_BOX=off` skips only the thread census.
- **P10. Guarded import.** `try: from lr_recon import telemetry except ImportError: telemetry =
  None`, the same pattern as `band` (`__main__.py:44-47`). The live layer is a per-file symlink farm
  (`install.sh:855-869`), and `deploy-live` links a new `*.py` only on its next tick
  (`deploy-parity-assert.sh:572-573`). A restart inside that window must not crash-loop the daemon.

---

## 3. Schema: `recon/telemetry.jsonl`, v1

Each row is one compact JSON object (`store.dumps`). Keys are in insertion order with **`t` first**,
so a reader can window rows by slicing `{"t":<num>,` without a full parse. Every row carries
`t` (wall epoch, 0.1 s), `k` (kind), `v` (1) and `pid`.

### 3.1 Row kinds

| `k` | When | Fields beyond `t,k,v,pid` | Typical size |
|---|---|---|---|
| `start` | once, at daemon start, before the first pass | `lstart`; `code{fp,mtime}` (sha1[:12] of sorted `(name,size,mtime)` over `lr_recon/*.py`, plus the newest mtime); `prev{pid,progress_age,phase,phase_age,seq}` (the **previous** daemon's heartbeat, read before it is overwritten); `band` (own base priority) | ~300 B |
| `pass` | a pass that is **not quiet** (rule in §3.3) | `seq`, `mode`, `dur` (s), `gap` (s since the previous pass ended), `slept`, `l1`, `open`, `active` (open records in the "moving" bucket, `report.bucket`), `placed`, `ph{phase: s}`, `ch{label:[n,sum,max,timeouts]}`, `gates{"gate:reason": n}`, `admits{why: n}`, `spawns{actuator: n}`, `band{self,min,roles{role:[n,min]},low[[role,pid,pri]],unk}`; optional `abstain`, `degraded` (only when the set changed), `exc` (repr ≤ 200), `tel` (this row's own cost, ms), `trunc` | 550-900 B (552 B measured for a representative row) |
| `quiet` | every 300 s, folding the quiet passes since the last row | `seq0`, `seq1`, `n`, `dur[p50,max]`, `gap_max`, `ph_max{}`, `ch{label:[n,max,timeouts]}`, `gates{}`, `band_min`, `low[]` | ~400 B |
| `box` | every 60 s while any record is open, else every 300 s; self-throttles on cost | `l1`, `ncpu`, `run{base_pri: n}` (**runnable** threads by **base** priority, `pth_priority`), `thr`, `procs` (readable), `of` (total pids), `kitty{pid:[task_base,main_base,main_cur]}`, `rail{role:[n,min,oldest_s]}`, `adj{role:[n,min,oldest_s]}`, `cost` (s) | ~350 B |
| `rec` | a record's state changed (birth included), after flap coalescing | `sid` (8), `rid`, `from` ("" at birth), `to`, `dwell` (s in `from`), `att`; optional `flaps` (suppressed repeats), `det`, `death` (birth row only) | ~200 B |
| `close` | a record that was **seen open** became terminal | `sid`, `rid`, `kind`, `out`, `via`, `src`, `dst`, `att`, `death`, `det`, `first`, `first_by`, `eng`, `dwell{state: s}` | ~500 B |
| `act` | an actuator's exit was scored (`_derive`) | `sid`, `rid`, `a` (actuator or `adopted`), `rc` (null = unknown), `wall` (spawn→exit-seen, s, from the UTC `lstart`), `att` | ~180 B |

**State key**, as computed by `telemetry.state_key(rec)`:

| Record | Key |
|---|---|
| terminal | `"T:" + outcome` |
| escalated | `"ESC:" + phase + "/" + substate` |
| otherwise | `phase + "/" + (substate or "-")` |

**Death time.** `death` is parsed from `close["death"]` = `"<uuid>@<iso ts>"` (`census.py:70-75`).
`fromisoformat` after `Z`→`+00:00` (Python 3.9 rejects a bare `Z`). It is null for idle moves.

**Child labels.** They come from `clock.child_label(argv)`:

| Child | Label | Source |
|---|---|---|
| `/bin/ps …` | `ps` | `observe.read_ps`, `store.proc_lstart:530-546` |
| `kitten @ …` | `kitten` | `observe.kitty_ls:235` |
| `bash -c "… cc_capacity_probe …"` | `probe` | `admit.py:224-230` |
| `… cc_capacity_token_mint …` | `mint` | `admit.py:243-262` |
| `claude-accounts --place …` | `claude-accounts --place` | `plan.py:308-327` |
| any other argv | `basename(argv[0])`, plus ` --flag` when argv[1] starts with `--` | |

Labels are capped at 40 characters and 24 distinct labels per pass; the rest fold into `other`.

**Rail roles.** One compiled regex over `ProcRow.args` finds them:

| Role | Matched text in the process args |
|---|---|
| `actuator` | `lr-recon-act`, the `act.wrap` token (`act.py:34`) |
| `poller` | `lr-reset-poller.sh` |
| `move-batch` | `lr-move-batch.sh` |
| `move-worker` | `lr-move-worker.sh` |
| `fleet` | `lr-fleet.sh` |
| `handoff` | `lr-handoff.sh` |
| `hf` | `handoff-fire.sh` |
| `resume` | `lr-fire-resume.sh` |
| `transplant` | `lr-transplant.sh` |
| `placer` | `claude-accounts --place` |

The adjacent role is `dispatch` (`cc-dispatch`), rendered separately (§13 F2). The first match by
position wins, so the actuator wrapper, whose args name its child script later, is `actuator`.

### 3.2 Record-side fields (`rec.close["tel"]`, one namespaced dict)

`{"st": "<state key>", "at": <wall when it entered st>, "dwell": {"<state>": s, …}, "first": <wall of
the first recovery-actuator spawn>, "first_by": "<A|A-husk|B|R|C|C-retry>"}`.

- `close` is `Dict[str, Any]`, and `T.from_dict` ignores unknown keys and defaults missing ones
  (`types.py:184-191`). The field therefore loads under old code and survives a rollback.
- No existing `close` key collides. Measured with a grep over `lr_recon/*.py`: 33 distinct keys,
  none of them `tel`.
- `dwell` is capped at 24 keys, dropping the smallest, and values are rounded to 0.1 s. That bounds
  it at about 1.5 KB.
- It changes only on a state change or at first spawn, so `store.save_records`' memo
  (`store.py:145-189`) rewrites no extra record.

### 3.3 The quiet rule (volume control)

A pass is written as a full `pass` row when **any** of these holds:
- `abstain`, `exc`, or `seq == 1`;
- `dur ≥ 30 s`;
- `active > 0`;
- a spawn, an admission or a `rec` row this pass;
- any child timeout;
- the `degraded` set changed;
- a rail process read below 31.

Otherwise it folds into the running `quiet` aggregate, which is flushed every 300 s, or before the
next full row so rows stay time-ordered.

A record parked for days in `WAIT_RESET` or `HOLD-*` is "waiting/held", not "moving". It therefore
costs one `quiet` row per 5 min, not one row per pass. The `quiet` row still carries the gate counts.

### 3.4 Heartbeat additions (flat keys)

`T.Heartbeat` (`types.py:448-473`) gains `phase: str = ""`, `phase_at: float = 0.0` and
`pass_seq: int = 0`. A reader can then see **where a long pass is right now**: the pass row is
written only at its end, and a 14-minute pass is otherwise invisible until then.

The keys are flat and unique on purpose. The watchdog's `hb_num` is `sed 's/.*"KEY":…'`, a greedy
match whose **last** occurrence wins (`lr-recon-watchdog.sh:105-115`). A nested object holding
`"pid":` would corrupt `HB_PID`. Test T12 runs the watchdog's own sed against the new heartbeat.

---

## 4. Write points (file:line) and change sketches

### 4.1 New: `scripts/limit-recover/lr_recon/telemetry.py` (about 380 LOC)

```python
"""telemetry.py — REPORT lever B6 … (the §3 schema table goes here verbatim) …
WRITE-ONLY for the rail: no decision reads this file or close["tel"] (test NoDecisionReadsTelemetry)."""
from __future__ import annotations
import calendar, collections, hashlib, json, os, re, threading, time
from typing import Any, Callable, Dict, List, Optional, Tuple
try:
    from lr_recon import band
except ImportError:
    band = None  # type: ignore[assignment]
from lr_recon import clock, store
from lr_recon import types as T

V, FILE, OFF_FILE = 1, "telemetry.jsonl", "telemetry.off"
MAX_BYTES, LINE_MAX = 8 << 20, 4096
SLOW_PASS_S, QUIET_EVERY_S = 30.0, 300.0
BOX_ACTIVE_S, BOX_QUIET_S, BOX_COST_FACTOR = 60.0, 300.0, 60.0
FAULT_LIMIT, FLAP_WINDOW_S, DWELL_KEYS_MAX, FLOOR = 20, 60.0, 24, 31
FIRST = ("A", "A-husk", "B", "R", "C", "C-retry")  # == __main__.FIRST_TURN (settle.MOVE_ACTUATORS + C)
RAIL = (("actuator","lr-recon-act"),("poller","lr-reset-poller.sh"),("move-batch","lr-move-batch.sh"),
        ("move-worker","lr-move-worker.sh"),("fleet","lr-fleet.sh"),("handoff","lr-handoff.sh"),
        ("hf","handoff-fire.sh"),("resume","lr-fire-resume.sh"),("transplant","lr-transplant.sh"),
        ("placer","claude-accounts --place"))
ADJ = (("dispatch", "cc-dispatch"),)
_ROLE_RE = re.compile("|".join(re.escape(s) for _, s in RAIL + ADJ))
_ROLE_OF = {s: r for r, s in RAIL + ADJ}

def _guard(fn):                      # P5
    def run(self, *a, **kw):
        if self.off or self.paused: return None
        try: return fn(self, *a, **kw)
        except Exception as e:       # noqa: BLE001
            self.faults += 1
            if self.faults >= FAULT_LIMIT and not self.off:
                self.off = True
                _safe_event(self.paths, "telemetry-off", "%d faults; last %r" % (self.faults, e))
            return None
    return run

def state_key(rec): ...             # §3.1
def death_ts(rec) -> Optional[float]: ...   # §3.1, never raises
def lstart_epoch(s) -> Optional[float]:     # ProcRole.lstart is UTC (store.py:533, observe.py:46)
    try: return float(calendar.timegm(time.strptime(s, "%a %b %d %H:%M:%S %Y")))
    except (ValueError, TypeError): return None

class Telemetry:
    def __init__(self, paths, env=None, wall=time.time, mono=time.monotonic,
                 read_pri=None, census=None, kitty_pri=None, loadavg=os.getloadavg):
        e = os.environ if env is None else env
        self.paths, self.path = paths, paths.p(FILE)
        self.max = store._max_bytes_env(e, "LR_RECON_TELEM_MAX_BYTES", MAX_BYTES)
        self.box_on = e.get("LR_RECON_TELEMETRY_BOX", "on") != "off"
        self.wall, self.mono, self.loadavg = wall, mono, loadavg
        self.read_pri = read_pri or (band.base_priority if band else (lambda pid=None: None))
        self.census = census or (band.runnable_by_base if band else None)
        self.kitty_pri = kitty_pri or (band.main_thread if band else None)
        self.off = self.paused = False; self.faults = self.werr = 0
        self.seq = 0; self.cur = None; self.t_end = None
        self.quiet = None; self.last_degraded = (); self.flaps = {}
        self.next_box = 0.0; self.box_every = BOX_QUIET_S; self.rail = {}; self.kitty_pids = ()
        self.last_alert = ""

    # lifecycle — called by __main__ (P3: daemon only)
    def check_switch(self):          # NOT guarded: a stat per pass, P9
        self.paused = os.path.exists(self.paths.p(OFF_FILE))
    @_guard
    def start(self, prev_hb: Optional[dict]): self._row({"k": "start", ...})
    @_guard
    def pass_begin(self, slept: float = 0.0):
        self.seq += 1; m = self.mono()
        self.cur = {"t0": m, "gap": None if self.t_end is None else round(m - self.t_end, 2),
                    "slept": round(slept, 1), "ph": {}, "pn": "", "pt": m, "ch": {},
                    "gates": collections.Counter(), "admits": collections.Counter(),
                    "spawns": collections.Counter(), "recrows": 0, "active": 0, "band": None, "cost": 0.0}
        clock.set_phase("begin", self.seq)
    @_guard
    def phase(self, name: str):
        c, m = self.cur, self.mono()
        if c["pn"]: c["ph"][c["pn"]] = c["ph"].get(c["pn"], 0.0) + (m - c["pt"])
        c["pn"], c["pt"] = name, m
        clock.set_phase(name, self.seq)
    @_guard
    def child(self, label: str, dur: float, late: bool):        # clock hook (bound thread only)
        ch = self.cur["ch"] if self.cur else None
        if ch is None: return
        if label not in ch and len(ch) >= 24: label = "other"
        v = ch.setdefault(label, [0, 0.0, 0.0, 0]); v[0] += 1; v[1] += dur; v[2] = max(v[2], dur); v[3] += int(late)
    @_guard
    def gate(self, gate: str, reason: str): self.cur["gates"][("%s:%s" % (gate, reason))[:60]] += 1
    @_guard
    def admitted(self, why: str): self.cur["admits"][why[:40]] += 1
    @_guard
    def spawned(self, rec, which: str):
        self.cur["spawns"][which] += 1
        if which in FIRST:
            tel = rec.close.setdefault("tel", {})
            if "first" not in tel: tel["first"], tel["first_by"] = round(self.wall(), 1), which
    @_guard
    def observed(self, snap):         # right after observe(): rail band from the pass's own ps read
        t0 = self.mono(); roles, low, unk = {}, [], 0
        for row in snap.procs.values():
            if row.zombie: continue
            m = _ROLE_RE.search(row.args)
            if not m: continue
            role = _ROLE_OF[m.group(0)]; pri = self.read_pri(row.pid)
            n_min = roles.setdefault(role, [0, None, None]); n_min[0] += 1
            if pri is None: unk += 1; continue
            n_min[1] = pri if n_min[1] is None else min(n_min[1], pri)
            age = lstart_epoch(row.lstart); n_min[2] = max(n_min[2] or 0, round(self.wall() - age)) if age else n_min[2]
            if pri < FLOOR and len(low) < 5: low.append([role, row.pid, pri])
        me = self.read_pri(None)
        self.cur["band"] = {"self": me, "min": _min(me, *[v[1] for v in roles.values()]),
                            "roles": {r: v[:2] for r, v in roles.items()}, "low": low, "unk": unk}
        self.rail = roles; self.kitty_pids = tuple(int(s.rsplit("-", 1)[-1]) for s in snap.sockets)
        self.cur["cost"] += self.mono() - t0
    @_guard
    def note_states(self, records, active_of: Callable):   # just before store.save_records
        now = round(self.wall(), 1)
        for rec in records:
            k = state_key(rec); tel = rec.close.get("tel")
            if tel is None or "st" not in tel:
                if rec.terminal is not None: continue          # pre-B6 terminal: no row, no write
                tel = rec.close.setdefault("tel", {}); tel["st"], tel["at"] = k, now
                self._rec_row(rec, "", k, 0.0, birth=True); continue
            if rec.open and active_of(rec): self.cur["active"] += 1
            if tel["st"] == k: continue
            dwell = max(0.0, now - float(tel.get("at") or now))
            d = tel.setdefault("dwell", {}); d[tel["st"]] = round(d.get(tel["st"], 0.0) + dwell, 1); _cap(d)
            prev, tel["st"], tel["at"] = tel["st"], k, now
            if not self._flap(rec.sid, prev, k, now): self._rec_row(rec, prev, k, dwell)
            if rec.terminal is not None: self._row(_close_row(rec))
    @_guard
    def act_exit(self, rec, pr, rc):
        t0 = lstart_epoch(pr.lstart)
        self._row({"k": "act", "sid": rec.sid[:8], "rid": rec.record_id, "a": pr.argv_hash, "rc": rc,
                   "wall": None if t0 is None else round(self.wall() - t0, 1), "att": rec.attempt})
    @_guard
    def pass_end(self, summary: Optional[dict], exc: Optional[BaseException]):
        c, m = self.cur, self.mono()
        if c["pn"]: c["ph"][c["pn"]] = c["ph"].get(c["pn"], 0.0) + (m - c["pt"])
        dur = m - c["t0"]; s = summary or {}
        deg = tuple(sorted(s.get("degraded") or ()))
        full = (exc is not None or s.get("abstain") or self.seq == 1 or dur >= SLOW_PASS_S
                or c["active"] or c["spawns"] or c["admits"] or c["recrows"]
                or any(v[3] for v in c["ch"].values()) or deg != self.last_degraded
                or (c["band"] or {}).get("low"))
        if full:
            self._flush_quiet(); self._row(self._pass_row(c, s, dur, deg, exc))
        else:
            self._fold_quiet(c, dur)
            if self.quiet and m - self.quiet["m0"] >= QUIET_EVERY_S: self._flush_quiet()
        self.last_degraded = deg; self.t_end = self.mono()
        self.last_alert = _alert(dur, c)          # §6.4, consumed by _report next pass
        clock.set_phase("idle", self.seq)
    @_guard
    def box(self):
        now = self.mono()
        if not self.box_on or now < self.next_box or self.census is None: return
        t0 = self.mono(); cen = self.census() or {}
        kit = {str(p): [self.read_pri(p)] + list(self.kitty_pri(p) or (None, None)) for p in self.kitty_pids}
        cost = self.mono() - t0
        l1 = self.loadavg()[0]                     # RECORDED, never read by a gate (§5 G1)
        self._row({"k": "box", "l1": round(l1, 1), "ncpu": os.cpu_count() or 0, "run": cen.get("run"),
                   "thr": cen.get("thr"), "procs": cen.get("procs"), "of": cen.get("of"), "kitty": kit,
                   "rail": _roles(self.rail, RAIL), "adj": _roles(self.rail, ADJ), "cost": round(cost, 3)})
        base = BOX_ACTIVE_S if (self.cur and self.cur["active"]) else BOX_QUIET_S
        self.next_box = now + max(base, BOX_COST_FACTOR * cost)    # a 2 s census → every 120 s at least

    def _row(self, obj: dict):            # P4: t first, ≤ LINE_MAX, one os.write
        row = {"t": round(self.wall(), 1)}; row.update(obj); row.setdefault("v", V); row["pid"] = os.getpid()
        line = _bounded(row, LINE_MAX)    # drops ch beyond top 12 by sum, gates beyond 16, low beyond 5; else stub+trunc
        try: store.append_bounded(self.path, line, self.max)
        except OSError: self.werr += 1    # surfaced as "werr" on the next row that lands

def readout(paths, now, since_s, history=False) -> dict: ...   # §6
def render(d: dict) -> List[str]: ...
def main(argv=None) -> int:   # python3 -m lr_recon.telemetry readout [--since 1h] [--json] [--root DIR] [--history]
```

`_flap(sid, a, b, now)` suppresses a `rec` row when the same `(a,b)` pair was emitted for this sid
within `FLAP_WINDOW_S`. It counts the suppression and attaches `flaps: n` to the next row emitted
for that sid. The dict holds at most 256 sids, evicting the oldest. `_alert` is §6.4.

### 4.2 `scripts/limit-recover/lr_recon/band.py` (about 55 LOC)

Add after `base_priority` (`band.py:74-93`). `main` (`:147-160`) is unchanged, so `bin/cc-dispatch`'s
file-mode call keeps working.

```python
PROC_PIDLISTTHREADS, PROC_PIDTHREADINFO, TH_STATE_RUNNING = 6, 5, 1
class _ThreadInfo(ctypes.Structure):   # struct proc_threadinfo: 2×u64, 8×i32, char[64] (112 B)
    _fields_ = [("user", c_uint64), ("system", c_uint64), ("cpu_usage", c_int32), ("policy", c_int32),
                ("run_state", c_int32), ("flags", c_int32), ("sleep_time", c_int32), ("curpri", c_int32),
                ("priority", c_int32), ("maxpriority", c_int32), ("name", c_char * 64)]
def _threads(pid, cap=2048) -> List[_ThreadInfo]: ...          # PROC_PIDLISTTHREADS then PROC_PIDTHREADINFO each
def main_thread(pid) -> Optional[Tuple[int, int]]:             # (base, current) of the first thread
def runnable_by_base(max_pids=8192) -> Optional[Dict[str, Any]]:
    """proc_listallpids, then every readable process's threads; count RUNNABLE ones by BASE priority
    (pth_priority). Same-user only: root-owned processes are unreadable, so counts are LOWER bounds
    ("procs" of "of"). ps shows decayed CURRENT priority and under-counts the default band 1.05-6x
    (axis 04 R0.2), which is why this exists."""
    → {"run": {"4": n, "20": n, "31": n, …}, "thr": n, "procs": readable, "of": total}
```

The struct layout was verified by the measurement script: 4,836-4,848 threads were read with
`r == sizeof` (§8).

### 4.3 `scripts/limit-recover/lr_recon/clock.py` (about 40 LOC)

- **`Heartbeat.__init__`** (`clock.py:209-235`): add `self.phase = ""`, `self.phase_at = 0.0`,
  `self.pass_seq = 0`.
- **`snapshot()`** (`:237-251`): pass the three fields.
- **New method:**
  ```python
  def set_phase(self, name: str, seq: int) -> None:
      with self._lock:
          self.phase, self.phase_at, self.pass_seq = name[:24], self.clock.wall(), int(seq)
  ```
- **New module functions**, beside `step()` (`:321-339`), with the same bound-thread rule:
  ```python
  def set_phase(name: str, seq: int = 0) -> None:
      loop = _LOOP
      if loop is not None and loop[1] == threading.get_ident():
          loop[0].set_phase(name, seq)

  _CHILD_HOOK: Optional[Callable[[str, float, bool], None]] = None
  def bind_child_hook(fn) -> None: global _CHILD_HOOK; _CHILD_HOOK = fn
  def child_label(argv: Any) -> str: ...   # §3.1 labels
  ```
- **`run_bounded`** (`:349-361`), changed:
  ```python
  declare_child(float(timeout))
  t0, late = time.monotonic(), False
  try:
      return subprocess.run(*args, **kw)
  except subprocess.TimeoutExpired:
      late = True
      raise                                   # callers still see it (admit.default_runner, plan.place, …)
  finally:
      _note_child(args[0] if args else kw.get("args"), time.monotonic() - t0, late)
      step()
  ```
  `_note_child` returns at once unless a hook is bound **and** the caller is the bound loop thread.
  It swallows any hook exception.
- **Why here.** `run_bounded` is already the single choke point for every child the loop waits on,
  by design (`clock.py:332-337`). A new call site inherits the ledger, as it already inherits the
  step.

### 4.4 `scripts/limit-recover/lr_recon/types.py` (3 LOC)

`class Heartbeat` (`types.py:448-473`) gains, after `max_step_gap_at`:

```python
phase: str = ""
phase_at: float = 0.0
pass_seq: int = 0
```

### 4.5 `scripts/limit-recover/lr_recon/__main__.py` (about 50 LOC)

Every call goes through `_tel(ctx)`, which is `getattr(ctx, "telem", None)`. With telemetry off,
behaviour is byte-identical (§9 T9).

| Where | Change |
|---|---|
| `:44-47` | `try: from lr_recon import telemetry` / `except ImportError: telemetry = None`, beside `band` (P10) |
| `Ctx.__init__` `:93-127` | `self.telem = None`. Only `daemon()` sets it (P3) |
| `run_pass` `:1652-1657` | `tel = _tel(ctx); if tel: tel.check_switch(); tel.pass_begin(getattr(ctx, "slept", 0.0))`. Wrap the existing body in `try … except BaseException as e: exc = e; raise … finally: if tel: tel.pass_end(out, exc)` |
| `_run_pass` `:1665-1729` | Phase marks, each one line `_ph(ctx, "<name>")`. `observe` before `:1667`, then `tel.observed(snap)` after `:1674`. `facts` before `:1696`. `census` before `:1698`. `derive` before `:1702`. `ctl` before `:1710`. `plan` before `:1715`. `own` before `:1719`. `dispatch` before `:1720`. `report` before `:1723`. `save` before `:1725`. **`tel.note_states(ctx.records.values(), lambda r: report.bucket(r) == "moving")` immediately before `store.save_records` at `:1728`**, so the dwell write rides this pass's record write (§3.2) |
| `_abstain` `:1613-1649` | Nothing. `pass_end` sees `summary["abstain"]` and writes a full row with only the `observe` phase |
| `_derive` exit loop `:807-811` | `if tel: tel.act_exit(rec, pr, rc)` inside the loop |
| `_wakes` `:444-449` | Before `continue` at `:446`: `tel.gate("wake", "pane-unseen")`. Before `continue` at `:449`: `tel.gate("wake", _why)`, giving `pacer:<acct>` |
| `_plan` `:1014-1036` | After the `place` event: `if rc != 0: tel.gate("place", plan.PLACE_CAUSE.get(rc, "exit"))` |
| `_dispatch` `:1237-1242` (C grace) | `tel.gate("grace", "C")` before `continue` |
| `_dispatch` `:1243-1247` (`may_actuate`) | `tel.gate("may", why)` before `continue`. This was **silent** |
| `_dispatch` `:1248-1267` (claim) | `tel.gate("claim", why)` before `continue`. This counts **every** refusal; the event stays on change only |
| `_dispatch` `:1269-1285` (admission) | `tel.gate("admit", why)` before `continue`. `why` keeps `pacer:<acct>` and `probe-error rc=N` |
| `_dispatch` `:1286` | `tel.admitted(why)` (`admit`, `admit:drip`, `launcher-admitted`, `no-first-turn`) |
| `_dispatch` `:1298-1300` | `tel.gate("argv", "empty")` before `continue` |
| `_dispatch` after `act.spawn` `:1304-1311` | `tel.spawned(rec, which)`, which also stamps `close["tel"].first` for `FIRST` actuators |
| `_report` `:1466-1469` | `line = report.readout_line(…)`. `alert = tel.last_alert if tel else ""`. `if line and alert: line += " · ⚠ rail: %s → cc-lr status --rail" % alert` (§6.4) |
| `daemon` `:1806-1853` | Before `_startup` (`:1818`): `prev = _read_json_or_none(paths.heartbeat)`. After `bind_steps(hb)` (`:1824`): `if telemetry and os.environ.get("LR_RECON_TELEMETRY","on") != "off": ctx.telem = telemetry.Telemetry(paths); clock.bind_child_hook(ctx.telem.child); ctx.telem.start(prev)`. In the loop, keep `slept` on ctx (`ctx.slept = slept`, `:1828`). After `_band` (`:1837`): `if ctx.telem: ctx.telem.box()`. In `finally` (`:1850`): `clock.bind_child_hook(None)` |

`_ph(ctx, name)` is `t = _tel(ctx); t and t.phase(name)`. `_startup`'s claim restamp
(`:1790-1794`) is A6's concern and is not touched here. The `start` row's `prev.phase` will show
which phase a killed predecessor was in, which is A6's missing evidence.

### 4.6 `scripts/limit-recover/lr_recon/report.py` (about 8 LOC)

In `cohort_status` (`report.py:245-278`), each member gains two fields:
- `"in_state_s"`: `round(now - tel["at"], 1)` when `tel := r.close.get("tel") or {}` has `"at"`
  (spelled without `:=` for 3.9 style consistency), else `None`;
- `"first_attempt_s"`: `round(tel["first"] - r.timeline.detected, 1)` when both are present.

`age_s` keeps its meaning. A grep of `tests/`, `scripts/limit-recover/` and `bin/` found no consumer
of the cohort `age_s` field (measured).

### 4.7 `bin/cc-lr` (about 30 LOC)

- **Usage** (`bin/cc-lr:203-206`). After the `status --cohort` lines, add:
  `cc-lr status --rail [--since 1h|30m|90s] [--json] [--history] [--root DIR]`. Its description:
  "the reconciler's own telemetry: bands, pass and phase times, gate refusals by reason, records'
  time in state, detect→first-attempt and detect→engaged".
- **`cmd_status`** (`:2505-2529`). Add a `--rail)` case that consumes `--since`/`--json`/`--history`
  /`--root` and calls `cl_status_rail`.
- **New `cl_status_rail`**, next to `cl_status_cohort` (`:2459-2489`). It reuses `cl_recon_pkg`
  (`:3121-3127`) exactly as `cmd_accounts` does (`:3138-3139`):
  ```bash
  pkg="$(cl_recon_pkg)" || cl_die "cannot reach scripts/limit-recover/lr_recon; nothing was read" 2
  LR_STATE_DIR="$STATE" LR_RECON_ROOT="$RECON_ROOT" PYTHONPATH="$pkg${PYTHONPATH:+:$PYTHONPATH}" \
    python3 -m lr_recon.telemetry readout "${args[@]}"
  ```
  Return codes: rc 0 for ok/warn, rc 1 for NO DATA, rc 2 when unreadable. No outer `timeout`: the
  windowed read is 0.02 s (§8).
- **`cl_status_cohort`'s jq** (`:2476-2486`): add `(if (.in_state_s|type)=="number" then "in-state
  \(.in_state_s|floor)s" else empty end)` after `age`.

---

## 5. Retention and volume

| Regime | Rows | Size (estimated from §3.1 sizes × cadence) |
|---|---|---|
| Quiet day (nothing open) | 288 `quiet` + 288 `box` (+ `start`) | ≈ 0.22 MB/day => one 8 MiB generation ≈ 36 days |
| Active recovery | one `pass` per pass. Measured `band.log` line gap at priority 31: p50 10 s, p90 13 s, max 193 s (`band.log`, n=3,732), so at most ~360-700 rows/h × ~700 B, plus 60 `box`/h | ≈ 0.3-0.5 MB/h => a 10-h incident ≈ 3-5 MB |
| Standing WAIT/HOLD for days | `quiet` every 300 s (§3.3) | same as quiet |
| Worst case on disk | `telemetry.jsonl` ≤ 8 MiB + `.1` ≤ 8 MiB | 16 MiB. Raise it with `LR_RECON_TELEM_MAX_BYTES` |

For comparison, `events.jsonl` is 4,588,620 B live and its `.1` (8,388,572 B) rotated on Oct 5,
i.e. about 15 days per generation (`ls -la recon/`, measured). Telemetry keeps **at least one full
incident plus about two weeks** of quiet history under the same bound class. Records keep
`close["tel"]` indefinitely, as all record fields are kept today; 138 record files exist (measured).

---

## 6. The readout: `cc-lr status --rail`

This is the one readout an operator or an agent reads.

### 6.1 Output (default window 1 h)

The example is illustrative. Its band, box and kitty values are today's measured readings; the
pass, gate and record values are invented for the illustration.

```
rail: WARN — 1 child timeout (ps 1) · record db755a94 in PRE-MOVE/WAIT_SLOT 41m > W_soft 10m
window 60m to 17:40Z · daemon 5233 up 1h42m · heartbeat 3s · now: dispatch 12s (pass 81433)
band   self 31 · poller 31 · hf 31 ×2 · move-worker — · kitty 853 task 31 main 47 · adjacent: dispatch 4 ×8 (oldest 5h42m) ⚠
box    runnable by base priority 4:151 20:9 31:17 37+:1 of 4,848 threads (1,125/1,600 procs readable) · load1 263 (26.3/core, recorded only)
passes 41 full + 12 quiet rows (640 passes) · full p50 4.1s p90 9.8s max 41.0s · quiet max 3.2s · gap p50 8s
phases p90/max  observe 3.1/38.9 · derive 0.4/1.2 · plan 0.0/1.9 · dispatch 0.6/30.2 · report 0.3/0.9 · save 0.1/0.2
child  n p90 max timeouts  ps 82 2.0 37.0 1 · kitten 41 0.1 0.4 0 · probe 4 2.9 30.0 0 · claude-accounts --place 3 1.9 2.2 0
gates  may:process-live 40 · may:backoff 12 · admit:pace 3 · grace:C 4 · wake:pane-unseen 0 — admitted 5 (admit 4, admit:drip 1) · spawned A 2, C 3
open 2 db755a94 PRE-MOVE/WAIT_SLOT 41m (detected 2h41m ago; first attempt 2h30m ago) · 3e929a81 PRE-MOVE/PLANNED 4m10s (detected 6m12s ago; not attempted)
closed 7  death→detect p50 4s max 50m · detect→first p50 1m12s p90 3m40s max 9m · detect→engaged p50 4m p90 11m max 23m · actuator wall p50 3m p90 11m (A 2, R 1, C 4)
```

### 6.2 Sources

| Readout section | Source |
|---|---|
| `band`, `box` | `box` rows, plus the latest `pass` row's `band` |
| `passes`, `phases`, `child`, `gates` | `pass` + `quiet` rows in the window |
| `open` | `recon/sessions/*.json` with `terminal == null` (`close["tel"].at` and `first`; `timeline.detected`) |
| `closed` | `close` + `act` rows in the window |
| `daemon` | `heartbeat` (`pid`, `progress_wall`, `phase`, `phase_at`, `pass_seq`) |

With `--history`, the readout adds detect→engaged over **all** records on disk that carry both stamps
(today n=12, measured). This works before any `close` row exists.

### 6.3 Verdict (computed, never narrated)

Every threshold is display-only and can be overridden with `LR_RAIL_*`.

| Verdict | Conditions |
|---|---|
| `NO DATA` | No telemetry file. Or no row in the window. Or the newest row is older than `max(600 s, 2×QUIET_EVERY_S)` while the heartbeat `progress_wall` is under 180 s old ("telemetry stopped": the `telemetry-off` event or the off-file is named if present). Or the heartbeat is stale (daemon down: "rail unknown") |
| `WARN` | Any of the rows below |
| `ok` | None of the above, plus a positive line: rows N, newest row age |

`WARN` fires on any one of:
- an LR rail role, or `self`, read below 31 (`low` non-empty);
- `kitty` task or main-thread base below 31;
- a full pass `dur > 180 s` (`P_max`, REPORT §5);
- any child timeout;
- an open, non-`HOLD*`/`HELD*`/`WAIT_RESET` record whose time in state is over 600 s (`W_soft`);
- an open record not attempted (`first` absent) more than 2,580 s after detection (43 min, the G
  estimate in REPORT §5);
- telemetry faults or `werr` above 0;
- unknown bands (`unk > 0`), which read "band unknown for N rail processes", never ok.

Adjacent roles (`dispatch`) are flagged `⚠` on their line but do not set the LR verdict.

`--json` emits `{"verdict","reasons":[],"window_s","daemon":{},"band":{},"box":{},"passes":{},
"phases":{},"children":{},"gates":{},"admits":{},"spawns":{},"open":[],"closed":{},"telemetry":{"rows",
"files","faults","werr"}}`. These keys are stable for agents; B1's harness asserts on them.

### 6.4 The pointer on the operator line

`readout.line`, the one counted line `hooks/operator-readout.sh:711-733` shows while anything is
open, gains ` · ⚠ rail: <alert> → cc-lr status --rail` only on a measured anomaly in the last pass:
- a rail process below 31: `"move-worker 41234 pri 20"`;
- a pass over 180 s: `"slow pass 7m12s (observe 6m50s)"`;
- a child timeout: `"ps timed out"`.

It is empty otherwise, so the Stop hook's "a wrong line is worse than a missing one" contract
(`operator-readout.sh:709-710`) holds. The hook itself is unchanged.

---

## 7. Failure modes under permanent 15-40 per core, and how each is handled

| # | Failure | Handling | Test |
|---|---|---|---|
| F1 | A telemetry bug raises inside a pass | `_guard` swallows it and counts `faults`. At 20 faults: off for the process, plus one `telemetry-off` event. The pass result is unchanged | T9 |
| F2 | Disk full or EIO on append | `OSError` caught; `werr` increments and is shown on the next row that lands. No fsync, so no stall beyond the append `events.jsonl` already does per event | T10 |
| F3 | A row is too large (many gate reasons or labels) | `_bounded` keeps top-N `ch` by sum (12), `gates` (16) and `low` (5). If it is still over 4,096 B: a stub row `{"t","k","v","pid","seq","trunc":<bytes>}`. Always valid JSON, one `os.write` | T10 |
| F4 | Box census slow under a kernel-side stall (REPORT §3.3: a `ps` once came back after 1,226 s at load 330) | No fork: in-process libproc reads, so a starved exec cannot hold it. `next_box = now + max(60/300 s, 60 × cost)`. `cost` is recorded on every row. `LR_RECON_TELEMETRY_BOX=off` | T8 |
| F5 | libproc unreadable (root pid, race, ctypes missing) | `None` → `?`. `unk` is counted, and the readout says "band unknown", never ok (P6) | T7 + mutant M4 |
| F6 | `ps` degraded, so `snap.procs` is empty | `band.roles` is empty and `band.self` is still read. The readout shows "rail band not observed this pass (ps degraded)" | T7 |
| F7 | The pass `now` is minutes old by the end of the pass (B7 class) | Telemetry stamps use `wall()` at the write point. Durations use monotonic time | T4 (clock advanced inside one pass) |
| F8 | A state flaps across passes (e.g. PLANNED↔WAIT_DATA on placer non-answers) | `_flap` coalesces within 60 s and attaches `flaps: n`. Dwell still accumulates exactly | T5 |
| F9 | 138 pre-B6 terminal records load at startup | No `st` and terminal: skipped, so no row and no write. An open pre-B6 record: one birth row, with `at` = first sight (labelled as such in the readout) | T4 + mutant M6 |
| F10 | A record waits for days (WAIT_RESET to a weekly reset) | Quiet rule (§3.3): one `quiet` row per 5 min, not one row per pass | T6 |
| F11 | Restart mid-cohort | `close["tel"]` is on disk, so dwell continues. The `start` row has `prev.phase/phase_age` of the dead daemon. The first pass after a restart is always a full row (`seq==1`) | T4 |
| F12 | The new `telemetry.py` symlink is missing when the daemon restarts | Guarded import (P10). The daemon runs without telemetry, exactly as before | T13 |
| F13 | Heartbeat keys break the watchdog's sed or the fence's awk | Flat, unique keys. T12 runs the watchdog's own `hb_num` sed and the fence's awk over a rendered heartbeat | T12 + mutant M7 |
| F14 | Python 3.9 syntax or library drift | Suite also run under `/usr/bin/python3`, the deployment interpreter (P8) | T14 |
| F15 | Two writers (a `--once` beside the daemon; the canary) | Only `daemon()` builds `Telemetry`. The canary and the rig have their own `paths.root` (`types.py:220-246`) | T3 asserts `--once` writes no telemetry |
| F16 | The readout itself is slow or wrong under load | It runs in the caller's band (31 from a session). Windowed parse 0.02 s; full 7 MB parse 0.32 s (§8). Tri-state verdict, so no "ok" without rows | T15 |
| F17 | Telemetry becomes an input to a decision later (drift) | Lint T11: decision modules may not reference `telemetry`, `"tel"` or `last_alert`. G1's load lint (B1) allow-lists `telemetry.py` | T11 |
| F18 | Readout-line pointer misleads in a Stop hook | Emitted only on measured anomalies of the last pass. The hook still prints nothing on a stale heartbeat (unchanged) | T16 |

---

## 8. Cost at priority 31 (measured, this box, load1 256-265 on 10 CPUs)

| Instrument | Measurement | Command |
|---|---|---|
| `band.base_priority(pid)` | 1,000 calls in 1.5 ms of wall and CPU (≈1.5 µs each) | `/usr/bin/python3 -I /tmp/b6probe/cost.py <lr_recon dir>` |
| Base priority of every pid | 1,590-1,626 pids, 1,116-1,143 readable; CPU 3.5-4.7 ms; wall 3.5-217 ms (one cold first run) | same, run 6 times |
| **Runnable census by base priority** | 4,836-4,904 threads; wall 0.010-0.143 s; CPU 0.010-0.016 s; runnable by base `{4: 145-155, 20: 7-17, 31: 14-22, 37: 0-1}` | same, run 6 times |
| One `pass` row: dumps + size check + `O_APPEND` write | 552 B; 106 µs wall / 70 µs CPU | `/usr/bin/python3 -I /tmp/b6probe/row.py` (2,000 rows to `/tmp`) |
| Readout parse | 7.0 MB / 15,000 rows: full 0.315 s wall / 0.093 s CPU; a 1,000-row window by `t`-prefix slicing: 0.022 s | `/usr/bin/python3 -I /tmp/b6probe/parse.py` |
| kitty bands | kitty 853 (the `/tmp/kitty-853` socket): task base 31, main thread base 47 / current 47 / max 63, talk threads 31 | `band.py 853`; `/tmp/b6probe/thr.py 853` |

**Estimated total.** At about 10 passes/min: 10 × ~0.3 ms (laps, ledger, role scan, one row) +
12 ms box census per minute = about 15 ms of CPU per minute ≈ 0.025% of one core. It adds no fork,
no fsync and no extra record write. Each `pass` row carries `tel` (ms) and each `box` row `cost`,
so this claim is re-measured continuously in production, not asserted.

---

## 9. Test plan

New suite `scripts/limit-recover/lr_recon/tests/test_telemetry.py` plus
`tests/lr-recon-telemetry.bats`. All tests are hermetic: tmp roots, injected clocks, injected
`read_pri`/`census`, and `LR_KITTEN_BIN=/usr/bin/false` from `tests/__init__.py`.

Run them with:
- `cd scripts/limit-recover && python3 -m unittest lr_recon.tests.test_telemetry`
- **and** `/usr/bin/python3 -m unittest lr_recon.tests.test_telemetry` (3.9.6)

### 9.1 Red-before-fix controls

Each one is red on `main` because the information is not on disk.

| ID | Test | Red on main because… | Green after |
|---|---|---|---|
| **R1** | `GateRefusalsAreCountable`. Three passes. One PLANNED limited record is refused by `pace` each pass (Admission with an empty bucket and a frozen `wall`). A second record is refused by `may_actuate` `backoff` | On main, `events.jsonl` holds **1** `admit-refused` row and **0** rows for `backoff`. The asserted counts 3 and 3 are not recoverable from any on-disk artifact (the test reads only disk) | `cc-lr status --rail --json --root $tmp` => `gates["admit:pace"]==3`, `gates["may:backoff"]==3`. `events.jsonl` still holds exactly 1 `admit-refused` row (equivalence guard) |
| **R2** | `TimeInStateIsOnDisk`. Wall clock injected. Record DETECTED at 1000, PLANNED at 1010, WAIT_SLOT at 1310, PLANNED again at 1910 | On main, cohort status `age_s` = time since detect or wait.since. No per-state time exists | `close["tel"]["dwell"] == {"PRE-MOVE/DETECTED":10, "PRE-MOVE/PLANNED":300, "PRE-MOVE/WAIT_SLOT":600}`. `in_state_s` correct. 3 `rec` rows |
| **R3** | `PassSplitsIntoPhases`. Fake observe `run` sleeps 0.5 s inside `ps` (via `run_bounded` with the loop bound to a test heartbeat) | No artifact splits a pass | `pass` row `ph.observe ≥ 0.5`, `ch.ps[2] ≥ 0.5`, `sum(ph) ≈ dur` within 50 ms |
| **R4** | `FirstAttemptStamped`. Spawn C at wall 1100 for a record detected at 1000, engaged 1300, then CLOSED | No first-attempt stamp anywhere | `close` row: `det` 1000, `first` 1100, `first_by` `C`, `eng` 1300. Readout `detect→first` 100 s |
| **R5** | `RailBandSeen`. `snap.procs` holds `lr-move-worker.sh` pid 41234; `read_pri` returns 20 for it | No band for any child is recorded | `band.low == [["move-worker",41234,20]]`; readout verdict WARN |

### 9.2 Mutants that prove power

Lesson "Green in both arms": each mutant below must turn its test red.

| Mutant | Test that must go red |
|---|---|
| M1: `gate()` counts only when the reason changes (the events dedupe copied) | R1 |
| M2: dwell measured from `timeline.detected` | R2 |
| M3: the `run_bounded` hook called before `subprocess.run` | R3 |
| M4: `None` priority rendered as 31 | T7 |
| M5: `_guard` removed | T9 |
| M6: the pre-B6-terminal skip removed | T4 |
| M7: heartbeat gains a nested `{"pid":…}` key | T12 |
| M8: quiet rule removed | T6 (row count bound) |

### 9.3 Equivalence guards and the remaining tests

| ID | Test |
|---|---|
| T3 | `--once` and any `Ctx` without `telem` write no `telemetry.jsonl` |
| T4 | Restart: `close["tel"]` reloads and dwell continues. 5 pre-B6 terminal records produce 0 rows and 0 writes (`store._SAVED` unchanged). The clock is advanced inside one pass to show stamps are wall-at-write, not the pass `now` |
| T5 | Flap coalescing: 50 PLANNED↔WAIT_DATA flips within 60 s windows give at most 1 row per pair per window. `flaps` sums to the suppressed count; dwell is exact |
| T6 | A record held in WAIT_RESET for a simulated 24 h with 3 s passes gives ≤ 288 quiet rows + box rows, and 0 full rows after the first |
| T7 | Unknown band (`read_pri` returns None) => `unk>0`, readout "band unknown", never ok |
| T8 | Box throttle: `census` costs 2.5 s (injected), so the next box is ≥ 150 s later. `LR_RECON_TELEMETRY_BOX=off` gives no box rows |
| T9 | **Equivalence**: the same 3-pass fixture with `telem` None vs on. `summary`, `events.jsonl` and every record field except `close["tel"]` are identical. With a `census` that raises: the pass returns normally; after 20 faults, telemetry is off and there is one `telemetry-off` event |
| T10 | 200 distinct gate reasons give a row ≤ 4,096 B, valid JSON, top-16 kept. An append that raises `OSError` gives `werr` on the next row |
| T11 | **Lint**: `admit.py act.py census.py classify.py evidence.py facts.py capped.py drain.py fence.py phase.py plan.py settle.py store.py transcript.py observe.py` contain none of `telemetry`, `"tel"` or `last_alert`. In `__main__.py`, `close["tel"]` / `close.get("tel")` appear nowhere. Only `telemetry.py` and `report.py` (display) read `close["tel"]` |
| T12 | The watchdog's `hb_num` sed and the fence's `_lr_recon_progress_wall` awk, read from the scripts and run with real `sed`/`awk` over a heartbeat rendered with the new keys, give the same pid/progress/wall/progress_wall/step_due/child_bound_s/lstart as without them |
| T13 | With `telemetry` unimportable (`sys.modules` patch), `run_pass` and `daemon` setup work with `ctx.telem is None` |
| T14 | `tests/lr-recon-telemetry.bats` runs the suite under `/usr/bin/python3` and asserts the `Ran N tests` / `OK` lines. Assert the count, not just the absence of failures (lesson "Gate refusal ≠ gate result") |
| T15 | Readout on fixtures (generated in `BATS_TEST_TMPDIR`, never `*.log`, which `.gitignore:11` ignores). Empty root gives `NO DATA` rc 1. Fresh heartbeat with a stale log gives `NO DATA — telemetry stopped`. A WARN fixture gives each reason. `--json` keys are stable |
| T16 | `readout.line` gains the `⚠ rail:` suffix only when `last_alert` is non-empty. With `telem` None it is byte-identical to today |
| — | `shellcheck bin/cc-lr` bare, as the land gate runs it (lesson "Gate invocation is contract") |
| — | Existing suites that touch these files: `test_main`, `test_midpass_progress`, `test_clock`, `test_band`, `test_report`, `test_store`, `tests/cc-lr-status-verdict.bats`. They must stay green unchanged; T9 is the guard |

### 9.4 Under load

The hermetic suite cannot show the cost claim under the band mix. That is B1's harness. Its rig runs
the real daemon (`tests/rig/lr-recon-rig.sh:9-18`), so `telemetry.jsonl` lands in
`/tmp/lr-rig/state`. B1 asserts G from `close` rows (`first - det`), P_max from `pass.dur`, and reads
`box.run` and `band` as the positive control that the load was present (rule "Verify a cure under
its load").

---

## 10. Rollout, kill switch, operator steps

1. **Land.** One commit holds the code and tests. `deploy-live` links `lr_recon/telemetry.py` on its
   next tick (`deploy-parity-assert.sh:572-573` demands `lr_recon/*.py`). Check it with
   `ls -la ~/.claude/scripts/limit-recover/lr_recon/telemetry.py`. Until the daemon restarts, nothing
   changes: the running process holds the old code, and the import is guarded.
2. **Activation, optional and operator-run.** It only changes **when** data starts. Do it when no
   cohort is open: `cat ~/.reso/limit-recover/recon/readout.line` prints nothing. That respects A6
   (i): no restart mid-cohort. Then run:
   ```
   bash ~/.claude/scripts/limit-recover/lr-band-reload.sh --confirm lr-band
   ```
   This is the existing A1 reload. It reloads the reconciler and the reset poller and re-reads the
   band, and `band.log` is unchanged, so its check still parses. Otherwise the next natural restart
   activates telemetry.
3. **Verify (read-only):**
   ```
   tail -n 3 ~/.reso/limit-recover/recon/telemetry.jsonl     # a "start" row with the new pid, then "box"/"pass"
   cc-lr status --rail                                        # verdict line + sections
   cc-lr status --rail --json | jq '.verdict, .telemetry'
   ```
4. **Kill switch.** Pause without a restart with `touch ~/.reso/limit-recover/recon/telemetry.off`;
   resume with `rm -f ~/.reso/limit-recover/recon/telemetry.off`. Or skip only the box census with
   `LR_RECON_TELEMETRY_BOX=off`, or disable from start with `LR_RECON_TELEMETRY=off`; both env
   variables need a plist edit and a reload, so they are operator acts. Telemetry also self-disables
   after 20 faults.
5. **Rollback.** Revert the commit. Records keep an inert `close["tel"]` (ignored by old code,
   `types.py:184-191`). `telemetry.jsonl` stays on disk, inert. Nothing else changes.

---

## 11. Dependencies on the other items

| Item | Relation |
|---|---|
| B1 load harness | **Consumes B6.** G, P_max and T_att assertions read `close`, `pass` and `act` rows. The positive control is the `box` row. B1's G1 lint must allow-list `telemetry.py`'s `os.getloadavg()` (recorded only) |
| B2 bounded pass | **Should land after B6.** B6 answers B2's own open question, the per-phase split (REPORT.md:514), and gives a baseline. B2 renames or adds phases through `tel.phase()`. Both edit `_run_pass`, so sequencing avoids conflicts |
| B3 deadline override | **Benefits.** B3 records bypasses as `tel.gate("deadline", "bypass:<gate>")` and verifies its bound from `first - det`. If B3 needs a first-attempt time as a **decision input**, it owns an always-on field; `close["tel"]` is write-only (P1) |
| A6 restart safety | **Evidence for it.** The `start` row's `code.fp/mtime` and `prev.phase` test the "deploy-driven restart" hypothesis (REPORT §6). No code coupling |
| B7 pass-`now` audit | Aligned. B6 introduces no new `now - stamp` against the pass `now` (P7). B7's "advance the wall clock inside one pass" helper is T4's technique |
| B4 cheap place | Measured by B6 (`ch["claude-accounts --place"]`). No coupling |
| B5 kitty off critical path, C2 socket prompt | Measured by `act.wall` per actuator (T_att) and `ch.kitten`. Actuator-internal splits (kitty RTT, boot_s) belong to those items (§12) |
| B8 kitty hygiene | Measured by `box.kitty` (task and main-thread base) every 60-300 s, including overnight screen lock |
| A7 limited-cohort ruling | Its cost becomes countable: `may:plan-only` is one of the silent `may_actuate` reasons (`act.py:455-456`) |
| D1 repick ruling | The `recycle_repick` "stays" decision is in `handoff-fire.sh` (bash); D1 owns logging it (§12) |
| D2 warning-band shedding | Independent. D2's shadow log is its own; it can reuse the readout pattern |
| G2 self-recovery | Recoveries outside the reconciler are invisible to B6. If G2 is built, it needs its own bounded rows, and `--rail` can read them later |
| C1 credential flip | None |

---

## 12. Out of scope, and who owns it

- **Actuator-internal timings** (kitty RTT ring, `boot_s`, handoff-fire phase stamps;
  `10-proactive.md:351` "The handoff log has no per-phase timestamps"). These are bash actuators
  with their own bundles and actlogs, so they belong to B5/C2. B6 gives their wall time
  (`act.wall`) and band (`hf`, `handoff`, `resume` roles).
- **`recycle_repick` "stays" decision to disk** (REPORT B6 bullet 4). It lives in
  `handoff-fire.sh:15962-16130` and is D1's ruling.
- **The reset poller's tick durations.** The poller is bash; B6 shows its band and age (`rail.poller
  [n,min,oldest_s]`), which makes "the 02:25 tick was still writing at 03:13" visible as an age.
- **Changing `band.log`.** Left byte-identical, because `lr-band-reload.sh:198` greps its exact
  format.

---

## 13. Side findings while researching (measured; not acted on)

- **F1. `ps` still times out at priority 31.**
  - 4 `abstain` events: "ps degraded … timed out at 30-37s; ps budget spent" at 07:40:03Z,
    08:19:59Z, 08:30:08Z and 11:06:22Z.
  - Each is bracketed by `band.log` lines reading `pid=4459 pri=31 floor=31 ok` (awk window ±30 s).
  - The kernel-side stall class of REPORT §3.3 is not fully escaped by the band. B6's `ch.ps`
    distribution is how B2 sizes it.
- **F2. Four `cc-dispatch --decide` processes at base priority 4.**
  - Read with `band.py <pid>`: pids 16648, 39037, 46756 and 24265 => 4.
  - `ps` showed 8 such processes with etime 24 min to 5 h 42 m. Three have ppid 1, and some are
    nested (16648 → 23905 → 24744).
  - Meanwhile `dispatch-band.log` reads `pri=31 ok` for launchd passes.
  - Something other than the Interactive launchd job starts `cc-dispatch --decide` in the background
    band, and those processes linger (hypothesis on the cause). The `adj.dispatch` role would show
    this continuously. Reported for the dispatcher owner; not LR.
- **F3. Cohort files are rewritten every pass.** 15 of 17 `cohorts/*.json` were modified within
  one minute (`find -mtime -1m`), including `next-7d-1791086400.json`, a cohort from 2026-10-05.
  `_report` writes every cohort that has any record, every pass (`__main__.py:1441-1454`), and each
  write is an fsync'd atomic write. The cost is unmeasured; B6's `ph.report` will measure it. That
  is a candidate B2 cut.
- **F4. Detect→engaged baseline.** Only 12 of 138 records carry both stamps. The 7 from 2026-10-20
  span 4,885-17,481 s (python over `recon/sessions/*.json`).
- **F5. A non-production kitty at priority 4.** `/Users/chrisren/kitty-pr3/.../kitty` pid 41475
  reads base 4 (`band.py 41475`). It owns no `/tmp/kitty-*` socket the reconciler uses, so it is
  outside the rail. It shows the instrument can see a priority-4 kitty.

---

## 14. Estimated LOC, conviction, risks

**LOC (estimated from the sketches above):**

| Part | LOC |
|---|---|
| `telemetry.py` | ~380 |
| `band.py` | ~55 |
| `clock.py` | ~40 |
| `types.py` | 3 |
| `__main__.py` | ~50 |
| `report.py` | ~8 |
| `bin/cc-lr` | ~30 |
| `test_telemetry.py` | ~430 |
| `lr-recon-telemetry.bats` | ~60 |
| **Total** | **≈ 1,050** |

**Conviction 80%** that an agent can land this as designed, that it adds no measurable cost or
behaviour change to the rail, and that the next incident's pass split, gate counts, dwell, latency
and bands are readable from `cc-lr status --rail` without forensics. The residual 20%:
- the heartbeat or watchdog contract (mitigated by T12);
- merge contention with B2/B3 in `_run_pass`/`_dispatch` (sequence B6 first);
- whether the readout is actually read: the readout-line pointer helps, but this is not provable in
  advance.

**Risks:**
1. Heartbeat key collision with the watchdog's greedy sed (`lr-recon-watchdog.sh:105-115`).
   Mitigation: flat unique keys, T12, mutant M7.
2. A telemetry exception crashing the daemon. Mitigation: `_guard`, self-disable, T9, mutant M5.
3. The new module not yet linked when the daemon restarts. Mitigation: guarded import (P10), T13.
4. Python 3.9 at runtime vs 3.11 in the default suite. Mitigation: T14 under `/usr/bin/python3`.
5. Volume blow-up from standing records or flapping. Mitigation: quiet rule, flap coalescing,
   8 MiB bound plus rotation (T5, T6).
6. Merge conflicts with B2/B3 in the same functions. Mitigation: land B6 first.
7. Box census wall spikes during kernel stalls. Mitigation: no fork, adaptive interval, `BOX=off`.
8. A NO-DATA state misread as healthy. Mitigation: tri-state verdict (T7, T15).
9. Telemetry drifting into a decision input. Mitigation: lint T11.

---

## Appendix: commands run for this design (all read-only; scratch in `/tmp/b6probe`)

| Command | Established |
|---|---|
| `git log --oneline -5`; `git diff --stat 28b25a119 main -- scripts/limit-recover bin/cc-lr` | Worktree = main for the cited files |
| `sed -n`/`grep -n` over `lr_recon/{__main__,clock,store,band,admit,act,report,types,plan,observe,census,settle}.py`, `bin/cc-lr`, `lr-recon-watchdog.sh`, `lr-recon-fence.sh`, `hooks/operator-readout.sh`, `install.sh`, `scripts/deploy-*.sh` | Every file:line above |
| `ls -la ~/.reso/limit-recover/recon`; `wc -c events.jsonl events.jsonl.1 band.log`; `cat heartbeat` | Sizes, rotation date, heartbeat keys |
| `awk … band.log \| python3 -I` | Pass-line gap p50 10 / p90 13 / p99 19 / max 193 s, n=3,732; 3,732 of 3,732 `pri=31 ok` |
| `python3 -I` over `events.jsonl` (counts since 2026-10-20T00:00Z; events after 07:23Z) | Event volume; the 4 `ps` abstains at priority 31 |
| `/usr/bin/python3 -I /tmp/b6probe/cost.py …` ×6; `row.py`; `parse.py`; `thr.py 853` | §8 costs; census by base priority; kitty bands |
| `band.py <pid>` for kitty 853 and 41475, and cc-dispatch 16648/39037/46756/24265; `ps -o pid,ppid,pri,etime,args` | §13 F2 and F5 |
| `PlistBuddy -c 'Print :ProgramArguments' com.reso.lr-reconciler.plist`; `/usr/bin/python3 --version`; `python3 --version` | 3.9.6 runtime vs 3.11.4 on PATH |
| `ls -lT cohorts`; `find cohorts -name '*.json' ! -name '*pages*' -mtime -1m \| wc -l` | §13 F3 |
| `python3 -I` over `recon/sessions/*.json` | §13 F4 |
| `TMPDIR=/tmp/b6probe/tmp PYTHONDONTWRITEBYTECODE=1 … python3 -m unittest lr_recon.tests.test_band lr_recon.tests.test_midpass_progress` | The suite runs hermetically (18 tests OK); `git status` clean afterwards |
| `git check-ignore -v tests/fixtures/x.log …` | `*.log` is ignored (`.gitignore:11`), `.jsonl` is not |

Nothing was typed into a pane, signalled, loaded or reloaded. No settings or credentials were
edited. No repository file other than this one was written.

---

## Review — correctness-and-safety

**Reviewer verdict: NEEDS-CHANGES.** Adjusted conviction: 68%. If the required changes below are
made, it returns to the design's 80%.

**Lens.** Could B6 strand a record, double-move one, lose a draft, cause split-brain, break an
invariant or break an existing test? Telemetry makes no decision, so it can reach those outcomes
only three ways:
- **(a) It crashes or restarts the daemon mid-pass.** Restarts are already hazardous: REPORT A6
  (REPORT.md:254-264) lists claim restamps, 25.9 min of self-refusals and a second-driver window.
- **(b) It stalls the loop past the fence's 180 s heartbeat-fresh window** (`lr-recon-fence.sh:195-204`),
  or into a watchdog kill.
- **(c) It puts a wrong line in a Stop hook**, or a value that decision code later reads.

The write-only core survives (a)-(c). Every gap I found is in the glue around it: the import, the
constructor, the `run_bounded` hook, the in-loop census, the role regex and the readout's WARN rules.

**Labels.** *Measured* means read-only, on 2026-10-20 between about 18:10Z and 18:25Z, with the
command named. *Hypothesis* is marked.

### R.1 Verified, and holding

- **Heartbeat key additions are safe for every reader.** `T.from_dict` ignores unknown keys and
  defaults missing ones (`types.py:183-190`), so the fence's `read_heartbeat`
  (`fence.py:85-94`, decision path) loads a new heartbeat under old code and an old one under new
  code.
  - The watchdog's `hb_num` is a greedy last-match on `"KEY":` (`lr-recon-watchdog.sh:105-116`).
    `phase`, `phase_at` and `pass_seq` contain no read key as a quoted suffix.
  - The fence's awk (`lr-recon-fence.sh:155-159`) and the hook's `${hb#*\"progress_wall\":}`
    (`operator-readout.sh:716`) both take the first match.
  - Keys are appended after `max_step_gap_at` (`types.py:473`).
- **`close["tel"]` adds no record writes and is inert to decisions.**
  - `save_records` memoises content apart from `updated_at`, and refreshes every record every 60 s
    anyway (`store.py:140-189`).
  - `act.spawn` calls `save_record` twice (`act.py:321,337`), which pops the memo, so a `first`
    stamp in the same pass costs nothing.
  - `grep` over `lr_recon/*.py` finds no truthiness test, iteration, `copy` or wholesale dump of
    `rec.close`. The only bulk write is `close.update(...)`, at `__main__.py:983` and
    `settle.py:846,916,954`.
- **The close row is emitted.** `_release_terminal` keeps terminal records in `ctx.records`
  (`__main__.py:1545-1558`), so `note_states` at :1728 sees each terminal transition.
- **The lint can be green on day one.** `grep -n 'telemetry\|"tel"\|last_alert' lr_recon/*.py`
  returns nothing (measured).
- **`death` parsing is safe under 3.9.** `/usr/bin/python3` (3.9.6) parses `…03.123Z` and `…03Z`
  after `Z`→`+00:00`, but raises on 5- or 9-digit fractions. `death_ts` must therefore catch the
  error, as the design says. `lstart` strptime round-trips (measured).
- **The cited lines are current.** Spot-checked against the code:
  - `__main__.py:44-47, 444-449, 807-811, 962-971, 1014-1036, 1237-1300, 1466-1469, 1652, 1728, 1796, 1806-1853`;
  - `clock.py:349-361`;
  - `store.py:530-546, 588-601`;
  - `act.py:34, 438-479`;
  - `admit.py:216-238, 320-333`;
  - `report.py:245-278`;
  - `bin/cc-lr:203-206, 2459, 2505, 3121`;
  - `install.sh:855-869`;
  - `lr-band-reload.sh:198`.

  One count is wrong: `may_actuate` has **13** refusal returns, not 14
  (`grep 'return False, "'` over act.py:438-479 => 13).

### R.2 Refuted or defective, and why

1. **Crash loop at start: the constructor calls a function that does not exist.**
   - `Telemetry.__init__` calls `store._max_bytes_env(...)`. `store.py:583` has only
     `_max_bytes(default)`, which reads `LR_RECON_LOG_MAX_BYTES`, and `store.py` is not in
     `files_touched`.
   - The constructor runs **unguarded** in `daemon()` (§4.5): `_guard` covers methods, not
     `__init__`. An `AttributeError` there kills every daemon start. launchd then restarts it into
     the A6 hazards.
   - `_read_json_or_none` does not exist either (`grep` => only `fence._load`, `fence.py:30`).
2. **The guarded import catches only `ImportError`.**
   - A `SyntaxError`, `NameError` or `AttributeError` raised while importing a new ~380-LOC module
     under the deployment interpreter (3.9.6) is not caught. Examples: a 3.10+ construct
     evaluated at runtime, or module-scope code touching `band.<new name>`.
   - The result is a crash loop on the next natural restart, which is the P8 risk. T14 reduces
     it but does not remove it.
3. **The `run_bounded` hook can take `step()` down with it.**
   - The sketch computes `child_label` inside `_note_child` in the `finally:` **before** `step()`.
   - Any exception escaping there replaces the child's result with an exception that callers do
     not catch (`(OSError, SubprocessError)`), and it skips the heartbeat step.
   - This sits on every child the loop waits on.
4. **The census can stall the loop.** *Hypothesis on the stall; the exposure is measured.*
   - `box()` runs on the loop thread, between `_band` and `hb.advance()`. It makes about 1,600
     `proc_pidinfo` task reads plus about 4,850 thread reads, where today there is one self read.
   - An in-process syscall cannot be timed out, and it is not a declared child. A kernel-side
     stall of the class REPORT §3.3 describes would freeze `progress_wall`. After 180 s the fence
     lapses (split-brain window), and the watchdog's no-CPU kill (`lr-recon-watchdog.sh:296-312`)
     could fire mid-cohort.
   - ctypes `CDLL` calls release the GIL, so a worker thread fixes this cheaply.
5. **Thread handles are 64-bit, and an unpinned call reads nothing.**
   - Measured with `/usr/bin/python3 -I /tmp/b6rev/thr_handles.py`, which reads this process's
     own threads: handles `0x1f76523a0` and `0x1707bf0e0` (>32 bits).
     - Passed as `c_uint64`, `proc_pidinfo(PROC_PIDTHREADINFO)` returns 112.
     - Passed as a plain Python int (ctypes' default C `int`), it returns **0**.
   - The sketch leaves `_threads` as `...`. If the handle width is not pinned, the census silently
     reads 0 runnable threads, which the readout could render as a healthy box (P6).
6. **Role matching by substring over the whole `args` mislabels processes.**
   - Measured with `ps -axww -o pid=,args= | grep -E '<the RAIL+ADJ alternation>'` => 39
     processes. Among them:
     - 6 **Claude sessions** classed `hf`: the text `handoff-fire.sh` sits at args offsets
       1,647-31,155;
     - 13 `expect -c` scripts;
     - a `ugrep` classed `actuator`;
     - a `jq` (base priority **4**, via `band.py 91233`) and a
       `timeout … taskpolicy -c background bats tests/…` (base **20**, `band.py 73405`), both
       classed `dispatch`.
   - Anchoring alone is not enough. A bats suite that runs a rail script from a worktree under
     `taskpolicy -c background` would read as `move-worker` (or similar) below 31. That puts
     `WARN` plus `⚠ rail: move-worker <pid> pri 4` in the **Stop-hook line**, breaking
     `operator-readout.sh:709-710` ("a wrong line is worse than a missing one").
   - It would also force a full row on every pass, so the file turns over in about a day instead
     of the claimed ~36 days.
7. **The `resume` role counts session hosts.** `lr-fire-resume.sh next*` processes host resumed
   sessions for their whole life: `ps -o etime=` => 6 alive for 12h59m-14h27m (measured). The
   readout would print "resume ×6, oldest 14h" as rail work in flight.
8. **`in_state_s` is wrong for one pass after each state change.**
   - `cohort_status` runs in `_report` (:1723), **before** `note_states` (:1728).
   - On the pass a record changes state, its cohort file shows the time since the **previous**
     state's `at`. `cl_status_cohort` and agents read that file.
9. **The readout would be `WARN` permanently from activation.**
   - Today's live state (measured, `python3 -I` over `recon/sessions/*.json`): 4 open records,
     all `PRE-MOVE/PARKED-REBOOT`, `plan_only`, detected 443-489 h ago, never attempted.
   - Both "time in state > W_soft" (it excludes only HOLD/HELD/WAIT_RESET) and "not attempted
     2,580 s after detection" fire on them indefinitely.
   - Two more rules make WARN near-constant:
     - "Any child timeout": `events.jsonl` since 00:00Z shows 10 of 30 `place` events at rc=124,
       at band 31 (measured). Under the binding premise that is "unknown, retry", not an anomaly.
     - "faults > 0": the count is per process lifetime, not per window.
   - A verdict that is always WARN carries no information.
10. **The stamp is lost precisely in a mid-pass restart.**
    - `spawned()` stamps `first` **after** `act.spawn`, so it lands on disk only at the end-of-pass
      `save_records`.
    - Under load the rest of the pass (`_report`, pages and children) lasts minutes. A restart in
      that window is the A6 class B6 is meant to diagnose, and it loses `first` for the very
      records that matter.
    - Pre-B6 open records get `first` and `at` from the first post-B6 sighting, which pollutes the
      latency distributions at activation.
11. **Tests do not cover what they claim.**
    - T9's "census that raises" never runs inside `run_pass`, because `box()` is in the daemon
      loop. So M5 does not go red through that arm.
    - `test_daemon_loop_starts_and_runs_a_pass` (`test_main.py:1845-1860`) runs `M.daemon` for
      real. It would build a Telemetry and census the live box from a unit test.
    - T6 at "3 s passes for 24 h" is 28,800 passes. Through `run_pass` that is far too slow.
12. **The child labels hide the F1 question.** All three `ps` children read as `ps`:
    - the table read (`observe.py:171`);
    - the tty read (`observe.py:180`);
    - the per-pid `ps -o lstart= -p` from `proc_lstart`, which runs at `__main__.py:130` (`_alive`)
      and `:1061` (every act pass), and after every spawn (`act.py:316`).

    F1 ("`ps` times out at 31") needs the table read separated. The `/bin/bash <script>` children
    (`_run_snap`, `__main__.py:567-578`) all read as `bash`.
13. **The lint list misses modules.** T11 names 15 modules. It omits `observe_rows.py`,
    `tokens.py`, `working.py`, `types.py`, `clock.py` and `band.py` (`ls lr_recon/*.py`). It also
    exempts all of `report.py`, which includes paging (`max_age_page`), an action.
14. **The activation precondition can never be met here.** "`cat readout.line` prints nothing" is
    false today and will stay false: it reads
    `lr-recon: 2 cohorts open · 0 moving · 4 waiting · …` (measured) because of the 4 parked
    records. `owned/` is empty (measured), so a better precondition is available.
15. **The doc disagrees with itself on box cadence.** §3.1 says "every 60 s while any record is
    open"; the sketch uses `active`, the moving bucket. On this box something is always open, so
    the two readings differ.

### R.3 Required changes

See the structured return. Each item above maps to one change, numbered RC1-RC17 in the return.

### R.4 Not defects (checked)

- A 3.9 parenthesised `with (` in `test_main.py:1853` already passes under 3.9.6. CPython 3.9's PEG
  parser accepts it.
- `snap.sockets` is `unix:/tmp/kitty-<digits>` (`observe.py:201-218`), so the sketch's `int()`
  parse works in production. It can still fault on test fixtures (RC12).
- `wait_for_change`, `shift_record` (`clock.py:167-180`) and `_invariant` do not touch
  `close["tel"]`.

---

## Review — efficacy-under-permanent-load

**Reviewer's lens.** Two questions:
- Does B6 help bound recovery time at 15-40 per core with every lane at priority 31?
- Does any new wait, bound or gate assume that load falls?

B6 makes no decisions, so for B6 these become two narrower questions:
- (a) Does it add any wait or bound to the rail's critical path?
- (b) Is it a sound instrument for **verifying** G (REPORT §5)? B1 and B3 consume it for exactly that (§9.4, §11).

**Verdict: NEEDS-CHANGES.** Adjusted conviction **62%**, down from the design's 80%.
- On (a), B6 is clean in the daemon, with one unbounded in-loop read (RC-8).
- On (b), the design does not hold up as written:
  - its detect→first statistics drop exactly the records that fail G;
  - they count time in hard holds against G;
  - they leave G's retry clause unmeasured;
  - they count no-op attempts as attempts.
- Its readout is also wrong under load in two places. It uses fixed thresholds on quantities that load stretches: pass length and the progress gap. It also misclassifies live Claude sessions as rail processes.

All of these are fixable inside B6's footprint.

**Labels.** *Measured* = a command I ran read-only on 2026-10-20 between 18:10Z and 18:25Z. The load then was `sysctl -n vm.loadavg` => `{ 31.75 75.38 141.51 }`, and later `os.getloadavg()` => `92.6`, on 10 CPUs: 3-9 per core. That is **below** the design's 26 per core, so my CPU-time numbers are load-independent CPU, not wall time under load. *Estimated* names its method. *Hypothesis* is unverified. Scratch files are in `/tmp/b6rev/`; I wrote nothing else.

### R.1 What I verified and found sound

- **No decision input, no load gate.**
  - Admission already discards load: `admit.py:283` `del load1, load5, ncpu`.
  - B6 only records `os.getloadavg()` (design §4.1 `box()`).
  - The lint T11 plus P1 keep it that way.
- **`run_bounded` really is the single choke point for every child the loop waits on.** `grep -n "run_bounded\|subprocess.run\|Popen" lr_recon/*.py` => every waited child goes through it, or through an injected `run` that defaults to it:
  - `observe.py:157,237,429,466`
  - `plan.py:295,499,523`
  - `admit.py:78`
  - `store.py:530`
  - `act.py:528`
  - `fence.py:128,149`
  - `report.py:552`
  - `__main__.py:569`

  The `Popen` sites (`act.py:315`, `__main__.py:529`, `plan.py:379`) are fire-and-forget. `grep -n threading` finds no worker threads (only the ident checks in `clock.py` and `transcript.py`), so the ledger sees every child on the bound thread. The hook adds no wait.
- **`set_phase` cannot wait on disk.**
  - `Heartbeat.snapshot` copies under `_lock` (`clock.py:237-251`).
  - `write_now` runs the fsync'd `atomic_write` outside the lock (`clock.py:279-287`, `183-199`).
- **Census cost reproduced.** `/usr/bin/python3 -I /tmp/b6rev/census.py` => 8.5-9.2 ms wall, equal to CPU, over 4,676-4,679 threads and 1,066-1,069 of 1,542-1,545 pids readable. No single pid took more than 5 ms. Runnable by base priority: `{4: 41-44, 20: 2-3, 31: 13-27}`. This is consistent with §8's 10-16 ms at 26 per core.
- **No extra record writes.** `store.save_records` memoizes the content without `updated_at` (`store.py:166-176`), and `close["tel"]` changes only on a state change or the first spawn.
- **Watchdog contract.**
  - `hb_num` is `sed 's/.*"KEY":…'` on one line (`lr-recon-watchdog.sh:105-115`).
  - `phase`, `phase_at` and `pass_seq` collide with no key it reads (pid, progress, wall, progress_wall, step_due, child_bound_s, lstart).
  - T12 plus M7 are the right guard.
- **Citations spot-checked and correct (±1 line):**
  - `__main__.py`: 44-47, 1237-1242, 1243-1247, 1248-1267, 1268-1285, 1298-1300, 1304-1311, 1652-1657, 1665-1729, 1806-1853, and 444-449 (`continue` at 446 and 449);
  - `act.py`: 438-479 (13 `return False` reasons, not 14);
  - `types.py`: 184-191, 448-473;
  - `band.py`: 74-93;
  - `store.py`: 588-601;
  - `report.py`: 245-278, 390-400;
  - `bin/cc-lr`: 204, 2459, 2505, 3121;
  - `lr-reset-poller.sh`: 259-262.

### R.2 Findings (attempted refutations that succeeded)

**F1. The G instrument has survivor bias.** Design §3.2, §4.1 `note_states` and §9.4 ("B1 asserts G from close rows (`first - det`)").
- **Records born terminal are dropped as if they were pre-B6.**
  - `note_states` skips any record with no `tel` and `terminal is not None` (design §4.1 `note_states`, first `if`).
  - `census.impossible_record` (`census.py:519-550`, terminal at birth at `:549`) and `census.not_needed_record` (`census.py:481-517`, terminal at `:513-515`) create records that are terminal at birth, during the daemon's life. So a limited session the census declares IMPOSSIBLE never produces a row. REPORT §5 step 5 requires "zero IMPOSSIBLE-for-soft-reason verdicts", and B6 hides precisely that class.
  - On today's disk such records number 0 of 138 (measured: python over `recon/sessions/*.json`; records are per-sid and later records overwrite them), so the frequency is unknown. The code path is live.
- **Closed records without `first` drop out silently.** The close stats compute detect→first only where `first` exists (§6.1 `closed` line). A record closed by ESCALATED→IMPOSSIBLE, `replaced`, or NOT_NEEDED with no attempt drops out of the distribution without a count. On disk today, 68 of 138 records are NOT_NEEDED (61 "idle member, no move", measured). Unless they are split out by outcome, the legitimate no-attempt closes drown the illegitimate ones.
- **Open records are not right-censored.** An open record that has never been attempted does not enter the percentiles at all. Only a WARN (> 2,580 s) touches it.

**F2. Hard-hold time is counted against G.** G applies to records "not held by a named hard predicate" (REPORT §5).
- `first - det` includes every second spent in WAIT_RESET (to a weekly reset), HOLD-* and HELD:*. The readout's detect→first p90 and max, and B1's assertion, will therefore be dominated by legitimate holds and fail spuriously.
- `close.dwell` is a lifetime total, so it cannot be split at `first` after the fact.
- The design's WARN list also uses an ad-hoc prefix set (§6.3: "non-`HOLD*`/`HELD*`/`WAIT_RESET`") that matches no written list of hard predicates.
- **Measured:** 4 records are open now, all `idle PRE-MOVE PARKED-REBOOT`, detected 443-489 h ago. PARKED-REBOOT belongs to another lane (`census.py:878`, `act.py:460` "boot-resume owns"). Under §6.3, all four WARN "not attempted > 2,580 s" from the first readout: their `first` is absent because they predate B6, not because nobody attempted them. The verdict is therefore WARN permanently on day one.

**F3. G's second clause is unmeasured, and the "stuck" WARN can be reset by flapping.**
- G also says that after a failed attempt the next one starts within `B_max + P_max` (REPORT §5). B6 keeps `first` only.
- Spawns are not rows, only a per-pass counter (§3.1 `spawns{}`), so the exit→next-spawn gap cannot be computed from telemetry.
- The substitute WARN, "time in state > 600 s", restarts on every state change. A record looping PLANNED↔WAIT_DATA (F8, the "retries that are no-ops" class of REPORT §3.4) never trips it.

**F4. A no-op attempt satisfies "attempted".**
- `first` is stamped on any FIRST spawn (§4.1 `spawned`), including an actuator that exits at once on a refusal. REPORT §3.4 is about exactly that: the self-claim refusal after a restart, a false HELD:busy.
- `act` rows carry no outcome class, although `__main__.py:807-809` computes `settle.settle_exit(...)` → `detail` at that very point.
- **`act.wall` mixes up three things.**
  - It is spawn→*exit-seen*: the exit is seen in `_derive` of a later pass (`act.reap_children` runs once per pass, `act.py:396-417`). That adds up to one pass gap plus one pass duration to T_att, and both are load-stretched.
  - Its start is `pr.lstart` from `store.proc_lstart` (`act.py:335`), which returns `""` on a 40 s `ps` timeout (`store.py:530-546`). So under load `wall` is null exactly when `ps` is slow.

**F5. The readout's thresholds assume load-stretched quantities stay small.**
- **"Telemetry stopped" fires during any long pass.** `NO DATA — telemetry stopped` fires when the newest row is over 600 s old while `progress_wall` is under 180 s (§6.3).
  - Pass rows are written only at pass end, and box and quiet rows only between passes (§4.1 `pass_end`, `box`).
  - `step()` keeps `progress_wall` fresh inside a pass (`clock.py:321-339`).
  - So any pass over about 10 min renders "telemetry stopped".
  - Passes of 5-14 min are the measured pre-B2 regime (REPORT.md:54), and B6 is meant to land before B2 (§11).
  - The readout therefore lies during exactly the incident B6 exists to make legible.
- **Liveness does not match the watchdog.** "Daemon down" uses `progress_wall < 180 s`. The watchdog instead reads `wall` against `STALE_HB_S=60` for death, and `step_due + STEP_MARGIN_S(60)` before it treats a frozen counter as a stall (`lr-recon-watchdog.sh:82-86`, `:271-305`). A 120 s `--place` plus a 40 s `ps` retry is a legitimate gap over 180 s.
- **The phase key can go stale.** `phase` and `phase_at` move only through `Telemetry.phase` → `clock.set_phase`. With telemetry paused (`telemetry.off`) or self-disabled (§4.1 `_guard`), the heartbeat keeps the last phase forever, and the readout prints "now: dispatch 3h".

**F6. Rail-role matching misclassifies live Claude sessions (measured).** `/usr/bin/python3 -I /tmp/b6rev/hitpri.py` runs the design's exact `RAIL+ADJ` regex over one `ps -axww -o pid=,ppid=,stat=,lstart=,args=` snapshot (1,636 processes), then reads `band.base_priority` for each hit. Result: 38 hits.

| Role | Hits | What they actually are |
|---|---|---|
| `hf` | 9 | All are Claude sessions (`cc-close-attrib …claude` and `claude --settings=…`) matching at byte 1,647-31,155 of their args. None is a `handoff-fire.sh` process |
| `dispatch` | 7 | Two are `bats` suites at **base 11**, matching at byte 4,375-12,209. One is `jq` with an inline program. Five are cc-dispatch-style processes that exited before the read (`None`) |
| `resume` | 20 | 7 are `lr-fire-resume.sh` wrappers alive since 2026-10-19 22:52 to 2026-10-20 00:20 local, plus 13 `expect` processes (6 of them from 2026-10-18). A tree trace (`awk` on ppid) shows 24868 `lr-fire-resume.sh` → 29897 `expect` → 29964 `cc-close-attrib … claude`: the parent chain of a running session, not recovery work in flight |

Consequences:
- Any background-band session or test run whose args mention a rail script reads `low` and sets WARN.
- It turns every pass into a full row (quiet rule, §3.3 "a rail process read below 31").
- It writes `⚠ rail: hf <pid> pri 4` onto the operator's Stop-hook line (§6.4), against that hook's "a wrong line is worse than a missing one" contract.
- `rail.resume oldest_s` reads days. Every true match sits at byte 38-56 of its args.

**F7. The cost claim is understated about 30×** for the per-pass role scan.
- Measured with `roles.py` under the same command: 9.74 ms CPU (11.97 ms wall) per pass over 1.45 MB of args. The largest single args string is 392,547 B.
- §8 budgets about 0.3 ms per pass for laps, ledger, role scan and row together.
- **Estimated** at about 6-10 passes per minute (band.log gap p50 10 s, per §5): 60-100 ms of CPU per minute, i.e. 0.1-0.17% of one core, not "< 0.05%".
- A scan limited to the first 400 bytes measured 2.28 ms with 13 hits.

This does not threaten the rail; it is a wrong number in the design.

**F8. The box census is a new in-loop operation with no bound, and its throttle thins under contention.**
- `box()` runs on the loop thread between `_band` and `hb.advance()` (§4.5 `daemon` row), about 6,500 libproc calls with no deadline. The design's own principle (`clock.py:349-353`: "an unbounded child is the one wait no watchdog margin can cover") applies in spirit.
- Today's cost is about 9 ms (measured). The tail under REPORT §3.3's kernel-side stall is unknown (hypothesis: `PROC_PIDTHREADINFO` does not read target memory, unlike `ps`'s `KERN_PROCARGS2`, so it is likely safer, but this is unproven).
- `next_box = now + max(base, 60 × wall_cost)` keys on **wall** time, which contention inflates. The positive control (REPORT §5 step 3) is therefore sampled least when the band is most contended, and recovers only when load falls. That is weak, but it is the pattern this lens checks for.

**F9. Kitty's band goes dark exactly when `ps` degrades.**
- `kitty_pids` come from `snap.sockets`, which need a live `ps` row (`observe.py:192-213`, `live(...)`).
- On a ps-degraded pass `snap.procs` is empty, so `kitty = {}`, and no rule in §6.3 renders an empty kitty map as unknown.
- **Measured:** `grep '"ev":"abstain"' events.jsonl` => 8 ps-timeout abstains on 2026-10-20, 4 of them after the 07:23Z reload to priority 31.
- The pid is in the socket name (`/tmp/kitty-<pid>`), so libproc can read it without `ps`.

**F10. The self-disable is permanent, and one root cause can trip it.**
- 20 faults over the process lifetime turn telemetry off until restart (§4.1 `_guard`). The daemon lives for days: pid 5233 started 16:04:56Z, and `progress` reads 1,113,626 (heartbeat, measured).
- A single transient fault in `pass_begin` leaves `cur` stale or None. Then about 13 guarded calls fault in the same pass (phases, observed, gates, note_states, pass_end), so two transient root causes blind the daemon permanently.
- That is a negative verdict from our own fault budget, against the premise "unknown, retry".

**F11. "rail: ok" claims more than the reconciler.**
- The move lane is 19.1% of the incident's lost minutes (REPORT.md:52, axis 02 §4.5). It runs outside the reconciler (`cc-lr move` batches under `~/.reso/limit-recover/move/<batch>/`, with per-sid `events.jsonl` and `summary.json`; `ls`, measured).
- boot-resume owns PARKED-REBOOT records.
- B6 sees neither lane's queue→attempt time or outcomes, yet its verdict is named `rail:`. The operator target, "every queued recovery is attempted within bounded time", covers those queues too.

**F12. Killed passes vanish from P_max.**
- A pass that the watchdog kills, or that crashes on SIGTERM (no Python handler), writes no `pass` row.
- The `start` row carries `prev.phase` and `phase_age`, but not when that pass began.
- So B1's "P_max from `pass.dur`" (§9.4) silently omits the longest passes: the restart-killed passes of REPORT.md:54.

**F13. Ledger labels mix cost classes that B2 must size apart.**
- `ps` merges the 1.5 MB full census (`observe.py:170-187`, the one timing out at 30-40 s) with 5 s per-pid reads: `store.py:530` `ps -o lstart= -p`, `act.py:528` `ps -o command= -p`, `fence.py:149` `ps -o <f>= -p`.
- The "basename(argv[0])" rule turns `/bin/bash lr-composer-snapshot.sh` (`__main__.py:567-579`, the composer-unreadable class of REPORT §2.2) into the generic label `bash`.

**F14. Sketch inaccuracies (minor).**
- `store._max_bytes_env` does not exist. `store.py:583` has `_max_bytes(default)`, which reads only `LR_RECON_LOG_MAX_BYTES`, and `store.py` is not in files_touched.
- `_read_json_or_none` does not exist in `__main__.py` (`grep` => none).
- T11's module list omits `observe_rows.py`, `tokens.py` and `working.py` (`ls lr_recon/`).
- `FIRST` is hard-coded rather than derived from `__main__.FIRST_TURN` (`__main__.py:1085`) and `settle.MOVE_ACTUATORS` (`settle.py:33`).
- The `placer` role is almost never observable: the placer is the pass's own child and never coexists with that pass's `ps` snapshot. Its band is inherited from `self` (`band.py:20-25`).

### R.3 Required changes

- **RC-1 (F1): de-bias the G statistics.**
  - At `start`, keep the set of sids loaded terminal (`_startup`, `__main__.py:1789`). Only those count as "pre-B6 terminal".
  - Any record born terminal later gets a `close` row with `born_terminal: true` and `first: null`.
  - The readout prints detect→first over **attempted + censored**:
    - open, unattempted records enter as `≥ age`;
    - closed, unattempted records are counted and split by `out`/`via`.
  - It prints `n_censored` and `n_closed_unattempted{outcome}` beside every percentile.
  - B1 asserts on the censored set too.
- **RC-2 (F2): net out hard holds by a written table.**
  - Define `HARD_HOLD` from REPORT §5's hard predicates and `OTHER_LANE = {PARKED-REBOOT}` in `telemetry.py`. Display-only, pinned by a test to B3's set once B3 lands.
  - In `spawned()`, stamp `held_pre`: the dwell in `HARD_HOLD` states before `first`, including the current state's open interval.
  - Report both raw `first-det` and net `first-det-held_pre`.
  - The "not attempted" WARN uses the net value, excludes `OTHER_LANE` (it names the owning lane instead), and renders pre-B6 records' `first` as **unknown**, never "not attempted" (P6).
- **RC-3 (F3): measure the retry clause.**
  - Emit a `spawn` row `{sid,rid,a,att,gap}`, where `gap` = seconds since this record's last exit was seen. Alternatively keep `regap_max` and `n_regap_over` in `close["tel"]`.
  - Replace the "time in state > 600 s" WARN with: an open record not in `HARD_HOLD`, whose last attempt exited more than `B_max + P_max` (480 s) ago, or which was detected more than `W_soft` ago with no attempt, and no new spawn since. Flaps cannot reset that.
- **RC-4 (F4): attempts carry an outcome, and T_att is exit-based.**
  - `act_exit(rec, pr, rc, detail)` takes the `settle.settle_exit` detail already computed at `__main__.py:808`, truncated to 80 characters.
  - `wall` = actlog mtime (`settle.actlog(...)`, already resolved at `:808`) minus the spawn wall stamped by telemetry in `spawned()` (an in-memory pid→wall map), falling back to `lstart`.
  - Add `seen_lag` = exit-seen minus actlog mtime.
  - The readout counts no-op attempts (rc ≠ 0 and wall < 10 s) separately.
- **RC-5 (F5, F12): liveness and long passes follow the watchdog, not fixed thresholds.**
  - The heartbeat gains a flat `pass_at` (wall at pass begin).
  - `_ph` calls `clock.set_phase` **directly**, outside the guarded `Telemetry`, so the phase stays true when telemetry is paused or off.
  - The readout's rules:
    - the daemon is alive iff the heartbeat `wall` age is ≤ 60 s;
    - an in-progress pass is WARN "pass N running Xm, phase P for Ys, child bound Zs, step due in Ws", never NO DATA;
    - "telemetry stopped" only when `pass_seq` has advanced at least 2 past the newest row's `seq`.
  - The `start` row carries `prev.pass_age` = last heartbeat `wall` − `pass_at`. The readout and B1 treat it as a P_max reading of at least that value.
  - Add a T15 fixture: a 14-minute in-progress pass with a fresh heartbeat renders WARN-in-progress.
- **RC-6 (F6): match roles on argv structure.**
  - Match the basename of argv0, or of argv[1] when argv0 is `bash`/`sh`/`zsh`/`python3`. For the actuator, match `lr-recon-act` only as argv[3] of `/bin/bash -c <WRAPPER>`.
  - Scan only the first 400 bytes.
  - Exclude argv0 ∈ {claude, node, expect, jq, bats, cc-close-attrib}.
  - Classify an `lr-fire-resume.sh` that has a live `claude` descendant (ppid chain in `snap.procs`) as `session-parent`, not rail.
  - Regression test with the measured shapes: a `claude --settings=…handoff-fire.sh…` row, a `bats … cc-dispatch` row at base 11, and the `lr-fire-resume.sh → expect → claude` chain.
- **RC-7 (F7): fix §8's estimate.** Measure the role scan with the RC-6 matcher, include it in each row's `tel`, and restate the total.
- **RC-8 (F8): bound the census and throttle on CPU.**
  - `runnable_by_base(deadline_s=2.0)` checks a monotonic deadline per pid and returns `partial: true` with the counts so far.
  - `next_box` uses `time.thread_time()` cost (CPU), not wall time. Wall time is still recorded.
- **RC-9 (F9): kitty without `ps`.** Take kitty pids from the `/tmp/kitty-*` glob (pid in the name, liveness by `proc_pidinfo`), not `snap.sockets`. An empty or unreadable kitty set renders `kitty unknown` and counts as unknown (P6).
- **RC-10 (F10): faults re-arm and do not cascade.**
  - When `cur` is None, the pass methods return without counting.
  - The off state lasts 1 h, then re-arms with a fresh budget, writing `telemetry-off` and `telemetry-on` events.
  - Test it with M5.
- **RC-11 (F11): scope the verdict honestly.** Do one of two things:
  - **(a)** The readout, at zero daemon cost, also reads `move/<batch>/` (per-sid `events.jsonl`, `summary.json`) within the window, showing queue→first worker start and NOTMOVED reasons, and lists `OTHER_LANE` records with their owner.
  - **(b)** Rename the verdict `reconciler:` and print "move lane, boot-resume: not covered".

  It must never print a bare `rail: ok`.
- **RC-12 (F2/F5, dwell resolution):** each `rec` row carries `p0` (pass-begin wall), so a transition is bracketed `[p0, t]`. Before B2, the stamp `at` is late by up to one pass (5-14 min). T4 must move the wall clock across a transition **inside** one pass and assert the bracket.
- **RC-13 (F13): split ledger labels.**
  - `ps:all` for `-ax…`; `ps:pid` for `-p`.
  - For an interpreter argv0, the label is the basename of argv[1] (e.g. `lr-composer-snapshot.sh`).
  - Keep `probe` and `mint` for the `bash -c` probes.
- **RC-14 (F14): correct the sketch.**
  - Either add `_max_bytes_env` to `store.py` and list it in files_touched, or keep the helper in `telemetry.py`.
  - Add `_read_json_or_none`, or reuse an existing reader.
  - T11 computes its module list as `lr_recon/*.py` minus `{telemetry,report,__main__}.py`.
  - `FIRST` is imported from `settle.MOVE_ACTUATORS + ("C","C-retry")`, with a test that it equals `__main__.FIRST_TURN`.
  - Drop `placer` from the claimed per-process bands, or say it is inherited from `self`.

### R.4 Recommended, not required

- A flat heartbeat key `child` (the label of the child currently declared, set in `declare_child`). A watchdog kill mid-child would then name the child as well as the phase: the A6 and B2 evidence for the 1,226 s `ps` class.
- A per-record G bound in the readout that uses `k_r` (open, non-held records detected earlier) and D, instead of a fixed 2,580 s. A cohort of 30 legitimately exceeds 43 min under the targets (estimated from REPORT §5: 10 + 3 + ceil(29/6)·15 = 88 min).

### R.5 Commands run for this review (read-only; scratch in `/tmp/b6rev`)

| Command | Established |
|---|---|
| `sed -n`/`grep -n` over `lr_recon/{__main__,clock,store,band,admit,act,observe,census,plan,report,settle,fence,types,drain}.py`, `lr-recon-watchdog.sh`, `lr-reset-poller.sh`, `bin/cc-lr` | Every file:line in R.1-R.3 |
| `sysctl -n vm.loadavg hw.ncpu`; `/usr/bin/time -p /bin/ps -axww -o pid=,ppid=,stat=,lstart=,args= > /tmp/b6rev/ps.txt` | Load at review time; the snapshot (1,636 processes, 1.53 MB, 0.15 s) |
| `/usr/bin/python3 -I /tmp/b6rev/roles.py /tmp/b6rev/ps.txt` | F7: 9.74 ms CPU per scan, 38 hits |
| `/usr/bin/python3 -I /tmp/b6rev/hitpri.py /tmp/b6rev/ps.txt …/lr_recon` | F6: base priority and match offset per hit; prefix-limited scan 2.28 ms |
| `awk` ppid trace for pids 24868 and 29897 | F6: `lr-fire-resume.sh` → `expect` → `cc-close-attrib … claude` |
| `/usr/bin/python3 -I /tmp/b6rev/census.py` | R.1 census cost |
| `/usr/bin/python3 -I /tmp/b6rev/recs.py`; inline `python3 -I` over `recon/sessions/*.json` | F1, F2: 138 records (68 NOT_NEEDED, 65 CLOSED, 1 IMPOSSIBLE, 4 open PARKED-REBOOT at 443-489 h); no born-terminal file survives |
| `grep '"ev":"abstain"' recon/events.jsonl`; `date -u -r` | F9: 8 ps-timeout abstains on 10-20 (03:58Z-11:06Z) |
| `cat recon/heartbeat`; `tail -n 2 recon/band.log` | F10: pid 5233, progress 1,113,626, `pri=31 ok` |
| `ls ~/.reso/limit-recover/move/<batch>/` | F11: per-sid move-lane files are readable by a readout |

Nothing was typed into a pane, signalled, loaded or reloaded. No settings, credentials or code
were edited. The only repository file written is this section of this file.
