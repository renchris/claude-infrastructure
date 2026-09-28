I found 12 defects; the last two are lower-confidence. Line numbers count `#!/bin/bash` as line 1.

**1. The JSONL row records the verdict before it is downgraded.**
- **What:** The appended row stores `$VERDICT` before the GPU-based downgrade to PARTIAL runs, so the file can say OK while the console says PARTIAL.
- **Where:** line 247 `"$(tr '\t' ',' <<<"$T0_APP")" "$GPU_N" "$CPU_N" "$VERDICT" >> "$OUT"`; the downgrade is line 251 `[ "$GPU_VERDICT" = OK ] || VERDICT="PARTIAL"`.
- **Why it is wrong:**
  - With `--interval >0` and `--out` set, if `sample` fails or matches nothing, `VERDICT` is already `OK` (line 231) when line 247 writes it.
  - Line 251 then prints `verdict=PARTIAL`, but the persisted row says `"verdict":"OK"` with `"gpu_frames":"NA"`, so it is filed as a full comparable row.
  - The row also holds only the `t0` reading, with no T1 and no drift, although `OK` is documented as "both readings taken".

**2. `verdict=OK` is set unconditionally after the interval.**
- **What:** Reaching the end of the drift block sets OK whether or not any reading or the window census produced data.
- **Where:** line 231 `VERDICT="OK"`.
- **Why it is wrong:**
  - The header says any missing drift, GPU profile or window census means PARTIAL.
  - If the T1 reading is all NA (top timed out, the process died) or the census is unavailable (`CENSUS_OK=0`), the drift lines print `NA`.
  - Line 231 still sets OK, and line 251 only downgrades on the GPU result. The run ends `verdict=OK` with missing columns.

**3. A failed `top` never yields `verdict=NO-DATA` or exit 3.**
- **What:** The header says NO-DATA (exit 3) covers "top returned nothing", but only a missing PID reaches that path.
- **Where:** line 151 `if [ -z "$line" ]; then printf 'NA\tNA\tNA\tNA\tNA\tNA\tNA\n'; return 1; fi`. The only NO-DATA exit is line 127 `echo "verdict=NO-DATA"; exit 3`.
- **Why it is wrong:** If `top` returns nothing for the app (timeout, permission, process gone), the script continues with NA rows and ends with exit 0 and OK or PARTIAL. "The instrument did not run" is not reported as such.

**4. The per-pane block reports zeros when the reading failed.**
- **What:** awk coerces the string `NA` to 0, so a failed T0 reading prints as measured zero.
- **Where:** lines 237–241, e.g. line 238 `printf "    threads/pane   %.2f\n", f[3]/p;`.
- **Why it is wrong:** With `--panes 30` and `T0_APP` equal to the NA row, `f[1..4]` are `"NA"`. The output is `threads/pane 0.00`, `ports/pane 0.00`, `MB/pane 0.0`, `cpu%/pane 0.00`. This is the "measured zero vs did not run" confusion the header warns about.

**5. A value-taking flag with no value loops forever.**
- **What:** The `${2:-}` default looks like handling for a missing value, but `shift 2` fails when only one argument remains and shifts nothing.
- **Where:** line 56 `--app)         APP="${2:-}"; shift 2 ;;`. Lines 57–60 (`--panes`, `--interval`, `--sample-secs`, `--out`) have the same pattern.
- **Why it is wrong:** Running `terminal-bench.sh --app` (or `--interval` as the last argument) makes `shift 2` return non-zero with `$#` still 1. The `while [ $# -gt 0 ]` loop never terminates and prints "shift count out of range" repeatedly. There is no `set -e` to stop it.

**6. The GPU/CPU "frame" counts are line counts over the whole `sample` file, so the 0:0 guard almost never fires.**
- **What:** `grep -c` counts every line in the file, including the "Binary Images:" list of loaded libraries, rather than weighted call-graph frames.
- **Where:** line 199 `GPU_N="$(grep -cE "$GPU_RE" "$SAMPLE_F" || true)"`, line 200 `CPU_N="$(grep -cE "$CPU_RE" "$SAMPLE_F" || true)"`, guard line 203 `if [ "$GPU_N" -gt 0 ] || [ "$CPU_N" -gt 0 ]; then GPU_VERDICT="OK"; fi`.
- **Why it is wrong:**
  - Any app that merely links Metal or CoreText has matching image lines. Ghostty, WezTerm, kitty and the generic `*` regexes (`Metal`, `CoreText`, `AGX`, `OpenGL`) hit these regardless of what the app draws.
  - The counts are then non-zero, the verdict is OK, and the ratio reflects library presence. That is the "existence, not use" evidence the header rejects, and the 0:0 guard is defeated.
  - Lines are not weighted by sample counts, and the same frame appears in several tree levels and in the "Sort by top of stack" section, so the ratio is not a time share.

**7. `show()` collapses empty fields despite the comment saying it prevents that.**
- **What:** With `IFS=$'\t'`, tab is an IFS whitespace character, so consecutive tabs merge and empty fields disappear.
- **Where:** line 186 `IFS=$'\t' read -r cpu mem th ports win off mpx <<<"$row"`.
- **Why it is wrong:** For a row like `0.0\t783\t17\t120\t\t\t` (an empty field from the census `cut`), `read` merges the delimiters. Later values shift left, so ports can land under threads, which is exactly what lines 182–183 say this code avoids. `drift` uses `cut -f`, which does not collapse, so the two disagree.

**8. The two `case "$APP"` tables disagree about aliases.**
- **What:** Aliases accepted for process lookup fall through to the generic GPU/CPU regexes.
- **Where:** line 101 `iTerm2|iTerm) PROC_NAMES="iTerm2";                       CENSUS_OWNER="iTerm2" ;;` versus line 136 `iTerm2)            GPU_RE='iTermMetalDriver';        CPU_RE='iTermTextDrawingHelper' ;;`. Likewise line 100 `kitty|kitty.app)` versus line 139 `kitty)             GPU_RE='OpenGL|CGL|AGX|gl[A-Z]';  CPU_RE='CoreText|CGContext' ;;`.
- **Why it is wrong:** `--app iTerm` finds the iTerm2 process but is profiled with the generic regexes (`Metal|AGX|…`) instead of `iTermMetalDriver`. The same happens for `--app kitty.app`. The row is labelled as if measured by the same instrument, but it was not.

**9. "appended" is printed even when the write failed.**
- **What:** The success message does not depend on the append succeeding.
- **Where:** line 247 `… "$VERDICT" >> "$OUT"` followed by line 248 `echo "  appended → $OUT"`.
- **Why it is wrong:** If `$OUT` is in a non-existent directory or is unwritable, the redirection fails with a stderr message, and the script still prints `appended → …`. The row is lost while the output claims otherwise.

**10. The drift rate is divided by `INTERVAL`, but the readings are further apart than that.**
- **What:** The elapsed time between T0 and T1 is `INTERVAL` plus the T0 WS reading, the `sample` run and the T1 `top`, but the rate uses `INTERVAL` alone.
- **Where:** line 226 `awk -v a="$a" -v b="$b" -v s="$INTERVAL" -v l="$label" \` with line 227 `'BEGIN{ d=b-a; printf "    %-14s %+.0f over %ds  = %+.1f/hr\n", l, d, s, d*3600/s }'`. The extra time comes from line 198 `sample "$PID" "$SAMPLE_SECS"` running between the readings.
- **Why it is wrong:** The `sample` run (5 s by default) and the reading overhead add roughly 7–9 s before `sleep "$INTERVAL"`. The printed "over ${INTERVAL}s" and per-hour rate are overstated by about 3% at `--interval 300` and about 25% at `--interval 30`.

**11. (Lower confidence) A stale census binary is used while the banner says the census is unavailable.**
- **What:** `CENSUS_OK` is not consulted by `reading()`, and a failed rebuild does not remove the old binary.
- **Where:** line 175 `if ! run 300 swiftc -O "$CENSUS_SRC" -o "$CENSUS_BIN" 2>/dev/null; then CENSUS_OK=0; fi`, versus line 163 `if [ -x "$CENSUS_BIN" ]; then`.
- **Why it is wrong:** If `window-census.swift` is newer than the existing binary and `swiftc` fails, `CENSUS_OK=0` and line 180 prints "window columns report NA". The old executable binary still exists, so line 163 runs it and the window columns hold values from a previous build of the source.

**12. (Lower confidence) `WS_PID` falls back to 0, which is `kernel_task`.**
- **What:** If `pgrep -x WindowServer` finds nothing, the WindowServer reading is taken for pid 0.
- **Where:** line 191 `T0_APP="$(reading "$PID" "$CENSUS_OWNER")"; T0_WS="$(reading "${WS_PID:-0}" 'Window Server')"` (same at line 218).
- **Why it is wrong:** Pid 0 is a real process. If `top -pid 0` accepts it, the grep `^[[:space:]]*0[[:space:]]` matches `kernel_task`, and its cpu/mem/threads/ports are printed under the `WS` label as WindowServer numbers.

Additionally, `--help` is truncated. Line 61 `-h|--help)     sed -n '1,45p' "$0"; exit 0 ;;` prints lines 1–45, but the header comment runs to line 47. The last sentence of the PARTIAL description and the whole `verdict=NO-DATA` token are cut off.
