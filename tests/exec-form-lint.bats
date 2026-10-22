#!/usr/bin/env bats
# exec-form-lint — rule R2 (scripts/exec-form-lint.sh + scripts/exec-form-lint.py): our shell code may
# not run a tracked #! file BY PATH more often than config/exec-form-baseline.tsv grants a file.
#
# Why: macOS 15.8.1 keeps ~1.1 KiB of kernel memory per by-path #! exec until reboot
# (docs/plans/KALLOC_TRIGGER_ELIMINATION_2026-10-22.md W4); scripts/lib/cc-run.sh is the cure.
# Each case builds a throwaway repo: a tracked +x #! tool, a caller, a baseline. Fixture shebangs are
# spelled "${SB}" so this file is never an inline stub write (rule R4) and never a subject itself.
# Assertions use the explicit `|| { …; false; }` form: a non-final `[[ ]]` is errexit-EXEMPT under bats.

# shellcheck disable=SC2016  # caller fixtures are shell text, written literally

SB='#!'

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  LINT="$REPO/scripts/exec-form-lint.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  R="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$R/bin" "$R/scripts" "$R/config"
  git -C "$R" init -q
  printf '# fixture baseline\n' > "$R/config/exec-form-baseline.tsv"
  _put bin/tool "${SB}/bin/bash" 'echo tool'
  chmod 755 "$R/bin/tool"
  _put scripts/helper.sh "${SB}/usr/bin/env bash" 'echo helper'
  chmod 755 "$R/scripts/helper.sh"
  git -C "$R" add -A
  unset EXEC_FORM_LINT_BASELINE
}

_put() {
  local p="$1"; shift
  mkdir -p "$(dirname "$R/$p")"
  printf '%s\n' "$@" > "$R/$p"
  git -C "$R" add -- "$p"
}
_base() { printf '%s\t%s\n' "$1" "$2" >> "$R/config/exec-form-baseline.tsv"; }
_lint() { run env EXEC_FORM_LINT_ROOT="$R" /bin/bash "$LINT" "$@"; }
# _caller <line>…: scripts/caller.sh with a shebang and the given lines.
_caller() { _put scripts/caller.sh "${SB}/bin/bash" "$@"; }
_red() { # <n>
  [ "$status" -eq 1 ] || { echo "expected rc 1, got $status:"; echo "$output"; false; }
  [[ "$output" == *"scripts/caller.sh: $1 by-path #! run(s), baseline 0"* ]] || { echo "want $1:"; echo "$output"; false; }
}
_green() { [ "$status" -eq 0 ] || { echo "expected rc 0, got $status:"; echo "$output"; false; }; }

@test "the real tree passes against the committed baseline — a ratchet that ships standing-red is rot" {
  run /bin/bash "$LINT"
  _green
}

@test "--selftest discriminates (exit 0)" {
  run /bin/bash "$LINT" --selftest
  _green
}

@test "RED: a literal path, a seam variable and a resolve_bin result are each one finding, lines named" {
  _caller '"$HOME/.claude/bin/tool" a' \
          'T="${CC_TOOL_BIN:-$HOME/.claude/bin/tool}"' 'out="$("$T" b)"' \
          'H="$(resolve_bin "${CC_H_BIN:-}" helper.sh)"' 'if "$H"; then :; fi'
  _lint
  _red 3
  [[ "$output" == *"2:\$HOME/.claude/bin/tool"* && "$output" == *"4:\$T"* && "$output" == *"6:\$H"* ]] || { echo "$output"; false; }
}

@test "RED: every relay the rule names is seen through, one finding each" {
  _caller 'exec "$HOME/.claude/bin/tool"' \
          'timeout -k 5 10 "$HOME/.claude/bin/tool"' \
          'gtimeout -s INT 3s "$HOME/.claude/bin/tool"' \
          'nohup "$HOME/.claude/bin/tool" &' \
          'taskpolicy -c utility "$HOME/.claude/bin/tool"' \
          'env -u X A=1 "$HOME/.claude/bin/tool"' \
          'printf x | xargs -n 1 "$HOME/.claude/bin/tool"' \
          'find . -name y -exec "$HOME/.claude/scripts/helper.sh" {} +'
  _lint
  _red 8
}

@test "RED: a beside-script path, a relative repo path and a local *bounded relay" {
  _caller '"$(dirname "$0")/helper.sh" x' 'scripts/helper.sh y' \
          'my_bounded() { timeout "$@"; }' 'my_bounded 5 "$HOME/.claude/bin/tool"'
  _lint
  _red 3
}

@test "GREEN: interpreter-led runs, cc_run/cc_argv, and words that are not commands" {
  _caller '/bin/bash "$HOME/.claude/bin/tool" a' 'cc_run "$HOME/.claude/bin/tool" a' \
          'T="$HOME/.claude/bin/tool"' 'cc_argv "$T"; timeout 5 "${CC_ARGV[@]}" a' \
          '/usr/bin/env bash "$T"' '[ -x "$T" ] && command -v "$T"' 'echo "$T" "$HOME/.claude/bin/tool"' \
          'case "$T" in bin/tool) echo ;; */helper.sh|x) : ;; esac' \
          'for f in "$HOME/.claude/bin/tool" "$T"; do :; done' '[[ -n "$T" && "$T" == x ]]' \
          'declare -a A=( "$HOME/.claude/bin/tool" )' '# "$HOME/.claude/bin/tool" in a comment' \
          'cat <<EOF' '"$HOME/.claude/bin/tool"' 'EOF' 'tool by-name' \
          'safe_bounded() { cc_argv "$1"; shift; timeout 5 "${CC_ARGV[@]}" "$@"; }' 'safe_bounded "$T"'
  _lint
  _green
}

@test "GREEN: a #! file that is not +x, a non-#! file, and a test file are out of the rule's scope" {
  _put bin/noexec "${SB}/bin/sh" ':'
  _put bin/data 'just data'
  chmod 755 "$R/bin/data"
  _caller '"$HOME/.claude/bin/noexec"' '"$HOME/.claude/bin/data"'
  _put tests/t.bats "${SB}/usr/bin/env bats" '"$HOME/.claude/bin/tool"'
  _lint
  _green
}

@test "RATCHET: a file at its ceiling passes, one over is red, --files judges only what it is given" {
  _caller '"$HOME/.claude/bin/tool"' '"$HOME/.claude/bin/tool"'
  _base scripts/caller.sh 2
  _lint
  _green
  _caller '"$HOME/.claude/bin/tool"' '"$HOME/.claude/bin/tool"' '"$HOME/.claude/bin/tool"'
  _lint
  [ "$status" -eq 1 ] && [[ "$output" == *"3 by-path #! run(s), baseline 2"* ]] || { echo "$output"; false; }
  _put scripts/other.sh "${SB}/bin/bash" ':'
  _lint --files scripts/other.sh
  _green
}

@test "RATCHET: --write-baseline records today's counts, and a decrease is announced" {
  _caller '"$HOME/.claude/bin/tool"' '"$HOME/.claude/bin/tool"'
  _lint --write-baseline
  _green
  grep -qxF "scripts/caller.sh	2" "$R/config/exec-form-baseline.tsv" || { cat "$R/config/exec-form-baseline.tsv"; false; }
  _caller 'cc_run "$HOME/.claude/bin/tool"' '"$HOME/.claude/bin/tool"'
  _lint
  _green
  [[ "$output" == *"1 file(s) now below baseline"* ]] || { echo "$output"; false; }
}

@test "NO VERDICT: an unreadable baseline exits 2, never a pass" {
  _caller ':'
  run env EXEC_FORM_LINT_ROOT="$R" EXEC_FORM_LINT_BASELINE="$R/nope.tsv" /bin/bash "$LINT"
  [ "$status" -eq 2 ] || { echo "got $status: $output"; false; }
}
