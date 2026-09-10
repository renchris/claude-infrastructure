I'm reviewing `scripts/pool-floor.sh` from the brief text alone. I found nine defects, listed from most to least serious.

**1. The machine floor only ever looks at the first `RUN` samples of each healthy streak.**

**What:** Session counts sustained later in a healthy streak can never raise the floor, so the headline number is wrong and can be zero on a fully healthy log.

**Where:** lines 111–113

```python
        cur_min = n if cur_min is None else min(cur_min, n)
        if streak >= run_len and cur_min > floor_m:
            floor_m, best_run = cur_min, streak
```

**Why:** `cur_min` is the minimum since the streak began, not over a window of `run_len` rows, and it can only fall. The only step at which a streak can update `floor_m` is when `streak` first equals `run_len`. After that `cur_min` is never above `floor_m`. Take an all-healthy log with sessions at 0 for its first ten rows and 30 for the next 600 rows. The result is a floor of 0, verdict INSUFFICIENT-DATA and exit 3, although the box held 30 sessions green for ten hours. Lines 26–27 define the floor as the largest count sustained across a run of healthy samples. With a 60 s cadence and hours-long healthy stretches, the published floor is whatever ran in the ten minutes after the last unhealthy sample, or at the top of the file. A side effect is that `best_run` is always exactly `run_len` when set, so `machine_floor_run_samples` and the "consecutive healthy samples" figure in the text are constants, not measurements.

**2. One verdict and one exit code are a conjunction over two independent floors.**

**What:** A computed machine floor is reported as INSUFFICIENT-DATA with exit 3, and a zero machine floor beside a computed pool floor exits 3 while the text output shows both as measured with no insufficiency notice.

**Where:** line 159 and line 183

```python
    "verdict": "OK" if (floor_m and pool) else "INSUFFICIENT-DATA",
```

```python
sys.exit(0 if (floor_m and pool) else 3)
```

**Why:** Line 43 says exit 0 means a floor was computed, and lines 25–28 say the machine floor is computable today and is the binding constraint. Until the utilization series spans 168 h, `pool` is None, so every run exits 3 and the JSON carries a non-zero `machine_floor_sessions` next to an INSUFFICIENT-DATA verdict. A caller keyed on exit 0 never receives the machine floor. Line 39 could be read as intending that, but it still contradicts line 43 and does not cover the reverse case. When `floor_m` is 0 and `pool` is computed, text mode prints "MACHINE floor : 0 concurrent sessions sustained" plus a POOL floor line, nothing says INSUFFICIENT-DATA, and the process exits 3. Only the pool branch at lines 171–181 has an insufficiency message. The machine side never says what is missing, which lines 3–4 promise.

**3. The INSUFFICIENT-DATA branch names the wrong cause once the span is sufficient.**

**What:** With the span already at or above `need_h` but no qualifying row, the message reports "0h short" and asserts the floor becomes computable by elapsed time.

**Where:** line 172 and lines 177–178

```python
        short = max(0.0, need_h - u_span_h)
```

```python
        print("                live sweep at no extra cost. Nothing to run; this becomes "
              "computable by elapsed time.")
```

**Why:** `pool` stays None when `per` is empty at line 145. That happens when every row is stale, every row has `weekly_pct` at or above 100, or rows lack an integer `k` or numeric `weekly_pct`, for instance after the recorder starts writing `k` as a string. The else branch then prints a line like "42 samples spanning 300h, need 168h (0h short)" followed by "Nothing to run; this becomes computable by elapsed time." Elapsed time cannot fix a type mismatch or an account pinned at 100%. The diagnosis is false, against the stated purpose of naming exactly what is missing.

**4. An unreadable utilization store is reported as proof that no sweep has happened.**

**What:** Any OSError on the utilization store, and any misconfigured path, yields the same output as an empty store, with exit 3 rather than the documented exit 1.

**Where:** lines 89–90 and lines 180–181

```python
    except OSError:
        return
```

```python
            print("                Store is EMPTY — no live sweep has happened since the "
                  "recorder landed.")
```

**Why:** `rows()` swallows every OSError, and unlike `CAP_LOG` at line 67 the util path is never checked. A permission error, a directory at the path, or a mistyped `CC_UTIL_LOG` gives an empty `util` list, and the script asserts as fact that no live sweep has happened since the recorder landed. Rows that merely lack an `acct` field produce the same message because line 125 filters on it. Line 44 reserves exit 1 for stores that could not be read. This path exits 3.

**5. Each store's span depends on exactly two rows, the first and the last.**

**What:** One row with a missing or unparseable `ts` at either end pins the span to 0 h for the life of the file, which blocks the pool floor permanently and misreports the data as spanning 0h.

**Where:** lines 128–130, with the same pattern for the machine log at lines 120–122

```python
    t0, t1 = ts_of(util[0]), ts_of(util[-1])
    if t0 and t1:
        u_span_h = (t1 - t0).total_seconds() / 3600.0
```

**Why:** `util` is filtered on `acct` only, so a first row without `ts`, or carrying an epoch number, or in a format `fromisoformat` rejects, is kept. `ts_of` returns None for it and `u_span_h` stays 0.0 no matter how many weeks of good rows follow. The gate at line 132 never opens and the output says "spanning 0h, need 168h (168h short)" indefinitely. If rows are ever out of order the difference goes negative and the reported shortfall exceeds `need_h`. For the machine log the same failure reports the healthy span as 0h.

**6. The pool floor is a single-sample spike, and the `CC_POOL_FLOOR_RUN` knob never touches it.**

**What:** The per-account floor is the maximum `k` seen in any one sweep, which is the spike lines 51–52 say a floor must not be, and the run-length setting named for the pool floor is applied only to the machine floor.

**Where:** line 144 and line 53

```python
            per[r["acct"]] = max(per.get(r["acct"], 0), k)
```

```bash
RUN="${CC_POOL_FLOOR_RUN:-10}"
```

**Why:** One sweep that catches an account at `k` 12 with `weekly_pct` 99 fixes that account's floor at 12 for the life of the store, even if every other sweep saw 2. These one-off maxima from different moments are summed and printed as "POOL floor : N concurrent sessions". `run_len` is referenced only at line 112, so an operator raising `CC_POOL_FLOOR_RUN` to make the pool figure stricter changes the machine floor and leaves the pool figure untouched. The comment at lines 133–135 describes the single-sample maximum, so the conflict is with the script's stated contract rather than with that comment.

**7. Streak continuity is by row adjacency, after rows without an integer session count are discarded.**

**What:** An unhealthy sample that lacks a session count, or a gap in the alarm's recording, does not reset the streak.

**Where:** line 102 and line 115

```python
cap = [r for r in rows(cap_log) if isinstance(r.get("sessions"), int)]
```

```python
        streak, cur_min = 0, None
```

**Why:** If the alarm writes a row with a non-OK verdict and `sessions` null or absent, for instance when the count could not be taken under load, line 102 removes it before it can reach the reset at line 115. The healthy rows on either side then count as one unbroken run. Two healthy rows separated by an hour of missing samples are likewise adjacent, although line 52 equates ten rows with ten minutes green. Both let the floor be certified by rows that do not prove sustained health.

**8. The health guard checks swap in use, while the header defines healthy as zero swap growth, and a missing swap field passes.**

**What:** The guard covers a narrower class than the header claims, and it treats an absent measurement as a zero measurement.

**Where:** line 106, against line 27

```python
    ok = r.get("verdict") == "OK" and float(r.get("swap_used_mb") or 0) <= 0
```

```bash
#   samples with verdict=OK and zero swap growth. This is a real lower bound on what the hardware
```

**Why:** On a box whose swap footprint is non-zero but stable, which is routine on macOS, every sample fails the guard. `healthy_total` is 0, `floor_m` is 0, and the script reports INSUFFICIENT-DATA with exit 3 for a box that is green under the header's definition. The comment at line 99 agrees with the code, so the header may be the wrong side, but the two contracts disagree and `--help` prints the header. Separately, `or 0` turns a missing `swap_used_mb` into zero swap, so a sample with no swap reading passes a guard whose stated point is to require that reading.

**9. `--help` prints a stale hard-coded line range.**

**What:** Help output ends with four lines of code and omits the documentation for both tuning knobs.

**Where:** line 63

```bash
    -h|--help) sed -n '2,50p' "$0"; exit 0 ;;
```

**Why:** Lines 47–50 are `set -uo pipefail`, a blank line, and the `CAP_LOG` and `UTIL_LOG` assignments, and all four are printed. Lines 51–56, which describe `CC_POOL_FLOOR_RUN` and `CC_POOL_FLOOR_SPAN_H`, are not. This one is minor.

**Recap.** The most consequential problem is the machine-floor loop, which never credits session counts past the first ten rows of a healthy streak and can report a zero floor on a healthy log. The verdict and exit code then fold that zero, or the expected week-long absence of a pool floor, into a single INSUFFICIENT-DATA that does not match the printed output or the documented exit contract. The remaining items are misdiagnosed causes in the insufficiency messages, a two-row span calculation that one bad timestamp pins at zero, a pool floor built from single-sample spikes, a streak check that skips dropped rows and time gaps, a swap guard that disagrees with the header, and a stale help range.
