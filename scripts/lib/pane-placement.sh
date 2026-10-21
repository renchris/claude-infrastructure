#!/usr/bin/env bash
# pane-placement.sh — where a new kitty pane goes. ONE policy, outside handoff-fire.
# shellcheck shell=bash
#
# ── THE INTERFACE (Wave E of docs/research/lr-wake-incident-2026-10-18/REPORT.md codes to this) ──
#
#   cc_place_pane <anchor> <cwd> -- <argv…>
#
#   <anchor>  the kitty window id the new pane should appear beside (the firing or source pane),
#             or "" for none. A non-integer is treated as none: an iTerm2 UUID or a stale token
#             must never reach `--match`, where kitty would fall through to the ACTIVE window.
#   <cwd>     the new pane's working directory, or the literal `current`, meaning the ANCHOR's
#             cwd (`--cwd=current` pinned with `--source-window id:<anchor>`; without the pin
#             kitty reads the operator's active window, the 2026-08-07 pane-theft class).
#             `current` with no anchor is a usage error.
#   <argv…>   appended VERBATIM to `kitty @ launch` after the placement flags: the caller's own
#             launch options (`--var`, `--env`, …), then `--` and the program. Never a --type,
#             --location, --match, --next-to or --os-window-state: placement owns those.
#
#   stdout    the new kitty window id, digits only, on success
#   rc        0 placed · 1 nothing launched (no kitty, every launch failed) · 2 usage
#
#   Environment (all optional):
#     CC_MAX_PANES_PER_SPACE  panes an OS window may hold (default 4, the operator rule)
#     CC_PLACE_REQUESTED      what the caller asked for, logged as requested= (e.g. split-right,
#                             tab, window; default split when anchored, else os-window)
#     CC_PLACE_DETAIL         appended to the pane-spawn row's detail (provenance)
#     CC_PLACE_FOCUS=1        let the new pane take focus (default: never steal the operator's)
#     CC_PLACE_KITTY_BIN      the kitty binary (default: CC_TERM_KITTY, then `kitty` on PATH)
#     CC_TERM_KITTY_TO        the kitty socket; passed as `--to` when set
#     CC_PLACE_BOUND_BASE_S   seconds one kitty call may take at zero load (default 10)
#     CC_PLACE_LOAD_PER_CORE  seam: the load figure the split bound is scaled from
#     CC_PLACE_LOG_SH         seam: path of pane-spawn-log.sh when cc_log_pane_spawn is not loaded
#
# ── THE ORDER (REPORT §4 Wave D; operator rule: NO kitty tabs, ever; every OS window fullscreen on
#    its own Space; at most 4 vertical split panes per Space) ──────────────────────────────────────
#   1. a vsplit beside the anchor, when the anchor's OS window has exactly 1 tab and fewer than
#      CC_MAX_PANES_PER_SPACE panes;
#   2. otherwise a vsplit into the next OS window with room (1 tab, fewer than the cap, not zoomed),
#      fullest first, so overflow windows fill to 4 before another is minted: a fullscreen window
#      holding one pane is the precondition of the 2026-10-15 kitty crash (kitty-fullscreen-guard).
#      Only windows of the anchor's own kind qualify: an lr-recon rig OS window (a pane cwd under
#      /tmp/lr-rig or /tmp/lrh-<id>-cure|red, or titled with that tag) takes only panes of that
#      rig, and a rig pane never goes elsewhere. A lead placed into a rig window broke a W4 pair
#      run's containment (LR_SUSTAINED_LOAD W4b);
#   3. otherwise a NEW OS window, `--os-window-state=fullscreen`. kitty 0.48.2 applies that state
#      through toggle_fullscreen_for_os_window (glfw.c:1452), which is NATIVE fullscreen unless
#      macos_traditional_fullscreen is set (glfw.c:1379; config/kitty.conf leaves it unset), so the
#      window gets its own Space — the 2026-09-30 one-fullscreen-window-per-Desktop ruling.
#   A tab is never a choice. An unreadable census is step 3: a new fullscreen window cannot break
#   the 4-pane rule, a blind split can.
#
# ── "SPLITS TIME OUT" (the motive the rescue briefs gave for --tab) ──────────────────────────────
#   Each split attempt is bounded by base × min(4, 1 + load_per_core/10) seconds (handoff-fire's
#   hf_load_scaled formula), and the number of attempts grows with load: 1 + load_per_core/4, at
#   most 3. A timed-out launch may still have created its window, so every attempt carries a
#   one-time `--var cc_place_token=<token>` and, before any retry or fallback, the census is read
#   again and a window carrying that token is ADOPTED rather than launched twice. Only when every
#   split attempt failed does placement fall to step 3.
#
# ── THE LOG ──────────────────────────────────────────────────────────────────────────────────────
#   Every pane this file creates writes one cc_log_pane_spawn row (scripts/lib/pane-spawn-log.sh),
#   surface `window` (a split) or `os-window`, detail `cc_place_pane requested=<asked> given=<split|
#   os-window-fs> …`. A launch that created nothing writes no row (a row means a pane exists) and
#   says so on stderr.

[ -n "${CC_PANE_PLACEMENT_LOADED:-}" ] && return 0 2>/dev/null
CC_PANE_PLACEMENT_LOADED=1

_ccp_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

_ccp_err() { printf 'cc_place_pane: %s\n' "$*" >&2; }

_ccp_kitty_bin() {
  local c
  for c in "${CC_PLACE_KITTY_BIN:-}" "${CC_TERM_KITTY:-}"; do
    [ -n "$c" ] || continue
    if [ -x "$c" ] || command -v "$c" >/dev/null 2>&1; then printf '%s' "$c"; return 0; fi
  done
  command -v kitty >/dev/null 2>&1 && { printf 'kitty'; return 0; }
  [ -x /Applications/kitty.app/Contents/MacOS/kitty ] && { printf '%s' /Applications/kitty.app/Contents/MacOS/kitty; return 0; }
  return 1
}

_ccp_timeout_bin() {
  local c
  for c in "$(command -v timeout 2>/dev/null || true)" "$(command -v gtimeout 2>/dev/null || true)" \
           /opt/homebrew/bin/timeout /usr/local/bin/timeout /opt/homebrew/bin/gtimeout /usr/local/bin/gtimeout; do
    [ -n "$c" ] && [ -x "$c" ] && { printf '%s' "$c"; return 0; }
  done
  return 1
}

_ccp_load_per_core() { # → 1-min load / logical cpus, 2 decimals; "" when unreadable
  if [ -n "${CC_PLACE_LOAD_PER_CORE+set}" ]; then printf '%s' "$CC_PLACE_LOAD_PER_CORE"; return 0; fi
  local la nc
  la="$(/usr/sbin/sysctl -n vm.loadavg 2>/dev/null | tr -d '{}' | awk '{print $1}')"
  nc="$(/usr/sbin/sysctl -n hw.logicalcpu 2>/dev/null)"
  case "$nc" in ''|*[!0-9]*|0) return 0 ;; esac
  awk -v l="$la" -v n="$nc" 'BEGIN { if (l == "" || l + 0 != l) exit; printf "%.2f", l / n }'
}

# kitty @ … through the socket and, when one is available, a timeout. $1 = bound in seconds.
_ccp_kt() {
  local bound="$1"; shift
  local to=(); [ -n "${CC_TERM_KITTY_TO:-}" ] && to=(--to "$CC_TERM_KITTY_TO")
  if [ -n "$_ccp_tmo" ]; then "$_ccp_tmo" "$bound" "$_ccp_kb" @ ${to[@]+"${to[@]}"} "$@"
  else "$_ccp_kb" @ ${to[@]+"${to[@]}"} "$@"; fi
}

# The decision, over ONE `kitty @ ls`. stdin = the listing. Prints one line:
#   split <next-to window id> <os window id> <panes before> <step 1|2>
#   os-window - - <reason>
# A listing that is not kitty's JSON prints `os-window - - census-unreadable`.
_ccp_decide() { # $1=anchor $2=cap
  python3 -c '
import json, sys
anchor, cap = sys.argv[1], int(sys.argv[2])
try:
    d = json.load(sys.stdin)
    assert isinstance(d, list)
except Exception:
    print("os-window - - census-unreadable"); sys.exit(0)
def panes(t):
    return len(t.get("groups") or []) or len(t.get("windows") or [])
def room(o):
    tabs = o.get("tabs") or []
    if len(tabs) != 1: return None
    t = tabs[0]
    if t.get("layout") == "stack" or panes(t) >= cap: return None
    return t
import re
RIG_CWD = re.compile(r"^(?:/private)?/tmp/(lr-rig|lrh-[0-9A-Za-z]+-(?:cure|red))(?:/|$)")
RIG_TITLE = re.compile(r"^(lr-rig|lrh-[0-9A-Za-z]+-(?:cure|red))(?: |$)")
def rig(o):
    # the lr-recon rig root an OS window belongs to (tests/rig/lr-recon-rig.sh: every pane cwd under
    # /tmp/lr-rig or /tmp/lrh-<id>-cure|red, titled with that tag), or None for any other window
    for t in o.get("tabs") or []:
        for w in t.get("windows") or []:
            m = RIG_CWD.match(str(w.get("cwd") or "")) or RIG_TITLE.match(str(w.get("title") or ""))
            if m: return m.group(1)
    return None
home = None
if anchor.isdigit():
    for o in d:
        for t in o.get("tabs") or []:
            if any(str(w.get("id")) == anchor for w in t.get("windows") or []):
                home = o
if home is not None and room(home) is not None:
    print("split %s %s %d 1" % (anchor, home["id"], panes(home["tabs"][0]))); sys.exit(0)
cands = []
mine = rig(home) if home is not None else None
for o in d:
    if o is home: continue
    # a rig OS window takes only the panes of the same rig, and a rig pane never spills into any
    # other window: either way the arm reads a containment breach and the pair is NO-VERDICT (W4b)
    if rig(o) != mine: continue
    t = room(o)
    if t is None or not t.get("windows"): continue
    cands.append((-panes(t), o["id"], o, t))
if not cands:
    print("os-window - - %s" % ("anchor-full" if home is not None else "no-room")); sys.exit(0)
cands.sort(key=lambda c: (c[0], c[1]))
_, oid, o, t = cands[0]
ws = [w for w in t["windows"] if not w.get("is_overlay")] or t["windows"]
w = sorted(ws, key=lambda w: (w.get("columns") or 0, w.get("id") or 0))[-1]
print("split %s %s %d 2" % (w["id"], oid, panes(t)))
' "$1" "$2" 2>/dev/null || printf 'os-window - - census-unreadable\n'
}

# The id of a window carrying `cc_place_token=$1` in the listing on stdin, or nothing.
_ccp_find_token() {
  python3 -c '
import json, sys
try: d = json.load(sys.stdin)
except Exception: sys.exit(0)
for o in d if isinstance(d, list) else []:
    for t in o.get("tabs") or []:
        for w in t.get("windows") or []:
            if (w.get("user_vars") or {}).get("cc_place_token") == sys.argv[1]:
                print(w["id"]); sys.exit(0)
' "$1" 2>/dev/null
}

_ccp_log() { # $1=surface $2=id $3=cwd $4=given $5=extra
  if ! command -v cc_log_pane_spawn >/dev/null 2>&1; then
    local f
    for f in "${CC_PLACE_LOG_SH:-}" "$_ccp_dir/pane-spawn-log.sh" \
             "${CLAUDE_CONFIG_DIR:-${HOME:-}/.claude}/scripts/lib/pane-spawn-log.sh" "${HOME:-}/.claude/scripts/lib/pane-spawn-log.sh"; do
      # shellcheck disable=SC1090  # runtime-resolved source; the ship gate runs shellcheck without -x
      [ -n "$f" ] && [ -f "$f" ] && . "$f" && break
    done
  fi
  command -v cc_log_pane_spawn >/dev/null 2>&1 || return 0
  cc_log_pane_spawn "$1" kitty "$2" "$3" "cc_place_pane requested=$_ccp_req given=$4 $5${CC_PLACE_DETAIL:+ $CC_PLACE_DETAIL}"
}

cc_place_pane() {
  local anchor="${1-}" cwd="${2-}"
  if [ "$#" -lt 3 ] || [ "${3-}" != "--" ]; then
    _ccp_err "usage: cc_place_pane <anchor> <cwd> -- <argv…>"; return 2
  fi
  shift 3
  case "$anchor" in *[!0-9]*) anchor="" ;; esac
  if [ -z "$cwd" ] || { [ "$cwd" = current ] && [ -z "$anchor" ]; }; then
    _ccp_err "usage: a cwd is required, and \`current\` needs an anchor"; return 2
  fi
  local _ccp_kb _ccp_tmo _ccp_req
  _ccp_kb="$(_ccp_kitty_bin)" || { _ccp_err "no kitty binary"; return 1; }
  _ccp_tmo="$(_ccp_timeout_bin || true)"
  _ccp_req="${CC_PLACE_REQUESTED:-$([ -n "$anchor" ] && echo split || echo os-window)}"
  local cap="${CC_MAX_PANES_PER_SPACE:-4}"
  case "$cap" in ''|*[!0-9]*|0) cap=4 ;; esac

  local lpc base bound tries
  lpc="$(_ccp_load_per_core)"
  base="${CC_PLACE_BOUND_BASE_S:-10}"
  case "$base" in ''|*[!0-9]*|0) base=10 ;; esac
  bound="$(awk -v b="$base" -v l="${lpc:-0}" 'BEGIN { f = 1 + (l + 0) / 10; if (f > 4) f = 4; printf "%d", b * f }')"
  tries="$(awk -v l="${lpc:-0}" 'BEGIN { n = 1 + int((l + 0) / 4); if (n > 3) n = 3; print n }')"
  [ -n "$_ccp_tmo" ] || tries=1

  local cwd_args=() focus_split=(--dont-take-focus) focus_os=(--keep-focus)
  if [ "$cwd" = current ]; then cwd_args=(--source-window "id:$anchor" --cwd=current)
  else cwd_args=(--cwd="$cwd"); fi
  [ "${CC_PLACE_FOCUS:-0}" = 1 ] && { focus_split=(); focus_os=(); }

  local ls decision kind target osw before step token id="" try=0 out
  ls="$(_ccp_kt "$bound" ls 2>/dev/null)" || ls=""
  decision="$(printf '%s' "$ls" | _ccp_decide "$anchor" "$cap")"
  read -r kind target osw before step <<EOF
$decision
EOF
  token="$(date +%s)-$$-${RANDOM}${RANDOM}"

  if [ "$kind" = split ]; then
    while [ "$try" -lt "$tries" ]; do
      try=$((try + 1))
      # step 2 splits a window in ANOTHER OS window: `current` still means the anchor's cwd, so
      # the pin stays on the anchor while --next-to names the pane being split
      out="$(_ccp_kt "$bound" launch --type=window --location=vsplit --match "window_id:$target" --next-to "id:$target" \
             "${cwd_args[@]}" ${focus_split[@]+"${focus_split[@]}"} \
             --var "cc_place_token=$token" "$@" 2>/dev/null)" || out=""
      id="$(printf '%s' "$out" | tr -d '[:space:]')"
      case "$id" in ''|*[!0-9]*) id="" ;; esac
      if [ -z "$id" ]; then
        # a timed-out launch may have landed anyway: adopt it rather than launch twice
        id="$(_ccp_kt "$bound" ls 2>/dev/null | _ccp_find_token "$token")"
        case "$id" in ''|*[!0-9]*) id="" ;; esac
      fi
      if [ -n "$id" ]; then
        _ccp_log window "$id" "$cwd" split "anchor:${anchor:--} os_window:$osw step:$step panes_before:$before tries:$try load_per_core:${lpc:-?}"
        printf '%s' "$id"; return 0
      fi
    done
    _ccp_err "split into OS window $osw failed $try time(s) (bound ${bound}s, load/core ${lpc:-?}); opening a fullscreen OS window instead"
    target="split-failed"
  else
    target="$before"     # the reason (no-room, anchor-full, census-unreadable)
  fi

  out="$(_ccp_kt "$bound" launch --type=os-window "${cwd_args[@]}" --os-window-state=fullscreen ${focus_os[@]+"${focus_os[@]}"} \
         --var "cc_place_token=$token" "$@" 2>/dev/null)" || out=""
  id="$(printf '%s' "$out" | tr -d '[:space:]')"
  case "$id" in ''|*[!0-9]*) id="" ;; esac
  if [ -z "$id" ]; then
    id="$(_ccp_kt "$bound" ls 2>/dev/null | _ccp_find_token "$token")"
    case "$id" in ''|*[!0-9]*) id="" ;; esac
  fi
  if [ -z "$id" ]; then
    _ccp_err "no pane was created (os-window launch failed; bound ${bound}s, load/core ${lpc:-?})"
    return 1
  fi
  _ccp_log os-window "$id" "$cwd" os-window-fs "anchor:${anchor:--} reason:$target tries:$try load_per_core:${lpc:-?}"
  printf '%s' "$id"
}

# CLI: `pane-placement.sh <anchor> <cwd> -- <argv…>` runs cc_place_pane (for callers in other
# languages and for operators); sourcing defines the function and runs nothing.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  cc_place_pane "$@"
  exit $?
fi
