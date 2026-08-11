1. **What** — A value-taking option with no following value leaves the argument list unchanged and makes the parser loop forever.

   **Where** — Lines 54 and 56–60:

   ```bash
   while [ $# -gt 0 ]; do
       --app)         APP="${2:-}"; shift 2 ;;
       --panes)       PANES="${2:-0}"; shift 2 ;;
       --interval)    INTERVAL="${2:-180}"; shift 2 ;;
       --sample-secs) SAMPLE_SECS="${2:-5}"; shift 2 ;;
       --out)         OUT="${2:-}"; shift 2 ;;
   ```

   **Why it is wrong** — For an invocation ending in an option such as `--app`, `shift 2` fails because only one argument remains, but without `set -e` the unchanged argument is processed repeatedly.

2. **What** — The help output is truncated in the middle of the verdict documentation.

   **Where** — Line 61:

   ```bash
       -h|--help)     sed -n '1,45p' "$0"; exit 0 ;;
   ```

   **Why it is wrong** — `--help` stops at line 45, which ends mid-sentence, and omits the rest of the `PARTIAL` explanation and the `NO-DATA` definition on lines 46–47.

3. **What** — A run without `--out` still writes files despite the stated read-only contract.

   **Where** — Lines 33–34, 175, 197–198, and 211:

   ```bash
   # READ-ONLY. Creates no panes, closes no panes, writes no preference, kills nothing. The only
   # side effect is an optional append to the results JSONL.
     if ! run 300 swiftc -O "$CENSUS_SRC" -o "$CENSUS_BIN" 2>/dev/null; then CENSUS_OK=0; fi
   SAMPLE_F="${TMPDIR:-/tmp}/tb-sample.$$.txt"
   if run 120 sample "$PID" "$SAMPLE_SECS" -f "$SAMPLE_F" >/dev/null 2>&1 && [ -s "$SAMPLE_F" ]; then
   rm -f "$SAMPLE_F"
   ```

   **Why it is wrong** — On a first run the script creates and leaves the compiled census binary, and every profiling attempt writes a sample file even when no output append was requested.

4. **What** — The census cache can execute a binary built from a different source tree or a failed prior build.

   **Where** — Lines 87, 163, and 174–177:

   ```bash
   CENSUS_BIN="${TMPDIR:-/tmp}/window-census.$(id -u)"
     if [ -x "$CENSUS_BIN" ]; then
   if [ ! -x "$CENSUS_BIN" ] || [ "$CENSUS_SRC" -nt "$CENSUS_BIN" ]; then
     if ! run 300 swiftc -O "$CENSUS_SRC" -o "$CENSUS_BIN" 2>/dev/null; then CENSUS_OK=0; fi
   fi
   [ -x "$CENSUS_BIN" ] || CENSUS_OK=0
   ```

   **Why it is wrong** — If another checkout left a newer executable at the UID-global path, the timestamp test skips compilation and `reading` runs that unrelated binary solely because it is executable; an old executable surviving a failed rebuild is likewise still run.

5. **What** — Fallback app names are interpreted as shell words, glob patterns, and regular expressions rather than literal process names.

   **Where** — Lines 102 and 105–106:

   ```bash
     *)               PROC_NAMES="$APP";                         CENSUS_OWNER="$APP" ;;
   for _p in $PROC_NAMES; do
     PID="$(pgrep -x "$_p" | head -1 || true)"
   ```

   **Why it is wrong** — An app name containing whitespace is split into multiple candidates, glob characters can expand against workspace filenames, and an ERE metacharacter such as `.` can make `pgrep` select a different process.

6. **What** — The advertised Alacritty target lacks the process-name/window-owner normalization needed for its differently cased macOS names.

   **Where** — Lines 102 and 140:

   ```bash
     *)               PROC_NAMES="$APP";                         CENSUS_OWNER="$APP" ;;
     alacritty|Alacritty) GPU_RE='OpenGL|CGL|AGX|gl[A-Z]'; CPU_RE='CoreText|CGContext' ;;
   ```

   **Why it is wrong** — With executable name `alacritty` and CGWindow owner `Alacritty`, lowercase input can find the process but searches for the wrong owner, while title-case input searches for the wrong process.

7. **What** — With multiple same-named app processes, the script arbitrarily measures one PID while obtaining windows by owner name, so one row can describe different populations.

   **Where** — Lines 106, 121, and 164:

   ```bash
     PID="$(pgrep -x "$_p" | head -1 || true)"
       PID="$(ps -eo pid=,comm= | awk -v want="$_p" '{n=split($2,a,"/"); if (a[n]==want) {print $1; exit}}')"
       local c; c="$(run 30 "$CENSUS_BIN" --owner "$owner" --tsv 2>/dev/null | grep -v '^owner' | grep -v '^verdict' | head -1)"
   ```

   **Why it is wrong** — When two instances share a process and owner name, CPU and profiling data come from the first arbitrary PID, while the owner-only census can aggregate both instances or choose an unrelated first owner row.

8. **What** — The captured PID is reused without verifying that it still belongs to the selected application.

   **Where** — Lines 106, 198, and 218:

   ```bash
     PID="$(pgrep -x "$_p" | head -1 || true)"
   if run 120 sample "$PID" "$SAMPLE_SECS" -f "$SAMPLE_F" >/dev/null 2>&1 && [ -s "$SAMPLE_F" ]; then
     T1_APP="$(reading "$PID" "$CENSUS_OWNER")"; T1_WS="$(reading "${WS_PID:-0}" 'Window Server')"
   ```

   **Why it is wrong** — If the app exits and macOS reassigns its PID before profiling or T1, the script reports metrics from the unrelated replacement process under the original app’s name.

9. **What** — Failure to find WindowServer substitutes PID 0 and can report kernel-task metrics as WindowServer metrics.

   **Where** — Lines 129, 191, and 218:

   ```bash
   WS_PID="$(pgrep -x WindowServer | head -1 || true)"
   T0_APP="$(reading "$PID" "$CENSUS_OWNER")"; T0_WS="$(reading "${WS_PID:-0}" 'Window Server')"
     T1_APP="$(reading "$PID" "$CENSUS_OWNER")"; T1_WS="$(reading "${WS_PID:-0}" 'Window Server')"
   ```

   **Why it is wrong** — When the lookup fails, `${WS_PID:-0}` targets macOS PID 0, which is `kernel_task`, and its `top` values are printed with the `WS` label.

10. **What** — The explicitly accepted `iTerm` and `kitty.app` aliases bypass their app-specific GPU discriminators.

    **Where** — Lines 100–101, 136, 139, and 141:

    ```bash
      kitty|kitty.app) PROC_NAMES="kitty";                        CENSUS_OWNER="kitty" ;;
      iTerm2|iTerm)    PROC_NAMES="iTerm2";                       CENSUS_OWNER="iTerm2" ;;
      iTerm2)            GPU_RE='iTermMetalDriver';        CPU_RE='iTermTextDrawingHelper' ;;
      kitty)             GPU_RE='OpenGL|CGL|AGX|gl[A-Z]';  CPU_RE='CoreText|CGContext' ;;
      *)                 GPU_RE='Metal|AGX|IOGPU|wgpu|CGL|OpenGL'; CPU_RE='CoreText|CGContext|CGSBlend' ;;
    ```

    **Why it is wrong** — Passing either alias resolves the intended process but falls into the generic GPU case, so the same application can receive different counts and even a different profile verdict depending only on its accepted spelling.

11. **What** — The supposed second `top` sample can actually be the first lifetime-average sample.

    **Where** — Lines 149–151:

    ```bash
      line="$(run 30 top -l 2 -pid "$pid" -stats pid,command,cpu,mem,th,ports 2>/dev/null \
              | grep -E "^[[:space:]]*${pid}[[:space:]]" | tail -1)"
      if [ -z "$line" ]; then printf 'NA\tNA\tNA\tNA\tNA\tNA\tNA\n'; return 1; fi
    ```

    **Why it is wrong** — If the process disappears before sample two or `top` times out after emitting sample one, there is still one matching line and `tail -1` accepts that lifetime-average row as valid.

12. **What** — The census command’s exit status and its emitted verdict are silently discarded.

    **Where** — Lines 164–165:

    ```bash
        local c; c="$(run 30 "$CENSUS_BIN" --owner "$owner" --tsv 2>/dev/null | grep -v '^owner' | grep -v '^verdict' | head -1)"
        if [ -n "$c" ]; then
    ```

    **Why it is wrong** — If the helper exits unsuccessfully or emits a `NO-DATA`/`PARTIAL` verdict alongside a data-looking row, the verdict is removed, the failure status is ignored, and that row is accepted.

13. **What** — The display splitter does not preserve empty TSV fields despite claiming to do so.

    **Where** — Line 186:

    ```bash
      IFS=$'\t' read -r cpu mem th ports win off mpx <<<"$row"
    ```

    **Why it is wrong** — Bash treats tab as IFS whitespace and collapses consecutive tabs, so an empty interior field shifts every later value into the wrong displayed column.

14. **What** — Empty census fields overwrite `NA` and are subsequently treated as numeric zero by drift calculations.

    **Where** — Lines 166 and 225–227:

    ```bash
          win="$(cut -f3 <<<"$c")"; off="$(cut -f5 <<<"$c")"; mpx="$(cut -f7 <<<"$c")"
        [ "$a" = NA ] || [ "$b" = NA ] && { printf '    %-14s NA\n' "$label"; return; }
        awk -v a="$a" -v b="$b" -v s="$INTERVAL" -v l="$label" \
          'BEGIN{ d=b-a; printf "    %-14s %+.0f over %ds  = %+.1f/hr\n", l, d, s, d*3600/s }'
    ```

    **Why it is wrong** — If a nonempty census row has an empty requested field, `cut` produces an empty string, the guard does not recognize it as missing, and `awk` calculates drift from zero.

15. **What** — A missing app `top` reading never produces the documented `NO-DATA` result or exit status 3.

    **Where** — Lines 151, 191, 218, 231, and 252:

    ```bash
      if [ -z "$line" ]; then printf 'NA\tNA\tNA\tNA\tNA\tNA\tNA\n'; return 1; fi
    T0_APP="$(reading "$PID" "$CENSUS_OWNER")"; T0_WS="$(reading "${WS_PID:-0}" 'Window Server')"
      T1_APP="$(reading "$PID" "$CENSUS_OWNER")"; T1_WS="$(reading "${WS_PID:-0}" 'Window Server')"
      VERDICT="OK"
    echo "verdict=$VERDICT"
    ```

    **Why it is wrong** — When `reading` returns failure, its assignment status is ignored, and an interval run with a matching GPU discriminator can end with `verdict=OK` and exit 0 even though one or both app readings are entirely `NA`.

16. **What** — Missing window-census data does not downgrade the final verdict to `PARTIAL`.

    **Where** — Lines 162, 180, 231, and 251:

    ```bash
      win="NA"; off="NA"; mpx="NA"
    [ "$CENSUS_OK" = 1 ] || echo "  ⚠ window census unavailable (swiftc failed) — window columns report NA"
      VERDICT="OK"
    [ "$GPU_VERDICT" = OK ] || VERDICT="PARTIAL"
    ```

    **Why it is wrong** — With a positive interval and a resolved GPU profile, compiler failure or a census invocation returning no row leaves every window field `NA` but still produces `verdict=OK`.

17. **What** — GPU-path proof scans the entire `sample` report, so loaded-image metadata can be mistaken for executed rendering code.

    **Where** — Lines 199–203:

    ```bash
      GPU_N="$(grep -cE "$GPU_RE" "$SAMPLE_F" || true)"
      CPU_N="$(grep -cE "$CPU_RE" "$SAMPLE_F" || true)"
      # A 0:0 result means the discriminator did not match this binary's symbols — NOT that the app
      # renders on neither path. Reporting it as "0 GPU" would be a vacuous pass.
      if [ "$GPU_N" -gt 0 ] || [ "$CPU_N" -gt 0 ]; then GPU_VERDICT="OK"; fi
    ```

    **Why it is wrong** — A `Metal`, `CoreText`, `CGL`, or similar match in `sample`’s loaded binary-image section makes a nonzero count and an `OK` profile even when no sampled stack executed that path.

18. **What** — The reported `gpu_frames`, `cpu_frames`, and their ratio are counts of matching report lines rather than sampled frames.

    **Where** — Lines 199–200 and 206–207:

    ```bash
      GPU_N="$(grep -cE "$GPU_RE" "$SAMPLE_F" || true)"
      CPU_N="$(grep -cE "$CPU_RE" "$SAMPLE_F" || true)"
      printf '  GPU path taken: gpu_frames=%s cpu_frames=%s  ratio=%s\n' "$GPU_N" "$CPU_N" \
        "$(awk -v g="$GPU_N" -v c="$CPU_N" 'BEGIN{ if(c==0){print "all-GPU"} else printf "%.2f:1", g/c }')"
    ```

    **Why it is wrong** — An aggregated call-graph line representing hundreds of samples counts as one, while duplicate appearances in different report sections count repeatedly, making both the frame totals and ratio unrelated to sampled execution counts.

19. **What** — Most GPU/CPU discriminators are too broad to establish which terminal-pane renderer was used.

    **Where** — Lines 137–141 and 203:

    ```bash
      ghostty|Ghostty)   GPU_RE='Metal|renderer.*[Mm]etal'; CPU_RE='CoreText|CGContext' ;;
      wezterm*|WezTerm*) GPU_RE='wgpu|Metal';              CPU_RE='CoreText|CGContext|glyphcache' ;;
      kitty)             GPU_RE='OpenGL|CGL|AGX|gl[A-Z]';  CPU_RE='CoreText|CGContext' ;;
      alacritty|Alacritty) GPU_RE='OpenGL|CGL|AGX|gl[A-Z]'; CPU_RE='CoreText|CGContext' ;;
      *)                 GPU_RE='Metal|AGX|IOGPU|wgpu|CGL|OpenGL'; CPU_RE='CoreText|CGContext|CGSBlend' ;;
      if [ "$GPU_N" -gt 0 ] || [ "$CPU_N" -gt 0 ]; then GPU_VERDICT="OK"; fi
    ```

    **Why it is wrong** — Calls from menus, window chrome, font shaping, or glyph preparation can match these framework-wide patterns even when pane drawing uses a different path, yet any such match resolves the profile.

20. **What** — Drift rates divide by the requested sleep interval rather than the actual time between T0 and T1.

    **Where** — Lines 191, 198, 217–218, and 226–227:

    ```bash
    T0_APP="$(reading "$PID" "$CENSUS_OWNER")"; T0_WS="$(reading "${WS_PID:-0}" 'Window Server')"
    if run 120 sample "$PID" "$SAMPLE_SECS" -f "$SAMPLE_F" >/dev/null 2>&1 && [ -s "$SAMPLE_F" ]; then
      sleep "$INTERVAL"
      T1_APP="$(reading "$PID" "$CENSUS_OWNER")"; T1_WS="$(reading "${WS_PID:-0}" 'Window Server')"
        awk -v a="$a" -v b="$b" -v s="$INTERVAL" -v l="$label" \
          'BEGIN{ d=b-a; printf "    %-14s %+.0f over %ds  = %+.1f/hr\n", l, d, s, d*3600/s }'
    ```

    **Why it is wrong** — The elapsed time also includes the T0 WindowServer reading, GPU sampling, processing overhead, and the T1 reading, so growth over that longer period is divided by a smaller duration and overstated per hour.

21. **What** — Per-pane normalization converts unavailable `top` values into measured zeros.

    **Where** — Lines 237–241:

    ```bash
      awk -v p="$PANES" -v r="$T0_APP" 'BEGIN{ split(r,f,"\t");
        printf "    threads/pane   %.2f\n", f[3]/p;
        printf "    ports/pane     %.2f\n", f[4]/p;
        printf "    MB/pane        %.1f\n",  f[2]/p;
        printf "    cpu%%/pane      %.2f\n", f[1]/p }'
    ```

    **Why it is wrong** — When `T0_APP` contains `NA`, `awk` coerces those strings to numeric zero and prints `0.00` or `0.0`, erasing the distinction between no measurement and an actual zero.

22. **What** — The JSONL result omits every T1 and WindowServer measurement even when the row is marked fully comparable.

    **Where** — Lines 245–247:

    ```bash
      printf '{"ts":"%s","app":"%s","pid":%s,"panes":%s,"interval":%s,"t0":"%s","gpu_frames":"%s","cpu_frames":"%s","verdict":"%s"}\n' \
        "$(date -u +%FT%TZ)" "$APP" "$PID" "${PANES:-0}" "$INTERVAL" \
        "$(tr '\t' ',' <<<"$T0_APP")" "$GPU_N" "$CPU_N" "$VERDICT" >> "$OUT"
    ```

    **Why it is wrong** — For an interval run, the persisted record cannot reconstruct the drift or inspect WindowServer cost despite potentially claiming `verdict=OK`.

23. **What** — The JSONL verdict is written before the missing-GPU downgrade is applied.

    **Where** — Lines 231, 247, and 251:

    ```bash
      VERDICT="OK"
        "$(tr '\t' ',' <<<"$T0_APP")" "$GPU_N" "$CPU_N" "$VERDICT" >> "$OUT"
    [ "$GPU_VERDICT" = OK ] || VERDICT="PARTIAL"
    ```

    **Why it is wrong** — With a positive interval and no matching GPU symbols, the file receives `"verdict":"OK"` while the final console line reports `verdict=PARTIAL`.

24. **What** — User-controlled values are interpolated into JSON without JSON escaping or validation as JSON numbers.

    **Where** — Lines 245–247:

    ```bash
      printf '{"ts":"%s","app":"%s","pid":%s,"panes":%s,"interval":%s,"t0":"%s","gpu_frames":"%s","cpu_frames":"%s","verdict":"%s"}\n' \
        "$(date -u +%FT%TZ)" "$APP" "$PID" "${PANES:-0}" "$INTERVAL" \
        "$(tr '\t' ',' <<<"$T0_APP")" "$GPU_N" "$CPU_N" "$VERDICT" >> "$OUT"
    ```

    **Why it is wrong** — An app name containing a quote or backslash breaks the JSON string, while accepted numeric spellings such as `--panes 01` are emitted as invalid JSON numbers.

25. **What** — Failure to append the requested result is reported as a successful append and does not make the script fail.

    **Where** — Lines 247–248 and 252:

    ```bash
        "$(tr '\t' ',' <<<"$T0_APP")" "$GPU_N" "$CPU_N" "$VERDICT" >> "$OUT"
      echo "  appended → $OUT"
    echo "verdict=$VERDICT"
    ```

    **Why it is wrong** — If `OUT` is unwritable or its directory does not exist, the failed redirection is ignored, the script prints `appended`, and the final successful `echo` leaves an exit status of 0.