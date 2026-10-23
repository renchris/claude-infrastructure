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

load helpers/cc-stub

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
  # The legacy paint is the FALLBACK when bin/cc-pane-verdict is absent; these cases pin it. The F5
  # cases at the end turn the tool on and pin the contract wording it paints instead.
  export CC_PANE_VERDICT_TOOL=off CC_PANE_VERDICT_DIR="$T/pv" CC_PANE_VERDICT_KITTY_BIN="$T/no-kitty"
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
# the painted text with its truecolor runs stripped (the OSC-2 title stays); the raw bytes are the file
painted() { LC_ALL=C sed $'s/\033\\[[0-9;]*m//g' "$T/dev/ttys099"; }
# what the verdict dropped from the pane: cc_say_detail's log, under the fixture HOME
said() { cat "$HOME/.claude/logs/pane-say.jsonl" 2>/dev/null; }
# every painted row fits the 56-cell pane budget (cc-say's own cell model), with no SGR-2 and no rule
assert_rows() {
  ! LC_ALL=C grep -q $'\033\\[2m' "$T/dev/ttys099" || { echo "SGR-2 painted"; false; }
  ! grep -q '────' "$T/dev/ttys099" || { echo "a rule was painted: $(painted)"; false; }
  # shellcheck source=/dev/null
  . "$REPO/lib/cc-say.sh"
  local line n=0
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    cc_say_cells "$line"; [ "$CC_SAY_CELLS" -le 56 ] || { echo "row is $CC_SAY_CELLS cells: $line"; false; }
    n=$((n + 1))
  done < <(painted)
  [ "$n" -ge 1 ] && [ "$n" -le 4 ] || { echo "$n rows painted: $(painted)"; false; }
}

@test "external-sigterm over a bare shell paints killed, the cause and triage; the PINNED launcher's resume line is logged" {
  run verdict_with "$HOOK" CRASH external-sigterm 143 15
  [ "$status" -eq 0 ]
  painted | grep -q '✗ 88e2c2b1 killed (external-sigterm)'
  painted | grep -q '▶ cc-husk-sweep --pane 330'
  said | grep -q 'external-sigterm (exit 143, signal 15)'
  said | grep -q "nocorrect CC_ACCOUNT_PINNED=1 claude3 --resume $SID"
  # the resume line (~85 cells) never fits a row; the pane's own printed spelling is never offered
  ! painted | grep -q -- '--resume' || false
  ! painted | grep -q '^▶.* claude --resume' || false
  # the stdout copy carries the same content, so a caller without a tty can still read it
  echo "$output" | grep -q 'killed (external-sigterm)'
  assert_rows
}

@test "the verdict carries the work state of the cwd and the session's last close verdict (facts, not the session's word)" {
  run verdict_with "$HOOK" CRASH external-sigterm 143 15
  painted | grep -q '⚠ uncommitted work in cwd'
  said | grep -q 'work in [^"]*: dirty:1'
  said | grep -q 'last close verdict: no'
}

@test "the title escape rides along, so the tab is labelled until the next prompt" {
  run verdict_with "$HOOK" CRASH external-sigterm 143 15
  painted | LC_ALL=C grep -q $'\033]2;⛔ KILLED 88e2c2b1\a'
}

@test "when the victim IS the desk the pane says so, and the death is escalated to Notification Center with the restore command" {
  printf '330\n' > "$T/roles/desk"
  run verdict_with "$HOOK" CRASH external-sigterm 143 15
  painted | grep -q '88e2c2b1 (desk) killed'
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

@test "a clean exit whose pane survived, over CLEAN work, paints one 'ended cleanly · closing in' row" {
  rm -f "$T/cwd/scratch.txt"
  printf '[2026-09-08 17:47:36] Session ended sid=%s reason=prompt_input_exit\n' "$SID" > "$CC_SESSIONS_LOG"
  run verdict_with "$HOOK" RECYCLE clean-exit 0 ""
  painted | grep -q '✓ 88e2c2b1 ended cleanly · closing in 0s'
  said | grep -q 'reason: prompt_input_exit'
  ! painted | grep -qi 'killed' || false
  assert_rows
}

@test "a clean exit over CLEAN work hands its pane to cc-pane-close after painting" {
  rm -f "$T/cwd/scratch.txt"
  run verdict_with "$HOOK" RECYCLE clean-exit 0 ""
  painted | grep -q 'closing in 0s'
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
  ! painted | grep -q 'closing in' || false        # no countdown when nothing will close it
  [ ! -s "$T/closed.txt" ] || { cat "$T/closed.txt"; false; }
}

@test "a clean exit over DIRTY work adds ONE amber work row instead of a countdown" {
  run verdict_with "$HOOK" RECYCLE clean-exit 0 ""
  painted | grep -q '✓ 88e2c2b1 ended cleanly'
  painted | grep -q '⚠ uncommitted work in cwd'
  ! painted | grep -q 'closing in\|safe to close' || false
  said | grep -q "claude3 --resume $SID"
  assert_rows
}

@test "a retirement by the desk whose pane survived says retired and closing; do NOT resume is logged" {
  run verdict_with "$HOOK" RECYCLE retired-by-desk 137 9
  painted | grep -q '✓ 88e2c2b1 retired by desk · closing in 0s'
  said | grep -q 'Do NOT resume'
  assert_rows
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
  painted | grep -q 'killed (external-sigterm)'
  said | grep -q 'last close verdict: -'
  said | grep -q "claude3 --resume $SID"
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
  painted | grep -q 'ended cleanly' || { echo "not painted over a bare prompt: $(painted)"; false; }
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
  painted | grep -q '✓ 88e2c2b1 work collected by pane 38 · do not resume'
  said | grep -q 'originator (pane 38) collected its work'
  said | grep -q 'custody w2-reso-review: abandon at 2026-10-01T03:59:28Z'
  painted | grep -q '▶ cc-husk-sweep --pane 330'
  assert_rows
}

@test "CRASH + custody still open: no resume line anywhere; one ⚠ row names the originator pane" {
  custody_row open 2026-10-01T00:35:50Z
  run verdict_with "$HOOK" CRASH external-sigterm 143 15
  [ "$status" -eq 0 ]
  ! painted | grep -q -- '--resume' || { echo "an owned lead was offered a resume: $(painted)"; false; }
  ! said | grep -q -- '--resume' || { echo "an owned lead's log offered a resume: $(said)"; false; }
  painted | grep -q 'killed (external-sigterm)'
  painted | grep -q '⚠ pane 38 holds custody of its work · tell it'
  said | grep -q 'its originator (pane 38) holds custody of this work (w2-reso-review'
  painted | grep -q 'cc-husk-sweep --pane 330'
  assert_rows
}

@test "CRASH + no custody for this pane (another pane's row, or an earlier tenant's) is unchanged" {
  custody_row open 2026-10-01T00:35:50Z 41
  custody_row abandon 2026-10-01T03:59:28Z 41
  run verdict_with "$HOOK" CRASH external-sigterm 143 15
  said | grep -q "resume: nocorrect CC_ACCOUNT_PINNED=1 claude3 --resume $SID"
  # pane-id reuse: a row targeting 330 from BEFORE this session's first record does not speak for it
  : > "$T/dev/ttys099"; : > "$HOME/.claude/logs/pane-say.jsonl"
  custody_row open 2026-09-30T10:00:00Z
  custody_row abandon 2026-09-30T12:00:00Z
  printf '{"type":"user","timestamp":"2026-10-01T00:00:00.000Z"}\n' | cat - "$TX" > "$T/tx2" && mv "$T/tx2" "$TX"
  run verdict_with "$HOOK" CRASH external-sigterm 143 15
  said | grep -q "resume: nocorrect CC_ACCOUNT_PINNED=1 claude3 --resume $SID"
  ! painted | grep -q 'work collected' || false
}

@test "a TEAMMATE's CRASH banner keeps naming its lead, custody or not" {
  printf '{"type":"user","teamName":"session-918b909f","agentName":"trunk-reds"}\n' >> "$TX"
  custody_row open 2026-10-01T00:35:50Z
  custody_row abandon 2026-10-01T03:59:28Z
  run verdict_with "$HOOK" CRASH external-sigterm 143 15
  painted | grep -q '⚠ trunk-reds not resumable · tell its lead 918b909f'
  ! painted | grep -q 'work collected' || false
  assert_rows
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

@test "STRANDED bundle: no CLOSED CLEANLY, no safe to close; the answer-first line names the move and cc-lr recover; the hint is claude3" {
  lr_move_fixture
  run verdict_with "$HOOK" RECYCLE clean-exit 0 ""
  [ "$status" -eq 0 ]
  painted | grep -qF "✗ 88e2c2b1 moved next4→next3, relaunch failed" || { painted; false; }
  painted | grep -qF "▶ cc-lr recover 88e2c2b1" || { painted; false; }
  ! painted | grep -q 'lr-fleet' || { painted; false; }   # not on PATH: the pasted command did not run
  ! painted | grep -q 'CLOSED CLEANLY\|ended cleanly' || { painted; false; }
  ! painted | grep -q 'safe to close\|closing in' || { painted; false; }
  said | grep -q '(claude3)' || { said; false; }
  ! painted | grep -q 'claude4' || { painted; false; }
  ! said | grep -q 'claude4' || { said; false; }
  said | grep -q 'last close verdict: no'          # read from the FULL transcript, not the stub
  assert_rows
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
  said | grep -q 'Queued for the limit-recover poller'
  rm -rf "$T/lr/requests"; mkdir -p "$T/lr/parked"; printf '{}\n' > "$T/lr/parked/$SID.json"; : > "$T/dev/ttys099"
  : > "$HOME/.claude/logs/pane-say.jsonl"
  run verdict_with "$HOOK" RECYCLE clean-exit 0 ""
  [ ! -e "$T/lr/requests/$SID.cc-lr.json" ]
  said | grep -q 'already holds it (a parked record)'
}

@test "K6: the same move with a LIVE copy cc-find shows in another pane is MOVED, and only then handed to the closer" {
  lr_move_fixture
  printf '%s\t442\tnext3\t%s\t/x\tLIVE\tLEAD\n' "$SID" "$DST" > "$T/find.out"
  run verdict_with "$HOOK" RECYCLE clean-exit 0 ""
  painted | grep -qF "✓ 88e2c2b1 moved, runs in pane 442 · closing in 0s" || { painted; false; }
  said | grep -qF 'moved next4→next3 and runs in pane 442' || { said; false; }
  assert_rows
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

@test "the closer decides before the paint: when --dry-run refuses, a triage row replaces the countdown and no close follows" {
  rm -f "$T/cwd/scratch.txt"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s"\ncase "$*" in *--dry-run*) echo "pane 330: REFUSED — nothing says session 88e2c2b1 meant to end"; exit 1 ;; esac\necho closed\n' "$T/closed.txt" > "$CC_PANE_CLOSE_BIN"
  run verdict_with "$HOOK" RECYCLE clean-exit 0 ""
  ! painted | grep -q 'safe to close\|closing in' || { painted; false; }
  painted | grep -q "◆ can't tell if 88e2c2b1 finished" || { painted; false; }
  ! painted | grep -q 'reason unknown' || { painted; false; }
  painted | grep -q '▶ cc-husk-sweep --pane 330' || { painted; false; }
  grep -qF $'\033]2;◆ check 88e2c2b1\007' "$T/dev/ttys099" || { cat -v "$T/dev/ttys099"; false; }
  said | grep -q 'the closer keeps this pane: nothing says session 88e2c2b1 meant to end' || { said; false; }
  [ "$(cat "$T/closed.txt")" = "--pane 330 --dry-run" ] || { cat "$T/closed.txt"; false; }
  assert_rows
}

@test "CONTROL: a lone fault record with no tombstone, lock or STRANDED verdict changes nothing" {
  mkdir -p "$T/lr/faults"; export LR_STATE_DIR="$T/lr"
  printf '{"sid":"%s","first_seen":%s,"claim":{"by":"/x/.claude-secondary"}}\n' "$SID" "$(date +%s)" > "$T/lr/faults/$SID.json"
  rm -f "$T/cwd/scratch.txt"
  run verdict_with "$HOOK" RECYCLE clean-exit 0 ""
  painted | grep -q 'ended cleanly'
  [ ! -d "$T/lr/requests" ]
}

@test "every verdict class paints answer-first rows of ≤ 56 cells, with no SGR-2 and no rule" {
  local c
  for c in "CRASH external-sigterm 143 15" "RECYCLE clean-exit 0 x" "RECYCLE retired-by-desk 137 9" "CRASH killed-oom-or-force 137 9"; do
    : > "$T/dev/ttys099"
    # shellcheck disable=SC2086  # the class tuple is split on purpose
    set -- $c
    run verdict_with "$HOOK" "$1" "$2" "$3" "${4#x}"
    [ "$status" -eq 0 ]
    assert_rows || { echo "class: $c"; false; }
  done
}

# ── husk rows (husk-panes-2026-10-22 F3): a paint over a kept pane leaves a durable retry row ──────
hrow() { jq -r ".$1" "$CC_PANE_CLOSE_QUEUE_DIR/husk-330.json"; }

@test "a CRASH paint over a bare shell leaves a husk row (reason crash) — RED before F3: no row, no retry" {
  export CC_PANE_CLOSE_QUEUE_DIR="$T/q"
  run verdict_with "$HOOK" CRASH external-sigterm 143 15
  [ "$(hrow kind)" = husk ]
  [ "$(hrow reason)" = crash ]
  [ "$(hrow sid)" = "$SID" ]
  [ "$(hrow tty)" = "$T/dev/ttys099" ]
  [ "$(hrow producer)" = lead-crash-watchdog ]
}

@test "the closer refusing a clean exit leaves a husk row carrying its refusal" {
  export CC_PANE_CLOSE_QUEUE_DIR="$T/q"
  rm -f "$T/cwd/scratch.txt"
  cc_stub "$(dirname "$CC_PANE_CLOSE_BIN")" "$(basename "$CC_PANE_CLOSE_BIN")" \
    '#!/bin/bash
case "$*" in *--dry-run*) echo "pane 330: REFUSED — kitty remote control is down"; exit 1 ;; esac
echo closed'
  run verdict_with "$HOOK" RECYCLE clean-exit 0 ""
  [ "$(hrow reason)" = closer-refused ]
  [ "$(hrow refusal)" = "kitty remote control is down" ]
}

@test "CONTROL: CC_PANE_VERDICT_CLOSE=off keeps the pane on purpose — no husk row" {
  export CC_PANE_CLOSE_QUEUE_DIR="$T/q"
  CC_PANE_VERDICT_CLOSE=off run verdict_with "$HOOK" CRASH external-sigterm 143 15
  [ ! -e "$T/q/husk-330.json" ]
}

@test "F5 interim: a refusal because kitty did not answer paints done + kitty didn't answer — never ✅ closed or reason unknown (pane 42)" {
  rm -f "$T/cwd/scratch.txt"
  cc_stub "$(dirname "$CC_PANE_CLOSE_BIN")" "$(basename "$CC_PANE_CLOSE_BIN")" \
    '#!/bin/bash
case "$*" in *--dry-run*) echo "pane 330: REFUSED — kitty remote control is down and a kitty window is in native fullscreen"; exit 1 ;; esac
echo closed'
  run verdict_with "$HOOK" RECYCLE clean-exit 0 ""
  ! grep -qF '✅ closed' "$T/dev/ttys099" || { cat -v "$T/dev/ttys099"; false; }
  ! painted | grep -q 'reason unknown' || { painted; false; }
  painted | grep -qF "kitty didn't answer" || { painted; false; }
  painted | grep -qF '✓ 88e2c2b1 finished' || { painted; false; }
  grep -qF $'\033]2;✓ done 88e2c2b1\007' "$T/dev/ttys099" || { cat -v "$T/dev/ttys099"; false; }
}

# Wave C3 (husk-panes round 2, RC4): the refusal's class picks row 2. Pre-change, any line naming the
# "fullscreen guard" painted "last pane of a fullscreen window" (an identity-pin refusal included),
# and the closer's new "did not answer" wording fell to "can't tell".
@test "wave C3: a close the remote side refused is STUCK — ⌘W, won't close by itself; never 'closes when it does'" {
  rm -f "$T/cwd/scratch.txt"
  cc_stub "$(dirname "$CC_PANE_CLOSE_BIN")" "$(basename "$CC_PANE_CLOSE_BIN")" \
    '#!/bin/bash
case "$*" in *--dry-run*) echo "pane 330: REFUSED — kitty remote control refused the close (fullscreen guard, composer guard or identity pin); not falling back to SIGHUP"; exit 1 ;; esac
echo closed'
  run verdict_with "$HOOK" RECYCLE clean-exit 0 ""
  painted | grep -qF "won't close by itself" || { painted; false; }
  ! painted | grep -qF 'closes when it does' || { painted; false; }
  ! painted | grep -qF 'last pane of a fullscreen window' || { painted; false; }
}

@test "wave C3: the closer's 'window list did not answer' is TRANSIENT — kitty didn't answer, closes when it does" {
  rm -f "$T/cwd/scratch.txt"
  cc_stub "$(dirname "$CC_PANE_CLOSE_BIN")" "$(basename "$CC_PANE_CLOSE_BIN")" \
    '#!/bin/bash
case "$*" in *--dry-run*) echo "pane 330: REFUSED — its launch never started claude (exit record rc 124), but kitty'"'"'s window list did not answer (connection refused), so this pane'"'"'s window cannot be named"; exit 1 ;; esac
echo closed'
  run verdict_with "$HOOK" RECYCLE clean-exit 0 ""
  painted | grep -qF "kitty didn't answer" || { painted; false; }
  ! painted | grep -q "can't tell" || { painted; false; }
}

# ── F5: the watchdog hands its verdict to bin/cc-pane-verdict, the one writer (contract wording) ────
@test "F5: a CRASH paints RESUME through cc-pane-verdict — no cause class, no exit code on screen" {
  export CC_PANE_VERDICT_TOOL=on
  run verdict_with "$HOOK" CRASH external-sigterm 143 15
  [ "$status" -eq 0 ]
  painted | grep -qF '✗ 88e2c2b1 stopped mid-task · 1 unsaved files' || { painted; false; }
  painted | grep -qF '▶ cc-husk-sweep --resume --yes --pane 330' || { painted; false; }
  ! painted | grep -qE 'external-sigterm|143|KILLED' || { painted; false; }
  grep -qF $'\033]2;⛔ resume 88e2c2b1\007' "$T/dev/ttys099" || { cat -v "$T/dev/ttys099"; false; }
}

@test "F5: a CRASH whose custody is still open paints OWNED, naming the pane that holds it" {
  export CC_PANE_VERDICT_TOOL=on
  custody_row open 2026-10-01T00:35:50Z
  run verdict_with "$HOOK" CRASH external-sigterm 143 15
  painted | grep -qF "⏸ pane 38 is handling 88e2c2b1 · don't resume" || { painted; false; }
  ! painted | grep -q -- '--resume' || { painted; false; }
}

@test "F5: a clean exit over clean work paints DONE and is still handed to the closer" {
  export CC_PANE_VERDICT_TOOL=on
  rm -f "$T/cwd/scratch.txt"
  run verdict_with "$HOOK" RECYCLE clean-exit 0 ""
  painted | grep -qF '✓ 88e2c2b1 finished · nothing to resume' || { painted; false; }
  painted | grep -qF 'closing now · Ctrl-D closes it' || { painted; false; }
  grep -qx -- '--pane 330' "$T/closed.txt" || { cat "$T/closed.txt"; false; }
}
