#!/bin/bash
# Both directions for pr-gate.sh. The false-positive direction is the one that matters:
# a gate that blocks good work gets switched off, and then it protects nothing.
#
# Check 0 (should this PR exist) runs BEFORE the body checks, so the body tests set
# PR_REVIEWER to get past it. That is not a workaround — it is how the checks isolate.
HOOK="$HOME/.claude/hooks/pr-gate.sh"
pass=0; fail=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

# Two fixture repos: one author, and two.
mkrepo() { # dir n_authors
  local d="$TMP/$1"; mkdir -p "$d"; git -C "$d" init -q
  git -C "$d" -c user.email=a@x.test -c user.name=A commit -q --allow-empty -m one
  [ "$2" = 2 ] && git -C "$d" -c user.email=b@x.test -c user.name=B commit -q --allow-empty -m two
  echo "$d"
}
SOLO=$(mkrepo solo 1)
TEAM=$(mkrepo team 2)

verdict() { # command [cwd] [env-assignment]
  local out
  out=$(jq -nc --arg c "$1" --arg d "${2:-$SOLO}" \
        '{tool_name:"Bash", cwd:$d, tool_input:{command:$c}}' \
        | env ${3:-IGNORE=1} bash "$HOOK" 2>/dev/null)
  case "$out" in
    *'"deny"'*) echo DENY ;;
    *'"ask"'*)  echo ASK  ;;
    *)          echo ALLOW ;;
  esac
}

check() { # name expected command [cwd] [env]
  local got; got=$(verdict "$3" "${4:-$SOLO}" "${5:-}")
  if [ "$got" = "$2" ]; then printf '  ✓ PASS  %-54s %s\n' "$1" "$got"; pass=$((pass+1))
  else printf '  ✗ FAIL  %-54s got %s want %s\n' "$1" "$got" "$2"; fail=$((fail+1)); fi
}

R="PR_REVIEWER=someone"          # gets past check 0 so body checks are reachable
LONG=$(python3 -c 'print(" ".join(["word"]*450))')
GOOD='The bridge no longer reports a booked guest as dropped.

The read-back ran before the index caught up, so a real reservation read as absent.
Verified with `npm test` (618 pass).

- `src/handler.ts` — settle-and-retry on an inconclusive read'

echo
echo "pr-gate — both directions"
echo
echo "CHECK 0 — should this PR exist (verdict is ASK, never DENY):"
check "solo repo, no reviewer -> ASK"        ASK   "gh pr create --title x --body 'A thing is now true.'"
check "solo repo, --reviewer named"          ALLOW "gh pr create --reviewer bob --body 'A thing is now true.'"
check "solo repo, PR_REVIEWER set"           ALLOW "gh pr create --body 'A thing is now true.'" "$SOLO" "$R"
check "multi-author repo is not asked"       ALLOW "gh pr create --body 'A thing is now true.'" "$TEAM"
check "pr EDIT is never asked (only create)" ALLOW "gh pr edit 12 --body 'A thing is now true.'"

echo
echo "CHECKS 1-2 — body shape (verdict is DENY):"
check "heading first"                DENY "gh pr create --body '## Summary

- did a thing'" "$SOLO" "$R"
check "bullet first"                 DENY "gh pr create --body '- fixed the parser'" "$SOLO" "$R"
check "numbered list first"          DENY "gh pr create --body '1. fixed the parser'" "$SOLO" "$R"
check "boilerplate opener"           DENY "gh pr create --body 'Summary of changes: we rewrote it.'" "$SOLO" "$R"
check "this PR contains"             DENY "gh pr create --body 'This PR contains the rewrite.'" "$SOLO" "$R"
check "over the word cap"            DENY "gh pr create --body '$LONG'" "$SOLO" "$R"
check "--body= form"                 DENY "gh pr create --body='## Changes'" "$SOLO" "$R"
check "pr edit body is gated"        DENY "gh pr edit 12 --body '- one line'"

echo
echo "NEGATIVE CONTROLS (must not fire at all):"
check "a good pyramid body"          ALLOW "gh pr create --body '$GOOD'" "$SOLO" "$R"
check "assertion then heading"       ALLOW "gh pr create --body 'The parser no longer drops rows.

## Detail
- one'" "$SOLO" "$R"
check "not a PR command"             ALLOW "git status"
check "gh pr list"                   ALLOW "gh pr list --state all"
check "no body (--fill)"             ALLOW "gh pr create --fill" "$SOLO" "$R"
check "body on stdin"                ALLOW "gh pr create --body-file -" "$SOLO" "$R"
check "prose mentioning gh pr"       ALLOW "echo 'run gh pr create later'"
check "code fence first"             ALLOW "gh pr create --body '\`\`\`
## not a heading, it is code
\`\`\`
The parser no longer drops rows.'" "$SOLO" "$R"
check "kill switch disables all"     ALLOW "gh pr create --body '- bullet first'" "$SOLO" "CC_PR_PYRAMID=off"

echo
echo "$( [ $fail -eq 0 ] && echo PASS || echo FAIL ) — $pass passed, $fail failed"
exit $(( fail > 0 ))
