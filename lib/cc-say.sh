# shellcheck shell=bash
# cc-say.sh — the ONE renderer for pane banners and Stop-readout rows (lr-wake 2026-10-18, RC8).
#
# INTERFACE (Waves C, F and H2 code to this; change it only through the lr-wake lead):
#
#   cc_say KIND VERDICT [FACT] [ACTION]
#       Prints ONE line to fd 2 (or $CC_SAY_FD): `glyph verdict · fact · ▶ action`. Always rc 0.
#       KIND     ok | wait | run | fail | warn | info | judge | foot
#                  ok ✓ green · wait ⏸ gray · run ⟳ gray · fail ✗ red · warn ⚠ amber ·
#                  info ─ gray · judge ◆ amber · foot ─ quiet gray
#       VERDICT  ≤ 6 words, answer first ("2e9ed9f2 not resumed").
#       FACT     the one fact that makes the verdict true ("next3 full 9/8"), meta gray.
#       ACTION   one pasteable command ≤ 40 chars ("cc-lr recover 2e9ed9f2"). Its bytes are printed
#                with NO SGR after `▶ `, so a drag-selection copies clean. Never truncated: when it
#                cannot share the line it moves to its own row, `  ▶ <action>` (the only 2-line case).
#       The line fits the cell budget (cc_say_width). Prose is cut with `…`, the fact first.
#       Detail never reaches the terminal unless CC_SAY_VERBOSE=1: it goes to the log (below).
#
#   cc_say_detail VERDICT [DETAIL]
#       Appends one log record (kind "detail") and prints nothing — for a stage that must stay
#       silent because another stage already said the verdict (one event, one line). Under
#       CC_SAY_VERBOSE=1 it also prints `  VERDICT · DETAIL` as a gray row.
#
#   cc_say_width            prints the cell budget lines are fitted to.
#   cc_say_cells STR        sets CC_SAY_CELLS to STR's display width (emoji count 2). No fork.
#   cc_say_cut STR N        sets CC_SAY_CUT to STR cut to ≤ N cells, ending in `…` when cut.
#   cc_say_fit PROSE [CMD]  prints PROSE, then $CC_SAY_SEP (default 3 spaces), then CMD, fitted to
#                           the budget by cutting PROSE only; a CMD that cannot fit beside a usable
#                           prose stub goes to its own row, `$CC_SAY_INDENT` + CMD. No colour. This
#                           is the primitive the Stop readout builds its multi-row block from.
#
#   env  CC_SAY_TOOL     log tag (default: basename of $0)
#        CC_SAY_DETAIL   free text → log only (or a gray row under CC_SAY_VERBOSE=1)
#        CC_SAY_VERBOSE  1 ⇒ detail rows are printed too
#        CC_SAY_COLOR    auto (default: on when the fd is a tty or the target is sm) | 1 | 0
#        NO_COLOR        set ⇒ no colour, whatever CC_SAY_COLOR says
#        CC_SAY_WIDTH    cell budget; default $COLUMNS, else 56; never above 56
#        CC_SAY_TARGET   tty (default) | sm — a Claude Code systemMessage: never emits `\e[0m`
#                        (Ink turns a full reset into white); every colour run ends by re-asserting
#                        the harness gray 153 instead
#        CC_SAY_FD       output fd (default 2)
#        CC_SAY_LOG      log path (default ~/.claude/logs/pane-say.jsonl); `off` disables it
#        CC_SAY_SID / CC_SAY_PANE  record fields (default $CLAUDE_SESSION_ID / $KITTY_WINDOW_ID)
#
# RULES it enforces (g-message-design.md §5.1): one line per event, answer first, at most one `▶`,
# ≤ 56 cells, explicit truecolor only and NEVER SGR-2 (`\e[2m` renders as nothing on some panes and
# as a different gray on others), never `\e[0m` inside a systemMessage.
#
# PORTABILITY: sourced by bash 3.2 (launchd, /bin/bash), bash 5 and zsh (lib/config-mirror.zsh),
# so it uses only the common subset: no arrays, no `[[ =~ ]]`, no `local -a`, no `printf -v`.
# No side effects at load. Character counting needs a UTF-8 locale, so every function that measures
# sets LC_ALL locally (CC_SAY_LOCALE, default en_US.UTF-8).
# Python twin with the same contract and the same log: lib/cc_say.py.

cc_say_width() {
  _cc_say_w
  printf '%s\n' "$_CC_SAY_W"
}

_cc_say_w() {
  # zsh sets COLUMNS=0 when there is no terminal: 0 means "unknown", not "zero wide".
  _CC_SAY_W="${CC_SAY_WIDTH:-${COLUMNS:-56}}"
  case "$_CC_SAY_W" in ''|*[!0-9]*|0) _CC_SAY_W=56 ;; esac
  [ "$_CC_SAY_W" -gt 56 ] && _CC_SAY_W=56
  [ "$_CC_SAY_W" -lt 12 ] && _CC_SAY_W=12
  return 0
}

# Wide (2-cell) glyphs the fleet actually prints. Everything else counts 1, which is right for the
# single-cell vocabulary above (✓ ✗ ⚠ ⏸ ⟳ ▶ ◆ ─ ▸ ·) and for ASCII.
_CC_SAY_WIDE='✅ ⛔ ❌ 📦 🚀 👤 🔧 📤 ⏳ ⏰ ⚡ ✨ 🔔 🚨 ♻️ 🔀'

cc_say_cells() {
  local LC_ALL="${CC_SAY_LOCALE:-en_US.UTF-8}"
  local s="$1" t w n rest="$_CC_SAY_WIDE "
  n=${#s}
  # a `while` over the string, not `for w in $list`: zsh does not word-split an unquoted variable
  while [ -n "$rest" ]; do
    w="${rest%% *}"; rest="${rest#* }"
    [ -n "$w" ] || continue
    case "$s" in *"$w"*)
      t="${s//"$w"/}"
      n=$(( n + (${#s} - ${#t}) / ${#w} )) ;;
    esac
  done
  CC_SAY_CELLS=$n
  return 0
}

cc_say_cut() {
  local LC_ALL="${CC_SAY_LOCALE:-en_US.UTF-8}"
  local s="$1" max="$2" k
  case "$max" in ''|*[!0-9]*) max=0 ;; esac
  cc_say_cells "$s"
  if [ "$CC_SAY_CELLS" -le "$max" ]; then CC_SAY_CUT="$s"; return 0; fi
  if [ "$max" -le 1 ]; then CC_SAY_CUT="…"; [ "$max" -le 0 ] && CC_SAY_CUT=""; return 0; fi
  k=$(( max - 1 ))
  [ "$k" -gt "${#s}" ] && k=${#s}
  while [ "$k" -gt 0 ]; do
    CC_SAY_CUT="${s:0:$k}"
    # never end a cut on a space or a separator dot: `verdict ·…` reads as broken
    case "$CC_SAY_CUT" in *" "|*" ·") k=$(( k - 1 )); continue ;; esac
    cc_say_cells "$CC_SAY_CUT"
    [ "$CC_SAY_CELLS" -le $(( max - 1 )) ] && break
    k=$(( k - 1 ))
  done
  # Prefer ending at a ` · ` boundary — whole facts, not `sin…` — when that keeps ≥ 2/3 of the row;
  # failing that, a word boundary on the same terms (`default fi…` names nothing).
  local b="" bw=0
  case "$CC_SAY_CUT" in *" · "*)
    b="${CC_SAY_CUT% · *}"; cc_say_cells "$b"
    [ $(( CC_SAY_CELLS * 3 )) -ge $(( max * 2 )) ] && bw=1 ;;
  esac
  if [ "$bw" = 0 ] && [ "${s:${#CC_SAY_CUT}:1}" != " " ]; then
    case "$CC_SAY_CUT" in *" "*)
      b="${CC_SAY_CUT% *}"; cc_say_cells "$b"
      [ $(( CC_SAY_CELLS * 3 )) -ge $(( max * 2 )) ] && bw=1 ;;
    esac
  fi
  [ "$bw" = 1 ] && CC_SAY_CUT="$b"
  CC_SAY_CUT="${CC_SAY_CUT}…"
  return 0
}

cc_say_fit() {
  local prose="$1" cmd="${2:-}" sep="${CC_SAY_SEP-   }" ind="${CC_SAY_INDENT-   }" pw cw room
  _cc_say_w
  if [ -z "$cmd" ]; then
    cc_say_cut "$prose" "$_CC_SAY_W"; printf '%s\n' "$CC_SAY_CUT"; return 0
  fi
  cc_say_cells "$sep$cmd"; cw=$CC_SAY_CELLS
  cc_say_cells "$prose"; pw=$CC_SAY_CELLS
  if [ $(( pw + cw )) -le "$_CC_SAY_W" ]; then
    printf '%s%s%s\n' "$prose" "$sep" "$cmd"; return 0
  fi
  room=$(( _CC_SAY_W - cw ))
  # Share the row only while the prose keeps ≥ 2/3 of itself (and ≥ 12 cells); a stub like
  # `research alpha: 2 pe…` says nothing, so the command takes its own row instead.
  if [ "$room" -ge 12 ] && [ $(( room * 3 )) -ge $(( pw * 2 )) ]; then
    cc_say_cut "$prose" "$room"; printf '%s%s%s\n' "$CC_SAY_CUT" "$sep" "$cmd"; return 0
  fi
  cc_say_cut "$prose" "$_CC_SAY_W"; printf '%s\n%s%s\n' "$CC_SAY_CUT" "$ind" "$cmd"
  return 0
}

# Colour on? Sets _CC_SAY_C (1/0) and the per-target reset _CC_SAY_R.
_cc_say_color() {
  local fd="${CC_SAY_FD:-2}" mode="${CC_SAY_COLOR:-auto}"
  _CC_SAY_C=0
  if [ -n "${NO_COLOR:-}" ] || [ "$mode" = 0 ]; then :
  elif [ "$mode" = 1 ]; then _CC_SAY_C=1
  elif [ "${CC_SAY_TARGET:-tty}" = sm ]; then _CC_SAY_C=1
  elif [ -t "$fd" ]; then _CC_SAY_C=1
  fi
  if [ "${CC_SAY_TARGET:-tty}" = sm ]; then _CC_SAY_R=$'\033[38;2;153;153;153m'
  else _CC_SAY_R=$'\033[39m'; fi
  return 0
}

# kind → glyph + RGB of glyph/verdict; `meta` kinds paint the whole line meta gray.
_cc_say_kind() {
  case "$1" in
    ok)    _CC_SAY_G='✓'; _CC_SAY_K='107;243;133' ;;
    fail)  _CC_SAY_G='✗'; _CC_SAY_K='255;107;107' ;;
    warn)  _CC_SAY_G='⚠'; _CC_SAY_K='255;193;7' ;;
    judge) _CC_SAY_G='◆'; _CC_SAY_K='255;193;7' ;;
    wait)  _CC_SAY_G='⏸'; _CC_SAY_K='150;150;160' ;;
    run)   _CC_SAY_G='⟳'; _CC_SAY_K='150;150;160' ;;
    foot)  _CC_SAY_G='─'; _CC_SAY_K='125;133;144' ;;
    *)     _CC_SAY_G='─'; _CC_SAY_K='150;150;160' ;;
  esac
  return 0
}

# JSON string body of $1 into _CC_SAY_JS (backslash, quote, newline, CR, tab, ESC escaped).
_cc_say_js() {
  # Replacements are UNQUOTED variables: bash 3.2 keeps the quotes of a quoted replacement literally.
  local s="$1" bs=$'\\' q='"' nl=$'\n' cr=$'\r' tb=$'\t' es=$'\033' r
  r="$bs$bs";    s=${s//"$bs"/$r}
  r="$bs$q";     s=${s//"$q"/$r}
  r="${bs}n";    s=${s//"$nl"/$r}
  r="${bs}r";    s=${s//"$cr"/$r}
  r="${bs}t";    s=${s//"$tb"/$r}
  r="${bs}u001b"; s=${s//"$es"/$r}
  _CC_SAY_JS="$s"
  return 0
}

# _cc_say_log KIND VERDICT FACT ACTION DETAIL — one JSONL record; never fails the caller.
_cc_say_log() {
  local log="${CC_SAY_LOG:-${HOME:-}/.claude/logs/pane-say.jsonl}" ts rec f
  [ "$log" = off ] && return 0
  [ -n "${HOME:-}" ] || [ -n "${CC_SAY_LOG:-}" ] || return 0
  [ -d "${log%/*}" ] || mkdir -p "${log%/*}" 2>/dev/null || return 0
  ts="${EPOCHSECONDS:-}"
  [ -n "$ts" ] || ts="$(date +%s 2>/dev/null)"
  rec="{\"ts\":${ts:-0}"
  for f in "tool=${CC_SAY_TOOL:-${0##*/}}" "sid=${CC_SAY_SID:-${CLAUDE_SESSION_ID:-}}" \
           "pane=${CC_SAY_PANE:-${KITTY_WINDOW_ID:-}}" "kind=$1" "verdict=$2" "fact=$3" \
           "action=$4" "detail=$5"; do
    _cc_say_js "${f#*=}"
    rec="$rec,\"${f%%=*}\":\"$_CC_SAY_JS\""
  done
  printf '%s}\n' "$rec" >> "$log" 2>/dev/null || true
  return 0
}

cc_say() {
  local LC_ALL="${CC_SAY_LOCALE:-en_US.UTF-8}"
  local kind="${1:-info}" verdict="${2:-}" fact="${3:-}" action="${4:-}"
  local fd="${CC_SAY_FD:-2}" head tail tw room vw own="" line m e="" kc mc ac
  _cc_say_w; _cc_say_kind "$kind"; _cc_say_color
  _cc_say_log "$kind" "$verdict" "$fact" "$action" "${CC_SAY_DETAIL:-}"

  # Fit in plain text first; colour is applied to the fitted pieces.
  tail=""; [ -n "$action" ] && tail=" · ▶ $action"
  cc_say_cells "$tail"; tw=$CC_SAY_CELLS
  room=$(( _CC_SAY_W - tw ))
  head="$_CC_SAY_G $verdict"
  cc_say_cells "$head"; vw=$CC_SAY_CELLS
  # The action shares the line only if the WHOLE verdict still fits beside it: a cut verdict is a
  # lost answer, so the action takes its own row instead (the facts are cut first, then dropped).
  if [ -n "$action" ] && [ "$vw" -gt "$room" ]; then own=1; room=$_CC_SAY_W; tail=""; fi
  if [ "$vw" -gt "$room" ]; then
    cc_say_cut "$verdict" $(( room - 2 )); verdict="$CC_SAY_CUT"; fact=""
  elif [ -n "$fact" ]; then
    m=$(( room - vw - 3 ))
    if [ "$m" -ge 8 ]; then cc_say_cut "$fact" "$m"; fact="$CC_SAY_CUT"; else fact=""; fi
  fi

  if [ "$_CC_SAY_C" = 1 ]; then
    e=$'\033['
    kc="${e}38;2;${_CC_SAY_K}m"; mc="${e}38;2;150;150;160m"; ac="${e}38;2;138;180;248m"
    line="${kc}${_CC_SAY_G} ${verdict}${_CC_SAY_R}"
    [ -n "$fact" ] && line="${line}${mc} · ${fact}${_CC_SAY_R}"
    [ -n "$tail" ] && line="${line}${mc} · ${_CC_SAY_R}${ac}▶${_CC_SAY_R} ${action}"
  else
    line="${_CC_SAY_G} ${verdict}"
    [ -n "$fact" ] && line="${line} · ${fact}"
    [ -n "$tail" ] && line="${line} · ▶ ${action}"
  fi
  printf '%s\n' "$line" >&"$fd"
  if [ -n "$own" ]; then
    if [ "$_CC_SAY_C" = 1 ]; then printf '  %s▶%s %s\n' "$ac" "$_CC_SAY_R" "$action" >&"$fd"
    else printf '  ▶ %s\n' "$action" >&"$fd"; fi
  fi
  if [ "${CC_SAY_VERBOSE:-0}" = 1 ] && [ -n "${CC_SAY_DETAIL:-}" ]; then
    _cc_say_vrow "${CC_SAY_DETAIL}"
  fi
  return 0
}

_cc_say_vrow() {
  local fd="${CC_SAY_FD:-2}"
  cc_say_cut "$1" $(( _CC_SAY_W - 2 ))
  if [ "$_CC_SAY_C" = 1 ]; then printf '  \033[38;2;150;150;160m%s%s\n' "$CC_SAY_CUT" "$_CC_SAY_R" >&"$fd"
  else printf '  %s\n' "$CC_SAY_CUT" >&"$fd"; fi
  return 0
}

cc_say_detail() {
  local LC_ALL="${CC_SAY_LOCALE:-en_US.UTF-8}"
  _cc_say_log detail "${1:-}" "" "" "${2:-}"
  if [ "${CC_SAY_VERBOSE:-0}" = 1 ]; then
    _cc_say_w; _cc_say_color
    _cc_say_vrow "${1:-}${2:+ · $2}"
  fi
  return 0
}
