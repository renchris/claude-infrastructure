#!/usr/bin/env bats
# THE NON-LOSSINESS PROOF FOR /compact-memory — scripts/memory-dropped-token-audit.py.
#
# THE DEFECT THIS AUDIT CLOSES. /compact-memory's prescribed audit re-runs over the lines that
# SURVIVE a pass. That direction cannot see a fact the rewrite DELETED: a token that appears in no
# finished line is unreachable from the finished file, so the command shipped with NO check able to
# prove a pass non-lossy in the one direction where a pass is irreversible.
#
# WHAT EACH ARM PINS, and the pairs are what make them mean anything:
#   1+2  A dropped code span unbacked by the topic file BLOCKS — and the SAME span, backed, is
#        clean. Without arm 2, arm 1 is equally consistent with a gate that always fires.
#   3+4  CLASS POLARITY, two-sided: an ordinary content word is ADVISORY and exits 0 (the reso
#        2026-08-07 pass produced 35 of them, every one an English connective — a gate that
#        blocked on those would have been switched off on its first run), and --strict-words
#        raises the same token to blocking. A one-sided arm would pass against a hardcoded class.
#   5+6  SHA and number are hard classes and BLOCK, so arm 3's leniency is scoped to words alone.
#   7+8  THE ROTOR ARM (trunk 65edba440, cc-memory-rotate leaves a pointer where a demotion used
#        to leave nothing): an entry that left the index blocks when NOTHING names it and clears
#        when the archive tier does. Un-paired, this arm would fire on every legitimate rotation —
#        measured live on reso, the 2026-08-07 prototype alarms on 35 rotor-demoted entries.
#   9a+9b THE HARVEST ARMS, both copied from trunk 809d308eb rather than re-invented: a title
#        quoting a regex keeps its link (`[^]]*` stops at that `]` and drops the line from the
#        harvest entirely) and a BOLD bullet is an entry (`^- \[` under-reads it). 9c pins the
#        stated RESIDUAL of trunk's last-`(….md)` rule — a hook carrying its own markdown link
#        misresolves, and must do so LOUDLY as a dangling block, never as a quiet pass.
#   10+11 EXIT 2 IS A NON-VERDICT, NOT A PASS: an unparseable link-shaped bullet and a missing
#        input file both refuse to render a verdict rather than exonerating the tree. An under-read
#        that exited 0 would acquit precisely the entries it failed to parse.
#   12   A dangling link blocks — the entry survived, its topic file did not.
#   13   CONTROL REPLAY against the real 2026-08-07 reso artifact when this box still has it.
#
# HERMETIC: fixture $HOME (rule 1 of test-hermeticity-lint), fixture memory dir, no live layer, no
# network. Every file the audit reads is one this suite wrote — except arm 12, which is explicitly
# guarded and skips with its reason rather than silently passing.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  AUDIT="$REPO/scripts/memory-dropped-token-audit.py"
  MEM="$BATS_TEST_TMPDIR/memory"; mkdir -p "$MEM"
  OLD="$BATS_TEST_TMPDIR/old.md"
  NEW="$MEM/MEMORY.md"
}

# topic <name> <body...> — a linked topic file.
topic() { local f="$MEM/$1"; shift; printf '%s\n' "$@" > "$f"; }
# idx <file> <line...> — an index surface.
idx() { local f="$1"; shift; { printf '# Memory\n'; printf '%s\n' "$@"; } > "$f"; }

run_audit() { run python3 "$AUDIT" --old "$OLD" --new "$NEW" "$@"; }

# $output assertions as ordinary commands: bash exempts `[[ ]]` from errexit, so a non-final
# `[[ "$output" == *x* ]]` is evaluated and DISCARDED and the test passes on a false assertion
# (scripts/bats-assert-liveness.py). grep is a simple command and stays live in every position.
has_out()   { printf '%s\n' "$output" | grep -qF -- "$1"; }
lacks_out() { ! printf '%s\n' "$output" | grep -qF -- "$1"; }

@test "1 a dropped code span with no backing in the topic file BLOCKS" {
  topic t.md "the rule body says nothing about that flag"
  idx "$OLD" '- [T](t.md) — the rule, driven by `--drain-oversized`'
  idx "$NEW" '- [T](t.md) — the rule'
  run_audit
  [ "$status" -eq 1 ]
  has_out 'verdict=lossy'
  has_out '[code] --drain-oversized'
}

@test "2 POSITIVE CONTROL: the same span, backed by the topic file, is clean" {
  topic t.md "the rule body explains --drain-oversized in full"
  idx "$OLD" '- [T](t.md) — the rule, driven by `--drain-oversized`'
  idx "$NEW" '- [T](t.md) — the rule'
  run_audit
  [ "$status" -eq 0 ]
  has_out 'verdict=clean'
  lacks_out 'drain-oversized'
}

@test "3 CLASS POLARITY a: an unbacked ordinary content word is ADVISORY and exits 0" {
  topic t.md "the rule body is about something else entirely"
  idx "$OLD" '- [T](t.md) — the rule about chandeliers'
  idx "$NEW" '- [T](t.md) — the rule'
  run_audit
  [ "$status" -eq 0 ]
  has_out 'verdict=clean'
  has_out 'ADVISORY'
  has_out '[word] chandeliers'
}

@test "4 CLASS POLARITY b: --strict-words raises that SAME token to blocking" {
  topic t.md "the rule body is about something else entirely"
  idx "$OLD" '- [T](t.md) — the rule about chandeliers'
  idx "$NEW" '- [T](t.md) — the rule'
  run_audit --strict-words
  [ "$status" -eq 1 ]
  has_out 'verdict=lossy'
  has_out '[word] chandeliers'
}

@test "5 a dropped landed SHA with no backing BLOCKS" {
  topic t.md "the rule body names no commit at all"
  idx "$OLD" '- [T](t.md) — the rule, landed 828816d'
  idx "$NEW" '- [T](t.md) — the rule'
  run_audit
  [ "$status" -eq 1 ]
  has_out '[sha] 828816d'
}

@test "6 a dropped measurement with no backing BLOCKS" {
  topic t.md "the rule body carries no figure"
  idx "$OLD" '- [T](t.md) — the rule, measured 23671 bytes'
  idx "$NEW" '- [T](t.md) — the rule'
  run_audit
  [ "$status" -eq 1 ]
  has_out '[num] 23671'
}

@test "7 THE ROTOR ARM a: an entry that left the index with NOTHING naming it BLOCKS" {
  topic gone.md "a live rule"
  topic t.md "kept"
  idx "$OLD" '- [G](gone.md) — the demoted rule' '- [T](t.md) — kept'
  idx "$NEW" '- [T](t.md) — kept'
  run_audit
  [ "$status" -eq 1 ]
  has_out 'entry-removed'
  has_out 'gone.md'
}

@test "8 THE ROTOR ARM b: the same entry clears once the archive tier NAMES it" {
  topic gone.md "a live rule"
  topic t.md "kept"
  printf '%s\n' '- demoted 2026-09-06 from MEMORY.md; the rule is unchanged at `gone.md`' \
    > "$MEM/MEMORY-ARCHIVE.md"
  idx "$OLD" '- [G](gone.md) — the demoted rule' '- [T](t.md) — kept'
  idx "$NEW" '- [T](t.md) — kept'
  run_audit
  [ "$status" -eq 0 ]
  has_out 'verdict=clean'
}

@test "9a THE HARVEST ARM: a title quoting a regex keeps its link — the [^]]* regression" {
  topic t.md "the rule body names no commit"
  idx "$OLD" '- [Tests +[0-9]+ passed](t.md) — the rule, landed 828816d'
  idx "$NEW" '- [Tests +[0-9]+ passed](t.md) — the rule'
  run_audit
  [ "$status" -eq 1 ]
  has_out 't.md  [sha] 828816d'
}

@test "9b BOLD BULLETS are entries too, and are not under-read" {
  topic t.md "the rule body names no commit"
  idx "$OLD" '- **[T](t.md)** — the rule, landed 828816d'
  idx "$NEW" '- **[T](t.md)** — the rule'
  run_audit
  [ "$status" -eq 1 ]
  has_out 't.md  [sha] 828816d'
}

@test "9c RESIDUAL: a hook carrying its own ](x.md) link fails LOUDLY, never silently" {
  topic t.md "kept"
  idx "$OLD" '- [T](t.md) — the rule, see [x](other.md), landed 828816d'
  idx "$NEW" '- [T](t.md) — the rule, see [x](other.md)'
  run_audit
  [ "$status" -eq 1 ]
  has_out 'dangling'
}

@test "10 NON-VERDICT a: a link-shaped bullet the harvest cannot parse exits 2, never 0 or 1" {
  topic t.md "kept"
  idx "$OLD" '- [T](t.md) — kept' '- [Broken](no-extension) — a link-shaped bullet'
  idx "$NEW" '- [T](t.md) — kept'
  run_audit
  [ "$status" -eq 2 ]
  has_out 'verdict=non-verdict'
}

@test "11 NON-VERDICT b: a missing input file exits 2 rather than exonerating the tree" {
  topic t.md "kept"
  idx "$NEW" '- [T](t.md) — kept'
  run python3 "$AUDIT" --old "$BATS_TEST_TMPDIR/nope.md" --new "$NEW"
  [ "$status" -eq 2 ]
  has_out 'verdict=non-verdict'
}

@test "12 a dangling link — the entry survived but its topic file did not — BLOCKS" {
  idx "$OLD" '- [T](t.md) — the rule, driven by `--drain-oversized`'
  idx "$NEW" '- [T](t.md) — the rule'
  run_audit
  [ "$status" -eq 1 ]
  has_out 'dangling'
}

@test "13 CONTROL REPLAY: the real 2026-08-07 reso pass reads clean end-to-end" {
  R="$HOME/../../../.claude/projects/-Users-chrisren-Development-reso-management-app/memory"
  R="/Users/chrisren/.claude/projects/-Users-chrisren-Development-reso-management-app/memory"
  [ -f "$R/archive/MEMORY_INDEX_PRE-COMPACT_2026-08-07.md" ] || \
    skip "the 2026-08-07 reso artifact is machine-local and untracked; absent on this box"
  run python3 "$AUDIT" --old "$R/archive/MEMORY_INDEX_PRE-COMPACT_2026-08-07.md" --new "$R/MEMORY.md"
  [ "$status" -eq 0 ]
  has_out 'verdict=clean'
}

