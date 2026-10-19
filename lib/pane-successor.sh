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
#     account pin, full launch line). A resume or transplant stage (mode `resume`, lr-wake Wave S)
#     instead wraps its launcher in `if bash handoff-fire.sh __succ-rails …; then …; fi`: the fold,
#     launch-lock and holder rails run here, at the claim, and a refusal starts nothing. The launcher
#     pins its own account, so that form exports no CLAUDE_CONFIG_DIR.
#     meta = {pane, pane_tty, pred_sid, watcher_pid, watcher_lstart, created_epoch, ttl_s, mode, token};
#     mode is fresh, resume or transplant.
#   · take   [tty] — consumer; claims with `mv <key>.cmd <key>.claimed.<pid>` and prints that path.
#     THE RENAME IS THE ACK: the watcher learns the outcome by whether its revoke finds the file.
#   · revoke <tty> — producer; `mv <key>.cmd <key>.revoked`. rc != 0 means the consumer won.
#   · claimed <tty> — prints "<claim path> <claim epoch>" if a claim exists.
#   · exec   <claimed> [1|0] — unset the predecessor's per-launch vars and exec the successor LOOP shell.
#   · handback <claimed> — a consumer running INSIDE that loop gives it the next claim instead of
#     exec'ing a shell of its own (see cc_pane_successor_exec for why the chain must stay flat).
#   · precmd — the zsh prompt hook: the interactive shell itself is a consumer (the kitty-setup rc block
#     installs it), so a pane whose claude was started from a bare prompt still claims.
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
# THE PANE'S TERMINAL, NOT WHATEVER THE PANE WAS LAUNCHED INTO (docs/research/recycle-failure-2026-10-14.md
# F2). Pane 434 was launched `zsh -lc 'reso-resume-one … 2>&1 | tee log; exec zsh -l'`; the predecessor
# ran under expect's own pty and never noticed, but this shell inherited the tee pipe as stdout, and
# Claude Code treats a non-tty stdout as print mode: no TUI, ever. So when stdin is the terminal and
# stdout or stderr is not, they are re-pointed at /dev/tty first, and the one line saying so goes to
# the new stderr. No controlling tty (the open fails even though /dev/tty is mode 666) ⇒ unchanged.
# shellcheck disable=SC2016  # every $ here expands in the successor shell, not in this one
_CC_PANE_SUCCESSOR_LOOP='__ccs_f="$1"; __ccs_h="$2.$$"
if [ -t 0 ] && { [ ! -t 1 ] || [ ! -t 2 ]; } && [ -w /dev/tty ] && (: >/dev/tty) 2>/dev/null; then
  __ccs_r="stdout and stderr were"; [ -t 1 ] && __ccs_r="stderr was"; [ -t 2 ] && __ccs_r="stdout was"
  [ -t 1 ] || exec >/dev/tty
  [ -t 2 ] || exec 2>/dev/tty
  printf "[pane-successor] %s not the terminal (a pipe or file); re-attached to /dev/tty so claude runs interactive\n" "$__ccs_r" >&2
  unset __ccs_r
fi
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

# THE PROMPT-HOOK CONSUMER (recycle-failures-kitty-2026-10-10 REPORT fix 8). Since c54a3c0bd 4 of 9
# recycles revoked the stage and fell back to typing: the process that regained the tty was a plain
# interactive zsh, which is none of the consumers above. Its next prompt is the first thing that shell
# does, so the claim runs from precmd. This runs before EVERY prompt in EVERY pane, and take forks jq,
# ps and stat, so it is gated on tests zsh evaluates in-process: nothing staged for this tty ⇒ no fork
# at all. $TTY is zsh's own parameter (a `tty` call would be a fork); it only opens the gate — take
# re-derives the tty itself and applies every guard, so a wrong $TTY can cost forks but never a claim.
# The claim replaces this shell (cc_pane_successor_exec keeps a login shell after the successor).
# A shell started before this hook existed does not have it: that case still falls back to typing.
cc_pane_successor_precmd() { # zsh precmd hook → always rc 0; on a claim it does not return
  [[ -n "${TTY:-}" && -e "${CC_PANE_SUCCESSOR_DIR:-${HOME:-}/.claude/run/pane-successor}/${TTY##*/}.cmd" ]] || return 0
  local _c
  _c="$(cc_pane_successor_take)" && [ -n "$_c" ] || return 0
  cc_pane_successor_exec "$_c"
  return 0
}

# THE ROOT-SHELL EXIT HOOK (docs/research/kitty-crash-2026-10-15/README.md § Chosen fix). Emptying a
# native-fullscreen OS window crashed the whole kitty on 2026-10-15, and a typed `exit` / Ctrl-D in a
# pane's ROOT shell is one way to empty it. So before such a shell exits it runs the fullscreen guard in
# TOGGLE mode (it leaves fullscreen first, so kitty's destroy happens windowed). A REFUSAL (rc 3: the
# window did not leave fullscreen cleanly) keeps the pane — the hook execs a fresh interactive shell
# in place of the exit, since letting it finish would empty the window in exactly the refused state;
# every other rc lets the exit proceed. It acts only when this shell is the pane's root process:
# window $KITTY_WINDOW_ID's `pid` in `kitty @ ls` is $$, or $PPID when that parent is not itself a
# shell (kitty may start the shell through a wrapper; a nested shell's parent shell is the root).
# A HANGUP means kitty is already closing the window (or died), so the hook skips — and the signal
# that proves it is kitty's own: a window kitty is closing, or a dead kitty, is not in `kitty @ ls`,
# where the root check below stops. fd 0 no longer being a tty is a cheap extra skip, not the proof
# (a pty whose master is gone still answers isatty — measured under load). Deliberately NO TRAPHUP: a
# function trap replaces zsh's own SIGHUP handling, which is what HUPs the pane's foreground job
# (review wf_bf440f65-940 measured a claude/sleep surviving the pane's close with one defined).
# zsh runs zshexit on a normal exit and on SIGHUP, not on `exec` (measured, README :367).
# Registered by THIS lib only in an interactive zsh with KITTY_WINDOW_ID set, so ~/.zshrc needs no edit
# and a shell outside kitty pays zero forks. Kill switch CC_KITTY_FS_GUARD=off; a path overrides the guard.
cc_pane_fs_zshexit() { # zsh zshexit hook → rc 0; on a guard refusal it execs a shell and does not return
  [ -n "${KITTY_WINDOW_ID:-}" ] || return 0
  [ "${CC_KITTY_FS_GUARD:-}" != off ] || return 0
  case "$KITTY_WINDOW_ID" in *[!0-9]*) return 0 ;; esac
  # A cheap early skip when fd 0 is no longer a tty. Tested on the OPEN fd 0, never by opening
  # /dev/tty — that open BLOCKS forever after a hangup (measured). The window's absence from
  # `kitty @ ls` below is the real hangup test.
  [ -t 0 ] || return 0
  local _k="${CC_TERM_KITTY:-}" _tb="" _c _pid _pc _g="${CC_KITTY_FS_GUARD:-}"
  [ -n "$_k" ] || _k="$(command -v kitty 2>/dev/null)" || _k=/Applications/kitty.app/Contents/MacOS/kitty
  for _c in "$(command -v timeout 2>/dev/null)" /opt/homebrew/bin/timeout /usr/local/bin/timeout \
            /opt/homebrew/bin/gtimeout /usr/local/bin/gtimeout; do
    [ -n "$_c" ] && [ -x "$_c" ] && { _tb="$_c"; break; }
  done
  # `kitty @ ls` bounded at 3 s: timeout(1), else perl's alarm (always on macOS).
  if [ -n "$_tb" ]; then
    _pid="$("$_tb" 3 "$_k" @ ls 2>/dev/null | jq -r --argjson w "$KITTY_WINDOW_ID" \
      '.[].tabs[].windows[] | select(.id == $w) | .pid' 2>/dev/null)"
  else
    # shellcheck disable=SC2016  # perl code, not shell
    _pid="$(/usr/bin/perl -e 'alarm shift; exec @ARGV or exit 127' 3 "$_k" @ ls 2>/dev/null | jq -r \
      --argjson w "$KITTY_WINDOW_ID" '.[].tabs[].windows[] | select(.id == $w) | .pid' 2>/dev/null)"
  fi
  case "$_pid" in ''|*[!0-9]*) return 0 ;; esac
  if [ "$_pid" != "$$" ]; then
    [ "$_pid" = "${PPID:-}" ] || return 0
    _pc="$(ps -o comm= -p "$PPID" 2>/dev/null)"
    case "${_pc##*/}" in *sh) return 0 ;; esac
  fi
  if [ -z "$_g" ]; then
    _g="${_CC_FS_LIB_DIR:+$_CC_FS_LIB_DIR/../bin/kitty-fullscreen-guard}"
    [ -n "$_g" ] && [ -x "$_g" ] || _g="${HOME:-}/.claude/bin/kitty-fullscreen-guard"
  fi
  if [ ! -x "$_g" ]; then
    printf 'cc_pane_fs_zshexit: no fullscreen guard at %s — exiting without it\n' "$_g" >&2
    return 0
  fi
  local _rc=0
  "$_g" --window "$KITTY_WINDOW_ID" --mode toggle --scope pane --tool zshexit >&2 || _rc=$?
  if [ "$_rc" = 3 ]; then
    printf 'cc_pane_fs_zshexit: last pane of a fullscreen kitty window that did not leave fullscreen cleanly — pane kept; leave fullscreen, then exit again (CC_KITTY_FS_GUARD=off overrides)\n' >&2
    exec "${SHELL:-/bin/zsh}" -i
  fi
  return 0
}

# zsh-only syntax lives in a string so bash never parses it.
if [ -n "${ZSH_VERSION:-}" ] && [ -n "${KITTY_WINDOW_ID:-}" ]; then
  # shellcheck disable=SC2016  # zsh code evaluated by zsh
  eval '
  if [[ -o interactive ]]; then
    _CC_FS_LIB_DIR=${${(%):-%x}:A:h}
    (( ${zshexit_functions[(I)cc_pane_fs_zshexit]} )) || zshexit_functions+=(cc_pane_fs_zshexit)
  fi'
fi
