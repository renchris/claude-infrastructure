# Review of `scripts/pool-floor.sh`

I found 9 defects.

---

### 1. The machine floor takes the minimum over the whole streak, not over a run of `RUN` samples

**Where:** line 108
```python
        cur_min = n if cur_min is None else min(cur_min, n)
```
(used by `if streak >= run_len and cur_min > floor_m:`)

**Why it is wrong:** `cur_min` resets only when a sample is unhealthy, so it is the minimum over the entire healthy streak. Suppose one unbroken healthy streak starts overnight at 2 sessions and then holds 40 for hours. `cur_min` stays at 2 and the floor comes out as 2. The header defines the floor as the largest count sustained across a run of `RUN` consecutive samples. Any higher level sustained later in a streak that began lower is never credited. `best_run` is also just the streak length at the moment of the update, not the length of the run that justified the floor.

---

### 2. "Consecutive samples" are never checked for time contiguity

**Where:** lines 104–111, for example
```python
        streak += 1
```

**Why it is wrong:** The comment says 10 samples equal "10 minutes green". The code counts adjacent log lines and never compares their `ts`. If the alarm stopped, or the box slept or rebooted, 10 adjacent lines can be hours or days apart. The floor is then published as "sustained" without any evidence that the samples were continuous.

---

### 3. A missing swap field counts as "no swap in use"

**Where:** line 104
```python
    ok = r.get("verdict") == "OK" and float(r.get("swap_used_mb") or 0) <= 0
```

**Why it is wrong:** If `swap_used_mb` is absent or null, the `or 0` passes the swap test. This silently skips the half of the health check that the comment calls essential. The code also checks absolute swap in use, while the header promises "zero swap growth". Finally, if the field holds a non-numeric string, `float()` raises and the whole script dies with a traceback.

---

### 4. The pool floor is a single-sample maximum, i.e. a spike

**Where:** line 142
```python
            per[r["acct"]] = max(per.get(r["acct"], 0), k)
```

**Why it is wrong:** The script's own rationale says "one lucky sample … proves the box briefly held 46, not that it sustains it." This line still takes the maximum of any single sample, with no run requirement and no health requirement. One transient high `k` becomes that account's published floor.

---

### 5. Summing per-account maxima is not a conservative fleet figure

**Where:** line 144
```python
        pool = {"per_account": per, "total": sum(per.values())}
```

**Why it is wrong:** Each account's maximum may come from a different time. The sum is therefore a concurrency level that may never have been observed at once, which makes it closer to an upper estimate than a lower bound. The comment calls it "conservative", and it is also printed as "concurrent sessions". In addition, if only some of the four accounts have qualifying samples, the partial sum is still presented as the pool floor.

---

### 6. The span test measures endpoints, not coverage, and counts stale rows

**Where:** lines 128–131
```python
    t0, t1 = ts_of(util[0]), ts_of(util[-1])
```
and line 133
```python
if u_span_h >= need_h:
```

**Why it is wrong:**
- Two samples a week apart satisfy "spans a full weekly window" even though almost nothing between them was measured.
- The span includes rows that are later discarded as `stale`, so the "week of data" may be mostly non-measurements.
- File order is assumed to be chronological.
- If the first or last row has an unparseable `ts`, the span is 0 and the result stays INSUFFICIENT-DATA forever.

---

### 7. A permanently empty pool result is reported as "wait for elapsed time"

**Where:** lines 173–176
```python
        short = max(0.0, need_h - u_span_h)
```
```python
        print("                live sweep at no extra cost. Nothing to run; this becomes "
              "computable by elapsed time.")
```

**Why it is wrong:** The span can be sufficient while `per` is still empty. This happens when every row is `stale`, has `weekly_pct >= 100`, or has a non-int `k`. In that case `pool` is None and the output says "INSUFFICIENT-DATA … (0h short)" and "becomes computable by elapsed time". That is false: waiting will never produce a number, and the real cause is not named. This contradicts the header's promise that the script "names exactly what is missing".

---

### 8. An unreadable utilization store is reported as an empty store

**Where:** lines 79–80
```python
    except OSError:
        return
```
(with only `[ -r "$CAP_LOG" ]` checked at line 64)

**Why it is wrong:** If `UTIL_LOG` exists but cannot be read (permissions, I/O error), `rows()` yields nothing. The script then prints "Store is EMPTY — no live sweep has happened since the recorder landed" and exits 3. The header says an unreadable store should exit 1. The failure is reported as an honest non-verdict with a false diagnosis.

---

### 9. The exit code and verdict conflate the two floors

**Where:** line 157
```python
    "verdict": "OK" if (floor_m and pool) else "INSUFFICIENT-DATA",
```
and line 183
```python
sys.exit(0 if (floor_m and pool) else 3)
```

**Why it is wrong:** The header says exit 0 means "a floor was computed". There are two failure cases:
- A valid machine floor with no pool floor exits 3.
- A computed pool floor with `floor_m == 0` also exits 3 and reports INSUFFICIENT-DATA. The text output meanwhile prints a numeric POOL floor line and no explanation of what is insufficient.

In both cases the reported verdict contradicts the numbers printed.

---

**Minor, same class as #8:** `rows()` silently drops any unparseable line anywhere in the file, not just the torn last line its comment describes. This means real corruption is invisible. A valid-JSON line that is not an object would also crash the script at `r.get`.
