I read the script end to end. It contains real defects — most of them in exactly the places the header says the tool exists to guard against: the verdict logic, the GPU discriminator, and the fallback paths. I found 12 defects I can point at, plus one flagged with uncertainty. Line numbers count from `#!/bin/bash` as line 1.

---

**1. The GPU frame counts are taken over the entire `sample` output file, including the Binary Images section, so loaded-but-unused frameworks count as "frames".**

- **Where:** lines 199–200
  ```bash
  GPU_N="$(grep -cE "$GPU_RE" "$SAMPLE_F" || true)"
  CPU_N="$(grep -cE "$CPU_RE" "$SAMPLE_F" || true)"
  ```
- **Why it is wrong:** `sample` always ends its report with a "Binary Images" section listing every loaded library with its path — `Metal.framework`, `OpenGL.framework`, `AGXMetal…`, `CoreText.framework` — one line each, regardless of whether any stack frame ever entered them. Every regex that names a framework (`Metal`, `OpenGL`, `CGL`, `AGX`, `IOGPU`, `CoreText` — i.e. the ghostty, wezterm, kitty, alacritty, and generic rows) therefore matches lines outside the call graph. An app that never touched the GPU still reports `gpu_frames ≥ 1`, the `0:0 → NO-DATA` guard at line 203 is satisfied vacuously, and `GPU_VERDICT=OK` is granted on loaded-not-used evidence — the precise "capability-initialized-is-not-capability-used" error the header says this instrument exists to prevent. Only iTerm2's app-specific symbol names are immune, so the incumbent is measured with a clean discriminator while every challenger's counts are inflated, breaking cross-app comparability too.

**2. The JSONL row is written before the final GPU demotion of the verdict, so a run the console reports as PARTIAL is archived as OK.**

- **Where:** line 247 (inside the `--out` block) and line 251 (after it)
  ```bash
  "$(tr '\t' ',' <<<"$T0_APP")" "$GPU_N" "$CPU_N" "$VERDICT" >> "$OUT"
  ```
  ```bash
  [ "$GPU_VERDICT" = OK ] || VERDICT="PARTIAL"
  ```
- **Why it is wrong:** with `--interval` > 0 and a failed GPU profile, `VERDICT` is still `"OK"` (set at line 231) when the JSONL line is appended; the demotion to PARTIAL happens only afterward. The machine-parsable archive — the artifact the header says must distinguish "measured zero" from "instrument did not run" — permanently records `"verdict":"OK"` for a run whose last stdout line says `verdict=PARTIAL`.

**3. `VERDICT="OK"` is set unconditionally whenever the interval elapsed, ignoring whether the window census or the T1 reading actually produced data.**

- **Where:** line 231
  ```bash
  VERDICT="OK"
  ```
- **Why it is wrong:** the spec at lines 43–45 says OK requires both readings *and* demotes to PARTIAL if any of {drift, GPU profile, window census} is missing. If `swiftc` fails (`CENSUS_OK=0`, every window column NA) or the app quits during the sleep (T1 all NA, every drift row prints NA), this line still sets OK, and line 251 only checks the GPU profile. A run with no window data and no usable drift is filed as "a full comparable row".

**4. The specified `verdict=NO-DATA` for "top returned nothing" is never implemented; the failure status of `reading()` is silently discarded.**

- **Where:** line 151 and line 191
  ```bash
  if [ -z "$line" ]; then printf 'NA\tNA\tNA\tNA\tNA\tNA\tNA\n'; return 1; fi
  ```
  ```bash
  T0_APP="$(reading "$PID" "$CENSUS_OWNER")"; T0_WS="$(reading "${WS_PID:-0}" 'Window Server')"
  ```
- **Why it is wrong:** line 47 of the header promises `verdict=NO-DATA … or top returned nothing (exit 3)`. The `return 1` is swallowed by the command substitution and no caller ever inspects it or tests the row for NA. If `top` yields nothing for the app pid, the script proceeds through drift, per-pane, and JSONL with NA rows and exits 0 with verdict OK or PARTIAL — a claimed outcome that was never checked.

**5. When `pgrep` cannot find WindowServer, the fallback pid `0` samples kernel_task and prints its numbers as WindowServer's.**

- **Where:** lines 191 and 218
  ```bash
  T0_APP="$(reading "$PID" "$CENSUS_OWNER")"; T0_WS="$(reading "${WS_PID:-0}" 'Window Server')"
  ```
- **Why it is wrong:** pid 0 on macOS is kernel_task, and `top -l 2 -pid 0` returns a valid row for it that matches the `^[[:space:]]*0[[:space:]]` grep. The script's own comments (lines 109–112) establish that `pgrep` on this box silently drops processes, so an empty `WS_PID` is a live condition — and instead of reporting NA, the run prints kernel_task's cpu/mem/threads/ports under the label `T0 WS`, fabricating the very WindowServer baseline the whole exercise revolves around.

**6. The per-pane normalisation treats NA readings as zero.**

- **Where:** lines 237–241
  ```bash
  awk -v p="$PANES" -v r="$T0_APP" 'BEGIN{ split(r,f,"\t");
  ```
- **Why it is wrong:** if the T0 reading failed (row is `NA\tNA\t…`), awk's numeric coercion turns each `NA` into 0 and the script prints `threads/pane 0.00`, `MB/pane 0.0`, etc. A dead instrument is reported as a measured zero — the exact confusion lines 41–42 say the output format must make impossible.

**7. Drift rates divide by `INTERVAL`, but the actual elapsed time between T0 and T1 also includes the GPU sampling and top runs.**

- **Where:** lines 226–227 (with T0 taken at line 191, `sample` at line 198, the sleep at line 217)
  ```bash
  awk -v a="$a" -v b="$b" -v s="$INTERVAL" -v l="$label" \
    'BEGIN{ d=b-a; printf "    %-14s %+.0f over %ds  = %+.1f/hr\n", l, d, s, d*3600/s }'
  ```
- **Why it is wrong:** T0 is read *before* the `sample` run (`SAMPLE_SECS` seconds plus symbolication, bounded only by the 120 s timeout) and before another multi-second `top -l 2` at T1, yet the per-hour rate uses `s=$INTERVAL` as the elapsed time. Every drift-per-hour figure is overstated; with `--sample-secs 60 --interval 60` the reported rate is roughly double the truth. The header's premise is "two readings, a *known* interval apart" — the interval printed is not the interval measured.

**8. App-name aliases accepted by the process table are not accepted by the GPU-discriminator table, so the same app gets different discriminators depending on spelling.**

- **Where:** line 136 (versus line 101 `iTerm2|iTerm)` and line 100 `kitty|kitty.app)`)
  ```bash
  iTerm2)            GPU_RE='iTermMetalDriver';        CPU_RE='iTermTextDrawingHelper' ;;
  ```
- **Why it is wrong:** `--app iTerm` resolves the correct process via line 101 but falls through to the generic `*` discriminator at line 141 (`kitty.app` likewise misses line 139). The generic `CoreText|CGContext|CGSBlend` counts iTerm2's glyph rasterisation as CPU-path frames where the app-specific pair would not, so `--app iTerm` and `--app iTerm2` produce materially different GPU profiles for the identical running process — defeating the "measured by the same instrument, so their numbers are comparable" premise.

**9. Alacritty — named at line 3 as a covered app and given its own discriminator row — has no row in the process/owner name table, even though that table exists precisely because process name ≠ owner name.**

- **Where:** line 102 (the fallthrough it lands on; the table is lines 97–103)
  ```bash
  *)               PROC_NAMES="$APP";                         CENSUS_OWNER="$APP" ;;
  ```
- **Why it is wrong:** Alacritty's GUI binary is lowercase `alacritty` while its window-server owner name is the capitalized app name, so no single user spelling satisfies both lookups. `--app Alacritty` finds no process and exits NO-DATA while the app is running; `--app alacritty` finds the pid but hands the census the wrong owner, so every window column silently reads NA — and via defect 3 the run can still be filed as OK.

**10. Any option given as the last argument without a value hangs the script in an infinite loop.**

- **Where:** line 56 (same pattern lines 57–60)
  ```bash
  --app)         APP="${2:-}"; shift 2 ;;
  ```
- **Why it is wrong:** with only one positional parameter left, bash's `shift 2` shifts nothing and returns non-zero; since `set -e` is not in effect, the loop repeats with `$1` still `--app`, forever. `scripts/terminal-bench.sh --app` never reaches the "--app is required" check at line 65 — it spins.

**11. `--help` prints lines 1–45, but the header runs to line 47, so the help output cuts off mid-sentence and omits the `verdict=NO-DATA` token entirely.**

- **Where:** line 61
  ```bash
  -h|--help)     sed -n '1,45p' "$0"; exit 0 ;;
  ```
- **Why it is wrong:** the verdict-token contract (lines 41–47) is the machine-parsing spec for consumers; the help drops one of the three tokens and its exit-code meaning, so anyone building a consumer from `-h` output gets an incomplete contract.

**12. The census-source guard says "fail loud rather than degrade" but only warns and proceeds.**

- **Where:** line 86
  ```bash
  [ -f "$CENSUS_SRC" ] || echo "terminal-bench: ⚠ census source not found under REPO=$REPO" >&2
  ```
- **Why it is wrong:** when `REPO` resolves somewhere without `tools/`, the script prints one stderr line and then does exactly what lines 70–71 describe as the ratcheted-against incident class: degrades every window column to NA, exits 0, and (via defect 3) can still print `verdict=OK`. A guard that observes the fatal condition and continues does not cover the class it claims to cover.

**13. (Flagged with uncertainty — I cannot verify tool behavior from the text alone.) `sample`'s documented output flag is `-file`, not `-f`.**

- **Where:** line 198
  ```bash
  if run 120 sample "$PID" "$SAMPLE_SECS" -f "$SAMPLE_F" >/dev/null 2>&1 && [ -s "$SAMPLE_F" ]; then
  ```
- **Why it is wrong (if so):** if `sample` rejects `-f`, it exits with a usage error, the condition is always false, the GPU profile is permanently NO-DATA, the printed verdict can never be OK — and, via defect 2, the JSONL would still record OK. If `-f` is in fact accepted as an alias on this platform, this item is void; I could not confirm it from the code alone.