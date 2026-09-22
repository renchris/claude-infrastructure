# Review of `scripts/terminal-bench.sh`

I found 13 defects. The file does not deliver the verdict contract its header describes (defects 1–3), and the GPU-path measurement cannot tell "used" from "loaded" (defects 5–6).

---

### 1. The JSONL row records the verdict before the GPU downgrade

- **What:** The results file gets the verdict before the GPU-profile check can lower it to PARTIAL, so the file and stdout can disagree.
- **Where:** lines 244–246 (`printf '{"ts":"%s",…,"verdict":"%s"}\n' \` … `"$(tr '\t' ',' <<<"$T0_APP")" "$GPU_N" "$CPU_N" "$VERDICT" >> "$OUT"`), which run before line 250 (`[ "$GPU_VERDICT" = OK ] || VERDICT="PARTIAL"`).
- **Why it is wrong:** Take `--interval 300 --out f.jsonl` where `sample` fails or matches nothing. Line 230 sets `VERDICT="OK"` and line 246 appends `"verdict":"OK"`. Only afterwards does line 250 downgrade it, so stdout prints `verdict=PARTIAL`. The persisted row claims a full comparable result that the script itself rejected.

### 2. A missing window census never makes the verdict PARTIAL

- **What:** The header lists "window census" as a condition for PARTIAL, but `CENSUS_OK` is never consulted when the verdict is computed.
- **Where:**
  - line 176: `[ -x "$CENSUS_BIN" ] || CENSUS_OK=0`
  - line 179: `[ "$CENSUS_OK" = 1 ] || echo "  ⚠ window census unavailable (swiftc failed) — window columns report NA"`
  - line 230: `VERDICT="OK"`
  - line 250: `[ "$GPU_VERDICT" = OK ] || VERDICT="PARTIAL"`
  - line 85: `[ -f "$CENSUS_SRC" ] || echo "terminal-bench: ⚠ census source not found under REPO=$REPO" >&2`
- **Why it is wrong:** Suppose `swiftc` fails, or REPO resolves to a tree without `tools/`, or the census returns no row for the owner. Every window column is then `NA`. With `--interval >0` and any GPU match, the script still prints `verdict=OK` and exits 0. That is the "NA-everywhere and still exit 0" outcome the comment at lines 66–73/84 says it prevents. Line 85 only warns and carries on.

### 3. A failed `top` reading never yields NO-DATA or PARTIAL

- **What:** `reading` returns 1 when `top` returns nothing, but every caller ignores that status. The drift block then sets OK unconditionally.
- **Where:**
  - line 150: `if [ -z "$line" ]; then printf 'NA\tNA\tNA\tNA\tNA\tNA\tNA\n'; return 1; fi`
  - line 190: `T0_APP="$(reading "$PID" "$CENSUS_OWNER")"; T0_WS="$(reading "${WS_PID:-0}" 'Window Server')"`
  - line 217: `T1_APP="$(reading "$PID" "$CENSUS_OWNER")"; T1_WS="$(reading "${WS_PID:-0}" 'Window Server')"`
  - line 230: `VERDICT="OK"`
- **Why it is wrong:** The header promises `verdict=NO-DATA` with exit 3 when "top returned nothing". That promise is broken in several cases:
  - `top` times out or is denied.
  - The app quits during the `sleep`, so `top -pid` finds nothing.
  - `top` returns nothing at T0.

  In all of these the rows are all-NA, drift prints `NA`, and the verdict is still `OK` (or `PARTIAL`) with exit 0. "The instrument did not run" becomes indistinguishable from a real row.

### 4. A missing WindowServer pid falls back to pid 0, which is `kernel_task`

- **What:** When `pgrep` can't find WindowServer, the script measures pid 0 instead and labels the result as WindowServer.
- **Where:**
  - line 128: `WS_PID="$(pgrep -x WindowServer | head -1 || true)"`
  - line 190 (and 217): `T0_WS="$(reading "${WS_PID:-0}" 'Window Server')"`
- **Why it is wrong:** If `pgrep -x WindowServer` returns nothing, `top -l 2 -pid 0` reports `kernel_task`. The grep `^[[:space:]]*0[[:space:]]` matches that row, so kernel_task's CPU, memory, threads and ports are printed as `T0  WS` / `T1  WS`. The comments at 108–114 document `pgrep` silently dropping processes on this box, so this is a realistic path. The result is wrong numbers, not NA.

### 5. The GPU discriminator greps the whole `sample` report, so it matches loaded libraries

- **What:** The patterns are counted across the entire `sample` output, including the "Binary Images" list of loaded libraries, not just the call tree.
- **Where:**
  - line 198: `GPU_N="$(grep -cE "$GPU_RE" "$SAMPLE_F" || true)"`
  - line 199: `CPU_N="$(grep -cE "$CPU_RE" "$SAMPLE_F" || true)"`
  - line 202: `if [ "$GPU_N" -gt 0 ] || [ "$CPU_N" -gt 0 ]; then GPU_VERDICT="OK"; fi`
- **Why it is wrong:** The `sample` output lists every loaded image, such as `…/Metal.framework/…`, `…/CoreText.framework/…`, `AGX…`, `OpenGL.framework`. Any app that merely links Metal or CoreText therefore scores `GPU_N>0` and `CPU_N>0` even if it never calls them. For the ghostty, wezterm, kitty, alacritty and generic patterns (`Metal`, `CoreText`, `OpenGL`, `CGL`, `AGX`, `IOGPU`), `GPU_VERDICT` becomes `OK` from load-time evidence alone. That is the "existence-of-a-fast-path" evidence the header (lines 9–12) says can never establish "used".

### 6. "frames" and the ratio are counts of matching lines, not samples

- **What:** `grep -c` counts text lines, but the output labels them frames and computes a GPU:CPU time ratio from them.
- **Where:**
  - lines 198–199 (above)
  - line 205: `printf '  GPU path taken: gpu_frames=%s cpu_frames=%s  ratio=%s\n' "$GPU_N" "$CPU_N" \`
  - line 206: `"$(awk -v g="$GPU_N" -v c="$CPU_N" 'BEGIN{ if(c==0){print "all-GPU"} else printf "%.2f:1", g/c }')"`
- **Why it is wrong:** In a `sample` call tree, each line carries its own sample count, and a symbol appears once per distinct call path. Consider a hot GPU path with 4,000 samples on one line versus a cold CPU symbol appearing on 10 lines with 1 sample each. That reports `0.10:1`, inverting the profile the axis exists to measure.

### 7. `IFS=$'\t'` still collapses empty fields

- **What:** Tab is an IFS whitespace character, so consecutive tabs collapse and empty fields are dropped. This is exactly the column shift the comment says the explicit split prevents.
- **Where:** line 185: `IFS=$'\t' read -r cpu mem th ports win off mpx <<<"$row"`
- **Why it is wrong:** Any empty field shifts every later column left. Examples: a census row whose column 3, 5 or 7 is empty, or a short `top` line leaving `th`/`ports` empty. Then `ports` would be printed as `th`, windows as ports, and so on. This is the "misattribute ports to threads" case described at lines 181–182.

### 8. Per-pane normalisation turns NA into a measured 0

- **What:** The per-pane block divides raw fields without checking for NA, so a missing reading prints as a real zero.
- **Where:**
  - line 236: `awk -v p="$PANES" -v r="$T0_APP" 'BEGIN{ split(r,f,"\t");`
  - lines 237–240: e.g. `printf "    threads/pane   %.2f\n", f[3]/p;`
- **Why it is wrong:** When the T0 reading failed (all `NA`), awk evaluates `"NA"/p` as 0 and prints `threads/pane 0.00`, `MB/pane 0.0`, and so on. That is a "measured zero" indistinguishable from real data, which is the specific failure the header's verdict-token section exists to prevent.

### 9. An option given without a value loops forever

- **What:** `shift 2` fails without shifting when only one argument remains, so the `while` loop never advances.
- **Where:** lines 55–59, e.g. `--app)         APP="${2:-}"; shift 2 ;;` and `--out)         OUT="${2:-}"; shift 2 ;;`
- **Why it is wrong:** Take `scripts/terminal-bench.sh --app iTerm2 --out` (or any value-taking flag as the last argument). Bash's `shift 2` with `$#=1` returns an error and leaves `$1` unchanged. The loop re-reads the same flag forever and the script hangs. The `${2:-…}` defaults show the author intended this case to be handled.

### 10. Aliases accepted by the process table fall through to the generic GPU discriminator

- **What:** `iTerm` and `kitty.app` are accepted for process lookup but not matched by the GPU-pattern table, so they get the generic patterns instead of the app-specific ones.
- **Where:**
  - line 100: `iTerm2|iTerm)    PROC_NAMES="iTerm2";                       CENSUS_OWNER="iTerm2" ;;` vs line 135: `iTerm2)            GPU_RE='iTermMetalDriver';        CPU_RE='iTermTextDrawingHelper' ;;`
  - line 99: `kitty|kitty.app) …` vs line 138: `kitty)             GPU_RE=…`
- **Why it is wrong:** With `--app iTerm`, the same process is profiled with `Metal|AGX|IOGPU|…` / `CoreText|CGContext|CGSBlend` instead of `iTermMetalDriver` / `iTermTextDrawingHelper`. Its ratio is then not comparable to a `--app iTerm2` row of the same app, and it is exposed to defect 5.

### 11. Alacritty is missing from the process/owner name table

- **What:** Alacritty is listed as supported in the header and the GPU table, but has no entry in the process/owner table, so it relies on the "names are equal" assumption the comment at lines 92–95 rejects.
- **Where:** line 101: `*)               PROC_NAMES="$APP";                         CENSUS_OWNER="$APP" ;;`
- **Why it is wrong:** Alacritty's executable is lowercase `alacritty`, while its window owner is `Alacritty`. With `--app Alacritty`, neither `pgrep -x` nor the ps-basename match finds the process, so the result is NO-DATA. With `--app alacritty`, the census is asked for owner `alacritty` and (if it matches case-sensitively) every window column comes back NA.

### 12. `top` columns are read by whitespace position, which breaks when the command name has a space

- **What:** CPU, memory, threads and ports are taken as fields 3–6, which assumes the COMMAND column contains no spaces.
- **Where:** lines 151–154, e.g. `cpu="$(awk '{print $3}' <<<"$line")"`, `ports="$(awk '{print $6}' <<<"$line" | tr -d '+-')"`
- **Why it is wrong:** For any app reaching the generic `*)` branch whose process name contains a space, every column shifts right. Part of the name lands in `cpu`, the CPU value lands in `mem`, and so on. Those wrong values then feed the drift and per-pane arithmetic.

### 13. `--help` truncates the verdict-token section

- **What:** The help text prints lines 1–45, but the header runs to line 46.
- **Where:** line 60: `-h|--help)     sed -n '1,45p' "$0"; exit 0 ;;`
- **Why it is wrong:** Line 46 (`#   verdict=NO-DATA   the app is not running, or top returned nothing  (exit 3)`) is never printed. `--help` therefore omits the NO-DATA token and the exit-3 contract that a consumer needs to parse results.
