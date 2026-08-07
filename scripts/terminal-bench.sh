#!/bin/bash
# terminal-bench.sh — measure what a terminal emulator costs this box, on the axes that decided the
# 2026-07-30 freeze. App-agnostic by construction: iTerm2, Ghostty, WezTerm, kitty and Alacritty are
# all measured by the same instrument, so their numbers are comparable.
#
# WHY THIS EXISTS. docs/research/iterm2-freeze-30-sessions-2026-07-30.md root-caused a UI freeze at
# ~30 concurrent Claude Code panes to WindowServer saturation plus a population of terminal window
# objects that could not be destroyed — NOT to memory, and NOT to the terminal's own CPU (iTerm2
# measured 0.0% while the UI was dead). Choosing a replacement terminal on architecture READING
# alone would repeat this repo's most expensive recorded error: existence-of-a-fast-path evidence
# (a loaded GPU driver, a warm shader cache, an enabled flag) can only refute "absent", it can never
# establish "used" (memory capability-initialized-is-not-capability-used, where a 5:1 CPU:GPU
# profile contradicted every flag). So: no terminal gets recommended here without being run.
#
# WHAT IT MEASURES, and why each axis
#   cpu/mem/threads/ports   per-pid, from the SECOND sample of `top -l 2`. Never `ps %cpu` — that is
#                           a LIFETIME average and misread WindowServer on this box by 2.3x.
#                           Threads matter specifically: iTerm2 allocates one render thread per
#                           Metal-drawn pane (upstream PTYTab.m calls it acquireScarceResources),
#                           which is why it hard-caps Metal at 6 panes/tab. A challenger that draws
#                           N panes on ONE thread is structurally different, and #TH proves it.
#                           Ports matter because WindowServer's mach-port table grew without bound
#                           during the freeze, ~16 ports per leaked window on each side.
#   windows                 via tools/terminal-bench/window-census.swift (CGWindowList, root-free,
#                           no Apple events — the AppleScript census perturbed its own subject by
#                           up to 18%).
#   GPU path TAKEN          `sample` symbol counts, not flags. See the discriminator table below.
#   DRIFT                   two readings, a known interval apart, at CONSTANT visible layout. This
#                           is the only reading that supports a leak verdict: a single offscreen
#                           window count convicts nobody, because every macOS app carries a large
#                           offscreen population (measured: Finder 20, Terminal 18, Cursor 22).
#
# READ-ONLY. Creates no panes, closes no panes, writes no preference, kills nothing. The only
# side effect is an optional append to the results JSONL.
#
# USAGE
#   scripts/terminal-bench.sh --app iTerm2 --panes 30 --interval 300
#   scripts/terminal-bench.sh --app ghostty --panes 30 --interval 300 --out /tmp/bakeoff.jsonl
#   scripts/terminal-bench.sh --app iTerm2 --interval 0      # single reading, no drift verdict
#   scripts/terminal-bench.sh --app kitty --interval 1800 --watch 30
#                                # THE LEAK RUN. Aborts the moment the layout moves, so a wasted
#                                # window costs seconds instead of the full 30 minutes. --watch 0
#                                # polls nothing; the two endpoints are still compared.
#
# VERDICT TOKENS (last line, machine-parsable — a consumer must be able to tell "measured zero"
# from "the instrument did not run", the failure recorded in memory claimed-outcome-vs-checked-outcome)
#   verdict=OK        both readings taken AND the GPU profile resolved — a full comparable row
#   verdict=PARTIAL   readings taken, but at least one of {drift, GPU profile, window census} is
#                     missing. `--interval 0` always yields PARTIAL by construction: a single
#                     reading cannot support a leak verdict, and must not be filed as if it could.
#   verdict=NO-DATA   the app is not running, or top returned nothing  (exit 3)
#   verdict=LAYOUT-DRIFT  the CONSTANT-LAYOUT precondition broke while the interval was held. The
#                     drift row is confounded, so it is NOT emitted at all  (exit 4)
#
# THE CONSTANT-LAYOUT PRECONDITION IS ENFORCED, BECAUSE verdict=OK DID NOT CERTIFY IT.
# The 2026-07-31 22:17Z 30-minute kitty run returned verdict=OK and its +10 ports/hr is unusable:
# the window census fell 36 → 19 while the interval held — 17 windows closed underneath it — and
# ports move WITH windows, so the delta cannot be separated into leaked-versus-released. The token
# attested that two readings and a GPU profile were obtained and nothing whatever about layout
# stability, so a consumer trusting it alone would file a confounded row as the clean bound it is
# not. The precondition is now measured, and a breach ABORTS rather than printing a row.
#
# WHAT THE GATE KEYS ON — and the trap in the obvious choice. It does NOT key on the `windows`
# column. That column is the ON- AND OFF-SCREEN total, and a rising offscreen count IS the leak this
# instrument exists to detect: gating on it would make a leaking terminal abort its own measurement
# and become structurally incapable of convicting. The gate is therefore asymmetric:
#     onscreen  must be UNCHANGED   — anything else means a pane opened or closed underneath the run
#     offscreen must not DECREASE   — a release event churns the population and moves ports with it
#     offscreen RISING is allowed   — that is the signal being measured, not a violation
# It is checked at both endpoints AND polled every --watch seconds, because a window that opens and
# closes inside the interval leaves the two endpoints equal while still having moved the ports.
#
# A run whose layout could not be certified at all (no window census) is PARTIAL, never OK — the
# header above has always promised that and, until 2026-07-31, the code did not implement it.
set -uo pipefail

TIMEOUT="$(command -v timeout || command -v gtimeout || true)"
run() { if [ -n "$TIMEOUT" ]; then "$TIMEOUT" "$@"; else shift; "$@"; fi; }

APP=""; PID_OVERRIDE=""; PANES=0; INTERVAL=180; SAMPLE_SECS=5; OUT=""; WATCH=30
while [ $# -gt 0 ]; do
  case "$1" in
    --app)         APP="${2:-}"; shift 2 ;;
    # 🚨 MEASURE THIS EXACT PROCESS. Name resolution below picks `pgrep -x <name> | head -1`, i.e.
    # the LOWEST pid with that name — which is the wrong one whenever more than one instance is up.
    # Measured: a film of WezTerm under 18 panes of load recorded cpu=0.0 mem=61MB th=13, because a
    # stale wezterm-gui from an earlier run outranked the instance actually being filmed. A caller
    # that already knows which window it is looking at (assets/demo/renderer-film.sh reads the pid
    # straight off the CGWindow) can say so instead of hoping the name resolves to the same process.
    --pid)         PID_OVERRIDE="${2:-}"; shift 2 ;;
    --panes)       PANES="${2:-0}"; shift 2 ;;
    --interval)    INTERVAL="${2:-180}"; shift 2 ;;
    --watch)       WATCH="${2:-30}"; shift 2 ;;
    --sample-secs) SAMPLE_SECS="${2:-5}"; shift 2 ;;
    --out)         OUT="${2:-}"; shift 2 ;;
    -h|--help)     sed -n '1,45p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done
[ -n "$APP" ] || { echo "terminal-bench: --app <AppName> is required" >&2; exit 2; }

# ── REPO ROOT, RESOLVED THROUGH THE SYMLINK CHAIN ─────────────────────────────────────────────────
# ~/.claude/scripts/ is a directory of PER-FILE SYMLINKS into this checkout, so for a script invoked
# through the live layer `dirname "$0"` is ~/.claude/scripts and `/..` is ~/.claude — which has no
# tools/. This script would then never find window-census.swift, silently report NA for every window
# column, and still exit 0. That is the exact class scripts/self-path-lint.sh ratchets against
# (three prior incidents, including the 2026-07-26 gate runaway). `pwd -P` alone is NOT sufficient:
# it resolves the DIRECTORY, not the final symlink component (memory
# self-identity-guard-must-fully-resolve), so the link chain is walked explicitly.
SELF="${BASH_SOURCE[0]}"
while [ -L "$SELF" ]; do
  _link="$(readlink "$SELF")"
  case "$_link" in
    /*) SELF="$_link" ;;
    *)  SELF="$(cd "$(dirname "$SELF")" && pwd -P)/$_link" ;;
  esac
done
REPO="${CC_REPO:-$(cd "$(dirname "$SELF")/.." && pwd -P)}"
CENSUS_SRC="$REPO/tools/terminal-bench/window-census.swift"
# Fail loud rather than degrade to NA-everywhere if the root resolved somewhere without the tool.
[ -f "$CENSUS_SRC" ] || echo "terminal-bench: ⚠ census source not found under REPO=$REPO" >&2
CENSUS_BIN="${TMPDIR:-/tmp}/window-census.$(id -u)"

# ── the app's main GUI process ────────────────────────────────────────────────────────────────────
# pgrep -x on the app name, then the bundle-name fallback. Deliberately NOT `pgrep -f`: argv on this
# box carries whole agent briefs, so a -f match counts every session that merely MENTIONS the app
# (memory pgrep-f-matches-agent-briefs — that error read 50 where the truth was 1).
# THE GUI PROCESS NAME IS NOT ALWAYS THE APP NAME, and neither is the window-server owner name.
# WezTerm's GUI process is `wezterm-gui` while its CGWindow owner is `WezTerm`; matching the app
# name alone found nothing and the run correctly reported NO-DATA — loud, but still a run wasted.
# Both names are therefore resolved from an explicit table rather than assumed equal.
case "$APP" in
  wezterm|WezTerm) PROC_NAMES="wezterm-gui WezTerm wezterm"; CENSUS_OWNER="WezTerm" ;;
  ghostty|Ghostty) PROC_NAMES="ghostty Ghostty";             CENSUS_OWNER="Ghostty" ;;
  kitty|kitty.app) PROC_NAMES="kitty";                        CENSUS_OWNER="kitty" ;;
  iTerm2|iTerm)    PROC_NAMES="iTerm2";                       CENSUS_OWNER="iTerm2" ;;
  *)               PROC_NAMES="$APP";                         CENSUS_OWNER="$APP" ;;
esac
PID=""
if [ -n "$PID_OVERRIDE" ]; then
  # Verify it: a pid that has already exited would otherwise be measured as a row of zeroes, which
  # is the vacuous pass this instrument exists to refuse.
  if kill -0 "$PID_OVERRIDE" 2>/dev/null; then
    PID="$PID_OVERRIDE"
  else
    echo "terminal-bench: --pid $PID_OVERRIDE is not running" >&2
    echo "verdict=NO-DATA"; exit 3
  fi
fi
for _p in $PROC_NAMES; do
  [ -n "$PID" ] && break
  PID="$(pgrep -x "$_p" | head -1 || true)"
  [ -n "$PID" ] && break
done
# FALLBACK, and it is not theoretical — it is the incumbent. `pgrep` CANNOT SEE iTerm2 on this box:
# not `pgrep -x iTerm2`, not `pgrep iTerm`, not `pgrep -i`, not even `pgrep -f MacOS/iTerm2`, while
# `ps` shows pid 591 plainly (measured 2026-07-31; pgrep listed 947 of 960 processes and iTerm2 was
# among the 13 it dropped). The cause is the accounting name: macOS stored iTerm2's p_comm as the
# first 16 chars of its FULL PATH — `/Applications/iT` — where kitty's is plain `kitty`. So -x can
# never match, and the whole bake-off silently lost its incumbent baseline row to a NO-DATA that
# looked like "iTerm2 isn't running".
# We match the BASENAME of ps's comm instead. Still deliberately NOT `pgrep -f`: argv on this box
# carries whole agent briefs (memory pgrep-f-matches-agent-briefs — it read 50 where the truth was 1),
# and -f would also match every session merely discussing the app.
if [ -z "$PID" ]; then
  for _p in $PROC_NAMES; do
    PID="$(ps -eo pid=,comm= | awk -v want="$_p" '{n=split($2,a,"/"); if (a[n]==want) {print $1; exit}}')"
    [ -n "$PID" ] && break
  done
fi
if [ -z "$PID" ]; then
  echo "terminal-bench: no running process named '$APP' (tried: $PROC_NAMES via pgrep -x and ps-comm-basename)" >&2
  echo "verdict=NO-DATA"; exit 3
fi
WS_PID="$(pgrep -x WindowServer | head -1 || true)"

# ── GPU-path discriminators ───────────────────────────────────────────────────────────────────────
# Per-app symbol pairs, because "is the GPU being used" has a different spelling in each renderer.
# The generic fallback counts framework-level frames and is used for any app not listed; it is
# weaker but honest, and it is never allowed to report 0:0 as a GPU verdict (see NO-DATA below).
case "$APP" in
  iTerm2)            GPU_RE='iTermMetalDriver';        CPU_RE='iTermTextDrawingHelper' ;;
  ghostty|Ghostty)   GPU_RE='Metal|renderer.*[Mm]etal'; CPU_RE='CoreText|CGContext' ;;
  wezterm*|WezTerm*) GPU_RE='wgpu|Metal';              CPU_RE='CoreText|CGContext|glyphcache' ;;
  kitty)             GPU_RE='OpenGL|CGL|AGX|gl[A-Z]';  CPU_RE='CoreText|CGContext' ;;
  alacritty|Alacritty) GPU_RE='OpenGL|CGL|AGX|gl[A-Z]'; CPU_RE='CoreText|CGContext' ;;
  *)                 GPU_RE='Metal|AGX|IOGPU|wgpu|CGL|OpenGL'; CPU_RE='CoreText|CGContext|CGSBlend' ;;
esac

# ── one reading ───────────────────────────────────────────────────────────────────────────────────
# Emits: cpu mem_mb threads ports windows offscreen mpx   (tab-separated, one line)
reading() {
  local pid="$1" owner="$2" cpu mem th ports line win off mpx
  # SECOND sample of top -l 2. The first sample of top is a lifetime average and is discarded.
  line="$(run 30 top -l 2 -pid "$pid" -stats pid,command,cpu,mem,th,ports 2>/dev/null \
          | grep -E "^[[:space:]]*${pid}[[:space:]]" | tail -1)"
  if [ -z "$line" ]; then printf 'NA\tNA\tNA\tNA\tNA\tNA\tNA\n'; return 1; fi
  cpu="$(awk '{print $3}' <<<"$line")"
  mem="$(awk '{print $4}' <<<"$line")"
  th="$(awk  '{print $5}' <<<"$line" | tr -d '+-' | cut -d/ -f1)"
  ports="$(awk '{print $6}' <<<"$line" | tr -d '+-')"
  # MEM arrives as 783M / 2594M / 1.7G — normalise to MB so drift arithmetic is meaningful.
  mem="$(awk -v m="$mem" 'BEGIN{
      v=m; sub(/[KMG][+-]?$/,"",v); u=substr(m,length(m),1);
      if(m ~ /G[+-]?$/) v=v*1024; else if(m ~ /K[+-]?$/) v=v/1024;
      printf "%.0f", v }')"

  win="NA"; off="NA"; mpx="NA"
  if [ -x "$CENSUS_BIN" ]; then
    local c; c="$(run 30 "$CENSUS_BIN" --owner "$owner" --tsv 2>/dev/null | grep -v '^owner' | grep -v '^verdict' | head -1)"
    if [ -n "$c" ]; then
      win="$(cut -f3 <<<"$c")"; off="$(cut -f5 <<<"$c")"; mpx="$(cut -f7 <<<"$c")"
    fi
  fi
  # PAD AT THE EMITTER. Tab is an IFS-*whitespace* character, so `IFS=$'\t' read` collapses a RUN
  # of delimiters into one: an empty cell does NOT produce an empty variable, it shifts every LATER
  # column one position LEFT, silently, at exit status 0. Splitting on tab explicitly (see `show`)
  # does not prevent that — only a non-empty cell does. The live sources of an empty cell here are
  # `awk '{print $5}'/'{print $6}'` on a `top` line with fewer stats columns than requested, which
  # empties th and ports while the census still answers — so the window columns slide LEFT into
  # them and the row reads th=<windows> ports=<offscreen>, the exact confusion the note above
  # `show` warns about, on the instrument that decides a terminal change. Measured on trunk:
  # `th=21 ports=20 win=1.00 off= mpx=` for a census reading windows=21 offscreen=20 mpx=1.00.
  #
  # This padding landed once already (68e17e2a) and was silently reverted by 68694672, a concurrent
  # rewrite of this file that branched before it — which is why tests/terminal-bench.bats now pins
  # it with a RED control instead of leaving it as a line the next same-file rewrite can drop.
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "${cpu:--}" "${mem:--}" "${th:--}" "${ports:--}" "${win:--}" "${off:--}" "${mpx:--}"
}

# ── build the census once (interpreted start-up is ~0.4 s, which distorts a tight loop) ───────────
CENSUS_OK=1
if [ ! -x "$CENSUS_BIN" ] || [ "$CENSUS_SRC" -nt "$CENSUS_BIN" ]; then
  if ! run 300 swiftc -O "$CENSUS_SRC" -o "$CENSUS_BIN" 2>/dev/null; then CENSUS_OK=0; fi
fi
[ -x "$CENSUS_BIN" ] || CENSUS_OK=0

echo "terminal-bench — app=$APP pid=$PID panes=${PANES:-unset} interval=${INTERVAL}s  $(date -u +%FT%TZ)"
[ "$CENSUS_OK" = 1 ] || echo "  ⚠ window census unavailable (swiftc failed) — window columns report NA"

# Split on TAB explicitly. Relying on `printf ... $(echo "$row")` word-splitting silently shifts
# every column left the moment one field is empty, which would misattribute ports to threads.
#
# The explicit split is only HALF the fix, and this note used to imply it was the whole one: tab is
# an IFS-whitespace character, so `IFS=$'\t' read` collapses a run of tabs too and an empty cell
# shifts the row here exactly as word-splitting would. What actually closes it is `reading()`
# padding every cell to "-" at the emitter; this reader is safe only because that holds.
show() {
  local label="$1" row="$2" cpu mem th ports win off mpx
  IFS=$'\t' read -r cpu mem th ports win off mpx <<<"$row"
  printf '  %s  cpu=%s mem=%sMB th=%s ports=%s win=%s off=%s mpx=%s\n' \
    "$label" "$cpu" "$mem" "$th" "$ports" "$win" "$off" "$mpx"
}

T0_APP="$(reading "$PID" "$CENSUS_OWNER")"; T0_WS="$(reading "${WS_PID:-0}" 'Window Server')"
show "T0  app " "$T0_APP"
show "T0  WS  " "$T0_WS"

# ── GPU path actually TAKEN (profile, not flag) ───────────────────────────────────────────────────
GPU_N="NA"; CPU_N="NA"; GPU_VERDICT="NO-DATA"
SAMPLE_F="${TMPDIR:-/tmp}/tb-sample.$$.txt"
if run 120 sample "$PID" "$SAMPLE_SECS" -f "$SAMPLE_F" >/dev/null 2>&1 && [ -s "$SAMPLE_F" ]; then
  GPU_N="$(grep -cE "$GPU_RE" "$SAMPLE_F" || true)"
  CPU_N="$(grep -cE "$CPU_RE" "$SAMPLE_F" || true)"
  # A 0:0 result means the discriminator did not match this binary's symbols — NOT that the app
  # renders on neither path. Reporting it as "0 GPU" would be a vacuous pass.
  if [ "$GPU_N" -gt 0 ] || [ "$CPU_N" -gt 0 ]; then GPU_VERDICT="OK"; fi
fi
if [ "$GPU_VERDICT" = OK ]; then
  printf '  GPU path taken: gpu_frames=%s cpu_frames=%s  ratio=%s\n' "$GPU_N" "$CPU_N" \
    "$(awk -v g="$GPU_N" -v c="$CPU_N" 'BEGIN{ if(c==0){print "all-GPU"} else printf "%.2f:1", g/c }')"
else
  printf '  GPU path taken: NO-DATA (discriminator matched no symbols; do NOT read as "no GPU")\n'
fi
rm -f "$SAMPLE_F"

# ── the constant-layout precondition ──────────────────────────────────────────────────────────────
# Its OWN probe rather than a re-read of reading()'s row, for two reasons: the gate must be legible
# and separately testable, and reading() captures `windows` (the on+off TOTAL) which is the wrong
# column to gate on — see the header. Emits "onscreen<TAB>offscreen", or NA/NA when it cannot answer.
layout_probe() {
  local c
  [ "$CENSUS_OK" = 1 ] || { printf 'NA\tNA\n'; return; }
  c="$(run 30 "$CENSUS_BIN" --owner "$CENSUS_OWNER" --tsv 2>/dev/null \
       | grep -v '^owner' | grep -v '^verdict' | head -1)"
  [ -n "$c" ] || { printf 'NA\tNA\n'; return; }
  printf '%s\t%s\n' "$(cut -f4 <<<"$c")" "$(cut -f5 <<<"$c")"
}

# The violation test lives in ONE place so the mid-hold poll and the endpoint check cannot drift
# apart and start disagreeing about what the precondition even is.
#   rc 0 = precondition holds · rc 1 = BROKEN · rc 2 = cannot certify (the census stayed silent)
# rc 2 is a third state on purpose: "I could not look" must never be spelled the same way as
# "I looked and it was fine" (memory claimed-outcome-vs-checked-outcome).
layout_ok() { # base_on base_off now_on now_off
  local b_on="$1" b_off="$2" n_on="$3" n_off="$4"
  case "${b_on}|${b_off}|${n_on}|${n_off}" in *NA*) return 2 ;; esac
  [ "$n_on"  -eq "$b_on"  ] || return 1
  [ "$n_off" -ge "$b_off" ] || return 1
  return 0
}

# ── drift ─────────────────────────────────────────────────────────────────────────────────────────
VERDICT="PARTIAL"; LAYOUT_STATE="n/a"
if [ "$INTERVAL" -gt 0 ]; then
  L0="$(layout_probe)"; L0_ON="$(cut -f1 <<<"$L0")"; L0_OFF="$(cut -f2 <<<"$L0")"
  echo "  … holding ${INTERVAL}s at constant layout (do not create or close panes) …"
  echo "    precondition baseline: onscreen=$L0_ON offscreen=$L0_OFF  (polling every ${WATCH}s)"

  # DEADLINE-CORRECTED hold. Counting sleeps alone would make the true elapsed INTERVAL + N×poll,
  # while the per-hour arithmetic below divides by the REQUESTED interval — the exact shape of
  # memory poll-loop-bound-excludes-its-own-check. So: sleep toward a wall-clock deadline, then
  # divide by what actually elapsed.
  HOLD_T0="$(date +%s)"; DEADLINE=$((HOLD_T0 + INTERVAL))
  LAYOUT_BROKE=""; BLIND_POLLS=0
  while :; do
    _now="$(date +%s)"; [ "$_now" -ge "$DEADLINE" ] && break
    _remain=$((DEADLINE - _now))
    if [ "$WATCH" -gt 0 ] && [ "$_remain" -gt "$WATCH" ]; then _step="$WATCH"; else _step="$_remain"; fi
    sleep "$_step"
    [ "$WATCH" -gt 0 ] || continue
    _L="$(layout_probe)"; _on="$(cut -f1 <<<"$_L")"; _off="$(cut -f2 <<<"$_L")"
    layout_ok "$L0_ON" "$L0_OFF" "$_on" "$_off"; _rc=$?
    if [ "$_rc" = 1 ]; then
      LAYOUT_BROKE="t+$(( $(date +%s) - HOLD_T0 ))s: onscreen ${L0_ON}→${_on}, offscreen ${L0_OFF}→${_off}"
      break
    elif [ "$_rc" = 2 ]; then
      BLIND_POLLS=$((BLIND_POLLS + 1))
    fi
  done
  ELAPSED=$(( $(date +%s) - HOLD_T0 )); [ "$ELAPSED" -gt 0 ] || ELAPSED=1

  # Endpoint check, closing the window the polls bracketed.
  if [ -z "$LAYOUT_BROKE" ]; then
    _L="$(layout_probe)"; _on="$(cut -f1 <<<"$_L")"; _off="$(cut -f2 <<<"$_L")"
    layout_ok "$L0_ON" "$L0_OFF" "$_on" "$_off"; _rc=$?
    [ "$_rc" = 1 ] && LAYOUT_BROKE="endpoint: onscreen ${L0_ON}→${_on}, offscreen ${L0_OFF}→${_off}"
    [ "$_rc" = 2 ] && BLIND_POLLS=$((BLIND_POLLS + 1))
  fi

  if [ -n "$LAYOUT_BROKE" ]; then
    # ABORT. Emitting the row and appending a caveat is what produced the unusable 22:17Z result:
    # the number gets quoted and the caveat does not travel with it.
    echo "  ⛔ CONSTANT-LAYOUT PRECONDITION BROKE — $LAYOUT_BROKE"
    echo "     Ports move WITH windows, so this window's mem/ports delta cannot be split into"
    echo "     leaked-versus-released. No drift row is emitted. Re-run when nothing opens or closes."
    LAYOUT_STATE="broken"; VERDICT="LAYOUT-DRIFT"
  else
    T1_APP="$(reading "$PID" "$CENSUS_OWNER")"; T1_WS="$(reading "${WS_PID:-0}" 'Window Server')"
    show "T1  app " "$T1_APP"
    show "T1  WS  " "$T1_WS"

    drift() { # field, label, unit
      local f="$1" label="$2" a b
      a="$(cut -f"$f" <<<"$T0_APP")"; b="$(cut -f"$f" <<<"$T1_APP")"
      [ "$a" = NA ] || [ "$b" = NA ] && { printf '    %-14s NA\n' "$label"; return; }
      awk -v a="$a" -v b="$b" -v s="$ELAPSED" -v l="$label" \
        'BEGIN{ d=b-a; printf "    %-14s %+.0f over %ds  = %+.1f/hr\n", l, d, s, d*3600/s }'
    }
    echo "  DRIFT (app, ${ELAPSED}s at CERTIFIED-constant layout — this is the leak instrument):"
    drift 2 "mem MB"; drift 4 "mach ports"; drift 5 "windows"; drift 6 "offscreen win"
    if [ "$BLIND_POLLS" -gt 0 ]; then
      # Not OK: the layout was unobserved for part or all of the hold, so "constant" is an
      # assumption here, not a measurement. The header has always promised PARTIAL for this.
      echo "    ⚠ layout UNCERTIFIED — the census stayed silent on $BLIND_POLLS check(s)"
      LAYOUT_STATE="uncertified"
    else
      LAYOUT_STATE="certified"; VERDICT="OK"
    fi
  fi
fi

# ── per-pane normalisation ────────────────────────────────────────────────────────────────────────
if [ "${PANES:-0}" -gt 0 ]; then
  echo "  PER-PANE at n=$PANES panes:"
  awk -v p="$PANES" -v r="$T0_APP" 'BEGIN{ split(r,f,"\t");
    printf "    threads/pane   %.2f\n", f[3]/p;
    printf "    ports/pane     %.2f\n", f[4]/p;
    printf "    MB/pane        %.1f\n",  f[2]/p;
    printf "    cpu%%/pane      %.2f\n", f[1]/p }'
fi

# FINALISE THE VERDICT BEFORE IT IS WRITTEN ANYWHERE. Until 2026-07-31 the JSONL row was appended
# ABOVE this downgrade, so a run whose stdout read PARTIAL could leave "OK" in the machine-readable
# sink — the overclaim landing in the surface a consumer parses rather than the one a human reads.
# LAYOUT-DRIFT is STICKY: a confounded window is not rescued by a resolved GPU profile, and must
# never be softened into the same token as an ordinary missing-column run.
if [ "$VERDICT" != "LAYOUT-DRIFT" ] && [ "$GPU_VERDICT" != OK ]; then VERDICT="PARTIAL"; fi

if [ -n "$OUT" ]; then
  printf '{"ts":"%s","app":"%s","pid":%s,"panes":%s,"interval":%s,"elapsed":%s,"layout":"%s","t0":"%s","gpu_frames":"%s","cpu_frames":"%s","verdict":"%s"}\n' \
    "$(date -u +%FT%TZ)" "$APP" "$PID" "${PANES:-0}" "$INTERVAL" "${ELAPSED:-0}" "$LAYOUT_STATE" \
    "$(tr '\t' ',' <<<"$T0_APP")" "$GPU_N" "$CPU_N" "$VERDICT" >> "$OUT"
  echo "  appended → $OUT"
fi

echo "verdict=$VERDICT"
[ "$VERDICT" = "LAYOUT-DRIFT" ] && exit 4
exit 0
