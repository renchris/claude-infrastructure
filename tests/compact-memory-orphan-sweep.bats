#!/usr/bin/env bats
bats_require_minimum_version 1.5.0   # `run -127` below needs the flag form
# The E3 exclusion of /compact-memory's step-4 orphan sweep — backlog 87822050d5e5.
#
# THE DEFECT. The documented sweep excluded a topic file from the ORPHAN list by asking one grep
# about three instruction paths at once:
#
#     grep -rqF "${f%.md}" "$P/CLAUDE.md" "$P/.claude/CLAUDE.md" "$P/.claude/rules" 2>/dev/null \
#       || echo "ORPHAN $f"
#
# An unreadable operand makes grep exit 2 EVEN WHEN ANOTHER OPERAND MATCHED, and `||` cannot tell
# 2 from 1 — so on any project missing one of those paths, EVERY residual file printed as an
# orphan. Measured on reso 2026-08-05 (no .claude/CLAUDE.md): 13 ORPHANs from the documented form,
# 0 from the corrected one. The impact is the failure the command's own text warns about two
# paragraphs earlier — a pass trusting the output re-indexes correctly-unindexed files and
# re-triggers the rotation it just performed.
#
# WHY IT SURVIVED, and why this suite asserts TWO grep behaviours: the bug is environment-
# dependent. Measured 2026-08-12 on the same fixture, match present + two operands missing —
# /usr/bin/grep (BSD) returns 0, because a match outranks the missing-operand error, so the snippet
# looks correct to a script; the bare `grep` an interactive session resolves returns 2, so the
# snippet is broken for the reader pasting it, which is who runs a /command (memory:
# interactive-grep-is-ugrep-not-usr-bin-grep). The fix must hold under both, so both are asserted:
# /usr/bin/grep directly, and the error-rc behaviour via the `strict_grep` stub below (see its
# comment for why a stub rather than the live interactive binary).
#
# NOT A DOC TEST. These cases execute the two E3 forms as shell, against a fixture with a genuinely
# missing instruction path. The OLD form is kept deliberately as the control: a case that only ever
# runs the fixed form cannot show that the fixture reaches the defect at all, and would pass
# against the broken snippet too (memory: control-must-replay-the-real-artifact).

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  P="$BATS_TEST_TMPDIR/proj"; mkdir -p "$P"
  # The fixture's whole point: CLAUDE.md exists AND cites the stem; the other two E3 paths do NOT
  # exist. That is the reso shape, and it is the shape the one-shot grep misreads.
  printf 'the always-loaded instruction file cites topic-alpha by stem\n' > "$P/CLAUDE.md"
  [ ! -e "$P/.claude/CLAUDE.md" ]
  [ ! -e "$P/.claude/rules" ]
  STEM="topic-alpha"
}

# The DOCUMENTED-BEFORE form — the artifact under indictment, replayed verbatim.
e3_old() { # $1=grep-binary $2=stem → prints ORPHAN when it thinks the stem is uncited
  "$1" -rqF "$2" "$P/CLAUDE.md" "$P/.claude/CLAUDE.md" "$P/.claude/rules" 2>/dev/null \
    || echo "ORPHAN $2.md"
}

# The CORRECTED form now in commands/compact-memory.md — skip operands that do not exist.
e3_new() { # $1=grep-binary $2=stem
  local hit=0 c
  for c in "$P/CLAUDE.md" "$P/.claude/CLAUDE.md" "$P/.claude/rules"; do
    [ -e "$c" ] || continue
    "$1" -rqF "$2" "$c" 2>/dev/null && { hit=1; break; }
  done
  [ "$hit" = 1 ] || echo "ORPHAN $2.md"
}

# A grep that reports an unreadable operand as rc 2 EVEN WHEN ANOTHER OPERAND MATCHED — the
# POSIX/GNU behaviour, and the behaviour measured 2026-08-12 from the bare `grep` an interactive
# session on this box resolves (a shell function ahead of /usr/bin/grep in `type -a`).
#
# IT IS A STUB ON PURPOSE, and this is the load-bearing design choice in the file. The suite must
# pin the CONTRACT — "if grep returns an error rc, the one-shot form misreports" — not one
# machine's binary. Resolving the live interactive grep was tried first and cannot work from a bats
# body: `command -v grep` returns the FUNCTION NAME, not a path, so the case silently fell through
# to /usr/bin/grep and passed vacuously against the very defect it names. Hardcoding the shell
# snapshot's path would pin a file that is regenerated per session. The stub delegates the actual
# matching to /usr/bin/grep and only supplies the error-rc discipline, so it cannot fake a match.
strict_grep() {
  local sg="$BATS_TEST_TMPDIR/strict-grep"
  [ -x "$sg" ] && { printf '%s' "$sg"; return 0; }
  cat > "$sg" <<'SH'
#!/usr/bin/env bash
# POSIX-conforming grep wrapper: rc 2 if ANY operand is unreadable, whatever the match said.
err=0; args=(); files=()
for a in "$@"; do case "$a" in -*) args+=("$a") ;; *) files+=("$a") ;; esac; done
for f in "${files[@]:1}"; do [ -e "$f" ] || err=1; done
/usr/bin/grep "${args[@]}" "${files[@]}" >/dev/null 2>&1; m=$?
[ "$err" = 1 ] && exit 2
exit $m
SH
  chmod +x "$sg"; printf '%s' "$sg"
}

@test "CONTROL: the pre-fix E3 form reports a FALSE orphan for a stem its CLAUDE.md does cite" {
  # If this ever stops failing, the fixture no longer reaches the defect and every case below is
  # vacuous. It is the reso incident in miniature.
  g="$(strict_grep)"
  run e3_old "$g" "$STEM"
  [ "$status" -eq 0 ]
  [ "$output" = "ORPHAN topic-alpha.md" ] || { echo "expected a false orphan, got: [$output]"; false; }
}

@test "the corrected E3 form reports NO orphan on the same fixture, same grep" {
  g="$(strict_grep)"
  run e3_new "$g" "$STEM"
  [ "$status" -eq 0 ]
  [ -z "$output" ] || { echo "corrected form still reported: [$output]"; false; }
}

@test "the corrected form is also correct under /usr/bin/grep, where the old form happened to work" {
  # The half that makes this a fix and not a swap: BSD grep returns 0 here (a match outranks the
  # missing-operand error), so the OLD form was already correct under it. The new form must not
  # regress that.
  run e3_old /usr/bin/grep "$STEM"
  [ "$status" -eq 0 ]
  [ -z "$output" ] || { echo "premise broken: /usr/bin/grep was expected to be the benign case"; false; }
  run e3_new /usr/bin/grep "$STEM"
  [ "$status" -eq 0 ]
  [ -z "$output" ] || { echo "corrected form regressed the benign case: [$output]"; false; }
}

@test "the corrected form still FINDS a genuine orphan — it did not just stop reporting" {
  # The alarm-polarity control. A fix that silences E3 entirely would pass all three cases above
  # and delete the sweep's whole purpose (memory: alarm-polarity-and-attention-budget).
  run e3_new /usr/bin/grep "never-mentioned-anywhere"
  [ "$status" -eq 0 ]
  [ "$output" = "ORPHAN never-mentioned-anywhere.md" ] || { echo "the sweep went silent: [$output]"; false; }
  g="$(strict_grep)"
  run e3_new "$g" "never-mentioned-anywhere"
  [ "$status" -eq 0 ]
  [ "$output" = "ORPHAN never-mentioned-anywhere.md" ] || { echo "the sweep went silent: [$output]"; false; }
}

@test "ALL THREE paths present: both forms agree, so the defect really is the missing operand" {
  # Isolates the variable. With nothing missing, the old form has no error to conflate and must
  # match the new one — which is what makes 'the missing operand' the named cause rather than a
  # story about grep in general.
  mkdir -p "$P/.claude/rules"; printf 'nothing here\n' > "$P/.claude/CLAUDE.md"
  g="$(strict_grep)"
  run e3_old "$g" "$STEM"
  [ "$status" -eq 0 ]
  [ -z "$output" ] || { echo "old form still wrong with all paths present: [$output]"; false; }
  run e3_new "$g" "$STEM"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "the snippet's own block is bash-only: shopt is not a zsh builtin" {
  # The secondary defect on the same row. The block opens with `shopt -s nullglob`; a reader who
  # pastes it into their interactive zsh gets 'command not found' and the block has only ever
  # appeared to work because the globs happened to match.
  run -127 zsh -c 'shopt -s nullglob'
  [ "$status" -eq 127 ]
  run bash -c 'shopt -s nullglob'
  [ "$status" -eq 0 ]
}
