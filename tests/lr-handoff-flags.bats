#!/usr/bin/env bats
# lr-handoff.sh — THE RECONCILER INTERFACE (LIMIT_RECOVER_FLEET_V2 W2a).
#
# Subject: the flags and env the lr-reconciler drives this script with — --record-id/--attempt,
# --account-evidence, --no-prompt, LR_PLACED_BY, LR_ASSIGN_ID, LR_ADMIT_TOKEN_PATH, LR_PRESEED_DONE,
# LR_WAKE_GUARD_S — plus the git lock around the pool/* rename and the success line that must not
# claim an engagement nobody awaited. Every one is INERT when unset; the byte-identity of the legacy
# launcher is pinned by tests/lr-handoff-launcher-quoting.bats, not here.
#
# Harness: the REAL script, stubbed only at its edges (lr-audit, lr-transplant, lr-preseed-env,
# lr-fire-resume, lr-ingest-verify, handoff-fire, cc-notify, claude-accounts, sysctl), under a
# fixture $HOME. Shape copied from tests/lr-handoff-voluntary.bats and the quoting suite.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd -P)"
  HANDOFF="$REPO/scripts/limit-recover/lr-handoff.sh"

  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export TMPDIR="$BATS_TEST_TMPDIR/tmp"; mkdir -p "$TMPDIR"
  export CC_FIRE_CAPACITY_GATE=off CC_FIRE_HEADROOM_GATE=off CC_ADMIT_GATE=off
  export CC_ADMIT_STATE_DIR="$BATS_TEST_TMPDIR/admit" CC_ADMIT_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/sweep.json"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-"
  export IT2_BIN="$BATS_TEST_TMPDIR/absent-it2"
  export LRH_LIVE_PARSER_CHECK=off
  export LRH_PRECHECK=off
  export LR_STATE_DIR="$BATS_TEST_TMPDIR/state"
  unset LR_PLACED_BY LR_ASSIGN_ID LR_ADMIT_TOKEN_PATH LR_PRESEED_DONE LR_WAKE_GUARD_S LR_INPLACE_AWAIT
  unset HF_RECYCLE_ATTEMPT HF_WATCHER_RECORD CC_RECYCLE_BGWORK_ANSWER KITTY_WINDOW_ID
  export IT2_WRAPPER_NO_KITTY=1

  STUB="$BATS_TEST_TMPDIR/bin"; mkdir -p "$STUB"
  export HF_LOG="$BATS_TEST_TMPDIR/hf.log"; : > "$HF_LOG"
  export TX_LOG="$BATS_TEST_TMPDIR/tx.log"; : > "$TX_LOG"
  export PRESEED_LOG="$BATS_TEST_TMPDIR/preseed.log"; : > "$PRESEED_LOG"
  export VERIFY_LOG="$BATS_TEST_TMPDIR/verify.log"; : > "$VERIFY_LOG"
  export ACCT_LOG="$BATS_TEST_TMPDIR/accounts.log"; : > "$ACCT_LOG"
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg"; mkdir -p "$CC_REGISTRY_DIR"
  LRD="$HOME/.claude/scripts/limit-recover"
  mkdir -p "$LRD" "$HOME/.claude/projects" "$HOME/.claude-next/projects/-x-y" \
           "$HOME/.claude-secondary/projects" "$BATS_TEST_TMPDIR/plain" "$BATS_TEST_TMPDIR/ev"

  # handoff-fire: answers the probe and records every call (it does NOT parse --record-id or
  # --account-evidence, which is the live state this wave lands against).
  cat > "$STUB/handoff-fire.sh" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "${HF_LOG:?}"
printf 'BGWORK=%s ATTEMPT=%s\n' "${CC_RECYCLE_BGWORK_ANSWER:-}" "${HF_RECYCLE_ATTEMPT:-}" >> "${HF_LOG:?}"
case " $* " in
  *" --probe-recycle-preconditions "*) printf 'live_subagents: 0\nverdict: OK\n'; exit 0 ;;
esac
exit "${HF_RC:-0}"
STUB
  printf '#!/bin/bash\nexit 0\n' > "$STUB/cc-notify"
  # --print-only hands the launcher to `cursor`; unshimmed it would open the real editor
  printf '#!/bin/bash\nexit 0\n' > "$STUB/cursor"
  # claude-accounts: ranks only next3, so the router REFUSES next2 whenever it is consulted.
  cat > "$STUB/claude-accounts" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "${ACCT_LOG:?}"
printf 'next3 90\n'
STUB
  chmod +x "$STUB/"*
  export CC_HANDOFF_FIRE_BIN="$STUB/handoff-fire.sh" CC_NOTIFY_BIN="$STUB/cc-notify"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/absent-accounts"

  cat > "$LRD/lr-audit.py" <<'PY'
import sys, json, os
a = sys.argv
out = a[a.index('--json') + 1]
os.makedirs(os.path.dirname(out), exist_ok=True)
json.dump({"session_dir": "/nonexistent", "transcript_sha256": "deadbeef",
           "counts": {"gaps": 3, "waiting": 2}}, open(out, "w"))
PY
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "${PRESEED_LOG:?}"\n' > "$LRD/lr-preseed-env.sh"
  cat > "$LRD/lr-transplant.sh" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "${TX_LOG:?}"
printf '{"ok":true,"target_transcript":"/dev/null"}\n'
STUB
  # argv printer with unambiguous boundaries
  cat > "$LRD/lr-fire-resume.sh" <<'STUB'
#!/bin/bash
echo "argc=$#"
i=0; for a in "$@"; do i=$((i+1)); printf 'argv[%d]=<%s>\n' "$i" "$a"; done
STUB
  # lr-ingest-verify: VERIFY_MODE picks the receipt (rc0 | A1 | A2 | C3)
  cat > "$LRD/lr-ingest-verify.sh" <<'STUB'
#!/bin/bash
echo ran >> "${VERIFY_LOG:?}"
case "${VERIFY_MODE:-rc0}" in
  rc0) echo "PASS A1 — gaps_at_handoff=0"; echo "FAST-PATH PROMPT — $LR_SUBMIT_TOKEN"; exit 0 ;;
  A1)  echo "FAIL A1 — gaps_at_handoff=3"; echo "verdict: rc 1 (first failure: A1)"; exit 1 ;;
  A2)  echo "PASS A1 — gaps_at_handoff=0"; echo "FAIL A2 — counts.gaps=1 counts.waiting=1"; echo "verdict: rc 1 (first failure: A2)"; exit 1 ;;
  C3)  echo "PASS A1 — gaps_at_handoff=0"; echo "FAIL C3 — target transcript sha mismatch"; echo "verdict: rc 1 (first failure: C3)"; exit 1 ;;
esac
STUB
  chmod +x "$LRD/"*.sh

  export PATH="$STUB:$PATH"
  SID="0000bbbb-0000-4000-8000-00000000beef"
  printf '{"session_id":"%s"}\n' "$SID" > "$CC_REGISTRY_DIR/31.json"
  # a HEALTHY transcript on the source account: the pane is not limit-blocked
  printf '{"type":"assistant","timestamp":"2026-09-29T10:00:00.000Z","message":{"role":"assistant","content":[{"type":"text","text":"working"}]}}\n' \
    > "$HOME/.claude-next/projects/-x-y/$SID.jsonl"
}

# in-place driver form on the source account `next` (config dir .claude-next) → target next2
fire() {
  run env PATH="$STUB:$PATH" CLAUDE_CONFIG_DIR="$HOME/.claude" \
      "$HANDOFF" --sid "$SID" --target next2 --config-dir "$HOME/.claude-next" \
      --cwd "$BATS_TEST_TMPDIR/plain" --launch --in-place --source-pane 31 "$@"
}
# --print-only: mints the launcher without firing anything
gen() {
  run env PATH="$STUB:$PATH" CLAUDE_CONFIG_DIR="$HOME/.claude" \
      "$HANDOFF" --sid "$SID" --target next2 --config-dir "$HOME/.claude-next" \
      --cwd "$BATS_TEST_TMPDIR/plain" --no-transplant --print-only "$@"
}
launcher_from_output() { printf '%s\n' "$output" | sed -n 's/^lr-handoff: launch script ready (not fired): //p' | tail -1; }
bundle_launcher() { ls "$HOME/.reso/limit-recover/$SID"/bundle-*/lr-launch-*.sh 2>/dev/null | tail -1; }
# the value of the LAST argv element the stub lr-fire-resume printed
last_argv() { printf '%s\n' "$output" | grep '^argv\[' | tail -1 | sed 's/^argv\[[0-9]*\]=<//; s/>$//'; }
fact() { # $1=basename $2=json → path
  printf '%s\n' "$2" > "$BATS_TEST_TMPDIR/ev/$1"; printf '%s' "$BATS_TEST_TMPDIR/ev/$1"
}
in_s() { echo $(( $(date +%s) + $1 )); }

# ── --account-evidence ────────────────────────────────────────────────────────────────────────
@test "evidence: a valid fact admits a voluntary move of a healthy pane — the transplant is reached" {
  f="$(fact next.5h.json "{\"status\":\"rejected\",\"scope\":\"5h\",\"resets_at\":$(in_s 7200)}")"
  fire --voluntary --account-evidence "$f"
  [ "$status" -eq 0 ]
  [[ "$output" == *"voluntary move admitted on account evidence $f (5h, "* ]] || false
  [ -s "$TX_LOG" ]
}
@test "evidence: an ISO-8601 UTC resets_at is accepted" {
  iso="$(date -u -r "$(in_s 7200)" +%Y-%m-%dT%H:%M:%SZ)"
  f="$(fact next.7d.json "{\"status\":\"rejected\",\"scope\":\"7d\",\"resets_at\":\"$iso\"}")"
  fire --voluntary --account-evidence "$f"
  [ "$status" -eq 0 ]
  [ -s "$TX_LOG" ]
}
@test "evidence: a missing file refuses rc 6 evidence-invalid, NOTMOVED, nothing transplanted" {
  fire --voluntary --account-evidence "$BATS_TEST_TMPDIR/ev/next.5h.json"
  [ "$status" -eq 6 ]
  [[ "$output" == *"REFUSED:evidence-invalid — unreadable"* ]] || false
  [[ "$output" == *"verdict=NOTMOVED from=- to=next2 proven=no trigger=voluntary"* ]] || false
  [ ! -s "$TX_LOG" ]
}
@test "evidence: resets_at only 10 minutes away is expired — rc 6" {
  f="$(fact next.5h.json "{\"status\":\"rejected\",\"scope\":\"5h\",\"resets_at\":$(in_s 600)}")"
  fire --voluntary --account-evidence "$f"
  [ "$status" -eq 6 ]
  [[ "$output" == *"REFUSED:evidence-invalid — expired"* ]] || false
  [ ! -s "$TX_LOG" ]
}
@test "evidence: a contradicted fact refuses rc 6" {
  f="$(fact next.5h.json "{\"status\":\"rejected\",\"scope\":\"5h\",\"contradicted\":true,\"resets_at\":$(in_s 7200)}")"
  fire --voluntary --account-evidence "$f"
  [ "$status" -eq 6 ]
  [[ "$output" == *"REFUSED:evidence-invalid — contradicted"* ]] || false
  [ ! -s "$TX_LOG" ]
}
@test "evidence: a fact for ANOTHER account refuses rc 6" {
  f="$(fact next3.5h.json "{\"status\":\"rejected\",\"scope\":\"5h\",\"resets_at\":$(in_s 7200)}")"
  fire --voluntary --account-evidence "$f"
  [ "$status" -eq 6 ]
  [[ "$output" == *"REFUSED:evidence-invalid — account mismatch"* ]] || false
  [ ! -s "$TX_LOG" ]
}
@test "evidence CONTROL: a healthy pane with no --account-evidence is refused not-limited, as today" {
  fire --voluntary
  [ "$status" -eq 6 ]
  [[ "$output" == *"REFUSED:not-limited"* ]] || false
  [[ "$output" != *"evidence-invalid"* ]] || false
  [ ! -s "$TX_LOG" ]
}

# ── the continue prompt under LR_PLACED_BY=reconciler ─────────────────────────────────────────
CONT="[limit-recover] Moved from next to next2 after a usage limit; same session, full transcript. Continue the task you were on."
run_launcher() { # $1=VERIFY_MODE → runs the launcher minted by the last gen
  local l tok
  l="$(launcher_from_output)"; [ -n "$l" ]
  LAUNCHER="$l"
  BUNDLE="$(dirname "$l")"
  tok="$(sed -n 's/^export LR_SUBMIT_TOKEN=//p' "$l")"; TOKEN="$tok"
  run env VERIFY_MODE="$1" /bin/bash "$l"
}
@test "reconciler prompt: rc 0 → the receipt's last line, exactly" {
  LR_PLACED_BY=reconciler gen
  [ "$status" -eq 0 ]
  run_launcher rc0
  [ "$(last_argv)" = "FAST-PATH PROMPT — $TOKEN" ]
}
@test "reconciler prompt: FAIL A1 → the gaps/waiting line read from audit.json" {
  LR_PLACED_BY=reconciler gen
  run_launcher A1
  [ "$(last_argv)" = "$CONT The handoff audit found 3 gap(s) and 2 waiting agent(s); read the Gaps section of $BUNDLE/audit.md and re-run what is incomplete. — $TOKEN" ]
}
@test "reconciler prompt: FAIL A2 with an unreadable audit.json → '?' counts" {
  LR_PLACED_BY=reconciler gen
  l="$(launcher_from_output)"; rm -f "$(dirname "$l")/audit.json"
  run_launcher A2
  [ "$(last_argv)" = "$CONT The handoff audit found ? gap(s) and ? waiting agent(s); read the Gaps section of $BUNDLE/audit.md and re-run what is incomplete. — $TOKEN" ]
}
@test "reconciler prompt: any other FAIL (C3) → the audit pointer with the FAIL line" {
  LR_PLACED_BY=reconciler gen
  run_launcher C3
  [ "$(last_argv)" = "$CONT Handoff audit: $BUNDLE/audit.md (lr-ingest-verify: FAIL C3 — target transcript sha mismatch). — $TOKEN" ]
}
@test "reconciler prompt CONTROL: without LR_PLACED_BY the fallback is still /limit-recover ingest" {
  gen
  run_launcher C3
  [[ "$(last_argv)" == "/limit-recover ingest $BUNDLE — lr-ingest-verify FAILED: FAIL C3 — target transcript sha mismatch — $TOKEN" ]]
}

# ── --no-prompt ───────────────────────────────────────────────────────────────────────────────
@test "--no-prompt: the launcher passes --no-prompt, no --prompt, and never runs lr-ingest-verify" {
  gen --no-prompt
  [ "$status" -eq 0 ]
  run_launcher rc0
  [ "$status" -eq 0 ]
  [ "$(last_argv)" = "--no-prompt" ]
  [ "$(printf '%s\n' "$output" | grep -c '^argv\[[0-9]*\]=<--prompt>$')" -eq 0 ]
  [ ! -s "$VERIFY_LOG" ]
}
@test "--no-prompt: a live lr-fire-resume that does not parse it refuses rc 5 before anything moves" {
  printf '#!/bin/bash\n# --branch) --model) --effort) --permission-mode) --prompt)\n' > "$LRD/lr-fire-resume.sh"
  LRH_LIVE_PARSER_CHECK=on gen --no-prompt
  [ "$status" -eq 5 ]
  [[ "$output" == *"does not parse: --no-prompt"* ]] || false
  # CONTROL: the same live copy is not refused over --no-prompt when this run does not emit it
  LRH_LIVE_PARSER_CHECK=on gen
  [[ "$output" != *"--no-prompt"* ]]
}

# ── the success line only claims what was awaited ─────────────────────────────────────────────
@test "LR_INPLACE_AWAIT=0: the success line says engagement NOT awaited, never 'engagement verified'" {
  LR_INPLACE_AWAIT=0 fire
  [ "$status" -eq 0 ]
  [[ "$output" == *"recycled IN PLACE — /exit landed and the watcher took over; engagement NOT awaited (see handoffs.jsonl)"* ]] || false
  [[ "$output" != *"engagement verified"* ]]
}

# ── LR_PLACED_BY=reconciler ───────────────────────────────────────────────────────────────────
@test "LR_PLACED_BY=reconciler skips the router and forces CC_RECYCLE_BGWORK_ANSWER=cancel" {
  CC_ACCOUNTS_BIN="$STUB/claude-accounts" LRH_PRECHECK=on LR_PLACED_BY=reconciler \
    CC_RECYCLE_BGWORK_ANSWER=wait fire
  [ "$status" -eq 0 ]
  [[ "$output" == *"router check is skipped"* ]] || false
  [ ! -s "$ACCT_LOG" ]
  grep -q '^BGWORK=cancel ' "$HF_LOG"
}
@test "LR_PLACED_BY CONTROL: unset, the same refusing router is consulted and refuses" {
  CC_ACCOUNTS_BIN="$STUB/claude-accounts" LRH_PRECHECK=on CC_RECYCLE_BGWORK_ANSWER=wait fire
  [ "$status" -eq 6 ]
  [ -s "$ACCT_LOG" ]
  [ ! -s "$TX_LOG" ]
}
@test "CC_RECYCLE_BGWORK_ANSWER passes through untouched for a legacy caller" {
  CC_RECYCLE_BGWORK_ANSWER=wait fire
  [ "$status" -eq 0 ]
  grep -q '^BGWORK=wait ' "$HF_LOG"
}

# ── LR_ASSIGN_ID ──────────────────────────────────────────────────────────────────────────────
@test "LR_ASSIGN_ID with --target auto refuses rc 2" {
  run env PATH="$STUB:$PATH" CLAUDE_CONFIG_DIR="$HOME/.claude" LR_ASSIGN_ID=as-9 \
      "$HANDOFF" --sid "$SID" --target auto --config-dir "$HOME/.claude-next" --no-transplant --print-only
  [ "$status" -eq 2 ]
  [[ "$output" == *"a placed actuator must carry an explicit --target"* ]]
}
@test "LR_ASSIGN_ID, --record-id and --attempt land in the manifest and the run's state log" {
  LR_ASSIGN_ID=as-9 LR_PLACED_BY=reconciler fire --record-id rec-7 --attempt 2
  [ "$status" -eq 0 ]
  m="$(ls "$HOME/.reso/limit-recover/$SID"/bundle-*/MANIFEST.json | tail -1)"
  [ "$(jq -r '[.record_id,.attempt,.placed_by,.assign_id]|join(",")' "$m")" = "rec-7,2,reconciler,as-9" ]
  grep -q '"placed"' "$(dirname "$m")/events.jsonl"
  grep -q 'assign_id=as-9' "$(dirname "$m")/events.jsonl"
}
@test "manifest CONTROL: with nothing set the four fields are absent (the legacy manifest is unchanged)" {
  gen
  m="$(ls "$HOME/.reso/limit-recover/$SID"/bundle-*/MANIFEST.json | tail -1)"
  [ "$(jq -r '[has("record_id"),has("attempt"),has("placed_by"),has("assign_id")]|join(",")' "$m")" = "false,false,false,false" ]
}
@test "manifest: one field set carries all four, the unset ones empty" {
  LR_PLACED_BY=reconciler gen
  m="$(ls "$HOME/.reso/limit-recover/$SID"/bundle-*/MANIFEST.json | tail -1)"
  [ "$(jq -r '[.record_id,.attempt,.placed_by,.assign_id]|join(",")' "$m")" = ",,reconciler," ]
}

# ── --record-id ───────────────────────────────────────────────────────────────────────────────
@test "--record-id reaches lr-transplant, defaults HF_RECYCLE_ATTEMPT, and is held back from an old handoff-fire" {
  fire --record-id rec-7 --attempt 3
  [ "$status" -eq 0 ]
  grep -q -- '--record-id rec-7' "$TX_LOG"
  grep -q '^BGWORK= ATTEMPT=rec-7:3$' "$HF_LOG"
  [[ "$output" == *"does not parse --record-id"* ]] || false
  [ "$(grep -c -- '--recycle.*--record-id' "$HF_LOG")" -eq 0 ]
}

# ── LR_ADMIT_TOKEN_PATH ───────────────────────────────────────────────────────────────────────
@test "LR_ADMIT_TOKEN_PATH: the caller's token reaches the launcher and no mint runs" {
  printf '  tok-caller-42  \nsecond line\n' > "$BATS_TEST_TMPDIR/token"
  LRH_PRECHECK=on LR_ADMIT_TOKEN_PATH="$BATS_TEST_TMPDIR/token" fire
  [ "$status" -eq 0 ]
  [[ "$output" == *"admission owned by the caller: token tok-caller-42"* ]] || false
  [[ "$output" != *"precheck admitted — admission token"* ]] || false
  grep -qx 'export LR_ADMIT_TOKEN=tok-caller-42' "$(bundle_launcher)"
}
@test "LR_ADMIT_TOKEN_PATH: an empty file is no token, logged" {
  : > "$BATS_TEST_TMPDIR/token"
  LRH_PRECHECK=on LR_ADMIT_TOKEN_PATH="$BATS_TEST_TMPDIR/token" fire
  [ "$status" -eq 0 ]
  [[ "$output" == *"holds no token"* ]] || false
  grep -qx "export LR_ADMIT_TOKEN=''" "$(bundle_launcher)"
}

# ── LR_PRESEED_DONE ───────────────────────────────────────────────────────────────────────────
@test "LR_PRESEED_DONE skips lr-preseed-env; unset, it runs" {
  LR_PRESEED_DONE=1 fire
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipping lr-preseed-env.sh"* ]] || false
  [ ! -s "$PRESEED_LOG" ]
  fire
  [ -s "$PRESEED_LOG" ]
}

# ── LR_WAKE_GUARD_S ───────────────────────────────────────────────────────────────────────────
@test "LR_WAKE_GUARD_S holds a move made seconds after a wake — NOTMOVED, nothing transplanted" {
  # "5 s ago" is computed when the stub is CALLED, not when it is written: under load the run can
  # take longer than the guard window between the two, and a fixed stamp then reads as an old wake.
  printf '#!/bin/bash\necho "{ sec = $(( $(date +%%s) - 5 )), usec = 999999 } Mon Sep 29 10:00:00 2026"\n' > "$STUB/sysctl"
  chmod +x "$STUB/sysctl"
  LR_WAKE_GUARD_S=60 fire
  [ "$status" -eq 6 ]
  [[ "$output" == *"HELD:wake-guard (woke "* ]] || false
  [[ "$output" == *"verdict=NOTMOVED"* ]] || false
  [ ! -s "$TX_LOG" ]
}
@test "LR_WAKE_GUARD_S: an unreadable waketime proceeds (fail-open)" {
  printf '#!/bin/bash\nexit 1\n' > "$STUB/sysctl"; chmod +x "$STUB/sysctl"
  LR_WAKE_GUARD_S=60 fire
  [ "$status" -eq 0 ]
  [[ "$output" == *"kern.waketime unreadable; proceeding"* ]] || false
  [ -s "$TX_LOG" ]
}

# ── the git lock around the pool/* rename ─────────────────────────────────────────────────────
mkpool() { # → $POOL: a repo on branch pool/x; $LOCKDIR: its lock path
  POOL="$BATS_TEST_TMPDIR/pool"
  git init -q "$POOL"
  git -C "$POOL" config user.email t@t.t; git -C "$POOL" config user.name t
  git -C "$POOL" commit -q --allow-empty -m init
  git -C "$POOL" switch -q -C pool/x
  local c; c="$(cd "$POOL/.git" && pwd -P)"
  LOCKDIR="$LR_STATE_DIR/locks/git-$(printf '%s' "$c" | shasum -a 1 | cut -d' ' -f1)"
}
@test "git lock: a dead holder is stolen at once; the rename lands and the lock is gone" {
  mkpool
  mkdir -p "$LOCKDIR"
  printf '{"pid":999999,"lstart":"Thu Jan  1 00:00:00 1970"}\n' > "$LOCKDIR/holder"
  gen --cwd "$POOL"
  [ "$status" -eq 0 ]
  [[ "$output" == *"dead holder"* ]] || false
  [ "$(git -C "$POOL" branch --show-current)" = "recovered/${SID:0:8}" ]
  [ ! -e "$LOCKDIR" ]
}
@test "git lock: a live holder past 10s skips the rename through the WARNING path, and its lock survives" {
  mkpool
  mkdir -p "$LOCKDIR"
  ls="$(TZ=UTC LC_ALL=C ps -o lstart= -p $$ | sed 's/^ *//; s/ *$//')"
  jq -nc --argjson pid $$ --arg ls "$ls" '{pid:$pid, lstart:$ls}' > "$LOCKDIR/holder"
  gen --cwd "$POOL"
  [ "$status" -eq 0 ]
  [[ "$output" == *"held by a live process"* ]] || false
  [[ "$output" == *"WARNING — branch pool/x is pool/* and the rename"* ]] || false
  [ "$(git -C "$POOL" branch --show-current)" = "pool/x" ]
  [ -f "$LOCKDIR/holder" ]
}
