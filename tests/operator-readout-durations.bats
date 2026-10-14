#!/usr/bin/env bats
# operator-readout-durations.bats — render_block's two slowest reads (the ledger and
# `cc-research pending`) run BESIDE its other work, not after it, and the block is unchanged
# (docs/plans/LOAD_AND_PROMPT_HOOK_TIMEOUTS.md, Wave 4b).
#
# The defect: replayed on real cancelled Stops, operator-readout alone took 5-8.5 s at a load of
# ~25 against a 10 s timeout, because the ledger (1.5-4 s: the one ask that carries the BUSY probe,
# so no sibling's memo serves it) and `cc-research pending` (0.6-1.3 s) ran one after the other at
# the end of render_block. § PREFETCH starts both at the top with the identical commands and
# collects them by `wait` where they were read.
#
# Both reads are made SLOW here (a 2 s sleep in front of the real ledger, a 2 s research stub), so
# the old arm cannot finish under ~4 s and the new one finishes near 2 s. Reverting § PREFETCH makes
# P1 red. Parity is against the real pre-change hook rebuilt from git: stdout, IDL row and latch.
#
# Assertions are simple commands only (bash exempts `[[ ]]` from errexit in a bats body).

load stop-hook-forks-helpers

# Trunk just before Wave 4b.
SHF_BASE=4b1224be5f1319ae68d0a50e021e0309bd21b34c

setup() {
  export CC_BACKLOG_PROJECT_WARN=off CC_FIRE_CAPACITY_GATE=off CC_ADMIT_GATE=off
  unset CLAUDE_SESSION_ID CLAUDE_CODE_SESSION_ID CC_SESSION_ID CLAUDE_CONFIG_DIR ITERM_SESSION_ID \
        KITTY_WINDOW_ID CC_PANE_ID NO_COLOR
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  OLD="$BATS_TEST_TMPDIR/old"
  shf_old_tree "$OLD" "$REPO" hooks/operator-readout.sh \
    || skip "the pre-change commit $SHF_BASE is not in this clone"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export SHF_OUT_DIR="$BATS_TEST_TMPDIR/out"; mkdir -p "$SHF_OUT_DIR"
  export CC_ACTIVATION_DIR="$BATS_TEST_TMPDIR/activation"
  export CC_DECISIONS_DIR="$BATS_TEST_TMPDIR/decisions"
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  export CC_BACKLOG_BIN="$REPO/bin/cc-backlog"
  export CC_BACKLOG_KICK=off CC_BACKLOG_KICK_MARKER="$BATS_TEST_TMPDIR/.kick"
  export CC_BACKLOG_KICK_BIN="$BATS_TEST_TMPDIR/no-such-dispatch"
  export WRAP_TRUNK="origin/main"
  export CC_SHARED_CHECKOUT="$BATS_TEST_TMPDIR/no-such-checkout"
  export CC_OPREADOUT_NOW=1000000 CC_OPREADOUT_TTL_S=900
  export CC_DO_BIN=cc-do
  export CC_HANDOFF_ALARM_DIR="$BATS_TEST_TMPDIR/handoff-alarms"
  export CC_ANNOUNCE_ALARM_DIR="$BATS_TEST_TMPDIR/announce-alarms"
  export CC_COMPLETION_RECORDS_DIR="$BATS_TEST_TMPDIR/completion-push"
  export CC_PAGES_DIR="$BATS_TEST_TMPDIR/pages"
  export CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/mailbox"
  export CC_SWEEP_SEEN_DIR="$BATS_TEST_TMPDIR/sweep-seen"
  export LR_STATE_DIR="$BATS_TEST_TMPDIR/lr" LR_RECON_ROOT="$BATS_TEST_TMPDIR/lr/recon"
  export CC_RESUME_DEBT_DIR="$BATS_TEST_TMPDIR/resume-debt"
  export CC_RESUME_DEBT_BIN="$BATS_TEST_TMPDIR/cc-resume-debt-stub"
  printf '#!/bin/bash\necho "[]"\n' > "$CC_RESUME_DEBT_BIN"; chmod +x "$CC_RESUME_DEBT_BIN"
  export CC_WF_PSTABLE_FILE="$BATS_TEST_TMPDIR/pstable"
  printf '1 0 /sbin/launchd\n' > "$CC_WF_PSTABLE_FILE"
  mkdir -p "$CC_ACTIVATION_DIR" "$CC_DECISIONS_DIR" "$CC_HANDOFF_ALARM_DIR" "$CC_ANNOUNCE_ALARM_DIR" \
           "$CC_COMPLETION_RECORDS_DIR" "$CC_PAGES_DIR" "$CC_MAILBOX_DIR/dead-letter" \
           "$CC_SWEEP_SEEN_DIR" "$CC_RESUME_DEBT_DIR/meta"
  : > "$CC_BACKLOG_FILE"
  # The real ledger behind a 2 s delay, and a research reader that answers after 2 s.
  export WRAP_LEDGER_BIN="$BATS_TEST_TMPDIR/slow-ledger.sh"
  printf '#!/bin/bash\nsleep 2\nexec bash %q "$@"\n' "$REPO/scripts/wrap-ledger.sh" > "$WRAP_LEDGER_BIN"
  export CC_RESEARCH_REGISTRY="$BATS_TEST_TMPDIR/programs.json"
  printf '{"programs":[]}\n' > "$CC_RESEARCH_REGISTRY"
  export CC_RESEARCH_BIN="$BATS_TEST_TMPDIR/slow-research"
  research_answers 0
  # A committed-but-unlanded repo (📦), so the block renders its governing line from the ledger.
  local o="$BATS_TEST_TMPDIR/o.git"
  W="$BATS_TEST_TMPDIR/w"
  git init -q --bare "$o"; git clone -q "$o" "$W" 2>/dev/null
  ( cd "$W" || exit 1; git config user.email t@e.com; git config user.name t; git checkout -q -b main
    echo base > base.txt; git add base.txt; git commit -q -m base; git push -q -u origin main
    echo x > x.txt; git add x.txt; git commit -q -m "unlanded work" ) >/dev/null 2>&1
}

research_answers() { # <rc> — the research stub sleeps 2 s, prints one pending program, exits <rc>
  printf '#!/bin/bash\nsleep 2\n[ "$*" = "pending --json" ] || exit 9\necho %q\nexit %s\n' \
    '{"programs":[{"program":"prog-x","pending_concerns":2,"menu":[{"id":"m1","label":"probe","price":3}]}]}' \
    "$1" > "$CC_RESEARCH_BIN"
  chmod +x "$CC_RESEARCH_BIN"
}

transcript() {
  local tp="$BATS_TEST_TMPDIR/t.jsonl"
  printf '%s\n' \
    '{"type":"user","entrypoint":"cli","message":{"content":"fix it"},"timestamp":"2026-10-12T00:00:00.000Z"}' \
    '{"type":"assistant","entrypoint":"cli","message":{"content":[{"type":"text","text":"Done."}]}}' > "$tp"
  printf '%s' "$tp"
}

# hook <old|new> <label> — one Stop through that arm, with its own state, cache, IDL and TMPDIR;
# wall time in ms lands in $SHF_OUT_DIR/<label>.ms.
hook() {
  local root="$REPO" s e
  [ "$1" = old ] && root="$OLD"
  mkdir -p "$BATS_TEST_TMPDIR/tmp-$2"
  s="$(perl -MTime::HiRes=time -e 'printf "%d", time*1000')"
  payload | CC_OPREADOUT_STATE_DIR="$BATS_TEST_TMPDIR/state-$2" CC_ORB_BLG_CACHE_DIR="$BATS_TEST_TMPDIR/blg-$2" \
    CC_IDL="$BATS_TEST_TMPDIR/idl-$2.jsonl" TMPDIR="$BATS_TEST_TMPDIR/tmp-$2" \
    /bin/bash "$root/hooks/operator-readout.sh" > "$SHF_OUT_DIR/$2.out" 2> "$SHF_OUT_DIR/$2.err" || true
  e="$(perl -MTime::HiRes=time -e 'printf "%d", time*1000')"
  echo $(( e - s )) > "$SHF_OUT_DIR/$2.ms"
  jq -c 'del(.ts)' "$BATS_TEST_TMPDIR/idl-$2.jsonl" > "$SHF_OUT_DIR/$2.idl" 2>/dev/null || : > "$SHF_OUT_DIR/$2.idl"
  ( cd "$BATS_TEST_TMPDIR/state-$2" 2>/dev/null && find . -type f | LC_ALL=C sort ) > "$SHF_OUT_DIR/$2.state" || true
}
payload() { jq -cn --arg c "$W" --arg t "$(transcript)" '{session_id:"S-dur",cwd:$c,transcript_path:$t}'; }
same() { # <old label> <new label>
  local k
  for k in out err idl state; do
    cmp "$SHF_OUT_DIR/$1.$k" "$SHF_OUT_DIR/$2.$k" || { echo "--- $k"; diff "$SHF_OUT_DIR/$1.$k" "$SHF_OUT_DIR/$2.$k"; return 1; }
  done
}

@test "P1 the ledger and the research read overlap: ~2 s, not ~4 s (reverting § PREFETCH makes this red)" {
  hook old o1
  hook new n1
  echo "old $(cat "$SHF_OUT_DIR/o1.ms") ms · new $(cat "$SHF_OUT_DIR/n1.ms") ms"
  [ "$(cat "$SHF_OUT_DIR/o1.ms")" -ge 4000 ]
  [ $(( $(cat "$SHF_OUT_DIR/n1.ms") + 1500 )) -le "$(cat "$SHF_OUT_DIR/o1.ms")" ]
}

@test "P2 PARITY: the block, IDL row and latch are byte-identical, and the block uses both reads" {
  hook old o2
  hook new n2
  same o2 n2
  grep -q 'research prog-x: 2 pending concern' "$SHF_OUT_DIR/n2.out"
  grep -q 'parked' "$SHF_OUT_DIR/n2.out"
}

@test "P3 PARITY when the research read FAILS: the same degraded IDL row, no research line" {
  research_answers 3
  hook old o3
  hook new n3
  same o3 n3
  grep -q 'research-pending-unread' "$SHF_OUT_DIR/n3.idl"
  ! grep -q 'research prog-x' "$SHF_OUT_DIR/n3.out"
}

@test "P4 PARITY with no research registry: the prefetch starts nothing, the block is unchanged" {
  rm -f "$CC_RESEARCH_REGISTRY"
  hook old o4
  hook new n4
  same o4 n4
}

@test "P5 PARITY in --render mode (render_block inside a command substitution)" {
  local root
  mkdir -p "$BATS_TEST_TMPDIR/tmp-rold" "$BATS_TEST_TMPDIR/tmp-rnew"
  for root in old new; do
    local r="$REPO"; [ "$root" = old ] && r="$OLD"
    ( cd "$W" && TMPDIR="$BATS_TEST_TMPDIR/tmp-r$root" CC_ORB_BLG_CACHE_DIR="$BATS_TEST_TMPDIR/blg-r$root" \
        /bin/bash "$r/hooks/operator-readout.sh" --render --sid S-dur ) > "$SHF_OUT_DIR/r$root.out" 2>/dev/null || true
  done
  cmp "$SHF_OUT_DIR/rold.out" "$SHF_OUT_DIR/rnew.out"
  grep -q 'research prog-x' "$SHF_OUT_DIR/rnew.out"
}

@test "P6 no prefetch file outlives the run" {
  hook new n6
  [ -z "$(find "$BATS_TEST_TMPDIR/tmp-n6" -name 'opreadout.*' 2>/dev/null)" ]
}
