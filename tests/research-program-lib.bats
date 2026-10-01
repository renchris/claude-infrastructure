#!/usr/bin/env bats
# research-program-lib.bats — scripts/lib/research-program.sh, the registry resolver every
# active-program exemption keys on (REPORT.md §10 open item 10, option 1).
#
# Planted input: a temp registry holding an active program versus none. Every case runs the lib
# under /bin/bash (3.2 on macOS) — the interpreter a hook or a launchd job actually gets — so a
# 4.x-only construct fails here instead of silently in the hook.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"   # hermetic: never the operator's live ~/
  LIB="$REPO/scripts/lib/research-program.sh"
  export CC_RESEARCH_REGISTRY="$BATS_TEST_TMPDIR/programs.json"
  ROOT="$BATS_TEST_TMPDIR/prog"; mkdir -p "$ROOT/sub/deeper" "$BATS_TEST_TMPDIR/progX" "$BATS_TEST_TMPDIR/elsewhere"
}

reg() { # <slug> <state> <root>... → writes a one-program registry
  local slug="$1" state="$2"; shift 2
  jq -n --arg s "$slug" --arg st "$state" --args \
    '{programs:[{slug:$s,aliases:[],cwd_roots:$ARGS.positional,state:$st}]}' "$@" > "$CC_RESEARCH_REGISTRY"
}
resolve()   { /bin/bash -c '. "$1"; rp_resolve_cwd "$2"' _ "$LIB" "$1"; }
is_active() { /bin/bash -c '. "$1"; rp_is_active "$2"' _ "$LIB" "$1"; }

@test "an active program's root and any dir under it resolve to '<slug> <state>'" {
  reg pilot certifying "$ROOT"
  run resolve "$ROOT"
  [ "$status" -eq 0 ]; [ "$output" = "pilot certifying" ]
  run resolve "$ROOT/sub/deeper"
  [ "$output" = "pilot certifying" ]
  run is_active "$ROOT/sub"
  [ "$status" -eq 0 ]
}

@test "registered, certifying and certified are active; closed and an unknown state are not" {
  local s
  for s in registered certifying certified; do
    reg pilot "$s" "$ROOT"; run is_active "$ROOT"; [ "$status" -eq 0 ]
  done
  for s in closed paused; do
    reg pilot "$s" "$ROOT"; run is_active "$ROOT"; [ "$status" -eq 1 ]
  done
  # a closed program still RESOLVES (the router reports it); it just is not active
  reg pilot closed "$ROOT"; run resolve "$ROOT"; [ "$output" = "pilot closed" ]
}

@test "a dir outside every root resolves to nothing and is not active — a name prefix is not containment" {
  reg pilot certified "$ROOT"
  run resolve "$BATS_TEST_TMPDIR/progX"     # shares the string prefix 'prog'
  [ "$status" -eq 0 ]; [ -z "$output" ]
  run is_active "$BATS_TEST_TMPDIR/elsewhere"
  [ "$status" -eq 1 ]
}

@test "the longest containing root wins when programs nest" {
  jq -n --arg a "$ROOT" --arg b "$ROOT/sub" \
    '{programs:[{slug:"outer",aliases:[],cwd_roots:[$a],state:"closed"},
                {slug:"inner",aliases:[],cwd_roots:[$b],state:"registered"}]}' > "$CC_RESEARCH_REGISTRY"
  run resolve "$ROOT/sub/deeper"; [ "$output" = "inner registered" ]
  run resolve "$ROOT";            [ "$output" = "outer closed" ]
}

@test "a root spelled through a symlink or with a trailing slash still contains the physical cwd" {
  ln -s "$ROOT" "$BATS_TEST_TMPDIR/link"
  reg pilot certified "$BATS_TEST_TMPDIR/link/"
  run resolve "$ROOT/sub"
  [ "$output" = "pilot certified" ]
}

@test "a missing registry means no program: nothing printed, rp_is_active exits 1, one stderr line" {
  rm -f "$CC_RESEARCH_REGISTRY"
  run resolve "$ROOT"
  [ "$status" -eq 0 ]; [ -z "$(resolve "$ROOT" 2>/dev/null)" ]
  run /bin/bash -c '. "$1"; rp_is_active "$2"; rp_is_active "$2"; echo "rc=$?"' _ "$LIB" "$ROOT"
  [ "$(printf '%s\n' "$output" | grep -c 'is missing')" -eq 1 ]   # said ONCE across two calls
  printf '%s' "$output" | grep -q 'rc=1'
}

@test "an unparseable or wrong-shape registry means no program and says so on stderr" {
  printf '{not json' > "$CC_RESEARCH_REGISTRY"
  run is_active "$ROOT"; [ "$status" -eq 1 ]
  printf '%s' "$output" | grep -q 'unparseable'
  printf '{"programs":{"slug":"x"}}' > "$CC_RESEARCH_REGISTRY"
  run is_active "$ROOT"; [ "$status" -eq 1 ]
  printf '%s' "$output" | grep -q 'unparseable'
}

@test "CLI: is-active and resolve work when the lib is executed, not sourced" {
  reg pilot certified "$ROOT"
  run /bin/bash "$LIB" is-active "$ROOT/sub";   [ "$status" -eq 0 ]
  run /bin/bash "$LIB" resolve "$ROOT";         [ "$output" = "pilot certified" ]
  run /bin/bash "$LIB" is-active "$BATS_TEST_TMPDIR/elsewhere"; [ "$status" -eq 1 ]
}
