#!/usr/bin/env bats
# handoff-fire.sh --recycle — the REMOTE IN-PLACE RESUME form (LIMIT_RECOVER_100P, 2026-09-09).
#
# THE DEFECT. A limit-blocked session cannot drive its own recovery (it cannot take a turn), so a
# THIRD session — or the launchd reset poller — drives it. `--recycle --session-id P` from that
# driver was refused by the self-identity gate ("no ancestor of this process owns that pane's
# tty"), correctly for a LIVE session (the 2026-07-30 c5f80b8b incident), and the only remaining
# path was to fire a NEW pane and leave the source as a husk — three of them on 2026-09-08.
#
# THE CARVE-OUT, and why it is not a bypass. The gate is REPLACED by evidence, exactly the way
# self-close's remote form already does it: the registry row for P must name S; S must carry the
# transplant tombstone (handed_off_to ≠ P's config dir) with its split-brain lock still held. A
# recycle TYPES into the pane, so it needs one more fact a close never did: the row's process must
# be alive with P's tty in its ancestry (kitty reuses window ids across restarts, so a stale row can
# name a window that now belongs to a stranger). Every precondition has a refusal below, because a
# precondition nothing can fail is not a precondition.
#
# RESUME MODE. The relaunch is `bash <launcher>` (the lr-launch-*.sh lr-handoff minted: lr-fire-resume
# of the SAME uuid on the TARGET account) — NOT exec'd, so the pane's shell outlives the session and
# the pane is recyclable next time. Engagement is a fresh non-error assistant turn in the TARGET's
# copy of the transcript, never the marker/sid-change signals a brief-carrying recycle uses.
#
# Technique mirrors tests/handoff-selfclose-transplanted-source.bats: PATH shims, --dry-run so every
# gate runs but nothing is typed, and the whole script invoked (never a sed-extracted unit) because
# the subject IS the gate's control flow. Only resume_engaged is extracted, as the pure oracle it is.

setup() {
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  unset KITTY_WINDOW_ID
  export IT2_WRAPPER_NO_KITTY=1
  export CC_TERM=iterm2
  unset ITERM_SESSION_ID CLAUDE_CODE_SESSION_ID

  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"

  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude"
  export CC_FIRED_DIR="$BATS_TEST_TMPDIR/cc-fired"; mkdir -p "$CC_FIRED_DIR"
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg"; mkdir -p "$CC_REGISTRY_DIR"
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/sweep-stamp.json"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-lock-"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/absent-claude-accounts"

  SHIM="$BATS_TEST_TMPDIR/shim"; mkdir -p "$SHIM"
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
  cat > "$SHIM/git" <<'SH'
#!/usr/bin/env bash
exit 0
SH
  # ps: `-o tty= -p <pid>` answers PS_TTY_OUT (the row pid's tty); `-o ppid=` answers nothing, so the
  # ancestry walk in hf_remote_source_pin stops after one hop; everything else answers nothing.
  cat > "$SHIM/ps" <<'SH'
#!/usr/bin/env bash
want=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) case "${2:-}" in tty=) want=tty ;; comm=) want=comm ;; esac; shift 2 ;;
    *) shift ;;
  esac
done
[ "$want" = tty ] && [ -n "${PS_TTY_OUT:-}" ] && printf '%s\n' "$PS_TTY_OUT"
exit 0
SH
  chmod +x "$SHIM/osascript" "$SHIM/git" "$SHIM/ps"
  export PATH="$SHIM:$PATH"

  SRC_PANE="11110000-2222-3333-4444-555566667777"
  SESS="7b3f9c10-0000-4000-8000-abcdefabcdef"
  SRC_CFG="$BATS_TEST_TMPDIR/cfg-source"
  TARGET_CFG="$BATS_TEST_TMPDIR/cfg-target"
  SLUG="-Users-x-Development-thing"
  mkdir -p "$SRC_CFG/projects/$SLUG" "$TARGET_CFG/projects/$SLUG"
  export CC_PROJECTS_DIRS="$SRC_CFG/projects $TARGET_CFG/projects"
  TOMB="$SRC_CFG/projects/$SLUG/$SESS.HANDOFF.json"
  LOCKDIR="$HOME/.reso/limit-recover/locks"; mkdir -p "$LOCKDIR"
  LOCK="$LOCKDIR/$SESS.lock"
  LAUNCHER="$BATS_TEST_TMPDIR/lr-launch-abcd1234-XXXXXX.sh"
  printf '#!/bin/bash\nexec /bin/echo resume\n' > "$LAUNCHER"; chmod +x "$LAUNCHER"
  CWD_DIR="$BATS_TEST_TMPDIR/wt"; mkdir -p "$CWD_DIR"
  export PS_TTY_OUT="TTY-$SRC_PANE"          # the row's process sits on the pane's own tty
}

mk_transplant() { # $1 (optional) = override for .handed_off_to
  printf '{"handed_off_to":"%s","target_transcript":"%s","ts":"2026-09-09T00:00:00Z","lock":"%s"}\n' \
    "${1:-$TARGET_CFG}" "$TARGET_CFG/projects/$SLUG/$SESS.jsonl" "$LOCK" > "$TOMB"
  printf '{"sid":"%s","from":"%s","to":"%s","pid":1}\n' "$SESS" "$SRC_CFG" "$TARGET_CFG" > "$LOCK"
}
src_row() { # $1 = session id the row names (default: the transplanted one)  $2 = pid (default: this live process)
  printf '{"paneUUID":"%s","name":"x-%s","cwd":"%s","account":"cfg-source","pid":%d,"session_id":"%s","surface":"pane"}\n' \
    "$SRC_PANE" "$SRC_PANE" "$CWD_DIR" "${2:-$$}" "${1:-$SESS}" > "$CC_REGISTRY_DIR/$SRC_PANE.json"
}
recycle() { # the remote resume form under test, with whatever extra args a case needs
  run bash "$HF" --recycle --dry-run --transplanted-source --source-pane "$SRC_PANE" --source-session "$SESS" \
      --resume-launcher "$LAUNCHER" --resume-cfg "$TARGET_CFG" "$@"
}

# ── ADMISSION ─────────────────────────────────────────────────────────────────────────────────────

@test "all preconditions satisfied: the remote in-place resume is ADMITTED, the gate REPLACED by the binding" {
  mk_transplant; src_row
  recycle
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"remote in-place resume: pane $SRC_PANE is PROVEN to hold session ${SESS:0:8}"* ]] || { echo "$output"; false; }
  [[ "$output" == *"self-identity gate is REPLACED by that binding"* ]] || { echo "$output"; false; }
  [[ "$output" != *"is NOT this session's pane"* ]] || { echo "the ownership gate still fired: $output"; false; }
}

@test "the relaunch is the launcher, NOT exec'd, under nocorrect, in the row's cwd" {
  mk_transplant; src_row
  recycle
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -qF "command:  cd $CWD_DIR && nocorrect bash $LAUNCHER" || { echo "$output"; false; }
  [[ "$output" != *"exec bash"* ]] || { echo "an exec'd launcher makes the pane launcher-rooted and un-recyclable: $output"; false; }
}

@test "--resume-cwd overrides the row's cwd" {
  mk_transplant; src_row
  other="$BATS_TEST_TMPDIR/elsewhere"; mkdir -p "$other"
  recycle --resume-cwd "$other"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -qF "command:  cd $other && nocorrect bash $LAUNCHER" || { echo "$output"; false; }
}

@test "the dry run names the mode: same uuid on the target, transcript-verified engagement, no goal inheritance" {
  mk_transplant; src_row
  recycle
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"resume:   IN-PLACE RESUME of session $SESS on $(basename "$TARGET_CFG")"* ]] || { echo "$output"; false; }
  [[ "$output" == *"no goal inheritance"* ]] || { echo "$output"; false; }
  [[ "$output" == *"remote:   pane $SRC_PANE bound to ${SESS:0:8}"* ]] || { echo "$output"; false; }
}

@test "the class implies --allow-live-subagents: a limit-blocked lead's dead subagents are the ingest's to re-audit" {
  mk_transplant; src_row
  recycle
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"re-audited by the ingest, not protected here"* ]] || { echo "$output"; false; }
}

# ── THE PANE↔SESSION BINDING (the registry row) ───────────────────────────────────────────────────

@test "CONTROL: without --transplanted-source the remote pane is REFUSED — the class must be named" {
  mk_transplant; src_row
  run bash "$HF" --recycle --dry-run --source-pane "$SRC_PANE" --source-session "$SESS" \
      --resume-launcher "$LAUNCHER" --resume-cfg "$TARGET_CFG"
  [ "$status" -eq 2 ]
  [[ "$output" == *"admissible ONLY with --transplanted-source"* ]] || { echo "$output"; false; }
}

@test "the remote form needs --resume-launcher: a transplanted source may only be relaunched INTO its own uuid" {
  mk_transplant; src_row
  run bash "$HF" --recycle --dry-run --transplanted-source --source-pane "$SRC_PANE" --source-session "$SESS"
  [ "$status" -eq 2 ]
  [[ "$output" == *"needs --resume-launcher"* ]] || { echo "$output"; false; }
}

@test "no registry row for the pane — REFUSED, nothing typed" {
  mk_transplant
  recycle
  [ "$status" -eq 2 ]
  [[ "$output" == *"no session-registry row for pane $SRC_PANE"* ]] || { echo "$output"; false; }
}

@test "the row names a DIFFERENT session — REFUSED" {
  mk_transplant; src_row "9999ffff-0000-4000-8000-000000000000"
  recycle
  [ "$status" -eq 2 ]
  [[ "$output" == *"does NOT hold session ${SESS:0:8}"* ]] || { echo "$output"; false; }
  [[ "$output" == *"the registry says that pane holds 9999ffff"* ]] || { echo "$output"; false; }
}

@test "the row carries no .session_id — REFUSED, never guessed at" {
  mk_transplant
  printf '{"paneUUID":"%s","pid":%d}\n' "$SRC_PANE" "$$" > "$CC_REGISTRY_DIR/$SRC_PANE.json"
  recycle
  [ "$status" -eq 2 ]
  [[ "$output" == *"names no .session_id"* ]] || { echo "$output"; false; }
}

# ── THE PIN (a recycle TYPES, so the row must name a process that is THERE) ───────────────────────

@test "the row's pid is DEAD — REFUSED: a stale row after a kitty id reuse names a stranger's window" {
  mk_transplant; src_row "$SESS" 4194000
  recycle
  [ "$status" -eq 2 ]
  [[ "$output" == *"which is DEAD"* ]] || { echo "$output"; false; }
}

@test "the row's pid is alive but on ANOTHER tty — REFUSED: the row is STALE" {
  mk_transplant; src_row
  export PS_TTY_OUT="TTY-somebody-else"
  recycle
  [ "$status" -eq 2 ]
  [[ "$output" == *"has no ancestor on tty"* ]] || { echo "$output"; false; }
  [[ "$output" == *"kitty reuses window ids"* ]] || { echo "$output"; false; }
}

@test "the row carries no usable pid — REFUSED" {
  mk_transplant
  printf '{"paneUUID":"%s","session_id":"%s","cwd":"%s"}\n' "$SRC_PANE" "$SESS" "$CWD_DIR" > "$CC_REGISTRY_DIR/$SRC_PANE.json"
  recycle
  [ "$status" -eq 2 ]
  [[ "$output" == *"carries no usable pid"* ]] || { echo "$output"; false; }
}

# ── THE TRANSPLANT EVIDENCE (the session must be PROVABLY retired at this pane) ───────────────────

@test "no tombstone: the session never moved, so this pane is an ORIGIN — REFUSED" {
  src_row
  recycle
  [ "$status" -eq 2 ]
  [[ "$output" == *"has NO transplant tombstone"* ]] || { echo "$output"; false; }
  [[ "$output" == *"looked for: $SRC_CFG/projects/*/$SESS.HANDOFF.json"* ]] || { echo "$output"; false; }
}

@test "tombstone hands the session to the SAME config dir: not a transplant — REFUSED" {
  mk_transplant "$SRC_CFG"; src_row
  run bash "$HF" --recycle --dry-run --transplanted-source --source-pane "$SRC_PANE" --source-session "$SESS" \
      --resume-launcher "$LAUNCHER" --resume-cfg "$SRC_CFG"
  [ "$status" -eq 2 ]
  [[ "$output" == *"THIS SAME config dir"* ]] || { echo "$output"; false; }
}

@test "the split-brain lock is gone: the move was released — REFUSED" {
  mk_transplant; src_row; rm -f "$LOCK"
  recycle
  [ "$status" -eq 2 ]
  [[ "$output" == *"split-brain lock is gone"* ]] || { echo "$output"; false; }
}

@test "--resume-cfg must be the tombstone's target: anywhere else is a second live copy — REFUSED" {
  mk_transplant; src_row
  third="$BATS_TEST_TMPDIR/cfg-third"; mkdir -p "$third/projects/$SLUG"
  run bash "$HF" --recycle --dry-run --transplanted-source --source-pane "$SRC_PANE" --source-session "$SESS" \
      --resume-launcher "$LAUNCHER" --resume-cfg "$third"
  [ "$status" -eq 2 ]
  [[ "$output" == *"a relaunch anywhere but the transplant target is a second live copy"* ]] || { echo "$output"; false; }
}

# ── FLAG SHAPE ────────────────────────────────────────────────────────────────────────────────────

@test "--resume-launcher and --resume-cfg are a PAIR" {
  mk_transplant; src_row
  run bash "$HF" --recycle --dry-run --transplanted-source --source-pane "$SRC_PANE" --source-session "$SESS" \
      --resume-launcher "$LAUNCHER"
  [ "$status" -eq 2 ]
  [[ "$output" == *"are a PAIR"* ]] || { echo "$output"; false; }
}

@test "the resume flags are --recycle flags: on a fire they are refused before any side effect" {
  pf="$BATS_TEST_TMPDIR/brief.md"; printf 'hello\n' > "$pf"
  run bash "$HF" --dry-run --prompt-file "$pf" --resume-launcher "$LAUNCHER" --resume-cfg "$TARGET_CFG"
  [ "$status" -eq 2 ]
  [[ "$output" == *"are --recycle flags"* ]] || { echo "$output"; false; }
}

@test "--session-id and the remote form both name the pane — refused, not merged" {
  mk_transplant; src_row
  recycle --session-id "$SRC_PANE"
  [ "$status" -eq 2 ]
  [[ "$output" == *"pass --source-pane only"* ]] || { echo "$output"; false; }
}

@test "--prompt-file is not a resume-mode input: the launcher carries the ingest prompt" {
  mk_transplant; src_row
  pf="$BATS_TEST_TMPDIR/brief.md"; printf 'hello\n' > "$pf"
  recycle --prompt-file "$pf"
  [ "$status" -eq 2 ]
  [[ "$output" == *"not used in resume mode"* ]] || { echo "$output"; false; }
}

@test "a missing launcher file is refused before anything else runs" {
  mk_transplant; src_row
  run bash "$HF" --recycle --dry-run --transplanted-source --source-pane "$SRC_PANE" --source-session "$SESS" \
      --resume-launcher "$BATS_TEST_TMPDIR/does-not-exist.sh" --resume-cfg "$TARGET_CFG"
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing or empty"* ]] || { echo "$output"; false; }
}

# ── THE GATE STILL BINDS WHERE IT SHOULD ─────────────────────────────────────────────────────────

@test "CONTROL: the LOCAL recycle form still runs the self-identity gate on a pane that is not ours" {
  # No remote flags: an explicit --session-id that no ancestor owns is exactly what c5f80b8b was.
  pf="$BATS_TEST_TMPDIR/brief.md"; printf 'hello\n' > "$pf"
  export PS_TTY_OUT="TTY-the-driver"          # our own ancestry sits elsewhere
  run bash "$HF" --recycle --dry-run --session-id "$SRC_PANE" --prompt-file "$pf"
  [ "$status" -eq 2 ]
  [[ "$output" == *"is NOT this session's pane"* ]] || { echo "$output"; false; }
}

@test "self-close reads the SAME predicates: one copy of the binding and of the transplant evidence" {
  run sed -n '/^if \[ "${1:-}" = "self-close" \]; then/,/^fi$/p' "$HF"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF 'hf_remote_source_bind "$SC_SOURCE_PANE" "$SC_SOURCE_SESSION" self-close' \
    || { echo "self-close no longer calls hf_remote_source_bind"; false; }
  printf '%s\n' "$output" | grep -qF 'hf_transplant_evidence "$SC_TS_SID" "$SC_TS_ROOTS" self-close' \
    || { echo "self-close no longer calls hf_transplant_evidence"; false; }
  # and the recycle pre-pass calls the same three
  run sed -n '/^if \[ "\$RECYCLE" = 1 \]; then/,/^fi$/p' "$HF"
  printf '%s\n' "$output" | grep -qF 'hf_remote_source_bind "$RCY_SOURCE_PANE" "$RCY_SOURCE_SESSION" --recycle' || { echo "recycle pre-pass lacks the bind"; false; }
  printf '%s\n' "$output" | grep -qF 'hf_remote_source_pin  "$RCY_SOURCE_PANE" "$HF_REMOTE_ROW_PID" --recycle' || { echo "recycle pre-pass lacks the pin"; false; }
  printf '%s\n' "$output" | grep -qF 'hf_transplant_evidence "$RCY_SOURCE_SESSION" "$CC_PROJECTS_DIRS" --recycle' || { echo "recycle pre-pass lacks the evidence"; false; }
}

@test "the watcher is handed the resume oracle's inputs and the source transcript to fold" {
  run grep -c '__recycle "\$SID" "\$tty" "\$cmdfile" "\$LAUNCH_DIR" "\$rcy_old_sid" "\$RECYCLE_MARKER" "\$FIRE_GOAL" "\${PROMPT_FILE_ORIG:-\$PROMPT_FILE}" "\$RESUME_CFG" "\${RESUME_LAUNCHER:+\${RCY_SOURCE_SESSION:-\$rcy_old_sid}}" "\$RCY_T0" "\$RCY_SRC_TX"' "$HF"
  [ "$output" = 1 ] || { echo "detach line does not carry \$10-\$13: $output"; false; }
  run grep -c 'RCY_RESUME_CFG="\${10:-}"; RCY_RESUME_SID="\${11:-}"; RCY_T0="\${12:-}"' "$HF"
  [ "$output" = 1 ]
  run grep -c 'RCY_SRC_TX="\${13:-}"' "$HF"
  [ "$output" = 1 ]
}

# ── resume_engaged — the resume-mode oracle, extracted as the pure function it is ─────────────────

oracle() { eval "$(sed -n '/^resume_engaged() {/,/^}/p' "$HF")"; command -v resume_engaged >/dev/null; }
tx() { # $1 = ISO ts  $2 = json fields after "type"
  printf '{"type":"assistant","timestamp":"%s",%s}\n' "$1" "$2" >> "$TARGET_CFG/projects/$SLUG/$SESS.jsonl"
}

@test "oracle: a content-bearing assistant turn NEWER than the baseline in the TARGET's copy = engaged" {
  oracle
  tx "2026-09-09T01:00:00.000Z" '"message":{"role":"assistant","content":[{"type":"text","text":"old"}]}'
  tx "2026-09-09T01:05:00.000Z" '"message":{"role":"assistant","content":[{"type":"text","text":"Running the audit"}]}'
  run resume_engaged "$TARGET_CFG" "$SESS" "2026-09-09T01:04:00"
  [ "$status" -eq 0 ]
}

@test "oracle CONTROL: only turns OLDER than the baseline = not engaged (a husk's history is not a turn)" {
  oracle
  tx "2026-09-09T01:00:00.000Z" '"message":{"role":"assistant","content":[{"type":"text","text":"old"}]}'
  run resume_engaged "$TARGET_CFG" "$SESS" "2026-09-09T01:04:00"
  [ "$status" -eq 1 ]
}

@test "oracle: the limit hitting AGAIN on the target (isApiErrorMessage) is NOT engagement" {
  oracle
  tx "2026-09-09T01:05:00.000Z" '"isApiErrorMessage":true,"message":{"role":"assistant","content":[{"type":"text","text":"You'"'"'ve hit your session limit"}]}'
  run resume_engaged "$TARGET_CFG" "$SESS" "2026-09-09T01:04:00"
  [ "$status" -eq 1 ]
}

@test "oracle: the synthetic 'No response requested.' a resume inserts is NOT engagement" {
  oracle
  tx "2026-09-09T01:05:00.000Z" '"message":{"role":"assistant","content":"No response requested."}'
  run resume_engaged "$TARGET_CFG" "$SESS" "2026-09-09T01:04:00"
  [ "$status" -eq 1 ]
}

@test "oracle: a turn in the SOURCE's copy does not count — the target is what must move" {
  oracle
  printf '{"type":"assistant","timestamp":"2026-09-09T01:05:00.000Z","message":{"role":"assistant","content":[{"type":"text","text":"husk wrote this"}]}}\n' \
    > "$SRC_CFG/projects/$SLUG/$SESS.jsonl"
  run resume_engaged "$TARGET_CFG" "$SESS" "2026-09-09T01:04:00"
  [ "$status" -eq 1 ]
}
