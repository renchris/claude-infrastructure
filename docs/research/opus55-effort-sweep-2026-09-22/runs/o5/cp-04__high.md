# Review — `scripts/terminal-bench.sh`

Line numbers are counted with `#!/bin/bash` as line 1; the verbatim text is the authoritative pointer.

---

## 1. The JSONL row is written before the GPU downgrade, so the file records `OK` while stdout prints `PARTIAL`

**What.** The persisted verdict is captured before the `GPU_VERDICT` check that can demote it, so a run whose GPU profile did not resolve is filed as a full comparable row.

**Where.** Lines ~244–246 and ~250:
```bash
    "$(tr '\t' ',' <<<"$T0_APP")" "$GPU_N" "$CPU_N" "$VERDICT" >> "$OUT"
```
```bash
[ "$GPU_VERDICT" = OK ] || VERDICT="PARTIAL"
```

**Why it is wrong.** With `--interval 300 --out file.jsonl` on an app whose discriminator matches nothing (`GPU_VERDICT=NO-DATA`, `gpu_frames=0`, `cpu_frames=0`), `VERDICT` is still `"OK"` at the time of the append (set at line ~230 by the drift branch). The file gets `"gpu_frames":"NA","cpu_frames":"NA","verdict":"OK"` while the terminal prints `verdict=PARTIAL`. A consumer parsing the JSONL — the stated machine-readable interface — cannot tell "the instrument did not run" from "a full comparable row", which is exactly the distinction the header says the tokens exist to preserve.

## 2. A missing/failed window census still yields `verdict=OK`

**What.** `CENSUS_OK` never influences `VERDICT`, so the documented PARTIAL condition "window census missing" is never enforced.

**Where.** Lines ~172–179 and ~230:
```bash
[ -x "$CENSUS_BIN" ] || CENSUS_OK=0
```
```bash
  VERDICT="OK"
```

**Why it is wrong.** Run with `swiftc` absent or `CENSUS_SRC` unresolvable: the script prints `⚠ window census unavailable`, every window/offscreen column reports `NA`, the drift lines for `windows` and `offscreen win` print `NA` — and because `INTERVAL > 0` and the GPU profile resolved, the last line is `verdict=OK`. The header states OK means "both readings taken AND the GPU profile resolved — a full comparable row", and PARTIAL covers a missing window census. A row with no window data, the axis the whole freeze investigation turned on, is filed as complete.

## 3. A failed `top` reading is not reported as NO-DATA

**What.** `reading` signals failure with exit status 1, but every call site captures it in a command substitution and discards the status, so an all-`NA` reading flows through to a success verdict.

**Where.** Line ~150 and ~190:
```bash
  if [ -z "$line" ]; then printf 'NA\tNA\tNA\tNA\tNA\tNA\tNA\n'; return 1; fi
```
```bash
T0_APP="$(reading "$PID" "$CENSUS_OWNER")"; T0_WS="$(reading "${WS_PID:-0}" 'Window Server')"
```

**Why it is wrong.** If the process exits between the `pgrep`/`ps` lookup and the sample, or `top` is killed by the 30 s timeout, `T0_APP` is the NA row. The documented contract is `verdict=NO-DATA … or top returned nothing (exit 3)`, but NO-DATA/exit 3 is only reachable from the PID lookup (line ~126). The run instead prints `cpu=NA mem=NAMB …`, drift `NA`, and terminates with `verdict=OK` and exit 0.

## 4. When `WindowServer` is not found, pid `0` is measured and labelled as WindowServer

**What.** The `${WS_PID:-0}` default substitutes a real, unrelated pid instead of signalling "not found".

**Where.** Lines ~128, ~190, ~217:
```bash
WS_PID="$(pgrep -x WindowServer | head -1 || true)"
```
```bash
T0_APP="$(reading "$PID" "$CENSUS_OWNER")"; T0_WS="$(reading "${WS_PID:-0}" 'Window Server')"
```

**Why it is wrong.** If `pgrep -x WindowServer` returns nothing — the same `pgrep` unreliability this file documents at length for iTerm2, lines ~108–114 — `WS_PID` is empty and `reading` is called with pid `0`. Pid 0 is `kernel_task`, and the filter `^[[:space:]]*0[[:space:]]` matches its row, so `top` returns a line and the NA path at line ~150 is never taken. The script then prints `T0 WS cpu=… ports=…` from kernel_task and the reader attributes kernel_task's mach-port count to WindowServer, the exact quantity the freeze was root-caused to.

## 5. A failed rebuild still runs the stale census binary while the banner claims the census is unavailable

**What.** `CENSUS_OK` gates only the warning message; `reading` gates on `[ -x "$CENSUS_BIN" ]`, so a stale binary is used and its numbers reported.

**Where.** Lines ~174, ~179, ~162:
```bash
  if ! run 300 swiftc -O "$CENSUS_SRC" -o "$CENSUS_BIN" 2>/dev/null; then CENSUS_OK=0; fi
```
```bash
[ "$CENSUS_OK" = 1 ] || echo "  ⚠ window census unavailable (swiftc failed) — window columns report NA"
```
```bash
  if [ -x "$CENSUS_BIN" ]; then
```

**Why it is wrong.** The rebuild is triggered precisely when `CENSUS_SRC -nt CENSUS_BIN`, i.e. the source changed. If `swiftc` then fails (compile error, `2>/dev/null` hides it), the previous binary is left in `$TMPDIR/window-census.$(id -u)` and is still executable. The run prints "window columns report NA" and then proceeds to emit window/offscreen/mpx numbers produced by a binary built from an older source revision. The printed warning and the printed data contradict each other, and the stale numbers feed the drift verdict.

## 6. GPU/CPU counts include `sample`'s non-frame sections, so a merely-loaded framework counts as a GPU path taken

**What.** `grep -cE` is run over the whole `sample` output file, not over call-graph frames only, so the trailing binary-image/library listing satisfies the discriminator.

**Where.** Lines ~198, ~202:
```bash
  GPU_N="$(grep -cE "$GPU_RE" "$SAMPLE_F" || true)"
```
```bash
  if [ "$GPU_N" -gt 0 ] || [ "$CPU_N" -gt 0 ]; then GPU_VERDICT="OK"; fi
```

**Why it is wrong.** `sample` appends a `Binary Images:` section listing every loaded image with its path. For `--app kitty` (`GPU_RE='OpenGL|CGL|AGX|gl[A-Z]'`) or the generic fallback (`Metal|AGX|IOGPU|wgpu|CGL|OpenGL`), an app that links Metal/OpenGL but renders entirely on the CPU during the sample window still produces `GPU_N ≥ 1` from lines like `/System/Library/.../AGXMetalG14X`. The script then prints `GPU path taken: gpu_frames=N …`. That is existence-of-a-fast-path evidence being reported as use — the precise inference the header (lines ~10–13) forbids.

## 7. The reported ratio counts matching lines, not samples, so it is not a CPU:GPU time ratio

**What.** `grep -c` yields the number of distinct matching lines, but the output labels them `gpu_frames`/`cpu_frames` and divides them into a ratio as if they were weighted sample counts.

**Where.** Lines ~198–199 and ~205–206:
```bash
    "$(awk -v g="$GPU_N" -v c="$CPU_N" 'BEGIN{ if(c==0){print "all-GPU"} else printf "%.2f:1", g/c }')"
```

**Why it is wrong.** Each `sample` call-graph line carries a leading sample count (e.g. `4821 -[... drawRect:]`). A GPU symbol appearing on three lines with 1 sample each and a CPU symbol appearing on one line with 5000 samples yields `3/1 = 3.00:1` "GPU-favouring", when the process spent essentially all its time on the CPU path. The number printed is a symbol-distinctness ratio presented as the CPU:GPU profile that the header says decides the bake-off.

## 8. A trailing option with no value sends the argument parser into an infinite loop

**What.** `shift 2` with only one positional parameter left does not shift and does not abort, so the `while` loop re-reads the same argument forever.

**Where.** Lines ~56–60, e.g.:
```bash
    --app)         APP="${2:-}"; shift 2 ;;
```

**Why it is wrong.** `scripts/terminal-bench.sh --app` (or any of `--panes`, `--interval`, `--sample-secs`, `--out` as the final token): `${2:-}` keeps `set -u` quiet, `shift 2` returns non-zero and leaves `$1` as `--app`, and there is no `set -e`. `[ $# -gt 0 ]` remains true forever. The user gets a silently hung process instead of the `--app <AppName> is required` error at line ~65.

## 9. `--help` truncates the header mid-sentence and omits the `NO-DATA` token

**What.** The help printer stops at line 45, which is inside the `verdict=PARTIAL` description.

**Where.** Line ~61:
```bash
    -h|--help)     sed -n '1,45p' "$0"; exit 0 ;;
```

**Why it is wrong.** The comment block runs to line 47. Line 45 ends `` …always yields PARTIAL by construction: a single`` — the sentence completing it (line 46) and the entire `verdict=NO-DATA … (exit 3)` line (line 47) are never printed. A user reading `--help` to learn the machine-parsable tokens is shown two of the three, and the one omitted is the failure token.

## 10. Per-pane normalisation turns `NA` fields into `0.00` and reports them as measurements

**What.** The awk block divides the raw reading fields by `$PANES` with no check for the `NA` sentinel, and awk coerces `NA` to 0.

**Where.** Lines ~236–240:
```bash
  awk -v p="$PANES" -v r="$T0_APP" 'BEGIN{ split(r,f,"\t");
```
```bash
    printf "    threads/pane   %.2f\n", f[3]/p;
```

**Why it is wrong.** Run with `--panes 30` when the `top` reading failed (see defect 3) or, for the window columns, when the census is unavailable: `f[3]` is the string `NA`, awk evaluates `"NA"/30` as `0/30`, and the output is `threads/pane 0.00`. "Measured zero threads per pane" is the single most load-bearing claim this instrument can make about a challenger (the header's `#TH proves it`), and here it is printed from no data at all. The drift path guards this case explicitly (line ~224); the per-pane path does not.

## 11. Alacritty has a GPU discriminator but no process/owner entry, so neither spelling of `--app` works fully

**What.** The `PROC_NAMES`/`CENSUS_OWNER` table omits Alacritty entirely, while the GPU table includes it, so Alacritty falls into the `*)` branch that assumes process name == app name == CGWindow owner — the assumption the surrounding comment says is false.

**Where.** Lines ~96–102 vs ~139:
```bash
  *)               PROC_NAMES="$APP";                         CENSUS_OWNER="$APP" ;;
```
```bash
  alacritty|Alacritty) GPU_RE='OpenGL|CGL|AGX|gl[A-Z]'; CPU_RE='CoreText|CGContext' ;;
```

**Why it is wrong.** Alacritty's executable is `alacritty` (lower case) while its CGWindow owner is `Alacritty`. `--app Alacritty` makes `PROC_NAMES="Alacritty"`, so `pgrep -x` and the ps-comm-basename fallback both miss and the run exits 3 with `verdict=NO-DATA` — the wasted-run failure mode the WezTerm comment (lines ~92–95) says the table exists to prevent. `--app alacritty` finds the pid but sets `CENSUS_OWNER="alacritty"`, which does not match the census owner string, so every window column silently reports `NA` and the run still ends `verdict=OK`. The header claims all five terminals are measured by the same instrument; one of them cannot be measured by either spelling. The same mismatch exists between `kitty|kitty.app` at line ~99 and the GPU case `kitty)` at line ~138: `--app kitty.app` silently gets the generic fallback regex instead of kitty's.

## 12. Column extraction from `top` assumes the command name contains no whitespace

**What.** `cpu`, `mem`, `th` and `ports` are read as fixed awk fields `$3`–`$6`, which is only correct when the COMMAND column is a single whitespace-free token.

**Where.** Lines ~148 and ~151–154:
```bash
  line="$(run 30 top -l 2 -pid "$pid" -stats pid,command,cpu,mem,th,ports 2>/dev/null \
```
```bash
  cpu="$(awk '{print $3}' <<<"$line")"
```

**Why it is wrong.** The `*)` branch accepts any application, and the script is advertised as app-agnostic. For any target whose `top` COMMAND contains a space (e.g. a helper named `Code Helper (GPU)`), `$3` is a fragment of the command rather than CPU%, `$4` is not MEM, and so on: the mem normaliser produces a bogus MB figure, `ports` picks up a thread count, and the JSONL `t0` field records all of it as a valid row. The `show` function's comment (lines ~181–182) warns about exactly this misattribution — ports read as threads — but only guards the downstream tab split, not the upstream field extraction.

## 13. Empty census fields bypass the drift `NA` guard and are differenced as zero

**What.** The drift guard tests only for the literal string `NA`, but `reading` can emit empty fields when the census line has fewer columns than expected.

**Where.** Lines ~163–165 and ~224:
```bash
      win="$(cut -f3 <<<"$c")"; off="$(cut -f5 <<<"$c")"; mpx="$(cut -f7 <<<"$c")"
```
```bash
    [ "$a" = NA ] || [ "$b" = NA ] && { printf '    %-14s NA\n' "$label"; return; }
```

**Why it is wrong.** If the census binary emits a short row — a version skew with the stale-binary path in defect 5 makes this reachable — `cut -f5`/`-f7` return the empty string, not `NA`. `win`/`off` are then empty, the guard at line ~224 does not fire, and awk coerces `""` to 0, printing `offscreen win +0 over 300s = +0.0/hr`. A field that was never measured is reported as a measured zero drift, which under this script's own semantics is an affirmative "no leak" finding.

---

### Minor, same class

**Missing-census-source warning does not fail.** Line ~85, `[ -f "$CENSUS_SRC" ] || echo "terminal-bench: ⚠ census source not found under REPO=$REPO" >&2` — the comment directly above says "Fail loud rather than degrade to NA-everywhere", but the script only warns and continues to completion with exit 0 and (per defect 2) `verdict=OK`. The symlink-resolution work above it is what protects against this, but the stated backstop is not one.

**`panes=unset` is unreachable.** Line ~178, `echo "terminal-bench — app=$APP pid=$PID panes=${PANES:-unset} interval=${INTERVAL}s  $(date -u +%FT%TZ)"` — `PANES` is initialised to `0` at line ~53 and defaulted to `0` in the parser, so the header always prints `panes=0` and never distinguishes "not supplied" from "supplied as 0".

### Observation, not a defect

`T0_WS`/`T1_WS` are read and displayed but never differenced; `drift` reads only `T0_APP`/`T1_APP` (line ~223). The output label `DRIFT (app, constant layout …)` is honest about this, so nothing is misreported — but WindowServer port growth is the root cause the header cites, and its drift is collected and then discarded.
