# Review: `scripts/terminal-bench.sh`

I found 20 defects. They are ordered roughly by severity.

---

**1. A missing window census never downgrades the verdict.**
- **Where:** line 251 `[ "$GPU_VERDICT" = OK ] || VERDICT="PARTIAL"`. The census is also only warned about at line 86 `[ -f "$CENSUS_SRC" ] || echo "terminal-bench: ⚠ census source not found under REPO=$REPO" >&2` and line 180 `[ "$CENSUS_OK" = 1 ] || echo "  ⚠ window census unavailable (swiftc failed) — window columns report NA"`.
- **Why:** The header (line 44) says a missing window census means PARTIAL. But `CENSUS_OK` and NA window columns never touch `VERDICT`. If swiftc is absent or fails, the source isn't found, or the owner name matches nothing, every window column is NA. With `--interval > 0` and a resolved GPU profile, the run still prints `verdict=OK` and exits 0. That is exactly the "silently report NA for every window column, and still exit 0" failure described at lines 70–71. The "fail loud" at line 86 is only a stderr line.

**2. A failed `top` reading never produces NO-DATA.**
- **Where:** line 151 `if [ -z "$line" ]; then printf 'NA\tNA\tNA\tNA\tNA\tNA\tNA\n'; return 1; fi` and line 191 `T0_APP="$(reading "$PID" "$CENSUS_OWNER")"; T0_WS="$(reading "${WS_PID:-0}" 'Window Server')"`.
- **Why:** The header (line 47) promises `verdict=NO-DATA` and exit 3 when "top returned nothing". But `reading`'s return status 1 is discarded by the assignment. If `top` yields no line for the pid (timeout, failure, or the process exiting), the run continues. With `--interval > 0` and a successful `sample`, it ends `verdict=OK` with exit 0 and a JSONL `"t0":"NA,NA,…"`.

**3. `VERDICT="OK"` is set unconditionally after the sleep.**
- **Where:** line 231 `VERDICT="OK"`.
- **Why:** "Both readings taken" (line 43) is never checked. Suppose the app quits during the interval, `top` fails at T1, or window fields are NA. Then `T1_APP` is all NA and every `drift` line prints NA. The verdict is still OK, so a run with no drift data is labeled as a full leak-capable row.

**4. The JSONL verdict is written before the GPU downgrade.**
- **Where:** line 247 `"$(tr '\t' ',' <<<"$T0_APP")" "$GPU_N" "$CPU_N" "$VERDICT" >> "$OUT"`, which runs before line 251 `[ "$GPU_VERDICT" = OK ] || VERDICT="PARTIAL"`.
- **Why:** Take `--interval > 0` with a GPU profile of NO-DATA. The results file records `"verdict":"OK"` while stdout prints `verdict=PARTIAL`. The persisted row claims more than the run established.

**5. The GPU/CPU regexes count loaded-library lines, so the GPU verdict and the 0:0 guard are vacuous.**
- **Where:** line 199 `GPU_N="$(grep -cE "$GPU_RE" "$SAMPLE_F" || true)"`, line 200 `CPU_N="$(grep -cE "$CPU_RE" "$SAMPLE_F" || true)"`, and line 203 `if [ "$GPU_N" -gt 0 ] || [ "$CPU_N" -gt 0 ]; then GPU_VERDICT="OK"; fi`. The regexes are on lines 137–141, e.g. line 141 `*)                 GPU_RE='Metal|AGX|IOGPU|wgpu|CGL|OpenGL'; CPU_RE='CoreText|CGContext|CGSBlend' ;;`.
- **Why:** The whole `sample` report is grepped. That includes the Binary Images list of every loaded image, plus `(in Metal)` / `(in CoreText)` library annotations. Any AppKit app that has Metal.framework, the AGX driver, IOGPU or CoreText loaded gets GPU_N ≥ 1 and CPU_N ≥ 1. This is true even if no rendering frame was sampled.
  - GPU_VERDICT becomes OK from "a loaded GPU driver", which the header (lines 10–12) says can never establish "used".
  - The NO-DATA branch at line 209 is effectively unreachable for every regex-based entry except iTerm2's.

**6. Tab-only `IFS` does not preserve empty fields, so the stated guard fails.**
- **Where:** line 186 `IFS=$'\t' read -r cpu mem th ports win off mpx <<<"$row"`.
- **Why:** Tab is an IFS-whitespace character, so bash collapses consecutive tabs and strips leading ones. Suppose an interior field is empty, e.g. `th` or `ports` when the `top` line has fewer columns, or an empty census column. Then later values shift left: ports show as `th=`, windows as `ports=`, and so on. That is exactly the misattribution the comment at lines 182–183 says this line prevents.

**7. If WindowServer's pid isn't found, the "WS" rows report kernel_task.**
- **Where:** line 129 `WS_PID="$(pgrep -x WindowServer | head -1 || true)"`, consumed as `reading "${WS_PID:-0}" 'Window Server'` on lines 191 and 218.
- **Why:** WindowServer has no ps fallback, even though the file documents `pgrep` dropping processes on this box. On failure the pid defaults to 0. `top -pid 0` returns kernel_task, and the grep `^…0[[:space:]]` matches it. kernel_task's cpu/mem/threads/ports are then printed as WindowServer's, mixed with real Window Server census counts, with no warning.

**8. A value-taking flag given last makes the script loop forever.**
- **Where:** lines 56–60, e.g. line 58 `--interval)    INTERVAL="${2:-180}"; shift 2 ;;`.
- **Why:** Consider `--app iTerm2 --out`, where the flag is the last argument. `shift 2` with `$# = 1` fails and shifts nothing in bash, and there is no `set -e`. The loop re-reads the same `$1` forever. It spins a CPU and never emits a verdict. The `${2:-…}` defaults show that a missing value was meant to be handled.

**9. Per-pane figures print 0 when the reading failed.**
- **Where:** line 237 `awk -v p="$PANES" -v r="$T0_APP" 'BEGIN{ split(r,f,"\t");` and lines 238–241.
- **Why:** If `T0_APP` is the NA row, awk evaluates `"NA"/p` as 0. It prints `threads/pane 0.00`, `MB/pane 0.0` and so on. This is the "measured zero" vs "instrument did not run" confusion the header (lines 41–42) says consumers must be able to tell apart.

**10. The printed gpu/cpu "frames" and ratio are matching-line counts, not samples.**
- **Where:** line 207 `"$(awk -v g="$GPU_N" -v c="$CPU_N" 'BEGIN{ if(c==0){print "all-GPU"} else printf "%.2f:1", g/c }')"`, fed by lines 199–200.
- **Why:** `grep -c` counts text lines. That means call-graph nodes, each carrying its own sample count, plus duplicates in the "Sort by top of stack" section and the library lines.
  - One hot GPU call chain with thousands of samples counts as a handful of lines.
  - A CPU path spread across many shallow chains with few samples counts as many lines.
  
  So the ratio can invert relative to actual time spent. It is not the CPU:GPU time profile the header relies on.

**11. The GPU table doesn't accept the aliases the process table accepts.**
- **Where:** line 136 `iTerm2)            GPU_RE='iTermMetalDriver';        CPU_RE='iTermTextDrawingHelper' ;;` versus line 101 `iTerm2|iTerm)    PROC_NAMES="iTerm2";                       CENSUS_OWNER="iTerm2" ;;`. Likewise `kitty.app` is accepted at line 100 but only `kitty)` appears at line 139.
- **Why:** `--app iTerm` or `--app kitty.app` finds the process but falls to the generic discriminator. Per item 5, that regex resolves OK from loaded-library lines. The incumbent row is then produced by a different, weaker instrument than `--app iTerm2`, and the two are not comparable.

**12. Alacritty, which the header lists, has no process/owner name mapping.**
- **Where:** lines 97–103; it falls through to line 102 `*)               PROC_NAMES="$APP";                         CENSUS_OWNER="$APP" ;;`.
- **Why:** Alacritty's executable is `alacritty` but its bundle/window-owner name is `Alacritty`.
  - `--app Alacritty` finds no process and returns NO-DATA.
  - `--app alacritty` finds the process but queries the census for owner `alacritty`, assuming exact matching. The window columns go NA, and per item 1 the verdict stays OK.
  
  This is the WezTerm class of failure described at lines 93–96. `--app wezterm-gui` has the same census-owner problem.

**13. Drift rates use the nominal interval, not the actual time between readings.**
- **Where:** line 226 `awk -v a="$a" -v b="$b" -v s="$INTERVAL" -v l="$label" \` and line 227 `'BEGIN{ d=b-a; printf "    %-14s %+.0f over %ds  = %+.1f/hr\n", l, d, s, d*3600/s }'`.
- **Why:** The time from `T0_APP` to `T1_APP` also includes:
  - the WindowServer `top -l 2` reading,
  - `sample` (`SAMPLE_SECS` plus symbolication),
  - census runs.
  
  That adds several to 15+ seconds. The per-hour rate is therefore overstated. At `--interval 30` the error is large, not marginal.

**14. Several CPU/GPU regexes fire on the wrong path.**
- **Where:** line 137 `ghostty|Ghostty)   GPU_RE='Metal|renderer.*[Mm]etal'; CPU_RE='CoreText|CGContext' ;;` and line 139 `kitty)             GPU_RE='OpenGL|CGL|AGX|gl[A-Z]';  CPU_RE='CoreText|CGContext' ;;`. Also `glyphcache` on line 138.
- **Why:** Ghostty, kitty and WezTerm rasterize glyphs for their GPU atlases via CoreText into CGBitmapContexts (and WezTerm's glyph cache). So GPU-path work is counted as "CPU path".
  - Separately, `CGL` also matches `CGLayer*` CoreGraphics symbols.
  - The result skews the ratio in both directions.

**15. The results row labeled OK carries none of the drift data.**
- **Where:** line 245 `printf '{"ts":"%s","app":"%s","pid":%s,"panes":%s,"interval":%s,"t0":"%s","gpu_frames":"%s","cpu_frames":"%s","verdict":"%s"}\n' \`.
- **Why:** The header says OK means "a full comparable row", and that drift is "the only reading that supports a leak verdict". Yet only T0 and the GPU counts are persisted. T1, the drift values and the WindowServer readings are lost, so no leak comparison can be made from the file.

**16. A stale census binary is used after a failed rebuild, contradicting the banner.**
- **Where:** line 163 `if [ -x "$CENSUS_BIN" ]; then`.
- **Why:** There are two cases:
  - The source is newer than the cached binary and `swiftc` fails. `CENSUS_OK=0` and the banner says "window columns report NA", but `reading` ignores `CENSUS_OK` and runs the outdated binary, reporting its numbers.
  - The source is missing, so `-nt` is false. Any old binary in `$TMPDIR` is then used silently.

**17. The "second sample" is not guaranteed.**
- **Where:** line 150 `| grep -E "^[[:space:]]*${pid}[[:space:]]" | tail -1)"`.
- **Why:** If only one matching line comes back, `tail -1` returns the first sample. That happens if the process disappears between samples or `top` is cut short. The comment at line 148 says the first sample is the lifetime average that must be discarded, and it is used silently here.

**18. The ps fallback breaks on executable paths containing spaces.**
- **Where:** line 121 `PID="$(ps -eo pid=,comm= | awk -v want="$_p" '{n=split($2,a,"/"); if (a[n]==want) {print $1; exit}}')"`.
- **Why:** `$2` is only the text up to the first space. For an app installed under a path with a space, the basename compared is a path fragment. The fallback then misses a running process and reports NO-DATA.

**19. Positional `top` parsing shifts when COMMAND contains a space.**
- **Where:** line 152 `cpu="$(awk '{print $3}' <<<"$line")"`, and similarly lines 153–155.
- **Why:** Take a generic `--app` whose `top` COMMAND has a space, e.g. "Some App". Then `$3` is the second word of the name, `mem` gets the CPU value, `th` gets the MEM value, and so on. Garbage values are reported as measurements.

**20. `--help` truncates the verdict documentation.**
- **Where:** line 61 `-h|--help)     sed -n '1,45p' "$0"; exit 0 ;;`.
- **Why:** The header runs to line 47. Help output drops lines 46–47, which include the `verdict=NO-DATA` / exit 3 definition a consumer needs in order to parse results.
