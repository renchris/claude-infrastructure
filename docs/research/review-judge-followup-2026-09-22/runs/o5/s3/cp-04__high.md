## Defects

---

### 1. The GPU discriminator greps the whole `sample` report, so loaded-framework lines count as frames

**What** — `grep -cE` is run over the entire `sample` output file, which includes the `Binary Images:` / loaded-library listing, so a linked-but-unused GPU framework produces a non-zero `gpu_frames` count.

**Where** — lines ~199–200:
```bash
  GPU_N="$(grep -cE "$GPU_RE" "$SAMPLE_F" || true)"
  CPU_N="$(grep -cE "$CPU_RE" "$SAMPLE_F" || true)"
```

**Why it is wrong** — Run against kitty or the `*)` fallback (`GPU_RE='Metal|AGX|IOGPU|wgpu|CGL|OpenGL'`, `CPU_RE='CoreText|CGContext|CGSBlend'`), the mapped-image section of any `sample` report lists `Metal.framework/Metal`, `AGXMetal…`, `OpenGL.framework`, `CoreText.framework` etc. even for a fully idle process that rendered nothing during the 5 s window. Those lines are counted, the printed "gpu_frames"/"cpu_frames" are not frames at all, and the ratio is computed from image names rather than stack frames. This is exactly the "existence-of-a-fast-path can never establish *used*" error the header (lines 10–13) says the script exists to avoid. It also silently defeats the `0:0` guard on line 203: once the frameworks are linked, the counts are essentially never both zero, so the NO-DATA branch that is supposed to catch "the discriminator did not match this binary" can no longer fire.

---

### 2. The JSONL row is written before the GPU downgrade, so the filed verdict contradicts the printed one

**What** — The `--out` append happens before `VERDICT` is downgraded for an unresolved GPU profile, so the persisted row can say `"verdict":"OK"` while stdout says `verdict=PARTIAL`.

**Where** — lines ~244–251:
```bash
    "$(tr '\t' ',' <<<"$T0_APP")" "$GPU_N" "$CPU_N" "$VERDICT" >> "$OUT"
```
```bash
[ "$GPU_VERDICT" = OK ] || VERDICT="PARTIAL"
```

**Why it is wrong** — With `--interval 300 --out file.jsonl` and a `sample` that failed or matched nothing, `VERDICT` is `OK` at the moment of the append (set on line 231) and only becomes `PARTIAL` on line 251. The JSONL row — the machine-readable artifact a consumer actually compares terminals with — records `gpu_frames:"NA"` alongside `verdict:"OK"`, i.e. "full comparable row" for a row whose GPU axis was never measured. That is the claimed-outcome-vs-checked-outcome failure named in the verdict-token comment on line 42.

---

### 3. A missing window census never downgrades the verdict

**What** — `CENSUS_OK` is computed but never consulted when setting the verdict, so a run with no window census at all can still report `verdict=OK`.

**Where** — lines ~173–180 and ~231:
```bash
CENSUS_OK=1
```
```bash
[ "$CENSUS_OK" = 1 ] || echo "  ⚠ window census unavailable (swiftc failed) — window columns report NA"
```
```bash
  VERDICT="OK"
```

**Why it is wrong** — The documented contract (lines 44–46) is `PARTIAL` when "at least one of {drift, GPU profile, window census} is missing". If `swiftc` is absent or the compile fails, `CENSUS_OK=0`, `win`/`off`/`mpx` are `NA`, `drift 5` and `drift 6` both print `NA` — and yet, provided the GPU profile resolved, the last line is `verdict=OK`. A consumer filing that row believes windows and offscreen drift were measured and found stable, when they were never read. The same applies to `drift 2`/`drift 4` printing `NA`: `VERDICT="OK"` is set unconditionally at the end of the drift block, so "readings taken" is treated as "drift measured".

---

### 4. `top` returning nothing never produces the documented `NO-DATA` / exit 3

**What** — `reading`'s failure return is discarded, so an empty `top` result yields an all-`NA` row that flows through to `verdict=OK`/`PARTIAL` and exit 0.

**Where** — line ~151 and line ~191:
```bash
  if [ -z "$line" ]; then printf 'NA\tNA\tNA\tNA\tNA\tNA\tNA\n'; return 1; fi
```
```bash
T0_APP="$(reading "$PID" "$CENSUS_OWNER")"; T0_WS="$(reading "${WS_PID:-0}" 'Window Server')"
```

**Why it is wrong** — Line 47 promises `verdict=NO-DATA … or top returned nothing (exit 3)`. If the process exits between the `pgrep`/`ps` lookup and the `top` call, or `top` is killed by the 30 s timeout, `$?` from the command substitution is thrown away (no `set -e`, and the two calls are joined with `;`). The run then prints `cpu=NA mem=NAMB …`, prints `NA` for every drift row, and terminates with `verdict=OK` and exit 0 — a total instrument failure reported as a completed measurement, which is precisely the distinction the verdict tokens were designed to preserve.

---

### 5. `reading "${WS_PID:-0}"` measures pid 0 (`kernel_task`) and labels it WindowServer

**What** — When the WindowServer pid lookup fails, the default `0` is passed to `top -pid 0`, which reports `kernel_task`, and its numbers are printed as the WindowServer row.

**Where** — lines ~191 and ~218:
```bash
T0_APP="$(reading "$PID" "$CENSUS_OWNER")"; T0_WS="$(reading "${WS_PID:-0}" 'Window Server')"
```

**Why it is wrong** — `WS_PID` can legitimately be empty: line 129 uses `pgrep -x WindowServer`, and this file itself documents (lines 109–112) that `pgrep` on this box dropped 13 of 960 processes. pid 0 exists and is visible to `top` as `kernel_task`, so the grep `^[[:space:]]*0[[:space:]]` matches, and `show "T0  WS  "` prints kernel_task's CPU, memory, thread and mach-port counts as WindowServer's. Since WindowServer saturation and its unbounded mach-port table are the two findings this script is meant to re-measure (lines 6–9, 22–23), the row most likely to be acted on is silently the wrong process rather than `NA`.

---

### 6. `--app iTerm` and `--app kitty.app` get the generic GPU discriminator, not the app-specific one

**What** — The two `case "$APP"` tables do not accept the same aliases, so app spellings that resolve a process correctly fall through to the weak generic regex pair.

**Where** — line ~101 vs line ~136, and line ~100 vs line ~139:
```bash
  iTerm2|iTerm)    PROC_NAMES="iTerm2";                       CENSUS_OWNER="iTerm2" ;;
```
```bash
  iTerm2)            GPU_RE='iTermMetalDriver';        CPU_RE='iTermTextDrawingHelper' ;;
```
```bash
  kitty|kitty.app) PROC_NAMES="kitty";                        CENSUS_OWNER="kitty" ;;
```
```bash
  kitty)             GPU_RE='OpenGL|CGL|AGX|gl[A-Z]';  CPU_RE='CoreText|CGContext' ;;
```

**Why it is wrong** — `scripts/terminal-bench.sh --app iTerm …` finds the right pid and census owner, then matches `*)` in the discriminator table, so the run measures `Metal|AGX|IOGPU|wgpu|CGL|OpenGL` vs `CoreText|CGContext|CGSBlend` instead of `iTermMetalDriver` vs `iTermTextDrawingHelper`. The row is emitted with `verdict=OK` and is not comparable to a row produced by `--app iTerm2`, even though the header's central claim (lines 2–4) is that all apps are "measured by the same instrument, so their numbers are comparable". `--app kitty.app` behaves the same way.

---

### 7. A value-taking flag with no value loops forever instead of erroring

**What** — `shift 2` fails without shifting when only one argument remains, and the `while` loop re-reads the same argument indefinitely.

**Where** — lines ~54–60:
```bash
    --app)         APP="${2:-}"; shift 2 ;;
```

**Why it is wrong** — `scripts/terminal-bench.sh --app` (or a trailing `--interval`, `--out`, …): `${2:-}` supplies the empty default, then `shift 2` with `$# = 1` returns non-zero and leaves `$#` at 1. `[ $# -gt 0 ]` is still true, `case "$1"` matches `--app` again, and the script spins in the argument loop. The required-argument check on line 65 that is supposed to print `--app <AppName> is required` and `exit 2` is never reached.

---

### 8. `IFS=$'\t' read` collapses empty fields, so `show` has the column shift its own comment claims to prevent

**What** — Tab is IFS *whitespace*, so a run of tabs is a single delimiter; an empty field in the row shifts every later column left in the printed line.

**Where** — lines ~182–186:
```bash
# Split on TAB explicitly. Relying on `printf ... $(echo "$row")` word-splitting silently shifts
```
```bash
  IFS=$'\t' read -r cpu mem th ports win off mpx <<<"$row"
```

**Why it is wrong** — If the census emits a short row (e.g. fewer than 7 columns), `cut -f5`/`cut -f7` on line 166 return empty strings, and `printf` on line 169 produces adjacent tabs. Because bash treats sequences of IFS whitespace as one delimiter, `read` assigns `off` the value of `mpx` and leaves `mpx` empty — the "misattribute ports to threads" failure the comment asserts is impossible. It also means `show` and the drift rows disagree about the same data, since `drift` uses `cut -f"$f"` on the raw row and is unaffected.

---

### 9. The drift NA-guard only recognises the literal `NA`, so an empty field is differenced against zero

**What** — `drift` skips only when a field is exactly `NA`; an empty field is passed to `awk`, which coerces it to 0.

**Where** — lines ~224–227:
```bash
    [ "$a" = NA ] || [ "$b" = NA ] && { printf '    %-14s NA\n' "$label"; return; }
```

**Why it is wrong** — With an empty `T0_APP` field (short census row, per defect 8) and a populated `T1_APP` field, both tests are false, `awk` computes `d = b - 0 = b`, and the script prints something like `windows +31 over 300s = +372.0/hr`. A missing baseline is reported as a large, confident leak — from the one reading the header (lines 28–31) says is "the only reading that supports a leak verdict".

---

### 10. Drift rates divide by the nominal interval, not the elapsed time between the two readings

**What** — The per-hour rate uses `INTERVAL`, but the actual gap between the two `top` second-samples also includes the T0 census, the `sample` run and the T1 `top` startup.

**Where** — lines ~226–227:
```bash
    awk -v a="$a" -v b="$b" -v s="$INTERVAL" -v l="$label" \
      'BEGIN{ d=b-a; printf "    %-14s %+.0f over %ds  = %+.1f/hr\n", l, d, s, d*3600/s }'
```

**Why it is wrong** — Between the two readings the script spends `--sample-secs` (default 5) in `sample`, plus two `top -l 2` runs (~2 s each) and up to two census invocations, before and after the `sleep "$INTERVAL"`. Real elapsed time is therefore ~8–10 s more than `INTERVAL`; the printed `/hr` figure and the literal `over ${INTERVAL}s` label both overstate the drift rate. At `--interval 0`… the block is skipped, but at short intervals the error is proportionally large (e.g. `--interval 30` overstates by ~30%).

---

### 11. Process-name lists and `top`/`ps` field positions break for any name containing a space

**What** — `PROC_NAMES` is word-split, and both the `ps` fallback and the `top` parser take fixed whitespace fields, so an app whose executable name or path contains a space is looked up and parsed wrongly.

**Where** — lines ~102, ~105, ~121, ~152–155:
```bash
  *)               PROC_NAMES="$APP";                         CENSUS_OWNER="$APP" ;;
```
```bash
    PID="$(ps -eo pid=,comm= | awk -v want="$_p" '{n=split($2,a,"/"); if (a[n]==want) {print $1; exit}}')"
```
```bash
  cpu="$(awk '{print $3}' <<<"$line")"
```

**Why it is wrong** — The `*)` branch accepts arbitrary app names, so `--app "Some Terminal"` splits into the two candidates `Some` and `Terminal` in the `for _p in $PROC_NAMES` loop — `Terminal` may match a completely different running app and be measured under the requested app's name. Independently, `ps -eo comm=` prints the full executable path on macOS; a path containing a space leaves `$2` truncated so `a[n]` can never equal `want`, and in `reading`, `top`'s COMMAND column containing a space makes `$3`…`$6` read command text instead of cpu/mem/th/ports (`cpu` would print a word, and `mem` normalisation would emit a bogus MB figure from it).

---

### 12. Memory normalisation ignores a byte suffix

**What** — The MB conversion strips only `K`/`M`/`G`, so a `B`-suffixed value is reported as if it were megabytes.

**Where** — lines ~157–160:
```bash
      v=m; sub(/[KMG][+-]?$/,"",v); u=substr(m,length(m),1);
```

**Why it is wrong** — When `top` prints a small MEM value such as `512B`, the `sub` does not match, `v` stays `"512B"`, neither the `G` nor the `K` branch fires, and awk's numeric coercion yields `512` — filed as 512 MB, a ~10⁶× overstatement that also poisons the `mem MB` drift row and `MB/pane`.

---

### 13. `--help` truncates the header mid-sentence and drops a documented verdict token

**What** — `sed -n '1,45p'` stops inside the `verdict=PARTIAL` paragraph, so `--help` never shows the `verdict=NO-DATA` line.

**Where** — line ~61:
```bash
    -h|--help)     sed -n '1,45p' "$0"; exit 0 ;;
```

**Why it is wrong** — The comment block runs to line 47 (`#   verdict=NO-DATA   the app is not running, or top returned nothing  (exit 3)`). `--help` ends at "…always yields PARTIAL by construction: a single", omitting both the rest of that sentence and the entire NO-DATA/exit-3 contract — the one token a consumer needs in order to distinguish "measured zero" from "the instrument did not run".

---

### 14. The census-source guard warns but does not fail

**What** — The `[ -f "$CENSUS_SRC" ]` check only prints to stderr and execution continues, despite the comment stating the intent is to fail rather than degrade.

**Where** — lines ~85–86:
```bash
# Fail loud rather than degrade to NA-everywhere if the root resolved somewhere without the tool.
[ -f "$CENSUS_SRC" ] || echo "terminal-bench: ⚠ census source not found under REPO=$REPO" >&2
```

**Why it is wrong** — If the symlink/`CC_REPO` resolution lands on a root without `tools/terminal-bench/`, the script prints one stderr line (plus a misleading `swiftc failed` line at 180, since swiftc was never given a real source) and then produces a complete-looking run with `NA` in every window column and, per defect 3, a final `verdict=OK` and exit 0 — the "silently report NA for every window column, and still exit 0" outcome described at lines 70–71 as the class being ratcheted against.

---

### 15. `panes=${PANES:-unset}` can never print `unset`

**What** — `PANES` is initialised to `0`, a non-empty value, so the `:-unset` default is dead and an unspecified pane count is reported as a measured `0`.

**Where** — lines ~53 and ~179:
```bash
APP=""; PANES=0; INTERVAL=180; SAMPLE_SECS=5; OUT=""
```
```bash
echo "terminal-bench — app=$APP pid=$PID panes=${PANES:-unset} interval=${INTERVAL}s  $(date -u +%FT%TZ)"
```

**Why it is wrong** — Run without `--panes`, the header line reads `panes=0`, which a reader (or a log scraper) takes as "measured with zero panes open" rather than "pane count not supplied"; the JSONL row records `"panes":0` for the same reason.
