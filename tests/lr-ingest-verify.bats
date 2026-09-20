#!/usr/bin/env bats
# lr-ingest-verify.sh — the precondition that licenses skipping `/limit-recover ingest`.
#
# WHY THIS GATE EXISTS (U12 §3-§6, re-measured here). The ingest costs 6-9 model round trips, 6-8
# tool calls and ~26.5 K PERMANENTLY RESIDENT tokens per recovered session. Across ALL 24 of
# 2026-09-19's recovery bundles it re-established `gaps_at_handoff == 0` — a fact already written on
# disk in every single one. So the common path is a conversation establishing a shell predicate.
#
# WHAT THIS SUITE IS FOR. A gate whose failure mode is "quietly says yes" is worse than no gate, so
# every case below is about the NO direction: a clause that cannot be evaluated, a field that is
# absent rather than zero, a lock that points elsewhere, a pool worktree, a state log that never
# ran. The single rc-0 case is the control — without it the other nine pass for a script that
# refuses everything.
#
# FIXTURES, NOT THE LIVE BUNDLES, AND THE REASON IS A MEASUREMENT. The spec asked for rc 0 against
# "today's five bundles". Run against all 24 live bundles (read-only mode) the script returns rc 1
# on every one, and on 10 of 24 the ONLY failing clause is A6: those bundles were cut before W2
# shipped the run state log, so none of them carries `events.jsonl` and `killed_inflight` is
# unknowable there. That is the fail-closed direction working — a bundle whose state log never ran
# degrades to the ingest it already ran — but it makes the live bundles unusable as a green fixture.
# Every fixture here is built to the shape those bundles actually have (verified field by field
# against 09e64dcb/bundle-20260919T172203Z), plus the `events.jsonl` W2 now always writes.
#
# Hermeticity:
#   * $HOME is the fixture: the script resolves the lock dir, the account map and
#     session-continue.sh from it. CLAUDE_CONFIG_DIR is passed EXPLICITLY on every run — it is
#     clause C1's own input, and an ambient one would make C1 a fact about this session.
#   * lr-audit.py and session-continue.sh are the REAL ones, copied from the worktree: clause B
#     runs the ledger and clause D runs the clear, and stubbing either would make its case
#     decorative.
#   * Both capacity gates are pinned off even though this script never probes them — a fixture that
#     reads the operator's live box for ANY reason is not a fixture.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  VERIFY="$REPO/scripts/limit-recover/lr-ingest-verify.sh"

  export CC_ADMIT_GATE=off
  export CC_FIRE_CAPACITY_GATE=off
  export CC_ADMIT_STATE_DIR="$BATS_TEST_TMPDIR/admit"
  export CC_ADMIT_IDL="$BATS_TEST_TMPDIR/admit-idl.jsonl"

  export HOME="$BATS_TEST_TMPDIR/home"
  unset CLAUDE_CONFIG_DIR CLAUDE_CODE_SESSION_ID CLAUDE_SESSION_ID WRAP_DOD_FILE WRAP_DOD_DIR
  export CONTINUE_IDL="$BATS_TEST_TMPDIR/continue-idl.jsonl"
  export CONTINUE_LOG="$BATS_TEST_TMPDIR/continue.log"

  SID="4be91f00-0000-4000-8000-00000000c0de"
  SLUG="-fixture-wt"
  SRC="$HOME/.claude-quaternary"
  TGT="$HOME/.claude-secondary"
  BUNDLE="$HOME/.reso/limit-recover/$SID/bundle-20260919T172203Z"
  WT="$BATS_TEST_TMPDIR/wt"

  mkdir -p "$HOME/.claude/scripts/limit-recover" "$HOME/.claude/hooks/lib" "$HOME/.claude/lib" \
           "$HOME/.reso/limit-recover/locks" "$BUNDLE" \
           "$TGT/projects/$SLUG" "$SRC/projects/$SLUG" "$WT"

  cp "$REPO/scripts/limit-recover/lr-audit.py"  "$HOME/.claude/scripts/limit-recover/"
  cp "$REPO/scripts/limit-recover/lr-ingest-verify.sh" "$HOME/.claude/scripts/limit-recover/"
  cp "$REPO/hooks/session-continue.sh"          "$HOME/.claude/hooks/"
  cp "$REPO"/hooks/lib/*.sh                     "$HOME/.claude/hooks/lib/" 2>/dev/null || true
  cp "$REPO/lib/account-map.generated.sh"       "$HOME/.claude/lib/"
  chmod +x "$HOME/.claude/hooks/session-continue.sh" "$HOME/.claude/scripts/limit-recover/lr-ingest-verify.sh"

  git init -q "$WT"
  git -C "$WT" config user.email t@t.t
  git -C "$WT" config user.name t
  git -C "$WT" commit -q --allow-empty -m init
  git -C "$WT" switch -q -C feat/work

  fixture_ok
}

# A bundle in the shape lr-handoff writes on the clean path: every field verified against
# 09e64dcb/bundle-20260919T172203Z, plus W2's events.jsonl.
fixture_ok() {
  jq -n --arg sid "$SID" --arg src "$SRC" --arg tgt "$TGT" --arg wt "$WT" --arg b "$BUNDLE" \
    '{sid:$sid, source_cfg:$src, target:"next2", target_cfg:$tgt, cwd:$wt, worktree:$wt,
      branch:"feat/work", head:"deadbeef1", ts:"20260919T172203Z", model:"claude-opus-5",
      task_list:"", transcript_sha256:"deadbeef", gaps_at_handoff:0,
      ingest_prompt:("/limit-recover ingest " + $b), runtime_model:"claude-opus-5",
      runtime_effort:"high", permission_mode:"auto", source_pane:"111", in_place:true}' \
    > "$BUNDLE/MANIFEST.json"

  jq -n '{counts:{workflows:0, subagents:0, gaps:0, waiting:0},
          delegations:{spawned:1, settled:1, open:0},
          last_api_error:{error:"rate_limit", status:429, kind:"session"},
          teams:{led:[{name:"t", members:[]}], other_team_dirs:[], wip_refs:[]},
          session_dir:"/nonexistent", transcript_sha256:"deadbeef"}' \
    > "$BUNDLE/audit.json"

  # W2's run state log. `admitted` is what lrh_precheck writes on the path that mints the token,
  # so a healthy post-W2 bundle always has at least this line.
  jq -cn '{ts:"2026-09-19T17:22:03Z", state:"admitted", stage:"gate", detail:"token abc"}' \
    > "$BUNDLE/events.jsonl"

  # A transcript the REAL ledger can read: no spawns, so open=0 / nonsuccess=0 / spawned==settled.
  printf '%s\n' \
    '{"type":"user","timestamp":"2026-09-19T17:00:00.000Z","message":{"role":"user","content":"go"}}' \
    '{"type":"assistant","timestamp":"2026-09-19T17:00:01.000Z","message":{"role":"assistant","content":[{"type":"text","text":"ok"}]}}' \
    > "$TGT/projects/$SLUG/$SID.jsonl"

  printf '{"handed_off_to":"%s","ts":"2026-09-19T17:22:05Z"}\n' "$TGT" > "$SRC/projects/$SLUG/$SID.HANDOFF.json"
  printf '{"sid":"%s","from":"%s","to":"%s","ts":"2026-09-19T17:22:05Z","pid":1,"host":"h"}\n' \
    "$SID" "$SRC" "$TGT" > "$HOME/.reso/limit-recover/locks/$SID.lock"

  jq -n --arg t "$TGT/projects/$SLUG/$SID.jsonl" --arg l "$HOME/.reso/limit-recover/locks/$SID.lock" \
        --arg tb "$SRC/projects/$SLUG/$SID.HANDOFF.json" \
    '{ok:true, target_transcript:$t, lock:$l, tombstone:$tb}' > "$BUNDLE/transplant.json"
}

# Run the verifier the way the launcher does: CLAUDE_CONFIG_DIR = the TARGET account.
verify() { env CLAUDE_CONFIG_DIR="$TGT" bash "$VERIFY" "$@" "$BUNDLE"; }

@test "CONTROL: a clean post-W2 bundle passes every clause and emits the one-line prompt" {
  run verify --no-clear
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" != *"FAIL"* ]] || { echo "$output"; false; }
  # the LAST line is the prompt the launcher substitutes — one line, and it names its own receipt
  last="$(printf '%s\n' "$output" | tail -1)"
  [[ "$last" == "Resumed in place on next2 — same pane, same session 4be91f00, after a session-limit 429 on next4."* ]] \
    || { echo "PROMPT: $last"; false; }
  [[ "$last" == *"INGEST-VERIFIED.txt"* ]] || { echo "$last"; false; }
  [[ "$last" == *"gaps 0, waiting 0, 0 open delegations"* ]] || { echo "$last"; false; }
  [ "$(printf '%s\n' "$output" | grep -c '^PASS ')" -eq 13 ] || { echo "$output"; false; }
}

@test "the run token from LR_SUBMIT_TOKEN is appended, and a standalone run still self-identifies" {
  run env CLAUDE_CONFIG_DIR="$TGT" LR_SUBMIT_TOKEN="run:4be91f00:20260919T172203Z:beefcafe" \
      bash "$VERIFY" --no-clear "$BUNDLE"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$(printf '%s\n' "$output" | tail -1)" == *"— run:4be91f00:20260919T172203Z:beefcafe" ]] || { echo "$output"; false; }

  run verify --no-clear     # no LR_SUBMIT_TOKEN in the environment
  [ "$status" -eq 0 ]
  [[ "$(printf '%s\n' "$output" | tail -1)" == *"— run:4be91f00:20260919T172203Z" ]] || { echo "$output"; false; }
}

@test "A6: events.jsonl carrying killed_inflight:1 REFUSES (pane 114's shape)" {
  jq -cn '{ts:"2026-09-19T17:22:04Z", state:"admitted", stage:"gate", killed_inflight:1}' \
    >> "$BUNDLE/events.jsonl"
  run verify --no-clear
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"FAIL A6 — killed_inflight=1"* ]] || { echo "$output"; false; }
  # a fail emits NO prompt line — the launcher must never be able to tail one off a refusal
  [[ "$(printf '%s\n' "$output" | tail -1)" == verdict:* ]] || { echo "$output"; false; }
}

@test "A6: an ABSENT events.jsonl is its own verdict, not an empty one" {
  # empty-vs-no-surface: `null | length` is 0 in jq, so an absent log would otherwise read as
  # "nothing was killed". The state log's absence means the precheck never ran, and that is a state
  # in which nothing here can say what the recycle interrupted.
  rm -f "$BUNDLE/events.jsonl"
  run verify --no-clear
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"FAIL A6 — no events.jsonl in the bundle"* ]] || { echo "$output"; false; }
}

@test "C5: a pool/* worktree REFUSES — a fleet slot is not the session's own tree" {
  git -C "$WT" switch -q -C pool/3
  run verify --no-clear
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"FAIL C5 — branch pool/3 is a fleet pool slot"* ]] || { echo "$output"; false; }
}

@test "A1/A2/A3: an ABSENT count is a failure, never a zero" {
  # The whole fail-closed contract in one case: three fields DELETED, not set to a nonzero value.
  jq 'del(.gaps_at_handoff)' "$BUNDLE/MANIFEST.json" > "$BUNDLE/m.tmp" && mv "$BUNDLE/m.tmp" "$BUNDLE/MANIFEST.json"
  jq 'del(.counts.waiting) | del(.delegations.open)' "$BUNDLE/audit.json" > "$BUNDLE/a.tmp" && mv "$BUNDLE/a.tmp" "$BUNDLE/audit.json"
  run verify --no-clear
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"FAIL A1 — gaps_at_handoff=ABSENT"* ]] || { echo "$output"; false; }
  [[ "$output" == *"FAIL A2 — counts.gaps=0 counts.waiting=ABSENT"* ]] || { echo "$output"; false; }
  [[ "$output" == *"FAIL A3 — delegations open=ABSENT"* ]] || { echo "$output"; false; }
}

@test "A4: a session that died on a NETWORK error, not a quota wall, REFUSES" {
  jq '.last_api_error.kind = "network"' "$BUNDLE/audit.json" > "$BUNDLE/a.tmp" && mv "$BUNDLE/a.tmp" "$BUNDLE/audit.json"
  run verify --no-clear
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL A4 — last_api_error.kind=network"* ]] || { echo "$output"; false; }
}

@test "A5: a RUNNING teammate REFUSES, and the teams object is read at its REAL shape" {
  # U12 §6.1 spelled this `.teams[].members[]?`; `.teams` is an OBJECT keyed led/other_team_dirs/
  # wip_refs, so that spelling ERRORS on every bundle on disk. This case pins the corrected path.
  jq '.teams.led[0].members = [{"verdict":"RUNNING"}]' "$BUNDLE/audit.json" > "$BUNDLE/a.tmp" && mv "$BUNDLE/a.tmp" "$BUNDLE/audit.json"
  run verify --no-clear
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL A5 — teams.led RUNNING members=1"* ]] || { echo "$output"; false; }
}

@test "C1: three-way config-dir agreement — env, manifest AND the live account map" {
  run env CLAUDE_CONFIG_DIR="$HOME/.claude-tertiary" bash "$VERIFY" --no-clear "$BUNDLE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL C1 — CLAUDE_CONFIG_DIR="*"≠ manifest target_cfg="* ]] || { echo "$output"; false; }

  # and the third leg: the manifest agrees with the env but the account map maps next2 elsewhere
  jq '.target = "next3"' "$BUNDLE/MANIFEST.json" > "$BUNDLE/m.tmp" && mv "$BUNDLE/m.tmp" "$BUNDLE/MANIFEST.json"
  run verify --no-clear
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL C1 — account map says next3 →"* ]] || { echo "$output"; false; }
}

@test "C3: a lock that names another target REFUSES (the field is .to, not .target_cfg)" {
  jq --arg t "$HOME/.claude-tertiary" '.to = $t' "$HOME/.reso/limit-recover/locks/$SID.lock" > "$BUNDLE/l.tmp" \
    && mv "$BUNDLE/l.tmp" "$HOME/.reso/limit-recover/locks/$SID.lock"
  run verify --no-clear
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL C3 — lock "*"says to="* ]] || { echo "$output"; false; }
}

@test "C4: no source tombstone REFUSES — the source may still be live" {
  rm -f "$SRC/projects/$SLUG/$SID.HANDOFF.json"
  jq 'del(.tombstone)' "$BUNDLE/transplant.json" > "$BUNDLE/t.tmp" && mv "$BUNDLE/t.tmp" "$BUNDLE/transplant.json"
  run verify --no-clear
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL C4 — no source tombstone"* ]] || { echo "$output"; false; }
}

@test "D: the clear runs from the session's OWN worktree and discharges its own sentinel" {
  env CLAUDE_CONFIG_DIR="$TGT" CLAUDE_CODE_SESSION_ID="$SID" \
    bash -c "cd '$WT' && '$HOME/.claude/hooks/session-continue.sh' set 'the pre-limit step'" >/dev/null
  run verify                      # clearing mode — the launcher's own occasion
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"PASS D1 — auto-continue cleared: cleared →"* ]] || { echo "$output"; false; }
  run env CLAUDE_CONFIG_DIR="$TGT" bash -c "cd '$WT' && '$HOME/.claude/hooks/session-continue.sh' status"
  [[ "$output" == "inactive" ]] || { echo "the sentinel survived its own session's ingest: $output"; false; }
}

@test "D: a SIBLING session's armed sentinel in the same worktree is NOT cleared" {
  # The defect this pins is not hypothetical: building this suite, a read-only sweep of the live
  # bundles ran clause D 24 times and disarmed two working sessions' continuations — one armed
  # 45 seconds earlier and driving a wave. The sentinel is keyed on (config-dir | cwd), so any
  # process in the directory clears whatever is armed there. `set` stamps the arming sid; `clear`
  # now reads it.
  env CLAUDE_CONFIG_DIR="$TGT" CLAUDE_CODE_SESSION_ID="9999ffff-0000-4000-8000-000000009999" \
    bash -c "cd '$WT' && '$HOME/.claude/hooks/session-continue.sh' set 'the SIBLING wave step'" >/dev/null
  run verify
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"PASS D1 — auto-continue cleared: refused — the sentinel armed for this cwd belongs to session 9999ffff"* ]] \
    || { echo "$output"; false; }
  run env CLAUDE_CONFIG_DIR="$TGT" bash -c "cd '$WT' && '$HOME/.claude/hooks/session-continue.sh' status"
  [[ "$output" == *"the SIBLING wave step"* ]] || { echo "THE SIBLING'S CHAIN WAS DISARMED: $output"; false; }
}

@test "--no-clear writes nothing into the sentinel store" {
  # The prompt the launcher composes advertises a re-derive command, and a re-derive that clears
  # the sentinel the session armed AFTER its ingest is a write wearing a read's clothes.
  env CLAUDE_CONFIG_DIR="$TGT" CLAUDE_CODE_SESSION_ID="$SID" \
    bash -c "cd '$WT' && '$HOME/.claude/hooks/session-continue.sh' set 'still armed'" >/dev/null
  before="$(ls -1 "$TGT/state" 2>/dev/null | sort | md5)"
  run verify --no-clear
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"PASS D1 — auto-continue NOT touched (--no-clear); sentinel reads: ARMED"* ]] || { echo "$output"; false; }
  after="$(ls -1 "$TGT/state" 2>/dev/null | sort | md5)"
  [ "$before" = "$after" ] || { echo "the read-only mode WROTE into $TGT/state"; ls -la "$TGT/state"; false; }
}

@test "the checker's own preconditions fail closed: no bundle, no MANIFEST, unparseable JSON" {
  run env CLAUDE_CONFIG_DIR="$TGT" bash "$VERIFY"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL argv"* ]] || { echo "$output"; false; }

  run env CLAUDE_CONFIG_DIR="$TGT" bash "$VERIFY" --no-clear "$BATS_TEST_TMPDIR/nowhere"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL A0 — MANIFEST.json is not readable"* ]] || { echo "$output"; false; }

  printf 'not json' > "$BUNDLE/audit.json"
  run verify --no-clear
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL A0 — audit.json is not parseable JSON"* ]] || { echo "$output"; false; }
}
