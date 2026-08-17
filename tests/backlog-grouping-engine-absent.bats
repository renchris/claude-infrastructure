#!/usr/bin/env bats
# scripts/backlog-grouping-sweep.sh — the ENGINE-ABSENT guard (backlog 70cc9f44040f).
#
# WHAT IS BEING PINNED, and why an exit code is the whole subject. This sweep is wired into
# autonomy-sweep on a 300 s tick with `>/dev/null 2>&1`, so its stderr reaches nobody and its rc is
# the ONLY thing that leaves the process. Until this change both engine guards answered `exit 0`
# with one discarded line — so a live layer that had never received `scripts/backlog-consolidation/*.py`
# (install.sh's deploy-class gap, fixed in 6d96bf560) ran this on schedule, reported success and
# folded nothing for the mechanism's entire deployed life. deploy-parity-assert.sh measured exactly
# that: "answered 'no grouper at …' with rc 0".
#
# THE MUTANT ARM IS THE POINT OF THE FILE. Every positive assertion here (`exit 2`) would also pass
# against a subject that exited 2 for some unrelated reason, and none of them credits the fix unless
# the pre-fix spelling can be shown to FAIL. `mutant()` restores the fail-open exit at the one site
# this change touched and is asserted to reach exit 0 on the same fixture — so the suite fails if the
# guard is ever reverted, and its anchor check fails if the site is renamed out from under it
# (memory: control-must-replay-the-real-artifact, per-site-mutation-attributes-coverage).
#
# THE OTHER HALF IS THE ALARM'S POLARITY. A guard that turned every "nothing to do" into a red would
# carry as little information as one that never fires, so the healthy path is pinned too: engine
# present + a store under the floor is still rc 0, and `--assert` writes nothing to the ledger.

setup() {
  export CC_BACKLOG_PROJECT_WARN=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"

  # A COPY of the tree, not the repo itself: the subject derives $GROUP from its own BASH_SOURCE, so
  # "the grouper is absent" is expressed by copying the caller without the engine beside it. Nothing
  # here can touch the real checkout.
  SUT_DIR="$BATS_TEST_TMPDIR/tree"
  mkdir -p "$SUT_DIR/scripts" "$SUT_DIR/hooks/lib" "$SUT_DIR/bin"
  cp "$REPO/scripts/backlog-grouping-sweep.sh" "$SUT_DIR/scripts/"
  cp "$REPO/hooks/lib/page-damp.sh" "$SUT_DIR/hooks/lib/"
  SUT="$SUT_DIR/scripts/backlog-grouping-sweep.sh"
  MUT="$SUT_DIR/scripts/mutant.sh"

  export CC_PAGE_DAMP_DIR="$BATS_TEST_TMPDIR/damp"
  CALLS="$BATS_TEST_TMPDIR/cc-backlog.calls"
  STUB="$SUT_DIR/bin/cc-backlog"
}

# Put the engine beside the caller: the whole consolidation dir, because group.py reads its siblings.
with_engine() { cp -R "$REPO/scripts/backlog-consolidation" "$SUT_DIR/scripts/"; }

# A cc-backlog that records every invocation. The store's own behaviour is not under test here —
# what is under test is whether the page is SENT, and how often.
stub_backlog() { # <exit-code>
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s"\nexit %s\n' "$CALLS" "${1:-0}" > "$STUB"
  chmod +x "$STUB"
  export CC_BACKLOG_BIN="$STUB"
}
n_calls() { [ -f "$CALLS" ] && wc -l < "$CALLS" | tr -d ' ' || printf '0'; }

# A PATH with no python3 on it. Built by naming what the guard path actually needs rather than by
# shadowing, because absence cannot be spelled as an override.
nopy_path() {
  local d="$BATS_TEST_TMPDIR/nopy" t p
  mkdir -p "$d"
  for t in dirname date mkdir rm head tr cat grep sed; do
    p="$(command -v "$t" 2>/dev/null)"
    [ -n "$p" ] && ln -sf "$p" "$d/$t"
  done
  printf '%s' "$d"
}

# THE MUTANT: the pre-fix fail-open, restored at the one site this change created. Anchored both
# ways, so a rename of the site reds the anchor instead of silently producing a mutant identical to
# the subject (memory: sibling-guard-makes-the-fixture-vacuous).
mutant() {
  [ "$(grep -c '^  exit 2$' "$SUT")" -eq 1 ]
  sed 's/^  exit 2$/  exit 0/' "$SUT" > "$MUT"
  [ "$(grep -c '^  exit 2$' "$MUT")" -eq 0 ]
  chmod +x "$MUT"
}

# THE FULL PRE-FIX ARTIFACT: both guard sites reverted to trunk's one-liner — stderr, rc 0, and no
# filing at all. `mutant()` above flips only the rc, so it can credit the fail-closed exit but says
# nothing about the page; this one is the arm the page's assertions hang off. Two sites, both
# reverted in one pass, and the anchor counts them so a rename cannot quietly produce a no-op mutant.
mutant_prefix() {
  [ "$(grep -c '|| engine_absent ' "$SUT")" -eq 2 ]
  sed 's/|| engine_absent .*/|| { printf "fail-open\\n" >\&2; exit 0; }/' "$SUT" > "$MUT"
  [ "$(grep -c '|| engine_absent ' "$MUT")" -eq 0 ]
  chmod +x "$MUT"
}

# ── fail-CLOSED: both engine sites ───────────────────────────────────────────────────────────────

@test "no grouper ⇒ rc 2, not the fail-open 0 the live layer ran on for its whole deployed life" {
  run bash "$SUT"
  [ "$status" -eq 2 ]
  printf '%s' "$output" | grep -q 'no grouper at'
  printf '%s' "$output" | grep -q 'CANNOT MEASURE'
}

@test "no python3 ⇒ rc 2 — the other engine site, attributed by its own reason" {
  with_engine
  # `env` rather than a PATH prefix on `run`: the restricted PATH has no bash on it either, so the
  # prefix form exits 127 and every assertion below would be measuring the harness (memory:
  # hermetic-in-stubs-not-in-interpreter).
  run env PATH="$(nopy_path)" /bin/bash "$SUT"
  [ "$status" -eq 2 ]
  printf '%s' "$output" | grep -q 'python3 missing'
}

@test "MUTANT: the pre-fix exit reaches 0 on the same fixture — the arm that credits the change" {
  mutant
  run bash "$MUT"
  # Fail-open, exactly as trunk behaved before 70cc9f44040f: a missing engine read as a clean store.
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'no grouper at'
}

@test "MUTANT: the whole pre-fix guard is silent to the store too — the arm the page hangs off" {
  mutant_prefix
  stub_backlog 0
  run bash "$MUT" --file
  # Trunk's behaviour in full: rc 0 into a caller that discards stderr, and nothing written anywhere
  # a reader would ever look. That is what "invisibly inert for its entire deployed life" was.
  [ "$status" -eq 0 ]
  [ "$(n_calls)" -eq 0 ]
}

# ── the page: filed, condition-keyed, damped ─────────────────────────────────────────────────────

@test "--file with no engine files ONE condition-keyed, self-falsifying row" {
  stub_backlog 0
  run bash "$SUT" --file
  [ "$status" -eq 2 ]
  [ "$(n_calls)" -eq 1 ]
  grep -q 'backlog-grouping-engine-absent' "$CALLS"
  grep -q 'source backlog-grouping-sweep' "$CALLS"
  # The probe must retract on the engine's RETURN, not on the floor going healthy — `--assert` would
  # have keyed the retraction to a different condition entirely.
  grep -q 'falsifier command -v python3' "$CALLS"
}

@test "a second tick inside the TTL is DAMPED — the page is a signal, not a stream" {
  stub_backlog 0
  run bash "$SUT" --file
  [ "$status" -eq 2 ]
  run bash "$SUT" --file
  [ "$status" -eq 2 ]
  # Two ticks, ONE send. The rc stays fail-closed on both: damping suppresses the page, never the
  # verdict (a damped alarm that also went green would be the fail-open again, wearing a marker).
  [ "$(n_calls)" -eq 1 ]
}

@test "a REFUSED filing drops its own damp marker, so the next tick retries" {
  stub_backlog 1
  run bash "$SUT" --file
  [ "$status" -eq 2 ]
  printf '%s' "$output" | grep -q 'could not file the engine-absent row'
  run bash "$SUT" --file
  # The marker records an INTENT to send; a send that failed must not burn the TTL suppressing the
  # retry of a page nobody received (page-damp.sh's damp_forget contract).
  [ "$(n_calls)" -eq 2 ]
}

@test "--assert stays a pure READ: rc 2, and not one write to the ledger" {
  stub_backlog 0
  run bash "$SUT" --assert
  # 2 is cc-premise's _FALSIFIER_UNASKABLE_RCS band ("COULD NOT ASK"), which is why a fourth code was
  # not minted: exit 0 here would have RETRACTED the escalation row this sweep exists to file.
  [ "$status" -eq 2 ]
  [ "$(n_calls)" -eq 0 ]
}

# ── alarm polarity: the healthy path must not have become an alarm ────────────────────────────────

@test "engine present and a store under the floor is still rc 0 — no always-firing alarm" {
  with_engine
  stub_backlog 0
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  export CC_BACKLOG_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_BACKLOG_KICK=off
  # The real grouper over the real store binary — a hand-rolled census would test this suite's idea
  # of the fold rather than cc-backlog's (memory: sibling-auditors-must-share-the-state-model).
  export CC_BACKLOG_BIN="$REPO/bin/cc-backlog"
  bash "$REPO/bin/cc-backlog" add --project claude-infrastructure \
    --title "deploy-live REFUSES: no GREEN tree descends live HEAD" --source fx >/dev/null
  run bash "$SUT" --file
  [ "$status" -eq 0 ]
}
