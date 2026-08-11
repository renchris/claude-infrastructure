I read the script end to end. It contains real defects — the most serious are in the MACHINE-floor streak logic (it can badly understate the floor, and it can silently splice non-consecutive runs together), plus a verdict/exit contract that contradicts its own header. Details below, ordered by severity.

---

**Defect 1 — The machine floor only ever considers the first `run_len` samples of each healthy streak, so a higher plateau later in the same streak is never credited.**

Where — lines 111–113:
```python
        cur_min = n if cur_min is None else min(cur_min, n)
        if streak >= run_len and cur_min > floor_m:
            floor_m, best_run = cur_min, streak
```

Why it is wrong — `cur_min` is the minimum over the *entire* streak so far, and within a streak it can only decrease. Therefore the condition `cur_min > floor_m` can only fire once per streak, at the moment `streak == run_len`, using the minimum of the streak's first 10 samples. The documented metric (line 26: "The largest session count sustained across a run of consecutive samples") is the max over *all* windows of `run_len` consecutive healthy samples. Given healthy samples `[1, 30, 30, 30, … (hundreds of 30s)]`, the true sustained floor is 30 (samples 2–11 onward), but the code reports 1: at streak 10 `cur_min` is 1, and it never recovers because `cur_min` can never rise within the streak. The published floor can understate the measured evidence by an arbitrary factor.

---

**Defect 2 — Filtering out rows without an integer `sessions` field *before* the streak walk means an unhealthy sample that lacks a session count does not reset the streak, splicing two short healthy runs into one "consecutive" run.**

Where — line 102 (interacting with the loop at 105–115):
```python
cap = [r for r in rows(cap_log) if isinstance(r.get("sessions"), int)]
```

Why it is wrong — the streak logic assumes adjacent elements of `cap` are consecutive log samples; the `else: streak, cur_min = 0, None` reset only runs for rows that survive the filter. If the alarm emits a sample with `verdict=SWAP-CRITICAL` but `sessions: null` (or the field missing — the existence of this filter implies such rows occur), that sample is deleted from the sequence rather than resetting the streak. Two healthy runs of 5 samples separated by an unhealthy one then count as 10 consecutive healthy samples, and a floor is published for a period during which the box was demonstrably not healthy — the exact opposite of "a real lower bound."

---

**Defect 3 — A sample with a missing or null `swap_used_mb` passes the swap half of the health gate, so absence of a measurement is counted as evidence of health.**

Where — line 106:
```python
    ok = r.get("verdict") == "OK" and float(r.get("swap_used_mb") or 0) <= 0
```

Why it is wrong — when `swap_used_mb` is absent or `null`, `r.get(...) or 0` yields 0, and the sample is classified healthy on the swap axis. If any slice of the log predates that field or an error path omits it, those samples extend healthy streaks and can raise the published floor. The file's own contract (lines 3–4: "Never estimates… where the data cannot answer, it says so") is violated: the floor is built partly on samples where the swap question was never answered.

---

**Defect 4 — The verdict and exit code require *both* floors, contradicting the documented contract "0 = a floor was computed."**

Where — lines 159 and 183:
```python
    "verdict": "OK" if (floor_m and pool) else "INSUFFICIENT-DATA",
```
```python
sys.exit(0 if (floor_m and pool) else 3)
```

Why it is wrong — line 43 defines exit 0 as "a floor was computed." For the entire first weekly window after the recorder lands — the expected steady state this script was shipped into — the machine floor (which the header calls "the BINDING constraint," line 28) is computed and even printed, yet the JSON `verdict` is INSUFFICIENT-DATA and the exit is 3. Any consumer branching on the exit code or the `verdict` field discards a valid, computed floor. The conjunction also conflates two different states in the other direction (pool computed, machine floor 0), and it cannot distinguish "no data" from "data present but floor is legitimately 0."

---

**Defect 5 — `machine_floor_run_samples` / `best_run` can only ever be 0 or exactly `run_len`; the actual length of the sustained run is never reported.**

Where — lines 112–113 (surfaced at lines 150 and 165):
```python
        if streak >= run_len and cur_min > floor_m:
            floor_m, best_run = cur_min, streak
```

Why it is wrong — as shown in Defect 1, the assignment can only fire at `streak == run_len` (strict `>` blocks re-firing once `floor_m == cur_min`). So after 5,000 consecutive healthy samples at a constant 30 sessions, the output prints "30 concurrent sessions sustained (10 consecutive healthy samples…)" and the JSON reports `machine_floor_run_samples: 10`. The field exists to state how long the floor was sustained, and it reports a constant instead of the measurement.

---

**Defect 6 — When the utilization series spans the full week but contains no qualifying sample, the INSUFFICIENT-DATA message gives a false diagnosis: "(0h short)" and "this becomes computable by elapsed time."**

Where — lines 172–178 (reached because `pool` stays `None` at lines 143–146):
```python
        short = max(0.0, need_h - u_span_h)
```
```python
        print("                live sweep at no extra cost. Nothing to run; this becomes "
              "computable by elapsed time.")
```

Why it is wrong — `pool` is `None` not only when the span is short but also when every row is marked `stale`, lacks an integer `k` or numeric `weekly_pct`, or has `weekly_pct >= 100`. In that case the script prints "need 168h (0h short)" and asserts elapsed time will fix it — which is false; more waiting produces the same result. The header promises the script "names exactly what is missing" (line 4); here it names the wrong thing.

---

**Defect 7 — "Consecutive" is positional, not temporal: no check on the gap between adjacent samples, so a run spanning hours or days of recorder downtime counts as sustained.**

Where — lines 105–113 (against the claim at lines 51–52):
```python
# 46, not that it sustains it. 10 consecutive 60 s samples = 10 minutes green.
```

Why it is wrong — the equation "10 consecutive samples = 10 minutes green" holds only if the 60 s cadence is verified, and the loop never looks at timestamps. If the alarm daemon was down for two days between sample 5 and sample 6 of a streak, the code still publishes a floor "sustained" across that run, though nothing was measured for 48 of those hours.

---

**Defect 8 — The health check tests absolute swap *usage*, while the metric is defined at the top of the file as zero swap *growth*.**

Where — line 106 (against line 27):
```python
    ok = r.get("verdict") == "OK" and float(r.get("swap_used_mb") or 0) <= 0
```

Why it is wrong — line 27 defines the metric as "consecutive samples with verdict=OK and zero swap growth." Nothing in the code compares swap between samples. On a box carrying static residual swap (common: the OS keeps swap allocated after a pressure event passes, with zero growth), every sample fails the gate forever, `floor_m` stays 0, and the script permanently reports INSUFFICIENT-DATA despite abundant data that is green under the documented criterion. I note the nearby comment at line 99 describes the check as implemented ("no swap is in use"), so the file contradicts itself; but the top-of-file metric definition is not what is computed.

---

**Defect 9 — Two plausible data shapes crash the interpreter with an unhandled exception, producing exit code 1, which the header defines as "the stores could not be read at all."**

Where — line 106 and lines 122 / 130:
```python
    ok = r.get("verdict") == "OK" and float(r.get("swap_used_mb") or 0) <= 0
```
```python
        span_h = (t1 - t0).total_seconds() / 3600.0
```

Why it is wrong — a non-numeric string in `swap_used_mb` makes `float()` raise `ValueError` (only `json.loads` errors are caught, at line 87); and `ts_of` returns a timezone-aware datetime for `"…Z"` timestamps but a naive one for offset-less timestamps, so a log whose first and last rows use different formats makes the subtraction raise `TypeError`. Either way the script dies with a traceback and exit 1 — the caller is told the store was unreadable when it was read fine and contained one odd row.

---

**Defect 10 (minor) — `--help` prints code, not just the header.**

Where — line 63:
```bash
    -h|--help) sed -n '2,50p' "$0"; exit 0 ;;
```

Why it is wrong — the header comment ends at line 46 (`# Usage: …`); lines 47–50 are `set -uo pipefail` and the `CAP_LOG`/`UTIL_LOG` assignments, which are emitted as part of the help text.

---

Out-of-scope observations I deliberately did not count as defects: unknown flags (e.g., a typo like `--jsn`) are silently ignored by the `case` at lines 60–64, and the pool floor accepts a single instantaneous sample per account (no run requirement), but the latter matches its own local specification at lines 133–135.