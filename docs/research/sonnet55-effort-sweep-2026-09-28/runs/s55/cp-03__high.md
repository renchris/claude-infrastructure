I found the defects below. I read only the text of the brief, and no tools were used.

**1. The pool-span gate is measured on rows that are then thrown away, and across all accounts combined.**
- **What:** The "series spans a full weekly window" guard counts stale rows and rows lacking `k` or `weekly_pct`, and it measures the span across all accounts pooled together.
- **Where:** lines 128-132: `t0, t1 = ts_of(util[0]), ts_of(util[-1])` and `if u_span_h >= need_h:`
- **Why it is wrong:** If `util` has 200 h of stale rows, or one account with 200 h of history and three accounts with an hour each, the gate passes. `per` is then built from the few surviving rows, or from a single account. A "POOL floor" is published, and the verdict is OK, on much less than a week of measurement per account. That is the four-days-of-data figure the header says must not be published.

**2. The pool "floor" is a single-sample maximum, and the sum of those maxima was never concurrent.**
- **What:** Each account's figure is the largest `k` seen in any one sample, and the accounts' figures are added together. Neither a sustained run nor simultaneity is required.
- **Where:** line 144: `per[r["acct"]] = max(per.get(r["acct"], 0), k)`, and line 146: `pool = {"per_account": per, "total": sum(per.values())}`
- **Why it is wrong:** Line 51 says a floor wants a run, not a spike, and the machine floor enforces that. Here one sample with `k=30` at weekly 5% sets the account's "floor" to 30. Account A's maximum and account B's maximum may be weeks apart, so their sum was never sustained at once. The comment calls this "conservative", but it is a sum of peaks. The only condition checked is `weekly_pct < 100`, which is not a health signal, so the output "each measured while that account's weekly window was under 100%" says nothing about sustainability.

**3. A missing or absent account is not detected.**
- **What:** The pool total is the sum over whichever accounts appear in the log, with no check that all four are present.
- **Where:** line 145-146: `if per:` / `pool = {"per_account": per, "total": sum(per.values())}`
- **Why it is wrong:** If only one or two accounts ever produced a qualifying row, the total covers those alone. It is still reported as the pool floor with verdict OK. If every qualifying `k` is 0, `pool` is still a truthy dict, so a floor of 0 counts as "computed".

**4. The INSUFFICIENT-DATA message is false when the span is satisfied but `per` is empty.**
- **What:** The message says the data is short by a number of hours and that the floor becomes computable by elapsed time, even when no time is missing.
- **Where:** line 159 (the `"verdict": "OK" if (floor_m and pool) else "INSUFFICIENT-DATA"` line), together with the printing branch `else:` / `short = max(0.0, need_h - u_span_h)` / `print(f"POOL floor    : INSUFFICIENT-DATA — {len(util)} samples spanning {u_span_h:.0f}h, "`
- **Why it is wrong:** If the log spans 200 h but every row is stale, lacks `k`, or has `weekly_pct >= 100`, the output reads "need 168h (0h short)… becomes computable by elapsed time". Waiting will not fix that. The script was meant to name exactly what is missing.

**5. The verdict can be INSUFFICIENT-DATA with no reason given when the machine floor is the problem.**
- **What:** When `floor_m` is 0 but `pool` exists, the script exits 3 and prints nothing about the shortfall.
- **Where:** line 159: `"verdict": "OK" if (floor_m and pool) else "INSUFFICIENT-DATA",` and the final `sys.exit(0 if (floor_m and pool) else 3)`
- **Why it is wrong:** The machine line prints "0 concurrent sessions sustained", and the pool line prints a normal-looking floor. The exit code and JSON verdict say INSUFFICIENT-DATA, and no line says which floor is missing.

**6. Missing or garbage swap data counts as healthy, and a non-numeric value crashes the script.**
- **What:** A sample with no `swap_used_mb` field is treated as zero swap. A non-numeric string aborts the run.
- **Where:** line 107: `ok = r.get("verdict") == "OK" and float(r.get("swap_used_mb") or 0) <= 0`
- **Why it is wrong:**
  - **Missing field:** `None or 0` becomes 0, so a sample that never reported swap passes the swap term. That term is described as the one that makes this a floor.
  - **Non-numeric value:** `float("n/a")` raises an uncaught `ValueError`. The traceback exits 1, which the header reserves for "stores could not be read".
  - **Header mismatch:** The header says "zero swap growth", but the code tests absolute swap in use. A box with constant nonzero swap never gets a floor, and growth is never tested.

**7. Samples that are dropped by the filter do not break a run, and time gaps are ignored.**
- **What:** "Consecutive" means consecutive in the filtered list, with no check on timestamps.
- **Where:** line 103: `cap = [r for r in rows(cap_log) if isinstance(r.get("sessions"), int)]` and line 112: `if streak >= run_len and cur_min > floor_m:`
- **Why it is wrong:**
  - **Filtered samples:** A sample that lacks an integer `sessions` (an error or degraded sample) is removed before the streak logic, so it does not reset the streak. Healthy samples on either side join into one run.
  - **Time gaps:** If the alarm was down for hours, 10 rows on either side of the gap count as "10 minutes green".

**8. The machine floor under-reports because the minimum is taken over the whole streak, not a window.**
- **What:** `cur_min` is the minimum since the streak began, so it never recovers.
- **Where:** line 111: `cur_min = n if cur_min is None else min(cur_min, n)`
- **Why it is wrong:** Take a streak of 10 samples at 5 sessions followed by 100 healthy samples at 40. `cur_min` stays 5, so 40 sustained for 100 minutes is never recorded. The header promises "the largest session count sustained across a run", and this does not compute that.

**9. Unreadable stores are reported as empty stores.**
- **What:** Any `OSError` on the utilization log is swallowed and looks like "no data".
- **Where:** lines 89-90: `except OSError:` / `return`, with the message `print("                Store is EMPTY — no live sweep has happened since the "`
- **Why it is wrong:** If `UTIL_LOG` exists but is unreadable, the script prints that no live sweep has happened. That is a premise it has not verified. The same swallowing means a directory passed as `CAP_LOG` (which passes `[ -r ]` at line 67) gives exit 3 instead of the documented exit 1.

**10. The timestamp helper can crash, and it silently zeroes the span.**
- **What:** `ts_of` catches only `ValueError`, and the span code assumes ordered, parseable first and last rows.
- **Where:** line 94: `return datetime.fromisoformat(str(r.get("ts", "")).replace("Z", "+00:00"))`, and lines 120-122 and 128-130 (`if t0 and t1:`)
- **Why it is wrong:**
  - **Mixed timestamps:** If one row's `ts` has `Z` or an offset and another is naive, `t1 - t0` raises an uncaught `TypeError`.
  - **Unparseable end rows:** If the first or last row has a missing or unparseable `ts`, the span silently becomes 0. This can wrongly force INSUFFICIENT-DATA on a week-long series.
  - **Ordering:** Taking the span from the first and last rows assumes the file is in chronological order.

**11. The `--help` output includes code.**
- **What:** Help prints lines beyond the header comment.
- **Where:** line 63: `-h|--help) sed -n '2,50p' "$0"; exit 0 ;;`
- **Why it is wrong:** The header ends at line 46, so `-n '2,50p'` also prints `set -uo pipefail` and the `CAP_LOG=` and `UTIL_LOG=` assignments as if they were documentation.
