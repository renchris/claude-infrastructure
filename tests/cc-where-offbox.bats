#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2329
#   Structurally false under bats: every @test body is its own subshell, so an `export` inside one
#   is meant to be test-local, and setup()'s helpers are called from those subshells.
#
# cc-where — the LOOKUP half of "make an off-box session visible locally"
# (docs/plans/CLOUD_OBSERVABILITY.md §9.3).
#
# THE DEFECT THIS CLOSES. cc-where's whole job is "where is my session, and how do I reach it",
# sourced from kitty's window tree. A session running in an Anthropic-managed VM is on no screen
# this box owns, so the tree cannot contain it and the honest-looking answer — `nothing matches
# 'session_…'` — is the §5.2 lie in its purest form: a live, healthy session reported as absent by
# an instrument that was never able to see it. It must ANSWER instead: off-box, state, open <url>.
#
# AND IT MUST NOT FAKE A PANE. An off-box session has no kitty window, no pid, no columns and no
# tab. Synthesising a census row for it would make it focusable, countable and (worse) reportable
# as ON SCREEN. So it gets its own block, `--json` stays a pane census, and `--go` exits 5 —
# found, off-box, nothing local to focus — which is distinguishable from 1, nothing anywhere.
#
# HERMETIC: the kitty tree is a fixture behind CC_WHERE_KITTY_LS, cc-cloud runs against a fixture
# CC_CLOUD_STATE over real local bare repositories, and `kitty`/`kitten`/`osascript` are PATH shims
# so no test touches the operator's live kitty, live cloud declarations or System Events.
# NO WALL-CLOCK: CC_CLOUD_NOW drives every age.
#
# DEAD-ASSERTION DISCIPLINE: POSIX `[ ]`, and `|| false` after any non-final negation — bash exempts
# `!` from errexit, so `! cmd` on a non-final line is an assertion that can never fail.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  W="$REPO/bin/cc-where"
  CLOUD="$REPO/bin/cc-cloud"
  D="$BATS_TEST_TMPDIR"

  export HOME="$D/home"; mkdir -p "$HOME"
  export CC_CLOUD_STATE="$D/cloud"; mkdir -p "$CC_CLOUD_STATE"
  export CC_WHERE_CLOUD_BIN="$CLOUD"
  export CC_CLOUD_NOW=2000000000
  export GIT_CONFIG_NOSYSTEM=1

  # PATH shims. `kitty` records the fact it was called (the local-focus control below asserts on
  # that record); `osascript` fails, which screen_positions() already degrades from.
  mkdir -p "$D/bin"
  cat > "$D/bin/kitty" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$D/kitty.calls"
exit 0
EOF
  cat > "$D/bin/osascript" <<'EOF'
#!/bin/bash
exit 1
EOF
  chmod +x "$D/bin/kitty" "$D/bin/osascript"
  export PATH="$D/bin:$PATH"

  # One OS window, one active tab, one ordinary local session pane.
  cat > "$D/tree.json" <<'EOF'
[{"id": 11, "tabs": [{
  "id": 18, "is_active": true, "layout": "splits",
  "groups": [{"id": 571, "windows": [480]}],
  "windows": [
    {"id": 480, "pid": 102, "title": "Fix dead holder lock", "cwd": "/w/b",
     "columns": 149, "lines": 38, "is_active": true, "is_focused": false,
     "created_at": 1786127774233656000}]}]}]
EOF
  export CC_WHERE_KITTY_LS="$D/tree.json"

  have_subject() {
    [ -x "$W" ]     || { echo "cc-where is missing or not executable at $W"; return 1; }
    [ -x "$CLOUD" ] || { echo "cc-cloud is missing or not executable at $CLOUD"; return 1; }
  }
  bare() { git init -q --bare "$D/$1.git" >/dev/null 2>&1; printf '%s' "$D/$1.git"; }
}

# ── the lookup answers instead of reporting absence ───────────────────────────────────────────────
@test "--go on an off-box session ANSWERS: kind=offbox, its state, and open <url> — exit 5" {
  have_subject
  # CONTROL FIRST, on the identical tree with nothing declared: the ordinary miss, exit 1.
  run "$W" --go 'session_01CHQ'
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -q 'nothing matches' || false

  r="$(bare rem)"
  "$CLOUD" declare --id session_01CHQoFxvsoD --branch feat/cloud --remote "$r" --repo "" \
    --url 'https://claude.ai/code/session_01CHQoFxvsoD' >/dev/null 2>&1

  run "$W" --go 'session_01CHQ'
  [ "$status" -eq 5 ]
  printf '%s\n' "$output" | grep -q 'kind=offbox' || false
  printf '%s\n' "$output" | grep -q 'addr=session_01CHQoFxvsoD' || false
  printf '%s\n' "$output" | grep -q 'state=BOOTING' || false
  printf '%s\n' "$output" | grep -q 'open https://claude.ai/code/session_01CHQoFxvsoD' || false
  # There is no local process, so nothing may be signalled and nothing focused.
  ! printf '%s\n' "$output" | grep -qi 'kill' || false
  [ ! -f "$D/kitty.calls" ]

  # The branch is a legitimate handle too — that is how the operator names the work.
  run "$W" --go 'feat/cloud'
  [ "$status" -eq 5 ]
}

@test "a LOCAL pane still wins — the off-box path is only reached on a genuine local miss" {
  have_subject
  r="$(bare rem)"
  # Declared and deliberately named so it WOULD match if the cloud path were consulted first.
  "$CLOUD" declare --id holder-lock-cloud --branch feat/holder-lock --remote "$r" --repo "" >/dev/null 2>&1

  run "$W" --go 'holder lock'
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q 'Fix dead holder lock' || false
  ! printf '%s\n' "$output" | grep -q 'kind=offbox' || false
  # The pane really was focused through kitty, i.e. the local arm ran unchanged.
  grep -q 'focus-window' "$D/kitty.calls" || false
}

@test "a RETIRED declaration is not somewhere to go" {
  have_subject
  r="$(bare rem)"
  "$CLOUD" declare --id session_done --branch feat/a --remote "$r" --repo "" >/dev/null 2>&1
  "$CLOUD" declare --id session_open --branch feat/b --remote "$r" --repo "" >/dev/null 2>&1
  "$CLOUD" retire  --id session_done >/dev/null 2>&1

  run "$W" --go 'session_done'
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -q 'nothing matches' || false

  # POSITIVE CONTROL off the same store: the sibling that was not retired still answers.
  run "$W" --go 'session_open'
  [ "$status" -eq 5 ]
  printf '%s\n' "$output" | grep -q 'addr=session_open' || false
}

@test "U0 renders as the literal word UNKNOWN, never as a gap" {
  have_subject
  gone="$D/never-existed.git"                  # unreachable remote ⇒ cc-cloud's U0 arm
  r="$(bare rem)"
  "$CLOUD" declare --id session_dark  --branch feat/a --remote "$gone" --repo "" >/dev/null 2>&1
  "$CLOUD" declare --id session_light --branch feat/b --remote "$r"    --repo "" >/dev/null 2>&1

  run "$W" --go 'session_dark'
  [ "$status" -eq 5 ]
  printf '%s\n' "$output" | grep -q 'state=UNKNOWN' || false
  ! printf '%s\n' "$output" | grep -qE 'state= ' || false

  # POSITIVE CONTROL: a reachable declaration on the same run reads a real verdict, so UNKNOWN is a
  # measurement and not this renderer's only output.
  run "$W" --go 'session_light'
  [ "$status" -eq 5 ]
  printf '%s\n' "$output" | grep -q 'state=BOOTING' || false
}

# ── it must never become a pane ───────────────────────────────────────────────────────────────────
@test "CONTROL — an off-box session is never a pane row: --json is byte-identical and pane-free" {
  have_subject
  before="$("$W" --json)"

  r="$(bare rem)"
  "$CLOUD" declare --id session_ghost --branch feat/a --remote "$r" --repo "" >/dev/null 2>&1
  after="$("$W" --json)"

  [ "$before" = "$after" ] || { echo "the pane census CHANGED:"; diff <(printf '%s\n' "$before") <(printf '%s\n' "$after"); false; }
  ! printf '%s\n' "$after" | grep -q 'session_ghost' || false
  [ "$(printf '%s' "$after" | jq -r 'length')" -eq 1 ]

  # POSITIVE CONTROL: the declaration IS visible on the surfaces that model it, so the byte-identity
  # above is a scoping decision rather than a join that silently did nothing.
  run "$W" --hidden
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q 'kind=offbox' || false
  printf '%s\n' "$output" | grep -q 'addr=session_ghost' || false
}

@test "the census and a title query both surface the off-box block without inventing a pane" {
  have_subject
  r="$(bare rem)"
  "$CLOUD" declare --id session_ghost --branch feat/ghost --remote "$r" --repo "" >/dev/null 2>&1

  # Full census: the local pane count is unchanged and the off-box block is additional.
  run "$W"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q '1 panes' || false
  printf '%s\n' "$output" | grep -q 'Fix dead holder lock' || false
  printf '%s\n' "$output" | grep -q 'addr=session_ghost' || false

  # A query that matches ONLY the off-box session must not answer "no pane matches" and must not
  # exit non-zero — it found the thing, it is simply not on a screen.
  run "$W" 'session_ghost'
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q 'addr=session_ghost' || false
  ! printf '%s\n' "$output" | grep -q 'no pane matches' || false

  # NEGATIVE CONTROL: a query matching neither still says so, and still fails.
  run "$W" 'nothing-at-all-matches-this'
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -q 'no pane matches' || false
}
