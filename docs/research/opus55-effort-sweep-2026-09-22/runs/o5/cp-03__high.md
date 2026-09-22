## Review — `scripts/pool-floor.sh`

Eleven defects. The first five change the number the script publishes or the status it reports.

---

### 1. The machine floor takes the minimum over the *entire* healthy streak, not over any run of `RUN` samples, so it reports a number far below the floor it defines

**Where** — lines 111–113:
```python
        cur_min = n if cur_min is None else min(cur_min, n)
        if streak >= run_len and cur_min > floor_m:
            floor_m, best_run = cur_min, streak
```

**Why it is wrong** — `cur_min` is monotonically non-increasing for as long as the streak lives, and it is only reset when a sample is unhealthy (line 115). Take a healthy run of 1,000 samples where the first ten are at 5 sessions and the remaining 990 are at 46. The header defines the machine floor as "the largest session count sustained across a run of consecutive samples with verdict=OK" — 990 consecutive samples at 46 is exactly such a run — but `cur_min` is pinned at 5 for the whole streak, so `floor_m` is 5. On a box that is healthy for days at a time (60 s cadence, "tens of thousands of samples"), a single quiet minute near the start of a long green stretch permanently caps the published floor for that stretch. The stated computation requires a max-over-windows of the within-window minimum; the code computes the min over an unbounded prefix.

---

### 2. The pool total sums per-account maxima observed at *different times* and prints the sum as a concurrency that was measured

**Where** — lines 144, 146 and 169:
```python
            per[r["acct"]] = max(per.get(r["acct"], 0), k)
```
```python
        pool = {"per_account": per, "total": sum(per.values())}
```
```python
        print(f"POOL floor    : {pool['total']} concurrent sessions ({pa}), each measured while "
```

**Why it is wrong** — `per[acct]` is each account's maximum over the whole series independently; nothing ties the four maxima to a common timestamp. If account A peaked at 12 on Monday while B, C and D sat at 2, and B peaked at 12 on Thursday while the others sat at 2, the script prints "POOL floor : 48 concurrent sessions", a figure never observed and never sustained. That is an extrapolation from four non-simultaneous observations, in a file whose opening line promises "Never estimates, never extrapolates", and it is an *upper*-leaning number published under a header that says "only lower bounds publish". The comment on line 135 calls the sum "the conservative fleet figure"; summing per-account maxima is the anti-conservative direction.

---

### 3. The pool floor is computed from single spikes; the run requirement the script insists on is applied only to the machine side

**Where** — line 144:
```python
            per[r["acct"]] = max(per.get(r["acct"], 0), k)
```

**Why it is wrong** — `run_len` is read on line 75 and used only at line 112. Lines 51–52 state the governing rule: "A floor wants a run, not a spike: one lucky sample at 46 sessions proves the box briefly held 46, not that it sustains it." One sweep that happens to catch an account at 12 live sessions — a momentary burst that collapsed a minute later — sets that account's contribution to 12 forever. The pool number is therefore a peak, while the output line (169) and the header (lines 17–18, "We have sustained N concurrently") assert it is a sustained floor.

---

### 4. The pool health guard checks only the weekly window, so samples taken while an account was throttled on its 5-hour or Fable window count toward the floor

**Where** — lines 140–143:
```python
        w, k = r.get("weekly_pct"), r.get("k")
        if not isinstance(k, int) or not isinstance(w, (int, float)):
            continue
        if w < 100:
```

**Why it is wrong** — line 31 states each sweep records "per-account 5h%, weekly%, Fable% and live session count", and lines 17–18 define a floor as sessions held "with every health signal green". A sample recorded while the account's 5-hour window was at 100% (requests being refused) passes this filter as long as `weekly_pct` is 99, and its session count is admitted into `per`. The guard covers one of the three measured signals while the surrounding text claims it covers the health of the account. A number produced under 5h exhaustion is not evidence the pool carries that concurrency.

---

### 5. A successfully computed floor is reported as INSUFFICIENT-DATA and exits 3

**Where** — lines 159 and 183:
```python
    "verdict": "OK" if (floor_m and pool) else "INSUFFICIENT-DATA",
```
```python
sys.exit(0 if (floor_m and pool) else 3)
```

**Why it is wrong** — lines 43–44 document `0 = a floor was computed` and `3 = INSUFFICIENT-DATA`. The header also states the machine floor is "computable today" and "the BINDING constraint", while the pool floor needs 168 h of a store that has just started filling. In that expected state — machine floor computed and printed on line 164, pool store four days old — the conjunction is false, so the script prints a real measured floor and simultaneously exits 3 with verdict INSUFFICIENT-DATA. A caller that gates on the exit status discards the one floor that was obtainable. The symmetric case fails too: a valid pool floor with `floor_m == 0` also yields 3.

---

### 6. A missing `swap_used_mb` field silently satisfies the swap half of the health test

**Where** — line 106:
```python
    ok = r.get("verdict") == "OK" and float(r.get("swap_used_mb") or 0) <= 0
```

**Why it is wrong** — if the capacity-alarm record omits `swap_used_mb` (older schema version, a partial record, a rung that does not sample swap), `r.get(...)` is `None`, `None or 0` is `0`, and `0 <= 0` is true. The sample is then judged healthy on `verdict` alone. Lines 99–101 justify the conjunction precisely on the grounds that "a box can read OK while swapping at the margin"; for any record lacking the field the second term is not merely absent but resolves in the permissive direction, and the floor is computed from samples that may have been swapping. The same expression treats `swap_used_mb: 0` and "not measured" as the same fact.

---

### 7. The swap term tests absolute swap in use, while the specification is zero swap *growth*

**Where** — line 27 versus line 106:
```
#   samples with verdict=OK and zero swap growth. This is a real lower bound on what the hardware
```
```python
    ok = r.get("verdict") == "OK" and float(r.get("swap_used_mb") or 0) <= 0
```

**Why it is wrong** — these select different sample classes. On a box that touched swap once days ago and never released it (the normal steady state on Darwin, where `swap_used_mb` stays at a few hundred MB indefinitely), swap growth is zero on every sample but `swap_used_mb` is never `<= 0`. Every sample is then classified unhealthy, `streak` never reaches `run_len`, and the script prints `MACHINE floor : 0 concurrent sessions sustained (0 consecutive healthy samples ... 0/34000 samples healthy)` and exits 3 — reporting the box as having demonstrated nothing, from a store that in fact documents months of green operation.

---

### 8. An unreadable pool store is reported as proof that no sweep has run

**Where** — lines 89–90 and 179–181:
```python
    except OSError:
        return
```
```python
        if not util:
            print("                Store is EMPTY — no live sweep has happened since the "
                  "recorder landed.")
```

**Why it is wrong** — `rows()` swallows every `OSError`. If `~/.claude/logs/account-utilization.jsonl` exists but is unreadable (permissions, a broken symlink, a directory in its place), `util` is `[]` and the script asserts as fact "Store is EMPTY — no live sweep has happened since the recorder landed" and tells the operator "Nothing to run; this becomes computable by elapsed time" (line 177). The premise is unproven: the file was never opened. Elapsed time will never fix a permission bit, so the diagnosis sends the operator away from the actual fault. Lines 43–44 reserve exit 1 for "the stores could not be read at all", but only `CAP_LOG` is checked for readability (line 67); an unreadable `UTIL_LOG` exits 3.

---

### 9. The 168-hour gate is decided by two rows, so a two-sample store can unlock the pool floor

**Where** — lines 128–132:
```python
    t0, t1 = ts_of(util[0]), ts_of(util[-1])
```
```python
if u_span_h >= need_h:
```

**Why it is wrong** — the gate measures the distance between the first and last line in the file, not coverage. A store containing one sweep from 8 days ago and one from today has `u_span_h == 192`, passes `>= 168`, and publishes a pool floor derived from two samples — the exact outcome lines 39–41 exist to prevent ("A floor published from four days of data would be quoted for months"). Nothing consults `len(util)`, which is reported in the JSON (line 156) but never tested. The same two-row basis fails in the other direction: rows excluded as `stale` on line 138 still count toward the span, so a week of inherited numbers plus one real sweep also opens the gate; and one unparseable or missing `ts` on the first or last line makes `ts_of` return `None`, leaving `u_span_h` at `0.0` so a store with a year of data reports "spanning 0h, need 168h (168h short)".

---

### 10. Mixed naive/aware timestamps crash the script, and the crash surfaces as the documented "cannot read the stores" exit

**Where** — lines 122 and 130:
```python
        span_h = (t1 - t0).total_seconds() / 3600.0
```
```python
        u_span_h = (t1 - t0).total_seconds() / 3600.0
```

**Why it is wrong** — `ts_of` returns an aware datetime for `...Z` or `...+00:00` values and a naive one for `2026-09-22T10:00:00`. If a store's first and last records disagree — a recorder whose timestamp format changed across the sibling change described on lines 35–36 is the obvious case — the subtraction raises `TypeError: can't subtract offset-naive and offset-aware datetimes`. `ts_of` catches only `ValueError` (line 95), so the traceback propagates and python exits 1, which per line 44 means "the stores could not be read at all" — a parse-format fault reported as an I/O fault.

---

### 11. Unrecognised arguments are accepted silently

**Where** — lines 60–64:
```bash
  case "$a" in
```

**Why it is wrong** — there is no `*)` arm. `pool-floor.sh --quite` or `pool-floor.sh --jsonl` sets neither flag, so the script emits full human-readable output and exits with a status the caller reads as a successful run of the mode it asked for. A wrapper that pipes the output to `jq` on the assumption `--json` was honoured gets prose.

---

### Minor, same class

**`--help` prints four lines of code.** Line 63: `-h|--help) sed -n '2,50p' "$0"; exit 0 ;;`. The usage line is line 46; lines 47–50 are `set -uo pipefail`, a blank line, and the two `*_LOG` assignments, which are printed to the user as part of the help text.
