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
  # git, per DIRECTORY. The default answer is still "not a work tree", so the dirty-tree guard is
  # skipped hermetically and independently of this test's CWD, exactly as before. What is new is that
  # the answer is keyed on the directory `-C` names (or $PWD when it names none): a marker file makes
  # one tree a CLEAN work tree and another a DIRTY one, which is what lets a test tell "the guard read
  # the SOURCE pane's worktree" from "the guard read the driver's". No marker anywhere ⇒ every
  # pre-existing test sees byte-identical behaviour.
  cat > "$SHIM/git" <<'SH'
#!/usr/bin/env bash
dir=""
if [ "${1:-}" = "-C" ]; then dir="${2:-}"; shift 2; fi
[ -n "$dir" ] || dir="$PWD"
case "${1:-}" in
  rev-parse) [ -f "$dir/.GITDIRTY" ] || [ -f "$dir/.GITCLEAN" ] || exit 1; exit 0 ;;
  status)    [ -f "$dir/.GITDIRTY" ] && printf ' M tracked-file\n'; exit 0 ;;
esac
exit 0
SH
  # TWO distinct ps forms, and the shim must not conflate them (same split as the assignee suite):
  #   ps -t <tty> -o command=   → full argv    (agent_id_on_tty, the assignee oracle)
  #   ps -o comm= -p <pid>      → command NAME (originator_liveness's recycled-pid discriminator)
  # Both answer EMPTY unless a fixture file is placed, so the default posture is "no assignee, no
  # teammates" — which is what every test here but the class-exclusivity one wants.
  PS_ARGV_DIR="$BATS_TEST_TMPDIR/argv"; mkdir -p "$PS_ARGV_DIR"
  PS_COMM_DIR="$BATS_TEST_TMPDIR/comm"; mkdir -p "$PS_COMM_DIR"
  PS_PIDS_DIR="$BATS_TEST_TMPDIR/pids"; mkdir -p "$PS_PIDS_DIR"
  export PS_ARGV_DIR PS_COMM_DIR PS_PIDS_DIR
  cat > "$SHIM/ps" <<'SH'
#!/usr/bin/env bash
tty="" pid="" want=""
while [ $# -gt 0 ]; do
  case "$1" in
    -t) tty="${2:-}"; shift 2 ;;
    -p) pid="${2:-}"; shift 2 ;;
    -o) case "${2:-}" in command=) want=argv ;; comm=) want=comm ;; tty=) want=tty ;; pid=) want=pidlist ;; esac; shift 2 ;;
    -axo) want=ptree; shift 2 ;;
    *)  shift ;;
  esac
done
if [ "$want" = argv ] && [ -n "$tty" ]; then
  [ -f "$PS_ARGV_DIR/$tty" ] && cat "$PS_ARGV_DIR/$tty"
  exit 0
fi
if [ "$want" = pidlist ] && [ -n "$tty" ]; then
  # `ps -o pid= -t <tty>` — pane_cc_state's roots. Empty by default (a tty we cannot read ⇒
  # `unknown`, the fail-safe verdict), so only a test that plants a pid changes any behaviour.
  [ -f "$PS_PIDS_DIR/$tty" ] && cat "$PS_PIDS_DIR/$tty"
  exit 0
fi
if [ "$want" = ptree ]; then
  # `ps -axo pid=,ppid=` — the closure pane_cc_state walks from those roots.
  [ -n "${PS_PTREE:-}" ] && printf '%s\n' "$PS_PTREE"
  exit 0
fi
if [ "$want" = tty ]; then
  # `ps -o tty= -p <pids>` — what own_ancestry_ttys reads to decide whether a pane is THIS
  # session's. Silent unless a test opts in, so the default posture stays pane_ownership=unknown
  # (which verify_self_pane deliberately does not refuse) exactly as before this arm existed.
  [ -n "${PS_TTY_OUT:-}" ] && printf '%s\n' "$PS_TTY_OUT"
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
  # 1 init + 1 argparse + 4 refusal branches (stale · spent · absent-repairable · absent) — the
  # pre-existing set, with `spent` arriving from trunk's CLOSE_INTEGRITY work and the SECOND `absent`
  # branch from the stamp-REPAIR work (item c163f42390a3) that landed after it. THIS CLASS ADDS NONE,
  # which is the whole assertion. Was 4, then 5; bumped to 6 deliberately and against the diff —
  # measured on pristine origin/main, where this test was already RED and the repair branch at :5011
  # is the sixth usage. Never bumped to make a red go away.
  [ "$output" = "6" ] || { echo "allow-origin-close usages moved: $output (expected 6)"; false; }
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
  # 3 → 4 (`spent`, CLOSE_INTEGRITY) → 5 (the stamp-REPAIR refusal at :5011, item c163f42390a3, which
  # landed WITHOUT bumping this literal and left the suite red on trunk — measured on pristine
  # origin/main before this change). Bumped against that diff, having read the site.
  run grep -c '"\$SC_CLASS_EXEMPT" = 0' "$HF"
  [ "$output" = "5" ] || { echo "expected 5 class-gated sites reading the predicate, got $output"; false; }
  # and no site still spells the old single-class test
  run grep -c 'SC_ORIGIN_CLASS" != "assignee"' "$HF"
  [ "$output" = "0" ] || { echo "a class-gated site still tests only for 'assignee'"; false; }
}

# ── 8. THE REMOTE FORM — the husk cannot close ITSELF (item c5d25ebe630b) ────────────────────────
#
# THE CASE THE WHOLE CLASS WAS BUILT FOR, and the one it could not reach. Measured 2026-08-10: three
# sessions were transplanted off next3 while next3 sat at 100% of its 5-hour window. A session at its
# limit CANNOT EXECUTE A TURN, so it can never run the command that retires it — the recovery is
# driven from a THIRD pane, and `self-close` there closes the DRIVER. So the flag was not used and
# three husk panes were left standing.
#
# WHAT MAKES NAMING ANOTHER PANE SAFE, given that verify_self_pane refuses exactly that. The gate
# under it is not "is this pane mine" — that is a PROXY for *does this pane hold the session this
# close is about*, and the process tree is only ever evidence a session has about ITSELF. For a pane
# the caller merely names it proves nothing (not-mine is equally true of the husk and of a bystander),
# which is why an unbacked assertion would retire an innocent pane. The registry row is independent
# evidence of the pairing, from a producer with no stake in this close (hooks/session-start.sh) and
# with an existing consumer (successor_pin reads the same row for the successor half of this close).
#
# EVERY TEST BELOW BUT THE FIRST IS A REFUSAL, and the last three prove the six preconditions still
# bind in remote mode ON THE SOURCE SESSION'S OWN EVIDENCE — its tombstone, found across the accounts,
# and the config dir derived from where that tombstone sits, never the driver's env.

remote_setup() {   # the driver is a DIFFERENT account and a DIFFERENT session than the husk
  SRC_CFG="$CLAUDE_CONFIG_DIR"
  DRIVER_CFG="$BATS_TEST_TMPDIR/cfg-driver"; mkdir -p "$DRIVER_CFG/projects"
  export CC_PROJECTS_DIRS="$SRC_CFG/projects $DRIVER_CFG/projects"
  export CLAUDE_CONFIG_DIR="$DRIVER_CFG"
  # If ANY of the six preconditions still read the invoker's env, this sid is what they would find —
  # a session with no tombstone anywhere. Admission below therefore proves the source's own sid was
  # used, rather than merely that the path ran.
  export CLAUDE_CODE_SESSION_ID="dr1v3r00-0000-4000-8000-000000000000"
}

src_row() {        # $1 = the session the registry says lives in the source pane (omit ⇒ no such field)
  if [ -n "${1:-}" ]; then
    printf '{"paneUUID":"%s","cwd":"%s","account":"claude-tertiary","pid":4242,"session_id":"%s"}\n' \
      "$SRC_PANE" "${SRC_ROW_CWD:-$PWD}" "$1" > "$CC_REGISTRY_DIR/$SRC_PANE.json"
  else
    printf '{"paneUUID":"%s","cwd":"%s","account":"claude-tertiary","pid":4242}\n' \
      "$SRC_PANE" "${SRC_ROW_CWD:-$PWD}" > "$CC_REGISTRY_DIR/$SRC_PANE.json"
  fi
}

close_remote() {   # NOTE: no --session-id — the source pane is named by --source-pane alone
  run bash "$HF" self-close --dry-run --source-pane "$SRC_PANE" --source-session "$SESS" "$@"
}

@test "remote: the registry row binds pane→session, and the class is ADMITTED on the SOURCE's evidence" {
  mk_transplant
  src_row "$SESS"
  remote_setup
  close_remote --successor "$SUCCESSOR" --transplanted-source
  [[ "$output" == *"is PROVEN to hold session ${SESS:0:8} by its registry row"* ]] || { echo "$output"; false; }
  [[ "$output" == *"transplanted-source close AUTHORIZED"* ]] || { echo "$output"; false; }
  # The sid in the authorisation is the SOURCE's, not the driver's — the env-vs-argument proof.
  [[ "$output" == *"session ${SESS:0:8} was handed off to $TARGET_CFG"* ]] || { echo "$output"; false; }
  [[ "$output" != *"dr1v3r00"* ]] || { echo "the driver's own session leaked into the close: $output"; false; }
  # and it got there without the blunt override, exactly like the local form
  [[ "$output" != *"--allow-origin-close"* ]] || { echo "$output"; false; }
}

@test "remote CONTROL: the row names a DIFFERENT session — REFUSED, nothing closed" {
  # The hazard the naive version of this flag was correctly refused over: an unbacked "pane P holds
  # session X" retires a live session that merely got named.
  mk_transplant
  src_row "9999ffff-0000-4000-8000-999999999999"
  remote_setup
  close_remote --successor "$SUCCESSOR" --transplanted-source
  [ "$status" -eq 2 ]
  [[ "$output" == *"does NOT hold session ${SESS:0:8}"* ]] || { echo "$output"; false; }
  [[ "$output" == *"the registry says that pane holds 9999ffff"* ]] || { echo "$output"; false; }
  [[ "$output" != *"AUTHORIZED"* ]] || { echo "$output"; false; }
}

@test "remote CONTROL: no registry row for the named pane — REFUSED" {
  mk_transplant
  rm -f "$CC_REGISTRY_DIR/$SRC_PANE.json"
  remote_setup
  close_remote --successor "$SUCCESSOR" --transplanted-source
  [ "$status" -eq 2 ]
  [[ "$output" == *"no session-registry row for pane $SRC_PANE"* ]] || { echo "$output"; false; }
}

@test "remote CONTROL: the row carries no .session_id — REFUSED, never guessed at" {
  mk_transplant
  src_row
  remote_setup
  close_remote --successor "$SUCCESSOR" --transplanted-source
  [ "$status" -eq 2 ]
  [[ "$output" == *"names no .session_id"* ]] || { echo "$output"; false; }
}

@test "remote: --source-pane is admissible ONLY with --transplanted-source" {
  # Without the class this would be a general-purpose 'close that pane', which self-close is
  # deliberately not: the justification for closing someone else's pane is that it is a husk over a
  # session being carried elsewhere, and only the class establishes that.
  mk_transplant
  src_row "$SESS"
  remote_setup
  close_remote --successor "$SUCCESSOR"
  [ "$status" -eq 2 ]
  [[ "$output" == *"admissible ONLY with --transplanted-source"* ]] || { echo "$output"; false; }
}

@test "remote: the pane and the session are a PAIR — half of it is refused" {
  mk_transplant
  src_row "$SESS"
  remote_setup
  run bash "$HF" self-close --dry-run --source-pane "$SRC_PANE" --successor "$SUCCESSOR" --transplanted-source
  [ "$status" -eq 2 ]
  [[ "$output" == *"are a PAIR"* ]] || { echo "$output"; false; }
  run bash "$HF" self-close --dry-run --source-session "$SESS" --successor "$SUCCESSOR" --transplanted-source
  [ "$status" -eq 2 ]
  [[ "$output" == *"are a PAIR"* ]] || { echo "$output"; false; }
}

@test "remote: --source-pane and --session-id both name the pane to close — refused, not merged" {
  mk_transplant
  src_row "$SESS"
  remote_setup
  run bash "$HF" self-close --dry-run --session-id "$SRC_PANE" \
      --source-pane "$SRC_PANE" --source-session "$SESS" --successor "$SUCCESSOR" --transplanted-source
  [ "$status" -eq 2 ]
  [[ "$output" == *"both name the pane to close"* ]] || { echo "$output"; false; }
}

@test "remote: precondition (4) reads the config dir the TOMBSTONE sits in, not the driver's" {
  # The tombstone hands the session back to the SOURCE account — not a transplant, so nothing is
  # carrying it. A build that compared .handed_off_to against the DRIVER's config dir would see two
  # different paths and admit this close, retiring a session outright. That is what this reddens on.
  mk_transplant "$CLAUDE_CONFIG_DIR"
  src_row "$SESS"
  remote_setup
  close_remote --successor "$SUCCESSOR" --transplanted-source
  [ "$status" -eq 2 ]
  [[ "$output" == *"hands this session off to THIS SAME config dir"* ]] || { echo "$output"; false; }
}

@test "remote: precondition (5) still binds — a released split-brain lock refuses the close" {
  mk_transplant
  rm -f "$LOCK"
  src_row "$SESS"
  remote_setup
  close_remote --successor "$SUCCESSOR" --transplanted-source
  [ "$status" -eq 2 ]
  [[ "$output" == *"split-brain lock is gone"* ]] || { echo "$output"; false; }
}

@test "remote CONTROL: the tombstone is found by SEARCHING the accounts, not by luck" {
  # Drop the source account from the search list and the same fixture must refuse. Without this the
  # admission test could be passing on a build that still globbed one config dir and happened to be
  # pointed at the right one.
  mk_transplant
  src_row "$SESS"
  remote_setup
  export CC_PROJECTS_DIRS="$DRIVER_CFG/projects"
  close_remote --successor "$SUCCESSOR" --transplanted-source
  [ "$status" -eq 2 ]
  [[ "$output" == *"has NO transplant tombstone"* ]] || { echo "$output"; false; }
  [[ "$output" == *"looked for: $DRIVER_CFG/projects/*/$SESS.HANDOFF.json"* ]] || { echo "$output"; false; }
}

@test "remote: the self-identity gate is REPLACED by the binding — a not-mine pane is not refused" {
  # THE SITE THIS PINS, and why the skip is a correctness fix rather than a shortcut. verify_self_pane
  # asks the process tree "is this pane mine". For a pane the caller NAMES that answer is always
  # not-mine — equally for the husk and for a bystander — so the gate cannot distinguish them, and it
  # does not merely refuse: on a DEFAULTED id it ADOPTS, rewriting the target to the pane this
  # process actually lives in. Left in place, the remote form would therefore retarget itself at the
  # DRIVER and close the pane running the recovery, which is the whole defect inverted.
  #
  # The default fixture cannot show this: with no tty answer own_ancestry_ttys is empty,
  # pane_ownership returns `unknown`, and `unknown` is deliberately not a refusal — so the gate is a
  # no-op either way and a mutant that re-enables it reddens nothing. PS_TTY_OUT supplies the
  # ancestry tty, which makes the verdict a real not-mine.
  mk_transplant
  src_row "$SESS"
  remote_setup
  export PS_TTY_OUT="ttys999"                 # this process's tty — NOT the source pane's
  close_remote --successor "$SUCCESSOR" --transplanted-source
  [[ "$output" == *"transplanted-source close AUTHORIZED"* ]] || { echo "$output"; false; }
  [[ "$output" != *"is NOT this session's pane"* ]] || { echo "$output"; false; }
  [[ "$output" != *"self-identity CORRECTED"* ]] || { echo "the gate retargeted the close at the driver: $output"; false; }
}

@test "CONTROL: the LOCAL form still runs the self-identity gate on that same fixture" {
  # The test above must not be readable as "the gate was deleted". Same PS_TTY_OUT, same pane, no
  # --source-pane: the gate runs, reads not-mine, and refuses — so the skip is scoped to the class
  # and the ordinary path is untouched.
  mk_transplant
  export PS_TTY_OUT="ttys999"
  close --successor "$SUCCESSOR" --transplanted-source
  [ "$status" -eq 2 ]
  [[ "$output" == *"is NOT this session's pane"* ]] || { echo "$output"; false; }
  [[ "$output" != *"AUTHORIZED"* ]] || { echo "$output"; false; }
}

# ── 9. THE CWD-SCOPED GUARDS FOLLOW THE SUBJECT, NOT THE CALLER ──────────────────────────────────
#
# The dirty-tree refusal asks "is the tree of the session about to evaporate holding un-persisted
# work". It asked it of $PWD — the same tree only while the closer IS the closed. A driver mid-edit
# is the NORMAL state of the pane driving a recovery, so left alone this guard would refuse most
# real remote closes over perfectly clean husks; and a genuinely dirty husk would pass on the
# driver's cleanliness. The two tests below drive both directions from the same fixture, which is
# what makes them a pair rather than one assertion stated twice.
#
# Reaching the guard at all needs the successor gate satisfied, which is why this section carries
# more fixture than the rest: a pid on the successor's tty, a process tree that reaches it, and a
# `comm` that reads as CC. --successor-assume-engaged skips ONLY the transcript half; it is passed
# here because this section is about the guard BELOW that gate, and the lr-handoff contract that
# forbids the flag is asserted in its own suite.

successor_is_live() {
  printf '5150\n' > "$PS_PIDS_DIR/TTY-$SUCCESSOR"
  export PS_PTREE="5150 1"
  printf 'claude\n' > "$PS_COMM_DIR/5150"
}

@test "remote: the dirty guard reads the SOURCE pane's worktree — a dirty DRIVER does not block it" {
  DRIVER_WT="$BATS_TEST_TMPDIR/driver-wt"; mkdir -p "$DRIVER_WT"; : > "$DRIVER_WT/.GITDIRTY"
  SRC_WT="$BATS_TEST_TMPDIR/src-wt";       mkdir -p "$SRC_WT";    : > "$SRC_WT/.GITCLEAN"
  mk_transplant
  SRC_ROW_CWD="$SRC_WT" src_row "$SESS"
  remote_setup
  successor_is_live
  cd "$DRIVER_WT"
  close_remote --successor "$SUCCESSOR" --transplanted-source --successor-assume-engaged
  [ "$status" -eq 0 ]
  [[ "$output" != *"refusing self-close: dirty git tree"* ]] || { echo "$output"; false; }
  # …and the close it planned is on the SOURCE pane. This is also the assertion that the retarget
  # survived pane resolution: the default one line under it substitutes THIS process's own pane for
  # an empty value, so a lost retarget prints (or closes) the driver instead.
  [[ "$output" == *"pane:      $SRC_PANE"* ]] || { echo "$output"; false; }
  [[ "$output" == *"the SOURCE pane's own worktree $SRC_WT"* ]] || { echo "$output"; false; }
}

@test "remote CONTROL: a dirty SOURCE worktree DOES block it — the guard was moved, not removed" {
  # Without this the test above would be equally green on a build that simply deleted the guard.
  DRIVER_WT="$BATS_TEST_TMPDIR/driver-wt"; mkdir -p "$DRIVER_WT"; : > "$DRIVER_WT/.GITCLEAN"
  SRC_WT="$BATS_TEST_TMPDIR/src-wt";       mkdir -p "$SRC_WT";    : > "$SRC_WT/.GITDIRTY"
  mk_transplant
  SRC_ROW_CWD="$SRC_WT" src_row "$SESS"
  remote_setup
  successor_is_live
  cd "$DRIVER_WT"
  close_remote --successor "$SUCCESSOR" --transplanted-source --successor-assume-engaged
  [ "$status" -eq 1 ]
  [[ "$output" == *"refusing self-close: dirty git tree in $SRC_WT"* ]] || { echo "$output"; false; }
}
