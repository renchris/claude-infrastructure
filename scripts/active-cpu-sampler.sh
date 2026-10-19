#!/bin/bash
# active-cpu-sampler.sh — CPU used by each claude session tree, for the admission gate's ACTIVE term
# (lr-wake 2026-10-18, REPORT §4 Wave B2; spec c2-capacity-admit-rescue-loop.md §5.3).
#
# WHY. capacity-admit.sh's ACTIVE term counted every session whose latest beat is `kind:"prompt"`
# (cc_sp_active). A turn blocked in `sleep`, Monitor or a background wait has that beat for as long
# as it waits, and it loads the box with nothing. Measured 2026-10-18: the rescuer 2cc3a7fa spent
# 07:12-07:41Z inside `until …; sleep 15` loops and counted as one of the 8 it was being refused
# against (c2 §2.6). The gate must count what actually loads the box: turns whose process tree is
# burning CPU. Reading that needs two samples some seconds apart, and the gate runs inside hooks and
# launchers that must never sleep, so this daemon takes the samples and the gate reads one file.
#
# WHAT IT WRITES — ${CC_ACTIVE_CPU_FILE:-~/.claude/autonomy/active-cpu.json}, atomically, every tick:
#   {"v":1, "t":<epoch>, "window_s":<s between the two samples>, "beats_live":true|false,
#    "other_cores":<CPU outside any claude tree>,
#    "trees":[{"pid":N, "lstart":"…", "cores":0.42, "mid_turn":true}, …]}
# One row per claude TREE: every process is charged to its NEAREST claude/claude.exe/claude-*
# ancestor, which is the same walk hooks/session-beat.sh makes when it records a beat's pid, so a
# tree's (pid,lstart) is exactly what a beat names. `mid_turn` is that (pid,lstart) carrying a live
# `kind:"prompt"` beat. The gate applies its own threshold (CC_ADMIT_ACTIVE_CPU_MIN_CORES) to `cores`.
#
# A LOWER BOUND, the same direction as the census it replaces. CPU of a process that is born and
# reaped between two samples is never seen (`ps` time is the process's own, not its reaped
# children's), so short fork churn is under-counted: the term under-refuses, never over-refuses.
# A process born since the previous sample is charged its whole CPU time, all of which is inside the
# window.
#
# `beats_live:false` means no beat at all was written inside CC_BEAT_LIVE_MAX_S (900): the producer's
# world is not demonstrably producing, so "no turn is mid-turn" would be manufactured out of a dead
# sensor (cc_sp_active's existence gate, same rule). The gate then falls back to the beat census.
#
# usage: active-cpu-sampler.sh            run forever, one tick every CC_ACTIVE_CPU_INTERVAL_S (15)
#        active-cpu-sampler.sh --once     one tick (the first tick only stores a baseline)
# exit 0 = tick written (or baseline stored) · 1 = this tick could not be measured · 2 = bad usage
# Env seams: CC_ACTIVE_CPU_FILE · CC_ACTIVE_CPU_INTERVAL_S · CC_ACTIVE_CPU_PS (the ps binary) ·
#   CC_BEAT_DIR · CC_BEAT_LIVE_MAX_S
# Bash 3.2 on purpose: launchd runs this under /bin/bash (lesson the-deployment-interpreter-is-not-
# the-one-on-your-path), and the tests run it there too.
set -uo pipefail

ONCE=0
case "${1:-}" in
  --once) ONCE=1 ;;
  "") : ;;
  -h|--help) sed -n '2,38p' "$0"; exit 0 ;;
  *) echo "active-cpu-sampler: unknown argument: $1" >&2; exit 2 ;;
esac

OUT="${CC_ACTIVE_CPU_FILE:-$HOME/.claude/autonomy/active-cpu.json}"
PREV="${OUT%.json}.prev"
INTERVAL="${CC_ACTIVE_CPU_INTERVAL_S:-15}"
case "$INTERVAL" in ''|*[!0-9]*|0) INTERVAL=15 ;; esac
PS_BIN="${CC_ACTIVE_CPU_PS:-ps}"
BEAT_DIR="${CC_BEAT_DIR:-$HOME/.claude/cc-beats}"
LIVE_MAX="${CC_BEAT_LIVE_MAX_S:-900}"
case "$LIVE_MAX" in ''|*[!0-9]*) LIVE_MAX=900 ;; esac

# Live `kind:"prompt"` beats as "pid<TAB>lstart" lines, preceded by one "T<max .t>" line. ONE jq over
# the beats touched in the last day (cc_sp_active's window), never one jq per file.
beats() {
  local files=() p
  [ -d "$BEAT_DIR" ] || { echo "T0"; return 0; }
  while IFS= read -r -d '' p; do files+=("$p"); done \
    < <(find "$BEAT_DIR" -maxdepth 1 -name '*.json' -mmin -1442 -print0 2>/dev/null)
  [ "${#files[@]}" -gt 0 ] || { echo "T0"; return 0; }
  # shellcheck disable=SC2016  # a jq program
  jq -r '"T\(map(select((.t|type) == "number") | .t) | max // 0)",
         (.[] | select(.kind == "prompt" and (.pid|type) == "number"
                       and ((.lstart // "") | tostring | length) > 0)
              | "\(.pid)\t\(.lstart)")' -s "${files[@]}" 2>/dev/null
}

tick() {
  local now dir snap bt tmp out
  now="$(date +%s)" || return 1
  dir="$(dirname "$OUT")"
  mkdir -p "$dir" 2>/dev/null || return 1
  snap="$dir/.active-cpu.snap.$$"
  bt="$dir/.active-cpu.beats.$$"
  tmp="$dir/.active-cpu.json.$$"
  # TZ=UTC: hooks/session-beat.sh pins TZ=UTC when it writes a beat's lstart, so the two renderings
  # are comparable by construction.
  TZ=UTC "$PS_BIN" -A -o pid=,ppid=,time=,lstart=,args= > "$snap" 2>/dev/null
  # POSITIVE CONTROL ON THE DENOMINATOR: a ps that produced nothing is a dead probe, never an idle box.
  [ -s "$snap" ] || { rm -f "$snap"; echo "active-cpu-sampler: ps produced no rows" >&2; return 1; }
  if ! beats > "$bt"; then
    rm -f "$snap" "$bt"; echo "active-cpu-sampler: beats unreadable (jq)" >&2; return 1
  fi

  out="$(awk -v now="$now" -v live_max="$LIVE_MAX" -v prevf="$PREV" -v beatf="$bt" '
    function norm(s) { gsub(/[ \t]+/, " ", s); sub(/^ /, "", s); sub(/ $/, "", s); return s }
    function secs(t,   n, a, d, s) {           # ps time: [[D-]H:]M:SS.ss → seconds
      d = 0
      if (index(t, "-") > 0) { d = substr(t, 1, index(t, "-") - 1) + 0; t = substr(t, index(t, "-") + 1) }
      n = split(t, a, ":")
      if (n == 3) s = a[1] * 3600 + a[2] * 60 + a[3]
      else if (n == 2) s = a[1] * 60 + a[2]
      else s = t + 0
      return d * 86400 + s
    }
    BEGIN {
      prev_t = ""
      while ((getline line < prevf) > 0) {
        if (prev_t == "") { prev_t = line + 0; continue }
        split(line, f, "\t"); pcpu[f[1] SUBSEP f[2]] = f[3] + 0
      }
      close(prevf)
      maxt = 0
      while ((getline line < beatf) > 0) {
        if (substr(line, 1, 1) == "T") { maxt = substr(line, 2) + 0; continue }
        split(line, f, "\t"); mid[f[1] SUBSEP norm(f[2])] = 1
      }
      close(beatf)
    }
    {
      pid = $1; ppid[pid] = $2; cpu[pid] = secs($3)
      ls[pid] = norm($4 " " $5 " " $6 " " $7 " " $8)
      exe = $9; sub(/.*\//, "", exe)
      if (exe == "claude" || exe == "claude.exe" || exe ~ /^claude-/) fam[pid] = 1
      order[++n] = pid
    }
    END {
      # The baseline for the NEXT tick, written whatever this one decides.
      print now > prevf
      for (i = 1; i <= n; i++) { p = order[i]; printf "%s\t%s\t%.2f\n", p, ls[p], cpu[p] > prevf }
      close(prevf)
      if (prev_t == "" || now - prev_t < 1) { print "BASELINE"; exit 0 }
      win = now - prev_t
      other = 0
      for (i = 1; i <= n; i++) {
        p = order[i]; k = p SUBSEP ls[p]
        d = (k in pcpu) ? cpu[p] - pcpu[k] : cpu[p]
        if (d < 0) d = 0
        r = p; hops = 0
        while (!(r in fam) && (r in ppid) && ppid[r] != r && hops < 64) { r = ppid[r]; hops++ }
        if (r in fam) used[r] += d; else other += d
      }
      live = (maxt > 0 && (maxt > now || now - maxt <= live_max)) ? "true" : "false"
      printf "{\"v\":1,\"t\":%d,\"window_s\":%d,\"beats_live\":%s,\"other_cores\":%.2f,\"trees\":[", now, win, live, other / win
      sep = ""
      for (i = 1; i <= n; i++) {
        p = order[i]
        if (!(p in fam)) continue
        printf "%s{\"pid\":%d,\"lstart\":\"%s\",\"cores\":%.3f,\"mid_turn\":%s}", sep, p, ls[p], used[p] / win, \
          (((p SUBSEP ls[p]) in mid) ? "true" : "false")
        sep = ","
      }
      print "]}"
    }' "$snap" 2>/dev/null)"
  rm -f "$snap" "$bt"
  [ -n "$out" ] || { echo "active-cpu-sampler: aggregation produced nothing" >&2; return 1; }
  [ "$out" = BASELINE ] && return 0
  printf '%s\n' "$out" > "$tmp" || { rm -f "$tmp"; return 1; }
  # Never publish a torn or malformed file: the gate would read it as a measurement.
  if command -v jq >/dev/null 2>&1 && ! jq -e '.trees | type == "array"' "$tmp" >/dev/null 2>&1; then
    rm -f "$tmp"; echo "active-cpu-sampler: refusing to publish malformed JSON" >&2; return 1
  fi
  mv -f "$tmp" "$OUT"
}

if [ "$ONCE" = 1 ]; then tick; exit $?; fi
while :; do
  tick || :
  sleep "$INTERVAL"
done
