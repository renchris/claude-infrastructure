#!/usr/bin/env bash
# context-econ.sh — shared context-economics SIGNALS for the recycle/boundary hooks (2026-07-20).
#
# WHY (operator goal): "know intelligently, not hardcoded, when to recycle" needs three signals no
# single threshold carries — VELOCITY (burn rate → forecast minutes to the auto-compact wall),
# VALUE (is a live 2-way exchange in flight? a conversation leaves NO git/mailbox trace, so the
# S1–S5 holds misclassify it as idle — the "74% mid-conversation" incident), and the existing FILL.
# This lib computes the first two; the consuming hooks (waiting-recycle.sh, boundary-handoff.sh)
# compose them onto their tier policies. Design + ground-truth corpus:
# docs/research/context-econ-2026-07-20.md.
#
# CONTRACT: pure readers except ce_sample (appends one line to the per-SID history file). Sourced
# by hooks — set -u safe, NO set -e, every seam guarded; a signal failure must degrade to the
# pre-upgrade behavior ("0 -1" / empty), never cost the hook. All output on stdout, exit 0 always.
#
# Env seams (tests): CC_CE_WIN_S · CC_CE_WALL · CC_CE_MIN_SPAN_S · CC_CE_HIST_MAX ·
#                    CC_CE_TAIL_BYTES · CC_CE_AUTO_RX

# ce_sample <tel_json> — append "ts used_pct input_tokens" to <tel_json%.json>.hist iff the
# telemetry ts is strictly newer than the last recorded sample (idempotent across hooks polling the
# same file). A fill DROP > 2 points means the window was compacted/replaced — the prior slope is
# poisoned, so the series restarts at the new sample. Bounded: prune to HIST_MAX/2 lines when the
# file exceeds CC_CE_HIST_MAX (default 120).
ce_sample() {
  local tel="${1:-}" hist ts used tok last last_ts last_used max lines
  { [ -n "$tel" ] && [ -f "$tel" ]; } || return 0
  command -v jq >/dev/null 2>&1 || return 0
  hist="${tel%.json}.hist"
  # every substitution carries a fallback: the lib must survive errexit callers too (contract above)
  ts="$(jq -r '.ts // 0' "$tel" 2>/dev/null || echo '')"; ts="${ts%.*}"
  case "$ts" in ''|*[!0-9]*) return 0 ;; esac
  [ "$ts" -gt 0 ] || return 0
  used="$(jq -r '.used_pct // empty' "$tel" 2>/dev/null || echo '')"; used="${used%.*}"
  case "$used" in ''|*[!0-9]*) return 0 ;; esac
  tok="$(jq -r '.input_tokens // 0' "$tel" 2>/dev/null || echo 0)"; tok="${tok%.*}"
  case "$tok" in ''|*[!0-9]*) tok=0 ;; esac
  last="$(tail -1 "$hist" 2>/dev/null || true)"
  last_ts="${last%% *}"; case "$last_ts" in ''|*[!0-9]*) last_ts=0 ;; esac
  [ "$ts" -gt "$last_ts" ] || return 0
  if [ "$last_ts" -gt 0 ]; then
    last_used="$(printf '%s' "$last" | awk '{print $2}' 2>/dev/null)"
    case "$last_used" in ''|*[!0-9]*) last_used=0 ;; esac
    if [ "$used" -lt $(( last_used - 2 )) ]; then
      printf '%s %s %s\n' "$ts" "$used" "$tok" > "$hist" 2>/dev/null || true
      return 0
    fi
  fi
  printf '%s %s %s\n' "$ts" "$used" "$tok" >> "$hist" 2>/dev/null || true
  max="${CC_CE_HIST_MAX:-120}"
  lines="$(wc -l < "$hist" 2>/dev/null | tr -d ' ')"; case "$lines" in ''|*[!0-9]*) lines=0 ;; esac
  if [ "$lines" -gt "$max" ]; then
    if tail -n $(( max / 2 )) "$hist" > "$hist.tmp.$$" 2>/dev/null; then
      mv -f "$hist.tmp.$$" "$hist" 2>/dev/null || rm -f "$hist.tmp.$$" 2>/dev/null
    else
      rm -f "$hist.tmp.$$" 2>/dev/null
    fi
  fi
  return 0
}

# ce_burn <tel_json> — echo "burn_x100 forecast_min".
#   burn_x100:   fill velocity, pct-points/min ×100 (integer), slope oldest-in-window → newest.
#   forecast_min: minutes until CC_CE_WALL (default 88) at that velocity, from the newest sample;
#                 0 = at/past the wall already; -1 = unknown (sparse/flat/declining — the honest
#                 answer; consumers MUST treat -1 as "no forecast", i.e. legacy behavior).
# Trust gate: ≥2 samples spanning ≥ CC_CE_MIN_SPAN_S (120s) inside CC_CE_WIN_S (900s).
ce_burn() {
  local tel="${1:-}" hist win minspan wall now cut first_ts first_used last_ts last_used span d burn remaining fc
  win="${CC_CE_WIN_S:-900}"; minspan="${CC_CE_MIN_SPAN_S:-120}"; wall="${CC_CE_WALL:-88}"
  hist="${tel%.json}.hist"
  { [ -n "$tel" ] && [ -s "$hist" ]; } || { printf '0 -1'; return 0; }
  now="$(date +%s)"; cut=$(( now - win ))
  # one pass: oldest sample not older than the window start, plus the newest sample
  read -r first_ts first_used last_ts last_used <<EOF
$(awk -v cut="$cut" '
      ($1+0) >= cut { if (!seen) { ft=$1; fu=$2; seen=1 } lt=$1; lu=$2 }
      END { if (!seen) print 0,0,0,0; else print ft+0, fu+0, lt+0, lu+0 }' "$hist" 2>/dev/null)
EOF
  first_ts="${first_ts:-0}"; first_used="${first_used:-0}"; last_ts="${last_ts:-0}"; last_used="${last_used:-0}"
  [ "$first_ts" -gt 0 ] 2>/dev/null || { printf '0 -1'; return 0; }
  span=$(( last_ts - first_ts ))
  [ "$span" -ge "$minspan" ] || { printf '0 -1'; return 0; }
  d=$(( last_used - first_used ))
  [ "$d" -gt 0 ] || { printf '0 -1'; return 0; }
  burn=$(( d * 6000 / span ))
  [ "$burn" -gt 0 ] || { printf '0 -1'; return 0; }
  remaining=$(( wall - last_used ))
  if [ "$remaining" -le 0 ]; then fc=0; else fc=$(( remaining * 100 / burn )); fi
  printf '%s %s' "$burn" "$fc"
  return 0
}

# ce_last_interactive_age <transcript_path> — echo the age in seconds of the last INTERACTIVE turn,
# or the empty string when none is visible in the bounded tail (CC_CE_TAIL_BYTES, default 2MB —
# recency needs the tail only; an interactive turn older than the tail is old enough not to hold).
#
# INTERACTIVE (ground-truthed against production transcripts, 2026-07-20):
#   type=="user" AND isMeta != true AND content is a string (or text blocks with NO tool_result)
#   AND the text does not match the auto-traffic regex. Auto-drive re-prompts (session-continue 🔧
#   loops, /goal Stop hooks) arrive as isMeta:true AND "Stop hook feedback:"-prefixed — excluded on
#   two independent axes, so an auto-driven desk still reads as NON-interactive (load-bearing: a
#   conversation-hold that counted its own auto-drive would deadlock every free-win recycle).
#   Operator slash-commands (<command-name>) COUNT (the operator is present); their paired
#   <local-command-stdout> echo, task-notifications, interrupt markers, and our own ⟳/⚑/⚠ hook
#   advisories do not.
ce_last_interactive_age() {
  local tp="${1:-}" tailb rx ep now
  { [ -n "$tp" ] && [ -f "$tp" ]; } || { printf ''; return 0; }
  command -v jq >/dev/null 2>&1 || { printf ''; return 0; }
  tailb="${CC_CE_TAIL_BYTES:-2000000}"
  rx="${CC_CE_AUTO_RX:-^<task-notification>|^<local-command-stdout>|^Stop hook feedback:|^\\[Request interrupted|^⟳|^⚑|^⚠}"
  # fromjson? drops the (possibly partial) first tailed line; `objects`/`strings` guard scalar lines
  # so one odd line can never abort the scan (jq runtime errors are per-program, not per-line).
  ep="$(tail -c "$tailb" "$tp" 2>/dev/null | jq -Rr --arg rx "$rx" '
      fromjson? | objects
      | select(.type=="user") | select(.isMeta != true)
      | (.message.content) as $c
      | ( if ($c|type)=="string" then $c
          elif ($c|type)=="array" and ([$c[]? | select(.type?=="tool_result")] | length)==0
          then ([$c[]? | select(.type?=="text") | .text] | join("\n"))
          else empty end ) as $t
      | select(($t|length) > 0)
      | select($t | test($rx) | not)
      | (.timestamp | strings | sub("\\.[0-9]+Z$"; "Z") | try fromdateiso8601 catch empty)
    ' 2>/dev/null | tail -1)"
  case "$ep" in ''|*[!0-9]*) printf ''; return 0 ;; esac
  now="$(date +%s)"
  if [ "$now" -ge "$ep" ]; then printf '%s' $(( now - ep )); else printf '0'; fi
  return 0
}
