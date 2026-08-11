# Review — `scripts/pool-floor.sh`

Seven defects, plus one minor. Line numbers count from `#!/bin/bash` as line 1.

---

## 1. The machine floor is the minimum over the *whole* healthy streak, not over a window of `run_len` samples

**What** — `cur_min` is reset only when health breaks, so the reported floor is the smallest session count anywhere in the longest green stretch, not the largest count sustained across some run of `run_len` consecutive healthy samples.

**Where** — lines 111–113, 115:
```python
        cur_min = n if cur_min is None else min(cur_min, n)
        if streak >= run_len and cur_min > floor_m:
            floor_m, best_run = cur_min, streak
```
```python
        streak, cur_min = 0, None
```

**Why it is wrong** — `cur_min` is monotonically non-increasing for the life of a streak, and `floor_m` is only ever raised. Take one unbroken healthy streak: 500 samples at `sessions=2` (idle overnight) followed by 500 samples at `sessions=46`. At sample 10, `cur_min=2` and `floor_m` becomes 2; every later sample can only lower or hold `cur_min`, so the run of 500 consecutive healthy samples at 46 is never seen. The script prints `MACHINE floor : 2 concurrent sessions sustained` for a box that demonstrably held 46 green for eight hours. The healthier the box, the longer the streak, the lower the reported floor — a machine that never leaves `verdict=OK` reports its quietest minute as its capacity, which is precisely the number a scheduler must not use.

## 2. `machine_floor_run_samples` is a constant, printed as a measurement

**What** — `best_run` can only ever hold `0` or exactly `run_len`, but it is published as the observed length of the sustaining run.

**Where** — lines 112–113, and the report at 150 / 165:
```python
        if streak >= run_len and cur_min > floor_m:
            floor_m, best_run = cur_min, streak
```
```python
          f"({best_run} consecutive healthy samples; peak ever seen {peak}; "
```

**Why it is wrong** — the update fires only when `cur_min > floor_m`. Within a streak `cur_min` never increases and `floor_m` never decreases, so if the test fails at `streak == run_len` it fails for the entire rest of that streak; if it succeeds, it succeeds at `streak == run_len` and never again. `best_run` is therefore always `run_len` (10) or 0, for any input whatsoever. The output line "`10 consecutive healthy samples`" and the JSON field `machine_floor_run_samples` look like evidence of how long the floor was held; they carry no information at all, and they understate a genuinely multi-day run as ten minutes.

## 3. A missing `swap_used_mb` field counts as proven-zero swap

**What** — the swap term of the health gate defaults an absent or null field to `0`, so records that never measured swap are admitted as swap-free.

**Where** — line 106:
```python
    ok = r.get("verdict") == "OK" and float(r.get("swap_used_mb") or 0) <= 0
```

**Why it is wrong** — `r.get("swap_used_mb")` returns `None` when the key is absent or JSON-null; `None or 0` is `0`; `0 <= 0` is true. Any capacity-alarm record written before the field existed, or by a code path that omits it, silently passes the very check the comment at lines 99–101 calls the second of "both terms," and the floor degrades to verdict-only for those samples — an unmeasured premise asserted as a green health signal, in a script whose header (line 3) claims it never asserts what the data does not show. Two related consequences on the same expression: the header at line 27 specifies "zero swap **growth**" while the code tests absolute swap in use, so on a box that has ever swapped, every subsequent sample is disqualified forever and the machine floor silently freezes; and a non-numeric value (e.g. `"1.5G"`) raises an uncaught `ValueError`, terminating with status 1, which line 44 reserves for "the stores could not be read at all."

## 4. An unreadable or unrecognised utilization store is reported as "no live sweep has happened"

**What** — the script prints an affirmative claim about the world — that the recorder has never run — whenever `util` is empty, including when the file exists and is full of samples.

**Where** — lines 125, 179–181, and the guard at 67:
```python
util = [r for r in rows(util_log) if r.get("acct")]
```
```python
        if not util:
            print("                Store is EMPTY — no live sweep has happened since the "
                  "recorder landed.")
```
```bash
[ -r "$CAP_LOG" ] || { echo "pool-floor: cannot read $CAP_LOG" >&2; exit 1; }
```

**Why it is wrong** — `rows()` swallows `OSError` and yields nothing (lines 89–90), and there is no readability check for `UTIL_LOG` to match the one for `CAP_LOG`, so a permission-denied file, a wrong `CC_UTIL_LOG` path, or a path that is a directory all produce an empty `util` and the sentence "no live sweep has happened since the recorder landed." The same message appears if the recorder writes the account under any key other than `acct`, since line 125 filters on that key alone — the store can hold months of samples and still be declared empty. The documented exit 1 for an unreadable store can never fire for the pool store.

## 5. When `pool` is `None` for any reason other than span, the INSUFFICIENT-DATA message misdiagnoses the cause

**What** — the shortfall message is printed unconditionally in the `else` branch, so it reports "0h short" and tells the user to wait, in cases where the span requirement has already been met and waiting will never help.

**Where** — lines 145, 172–178:
```python
    if per:
```
```python
        short = max(0.0, need_h - u_span_h)
        print(f"POOL floor    : INSUFFICIENT-DATA — {len(util)} samples spanning {u_span_h:.0f}h, "
              f"need {need_h:.0f}h ({short:.0f}h short).")
```
```python
        print("                live sweep at no extra cost. Nothing to run; this becomes "
              "computable by elapsed time.")
```

**Why it is wrong** — `pool` stays `None` whenever `per` ends up empty despite `u_span_h >= need_h`: every record marked `stale`, every account at `weekly_pct >= 100`, or `k` recorded as a JSON float rather than an int (line 141 accepts `int` only, so `3.0` is skipped on every row). With a year of data the script then prints "`8760 samples spanning 8760h, need 168h (0h short)`" followed by "this becomes computable by elapsed time" — self-contradictory, and it directs the operator to wait for a condition that is already satisfied while the real blocker goes unnamed. The same message also fires when the recorder has stopped: `u_span_h` is measured between the first and last *record*, not against wall clock, so a series that ended a month ago reports a fixed "68h short" forever and claims elapsed time will close it.

## 6. The weekly-span gate is fleet-wide and endpoint-only, but the number it licenses is per-account

**What** — a single span check over the first and last record of the whole file is used to certify per-account floors, so an account with hours of history is published as though it had a full weekly window behind it.

**Where** — lines 128–132, 144:
```python
    t0, t1 = ts_of(util[0]), ts_of(util[-1])
```
```python
if u_span_h >= need_h:
```
```python
            per[r["acct"]] = max(per.get(r["acct"], 0), k)
```

**Why it is wrong** — `u_span_h` is the difference between two timestamps and says nothing about density or per-account coverage. Two records a week apart pass the gate. A fourth account added yesterday, into a store that has been filling for a month, passes the gate and contributes its one-day maximum to the published total — exactly the "floor published from four days of data" that lines 39–41 exist to prevent, and it is published with no caveat at all. Conversely, if the first or last record has a missing or unparseable `ts`, `u_span_h` stays `0.0` (lines 129–130) and a store spanning a year is refused with "168h short."

## 7. The pool total sums per-account maxima taken at different times and calls the sum "concurrent sessions"

**What** — each account contributes its historical peak, whenever that occurred, and the sum of those unrelated peaks is printed as a measured concurrency figure.

**Where** — lines 144, 146, 169:
```python
            per[r["acct"]] = max(per.get(r["acct"], 0), k)
```
```python
        pool = {"per_account": per, "total": sum(per.values())}
```
```python
        print(f"POOL floor    : {pool['total']} concurrent sessions ({pa}), each measured while "
```

**Why it is wrong** — if account A peaked at 12 on Monday while B, C and D were idle, and B peaked at 9 on Friday, `total` is 21+ and the script states that 21 concurrent sessions were held — a state no sample ever recorded. That is a synthesised number, in a file whose second line promises "Never estimates, never extrapolates." Two further consequences of using `max`: a per-account figure rests on a *single* sample, the exact spike-versus-run distinction the script insists on for the machine floor at lines 51–52 ("one lucky sample at 46 sessions proves the box briefly held 46, not that it sustains it"); and because `max` over the full history only ever rises, no later observation can lower it, contradicting line 19's "it is falsifiable — one counter-example sample lowers it." An account that has since been downgraded or removed keeps its historical peak in the published total permanently.

## 8. A measured floor of zero is indistinguishable from no floor at all

**What** — `floor_m` uses `0` both as the initial "nothing found" sentinel and as a legitimate result, and the verdict/exit test keys on its truthiness.

**Where** — lines 103, 112, 159, 183, 164:
```python
floor_m, best_run, streak, cur_min = 0, 0, 0, None
```
```python
    "verdict": "OK" if (floor_m and pool) else "INSUFFICIENT-DATA",
```
```python
sys.exit(0 if (floor_m and pool) else 3)
```

**Why it is wrong** — an idle box producing ten consecutive healthy samples at `sessions=0` yields `cur_min=0`, and `0 > 0` is false, so the qualifying run is never recorded; the data conclusively supports a floor of 0 and the script reports it as INSUFFICIENT-DATA. In the other direction, when the capacity log is empty or contains no healthy run at all, line 164 still prints "`MACHINE floor : 0 concurrent sessions sustained`" as a positive statement of measurement rather than as an absence. Related contract conflict on the same expressions: line 43 documents exit 0 as "a floor was computed," yet a fully computed machine floor — which line 28 calls today's binding constraint — always exits 3, so any caller keying on exit status discards a real published number.

---

### Minor

**What** — `--help` dumps three lines of executable code along with the header.

**Where** — line 63:
```bash
    -h|--help) sed -n '2,50p' "$0"; exit 0 ;;
```

**Why it is wrong** — the header comment block ends at line 46 (`# Usage: ...`); the range `2,50` also emits line 47 `set -uo pipefail` and the `CAP_LOG`/`UTIL_LOG` assignments at 49–50, so help output ends mid-source with no usage summary of the two environment variables it happens to reveal.