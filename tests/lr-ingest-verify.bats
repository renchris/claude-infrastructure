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
  export CC_FIRE_HEADROOM_GATE=off
  # …and the three seams that reach the operator's LIVE box rather than a gate: the account sweep
  # stamp, the accounts binary and the self-heal lock prefix. Each is pointed at a path that does
  # not exist under $BATS_TEST_TMPDIR, because a fixture that reads the desk's mood for ANY reason
  # is not a fixture — and an absent path is the only value that cannot be satisfied by accident.
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/absent-sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/absent-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/absent-heal-"
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

  # `notifications` is ALWAYS emitted by lr-audit.py (:2306) and the fixture omitted it, so B1's
  # baseline read as an ABSENT container over a bundle that in production always has one — a fixture
  # unfaithful on exactly the axis clause B1 was being changed on.
  jq -n '{counts:{workflows:0, subagents:0, gaps:0, waiting:0},
          delegations:{spawned:1, settled:1, open:0, notifications:{}},
          last_api_error:{error:"rate_limit", status:429, kind:"session"},
          teams:{led:[{name:"t", members:[]}], other_team_dirs:[], wip_refs:[]},
          session_dir:"/nonexistent", transcript_sha256:"deadbeef"}' \
    > "$BUNDLE/audit.json"

  # W2's run state log. `admitted` is what lrh_precheck writes on the path that mints the token, so
  # a healthy post-W2 bundle always has at least this line — and the line must STATE the value A6
  # reads. This fixture used to carry only `detail:"token abc"`, i.e. the present-but-SILENT shape,
  # which is what pinned A6's fail-open: silence read as zero, and the CONTROL certified it.
  jq -cn '{ts:"2026-09-19T17:22:03Z", state:"admitted", stage:"gate",
           detail:"token abc killed_inflight=0", killed_inflight:0}' \
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

# Arm a continuation sentinel in $WT, keyed on config dir $1, as session $2, with step $3.
# The KEY is the whole point of clause D: the sentinel the pre-limit session armed is keyed on the
# config dir it was running under — the SOURCE account's — and the recovered session reads a
# different key entirely under the target's.
sc_arm() { env CLAUDE_CONFIG_DIR="$1" CLAUDE_CODE_SESSION_ID="$2" \
  bash -c "cd '$WT' && '$HOME/.claude/hooks/session-continue.sh' set '$3'" >/dev/null; }
# What `status` reads at that same key.
sc_stat() { env CLAUDE_CONFIG_DIR="$1" \
  bash -c "cd '$WT' && '$HOME/.claude/hooks/session-continue.sh' status"; }

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
  # The verdict names its own count; asserting the two agree pins the pair without putting a third
  # copy of the number in the suite (W3i: the literal 13 survived a 14th clause landing).
  n="$(printf '%s\n' "$output" | grep -c '^PASS ')"
  [[ "$output" == *"verdict: rc 0 ($n clauses PASS)"* ]] || { echo "PASS lines=$n but: $output"; false; }
  [ "$n" -ge 14 ] || { echo "only $n clauses ran: $output"; false; }
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

@test "D1: the PRE-LIMIT sentinel is keyed on the SOURCE config dir, and that is the one D clears" {
  # THE DEFECT THIS PINS (W3i D1). The sentinel is keyed on (config-dir | cwd), and the config dir
  # that keyed the pre-limit arm is the account the session was running under WHEN IT ARMED — the
  # SOURCE. Clause D used to run its clear under the TARGET, where this session has never run: it
  # could not reach the sentinel it exists for, and the only sentinel at that key belongs to
  # somebody else. Nothing is armed under the target here, so the target key is empty and only the
  # source-side clear can produce a "cleared".
  sc_arm "$SRC" "$SID" "the pre-limit step"
  run verify                      # clearing mode — the launcher's own occasion
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"PASS D1 — pre-limit auto-continue CLEARED under $SRC"* ]] || { echo "$output"; false; }
  run sc_stat "$SRC"
  [[ "$output" == "inactive" ]] || { echo "the pre-limit sentinel survived the ingest: $output"; false; }
}

@test "D1: an ABSENT source_cfg FAILS — a 'cleared' over a guessed directory is the false claim" {
  jq 'del(.source_cfg)' "$BUNDLE/MANIFEST.json" > "$BUNDLE/m.tmp" && mv "$BUNDLE/m.tmp" "$BUNDLE/MANIFEST.json"
  run verify
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"FAIL D1 — the manifest records no source_cfg"* ]] || { echo "$output"; false; }
}

@test "D2: this session's OWN stale sentinel at the TARGET key is cleared, and named as its own" {
  # The one case where the target key legitimately carries something of ours — a second recovery
  # back onto an account this session has run under before.
  sc_arm "$TGT" "$SID" "a stale target-side step"
  run verify
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"PASS D2 — this session's OWN stale sentinel at the target key was cleared"* ]] \
    || { echo "$output"; false; }
  run sc_stat "$TGT"
  [[ "$output" == "inactive" ]] || { echo "our own stale sentinel survived: $output"; false; }
}

@test "D2: a SIBLING armed at the TARGET key REFUSES the fast path, and is NOT touched" {
  # The defect this pins is not hypothetical: building this suite, a read-only sweep of the live
  # bundles ran clause D 24 times and disarmed two working sessions' continuations — one armed
  # 45 seconds earlier and driving a wave. Two things must hold, and they are separate facts: the
  # sibling's chain SURVIVES (the steal is gone), and the gate REFUSES (a live sibling armed in the
  # very cwd this session is about to resume into is a state the fast path must not license — the
  # recovered session's own first Stop would clear-and-ignore it, silently).
  sc_arm "$TGT" "9999ffff-0000-4000-8000-000000009999" "the SIBLING wave step"
  run verify
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"FAIL D2 — session 9999ffff-0000-4000-8000-000000009999 has an armed continuation"* ]] \
    || { echo "$output"; false; }
  run sc_stat "$TGT"
  [[ "$output" == *"the SIBLING wave step"* ]] || { echo "THE SIBLING'S CHAIN WAS DISARMED: $output"; false; }
}

@test "D1: a SIBLING armed at the SOURCE key is left alone, and D1 says NOTHING WAS CLEARED" {
  # The source-side twin of the case above. Here the refusal comes from session-continue's own
  # ownership guard, and the receipt must report the refusal as a refusal — see the D7 case below.
  sc_arm "$SRC" "9999ffff-0000-4000-8000-000000009999" "the SIBLING wave step"
  run verify
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"PASS D1 — NOTHING WAS CLEARED"* ]] || { echo "$output"; false; }
  run sc_stat "$SRC"
  [[ "$output" == *"the SIBLING wave step"* ]] || { echo "THE SIBLING'S CHAIN WAS DISARMED: $output"; false; }
}

@test "--no-clear writes nothing into EITHER sentinel store" {
  # The prompt the launcher composes advertises a re-derive command, and a re-derive that clears
  # the sentinel the session armed AFTER its ingest is a write wearing a read's clothes. Both keys
  # are armed here, because --no-clear has to hold on BOTH sides: D1's source-side clear and D2's
  # own-sentinel clear are two separate writes.
  sc_arm "$SRC" "$SID" "still armed at the source key"
  sc_arm "$TGT" "$SID" "still armed at the target key"
  before_s="$(ls -1 "$SRC/state" 2>/dev/null | sort | /usr/bin/shasum)"
  before_t="$(ls -1 "$TGT/state" 2>/dev/null | sort | /usr/bin/shasum)"
  run verify --no-clear
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  # The --no-clear branch now CLASSIFIES what it read instead of blanket-reporting it (W3i C4), so
  # the line names whose sentinel is armed at the source key as well as that it was left alone.
  [[ "$output" == *"PASS D1 — this session's own pre-limit sentinel is armed at"* ]] || { echo "$output"; false; }
  [[ "$output" == *"NOT touched (--no-clear)"* ]] || { echo "$output"; false; }
  [[ "$output" == *"PASS D2 — this session's own sentinel is armed at the target key, NOT touched"* ]] \
    || { echo "$output"; false; }
  [ "$before_s" = "$(ls -1 "$SRC/state" 2>/dev/null | sort | /usr/bin/shasum)" ] \
    || { echo "the read-only mode WROTE into $SRC/state"; ls -la "$SRC/state"; false; }
  [ "$before_t" = "$(ls -1 "$TGT/state" 2>/dev/null | sort | /usr/bin/shasum)" ] \
    || { echo "the read-only mode WROTE into $TGT/state"; ls -la "$TGT/state"; false; }
  run sc_stat "$SRC"
  [[ "$output" == *"still armed at the source key"* ]] || { echo "the source sentinel was disarmed: $output"; false; }
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

@test "D7: the receipt and the composed prompt never claim a clear that did not happen" {
  # A label that contradicts its own value is how a false claim survives review. Measured on the
  # unmodified tree, the receipt read
  #   PASS D1 — auto-continue cleared: refused — the sentinel armed for this cwd belongs to session
  #   9999ffff (you are 4be91f00); nothing was cleared: <cwd>
  # and the PROMPT THE RECOVERED SESSION READS asserted "auto-continue cleared" unconditionally.
  # Both are read off the outcome now.
  sc_arm "$SRC" "9999ffff-0000-4000-8000-000000009999" "the SIBLING wave step"
  run verify
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" != *"D1 — auto-continue cleared: refused"* ]] || { echo "the label still contradicts its value: $output"; false; }
  last="$(printf '%s\n' "$output" | tail -1)"
  [[ "$last" != *"auto-continue cleared"* ]] || { echo "the PROMPT claims a clear that did not happen: $last"; false; }
  # The check list in the prompt is now ACCUMULATED at the clause calls (W3i C6), so D1's own
  # outcome rides in as its subject rather than as a hand-written trailing clause.
  [[ "$last" == *"pre-limit auto-continue: left to its owner"* ]] || { echo "the prompt does not say what actually happened: $last"; false; }
}

@test "A6: a PRESENT but SILENT events.jsonl REFUSES — silence is not zero" {
  # W3i D2, and the fail-open that mattered most: nothing in the tree writes killed_inflight yet, so
  # once W2's state log is being written, present-and-silent is the shape of EVERY bundle. The old
  # `-1 ⇒ PASS` arm would have cleared all of them while having measured nothing — and this suite's
  # own CONTROL fixture was built to that shape, so it pinned the fail-open rather than catching it.
  jq -cn '{ts:"2026-09-19T17:22:03Z", state:"admitted", stage:"gate", detail:"token abc"}' \
    > "$BUNDLE/events.jsonl"
  run verify --no-clear
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"FAIL A6 — events.jsonl carries no killed_inflight record"* ]] || { echo "$output"; false; }
}

@test "C5: a NON-GIT worktree the manifest says WAS a repo is unevaluable, and fails" {
  # W3i D5. `rev-parse --git-dir` returns one rc for "not a repo" and for "git could not answer",
  # and passing on it contradicts this file's own contract. The manifest's `.branch` is the second
  # source that separates the two.
  rm -rf "$WT/.git"
  run verify --no-clear
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"FAIL C5 — the manifest recorded branch feat/work but git cannot read"* ]] || { echo "$output"; false; }
}

@test "C5 CONTROL: a non-git worktree the manifest ALSO calls branchless passes — the two agree" {
  # Without this, the case above is satisfiable by a C5 that refuses every non-repo, and the
  # legitimate non-git cwd — lr-handoff emits no --branch for one — would take the expensive ingest
  # forever. This is the arm that keeps the fix from being a blanket refusal.
  rm -rf "$WT/.git"
  jq 'del(.branch)' "$BUNDLE/MANIFEST.json" > "$BUNDLE/m.tmp" && mv "$BUNDLE/m.tmp" "$BUNDLE/MANIFEST.json"
  run verify --no-clear
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"PASS C5 — $WT is not a git repo and the manifest recorded no branch"* ]] || { echo "$output"; false; }
}

# ══ ONE CASE PER SURVIVING MUTANT (W3i M1-M8) ════════════════════════════════════════════════════
# An adversarial pass built 37 mutants of this gate and 11 SURVIVED a fully green suite. A clause
# with no case that dies on its mutation is decorative: it can be deleted, inverted or forced true
# and every run still reads `ok`. Each case below is named for the arm it kills.

@test "M1: B1 refuses a re-audit that finds an OPEN delegation" {
  # B1's whole point: the bundle's audit is a SNAPSHOT, and B1 re-derives the ledger from the
  # transcript the recovered session is about to resume. Until now B1 had NO failing arm at all, so
  # its predicate could be replaced by `true` with the suite green.
  printf '%s\n' \
    '{"type":"user","timestamp":"2026-09-19T17:00:00.000Z","message":{"role":"user","content":"go"}}' \
    '{"type":"assistant","timestamp":"2026-09-19T17:00:01.000Z","message":{"role":"assistant","content":[{"type":"tool_use","id":"tu_open_1","name":"Agent","input":{"description":"a delegation nobody settled"}}]}}' \
    > "$TGT/projects/$SLUG/$SID.jsonl"
  run verify --no-clear
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"FAIL B1 — re-audit open=1"* ]] || { echo "$output"; false; }
}

@test "M2: B1 fails CLOSED when the target transcript cannot be read" {
  # The unevaluable arm: transplant.json names a transcript that is not there and the glob finds
  # none either, so the ledger cannot be re-derived — a FAILURE, never a pass.
  rm -f "$TGT/projects/$SLUG/$SID.jsonl"
  jq --arg t "$BATS_TEST_TMPDIR/gone.jsonl" '.target_transcript = $t' "$BUNDLE/transplant.json" \
    > "$BUNDLE/t.tmp" && mv "$BUNDLE/t.tmp" "$BUNDLE/transplant.json"
  run verify --no-clear
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"FAIL B1 — no readable target transcript"* ]] || { echo "$output"; false; }
}

@test "M3: C2 refuses BOTH counts it is written for — zero copies and two" {
  # A count clause needs both failing arms, or either side of the comparison can be replaced by
  # `true` and nothing notices. 0 and 2 are the two directions.
  mv "$TGT/projects/$SLUG/$SID.jsonl" "$BATS_TEST_TMPDIR/held.jsonl"
  run verify --no-clear
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"FAIL C2 — no transcript $SID"* ]] || { echo "$output"; false; }

  mkdir -p "$TGT/projects/-second-copy"
  cp "$BATS_TEST_TMPDIR/held.jsonl" "$TGT/projects/$SLUG/$SID.jsonl"
  cp "$BATS_TEST_TMPDIR/held.jsonl" "$TGT/projects/-second-copy/$SID.jsonl"
  run verify --no-clear
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"FAIL C2 — 2 copies of $SID"* ]] || { echo "$output"; false; }
}

@test "M4: C5 refuses a DETACHED HEAD — there is no branch to check against pool/*" {
  git -C "$WT" checkout -q --detach
  run verify --no-clear
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"FAIL C5 — $WT is on a detached HEAD"* ]] || { echo "$output"; false; }
}

@test "M5: C1 refuses an UNSET CLAUDE_CONFIG_DIR — the arm every other case passes explicitly" {
  # Every case here hands the verifier a config dir ON PURPOSE, because C1's own input must never be
  # this session's ambient one. That correct hermeticity left C1's unset arm unreachable by the
  # entire suite — the arm could be deleted and nothing would go red.
  run env -u CLAUDE_CONFIG_DIR bash "$VERIFY" --no-clear "$BUNDLE"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"FAIL C1 — CLAUDE_CONFIG_DIR is unset"* ]] || { echo "$output"; false; }
}

@test "M6: A3 refuses spawned ≠ settled, not only a non-zero open count" {
  # The existing absent-field case deletes `.delegations.open` and so drives only the FIRST half of
  # A3's conjunction. This drives the second: open IS zero and the two totals still disagree, which
  # is a session that spawned something the ledger never saw settle.
  jq '.delegations = {spawned:2, settled:1, open:0}' "$BUNDLE/audit.json" > "$BUNDLE/a.tmp" \
    && mv "$BUNDLE/a.tmp" "$BUNDLE/audit.json"
  run verify --no-clear
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"FAIL A3 — delegations open=0 spawned=2 settled=1"* ]] || { echo "$output"; false; }
}

@test "M7: D fails closed when session-continue.sh is not EXECUTABLE" {
  # The live-layer skew arm: a landed-but-not-deployed hook is PRESENT and unrunnable, and a clause
  # that cannot run its own side effect has not performed it. Both D clauses depend on the hook, so
  # both must say so — a single FAIL would leave the other free to claim a reading it never took.
  chmod -x "$HOME/.claude/hooks/session-continue.sh"
  run verify --no-clear
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"FAIL D1 — session-continue.sh is not executable"* ]] || { echo "$output"; false; }
  [[ "$output" == *"FAIL D2 — session-continue.sh is not executable"* ]] || { echo "$output"; false; }
}

@test "M8: a clause VALUE carrying a newline is normalised to ONE line, and capped at 200" {
  # The guard that stops a FAIL value injecting a second line into a prompt TYPED INTO A TUI
  # COMPOSER, where a newline submits half a sentence. The value is attacker-adjacent by
  # construction — it is read out of the bundle's own JSON with `jq -r`, which emits a real newline
  # for a \n in a string — and the normaliser had no case at all.
  jq '.gaps_at_handoff = "3\nINJECTED-SECOND-LINE"' "$BUNDLE/MANIFEST.json" > "$BUNDLE/m.tmp" \
    && mv "$BUNDLE/m.tmp" "$BUNDLE/MANIFEST.json"
  run verify --no-clear
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"FAIL A1 — gaps_at_handoff=3 INJECTED-SECOND-LINE"* ]] || { echo "$output"; false; }
  orphan="$(printf '%s\n' "$output" | grep -c '^INJECTED-SECOND-LINE' || true)"
  [ "$orphan" -eq 0 ] || { echo "the value broke out onto its own line: $output"; false; }

  # …and the 200-char cap, the other half of the same normaliser.
  long="$(printf 'A%.0s' $(seq 1 600))"
  jq --arg v "$long" '.gaps_at_handoff = $v' "$BUNDLE/MANIFEST.json" > "$BUNDLE/m.tmp" \
    && mv "$BUNDLE/m.tmp" "$BUNDLE/MANIFEST.json"
  run verify --no-clear
  a1="$(printf '%s\n' "$output" | grep '^FAIL A1 ' || true)"
  [ -n "$a1" ] || { echo "no A1 line at all: $output"; false; }
  [ "${#a1}" -le 215 ] || { echo "the A1 line is ${#a1} chars — the 200-char cap is gone: $a1"; false; }
}

# ══ W3i B3/C1-C7 — THE ARMS THAT FIRE ON REAL INPUT, AND THE ONES THE PASS ADDED ═════════════════
# A read-only sweep of all 69 bundles under ~/.reso/limit-recover returned rc=1 on 69 of 69. Each
# case below is either an arm that fired on those real bundles with no case at all (D's rc-97 pair
# fired on 10 of 69), or an arm this hardening pass itself ADDED — a new guard with no mutant that
# kills it is untested surface added at the same rate the old surface was pinned.

# A transcript carrying ONE spawn whose only terminal word is a FAILED task-notification:
# spawned=1, settled=1 (a terminal notification settles), open=0, nonsuccess=1.
tx_one_failed_delegation() { # $1=tool_use_id
  printf '%s\n' \
    '{"type":"user","timestamp":"2026-09-19T17:00:00.000Z","message":{"role":"user","content":"go"}}' \
    "{\"type\":\"assistant\",\"timestamp\":\"2026-09-19T17:00:01.000Z\",\"message\":{\"role\":\"assistant\",\"content\":[{\"type\":\"tool_use\",\"id\":\"$1\",\"name\":\"Agent\",\"input\":{\"description\":\"a delegation that failed\"}}]}}" \
    "{\"type\":\"user\",\"timestamp\":\"2026-09-19T17:05:00.000Z\",\"message\":{\"role\":\"user\",\"content\":\"<task-notification><task-id>t1</task-id><tool-use-id>$1</tool-use-id><status>failed</status></task-notification>\"}}" \
    > "$TGT/projects/$SLUG/$SID.jsonl"
}

@test "B1: a nonsuccess notification the BUNDLE already recorded is not a change" {
  # THE MEASUREMENT THAT MOTIVATED THIS. B1's own heading is "nothing changed under us since the
  # bundle was cut", and it asked `nonsuccess == 0` — an ABSOLUTE test over a re-derivation of the
  # WHOLE transcript, so every delegation the session ever failed counted against a recovery that
  # had changed nothing. Over the 33 current-schema bundles on disk B1 failed 19, `open=0` and
  # `spawned==settled` in every one, so nonsuccess was the sole discriminator — while the bundle's
  # own audit already held the same ids (a99681dc 8 and 8, 4101dbdf 1 and 1, c0f857b6 1 and 1).
  tx_one_failed_delegation tu_ns_1
  jq '.delegations.notifications = {"tu_ns_1":{"status":"failed","task_id":"t1"}}' "$BUNDLE/audit.json" \
    > "$BUNDLE/a.tmp" && mv "$BUNDLE/a.tmp" "$BUNDLE/audit.json"
  run verify --no-clear
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"PASS B1 — re-audit open=0"* ]] || { echo "$output"; false; }
  [[ "$output" == *"no NEW nonsuccess notification since the bundle (1 already recorded in its audit)"* ]] \
    || { echo "$output"; false; }
}

@test "B1: a nonsuccess notification the bundle did NOT record IS a change, and refuses" {
  # The other half, and what keeps the clause a gate rather than a formality: a delegation that
  # failed BETWEEN the handoff and the relaunch is exactly an id absent from the bundle's baseline.
  tx_one_failed_delegation tu_ns_2
  run verify --no-clear
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"FAIL B1 — re-audit open=0 NEW-nonsuccess=1 (of 1 total)"* ]] || { echo "$output"; false; }
}

@test "B1: a bundle with NO notifications baseline is unevaluable, not zero — but only when there is something to compare" {
  # The absent-container arm (empty-vs-no-surface). An audit that predates the `delegations` field
  # carries no baseline at all: with a nonsuccess to judge, that is unevaluable and fails; with none,
  # nothing needs a baseline and the clause clears.
  tx_one_failed_delegation tu_ns_3
  jq 'del(.delegations)' "$BUNDLE/audit.json" > "$BUNDLE/a.tmp" && mv "$BUNDLE/a.tmp" "$BUNDLE/audit.json"
  run verify --no-clear
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"FAIL B1 — re-audit open=0 NEW-nonsuccess=NO-BASELINE"* ]] || { echo "$output"; false; }

  fixture_ok                                  # restore, then take the baseline away with no nonsuccess
  jq 'del(.delegations)' "$BUNDLE/audit.json" > "$BUNDLE/a.tmp" && mv "$BUNDLE/a.tmp" "$BUNDLE/audit.json"
  run verify --no-clear
  [[ "$output" == *"PASS B1 —"* ]] || { echo "an absent baseline refused a re-audit with nothing to compare: $output"; false; }
}

@test "GITPATH: C5 with NO git on PATH is a FAILURE, not the not-a-repo pass" {
  # W3i C2. C5's `command -v git` arm was decorative: deleting it leaves `git -C … rev-parse`
  # exiting 127, which falls into the not-a-repo branch, and a manifest with no branch then PASSES —
  # a gate clearing a question it could not ask. PATH is rebuilt from scratch so the absence is real
  # rather than shadowed by a later directory that still holds git.
  stub="$BATS_TEST_TMPDIR/nogit"; mkdir -p "$stub"
  for t in bash sh env jq python3 sed cut tr date cat ls rm mkdir chmod shasum grep awk head tail sort wc dirname basename printf; do
    real="$(command -v "$t" 2>/dev/null)" || continue
    [ -n "$real" ] || continue
    ln -sf "$real" "$stub/$t"
  done
  [ ! -e "$stub/git" ] || { echo "the stub PATH still carries git"; false; }
  jq 'del(.branch)' "$BUNDLE/MANIFEST.json" > "$BUNDLE/m.tmp" && mv "$BUNDLE/m.tmp" "$BUNDLE/MANIFEST.json"
  run env PATH="$stub" CLAUDE_CONFIG_DIR="$TGT" bash "$VERIFY" --no-clear "$BUNDLE"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"FAIL C5 — git is not on PATH"* ]] || { echo "$output"; false; }
  [[ "$output" != *"PASS C5"* ]] || { echo "C5 passed over a question it could not ask: $output"; false; }
}

@test "C5: a manifest with NEITHER worktree nor cwd says so, instead of naming an empty path" {
  # 4 of the 69 live bundles printed "worktree  does not exist" — a sentence with a hole where its
  # subject belongs, because `[ ! -d "" ]` renders "empty" and "missing" identically.
  jq 'del(.worktree) | del(.cwd)' "$BUNDLE/MANIFEST.json" > "$BUNDLE/m.tmp" && mv "$BUNDLE/m.tmp" "$BUNDLE/MANIFEST.json"
  run verify --no-clear
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"FAIL C5 — the manifest records neither worktree nor cwd"* ]] || { echo "$output"; false; }
}

@test "D1RC/D2RC: a worktree that no longer exists names the CAUSE, not an exit code" {
  # W3i C7. These two arms fired on 10 of the 69 live bundles — every one whose worktree has since
  # been removed — and printed `session-continue.sh status under <dir> exited 97: ` with an empty
  # tail: an exit code where a cause belongs, from a number this script produces itself (its own
  # `cd` guard), not one the hook ever returned.
  gone="$BATS_TEST_TMPDIR/worktree-that-was-reaped"
  jq --arg w "$gone" '.worktree = $w | .cwd = $w' "$BUNDLE/MANIFEST.json" \
    > "$BUNDLE/m.tmp" && mv "$BUNDLE/m.tmp" "$BUNDLE/MANIFEST.json"
  run verify --no-clear
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"FAIL D1 — the worktree $gone no longer exists"* ]] || { echo "$output"; false; }
  [[ "$output" == *"FAIL D2 — the worktree $gone no longer exists"* ]] || { echo "$output"; false; }
  [[ "$output" != *"exited 97"* ]] || { echo "the bare exit code is back: $output"; false; }
}

@test "D2NOCFG: an ABSENT target_cfg is its own D2 failure, not a key read from nothing" {
  jq 'del(.target_cfg)' "$BUNDLE/MANIFEST.json" > "$BUNDLE/m.tmp" && mv "$BUNDLE/m.tmp" "$BUNDLE/MANIFEST.json"
  run verify --no-clear
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"FAIL D2 — the manifest records no target_cfg"* ]] || { echo "$output"; false; }
}

@test "D1UNCLASS/D2UNCLASS: a hook line neither clause can classify fails CLOSED on both" {
  # The `*)` arms. A session-continue that answers something this gate has no rule for is a contract
  # change, and the only safe reading of an answer you cannot parse is "I do not know".
  cat > "$HOME/.claude/hooks/session-continue.sh" <<'SH'
#!/bin/bash
echo "banana"
exit 0
SH
  chmod +x "$HOME/.claude/hooks/session-continue.sh"
  run verify --no-clear
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"FAIL D1 — session-continue.sh status"*"returned an outcome this gate cannot classify: banana"* ]] \
    || { echo "$output"; false; }
  [[ "$output" == *"FAIL D2 — session-continue.sh status"*"returned an unclassifiable line: banana"* ]] \
    || { echo "$output"; false; }
}

@test "D2: an anonymously armed sentinel at the target key refuses, and is not called 'session ?'" {
  # W3i C3, the D6 defect one layer down. `status` rendered the no-sid state `sid=?`, so D2 printed
  # "session ? has an armed continuation" — a sentence about a session that does not exist. The
  # VERDICT was always right (unknown ownership is not consent); the sentence invented a subject.
  env CLAUDE_CONFIG_DIR="$TGT" bash -c "cd '$WT' && '$HOME/.claude/hooks/session-continue.sh' set 'an anonymous park'" >/dev/null
  run verify --no-clear
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"FAIL D2 — an armer that recorded NO sid has a continuation"* ]] || { echo "$output"; false; }
  [[ "$output" != *"session ? has"* ]] || { echo "the invented session is back: $output"; false; }
  [[ "$output" != *"session unrecorded has"* ]] || { echo "the token leaked into the sentence: $output"; false; }
}

@test "C4: when source_cfg == target_cfg, D1 takes D2's verdict instead of contradicting it" {
  # W3i C4. D1 and D2 used to take OPPOSITE verdicts on ONE state: a foreign sentinel at the source
  # key read `PASS D1 — NOTHING WAS CLEARED` while the identical state at the target key read
  # `FAIL D2`. When the two config dirs are equal those are THE SAME FILE — measured on 1 of the 69
  # live bundles — so the contradiction is not hypothetical. The rule is one (never clear what this
  # session did not arm); the VERDICT is a property of the key, and this key is the one the
  # recovered session's own Stop hook will read.
  jq --arg t "$TGT" '.source_cfg = $t' "$BUNDLE/MANIFEST.json" > "$BUNDLE/m.tmp" && mv "$BUNDLE/m.tmp" "$BUNDLE/MANIFEST.json"
  sc_arm "$TGT" "9999ffff-0000-4000-8000-000000009999" "the SIBLING wave step"
  run verify --no-clear
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"FAIL D1 — source_cfg == target_cfg, so this IS the key the recovered session reads"* ]] \
    || { echo "$output"; false; }
  [[ "$output" == *"FAIL D2 — session 9999ffff-0000-4000-8000-000000009999 has an armed continuation"* ]] \
    || { echo "$output"; false; }
}

@test "C4 CONTROL: a DIFFERENT source key still passes D1 while D2 refuses the target key" {
  # The arm that keeps the case above from being a blanket refusal. The transplant moves the session
  # to $TCFG and its Stop resolves the sentinel there, so a stranger armed at the SOURCE key is a
  # key the recovered session can never read — nothing of ours, and no risk of ours.
  sc_arm "$SRC" "9999ffff-0000-4000-8000-000000009999" "a sibling on the source account"
  run verify --no-clear
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"PASS D1 — NOTHING WAS CLEARED"* ]] || { echo "$output"; false; }
  [[ "$output" == *"the source key is NOT the key the recovered session reads"* ]] || { echo "$output"; false; }
  [[ "$output" == *"PASS D2 — nothing armed at the key the recovered session reads"* ]] || { echo "$output"; false; }
}

@test "C6: the prompt's check list is the clauses that PASSED, never a hand-written one" {
  # W3i C6. The list used to be a literal — "(config dir, session id, transcript path, lock target,
  # source tombstone, branch; …)" — and it had already drifted: "session id" is no clause of this
  # gate, and NONE of the six A clauses that decide whether anything is owed appeared at all. It is
  # accumulated at the clause calls now, which is the only place that knows a clause ran.
  run verify --no-clear
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  last="$(printf '%s\n' "$output" | tail -1)"
  for subj in "nothing owed at handoff" "every delegation settled" "died on a quota wall" \
              "the recycle interrupted nothing" "config dir" "lock target" "branch"; do
    [[ "$last" == *"$subj"* ]] || { echo "the check list does not name '$subj': $last"; false; }
  done
  [[ "$last" != *"session id"* ]] || { echo "the stale hand-written entry is back: $last"; false; }
  # …and a clause that did NOT run contributes nothing: drop A5's container and its subject goes.
  jq 'del(.teams)' "$BUNDLE/audit.json" > "$BUNDLE/a.tmp" && mv "$BUNDLE/a.tmp" "$BUNDLE/audit.json"
  run verify --no-clear
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" != *"no running teammate"* ]] || { echo "a FAILED clause still described itself in the list: $output"; false; }
}
