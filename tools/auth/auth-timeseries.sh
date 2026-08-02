#!/usr/bin/env bash
# auth-timeseries.sh — the instrument backlog f272b30e66f5 says does not exist:
# a per-account auth-state time series. READ-ONLY. Never emits a token value —
# only sha256 prefixes, so a rotation is visible without the secret being.
#
# Answers, from evidence rather than inference:
#   * does a refresh ROTATE the refresh token?      (rt hash changes)
#   * how many rotations happen per access-token TTL? (>1 per window ⇒ the
#     thundering-herd race: N sessions each rotating what the others hold)
#   * when does a credential go EMPTY?               (= the forced logout)
#
# Usage: auth-timeseries.sh <out.jsonl> [interval_s] [duration_s]
set -uo pipefail
OUT="${1:?out.jsonl}"; INT="${2:-60}"; DUR="${3:-21600}"
KC_ACCT=chrisren
declare -a DIRS=(
  "next:/Users/chrisren/.claude-next"
  "next2:/Users/chrisren/.claude-secondary"
  "next3:/Users/chrisren/.claude-tertiary"
  "next4:/Users/chrisren/.claude-quaternary"
  "default:/Users/chrisren/.claude"
)
svc() { printf 'Claude Code-credentials-%s' "$(printf '%s' "$1" | shasum -a 256 | cut -c1-8)"; }

END=$(( $(date +%s) + DUR ))
while [ "$(date +%s)" -lt "$END" ]; do
  TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  for row in "${DIRS[@]}" "unsuffixed:"; do
    name="${row%%:*}"; dir="${row#*:}"
    if [ -z "$dir" ]; then s="Claude Code-credentials"; else s="$(svc "$dir")"; fi
    # Live INTERACTIVE-SESSION count for this config dir — the population sharing this ONE
    # credential. Must key on argv[0] being the claude binary, else every node/MCP/hook child
    # that merely INHERITED CLAUDE_CONFIG_DIR is counted too (a bare grep read 57 where the
    # truth was 0). Matches BOTH spellings: the .bin/claude symlink AND the native claude.exe
    # it points at — claude-accounts' own concurrency() misses the latter, which is exactly
    # the blindness under investigation, so this instrument must not inherit it.
    if [ -n "$dir" ]; then
      n=$(ps -wwEo command= 2>/dev/null | CFG="$dir" python3 -c '
import sys,os,re
d=os.environ["CFG"]; n=0
for line in sys.stdin:
    t=line.split()
    if not t: continue
    t0=t[0]
    if not (t0=="claude" or t0.endswith("/claude") or t0.endswith("claude.exe") or "cli.js" in t0): continue
    head=[x for x in t[1:7] if x.startswith("-")]
    if {"-p","--print","--version"} & set(head): continue
    m=re.findall(r"CLAUDE_CONFIG_DIR=(\S+)",line)
    if (m[-1].rstrip("/") if m else os.path.expanduser("~/.claude"))==d: n+=1
print(n)')
    else n=0; fi
    /usr/bin/security find-generic-password -s "$s" -a "$KC_ACCT" -w 2>/dev/null \
    | TS="$TS" ACCT="$name" SVC="$s" NLIVE="$n" python3 -c '
import sys,json,os,hashlib
raw=sys.stdin.read().strip()
rec={"ts":os.environ["TS"],"acct":os.environ["ACCT"],"svc":os.environ["SVC"],
     "n_live":int(os.environ["NLIVE"])}
if not raw:
    rec["state"]="NO_ITEM"
else:
    try: d=json.loads(raw)
    except Exception: d=None
    if d is None: rec["state"]="UNPARSEABLE"
    else:
        o=d.get("claudeAiOauth") or {}
        at=o.get("accessToken") or ""; rt=o.get("refreshToken") or ""
        h=lambda v: hashlib.sha256(v.encode()).hexdigest()[:12] if v else None
        rec.update(state=("EMPTY" if not at and not rt else "OK"),
                   at=h(at), rt=h(rt),
                   expiresAt=o.get("expiresAt"),
                   refreshTokenExpiresAt=o.get("refreshTokenExpiresAt"),
                   scopes=len(o.get("scopes") or []),
                   sub=o.get("subscriptionType"))
print(json.dumps(rec))' >> "$OUT" 2>/dev/null
  done
  sleep "$INT"
done
