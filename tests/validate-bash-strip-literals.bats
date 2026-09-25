#!/usr/bin/env bats
# validate-bash-strip-literals — the text-matching deny rules decide on what EXECUTES, not on what is
# MENTIONED (hooks/validate-bash.sh :: vb_classify / vb_rule_text_init, 2026-09-24).
#
# Replaying 118 real denies from 2026-09-09..23 left 26 standing, ~16 of them a rule firing on words
# inside a heredoc body or a quoted literal: a bats fixture being written, a commit message, a
# `for c in "…sudo rm -rf /x…"` test list. Two halves, and the second is the one that matters:
#   FP  — each shape (shortened from a real row) must NOT carry the rule's deny reason. Red on the
#         pre-change hook, green after.
#   TP  — the bare act, and the same act handed to an interpreter (`sh -c`, `bash -c`, `eval`,
#         `bash <<EOF`, `| bash`, `bash <<<`), must still DENY. Green on both hooks: the narrowing
#         opened nothing.
# Run against another hook with VB_STRIP_HOOK=/path/to/validate-bash.sh (it needs a lib/ beside it).

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_VB_DECISION_LOG="$BATS_TEST_TMPDIR/decisions.jsonl"
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="${VB_STRIP_HOOK:-$REPO/hooks/validate-bash.sh}"
  FX="$BATS_TEST_TMPDIR/fx"; mkdir -p "$FX"; git -C "$FX" init -q -b main .
  command -v python3 >/dev/null 2>&1 || skip "python3 not installed"
}

decide() {  # <command> → DENY|<reason> · ASK|<reason> · PASS
  local out
  out="$(python3 -c 'import json,sys;print(json.dumps({"session_id":"5f0c1a2e-0000-4000-8000-00000000cb01","cwd":sys.argv[2],"tool_input":{"command":sys.argv[1]}}))' "$1" "$FX" \
        | bash "$HOOK" 2>/dev/null)"
  [ -z "$out" ] && { printf 'PASS'; return 0; }
  printf '%s' "$out" | python3 -c 'import sys,json;h=json.load(sys.stdin)["hookSpecificOutput"];print(h["permissionDecision"].upper()+"|"+h.get("permissionDecisionReason",""))'
}

must_deny() {  # <command>…
  local c d
  for c in "$@"; do
    d="$(decide "$c")"
    [[ "$d" == DENY* ]] || { printf 'NOT DENIED (%s):\n%s\n' "${d%%|*}" "$c"; return 1; }
  done
}

must_not_fire() {  # <reason-prefix> <command>… — the rule's own deny must be absent
  local why="$1" c d; shift
  for c in "$@"; do
    d="$(decide "$c")"
    [[ "$d" != *"$why"* ]] || { printf 'RULE FIRED on a mention:\n%s\n' "$c"; return 1; }
  done
}

# ── FALSE POSITIVES: a mention is not the act ────────────────────────────────────────────────────
@test "FP sudo rm: a quoted list item and a heredoc body are not the act" {
  must_not_fire 'potential system damage (sudo rm' \
    'for c in "git status" "sudo rm -rf /x" "cc-do --list"; do printf "%s\n" "$c"; done' \
    $'cat > /tmp/pb-guard.sh <<\'PBEOF\'\n# refuses sudo rm and fork bombs\nPBEOF'
}

@test "FP git commit -n: quoted test data and a heredoc body are not the act" {
  must_not_fire 'git commit -n blocked' \
    $'for c in \'git commit -n -m x\' \'git add -A\'; do o=$(printf "%s" "$c"); done' \
    $'python3 - <<\'PY\'\ncases = ["git commit -n -m x", "git push -f origin main"]\nPY'
}

@test "FP git identity write: a fixture WRITTEN through a heredoc is not a write here" {
  must_not_fire 'git identity write' \
    $'cat > tests/x.bats <<\'BATS\'\nsetup() {\n  cd "$WORK" || return 1\n  git config user.email tester@example.com\n}\nBATS' \
    $'python3 - <<\'PY\'\ns = \'\'\'git -C "$d" config user.email t@t\'\'\'\nPY'
}

@test "FP DDL: a tool and its SQL named only inside literals or a heredoc body" {
  must_not_fire 'DDL blocked' \
    $'printf \'%s\\n\' "import sqlite3" "c.execute(\'CREATE TABLE t(a)\')" > /tmp/bench.py' \
    $'cat > /tmp/probe.mjs <<\'EOF\'\nimport "@libsql/client"\nawait q("CREATE TABLE IF NOT EXISTS parent (id INTEGER)")\nEOF'
}

@test "FP drizzle-kit push: grepping for the deny text, and a doc that names it" {
  must_not_fire 'drizzle-kit push bypasses' \
    "grep -E 'drizzle-kit push bypasses|DDL blocked' /tmp/denies.log" \
    $'cat > note.md <<\'MD\'\nnever run drizzle-kit push against prod\nMD'
}

@test "FP git add -f: a commit-message body and a written fixture are not git add's argv" {
  must_not_fire 'git add' \
    $'git add a.txt\ngit commit -q -F - <<\'MSG\'\ndocs: why\n\ngit add -f is refused here\nMSG' \
    $'cat > t.bats <<\'BATS\'\n  git add -f ignored.txt\nBATS'
}

# ── TRUE POSITIVES: the act, bare and handed to an interpreter, still denies ─────────────────────
@test "TP sudo rm / fork bomb, bare and wrapped" {
  must_deny 'sudo rm -rf /x' "sh -c 'sudo rm -rf /x'" 'bash -c "sudo rm -rf /x"' 'eval "sudo rm -rf /x"' \
    $'bash <<\'EOF\'\nsudo rm -rf /x\nEOF' "printf '%s' 'sudo rm -rf /x' | bash" 'bash <<<"sudo rm -rf /x"' \
    ':(){ :|:& };:'
}

@test "TP sudo rm hidden behind quoting tricks the scanner must not blank" {
  must_deny $'echo "it\'s" ; sudo rm -rf /x ; echo \'a b\'' \
    'x="$(sudo rm -rf /x)"' \
    $'# don\'t\nsudo rm -rf /x \'y z\'' \
    'ssh host "sudo rm -rf /x"' \
    "awk 'BEGIN{system(\"sudo rm -rf /x\")}'" \
    $'python3 - <<\'PY\'\nimport os\nos.system("sudo rm -rf /x")\nPY'
}

@test "TP git commit -n, bare and wrapped" {
  must_deny 'git commit -n -m x' "sh -c 'git commit -n -m x'" 'bash -c "git commit -n -m x"' \
    'eval "git commit -n -m x"' $'bash <<\'EOF\'\ngit commit -n -m x\nEOF' \
    'git commit -m "a b" -n'
}

@test "TP git identity write, bare and wrapped" {
  must_deny 'git config user.email a@b' "sh -c 'git config user.email a@b'" \
    'bash -c "git config user.email a@b"' 'eval "git config user.email a@b"' \
    $'bash <<\'EOF\'\ngit config user.email a@b\nEOF' 'git -C "" config user.email t@t' \
    'git -C "$d" config user.email t@t'
}

@test "TP DDL, bare and wrapped" {
  must_deny 'turso db shell x "DROP TABLE t"' "sh -c 'turso db shell x \"DROP TABLE t\"'" \
    "bash -c 'turso db shell x \"DROP TABLE t\"'" "eval 'turso db shell x \"DROP TABLE t\"'" \
    $'bash <<\'EOF\'\nturso db shell x "DROP TABLE t"\nEOF' \
    $'turso db shell x <<\'SQL\'\nDROP TABLE t;\nSQL' 'echo "DROP TABLE x" | sqlite3 app.db'
}

@test "TP drizzle-kit push, bare and wrapped" {
  must_deny 'drizzle-kit push' "sh -c 'drizzle-kit push'" \
    'bash -c "drizzle-kit push"' 'eval "drizzle-kit push"' $'bash <<\'EOF\'\ndrizzle-kit push\nEOF'
}

@test "TP git add -f, bare and wrapped" {
  must_deny 'git add -f ignored.txt' 'git add -f "my file.txt"' \
    $'git add -f x\ngit commit -q -F - <<\'MSG\'\nwhy\nMSG' \
    'bash -c "git add -f x"' "sh -c 'git add -f x'" 'eval "git add -f x"' \
    $'bash <<\'EOF\'\ngit add -f x\nEOF'
}

# ── Newly CLOSED: the raw regex let these through, the literal-aware text does not ──────────────
# Red on the pre-change hook, green after — the opposite direction from the FP tests. The raw
# commit regex stopped at the `;` INSIDE a quoted message; the raw drizzle regex could not see
# through a quoted command word. A blanked literal is one word, and a bare quoted word is unquoted.
@test "CLOSED: a metacharacter inside a quoted message, and a quoted command word" {
  must_deny 'git commit -m "a;b" -n' 'npx "drizzle-kit" push'
}
