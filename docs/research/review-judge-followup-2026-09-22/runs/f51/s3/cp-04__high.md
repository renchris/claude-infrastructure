Reviewing the script as text only. Findings below, roughly ordered by impact.

**1. The JSONL row records the verdict before the GPU demotion is applied.**

Where, line 247 and line 251:
```
    "$(tr '\t' ',' <<<"$T0_APP")" "$GPU_N" "$CPU_N" "$VERDICT" >> "$OUT"
```
```
[ "$GPU_VERDICT" = OK ] || VERDICT="PARTIAL"
```
Why: with `--interval` > 0 the drift block sets `VERDICT="OK"` on line 231. If the GPU profile failed (`sample` denied, timed out, or matched nothing), the file gets `"verdict":"OK"` and only the stdout line is demoted to PARTIAL. The persistent record, which is what the bake-off consumes, claims "GPU profile resolved" for a run where it did not.

**2. A missing window census never demotes the verdict, contrary to the header contract.**

Where, line 231, line 251, and line 86:
```
  VERDICT="OK"
```
```
[ "$GPU_VERDICT" = OK ] || VERDICT="PARTIAL"
```
```
[ -f "$CENSUS_SRC" ] || echo "terminal-bench: ⚠ census source not found under REPO=$REPO" >&2
```
Why: `CENSUS_OK` is set on lines 173 to 177 and printed on line 180 but never consulted when computing `VERDICT`. If the repo root resolves wrong, `swiftc` fails, or the census emits nothing, every window column is NA, `drift 5` and `drift 6` print NA, and the run still ends `verdict=OK` with exit 0. Lines 70 to 71 describe this exact outcome as the incident class the script must not repeat, and line 86 says "fail loud" but only warns and continues.

**3. An empty `top` reading is not reported as NO-DATA; the failure status is discarded.**

Where, lines 151 and 191:
```
  if [ -z "$line" ]; then printf 'NA\tNA\tNA\tNA\tNA\tNA\tNA\n'; return 1; fi
```
```
T0_APP="$(reading "$PID" "$CENSUS_OWNER")"; T0_WS="$(reading "${WS_PID:-0}" 'Window Server')"
```
Why: the `return 1` is swallowed by the command substitution and nothing checks for an all-NA row. The header on line 47 promises `verdict=NO-DATA` and exit 3 when "top returned nothing", but the script continues, prints NA drift, writes a `"t0":"NA,NA,..."` row, and can still emit `verdict=OK`. The same holds if the process dies before T1.

**4. GPU and CPU frame counts include the sample file's Binary Images section, so "loaded" is counted as "used".**

Where, lines 199 to 200 and 203:
```
  GPU_N="$(grep -cE "$GPU_RE" "$SAMPLE_F" || true)"
  CPU_N="$(grep -cE "$CPU_RE" "$SAMPLE_F" || true)"
```
```
  if [ "$GPU_N" -gt 0 ] || [ "$CPU_N" -gt 0 ]; then GPU_VERDICT="OK"; fi
```
Why: `sample` output ends with a Binary Images list of every loaded library, with paths such as `Metal.framework`, `CoreText.framework`, `OpenGL.framework` and `AGXMetal...`. Every macOS GUI app loads CoreText and Metal, so for the ghostty, wezterm, kitty, alacritty and generic patterns both counts are non-zero even with zero matching stack frames. The 0:0 guard can never fire, `GPU_VERDICT` is always OK, and the printed ratio is partly a count of library names. This is the "loaded driver as evidence of use" error that lines 10 to 13 say the tool exists to avoid. Separately, `grep -c` counts distinct tree lines, not the per-frame sample counts `sample` prefixes each line with, so the ratio does not reflect time on either path.

**5. A trailing option with no value loops forever.**

Where, lines 54 to 64, for example line 60:
```
    --out)         OUT="${2:-}"; shift 2 ;;
```
Why: with only one positional left, bash's `shift 2` fails and leaves the parameters unchanged. Since `set -e` is not on, the loop re-enters with the same `$1`, matches the same case, and never terminates. `terminal-bench.sh --app iTerm2 --out` hangs instead of erroring.

**6. If WindowServer's pid is not found, kernel_task is measured and labelled as WindowServer.**

Where, lines 129 and 191:
```
WS_PID="$(pgrep -x WindowServer | head -1 || true)"
```
```
T0_APP="$(reading "$PID" "$CENSUS_OWNER")"; T0_WS="$(reading "${WS_PID:-0}" 'Window Server')"
```
Why: the script's own comments on lines 109 to 115 establish that `pgrep -x` silently drops processes on this box. When it returns nothing, the fallback pid is `0`, `top -pid 0` reports kernel_task, and its cpu, memory, thread and port figures are printed under the "WS" label with no NA and no warning.

**7. Accepted app aliases fall through to the generic GPU discriminator.**

Where, lines 100 to 101 versus lines 136 and 139:
```
  kitty|kitty.app) PROC_NAMES="kitty";                        CENSUS_OWNER="kitty" ;;
  iTerm2|iTerm)    PROC_NAMES="iTerm2";                       CENSUS_OWNER="iTerm2" ;;
```
```
  iTerm2)            GPU_RE='iTermMetalDriver';        CPU_RE='iTermTextDrawingHelper' ;;
  kitty)             GPU_RE='OpenGL|CGL|AGX|gl[A-Z]';  CPU_RE='CoreText|CGContext' ;;
```
Why: `--app iTerm` and `--app kitty.app` are accepted for process lookup but do not match the second case, so they use the `*` regexes. The same app then yields different `gpu_frames`/`cpu_frames` numbers depending on how it was spelled, and the rows are filed as if comparable.

**8. Per-pane normalisation prints 0.00 for NA fields instead of NA.**

Where, lines 237 to 241:
```
  awk -v p="$PANES" -v r="$T0_APP" 'BEGIN{ split(r,f,"\t");
```
Why: awk coerces the string `NA` to 0, so a failed `top` reading or missing census produces `threads/pane 0.00`, `MB/pane 0.0` and so on. A missing measurement is reported as a measured zero, the exact confusion lines 41 to 42 say the output must prevent.

**9. `--help` truncates the header it is meant to print.**

Where, line 61:
```
    -h|--help)     sed -n '1,45p' "$0"; exit 0 ;;
```
Why: the header runs through line 47. Help output stops mid-way through the PARTIAL definition and omits the NO-DATA token and its exit code entirely.

**10. Column parsing assumes the process name has no spaces.**

Where, lines 152 to 155:
```
  cpu="$(awk '{print $3}' <<<"$line")"
```
Why: `top` prints the command name unquoted. For any app reached through the generic `*` branch whose name contains a space, every field shifts right by one, and the command's second word is reported as cpu, cpu as memory, and so on, with no error.

**11. The NO-DATA message asserts a cause it has not established.**

Where, line 209:
```
  printf '  GPU path taken: NO-DATA (discriminator matched no symbols; do NOT read as "no GPU")\n'
```
Why: this branch is also reached when `sample` itself fails on line 198, for example on a permission denial or timeout, in which case no symbols were ever examined. The message reports the wrong reason for the missing data.

**12. The OK row written to the JSONL omits the drift readings the token is defined by.**

Where, lines 245 to 247:
```
  printf '{"ts":"%s","app":"%s","pid":%s,"panes":%s,"interval":%s,"t0":"%s","gpu_frames":"%s","cpu_frames":"%s","verdict":"%s"}\n' \
```
Why: line 43 defines OK as "both readings taken" and "a full comparable row", and lines 28 to 31 name drift as the only reading that supports a leak verdict. The row contains only T0 and no T1 or drift values, so a downstream consumer reading `verdict=OK` cannot recover the measurement that justified it.
