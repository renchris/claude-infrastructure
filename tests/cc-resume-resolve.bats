#!/usr/bin/env bats
# cc-resume-resolve + _cc_resume_pin — cross-account, cross-worktree `claude --resume <id>`.
#
# Hermetic: every store is a fixture under $BATS_TEST_TMPDIR and reached via CC_RESUME_STORES,
# so the suite never reads the operator's real ~/.claude* trees and never depends on which
# account the developer happens to be on.

bats_require_minimum_version 1.5.0   # `run --separate-stderr`

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  RESOLVE="$REPO/bin/cc-resume-resolve"
  SHLIB="$REPO/lib/cc-resume-shell.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  # Pin the store set explicitly: the account map must not reach past the fixtures.
  A="$BATS_TEST_TMPDIR/store-a"
  B="$BATS_TEST_TMPDIR/store-b"
  export CC_RESUME_STORES="$A:$B"
  export CC_RESUME_RESOLVE_BIN="$RESOLVE"
  unset CC_RESUME_NO_RESOLVE CC_RESUME_MKDIR
}

# mkses <store> <cwd> <sid> — write a fixture transcript the way Claude Code does: one
# jsonl under projects/<cwd with every non-alphanumeric replaced by a dash>/<sid>.jsonl.
mkses() {
  local store="$1" cwd="$2" sid="$3"
  local hash; hash="$(printf '%s' "$cwd" | sed 's/[^a-zA-Z0-9]/-/g')"
  mkdir -p "$store/projects/$hash"
  printf '{"type":"user","cwd":"%s","sessionId":"%s"}\n' "$cwd" "$sid" \
    > "$store/projects/$hash/$sid.jsonl"
}

SID1=11111111-aaaa-4bbb-8ccc-111111111111

# ── resolver ────────────────────────────────────────────────────────────────────────────

@test "resolves a session in a non-default store to its config dir and recorded cwd" {
  mkdir -p "$BATS_TEST_TMPDIR/wt-x"
  mkses "$B" "$BATS_TEST_TMPDIR/wt-x" "$SID1"
  run "$RESOLVE" "$SID1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"sid=$SID1"* ]] || return 1
  [[ "$output" == *"config_dir=$B"* ]] || return 1
  [[ "$output" == *"cwd=$BATS_TEST_TMPDIR/wt-x"* ]] || return 1
  [[ "$output" == *"cwd_exists=1"* ]] || return 1
}

@test "reports cwd_exists=0 when the worktree was reaped" {
  mkses "$B" "$BATS_TEST_TMPDIR/wt-gone" "$SID1"   # never mkdir'd
  run "$RESOLVE" "$SID1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"cwd_exists=0"* ]] || return 1
}

@test "an 8-char prefix expands to the full session id" {
  mkdir -p "$BATS_TEST_TMPDIR/wt-x"
  mkses "$A" "$BATS_TEST_TMPDIR/wt-x" "$SID1"
  run "$RESOLVE" "${SID1:0:8}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"sid=$SID1"* ]] || return 1
}

@test "an ambiguous prefix exits 4 with EMPTY stdout and both candidates on stderr" {
  mkdir -p "$BATS_TEST_TMPDIR/wt-x"
  mkses "$A" "$BATS_TEST_TMPDIR/wt-x" "aaaaaaaa-1111-4bbb-8ccc-111111111111"
  mkses "$B" "$BATS_TEST_TMPDIR/wt-x" "aaaaaaaa-2222-4bbb-8ccc-222222222222"
  run --separate-stderr "$RESOLVE" aaaaaaaa
  [ "$status" -eq 4 ]
  [ -z "$output" ]
  [[ "$stderr" == *"ambiguous"* ]] || return 1
  [[ "$stderr" == *"aaaaaaaa-1111"* ]] || return 1
  [[ "$stderr" == *"aaaaaaaa-2222"* ]] || return 1
}

@test "an unknown session exits 3 with empty stdout (caller must fail open)" {
  run --separate-stderr "$RESOLVE" deadbeef-0000-4000-8000-000000000000
  [ "$status" -eq 3 ]
  [ -z "$output" ]                       # stdout empty — a caller parsing KEY=value gets nothing
  [[ "$stderr" == *"no session"* ]] || return 1   # the diagnosis goes to stderr, where it cannot be parsed
}

@test "rejects a non-id argument instead of globbing the stores with it" {
  run "$RESOLVE" 'foo;rm -rf /'
  [ "$status" -eq 2 ]
  run "$RESOLVE" 'abc'
  [ "$status" -eq 2 ]
}

@test "two store names for ONE projects tree resolve once, not as an ambiguity" {
  # ~/.claude-next/projects is a symlink to ~/.claude/projects — the same account under two
  # names. Without the realpath dedupe this is a spurious duplicate hit.
  mkdir -p "$BATS_TEST_TMPDIR/wt-x"
  mkses "$A" "$BATS_TEST_TMPDIR/wt-x" "$SID1"
  mkdir -p "$B"
  ln -s "$A/projects" "$B/projects"
  run "$RESOLVE" "$SID1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"config_dir=$A"* ]] || return 1
}

@test "a prefix search ignores files that merely SHARE the prefix" {
  # `<prefix>*.jsonl` also globs `<sid>-copy.jsonl` and `agent-<sid>.jsonl`. Only the first is
  # reachable by the glob at all, so it is the one that actually exercises the shape guard —
  # the agent- case passes for free and would prove nothing on its own.
  mkdir -p "$BATS_TEST_TMPDIR/wt-x"
  local hash; hash="$(printf '%s' "$BATS_TEST_TMPDIR/wt-x" | sed 's/[^a-zA-Z0-9]/-/g')"
  mkdir -p "$A/projects/$hash"
  printf '{"cwd":"x"}\n' > "$A/projects/$hash/$SID1-copy.jsonl"
  printf '{"cwd":"x"}\n' > "$A/projects/$hash/agent-$SID1.jsonl"
  run "$RESOLVE" "${SID1:0:8}"
  [ "$status" -eq 3 ]
  # ...and with the real session alongside them, it resolves to the real one, unambiguously.
  mkses "$A" "$BATS_TEST_TMPDIR/wt-x" "$SID1"
  run "$RESOLVE" "${SID1:0:8}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"sid=$SID1"* ]] || return 1
}

# ── the launcher-side pin ───────────────────────────────────────────────────────────────

# pin <default_cfg> <args...> — source the lib, run the pin, echo what a launcher would do.
pin() {
  local def="$1"; shift
  # shellcheck source=/dev/null
  source "$SHLIB"
  _cc_resume_pin "$def" "$@"
  echo "CFG=[$CC_RESUME_CFG]"
  echo "CWD=[$CC_RESUME_CWD]"
  echo "ARGS=[${CC_RESUME_ARGS[*]}]"
}

@test "pin redirects config dir AND cwd for a session in another account" {
  mkdir -p "$BATS_TEST_TMPDIR/wt-x" "$A/projects"
  mkses "$B" "$BATS_TEST_TMPDIR/wt-x" "$SID1"
  run pin "$A" --resume "$SID1" -p hi
  [ "$status" -eq 0 ]
  [[ "$output" == *"CFG=[$B]"* ]] || return 1
  [[ "$output" == *"CWD=[$BATS_TEST_TMPDIR/wt-x]"* ]] || return 1
}

@test "pin leaves the config dir alone when the default already reaches the transcript" {
  mkdir -p "$BATS_TEST_TMPDIR/wt-x"
  mkses "$A" "$BATS_TEST_TMPDIR/wt-x" "$SID1"
  run pin "$A" --resume "$SID1"
  [[ "$output" == *"CFG=[]"* ]] || return 1
  [[ "$output" == *"CWD=[$BATS_TEST_TMPDIR/wt-x]"* ]] || return 1
}

@test "pin rewrites a prefix in argv to the full id, in both --resume forms" {
  mkdir -p "$BATS_TEST_TMPDIR/wt-x"
  mkses "$A" "$BATS_TEST_TMPDIR/wt-x" "$SID1"
  run pin "$A" --model m --resume "${SID1:0:8}" -p hi
  [[ "$output" == *"ARGS=[--model m --resume $SID1 -p hi]"* ]] || return 1
  run pin "$A" "--resume=${SID1:0:8}" -p hi
  [[ "$output" == *"ARGS=[--resume=$SID1 -p hi]"* ]] || return 1
}

@test "pin passes a BARE --resume through untouched (that is Claude's own picker)" {
  mkdir -p "$BATS_TEST_TMPDIR/wt-x"
  mkses "$B" "$BATS_TEST_TMPDIR/wt-x" "$SID1"
  run pin "$A" --resume
  [[ "$output" == *"ARGS=[--resume]"* ]] || return 1
  [[ "$output" == *"CFG=[]"* ]] || return 1
  run pin "$A" --resume --model m
  [[ "$output" == *"ARGS=[--resume --model m]"* ]] || return 1
  [[ "$output" != *"CFG=[$B]"* ]] || return 1
}

@test "pin is inert with no --resume at all" {
  run pin "$A" --model m -p hi
  [[ "$output" == *"ARGS=[--model m -p hi]"* ]] || return 1
  [[ "$output" != *"CFG=[$B]"* ]] || return 1
}

@test "pin fails OPEN on an unresolvable id so Claude prints its own error" {
  run pin "$A" --resume deadbeef-0000-4000-8000-000000000000
  [ "$status" -eq 0 ]
  [[ "$output" == *"ARGS=[--resume deadbeef-0000-4000-8000-000000000000]"* ]] || return 1
  [[ "$output" != *"CFG=[$B]"* ]] || return 1
}

@test "CC_RESUME_NO_RESOLVE=1 disables the pin entirely" {
  mkdir -p "$BATS_TEST_TMPDIR/wt-x"
  mkses "$B" "$BATS_TEST_TMPDIR/wt-x" "$SID1"
  export CC_RESUME_NO_RESOLVE=1
  run pin "$A" --resume "$SID1"
  [[ "$output" != *"CFG=[$B]"* ]] || return 1
  [[ "$output" == *"ARGS=[--resume $SID1]"* ]] || return 1
}

@test "pin recreates a reaped worktree path so the transcript can still load" {
  mkses "$B" "$BATS_TEST_TMPDIR/wt-gone" "$SID1"
  [ ! -d "$BATS_TEST_TMPDIR/wt-gone" ]
  run pin "$A" --resume "$SID1"
  [[ "$output" == *"CWD=[$BATS_TEST_TMPDIR/wt-gone]"* ]] || return 1
  [ -d "$BATS_TEST_TMPDIR/wt-gone" ]
}

@test "CC_RESUME_MKDIR=0 refuses to recreate a reaped worktree and pins no cwd" {
  mkses "$B" "$BATS_TEST_TMPDIR/wt-gone2" "$SID1"
  export CC_RESUME_MKDIR=0
  run pin "$A" --resume "$SID1"
  [ ! -d "$BATS_TEST_TMPDIR/wt-gone2" ]
  [[ "$output" != *"CWD=[$BATS_TEST_TMPDIR/wt-gone2]"* ]] || return 1
}

@test "pin does not treat a --resume value that is another flag as a session id" {
  run pin "$A" --resume --fork-session
  [[ "$output" == *"ARGS=[--resume --fork-session]"* ]] || return 1
}

# ── the shell the launchers actually run in ─────────────────────────────────────────────

@test "under real zsh: the pin emits NOTHING on stdout and rewrites the right argv slot" {
  # This suite runs under bash, and the two defects that mattered here are zsh-only: zsh arrays
  # are 1-indexed (a wrong index corrupts argv) and `local x` on an existing name PRINTS it (one
  # leaked line of argv per loop iteration, straight into the launcher's stdout). Neither can
  # fail a bash test, so the guard has to be an actual zsh run.
  command -v zsh >/dev/null || skip "zsh not installed"
  mkdir -p "$BATS_TEST_TMPDIR/wt-x"
  mkses "$B" "$BATS_TEST_TMPDIR/wt-x" "$SID1"
  cat > "$BATS_TEST_TMPDIR/probe.zsh" <<ZSH
source "$SHLIB"
export CC_RESUME_RESOLVE_BIN="$RESOLVE" CC_RESUME_STORES="$A:$B"
_cc_resume_pin "$A" --model m --resume "${SID1:0:8}" -p hi 2>/dev/null
print -r -- "ARGS=[\${CC_RESUME_ARGS[*]}]"
print -r -- "CFG=[\$CC_RESUME_CFG]"
ZSH
  run zsh -f "$BATS_TEST_TMPDIR/probe.zsh"
  [ "$status" -eq 0 ]
  # Exactly two lines: anything else is the `local` leak writing argv to stdout.
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" = "2" ]
  [[ "$output" == *"ARGS=[--model m --resume $SID1 -p hi]"* ]] || return 1
  [[ "$output" == *"CFG=[$B]"* ]] || return 1
}
