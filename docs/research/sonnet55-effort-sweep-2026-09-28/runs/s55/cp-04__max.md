Twelve defects, most consequential first. Everything below comes from the text of the brief; I used no tools.

**1.**
- **What**: `VERDICT` is set to `OK` whenever `--interval > 0`, with no check that a reading returned data or that the window census ran. The documented `NO-DATA` (top returned nothing) and census-missing `PARTIAL` outcomes can therefore never be produced.
- **Where**: `scripts/terminal-bench.sh:231` `VERDICT="OK"`. It ignores these failure signals:
  - `:151` `if [ -z "$line" ]; then printf 'NA\tNA\tNA\tNA\tNA\tNA\tNA\n'; return 1; fi`. The status of `reading` is never tested at `:191` or `:218`.
  - `:180` `[ "$CENSUS_OK" = 1 ] || echo "  ⚠ window census unavailable (swiftc failed) — window columns report NA"`. `CENSUS_OK` feeds only this warning, and `:86` likewise only warns.
- **Why it is wrong**: Header lines 43–47 define OK as "both readings taken". They list a missing window census under PARTIAL and "top returned nothing (exit 3)" under NO-DATA. Only the process-not-found case (`:125-128`) exits 3.
  - If the app dies or `top` returns no row during the hold, T1 is the all-`NA` row and every DRIFT line prints `NA`. If the earlier `sample` matched, the run still ends `verdict=OK` with exit 0 and no drift measured.
  - If the census source is missing or `swiftc` fails, every window/offscreen column is `NA` and the token is still `OK`, not `PARTIAL`.
  - Both are "instrument did not run" reported as success, the failure lines 41–42 say the token exists to prevent.

**2.**
- **What**: The JSONL row is appended before line 251 downgrades `VERDICT` for an unresolved GPU profile, so the stored verdict and the printed verdict can disagree.
- **Where**: `scripts/terminal-bench.sh:247` `"$(tr '\t' ',' <<<"$T0_APP")" "$GPU_N" "$CPU_N" "$VERDICT" >> "$OUT"` runs before `:251` `[ "$GPU_VERDICT" = OK ] || VERDICT="PARTIAL"`.
- **Why it is wrong**: Run `--interval 300 --out r.jsonl` where `sample` fails or matches nothing, so `GPU_VERDICT=NO-DATA` and `GPU_N=CPU_N=NA`.
  - At the append, `VERDICT` is still `OK` from `:231`. The file gets `"gpu_frames":"NA","cpu_frames":"NA","verdict":"OK"`, while stdout ends `verdict=PARTIAL`.
  - The saved record claims a resolved GPU profile (line 43) that does not exist.
  - The row holds only T0, so nothing in it contradicts the `OK`.

**3.**
- **What**: The per-pane block does arithmetic on the `NA` placeholder, so a missing reading is printed as zeros.
- **Where**: `scripts/terminal-bench.sh:237` `awk -v p="$PANES" -v r="$T0_APP" 'BEGIN{ split(r,f,"\t");` with `:238` `printf "    threads/pane   %.2f\n", f[3]/p;` (and `:239-241`).
- **Why it is wrong**: If T0_APP is the all-`NA` row from `:151` and `--panes 30` is given, awk coerces `"NA"` to 0. It prints `threads/pane 0.00`, `ports/pane 0.00`, `MB/pane 0.0` and `cpu%/pane 0.00`, indistinguishable from a real measured zero. `drift` guards `NA` (`:225`); this block does not. Header lines 41–42 require "measured zero" and "did not run" to be distinguishable.

**4.**
- **What**: A value-taking option given as the last argument makes the argument loop spin forever.
- **Where**: `scripts/terminal-bench.sh:56` `--app)         APP="${2:-}"; shift 2 ;;`. The same `shift 2 ;;` arms are at `:57` (`--panes`), `:58` (`--interval`), `:59` (`--sample-secs`) and `:60` (`--out`).
- **Why it is wrong**: Take `terminal-bench.sh --app iTerm2 --interval`.
  - After `--app iTerm2` is consumed, `$#` is 1. `${2:-180}` supplies a default, but `shift 2` fails because the count exceeds `$#`, leaving `$1` unchanged.
  - `[ $# -gt 0 ]` stays true and the `--interval` arm reruns indefinitely: a hang with no verdict.
  - `--app` alone hangs the same way, before the "required" check at `:65` can fire.

**5.**
- **What**: "appended → $OUT" is printed unconditionally after the redirected write, whether or not the write succeeded.
- **Where**: `scripts/terminal-bench.sh:247` `"$(tr '\t' ',' <<<"$T0_APP")" "$GPU_N" "$CPU_N" "$VERDICT" >> "$OUT"`, then `:248` `echo "  appended → $OUT"`.
- **Why it is wrong**: With `--out /nonexistent/dir/r.jsonl`, or any unwritable path, the `>>` fails and nothing is stored (only a shell redirection error goes to stderr). Stdout still reports the row as appended, then prints a verdict and exits 0.

**6.**
- **What**: The GPU/CPU counters grep the entire `sample` report, including its "Binary Images" list of loaded libraries. They therefore count library presence rather than frames taken, and the 0:0 → NO-DATA guard is defeated.
- **Where**: `scripts/terminal-bench.sh:199` `GPU_N="$(grep -cE "$GPU_RE" "$SAMPLE_F" || true)"`, `:200` `CPU_N="$(grep -cE "$CPU_RE" "$SAMPLE_F" || true)"`, `:203` `if [ "$GPU_N" -gt 0 ] || [ "$CPU_N" -gt 0 ]; then GPU_VERDICT="OK"; fi`.
- **Why it is wrong**: `sample` ends with one line per loaded image, for example `.../CoreText.framework/...` and `.../Metal.framework/...`.
  - Every non-iTerm2 pattern (ghostty, wezterm, kitty, generic) uses bare names such as `Metal`, `CoreText`, `OpenGL`, `AGX` or `CGL`. They match those lines merely because the library is loaded, which is the "existence of a fast path" evidence header lines 10–13 say cannot establish "used".
  - CoreText is loaded by any AppKit app, so `CPU_N` is non-zero even when no sampled frame matched. The 0:0 case (`:201-202`) cannot occur, `GPU_VERDICT` becomes `OK` on library-list lines alone, and gpu_frames, cpu_frames and the ratio are inflated by them.

**7.**
- **What**: The process/owner table and the GPU-discriminator table accept different spellings of the app name. An accepted alias silently gets the wrong discriminator or the wrong window-owner name.
- **Where**:
  - `scripts/terminal-bench.sh:101` `iTerm2|iTerm)    PROC_NAMES="iTerm2";                       CENSUS_OWNER="iTerm2" ;;` versus `:136` `iTerm2)            GPU_RE='iTermMetalDriver';        CPU_RE='iTermTextDrawingHelper' ;;`
  - `:100` `kitty|kitty.app) PROC_NAMES="kitty";                        CENSUS_OWNER="kitty" ;;` versus `:139` `kitty)             GPU_RE='OpenGL|CGL|AGX|gl[A-Z]';  CPU_RE='CoreText|CGContext' ;;`
  - `:138` `wezterm*|WezTerm*) GPU_RE='wgpu|Metal';              CPU_RE='CoreText|CGContext|glyphcache' ;;` versus `:98` `wezterm|WezTerm) PROC_NAMES="wezterm-gui WezTerm wezterm"; CENSUS_OWNER="WezTerm" ;;`
- **Why it is wrong**:
  - `--app iTerm` or `--app kitty.app` finds the right process, but the GPU `case` keys on the raw `$APP` and has no arm for the alias. It falls to `*)` at `:141`, so the generic patterns produce gpu_frames and cpu_frames that differ from `--app iTerm2` on the same process. That contradicts the comparability claim in header lines 3–4.
  - `--app wezterm-gui` gets the WezTerm GPU patterns (`:138`) but falls to the process table's `*)` (`:102`) with `CENSUS_OWNER="wezterm-gui"`. The comment at `:94` says the window owner is `WezTerm`, so the window columns come out `NA`, exactly the name confusion `:93-96` says the table exists to prevent.

**8.**
- **What**: DRIFT rates and the "over Ns" label use `INTERVAL` as the elapsed time, but T0 and T1 are further apart than `INTERVAL`.
- **Where**: `scripts/terminal-bench.sh:227` `'BEGIN{ d=b-a; printf "    %-14s %+.0f over %ds  = %+.1f/hr\n", l, d, s, d*3600/s }'` with `:226` `awk -v a="$a" -v b="$b" -v s="$INTERVAL" -v l="$label" \`. The extra time comes from `:191` `T0_APP="$(reading "$PID" "$CENSUS_OWNER")"; T0_WS="$(reading "${WS_PID:-0}" 'Window Server')"`, `:198` `if run 120 sample "$PID" "$SAMPLE_SECS" -f "$SAMPLE_F" >/dev/null 2>&1 && [ -s "$SAMPLE_F" ]; then` and `:217` `sleep "$INTERVAL"`.
- **Why it is wrong**: T0_APP is captured first. The T0 WindowServer reading (another `top -l 2` plus census) and a `sample` of `SAMPLE_SECS` (default 5 s, plus symbolication) both run before the `sleep` starts. The T0_APP→T1_APP gap is `INTERVAL` plus at least about 6 s. Every per-hour rate is still divided by `INTERVAL` and labelled "over ${INTERVAL}s". With `--interval 60` and defaults, every rate is overstated by at least 10%, and the error grows with `--sample-secs` and shrinks with longer intervals. This contradicts "a known interval apart" (line 28).

**9.**
- **What**: `show()` claims that tab-splitting keeps empty fields, but `read` with `IFS=$'\t'` collapses adjacent tabs, so an empty field shifts every later column left.
- **Where**: `scripts/terminal-bench.sh:186` `IFS=$'\t' read -r cpu mem th ports win off mpx <<<"$row"` (the claim is in the comment at `:182-183`).
- **Why it is wrong**: Tab is an IFS-whitespace character, so consecutive tabs count as one delimiter.
  - Take the row `12.3<TAB>783<TAB>45<TAB><TAB>2<TAB>1<TAB>0`, with `ports` empty (from `awk '{print $6}'` at `:155`, or a blank census column via `cut` at `:166`).
  - It prints `ports=2 win=1 off=0 mpx=`, so windows are shown as ports and offscreen as windows. That is the misattribution the comment says this code avoids.
  - `drift` uses `cut -f`, which does not collapse, so the DRIFT lines then disagree with the displayed T0/T1 rows.

**10.**
- **What**: `--help` prints a truncated copy of the header.
- **Where**: `scripts/terminal-bench.sh:61` `-h|--help)     sed -n '1,45p' "$0"; exit 0 ;;`
- **Why it is wrong**: The header comment runs through line 47. `1,45p` stops mid-sentence in the PARTIAL entry ("…always yields PARTIAL by construction: a single"). It drops lines 46–47, including the whole `verdict=NO-DATA … (exit 3)` token, so `--help` never documents that token or the exit code.

**11.**
- **What**: When the census rebuild fails but an older binary exists, the script announces that window columns are `NA` and then runs the stale binary anyway.
- **Where**: `scripts/terminal-bench.sh:175` `if ! run 300 swiftc -O "$CENSUS_SRC" -o "$CENSUS_BIN" 2>/dev/null; then CENSUS_OK=0; fi`, `:180` `[ "$CENSUS_OK" = 1 ] || echo "  ⚠ window census unavailable (swiftc failed) — window columns report NA"`, and `:163` `if [ -x "$CENSUS_BIN" ]; then`.
- **Why it is wrong**: A source newer than the binary triggers a rebuild (`:174`). If `swiftc` fails, for example because the source was just edited into a broken state, `CENSUS_OK=0` and the warning prints. But `reading` only tests `-x "$CENSUS_BIN"`, which the old binary satisfies. The window, offscreen and mpx columns and their DRIFT lines then carry numbers from a binary that no longer matches the source, contrary to the "report NA" message.

**12.**
- **What**: The numeric flags `--panes` and `--interval` are never validated, and their raw text is written unquoted into the JSON row.
- **Where**: `scripts/terminal-bench.sh:245` `printf '{"ts":"%s","app":"%s","pid":%s,"panes":%s,"interval":%s,"t0":"%s","gpu_frames":"%s","cpu_frames":"%s","verdict":"%s"}\n' \` with `:246` `"$(date -u +%FT%TZ)" "$APP" "$PID" "${PANES:-0}" "$INTERVAL" \`. The only gates are `:235` `if [ "${PANES:-0}" -gt 0 ]; then` and `:215` `if [ "$INTERVAL" -gt 0 ]; then`.
- **Why it is wrong**: With `--panes abc --out r.jsonl`, `[ abc -gt 0 ]` errors on stderr and the per-pane block is skipped. The script carries on, appends a line containing `"panes":abc`, which is invalid JSON, and prints `appended →`. `--interval abc` likewise skips the hold and writes `"interval":abc`.
