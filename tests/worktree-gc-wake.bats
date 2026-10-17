#!/usr/bin/env bats
# scripts/worktree-gc-wake.sh — the event-driven worktree janitor run (DESIGN load-root-cause-2026-10-17
# §3.4 "How a wake run evaluates", WP-15).
#
# What is pinned: the idle tick forks no janitor and writes no log row; the repo-scope table decides
# --dry-run (observe unless the mode is act AND the repo is home or promoted; reso never evaluated);
# no branch prune or landed-dirt disposal ever rides along; clock KEEPs are requeued and terminal
# verdicts dequeued; a newer event resets the grace; a burst is debounced. One end-to-end case runs
# the REAL worktree-gc.sh in observe mode and proves the worktree list is unchanged.
#
# Hermetic: HOME, every WT_* and CC_WTGC_* seam, and every repo live under $BATS_TEST_TMPDIR. The
# janitor is a stub (it records its argv and env, and prints one decision line per --path from a
# template) except in the end-to-end case. WT_NOW pins the wake run's clock.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  WAKE="$REPO/scripts/worktree-gc-wake.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  ST="$HOME/.claude/state"; mkdir -p "$ST"
  export WT_STATE_DIR="$ST"
  export WT_EVENTS_FILE="$ST/wt-events.jsonl"
  export WT_WAKE_FILE="$ST/worktree-gc.wake"
  export WT_PARK_INDEX="$ST/wt-parked"
  export WT_PARK_ROOT="$BATS_TEST_TMPDIR/parked"
  export WT_LEDGER="$BATS_TEST_TMPDIR/ledger.jsonl"
  export WT_TOMB_DIR="$BATS_TEST_TMPDIR/tombs"
  export CC_WT_TOMBSTONE_LIB="$REPO/scripts/lib/wt-tombstone.sh"
  export CC_WTGC_WAKE_LOG="$BATS_TEST_TMPDIR/wake.log"
  export CC_WTGC_EVENTS_MODE_FILE="$BATS_TEST_TMPDIR/events.mode"
  export CC_WTGC_PROMOTED_FILE="$BATS_TEST_TMPDIR/promoted"
  export CC_WTGC_WAKE_DEBOUNCE_S=0
  unset WTGC_EVENTS CC_WTGC_GRACE_S CC_WTGC_SCOPE_EXCLUDE
  # Relative to the real clock (an absolute stamp drifts in meaning as the calendar advances).
  export WT_NOW; WT_NOW="$(date +%s)"
  OLD_TS="$(date -u -r $((WT_NOW - 30 * 86400)) +%Y-%m-%dT%H:%M:%SZ)"   # well past a 24 h grace at WT_NOW
  NOW_TS="$(date -u -r "$WT_NOW" +%Y-%m-%dT%H:%M:%SZ)"                  # == WT_NOW: not due for another 24 h

  # The stub janitor: argv one per line, then its env, then "---"; one decision line per --path.
  STUB_LOG="$BATS_TEST_TMPDIR/stub.calls"
  export STUB_LOG STUB_LINE='KEEP    %s [b] — LIVE — a registered session / running claude is cwd'"'"'d here'
  export CC_WTGC_INFRA_GC="$BATS_TEST_TMPDIR/stub-gc.sh"
  cat > "$CC_WTGC_INFRA_GC" <<'SH'
#!/bin/bash
want=0
{ for a in "$@"; do printf 'arg %s\n' "$a"; done
  printf 'env CC_WTGC_REPO=%s\nenv CC_WTGC_TRUNK=%s\n---\n' "${CC_WTGC_REPO:-}" "${CC_WTGC_TRUNK:-}"; } >> "$STUB_LOG"
for a in "$@"; do
  if [ "$want" = 1 ]; then printf "$STUB_LINE\n" "$a"; want=0; continue; fi
  [ "$a" = --path ] && want=1
done
exit 0
SH
  chmod +x "$CC_WTGC_INFRA_GC"

  HOMEREPO="$(mkrepo claude-infrastructure)"
  export CC_WTGC_INFRA_REPO="$HOMEREPO"
}

# mkrepo <name> → a clone of a throwaway bare origin (so refs/remotes/origin/HEAD exists); prints it.
mkrepo() {
  local o="$BATS_TEST_TMPDIR/origins/$1.git" c="$BATS_TEST_TMPDIR/repos/$1" s="$BATS_TEST_TMPDIR/seed-$1"
  mkdir -p "${o%/*}" "${c%/*}"
  git init -q -b main "$s" && git -C "$s" -c user.email=t@t -c user.name=t commit -q --allow-empty -m seed
  git clone -q --bare "$s" "$o" && git clone -q "$o" "$c"
  git -C "$c" config user.email t@t; git -C "$c" config user.name t
  (cd -P "$c" && pwd -P)
}
# mkwt <repo> <name> → a linked worktree on its own branch; prints its physical path.
mkwt() {
  local p="$BATS_TEST_TMPDIR/wts/$2"
  mkdir -p "${p%/*}"
  git -C "$1" worktree add -q -b "$2" "$p" >/dev/null 2>&1
  (cd -P "$p" && pwd -P)
}
emit() { # <path> [ts] [ev]
  printf '{"ev":"%s","path":"%s","sid":"s1","repo":null,"ts":"%s"}\n' "${3:-session-end}" "$1" "${2:-$OLD_TS}" \
    >> "$WT_EVENTS_FILE"
}
calls() { if [ -f "$STUB_LOG" ]; then grep -c "^---\$" "$STUB_LOG"; else echo 0; fi; }
wake() { run /bin/bash "$WAKE" </dev/null; }   # launchd runs /bin/bash 3.2

@test "1: nothing due — exit 0, the janitor is never forked, and no log row is written" {
  wake
  [ "$status" -eq 0 ] || { echo "empty queue: rc=$status $output"; false; }
  local wt; wt="$(mkwt "$HOMEREPO" wt-a)"
  emit "$wt" "$NOW_TS"                      # queued, but its grace has 24 h to run
  wake
  [ "$status" -eq 0 ] || { echo "not-due: rc=$status $output"; false; }
  [ "$(calls)" = 0 ] || { echo "the janitor ran with nothing due: $(cat "$STUB_LOG")"; false; }
  [ ! -s "$CC_WTGC_WAKE_LOG" ] || { echo "an idle tick wrote a log row: $(cat "$CC_WTGC_WAKE_LOG")"; false; }
  run cut -f1 "$ST/wt-queue.tsv"
  [ "$output" = "$wt" ] || { echo "the event was not queued: '$output'"; false; }
}

@test "2: home repo, mode observe — one run WITH --dry-run --park-first --path, nothing whole-repo" {
  local wt; wt="$(mkwt "$HOMEREPO" wt-a)"
  emit "$wt"
  wake
  [ "$status" -eq 0 ] || { echo "rc=$status $output"; false; }
  [ "$(calls)" = 1 ] || { echo "expected 1 janitor run, got $(calls)"; false; }
  grep -qx 'arg --dry-run' "$STUB_LOG" || { echo "observe ran WITHOUT --dry-run: $(cat "$STUB_LOG")"; false; }
  grep -qx 'arg --park-first' "$STUB_LOG" || { echo "no --park-first: $(cat "$STUB_LOG")"; false; }
  grep -qx "arg $wt" "$STUB_LOG" || { echo "the path was not passed: $(cat "$STUB_LOG")"; false; }
  ! grep -q 'prune-branches\|dispose-landed-dirt' "$STUB_LOG" || { echo "a whole-repo flag rode along"; false; }
  grep -qx 'env CC_WTGC_TRUNK=origin/main' "$STUB_LOG" || { echo "home trunk not origin/main: $(cat "$STUB_LOG")"; false; }
  grep -q "mode=observe repo=claude-infrastructure decision=would_keep path=$wt " "$CC_WTGC_WAKE_LOG" \
    || { echo "no per-path row: $(cat "$CC_WTGC_WAKE_LOG")"; false; }
  grep -q 'verdict=ok due=1 evaluated=1 dequeued=1 requeued=0 mode=observe' "$CC_WTGC_WAKE_LOG" \
    || { echo "summary row: $(cat "$CC_WTGC_WAKE_LOG")"; false; }
}

@test "3: home repo, WTGC_EVENTS=act — no --dry-run" {
  local wt; wt="$(mkwt "$HOMEREPO" wt-a)"
  emit "$wt"
  WTGC_EVENTS=act wake
  [ "$(calls)" = 1 ] || { echo "expected 1 janitor run, got $(calls)"; false; }
  ! grep -qx 'arg --dry-run' "$STUB_LOG" || { echo "act mode still passed --dry-run"; false; }
  grep -q "mode=act .*decision=kept path=$wt " "$CC_WTGC_WAKE_LOG" || { echo "row: $(cat "$CC_WTGC_WAKE_LOG")"; false; }
}

@test "4: a foreign UNPROMOTED repo under act is still --dry-run" {
  local fr wt; fr="$(mkrepo other-repo)"; wt="$(mkwt "$fr" wt-f)"
  emit "$wt"
  WTGC_EVENTS=act wake
  [ "$(calls)" = 1 ] || { echo "expected 1 janitor run, got $(calls)"; false; }
  grep -qx 'arg --dry-run' "$STUB_LOG" || { echo "an unpromoted foreign repo ran for real: $(cat "$STUB_LOG")"; false; }
  grep -qx "env CC_WTGC_REPO=$fr" "$STUB_LOG" || { echo "repo env: $(cat "$STUB_LOG")"; false; }
}

@test "5: a foreign PROMOTED repo under act runs without --dry-run" {
  local fr wt; fr="$(mkrepo other-repo)"; wt="$(mkwt "$fr" wt-f)"
  printf '%s\n' "$fr" > "$CC_WTGC_PROMOTED_FILE"
  emit "$wt"
  WTGC_EVENTS=act wake
  [ "$(calls)" = 1 ] || { echo "expected 1 janitor run, got $(calls)"; false; }
  ! grep -qx 'arg --dry-run' "$STUB_LOG" || { echo "a promoted repo under act still dry-ran"; false; }
}

@test "6: reso-management-app is scope=excluded — logged, dequeued, never evaluated" {
  local rr wt; rr="$(mkrepo reso-management-app)"; wt="$(mkwt "$rr" wt-r)"
  emit "$wt"
  WTGC_EVENTS=act wake
  [ "$(calls)" = 0 ] || { echo "the janitor was run on reso: $(cat "$STUB_LOG")"; false; }
  grep -q "repo=reso-management-app decision=dropped path=$wt reason=scope=excluded" "$CC_WTGC_WAKE_LOG" \
    || { echo "no scope=excluded row: $(cat "$CC_WTGC_WAKE_LOG")"; false; }
  [ ! -s "$ST/wt-queue.tsv" ] || { echo "reso row not dequeued: $(cat "$ST/wt-queue.tsv")"; false; }
}

@test "7: a CLOCK KEEP is requeued with not_before = now + grace" {
  local wt; wt="$(mkwt "$HOMEREPO" wt-a)"
  emit "$wt"
  STUB_LINE='KEEP    %s [b] — landed-clean, inside the PARK grace — newest transcript 2h old (< 24h)' wake
  run cat "$ST/wt-queue.tsv"
  [ "$output" = "$wt	$((WT_NOW + 86400))	session-end	s1" ] || { echo "queue: '$output'"; false; }
  grep -q 'dequeued=0 requeued=1' "$CC_WTGC_WAKE_LOG" || { echo "summary: $(cat "$CC_WTGC_WAKE_LOG")"; false; }
}

@test "8: terminal verdicts are dequeued — a state KEEP and a would-park alike" {
  local a b; a="$(mkwt "$HOMEREPO" wt-a)"; b="$(mkwt "$HOMEREPO" wt-b)"
  emit "$a"
  wake                                       # default stub line: KEEP … LIVE …
  [ ! -s "$ST/wt-queue.tsv" ] || { echo "a LIVE keep stayed queued: $(cat "$ST/wt-queue.tsv")"; false; }
  emit "$b"
  STUB_LINE='would park    %s [b] — arm-i (landed-clean, quiet 3d)' wake
  [ ! -s "$ST/wt-queue.tsv" ] || { echo "a would-park stayed queued: $(cat "$ST/wt-queue.tsv")"; false; }
  grep -q "decision=would_park path=$b " "$CC_WTGC_WAKE_LOG" || { echo "row: $(cat "$CC_WTGC_WAKE_LOG")"; false; }
  # DESIGN §3.4 "dirty-and-young": an arm-ii 7 d floor is terminal, left to the 04:15 backstop.
  local c; c="$(mkwt "$HOMEREPO" wt-c)"
  emit "$c"
  STUB_LINE='KEEP    %s [b] — dirty, arm-ii floor: tip is 2d old (< 7d)' wake
  [ ! -s "$ST/wt-queue.tsv" ] || { echo "an arm-ii floor KEEP stayed queued: $(cat "$ST/wt-queue.tsv")"; false; }
  grep -q "path=$c reason=.*(keep=terminal)" "$CC_WTGC_WAKE_LOG" || { echo "row: $(cat "$CC_WTGC_WAKE_LOG")"; false; }
}

@test "9: a newer event for the same path resets the grace (one row, later not_before)" {
  local wt; wt="$(mkwt "$HOMEREPO" wt-a)"
  emit "$wt"                                  # due on its own…
  emit "$wt" "$NOW_TS"                        # …but this later event restarts the clock
  wake
  [ "$(calls)" = 0 ] || { echo "evaluated before the reset grace ran out"; false; }
  run cat "$ST/wt-queue.tsv"
  [ "$output" = "$wt	$((WT_NOW + 86400))	session-end	s1" ] || { echo "queue: '$output'"; false; }
}

@test "10: a run started < debounce ago exits silently; one past it runs" {
  export CC_WTGC_WAKE_DEBOUNCE_S=60
  local a b; a="$(mkwt "$HOMEREPO" wt-a)"; b="$(mkwt "$HOMEREPO" wt-b)"
  emit "$a"
  wake
  [ "$(calls)" = 1 ] || { echo "first run: $(calls) janitor runs"; false; }
  local rows; rows="$(grep -c . "$CC_WTGC_WAKE_LOG")"
  emit "$b"
  WT_NOW=$((WT_NOW + 30)) wake
  [ "$status" -eq 0 ]
  [ "$(calls)" = 1 ] || { echo "debounced run still evaluated"; false; }
  [ "$(grep -c . "$CC_WTGC_WAKE_LOG")" = "$rows" ] || { echo "debounced run logged"; false; }
  WT_NOW=$((WT_NOW + 61)) wake
  [ "$(calls)" = 2 ] || { echo "a run past the debounce did not evaluate"; false; }
}

@test "11: malformed event lines are skipped; a truncated events file is reread from 0" {
  local wt; wt="$(mkwt "$HOMEREPO" wt-a)"
  printf 'not json\n{"path":7}\n' >> "$WT_EVENTS_FILE"
  emit "$wt" "$NOW_TS"
  wake
  run cut -f1 "$ST/wt-queue.tsv"
  [ "$output" = "$wt" ] || { echo "queue after malformed lines: '$output'"; false; }
  : > "$WT_EVENTS_FILE"; : > "$ST/wt-queue.tsv"
  emit "$wt" "$NOW_TS"                       # shorter than the cursor now
  wake
  run cut -f1 "$ST/wt-queue.tsv"
  [ "$output" = "$wt" ] || { echo "a rotated events file was not reread: '$output'"; false; }
}

@test "12: end-to-end against the REAL worktree-gc.sh in observe mode mutates nothing" {
  unset WT_NOW                                # the real janitor reads the real clock
  export CC_WTGC_INFRA_GC="$REPO/scripts/worktree-gc.sh"
  local shim="$BATS_TEST_TMPDIR/cc-notify" null="$BATS_TEST_TMPDIR/nullbin"
  printf '#!/bin/bash\necho "[]"\n' > "$shim"; chmod +x "$shim"
  # shellcheck disable=SC2016  # the stub's own program: $@ and $$ are the stub's, not this shell's
  printf '#!/bin/bash\nfor a in "$@"; do [ "$a" = cwd ] && { printf "p%%s\\nn/\\n" "$$"; exit 0; }; done\nexit 1\n' > "$null"
  chmod +x "$null"
  export CC_WTGC_CC_NOTIFY="$shim" CC_WTGC_LSOF="$null" CC_WTGC_PGREP="$null"
  export CC_WTGC_REGISTRY_DIR="$BATS_TEST_TMPDIR/registry" CC_WTGC_LOCK="$BATS_TEST_TMPDIR/gc.lock"
  export CC_WTGC_DISPOSAL_LOG="$BATS_TEST_TMPDIR/disposals.jsonl" CC_WTGC_DISABLE_FILE=""
  export CC_WTGC_TOMBSTONE_LIB="$REPO/scripts/lib/wt-tombstone.sh"
  mkdir -p "$CC_WTGC_REGISTRY_DIR"
  local wt before after; wt="$(mkwt "$HOMEREPO" wt-e2e)"
  emit "$wt" "2020-01-01T00:00:00Z"
  before="$(git -C "$HOMEREPO" worktree list --porcelain)"
  WTGC_EVENTS=observe wake
  [ "$status" -eq 0 ] || { echo "rc=$status $output"; false; }
  after="$(git -C "$HOMEREPO" worktree list --porcelain)"
  [ "$before" = "$after" ] || { printf 'worktree list changed:\n%s\n---\n%s\n' "$before" "$after"; false; }
  [ -d "$wt" ] || { echo "the worktree dir is gone"; false; }
  grep -q "mode=observe repo=claude-infrastructure decision=would_[a-z]* path=$wt " "$CC_WTGC_WAKE_LOG" \
    || { echo "no decision row from the real janitor: $(cat "$CC_WTGC_WAKE_LOG")"; false; }
}
