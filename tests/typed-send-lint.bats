#!/usr/bin/env bats
# typed-send-lint — the RATCHET that stops a raw COMMAND LINE being typed into an interactive pane.
#
# The failure it exists for is in-tree history, not a hypothetical. This operator's zsh runs with
# `setopt CORRECT`: a command line whose first word the shell does not recognise — because a paste
# raced ZLE, because autosuggestions rewrote the buffer, because the pane was still booting — does
# not run and does not fail. The pane parks forever on
#     zsh: correct 'clade' to 'claude' [nyae]?
# waiting for a keypress from a human who is not there, while the fire reports success. Measured
# 2026-07-26: a 6m40s wedge that lost a whole dispatched work item silently. The sanctioned helpers
# (it2_type_verified / _it2_type_line in scripts/handoff-fire.sh, osa_type_verified in
# scripts/lib/cc-type-verified.sh) exist to convert that silent hang into a loud failure: they paste
# the line, READ THE PANE BACK to prove it landed intact, and only then send the Enter.
#
# Five properties are proved here, and all five matter:
#   • it DISCRIMINATES — red on every raw primitive, green on the same site once routed through a
#     helper. A lint that cannot show the FIX clearing it is not enforcing a rule, it is a tax;
#   • the SANCTIONED-HELPER exemption is scoped to the FUNCTION, in both directions — the same body
#     under an unsanctioned name is red, and a raw send after the helper closes is red. A file-wide
#     exemption would make handoff-fire.sh (which owns the helpers AND 3700 other lines) unreachable
#     by the rule, and would let anyone launder a raw send by wrapping it in a function;
#   • it does not fire on PROSE — this repo writes "keystroke", "write text" and "session send" into
#     comments and status strings constantly, almost always to say it does NOT do one. A detector
#     that reports text ABOUT the defect reports the fix as the bug
#     (memory: detector-matching-its-own-skill-description);
#   • it is GREEN on the tree as it stands — a lint that ships standing-red is rot, and the nightly
#     runs every scripts/*lint*.sh, so one false red poisons the whole nightly signal;
#   • it RUNS OVER THE REAL TREE from here (the last test). tests/handoff-payload-gates.bats:11
#     records scripts/pane-id-lint.sh sitting on trunk with ZERO call sites — "orphaned detection,
#     not a gate". This suite is the call site that keeps that from happening twice.
#
# Assertions use the explicit `|| { …; false; }` form throughout: a non-final `[[ ]]` is
# errexit-EXEMPT under bats and would be a DEAD assertion that can never fail
# (memory: bats-dead-assertions-errexit-exemptions).
#
# SC2016 is disabled file-wide: every fixture below must carry a LITERAL `$LAUNCHER`, `$id` or
# `$'\r'` and must NOT expand it — expansion would substitute this suite's environment into the
# sample being matched and quietly destroy the controls, which is the difference between a control
# and a decoration.
# shellcheck disable=SC2016

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LINT="$REPO/scripts/typed-send-lint.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"   # dogfood the sibling hermeticity rule
  # Nothing here fires a pane — the pin is free, and the sibling ratchet's scope test is a plain
  # `grep -F handoff-fire` over the whole file, which this suite's header trips by NAMING the file
  # the sanctioned helpers live in. Pinning is the right answer to that: the alternative is deleting
  # accurate documentation to satisfy a textual detector.
  export CC_FIRE_CAPACITY_GATE=off
  FIX="$BATS_TEST_TMPDIR/fix"; mkdir -p "$FIX"
}

# mk <case> <body…> — a scan root $FIX/<case> holding one shell file under scripts/. Built with
# printf and not a heredoc: bats' preprocessor rewrites heredoc bodies in a test file, and a fixture
# that does not reach disk byte-for-byte is not a control.
mk() {
  local case_="$1"; shift
  mkdir -p "$FIX/$case_/scripts"
  { printf '#!/bin/bash\n'; printf '%s\n' "$@"; } > "$FIX/$case_/scripts/probe.sh"
}

@test "1: the lint's own --selftest passes, and reports every case it ran" {
  run bash "$LINT" --selftest
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  # The count is COMPUTED by the selftest, so this asserts the FORM (n/n, all passed) and a floor,
  # rather than a literal that would drift every time a case is added.
  n="$(printf '%s' "$output" | sed -n 's/.*--selftest: \([0-9]*\)\/\([0-9]*\) .*/\1 \2/p')"
  [ -n "$n" ] || { echo "no n/n count in selftest output: $output"; false; }
  ran="${n% *}"; total="${n#* }"
  [ "$ran" = "$total" ] || { echo "selftest reported $ran/$total — not all cases passed"; false; }
  [ "$ran" -ge 30 ] || { echo "selftest shrank to $ran cases — coverage was removed, not added"; false; }
}

@test "2: RED on a bare osascript \`write text\` of a launch command (THE scar shape)" {
  mk scar 'osascript <<OSA' \
          'tell application "iTerm2"' \
          '  set newWin to (create window with default profile)' \
          '  tell current session of newWin to write text "exec /bin/bash $LAUNCHER"' \
          'end tell' \
          'OSA'
  run bash "$LINT" "$FIX/scar"
  [ "$status" -eq 1 ] || { echo "expected rc 1, got $status: $output"; false; }
  printf '%s' "$output" | grep -q 'TYPED-SEND' || { echo "no TYPED-SEND verdict: $output"; false; }
}

@test "3: GREEN once the SAME site is routed through osa_type_verified — the fix clears the lint" {
  mk fixed '. "$ROOT/scripts/lib/cc-type-verified.sh"' \
           'osa_type_verified "$pane" "exec /bin/bash $LAUNCHER" || exit 3'
  run bash "$LINT" "$FIX/fixed"
  [ "$status" -eq 0 ] || { echo "the routed site was flagged — the fix does not clear the lint: $output"; false; }
}

@test "4: RED on every other way to make a shell run a line (it2, async, do script, keystroke, tmux)" {
  mk it2 '"$IT2" session send -s "$id" "exec /bin/bash $LAUNCHER"'
  run bash "$LINT" "$FIX/it2"
  [ "$status" -eq 1 ] || { echo "a raw it2 session send went green: $output"; false; }

  mk async 'async_send_text("exec /bin/bash $LAUNCHER")'
  run bash "$LINT" "$FIX/async"
  [ "$status" -eq 1 ] || { echo "a raw async_send_text went green: $output"; false; }

  mk doscript 'osascript -e "tell application \"Terminal\" to do script \"exec /bin/bash $L\""'
  run bash "$LINT" "$FIX/doscript"
  [ "$status" -eq 1 ] || { echo "an AppleScript do script went green: $output"; false; }

  mk keyst "osascript -e 'tell application \"System Events\" to keystroke \"claude\"'"
  run bash "$LINT" "$FIX/keyst"
  [ "$status" -eq 1 ] || { echo "an AppleScript keystroke went green: $output"; false; }

  mk tmx 'tmux send-keys -t "$pane" "exec /bin/bash $LAUNCHER" C-m'
  run bash "$LINT" "$FIX/tmx"
  [ "$status" -eq 1 ] || { echo "a tmux send-keys went green: $output"; false; }
}

@test "5: the sanctioned helper's OWN internals are green — and ONLY under a sanctioned name" {
  # The helper necessarily contains the raw primitive; that is what a helper IS.
  mk sanctioned 'osa_type_verified() { # $1=pane $2=command' \
                '  osascript -e "tell application \"iTerm2\" to tell session id \"$1\" to write text \"$2\""' \
                '}'
  run bash "$LINT" "$FIX/sanctioned"
  [ "$status" -eq 0 ] || { echo "the sanctioned helper's own internals were flagged: $output"; false; }

  # THE OTHER DIRECTION, and the case the whole exemption turns on: byte-identical body, under a
  # name that is not sanctioned. If the rule keyed on "it is inside a function", wrapping a raw send
  # in one would defeat the lint entirely.
  mk unsanctioned 'osa_write_raw() { # $1=pane $2=command' \
                  '  osascript -e "tell application \"iTerm2\" to tell session id \"$1\" to write text \"$2\""' \
                  '}'
  run bash "$LINT" "$FIX/unsanctioned"
  [ "$status" -eq 1 ] || { echo "an identical body under a NON-sanctioned name went green — the exemption is a hole anyone can walk through: $output"; false; }
}

@test "6: the exemption ends where the FUNCTION ends, not where the file ends" {
  # handoff-fire.sh owns both helpers AND 3700 other lines. A file-wide exemption would put the file
  # most likely to grow a new raw send permanently out of jurisdiction.
  mk after '_it2_type_line() { # $1=it2-bin $2=session-id $3=line' \
           '  hf_bounded "$1" session send -s "$2" "$wire" || return 1' \
           '}' \
           '"$IT2" session send -s "$sid" "exec /bin/bash $LAUNCHER"'
  run bash "$LINT" "$FIX/after"
  [ "$status" -eq 1 ] || { echo "a raw send AFTER the helper closed went green — the exemption is file-wide: $output"; false; }
  printf '%s' "$output" | grep -q 'probe.sh:5' || { echo "the wrong line was blamed (expected the post-helper send at :5): $output"; false; }
}

@test "7: a CONTROL-CHARACTER payload is not a typed command line — but a command payload is" {
  # handoff-fire.sh:527/537/1664/1747. A bare CR or Ctrl-U types no first word, so there is nothing
  # for the shell to mis-correct; flagging these would bury the real signal under the helpers' own
  # scrub-and-submit sends.
  mk ctrl '"$IT2" session send -s "$id" $'"'"'\r'"'"' >/dev/null 2>&1 || true' \
          '"$IT2" session send -s "$id" $'"'"'\x15'"'"' >/dev/null 2>&1 || true' \
          '[ "$waited" = 60 ] && hf_bounded "$IT2" session send -s "$SID" $'"'"'\r'"'"' >/dev/null 2>&1 || true'
  run bash "$LINT" "$FIX/ctrl"
  [ "$status" -eq 0 ] || { echo "a control-character payload was flagged as a typed command line: $output"; false; }

  # Same transport, same wrapper, same redirections — only the payload differs. Without this half,
  # "it is a control character" could be silently exempting the whole transport.
  mk ctrl_bad '"$IT2" session send -s "$id" "claude --resume $SID" >/dev/null 2>&1 || true'
  run bash "$LINT" "$FIX/ctrl_bad"
  [ "$status" -eq 1 ] || { echo "a COMMAND payload on the same transport went green — the exemption is on the transport, not the payload: $output"; false; }
}

@test "7b: the control exemption survives an fd-prefixed redirect — \`2>/dev/null\` is the same send as \`>/dev/null 2>&1\`" {
  # bin/reso-keepalive:79-80, 2026-08-12 — an off-box RED that was the DETECTOR, not the subject.
  # A redirection is `[0-9]*[<>]`, but the payload cut ran to the first `[>|;&]` and so left the
  # FILE-DESCRIPTOR number behind as a word of its own: `$'\r' 2>/dev/null` ended in `2`, not the
  # escape, and a bare CR read as a typed command line. Case 7's fixture, and all four real
  # handoff-fire sites, spell it `>/dev/null 2>&1` — no digit before the first operator — so nothing
  # in this suite could tell the two spellings apart, and they are the same send.
  mk ctrl_fd '"$IT2" session send -s "$id" $'"'"'\r'"'"' 2>/dev/null; sleep 0.3' \
             '"$IT2" session send -s "$id" $'"'"'\x15'"'"' 1>/dev/null 2>&1'
  run bash "$LINT" "$FIX/ctrl_fd"
  [ "$status" -eq 0 ] || { echo "a control payload followed by an fd-prefixed redirect was flagged as a typed command line: $output"; false; }

  # The other direction, or the cut could be swallowing the payload rather than the fd number: same
  # fd spelling, same wrapper, COMMAND payload.
  mk ctrl_fd_bad '"$IT2" session send -s "$id" "claude --resume $SID" 2>/dev/null; sleep 0.5'
  run bash "$LINT" "$FIX/ctrl_fd_bad"
  [ "$status" -eq 1 ] || { echo "a COMMAND payload with the same fd-prefixed redirect went green — the cut is eating the payload, not the fd: $output"; false; }
}

@test "8: prose and non-typing osascript are not findings — the same verb in a tell block is" {
  mk prose '# with spaces survives the osascript `write text` shell.' \
           '# re-engagement must NEVER keystroke a live composer.' \
           '# IT2 is read-only here (session list) — NEVER `session send`.' \
           'osascript -e '"'"'display notification "gate red" with title "claude"'"'"' || true' \
           'osascript -e '"'"'display dialog "continue?" buttons {"no","yes"}'"'"' || true' \
           'badp "stunned: KEYSTROKED a live composer (F7 regression)"' \
           'notify "desk idle" "enqueued to the inbox — no keystroke \"here\""   # never a write text "cmd"'
  run bash "$LINT" "$FIX/prose"
  [ "$status" -eq 0 ] || { echo "prose / display notification was reported as the defect: $output"; false; }

  # …and the judgement must cut both ways, or it is just the rule switched off: identical verb,
  # identical quoting, moved into a context where it really does type.
  mk realsend 'osascript -e "tell current session of newWin to write text \"$cmd\"" >/dev/null'
  run bash "$LINT" "$FIX/realsend"
  [ "$status" -eq 1 ] || { echo "the same verb inside an osascript tell went green: $output"; false; }
}

@test "9: the typed-send-lint:allow hatch suppresses inline and on the line above — a bare comment does not" {
  mk hatch1 '"$IT2" session send -s "$id" "exec /bin/bash $L"   # typed-send-lint:allow — fixture'
  run bash "$LINT" "$FIX/hatch1"
  [ "$status" -eq 0 ] || { echo "an inline hatch did not suppress: $output"; false; }

  mk hatch2 '# typed-send-lint:allow — reviewed: the pane is proven dead, this is the teardown probe' \
            '"$IT2" session send -s "$id" "exec /bin/bash $L"'
  run bash "$LINT" "$FIX/hatch2"
  [ "$status" -eq 0 ] || { echo "a preceding-line hatch did not suppress: $output"; false; }

  mk hatch3 '# an ordinary explanatory comment about what this launcher does' \
            '"$IT2" session send -s "$id" "exec /bin/bash $L"'
  run bash "$LINT" "$FIX/hatch3"
  [ "$status" -eq 1 ] || { echo "any comment now works as an exemption: $output"; false; }
}

@test "10: the ratchet SHRINKS — grandfathered is green, fixed-but-still-listed is RED" {
  mk shrink '"$IT2" session send -s "$id" "exec /bin/bash $L"'
  CC_TYPEDSEND_ALLOWLIST="scripts/probe.sh" run bash "$LINT" "$FIX/shrink"
  [ "$status" -eq 0 ] || { echo "a grandfathered violation blocked: $output"; false; }

  mk shrink2 'osa_type_verified "$id" "exec /bin/bash $L" || exit 3'
  CC_TYPEDSEND_ALLOWLIST="scripts/probe.sh" run bash "$LINT" "$FIX/shrink2"
  [ "$status" -eq 1 ] || { echo "a fixed file kept its allowlist line and still passed — the ratchet is a permanent exemption list: $output"; false; }
  printf '%s' "$output" | grep -q 'RATCHET' || { echo "no RATCHET verdict: $output"; false; }
}

@test "11: a path::function ratchet entry grandfathers ONE function, not the whole file" {
  # The narrow form is what keeps handoff-fire.sh under jurisdiction while its two legacy senders are
  # grandfathered. A bare path would exempt every future raw send in a 3700-line file.
  mk narrow 'as_write() { # $1=session $2=text' \
            '  osascript -e "tell application \"iTerm2\" to tell session id \"$1\" to write text \"$2\""' \
            '}' \
            'elsewhere() {' \
            '  "$IT2" session send -s "$id" "exec /bin/bash $L"' \
            '}'
  CC_TYPEDSEND_ALLOWLIST="scripts/probe.sh::as_write" run bash "$LINT" "$FIX/narrow"
  [ "$status" -eq 1 ] || { echo "a narrow entry exempted the whole file: $output"; false; }
  printf '%s' "$output" | grep -q 'in elsewhere()' || { echo "the second site was not the one blamed: $output"; false; }

  # The other half: with BOTH functions listed the file is clean, so the failure above is really
  # about scope and not about the entry failing to match at all.
  CC_TYPEDSEND_ALLOWLIST="$(printf 'scripts/probe.sh::as_write\nscripts/probe.sh::elsewhere\n')" run bash "$LINT" "$FIX/narrow"
  [ "$status" -eq 0 ] || { echo "a path::function entry did not grandfather its own function: $output"; false; }
}

@test "12: an entry out of the scan root's VIEW is not stale — but on a full-tree run, absence is" {
  # Both arms of one judgement, and the asymmetry is the whole point. The allowlist is rooted at the
  # REPO while the scan root is a parameter, so judging "this entry matched nothing" against a
  # two-file fixture reported all five real entries stale and made every narrowed scan unusable.
  mk oov 'osa_type_verified "$id" "exec /bin/bash $L" || exit 3'
  CC_TYPEDSEND_ALLOWLIST="scripts/somewhere-else.sh" run bash "$LINT" "$FIX/oov"
  [ "$status" -eq 0 ] || { echo "an entry for a path outside the scan root was reported stale: $output"; false; }

  # On the full tree, where every entry IS in view, a path that no longer exists is dead weight and
  # the ratchet must say so — otherwise a renamed file leaves a line nothing will ever remove.
  CC_TYPEDSEND_ALLOWLIST="scripts/this-file-does-not-exist.sh" run bash "$LINT" "$REPO"
  [ "$status" -eq 1 ] || { echo "a dangling entry survived a full-tree run: $output"; false; }
  printf '%s' "$output" | grep -q 'no longer exists' || { echo "the dangling entry was not named as such: $output"; false; }
}

@test "13: an unrunnable detector is a NON-VERDICT (exit 2), never a named violation" {
  # A check whose own tool cannot run must not answer. The sibling hermeticity ratchet fabricated
  # findings NAMING GOOD FILES under fork pressure, which reads as an attributable RED and sends
  # people to fix code that was never broken (memory: named-failure-vs-no-verdict).
  mk killed '"$IT2" session send -s "$id" "exec /bin/bash $L"'
  stub="$BATS_TEST_TMPDIR/stub"; mkdir -p "$stub"
  printf '#!/bin/bash\nexit 2\n' > "$stub/awk"; chmod +x "$stub/awk"
  PATH="$stub:$PATH" CC_TYPEDSEND_ALLOWLIST="" run bash "$LINT" "$FIX/killed"
  [ "$status" -eq 2 ] || { echo "expected the non-verdict rc 2, got $status: $output"; false; }
! printf '%s' "$output" | grep -q 'TYPED-SEND' || { echo "an unrunnable detector fabricated a finding: $output"; false; }
  printf '%s' "$output" | grep -q 'UNUSABLE' || { echo "the non-verdict was not announced: $output"; false; }
}

@test "14: LOUD (exit 2) on a missing scan root and on a root with no deployed layers" {
  run bash "$LINT" "$FIX/does-not-exist"
  [ "$status" -eq 2 ] || { echo "a missing root did not exit 2: $output"; false; }

  mkdir -p "$FIX/nolayers/docs"
  run bash "$LINT" "$FIX/nolayers"
  [ "$status" -eq 2 ] || { echo "a root with no deployed layers did not exit 2: $output"; false; }
}

@test "15: non-shell files and tests/ subtrees are out of jurisdiction" {
  mkdir -p "$FIX/scope/scripts" "$FIX/scope/hooks/tests"
  printf 'tell current session of w to write text "exec /bin/bash $L"\n' > "$FIX/scope/scripts/doc.md"
  printf '#!/bin/bash\n"$IT2" session send -s "$id" "exec /bin/bash $L"\n' > "$FIX/scope/hooks/tests/t.sh"
  printf '#!/bin/bash\ntrue\n' > "$FIX/scope/scripts/ok.sh"
  run bash "$LINT" "$FIX/scope"
  [ "$status" -eq 0 ] || { echo "a .md file or a tests/ subtree was scanned: $output"; false; }
}

@test "16: the lint resolves its OWN \$0 — it must not carry a defect of the class it enforces" {
  # Invoked as ~/.claude/scripts/typed-send-lint.sh (a per-file symlink into this checkout), an
  # unresolved ROOT would land in ~/.claude, find none of the layers, and exit 2 forever.
  link="$BATS_TEST_TMPDIR/linked-lint.sh"
  ln -s "$LINT" "$link"
  run bash "$link" --selftest
  [ "$status" -eq 0 ] || { echo "the lint failed when invoked through a symlink: $output"; false; }
}

@test "17: GREEN on the REAL tree — and this run is the lint's CALL SITE" {
  # THE POINT OF THIS TEST. scripts/pane-id-lint.sh sat on trunk with ZERO call sites — "orphaned
  # detection, not a gate" (tests/handoff-payload-gates.bats:11). A detector nothing ever runs is
  # worth exactly nothing, and it rots silently because no signal ever contradicts it. This scan
  # over the real scripts/ hooks/ bin/ is what makes typed-send-lint a gate rather than a file, and
  # it is what fails the day someone adds a raw typed send anywhere in the deployed layers.
  run bash "$LINT" "$REPO"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s' "$output" | grep -q 'clean' || { echo "no clean verdict on the real tree: $output"; false; }
}
