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
