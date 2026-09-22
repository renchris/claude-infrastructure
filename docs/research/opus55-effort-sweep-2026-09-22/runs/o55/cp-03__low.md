# Review of `scripts/pool-floor.sh`

I found nine defects.

### 1. The pool floor is a single-sample peak, not a sustained floor
- **What:** Each account's "floor" is the largest `k` seen in any one sample, so it is a peak, not a sustained lower bound.
- **Where:** line ~137: `per[r["acct"]] = max(per.get(r["acct"], 0), k)`
- **Why it is wrong:** Say one sweep records an account at k=12 with weekly at 40%, and every other sweep shows 3. The pool floor reports 12. That is the "one lucky sample" spike the script itself rejects for the machine floor (the `RUN` comment). The output is then presented as "concurrent sessions … measured", which overstates what was shown.

### 2. The summed pool total was never observed concurrently
- **What:** The total adds per-account maxima taken at different times and presents the sum as a concurrent figure.
- **Where:** `pool = {"per_account": per, "total": sum(per.values())}`
- **Why it is wrong:** Suppose account A peaked at 10 on Monday and account B peaked at 10 on Friday. The script reports "20 concurrent sessions", but the fleet never ran 20 at once. That is not a conservative figure; it is an upper-leaning one.

### 3. Rows dropped before the streak loop silently join runs
- **What:** Samples without an int `sessions` are removed before streak counting, so they never break a run.
- **Where:** `cap = [r for r in rows(cap_log) if isinstance(r.get("sessions"), int)]` (and `rows()` skipping unparseable lines)
- **Why it is wrong:** Suppose a sample has verdict CRIT but `sessions: null`, or a line is malformed mid-file. It disappears, and the healthy samples on either side merge into one "consecutive" run. A run that was actually broken can then set the floor.

### 4. "Consecutive" ignores gaps in time
- **What:** A streak counts adjacent rows with no check that they are about 60 s apart.
- **Where:** `streak += 1`
- **Why it is wrong:** Suppose the alarm was down, or the box slept, for hours between samples. Ten rows spread across a day still count as "10 minutes green", so the sustained-run guarantee does not hold.

### 5. The span check ignores gaps and never checks coverage
- **What:** The data span is simply the last timestamp minus the first, with no check that the samples in between cover the window.
- **Where:** `u_span_h = (t1 - t0).total_seconds() / 3600.0` and `if u_span_h >= need_h:`
- **Why it is wrong:** Two samples 168 h apart, with nothing between them, satisfy "the series spans a full weekly window". A pool number is then published from essentially no data, which is exactly what the header says must not happen.

### 6. Mixed naive and aware timestamps crash the script, and the crash reads as exit 1
- **What:** Mixing naive and aware timestamps raises an exception, which surfaces as exit 1.
- **Where:** `span_h = (t1 - t0).total_seconds() / 3600.0` (and the `u_span_h` equivalent)
- **Why it is wrong:** If the first row's `ts` has `Z` and the last has no offset, subtracting them raises `TypeError`. Python exits 1, which the script's contract defines as "stores could not be read". The same happens when `float(r.get("swap_used_mb") or 0)` meets a non-numeric string.

### 7. An unreadable or empty utilization store is reported as INSUFFICIENT-DATA
- **What:** An unreadable `UTIL_LOG`, or an unusable `CAP_LOG`, is reported as an honest non-verdict (exit 3) instead of a read failure (exit 1).
- **Where:** `except OSError: return` in `rows()`. Only `[ -r "$CAP_LOG" ]` is checked in bash.
- **Why it is wrong:**
  - If the utilization log has bad permissions, it is treated as empty, and the script prints "Nothing to run; this becomes computable by elapsed time". That will never become true.
  - If `CAP_LOG` is readable but every line is corrupt, the result is also exit 3, not exit 1.

### 8. Misleading message when the span is met but no usable rows exist
- **What:** When the span requirement is met but no row qualifies, the output still reports a time shortfall.
- **Where:** `short = max(0.0, need_h - u_span_h)` and the INSUFFICIENT-DATA print
- **Why it is wrong:** Suppose every row is `stale`, lacks int `k`, or has weekly ≥ 100 over a full week. The output says "need 168h (0h short)" and "becomes computable by elapsed time". The real problem is the data, and waiting will not fix it.

### 9. Stale rows count toward the required span
- **What:** The span that gates computation is measured across all rows, including `stale` ones.
- **Where:** `util = [r for r in rows(util_log) if r.get("acct")]`, which is then used for `u_span_h`
- **Why it is wrong:** Suppose the series is mostly inherited (stale) values with a few real measurements. The weekly-window requirement is still judged satisfied, even though the actual measurements may cover far less than 168 h.
