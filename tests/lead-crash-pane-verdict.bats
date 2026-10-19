#!/usr/bin/env bats
# lead-crash-watchdog.sh — THE PANE VERDICT (desk 88e2c2b1 / pane 330, 2026-09-08).
#
# WHAT FAILED. The desk was SIGTERMed from outside at 22:47:36Z while idle. The watchdog classified
# it correctly 30 s later (class=CRASH cause=external-sigterm) and paged role=desk — the victim.
# cc-notify appended the page to a dead inbox and returned 0; the supervisor recorded "no live
# desk" and digested it to one word. The pane showed Claude Code's ordinary `Resume this session
# with:` line over a live shell prompt, byte-identical to a clean /exit, and three hours later the
# operator had to ask which one it was. Two mechanisms, each with its own polarity here:
#   (1) the verdict is PAINTED INTO THE PANE (write(2) to the tty, no terminal API), and only over
#       a pane that settled at a bare shell — never over a relaunch, a closed pane, or a running
#       command; a clean exit that left its pane behind gets the OTHER verdict ("safe to close");
#   (2) a death whose page is addressed to the desk while the victim IS the desk is escalated to
#       the liveness-free channel, naming the restore command.
# Every source is fixtured through the arm's seams; nothing here touches a live tty, pane or store.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="${LCW_HOOK_UNDER_TEST:-$REPO/hooks/lead-crash-watchdog.sh}"
  T="$BATS_TEST_TMPDIR"
  export HOME="$T/home"
  mkdir -p "$HOME/.claude/bin" "$HOME/.claude/watchdog" "$HOME/.claude/logs" "$T/dev" "$T/roles" "$T/acct/projects/proj" "$T/jetsam" "$T/teardown" "$T/registry"
  export CC_ACCOUNT_BASES="$T/acct" CC_JETSAM_DIRS="$T/jetsam" CC_TEARDOWN_DIR="$T/teardown" CC_REGISTRY_DIR="$T/registry"
  export CC_ROLES_DIR="$T/roles" CC_SESSIONS_LOG="$T/sessions.log" CC_CUSTODY_DIR="$T/custody"
  # the pane: a fixture "tty" file stands in for /dev/ttys099; a procs file stands in for
  # `ps -t <tty> -o stat=,command=` (STAT first: `+` marks the tty's foreground process group)
  export CC_PANE_VERDICT_DEV="$T/dev" CC_PANE_VERDICT_TTY=ttys099 CC_PANE_VERDICT_TTY_PROCS="$T/procs"
  export CC_PANE_VERDICT_SETTLE_S=0 CC_PANE_VERDICT_PANE=330 CC_PANE_VERDICT_CFG="/x/.claude-tertiary"
  export CC_PANE_VERDICT_CWD="$T/cwd"
  # the closer a "holds nothing" verdict hands the pane to: a recorder, never the real cc-pane-close
  export CC_PANE_CLOSE_BIN="$T/stub-pane-close" CC_PANE_VERDICT_CLOSE_GRACE_S=0
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s"\necho "closed"\n' "$T/closed.txt" > "$CC_PANE_CLOSE_BIN"; chmod +x "$CC_PANE_CLOSE_BIN"
  : > "$T/dev/ttys099"; printf 'Ss+ /bin/zsh -l\n' > "$T/procs"; printf '999\n' > "$T/roles/desk"
  # the session's cwd: a git repo, dirty by default (an untracked file); tests make it clean as needed
  mkdir -p "$T/cwd"; git -C "$T/cwd" init -q; git -C "$T/cwd" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  git -C "$T/cwd" update-ref refs/remotes/origin/main HEAD; : > "$T/cwd/scratch.txt"
  # the two liveness-free transports, stubbed as collectors
  PAGED="$T/paged.txt"; OSA="$T/osa.txt"
  export CC_DEATH_PAGER="$T/stub-pager" CC_DEATH_OSA_BIN="$T/stub-osa"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s"\n' "$PAGED" > "$CC_DEATH_PAGER"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s"\n' "$OSA" > "$CC_DEATH_OSA_BIN"
  chmod +x "$CC_DEATH_PAGER" "$CC_DEATH_OSA_BIN"
  SID="88e2c2b1-ad2b-407a-a889-e7fd15c8076e"
  TX="$T/acct/projects/proj/$SID.jsonl"
  printf '{"type":"assistant","message":{"content":[{"type":"text","text":"Good to close: no — waiting"}]},"version":"2.1.260"}\n' > "$TX"
}
verdict_with() { # $1=hook $2=class $3=cause $4=exit $5=sig
  bash "$1" --pane-verdict "$SID" 63977 "$2" "$3" "$4" "$5" "$TX" </dev/null
}
painted() { cat "$T/dev/ttys099"; }

@test "external-sigterm over a bare shell paints NOT A CLEAN EXIT, the cause, and the PINNED launcher's resume line" {
  run verdict_with "$HOOK" CRASH external-sigterm 143 15
  [ "$status" -eq 0 ]
  painted | grep -q 'NOT A CLEAN EXIT'
  painted | grep -q 'was KILLED here'
  painted | grep -q 'external-sigterm (exit 143, signal 15)'
  painted | grep -q "nocorrect CC_ACCOUNT_PINNED=1 claude3 --resume $SID"
  painted | grep -q 'cc-husk-sweep --pane 330'
  # the pane's own printed spelling (default account) is named as WRONG, never offered as the command
  ! painted | grep -q '^▶.* claude --resume' || false
  # the stdout copy carries the same content, so a caller without a tty can still read it
  echo "$output" | grep -q 'NOT A CLEAN EXIT'
}

@test "the verdict carries the work state of the cwd and the session's last close verdict (facts, not the session's word)" {
  run verdict_with "$HOOK" CRASH external-sigterm 143 15
  painted | grep -q 'dirty:1'
  painted | grep -q 'last close verdict: no'
}

@test "the title escape rides along, so the tab is labelled until the next prompt" {
  run verdict_with "$HOOK" CRASH external-sigterm 143 15
  painted | LC_ALL=C grep -q $'\033]2;⛔ KILLED 88e2c2b1\a'
}

@test "when the victim IS the desk the pane says so, and the death is escalated to Notification Center with the restore command" {
  printf '330\n' > "$T/roles/desk"
  run verdict_with "$HOOK" CRASH external-sigterm 143 15
  painted | grep -q 'the DESK'
  run bash "$HOOK" --surface-death "$SID" 63977 CRASH external-sigterm 143 15 "$TX"
  [ -s "$PAGED" ]
  [ -s "$OSA" ] || { echo "desk death was not escalated"; false; }
  grep -q 'DESK DOWN' "$OSA"
  grep -q 'cc-husk-sweep --resume --pane 330' "$OSA"
}

@test "POLARITY: a death that is not the desk's is paged but NOT escalated to the OS channel" {
  run bash "$HOOK" --surface-death "$SID" 63977 CRASH external-sigterm 143 15 "$TX"
  [ -s "$PAGED" ]
  [ ! -s "$OSA" ] || { echo "a non-desk death was escalated: $(cat "$OSA")"; false; }
}

@test "a pane where a claude is back on the tty (recycle/resume) is left alone" {
  printf 'Ss /bin/zsh -l\nS+ bash /x/cc-close-attrib /x/.claude-260/node_modules/.bin/claude --permission-mode auto\nS+ /x/.claude-260/node_modules/.bin/claude --permission-mode auto\n' > "$T/procs"
  run verdict_with "$HOOK" CRASH external-sigterm 143 15
  [ "$status" -eq 0 ]
  [ ! -s "$T/dev/ttys099" ] || { echo "painted over a live claude: $(painted)"; false; }
}

@test "a pane that closed (tty gone) is left alone — and nothing creates a phantom tty file" {
  rm -f "$T/dev/ttys099"
  run verdict_with "$HOOK" CRASH external-sigterm 143 15
  [ "$status" -eq 0 ]
  [ ! -e "$T/dev/ttys099" ]
}

@test "a running command on the tty (not a bare prompt) is never written over" {
  printf 'Ss /bin/zsh -l\nS+ vim notes.md\n' > "$T/procs"
  run verdict_with "$HOOK" CRASH external-sigterm 143 15
  [ ! -s "$T/dev/ttys099" ] || { echo "painted over a running command"; false; }
}

@test "a clean exit whose pane survived, over CLEAN work, paints CLOSED CLEANLY and 'safe to close'" {
  rm -f "$T/cwd/scratch.txt"
  printf '[2026-09-08 17:47:36] Session ended sid=%s reason=prompt_input_exit\n' "$SID" > "$CC_SESSIONS_LOG"
  run verdict_with "$HOOK" RECYCLE clean-exit 0 ""
  painted | grep -q 'CLOSED CLEANLY'
  painted | grep -q 'reason: prompt_input_exit'
  painted | grep -q 'safe to close'
  ! painted | grep -q 'KILLED' || false
}

@test "a clean exit over CLEAN work hands its pane to cc-pane-close after painting" {
  rm -f "$T/cwd/scratch.txt"
  run verdict_with "$HOOK" RECYCLE clean-exit 0 ""
  painted | grep -q 'safe to close'
  grep -qx -- '--pane 330' "$T/closed.txt" || { cat "$T/closed.txt" 2>/dev/null; false; }
}
@test "CONTROL: a clean exit over DIRTY work is never handed to the closer" {
  run verdict_with "$HOOK" RECYCLE clean-exit 0 ""
  [ ! -s "$T/closed.txt" ] || { cat "$T/closed.txt"; false; }
}
@test "CONTROL: a crash verdict is never handed to the closer" {
  rm -f "$T/cwd/scratch.txt"
  run verdict_with "$HOOK" CRASH external-sigterm 143 15
  [ ! -s "$T/closed.txt" ] || { cat "$T/closed.txt"; false; }
}
@test "a desk retirement's pane is handed to the closer; CC_PANE_VERDICT_CLOSE=off paints only" {
  run verdict_with "$HOOK" RECYCLE retired-by-desk 137 9
  grep -qx -- '--pane 330' "$T/closed.txt" || false
  rm -f "$T/closed.txt"; : > "$T/dev/ttys099"
  CC_PANE_VERDICT_CLOSE=off run verdict_with "$HOOK" RECYCLE retired-by-desk 137 9
  painted | grep -q 'safe to close'
  [ ! -s "$T/closed.txt" ] || { cat "$T/closed.txt"; false; }
}

@test "a clean exit over DIRTY work warns about the work instead of saying safe" {
  run verdict_with "$HOOK" RECYCLE clean-exit 0 ""
  painted | grep -q 'CLOSED CLEANLY'
  painted | grep -q 'uncommitted or unlanded work'
  ! painted | grep -q 'safe to close' || false
  painted | grep -q "claude3 --resume $SID"
}

@test "a retirement by the desk whose pane survived says safe to close and do NOT resume" {
  run verdict_with "$HOOK" RECYCLE retired-by-desk 137 9
  painted | grep -q 'RETIRED'
  painted | grep -q 'Do NOT resume'
  painted | grep -q 'safe to close'
}

@test "kill switch CC_PANE_VERDICT=0 paints nothing" {
  CC_PANE_VERDICT=0 run verdict_with "$HOOK" CRASH external-sigterm 143 15
  [ "$status" -eq 0 ]
  [ ! -s "$T/dev/ttys099" ]
}

@test "no tty recorded at registration ⇒ nothing painted, nothing written anywhere under the dev dir" {
  CC_PANE_VERDICT_TTY="" run verdict_with "$HOOK" CRASH external-sigterm 143 15
  [ "$status" -eq 0 ]
  [ ! -s "$T/dev/ttys099" ]
}

# ── THE CONTROL. Executes the PRE-FIX file and asserts it CANNOT paint. Self-located from the
# change itself (MEMORY.md control-population-must-be-stable), never from a moving ref.
@test "RED-PROOF: the pre-fix hook paints no pane verdict (control must FAIL)" {
  ADDED="$(git -C "$REPO" log --format=%H -S'paint_pane_verdict' -- hooks/lead-crash-watchdog.sh 2>/dev/null | tail -1)"
  [ -n "$ADDED" ] || skip "cannot locate the commit that introduced paint_pane_verdict (uncommitted, or shallow clone)"
  OLD="$T/old-hook.sh"
  git -C "$REPO" show "$ADDED^:hooks/lead-crash-watchdog.sh" > "$OLD" 2>/dev/null || skip "no parent revision for $ADDED"
  ! grep -q 'paint_pane_verdict' "$OLD" || false
  run verdict_with "$OLD" CRASH external-sigterm 143 15
  ! painted | grep -q 'NOT A CLEAN EXIT' || false
  [ ! -s "$T/dev/ttys099" ] || { echo "pre-fix hook painted something: $(painted)"; false; }
}

@test "a transcript with no 'Good to close' phrase and no SessionEnd row still paints a full verdict (pipefail must not eat it)" {
  printf '{"type":"assistant","message":{"content":[{"type":"text","text":"working"}]}}\n' > "$TX"
  rm -f "$CC_SESSIONS_LOG"
  run verdict_with "$HOOK" CRASH external-sigterm 143 15
  [ "$status" -eq 0 ]
  painted | grep -q 'NOT A CLEAN EXIT'
  painted | grep -q 'last close verdict: -'
  painted | grep -q "claude3 --resume $SID"
}

# ── the prompt's background residents (2026-09-22, pane 503 / ttys006) ─────────────────────────────
# A zsh pane here always carries the prompt's gitstatusd on its tty (ppid = the shell, or 1 once
# its shell died). The prior rule — every attached process must be NAMED like a shell — refused 31
# of 33 panes that settled at a prompt. "Is something running there" is the foreground process
# group's question; ps answers it with `+`. These fixtures are the incident tty's real shape.
GITSTATUSD='/Users/x/.cache/gitstatus/gitstatusd-darwin-arm64 -G v1.5.4 -s -1 -u -1 -d -1 -c -1 -m -1 -v FATAL -t 20'

@test "INCIDENT: a bare prompt whose tty also holds the prompt's background gitstatusd IS painted" {
  printf 'S+ /bin/zsh -l -i\nS /bin/zsh -l -i\nSs /bin/zsh -l\nS %s\nS %s\n' "$GITSTATUSD" "$GITSTATUSD" > "$T/procs"
  run verdict_with "$HOOK" RECYCLE clean-exit 0 ""
  [ "$status" -eq 0 ]
  painted | grep -q 'CLOSED CLEANLY' || { echo "not painted over a bare prompt: $(painted)"; false; }
}

@test "a background resident never masks a FOREGROUND command — that pane is still not written over" {
  printf 'Ss /bin/zsh -l\nS %s\nS+ vim notes.md\n' "$GITSTATUSD" > "$T/procs"
  run verdict_with "$HOOK" RECYCLE clean-exit 0 ""
  [ ! -s "$T/dev/ttys099" ] || { echo "painted over a foreground vim: $(painted)"; false; }
}

@test "a probe that shows NO foreground marker falls back to judging every process (a blind probe is not a prompt)" {
  printf 'Ss /bin/zsh -l\nS %s\n' "$GITSTATUSD" > "$T/procs"
  run verdict_with "$HOOK" RECYCLE clean-exit 0 ""
  [ ! -s "$T/dev/ttys099" ] || { echo "painted on a probe that could not see the foreground group: $(painted)"; false; }
}

@test "RED-PROOF: the pre-fix name-allowlist rule refuses the incident tty (control must FAIL)" {
  FIXED="$(git -C "$REPO" log --format=%H -S'the foreground group is only shells' -- hooks/lead-crash-watchdog.sh 2>/dev/null | tail -1)"
  [ -n "$FIXED" ] || skip "cannot locate the commit that introduced the foreground-group rule (uncommitted, or shallow clone)"
  OLD="$T/old-hook.sh"
  git -C "$REPO" show "$FIXED^:hooks/lead-crash-watchdog.sh" > "$OLD" 2>/dev/null || skip "no parent revision for $FIXED"
  ! grep -q 'the foreground group is only shells' "$OLD" || false
  # the pre-fix probe emitted command-only lines; replay the incident tty in THAT shape
  printf '/bin/zsh -l -i\n/bin/zsh -l -i\n/bin/zsh -l\n%s\n' "$GITSTATUSD" > "$T/procs"
  run verdict_with "$OLD" RECYCLE clean-exit 0 ""
  [ ! -s "$T/dev/ttys099" ] || { echo "pre-fix hook painted — the control proves nothing: $(painted)"; false; }
}

# ── custody (docs/research/husk-triage-2026-10-01.md § Gaps, item 2) ───────────────────────────────
# Pane 55's lead was killed at 02:26Z; its orchestrator collected the work and abandoned its custody
# at 03:59Z, yet the banner said "▶ Resume it here", which would re-arm a live /goal over finished
# work. The CRASH arm now reads lib/pane-custody.sh for its pane (330 here).
custody_row() { # <kind> <ts> [targetPane]
  mkdir -p "$CC_CUSTODY_DIR"
  printf '{"ts":"%s","kind":"%s","cwd":"/orig","originatorPane":"38","targetPane":"%s","marker":"M55","slug":"w2-reso-review"}\n' "$2" "$1" "${3:-330}" >> "$CC_CUSTODY_DIR/k.jsonl"
}

@test "CRASH + custody collected by its originator: no --resume line, says collected and close the pane" {
  custody_row open 2026-10-01T00:35:50Z
  custody_row abandon 2026-10-01T03:59:28Z
  run verdict_with "$HOOK" CRASH external-sigterm 143 15
  [ "$status" -eq 0 ]
  ! painted | grep -q -- '--resume' || { echo "a collected lead was offered a resume: $(painted)"; false; }
  painted | grep -q 'WORK COLLECTED'
  painted | grep -q 'originator (pane 38) collected its work'
  painted | grep -q 'custody w2-reso-review: abandon at 2026-10-01T03:59:28Z'
  painted | grep -q 'Do NOT resume it — close this pane (Ctrl-D)'
  painted | grep -q 'cc-husk-sweep --pane 330'
}

@test "CRASH + custody still open: no bare resume line; the banner names the originator pane" {
  custody_row open 2026-10-01T00:35:50Z
  run verdict_with "$HOOK" CRASH external-sigterm 143 15
  [ "$status" -eq 0 ]
  ! painted | grep -q 'Resume it here' || { echo "an owned lead was offered a resume: $(painted)"; false; }
  ! painted | grep -q -- '--resume' || false
  painted | grep -q 'NOT A CLEAN EXIT'
  painted | grep -q 'its originator (pane 38) holds custody of this work (w2-reso-review'
  painted | grep -q 'cc-husk-sweep --pane 330'
}

@test "CRASH + no custody for this pane (another pane's row, or an earlier tenant's) is unchanged" {
  custody_row open 2026-10-01T00:35:50Z 41
  custody_row abandon 2026-10-01T03:59:28Z 41
  run verdict_with "$HOOK" CRASH external-sigterm 143 15
  painted | grep -q "▶ Resume it here:   nocorrect CC_ACCOUNT_PINNED=1 claude3 --resume $SID"
  # pane-id reuse: a row targeting 330 from BEFORE this session's first record does not speak for it
  : > "$T/dev/ttys099"
  custody_row open 2026-09-30T10:00:00Z
  custody_row abandon 2026-09-30T12:00:00Z
  printf '{"type":"user","timestamp":"2026-10-01T00:00:00.000Z"}\n' | cat - "$TX" > "$T/tx2" && mv "$T/tx2" "$TX"
  run verdict_with "$HOOK" CRASH external-sigterm 143 15
  painted | grep -q "▶ Resume it here:   nocorrect CC_ACCOUNT_PINNED=1 claude3 --resume $SID"
  ! painted | grep -q 'WORK COLLECTED' || false
}

@test "a TEAMMATE's CRASH banner keeps naming its lead, custody or not" {
  printf '{"type":"user","teamName":"session-918b909f","agentName":"trunk-reds"}\n' >> "$TX"
  custody_row open 2026-10-01T00:35:50Z
  custody_row abandon 2026-10-01T03:59:28Z
  run verdict_with "$HOOK" CRASH external-sigterm 143 15
  painted | grep -q 'Teammate trunk-reds is not resumable'
  ! painted | grep -q 'WORK COLLECTED' || false
}

# ── lr-wake 2026-10-18 (REPORT §4 Wave F, RC4): lr's records outrank the death class ─────────────
# Pane 332 was painted "✅ CLOSED CLEANLY … safe to close" 28 s after lr recorded STRANDED, with a
# `claude4` resume line for a session whose full transcript lived on another account. The fixture is
# a move next4→next3: the registration's store (quaternary) holds the 4 KB stub + the HANDOFF.json
# tombstone, the tertiary store holds the full transcript, and the bundle's verdict row says STRANDED.
# RED on origin/main (7dc482f24), measured: the five cases below fail there (the first paints CLOSED
# CLEANLY and `safe to close`); the lone-fault CONTROL passes on both.
lr_move_fixture() {
  SRC="$T/src/.claude-quaternary"; DST="$T/dst/.claude-tertiary"
  mkdir -p "$SRC/projects/proj" "$DST/projects/proj" "$T/lr/$SID/bundle-20261018T071345Z"
  export CC_PANE_VERDICT_CFG="$SRC" LR_STATE_DIR="$T/lr" CC_FIND_BIN="$T/stub-find"
  printf '{"type":"user","message":{"role":"user","content":"stub"}}\n' > "$SRC/projects/proj/$SID.jsonl"
  printf '{"sid":"%s","handed_off_to":"%s"}\n' "$SID" "$DST" > "$SRC/projects/proj/$SID.HANDOFF.json"
  printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Good to close: no — mid-search"}]}}\n' > "$DST/projects/proj/$SID.jsonl"
  printf '{"ts":"%s","state":"STRANDED","stage":"verdict","detail":"proven=no — session %s now lives under %s, and the source pane 330 is a tombstoned husk"}\n' \
    "$(date -u +%FT%TZ)" "${SID:0:8}" "$DST" > "$T/lr/$SID/bundle-20261018T071345Z/events.jsonl"
  printf '#!/bin/bash\ncat "%s" 2>/dev/null\nexit 0\n' "$T/find.out" > "$T/stub-find"; chmod +x "$T/stub-find"
  rm -f "$T/cwd/scratch.txt"                      # clean work: the old arm said "safe to close" here
}

@test "STRANDED bundle: no CLOSED CLEANLY, no safe to close; the answer-first line names the move and lr-fleet; the hint is claude3" {
  lr_move_fixture
  run verdict_with "$HOOK" RECYCLE clean-exit 0 ""
  [ "$status" -eq 0 ]
  painted | grep -qF "✗ 88e2c2b1 moved next4→next3, relaunch failed · ▶ lr-fleet --one 88e2c2b1" || { painted; false; }
  ! painted | grep -q 'CLOSED CLEANLY' || { painted; false; }
  ! painted | grep -q 'safe to close' || { painted; false; }
  painted | grep -q '(claude3)' || { painted; false; }
  ! painted | grep -q 'claude4' || { painted; false; }
  painted | grep -q 'last close verdict: no'          # read from the FULL transcript, not the stub
  # it is never handed to the closer, and it is queued exactly once for lr's poller
  [ ! -s "$T/closed.txt" ] || { cat "$T/closed.txt"; false; }
  jq -e --arg d "$DST" '.cause == "stranded" and .mode == "recover" and .config_dir == $d and .pane == "330"' "$T/lr/requests/$SID.cc-lr.json"
}

@test "STRANDED: a repaint queues nothing twice, and a parked record or live run claim means nothing is queued" {
  lr_move_fixture
  run verdict_with "$HOOK" RECYCLE clean-exit 0 ""
  at1=$(jq -r .at "$T/lr/requests/$SID.cc-lr.json"); : > "$T/dev/ttys099"
  run verdict_with "$HOOK" CRASH external-sigterm 143 15
  [ "$(jq -r .at "$T/lr/requests/$SID.cc-lr.json")" = "$at1" ]
  [ "$(find "$T/lr/requests" -name "$SID*" | wc -l | tr -d ' ')" = 1 ]
  painted | grep -q 'Queued for the limit-recover poller'
  rm -rf "$T/lr/requests"; mkdir -p "$T/lr/parked"; printf '{}\n' > "$T/lr/parked/$SID.json"; : > "$T/dev/ttys099"
  run verdict_with "$HOOK" RECYCLE clean-exit 0 ""
  [ ! -e "$T/lr/requests/$SID.cc-lr.json" ]
  painted | grep -q 'already holds it (a parked record)'
}

@test "K6: the same move with a LIVE copy cc-find shows in another pane is MOVED, and only then handed to the closer" {
  lr_move_fixture
  printf '%s\t442\tnext3\t%s\t/x\tLIVE\tLEAD\n' "$SID" "$DST" > "$T/find.out"
  run verdict_with "$HOOK" RECYCLE clean-exit 0 ""
  painted | grep -qF "✅ 88e2c2b1 moved next4→next3 and runs in pane 442" || { painted; false; }
  [ ! -e "$T/lr/requests/$SID.cc-lr.json" ]
  grep -qx -- '--pane 330 --dry-run' "$T/closed.txt"
  grep -qx -- '--pane 330' "$T/closed.txt"
}

@test "K6 CONTROL: a LIVE copy in THIS pane is not a copy elsewhere — still STRANDED" {
  lr_move_fixture
  printf '%s\t330\tnext3\t%s\t/x\tLIVE\tLEAD\n' "$SID" "$DST" > "$T/find.out"
  run verdict_with "$HOOK" RECYCLE clean-exit 0 ""
  painted | grep -q 'relaunch failed' || { painted; false; }
}

@test "the closer decides before the paint: when --dry-run refuses, its reason replaces 'safe to close' and no close follows" {
  rm -f "$T/cwd/scratch.txt"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s"\ncase "$*" in *--dry-run*) echo "pane 330: REFUSED — nothing says session 88e2c2b1 meant to end"; exit 1 ;; esac\necho closed\n' "$T/closed.txt" > "$CC_PANE_CLOSE_BIN"
  run verdict_with "$HOOK" RECYCLE clean-exit 0 ""
  ! painted | grep -q 'safe to close' || { painted; false; }
  painted | grep -q 'the closer keeps this pane: nothing says session 88e2c2b1 meant to end' || { painted; false; }
  [ "$(cat "$T/closed.txt")" = "--pane 330 --dry-run" ] || { cat "$T/closed.txt"; false; }
}

@test "CONTROL: a lone fault record with no tombstone, lock or STRANDED verdict changes nothing" {
  mkdir -p "$T/lr/faults"; export LR_STATE_DIR="$T/lr"
  printf '{"sid":"%s","first_seen":%s,"claim":{"by":"/x/.claude-secondary"}}\n' "$SID" "$(date +%s)" > "$T/lr/faults/$SID.json"
  rm -f "$T/cwd/scratch.txt"
  run verdict_with "$HOOK" RECYCLE clean-exit 0 ""
  painted | grep -q 'CLOSED CLEANLY'
  [ ! -d "$T/lr/requests" ]
}
