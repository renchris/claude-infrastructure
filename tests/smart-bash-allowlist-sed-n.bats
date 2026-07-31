#!/usr/bin/env bats
# smart-bash-allowlist rule 6 — `sed -n` read-only paging.
#
# Measured 2026-07-31 (bin/cc-permission-audit): sed -n is 730 of the 1,014 simple-verb
# permission-prompt candidates (72%) across 41,829 Bash calls in the transcript corpus. It is the
# single largest allow-listable slice, and it is read-only: -n suppresses auto-print, so sed emits
# only what an explicit p/=/l prints.
#
# The script is validated by POSITIVE WHITELIST. The first draft blacklisted w/W/e and still let
# `sed -n 'w /tmp/out' f` through, because the guard assumed a character preceded the command
# letter — enumerating spellings instead of the class. These tests pin the whitelist AND the
# effectful forms it must exclude.
#
# NOTE ON FIXTURES: the chained-command cases below use a harmless `echo` payload rather than a
# destructive one. The repo's own bash denylist blocks a heredoc merely CONTAINING the destructive
# spelling, so writing that test would be refused by the guard it is testing near. The assertion is
# about the CHAINING operator, not the payload, so the operator is what these vary.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  HOOK="$REPO/hooks/smart-bash-allowlist.sh"
  [ -f "$HOOK" ] || skip "hook not found"
}

decide() { # $1=command -> "allow" | "defer"
  local json
  json=$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$1")
  if printf '%s' "$json" | bash "$HOOK" 2>/dev/null | grep -q '"permissionDecision": "allow"'; then
    echo allow
  else
    echo defer
  fi
}

@test "allows numeric line and range paging" {
  [ "$(decide "sed -n 5p /etc/hosts")" = allow ]
  [ "$(decide "sed -n '1,20p' file.txt")" = allow ]
  [ "$(decide "sed -n '10,\$p' f")" = allow ]
}

@test "allows regex-range paging and the = line-number command" {
  [ "$(decide "sed -n '/foo/,/bar/p' a.py")" = allow ]
  [ "$(decide "sed -n '/x/=' f")" = allow ]
}

@test "REFUSES the w command — it writes a file even under -n" {
  # the exact case the blacklist draft let through
  [ "$(decide "sed -n 'w /tmp/out' f")" = defer ]
  [ "$(decide "sed -n 's/a/b/w out' f")" = defer ]
}

@test "REFUSES e (execute) and r (read a file into the stream)" {
  [ "$(decide "sed -n '1e id' f")" = defer ]
  [ "$(decide "sed -n '1r /etc/passwd' f")" = defer ]
}

@test "REFUSES every chaining operator — nothing may ride in on the sed prefix" {
  [ "$(decide "sed -n '1p' f; echo chained")" = defer ]
  [ "$(decide "sed -n '1p' f && echo chained")" = defer ]
  [ "$(decide "sed -n '1p' f || echo chained")" = defer ]
  [ "$(decide "sed -n '1p' f | sh")" = defer ]
}

@test "REFUSES in-place editing under any spelling" {
  [ "$(decide "sed -n -i 's/a/b/' f")" = defer ]
  [ "$(decide "sed -n --in-place 's/a/b/' f")" = defer ]
}

@test "an unrecognised script shape falls through rather than being guessed at" {
  [ "$(decide "sed -n '1{h;d}' f")" = defer ]
  [ "$(decide "sed -n 'y/abc/xyz/p' f")" = defer ]
}
