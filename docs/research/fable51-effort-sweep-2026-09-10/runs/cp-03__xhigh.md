I read the full listing and counted line numbers from the top of the file as shown in the brief. I found nine defects. The most serious is in the machine floor loop, which takes the minimum over an entire healthy streak instead of over a window, so the published floor collapses toward the streak's idle minimum.

**1. The machine floor is the minimum over the whole healthy streak, not over any window of RUN samples.**

Where: lines 111 to 113

```
        cur_min = n if cur_min is None else min(cur_min, n)
        if streak >= run_len and cur_min > floor_m:
            floor_m, best_run = cur_min, streak
```

Why: The streak only resets on an unhealthy sample, and cur_min only ever decreases within a streak. A healthy streak of 2 sessions for 10 samples followed by 40 sessions for 20 samples yields a floor of 2. The box held 40 for twice the required run, and that is the correct floor. On a box that stays healthy for days, cur_min becomes the all-time minimum of the streak, typically the overnight idle count. If a streak's first RUN samples include a 0-session sample, that streak can never raise the floor. The result is exit 3 and INSUFFICIENT-DATA despite hours sustained at 14 or more sessions.

**2. The swap term rejects any swap in use, but the floor is defined on zero swap growth.**

Where: line 106

```
    ok = r.get("verdict") == "OK" and float(r.get("swap_used_mb") or 0) <= 0
```

Why: Line 27 defines a healthy sample as verdict OK with zero swap growth. The code instead rejects any sample whose swap_used_mb is positive. On macOS, swap once used commonly stays reported as used until reboot. A box carrying a few resident megabytes then has no healthy samples at all. The machine floor is 0 for the life of the log, and the text output reports 0 of N samples healthy while every verdict was OK.

**3. A sample with no swap reading is credited as swap-free.**

Where: line 106, the same line as above

Why: The expression `r.get("swap_used_mb") or 0` turns a missing or null field into 0, which passes the test. Samples written before the alarm recorded swap, or samples where the reading failed, count as healthy on verdict alone. The requirement that both terms hold is silently dropped for exactly the samples where the second term was never measured.

**4. The reported run length is the streak length at first credit, not the run over which the floor held.**

Where: lines 112 to 113

```
        if streak >= run_len and cur_min > floor_m:
            floor_m, best_run = cur_min, streak
```

Why: Once floor_m equals cur_min, the comparison is false for the rest of the streak, so best_run freezes at the moment of credit. A floor of 20 held for 110 consecutive healthy samples prints as "20 concurrent sessions sustained (10 consecutive healthy samples)". Both the JSON field and the text line understate the evidence behind the floor.

**5. The pool floor is a single-sample peak per account, summed across sweeps taken at different times.**

Where: lines 144 and 146

```
            per[r["acct"]] = max(per.get(r["acct"], 0), k)
```
```
        pool = {"per_account": per, "total": sum(per.values())}
```

Why: Lines 51 to 52 state that one lucky sample proves a box briefly held N, not that it sustains it, and impose a run for that reason. The pool path applies no run at all. One sweep showing k of 12 for an account sets that account's floor to 12. The total then adds maxima that may come from sweeps days apart, so the number labelled POOL floor was never observed concurrently. Line 3 promises the script never extrapolates.

**6. The weekly-span gate checks only the first and last timestamps, not that the series covers the window.**

Where: lines 128 and 132

```
    t0, t1 = ts_of(util[0]), ts_of(util[-1])
```
```
if u_span_h >= need_h:
```

Why: A store with one row from a recorder test a month ago and one row today passes the gate with two samples. A store with a six-day gap where the recorder was broken also passes. Lines 39 to 41 say the gate exists to stop a floor being published from four days of data. The gate measures elapsed wall clock, not days of data, so that case is not blocked.

**7. The INSUFFICIENT-DATA message asserts that elapsed time is what is missing without checking that it is.**

Where: lines 172 to 178

```
        short = max(0.0, need_h - u_span_h)
```
```
        print("                live sweep at no extra cost. Nothing to run; this becomes "
              "computable by elapsed time.")
```

Why: pool stays None in cases that time cannot fix. If the span is met but every row is stale, lacks an integer k, or shows weekly_pct at 100 or more, per is empty and the output says 0h short and that waiting will resolve it. If the ts field in the store is not in ISO 8601 form, ts_of returns None, u_span_h stays 0.0, and the message reports the full shortfall forever. In each case the operator is told to wait when waiting cannot help.

**8. An unreadable or unparseable utilization store is reported as an empty store with exit 3, not as a read failure with exit 1.**

Where: lines 67, 89 to 90, and 180 to 181

```
[ -r "$CAP_LOG" ] || { echo "pool-floor: cannot read $CAP_LOG" >&2; exit 1; }
```
```
    except OSError:
        return
```
```
            print("                Store is EMPTY — no live sweep has happened since the "
                  "recorder landed.")
```

Why: Only the capacity log is checked for readability. If the utilization log exists but is permission-denied or is a directory, the OSError is swallowed and util is empty. The script then states that no live sweep has happened since the recorder landed and exits 3, the code line 43 reserves for an honest non-verdict. Line 44 assigns exit 1 to stores that could not be read. The same false diagnosis prints when every line fails to parse or every row lacks an acct field.

**9. The verdict is a single bit over two independent stores, and a missing machine floor is printed as a measured zero.**

Where: lines 159, 164, and 183

```
    "verdict": "OK" if (floor_m and pool) else "INSUFFICIENT-DATA",
```
```
    print(f"MACHINE floor : {floor_m} concurrent sessions sustained "
```
```
sys.exit(0 if (floor_m and pool) else 3)
```

Why: When no run of RUN healthy samples exists, floor_m is 0 and text mode prints "MACHINE floor : 0 concurrent sessions sustained (0 consecutive healthy samples ...)". That is a non-result in the shape of a measurement, with no INSUFFICIENT-DATA marker on the line. In the other direction, during the first week after the recorder landed the machine floor is computed and, per line 28, is the binding constraint. The exit code is still 3 and the JSON verdict is still INSUFFICIENT-DATA because the unrelated pool store is short. A caller keyed on the exit code cannot tell which store fell short or whether any floor exists.
