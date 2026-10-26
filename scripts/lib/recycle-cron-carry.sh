#!/usr/bin/env bash
# recycle-cron-carry.sh — carry a session's live CronCreate jobs across a self-recycle.
#
# WHY. A session scheduled task (the CronCreate tool) lives only in the Claude Code process's memory:
# its own tool_result says "Session-only (not written to disk, dies when Claude exits)". A self-recycle
# (handoff-fire.sh --recycle) exits that process and starts a successor in the same pane, so every such
# task silently stops. The predecessor's transcript is the only record of what was scheduled, so this lib
# reads it and appends a "re-create these with CronCreate" block to the successor's prompt file, which the
# staged launch command reads with $(cat …) — the append is seen as long as it lands before the key is
# sent. Design: docs/research/selfrecycle-latency-2026-10-26/REPORT.md D3. Kill switch
# CC_RECYCLE_CRON_CARRY=off.
#
# WHAT COUNTS AS LIVE. A CronCreate whose result carried a job id, was not an error and was not
# durable:true (the harness's own verdict that it survives the exit), with no later non-error CronDelete
# of that id; a recurring job older than 7 days has expired, and a one-shot whose prompt has already come
# back as a user turn has fired.
#
# COST. Transcripts reach 50+ MB, so jq never sees the whole file: a fixed-string pass picks the lines
# that mention CronCreate/CronDelete, a second one the lines carrying those tool_use ids (results) or a
# one-shot's prompt prefix (fires), and only that handful is parsed. A file with no cron line costs one
# pass. The passes are perl index() (grep -a -F fallback): see _hf_cron_lines for the measurement.
#
# Sourced by handoff-fire.sh (`. lib || true`, calls guarded by `command -v`): defines functions only,
# runs nothing at source time, never exits the caller. bash 3.2 compatible.
#
# Usage:  . scripts/lib/recycle-cron-carry.sh ;  hf_cron_carry_append "$transcript" "$prompt_file"

_hf_cron_jq_lib() { # → the jq defs both passes share, on stdout (a function, so sourcing adds no global)
  # shellcheck disable=SC2016  # jq program text: its $vars are jq's, never the shell's
  printf '%s' '
def body: if (.message.content | type) == "string" then .message.content
  else ([.message.content[]? | objects | select(.type == "text") | .text | strings] | join("\n")) end;
def rtext: if (.content | type) == "string" then .content
  else ([.content[]? | objects | .text? | strings] | join("\n")) end;
def recs: [inputs | (index(":")) as $i | select($i != null)
  | {n: (.[:$i] | tonumber), r: (.[$i + 1:] | try fromjson catch null)} | select(.r | type == "object")];
def uses($name): .[] | .n as $n | .r as $r | select($r.type == "assistant")
  | $r.message.content[]? | objects | select(.type == "tool_use" and .name == $name)
  | {n: $n, tid: .id, input: (.input // {}), ts: $r.timestamp};
'
}

_hf_cron_lines() { # $1=file $2...=fixed strings → "LINENO:line" for each line holding any of them; rc 0
  local f="$1"; shift
  # perl's index() rather than grep -F: macOS grep with 2+ -F patterns read a 57 MB transcript in 1.4 s
  # user (2.2 s wall at load 130) per pass, so the two passes alone broke the 2 s budget; perl takes 0.03 s.
  if [ -x /usr/bin/perl ]; then
    /usr/bin/perl -ne 'BEGIN { @p = splice(@ARGV, 1) } for my $q (@p) { if (index($_, $q) >= 0) { print "$.:$_"; last } }' \
      -- "$f" "$@" 2>/dev/null
  else
    local -a e=(); local p
    for p in "$@"; do e+=(-e "$p"); done
    LC_ALL=C grep -a -n -F "${e[@]}" -- "$f" 2>/dev/null
  fi
  return 0
}

hf_session_crons() { # $1=transcript.jsonl → one JSON object per live job on stdout, creation order; rc 0
  local f="$1" seeds line
  local -a pats
  [ -n "$f" ] && [ -f "$f" ] && [ -r "$f" ] || return 0
  seeds="$(_hf_cron_lines "$f" '"CronCreate"' '"CronDelete"')"
  [ -n "$seeds" ] || return 0
  # Second-pass patterns: every Cron tool_use id (to find its result) and every one-shot's JSON-encoded
  # prompt prefix (to find its fire). An empty pattern would match every line, so none is kept.
  pats=('"CronCreate"' '"CronDelete"')
  while IFS= read -r line; do
    [ -n "$line" ] && pats+=("$line")
  done < <(printf '%s\n' "$seeds" | jq -R -n -r "$(_hf_cron_jq_lib)"'
  recs | (uses("CronCreate"), uses("CronDelete")) as $u
  | ($u.tid | strings | select(length > 0)),
    (select($u.input.recurring == false) | $u.input.prompt | strings | .[:120] | tojson | .[1:-1]
     | select(length > 0))' 2>/dev/null)
  _hf_cron_lines "$f" "${pats[@]}" | jq -R -n -c "$(_hf_cron_jq_lib)"'
  recs as $all
  | [$all[] | .n as $n | .r as $r | select($r.type == "user") | $r.message.content | arrays | .[]
     | objects | select(.type == "tool_result")
     | {n: $n, tid: .tool_use_id, err: (.is_error == true), text: rtext,
        tur: ($r.toolUseResult | if type == "object" then . else {} end)}] as $res
  | [$all[] | select(.r.type == "user" and ([.r.message.content | arrays | .[] | objects
       | select(.type == "tool_result")] | length) == 0) | {n, text: (.r | body)}] as $turns
  | [$all | uses("CronDelete") | . as $d
     | select(any($res[]; .tid == $d.tid and (.err | not))) | {n, id: (.input.id | tostring)}] as $dels
  | (now - 7 * 86400) as $cutoff
  | [$all | uses("CronCreate") | . as $c
     | (first($res[] | select(.tid == $c.tid)) // null) as $rr
     | select($rr != null and ($rr.err | not) and ($rr.tur.durable != true))
     | ($rr.tur.id // ($rr.text | capture("job (?<id>[0-9a-f]{6,})").id) // null) as $id
     | select($id != null and $id != "") | ($id | tostring) as $id
     | (if $c.input.recurring == false then false else true end) as $rec
     | ($c.input.prompt // "" | tostring) as $p
     | select(any($dels[]; .id == $id and .n > $c.n) | not)
     | select(($rec | not) or ((($c.ts // "") | tostring | sub("\\.[0-9]+"; "")
         | try fromdateiso8601 catch null) as $t | $t == null or $t >= $cutoff))
     | select($rec or ($p == "") or (any($turns[]; .n > $c.n and (.text | contains($p[:120]))) | not))
     | {n: $c.n, o: {id: $id, cron: ($c.input.cron // "" | tostring), prompt: $p, recurring: $rec,
        created_at: $c.ts}}]
  | sort_by(.n) | .[].o' 2>/dev/null
  return 0
}

hf_cron_carry_block() { # $1=transcript.jsonl → the markdown re-create block on stdout; rc 1 (no output) when no live job
  local jobs
  jobs="$(hf_session_crons "$1")"
  [ -n "$jobs" ] || return 1
  printf '%s\n' '<!-- recycle-cron-carry v1 -->' \
    '## Session scheduled tasks to re-create' \
    'Your predecessor had these session-only scheduled tasks (CronCreate). They ended when it exited.' \
    'Re-create each one now with the CronCreate tool, with exactly these arguments, before other work:'
  printf '%s\n' "$jobs" | jq -r -c '"~~~json", ({cron, prompt, recurring} | tojson), "~~~"' || return 1
  return 0
}

hf_cron_carry_append() { # $1=transcript.jsonl $2=prompt-file → rc 0 appended · 1 nothing to carry · 2 already carried · 3 not written
  local transcript="$1" pf="$2" block n dir tmp lead=''
  [ "${CC_RECYCLE_CRON_CARRY:-on}" = off ] && return 1
  # Checked before the transcript is read: a prompt file that cannot take the block is "not written"
  # whatever the transcript holds, and the marker check makes a second recycle a no-op.
  [ -n "$pf" ] && [ -f "$pf" ] && [ -w "$pf" ] || return 3
  dir="$(dirname "$pf")"
  [ -w "$dir" ] || return 3
  grep -q -F -e '<!-- recycle-cron-carry v1 -->' -- "$pf" 2>/dev/null && return 2
  block="$(hf_cron_carry_block "$transcript")" || return 1
  n="$(printf '%s\n' "$block" | grep -c -x -F -e '~~~json')"
  # One blank line before the block, even when the file does not end in a newline.
  [ -s "$pf" ] && [ -n "$(tail -c 1 "$pf")" ] && lead=$'\n'
  tmp="$(mktemp "$dir/.cron-carry.XXXXXX" 2>/dev/null)" || return 3
  # cp -p onto the temp keeps the original's mode (0600 stays 0600); mv -f makes the swap atomic.
  if cp -p -- "$pf" "$tmp" 2>/dev/null && printf '%s\n%s\n' "$lead" "$block" >> "$tmp" \
     && mv -f -- "$tmp" "$pf" 2>/dev/null; then
    printf '→ cron-carry: %s job(s) appended to %s\n' "$n" "$pf"
    return 0
  fi
  rm -f -- "$tmp" 2>/dev/null
  return 3
}
