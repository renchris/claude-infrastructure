#!/usr/bin/env bats
# tests-dir-lint-memo.bats — the per-file memo in the land-gate ratchet lints that judge tests/*.bats one
# suite at a time (follow-on 3 of the cloud-lane redesign: memoize the arms, highest runtime first).
# moving-ref-control-lint is the first; the siblings of the same shape append their cases below.
#
# SAME CONTRACT AS gitid-file-memo.bats and pipefail-file-memo.bats: --selftest owns the DETECTOR (and
# runs memo-OFF, so it always exercises it); this suite owns the MEMO — it carries, a carried run says
# exactly what an unmemoized run says, and every component of its key INVALIDATES when it moves. A memo
# keyed on the wrong thing is strictly worse than no memo: it hands out a green nobody earned.
#
# THE CORPUS IS FULLY OURS, so every count is exact: three clean suites and one that is a finding for the
# lint under test. A warm run therefore carries 3 and re-proves 1 — the finding, which is never cached.
#
# 🚨 Each lint's POSITIVE CONTROL comes first: the memo refuses on a dirty worktree, so a suite that
# silently ran memo-OFF would pass every other case while asserting nothing.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"          # hermeticity: never the operator's live ~
  mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  CORPUS="$BATS_TEST_TMPDIR/corpus"
}

# mkcorpus <lint basename> <env prefix> <a line that makes a suite a FINDING for that lint>
mkcorpus() {
  LINT_BASE="$1"; P="$2"
  mkdir -p "$CORPUS/scripts/lib" "$CORPUS/tests"
  # The library travels with the lint: it is sourced from the lint's own ROOT, so a copy without it is
  # a lint whose memo is fail-closed OFF — correct, and silent. The positive control catches that.
  cp "$REPO/scripts/$1" "$CORPUS/scripts/"
  cp "$REPO/scripts/lib/gate-memo.sh" "$CORPUS/scripts/lib/"
  for n in 1 2 3; do printf '@test "clean %s" {\n  true\n}\n' "$n" > "$CORPUS/tests/clean$n.bats"; done
  printf '@test "finding" {\n  %s\n}\n' "$3" > "$CORPUS/tests/zz-hit.bats"
  ( cd "$CORPUS" && git init -q . && git add -A && git -c user.email=t@e.x -c user.name=t commit -qm init )
}
commit() { ( cd "$CORPUS" && git add -A && git -c user.email=t@e.x -c user.name=t commit -qm "$1" ); }

# The invocation ship-land's own_run makes: the own-set EXPORTED (here to a name nothing matches, so the
# finding is advisory and the rc is not the subject), the suites dir given relative to the repo root.
run_lint() {  # [extra VAR=value …] → combined output
  ( cd "$CORPUS" && env "CC_${P}_OWN=x" "$@" bash "scripts/$LINT_BASE" tests 2>&1 ) || true
}

# An ABSENT attestation answers -1, never the empty string: `[ "" -eq 1 ]` aborts the test with a usage
# error, which reads as a red for the wrong reason and hides which assertion failed.
carried() {
  local v; v="$(printf '%s\n' "$1" | sed -n 's/.*per-file memo — \([0-9]*\) verdict(s) carried.*/\1/p' | tail -1)"
  printf '%s' "${v:--1}"
}
proven() {
  local v; v="$(printf '%s\n' "$1" | sed -n 's/.*carried, \([0-9]*\) proven fresh.*/\1/p' | tail -1)"
  printf '%s' "${v:--1}"
}
store_entries() { find "$CORPUS/.git/ship-land-memo" -type f 2>/dev/null | grep -c . || true; }

# A PATH shim whose bytes are FIXED for the life of a test (so it keys exactly one checker, where it is in
# the key at all); whether it fails is decided by a flag FILE, which is outside every key by construction.
shim() {  # $1=tool · $2=case pattern over "$*" that makes it fail while the flag exists · $3=exit code
  SHIM="$BATS_TEST_TMPDIR/shim"; mkdir -p "$SHIM"
  export MEMO_SHIM_FLAG="$BATS_TEST_TMPDIR/fail.flag"
  # shellcheck disable=SC2016  # the shim's own "$MEMO_SHIM_FLAG" / "$*" / "$@" must reach it LITERALLY
  { printf '#!/bin/bash\n'
    printf 'if [ -e "$MEMO_SHIM_FLAG" ]; then case "$*" in %s) exit %s ;; esac; fi\n' "$2" "$3"
    printf 'exec /usr/bin/%s "$@"\n' "$1"
  } > "$SHIM/$1"
  chmod +x "$SHIM/$1"
}

# ── moving-ref-control-lint ──────────────────────────────────────────────────────────────────────────
# Its finding: a pre-fix control replayed from a ref that ADVANCES. Carried here inside single quotes,
# which the detector strips, so this suite is not itself a finding.
# shellcheck disable=SC2016  # the fixture LINE is data written into a corpus suite, never expanded here
mr() { mkcorpus moving-ref-control-lint.sh MOVINGREF 'run git -C "$REPO" show main:scripts/x.sh'; }

@test "moving-ref POSITIVE CONTROL: the memo arms, and carries every clean suite" {
  mr
  first="$(run_lint)"
  [[ "$first" == *"per-file memo"* ]] || { echo "MEMO NEVER ARMED — every moving-ref case is vacuous"; echo "$first"; false; }
  [ "$(carried "$first")" -eq 0 ]
  [ "$(proven "$first")" -eq 4 ]
  second="$(run_lint)"
  [ "$(carried "$second")" -eq 3 ]
  [ "$(proven "$second")" -eq 1 ]
}

@test "moving-ref: a carried run says exactly what an unmemoized run says, and re-reports the finding" {
  mr
  run_lint >/dev/null
  warm="$(run_lint)"
  [ "$(carried "$warm")" -eq 3 ]
  cold="$(run_lint CC_MOVINGREF_MEMO=off)"
  [ "$(printf '%s\n' "$warm" | grep -v 'per-file memo')" = "$(printf '%s\n' "$cold" | grep -v 'per-file memo')" ]
  [[ "$warm" == *"zz-hit.bats"* ]]
}

@test "moving-ref: editing one suite re-proves THAT suite and no other" {
  mr
  run_lint >/dev/null
  printf '# bytes that change no verdict\n' >> "$CORPUS/tests/clean2.bats"
  commit edit
  after="$(run_lint)"
  [ "$(proven "$after")" -eq 2 ]
  [ "$(carried "$after")" -eq 2 ]
}

@test "moving-ref KEY: the lint's own blob invalidates every carried verdict" {
  mr
  run_lint >/dev/null
  printf '\n# read-set change\n' >> "$CORPUS/scripts/moving-ref-control-lint.sh"
  commit lint-edit
  [ "$(carried "$(run_lint)")" -eq 0 ]
}

@test "moving-ref KEY: the allowlist is in the key BY VALUE — no byte of any file moves" {
  mr
  run_lint >/dev/null
  [ "$(carried "$(run_lint CC_MOVINGREF_ALLOWLIST=unrelated.bats)")" -eq 0 ]
}

@test "moving-ref KEY: a different AWK binary invalidates — and then re-earns" {
  mr
  run_lint >/dev/null
  shim awk 'NEVER-MATCHES' 3
  [ "$(carried "$(run_lint PATH="$SHIM:$PATH")")" -eq 0 ]
  [ "$(carried "$(run_lint PATH="$SHIM:$PATH")")" -eq 3 ]
}

@test "moving-ref: an AWK that could not run for a clean suite is never banked" {
  mr
  shim awk '*tests/clean1.bats*' 3
  : > "$MEMO_SHIM_FLAG"
  run_lint PATH="$SHIM:$PATH" >/dev/null
  rm -f "$MEMO_SHIM_FLAG"
  b="$(run_lint PATH="$SHIM:$PATH")"
  [ "$(proven "$b")" -eq 2 ]                   # clean1 + the finding
  [ "$(carried "$b")" -eq 2 ]
}

@test "moving-ref: an allowlisted CLEAN suite is never banked, even when the allowlist probe cannot run" {
  # The RATCHET line ("fixed but still grandfathered") is how the list shrinks, and it must print on every
  # run. in_allowlist is a forked grep; if it fails, the suite falls through to the clean branch — and
  # without the builtin guard at the record site that fall-through would be BANKED, silencing the line
  # for as long as the key holds. grep is not in this lint's key, so the shim cannot hide the bug.
  mr
  shim grep '*-xF*' 2
  : > "$MEMO_SHIM_FLAG"
  run_lint PATH="$SHIM:$PATH" CC_MOVINGREF_ALLOWLIST=clean1.bats >/dev/null
  rm -f "$MEMO_SHIM_FLAG"
  out="$(run_lint PATH="$SHIM:$PATH" CC_MOVINGREF_ALLOWLIST=clean1.bats)"
  [[ "$out" == *"clean1.bats"* ]]
}

@test "moving-ref: --selftest runs memo-OFF and writes nothing to the store" {
  mr
  run_lint >/dev/null
  before="$(store_entries)"
  ( cd "$CORPUS" && bash scripts/moving-ref-control-lint.sh --selftest >/dev/null 2>&1 ) || true
  [ "$(store_entries)" -eq "$before" ]
}

@test "moving-ref: a dirty worktree, and CC_MOVINGREF_MEMO=off, each disarm the memo" {
  mr
  [[ "$(run_lint CC_MOVINGREF_MEMO=off)" != *"per-file memo"* ]] || false
  printf '# uncommitted\n' >> "$CORPUS/tests/clean1.bats"
  [[ "$(run_lint)" != *"per-file memo"* ]]
}

# ── test-afunix-path-lint ────────────────────────────────────────────────────────────────────────────
# Its finding: an AF_UNIX socket bound to an ABSOLUTE path. The detector reads RAW lines — no quote
# stripping — so this suite may never carry the two tokens literally near each other; the fixture line is
# assembled from split words, and the lint judging THIS file sees neither token.
af() {
  local u="AF""_UNIX" b=".bi""nd("
  mkcorpus test-afunix-path-lint.sh AFUNIX "python3 -c \"import socket; s=socket.socket(socket.${u}); s${b}'/tmp/x.sock')\""
}

@test "afunix POSITIVE CONTROL: the memo arms, and carries every clean suite" {
  af
  first="$(run_lint)"
  [[ "$first" == *"per-file memo"* ]] || { echo "MEMO NEVER ARMED — every afunix case is vacuous"; echo "$first"; false; }
  [ "$(carried "$first")" -eq 0 ]
  [ "$(proven "$first")" -eq 4 ]
  second="$(run_lint)"
  [ "$(carried "$second")" -eq 3 ]
  [ "$(proven "$second")" -eq 1 ]
}

@test "afunix: a carried run says exactly what an unmemoized run says, and re-reports the finding" {
  af
  run_lint >/dev/null
  warm="$(run_lint)"
  [ "$(carried "$warm")" -eq 3 ]
  cold="$(run_lint CC_AFUNIX_MEMO=off)"
  [ "$(printf '%s\n' "$warm" | grep -v 'per-file memo')" = "$(printf '%s\n' "$cold" | grep -v 'per-file memo')" ]
  [[ "$warm" == *"zz-hit.bats"* ]]
}

@test "afunix: editing one suite re-proves THAT suite and no other" {
  af
  run_lint >/dev/null
  printf '# bytes that change no verdict\n' >> "$CORPUS/tests/clean2.bats"
  commit edit
  after="$(run_lint)"
  [ "$(proven "$after")" -eq 2 ]
  [ "$(carried "$after")" -eq 2 ]
}

@test "afunix KEY: the lint's own blob invalidates every carried verdict" {
  af
  run_lint >/dev/null
  printf '\n# read-set change\n' >> "$CORPUS/scripts/test-afunix-path-lint.sh"
  commit lint-edit
  [ "$(carried "$(run_lint)")" -eq 0 ]
}

@test "afunix KEY: the allowlist is in the key BY VALUE — no byte of any file moves" {
  af
  run_lint >/dev/null
  [ "$(carried "$(run_lint CC_AFUNIX_ALLOWLIST=unrelated.bats)")" -eq 0 ]
}

@test "afunix KEY: the WINDOW is in the key — it decides what counts as AF_UNIX in scope" {
  af
  run_lint >/dev/null
  [ "$(carried "$(run_lint CC_AFUNIX_WINDOW=1)")" -eq 0 ]
}

@test "afunix KEY: a different AWK binary invalidates — and then re-earns" {
  af
  run_lint >/dev/null
  shim awk 'NEVER-MATCHES' 3
  [ "$(carried "$(run_lint PATH="$SHIM:$PATH")")" -eq 0 ]
  [ "$(carried "$(run_lint PATH="$SHIM:$PATH")")" -eq 3 ]
}

@test "afunix: an AWK that could not run for a clean suite is never banked" {
  af
  shim awk '*tests/clean1.bats*' 3
  : > "$MEMO_SHIM_FLAG"
  run_lint PATH="$SHIM:$PATH" >/dev/null
  rm -f "$MEMO_SHIM_FLAG"
  b="$(run_lint PATH="$SHIM:$PATH")"
  [ "$(proven "$b")" -eq 2 ]
  [ "$(carried "$b")" -eq 2 ]
}

@test "afunix: an allowlisted CLEAN suite is never banked, even when the allowlist probe cannot run" {
  af
  shim grep '*-xF*' 2
  : > "$MEMO_SHIM_FLAG"
  run_lint PATH="$SHIM:$PATH" CC_AFUNIX_ALLOWLIST=clean1.bats >/dev/null
  rm -f "$MEMO_SHIM_FLAG"
  out="$(run_lint PATH="$SHIM:$PATH" CC_AFUNIX_ALLOWLIST=clean1.bats)"
  [[ "$out" == *"clean1.bats"* ]]
}

@test "afunix: --selftest runs memo-OFF and writes nothing to the store" {
  af
  run_lint >/dev/null
  before="$(store_entries)"
  ( cd "$CORPUS" && bash scripts/test-afunix-path-lint.sh --selftest >/dev/null 2>&1 ) || true
  [ "$(store_entries)" -eq "$before" ]
}

@test "afunix: a dirty worktree, and CC_AFUNIX_MEMO=off, each disarm the memo" {
  af
  [[ "$(run_lint CC_AFUNIX_MEMO=off)" != *"per-file memo"* ]] || false
  printf '# uncommitted\n' >> "$CORPUS/tests/clean1.bats"
  [[ "$(run_lint)" != *"per-file memo"* ]]
}

# ── test-walltime-lint ───────────────────────────────────────────────────────────────────────────────
# Its finding: a FUTURE absolute date inside the horizon. Built with arithmetic, so this suite — which the
# lint also judges — never carries a literal future date of its own.
wt() {
  local y; y=$(( $(date -u +%Y) + 2 ))
  mkcorpus test-walltime-lint.sh WALLTIME "run subject --until \"${y}-01-15\""
}

@test "walltime POSITIVE CONTROL: the memo arms, and carries every clean suite" {
  wt
  first="$(run_lint)"
  [[ "$first" == *"per-file memo"* ]] || { echo "MEMO NEVER ARMED — every walltime case is vacuous"; echo "$first"; false; }
  [ "$(carried "$first")" -eq 0 ]
  [ "$(proven "$first")" -eq 4 ]
  second="$(run_lint)"
  [ "$(carried "$second")" -eq 3 ]
  [ "$(proven "$second")" -eq 1 ]
}

@test "walltime: a carried run says exactly what an unmemoized run says, and re-reports the finding" {
  wt
  run_lint >/dev/null
  warm="$(run_lint)"
  [ "$(carried "$warm")" -eq 3 ]
  cold="$(run_lint CC_WALLTIME_MEMO=off)"
  [ "$(printf '%s\n' "$warm" | grep -v 'per-file memo')" = "$(printf '%s\n' "$cold" | grep -v 'per-file memo')" ]
  [[ "$warm" == *"zz-hit.bats"* ]]
}

@test "walltime: editing one suite re-proves THAT suite and no other" {
  wt
  run_lint >/dev/null
  printf '# bytes that change no verdict\n' >> "$CORPUS/tests/clean2.bats"
  commit edit
  after="$(run_lint)"
  [ "$(proven "$after")" -eq 2 ]
  [ "$(carried "$after")" -eq 2 ]
}

@test "walltime KEY: the lint's own blob invalidates every carried verdict" {
  wt
  run_lint >/dev/null
  printf '\n# read-set change\n' >> "$CORPUS/scripts/test-walltime-lint.sh"
  commit lint-edit
  [ "$(carried "$(run_lint)")" -eq 0 ]
}

@test "walltime KEY: the allowlist is in the key BY VALUE — no byte of any file moves" {
  wt
  run_lint >/dev/null
  [ "$(carried "$(run_lint CC_WALLTIME_ALLOWLIST=unrelated.bats)")" -eq 0 ]
}

@test "walltime KEY: TODAY is in the key — a clean verdict earned today is not honoured on another day" {
  wt
  run_lint >/dev/null
  [ "$(carried "$(run_lint CC_WALLTIME_TODAY=20200101)")" -eq 0 ]
}

@test "walltime KEY: the HORIZON is in the key" {
  wt
  run_lint >/dev/null
  [ "$(carried "$(run_lint CC_WALLTIME_HORIZON_YEARS=3)")" -eq 0 ]
}

@test "walltime KEY: a different GREP binary invalidates — and then re-earns" {
  wt
  run_lint >/dev/null
  shim grep 'NEVER-MATCHES' 2
  [ "$(carried "$(run_lint PATH="$SHIM:$PATH")")" -eq 0 ]
  [ "$(carried "$(run_lint PATH="$SHIM:$PATH")")" -eq 3 ]
}

@test "walltime KEY: a different SORT binary invalidates — and then re-earns" {
  wt
  run_lint >/dev/null
  shim sort 'NEVER-MATCHES' 2
  [ "$(carried "$(run_lint PATH="$SHIM:$PATH")")" -eq 0 ]
  [ "$(carried "$(run_lint PATH="$SHIM:$PATH")")" -eq 3 ]
}

@test "walltime KEY: a different AWK binary invalidates — and then re-earns" {
  wt
  run_lint >/dev/null
  shim awk 'NEVER-MATCHES' 2
  [ "$(carried "$(run_lint PATH="$SHIM:$PATH")")" -eq 0 ]
  [ "$(carried "$(run_lint PATH="$SHIM:$PATH")")" -eq 3 ]
}

@test "walltime: a date scan that could not RUN banks nothing — the veto is ABSOLUTE, not per file" {
  # clean1 is FIRST in glob order, so the two readings separate completely: an absolute veto banks
  # nothing (carried 0 next run); a per-file one banks clean2, clean3 (carried 2).
  wt
  shim grep '*tests/clean1.bats*' 2
  : > "$MEMO_SHIM_FLAG"
  run_lint PATH="$SHIM:$PATH" >/dev/null
  rm -f "$MEMO_SHIM_FLAG"
  b="$(run_lint PATH="$SHIM:$PATH")"
  [ "$(carried "$b")" -eq 0 ]
  [ "$(proven "$b")" -eq 4 ]
}

@test "walltime: an allowlisted CLEAN suite is never banked, even when the allowlist probe cannot run" {
  wt
  shim grep '*-xF*' 2
  : > "$MEMO_SHIM_FLAG"
  run_lint PATH="$SHIM:$PATH" CC_WALLTIME_ALLOWLIST=clean1.bats >/dev/null
  rm -f "$MEMO_SHIM_FLAG"
  out="$(run_lint PATH="$SHIM:$PATH" CC_WALLTIME_ALLOWLIST=clean1.bats)"
  [[ "$out" == *"clean1.bats"* ]]
}

@test "walltime: --selftest runs memo-OFF and writes nothing to the store" {
  wt
  run_lint >/dev/null
  before="$(store_entries)"
  ( cd "$CORPUS" && bash scripts/test-walltime-lint.sh --selftest >/dev/null 2>&1 ) || true
  [ "$(store_entries)" -eq "$before" ]
}

@test "walltime: a dirty worktree, and CC_WALLTIME_MEMO=off, each disarm the memo" {
  wt
  [[ "$(run_lint CC_WALLTIME_MEMO=off)" != *"per-file memo"* ]] || false
  printf '# uncommitted\n' >> "$CORPUS/tests/clean1.bats"
  [[ "$(run_lint)" != *"per-file memo"* ]]
}

@test "walltime: ONE DAY PER RUN — a run straddling midnight cannot bank a verdict under the wrong day" {
  # The clock shim answers DAY1 to the first `date -u +%Y%m%d` and DAY2 to every later one: a run that
  # crosses midnight. Unpinned, the key reads DAY1 (it is computed first) while the suites are judged
  # against DAY2, so a date EQUAL to DAY2 — future on DAY1, not on DAY2 — is judged clean and banked under
  # DAY1's key, and the next DAY1 run carries it silently over a real finding. Pinned, the run is DAY1.
  # Dates are assembled arithmetically so this suite, which the lint also judges, carries no literal one.
  local d1 d2 ymd
  d1="20$((30))0101"; d2="20$((30))0102"; ymd="20$((30))-01-02"
  mkcorpus test-walltime-lint.sh WALLTIME "run subject --until \"$ymd\""
  CLOCK="$BATS_TEST_TMPDIR/clock"; mkdir -p "$CLOCK"   # its own name: SHIM belongs to shim(), read by later cases
  # shellcheck disable=SC2016  # the shim's own "$*", "$c" and "$@" must reach it LITERALLY
  printf '#!/bin/bash\nc="%s"\nif [ "$*" = "-u +%%Y%%m%%d" ]; then\n  if [ -e "$c" ]; then echo %s; else : > "$c"; echo %s; fi\n  exit 0\nfi\nexec /bin/date "$@"\n' \
    "$BATS_TEST_TMPDIR/date.calls" "$d2" "$d1" > "$CLOCK/date"
  chmod +x "$CLOCK/date"
  run_lint PATH="$CLOCK:$PATH" >/dev/null
  out="$(run_lint CC_WALLTIME_TODAY="$d1")"
  [[ "$out" == *"zz-hit.bats"* ]]            # on DAY1 that date IS in the future: it must be reported
}

# ── bats-kill-guard-lint ─────────────────────────────────────────────────────────────────────────────
# A different mechanism: ONE awk pass over every suite, so the memo shrinks the awk's INPUT to the unproven
# suites and banks only suites the pass never named. Its finding — a kill whose stderr is silenced and whose
# status is not — is carried inside single quotes, which this lint's own scanner blanks.
# shellcheck disable=SC2016  # the fixture LINE is data written into a corpus suite, never expanded here
kg() { mkcorpus bats-kill-guard-lint.sh KILLGUARD 'kill "$p" 2>/dev/null'; }

@test "kill-guard POSITIVE CONTROL: the memo arms, and carries every clean suite" {
  kg
  first="$(run_lint)"
  [[ "$first" == *"per-file memo"* ]] || { echo "MEMO NEVER ARMED — every kill-guard case is vacuous"; echo "$first"; false; }
  [ "$(carried "$first")" -eq 0 ]
  [ "$(proven "$first")" -eq 4 ]
  second="$(run_lint)"
  [ "$(carried "$second")" -eq 3 ]
  [ "$(proven "$second")" -eq 1 ]
}

@test "kill-guard: a carried run says exactly what an unmemoized run says, and re-reports the finding" {
  kg
  run_lint >/dev/null
  warm="$(run_lint)"
  [ "$(carried "$warm")" -eq 3 ]
  cold="$(run_lint CC_KILLGUARD_MEMO=off)"
  [ "$(printf '%s\n' "$warm" | grep -v 'per-file memo')" = "$(printf '%s\n' "$cold" | grep -v 'per-file memo')" ]
  [[ "$warm" == *"zz-hit.bats"* ]]
}

@test "kill-guard: editing one suite re-proves THAT suite and no other" {
  kg
  run_lint >/dev/null
  printf '# bytes that change no verdict\n' >> "$CORPUS/tests/clean2.bats"
  commit edit
  after="$(run_lint)"
  [ "$(proven "$after")" -eq 2 ]
  [ "$(carried "$after")" -eq 2 ]
}

@test "kill-guard KEY: the lint's own blob invalidates every carried verdict" {
  kg
  run_lint >/dev/null
  printf '\n# read-set change\n' >> "$CORPUS/scripts/bats-kill-guard-lint.sh"
  commit lint-edit
  [ "$(carried "$(run_lint)")" -eq 0 ]
}

@test "kill-guard KEY: a different AWK binary invalidates — and then re-earns" {
  kg
  run_lint >/dev/null
  shim awk 'NEVER-MATCHES' 3
  [ "$(carried "$(run_lint PATH="$SHIM:$PATH")")" -eq 0 ]
  [ "$(carried "$(run_lint PATH="$SHIM:$PATH")")" -eq 3 ]
}

@test "kill-guard: a pass that did not exit 0 banks NOTHING — not even the suites it never named" {
  # The whole population is ONE awk invocation, so its failure says nothing about ANY suite in it. Banking
  # the unnamed ones would bank the finding too: a dead pass names nobody, zz-hit included.
  kg
  shim awk '*tests/clean1.bats*' 3
  : > "$MEMO_SHIM_FLAG"
  run_lint PATH="$SHIM:$PATH" >/dev/null
  rm -f "$MEMO_SHIM_FLAG"
  b="$(run_lint PATH="$SHIM:$PATH")"
  [ "$(carried "$b")" -eq 0 ]
  [[ "$b" == *"zz-hit.bats"* ]]
}

@test "kill-guard: an UNREADABLE suite (UNBALANCED) is never banked — it must say so on every run" {
  # The unterminated quote sits AFTER the last column-zero `}`, where the scanner's resync cannot clear it.
  kg
  printf '@test "u" {\n  true\n}\nx="this quote never closes\n' > "$CORPUS/tests/unbal.bats"
  commit unbal
  run_lint >/dev/null
  out="$(run_lint)"
  [[ "$out" == *"unbal.bats"* ]]
}

@test "kill-guard: a finding in a path containing a colon is never banked by mis-attribution" {
  kg
  # shellcheck disable=SC2016  # the fixture BODY is data written into a corpus suite, never expanded here
  printf '@test "c" {\n  kill "$p" 2>/dev/null\n}\n' > "$CORPUS/tests/zz:colon.bats"
  commit colon
  run_lint >/dev/null
  out="$(run_lint)"
  [[ "$out" == *"zz:colon.bats"* ]]
}

@test "kill-guard: --selftest runs memo-OFF (EXPORTED — it re-invokes itself) and writes nothing to the store" {
  kg
  run_lint >/dev/null
  before="$(store_entries)"
  ( cd "$CORPUS" && bash scripts/bats-kill-guard-lint.sh --selftest >/dev/null 2>&1 ) || true
  [ "$(store_entries)" -eq "$before" ]
}

@test "kill-guard: a dirty worktree, and CC_KILLGUARD_MEMO=off, each disarm the memo" {
  kg
  [[ "$(run_lint CC_KILLGUARD_MEMO=off)" != *"per-file memo"* ]] || false
  printf '# uncommitted\n' >> "$CORPUS/tests/clean1.bats"
  [[ "$(run_lint)" != *"per-file memo"* ]]
}

@test "kill-guard: the record index is the suite's place in the POPULATION, never in the miss-list" {
  # A finding is never recorded, so it sits in EVERY pass's miss-list. With the population [clean1, zz-hit,
  # clean2] and clean2 edited, the miss-list is [zz-hit, clean2]: recording clean2 by its miss-list
  # position (1) would bank population[1] — the FINDING — as green, and the next run would carry it.
  # THE ORDER IS PINNED by naming the files: collect_bats walks a directory with find, whose order is the
  # filesystem's, and a case that assumed alphabetical order let exactly this mutant survive.
  kg
  run3() { ( cd "$CORPUS" && env CC_KILLGUARD_OWN=x bash scripts/bats-kill-guard-lint.sh \
               tests/clean1.bats tests/zz-hit.bats tests/clean2.bats 2>&1 ) || true; }
  run3 >/dev/null
  printf '# bytes that change no verdict\n' >> "$CORPUS/tests/clean2.bats"
  commit edit
  run3 >/dev/null
  out="$(run3)"
  [[ "$out" == *"zz-hit.bats"* ]]
}

# ── utc-stamp-lint ───────────────────────────────────────────────────────────────────────────────────
# Its population is every script under a TARGET DIR (a bare run takes bin/ hooks/ scripts/); the one target
# here is the corpus's tests/, so the same four suites are its population. Its finding: a stamp that CLAIMS
# UTC with a literal Z and reads the local clock.
ut() { local q="'"; mkcorpus utc-stamp-lint.sh UTC "ts=\"\$(date ${q}+%Y-%m-%dT%H:%M:%SZ${q})\""; }

# A grep shim that fails ONE of lying_stamps' two pipelines for clean1, told apart by the second one's
# `strftime` pattern. Its own dir, so no other case's SHIM is touched. $1=which pipeline (1|2).
ut_probe_shim() {
  PSHIM="$BATS_TEST_TMPDIR/pshim$1"; mkdir -p "$PSHIM"
  export MEMO_SHIM_FLAG="$BATS_TEST_TMPDIR/fail.flag"
  local arm='*strftime*) ;; *tests/clean1.bats*) exit 2 ;;'
  [ "$1" = 2 ] && arm='*strftime*tests/clean1.bats*) exit 2 ;;'
  # shellcheck disable=SC2016  # the shim's own "$MEMO_SHIM_FLAG" / "$*" / "$@" must reach it LITERALLY
  printf '#!/bin/bash\nif [ -e "$MEMO_SHIM_FLAG" ]; then case "$*" in %s esac; fi\nexec /usr/bin/grep "$@"\n' "$arm" > "$PSHIM/grep"
  chmod +x "$PSHIM/grep"
}

@test "utc POSITIVE CONTROL: the memo arms, and carries every clean file" {
  ut
  first="$(run_lint)"
  [[ "$first" == *"per-file memo"* ]] || { echo "MEMO NEVER ARMED — every utc case is vacuous"; echo "$first"; false; }
  [ "$(carried "$first")" -eq 0 ]
  [ "$(proven "$first")" -eq 4 ]
  second="$(run_lint)"
  [ "$(carried "$second")" -eq 3 ]
  [ "$(proven "$second")" -eq 1 ]
}

@test "utc: a carried run says exactly what an unmemoized run says, and re-reports the finding" {
  ut
  run_lint >/dev/null
  warm="$(run_lint)"
  [ "$(carried "$warm")" -eq 3 ]
  cold="$(run_lint CC_UTC_MEMO=off)"
  [ "$(printf '%s\n' "$warm" | grep -v 'per-file memo')" = "$(printf '%s\n' "$cold" | grep -v 'per-file memo')" ]
  [[ "$warm" == *"zz-hit.bats"* ]]
}

@test "utc: editing one file re-proves THAT file and no other" {
  ut
  run_lint >/dev/null
  printf '# bytes that change no verdict\n' >> "$CORPUS/tests/clean2.bats"
  commit edit
  after="$(run_lint)"
  [ "$(proven "$after")" -eq 2 ]
  [ "$(carried "$after")" -eq 2 ]
}

@test "utc KEY: the lint's own blob invalidates every carried verdict" {
  ut
  run_lint >/dev/null
  printf '\n# read-set change\n' >> "$CORPUS/scripts/utc-stamp-lint.sh"
  commit lint-edit
  [ "$(carried "$(run_lint)")" -eq 0 ]
}

@test "utc KEY: the allowlist is in the key BY VALUE — no byte of any file moves" {
  ut
  run_lint >/dev/null
  [ "$(carried "$(run_lint CC_UTC_ALLOWLIST=unrelated.bats)")" -eq 0 ]
}

@test "utc KEY: a different GREP binary invalidates — and then re-earns" {
  ut
  run_lint >/dev/null
  shim grep 'NEVER-MATCHES' 2
  [ "$(carried "$(run_lint PATH="$SHIM:$PATH")")" -eq 0 ]
  [ "$(carried "$(run_lint PATH="$SHIM:$PATH")")" -eq 3 ]
}

@test "utc: a FIRST-pipeline probe that could not run is never banked" {
  ut
  ut_probe_shim 1
  : > "$MEMO_SHIM_FLAG"
  run_lint PATH="$PSHIM:$PATH" >/dev/null
  rm -f "$MEMO_SHIM_FLAG"
  b="$(run_lint PATH="$PSHIM:$PATH")"
  [ "$(proven "$b")" -eq 2 ]                   # clean1 + the finding
  [ "$(carried "$b")" -eq 2 ]
}

@test "utc: a SECOND-pipeline probe that could not run is never banked" {
  ut
  ut_probe_shim 2
  : > "$MEMO_SHIM_FLAG"
  run_lint PATH="$PSHIM:$PATH" >/dev/null
  rm -f "$MEMO_SHIM_FLAG"
  b="$(run_lint PATH="$PSHIM:$PATH")"
  [ "$(proven "$b")" -eq 2 ]
  [ "$(carried "$b")" -eq 2 ]
}

@test "utc: an allowlisted CLEAN file is never banked, even when the allowlist probe cannot run" {
  ut
  shim grep '*-xF*' 2
  : > "$MEMO_SHIM_FLAG"
  run_lint PATH="$SHIM:$PATH" CC_UTC_ALLOWLIST=clean1.bats >/dev/null
  rm -f "$MEMO_SHIM_FLAG"
  out="$(run_lint PATH="$SHIM:$PATH" CC_UTC_ALLOWLIST=clean1.bats)"
  [[ "$out" == *"clean1.bats"* ]]
}

@test "utc: --selftest runs memo-OFF and writes nothing to the store" {
  ut
  run_lint >/dev/null
  before="$(store_entries)"
  ( cd "$CORPUS" && bash scripts/utc-stamp-lint.sh --selftest >/dev/null 2>&1 ) || true
  [ "$(store_entries)" -eq "$before" ]
}

@test "utc: a dirty worktree, and CC_UTC_MEMO=off, each disarm the memo" {
  ut
  [[ "$(run_lint CC_UTC_MEMO=off)" != *"per-file memo"* ]] || false
  printf '# uncommitted\n' >> "$CORPUS/tests/clean1.bats"
  [[ "$(run_lint)" != *"per-file memo"* ]]
}
