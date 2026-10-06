#!/usr/bin/env bats
# operator-readout.sh — the close's two verdicts (REPORT.md §8 item 13, operator ruling 2026-10-01).
#
#   1. The "✅ SAFE TO CLOSE" certificate is WITHHELD whenever the ledger's SCOPE is unknown (no
#      durable DoD), with the distinct abstain reason `cert-scope-unknown`. It still renders over a
#      DoD whose remainder is 0.
#   2. Research programs: one counted `◆ research <slug>: …` line per program that has pending
#      concerns or an open priced menu, read from `cc-research pending --json` under a bound.
#      Never a `▶` line — a menu item is the operator's purchase decision. Nothing renders when no
#      program is registered, and then cc-research is never called.
#
# Planted inputs: throwaway repos, a fixtured registry (CC_RESEARCH_REGISTRY) and a stub cc-research
# (CC_RESEARCH_BIN) that counts its own calls.

setup_file() {
  export HOME="$BATS_FILE_TMPDIR/home"; mkdir -p "$HOME"
}

setup() {
  export HOME="$BATS_FILE_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  READOUT="$REPO/hooks/operator-readout.sh"
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/cfg"; mkdir -p "$CLAUDE_CONFIG_DIR"
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@e.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@e.com
  export CC_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_OPREADOUT_STATE_DIR="$BATS_TEST_TMPDIR/state"
  export CC_SHARED_CHECKOUT="$BATS_TEST_TMPDIR/no-such-checkout"
  export CC_RESUME_DEBT_BIN=none
  export LR_STATE_DIR="$BATS_TEST_TMPDIR/lr" LR_RECON_ROOT="$BATS_TEST_TMPDIR/lr/recon"
  export WRAP_LEDGER_BIN="$REPO/scripts/wrap-ledger.sh"
  export WRAP_TRUNK="origin/main" WRAP_CACHE=off
  export CC_OPREADOUT_COLOR=0 CC_WAKE_FLOOR=0
  unset KITTY_WINDOW_ID WRAP_DOD_FILE WRAP_SESSION_ID CLAUDE_SESSION_ID CLAUDE_CODE_SESSION_ID
  unset CC_OPREADOUT_RESEARCH_TIMEOUT_S WRAP_RESEARCH
  export CC_RESEARCH_REGISTRY="$BATS_TEST_TMPDIR/registry/programs.json"
  export CC_RESEARCH_BIN="$BATS_TEST_TMPDIR/bin/cc-research"
  CALLS="$BATS_TEST_TMPDIR/research-calls.log"
  export CALLS
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  # default: no pending concern and no menu anywhere
  stub_pending '[]'
}

mkrepo() {
  local o="$BATS_TEST_TMPDIR/o-$1.git" w="$BATS_TEST_TMPDIR/w-$1"
  git init -q --bare "$o"; git clone -q "$o" "$w" 2>/dev/null
  ( cd "$w" || exit 1; git checkout -q -b main
    echo base > f.txt; git add -A; git commit -q -m base
    git push -q -u origin main ) >/dev/null 2>&1
  printf '%s' "$(cd "$w" && pwd -P)"
}

# a transcript whose last turn edits $2 — the write turn the certificate requires
mktr() {
  python3 - "$1" "$2" <<'PY'
import json, sys
out, p = sys.argv[1], sys.argv[2]
rows = [{"type": "user", "message": {"content": "go"}},
        {"type": "assistant", "message": {"content": [
            {"type": "tool_use", "name": "Edit", "input": {"file_path": p}}]}},
        {"type": "assistant", "message": {"content": [{"type": "text", "text": "ok"}]}}]
open(out, "w").write("\n".join(json.dumps(r) for r in rows) + "\n")
PY
  printf '%s' "$1"
}

hook() {  # hook <cwd> <transcript> → systemMessage text in $msg
  run bash -c "python3 -c 'import json,sys;print(json.dumps({\"session_id\":\"S1\",\"cwd\":sys.argv[1],\"transcript_path\":sys.argv[2]}))' '$1' '$2' | bash '$READOUT'"
  msg="$(printf '%s' "$output" | jq -r '.systemMessage // ""' 2>/dev/null)"
}

# stub_pending <programs JSON array> — `pending --json` answers it; `verdict` answers a fixed shape
stub_pending() {
  printf '%s' "$1" > "$BATS_TEST_TMPDIR/pending.json"
  cat > "$CC_RESEARCH_BIN" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$CALLS"
case "\$1" in
  pending) printf '{"programs":%s}\n' "\$(cat "$BATS_TEST_TMPDIR/pending.json")" ;;
  verdict) printf '{"program":"alpha","state":"certifying","lines":[],"pending_concerns":0,"waiting_since":null,"menu":[]}\n' ;;
  *) exit 2 ;;
esac
STUB
  chmod +x "$CC_RESEARCH_BIN"
}

plant_registry() {
  mkdir -p "$(dirname "$CC_RESEARCH_REGISTRY")"
  printf '{"programs":[{"slug":"alpha","aliases":[],"cwd_roots":["%s"],"state":"certifying"}]}\n' \
    "$BATS_TEST_TMPDIR/program-root" > "$CC_RESEARCH_REGISTRY"
}

ncalls() { if [ -f "$CALLS" ]; then grep -c . "$CALLS"; else echo 0; fi; }

PENDING2='[{"program":"alpha","state":"certifying","pending_concerns":2,"waiting_since":"2026-10-01T00:00:00Z","menu":[{"id":"m1","label":"extra round","price":"~4% weekly","effect":"x"},{"id":"m2","label":"reopen","price":"~1%","effect":"y"}]}]'

# ── 1 · the certificate is withheld on an unknown scope ──────────────────────────────────────────

@test "absent DoD + clean landed tree on a write turn renders NO certificate (cert-scope-unknown)" {
  w="$(mkrepo c1)"; tr="$(mktr "$BATS_TEST_TMPDIR/c1.jsonl" "$w/f.txt")"
  hook "$w" "$tr"
  [ "$status" -eq 0 ]
  [[ "$msg" != *"SAFE TO CLOSE"* ]] || false
  grep -q '"reason":"cert-scope-unknown"' "$CC_IDL"
}

@test "the same close with a DoD whose remainder is 0 still renders the certificate" {
  # Paired with the case above on ONE repo and ONE transcript, so the DoD is the only variable:
  # withheld first, then certified once the scope can be confirmed.
  w="$(mkrepo c2)"; tr="$(mktr "$BATS_TEST_TMPDIR/c2.jsonl" "$w/f.txt")"
  hook "$w" "$tr"
  [ "$status" -eq 0 ]
  [[ "$msg" != *"SAFE TO CLOSE"* ]] || false
  rm -f "$CC_OPREADOUT_STATE_DIR"/* 2>/dev/null || true
  printf -- '- [x] one\n' > "$BATS_TEST_TMPDIR/dod.md"
  export WRAP_DOD_FILE="$BATS_TEST_TMPDIR/dod.md"
  hook "$w" "$tr"
  [ "$status" -eq 0 ]
  [[ "$msg" == *"SAFE TO CLOSE"* ]] || false
  [[ "$msg" == *"frozen-DoD remainder 0"* ]]
}

# ── 2 · the research line ────────────────────────────────────────────────────────────────────────

@test "pending concerns render one counted ◆ research line naming the priced menu" {
  plant_registry; stub_pending "$PENDING2"
  w="$(mkrepo r1)"
  run bash "$READOUT" --render --cwd "$w"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c '^ ◆ research ')" -eq 1 ]
  printf '%s\n' "$output" | grep -qF ' ◆ research alpha: 2 pending concern(s) — menu: extra round (~4% weekly) · reopen (~1%)'
  # a menu item is the operator's purchase decision: never a run line
  [ "$(printf '%s\n' "$output" | grep -c '▶.*research')" -eq 0 ]
}

@test "an open menu with no pending concern still renders the line" {
  plant_registry
  stub_pending '[{"program":"alpha","state":"certified","pending_concerns":0,"waiting_since":null,"menu":[{"id":"m1","label":"extra round","price":"~4%","effect":"x"}]}]'
  w="$(mkrepo r2)"
  run bash "$READOUT" --render --cwd "$w"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF ' ◆ research alpha: 0 pending concern(s) — menu: extra round (~4%)'
}

@test "overridden relays alone render one counted ◆ research line, never a run line" {
  plant_registry
  stub_pending '[{"program":"alpha","state":"certified","pending_concerns":0,"waiting_since":null,"menu":[],"overridden_relays":3}]'
  w="$(mkrepo r2o)"
  run bash "$READOUT" --render --cwd "$w"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c '^ ◆ research ')" -eq 1 ]
  printf '%s\n' "$output" | grep -qF ' ◆ research alpha: 0 pending concern(s) · 3 relay(s) you overrode as misrouted   cc-research verdict alpha'
  [ "$(printf '%s\n' "$output" | grep -c '▶.*research')" -eq 0 ]
}

@test "with the overridden_relays key absent the research line is byte-for-byte the old one" {
  plant_registry; stub_pending "$PENDING2"
  w="$(mkrepo r2a)"
  run bash "$READOUT" --render --cwd "$w"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF ' ◆ research alpha: 2 pending concern(s) — menu: extra round (~4% weekly) · reopen (~1%)   cc-research verdict alpha'
  [ "$(printf '%s\n' "$output" | grep -c 'overrode')" -eq 0 ]
}

@test "with concerns and overrides both, the override clause follows the menu" {
  plant_registry
  stub_pending "$(printf '%s' "$PENDING2" | jq -c '.[0].overridden_relays = 1')"
  w="$(mkrepo r2b)"
  run bash "$READOUT" --render --cwd "$w"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c '^ ◆ research ')" -eq 1 ]
  printf '%s\n' "$output" | grep -qF ' ◆ research alpha: 2 pending concern(s) — menu: extra round (~4% weekly) · reopen (~1%) · 1 relay(s) you overrode as misrouted   cc-research verdict alpha'
  [ "$(printf '%s\n' "$output" | grep -c '▶.*research')" -eq 0 ]
}

@test "no pending concern and no menu: no research line" {
  plant_registry
  stub_pending '[{"program":"alpha","state":"certified","pending_concerns":0,"waiting_since":null,"menu":[]}]'
  w="$(mkrepo r3)"
  run bash "$READOUT" --render --cwd "$w"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c '◆ research')" -eq 0 ]
  # the absence is a READ that found nothing, not a read that never happened
  [ "$(ncalls)" -eq 1 ]
  grep -q '^pending --json' "$CALLS"
}

@test "no registered program: no research line and cc-research is never called" {
  # control first: with the registry planted the pending read happens and the line renders …
  plant_registry; stub_pending "$PENDING2"
  w="$(mkrepo r4)"
  run bash "$READOUT" --render --cwd "$w"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c '◆ research')" -eq 1 ]
  [ "$(ncalls)" -eq 1 ]
  # … then with no registry the same render makes no call at all and prints no line
  rm -f "$CC_RESEARCH_REGISTRY"
  run bash "$READOUT" --render --cwd "$w"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c '◆ research')" -eq 0 ]
  [ "$(ncalls)" -eq 1 ]
}

@test "a hanging cc-research pending read is bounded and renders nothing" {
  plant_registry
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s"\nsleep 30\n' "$CALLS" > "$CC_RESEARCH_BIN"
  chmod +x "$CC_RESEARCH_BIN"
  export CC_OPREADOUT_RESEARCH_TIMEOUT_S=1 WRAP_RESEARCH_TIMEOUT_S=1
  w="$(mkrepo r5)"
  local t0 t1; t0="$(date +%s)"
  run bash "$READOUT" --render --cwd "$w"
  t1="$(date +%s)"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c '◆ research')" -eq 0 ]
  [ $((t1 - t0)) -lt 15 ]
  # the read was attempted (and then cut off), not skipped
  grep -q '^pending --json' "$CALLS"
}

@test "write turn, absent DoD, pending research: the block shows the program line and no certificate" {
  plant_registry; stub_pending "$PENDING2"
  w="$(mkrepo h1)"; tr="$(mktr "$BATS_TEST_TMPDIR/h1.jsonl" "$w/f.txt")"
  hook "$w" "$tr"
  [ "$status" -eq 0 ]
  [[ "$msg" == *"◆ research alpha: 2 pending concern(s)"* ]] || false
  [[ "$msg" != *"SAFE TO CLOSE"* ]] || false
  [[ "$(printf '%s\n' "$msg" | head -1)" == *"completeness UNKNOWN"* ]]
}

@test "write turn, DoD met, pending research: session verdict on line 1, program line separate" {
  plant_registry; stub_pending "$PENDING2"
  printf -- '- [x] one\n' > "$BATS_TEST_TMPDIR/dod.md"
  export WRAP_DOD_FILE="$BATS_TEST_TMPDIR/dod.md"
  w="$(mkrepo h2)"; tr="$(mktr "$BATS_TEST_TMPDIR/h2.jsonl" "$w/f.txt")"
  hook "$w" "$tr"
  [ "$status" -eq 0 ]
  [[ "$(printf '%s\n' "$msg" | head -1)" == *"SAFE TO CLOSE"* ]] || false
  [[ "$(printf '%s\n' "$msg" | head -1)" != *"research"* ]] || false
  [[ "$msg" == *"◆ research alpha: 2 pending concern(s)"* ]]
}
