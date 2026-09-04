#!/bin/bash
# Both directions for pr-pyramid-gate.sh. The false-DENY direction is the one that matters:
# a gate that blocks good PR bodies gets switched off, and then it protects nothing.
HOOK="$HOME/.claude/hooks/pr-pyramid-gate.sh"
pass=0; fail=0

# Feed a command through the hook; echo DENY or ALLOW.
verdict() {
  local out
  out=$(jq -nc --arg c "$1" '{tool_name:"Bash", tool_input:{command:$c}}' | bash "$HOOK" 2>/dev/null)
  case "$out" in *'"deny"'*) echo DENY ;; *) echo ALLOW ;; esac
}

check() { # name expected command
  local got; got=$(verdict "$3")
  if [ "$got" = "$2" ]; then printf '  ✓ PASS  %-52s %s\n' "$1" "$got"; pass=$((pass+1))
  else printf '  ✗ FAIL  %-52s got %s want %s\n' "$1" "$got" "$2"; fail=$((fail+1)); fi
}

LONG=$(python3 -c 'print(" ".join(["word"]*450))')
GOOD='The bridge no longer reports a booked guest as dropped.

The read-back ran before the guestlist index caught up, so a real reservation read as absent.
Verified with `npm test` (618 pass) and one live read.

- `src/handler.ts` — settle-and-retry on an inconclusive read
- `test/handler.test.ts` — the false-absent case'

echo
echo "pr-pyramid-gate — both directions"
echo
echo "MUST DENY:"
check "heading first"            DENY "gh pr create --title x --body '## Summary

- did a thing'"
check "bullet first"             DENY "gh pr create --title x --body '- fixed the parser
- added a test'"
check "numbered list first"      DENY "gh pr create --title x --body '1. fixed the parser'"
check "boilerplate opener"       DENY "gh pr create --title x --body 'Summary of changes: we rewrote the mapper.'"
check "this PR contains"         DENY "gh pr create --title x --body 'This PR contains the mapper rewrite.'"
check "over the word cap"        DENY "gh pr create --title x --body '$LONG'"
check "--body= form"             DENY "gh pr create --body='## Changes'"
check "pr edit is gated too"     DENY "gh pr edit 12 --body '- one line'"

echo
echo "MUST ALLOW (negative controls):"
check "a good pyramid body"      ALLOW "gh pr create --title x --body '$GOOD'"
check "assertion then heading"   ALLOW "gh pr create --title x --body 'The parser no longer drops rows.

## Detail
- one'"
check "not a PR command"         ALLOW "git status"
check "gh pr list"               ALLOW "gh pr list --state all"
check "no body (--fill)"         ALLOW "gh pr create --fill"
check "body on stdin"            ALLOW "gh pr create --body-file -"
check "prose mentioning gh pr"   ALLOW "echo 'run gh pr create later'"
check "code fence first"         ALLOW "gh pr create --body '\`\`\`
## not a heading, it is code
\`\`\`
The parser no longer drops rows.'"
check "kill switch honoured"     ALLOW "$(CC_PR_PYRAMID=off; echo 'gh pr create --body \"- bullet\"')"

# kill switch needs the env set for the hook process, not the subshell above
out=$(CC_PR_PYRAMID=off jq -nc '{tool_name:"Bash",tool_input:{command:"gh pr create --body \"- bullet first\""}}' | CC_PR_PYRAMID=off bash "$HOOK" 2>/dev/null)
if [ -z "$out" ]; then printf '  ✓ PASS  %-52s ALLOW\n' "CC_PR_PYRAMID=off disables the gate"; pass=$((pass+1))
else printf '  ✗ FAIL  %-52s still denied\n' "CC_PR_PYRAMID=off disables the gate"; fail=$((fail+1)); fi

echo
echo "$( [ $fail -eq 0 ] && echo PASS || echo FAIL ) — $pass passed, $fail failed"
exit $(( fail > 0 ))
