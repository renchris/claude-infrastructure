# shellcheck shell=bash
# pane-successor.sh — keystroke-free successor delivery for a recycled pane. Sourced; bash 3.2 / zsh
# portable (lr-fire-resume, reso-resume-one, cc-close-attrib and the handoff-fire watcher are bash).
#
# WHY THIS EXISTS (docs/plans/RECYCLE_KEYSTROKELESS_DELIVERY.md §D1). On 2026-10-09 a recycle's watcher
# had to TYPE the successor's launch line into a cold zsh at load ~45 per core; 16 typed attempts failed
# and pane 44 stranded at a bare prompt. Every process that regains the pane's tty when claude exits
# already exists (lr-fire-resume's fall-through, reso-resume-one's, cc-close-attrib). So the recycler
# STAGES the successor here before it sends /exit, and whichever of those regains the tty RUNS it.
# Delivery becomes a local atomic rename: load can delay it but cannot fail it.
#
# THE CONTRACT. Dir ${CC_PANE_SUCCESSOR_DIR:-~/.claude/run/pane-successor} (0700); key = the pane's tty
# basename (`ttys013`).
#   · stage  <tty> <cmdfile> <meta.json> — producer; removes any old <key>.cmd, then writes <key>.json
#     then <key>.cmd, each tmp + mv, both carrying one fresh NONCE (meta `.nonce`; the .cmd's last line
#     `# cc-pane-successor-nonce: <n>`). The .cmd is self-sufficient (cd, explicit CLAUDE_CONFIG_DIR,
#     account pin, full launch line).
#     meta = {pane, pane_tty, pred_sid, watcher_pid, watcher_lstart, created_epoch, ttl_s, mode, token}.
#   · take   [tty] — consumer; claims with `mv <key>.cmd <key>.claimed.<pid>` and prints that path.
#     THE RENAME IS THE ACK: the watcher learns the outcome by whether its revoke finds the file.
#   · revoke <tty> — producer; `mv <key>.cmd <key>.revoked`. rc != 0 means the consumer won.
#   · claimed <tty> — prints "<claim path> <claim epoch>" if a claim exists.
#   · exec   <claimed> [1|0] — unset the predecessor's per-launch vars and exec the successor LOOP shell.
#   · handback <claimed> — a consumer running INSIDE that loop gives it the next claim instead of
#     exec'ing a shell of its own (see cc_pane_successor_exec for why the chain must stay flat).
#
# FAILS SAFE, which here means DO NOT CLAIM. A claim the watcher did not mean (a stale stage, another
# pane's, a file someone else could have written) runs an arbitrary launch line in the operator's pane;
# a refusal only costs the watcher's typed fallback. So take claims only on positive proof of every
# condition, and anything unreadable — no jq, garbled meta, no tty, a ps that cannot answer — is rc 1
# with nothing printed. The tty match is what keeps an expect INNER pty (cc-close-attrib running inside
# lr-fire-resume's expect) from consuming: only the process holding the pane's own tty may take. A tty
# outlives its window, though — kitty hands ttys013 to the next window opened after pane 44 closes — so
# when meta.pane and $KITTY_WINDOW_ID are BOTH numeric they must also agree (either unknown ⇒ the tty
# decides alone). And the .cmd must carry its meta's nonce: a .cmd left by a SIGKILLed watcher would
# otherwise pair with the NEXT stage's meta, whose watcher is alive, and run the dead recycle's line.
# Seams: CC_PANE_SUCCESSOR_DIR, CC_PANE_SUCCESSOR_TTY (the caller's tty), CC_PANE_SUCCESSOR_NOW (epoch).
# Kill switch: CC_PANE_SUCCESSOR=off ⇒ take always refuses (the watcher then falls back to typing).

cc_pane_successor_dir() { # → the staging directory
  printf '%s\n' "${CC_PANE_SUCCESSOR_DIR:-${HOME:-}/.claude/run/pane-successor}"
}

_cc_pane_successor_key() { # $1=tty path or basename → the key, or rc 1 if it is not a plain name
  local _k="${1##*/}"
  case "$_k" in ''|.*|*[!A-Za-z0-9._-]*) return 1 ;; esac
  printf '%s' "$_k"
}

_cc_pane_successor_own_tty() { # → the caller's own tty basename; rc 1 when stdin is not a terminal
  local _t="${CC_PANE_SUCCESSOR_TTY:-}"
  [ -n "$_t" ] || _t="$(tty 2>/dev/null)" || return 1
  case "$_t" in 'not a tty'|'') return 1 ;; esac
  _cc_pane_successor_key "$_t"
}

_cc_pane_successor_safe() { # $1=path → rc 0 iff owned by this uid and neither group- nor world-writable
  local _p="$1" _st _u _m
  [ -L "$_p" ] && return 1
  # BSD form first; a GNU stat answers `-f` with filesystem data (or an error), so the OUTPUT is
  # validated rather than the exit code before the GNU form is tried.
  _st="$(stat -f '%u %Lp' "$_p" 2>/dev/null)"
  case "$_st" in [0-9]*' '[0-7]*) ;; *) _st="$(stat -c '%u %a' "$_p" 2>/dev/null)" ;; esac
  _u="${_st%% *}"; _m="${_st#* }"
  case "$_u" in ''|*[!0-9]*) return 1 ;; esac
  case "$_m" in ''|*[!0-7]*) return 1 ;; esac
  [ "$_u" = "$(id -u 2>/dev/null)" ] || return 1
  case "$_m" in *[2367]?|*[2367]) return 1 ;; esac
  return 0
}

_cc_pane_successor_nonce() { # → a fresh hex nonce (urandom; a time/pid/RANDOM fallback)
  local _n
  _n="$(od -An -N8 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')"
  case "$_n" in ''|*[!0-9a-f]*) _n="$(date +%s 2>/dev/null)$$${RANDOM:-0}" ;; esac
  printf '%s' "$_n"
}

_cc_pane_successor_cmd_nonce() { # $1=cmd file → the nonce its last line carries, or rc 1
  local _l
  _l="$(tail -n 1 "$1" 2>/dev/null)" || return 1
  case "$_l" in '# cc-pane-successor-nonce: '*) ;; *) return 1 ;; esac
  _l="${_l#\# cc-pane-successor-nonce: }"
  case "$_l" in ''|*[!A-Za-z0-9]*) return 1 ;; esac
  printf '%s' "$_l"
}

cc_pane_successor_stage() { # $1=tty $2=cmdfile $3=meta.json → rc 0 = staged
  local _k _d _t _old _n
  _k="$(_cc_pane_successor_key "${1:-}")" || return 1
  [ -f "${2:-}" ] && [ -r "$2" ] && [ -f "${3:-}" ] && [ -r "$3" ] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  _d="$(cc_pane_successor_dir)"
  (umask 077; mkdir -p "$_d") 2>/dev/null || return 1
  chmod 700 "$_d" 2>/dev/null || return 1
  # The old .cmd goes FIRST: between this stage's two renames it would otherwise pair with the new
  # meta (a live watcher) and be takeable. The nonce below refuses it anyway; this closes the window.
  rm -f "$_d/$_k.cmd" 2>/dev/null
  [ ! -e "$_d/$_k.cmd" ] || return 1
  # A previous recycle's outcome must not read as this one's (claimed would report a stale claim).
  rm -f "$_d/$_k.revoked" 2>/dev/null
  find "$_d" -maxdepth 1 -name "$_k.claimed.*" 2>/dev/null | while IFS= read -r _old; do
    rm -f "$_old" 2>/dev/null
  done
  _n="$(_cc_pane_successor_nonce)"
  # meta FIRST, cmd LAST: the .cmd appearing is what makes the stage takeable.
  _t="$_d/.$_k.json.tmp.$$"
  if (umask 077; jq -c --arg n "$_n" '.nonce = $n' "$3" > "$_t") 2>/dev/null && mv -f "$_t" "$_d/$_k.json" 2>/dev/null; then :; else
    rm -f "$_t" 2>/dev/null; return 1
  fi
  _t="$_d/.$_k.cmd.tmp.$$"
  if (umask 077; { cat "$2"; [ -z "$(tail -c 1 "$2")" ] || printf '\n'; printf '# cc-pane-successor-nonce: %s\n' "$_n"; } > "$_t") 2>/dev/null \
     && mv -f "$_t" "$_d/$_k.cmd" 2>/dev/null; then :; else
    rm -f "$_t" 2>/dev/null; return 1
  fi
  return 0
}

cc_pane_successor_take() { # [$1=tty] → rc 0 + prints the claimed path; rc 1 (silent) on any doubt
  [ "${CC_PANE_SUCCESSOR:-on}" != off ] || return 1
  local _own _k _d _cmd _meta _row _mt _wp _ce _ttl _nc _mp _wl _cur _now _claim _kw="${KITTY_WINDOW_ID:-}"
  _own="$(_cc_pane_successor_own_tty)" || return 1
  _k="$(_cc_pane_successor_key "${1:-$_own}")" || return 1
  [ "$_k" = "$_own" ] || return 1
  _d="$(cc_pane_successor_dir)"
  _cmd="$_d/$_k.cmd"; _meta="$_d/$_k.json"
  [ -f "$_cmd" ] && [ -f "$_meta" ] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  # One jq pass that also TYPE-checks: a missing or non-numeric field yields no output, so -e fails.
  # pane may be absent or non-numeric (an iTerm session id) — it then prints "-", never an empty
  # field, because tab is IFS whitespace and `read` would collapse an empty one and shift the rest.
  _row="$(jq -er '
    def num: (tostring | test("^[0-9]+$"));
    if (.pane_tty|type) == "string" and (.watcher_lstart|type) == "string"
       and (.watcher_pid|num) and (.created_epoch|num) and (.ttl_s|num)
       and (.nonce|type) == "string" and (.nonce|test("^[A-Za-z0-9]+$"))
    then "\(.pane_tty)\t\(.watcher_pid)\t\(.created_epoch)\t\(.ttl_s)\t\(.nonce)\t\(if (.pane|num) then (.pane|tostring) else "-" end)\t\(.watcher_lstart)"
    else empty end' "$_meta" 2>/dev/null)" || return 1
  IFS="$(printf '\t')" read -r _mt _wp _ce _ttl _nc _mp _wl <<EOF
$_row
EOF
  [ "${_mt##*/}" = "$_own" ] || return 1
  # Same tty, different window ⇒ the stage belongs to a pane that has since closed.
  case "$_mp" in ''|*[!0-9]*) ;; *)
    case "$_kw" in ''|*[!0-9]*) ;; *) [ "$_mp" = "$_kw" ] || return 1 ;; esac ;;
  esac
  [ "$(_cc_pane_successor_cmd_nonce "$_cmd")" = "$_nc" ] || return 1
  case "$_wp" in ''|*[!0-9]*|0) return 1 ;; esac
  case "$_ce" in ''|*[!0-9]*) return 1 ;; esac
  case "$_ttl" in ''|*[!0-9]*) return 1 ;; esac
  _wl="$(printf '%s' "$_wl" | tr -s ' ' | sed 's/^ *//; s/ *$//')"
  [ -n "$_wl" ] || return 1
  # Watcher alive AND the same process (pid reuse ⇒ a different lstart), as lib/pane-recycle-pending.sh.
  _cur="$(TZ=UTC LC_ALL=C ps -o lstart= -p "$_wp" 2>/dev/null | tr -s ' ' | sed 's/^ *//; s/ *$//')"
  [ -n "$_cur" ] && [ "$_cur" = "$_wl" ] || return 1
  _now="${CC_PANE_SUCCESSOR_NOW:-$(date +%s 2>/dev/null)}"
  case "$_now" in ''|*[!0-9]*) return 1 ;; esac
  [ "$_now" -lt $((_ce + _ttl)) ] || return 1
  # Ownership last, immediately before the rename.
  _cc_pane_successor_safe "$_d" && _cc_pane_successor_safe "$_cmd" || return 1
  _claim="$_d/$_k.claimed.$$"
  mv -f "$_cmd" "$_claim" 2>/dev/null || return 1
  # The checks above read the .cmd by NAME; a new stage could have swapped it before the rename. What
  # was claimed must carry the nonce that was checked, or it goes back for its own consumer.
  if [ "$(_cc_pane_successor_cmd_nonce "$_claim")" != "$_nc" ]; then
    [ -e "$_cmd" ] || mv "$_claim" "$_cmd" 2>/dev/null
    return 1
  fi
  touch "$_claim" 2>/dev/null   # mtime = claim time (mv keeps the staged mtime); read by claimed
  printf '%s\n' "$_claim"
}

cc_pane_successor_revoke() { # $1=tty → rc 0 = revoked; rc != 0 = nothing left to revoke (the consumer won)
  local _k _d
  _k="$(_cc_pane_successor_key "${1:-}")" || return 2
  _d="$(cc_pane_successor_dir)"
  mv "$_d/$_k.cmd" "$_d/$_k.revoked" 2>/dev/null
}

cc_pane_successor_claimed() { # $1=tty → rc 0 + "<claim path> <claim epoch>" if a claim exists
  local _k _d _c _e
  _k="$(_cc_pane_successor_key "${1:-}")" || return 1
  _d="$(cc_pane_successor_dir)"
  _c="$(find "$_d" -maxdepth 1 -name "$_k.claimed.*" 2>/dev/null | head -1)"
  [ -n "$_c" ] && [ -f "$_c" ] || return 1
  _e="$(stat -f '%m' "$_c" 2>/dev/null)"
  case "$_e" in ''|*[!0-9]*) _e="$(stat -c '%Y' "$_c" 2>/dev/null)" ;; esac
  printf '%s %s\n' "$_c" "$_e"
}

# THE SUCCESSOR LOOP (the program cc_pane_successor_exec hands the login shell). Its claude's own
# wrapper, cc-close-attrib, is a CHILD of this shell and regains the tty when that claude exits; when it
# claims the next recycle's stage, exec'ing a fresh shell there would leave this one idle underneath —
# one more login zsh per recycle generation, forever (review 2026-10-09 item 4: gen-3 ancestry
# stub←cca←gen2 zsh←gen1 zsh). So the shell LOOPS: it exports its pid and a hand-back path, sources the
# claim, and when that returns it sources whatever claim cc_pane_successor_handback left at the path.
# The depth stays constant at one loop shell. The per-launch vars are unset before EVERY source (a
# .cmd exports its own), and the loop's two vars are unset when it ends, because the trailing login
# shell keeps the SAME pid — a claude typed there later must not hand back to a loop that is gone.
# $1 = the claimed path, $2 = the hand-back prefix (the loop appends its own pid).
# shellcheck disable=SC2016  # every $ here expands in the successor shell, not in this one
_CC_PANE_SUCCESSOR_LOOP='__ccs_f="$1"; __ccs_h="$2.$$"
export CC_PANE_SUCCESSOR_LOOP_PID="$$" CC_PANE_SUCCESSOR_HANDBACK="$__ccs_h"
while [ -n "$__ccs_f" ] && [ -f "$__ccs_f" ]; do
  unset CLAUDE_CONFIG_DIR CC_ACCOUNT_PINNED CLAUDE_ISOLATION_SKIP
  source "$__ccs_f"
  __ccs_f=""
  if [ -s "$__ccs_h" ]; then __ccs_f="$(cat "$__ccs_h")"; rm -f "$__ccs_h"; fi
done
unset CC_PANE_SUCCESSOR_LOOP_PID CC_PANE_SUCCESSOR_HANDBACK __ccs_f __ccs_h'

cc_pane_successor_exec() { # $1=claimed path, $2=1 keep a login shell after it (default) | 0 return
  local _c="${1:-}" _sh="${SHELL:-/bin/zsh}" _k _tail=''
  [ -f "$_c" ] || return 1
  _k="${_c##*/}"; _k="${_k%%.claimed.*}"
  # The predecessor's per-launch prefixes (lib/claude-launcher.zsh claudeN, handoff relaunch lines)
  # reach this process's env; the .cmd sets its own, so nothing here may leak into the successor.
  unset CLAUDE_CONFIG_DIR CC_ACCOUNT_PINNED CLAUDE_ISOLATION_SKIP
  # shellcheck disable=SC2016  # ${SHELL} expands in the successor shell, not here
  [ "${2:-1}" = 0 ] || _tail='
exec "${SHELL:-/bin/zsh}" -l -i'
  # `-l -i` is load-bearing: the launch line calls zsh FUNCTIONS defined only in the interactive rc.
  exec "$_sh" -l -i -c "$_CC_PANE_SUCCESSOR_LOOP$_tail" cc-successor "$_c" "$(cc_pane_successor_dir)/$_k.handback"
}

cc_pane_successor_handback() { # $1=claimed path → rc 0 = handed to the successor loop this process runs under
  local _c="${1:-}" _lp="${CC_PANE_SUCCESSOR_LOOP_PID:-}" _hb="${CC_PANE_SUCCESSOR_HANDBACK:-}" _p _n=0 _t
  [ -f "$_c" ] || return 1
  case "$_lp" in ''|*[!0-9]*) return 1 ;; esac
  case "$_hb" in "$(cc_pane_successor_dir)"/*.handback."$_lp") ;; *) return 1 ;; esac
  # The loop must be a LIVE ANCESTOR, not merely named in an inherited env: the launcher may run the
  # wrapper inside a `( cd … )` subshell, so a few hops are allowed; nothing further is.
  _p="${PPID:-}"
  while [ "$_p" != "$_lp" ]; do
    [ "$_n" -lt 3 ] || return 1
    _p="$(ps -o ppid= -p "$_p" 2>/dev/null | tr -d ' ')"
    case "$_p" in ''|*[!0-9]*|0|1) return 1 ;; esac
    _n=$((_n + 1))
  done
  _t="$_hb.tmp.$$"
  if (umask 077; printf '%s\n' "$_c" > "$_t") 2>/dev/null && mv -f "$_t" "$_hb" 2>/dev/null; then return 0; fi
  rm -f "$_t" 2>/dev/null
  return 1
}
