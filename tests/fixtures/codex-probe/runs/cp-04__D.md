## Report

Fourteen defects. The most consequential ones all sit on the same fault line the header says this script exists to avoid: a run that did not measure something still gets filed as if it did.

---

### 1. The JSONL row is written before the GPU downgrade, so the persisted verdict contradicts the printed one

**Where** — lines 244–247 and 251:
```bash
    "$(tr '\t' ',' <<<"$T0_APP")" "$GPU_N" "$CPU_N" "$VERDICT" >> "$OUT"
```
```bash
[ "$GPU_VERDICT" = OK ] || VERDICT="PARTIAL"
```

**Why it is wrong** — With `--interval 300 --out file.jsonl` on a run where `sample` fails or the discriminator matches nothing, `VERDICT` is `"OK"` at line 231 and stays `"OK"` through the append. Line 251 then downgrades it and line 252 prints `verdict=PARTIAL`. The JSONL — the durable bake-off record, and the only artifact a consumer reads later — records `"verdict":"OK"` with `"gpu_frames":"NA"`, i.e. a row claiming "both readings taken AND the GPU profile resolved" for a run whose GPU profile did not resolve.

---

### 2. `show()`'s explicit tab split does not preserve empty fields — the exact shift its comment claims to prevent

**Where** — lines 182–183 and 186:
```bash
# Split on TAB explicitly. Relying on `printf ... $(echo "$row")` word-splitting silently shifts
# every column left the moment one field is empty, which would misattribute ports to threads.
```
```bash
  IFS=$'\t' read -r cpu mem th ports win off mpx <<<"$row"
```

**Why it is wrong** — Tab is an IFS *whitespace* character, so even with `IFS=$'\t'` bash collapses a run of tabs into one delimiter and drops leading/trailing ones. If any field emitted by `reading` is empty — e.g. `awk '{print $6}'` returns nothing because the top line was short, or the census TSV lacks column 5 or 7 — `a\t\tb` splits into two fields, not three. Every column right of the empty one is read one position left: the ports value is printed as `th=`, and so on. Meanwhile `drift()` uses `cut -f`, which *does* preserve empty fields, so the same row is displayed under one column mapping and differenced under another.

---

### 3. A failed window census never affects the verdict

**Where** — lines 177, 180 and 231:
```bash
[ -x "$CENSUS_BIN" ] || CENSUS_OK=0
```
```bash
[ "$CENSUS_OK" = 1 ] || echo "  ⚠ window census unavailable (swiftc failed) — window columns report NA"
```
```bash
  VERDICT="OK"
```

**Why it is wrong** — The documented contract (line 44) makes a missing **window census** a `PARTIAL` trigger alongside drift and GPU profile. `CENSUS_OK` is computed and used for one stderr-ish warning, then never read again. With `swiftc` unavailable and `--interval 300`, the run prints `win=NA off=NA mpx=NA`, prints `NA` for the windows and offscreen drift rows — and still emits `verdict=OK`, which the header defines as "a full comparable row". The window/leak axis is the reason the script exists, and its absence is filed as a complete measurement.

---

### 4. `reading()` reports failure, and nothing consumes it — "top returned nothing" never becomes NO-DATA

**Where** — lines 151 and 191:
```bash
  if [ -z "$line" ]; then printf 'NA\tNA\tNA\tNA\tNA\tNA\tNA\n'; return 1; fi
```
```bash
T0_APP="$(reading "$PID" "$CENSUS_OWNER")"; T0_WS="$(reading "${WS_PID:-0}" 'Window Server')"
```

**Why it is wrong** — Line 47 documents `verdict=NO-DATA` for "the app is not running, **or top returned nothing** (exit 3)". The second half is never implemented: `set -e` is not in effect, and the `return 1` is discarded by the command substitution. If the process exits between PID resolution and the `top` call, or the `timeout` fires, every column is `NA`, the drift rows are `NA`, and the script still ends at `verdict=OK` (or `PARTIAL`) with exit 0. The one verdict token reserved for "the instrument did not run" is unreachable by the path it names.

---

### 5. Per-pane normalisation turns `NA` into `0.00` and prints it as a measurement

**Where** — lines 237–241:
```bash
  awk -v p="$PANES" -v r="$T0_APP" 'BEGIN{ split(r,f,"\t");
    printf "    threads/pane   %.2f\n", f[3]/p;
```

**Why it is wrong** — awk coerces the string `NA` to numeric 0. When `reading` returned the all-`NA` row (defect 4), `--panes 30` prints `threads/pane 0.00`, `ports/pane 0.00`, `MB/pane 0.0`, `cpu%/pane 0.00`. A challenger that was never successfully measured reports the best possible per-pane numbers in the bake-off — the "measured zero vs. instrument did not run" confusion the header says a consumer must be protected from, manufactured by the script itself.

---

### 6. The GPU discriminator greps the whole `sample` file, so a merely *loaded* framework counts as frames taken

**Where** — lines 199–203:
```bash
  GPU_N="$(grep -cE "$GPU_RE" "$SAMPLE_F" || true)"
```
```bash
  if [ "$GPU_N" -gt 0 ] || [ "$CPU_N" -gt 0 ]; then GPU_VERDICT="OK"; fi
```

**Why it is wrong** — `sample`'s output is not only the call graph; it ends with a `Binary Images:` section listing every loaded dylib with its path, and begins with `Path:`/`Process:` header lines. For `ghostty` (`GPU_RE='Metal|renderer.*[Mm]etal'`), `kitty`/`alacritty` (`'OpenGL|CGL|AGX|gl[A-Z]'`) and the generic fallback, `/System/Library/Frameworks/Metal.framework/...` matches whether or not a single frame was on a Metal stack. `CPU_RE='CoreText|CGContext'` matches `CoreText.framework` the same way. So `gpu_frames` counts loaded images, the printed ratio is between two contaminated counts, and the 0:0 guard — the one thing standing between this and a vacuous verdict — can essentially never fire for exactly the apps whose discriminators are weakest. This is the "existence-of-a-fast-path evidence establishes 'used'" error the header block is written to prevent.

---

### 7. When `pgrep` cannot see WindowServer, the script measures pid 0 and labels it WS

**Where** — lines 129, 191, 218:
```bash
WS_PID="$(pgrep -x WindowServer | head -1 || true)"
```
```bash
T0_APP="$(reading "$PID" "$CENSUS_OWNER")"; T0_WS="$(reading "${WS_PID:-0}" 'Window Server')"
```

**Why it is wrong** — `${WS_PID:-0}` substitutes pid 0, which on macOS is `kernel_task`. `top -l 2 -pid 0` returns kernel_task's cpu/mem/threads/ports and the grep on `^[[:space:]]*0[[:space:]]` matches it, so the `T0 WS` / `T1 WS` rows print kernel_task's numbers under the WindowServer label with no warning. The script's own comment at lines 109–115 establishes that `pgrep` silently dropped 13 of 960 processes on this box, and the ps-comm fallback built for that failure is applied only to the app, not to WindowServer — whose saturation is the root cause the whole document is about.

---

### 8. `CENSUS_OK` and the gate that actually runs the census are different predicates, so a stale binary is used after announcing NA

**Where** — lines 175, 177, 180 and 163:
```bash
  if ! run 300 swiftc -O "$CENSUS_SRC" -o "$CENSUS_BIN" 2>/dev/null; then CENSUS_OK=0; fi
```
```bash
  if [ -x "$CENSUS_BIN" ]; then
```

**Why it is wrong** — `CENSUS_BIN` is `${TMPDIR:-/tmp}/window-census.$(id -u)`, keyed only by uid and shared across every checkout and every invocation. If the compile fails now but a binary from an earlier run is still there, `CENSUS_OK` is 0 and line 180 announces "window census unavailable — window columns report NA", while `reading()` tests `-x "$CENSUS_BIN"`, finds the old binary, runs it, and fills `win`/`off`/`mpx` with its output. The header says one thing and the columns say another, and the numbers came from a source that is not the one at `CENSUS_SRC`.

---

### 9. A missing census source only warns, and cannot even force a rebuild

**Where** — lines 85–86 and 174:
```bash
# Fail loud rather than degrade to NA-everywhere if the root resolved somewhere without the tool.
[ -f "$CENSUS_SRC" ] || echo "terminal-bench: ⚠ census source not found under REPO=$REPO" >&2
```
```bash
if [ ! -x "$CENSUS_BIN" ] || [ "$CENSUS_SRC" -nt "$CENSUS_BIN" ]; then
```

**Why it is wrong** — The comment promises a loud failure; the code emits one stderr line and continues to completion with exit 0. Worse, `-nt` is false when the left operand does not exist, so a bad `REPO` resolution cannot even trigger a rebuild attempt: with a stale `CENSUS_BIN` present the script takes the "already built" branch, keeps `CENSUS_OK=1`, prints no warning at line 180, and reports the stale binary's window counts as this run's census. That is precisely the degradation described at lines 70–71 as the class being ratcheted against.

---

### 10. A valueless trailing flag makes the argument loop spin forever

**Where** — lines 54–60, e.g.:
```bash
    --app)         APP="${2:-}"; shift 2 ;;
```

**Why it is wrong** — `scripts/terminal-bench.sh --app` (or a trailing `--out`, `--panes`, `--interval`, `--sample-secs`) leaves `$#` at 1. `${2:-}` is guarded against `set -u`, and bash's `shift 2` with `$# = 1` fails silently without shifting, so `$1` is still `--app` and `[ $# -gt 0 ]` is still true. The script hangs with no output and no diagnostic instead of reaching the `--app is required` check at line 65.

---

### 11. A multi-word app name is word-split into several wrong process names

**Where** — lines 102, 105:
```bash
  *)               PROC_NAMES="$APP";                         CENSUS_OWNER="$APP" ;;
```
```bash
for _p in $PROC_NAMES; do
```

**Why it is wrong** — `$PROC_NAMES` is deliberately unquoted so the multi-name lists (`"wezterm-gui WezTerm wezterm"`) split into candidates. For the generic branch the script advertises ("App-agnostic by construction"), `--app "Some Terminal"` therefore searches for two names, `Some` and `Terminal`, neither of which is the app. Both the pgrep pass and the ps-comm pass miss, and a running app is reported as `no running process named 'Some Terminal'` with `verdict=NO-DATA` and exit 3 — a false negative indistinguishable from the app genuinely not running.

---

### 12. The `top` line is parsed by whitespace position, assuming COMMAND is a single token

**Where** — lines 152–155:
```bash
  cpu="$(awk '{print $3}' <<<"$line")"
  mem="$(awk '{print $4}' <<<"$line")"
  th="$(awk  '{print $5}' <<<"$line" | tr -d '+-' | cut -d/ -f1)"
  ports="$(awk '{print $6}' <<<"$line" | tr -d '+-')"
```

**Why it is wrong** — `-stats pid,command,cpu,mem,th,ports` puts COMMAND in field 2, but macOS accounting names routinely contain spaces (`Google Chrome`, `Adobe Desktop Service`), and the generic `*)` branch accepts any such app. When COMMAND is two words, `$3` is the second word of the name, `$4` is `%CPU`, `$5` is `MEM`, `$6` is `#TH`. The mem normaliser then runs on a CPU percentage, `#TH` is reported as ports, and `#PORTS` is dropped — every number silently misattributed one column right, which is the failure mode `show()`'s comment at lines 182–183 says must not be allowed.

---

### 13. `tail -1` does not verify that a second sample was produced

**Where** — line 150:
```bash
          | grep -E "^[[:space:]]*${pid}[[:space:]]" | tail -1)"
```

**Why it is wrong** — The stated invariant (line 148) is that the first `top` sample is a lifetime average and is discarded. The only check is that the output was non-empty. If `top` produced just one process line — the target exits after the first sample, or the `timeout 30` at line 149 kills it mid-run — `tail -1` returns the *first* sample and the code reports the lifetime average as the interval reading, with no `NA` and no warning. That is the 2.3x WindowServer misread named at line 17, reintroduced through the guard meant to exclude it.

---

### 14. The drift rate is divided by the nominal interval, not the elapsed time between readings

**Where** — lines 217 and 226–227:
```bash
  sleep "$INTERVAL"
```
```bash
      'BEGIN{ d=b-a; printf "    %-14s %+.0f over %ds  = %+.1f/hr\n", l, d, s, d*3600/s }'
```

**Why it is wrong** — Between the T0 app reading and the T1 app reading the script also performs the T0 WindowServer reading (another `top -l 2`, ~2 s, plus a census invocation) and a `sample` run of `SAMPLE_SECS` (default 5 s, up to the 120 s cap). Real elapsed time is `INTERVAL` plus that overhead, but the extrapolation divides by `INTERVAL` alone, so every `/hr` leak rate is overstated. At the documented `--interval 300` that is a few percent; at short intervals the overhead dominates and the reported rate is arbitrary. Nothing timestamps either reading, so the "known interval apart" premise at line 28 is asserted rather than measured.

---

### 15. `--help` truncates the verdict-token contract mid-sentence

**Where** — line 61:
```bash
    -h|--help)     sed -n '1,45p' "$0"; exit 0 ;;
```

**Why it is wrong** — The header block runs to line 47. `1,45p` stops in the middle of the `verdict=PARTIAL` description ("...by construction: a single") and omits line 47 entirely, so `--help` never shows `verdict=NO-DATA` or its exit code 3. A consumer reading the help — the documented machine-parsable contract — learns only two of the three tokens the script can emit, and the missing one is the failure token.