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

# ── a missing cwd: parked, removed with a tombstone, or neither (DESIGN load-root-cause §3.5) ──
# A throwaway repo with linked worktrees, HOME and every WT_* store under the tmpdir. The transcript
# store A doubles as the tombstone's config root, so the row's `sids` come from these fixtures.

SID2=22222222-bbbb-4ccc-8ddd-222222222222

lab() {
  T="$(cd -P "$BATS_TEST_TMPDIR" && pwd -P)"
  A="$T/store-a"; B="$T/store-b"; mkdir -p "$A/projects" "$B"
  export CC_RESUME_STORES="$A:$B"
  export GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
  unset WT_TRUNK WT_NOW CC_WTGC_DISPOSAL_LOG _WT_TOMBSTONE_SH _WT_PARK_SH
  export WT_LEDGER="$T/ledger.jsonl" WT_TOMB_DIR="$T/tombs" WT_STATE_DIR="$T/state" \
         WT_CONFIG_ROOTS="$A" WT_RESUME_REAPED="$T/resume-reaped.jsonl" WT_PARK_ROOT="$T/parked"
  export WT_EVENTS_FILE="$WT_STATE_DIR/wt-events.jsonl" WT_WAKE_FILE="$WT_STATE_DIR/worktree-gc.wake" \
         WT_PARK_INDEX="$WT_STATE_DIR/wt-parked"
  export PATH="$REPO/bin:$PATH"
  git init -q --bare -b main "$T/origin.git"
  git init -q -b main "$T/main"
  printf '.env*\nout/\n' > "$T/main/.gitignore"; echo base > "$T/main/f.txt"
  git -C "$T/main" add -A; git -C "$T/main" commit -qm base
  git -C "$T/main" remote add origin "$T/origin.git"; git -C "$T/main" push -q -u origin main
  git -C "$T/main" remote set-head origin main
}

# labses <cwd> <sid> <gitBranch> — a transcript in store A recording cwd and gitBranch
labses() {
  local d; d="$A/projects/$(printf '%s' "$1" | sed 's#[/.]#-#g')"
  mkdir -p "$d"
  printf '{"type":"user","cwd":"%s","gitBranch":"%s","sessionId":"%s"}\n' "$1" "$3" "$2" > "$d/$2.jsonl"
}

# labwt <name> → a linked worktree on branch <name> with a commit and ignored residue
labwt() {
  local w="$T/wts/$1"
  git -C "$T/main" worktree add -q -b "$1" "$w" main
  echo one > "$w/one.txt"; git -C "$w" add one.txt; git -C "$w" commit -qm one
  echo 'SECRET=1' > "$w/.env.local"; mkdir -p "$w/out"; echo data > "$w/out/data.bin"
  printf '%s' "$w"
}

key() { printf '%s\n' "$output" | sed -n "s/^$1=//p"; }

@test "resolver: a removed tree whose tombstone holds the sid ⇒ tomb_* keys" {
  lab
  w="$(labwt feat)"; labses "$w" "$SID1" feat
  head="$(git -C "$w" rev-parse HEAD)"
  id="$(wt-tombstone tombstone "$w" lab test)"
  git -C "$T/main" worktree remove "$w"
  run "$RESOLVE" "$SID1"
  [ "$status" -eq 0 ]
  [ "$(key cwd_exists)" = 0 ]
  [ "$(key tomb_state)" = detached ]
  [ "$(key tomb_id)" = "$id" ]
  [ "$(key tomb_repo)" = "$T/main" ]
  [ "$(key tomb_branch)" = feat ]
  [ "$(key tomb_head)" = "$head" ]
  [ "$(key tomb_preserved)" = 2 ]
  [ "$(key tomb_files)" -ge 4 ]          # .gitignore f.txt one.txt + the two residue files
  [ -z "$(key parked)" ]
}

@test "resolver: a different sid AND a different branch on the same path ⇒ no tomb_* keys (pool re-let)" {
  lab
  w="$(labwt other)"; labses "$w" "$SID2" other
  wt-tombstone tombstone "$w" lab test >/dev/null
  git -C "$T/main" worktree remove "$w"
  labses "$w" "$SID1" feat               # a later tenant of the same path, written after the removal
  run "$RESOLVE" "$SID1"
  [ "$status" -eq 0 ]
  [ "$(key cwd_exists)" = 0 ]
  [ -z "$(key tomb_state)" ] && [ -z "$(key tomb_id)" ]
  run "$RESOLVE" "$SID2"                 # control: the row is there for its own session
  [ "$(key tomb_state)" = detached ]
}

@test "resolver: a parked path ⇒ parked=1 + parked_path, with no sid or branch match needed" {
  lab
  w="$(labwt pk)"
  parked="$(wt-tombstone park "$w" lab test --arm ii)"
  [ ! -e "$w" ] && [ -d "$parked" ]
  labses "$w" "$SID1" unrelated          # written after the park: the index has never heard of this sid
  run "$RESOLVE" "$SID1"
  [ "$status" -eq 0 ]
  [ "$(key cwd_exists)" = 0 ]
  [ "$(key parked)" = 1 ]
  [ "$(key parked_path)" = "$parked" ]
  [ -z "$(key tomb_state)" ]
}

@test "pin: a parked cwd comes back by unpark — status --ignored and reflog identical, row 'unparked'" {
  lab
  w="$(labwt pk)"; labses "$w" "$SID1" pk
  git -C "$w" status --porcelain --ignored > "$T/status.before"
  git -C "$w" reflog > "$T/reflog.before"
  wt-tombstone park "$w" lab test --arm i >/dev/null
  [ ! -e "$w" ]
  cd "$T"
  run --separate-stderr pin "$A" --resume "$SID1"
  [ "$status" -eq 0 ] || { echo "$stderr"; false; }
  [[ "$output" == *"CWD=[$w]"* ]] || return 1
  [ "$(git -C "$w" rev-parse --abbrev-ref HEAD)" = pk ]
  git -C "$w" status --porcelain --ignored | diff "$T/status.before" -
  git -C "$w" reflog | diff "$T/reflog.before" -
  [ "$(jq -r .outcome "$WT_RESUME_REAPED")" = unparked ]
  [ "$(jq -r .sid "$WT_RESUME_REAPED")" = "$SID1" ]
}

@test "under real zsh: a parked cwd unparks and the pin still emits nothing on stdout" {
  command -v zsh >/dev/null || skip "zsh not installed"
  lab
  w="$(labwt pkz)"; labses "$w" "$SID1" pkz
  wt-tombstone park "$w" lab test --arm i >/dev/null
  cat > "$T/probe.zsh" <<ZSH
source "$SHLIB"
cd "$T"
_cc_resume_pin "$A" --resume "$SID1" 2>/dev/null
print -r -- "CWD=[\$CC_RESUME_CWD]"
ZSH
  run zsh -f "$T/probe.zsh"
  [ "$status" -eq 0 ]
  [ "$output" = "CWD=[$w]" ]
  [ "$(git -C "$w" rev-parse --abbrev-ref HEAD)" = pkz ]
}

@test "RED control: the pre-change lib on a parked cwd leaves an EMPTY dir at the path" {
  lab
  git -C "$REPO" show 7fa90e0c2:lib/cc-resume-shell.sh > "$T/old-shell.sh"
  w="$(labwt pk)"; labses "$w" "$SID1" pk
  wt-tombstone park "$w" lab test --arm i >/dev/null
  cd "$T"
  SHLIB="$T/old-shell.sh" run pin "$A" --resume "$SID1"
  [ -d "$w" ]
  [ -z "$(ls -A "$w")" ]                 # the tree is still parked; the session would land in an empty dir
}

@test "pin: a detached tombstone with no terminal ⇒ empty dir, the restore command printed, row 'recreated-empty'" {
  lab
  w="$(labwt gone)"; labses "$w" "$SID1" gone
  wt-tombstone tombstone "$w" lab test >/dev/null
  git -C "$T/main" worktree remove "$w"
  cd "$T"
  run --separate-stderr pin "$A" --resume "$SID1" < /dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *"CWD=[$w]"* ]] || return 1
  [ -d "$w" ] && [ -z "$(ls -A "$w")" ]
  [[ "$stderr" == *"cc-wt-restore $w --sid $SID1"* ]] || return 1
  [ "$(jq -r .outcome "$WT_RESUME_REAPED")" = recreated-empty ]
}

@test "pin: no tombstone and not parked ⇒ stderr and stdout byte-identical to the pre-change lib" {
  lab
  git -C "$REPO" show 7fa90e0c2:lib/cc-resume-shell.sh > "$T/old-shell.sh"
  w="$T/wts/never"; labses "$w" "$SID1" never
  cd "$T"
  SHLIB="$T/old-shell.sh" run --separate-stderr pin "$A" --resume "$SID1" < /dev/null
  old_out="$output" old_err="$stderr"
  [ -d "$w" ]; rmdir "$w"
  run --separate-stderr pin "$A" --resume "$SID1" < /dev/null
  [ "$output" = "$old_out" ]
  [ "$stderr" = "$old_err" ]
  [ -d "$w" ]
  [ "$(jq -r .outcome "$WT_RESUME_REAPED")" = recreated-empty ]
}
