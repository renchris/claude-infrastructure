#!/usr/bin/env bats
# Hook commands and the status line name their interpreter (docs/research/panic-2026-10-18-zone-map-
# shebang-leak.md improvement 1): scripts/hook-interp.py (rewrite + lint), scripts/hook-shebang-lint.sh
# (the land-gate arm), scripts/lib/hook-cmd-bare.jq (the one normalizer), migration 0070 (the live
# rewrite, c10) and hooks/lib/shasum-direct.sh (the Stop path's shasum without a #! exec).
#
# RED-proof: the template lint case strips the prefixes from the REAL template and the same lint goes
# RED on it (77 bare commands before 2026-10-18); 0070's verify exits 1 on the bare fixture before it
# runs; without shasum-direct.sh, `type -t shasum` is `file` (the #! perl script).
#
# Hermetic: $HOME is a fixture; scripts resolve through fixture dirs, never the live layer.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  F="$BATS_TEST_TMPDIR/fx"
  mkdir -p "$HOME/.claude/hooks" "$F"
  # shellcheck disable=SC2016  # the fixture script's own $0/$1, not ours
  printf '#!/bin/bash\nprintf "%%s|%%s|%%s\\n" "$0" "$1" "$(cat)"\n' > "$HOME/.claude/hooks/b.sh"
  # shellcheck disable=SC2016  # the fixture script's own $0/$1, not ours
  printf '#!/usr/bin/env bash\nprintf "env:%%s\\n" "$1"\n' > "$HOME/.claude/hooks/e.sh"
  printf '#!/usr/bin/env python3\nimport sys; print("py:" + sys.argv[1])\n' > "$HOME/.claude/hooks/p.py"
  chmod +x "$HOME/.claude/hooks/"*
  PRED=(/usr/bin/env python3 "$REPO/scripts/hook-interp.py")
}

settings() { # <file> — every command spelling a live settings.json carries, plus non-hooks
  jq -n --arg abs "$HOME/.claude/hooks/b.sh" '{
    hooks:{
      PreToolUse:[{matcher:"Bash",hooks:[{type:"command",command:"~/.claude/hooks/b.sh pre",timeout:5,"if":"Bash(*x*)"}]}],
      Stop:[{hooks:[{type:"command",command:"$HOME/.claude/hooks/e.sh stop"},
                    {type:"command",command:($abs + " abs")},
                    {type:"command",command:"~/.claude/hooks/p.py arg"},
                    {type:"command",command:"/bin/bash ~/.claude/hooks/b.sh done"},
                    {type:"command",command:"date +%s >> /dev/null"}]}]},
    statusLine:{type:"command",command:"~/.claude/hooks/b.sh status"},
    mcpServers:{x:{command:"~/.claude/hooks/b.sh"}}}' > "$1"
}

@test "rewrite prefixes each #! command with its own shebang interpreter, verbatim, and nothing else" {
  settings "$F/s.json"
  run "${PRED[@]}" rewrite "$F/s.json"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | sed '/^rewrote/d' > "$F/out.json"
  run jq -r '[.hooks.PreToolUse[0].hooks[0].command, (.hooks.Stop[0].hooks[].command), .statusLine.command, .mcpServers.x.command] | .[]' "$F/out.json"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "/bin/bash ~/.claude/hooks/b.sh pre" ]
  [ "${lines[1]}" = "/usr/bin/env bash \$HOME/.claude/hooks/e.sh stop" ]
  [ "${lines[2]}" = "/bin/bash $HOME/.claude/hooks/b.sh abs" ]
  [ "${lines[3]}" = "/usr/bin/env python3 ~/.claude/hooks/p.py arg" ]
  [ "${lines[4]}" = "/bin/bash ~/.claude/hooks/b.sh done" ]      # already explicit: untouched
  [ "${lines[5]}" = "date +%s >> /dev/null" ]                     # a Mach-O first word: untouched
  [ "${lines[6]}" = "/bin/bash ~/.claude/hooks/b.sh status" ]
  # shellcheck disable=SC2088  # a literal ~, as settings.json stores it
  [ "${lines[7]}" = "~/.claude/hooks/b.sh" ]                      # mcpServers are not hooks
  # matcher, if, timeout carried through; a second rewrite is the identity
  [ "$(jq -c '.hooks.PreToolUse[0] | del(.hooks[0].command)' "$F/out.json")" = \
    "$(jq -c '.hooks.PreToolUse[0] | del(.hooks[0].command)' "$F/s.json")" ]
  "${PRED[@]}" rewrite "$F/out.json" 2>/dev/null | jq -S . > "$F/again.json"
  [ "$(jq -S . "$F/out.json")" = "$(cat "$F/again.json")" ]
}

@test "the rewritten command runs the same program with the same \$0, args, stdin and ~ expansion" {
  settings "$F/s.json"
  "${PRED[@]}" rewrite "$F/s.json" 2>/dev/null > "$F/out.json"
  for q in '.hooks.PreToolUse[0].hooks[0].command' '.hooks.Stop[0].hooks[0].command' \
           '.hooks.Stop[0].hooks[2].command' '.statusLine.command'; do
    old="$(jq -r "$q" "$F/s.json")"; new="$(jq -r "$q" "$F/out.json")"
    [ "$old" != "$new" ]
    # Claude Code hands the string to a shell; so do we.
    a="$(printf 'in' | /bin/bash -c "$old")"; b="$(printf 'in' | /bin/bash -c "$new")"
    [ -n "$a" ]
    [ "$a" = "$b" ]
  done
}

@test "rewrite refuses an interpreter cmd_bare cannot strip, and a prefix that contradicts the shebang" {
  printf '#!/usr/local/bin/fish\n' > "$HOME/.claude/hooks/k.sh"
  jq -n '{hooks:{Stop:[{hooks:[{type:"command",command:"~/.claude/hooks/k.sh"}]}]}}' > "$F/k.json"
  run "${PRED[@]}" rewrite "$F/k.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"refused"*"unknown-interp"* ]] || false
  [[ "$output" != *'"hooks"'* ]] || false # nothing on stdout to write
  jq -n '{hooks:{Stop:[{hooks:[{type:"command",command:"/bin/bash ~/.claude/hooks/p.py"}]}]}}' > "$F/m.json"
  run "${PRED[@]}" lint "$F/m.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"does not match the script's own shebang"* ]]
}

@test "the jq normalizer and the python one agree on one corpus" {
  local c py jqv
  # shellcheck disable=SC2088  # a literal ~, as settings.json stores it
  for c in "/bin/bash ~/.claude/hooks/x.sh a" "/usr/bin/env bash \$HOME/x.sh" "/usr/bin/env python3 /a/b.py" \
           "/bin/sh ~/x" "/bin/bash -c 'echo hi'" "~/.claude/hooks/x.sh" "date +%s" "/usr/bin/env  bash ~/y"; do
    py="$("${PRED[@]}" bare "$c")"
    jqv="$(jq -rn -L "$REPO/scripts/lib" --arg c "$c" 'include "hook-cmd-bare"; $c | cmd_bare')"
    [ "$py" = "$jqv" ] || { echo "disagree on [$c]: py=[$py] jq=[$jqv]"; false; }
  done
}

@test "land-gate lint: the real template is clean, and the same template with its prefixes stripped is RED" {
  run "$REPO/scripts/hook-shebang-lint.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=clean"* ]] || false
  jq -L "$REPO/scripts/lib" 'include "hook-cmd-bare";
      .hooks |= map_values(map(.hooks |= map(.command |= cmd_bare))) | .statusLine.command |= cmd_bare' \
     "$REPO/settings-templates/settings.example.json" > "$F/stripped.json"
  run "$REPO/scripts/hook-shebang-lint.sh" --file "$F/stripped.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"statusLine"* ]] || false
  [[ "$output" =~ verdict=RED\ n=([0-9]+) ]] || false
  [ "${BASH_REMATCH[1]}" -ge 70 ]
  run "$REPO/scripts/hook-shebang-lint.sh" --selftest
  [ "$status" -eq 0 ]
}

@test "lint: an absent file is no verdict (2), never clean" {
  run "$REPO/scripts/hook-shebang-lint.sh" --file "$F/nope.json"
  [ "$status" -eq 2 ]
}

m0070() { CC_MIGRATION_REPO="$REPO" CC_HOOK_INTERP_DIRS="$DIRS" CC_HOOK_INTERP_BACKUP_ROOT="$F/bk" \
            /bin/bash "$REPO/migrations/0070-hook-explicit-interpreter.sh" "$@"; }

fleet() { # one shared file linked from three dirs, plus one forked real copy
  mkdir -p "$HOME/.claude-next" "$HOME/.claude-secondary" "$HOME/.claude-quaternary"
  settings "$HOME/.claude/settings.json"
  ln -s "$HOME/.claude/settings.json" "$HOME/.claude-next/settings.json"
  ln -s "$HOME/.claude/settings.json" "$HOME/.claude-secondary/settings.json"
  settings "$HOME/.claude-quaternary/settings.json"
  DIRS="$HOME/.claude:$HOME/.claude-next:$HOME/.claude-secondary:$HOME/.claude-quaternary"
  cp "$HOME/.claude/settings.json" "$F/orig.json"
}

@test "0070: verify is RED before, --dry-run and a bare run write nothing" {
  fleet
  run m0070 --verify
  [ "$status" -eq 1 ]
  run m0070 --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"/bin/bash ~/.claude/hooks/b.sh pre"* ]] || false
  run m0070
  [ "$status" -eq 2 ]
  cmp -s "$HOME/.claude/settings.json" "$F/orig.json"
  cmp -s "$HOME/.claude-quaternary/settings.json" "$F/orig.json"
}

@test "0070: --confirm rewrites each real file once, links survive, backups restore, second run is a no-op" {
  fleet
  run m0070 --confirm settings.json
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c '^0070: rewrote ')" -eq 2 ]     # shared file + the fork
  [ -L "$HOME/.claude-next/settings.json" ] && [ -L "$HOME/.claude-secondary/settings.json" ] || false
  run m0070 --verify
  [ "$status" -eq 0 ]
  [ "$(jq -r .statusLine.command "$HOME/.claude-quaternary/settings.json")" = "/bin/bash ~/.claude/hooks/b.sh status" ]
  # every backup is byte-identical to the original it names
  m="$(ls "$F"/bk/hook-interp-0070-*/MANIFEST)"
  [ "$(wc -l < "$m")" -eq 2 ]
  while IFS=$'\t' read -r b _; do cmp -s "$b" "$F/orig.json"; done < "$m"
  cp "$HOME/.claude/settings.json" "$F/after.json"
  run m0070 --confirm settings.json
  [ "$status" -eq 0 ]
  [[ "$output" == *"already applied in every config dir"* ]] || false
  cmp -s "$HOME/.claude/settings.json" "$F/after.json"
}

@test "shasum-direct: same digests as /usr/bin/shasum, from the Mach-O sha1sum/sha256sum, no #! exec" {
  [ -x /sbin/sha256sum ] && [ -x /sbin/sha1sum ] || skip "no /sbin/sha*sum on this platform" || false
  [ "$(head -c 2 /sbin/sha256sum)" != '#!' ]
  run /bin/bash -c '. "$1/hooks/lib/shasum-direct.sh"; type -t shasum || echo none
                    printf "%s\n%s\n" "$CC_SHA1" "$CC_SHA256"
                    printf abc | "$CC_SHA1"; printf abc | "$CC_SHA256"' _ "$REPO"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" != "function" ]     # no perl shim left (`file` is /usr/bin/shasum on PATH)
  [ "${lines[1]}" = /sbin/sha1sum ]
  [ "${lines[2]}" = /sbin/sha256sum ]
  if [ -x /usr/bin/shasum ]; then
    [ "${lines[3]}" = "$(printf abc | /usr/bin/shasum)" ]
    [ "${lines[4]}" = "$(printf abc | /usr/bin/shasum -a 256)" ]
  fi
  # the Stop-path libs pull it in
  run /bin/bash -c '. "$1/hooks/lib/continue-sentinel.sh"; printf "%s\n" "$CC_SHA1"' _ "$REPO"
  [ "$output" = /sbin/sha1sum ]
}
