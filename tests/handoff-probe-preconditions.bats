#!/usr/bin/env bats
# THE READ-ONLY PRECONDITION PROBE, AND THE CROSS-ROOT SEARCH IT RESTS ON.
#
# W2 shipped `--probe-recycle-preconditions` as the refusable read that must happen BEFORE the
# transplant — it is the whole cure for the four husks of 2026-09-19, where the launcher refused
# 11-16 s AFTER the transcript had already moved. It shipped with NO direct test: the only thing
# naming it in tests/ was a STUB of the whole binary in lr-handoff-launcher-quoting.bats. It was
# therefore possible for the verb to be wrong in a way that no suite could see, and it was:
#
#   for _f in ${CC_PROJECTS_DIRS:-$HOME/.claude*/projects}/*/"$SID".jsonl
#
# `${LIST}/*/x` is ONE word before field splitting, so the literal suffix attaches only to the LAST
# element of $LIST; every earlier element expands to a bare directory path that no [ -f ] can match.
# Measured 2026-09-20 against the LIVE layer: the probe searched only ~/.claude-quaternary/projects
# and answered REFUSED:no-transcript for a session whose transcript sat in ~/.claude-tertiary —
# four of the five config roots invisible, i.e. the precheck refused ~80% of recoverable sessions.
# It fails CLOSED (it refuses, it moves nothing) so it cost no data; it made recovery impossible.
#
# WHY NO EXISTING FIXTURE COULD HAVE CAUGHT IT: every suite fixtures ONE config root, and with one
# root the broken form and the correct form are identical. Two disjoint identifier spaces given one
# shape make the address bug unreachable — docs/lessons/fixture-shape-hides-address-bugs.md. So
# every case here fixtures TWO roots and puts the subject in the FIRST.
#
# RED-PROOFS vs GUARDS, stated so no one has to re-derive it: cases 1 and 5 are the red-proofs —
# both fail on the unfixed tree, 1 with "the probe did not look in the FIRST config root" and 5
# with an empty result. Cases 2, 3 and 4 are GREEN IN BOTH ARMS by construction and are labelled
# so in their names: they pin the properties the fix must not trade away (the last root still
# works, a genuine miss still fails closed, the probe still writes nothing).
#
# The UNSET default hides it too (`$HOME/.claude*/projects/*/x` is one word carrying TWO globs, and
# that does expand across roots), and handoff-fire.sh:399 always SETS the variable — so the broken
# arm was the only one that ever ran.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"

  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  # HERMETICITY (land ratchet): no live machine load, and the three seams that do NOT resolve
  # under $HOME point at absent paths inside the test dir.
  export CC_ADMIT_GATE=off
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/absent-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-"

  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg"; mkdir -p "$CC_REGISTRY_DIR"
  SID="a1b2c3d4-0000-4000-8000-000000000001"
  PANE=900
  printf '{"session_id":"%s","pane":"%s"}\n' "$SID" "$PANE" > "$CC_REGISTRY_DIR/$PANE.json"

  # TWO roots, deliberately. ROOT_A is FIRST in the list and is where the broken form cannot look.
  ROOT_A="$BATS_TEST_TMPDIR/cfgA/projects"; ROOT_B="$BATS_TEST_TMPDIR/cfgB/projects"
  mkdir -p "$ROOT_A/-some-repo" "$ROOT_B/-some-repo"
  export CC_PROJECTS_DIRS="$ROOT_A $ROOT_B"
  # The live-member census (lr-team.sh) reads ONE ps snapshot through this seam: never the box's.
  export LR_TEAM_PS_SNAPSHOT="$BATS_TEST_TMPDIR/team-ps.txt"
  printf '1 Ss /sbin/launchd\n' > "$LR_TEAM_PS_SNAPSHOT"
}

# a transcript whose LAST assistant record is a usage-limit error
seed_limited_transcript() { # $1=dir
  printf '%s\n' \
    '{"type":"user","timestamp":"2026-09-20T00:00:00.000Z","message":{"role":"user","content":"go"}}' \
    '{"type":"assistant","timestamp":"2026-09-20T00:00:01.000Z","isApiErrorMessage":true,"message":{"role":"assistant","model":"<synthetic>","content":[{"type":"text","text":"You'"'"'ve hit your weekly limit \u00b7 resets 4am (America/Chicago)"}]}}' \
    > "$1/-some-repo/$SID.jsonl"
}

@test "probe: a transcript in the FIRST of two config roots is FOUND (cross-root search)" {
  seed_limited_transcript "$ROOT_A"
  run bash "$HF" --probe-recycle-preconditions --source-pane "$PANE" --source-session "$SID"
  # The verdict may legitimately be a later refusal (there is no real pane here) — what this case
  # pins is that the search REACHED the transcript at all.
  [[ "$output" != *"NO TRANSCRIPT"* ]] || {
    echo "the probe did not look in the FIRST config root:"; echo "$output"
    echo "CC_PROJECTS_DIRS=$CC_PROJECTS_DIRS"; ls -la "$ROOT_A/-some-repo"; false; }
  [[ "$output" == *"limit: kind=limit"* ]] || { echo "$output"; false; }
}

@test "probe: a transcript in the LAST config root is FOUND (equivalence guard — green both arms)" {
  # DELIBERATELY green before and after the fix: the broken form searched exactly this root. It is
  # here so the fix cannot be "search only the first root", and it is NOT a red-proof.
  seed_limited_transcript "$ROOT_B"
  run bash "$HF" --probe-recycle-preconditions --source-pane "$PANE" --source-session "$SID"
  [[ "$output" != *"NO TRANSCRIPT"* ]] || { echo "$output"; false; }
  [[ "$output" == *"limit: kind=limit"* ]] || { echo "$output"; false; }
}

@test "probe: a session in NO root is REFUSED:no-transcript, not silently admitted (guard — green both arms)" {
  # The polarity that matters: absence must REFUSE. A search that reaches every root is only safe
  # if a genuine miss still fails closed.
  run bash "$HF" --probe-recycle-preconditions --source-pane "$PANE" --source-session "$SID"
  [[ "$output" == *"REFUSED:no-transcript"* ]] || { echo "$output"; false; }
  [ "$status" -eq 5 ] || { echo "status=$status"; echo "$output"; false; }
}

@test "probe: it writes NOTHING — the fixture tree is byte-identical after a run (guard — green both arms)" {
  seed_limited_transcript "$ROOT_A"
  # SCOPED to what the probe reads — the two project roots and the registry. Hashing all of
  # $BATS_TEST_TMPDIR instead swept $HOME, where an unrelated interpreter drops .pyc caches, and
  # the case then failed on the INSTRUMENT rather than on its subject.
  snap() { find "$ROOT_A" "$ROOT_B" "$CC_REGISTRY_DIR" -type f -exec shasum {} \; | sort; }
  before="$(snap)"
  run bash "$HF" --probe-recycle-preconditions --source-pane "$PANE" --source-session "$SID"
  after="$(snap)"
  [ "$before" = "$after" ] || {
    echo "the READ-ONLY probe changed something:"; diff <(printf '%s\n' "$before") <(printf '%s\n' "$after") || true; false; }
}

# D4.0 (FLEET_V2 W6, operator decision 4): a lead with a live member is HELD:team, next to the teammate
# refusal and before any pane read. Mutants: drop the 3b block (the lead reaches the pane read) · make
# an unreadable census pass (the empty-snapshot row goes green-to-red).
@test "probe: a LEAD with a live member is HELD:team; a zombie member does not hold; an unreadable ps holds" {
  seed_limited_transcript "$ROOT_A"
  printf '4242 S+ /Users/x/.claude-284/node_modules/.bin/claude --agent-id w@session-t --parent-session-id %s\n' "$SID" > "$LR_TEAM_PS_SNAPSHOT"
  run bash "$HF" --probe-recycle-preconditions --source-pane "$PANE" --source-session "$SID"
  [ "$status" -eq 3 ] || { echo "status=$status $output"; false; }
  [[ "$output" == *"team: LEAD — 1 live member(s)"* ]] || { echo "$output"; false; }
  [[ "$output" == *"verdict: HELD:team"* ]] || { echo "$output"; false; }
  [[ "$output" != *"pane_state:"* ]] || { echo "the pane was read before the team hold: $output"; false; }
  # A member that exited is not a member: the lead is released.
  printf '4242 Z /Users/x/.claude-284/node_modules/.bin/claude --parent-session-id %s\n' "$SID" > "$LR_TEAM_PS_SNAPSHOT"
  run bash "$HF" --probe-recycle-preconditions --source-pane "$PANE" --source-session "$SID"
  [[ "$output" == *"team: no live members"* ]] || { echo "$output"; false; }
  [[ "$output" != *"HELD:team"* ]] || { echo "$output"; false; }
  # Cannot tell a lead from a solo session: held, never guessed.
  : > "$LR_TEAM_PS_SNAPSHOT"
  run bash "$HF" --probe-recycle-preconditions --source-pane "$PANE" --source-session "$SID"
  [ "$status" -eq 3 ] || { echo "status=$status $output"; false; }
  [[ "$output" == *"team: UNREADABLE — ps unreadable"* ]] || { echo "$output"; false; }
  # Kill switch.
  HF_TEAM_HOLD=off run bash "$HF" --probe-recycle-preconditions --source-pane "$PANE" --source-session "$SID"
  [[ "$output" != *"team:"* ]] || { echo "$output"; false; }
}

# ══ KERNEL PANE IDENTITY IN THE PRECHECK (W12, B5a §5.2; reviews R-2, S1, S3, S16a) ═══════════════
# The pane's identity from the registry row and the kernel, through a ps stub (HF_KID_PS_BIN): kitty
# 610 → root 70001 on ttys777 → claude 70003, the row naming pid 70003. CC_TERM=kitty and a fixture
# socket are preset in every arm, so no arm can reach a live kitty (the resolver returns at once on a
# preset CC_TERM, and the kitty probe connects only to the fixture socket, which nothing listens on).
# A socket FILE (bound, never listened on). Basename bind: Darwin caps sun_path at 104 bytes.
afunix_file() { /usr/bin/python3 -c 'import os,socket,sys; d,b=os.path.split(os.path.abspath(sys.argv[1])); os.chdir(d); socket.socket(socket.AF_UNIX).bind(b)' "$1"; }
kid_setup() {
  export LR_STATE_DIR="$BATS_TEST_TMPDIR/lr" LR_RECON_ROOT="$BATS_TEST_TMPDIR/recon" TMPDIR="$BATS_TEST_TMPDIR/tmp"
  mkdir -p "$LR_STATE_DIR" "$TMPDIR"
  KF="$BATS_TEST_TMPDIR/kid"; mkdir -p "$KF"
  SOCK="$KF/kitty-610"; LS="Wed Oct 21 03:37:41 2026"
  afunix_file "$SOCK"
  # shellcheck disable=SC2016  # expanded when the STUB runs
  printf '%s\n' '#!/bin/bash' 'F="${KID_FIX:?}"; L="${!#}"; printf "%s\n" "$*" >> "$F/calls"' \
    'if [ -f "$F/sleep" ]; then /bin/sleep "$(cat "$F/sleep")"; fi' \
    'case "$*" in' \
    '  "-E -ww -o command= -p "*) cat "$F/env.$L" 2>/dev/null ;;' \
    '  "-axo pid=,ppid=,stat=,tty=,lstart=,comm=") cat "$F/table" ;;' \
    '  "-ww -o command= -p "*) cat "$F/argv.$L" 2>/dev/null ;;' \
    'esac' > "$KF/ps"
  chmod +x "$KF/ps"
  printf '%s\n' "  610     1 S    ??       $LS /Applications/kitty.app/Contents/MacOS/kitty" \
    "70001   610 Ss   ttys777  $LS login" "70002 70001 S    ttys777  $LS -zsh" "70003 70002 S+   ttys777  $LS claude" > "$KF/table"
  printf 'claude --resume x' > "$KF/argv.70003"
  printf 'claude --resume x HOME=/h PATH=/bin KITTY_WINDOW_ID=%s KITTY_PID=610 KITTY_LISTEN_ON=unix:%s\n' "$PANE" "$SOCK" > "$KF/env.70003"
  printf '{"session_id":"%s","pane":"%s","pid":70003,"lstart":"%s","kitty_pid":610}\n' "$SID" "$PANE" "$LS" > "$CC_REGISTRY_DIR/$PANE.json"
  : > "$BATS_TEST_TMPDIR/netstat.txt"
  seed_limited_transcript "$ROOT_A"
}
# HF_KID_BOUND_S=0 (unbounded) where a case asserts a VERIFIED identity: at load ~170 the 20 s bound
# honestly fired once (no verdict, fall back), which is the bound's case below, not these.
kid_probe() { # $@=extra env
  run env KID_FIX="$KF" HF_KID_PS_BIN="$KF/ps" HF_KID_BOUND_S=0 CC_TERM=kitty CC_TERM_KITTY_TO="unix:$SOCK" \
      CC_HF_NETSTAT_FILE="$BATS_TEST_TMPDIR/netstat.txt" CC_KITTY_CONNECT_TIMEOUT_S=0 "$@" \
      bash "$HF" --probe-recycle-preconditions --source-pane "$PANE" --source-session "$SID"
}
kid_rows() { jq -c 'select(.class == "recycle-kid-shadow")' "$HOME/.claude/logs/handoffs.jsonl" 2>/dev/null || true; }
norm() { printf '%s\n' "$1" | sed -E 's/ over [0-9]+s/ over Ns/g'; }

@test "W12 mode on: a verified identity replaces the kitty resolver and the tty/root reads — 'identity: kernel', the root's lstart, the probe on the VERIFIED socket" {
  kid_setup
  kid_probe HF_KITTY_OFFPATH=on
  [[ "$output" == *"identity: kernel (kitty 610 window $PANE root 70001 on ttys777; no terminal round-trip)"* ]] || { echo "$output"; false; }
  [ "$(grep -c . "$KF/calls")" -eq 3 ] || { cat "$KF/calls"; false; }
  [ "$(printf '%s\n' "$output" | sed -n 's/^verdict: //p')" = HELD:unreachable ] || { echo "$output"; false; }
  [[ "$output" == *"kitty_probe: not answering"* ]] || { echo "$output"; false; }
  [ -z "$(kid_rows)" ] || { echo "mode on writes no shadow row"; false; }
}

@test "W12 S1: a preset socket naming ANOTHER kitty is overridden by the verified kitty's own, and said so" {
  kid_setup
  afunix_file "$KF/kitty-999"
  run env KID_FIX="$KF" HF_KID_PS_BIN="$KF/ps" HF_KID_BOUND_S=0 CC_TERM=kitty CC_TERM_KITTY_TO="unix:$KF/kitty-999" HF_KITTY_OFFPATH=on \
      CC_HF_NETSTAT_FILE="$BATS_TEST_TMPDIR/netstat.txt" CC_KITTY_CONNECT_TIMEOUT_S=0 \
      bash "$HF" --probe-recycle-preconditions --source-pane "$PANE" --source-session "$SID"
  [[ "$output" == *"CC_TERM_KITTY_TO=unix:$KF/kitty-999 overridden by kitty 610's own socket unix:$SOCK"* ]] || { echo "$output"; false; }
  [[ "$output" == *"kitty_probe: not answering — the control socket $SOCK did not accept"* ]] || { echo "the probe did not use the verified socket: $output"; false; }
}

@test "W12 shadow control: the identity runs (3 ps forks, one row with both ttys agreeing) and the output equals mode off's, which runs nothing" {
  kid_setup
  kid_probe HF_KITTY_OFFPATH=off; off_out="$(norm "$output")"; off_rc=$status
  [ ! -s "$KF/calls" ] || { echo "mode off forked the identity: $(cat "$KF/calls")"; false; }
  [ -z "$(kid_rows)" ] || false
  kid_probe; sh_out="$(norm "$output")"
  [ "$status" -eq "$off_rc" ] || { echo "rc shadow=$status off=$off_rc"; false; }
  [ "$sh_out" = "$off_out" ] || { diff <(printf '%s\n' "$off_out") <(printf '%s\n' "$sh_out"); false; }
  [ "$(grep -c . "$KF/calls")" -eq 3 ] || { cat "$KF/calls"; false; }
  r="$(kid_rows)"
  [[ "$r" == *"kid_rc=0 kernel_tty=ttys777 kitty_tty="*" agree="*"kitty_pid=610"* ]] || { echo "$r"; false; }
  [ "$(printf '%s\n' "$r" | grep -c .)" -eq 1 ] || { echo "$r"; false; }
  # …and the instrument can see a difference: mode on's output is not off's
  kid_probe HF_KITTY_OFFPATH=on
  [ "$(norm "$output")" != "$off_out" ] || false
}

@test "W12 R-2: a ps that sleeps past the bound is no verdict — rc 2, logged, today's path runs" {
  kid_setup
  printf 4 > "$KF/sleep"
  kid_probe HF_KID_BOUND_S=1 HANDOFF_IT2_TIMEOUT_BIN="$(command -v gtimeout || command -v timeout)"
  r="$(kid_rows)"
  [[ "$r" == *"kid_rc=2 kernel_tty= "*"the identity probe ended rc 124"* ]] || { echo "$r"; echo "$output"; false; }
  [[ "$output" != *"identity: kernel"* ]] || false
}

@test "W12 S16a: under a test runner the identity does not run without HF_KID_PS_BIN — no fork, no row" {
  kid_setup
  run env KID_FIX="$KF" CC_TERM=kitty CC_TERM_KITTY_TO="unix:$SOCK" HF_KITTY_OFFPATH=on \
      CC_HF_NETSTAT_FILE="$BATS_TEST_TMPDIR/netstat.txt" CC_KITTY_CONNECT_TIMEOUT_S=0 \
      bash "$HF" --probe-recycle-preconditions --source-pane "$PANE" --source-session "$SID"
  [[ "$output" != *"identity: kernel"* ]] || { echo "$output"; false; }
  [ ! -s "$KF/calls" ] && [ -z "$(kid_rows)" ] || false
}

@test "subagent_dir_for_sid: a subagents dir in the FIRST of two config roots is FOUND" {
  # The SAME broken idiom, at a PRE-EXISTING site (not W2's), and this one is a safety hold: the
  # recycle gate asks this function whether the dying session still has live subagents. Answering
  # "none" for every session outside the last config root would let a recycle proceed over
  # in-flight work. Extracted by name so a sibling definition cannot answer for it.
  eval "$(awk '/^subagent_dir_for_sid\(\) \{/{p=1} p{print} p&&/^\}$/{exit}' "$HF")"
  mkdir -p "$ROOT_A/-some-repo/$SID/subagents"
  run subagent_dir_for_sid "$SID"
  [ "$output" = "$ROOT_A/-some-repo/$SID" ] || {
    echo "expected the FIRST root's dir, got '<$output>'"; echo "CC_PROJECTS_DIRS=$CC_PROJECTS_DIRS"; false; }
}
