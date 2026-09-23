#!/usr/bin/env bats
# lr-fire-resume.sh / reso-resume-one — terminal REPLIES queued on the pane tty during boot must not
# reach the resumed session as typed text.
#
# THE DEFECT (measured 2026-09-23, pane 405). After an in-place account switch the resumed composer
# held, literally: `^[P>|kitty(0.48.2)^[\^[[?5u^[[?62;52;c^[[<35;45;24M^[[<35;41;24M…` — kitty's
# XTVERSION reply, its keyboard-protocol reply, the DA1 reply, then dozens of SGR mouse reports.
# Process tree: claude <- cc-close-attrib <- expect <- lr-fire-resume.sh. The expect program runs a
# long pre-`interact` phase that never reads its OWN stdin (the pane tty); the TUI's startup queries
# and its mouse tracking make the terminal answer onto that tty, and `interact` then forwarded the
# whole backlog into the new pty as keystrokes.
#
# THE CURE is a bounded, non-blocking drain immediately before `interact` that drops terminal
# reports and forwards everything else. It is one block, byte-identical in both launchers.
#
# WHY THE EXECUTED ARM RUNS THE REAL PROGRAM. A grep for the drain proc would pass on a program that
# defines it and never calls it, or calls it after `interact`. So the arm below extracts the whole
# expect body (the shape of tests/lr-fire-resume-close-attrib.bats), queues the measured bytes on its
# stdin BEFORE it reaches `interact`, and reads what the spawned stub actually received on its pty.
# Red-proof: against the pre-fix subject that arm receives the reports verbatim in front of the `x`.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  FIRE="$REPO/scripts/limit-recover/lr-fire-resume.sh"
  RRO="$REPO/bin/reso-resume-one"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_ADMIT_GATE=off
  command -v expect >/dev/null || skip "expect(1) not installed"
}

# The drain span, by its marker lines. A range whose START never matches emits NOTHING, so every
# caller asserts non-empty before using it.
span() { sed -n '/^  # >>> lr-reply-drain/,/^  # <<< lr-reply-drain$/p' "$1"; }

# Run lr_reply_filter from the span of file $1 over the bytes in file $2; print the result with every
# ESC rendered as <ESC>, so an assertion can be read and a failure shows what leaked.
filt() {
  local procs="$BATS_TEST_TMPDIR/procs.exp" drv="$BATS_TEST_TMPDIR/filt.exp"
  span "$1" > "$procs"
  [ -s "$procs" ] || { echo "no lr-reply-drain span in $1"; return 1; }
  cat > "$drv" <<'EXP'
source [lindex $argv 0]
set f [open [lindex $argv 1] r]
fconfigure $f -translation binary
set s [read $f]
close $f
puts -nonewline [string map [list \x1b <ESC> \r <CR>] [lr_reply_filter $s]]
# expect exits WITHOUT flushing a partial stdout line; unflushed, every case reads empty
flush stdout
EXP
  expect -f "$drv" "$procs" "$2"
}

# The exact incident bytes, then one real keystroke and Enter.
incident_bytes() {
  # shellcheck disable=SC1003  # the trailing backslash is the ST terminator byte, not a quote escape
  printf '\033P>|kitty(0.48.2)\033\\'
  printf '\033[?5u'
  printf '\033[?62;52;c'
  local i; for i in 1 2 3 4 5 6 7 8; do printf '\033[<35;%d;24M' $((40 + i)); done
  printf 'x\r'
}

@test "the filter drops the measured reports and keeps the keystroke — in BOTH launchers" {
  incident_bytes > "$BATS_TEST_TMPDIR/in"
  local f out
  for f in "$FIRE" "$RRO"; do
    out="$(filt "$f" "$BATS_TEST_TMPDIR/in")"
    [ "$out" = "x<CR>" ] || { echo "$f -> [$out]"; false; }
  done
}

@test "real keys survive: arrows, a kitty-protocol key, text; the other reports go" {
  # ESC [ A (Up), ESC [ 97 ; 5 u (ctrl-a in the kitty protocol, NO private prefix), plain text,
  # interleaved with an OSC colour reply, a CPR, a DECRPM, a DA2, and a mouse report CUT by the read.
  # shellcheck disable=SC2016  # the $y is a literal byte of the DECRPM reply, never an expansion
  printf 'a\033[A\033]11;rgb:0000/0000/0000\033\\b\033[97;5u\033[12;40R\033[?2026;2$y\033[>1;4000;29cc\033[<35;4' \
    > "$BATS_TEST_TMPDIR/in"
  local out; out="$(filt "$FIRE" "$BATS_TEST_TMPDIR/in")"
  [ "$out" = "a<ESC>[Ab<ESC>[97;5uc" ] || { echo "got [$out]"; false; }
  # a lone trailing ESC is the head of a split report as often as a keypress, and is dropped
  printf 'q\033' > "$BATS_TEST_TMPDIR/in"
  out="$(filt "$FIRE" "$BATS_TEST_TMPDIR/in")"
  [ "$out" = "q" ] || { echo "got [$out]"; false; }
}

@test "the drain block is identical in both launchers and runs immediately before interact" {
  local a b
  a="$(span "$FIRE")"; b="$(span "$RRO")"
  [ -n "$a" ] || { echo "no lr-reply-drain span in $FIRE"; false; }
  [ -n "$b" ] || { echo "no lr-reply-drain span in $RRO"; false; }
  [ "$a" = "$b" ] || { diff <(printf '%s\n' "$a") <(printf '%s\n' "$b"); false; }
  # The call site: the only `interact` in each file, preceded by the drain call and its send.
  local f
  for f in "$FIRE" "$RRO"; do
    [ "$(grep -c '^  interact$' "$f")" = 1 ] || { echo "$f: expected exactly one interact"; false; }
    # shellcheck disable=SC2016  # the expected text is literal Tcl source, never a shell expansion
    [ "$(grep -B2 '^  interact$' "$f" | head -2 | tr -d '\n')" = \
      '  set lr_keep [lr_drain_user]  if {$lr_keep ne ""} { send -- $lr_keep }' ] \
      || { echo "$f: the drain call does not immediately precede interact"; grep -B3 '^  interact$' "$f"; false; }
  done
}

@test "EXECUTED: reports queued before interact never reach the spawned session; the keystroke does" {
  EXP="$BATS_TEST_TMPDIR/resume.exp"
  sed -n "/^expect -c '\$/,/^' ||/p" "$FIRE" | sed '1d;$d' > "$EXP"
  [ -s "$EXP" ] || { echo "extraction of the expect body from $FIRE failed"; false; }
  grep -q '^  interact$' "$EXP"

  # The stub stands in for claude: it records every line its pty delivers.
  STUB="$BATS_TEST_TMPDIR/stub"
  cat > "$STUB" <<'SH'
#!/bin/bash
echo "BOOTED"
while IFS= read -r line; do printf '%s\n' "$line" >> "$LR_TEST_GOT"; done
SH
  chmod +x "$STUB"
  export LR_TEST_GOT="$BATS_TEST_TMPDIR/got"

  # No prompt, and every answer pattern pinned to a string the stub never prints: the main loop
  # settles on its quiet arm after 1 s, types nothing, and falls through to `interact` — the
  # subject. Everything queued on stdin before that moment is the boot-time backlog.
  export LR_CFG="$BATS_TEST_TMPDIR/cfg" LR_BIN="$STUB" LR_MODEL=m LR_EFFORT=high \
         LR_SID="00000000-0000-0000-0000-000000000000" LR_PROMPT="" LR_ASIS=1 LR_WRAP="" LR_QUIET_S=1
  local never='ZZZ-NEVER-MATCHES-ZZZ'
  export LR_RE_MENU="$never" LR_RE_ASIS_STRONG="$never" LR_RE_ASIS="$never" \
         LR_RE_TRUST="$never" LR_RE_TRUST_RB="$never" LR_RE_FS="$never" LR_RE_FS_RB="$never" \
         LR_RE_OVERAGE="$never" LR_RE_READY="$never"

  incident_bytes > "$BATS_TEST_TMPDIR/in"
  # stdin = the bytes, queued at once, then held OPEN until the stub has recorded a line (bounded
  # 10 s), so `interact` is still running when the line arrives and ends on EOF afterwards.
  feed() {
    cat "$BATS_TEST_TMPDIR/in"
    local i=0
    while [ ! -s "$LR_TEST_GOT" ] && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
    sleep 0.3
  }
  local rc=0
  feed | timeout 60 expect -f "$EXP" > "$BATS_TEST_TMPDIR/out" 2>&1 || rc=$?
  [ "$rc" -ne 124 ] || { echo "the expect program did not finish"; false; }
  [ -s "$LR_TEST_GOT" ] || { echo "the stub received nothing at all"; cat "$BATS_TEST_TMPDIR/out"; false; }

  local got; got="$(tr '\033' '~' < "$LR_TEST_GOT")"
  [ "$got" = "x" ] || { echo "the spawned session received [$got] (ESC shown as ~), expected [x]"; false; }
}
