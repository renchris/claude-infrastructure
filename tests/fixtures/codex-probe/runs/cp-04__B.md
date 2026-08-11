1. **What** — The help output is truncated in the middle of the verdict documentation.

   **Where** — Line 61:
   ```bash
       -h|--help)     sed -n '1,45p' "$0"; exit 0 ;;
   ```

   **Why it is wrong** — Line 45 ends midway through the `PARTIAL` explanation, so `--help` omits its conclusion and the entire `NO-DATA` definition.

2. **What** — An option missing its value causes an infinite argument-processing loop.

   **Where** — Lines 56–60:
   ```bash
       --app)         APP="${2:-}"; shift 2 ;;
       --panes)       PANES="${2:-0}"; shift 2 ;;
       --interval)    INTERVAL="${2:-180}"; shift 2 ;;
       --sample-secs) SAMPLE_SECS="${2:-5}"; shift 2 ;;
       --out)         OUT="${2:-}"; shift 2 ;;
   ```

   **Why it is wrong** — If one of these options is the final argument, `shift 2` fails because only one argument remains; without `set -e`, the arguments remain unchanged and the loop repeats indefinitely.

3. **What** — Numeric option values are used without validation, allowing failed arithmetic checks to be reported as successful runs.

   **Where** — Lines 57–59, 215, and 235:
   ```bash
       --panes)       PANES="${2:-0}"; shift 2 ;;
       --interval)    INTERVAL="${2:-180}"; shift 2 ;;
       --sample-secs) SAMPLE_SECS="${2:-5}"; shift 2 ;;
   ```
   ```bash
   if [ "$INTERVAL" -gt 0 ]; then
   ```
   ```bash
   if [ "${PANES:-0}" -gt 0 ]; then
   ```

   **Why it is wrong** — For example, `--panes abc` makes `[` report an integer-expression error, but execution continues and can still finish with `verdict=OK` without producing the requested per-pane result.

4. **What** — Unknown application names containing whitespace or glob characters are split or expanded instead of being treated as one process name.

   **Where** — Lines 102, 105, and 120:
   ```bash
     *)               PROC_NAMES="$APP";                         CENSUS_OWNER="$APP" ;;
   ```
   ```bash
   for _p in $PROC_NAMES; do
   ```
   ```bash
     for _p in $PROC_NAMES; do
   ```

   **Why it is wrong** — With an application name such as `My Terminal`, the loops search separately for `My` and `Terminal` and may either return `NO-DATA` or select an unrelated process named `Terminal`.

5. **What** — The `ps` fallback cannot parse a `comm` path containing whitespace.

   **Where** — Line 121:
   ```bash
       PID="$(ps -eo pid=,comm= | awk -v want="$_p" '{n=split($2,a,"/"); if (a[n]==want) {print $1; exit}}')"
   ```

   **Why it is wrong** — When `comm` is a path such as `/Applications/My Terminal.app/Contents/MacOS/Foo`, awk places only `/Applications/My` in `$2`, so the basename comparison misses the running `Foo` process.

6. **What** — Only the first matching application process is measured.

   **Where** — Lines 106 and 121:
   ```bash
     PID="$(pgrep -x "$_p" | head -1 || true)"
   ```
   ```bash
       PID="$(ps -eo pid=,comm= | awk -v want="$_p" '{n=split($2,a,"/"); if (a[n]==want) {print $1; exit}}')"
   ```

   **Why it is wrong** — When a terminal uses multiple GUI processes, CPU, memory, threads, ports, and GPU samples come from one arbitrary process while the owner-based window census can cover all of them, producing an undercounted and internally inconsistent row.

7. **What** — Failure to find WindowServer causes PID 0 to be measured and labeled as WindowServer.

   **Where** — Lines 191 and 218:
   ```bash
   T0_APP="$(reading "$PID" "$CENSUS_OWNER")"; T0_WS="$(reading "${WS_PID:-0}" 'Window Server')"
   ```
   ```bash
     T1_APP="$(reading "$PID" "$CENSUS_OWNER")"; T1_WS="$(reading "${WS_PID:-0}" 'Window Server')"
   ```

   **Why it is wrong** — If `pgrep -x WindowServer` returns nothing, `top -pid 0` can return the kernel process, whose metrics are then printed as the Window Server readings.

8. **What** — The accepted `iTerm` and `kitty.app` aliases do not receive their application-specific GPU discriminators.

   **Where** — Lines 100–101, 136, 139, and 141:
   ```bash
     kitty|kitty.app) PROC_NAMES="kitty";                        CENSUS_OWNER="kitty" ;;
     iTerm2|iTerm)    PROC_NAMES="iTerm2";                       CENSUS_OWNER="iTerm2" ;;
   ```
   ```bash
     iTerm2)            GPU_RE='iTermMetalDriver';        CPU_RE='iTermTextDrawingHelper' ;;
   ```
   ```bash
     kitty)             GPU_RE='OpenGL|CGL|AGX|gl[A-Z]';  CPU_RE='CoreText|CGContext' ;;
   ```
   ```bash
     *)                 GPU_RE='Metal|AGX|IOGPU|wgpu|CGL|OpenGL'; CPU_RE='CoreText|CGContext|CGSBlend' ;;
   ```

   **Why it is wrong** — Invoking the same process as `--app iTerm` or `--app kitty.app` falls into the generic discriminator and can produce a different GPU result from the canonical `iTerm2` or `kitty` invocation.

9. **What** — The census cache can reuse a binary built from a different checkout or source version.

   **Where** — Lines 87 and 174:
   ```bash
   CENSUS_BIN="${TMPDIR:-/tmp}/window-census.$(id -u)"
   ```
   ```bash
   if [ ! -x "$CENSUS_BIN" ] || [ "$CENSUS_SRC" -nt "$CENSUS_BIN" ]; then
   ```

   **Why it is wrong** — All checkouts for one user share the same path, and if a foreign binary has a newer timestamp than the current source—or the current source is missing—the code treats that unrelated binary as current and executes it.

10. **What** — Taking the last matching `top` row does not prove that it came from the second sample.

    **Where** — Lines 149–150:
    ```bash
      line="$(run 30 top -l 2 -pid "$pid" -stats pid,command,cpu,mem,th,ports 2>/dev/null \
              | grep -E "^[[:space:]]*${pid}[[:space:]]" | tail -1)"
    ```

    **Why it is wrong** — If `top` emits the process during its first sample but times out or loses the process before the second, `tail -1` accepts that sole lifetime-average row as the required second reading.

11. **What** — The census header filters also discard valid data rows whose owner begins with `owner` or `verdict`.

    **Where** — Line 164:
    ```bash
        local c; c="$(run 30 "$CENSUS_BIN" --owner "$owner" --tsv 2>/dev/null | grep -v '^owner' | grep -v '^verdict' | head -1)"
    ```

    **Why it is wrong** — For an owner such as `owner-terminal`, the valid row matches `^owner`, is removed as though it were a header, and all census fields become `NA`.

12. **What** — The claimed empty-field-safe TSV split actually collapses consecutive tab delimiters.

    **Where** — Line 186:
    ```bash
      IFS=$'\t' read -r cpu mem th ports win off mpx <<<"$row"
    ```

    **Why it is wrong** — Tab is IFS whitespace, so an empty field between consecutive tabs is discarded and every subsequent value shifts into the wrong displayed column.

13. **What** — GPU-path detection scans the entire `sample` report rather than only sampled stack frames.

    **Where** — Lines 199–203:
    ```bash
      GPU_N="$(grep -cE "$GPU_RE" "$SAMPLE_F" || true)"
      CPU_N="$(grep -cE "$CPU_RE" "$SAMPLE_F" || true)"
    ```
    ```bash
      if [ "$GPU_N" -gt 0 ] || [ "$CPU_N" -gt 0 ]; then GPU_VERDICT="OK"; fi
    ```

    **Why it is wrong** — A matching name in metadata such as a loaded-framework or binary-image listing makes the count nonzero and establishes `GPU_VERDICT=OK` even when no sampled execution used that rendering path.

14. **What** — The reported GPU and CPU frame counts are counts of matching text lines, not sampled frames.

    **Where** — Lines 199–200:
    ```bash
      GPU_N="$(grep -cE "$GPU_RE" "$SAMPLE_F" || true)"
      CPU_N="$(grep -cE "$CPU_RE" "$SAMPLE_F" || true)"
    ```

    **Why it is wrong** — When one matching call-tree line represents many sample hits, `grep -c` still counts it as one, so `gpu_frames`, `cpu_frames`, and their ratio can be numerically wrong.

15. **What** — A missing `top` reading is converted to `NA` but never triggers the documented `NO-DATA` exit.

    **Where** — Lines 151, 191, 218, and 231:
    ```bash
      if [ -z "$line" ]; then printf 'NA\tNA\tNA\tNA\tNA\tNA\tNA\n'; return 1; fi
    ```
    ```bash
   T0_APP="$(reading "$PID" "$CENSUS_OWNER")"; T0_WS="$(reading "${WS_PID:-0}" 'Window Server')"
    ```
    ```bash
      T1_APP="$(reading "$PID" "$CENSUS_OWNER")"; T1_WS="$(reading "${WS_PID:-0}" 'Window Server')"
    ```
    ```bash
      VERDICT="OK"
    ```

    **Why it is wrong** — If either application `top` call returns nothing but the earlier GPU sample resolves, the failed assignment status is ignored and an interval run can finish with `verdict=OK` instead of `verdict=NO-DATA` and exit 3.

16. **What** — Missing window-census data does not prevent an `OK` verdict.

    **Where** — Lines 180, 231, and 251:
    ```bash
   [ "$CENSUS_OK" = 1 ] || echo "  ⚠ window census unavailable (swiftc failed) — window columns report NA"
    ```
    ```bash
      VERDICT="OK"
    ```
    ```bash
   [ "$GPU_VERDICT" = OK ] || VERDICT="PARTIAL"
    ```

    **Why it is wrong** — With a positive interval, a successful GPU discriminator, and a failed or unreadable census, the window fields and their drift are `NA` but the only final downgrade checks the GPU result, so the script reports `OK`.

17. **What** — Drift rates use the requested sleep duration rather than the actual elapsed time between readings.

    **Where** — Lines 191, 198, 217, and 226–227:
    ```bash
   T0_APP="$(reading "$PID" "$CENSUS_OWNER")"; T0_WS="$(reading "${WS_PID:-0}" 'Window Server')"
    ```
    ```bash
   if run 120 sample "$PID" "$SAMPLE_SECS" -f "$SAMPLE_F" >/dev/null 2>&1 && [ -s "$SAMPLE_F" ]; then
    ```
    ```bash
      sleep "$INTERVAL"
    ```
    ```bash
        awk -v a="$a" -v b="$b" -v s="$INTERVAL" -v l="$label" \
          'BEGIN{ d=b-a; printf "    %-14s %+.0f over %ds  = %+.1f/hr\n", l, d, s, d*3600/s }'
    ```

    **Why it is wrong** — The WindowServer reading, GPU sampling, and other work occur after T0 and before the sleep, so the observations are more than `INTERVAL` seconds apart and the computed per-hour rate is overstated.

18. **What** — The second reading assumes the original PID still identifies the same application process.

    **Where** — Lines 106 and 218:
    ```bash
      PID="$(pgrep -x "$_p" | head -1 || true)"
    ```
    ```bash
      T1_APP="$(reading "$PID" "$CENSUS_OWNER")"; T1_WS="$(reading "${WS_PID:-0}" 'Window Server')"
    ```

    **Why it is wrong** — If the application exits during the interval and its PID is reused, T1 measures the replacement process and reports its resource difference as application drift.

19. **What** — Per-pane normalization turns missing readings into measured zeroes.

    **Where** — Lines 237–241:
    ```bash
      awk -v p="$PANES" -v r="$T0_APP" 'BEGIN{ split(r,f,"\t");
        printf "    threads/pane   %.2f\n", f[3]/p;
        printf "    ports/pane     %.2f\n", f[4]/p;
        printf "    MB/pane        %.1f\n",  f[2]/p;
        printf "    cpu%%/pane      %.2f\n", f[1]/p }'
    ```

    **Why it is wrong** — When `T0_APP` contains `NA`, awk coerces those strings to numeric zero and prints `0.00` or `0.0`, falsely distinguishing missing data as measured zero.

20. **What** — The JSONL record omits the T1 and both WindowServer readings, so it cannot preserve the drift measurement it claims succeeded.

    **Where** — Lines 245–247:
    ```bash
      printf '{"ts":"%s","app":"%s","pid":%s,"panes":%s,"interval":%s,"t0":"%s","gpu_frames":"%s","cpu_frames":"%s","verdict":"%s"}\n' \
        "$(date -u +%FT%TZ)" "$APP" "$PID" "${PANES:-0}" "$INTERVAL" \
        "$(tr '\t' ',' <<<"$T0_APP")" "$GPU_N" "$CPU_N" "$VERDICT" >> "$OUT"
    ```

    **Why it is wrong** — On every positive-interval run, the persisted record can say `OK` but contains no T1 values from which application drift can be recovered and none of the collected WindowServer data.

21. **What** — The JSONL verdict is written before the GPU failure downgrade is applied.

    **Where** — Lines 247 and 251:
    ```bash
        "$(tr '\t' ',' <<<"$T0_APP")" "$GPU_N" "$CPU_N" "$VERDICT" >> "$OUT"
    ```
    ```bash
   [ "$GPU_VERDICT" = OK ] || VERDICT="PARTIAL"
    ```

    **Why it is wrong** — When the interval readings exist but GPU profiling returns `NO-DATA`, the JSONL record contains `"verdict":"OK"` while the final machine-readable line correctly says `verdict=PARTIAL`.

22. **What** — User-supplied values are interpolated into the JSONL output without JSON escaping or numeric validation.

    **Where** — Lines 245–247:
    ```bash
      printf '{"ts":"%s","app":"%s","pid":%s,"panes":%s,"interval":%s,"t0":"%s","gpu_frames":"%s","cpu_frames":"%s","verdict":"%s"}\n' \
        "$(date -u +%FT%TZ)" "$APP" "$PID" "${PANES:-0}" "$INTERVAL" \
        "$(tr '\t' ',' <<<"$T0_APP")" "$GPU_N" "$CPU_N" "$VERDICT" >> "$OUT"
    ```

    **Why it is wrong** — An accepted value such as `--panes abc` produces the invalid JSON token `"panes":abc`, while quotes or backslashes in an application name can break its JSON string.

23. **What** — Failure to append the JSONL record is reported as a successful append.

    **Where** — Lines 245–248:
    ```bash
      printf '{"ts":"%s","app":"%s","pid":%s,"panes":%s,"interval":%s,"t0":"%s","gpu_frames":"%s","cpu_frames":"%s","verdict":"%s"}\n' \
        "$(date -u +%FT%TZ)" "$APP" "$PID" "${PANES:-0}" "$INTERVAL" \
        "$(tr '\t' ',' <<<"$T0_APP")" "$GPU_N" "$CPU_N" "$VERDICT" >> "$OUT"
      echo "  appended → $OUT"
    ```

    **Why it is wrong** — If `OUT` is unwritable or the append fails, execution continues, prints `appended`, and ultimately exits successfully even though no result was stored.