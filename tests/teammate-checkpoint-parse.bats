#!/usr/bin/env bats
#
# teammate-checkpoint.sh — the PARSE + ABSTAIN path (HOOK_CHAIN_COST.md §2.5, remainder R-2).
#
# WHAT THIS FILE EXISTS TO PIN. This hook is registered on the match-all PostToolUse matcher, so
# its abstain path runs on every tool call of every session. It used to spend 9 external execs
# discovering it had nothing to do (`cat`, 5x `jq` over ONE payload, `git rev-parse`, the GC
# damper's `find`, `cat` of the counter); it now spends 2. Nothing in teammate-checkpoint-gc.bats
# could see that change — every one of its 13 cases fires Stop, which is the path that DOES work —
# so without this file the whole R-2 saving is unpinned and the next edit silently re-adds forks.
#
# Harness laws, inherited from teammate-checkpoint-gc.bats and extended:
#   L1  real repos, real `git`, real payloads built by `jq -n` — never a hand-written JSON string
#       whose escaping is the thing under test.
#   L2  every case asserts a CONSEQUENCE (a ref exists / a count is bounded), never that two
#       copies of a formula agree — the vacuous-pass trap that file documents.
#   L3  a shim resolves its real binary to an ABSOLUTE path BEFORE shadowing, and asserts it. A
#       bare name in a shim re-execs the SHIM: infinite recursion, which presents as a hung test
#       rather than a failing one. (Cost this session ~4 min of wall clock to diagnose: under zsh
#       `command -v find` returns a FUNCTION name, not a path.)
#   L4  the fast path's guard has a fixture that makes the fast path WRONG, so deleting the guard
#       goes red rather than merely unmeasured.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/teammate-checkpoint.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/watchdog" "$HOME/.claude/logs"
  WD="$HOME/.claude/watchdog"
  WT="$BATS_TEST_TMPDIR/wt-team-alice"
  mkdir -p "$WT"
  git -C "$WT" init -q
  printf 'seed\n' > "$WT/seed.txt"
  git -C "$WT" add -A >/dev/null
  git -c user.email=t@t -c user.name=t -C "$WT" commit -qm seed >/dev/null
}

payload() { # <event> [cwd] [sid]
  jq -nc --arg e "$1" --arg c "${2:-$WT}" --arg s "${3:-sid-parse}" \
    '{session_id:$s,hook_event_name:$e,tool_name:"Bash",cwd:$c}'
}
fire()   { payload "${1:-Stop}" "${2:-$WT}" "${3:-sid-parse}" | bash "$HOOK" >/dev/null 2>&1; }
dirty()  { printf 'work %s\n' "${1:-1}" > "$WT/new.txt"; }
has_cp() { git -C "${2:-$WT}" show-ref --verify --quiet "refs/wip/$1/LAST"; }

# Build a counting shim dir for the named externals. Absolute-resolution is asserted (L3).
mkshim() { # <dir> <logfile> <binary>...
  local dir="$1" log="$2" b real; shift 2
  mkdir -p "$dir"
  for b in "$@"; do
    real="$(PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin command -v "$b")"
    case "$real" in /*) ;; *) echo "harness: '$b' -> '${real:-empty}' is not absolute" >&2; return 1 ;; esac
    cat > "$dir/$b" <<SHIM
#!/bin/bash
printf '%s %s\n' '$b' "\$*" >> '$log'
exec '$real' "\$@"
SHIM
    chmod +x "$dir/$b"
  done
}

# ── equivalence: the batched parse must read the same three fields the per-field form did ───────

@test "an ordinary payload still checkpoints under the member from the path" {
  dirty
  fire Stop
  has_cp team-alice
}

@test "an explicit teammate_name in the payload still wins over the path" {
  dirty
  jq -nc --arg c "$WT" '{session_id:"s",hook_event_name:"Stop",cwd:$c,teammate_name:"zoe"}' \
    | bash "$HOOK" >/dev/null 2>&1
  has_cp zoe
}

@test "a team_name prefix is still stripped from the basename" {
  dirty
  jq -nc --arg c "$WT" '{session_id:"s",hook_event_name:"Stop",cwd:$c,team_name:"team"}' \
    | bash "$HOOK" >/dev/null 2>&1
  has_cp alice
}

# ── L4: the control that makes the batched parse safe rather than merely fast ────────────────────

@test "GUARD: a cwd containing a NEWLINE still checkpoints (batched split would truncate it)" {
  # The newline lives in a PARENT component, so the basename — and therefore the ref name, which
  # git will not accept with a newline in it — stays clean. Splitting one jq's output on newlines
  # hands CWD only "<tmp>/pa", which is not a repo, so an unguarded hook abstains and this goes RED.
  local parent="$BATS_TEST_TMPDIR/pa"$'\n'"rent" nlwt
  nlwt="$parent/wt-team-nl"
  mkdir -p "$nlwt"
  git -C "$nlwt" init -q
  printf 'seed\n' > "$nlwt/seed.txt"
  git -C "$nlwt" add -A >/dev/null
  git -c user.email=t@t -c user.name=t -C "$nlwt" commit -qm seed >/dev/null
  printf 'dirty\n' > "$nlwt/new.txt"
  # precondition: the truncated prefix really is NOT a repo, or this case proves nothing
  run git -C "$BATS_TEST_TMPDIR/pa" rev-parse --git-common-dir
  [ "$status" -ne 0 ]

  payload Stop "$nlwt" sid-nl | bash "$HOOK" >/dev/null 2>&1
  has_cp team-nl "$nlwt"
}

@test "malformed JSON abstains cleanly instead of crashing" {
  run bash -c "printf '%s' 'not json at all' | bash '$HOOK'"
  [ "$status" -eq 0 ]
}

@test "an empty payload abstains cleanly" {
  run bash -c "printf '' | bash '$HOOK'"
  [ "$status" -eq 0 ]
}

# ── the counter, now read by a builtin ──────────────────────────────────────────────────────────

@test "a corrupt counter file does not abort the hook — it re-counts from zero" {
  printf 'not-a-number\n' > "$WD/cp-sid-parse.count"
  dirty
  run bash -c "$(declare -f payload); WT='$WT'; payload PostToolUse '$WT' sid-parse | bash '$HOOK'"
  [ "$status" -eq 0 ]
  read -r n < "$WD/cp-sid-parse.count"
  [ "$n" = "1" ]
}

@test "the counter still drives the every-N snapshot" {
  dirty
  for _ in 1 2 3 4; do fire PostToolUse; done
  run has_cp team-alice
  [ "$status" -ne 0 ]          # 4 calls: not yet
  fire PostToolUse             # 5th trips EVERY=5
  has_cp team-alice
}

# ── the R-2 contract itself: what the abstain path is allowed to spend ──────────────────────────

@test "R-2: an abstaining call spends at most 3 external execs" {
  local shim="$BATS_TEST_TMPDIR/shim-x" log="$BATS_TEST_TMPDIR/x.log"
  mkshim "$shim" "$log" jq git find cat date basename grep shasum head tr cut sed awk
  for _ in 1 2 3; do fire PostToolUse; done   # warm; the 4th call abstains (4 % 5 != 0)
  : > "$log"
  PATH="$shim:$PATH" fire PostToolUse
  local n; n="$(grep -c . "$log" || true)"
  # A CEILING, not an equality: this must red when a future edit ADDS a fork, and must not red
  # merely because one was removed. Pre-fix this path spent 9 and would fail at any ceiling here.
  [ "$n" -le 3 ]
  # ...and it must still be doing its job, not exiting early by accident
  [ -f "$WD/cp-sid-parse.count" ]
}

@test "R-2: an abstaining call never parses .team_name or .teammate_name" {
  local shim="$BATS_TEST_TMPDIR/shim-j" log="$BATS_TEST_TMPDIR/j.log"
  mkshim "$shim" "$log" jq
  for _ in 1 2 3; do fire PostToolUse; done
  : > "$log"
  PATH="$shim:$PATH" fire PostToolUse
  [ "$(grep -c 'team_name' "$log" || true)" -eq 0 ]
  # the SAME probe must see them on the snapshot path, or this case would pass on a hook that
  # never reads those fields at all (which would break teammate naming and go undetected here)
  dirty
  : > "$log"
  PATH="$shim:$PATH" fire Stop
  [ "$(grep -c 'team_name' "$log" || true)" -ge 1 ]
}

@test "R-2: the GC damper's find is not on the abstain path, but Stop still reaches the GC" {
  local shim="$BATS_TEST_TMPDIR/shim-f" log="$BATS_TEST_TMPDIR/f.log"
  mkshim "$shim" "$log" find
  for _ in 1 2 3; do fire PostToolUse; done
  : > "$log"
  PATH="$shim:$PATH" fire PostToolUse
  [ "$(grep -c . "$log" || true)" -eq 0 ]     # abstain: no damper fork at all
  : > "$log"
  PATH="$shim:$PATH" fire Stop
  [ "$(grep -c . "$log" || true)" -ge 1 ]     # Stop: the sweep is still reachable
}

# ── the dirty-tree gate, at a size the published SIGPIPE floors do not describe ──────────────────
#
# Every case above dirties the tree with ONE small file, and every one of them stays GREEN over the
# defect these two exist to catch — which is exactly why it shipped. The gate at :251 used to read
# `status --porcelain | grep -q .`; on a large dirty tree grep -q leaves at line 1, `git status`
# takes SIGPIPE, pipefail promotes it and the leading `!` sends a DIRTY tree down the "tree clean"
# branch, skipping the snapshot. A one-file fixture never reaches that regime.
#
# L5 (extending the harness laws above): a fixture for a size-dependent failure must ASSERT it
# reached the regime. A case named after a floor it never crosses is a control that cannot fail.

# Build a repo whose `git status --porcelain` crosses the regime, by MODIFYING tracked files —
# untracked ones collapse to a single `?? src/` line and could never get there. Long names buy the
# byte count with few files: ~166 B per porcelain line, so 250 files clear 40,000 B in ~1 commit.
mkbig() { # <dir> [files]
  local d="$1"
  local n="${2:-250}"
  local i=0 pad
  pad="$(printf '%0150d' 0)"
  mkdir -p "$d/src"
  git -C "$d" init -q
  while [ "$i" -lt "$n" ]; do printf 'seed\n' > "$d/src/f-$i-$pad.txt"; i=$((i+1)); done
  git -C "$d" add -A >/dev/null
  git -c user.email=t@t -c user.name=t -C "$d" commit -qm seed >/dev/null
}
dirtybig() { # <dir>
  local f
  for f in "$1"/src/*.txt; do printf 'changed\n' >> "$f"; done
}
porcbytes() { git -C "$1" status --porcelain | wc -c | tr -d ' '; }

@test "MECHANISM: a dirty tree past the measured always-inverted floor still checkpoints" {
  local BIG="$BATS_TEST_TMPDIR/wt-team-big"
  mkbig "$BIG"
  dirtybig "$BIG"
  # ANTI-VACUITY, and the number is chosen rather than inherited. 30,000 B is where THIS producer —
  # `git status --porcelain`, which must walk the tree before it can write — was measured 20/20
  # inverted (19/20 at 25,500). It is NOT 37,121: that figure was taken on a producer holding its
  # whole output in memory, able to write the instant the pipeline forks, and it does not describe
  # this shape. Past the always-inverted point a re-introduced `grep -q` fails EVERY run rather
  # than one in twenty, so this case is deterministic by construction.
  local b
  b="$(porcbytes "$BIG")"
  [ "$b" -ge 30000 ] || { echo "fixture is $b B, under the 30,000 B always-inverted floor — it cannot discriminate" >&2; return 1; }
  fire Stop "$BIG"
  has_cp team-big "$BIG"
}

@test "NEG: a clean tree of the same size still makes no checkpoint" {
  local BIG="$BATS_TEST_TMPDIR/wt-team-clean"
  mkbig "$BIG"
  # Same machinery, NOT dirtied. Without this the case above would pass on a hook that snapshotted
  # unconditionally — the other way to be wrong about the same predicate, and one a red count alone
  # cannot distinguish from a correct fix.
  [ "$(porcbytes "$BIG")" -eq 0 ]
  fire Stop "$BIG"
  run has_cp team-clean "$BIG"
  [ "$status" -ne 0 ]
}
