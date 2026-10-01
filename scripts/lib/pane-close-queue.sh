# shellcheck shell=bash
# pane-close-queue.sh — the durable record of a pane close that did not happen (F-b, 2026-09-30).
#
# WHY THIS EXISTS. Every teammate closer made ONE attempt and gave up (docs/research/
# husk-panes-2026-09-30.md, root cause 4): hooks/teammate-auto-shutdown.sh logged `✗ pane close
# FAILED (rc=124)` and sent a DAMPED page, and the TeammateIdle that would have retried never fired
# again. Five husks (panes 33, 57-60) outlived their members that way while kitty remote control was
# intermittently deaf (root cause 3). A page is a notification, not a record: once damped or missed,
# nothing on disk remembered that a pane was still standing. A row here is that record, and
# scripts/pane-close-retry.sh drains it once `kitty @ ls` answers again.
#
# SOURCED, SIDE-EFFECT-FREE: defines PCQ_DIR and four functions, runs nothing, never exits, never sets
# shell options. Safe under `set -u` and /bin/bash 3.2 (launchd runs the drainer's caller there).
#
# THE INTERFACE IS FIXED (handoff-fire's self-close arm and the drainer code against it):
#   pcq_add <kind> <pane> [key=value ...]   rc 0 written · 1 not. kind ∈ teammate | self-close
#   pcq_list                                one row path per line
#   pcq_remove <row path>                   only a row inside PCQ_DIR
#   pcq_get <row path> <key>                the value, or nothing
#
# One flat JSON object per row, `<kind>-<sanitised pane>.json`, written tmp + mv so a reader never sees
# half a row. Re-adding the same kind+pane UPDATES the row (first_ts and attempts kept unless given,
# last_ts refreshed, given keys overwritten) — one stuck pane is one row however often it fails.

PCQ_DIR="${CC_PANE_CLOSE_QUEUE_DIR:-$HOME/.claude/state/pane-close-queue}"

_pcq_row_path() { # <kind> <pane> → the row's path (pane sanitised: it becomes a filename)
  printf '%s/%s-%s.json' "$PCQ_DIR" "$1" "${2//[^A-Za-z0-9._-]/_}"
}

# The no-jq leg's sanitiser: a value keeps only characters that can never break a JSON string or a
# line — no quote, no backslash, no control byte. Lossy on purpose; jq is the path that escapes.
_pcq_strict() { printf '%s' "$1" | LC_ALL=C tr -cd 'A-Za-z0-9 ._:/@+=,%~^-'; }

pcq_add() {
  local kind="${1:-}" pane="${2:-}" row tmp now kv key
  case "$kind" in teammate|self-close) ;; *) return 1 ;; esac
  [[ -n "$pane" ]] || return 1
  shift 2
  local -a pairs=()
  for kv in "$@"; do
    key="${kv%%=*}"
    [[ "$kv" == *=* && "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || return 1
    # The identity and the clock are the lib's own fields — a caller cannot rewrite which row this is.
    case "$key" in kind|pane|first_ts|last_ts) continue ;; esac
    pairs+=("$key" "${kv#*=}")
  done
  mkdir -p "$PCQ_DIR" 2>/dev/null || return 1
  row="$(_pcq_row_path "$kind" "$pane")"; tmp="$row.tmp.$$"
  now="$(date -u +%FT%TZ)"
  if command -v jq >/dev/null 2>&1; then
    local prev=/dev/null
    jq -e 'type == "object"' "$row" >/dev/null 2>&1 && prev="$row"   # a corrupt row restarts, not wedges
    # attempts stays a NUMBER (the drainer compares it); every other given value stays a string.
    jq -n --arg kind "$kind" --arg pane "$pane" --arg now "$now" --slurpfile prev "$prev" '
      ($prev[0] // {}) as $p
      | $p + {kind: $kind, pane: $pane, first_ts: ($p.first_ts // $now), last_ts: $now,
              attempts: ($p.attempts // 0)}
      | reduce range(0; $ARGS.positional | length; 2) as $i (.;
          ($ARGS.positional[$i]) as $k | ($ARGS.positional[$i + 1]) as $v
          | .[$k] = (if $k == "attempts" then ($v | tonumber? // 0) else $v end))
    ' --args ${pairs[@]+"${pairs[@]}"} > "$tmp" 2>/dev/null || { rm -f "$tmp"; return 1; }
  else
    # Degraded leg: keeps first_ts and attempts, drops any other earlier key. Never silent about
    # WHETHER a row exists, which is the property the queue is for.
    local first attempts i body
    first="$(pcq_get "$row" first_ts)"; attempts="$(pcq_get "$row" attempts)"
    body="\"kind\":\"$kind\",\"pane\":\"$(_pcq_strict "$pane")\",\"first_ts\":\"$(_pcq_strict "${first:-$now}")\",\"last_ts\":\"$now\""
    for (( i = 0; i < ${#pairs[@]}; i += 2 )); do
      [[ "${pairs[i]}" == attempts ]] && { attempts="${pairs[i+1]}"; continue; }
      body="$body,\"${pairs[i]}\":\"$(_pcq_strict "${pairs[i+1]}")\""
    done
    [[ "$attempts" =~ ^[0-9]+$ ]] || attempts=0
    printf '{%s,"attempts":%s}\n' "$body" "$attempts" > "$tmp" 2>/dev/null || { rm -f "$tmp"; return 1; }
  fi
  mv -f "$tmp" "$row" 2>/dev/null || { rm -f "$tmp"; return 1; }
}

pcq_list() {
  local f
  for f in "$PCQ_DIR"/*.json; do [[ -f "$f" ]] && printf '%s\n' "$f"; done
  return 0
}

pcq_remove() {
  local row="${1:-}"
  case "$row" in "$PCQ_DIR"/*.json) rm -f -- "$row" ;; *) return 1 ;; esac
}

pcq_get() {
  local row="${1:-}" key="${2:-}"
  [[ -f "$row" && -n "$key" ]] || return 0
  if command -v jq >/dev/null 2>&1; then
    jq -r --arg k "$key" '.[$k] // empty | tostring' "$row" 2>/dev/null
  else
    sed -n "s/.*\"$key\":\"\{0,1\}\([^\",}]*\).*/\1/p" "$row" 2>/dev/null | head -1
  fi
  return 0
}
