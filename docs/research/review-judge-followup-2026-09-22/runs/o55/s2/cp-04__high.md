# Review of `scripts/terminal-bench.sh`

I found 10 defects.

---

### 1. The JSONL row is written before the GPU downgrade

**What:** The results file records the verdict before the GPU check can downgrade it, so the file can say `OK` while stdout says `PARTIAL`.

**Where:** Lines 246 and 250:
- `    "$(tr '\t' ',' <<<"$T0_APP")" "$GPU_N" "$CPU_N" "$VERDICT" >> "$OUT"`
- `[ "$GPU_VERDICT" = OK ] || VERDICT="PARTIAL"`

**Why it is wrong:** Take a run with `--interval 300 --out f.jsonl` where `sample` fails or matches nothing (`GPU_VERDICT=NO-DATA`). Line 230 sets `VERDICT="OK"`, and line 246 appends `"verdict":"OK"`. Only afterwards does line 250 downgrade it to `PARTIAL`. The machine-readable record claims a full comparable row with no GPU profile behind it.

### 2. `OK` is issued no matter what the T1 readings and census returned

**What:** `VERDICT="OK"` is set unconditionally once the sleep finishes. It ignores whether the T1 readings succeeded and whether the window census ran.

**Where:** Line 230: `  VERDICT="OK"`. See also line 179: `[ "$CENSUS_OK" = 1 ] || echo "  ⚠ window census unavailable (swiftc failed) — window columns report NA"`

**Why it is wrong:** The header says `PARTIAL` must be emitted when drift or the window census is missing. Two cases break this:
- If the app exits during the interval, or `top` returns nothing at T1, `T1_APP` is all `NA`. Every drift line prints `NA`, yet the verdict is still `OK`.
- If `swiftc` failed, or the census returned no row, every window column is `NA`, yet the verdict is still `OK`.

The script then exits 0 with `verdict=OK`. That is the exact "NA-everywhere, still exit 0" outcome the comment block at lines 66–73 says it prevents.

### 3. "top returned nothing" never produces NO-DATA

**What:** The documented NO-DATA path for an empty `top` result is never taken.

**Where:** Line 150: `  if [ -z "$line" ]; then printf 'NA\tNA\tNA\tNA\tNA\tNA\tNA\n'; return 1; fi`. See also line 190: `T0_APP="$(reading "$PID" "$CENSUS_OWNER")"; ...`

**Why it is wrong:** The `return 1` is discarded inside the command substitution, and nothing checks for an all-`NA` row. When `top` yields no line (timeout, pid gone, or a parse miss), the script continues instead of printing `verdict=NO-DATA` and exiting 3. With an interval it ends as `OK` (see defect 2). With an interval and a successful GPU sample, a run with zero metrics is reported as a full result.

### 4. A missing WindowServer pid silently measures kernel_task

**What:** If WindowServer's pid is not found, the WS readings are taken from pid 0 (kernel_task) and still labelled as WindowServer.

**Where:** Line 190: `T0_APP="$(reading "$PID" "$CENSUS_OWNER")"; T0_WS="$(reading "${WS_PID:-0}" 'Window Server')"`. The same happens at line 217.

**Why it is wrong:** The script itself documents that `pgrep` drops some processes on this box (lines 108–111). If `pgrep -x WindowServer` returns nothing, then `top -l 2 -pid 0` reports kernel_task. The grep at line 149 matches its `0 ...` line, and the kernel's cpu, mem, threads and ports are printed as `WS`. Those figures are then read against the WindowServer-saturation hypothesis.

### 5. The GPU discriminators match the "Binary Images" section, so the 0:0 guard is vacuous

**What:** The GPU and CPU patterns for most apps match framework paths in `sample`'s Binary Images list, not just symbols on the call path.

**Where:**
- Line 136: `  ghostty|Ghostty)   GPU_RE='Metal|renderer.*[Mm]etal'; CPU_RE='CoreText|CGContext' ;;`
- Line 140: `  *)                 GPU_RE='Metal|AGX|IOGPU|wgpu|CGL|OpenGL'; CPU_RE='CoreText|CGContext|CGSBlend' ;;`
- The same issue applies to lines 137–139.
- Line 202: `  if [ "$GPU_N" -gt 0 ] || [ "$CPU_N" -gt 0 ]; then GPU_VERDICT="OK"; fi`

**Why it is wrong:** `sample` output ends with a list of every loaded image, including `/System/Library/Frameworks/CoreText.framework`, `Metal.framework`, `AGXMetal…` and `IOGPU.framework`. `grep -c` counts those lines. For any GUI app, both `GPU_N` and `CPU_N` are therefore at least 1, so the "0:0 means the discriminator didn't match" guard can never fire.

The GPU count also includes "the Metal driver is loaded", which the header says can only refute "absent" and never establish "used". The script prints a `GPU path taken` ratio and `GPU_VERDICT=OK` based on that existence evidence.

### 6. `--app iTerm` (and `kitty.app`) gets the generic discriminator

**What:** The GPU discriminator table does not accept the same aliases as the process table.

**Where:**
- Line 100: `  iTerm2|iTerm)    PROC_NAMES="iTerm2";                       CENSUS_OWNER="iTerm2" ;;`
- Line 135: `  iTerm2)            GPU_RE='iTermMetalDriver';        CPU_RE='iTermTextDrawingHelper' ;;`

**Why it is wrong:** With `--app iTerm`, the pid resolves to iTerm2, but `GPU_RE`/`CPU_RE` fall through to the generic `Metal|AGX|…` / `CoreText|…` patterns. The incumbent's row then uses a different, weaker instrument than a `--app iTerm2` row, and the two are not comparable. `--app kitty.app` has the same problem (line 99 vs line 138).

### 7. `show` does not stop column shifting on empty fields

**What:** The comment says splitting on tab prevents columns from shifting, but tab is an IFS whitespace character, so `read` still collapses consecutive tabs.

**Where:** Line 185: `  IFS=$'\t' read -r cpu mem th ports win off mpx <<<"$row"`

**Why it is wrong:** An empty field produces two adjacent tabs, for example an empty `cut -f3` from a short census row, or an empty `awk '{print $3}'`. `read` treats those as one delimiter, so every later value moves one column left. Ports get printed as threads, and so on — the exact misattribution the comment at lines 181–182 claims to prevent. Meanwhile `drift` uses `cut -f`, which does not collapse, so the displayed row and the drift arithmetic disagree.

### 8. Per-pane figures turn NA into 0

**What:** Per-pane normalisation does arithmetic on `NA` fields.

**Where:** Lines 236–240, e.g. `    printf "    threads/pane   %.2f\n", f[3]/p;`

**Why it is wrong:** When the T0 reading failed (`T0_APP` is all `NA`), awk evaluates `"NA"/p` as 0. It prints `threads/pane 0.00`, `ports/pane 0.00`, `MB/pane 0.0` and `cpu%/pane 0.00`. That makes "the instrument did not run" look like "measured zero", which the header explicitly forbids.

### 9. A stale census binary is used while the script says the census is unavailable

**What:** If recompiling fails but an older `$CENSUS_BIN` exists, the script prints that window columns will be NA, then populates them from the stale binary anyway.

**Where:**
- Line 174: `  if ! run 300 swiftc -O "$CENSUS_SRC" -o "$CENSUS_BIN" 2>/dev/null; then CENSUS_OK=0; fi`
- Line 162: `  if [ -x "$CENSUS_BIN" ]; then`

**Why it is wrong:** `reading()` checks only `-x "$CENSUS_BIN"`, never `CENSUS_OK`. When the source is newer but fails to compile, the output says "window columns report NA" while the columns contain numbers from an outdated census build.

The shared path `${TMPDIR}/window-census.$(id -u)` makes this worse. When `CENSUS_SRC` is missing (line 85 only warns), `-nt` is false, and a binary built from some other checkout is used without comment.

### 10. The `top` line is parsed with whitespace fields, but `command` can contain spaces

**What:** The cpu, mem, threads and ports columns are taken by whitespace position after a free-text `command` column.

**Where:** Line 151: `  cpu="$(awk '{print $3}' <<<"$line")"`. Lines 152–154 do the same.

**Why it is wrong:** For any process whose `top` COMMAND contains a space (possible via the `*)` fallback with an arbitrary `--app`), `$3` is part of the name. The mem, threads and ports values are shifted into the wrong fields and misreported. The mem normaliser at line 156 then turns a non-numeric token into `0`.
