#!/usr/bin/env bats
# notify.sh — the sound + desktop-alert hook (Stop / Notification / PermissionRequest).
#
# WHY THIS SUITE EXISTS: the hook used to read EVENT_TYPE="$1" and NOTHING else — no stdin, no
# payload — so every alert said "Claude needs your approval" and named no session, no directory and
# no command. At ~30 concurrent sessions that is untriageable, and its 2 s debounce was keyed per
# ACCOUNT, so two sessions blocking within the window collapsed into one alert and the second block
# vanished. Both are measured drops, not theory (docs/research/step3-to-step4-pathway-2026-07-31.md
# §2b, §3 Stage A.1/A.2). These tests pin the identity render, the per-session debounce, and every
# fail-open path — a hook that renders nothing is worse than the anonymous alert it replaced.

setup() {
  # HOME is fixtured even though every path this suite exercises is already pinned by an explicit
  # seam: the hook resolves the account label as ${CLAUDE_CONFIG_DIR:-$HOME/.claude}, so an
  # unfixtured HOME is one deleted export away from writing the operator's real config dir. The
  # ratchet is structural on purpose — it must not wait for the day the fallback is taken.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  H="$REPO/hooks/notify.sh"
  export CC_NOTIFY_DIR="$BATS_TEST_TMPDIR/nty"
  mkdir -p "$CC_NOTIFY_DIR"
  # Stub the two side-effecting binaries. osascript records its argv so we can assert on the exact
  # AppleScript that WOULD have been evaluated; afplay is a no-op so the suite stays silent.
  STUB="$BATS_TEST_TMPDIR/bin"; mkdir -p "$STUB"
  printf '#!/bin/bash\nprintf "%%s\\n" "$2" >> "%s/osa.argv"\n' "$CC_NOTIFY_DIR" > "$STUB/osascript"
  printf '#!/bin/bash\nexit 0\n' > "$STUB/afplay"
  chmod +x "$STUB/osascript" "$STUB/afplay"
  export PATH="$STUB:$PATH"
  export NTY_OSA_TIMEOUT_BIN=""            # documented seam: set-but-EMPTY disables the wrapper
  export CLAUDE_CONFIG_DIR="$HOME/.claude-test"
  unset CLAUDE_PROJECT_DIR
}

# a well-formed harness payload: session $1, cwd $2, Bash command $3
payload() { jq -nc --arg s "$1" --arg c "$2" --arg m "$3" \
  '{session_id:$s,cwd:$c,tool_name:"Bash",tool_input:{command:$m}}'; }
osa() { cat "$CC_NOTIFY_DIR/osa.argv" 2>/dev/null; }
fire() { printf '%s' "$1" | "$H" "$2"; }

@test "hook is executable (a non-+x hook is silently skipped by the harness)" {
  [ -x "$H" ]
}

# ── IDENTITY — the alert must NAME the session, the directory and the actual command ─────────────
@test "permission alert renders session + cwd + the real command" {
  fire "$(payload 1a5cf368-aaaa-bbbb-cccc-dddd /Users/x/proj 'git push --force origin main')" permission
  run osa
  [[ "$output" == *'display notification "git push --force origin main"'* ]]
  [[ "$output" == *'with title "Permission · proj"'* ]]
  [[ "$output" == *'subtitle "1a5cf368 · Bash"'* ]]
}

@test "RED CONTROL: the identity assertions fail against the pre-fix anonymous alert" {
  # Guards against the suite passing on a hook that reverted to naming nothing.
  run bash -c 'printf "" | "$1" permission' _ "$H"
  [[ "$(osa)" != *'subtitle'* ]]
  [[ "$(osa)" != *'git push'* ]]
}

@test "the cwd BASENAME is the title, and the session id is shortened to its first uuid group" {
  fire "$(payload 873ec4e0-7f29-46ff-9443-6fc717bc1777 /Users/x/claude-infrastructure 'ls')" permission
  run osa
  [[ "$output" == *'with title "Permission · claude-infrastructure"'* ]]
  [[ "$output" == *'subtitle "873ec4e0 · Bash"'* ]]
  [[ "$output" != *6fc717bc1777* ]]                # the full uuid would crowd out the command
}

@test "a non-Bash tool falls back to file_path, then description, then .message" {
  printf '%s' '{"session_id":"s-w","cwd":"/w","tool_name":"Write","tool_input":{"file_path":"/x/y.ts"}}' | "$H" permission
  [[ "$(osa)" == *'display notification "/x/y.ts"'* ]]
  : > "$CC_NOTIFY_DIR/osa.argv"
  printf '%s' '{"session_id":"s-n","cwd":"/w","message":"Claude is waiting for your input"}' | "$H" question
  [[ "$(osa)" == *'display notification "Claude is waiting for your input"'* ]]
}

@test "each event type keeps its own title and sound" {
  fire "$(payload s-q /w/proj hi)" question
  [[ "$(osa)" == *'with title "Question · proj"'*'sound name "Blow"'* ]]
  : > "$CC_NOTIFY_DIR/osa.argv"
  fire "$(payload s-p /w/proj hi)" plan
  [[ "$(osa)" == *'with title "Plan ready · proj"'*'sound name "Glass"'* ]]
}

# ── APPLESCRIPT SAFETY — the command is MODEL-AUTHORED text inside a string literal ──────────────
# This is the RED-control for a bug that shipped in the first draft: `"` was replaced with `\'`,
# which is a hard AppleScript syntax error (-2741), so EVERY alert whose command contained a quote
# — `git commit -m "…"`, the common case — would have rendered nothing at all. The assertion is
# therefore not "the quote is gone" but "the produced script actually PARSES", checked by running
# the real osascript compiler over it.
@test "a command containing quotes and backslashes still produces a script osascript can parse" {
  fire "$(payload s-inj /w/proj 'git commit -m "fix: \ the thing" && echo "done"')" permission
  script="$(osa)"
  [[ -n "$script" ]]
  bs=$'\\'                                          # a lone backslash, ANSI-C quoted
  [[ "$script" != *"$bs"* ]]                        # no backslash survives into the literal
  # Compile the REAL artifact, unmodified — `if false then <stmt>` parses the whole statement
  # without displaying anything. Rewriting the script into some other shape would test an
  # approximation and pass vacuously (memory control-must-replay-the-real-artifact).
  run /usr/bin/osascript -e "if false then $script"
  [ "$status" -eq 0 ]                               # a -2741 syntax error would fail here
}

@test "RED CONTROL: the parse check can actually fail on a script with a stray escape" {
  # Without this, the test above could pass because osascript accepts anything. This proves the
  # instrument detects exactly the defect that shipped in the first draft.
  # Assemble the bad script from parts so the escape sequence under test is DATA, not something
  # this file has to quote its way around.
  bad="$(printf 'if false then display notification "a%s%sb" with title "t"' $'\\' "'")"
  run /usr/bin/osascript -e "$bad"
  [ "$status" -ne 0 ]
}

@test "an injected 'with title' cannot hijack the real title or sound" {
  fire "$(payload s-hij /w/proj 'x" with title "EVIL" sound name "Sosumi')" permission
  script="$(osa)"
  [[ "$script" == *'with title "Permission · proj"'* ]]
  [[ "$script" == *'sound name "Funk"'* ]]
  [[ "$script" != *'"EVIL"'* ]]                     # the injected literal never becomes a token
}

@test "control characters and over-long commands are bounded, not passed through" {
  long="$(printf 'x%.0s' $(seq 1 400))"
  fire "$(payload s-long /w/proj "$(printf 'a\tb\nc')")" permission
  [[ "$(osa)" == *'display notification "a b c"'* ]]
  : > "$CC_NOTIFY_DIR/osa.argv"
  fire "$(payload s-long2 /w/proj "$long")" permission
  msg="$(osa)"
  [ "${#msg}" -lt 260 ]                             # 140-char cap + the surrounding script
  [[ "$msg" == *'…'* ]]                             # truncation is VISIBLE, never silent
}

# ── FAIL-OPEN — no payload must still alert; a hook that renders nothing is the worst outcome ────
@test "empty stdin: the alert still fires with the original anonymous message" {
  run bash -c 'printf "" | "$1" permission' _ "$H"
  [ "$status" -eq 0 ]
  [[ "$(osa)" == *'display notification "Claude needs your approval"'* ]]
}

@test "malformed JSON: exit 0 and the anonymous alert still fires" {
  run bash -c 'printf "not json {{{" | "$1" permission' _ "$H"
  [ "$status" -eq 0 ]
  [[ "$(osa)" == *'display notification "Claude needs your approval"'* ]]
}

@test "no jq at all: the hook degrades to the anonymous alert instead of dying" {
  # The seam is required to reach this branch: with jq merely off PATH the hook still finds
  # /opt/homebrew/bin/jq by absolute path (deliberate — hooks and launchd jobs run without
  # Homebrew on PATH), so removing it from PATH would NOT have exercised the no-jq code.
  CC_NOTIFY_JQ="$BATS_TEST_TMPDIR/no-such-jq" run bash -c 'printf "%s" "$1" | "$2" permission' \
      _ "$(payload s-nojq /w/proj ls)" "$H"
  [ "$status" -eq 0 ]
  [[ "$(osa)" == *'display notification "Claude needs your approval"'* ]]
}

@test "an empty subtitle is OMITTED, never rendered as a blank line" {
  run bash -c 'printf "" | "$1" permission' _ "$H"
  [[ "$(osa)" != *subtitle* ]]
}

# ── DEBOUNCE — keyed PER SESSION, which is the whole point ───────────────────────────────────────
@test "two DIFFERENT sessions blocking inside the 2 s window BOTH notify" {
  # The measured pre-fix drop: one key per account meant the second session vanished.
  fire "$(payload sess-one /w/proj 'cmd-one')" permission
  fire "$(payload sess-two /w/proj 'cmd-two')" permission
  [ "$(osa | grep -c 'display notification')" -eq 2 ]
  [[ "$(osa)" == *cmd-one* ]]
  [[ "$(osa)" == *cmd-two* ]]
}

@test "the SAME session firing twice inside the window is still debounced to one" {
  fire "$(payload sess-same /w/proj 'cmd-a')" permission
  fire "$(payload sess-same /w/proj 'cmd-b')" permission
  [ "$(osa | grep -c 'display notification')" -eq 1 ]
}

@test "the debounce lock is keyed by session id, and distinct sessions get distinct locks" {
  fire "$(payload sess-alpha /w/proj x)" permission
  fire "$(payload sess-beta  /w/proj x)" permission
  [ -f "$CC_NOTIFY_DIR/claude-notify-.claude-test-sess-alpha-permission.lock" ]
  [ -f "$CC_NOTIFY_DIR/claude-notify-.claude-test-sess-beta-permission.lock" ]
}

@test "different EVENT TYPES from one session are debounced independently" {
  fire "$(payload sess-ev /w/proj x)" permission
  fire "$(payload sess-ev /w/proj x)" question
  [ "$(osa | grep -c 'display notification')" -eq 2 ]
}

@test "an unsafe session id cannot escape CC_NOTIFY_DIR via the lock path" {
  for bad in "../evil" "a/b" 'semi;rm' '/abs'; do
    printf '%s' "$(jq -nc --arg s "$bad" '{session_id:$s,cwd:"/w",tool_name:"Bash",tool_input:{command:"x"}}')" \
      | "$H" permission
  done
  [ ! -e "$BATS_TEST_TMPDIR/evil-permission.lock" ]
  n=0
  for f in "$CC_NOTIFY_DIR"/*nosid-permission.lock; do [ -e "$f" ] && n=$((n + 1)); done
  [ "$n" -eq 1 ]                                     # every unsafe sid fell back to the nosid key
}

# ── QUIET EVENTS — `complete` is sound-only and must stay that way ───────────────────────────────
@test "complete fires no desktop notification (sound only), but IS debounced per session" {
  fire "$(payload sess-c1 /w/proj x)" complete
  fire "$(payload sess-c2 /w/proj x)" complete
  [ ! -s "$CC_NOTIFY_DIR/osa.argv" ]
  [ -f "$CC_NOTIFY_DIR/claude-notify-.claude-test-sess-c1-complete.lock" ]
  [ -f "$CC_NOTIFY_DIR/claude-notify-.claude-test-sess-c2-complete.lock" ]
}

@test "the debug log carries the identity so the log is triageable after the fact" {
  fire "$(payload 4f9c21ab-0000-1111-2222-333344445555 /Users/x/claude-infrastructure 'ls')" permission
  run cat "$CC_NOTIFY_DIR/claude-notify.log"
  [[ "$output" == *"[4f9c21ab claude-infrastructure]"* ]]
}

# ── Adversarial-review fixes (verify-notify, 2026-07-31) ─────────────────────────────────────────
# Two of these produced a SILENT TOTAL DROP of the alert — strictly worse than the anonymous alert
# this hook replaced, and the exact outcome this suite exists to prevent. None had a test.
@test "D1: a lock stamped in the FUTURE does not suppress the alert" {
  # NOW - LAST_NOTIFY goes negative, which satisfies `< 2` forever, and the touch that would heal
  # it is never reached. Triggered by any backward clock step, or by a local user pre-creating the
  # lock — the filenames are world-readable in /tmp and publish live session ids.
  touch -t 203001010000 "$CC_NOTIFY_DIR/claude-notify-.claude-test-skew-permission.lock"
  fire "$(payload skew /w/proj 'x')" permission
  [[ "$(osa)" == *'display notification "x"'* ]] || false
}

@test "D2: an unwritable debug log does not kill the alert" {
  : > "$CC_NOTIFY_DIR/claude-notify.log"; chmod 000 "$CC_NOTIFY_DIR/claude-notify.log"
  run bash -c 'printf "%s" "$1" | "$2" permission' _ "$(payload log000 /w/proj 'git push --force')" "$H"
  chmod 644 "$CC_NOTIFY_DIR/claude-notify.log"
  [ "$status" -eq 0 ]
  [[ "$(osa)" == *'display notification "git push --force"'* ]] || false
}

@test "D2b: an unwritable lock directory does not kill the alert either" {
  chmod 500 "$CC_NOTIFY_DIR"
  run bash -c 'printf "%s" "$1" | "$2" permission' _ "$(payload lk /w/proj 'ls')" "$H"
  chmod 755 "$CC_NOTIFY_DIR"
  [ "$status" -eq 0 ]
}

@test "D3: a metacharacter in session_id cannot break the emitted AppleScript" {
  # SID8 reaches the script literal. It was sanitized for the FILENAME sink and left raw here —
  # inconsistent sinks on one untrusted value; a quote is a -2740 error, i.e. nothing renders.
  printf '%s' '{"session_id":"a\"b-1111","cwd":"/w/proj","tool_name":"Bash","tool_input":{"command":"ls"}}' | "$H" permission
  script="$(osa)"
  [ -n "$script" ]
  run /usr/bin/osascript -e "if false then $script"
  [ "$status" -eq 0 ]
}

@test "D4: a multi-megabyte payload stays far inside the 5 s hook budget" {
  # The scrub's three global substitutions ran over the WHOLE tool_input before the 140-char cut:
  # 2 MB measured 5.4 s, straight through the budget, on the path that blocks the operator's prompt.
  # The payload goes via a FILE: a 2 MB jq --arg overflows the argv limit, which fails the test
  # harness rather than the subject (observed: "jq: Argument list too long").
  python3 -c "import json;json.dump({'session_id':'sz','cwd':'/w/proj','tool_name':'Bash','tool_input':{'command':'a'*2000000}},open('$BATS_TEST_TMPDIR/big.json','w'))"
  start=$(date +%s)
  "$H" permission < "$BATS_TEST_TMPDIR/big.json"
  [ $(( $(date +%s) - start )) -lt 3 ]
  [[ "$(osa)" == *'…'* ]] || false        # still truncated, still rendered
}
