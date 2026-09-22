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
  export CC_ADMIT_GATE=off              # hermeticity: the launcher path reaches capacity-admit.sh
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
recycle_self() { # the SELF form: --transplanted-source with NO --source-pane/--source-session.
  # This is the shape `cc-lr switch` fires (VOLUNTARY_ACCOUNT_SWITCH §5 DEC-2 — the subject IS the
  # actor), and it names its pane through $ITERM_SESSION_ID, never --session-id: resume mode refuses
  # --session-id outright. The sid the tombstone is keyed on arrives as $CLAUDE_CODE_SESSION_ID, and
  # $CLAUDE_CONFIG_DIR is the SOURCE account, because that is where its own tombstone sits.
  run env ITERM_SESSION_ID="w0t0p0:$SRC_PANE" CLAUDE_CODE_SESSION_ID="$SESS" CLAUDE_CONFIG_DIR="$SRC_CFG" \
      bash "$HF" --recycle --dry-run --transplanted-source \
      --resume-launcher "$LAUNCHER" --resume-cfg "$TARGET_CFG" "$@"
}

# EQUIVALENCE GUARDS, said plainly (2026-09-22, VOLUNTARY_ACCOUNT_SWITCH D1/D2). Every case in this
# file OUTSIDE the two blocks headed "D1 —" and "D2 —" passes against BOTH the pre-2026-09-22
# subject and the post-fix one. That is not a claim of coverage: a test green on subject and mutant
# alike proves nothing about the mutation — it only guards the admission, binding, pin and refusal
# behaviour AROUND the change against regression. The nine cases inside the blocks headed "D1 —",
# "D2 —" and "THE SELF FORM" are the evidence: every one of them FAILS against the unfixed subject
# (verified by reverting scripts/handoff-fire.sh to HEAD and re-running). Everything else is fence.

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

# ── D1 — THE CAUSE, NOT THE CLASS, DECIDES WHETHER LIVE SUBAGENTS MAY BE KILLED ──────────────────
#
# Until 2026-09-22 --transplanted-source forced ALLOW_LIVE_SA=1 unconditionally, and the first case
# below asserted that POSITIVELY — i.e. it pinned the defect. The justification ("a limit-blocked
# lead's subagents died with it") is true of a LIMIT and false of a VOLUNTARY move, whose source is
# healthy and whose subagents are genuinely running. The pin is un-pinned here deliberately: the
# limit path keeps its behaviour, now behind an explicit --transplant-cause limit, and the cases
# after it are the RED PROOF — against the unfixed subject, which forces on the CLASS, the
# voluntary and absent cases see the auto-allow line that must not be there.

@test "--transplant-cause limit implies --allow-live-subagents: a limit-blocked lead's dead subagents are the ingest's to re-audit" {
  mk_transplant; src_row
  recycle --transplant-cause limit
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"re-audited by the ingest, not protected here"* ]] || { echo "$output"; false; }
}

@test "RED PROOF (D1): --transplant-cause voluntary NEVER implies --allow-live-subagents — a healthy source's subagents are running" {
  mk_transplant; src_row
  recycle --transplant-cause voluntary
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" != *"re-audited by the ingest, not protected here"* ]] || {
    echo "the auto-allow fired for a VOLUNTARY move — live subagents would be SIGKILLed with no ingest to re-audit them:"; echo "$output"; false; }
}

@test "RED PROOF (D1): an ABSENT --transplant-cause takes the SAFE branch — fail-closed, never a silent kill" {
  mk_transplant; src_row
  recycle
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" != *"re-audited by the ingest, not protected here"* ]] || {
    echo "the class alone still forced the override; an ungated caller must meet the gate, not bypass it:"; echo "$output"; false; }
}

@test "--transplant-cause rejects an unknown cause with the usage rc (3), before any side effect" {
  mk_transplant; src_row
  recycle --transplant-cause maybe
  [ "$status" -eq 3 ] || { echo "status=$status"; echo "$output"; false; }
  [[ "$output" == *"unknown cause 'maybe'"* ]] || { echo "$output"; false; }
}

# ── D2 — THE PRE-/exit TRANSPLANT CONFIRM ────────────────────────────────────────────────────────
#
# The call site itself lives past `as_write "$SID" "/exit"`'s guard rails and is therefore
# unreachable under --dry-run (the DRY arm returns before recycle_fire). What IS assertable here is
# the readout contract: a dry run must not describe a different decision than the real run. These
# two cases pin that the confirm step is ANNOUNCED and that its kill switch is honoured; the
# behaviour of `--phase confirm` itself belongs to lr-transplant.sh's own suite, and the ABORT
# branches belong to an e2e that can reach recycle_fire.

@test "RED PROOF (D2): the dry run announces the pre-/exit transplant confirm as an ABORT point" {
  mk_transplant; src_row
  recycle --transplant-cause voluntary
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"--phase confirm runs immediately before /exit"* ]] || { echo "$output"; false; }
  [[ "$output" == *"rc != 0 ABORTS"* ]] || { echo "$output"; false; }
}

@test "kill switch: CC_TRANSPLANT_CONFIRM=off names the risk it restores instead of going quiet" {
  mk_transplant; src_row
  export CC_TRANSPLANT_CONFIRM=off      # exported, not a `VAR=x fn` prefix: the subject is the
                                        # `bash "$HF"` CHILD inside recycle(), not the function
  recycle --transplant-cause voluntary
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"confirm SKIPPED (CC_TRANSPLANT_CONFIRM=off)"* ]] || { echo "$output"; false; }
  [[ "$output" != *"--phase confirm runs immediately before /exit"* ]] || { echo "$output"; false; }
}

# ── THE SELF FORM — --transplanted-source WITHOUT --source-pane ──────────────────────────────────
#
# The primary path of the voluntary switch, and the one this file could not see until 2026-09-22:
# the remote pre-pass was hf_transplant_evidence's only caller, so the self arm resolved NO
# HF_TS_* operand and D2's confirm step would have aborted on every real `cc-lr switch`. These
# cases are the evidence that the self arm now reads its own tombstone. Both are RED PROOFS — the
# first sees `<unknown>` on the unfixed subject, the second is not refused by it at all.

@test "RED PROOF (self form): --transplanted-source with no --source-pane resolves its confirm operands from its OWN tombstone" {
  mk_transplant; src_row
  recycle_self --transplant-cause voluntary
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  # The class is admitted on evidence this arm read for itself …
  [[ "$output" == *"session ${SESS:0:8} is a transplanted source by its OWN tombstone"* ]] || { echo "$output"; false; }
  [[ "$output" == *"handed off to $TARGET_CFG"* ]] || { echo "$output"; false; }
  # … and the confirm step's OPERANDS are what the readout renders, so a resolved sid and a resolved
  # target here IS the proof they are non-empty at the call site. An unresolved run renders the
  # empty sid and the literal <unknown> basename instead of aborting invisibly in a dry run.
  [[ "$output" == *"re-copy + re-verify ${SESS:0:8} into $(basename "$TARGET_CFG")"* ]] || { echo "$output"; false; }
  [[ "$output" != *"re-verify  into"* ]] || { echo "the sid operand is EMPTY: $output"; false; }
  [[ "$output" != *"<unknown>"* ]] || { echo "the --to operand is EMPTY: $output"; false; }
}

@test "CONTROL (self form): no tombstone means this pane is an ORIGIN, not a husk — REFUSED before any side effect" {
  src_row                                    # deliberately NO mk_transplant
  recycle_self --transplant-cause voluntary
  [ "$status" -eq 2 ]
  [[ "$output" == *"has NO transplant tombstone"* ]] || { echo "$output"; false; }
  [[ "$output" != *"--phase confirm runs immediately before /exit"* ]] || { echo "it got as far as announcing the confirm: $output"; false; }
}

@test "CONTROL (self form): --resume-cfg that is not the tombstone's target is a second live copy — REFUSED" {
  mk_transplant; src_row
  other="$BATS_TEST_TMPDIR/cfg-somewhere-else"; mkdir -p "$other"
  run env ITERM_SESSION_ID="w0t0p0:$SRC_PANE" CLAUDE_CODE_SESSION_ID="$SESS" CLAUDE_CONFIG_DIR="$SRC_CFG" \
      bash "$HF" --recycle --dry-run --transplanted-source \
      --resume-launcher "$LAUNCHER" --resume-cfg "$other" --transplant-cause voluntary
  [ "$status" -eq 2 ]
  [[ "$output" == *"a relaunch anywhere but the transplant target is a second live copy"* ]] || { echo "$output"; false; }
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

# ── W1(b): THE ONE SILENT TERMINAL ARM ────────────────────────────────────────────────────────────
#
# `!! relaunch typed but no claude process appeared within 90s` is the watcher's LAST arm and, until
# W1, the only terminal arm of the four that wrote NOTHING — no ledger row, no alarm, no goal
# disposition (U04 §3, measured: 4 husks on 2026-09-19, `ls ~/.claude/handoff-alarms | grep 20260919`
# empty all day). It also said "90s" unconditionally, and typed its fallback through
# `it2 session run`, whose armed-pane branch writes a `.cmd` file instead of reaching the screen
# (`handoff-fire.sh:1419-1431`) — the write path that raced on the morning of the incident.
#
# WHAT IS DRIVEN. The detached `__recycle` watcher, directly, with a phase-aware `ps` shim modelled
# on tests/handoff-recycle-engagement.bats — except that the phase NEVER advances to `alive`, so the
# pane reaches a confirmed shell (the relaunch IS typed), and then no claude ever appears. That is
# exactly the 2026-09-19 shape: `lr-fire-resume` exits 9 at the capacity gate ~2 s after the launcher
# line is typed, and the watcher polls a corpse for 90 s. RCY_PROC_TICKS/RCY_PROC_IVL_S are the seams
# that make those two 45 s waits runnable in a test; they can only make the watcher give up SOONER.
#
# THE IDL JOIN. The cause of that exit-9 is on disk — `~/.claude/autonomy/idl.jsonl`,
# `caller:"lr-fire-resume"`, `term:"load"|"active"|…` — and nothing joined it, so every husk read as
# "no process appeared" with no why. The fixture below is the real row shape (capacity-admit.sh:418).
# TTY_PATH is a plain FILE here: pane_cc_state only ever takes its basename (`${ptty##*/}`), so the
# ps shim answers exactly as it would for a real pty, while the arm's `printf > "$TTY_PATH"` paint
# becomes assertable.

noproc_setup() { # → a watcher whose pane reaches a shell and never gets a claude back
  export CC_HANDOFF_ALARM_DIR="$HOME/.claude/handoff-alarms"
  export CC_NOTIFY_BIN="$HOME/.claude/bin/cc-notify"
  mkdir -p "$HOME/.claude/bin" "$HOME/.claude/logs" "$HOME/.claude/autonomy"
  cat > "$CC_NOTIFY_BIN" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$HOME/ccnotify-calls.log"
STUB
  chmod +x "$CC_NOTIFY_BIN"

  WSHIM="$BATS_TEST_TMPDIR/wshim"; mkdir -p "$WSHIM"
  # Phase-aware ps, pinned in the `shell` phase forever (PS_DEAD_CALLS is never reached).
  cat > "$WSHIM/ps" <<'SH'
#!/usr/bin/env bash
args="$*"
case "$args" in *pgid=*) printf '%s\n' "4242"; exit 0 ;; esac
case "$args" in
  *"-o pid= -t"*)    printf '100\n' ;;
  *"-o tpgid= -t"*)  printf '100\n' ;;
  *"-o comm= -t"*)   printf -- '-zsh\n' ;;
  *pid=,ppid=*)      printf '100 1\n' ;;
  *"pid=,comm= -g"*) printf '100 /bin/zsh\n' ;;
  *"-p 100"*)        printf '/bin/zsh\n' ;;
esac
exit 0
SH
  printf '#!/usr/bin/env bash\nexit 0\n' > "$WSHIM/osascript"
  chmod +x "$WSHIM/ps" "$WSHIM/osascript"

  WPANE="NOPROC-PANE"
  export STUB_PANE="$WPANE"
  cat > "$HOME/.claude/bin/it2" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$HOME/it2-calls.log"
case "$1 $2" in
  "session list")
    if [ "${3:-}" = --json ]; then printf '[{"id": "%s", "tty": "/dev/ttys999"}]\n' "${STUB_PANE:-NOPROC-PANE}"
    else printf '%s\n' "${STUB_PANE:-NOPROC-PANE}"; fi
    exit 0 ;;
  "session send") txt="${!#}"; [ "${#txt}" -gt 3 ] && printf '%s' "$txt" > "$HOME/it2-screen" ;;
  "session read") cat "$HOME/it2-screen" 2>/dev/null ;;
esac
exit 0
SH
  chmod +x "$HOME/.claude/bin/it2"
  WCMDF="$BATS_TEST_TMPDIR/relaunch.cmd"
  printf 'cd /tmp && nocorrect bash /tmp/lr-launch-abcd1234.sh\n' > "$WCMDF"
  WTTY="$BATS_TEST_TMPDIR/ttys999"; : > "$WTTY"
  export CC_ADMIT_IDL="$HOME/.claude/autonomy/idl.jsonl"
  : > "$CC_ADMIT_IDL"
}

idl_refusal() { # $1=sid $2=term $3=ts — one real-shaped lr-fire-resume refusal row
  printf '{"ts":"%s","hook":"capacity-admit","sid":"?","disposition":"refused","reason":"capacity","gate":"capacity-admit","verdict":"refuse","basis":"measured","caller":"lr-fire-resume","what":"resume %s on next2","detail":"load 2.57/core > 2.0 (refusal 2 of budget 3)","term":"%s","terms":"load,headroom,segments,active"}\n' \
    "$3" "$1" "$2" >> "$CC_ADMIT_IDL"
}

# THE BOOT SEAMS CHANGED SHAPE IN W2, AND THIS DRIVER IS UPDATED RATHER THAN PATCHED AROUND.
# W1 shrank two 45 s process waits with RCY_PROC_TICKS × RCY_PROC_IVL_S. W2 DELETES that loop —
# and the retype it existed to bracket — and replaces it with a date-bounded wait on positive
# discriminators (relaunch.rc · a fresh IDL refusal · claude on the pane), so the seams are now the
# two BOUNDS: RCY_BOOT_WAIT_S (INDETERMINATE) and RCY_BOOT_STALE_S (terminal). W1's two cases below
# are unchanged in what they assert; only the names of the knobs that make them run in seconds move.
drive_noproc() { # the watcher, resume-mode positional argv ($10 cfg $11 sid $12 T0 $13 srctx $14 run dir)
  run env HOME="$HOME" PATH="$WSHIM:$PATH" \
      RCY_BOOT_WAIT_S="${BOOT_WAIT:-1}" RCY_BOOT_STALE_S="${BOOT_STALE:-2}" \
      RCY_BOOT_IVL_S=0.2 RCY_BOOT_SLOW_IVL_S=1 RCY_BOOT_PANE_EVERY=2 \
      IT2_BIN="$HOME/.claude/bin/it2" \
      bash "$HF" __recycle "$WPANE" "$WTTY" "$WCMDF" /tmp "$SESS" "" "" "" \
                 "$TARGET_CFG" "$SESS" "2026-09-19T17:00:00" "" "${WRUN:-}"
}

@test "W1(b): the no-process arm writes a recycle-dead row whose detail carries the IDL term= for this sid" {
  noproc_setup
  idl_refusal "$SESS" load "2026-09-19T17:22:17Z"
  drive_noproc
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [ -f "$HOME/.claude/logs/handoffs.jsonl" ] || { echo "NO LEDGER ROW AT ALL:"; echo "$output"; false; }
  row="$(grep '"class":"recycle-dead"' "$HOME/.claude/logs/handoffs.jsonl" | tail -1)"
  [ -n "$row" ] || { cat "$HOME/.claude/logs/handoffs.jsonl"; echo "$output"; false; }
  printf '%s' "$row" | grep -q 'term=load' || { echo "$row"; echo "$output"; false; }
  # the REAL elapsed, never the literal 90 — the seam ran the two waits in ~2s
  ! printf '%s' "$row" | grep -q 'within 90s' || { echo "row still claims 90s: $row"; false; }
}

@test "W1(b): the no-process arm alarms and PAINTS the verdict to the tty — never it2 session run" {
  noproc_setup
  idl_refusal "$SESS" active "2026-09-19T17:22:17Z"
  drive_noproc
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  alarm="$(cat "$CC_HANDOFF_ALARM_DIR"/* 2>/dev/null || true)"
  printf '%s' "$alarm" | grep -q 'recycle-relaunch-refused' || { echo "NO ALARM: $alarm"; echo "$output"; false; }
  printf '%s' "$alarm" | grep -q 'term=active' || { echo "$alarm"; false; }
  # the pane is told, by a single printf to its own tty
  grep -q 'RECYCLE FAILED' "$WTTY" || { echo "TTY NOT PAINTED:"; cat "$WTTY"; echo "$output"; false; }
  grep -q 'lr-launch-abcd1234.sh' "$WTTY" || { cat "$WTTY"; false; }
  # and NOT through it2's launch verb, whose armed-pane branch writes a .cmd file instead
  ! grep -q 'session run' "$HOME/it2-calls.log" || { cat "$HOME/it2-calls.log"; false; }
}

# ══ W2 — THE BOOT WAIT: POSITIVE DISCRIMINATORS, NO RETYPE, AND A TIMEOUT THAT IS NOT A VERDICT ═══
# WHAT THIS REPLACES. The watcher typed the relaunch, waited 15 × 3 s for a claude, RETYPED the
# identical command, waited another 45 s, and called it "no process appeared within 90s". Measured
# 2026-09-19 (U02 §2d, U05 §3.4): the launcher had already exited ~2 s in, refused by its own
# capacity gate, so the 90 s was spent polling a corpse — and the retype re-ran the same command
# against a refusal counter that had advanced by exactly one, i.e. it could not possibly succeed.
#
# The new arm reads three POSITIVE facts: `relaunch.rc` newer than the type, an lr-fire-resume
# REFUSAL row newer than the type, and claude on the pane. A bound expiring is INDETERMINATE (a
# state and an alarm, then more reading), and only the outer bound is terminal — STALE:boot.
#
# The fixture writes relaunch.rc FROM THE it2 STUB, i.e. at the moment the relaunch is typed, which
# is the production shape: a stale rc must not be attributed to this attempt, and a rc written by
# the test body before the watcher starts is exactly that stale case (drive_w2_stale below).

w2_run_dir() { # → a run dir; RC_ON_TYPE=<n> makes the it2 stub write relaunch.rc when it types
  WRUN="$BATS_TEST_TMPDIR/bundle-w2"; mkdir -p "$WRUN"
  cat > "$HOME/.claude/bin/it2" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$HOME/it2-calls.log"
case "\$1 \$2" in
  "session list")
    if [ "\${3:-}" = --json ]; then printf '[{"id": "%s", "tty": "/dev/ttys999"}]\n' "\${STUB_PANE:-NOPROC-PANE}"
    else printf '%s\n' "\${STUB_PANE:-NOPROC-PANE}"; fi
    exit 0 ;;
  "session send")
    txt="\${!#}"; [ "\${#txt}" -gt 3 ] && printf '%s' "\$txt" > "$HOME/it2-screen"
    # the LAUNCHER's own fate, written where lr-fire-resume writes it, at the moment it is typed
    case "\$txt" in *lr-launch*) [ -n "\${RC_ON_TYPE:-}" ] && printf '%s\n' "\$RC_ON_TYPE" > "$WRUN/relaunch.rc" ;; esac
    ;;
  "session read") cat "$HOME/it2-screen" 2>/dev/null ;;
esac
exit 0
SH
  chmod +x "$HOME/.claude/bin/it2"
}

@test "W2: relaunch.rc=9 is a FAILED:relaunch verdict in ≤3s, with the IDL term in the alarm" {
  noproc_setup
  w2_run_dir
  idl_refusal "$SESS" load "2026-09-19T17:22:17Z"
  export RC_ON_TYPE=9
  # the DEFAULT bounds, deliberately: the 3 s property must not be an artifact of a tiny seam.
  BOOT_WAIT=60 BOOT_STALE=180
  t0=$(date +%s)
  drive_noproc
  t1=$(date +%s)
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  # THE WATCHER'S OWN CLOCK is the subject — its elapsed is measured from the moment it typed, so it
  # excludes this fixture's arming and pane-probe overhead, which is not what the 3 s claim is about.
  el="$(printf '%s\n' "$output" | sed -n 's/.*no claude process within \([0-9]*\)s.*/\1/p' | tail -1)"
  # SPLIT (bats-assert-liveness `and-absorbed`): "the watcher printed no elapsed at all" and
  # "it printed one and it was too big" are different failures — the first says the message
  # shape moved, the second says the watcher was slow.
  [ -n "$el" ] || { echo "the watcher printed no elapsed — its message shape moved: $output"; false; }
  # JUDGED ONLY ON A QUIET BOX. Both numbers below are WALL CLOCK, and a wall-clock verdict taken on
  # a saturated machine is a fact about the BOX. Measured 2026-09-20 by an adversarial pass: on the
  # UNMUTATED tree at 1-min load 62 this case failed twice consecutively, reading 5 s and 6 s
  # against the ≤3 s bound — the identical defect 1b2676f4c fixed in tests/cc-lr.bats one day
  # earlier, re-introduced here. Above the band the timings are PRINTED, never judged; the
  # load-INVARIANT half of the claim — that the verdict is FAILED:relaunch:rc=9, that the ledger row
  # and the alarm carry the refusing term, and that the run's own state log records it — is asserted
  # unconditionally below and is what this case actually exists to pin. The band is 1.0/core, not
  # 2.0: 2.0 is the capacity gate's REFUSAL line for net-new work, not a quiet-box line.
  lpc="$(python3 -c 'import os;print("%.2f" % (os.getloadavg()[0]/(os.cpu_count() or 1)))')"
  quiet="$(python3 -c "import sys;print(1 if float(sys.argv[1]) < float('${RCY_JUDGE_MAX_LPC:-1.0}') else 0)" "$lpc")"
  echo "# watcher elapsed ${el}s, whole run $((t1 - t0))s, at load/core $lpc (judged: $quiet)" >&3
  if [ "$quiet" = 1 ]; then
    [ "$el" -le 3 ] || { echo "the watcher took ${el}s to read an rc that was on disk before it looked: $output"; false; }
    [ $((t1 - t0)) -le 15 ] || { echo "the whole run took $((t1 - t0))s: $output"; false; }
  fi
  [[ "$output" == *"FAILED:relaunch:rc=9"* ]] || { echo "$output"; false; }
  row="$(grep '"class":"recycle-dead"' "$HOME/.claude/logs/handoffs.jsonl" | tail -1)"
  printf '%s' "$row" | grep -q 'FAILED:relaunch:rc=9' || { echo "$row"; false; }
  alarm="$(cat "$CC_HANDOFF_ALARM_DIR"/* 2>/dev/null || true)"
  printf '%s' "$alarm" | grep -q 'term=load' || { echo "NO TERM IN THE ALARM: $alarm"; false; }
  # the run's own state log carries it too — the store a reader consults without the ledger
  grep -q 'FAILED' "$WRUN/events.jsonl" || { cat "$WRUN/events.jsonl" 2>/dev/null; false; }
}

@test "W2: a relaunch.rc OLDER than the type is IGNORED — a previous attempt is not this evidence" {
  # D1-safety R5. The watcher removes the file before typing AND compares mtime to typed_at; the
  # unlink alone loses to a writer that recreated it in between, and the timestamp alone loses to a
  # file nobody cleared. This drives the second half: the rc is pre-seeded, and back-dated.
  noproc_setup
  w2_run_dir
  printf '9\n' > "$WRUN/relaunch.rc"
  touch -t 202601010000 "$WRUN/relaunch.rc"
  drive_noproc
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" != *"FAILED:relaunch:rc=9"* ]] \
    || { echo "a STALE rc was attributed to this attempt: $output"; false; }
  [[ "$output" == *"STALE:boot"* ]] || { echo "$output"; false; }
}

@test "W2: 60s with no evidence is INDETERMINATE:boot — an alarm and MORE reading, not a verdict" {
  noproc_setup
  w2_run_dir
  drive_noproc
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"INDETERMINATE:boot"* ]] || { echo "$output"; false; }
  alarm="$(cat "$CC_HANDOFF_ALARM_DIR"/* 2>/dev/null || true)"
  printf '%s' "$alarm" | grep -q 'recycle-boot-indeterminate' || { echo "NO INDETERMINATE ALARM: $alarm"; false; }
  printf '%s' "$alarm" | grep -q 'ABSTENTION, not a failure' || { echo "$alarm"; false; }
  # …and the terminal state past the OUTER bound is STALE, which is a different word from FAILED
  [[ "$output" == *"STALE:boot"* ]] || { echo "$output"; false; }
  [[ "$output" != *"FAILED:relaunch"* ]] || { echo "$output"; false; }
}

@test "W2: the relaunch is typed ONCE — the retype arm is gone, in the source and in the run" {
  # THE SOURCE HALF, bounded by two anchors that must BOTH match (a stale range endpoint selects
  # everything, docs/lessons/absent-range-endpoint-selects-everything).
  start="$(grep -n 'shell-prompt settle after claude exits' "$HF" | head -1 | cut -d: -f1)"
  end="$(grep -n 'THE ONE SILENT TERMINAL ARM' "$HF" | head -1 | cut -d: -f1)"
  # SPLIT (bats-assert-liveness `and-absorbed`): each anchor names itself, so a re-pin knows
  # WHICH end moved. An absent endpoint does not fail a range selection, it INVERTS it
  # (docs/lessons/absent-range-endpoint-selects-everything), so both must be asserted.
  [ -n "$start" ] || { echo "the boot region's START anchor moved — re-pin this case"; false; }
  [ -n "$end" ] || { echo "the boot region's END anchor moved — re-pin this case"; false; }
  [ "$end" -gt "$start" ] || { echo "the boot region's anchors crossed (start=$start end=$end) — re-pin this case"; false; }
  n="$(awk -v a="$start" -v b="$end" 'NR>a && NR<b' "$HF" | grep -c 'it2_type_verified' || true)"
  [ "$n" = 1 ] || { echo "the resume-mode boot region types $n times, not 1 — the retype is back"; false; }
  ! awk -v a="$start" -v b="$end" 'NR>a && NR<b' "$HF" | grep -q 'retyping once' \
    || { echo "the retype message survives in the boot region"; false; }
  # THE BEHAVIOURAL HALF: one type, and no retype line, in a run that never gets a claude back.
  noproc_setup
  w2_run_dir
  drive_noproc
  # the TYPE line, not any line MENTIONING it: the terminal verdict quotes the same phrase.
  [ "$(printf '%s\n' "$output" | grep -c '→ relaunch typed into')" = 1 ] || { echo "$output"; false; }
  [[ "$output" != *"retyping once"* ]] || { echo "$output"; false; }
}
