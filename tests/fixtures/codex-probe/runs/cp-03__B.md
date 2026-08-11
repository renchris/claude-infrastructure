1. **What** — An unreadable utilization log is silently treated as an empty store rather than a read failure.

   **Where** — Lines 66, 88–89, and 123:
   ```bash
   [ -r "$CAP_LOG" ] || { echo "pool-floor: cannot read $CAP_LOG" >&2; exit 1; }
   ```
   ```python
       except OSError:
           return
   ```
   ```python
   util = [r for r in rows(util_log) if r.get("acct")]
   ```

   **Why it is wrong** — If `UTIL_LOG` exists but cannot be opened, `rows()` returns no records, so the script reports `INSUFFICIENT-DATA`/“Store is EMPTY” and exits 3 instead of reporting the read failure with exit 1.

2. **What** — Every malformed JSON line is silently discarded even though the exception is justified only for a torn final line.

   **Where** — Lines 84–87:
   ```python
                   try:
                       yield json.loads(line)
                   except ValueError:
                       continue                       # a torn last line mid-append is not corruption
   ```

   **Why it is wrong** — A malformed interior record is skipped as though it never existed; in the capacity log this can join the healthy records on either side into a purported consecutive run, and in either log it can produce a result from incomplete, corrupted evidence.

3. **What** — Span calculation uses only the first and last eligible records rather than the valid timestamp extent of the data.

   **Where** — Lines 117–120 and 125–128:
   ```python
   if cap:
       t0, t1 = ts_of(cap[0]), ts_of(cap[-1])
       if t0 and t1:
           span_h = (t1 - t0).total_seconds() / 3600.0
   ```
   ```python
   if util:
       t0, t1 = ts_of(util[0]), ts_of(util[-1])
       if t0 and t1:
           u_span_h = (t1 - t0).total_seconds() / 3600.0
   ```

   **Why it is wrong** — If the first record has an invalid timestamp, all later valid utilization records can cover more than a week but `u_span_h` remains zero; out-of-order endpoints can likewise overstate, understate, or negate the actual span.

4. **What** — A missing swap measurement is interpreted as proof that swap usage is zero.

   **Where** — Line 104:
   ```python
       ok = r.get("verdict") == "OK" and float(r.get("swap_used_mb") or 0) <= 0
   ```

   **Why it is wrong** — A record whose verdict is `OK` but whose `swap_used_mb` field is absent, null, or empty increments the healthy streak, so ten records with no swap evidence can establish a machine floor.

5. **What** — The machine-health test checks zero swap usage, although the declared floor criterion is zero swap growth.

   **Where** — Lines 27 and 104:
   ```bash
   #   samples with verdict=OK and zero swap growth. This is a real lower bound on what the hardware
   ```
   ```python
       ok = r.get("verdict") == "OK" and float(r.get("swap_used_mb") or 0) <= 0
   ```

   **Why it is wrong** — When swap remains stable at a positive value, swap growth is zero and the sample meets the stated criterion, but the code marks it unhealthy and can report a machine floor lower than the stated largest qualifying floor.

6. **What** — Adjacent log records are counted as consecutive 60-second samples without checking their timestamps.

   **Where** — Lines 103–107:
   ```python
   for r in cap:
       ok = r.get("verdict") == "OK" and float(r.get("swap_used_mb") or 0) <= 0
       if ok:
           healthy_total += 1
           streak += 1
   ```

   **Why it is wrong** — If recording stops for hours or days between two healthy rows, those rows still extend the same streak, allowing ten widely separated observations to be reported as ten consecutive samples and ten minutes of sustained capacity.

7. **What** — The machine-floor algorithm takes the minimum over the entire healthy streak and therefore misses better qualifying sub-runs later in that streak.

   **Where** — Lines 109–111:
   ```python
           cur_min = n if cur_min is None else min(cur_min, n)
           if streak >= run_len and cur_min > floor_m:
               floor_m, best_run = cur_min, streak
   ```

   **Why it is wrong** — For eleven healthy samples with session counts `1, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10`, the final ten-sample run sustains 10, but `cur_min` remains 1 and the script reports a machine floor of 1.

8. **What** — Later counterexamples never lower an already recorded machine floor, contrary to the stated falsifiability rule.

   **Where** — Lines 19 and 110–113:
   ```bash
   # and it is falsifiable — one counter-example sample lowers it. It is also the honest shape for
   ```
   ```python
           if streak >= run_len and cur_min > floor_m:
               floor_m, best_run = cur_min, streak
       else:
           streak, cur_min = 0, None
   ```

   **Why it is wrong** — After ten healthy samples establish a floor at a given concurrency, a later unhealthy sample at that concurrency merely resets the current streak; `floor_m` retains the historical value and is never lowered.

9. **What** — Human-readable output labels zero as a sustained machine floor even when no qualifying run was found.

   **Where** — Lines 157 and 162–164:
   ```python
       "verdict": "OK" if (floor_m and pool) else "INSUFFICIENT-DATA",
   ```
   ```python
       print(f"MACHINE floor : {floor_m} concurrent sessions sustained "
             f"({best_run} consecutive healthy samples; peak ever seen {peak}; "
             f"{healthy_total}/{len(cap)} samples healthy over {span_h:.0f}h)")
   ```

   **Why it is wrong** — With fewer than `RUN` healthy samples, `floor_m` and `best_run` remain zero, yet the script prints `MACHINE floor : 0 concurrent sessions sustained (0 consecutive healthy samples)` instead of identifying the machine result as uncomputed.

10. **What** — The pool’s weekly-span prerequisite can be satisfied by stale rows or by history belonging to accounts other than the account whose floor is published.

    **Where** — Lines 123–130 and 135–137:
    ```python
    util = [r for r in rows(util_log) if r.get("acct")]
    u_span_h, pool = 0.0, None
    if util:
        t0, t1 = ts_of(util[0]), ts_of(util[-1])
        if t0 and t1:
            u_span_h = (t1 - t0).total_seconds() / 3600.0

    if u_span_h >= need_h:
    ```
    ```python
        for r in util:
            if r.get("stale"):
                continue                               # an inherited number is not a measurement
    ```

    **Why it is wrong** — Week-separated stale records can make the global guard pass even though they are explicitly not measurements, and one fresh sample for a newly seen account can then receive a published floor without that account having a full weekly series.

11. **What** — A single utilization sample can establish a pool floor even though the script defines a floor as a sustained run rather than a spike.

    **Where** — Lines 135 and 141–142:
    ```python
        for r in util:
    ```
    ```python
            if w < 100:
                per[r["acct"]] = max(per.get(r["acct"], 0), k)
    ```

    **Why it is wrong** — Once the global span guard passes, one isolated high `k` value under 100% becomes that account’s floor without any consecutive-sample or duration requirement, so an instantaneous spike is reported as sustained capacity.

12. **What** — The pool total sums per-account maxima that need not have occurred concurrently.

    **Where** — Lines 142–144:
    ```python
                per[r["acct"]] = max(per.get(r["acct"], 0), k)
        if per:
            pool = {"per_account": per, "total": sum(per.values())}
    ```

    **Why it is wrong** — If account A reaches 10 sessions only while B has 0, and later B reaches 10 only while A has 0, the code reports a measured pool floor of 20 even though the largest observed concurrent total was 10.

13. **What** — The insufficient-data result omits the promised date on which the pool floor becomes computable.

    **Where** — Lines 38 and 170–172:
    ```bash
    #   Until then the verdict is INSUFFICIENT-DATA with the date it becomes computable — NOT a
    ```
    ```python
            short = max(0.0, need_h - u_span_h)
            print(f"POOL floor    : INSUFFICIENT-DATA — {len(util)} samples spanning {u_span_h:.0f}h, "
                  f"need {need_h:.0f}h ({short:.0f}h short).")
    ```

    **Why it is wrong** — When utilization data has begun but covers less than 168 hours, the output provides only a rounded duration and never reports the calendar date that the file explicitly promises.