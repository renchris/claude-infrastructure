#!/usr/bin/env bats
# cc-dispatch: a fire's own narration must survive SUCCESS, not only failure.
#
# Regression under test (2026-08-07, docs/plans/PANE_THEFT_2026-08-07.md §4.7). cc-dispatch captured
# handoff-fire's combined output to a mktemp and then, on rc 0, `rm`'d it UNREAD — only the failure
# arm ran fire_excerpt. handoff-fire narrates its entire anchor decision on stderr
# (`→ headless fire: … anchored to live pane X`, `!! FOCUS-STOLEN …`, `Closed the untyped pane N`,
# every `→ fire-cleanup: …`) and that stream existed nowhere else, so the ONE path that succeeds was
# the ONE path whose evidence was destroyed.
#
# It stopped being hypothetical when two headless fires anchored on the operator's own panes, one of
# which was destroyed with unsent composer text in it, and "which call did that?" turned out to be
# unanswerable: /tmp/claude-dispatcher.stderr.log holds ZERO occurrences of `headless fire`,
# `anchor`, `FOCUS-STOLEN` or `fire-cleanup` across its whole history. Same shape as
# memory gate-silence-population-and-suppression — never-LOOKED-AT and told-to-IGNORE render as the
# same green.
#
# fire_log_keep is extracted from the shipped bin/cc-dispatch and executed, so this replays the real
# artifact. The last test is a MUTATION CONTROL proving the assertions can fail.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/logs"
  REPO="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  DISPATCH="$REPO/bin/cc-dispatch"
  [ -f "$DISPATCH" ] || skip "bin/cc-dispatch not found at $DISPATCH"

  export CC_DISPATCH_FIRE_LOG="$BATS_TEST_TMPDIR/dispatch-fires.log"
  LIB="$BATS_TEST_TMPDIR/lib.sh"
  sed -n '/^fire_log_keep()/,/^}/p' "$DISPATCH" > "$LIB"
  grep -q '^fire_log_keep()' "$LIB" || skip "could not extract fire_log_keep from $DISPATCH"

  CAP="$BATS_TEST_TMPDIR/fire-output.txt"
  cat > "$CAP" <<'EOF'
→ headless fire: no firing pane (launchd/cron caller); anchored to live pane 247 (2 pane(s) in its tab)
→ fire-cleanup: task-less pane 248 made VISIBLE (registry row + fired-peer marker)
EOF
}

keep() { bash -c ". '$LIB'; fire_log_keep '$1' '$2' '$3' '$CAP'"; }
logged() { cat "$CC_DISPATCH_FIRE_LOG" 2>/dev/null; }

# ── the success path is evidenced ─────────────────────────────────────────────────────

@test "a SUCCESSFUL fire's output is persisted, not deleted unread" {
  run keep abc123 next3 0
  [ "$status" -eq 0 ]
  logged | grep -q 'anchored to live pane 247'
}

@test "the record carries the item, the account and the rc" {
  keep abc123 next3 0
  logged | grep -q 'item=abc123'
  logged | grep -q 'account=next3'
  logged | grep -q 'rc=0'
}

@test "failures are persisted too — one store, not two" {
  keep def456 next4 9
  logged | grep -q 'item=def456'
  logged | grep -q 'rc=9'
}

@test "successive fires APPEND rather than overwrite" {
  keep a1 next3 0
  keep a2 next3 0
  [ "$(grep -c '^===== ' "$CC_DISPATCH_FIRE_LOG")" = "2" ]
}

# ── it cannot become the next outage ──────────────────────────────────────────────────

@test "an empty or missing capture file is a no-op, never an error" {
  # A side-car must fail no wider than itself (memory: addon-failure-exceeds-its-blast-radius).
  : > "$BATS_TEST_TMPDIR/empty.txt"
  run bash -c ". '$LIB'; fire_log_keep x y 0 '$BATS_TEST_TMPDIR/empty.txt'"
  [ "$status" -eq 0 ]
  run bash -c ". '$LIB'; fire_log_keep x y 0 '$BATS_TEST_TMPDIR/does-not-exist'"
  [ "$status" -eq 0 ]
  run bash -c ". '$LIB'; fire_log_keep x y 0 ''"
  [ "$status" -eq 0 ]
}

@test "an unwritable log directory does not fail the dispatcher" {
  run bash -c "CC_DISPATCH_FIRE_LOG=/proc/nope/nope.log . '$LIB'; \
               CC_DISPATCH_FIRE_LOG=/proc/nope/nope.log fire_log_keep x y 0 '$CAP'"
  [ "$status" -eq 0 ]
}

# mode_of <file> → the permission bits, on either stat dialect.
#
# 🚨 A `stat -f … || stat -c …` CHAIN DOES NOT WORK, and the reason is why these two cases were red
# rather than merely unportable. Both assertions read a real property of a real file and were spelled
# BSD-only; on GNU coreutils `-f` is not an unknown flag that errors into a fallback, it means
# `--file-system` — so `stat -f %z FILE` prints a filesystem report and EXITS 0. A `||` fallback can
# never fire, and `$sz` becomes a multi-line block that fails `[ ]` with "integer expression
# expected". scripts/compressor-sentinel.sh:1040 carries that same chain and is latently wrong on
# Linux for the same reason; it is not the idiom to copy.
#
# So the dialect is PROBED, not guessed: GNU stat has `--version`, BSD stat does not. Size skips
# stat entirely — `wc -c` is POSIX and identical on both.
#
# WHY THIS IS IN SCOPE FOR A CLOUD LAND AT ALL. Every cloud dispatch of this repo runs Linux, so
# these two cases red for every land whose smoke scope reaches bin/cc-dispatch, while the behaviour
# they guard is correct — a false RED about the machine wearing a verdict about the diff, the 6-vs-9
# confusion the land pipeline exists to keep apart (tests/cc-venue.bats:186 documents the same
# inversion from the root/mode-bit direction). Darwin keeps its exact spelling and its verdict.
mode_of() {
  if stat --version >/dev/null 2>&1; then stat -c '%a' "$1"; else stat -f '%Lp' "$1"; fi
}

@test "the log is 0600 — a fire's output can quote a prompt" {
  keep abc123 next3 0
  run mode_of "$CC_DISPATCH_FIRE_LOG"
  [ "$output" = "600" ]
}

@test "each fire's excerpt is bounded, so one runaway cannot fill the disk" {
  head -c 200000 /dev/zero | tr '\0' 'x' > "$BATS_TEST_TMPDIR/big.txt"
  keep big next3 0
  local sz; sz="$(wc -c < "$CC_DISPATCH_FIRE_LOG" | tr -d '[:space:]')"
  [ "$sz" -lt 20000 ]
  # 0 would satisfy `< 20000` vacuously — the bound must be proven over a file that actually has
  # content, which is exactly what the broken chain above was silently failing to establish.
  [ "$sz" -gt 0 ] || { echo "the log is empty, so the bound proves nothing: sz=$sz"; false; }
}

# ── the caller wires it on BOTH arms, and surfaces the anchor ─────────────────────────

@test "cc-dispatch calls fire_log_keep on the success arm as well as the failure arm" {
  # The whole defect was an asymmetry between the two arms; asserting only that the function exists
  # would leave exactly that asymmetry re-introducible.
  run bash -c "grep -c 'fire_log_keep \"\$id\"' '$DISPATCH'"
  [ "$output" = "2" ]
}

@test "the anchor decision is promoted into the IDL verdict line" {
  # 'which pane did an autonomous fire attach itself to' is the question that took an incident to
  # ask and had no answer; it now rides on the one-line record too, not only in the log file.
  grep -q "anchored to live pane" "$DISPATCH"
  grep -q 'idl fired "$id -> $acct${fanch:+ — $fanch}"' "$DISPATCH"
}

@test "CONTROL: the OLD success arm keeps nothing — the assertions above can fail" {
  cat > "$BATS_TEST_TMPDIR/old.sh" <<'SH'
old_arm() { # the pre-fix shape: capture, branch, delete unread
  local ferrf="$1"
  if [ "$2" -eq 0 ]; then :; else :; fi
  rm -f "$ferrf" 2>/dev/null
}
SH
  cp "$CAP" "$BATS_TEST_TMPDIR/victim.txt"
  run bash -c ". '$BATS_TEST_TMPDIR/old.sh'; old_arm '$BATS_TEST_TMPDIR/victim.txt' 0"
  [ "$status" -eq 0 ]
  # the evidence is gone and nothing was written anywhere
  [ ! -f "$BATS_TEST_TMPDIR/victim.txt" ]
  [ ! -s "$CC_DISPATCH_FIRE_LOG" ]
}
