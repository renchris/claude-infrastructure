Reviewing the script text only, as instructed. Five defects found.

**1. The machine floor is not the largest count sustained over a run of `RUN` samples; it is the minimum over the whole healthy streak so far.**

Lines 111 to 113:
```
        cur_min = n if cur_min is None else min(cur_min, n)
        if streak >= run_len and cur_min > floor_m:
            floor_m, best_run = cur_min, streak
```
`cur_min` is only reset when a sample is unhealthy, never when the window slides. A healthy streak that reads 5 sessions once and then 46 sessions for the next 50 samples yields a floor of 5, even though 46 was sustained for 50 consecutive healthy samples. The header at lines 25 to 27 promises the largest count across a run of consecutive samples, and the printed `best_run` is the streak prefix length, not the length of the run that supports the reported number. The published floor is therefore far too low whenever a low sample precedes a long high plateau in the same healthy stretch.

**2. "Consecutive" means adjacent in the file, not adjacent in time, so a run can span an outage.**

Line 109 and line 115:
```
        streak += 1
```
```
        streak, cur_min = 0, None
```
No timestamp check is made between neighbouring samples. If the alarm daemon stops for hours between two samples, they still extend the same streak, and a series such as 5 healthy samples at 46, a multi-hour gap, then 5 more at 46 satisfies `streak >= run_len` and publishes 46 as sustained for "10 minutes green" (line 52). The same file-order assumption drives the span computations at lines 120 and 128, which use only the first and last rows and assume they are chronologically ordered.

**3. A sample missing the swap field is counted as healthy, and the swap test does not match the documented criterion.**

Line 106:
```
    ok = r.get("verdict") == "OK" and float(r.get("swap_used_mb") or 0) <= 0
```
When `swap_used_mb` is absent or `null`, the expression becomes `float(0) <= 0`, which is true, so the sample passes the swap guard without any swap evidence. The header (line 27) says the floor requires "zero swap growth"; the code instead requires zero swap in use, so a box carrying a constant residual swap footprint never produces a healthy sample and the machine floor stays at 0 forever. Also, a non-numeric value in that field raises an uncaught `ValueError`, which aborts the script with a Python traceback and exit code 1, the code reserved for unreadable stores.

**4. When the utilization series spans the required window but yields no usable rows, the script misdiagnoses the cause and claims time will fix it.**

Lines 145 to 146 and lines 172 to 178:
```
    if per:
        pool = {"per_account": per, "total": sum(per.values())}
```
```
        short = max(0.0, need_h - u_span_h)
        print(f"POOL floor    : INSUFFICIENT-DATA — {len(util)} samples spanning {u_span_h:.0f}h, "
              f"need {need_h:.0f}h ({short:.0f}h short).")
```
If `u_span_h >= need_h` but every row is stale, has a non-integer `k`, a non-numeric `weekly_pct`, or `weekly_pct >= 100`, `pool` stays `None`. The output then reports INSUFFICIENT-DATA with "0h short" and states that nothing needs to run because the floor "becomes computable by elapsed time." That is false: no amount of elapsed time will change the result, and the real reason (no qualifying samples) is never reported.

**5. An unreadable utilization store is reported as an empty store rather than a read failure.**

Line 67, and lines 89 to 90, and lines 179 to 181:
```
[ -r "$CAP_LOG" ] || { echo "pool-floor: cannot read $CAP_LOG" >&2; exit 1; }
```
```
    except OSError:
        return
```
```
        if not util:
            print("                Store is EMPTY — no live sweep has happened since the "
```
Only the capacity log is readability-checked. If `UTIL_LOG` exists but cannot be opened (permissions, I/O error), `rows()` silently yields nothing, `util` is empty, and the script prints "Store is EMPTY — no live sweep has happened since the recorder landed" and exits 3. The header at lines 43 to 44 defines exit 1 as "the stores could not be read at all," so a read failure is reported as an honest non-verdict with a fabricated explanation.

**Minor, same category:** line 86 catches only `ValueError`, so a valid JSON line that is not an object (for example `[1,2]` or `3`) passes through, and `r.get(...)` at line 102 or 125 raises `AttributeError`, aborting the script with exit 1 rather than skipping the row.
