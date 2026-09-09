#!/usr/bin/env bats
# scripts/limit-recover/lr-fleet.sh — the /limit-recover fleet front end (LIMIT_RECOVER_100P).
# Hermetic: four fixture stores under $HOME, a fixture registry, a recording lr-handoff stub, a
# claude-accounts stub, and the capacity gate pinned open. Nothing here types into a pane.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  FLEET="$REPO/scripts/limit-recover/lr-fleet.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/bin"
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg"; mkdir -p "$CC_REGISTRY_DIR"
  export LR_STATE_DIR="$BATS_TEST_TMPDIR/state"; mkdir -p "$LR_STATE_DIR/locks"
  export CC_ADMIT_GATE=off
  export CC_ACCOUNT_MAP="$BATS_TEST_TMPDIR/absent-map"
  SEC="$HOME/.claude-secondary"; TER="$HOME/.claude-tertiary"
  SLUG="-Users-x-thing"; mkdir -p "$SEC/projects/$SLUG" "$TER/projects/$SLUG"
  export LR_CONFIG_DIRS="$SEC:$TER"
  CWD="$BATS_TEST_TMPDIR/wt"; mkdir -p "$CWD"
  # The incident sid, with a ZEROED tail. The full 2026-09-09 uuid is LIVE on this box (a tmux
# `claude --resume <that uuid>` has been running since 00:51Z), and both liveness censuses under
# test — lr-select's `pgrep -f "resume <sid>"` and lr-lib's `ps -axo command=` / `--resume <sid>`
# — read the REAL process table, so the fixture's own registry row stopped being the only voice:
# --locate said DUPLICATE where the case pins RECOVERABLE, and the poller retired the record before
# it could nudge. A fixture may never name an identifier that can exist outside it (memory:
# hermetic-in-stubs-not-in-interpreter). The `52e35019` prefix is kept — it is what the display
# assertions match on, and it is how this suite stays legible against the incident it was written from.
  SID="52e35019-17e8-40f6-a54f-000000000000"
  # lr-handoff stub: records argv, exits per LRH_RC, prints the announcements the fleet parses
  export LR_HANDOFF_BIN="$BATS_TEST_TMPDIR/lr-handoff"
  cat > "$LR_HANDOFF_BIN" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >> "${LRH_LOG:?}"
case "${LRH_MODE:-inplace}" in
  inplace) echo "lr-handoff: recycled IN PLACE — pane X continues session Y" >&2 ;;
  replace) echo "lr-handoff: REPLACED in place — successor pane 701 fired beside source pane 616 on 'next3'" >&2 ;;
esac
echo "/bundle/path"
exit "${LRH_RC:-0}"
SH
  chmod +x "$LR_HANDOFF_BIN"; export LRH_LOG="$BATS_TEST_TMPDIR/lrh.log"; : > "$LRH_LOG"
  export CC_ACCOUNTS_BIN="$HOME/bin/claude-accounts"
  cat > "$CC_ACCOUNTS_BIN" <<'SH'
#!/bin/bash
case "$*" in *--rank*) printf 'next2 0.9\nnext3 0.8\nnext4 0.5\n' ;; esac
SH
  chmod +x "$CC_ACCOUNTS_BIN"
}
blocked_tx() { # $1=store $2=sid [$3=model $4=effort]
  local f="$1/projects/$SLUG/$2.jsonl"
  printf '{"type":"user","cwd":"%s","timestamp":"2026-09-08T22:00:00.000Z","message":{"role":"user","content":"go"}}\n' "$CWD" > "$f"
  printf '{"type":"assistant","timestamp":"2026-09-08T22:30:00.000Z","effort":"%s","message":{"role":"assistant","model":"%s","content":[{"type":"text","text":"work"}]}}\n' "${4:-xhigh}" "${3:-claude-fable-5-1}" >> "$f"
  printf '{"type":"assistant","timestamp":"2026-09-08T23:11:09.000Z","isApiErrorMessage":true,"message":{"role":"assistant","content":[{"type":"text","text":"You'"'"'ve hit your session limit · resets 7:50pm"}]}}\n' >> "$f"
}
row() { printf '{"paneUUID":"%s","session_id":"%s","pid":%d,"account":"claude-secondary","cwd":"%s"}\n' "$1" "$2" "${3:-$$}" "$CWD" > "$CC_REGISTRY_DIR/$1.json"; }

@test "locate: a limit-blocked session with a live registry pane is RECOVERABLE, with its pane and transcript tier" {
  blocked_tx "$SEC" "$SID"; row 616 "$SID"
  run bash "$FLEET" --locate
  [ "$status" -eq 0 ]
  # ACCT is the account NAME, not the config-dir basename: lr-fleet resolves it through the repo's
  # own lib/account-map.generated.sh (CC_ACCOUNT_MAP is only the first candidate, and pinning it at
  # an absent path falls through to that in-repo map rather than to the basename).
  # The census is COLUMN-PADDED, so the row is matched on a whitespace-squeezed copy — pinning the
  # literal single-space spelling asserts the column widths, which is not what this case is about.
  [[ "$(printf '%s' "$output" | tr -s ' ')" == *"52e35019 next2 616"* ]] || { echo "$output"; false; }
  [[ "$output" == *"claude-fable-5-1/xhigh"* ]] || { echo "$output"; false; }
  [[ "$output" == *"RECOVERABLE"* ]] || { echo "$output"; false; }
}
@test "locate: a session that took a real turn since its limit error is NOT blocked (the tail rule)" {
  blocked_tx "$SEC" "$SID"
  printf '{"type":"assistant","timestamp":"2026-09-09T01:00:00.000Z","message":{"role":"assistant","model":"claude-opus-5","content":[{"type":"text","text":"back"}]}}\n' >> "$SEC/projects/$SLUG/$SID.jsonl"
  run bash "$FLEET" --locate
  [[ "$output" == *"(no limit-blocked session anywhere)"* ]] || { echo "$output"; false; }
}
@test "locate: no live process holding it is NO-PANE; a teammate transcript is TEAMMATE" {
  blocked_tx "$SEC" "$SID"
  tm="9b9b9b9b-0000-4000-8000-000000000002"; blocked_tx "$SEC" "$tm"
  sed -i '' '1s/{"type":"user",/{"type":"user","agentName":"w1",/' "$SEC/projects/$SLUG/$tm.jsonl"
  run bash "$FLEET" --locate
  [[ "$output" == *"52e35019"*"NO-PANE"* ]] || { echo "$output"; false; }
  [[ "$output" == *"9b9b9b9b"*"TEAMMATE"* ]] || { echo "$output"; false; }
}
@test "locate: a session already transplanted (lock names another store, successor on disk) is TRANSPLANTED" {
  blocked_tx "$SEC" "$SID"; row 616 "$SID"
  printf '{"sid":"%s","from":"%s","to":"%s"}\n' "$SID" "$SEC" "$TER" > "$LR_STATE_DIR/locks/$SID.lock"
  : > "$TER/projects/$SLUG/$SID.jsonl"
  run bash "$FLEET" --locate
  [[ "$output" == *"TRANSPLANTED→"* ]] || { echo "$output"; false; }
}
@test "locate: two live processes on one sid is DUPLICATE, never RECOVERABLE" {
  blocked_tx "$SEC" "$SID"; row 616 "$SID"; row 647 "$SID"
  run bash "$FLEET" --locate
  [[ "$output" == *"DUPLICATE"* ]] || { echo "$output"; false; }
}
@test "locate --json emits one object per session with the same fields" {
  blocked_tx "$SEC" "$SID"; row 616 "$SID"
  run bash "$FLEET" --locate --json
  echo "$output" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d[0]["pane"]=="616" and d[0]["disposition"]=="RECOVERABLE", d'
}

@test "recover: drives lr-handoff --in-place with the pane, the transcript tier and a target that is NOT the limited account" {
  blocked_tx "$SEC" "$SID"; row 616 "$SID"
  run bash "$FLEET" --recover
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -q -- "--sid $SID --config-dir $SEC --cwd $CWD --target next3 --launch --in-place --source-pane 616 --model claude-fable-5-1 --effort xhigh" "$LRH_LOG" || { cat "$LRH_LOG"; false; }
  [[ "$output" == *"RECOVERY COMPLETE — 1 in place (same pane id), 0 replaced"* ]] || { echo "$output"; false; }
}
@test "recover: the ranked winner is skipped when it IS the limited account (its 5h window just closed)" {
  blocked_tx "$SEC" "$SID"; row 616 "$SID"
  # .claude-secondary IS next2 in the repo's account map, which lr-fleet resolves even with
  # CC_ACCOUNT_MAP pinned at an absent path — so rank next2 first and it must be passed over.
  printf '#!/bin/bash\ncase "$*" in *--rank*) printf "next2 0.9\\nnext4 0.5\\n" ;; esac\n' > "$CC_ACCOUNTS_BIN"
  run bash "$FLEET" --recover
  grep -q -- "--target next4" "$LRH_LOG" || { cat "$LRH_LOG"; false; }
}
@test "recover --dry-run composes the same argv and touches nothing" {
  blocked_tx "$SEC" "$SID"; row 616 "$SID"
  run bash "$FLEET" --recover --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"would recover 52e35019: pane 616"*"--in-place --source-pane 616"* ]] || { echo "$output"; false; }
  [ ! -s "$LRH_LOG" ]
}
@test "recover: a REPLACE announcement is reported as replaced beside its source, with the new pane id" {
  blocked_tx "$SEC" "$SID"; row 616 "$SID"
  LRH_MODE=replace run bash "$FLEET" --recover
  [ "$status" -eq 0 ]
  [[ "$output" == *"52e35019  616      701"* ]] || { echo "$output"; false; }
  [[ "$output" == *"replace-in-place/RECOVERED"* ]] || { echo "$output"; false; }
  [[ "$output" == *"0 in place (same pane id), 1 replaced beside their source"* ]] || { echo "$output"; false; }
}
@test "recover: lr-handoff rc 4 (transplanted, relaunch unverified) is a NAMED gap — RECOVERY PARTIAL, exit 1" {
  blocked_tx "$SEC" "$SID"; row 616 "$SID"
  LRH_RC=4 run bash "$FLEET" --recover
  [ "$status" -eq 1 ]
  [[ "$output" == *"RECOVERY PARTIAL — 1 named gap"* ]] || { echo "$output"; false; }
  [[ "$output" == *"recycle-in-place/PARTIAL"*"transplanted but the relaunch did not verify"* ]] || { echo "$output"; false; }
}
@test "recover: a DUPLICATE is parked and named, never recovered over two live processes" {
  blocked_tx "$SEC" "$SID"; row 616 "$SID"; row 647 "$SID"
  run bash "$FLEET" --recover
  [ "$status" -eq 1 ]
  [ ! -s "$LRH_LOG" ]
  [[ "$output" == *"DUPLICATE — more than one live process"* ]] || { echo "$output"; false; }
}
@test "recover: sessions are sequenced one at a time and --max bounds a run" {
  blocked_tx "$SEC" "$SID"; row 616 "$SID"
  s2="66660000-0000-4000-8000-000000000003"; blocked_tx "$SEC" "$s2"; row 630 "$s2"
  run bash "$FLEET" --recover --max 1
  [ "$status" -eq 1 ]
  [ "$(grep -c -- '--in-place' "$LRH_LOG")" = 1 ]
  [[ "$output" == *"--max 1 reached"* ]] || { echo "$output"; false; }
}

@test "enqueue: a request per RECOVERABLE session lands in the poller's requests dir and names the kickstart" {
  blocked_tx "$SEC" "$SID"; row 616 "$SID"
  run bash "$FLEET" --enqueue --target next4
  [ "$status" -eq 0 ]
  [ -f "$LR_STATE_DIR/requests/$SID.json" ]
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["source_pane"]=="616" and d["target"]=="next4", d' "$LR_STATE_DIR/requests/$SID.json"
  [[ "$output" == *"launchctl kickstart -k gui/"* ]] || { echo "$output"; false; }
}

@test "duplicates: a sid held by two live registry panes is listed with both, and --mark writes the SUPERSEDED tombstone" {
  blocked_tx "$SEC" "$SID"; row 616 "$SID"; row 647 "$SID"
  run bash "$FLEET" --duplicates
  [[ "$output" == *"DUPLICATE 52e35019: 2 registry pane(s)"* ]] || { echo "$output"; false; }
  run bash "$FLEET" --duplicates --mark "$SID" --live "$$"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  tomb="$SEC/projects/$SLUG/$SID.HANDOFF.json"
  [ -f "$tomb" ]
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["superseded_by_pid"]==int(sys.argv[2]) and d["handed_off_to"].endswith(".claude-secondary"), d' "$tomb" "$$"
  run bash "$FLEET" --duplicates --mark "$SID" --live "$$"
  [ "$status" -eq 2 ]                                      # never overwrites a tombstone
}
@test "duplicates --mark refuses a dead --live pid: a SUPERSEDED tombstone must name a live successor" {
  blocked_tx "$SEC" "$SID"; row 616 "$SID"
  run bash "$FLEET" --duplicates --mark "$SID" --live 4194103
  [ "$status" -eq 2 ]
}
@test "iron rule 7: the fleet driver never pushes, ships or deploys" {
  run grep -nE 'git push|/ship|ship-land|deploy-live' "$FLEET"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
}
