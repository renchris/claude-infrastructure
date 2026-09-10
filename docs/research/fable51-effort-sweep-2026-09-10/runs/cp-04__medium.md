Reviewing the script text only, as instructed. Findings below, ordered roughly by severity.

## Defects

**1. The JSONL row is written before the GPU demotion, so the archive can record `verdict=OK` while stdout prints `PARTIAL`.**
- Where: lines 244-251
  ```
  "$(tr '\t' ',' <<<"$T0_APP")" "$GPU_N" "$CPU_N" "$VERDICT" >> "$OUT"
  ...
  [ "$GPU_VERDICT" = OK ] || VERDICT="PARTIAL"
  ```
- Why: with `--interval >0` and `--out` set, the drift block sets VERDICT to OK at line 231. The JSON line is appended at line 247 using that value. Only afterwards, at line 251, does a GPU profile of NO-DATA demote it. The persistent results file, which is what downstream comparison reads, files a row with `gpu_frames:"NA"` as a full comparable OK row. This is the exact claimed-outcome-vs-checked-outcome failure the header says the tokens exist to prevent.

**2. A failed `reading()` is ignored: an all-NA row still yields `verdict=OK` and exit 0, and the doc-promised NO-DATA/exit 3 for "top returned nothing" never happens.**
- Where: line 151 and line 191 (also 218)
  ```
  if [ -z "$line" ]; then printf 'NA\tNA\tNA\tNA\tNA\tNA\tNA\n'; return 1; fi
  T0_APP="$(reading "$PID" "$CENSUS_OWNER")"; T0_WS="$(reading "${WS_PID:-0}" 'Window Server')"
  ```
- Why: the return status of `reading` is swallowed by command substitution and never checked. If top times out or the pid vanishes between lookup and reading, T0_APP and T1_APP are NA rows. The drift block still runs and sets OK, the JSONL row records `"t0":"NA,NA,..."` with OK, and the script exits 0 instead of 3.

**3. Per-pane normalisation turns NA into real-looking zeros.**
- Where: lines 237-241
  ```
  awk -v p="$PANES" -v r="$T0_APP" 'BEGIN{ split(r,f,"\t");
  ```
- Why: awk coerces the string `NA` to 0, so after a failed T0 reading the script prints `threads/pane 0.00`, `ports/pane 0.00`, `MB/pane 0.0`, `cpu%/pane 0.00` as if measured. The drift function guards NA at line 225; this block does not.

**4. A missing or unbuildable window census never affects the verdict, despite the header saying PARTIAL covers a missing census and the comment saying it "fails loud".**
- Where: line 86, lines 173-180
  ```
  [ -f "$CENSUS_SRC" ] || echo "terminal-bench: ⚠ census source not found under REPO=$REPO" >&2
  [ "$CENSUS_OK" = 1 ] || echo "  ⚠ window census unavailable (swiftc failed) — window columns report NA"
  ```
- Why: CENSUS_OK is set but never read by the verdict logic. When the symlinked layout resolves to a root without tools/, or swiftc fails, every window column is NA, drift prints NA for windows and offscreen (the only leak instrument per the header), and the run still ends with `verdict=OK` and exit 0. That is precisely the NA-everywhere-exit-0 class the comment at lines 68-71 says the script must avoid.

**5. The GPU discriminator counts every matching line in the `sample` file, including the Binary Images section, so mere linkage of Metal/CoreText counts as a taken path.**
- Where: lines 199-203
  ```
  GPU_N="$(grep -cE "$GPU_RE" "$SAMPLE_F" || true)"
  CPU_N="$(grep -cE "$CPU_RE" "$SAMPLE_F" || true)"
  if [ "$GPU_N" -gt 0 ] || [ "$CPU_N" -gt 0 ]; then GPU_VERDICT="OK"; fi
  ```
- Why: `sample` output ends with a Binary Images list of every loaded dylib, which for any AppKit app includes paths such as Metal.framework, CoreText.framework, and AGX driver bundles. Regexes like `Metal`, `CoreText`, `AGX`, `OpenGL` (lines 137-141) match those path lines with zero call-stack frames. The 0:0 guard is defeated, GPU_VERDICT becomes OK, and the printed ratio is built from loaded-library evidence. That is the "capability-initialized-is-not-capability-used" error the header names as the one thing this script must not commit. Separately, `grep -c` counts distinct call-tree lines, not the per-line sample counts `sample` prints, so a frame hit 2000 times weighs the same as one hit once and the "ratio" is not a time ratio.

**6. `show()` does not actually preserve empty fields; `read` with `IFS=$'\t'` collapses adjacent tabs, so an empty field shifts every column left, which is exactly what the comment claims is prevented.**
- Where: line 186
  ```
  IFS=$'\t' read -r cpu mem th ports win off mpx <<<"$row"
  ```
- Why: tab is an IFS whitespace character, and bash treats runs of IFS whitespace as a single delimiter and strips leading ones. If the census TSV has fewer than 7 columns, `cut -f7` at line 166 yields an empty mpx, or if top emits a short line so `$6` is empty, the row contains consecutive tabs and `read` assigns later fields to earlier names. Ports would then be displayed as threads, the misattribution the comment at lines 182-183 says the code avoids.

**7. When WindowServer's pid cannot be found, the fallback pid 0 measures kernel_task and labels it as WindowServer.**
- Where: line 191 (and 218)
  ```
  T0_APP="$(reading "$PID" "$CENSUS_OWNER")"; T0_WS="$(reading "${WS_PID:-0}" 'Window Server')"
  ```
- Why: pid 0 is a real process on macOS (kernel_task) and `top -pid 0` reports it. The comment at lines 109-114 establishes that `pgrep -x` on this box can miss processes whose comm is a path prefix, and no ps fallback is applied to WindowServer. If that happens, the "WS" rows show kernel_task's cpu, memory, threads and ports, and nothing indicates the substitution.

**8. Accepted app aliases resolve to the wrong GPU discriminator, and Alacritty cannot be found under its documented name.**
- Where: lines 101, 100, 136, 139, 140
  ```
  iTerm2|iTerm)    PROC_NAMES="iTerm2";                       CENSUS_OWNER="iTerm2" ;;
  iTerm2)            GPU_RE='iTermMetalDriver';        CPU_RE='iTermTextDrawingHelper' ;;
  kitty)             GPU_RE='OpenGL|CGL|AGX|gl[A-Z]';  CPU_RE='CoreText|CGContext' ;;
  alacritty|Alacritty) GPU_RE='OpenGL|CGL|AGX|gl[A-Z]'; CPU_RE='CoreText|CGContext' ;;
  ```
- Why: `--app iTerm` is accepted at line 101 but falls to the generic `*` arm at line 141, so the incumbent is profiled with framework-level regexes instead of the iTerm-specific ones and its row is not comparable to a `--app iTerm2` run. `--app kitty.app` likewise falls to generic. `--app Alacritty` is anticipated at line 140 but the process lookup uses `PROC_NAMES="Alacritty"` from the `*` arm at line 102; the binary is `alacritty`, both `pgrep -x` and the case-sensitive awk basename match at line 121 miss it, and the run exits NO-DATA although the header lists Alacritty as a measured app.

**9. An option given as the last argument with no value loops forever.**
- Where: lines 54-64, e.g. line 60
  ```
  --out)         OUT="${2:-}"; shift 2 ;;
  ```
- Why: when `$2` does not exist, `shift 2` fails and shifts nothing, `$#` stays at 1, and the `while [ $# -gt 0 ]` loop re-enters the same case forever. Example: `scripts/terminal-bench.sh --app ghostty --out`.

**10. The drift rate divides by `INTERVAL` but the two readings are farther apart than that, and the app was profiled in between.**
- Where: lines 191, 198, 217, 226-227
  ```
  'BEGIN{ d=b-a; printf "    %-14s %+.0f over %ds  = %+.1f/hr\n", l, d, s, d*3600/s }'
  ```
- Why: T0 is taken at line 191, then `sample` runs for SAMPLE_SECS plus its own attach/symbolication time at line 198, then two `top -l 2` invocations add several more seconds around the sleep. The true T0-to-T1 elapsed time is INTERVAL plus roughly SAMPLE_SECS plus 4-6 s, so the printed per-hour rate is inflated. At the documented 300 s it is a few percent; at short intervals it is large. The `sample` attach also perturbs the subject between the two readings that are supposed to differ only by elapsed time.

**11. `--help` truncates the header before the verdict tokens are fully described.**
- Where: line 61
  ```
  -h|--help)     sed -n '1,45p' "$0"; exit 0 ;;
  ```
- Why: the header runs through line 47. The help output cuts off mid-way through the PARTIAL description and omits the NO-DATA token and its exit code entirely.

**12. The ps fallback breaks on executable paths containing spaces.**
- Where: line 121
  ```
  PID="$(ps -eo pid=,comm= | awk -v want="$_p" '{n=split($2,a,"/"); if (a[n]==want) {print $1; exit}}')"
  ```
- Why: `comm` on macOS is the full path, and awk's `$2` is only the first whitespace-delimited token of it. For any app installed under a path with a space (the generic `*` arm accepts arbitrary names), the basename compared is wrong, the fallback silently misses, and the script reports NO-DATA as if the app were not running.
