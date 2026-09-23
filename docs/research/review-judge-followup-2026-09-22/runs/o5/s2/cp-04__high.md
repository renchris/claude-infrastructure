## Defects

---

**1. The JSONL row is written with a verdict that the script then contradicts on stdout.**

**Where** — line 247 (inside the `--out` block) vs. line 251:
```bash
    "$(tr '\t' ',' <<<"$T0_APP")" "$GPU_N" "$CPU_N" "$VERDICT" >> "$OUT"
```
```bash
[ "$GPU_VERDICT" = OK ] || VERDICT="PARTIAL"
```

**Why it is wrong** — With `--interval 300 --out file`, if the `sample` discriminator matched nothing (`GPU_VERDICT=NO-DATA`), `VERDICT` is still `"OK"` when the JSON line is appended at 247; the downgrade at 251 happens afterwards. The file — the machine-parsable artifact the header says must distinguish "measured zero" from "the instrument did not run" — records `"verdict":"OK"` while the terminal prints `verdict=PARTIAL` for the same run. The two consumers disagree about the same measurement.

---

**2. `verdict=OK` is emitted even when the window census never ran, contrary to the documented definition.**

**Where** — line 231, with line 180:
```bash
  VERDICT="OK"
```
```bash
[ "$CENSUS_OK" = 1 ] || echo "  ⚠ window census unavailable (swiftc failed) — window columns report NA"
```

**Why it is wrong** — Line 44 defines `PARTIAL` as "readings taken, but at least one of {drift, GPU profile, window census} is missing". `CENSUS_OK=0` (swiftc absent, compile failure, missing source) only prints a warning; it never touches `VERDICT`. A run where `win`/`off`/`mpx` are `NA` on every row, and where all three window-related drift lines print `NA`, still files `verdict=OK` — "a full comparable row" — into the bake-off. This is precisely the "silently report NA for every window column, and still exit 0" outcome the comment at lines 70–71 says the script is built to prevent.

---

**3. A reading that returns no data never produces `NO-DATA`; its failure status is discarded.**

**Where** — line 151, consumed at lines 191 and 218:
```bash
  if [ -z "$line" ]; then printf 'NA\tNA\tNA\tNA\tNA\tNA\tNA\n'; return 1; fi
```
```bash
T0_APP="$(reading "$PID" "$CENSUS_OWNER")"; T0_WS="$(reading "${WS_PID:-0}" 'Window Server')"
```

**Why it is wrong** — Line 47 promises `verdict=NO-DATA ... or top returned nothing (exit 3)`. But `reading`'s `return 1` is swallowed by command substitution and never tested. If the app exits between PID resolution and the `top` call, or `top` is killed by the 30 s timeout, `T0_APP` is the all-`NA` row, the script continues, prints `cpu=NA mem=NAMB`, computes drift as `NA`, and (with `--interval > 0` and a GPU match) ends at `verdict=OK` with exit 0. The only path to `NO-DATA` is the pgrep/ps miss at lines 125–128.

---

**4. When `WindowServer` is not found, the script measures pid 0 — `kernel_task` — and labels it as the window server.**

**Where** — lines 191 and 218:
```bash
T0_APP="$(reading "$PID" "$CENSUS_OWNER")"; T0_WS="$(reading "${WS_PID:-0}" 'Window Server')"
```

**Why it is wrong** — If line 129 yields nothing, `${WS_PID:-0}` substitutes `0`. On macOS pid 0 is `kernel_task`, a real, always-present process, so `top -l 2 -pid 0` returns a populated line and the grep `^[[:space:]]*0[[:space:]]` matches it. The output rows `T0 WS` / `T1 WS` then carry kernel_task's CPU, memory, thread and port counts presented as WindowServer's — the exact axis (WindowServer saturation and unbounded mach-port growth) the file exists to measure. There is no indication in the output that the subject was substituted.

---

**5. WindowServer's pid is resolved with `pgrep -x` alone — the method this same file documents as unreliable on this box — with no ps-comm fallback.**

**Where** — line 129:
```bash
WS_PID="$(pgrep -x WindowServer | head -1 || true)"
```

**Why it is wrong** — Lines 109–118 record that `pgrep -x` cannot see iTerm2 here because macOS stored p_comm as the first 16 characters of the full executable path. WindowServer lives at `/System/Library/PrivateFrameworks/SkyLight.framework/.../WindowServer`, so it is subject to the identical accounting-name truncation, and the basename fallback built at lines 119–124 is applied only to `$APP`, never to WindowServer. When the lookup fails the result is not a loud miss but defect 4: silent kernel_task numbers.

---

**6. The GPU discriminator counts matching *lines anywhere in the sample file*, including the loaded-library listing, so linkage alone can produce a GPU verdict.**

**Where** — lines 199–200, with the generic pattern at line 141:
```bash
  GPU_N="$(grep -cE "$GPU_RE" "$SAMPLE_F" || true)"
```
```bash
  *)                 GPU_RE='Metal|AGX|IOGPU|wgpu|CGL|OpenGL'; CPU_RE='CoreText|CGContext|CGSBlend' ;;
```

**Why it is wrong** — `sample`'s output ends with a binary-images section naming every loaded image, e.g. `/System/Library/Frameworks/Metal.framework/Metal` and the AGX driver bundle. For any app taking the generic branch (and for `--app iTerm`/`kitty.app`, see defect 7), a process that links Metal but rasterises every glyph on the CPU still yields `GPU_N > 0`. If its CPU symbols also miss, `CPU_N` is 0 and line 207 prints `ratio=all-GPU`. That is existence-of-a-fast-path evidence reported as path-taken evidence — the error lines 10–13 state the script was written to avoid. Separately, `grep -c` counts distinct stack-frame *lines*, not sample weights, so the value labelled `gpu_frames` and the `%.2f:1` ratio are not a CPU:GPU workload ratio.

---

**7. `--app iTerm` and `--app kitty.app` resolve a process but silently fall through to the generic GPU discriminator.**

**Where** — lines 100–101 vs. lines 136, 139:
```bash
  kitty|kitty.app) PROC_NAMES="kitty";                        CENSUS_OWNER="kitty" ;;
  iTerm2|iTerm)    PROC_NAMES="iTerm2";                       CENSUS_OWNER="iTerm2" ;;
```
```bash
  iTerm2)            GPU_RE='iTermMetalDriver';        CPU_RE='iTermTextDrawingHelper' ;;
```

**Why it is wrong** — The second `case` at line 135 has no `iTerm` or `kitty.app` alternative, so those spellings hit `*)` at line 141. `--app iTerm` and `--app iTerm2` measure the same process with *different* instruments: the first uses the weak framework-level regex instead of the `iTermMetalDriver`/`iTermTextDrawingHelper` pair. The resulting rows are filed as comparable (line 4 claims "measured by the same instrument") when they are not, and the incumbent's numbers depend on how the user spelled its name.

---

**8. Alacritty is missing from the process/owner table, so its window census silently returns nothing.**

**Where** — lines 97–103 (no `alacritty` branch) vs. line 140:
```bash
  *)               PROC_NAMES="$APP";                         CENSUS_OWNER="$APP" ;;
```
```bash
  alacritty|Alacritty) GPU_RE='OpenGL|CGL|AGX|gl[A-Z]'; CPU_RE='CoreText|CGContext' ;;
```

**Why it is wrong** — Alacritty is named in the header (line 3) and in the GPU table, but not in the name table, so `--app alacritty` sets `CENSUS_OWNER="alacritty"` while the CGWindow owner string is `Alacritty`. The census matches no owner, `$c` is empty, and `win`/`off`/`mpx` stay `NA` — without any warning, because `CENSUS_OK` is still 1. This is the WezTerm failure described at lines 93–96, except it degrades to silent NA instead of a loud NO-DATA, and (per defect 2) the run still files `verdict=OK`.

---

**9. Per-pane normalisation divides `NA` fields and prints the result as `0.00`.**

**Where** — lines 237–241:
```bash
  awk -v p="$PANES" -v r="$T0_APP" 'BEGIN{ split(r,f,"\t");
    printf "    threads/pane   %.2f\n", f[3]/p;
```

**Why it is wrong** — When `reading` emitted the all-`NA` row (defect 3), or when only the census columns are `NA`, awk coerces `"NA"` to 0. With `--panes 30` the output reads `threads/pane 0.00`, `ports/pane 0.00`, `MB/pane 0.0`, `cpu%/pane 0.00` — a measured zero, which for the thread-per-pane axis (lines 18–21) is the single most favourable possible result for a challenger. The failure to measure is rendered as the ideal measurement.

---

**10. The drift rate is computed from the nominal `--interval`, but the two readings are further apart than that.**

**Where** — line 227:
```bash
      'BEGIN{ d=b-a; printf "    %-14s %+.0f over %ds  = %+.1f/hr\n", l, d, s, d*3600/s }'
```

**Why it is wrong** — Between `T0_APP` (line 191) and `T1_APP` (line 218) the script also runs the T0 WindowServer reading, two `top -l 2` invocations (~2 s each), up to two census invocations, and `sample` for `SAMPLE_SECS` (default 5). Actual elapsed time is roughly `INTERVAL + 10 s`, but `s` is `INTERVAL`. With `--interval 60` the reported `/hr` figures are overstated by ~15%; the header calls this "a known interval apart" (line 28), and the interval is assumed rather than measured.

---

**11. A trailing option without its value sends the argument loop into an infinite spin.**

**Where** — lines 56–60, e.g.:
```bash
    --app)         APP="${2:-}"; shift 2 ;;
```

**Why it is wrong** — Invoked as `terminal-bench.sh --app` (or with `--interval`, `--out`, etc. last), `$#` is 1, so `shift 2` fails and shifts nothing. `$1` is still `--app`, the `while [ $# -gt 0 ]` condition still holds, and there is no `set -e`. The script loops forever without producing a verdict line or an exit code — a consumer waiting on the last line hangs rather than receiving the documented `exit 2`.

---

**12. `--help` truncates the help text mid-sentence and omits the `NO-DATA` token.**

**Where** — line 61:
```bash
    -h|--help)     sed -n '1,45p' "$0"; exit 0 ;;
```

**Why it is wrong** — The header block runs to line 47. Line 45 ends `` `--interval 0` always yields PARTIAL by construction: a single`` — so `--help` cuts off in the middle of the `PARTIAL` description and never prints line 47, the `verdict=NO-DATA ... (exit 3)` entry. A user who reads only `--help` learns two of the three verdict tokens and does not learn about exit 3.

---

**13. The "fail loud" guard on a missing census source does not fail, and a stale compiled binary is used in its place.**

**Where** — lines 85–86 and 174:
```bash
# Fail loud rather than degrade to NA-everywhere if the root resolved somewhere without the tool.
[ -f "$CENSUS_SRC" ] || echo "terminal-bench: ⚠ census source not found under REPO=$REPO" >&2
```
```bash
if [ ! -x "$CENSUS_BIN" ] || [ "$CENSUS_SRC" -nt "$CENSUS_BIN" ]; then
```

**Why it is wrong** — The comment states the intent to fail; the code only writes to stderr and continues, which is the NA-everywhere degradation it names. Worse, `CENSUS_BIN` is keyed only on uid (`window-census.$(id -u)`), shared across checkouts and branches. If any earlier run left a binary there, `[ "$CENSUS_SRC" -nt "$CENSUS_BIN" ]` is false for a *nonexistent* source, so no rebuild is attempted, `CENSUS_OK` stays 1, and window counts are produced by a binary built from a different (possibly missing) revision of the source — window numbers filed as `OK` on an unverified instrument.

---

**14. Short census output bypasses the `NA` guard in `drift`, so missing fields are differenced as zero.**

**Where** — line 166 and line 225:
```bash
      win="$(cut -f3 <<<"$c")"; off="$(cut -f5 <<<"$c")"; mpx="$(cut -f7 <<<"$c")"
```
```bash
    [ "$a" = NA ] || [ "$b" = NA ] && { printf '    %-14s NA\n' "$label"; return; }
```

**Why it is wrong** — If the census emits fewer than 7 columns, `cut` yields empty strings, not `NA`. The guard tests only for the literal `NA`, so `drift 6 "offscreen win"` passes `a=""`/`b=""` to awk, which coerces them to 0 and prints `+0 over 300s = +0.0/hr`. A field the instrument never obtained is reported as a confirmed zero-leak reading — the leak verdict the header (lines 28–31) says this line alone is entitled to support.

---

**15. `top` output is split on whitespace assuming `COMMAND` is a single field.**

**Where** — lines 152–155:
```bash
  cpu="$(awk '{print $3}' <<<"$line")"
```

**Why it is wrong** — `-stats pid,command,cpu,mem,th,ports` puts `COMMAND` in position 2. For any `--app` whose accounting name contains a space (reachable via the generic `*)` branch at line 102, which accepts an arbitrary app name), `$3` is the tail of the command rather than `%CPU`, and every subsequent field shifts: memory is read from the CPU column, threads from memory, ports from threads. The `mem` awk then finds no `K/M/G` suffix and prints a plausible-looking number, so the corruption is not visible in the output — the same column-shift failure the comment at lines 182–183 guards against in `show`.

---

**16. `--panes` and `--interval` values are never validated, and go verbatim into the JSON as bare numbers.**

**Where** — line 246:
```bash
    "$(date -u +%FT%TZ)" "$APP" "$PID" "${PANES:-0}" "$INTERVAL" \
```

**Why it is wrong** — With `--panes 30x`, the tests at lines 215 and 235 write `integer expression expected` to stderr and, with no `set -e`, execution continues; the drift and per-pane blocks are skipped. The appended line then contains `"panes":30x` — unquoted and not a number — so the whole JSONL record fails to parse, and the run reports `appended → $OUT` and a `verdict=` line as if it had filed successfully.
