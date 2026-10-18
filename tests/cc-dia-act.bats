#!/usr/bin/env bats
# shellcheck disable=SC2016  # the stub bodies are single-quoted on purpose: they expand when a stub runs
# bin/cc-dia-act — the gates in front of every click, fill and press in the operator's real Dia
# (decision a9b998025419): operator host list, supervised first run, 24 h bot-wall cooldown,
# idle gate, own-window scope, and bot-wall detection after every act and read.
#
# Hermetic: the Accessibility helper is a stub (CC_DIA_ACT_AX) that serves one page per window
# identifier and logs every call; osascript is a stub (CC_DIA_ACT_OSASCRIPT); cc-dia-js runs for
# real over stubbed ps/pgrep (DIA_JS_PS / DIA_JS_PGREP), as in tests/cc-dia-js.bats. No case can
# reach the real Dia: setup fails if any of the four overrides is unset.
# RED-proof: new tool. Each refusal case was run against a scratch copy of bin/cc-dia-act with
# that one gate deleted (host list, supervised record, cooldown, wall check, state-file scope,
# idle) and went red.

setup() {
  REPO="${CC_REDPROOF_TREE:-$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)}"
  SUT="$REPO/bin/cc-dia-act"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  unset XDG_STATE_HOME XDG_CACHE_HOME
  S="$BATS_TEST_TMPDIR/stub"; mkdir -p "$S/pages"
  CFG="$HOME/.config/cc-dia-act"
  # cc-dia-js over stubbed ps/pgrep: one personal Dia, pid 41919, flag off.
  printf '%s\n' '#!/bin/bash' 'echo 41919' > "$S/pgrep"
  printf '%s\n' '#!/bin/bash' \
    'field=""; while [ $# -gt 0 ]; do case "$1" in -o) field=${2%=}; shift ;; esac; shift; done' \
    'case "$field" in command) echo /Applications/Dia.app/Contents/MacOS/Dia ;; ucomm) echo Dia ;;' \
    '  lstart) echo "Thu Oct 15 21:38:19 2026" ;; etime) echo 01:00 ;; esac' > "$S/ps"
  # osascript stub: logs the script; `make new window` prints the id in $S/newid.
  printf '%s\n' '#!/bin/bash' \
    'printf "%s\n---\n" "$2" >> "'"$S"'/osa.log"' \
    'case "$2" in *"make new window"*) cat "'"$S"'/newid" ;; esac' > "$S/osascript"
  # AX helper stub: logs argv; serves $S/pages/<ident>.{url,txt}; idle from $S/idle; act exit from $S/act_rc.
  printf '%s\n' '#!/bin/bash' \
    'printf "%s\n" "$*" >> "'"$S"'/ax.log"' \
    'sub=$1; shift; ident=""' \
    'while [ $# -gt 0 ]; do case "$1" in --ident) ident=$2; shift ;; esac; shift; done' \
    'p="'"$S"'/pages/$ident"' \
    'case "$sub" in' \
    '  trusted) exit 0 ;;' \
    '  idle) cat "'"$S"'/idle" ;;' \
    '  focus-save) echo "front_pid=777 dia_window=bigBrowserWindow_OPERATOR" ;;' \
    '  focus-restore) exit 0 ;;' \
    '  url) [ -f "$p.url" ] || exit 6; cat "$p.url" ;;' \
    '  read) [ -f "$p.txt" ] || exit 6; cat "$p.txt"; [ -f "$p.after" ] && mv "$p.after" "$p.txt"; exit 0 ;;' \
    '  fields) echo "0 | AXTextField | Last Name | " ;;' \
    '  click|fill|press) [ -f "$p.acted" ] && mv "$p.acted" "$p.txt"; [ -f "'"$S"'/act_out" ] && cat "'"$S"'/act_out"; exit "$(cat "'"$S"'/act_rc")" ;;' \
    'esac' > "$S/ax"
  chmod +x "$S/pgrep" "$S/ps" "$S/osascript" "$S/ax"
  echo 'idle_s=60 locked=0' > "$S/idle"
  echo 0 > "$S/act_rc"
  export DIA_JS_PGREP="$S/pgrep" DIA_JS_PS="$S/ps" CC_DIA_ACT_OSASCRIPT="$S/osascript" CC_DIA_ACT_AX="$S/ax"
  [ -n "${DIA_JS_PGREP:-}" ] && [ -n "${DIA_JS_PS:-}" ] && [ -n "${CC_DIA_ACT_OSASCRIPT:-}" ] && [ -n "${CC_DIA_ACT_AX:-}" ] || return 1
}

# page IDENT-SUFFIX URL TEXT — what the stub serves for window bigBrowserWindow_<suffix>.
page() { printf '%s\n' "$2" > "$S/pages/bigBrowserWindow_$1.url"; printf '%s\n' "$3" > "$S/pages/bigBrowserWindow_$1.txt"; }
# opened ID URL TEXT — the agent's own window, opened through cc-dia-act.
opened() {
  printf '%s\n' "$1" > "$S/newid"
  page "$1" "$2" "$3"
  run "$SUT" open "$2"
  [ "$status" -eq 0 ]
  [ "$output" = "$1" ]
}
acts() { grep -cE '^(click|fill|press) ' "$S/ax.log" 2>/dev/null || true; }
list() { mkdir -p "$CFG"; printf '%s\n' "$@" > "$CFG/allow-hosts"; }
supervised() { mkdir -p "$CFG/supervised"; echo "at=earlier" > "$CFG/supervised/$1"; }

COURT=https://odysseypa.example.gov/Search

@test "host gate: a host missing from the operator's list is refused (9) and no act reaches the helper" {
  opened AAA "$COURT" "Party search"
  list other.example.gov
  supervised odysseypa.example.gov
  run "$SUT" click --window AAA --text Search --settle 0
  [ "$status" -eq 9 ]
  [[ "$output" == *"HOST_NOT_LISTED: odysseypa.example.gov"* ]] || false
  [ "$(acts)" -eq 0 ]
  # the same act on a listed host reaches the helper with the host pinned for its own re-check
  list odysseypa.example.gov
  run "$SUT" click --window AAA --text Search --settle 0
  [ "$status" -eq 0 ]
  [ "$(acts)" -eq 1 ]
  grep -q '^click .*--expect-host odysseypa.example.gov' "$S/ax.log"
}

@test "supervised record: missing → refused (10); --supervised acts and records it; later runs need no flag" {
  opened AAA "$COURT" "Party search"
  list odysseypa.example.gov
  run "$SUT" fill --window AAA --index 0 "DOE" --settle 0
  [ "$status" -eq 10 ]
  [ "$(acts)" -eq 0 ]
  [ ! -e "$CFG/supervised/odysseypa.example.gov" ]
  run "$SUT" fill --window AAA --index 0 "DOE" --supervised --settle 0
  [ "$status" -eq 0 ]
  [ -s "$CFG/supervised/odysseypa.example.gov" ]
  grep -q '^fill .*--value DOE' "$S/ax.log"
  run "$SUT" press --window AAA --index 0 return --settle 0
  [ "$status" -eq 0 ]
  [ "$(acts)" -eq 2 ]
}

@test "cooldown: a live marker blocks acts (12) and navigation to the host; an expired one does not" {
  opened AAA "$COURT" "Party search"
  list odysseypa.example.gov; supervised odysseypa.example.gov
  mkdir -p "$CFG/cooldown"
  echo "until=$(( $(date +%s) + 3600 )) host=odysseypa.example.gov" > "$CFG/cooldown/odysseypa.example.gov"
  run "$SUT" click --window AAA --index 0 --settle 0
  [ "$status" -eq 12 ]
  [ "$(acts)" -eq 0 ]
  : > "$S/osa.log"
  run "$SUT" open "$COURT"
  [ "$status" -eq 12 ]
  [ ! -s "$S/osa.log" ]
  echo "until=$(( $(date +%s) - 1 )) host=odysseypa.example.gov" > "$CFG/cooldown/odysseypa.example.gov"
  run "$SUT" click --window AAA --index 0 --settle 0
  [ "$status" -eq 0 ]
  [ "$(acts)" -eq 1 ]
}

@test "rejection after an act: exit 8, 24 h cooldown written, no supervised record, next act refused" {
  opened AAA "$COURT" "Party search"
  list odysseypa.example.gov
  printf 'The requested URL was rejected. Please consult with your administrator.\nYour support ID is: 1234567890\n' \
    > "$S/pages/bigBrowserWindow_AAA.acted"
  before=$(date +%s)
  run "$SUT" click --window AAA --text Search --supervised --settle 0
  [ "$status" -eq 8 ]
  [[ "$output" == *"BOT_WALL on odysseypa.example.gov"* ]] || false
  until=$(sed -n 's/^until=\([0-9]*\).*/\1/p' "$CFG/cooldown/odysseypa.example.gov")
  [ "$until" -ge $(( before + 86400 )) ]
  [ "$until" -le $(( $(date +%s) + 86400 )) ]
  [ ! -e "$CFG/supervised/odysseypa.example.gov" ]
  run "$SUT" click --window AAA --text Search --supervised --settle 0
  [ "$status" -eq 12 ]
  [ "$(acts)" -eq 1 ]
}

@test "wall detection on read: F5, Akamai and Cloudflare pages exit 8; a page that only mentions access does not" {
  opened AAA https://shop.example.com/ "home"
  for wall in 'Request Rejected' 'Access Denied' "You don't have permission to access \"http://x/\" on this server." \
              'Just a moment...' 'Verify you are human by completing the action below.'; do
    rm -rf "$CFG/cooldown"
    printf 'header\n%s\nfooter\n' "$wall" > "$S/pages/bigBrowserWindow_AAA.txt"
    run "$SUT" read --window AAA
    [ "$status" -eq 8 ] || { echo "not detected: $wall"; false; }
    [ -f "$CFG/cooldown/shop.example.com" ]
  done
  rm -rf "$CFG/cooldown"
  printf 'Case 123\nAccess Denied for sealed records is shown as a placeholder.\n' > "$S/pages/bigBrowserWindow_AAA.txt"
  run "$SUT" read --window AAA
  [ "$status" -eq 0 ]
  [ ! -e "$CFG/cooldown" ]
}

@test "scope: a window cc-dia-act did not open is never read; every AX call names only the agent's window" {
  page OPERATOR https://mail.example.com/inbox "SECRET inbox subject"
  opened AAA https://shop.example.com/ "agent page"
  : > "$S/ax.log"
  for sub in read fields; do
    run "$SUT" "$sub" --window OPERATOR
    [ "$status" -eq 6 ]
    [[ "$output" != *SECRET* ]] || false
  done
  run "$SUT" wait-for --window OPERATOR "SECRET" --timeout 0
  [ "$status" -eq 6 ]
  [ ! -s "$S/ax.log" ]
  run "$SUT" read --window AAA
  [ "$status" -eq 0 ]
  [ "$output" = "agent page" ]
  # the only identifiers reaching the helper are the agent's own
  run grep -c -- '--ident bigBrowserWindow_AAA' "$S/ax.log"
  [ "$output" -ge 1 ]
  run grep -- '--ident' "$S/ax.log"
  [ "${#lines[@]}" -ge 1 ]
  for l in "${lines[@]}"; do [[ "$l" == *"--ident bigBrowserWindow_AAA"* ]] || false; done
}

@test "idle gate: recent operator input or a locked screen refuses the act (13) before the helper acts" {
  opened AAA "$COURT" "Party search"
  list odysseypa.example.gov; supervised odysseypa.example.gov
  echo 'idle_s=2 locked=0' > "$S/idle"
  run "$SUT" click --window AAA --index 0 --settle 0
  [ "$status" -eq 13 ]
  echo 'idle_s=600 locked=1' > "$S/idle"
  run "$SUT" click --window AAA --index 0 --settle 0
  [ "$status" -eq 13 ]
  [ "$(acts)" -eq 0 ]
}

@test "open: never launches a stopped Dia (4, no osascript); records the window and saves then restores focus" {
  printf '%s\n' '#!/bin/bash' 'exit 1' > "$S/pgrep"
  run "$SUT" open "$COURT"
  [ "$status" -eq 4 ]
  [ ! -e "$S/osa.log" ]
  printf '%s\n' '#!/bin/bash' 'echo 41919' > "$S/pgrep"
  opened AAA "$COURT" "Party search"
  [ -f "$HOME/.local/state/cc-dia-act/windows/AAA" ]
  grep -q 'if application id "company.thebrowser.dia" is running' "$S/osa.log"
  grep -q '^focus-restore --pid 41919 --front 777 --dia-window bigBrowserWindow_OPERATOR' "$S/ax.log"
}

@test "wait-for: returns once the text loads; times out with 124 when it never does" {
  opened AAA "$COURT" "Searching..."
  printf 'Results\nDOE, JOHN  2019-CR-1\n' > "$S/pages/bigBrowserWindow_AAA.after"
  run "$SUT" wait-for --window AAA "DOE, JOHN" --timeout 30 --interval 0
  [ "$status" -eq 0 ]
  [ "$output" = "found: DOE, JOHN" ]
  [ "$(grep -c '^read ' "$S/ax.log")" -eq 2 ]
  run "$SUT" wait-for --window AAA "SMITH" --timeout 0 --interval 0
  [ "$status" -eq 124 ]
}

@test "helper not built for the current source: exit 3 naming cc-dia-act build" {
  opened AAA "$COURT" "Party search"
  CC_DIA_ACT_AX="$BATS_TEST_TMPDIR/absent" run "$SUT" read --window AAA
  [ "$status" -eq 3 ]
  [[ "$output" == *"cc-dia-act build"* ]] || false
}

@test "allow (the operator's command): lowercases, dedupes and rejects a non-host" {
  run "$SUT" allow OdysseyPA.example.gov odysseypa.example.gov odysseyweb.example.gov
  [ "$status" -eq 0 ]
  [ "$(cat "$CFG/allow-hosts")" = "$(printf 'odysseypa.example.gov\nodysseyweb.example.gov')" ]
  run "$SUT" allow 'evil.gov/../x'
  [ "$status" -eq 64 ]
}

@test "click --mouse: the helper is told to skip AXPress and gets the settle window; --mouse on fill is refused" {
  opened AAA "$COURT" "Party search"
  list odysseypa.example.gov; supervised odysseypa.example.gov
  echo 'clicked (mouse fallback: AXPress changed nothing in 3 s): Civil' > "$S/act_out"
  run "$SUT" click --window AAA --text Civil --settle 3
  [ "$status" -eq 0 ]
  # the helper's path line is what the caller sees
  [[ "$output" == *"clicked (mouse fallback: AXPress changed nothing in 3 s): Civil"* ]] || false
  grep -q '^click .*--settle 3' "$S/ax.log"
  [ "$(grep -c -- '--mouse' "$S/ax.log")" -eq 0 ]
  run "$SUT" click --window AAA --text Civil --mouse --settle 0
  [ "$status" -eq 0 ]
  [ "$(grep -c -- '^click .*--mouse 1' "$S/ax.log")" -eq 1 ]
  run "$SUT" fill --window AAA --index 0 "DOE" --mouse --settle 0
  [ "$status" -eq 64 ]
  [ "$(acts)" -eq 2 ]
}

# The real helper, compiled: `keys` prints the strokes fill posts (the same strokes() fill types
# from). RED-proof: run against the pre-fix helper (no `keys`, every character virtualKey 0 plus a
# unicode string) and with the layout check deleted (AZERTY 'a' then posts US key 0, which types 'q').
@test "fill key codes: real US-layout codes with shift for ASCII; unicode only where the layout has no key" {
  command -v swiftc >/dev/null || skip "swiftc unavailable"
  bin="$BATS_TEST_TMPDIR/cc-dia-act-ax"
  swiftc "$REPO/skills/dia-agent/cc-dia-act-ax.swift" -o "$bin" 2>"$BATS_TEST_TMPDIR/swiftc.log" \
    || { cat "$BATS_TEST_TMPDIR/swiftc.log"; false; }
  run "$bin" keys --layout com.apple.keylayout.US --value 'aZ1!_ ~"é'
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'layout=com.apple.keylayout.US\na\tkey 0\nZ\tkey 6 shift\n1\tkey 18\n!\tkey 18 shift\n_\tkey 27 shift\n \tkey 49\n~\tkey 50 shift\n"\tkey 39 shift\né\tunicode')" ]
  # every printable ASCII character has a key on US: none falls back to a string
  ascii=' !"#$%&'"'"'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\]^_`abcdefghijklmnopqrstuvwxyz{|}~'
  [ "${#ascii}" -eq 95 ]
  run "$bin" keys --layout com.apple.keylayout.US --value "$ascii"
  [ "$(grep -c $'\tkey ' <<<"$output")" -eq 95 ]
  # a layout whose key 0 is not 'a' (French AZERTY): the US code is never posted for it
  run "$bin" keys --layout com.apple.keylayout.French --value 'a'
  [ "$status" -eq 0 ]
  [ "${lines[1]}" = "$(printf 'a\tunicode')" ]
}
