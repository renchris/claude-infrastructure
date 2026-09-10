Reviewing `scripts/terminal-bench.sh` from the brief text only.

## Defects

**1. The JSONL row records verdict OK when the GPU profile failed, because the downgrade runs after the append.**

Where: line 247 and line 251
```
    "$(tr '\t' ',' <<<"$T0_APP")" "$GPU_N" "$CPU_N" "$VERDICT" >> "$OUT"
```
```
[ "$GPU_VERDICT" = OK ] || VERDICT="PARTIAL"
```
Why: with `--out` set, `--interval` greater than zero, and `sample` producing no matching symbols, `VERDICT` is still "OK" at line 247. The persisted row says OK while stdout prints PARTIAL. The bake-off consumer reads the file, not stdout, so the failure the header says must be distinguishable is filed as a full comparable row.

**2. The GPU symbol counts include the `sample` report's Binary Images and header lines, so a merely loaded GPU framework counts as a GPU frame.**

Where: lines 199 and 200
```
  GPU_N="$(grep -cE "$GPU_RE" "$SAMPLE_F" || true)"
  CPU_N="$(grep -cE "$CPU_RE" "$SAMPLE_F" || true)"
```
Why: `sample` output ends with a Binary Images section listing every loaded library by path, including Metal.framework, MetalPerformanceShaders, the AGX driver, OpenGL and CoreText. Every AppKit process loads several of these. For any app using a regex containing `Metal`, `AGX`, `OpenGL` or `CoreText` (all but iTerm2), a process that draws entirely on the CPU still yields a nonzero `GPU_N`, `GPU_VERDICT` becomes OK, and a ratio is printed. That is the loaded-driver-as-evidence error the header says the script exists to avoid.

**3. The counts are distinct output lines, not sample weights, so the printed ratio does not measure time on either path.**

Where: lines 199, 200 and 207
```
    "$(awk -v g="$GPU_N" -v c="$CPU_N" 'BEGIN{ if(c==0){print "all-GPU"} else printf "%.2f:1", g/c }')"
```
Why: `sample` prints each call-tree line once with its hit count as a prefix, then repeats symbols in the "Sort by top of stack" section. `grep -c` ignores the prefix and counts lines. A deep GPU call tree hit in one sample produces many matching lines, a shallow CPU path hit in every sample produces few. The ratio reflects tree shape and duplication, not which path the process spent its time on.

**4. Window-census unavailability and all-NA drift never downgrade the verdict, so a run with no leak data is filed as OK.**

Where: line 231, with lines 180 and 86
```
  VERDICT="OK"
```
```
[ "$CENSUS_OK" = 1 ] || echo "  ⚠ window census unavailable (swiftc failed) — window columns report NA"
```
Why: the header defines PARTIAL as any of drift, GPU profile, or window census missing. `VERDICT` is set to OK on interval alone. When the census binary is missing (the symlink-root failure described at lines 68 to 72), or the app dies during the hold so T1 is all NA, every drift line prints NA and the verdict is still OK. Line 86 says "fail loud" but only warns and continues to that OK, which is the exit-0 NA-everywhere outcome the comment says it prevents.

**5. "top returned nothing" does not produce NO-DATA; the NA row flows through as zeros and an OK verdict.**

Where: line 151, line 191, and lines 238 to 241
```
  if [ -z "$line" ]; then printf 'NA\tNA\tNA\tNA\tNA\tNA\tNA\n'; return 1; fi
```
```
T0_APP="$(reading "$PID" "$CENSUS_OWNER")"; T0_WS="$(reading "${WS_PID:-0}" 'Window Server')"
```
```
    printf "    threads/pane   %.2f\n", f[3]/p;
```
Why: the return status of `reading` is discarded by the command substitution. If `top` emits nothing for the pid, the script continues, awk coerces "NA" to 0 and prints "threads/pane 0.00", "MB/pane 0.0" and "cpu%/pane 0.00" as if measured, and the JSONL row is appended with an NA t0 field. The header promises exit 3 with NO-DATA for exactly this case.

**6. The drift rate is normalised by the requested interval, not the elapsed time between the two readings.**

Where: lines 217 and 226 to 227
```
  sleep "$INTERVAL"
```
```
      'BEGIN{ d=b-a; printf "    %-14s %+.0f over %ds  = %+.1f/hr\n", l, d, s, d*3600/s }'
```
Why: between T0 and T1 the script also runs `sample` for `SAMPLE_SECS`, a second `top -l 2`, and the census. With `--interval 30 --sample-secs 30` the true gap is over twice the divisor, so the per-hour rate is overstated by more than 2x. The header calls this "a known interval apart"; it is not the interval used in the arithmetic.

**7. When WindowServer's pid is not found, the script measures kernel_task and labels it WindowServer.**

Where: lines 191 and 218
```
T0_APP="$(reading "$PID" "$CENSUS_OWNER")"; T0_WS="$(reading "${WS_PID:-0}" 'Window Server')"
```
Why: `pgrep -x WindowServer` can return empty (the file itself documents pgrep dropping 13 processes on this box). The fallback pid 0 is kernel_task, `top -pid 0` reports it, and the grep at line 150 matches its row. The WS lines then show kernel_task's cpu, memory, threads and ports under the "WS" label instead of NA.

**8. The accepted spelling of the app name selects a different GPU discriminator and census owner than the process table, so the same app yields non-comparable rows.**

Where: line 101 versus line 136, line 100 versus line 139, and line 140 with no matching entry at lines 97 to 102
```
  iTerm2|iTerm)    PROC_NAMES="iTerm2";                       CENSUS_OWNER="iTerm2" ;;
```
```
  iTerm2)            GPU_RE='iTermMetalDriver';        CPU_RE='iTermTextDrawingHelper' ;;
```
Why: `--app iTerm` finds the iTerm2 process but falls to the generic regexes, so gpu_frames and cpu_frames are counted against different patterns than `--app iTerm2` and the two rows cannot be compared. `--app kitty.app` likewise gets the generic discriminator. `--app alacritty` gets `CENSUS_OWNER="alacritty"` while the discriminator table expects the app, so the window census is queried with a lowercase owner the window list may not match.

**9. A stale census binary is used for readings while the script announces the census is unavailable.**

Where: lines 175, 177, 180 and 163
```
  if ! run 300 swiftc -O "$CENSUS_SRC" -o "$CENSUS_BIN" 2>/dev/null; then CENSUS_OK=0; fi
```
```
  if [ -x "$CENSUS_BIN" ]; then
```
Why: if the source is newer than an existing binary and the rebuild fails, `CENSUS_OK` is 0 and line 180 prints "window columns report NA", but `reading` only checks executability and runs the old binary. Window columns are populated from a build of superseded source while the log says they are NA.

**10. `--help` truncates the header before the NO-DATA verdict definition.**

Where: line 61
```
    -h|--help)     sed -n '1,45p' "$0"; exit 0 ;;
```
Why: the header comment runs through line 47. Lines 46 and 47, including the `verdict=NO-DATA` token and its exit code, are not printed. Help output omits one of the three verdict tokens a consumer must parse.

**11. The persisted row contains only the T0 reading, so an OK verdict on file has no drift data behind it.**

Where: lines 245 to 247
```
  printf '{"ts":"%s","app":"%s","pid":%s,"panes":%s,"interval":%s,"t0":"%s","gpu_frames":"%s","cpu_frames":"%s","verdict":"%s"}\n' \
```
Why: the header says drift is the only reading that supports a leak verdict and that OK means "a full comparable row". The row omits T1 and every drift figure, so two OK rows in the JSONL cannot be compared on the axis the freeze was root-caused to.
