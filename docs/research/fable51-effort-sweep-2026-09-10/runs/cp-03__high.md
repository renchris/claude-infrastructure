Reviewing `scripts/pool-floor.sh` from the brief text only. Findings below.

**1. The machine floor takes the minimum over the whole healthy streak, not over a window of `RUN` samples, so a ramp-up is undercounted.**

Lines 111–113:
```
        cur_min = n if cur_min is None else min(cur_min, n)
        if streak >= run_len and cur_min > floor_m:
            floor_m, best_run = cur_min, streak
```
Why: `cur_min` only resets on an unhealthy sample. A streak of 10 healthy samples at 5 sessions followed by 100 healthy samples at 40 sessions has a 10-sample window sustaining 40, but `cur_min` stays 5 for the whole streak and the floor is reported as 5. The header defines the floor as the largest count sustained across `RUN` consecutive samples, which this does not compute.

**2. "Consecutive" is file adjacency, not time adjacency, so a run can straddle an unobserved gap.**

Lines 105–109:
```
for r in cap:
    ok = r.get("verdict") == "OK" and float(r.get("swap_used_mb") or 0) <= 0
    if ok:
        healthy_total += 1
        streak += 1
```
Why: the comment on line 52 says ten consecutive samples mean ten minutes green, but no timestamp is consulted. If the alarm daemon was down for hours between two adjacent lines, the box may have swapped and recovered unobserved, and those lines still join one streak. A floor gets published from a run that was never actually watched.

**3. A sample missing the swap field is treated as swap-free and counted healthy.**

Line 106:
```
    ok = r.get("verdict") == "OK" and float(r.get("swap_used_mb") or 0) <= 0
```
Why: the code requires both verdict OK and zero swap, but a record with no `swap_used_mb` key, or with it set to null, evaluates to 0 and passes. Older-schema or partially written samples satisfy a guard they never provided evidence for. A non-numeric string in that field also raises an uncaught ValueError and aborts the script.

**4. The weekly-span gate is fleet-wide and first-to-last only, so a per-account floor can be published from far less than a week of that account's data.**

Lines 128–130 and 132:
```
    t0, t1 = ts_of(util[0]), ts_of(util[-1])
    if t0 and t1:
        u_span_h = (t1 - t0).total_seconds() / 3600.0
...
if u_span_h >= need_h:
```
Why: the span is taken from the first and last rows of the file regardless of account or of the `stale` flag. An account added yesterday contributes its max `k` to the summed total the moment any other account's rows span 168 hours. Two rows a week apart, or a week of stale rows, also satisfy the gate. The header says a floor from four days of data must not be published, and this gate does not enforce that per account.

**5. The pool floor is a single-sample peak, not a sustained run.**

Lines 143–144:
```
        if w < 100:
            per[r["acct"]] = max(per.get(r["acct"], 0), k)
```
Why: one sweep that saw `k` sessions while weekly was under 100% sets that account's floor to `k`. The script's own rationale on lines 51–52 says a single lucky sample proves a spike, not a floor. The header on lines 13–14 also states that weekly quota does not gate session creation, so the `w < 100` condition is not a health signal for concurrency. The published pool figure is therefore an observed maximum, not the lower bound the header promises.

**6. A computed machine floor is reported as INSUFFICIENT-DATA and exit 3.**

Lines 159 and 183:
```
    "verdict": "OK" if (floor_m and pool) else "INSUFFICIENT-DATA",
...
sys.exit(0 if (floor_m and pool) else 3)
```
Why: the header says exit 0 means a floor was computed and that the machine floor is computable today and is the binding constraint. Until the pool series spans a week, the script always exits 3 and the JSON verdict says INSUFFICIENT-DATA, even when `machine_floor_sessions` holds a valid measured number. A caller keying on the verdict discards a real result.

**7. When the span is sufficient but no sample qualifies, the output blames elapsed time.**

Lines 171–178:
```
    else:
        short = max(0.0, need_h - u_span_h)
        print(f"POOL floor    : INSUFFICIENT-DATA — {len(util)} samples spanning {u_span_h:.0f}h, "
              f"need {need_h:.0f}h ({short:.0f}h short).")
...
        print("                live sweep at no extra cost. Nothing to run; this becomes "
              "computable by elapsed time.")
```
Why: `pool` is None both when the span is short and when `per` is empty on line 145. If every row is stale, has a non-integer `k`, or has weekly at or above 100, the message reports "0h short" and says waiting will fix it. Waiting will not. The actual cause, unusable samples, is never surfaced.

**8. An unreadable utilization log is reported as an empty store.**

Lines 89–90 and 179–181:
```
    except OSError:
        return
...
        if not util:
            print("                Store is EMPTY — no live sweep has happened since the "
                  "recorder landed.")
```
Why: only the capacity log is checked on line 67. If the utilization log exists but cannot be opened, for example a permissions error, `rows` swallows the OSError and yields nothing. The script then claims no sweep has run and exits 3, instead of the exit 1 the header reserves for stores that could not be read.
