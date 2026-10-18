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
  *" --probe-recycle-preconditions "*) printf 'live_subagents: 0\n%s' "${PROBE_EXTRA:-}"; printf 'verdict: OK\n'; exit 0 ;;
esac
[ -n "${TOMB_CHECK:-}" ] && [ -e "$TOMB_CHECK" ] && echo "tombstone-present-at-fire" >> "${HF_LOG:?}"
if [ -n "${HF_HELD_CLASS:-}" ]; then
  mkdir -p "$HOME/.claude/logs"
  printf '{"ts":"%s","class":"%s","target_pane":"31"}\n' "$(date -u +%FT%TZ)" "$HF_HELD_CLASS" >> "$HOME/.claude/logs/handoffs.jsonl"
fi
[ -n "${HF_ERR:-}" ] && printf '%s\n' "$HF_ERR" >&2
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
echo "pair=<${LR_RECORD_ID:-}|${LR_ATTEMPT:-}>"
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
last_match() { # $@=a glob's expansion → the last existing path (the shell sorts a glob as ls does)
  local f last=""
  for f in "$@"; do [ -e "$f" ] && last="$f"; done
  printf '%s' "$last"
}
bundle_launcher() { last_match "$HOME/.reso/limit-recover/$SID"/bundle-*/lr-launch-*.sh; }
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
@test "evidence: a live auth fact (no resets_at) admits a voluntary move — the TARGET-AUTH hop" {
  f="$(fact next.auth.json '{"acct":"next","scope":"auth","status":"rejected","resets_at":null}')"
  fire --voluntary --account-evidence "$f"
  [ "$status" -eq 0 ]
  [[ "$output" == *"voluntary move admitted on account evidence $f (auth, -)"* ]] || false
}
@test "evidence: a contradicted auth fact refuses rc 6" {
  f="$(fact next.auth.json '{"acct":"next","scope":"auth","status":"rejected","contradicted":true}')"
  fire --voluntary --account-evidence "$f"
  [ "$status" -eq 6 ]
  [[ "$output" == *"REFUSED:evidence-invalid"*"contradicted=true"* ]] || false
}
@test "evidence: an auth fact whose resets_at has passed (+60 s grace) is expired — rc 6" {
  f="$(fact next.auth.json "{\"acct\":\"next\",\"scope\":\"auth\",\"status\":\"rejected\",\"resets_at\":$(in_s -120)}")"
  fire --voluntary --account-evidence "$f"
  [ "$status" -eq 6 ]
  [[ "$output" == *"REFUSED:evidence-invalid"*"expired"* ]] || false
  [ ! -s "$TX_LOG" ]
}
@test "evidence: an auth fact without --voluntary admits nothing (not-limited, as today)" {
  f="$(fact next.auth.json '{"acct":"next","scope":"auth","status":"rejected"}')"
  fire --account-evidence "$f"
  [[ "$output" != *"voluntary move admitted"* ]] || false
}
@test "evidence: the precheck probe gets --voluntary beside --account-evidence (W5 B2)" {
  # a live handoff-fire that parses the flag (lr-handoff greps for the case label)
  printf '# --account-evidence) parsed\n' >> "$STUB/handoff-fire.sh"
  f="$(fact next.5h.json "{\"status\":\"rejected\",\"scope\":\"5h\",\"resets_at\":$(in_s 7200)}")"
  LRH_PRECHECK=on fire --voluntary --account-evidence "$f"
  line="$(grep -- '--probe-recycle-preconditions' "$HF_LOG" | head -1)"
  [[ "$line" == *"--account-evidence $f"* ]] || false
  [[ "$line" == *"--voluntary"* ]] || false
}
@test "evidence: the precheck probe CONTROL — no evidence, no --voluntary added" {
  printf '# --account-evidence) parsed\n' >> "$STUB/handoff-fire.sh"
  LRH_PRECHECK=on fire
  line="$(grep -- '--probe-recycle-preconditions' "$HF_LOG" | head -1)"
  [ -n "$line" ]
  [[ "$line" != *"--voluntary"* ]] || false
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
@test "reconciler prompt: the reconciler's LR_RECON_SUBMIT_TOKEN is the token typed (W5 rig)" {
  LR_PLACED_BY=reconciler LR_RECON_SUBMIT_TOKEN=lrr-0123456789ab gen
  run_launcher rc0
  [ "$TOKEN" = "lrr-0123456789ab" ]
  [ "$(last_argv)" = "FAST-PATH PROMPT — lrr-0123456789ab" ]
}
@test "reconciler launcher: record id and attempt reach lr-fire-resume call-scoped, never exported (W5 rig)" {
  LR_PLACED_BY=reconciler gen --record-id rec-7 --attempt 2
  [ "$status" -eq 0 ]
  l="$(launcher_from_output)"; [ -n "$l" ]
  grep -q '^exec env LR_RECORD_ID="${LR_RECORD_ID:-rec-7}" LR_ATTEMPT="${LR_ATTEMPT:-2}" .*lr-fire-resume.sh' "$l"
  ! grep -q '^export LR_RECORD_ID\|^export LR_ATTEMPT' "$l"
}
@test "reconciler launcher: the actor that TYPES it owns the pair; a bare run gets the minted one (W5b canary 3)" {
  LR_PLACED_BY=reconciler gen --record-id rec-7 --attempt 2
  l="$(launcher_from_output)"; [ -n "$l" ]
  run env -u LR_RECORD_ID -u LR_ATTEMPT VERIFY_MODE=rc0 /bin/bash "$l"
  [[ "$output" == *"pair=<rec-7|2>"* ]] || { echo "$output"; false; }
  # the reconciler's in-place rescue (B) re-types this launcher under a NEW attempt after taking the
  # launch lock as that attempt: lr-fire-resume must see the new one, or it refuses its own rescuer
  run env LR_RECORD_ID=rec-7 LR_ATTEMPT=5 VERIFY_MODE=rc0 /bin/bash "$l"
  [[ "$output" == *"pair=<rec-7|5>"* ]] || { echo "$output"; false; }
}
@test "reconciler launcher: a record id that is not a plain token keeps the pinned, quoted form" {
  LR_PLACED_BY=reconciler gen --record-id 'rec 7;x' --attempt 2
  l="$(launcher_from_output)"; [ -n "$l" ]
  grep -q '^exec env LR_RECORD_ID=rec\\ 7\\;x LR_ATTEMPT=2 ' "$l"
}
@test "reconciler launcher CONTROL: no --record-id, no env prefix" {
  LR_PLACED_BY=reconciler gen
  l="$(launcher_from_output)"; [ -n "$l" ]
  ! grep -q 'LR_RECORD_ID' "$l"
}
@test "reconciler token CONTROL: without LR_PLACED_BY=reconciler an incoming token is ignored" {
  LR_RECON_SUBMIT_TOKEN=lrr-0123456789ab gen
  run_launcher rc0
  [[ "$TOKEN" == run:* ]]
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

# ── a recycle held after the confirm and UNDONE is not a strand (W5 rig, draft-after-confirm) ─────
ABORT='!! recycle ABORTED before /exit (held: draft): composer: operator draft typed after confirm — /exit NOT submitted, watcher disarmed, pane lock released, unconfirm rc 0. The session stays alive. Re-run: x'
@test "a recycle held after the confirm with unconfirm rc 0 is NOTMOVED HELD:draft, rc 6, never STRANDED" {
  HF_RC=1 HF_ERR="$ABORT" fire
  [ "$status" -eq 6 ] || { echo "status=$status $output"; false; }
  [[ "$output" == *"verdict: HELD:draft"* ]] || { echo "$output"; false; }
  [[ "$output" == *"verdict=NOTMOVED"* ]] || { echo "$output"; false; }
  [[ "$output" != *"verdict=STRANDED"* ]] || { echo "$output"; false; }
}
@test "a SLOW tee still yields the hold verdict: the greps wait for the tee to drain, never read an empty file" {
  # The tee runs in a process substitution, which the recycle call does not wait for. A tee that
  # starts 2 s late reproduces, every time, what load did intermittently to the case above.
  printf '#!/bin/bash\n/bin/sleep 2\nexec /usr/bin/tee "$@"\n' > "$STUB/tee"; chmod +x "$STUB/tee"
  HF_RC=1 HF_ERR="$ABORT" fire
  [ "$status" -eq 6 ] || { echo "status=$status $output"; false; }
  [[ "$output" == *"verdict: HELD:draft"* ]] || { echo "$output"; false; }
  [[ "$output" != *"verdict=STRANDED"* ]] || { echo "$output"; false; }
}
# hf_recycle_hold's exit-readback form, held AFTER /exit was typed, says so instead of "ABORTED before
# /exit" (recycle-failures-kitty REPORT.md fix 2); keyed on the old literal alone it fell to STRANDED.
READBACK_HELD="!! recycle HELD after /exit was TYPED (held: exit-readback): the composer read back '<unreadable>', not '/exit' — no DELs sent: the composer could not be read, so the /exit we typed MAY STILL BE IN THE BOX — clear it before typing; residue receipt /r/31 lets the next recycle's composer gate scrub it — the /exit was NOT submitted (no Enter sent), watcher disarmed, pane lock released, unconfirm rc 0. The session stays alive. Re-run: x"
@test "the exit-readback hold form (HELD after /exit was TYPED) is NOTMOVED HELD:exit-readback, rc 6, never STRANDED" {
  HF_RC=1 HF_ERR="$READBACK_HELD" fire
  [ "$status" -eq 6 ] || { echo "status=$status $output"; false; }
  [[ "$output" == *"verdict: HELD:exit-readback"* ]] || { echo "$output"; false; }
  [[ "$output" != *"verdict=STRANDED"* ]] || { echo "$output"; false; }
}
@test "the SIGTERM hold form (HELD after SIGTERM) is NOTMOVED HELD:exit-signal-ignored, rc 6, never STRANDED" {
  HF_RC=1 HF_ERR="!! recycle HELD after SIGTERM (held: exit-signal-ignored): claude pid 4242 is still running 30s after SIGTERM; no KILL was sent and nothing was typed, so the session is alive — watcher disarmed, pane lock released, unconfirm rc 0. Re-run: x" fire
  [ "$status" -eq 6 ] || { echo "status=$status $output"; false; }
  [[ "$output" == *"verdict: HELD:exit-signal-ignored"* ]] || { echo "$output"; false; }
  [[ "$output" != *"verdict=STRANDED"* ]] || { echo "$output"; false; }
}
@test "CONTROL: held but the unconfirm FAILED (rc 2) is still STRANDED, rc 4" {
  # a refused unconfirm leaves the confirm's retirement in place: the source IS retired
  : > "$HOME/.claude-next/projects/-x-y/$SID.jsonl.handed-off"
  HF_RC=1 HF_ERR="${ABORT/unconfirm rc 0/unconfirm rc 2}" fire
  [ "$status" -eq 4 ] || { echo "status=$status $output"; false; }
  [[ "$output" == *"verdict=STRANDED"* ]] || { echo "$output"; false; }
  [[ "$output" != *"verdict=NOTMOVED"* ]] || { echo "$output"; false; }
}

# ── D7.1 (FLEET_V2 W6): a recycle that stands down BEFORE any confirm is not a strand ──────────────
# In-place mode runs only `--phase admit`; five handoff-fire exits leave the source unretired. Each
# must abort the admit — tombstone and lock really gone (the REAL lr-transplant runs here) — and read
# NOTMOVED HELD:<reason>, rc 6. The reason is handoff-fire's own recycle-held-* row, else `unknown`.
# Mutant: drop the `elif ! lrh_source_retired` arm — every row goes STRANDED, rc 4.
D71_CASES=(
  "recycle-held-focused|focused|!! recycle DEFERRED: pane 31 is FOCUSED — the operator may be typing into it. Nothing typed, no watcher armed, the session stays alive."
  "recycle-held-draft|draft|!! recycle DEFERRED: pane 31 is focused and its composer did not read EMPTY twice 10s apart ('x'). Nothing typed, no watcher armed."
  "recycle-held-draft|draft|!! recycle REFUSED after 180s: pane 31's composer holds unsubmitted text ('x') — Nothing was typed; the session stays alive."
  "-|unknown|!! recycle ABORTED: watcher heartbeat never appeared (log) — /exit NOT typed, session stays alive. Run manually: x"
  "-|unknown|!! recycle ABORTED: the watcher cannot write pane 31 (see log) — /exit NOT typed, session stays alive. Run manually: x"
  "recycle-held-draft|draft|!! recycle ABORTED at the last read: composer became non-empty ('x') between arming and /exit — nothing typed, watcher disarmed, session stays alive. Re-run: x"
  "recycle-held-busy|busy|!! recycle ABORTED at the last read: session 0000bbbb is no longer at rest (rc 1 — 1 a turn is in flight, 2 unreadable) — nothing typed, watcher disarmed, session untouched. Re-run once it is idle."
)
@test "D7.1 every pre-confirm exit of the recycle aborts the admit: tombstone and lock gone, NOTMOVED HELD:<reason>, rc 6" {
  cp "$REPO/scripts/limit-recover/lr-transplant.sh" "$LRD/lr-transplant.sh"; chmod +x "$LRD/lr-transplant.sh"
  local c cls reason err tomb="$HOME/.claude-next/projects/-x-y/$SID.HANDOFF.json" lock="$LR_STATE_DIR/locks/$SID.lock"
  for c in "${D71_CASES[@]}"; do
    cls="${c%%|*}"; reason="${c#*|}"; reason="${reason%%|*}"; err="${c#*|*|}"
    [ "$cls" = - ] && cls=""
    : > "$HF_LOG"
    TOMB_CHECK="$tomb" HF_HELD_CLASS="$cls" HF_RC=1 HF_ERR="$err" fire
    [ "$status" -eq 6 ] || { echo "[$reason] status=$status $output"; false; }
    grep -q '^tombstone-present-at-fire$' "$HF_LOG" || { echo "[$reason] the admit never tombstoned"; cat "$HF_LOG"; false; }
    [[ "$output" == *"verdict: HELD:$reason"* ]] || { echo "[$reason] $output"; false; }
    [[ "$output" == *"verdict=NOTMOVED"* ]] || { echo "[$reason] $output"; false; }
    [[ "$output" != *"verdict=STRANDED"* ]] || { echo "[$reason] $output"; false; }
    [ ! -e "$tomb" ] || { echo "[$reason] tombstone still there"; false; }
    [ ! -e "$lock" ] || { echo "[$reason] lock still there"; false; }
    [ -f "$HOME/.claude-next/projects/-x-y/$SID.jsonl" ] || { echo "[$reason] the source transcript is gone"; false; }
  done
}
@test "D7.1 CONTROL: an abort lr-transplant refuses is FAILED rc 4, and names the retry" {
  cat > "$LRD/lr-transplant.sh" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "${TX_LOG:?}"
case " $* " in *" --phase abort "*) echo '{"ok":false,"reason":"target-held"}'; exit 2 ;; esac
printf '{"ok":true,"target_transcript":"/dev/null"}\n'
STUB
  chmod +x "$LRD/lr-transplant.sh"
  HF_RC=1 HF_ERR="!! recycle ABORTED: watcher heartbeat never appeared (log) — /exit NOT typed" fire
  [ "$status" -eq 4 ] || { echo "status=$status $output"; false; }
  [[ "$output" == *"verdict=FAILED"* ]] || { echo "$output"; false; }
  [[ "$output" == *"abort refused (rc 2"* ]] || { echo "$output"; false; }
  [[ "$output" != *"verdict=STRANDED"* ]] || { echo "$output"; false; }
  grep -q -- '--phase abort --sid '"$SID"' ' "$TX_LOG" || { cat "$TX_LOG"; false; }
}

# D7.5 (FLEET_V2 W6): the probe's focus and operator-idle lines land in the run's own state log on every
# dispatch, before the LR_MOVE_FOCUSED flip. Mutant: drop the `lrh_state probed focus` row.
@test "D7.5 the probe's focused: and hid_idle_s: lines become a state row; a probe without them says unread" {
  LRH_PRECHECK=on PROBE_EXTRA=$'focused: yes\nhid_idle_s: 12\n' fire
  [ "$status" -eq 0 ] || { echo "status=$status $output"; false; }
  local ev
  ev="$(last_match "$HOME/.reso/limit-recover/$SID"/bundle-*/events.jsonl)"
  [ -n "$ev" ] || { find "$HOME/.reso" 2>&1 | head; false; }
  grep -q '"stage":"focus","detail":"focused=yes hid_idle_s=12 verdict=OK"' "$ev" || { cat "$ev"; false; }
  LRH_PRECHECK=on fire
  ev="$(last_match "$HOME/.reso/limit-recover/$SID"/bundle-*/events.jsonl)"
  grep -q '"detail":"focused=unread hid_idle_s=unread verdict=OK"' "$ev" || { cat "$ev"; false; }
}

# ── LR_PLACED_BY=reconciler ───────────────────────────────────────────────────────────────────
@test "LR_PLACED_BY=reconciler skips the router and forces CC_RECYCLE_BGWORK_ANSWER=cancel" {
  CC_ACCOUNTS_BIN="$STUB/claude-accounts" LRH_PRECHECK=on LR_PLACED_BY=reconciler \
    CC_RECYCLE_BGWORK_ANSWER="wait" fire
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
  CC_RECYCLE_BGWORK_ANSWER="wait" fire
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
@test "--target auto asks the router with thin-account promotion OFF (the pick records no claim)" {
  # docs/research/dispatch-strand-rescue-2026-10-09.md: a promoted thin account is budgeted for one
  # fire, and only handoff-fire's --assign writes the claim that caps a second one. An env prefix is
  # invisible in argv, so the stub records the variable as this call saw it.
  mkdir -p "$HOME/bin"
  printf '#!/bin/bash\nprintf "%%s FIRST=%%s\\n" "$*" "${CC_ROUTE_DISPATCH_STRAND_FIRST-UNSET}" >> "%s/route.log"\necho next3\n' \
    "$BATS_TEST_TMPDIR" > "$HOME/bin/claude-accounts"
  chmod +x "$HOME/bin/claude-accounts"
  run env PATH="$STUB:$PATH" CLAUDE_CONFIG_DIR="$HOME/.claude" \
      "$HANDOFF" --sid "$SID" --target auto --config-dir "$HOME/.claude-next" --no-transplant --print-only
  grep -q '^--route general FIRST=off$' "$BATS_TEST_TMPDIR/route.log" || { cat "$BATS_TEST_TMPDIR/route.log"; false; }
}
@test "LR_ASSIGN_ID, --record-id and --attempt land in the manifest and the run's state log" {
  LR_ASSIGN_ID=as-9 LR_PLACED_BY=reconciler fire --record-id rec-7 --attempt 2
  [ "$status" -eq 0 ]
  m="$(last_match "$HOME/.reso/limit-recover/$SID"/bundle-*/MANIFEST.json)"
  [ "$(jq -r '[.record_id,.attempt,.placed_by,.assign_id]|join(",")' "$m")" = "rec-7,2,reconciler,as-9" ]
  grep -q '"placed"' "$(dirname "$m")/events.jsonl"
  grep -q 'assign_id=as-9' "$(dirname "$m")/events.jsonl"
}
@test "manifest CONTROL: with nothing set the four fields are absent (the legacy manifest is unchanged)" {
  gen
  m="$(last_match "$HOME/.reso/limit-recover/$SID"/bundle-*/MANIFEST.json)"
  [ "$(jq -r '[has("record_id"),has("attempt"),has("placed_by"),has("assign_id")]|join(",")' "$m")" = "false,false,false,false" ]
}
@test "manifest: one field set carries all four, the unset ones empty" {
  LR_PLACED_BY=reconciler gen
  m="$(last_match "$HOME/.reso/limit-recover/$SID"/bundle-*/MANIFEST.json)"
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
@test "LR_ADMIT_TOKEN_PATH: a REAL minted token IS the token — the pane redeems it (basis token) and in-flight drops to 0" {
  # The reconciler hands over the path cc_capacity_token_mint PRINTS (lr_recon/admit.py), and the
  # file at that path is the token record itself. The old fixture wrote a made-up string into the
  # file, so the defect — reading line 1 of the record as if it held a path — passed for weeks
  # (docs/research/lr-wake-incident-2026-10-18/c2 §2.4: 12+ `token ABSENT (<record>)` IDL rows).
  CA="$REPO/scripts/lib/capacity-admit.sh"
  tok="$(bash -c '. "$1" && cc_capacity_token_mint "$2"' _ "$CA" "$SID")"
  [ -f "$tok" ]
  [ "$(bash -c '. "$1" && cc_capacity_tokens_inflight' _ "$CA")" = 1 ]
  LRH_PRECHECK=on LR_ADMIT_TOKEN_PATH="$tok" fire
  [ "$status" -eq 0 ]
  [[ "$output" == *"admission owned by the caller: token $tok"* ]] || false
  [[ "$output" != *"precheck admitted — admission token"* ]] || false
  grep -qx "export LR_ADMIT_TOKEN=$(printf '%q' "$tok")" "$(bundle_launcher)"
  # the pane's redeem, exactly as lr-fire-resume.sh calls it
  ltok="$(sed -n 's/^export LR_ADMIT_TOKEN=//p' "$(bundle_launcher)")"
  run env -u CC_ADMIT_GATE bash -c '. "$1" && CC_ADMIT_TOKEN="$2" CC_ADMIT_WANT_SID="$3" cc_capacity_admit lr-fire-resume "resume $3"' \
    _ "$CA" "$ltok" "$SID"
  [ "$status" -eq 0 ]
  [ "$(jq -r 'select(.caller=="lr-fire-resume") | .basis' "$CC_ADMIT_IDL" | tail -n 1)" = token ]
  [ "$(bash -c '. "$1" && cc_capacity_tokens_inflight' _ "$CA")" = 0 ]
}
@test "LR_ADMIT_TOKEN_PATH: a file that is NOT a token record still yields its first line (the legacy pointer form)" {
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

# ── K3 (lr-inplace-immediacy 2026-10-18): the in-place precheck says its relaunch will be TYPED ───────
# Later moves transplanted and THEN held HELD:load at the /exit. The probe can hold on load before the
# transplant only if it is told the relaunch is typed; the probe's own side is pinned in
# tests/handoff-recycle-kitty-precheck.bats (K3). RED on the unfixed tree: nothing set the env, so this
# stub answered OK and the move transplanted.
@test "K3 the in-place precheck tells the probe its relaunch is typed; HELD:load is PRECHECK, rc 6, nothing transplanted" {
  cat > "$STUB/handoff-fire.sh" <<'STUB'
#!/bin/bash
printf '%s TYPED=%s\n' "$*" "${HF_PRECHECK_TYPED_RELAUNCH:-}" >> "${HF_LOG:?}"
case " $* " in
  *" --probe-recycle-preconditions "*)
    if [ "${HF_PRECHECK_TYPED_RELAUNCH:-}" = 1 ]; then
      echo "load: 30/core is above the 8/core bound, and this move types its relaunch"; echo "verdict: HELD:load"; exit 3
    fi
    echo "verdict: OK"; exit 0 ;;
esac
exit 0
STUB
  LRH_PRECHECK=on fire
  [ "$status" -eq 6 ] || { echo "status=$status $output"; false; }
  grep -q -- '--probe-recycle-preconditions .* TYPED=1$' "$HF_LOG" || { cat "$HF_LOG"; false; }
  [[ "$output" == *"PRECHECK HELD:load — NOTHING has been transplanted"* ]] || { echo "$output"; false; }
  [ ! -s "$TX_LOG" ] || { cat "$TX_LOG"; false; }
  # The move worker names the hold from this output with this extraction (lr-move-worker.sh, `held=`).
  held="$(printf '%s\n' "$output" | sed -n 's/.*\(HELD:[A-Za-z:-]*\).*/\1/p; s/.*\(REFUSED:[A-Za-z:-]*\).*/\1/p' | tail -1)"
  [ "$held" = HELD:load ] || { echo "the worker would read '$held'"; false; }
}
