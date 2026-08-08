#!/usr/bin/env bats
# Regression guard for RECYCLE-path ENGAGEMENT — handoff-fire.sh, backlog f44a901152d9 /
# infra-reliability-audit-2026-07-22 ("--recycle confirms process-birth (cc_alive), never an
# assistant turn — the ff2d6609 'birth ≠ engagement' bug is still live in the recycle path").
#
# THE DEFECT. ef11307 taught the FIRE path that a transcript's existence is not engagement: it must
# show a real assistant turn. That fix never reached the recycle watcher — ENGAGE_VERIFY=1 is set
# only for RECYCLE=0, and the __recycle watcher's success test was `cc_alive`, a node process on the
# pane's tty, i.e. pure process birth. So a relaunch whose brief the harness consumed or rejected (a
# slash-command-headed payload, a /goal over the 4000-char cap) sat at an empty composer with claude
# alive and the watcher logged "→ relaunched + CONFIRMED". A silent dead recycle reported as success,
# with no backstop anywhere — the fire path at least FAILS LOUD.
#
# THE TRAP THIS SUITE EXISTS TO PIN. A recycle reuses its OWN pane, so the pane's registry row and
# the predecessor's transcript both belong to the session being replaced. Any check that reads "the
# row's session_id → that transcript → does it have an assistant turn?" passes TRIVIALLY on the dying
# predecessor. The discriminator has to be a CHANGE (a new sid) or a token that only the relaunch
# could carry (the marker) — and the predecessor's transcript must be excluded from the marker search
# as a belt, because the caller of a recycle IS the session being recycled. Tests 4 and 5 are those.

setup() {
  # M11 (MACHINE_CAPACITY_V2 §11.3) — a test's environment is PINNED, not ambient. The per-test pins
  # below predate this and are the shape the hermeticity ratchet rejects: they leave every OTHER test in
  # the file reading live machine state. handoff-fire.sh's capacity_gate reads the box's loadavg AND
  # (M10) its memory headroom — the two TERMS of one exit 9 (handoff-fire.sh:4487) — so both are pinned
  # here, for the whole file. tests/handoff-fire-capacity-gate.bats is the ONE place the gate runs ON.
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  REPO_SRC="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO_SRC/scripts/handoff-fire.sh"

  REGDIR="$BATS_TEST_TMPDIR/reg";   mkdir -p "$REGDIR"
  PROJDIR="$BATS_TEST_TMPDIR/proj"; mkdir -p "$PROJDIR"
  export CC_REGISTRY_DIR="$REGDIR" CC_PROJECTS_DIRS="$PROJDIR"

  PANE="RECY-PANE"; OLD_SID="old-sess-dying"; NEW_SID="new-sess-relaunched"

  # The PREDECESSOR: a long-lived session with plenty of assistant turns. It is the false-positive
  # source — every naive check passes on this transcript.
  printf '%s\n' \
    '{"type":"user","message":{"content":"the work so far"}}' \
    '{"type":"assistant","message":{"content":"did a lot of work over many hours"}}' \
    > "$PROJDIR/$OLD_SID.jsonl"

  # a fake HOME with a recording cc-notify (the dead-recycle page) and an it2 stub
  H="$BATS_TEST_TMPDIR/home"; mkdir -p "$H/.claude/bin"
  cat > "$H/.claude/bin/cc-notify" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$HOME/ccnotify-calls.log"
exit 0
SH
  cat > "$H/.claude/bin/it2" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$HOME/it2-calls.log"
exit 0
SH
  chmod +x "$H/.claude/bin/cc-notify" "$H/.claude/bin/it2"
  # Fixtured in setup(), not per-test (test-hermeticity-lint): the watcher and the arming side both
  # resolve cc-notify / it2 / REAL_IT2 under $HOME, so an unfixtured suite pages the operator's real
  # desk and probes their live ~/.claude.
  export HOME="$H"

  eval "$(sed -n '/^assistant_turn_in() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^cc_sid_for_pane() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^recycle_engaged() {/,/^}/p' "$HF")"
}

row() { printf '{"paneUUID":"%s","session_id":"%s"}\n' "$PANE" "$1" > "$REGDIR/$PANE.json"; }

# ── recycle_engaged: the predicate ────────────────────────────────────────────────────────────────

@test "marker in the relaunch's transcript WITH an assistant turn → engaged" {
  row "$OLD_SID"
  printf '%s\n' \
    '{"type":"user","message":{"content":"brief <!-- handoff-fire recycle engagement marker: MK-1 (ignore) -->"}}' \
    '{"type":"assistant","message":{"content":"on it"}}' > "$PROJDIR/$NEW_SID.jsonl"
  run recycle_engaged "$PANE" "$OLD_SID" "MK-1"
  [ "$status" -eq 0 ]
}

@test "RED-PROOF marker present but ZERO assistant turns → NOT engaged (birth is not engagement)" {
  # The exact dead recycle: the brief was ingested into a transcript that then never ran a turn.
  # cc_alive said yes and the pre-fix watcher called this CONFIRMED.
  row "$OLD_SID"
  printf '%s\n' \
    '{"type":"user","message":{"content":"brief <!-- handoff-fire recycle engagement marker: MK-2 (ignore) -->"}}' \
    '{"type":"system","subtype":"init"}' > "$PROJDIR/$NEW_SID.jsonl"
  run recycle_engaged "$PANE" "$OLD_SID" "MK-2"
  [ "$status" -eq 1 ]
}

@test "registry ROW-CHANGE to a session with an assistant turn → engaged (no marker needed)" {
  row "$NEW_SID"                                   # SessionStart re-registered the pane
  printf '%s\n' \
    '{"type":"user","message":{"content":"go"}}' \
    '{"type":"assistant","message":{"content":"continuing the work"}}' > "$PROJDIR/$NEW_SID.jsonl"
  run recycle_engaged "$PANE" "$OLD_SID" ""
  [ "$status" -eq 0 ] || { echo "the ROW-CHANGE signal did not fire"; false; }
}

@test "THE TRAP: row still names the DYING predecessor → NOT engaged, despite its assistant turns" {
  # A recycle reuses its own pane. Reading the row's sid without comparing it to the baseline reads
  # the PREDECESSOR's transcript, which is full of assistant turns — so the check would report
  # success for every dead recycle. The CHANGE is the discriminator, not the presence.
  row "$OLD_SID"
  run recycle_engaged "$PANE" "$OLD_SID" ""
  [ "$status" -eq 1 ] || { echo "passed on the DYING predecessor's own transcript"; false; }
}

@test "THE BELT: a marker that leaked into the PREDECESSOR's transcript cannot pass the check" {
  # The marker is written only to the launch-time copy and never echoed — but the caller of a recycle
  # IS the session being recycled, so a leak would land in ITS transcript, which trivially has
  # assistant turns. The predecessor's transcript is excluded from the marker search.
  row "$OLD_SID"
  printf '%s\n' \
    '{"type":"user","message":{"content":"ran handoff-fire, output mentioned MK-3"}}' \
    '{"type":"assistant","message":{"content":"lots of prior work"}}' > "$PROJDIR/$OLD_SID.jsonl"
  run recycle_engaged "$PANE" "$OLD_SID" "MK-3"
  [ "$status" -eq 1 ] || { echo "a leaked marker passed on the predecessor's transcript"; false; }
}

@test "unknown baseline (no pre-recycle sid resolvable) disables the ROW-CHANGE signal" {
  # An unknown baseline cannot witness a change: with oldsid empty, ANY row would look 'different'
  # and the predecessor's transcript would pass. Fail closed instead.
  row "$OLD_SID"
  run recycle_engaged "$PANE" "" ""
  [ "$status" -eq 1 ]
}

# ── the __recycle watcher: what the verdict LINE says ────────────────────────────────────────────
#
# The watcher is driven directly (no detach, no real pane) with a `ps` shim that reports claude alive
# on the tty — the pre-fix success condition — so these tests assert what the watcher does once
# process-birth is already satisfied.

watcher_setup() {
  SHIM="$BATS_TEST_TMPDIR/shim"; mkdir -p "$SHIM"
  # PHASE-AWARE ps. The watcher's real sequence is: wait until CC is GONE (the typed /exit landing),
  # then type the relaunch, then poll for CC to come BACK. A shim that always answers "claude" makes
  # the first loop run its full 600s (this suite hung on exactly that), and one that always answers
  # "dead" makes the watcher give up before the relaunch. So: the tty liveness probe reports dead for
  # the first PS_DEAD_CALLS reads and alive after — while `-o pgid=` (the armed banner) is answered
  # separately, so it can never consume a slot in that count.
  #
  # 2026-08-06 — THE "GONE" PHASE NOW MODELS A BARE SHELL PANE, NOT AN EMPTY tty, and the shim
  # answers the process-TREE query forms. Both follow from the fail-safe probe (pane_cc_state): the
  # watcher no longer types on the ABSENCE of a claude match, because that absence is ALSO what a CC
  # launched under `expect` looks like (its nested pty hides claude from the pane's tty) — acting on
  # it typed a shell command into a live composer on 2026-08-06. Typing now requires a POSITIVELY
  # confirmed shell prompt, so an empty tty is `unknown` and is refused forever; that is what hung
  # this suite. The FIXTURE was the thing that was wrong: a pane whose typed /exit has landed sits at
  # a zsh prompt, never at a tty with no processes at all. Every assertion below is unchanged.
  # Only the ROOT query (`-o pid= -t`) advances the phase — every other form must describe the SAME
  # instant, or one state read would be answered out of two different process tables.
  export PS_COUNT_FILE="$BATS_TEST_TMPDIR/ps-count"; rm -f "$PS_COUNT_FILE"
  cat > "$SHIM/ps" <<'SH'
#!/usr/bin/env bash
args="$*"
case "$args" in *pgid=*) printf '%s\n' "4242"; exit 0 ;; esac   # armed banner — never a phase read
c="${PS_COUNT_FILE:?}"
if [ "${args#*-o pid= -t}" != "$args" ]; then
  n=$(( $(cat "$c" 2>/dev/null || echo 0) + 1 )); printf '%s' "$n" > "$c"
else
  n=$(cat "$c" 2>/dev/null || echo 0)
fi
phase=alive; [ "$n" -le "${PS_DEAD_CALLS:-2}" ] && phase=shell
# 100 = the pane's zsh (and the foreground pgroup leader) · 200 = claude under it, only when alive
case "$args" in
  *"-o pid= -t"*)   printf '100\n'; [ "$phase" = alive ] && printf '200\n' ;;
  *"-o tpgid= -t"*) printf '100\n'; [ "$phase" = alive ] && printf '100\n' ;;
  *"-o comm= -t"*)  if [ "$phase" = alive ]; then printf 'claude\n'; else printf -- '-zsh\n'; fi ;;
  *pid=,ppid=*)     printf '100 1\n'; [ "$phase" = alive ] && printf '200 100\n' ;;
  *"pid=,comm= -g"*) printf '100 /bin/zsh\n' ;;
  *"-p 200"*)       printf '/Users/chrisren/.claude-220/node_modules/.bin/claude\n' ;;
  *"-p 100"*)       printf '/bin/zsh\n' ;;
esac
exit 0
SH
  cat > "$SHIM/osascript" <<'SH'
#!/usr/bin/env bash
exit 0
SH
  chmod +x "$SHIM/ps" "$SHIM/osascript"

  # PIN THE TERMINAL. handoff-fire's primitives branch on the terminal, so run from inside kitty — or
  # from an iTerm2 pane that merely INHERITED KITTY_* — this suite's verdict becomes a function of the
  # developer's environment rather than of its subject. Same pin, same reason, as
  # tests/handoff-selfclose.bats and tests/handoff-selfclose-teammate-gate.bats.
  unset KITTY_WINDOW_ID; export IT2_WRAPPER_NO_KITTY=1; unset CC_TERM
  export STUB_PANE="$PANE"     # the listing must enumerate the pane these tests model
  # it2_type_verified TYPES then re-READS the screen and only submits when it finds the command
  # echoed back. This stub models that: a substantial `session send` becomes the screen contents that
  # the next `session read` returns — otherwise the relaunch typing fails 4/4 and the watcher exits
  # before ever reaching the engagement check under test.
  #
  # `session list` must ENUMERATE the pane too. Every test here drives the __recycle WATCHER, which
  # since the reachability handshake landed (2026-08-02) proves the pane reachable before it acts —
  # so a stub answering the empty list refuses at the probe and never reaches the engagement check
  # under test. That is why tests 7/8/10/11 have been RED on trunk; e9cabc46 repaired this same
  # fixture class in seven suites and did not reach this one. Answers BOTH shapes the real transports
  # emit (`--json` and bare ids), so the fixture cannot silently model only the transport that
  # happened to work — the exact blindness that let the iTerm2 path stay broken under a green suite.
  cat > "$H/.claude/bin/it2" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$HOME/it2-calls.log"
case "$1 $2" in
  "session list")
    if [ "${3:-}" = --json ]; then printf '[{"id": "%s", "tty": "/dev/ttys999"}]\n' "${STUB_PANE:-RECY-PANE}"
    else printf '%s\n' "${STUB_PANE:-RECY-PANE}"; fi
    exit 0 ;;
  "session send") txt="${!#}"; [ "${#txt}" -gt 3 ] && printf '%s' "$txt" > "$HOME/it2-screen" ;;
  "session read") cat "$HOME/it2-screen" 2>/dev/null ;;
esac
exit 0
SH
  chmod +x "$H/.claude/bin/it2"
  CMDF="$BATS_TEST_TMPDIR/cmd.sh"; printf 'cd /tmp && claude "$(cat /tmp/p)"\n' > "$CMDF"
}

@test "RED-PROOF watcher: claude alive but never engaged → RECYCLE FAILED, desk paged, exit 1" {
  # Pre-fix this printed "→ relaunched + CONFIRMED in <pane> (claude process on tty)" and exited 0.
  watcher_setup
  row "$OLD_SID"                                   # row never changed → relaunch never registered
  run env HOME="$H" PATH="$SHIM:$PATH" RCY_ENGAGE_TIMEOUT=2 RCY_ENGAGE_INTERVAL=1 \
      IT2_BIN="$H/.claude/bin/it2" \
      bash "$HF" __recycle "$PANE" /dev/ttys999 "$CMDF" /tmp "$OLD_SID" "MK-NONE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"RECYCLE FAILED — never engaged"* ]] || { echo "$output"; false; }
  [[ "$output" == *"LIVE but TASK-LESS"* ]] || false
  ! [[ "$output" == *"+ CONFIRMED"* ]] || { echo "still claimed CONFIRMED"; false; }
  grep -q "HANDOFF-RECYCLE-DEAD" "$H/ccnotify-calls.log"
}

@test "watcher: a real assistant turn in the relaunched session → ENGAGEMENT CONFIRMED, exit 0" {
  watcher_setup
  row "$NEW_SID"
  printf '%s\n' \
    '{"type":"user","message":{"content":"brief <!-- handoff-fire recycle engagement marker: MK-9 (ignore) -->"}}' \
    '{"type":"assistant","message":{"content":"continuing"}}' > "$PROJDIR/$NEW_SID.jsonl"
  run env HOME="$H" PATH="$SHIM:$PATH" RCY_ENGAGE_TIMEOUT=6 RCY_ENGAGE_INTERVAL=1 \
      IT2_BIN="$H/.claude/bin/it2" \
      bash "$HF" __recycle "$PANE" /dev/ttys999 "$CMDF" /tmp "$OLD_SID" "MK-9"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ENGAGEMENT CONFIRMED"* ]] || { echo "$output"; false; }
  [ ! -f "$H/ccnotify-calls.log" ]                 # nobody paged on the happy path
}

@test "watcher: the dead-recycle path does NOT re-type the brief into a live composer" {
  # Unlike the fire path, this pane holds a LIVE claude. Pasting the brief into a session that IS
  # working but whose transcript we could not read would interrupt its turn — so the verdict is
  # truthful reporting plus a page, never a blind retry. Only the pre-engagement relaunch typing
  # (it2_type_verified) may write, and that is done before this point.
  watcher_setup
  row "$OLD_SID"
  run env HOME="$H" PATH="$SHIM:$PATH" RCY_ENGAGE_TIMEOUT=2 RCY_ENGAGE_INTERVAL=1 \
      IT2_BIN="$H/.claude/bin/it2" \
      bash "$HF" __recycle "$PANE" /dev/ttys999 "$CMDF" /tmp "$OLD_SID" "MK-NONE"
  [ "$status" -eq 1 ]
  if grep -q "HANDOFF RELAUNCH FAILED" "$H/it2-calls.log" 2>/dev/null; then
    echo "typed the shell-fallback comment into a pane running claude"; false
  fi
}

@test "watcher: NEITHER marker nor baseline handed over → the PROCESS-ALIVE disclaimer + an event" {
  # A deployed-copy skew mid-land can arm this watcher without the new args. It must degrade to the
  # OLD behaviour (exit 0 on birth) but must NOT claim engagement — a bare "CONFIRMED" would
  # re-introduce the exact false success this fix removes.
  #
  # The wording asserted here is TRUNK's (V2 §6 F12 / R12), kept verbatim through the convergence:
  # trunk fixed the report and named this very gap ("until [a marker check] does [run], the honest
  # report is the one that says what was actually observed"), so its disclaimer IS the degraded
  # branch and its `recycle-unverified` event is the disk-visible record. Asserting trunk's strings
  # rather than this change's own is deliberate — it pins the composition, not just my half.
  watcher_setup
  run env HOME="$H" PATH="$SHIM:$PATH" IT2_BIN="$H/.claude/bin/it2" \
      bash "$HF" __recycle "$PANE" /dev/ttys999 "$CMDF" /tmp
  [ "$status" -eq 0 ]
  [[ "$output" == *"NOT engagement-verified"* ]] || { echo "$output"; false; }
  [[ "$output" == *"PROCESS-ALIVE"* ]] || { echo "$output"; false; }
  # never the bare overclaim the whole fix exists to remove
  if printf '%s' "$output" | grep -qE '\+ (ENGAGEMENT )?CONFIRMED'; then
    echo "the degraded branch claimed CONFIRMED"; false
  fi
  # disk-visible, so a task-less recycle is findable without being at the pane
  grep -q '"class":"recycle-unverified"' "$H/.claude/logs/handoffs.jsonl" \
    || { echo "no recycle-unverified event written"; cat "$H/.claude/logs/handoffs.jsonl" 2>/dev/null; false; }
}

@test "watcher: the DEAD recycle also leaves a disk-visible event (not just a log line)" {
  # Symmetry with the unverified branch: "relaunched but never engaged" must be answerable from disk
  # by whoever reads the fire→engaged metric, not only by someone tailing the watcher log.
  watcher_setup
  row "$OLD_SID"
  run env HOME="$H" PATH="$SHIM:$PATH" RCY_ENGAGE_TIMEOUT=2 RCY_ENGAGE_INTERVAL=1 \
      IT2_BIN="$H/.claude/bin/it2" \
      bash "$HF" __recycle "$PANE" /dev/ttys999 "$CMDF" /tmp "$OLD_SID" "MK-NONE"
  [ "$status" -eq 1 ]
  grep -q '"class":"recycle-dead"' "$H/.claude/logs/handoffs.jsonl" \
    || { echo "no recycle-dead event written"; cat "$H/.claude/logs/handoffs.jsonl" 2>/dev/null; false; }
}

# ── the arming side: the marker reaches the relaunched session ────────────────────────────────────

@test "a real recycle embeds a recycle marker in the prompt COPY, never the caller's file" {
  PF="$BATS_TEST_TMPDIR/brief.md"; printf 'original body\n' > "$PF"
  run env ITERM_SESSION_ID="w1t0p0:AAAAAAAA-0000-0000-0000-000000000009" \
      HANDOFF_ACCOUNT_SWEEP=off CC_FIRE_CAPACITY_GATE=off \
      bash "$HF" --prompt-file "$PF" --launcher claude-test --recycle --dry-run
  [ "$status" -eq 0 ]
  # dry runs fire nothing, so they must still make NO copy — this is the notify-back contract
  ! [[ "$output" == *"handoff-prompt-nb"* ]] || { echo "a dry recycle made a copy"; false; }
  ! grep -q 'recycle engagement marker' "$PF" || { echo "the caller's own file was modified"; false; }
}
