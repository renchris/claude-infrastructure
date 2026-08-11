1. **What** — Read failures inside either JSONL store are silently converted into end-of-file instead of producing the documented exit status 1.

   **Where** — Lines 88–89:

   ```bash
       except OSError:
           return
   ```

   **Why it is wrong** — If the utilization log is unreadable, or either file encounters an I/O error during iteration, the code uses empty or partial data and can return `INSUFFICIENT-DATA` or even success rather than reporting that the store could not be read.

2. **What** — Every malformed JSON line is silently treated as a harmless torn tail, even when it occurs in the middle of the file.

   **Where** — Lines 84–87:

   ```bash
                   try:
                       yield json.loads(line)
                   except ValueError:
                       continue                       # a torn last line mid-append is not corruption
   ```

   **Why it is wrong** — A corrupted middle record is discarded just like an incomplete final append, so calculations can continue and report success from a corrupted store; for machine data, records on either side can also become falsely adjacent.

3. **What** — Capacity records without an integer `sessions` value are removed before health evaluation, allowing an unhealthy or unknown sample to be skipped without breaking a run.

   **Where** — Line 100:

   ```bash
   cap = [r for r in rows(cap_log) if isinstance(r.get("sessions"), int)]
   ```

   **Why it is wrong** — If five healthy records are followed by an `ALERT` record whose session field is missing and then five more healthy records, the `ALERT` record disappears and the code counts a ten-sample healthy streak that never occurred.

4. **What** — The machine streak never verifies timestamps, so adjacent retained records are assumed to be uninterrupted 60-second samples regardless of their actual spacing or order.

   **Where** — Lines 103–110:

   ```bash
   for r in cap:
       ok = r.get("verdict") == "OK" and float(r.get("swap_used_mb") or 0) <= 0
       if ok:
           healthy_total += 1
           streak += 1
           n = r["sessions"]
           cur_min = n if cur_min is None else min(cur_min, n)
           if streak >= run_len and cur_min > floor_m:
   ```

   **Why it is wrong** — Ten healthy records separated by a daemon outage or long logging gaps satisfy `RUN=10`, causing the script to claim sustained concurrency even though the intervening period was unobserved.

5. **What** — A missing swap measurement is silently treated as zero swap and therefore as healthy.

   **Where** — Line 104:

   ```bash
       ok = r.get("verdict") == "OK" and float(r.get("swap_used_mb") or 0) <= 0
   ```

   **Why it is wrong** — When `swap_used_mb` is absent, `null`, or an empty string, `or 0` makes the swap condition pass; an `OK` verdict then advances the streak despite there being no evidence that swap was zero.

6. **What** — The running minimum is never reset as a fixed-length window advances within a healthy streak, so later qualifying high-concurrency runs are ignored.

   **Where** — Lines 109–113:

   ```bash
           cur_min = n if cur_min is None else min(cur_min, n)
           if streak >= run_len and cur_min > floor_m:
               floor_m, best_run = cur_min, streak
       else:
           streak, cur_min = 0, None
   ```

   **Why it is wrong** — With `RUN=10`, one healthy sample at 1 session followed by ten healthy samples at 10 sessions contains a valid ten-sample floor of 10, but `cur_min` remains 1 for the entire streak and the script reports only 1.

7. **What** — Zero is used both as the “no machine floor” sentinel and as the printed floor, so human mode reports an unproven floor as sustained while a genuine zero-session run cannot be recorded.

   **Where** — Lines 101, 110–111, 157, and 161–164:

   ```bash
   floor_m, best_run, streak, cur_min = 0, 0, 0, None
   ```

   ```bash
           if streak >= run_len and cur_min > floor_m:
               floor_m, best_run = cur_min, streak
   ```

   ```bash
       "verdict": "OK" if (floor_m and pool) else "INSUFFICIENT-DATA",
   ```

   ```bash
   elif not quiet:
       print(f"MACHINE floor : {floor_m} concurrent sessions sustained "
             f"({best_run} consecutive healthy samples; peak ever seen {peak}; "
             f"{healthy_total}/{len(cap)} samples healthy over {span_h:.0f}h)")
   ```

   **Why it is wrong** — With fewer than `RUN` healthy samples, human output says “0 concurrent sessions sustained” although no run qualified; conversely, `RUN` healthy samples at zero sessions never satisfy `cur_min > floor_m` and are treated as insufficient despite establishing a zero floor.

8. **What** — The weekly sufficiency gate uses the global span of all account-tagged rows, including stale or otherwise unusable rows, rather than qualifying measurement spans for each account.

   **Where** — Lines 123–130 and 135–140:

   ```bash
   util = [r for r in rows(util_log) if r.get("acct")]
   u_span_h, pool = 0.0, None
   if util:
       t0, t1 = ts_of(util[0]), ts_of(util[-1])
       if t0 and t1:
           u_span_h = (t1 - t0).total_seconds() / 3600.0

   if u_span_h >= need_h:
   ```

   ```bash
       for r in util:
           if r.get("stale"):
               continue                               # an inherited number is not a measurement
           w, k = r.get("weekly_pct"), r.get("k")
           if not isinstance(k, int) or not isinstance(w, (int, float)):
               continue
   ```

   **Why it is wrong** — Stale or invalid records, or records belonging to a different account, can establish the 168-hour span; one recent valid record can then produce a pool floor even though that account has not supplied a full weekly measurement series.

9. **What** — Any nonempty set of historical account identifiers is accepted and summed without proving that it is the box’s current four-account pool.

   **Where** — Lines 142–144:

   ```bash
               per[r["acct"]] = max(per.get(r["acct"], 0), k)
       if per:
           pool = {"per_account": per, "total": sum(per.values())}
   ```

   **Why it is wrong** — If an account is retired, replaced, or renamed, maxima for both the old and current identifiers remain in the append-only log and are added together, overstating the concurrency available from the current subscriptions.

10. **What** — Every missing pool result is reported as an elapsed-span shortage, even when the span requirement passed but no qualifying per-account measurements existed.

    **Where** — Lines 143–144 and 169–176:

    ```bash
       if per:
           pool = {"per_account": per, "total": sum(per.values())}
    ```

    ```bash
       else:
           short = max(0.0, need_h - u_span_h)
           print(f"POOL floor    : INSUFFICIENT-DATA — {len(util)} samples spanning {u_span_h:.0f}h, "
                 f"need {need_h:.0f}h ({short:.0f}h short).")
           print("                The recorder is bin/claude-accounts:record_utilization, which "
                 "appends on every")
           print("                live sweep at no extra cost. Nothing to run; this becomes "
                 "computable by elapsed time.")
    ```

    **Why it is wrong** — If the log spans 168 hours but every record is stale, malformed, or has `weekly_pct >= 100`, `per` remains empty and the script says it is “0h short” and will become computable through elapsed time, although qualifying measurements—not time—are missing.

11. **What** — The insufficient-data output omits the promised date on which the weekly span will become computable.

    **Where** — Lines 170–176:

    ```bash
           short = max(0.0, need_h - u_span_h)
           print(f"POOL floor    : INSUFFICIENT-DATA — {len(util)} samples spanning {u_span_h:.0f}h, "
                 f"need {need_h:.0f}h ({short:.0f}h short).")
           print("                The recorder is bin/claude-accounts:record_utilization, which "
                 "appends on every")
           print("                live sweep at no extra cost. Nothing to run; this becomes "
                 "computable by elapsed time.")
    ```

    **Why it is wrong** — Whenever the series is genuinely short of 168 hours, the script supplies only a rounded duration; neither human nor JSON output contains the stated calendar date.

12. **What** — Whole-hour rounding can report that the pool is insufficient while simultaneously claiming it has the required span and is zero hours short.

    **Where** — Lines 171–172:

    ```bash
           print(f"POOL floor    : INSUFFICIENT-DATA — {len(util)} samples spanning {u_span_h:.0f}h, "
                 f"need {need_h:.0f}h ({short:.0f}h short).")
    ```

    **Why it is wrong** — With `u_span_h = 167.6` and `need_h = 168`, the exact gate fails, but the output rounds both the span and the 0.4-hour deficit and prints “spanning 168h, need 168h (0h short).”