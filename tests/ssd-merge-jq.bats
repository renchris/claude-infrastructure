#!/usr/bin/env bats
# ssd-merge-jq.bats — the dispatcher's merge program alone (hooks/lib/ssd-merge.jq), on fixture
# rawfiles: no children run, no shell, no clock. A3-dispatcher.md §6 T16, README Wave 2 row #19.
#
# The program's contract, each asserted below:
#   · channel split: a JSON object gives its additionalContext and systemMessage; anything else is
#     plain context (v1's contract, which is the harness's); registration order everywhere
#   · tiers decide what the context cap CUTS, never the order; whole-or-nothing per child
#   · the notices: one line per late / killed / absent / malformed / cut child, first, with recovery
#   · line 2 is the ledger row (main) or one row per late child (late mode)

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd -P)"
  PROG="$REPO/hooks/lib/ssd-merge.jq"
  D="$BATS_TEST_TMPDIR"; : > "$D/status"
  export HOME="$D/home"; mkdir -p "$HOME"    # the program reads no file, but no suite runs on the live ~/
  printf '1000.000000000 /x/run.1/t0\n' > "$D/times"
  RAW=()
}

kid() { # <NN> <name> <done|late|absent|killed> <rc|-> [stdout]
  printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >> "$D/status"
  if [ $# -ge 5 ]; then printf '%s' "$5" > "$D/o$1"; RAW+=(--rawfile "o$1" "$D/o$1"); fi
}

merge() {
  run jq -nc -f "$PROG" --arg mode "${MODE:-main}" --arg sid S1 --arg src startup --arg cfg .claude-x \
    --arg ledger /h/.claude/logs/ssd.jsonl --arg home /h --arg dir /h/.claude/hooks \
    --argjson cap "${CAP:-9500}" --argjson smcap "${SMCAP:-9000}" --argjson emit 9 --argjson late 60 \
    --argjson lag 0 --argjson pid 11 --argjson ppid 22 \
    --rawfile status "$D/status" --rawfile times "$D/times" "${RAW[@]}"
  [ "$status" -eq 0 ]
  L1="$(printf '%s\n' "$output" | sed -n 1p)"; L2="$(printf '%s\n' "$output" | sed -n 2p)"
}
c1() { printf '%s' "$L1" | jq -r '.hookSpecificOutput.additionalContext // empty'; }
s1() { printf '%s' "$L1" | jq -r '.systemMessage // empty'; }

@test "channel split, plain text and registration order, with v1's exact keys" {
  kid 01 a.sh "done" 0 '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"A1"},"systemMessage":"S1"}'
  kid 02 b.sh "done" 0 $'P2\n'
  kid 03 c.sh "done" 0 '{"systemMessage":"S3"}'
  merge
  [ "$L1" = '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"A1\nP2"},"systemMessage":"S1\nS3"}' ]
}

@test "non-object JSON and non-JSON are plain context with no notice; a broken { is plain but named" {
  kid 01 a.sh "done" 0 '"str"'
  kid 02 b.sh "done" 0 '42'
  kid 03 c.sh "done" 0 '[1,'
  merge
  [ "$(c1)" = "$(printf '"str"\n42\n[1,')" ]
  [ -z "$(s1)" ]
  : > "$D/status"; RAW=()
  kid 01 d.sh "done" 0 '{"x":'
  merge
  [ "$(c1)" = '{"x":' ]
  [ "$(s1)" = '⚠ startup: d.sh printed unparseable JSON (5 chars) → merged as plain context, as the harness would' ]
  [ "$(printf '%s' "$L2" | jq -r '.kids[0].st')" = malformed ]
}

@test "a wrong-typed field is dropped and named; the good fields of that child survive" {
  kid 01 a.sh "done" 0 '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":5},"systemMessage":"OK-BANNER"}'
  merge
  [ -z "$(c1)" ]
  [ "$(s1)" = "$(printf '⚠ startup: a.sh printed hook JSON with a wrong-typed field → that field was dropped\nOK-BANNER')" ]
}

@test "empty or newline-only stdout contributes nothing; nothing at all ⇒ line 1 is null" {
  kid 01 a.sh "done" 0 ''
  kid 02 b.sh "done" 0 $'\n'
  merge
  [ "$L1" = null ]
  [ "$(printf '%s' "$L2" | jq -r '.printed')" = false ]
}

@test "tiers pick what the cap cuts; the kept children stay in registration order" {
  kid 01 frontier-status.sh "done" 0 "$(printf 'f%.0s' $(seq 300))"
  kid 02 session-start.sh "done" 0 "$(printf 's%.0s' $(seq 300))"
  kid 03 setup-plan-symlinks.sh "done" 0 'PLANS'
  CAP=400 merge
  # tier 1 (session-start) and tier 2 (plans) fit; tier 3 (frontier) is cut whole, even though first
  [ "$(c1)" = "$(printf 's%.0s' $(seq 300))"$'\n'PLANS ]
  [ "$(s1)" = "⚠ startup: context over the 400-char cap → dropped frontier-status.sh's context (300 chars)" ]
  [ "$(printf '%s' "$L2" | jq -r '[.kids[] | "\(.st):\(.cut // "-")"] | join(",")')" = "cut:ctx,ok:-,ok:-" ]
}

@test "late notice: exact text, ledger path tilde-ized, the child's own recovery command" {
  kid 01 config-mirror-assert.sh late -
  merge
  [ "$(s1)" = "⚠ startup: config-mirror-assert.sh still running at 9s → the mirror/parity/drift/budget checks NOT shown this start; its result logs to ~/.claude/logs/ssd.jsonl (late row) · re-check: zsh -fc 'source ~/.claude/lib/config-mirror.zsh; _cc_sync_account ~/.claude-x'" ]
  [ -z "$(c1)" ]                                                     # a banner child costs 0 tokens
}

@test "a late recycle child gives the model its check line, naming this session's packet" {
  kid 01 recycle-failed-inject.sh late -
  kid 02 a.sh "done" 0 'A'
  merge
  [ "$(c1)" = "$(printf 'RECYCLE CHECK INCOMPLETE — if ~/.claude/autonomy/recycle-failed/S1.prompt.md exists, read it and act on it first.\nA')" ]
}

@test "absent: named with the install command; a model-facing one also gets its model line" {
  kid 01 session-start.sh absent -
  merge
  [ "$(s1)" = "⚠ startup: session-start.sh is missing or not executable in ~/.claude/hooks → the MCP status line skipped this start · re-install: bash ~/Development/claude-infrastructure/install.sh" ]
  [ "$(c1)" = "MCP status line missing this start; do not assume MCP servers are connected." ]
}

@test "rc >= 129 is a kill: the partial output is dropped and its size named" {
  kid 01 a.sh "done" 137 'PARTIAL'
  merge
  [ -z "$(c1)" ]
  [ "$(s1)" = "⚠ startup: a.sh was killed (rc 137) → its partial output (7 chars) was dropped, not merged" ]
  [ "$(printf '%s' "$L2" | jq -c '.kids[0] | {st, rc, pc}')" = '{"st":"killed","rc":137,"pc":7}' ]
}

@test "ledger row (line 2): fields, per-child ms from the mtimes, notices" {
  printf '1000.000000000 /x/run.1/t0\n1000.250000000 /x/run.1/r01\n1002.000400000 /x/run.1/r02\n' > "$D/times"
  kid 01 a.sh "done" 0 'A'
  kid 02 b.sh "done" 3 '{"systemMessage":"BB"}'
  kid 03 c.sh late -
  merge
  [ "$(printf '%s' "$L2" | jq -c '{v, sid, src, cfg, pid, ppid, lag_s, emit_s, printed, ctx_out}')" = '{"v":1,"sid":"S1","src":"startup","cfg":".claude-x","pid":11,"ppid":22,"lag_s":0,"emit_s":9,"printed":true,"ctx_out":1}' ]
  [ "$(printf '%s' "$L2" | jq -c '[.kids[] | [.c, .st, .rc, .ms, .cc, .sc]]')" = '[["a.sh","ok",0,250,1,0],["b.sh","fail",3,2000,0,2],["c.sh","late",null,null,null,null]]' ]
  [ "$(printf '%s' "$L2" | jq -c .notices)" = '["c.sh late"]' ]
  printf '%s' "$L2" | jq -e '.ts | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$")'
}

@test "watchPaths union keeps order and strings only; first sessionTitle wins; initialUserMessage dropped" {
  kid 01 a.sh "done" 0 '{"hookSpecificOutput":{"hookEventName":"SessionStart","watchPaths":["/x","/y",7],"sessionTitle":"T1","initialUserMessage":"go"}}'
  kid 02 b.sh "done" 0 '{"hookSpecificOutput":{"hookEventName":"SessionStart","watchPaths":["/y","/z"],"sessionTitle":"T2"}}'
  merge
  [ "$L1" = '{"hookSpecificOutput":{"hookEventName":"SessionStart","watchPaths":["/x","/y","/z"],"sessionTitle":"T1"}}' ]
  [ "$(printf '%s' "$L2" | jq -c '.kids[0].dropped_fields')" = '["initialUserMessage"]' ]
}

@test "the systemMessage cap never drops a notice, only banners, from the end" {
  kid 01 x.sh late -
  kid 02 a.sh "done" 0 "{\"systemMessage\":\"$(printf 'a%.0s' $(seq 60))\"}"
  kid 03 b.sh "done" 0 "{\"systemMessage\":\"$(printf 'b%.0s' $(seq 60))\"}"
  SMCAP=200 merge
  [ "$(s1 | sed -n 1p)" = "⚠ startup: x.sh still running at 9s → its output NOT shown this start; its result logs to ~/.claude/logs/ssd.jsonl (late row)" ]
  [[ "$(s1)" == *"dropped b.sh's banner (60 chars)"* ]] || false
  [[ "$(s1)" == *"dropped a.sh's banner (60 chars)"* ]] || false
  # no banner bytes left, names only: a 10-byte run is no notice word (the notices' own prose holds
  # 20+ a/b letters, so a letter count cannot tell a name from a banner)
  [[ "$(s1)" != *aaaaaaaaaa* && "$(s1)" != *bbbbbbbbbb* ]] || false
  [ "$(s1 | grep -c .)" -eq 3 ]                                      # one late notice + two drop notices
}

@test "late mode: one row per late child (late-ok / late-fail / killed); a killed child is never merged" {
  printf '1000.000000000 /x/run.1/t0\n1014.210000000 /x/run.1/r01\n1003.000000000 /x/run.1/r02\n' > "$D/times"
  kid 01 a.sh "done" 0 '{"systemMessage":"LATE-BANNER"}'
  kid 02 b.sh "done" 1 'LATE-CTX'
  kid 03 c.sh killed - 'PART'
  MODE=late merge
  [ "$(c1)" = LATE-CTX ]
  [ "$(s1)" = "$(printf '⚠ startup: c.sh was killed at the 60s backstop → its partial output (4 chars) was dropped, not merged\nLATE-BANNER')" ]
  [ "$(printf '%s\n' "$output" | sed -n '2,$p' | jq -c '[.kind, .c, .st, .rc, .ms]' | paste -sd' ' -)" = '["late","a.sh","late-ok",0,14210] ["late","b.sh","late-fail",1,3000] ["late","c.sh","killed",null,null]' ]
}
