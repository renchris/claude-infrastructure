#!/usr/bin/env bats
# What a refused relaunch leaves on the pane — the replay of husk pane 435 (lr-wake 2026-10-18, RC8,
# REPORT §4 Wave H2; g-message-design §2.2 and §5.5 test 2).
#
# THE SCREEN THAT NIGHT, 7 lines (about 20 rows at 57 columns) for one fact, "2e9ed9f2 did not start":
#   the echoed launch line (≈400 chars) · `-- lr-fire-resume: tombstone check: …` · `lr-preseed: …` ·
#   `✗ capacity-admit: REFUSING resume 2e9ed9f2-… (refusal 3 of 3; … the next evaluation ADMITS …)` ·
#   `Shed load first …, then re-run this exact command.` · `Override …: CC_ADMIT_GATE=off ; raise the
#   bar: CC_ADMIT_MAX_LOAD_PER_CORE=<n>` (the wrong knob: the active ceiling refused) ·
#   `cc-pane-runner: the fleet launch line exited 9 — keeping a shell for diagnosis/resume`.
#
# THE REPLAY. The same chain, end to end: bin/cc-pane-runner in env mode (the fleet's interactive
# delivery) runs a rescue wrapper that execs lr-fire-resume.sh, whose real capacity-admit.sh refuses
# on the term that refused that night — 8 sessions mid-turn + 1 > active ceiling 8, fed through the
# library's own CC_SP_ACTIVE_OVERRIDE seam, no gate switched off. Everything the pane receives on fd 2
# is the screen. Two outcomes, because Wave C made the refusal durable:
#   · nothing can retry it (the queue cannot be written) — pane 435's own situation. ≤ 2 lines, the
#     first `✗ <sid8> …`, carrying ONE `▶` command of ≤ 40 characters, and that command, run with
#     --dry-run, does not refuse (g V2.6: a one-line banner naming a command that refuses is the same
#     false promise in fewer characters);
#   · the queue holds it — ≤ 2 lines, the first `⏸ <sid8> queued`, and nothing invites a re-run.

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  RUNNER="$REPO/bin/cc-pane-runner"
  FIRE="$REPO/scripts/limit-recover/lr-fire-resume.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/cfgdir"; mkdir -p "$CLAUDE_CONFIG_DIR"
  export LR_STATE_DIR="$BATS_TEST_TMPDIR/state"; mkdir -p "$LR_STATE_DIR"
  export CC_SAY_LOG="$BATS_TEST_TMPDIR/pane-say.jsonl"
  export CC_ADMIT_STATE_DIR="$BATS_TEST_TMPDIR/admit" CC_ADMIT_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_ADMIT_NOTIFY_BIN="$BATS_TEST_TMPDIR/notify"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s/pages.txt"\n' "$BATS_TEST_TMPDIR" > "$CC_ADMIT_NOTIFY_BIN"
  chmod +x "$CC_ADMIT_NOTIFY_BIN"
  # Pane 435's refusing term. Every other ambient input is pinned to a value that admits, so the
  # active ceiling is the term that answers; a budget no case reaches keeps a refusal a refusal.
  export CC_SP_ACTIVE_OVERRIDE=8 CC_ADMIT_ACTIVE_CEILING=8 CC_ADMIT_BUDGET=99
  export CC_ADMIT_HEADROOM_OVERRIDE=64 CC_ADMIT_SEGMENT_OVERRIDE=0 CC_ADMIT_LOADAVG_OVERRIDE=0
  export CC_SP_TREES_OVERRIDE=0            # the reserve-slots term's live `ps` census, pinned too
  export LR_PRESEED_DONE=test CC_RESUME_TOMBSTONE_LIB="" CC_RESUME_TEAMMATE_GUARD=checked
  unset LR_RUN LR_RUN_DIR LR_ADMIT_TOKEN LR_SUBMIT_TOKEN CC_PANE_EXIT_OWED CC_SAY_VERBOSE COLUMNS
  unset KITTY_WINDOW_ID CC_PANE_CMD_DIR CLAUDE_CODE_SESSION_ID CC_PANE_ID ITERM_SESSION_ID
  unset CC_PANE_CMD CC_PANE_CMD_INTERACTIVE   # injected into every fired pane; pane() sets them per call
  SID="2e9ed9f2-9e21-4161-a0f7-10b329ade8f0"
  CFG="$BATS_TEST_TMPDIR/.claude-tertiary"; mkdir -p "$CFG/projects"
  WT="$BATS_TEST_TMPDIR/personal"; mkdir -p "$WT"
  # A claude that would only run if the gate let the launch through.
  export LR_CLAUDE_BIN="$BATS_TEST_TMPDIR/claude"
  printf '#!/bin/bash\necho SPAWNED >> "%s/spawned"\nexit 0\n' "$BATS_TEST_TMPDIR" > "$LR_CLAUDE_BIN"
  chmod +x "$LR_CLAUDE_BIN"
  # The rescue wrapper pane 435 ran (/tmp/lr-rescue/resume-2e9ed9f2.sh), with the launcher's own
  # trailing MCP flags, which the wrapper ignores.
  RESCUE="$BATS_TEST_TMPDIR/resume-2e9ed9f2.sh"
  printf '#!/bin/bash\nexec /bin/bash %q %q %q %q --model m --effort high --prompt %q\n' \
    "$FIRE" "$CFG" "$WT" "$SID" "continue the work" > "$RESCUE"
  chmod +x "$RESCUE"
  # The pane's $SHELL. The runner runs a fleet line as `$SHELL -l -i -c <line>` and then becomes
  # `$SHELL -l -i`; a real interactive shell without a tty would add its own job-control lines to the
  # screen under test, so this one runs the line under bash and ends where the operator's prompt is.
  export SHELL="$BATS_TEST_TMPDIR/sh"
  # shellcheck disable=SC2016  # the $3/$4/$l belong to the generated stub and must reach it unexpanded
  printf '#!/bin/bash\n[ "$3" = -c ] || exit 0\nl="${4//nocorrect /}"\nexec /bin/bash -c "$l"\n' > "$SHELL"
  chmod +x "$SHELL"
}

# The pane: the runner in env mode, exactly as handoff-fire / lr-lib deliver a fleet line.
pane() {
  CC_PANE_CMD="cd $WT && nocorrect CC_ACCOUNT_PINNED=1 $RESCUE --strict-mcp-config --mcp-config=/var/folders/x/cc-mcp-userscope-.claude-tertiary.json" \
    CC_PANE_CMD_INTERACTIVE=1 run timeout 120 /bin/bash "$RUNNER" </dev/null
  # What a terminal draws: lr-fire-resume resets mouse reporting with private-mode CSIs (`ESC[?1000l`
  # …), which a screen consumes without a glyph; they would otherwise prefix line 1 here.
  output="$(printf '%s' "$output" | sed $'s/\e\\[?[0-9;]*[hl]//g')"
}
screen_lines() { printf '%s\n' "$output" | grep -c '[^[:space:]]' || true; }

# cc-lr, hermetic: the same stubs tests/cc-lr-front.bats pins, so nothing reads or drives the live fleet.
cclr_env() {
  export LR_MOVE_ENV_DIR="$BATS_TEST_TMPDIR/penv"; mkdir -p "$LR_MOVE_ENV_DIR"
  export CC_LR_FIND_BIN="$BATS_TEST_TMPDIR/cc-find" CC_LR_FLEET_BIN="$BATS_TEST_TMPDIR/lr-fleet.sh"
  export CC_LR_HANDOFF_BIN="$BATS_TEST_TMPDIR/lr-handoff.sh" CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/claude-accounts"
  export CC_LR_POLLER_LABEL="com.reso.lr-reset-poller"
  # cc-find's row for 2e9ed9f2 that night: on next3 (transplanted), no live process, last word a limit.
  printf '#!/bin/bash\nprintf "%%s\\t-\\tclaude-tertiary\\t%%s\\t%%s\\t-\\tLIMITED\\n" %q %q %q\n' \
    "$SID" "$CFG" "$WT" > "$CC_LR_FIND_BIN"
  local b
  for b in "$CC_LR_FLEET_BIN" "$CC_LR_HANDOFF_BIN" "$CC_ACCOUNTS_BIN"; do
    printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s/driven.argv"\nexit 97\n' "$BATS_TEST_TMPDIR" > "$b"
  done
  chmod +x "$CC_LR_FIND_BIN" "$CC_LR_FLEET_BIN" "$CC_LR_HANDOFF_BIN" "$CC_ACCOUNTS_BIN"
}

@test "RED-PROOF pane 435, nothing retries: ≤ 2 lines, the first ✗ naming the sid8, one ▶ of ≤ 40 chars" {
  : > "$LR_STATE_DIR/requests"      # a file where the queue's directory belongs: the request cannot be written
  pane
  [ ! -e "$BATS_TEST_TMPDIR/spawned" ] || { echo "the refused launch spawned claude"; false; }
  local n first act
  n="$(screen_lines)"
  [ "$n" -le 2 ] || { echo "$n lines on the pane:"; echo "$output"; false; }
  first="$(printf '%s\n' "$output" | grep '[^[:space:]]' | head -1)"
  [[ "$first" == "✗ "* ]] || { echo "line 1 is not a ✗ verdict: $first"; false; }
  [[ "$first" == *"${SID:0:8}"* ]] || { echo "line 1 does not name ${SID:0:8}: $first"; false; }
  [ "$(printf '%s\n' "$output" | grep -c '▶')" = 1 ] || { echo "not exactly one ▶: $output"; false; }
  act="$(printf '%s\n' "$output" | sed -n 's/.*▶ //p')"
  [ -n "$act" ] || { echo "no ▶ command on the pane: $output"; false; }
  [ "${#act}" -le 40 ] || { echo "the ▶ command is '${act}' (${#act} chars)"; false; }
  [[ "$output" != *"re-run this exact command"* ]] || { echo "$output"; false; }
  [[ "$output" != *"cc-pane-runner"* ]] || { echo "the runner spoke after the launcher: $output"; false; }
  [[ "$output" != *"$RESCUE"* ]] || { echo "the launch line was echoed: $output"; false; }
  # every line fits the 57-column pane (≤ 56 cells; this vocabulary is single-cell)
  local l
  while IFS= read -r l; do
    [ "$(printf '%s' "$l" | LC_ALL=en_US.UTF-8 wc -m | tr -d ' ')" -le 56 ] || { echo "too wide: $l"; false; }
  done <<<"$output"
  printf '%s' "$act" > "$BATS_TEST_TMPDIR/act"
}

@test "RED-PROOF pane 435: the printed ▶ command, run with --dry-run, does not refuse" {
  : > "$LR_STATE_DIR/requests"
  pane
  local act; act="$(printf '%s\n' "$output" | sed -n 's/.*▶ //p')"
  [[ "$act" == "cc-lr "* ]] || { echo "the ▶ command is not a cc-lr verb: '$act'"; false; }
  cclr_env
  # shellcheck disable=SC2086  # the printed command is split exactly as a paste would split it
  run bash "$REPO/bin/cc-lr" ${act#cc-lr } --dry-run
  [ "$status" -eq 0 ] || { echo "rc $status: $output"; false; }
  [[ "$output" != *"REFUSED"* ]] || { echo "$output"; false; }
  [ ! -e "$BATS_TEST_TMPDIR/driven.argv" ] || { echo "a dry run drove something:"; cat "$BATS_TEST_TMPDIR/driven.argv"; false; }
}

@test "RED-PROOF pane 435, queued: ≤ 2 lines, the first ⏸ <sid8> queued, no invitation to re-run" {
  pane
  [ "$status" -eq 0 ] || { echo "rc $status: $output"; false; }
  [ -f "$LR_STATE_DIR/requests/$SID.cc-lr.json" ] || { echo "no request written"; ls -R "$LR_STATE_DIR"; false; }
  local n first
  n="$(screen_lines)"
  [ "$n" -le 2 ] || { echo "$n lines on the pane:"; echo "$output"; false; }
  first="$(printf '%s\n' "$output" | grep '[^[:space:]]' | head -1)"
  [[ "$first" == "⏸ ${SID:0:8} queued"* ]] || { echo "line 1: $first"; false; }
  [[ "$output" != *"re-run this exact command"* ]] || { echo "$output"; false; }
  [[ "$output" != *"refusal 1 of"* ]] || { echo "budget arithmetic on the pane: $output"; false; }
  [[ "$output" != *"cc-pane-runner"* ]] || { echo "$output"; false; }
}

@test "the knob in the detail names the term that refused (the active ceiling), and only there" {
  : > "$LR_STATE_DIR/requests"
  pane
  [[ "$output" != *"CC_ADMIT_MAX_LOAD_PER_CORE"* ]] || { echo "the wrong knob on the pane: $output"; false; }
  grep -q 'knob CC_ADMIT_ACTIVE_CEILING' "$CC_SAY_LOG" || { echo "no knob in the detail:"; cat "$CC_SAY_LOG"; false; }
  # the preflight notes reached the log, not the pane
  grep -q '"verdict":"preseed skipped"' "$CC_SAY_LOG" || { cat "$CC_SAY_LOG"; false; }
  grep -q '"verdict":"fleet launch line"' "$CC_SAY_LOG" || { cat "$CC_SAY_LOG"; false; }
  [[ "$output" != *"preseed"* ]] || { echo "$output"; false; }
  CC_SAY_VERBOSE=1 pane
  [[ "$output" == *"knob CC_ADMIT_ACTIVE_CEILING"* ]] || { echo "verbose does not name the knob: $output"; false; }
}

@test "no SGR-2 anywhere on the pane, with colour forced on" {
  : > "$LR_STATE_DIR/requests"
  CC_SAY_COLOR=1 pane
  [ "$(printf '%s' "$output" | grep -c $'\e\[2m')" = 0 ] || { printf '%q\n' "$output"; false; }
  [[ "$output" == *$'\e[38;2;'* ]] || { echo "colour was forced but nothing is coloured: $output"; false; }
}
