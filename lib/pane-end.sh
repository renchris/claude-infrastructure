# shellcheck shell=bash
# pane-end.sh — is this session finished? The ONE decision function. Sourced; bash 3.2, set -u clean.
#
# WHY THIS EXISTS (docs/research/husk-history-2026-10-24/FIX-DESIGN.md §2, D8). The closer
# (bin/cc-pane-close), the sweep (bin/cc-husk-sweep) and the watchdog (hooks/lead-crash-watchdog.sh)
# each carried their own transcript reader, their own dirt subject and their own verdict, and they
# disagreed: pane 304 (2026-10-25) was refused 33 times by the closer, painted CANTTELL, and called
# COLLECTED by the sweep, all at once. Here the question is asked once and every caller prints the
# answer. Custody comes from lib/pane-custody.sh (the ONE custody reader); which files a session
# wrote comes from hooks/lib/session-writes.sh. Nothing here writes a store or touches a pane.
#
# FIELDS ARE SEPARATED BY \037 (ASCII unit separator), never a tab: tab is IFS whitespace, so an
# empty cell would shift the next column left on a `read` (scripts/tsv-pad-lint.sh).
#
#   pe_facts   <tp>                              → team␟close␟cwd␟records
#   pe_end     <sid> <pane> <since> [class]      → crash | clean | unknown
#   pe_work    <tp> <dir> <own|strict|team>      → - | clean | dirty:N | unlanded:N | unknown
#   pe_verdict <sid> <tp> <pane> [since] [class] [cwd] → STATE␟why␟work␟close␟end␟owner␟cwd
#     (cwd is a FALLBACK, used only when the transcript records none — a caller's registry or shell
#     cwd; without it such a session's work read "-", and a crash over its own dirt read DONE)
#
# Seams: CC_PANE_EXIT_DIR (runner exit records <pane>.json {rc, ts, …}), CC_CRASH_LOG (jsonl rows
# {sid, class, cause, …}), CC_FIRED_DIR (fired records <pane>.json {closedAt, transcript, …}),
# CC_PE_READ_TIMEOUT_S (transcript read bound, default 30), and pane-custody's CC_CUSTODY_DIR.

_pe_here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
if [ -n "$_pe_here" ] && [ -r "$_pe_here/pane-custody.sh" ]; then
  # shellcheck source=/dev/null
  . "$_pe_here/pane-custody.sh"
else
  # shellcheck source=/dev/null
  . "${HOME:-}/.claude/lib/pane-custody.sh"
fi
if [ -n "$_pe_here" ] && [ -r "$_pe_here/../hooks/lib/session-writes.sh" ]; then
  # shellcheck source=/dev/null
  . "$_pe_here/../hooks/lib/session-writes.sh"
else
  # shellcheck source=/dev/null
  . "${HOME:-}/.claude/hooks/lib/session-writes.sh"
fi
unset _pe_here

_PE_US=$'\037'

# The transcript in ONE bounded streaming pass. close is read from assistant TEXT blocks only — a
# thinking block is not something the session said, and the whole-JSONL grep this replaces matched
# the CLAUDE.md attachment's own example close (husk-panes root cause 7). A cut read cannot vouch for
# the LAST close, so it reports "-" rather than an earlier one. records counts JSON-object lines: a
# file the session never wrote a record into is pane 304's shape (§2 row 1b).
pe_facts() { # $1=transcript → team␟close␟cwd␟records
  local tp="${1:-}" out
  if [ -z "$tp" ] || [ ! -f "$tp" ]; then
    printf '0%s-%s-%s0\n' "$_PE_US" "$_PE_US" "$_PE_US"; return 0
  fi
  out="$(CC_PE_READ_TIMEOUT_S="${CC_PE_READ_TIMEOUT_S:-30}" python3 - "$tp" <<'PY' 2>/dev/null
import json, os, re, signal, sys
TEAM = re.compile(r'"teamName":\s*"[^"]')
CWD = re.compile(r'"cwd":\s*"((?:[^"\\]|\\.)*)"')
CLOSE = re.compile(r"Good to close:[ \t]*([A-Za-z]*)")
class Cut(Exception):
    pass
def on_alarm(*_):
    raise Cut()
team, close, cwd, records = 0, "-", "", 0
signal.signal(signal.SIGALRM, on_alarm)
try:
    bound = int(os.environ.get("CC_PE_READ_TIMEOUT_S") or 30)
except ValueError:
    bound = 30
signal.alarm(max(bound, 1))
try:
    with open(sys.argv[1], "r", errors="replace") as fh:
        for line in fh:
            if not line.lstrip().startswith("{"):
                continue
            records += 1
            # A bare-key match is unforgeable by content: a "teamName" quoted inside a message string
            # is JSON-escaped (\"teamName\"), so only a real record key matches.
            if not team and TEAM.search(line):
                team = 1
            m = CWD.search(line)
            if m:
                try:
                    cwd = json.loads('"' + m.group(1) + '"')
                except Exception:
                    pass
            if '"assistant"' not in line or "Good to close:" not in line:
                continue
            try:
                rec = json.loads(line)
            except Exception:
                continue
            if not isinstance(rec, dict):
                continue
            msg = rec.get("message") or {}
            if not isinstance(msg, dict):
                continue
            if msg.get("role") != "assistant" and rec.get("type") != "assistant":
                continue
            content = msg.get("content")
            if isinstance(content, str):
                texts = [content]
            elif isinstance(content, list):
                texts = [b.get("text") or "" for b in content if isinstance(b, dict) and b.get("type") == "text"]
            else:
                continue
            for t in texts:
                for v in CLOSE.findall(t):
                    v = v.lower()
                    close = v if v in ("yes", "no") else "-"
except Cut:
    close = "-"
    if records == 0:
        sys.exit(3)
except Exception:
    sys.exit(3)
signal.alarm(0)
cwd = cwd.replace("\x1f", " ").replace("\n", " ") or "-"
if records == 0:
    team, close, cwd = 0, "-", "-"
sys.stdout.write("%d\x1f%s\x1f%s\x1f%d\n" % (team, close, cwd, records))
PY
)"
  case "$out" in
    *"$_PE_US"*"$_PE_US"*"$_PE_US"*) printf '%s\n' "$out" ;;
    # The read itself failed (python missing, killed, file unreadable). records is "-", NOT 0: a zero
    # would read as "never received a turn" (§2 row 1b) and close a pane on an unread transcript.
    *) printf '0%s-%s-%s-\n' "$_PE_US" "$_PE_US" "$_PE_US" ;;
  esac
}

_pe_iso_epoch() { # $1=ISO-8601 Z → whole-second epoch, or 0
  local t="${1%%.*}"
  t="${t%Z}Z"
  TZ=UTC date -j -f '%Y-%m-%dT%H:%M:%SZ' "$t" +%s 2>/dev/null \
    || date -u -d "${1:-}" +%s 2>/dev/null || printf '0\n'
}

# How the session ENDED, never what it said. A RECYCLE cause is a clean exit, not a crash: 1659 of
# 2075 crash-log rows since 2026-10-01 are RECYCLE (FIX-DESIGN D9), and reading them as crashes is
# what B8 pins. Without a crash-log row the runner's exit record decides, if it is from this tenant.
pe_end() { # $1=sid $2=pane $3=since-epoch [$4=class] → crash | clean | unknown
  local sid="${1:-}" pane="${2:-}" since="${3:-0}" class="${4:-}" log f row rc ts
  case "$since" in ''|*[!0-9]*) since=0 ;; esac
  if [ -z "$class" ] && [ -n "$sid" ]; then
    log="${CC_CRASH_LOG:-${HOME:-}/.claude/logs/claude-crashes.jsonl}"
    if [ -f "$log" ] && command -v jq >/dev/null 2>&1; then
      class="$(LC_ALL=C grep -F -- "$sid" "$log" 2>/dev/null \
        | jq -R -r --arg s "$sid" 'fromjson? | objects | select(.sid == $s) | .class // empty' 2>/dev/null \
        | tail -n 1)"
    fi
  fi
  case "$class" in
    CRASH)   printf 'crash\n'; return 0 ;;
    RECYCLE) printf 'clean\n'; return 0 ;;
  esac
  f="${CC_PANE_EXIT_DIR:-${HOME:-}/.claude/run/pane-exit}/$pane.json"
  if [ -n "$pane" ] && [ -s "$f" ] && command -v jq >/dev/null 2>&1; then
    row="$(jq -r '[(.rc // "" | tostring), (.ts // "" | tostring)] | join(" ")' "$f" 2>/dev/null)"
    rc="${row%% *}"; ts="${row#* }"
    case "$rc" in ''|*[!0-9]*) rc="" ;; esac
    case "$ts" in ''|*[!0-9]*) ts="" ;; esac
    if [ -n "$rc" ] && [ -n "$ts" ] && [ "$ts" -ge "$since" ]; then
      case "$rc" in 0|75) printf 'clean\n' ;; *) printf 'crash\n' ;; esac
      return 0
    fi
  fi
  printf 'unknown\n'
}

# Trunk ladder, copied from scripts/bats-shellcheck-lint.sh:565-569 (the `-q` probe form, never the
# naive one): origin/HEAD, then origin/main, then origin/master. 32 of 201 repos lack origin/HEAD
# (FIX-DESIGN D10). None resolves ⇒ empty, and the unlanded step is skipped.
_pe_trunk() { # $1=dir → trunk ref, or empty
  local d="${1:-}" t=""
  if git -C "$d" rev-parse --verify -q origin/HEAD >/dev/null 2>&1; then
    t="$(git -C "$d" rev-parse --abbrev-ref origin/HEAD 2>/dev/null || true)"
  fi
  [ -n "$t" ] || { git -C "$d" rev-parse --verify -q origin/main   >/dev/null 2>&1 && t="origin/main"; }
  [ -n "$t" ] || { git -C "$d" rev-parse --verify -q origin/master >/dev/null 2>&1 && t="origin/master"; }
  if [ -n "$t" ] && ! git -C "$d" rev-parse --verify -q "$t" >/dev/null 2>&1; then t=""; fi
  printf '%s' "$t"
}

# Sets _PE_WORK (the pe_work answer) and _PE_TRUNK (the trunk it compared against) in THIS shell, so
# pe_verdict can name the trunk in its reason without a second ladder.
_pe_work() { # $1=tp $2=dir $3=own|strict|team
  local tp="${1:-}" dir="${2:-}" mode="${3:-strict}" porc n mine rc ahead
  _PE_WORK="unknown"; _PE_TRUNK=""
  if [ -z "$dir" ] || [ "$dir" = "-" ] || [ ! -d "$dir" ] \
     || ! git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then
    _PE_WORK="-"; return 0
  fi
  porc="$(GIT_OPTIONAL_LOCKS=0 git -C "$dir" status --porcelain 2>/dev/null)" || return 0
  n=0
  [ -n "$porc" ] && n="$(printf '%s\n' "$porc" | wc -l | tr -d ' ')"
  case "$mode" in
    team)
      if [ "$n" -eq 0 ]; then _PE_WORK="clean"; else _PE_WORK="dirty:$n"; fi
      return 0 ;;
    strict)
      [ "$n" -eq 0 ] || { _PE_WORK="dirty:$n"; return 0; } ;;
    own)
      if [ "$n" -gt 0 ]; then
        mine="$(session_dirty_mine "$tp" "$dir")"; rc=$?
        case "$rc" in
          0) _PE_WORK="dirty:$(printf '%s\n' "$mine" | grep -c .)"; return 0 ;;
          1) ;;
          *) return 0 ;;
        esac
      fi ;;
    *) return 0 ;;
  esac
  _PE_TRUNK="$(_pe_trunk "$dir")"
  [ -n "$_PE_TRUNK" ] || { _PE_WORK="clean"; return 0; }
  # Commits ahead of the merge base only: a checkout that is merely BEHIND trunk has nothing unlanded.
  ahead="$(git -C "$dir" rev-list --count "$_PE_TRUNK..HEAD" 2>/dev/null)" || return 0
  case "$ahead" in ''|*[!0-9]*) return 0 ;; 0) _PE_WORK="clean"; return 0 ;; esac
  # Only now is the transcript parsed for the commit side: a clean, landed tree never pays for it.
  session_unlanded_mine "$tp" "$dir" "$_PE_TRUNK" >/dev/null 2>&1; rc=$?
  case "$rc" in
    0) _PE_WORK="unlanded:$ahead" ;;
    1) _PE_WORK="clean" ;;
    *) _PE_WORK="unknown" ;;
  esac
}

pe_work() { # $1=tp $2=dir $3=own|strict|team → - | clean | dirty:N | unlanded:N | unknown
  local _PE_WORK _PE_TRUNK
  _pe_work "$@"
  printf '%s\n' "$_PE_WORK"
}

_pe_self_closed() { # $1=pane $2=sid $3=since → 0 iff the pane's fired record says THIS session self-closed since
  local f="${CC_FIRED_DIR:-${HOME:-}/.claude/cc-fired}/${1:-}.json" row at tp
  [ -n "${1:-}" ] && [ -n "${2:-}" ] && [ -s "$f" ] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  row="$(jq -r '[.closedAt // "", .transcript // ""] | join("\u001f")' "$f" 2>/dev/null)" || return 1
  at="${row%%"$_PE_US"*}"; tp="${row#*"$_PE_US"}"
  [ -n "$at" ] && [ "${tp##*/}" = "$2.jsonl" ] || return 1
  [ "$(_pe_iso_epoch "$at")" -ge "${3:-0}" ]
}

_pe_work_why() { # $1=work $2=mode $3=short-sid → the reason a non-clean work answer blocks DONE
  case "$1" in
    dirty:*)
      case "$2" in
        own)  printf '%s uncommitted change(s) in files session %s wrote' "${1#dirty:}" "$3" ;;
        team) printf '%s uncommitted change(s) in team member %s'"'"'s cwd, and a member'"'"'s writes cannot be told apart, so every change counts' "${1#dirty:}" "$3" ;;
        *)    printf '%s uncommitted change(s), and session %s did not end cleanly, so every change counts' "${1#dirty:}" "$3" ;;
      esac ;;
    unlanded:*) printf 'commits touching files session %s wrote are not on %s' "$3" "${_PE_TRUNK:-trunk}" ;;
    *) printf 'session %s'"'"'s own writes cannot be read' "$3" ;;
  esac
}

pe_verdict() { # $1=sid $2=tp $3=pane [$4=since] [$5=class] [$6=fallback cwd] → STATE␟why␟work␟close␟end␟owner␟cwd
  local sid="${1:-}" tp="${2:-}" pane="${3:-}" since="${4:-}" class="${5:-}" fcwd="${6:-}"
  local s8 facts team close cwd records end mode cust="" cstate="" owner="-" state why work="-"
  local _PE_WORK="" _PE_TRUNK=""
  s8="${sid:0:8}"; [ -n "$s8" ] || s8="?"
  [ -n "$since" ] || since="$(cc_transcript_start_epoch "$tp")"
  case "$since" in ''|*[!0-9]*) since=0 ;; esac
  facts="$(pe_facts "$tp")"
  IFS="$_PE_US" read -r team close cwd records <<<"$facts"
  case "$cwd" in ''|-) [ -z "$fcwd" ] || cwd="$fcwd" ;; esac
  end="$(pe_end "$sid" "$pane" "$since" "$class")"
  [ "$end" = clean ] && mode=own || mode=strict
  if cust="$(cc_pane_custody "$pane" "$since")"; then
    cstate="${cust%%$'\t'*}"
    owner="${cust##*$'\t'}"; [ -n "$owner" ] || owner="-"
  fi
  if [ "$cstate" = collected ]; then                                                    # row 1
    state=COLLECTED; why="custody of session $s8 was discharged by its originator"
  elif [ "${records:--}" = 0 ]; then                                                    # row 1b
    if [ "$end" = clean ]; then state=DONE; why="session $s8 never received a turn"
    else state=CANTTELL; why="session $s8 never received a turn, but did not end cleanly ($end)"; fi
  elif [ "$team" = 1 ]; then                                                            # row 2
    _pe_work "$tp" "$cwd" team; work="$_PE_WORK"
    case "$work" in
      clean|-) state=DONE; why="team member $s8 left a clean cwd" ;;
      *) state=CANTTELL; why="$(_pe_work_why "$work" team "$s8")" ;;
    esac
  elif [ "$close" = yes ] || _pe_self_closed "$pane" "$sid" "$since"; then             # row 3
    _pe_work "$tp" "$cwd" "$mode"; work="$_PE_WORK"
    case "$work" in
      clean|-) state=DONE; why="session $s8 closed itself and left nothing of its own open" ;;
      *) why="$(_pe_work_why "$work" "$mode" "$s8")"
         if [ "$end" = crash ]; then
           if [ "$cstate" = open ]; then state=OWNED; why="$why; pane $owner holds its custody"
           else state=RESUME; fi
         else state=CANTTELL; fi ;;
    esac
  elif [ "$end" = crash ]; then                                                         # row 4
    _pe_work "$tp" "$cwd" "$mode"; work="$_PE_WORK"
    if [ "$cstate" = open ]; then state=OWNED; why="session $s8 crashed; pane $owner holds its custody"
    else state=RESUME; why="session $s8 crashed before it said Good to close: yes"; fi
  else                                                                                  # row 5
    _pe_work "$tp" "$cwd" "$mode"; work="$_PE_WORK"
    state=CANTTELL
    case "$close" in
      no) why="session $s8 said Good to close: no and did not crash ($end end)" ;;
      *)  why="session $s8 never said Good to close: yes and did not crash ($end end)" ;;
    esac
  fi
  printf '%s\n' "$state$_PE_US$why$_PE_US$work$_PE_US$close$_PE_US$end$_PE_US$owner$_PE_US$cwd"
}
