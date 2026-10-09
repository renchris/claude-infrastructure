#!/usr/bin/env bats
# handoff-fire.sh __recycle — a CONFIRMED shell must stay confirmed.
#
# THE INCIDENT (2026-09-26T21:01Z, pane 780, kitty, limit recovery of ac0f0123 next → next2). The
# watcher's own log reads, in full after arming:
#   !! pane 780 never reached a CONFIRMED shell prompt in 6s (probe verdict: shell)
# and the ledger row: "never reached a confirmed shell in 6s (verdict: shell); background-work
# dialog SEEN, answered 0x". The /exit HAD landed: the wait loop ended at 6 s because at_shell
# SUCCEEDED. The post-loop `if ! at_shell` then probed the pane a SECOND time, caught zsh's precmd
# with a child in the foreground process group (pane_cc_state reads anything but a shell there as
# `unknown`), and declared the pane dead. A third probe, for the message, read `shell` again. So a
# recycle that worked was refused over a sub-second prompt redraw, and the relaunch was never typed.
#
# The "dialog SEEN, answered 0x" clause was false as well: no dialog check ran at all (the first one
# is at 15 s). `${rcy_bgwork_seen:+…}` expands for any non-empty value, and the flag is initialised
# to 0, so every recycle-dead row claimed a dialog. That false clause is what pointed the incident
# report at a missing kitty answer path.
#
# WHAT IS DRIVEN. The detached `__recycle` watcher itself, against a stub `it2` and a `ps` that
# answers pane_cc_state's queries from a counter: the foreground-group query (`ps -g`) reads a bare
# zsh on every call except the SECOND, which carries a prompt helper. That is the incident's probe
# sequence (shell, then not-shell, then shell) with the timing removed.

setup() {
  REPO_SRC="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO_SRC/scripts/handoff-fire.sh"
  [ -f "$HF" ] || { echo "subject missing" >&2; return 1; }
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  export HANDOFF_ACCOUNT_SWEEP=off
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/no-sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/no-such-claude-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/no-such-heal-lock-"
  export H="$BATS_TEST_TMPDIR/home"; mkdir -p "$H/.claude/bin"; export HOME="$H"
  export CC_HANDOFF_ALARM_DIR="$H/.claude/handoff-alarms"

  SHIM="$BATS_TEST_TMPDIR/shim"; mkdir -p "$SHIM"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$SHIM/osascript"; chmod +x "$SHIM/osascript"
  export CC_NOTIFY_BIN="$H/.claude/bin/cc-notify"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$CC_NOTIFY_BIN"; chmod +x "$CC_NOTIFY_BIN"

  # The pane: one zsh (pid 4100) owning the tty and its own foreground group. `-g` is the leg-(b)
  # query; its 2nd answer adds a non-shell member, which pane_cc_state reads as `unknown`.
  export PS_COUNT="$BATS_TEST_TMPDIR/ps-g.count"; : > "$PS_COUNT"
  export FLICKER_AT="${FLICKER_AT:-2}"
  cat > "$SHIM/ps" <<'PS'
#!/usr/bin/env bash
case " $* " in
  *" -g "*)
    printf 'x' >> "$PS_COUNT"; n="$(wc -c < "$PS_COUNT" | tr -d ' ')"
    printf '4100 /bin/zsh\n'
    [ "$n" = "${FLICKER_AT:-2}" ] && printf '4101 git\n'
    exit 0 ;;
  *" -axo "*|*" -Ao "*) printf '4100 1\n'; exit 0 ;;
  *"comm="*) printf '/bin/zsh\n'; exit 0 ;;
  *"args="*) printf -- '-zsh\n'; exit 0 ;;
esac
printf '4100\n'
PS
  chmod +x "$SHIM/ps"
  export PATH="$SHIM:$PATH"

  export STUB_PANE="FLICKER-PANE"
  cat > "$H/.claude/bin/it2" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$HOME/it2-calls.log"
case "$1 $2" in
  "session list")
    if [ "${3:-}" = --json ]; then printf '[{"id": "%s", "tty": "/dev/ttys999"}]\n' "$STUB_PANE"
    else printf '%s\n' "$STUB_PANE"; fi
    exit 0 ;;
  "session read") printf '%s\n' '~/work %'; exit 0 ;;
esac
exit 0
SH
  chmod +x "$H/.claude/bin/it2"

  CMDFILE="$BATS_TEST_TMPDIR/relaunch.cmd"; printf 'claude --permission-mode auto\n' > "$CMDFILE"
  export CMDFILE
  export HF_RECYCLE_SHELL_WAIT_S=6
  # The typing loop is a deadline now (RECYCLE_KEYSTROKELESS_DELIVERY §D2.7, default 600 s); 0 keeps
  # the old two rounds, which is all a case here that serves a non-echoing screen should wait.
  export CC_RECYCLE_TYPE_DEADLINE_S=0
}

drive() { bash "$HF" __recycle "$STUB_PANE" /dev/ttys999 "$CMDFILE" "$BATS_TEST_TMPDIR"; }

@test "[RED] a shell the wait loop CONFIRMED is not re-convicted by a second probe that caught a prompt redraw" {
  run drive
  [[ "$output" == *"CONFIRMED at a shell prompt"* ]] || { echo "$output"; false; }
  [[ "$output" != *"never reached a CONFIRMED shell prompt"* ]] || { echo "$output"; false; }
  run bash -c "grep -c 'recycle-dead.*never reached a confirmed shell' '$H/.claude/logs/handoffs.jsonl' || true"
  [ "$output" = 0 ] || { cat "$H/.claude/logs/handoffs.jsonl"; false; }
}

@test "CONTROL: a pane that never shows a shell is still refused — the fix does not type onto an unconfirmed pane" {
  # Every foreground-group read carries the helper, so no probe ever certifies a shell.
  cat > "$SHIM/ps" <<'PS'
#!/usr/bin/env bash
case " $* " in
  *" -g "*) printf '4100 /bin/zsh\n4101 git\n'; exit 0 ;;
  *" -axo "*|*" -Ao "*) printf '4100 1\n'; exit 0 ;;
  *"comm="*) printf '/bin/zsh\n'; exit 0 ;;
  *"args="*) printf -- '-zsh\n'; exit 0 ;;
esac
printf '4100\n'
PS
  run drive
  [ "$status" -ne 0 ]
  [[ "$output" == *"never reached a CONFIRMED shell prompt"* ]] || { echo "$output"; false; }
  run bash -c "grep -c 'session run' '$H/it2-calls.log' || true"
  [ "$output" = 0 ] || { cat "$H/it2-calls.log"; false; }
}

@test "[RED] a recycle-dead row claims the background-work dialog ONLY when a dialog was actually seen" {
  cat > "$SHIM/ps" <<'PS'
#!/usr/bin/env bash
case " $* " in
  *" -g "*) printf '4100 /bin/zsh\n4101 git\n'; exit 0 ;;
  *" -axo "*|*" -Ao "*) printf '4100 1\n'; exit 0 ;;
  *"comm="*) printf '/bin/zsh\n'; exit 0 ;;
  *"args="*) printf -- '-zsh\n'; exit 0 ;;
esac
printf '4100\n'
PS
  drive || true
  run cat "$H/.claude/logs/handoffs.jsonl"
  [[ "$output" == *"never reached a confirmed shell"* ]] || { echo "$output"; false; }
  [[ "$output" != *"background-work dialog SEEN"* ]] || { echo "$output"; false; }
}
