#!/usr/bin/env bats
# qos-rewrite-forks.bats — the process budget of hooks/qos-rewrite.sh on a simple command, and proof
# that cutting it changed nothing the hook prints or how it exits.
#
# Two trims (docs/plans LOAD W4, X13): the table walk started one `grep -qE` per row on every simple
# command, and a miss — nearly every call — ran them all; one union grep now decides the miss. The
# checkout resolution started dirname(1) once per symlink hop and once more after; it is now a
# parameter expansion.
#
# Parity is against the REAL pre-change hook, rebuilt from git (stop-hook-forks-helpers.bash), and
# both arms run through a symlink so the symlink walk itself is exercised. Every table and binary is
# pinned by seam, so the two arms see identical inputs. Assertions are simple commands only.

load stop-hook-forks-helpers
SHF_BASE=55d01fcd4fca631650df1dbae16e91cfa30821c5

setup_file() {
  STUB="$BATS_FILE_TMPDIR/stub"
  shf_build_stubs "$STUB"
  export STUB
}

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  OLD="$BATS_TEST_TMPDIR/old"
  shf_old_tree "$OLD" "$REPO" hooks/qos-rewrite.sh \
    || skip "the pre-change commit $SHF_BASE is not in this clone"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"     # no cc-bats ⇒ transform (a) off
  export SHF_OUT_DIR="$BATS_TEST_TMPDIR/out"; mkdir -p "$SHF_OUT_DIR"
  mkdir -p "$BATS_TEST_TMPDIR/lnk-old" "$BATS_TEST_TMPDIR/lnk-new" "$BATS_TEST_TMPDIR/bin"
  ln -s "$OLD/hooks/qos-rewrite.sh" "$BATS_TEST_TMPDIR/lnk-old/qos-rewrite.sh"
  ln -s "$REPO/hooks/qos-rewrite.sh" "$BATS_TEST_TMPDIR/lnk-new/qos-rewrite.sh"
  cp "$REPO/config/qos-batch.patterns" "$BATS_TEST_TMPDIR/batch.patterns"
  cp "$REPO/config/qos-bound.patterns" "$BATS_TEST_TMPDIR/bound.patterns"
  printf '#!/bin/sh\nexit 0\n' > "$BATS_TEST_TMPDIR/bin/cc-cpubound"
  printf '#!/bin/sh\nexit 0\n' > "$BATS_TEST_TMPDIR/bin/taskpolicy"
  chmod +x "$BATS_TEST_TMPDIR/bin/"*
  export CC_QOS_PATTERNS="$BATS_TEST_TMPDIR/batch.patterns"
  export CC_QOS_BOUND_PATTERNS="$BATS_TEST_TMPDIR/bound.patterns"
  export CC_QOS_CPUBOUND="$BATS_TEST_TMPDIR/bin/cc-cpubound"
  export CC_QOS_TASKPOLICY="$BATS_TEST_TMPDIR/bin/taskpolicy"
  unset CC_QOS_REWRITE CC_QOS_CC_BATS
}

# pair <label> <command> — run the old and the new hook on one payload; stdout, stderr and rc equal.
pair() {
  local p rco=0 rcn=0
  p=$(jq -cn --arg c "$2" '{tool_name:"Bash",tool_input:{command:$c}}')
  printf '%s' "$p" | shf_run "$1.old" "$BATS_TEST_TMPDIR/lnk-old/qos-rewrite.sh" || rco=$?
  printf '%s' "$p" | shf_run "$1.new" "$BATS_TEST_TMPDIR/lnk-new/qos-rewrite.sh" || rcn=$?
  [ "$rco" = "$rcn" ]
  cmp "$SHF_OUT_DIR/$1.old.out" "$SHF_OUT_DIR/$1.new.out"
  cmp "$SHF_OUT_DIR/$1.old.err" "$SHF_OUT_DIR/$1.new.err"
}

# fewer <label> <name> — the new arm started <name> strictly fewer times than the old one.
fewer() {
  local o n
  o=$(shf_calls "$1.old" "$2"); n=$(shf_calls "$1.new" "$2")
  echo "$1 $2: old=$o new=$n (old: $(shf_census "$1.old"); new: $(shf_census "$1.new"))"
  [ "$n" -lt "$o" ]
}

@test "a simple command that matches no row: same silence, one grep for the tables, no dirname" {
  pair miss 'ls -la /tmp'
  [ ! -s "$SHF_OUT_DIR/miss.new.out" ]
  fewer miss grep
  fewer miss dirname
  [ "$(shf_calls miss.new dirname)" -eq 0 ]
  [ "$(shf_total miss.new)" -lt "$(shf_total miss.old)" ]
}

@test "a bound-table hit: the same cc-cpubound prefix" {
  pair bound 'grep -rn needle /tmp'
  grep -q 'cc-cpubound 60 grep -rn needle /tmp' "$SHF_OUT_DIR/bound.new.out"
  fewer bound dirname
}

@test "a batch-table hit: the same taskpolicy prefix, and the bound miss is one grep" {
  pair batch 'pytest -q tests'
  grep -q 'taskpolicy -c utility pytest -q tests' "$SHF_OUT_DIR/batch.new.out"
  fewer batch grep
}

@test "an invalid ERE row still lets a later valid row match (the union's rc 2 falls through)" {
  printf 'utility\t(unclosed\nutility\tpytest\n' > "$CC_QOS_PATTERNS"
  pair badere 'pytest -x'
  grep -q 'taskpolicy -c utility pytest -x' "$SHF_OUT_DIR/badere.new.out"
}

@test "a row starting with a dash keeps the walk's own reading of it" {
  printf 'utility\t-efoo\n' > "$CC_QOS_PATTERNS"
  pair dash 'echo foo'
  pair dash2 'echo bar'
}

@test "a command over 64 KB: a miss and a hit both match the old hook" {
  local big
  big=$(printf 'a%.0s' $(seq 1 70000))
  pair bigmiss "echo $big"
  [ ! -s "$SHF_OUT_DIR/bigmiss.new.out" ]
  fewer bigmiss grep
  pair bighit "pytest $big"
  grep -q 'taskpolicy -c utility pytest' "$SHF_OUT_DIR/bighit.new.out"
}

@test "compound and assignment commands: unchanged early exits" {
  pair compound 'ls | head -1'
  [ ! -s "$SHF_OUT_DIR/compound.new.out" ]
  pair assign 'FOO=1 pytest'
  [ ! -s "$SHF_OUT_DIR/assign.new.out" ]
}

@test "a CRLF table with comments and a TAB-less row parses the same" {
  printf '# c\r\n\r\nnotab\r\nutility\tshellcheck\r\n' > "$CC_QOS_PATTERNS"
  pair crlf 'shellcheck x.sh'
  grep -q 'taskpolicy -c utility shellcheck x.sh' "$SHF_OUT_DIR/crlf.new.out"
  pair crlfmiss 'ls'
}
