#!/usr/bin/env bats
# cc-close-attrib — autoMemoryDirectory real-path injection (2026-09-24).
#
# On the symlinked accounts the auto-memory dir is reached through a symlink into ~/.claude/projects,
# and CC prompts (un-approvably, safetyCheck) on every memory write. The wrapper therefore passes
# --settings={"autoMemoryDirectory":"<real path>"} — merged into any existing --settings, never a
# second flag. These tests assert the argv the stub binary actually RECEIVES.
# Lesson: docs/lessons/symlinked-auto-memory-dir-prompts-on-every-write.md

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  WRAP="$REPO/bin/cc-close-attrib"
  export CC_CLOSE_RECORDS_DIR="$BATS_TEST_TMPDIR/close-records"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  unset CC_MEMDIR_REALPATH CC_CLOSE_ATTRIB_DISABLED
  # Physical tmp path: macOS /var → /private/var would otherwise make EVERY path "symlinked".
  T="$(cd -P "$BATS_TEST_TMPDIR" && pwd -P)"
  CANON="$T/canon/projects"            # the ~/.claude/projects stand-in
  mkdir -p "$CANON"
  ARGS="$T/argv"
  STUB="$T/stub"
  # shellcheck disable=SC2016  # the stub's body is literal text; it expands when the STUB runs
  { printf '#!/bin/bash\n[[ "$1" == "--version" ]] && { echo "stub 9.9.9"; exit 0; }\n'
    printf ': > %q\nfor a in "$@"; do printf "%%s\\n" "$a" >> %q; done\n' "$ARGS" "$ARGS"
  } > "$STUB"
  chmod +x "$STUB"
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
}

mkrepo() { mkdir -p "$1" && git -C "$1" init -q && git -C "$1" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init; }
slug_of() { printf '%s' "$1" | LC_ALL=C sed 's/[^a-zA-Z0-9]/-/g'; }

# account whose WHOLE projects/ dir is a symlink (the .claude-next shape)
acct_whole() { mkdir -p "$T/acct-whole"; ln -s "$CANON" "$T/acct-whole/projects"; echo "$T/acct-whole"; }
# account whose per-project memory/ is a symlink (the -secondary/-tertiary/-quaternary shape)
acct_per_memory() { # $1=slug
  mkdir -p "$T/acct-per/projects/$1" "$CANON/$1/memory"
  ln -s "$CANON/$1/memory" "$T/acct-per/projects/$1/memory"
  echo "$T/acct-per"
}

run_wrap() { # $1=cwd  $2..=argv for the stub
  local cwd="$1"; shift
  run bash -c 'cd "$1" && shift && exec "$@"' _ "$cwd" "${WRAP_BASH:-bash}" "$WRAP" "$STUB" "$@"
}

@test "whole-projects symlink: --settings with the REAL memory path is prepended" {
  mkrepo "$T/r1"
  local s; s="$(slug_of "$T/r1")"
  CLAUDE_CONFIG_DIR="$(acct_whole)" run_wrap "$T/r1" --permission-mode auto
  [ "$status" -eq 0 ]
  [ "$(sed -n 1p "$ARGS")" = "--settings={\"autoMemoryDirectory\":\"$CANON/$s/memory\"}" ]
  [ "$(sed -n 2p "$ARGS")" = "--permission-mode" ]
  [ "$(sed -n 3p "$ARGS")" = "auto" ]
  [ "$(wc -l < "$ARGS" | tr -d ' ')" = 3 ]
}

@test "per-memory symlink: injects the resolved target" {
  mkrepo "$T/r2"
  local s; s="$(slug_of "$T/r2")"
  CLAUDE_CONFIG_DIR="$(acct_per_memory "$s")" run_wrap "$T/r2" -p hi
  [ "$status" -eq 0 ]
  [ "$(sed -n 1p "$ARGS")" = "--settings={\"autoMemoryDirectory\":\"$CANON/$s/memory\"}" ]
  [ "$(sed -n 2p "$ARGS")" = "-p" ]
}

@test "linked worktree subdir: slug is the MAIN checkout root" {
  mkrepo "$T/main"
  git -C "$T/main" worktree add -q "$T/wt" -b feat
  mkdir -p "$T/wt/sub"
  local s; s="$(slug_of "$T/main")"
  CLAUDE_CONFIG_DIR="$(acct_whole)" run_wrap "$T/wt/sub" x
  [ "$status" -eq 0 ]
  [ "$(sed -n 1p "$ARGS")" = "--settings={\"autoMemoryDirectory\":\"$CANON/$s/memory\"}" ]
}

@test "non-git dir: slug is the cwd" {
  mkdir -p "$T/plain"
  local s; s="$(slug_of "$T/plain")"
  CLAUDE_CONFIG_DIR="$(acct_whole)" GIT_CEILING_DIRECTORIES="$T" run_wrap "$T/plain" x
  [ "$status" -eq 0 ]
  [ "$(sed -n 1p "$ARGS")" = "--settings={\"autoMemoryDirectory\":\"$CANON/$s/memory\"}" ]
}

@test "no symlink on the path: argv untouched" {
  mkrepo "$T/r3"
  mkdir -p "$T/acct-real/projects"
  CLAUDE_CONFIG_DIR="$T/acct-real" run_wrap "$T/r3" --permission-mode auto
  [ "$status" -eq 0 ]
  [ "$(cat "$ARGS")" = "$(printf -- '--permission-mode\nauto')" ]
}

@test "CLAUDE_CONFIG_DIR unset: argv untouched" {
  mkrepo "$T/r4"
  unset CLAUDE_CONFIG_DIR
  run_wrap "$T/r4" a b
  [ "$status" -eq 0 ]
  [ "$(cat "$ARGS")" = "$(printf 'a\nb')" ]
}

@test "existing --settings=<file> is merged: both keys present, still ONE --settings" {
  mkrepo "$T/r5"
  local s; s="$(slug_of "$T/r5")"
  printf '{"disabledMcpjsonServers":["x"]}\n' > "$T/dec.json"
  CLAUDE_CONFIG_DIR="$(acct_whole)" run_wrap "$T/r5" --model m "--settings=$T/dec.json" q
  [ "$status" -eq 0 ]
  [ "$(grep -c -- '--settings' "$ARGS")" = 1 ]
  local v; v="$(sed -n 3p "$ARGS")"
  v="${v#--settings=}"
  [ "$(printf '%s' "$v" | jq -r .autoMemoryDirectory)" = "$CANON/$s/memory" ]
  [ "$(printf '%s' "$v" | jq -r '.disabledMcpjsonServers[0]')" = "x" ]
  [ "$(sed -n 4p "$ARGS")" = "q" ]
}

@test "existing --settings '<json>' (space form) is merged in place" {
  mkrepo "$T/r6"
  local s; s="$(slug_of "$T/r6")"
  CLAUDE_CONFIG_DIR="$(acct_whole)" run_wrap "$T/r6" --settings ' { "a": 1 }' q
  [ "$status" -eq 0 ]
  [ "$(sed -n 1p "$ARGS")" = "--settings" ]
  local v; v="$(sed -n 2p "$ARGS")"
  [ "$(printf '%s' "$v" | jq -r .autoMemoryDirectory)" = "$CANON/$s/memory" ]
  [ "$(printf '%s' "$v" | jq -r .a)" = 1 ]
  [ "$(wc -l < "$ARGS" | tr -d ' ')" = 3 ]
}

@test "existing empty '{}' settings literal merges to a valid object" {
  mkrepo "$T/r7"
  local s; s="$(slug_of "$T/r7")"
  CLAUDE_CONFIG_DIR="$(acct_whole)" run_wrap "$T/r7" '--settings={}'
  [ "$status" -eq 0 ]
  [ "$(sed -n 1p "$ARGS")" = "--settings={\"autoMemoryDirectory\":\"$CANON/$s/memory\"}" ]
}

@test "argv already sets autoMemoryDirectory: untouched" {
  mkrepo "$T/r8"
  CLAUDE_CONFIG_DIR="$(acct_whole)" run_wrap "$T/r8" '--settings={"autoMemoryDirectory":"/elsewhere"}'
  [ "$status" -eq 0 ]
  [ "$(cat "$ARGS")" = '--settings={"autoMemoryDirectory":"/elsewhere"}' ]
}

@test "unreadable --settings file: fail open, argv untouched" {
  mkrepo "$T/r9"
  CLAUDE_CONFIG_DIR="$(acct_whole)" run_wrap "$T/r9" "--settings=$T/missing.json"
  [ "$status" -eq 0 ]
  [ "$(cat "$ARGS")" = "--settings=$T/missing.json" ]
}

@test "slug over 200 chars: skipped (CC hashes it)" {
  local long
  long="$T/$(printf 'd%.0s' $(seq 1 210))"
  mkrepo "$long"
  CLAUDE_CONFIG_DIR="$(acct_whole)" run_wrap "$long" x
  [ "$status" -eq 0 ]
  [ "$(cat "$ARGS")" = "x" ]
}

@test "kill switch CC_MEMDIR_REALPATH=off: argv untouched" {
  mkrepo "$T/r10"
  CLAUDE_CONFIG_DIR="$(acct_whole)" CC_MEMDIR_REALPATH=off run_wrap "$T/r10" x
  [ "$status" -eq 0 ]
  [ "$(cat "$ARGS")" = "x" ]
}

@test "injection also rides the CC_CLOSE_ATTRIB_DISABLED plain-exec path" {
  mkrepo "$T/r11"
  local s; s="$(slug_of "$T/r11")"
  CLAUDE_CONFIG_DIR="$(acct_whole)" CC_CLOSE_ATTRIB_DISABLED=1 run_wrap "$T/r11" x
  [ "$status" -eq 0 ]
  [ "$(sed -n 1p "$ARGS")" = "--settings={\"autoMemoryDirectory\":\"$CANON/$s/memory\"}" ]
}

@test "close-record argv still records the ORIGINAL args" {
  mkrepo "$T/r12"
  CLAUDE_CONFIG_DIR="$(acct_whole)" run_wrap "$T/r12" alpha beta
  [ "$status" -eq 0 ]
  # shellcheck disable=SC2012  # sandboxed dir, wrapper-controlled names
  grep -q ',"alpha","beta"\]' "$(ls -1t "$CC_CLOSE_RECORDS_DIR"/*.json | head -1)"
}

@test "bash 3.2 (the launchd resolution of env bash): same injection" {
  [ -x /bin/bash ] || skip "no /bin/bash"
  mkrepo "$T/r13"
  local s; s="$(slug_of "$T/r13")"
  printf '{"k":2}' > "$T/d13.json"
  CLAUDE_CONFIG_DIR="$(acct_whole)" WRAP_BASH=/bin/bash run_wrap "$T/r13" "--settings=$T/d13.json" x
  [ "$status" -eq 0 ]
  [ "$(sed -n 1p "$ARGS")" = "--settings={\"autoMemoryDirectory\":\"$CANON/$s/memory\",\"k\":2}" ]
}
