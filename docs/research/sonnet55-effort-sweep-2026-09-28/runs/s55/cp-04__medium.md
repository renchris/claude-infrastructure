I found five defects.

**1. The verdict is `OK` whenever `--interval` is above 0, even if the readings failed or the window census is missing.**
- **Where:** line 232, `  VERDICT="OK"`. Line 252, `[ "$GPU_VERDICT" = OK ] || VERDICT="PARTIAL"`, only downgrades for the GPU profile.
- **Why it is wrong:** The header says `OK` requires both readings taken and says `PARTIAL` applies if drift or the window census is missing. It also says the run exits 3 with `NO-DATA` if top returns nothing. None of that is checked. If `top` returns nothing for the pid, `reading` emits all-NA and the script continues. If the census failed to build (`CENSUS_OK=0`), every window column is NA. In both cases, if the GPU profile resolves, it prints `verdict=OK` and exits 0. A consumer reads a full comparable row when the instrument did not run.

**2. The JSONL row records the verdict before the GPU downgrade, so the file can say `OK` while the console says `PARTIAL`.**
- **Where:** line 248, `    "$(tr '\t' ',' <<<"$T0_APP")" "$GPU_N" "$CPU_N" "$VERDICT" >> "$OUT"`. The downgrade is at line 252, `[ "$GPU_VERDICT" = OK ] || VERDICT="PARTIAL"`.
- **Why it is wrong:** When `--out` is given, `--interval` is above 0 and the GPU profile is NO-DATA, the appended record has `"verdict":"OK"` with `"gpu_frames":"NA"`. The final printed line then says `PARTIAL`. The persisted record therefore claims a complete row that the script itself judged incomplete.

**3. The per-pane normalisation turns NA into a measured zero.**
- **Where:** lines 239–242:
  - `    printf "    threads/pane   %.2f\n", f[3]/p;`
  - `    printf "    ports/pane     %.2f\n", f[4]/p;`
  - `    printf "    MB/pane        %.1f\n",  f[2]/p;`
  - `    printf "    cpu%%/pane      %.2f\n", f[1]/p }'`
- **Why it is wrong:** If the T0 reading failed, `T0_APP` is `NA` in every field. awk coerces the string `"NA"` to 0, so with `--panes 30` it prints `0.00` for threads, ports, MB and CPU per pane. That is a "measured zero", the failure the header says a consumer must be able to distinguish from "the instrument did not run".

**4. The GPU and CPU "frame" counts are every matching line in the whole `sample` output, including non-stack sections, so they can reflect loaded libraries rather than the path taken.**
- **Where:**
  - line 200, `  GPU_N="$(grep -cE "$GPU_RE" "$SAMPLE_F" || true)"`
  - line 201, `  CPU_N="$(grep -cE "$CPU_RE" "$SAMPLE_F" || true)"`
- **Why it is wrong:** `sample` output contains a "Binary Images" list and header lines as well as call-graph frames. Loose patterns such as `Metal`, `CoreText` and `gl[A-Z]` also match library names there. Any app that merely links Metal or CoreText gets nonzero counts, so `GPU_VERDICT` becomes `OK` and a ratio is printed. That is existence-of-a-library evidence of the kind the header says cannot establish "used". The counts are also not weighted by sample counts, so they are not time spent on either path.

**5. The drift rate is scaled by the nominal interval, not the actual elapsed time between the two readings.**
- **Where:** line 228, `      'BEGIN{ d=b-a; printf "    %-14s %+.0f over %ds  = %+.1f/hr\n", l, d, s, d*3600/s }'`. The `-v s="$INTERVAL"` is on line 227.
- **Why it is wrong:** T0 is taken at line 192. The `sample` run (about `SAMPLE_SECS` plus overhead) and the T0 window-server reading then happen before `sleep "$INTERVAL"`, and T1 is taken after that. The true gap between the app readings is therefore longer than `INTERVAL`. Dividing by `INTERVAL` overstates every per-hour drift figure, and the error grows as `--interval` shrinks.
