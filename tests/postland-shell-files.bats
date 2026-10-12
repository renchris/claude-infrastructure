#!/usr/bin/env bats
# postland-verify.sh shell_files(): the shebang sniff reads each tracked file's first line with the
# builtin `read`, not `$(head -1 …)` — a subshell plus a head per tracked file was 7.4% of the whole
# box's process spawns in a 30 s exec trace (2026-10-12). The contract under test is that the file
# list is IDENTICAL to the head-based one, including the edge shapes `read` treats differently from
# a command substitution: no trailing newline, an empty file, a NUL byte, CRLF, a binary blob.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$REPO/scripts/postland-verify.sh"
  WT="$BATS_TEST_TMPDIR/wt"
  mkdir -p "$WT/sub"
  git -C "$WT" init -q
  printf 'echo plain\n'                        > "$WT/a.sh"
  printf '#!/bin/bash\necho x\n'               > "$WT/x"
  printf '#!/usr/bin/env bash'                 > "$WT/sub/y"      # no trailing newline
  printf '#!/bin/sh\n'                         > "$WT/z"
  printf '#!/usr/bin/env sh\n'                 > "$WT/w"
  printf '#!/usr/bin/env python3\nprint(1)\n'  > "$WT/p"
  printf '# title\n'                           > "$WT/t.md"
  : > "$WT/e"                                                    # empty
  printf '#!/bin/bash\000\001\002\n'           > "$WT/n"          # NUL byte on the shebang line
  printf '#!/bin/bash\r\necho crlf\r\n'        > "$WT/c"
  printf '\177ELF\002\001\001\000\000'         > "$WT/bin.o"
  git -C "$WT" add -A
}

# The function under test, lifted verbatim from the script (it runs its main on source).
load_new() { eval "$(sed -n '/^shell_files() {/,/^}/p' "$SCRIPT")"; }
# The pre-change body: identical but for the head-based first-line read.
load_old() {
  eval "$(sed -n '/^shell_files() {/,/^}/p' "$SCRIPT" \
    | sed -e '/# Builtin read, not/d' -e '/# 1,173 execs in one 30 s/d' \
          -e 's|first=""; IFS= read -r first < "$WORKTREE/$f" 2>/dev/null \|\| true|first="$(head -1 "$WORKTREE/$f" 2>/dev/null)"|')"
}

@test "shell_files: the builtin read selects exactly what the head-based sniff selected" {
  export WORKTREE="$WT"
  load_old; old="$(shell_files | sort)"
  grep -q 'head -1' <<<"$(declare -f shell_files)" || false     # the control really is the old body
  load_new; new="$(shell_files | sort)"
  ! grep -q 'head -1' <<<"$(declare -f shell_files)" || false
  [ "$old" = "$new" ] || { diff <(echo "$old") <(echo "$new") >&2; false; }
  [ "$new" = "$(printf '%s\n' a.sh c n sub/y w x z | sort)" ] || { echo "$new" >&2; false; }
}

@test "shell_files: no head process is started per file" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/bash\necho x >> "%s"\nexec /usr/bin/head "$@"\n' "$BATS_TEST_TMPDIR/head.log" > "$BATS_TEST_TMPDIR/bin/head"
  chmod +x "$BATS_TEST_TMPDIR/bin/head"
  export WORKTREE="$WT"; load_new
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" shell_files >/dev/null
  [ ! -s "$BATS_TEST_TMPDIR/head.log" ] || { wc -l < "$BATS_TEST_TMPDIR/head.log" >&2; false; }
}
