#!/usr/bin/env bats
# shellcheck shell=bash
#   bats files are bash with @test sugar and shellcheck has no bats mode (SC1008).
# cc-thread — the per-box cursor view of cross-session mail (mail-v3 D9, cc-backlog 02ba4e52389a).
#
# The tool was adopted into bin/ with no suite. What these tests pin:
#   · READ-ONLY by construction — the whole point of the tool is that reading mail here does not
#     consume it, so no cursor, inbox or lock may change under any verb
#   · the per-line cursor marks (✓ acked · · surfaced · ⚠ waiting) and the UNDRAINED flag
#   · lookup by full key, prefix, suffix and case — the arm that was dead on macOS: `${u^^}` is a
#     bad substitution under the #!/bin/bash (3.2) shebang, so every lookup-by-argument died
#   · --pending lists only boxes with unsurfaced lines; archive/ is never read as a box
#
# Hermetic: CC_MAILBOX_DIR is a tmpdir and cc-sessions is stubbed on PATH, so the friendly-name
# lookup can never execute the operator's live registry reader.
# Assertion style: `[ ]` throughout (a non-final `[[ ]]`/`!` is errexit-exempt under bats).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  T="$REPO/bin/cc-thread"
  D="$BATS_TEST_TMPDIR"
  export HOME="$D/home"; mkdir -p "$HOME"
  export CC_MAILBOX_DIR="$D/mbox"; mkdir -p "$CC_MAILBOX_DIR/archive"
  mkdir -p "$D/bin"
  printf '#!/bin/bash\necho "[]"\n' > "$D/bin/cc-sessions"; chmod +x "$D/bin/cc-sessions"
  export PATH="$D/bin:$PATH"
  U=AB12CD34-2222-3333-4444-555555555555
  V=EF56AB78-6666-7777-8888-999999999999
}

box() { # <key> <lines> <seen> <acked>
  local i; : > "$CC_MAILBOX_DIR/$1.md"
  for i in $(seq 1 "$2"); do printf '2026-09-23T00:00:00Z [peer] line-%s\n' "$i" >> "$CC_MAILBOX_DIR/$1.md"; done
  printf '%s\n' "$3" > "$CC_MAILBOX_DIR/$1.seen"
  printf '%s\n' "$4" > "$CC_MAILBOX_DIR/$1.acked"
}
snapshot() { (cd "$CC_MAILBOX_DIR" && find . -type f -exec cksum {} + | sort); }

@test "one box: cursor marks per line and the UNDRAINED flag" {
  box "$U" 4 3 1
  run "$T" "$U"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'lines=4  seen=3  acked=1'
  echo "$output" | grep -q 'UNDRAINED'
  [ "$(echo "$output" | grep -c '^  ✓ ')" -eq 1 ]
  [ "$(echo "$output" | grep -c '^  · ')" -eq 2 ]
  [ "$(echo "$output" | grep -c '^  ⚠ ')" -eq 1 ]
}

@test "lookup by prefix, by suffix, and case-insensitively (the arm dead under bash 3.2)" {
  box "$U" 1 1 1
  run "$T" ab12cd34;          [ "$status" -eq 0 ]; echo "$output" | grep -qF "[$U]"
  run "$T" 555555555555;      [ "$status" -eq 0 ]; echo "$output" | grep -qF "[$U]"
  run "$T" "$(echo "$U" | tr 'A-Z' 'a-z')"; [ "$status" -eq 0 ]; echo "$output" | grep -qF "[$U]"
  run "$T" nosuchbox
  [ "$status" -eq 1 ]
}

@test "bash-3.2 guard: no bash-4-only case-modification expansion in a #!/bin/bash tool" {
  head -1 "$T" | grep -qx '#!/bin/bash'
  # CODE lines only: the fix's own comment quotes the old spelling in prose.
  run bash -c 'grep -vE "^[[:space:]]*#" "$1" | grep -nE "\\$\\{[A-Za-z_][A-Za-z0-9_]*(\\^\\^?|,,?)"' _ "$T"
  [ "$status" -eq 1 ]
  # POSITIVE CONTROL: the same predicate convicts the pre-fix line, so a green here is not vacuous.
  run bash -c 'printf "%s\n" "case \"\${u^^}\" in" | grep -nE "\\$\\{[A-Za-z_][A-Za-z0-9_]*(\\^\\^?|,,?)"'
  [ "$status" -eq 0 ]
}

@test "--pending lists only boxes with unsurfaced lines" {
  box "$U" 3 1 1
  box "$V" 2 2 2
  run "$T" --pending
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF "[$U]"
  [ "$(echo "$output" | grep -cF "[$V]")" -eq 0 ]
  box "$U" 3 3 3
  run "$T" --pending
  echo "$output" | grep -q 'no undrained mail'
}

@test "--me resolves the drain's own pane spelling (CC_PANE_ID, else ITERM_SESSION_ID's tail)" {
  box 117 2 0 0
  CC_PANE_ID=117 run "$T" --me
  [ "$status" -eq 0 ]; echo "$output" | grep -qF '[117]'
  run env -u CC_PANE_ID ITERM_SESSION_ID=w0t0p0:117 "$T" --me
  [ "$status" -eq 0 ]; echo "$output" | grep -qF '[117]'
}

@test "the default listing shows every box with mail, newest first, and never an archived one" {
  box "$U" 1 1 1; touch -d '2026-01-01' "$CC_MAILBOX_DIR/$U.md" 2>/dev/null || touch -t 202601010000 "$CC_MAILBOX_DIR/$U.md"
  box "$V" 1 1 1
  printf 'x\n' > "$CC_MAILBOX_DIR/archive/ARCHIVED-KEY.md"
  : > "$CC_MAILBOX_DIR/EMPTYBOX.md"
  run "$T"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | grep -c '^── ')" -eq 2 ]
  [ "$(echo "$output" | grep -m1 '^── ' | grep -cF "[$V]")" -eq 1 ]
  [ "$(echo "$output" | grep -cF 'ARCHIVED-KEY')" -eq 0 ]
}

@test "READ-ONLY: no verb changes a single byte of the mailbox dir" {
  box "$U" 4 2 1; box "$V" 2 0 0
  local before; before="$(snapshot)"
  "$T" >/dev/null; "$T" --pending >/dev/null; "$T" "$U" >/dev/null
  CC_PANE_ID="$V" "$T" --me >/dev/null
  [ "$(snapshot)" = "$before" ]
}
