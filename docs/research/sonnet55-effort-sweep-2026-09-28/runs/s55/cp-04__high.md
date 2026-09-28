I found nine defects. I read the text only and ran nothing, so line numbers come from my own count of the pasted file.

**1. A flag given as the last argument hangs the script forever.**
- **Where:** lines 56–60, e.g. line 60: `    --out)         OUT="${2:-}"; shift 2 ;;`. `--app`, `--panes`, `--interval` and `--sample-secs` have the same `shift 2`.
- **Why it is wrong:** `${2:-}` tolerates a missing value, but `shift 2` with only one argument left fails and shifts nothing. Running `terminal-bench.sh --app iTerm2 --out` (or any value-taking flag last) leaves `$#` at 1, so the `while [ $# -gt 0 ]` loop spins forever instead of exiting 2.

**2. `verdict=OK` ignores the window census, so a row with no window data is called complete.**
- **Where:** line 232 `  VERDICT="OK"` and line 252 `[ "$GPU_VERDICT" = OK ] || VERDICT="PARTIAL"`.
- **Why it is wrong:** The header says PARTIAL applies when any of drift, GPU profile or window census is missing. `CENSUS_OK` is only used to print a warning at line 181, and the verdict never reads it. If swiftc fails or the census returns nothing, `win`, `off` and `mpx` are NA, yet a run with a resolved GPU profile and interval > 0 still ends `verdict=OK`.

**3. A failed `top` reading never produces NO-DATA, and a failed T1 reading still yields OK.**
- **Where:** line 152 `  if [ -z "$line" ]; then printf 'NA\tNA\tNA\tNA\tNA\tNA\tNA\n'; return 1; fi`, plus line 232 `  VERDICT="OK"`.
- **Why it is wrong:** The header says NO-DATA means "the app is not running, or top returned nothing (exit 3)". The script only exits 3 when `pgrep`/`ps` finds no PID, so it carries on if `top` returns nothing. If the process exits between the PID lookup and the readings, T0 and T1 are all NA. Line 232 sets `VERDICT="OK"` unconditionally once `INTERVAL > 0`, and the drift lines print NA. With a GPU verdict of OK the script prints `verdict=OK` and exits 0 with no measurements. That is the "measured zero versus instrument did not run" failure the header says it prevents.

**4. The JSONL row records a verdict that differs from the one printed.**
- **Where:** line 248 `    "$(tr '\t' ',' <<<"$T0_APP")" "$GPU_N" "$CPU_N" "$VERDICT" >> "$OUT"` versus line 252 `[ "$GPU_VERDICT" = OK ] || VERDICT="PARTIAL"`.
- **Why it is wrong:** The append happens before the GPU downgrade on line 252. When `--out` is used, `--interval` is above 0 and the GPU profile is NO-DATA, the file gets `"verdict":"OK"` while stdout prints `verdict=PARTIAL`. The persisted results, which are what gets compared across terminals, overstate completeness.

**5. Missing readings become zero in the per-pane block.**
- **Where:** line 239 `    printf "    threads/pane   %.2f\n", f[3]/p;` (lines 239–242 all do this).
- **Why it is wrong:** If T0 is all NA (`top` failed), `f[3]` is the string "NA". awk coerces it to 0, so the script prints `threads/pane 0.00`, `ports/pane 0.00`, `MB/pane 0.0` and `cpu%/pane 0.00`. A failed measurement is reported as a measured zero.

**6. The GPU/CPU frame counts are line counts over the whole `sample` file, not frames taken.**
- **Where:** line 200 `  GPU_N="$(grep -cE "$GPU_RE" "$SAMPLE_F" || true)"` and line 201 `  CPU_N="$(grep -cE "$CPU_RE" "$SAMPLE_F" || true)"`.
- **Why it is wrong:** `sample` output includes a "Binary Images" list and thread and header lines, not only stack frames. Loose patterns such as `Metal`, `AGX`, `OpenGL`, `CoreText` and `CGContext` can match the image paths of loaded frameworks, for example `Metal.framework` or `CoreText.framework`. That counts a library being loaded, which is the "existence of a fast path" evidence the header says can't show a path is used. The counts also ignore the per-frame sample counts in the call tree, so a frame seen once weighs the same as one seen in every sample. The GPU:CPU ratio and the "OK" GPU verdict can therefore be non-zero or skewed for an app that never renders on that path.

**7. Names accepted by the process table are not handled by the GPU table, and alacritty is missing from the process/owner table.**
- **Where:** line 101 `  iTerm2|iTerm)    PROC_NAMES="iTerm2";                       CENSUS_OWNER="iTerm2" ;;`, line 137 `  iTerm2)            GPU_RE='iTermMetalDriver';        CPU_RE='iTermTextDrawingHelper' ;;`, and line 102 `  *)               PROC_NAMES="$APP";                         CENSUS_OWNER="$APP" ;;`.
- **Why it is wrong:**
  - `--app iTerm` (and `--app kitty.app`) is accepted at lines 98–101 but falls through to the generic `*)` GPU patterns at line 142. It runs with different discriminators from `--app iTerm2`, so the numbers are not comparable.
  - Alacritty has a GPU entry but no process/owner entry. `--app Alacritty` looks for a process literally named `Alacritty`, and the binary is normally lowercase `alacritty`, so it reports NO-DATA. `--app alacritty` finds the process but sets `CENSUS_OWNER="alacritty"`, and the window-server owner is normally `Alacritty`. The window columns come back NA, the same mismatch the comment describes for WezTerm.

**8. Drift rates are divided by the requested interval, not the elapsed time.**
- **Where:** line 228 `      'BEGIN{ d=b-a; printf "    %-14s %+.0f over %ds  = %+.1f/hr\n", l, d, s, d*3600/s }'`, with `-v s="$INTERVAL"` on line 227.
- **Why it is wrong:** Between the T0 and T1 readings the script also runs the T0 window-server reading, a `sample` of `SAMPLE_SECS` (default 5 s, up to 120 s allowed), and the reading time itself. The gap is therefore `INTERVAL` plus roughly 10–20 s or more, but the /hr figure assumes exactly `INTERVAL`. This overstates the per-hour rate, and badly so for small `--interval` values. The header's "a known interval apart" is not true.

**9. `show` uses `IFS=$'\t'`, which does not preserve empty fields.**
- **Where:** line 187 `  IFS=$'\t' read -r cpu mem th ports win off mpx <<<"$row"`.
- **Why it is wrong:** The comment above it says splitting on TAB avoids columns shifting when a field is empty. Tab is an IFS whitespace character, so consecutive tabs collapse into one separator. If any field is empty, for example an empty `th` from a blank `awk '{print $5}'` or a census `cut` that yields nothing, every later value moves one column left. The printed line then shows ports under `th=` and so on, which is the misattribution the comment claims is prevented.
