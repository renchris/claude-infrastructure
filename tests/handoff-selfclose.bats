#!/usr/bin/env bats
# Regression guard for handoff-fire.sh SELF-CLOSE — the successor ENGAGEMENT gate + the close-instant
# re-verify + the light pre-close inventory (2026-07-24).
#
# The gaps these lock down:
#   1. ENGAGEMENT (not just liveness). The arm-time successor gate used to be a bare process-existence
#      check (ps | grep node|claude). A successor that BOOTED but never ingested work (cold-fire
#      auto-submit race, /goal-length rejection) passed it — the predecessor closed and the work
#      stranded in BOTH panes. The gate now ALSO requires the successor's transcript to show ≥1 real
#      assistant turn (reusing the spawn-path assistant_turn_in predicate). --successor-assume-engaged
#      skips ONLY that half (for a successor whose transcript is unreadable from this account).
#   2. CLOSE-INSTANT RE-VERIFY. The successor is verified once at arm time, but the detached watcher
#      closes up to ~180s later — a successor dying in that window stranded both panes. The watcher now
#      re-checks the successor's liveness immediately before the close; dead ⇒ do NOT close, page the
#      desk, leave the predecessor alive, exit nonzero.
#   3. PRE-CLOSE INVENTORY (light, WARN-only): unread mail in this session's inbox + peers this session
#      fired that have no live session.
#
# Technique mirrors tests/handoff-splitright.bats: PATH shims for osascript/ps/git (the gate path,
# driven via --dry-run so the gate runs but nothing is armed/closed), a HOME override with recording
# it2/cc-notify stubs (the __selfclose watcher path, invoked directly), and sed-extracted functions
# for the inventory unit checks. `bash "$HF" __selfclose …` runs the watcher body in the foreground —
# no detach, no real panes.

setup() {
  # handoff-fire.sh bounds every external iTerm2 call (osascript / it2 CLI / iterm2 python) through
  # hf_bounded — a timeout(1) wrapper — because a wedged iTerm2 API blocks them indefinitely. These
  # suites EXTRACT individual functions instead of sourcing the script, so that helper is not in
  # scope and an extracted function would die with "hf_bounded: command not found". A passthrough
  # keeps the extracted behaviour byte-identical and deterministic; the helper's OWN semantics
  # (bound applied, expiry -> 124, set-but-empty disable seam) are covered by
  # tests/handoff-fire-it2-bound.bats against the real definition.
  hf_bounded() { "$@"; }
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"

  SHIM="$BATS_TEST_TMPDIR/shim"; mkdir -p "$SHIM"
  OSA_GONE_DIR="$BATS_TEST_TMPDIR/gone"; mkdir -p "$OSA_GONE_DIR"
  PS_DEAD_DIR="$BATS_TEST_TMPDIR/dead";  mkdir -p "$PS_DEAD_DIR"
  export OSA_GONE_DIR PS_DEAD_DIR

  # as_tty's query: `osascript - <uuid>` → print TTY-<uuid>, or empty when a gone-marker exists.
  cat > "$SHIM/osascript" <<'SH'
#!/usr/bin/env bash
uuid=""
while [ $# -gt 0 ]; do
  case "$1" in
    -e) shift 2 2>/dev/null || shift ;;   # -e '<script>' (delay/as_write) → no-op success
    -)  shift ;;
    *)  uuid="$1"; shift ;;
  esac
done
[ -n "$uuid" ] || exit 0
[ -n "${OSA_GONE_DIR:-}" ] && [ -e "$OSA_GONE_DIR/$uuid" ] && exit 0   # pane absent → empty tty
printf '%s' "TTY-$uuid"
exit 0
SH

  # liveness probe: `ps -o comm= -t <tty>` → print "claude" unless a dead-marker exists for <tty>.
  cat > "$SHIM/ps" <<'SH'
#!/usr/bin/env bash
tty=""
while [ $# -gt 0 ]; do case "$1" in -t) tty="${2:-}"; shift 2 ;; *) shift ;; esac; done
[ -n "$tty" ] || exit 0
[ -n "${PS_DEAD_DIR:-}" ] && [ -e "$PS_DEAD_DIR/$tty" ] && exit 0     # no process line → "dead"
printf '%s\n' "claude"
exit 0
SH

  # only `git rev-parse --is-inside-work-tree` is hit in the dry-run gate path — report "not a work
  # tree" so the dirty-tree guard is skipped (hermetic, independent of the test's CWD).
  cat > "$SHIM/git" <<'SH'
#!/usr/bin/env bash
[ "${1:-}" = rev-parse ] && exit 1
exit 0
SH
  chmod +x "$SHIM/osascript" "$SHIM/ps" "$SHIM/git"
  export PATH="$SHIM:$PATH"

  REGDIR="$BATS_TEST_TMPDIR/reg";  mkdir -p "$REGDIR"
  PROJDIR="$BATS_TEST_TMPDIR/proj"; mkdir -p "$PROJDIR"
  export CC_REGISTRY_DIR="$REGDIR" CC_PROJECTS_DIRS="$PROJDIR"

  SUCC="SUCC-PANE"; PRED="PRED-PANE"; SUCC_SESS="succ-sess-0"
  printf '{"session_id":"%s"}\n' "$SUCC_SESS" > "$REGDIR/$SUCC.json"   # registry row → transcript name

  # ORIGIN GATE (2026-07-26): self-close is available ONLY to a session that was FIRED BY an
  # originator. Every test below models a fired PEER retiring — the only legitimate self-close —
  # so stamp $PRED as one. This was previously implicit; the gate makes it explicit.
  # The gate's own behaviour (refuse/allow/override) is covered by the tests at the end of this file.
  export CC_FIRED_DIR="$BATS_TEST_TMPDIR/cc-fired"; mkdir -p "$CC_FIRED_DIR"
  printf '{"paneUUID":"%s","cwd":"/tmp","firedBy":"ORIGINATOR","firedAt":"2026-07-26T18:00:00Z","selfRetire":true}\n' \
    "$PRED" > "$CC_FIRED_DIR/$PRED.json"
}

# a fake HOME with it2 + cc-notify stubs that RECORD their args (for the watcher tests).
mk_home() { # $1=dir
  local h="$1"; mkdir -p "$h/.claude/bin" "$h/.claude/cc-roles"
  cat > "$h/.claude/bin/it2" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$HOME/it2-calls.log"
exit 0
SH
  cat > "$h/.claude/bin/cc-notify" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$HOME/ccnotify-calls.log"
exit 0
SH
  chmod +x "$h/.claude/bin/it2" "$h/.claude/bin/cc-notify"
  printf 'DESK-PANE\n' > "$h/.claude/cc-roles/desk"
}

# ── 1. ENGAGEMENT GATE ─────────────────────────────────────────────────────────────────────────

@test "gate: successor process-alive but transcript has ZERO assistant turns → exit 3, no close" {
  printf '%s\n' \
    '{"type":"user","message":{"content":"do the thing"}}' \
    '{"type":"system","subtype":"init"}' > "$PROJDIR/$SUCC_SESS.jsonl"   # born, never ran
  run bash "$HF" self-close --dry-run --session-id "$PRED" --successor "$SUCC"
  [ "$status" -eq 3 ]
  [[ "$output" == *"NEVER ENGAGED"* ]] || false
  [[ "$output" == *"--successor-assume-engaged"* ]] || false # recovery hint present
  ! [[ "$output" == *"dry run (self-close)"* ]]        # aborted BEFORE the plan → no close side of it
}

@test "gate: successor with a real assistant turn → engagement verified, gate passes" {
  printf '%s\n' \
    '{"type":"user","message":{"content":"go"}}' \
    '{"type":"assistant","message":{"content":"on it — starting the task"}}' > "$PROJDIR/$SUCC_SESS.jsonl"
  run bash "$HF" self-close --dry-run --session-id "$PRED" --successor "$SUCC"
  [ "$status" -eq 0 ]
  [[ "$output" == *"successor engagement verified"* ]] || false
  [[ "$output" == *"dry run (self-close)"* ]]          # reached the plan → gate passed
}

@test "gate: --successor-assume-engaged skips the engagement check when the transcript is unreadable" {
  # No transcript at all → engagement would fail, but the flag skips ONLY that half.
  run bash "$HF" self-close --dry-run --session-id "$PRED" --successor "$SUCC" --successor-assume-engaged
  [ "$status" -eq 0 ]
  [[ "$output" == *"engagement check SKIPPED"* ]] || false
  [[ "$output" == *"dry run (self-close)"* ]]
}

@test "gate: --successor-assume-engaged still ENFORCES liveness (dead successor → exit 3)" {
  : > "$PS_DEAD_DIR/TTY-$SUCC"                          # pane resolves but no claude on its tty
  run bash "$HF" self-close --dry-run --session-id "$PRED" --successor "$SUCC" --successor-assume-engaged
  [ "$status" -eq 3 ]
  [[ "$output" == *"no live claude on successor"* ]]   # liveness half is NOT skipped by the flag
}

# ── 2. CLOSE-INSTANT RE-VERIFY (the __selfclose watcher) ─────────────────────────────────────────

@test "watcher: successor DEAD at close-instant → no close, desk paged, predecessor left alive" {
  H="$BATS_TEST_TMPDIR/home-abort"; mk_home "$H"
  : > "$PS_DEAD_DIR/TTY-A"                              # predecessor already exited → skip wait loop
  : > "$PS_DEAD_DIR/TTY-B"                              # successor DIED before the close instant
  run env HOME="$H" bash "$HF" __selfclose PREDSID TTY-A SUCC-B TTY-B
  [ "$status" -ne 0 ]
  [[ "$output" == *"ABORTED at close-instant"* ]] || false
  [[ "$output" == *"NO LONGER ALIVE"* ]] || false
  [ ! -f "$H/it2-calls.log" ]                          # it2 close NEVER invoked → predecessor alive
  grep -q "HANDOFF-STRAND-RISK" "$H/ccnotify-calls.log"  # desk paged (best-effort)
}

@test "watcher: successor ALIVE at close-instant → closes predecessor + focuses successor, no page" {
  H="$BATS_TEST_TMPDIR/home-ok"; mk_home "$H"
  : > "$PS_DEAD_DIR/TTY-A"                              # predecessor exited → skip wait loop
  # (no dead-marker for TTY-B → successor alive at the close instant)
  run env HOME="$H" bash "$HF" __selfclose PREDSID TTY-A SUCC-B TTY-B
  [ "$status" -eq 0 ]
  grep -q "session close -f -s PREDSID" "$H/it2-calls.log"
  grep -q "session focus SUCC-B" "$H/it2-calls.log"
  [ ! -f "$H/ccnotify-calls.log" ]                     # happy path pages nobody
  [[ "$output" == *"focus handed to successor SUCC-B"* ]]
}

# ── 3. PRE-CLOSE INVENTORY (light, WARN-only) ────────────────────────────────────────────────────

@test "inventory: WARNs when this session has unread mail (a)" {
  eval "$(sed -n '/^selfclose_inventory_warn() {/,/^}/p' "$HF")"
  mailbox_pending_count() { echo 2; }                  # stub the shared cursor primitive
  FIRED_DIR=""                                         # skip (b)
  run selfclose_inventory_warn "MYSID" ""
  [ "$status" -eq 0 ]
  [[ "$output" == *"2 unread message(s)"* ]]
}

@test "inventory: WARNs on a peer this session fired that has no live session (b)" {
  eval "$(sed -n '/^selfclose_inventory_warn() {/,/^}/p' "$HF")"
  mailbox_pending_count() { echo 0; }                  # no unread → (a) silent
  as_tty() { echo ""; }                                # fired pane unresolvable → orphan
  FIRED_DIR="$BATS_TEST_TMPDIR/fired"; mkdir -p "$FIRED_DIR"
  printf '{"paneUUID":"DEADPEER","firedBy":"MYSID"}\n'   > "$FIRED_DIR/DEADPEER.json"
  printf '{"paneUUID":"OTHERPEER","firedBy":"SOMEONE"}\n' > "$FIRED_DIR/OTHERPEER.json"   # not ours
  run selfclose_inventory_warn "MYSID" ""
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 peer(s) fired by this session"* ]]
}

@test "inventory: silent when nothing is pending" {
  eval "$(sed -n '/^selfclose_inventory_warn() {/,/^}/p' "$HF")"
  mailbox_pending_count() { echo 0; }
  FIRED_DIR="$BATS_TEST_TMPDIR/fired-empty"; mkdir -p "$FIRED_DIR"
  run selfclose_inventory_warn "MYSID" ""
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ── ORIGIN GATE (operator invariant, 2026-07-26) ────────────────────────────────────────────────
# "A main session should and wouldn't self-close on itself, the same way a team LEAD never self
# closes itself while in progress or when its done." Self-close belongs ONLY to a session with an
# ORIGINATOR to hand back to. cc-classify:596 already refuses to REAP an unstamped (operator-launched)
# pane; until this gate, that same pane could still kill ITSELF via --terminal. Oracle = the
# fired-peer stamp handoff-fire writes at fire time (mark_fired_peer).

@test "origin gate: an UNSTAMPED (operator-launched) session is REFUSED --terminal" {
  export CC_FIRED_DIR="$BATS_TEST_TMPDIR/fired-none"; mkdir -p "$CC_FIRED_DIR"
  run bash "$HF" self-close --terminal --session-id "ORIGIN-1111" --dry-run
  [ "$status" -eq 2 ] || false
  echo "$output" | grep -qi "ORIGIN session" || false
  echo "$output" | grep -qi "no fired-peer stamp" || false
}

@test "origin gate: an unstamped session is refused --successor too (not just --terminal)" {
  export CC_FIRED_DIR="$BATS_TEST_TMPDIR/fired-none2"; mkdir -p "$CC_FIRED_DIR"
  run bash "$HF" self-close --successor "SOMEPANE-9999" --session-id "ORIGIN-2222" --dry-run
  [ "$status" -eq 2 ] || false
  echo "$output" | grep -qi "ORIGIN session" || false
}

@test "origin gate: a FIRED PEER (stamp present) passes the origin gate" {
  export CC_FIRED_DIR="$BATS_TEST_TMPDIR/fired-yes"; mkdir -p "$CC_FIRED_DIR"
  printf '{"paneUUID":"PEER-3333","cwd":"/tmp","firedBy":"ORIGIN-1111","firedAt":"2026-07-26T18:00:00Z","selfRetire":true}\n' \
    > "$CC_FIRED_DIR/PEER-3333.json"
  run bash "$HF" self-close --terminal --session-id "PEER-3333" --dry-run
  # It may still stop at a LATER gate (dirty tree, registry) — it must NOT stop at the origin gate.
  # `[ ]` form, not `&& false`: a non-final `A && B` is errexit-EXEMPT, so the original could never
  # fail. `[ ]` is live in ANY position, which is what the liveness ratchet is asking for.
  [ "$(echo "$output" | grep -ci "ORIGIN session")" -eq 0 ]
  [ "$status" -ne 2 ] || echo "$output" | grep -qvi "ORIGIN session" || false
}

@test "origin gate: an EMPTY stamp file is treated as absent (fail-safe, refuse)" {
  export CC_FIRED_DIR="$BATS_TEST_TMPDIR/fired-empty-stamp"; mkdir -p "$CC_FIRED_DIR"
  : > "$CC_FIRED_DIR/PEER-4444.json"          # zero-byte ⇒ unusable ⇒ must NOT authorise a close
  run bash "$HF" self-close --terminal --session-id "PEER-4444" --dry-run
  [ "$status" -eq 2 ] || false
  echo "$output" | grep -qi "ORIGIN session" || false
}

@test "origin gate: --allow-origin-close is the documented, loud override" {
  export CC_FIRED_DIR="$BATS_TEST_TMPDIR/fired-none3"; mkdir -p "$CC_FIRED_DIR"
  run bash "$HF" self-close --terminal --session-id "ORIGIN-5555" --allow-origin-close --dry-run
  # Was `&& false` followed by a bare `true` — dead twice over: errexit-exempt in non-final
  # position, and the trailing `true` reset the status even if it had not been.
  [ "$(echo "$output" | grep -ci "ORIGIN session")" -eq 0 ]
}
