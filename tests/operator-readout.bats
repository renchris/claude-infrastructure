#!/usr/bin/env bats
# operator-readout.sh — Stop hook: the silver-platter close renderer. Proves:
#   · fire predicate (steps>0 ∨ 📦; silent on ✅/🔧-with-no-steps)
#   · every step source renders its EXACT runnable command (fixture-parity: fixtures are created
#     by the REAL producers — cc-decide / cc-backlog / activation-file convention — never by
#     hand-rolled JSON, per the fixture-shape-parity rule)
#   · degradation order for decisions: run_command → staged_artifact_path → prose-◆
#   · damping: change→render, unchanged+TTL→silent, TTL-elapsed→re-render
#   · pure-advisory contract: output is {systemMessage}, NEVER {decision:"block"}; exit 0 always
#   · compose-guard (continue-armed), kill-switch, cap+footer counts, B ≤24h veto summary
#   · IDL B-3: one {fired|abstained} line per hook invocation

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/operator-readout.sh"
  DECIDE="$REPO/bin/cc-decide"
  BACKLOG="$REPO/bin/cc-backlog"

  export CC_OPREADOUT_STATE_DIR="$BATS_TEST_TMPDIR/state"
  export CC_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_ACTIVATION_DIR="$BATS_TEST_TMPDIR/activation"
  export CC_DECISIONS_DIR="$BATS_TEST_TMPDIR/decisions"
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  export CC_BACKLOG_BIN="$BACKLOG"
  export WRAP_LEDGER_BIN="$REPO/scripts/wrap-ledger.sh"
  export WRAP_TRUNK="origin/main"
  # point the shared checkout at an EMPTY fixture by default → no deploy-lag step
  export CC_SHARED_CHECKOUT="$BATS_TEST_TMPDIR/no-such-checkout"
  export CC_OPREADOUT_NOW=1000000
  export CC_OPREADOUT_TTL_S=900
  mkdir -p "$CC_ACTIVATION_DIR" "$CC_DECISIONS_DIR"
  : > "$CC_BACKLOG_FILE"
}

hookrun() { # $1=cwd → run hook mode with stdin JSON; stdout in $output
  printf '{"session_id":"t-%s","cwd":"%s"}' "$BATS_TEST_NUMBER" "${1:-}" | "$HOOK"
}

# clean repo, HEAD == origin/main (landed → ✅-shaped git state)
mkrepo_landed() {
  local o="$BATS_TEST_TMPDIR/o-$1.git" w="$BATS_TEST_TMPDIR/w-$1"
  git init -q --bare "$o"; git clone -q "$o" "$w"
  ( cd "$w"; git config user.email t@e.com; git config user.name t; git checkout -q -b main
    echo base > base.txt; git add base.txt; git commit -q -m base; git push -q -u origin main ) >/dev/null 2>&1
  printf '%s' "$w"
}
# clean tree, one commit ahead (committed-but-unlanded → 📦)
mkrepo_unlanded() {
  local w; w="$(mkrepo_landed "$1")"
  ( cd "$w"; echo x > x.txt; git add x.txt; git commit -q -m "unlanded work" ) >/dev/null 2>&1
  printf '%s' "$w"
}

# ── fire predicate ────────────────────────────────────────────────────────────────────────────────

@test "no steps + landed-clean repo → silent (exit 0, no output), IDL abstain logged" {
  w="$(mkrepo_landed a)"
  run hookrun "$w"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  grep -q '"disposition":"abstained","reason":"nothing-to-surface"' "$CC_IDL"
}

@test "no steps + 📦 unlanded repo → fires with the parked state line and /ship verb" {
  w="$(mkrepo_unlanded b)"
  run hookrun "$w"
  [ "$status" -eq 0 ]
  msg="$(printf '%s' "$output" | jq -r '.systemMessage')"
  printf '%s' "$msg" | grep -q '📦 parked — 1 commit(s)'
  printf '%s' "$msg" | grep -q '→ /ship'
}

@test "pure-advisory contract: fired output carries systemMessage and NEVER decision:block" {
  w="$(mkrepo_unlanded c)"
  run hookrun "$w"
  printf '%s' "$output" | jq -e '.systemMessage' >/dev/null
  printf '%s' "$output" | jq -e 'has("decision") | not' >/dev/null
}

# ── step sources (fixture-parity: real producers) ────────────────────────────────────────────────

@test "un-run activation renders bash+touch one-liner; .done-marked and CONFIRM-gated handled" {
  printf '#!/bin/bash\necho hi\n' > "$CC_ACTIVATION_DIR/10-plain-activate.sh"
  printf '#!/bin/bash\n[ "${CONFIRM:-0}" = 1 ] || exit 0\n' > "$CC_ACTIVATION_DIR/11-gated-activate.sh"
  printf '#!/bin/bash\n' > "$CC_ACTIVATION_DIR/12-done-activate.sh"
  : > "$CC_ACTIVATION_DIR/12-done-activate.sh.done"
  run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'bash .*/10-plain-activate.sh && touch .*/10-plain-activate.sh.done   \[activation\]'
  echo "$output" | grep -q 'CONFIRM=1 bash .*/11-gated-activate.sh'
  ! echo "$output" | grep -q '12-done-activate'
}

@test "open class-C decision with staged artifact renders '▶ bash <staged>' (real cc-decide packet)" {
  "$DECIDE" open --class C --what "Wire the widget. Full detail here." \
    --staged-artifact "$BATS_TEST_TMPDIR/staged-fix.sh" >/dev/null
  run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  echo "$output" | grep -q "▶ bash $BATS_TEST_TMPDIR/staged-fix.sh   \[decision C "
  echo "$output" | grep -q 'Wire the widget'
}

@test "open class-C without command degrades to ◆ first-sentence; class-A never renders" {
  "$DECIDE" open --class C --what "Choose the reboot posture. Long tail of context that must not appear." >/dev/null
  "$DECIDE" open --class A --what "Auto-decided audit trail entry. Never operator-facing." >/dev/null
  run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  echo "$output" | grep -q '◆ \[decision C .*\] Choose the reboot posture'
  ! echo "$output" | grep -q 'Long tail of context'
  ! echo "$output" | grep -q 'audit trail entry'
}

@test "actioned/vetoed class-C packets stop rendering (status is honored)" {
  id="$("$DECIDE" open --class C --what "Transient gate. Done soon.")"
  run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  echo "$output" | grep -q 'Transient gate'
  "$DECIDE" action "$id" --evidence t >/dev/null
  run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  ! echo "$output" | grep -q 'Transient gate'
}

@test "blocked backlog item renders ◆ with its needs text (real cc-backlog producer)" {
  id="$("$BACKLOG" add --title "Rotate the API key" --project infra)"
  "$BACKLOG" block "$id" --needs "operator must mint the key in the vendor console" >/dev/null
  run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  echo "$output" | grep -q '◆ \[backlog .*\] Rotate the API key — needs: operator must mint the key'
}

@test "forward-compat: a backlog item carrying a run/run_command field renders it as ▶" {
  # main's fold whitelists fields (no run yet); feat/board-runnable-commands adds it. The
  # renderer's contract seam is `cc-backlog list --blocked --json` output — stub that binary
  # with the board branch's emission shape and prove the ▶ path is already wired.
  stub="$BATS_TEST_TMPDIR/cc-backlog-stub"
  cat > "$stub" <<'EOS'
#!/bin/bash
printf '[{"id":"abc123def456","title":"Load the dispatcher","needs":"run the loader","run":"launchctl load ~/L/dispatcher.plist","status":"blocked"}]\n'
EOS
  chmod +x "$stub"
  CC_BACKLOG_BIN="$stub" run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  echo "$output" | grep -q '▶ launchctl load ~/L/dispatcher.plist   \[backlog abc123def456: Load the dispatcher\]'
}

@test "deploy-lag: shared checkout on main behind origin/main renders the exact ff-sync command" {
  w="$(mkrepo_landed d)"
  ( cd "$w"; echo z > z.txt; git add z.txt; git commit -q -m more; git push -q origin main
    git reset -q --hard HEAD~1 ) >/dev/null 2>&1   # local main now 1 behind its origin/main
  export CC_SHARED_CHECKOUT="$w"
  run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  echo "$output" | grep -q "▶ git -C $w pull --ff-only   \[deploy: live layer 1 behind origin/main\]"
}

@test "class-B is never itemized; ≤24h deadline appears only as the veto summary line" {
  "$DECIDE" open --class B --what "Imminent default. Detail." \
    --default "proceed" --deadline "2026-07-20T12:00:00Z" >/dev/null
  "$DECIDE" open --class B --what "Far-future default. Detail." \
    --default "proceed" --deadline "2099-01-01T00:00:00Z" >/dev/null
  printf '#!/bin/bash\n' > "$CC_ACTIVATION_DIR/13-x-activate.sh"   # ensure the block fires
  CC_OPREADOUT_NOW=1784894400 run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"                  # 2026-07-23T12:00:00Z epoch-ish
  ! echo "$output" | grep -q 'Imminent default'
  ! echo "$output" | grep -q 'Far-future default'
  echo "$output" | grep -q '1 class-B default(s) auto-fire ≤24h (earliest 2026-07-20T12:00:00Z) — veto: cc-decide veto <id>'
}

# ── composition: cap, counts, header ─────────────────────────────────────────────────────────────

@test "cap: >MAX steps → numbered MAX, footer counts the overflow and the total is in the header" {
  for i in 1 2 3; do printf '#!/bin/bash\n' > "$CC_ACTIVATION_DIR/2$i-s-activate.sh"; done
  CC_OPREADOUT_MAX=2 run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  echo "$output" | grep -q 'OPERATOR ▸ 3 manual step(s)'
  echo "$output" | grep -q ' 2 ▶ '
  ! echo "$output" | grep -q ' 3 ▶ '
  echo "$output" | grep -q '+1 more'
}

@test "state line: dirty repo renders 🔧 with the uncommitted-file fact" {
  w="$(mkrepo_landed e)"; echo dirt > "$w/dirt.txt"
  printf '#!/bin/bash\n' > "$CC_ACTIVATION_DIR/14-y-activate.sh"
  run "$HOOK" --render --cwd "$w"
  echo "$output" | grep -q '🔧 in progress — 1 file(s) uncommitted'
}

# ── damping ──────────────────────────────────────────────────────────────────────────────────────

@test "damping: unchanged within TTL → abstain latched-ttl; after TTL → re-fires; change → immediate" {
  printf '#!/bin/bash\n' > "$CC_ACTIVATION_DIR/15-z-activate.sh"
  w="$(mkrepo_landed f)"
  CC_OPREADOUT_NOW=1000000 hookrun "$w" | jq -e '.systemMessage' >/dev/null
  out2="$(CC_OPREADOUT_NOW=1000100 hookrun "$w")"
  [ -z "$out2" ]
  grep -q '"reason":"latched-ttl:100s<900s"' "$CC_IDL"
  out3="$(CC_OPREADOUT_NOW=1001000 hookrun "$w")"
  printf '%s' "$out3" | jq -e '.systemMessage' >/dev/null
  # a NEW step re-renders immediately even inside the TTL window
  printf '#!/bin/bash\n' > "$CC_ACTIVATION_DIR/16-new-activate.sh"
  out4="$(CC_OPREADOUT_NOW=1001010 hookrun "$w")"
  printf '%s' "$out4" | jq -r '.systemMessage' | grep -q '16-new-activate'
}

# ── guards ───────────────────────────────────────────────────────────────────────────────────────

@test "kill-switch CC_OPREADOUT_DISABLE=1 → silent abstain" {
  printf '#!/bin/bash\n' > "$CC_ACTIVATION_DIR/17-k-activate.sh"
  out="$(printf '{"session_id":"k","cwd":""}' | CC_OPREADOUT_DISABLE=1 "$HOOK")"
  [ -z "$out" ]
  grep -q '"reason":"disabled"' "$CC_IDL"
}

@test "compose-guard: armed continue sentinel → abstain continue-armed (session-continue owns the turn)" {
  printf '#!/bin/bash\n' > "$CC_ACTIVATION_DIR/18-c-activate.sh"
  w="$(mkrepo_landed g)"
  sent="$BATS_TEST_TMPDIR/armed-sentinel"; : > "$sent"
  out="$(printf '{"session_id":"cg","cwd":"%s"}' "$w" | CC_CONTINUE_SENTINEL="$sent" "$HOOK")"
  [ -z "$out" ]
  grep -q '"reason":"continue-armed"' "$CC_IDL"
}

@test "malformed decision JSON is skipped, never crashes the render (fail-open per file)" {
  printf 'NOT JSON{{{' > "$CC_DECISIONS_DIR/broken.json"
  "$DECIDE" open --class C --what "Still renders. Yes." >/dev/null
  run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'Still renders'
}

@test "--render with nothing pending prints the explicit none-line (pull surface never silent)" {
  run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
  [ "$output" = "OPERATOR ▸ no manual steps pending." ]
}
