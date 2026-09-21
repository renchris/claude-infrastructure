#!/usr/bin/env bats
# cc-husk-sweep — a pane at a bare shell over a DEAD session is resolved to (sid, account
# launcher, cwd), classified by how it died and what it left open, and resumed with the PINNED
# launcher (never the pane's own printed `claude --resume`, which uses the default account and
# cannot see another store's transcript). Every source is fixtured through the tool's seams; the
# only live thing here is the tool.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SWEEP="$REPO/bin/cc-husk-sweep"
  T="$BATS_TEST_TMPDIR"
  export CC_REGISTRY_DIR="$T/reg"; mkdir -p "$CC_REGISTRY_DIR"
  export CC_HUSK_CRASH_LOG="$T/crashes.jsonl"; : > "$CC_HUSK_CRASH_LOG"
  export CC_HUSK_LOG="$T/husk-sweep.jsonl"
  export CC_HUSK_STORES="$T/.claude-secondary:$T/.claude-tertiary"
  export CC_HUSK_PANES_JSON="$T/panes.json"
  export CC_HUSK_PS_FILE="$T/ps.txt"
  export CC_HUSK_IT2="$T/it2"
  # a fake it2 that records every send and answers a read with what was sent (echo-verify passes)
  cat > "$CC_HUSK_IT2" <<'IT2'
#!/bin/bash
log="${CC_HUSK_IT2_LOG:?}"
case "$1 $2" in
  "session send") printf 'SEND %s %s\n' "$4" "$5" >> "$log" ;;
  "session read") grep "^SEND $4 " "$log" | tail -1 | sed 's/^SEND [^ ]* //' ;;
esac
exit 0
IT2
  chmod +x "$CC_HUSK_IT2"; export CC_HUSK_IT2_LOG="$T/it2.log"; : > "$CC_HUSK_IT2_LOG"
  CWD_A="$T/wt-a"; CWD_B="$T/wt-b"; mkdir -p "$CWD_A" "$CWD_B"
  # pane 10: husk (shell 100, child zsh 101, nothing else) · pane 20: live (claude under 201)
  printf '[{"id":"10","pid":100,"cwd":"%s"},{"id":"20","pid":200,"cwd":"%s"},{"id":"30","pid":300,"cwd":"%s"}]\n' "$CWD_A" "$CWD_B" "$CWD_B" > "$CC_HUSK_PANES_JSON"
  printf '%s\n' "100 1 login -fp chris" "101 100 -zsh" "200 1 /bin/zsh" "201 200 bash cc-close-attrib" "202 201 /Users/x/.claude-260/node_modules/.bin/claude --resume z" "300 1 /bin/zsh" > "$CC_HUSK_PS_FILE"
}
slug() { printf '%s' "$1" | LC_ALL=C sed 's/[^a-zA-Z0-9]/-/g'; }
transcript() { # <store> <cwd> <sid> <last-close: yes|no|none>
  local d; d="$1/projects/$(slug "$2")"; mkdir -p "$d"
  { echo '{"type":"user"}'; [ "$4" = none ] || printf '{"type":"assistant","message":{"content":[{"type":"text","text":"... Good to close: %s — x"}]}}\n' "$4"; } > "$d/$3.jsonl"
}

@test "a pane with a claude anywhere beneath its shell is not a husk; a bare one is" {
  transcript "$T/.claude-secondary" "$CWD_A" "aaaaaaaa-0000-0000-0000-000000000001" yes
  run "$SWEEP" --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"pane":"10"'* ]] || false
  [[ "$output" != *'"pane":"20"'* ]] || false
}

@test "registry wins: sid, ACCOUNT launcher and cwd come from the surviving row" {
  printf '{"paneUUID":"10","session_id":"bbbbbbbb-0000-0000-0000-000000000002","account":"claude-tertiary","cwd":"%s","pid":999}\n' "$CWD_B" > "$CC_REGISTRY_DIR/10.json"
  transcript "$T/.claude-tertiary" "$CWD_B" "bbbbbbbb-0000-0000-0000-000000000002" no
  run "$SWEEP" --json --pane 10
  [ "$status" -eq 0 ]
  [[ "$output" == *'"sid":"bbbbbbbb-0000-0000-0000-000000000002"'* ]] || false
  [[ "$output" == *'"launcher":"claude3"'* ]] || false
  [[ "$output" == *'"source":"registry"'* ]] || false
}

@test "no registry row: the newest transcript for the pane's cwd names the session AND its store's account" {
  transcript "$T/.claude-secondary" "$CWD_A" "cccccccc-0000-0000-0000-000000000003" yes
  sleep 1
  transcript "$T/.claude-tertiary" "$CWD_A" "dddddddd-0000-0000-0000-000000000004" no
  run "$SWEEP" --json --pane 10
  [ "$status" -eq 0 ]
  [[ "$output" == *'"sid":"dddddddd-0000-0000-0000-000000000004"'* ]] || false
  [[ "$output" == *'"launcher":"claude3"'* ]] || false
  [[ "$output" == *'"source":"transcript"'* ]] || false
}

@test "verdict: 'Good to close: no' ⇒ RESUME; 'yes' on a non-git cwd ⇒ UNKNOWN (not shown done); the crash cause is carried" {
  transcript "$T/.claude-secondary" "$CWD_A" "eeeeeeee-0000-0000-0000-000000000005" no
  printf '{"sid":"eeeeeeee-0000-0000-0000-000000000005","cause":"external-sigterm"}\n' > "$CC_HUSK_CRASH_LOG"
  run "$SWEEP" --json --pane 10
  [[ "$output" == *'"verdict":"RESUME"'* ]] || false
  [[ "$output" == *'"death":"external-sigterm"'* ]] || false
  transcript "$T/.claude-secondary" "$CWD_B" "ffffffff-0000-0000-0000-000000000006" yes
  run "$SWEEP" --json --pane 30
  [[ "$output" == *'"verdict":"UNKNOWN"'* ]] || false
}

@test "verdict: uncommitted or unlanded work in the cwd forces RESUME whatever the session said" {
  git -C "$CWD_A" init -q && git -C "$CWD_A" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  echo x > "$CWD_A/dirty"
  transcript "$T/.claude-secondary" "$CWD_A" "aaaaaaaa-0000-0000-0000-000000000007" yes
  run "$SWEEP" --json --pane 10
  [[ "$output" == *'"work":"dirty"'* ]] || false
  [[ "$output" == *'"verdict":"RESUME"'* ]] || false
}

@test "--resume --yes types the PINNED launcher line, echo-verified, and records the attempt" {
  transcript "$T/.claude-tertiary" "$CWD_A" "abababab-0000-0000-0000-000000000008" no
  run "$SWEEP" --resume --yes --pane 10
  [ "$status" -ne 2 ]
  grep -q 'SEND 10 : hs-.*nocorrect CC_ACCOUNT_PINNED=1 claude3 --resume abababab-0000-0000-0000-000000000008' "$CC_HUSK_IT2_LOG"
  grep -q '"pane":"10","sid":"abababab-0000-0000-0000-000000000008","launcher":"claude3"' "$CC_HUSK_LOG"
  # never the pane's own default-account spelling
  if grep -q 'SEND 10 : hs-.* claude --resume' "$CC_HUSK_IT2_LOG"; then false; fi
}

@test "--resume skips DONE husks unless --all, and without --yes it types NOTHING" {
  git -C "$CWD_A" init -q && git -C "$CWD_A" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  git -C "$CWD_A" remote add origin "$CWD_A" && git -C "$CWD_A" fetch -q origin && git -C "$CWD_A" update-ref refs/remotes/origin/main HEAD
  transcript "$T/.claude-secondary" "$CWD_A" "acacacac-0000-0000-0000-000000000009" yes
  run "$SWEEP" --json --pane 10
  [[ "$output" == *'"verdict":"DONE"'* ]] || false
  run "$SWEEP" --resume --yes --pane 10
  [[ "$output" == *"nothing to resume"* ]] || false
  [ ! -s "$CC_HUSK_IT2_LOG" ]
  run "$SWEEP" --resume --pane 10 --all </dev/null
  [ "$status" -eq 3 ]
  [ ! -s "$CC_HUSK_IT2_LOG" ]
}

@test "a LIVE session's id is never a husk's identity — the newest transcript in a shared cwd may belong to a session running elsewhere" {
  # pane 10 (bare shell) and a live session that last wrote the newest transcript for that cwd
  transcript "$T/.claude-secondary" "$CWD_A" "dddddddd-0000-0000-0000-000000000010" no
  sleep 1
  transcript "$T/.claude-tertiary" "$CWD_A" "eeeeeeee-0000-0000-0000-000000000011" no   # newest, but LIVE
  export CC_HUSK_LIVE_SIDS="$T/live.txt"; printf 'eeeeeeee-0000-0000-0000-000000000011\n' > "$CC_HUSK_LIVE_SIDS"
  run "$SWEEP" --json --pane 10
  [ "$status" -eq 0 ]
  [[ "$output" != *'eeeeeeee-0000-0000-0000-000000000011'* ]] || { echo "resolved to a LIVE sid: $output"; false; }
  [[ "$output" == *'"sid":"dddddddd-0000-0000-0000-000000000010"'* ]] || false
  run "$SWEEP" --resume --yes --pane 10
  if grep -q 'eeeeeeee-0000-0000-0000-000000000011' "$CC_HUSK_IT2_LOG"; then echo "typed a live session's resume line"; false; fi
}

# ── W5-C · TRANSPLANT ────────────────────────────────────────────────────────────────────────────
# A transplanted session keeps the SAME sid and moves to another account's store. Its source pane
# is left at a bare shell, which is exactly a husk — so the sweep would resolve it, name the SOURCE
# account, and type that account's resume line while the work is live somewhere else: two writers
# on one transcript. Every case below holds the successor NON-LIVE (an EMPTY CC_HUSK_LIVE_SIDS),
# because is_live_sid (the two call sites inside resolve(), on the scrollback and transcript arms)
# already suppresses a live successor and would make a naive red-proof pass for the wrong reason. LR_STATE_DIR is pinned rather than left to the tmp HOME, so
# the lock store is sealed on purpose and not by accident.
tombstone() { # <store> <cwd> <sid> <target cfg> — what lr-transplant.sh leaves in the SOURCE store
  local d; d="$1/projects/$(slug "$2")"; mkdir -p "$d"
  printf '{"sid":"%s","handed_off_to":"%s","target_transcript":"%s/projects/x/%s.jsonl"}\n' \
    "$3" "$4" "$4" "$3" > "$d/$3.HANDOFF.json"
}
xplant_seals() {
  export CC_HUSK_LIVE_SIDS="$T/live-none.txt"; : > "$CC_HUSK_LIVE_SIDS"
  export LR_STATE_DIR="$T/lrstate"; mkdir -p "$LR_STATE_DIR/locks"
}
xplant_registry_fixture() { # <sid> — pane 10 resolves from the registry to .claude-tertiary
  printf '{"paneUUID":"10","session_id":"%s","account":"claude-tertiary","cwd":"%s"}\n' \
    "$1" "$CWD_A" > "$CC_REGISTRY_DIR/10.json"
  transcript "$T/.claude-tertiary"  "$CWD_A" "$1" no      # the source copy, still on disk
  tombstone  "$T/.claude-tertiary"  "$CWD_A" "$1" "$T/.claude-secondary"
  transcript "$T/.claude-secondary" "$CWD_B" "$1" none    # the successor — present, NOT live
}

@test "TRANSPLANTED: a registry-resolved sid whose own store holds a transplant tombstone is classified, not RESUME" {
  xplant_seals
  xplant_registry_fixture 11111111-0000-0000-0000-000000000001
  run "$SWEEP" --json --pane 10
  [ "$status" -eq 0 ]
  [[ "$output" == *'"source":"registry"'* ]] || { echo "$output"; false; }
  [[ "$output" == *'"verdict":"TRANSPLANTED→next2"'* ]] || { echo "$output"; false; }
  [[ "$output" != *'"verdict":"RESUME"'* ]] || { echo "$output"; false; }
}

@test "TRANSPLANTED is never resumed from the sweep — not even with --all --yes" {
  xplant_seals
  xplant_registry_fixture 22222222-0000-0000-0000-000000000002
  run "$SWEEP" --resume --all --yes --pane 10
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to resume"* ]] || { echo "$output"; false; }
  [ ! -s "$CC_HUSK_IT2_LOG" ]
}

@test "TRANSPLANTED: the scrollback arm derives its store from the LAUNCHER it read" {
  xplant_seals
  unset CC_HUSK_PANES_JSON
  SID=33333333-0000-0000-0000-000000000003
  printf '%s\n' '  $ claude3 --strict-mcp-config --model claude-opus-5' \
                '  ... work ...' \
                "  Resume this session with: claude --resume $SID" > "$T/sb.txt"
  printf '[{"id":"10","pid":100,"cwd":"%s"}]\n' "$CWD_A" > "$T/sb-panes.json"
  export CC_HUSK_SB_PANES="$T/sb-panes.json" CC_HUSK_SB_TEXT="$T/sb.txt"
  cat > "$T/it2-sb" <<'IT2'
#!/bin/bash
log="${CC_HUSK_IT2_LOG:?}"
case "$1 $2" in
  "session list") cat "${CC_HUSK_SB_PANES:?}" ;;
  "session send") printf 'SEND %s %s\n' "$4" "$5" >> "$log" ;;
  "session read")
    if grep -q "^SEND $4 " "$log" 2>/dev/null; then grep "^SEND $4 " "$log" | tail -1 | sed 's/^SEND [^ ]* //'
    else cat "${CC_HUSK_SB_TEXT:?}"; fi ;;
esac
exit 0
IT2
  chmod +x "$T/it2-sb"; export CC_HUSK_IT2="$T/it2-sb"
  tombstone  "$T/.claude-tertiary"  "$CWD_A" "$SID" "$T/.claude-secondary"
  transcript "$T/.claude-secondary" "$CWD_B" "$SID" none
  run "$SWEEP" --json --pane 10
  [ "$status" -eq 0 ]
  [[ "$output" == *'"source":"scrollback"'* ]] || { echo "$output"; false; }
  [[ "$output" == *'"verdict":"TRANSPLANTED→next2"'* ]] || { echo "$output"; false; }
}

@test "TRANSPLANTED: the transcript arm uses the store the jsonl was FOUND in" {
  xplant_seals
  SID=44444444-0000-0000-0000-000000000004
  transcript "$T/.claude-tertiary"  "$CWD_A" "$SID" no     # found here, under the pane's own cwd
  tombstone  "$T/.claude-tertiary"  "$CWD_A" "$SID" "$T/.claude-secondary"
  transcript "$T/.claude-secondary" "$CWD_B" "$SID" none   # successor under a DIFFERENT cwd slug
  run "$SWEEP" --json --pane 10
  [ "$status" -eq 0 ]
  [[ "$output" == *'"source":"transcript"'* ]] || { echo "$output"; false; }
  [[ "$output" == *'"verdict":"TRANSPLANTED→next2"'* ]] || { echo "$output"; false; }
}

@test "the mirror is ONE store: a tombstone naming ~/.claude-next from ~/.claude is not a transplant" {
  xplant_seals
  mkdir -p "$T/.claude/projects" "$T/.claude-next"
  ln -s "$T/.claude/projects" "$T/.claude-next/projects"
  export CC_HUSK_STORES="$T/.claude:$T/.claude-next"
  SID=55555555-0000-0000-0000-000000000005
  printf '{"paneUUID":"10","session_id":"%s","account":"claude-next","cwd":"%s"}\n' "$SID" "$CWD_A" \
    > "$CC_REGISTRY_DIR/10.json"
  transcript "$T/.claude" "$CWD_A" "$SID" no
  tombstone  "$T/.claude" "$CWD_A" "$SID" "$T/.claude-next"   # one store, the other spelling
  run "$SWEEP" --json --pane 10
  [ "$status" -eq 0 ]
  [[ "$output" != *TRANSPLANTED* ]] || { echo "folded the mirror wrong: $output"; false; }
  [[ "$output" == *'"verdict":"RESUME"'* ]] || { echo "$output"; false; }
}

@test "a transplant tombstone in an account this session never ran under does not convict it" {
  xplant_seals
  SID=66666666-0000-0000-0000-000000000006
  printf '{"paneUUID":"10","session_id":"%s","account":"claude-tertiary","cwd":"%s"}\n' "$SID" "$CWD_A" \
    > "$CC_REGISTRY_DIR/10.json"
  transcript "$T/.claude-tertiary"   "$CWD_A" "$SID" no
  tombstone  "$T/.claude-secondary"  "$CWD_A" "$SID" "$T/.claude-quaternary"   # a foreign store's row
  transcript "$T/.claude-quaternary" "$CWD_B" "$SID" none
  run "$SWEEP" --json --pane 10
  [ "$status" -eq 0 ]
  [[ "$output" != *TRANSPLANTED* ]] || { echo "$output"; false; }
  [[ "$output" == *'"verdict":"RESUME"'* ]] || { echo "$output"; false; }
}

@test "the LOCK half of the superset reaches the sweep too, with no tombstone on disk" {
  xplant_seals
  SID=77777777-0000-0000-0000-000000000007
  printf '{"paneUUID":"10","session_id":"%s","account":"claude-tertiary","cwd":"%s"}\n' "$SID" "$CWD_A" \
    > "$CC_REGISTRY_DIR/10.json"
  transcript "$T/.claude-tertiary"  "$CWD_A" "$SID" no
  printf '{"sid":"%s","to":"%s"}\n' "$SID" "$T/.claude-secondary" > "$LR_STATE_DIR/locks/$SID.lock"
  transcript "$T/.claude-secondary" "$CWD_B" "$SID" none
  run "$SWEEP" --json --pane 10
  [ "$status" -eq 0 ]
  [[ "$output" == *'"verdict":"TRANSPLANTED→next2"'* ]] || { echo "$output"; false; }
}

@test "lr-lib unreachable is FATAL, never fail-open — a guard that PREVENTS a resume may not vanish quietly" {
  xplant_seals
  export CC_HUSK_LR_LIB="$T/no-such-lr-lib.sh"
  transcript "$T/.claude-secondary" "$CWD_A" "88888888-0000-0000-0000-000000000008" no
  run "$SWEEP" --json --pane 10
  [ "$status" -eq 2 ]
  [[ "$output" == *"lr-lib.sh"* ]] || { echo "$output"; false; }
}

# The two cases below drive transplant_target_of at its CONTRACT BOUNDARY with lr-lib, through the
# same CC_HUSK_LR_LIB seam the FATAL case uses. Both arms they cover survived a mutation pass as
# "equivalence guards" against the real library, which is precisely the reading that lets a defence
# rot: lr-lib is a sibling that changes, and these pin what this tool must do when it answers oddly.
stub_lr_lib() { # <body of lr_transplant_target>
  printf '%s\n' '#!/usr/bin/env bash' "lr_transplant_target() { $1 }" > "$T/lr-stub.sh"
  export CC_HUSK_LR_LIB="$T/lr-stub.sh"
}

@test "two UNRESOLVABLE config dirs are not 'the same store' — the fold may not swallow the guard" {
  xplant_seals
  SID=99999999-0000-0000-0000-000000000009
  # $T/.claude-tertiary is in STORES but has no projects/ in this test, and the target does not
  # exist at all: BOTH sides are unresolvable, and a fold that collapses them onto the empty string
  # would call them equal and silently disarm every transplant on this box.
  printf '{"paneUUID":"10","session_id":"%s","account":"claude-tertiary","cwd":"%s"}\n' "$SID" "$CWD_A" \
    > "$CC_REGISTRY_DIR/10.json"
  stub_lr_lib 'printf "%s" "/nope/target-store";'
  run "$SWEEP" --json --pane 10
  [ "$status" -eq 0 ]
  [[ "$output" == *'"verdict":"TRANSPLANTED→next"'* ]] || { echo "$output"; false; }
}

@test "an EMPTY target on rc 0 fabricates no transplant" {
  xplant_seals
  SID=aaaa0000-0000-0000-0000-00000000000a
  printf '{"paneUUID":"10","session_id":"%s","account":"claude-tertiary","cwd":"%s"}\n' "$SID" "$CWD_A" \
    > "$CC_REGISTRY_DIR/10.json"
  transcript "$T/.claude-tertiary" "$CWD_A" "$SID" no
  stub_lr_lib 'return 0;'          # rc 0, nothing on stdout
  run "$SWEEP" --json --pane 10
  [ "$status" -eq 0 ]
  [[ "$output" != *TRANSPLANTED* ]] || { echo "fabricated a transplant from an empty target: $output"; false; }
  [[ "$output" == *'"verdict":"RESUME"'* ]] || { echo "$output"; false; }
}

@test "a target cfg recorded with a trailing slash still names the right account" {
  # lr_transplant_target prints the target EXACTLY as the lock or tombstone recorded it, and a
  # writer is free to record "…/.claude-secondary/". Unstripped, ${1##*/} is the empty string and
  # every such row renders TRANSPLANTED→next — a confident wrong account, not an error.
  xplant_seals
  SID=bbbb0000-0000-0000-0000-00000000000b
  printf '{"paneUUID":"10","session_id":"%s","account":"claude-tertiary","cwd":"%s"}\n' "$SID" "$CWD_A" \
    > "$CC_REGISTRY_DIR/10.json"
  transcript "$T/.claude-tertiary"  "$CWD_A" "$SID" no
  tombstone  "$T/.claude-tertiary"  "$CWD_A" "$SID" "$T/.claude-secondary/"
  transcript "$T/.claude-secondary" "$CWD_B" "$SID" none
  run "$SWEEP" --json --pane 10
  [ "$status" -eq 0 ]
  [[ "$output" == *'"verdict":"TRANSPLANTED→next2"'* ]] || { echo "$output"; false; }
}
