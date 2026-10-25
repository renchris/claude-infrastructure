#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031
#   Structurally false under bats (every @test body is its own subshell; `run` sets $output there).
#
# cc-resume-layout.sh --desktops --restore --dry-run against the 2026-10-25 reboot: the 03:45 kitty
# tree of dead kitty 1881 (10 OS windows, ~40 panes), its reconstructed roster, and the 10-row
# resume plan the incident used. That restore came back with every two-pane window split 1/3 : 2/3
# (or 1/4 : 3/4), 11 bare shells in session-less panes, and voiceink in a window of its own.
#
# Contracts under test (all on the DRY plan, so nothing here needs kitty):
#   · widths: every pane of the 03:45 tree was even (73 columns x4, 98/99/99 x3), so every split the
#     plan makes is even — no `bias=` on any launch line;
#   · no shells: a recorded pane that held no session is left out unless --keep-shells, and a
#     teammate pane (a claude whose argv names --agent-id / --parent-session-id) never comes back;
#   · pane → session: a resume argv is proof (voiceink, whose roster names no pane, goes back to
#     pane 12, which ran `reso-resume-one … 509e3aad…`); a session id inside some other argument is
#     not (2b3becea appears inside pane 323's argv and stays in its roster pane, window 18); the
#     roster pane stands when the CLAUDE process cwd agrees (3f1c1301 in pane 297, whose kitty
#     `cwd` is the shell's, lead-idle-fix, while its claude ran in lkw-scope-floor).
#
# Fixture: tests/fixtures/kitty-reboot-2026-10-25/ — hb.kitty-ls.json minimized from the
# reconstructed heartbeat (~/incident-2026-10-25/rca/session-inventory/reconstructed-hb/1881/): ids,
# layout_state, cwd, columns and lines kept; each process argv cut to its first two words, its
# session-id and team flags, and any argument holding a session id shortened around it. The
# roster, displays and resume-plan.tsv are copied as they were.
#
# RED-proof: against the pre-change script (`git show origin/main:bin/cc-resume-layout.sh`, the
# parent of this change) case 1 fails at the bias check (bias=66.6667 on window 8, 75.0000 on 17 and
# 18) and at the shell check (11 shell lines); case 2 fails (shells but voiceink in its own window);
# case 3's negative control passes there vacuously, its positive half fails (voiceink has no pane).

bats_require_minimum_version 1.5.0

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  FIXD="$BATS_TEST_DIRNAME/fixtures/kitty-reboot-2026-10-25"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_HEARTBEAT_DIR="$BATS_TEST_TMPDIR/heartbeat" CC_BOOT_RESUME_STATE_DIR="$BATS_TEST_TMPDIR/boot-resume"
  export CC_ADMIT_GATE=off
  FIX="$BATS_TEST_TMPDIR/tree"; mkdir -p "$FIX/bin" "$FIX/scripts/lib" "$FIX/scripts/limit-recover"
  cp "$REPO/bin/cc-resume-layout.sh" "$FIX/bin/"
  printf 'cc_capacity_admit() { return 0; }\ncc_capacity_probe() { return 0; }\ncc_capacity_admit_reason() { printf stub; }\n' \
    > "$FIX/scripts/lib/capacity-admit.sh"
  printf 'cc_log_pane_spawn() { :; }\n' > "$FIX/scripts/lib/pane-spawn-log.sh"
  LAYOUT="$FIX/bin/cc-resume-layout.sh"
  T="$BATS_TEST_TMPDIR/t"; mkdir -p "$T"; cp "$FIXD"/hb.* "$T/"
  unset KITTY_WINDOW_ID KITTY_PID CC_TERM_KITTY CC_TERM_KITTY_TO CC_RESTORE_TREE
}

plan() { run --separate-stderr env PATH=/usr/bin:/bin /bin/bash "$LAYOUT" --desktops --restore --dry-run --tree "$T/hb.kitty-ls.json" "$@" < "$FIXD/resume-plan.tsv"; }
launch_lines() { printf '%s\n' "$stderr" | grep -E '^DRY \[CC-DESK-[0-9]+ [^]]*\] (head|tab|vsplit|hsplit) '; }
win_of() { # <sid prefix> → the recorded window its pane is planned into (k<pid>w<n>)
  launch_lines | grep -- " $1" | sed -E 's/^DRY \[CC-DESK-[0-9]+ ([^]]*)\].*/\1/'
}

@test "reboot 2026-10-25: the 10 rows come back in 6 recorded windows, every split even, no shell" {
  plan
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c '^cc-resume-layout: tree oswin=')" -eq 6 ]
  [ "$(launch_lines | grep -cE '\] (head|vsplit|hsplit) [a-z0-9]+ [0-9a-f]{8}-')" -eq 10 ]
  ! launch_lines | grep -q ' shell ' || false
  ! launch_lines | grep -q 'bias=' || false                      # 03:45 was even, so even it is
  printf '%s\n' "$output" | grep -q 'src=ktreew8 .* panes=2 .* layout=splits:H(p,p) '
  printf '%s\n' "$output" | grep -q 'src=ktreew17 .* panes=2 .* layout=splits:H(p,p) '
  printf '%s\n' "$output" | grep -q 'src=ktreew18 .* panes=2 .* layout=splits:H(p,p) '
  # every session in its recorded window
  [ "$(win_of 509e3aad)" = ktreew7 ]     # voiceink: by pane 12's resume argv (no roster pane)
  [ "$(win_of 502bd860)" = ktreew7 ]
  [ "$(win_of 2b3becea)" = ktreew18 ]    # its id inside pane 323's argv is not proof
  [ "$(win_of 3f1c1301)" = ktreew26 ]
  [ "$(win_of 568f7c83)" = ktreew27 ]
}

@test "reboot 2026-10-25: --keep-shells brings the session-less panes back as shells, but never a teammate" {
  plan --keep-shells
  [ "$status" -eq 0 ]
  [ "$(launch_lines | grep -c ' shell ')" -ge 10 ]
  # window 26 held 3f1c1301 (297), its teammate lkw-ledger (298) and ba56f290 (327, not restored)
  printf '%s\n' "$output" | grep -q 'src=ktreew26 .* panes=1 claude=1 shells=0 '
}

@test "reboot 2026-10-25: a resume argv is proof of the pane; without it voiceink gets a window of its own" {
  python3 - "$T/hb.kitty-ls.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p))
for o in d:
    for t in o["tabs"]:
        for w in t["windows"]:
            if w["id"] == 12:
                w["foreground_processes"] = [{"cmdline": ["-zsh"], "cwd": w["cwd"]}]
json.dump(d, open(p, "w"))
PY
  plan
  [ "$status" -eq 0 ]
  # pane 12 is now a plain shell in voiceink's cwd, so the cwd rule may claim it: still window 7
  [ "$(win_of 509e3aad)" = ktreew7 ]
  # and with pane 12 gone from the record altogether, no pane holds it: a planned window
  python3 - "$T/hb.kitty-ls.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p))
for o in d:
    for t in o["tabs"]:
        for w in t["windows"]:
            if w["id"] == 12:
                w["cwd"] = "/nowhere"; w["foreground_processes"] = [{"cmdline": ["-zsh"], "cwd": "/nowhere"}]
json.dump(d, open(p, "w"))
PY
  plan
  [ "$status" -eq 0 ]
  [ "$(win_of 509e3aad)" != ktreew7 ]
  # a planned window opens on the display the recorded ones were on, fullscreen
  printf '%s\n' "$stderr" | grep -q '^DRY \[CC-DESK-7\] place on display 1B6097CB-8D65-4AE0-BEB3-68A968162BBE (-1358,-1440 2560x1440)$'
}
