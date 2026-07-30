#!/usr/bin/env bats
# store-bounds.bats — row 13 M9c (MACHINE_CAPACITY_V2.md §11.3). The unbounded-store ratchet.
#
# The properties that matter, in priority order:
#   1. It NEVER deletes, rotates, or truncates. A watcher that also prunes will eventually prune on a
#      bad read (memory append-only-store-safety-rules: an "archive" whose `mv -f` destroyed 1,461
#      lines). Asserted twice — once on behaviour, once on the script's executable text.
#   2. A void does not read as success. Root missing ⇒ NO-DATA, never a clean OK over zero stores
#      (memory absence-alarm-needs-existence-evidence).
#   3. Sizes are HAND-WRITTEN in the fixture and compared against literals, never recomputed with the
#      subject's own sizing code — the tautology that made the incumbent capacity-alarm census test
#      worthless (see capacity-alarm.bats (vii)).
#   4. Every rung is reachable, proven by a positive control rather than asserted.
#
# `|| false` on every non-final [[ ]]/[ ] chain — errexit-exempt assertions are DEAD (memory
# bats-dead-assertions-errexit-exemptions).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd -P)"
  CENSUS="$REPO/scripts/store-bounds-census.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/logs"
  export CC_SB_ROOT="$BATS_TEST_TMPDIR/root"
  export CC_SB_LOG="$BATS_TEST_TMPDIR/sb.jsonl"
  export CC_PAGES_DIR="$BATS_TEST_TMPDIR/pages"
  MAN="$BATS_TEST_TMPDIR/m.manifest"
  export CC_SB_MANIFEST="$MAN"
}

# A fixture store of an EXACT byte size. mkfile-free and fork-cheap: 1 MiB = 1048576 bytes, so the
# expected MB in every assertion below is a literal a reader can check by hand.
mkstore() { # <relative-path> <mebibytes>
  local p="$CC_SB_ROOT/$1"
  mkdir -p "$(dirname "$p")"
  dd if=/dev/zero of="$p" bs=1048576 count="$2" 2>/dev/null
}

@test "(i) selftest GREEN — all three rungs, the parser, and measure-only are controlled" {
  run /bin/bash "$CENSUS" --selftest
  [ "$status" -eq 0 ] || false
  [[ "$output" =~ "selftest GREEN" ]] || false
  # each rung NAMED, so a silently-unreachable one cannot hide behind an aggregate pass
  [[ "$output" =~ "→ OK" ]] || false
  [[ "$output" =~ "→ BREACH" ]] || false
  [[ "$output" =~ "→ NO-DATA" ]] || false
  [[ "$output" =~ "parser valid=2 malformed=3" ]] || false
  [[ "$output" =~ "measure-only" ]] || false
}

@test "(ii) every store under cap → OK, rc 0" {
  mkdir -p "$CC_SB_ROOT"
  mkstore logs/a.log 2
  printf '%s\n' 'logs/a.log|10|6|rotate' > "$MAN"
  run /bin/bash "$CENSUS" --json --quiet --no-append
  [ "$status" -eq 0 ] || false
  [[ "$output" =~ \"verdict\":\"OK\" ]] || false
  [[ "$output" =~ \"mb\":2.0 ]] || false          # 2 MiB, written by hand above
  [[ "$output" =~ \"breaches\":0 ]] || false
}

@test "(iii) THE LOAD-BEARING ONE — a store over cap → BREACH, rc 1, with the literal size" {
  mkdir -p "$CC_SB_ROOT"
  mkstore logs/big.log 12
  printf '%s\n' 'logs/big.log|4|6|rotate: gzip+truncate' > "$MAN"
  run /bin/bash "$CENSUS" --json --quiet --no-append
  [ "$status" -eq 1 ] || false
  [[ "$output" =~ \"verdict\":\"BREACH\" ]] || false
  [[ "$output" =~ \"mb\":12.0 ]] || false         # 12 MiB > 4 MiB cap
  [[ "$output" =~ \"breaches\":1 ]] || false
  [[ "$output" =~ \"breach\":true ]] || false
}

@test "(iv) a multi-file glob is SUMMED and judged as ONE store" {
  # The stale-backup row is exactly this shape: session-index.db.bak-* is three files that are one
  # problem. Summing is what makes a cap on the SET meaningful.
  mkdir -p "$CC_SB_ROOT"
  mkstore state/db.bak-1 3
  mkstore state/db.bak-2 3
  mkstore state/db.bak-3 2
  printf '%s\n' 'state/db.bak-*|4|9|stale backup — operator call' > "$MAN"
  run /bin/bash "$CENSUS" --json --quiet --no-append
  [ "$status" -eq 1 ] || false
  [[ "$output" =~ \"mb\":8.0 ]] || false          # 3+3+2, hand-summed
  [[ "$output" =~ \"files\":3 ]] || false
}

@test "(v) IT NEVER DELETES — the over-cap store is byte-for-byte intact after a BREACH" {
  # The property, asserted on behaviour. A page is the only thing a breach may produce.
  mkdir -p "$CC_SB_ROOT"
  mkstore logs/precious.log 6
  before="$(stat -f %z "$CC_SB_ROOT/logs/precious.log")"
  printf '%s\n' 'logs/precious.log|1|6|rotate' > "$MAN"
  run /bin/bash "$CENSUS" --quiet
  [ "$status" -eq 1 ] || false
  [ -f "$CC_SB_ROOT/logs/precious.log" ] || false
  after="$(stat -f %z "$CC_SB_ROOT/logs/precious.log")"
  [ "$before" = "$after" ] || false
  [ "$after" -eq 6291456 ] || false               # 6 MiB, unchanged
}

@test "(vi) POSITIVE CONTROL for the measure-only guard — the REAL selftest convicts an injected line" {
  # The selftest's measure-only control passes today; without this, that pass could equally mean the
  # pattern matches NOTHING AT ALL — an unfalsifiable green.
  #
  # THIS CONTROL RUNS THE REAL ARTIFACT, not a replica of its regex. The first version of this test
  # re-typed an approximation of the guard pattern into the test and convicted a bait file with it —
  # which proves only that *some* pattern can match, never that the SUBJECT's pattern can. A regex
  # edit that defanged the real guard would have left this test passing (memory
  # control-must-replay-the-real-artifact: a proof that hand-edits an approximation passes
  # vacuously). So instead: copy the actual script, inject one destructive line, and require its OWN
  # --selftest to go RED.
  #
  # The injected line is appended AFTER the final `exit`, so it is text the guard must catch and code
  # that can never run — the fixture cannot delete anything even if the guard were removed entirely.
  doctored="$BATS_TEST_TMPDIR/doctored.sh"
  cp "$CENSUS" "$doctored"
  printf '%s\n' 'rm -f "$ROOT/logs/victim.log"' >> "$doctored"
  run /bin/bash "$doctored" --selftest
  [ "$status" -eq 70 ] || false
  [[ "$output" =~ "a destructive verb targets a store path" ]] || false
  [[ "$output" =~ "selftest RED" ]] || false

  # NEGATIVE CONTROL — an unmodified copy at the same path must stay GREEN, so the conviction above is
  # attributable to the injected line and not to the copying itself.
  pristine="$BATS_TEST_TMPDIR/pristine.sh"
  cp "$CENSUS" "$pristine"
  run /bin/bash "$pristine" --selftest
  [ "$status" -eq 0 ] || false
  [[ "$output" =~ "no destructive verb targets any store path" ]] || false
}

@test "(vi-b) the guard does NOT convict the two shapes that are legitimate — comment, and \$PAGE" {
  # A guard that fires on anything containing `rm` is unusable: this script must be free to retract the
  # page it wrote. Both false-positive shapes are injected into the REAL artifact and must stay GREEN,
  # which is what makes the conviction in (vi) meaningful rather than trigger-happy.
  #   · a COMMENT naming a destructive op on a store  — text is never evidence
  #     (memory detector-matching-its-own-skill-description)
  #   · `rm -f "$PAGE"` — self-clearing a page it owns is nothing like touching somebody's store
  benign="$BATS_TEST_TMPDIR/benign.sh"
  cp "$CENSUS" "$benign"
  printf '%s\n' '# rm -f "$ROOT/logs/x.log" — discussed, never done' 'rm -f "$PAGE.extra"' >> "$benign"
  run /bin/bash "$benign" --selftest
  [ "$status" -eq 0 ] || false
  [[ "$output" =~ "no destructive verb targets any store path" ]] || false
  [[ "$output" =~ "selftest GREEN" ]] || false
}

@test "(vii) a MISSING ROOT is NO-DATA (rc 3), never a clean OK over zero stores" {
  # The fixtured-void trap. Every glob matches nothing, every store sums to 0, and a naive reading
  # reports success — the exact shape of a phantom green.
  export CC_SB_ROOT="$BATS_TEST_TMPDIR/does-not-exist"
  printf '%s\n' 'logs/a.log|10|6|rotate' > "$MAN"
  run /bin/bash "$CENSUS" --json --quiet --no-append
  [ "$status" -eq 3 ] || false
  [[ "$output" =~ \"verdict\":\"NO-DATA\" ]] || false
  ! [[ "$output" =~ \"verdict\":\"OK\" ]] || false
}

@test "(viii) a glob that matches NOTHING while the root exists is OK — absent is not unbounded" {
  # The distinction (vii) turns on: a declared store that has not been created yet is genuinely not a
  # growth problem, so it must NOT be NO-DATA. Getting this wrong would make the census blind on any
  # box where one store happens not to exist.
  mkdir -p "$CC_SB_ROOT"
  printf '%s\n' 'logs/never-created.log|10|6|rotate' > "$MAN"
  run /bin/bash "$CENSUS" --json --quiet --no-append
  [ "$status" -eq 0 ] || false
  [[ "$output" =~ \"verdict\":\"OK\" ]] || false
  [[ "$output" =~ \"mb\":0.0 ]] || false
  [[ "$output" =~ \"files\":0 ]] || false
  [[ "$output" =~ \"rows\":1 ]] || false           # the row was READ, not skipped
}

@test "(ix) comments, blanks and indented comments are ignored; malformed rows counted not fatal" {
  mkdir -p "$CC_SB_ROOT"
  mkstore logs/a.log 1
  {
    echo '# a header comment'
    echo ''
    echo '   # an indented comment'
    echo 'logs/a.log|10|6|rotate'
    echo 'logs/missing-fields.log|10'
    echo 'logs/bad-cap.log|abc|6|rotate'
    echo '../escape.log|10|6|rotate'
  } > "$MAN"
  run /bin/bash "$CENSUS" --json --quiet --no-append
  [ "$status" -eq 0 ] || false
  [[ "$output" =~ \"rows\":1 ]] || false           # exactly the one good row
  [[ "$output" =~ \"malformed\":3 ]] || false      # short, non-numeric cap, and the `..` escape
  [[ "$output" =~ \"verdict\":\"OK\" ]] || false
}

@test "(x) a manifest with ZERO usable rows is NO-DATA — a comment-only file asserts nothing" {
  # Distinct from (viii): there, a row existed and measured 0. Here the corpus itself is empty, so
  # there is nothing to be OK about. A parser regression that dropped every row would land here.
  mkdir -p "$CC_SB_ROOT"
  { echo '# only comments'; echo ''; } > "$MAN"
  run /bin/bash "$CENSUS" --json --quiet --no-append
  [ "$status" -eq 3 ] || false
  [[ "$output" =~ \"verdict\":\"NO-DATA\" ]] || false
  [[ "$output" =~ \"rows\":0 ]] || false
}

@test "(xi) an ABSENT manifest is NO-DATA, not OK" {
  mkdir -p "$CC_SB_ROOT"
  export CC_SB_MANIFEST="$BATS_TEST_TMPDIR/no-such.manifest"
  run /bin/bash "$CENSUS" --json --quiet --no-append
  [ "$status" -eq 3 ] || false
  [[ "$output" =~ \"verdict\":\"NO-DATA\" ]] || false
}

@test "(xii) BREACH writes ONE fixed-slug page naming store/size/cap/owner/remedy; OK CLEARS it" {
  mkdir -p "$CC_SB_ROOT"
  mkstore logs/big.log 12
  printf '%s\n' 'logs/big.log|4|6|rotate: gzip+truncate per its own header' > "$MAN"
  page="$CC_PAGES_DIR/store-bounds.page"

  run /bin/bash "$CENSUS" --quiet
  [ "$status" -eq 1 ] || false
  [ -f "$page" ] || false
  run grep -c 'store-bounds BREACH' "$page"
  [ "$output" -ge 1 ] || false
  # the page must carry the ACTIONABLE fields, not just a count
  run grep -cE 'logs/big\.log 12\.0/4MB owner=6 remedy=rotate' "$page"
  [ "$output" -ge 1 ] || false

  # raise the cap above the size ⇒ condition cleared ⇒ page retracted (self-clearing, not history)
  printf '%s\n' 'logs/big.log|64|6|rotate' > "$MAN"
  run /bin/bash "$CENSUS" --quiet
  [ "$status" -eq 0 ] || false
  [ ! -f "$page" ] || false
}

@test "(xiii) NO-DATA also retracts a stale page — never assert a condition we cannot see" {
  mkdir -p "$CC_SB_ROOT"
  mkstore logs/big.log 12
  printf '%s\n' 'logs/big.log|4|6|rotate' > "$MAN"
  page="$CC_PAGES_DIR/store-bounds.page"
  run /bin/bash "$CENSUS" --quiet
  [ -f "$page" ] || false
  export CC_SB_ROOT="$BATS_TEST_TMPDIR/gone"
  run /bin/bash "$CENSUS" --quiet
  [ "$status" -eq 3 ] || false
  [ ! -f "$page" ] || false
}

@test "(xiv) the page slug is FIXED — repeated breaches overwrite, never accumulate" {
  # The unslugged channel has 490 files on disk. A job on an interval must not add to that.
  mkdir -p "$CC_SB_ROOT"
  mkstore logs/big.log 12
  printf '%s\n' 'logs/big.log|4|6|rotate' > "$MAN"
  for _ in 1 2 3; do
    run /bin/bash "$CENSUS" --quiet
    [ "$status" -eq 1 ] || false
  done
  n="$(find "$CC_PAGES_DIR" -name '*.page' | wc -l | tr -d ' ')"
  [ "$n" -eq 1 ] || false
}

@test "(xv) kill switch CC_STORE_BOUNDS=off → rc 0, NO log and NO page" {
  mkdir -p "$CC_SB_ROOT"
  mkstore logs/big.log 12
  printf '%s\n' 'logs/big.log|4|6|rotate' > "$MAN"
  run env CC_STORE_BOUNDS=off CC_SB_LOG="$BATS_TEST_TMPDIR/ks.jsonl" /bin/bash "$CENSUS" --quiet
  [ "$status" -eq 0 ] || false
  [ ! -f "$BATS_TEST_TMPDIR/ks.jsonl" ] || false
  [ ! -f "$CC_PAGES_DIR/store-bounds.page" ] || false
}

@test "(xvi) appends a durable row by default; --no-append writes NEITHER log nor page" {
  mkdir -p "$CC_SB_ROOT"
  mkstore logs/big.log 12
  printf '%s\n' 'logs/big.log|4|6|rotate' > "$MAN"
  log="$BATS_TEST_TMPDIR/a.jsonl"
  run env CC_SB_LOG="$log" /bin/bash "$CENSUS" --quiet
  [ -f "$log" ] || false
  run grep -c '"verdict":' "$log"
  [ "$output" -ge 1 ] || false

  log2="$BATS_TEST_TMPDIR/b.jsonl"
  run env CC_SB_LOG="$log2" CC_PAGES_DIR="$BATS_TEST_TMPDIR/pages2" /bin/bash "$CENSUS" --quiet --no-append
  [ "$status" -eq 1 ] || false                     # verdict still reported — a dry read still reads
  [ ! -f "$log2" ] || false
  [ ! -f "$BATS_TEST_TMPDIR/pages2/store-bounds.page" ] || false
}

@test "(xvii) CC_SB_PAGE=off suppresses the page but still logs (channel and record are separate)" {
  mkdir -p "$CC_SB_ROOT"
  mkstore logs/big.log 12
  printf '%s\n' 'logs/big.log|4|6|rotate' > "$MAN"
  log="$BATS_TEST_TMPDIR/p.jsonl"
  run env CC_SB_PAGE=off CC_SB_LOG="$log" /bin/bash "$CENSUS" --quiet
  [ "$status" -eq 1 ] || false
  [ ! -f "$CC_PAGES_DIR/store-bounds.page" ] || false
  [ -f "$log" ] || false
  run grep -c '"verdict":"BREACH"' "$log"
  [ "$output" -ge 1 ] || false
}

@test "(xviii) unknown arg → rc 64, never a silent ignore" {
  run /bin/bash "$CENSUS" --definitely-not-a-flag
  [ "$status" -eq 64 ] || false
}

@test "(xix) the read is BOUNDED — no find/recursive walk over the transcript corpus" {
  # ~/.claude holds 7,359 transcript files / 4.26 GB under projects/. A census that walked it would
  # become the load problem this row exists to eliminate. Comments stripped first: the header explains
  # this at length, and a guard that convicts its own documentation is worthless (memory
  # detector-matching-its-own-skill-description).
  [ -f "$CENSUS" ] || false
  run bash -c "sed 's/#.*//' '$CENSUS' | grep -nE '\\bfind\\b|\\bdu\\b[[:space:]]+-|-exec\\b|\\bprojects/'"
  [ "$status" -ne 0 ] || false
}

@test "(xx) POSITIVE CONTROL for (xix): the comment-stripped grep still catches a real find" {
  printf '%s\n' '# we never find here' 'find "$ROOT" -type f' > "$BATS_TEST_TMPDIR/fbait.sh"
  run bash -c "sed 's/#.*//' '$BATS_TEST_TMPDIR/fbait.sh' | grep -nE '\\bfind\\b'"
  [ "$status" -eq 0 ] || false
  printf '%s\n' '# we never find here' ':' > "$BATS_TEST_TMPDIR/fclean.sh"
  run bash -c "sed 's/#.*//' '$BATS_TEST_TMPDIR/fclean.sh' | grep -nE '\\bfind\\b'"
  [ "$status" -ne 0 ] || false
}

@test "(xx-b) it is DIRECTLY EXECUTABLE — the one property every test above is blind to" {
  # Caught by inspection, not by this suite, and that is the point worth recording: every other test
  # invokes the subject as `/bin/bash "$CENSUS"`, which succeeds whether or not the file carries its
  # executable bit. The suite was therefore structurally incapable of noticing that the script shipped
  # mode 644 — and it ships to LAUNCHD, which execs ProgramArguments[0] directly and would have failed
  # with EACCES on every single run. The page it writes also advertises `re-run: $0`, an instruction
  # the operator could not follow.
  #
  # A gate that can only ever see the artifact through an interpreter cannot certify how the artifact
  # is actually launched — so this asserts the launch path itself: the mode bit AND the shebang.
  [ -x "$CENSUS" ] || false
  run head -1 "$CENSUS"
  [ "$output" = "#!/bin/bash" ] || false
  # and it really runs with no interpreter named — the property, not just the bit
  run env CC_STORE_BOUNDS=off "$CENSUS" --quiet
  [ "$status" -eq 0 ] || false
}

@test "(xxi) the SHIPPED manifest declares every §8.5.5 store, and parses to zero malformed rows" {
  # A manifest is a claim about coverage. This asserts the claim against the real file rather than
  # against a fixture, so a row lost to a bad edit fails here instead of silently narrowing the census.
  real="$REPO/config/store-bounds.manifest"
  [ -f "$real" ] || false
  for store in logs/bash-execution.log logs/bash-commands.log autonomy/idl.jsonl \
               logs/teammate-checkpoint.log session-index.db state/session-index.db.bak- \
               logs/cc-reaper.log history.jsonl; do
    run grep -cF "$store" "$real"
    [ "$output" -ge 1 ] || false
  done
  mkdir -p "$CC_SB_ROOT"
  run env CC_SB_MANIFEST="$real" /bin/bash "$CENSUS" --json --quiet --no-append
  [[ "$output" =~ \"rows\":8 ]] || false
  [[ "$output" =~ \"malformed\":0 ]] || false
}
