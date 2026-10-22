#!/usr/bin/env bats
# tests/helpers/cc-stub.bash: `cc_stub DIR NAME BODY` makes a PATH stub that behaves exactly like the
# plain `#!` file it replaces, without the kernel ever taking its `#!` path (macOS 15.x keeps ~1.1 KiB
# per such exec until reboot; docs/research/kalloc-longterm-2026-10-21/REPORT.md §3 Phase 3).
#
# Differential: every behaviour case runs the same body once as a plain stub (CC_SHIM unset, today's
# shape) and once through the shim, and asserts the same stdout, stderr, exit code and argv.
# Hermetic: the shim is built from tools/cc-shim into this file's tmpdir, never the live ~/.claude.

# shellcheck disable=SC2030,SC2031  # each @test is its own subshell; CC_SHIM is set per test on purpose
load helpers/cc-stub

setup_file() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export REPO
  export TEST_SHIM="$BATS_FILE_TMPDIR/libexec/cc-shim"
  if command -v clang >/dev/null 2>&1 || command -v cc >/dev/null 2>&1; then
    CC_SHIM_CACHE="$BATS_FILE_TMPDIR/cache" CC_SHIM_LINK="$TEST_SHIM" \
      /bin/bash "$REPO/tools/cc-shim/build.sh" >"$BATS_FILE_TMPDIR/build.out" 2>&1 || true
  fi
}

setup() {
  unset CC_SHIM CC_SHIM_HOPS
  W="$BATS_TEST_TMPDIR/w"
  mkdir -p "$W"
}

need_shim() {
  if ! command -v clang >/dev/null 2>&1 && ! command -v cc >/dev/null 2>&1; then
    skip "no C compiler: cc_stub's plain fallback is the only mode here"
  fi
  [ -x "$TEST_SHIM" ] || { cat "$BATS_FILE_TMPDIR/build.out" >&2; return 1; }
}

# run_both NAME BODY ARGS… — the same stub through both modes, captured as "<rc>|<stdout>|<stderr>".
run_both() {
  local name="$1" body="$2"
  shift 2
  local rc=0
  CC_SHIM='' cc_stub "$W/plain" "$name" "$body"
  CC_SHIM="$TEST_SHIM" cc_stub "$W/shim" "$name" "$body"
  PATH="$W/plain:$PATH" "$name" "$@" >"$W/p.out" 2>"$W/p.err" </dev/null || rc=$?
  PLAIN="$rc|$(cat "$W/p.out")|$(cat "$W/p.err")"
  rc=0
  PATH="$W/shim:$PATH" "$name" "$@" >"$W/s.out" 2>"$W/s.err" </dev/null || rc=$?
  SHIMMED="$rc|$(cat "$W/s.out")|$(cat "$W/s.err")"
}

@test "without CC_SHIM it writes today's plain #! stub" {
  cc_stub "$W/bin" hello $'#!/bin/bash\necho hi\n'
  [ -f "$W/bin/hello" ]
  [ ! -L "$W/bin/hello" ]
  [ -x "$W/bin/hello" ]
  [ "$(cat "$W/bin/hello")" = $'#!/bin/bash\necho hi' ]
  [ "$(cc_stub_body "$W/bin" hello)" = "$W/bin/hello" ]
  run "$W/bin/hello"
  [ "$status" -eq 0 ]
  [ "$output" = hi ]
}

@test "CC_SHIM set but empty, or not executable, falls back to the plain stub" {
  CC_SHIM='' cc_stub "$W/a" x $'#!/bin/sh\necho a\n'
  [ ! -L "$W/a/x" ]
  CC_SHIM="$W/no-such-shim" cc_stub "$W/b" x $'#!/bin/sh\necho b\n'
  [ ! -L "$W/b/x" ]
  [ ! -e "$W/.b-real" ]
}

@test "with CC_SHIM the name is a link to the shim and the body sits in .D-real" {
  need_shim
  export CC_SHIM="$TEST_SHIM"
  cc_stub "$W/bin" hello $'#!/bin/bash\necho hi "$@"\n'
  [ -L "$W/bin/hello" ]
  [ "$W/bin/hello" -ef "$TEST_SHIM" ]
  [ -x "$W/.bin-real/hello" ]
  [ "$(cc_stub_body "$W/bin" hello)" = "$W/.bin-real/hello" ]
  run env PATH="$W/bin:$PATH" hello a b
  [ "$status" -eq 0 ]
  [ "$output" = "hi a b" ]
}

@test "differential: argv, quoting, stdout, stderr and exit code match the plain stub" {
  need_shim
  # shellcheck disable=SC2016  # the stub's own $@
  run_both argv $'#!/bin/bash\nprintf "<%s>" "$@"; echo; echo err >&2; exit 7\n' 'a b' '' "c'd" '*'
  [ "$PLAIN" = "$SHIMMED" ]
  [ "$PLAIN" = "7|<a b><><c'd><*>|err" ]
}

@test "differential: env interpreter, an -e flag and a body read from stdin" {
  need_shim
  run_both envy $'#!/usr/bin/env bash\necho "bash ${BASH_VERSINFO[0]}"\n'
  [ "$PLAIN" = "$SHIMMED" ]
  run_both strict $'#!/bin/bash -e\nfalse\necho unreachable\n'
  [ "$PLAIN" = "$SHIMMED" ]
  [ "${PLAIN%%|*}" = 1 ]
  CC_SHIM="$TEST_SHIM" cc_stub "$W/in" piped - <<'EOF'
#!/bin/sh
echo "from stdin $1"
EOF
  run env PATH="$W/in:$PATH" piped x
  [ "$output" = "from stdin x" ]
}

@test "stdin passes through to the body" {
  need_shim
  CC_SHIM="$TEST_SHIM" cc_stub "$W/bin" up $'#!/bin/sh\ntr a-z A-Z\n'
  run bash -c 'printf "abc\n" | PATH="$1:$PATH" up' _ "$W/bin"
  [ "$output" = ABC ]
}

@test "the body sees \$0 under .D-real and runs as the same pid" {
  need_shim
  # shellcheck disable=SC2016  # the stub's own $0 and $$
  CC_SHIM="$TEST_SHIM" cc_stub "$W/bin" who $'#!/bin/bash\necho "$0"\n'
  run env PATH="$W/bin:$PATH" who
  [ "$output" = "$W/.bin-real/who" ]
  # exec, never fork: the pid the caller started is the pid the body reports
  CC_SHIM="$TEST_SHIM" cc_stub "$W/bin" pid $'#!/bin/bash\necho $$\n'
  run bash -c '"$1/pid" & echo "$!"; wait' _ "$W/bin"
  [ "${lines[0]}" = "${lines[1]}" ]
}

@test "re-stubbing a name rewrites the body, never the shared shim" {
  need_shim
  local before after
  before="$(/sbin/sha256sum <"$TEST_SHIM")"
  CC_SHIM="$TEST_SHIM" cc_stub "$W/bin" x $'#!/bin/sh\necho one\n'
  CC_SHIM="$TEST_SHIM" cc_stub "$W/bin" x $'#!/bin/sh\necho two\n'
  run env PATH="$W/bin:$PATH" x
  [ "$output" = two ]
  # the classic mistake — a redirect onto the stub — fails on the 0555 shim instead of corrupting it
  run bash -c 'printf "#!/bin/sh\necho clobbered\n" > "$1"' _ "$W/bin/x"
  [ "$status" -ne 0 ]
  after="$(/sbin/sha256sum <"$TEST_SHIM")"
  [ "$before" = "$after" ]
  # a plain stub replaced by a shimmed one (and back) leaves no stale file behind
  CC_SHIM='' cc_stub "$W/bin" x $'#!/bin/sh\necho plain\n'
  [ ! -L "$W/bin/x" ]
  run "$W/bin/x"
  [ "$output" = plain ]
}

@test "a body without a trailing newline gets one; a body with no #! line stays plain" {
  need_shim
  CC_SHIM="$TEST_SHIM" cc_stub "$W/bin" nonl '#!/bin/sh
echo ok'
  [ -L "$W/bin/nonl" ]
  run env PATH="$W/bin:$PATH" nonl
  [ "$output" = ok ]
  CC_SHIM="$TEST_SHIM" cc_stub "$W/bin" noshebang $'echo plain-sh\n'
  [ ! -L "$W/bin/noshebang" ]
}

@test "a #! line the kernel would refuse (512 bytes or more) is written plain, not shimmed" {
  need_shim
  local long
  long="#!/bin/sh $(printf '%*s' 510 '' | tr ' ' x)"
  CC_SHIM="$TEST_SHIM" cc_stub "$W/bin" long "$long"$'\necho x\n'
  [ ! -L "$W/bin/long" ]
}

@test "batch form: bodies in cc_stub_dir, one cc_stub_finish, same behaviour in both modes" {
  local mode d n
  for mode in plain shim; do
    if [ "$mode" = shim ]; then need_shim; export CC_SHIM="$TEST_SHIM"; else unset CC_SHIM; fi
    d="$(cc_stub_dir "$W/$mode")"
    for n in one two three; do
      printf '#!/bin/sh\necho %s "$@"\n' "$n" >"$d/$n"
    done
    cc_stub_finish "$W/$mode"
    run env PATH="$W/$mode:$PATH" two x
    [ "$output" = "two x" ]
  done
  [ ! -L "$W/plain/one" ]
  [ "$W/shim/three" -ef "$TEST_SHIM" ]
  [ "$(cc_stub_body "$W/shim" three)" = "$W/.shim-real/three" ]
}

@test "a relative DIR resolves to the same .D-real the shim reads" {
  need_shim
  cd "$W"
  CC_SHIM="$TEST_SHIM" cc_stub rel r $'#!/bin/sh\necho rel\n'
  [ -x "$W/.rel-real/r" ]
  run ./rel/r
  [ "$output" = rel ]
}
