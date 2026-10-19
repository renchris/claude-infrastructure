# shellcheck shell=bash
# hook-timing-fold.sh — ht_fold, the off-prompt-path half of hooks/lib/hook-timing.sh (read that
# header for the stamp format, the row schema and why the rows are not in idl.jsonl). Sourced only by
# session-beat.sh's detached prompt worker. bash 3.2.

_ht_ms() { # <epoch seconds, decimal> → _HT_MS = milliseconds, integer (no fork)
  local s="${1%%.*}" f=000
  case "$1" in *.*) f="${1#*.}000"; f="${f:0:3}" ;; esac
  case "$s$f" in ''|*[!0-9]*) _HT_MS=""; return 1 ;; esac
  _HT_MS=$(( 10#$s * 1000 + 10#$f ))
}

_ht_mt() { # <path> → _HT_MT = its mtime from the fold's one stat (rc 1 when it was not stat'ed)
  local e
  _HT_MT=""
  for e in ${_HT_MTS[@]+"${_HT_MTS[@]}"}; do [ "${e%=*}" = "$1" ] && { _HT_MT="${e##*=}"; return 0; }; done
  return 1
}

# ht_fold — settle every finished (or dead) stamp pair into the ledger. Forks: one stat, one date,
# one rm; none when the directory holds no `.s`. bash 3.2 + `set -u`: every array expansion is
# guarded with ${a[@]+…}, because 3.2 calls an empty array unbound.
ht_fold() {
  local d="${CC_HOOK_TIMING_DIR:-$HOME/.claude/state/hook-timing}"
  local led="${CC_HOOK_TIMING_LEDGER:-$HOME/.claude/logs/hook-timing.jsonl}"
  local f b pid line rows="" i nowmt="" now mark
  local claimed=() live=() stf=()
  _HT_MTS=()
  [ -d "$d" ] || return 0
  for f in "$d"/*.s; do
    [ -e "$f" ] || continue
    b="${f%.s}"; pid="${b##*.}"
    case "$pid" in ''|*[!0-9]*) continue ;; esac
    # Finished, or gone without an end (killed): claim it. Still running: an age check below, so a
    # pid recycled into a live process cannot hold a dead hook's stamp forever.
    if [ ! -e "$b.e" ] && kill -0 "$pid" 2>/dev/null; then live+=("$f"); continue; fi
    mv "$f" "$f.F$$" 2>/dev/null || continue
    claimed+=("$b")
  done
  [ "${#claimed[@]}" -gt 0 ] || [ "${#live[@]}" -gt 0 ] || return 0
  # "now" is a marker file's mtime, so it comes from the same clock as the stamps.
  mark="$d/.now.$$"; : > "$mark" 2>/dev/null
  stf=("$mark")
  for b in ${claimed[@]+"${claimed[@]}"}; do stf+=("$b.s.F$$"); [ -e "$b.e" ] && stf+=("$b.e"); done
  for f in ${live[@]+"${live[@]}"}; do stf+=("$f"); done
  [ -f "$led" ] && stf+=("$led")
  local mt sz rest ledsz=0
  while IFS= read -r line; do
    mt="${line%% *}"; rest="${line#* }"; sz="${rest%% *}"; rest="${rest#* }"
    [ "$rest" = "$led" ] && { ledsz="$sz"; continue; }
    _HT_MTS+=("$rest=$mt")
  done < <(stat -f '%Fm %z %N' "${stf[@]}" 2>/dev/null)
  _ht_mt "$mark" && _ht_ms "$_HT_MT" && nowmt="$_HT_MS"
  for f in ${live[@]+"${live[@]}"}; do
    _ht_mt "$f" && _ht_ms "$_HT_MT" && [ -n "$nowmt" ] && [ $(( nowmt - _HT_MS )) -gt 3600000 ] || continue
    mv "$f" "$f.F$$" 2>/dev/null || continue
    claimed+=("${f%.s}"); _HT_MTS+=("$f.F$$=$_HT_MT")
  done
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo '?')"
  local hook ev rt0 rc rt1 sid t0 ms disp clk s0 e0
  for b in ${claimed[@]+"${claimed[@]}"}; do
    hook="${b##*/}"; hook="${hook%.*}"
    ev=""; rt0=""; rc=""; rt1=""; sid=""; e0=""; disp=killed
    read -r ev rt0 < "$b.s.F$$" 2>/dev/null
    _ht_mt "$b.s.F$$"; s0="$_HT_MT"
    if [ -e "$b.e" ]; then
      read -r rc rt1 sid < "$b.e" 2>/dev/null
      _ht_mt "$b.e"; e0="$_HT_MT"; disp=timed
    fi
    [ "$rt0" = - ] && rt0=""; [ "$rt1" = - ] && rt1=""; [ "$sid" = - ] && sid=""
    case "$ev" in ''|*[!A-Za-z]*) ev=UserPromptSubmit ;; esac
    case "$rc" in ''|*[!0-9]*) rc=null ;; esac
    case "$sid" in ''|*[!0-9A-Za-z_-]*) sid="?" ;; esac
    clk=mtime; t0="$s0"; ms=""
    if [ -n "$rt0" ] && [ -n "$rt1" ] && _ht_ms "$rt0"; then
      i="$_HT_MS"; _ht_ms "$rt1" && { ms=$(( _HT_MS - i )); clk=rt; t0="$rt0"; }
    fi
    if [ -z "$ms" ] && _ht_ms "$s0"; then
      i="$_HT_MS"
      if [ -n "$e0" ]; then _ht_ms "$e0" && ms=$(( _HT_MS - i ))
      elif [ -n "$nowmt" ]; then ms=$(( nowmt - i )); fi   # killed: the age it had reached by now
    fi
    case "$ms" in ''|-*) ms=null ;; esac
    case "$t0" in ''|*[!0-9.]*) t0=null ;; esac
    rows="$rows{\"ts\":\"$now\",\"hook\":\"$hook\",\"sid\":\"$sid\",\"disposition\":\"$disp\",\"reason\":\"$ev\",\"t0\":$t0,\"ms\":$ms,\"rc\":$rc,\"clock\":\"$clk\"}"$'\n'
  done
  if [ -n "$rows" ]; then
    [ -d "${led%/*}" ] || mkdir -p "${led%/*}" 2>/dev/null
    # One generation of history: the ledger grows ~2 MB a day at ~7 rows per prompt.
    case "$ledsz" in *[!0-9]*) ledsz=0 ;; esac
    [ "$ledsz" -gt "${CC_HOOK_TIMING_MAX_BYTES:-20971520}" ] && mv -f "$led" "$led.1" 2>/dev/null
    printf '%s' "$rows" >> "$led" 2>/dev/null
  fi
  stf=("$mark")
  for b in ${claimed[@]+"${claimed[@]}"}; do stf+=("$b.s.F$$" "$b.e"); done
  rm -f "${stf[@]}"
  return 0
}
