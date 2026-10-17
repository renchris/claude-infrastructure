#!/usr/bin/env bats
# ~/.claude/autonomy/worktree-gc-repos.promoted has ONE writer: the operator (OP-5, DESIGN
# load-root-cause-2026-10-17 §3.4). A repo listed there lets the worktree-gc wake run and its 04:15
# backstop ACT on that repo's worktrees (park, detach, lock) instead of only logging would_*. So an
# agent or script that appended a line would promote a repo nobody reviewed — the review of its
# observe log is the whole safety stage. Shipped code may only READ the file.
#
# This greps every shipped source tree for a write to the file, by name or through the variable
# scripts/lib/wtgc-scope.sh reads it into, and asserts there is none. The positive controls run the
# SAME function over fixtures that do write it, so a grep that silently matches nothing is RED.
# Read-only: no file under the repo is written; fixtures live in $BATS_TEST_TMPDIR.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  # hermetic even though nothing here reads ~: a grep over the repo must never see the live layer
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
}

# The target token: the file's name, or the variables that hold its path.
_T='(worktree-gc-repos\.promoted|\$\{?(CC_)?WTGC_PROMOTED_FILE\}?)'

# promoted_writers <path>... → prints file:line for every write to the promoted file; rc 0 always.
promoted_writers() {
  grep -rnE \
    -e ">>?[[:space:]]*[\"']?[^[:space:]\"']*$_T" \
    -e "(^|[^[:alnum:]_])tee([[:space:]]+-[a-z]+)*[[:space:]]+[^|;&]*$_T" \
    -e "(^|[^[:alnum:]_])(mv|cp|install|ln)[[:space:]][^|;&]*$_T[\"']?[[:space:]]*(\$|[;&|)#])" \
    -e "open\(.*$_T.*,[[:space:]]*[\"'][^\"']*[wax+]" \
    -e "open\(.*$_T.*\)\.write" \
    -e "(write_text|write_bytes)\(" \
    "$@" 2>/dev/null \
    | grep -E "$_T" || true
}

@test "no shipped source writes the promoted file (OP-5: the operator is its only writer)" {
  local roots=() d
  for d in scripts hooks bin docs/activation migrations launchd; do
    [ -d "$REPO_ROOT/$d" ] && roots+=("$REPO_ROOT/$d")
  done
  [ "${#roots[@]}" -ge 5 ]                       # the scan reached the trees it names
  run promoted_writers "${roots[@]}"
  [ "$status" -eq 0 ]
  [ -z "$output" ] || { printf 'writer(s) found:\n%s\n' "$output"; false; }
}

@test "the scan sees the shipped READER (it is not grepping an empty tree)" {
  grep -q 'worktree-gc-repos.promoted' "$REPO_ROOT/scripts/lib/wtgc-scope.sh"
  # …and the reader itself is not a writer.
  run promoted_writers "$REPO_ROOT/scripts/lib/wtgc-scope.sh"
  [ -z "$output" ]
}

@test "POSITIVE CONTROL: every write shape is caught by the same function" {
  F="$BATS_TEST_TMPDIR/writers"; mkdir -p "$F"
  printf '%s\n' 'echo /r >> ~/.claude/autonomy/worktree-gc-repos.promoted' > "$F/append.sh"
  printf '%s\n' 'printf x > "$HOME/.claude/autonomy/worktree-gc-repos.promoted"' > "$F/trunc.sh"
  printf '%s\n' 'echo /r | tee -a "$WTGC_PROMOTED_FILE" >/dev/null' > "$F/tee.sh"
  printf '%s\n' 'mv "$tmp" "$HOME/.claude/autonomy/worktree-gc-repos.promoted"' > "$F/mv.sh"
  printf '%s\n' 'cp /tmp/list ${CC_WTGC_PROMOTED_FILE}' > "$F/cp.sh"
  printf '%s\n' "open(os.path.expanduser('~/.claude/autonomy/worktree-gc-repos.promoted'), 'a').write(r)" > "$F/py.py"
  printf '%s\n' 'echo "$root" >>"$WTGC_PROMOTED_FILE"' > "$F/var.sh"
  run promoted_writers "$F"
  for f in append.sh trunc.sh tee.sh mv.sh cp.sh py.py var.sh; do
    printf '%s\n' "$output" | grep -q "$f:" || { echo "MISSED $f"; false; }
  done
}

@test "NEGATIVE CONTROL: reads and mentions are not writes" {
  F="$BATS_TEST_TMPDIR/readers"; mkdir -p "$F"
  printf '%s\n' 'done < "$WTGC_PROMOTED_FILE"' > "$F/read.sh"
  printf '%s\n' '[ -r "$WTGC_PROMOTED_FILE" ] || return 1' > "$F/test.sh"
  printf '%s\n' 'cp ~/.claude/autonomy/worktree-gc-repos.promoted /tmp/backup' > "$F/cp-from.sh"
  printf '%s\n' '# ~/.claude/autonomy/worktree-gc-repos.promoted  one absolute git common dir per line' > "$F/doc.sh"
  printf '%s\n' "open(os.path.expanduser('~/.claude/autonomy/worktree-gc-repos.promoted')).read()" > "$F/py.py"
  run promoted_writers "$F"
  [ -z "$output" ] || { printf 'false positive(s):\n%s\n' "$output"; false; }
}
