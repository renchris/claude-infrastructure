#!/usr/bin/env bats
# handoff-fire.sh self-close — THE FOURTH SESSION CATEGORY: a TRANSPLANTED SOURCE.
#
# THE DEFECT. A limit or login-cliff recovery moves a session to another account: lr-transplant.sh
# copies the transcript into the target config dir, takes a split-brain lock, and writes a TOMBSTONE
# beside the original. A successor is then fired on the new account and carries the work. What is
# left behind is a pane whose SESSION IS SOMEWHERE ELSE — a husk that will never produce another
# turn, sitting in the operator's window looking exactly like live work.
#
# self-close refused it. Its oracle is the fired-peer stamp, and a transplant source has none: it was
# launched by the operator, which is precisely why the transplant was needed. So the origin gate read
# `origin` — correctly on the evidence it had, wrongly on the facts.
#
# WHY NOT --allow-origin-close. It exists, it is documented "deliberate, loud, almost never right",
# and it would work. It is still the wrong instrument, and this suite exists to pin that: the gate's
# purpose is to stop a close with NO continuation, and this close HAS one — a named, alive, engaged
# successor holding the transplanted session. Spending a safety gate on a case that can PROVE it is
# safe would also leave the class unnamed for the next caller. So the fix NAMES the category, exactly
# as the orphaned-assignee row above it did (tests/handoff-orphaned-assignee.bats), and every test
# below is a REFUSAL except the two that satisfy all six preconditions.
#
# THE PRECONDITION THAT CARRIES THE WEIGHT is that the FLAG IS NOT EVIDENCE. `--transplanted-source`
# names a category; it cannot confer one. Admission needs a live --successor (never --terminal), the
# tombstone lr-transplant writes only after a sha-verified copy, a .handed_off_to pointing at a
# DIFFERENT config dir, and the split-brain lock still held. Each of those has a test below for its
# ABSENCE, because a precondition nothing can fail is not a precondition.
#
# Technique mirrors tests/handoff-orphaned-assignee.bats: PATH shims, --dry-run so the gate runs but
# nothing is armed or closed, and the whole script invoked (never a sed-extracted unit) because the
# subject IS the gate's control flow.

setup() {
  # M11 — pin the machine-capacity gates: unpinned, this suite goes red because the box is busy.
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  # PIN THE TERMINAL, all three spellings (env divert, kill switch, identity). Run from kitty the
  # subject takes the kitty branch while only osascript is stubbed, and the verdict silently becomes
  # a function of which terminal the developer is sitting in.
  unset KITTY_WINDOW_ID
  export IT2_WRAPPER_NO_KITTY=1
  export CC_TERM=iterm2

  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"

  # HERMETICITY: the subject resolves defaults under $HOME (~/.claude/cc-fired, ~/.reso/…). An
  # unfixtured $HOME would read and MUTATE the operator's live state.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude"
  export CC_FIRED_DIR="$BATS_TEST_TMPDIR/cc-fired"; mkdir -p "$CC_FIRED_DIR"
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg"; mkdir -p "$CC_REGISTRY_DIR"
  # Seams that do NOT resolve under $HOME (test-hermeticity-lint 5a/5b): an absolute /tmp default and
  # a BARE NAME the subject would execute off the operator's PATH. Fixturing $HOME does not redirect
  # either, so unpinned this suite would read the operator's live account state and run their
  # deployed claude-accounts once per test. ABSENT paths are the right pin — these sensors fail open.
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/sweep-stamp.json"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-lock-"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/absent-claude-accounts"

  SHIM="$BATS_TEST_TMPDIR/shim"; mkdir -p "$SHIM"
  # as_tty's query: `osascript - <uuid>` → "TTY-<uuid>". Enough for the successor gate to resolve a
  # pane; this suite asserts on the ORIGIN gate, which runs strictly earlier.
  cat > "$SHIM/osascript" <<'SH'
#!/usr/bin/env bash
uuid=""
while [ $# -gt 0 ]; do
  case "$1" in
    -e) shift 2 2>/dev/null || shift ;;
    -)  shift ;;
    *)  uuid="$1"; shift ;;
  esac
done
[ -n "$uuid" ] && printf '%s' "TTY-$uuid"
exit 0
SH
  # only `git rev-parse --is-inside-work-tree` is hit — report "not a work tree" so the dirty-tree
  # guard is skipped, hermetically and independently of this test's CWD.
  cat > "$SHIM/git" <<'SH'
#!/usr/bin/env bash
[ "${1:-}" = rev-parse ] && exit 1
exit 0
SH
  # TWO distinct ps forms, and the shim must not conflate them (same split as the assignee suite):
  #   ps -t <tty> -o command=   → full argv    (agent_id_on_tty, the assignee oracle)
  #   ps -o comm= -p <pid>      → command NAME (originator_liveness's recycled-pid discriminator)
  # Both answer EMPTY unless a fixture file is placed, so the default posture is "no assignee, no
  # teammates" — which is what every test here but the class-exclusivity one wants.
  PS_ARGV_DIR="$BATS_TEST_TMPDIR/argv"; mkdir -p "$PS_ARGV_DIR"
  PS_COMM_DIR="$BATS_TEST_TMPDIR/comm"; mkdir -p "$PS_COMM_DIR"
  export PS_ARGV_DIR PS_COMM_DIR
  cat > "$SHIM/ps" <<'SH'
#!/usr/bin/env bash
tty="" pid="" want=""
while [ $# -gt 0 ]; do
  case "$1" in
    -t) tty="${2:-}"; shift 2 ;;
    -p) pid="${2:-}"; shift 2 ;;
    -o) case "${2:-}" in command=) want=argv ;; comm=) want=comm ;; esac; shift 2 ;;
    *)  shift ;;
  esac
done
if [ "$want" = argv ] && [ -n "$tty" ]; then
  [ -f "$PS_ARGV_DIR/$tty" ] && cat "$PS_ARGV_DIR/$tty"
  exit 0
fi
if [ "$want" = comm ] && [ -n "$pid" ]; then
  [ -f "$PS_COMM_DIR/$pid" ] && cat "$PS_COMM_DIR/$pid"
  exit 0
fi
exit 0
SH
  chmod +x "$SHIM/osascript" "$SHIM/git" "$SHIM/ps"
  export PATH="$SHIM:$PATH"

  SRC_PANE="11110000-2222-3333-4444-555566667777"
  SUCCESSOR="99990000-8888-7777-6666-555544443333"
  SESS="7b3f9c10-0000-4000-8000-abcdefabcdef"

  # The SOURCE account's config dir — this pane's own. The transplant TARGET is a different one.
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/cfg-source"
  TARGET_CFG="$BATS_TEST_TMPDIR/cfg-target"
  SLUG="-Users-x-Development-thing"
  PROJ="$CLAUDE_CONFIG_DIR/projects/$SLUG"
  mkdir -p "$PROJ" "$TARGET_CFG/projects/$SLUG"
  TOMB="$PROJ/$SESS.HANDOFF.json"
  LOCKDIR="$HOME/.reso/limit-recover/locks"; mkdir -p "$LOCKDIR"
  LOCK="$LOCKDIR/$SESS.lock"

  export CLAUDE_CODE_SESSION_ID="$SESS"
}

# The tombstone exactly as lr-transplant.sh:93 writes it, and the lock exactly as :60-69 takes it.
# Both are reproduced from the producer rather than invented, so a change in the producer's shape
# shows up here as a red test instead of as a silently-unreachable class.
mk_transplant() { # $1 (optional) = override for .handed_off_to
  printf '{"handed_off_to":"%s","target_transcript":"%s","ts":"%s","lock":"%s"}\n' \
    "${1:-$TARGET_CFG}" "$TARGET_CFG/projects/$SLUG/$SESS.jsonl" "2026-08-10T00:00:00Z" "$LOCK" \
    > "$TOMB"
  printf '{"sid":"%s","from":"%s","to":"%s","pid":%d}\n' "$SESS" "$CLAUDE_CONFIG_DIR" "$TARGET_CFG" 1 \
    > "$LOCK"
}

close() { # the close under test, with whatever extra args a case needs
  run bash "$HF" self-close --session-id "$SRC_PANE" --dry-run "$@"
}

# A stamp for THIS pane id naming a DIFFERENT cwd — the `stale` tenancy state (kitty reuses small
# integer window ids, so an id can outlive the session stamped under it).
#
# The cwd must be a directory that EXISTS. fired_stamp_tenancy resolves both sides with `cd … && pwd
# -P` and returns `unknown` — not `stale` — when either side is unresolvable, and `unknown` fires
# NEITHER refusal branch. A made-up path therefore produces a test that passes without ever reaching
# the branch it names: measured, the first version of this fixture used /some/other/worktree and the
# exemption test was green against a wall it never touched.
stale_stamp() {
  local other="$BATS_TEST_TMPDIR/some-other-worktree"; mkdir -p "$other"
  printf '{"paneUUID":"%s","cwd":"%s","firedAt":"2026-08-10T00:00:00Z","selfRetire":true}\n' \
    "$SRC_PANE" "$other" > "$CC_FIRED_DIR/$SRC_PANE.json"
}

# A stamp for THIS pane id in THIS cwd whose contract is already USED UP — `closedAt` set is the
# `spent` state (hooks/lib/origin-identity.sh). Same underlying phenomenon as `stale`, kitty reusing
# a window id, read through a different field: a completed self-close spent the contract, and the
# next tenant of that id inherits the stamp.
spent_stamp() {
  printf '{"paneUUID":"%s","cwd":"%s","firedAt":"2026-08-10T00:00:00Z","closedAt":"2026-08-10T01:00:00Z","selfRetire":true}\n' \
    "$SRC_PANE" "$PWD" > "$CC_FIRED_DIR/$SRC_PANE.json"
}

# ── 1. ADMISSION — all six preconditions, and the gate that would otherwise refuse ────────────────

@test "all six preconditions satisfied: the transplanted-source class is ADMITTED" {
  mk_transplant
  close --successor "$SUCCESSOR" --transplanted-source
  [[ "$output" == *"transplanted-source close AUTHORIZED"* ]] || { echo "$output"; false; }
  [[ "$output" == *"handed off to $TARGET_CFG"* ]] || { echo "$output"; false; }
  # the origin gate did NOT fire — the class is what carried it past, not an override
  [[ "$output" != *"this is an ORIGIN session"* ]] || { echo "$output"; false; }
  # and it got there WITHOUT the blunt override anywhere in play
  [[ "$output" != *"--allow-origin-close"* ]] || { echo "$output"; false; }
}

# THE CONTROL for the test above. Identical fixture, flag removed. Without this, "ADMITTED" could be
# reporting a gate that was never going to refuse in the first place, and every refusal test below
# would be asserting against a wall that is not there.
@test "CONTROL: the same pane WITHOUT the flag is refused by the origin gate" {
  mk_transplant
  close --successor "$SUCCESSOR"
  [ "$status" -eq 2 ]
  [[ "$output" == *"this is an ORIGIN session"* ]] || { echo "$output"; false; }
}

# The SECOND refusal branch. `stale` is a different fact from `absent` — a stamp exists for this pane
# id but names another cwd (kitty reuses small integer ids, so an id can outlive its session). Both
# branches must honour the class, and this is the one a same-file fix is most likely to miss: it is
# ~20 lines from the other and reads almost identically.
@test "the class exempts the STALE-stamp refusal branch too, not only the ABSENT one" {
  mk_transplant
  stale_stamp
  close --successor "$SUCCESSOR" --transplanted-source
  [[ "$output" == *"transplanted-source close AUTHORIZED"* ]] || { echo "$output"; false; }
  [[ "$output" != *"belongs to a DIFFERENT session"* ]] || { echo "$output"; false; }
}

# The THIRD refusal branch, and the one this class met by rebase rather than by design: trunk's
# CLOSE_INTEGRITY work added `spent` while this was in flight. It is the same pane-id reuse `stale`
# catches, read through closedAt — and a named class establishes its authorisation from evidence
# that has nothing to do with the fired-peer stamp, so a contract some PREVIOUS tenant of this id
# spent says nothing about whether THIS session was transplanted. Exempt, for the same reason and by
# the same predicate.
@test "the class exempts the SPENT-stamp refusal branch, met at the rebase" {
  mk_transplant
  spent_stamp
  close --successor "$SUCCESSOR" --transplanted-source
  [[ "$output" == *"transplanted-source close AUTHORIZED"* ]] || { echo "$output"; false; }
  [[ "$output" != *"is SPENT"* ]] || { echo "$output"; false; }
}

@test "CONTROL: a spent stamp WITHOUT the flag still hits the spent-branch refusal" {
  mk_transplant
  spent_stamp
  close --successor "$SUCCESSOR"
  [ "$status" -eq 2 ]
  [[ "$output" == *"is SPENT"* ]] || { echo "$output"; false; }
}

@test "CONTROL: a stale stamp WITHOUT the flag still hits the stale-branch refusal" {
  mk_transplant
  stale_stamp
  close --successor "$SUCCESSOR"
  [ "$status" -eq 2 ]
  [[ "$output" == *"belongs to a DIFFERENT session"* ]] || { echo "$output"; false; }
}

# ── 2. PRECONDITION (2) — a carried session, never an end-of-line ────────────────────────────────

@test "--terminal never qualifies: the class asserts something IS carrying the session" {
  mk_transplant
  close --terminal --transplanted-source
  [ "$status" -eq 2 ]
  [[ "$output" == *"needs --successor"* ]] || { echo "$output"; false; }
  [[ "$output" != *"AUTHORIZED"* ]] || { echo "$output"; false; }
}

# ── 3. PRECONDITION (3) — the tombstone, and only a real one ─────────────────────────────────────

@test "no \$CLAUDE_CODE_SESSION_ID: there is nothing to look the tombstone up by" {
  mk_transplant
  unset CLAUDE_CODE_SESSION_ID
  close --successor "$SUCCESSOR" --transplanted-source
  [ "$status" -eq 2 ]
  [[ "$output" == *"CLAUDE_CODE_SESSION_ID is unset"* ]] || { echo "$output"; false; }
}

@test "no tombstone: the flag cannot confer the category it names" {
  # deliberately NOT calling mk_transplant — the lock exists, the tombstone does not
  mkdir -p "$LOCKDIR"; printf '{}\n' > "$LOCK"
  close --successor "$SUCCESSOR" --transplanted-source
  [ "$status" -eq 2 ]
  [[ "$output" == *"NO transplant tombstone"* ]] || { echo "$output"; false; }
  [[ "$output" == *"cannot confer one"* ]] || { echo "$output"; false; }
}

@test "unparseable tombstone: an unreadable record is not evidence" {
  mk_transplant
  printf 'not json at all\n' > "$TOMB"
  close --successor "$SUCCESSOR" --transplanted-source
  [ "$status" -eq 2 ]
  [[ "$output" == *"not valid JSON"* ]] || { echo "$output"; false; }
}

@test "tombstone with no .handed_off_to: it does not say where the session went" {
  mk_transplant
  printf '{"ts":"2026-08-10T00:00:00Z","lock":"%s"}\n' "$LOCK" > "$TOMB"
  close --successor "$SUCCESSOR" --transplanted-source
  [ "$status" -eq 2 ]
  [[ "$output" == *"no .handed_off_to"* ]] || { echo "$output"; false; }
}

@test "two tombstones for one session uuid: refused, never picked from" {
  mk_transplant
  mkdir -p "$CLAUDE_CONFIG_DIR/projects/-other-slug"
  cp "$TOMB" "$CLAUDE_CONFIG_DIR/projects/-other-slug/$SESS.HANDOFF.json"
  close --successor "$SUCCESSOR" --transplanted-source
  [ "$status" -eq 2 ]
  [[ "$output" == *"more than one transplant tombstone"* ]] || { echo "$output"; false; }
}

# ── 4. PRECONDITION (4) — it really moved OFF this account ───────────────────────────────────────

@test "handed off to THIS SAME config dir: not a transplant, so nothing is carrying it" {
  mk_transplant "$CLAUDE_CONFIG_DIR"
  close --successor "$SUCCESSOR" --transplanted-source
  [ "$status" -eq 2 ]
  [[ "$output" == *"THIS SAME config dir"* ]] || { echo "$output"; false; }
}

@test "a trailing slash is not a different account — the comparison normalises it" {
  # The producer writes whatever $TO it was given; an operator passing `--to ~/.claude-next/` would
  # otherwise walk straight through precondition 4 on a pure string difference.
  mk_transplant "$CLAUDE_CONFIG_DIR/"
  close --successor "$SUCCESSOR" --transplanted-source
  [ "$status" -eq 2 ]
  [[ "$output" == *"THIS SAME config dir"* ]] || { echo "$output"; false; }
}

# ── 5. PRECONDITION (5) — the split-brain lock still held ────────────────────────────────────────

@test "the lock is gone: the move was released or superseded, so the husk claim no longer holds" {
  mk_transplant
  rm -f "$LOCK"
  close --successor "$SUCCESSOR" --transplanted-source
  [ "$status" -eq 2 ]
  [[ "$output" == *"split-brain lock is gone"* ]] || { echo "$output"; false; }
}

@test "the tombstone names no lock at all: same refusal, and it SAYS which" {
  mk_transplant
  printf '{"handed_off_to":"%s"}\n' "$TARGET_CFG" > "$TOMB"
  close --successor "$SUCCESSOR" --transplanted-source
  [ "$status" -eq 2 ]
  [[ "$output" == *"none named in the tombstone"* ]] || { echo "$output"; false; }
}

# ── 6. PRECONDITION (0) — the kill switch, and class exclusivity ─────────────────────────────────

@test "CC_TRANSPLANT_SOURCE_CLOSE=0 disables the path: it falls THROUGH to the origin gate" {
  mk_transplant
  export CC_TRANSPLANT_SOURCE_CLOSE=0
  close --successor "$SUCCESSOR" --transplanted-source
  [ "$status" -eq 2 ]
  # not a new refusal of its own — the pre-existing gate, unchanged, exactly as before this class
  [[ "$output" == *"this is an ORIGIN session"* ]] || { echo "$output"; false; }
  [[ "$output" != *"AUTHORIZED"* ]] || { echo "$output"; false; }
}

@test "two class flags at once name two different categories: refused, not merged" {
  # Reaching this guard needs the ASSIGNEE path to SUCCEED first — it adjudicates earlier, and on a
  # pane that is not an assignee it refuses on its own precondition long before the classes could
  # meet. So the fixture makes this pane a genuine orphaned assignee (assignee argv on its tty, a
  # registry row for its lead, that lead's pid provably reaped) AND a genuine transplanted source.
  # Without that setup the test would still go green — on the assignee refusal — and would say
  # nothing about whether two classes can merge.
  mk_transplant
  local lead_sid="lead-sess-0001" dp
  ( exec true ) & dp=$!
  wait "$dp" 2>/dev/null || true
  run kill -0 "$dp"; [ "$status" -ne 0 ]        # positive control: the lead's pid really is gone
  printf '%s\n' "/usr/local/bin/node /opt/claude/cli.js --agent-id gu5-decide@session-$lead_sid --model claude-opus-5" \
    > "$PS_ARGV_DIR/TTY-$SRC_PANE"
  printf '{"paneUUID":"LEADPANE","session_id":"%s","pid":%s}\n' "$lead_sid" "$dp" \
    > "$CC_REGISTRY_DIR/LEADPANE.json"

  # CONTROL: that fixture really does admit the assignee class on its own.
  close --terminal --orphaned-assignee
  [[ "$output" == *"orphaned-assignee close AUTHORIZED"* ]] || { echo "$output"; false; }

  close --successor "$SUCCESSOR" --transplanted-source --orphaned-assignee
  [ "$status" -eq 2 ]
  [[ "$output" == *"DIFFERENT classes"* ]] || { echo "$output"; false; }
  [[ "$output" != *"transplanted-source close AUTHORIZED"* ]] || { echo "$output"; false; }
}

# ── 7. the override this class exists NOT to widen ───────────────────────────────────────────────

@test "the class is a NAMED category, not a second spelling of --allow-origin-close" {
  # A source-shape assertion on purpose. The behavioural tests above prove the class works; this one
  # pins WHY it was built that way, and is the assertion that would catch a later "simplification"
  # into the blunt override. The override's own uses are unchanged and stay countable.
  run grep -c 'SC_ALLOW_ORIGIN_CLOSE' "$HF"
  [ "$status" -eq 0 ]
  # 1 init + 1 argparse + 3 refusal branches (stale · spent · absent) — the pre-existing set, with
  # `spent` arriving from trunk's CLOSE_INTEGRITY work, not from this class. THIS CLASS ADDS NONE,
  # which is the whole assertion. Was 4 before that landed; bumped at the rebase, deliberately and
  # against the diff, never to make a red go away.
  [ "$output" = "5" ] || { echo "allow-origin-close usages moved: $output (expected 5)"; false; }
  # and the new path never mentions it
  run bash -c "sed -n '/TRANSPLANTED-SOURCE PATH/,/^  fi\$/p' '$HF' | grep -c 'ALLOW_ORIGIN_CLOSE'"
  [ "$output" = "0" ] || { echo "the transplanted-source block reaches for the override"; false; }
}

@test "every class-gated site reads ONE predicate, so a FIFTH class cannot be half-added" {
  # The refusal branches are each pinned behaviourally above (revert one, exactly its own test
  # reddens). The ADOPTION site cannot be: reverting it changes nothing observable, because adoption
  # only ever replaces an ABSENT stamp with a valid one and an admitted class is past the gate either
  # way — measured, its per-site mutant reddened zero tests. That is precisely the site a future
  # class would be missed at, so it is pinned structurally instead.
  #
  # THIS ASSERTION HAS ALREADY EARNED ITS KEEP. It read 3 when written; the CLOSE_INTEGRITY work
  # landed a FOURTH class-gated branch on trunk while this was in flight (`spent` — the same pane-id
  # reuse `stale` catches, read through closedAt), and the rebase conflict it caused is exactly the
  # half-added case: taking either side wholesale gives a green rebase and a gate where one branch
  # still asks the old single-class question. Bump the count deliberately when a site is added, never
  # to make a red go away.
  run grep -c '"\$SC_CLASS_EXEMPT" = 0' "$HF"
  [ "$output" = "4" ] || { echo "expected 4 class-gated sites reading the predicate, got $output"; false; }
  # and no site still spells the old single-class test
  run grep -c 'SC_ORIGIN_CLASS" != "assignee"' "$HF"
  [ "$output" = "0" ] || { echo "a class-gated site still tests only for 'assignee'"; false; }
}
