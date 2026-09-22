Seventeen defects, ordered roughly by impact.

---

### 1. GPU "path taken" counts loaded libraries, not sampled frames

**What:** The discriminator regexes are grepped over the entire `sample` report, including its "Binary Images" list of loaded frameworks, so a framework being *loaded* counts as its render path being *taken*.

**Where:** `scripts/terminal-bench.sh` lines 199, 200, 203
```bash
  GPU_N="$(grep -cE "$GPU_RE" "$SAMPLE_F" || true)"
  CPU_N="$(grep -cE "$CPU_RE" "$SAMPLE_F" || true)"
  if [ "$GPU_N" -gt 0 ] || [ "$CPU_N" -gt 0 ]; then GPU_VERDICT="OK"; fi
```

**Why:** iTerm2's patterns are class names, but every other app's patterns match image-list lines:
- `Metal.framework`, `AGXMetal…`, `IOGPU.framework` and `OpenGL.framework` match GPU_RE.
- `CoreText.framework` matches CPU_RE.

Every AppKit app has these loaded, so GPU_N and CPU_N are ≥1 even when no sampled stack touched either path (for example, an idle Ghostty during the 5 s window). As a result:
- The 0:0 guard can never fire.
- GPU_VERDICT becomes OK.
- The ratio is partly a count of linked frameworks.

That is exactly the "loaded GPU driver" evidence the header says can never establish "used".

### 2. A failed `top` reading still ends in `verdict=OK`

**What:** `reading`'s failure status is discarded and `VERDICT="OK"` is set unconditionally after the hold, so the documented NO-DATA/exit 3 for "top returned nothing" never happens, and OK is issued without two readings.

**Where:** lines 151, 191, 218, 231
```bash
  if [ -z "$line" ]; then printf 'NA\tNA\tNA\tNA\tNA\tNA\tNA\n'; return 1; fi
T0_APP="$(reading "$PID" "$CENSUS_OWNER")"; T0_WS="$(reading "${WS_PID:-0}" 'Window Server')"
  T1_APP="$(reading "$PID" "$CENSUS_OWNER")"; T1_WS="$(reading "${WS_PID:-0}" 'Window Server')"
  VERDICT="OK"
```

**Why:** Suppose the app quits or crashes during the hold, so `top -pid` finds nothing at T1. The T1 row is all-NA and every drift line prints `NA`, yet VERDICT is still set to OK. With the GPU profile already taken at T0, the run ends `verdict=OK`, exits 0, and appends an OK row. The header defines OK as "both readings taken" (line 43) and requires NO-DATA/exit 3 when top returns nothing (line 47).

### 3. A missing window census never downgrades the verdict

**What:** Nothing on the verdict path consults `CENSUS_OK` or NA window columns.

**Where:** lines 86, 180, 231, 251
```bash
[ -f "$CENSUS_SRC" ] || echo "terminal-bench: ⚠ census source not found under REPO=$REPO" >&2
[ "$CENSUS_OK" = 1 ] || echo "  ⚠ window census unavailable (swiftc failed) — window columns report NA"
  VERDICT="OK"
[ "$GPU_VERDICT" = OK ] || VERDICT="PARTIAL"
```

**Why:** win/off/mpx are NA in both readings in any of these cases:
- swiftc fails.
- The source isn't under REPO (line 86 only warns).
- The census returns no row for the owner.

Line 231 still sets OK, and line 251 checks only the GPU verdict. Header line 44 says a missing window census yields PARTIAL. This is the "report NA for every window column, and still exit 0" failure that lines 68–71 describe, now labelled `verdict=OK`.

### 4. The JSONL row is written before the GPU downgrade

**What:** The results row is appended with `$VERDICT` before line 251 downgrades it for a failed GPU profile, and the GPU verdict itself is never recorded.

**Where:** lines 247, 251
```bash
    "$(tr '\t' ',' <<<"$T0_APP")" "$GPU_N" "$CPU_N" "$VERDICT" >> "$OUT"
[ "$GPU_VERDICT" = OK ] || VERDICT="PARTIAL"
```

**Why:** Take `--interval 300 --out f` with a GPU profile that failed or came back 0:0:
1. Line 231 sets OK.
2. Line 247 appends `"verdict":"OK"`.
3. Line 251 prints `verdict=PARTIAL`.

The persisted row claims a full comparable row. In the 0:0 case it also stores `"gpu_frames":"0","cpu_frames":"0"` as measured zeros, which lines 201–202 say must not be read that way.

### 5. A WindowServer lookup miss silently measures kernel_task

**What:** When `pgrep` returns no WindowServer pid, `reading` is called with pid 0, which on macOS is kernel_task.

**Where:** lines 129, 191 (same at 218)
```bash
WS_PID="$(pgrep -x WindowServer | head -1 || true)"
T0_APP="$(reading "$PID" "$CENSUS_OWNER")"; T0_WS="$(reading "${WS_PID:-0}" 'Window Server')"
```

**Why:** `top -l 2 -pid 0` returns kernel_task's row, and `^[[:space:]]*0[[:space:]]` matches it. The "WS" row then shows kernel_task's CPU/MEM/#TH/#PORTS beside WindowServer's census columns, with no warning. The WindowServer lookup has no ps fallback, although lines 109–115 document that pgrep silently misses processes on this box.

### 6. The two lookup tables accept different spellings of the same app

**What:** An alias accepted by the name table falls through to the generic discriminator, or the reverse, because the second `case` uses different patterns.

**Where:** lines 98, 100, 101, 136, 138, 139
```bash
  wezterm|WezTerm) PROC_NAMES="wezterm-gui WezTerm wezterm"; CENSUS_OWNER="WezTerm" ;;
  kitty|kitty.app) PROC_NAMES="kitty";                        CENSUS_OWNER="kitty" ;;
  iTerm2|iTerm)    PROC_NAMES="iTerm2";                       CENSUS_OWNER="iTerm2" ;;
  iTerm2)            GPU_RE='iTermMetalDriver';        CPU_RE='iTermTextDrawingHelper' ;;
  wezterm*|WezTerm*) GPU_RE='wgpu|Metal';              CPU_RE='CoreText|CGContext|glyphcache' ;;
  kitty)             GPU_RE='OpenGL|CGL|AGX|gl[A-Z]';  CPU_RE='CoreText|CGContext' ;;
```

**Why:**
- **`--app iTerm`:** finds the iTerm2 process but gets the generic `Metal|AGX|IOGPU|wgpu|CGL|OpenGL` / `CoreText|CGContext|CGSBlend` instead of the iTerm2 class names. The same process then yields entirely different counts and ratio depending on spelling, and the row is filed under a different `"app"` name.
- **`--app kitty.app`:** also gets the generic regexes.
- **`--app wezterm-gui`:** matches the `wezterm*` glob but not the name table, so the census owner becomes `wezterm-gui` instead of `WezTerm`. That is the mismatch lines 94–96 say the table exists to prevent.

### 7. Alacritty is missing from the process/owner table

**What:** Alacritty is one of the five terminals the header says are measured and has a discriminator entry, but it has no name-table entry, so it falls to the row that assumes process name = owner name = `--app`.

**Where:** lines 102, 140
```bash
  *)               PROC_NAMES="$APP";                         CENSUS_OWNER="$APP" ;;
  alacritty|Alacritty) GPU_RE='OpenGL|CGL|AGX|gl[A-Z]'; CPU_RE='CoreText|CGContext' ;;
```

**Why:** Alacritty's executable is `alacritty`, but its window owner is `Alacritty`.
- **`--app Alacritty`:** both the pgrep and ps-basename matches are case-sensitive and miss, giving NO-DATA while Alacritty is running.
- **`--app alacritty`:** finds the process, but the census is asked for owner `alacritty`. Unless the census compares case-insensitively, the window columns come back empty, and per #3 the run still ends OK.

### 8. The drift rate divides by INTERVAL, not by the real elapsed time

**What:** Drift is divided by INTERVAL, but the gap between the T0 and T1 samples also contains the WindowServer reading and the whole `sample` run.

**Where:** lines 198, 217, 226, 227
```bash
if run 120 sample "$PID" "$SAMPLE_SECS" -f "$SAMPLE_F" >/dev/null 2>&1 && [ -s "$SAMPLE_F" ]; then
  sleep "$INTERVAL"
    awk -v a="$a" -v b="$b" -v s="$INTERVAL" -v l="$label" \
      'BEGIN{ d=b-a; printf "    %-14s %+.0f over %ds  = %+.1f/hr\n", l, d, s, d*3600/s }'
```

**Why:** After T0_APP, the script runs:
1. Another `top -l 2` plus a census for WindowServer.
2. `sample` for SAMPLE_SECS plus symbolication.
3. The INTERVAL sleep.

So "over 180s" is always false, and every /hr figure is inflated by elapsed/INTERVAL: a few percent at the defaults, roughly 2× with `--interval 30 --sample-secs 30`. The header claims the readings are "a known interval apart".

### 9. The GPU/CPU counts are line counts, not sample counts

**What:** `grep -c` counts matching lines and ignores the per-node sample counts that `sample` prints, so `gpu_frames`, `cpu_frames` and `ratio` don't measure how often each path was on the stack.

**Where:** lines 199, 200, 207
```bash
  GPU_N="$(grep -cE "$GPU_RE" "$SAMPLE_F" || true)"
  CPU_N="$(grep -cE "$CPU_RE" "$SAMPLE_F" || true)"
    "$(awk -v g="$GPU_N" -v c="$CPU_N" 'BEGIN{ if(c==0){print "all-GPU"} else printf "%.2f:1", g/c }')"
```

**Why:** Each call-graph line is one distinct node, prefixed by the number of samples it appeared in. Consider two paths:
- A path present in 4,000 of 5,000 samples through 3 nodes counts 3.
- A path present in 10 samples spread over 40 nodes counts 40.

The printed "profile" ratio can therefore invert the real split.

### 10. The tab-only IFS split still drops empty fields

**What:** `IFS=$'\t' read` collapses consecutive tabs, so `show` has the same empty-field column shift that the comment at lines 182–183 says it prevents.

**Where:** line 186
```bash
  IFS=$'\t' read -r cpu mem th ports win off mpx <<<"$row"
```

**Why:** Tab is IFS whitespace in bash, so a run of tabs counts as one delimiter and empty fields vanish. Any empty non-final field shifts every later value one column left. Examples are `th` from a short `top` line or an empty census cell. The output then shows the ports value under `th=` and the window count under `ports=`.

### 11. Per-pane normalisation prints NA as 0.00

**What:** The per-pane block passes NA fields to awk, which coerces them to 0.

**Where:** lines 237–241
```bash
  awk -v p="$PANES" -v r="$T0_APP" 'BEGIN{ split(r,f,"\t");
    printf "    threads/pane   %.2f\n", f[3]/p;
    printf "    ports/pane     %.2f\n", f[4]/p;
    printf "    MB/pane        %.1f\n",  f[2]/p;
    printf "    cpu%%/pane      %.2f\n", f[1]/p }'
```

**Why:** If the T0 `top` reading failed and `--panes` > 0, the block prints `0.00` for threads, ports, MB and cpu per pane. An instrument failure is shown as measured zeros, the distinction the header says a consumer must be able to make.

### 12. A stale census binary is used after a failed rebuild

**What:** `CENSUS_OK` records a failed rebuild, but `reading` gates the census on `-x "$CENSUS_BIN"`, so the old binary is used while the banner says the columns are NA.

**Where:** lines 175, 177, 180, 163
```bash
  if ! run 300 swiftc -O "$CENSUS_SRC" -o "$CENSUS_BIN" 2>/dev/null; then CENSUS_OK=0; fi
[ -x "$CENSUS_BIN" ] || CENSUS_OK=0
[ "$CENSUS_OK" = 1 ] || echo "  ⚠ window census unavailable (swiftc failed) — window columns report NA"
  if [ -x "$CENSUS_BIN" ]; then
```

**Why:** Suppose the source is edited, making it newer than the binary, and the rebuild then fails (compile error, missing swiftc, or timeout). The previous executable stays in place. The banner says "report NA", but every reading fills win/off/mpx from a census that no longer matches its source, and `cut -f3/-f5/-f7` may no longer fit its column layout.

### 13. "appended" is printed even when the append failed

**What:** The success message is printed whether or not the append succeeded.

**Where:** lines 247, 248
```bash
    "$(tr '\t' ',' <<<"$T0_APP")" "$GPU_N" "$CPU_N" "$VERDICT" >> "$OUT"
  echo "  appended → $OUT"
```

**Why:** If `--out` points into a non-existent directory or at an unwritable file, the redirection fails and `printf` never runs. Line 248 still reports "appended", and the run exits 0. The row is lost while the output says it was recorded.

### 14. The JSONL row has no T1 reading or drift

**What:** The only persisted record carries the T0 reading but no T1 reading, drift, or WindowServer data, yet it can be stamped OK.

**Where:** line 245
```bash
  printf '{"ts":"%s","app":"%s","pid":%s,"panes":%s,"interval":%s,"t0":"%s","gpu_frames":"%s","cpu_frames":"%s","verdict":"%s"}\n' \
```

**Why:** With `--interval 300 --out f`, drift exists only on stdout, although the header calls it "the only reading that supports a leak verdict". The results file cannot compare terminals on the leak axis, even though OK means "a full comparable row".

### 15. A value flag given last causes an infinite loop

**What:** `shift 2` with only one argument left fails without shifting, and nothing stops the loop.

**Where:** lines 56–60 (for example line 56)
```bash
    --app)         APP="${2:-}"; shift 2 ;;
```

**Why:** Running `terminal-bench.sh --app iTerm2 --out` (or any value flag as the last argument) hits this. There is no `set -e`, so `$1` stays the same flag and the `while` loop spins forever instead of reporting a usage error.

### 16. The census binary cache is keyed only by uid and mtime

**What:** The compiled census is cached at a path keyed only by uid, and staleness is judged only by mtime.

**Where:** lines 87, 174
```bash
CENSUS_BIN="${TMPDIR:-/tmp}/window-census.$(id -u)"
if [ ! -x "$CENSUS_BIN" ] || [ "$CENSUS_SRC" -nt "$CENSUS_BIN" ]; then
```

**Why:** Two checkouts with different census sources (via `CC_REPO` or worktrees) share one binary. A checkout whose source is older than the last build silently runs the other checkout's census. With TMPDIR unset, any executable already at `/tmp/window-census.<uid>` is run without any provenance check.

### 17. `--help` truncates the header

**What:** `--help` prints lines 1–45, but the header runs to line 47.

**Where:** line 61
```bash
    -h|--help)     sed -n '1,45p' "$0"; exit 0 ;;
```

**Why:** The help text stops mid-sentence and omits the `verdict=NO-DATA … (exit 3)` token and exit code that a caller needs to recognise "instrument did not run".
