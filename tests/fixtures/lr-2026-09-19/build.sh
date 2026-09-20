#!/bin/bash
# build.sh — the 5-session acceptance fixture for bin/cc-limited (LIMIT_DETECT_100P § 5).
#
# This is one real afternoon, frozen. Every row below was measured on 2026-09-19 on the live fleet
# and is reproduced here with its real 8-char sid prefix (tail zeroed), its real timestamps and its
# real account. It is the fixture because each of the five sessions is a DIFFERENT way the shipped
# census was wrong, and a census that gets all five right cannot be getting them right by accident:
#
#   07e30aeb  the preferred copy is a 3-record STUB with 0 assistant records while a 1.1 MB frozen
#             snapshot sits under another root. Ordering copies by size or mtime names the snapshot
#             and welds the wrong transcript to the pane. Expect RECOVERABLE (stub), 3 copies.
#   09e64dcb  three deaths across TWO accounts, and its pane has since been taken by a different
#             session. Grouping by the marker FILENAME reports it twice, under both accounts.
#             Expect ONE row, fires=3, PANE-REUSED.
#   65186f1f  moved to another account and RE-ENGAGED there — a registry row started 20:48:39Z
#             against a death at 19:58:34Z. It must be grouped under where it IS, not where it died.
#   98f02458  a transplant CLAIMED it 21 minutes ago and the claimant is not running. The shipped
#             census cannot see this state at all; it is the "recovery produced nothing" case.
#   4bc1159f  the same, with no transcript copy anywhere.
#
# Usage:  build.sh <dir>   then source <dir>/env.sh to get the seams.
# Writes only under <dir>. Requires nothing but bash and coreutils.
set -euo pipefail

W="${1:?usage: build.sh <dir>}"
rm -rf "$W"; mkdir -p "$W"
H="$W/home"

# The pinned instant. Every "in 16m", every claim age and every reset countdown below is relative
# to THIS, never to the wall clock — an assertion that moves with the machine is not an assertion.
NOW_ISO="2026-09-19T21:14:00Z"

mk() { mkdir -p "$(dirname "$1")"; cat > "$1"; }

# ── accounts: four config dirs, and ~/.claude reachable ONLY through next's alias ────────────────
mk "$H/.claude/accounts.json" <<'JSON'
{"accounts":[
  {"name":"next",  "config_dir":"~/.claude-next",       "aliases":["claude"]},
  {"name":"next2", "config_dir":"~/.claude-secondary",  "aliases":[]},
  {"name":"next3", "config_dir":"~/.claude-tertiary",   "aliases":[]},
  {"name":"next4", "config_dir":"~/.claude-quaternary", "aliases":[]}
]}
JSON

# The cwds are real absolute paths rooted inside the fixture so `cwd_ok` is a TRUE fact about this
# tree rather than an accident of the box. The transcript slug is derived from the same string, so
# the slug-directed probe is exercised exactly as it is in production.
DEV="$W/Users/chrisren/Development"
CWD_INFRA="$DEV/claude-infrastructure"
CWD_POOL2="$DEV/.worktrees/wt-pool-2"
CWD_W0="$DEV/.worktrees/subagent-lifecycle-w0"
CWD_143039="$DEV/.worktrees/wt-cc-143039-68221"
mkdir -p "$CWD_INFRA" "$CWD_POOL2" "$CWD_W0" "$CWD_143039"
slug() { printf '%s' "$1" | sed 's/[^A-Za-z0-9]/-/g'; }

# ── 1. the nine marker rows, in two cause files ─────────────────────────────────────────────────
row() { # sid acct_cfg cwd pane ts text
  printf '{"ts":"%s","error":"rate_limit","account":"%s","config_dir":"%s","session_id":"%s",' \
    "$5" "$2" "$H/.claude-$2x" "$1"
  printf '"cwd":"%s","transcript_path":"","hook_event_name":"StopFailure","pane":"%s",' "$3" "$4"
  printf '"last_assistant_message":"%s"}\n' "$6"
}
CAP5H="You've hit your session limit · resets 4:30pm (America/Chicago)"
M="$H/.claude/autonomy/stop-failure"; mkdir -p "$M"
{
  row 09e64dcb-0000-4000-8000-000000000000 quaternary "$CWD_INFRA"   111 2026-09-19T17:01:34Z "$CAP5H"
  row 09e64dcb-0000-4000-8000-000000000000 quaternary "$CWD_INFRA"   111 2026-09-19T17:11:29Z "$CAP5H"
} > "$M/rate_limit__next4.jsonl"
{
  row 98f02458-0000-4000-8000-000000000000 tertiary "$CWD_POOL2"   ""  2026-09-19T19:52:33Z "$CAP5H"
  row 09e64dcb-0000-4000-8000-000000000000 tertiary "$CWD_INFRA"   111 2026-09-19T19:53:38Z "$CAP5H"
  row 65186f1f-0000-4000-8000-000000000000 tertiary "$CWD_W0"      121 2026-09-19T19:57:41Z "$CAP5H"
  row 98f02458-0000-4000-8000-000000000000 tertiary "$CWD_POOL2"   ""  2026-09-19T19:57:43Z "$CAP5H"
  row 65186f1f-0000-4000-8000-000000000000 tertiary "$CWD_W0"      121 2026-09-19T19:58:34Z "$CAP5H"
  row 4bc1159f-0000-4000-8000-000000000000 tertiary "$CWD_INFRA"   ""  2026-09-19T20:00:44Z "$CAP5H"
  row 07e30aeb-0000-4000-8000-000000000000 tertiary "$CWD_143039"  147 2026-09-19T20:29:28Z "$CAP5H"
} > "$M/rate_limit__next3.jsonl"
# The config_dir written above is a stand-in; rewrite it to the real fixture dirs so the account
# resolves through the SAME basename path production uses.
sed -i.bak "s|$H/.claude-quaternaryx|$H/.claude-quaternary|g; s|$H/.claude-tertiaryx|$H/.claude-tertiary|g" \
  "$M/rate_limit__next4.jsonl" "$M/rate_limit__next3.jsonl"
rm -f "$M"/*.bak

# ── 2. the registry, and the ps table it is judged against ──────────────────────────────────────
# lstart is pinned text, and both sides render it the same way — an unpinned (pid,lstart) pair
# convicts every row on a DST flip.
R="$H/.claude/cc-registry"; mkdir -p "$R"
reg() { # pane sid account pid startedAt_ms cwd
  mk "$R/$1.json" <<JSON
{"paneUUID":"$1","name":"p$1","cwd":"$6","account":"$3","pid":$4,
 "startedAt":$5,"session_id":"$2","surface":"kitty","lstart":"Fri Sep 19 12:00:00 2026"}
JSON
}
# pane 111 was RECYCLED: it now belongs to cb29ae36, not to 09e64dcb. startedAt 22:36:06Z.
reg 111 cb29ae36-0000-4000-8000-000000000000 claude-secondary 12341 1789857366000 "$CWD_INFRA"
# 65186f1f is alive on ANOTHER account (next2), started 20:48:39Z — after its 19:58:34Z death.
reg 121 65186f1f-0000-4000-8000-000000000000 claude-secondary 59379 1789850919000 "$CWD_W0"
# 07e30aeb is alive in place on next3.
reg 147 07e30aeb-0000-4000-8000-000000000000 claude-tertiary  84167 1789852000000 "$CWD_143039"
{
  echo "12341 Fri Sep 19 12:00:00 2026"
  echo "59379 Fri Sep 19 12:00:00 2026"
  echo "84167 Fri Sep 19 12:00:00 2026"
  echo "  1 Fri Sep 19 00:00:00 2026"
} > "$W/ps.txt"
: > "$W/procs.txt"          # no `--resume` process is in flight in this world

# ── 3. the two claims — a transplant said it would recover these, 21 and 14 minutes ago ─────────
L="$H/.reso/limit-recover/locks"; mkdir -p "$L"
mk "$L/98f02458-0000-4000-8000-000000000000.lock" <<JSON
{"to":"$H/.claude-secondary","ts":"2026-09-19T20:53:26Z","pid":32971}
JSON
mk "$L/4bc1159f-0000-4000-8000-000000000000.lock" <<JSON
{"to":"$H/.claude-secondary","ts":"2026-09-19T20:59:34Z","pid":44616}
JSON
mkdir -p "$H/.reso/limit-recover/parked" "$H/.reso/limit-recover/faults"
# cc-beats EXISTS and is EMPTY. Both halves matter: the census names an absent optional store in
# its footer (§ 11 #11), so a fixture that simply omitted the directory would make every row above
# assert against a footer no production box prints. An empty store is the healthy shape here —
# these five sessions are dead, and a beat is written on prompt submission.
mkdir -p "$H/.claude/cc-beats"

# ── 4. the transcript copies ────────────────────────────────────────────────────────────────────
death() { printf '{"type":"assistant","isApiErrorMessage":true,"error":"rate_limit","apiErrorStatus":429,"uuid":"d-%s","timestamp":"%s","message":{"model":"<synthetic>","content":[{"type":"text","text":"%s"}]},"quotaLimits":{"resetsAt":1789853400,"rateLimitType":"five_hour"}}\n' "$1" "$2" "$CAP5H"; }
turn()  { printf '{"type":"assistant","uuid":"t-%s","timestamp":"%s","message":{"model":"claude-opus-5","content":[{"type":"text","text":"a real turn"}]}}\n{"type":"system","subtype":"ai-title","aiTitle":"%s"}\n' "$1" "$2" "$3"; }

copy() { mkdir -p "$(dirname "$1")"; cat > "$1"; }
SEC="$H/.claude-secondary/projects"; TER="$H/.claude-tertiary/projects"

# 07e30aeb — THE STUB CASE. The copy under the LIVE account's root is 3 records with ZERO assistant
# turns; the copy holding the death record is 8x larger and sits under a different root. Any rule
# that picks "the biggest" or "the newest" names the wrong one.
copy "$TER/$(slug "$CWD_143039")/07e30aeb-0000-4000-8000-000000000000.jsonl" <<'EOF'
{"type":"system","subtype":"queue-operation","op":"enqueue"}
{"type":"system","subtype":"queue-operation","op":"drain"}
{"type":"system","subtype":"bridge-session"}
EOF
{ turn 07e30aeb-a 2026-09-19T20:00:00Z "wt-cc-143039-68221"; death 07e30aeb 2026-09-19T20:29:28Z; } \
  > /tmp/.lrfix.$$ && copy "$SEC/$(slug "$CWD_143039")/07e30aeb-0000-4000-8000-000000000000.jsonl.handed-off" < /tmp/.lrfix.$$ && rm -f /tmp/.lrfix.$$

# ...and a THIRD, a salvage copy under a third root. Three copies of one session is ordinary here
# (median 2, max 4), and it is what makes "pick the live copy" unanswerable by inspection.
copy "$TER/$(slug "$CWD_143039")/07e30aeb-0000-4000-8000-000000000000.jsonl.handed-off" <<'EOF'
{"type":"system","subtype":"bridge-session"}
EOF

# 98f02458 — blocked, its copy ends on the death record.
{ turn 98f02458-a 2026-09-19T19:50:00Z "wt-pool-2"; death 98f02458 2026-09-19T19:57:43Z; } \
  > /tmp/.lrfix.$$ && copy "$SEC/$(slug "$CWD_POOL2")/98f02458-0000-4000-8000-000000000000.jsonl" < /tmp/.lrfix.$$ && rm -f /tmp/.lrfix.$$

# 65186f1f — RE-ENGAGED: a REAL assistant turn at 20:50Z, after the 19:58:34Z death.
{ death 65186f1f 2026-09-19T19:58:34Z; turn 65186f1f-b 2026-09-19T20:50:00Z "subagent-lifecycle-w0"; } \
  > /tmp/.lrfix.$$ && copy "$SEC/$(slug "$CWD_W0")/65186f1f-0000-4000-8000-000000000000.jsonl" < /tmp/.lrfix.$$ && rm -f /tmp/.lrfix.$$

# 09e64dcb — blocked, copy ends on the death record.
{ turn 09e64dcb-a 2026-09-19T19:50:00Z "claude-infrastructure"; death 09e64dcb 2026-09-19T19:53:38Z; } \
  > /tmp/.lrfix.$$ && copy "$TER/$(slug "$CWD_INFRA")/09e64dcb-0000-4000-8000-000000000000.jsonl" < /tmp/.lrfix.$$ && rm -f /tmp/.lrfix.$$

# 4bc1159f — NO copy anywhere. Blocked by construction, and the FAULT must still be named.

# ── the seams ───────────────────────────────────────────────────────────────────────────────────
cat > "$W/env.sh" <<ENVSH
export HOME="$H"
export CC_LIMITED_MARKER_DIR="$M"
export CC_REGISTRY_DIR="$R"
export LR_STATE_DIR="$H/.reso/limit-recover"
export CC_LIMITED_ACCOUNTS="$H/.claude/accounts.json"
export CC_LIMITED_ROOTS="$H/.claude-next:$H/.claude-secondary:$H/.claude-tertiary:$H/.claude-quaternary"
export CC_LIMITED_PS="$W/ps.txt"
export CC_LIMITED_PROCS="$W/procs.txt"
export CC_LIMITED_IDL="$W/idl.jsonl"
export CC_BEAT_DIR="$H/.claude/cc-beats"
export LR_NOW="$NOW_ISO"
ENVSH
: > "$W/idl.jsonl"
echo "$W"
