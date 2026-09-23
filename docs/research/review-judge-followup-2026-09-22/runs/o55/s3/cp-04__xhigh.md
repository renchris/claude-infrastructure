# Defects found in `scripts/terminal-bench.sh`

I found 16 defects. They are listed roughly from most to least severe.

---

### 1. The JSONL row records the verdict before the GPU downgrade is applied

**What:** The results file is written before the final GPU check can downgrade the verdict, so it can record `"verdict":"OK"` while stdout says `verdict=PARTIAL`.

**Where:**
- Line 247: `"$(tr '\t' ',' <<<"$T0_APP")" "$GPU_N" "$CPU_N" "$VERDICT" >> "$OUT"`
- Line 251: `[ "$GPU_VERDICT" = OK ] || VERDICT="PARTIAL"`

**Why it is wrong:** Take any run with `--interval > 0` where `sample` fails or matches nothing (`GPU_VERDICT=NO-DATA`).
- Line 231 has already set `VERDICT="OK"`.
- The JSONL row is appended with `OK`.
- Only after that does line 251 demote the verdict to `PARTIAL`.
- The filed row claims a "full comparable row" the run never produced.

---

### 2. "top returned nothing" never produces `NO-DATA` / exit 3

**What:** A failed `top` reading returns status 1, but no caller checks it, so the header's `NO-DATA (exit 3)` case for "top returned nothing" is never reached.

**Where:**
- Line 151: `if [ -z "$line" ]; then printf 'NA\tNA\tNA\tNA\tNA\tNA\tNA\n'; return 1; fi`
- Line 191: `T0_APP="$(reading "$PID" "$CENSUS_OWNER")"; T0_WS="$(reading "${WS_PID:-0}" 'Window Server')"`
- Line 218: `T1_APP="$(reading "$PID" "$CENSUS_OWNER")"; T1_WS="$(reading "${WS_PID:-0}" 'Window Server')"`
- Line 231: `VERDICT="OK"`

**Why it is wrong:** Suppose `top` yields no line for the pid at T0 or T1. Causes include a timeout, the process exiting mid-interval, or the pgrep/ps blind spot the file documents.
- The row becomes all `NA`.
- Execution continues.
- Line 231 unconditionally sets `OK`.
- The run exits 0 with `verdict=OK` (or `PARTIAL`), never `NO-DATA`.

---

### 3. A missing window census never downgrades the verdict

**What:** `CENSUS_OK` is only used to print a warning, so a run with no window census can still end `verdict=OK`. The header contract (line 44) says it must be `PARTIAL`.

**Where:**
- Line 180: `[ "$CENSUS_OK" = 1 ] || echo "  ⚠ window census unavailable (swiftc failed) — window columns report NA"`
- Line 231: `VERDICT="OK"`

**Why it is wrong:** The census can be unavailable in three ways:
- `swiftc` fails;
- the census source is not found (line 86 only warns);
- the census returns no row for the owner.

In all three, the `windows`/`offscreen` columns and their drift print `NA`, yet the verdict is `OK` and exit is 0. This is the "silently report NA for every window column, and still exit 0" class that lines 70–71 say the script guards against.

---

### 4. The GPU discriminators match the loaded-library list, so the 0:0 guard can never trigger

**What:** For every app except iTerm2, the discriminators match loaded-library entries in the `sample` output. The GPU verdict therefore always resolves to `OK`, and the counts include "library is loaded" lines.

**Where:**
- Line 199: `GPU_N="$(grep -cE "$GPU_RE" "$SAMPLE_F" || true)"`
- Line 200: `CPU_N="$(grep -cE "$CPU_RE" "$SAMPLE_F" || true)"`
- Line 203: `if [ "$GPU_N" -gt 0 ] || [ "$CPU_N" -gt 0 ]; then GPU_VERDICT="OK"; fi`

**Why it is wrong:**
- `grep` scans the whole `sample` file, including its "Binary Images" section.
- That section lists every loaded framework path: `CoreText.framework`, `Metal.framework`, the AGX driver bundle, `OpenGL.framework`.
- Every AppKit process loads CoreText, so `CPU_RE` (which contains `CoreText` for every non-iTerm2 app) is always ≥ 1. Line 203 is therefore always true, and the 0:0 guard (lines 201–202) is unreachable.
- `GPU_N` likewise counts "Metal/AGX is loaded" lines. That is the "loaded GPU driver" evidence the header (lines 10–12) says can never establish "used".

---

### 5. The GPU/CPU "frames" and ratio are line counts, not sample counts

**What:** `gpu_frames`, `cpu_frames` and the printed ratio count matching text lines, not samples.

**Where:**
- Lines 199–200 (quoted in defect 4)
- Line 207: `"$(awk -v g="$GPU_N" -v c="$CPU_N" 'BEGIN{ if(c==0){print "all-GPU"} else printf "%.2f:1", g/c }')"`

**Why it is wrong:**
- `sample` output is a call tree in which each node line carries its own sample count, plus a "top of stack" summary.
- `grep -c` counts distinct matching lines and ignores the per-line counts.
- A GPU path hit in thousands of samples through one call chain contributes a few lines.
- A rarely-hit CPU path spread over many call sites contributes many.
- The printed `N:1` ratio reads like the time-weighted CPU:GPU profile the header cites, but it measures stack-shape breadth, not time on each path.

---

### 6. `show` does not prevent the column shift it claims to prevent

**What:** Splitting with `IFS=$'\t'` does not preserve empty fields, so the column shift described in lines 182–183 still happens.

**Where:**
- Line 186: `IFS=$'\t' read -r cpu mem th ports win off mpx <<<"$row"`

**Why it is wrong:** Tab is an IFS-whitespace character in bash, so consecutive tabs collapse into one delimiter.

Example: a row `5.0\t800\t\t120\t40\t10\t2` (empty `th`) is read as:
- `th=120`
- `ports=40`
- `win=10`
- `off=2`
- `mpx=` (empty)

Ports are misattributed to threads, which is exactly the example the comment names. Empty fields occur when:
- the `top` line has fewer than 5 fields; or
- the census TSV row has fewer than 7 columns.

---

### 7. A missing WindowServer pid silently measures kernel_task instead

**What:** When WindowServer's pid is not found, the script measures pid 0 (`kernel_task`) and labels it `WS`.

**Where:**
- Line 129: `WS_PID="$(pgrep -x WindowServer | head -1 || true)"`
- Line 191: `T0_APP="$(reading "$PID" "$CENSUS_OWNER")"; T0_WS="$(reading "${WS_PID:-0}" 'Window Server')"`

**Why it is wrong:**
- `WS_PID` uses bare `pgrep`, with no `ps` fallback, although lines 109–115 document that `pgrep` drops processes on this box.
- When it comes back empty, `${WS_PID:-0}` passes pid 0.
- Pid 0 is `kernel_task`, which `top -pid 0` reports.
- So the "WS" row shows kernel_task's cpu/mem/threads/ports as WindowServer's, with no warning.

---

### 8. Drift per hour divides by the sleep time, not the real time between readings

**What:** The drift rate divides by `INTERVAL`, not by the time actually elapsed between the T0 and T1 app readings.

**Where:**
- Line 227: `'BEGIN{ d=b-a; printf "    %-14s %+.0f over %ds  = %+.1f/hr\n", l, d, s, d*3600/s }'`

**Why it is wrong:** Between `T0_APP` and `T1_APP` the script also runs:
- the T0 WindowServer reading (`top -l 2` plus census);
- `sample` for `SAMPLE_SECS`, plus symbolication;
- then `sleep "$INTERVAL"`.

The real gap is therefore always longer than `INTERVAL`, so the "/hr" leak rate and "over Ns" are overstated. For example, with `--interval 60 --sample-secs 30` the real gap is at least 90 s, overstating the rate by 50% or more.

---

### 9. Per-pane figures turn `NA` into zeros

**What:** The per-pane normalisation prints `NA` readings as numeric zeros.

**Where:**
- Line 237: `awk -v p="$PANES" -v r="$T0_APP" 'BEGIN{ split(r,f,"\t");`
- Line 238: `printf "    threads/pane   %.2f\n", f[3]/p;`

**Why it is wrong:** When the T0 `top` reading failed, every field is `"NA"`. In awk, `"NA"/p` evaluates to 0, so the output is `threads/pane 0.00`, `ports/pane 0.00`, and so on. This is a measured-looking zero for an instrument that did not run, the distinction the header (lines 41–42) says consumers must be able to make.

---

### 10. A stale census binary is used while the script says the columns are NA

**What:** After a failed compile, the script says the window columns report `NA`, but an old census binary still runs and fills them in.

**Where:**
- Line 163: `if [ -x "$CENSUS_BIN" ]; then`
- Line 177: `[ -x "$CENSUS_BIN" ] || CENSUS_OK=0`
- Line 180 (quoted in defect 3)

**Why it is wrong:**
- **Failed rebuild:** If the source is newer than an existing binary and `swiftc` fails (for example, an edit error), `CENSUS_OK=0` and the warning prints. But `reading()` checks `-x "$CENSUS_BIN"`, not `CENSUS_OK`, so the pre-edit binary runs and real-looking window counts are printed under a message saying they are `NA`.
- **Missing source:** If `CENSUS_SRC` is missing (line 86 warned), `-nt` is false. Any existing `$TMPDIR/window-census.$UID` then runs with `CENSUS_OK=1`, whatever its origin (for example, one built from another checkout).

---

### 11. Accepted app aliases get a different GPU discriminator

**What:** Some app names are accepted as aliases by the process-name table but fall through to the generic GPU discriminator.

**Where:**
- Line 101: `iTerm2|iTerm)    PROC_NAMES="iTerm2";                       CENSUS_OWNER="iTerm2" ;;`
- Line 136: `iTerm2)            GPU_RE='iTermMetalDriver';        CPU_RE='iTermTextDrawingHelper' ;;`
- The same mismatch exists between line 100 (`kitty|kitty.app`) and line 139 (`kitty)`).

**Why it is wrong:**
- `--app iTerm` or `--app kitty.app` finds the right process.
- It then gets the generic `Metal|AGX|…` / `CoreText|…` regexes.
- The same app is measured with a different GPU instrument depending on spelling, so its rows are not comparable. The generic set also always resolves `OK` (see defect 4).

---

### 12. Alacritty is missing from the process-name table

**What:** Alacritty appears in the header and the GPU table but not in the process/owner name table.

**Where:**
- Line 102: `*)               PROC_NAMES="$APP";                         CENSUS_OWNER="$APP" ;;`
- Compare line 140: `alacritty|Alacritty) GPU_RE='OpenGL|CGL|AGX|gl[A-Z]'; CPU_RE='CoreText|CGContext' ;;`

**Why it is wrong:** Alacritty's executable is `alacritty` (lowercase) but its window owner is `Alacritty`. Assuming the census matches owner names exactly (which is why the table exists), neither spelling works fully:
- `--app Alacritty` fails both `pgrep -x` and the ps-basename match, giving `NO-DATA` / exit 3.
- `--app alacritty` passes owner `alacritty` to the census, so the window columns are `NA`. By defect 3 the run still ends `verdict=OK`.

This is the WezTerm failure described in lines 93–96.

---

### 13. The "appended" message prints even if the write failed

**What:** The success message is printed without checking whether the append to the results file worked.

**Where:**
- Line 247 (quoted in defect 1)
- Line 248: `echo "  appended → $OUT"`

**Why it is wrong:** With no `set -e`, a failed `>> "$OUT"` only prints an error to stderr. Causes include a missing directory or a read-only path. The next line then reports `appended → $OUT`, so a failure is reported as a success.

---

### 14. "all-GPU" is inferred from a zero CPU count

**What:** A CPU count of zero is reported as the positive finding "all-GPU".

**Where:**
- Line 207 (quoted in defect 5)

**Why it is wrong:** The script's own rule (lines 201–202) says a zero count means the discriminator did not match, not that the path is absent. When `CPU_N=0` and `GPU_N>0`, the ratio prints `all-GPU` anyway. For example, with iTerm2, if `iTermTextDrawingHelper` is renamed or not symbolicated, the output claims all rendering is on the GPU, based only on a regex failing to match.

---

### 15. The GPU NO-DATA message states the wrong cause

**What:** The `NO-DATA` message blames the discriminator even when `sample` itself never ran.

**Where:**
- Line 198: `if run 120 sample "$PID" "$SAMPLE_SECS" -f "$SAMPLE_F" >/dev/null 2>&1 && [ -s "$SAMPLE_F" ]; then`
- Line 209: `printf '  GPU path taken: NO-DATA (discriminator matched no symbols; do NOT read as "no GPU")\n'`

**Why it is wrong:** If `sample` fails, times out, or writes an empty file, line 198's condition is false and line 209 says "discriminator matched no symbols". The instrument did not run at all, but the message attributes the result to a symbol mismatch.

---

### 16. `--help` cuts off the end of the verdict contract

**What:** `--help` stops at line 45, so the last two lines of the header are not shown.

**Where:**
- Line 61: `-h|--help)     sed -n '1,45p' "$0"; exit 0 ;;`

**Why it is wrong:** The header runs to line 47. Line 46 finishes the `PARTIAL` definition and line 47 defines `verdict=NO-DATA … (exit 3)`. `--help` omits both, including the NO-DATA token and its exit code, which consumers need to parse the last line.
