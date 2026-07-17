#!/bin/bash
# shellcheck disable=SC2015  # the `<check> && ok || bad` reporter idiom is intentional — ok/bad always return 0
# reaper-e2e.sh — REAL end-to-end acceptance for the autonomous reaper. Reproduces an orphaned
# handed-off lead on REAL infra (a throwaway iTerm2 window + a real victim process + a live successor
# + a real git repo) and proves cc-reaper: (A) reaps it — closing the REAL pane, confirmed by
# re-enumeration; (B) with UNCOMMITTED work, checkpoints FIRST then ABORTS (never loses/kills WIP).
# Blast radius is bounded to the throwaway window by a FIXTURED registry (cc-teardown can only resolve
# the one pane we created). Guaranteed cleanup via trap. NO real session is ever touched.
#
#   scripts/reaper-e2e.sh        # runs both scenarios, prints PASS/FAIL, cleans up

set -uo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
IT2="$HOME/.claude/bin/it2"
LABEL="ccreaper_e2e_$$"
D="$(mktemp -d "${TMPDIR:-/tmp}/reaper-e2e.XXXXXX")"
PANE=""; VICTIM_PID=""; SUCC_PID=""
PASS=0; FAIL=0
ok(){ printf '  ✅ %s\n' "$1"; PASS=$((PASS+1)); }
bad(){ printf '  ⛔ %s\n' "$1"; FAIL=$((FAIL+1)); }

cleanup() {
  [ -n "$PANE" ] && "$IT2" session close -f -s "$PANE" >/dev/null 2>&1 || true
  pkill -f "$LABEL" 2>/dev/null || true
  [ -n "$SUCC_PID" ] && kill "$SUCC_PID" 2>/dev/null || true
  rm -rf "$D" 2>/dev/null || true
}
trap cleanup EXIT

pane_present() { "$IT2" session list --json 2>/dev/null | jq -e --arg u "$1" 'any(.[]; .id==$u)' >/dev/null 2>&1; }

echo "reaper-e2e — REAL orphan reproduction + reap (throwaway window; fixtured registry; trap cleanup)"

# ── fixtures: a clean+shipped git repo (the lead's cwd) ─────────────────────────────────────────
REPO="$D/repo"; mkdir -p "$REPO"
git -C "$REPO" init -q; git -C "$REPO" config user.email t@t; git -C "$REPO" config user.name t
echo a > "$REPO/f"; git -C "$REPO" add f; git -C "$REPO" commit -qm c1
git -C "$REPO" update-ref refs/remotes/origin/main HEAD
git -C "$REPO" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main

# ── the throwaway pane = the "orphaned lead" ────────────────────────────────────────────────────
BEFORE="$("$IT2" session list --json 2>/dev/null | jq -r '.[].id' | sort)"
"$IT2" window new >/dev/null 2>&1; sleep 1
AFTER="$("$IT2" session list --json 2>/dev/null | jq -r '.[].id' | sort)"
PANE="$(comm -13 <(echo "$BEFORE") <(echo "$AFTER") | head -1)"
[ -n "$PANE" ] || { echo "FATAL: could not create a throwaway window"; exit 1; }
"$IT2" session run -s "$PANE" "exec -a $LABEL sleep 3000" >/dev/null 2>&1; sleep 1
VICTIM_PID="$(pgrep -f "$LABEL" | head -1)"
[ -n "$VICTIM_PID" ] || { echo "FATAL: victim process did not start"; exit 1; }

# ── the live successor (a real process in the SAME cwd, newer) ───────────────────────────────────
( exec -a "${LABEL}_succ" sleep 3000 ) & SUCC_PID=$!
sleep 0.3
NOW="$(date +%s)"; OLD_TS="$(TZ=UTC date -j -f %s "$((NOW-3600))" +%Y-%m-%dT%H:%M:%S 2>/dev/null).000Z"
SUCC_STARTED="$((NOW-60))"

# ── fixtured registry (ONLY these two entries — bounds cc-teardown to the throwaway pane) ────────
mkdir -p "$D/proj/slug" "$D/bin"
cat > "$D/sessions.json" <<EOF
[{"name":"e2e-lead","paneUUID":"$PANE","account":"next","cwd":"$REPO","pid":$VICTIM_PID,"session_id":"sidA","startedAt":$((NOW-7200))},
 {"name":"e2e-succ","paneUUID":"SUCC-FAKE-0000","account":"next","cwd":"$REPO","pid":$SUCC_PID,"session_id":"sidB","startedAt":$SUCC_STARTED}]
EOF
# ── the orphan's transcript: idle 1h + a REAL /handoff invocation in the tail ────────────────────
cat > "$D/proj/slug/sidA.jsonl" <<EOF
{"type":"assistant","isSidechain":false,"timestamp":"$OLD_TS","message":{"role":"assistant","content":[{"type":"text","text":"work done, handing off"}]}}
{"type":"assistant","isSidechain":false,"timestamp":"$OLD_TS","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":"~/.claude/scripts/handoff-fire.sh --recycle --prompt-file /tmp/x"}}]}}
EOF

# ── wiring: classify + teardown read the FIXTURED registry; teardown uses the REAL it2 ───────────
cat > "$D/bin/classify" <<EOF
#!/bin/bash
CC_CLASSIFY_SESSIONS_BIN="$D/bin/sessions" CC_CLASSIFY_PROJECT_ROOTS="$D/proj" \\
CC_CLASSIFY_TEAMS_GLOB="$D/noteams" exec "$HERE/bin/cc-classify" "\$@"
EOF
cat > "$D/bin/sessions" <<EOF
#!/bin/bash
[ "\${1:-}" = "--json" ] || [ "\${1:-}" = "--all" ] && { cat "$D/sessions.json"; exit 0; }
cat "$D/sessions.json"
EOF
cat > "$D/bin/teardown" <<EOF
#!/bin/bash
CC_TEARDOWN_SESSIONS_BIN="$D/bin/sessions" CC_TEARDOWN_SELF_UUID="none" \\
CC_TEARDOWN_RECORDS_DIR="$D/rec" exec "$HERE/bin/cc-teardown" "\$@"
EOF
chmod +x "$D/bin/classify" "$D/bin/sessions" "$D/bin/teardown"
export CC_REAPER_CLASSIFY_BIN="$D/bin/classify"
export CC_REAPER_TEARDOWN_BIN="$D/bin/teardown"
export CC_REAPER_SETTLE_S=1
export CC_REAPER_LOG="$D/reaper.log"

echo ""
echo "── Scenario B — RACE (clean at classify, DIRTY at act-time): checkpoint FIRST, then ABORT ──"
# Stage the race: a mock classify asserts landed=yes (as if clean when classified), but the tree is
# dirty NOW — so the reaper's OWN act-time work-landed re-check must catch it, checkpoint the WIP, abort.
echo "uncommitted" > "$REPO/WIP_UNCOMMITTED.txt"     # dirty the tree
cat > "$D/bin/classifyB" <<EOF
#!/bin/bash
jq -nc '[{name:"e2e-lead",paneUUID:"$PANE",account:"next",cwd:"$REPO",cause:"handed-off-lead",idle_s:999,work_landed:"yes",successor:"SUCC-FAKE-0000",detail:"staged race"}]'
EOF
chmod +x "$D/bin/classifyB"
CC_REAPER_CLASSIFY_BIN="$D/bin/classifyB" "$HERE/bin/cc-reaper" sweep --reap > "$D/outB.txt" 2>&1 || true
if pane_present "$PANE" && kill -0 "$VICTIM_PID" 2>/dev/null; then ok "orphan NOT reaped — pane + process survive (WIP not lost)"; else bad "orphan was reaped despite dirty tree (WIP LOST)"; fi
if git -C "$REPO" for-each-ref 'refs/wip/**' 'refs/checkpoints/**' 2>/dev/null | grep -q .; then ok "WIP checkpointed BEFORE the close attempt ($(git -C "$REPO" for-each-ref --format='%(refname)' 'refs/wip/**' 'refs/checkpoints/**' | head -1))"; else bad "no checkpoint ref created for uncommitted work"; fi
grep -q ABORT "$D/outB.txt" && ok "reaper reported ABORT (dirty at act-time re-check)" || bad "no ABORT reported"
rm -f "$REPO/WIP_UNCOMMITTED.txt"; git -C "$REPO" update-ref -d refs/wip/e2e-lead/LAST 2>/dev/null || true

echo ""
echo "── Scenario A — clean+landed handed-off orphan: REAP + re-enumeration confirms the pane is GONE ──"
rm -f "$REPO/WIP_UNCOMMITTED.txt"             # clean the tree → work-landed
[ -z "$(git -C "$REPO" status --porcelain)" ] && ok "precondition: tree clean, 0 ahead of origin/main (work landed)" || bad "tree not clean"
"$HERE/bin/cc-reaper" sweep --reap > "$D/outA.txt" 2>&1 || true
sleep 1
if ! pane_present "$PANE"; then ok "REAL pane $PANE is GONE (cc-teardown closed it; re-enumeration confirms)"; PANE=""; else bad "pane still present after reap"; fi
if ! kill -0 "$VICTIM_PID" 2>/dev/null; then ok "victim process is dead (both legs effect-verified)"; else bad "victim process survived"; fi
grep -qiE 'reaped|torn down' "$D/outA.txt" && ok "reaper reported the reap + effect-verify" || bad "reaper did not report a reap"

echo ""
printf 'reaper-e2e: %d passed · %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
