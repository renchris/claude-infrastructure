#!/usr/bin/env bats
# install-core.sh — the portable autonomy core, installed into a throwaway HOME and exercised hook by hook.
#
# Every test points HOME and CLAUDE_CONFIG_DIR at $BATS_TEST_TMPDIR: the installer reads
# CLAUDE_CONFIG_DIR first, so an inherited value would otherwise install into a real config dir.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  export CLAUDE_CONFIG_DIR="$HOME/.claude"
  unset CLAUDE_CODE_SESSION_ID AUTONOMY_CORE_CONTINUE AUTONOMY_CORE_GATE AUTONOMY_CONTINUE_MAX
  CFG="$CLAUDE_CONFIG_DIR"
  AC="$CFG/autonomy-core"
  mkdir -p "$CFG"
  # /bin/bash is 3.2 on macOS: the installer and hooks must run under it.
  BASH_UNDER_TEST=/bin/bash
}

install_core() { run "$BASH_UNDER_TEST" "$REPO/install-core.sh" "$@"; }

# A throwaway git repo with one commit; $1 = directory.
mkrepo() {
  git init -q "$1"
  git -C "$1" config user.email t@example.invalid
  git -C "$1" config user.name t
  echo a > "$1/f"; git -C "$1" add f; git -C "$1" commit -qm init
}

stop_json() {  # <cwd> <message> [session]
  printf '{"session_id":"%s","cwd":"%s","last_assistant_message":"%s"}' "${3:-s1}" "$1" "$2"
}

@test "the embedded payload matches core/ (build-core-installer --check)" {
  run bash "$REPO/core/build.sh" --check
  [ "$status" -eq 0 ]
}

@test "fresh install into an empty config dir verifies itself and prints READY" {
  install_core
  [ "$status" -eq 0 ]
  [[ "$output" == *"READY."* ]]
  [[ "$output" != *"FAIL"* ]]
  [ -x "$AC/bin/autonomy" ] && [ -f "$CFG/commands/wrap.md" ] && [ -f "$CFG/commands/handoff.md" ]
  [ "$(jq '[.hooks[][].hooks[].command | select(contains("autonomy-core/hooks/"))] | length' "$CFG/settings.json")" -eq 3 ]
  grep -q 'BEGIN autonomy-core' "$CFG/CLAUDE.md"
  # the install directory is filled into the rules and commands
  ! grep -rq '__AC_HOME__' "$CFG/CLAUDE.md" "$CFG/commands" "$AC"
  grep -q "$AC/bin/autonomy continue set" "$CFG/CLAUDE.md"
}

@test "merge keeps the user's settings and hooks, backs up once, and a re-run changes nothing" {
  printf '{"model":"m","permissions":{"deny":["Bash(rm *)"]},"hooks":{"Stop":[{"hooks":[{"type":"command","command":"echo mine"}]}]}}\n' > "$CFG/settings.json"
  printf '# my rules\nkeep me\n' > "$CFG/CLAUDE.md"
  install_core; [ "$status" -eq 0 ]
  [ "$(jq -r .model "$CFG/settings.json")" = m ]
  [ "$(jq -r '.permissions.deny[0]' "$CFG/settings.json")" = 'Bash(rm *)' ]
  [ "$(jq -r '.hooks.Stop[0].hooks[0].command' "$CFG/settings.json")" = 'echo mine' ]
  cmp -s "$CFG/settings.json.before-autonomy-core" <(printf '{"model":"m","permissions":{"deny":["Bash(rm *)"]},"hooks":{"Stop":[{"hooks":[{"type":"command","command":"echo mine"}]}]}}\n')
  [ "$(head -2 "$CFG/CLAUDE.md")" = "$(printf '# my rules\nkeep me')" ]
  cp "$CFG/settings.json" "$BATS_TEST_TMPDIR/s1"; cp "$CFG/CLAUDE.md" "$BATS_TEST_TMPDIR/m1"
  install_core; [ "$status" -eq 0 ]
  [[ "$output" == *"settings.json already up to date"* ]]
  [[ "$output" == *"CLAUDE.md block already up to date"* ]]
  cmp -s "$CFG/settings.json" "$BATS_TEST_TMPDIR/s1"
  cmp -s "$CFG/CLAUDE.md" "$BATS_TEST_TMPDIR/m1"
  [ "$(jq '[.hooks[][].hooks[].command | select(contains("autonomy-core/hooks/"))] | length' "$CFG/settings.json")" -eq 3 ]
}

@test "uninstall restores the user's settings and CLAUDE.md and keeps their backups" {
  printf '{"model":"m","hooks":{"Stop":[{"hooks":[{"type":"command","command":"echo mine"}]}]}}\n' > "$CFG/settings.json"
  printf '# my rules\n' > "$CFG/CLAUDE.md"
  install_core; [ "$status" -eq 0 ]
  printf 'x\n' > "$BATS_TEST_TMPDIR/doc"
  printf '{"tool_input":{"file_path":"%s"}}' "$BATS_TEST_TMPDIR/doc" | bash "$AC/hooks/backup-before-write.sh"
  install_core --uninstall; [ "$status" -eq 0 ]
  [ "$(jq -c . "$CFG/settings.json")" = '{"model":"m","hooks":{"Stop":[{"hooks":[{"type":"command","command":"echo mine"}]}]}}' ]
  [ "$(cat "$CFG/CLAUDE.md")" = '# my rules' ]
  [ ! -e "$CFG/commands/wrap.md" ] && [ ! -e "$AC/hooks" ] && [ ! -e "$AC/bin" ]
  [ -n "$(find "$AC/backups" -type f)" ]
}

@test "uninstall after a fresh install leaves no settings hooks and no CLAUDE.md" {
  install_core; [ "$status" -eq 0 ]
  install_core --uninstall; [ "$status" -eq 0 ]
  [ ! -e "$CFG/CLAUDE.md" ]
  [ "$(jq -c . "$CFG/settings.json")" = '{}' ]
}

@test "a user's own /wrap is left alone" {
  mkdir -p "$CFG/commands"; printf 'my wrap\n' > "$CFG/commands/wrap.md"
  install_core; [ "$status" -eq 0 ]
  [ "$(cat "$CFG/commands/wrap.md")" = 'my wrap' ]
  [[ "$output" == *"is your own /wrap; left alone"* ]]
  [ -f "$CFG/commands/handoff.md" ]
}

@test "refuses (and changes nothing) where the full install is present; --force overrides" {
  mkdir -p "$CFG/hooks"; : > "$CFG/hooks/session-continue.sh"
  install_core; [ "$status" -eq 1 ]
  [[ "$output" == *"full claude-infrastructure install is already"* ]]
  [ ! -e "$AC" ] && [ ! -e "$CFG/settings.json" ]
  install_core --force; [ "$status" -eq 0 ]
}

@test "an invalid settings.json is refused and left byte-identical" {
  printf '{ not json\n' > "$CFG/settings.json"
  install_core; [ "$status" -eq 1 ]
  [[ "$output" == *"is not valid JSON"* ]]
  [ "$(cat "$CFG/settings.json")" = '{ not json' ]
}

@test "without jq, python3 does the JSON (the stock Ubuntu / WSL2 case)" {
  local bin="$BATS_TEST_TMPDIR/nojq"; mkdir -p "$bin"
  local t
  for t in bash sh git python3 cat mkdir chmod cp mv rm sed awk grep tr wc date find cksum mktemp \
           dirname uname tail head cmp sort ls env rmdir; do
    ln -s "$(command -v "$t")" "$bin/$t"
  done
  PATH="$bin" run "$bin/bash" "$REPO/install-core.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"JSON via python3"* ]]
  [[ "$output" == *"READY."* ]]
  [ "$(jq '[.hooks[][].hooks[].command | select(contains("autonomy-core/hooks/"))] | length' "$CFG/settings.json")" -eq 3 ]
  # the hooks read their input without jq too
  PATH="$bin" run bash -c "cd '$BATS_TEST_TMPDIR' && CLAUDE_CODE_SESSION_ID=p '$AC/bin/autonomy' continue set 'py step' && printf '{\"session_id\":\"p\"}' | bash '$AC/hooks/continue.sh'"
  [[ "$output" == *'"decision":"block"'*"py step"* ]]
}

@test "GNU userland first on PATH (a Linux proxy) installs and verifies" {
  local gnu="" d
  for d in coreutils gnu-sed findutils grep gawk; do
    [ -d "/opt/homebrew/opt/$d/libexec/gnubin" ] && gnu="$gnu/opt/homebrew/opt/$d/libexec/gnubin:"
  done
  [ -n "$gnu" ] || skip "no GNU userland installed here"
  PATH="$gnu$PATH" run bash "$REPO/install-core.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"READY."* ]]
}

@test "auto-continue: cwd-keyed without a session id, capped, and clear stops it" {
  install_core; [ "$status" -eq 0 ]
  mkdir -p "$BATS_TEST_TMPDIR/w"; cd "$BATS_TEST_TMPDIR/w"
  "$BASH_UNDER_TEST" "$AC/bin/autonomy" continue set "next thing"
  run "$BASH_UNDER_TEST" "$AC/bin/autonomy" continue status
  [[ "$output" == "armed (0/8): next thing" ]]
  export AUTONOMY_CONTINUE_MAX=2
  local in; in="$(printf '{"session_id":"zz","cwd":"%s"}' "$PWD")"
  run bash -c "printf '%s' '$in' | '$BASH_UNDER_TEST' '$AC/hooks/continue.sh'"; [[ "$output" == *"Auto-continue (1/2): next thing"* ]]
  run bash -c "printf '%s' '$in' | '$BASH_UNDER_TEST' '$AC/hooks/continue.sh'"; [[ "$output" == *"Auto-continue (2/2)"* ]]
  run bash -c "printf '%s' '$in' | '$BASH_UNDER_TEST' '$AC/hooks/continue.sh'"
  [[ "$output" == *systemMessage*"stopped after 2 turns"* ]] && [[ "$output" != *block* ]]
  run "$BASH_UNDER_TEST" "$AC/bin/autonomy" continue status; [ "$output" = "not armed" ]
  # another directory is never driven by this one's sentinel
  "$BASH_UNDER_TEST" "$AC/bin/autonomy" continue set "here only"
  run bash -c "printf '{\"cwd\":\"/elsewhere\"}' | '$BASH_UNDER_TEST' '$AC/hooks/continue.sh'"; [ -z "$output" ]
  "$BASH_UNDER_TEST" "$AC/bin/autonomy" continue clear
  run bash -c "printf '%s' '$in' | '$BASH_UNDER_TEST' '$AC/hooks/continue.sh'"; [ -z "$output" ]
  AUTONOMY_CORE_CONTINUE=off "$BASH_UNDER_TEST" "$AC/bin/autonomy" continue set "x"
  run bash -c "printf '%s' '$in' | AUTONOMY_CORE_CONTINUE=off '$BASH_UNDER_TEST' '$AC/hooks/continue.sh'"; [ -z "$output" ]
}

@test "completion gate: blocks done over dirt or unpushed commits; silent on negation, clean or non-git" {
  install_core; [ "$status" -eq 0 ]
  local r="$BATS_TEST_TMPDIR/r" gate="$AC/hooks/completion-gate.sh"
  mkrepo "$r"
  run bash -c "printf '%s' '$(stop_json "$r" "All done.")' | '$BASH_UNDER_TEST' '$gate'"; [ -z "$output" ]      # clean
  echo b > "$r/f"
  run bash -c "printf '%s' '$(stop_json "$r" "Not done yet, tests next.")' | '$BASH_UNDER_TEST' '$gate'"; [ -z "$output" ]
  run bash -c "printf '%s' '$(stop_json "$r" "Refactor landed ✅")' | '$BASH_UNDER_TEST' '$gate'"
  [[ "$output" == *'"decision":"block"'*"1 tracked file(s) with uncommitted changes"* ]]
  run bash -c "printf '%s' '$(stop_json "$r" "Refactor landed ✅")' | '$BASH_UNDER_TEST' '$gate'"; [ -z "$output" ]  # same state
  run bash -c "printf '%s' '$(stop_json "$r" "Refactor landed ✅" s2)' | '$BASH_UNDER_TEST' '$gate'"; [[ "$output" == *block* ]]  # other session
  # unpushed: a clone that is one commit ahead of its upstream
  git clone -q "$r" "$BATS_TEST_TMPDIR/c"; git -C "$r" checkout -q -- f
  git -C "$BATS_TEST_TMPDIR/c" config user.email t@example.invalid; git -C "$BATS_TEST_TMPDIR/c" config user.name t
  echo c > "$BATS_TEST_TMPDIR/c/g"; git -C "$BATS_TEST_TMPDIR/c" add g; git -C "$BATS_TEST_TMPDIR/c" commit -qm two
  run bash -c "printf '%s' '$(stop_json "$BATS_TEST_TMPDIR/c" "Work is complete.")' | '$BASH_UNDER_TEST' '$gate'"
  [[ "$output" == *"1 commit(s) not pushed to origin/"* ]]
  mkdir -p "$BATS_TEST_TMPDIR/plain"
  run bash -c "printf '%s' '$(stop_json "$BATS_TEST_TMPDIR/plain" "All done.")' | '$BASH_UNDER_TEST' '$gate'"; [ -z "$output" ]
  run bash -c "printf '{\"cwd\":\"%s\"}' '$r' | '$BASH_UNDER_TEST' '$gate'"; [ -z "$output" ]   # no message field
}

@test "backup before write: every replaced file is kept, same-second copies included, restore takes the newest" {
  install_core; [ "$status" -eq 0 ]
  local f="$BATS_TEST_TMPDIR/plan.md" in
  in="$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$f")"
  run bash -c "printf '%s' '$in' | '$BASH_UNDER_TEST' '$AC/hooks/backup-before-write.sh'"; [ "$status" -eq 0 ]   # new file: nothing to keep
  [ -z "$(find "$AC/backups" -type f)" ]
  echo v1 > "$f"; printf '%s' "$in" | "$BASH_UNDER_TEST" "$AC/hooks/backup-before-write.sh"
  echo v2 > "$f"; printf '%s' "$in" | "$BASH_UNDER_TEST" "$AC/hooks/backup-before-write.sh"
  echo v3 > "$f"
  [ "$(find "$AC/backups" -type f | wc -l | tr -d ' ')" -eq 2 ]
  run "$BASH_UNDER_TEST" "$AC/bin/autonomy" restore "$f"; [ "$status" -eq 0 ]
  [ "$(cat "$f")" = v2 ]
  # the restore kept v3 as well, so it can be undone
  run "$BASH_UNDER_TEST" "$AC/bin/autonomy" restore "$f" --list
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -eq 3 ]
}

@test "ledger rungs come from git: 🔧 dirty, 📦 unpushed, ✅ clean and pushed, — outside git" {
  install_core; [ "$status" -eq 0 ]
  local L="$AC/bin/autonomy"
  mkrepo "$BATS_TEST_TMPDIR/o"; git clone -q "$BATS_TEST_TMPDIR/o" "$BATS_TEST_TMPDIR/c"; cd "$BATS_TEST_TMPDIR/c"
  git config user.email t@example.invalid; git config user.name t
  run "$BASH_UNDER_TEST" "$L" ledger; [[ "${lines[0]}" == "READOUT=✅ Complete — clean and pushed to origin/"* ]]
  echo x > new; run "$BASH_UNDER_TEST" "$L" ledger; [[ "${lines[0]}" == "READOUT=🔧 Loose ends — 1 uncommitted change(s) (0 tracked, 1 untracked)" ]]
  git add new; git commit -qm n; run "$BASH_UNDER_TEST" "$L" ledger; [[ "${lines[0]}" == "READOUT=📦 Committed, not pushed — 1 commit(s)"* ]]
  cd "$BATS_TEST_TMPDIR"; run "$BASH_UNDER_TEST" "$L" ledger; [[ "${lines[0]}" == "READOUT=— Not a git repository"* ]]
}

@test "--verify re-runs the self-checks without changing anything" {
  install_core; [ "$status" -eq 0 ]
  cp "$CFG/settings.json" "$BATS_TEST_TMPDIR/s"
  install_core --verify; [ "$status" -eq 0 ]
  [[ "$output" == *READY* ]]
  cmp -s "$CFG/settings.json" "$BATS_TEST_TMPDIR/s"
  rm "$AC/hooks/continue.sh"
  install_core --verify; [ "$status" -eq 1 ]
  [[ "$output" == *"NOT READY"* ]]
}

@test "the core ships nothing fleet-only or macOS-only" {
  run grep -nE 'launchctl|osascript|kitty|it2 |cc-notify|cc-backlog|cc-decide|mailbox|accounts\.json|\.claude-(next|secondary|tertiary|quaternary)|sed -i|readlink -f|stat -[fc]|date -[jd]' \
    "$REPO"/core/hooks/*.sh "$REPO/core/bin/autonomy"
  [ "$status" -eq 1 ]
}
