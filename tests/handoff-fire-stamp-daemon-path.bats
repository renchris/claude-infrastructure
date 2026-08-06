#!/usr/bin/env bats
# handoff-fire.sh `stamp-peer` under the DAEMON PATH, and the diagnostic that named the wrong cause
# (item 890cd862b965, 2026-08-05).
#
# WHAT THIS FILE REFUTES. The item was filed to route ~60 bare-name `jq` call sites in
# scripts/handoff-fire.sh through a `cc-jq-bin` resolver — a sibling of bin/cc-kitty-bin — on the
# premise that "jq is Homebrew-only, so every `command -v jq` guard takes the jq-missing branch under
# the hook/launchd PATH". The premise is false on this platform and the remedy would have been dead
# code:
#
#     macOS 15 SHIPS jq. /usr/bin/jq is jq-1.7.1-apple, root:wheel, part of the base OS — so it is
#     on PATH=/usr/bin:/bin:/usr/sbin:/sbin, the PATH hooks and launchd jobs actually run with.
#
# That is the whole difference from the bare-`kitty` defect fixed in 86588cbf, which this item was
# modelled on: `kitty` genuinely does not exist under that PATH, and `jq` genuinely does. The two
# builds were also compared directly — /usr/bin/jq and /opt/homebrew/bin/jq have identical 218-builtin
# sets (Apple links oniguruma statically) and produced byte-identical stdout and exit codes on every
# construct these scripts use — so there is no version-skew defect hiding behind the absent one.
#
# WHAT THE ITEM DID FIND, which is real. The failure message it was filed against GUESSED:
#     "no stamp written at … (jq missing, or the directory is unwritable)"
# It named two candidates, measured neither, and omitted the one a caller trips most easily — a pane
# id that mark_fired_peer's UUID-shape guard refuses. `stamp-peer --pane %3` (a tmux-style id)
# therefore reported "jq missing" with jq present and the directory writable. A failure message is a
# diagnosis and gets read as one: this one produced a 60-site refactor proposal against a cause that
# cannot occur here. The message now relays MFP_SKIP_REASON, set by the writer that actually declined.
#
# WHY A DAEMON-PATH FIXTURE AT ALL. No handoff-fire suite carried one before this file (only
# tests/it2-kitty.bats did), which is exactly why the claim survived to become a work item: nothing
# in the suite could contradict it. The first test below is the control that now would.
#
# Every assertion is `[ ]`, `run`+status, or `… || false`. `[[ ]]` and `(( ))` are errexit-EXEMPT in
# bats and are silently DEAD anywhere but a body's last line — that has burned this repo twice.

setup() {
  # HERMETIC $HOME (scripts/test-hermeticity-lint.sh): the subject resolves state under ~.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"

  # The two M11 pins, required of every fire-executing suite: handoff-fire's capacity_gate() refuses
  # a net-new fire above 2.0/core and this box lives well above that, so an unpinned suite goes
  # red-by-LOAD rather than by its subject. scripts/test-hermeticity-lint.sh checks the first and the
  # DERIVED pin-guard ratchet (tests/handoff-fire-capacity-gate.bats:384) fails any new fire-executing
  # suite missing either.
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  export CC_FIRED_DIR="$BATS_TEST_TMPDIR/cc-fired"; mkdir -p "$CC_FIRED_DIR"
  PEERWT="$BATS_TEST_TMPDIR/peer-wt"; mkdir -p "$PEERWT"
}

# THE DAEMON ENVIRONMENT, built the way launchd builds it: `env -i` so nothing of the developer's
# shell leaks in, and the stock system PATH with no /opt/homebrew on it. Anything this script needs
# beyond that must be passed explicitly — which is the point.
DAEMON_PATH=/usr/bin:/bin:/usr/sbin:/sbin
daemon_stamp() {
  run env -i PATH="$DAEMON_PATH" HOME="$HOME" \
      CC_FIRED_DIR="$CC_FIRED_DIR" CC_FIRE_CAPACITY_GATE=off CC_FIRE_HEADROOM_GATE=off \
      /bin/bash "$HF" stamp-peer "$@"
}

# ── the refutation ──────────────────────────────────────────────────────────────────────────────

@test "REFUTATION: stamp-peer succeeds under the daemon PATH — jq needs no resolver (item 890cd862b965)" {
  # The control the suite lacked. If jq were Homebrew-only, mark_fired_peer's `command -v jq` guard
  # would take its skip branch here and stamp-peer would exit 1 with an empty fired-dir.
  daemon_stamp --pane 28 --cwd "$PEERWT" --by 2
  [ "$status" -eq 0 ]
  [ -s "$CC_FIRED_DIR/28.json" ]
  # Content, not just presence: a truncated or empty stamp is the failure this would otherwise mask.
  [ "$(jq -r '.selfRetire'  "$CC_FIRED_DIR/28.json")" = "true" ]
  [ "$(jq -r '.originClass' "$CC_FIRED_DIR/28.json")" = "fired-peer" ]
  [ "$(jq -r '.cwd'         "$CC_FIRED_DIR/28.json")" = "$PEERWT" ]
}

@test "THE PLATFORM FACT: jq resolves under the daemon PATH, and it is the SYSTEM one" {
  # Asserted directly so the premise is re-measured on every run rather than remembered. If a future
  # macOS drops /usr/bin/jq, this goes red HERE — naming the cause — instead of every daemon-fired
  # stamp silently becoming a no-op, which is the failure mode the item feared and mislocated.
  run env -i PATH="$DAEMON_PATH" /usr/bin/which jq
  [ "$status" -eq 0 ]
  [ "$output" = "/usr/bin/jq" ]
}

# ── the diagnostic: name the cause you MEASURED ─────────────────────────────────────────────────

# Assert on the REASON CLAUSE, never the whole line. The line leads with the stamp's absolute path
# under $BATS_TEST_TMPDIR, which is randomly named — a bare `!= *"jq"*` over the whole output would
# flake the day bats hands this suite a /var/folders/xjq… directory. The message format is
# "… — <reason>", so the clause after the em-dash is the part under test.
reason_of() { printf '%s' "${1##*— }"; }

@test "the pane-shape refusal names ITSELF, and never mentions jq" {
  # The exact call that reported "jq missing" with jq present and the fired-dir writable. `%3` is a
  # tmux pane id — a shape mark_fired_peer's guard refuses so a pane id can never be a path fragment.
  run bash "$HF" stamp-peer --pane '%3' --cwd "$PEERWT" --by 2
  [ "$status" -eq 1 ]
  [[ "$output" == *"no stamp written"* ]] || false
  local why; why="$(reason_of "$output")"
  [[ "$why" == *"not UUID/hex-shaped"* ]] || false
  # The whole defect in one assertion: the old message blamed jq here, and jq was never the cause.
  [[ "$why" != *"jq"* ]] || false
}

@test "the unwritable-dir refusal names the DIRECTORY as the cause, not an either/or with jq" {
  # This message legitimately mentions jq — jq RAN and its output could not be written, which is a
  # measurement, not a guess. So the discriminator is not the word "jq" but the GUESS the old line
  # made: "jq missing" offered two candidates and resolved neither. That phrase must be gone.
  chmod 500 "$CC_FIRED_DIR"
  run bash "$HF" stamp-peer --pane 28 --cwd "$PEERWT" --by 2
  chmod 700 "$CC_FIRED_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no stamp written"* ]] || false
  local why; why="$(reason_of "$output")"
  [[ "$why" == *"unwritable"* ]] || false
  [[ "$why" == *"$CC_FIRED_DIR"* ]] || false
  [[ "$why" != *"jq missing"* ]] || false
}

@test "POSITIVE CONTROL: with jq genuinely ABSENT the message DOES name jq" {
  # Without this, the two "does not blame jq" tests above could pass by the message having become
  # incapable of naming jq at all — which would be a worse diagnostic, not a better one. A PATH farm
  # of the daemon PATH minus jq is the only way to produce the cause the item assumed was routine.
  local nojq="$BATS_TEST_TMPDIR/nojq"; mkdir -p "$nojq"
  local d f b
  for d in /usr/bin /bin /usr/sbin /sbin; do
    for f in "$d"/*; do
      b="${f##*/}"
      [ "$b" = jq ] && continue
      [ -e "$nojq/$b" ] || ln -s "$f" "$nojq/$b" 2>/dev/null || true
    done
  done
  # Assert the farm is actually a farm — an empty or jq-carrying one makes this case vacuous.
  [ ! -e "$nojq/jq" ]
  [ -x "$nojq/mkdir" ]

  run env -i PATH="$nojq" HOME="$HOME" \
      CC_FIRED_DIR="$CC_FIRED_DIR" CC_FIRE_CAPACITY_GATE=off CC_FIRE_HEADROOM_GATE=off \
      /bin/bash "$HF" stamp-peer --pane 28 --cwd "$PEERWT" --by 2
  [ "$status" -eq 1 ]
  [[ "$output" == *"jq is not on PATH"* ]] || false
  [ ! -f "$CC_FIRED_DIR/28.json" ]
}

# ── the contract that must not move ─────────────────────────────────────────────────────────────

@test "mark_fired_peer still returns 0 when it declines — a FIRE must not die on its bookkeeping" {
  # MFP_SKIP_REASON is an out-param precisely so this return code could stay untouched. Both
  # fire-path call sites (:3890 unguarded by `|| true`, :5198) depend on it under `set -e`.
  x_mfp="$(sed -n '/^mark_fired_peer() {/,/^}/p' "$HF")"; [ -n "$x_mfp" ]
  eval "$x_mfp"
  # A pane shape it refuses, a jq-less lookup and an uncreatable dir: all decline, all return 0.
  run mark_fired_peer "$CC_FIRED_DIR" '%3' "$PEERWT" 2
  [ "$status" -eq 0 ]
  run mark_fired_peer "/dev/null/cannot-exist" 28 "$PEERWT" 2
  [ "$status" -eq 0 ]
  # …and the reason is set rather than merely absent, or the caller has nothing to relay.
  mark_fired_peer "$CC_FIRED_DIR" '%3' "$PEERWT" 2
  [ -n "$MFP_SKIP_REASON" ]
  # A SUCCESSFUL write must clear it — a stale reason from a prior call would be relayed as this
  # call's cause the next time a stamp legitimately fails.
  mark_fired_peer "$CC_FIRED_DIR" 28 "$PEERWT" 2
  [ -s "$CC_FIRED_DIR/28.json" ]
  [ -z "$MFP_SKIP_REASON" ]
}
