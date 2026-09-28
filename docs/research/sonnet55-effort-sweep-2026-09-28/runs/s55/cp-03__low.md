I found seven defects.

**1. The machine-floor run does not have to be consecutive in time, and dropped rows do not break it.**
- **What:** A "run of consecutive samples" is any adjacent surviving lines, whatever the gap between them or whatever was dropped.
- **Where:** line 103 `cap = [r for r in rows(cap_log) if isinstance(r.get("sessions"), int)]` and line 110 `streak += 1`
- **Why it is wrong:** Rows lacking an int `sessions` (including torn or skipped lines) are removed before the loop, so they never reset `streak`. Two healthy samples hours apart, or across an outage, also count as adjacent. Ten such samples are reported as "10 minutes green" when the box was never observed continuously. `bool` also passes `isinstance(..., int)`.

**2. The floor is the minimum over the whole streak, not over the best run of `run_len` samples.**
- **What:** `cur_min` is never windowed, so one early low sample caps every later value in that streak.
- **Where:** line 112 `cur_min = n if cur_min is None else min(cur_min, n)` and line 114 `floor_m, best_run = cur_min, streak`
- **Why it is wrong:** A long healthy streak that starts with a few samples at 2 sessions, then holds 40 for 30 minutes, reports a floor of 2. `best_run` is the streak length at the moment of the update, not the length of the run that supports `cur_min`. The result is not the "largest session count sustained across a run" that the header describes.

**3. The health test checks absolute swap use, not swap growth, and treats a missing field as healthy.**
- **What:** The header says "zero swap growth", but the code tests whether swap is in use at all.
- **Where:** line 107 `ok = r.get("verdict") == "OK" and float(r.get("swap_used_mb") or 0) <= 0`
- **Why it is wrong:**
  - A box with any constant pre-existing swap never has a healthy sample, so the floor is 0 forever.
  - A row with no `swap_used_mb` (or null) becomes 0 and passes, so the swap term is silently skipped.
  - A non-numeric string raises `ValueError` and crashes the script.
  - A non-dict JSON line makes `r.get` raise on line 103 or 107.

**4. The pool floor is a sum of per-account single-sample maxima taken at different times, with no run requirement and no health gate.**
- **What:** The pool figure is presented as "concurrent sessions" that were sustained, but nothing shows those counts coexisted or were sustained.
- **Where:** line 145 `per[r["acct"]] = max(per.get(r["acct"], 0), k)` and the pool output line `print(f"POOL floor    : {pool['total']} concurrent sessions ({pa}), each measured while "`
- **Why it is wrong:** The script's own comment says a floor wants "a run, not a spike", yet one sample per account sets its value. Account A's maximum can be from week 1 and account B's from week 3. The sum is then a concurrency the pool never carried, so it can overstate the floor, which is the opposite of what a floor is for. Only `weekly_pct < 100` gates a sample; the 5h and Fable percentages are ignored.

**5. The pool span counts stale rows, so the "full weekly window" guard can pass without enough real measurements.**
- **What:** The span gate uses the first and last rows, including stale ones, and does not require non-stale coverage.
- **Where:** line 129 `t0, t1 = ts_of(util[0]), ts_of(util[-1])` and line 133 `if u_span_h >= need_h:`
- **Why it is wrong:** Stale rows are excluded later (line 139), but they already counted toward the span. Two live samples a week apart, with stale rows in between, satisfy the "series spans a week" guard and publish a number. The same first/last-row logic assumes the log is in time order.

**6. An unreadable utilization store is reported as an empty one, and a sufficient span with no usable rows gets the wrong message.**
- **What:** Read errors on `UTIL_LOG` are swallowed. The stated "1 = the stores could not be read at all" exit is only checked for `CAP_LOG`.
- **Where:** line 89 `except OSError:` (followed by `return`), line 67 `[ -r "$CAP_LOG" ] || { echo "pool-floor: cannot read $CAP_LOG" >&2; exit 1; }`, and `print("                Store is EMPTY — no live sweep has happened since the "`
- **Why it is wrong:** A permission error or a missing `UTIL_LOG` yields zero rows. The script then asserts that no live sweep has happened, which is an unproven premise, and exits 3 instead of 1. If the span is at least `need_h` but every row is stale or malformed, `pool` is `None` and it prints "INSUFFICIENT-DATA … 0h short", which is misleading.

**7. Timestamp handling can crash on mixed timezone-aware and naive values, and non-string `ts` is masked.**
- **What:** Only `ValueError` is caught, but subtracting an aware datetime from a naive one raises `TypeError`.
- **Where:** line 123 `span_h = (t1 - t0).total_seconds() / 3600.0` (and the same subtraction at line 131)
- **Why it is wrong:** If the first row's `ts` has a `Z` or offset and the last does not, or the reverse, the script dies with a traceback and no verdict. Under `set -u` with no `-e`, that surfaces as exit 1, which the header defines as "stores could not be read".

Minor: line 63 `-h|--help) sed -n '2,50p' "$0"; exit 0 ;;` prints through line 50, which includes code lines (`set -uo pipefail`, the `CAP_LOG=` and `UTIL_LOG=` assignments) after the header ends at line 46.
