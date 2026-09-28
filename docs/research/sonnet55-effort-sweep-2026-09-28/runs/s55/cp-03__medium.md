I found seven defects.

**1. The "consecutive" run is consecutive in the file, not in time.**
- **What:** Samples are treated as one run by file adjacency, with no check on the timestamp gap between them.
- **Where:** lines 111 and 114: `streak += 1` and `if streak >= run_len and cur_min > floor_m:`
- **Why it is wrong:** The comment says 10 samples means 10 minutes green. If the box was off or the logger was down, 10 healthy samples hours or days apart still count as a run. Rows dropped by the `isinstance(r.get("sessions"), int)` filter at line 104 also leave the streak unbroken. The floor is then published as "sustained" when it was never observed continuously.

**2. The run's session count is the minimum over the whole streak, not over the qualifying window.**
- **What:** `cur_min` accumulates from the start of the streak, so the floor is capped by the lowest sample anywhere earlier in it.
- **Where:** line 113: `cur_min = n if cur_min is None else min(cur_min, n)`
- **Why it is wrong:** Take one healthy sample at 5 sessions followed by 50 healthy samples at 40. The floor stays 5, although 40 was sustained for 10 or more samples. It under-reports the "largest session count sustained across a run", and `best_run` reports the whole streak length rather than a `run_len` window.

**3. A missing or null swap field counts as "no swap".**
- **What:** The swap check passes when the field is absent, and it crashes on a non-numeric value.
- **Where:** line 108: `ok = r.get("verdict") == "OK" and float(r.get("swap_used_mb") or 0) <= 0`
- **Why it is wrong:** A row without `swap_used_mb` (older schema, failed probe) is treated as swap-free and counted healthy, so the second guard is silently skipped. A string like `"n/a"` raises an uncaught `ValueError` and aborts the whole script.

**4. The pool floor is a single-sample maximum, not a sustained value, and the sum is not a simultaneous figure.**
- **What:** Each account's floor is the highest `k` ever seen, with no run requirement and no machine-health condition. The per-account maxima are then summed.
- **Where:** line 146: `per[r["acct"]] = max(per.get(r["acct"], 0), k)`, and line 148: `pool = {"per_account": per, "total": sum(per.values())}`
- **Why it is wrong:** The header says one lucky sample proves nothing, yet one spike sample sets an account's number. The maxima can come from different weeks, so the sum is a level that was never held concurrently. The comment calls it "the conservative fleet figure", but it is not a lower bound.

**5. The span check only compares the first and last timestamps.**
- **What:** "The series spans a weekly window" is judged from the first and last rows alone.
- **Where:** lines 130-132 and 134: `t0, t1 = ts_of(util[0]), ts_of(util[-1])` and `if u_span_h >= need_h:`
- **Why it is wrong:** Two samples 168 hours apart pass the gate, and the pool number is computed from almost no data. Ordering is also assumed. An unparseable first or last timestamp gives `None`, which leaves the span at 0 with no indication why. The same first/last logic drives `span_h` at lines 122-124.

**6. Mixing naive and aware timestamps crashes the script.**
- **What:** `ts_of` catches only `ValueError`, but subtracting a naive datetime from an aware one raises `TypeError`.
- **Where:** line 124: `span_h = (t1 - t0).total_seconds() / 3600.0` and line 132: `u_span_h = (t1 - t0).total_seconds() / 3600.0`
- **Why it is wrong:** If one endpoint has a `Z` or offset and the other does not, the script dies with a traceback and no verdict. The failure does not map to any of the documented exit codes.

**7. Failure paths are reported as "insufficient data, wait for time".**
- **What:** An unreadable utilization log, or a pool that comes out empty after the span gate passes, is reported as a data shortage that elapsed time will fix.
- **Where:** line 91: `return` (inside `except OSError:`), line 175: `print(f"POOL floor    : INSUFFICIENT-DATA — {len(util)} samples spanning {u_span_h:.0f}h, "`, and the message text "this becomes computable by elapsed time"
- **Why it is wrong:**
  - **Unreadable log:** A missing or permission-denied `UTIL_LOG` is swallowed by `rows` and looks like an empty store. The script prints "no live sweep has happened", not an error, unlike the hard exit 1 for `CAP_LOG`.
  - **Empty pool after the gate:** If the span is already ≥ `need_h` but every row is stale, lacks an int `k`, or has weekly ≥ 100, `pool` stays `None`. It then prints "need 168h (0h short)… computable by elapsed time", which is false, and exits 3.
