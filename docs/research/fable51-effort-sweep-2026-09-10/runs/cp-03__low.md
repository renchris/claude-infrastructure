Reviewing `scripts/pool-floor.sh` from the brief text alone. Findings below.

**Defect 1 — machine floor uses the minimum over the whole healthy streak, not a sliding window of RUN samples**

- Where: lines 111–113
  ```
  cur_min = n if cur_min is None else min(cur_min, n)
  if streak >= run_len and cur_min > floor_m:
      floor_m, best_run = cur_min, streak
  ```
- Why: `cur_min` only resets when an unhealthy sample breaks the streak. If the box is healthy for 100 consecutive samples starting at 5 sessions and then holds 40 sessions for the last 50 of them, `cur_min` stays 5 and the floor is published as 5. The header promises "the largest session count sustained across a run of consecutive samples"; 40 was sustained for 50 minutes green and is discarded. The floor is systematically understated on any long uptime, and `best_run` reports the streak length at the moment of the update rather than the run that backs the number.

**Defect 2 — "consecutive samples" ignores time gaps, so a run can span hours of missing data**

- Where: lines 109 and 112, with the premise at line 52
  ```
  streak += 1
  if streak >= run_len and cur_min > floor_m:
  # 46, not that it sustains it. 10 consecutive 60 s samples = 10 minutes green.
  ```
- Why: adjacency in the file is treated as adjacency in time. If the alarm stopped writing for a day, five samples before the gap and five after count as ten consecutive healthy minutes. The floor is then published from a "run" that was never sustained, which is exactly the spike the comment says it rejects.

**Defect 3 — an unreadable utilization store is reported as an empty store**

- Where: lines 89–90, 67, and 179–181
  ```
  except OSError:
      return
  [ -r "$CAP_LOG" ] || { echo "pool-floor: cannot read $CAP_LOG" >&2; exit 1; }
  if not util:
      print("                Store is EMPTY — no live sweep has happened since the "
  ```
- Why: only the capacity log is checked for readability. If the utilization log exists but has wrong permissions or is a broken path, the OSError is swallowed, `util` is empty, and the script prints that no live sweep has happened. The header defines exit 1 for "stores could not be read at all"; instead a read failure is reported as a diagnosis about the recorder.

**Defect 4 — a missing swap field is treated as proof of zero swap**

- Where: line 106
  ```
  ok = r.get("verdict") == "OK" and float(r.get("swap_used_mb") or 0) <= 0
  ```
- Why: a sample with no `swap_used_mb` key, or with `null`, satisfies the swap guard. The header says a healthy sample requires "zero swap growth" as a second independent term. Rows that never measured swap count as healthy, so the floor can be built from samples where the guard was skipped rather than passed. Additionally a non-numeric value raises an uncaught ValueError, which exits 1 and is indistinguishable from an unreadable store.

**Defect 5 — the weekly-span check is satisfied by rows that are then discarded as non-measurements**

- Where: lines 125–130 and 138–139
  ```
  util = [r for r in rows(util_log) if r.get("acct")]
  if r.get("stale"):
      continue                               # an inherited number is not a measurement
  ```
- Why: `u_span_h` is computed from the first and last rows of the whole store, including stale rows and rows lacking `weekly_pct` or `k`. A store whose first 160 hours are stale inherited numbers and whose last eight hours are real passes the 168 h gate, and a pool floor is published from eight hours of measurement. The header says a number from a short series must not publish.

**Defect 6 — a bad or missing timestamp on the first or last row silently zeroes the span**

- Where: lines 94–96 and 120–122 / 128–130
  ```
  return datetime.fromisoformat(str(r.get("ts", "")).replace("Z", "+00:00"))
  t0, t1 = ts_of(util[0]), ts_of(util[-1])
  ```
- Why: if either boundary row lacks a parseable `ts`, the span stays 0.0 and the verdict is INSUFFICIENT-DATA reporting "need 168h (168h short)" even when months of valid rows sit between them. The failure is reported as insufficient elapsed time rather than as a malformed store.

**Defect 7 — a genuinely computed machine floor of zero is reported as insufficient data**

- Where: line 159 and line 183
  ```
  "verdict": "OK" if (floor_m and pool) else "INSUFFICIENT-DATA",
  sys.exit(0 if (floor_m and pool) else 3)
  ```
- Why: a full capacity log in which no ten-sample healthy run exists is a real measured result about this box, not missing data. It exits 3 with the INSUFFICIENT-DATA verdict, and nothing in the output distinguishes "log is thin" from "the box never held ten healthy minutes". Conversely the header says exit 0 means "a floor was computed", but a computed machine floor with a pending pool store also exits 3.

**Defect 8 — the pool floor is a single-sample spike, contradicting the stated floor definition**

- Where: lines 143–144
  ```
  if w < 100:
      per[r["acct"]] = max(per.get(r["acct"], 0), k)
  ```
- Why: line 51 states "A floor wants a run, not a spike", and the machine side enforces a run. The pool side takes the maximum `k` ever seen per account, so one sweep that caught a momentary session count publishes as the sustained pool floor. The per-account values are then summed at line 146, compounding four spikes into a fleet figure.

No other defects found. The `--help` path, argument parsing, and JSON output are consistent with the header.
