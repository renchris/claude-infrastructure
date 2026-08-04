#!/usr/bin/env bats
# it2-kitty — the `session list` output CONTRACT, which has two shapes and two different consumers.
#
# WHY THIS SUITE EXISTS. `session list` is the only verb in the shim answered differently depending
# on a flag, and the flag is the one Claude Code never passes:
#
#   bare      Claude Code's ITermBackend. Prunes dead teammates with stdout.includes(<paneId>),
#             so it needs raw ids, one per line.
#   --json    THIS REPO. bin/cc-pane:153 and bin/cc-notify both call `session list --json` and
#             jq-parse `.[].id` — cc-pane for the seam's liveness verdict, cc-notify for the
#             pane-liveness oracle behind two-way comms.
#
# Until the flag was parsed it fell through the arg loop's `*)` arm into ARGS, and `list` ignores
# ARGS — so both repo callers received bare integers where they demanded an array. Measured live on
# 2026-07-31 against a real kitty: jq read each line as a separate scalar, cc-pane's `n` became a
# multi-line string, and `[ "$n" -eq 0 ]` raised `integer expression expected` → cc-pane exited
# INDETERMINATE; cc-notify's `type=="array"` test failed → liveness "unknown". Both degraded SAFELY
# and both were non-functional, which is exactly the shape a green suite does not catch.
#
# Every assertion is `[ ]` or `… || false` — `[[ ]]` and `(( ))` are errexit-EXEMPT in bats and are
# silently DEAD anywhere but a body's last line (memory: bats-dead-assertions-errexit-exemptions;
# independently re-measured in this repo as plan §7.8 learning 1).

setup() {
  # handoff-fire's capacity_gate() refuses a net-new fire above 2.0/core and this box lives well
  # above that, so an unpinned suite goes red-by-LOAD rather than by its subject. Named by
  # test-hermeticity-lint, which blocks the land on it.
  export CC_FIRE_CAPACITY_GATE=off
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  K="$REPO/bin/it2-kitty"
  # The shim refuses to run without a control socket (exit 4). Point it at a fake and give it a
  # fake kitty, so nothing here can touch the operator's live fleet — this suite enumerates panes,
  # and the sibling suites learned the hard way that an unfixtured seam reaches real $HOME.
  export CC_TERM_KITTY_TO="unix:$BATS_TEST_TMPDIR/sock"
  export CC_TERM_KITTY="$BATS_TEST_TMPDIR/fake-kitty"
}

# A stand-in for `kitty @ … ls`. Three panes across two tabs in one OS window, so a flattening bug
# that only walks the first tab is observable rather than passing by luck.
fake_kitty() {
  cat > "$CC_TERM_KITTY" <<'SH'
#!/bin/bash
for a in "$@"; do [ "$a" = ls ] || continue
cat <<'JSON'
[{"id":1,"tabs":[
  {"id":1,"windows":[{"id":2,"title":"leader","cwd":"/tmp/a","pid":100},
                     {"id":15,"title":"teammate","cwd":"/tmp/b","pid":101}]},
  {"id":2,"windows":[{"id":260,"title":"other","cwd":"/tmp/c","pid":102}]}]}]
JSON
exit 0; done
exit 0
SH
  chmod +x "$CC_TERM_KITTY"
}

setup_file() { :; }

# ── the bare shape: Claude Code's contract ───────────────────────────────────────────────────────

@test "bare 'session list' prints raw ids one per line (Claude Code's prune path)" {
  fake_kitty
  run "$K" session list
  [ "$status" -eq 0 ]
  [ "$output" = "2
15
260" ]
}

# ── the --json shape: this repo's contract ───────────────────────────────────────────────────────

@test "'session list --json' emits a JSON ARRAY, not bare lines" {
  fake_kitty
  run "$K" session list --json
  [ "$status" -eq 0 ]
  # RED-proof: before --json was parsed this was "2\n15\n260", and jq -e type=="array" failed —
  # which is precisely how cc-notify's oracle fell through to "unknown".
  printf '%s' "$output" | jq -e 'type=="array"' >/dev/null || false
  [ "$(printf '%s' "$output" | jq -r 'length')" = 3 ]
}

@test "--json ids are strings and match the bare list EXACTLY (one enumeration, two renderings)" {
  fake_kitty
  local bare json
  bare="$("$K" session list)"
  json="$("$K" session list --json | jq -r '.[].id')"
  [ "$bare" = "$json" ]
  # ids are strings: a number would still satisfy `.[].id` but breaks the opaque-token contract the
  # split verb honours, where Claude Code hands whatever token we printed straight back as `-s <id>`.
  "$K" session list --json | jq -e 'all(.[].id; type=="string")' >/dev/null || false
}

@test "--json ids are FULL, never truncated — the defect that makes real it2 prune live teammates" {
  # The real it2 renders this list through `rich`, which truncates the Session ID column to the 80
  # columns it assumes when stdout is a pipe. That makes Claude Code's own
  # !stdout.includes(fullSessionId) liveness test always read "dead" (plan §4.3). A long id must
  # survive both renderings intact.
  cat > "$CC_TERM_KITTY" <<'SH'
#!/bin/bash
for a in "$@"; do [ "$a" = ls ] || continue
printf '[{"id":1,"tabs":[{"id":1,"windows":[{"id":123456789012345678901234567890,"title":"'
printf 'x%.0s' $(seq 1 200)
printf '","cwd":"/tmp","pid":1}]}]}]\n'
exit 0; done
exit 0
SH
  chmod +x "$CC_TERM_KITTY"
  run "$K" session list --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.[0].id')" = "123456789012345678901234567890" ]
}

# ── the flag must not leak into other verbs ──────────────────────────────────────────────────────

@test "--json is consumed as a FLAG — it never reaches send/run text" {
  # Before the fix, an unrecognised flag landed in ARGS. `list` ignored ARGS so the bug was silent
  # there, but the same `*)` arm feeds send/run, where a leaked token is TYPED INTO THE PANE.
  cat > "$CC_TERM_KITTY" <<'SH'
#!/bin/bash
printf '%s\n' "$*" > "$CC_ARGS_SINK"
exit 0
SH
  chmod +x "$CC_TERM_KITTY"
  export CC_ARGS_SINK="$BATS_TEST_TMPDIR/args"
  run "$K" session send -s 7 --json hello
  [ "$status" -eq 0 ]
  grep -q 'hello' "$CC_ARGS_SINK" || false
  # `! A || false`, NOT `A && false`. The latter is what the dead-assertion ratchet named here: as a
  # non-final `A && B` the failure is absorbed and errexit never sees it, so the assertion could not
  # fail — it only LOOKED like it was checking. And a uniform `|| false` is the wrong repair for this
  # class (it fails on BOTH branches); the negation has to move onto the command itself.
  ! grep -q -- '--json' "$CC_ARGS_SINK" || false
}

# ── the integration that actually regressed ──────────────────────────────────────────────────────

@test "cc-pane list SUCCEEDS through the shim (was: INDETERMINATE + a bash error)" {
  fake_kitty
  run env CC_PANE_IT2="$K" "$REPO/bin/cc-pane" list
  # The pre-fix run exited 2 (INDETERMINATE) after printing
  #   cc-pane: line 160: [: -1\n-1\n-1: integer expression expected
  # to stderr. Both halves are asserted: the verdict AND the absence of the parse error.
  [ "$status" -eq 0 ]
  [ "$output" = "2
15
260" ]
}

@test "cc-pane address distinguishes ABSENT from INDETERMINATE through the shim" {
  fake_kitty
  run env CC_PANE_IT2="$K" "$REPO/bin/cc-pane" address 15
  [ "$status" -eq 0 ]
  [ "$output" = "15" ]
  # A pane that is genuinely gone must be an authoritative NO (1), never INDETERMINATE (2) — the
  # distinction cc-pane exists to preserve, and the one a broken enumerator collapses.
  run env CC_PANE_IT2="$K" "$REPO/bin/cc-pane" address 9999
  [ "$status" -eq 1 ]
}

@test "a BLIND enumerator still reads INDETERMINATE, not 'no panes'" {
  # Positive control for the guard above it: fixing --json must not make an unreadable kitty look
  # like an empty one. cc-pane:160 treats zero enumerated panes as a failed probe precisely because
  # reporting "no panes" lets a caller reap a live fleet.
  cat > "$CC_TERM_KITTY" <<'SH'
#!/bin/bash
exit 1
SH
  chmod +x "$CC_TERM_KITTY"
  run env CC_PANE_IT2="$K" "$REPO/bin/cc-pane" list
  [ "$status" -eq 2 ]
}

# ── BINARY RESOLUTION (added 2026-08-01) ─────────────────────────────────────────────────────────
# WHY THESE EXIST. `KITTY_BIN="${CC_TERM_KITTY:-kitty}"` — a bare name — meant every AUTOMATED pane
# close was a silent no-op on kitty while every interactive one worked. Hooks and launchd jobs run
# with PATH=/usr/bin:/bin:/usr/sbin:/sbin (no Homebrew), so `kitty` did not exist for exactly the
# callers that close panes: teammate-auto-shutdown, cc-teardown, cc-reaper, handoff-fire. Measured
# live: rc=1 `kitty: command not found`, teammate pane survived 3h09m with its 653 MB claude.exe
# still resident. The one caller that COULD close was the operator's own shell.
#
# The suite above cannot catch this — its setup() pins CC_TERM_KITTY to a fixture, which is the one
# configuration where the bare name is never reached. So these drop the fixture on purpose.
setup_nofixture() {
  # handoff-fire's capacity_gate() refuses a net-new fire above 2.0/core and this box lives well
  # above that, so an unpinned suite goes red-by-LOAD rather than by its subject. Named by
  # test-hermeticity-lint, which blocks the land on it.
  export CC_FIRE_CAPACITY_GATE=off
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  K="$REPO/bin/it2-kitty"
  export CC_TERM_KITTY_TO="unix:$BATS_TEST_TMPDIR/sock"   # bypasses the ancestry guard
  unset CC_TERM_KITTY
}

@test "REGRESSION: auto-resolves kitty under a launchd-style minimal PATH (no Homebrew)" {
  setup_nofixture
  # THE leg that regressed, and the only one that can prove the fix. CC_TERM_KITTY is UNSET here on
  # purpose: with it set, the pre-fix `${CC_TERM_KITTY:-kitty}` used it verbatim too, so a fixtured
  # version of this test passes against the BUG and proves nothing (it did, until this comment).
  #
  # Assertion is on the FAILURE MODE, not on success: with a bogus socket the call must still fail,
  # but it must fail at the SOCKET (resolution happened) and never at `kitty: command not found`
  # (resolution did not). That distinction is the whole defect.
  command -v /opt/homebrew/bin/kitty >/dev/null 2>&1 || [ -x /opt/homebrew/bin/kitty ] \
    || [ -x /usr/local/bin/kitty ] || [ -x /Applications/kitty.app/Contents/MacOS/kitty ] \
    || skip "no kitty installed at any absolute fallback — nothing to resolve"
  run env -i HOME="$HOME" PATH=/usr/bin:/bin \
      CC_TERM_KITTY_TO="unix:$BATS_TEST_TMPDIR/definitely-not-a-socket" "$K" session list
  [ "$status" -ne 0 ] || false
  # Assert the RESOLUTION POSITIVELY, via the binary the failure path names. An earlier draft
  # asserted the ABSENCE of "command not found" and was vacuous twice over: absence is satisfied by
  # any other error, and this file's own stderr-capture fix changed the wording to "failed to run
  # command 'kitty'" so the literal never appeared at all. A negative assertion is only as good as
  # your list of spellings; `binary: /` is one fact with one meaning — an ABSOLUTE path was resolved.
  # Under the pre-fix bare name the same line reads `binary: kitty`, so this fails exactly there.
  echo "$output" | grep -q "binary: /" || { echo "$output"; false; }
}

@test "REGRESSION: a bad CC_TERM_KITTY refuses — an override must not be overridable" {
  setup_nofixture
  # Folding CC_TERM_KITTY into the fallback list looks equivalent and is not: a non-executable
  # override would be SKIPPED and an auto-detected kitty driven instead. Caught by this file's own
  # control during the fix — CC_TERM_KITTY=/nonexistent/kitty closed a pane through the real kitty
  # and reported success. The operator pins a binary; the shim must use it or refuse.
  run env -i HOME="$HOME" PATH=/usr/bin:/bin CC_TERM_KITTY=/nonexistent/kitty \
      CC_TERM_KITTY_TO="$CC_TERM_KITTY_TO" "$K" session close -f -s 15
  [ "$status" -eq 5 ] || false
  echo "$output" | grep -q "is not executable" || false
}

# ── SPAWN MUST NOT STEAL FOCUS ───────────────────────────────────────────────────────────────────
# kitty focuses a newly-launched window BY DEFAULT; iTerm2 does not. `launch` starts a bare
# interactive zsh, and the backend's contract is split → send Ctrl-U → run <text>, so between the
# line-clear and the command a FOCUSED pane owns the keyboard for ~50-150ms. Whatever the operator
# is typing elsewhere lands in that line buffer: measured 2026-08-03, one stray `a` turned a
# teammate launch into `acd …` and, via `setopt CORRECT`, into an interactive `[nyae]` HANG that no
# caller can tell apart from a working agent. `focus_follows_mouse` is `no`, so the theft is STICKY.
#
# These pin the FLAG, not the observed focus: a hermetic suite has no compositor. The live A/B that
# justifies them (focus HELD vs STOLEN, both arms positive-controlled on pane count) is recorded in
# the commit. Recording kitty's argv is what makes "did not pass the flag" observable at all.

# A stand-in kitty that RECORDS its argv, so an assertion can read what launch was actually asked
# for. Prints a plausible new-window id, because split() rejects a non-numeric result before we get
# to inspect anything.
fake_kitty_recording() {
  ARGV_LOG="$BATS_TEST_TMPDIR/kitty-argv"
  cat > "$CC_TERM_KITTY" <<SH
#!/bin/bash
printf '%s\n' "\$*" >> "$ARGV_LOG"
case "\$*" in *launch*) printf '77\n' ;; esac
exit 0
SH
  chmod +x "$CC_TERM_KITTY"
}

@test "session split passes --keep-focus (anchored) — a spawn must not take the keyboard" {
  fake_kitty_recording
  run "$K" session split -s 15
  [ "$status" -eq 0 ] || false
  # Positive control FIRST: without this, a split that never reached `launch` would satisfy the
  # grep-for-absence trivially and the test would pass vacuously.
  grep -q -- 'launch' "$ARGV_LOG" || false
  grep -q -- '--next-to id:15' "$ARGV_LOG" || false
  grep -q -- '--keep-focus' "$ARGV_LOG" || false
  # The backend parses this line; losing it strands the operator watching an empty window.
  echo "$output" | grep -q '^Created new pane: 77$' || false
}

@test "session split passes --keep-focus (anchorless) — the unanchored path lands on the ACTIVE tab" {
  fake_kitty_recording
  # No -s: kitty puts the window in whatever tab is active, i.e. the one the operator is looking
  # at. That makes the flag MORE load-bearing here, not less.
  run "$K" session split
  [ "$status" -eq 0 ] || false
  grep -q -- 'launch' "$ARGV_LOG" || false
  grep -q -- '--keep-focus' "$ARGV_LOG" || false
}

# ── CLOSE-TARGET IDENTITY PIN (added 2026-08-04) ─────────────────────────────────────────────────
# WHY THESE EXIST. `session close` guarded its target with `valid_id` alone — a DIGITS-ONLY shape
# check. That is sound for the iTerm2 session UUIDs this shim impersonates, which are never
# recycled, so a stale id can only ever no-op. It is FALSE for kitty: a window id is a per-process
# counter that restarts at 1 with every kitty, so an id recorded before a restart survives as a
# perfectly valid id naming a completely unrelated LIVE window. A positive control closed a
# non-claude window exactly this way.
#
# The pins are OPTIONAL and caller-supplied, which splits this suite in two and both halves matter:
# the flagged arms prove the check refuses/permits on evidence, and the LAST arm proves that a
# caller who supplies neither flag reaches kitty on the old path with no `ls` probe at all — because
# a pin that quietly became mandatory would turn one mis-wired caller into a self-close OUTAGE.
#
# Every assertion is `[ ]` or `… || false`, and every negative is an `if grep -q … then fail` block:
# `! grep` is errexit-EXEMPT in bats (silently dead off a body's last line) and is blocked at the
# land by scripts/bats-assert-liveness.py.

# A kitty that RECORDS every invocation and answers `ls` from a payload file the test writes. The
# recording is what makes "the close call was NOT emitted" and "the ls probe WAS made" observable —
# an exit code alone cannot distinguish a refusal from a close that happened and then failed.
fake_kitty_identity() {
  CALLS="$BATS_TEST_TMPDIR/kitty-calls"
  LSPAYLOAD="$BATS_TEST_TMPDIR/ls.json"
  : > "$CALLS"
  cat > "$CC_TERM_KITTY" <<SH
#!/bin/bash
printf '%s\n' "\$*" >> "$CALLS"
for a in "\$@"; do
  [ "\$a" = ls ] || continue
  cat "$LSPAYLOAD"
  exit 0
done
exit 0
SH
  chmod +x "$CC_TERM_KITTY"
}

# \$1 = window id · \$2 = the window's env.KITTY_PID · \$3 = a JSON array literal for the FOREGROUND
# process cmdline. The window's own `cmdline` is deliberately a bare shell in every fixture, so a
# match can only come from the foreground process — i.e. the half of the union that a narrower
# implementation would have skipped. A caffeinate row rides along because live panes really do carry
# one (bin/cc-spawn-verify:32), so a haystack that only read the FIRST process would fail here.
id_payload() {
  cat > "$LSPAYLOAD" <<JSON
[{"id":1,"tabs":[{"id":1,"windows":[
  {"id":$1,"title":"t","cwd":"/tmp","pid":9,
   "env":{"KITTY_PID":"$2","KITTY_WINDOW_ID":"$1"},
   "foreground_processes":[{"cmdline":["/usr/bin/caffeinate","-i"]},{"cmdline":$3}],
   "cmdline":["/bin/zsh"]}]}]}]
JSON
}

@test "close --expect-cmdline-match REFUSES a window whose cmdline lacks the pin (id was recycled)" {
  fake_kitty_identity
  # Window 15 exists and is perfectly healthy — it just belongs to somebody else. This is the live
  # failure: post-restart, id 15 resolves, `valid_id` passes, and the pre-fix close destroys it.
  id_payload 15 4242 '["claude","--agent-name","someone-else"]'
  run "$K" session close -f -s 15 --expect-cmdline-match '--agent-name m'
  [ "$status" -eq 66 ] || { echo "$output"; false; }
  # Positive control FIRST: the probe really ran, so the refusal is a VERDICT and not an accident of
  # some earlier arg-parsing failure that never reached kitty at all.
  grep -q -- 'ls --match id:15' "$CALLS" || { cat "$CALLS"; false; }
  if grep -q -- 'close-window' "$CALLS"; then echo "unexpected close call" >&2; false; fi
}

@test "close --expect-cmdline-match CLOSES when the foreground cmdline carries the pin" {
  fake_kitty_identity
  # The paired positive. Without it the refusal above is satisfied by a check that refuses ALWAYS,
  # which would be a self-close outage wearing a passing test.
  id_payload 15 4242 '["claude","--agent-name","m","--effort","high"]'
  run "$K" session close -f -s 15 --expect-cmdline-match '--agent-name m'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -q -- 'close-window --match id:15' "$CALLS" || { cat "$CALLS"; false; }
}

@test "close --expect-generation REFUSES when env.KITTY_PID is a different kitty" {
  fake_kitty_identity
  # The generation IS the recycling hazard stated directly: same id, different kitty process.
  id_payload 15 4242 '["claude","--agent-name","m"]'
  run "$K" session close -f -s 15 --expect-generation 9999
  [ "$status" -eq 66 ] || { echo "$output"; false; }
  grep -q -- 'ls --match id:15' "$CALLS" || { cat "$CALLS"; false; }
  if grep -q -- 'close-window' "$CALLS"; then echo "unexpected close call" >&2; false; fi
}

@test "close --expect-generation CLOSES when env.KITTY_PID is the pinned kitty" {
  fake_kitty_identity
  id_payload 15 4242 '["claude","--agent-name","m"]'
  run "$K" session close -f -s 15 --expect-generation 4242
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -q -- 'close-window --match id:15' "$CALLS" || { cat "$CALLS"; false; }
}

@test "close REFUSES when the ls payload is unreadable — a blind probe must not authorise a close" {
  fake_kitty_identity
  # Tri-state, the same discipline pane_present carries: an unreadable oracle is INDETERMINATE, and
  # indeterminate must never resolve to 'go ahead'. Absence of evidence is not evidence of target.
  printf 'not json at all\n' > "$LSPAYLOAD"
  run "$K" session close -f -s 15 --expect-cmdline-match '--agent-name m'
  [ "$status" -eq 66 ] || { echo "$output"; false; }
  if grep -q -- 'close-window' "$CALLS"; then echo "unexpected close call" >&2; false; fi
}

@test "close REFUSES when ZERO windows carry the id — a vanished target is not a free close" {
  fake_kitty_identity
  # Well-formed payload, no such window. Distinct from the unreadable case above: here kitty is
  # perfectly healthy and simply does not have the window, which pre-fix reached close-window and
  # let kitty decide — the exact path by which a recycled id gets acted on.
  id_payload 260 4242 '["claude","--agent-name","m"]'
  run "$K" session close -f -s 15 --expect-cmdline-match '--agent-name m'
  [ "$status" -eq 66 ] || { echo "$output"; false; }
  if grep -q -- 'close-window' "$CALLS"; then echo "unexpected close call" >&2; false; fi
}

@test "close with NEITHER flag closes on the old path and makes NO ls probe (self-close untouched)" {
  fake_kitty_identity
  # THE regression pin for handoff-fire's self-close, cc-pane, and every operator close. The pin is
  # caller-supplied precisely so a mispinned check can never become an outage — which is only true
  # while the unflagged path never consults the oracle at all. A verification that crept in here
  # would make every unpinned caller depend on `kt ls` succeeding. The payload deliberately names
  # the WRONG agent, so a check that ran unconditionally would refuse and this would go red.
  id_payload 15 4242 '["claude","--agent-name","someone-else"]'
  run "$K" session close -f -s 15
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -q -- 'close-window --match id:15' "$CALLS" || { cat "$CALLS"; false; }
  if grep -q -- ' ls ' "$CALLS"; then echo "unexpected ls probe on the unpinned path" >&2; false; fi
}
