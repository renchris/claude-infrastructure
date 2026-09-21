#!/usr/bin/env bats
# scripts/lib/cc-tui.sh — type a prompt into a live Claude Code composer and PROVE it landed.
#
# WHY THIS SUITE EXISTS, AND WHY IT IS ONE CASE PER RC VALUE. The entry point's whole product is a
# six-valued rc, and five of those six decide something opposite: rc 2/3 mean NOTHING WAS TYPED
# (retry later), rc 4 means text is in the composer and the CR was withheld (clean up), rc 1 means
# the pane is gone (re-derive the id), and rc 5 means it may well have worked (never re-fire —
# that is the duplicate-work incident handoff-fire.sh:3186's state 3 exists for). PLAN_DRAFT.md:625
# asks for two of the six; three values would then ship with no red-proof at all.
#
# THE ONE THAT MATTERS MOST IS THE NEGATIVE CONTROL FOR rc 0. The oracle is keyed on a BYTE OFFSET
# taken before the send, and the cheap way to build it — scan the whole transcript — passes every
# happy-path test while proving nothing, because the payload's own earlier copy is already in the
# file. `records the payload BEFORE the offset are not evidence` is that mutant's executioner.
#
# Hermeticity: every kitty call goes through cc_tui_rpc, which is stubbed here, so nothing in this
# file depends on a terminal, a socket, or which pane the developer is sitting in. $HOME, the
# registry dir and the residue store are all fixtured.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LIB="$REPO/scripts/lib/cc-tui.sh"
  HF="$REPO/scripts/handoff-fire.sh"
  K="$REPO/bin/it2-kitty"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/logs"
  export CC_COMPOSER_RESIDUE_DIR="$BATS_TEST_TMPDIR/residue"
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg"; mkdir -p "$CC_REGISTRY_DIR"
  export CC_TERM_KITTY_TO="unix:$BATS_TEST_TMPDIR/sock"
  # Every wait knob to ~0: the suite must be sub-second and must never depend on real settling.
  export CC_TUI_PREWAIT=0 CC_TUI_PREIVL=0.01 CC_TUI_SETTLE=0.01
  export CC_TUI_READBACK_TRIES=2 CC_TUI_RECORD_TRIES=2 CC_TUI_RECORD_IVL=0.01
  export CC_TUI_SCRUB_ROUNDS=2

  SDIR="$BATS_TEST_TMPDIR/screens"; mkdir -p "$SDIR"
  RPC_LOG="$BATS_TEST_TMPDIR/rpc.log"; : > "$RPC_LOG"
  LS_JSON="$BATS_TEST_TMPDIR/ls.json"
  printf '%s' '[{"tabs":[{"windows":[{"id":42}]}]}]' > "$LS_JSON"
  LS_RC=0; SEND_RC=0; CR_RC=0; CR_APPEND=""; CR_REPLACE=""
  TRANS="$BATS_TEST_TMPDIR/session.jsonl"
  export CC_TUI_TRANSCRIPT="$TRANS"

  PAY="$BATS_TEST_TMPDIR/payload.txt"
  printf '%s\n%s\n' 'resume the limit-recovered session and continue wave five' \
                    'pick up from where the transcript leaves off' > "$PAY"
  MARK='resume the limit-recovered session and continue wave five'

  B="$(printf '\xe2\x94\x80%.0s' $(seq 1 100))"   # a full-width U+2500 border row

  # shellcheck disable=SC1090
  . "$LIB"

  # ---- THE ONLY TRANSPORT THE LIB TOUCHES -------------------------------------------------
  # get-text is SCRIPTED per call (a file counter, not a shell variable: every reader runs inside
  # a command substitution, i.e. a subshell, where an incremented global would evaporate —
  # memory: assignment-inside-command-substitution-never-escapes).
  cc_tui_rpc() {
    local a last n f
    case "$1" in
      ls)
        printf 'ls\n' >> "$RPC_LOG"
        [ "${LS_RC:-0}" = 0 ] || return "${LS_RC}"
        cat "$LS_JSON"
        ;;
      get-text)
        n="$(cat "$SDIR/.n" 2>/dev/null || printf 0)"; n=$((n + 1)); printf '%s' "$n" > "$SDIR/.n"
        printf 'get-text#%s\n' "$n" >> "$RPC_LOG"
        f="$SDIR/$n"; [ -f "$f" ] || f="$SDIR/default"
        [ -f "$f" ] || return 1
        cat "$f"
        ;;
      send-text)
        last=""; for a in "$@"; do last="$a"; done
        case " $* " in
          *" --from-file "*) printf 'PASTE\n' >> "$RPC_LOG"; return "${SEND_RC:-0}" ;;
        esac
        case "$last" in
          $'\x15') printf 'CTRL-U\n' >> "$RPC_LOG"; return "${SEND_RC:-0}" ;;
          $'\x7f') printf 'DEL\n'    >> "$RPC_LOG"; return "${SEND_RC:-0}" ;;
          $'\r')   printf 'CR\n'     >> "$RPC_LOG"
                   [ -n "${CR_APPEND:-}" ] && [ -f "$CR_APPEND" ] && cat "$CR_APPEND" >> "$TRANS"
                   [ -n "${CR_REPLACE:-}" ] && [ -f "$CR_REPLACE" ] && cp "$CR_REPLACE" "$TRANS"
                   return "${CR_RC:-0}" ;;
          *)       printf 'TEXT\n'   >> "$RPC_LOG"; return "${SEND_RC:-0}" ;;
        esac
        ;;
      *) printf 'OTHER:%s\n' "$1" >> "$RPC_LOG" ;;
    esac
  }
}

# ---- fixture builders -----------------------------------------------------------------------
screen_empty()  { printf 'scrollback line\n%s\n \xe2\x9d\xaf \n%s\n' "$B" "$B" > "$1"; }
screen_draft()  { printf 'scrollback line\n%s\n \xe2\x9d\xaf %s\n%s\n' "$B" "$2" "$B" > "$1"; }
screen_nobox()  { printf 'a torn frame with no input box at all\nnothing here\n' > "$1"; }
screen_paste()  { { printf 'scrollback line\n%s\n' "$B"; cat "$2"; printf '%s\n' "$B"; } > "$1"; }
sent()          { grep -c "^$1\$" "$RPC_LOG" 2>/dev/null || true; }

# =================================================================================================
# rc 1 — the pane
# =================================================================================================

@test "rc 1: a non-integer window id is refused WITHOUT any RPC (a malformed --match costs 7.6s)" {
  screen_empty "$SDIR/default"
  run cc_tui_submit "E5D77446-1234-4321-9999-abcdefabcdef" "$PAY"
  [ "$status" -eq 1 ]
  [ ! -s "$RPC_LOG" ]
}

@test "rc 1: a pane absent from kitty's window list is refused and nothing is typed" {
  screen_empty "$SDIR/default"
  run cc_tui_submit 99 "$PAY"
  [ "$status" -eq 1 ]
  [ "$(sent PASTE)" -eq 0 ]
  [ "$(sent CR)" -eq 0 ]
}

@test "rc 1: a payload file that does not exist is refused before any RPC" {
  screen_empty "$SDIR/default"
  run cc_tui_submit 42 "$BATS_TEST_TMPDIR/no-such-payload"
  [ "$status" -eq 1 ]
  [ ! -s "$RPC_LOG" ]
}

@test "an UNREADABLE window list is could-not-tell and DELIVERS ANYWAY — it is never rc 1" {
  LS_RC=2
  screen_empty "$SDIR/default"
  run cc_tui_type 42 "$PAY"
  [ "$status" -eq 0 ]
  [ "$(sent PASTE)" -eq 1 ]
}

@test "rc 1: a CR whose RPC fails leaves the payload UNSUBMITTED and scrubs the composer" {
  screen_empty "$SDIR/1"; screen_paste "$SDIR/2" "$PAY"
  screen_draft "$SDIR/3" "leftover"; screen_empty "$SDIR/default"
  CR_RC=1
  run cc_tui_submit 42 "$PAY"
  [ "$status" -eq 1 ]
  [ "$(sent CR)" -eq 1 ]
  [ "$(sent CTRL-U)" -ge 1 ]
}

# =================================================================================================
# rc 2 / rc 3 — the emptiness pre-gate. NOTHING may be typed in either.
# =================================================================================================

@test "rc 2: a composer that cannot be read through the pre-wait ABSTAINS and types nothing" {
  screen_nobox "$SDIR/default"
  run cc_tui_submit 42 "$PAY"
  [ "$status" -eq 2 ]
  [ "$(sent PASTE)" -eq 0 ]
  [ "$(sent CR)" -eq 0 ]
  [ "$(sent CTRL-U)" -eq 0 ]
}

@test "rc 3: a composer holding an operator draft HOLDS and types nothing" {
  screen_draft "$SDIR/default" "also fix the margin on the invoice page"
  run cc_tui_submit 42 "$PAY"
  [ "$status" -eq 3 ]
  [ "$(sent PASTE)" -eq 0 ]
  [ "$(sent CR)" -eq 0 ]
}

@test "rc 3 and rc 2 are DIFFERENT verdicts — an occupied box is not an unreadable one" {
  screen_draft "$SDIR/default" "a draft"
  run cc_tui_submit 42 "$PAY"
  [ "$status" -eq 3 ]
  : > "$RPC_LOG"; rm -f "$SDIR/.n"
  screen_nobox "$SDIR/default"
  run cc_tui_submit 42 "$PAY"
  [ "$status" -eq 2 ]
}

# =================================================================================================
# rc 4 — the read-back tier. The CR is the thing it withholds.
# =================================================================================================

@test "rc 4: a read-back that is not this payload withholds the CR and records the residue" {
  screen_empty "$SDIR/1"
  screen_draft "$SDIR/default" "somethingelseentirely"
  run cc_tui_submit 42 "$PAY"
  [ "$status" -eq 4 ]
  [ "$(sent PASTE)" -eq 1 ]
  [ "$(sent CR)" -eq 0 ]
  [ "$(sent CTRL-U)" -ge 1 ]
  [ -f "$CC_COMPOSER_RESIDUE_DIR/42" ]
}

@test "rc 4: a scrub that PROVES the composer empty forgets the receipt instead of writing one" {
  mkdir -p "$CC_COMPOSER_RESIDUE_DIR"; printf 'stale\tstale\n' > "$CC_COMPOSER_RESIDUE_DIR/42"
  screen_empty "$SDIR/1"
  screen_draft "$SDIR/2" "somethingelse"; screen_draft "$SDIR/3" "somethingelse"
  screen_draft "$SDIR/4" "somethingelse"          # cc_tui_clear's first read: non-empty
  screen_empty "$SDIR/default"                    # after the first Ctrl-U: proven empty
  run cc_tui_submit 42 "$PAY"
  [ "$status" -eq 4 ]
  [ "$(sent CR)" -eq 0 ]
  [ ! -f "$CC_COMPOSER_RESIDUE_DIR/42" ]
}

@test "cc_tui_clear sends NOTHING into an unreadable box and returns 2 before the first keystroke" {
  screen_nobox "$SDIR/default"
  run cc_tui_clear 42
  [ "$status" -eq 2 ]
  [ "$(sent CTRL-U)" -eq 0 ]
  [ "$(sent DEL)" -eq 0 ]
}

@test "cc_tui_clear eats the empty line with \\x7f when Ctrl-U stops making progress" {
  screen_draft "$SDIR/default" "stuck"
  run cc_tui_clear 42
  [ "$status" -eq 1 ]
  [ "$(sent DEL)" -ge 1 ]
}

# =================================================================================================
# rc 5 / rc 0 — the disk oracle
# =================================================================================================

@test "rc 5: the CR goes out but no record appears — CANNOT TELL, never a failure" {
  screen_empty "$SDIR/1"; screen_paste "$SDIR/default" "$PAY"
  printf '%s\n' '{"type":"assistant","message":{"content":"earlier turn"}}' > "$TRANS"
  run cc_tui_submit 42 "$PAY"
  [ "$status" -eq 5 ]
  [ "$(sent CR)" -eq 1 ]
}

@test "rc 0: a user record carrying the payload appears past the offset" {
  screen_empty "$SDIR/1"; screen_paste "$SDIR/default" "$PAY"
  printf '%s\n' '{"type":"assistant","message":{"content":"earlier turn"}}' > "$TRANS"
  CR_APPEND="$BATS_TEST_TMPDIR/append.jsonl"
  printf '{"type":"user","message":{"content":"%s"}}\n' "$MARK" > "$CR_APPEND"
  run cc_tui_submit 42 "$PAY"
  [ "$status" -eq 0 ]
  [ "$(sent CR)" -eq 1 ]
}

@test "rc 0 also reads the ARRAY content form, through .text and not through a JSON dump" {
  screen_empty "$SDIR/1"; screen_paste "$SDIR/default" "$PAY"
  : > "$TRANS"
  CR_APPEND="$BATS_TEST_TMPDIR/append.jsonl"
  printf '{"type":"user","message":{"content":[{"type":"text","text":"%s"}]}}\n' "$MARK" > "$CR_APPEND"
  run cc_tui_submit 42 "$PAY"
  [ "$status" -eq 0 ]
}

@test "records carrying the payload BEFORE the offset are not evidence — the byte mark is the point" {
  screen_empty "$SDIR/1"; screen_paste "$SDIR/default" "$PAY"
  printf '{"type":"user","message":{"content":"%s"}}\n' "$MARK" > "$TRANS"
  run cc_tui_submit 42 "$PAY"
  [ "$status" -eq 5 ]
}

@test "an ASSISTANT record carrying the payload is not evidence — only a user record is ingestion" {
  screen_empty "$SDIR/1"; screen_paste "$SDIR/default" "$PAY"
  : > "$TRANS"
  CR_APPEND="$BATS_TEST_TMPDIR/append.jsonl"
  printf '{"type":"assistant","message":{"content":"%s"}}\n' "$MARK" > "$CR_APPEND"
  run cc_tui_submit 42 "$PAY"
  [ "$status" -eq 5 ]
}

@test "a payload with no printable run long enough to prove anything still submits, and says 5" {
  SHORT="$BATS_TEST_TMPDIR/short.txt"; printf 'hi\n' > "$SHORT"
  screen_empty "$SDIR/1"; screen_paste "$SDIR/default" "$SHORT"
  : > "$TRANS"
  CR_APPEND="$BATS_TEST_TMPDIR/append.jsonl"
  printf '{"type":"user","message":{"content":"hi"}}\n' > "$CR_APPEND"
  run cc_tui_submit 42 "$SHORT"
  [ "$status" -eq 5 ]
  [ "$(sent CR)" -eq 1 ]
}

@test "a transcript that SHRANK below the offset is re-read from zero, not skipped" {
  # The baseline is large; the CR rotates a SMALLER file into place carrying the record. Without
  # the shrink guard the stale offset sits past EOF and the real record is invisible forever.
  screen_empty "$SDIR/1"; screen_paste "$SDIR/default" "$PAY"
  i=0; : > "$TRANS"
  while [ "$i" -lt 60 ]; do printf '{"type":"assistant","message":{"content":"filler turn"}}\n' >> "$TRANS"; i=$((i + 1)); done
  [ "$(_cc_tui_size "$TRANS")" -gt 2000 ]
  CR_REPLACE="$BATS_TEST_TMPDIR/rotated.jsonl"
  printf '{"type":"user","message":{"content":"%s"}}\n' "$MARK" > "$CR_REPLACE"
  run cc_tui_submit 42 "$PAY"
  [ "$status" -eq 0 ]
}

@test "cc_tui_record_after finds nothing past the end of a file and says so rather than erroring" {
  printf '{"type":"user","message":{"content":"%s"}}\n' "$MARK" > "$TRANS"
  run cc_tui_record_after "$TRANS" 999999 "$MARK"
  [ "$status" -eq 1 ]
}

@test "cc_tui_type on a PROVABLY absent pane refuses and sends nothing" {
  run cc_tui_type 99 "$PAY"
  [ "$status" -eq 1 ]
  [ "$(sent PASTE)" -eq 0 ]
}

@test "the content walk goes through .text — a JSON dump would escape a quote out of the needle" {
  Q="$BATS_TEST_TMPDIR/quoted.txt"
  printf '%s\n' 'he said "resume the recovered session now" and then left the pane' > "$Q"
  screen_empty "$SDIR/1"; screen_paste "$SDIR/default" "$Q"
  : > "$TRANS"
  run cc_tui_marker "$Q"
  [ "$status" -eq 0 ]
  QMARK="$output"
  CR_APPEND="$BATS_TEST_TMPDIR/append.jsonl"
  QMARK="$QMARK" /usr/bin/python3 -c '
import json, os, sys
print(json.dumps({"type": "user",
                  "message": {"content": [{"type": "text", "text": os.environ["QMARK"]}]}}))' > "$CR_APPEND"
  # the control: the JSON dump of that same record does NOT contain the needle verbatim
  n="$(grep -cF -- "$QMARK" "$CR_APPEND" || true)"
  [ "$n" -eq 0 ]
  run cc_tui_submit 42 "$Q"
  [ "$status" -eq 0 ]
}

@test "cc_tui_marker is a CONTIGUOUS substring of the payload even when it holds non-ASCII" {
  U="$BATS_TEST_TMPDIR/utf.txt"
  printf 'short\n\xe2\x94\x80\xe2\x94\x80 resume the recovered session now \xe2\x9d\xaf\n' > "$U"
  run cc_tui_marker "$U"
  [ "$status" -eq 0 ]
  [ "$output" = "resume the recovered session now" ]
  grep -qF -- "$output" "$U" || false
}

@test "cc_tui_marker refuses a needle under the floor rather than minting a weak oracle" {
  S="$BATS_TEST_TMPDIR/tiny.txt"; printf 'ok\n' > "$S"
  run cc_tui_marker "$S"
  [ "$status" -eq 1 ]
}

# =================================================================================================
# the read-back forms
# =================================================================================================

@test "read-back: the inline form matches, whitespace-stripped" {
  W="$(LC_ALL=C tr -cd '[:print:]' < "$PAY" | LC_ALL=C tr -d '[:space:]')"
  run cc_tui_readback_ok "$PAY" "$W"
  [ "$status" -eq 0 ]
}

@test "read-back: a scrolled TAIL over the floor matches; the same TAIL under it does not" {
  W="$(LC_ALL=C tr -cd '[:print:]' < "$PAY" | LC_ALL=C tr -d '[:space:]')"
  run cc_tui_readback_ok "$PAY" "${W: -70}"
  [ "$status" -eq 0 ]
  run cc_tui_readback_ok "$PAY" "${W: -20}"
  [ "$status" -eq 1 ]
}

@test "read-back: a HEAD match stays a MISMATCH — that truncation direction is transport loss" {
  W="$(LC_ALL=C tr -cd '[:print:]' < "$PAY" | LC_ALL=C tr -d '[:space:]')"
  run cc_tui_readback_ok "$PAY" "${W:0:70}"
  [ "$status" -eq 1 ]
}

@test "read-back: the placeholder form pins N to the payload's OWN newline count" {
  BIG="$BATS_TEST_TMPDIR/big.txt"; : > "$BIG"
  i=0; while [ "$i" -lt 19 ]; do printf 'line %s of a long brief\n' "$i" >> "$BIG"; i=$((i + 1)); done
  run cc_tui_readback_ok "$BIG" '[Pastedtext#1+19lines]'
  [ "$status" -eq 0 ]
  run cc_tui_readback_ok "$BIG" '[Pastedtext#1+18lines]'
  [ "$status" -eq 1 ]
}

@test "read-back: the newline count comes from the FILE, so a trailing newline is not lost" {
  N="$BATS_TEST_TMPDIR/nl.txt"; printf 'alpha\nbeta\n' > "$N"
  run _cc_tui_nl_file "$N"
  [ "$output" = "2" ]
}

@test "read-back: the measured hybrid shape (draft + placeholder) is a MISMATCH" {
  BIG="$BATS_TEST_TMPDIR/big.txt"; : > "$BIG"
  i=0; while [ "$i" -lt 19 ]; do printf 'line %s of a long brief\n' "$i" >> "$BIG"; i=$((i + 1)); done
  run cc_tui_readback_ok "$BIG" 'alsofixthemargin[Pastedtext#1+19lines]'
  [ "$status" -eq 1 ]
}

# =================================================================================================
# the copies, and the transport
# =================================================================================================

@test "cc_tui_composer agrees with handoff-fire.sh's composer_content on every fixture screen" {
  U="$BATS_TEST_TMPDIR/units.sh"
  sed -n '/^composer_content() {/,/^}/p' "$HF" > "$U"
  bash -n "$U" || false
  # shellcheck disable=SC1090
  . "$U"
  SCREEN_FILE="$SDIR/default"
  hf_bounded() { cat "$SCREEN_FILE" 2>/dev/null; }
  for fx in empty draft nobox placeholder; do
    rm -f "$SDIR/.n"
    case "$fx" in
      empty)       screen_empty "$SCREEN_FILE" ;;
      draft)       screen_draft "$SCREEN_FILE" "a live draft here" ;;
      nobox)       screen_nobox "$SCREEN_FILE" ;;
      placeholder) printf 'x\n%s\n Try "fix the tests" \n%s\n' "$B" "$B" > "$SCREEN_FILE" ;;
    esac
    arc=0; a="$(cc_tui_composer 42)" || arc=$?
    brc=0; b="$(composer_content it2 42)" || brc=$?
    [ "$arc" = "$brc" ] || false
    [ "$a" = "$b" ] || false
  done
  [ "$a" = "" ]
  rm -f "$SDIR/.n"; screen_draft "$SCREEN_FILE" "a live draft here"
  arc=0; a="$(cc_tui_composer 42)" || arc=$?
  [ "$arc" -eq 0 ]
  [ "$a" = "alivedrafthere" ]
}

@test "the never-typed-in placeholder row reads EMPTY, but a draft that merely starts with it does not" {
  printf 'x\n%s\n Try "fix the tests" \n%s\n' "$B" "$B" > "$SDIR/default"
  run cc_tui_composer 42
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  rm -f "$SDIR/.n"
  printf 'x\n%s\n Try "this" and then ship it\n%s\n' "$B" "$B" > "$SDIR/default"
  run cc_tui_composer 42
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "cc_tui_rpc REFUSES when no socket resolves — it never drives the ambient kitty with --to ''" {
  unset -f cc_tui_rpc                      # drop the stub and restore the real one
  unset CC_TUI_LIB_LOADED
  unset CC_TERM_KITTY_TO
  export CC_KITTY_SOCKET_BIN="$BATS_TEST_TMPDIR/no-such-socket-bin"
  export CC_TUI_DIR="$BATS_TEST_TMPDIR/nowhere"
  # shellcheck disable=SC1090
  . "$LIB"
  run cc_tui_socket
  [ "$status" -eq 1 ]
  run cc_tui_rpc ls
  [ "$status" -eq 2 ]
}

@test "the paste is sent --from-file, never as a text argument (python escapes are on the wire)" {
  cc_tui_rpc() { printf '%s\n' "$*" >> "$RPC_LOG"; [ "$1" = ls ] && cat "$LS_JSON"; return 0; }
  run cc_tui_type 42 "$PAY"
  [ "$status" -eq 0 ]
  grep -q -- '--from-file' "$RPC_LOG" || false
  grep -q -- '--bracketed-paste=enable' "$RPC_LOG" || false
}

# =================================================================================================
# bin/it2-kitty session tui-submit — the seam
# =================================================================================================

kitty_env() {
  export CC_TERM_KITTY_TO="unix:$BATS_TEST_TMPDIR/sock"
  export CC_PANE_CMD_DIR="$BATS_TEST_TMPDIR/cmd"; mkdir -p "$CC_PANE_CMD_DIR"
  STUB="$BATS_TEST_TMPDIR/stub-lib.sh"
  cat > "$STUB" <<'SH'
cc_tui_submit() { printf 'CALLED %s %s\n' "$1" "$2" >> "$STUB_LOG"; return "${STUB_RC:-0}"; }
SH
  export CC_TUI_LIB="$STUB"
  export STUB_LOG="$BATS_TEST_TMPDIR/stub.log"; : > "$STUB_LOG"
}

@test "verb: tui-submit with no -s is a usage error (64), not an unreadable pane" {
  kitty_env
  run "$K" session tui-submit --from-file "$PAY"
  [ "$status" -eq 64 ]
}

@test "verb: tui-submit with an iTerm2 UUID is rejected as a bad id (65)" {
  kitty_env
  run "$K" session tui-submit -s E5D77446-1234-4321-9999-abcdefabcdef --from-file "$PAY"
  [ "$status" -eq 65 ]
}

@test "verb: tui-submit without --from-file is refused — a payload is never a text argument" {
  kitty_env
  run "$K" session tui-submit -s 42
  [ "$status" -eq 64 ]
}

@test "verb: tui-submit with a missing payload file is refused" {
  kitty_env
  run "$K" session tui-submit -s 42 --from-file "$BATS_TEST_TMPDIR/nope"
  [ "$status" -eq 64 ]
}

@test "verb: tui-submit passes the lib's rc THROUGH, for every value in the table" {
  kitty_env
  for want in 0 1 2 3 4 5; do
    STUB_RC="$want" run "$K" session tui-submit -s 42 --from-file "$PAY"
    [ "$status" -eq "$want" ]
  done
}

@test "verb: tui-submit does NOT short-circuit on the armed marker the way session send does" {
  kitty_env
  printf '%s\n' 0 > "$CC_PANE_CMD_DIR/42.armed"
  run "$K" session tui-submit -s 42 --from-file "$PAY"
  [ "$status" -eq 0 ]
  grep -q '^CALLED 42 ' "$STUB_LOG" || false
}

@test "verb: --from-file is parsed as a FLAG, so it can never become text typed at a pane" {
  kitty_env
  export CC_TERM_KITTY="$BATS_TEST_TMPDIR/fake-kitty"
  cat > "$CC_TERM_KITTY" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$KLOG"
case " $* " in *" ls "*) printf '%s' '[{"tabs":[{"windows":[{"id":42}]}]}]' ;; esac
exit 0
SH
  chmod +x "$CC_TERM_KITTY"
  export KLOG="$BATS_TEST_TMPDIR/klog"; : > "$KLOG"
  run "$K" session send -s 42 --from-file /etc/passwd
  # A plain `[ ]` on a COUNT, never `grep && false`: an and-absorbed assertion is errexit-exempt
  # in bats (scripts/bats-assert-liveness.py flags it) and its polarity is the wrong way round.
  n="$(grep -c -- '--from-file' "$KLOG" || true)"
  [ "$n" -eq 0 ]
  [ -s "$KLOG" ]
}
