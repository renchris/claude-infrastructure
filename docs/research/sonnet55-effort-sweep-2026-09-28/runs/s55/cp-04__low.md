I found six defects. I had no tools available, so I counted line numbers by hand and they may be off by a line or two.

**1. A missing value after an option makes the argument loop spin forever.**
- **Where:** lines 56–60, e.g. `--app)         APP="${2:-}"; shift 2 ;;` (the same `shift 2` is in `--panes`, `--interval`, `--sample-secs` and `--out`).
- **Why it is wrong:** run `terminal-bench.sh --app` or `... --interval` with the value omitted, so the option is the last argument. `$#` is 1, so `shift 2` fails and shifts nothing, and `$1` is unchanged. The `while [ $# -gt 0 ]` loop then repeats the same case forever, and the script hangs instead of reporting a usage error.

**2. The GPU/CPU frame counts include the sample's loaded-library list, so they measure what is loaded rather than what is used.**
- **Where:** lines 201–202: `GPU_N="$(grep -cE "$GPU_RE" "$SAMPLE_F" || true)"` and `CPU_N="$(grep -cE "$CPU_RE" "$SAMPLE_F" || true)"`.
- **Why it is wrong:** the whole `sample` output file is grepped, not only the call-graph section. That file ends with a "Binary Images" list of every loaded library. Patterns like `Metal`, `CoreText`, `CGContext`, `AGX` and `OpenGL` match those library lines even if the renderer never ran.
  - A process that merely has Metal loaded scores `GPU_N>0`, and the run reports `GPU_VERDICT="OK"`.
  - The header comment says a loaded driver can only refute "absent", never establish "used".

**3. Aliases the app-name table accepts get the wrong GPU discriminator.**
- **Where:** line 138, `iTerm2)            GPU_RE='iTermMetalDriver';        CPU_RE='iTermTextDrawingHelper' ;;` (the later case arms have the same gap: `kitty)` at 141, and `ghostty|Ghostty)` at 139 versus `wezterm*|WezTerm*)` at 140).
- **Why it is wrong:** the process table at lines 97–103 accepts `iTerm` and `kitty.app`, but the GPU case matches only `iTerm2` and `kitty`. With `--app iTerm` or `--app kitty.app`, the process is found but the generic regex `Metal|AGX|...|CoreText...` is used. That is the weak discriminator, and it matches library lines (defect 2). The run can report `verdict=OK` on a row that is not comparable to the `iTerm2` or `kitty` rows.

**4. `verdict=OK` is assigned whenever the interval is positive, regardless of whether the drift readings exist.**
- **Where:** line 233, `  VERDICT="OK"`.
- **Why it is wrong:** the header says OK requires both readings and says PARTIAL applies when drift or the window census is missing.
  - If swiftc failed, the window columns are NA, and `drift 5` and `drift 6` print NA.
  - If the T1 `top` reading failed, every drift line is NA.
  - In both cases the verdict is still OK as long as the GPU profile resolved.
  - A T0 app reading that failed entirely (`top` returned nothing) also proceeds and can reach OK, instead of the documented NO-DATA and exit 3.

**5. The JSONL row records the verdict before the GPU downgrade, so it disagrees with the printed verdict.**
- **Where:** line 247 writes `"$VERDICT"` into the row, but the downgrade comes afterwards at line 253: `[ "$GPU_VERDICT" = OK ] || VERDICT="PARTIAL"`.
- **Why it is wrong:** when the GPU profile is NO-DATA and drift succeeded, `VERDICT` is still `OK` at append time. The file gets `"verdict":"OK"` while stdout prints `verdict=PARTIAL`. A consumer of the JSONL sees an incomplete row as a full comparable one, which is the failure the header says the tokens exist to prevent.

**6. Per-pane figures turn a failed reading into zeros.**
- **Where:** lines 239–243: `awk -v p="$PANES" -v r="$T0_APP" 'BEGIN{ split(r,f,"\t");` followed by `printf "    threads/pane   %.2f\n", f[3]/p;`.
- **Why it is wrong:** if the T0 reading failed, `T0_APP` is `NA<TAB>NA...`. awk coerces the string `"NA"` to 0, so the script prints `threads/pane 0.00`, `ports/pane 0.00`, `MB/pane 0.0` and `cpu%/pane 0.00`. A failed measurement is reported as a measured zero, which the header explicitly says a consumer must be able to distinguish.
