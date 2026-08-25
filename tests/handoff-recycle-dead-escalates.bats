#!/usr/bin/env bats
# handoff-fire.sh __recycle — recycle-dead ESCALATES (RECYCLE_SIGTERM_INCIDENT_2026-08-25, D3).
#
# THE DEFECT. `recycle-dead` is the TERMINAL failure of a recycle: the /exit already landed, so the
# predecessor is gone, and the relaunch was never typed — the pane holds no claude at all. It wrote
# a ledger row and nothing else. Its SIBLING terminal failure on the same path,
# `recycle-relaunch-failed`, has called hf_alarm since it was written, so the WORSE outcome was the
# quieter one. Measured: pane 30 on 2026-08-25 burned 600 s (21:36:05Z → 21:46:16Z) across three
# `decision=unknown` holds and nothing told anyone.
#
# THE SECOND HALF, which is a claim about EVIDENCE rather than about noise. The recorded verdict was
# `unknown`, and `unknown` is returned from seven branches of pane_cc_state (:2863, 2874, 2884,
# 2890, 2892, 2898, 2903) — every one meaning "this pane could not be READ", none meaning "there is
# no shell here". So the ledger row cannot answer the question the incident asked (did pane 30's
# shell never appear, or did the detector fail to see one that did?), and the escalation must not
# pretend otherwise. The alarm therefore has to say ABSTENTION, not absence.
#
# WHAT THIS SUITE DRIVES, and why it is safe. The detached `__recycle` watcher is invoked directly,
# against a fabricated pane id and a tty path that does not exist. pane_cc_state reads that tty,
# finds no processes, and returns `unknown` (:2874) — the exact state pane 30 sat in — so at_shell
# is never satisfied and the watcher walks to its terminal arm. Nothing is typed: the terminal arm
# is upstream of every keystroke, and it is reached precisely BECAUSE the pane was never confirmed.
# HF_RECYCLE_SHELL_WAIT_S bounds the wait; the seam defaults to 600 and can only make the watcher
# give up sooner, never make it type onto a pane it has not confirmed.

setup() {
  REPO_SRC="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO_SRC/scripts/handoff-fire.sh"
  [ -f "$HF" ] || { echo "subject missing: $HF" >&2; return 1; }

  # M11: pin the machine-state gates — an unpinned suite reads the box's live loadavg and memory and
  # decides a verdict on how busy the machine is rather than on the tree.
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  export HANDOFF_ACCOUNT_SWEEP=off
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/no-such-sweep-stamp.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/no-such-claude-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/no-such-heal-lock-"

  export H="$BATS_TEST_TMPDIR/home"; mkdir -p "$H/.claude/bin"
  export HOME="$H"
  export CC_HANDOFF_ALARM_DIR="$H/.claude/handoff-alarms"

  SHIM="$BATS_TEST_TMPDIR/shim"; mkdir -p "$SHIM"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$SHIM/osascript"; chmod +x "$SHIM/osascript"
  export PATH="$SHIM:$PATH"

  # The pager is a stub: this suite must never page a live session.
  export CC_NOTIFY_BIN="$H/.claude/bin/cc-notify"
  cat > "$CC_NOTIFY_BIN" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$H/paged.txt"
STUB
  chmod +x "$CC_NOTIFY_BIN"

  # it2 reports the pane as REACHABLE (so pane_proof passes) but the tty it names does not exist,
  # which is what makes pane_cc_state abstain.
  export STUB_PANE="RECY-DEAD-PANE"
  cat > "$H/.claude/bin/it2" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$HOME/it2-calls.log"
case "$1 $2" in
  "session list")
    if [ "${3:-}" = --json ]; then printf '[{"id": "%s", "tty": "/dev/ttys999"}]\n' "${STUB_PANE:-RECY-DEAD-PANE}"
    else printf '%s\n' "${STUB_PANE:-RECY-DEAD-PANE}"; fi
    exit 0 ;;
esac
exit 0
SH
  chmod +x "$H/.claude/bin/it2"
  export IT2_BIN="$H/.claude/bin/it2"

  CMDFILE="$BATS_TEST_TMPDIR/relaunch.cmd"
  printf 'claude --permission-mode auto\n' > "$CMDFILE"
  export CMDFILE
  export HF_RECYCLE_SHELL_WAIT_S=3
}

drive_dead() { HF_RECYCLE_SHELL_WAIT_S=3 bash "$HF" __recycle "$STUB_PANE" "$BATS_TEST_TMPDIR/no-such-tty" "$CMDFILE" "$BATS_TEST_TMPDIR"; }

alarms() { cat "$CC_HANDOFF_ALARM_DIR"/* 2>/dev/null; }

@test "recycle-dead now ESCALATES — an alarm record exists, not just a ledger row" {
  run drive_dead
  [ "$status" -ne 0 ]                                   # the terminal arm still refuses, as designed
  run alarms
  echo "$output" | grep -q 'recycle-dead'
  echo "$output" | grep -q 'HANDOFF-RECYCLE-DEAD'
}

@test "the alarm states the CONSEQUENCE: the pane now holds no claude and work is stranded" {
  drive_dead || true
  run alarms
  echo "$output" | grep -qi 'holds NO claude'
  echo "$output" | grep -qi 'stranded'
}

@test "an 'unknown' verdict is reported as an ABSTENTION, never as 'no shell appeared'" {
  drive_dead || true
  run alarms
  # This is the whole evidentiary point of D3: the probe could not READ the pane, which does not
  # establish that no shell was there. The alarm must not upgrade a miss into an absence.
  echo "$output" | grep -q 'ABSTENTION'
  echo "$output" | grep -q 'does NOT establish that no shell appeared'
}

@test "the alarm carries the ONE recovery action — the manual relaunch command" {
  drive_dead || true
  run alarms
  echo "$output" | grep -q 'Relaunch manually'
  echo "$output" | grep -q 'claude --permission-mode auto'
}

@test "the refusal is UNCHANGED: nothing is typed onto a pane that was never confirmed" {
  drive_dead || true
  # `session send` is the only write verb; the watcher must not have reached one.
  run cat "$H/it2-calls.log"
  ! echo "$output" | grep -q 'session send'
}

@test "the wait seam DEFAULTS to 600 — the live gate is not weakened by its own test hook" {
  run grep -n 'HF_RECYCLE_SHELL_WAIT_S:-600' "$HF"
  [ "$status" -eq 0 ]
  # and a non-numeric value falls back to 600 rather than to an unbounded or zero wait
  run grep -n 'rcy_wait_max=600' "$HF"
  [ "$status" -eq 0 ]
}

@test "RED-PROOF: pre-fix, the SHELL-TIMEOUT site alone did not escalate (control must FAIL)" {
  # 🚨 THE CONTROL MUST NOT BE KEYED ON `HEAD`. It was, and it INVERTED the moment the fix was
  # committed: `git show HEAD:` then returns the FIXED file, the "pre-fix has no alarm" assertion
  # fails, and a passing suite turns red for a reason that has nothing to do with the subject.
  # A control re-derived from a moving ref is non-deterministic by construction (MEMORY.md
  # control-population-must-be-stable). Self-LOCATE the pre-fix revision instead: find the commit
  # that INTRODUCED this site's wording, and read its parent. That survives rebases, re-lands and
  # any number of later commits, because it is keyed on the change itself rather than on a ref.
  MARK='the /exit landed but no relaunch was typed'
  ADDED="$(git -C "$REPO_SRC" log --format=%H -S"$MARK" -- scripts/handoff-fire.sh 2>/dev/null | tail -1)"
  [ -n "$ADDED" ] || skip "cannot locate the commit that introduced this arm (shallow clone?)"
  OLD="$BATS_TEST_TMPDIR/old-hf.sh"
  git -C "$REPO_SRC" show "$ADDED^:scripts/handoff-fire.sh" > "$OLD" 2>/dev/null \
    || skip "no parent revision for $ADDED (root commit?)"

  # 🚨 THE CONTROL MUST KEY ON THIS SITE, NOT ON THE CLASS. `recycle-dead` is emitted from THREE
  # places, and the naive control (grep the file for 'hf_alarm recycle-dead' / 'HANDOFF-RECYCLE-
  # DEAD') SKIPPED as "HEAD already carries the fix" — because the never-ENGAGED site at :5591
  # already alarms with both of those strings. That control's span was the whole file while its
  # subject was one arm of it, so a sibling's fix silently certified this one (MEMORY.md
  # assertion-span-must-equal-its-subject). Key on the shell-timeout site's own wording instead.
  #
  # The real asymmetry, which is what made this a bug rather than a policy: of the three sites,
  #   :5513 relaunch-write-failed  → ledger row + hf_alarm recycle-relaunch-failed   (escalates)
  #   :5591 relaunched-never-engaged → ledger row + goal_unreachable + hf_alarm       (escalates)
  #   :5483 never-reached-a-shell  → ledger row ONLY                                  (SILENT)
  # and :5483 is the one pane 30 hit on 2026-08-25.
  run grep -c 'hf_alarm recycle-relaunch-failed' "$OLD"
  [ "$output" -ge 1 ]                          # sibling A escalated...
  run grep -c 'HANDOFF-RECYCLE-DEAD: pane $RSID relaunched but never engaged' "$OLD"
  [ "$output" -ge 1 ]                          # ...sibling B escalated...
  run grep -c 'the /exit landed but no relaunch was typed' "$OLD"
  [ "$output" -eq 0 ]                          # ...and the shell-timeout site did NOT. The bug.

  # And prove it BEHAVIOURALLY, not only by grep: the pre-fix file has no wait seam, so pin its
  # hardcoded 600 to 3 with sed and drive the same path. It must reach the terminal refusal and
  # leave the alarm store empty.
  sed 's/\[ "\$waited" -lt 600 \]/[ "$waited" -lt 3 ]/' "$OLD" > "$OLD.fast"
  run grep -c '"\$waited" -lt 3' "$OLD.fast"
  [ "$output" -ge 1 ] || skip "could not pin the pre-fix bound — structural assertions above stand"
  HF_RECYCLE_SHELL_WAIT_S=3 run bash "$OLD.fast" __recycle "$STUB_PANE" "$BATS_TEST_TMPDIR/no-such-tty" "$CMDFILE" "$BATS_TEST_TMPDIR"
  [ "$status" -ne 0 ]                          # it refuses, exactly as the fixed one does...
  run alarms
  [ -z "$output" ]                             # ...but it pages NOBODY. That is the defect.
}
