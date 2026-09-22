Line numbers count `#!/bin/bash` as line 1. I found 14 defects.

## Machine floor

**1.**
- **What:** The run minimum is a running minimum from the start of each healthy streak, so only the first `RUN` samples of a streak can ever set the machine floor.
- **Where:** L111 `cur_min = n if cur_min is None else min(cur_min, n)`; L112 `if streak >= run_len and cur_min > floor_m:`; L113 `floor_m, best_run = cur_min, streak`
- **Why:** `cur_min` is reset only by an unhealthy sample (L115), so within a streak it can only fall. Take a single healthy streak that opens at 3 sessions and later holds 40 for five hours. It yields a floor of at most 3, and the 40-session stretch can never register. The header's definition (L26–27, "the largest session count sustained across a run of consecutive samples") gives 40. On a mostly-healthy box, where streaks are long, the floor is just the minimum load in the first 10 samples after each alarm clears.

**2.**
- **What:** `best_run` (reported as `machine_floor_run_samples` and "N consecutive healthy samples") is always exactly `RUN` or 0, never the length of the run that held the floor.
- **Where:** L113 `floor_m, best_run = cur_min, streak`
- **Why:** `cur_min` never rises within a streak, so L112 can be true only at `streak == run_len`; after that `cur_min <= floor_m`. A floor held for 500 consecutive healthy samples is reported as "10 consecutive healthy samples". The configured threshold is echoed back as if it were a measurement.

**3.**
- **What:** Neither floor is ever lowered by contrary evidence, although the header says "one counter-example sample lowers it" (L19).
- **Where:** L112 `if streak >= run_len and cur_min > floor_m:`; L143 `if w < 100:`; L144 `per[r["acct"]] = max(per.get(r["acct"], 0), k)`
- **Why:** `floor_m` and each `per[acct]` only move upward. A sample that is unhealthy, or at ≥100% weekly, at fewer sessions than the current floor is simply skipped. If the box held 30 green months ago and today goes non-OK or starts swapping at 12, the script still publishes 30 from the whole-history log. Likewise, an account observed at 100% weekly with k=4 keeps its per-account floor of 12.

**4.**
- **What:** Rows whose `sessions` is not an int are removed before the streak loop, so an unhealthy sample without a session count cannot break a run.
- **Where:** L102 `cap = [r for r in rows(cap_log) if isinstance(r.get("sessions"), int)]`
- **Why:** The filter applies to the sequence the streak walks, not just to the minimum. A row such as `{"verdict":"CRIT","sessions":null,…}` sitting between healthy rows disappears. Its neighbours become "consecutive", and a green run is certified straight through a sample the alarm itself flagged.

**5.**
- **What:** Adjacent rows are treated as adjacent minutes; timestamps are never checked inside a run.
- **Where:** L109 `streak += 1` (the only `ts` reads for this log are the endpoints, L120 `t0, t1 = ts_of(cap[0]), ts_of(cap[-1])`)
- **Why:** The premise on L52 ("10 consecutive 60 s samples = 10 minutes green") is assumed, not verified. Suppose the alarm wrote nothing for hours because the host was asleep, or because the daemon stalled or was killed under memory pressure. Then 5 samples before the gap and 5 after it count as a 10-minute green run.

**6.**
- **What:** A missing or null `swap_used_mb` is treated as zero swap, which silently waives the swap half of the health test.
- **Where:** L106 `ok = r.get("verdict") == "OK" and float(r.get("swap_used_mb") or 0) <= 0`
- **Why:** `or 0` maps an absent or null field to 0. Any row lacking the field (older schema, renamed field, failed swap read) therefore passes as "no swap". L99–101 say that requiring both terms is what makes this a floor, but for such rows the floor rests on `verdict` alone.

**7.**
- **What:** The swap test implements "no swap in use", not the "zero swap growth" that the header uses to define the machine floor.
- **Where:** L106 `ok = r.get("verdict") == "OK" and float(r.get("swap_used_mb") or 0) <= 0` (vs. L27 `…samples with verdict=OK and zero swap growth…`)
- **Why:** Swap left over from an earlier episode can stay allocated but flat, for example on macOS, where swap persists long after pressure subsides. In that state every sample fails `<= 0` and no streak forms. Samples that the stated definition counts as healthy are excluded, lowering the floor, down to 0 / INSUFFICIENT-DATA if swap never returns to zero.

## Pool floor

**8.**
- **What:** The "series must span a weekly window" guard is measured over all rows of all accounts combined, including rows the floor computation then discards.
- **Where:** L125 `util = [r for r in rows(util_log) if r.get("acct")]`; L132 `if u_span_h >= need_h:`
- **Why:** The span runs from the first row to the last row of the union and counts `stale` rows and rows lacking `k`/`weekly_pct`. That lets thin data through in several ways:
  - If accounts A–C have 8 days of rows and D was first recorded an hour ago, D's single sample becomes its per-account floor and is summed in.
  - If the first 6 days are all stale rows, the "weekly" floor rests on about 1 day of real measurements.
  - Two rows 168 h apart also pass.

  L54–55 say the span requirement exists so the number isn't noise, and this guard does not establish that. `pool_samples` and the "N samples" text (L156, L173) also count the stale rows.

**9.**
- **What:** Each per-account pool value is the single largest instantaneous `k` (a spike), and the total sums spikes taken at different moments.
- **Where:** L144 `per[r["acct"]] = max(per.get(r["acct"], 0), k)`; L146 `pool = {"per_account": per, "total": sum(per.values())}`
- **Why:** One sweep that saw 12 live sessions on an account sets its floor to 12, even if every other sweep saw 3 or fewer. That is exactly what L51–52 say a floor must not do, and the run requirement applied to the machine floor is absent here. A=12 on Monday plus B=10 on Thursday is published as 22, a concurrency that was never held, and L134–135 call it "the conservative fleet figure".

**10.**
- **What:** The condition "while that account's weekly window stayed under 100%" is checked only at the instant of each sample.
- **Where:** L143 `if w < 100:`
- **Why:** A sweep at 97% weekly with k=12 qualifies even if that load pushed the account to 100% an hour later in the same window. The load was demonstrably not sustainable, yet it is published as the floor, labelled "measured while … under 100%".

**11.**
- **What:** The pool span uses only the first and last rows, so one missing or unparseable `ts` at either end sets it to zero.
- **Where:** L128 `t0, t1 = ts_of(util[0]), ts_of(util[-1])`; L129 `if t0 and t1:`
- **Why:** `ts_of` returns None, so `u_span_h` stays 0.0 however many timestamped rows lie between. The pool floor is withheld and the output says "spanning 0h … (168h short)". If the bad row is the first one, this is permanent. L120–121 do the same for the machine "over Nh" figure.

## Verdict / reporting

**12.**
- **What:** Whenever `pool` is None, the output asserts the pool floor will become computable with elapsed time, without establishing that the span is what's missing.
- **Where:** L172 `short = max(0.0, need_h - u_span_h)`; L177 `print("                live sweep at no extra cost. Nothing to run; this becomes "`
- **Why:** The span can be 168 h or more while no row qualifies: every row is stale, every row is at ≥100% weekly, or `k`/`weekly_pct` is absent or the wrong type (e.g. `k` written as `3.0`). Then `if per:` (L145) fails, and the script prints "INSUFFICIENT-DATA — N samples spanning 200h, need 168h (0h short). … Nothing to run; this becomes computable by elapsed time." It never will. A schema break, or a pool that is always exhausted, is reported as an honest exit-3 wait. The span is also measured to the last row rather than to now, so a recorder that has stopped appending gets the same promise.

**13.**
- **What:** A missing or unreadable utilization store is indistinguishable from an empty one and is reported as "no live sweep has happened … becomes computable by elapsed time", with exit 3.
- **Where:** L89 `except OSError:`; L90 `return`; L67 `[ -r "$CAP_LOG" ] || { echo "pool-floor: cannot read $CAP_LOG" >&2; exit 1; }`; L180 `print("                Store is EMPTY — no live sweep has happened since the "`
- **Why:** `rows()` turns any OSError into an empty sequence: permission denied, an I/O error, a path that is a directory, or `CC_UTIL_LOG` pointing at the wrong place. Only `CAP_LOG` gets the readability check that leads to exit 1 (L44: "the stores could not be read"). In any of these cases the script tells the operator nothing is wrong and waiting will fix it, and it keeps saying so indefinitely.

**14.**
- **What:** `floor_m == 0` serves both as "no machine floor" and as a printed measurement, so the outputs contradict each other.
- **Where:** L159 `"verdict": "OK" if (floor_m and pool) else "INSUFFICIENT-DATA",`; L164 `print(f"MACHINE floor : {floor_m} concurrent sessions sustained "`; L183 `sys.exit(0 if (floor_m and pool) else 3)`
- **Why:** Suppose `CAP_LOG` is readable but empty, has no int `sessions`, or no healthy run reaches `RUN`. The text then says "MACHINE floor : 0 concurrent sessions sustained (0 consecutive healthy samples; … 0/0 samples healthy over 0h)". That is a number, with no statement of what's missing, although L3–4 promise one, and the JSON carries `"machine_floor_sessions":0`. Once the pool floor exists, a zero machine floor produces text showing two floors and no INSUFFICIENT-DATA line, while the JSON verdict and exit code say INSUFFICIENT-DATA / 3.
