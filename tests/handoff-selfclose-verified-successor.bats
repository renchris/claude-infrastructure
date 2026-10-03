#!/usr/bin/env bats
# handoff-fire.sh self-close — THE FIFTH ADMISSIBLE CLASS: verified-successor
# (docs/plans/AGENT_PEER_WAKE.md, capability 2).
#
# THE DEFECT. An operator-launched (ORIGIN) pane that has finished and handed its work to a live
# successor could not retire: the origin gate refuses every close without a fired-peer stamp, so the
# close became an operator hand-step (2026-10-03, pane tm2-plan-replan-10 → claude-infrastructure-83).
#
# THE FIX names the category instead of widening --allow-origin-close. Admission needs ALL of: the
# successor READ this pane's handover (receipt `read`, never merely delivered or surfaced), a clean
# tree, and no open custody this pane owns or cannot attribute away. Every precondition has a test
# for its ABSENCE below, each asserting the ORIGIN GATE still refuses — a failed check falls through
# to the unchanged gate. --terminal, --allow-dirty, --dirty-owner and --successor-assume-engaged are
# each pinned as never reaching the class.
#
# Technique and shims are tests/handoff-selfclose-transplanted-source.bats's: PATH shims, --dry-run
# so the gate runs but nothing is armed or closed, the whole script invoked.
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

  export CLAUDE_CODE_SESSION_ID="$SESS"

  # ── this class's fixtures ──
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/cfg"; mkdir -p "$CLAUDE_CONFIG_DIR"
  export CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/mbox"; mkdir -p "$CC_MAILBOX_DIR/.sent-lines"
  WT="$BATS_TEST_TMPDIR/wt"; mkdir -p "$WT"; touch "$WT/.GITCLEAN"; cd "$WT" || return 1
  # the handover: three lines in the successor's inbox, this pane's record naming line 3
  printf 'l1\nl2\nl3 HANDOVER\n' > "$CC_MAILBOX_DIR/$SUCCESSOR.md"
  printf '2026-10-03T12:00:00-0500 %s 3 %s\n' "$SUCCESSOR" "$SUCCESSOR" > "$CC_MAILBOX_DIR/.sent-lines/$SRC_PANE"
  read_receipt read
  # custody: a fake cc-custody whose answer is a file (absent file ⇒ the store is unreadable)
  CUSTODY_JSON="$BATS_TEST_TMPDIR/custody.json"; printf '[]\n' > "$CUSTODY_JSON"
  printf '#!/bin/bash\n[ -f "%s" ] || exit 1\ncat "%s"\n' "$CUSTODY_JSON" "$CUSTODY_JSON" > "$SHIM/cc-custody"
  chmod +x "$SHIM/cc-custody"; export CC_CUSTODY_BIN="$SHIM/cc-custody"
  unset CC_ORIGIN_SUCCESSOR_CLOSE
}

read_receipt() { # read | surfaced | unread — set the successor box's cursors relative to line 3
  case "$1" in
    read)     echo 3 > "$CC_MAILBOX_DIR/$SUCCESSOR.seen"; echo 3 > "$CC_MAILBOX_DIR/$SUCCESSOR.acked" ;;
    surfaced) echo 3 > "$CC_MAILBOX_DIR/$SUCCESSOR.seen"; echo 2 > "$CC_MAILBOX_DIR/$SUCCESSOR.acked" ;;
    unread)   echo 2 > "$CC_MAILBOX_DIR/$SUCCESSOR.seen"; echo 2 > "$CC_MAILBOX_DIR/$SUCCESSOR.acked" ;;
  esac
}

close() { run bash "$HF" self-close --session-id "$SRC_PANE" --dry-run "$@"; }

origin_refused() {
  [ "$status" -eq 2 ] || { echo "status=$status"; echo "$output"; return 1; }
  [[ "$output" == *"this is an ORIGIN session"* ]] || { echo "$output"; return 1; }
  [[ "$output" != *"verified-successor close AUTHORIZED"* ]] || { echo "$output"; return 1; }
}

stale_stamp() {
  local other="$BATS_TEST_TMPDIR/some-other-worktree"; mkdir -p "$other"
  printf '{"paneUUID":"%s","cwd":"%s","firedAt":"2026-08-10T00:00:00Z","selfRetire":true}\n' \
    "$SRC_PANE" "$other" > "$CC_FIRED_DIR/$SRC_PANE.json"
}

# ── admission ────────────────────────────────────────────────────────────────────────────────────

@test "all evidence holds: the verified-successor class is ADMITTED, without the override" {
  close --successor "$SUCCESSOR"
  [[ "$output" == *"✓ V1: the successor READ the handover (line 3"* ]] || { echo "$output"; false; }
  [[ "$output" == *"verified-successor close AUTHORIZED"* ]] || { echo "$output"; false; }
  [[ "$output" != *"this is an ORIGIN session"* ]] || { echo "$output"; false; }
  [[ "$output" != *"--allow-origin-close"* ]] || { echo "$output"; false; }
}

@test "the class also exempts the STALE-stamp refusal branch" {
  stale_stamp
  close --successor "$SUCCESSOR"
  [[ "$output" == *"verified-successor close AUTHORIZED"* ]] || { echo "$output"; false; }
  [[ "$output" != *"belongs to a DIFFERENT session"* ]] || { echo "$output"; false; }
}

@test "a VALID fired-peer stamp is not touched: the class is not even considered" {
  printf '{"paneUUID":"%s","cwd":"%s","firedAt":"2026-10-03T00:00:00Z","selfRetire":true}\n' \
    "$SRC_PANE" "$(pwd -P)" > "$CC_FIRED_DIR/$SRC_PANE.json"
  close --successor "$SUCCESSOR"
  [[ "$output" != *"checking the verified-successor class"* ]] || { echo "$output"; false; }
}

# ── V1: the handover must be READ ────────────────────────────────────────────────────────────────

@test "V1: no recorded message to the successor ⇒ origin gate refuses" {
  rm "$CC_MAILBOX_DIR/.sent-lines/$SRC_PANE"
  close --successor "$SUCCESSOR"
  origin_refused
  [[ "$output" == *"✗ V1: this pane"*"has no recorded message"* ]] || { echo "$output"; false; }
}

@test "V1: a record for a DIFFERENT inbox does not count" {
  printf '2026-10-03T12:00:00-0500 SOMEONE-ELSE 3 x\n' > "$CC_MAILBOX_DIR/.sent-lines/$SRC_PANE"
  close --successor "$SUCCESSOR"
  origin_refused
  [[ "$output" == *"has no recorded message"* ]] || { echo "$output"; false; }
}

@test "V1: SURFACED is not read ⇒ origin gate refuses" {
  read_receipt surfaced
  close --successor "$SUCCESSOR"
  origin_refused
  [[ "$output" == *"reads 'surfaced', not 'read'"* ]] || { echo "$output"; false; }
}

@test "V1: UNREAD ⇒ origin gate refuses, naming the wake and the receipt command" {
  read_receipt unread
  close --successor "$SUCCESSOR"
  origin_refused
  [[ "$output" == *"reads 'unread'"* ]] || { echo "$output"; false; }
  [[ "$output" == *"cc-wake $SUCCESSOR"* ]] || { echo "$output"; false; }
}

@test "V1: the NEWEST record decides — an older read line does not cover a newer unread one" {
  printf 'l4 SECOND HANDOVER\n' >> "$CC_MAILBOX_DIR/$SUCCESSOR.md"
  printf '2026-10-03T12:05:00-0500 %s 4 %s\n' "$SUCCESSOR" "$SUCCESSOR" >> "$CC_MAILBOX_DIR/.sent-lines/$SRC_PANE"
  close --successor "$SUCCESSOR"
  origin_refused
  [[ "$output" == *"line 4"* ]] || { echo "$output"; false; }
}

# ── V2: clean tree ───────────────────────────────────────────────────────────────────────────────

@test "V2: a dirty tree ⇒ origin gate refuses" {
  rm "$WT/.GITCLEAN"; touch "$WT/.GITDIRTY"
  close --successor "$SUCCESSOR"
  origin_refused
  [[ "$output" == *"✗ V2"* ]] || { echo "$output"; false; }
}

# ── V3: custody ──────────────────────────────────────────────────────────────────────────────────

@test "V3: an open custody row THIS pane owns ⇒ origin gate refuses" {
  printf '[{"kind":"open","originatorPane":"%s","targetPane":"x"}]\n' "$SRC_PANE" > "$CUSTODY_JSON"
  close --successor "$SUCCESSOR"
  origin_refused
  [[ "$output" == *"✗ V3: open custody"* ]] || { echo "$output"; false; }
}

@test "V3: an UNATTRIBUTABLE open row still counts ⇒ refused" {
  printf '[{"kind":"open","targetPane":"x"}]\n' > "$CUSTODY_JSON"
  close --successor "$SUCCESSOR"
  origin_refused
}

@test "V3: another pane's row in the same cwd is not this pane's debt ⇒ admitted" {
  printf '[{"kind":"open","originatorPane":"OTHER","notifyBack":"wt-OTHER"}]\n' > "$CUSTODY_JSON"
  close --successor "$SUCCESSOR"
  [[ "$output" == *"verified-successor close AUTHORIZED"* ]] || { echo "$output"; false; }
}

@test "V3: an unreadable custody store REFUSES (unknown debt is not zero)" {
  rm "$CUSTODY_JSON"
  close --successor "$SUCCESSOR"
  origin_refused
  [[ "$output" == *"custody store could not be read"* ]] || { echo "$output"; false; }
}

# ── what never reaches the class ─────────────────────────────────────────────────────────────────

@test "--terminal is still refused for an origin session, evidence or not" {
  close --terminal
  origin_refused
  [[ "$output" != *"checking the verified-successor class"* ]] || { echo "$output"; false; }
}

@test "--allow-dirty, --dirty-owner and --successor-assume-engaged each keep the class out" {
  for f in --allow-dirty "--dirty-owner successor" --successor-assume-engaged; do
    # shellcheck disable=SC2086
    close --successor "$SUCCESSOR" $f
    [[ "$output" == *"verified-successor class NOT considered"* ]] || { echo "[$f] $output"; false; }
    [[ "$output" != *"verified-successor close AUTHORIZED"* ]] || { echo "[$f] $output"; false; }
  done
}

@test "kill switch CC_ORIGIN_SUCCESSOR_CLOSE=0 restores the plain origin refusal" {
  CC_ORIGIN_SUCCESSOR_CLOSE=0 close --successor "$SUCCESSOR"
  origin_refused
  [[ "$output" != *"checking the verified-successor class"* ]] || { echo "$output"; false; }
}

@test "--allow-origin-close stays the operator's override: it passes the gate even when the class cannot" {
  read_receipt unread
  close --successor "$SUCCESSOR" --allow-origin-close
  [[ "$output" == *"verified-successor class NOT established"* ]] || { echo "$output"; false; }
  [[ "$output" != *"this is an ORIGIN session"* ]] || { echo "$output"; false; }
}

@test "the class never reads the override flag (it is a named class, not a second spelling of it)" {
  run bash -c "sed -n '/VERIFIED-SUCCESSOR PATH/,/^  fi\$/p' '$HF' | grep -c 'ALLOW_ORIGIN_CLOSE'"
  [ "$output" = "0" ]
}
