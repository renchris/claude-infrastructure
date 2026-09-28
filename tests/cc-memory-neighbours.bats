#!/usr/bin/env bats
# CONSOLIDATION FAMILIES — bin/cc-memory-neighbours, /compact-memory step 7b (truememory §3.16).
#
# PROPOSE-ONLY is the contract this suite exists to hold: a default run writes NOTHING to the store,
# and `--record` writes exactly one file, archive/.family-names. A tool that quietly wrote a link or a
# summary would hide a true duplicate from every later pass (step 7 presumes linked pairs distinct).
#
# THE FIXTURE STORE, 16 topics, each group sharing rare words no other group uses:
#   alpha1/alpha2   mutual pair, unlinked, distinct sessions      → PROPOSED
#   beta1/beta2     mutual pair, beta1 carries [[beta2]]           → not proposed (already linked)
#   gamma1/gamma2   mutual pair, one shared originSessionId        → not proposed (presumed distinct)
#   hub/delta       mutual pair; hub has 3 inbound links           → PROPOSED; hub becomes hot if LINKed
#   eps1/eps2/eps3  three-way mutual                               → 3 pairs, ONE family
#   anchor          4 inbound links (f1..f4)                       → the one hub before
#   f1..f4          fillers, no shared words
# So the whole-store answer is pairs=5 families=3, HOT-HUBS before=1 after_if_linked=2.
#
# HERMETIC: fixture $HOME and store under $BATS_TEST_TMPDIR; the real memory stores are never read.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  NB="$REPO/bin/cc-memory-neighbours"
  MEM="$BATS_TEST_TMPDIR/memory"; mkdir -p "$MEM"
  build_store
}

# mt <stem> <description> <originSessionId> <first paragraph> [later paragraph]
mt() {
  printf '%s\n' '---' "name: $1" "description: $2" 'metadata:' "  originSessionId: $3" '---' '' \
    "$4" '' "${5:-}" > "$MEM/$1.md"
}

build_store() {
  printf '%s\n' '# Memory' '- [Alpha](alpha1.md) — index only' > "$MEM/MEMORY.md"
  mt alpha1 'zephyr quokka marmot' s-a1 'The zephyr quokka marmot rule.'
  mt alpha2 'zephyr quokka marmot twin' s-a2 'Zephyr quokka marmot again.'
  mt beta1 'walrus pangolin narwhal' s-b1 'Walrus pangolin narwhal.' 'See [[beta2]].'
  mt beta2 'walrus pangolin narwhal too' s-b2 'Walrus pangolin narwhal too.'
  mt gamma1 'ocelot tapir gibbon' s-shared 'Ocelot tapir gibbon.'
  mt gamma2 'ocelot tapir gibbon also' s-shared 'Ocelot tapir gibbon also.'
  mt hub 'axolotl kinkajou' s-h 'Axolotl kinkajou central.'
  mt delta 'axolotl kinkajou copy' s-d 'Axolotl kinkajou copy.'
  mt anchor 'meerkat wombat' s-an 'Meerkat wombat.'
  mt eps1 'capybara dingo' s-e1 'Capybara dingo one.'
  mt eps2 'capybara dingo' s-e2 'Capybara dingo two.'
  mt eps3 'capybara dingo' s-e3 'Capybara dingo three.'
  mt f1 'lemur' s-f1 'Lemur.' 'See [[hub]] and [[anchor]].'
  mt f2 'jaguar' s-f2 'Jaguar.' 'See [[hub]] and [[anchor]].'
  mt f3 'bison' s-f3 'Bison.' 'See [[hub]] and [[anchor]].'
  mt f4 'heron' s-f4 'Heron.' 'See [[anchor]].'
}

# Every file under the store, with its hash — the byte-identity oracle.
snapshot() { (cd "$MEM" && find . -type f -print0 | sort -z | xargs -0 shasum); }

has_out()   { printf '%s\n' "$output" | grep -qF -- "$1"; }
lacks_out() { ! printf '%s\n' "$output" | grep -qF -- "$1"; }

@test "1 the whole store: an unlinked mutual pair is proposed, with the decision slot" {
  run "$NB" "$MEM"
  [ "$status" -eq 0 ]
  has_out '  - alpha1 — zephyr quokka marmot'
  has_out '  - alpha2 — zephyr quokka marmot twin'
  has_out '  pair: alpha1 <-> alpha2'
  has_out '  pair: delta <-> hub'
  has_out '  decision: MERGE | LINK | NONE  (human decides)'
  has_out 'FAMILIES-VERDICT topics=16 pairs=5 families=3'
}

@test "2 an already-linked pair and a shared-originSessionId pair are NOT proposed" {
  run "$NB" "$MEM"
  [ "$status" -eq 0 ]
  lacks_out 'beta1'
  lacks_out 'gamma1'
  lacks_out 'gamma2'
}

@test "3 a three-way mutual group is ONE family of three pairs" {
  run "$NB" "$MEM"
  [ "$status" -eq 0 ]
  has_out 'FAMILY 3  (3 members)'
  has_out '  pair: eps1 <-> eps2'
  has_out '  pair: eps1 <-> eps3'
  has_out '  pair: eps2 <-> eps3'
}

@test "4 HOT-HUBS counts the hub before and the one a LINK would create" {
  run "$NB" "$MEM"
  [ "$status" -eq 0 ]
  has_out 'HOT-HUBS before=1 after_if_linked=2'
}

@test "5 a default run leaves the store byte-identical and creates nothing" {
  before="$(snapshot)"
  run "$NB" "$MEM"
  [ "$status" -eq 0 ]
  [ "$(snapshot)" = "$before" ]
  [ ! -e "$MEM/archive" ]
}

@test "6 .family-names scopes out a reviewed pair; --all brings it back" {
  mkdir -p "$MEM/archive"
  printf '%s\n' alpha1 alpha2 > "$MEM/archive/.family-names"
  run "$NB" "$MEM"
  [ "$status" -eq 0 ]
  lacks_out 'alpha1'
  has_out 'FAMILIES-VERDICT topics=14 pairs=4 families=2'
  run "$NB" "$MEM" --all
  [ "$status" -eq 0 ]
  has_out '  pair: alpha1 <-> alpha2'
  has_out 'FAMILIES-VERDICT topics=16 pairs=5 families=3'
}

@test "7 a pair with only ONE member already reviewed is still proposed" {
  mkdir -p "$MEM/archive"
  printf '%s\n' alpha1 > "$MEM/archive/.family-names"
  run "$NB" "$MEM"
  [ "$status" -eq 0 ]
  has_out '  pair: alpha1 <-> alpha2'
  has_out 'FAMILIES-VERDICT topics=15 pairs=5 families=3'
}

@test "8 --record appends the in-scope names to .family-names and touches nothing else" {
  mkdir -p "$MEM/archive"
  printf '%s\n' alpha1 alpha2 > "$MEM/archive/.family-names"
  before="$(cd "$MEM" && find . -type f ! -name .family-names -print0 | sort -z | xargs -0 shasum)"
  run "$NB" "$MEM" --record
  [ "$status" -eq 0 ]
  has_out 'RECORDED 14 topic name(s)'
  after="$(cd "$MEM" && find . -type f ! -name .family-names -print0 | sort -z | xargs -0 shasum)"
  [ "$after" = "$before" ]
  [ "$(wc -l < "$MEM/archive/.family-names" | tr -d ' ')" -eq 16 ]
  [ "$(head -1 "$MEM/archive/.family-names")" = alpha1 ]
  run "$NB" "$MEM"
  has_out 'FAMILIES-VERDICT topics=0 pairs=0 families=0'
}

@test "9 --json carries the same answer with a null decision per family" {
  run "$NB" "$MEM" --json
  [ "$status" -eq 0 ]
  has_out '"after_if_linked": 2'
  has_out '"decision": null'
  has_out '"a": "alpha1"'
}

@test "10 X1: a run through a SYMLINK finds the tokenizer beside the real file" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  ln -s "$NB" "$BATS_TEST_TMPDIR/bin/cc-memory-neighbours"
  [ ! -e "$BATS_TEST_TMPDIR/hooks/lib/memory_neighbours.py" ]
  run "$BATS_TEST_TMPDIR/bin/cc-memory-neighbours" "$MEM"
  [ "$status" -eq 0 ]
  has_out 'FAMILIES-VERDICT topics=16 pairs=5 families=3'
}

@test "11 a store path that is not a directory exits 2" {
  run "$NB" "$BATS_TEST_TMPDIR/nope"
  [ "$status" -eq 2 ]
  has_out 'not a directory'
}
