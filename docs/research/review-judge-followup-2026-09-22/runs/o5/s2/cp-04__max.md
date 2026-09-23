# Review: `scripts/terminal-bench.sh`

I found 16 defects. Line numbers count every line of the file including the comment header (`set -uo pipefail` is line 48).

---

## 1. The JSONL row is written with the pre-downgrade verdict

**What** — The optional results append records `"verdict":"OK"` for runs whose GPU profile never resolved, because the append happens before the GPU downgrade is applied.

**Where** — lines 247 and 251:
```
    "$(tr '\t' ',' <<<"$T0_APP")" "$GPU_N" "$CPU_N" "$VERDICT" >> "$OUT"
```
```
[ "$GPU_VERDICT" = OK ] || VERDICT="PARTIAL"
```

**Why it is wrong** — Run `--app ghostty --interval 300 --out /tmp/bakeoff.jsonl` on a box where `sample` fails (permission, timeout) or the discriminator matches nothing. `GPU_VERDICT` stays `NO-DATA`, but `VERDICT` was set to `OK` at line 231 and is written to the file at 247. Line 251 then downgrades the shell variable, so stdout prints `verdict=PARTIAL` while the persisted row — the only durable artifact, and the one a bake-off consumer parses — says `OK`. The two records of the same run disagree, and the file claims "a full comparable row" that was never produced.

---

## 2. A missing window census never downgrades the verdict

**What** — The documented PARTIAL condition "window census missing" is never applied; a run with no census at all can still end `verdict=OK`.

**Where** — line 231, with lines 177 and 180:
```
  VERDICT="OK"
```
```
[ -x "$CENSUS_BIN" ] || CENSUS_OK=0
```
```
[ "$CENSUS_OK" = 1 ] || echo "  ⚠ window census unavailable (swiftc failed) — window columns report NA"
```

**Why it is wrong** — If `swiftc` is absent or `CENSUS_SRC` was not found (line 86 only warns, despite the comment on 85 promising to "fail loud"), `CENSUS_OK=0`, every reading reports `win/off/mpx = NA`, and `drift 5 "windows"` / `drift 6 "offscreen win"` print `NA`. `CENSUS_OK` is used for nothing but the warning on 180 — it is never consulted when setting `VERDICT`. With `--interval 300` and a resolved GPU profile, the run prints `verdict=OK` while missing the entire windows axis, so a consumer filing on the verdict token cannot tell this row from one where the census actually ran.

---

## 3. `reading`'s failure return is discarded, so "top returned nothing" never yields NO-DATA

**What** — When `top` produces no line for the pid, `reading` emits an all-NA row and returns 1, but no caller checks the status, so the documented `verdict=NO-DATA` / exit 3 path is unreachable for this case.

**Where** — lines 151, 191, 218:
```
  if [ -z "$line" ]; then printf 'NA\tNA\tNA\tNA\tNA\tNA\tNA\n'; return 1; fi
```
```
T0_APP="$(reading "$PID" "$CENSUS_OWNER")"; T0_WS="$(reading "${WS_PID:-0}" 'Window Server')"
```
```
  T1_APP="$(reading "$PID" "$CENSUS_OWNER")"; T1_WS="$(reading "${WS_PID:-0}" 'Window Server')"
```

**Why it is wrong** — The header documents `verdict=NO-DATA (exit 3)` for "the app is not running, **or top returned nothing**". Only the first half is implemented (lines 125–128). If the terminal quits during the `sleep "$INTERVAL"` hold — the most likely failure during a 300 s measurement — line 218 returns an all-NA `T1_APP`, every drift line prints `NA` (guarded at 225), line 231 still sets `VERDICT="OK"`, and the run reports success with zero drift evidence. The same applies to `T0_APP` if the 30 s `run` timeout kills `top`.

---

## 4. Per-pane normalisation converts NA into 0.00

**What** — The per-pane block feeds the raw row to awk with no NA guard, so a failed reading is printed as measured zeros.

**Where** — lines 237–241:
```
  awk -v p="$PANES" -v r="$T0_APP" 'BEGIN{ split(r,f,"\t");
    printf "    threads/pane   %.2f\n", f[3]/p;
    printf "    ports/pane     %.2f\n", f[4]/p;
    printf "    MB/pane        %.1f\n",  f[2]/p;
    printf "    cpu%%/pane      %.2f\n", f[1]/p }'
```

**Why it is wrong** — If `T0_APP` is the NA row from line 151, awk coerces the string `NA` to 0 in arithmetic context, and `--panes 30` prints `threads/pane 0.00`, `ports/pane 0.00`, `MB/pane 0.0`, `cpu%/pane 0.00`. An operator reads "this challenger costs nothing per pane" from an instrument that did not run — the exact "measured zero" vs "the instrument did not run" confusion the verdict-token comment (lines 41–42) says the script exists to prevent. `drift()` guards for NA on line 225; this block, using the same row, does not.

---

## 5. `show()`'s tab split collapses empty fields — the column shift it claims to prevent

**What** — `IFS=$'\t' read` does not give strict field splitting, so an empty column silently shifts every later column one slot left.

**Where** — line 186 (comment at 182–183):
```
  IFS=$'\t' read -r cpu mem th ports win off mpx <<<"$row"
```

**Why it is wrong** — Tab is an IFS *whitespace* character, so a run of consecutive tabs delimits a single field and leading/trailing tabs are dropped. Given a row where one field is empty — reachable at line 166, where `off="$(cut -f5 <<<"$c")"` yields an empty string if the census TSV has an empty column — `read` sees `...\t\t...` as one separator, assigns `mpx`'s value to `off`, and leaves `mpx` empty. The printed line then reports the multiplexer value under `off=`, which is precisely the "misattribute ports to threads" failure the comment above the function says this construction eliminates.

---

## 6. GPU/CPU symbol counts are taken over the whole `sample` file, including the loaded-library list

**What** — `grep -c` over the entire sample output counts the "Binary Images" and header sections, so a merely *linked* framework registers as GPU usage.

**Where** — lines 199–200:
```
  GPU_N="$(grep -cE "$GPU_RE" "$SAMPLE_F" || true)"
  CPU_N="$(grep -cE "$CPU_RE" "$SAMPLE_F" || true)"
```

**Why it is wrong** — `sample -f` writes a header, the call graph, and a trailing `Binary Images:` listing with the full path of every loaded dylib. For every discriminator except `iTerm2`'s, the regexes match those paths: `Metal`, `OpenGL`, `CGL`, `AGX`, `CoreText` all appear as framework names regardless of whether a single frame was drawn through them. A terminal that loads `Metal.framework` at start-up and then renders every glyph on the CPU still yields `GPU_N ≥ 1`; if `CPU_N` happens to be 0, line 207 prints `ratio=all-GPU`. That is existence-of-a-fast-path evidence being reported as path-taken evidence — the `capability-initialized-is-not-capability-used` error the header (lines 10–13) says the script was written to avoid. Separately, `grep -c` counts *lines*, not stack frames or samples, and both counts carry an app-dependent constant offset from the image list, so the printed `gpu_frames`/`cpu_frames` and their ratio are not comparable across the five terminals.

---

## 7. The WindowServer reading falls back to pid 0

**What** — When `pgrep -x WindowServer` returns nothing, the WS reading is taken against pid 0 and reported under the `WS` label with no warning.

**Where** — lines 129, 191, 218:
```
WS_PID="$(pgrep -x WindowServer | head -1 || true)"
```
```
T0_APP="$(reading "$PID" "$CENSUS_OWNER")"; T0_WS="$(reading "${WS_PID:-0}" 'Window Server')"
```

**Why it is wrong** — The `${WS_PID:-0}` default substitutes a pid that exists: on macOS pid 0 is `kernel_task`. `top -l 2 -pid 0` reports kernel_task, and the filter `grep -E "^[[:space:]]*0[[:space:]]"` matches its row, so the line printed as `T0  WS` carries kernel_task's cpu/mem/threads/ports. (If `top` rejects pid 0 instead, the row is silently NA.) Either way nothing tells the operator the WindowServer row is missing, and the verdict is unaffected — for a tool whose stated root cause is "WindowServer saturation plus a mach-port table that grew without bound" (lines 7 and 22–23), the WS row is either fabricated from the wrong process or absent, and passes as data.

---

## 8. Alacritty has no entry in the process/owner table

**What** — Alacritty, one of the five apps the header says are all measured by the same instrument, falls through to the `*)` branch, which assumes process name = census owner name = the string passed on the command line.

**Where** — lines 100–102:
```
  kitty|kitty.app) PROC_NAMES="kitty";                        CENSUS_OWNER="kitty" ;;
  iTerm2|iTerm)    PROC_NAMES="iTerm2";                       CENSUS_OWNER="iTerm2" ;;
  *)               PROC_NAMES="$APP";                         CENSUS_OWNER="$APP" ;;
```

**Why it is wrong** — Alacritty's executable is `Alacritty.app/Contents/MacOS/alacritty` while its CGWindow owner name is the bundle name `Alacritty`; the two spellings differ, which is exactly the situation the comment on lines 93–96 says the table exists to handle. Both lookups are case-sensitive (`pgrep -x` on 106, and the `a[n]==want` comparison on 121), so `--app Alacritty` finds no pid and exits 3 with "no running process named 'Alacritty'" while Alacritty is running, and `--app alacritty` finds the pid but passes `--owner alacritty` to the census (line 164), which returns nothing, giving NA window columns for the whole run — and, per defect 2, still `verdict=OK`. The GPU table on line 140 does have an `alacritty|Alacritty` branch, so the omission is in the process table only.

---

## 9. Accepted app spellings fall through to the generic GPU discriminator

**What** — The two `case "$APP"` tables accept different sets of spellings, so the same terminal measured under an alias gets a different, weaker GPU discriminator.

**Where** — lines 100–101 versus 136 and 139:
```
  iTerm2|iTerm)    PROC_NAMES="iTerm2";                       CENSUS_OWNER="iTerm2" ;;
```
```
  iTerm2)            GPU_RE='iTermMetalDriver';        CPU_RE='iTermTextDrawingHelper' ;;
```
```
  kitty)             GPU_RE='OpenGL|CGL|AGX|gl[A-Z]';  CPU_RE='CoreText|CGContext' ;;
```

**Why it is wrong** — `--app iTerm` resolves the pid and census owner correctly (line 101) but misses line 136 and lands on the generic fallback at 141 (`Metal|AGX|IOGPU|wgpu|CGL|OpenGL` vs `CoreText|CGContext|CGSBlend`); `--app kitty.app` does the same via line 100. The run succeeds and is filed as `verdict=OK`, but its `gpu_frames`/`cpu_frames` come from a different instrument than a run invoked as `--app iTerm2`. Two rows in the same JSONL for the same terminal are then not comparable, which is the property the first three lines of the file claim for every row.

---

## 10. Drift rates are extrapolated from `INTERVAL`, not from the elapsed time between readings

**What** — The per-hour extrapolation divides by the requested sleep duration, but substantially more time than that passes between the two readings.

**Where** — lines 226–227:
```
    awk -v a="$a" -v b="$b" -v s="$INTERVAL" -v l="$label" \
      'BEGIN{ d=b-a; printf "    %-14s %+.0f over %ds  = %+.1f/hr\n", l, d, s, d*3600/s }'
```

**Why it is wrong** — Between T0 (line 191) and T1 (line 218) the script runs a second `top -l 2` for WindowServer, then `sample` for `SAMPLE_SECS` (default 5) plus its symbolication, then sleeps `INTERVAL`, then runs `top -l 2` again — whose *second* sample, the one actually read, lands roughly a further second or two later, plus a census invocation. The true span is on the order of `INTERVAL + 10–20 s`, so every `/hr` figure is overstated by that fraction: about 5–10% at the default 180 s, and grossly at short intervals. The header calls this reading "the only reading that supports a leak verdict"; its denominator is assumed rather than measured, and the printed text `over %ds` asserts an interval that did not occur.

---

## 11. `--help` truncates the documentation it prints

**What** — The help text stops at line 45, cutting the PARTIAL description mid-sentence and omitting the `verdict=NO-DATA` token entirely.

**Where** — line 61:
```
    -h|--help)     sed -n '1,45p' "$0"; exit 0 ;;
```

**Why it is wrong** — The comment block runs to line 47. `sed -n '1,45p'` ends at `missing. \`--interval 0\` always yields PARTIAL by construction: a single`, dropping line 46 and the whole `verdict=NO-DATA the app is not running, or top returned nothing (exit 3)` line. A user running `--help` to learn the machine-parsable contract is shown two of the three verdict tokens the script can emit, and is never told that NO-DATA exits 3.

---

## 12. A missing option value makes the argument loop spin forever

**What** — `shift 2` with only one positional argument left fails without shifting, so the `while` loop re-matches the same flag indefinitely.

**Where** — lines 54–56 (identical on 57–60):
```
while [ $# -gt 0 ]; do
  case "$1" in
    --app)         APP="${2:-}"; shift 2 ;;
```

**Why it is wrong** — Invoke `scripts/terminal-bench.sh --app` (flag typed last, value forgotten). `${2:-}` supplies an empty `APP`, then bash's `shift 2` returns non-zero and leaves `$#` at 1 because 2 exceeds the number of positionals; `set -uo pipefail` does not include `-e`, so nothing aborts. `$1` is still `--app`, the loop body repeats forever, and the script hangs silently instead of reaching the `--app <AppName> is required` check on line 65.

---

## 13. Unvalidated numeric arguments are interpolated bare into the JSON row

**What** — `panes` and `interval` are written as unquoted JSON values without ever being checked for numerality, so a non-numeric argument produces an unparseable line in the results file.

**Where** — lines 245–246:
```
  printf '{"ts":"%s","app":"%s","pid":%s,"panes":%s,"interval":%s,"t0":"%s","gpu_frames":"%s","cpu_frames":"%s","verdict":"%s"}\n' \
    "$(date -u +%FT%TZ)" "$APP" "$PID" "${PANES:-0}" "$INTERVAL" \
```

**Why it is wrong** — `--panes thirty --out /tmp/bakeoff.jsonl` appends `{"ts":"…","app":"iTerm2","pid":591,"panes":thirty,…}`. That is not JSON, so a consumer reading the JSONL fails on the whole file, not just the bad row — and the run still prints `verdict=OK`. The same input also makes `[ "${PANES:-0}" -gt 0 ]` on line 235 emit a bash "integer expression expected" error and silently skip the per-pane block.

---

## 14. A stale census binary is used when the source file is missing

**What** — The rebuild condition cannot fire when `CENSUS_SRC` does not exist, so a leftover binary from an earlier checkout is executed and its output reported as the current tool's.

**Where** — lines 174 and 87:
```
if [ ! -x "$CENSUS_BIN" ] || [ "$CENSUS_SRC" -nt "$CENSUS_BIN" ]; then
```
```
CENSUS_BIN="${TMPDIR:-/tmp}/window-census.$(id -u)"
```

**Why it is wrong** — If `REPO` resolves somewhere without `tools/terminal-bench/` (the failure mode the whole symlink block on 75–83 exists to prevent), line 86 prints a warning and continues. Then `-nt` is false because the first operand does not exist, and `! -x` is false because a `window-census.<uid>` from a previous run is still in `TMPDIR`, so the compile is skipped, `CENSUS_OK` stays 1, no "census unavailable" warning is printed, and the window columns are filled by an unknown-vintage binary. Additionally, when `TMPDIR` is unset (launchd, cron, `env -i`), the path is `/tmp/window-census.<uid>` in a world-writable directory and is executed with no provenance check at all.

---

## 15. The `ps` fallback computes the basename from only the first whitespace token of `comm`

**What** — `awk`'s `$2` is the first space-delimited field of the command path, so any executable path containing a space is matched against a truncated basename.

**Where** — line 121:
```
    PID="$(ps -eo pid=,comm= | awk -v want="$_p" '{n=split($2,a,"/"); if (a[n]==want) {print $1; exit}}')"
```

**Why it is wrong** — `ps -eo comm=` prints the full executable path, which the fallback splits on `/` to get the basename. For a bundle installed under a path with a space — a home directory such as `/Users/chris ren/Applications/Ghostty.app/Contents/MacOS/ghostty`, or any app relocated into a folder with a space — `$2` is `/Users/chris`, the computed basename is `chris`, and the comparison against `ghostty` fails. The one fallback written specifically because `pgrep` cannot be trusted on this box then also misses, and the script reports `verdict=NO-DATA` exit 3 for a terminal that is running.

---

## 16. The persisted row omits the second reading and the drift numbers

**What** — The JSONL line records only `t0`, so the drift measurement that `verdict=OK` certifies is never written to the file.

**Where** — lines 245–247:
```
    "$(tr '\t' ',' <<<"$T0_APP")" "$GPU_N" "$CPU_N" "$VERDICT" >> "$OUT"
```

**Why it is wrong** — `verdict=OK` is documented as "both readings taken … a full comparable row", but `T1_APP`, `T1_WS`, `T0_WS` and the four drift figures exist only on the terminal and are discarded when the process exits. A consumer parsing `/tmp/bakeoff.jsonl` sees an `OK` verdict with no way to check the readings behind it — including, per defect 3, the case where every drift line printed `NA`.

---

No other defects found: the `drift` field indices (2/4/5/6) and the per-pane field indices (f[1]–f[4]) both match the column order emitted by `reading`, the `[ "$a" = NA ] || [ "$b" = NA ] && …` guard on line 225 evaluates as intended, the symlink walk on 75–83 correctly resolves the final link component, the MB normalisation on 157–160 handles the `K`/`M`/`G` and `+`/`-` suffixes `top` emits, and the `run` helper's no-timeout branch correctly drops the duration argument.
