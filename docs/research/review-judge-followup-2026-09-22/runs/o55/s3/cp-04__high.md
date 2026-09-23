# Review: `scripts/terminal-bench.sh`

I found 12 defects.

---

**1. The JSONL row records a verdict that is later downgraded.**
- **Where:** line 245, `printf '{"ts":"%s","app":"%s","pid":%s,"panes":%s,"interval":%s,"t0":"%s","gpu_frames":"%s","cpu_frames":"%s","verdict":"%s"}\n' \`, and line 251, `[ "$GPU_VERDICT" = OK ] || VERDICT="PARTIAL"`
- **Why:** Take a run with `--interval 300 --out f.jsonl` where `sample` fails or matches nothing. Line 231 sets `VERDICT="OK"` and the JSONL row is appended with `"verdict":"OK"`. Only after that does line 251 downgrade stdout to `verdict=PARTIAL`. The persisted results file therefore files a row with no GPU profile as a full comparable row.

**2. A missing window census never downgrades the verdict.**
- **Where:** line 231, `VERDICT="OK"`, and line 251, `[ "$GPU_VERDICT" = OK ] || VERDICT="PARTIAL"`
- **Why:** The header says PARTIAL applies when the window census is missing. `CENSUS_OK` is never consulted for the verdict, and neither are NA window columns. When `swiftc` fails, or `REPO` resolved without `tools/` (line 86 only warns), every window column is NA but the run still ends with `verdict=OK` and exit 0. That is exactly the "silently NA, still exit 0" class the comment at lines 67–74 claims to prevent.

**3. "top returned nothing" never produces NO-DATA or exit 3.**
- **Where:** line 151, `if [ -z "$line" ]; then printf 'NA\tNA\tNA\tNA\tNA\tNA\tNA\n'; return 1; fi`, and line 191, `T0_APP="$(reading "$PID" "$CENSUS_OWNER")"; T0_WS="$(reading "${WS_PID:-0}" 'Window Server')"`
- **Why:** The return status of `reading` is discarded. Suppose top times out, lacks permission, or the pid vanished. The run continues with all-NA rows, and with `--interval > 0` it still reaches `verdict=OK` with exit 0. The documented contract is `verdict=NO-DATA` with exit 3.

**4. OK is issued even when the T1 reading failed.**
- **Where:** line 218, `T1_APP="$(reading "$PID" "$CENSUS_OWNER")"; T1_WS="$(reading "${WS_PID:-0}" 'Window Server')"`, and line 231, `VERDICT="OK"`
- **Why:** If the app quit or restarted during the `sleep` (or top failed at T1), `T1_APP` is all NA and every drift line prints NA. `VERDICT` is still set to OK, which claims "both readings taken" when only one was.

**5. The GPU/CPU discriminator matches the `Binary Images` section of the `sample` report, so the 0:0 guard is vacuous.**
- **Where:** line 199, `GPU_N="$(grep -cE "$GPU_RE" "$SAMPLE_F" || true)"`, and line 200, `CPU_N="$(grep -cE "$CPU_RE" "$SAMPLE_F" || true)"`
- **Why:** `grep` runs over the whole report, which includes the loaded-image list: `.../Metal.framework`, `AGXMetal…`, `CoreText.framework`, `OpenGL.framework`. Any app that merely links these frameworks gets non-zero counts even if no stack frame uses them. So line 203 always yields `GPU_VERDICT=OK`, and the counts and ratio include "library is loaded" lines. This is the existence-of-a-fast-path evidence the header says cannot establish "used".

**6. Consecutive tabs collapse in `show`, so an empty field still shifts columns left.**
- **Where:** line 186, `IFS=$'\t' read -r cpu mem th ports win off mpx <<<"$row"`
- **Why:** Tab is an IFS-whitespace character, so `read` merges adjacent tabs into one delimiter. Examples: `cut -f5` returns empty for a census row with fewer than 5 columns, or `awk '{print $6}'` is empty on a short top line. The following values then shift left, e.g. `win` is printed as `ports=`. The comment at lines 182–183 says this code prevents exactly that misattribution.

**7. When WindowServer's pid isn't found, the "WS" row silently measures pid 0 (`kernel_task`).**
- **Where:** line 191, `T0_WS="$(reading "${WS_PID:-0}" 'Window Server')"` (same at line 218)
- **Why:** If line 129, `WS_PID="$(pgrep -x WindowServer | head -1 || true)"`, comes back empty, `reading 0` runs `top -pid 0`. The line-150 grep for `^\s*0\s` then matches `kernel_task`. Its cpu, mem, threads and ports are printed as `WS`, not NA. The script's own comment (lines 109–115) documents that `pgrep -x` can miss processes whose `p_comm` is a path prefix, and no ps fallback is applied for WindowServer.

**8. Per-pane normalisation turns NA into a measured zero.**
- **Where:** line 237, `awk -v p="$PANES" -v r="$T0_APP" 'BEGIN{ split(r,f,"\t");`, and line 238, `printf "    threads/pane   %.2f\n", f[3]/p;`
- **Why:** When the T0 reading failed or a field is NA, awk evaluates `"NA"/p` as `0`. It prints `threads/pane 0.00`, `MB/pane 0.0` and so on. This is the "measured zero vs. instrument did not run" confusion the verdict section says a consumer must be able to distinguish.

**9. Alacritty has no entry in the process/owner table, so it cannot be measured correctly under either spelling.**
- **Where:** line 102, `*)               PROC_NAMES="$APP";                         CENSUS_OWNER="$APP" ;;`
- **Why:** Alacritty's executable is `alacritty` but its window owner is `Alacritty`. With `--app Alacritty`, both `pgrep -x` and the ps-basename fallback miss, giving NO-DATA and exit 3. With `--app alacritty`, the census is queried for owner `alacritty` and the window columns come back NA. This is the WezTerm failure mode the comment at lines 93–96 says the explicit table exists to prevent. The header lists Alacritty as supported, and line 140 has an Alacritty GPU entry.

**10. App aliases accepted by the name table fall through to the generic GPU discriminator.**
- **Where:** line 101, `iTerm2|iTerm)    PROC_NAMES="iTerm2";                       CENSUS_OWNER="iTerm2" ;;`, vs line 136, `iTerm2)            GPU_RE='iTermMetalDriver';        CPU_RE='iTermTextDrawingHelper' ;;`. Also line 100, `kitty|kitty.app)`, vs line 139, `kitty)`.
- **Why:** `--app iTerm` or `--app kitty.app` finds the right process. The GPU profile, however, uses the generic `Metal|AGX|IOGPU|…` / `CoreText|CGContext|CGSBlend` regexes instead of the app-specific symbols. That produces different, non-comparable frame counts for the same app depending on spelling.

**11. A failed census rebuild warns "unavailable" while a stale binary is still used.**
- **Where:** line 175, `if ! run 300 swiftc -O "$CENSUS_SRC" -o "$CENSUS_BIN" 2>/dev/null; then CENSUS_OK=0; fi`, and line 163, `if [ -x "$CENSUS_BIN" ]; then`
- **Why:** Suppose the source is newer than an existing binary and `swiftc` fails. `CENSUS_OK=0` is set and line 180 prints "window census unavailable … window columns report NA". But `reading` only checks `-x "$CENSUS_BIN"`, so it runs the old binary and populates the window columns from outdated code. The output contradicts its own warning.

**12. `--help` truncates the header before the NO-DATA verdict documentation.**
- **Where:** line 61, `-h|--help)     sed -n '1,45p' "$0"; exit 0 ;;`
- **Why:** The verdict block runs through line 47. Help output stops mid-sentence in the PARTIAL description and omits the `verdict=NO-DATA` token and its exit code 3.
