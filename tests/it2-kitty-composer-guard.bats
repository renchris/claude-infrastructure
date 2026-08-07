#!/usr/bin/env bats
# bin/it2-kitty `close`: the composer guard.
#
# A composer buffer lives ONLY in process memory — history.jsonl is submit-keyed, `queue-operation`
# is Enter-keyed, and a transcript is not born until the first submit (measured 85 s after session
# start). So an autonomous close of a pane holding unsent text destroys it with no recovery path.
# The guard refuses unless the pane is POSITIVELY PROVEN to hold no composer text, read live from
# the screen buffer (docs/research/pane-theft-composer-guard.md §3).
#
# The two assertions that carry this suite are the ones that keep the guard SHIPPABLE rather than
# merely safe, because each is a common case a two-state abstain rule would have retired:
#
#   · a pane at a SHELL PROMPT closes.  handoff-fire types /exit, ps-polls until CC is gone, and only
#     then closes — so every self-close hands this verb a shell, which has no composer region. The
#     research doc's §3.3 pseudocode refuses there, which would have turned the fleet's most common
#     autonomous close into a 4-retry HUSK-PANE desk page.
#   · a pane showing a DIM PLACEHOLDER closes.  CC renders "Press up to edit queued messages" and
#     queued-prompt previews inside the same rule pair as real input; 4 of 27 live windows were in
#     that state. A plain-text read calls them NON-EMPTY and refuses to close a perfectly safe pane.
#
# Both have a red-on-mutation control at the bottom: cut the correction out of the shipped script and
# the corresponding assertion must FAIL, or the assertion was never testing the correction.
#
# Behavioural: the shipped bin/it2-kitty runs against a stub `kitty` that records argv and serves a
# scripted screen, so these observe what the real script would have asked the real kitty to do.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude"
  REPO="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  SHIM="$REPO/bin/it2-kitty"
  [ -x "$SHIM" ] || skip "bin/it2-kitty not found or not executable at $SHIM"

  BIN="$BATS_TEST_TMPDIR/bin"; mkdir -p "$BIN"
  export KITTY_ARGV="$BATS_TEST_TMPDIR/kitty-argv.log"
  export SCREEN="$BATS_TEST_TMPDIR/screen.txt"   # what get-text serves
  # JSON booleans, lowercase — kitty emits `true`/`false` and a Python-style `True` makes json.load
  # fail, which the guard correctly reads as UNKNOWN. That failure is UNIFORM across the suite and so
  # indicts the fixture, never the subject (memory: uniform-error-ratio-indicts-the-model).
  export ALT=true                                # in_alternate_screen for the stub window
  export LS_RC=0 TEXT_RC=0                       # force RPC failures

  cat > "$BIN/kitty" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >> "$KITTY_ARGV"
for a in "$@"; do
  if [ "$a" = "ls" ]; then
    [ "${LS_RC:-0}" = 0 ] || exit "$LS_RC"
    printf '[{"id":1,"tabs":[{"id":1,"windows":[{"id":300,"columns":100,"in_alternate_screen":%s,"is_focused":false,"pid":1,"cwd":"/tmp","foreground_processes":[]}]}]}]\n' "${ALT:-true}"
    exit 0
  fi
  if [ "$a" = "get-text" ]; then
    [ "${TEXT_RC:-0}" = 0 ] || exit "$TEXT_RC"
    cat "$SCREEN" 2>/dev/null
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
}

RULE='──────────────────────────────────────────────────────────────────────────────────────────────'
NBSP=$' '

# Compose a screen. $1 = the composer body lines (already ANSI-decorated), joined verbatim.
screen() { printf '%s\n%s\n%s\n' "$RULE" "$1" "$RULE" > "$SCREEN"; }
closed()  { grep -q 'close-window --match id:300' "$KITTY_ARGV"; }
# `grep -c` PRINTS 0 and EXITS 1 on no-match, so a `|| echo 0` tail emits "0\n0" and every
# refusal assertion fails while looking like the guard let the close through.
attempts(){ local n; n="$(grep -c 'close-window' "$KITTY_ARGV" 2>/dev/null)" || n=0; printf '%s' "${n:-0}"; }

# ── the guard refuses what it exists to protect ──────────────────────────────────────────

@test "a pane holding unsent composer text is NOT closed" {
  screen "$(printf '\033[m❯%sWow. So it was never destroyed, it was just hidden. Why?' "$NBSP")"
  run "$SHIM" session close -f -s 300
  [ "$status" -eq 67 ]
  [ "$(attempts)" = "0" ]
}

@test "the refusal explains that the text exists nowhere on disk, not just that it refused" {
  # An agent reading this must learn WHY, or the next caller reaches for the env override.
  screen "$(printf '\033[m❯%sdraft text' "$NBSP")"
  run "$SHIM" session close -f -s 300
  echo "$output" | grep -qi 'only in this process'
  echo "$output" | grep -qi 'history.jsonl'
}

@test "text on a CONTINUATION line is caught — the first line alone is not the composer" {
  screen "$(printf '\033[m❯%s\n\033[m  second line carries the words' "$NBSP")"
  run "$SHIM" session close -f -s 300
  [ "$status" -eq 67 ]
  [ "$(attempts)" = "0" ]
}

@test "a LABELLED top rule still reads as a composer — ^─+\$ would miss it entirely" {
  # Agent panes draw "──── @name ──". Anchoring the rule regex mis-reads those as having no
  # composer at all, i.e. the guard silently stops guarding on exactly the panes agents close.
  printf '%s\n%s\n%s\n' \
    "────────────────────────────────────── @composer-guard ──────────────────────────────────────" \
    "$(printf '\033[m❯%sreal words typed by a person' "$NBSP")" \
    "$RULE" > "$SCREEN"
  run "$SHIM" session close -f -s 300
  [ "$status" -eq 67 ]
  [ "$(attempts)" = "0" ]
}

@test "the composer is SNAPSHOT before the refusal — after the close it is worth nothing" {
  screen "$(printf '\033[m❯%sirreplaceable' "$NBSP")"
  run "$SHIM" session close -f -s 300
  [ "$status" -eq 67 ]
  run bash -c "cat '$HOME'/.claude/logs/composer-snapshots/*win300.txt 2>/dev/null"
  echo "$output" | grep -q 'irreplaceable'
}

# ── …and refuses when it cannot SEE, because unreadable is not empty ──────────────────────

@test "a TUI pane with no readable composer region (permission modal) is refused" {
  ALT=true; printf 'Do you want to proceed?\n 1. Yes\n 2. No\n' > "$SCREEN"
  run "$SHIM" session close -f -s 300
  [ "$status" -eq 67 ]
  [ "$(attempts)" = "0" ]
  echo "$output" | grep -qi 'could not be read'
}

@test "an RPC failure refuses — a guard that cannot read must never assume empty" {
  screen "$(printf '\033[m❯%s' "$NBSP")"
  LS_RC=1 run "$SHIM" session close -f -s 300
  [ "$status" -eq 67 ]
  TEXT_RC=1 run "$SHIM" session close -f -s 300
  [ "$status" -eq 67 ]
  [ "$(attempts)" = "0" ]
}

@test "a BLANK screen read refuses — zero bytes proves nothing about the pane" {
  : > "$SCREEN"
  run "$SHIM" session close -f -s 300
  [ "$status" -eq 67 ]
  [ "$(attempts)" = "0" ]
}

# ── the common cases the guard must NOT retire ───────────────────────────────────────────

@test "an EMPTY composer closes normally" {
  screen "$(printf '\033[m❯%s' "$NBSP")"
  run "$SHIM" session close -f -s 300
  [ "$status" -eq 0 ]
  closed
}

@test "a pane at a SHELL PROMPT closes — this is what every self-close hands us" {
  # handoff-fire.sh:2795 — "The /exit half has already landed (CC is gone)". The pane is a shell
  # with no composer region at all. Refusing here breaks self-close and pages HUSK-PANE every time.
  ALT=false; printf 'chrisren@host ~ %% \n' > "$SCREEN"
  run "$SHIM" session close -f -s 300
  [ "$status" -eq 0 ]
  closed
}

@test "a DIM placeholder is not content — CC's own hint text must not block a close" {
  # Measured live: "Press up to edit queued messages" and queued-prompt previews arrive as SGR 2.
  screen "$(printf '\033[m\033[38:2:153:153:153m❯%s\033[22;2;39mPress up to edit queued messages' "$NBSP")"
  run "$SHIM" session close -f -s 300
  [ "$status" -eq 0 ]
  closed
}

@test "the queued-prompt preview a fired peer shows is also dim, and also closes" {
  screen "$(printf '\033[m\033[38:2:202:138:4m❯%s\033[22;2;39mself-close the pane' "$NBSP")"
  run "$SHIM" session close -f -s 300
  [ "$status" -eq 0 ]
  closed
}

# ── the escape hatch, and the flag that must NOT be one ──────────────────────────────────

@test "CC_CLOSE_COMPOSER_GUARD=off bypasses — the drift/e2e harnesses need it" {
  screen "$(printf '\033[m❯%sreal text' "$NBSP")"
  CC_CLOSE_COMPOSER_GUARD=off run "$SHIM" session close -f -s 300
  [ "$status" -eq 0 ]
  closed
}

@test "-f does NOT bypass the guard — every automated caller passes it" {
  # An -f exemption would be a guard that never runs in production and only ever in tests.
  screen "$(printf '\033[m❯%sreal text' "$NBSP")"
  run "$SHIM" session close -f -s 300
  [ "$status" -eq 67 ]
  run "$SHIM" session close -s 300
  [ "$status" -eq 67 ]
  [ "$(attempts)" = "0" ]
}

@test "exit 67 is distinct from 66 — an identity refusal and a composer refusal differ" {
  # A caller that retries must be able to tell "wrong pane, re-derive the id" from "right pane,
  # it is holding text". Collapsing them onto one code makes both unactionable.
  grep -q 'exit 66' "$SHIM"
  grep -q 'exit 67' "$SHIM"
}

# ── red-on-mutation: each correction is cut out, and its assertion must break ─────────────
#
# Per-site, because the two corrections are independent and a single mutant would attribute the
# coverage of both to whichever assertion happened to fail first. Each mutant is syntax-checked
# before use — a malformed one reddens everything, which reads as maximal coverage and is worth
# nothing (memory: per-site-mutation-attributes-coverage).

mutate() { # $1=anchor $2=replacement -> path to the mutant, or fail
  local m="$BATS_TEST_TMPDIR/mutant-$$.sh"
  [ "$(grep -cF "$1" "$SHIM")" = 1 ] || { echo "anchor not unique: $1" >&2; return 1; }
  # LITERAL replacement. awk's sub() takes a REGEX, and these anchors carry `(`, `)` and `.` — the
  # NO-TUI mutant silently applied nothing, so the control ran the UNMUTATED script and reported the
  # subject healthy. A mutant that cannot mutate is a control that cannot fail, so the three
  # properties are asserted rather than assumed: it parses, it is UNIQUE, and it actually DIFFERS.
  ANCHOR="$1" REPL="$2" python3 -c '
import os, sys
src = open(sys.argv[1]).read()
a, b = os.environ["ANCHOR"], os.environ["REPL"]
assert src.count(a) == 1, "anchor appears %d times" % src.count(a)
open(sys.argv[2], "w").write(src.replace(a, b))' "$SHIM" "$m" || return 1
  chmod +x "$m"
  bash -n "$m" || { echo "mutant does not parse" >&2; return 1; }
  cmp -s "$SHIM" "$m" && { echo "mutant is identical to the subject — it cannot fail" >&2; return 1; }
  printf '%s' "$m"
}

@test "META: a mutant that changes nothing is rejected, not silently run" {
  # The control's own control. Without this, a stale anchor degrades every mutation test below into
  # a green that proves the subject works — the opposite of what it claims to prove.
  run mutate 'this string is not in the file' 'x'
  [ "$status" -ne 0 ]
}

@test "CONTROL: without the NO-TUI split, the shell-prompt pane is refused" {
  local m; m="$(mutate 'print("UNKNOWN" if alt else "NO-TUI")' 'print("UNKNOWN")')"
  ALT=false; printf 'chrisren@host ~ %% \n' > "$SCREEN"
  run "$m" session close -f -s 300
  [ "$status" -eq 67 ]           # the mutant breaks self-close — so the real assertion tests it
  [ "$(attempts)" = "0" ]
}

@test "CONTROL: without dim-awareness, CC's placeholder blocks the close" {
  local m; m="$(mutate 'elif tok == "2": dim = True' 'elif tok == "2": dim = False')"
  screen "$(printf '\033[m\033[38:2:153:153:153m❯%s\033[22;2;39mPress up to edit queued messages' "$NBSP")"
  run "$m" session close -f -s 300
  [ "$status" -eq 67 ]           # the mutant refuses a safe pane — so the real assertion tests it
  [ "$(attempts)" = "0" ]
}

@test "CONTROL: without the guard at all, a pane holding text is destroyed" {
  # The bug this whole file exists to prevent, reproduced against the unguarded path.
  screen "$(printf '\033[m❯%sirreplaceable draft' "$NBSP")"
  CC_CLOSE_COMPOSER_GUARD=off run "$SHIM" session close -f -s 300
  [ "$status" -eq 0 ]
  closed                         # kitty WAS asked to destroy it — the guard is the only thing stopping this
}
