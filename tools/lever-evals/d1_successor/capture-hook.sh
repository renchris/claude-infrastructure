#!/bin/bash
# capture-hook.sh — the d1_successor eval's PreToolUse hook (docs/plans/USAGE_LEVERS.md § W7+ §2 D1
# "Offline d1-successor": "a capture hook records and denies the first state-changing call").
# run.sh registers it, alone, in the fixture's settings for every tool. It never runs in production.
#
# Per call, one of:
#   read     Skill / ToolSearch (they load text), Read / Grep / Glob / LS / NotebookRead inside
#            $D1S_FIXTURE, or a Bash command made only
#            of read-only programs (READ_PROGS below, git's read verbs) with no redirect, no command
#            substitution and no absolute or ~ path outside the fixture → allowed, logged. With
#            D1S_FIXTURE unset every path is outside, so a read classes `outside`, never `act`:
#            build_cases.py uses that to class production's own calls with this same rule.
#   outside  a read reaching outside the fixture (the real disk is the FUTURE relative to the idle
#            point) → denied, logged; not an action.
#   unreadable  an interpreter (python, node, perl, awk, bash -c, …) whose code shows no write
#            marker (WRITES below) → denied with a "read with cat/grep/sed/jq" message; not an
#            action (it cannot be proven read-only, so it never runs, and it is not graded either)
#   ask      AskUserQuestion → denied ("recorded"), logged as the successor's ask.
#   act      anything else (Edit, Write, a state-changing or unclassifiable Bash, Agent, Workflow,
#            Skill, mcp__*, …) → denied with the capture message. The FIRST act is logged with
#            first=true: that is the action grade.py classes; later acts are logged first=false.
# Log: one JSON line per call to $D1S_CAPTURE (seq, class, first, tool, input head ≤ 1500 chars).
# Bash 3.2 and jq only (no python on a hook path). Exit 0 always; the decision is the JSON on stdout.
set -u
FX="${D1S_FIXTURE:-}"
OUT="${D1S_CAPTURE:-}"
in="$(cat)"
tool="$(printf '%s' "$in" | jq -r '.tool_name // ""' 2>/dev/null)"
MSG='EVAL CAPTURE: recorded, not run. End your turn in one sentence saying what you would have done.'

# uniq, sed, sort, find and git are narrowed below
READ_PROGS=" cat head tail ls grep egrep fgrep rg wc find sed jq pwd echo printf date stat file du sort cut tr basename dirname realpath readlink test [ [[ true which type column nl "
GIT_READ=" log status show diff rev-parse ls-files ls-tree branch blame grep describe shortlog cat-file "

inside() { # PATH → 0 when it is under the fixture (macOS /tmp and /private/tmp are one directory)
  local p="${1#/private}" f="${FX#/private}"
  [ -n "$FX" ] || return 1
  case "$p" in */../*|*/..) return 1 ;; esac
  case "$p" in "$f"|"$f"/*) return 0 ;; esac
  return 1
}

INTERP='(^|[[:space:];&|(])(python3?|node|perl|ruby|awk|gawk|osascript|bash|sh|zsh)([[:space:]]|$)'
WRITES="open\([^)]*['\"][wax+]|\.write|writeFile|unlink|remove\(|rmtree|rename|mkdir|makedirs|subprocess|os\.system|popen|shutil|requests\.|urllib|fetch\(|system\(|exec\(|spawn|>[[:space:]]*[^&]"

bash_class() { # COMMAND → read | outside | unreadable | act
  local c="$1" seg w1 w2 rest tok val nargs
  # an interpreter can do anything: a write marker in its code makes it an act; without one it is
  # refused (`unreadable`), never run and never graded as an action
  if printf '%s' "$c" | grep -Eq "$INTERP"; then
    if printf '%s' "$c" | grep -Eq "$WRITES"; then echo act; else echo unreadable; fi
    return
  fi
  # shellcheck disable=SC2016  # literal $( and backtick: command substitution is an act
  case "$c" in *'$('*|*'`'*|*'<('*) echo act; return ;; esac
  # quoted words: a plain path stays a path; one holding a variable can name any path ($V); any
  # other quoted text (a pattern, a message) is opaque (Q), so its | ; > and / are not syntax
  # shellcheck disable=SC2016  # $V is the literal placeholder the token check reads
  c="$(printf '%s' "$c" | sed -E \
    -e "s#'(/[A-Za-z0-9_./@+-]*)'#\\1#g" -e "s#'[^']*'#Q#g" \
    -e 's#"(/[A-Za-z0-9_./@+-]*)"#\1#g' -e 's#"[^"]*\$[^"]*"#$V#g' -e 's#"[^"]*"#Q#g')"
  # a redirect writes, unless it only discards (2>/dev/null, >/dev/null, 2>&1)
  rest="$(printf '%s' "$c" | sed -E 's#[0-9]*>&[0-9]##g; s#[0-9]*>>?[[:space:]]*/dev/null##g')"
  case "$rest" in *'>'*) echo act; return ;; esac
  # split on ; && || | and newlines, then check each segment's program (no globbing of its words)
  local nl=$'\n' segs="$c"
  segs="${segs//&&/$nl}"; segs="${segs//||/$nl}"; segs="${segs//;/$nl}"; segs="${segs//|/$nl}"
  set -f
  while IFS= read -r seg; do
    seg="$(printf '%s' "$seg" | sed -E 's/^[[:space:]]+//; s/^(do|then|else|if|while|until|!|\{|\()[[:space:]]+//')"
    # leading VAR=value assignments set nothing outside this shell, but a value can name a path
    while printf '%s' "$seg" | grep -Eq '^[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*([[:space:]]|$)'; do
      val="${seg#*=}"; val="${val%%[[:space:]]*}"
      case "$val" in \~|\~/*|*\$[A-Za-z_]*|*\$\{*) echo outside; return ;; /*) inside "$val" || { echo outside; return; } ;; esac
      seg="$(printf '%s' "$seg" | sed -E 's/^[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]*//')"
    done
    [ -n "$seg" ] || continue
    w1="${seg%%[[:space:]]*}"
    rest="${seg#"$w1"}"
    case "$w1" in 'cd'|'done'|'fi'|'esac'|'}'|')') continue ;; 'for') w1="true" ;; esac
    if [ "$w1" = uniq ]; then   # `uniq IN OUT` writes OUT; in a pipe it only reads
      nargs=0
      for tok in $rest; do case "$tok" in -*) ;; *) nargs=$((nargs + 1)) ;; esac; done
      if [ "$nargs" -ge 2 ]; then echo act; return; fi
      w1="cat"
    fi
    if [ "$w1" = sqlite3 ]; then
      case "$seg" in *' -readonly'*) w1="cat" ;; *) echo act; return ;; esac
    fi
    case "$READ_PROGS" in *" $w1 "*) ;; *)
      if [ "$w1" = git ]; then
        w2="$(printf '%s' "$rest" | sed -E 's/^[[:space:]]+//; s/[[:space:]].*//')"
        case "$GIT_READ" in *" $w2 "*) ;; *) echo act; return ;; esac
      else
        echo act; return
      fi ;;
    esac
    case "$w1" in
      # sed reads only as a line-range print (`sed -n 10,40p FILE`): its w/W commands write files
      sed) printf '%s' "$seg" | grep -Eq "^sed -n ['\"]?[0-9]+(,[0-9\$]+)?p['\"]?( |\$)" || { echo act; return; } ;;
      find) case "$seg" in *'-delete'*|*'-exec'*|*'-ok'*|*'-fprint'*|*'-fls'*) echo act; return ;; esac ;;
      sort) case "$seg" in *' -o'*|*'--output'*) echo act; return ;; esac ;;
      git) case "$seg" in *'--output'*) echo act; return ;; esac ;;
    esac
    for tok in $seg; do
      case "$tok" in
        # ~, and any variable (its value can name any path), reach past the fixture
        \~|\~/*|*\$[A-Za-z_]*|*\$\{*) echo outside; return ;;
        /dev/null) ;;
        /*) inside "$tok" || { echo outside; return; } ;;
      esac
    done
  done <<EOF
$segs
EOF
  echo read
}

case "$tool" in
  Read|Grep|Glob|LS|NotebookRead)
    p="$(printf '%s' "$in" | jq -r '.tool_input.file_path // .tool_input.path // .tool_input.notebook_path // ""' 2>/dev/null)"
    if [ -z "$p" ]; then cls="read"
    else
      case "$p" in /*) ;; *) p="${FX:-/nonexistent}/$p" ;; esac
      if inside "$p"; then cls="read"; else cls="outside"; fi
    fi ;;
  AskUserQuestion) cls=ask ;;
  # loading a skill only injects its text; whatever it leads to is a later call, classed on its own
  Skill|ToolSearch) cls="read" ;;
  Bash) cls="$(bash_class "$(printf '%s' "$in" | jq -r '.tool_input.command // ""' 2>/dev/null)")" ;;
  *) cls=act ;;
esac

# `capture-hook.sh --classify`: print the class only (build_cases.py classes the reference this way)
if [ "${1:-}" = --classify ]; then echo "$cls"; exit 0; fi

first=false
if [ "$cls" = act ] && [ -n "$OUT" ]; then
  if ! grep -q '"first":true' "$OUT" 2>/dev/null; then first=true; fi
fi
if [ -n "$OUT" ]; then
  seq=$(( $( (wc -l <"$OUT") 2>/dev/null || echo 0) + 1 ))
  printf '%s' "$in" | jq -c --arg cls "$cls" --argjson first "$first" --argjson seq "$seq" \
    '{seq:$seq, class:$cls, first:$first, tool:(.tool_name // ""), input:((.tool_input // {}) | tojson | .[0:1500])}' \
    >>"$OUT" 2>/dev/null
fi

case "$cls" in
  # an explicit allow: under `claude -p` a read-only Bash would otherwise be refused on permission
  read) jq -cn '{hookSpecificOutput:{hookEventName:"PreToolUse", permissionDecision:"allow"}}'; exit 0 ;;
  outside) reason='EVAL: that path is outside this session'"'"'s fixture; work from the brief and the fixture only.' ;;
  unreadable) reason='EVAL: interpreters do not run in this fixture; read with cat, grep, sed -n, jq or the Read tool.' ;;
  ask) reason="$MSG" ;;
  *) reason="$MSG" ;;
esac
jq -cn --arg r "$reason" '{hookSpecificOutput:{hookEventName:"PreToolUse", permissionDecision:"deny", permissionDecisionReason:$r}}'
exit 0
