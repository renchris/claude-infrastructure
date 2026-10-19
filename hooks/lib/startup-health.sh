# shellcheck shell=bash
# startup-health.sh — the READ side of the startup sentinels (sourced; bash 3.2).
#
# hooks/lib/startup-sentinel.sh (unit 3.1) leaves <hook>.start / <hook>.done per own sync SessionStart
# hook. A `.done` with rc 0 does NOT prove delivery: the harness discards the output of hooks that
# finish inside its lag (docs/research/startup-hooks-2026-10-18/gap-G3.md F3), and foreign project
# hooks leave no sentinel at all. The session's own transcript is the authority: its SessionStart
# `hook_cancelled` records name every cancelled hook, own or foreign (gap-G3 F1). This lib reads them
# off the prompt path and turns them into per-hook verdicts (README §5 unit 3.4).
#
# Callers:
#   hooks/session-beat.sh   detached prompt worker → sh_worker (scan once per start epoch)
#   bin/cc-startup-health   read-only report and the off-path fleet fold
#
# Files under "$R/<sid>/" (R=${CC_STARTUP_HEALTH_DIR:-$HOME/.claude/state/startup-health}; the
# binding contract is in the 3.1 header and README §5 Wave 3):
#   cancels.tsv          one row per SessionStart hook_cancelled record:
#                        command<TAB>hookName<TAB>durationMs<TAB>timeoutMs. Empty = scanned, none.
#                        Written LAST (temp + mv), so a reader that sees it current sees every verdict.
#   <hook>.verdict       confirmed | cleared | nothing-owed — for every own hook with a `.start`, and
#                        for an own hook cancelled before its sentinel opened
#   foreign-<n>.verdict  `confirmed <command>` — row <n> of cancels.tsv, a hook with no sentinel
#
# START EPOCH. A resumed session keeps its sid, so its hooks rewrite `.start` while `session.start`
# (first writer only) still holds the original offset. "Current" therefore always means "not older
# than the newest .start": a cancels.tsv older than that is a previous epoch's scan. Records are kept
# only from SH_FLOOR_S (30 s) before the newest .start, so a resume or a fork whose transcript carries
# an earlier start's cancels never reports them again (README §5 3.4 fixture d).
#
# Kill switch: CC_STARTUP_HEALTH=0 (reader side; the sentinels have their own).

_SH_LIBDIR="${BASH_SOURCE[0]%/*}"
SH_OWN="session-start-dispatch dod-persist mailbox-drain desk-brief-inject"
SH_CAP_BYTES=524288      # first user record: p99 165 KB, max 336 KB (gap-G3 F1)
SH_FLOOR_S=30

sh_dir() { # <sid> → SH_D (empty when the sid is not path-safe). Builtins only.
  SH_D=""
  case "${1:-}" in ''|*[!0-9A-Za-z-]*) return 1 ;; esac
  SH_D="${CC_STARTUP_HEALTH_DIR:-$HOME/.claude/state/startup-health}/$1"
}

sh_read_done() { # <dir> <hook> → SH_DONE (0|1) SH_RC SH_EL SH_OWED SH_TMO. Builtins only.
  local k v
  SH_DONE=0; SH_RC=""; SH_EL=0; SH_OWED=0; SH_TMO=5000
  [ -f "$1/$2.done" ] || return 0
  SH_DONE=1
  while IFS='=' read -r k v; do
    case "$k" in
      rc) SH_RC="$v" ;; elapsed_s) SH_EL="$v" ;; owed) SH_OWED="$v" ;; timeout_ms) SH_TMO="$v" ;;
    esac
  done < "$1/$2.done"
  case "$SH_EL" in ''|*[!0-9]*) SH_EL=0 ;; esac
  case "$SH_OWED" in ''|*[!0-9]*) SH_OWED=0 ;; esac
  case "$SH_TMO" in ''|*[!0-9]*) SH_TMO=5000 ;; esac
}

# sh_possible <dir> <hook> → SH_REASON, empty when the sentinel alone shows no possible loss.
# Valid at the FIRST prompt, when every sync SessionStart hook has ended or been cancelled. The
# − 1 s margin covers the sentinel starting after the harness spawned the hook (gap-G3 F3).
# Builtins only — it runs on the prompt path.
# shellcheck disable=SC2034  # SH_REASON is this function's result, read by its callers
sh_possible() {
  SH_REASON=""
  sh_read_done "$1" "$2"
  if [ "$SH_DONE" = 0 ]; then SH_REASON="it never finished"; return 0; fi
  if [ "$SH_RC" != 0 ]; then SH_REASON="exit ${SH_RC:-?}"; return 0; fi
  if [ "$SH_OWED" -gt 0 ] && [ $(( SH_EL * 1000 )) -ge $(( SH_TMO - 1000 )) ]; then
    SH_REASON="ended at its $(( SH_TMO / 1000 )) s timeout with output owed"
  fi
}

# sh_scan <dir> [<fallback transcript path>] → cancels TSV on stdout; rc 3 = no transcript yet.
# Reads from session.start's offset. In the start epoch the read stops at the first user record and
# at SH_CAP_BYTES; after a resume (session.start older than the newest .start) the rest of the file
# is read, since a resume's records sit mid-file (gap-G3 F1). rg/jq only on the hits.
sh_scan() {
  local d="$1" tp="" size=0 k v newest=0 sm=0 m f fsz floor
  if [ -f "$d/session.start" ]; then
    while IFS='=' read -r k v; do
      case "$k" in transcript_path) tp="$v" ;; size) size="$v" ;; esac
    done < "$d/session.start"
    sm="$(stat -f %m "$d/session.start" 2>/dev/null || echo 0)"
  fi
  [ -n "$tp" ] || tp="${2:-}"
  [ -n "$tp" ] && [ -f "$tp" ] || return 3
  case "$size" in ''|*[!0-9]*) size=0 ;; esac
  for f in "$d"/*.start; do
    [ -e "$f" ] || continue
    case "$f" in */session.start) continue ;; esac
    m="$(stat -f %m "$f" 2>/dev/null || echo 0)"
    [ "$m" -gt "$newest" ] && newest="$m"
  done
  [ "$newest" -gt 0 ] || newest="$sm"
  floor=$(( newest - SH_FLOOR_S ))
  fsz="$(stat -f %z "$tp" 2>/dev/null || echo 0)"
  [ "$fsz" -lt "$size" ] && size=0          # rewritten or truncated since the start: read it all
  {
    if [ "$sm" -ge "$floor" ]; then
      tail -c +"$(( size + 1 ))" "$tp" 2>/dev/null | head -c "$SH_CAP_BYTES" | sed '/"type":"user"/q'
    else
      tail -c +"$(( size + 1 ))" "$tp" 2>/dev/null
    fi
  } | LC_ALL=C grep -F '"hook_cancelled"' | LC_ALL=C grep -F 'SessionStart' \
    | jq -R -r --argjson f "$floor" '
        def cell(ph): (if . == null then "" else . end) | tostring
                      | gsub("[\\t\\r\\n]"; " ") | if . == "" then ph else . end;
        fromjson? | select(type == "object")
        | select((.attachment.type? // "") == "hook_cancelled" and (.attachment.hookEvent? // "") == "SessionStart")
        | select(((.timestamp // "") | tostring | sub("\\.[0-9]+Z$"; "Z") | (try fromdateiso8601 catch 0)) >= $f)
        | [(.attachment.command | cell("?")), (.attachment.hookName | cell("?")),
           (.attachment.durationMs | cell("0")), (.attachment.timeoutMs | cell("0"))]
        | map(gsub("[[:cntrl:]]"; " ")) | join("\t")' 2>/dev/null
  return 0
}

sh_own_of() { # <command> → SH_OWNER: the own hook stem the command runs, or empty. Builtins only.
  local s
  SH_OWNER=""
  for s in $SH_OWN; do
    case "$1" in *"/$s.sh"|*"/$s.sh "*) SH_OWNER="$s"; return 0 ;; esac
  done
}

# sh_judge <dir> <cancels-file> → "name<TAB>verdict" lines (own hooks, then foreign-<n>).
# THE TRANSCRIPT IS THE AUTHORITY: a record confirms, its absence clears, whatever .done says.
sh_judge() {
  local d="$1" c="$2" f h cmd n=0 seen=" "
  for f in "$d"/*.start; do
    [ -e "$f" ] || continue
    h="${f##*/}"; h="${h%.start}"
    [ "$h" = session ] && continue
    seen="$seen$h "
    if LC_ALL=C grep -qF "/$h.sh" "$c" 2>/dev/null; then
      sh_read_done "$d" "$h"
      if [ "$SH_DONE" = 1 ] && [ "$SH_OWED" = 0 ]; then printf '%s\tnothing-owed\n' "$h"
      else printf '%s\tconfirmed\n' "$h"; fi
    else
      printf '%s\tcleared\n' "$h"
    fi
  done
  while IFS=$'\t' read -r cmd _ _ _; do
    n=$(( n + 1 ))
    sh_own_of "$cmd"
    if [ -n "$SH_OWNER" ]; then
      # An own hook cancelled before its sentinel opened (or not yet wired): still own, never "foreign".
      case "$seen" in *" $SH_OWNER "*) ;; *) seen="$seen$SH_OWNER "; printf '%s\tconfirmed\n' "$SH_OWNER" ;; esac
    else
      printf 'foreign-%s\tconfirmed %s\n' "$n" "$cmd"
    fi
  done < "$c"
}

# sh_current <dir> → 0 when cancels.tsv exists and no hook .start is newer (this epoch is scanned).
sh_current() {
  local f
  [ -f "$1/cancels.tsv" ] || return 1
  for f in "$1"/*.start; do
    [ -e "$f" ] || continue
    [ "$f" -nt "$1/cancels.tsv" ] && return 1
  done
  return 0
}

# sh_write <dir> [<fallback tp>] → scan + judge + write, under a per-session single-flight lock.
# rc 0 written · 3 no transcript · 4 another scan holds the lock · 5 write failed.
sh_write() {
  local d="$1" tmp name v rc=0
  mkdir "$d/scan.lock" 2>/dev/null || {
    # A SIGKILLed scan leaves its lock; its pid file says whether anyone still holds it.
    local p=""; read -r p < "$d/scan.lock/pid" 2>/dev/null
    if [ -n "$p" ] && kill -0 "$p" 2>/dev/null; then return 4; fi
    rm -f "$d/scan.lock/pid"; rmdir "$d/scan.lock" 2>/dev/null; mkdir "$d/scan.lock" 2>/dev/null || return 4
  }
  printf '%s\n' "$$" > "$d/scan.lock/pid" 2>/dev/null
  tmp="$d/.cancels.$$"
  sh_scan "$d" "${2:-}" > "$tmp" || rc=$?
  if [ "$rc" = 0 ]; then
    rm -f "$d"/foreign-*.verdict
    while IFS=$'\t' read -r name v; do
      [ -n "$name" ] || continue
      printf '%s\n' "$v" > "$d/.$name.verdict.$$" && mv -f "$d/.$name.verdict.$$" "$d/$name.verdict" || rc=5
    done < <(sh_judge "$d" "$tmp")
    [ "$rc" = 0 ] && { mv -f "$tmp" "$d/cancels.tsv" || rc=5; }
    rm -f "$d/pending"
  fi
  rm -f "$tmp" "$d/scan.lock/pid"; rmdir "$d/scan.lock" 2>/dev/null
  return "$rc"
}

# sh_worker <sid> [<transcript path from the prompt payload>] — session-beat's detached prompt worker.
# No-op (builtins) unless this start epoch is unscanned. Claude Code creates the transcript lazily,
# after the first prompt (42 of 42 cancel sessions had none at prompt 1, gap-G3 F2), so it polls for
# it for at most CC_STARTUP_HEALTH_POLL_S (60) — inside the existing worker, never a new process.
sh_worker() {
  local tp="${2:-}" k v i=0 cap="${CC_STARTUP_HEALTH_POLL_S:-60}"
  [ "${CC_STARTUP_HEALTH:-1}" = 0 ] && return 0
  sh_dir "${1:-}" || return 0
  [ -d "$SH_D" ] || return 0
  [ -e "$SH_D/resolved" ] && sh_current "$SH_D" && return 0
  sh_current "$SH_D" && return 0
  if [ -f "$SH_D/session.start" ]; then
    while IFS='=' read -r k v; do [ "$k" = transcript_path ] && [ -n "$v" ] && tp="$v"; done < "$SH_D/session.start"
  fi
  [ -n "$tp" ] || return 0
  case "$cap" in ''|*[!0-9]*) cap=60 ;; esac
  while [ ! -f "$tp" ]; do
    [ "$i" -ge "$cap" ] && return 0
    sleep 1; i=$(( i + 1 ))
  done
  sh_write "$SH_D" "$tp"
}

# ── prompt front (README §5 unit 3.2) — runs on EVERY prompt, so builtins only until there is news ──

# The recovery is TEXT for the operator to read, so the tilde is printed, never expanded.
# shellcheck disable=SC2088
sh_lost_of() { # <hook> <sid> → SH_LOST SH_RECOV (contract w3-format.md, fixed text)
  case "$1" in
    dod-persist) SH_LOST="the frozen DoD contract"; SH_RECOV="~/.claude/hooks/dod-persist.sh get" ;;
    mailbox-drain) SH_LOST="peer mail (deferred, not lost)"; SH_RECOV="mail re-delivers at the next boundary (cc-mail to read now)" ;;
    session-start-dispatch) SH_LOST="the startup board and notices"; SH_RECOV="claude-accounts (board) / cc-startup-health $2" ;;
    desk-brief-inject) SH_LOST="the desk brief"; SH_RECOV="none needed" ;;
    *) SH_LOST="its output"; SH_RECOV="cc-startup-health $2" ;;
  esac
}

sh_secs() { # <ms> → SH_T, one decimal, builtins
  case "${1:-}" in ''|*[!0-9]*) SH_T="?"; return 0 ;; esac
  SH_T="$(( $1 / 1000 )).$(( $1 % 1000 / 100 ))"
}

sh_row_of() { # <dir> <n> | own <hook> → SH_CMD SH_DUR from cancels.tsv (builtin read loop)
  local d="$1" want="$2" cmd dur n=0
  SH_CMD=""; SH_DUR=""
  while IFS=$'\t' read -r cmd _ dur _; do
    n=$(( n + 1 ))
    if [ "$want" = own ]; then
      case "$cmd" in *"/$3.sh"|*"/$3.sh "*) SH_CMD="$cmd"; SH_DUR="$dur"; return 0 ;; esac
    elif [ "$n" = "$want" ]; then SH_CMD="$cmd"; SH_DUR="$dur"; return 0; fi
  done < "$d/cancels.tsv"
}

sh_add() { # <line> → appended to SH_SYS
  if [ -n "$SH_SYS" ]; then SH_SYS="$SH_SYS"$'\n'"$1"; else SH_SYS="$1"; fi
}

sh_idl() { # <disposition> <reason> — one IDL row per reported drop (only ever on a report path)
  [ -n "${_SH_IDL_READY:-}" ] || {
    # shellcheck source=idl-log.sh disable=SC1091
    . "${_SH_LIBDIR}/idl-log.sh" 2>/dev/null || return 0
    # shellcheck disable=SC2034  # read by indirection in idl-log.sh (idl_init's sid-var slot)
    SH_IDL_SID="$_SH_SID"
    idl_init "${CC_IDL:-$HOME/.claude/autonomy/idl.jsonl}" "startup-health" SH_IDL_SID
    _SH_IDL_READY=1
  }
  log_idl_fixed "$1" "$2"
}

SH_DOD_PTR="Startup hook dod-persist may not have delivered this session's frozen DoD contract (the completeness baseline). If no Durable frozen DoD block is above, read it now: ~/.claude/hooks/dod-persist.sh get"

# sh_front <sid> → SH_SYS (operator lines, newline-joined) and SH_CTX (model pointer), both empty on a
# healthy prompt. Fast exit: "$R/<sid>/resolved" newer than every .start (a resume re-opens it).
sh_front() {
  SH_SYS=""; SH_CTX=""
  [ "${CC_STARTUP_HEALTH:-1}" = 0 ] && return 0
  sh_dir "${1:-}" || return 0
  local d="$SH_D" f h v rest tries cur=0 open=0 possible_any=0
  _SH_SID="$1"
  [ -d "$d" ] || return 0
  if [ -e "$d/resolved" ]; then
    open=0
    for f in "$d"/*.start; do [ "$f" -nt "$d/resolved" ] && { open=1; break; }; done
    [ "$open" = 0 ] && return 0
  fi
  sh_current "$d" && cur=1
  open=0
  # 1. Own hooks with a sentinel and no verdict for this epoch yet: the possible-loss line, once.
  for f in "$d"/*.start; do
    [ -e "$f" ] || continue
    h="${f##*/}"; h="${h%.start}"
    [ "$h" = session ] && continue
    [ "$cur" = 1 ] && [ -e "$d/$h.verdict" ] && continue
    tries=0
    if [ -e "$d/$h.tries" ] && ! [ "$f" -nt "$d/$h.tries" ]; then read -r tries < "$d/$h.tries"; fi
    case "$tries" in ''|*[!0-9]*) tries=0 ;; esac
    [ "$tries" -ge 3 ] && continue                       # gave up: cc-startup-health shows it unconfirmed
    sh_possible "$d" "$h"
    if [ -n "$SH_REASON" ]; then
      possible_any=1
      if [ "$tries" = 0 ]; then
        sh_add "⚠ startup: $h may not have delivered ($SH_REASON) — confirming"
        [ "$h" = dod-persist ] && SH_CTX="$SH_DOD_PTR"
      fi
    fi
    tries=$(( tries + 1 ))
    printf '%s\n' "$tries" > "$d/$h.tries" 2>/dev/null
    [ "$tries" -lt 3 ] && open=1
  done
  [ "$possible_any" = 1 ] && : > "$d/pending" 2>/dev/null
  # 2. This epoch is scanned: report every verdict not yet reported (own and foreign), once each.
  if [ "$cur" = 1 ]; then
    for f in "$d"/*.verdict; do
      [ -e "$f" ] || continue
      h="${f##*/}"; h="${h%.verdict}"
      [ -e "$d/$h.reported" ] && ! [ "$f" -nt "$d/$h.reported" ] && continue
      v=""; rest=""
      read -r v rest < "$f"
      case "$h" in
        foreign-*)
          if [ "$v" = confirmed ]; then
            sh_row_of "$d" "${h#foreign-}"; sh_secs "$SH_DUR"
            sh_add "⚠ startup: project hook ${rest:-$SH_CMD} was cancelled after $SH_T s — not re-run · re-run it by hand"
            sh_idl fired "startup-drop:confirmed:foreign"
          fi ;;
        *)
          sh_possible "$d" "$h"
          case "$v" in
            confirmed)
              sh_row_of "$d" own "$h"; sh_secs "$SH_DUR"; sh_lost_of "$h" "$1"
              sh_add "⚠ startup: $h did not finish (cancelled after $SH_T s) — $SH_LOST · $SH_RECOV"
              # The pointer once: with the possible line, or here if this loss was never flagged.
              if [ "$h" = dod-persist ]; then
                tries=0; [ -e "$d/$h.tries" ] && read -r tries < "$d/$h.tries"
                { [ -z "$SH_REASON" ] || [ "${tries:-0}" = 0 ]; } && SH_CTX="$SH_DOD_PTR"
              fi
              sh_idl fired "startup-drop:confirmed:$h" ;;
            nothing-owed) sh_idl cleared "startup-drop:nothing-owed:$h" ;;
            cleared) [ -n "$SH_REASON" ] && sh_idl cleared "startup-drop:cleared:$h" ;;
          esac ;;
      esac
      : > "$d/$h.reported" 2>/dev/null
    done
  fi
  # Resolved: this epoch is scanned and every verdict above is reported, or no transcript ever
  # came and every hook has had its 3 tries. Either way nothing is left to say until a new .start.
  if [ "$cur" = 1 ] || [ "$open" = 0 ]; then
    : > "$d/resolved" 2>/dev/null
    # Nothing is pending any more, so the idle-pane alert file (startup-alert.sh) is emptied too.
    [ -s "${d%/*}/alerts/$1" ] && : > "${d%/*}/alerts/$1" 2>/dev/null
  fi
  return 0
}

sh_json_esc() { # <string> → SH_J, JSON-string-safe (the worker already blanked control bytes)
  local s="$1"
  s="${s//\\/\\\\}"; s="${s//\"/\\\"}"; s="${s//$'\n'/\\n}"; s="${s//$'\t'/\\t}"; s="${s//$'\r'/\\r}"; s="${s//$'\033'/\\u001b}"
  SH_J="$s"
}

# sh_front_emit <sid> <hookEventName> → prints the hook JSON, or nothing on a healthy prompt.
sh_front_emit() {
  local m
  sh_front "$1"
  # SH_SYS_EXTRA: an operator line the caller needs printed in the SAME object (session-beat's late
  # renders, hooks/lib/hook-deadline.sh) — one hook, one JSON document.
  [ -n "${SH_SYS_EXTRA:-}" ] && SH_SYS="${SH_SYS:+$SH_SYS$'\n'}$SH_SYS_EXTRA"
  [ -n "$SH_SYS" ] || [ -n "$SH_CTX" ] || return 0
  sh_json_esc "$SH_SYS"; m="$SH_J"
  if [ -n "$SH_CTX" ]; then
    sh_json_esc "$SH_CTX"
    printf '{"systemMessage":"%s","hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' \
      "$m" "${2:-UserPromptSubmit}" "$SH_J"
  else
    printf '{"systemMessage":"%s"}\n' "$m"
  fi
}
