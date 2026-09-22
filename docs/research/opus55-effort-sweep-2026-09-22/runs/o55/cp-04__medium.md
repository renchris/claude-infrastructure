I found 12 defects in `scripts/terminal-bench.sh`, listed from most to least serious.

---

**1. The JSONL row is written before the verdict is downgraded, so the file and the terminal disagree.**
- **Where:** lines 247–249 and 253
  - `"$(tr '\t' ',' <<<"$T0_APP")" "$GPU_N" "$CPU_N" "$VERDICT" >> "$OUT"`
  - `[ "$GPU_VERDICT" = OK ] || VERDICT="PARTIAL"`
- **Why it is wrong:** Take a run with `--interval 300` where `sample` fails or matches nothing. `VERDICT` is still `OK` when the row is appended, so the file records `"verdict":"OK"`. Only after that is it changed to `PARTIAL`, and stdout prints `verdict=PARTIAL`. The persisted row then claims a full, comparable result that the run itself rejected.

**2. A missing window census never downgrades the verdict, even though the header says it must.**
- **Where:** line 233, `VERDICT="OK"`, together with line 253 (the only downgrade, which checks the GPU alone).
- **Why it is wrong:** The header defines `PARTIAL` as missing any of {drift, GPU profile, window census}. Suppose `swiftc` fails or `CENSUS_SRC` is not found (`CENSUS_OK=0`, every window column `NA`). The run still ends with `verdict=OK` and exit 0. This is exactly the "silently NA every window column and still exit 0" class the symlink comment says it guards against. The line-128 check (`[ -f "$CENSUS_SRC" ] || echo …`) only warns and does not fail.

**3. A failed `top` reading never produces NO-DATA, and failed readings still yield OK.**
- **Where:** lines 208 and 219, where `reading`'s `return 1` is discarded:
  - `T0_APP="$(reading "$PID" "$CENSUS_OWNER")"; T0_WS="$(reading "${WS_PID:-0}" 'Window Server')"`
  - `T1_APP="$(reading "$PID" "$CENSUS_OWNER")"; ...`
- **Why it is wrong:** The header promises `verdict=NO-DATA (exit 3)` when "top returned nothing". Suppose `top` times out, or the app exits during the hold. Every column becomes `NA`, but nothing checks this. Drift prints `NA` for every axis, `VERDICT="OK"` is still set, and the result is `verdict=OK` (or `PARTIAL` with exit 0) instead of NO-DATA.

**4. The GPU discriminator counts the "Binary Images" section of the `sample` report, so it measures loaded frameworks rather than the path taken.**
- **Where:** lines 212–213:
  - `GPU_N="$(grep -cE "$GPU_RE" "$SAMPLE_F" || true)"`
  - `CPU_N="$(grep -cE "$CPU_RE" "$SAMPLE_F" || true)"`
- **Why it is wrong:** `sample` output ends with a list of every loaded image. That list includes lines for `Metal.framework`, `CoreText.framework`, `OpenGL.framework`, `AGX…`, `IOGPU` and so on. For any app that merely links these (for example Ghostty `'Metal|…'`, WezTerm, kitty, or the generic fallback), both counts are non-zero even if no rendering frame was ever sampled.
  - The 0:0 → NO-DATA guard therefore essentially never fires.
  - The ratio is inflated by "existence" evidence, which is precisely what the header says can never establish "used".
  - `grep -c` also counts call-graph lines, not samples.

**5. An empty `WS_PID` falls back to pid 0, so kernel_task is reported as WindowServer.**
- **Where:** line 208 (and line 219), `T0_WS="$(reading "${WS_PID:-0}" 'Window Server')"`
- **Why it is wrong:** If `pgrep -x WindowServer` returns nothing, `top -pid 0` is run. The grep `^[[:space:]]*0[[:space:]]` then matches kernel_task's row. That process's CPU, memory, threads and ports are printed under the `WS` label as a valid reading, with no NA.

**6. Per-pane figures turn NA readings into measured zeros.**
- **Where:** lines 238–242, for example `printf "    threads/pane   %.2f\n", f[3]/p;`
- **Why it is wrong:** If the T0 reading is `NA`, awk coerces `"NA"` to 0 and prints `threads/pane 0.00`, `ports/pane 0.00` and so on. This is the "measured zero vs instrument did not run" confusion the header says consumers must be able to tell apart.

**7. `--app iTerm` gets the generic GPU discriminator, not iTerm2's.**
- **Where:** line 162, `iTerm2)            GPU_RE='iTermMetalDriver';        CPU_RE='iTermTextDrawingHelper' ;;`
- **Why it is wrong:** The process table on line 100 accepts `iTerm2|iTerm`, but the discriminator table matches only `iTerm2`. So `--app iTerm` finds the process but uses `'Metal|AGX|IOGPU|wgpu|CGL|OpenGL'`. That GPU row is not comparable with `--app iTerm2` runs of the same app.
  - The same mismatch exists for `kitty.app`, which is accepted on line 99 but not on line 165.

**8. Alacritty has a discriminator entry but no process-table entry.**
- **Where:** line 101, `*)               PROC_NAMES="$APP";                         CENSUS_OWNER="$APP" ;;`
- **Why it is wrong:** The discriminator table on line 166 accepts `Alacritty`, but the process table has no mapping for it. `--app Alacritty` therefore searches for a process named `Alacritty`, while the binary's name is `alacritty`. The run reports NO-DATA for an app that is running, which is the failure the WezTerm comment describes.

**9. Only the app's drift is computed; WindowServer's drift is never compared.**
- **Where:** line 232, `drift 2 "mem MB"; drift 4 "mach ports"; drift 5 "windows"; drift 6 "offscreen win"` (`drift` reads only `T0_APP`/`T1_APP`, lines 225–226).
- **Why it is wrong:** The header names WindowServer's unbounded mach-port growth as the freeze mechanism, and `T1_WS` is collected. Yet it is only displayed and never differenced.
  - A terminal that leaks WindowServer-side ports while its own ports stay flat still gets a clean drift section and `verdict=OK`.
  - The JSONL row stores no drift at all, only `t0` (lines 245–248).

**10. Column parsing breaks when the command name or executable path contains a space.**
- **Where:**
  - line 179, `cpu="$(awk '{print $3}' <<<"$line")"` (and lines 180–182)
  - line 145, `awk -v want="$_p" '{n=split($2,a,"/"); ...}'`
- **Why it is wrong:**
  - With the generic `*)` app path and a command such as "Some App", `$3` onward are shifted. Parts of the name are read as CPU and memory, and each metric lands in the wrong column.
  - Likewise, `$2` of `ps` comm truncates an executable path at its first space, so the fallback lookup fails.

**11. When only one `top` sample matches, the lifetime-average first sample is silently used.**
- **Where:** line 177, `| grep -E "^[[:space:]]*${pid}[[:space:]]" | tail -1)"`
- **Why it is wrong:** If the second sample lacks the pid (the process exited, or `top` was cut off by the 30 s timeout after the first sample), `tail -1` returns the first sample. That is the lifetime `%cpu` the comment says must be discarded, and it is reported as a valid reading.

**12. A stale census binary is used when the source is missing.**
- **Where:** line 196, `if [ ! -x "$CENSUS_BIN" ] || [ "$CENSUS_SRC" -nt "$CENSUS_BIN" ]; then`
- **Why it is wrong:** `CENSUS_BIN` is a shared per-uid file in `$TMPDIR`. If `CENSUS_SRC` does not exist (the mis-resolved-REPO case), `-nt` is false, so an old binary left by some other checkout or version runs unchecked. Its column layout (`cut -f3/-f5/-f7`) may not match what this script expects.
