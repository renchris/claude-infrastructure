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
# Usage:
#   auth-timeseries.sh --once [out.jsonl]                  ONE sample batch, then exit
#   auth-timeseries.sh <out.jsonl> [interval_s] [duration_s]   ad-hoc run (the original contract)
#
# WHY --once EXISTS. This was a manual, time-bounded instrument: a 6-hour ad-hoc run to a
# caller-supplied path, which nothing scheduled and which accumulated into no durable store. So
# the thing it was built to catch — a forced logout — left no trace once the session watching for
# it ended, and every observation died with its observer. The fix is a schedule, and a scheduled
# job cannot be a process that runs for six hours: under StartInterval, overlapping 6-hour
# samplers pile up until the box is carrying dozens of them. --once makes one batch the unit of
# work and lets launchd own the cadence. The looping contract is untouched for existing callers.
#
# THE STORE is ${AUTH_TS_OUT:-$HOME/.claude/logs/auth-timeseries.jsonl} — appended, never
# truncated, rotated by scripts/rotate-autonomy-logs.sh and bounded by config/store-bounds.manifest.
# A positional path still wins, so an investigation can still sample to its own scratch file
# without polluting the durable series.
set -uo pipefail
ONCE=0
[ "${1:-}" = "--once" ] && { ONCE=1; shift; }
OUT="${1:-${AUTH_TS_OUT:-$HOME/.claude/logs/auth-timeseries.jsonl}}"; INT="${2:-60}"; DUR="${3:-21600}"
mkdir -p "$(dirname "$OUT")" 2>/dev/null || true
KC_ACCT="${AUTH_TS_KC_ACCT:-chrisren}"
declare -a DIRS=(
  "next:$HOME/.claude-next"
  "next2:$HOME/.claude-secondary"
  "next3:$HOME/.claude-tertiary"
  "next4:$HOME/.claude-quaternary"
  "default:$HOME/.claude"
)
svc() { printf 'Claude Code-credentials-%s' "$(printf '%s' "$1" | shasum -a 256 | cut -c1-8)"; }

END=$(( $(date +%s) + DUR ))
rows_now() { if [ -f "$OUT" ]; then wc -l < "$OUT" 2>/dev/null || echo 0; else echo 0; fi; }
BEFORE=$(rows_now)
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
    # mdat = the keychain item's WRITE time. Distinct from a token change, and the
    # discriminator the token hashes alone cannot give: a write that leaves the hashes
    # identical is a re-write (a second writer replaying what it already held), while a
    # changed hash with no new mdat is impossible. Without it, "who wrote this" is
    # unanswerable and a stale-writer race is indistinguishable from a quiet credential.
    # The attribute dump goes to STDOUT (same stream as -w's payload); the only thing on
    # stderr is the not-found message. Do NOT "fix" this to `2>&1 >/dev/null` — that reads
    # correct and yields an empty mdat on EVERY row under bash. It appears to work only if
    # you test it in zsh, whose MULTIOS tees stdout to both the pipe and /dev/null; the
    # control then passes in a shell the subject never runs in.
    md=$(/usr/bin/security find-generic-password -s "$s" -a "$KC_ACCT" 2>/dev/null \
         | sed -n 's/.*"mdat"<timedate>=0x[0-9A-F]*  *"\([0-9]*\)Z.*/\1/p' | head -1)
    /usr/bin/security find-generic-password -s "$s" -a "$KC_ACCT" -w 2>/dev/null \
    | TS="$TS" ACCT="$name" SVC="$s" NLIVE="$n" MDAT="${md:-}" python3 -c '
import sys,json,os,hashlib
raw=sys.stdin.read().strip()
rec={"ts":os.environ["TS"],"acct":os.environ["ACCT"],"svc":os.environ["SVC"],
     "n_live":int(os.environ["NLIVE"]),"mdat":os.environ.get("MDAT") or None}
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
  [ "$ONCE" = 1 ] && break
  sleep "$INT"
done

# A scheduled sampler that samples NOTHING must say so. Every failure inside the loop is
# swallowed by `2>/dev/null` — deliberately, so one unreadable keychain item cannot abort the
# batch — which means silence is indistinguishable from success unless something counts. Under
# launchd there is additionally no interactive session to answer a keychain ACL prompt, and that
# denial is exactly the failure that would otherwise render as a clean run of NO_ITEM rows.
# Exit 3 = NO-DATA, an honest non-verdict, following the qos-census precedent that a non-zero
# exit can be the DESIGNED outcome for a census. Only on --once: a long ad-hoc run keeps its
# original always-0 contract.
if [ "$ONCE" = 1 ]; then
  AFTER=$(rows_now)
  if [ "$AFTER" -le "$BEFORE" ]; then
    echo "auth-timeseries: NO-DATA — appended 0 rows to $OUT (keychain ACL under launchd?)" >&2
    exit 3
  fi
fi
exit 0
