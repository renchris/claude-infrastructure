#!/usr/bin/env bats
# lead-crash-watchdog.sh — ASSIGNEE HARVEST (leg a). On lead death, each assignee's final report is
# recovered from DISK TRUTH (its own transcript JSONL), never from a notification, and ALWAYS before
# any teardown: cc-teardown closes the pane, and a closed pane cannot be harvested.
#
# Observed 2026-07-26 on team session-a3f68174 — lead died, 8 assignees survived, every final report
# reachable only by hand-digging transcripts off disk. That manual dig is what this leg replaces.
#
# Coverage:
#   (i)    cwd-slug resolution encodes BOTH '/' and '.' as '-'   ← the measured near-miss
#   (ii)   a slash-only slug finds NOTHING (guards the fix from silently regressing)
#   (iii)  the LAST assistant message wins (mid-run narration must not shadow the final report)
#   (iv)   tool_use / thinking blocks carry no text and are skipped
#   (v)    several assignees in ONE worktree are disambiguated by agentName
#   (vi)   the newest transcript wins when an assignee was re-fired
#   (vii)  status.tsv is THREE-state: HARVESTED / EMPTY / NO-TRANSCRIPT
#   (viii) team-lead is never harvested as an assignee
#   (ix)   a transcript with no assistant text is EMPTY (proven), not NO-TRANSCRIPT (unresolved)

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  WD="$REPO/hooks/lead-crash-watchdog.sh"

  # Fixture $HOME — without it this suite reads the operator's LIVE ~/.claude transcript corpus and
  # its "harvest" assertions become assertions about real sessions.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"

  # Fixture the account roots the harvest scans, so nothing reaches a real projects/ dir.
  export CC_ACCOUNT_BASES="$BATS_TEST_TMPDIR/acct1 $BATS_TEST_TMPDIR/acct2"
  A1="$BATS_TEST_TMPDIR/acct1"; A2="$BATS_TEST_TMPDIR/acct2"
  mkdir -p "$A1/projects" "$A2/projects"

  # A worktree cwd containing a DOT segment — the shape every dispatch worktree actually has.
  CWD="$BATS_TEST_TMPDIR/Development/.worktrees/wt-pool-9"
  mkdir -p "$CWD"
  SLUG_DOT="$(s="${CWD//\//-}"; echo "${s//./-}")"   # '/'+'.' → '-'  (the real CC encoding)
  SLUG_SLASH="${CWD//\//-}"                          # '/' only      (the near-miss)
  PROJ="$A1/projects/$SLUG_DOT"; mkdir -p "$PROJ"
}

# Append one assistant text record to a transcript fixture.
mk_assistant() { # $1=file $2=agentName $3=text
  printf '{"message":{"role":"assistant","content":[{"type":"text","text":"%s"}]},"agentName":"%s"}\n' \
    "$3" "$2" >> "$1"
}

@test "(i) cwd-slug resolution encodes BOTH slash and dot — the real CC project-dir encoding" {
  mk_assistant "$PROJ/s1.jsonl" "aa-worker" "FINAL REPORT AA"
  run bash "$WD" --harvest-member "aa-worker" "$CWD"
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"TRANSCRIPT $PROJ/s1.jsonl"* ]] || false
  [[ "$output" == *"FINAL REPORT AA"* ]] || false
}

@test "(ii) with the corpus fallback OFF, the cwd-slug path alone still resolves the dot encoding" {
  # Strategy 1 in ISOLATION. Without disabling the fallback, a broken slug encoding is silently
  # rescued by the corpus walk and the dot-encoding bug looks fixed when it is not.
  mk_assistant "$PROJ/s1.jsonl" "bb-worker" "PRIMARY PATH REPORT"
  LCW_HARVEST_FALLBACK= run bash "$WD" --harvest-member "bb-worker" "$CWD"
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"PRIMARY PATH REPORT"* ]] || false
}

@test "(ii-b) a slash-only slug dir is NOT where CC writes — the primary path must miss it" {
  # The measured near-miss, pinned: filed under the slash-only encoding, the cwd-slug path must
  # resolve NOTHING. With the fallback off this fails loudly instead of silently harvesting nothing.
  [ "$SLUG_DOT" != "$SLUG_SLASH" ] || false          # the fixture must actually exercise the case
  mkdir -p "$A1/projects/$SLUG_SLASH"
  mk_assistant "$A1/projects/$SLUG_SLASH/s1.jsonl" "bb2-worker" "WRONG DIR"
  LCW_HARVEST_FALLBACK= run bash "$WD" --harvest-member "bb2-worker" "$CWD"
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"NO-TRANSCRIPT"* ]] || false
}

@test "(ii-c) the corpus fallback DOES rescue a transcript whose worktree the lead force-removed" {
  # The observed incident: the lead force-removed every assignee worktree, so the cwd-slug dir may
  # not exist at all. The report must still be recovered — losing it is the failure this leg exists
  # to prevent. This is why the fallback is not merely nice-to-have.
  mkdir -p "$A1/projects/-Users-somewhere-else-entirely"
  mk_assistant "$A1/projects/-Users-somewhere-else-entirely/s1.jsonl" "kk-worker" "RESCUED REPORT"
  run bash "$WD" --harvest-member "kk-worker" "$BATS_TEST_TMPDIR/gone/wt-vanished"
  [[ "$output" == *"RESCUED REPORT"* ]] || false
}

@test "(iii) the LAST assistant message wins — mid-run narration must not shadow the final report" {
  mk_assistant "$PROJ/s1.jsonl" "cc-worker" "interim narration"
  mk_assistant "$PROJ/s1.jsonl" "cc-worker" "THE FINAL REPORT"
  run bash "$WD" --harvest-member "cc-worker" "$CWD"
  [[ "$output" == *"THE FINAL REPORT"* ]] || false
  [[ "$output" == *"interim narration"* ]] && false
  true
}

@test "(iv) tool_use and thinking blocks carry no text and are skipped" {
  mk_assistant "$PROJ/s1.jsonl" "dd-worker" "REAL TEXT REPORT"
  printf '{"message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{}}]},"agentName":"dd-worker"}\n' >> "$PROJ/s1.jsonl"
  printf '{"message":{"role":"assistant","content":[{"type":"thinking","thinking":"pondering"}]},"agentName":"dd-worker"}\n' >> "$PROJ/s1.jsonl"
  run bash "$WD" --harvest-member "dd-worker" "$CWD"
  [[ "$output" == *"REAL TEXT REPORT"* ]] || false
  [[ "$output" == *"pondering"* ]] && false
  true
}

@test "(v) several assignees share one worktree — disambiguated by agentName" {
  mk_assistant "$PROJ/s1.jsonl" "ee-one" "REPORT ONE"
  mk_assistant "$PROJ/s2.jsonl" "ee-two" "REPORT TWO"
  run bash "$WD" --harvest-member "ee-two" "$CWD"
  [[ "$output" == *"REPORT TWO"* ]] || false
  [[ "$output" == *"REPORT ONE"* ]] && false
  true
}

@test "(vi) an assignee re-fired twice harvests the NEWEST transcript" {
  mk_assistant "$PROJ/old.jsonl" "ff-worker" "STALE FIRST RUN"
  mk_assistant "$PROJ/new.jsonl" "ff-worker" "LATEST RUN REPORT"
  touch -t 202001010000 "$PROJ/old.jsonl"
  run bash "$WD" --harvest-member "ff-worker" "$CWD"
  [[ "$output" == *"LATEST RUN REPORT"* ]] || false
  [[ "$output" == *"STALE FIRST RUN"* ]] && false
  true
}

@test "(vii) an assignee with no transcript anywhere reports NO-TRANSCRIPT, not a silent empty" {
  run bash "$WD" --harvest-member "gg-never-ran" "$CWD"
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"NO-TRANSCRIPT"* ]] || false
}

@test "(viii) a transcript holding no assistant text yields an EMPTY report, not a crash" {
  printf '{"message":{"role":"user","content":"hi"},"agentName":"hh-worker"}\n' > "$PROJ/s1.jsonl"
  run bash "$WD" --harvest-member "hh-worker" "$CWD"
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"TRANSCRIPT"* ]] || false          # resolved (so NOT "no transcript") …
  [[ "$output" != *"NO-TRANSCRIPT"* ]] || false       # … and reported as resolved-but-empty
}

@test "(ix) a malformed JSONL line is skipped, and the good record still harvests" {
  printf 'not json at all\n' > "$PROJ/s1.jsonl"
  mk_assistant "$PROJ/s1.jsonl" "ii-worker" "SURVIVED THE GARBAGE"
  run bash "$WD" --harvest-member "ii-worker" "$CWD"
  [[ "$output" == *"SURVIVED THE GARBAGE"* ]] || false
}

@test "(x) harvest resolves a transcript in a SECOND account root (multi-account fleet)" {
  P2="$A2/projects/$SLUG_DOT"; mkdir -p "$P2"
  mk_assistant "$P2/s9.jsonl" "jj-worker" "SECOND ACCOUNT REPORT"
  run bash "$WD" --harvest-member "jj-worker" "$CWD"
  [[ "$output" == *"SECOND ACCOUNT REPORT"* ]] || false
}
