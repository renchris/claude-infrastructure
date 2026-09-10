Reviewing the script text only, as instructed. Findings below.

**1. JSONL row records the verdict before the GPU downgrade is applied.**
Where: lines
```bash
    "$(tr '\t' ',' <<<"$T0_APP")" "$GPU_N" "$CPU_N" "$VERDICT" >> "$OUT"
...
[ "$GPU_VERDICT" = OK ] || VERDICT="PARTIAL"
```
Why: with `--interval >0` and a GPU profile that resolved to NO-DATA, the `--out` append writes `"verdict":"OK"` while the last stdout line says `verdict=PARTIAL`. The header defines OK as requiring the GPU profile, and the JSONL is the consumer-facing record, so an incomparable row is filed as full.

**2. A missing window census never downgrades the verdict.**
Where:
```bash
[ -x "$CENSUS_BIN" ] || CENSUS_OK=0
...
  VERDICT="OK"
```
Why: the header says PARTIAL when the window census is missing, but `CENSUS_OK` is never consulted when setting `VERDICT`. If the census fails to build, window/offscreen/mpx are NA in both readings, drift prints NA for windows, and the run still reports OK. This is the exact "NA everywhere, exit 0" outcome the symlink-resolution comment says the script guards against.

**3. "Fail loud" on a missing census source only warns and continues.**
Where:
```bash
[ -f "$CENSUS_SRC" ] || echo "terminal-bench: ⚠ census source not found under REPO=$REPO" >&2
```
Why: when REPO resolves wrongly, the script prints a warning, then runs `swiftc` on a nonexistent file, reports "swiftc failed", and proceeds to a verdict of OK per defect 2. Nothing fails.

**4. A failed `top` reading is discarded and can still yield OK.**
Where:
```bash
  if [ -z "$line" ]; then printf 'NA\tNA\tNA\tNA\tNA\tNA\tNA\n'; return 1; fi
...
T0_APP="$(reading "$PID" "$CENSUS_OWNER")"; T0_WS="$(reading "${WS_PID:-0}" 'Window Server')"
```
Why: `reading` returns 1 when top prints nothing, but the exit status vanishes inside `$(...)` and is never checked. The header promises `verdict=NO-DATA` with exit 3 when top returns nothing. Instead, all-NA T0 and T1 rows produce NA drift lines, `VERDICT="OK"` is set unconditionally after the sleep, and the run exits 0.

**5. Per-pane normalisation turns NA into 0.00.**
Where:
```bash
    printf "    threads/pane   %.2f\n", f[3]/p;
```
Why: if the reading was NA (top failed), awk coerces "NA" to 0 and prints 0.00 threads/pane, 0.00 ports/pane, 0.0 MB/pane. A missing measurement is reported as a measured zero.

**6. GPU symbol counts include the loaded-library list, so "loaded" counts as "used".**
Where:
```bash
  GPU_N="$(grep -cE "$GPU_RE" "$SAMPLE_F" || true)"
```
Why: `sample -f` output ends with a Binary Images section listing every loaded framework and driver path. Regexes like `Metal`, `AGX`, `OpenGL`, `CoreText` match those path lines for any GUI process, regardless of what the call stacks contain. A process rendering entirely on the CPU still gets GPU_N > 0, the GPU verdict becomes OK, and the ratio is computed on inflated counts. This is the "capability-loaded is not capability-used" error the header says the script exists to avoid.

**7. GPU discriminator table does not cover the aliases the process table accepts.**
Where:
```bash
  iTerm2)            GPU_RE='iTermMetalDriver';        CPU_RE='iTermTextDrawingHelper' ;;
  kitty)             GPU_RE='OpenGL|CGL|AGX|gl[A-Z]';  CPU_RE='CoreText|CGContext' ;;
```
Why: `--app iTerm` and `--app kitty.app` resolve a PID via the first table but fall to the generic `*)` regex here, so the app-specific symbols are silently not used and the reported ratio is not comparable to a run invoked with `--app iTerm2` or `--app kitty`.

**8. If WindowServer's PID is not found, kernel_task is measured under the WS label.**
Where:
```bash
T0_WS="$(reading "$PID" "$CENSUS_OWNER")"; T0_WS="$(reading "${WS_PID:-0}" 'Window Server')"
```
(the relevant text is `"${WS_PID:-0}"`)
Why: the comment above documents that `pgrep` on this box drops some processes. If it drops WindowServer, `WS_PID` is empty, `top -pid 0` reports pid 0 (kernel_task), the grep on `^\s*0\s` matches it, and those numbers are printed as "T0 WS" with no indication of substitution.

**9. After a failed rebuild, the script says window columns will be NA but uses a stale binary anyway.**
Where:
```bash
  if ! run 300 swiftc -O "$CENSUS_SRC" -o "$CENSUS_BIN" 2>/dev/null; then CENSUS_OK=0; fi
```
Why: if an older `window-census` binary exists and the recompile fails, `CENSUS_OK=0` prints the "window columns report NA" warning, but `reading` only checks `-x` and still runs the old binary. The output contradicts the warning, and the numbers come from a tool version that no longer matches the source.
