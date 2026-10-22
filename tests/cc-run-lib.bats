#!/usr/bin/env bats
# scripts/lib/cc-run.sh (cc_argv / cc_run) and its Python twin scripts/lib/cc_run.py: run a script
# through its own #! interpreter (bin/cc-run, the heartbeat wrapper, is tests/cc-run.bats — unrelated) so the kernel never takes its #! path (macOS 15.8.1 keeps ~1.1 KiB per
# such exec until reboot; docs/plans/KALLOC_TRIGGER_ELIMINATION_2026-10-22.md W4).
#
# Differential where it matters: the argv cases run the file once BY PATH (the kernel parses the #!) and
# once through the runner, and require identical output. `#!/usr/bin/printf …` makes the interpreter
# print its own argv, so a split or ordering difference shows byte for byte. LEAK BUDGET: 6 by-path
# #! execs per run (the differential arm), every other case is kernel-free.
#
# Every case runs under /bin/bash 3.2 (what launchd runs) AND the newest bash on PATH, because the
# library's whole point is to be safe on both.

# shellcheck disable=SC2016  # snippets and subject bodies run in a child shell: single quotes on purpose

setup_file() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export REPO LIB="$REPO/scripts/lib/cc-run.sh" PYLIB="$REPO/scripts/lib"
  NEWBASH=""
  for b in /opt/homebrew/bin/bash /usr/local/bin/bash; do [ -x "$b" ] && { NEWBASH="$b"; break; }; done
  export NEWBASH
}

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"   # hermetic: never the live ~/
  R="$BATS_TEST_TMPDIR/r"
  mkdir -p "$R"
}

# mk <name> <mode> <body, printf %b escapes>: a subject file (data, not a PATH stub).
mk() { printf '%b' "$3" >"$R/$1"; chmod "$2" "$R/$1"; }

# in_bashes <script>: run the snippet under /bin/bash and NEWBASH with the library sourced; each
# output line is prefixed with the bash's major version so a split between them is visible.
in_bashes() {
  local s="$1" b out all=""
  shift
  for b in /bin/bash ${NEWBASH:+"$NEWBASH"}; do
    out="$("$b" -c '. "$LIB"; '"$s" "$@" 2>&1)" || out="$out [rc=$?]"
    all="$all${all:+$'\n'}$out"
  done
  printf '%s\n' "$all"
}

# argv_of <path>: CC_ARGV as one line per bash, words in [].
argv_of() { in_bashes 'cc_argv "$1"; printf "[%s]" "${CC_ARGV[@]}"; echo' _ "$1" ; }

@test "the two bashes exist: /bin/bash is 3.2 and a newer bash is on this box" {
  run /bin/bash -c 'echo "${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}"'
  [ "$output" = 3.2 ]
  [ -n "$NEWBASH" ] || skip "no Homebrew bash on this box"
  run "$NEWBASH" -c 'echo "${BASH_VERSINFO[0]}"'
  [ "$output" -ge 4 ]
}

@test "differential: the runner's argv equals the kernel's for the #! forms that matter" {
  mk one 755 '#!/usr/bin/printf [%s]\n'
  mk words 755 '#!/usr/bin/printf [%s] x \t y\n'
  mk space 755 '#!  /usr/bin/printf [%s]\n'
  mk trail 755 '#!/usr/bin/printf [%s]   \n'
  local f k b r
  for f in one words space trail; do
    k="$("$R/$f" a 'b c')"                      # by path: the kernel builds the argv
    for b in /bin/bash ${NEWBASH:+"$NEWBASH"}; do
      r="$("$b" -c '. "$LIB"; cc_run "$1" a "b c"' _ "$R/$f")"
      [ "$r" = "$k" ] || { echo "$f under $b: kernel=$k runner=$r"; false; }
    done
  done
}

@test "differential: \$0, BASH_SOURCE and the exit code of an env-bash script match a by-path run" {
  mk env 755 '#!/usr/bin/env bash\necho "[$0] [${BASH_SOURCE[0]}] [$*]"\nexit 7\n'
  local k kr b r rr
  kr=0; k="$("$R/env" x y)" || kr=$?
  [ "$kr" = 7 ]
  for b in /bin/bash ${NEWBASH:+"$NEWBASH"}; do
    rr=0; r="$("$b" -c '. "$LIB"; cc_run "$1" x y' _ "$R/env")" || rr=$?
    [ "$r" = "$k" ] && [ "$rr" = "$kr" ] || { echo "$b: kernel=$k/$kr runner=$r/$rr"; false; }
  done
}

@test "cc_argv: a #! file becomes interpreter + its words + the path" {
  mk env 755 '#!/usr/bin/env bash\n:\n'
  mk shx 755 '#!/bin/sh -x\n:\n'
  run argv_of "$R/env"
  [ "${lines[0]}" = "[/usr/bin/env][bash][$R/env]" ]
  [ -z "$NEWBASH" ] || [ "${lines[1]}" = "[/usr/bin/env][bash][$R/env]" ]
  run argv_of "$R/shx"
  [ "${lines[0]}" = "[/bin/sh][-x][$R/shx]" ]
  [ -z "$NEWBASH" ] || [ "${lines[1]}" = "[/bin/sh][-x][$R/shx]" ]
}

@test "cc_argv passes through, unchanged, everything the kernel would decide itself" {
  mk plain 755 'echo no shebang\n'
  mk noexec 644 '#!/bin/sh\n:\n'
  mk bare 755 '#!\n'
  mk nointerp 755 '#!/nonexistent/interp\n:\n'
  mk crlf 755 '#!/bin/sh\r\n:\n'
  mk inner 755 '#!/bin/sh\n:\n'
  mk outer 755 "#!$R/inner\n:\n"           # interpreter that is itself #!: the kernel refuses it
  local p
  for p in /usr/bin/true "$R/plain" "$R/noexec" "$R/bare" "$R/nointerp" "$R/crlf" "$R/outer" "$R/missing" cc-run-bare-name; do
    run argv_of "$p"
    [ "${lines[0]}" = "[$p]" ] || { echo "$p: $output"; false; }
    [ -z "$NEWBASH" ] || [ "${lines[1]}" = "[$p]" ] || { echo "$p: $output"; false; }
  done
}

@test "cc_run under set -euo pipefail: no args, empty-string args, a failing program, a '#!'-only file" {
  mk env 755 '#!/usr/bin/env bash\necho "n=$# [${1-unset}]"\n'
  mk fail 755 '#!/bin/sh\nexit 3\n'
  printf '#!' >"$R/stub-noeol"; chmod 755 "$R/stub-noeol"
  run in_bashes 'set -euo pipefail; cc_run "$1"; cc_run "$1" ""; rc=0; cc_run "$2" || rc=$?; echo "rc=$rc"; cc_argv "$3"; echo "[${CC_ARGV[*]}]"' \
    _ "$R/env" "$R/fail" "$R/stub-noeol"
  [ "${lines[0]}" = "n=0 [unset]" ]
  [ "${lines[1]}" = "n=1 []" ]
  [ "${lines[2]}" = "rc=3" ]
  [ "${lines[3]}" = "[$R/stub-noeol]" ]
  [ -z "$NEWBASH" ] || [ "${#lines[@]}" = 8 ]
}

@test "cc_argv with exec and a relay: the program replaces the shell and keeps its pid" {
  mk pid 755 '#!/bin/sh\necho "$$"\n'
  run in_bashes 'cc_argv "$1"; echo "$$"; exec /usr/bin/env "${CC_ARGV[@]}"' _ "$R/pid"
  [ "${lines[0]}" = "${lines[1]}" ]
  [ -z "$NEWBASH" ] || [ "${lines[2]}" = "${lines[3]}" ]
}

@test "python twin: cc_argv agrees with the bash runner on every form above" {
  mk env 755 '#!/usr/bin/env bash\n:\n'
  mk shx 755 '#!/bin/sh -x\n:\n'
  mk words 755 '#!/usr/bin/printf [%s] x \t y\n'
  mk plain 755 'echo no shebang\n'
  mk noexec 644 '#!/bin/sh\n:\n'
  mk crlf 755 '#!/bin/sh\r\n:\n'
  mk inner 755 '#!/bin/sh\n:\n'
  mk outer 755 "#!$R/inner\n:\n"
  local p sh py
  for p in "$R/env" "$R/shx" "$R/words" "$R/plain" "$R/noexec" "$R/crlf" "$R/outer" /usr/bin/true bare-name; do
    sh="$(/bin/bash -c '. "$LIB"; cc_argv "$1"; printf "[%s]" "${CC_ARGV[@]}"' _ "$p")"
    py="$(python3 -I -c 'import sys; sys.path.insert(0, sys.argv[1]); from cc_run import cc_argv; print("".join("[%s]" % w for w in cc_argv(sys.argv[2])), end="")' "$PYLIB" "$p")"
    [ "$sh" = "$py" ] || { echo "$p: bash=$sh python=$py"; false; }
  done
}

@test "python twin: cc_run runs the program and returns its exit code" {
  mk env 755 '#!/usr/bin/env bash\necho "[$0] [$*]"\nexit 5\n'
  run python3 -I -c 'import sys; sys.path.insert(0, sys.argv[1]); from cc_run import cc_run
p = cc_run([sys.argv[2], "a b"], capture_output=True, text=True); print(p.stdout, end=""); print(p.returncode)' "$PYLIB" "$R/env"
  [ "${lines[0]}" = "[$R/env] [a b]" ]
  [ "${lines[1]}" = 5 ]
}
