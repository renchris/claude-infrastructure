8 defects, ordered by impact. This is from the text of the brief only; nothing was run.

## 1. Machine floor only scores the first `RUN` samples of each healthy streak
- **What** — `cur_min` is the minimum since the streak began, not over the latest `run_len` samples, so a healthy streak can only ever contribute the minimum of its first `run_len` rows.
- **Where** — lines 111–113:
  ```
          cur_min = n if cur_min is None else min(cur_min, n)
          if streak >= run_len and cur_min > floor_m:
              floor_m, best_run = cur_min, streak
  ```
- **Why it is wrong** — `cur_min` never rises within a streak, so the only update that can fire is at `streak == run_len`.
  - Input: `RUN=10`, every row `verdict=OK` with no swap, `sessions` = 2 followed by thirty rows of 40.
  - At the 10th row `cur_min` is 2, so `floor_m` becomes 2 and stays 2. Rows 2–31 are 30 consecutive healthy samples at 40, and any 10-row window among them meets lines 51–52, yet they are never evaluated.
  - The floor is understated. `best_run` is also always exactly `run_len` whenever `floor_m > 0`, so the printed "N consecutive healthy samples" says nothing about how long the floor was held.

## 2. A missing swap reading counts as zero swap
- **What** — the swap half of the health test turns an absent or null `swap_used_mb` into 0, which passes.
- **Where** — line 106: `    ok = r.get("verdict") == "OK" and float(r.get("swap_used_mb") or 0) <= 0`
- **Why it is wrong** — a row with `swap_used_mb` absent, null or empty evaluates `float(0) <= 0`, which is True.
  - Lines 99–101 say both terms are required, but for such a row only the verdict term is applied.
  - The row is counted in `healthy_total` and extends runs.
  - A non-numeric value such as `"n/a"` raises `ValueError` here, which nothing catches, so the script dies with a traceback.

## 3. "Consecutive" is positional in the filtered list; dropped rows and time gaps do not break a run
- **What** — rows removed before the streak loop (unparseable lines, rows without an int `sessions`) and any time gap between rows leave the neighbouring OK rows counted as consecutive.
- **Where** — lines 88, 102, 115:
  - `                    continue                       # a torn last line mid-append is not corruption`
  - `cap = [r for r in rows(cap_log) if isinstance(r.get("sessions"), int)]`
  - `        streak, cur_min = 0, None`
- **Why it is wrong** — the reset at 115 fires only for a row that survives the filter and is unhealthy.
  - A row with `verdict` other than OK and no integer `sessions`, or a corrupt line anywhere in the file (not only the last), is deleted at 88/102.
  - So 5 OK rows at 46, that row, then 5 OK rows at 46 form a 10-run and give `floor_m=46`.
  - Timestamps are never consulted in the loop. If the alarm did not run for hours (box asleep or off), the rows either side of the hole are adjacent. "10 consecutive 60 s samples = 10 minutes green" (line 52) then means 10 rows over any elapsed time.

## 4. The weekly-span gate is measured on rows the floor then discards, and needs only two rows
- **What** — `u_span_h` runs from the first to the last row of any account (stale or not, usable or not), but the floor uses only fresh, well-typed rows with `weekly_pct < 100`.
- **Where** — lines 125, 128, 132, 139:
  - `util = [r for r in rows(util_log) if r.get("acct")]`
  - `    t0, t1 = ts_of(util[0]), ts_of(util[-1])`
  - `if u_span_h >= need_h:`
  - `            continue                               # an inherited number is not a measurement`
- **Why it is wrong** — one fresh row for account `a` (k=3, weekly 20) at T0 plus a `stale:true` row for account `b` at T0+168h opens the gate.
  - `per` becomes `{"a": 3}` and `pool` is set. With a machine floor, the script exits 0 publishing a pool floor backed by one measurement of one account.
  - That is the "four days of data" case lines 39–41 say must yield INSUFFICIENT-DATA.
  - Stale rows are also counted in `pool_samples` and "samples spanning", although line 139 says they are not measurements.

## 5. The pool floor is a maximum over single samples; no run is required
- **What** — a per-account floor is the largest `k` from any one non-stale row with `weekly_pct < 100`.
- **Where** — line 144: `            per[r["acct"]] = max(per.get(r["acct"], 0), k)`
- **Why it is wrong** — lines 51–52 say a floor "wants a run, not a spike: one lucky sample … proves the box briefly held 46, not that it sustains it", and the machine floor enforces that. The pool floor does not.
  - One sweep row with k=9 sets that account's floor to 9.
  - Because it is a max, no later sample can lower it. A transient reading is published as a floor and summed into `total`.

## 6. The INSUFFICIENT-DATA message blames elapsed time for every shortfall
- **What** — whenever `pool` is None, the output says the gap is hours of history that time will close, even when the span is already met or the timestamps could not be parsed.
- **Where** — lines 129, 172, 174, 178:
  - `    if t0 and t1:`
  - `        short = max(0.0, need_h - u_span_h)`
  - `              f"need {need_h:.0f}h ({short:.0f}h short).")`
  - `              "computable by elapsed time.")`
- **Why it is wrong** — two cases:
  - **Span met, `per` empty.** The series spans ≥168 h but every row is stale, every `weekly_pct` is ≥100, or `k`/`weekly_pct` are missing or of another type. It prints "need 168h (0h short)" and "computable by elapsed time", but waiting changes none of those inputs.
  - **Unparseable `ts`.** If the first or last `ts` fails `fromisoformat`, `ts_of` returns None (line 96) and line 129 skips the span computation. A log holding months of rows is reported as "spanning 0h … (168h short)".

## 7. An unreadable or missing pool store is reported as empty, with the "not a failure" exit code
- **What** — only `CAP_LOG` is checked for readability and `rows()` turns every `OSError` into an empty result, so an unreadable, missing or mis-pathed `UTIL_LOG` is reported as "Store is EMPTY".
- **Where** — lines 67, 89–90, 179–181:
  - `[ -r "$CAP_LOG" ] || { echo "pool-floor: cannot read $CAP_LOG" >&2; exit 1; }`
  - `    except OSError:` / `        return`
  - `        if not util:` / `            print("                Store is EMPTY — no live sweep has happened since the "` / `                  "recorder landed.")`
- **Why it is wrong** — with `CC_UTIL_LOG` set to a file the user cannot read, a directory, or a mistyped path (or a file whose rows all lack `acct`), `util` is `[]`.
  - The script prints "Store is EMPTY — no live sweep has happened since the recorder landed." and exits 3, which lines 43–44 call "an honest non-verdict, not a failure". Exit 1 ("the stores could not be read") is not used.
  - A `CAP_LOG` that is a directory passes `-r`, hits the same `except OSError`, prints "0/0 samples healthy", and also exits 3 instead of 1.

## 8. `--help` prints code
- **What** — help prints lines 2–50, but the comment block ends at line 46.
- **Where** — line 63: `    -h|--help) sed -n '2,50p' "$0"; exit 0 ;;`
- **Why it is wrong** — every `--help` also emits lines 47–50: `set -uo pipefail`, a blank line, and the `CAP_LOG=` and `UTIL_LOG=` assignments.
