#!/bin/bash
# turn-scan.sh — the last N main-chain turns of a transcript, each reduced to three facts:
#   b  the text of the record that OPENED the turn (a human prompt, a task notification, or a
#      "Stop hook feedback:\n<reason>" record written when a Stop hook blocked)
#   g  a /goal evaluation judged the goal UNMET at the Stop that opened this turn (a non-sentinel
#      `goal_status` attachment with met:false, before the turn's first assistant record)
#   w  the turn made at least one tool call that can WRITE something
#
# Readers: hooks/session-continue.sh (skip an identical 🔧 re-block after an idle forced turn,
# token-efficiency rank 17) and hooks/goal-inert-watch.sh (one notice after a streak of empty
# goal-forced turns, rank 13). ONE reader, so the two can never disagree about what "wrote nothing"
# means.
#
# WHAT COUNTS AS WORK — deliberately over-inclusive, because both callers act only on "no work" and
# a false "no work" costs autonomous driving:
#   · any tool other than a read-only set (Read, Grep, Glob, ToolSearch, Task*/List* readers,
#     WebFetch/WebSearch, Monitor): Edit/Write/NotebookEdit, Agent, SendMessage, Workflow, MCP writes…
#   · a Bash command containing an output redirect (other than to /dev/null or an fd dup), `sed -i`,
#     or `find -delete/-exec`, or ANY clause whose verb is outside a read-only list — including every
#     interpreter and script (`bash x.sh`, `python3`, `sh -c`), `tee`, `rm`, `mv`, `touch`, `xargs`,
#     and git verbs other than status/log/diff/show/rev-parse/… .
# A turn boundary is a main-chain `user` record with no tool_result (the definition
# hooks/lib/session-writes.sh uses). Sidechain records are ignored.
#
# Pure function definitions only; safe to source under `set -u`.

# turn_scan <transcript> <n> → JSONL, oldest first, one {"b":…,"g":bool,"w":bool} per turn.
#   rc 0 read cleanly (possibly zero lines: no turn in the window) · rc 2 cannot tell.
#   Reads only the last CC_TURN_SCAN_TAIL_BYTES (default 4 MiB); a window that starts mid-record
#   drops that partial line, so the OLDEST turn in a truncated window may be missing records —
#   callers should ask for one turn more than they need, or treat a short window as cannot-tell.
turn_scan() {
  local tp="${1:-}" n="${2:-1}" lim sz
  command -v jq >/dev/null 2>&1 || return 2
  case "$tp" in "~"*) tp="$HOME${tp#\~}" ;; esac
  [ -n "$tp" ] && [ -f "$tp" ] || return 2
  case "$n" in ''|*[!0-9]*) n=1 ;; esac
  lim="${CC_TURN_SCAN_TAIL_BYTES:-4194304}"; case "$lim" in ''|*[!0-9]*) lim=4194304 ;; esac
  sz="$(wc -c < "$tp" 2>/dev/null | tr -d ' ')"; case "$sz" in ''|*[!0-9]*) return 2 ;; esac
  # shellcheck disable=SC2016  # $r, $c, $w, $a, $s, $n are jq bindings, not shell expansions
  { if [ "$sz" -gt "$lim" ]; then tail -c "$lim" "$tp" | sed 1d; else cat "$tp"; fi; } 2>/dev/null \
  | jq -Rcn --argjson n "$n" '
      def ro_tool: test("^(Read|Grep|Glob|LS|ToolSearch|TaskList|TaskGet|TaskOutput|ListAgents|ReadNotifications|WebFetch|WebSearch|Monitor|ListMcpResourcesTool|ReadMcpResourceTool)$");
      def ro_word: test("^(cat|head|tail|ls|grep|egrep|fgrep|rg|wc|jq|sed|sleep|echo|printf|date|ps|pgrep|stat|sort|uniq|cut|tr|test|\\[|true|false|command|which|type|cd|pwd|diff|comm|file|du|df|basename|dirname|readlink|realpath|nl|column|done|fi|esac|\\}|cc-await-ping|cc-mail|cc-thread|cc-context|claude-accounts|session-continue\\.sh|wrap-ledger\\.sh)$");
      def git_ro: test("^(status|log|diff|show|rev-parse|rev-list|ls-tree|ls-files|merge-base|cat-file|describe|fetch|blame|shortlog|reflog|grep)$");
      def clause_work:
        sub("^[[:space:]]+"; "")
        | sub("^((then|do|else|if|elif|while|until|time|!|\\{)[[:space:]]+)+"; "")
        | sub("^([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)+"; "")
        | if . == "" then false
          else (split(" ") | map(select(. != ""))) as $w
          | ($w[0] | sub(".*/"; "")) as $c
          | if $c == "git" then
              ($w[1:] | . as $a
               | reduce range(0; length) as $i ({skip:false, s:null};
                   if .s != null then .
                   elif .skip then .skip = false
                   elif ($a[$i] | test("^-(C|c)$")) then .skip = true
                   elif ($a[$i] | startswith("-")) then .
                   else .s = $a[$i] end)
               | .s) as $s
              | (($s // "") | git_ro | not)
            else ($c | ro_word | not) end
          end;
      def bash_work:
        (gsub("[0-9]?>[[:space:]]*/dev/null|&>[[:space:]]*/dev/null|[0-9]?>&[0-9-]"; "") | test(">"))
        or test("(^|[[:space:];|&])sed[[:space:]]+(-[A-Za-z]*i|--in-place)|(^|[[:space:]])-(delete|exec|execdir|ok)([[:space:]]|$)")
        or ([ splits("\n|&&|\\|\\||;|\\||\\$\\(|`|\\(|\\)") | clause_work ] | any);
      def tool_work:
        if .name == "Bash" then ((.input.command // "") | bash_work)
        else ((.name // "") | ro_tool | not) end;
      def boundary($r):
        $r.type == "user" and ($r.isSidechain != true)
        and ( (($r.message.content|type) != "array")
              or (([$r.message.content[] | select(.type? == "tool_result")] | length) == 0) );
      def text: if type == "string" then . else ([.[]? | .text? // empty] | join("\n")) end;
      reduce (inputs | fromjson?) as $r ([];
        if boundary($r) then
          (. + [{b: ($r.message.content | text), g: false, w: false, a: false}]) | .[-($n + 1):]
        elif length == 0 then .
        elif ($r.type == "attachment") and (($r.attachment.type // "") == "goal_status")
             and ($r.attachment.sentinel != true) and ($r.attachment.met == false) and (.[-1].a | not)
        then .[-1].g = true
        elif ($r.type == "assistant") and ($r.isSidechain != true) then
          .[-1].a = true
          | .[-1].w = (.[-1].w or ([ $r.message.content[]? | select(.type? == "tool_use") | tool_work ] | any))
        else . end)
      | .[-$n:][] | {b, g, w}'
}
