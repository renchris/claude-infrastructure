#!/usr/bin/env bats
# shellcheck disable=SC2016  # script bodies and bash -c strings carry literal $ on purpose
# cc-shim — the compiled #! launcher (tools/cc-shim/cc-shim.c; docs/research/kalloc-longterm-2026-10-21/shim.md §3).
# Differential: each case writes ONE script at $R/<name> (the .stub-real dir) and runs it twice —
# BY PATH, so the kernel parses its #! line, and as $S/<name>, a symlink to the shim, which must parse
# it the same way. The script path T is the same string on both routes, so rc and output (argv as the
# body or a printf interpreter prints it) must match byte for byte, CR and empty words included.
# Where the shim deliberately differs from the kernel route, the test asserts the shim's documented
# behaviour and says why.
#
# LEAK BUDGET: every by-path #! exec retains ~1 KiB of kernel memory until reboot on macOS 15, so
# kernel runs here are counted: ~17 per file run. Keep it under 30; shim-route runs cost nothing.
#
# Hermetic: the shim is built once in setup_file into $BATS_FILE_TMPDIR (CC_SHIM_CACHE/CC_SHIM_LINK),
# never the live ~/.claude/libexec.

bats_require_minimum_version 1.5.0
setup_file() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export REPO
  export CACHE="$BATS_FILE_TMPDIR/cache" LINK="$BATS_FILE_TMPDIR/libexec/cc-shim"
  CC_SHIM_CACHE="$CACHE" CC_SHIM_LINK="$LINK" /bin/bash "$REPO/tools/cc-shim/build.sh" >"$BATS_FILE_TMPDIR/build.out" 2>&1 || {
    cat "$BATS_FILE_TMPDIR/build.out" >&3
    return 1
  }
}

setup() {
  S="$BATS_TEST_TMPDIR/stub"
  R="$BATS_TEST_TMPDIR/.stub-real"
  mkdir -p "$S" "$R"
}

# mk <name> <mode> <body, printf %b escapes>: write the script at $R/<name>, link $S/<name> → shim.
mk() {
  printf '%b' "$3" >"$R/$1"
  chmod "$2" "$R/$1"
  ln -s "$LINK" "$S/$1"
}

# both <name> [args…]: kernel route then shim route; rc and output must be identical. Leaves the
# shim run in $status/$output for the caller's absolute assertion.
both() {
  local n="$1"
  shift
  run "$R/$n" "$@"
  local ks="$status" ko="$output"
  run "$S/$n" "$@"
  if [ "$status" -ne "$ks" ] || [ "$output" != "$ko" ]; then
    printf 'kernel rc=%s %q\nshim   rc=%s %q\n' "$ks" "$ko" "$status" "$output"
    return 1
  fi
}

# --- shebang forms: the shim reproduces the kernel's argv ---

@test "#!/bin/bash -e: interpreter plus one option, script path, args" {
  mk bash-e 755 '#!/bin/bash -e\necho "[$0] [$*] [$-]"\n'
  both bash-e a 'b c'
  [[ "$output" == "[$R/bash-e] [a b c] ["*e*"]" ]]
}

@test "#!/usr/bin/env bash resolves bash on the caller's PATH" {
  mk env-bash 755 '#!/usr/bin/env bash\necho "[$0] [$*] [$BASH]"\n'
  both env-bash a
  [[ "$output" == "[$R/env-bash] [a] [/"*bash"]" ]]
}

@test "#!/usr/bin/env resolves a name from a test-local PATH dir at run time (binary and #! script)" {
  P="$BATS_TEST_TMPDIR/pathbin"
  mkdir -p "$P"
  ln -s /usr/bin/printf "$P/zzprint"
  printf '#!/bin/sh\necho "zzscript [$*]"\n' >"$P/zzscript"
  chmod 755 "$P/zzscript"
  mk env-local 755 '#!/usr/bin/env zzprint [%s]\n'
  mk env-local-sh 755 '#!/usr/bin/env zzscript\n'
  PATH="$P:$PATH" both env-local a
  [ "$output" = "[$R/env-local][a]" ]
  # A #! tool on PATH takes the env route (exec'ing it from the shim would just be the kernel #! path).
  PATH="$P:$PATH" both env-local-sh a
  [ "$output" = "zzscript [$R/env-local-sh a]" ]
  # The name is looked up per run, not baked in: off PATH, env itself reports it.
  run -127 "$S/env-local" a
  [ "$status" -eq 127 ]
  [[ "$output" == *"zzprint"*"No such file or directory"* ]]
}

@test "multiple words on the #! line become separate argv entries (macOS splits; Linux would not)" {
  mk split 755 '#!/usr/bin/printf [%s] x \t y\n'
  both split a
  [ "$output" = "[x][y][$R/split][a]" ]
}

@test "# ends the #! line, mid-word and as a comment" {
  mk hash 755 '#!/usr/bin/printf [%s] x#y z\n'
  both hash a
  [ "$output" = "[x][$R/hash][a]" ]
  mk hash-comment 755 '#!/bin/bash -e # trailing comment\necho "[$*]"\n'
  both hash-comment a
  [ "$output" = "[a]" ]
}

@test "CRLF: CR is not whitespace, it stays in the last word" {
  mk crlf-arg 755 '#!/usr/bin/printf [%s]\r\n'
  both crlf-arg a
  [ "$output" = "[$R/crlf-arg]"$'\r'"[a]"$'\r' ]
  # With no option word the CR lands in the interpreter name. Kernel route: bash says "bad
  # interpreter", 126. The shim reports the execve errno the shell way: ENOENT → 127.
  mk crlf 755 '#!/bin/sh\r\necho hi\n'
  run -127 "$S/crlf"
  [ "$status" -eq 127 ]
  [ "$output" = "cc-shim: /bin/sh"$'\r'": No such file or directory" ]
}

@test "a NUL inside the #! line truncates there and leaves an empty word, as the kernel does" {
  mk nul 755 '#!/usr/bin/printf [%s] \0 x\n'
  both nul a
  [ "$output" = "[][$R/nul][a]" ]
}

# pad <L>: a #!/bin/sh line of exactly L bytes, newline included (trailing blanks are trimmed).
pad() { printf '#!/bin/sh%*s\\n' $(($1 - 10)) ''; }

@test "#! lines of 511 and 512 bytes run; the EOL must fall inside the first 512 bytes" {
  mk len511 755 "$(pad 511)"'echo "[$0] [$*]"\n'
  mk len512 755 "$(pad 512)"'echo "[$0] [$*]"\n'
  [ "$(head -n1 "$R/len511" | wc -c | tr -d ' ')" -eq 511 ]
  [ "$(head -n1 "$R/len512" | wc -c | tr -d ' ')" -eq 512 ]
  both len511 a
  [ "$output" = "[$R/len511] [a]" ]
  both len512 a
  [ "$output" = "[$R/len512] [a]" ]
}

@test "a 513-byte #! line is refused 126 (DELIBERATE: the kernel says ENOEXEC and bash then runs the file itself)" {
  mk len513 755 "$(pad 513)"'echo "[$0] [$*]"\n'
  [ "$(head -n1 "$R/len513" | wc -c | tr -d ' ')" -eq 513 ]
  run "$R/len513" a
  # bash's ENOEXEC fallback ran the file as a bash script; no #! interpreter was involved.
  [ "$status" -eq 0 ]
  [ "$output" = "[$R/len513] [a]" ]
  run "$S/len513" a
  [ "$status" -eq 126 ]
  [ "$output" = "cc-shim: $R/len513: #! line has no newline in 512 bytes" ]
}

@test "no newline in the file and a bare #! are refused 126 (DELIBERATE, same ENOEXEC reasoning)" {
  mk nonl 755 '#!/bin/sh'
  run "$S/nonl"
  [ "$status" -eq 126 ]
  [ "$output" = "cc-shim: $R/nonl: #! line has no newline in 512 bytes" ]
  mk bare 755 '#!\necho hi\n'
  run "$S/bare"
  [ "$status" -eq 126 ]
  [ "$output" = "cc-shim: $R/bare: #! line names no interpreter" ]
}

# --- non-#! targets ---

@test "a Mach-O target is exec'd directly with the caller's argv" {
  ln -s /bin/echo "$R/macho"
  ln -s "$LINK" "$S/macho"
  both macho a 'b c'
  [ "$output" = "a b c" ]
}

@test "a target with no #! runs under /bin/sh (execvp's ENOEXEC rule)" {
  mk plain 755 'echo "plain [$0] [$*]"\n'
  both plain a
  [ "$output" = "plain [$R/plain] [a]" ]
}

@test "cc-exec explicit mode: cc-exec <script> [args] runs it like the kernel would" {
  mk explicit 755 '#!/bin/bash\necho "[$0] [$*]"\n'
  ln -s "$LINK" "$BATS_TEST_TMPDIR/cc-exec"
  run "$R/explicit" a
  local ko="$output"
  run "$BATS_TEST_TMPDIR/cc-exec" "$R/explicit" a
  [ "$status" -eq 0 ]
  [ "$output" = "$ko" ]
  [ "$output" = "[$R/explicit] [a]" ]
  run "$BATS_TEST_TMPDIR/cc-exec"
  [ "$status" -eq 64 ]
}

# --- failures: rc and the cc-shim: message ---

@test "missing interpreter: 127 (DELIBERATE: bash's kernel route says 126 'bad interpreter'; the shim reports ENOENT the shell way)" {
  mk nointerp 755 '#!/nonexistent/zz9\n'
  run -127 "$S/nointerp"
  [ "$status" -eq 127 ]
  [ "$output" = "cc-shim: /nonexistent/zz9: No such file or directory" ]
}

@test "an interpreter that is itself a #! script is refused 126, as the kernel refuses it" {
  printf '#!/bin/sh\necho inner-ran\n' >"$BATS_TEST_TMPDIR/inner"
  chmod 755 "$BATS_TEST_TMPDIR/inner"
  mk nested 755 "#!$BATS_TEST_TMPDIR/inner\n"
  run "$S/nested"
  [ "$status" -eq 126 ]
  [ "$output" = "cc-shim: $R/nested: interpreter $BATS_TEST_TMPDIR/inner is itself a #! script" ]
}

@test "a target without +x is refused 126, as the kernel refuses it" {
  mk nox 644 '#!/bin/sh\necho hi\n'
  run "$R/nox"
  [ "$status" -eq 126 ]
  run "$S/nox"
  [ "$status" -eq 126 ]
  [ "$output" = "cc-shim: $R/nox: Permission denied" ]
}

@test "a dangling .D-real link and a missing target are 127 'no target'" {
  ln -s "$BATS_TEST_TMPDIR/gone" "$R/dangling"
  ln -s "$LINK" "$S/dangling"
  run -127 "$S/dangling"
  [ "$status" -eq 127 ]
  [ "$output" = "cc-shim: dangling: no target $R/dangling" ]
  ln -s "$LINK" "$S/absent"
  run -127 "$S/absent"
  [ "$status" -eq 127 ]
  [ "$output" = "cc-shim: absent: no target $R/absent" ]
}

# --- process contract ---

@test "16 same-pid hops through a self-re-exec'ing stub, then 126" {
  export HOPLOG="$BATS_TEST_TMPDIR/hops"
  # The body's $0 is the .stub-real path; it re-execs through the STUB so every hop crosses the shim.
  mk loop 755 '#!/bin/bash\necho x >>"$HOPLOG"\nexec "'"$S/loop"'" "$@"\n'
  run "$S/loop"
  [ "$status" -eq 126 ]
  [ "$output" = "cc-shim: exec loop through loop (16 same-pid hops)" ]
  [ "$(wc -l <"$HOPLOG" | tr -d ' ')" -eq 16 ]
}

@test "pid is preserved: the shim execs, it never forks" {
  mk pid 755 '#!/bin/bash\necho "$$"\n'
  run bash -c 'echo "$$"; exec "$1"' _ "$S/pid"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
  [ "${lines[0]}" = "${lines[1]}" ]
}

@test "--selftest passes and --version prints the source hash it was built from" {
  run "$LINK" --selftest
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^cc-shim\ selftest:\ ok\ ([0-9]+)/([0-9]+)$ ]]
  [ "${BASH_REMATCH[1]}" = "${BASH_REMATCH[2]}" ]
  run "$LINK" --version
  [ "$status" -eq 0 ]
  local sha
  sha=$(shasum -a 256 <"$REPO/tools/cc-shim/cc-shim.c")
  [ "$output" = "cc-shim ${sha%% *}" ]
  run "$LINK" --bogus
  [ "$status" -eq 64 ]
}

@test "republishing LINK from a changed source while execs run: zero failures, LINK ends on the new binary" {
  local L2="$BATS_TEST_TMPDIR/libexec/cc-shim" SRC2="$BATS_TEST_TMPDIR/src"
  CC_SHIM_CACHE="$CACHE" CC_SHIM_LINK="$L2" /bin/bash "$REPO/tools/cc-shim/build.sh" >/dev/null 2>&1
  mkdir -p "$SRC2"
  cp "$REPO/tools/cc-shim/build.sh" "$SRC2/build.sh"
  cp "$REPO/tools/cc-shim/cc-shim.c" "$SRC2/cc-shim.c"
  printf '/* rebuild-under-load test: a new hash */\n' >>"$SRC2/cc-shim.c"
  printf '#!/bin/sh\nexit 0\n' >"$R/spin"
  chmod 755 "$R/spin"
  ln -s "$L2" "$S/spin"
  # The loop runs from before the build starts until after it returns, so the publish swap falls
  # inside it by construction, so N is only a floor for a build that finishes instantly. N=300 took
  # 114 s at load ~420 (2026-10-22); the build's own duration supplies the execs that matter.
  local N=50 stop="$BATS_TEST_TMPDIR/stop" started="$BATS_TEST_TMPDIR/started" res="$BATS_TEST_TMPDIR/res"
  (
    i=0 fails=0
    while [ "$i" -lt "$N" ] || [ ! -e "$stop" ]; do
      "$S/spin" || fails=$((fails + 1))
      i=$((i + 1))
      [ "$i" -eq 1 ] && : >"$started"
    done
    echo "$i $fails" >"$res"
  ) >/dev/null 2>&1 3>&- &
  local loop=$! w=0 brc=0
  while [ ! -e "$started" ] && [ "$w" -lt 600 ]; do
    sleep 0.05
    w=$((w + 1))
  done
  # Status captured, not tripped on: the stop file must be written or the loop never ends.
  CC_SHIM_CACHE="$CACHE" CC_SHIM_LINK="$L2" /bin/bash "$SRC2/build.sh" >"$BATS_TEST_TMPDIR/build2.out" 2>&1 || brc=$?
  : >"$stop"
  wait "$loop"
  cat "$BATS_TEST_TMPDIR/build2.out"
  [ "$brc" -eq 0 ]
  read -r runs fails <"$res"
  echo "runs=$runs fails=$fails"
  [ "$runs" -ge "$N" ]
  [ "$fails" -eq 0 ]
  local sha2
  sha2=$(shasum -a 256 <"$SRC2/cc-shim.c")
  [ "$(readlink "$L2")" = "$(cd "$CACHE" && pwd -P)/${sha2:0:16}-$(uname -m)/cc-shim" ]
  run "$L2" --version
  [ "$output" = "cc-shim ${sha2%% *}" ]
}
