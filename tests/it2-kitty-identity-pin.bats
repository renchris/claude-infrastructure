#!/usr/bin/env bats
# bin/it2-kitty `close`: the identity pin, and the state it used to collapse (RC-6).
#
# The pin itself is not in question and is never removed here. A kitty window id is a per-process
# counter that restarts at 1 with every kitty, so a stale id can name a LIVE unrelated window, and
# a wrong-window close was observed (hooks/teammate-auto-shutdown.sh:169-184). Refusing on anything
# short of an affirmative match is correct and stays.
#
# What WAS wrong is that the pin had two states where the world has three. `kitty @ ls --match
# id:N` answers a VANISHED window with rc 1, EMPTY stdout and "No matching windows" on stderr; the
# embedded python saw stdin that would not parse and reported "payload from kitty ls is
# unreadable", i.e. the safe-sounding cannot-tell. Measured over 30 d: 65 spurious refusals, and 42
# of the 51 in September were a SECOND fire against a pane the log shows closed <= 6 lines earlier.
# An already-gone pane is not an unverifiable one — it is the one case where there is provably
# nothing left to protect and nothing left to destroy.
#
# The split is exit 68, distinct from 66, and its stderr says "not found" so that the closer maps
# it through its existing already-gone arm rather than paging a CLOSE-FAILED for a pane that does
# not exist (hooks/teammate-auto-shutdown.sh:309 matches on that stderr, not on the rc).
#
# Behavioural: the shipped bin/it2-kitty runs against a stub `kitty` whose `ls` output, rc and
# stderr are scripted per test, so these observe what the real script would do with the real
# kitty answers.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude"
  REPO="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  SHIM="$REPO/bin/it2-kitty"
  [ -x "$SHIM" ] || skip "bin/it2-kitty not found or not executable at $SHIM"

  BIN="$BATS_TEST_TMPDIR/bin"; mkdir -p "$BIN"
  export KITTY_ARGV="$BATS_TEST_TMPDIR/kitty-argv.log"
  export LS_OUT="$BATS_TEST_TMPDIR/ls-out.json"   # what `kitty @ ls` prints on stdout
  export LS_ERR="$BATS_TEST_TMPDIR/ls-err.txt"    # ...and on stderr
  export LS_RC=0
  : > "$LS_ERR"

  # THE PANE, as kitty really reports it: one window, id 300, running an argv-proven agent. Every
  # test starts from the affirmative case and takes exactly one thing away, so a failure names the
  # conjunct it removed rather than the fixture.
  cat > "$LS_OUT" <<'JSON'
[{"id":1,"tabs":[{"id":1,"windows":[{"id":300,"columns":100,"in_alternate_screen":false,"pid":1,"cwd":"/tmp","env":{"KITTY_PID":"4242"},"foreground_processes":[{"cmdline":["/opt/claude/bin/claude.exe","--agent-id","w2-pin@session-x","--agent-name","w2-pin"]}]}]}]}]
JSON

  cat > "$BIN/kitty" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >> "$KITTY_ARGV"
for a in "$@"; do
  if [ "$a" = "ls" ]; then
    # stdout and stderr BOTH emitted, THEN the rc — kitty does exactly this, and the gone verdict
    # is a conjunction over all three. An early `exit $LS_RC` would make stdout unreachable
    # whenever the rc is non-zero, so the "rc 1 with a payload that will not parse" control could
    # not express its own case and would silently test the empty-stdout one twice.
    cat "$LS_OUT"
    cat "$LS_ERR" >&2
    exit "${LS_RC:-0}"
  fi
  if [ "$a" = "get-text" ]; then
    # Not under test here: serve a shell prompt so the composer guard resolves NO-TUI and never
    # masks an identity verdict with one of its own.
    printf 'chrisren@host ~ %% \n'
    exit 0
  fi
done
exit 0
SH
  chmod +x "$BIN/kitty"
  export CC_TERM_KITTY="$BIN/kitty"
  export PATH="$BIN:$PATH"
  export KITTY_WINDOW_ID=300
  export CC_KITTY_ARGV_SPAWN=0
  # Same declared terminal identity as the composer-guard suite: bin/it2-kitty refuses at its
  # terminal gate long before the pin unless cc-in-kitty agrees AND a control socket is named.
  export CC_TERM=kitty
  export KITTY_LISTEN_ON="unix:$BATS_TEST_TMPDIR/kitty-sock"
  unset CC_TERM_KITTY_TO
  unset CC_PANE_CMD CC_PANE_CMD_DIR CC_PANE_CMD_INTERACTIVE
}

closed()   { grep -q 'close-window --match id:300' "$KITTY_ARGV"; }
attempts() { local n; n="$(grep -c 'close-window' "$KITTY_ARGV" 2>/dev/null)" || n=0; printf '%s' "${n:-0}"; }

# kitty answers a vanished window exactly this way — rc 1, nothing on stdout, one stderr line.
gone_window() { LS_RC=1; : > "$LS_OUT"; printf 'No matching windows\n' > "$LS_ERR"; }

# ── the affirmative case, so every refusal below is a DIFFERENCE and not the baseline ────

@test "the pin AFFIRMS a matching window and the close proceeds" {
  run "$SHIM" session close -f -s 300 --expect-cmdline-match '--agent-name w2-pin'
  [ "$status" -eq 0 ]
  closed
}

# ── RC-6: GONE is a third state, not a flavour of unreadable ─────────────────────────────

@test "RC-6: a window kitty answers with 'No matching windows' is GONE, not unverifiable" {
  gone_window
  run "$SHIM" session close -f -s 300 --expect-cmdline-match '--agent-name w2-pin'
  [ "$status" -eq 68 ]
  [ "$(attempts)" = "0" ]
}

@test "RC-6: the gone verdict says 'not found' — the closer maps on that stderr, not on the rc" {
  # hooks/teammate-auto-shutdown.sh:309 routes a close whose stderr carries "not found" to
  # `~ pane already gone`. Without this wording an rc 68 falls to the CLOSE-FAILED arm and pages
  # the desk about a pane that does not exist.
  gone_window
  run "$SHIM" session close -f -s 300 --expect-cmdline-match '--agent-name w2-pin'
  echo "$output" | grep -qi 'not found'
  echo "$output" | grep -qi 'already gone'
}

@test "RC-6: 68 is distinct from 66 — 'gone' and 'wrong window' are different answers" {
  # A caller that retries must tell "stop, it is already gone" from "re-derive the id and retry".
  gone_window
  run "$SHIM" session close -f -s 300 --expect-cmdline-match '--agent-name w2-pin'
  [ "$status" -eq 68 ]
  # ...and the same shim, same flags, on a window that EXISTS but does not match, still says 66.
  # The stub must be put back first: `run` does not restore the environment, so without this the
  # second arm re-runs the gone fixture and 66-vs-68 is never actually contrasted.
  LS_RC=0; : > "$LS_ERR"
  cat > "$LS_OUT" <<'JSON'
[{"id":1,"tabs":[{"id":1,"windows":[{"id":300,"columns":100,"pid":1,"env":{"KITTY_PID":"4242"},"foreground_processes":[{"cmdline":["/opt/claude/bin/claude.exe","--agent-id","w2-pin@session-x","--agent-name","w2-pin"]}]}]}]}]
JSON
  run "$SHIM" session close -f -s 300 --expect-cmdline-match '--agent-name someone-else'
  [ "$status" -eq 66 ]
}

@test "RC-6: the generation pin reaches the gone verdict too, not only the cmdline pin" {
  gone_window
  run "$SHIM" session close -f -s 300 --expect-generation 4242
  [ "$status" -eq 68 ]
  [ "$(attempts)" = "0" ]
}

# ── ...and every OTHER unreadable answer still refuses, which is the whole point ──────────

@test "RC-6 CONTROL: a TWO-window payload is refused exactly as before — ambiguity is not absence" {
  # THE EQUIVALENCE GUARD. This passes on both sides of the fix by construction, so it is here to
  # pin that the fix did not widen the gone branch into the ambiguous one — and it is only worth
  # keeping because the mutant below proves it has power.
  cat > "$LS_OUT" <<'JSON'
[{"id":1,"tabs":[{"id":1,"windows":[{"id":300,"columns":100,"pid":1,"env":{"KITTY_PID":"4242"},"foreground_processes":[{"cmdline":["/opt/claude/bin/claude.exe","--agent-id","w2-pin@session-x","--agent-name","w2-pin"]}]},{"id":300,"columns":100,"pid":2,"env":{"KITTY_PID":"4242"},"foreground_processes":[{"cmdline":["/opt/claude/bin/claude.exe","--agent-id","w2-pin@session-x","--agent-name","w2-pin"]}]}]}]}]
JSON
  run "$SHIM" session close -f -s 300 --expect-cmdline-match '--agent-name w2-pin'
  [ "$status" -eq 66 ]
  [ "$(attempts)" = "0" ]
  echo "$output" | grep -qi 'exactly 1 window'
}

@test "RC-6 CONTROL: rc 1 with a NON-empty stdout that will not parse is still 66, not gone" {
  # The gone verdict requires EMPTY stdout. A truncated or corrupt payload is a kitty that answered
  # badly, not a window that vanished, and reading it as gone would close on a parse failure.
  LS_RC=1; printf '{"partial":' > "$LS_OUT"; printf 'No matching windows\n' > "$LS_ERR"
  run "$SHIM" session close -f -s 300 --expect-cmdline-match '--agent-name w2-pin'
  [ "$status" -eq 66 ]
  [ "$(attempts)" = "0" ]
}

@test "RC-6 CONTROL: empty stdout WITHOUT the kitty message is still 66 — a silent rc is not proof" {
  # rc 1 and nothing at all is kitty failing to answer (socket gone, permission, crash). The
  # evidence for gone is kitty SAYING so; absence of evidence stays a refusal.
  LS_RC=1; : > "$LS_OUT"; : > "$LS_ERR"
  run "$SHIM" session close -f -s 300 --expect-cmdline-match '--agent-name w2-pin'
  [ "$status" -eq 66 ]
  [ "$(attempts)" = "0" ]
}

@test "RC-6 CONTROL: kitty rc 0 with the message on stderr is NOT gone — the rc is half the proof" {
  LS_RC=0; printf 'No matching windows\n' > "$LS_ERR"
  run "$SHIM" session close -f -s 300 --expect-cmdline-match '--agent-name w2-pin'
  [ "$status" -eq 0 ]
  closed
}

@test "RC-6 CONTROL: with NO pin supplied the gone path is never consulted — today's behaviour" {
  # Neither flag means the whole identity block is SKIPPED, so 68 is unreachable on this path no
  # matter what kitty says. What an unpinned close of a vanished pane meets instead is the composer
  # guard, which cannot read it and refuses 67 — exactly as it did before this change. Asserting 67
  # rather than 0 is the honest expectation: the unpinned path is untouched, not improved. (Whether
  # an unpinned gone pane SHOULD still cost a 67 is a real question and deliberately out of RC-6:
  # the licensed change is the pin two-state collapse, not a new permissive default.)
  gone_window
  run "$SHIM" session close -f -s 300
  [ "$status" -eq 67 ]
  [ "$(attempts)" = "0" ]
}

# ── red-on-mutation: the equivalence guard must be killable, or it guards nothing ─────────

mutate() { # $1=anchor $2=replacement -> path to the mutant
  local m="$BATS_TEST_TMPDIR/mutant-$$.sh"
  ANCHOR="$1" REPL="$2" python3 -c '
import os, sys
src = open(sys.argv[1]).read()
a, b = os.environ["ANCHOR"], os.environ["REPL"]
assert src.count(a) == 1, "anchor appears %d times" % src.count(a)
open(sys.argv[2], "w").write(src.replace(a, b))' "$SHIM" "$m" || return 1
  chmod +x "$m"
  bash -n "$m" || { echo "mutant does not parse" >&2; return 1; }
  cmp -s "$SHIM" "$m" && { echo "mutant is identical to the subject" >&2; return 1; }
  printf '%s' "$m"
}

@test "MUTANT: dropping the len(rows) != 1 test makes the two-window payload close — the guard has power" {
  # The equivalence guard above is green on both sides of the fix, so on its own it proves nothing.
  # Cutting the ambiguity test out of the shipped script must turn it red, or it was never testing
  # anything (memory: a-guard-can-test-a-proxy).
  # The anchor must be UNIQUE: `if len(rows) != 1:` appears three times in the shim (identity_ok
  # plus both composer_state blocks), so it selects nothing. Anchor on the stderr line that only
  # identity_ok writes, and cut the branch by making its guard unreachable.
  local m; m="$(mutate 'if len(rows) != 1:
    sys.stderr.write("expected exactly 1 window with id' 'if False:
    sys.stderr.write("expected exactly 1 window with id')" || { echo "$m"; return 1; }
  cat > "$LS_OUT" <<'JSON'
[{"id":1,"tabs":[{"id":1,"windows":[{"id":300,"columns":100,"pid":1,"env":{"KITTY_PID":"4242"},"foreground_processes":[{"cmdline":["/opt/claude/bin/claude.exe","--agent-id","w2-pin@session-x","--agent-name","w2-pin"]}]},{"id":300,"columns":100,"pid":2,"env":{"KITTY_PID":"4242"},"foreground_processes":[{"cmdline":["/opt/claude/bin/claude.exe","--agent-id","w2-pin@session-x","--agent-name","w2-pin"]}]}]}]}]
JSON
  # The composer guard runs AFTER the pin and has its own `len(rows) != 1` test, so on a two-window
  # payload it refuses 67 on its own and masks the mutant entirely — the pin would look alive when
  # it is dead. Turn that second gate off (its own documented escape hatch) so this observes the
  # PIN and nothing else; the un-mutated arm above keeps the guard on and still reads 66.
  CC_CLOSE_COMPOSER_GUARD=off run "$m" session close -f -s 300 --expect-cmdline-match '--agent-name w2-pin'
  [ "$status" -eq 0 ]
}

@test "MUTANT: dropping the empty-stdout test makes a corrupt payload read as gone" {
  # The other direction: the gone branch must require EMPTY stdout, not merely a non-zero rc.
  local m; m="$(mutate '[ ! -s "$_out" ]' '[ -n "" ] || :')" || { echo "$m"; return 1; }
  LS_RC=1; printf '{"partial":' > "$LS_OUT"; printf 'No matching windows\n' > "$LS_ERR"
  run "$m" session close -f -s 300 --expect-cmdline-match '--agent-name w2-pin'
  [ "$status" -eq 68 ]
}
