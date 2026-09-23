I read the whole script and traced the verdict, reading, GPU-profile, and drift paths. I found 10 defects. The first four affect the machine-parsable verdict and the persisted row directly.

**1. The JSONL row is appended before the final verdict downgrade, so the file records OK for runs whose GPU profile did not resolve.**

Where: lines 244-251

```bash
    "$(tr '\t' ',' <<<"$T0_APP")" "$GPU_N" "$CPU_N" "$VERDICT" >> "$OUT"
...
[ "$GPU_VERDICT" = OK ] || VERDICT="PARTIAL"
```

Why: with an interval above zero, the drift block sets the verdict to OK at line 231. If the GPU sample failed or matched nothing, the JSONL gets `"verdict":"OK"` while stdout prints `verdict=PARTIAL`. The persisted file, which is what a consumer parses, contradicts the documented contract at lines 43-45 and the terminal output of the same run.

**2. An unavailable window census never downgrades the verdict, so a run with NA in every window column is filed as OK.**

Where: line 86, line 231, line 251

```bash
[ -f "$CENSUS_SRC" ] || echo "terminal-bench: ⚠ census source not found under REPO=$REPO" >&2
  VERDICT="OK"
[ "$GPU_VERDICT" = OK ] || VERDICT="PARTIAL"
```

Why: the verdict only considers the interval and the GPU profile. When the census source is missing or swiftc fails, the script warns, reports NA for windows, offscreen and mpx, prints verdict OK, and exits 0. Lines 44-45 say a missing census must yield PARTIAL, and lines 70-71 describe exactly this outcome as the incident class the guard exists to prevent. The comment at line 85 says "fail loud", but line 86 only warns and continues.

**3. The GPU discriminator counts matching lines across the whole sample file, including the Binary Images section, so loaded-library evidence is reported as frames and the 0:0 guard can never fire.**

Where: lines 199-203

```bash
  GPU_N="$(grep -cE "$GPU_RE" "$SAMPLE_F" || true)"
  CPU_N="$(grep -cE "$CPU_RE" "$SAMPLE_F" || true)"
  if [ "$GPU_N" -gt 0 ] || [ "$CPU_N" -gt 0 ]; then GPU_VERDICT="OK"; fi
```

Why: a sample file ends with a Binary Images list of every loaded library, with full paths. For Ghostty, WezTerm, kitty and the generic case, patterns like Metal, AGX, OpenGL and CGL match those library lines whether or not any frame executed them, and CoreText matches its framework line in every GUI app. This is the "loaded driver proves nothing" error the header forbids at lines 10-13. Because CPU_N is therefore never zero, the 0:0 NO-DATA guard is unreachable and every run reports OK. Separately, grep -c counts distinct lines, not the per-line sample counts, and the "Total number in stack" and "Sort by top of stack" sections repeat each frame. The printed ratio compares tree-node counts, not time on each path.

**4. A reading that produced no top output is never detected, so a run with no data prints verdict OK and exits 0.**

Where: line 151, line 191, line 218

```bash
  if [ -z "$line" ]; then printf 'NA\tNA\tNA\tNA\tNA\tNA\tNA\n'; return 1; fi
T0_APP="$(reading "$PID" "$CENSUS_OWNER")"; T0_WS="$(reading "${WS_PID:-0}" 'Window Server')"
  T1_APP="$(reading "$PID" "$CENSUS_OWNER")"; T1_WS="$(reading "${WS_PID:-0}" 'Window Server')"
```

Why: the return code is discarded by the command substitution and nothing inspects the row for NA. If the app quits during the hold, T1 is all NA, every drift line prints NA, line 231 still sets OK, and the JSONL row is written. Line 47 says top returning nothing must be NO-DATA with exit 3.

**5. When WindowServer's pid is not found, the script measures pid 0 and labels the result as WindowServer.**

Where: line 129 and line 191

```bash
WS_PID="$(pgrep -x WindowServer | head -1 || true)"
T0_APP="$(reading "$PID" "$CENSUS_OWNER")"; T0_WS="$(reading "${WS_PID:-0}" 'Window Server')"
```

Why: the comment at lines 109-115 records that pgrep on this box drops processes. If it drops WindowServer, the fallback runs top against pid 0, which is kernel_task, and the T0 and T1 WS rows show kernel_task's cpu, memory, threads and ports under the WS label. The correct output for an unresolved pid is NA.

**6. The drift rate divides by the nominal sleep, not the actual gap between the two readings.**

Where: lines 226-227

```bash
    awk -v a="$a" -v b="$b" -v s="$INTERVAL" -v l="$label" \
      'BEGIN{ d=b-a; printf "    %-14s %+.0f over %ds  = %+.1f/hr\n", l, d, s, d*3600/s }'
```

Why: T0 is taken at line 191, then the GPU sample runs for SAMPLE_SECS at line 198, then the sleep, then two more top runs of about a second each before T1. The true elapsed time is the interval plus the sample duration plus several seconds. With a short interval and a long sample the per-hour rate is overstated by a large factor. Line 28 claims the readings are "a known interval apart".

**7. The display splitter collapses empty fields, which is the column shift the comment says it prevents.**

Where: line 186

```bash
  IFS=$'\t' read -r cpu mem th ports win off mpx <<<"$row"
```

Why: tab is an IFS whitespace character, so bash treats runs of tabs as one delimiter and drops leading and trailing ones. If any field is empty, for example a missing ports column or a short census line, every later column shifts left and ports print under the threads label. Lines 182-183 claim the opposite. The drift and per-pane paths use cut and awk split, which do preserve empty fields, so this affects only the printed rows.

**8. Accepted app aliases select different GPU discriminators, so the same app gets different numbers depending on spelling.**

Where: line 101 versus line 136, and line 100 versus line 139

```bash
  iTerm2|iTerm)    PROC_NAMES="iTerm2";                       CENSUS_OWNER="iTerm2" ;;
  iTerm2)            GPU_RE='iTermMetalDriver';        CPU_RE='iTermTextDrawingHelper' ;;
  kitty|kitty.app) PROC_NAMES="kitty";                        CENSUS_OWNER="kitty" ;;
  kitty)             GPU_RE='OpenGL|CGL|AGX|gl[A-Z]';  CPU_RE='CoreText|CGContext' ;;
```

Why: `--app iTerm` and `--app kitty.app` resolve the process correctly but fall through to the generic regex at line 141, so the GPU and CPU counts differ from a run spelled `iTerm2` or `kitty`. The JSONL also stores the alias verbatim, so the rows look like different apps. Alacritty has no row in the process table, so `--app alacritty` sets the census owner to lowercase, which will not match a case-sensitive owner comparison against the window owner name.

**9. The per-pane normalisation turns NA into zero.**

Where: lines 237-241

```bash
  awk -v p="$PANES" -v r="$T0_APP" 'BEGIN{ split(r,f,"\t");
    printf "    threads/pane   %.2f\n", f[3]/p;
```

Why: awk coerces the string NA to 0, so a failed T0 reading prints 0.00 threads per pane and 0.0 MB per pane as if measured. This compounds defect 4.

**10. Help output stops two lines short of the verdict documentation.**

Where: line 61

```bash
    -h|--help)     sed -n '1,45p' "$0"; exit 0 ;;
```

Why: the header runs through line 47, so help omits the end of the PARTIAL definition and the whole NO-DATA line, which is the token a consumer most needs to recognise.
