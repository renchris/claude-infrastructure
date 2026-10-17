#!/usr/bin/env bats
# coldcompile-admit-forks.bats — the process budget of hooks/coldcompile-admit.sh, and proof that
# cutting it changed nothing the hook prints or how it exits.
#
# Two trims (docs/plans LOAD W4, X13): the ignition-table walk started one `grep -qE` per row on
# every compound command, and a miss — nearly every call — ran them all; one union grep now decides
# the miss. The checkout resolution started dirname(1) once per symlink hop and once more after; it is
# now a parameter expansion.
#
# Parity is against the REAL pre-change hook, rebuilt from git (stop-hook-forks-helpers.bash), and
# both arms run through a symlink so the symlink walk itself is exercised. The table and the gate are
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
  shf_old_tree "$OLD" "$REPO" hooks/coldcompile-admit.sh \
    || skip "the pre-change commit $SHF_BASE is not in this clone"
  export SHF_OUT_DIR="$BATS_TEST_TMPDIR/out"; mkdir -p "$SHF_OUT_DIR"
  mkdir -p "$BATS_TEST_TMPDIR/lnk-old" "$BATS_TEST_TMPDIR/lnk-new" "$BATS_TEST_TMPDIR/bin"
  ln -s "$OLD/hooks/coldcompile-admit.sh" "$BATS_TEST_TMPDIR/lnk-old/coldcompile-admit.sh"
  ln -s "$REPO/hooks/coldcompile-admit.sh" "$BATS_TEST_TMPDIR/lnk-new/coldcompile-admit.sh"
  cp "$REPO/config/coldcompile.patterns" "$BATS_TEST_TMPDIR/cold.patterns"
  printf '#!/bin/sh\nexit 0\n' > "$BATS_TEST_TMPDIR/bin/cc-ignition-gate"
  chmod +x "$BATS_TEST_TMPDIR/bin/cc-ignition-gate"
  export CC_COLDCOMPILE_PATTERNS="$BATS_TEST_TMPDIR/cold.patterns"
  export CC_COLDCOMPILE_GATE="$BATS_TEST_TMPDIR/bin/cc-ignition-gate"
  unset CC_COLDCOMPILE_ADMIT
}

# pair <label> <command> — run the old and the new hook on one payload; stdout, stderr and rc equal.
pair() {
  local p rco=0 rcn=0
  p=$(jq -cn --arg c "$2" '{tool_name:"Bash",tool_input:{command:$c}}')
  printf '%s' "$p" | shf_run "$1.old" "$BATS_TEST_TMPDIR/lnk-old/coldcompile-admit.sh" || rco=$?
  printf '%s' "$p" | shf_run "$1.new" "$BATS_TEST_TMPDIR/lnk-new/coldcompile-admit.sh" || rcn=$?
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

@test "a compound command that ignites nothing: same silence, one grep for the table, no dirname" {
  pair miss 'ls -la /tmp | head -3'
  [ ! -s "$SHF_OUT_DIR/miss.new.out" ]
  fewer miss grep
  fewer miss dirname
  [ "$(shf_calls miss.new dirname)" -eq 0 ]
  [ "$(shf_total miss.new)" -lt "$(shf_total miss.old)" ]
}

@test "an igniting compound command: the same gate statement" {
  pair hit 'cd app && (npx next dev -p 3001 &) ; sleep 25'
  grep -q 'cc-ignition-gate --class next-dev ; cd app' "$SHF_OUT_DIR/hit.new.out"
  fewer hit dirname
}

@test "a simple command with a leading assignment: the same gate statement" {
  pair assign 'PW_BASE_URL=http://x pnpm design:gate'
  grep -q 'cc-ignition-gate --class pkg-script ; PW_BASE_URL' "$SHF_OUT_DIR/assign.new.out"
}

@test "an invalid ERE row still lets a later valid row match (the union's rc 2 falls through)" {
  printf 'broken\t(unclosed\nnext-dev\tnext dev\n' > "$CC_COLDCOMPILE_PATTERNS"
  pair badere 'cd app && next dev'
  grep -q 'cc-ignition-gate --class next-dev' "$SHF_OUT_DIR/badere.new.out"
}

@test "a row starting with a dash keeps the walk's own reading of it" {
  printf 'dash\t-efoo\n' > "$CC_COLDCOMPILE_PATTERNS"
  pair dash 'cd x && echo foo'
  pair dash2 'cd x && echo bar'
}

@test "a command over 64 KB: a miss and a hit both match the old hook" {
  local big
  big=$(printf 'a%.0s' $(seq 1 70000))
  pair bigmiss "cd x && echo $big"
  [ ! -s "$SHF_OUT_DIR/bigmiss.new.out" ]
  fewer bigmiss grep
  pair bighit "cd x && npm run dev $big"
}

@test "bats commands and plain simple commands: unchanged early exits" {
  pair bats 'cd x && bats tests/a.bats'
  [ ! -s "$SHF_OUT_DIR/bats.new.out" ]
  pair simple 'npm run dev'
  [ ! -s "$SHF_OUT_DIR/simple.new.out" ]
}

@test "an empty or comment-only table: the same silence" {
  printf '# only a comment\n\n' > "$CC_COLDCOMPILE_PATTERNS"
  pair empty 'cd x && next dev'
  [ ! -s "$SHF_OUT_DIR/empty.new.out" ]
}
