#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031
#   Structurally false under bats (every @test body is its own subshell; `run` sets $output there).
#
# bin/cc-panes — the pane census cc-resume-layout's verdict now rests on (2026-10-25: a restore said
# launched=10 over 11 bare shells, because nothing read a pane back). Contracts, through the CLI
# against a kitty stub that answers `ls` from $K.ls and `get-text --match id:N` from $K.text.N:
#   · kind: CLAUDE (claude or its resume launcher) · TEAMMATE (--agent-id / --parent-session-id)
#     · SHELL (a bare login shell) · OTHER;
#   · session: an exact argv token after a resume launcher or --resume — never a substring of some
#     other argument, never a teammate's parent id;
#   · state from the screen: working (esc to interrupt) · prompt (❯ between two rules) · starting;
#   · --expect exits 0 only when every WID=SID / ?=SID is a CLAUDE pane resuming it, live; 1 with a
#     line per miss; 3 when kitty does not answer.
# RED-proof: new file; against a cc-panes whose resumed() matched substrings, case 2 reports pane 3
# as resuming 2b3becea; with the teammate check removed, case 2's pane 4 is CLAUDE.

bats_require_minimum_version 1.5.0

load helpers/cc-stub

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  PANES="$REPO/bin/cc-panes"
  export K="$BATS_TEST_TMPDIR/k"
  export CC_TERM_KITTY="$BATS_TEST_TMPDIR/kitty"
  cc_stub "$BATS_TEST_TMPDIR" kitty - <<'SH'
#!/bin/bash
printf '%s\n' "$*" >> "$K.log"
case " $* " in
  *" ls "*) [ -f "$K.down" ] && exit 1; cat "$K.ls" ;;
  *" get-text --match id:"*) for a; do :; done; cat "$K.text.${a#id:}" 2>/dev/null ;;
esac
SH
  export CC_DEFAULTS_BIN=""             # no Spaces read
  S1=11111111-1111-4111-8111-111111111111; S2=22222222-2222-4222-8222-222222222222
  cat > "$K.ls" <<JSON
[{"id":1,"platform_window_id":900,"tabs":[{"id":1,"windows":[
 {"id":1,"columns":76,"lines":60,"cwd":"/w","foreground_processes":[{"cmdline":["bash","/x/reso-resume-one","next","/w/a","$S1","br"],"cwd":"/w/a"}]},
 {"id":2,"columns":154,"lines":60,"cwd":"/w","foreground_processes":[{"cmdline":["-zsh"],"cwd":"/w/b"}]},
 {"id":3,"columns":76,"lines":60,"cwd":"/w","foreground_processes":[{"cmdline":["/x/bin/claude","--mcp-config=/tmp/cc-$S2-x.json"],"cwd":"/w/c"}]},
 {"id":4,"columns":76,"lines":60,"cwd":"/w","foreground_processes":[{"cmdline":["/x/claude.exe","--agent-id","lead@s","--parent-session-id","$S1"],"cwd":"/w/a"}]},
 {"id":5,"columns":76,"lines":60,"cwd":"/w","foreground_processes":[{"cmdline":["/x/bin/claude","--resume","$S2"],"cwd":"/w/d"}]}]}]}]
JSON
  rule='────────────────────────────────'
  printf 'output\n%s\n❯ \n%s\n  footer\n' "$rule" "$rule" > "$K.text.1"
  printf 'thinking\n  esc to interrupt\n' > "$K.text.5"
  printf 'Resuming…\n' > "$K.text.3"
}

col() { printf '%s\n' "$output" | awk -v p="$1" -v c="$2" '$3 == p { print $c }'; }

@test "table: each pane gets its kind, its resumed session and its screen state" {
  run "$PANES" --to unix:/tmp/fake
  [ "$status" -eq 0 ]
  [ "$(col 1 5)" = CLAUDE ];   [ "$(col 1 6)" = 11111111 ]; [ "$(col 1 7)" = prompt ]; [ "$(col 1 4)" = 76x60 ]
  [ "$(col 2 5)" = SHELL ];    [ "$(col 2 7)" = - ]
  [ "$(col 3 5)" = CLAUDE ];   [ "$(col 3 6)" = '?' ];      [ "$(col 3 7)" = starting ]
  [ "$(col 4 5)" = TEAMMATE ]
  [ "$(col 5 6)" = 22222222 ]; [ "$(col 5 7)" = working ]
  grep -q -- '--to unix:/tmp/fake ls' "$K.log"
  ! grep -q 'get-text --match id:2$' "$K.log" || false           # a shell's screen is never read
}

@test "a session id inside another argument, or as a teammate's parent, is not the pane's session" {
  run "$PANES" --to unix:/tmp/fake --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.[] | select(.pane == 3) | .sids | length')" = 0 ]
  [ "$(printf '%s' "$output" | jq -r '.[] | select(.pane == 4) | .kind')" = TEAMMATE ]
  [ "$(printf '%s' "$output" | jq -r '.[] | select(.pane == 4) | .sids | length')" = 0 ]
  [ "$(printf '%s' "$output" | jq -r '.[] | select(.pane == 1) | .cwd')" = /w/a ]   # the process cwd, not kitty's
}

@test "--expect: 0 when every row is live in its pane; 1 with one line per miss" {
  run "$PANES" --to unix:/tmp/fake --expect "1=$S1 5=$S2"
  [ "$status" -eq 0 ]
  [ "$output" = "cc-panes: expect ok=2 bad=0" ]
  run "$PANES" --to unix:/tmp/fake --expect "1=$S1 2=$S2 3=$S2 ?=33333333-3333-4333-8333-333333333333 ?=$S2"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qx "cc-panes: expect wid=2 sid=$S2 state=shell — pane 2 is SHELL, not Claude"
  printf '%s\n' "$output" | grep -qx "cc-panes: expect wid=3 sid=$S2 state=starting — pane 3 resumes no session id"
  printf '%s\n' "$output" | grep -qx 'cc-panes: expect wid=? sid=33333333-3333-4333-8333-333333333333 state=missing — no pane resumes it'
  printf '%s\n' "$output" | grep -qx 'cc-panes: expect ok=2 bad=3'
}

@test "--expect waits for a starting session, then judges what it reads" {
  printf 'Resuming…\n' > "$K.text.1"
  run "$PANES" --to unix:/tmp/fake --expect "1=$S1" --wait 0 --poll 1
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -q 'state=starting — not at a prompt yet'
  # the screen reaches its prompt while it polls
  ( sleep 1; printf 'x\n%s\n❯ \n%s\n' "────────────────" "────────────────" > "$K.text.1" ) &
  run "$PANES" --to unix:/tmp/fake --expect "1=$S1" --wait 6 --poll 1
  wait
  [ "$status" -eq 0 ]
}

@test "kitty not answering is exit 3, never a verdict about the panes" {
  touch "$K.down"
  run "$PANES" --to unix:/tmp/fake --expect "1=$S1"
  [ "$status" -eq 3 ]
  run "$PANES" --to unix:/tmp/fake
  [ "$status" -eq 3 ]
}
