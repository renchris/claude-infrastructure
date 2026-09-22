# Review of `scripts/terminal-bench.sh`: 7 defects found

**1. The run reports `verdict=OK` even when the window census or the T1 reading is missing.**
- **Where:** line near the end of the drift block, `  VERDICT="OK"`
- **Why it is wrong:** The header says PARTIAL is required when the window census is missing. `VERDICT` is set to OK whenever `INTERVAL > 0`, without checking any of these:
  - `CENSUS_OK`
  - whether `win`/`off` are `NA`
  - whether the T1 `reading` failed (returned all-`NA`)

  So a run where swiftc failed, or where top returned nothing at T1, is still filed as a full comparable row.

**2. The JSONL row is written before the GPU downgrade, so the file can say OK while stdout says PARTIAL.**
- **Where:** `[ "$GPU_VERDICT" = OK ] || VERDICT="PARTIAL"`, which runs after the `>> "$OUT"` append.
- **Why it is wrong:** Take a run with `--interval 300` where `sample` fails or matches 0:0. It appends `"verdict":"OK"` to the results file, then prints `verdict=PARTIAL`. The persisted record overstates the result.

**3. The documented "top returned nothing → NO-DATA (exit 3)" path does not exist.**
- **Where:** `T0_APP="$(reading "$PID" "$CENSUS_OWNER")"; T0_WS="$(reading "${WS_PID:-0}" 'Window Server')"`
- **Why it is wrong:** The `return 1` from `reading` is discarded inside the command substitution. If top yields nothing (or times out), the script continues with an all-`NA` row. It can still end in PARTIAL or OK (see #1), and it exits 0 instead of 3.

**4. A missing WindowServer pid falls back to pid 0, which measures kernel_task.**
- **Where:** `reading "${WS_PID:-0}" 'Window Server'` (both at T0 and at T1)
- **Why it is wrong:** If `pgrep -x WindowServer` finds nothing, `top -pid 0` reports kernel_task. The script prints those numbers labelled "WS", so kernel_task's cpu, memory and ports are misattributed to WindowServer.

**5. The GPU discriminator counts the Binary Images / library listing, not just stack frames.**
- **Where:** `GPU_N="$(grep -cE "$GPU_RE" "$SAMPLE_F" || true)"`
- **Why it is wrong:** `sample` output includes a Binary Images section listing loaded frameworks, such as `Metal.framework`, `AGXMetal…`, `CoreText`, and `OpenGL`. With the broad regexes (`Metal`, `AGX`, `CGL`, `OpenGL`, `CoreText`), any app that merely loads these frameworks gets non-zero counts, and `GPU_VERDICT=OK`. This is exactly the "loaded driver" existence evidence that the header says cannot establish "used". The ratio is contaminated the same way.

**6. `--app iTerm` gets the generic GPU regex, not the iTerm2 discriminator.**
- **Where:** `  iTerm2)            GPU_RE='iTermMetalDriver';        CPU_RE='iTermTextDrawingHelper' ;;`
- **Why it is wrong:** The process table accepts `iTerm2|iTerm`, but the GPU table only matches `iTerm2`. With `--app iTerm` the same app is profiled using the weak generic pattern. That makes its GPU numbers non-comparable with an `--app iTerm2` run.

**7. The per-pane figures silently turn `NA` into 0.**
- **Where:** `awk -v p="$PANES" -v r="$T0_APP" 'BEGIN{ split(r,f,"\t");`
- **Why it is wrong:** When T0 failed or a field is `NA`, awk evaluates `"NA"/p` as 0. The script then prints `threads/pane 0.00`, `MB/pane 0.0` and so on as if they were measured values. This is the "measured zero vs. instrument did not run" confusion that the header says it forbids.
