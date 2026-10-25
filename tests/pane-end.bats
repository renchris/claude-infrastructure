#!/usr/bin/env bats
# lib/pane-end.sh — the ONE "is this session finished?" decision (FIX-DESIGN §2, D8-D10, D16), and
# the three-dot unlanded diff in hooks/lib/session-writes.sh it depends on. Every store is a fixture
# under $BATS_TEST_TMPDIR: temp git repos, synthetic transcripts, a stub crash log, runner exit
# records, fired records and a custody store. Nothing reads the real ~/.claude.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  T="$(cd "$BATS_TEST_TMPDIR" && pwd -P)"
  export HOME="$T/home"; mkdir -p "$HOME"
  export CC_CUSTODY_DIR="$T/custody" CC_CRASH_LOG="$T/crashes.jsonl" CC_PANE_EXIT_DIR="$T/pane-exit" \
         CC_FIRED_DIR="$T/fired"
  mkdir -p "$CC_CUSTODY_DIR" "$CC_PANE_EXIT_DIR" "$CC_FIRED_DIR"
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_NOSYSTEM=1
  SID=d0d00017-aaaa-bbbb-cccc-000000000304
  PANE=304
  TP="$T/$SID.jsonl"
  R="$T/repo"
  # 2026-10-25T10:00:00Z — the transcript's first record, so the default `since`
  START=1792922400
}

pe() { /bin/bash -c 'set -u; . "$1/lib/pane-end.sh"; shift; "$@"' _ "$REPO" "$@"; }
sw() { /bin/bash -c 'set -u; . "$1/hooks/lib/session-writes.sh"; shift; "$@"' _ "$REPO" "$@"; }
fld() { printf '%s\n' "$output" | cut -d $'\037' -f "$1"; }

mkrepo() { # a repo at $R with one commit and origin/main + origin/HEAD pointing at it
  mkdir -p "$R"; git -C "$R" init -q -b main
  printf 'b\n' > "$R/base.txt"; printf 'o\n' > "$R/old.txt"
  git -C "$R" add -A; git -C "$R" commit -qm base
  git -C "$R" update-ref refs/remotes/origin/main HEAD
  git -C "$R" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
}
commit_file() { printf '%s\n' "${2:-x}" > "$R/$1"; git -C "$R" add "$1"; git -C "$R" commit -qm "$1"; }

tx_start() { printf '{"type":"user","timestamp":"2026-10-25T10:00:00.000Z","cwd":"%s","sessionId":"%s","message":{"role":"user","content":"go"}}\n' "${1:-$R}" "$SID" > "$TP"; }
tx_write() { printf '{"type":"assistant","timestamp":"2026-10-25T10:01:00.000Z","cwd":"%s","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Write","input":{"file_path":"%s","content":"x"}}]}}\n' "$R" "$1" >> "$TP"; }
tx_say() { printf '{"type":"assistant","timestamp":"2026-10-25T10:02:00.000Z","cwd":"%s","message":{"role":"assistant","content":[{"type":"text","text":"%s"}]}}\n' "$R" "$1" >> "$TP"; }
tx_think() { printf '{"type":"assistant","timestamp":"2026-10-25T10:03:00.000Z","cwd":"%s","message":{"role":"assistant","content":[{"type":"thinking","thinking":"%s"}]}}\n' "$R" "$1" >> "$TP"; }
tx_team() { printf '{"type":"user","timestamp":"2026-10-25T10:00:30.000Z","cwd":"%s","teamName":"w1","agentName":"t3","message":{"role":"user","content":"brief"}}\n' "$R" >> "$TP"; }

crash_row() { printf '{"ts":"2026-10-25T11:00:00Z","sid":"%s","class":"%s","cause":"%s"}\n' "$SID" "$1" "${2:-x}" >> "$CC_CRASH_LOG"; }
exit_rec() { printf '{"rc":%s,"claude_started":true,"launch_sha":"abc","ts":%s}\n' "$1" "${2:-$((START + 3600))}" > "$CC_PANE_EXIT_DIR/$PANE.json"; }
custody_open() { printf '{"ts":"2026-10-25T10:00:30Z","kind":"open","cwd":"/orig","originatorPane":"%s","targetPane":"%s","marker":"M1","slug":"w1"}\n' "${1:-38}" "$PANE" >> "$CC_CUSTODY_DIR/aaaa.jsonl"; }
custody_discharge() { printf '{"ts":"2026-10-25T11:30:00Z","kind":"%s","cwd":"/orig","targetPane":"%s","marker":"M1","slug":"w1","why":"x"}\n' "${1:-abandon}" "$PANE" >> "$CC_CUSTODY_DIR/aaaa.jsonl"; }
fired_close() { printf '{"closedAt":"%s","transcript":"/x/%s.jsonl"}\n' "${1:-2026-10-25T11:00:00Z}" "$SID" > "$CC_FIRED_DIR/$PANE.json"; }

# ── pe_facts ─────────────────────────────────────────────────────────────────────────────────────

@test "pe_facts: a missing file and an empty path both read 0␟-␟-␟0" {
  run pe pe_facts "$T/nope.jsonl"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '0\037-\037-\0370')" ]
  run pe pe_facts ""
  [ "$output" = "$(printf '0\037-\037-\0370')" ]
}

@test "pe_facts: a 0-record transcript reads 0␟-␟-␟0" {
  : > "$TP"
  run pe pe_facts "$TP"
  [ "$output" = "$(printf '0\037-\037-\0370')" ]
}

@test "pe_facts: close is the LAST text-block close; a thinking block and a user record never count" {
  mkrepo; tx_start; tx_say "Good to close: no"; tx_say "✅ Good to close: yes — done"
  tx_think "Good to close: no"
  printf '{"type":"user","cwd":"%s","message":{"role":"user","content":"An honest Good to close: no"}}\n' "$R" >> "$TP"
  run pe pe_facts "$TP"
  [ "$output" = "$(printf '0\037yes\037%s\0375' "$R")" ]
}

@test "pe_facts: a teamName record key marks a member; the same words inside a message do not" {
  mkrepo; tx_start; tx_say 'quoted \"teamName\":\"w9\" in prose'
  run pe pe_facts "$TP"
  [ "$(fld 1)" = 0 ]
  tx_team
  run pe pe_facts "$TP"
  [ "$(fld 1)" = 1 ]
}

@test "pe_facts: a read that dies reports records '-', never 0 (which would mean 'never received a turn')" {
  mkrepo; tx_start
  mkdir -p "$T/bin"; printf '#!/bin/sh\nexit 137\n' > "$T/bin/python3"; chmod +x "$T/bin/python3"
  PATH="$T/bin:$PATH" run pe pe_facts "$TP"
  [ "$output" = "$(printf '0\037-\037-\037-')" ]
}

# ── pe_end ───────────────────────────────────────────────────────────────────────────────────────

@test "pe_end: the class argument decides — CRASH is crash, RECYCLE is clean" {
  run pe pe_end "$SID" "$PANE" "$START" CRASH
  [ "$output" = crash ]
  run pe pe_end "$SID" "$PANE" "$START" RECYCLE
  [ "$output" = clean ]
}

@test "pe_end: RECYCLE in the crash log is a clean end, and the LATEST row for the sid wins (B8)" {
  crash_row CRASH sigterm; crash_row RECYCLE clean-exit
  printf '{"sid":"someone-else","class":"CRASH"}\n' >> "$CC_CRASH_LOG"
  exit_rec 143
  run pe pe_end "$SID" "$PANE" "$START"
  [ "$output" = clean ]
}

@test "pe_end: with no crash row, a fresh exit record decides — 0 and 75 clean, anything else crash" {
  exit_rec 0;   run pe pe_end "$SID" "$PANE" "$START"; [ "$output" = clean ]
  exit_rec 75;  run pe pe_end "$SID" "$PANE" "$START"; [ "$output" = clean ]
  exit_rec 143; run pe pe_end "$SID" "$PANE" "$START"; [ "$output" = crash ]
}

@test "pe_end: an exit record from before the session start, or none at all, is unknown" {
  run pe pe_end "$SID" "$PANE" "$START"
  [ "$output" = unknown ]
  exit_rec 143 $((START - 1))
  run pe pe_end "$SID" "$PANE" "$START"
  [ "$output" = unknown ]
}

# ── pe_work ──────────────────────────────────────────────────────────────────────────────────────

@test "pe_work: an absent dir and a non-repo dir both read '-'" {
  mkdir -p "$T/plain"
  run pe pe_work "$TP" "$T/gone" strict;  [ "$output" = - ]
  run pe pe_work "$TP" "$T/plain" strict; [ "$output" = - ]
  run pe pe_work "$TP" - own;             [ "$output" = - ]
}

@test "pe_work: a clean, landed tree is clean without reading the transcript at all" {
  mkrepo
  run pe pe_work "$T/never-written.jsonl" "$R" own
  [ "$output" = clean ]
}

@test "pe_work own: only the session's Edit/Write-recorded paths count as dirty" {
  mkrepo; tx_start; tx_write "$R/mine.txt"
  printf 'sib\n' > "$R/sibling.txt"
  run pe pe_work "$TP" "$R" own
  [ "$output" = clean ]
  printf 'm\n' > "$R/mine.txt"
  run pe pe_work "$TP" "$R" own
  [ "$output" = dirty:1 ]
}

@test "pe_work own: an unreadable transcript over a dirty tree is unknown" {
  mkrepo; printf 'sib\n' > "$R/sibling.txt"
  run pe pe_work "$T/never-written.jsonl" "$R" own
  [ "$output" = unknown ]
}

@test "pe_work own: a commit ahead of trunk touching a file the session wrote is unlanded" {
  mkrepo; tx_start; tx_write "$R/mine.txt"
  commit_file other.txt
  run pe pe_work "$TP" "$R" own
  [ "$output" = clean ]
  commit_file mine.txt
  run pe pe_work "$TP" "$R" own
  [ "$output" = unlanded:2 ]
}

@test "pe_work strict: whole-cwd porcelain counts a sibling's dirt, then own unlanded" {
  mkrepo; tx_start; tx_write "$R/mine.txt"
  printf 'sib\n' > "$R/sibling.txt"
  run pe pe_work "$TP" "$R" strict
  [ "$output" = dirty:1 ]
  rm -f "$R/sibling.txt"; commit_file mine.txt
  run pe pe_work "$TP" "$R" strict
  [ "$output" = unlanded:1 ]
}

@test "pe_work strict: a git mv of an old file is dirty — mtime is never a per-path proof (I4)" {
  mkrepo; tx_start
  touch -t 202001010000 "$R/old.txt"
  git -C "$R" mv old.txt moved.txt
  touch -t 202001010000 "$R/moved.txt"
  run pe pe_work "$TP" "$R" strict
  [ "$output" = dirty:1 ]
}

@test "pe_work team: whole-cwd porcelain only — commits ahead of trunk do not count" {
  mkrepo; tx_start; tx_write "$R/mine.txt"
  commit_file mine.txt
  run pe pe_work "$TP" "$R" team
  [ "$output" = clean ]
  printf 'sib\n' > "$R/sibling.txt"
  run pe pe_work "$TP" "$R" team
  [ "$output" = dirty:1 ]
}

@test "trunk ladder: origin/main alone (no origin/HEAD) still finds the unlanded commit (B5c)" {
  mkrepo; tx_start; tx_write "$R/mine.txt"
  git -C "$R" symbolic-ref -d refs/remotes/origin/HEAD
  commit_file mine.txt
  run pe pe_work "$TP" "$R" own
  [ "$output" = unlanded:1 ]
}

@test "trunk ladder: origin/master is the last rung" {
  mkrepo; tx_start; tx_write "$R/mine.txt"
  git -C "$R" symbolic-ref -d refs/remotes/origin/HEAD
  git -C "$R" update-ref refs/remotes/origin/master refs/remotes/origin/main
  git -C "$R" update-ref -d refs/remotes/origin/main
  commit_file mine.txt
  run pe pe_work "$TP" "$R" own
  [ "$output" = unlanded:1 ]
}

@test "trunk ladder: no trunk resolves ⇒ the unlanded step is skipped, not guessed" {
  mkrepo; tx_start; tx_write "$R/mine.txt"
  git -C "$R" symbolic-ref -d refs/remotes/origin/HEAD
  git -C "$R" update-ref -d refs/remotes/origin/main
  commit_file mine.txt
  run pe pe_work "$TP" "$R" own
  [ "$output" = clean ]
}

@test "three dots: a behind-only checkout has nothing unlanded (session_unlanded_mine, B5b)" {
  mkrepo; tx_start; tx_write "$R/mine.txt"
  commit_file mine.txt trunk-side
  git -C "$R" update-ref refs/remotes/origin/main HEAD
  git -C "$R" checkout -q HEAD~1
  run sw session_unlanded_mine "$TP" "$R" origin/main
  [ "$status" -eq 1 ]
}

@test "three dots: diverged from trunk, only HEAD's own side counts (B5b through pe_work)" {
  mkrepo; tx_start; tx_write "$R/mine.txt"
  commit_file mine.txt trunk-side
  git -C "$R" update-ref refs/remotes/origin/main HEAD
  git -C "$R" checkout -q HEAD~1
  commit_file other.txt
  run pe pe_work "$TP" "$R" own
  [ "$output" = clean ]
}

# ── pe_verdict: one test per §2 row ──────────────────────────────────────────────────────────────

@test "row 1: custody discharged since the start ⇒ COLLECTED, whatever the tree says" {
  mkrepo; tx_start; printf 'sib\n' > "$R/sibling.txt"; crash_row CRASH
  custody_open 38; custody_discharge abandon
  run pe pe_verdict "$SID" "$TP" "$PANE"
  [ "$(fld 1)" = COLLECTED ]
  [ "$(fld 6)" = 38 ]
}

@test "row 1b: no transcript and a clean end ⇒ DONE (pane 304: never received a turn)" {
  mkrepo; printf 'sib\n' > "$R/sibling.txt"; crash_row RECYCLE clean-exit
  run pe pe_verdict "$SID" "$T/absent.jsonl" "$PANE"
  [ "$(fld 1)" = DONE ]
  [ "$(fld 2)" = "session d0d00017 never received a turn" ]
}

@test "row 1b: a 0-record transcript with an rc-0 exit ⇒ DONE; with a crash or unknown end ⇒ CANTTELL" {
  : > "$TP"; exit_rec 0 $((START + 10))
  run pe pe_verdict "$SID" "$TP" "$PANE" "$START"
  [ "$(fld 1)" = DONE ]
  exit_rec 143 $((START + 10))
  run pe pe_verdict "$SID" "$TP" "$PANE" "$START"
  [ "$(fld 1)" = CANTTELL ]
  rm -f "$CC_PANE_EXIT_DIR/$PANE.json"
  run pe pe_verdict "$SID" "$TP" "$PANE" "$START"
  [ "$(fld 1)" = CANTTELL ]
}

@test "row 2: a team member with a clean cwd ⇒ DONE" {
  mkrepo; tx_start; tx_team; crash_row RECYCLE
  run pe pe_verdict "$SID" "$TP" "$PANE"
  [ "$(fld 1)" = DONE ]
}

@test "row 2: a team member over ANY dirt ⇒ CANTTELL, even a clean end with no own writes (I3)" {
  mkrepo; tx_start; tx_team; tx_say "Good to close: yes"; crash_row RECYCLE
  printf 'sib\n' > "$R/sibling.txt"
  run pe pe_verdict "$SID" "$TP" "$PANE"
  [ "$(fld 1)" = CANTTELL ]
  [ "$(fld 3)" = dirty:1 ]
}

@test "row 3: yes on a clean end, sibling dirt only ⇒ DONE (own mode)" {
  mkrepo; tx_start; tx_write "$R/mine.txt"; tx_say "Good to close: yes"; crash_row RECYCLE
  printf 'sib\n' > "$R/sibling.txt"
  run pe pe_verdict "$SID" "$TP" "$PANE"
  [ "$(fld 1)" = DONE ]
  [ "$(fld 5)" = clean ]
}

@test "row 3: yes on a clean end over the session's own dirt ⇒ CANTTELL, naming its files" {
  mkrepo; tx_start; tx_write "$R/mine.txt"; tx_say "Good to close: yes"; crash_row RECYCLE
  printf 'm\n' > "$R/mine.txt"
  run pe pe_verdict "$SID" "$TP" "$PANE"
  [ "$(fld 1)" = CANTTELL ]
  [ "$(fld 2)" = "1 uncommitted change(s) in files session d0d00017 wrote" ]
}

@test "row 3: yes on a clean end over own unlanded commits ⇒ CANTTELL, naming the trunk" {
  mkrepo; tx_start; tx_write "$R/mine.txt"; tx_say "Good to close: yes"; crash_row RECYCLE
  commit_file mine.txt
  run pe pe_verdict "$SID" "$TP" "$PANE"
  [ "$(fld 1)" = CANTTELL ]
  [ "$(fld 2)" = "commits touching files session d0d00017 wrote are not on origin/main" ]
}

@test "row 3: a stale yes, a Bash-only write, a CRASH row and no exit record ⇒ RESUME (I2n)" {
  mkrepo; tx_start; tx_say "Good to close: yes"; crash_row CRASH sigkill
  printf 'bash-only\n' > "$R/via-sed.txt"
  run pe pe_verdict "$SID" "$TP" "$PANE"
  [ "$(fld 1)" = RESUME ]
  [ "$(fld 2)" = "1 uncommitted change(s), and session d0d00017 did not end cleanly, so every change counts" ]
}

@test "fallback cwd: a transcript with no cwd uses the caller's, so a crash over dirt is RESUME, not DONE" {
  mkrepo
  # records with no cwd field at all (tx_start/tx_say both carry one)
  printf '{"type":"user","timestamp":"2026-10-25T10:00:00.000Z","sessionId":"%s","message":{"role":"user","content":"go"}}\n' "$SID" > "$TP"
  printf '{"type":"assistant","timestamp":"2026-10-25T10:02:00.000Z","message":{"role":"assistant","content":[{"type":"text","text":"Good to close: yes"}]}}\n' >> "$TP"
  crash_row CRASH sigkill
  printf 'x\n' > "$R/dirty.txt"
  run pe pe_verdict "$SID" "$TP" "$PANE"
  [ "$(fld 1)" = DONE ]                      # no cwd anywhere: nothing to read, so nothing open
  run pe pe_verdict "$SID" "$TP" "$PANE" "" "" "$R"
  [ "$(fld 1)" = RESUME ]
  [ "$(fld 7)" = "$R" ]
  tx_start "$T"                              # a transcript cwd outranks the fallback
  run pe pe_verdict "$SID" "$TP" "$PANE" "" "" "$R"
  [ "$(fld 7)" = "$T" ]
}

@test "row 3: yes, crash, dirt, custody open ⇒ OWNED by the originator pane" {
  mkrepo; tx_start; tx_say "Good to close: yes"; crash_row CRASH
  printf 'x\n' > "$R/via-sed.txt"; custody_open 41
  run pe pe_verdict "$SID" "$TP" "$PANE"
  [ "$(fld 1)" = OWNED ]
  [ "$(fld 6)" = 41 ]
}

@test "row 3: yes on an unknown end counts every change (strict) ⇒ CANTTELL" {
  mkrepo; tx_start; tx_say "Good to close: yes"
  printf 'sib\n' > "$R/sibling.txt"
  run pe pe_verdict "$SID" "$TP" "$PANE"
  [ "$(fld 1)" = CANTTELL ]
  [ "$(fld 5)" = unknown ]
}

@test "row 3: a self-close stamp since the start stands in for yes; a stale one does not" {
  mkrepo; tx_start; tx_say "Good to close: no"; crash_row RECYCLE
  fired_close 2026-10-25T11:00:00Z
  run pe pe_verdict "$SID" "$TP" "$PANE"
  [ "$(fld 1)" = DONE ]
  fired_close 2026-10-24T09:00:00Z
  run pe pe_verdict "$SID" "$TP" "$PANE"
  [ "$(fld 1)" = CANTTELL ]
}

@test "row 4: a crash with no yes ⇒ RESUME; with custody open ⇒ OWNED" {
  mkrepo; tx_start; tx_say "Good to close: no"; exit_rec 143
  run pe pe_verdict "$SID" "$TP" "$PANE"
  [ "$(fld 1)" = RESUME ]
  [ "$(fld 4)" = no ]
  custody_open 38
  run pe pe_verdict "$SID" "$TP" "$PANE"
  [ "$(fld 1)" = OWNED ]
}

@test "row 5: no on a RECYCLE end is CANTTELL, never RESUME (B8)" {
  mkrepo; tx_start; tx_say "Good to close: no"; crash_row RECYCLE clean-exit
  run pe pe_verdict "$SID" "$TP" "$PANE"
  [ "$(fld 1)" = CANTTELL ]
  [ "$(fld 5)" = clean ]
}

@test "row 5: no close at all on an unknown end ⇒ CANTTELL; the record carries all seven fields" {
  mkrepo; tx_start
  run pe pe_verdict "$SID" "$TP" "$PANE"
  [ "$(fld 1)" = CANTTELL ]
  [ "$(printf '%s' "$output" | tr -cd '\037' | wc -c | tr -d ' ')" = 6 ]
  [ "$(fld 3)" = clean ]
  [ "$(fld 4)" = - ]
  [ "$(fld 6)" = - ]
  [ "$(fld 7)" = "$R" ]
}

@test "since defaults to the transcript start: an exit record from the pane's previous tenant is ignored" {
  mkrepo; tx_start; tx_say "Good to close: no"; exit_rec 143 $((START - 60))
  run pe pe_verdict "$SID" "$TP" "$PANE"
  [ "$(fld 5)" = unknown ]
  [ "$(fld 1)" = CANTTELL ]
}

@test "sourcing is side-effect free and set -u clean" {
  run /bin/bash -c 'set -u; cd "$2"; . "$1/lib/pane-end.sh" >"$2/src.out" 2>&1; declare -F pe_verdict pe_work pe_end pe_facts >/dev/null' _ "$REPO" "$T"
  [ "$status" -eq 0 ]
  [ ! -s "$T/src.out" ]
  [ "$(find "$T" -mindepth 1 -maxdepth 1 ! -name src.out ! -name home ! -name custody ! -name pane-exit ! -name fired | wc -l | tr -d ' ')" = 0 ]
}
