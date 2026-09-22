# Review of `scripts/terminal-bench.sh`

Line numbers count from `#!/bin/bash` as line 1.

---

**1. A missing window census never downgrades the verdict.**
- **Where:** L231 `  VERDICT="OK"` and L251 `[ "$GPU_VERDICT" = OK ] || VERDICT="PARTIAL"`. The only guard is L86 `[ -f "$CENSUS_SRC" ] || echo "terminal-bench: ⚠ census source not found under REPO=$REPO" >&2`.
- **Why:** The header says PARTIAL means "at least one of {drift, GPU profile, window census} is missing". `CENSUS_OK` and the NA window columns are never consulted, though. Suppose the census source is not found, `swiftc` fails, or the census owner name matches nothing. Then every window column is NA, yet the run prints `verdict=OK` and exits 0. That is exactly the "silently report NA … and still exit 0" failure the comment at L70–71 says this block prevents. The L86 "fail loud" guard is only a stderr line.

**2. The JSONL row records the verdict before the GPU downgrade is applied.**
- **Where:** L247 `    "$(tr '\t' ',' <<<"$T0_APP")" "$GPU_N" "$CPU_N" "$VERDICT" >> "$OUT"` runs before L251 `[ "$GPU_VERDICT" = OK ] || VERDICT="PARTIAL"`.
- **Why:** Take `--interval 180 --out f.jsonl` where `sample` fails or matches 0:0. The file gets `"verdict":"OK"` while stdout prints `verdict=PARTIAL`. The persisted row claims a full, comparable result that was never obtained.

**3. The GPU/CPU discriminators match the loaded-image list, not only frames that ran.**
- **Where:** L199 `  GPU_N="$(grep -cE "$GPU_RE" "$SAMPLE_F" || true)"` and L200 `  CPU_N="$(grep -cE "$CPU_RE" "$SAMPLE_F" || true)"`, with regexes such as L141 `  *)                 GPU_RE='Metal|AGX|IOGPU|wgpu|CGL|OpenGL'; CPU_RE='CoreText|CGContext|CGSBlend' ;;`.
- **Why:** A `sample` report ends with a "Binary Images" section listing every loaded library. For any AppKit app that includes Metal.framework, the AGX driver, IOGPU, OpenGL/CGL and CoreText. So for Ghostty, WezTerm, kitty, Alacritty and generic apps:
  - both counts are ≥1 whether or not those paths were used;
  - the 0:0 guard at L203 can never fire;
  - `gpu_frames` is inflated by "loaded" evidence, which the header says can never establish "used".
  
  iTerm2's symbol-only regex is not inflated this way, so the rows across apps are not comparable.

**4. `grep -c` counts matching lines, not samples, but is reported as frames and a time ratio.**
- **Where:** L199 and L200 (above), and L206 `  printf '  GPU path taken: gpu_frames=%s cpu_frames=%s  ratio=%s\n' "$GPU_N" "$CPU_N" \`.
- **Why:** `sample` output is a call tree where each line carries its own sample count. One hot GPU node with 4000 samples counts as 1, while a cold CPU path spread over 40 nodes counts as 40. The same symbols are counted again in the "Total number in stack" and "Sort by top of stack" sections. The printed `ratio` therefore does not reflect which path the time was spent on.

**5. `IFS=$'\t'` does not stop empty fields from shifting columns.**
- **Where:** L186 `  IFS=$'\t' read -r cpu mem th ports win off mpx <<<"$row"`
- **Why:** Tab is an IFS whitespace character, so bash collapses consecutive tabs and strips leading ones, just like default word splitting. If any field is empty (e.g. a census `cut -f` yields nothing), every later label shows the next column's value. This is the misattribution the comment at L182–183 says this line prevents.

**6. "top returned nothing" does not produce NO-DATA, and failed readings still yield OK.**
- **Where:** L151 `  if [ -z "$line" ]; then printf 'NA\tNA\tNA\tNA\tNA\tNA\tNA\n'; return 1; fi`. Its status is discarded at L191 `T0_APP="$(reading "$PID" "$CENSUS_OWNER")"; T0_WS="$(reading "${WS_PID:-0}" 'Window Server')"` and at L218. L231 `  VERDICT="OK"` is then set unconditionally.
- **Why:** The header says NO-DATA (exit 3) covers "top returned nothing". If `top` times out, or the app quits or relaunches during the interval, T0 or T1 is all NA. Every drift line prints NA, yet the run reports `verdict=OK` ("both readings taken") and exits 0.

**7. Per-pane normalisation turns a missing reading into a measured zero.**
- **Where:** L237 `  awk -v p="$PANES" -v r="$T0_APP" 'BEGIN{ split(r,f,"\t");` through L241 `    printf "    cpu%%/pane      %.2f\n", f[1]/p }'`
- **Why:** When T0 is NA (see #6), awk evaluates `"NA"/p` as 0. The script prints `threads/pane 0.00`, `ports/pane 0.00` and so on, the "measured zero vs. instrument did not run" confusion the header warns about.

**8. The WindowServer fallback PID 0 measures `kernel_task`.**
- **Where:** L191 `... T0_WS="$(reading "${WS_PID:-0}" 'Window Server')"` (same at L218).
- **Why:** If L129's `pgrep -x WindowServer` finds nothing, `top -l 2 -pid 0` returns `kernel_task`. Its line matches `^ *0 `, so kernel_task's cpu, mem, threads and ports are printed under the "WS" label as if they were WindowServer's.

**9. App aliases accepted by the name table are not honoured by the discriminator table.**
- **Where:** L101 `  iTerm2|iTerm)    PROC_NAMES="iTerm2";                       CENSUS_OWNER="iTerm2" ;;` versus L136 `  iTerm2)            GPU_RE='iTermMetalDriver';        CPU_RE='iTermTextDrawingHelper' ;;`. Likewise L100 `kitty|kitty.app` versus L139 `  kitty)`.
- **Why:** `--app iTerm` measures the iTerm2 process with the generic `Metal|AGX|…` regexes instead of `iTermMetalDriver`/`iTermTextDrawingHelper`. The incumbent's GPU numbers then come from a different, image-list-contaminated instrument (see #3). `--app kitty.app` has the same problem.

**10. Alacritty is missing from the process/owner name table.**
- **Where:** L102 `  *)               PROC_NAMES="$APP";                         CENSUS_OWNER="$APP" ;;` (L140 does list `alacritty|Alacritty` for the discriminators).
- **Why:** Alacritty's executable is `alacritty` but its window owner is `Alacritty`, the same mismatch the table was built for.
  - `--app Alacritty` fails both `pgrep -x` and the ps basename match, giving NO-DATA.
  - `--app alacritty` finds the process, but the census is queried for owner `alacritty`, so the window columns are NA while the verdict stays OK (see #1).

**11. A stale census binary is used after a failed rebuild, while the output says the columns are NA.**
- **Where:** L175 `  if ! run 300 swiftc -O "$CENSUS_SRC" -o "$CENSUS_BIN" 2>/dev/null; then CENSUS_OK=0; fi`. L180 `[ "$CENSUS_OK" = 1 ] || echo "  ⚠ window census unavailable (swiftc failed) — window columns report NA"`. But `reading` gates on L163 `  if [ -x "$CENSUS_BIN" ]; then`.
- **Why:** Suppose the source is newer than an existing binary and compilation fails. The script announces that the columns will be NA, then runs the old binary and reports its numbers as current. Any output-format change in the newer source means those numbers may land in the wrong `cut` columns.

**12. A value flag given as the last argument causes an infinite loop.**
- **Where:** L56 `    --app)         APP="${2:-}"; shift 2 ;;` (same pattern at L57–60).
- **Why:** For example, `terminal-bench.sh --interval`. `shift 2` with only one positional argument fails without shifting, so `$1` stays the same and the `while` loop never ends.

**13. The ps-comm fallback breaks on executable paths that contain spaces.**
- **Where:** L121 `    PID="$(ps -eo pid=,comm= | awk -v want="$_p" '{n=split($2,a,"/"); if (a[n]==want) {print $1; exit}}')"`
- **Why:** `comm` is the full executable path, and awk's default field splitting cuts `$2` at the first space. An app under e.g. `/Applications/My Tools/X.app/...` can never match, so the result is NO-DATA.

**14. The GPU NO-DATA message blames the discriminator even when `sample` never ran.**
- **Where:** L209 `  printf '  GPU path taken: NO-DATA (discriminator matched no symbols; do NOT read as "no GPU")\n'`
- **Why:** This branch is also taken when `sample` fails (permission denied, timeout) or writes an empty file (L198). The reported cause is then wrong: the instrument did not run at all.

**15. A JSONL row marked OK carries no drift data.**
- **Where:** L245 `  printf '{"ts":"%s","app":"%s","pid":%s,"panes":%s,"interval":%s,"t0":"%s","gpu_frames":"%s","cpu_frames":"%s","verdict":"%s"}\n' \`
- **Why:** The header calls DRIFT "the only reading that supports a leak verdict" and says OK means "a full comparable row". The persisted row contains only T0; T1, drift and all WindowServer figures are dropped. A consumer of the results file cannot recover the leak measurement behind an OK row.

**16. `--help` truncates the verdict contract.**
- **Where:** L61 `    -h|--help)     sed -n '1,45p' "$0"; exit 0 ;;`
- **Why:** The header runs to L47. Help output stops mid-way through the PARTIAL description and omits `verdict=NO-DATA` and its exit code 3, the machine-parsable contract a consumer needs.
