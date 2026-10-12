#!/usr/bin/env bats
# rm-prompt-preempt.sh + hooks/lib/rm_prompt_shape.py — the PermissionRequest(Bash) hook that answers
# Claude Code's built-in dangerous-removal dialog with an instant DENY carrying the rewrite, instead
# of the 2-minute unattended timer. Pinned both ways: the census shapes deny, everything else (other
# dialogs, non-timer modes, the kill switch, malformed input) passes through silently.
#
# Positives come from docs/research/autodeny-prompts-2026-10-11/prototypes/autodeny-64.tsv, the 64
# real auto-denied commands. That TSV stores only command_head (~240 chars, newlines as " ⏎ "), and
# the prototype predicate's 54 hits were scored on the FULL commands. On full commands this port
# matches the prototype on 64 of 64 (measured 2026-10-11 against /tmp/autodeny-census/final/rows.json,
# which is not in the repo). On the truncated heads it matches 34 of the 54: the 20 misses are rows
# whose -c script, rm or cd is cut off by the truncation, not predicate gaps:
#   inline_shell (15): 10-08T17:23:42 10-09T18:32:13 10-10T02:06:23 10-10T03:23:36 10-10T03:55:31
#     10-10T04:13:50 10-10T05:30:48 10-10T13:44:59 10-10T15:54:46 10-10T16:33:01 10-10T16:36:14
#     10-10T18:44:05 10-10T22:17:23 10-11T04:29:12 10-11T04:29:33
#   cd_rel_glob (4): 10-06T18:28:27 10-10T17:59:59 10-10T18:43:58 10-11T04:52:11
#   unguarded_var (1): 10-11T06:53:07
# Truncation also cuts the rm out of 2 of the 3 G4 heads (bash -c script that DOES remove), so the
# G4 recipe is pinned on minimal reconstructions of those three shapes below.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  H="$REPO/hooks/rm-prompt-preempt.sh"
  LIB="$REPO/hooks/lib/rm_prompt_shape.py"
  TSV="$REPO/docs/research/autodeny-prompts-2026-10-11/prototypes/autodeny-64.tsv"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  LOG="$HOME/.claude/logs/rm-prompt-preempt.jsonl"
  unset CC_RM_PREEMPT
  PERSON_ONLY='Only a person may approve a removal this check stops; do not work around it by splitting, scripting, or re-issuing the removal through another tool or shell.'
}

# req <command> [mode] [tool] [agent_id] → the PermissionRequest hook JSON
req() {
  jq -cn --arg c "$1" --arg m "${2:-auto}" --arg t "${3:-Bash}" --arg a "${4:-}" \
    '{session_id:"sess-1", hook_event_name:"PermissionRequest", tool_name:$t, permission_mode:$m,
      tool_input:{command:$c}, permission_suggestions:[]} + (if $a == "" then {} else {agent_id:$a} end)'
}

# run the hook the way Claude Code would, under /bin/bash (3.2 on macOS)
hook() { printf '%s' "$1" | /bin/bash "$H"; }

behavior() { jq -r '.hookSpecificOutput.decision.behavior // empty' <<<"$1"; }
message() { jq -r '.hookSpecificOutput.decision.message // empty' <<<"$1"; }

INLINE='bash -c '\''f(){ "$@"; }; f true'\'''

@test "hook is executable and bash -n clean under /bin/bash" {
  [ -x "$H" ]
  /bin/bash -n "$H"
}

@test "census positives: 34 of the 54 predicate-hit TSV heads deny, each with its predicted shape" {
  python3 -I - "$TSV" >"$BATS_TEST_TMPDIR/pos.jsonl" <<'PY'
import csv, json, sys
for r in csv.DictReader(open(sys.argv[1], encoding='utf-8'), delimiter='\t'):
    if not r['preempt_predicate_hit']:
        continue
    cmd = r['command_head'].replace(' ⏎ ', '\n').replace('⏎', '\n')
    print(json.dumps({'want': r['preempt_predicate_hit'], 'ts': r['ts'],
                      'req': {'session_id': 'tsv-' + r['ts'], 'tool_name': 'Bash',
                              'permission_mode': 'auto', 'tool_input': {'command': cmd}}}))
PY
  [ "$(wc -l <"$BATS_TEST_TMPDIR/pos.jsonl" | tr -d ' ')" -eq 54 ]
  denied=0
  while IFS= read -r line; do
    want="$(jq -r .want <<<"$line")"
    out="$(hook "$(jq -c .req <<<"$line")")"
    [ -z "$out" ] && continue
    [ "$(behavior "$out")" = deny ] || { echo "not a deny: $out"; false; }
    got="$(tail -n 1 "$LOG" | jq -r .shape)"
    [ "$got" = "$want" ] || { echo "shape $got != $want for $(jq -r .ts <<<"$line")"; false; }
    denied=$((denied + 1))
  done <"$BATS_TEST_TMPDIR/pos.jsonl"
  echo "denied=$denied"
  [ "$denied" -eq 34 ]
  [ "$(wc -l <"$LOG" | tr -d ' ')" -eq 34 ]
}

@test "census rows the predicate does not match stay silent" {
  python3 -I - "$TSV" >"$BATS_TEST_TMPDIR/neg.jsonl" <<'PY'
import csv, json, sys
for r in csv.DictReader(open(sys.argv[1], encoding='utf-8'), delimiter='\t'):
    if r['preempt_predicate_hit']:
        continue
    cmd = r['command_head'].replace(' ⏎ ', '\n').replace('⏎', '\n')
    print(json.dumps({'tool_name': 'Bash', 'permission_mode': 'auto', 'tool_input': {'command': cmd}}))
PY
  [ "$(wc -l <"$BATS_TEST_TMPDIR/neg.jsonl" | tr -d ' ')" -eq 10 ]
  while IFS= read -r line; do
    [ -z "$(hook "$line")" ] || { echo "unexpected deny: $line"; false; }
  done <"$BATS_TEST_TMPDIR/neg.jsonl"
}

@test "no output ever carries allow or updatedInput, and the sources have no allow branch" {
  for c in "$INLINE" 'D=/tmp/x; rm -f $D/*.jpg' 'cd /tmp/a && rm -f shots/*'; do
    out="$(hook "$(req "$c")")"
    [ "$(behavior "$out")" = deny ]
    # bats errexit ignores a non-final `!` command, hence `|| false` on every negation here
    ! grep -q 'updatedInput' <<<"$out" || false
    ! grep -q '"allow"' <<<"$out" || false
  done
  ! grep -nE "\"allow\"|'allow'|updatedInput" "$H" "$LIB" || false
}

@test "every recipe carries Claude Code's person-only sentence, the 2-minute reason and a re-issue" {
  for c in "$INLINE" 'D=/tmp/x; rm -f $D/*.jpg' 'cd /tmp/a && rm -f shots/*'; do
    msg="$(message "$(hook "$(req "$c")")")"
    grep -qF "$PERSON_ONLY" <<<"$msg"
    grep -qF '2-minute' <<<"$msg"
    grep -qF 'rm-prompt-preempt hook' <<<"$msg"
    grep -qF 'Re-issue' <<<"$msg"
  done
}

@test "inline_shell with no removal: script-file or direct recipe, with the zsh function note" {
  msg="$(message "$(hook "$(req "$INLINE")")")"
  grep -qF 'bash /tmp/<name>.sh' <<<"$msg"
  grep -qF 'zsh' <<<"$msg"
  grep -qF 'AB(){ agent-browser --session x "$@"; }' <<<"$msg"
}

@test "inline_shell that removes (the 3 G4 shapes): literal-path recipe, never a script file" {
  g4a='bash -c '\''. /x/w3_common.sh; T=/tmp/tm2-w3/inspect; rm -rf $T; mkdir -p $T/home; for s in "a 1" "b 2"; do set -- $s; echo $1; done'\'''
  g4b='T=$(mktemp -d /tmp/gar.XXXX); bash -c '\''hf(){ "$@"; }; source <(sed -n "/^f()/,/^}/p" x.sh); f a'\''; rm -rf $T'
  g4c='bash -c '\''hf(){ "$@"; }; for f in /tmp/gar/a /tmp/gar/b; do cp "$f" /tmp/gar/t; rm -f /tmp/gar/t.ansi; done'\'''
  for c in "$g4a" "$g4b" "$g4c"; do
    out="$(hook "$(req "$c")")"
    [ "$(behavior "$out")" = deny ]
    msg="$(message "$out")"
    grep -qF '"${VAR:?}"' <<<"$msg"
    grep -qF 'literal absolute path' <<<"$msg"
    ! grep -qF 'bash /tmp/' <<<"$msg" || false
    grep -qF "$PERSON_ONLY" <<<"$msg"
    [ "$(tail -n 1 "$LOG" | jq -r '.shape + ":" + (.removal|tostring)')" = inline_shell:true ]
  done
}

@test "find -delete and unlink inside the script also count as a removal" {
  for c in 'bash -c '\''f(){ "$@"; }; f find /tmp/q -name x -delete'\''' \
           'bash -c '\''f(){ "$@"; }; f unlink /tmp/q/x'\'''; do
    out="$(hook "$(req "$c")")"
    [ "$(behavior "$out")" = deny ]
    ! grep -qF 'bash /tmp/' <<<"$(message "$out")" || false
    [ "$(tail -n 1 "$LOG" | jq -r .removal)" = true ]
  done
}

@test "unguarded_var and cd_rel_glob recipes name the token and the readable form" {
  msg="$(message "$(hook "$(req 'D=/tmp/x; rm -f $D/*.jpg')")")"
  grep -qF '`$D/*.jpg`' <<<"$msg"
  grep -qF '"${VAR:?}"/' <<<"$msg"
  msg="$(message "$(hook "$(req 'cd /tmp/a && rm -f shots/*')")")"
  grep -qF '`shots/*`' <<<"$msg"
  grep -qF 'rm -f /abs/dir/<glob>' <<<"$msg"
}

@test "readable removals and other dialogs pass through silently" {
  for c in 'rm -rf /Users/chrisren/Development/.worktrees/wt-cc-174746-13116' \
           'R=/tmp/x; rm -rf $R' \
           'git rm -r --cached $P' \
           "timeout 270 bash -c 'until grep -q DONE f; do sleep 15; done'" \
           'rm -rf "${D:?}"/build' \
           'git push origin main'; do
    out="$(hook "$(req "$c")")"
    [ -z "$out" ] || { echo "unexpected output for: $c → $out"; false; }
  done
  [ ! -e "$LOG" ]
}

@test "a non-Bash tool passes through" {
  [ -z "$(hook "$(req "$INLINE" auto Write)")" ]
  [ -z "$(hook "$(req "$INLINE" auto Agent)")" ]
}

@test "mode gate: default and acceptEdits pass through; auto, plan and bypassPermissions deny" {
  [ -z "$(hook "$(req "$INLINE" default)")" ]
  [ -z "$(hook "$(req "$INLINE" acceptEdits)")" ]
  [ -z "$(hook "$(jq -c 'del(.permission_mode)' <<<"$(req "$INLINE")")")" ]
  for m in auto plan bypassPermissions; do
    [ "$(behavior "$(hook "$(req "$INLINE" "$m")")")" = deny ] || { echo "mode $m"; false; }
  done
}

@test "kill switch: CC_RM_PREEMPT=off is a no-op; =agents acts only on subagent calls" {
  export CC_RM_PREEMPT=off
  [ -z "$(hook "$(req "$INLINE" auto Bash agent-7)")" ]
  export CC_RM_PREEMPT=agents
  [ -z "$(hook "$(req "$INLINE")")" ]
  [ "$(behavior "$(hook "$(req "$INLINE" auto Bash agent-7)")")" = deny ]
  [ "$(tail -n 1 "$LOG" | jq -r .agent_id)" = agent-7 ]
}

@test "log row: cmd_head of at most 200 chars plus sha256, never the full command" {
  long="bash -c 'f(){ \"\$@\"; }; f echo $(printf 'x%.0s' $(seq 1 300)) TAIL-MARKER-91f3'"
  out="$(hook "$(req "$long")")"
  [ "$(behavior "$out")" = deny ]
  [ "$(wc -l <"$LOG" | tr -d ' ')" -eq 1 ]
  ! grep -qF 'TAIL-MARKER-91f3' "$LOG" || false
  row="$(cat "$LOG")"
  [ "$(jq -c 'keys' <<<"$row")" = '["agent_id","cmd_head","cmd_sha256","permission_mode","removal","session_id","shape","ts"]' ]
  [ "$(jq -r '.cmd_head | length' <<<"$row")" -le 200 ]
  want="$(printf '%s' "$long" | shasum -a 256 | cut -d' ' -f1)"
  [ "$(jq -r .cmd_sha256 <<<"$row")" = "$want" ]
  [ "$(jq -r '[.ts, .session_id, .shape, .permission_mode] | join(" ")' <<<"$row" | cut -d' ' -f2-)" = 'sess-1 inline_shell auto' ]
  [ -z "$(jq -r '.command // empty' <<<"$row")" ]
}

@test "malformed, empty or odd input exits 0 silently (fail-open)" {
  run /bin/bash "$H" <<<'{bad json'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run /bin/bash "$H" </dev/null
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run /bin/bash "$H" <<<'{"tool_name":"Bash","permission_mode":"auto","tool_input":{"command":42}}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run /bin/bash "$H" <<<'{"tool_name":"Bash","permission_mode":"auto","tool_input":"rm -rf $D/"}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run python3 -I "$LIB" --decide <<<'not json at all'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a 100 KB command returns silently in under 3 s of CPU (length cap ahead of the backtracking regexes)" {
  # 500-line blank runs make NAN3/RM_OCC/CD backtrack quadratically: ~6 s uncapped (measured 2026-10-11)
  python3 -I - "$BATS_TEST_TMPDIR/big.json" <<'PY'
import json, sys
body = ""
while len(body) < 100000:
    body += "echo a\n" + "\n" * 500
json.dump({"session_id": "sess-1", "tool_name": "Bash", "permission_mode": "auto",
           "tool_input": {"command": "bash -c '" + body + "'"}}, open(sys.argv[1], "w"))
PY
  # CPU time of the hook and its children, not wall clock: at load average ~600 (2026-10-11) the
  # capped hook took 8.7 s of wall time, while its CPU time stays ~0.1 s capped vs ~6 s uncapped.
  run python3 -I - "$H" "$BATS_TEST_TMPDIR/big.json" <<'PY'
import resource, subprocess, sys
p = subprocess.run(["/bin/bash", sys.argv[1]], stdin=open(sys.argv[2], "rb"), capture_output=True)
ru = resource.getrusage(resource.RUSAGE_CHILDREN)
print("rc=%d out_bytes=%d cpu_ms=%d" % (p.returncode, len(p.stdout), int((ru.ru_utime + ru.ru_stime) * 1000)))
PY
  echo "$output"
  [ "$status" -eq 0 ]
  [[ $output =~ ^rc=0\ out_bytes=0\ cpu_ms=([0-9]+)$ ]]
  [ "${BASH_REMATCH[1]}" -lt 3000 ]
  [ ! -e "$LOG" ]
}

@test "a log that cannot be written still denies (the deny never depends on the log)" {
  mkdir -p "$HOME/.claude"
  printf 'x' >"$HOME/.claude/logs"   # a FILE where the log dir should be
  [ "$(behavior "$(hook "$(req "$INLINE")")")" = deny ]
}
