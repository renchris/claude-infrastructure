Fifteen defects, ordered roughly by impact.

---

### 1. Machine floor never slides its window, so a ramp pins the floor to its starting count

**What:** `cur_min` is the minimum over the entire healthy streak so far, not over the last `RUN` samples. A high plateau reached after a low start in the same streak is never credited.

**Where:** lines 111–112
```
        cur_min = n if cur_min is None else min(cur_min, n)
        if streak >= run_len and cur_min > floor_m:
```

**Why it is wrong:** Take a healthy streak of 10 samples at 3 sessions, then 500 samples at 40. `cur_min` locks at 3 and can only fall. The reported floor is 3, though the box sustained 40 for over eight hours with every signal green. Daily ramps from an overnight low are exactly this shape, so the reported floor sits at the low, not at the "largest session count sustained across a run" the header describes.

### 2. `best_run` is always exactly `RUN`, not the length of the run

**What:** Because `cur_min` never increases within a streak, `floor_m` can only be updated at `streak == run_len`. The reported "consecutive healthy samples" is therefore always the configured threshold (or 0).

**Where:** line 113, and the report at line 165
```
            floor_m, best_run = cur_min, streak
```
```
          f"({best_run} consecutive healthy samples; peak ever seen {peak}; "
```

**Why it is wrong:** A 500-sample healthy run is reported as "10 consecutive healthy samples", both in text and in `machine_floor_run_samples`. The field reports the configured parameter, not an observation.

### 3. "Consecutive" is judged by file adjacency with no timestamp check

**What:** The streak loop never looks at `ts`, so samples separated by hours or days count as consecutive.

**Where:** line 105 (the comment at line 52 claims "10 consecutive 60 s samples = 10 minutes green")
```
for r in cap:
```

**Why it is wrong:** Suppose the alarm daemon stops, or the box sleeps or reboots, between two healthy stretches of 5 samples each. Together they form a qualifying 10-sample run. The floor is then credited as "sustained" across a gap in which nothing was measured.

### 4. Rows that should break a streak are removed before the streak is computed

**What:** Rows whose `sessions` is not an int are filtered out before the loop. `rows()` also silently drops any malformed line anywhere in the file, not only a torn last line. Neither kind of row resets `streak`.

**Where:** line 102, and lines 87–88
```
cap = [r for r in rows(cap_log) if isinstance(r.get("sessions"), int)]
```
```
                except ValueError:
                    continue                       # a torn last line mid-append is not corruption
```

**Why it is wrong:** Suppose the alarm writes a sample with `sessions` null, or a line is corrupted mid-file. That can easily happen precisely when the box is overloaded. The row vanishes and the healthy samples on either side join into one streak, so an unhealthy moment is erased from the run.

### 5. A missing swap reading counts as "no swap"

**What:** `r.get("swap_used_mb") or 0` treats an absent or null swap field as 0, which passes the swap check.

**Where:** line 106
```
    ok = r.get("verdict") == "OK" and float(r.get("swap_used_mb") or 0) <= 0
```

**Why it is wrong:** Records written before the field existed, or with a failed swap probe (`null`), are counted healthy. The comment at lines 99–101 calls swap the check that makes this "a floor rather than an average", yet here it is silently skipped.

### 6. The swap criterion is absolute swap in use, not swap growth

**What:** The header defines healthy as "zero swap growth", but the code requires `swap_used_mb <= 0`, an absolute level.

**Where:** line 106 (same line as above)

**Why it is wrong:** Swap that was allocated during an earlier pressure event persists after the pressure is gone; macOS in particular keeps it until reboot. Once that happens, every later sample is unhealthy even with no swap growth at all. `floor_m` collapses to 0 (or to a stale pre-swap value) for the rest of the uptime.

### 7. The pool floor is a single-sample maximum, not a sustained value

**What:** The per-account figure is the `max` of individual observations, with no run requirement.

**Where:** line 144
```
            per[r["acct"]] = max(per.get(r["acct"], 0), k)
```

**Why it is wrong:** One sweep that happens to see a burst of sessions on an account becomes that account's "floor". That is the spike the file itself rejects at lines 51–52 ("one lucky sample at 46 sessions proves the box briefly held 46, not that it sustains it"). The result is a peak published under the label of a floor.

### 8. Per-account maxima from different times are summed and reported as concurrent sessions

**What:** The total adds each account's peak, however far apart in time those peaks were, and prints the sum as "concurrent sessions".

**Where:** lines 146 and 169
```
        pool = {"per_account": per, "total": sum(per.values())}
```
```
        print(f"POOL floor    : {pool['total']} concurrent sessions ({pa}), each measured while "
```

**Why it is wrong:** Say account A peaked at 20 on Monday and account B at 25 on Thursday. The script reports a pool floor of 45 concurrent sessions, a concurrency never observed. It is the most optimistic combination, not the "conservative fleet figure" the comment at line 135 claims, and it breaks the "never extrapolates" contract.

### 9. The weekly-window gate measures first-to-last span, not coverage, and counts unusable rows

**What:** The span is computed from the first and last rows that have any `acct`, including `stale` rows and rows lacking `k` or `weekly_pct`.

**Where:** lines 128 and 132
```
    t0, t1 = ts_of(util[0]), ts_of(util[-1])
```
```
if u_span_h >= need_h:
```

**Why it is wrong:** Two cases pass the gate:
- Two samples seven days apart.
- A week of rows that are mostly `stale` (which line 139 says are "not a measurement"), with real measurements covering only a day.

Either way, the pool number is published from exactly the thin data the header says must yield INSUFFICIENT-DATA.

### 10. One unparseable timestamp on the first row blocks the pool floor permanently

**What:** The span depends only on `util[0]` and `util[-1]` both parsing. If `ts_of` returns `None` for either, `u_span_h` stays 0.

**Where:** lines 128–130 (the same pattern for the machine span is at lines 120–122)
```
        u_span_h = (t1 - t0).total_seconds() / 3600.0
```

**Why it is wrong:** The first row of an append-only log never changes. If it lacks `ts`, or has a format `fromisoformat` rejects (for example epoch seconds, or non-3/6-digit fractions on Python < 3.11), `u_span_h` is 0 forever. The pool floor is never computed, while the output keeps saying it becomes computable with elapsed time.

### 11. The INSUFFICIENT-DATA message blames elapsed time when the span is already sufficient

**What:** When the span meets `need_h` but no row qualifies, `pool` is `None` and the message prints "0h short" and "computable by elapsed time".

**Where:** lines 172 and 177–178
```
        short = max(0.0, need_h - u_span_h)
```
```
        print("                live sweep at no extra cost. Nothing to run; this becomes "
              "computable by elapsed time.")
```

**Why it is wrong:** If every row is `stale`, has `weekly_pct >= 100`, or has a non-int `k`, more time will not fix anything. The script names the wrong missing thing, contrary to the header's "names exactly what is missing". The header also promises "the date it becomes computable", which is never produced.

### 12. "Computable by elapsed time" assumes the recorder is still appending

**What:** The shortfall is `need_h` minus the first-to-last span, with no check of the last sample's age against now.

**Where:** lines 172 and 177–178 (as above)

**Why it is wrong:** Suppose live sweeps stop, for example because nobody runs `claude-accounts` live or the recorder breaks. The span freezes, "Nh short" never shrinks, and the script keeps telling the operator there is "Nothing to run".

### 13. An unreadable or missing utilization log is reported as an empty store

**What:** Only `CAP_LOG` is checked for readability. `rows()` swallows `OSError` on `UTIL_LOG`, so it returns nothing.

**Where:** line 67, lines 89–90, and line 180
```
[ -r "$CAP_LOG" ] || { echo "pool-floor: cannot read $CAP_LOG" >&2; exit 1; }
```
```
    except OSError:
        return
```
```
            print("                Store is EMPTY — no live sweep has happened since the "
```

**Why it is wrong:** A permissions error, a wrong `CC_UTIL_LOG`, or a recorder that never created the file all produce the same result: exit 3 plus a flat assertion that "no live sweep has happened since the recorder landed". The header's exit 1 is reserved for unreadable stores, and here the script states a premise it never checked. The same applies if `CAP_LOG` is a directory: `-r` passes, `open` fails, and you get floor 0 and exit 3 instead of exit 1.

### 14. The verdict and exit code are inconsistent with what was computed

**What:** Verdict `OK` and exit 0 require both floors, and the checks use truthiness.

**Where:** lines 159 and 183 (the text output is at line 164)
```
    "verdict": "OK" if (floor_m and pool) else "INSUFFICIENT-DATA",
```
```
sys.exit(0 if (floor_m and pool) else 3)
```

**Why it is wrong:** Three cases misreport:
- **Machine floor computed, pool not yet:** exits 3 although the header defines 0 as "a floor was computed" and calls the machine floor computable today.
- **`floor_m == 0`:** the text still prints "MACHINE floor : 0 concurrent sessions sustained" as a measurement, while the verdict calls it INSUFFICIENT-DATA with no explanation.
- **Every account's max `k` is 0:** `pool` is a non-empty dict and therefore truthy, so a pool floor of 0 yields verdict `OK`.

### 15. Any Python exception exits 1, the code reserved for "stores could not be read"

**What:** Parsing errors are uncaught, and Python exits 1 with a traceback.

**Where:** line 106 (`float(...)`), lines 122/130 (the subtraction), and line 102 (`r.get`)

**Why it is wrong:** Several ordinary inputs crash the script:
- `swap_used_mb` holding a non-numeric string raises `ValueError`.
- One timestamp with an offset and one without raises `TypeError` on subtraction.
- A valid-JSON line that is not an object (`null`, `3`) raises `AttributeError`.
- A non-integer `CC_POOL_FLOOR_RUN` fails at startup.

Each of these is reported to callers as "the stores could not be read at all", when they were read and one value was malformed.

### 16. `--help` prints script code along with the header

**What:** `sed -n '2,50p'` runs past the header comment, which ends at line 46.

**Where:** line 63
```
    -h|--help) sed -n '2,50p' "$0"; exit 0 ;;
```

**Why it is wrong:** The help output includes `set -uo pipefail`, a blank line, and the `CAP_LOG=`/`UTIL_LOG=` assignments after the usage text.
