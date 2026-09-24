# Dossier 2

## Brief
```
In /tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh, which environment variables act as kill switches or off-switches (a variable that, when set to off/0, disables a section or check)? For each give the variable, the line, and what it turns off. numbers: {"kill_switches": <how many>}.
```

## Returned headline
wrap-ledger.sh has 3 kill switches: WRAP_CACHE (line 379; off/0/no turns off the memo cache), WRAP_RESIDENT (line 1160; off turns off the resident-teammate check) and WRAP_BUSY (line 2137; off turns off the session-busy probe).

## Returned numbers
`{"kill_switches": 3}`

## answer.md
# Kill switches in scripts/wrap-ledger.sh

There are 3 kill switches. Each one defaults to on and turns off one section of the ledger.

| # | Variable | Line | Accepted "off" values | What it turns off |
|---|----------|------|-----------------------|-------------------|
| 1 | `WRAP_CACHE` | 379 (`case "${WRAP_CACHE:-on}" in off\|0\|no\|OFF\|NO) WL_TRANSCRIPT="" ;; esac`); documented at 276 | `off`, `0`, `no`, `OFF`, `NO` | The ledger memo cache. It blanks `WL_TRANSCRIPT`, and the `if [ "$MODE" = "machine" ] && [ -n "$WL_TRANSCRIPT" ]` block at line 380 then skips the cache key, the read and the write. Line 276 says: "never read, never write (the benchmark's control arm)". The goal/transcript term is not affected, because `GOAL_TRANSCRIPT` is copied at line 285, before the blanking. |
| 2 | `WRAP_RESIDENT` | 1160 (`[ "${WRAP_RESIDENT:-on}" = "off" ] && { RESIDENT_SRC="none"; return 0; }`, in `count_resident_members`) | `off` only | The resident-teammate check (`RESIDENT_MINE`). This check turns live members of this session's team, and a member's dirty files, into a 🔧 loose end. When off, `RESIDENT_SRC=none` and nothing is counted. |
| 3 | `WRAP_BUSY` | 2137 (`if [ "${WRAP_BUSY:-on}" != "off" ] && [ -f "$_wl_sbl" ]; then`) | `off` only | The session-busy probe: it sources `hooks/lib/session-busy.sh` and calls `session_busy_live`. When off, BUSY/BUSY_STATE/BUSY_SRC/BUSY_AGE/BUSY_SUSPECT/PERMPEND keep their defaults (`BUSY_STATE=UNKNOWN`, `BUSY_SRC=none`). |

Only `WRAP_CACHE` also accepts `0` or `no`. `WRAP_RESIDENT` and `WRAP_BUSY` react only to the exact string `off`, so setting either to `0` does nothing.

The other `WRAP_*` and `CC_*` variables are not counted. They are test seams, timeouts or budgets (`WRAP_LIVE_BUDGET_*`, `WRAP_*_TIMEOUT_S`, `WRAP_CACHE_DIR`, `WRAP_LIVE_STALE_MAX`, and so on), and none of them switches a section off when set to off or 0.


## Tool calls (7) with the first 300 chars of each result
1. `Bash: {"command": "F=/tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh; wc -l $F; grep -nE '(:-|:=)(on|off|1|0)\\}|=\\s*\"?(off|0)\"?|!= *\"?(off|0)|== *\"?(off|0)|\"off\"|\\boff\\b' $F | head -120"}`
   →     2444 /tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh
30:#     ✅  clean ∧ not-stale ∧ landed ∧ remainder = 0 ∧ no unrun operator step from this session
52:#   that cannot (MEMORY.md alarm-polarity). Unresolvable session ⇒ BLOCKED=0 + BLOCKED_SRC=none;
53:#   unreadable store ⇒ BLOCKED=0 + BLOCK
2. `Bash: {"command": "F=/tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh; grep -nE '\\$\\{[A-Z_]+:-(on|1|yes|true)\\}|[Kk]ill.?switch|off-switch|disable' $F; echo ---; sed -n 270,285p $F; sed -n 375,382p $F; sed -n 1150,1162p $F; sed -n 2125,2140p $F"}`
   → 276:# Kill switch: WRAP_CACHE=off|0|no ⇒ never read, never write (the benchmark's control arm).
279:# The transcript as an INPUT, kept out of the cache kill-switch's reach. $WL_TRANSCRIPT is a
379:case "${WRAP_CACHE:-on}" in off|0|no|OFF|NO) WL_TRANSCRIPT="" ;; esac
553:  # shellcheck disable=SC1091
3. `Bash: {"command": "F=/tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh; grep -noE '\\$\\{[A-Z][A-Z0-9_]+:-[^}]{0,20}\\}' $F | sort -t: -k3 -u | awk -F: '{print $1\": \"$2}' | sort -u -t' ' -k2; grep -nE 'CC_[A-Z_]+' $F | grep -viE 'shellcheck' | head -40"}`
   → 857: ${CC_CONVICTION_EPOCH
396: ${CC_PANE_ID
591: ${DHASH
278: ${TRANSCRIPT_FLAG
2241: ${TRUNK
400: ${UID
2144: ${WRAP_BUSY_TIMEOUT_S
379: ${WRAP_CACHE
400: ${WRAP_CACHE_DIR
376: ${WRAP_CACHE_LOCK_STALE_S
438: ${WRAP_CACHE_WAIT_MS
436: ${WRAP_CACHE_WAIT_TRIES
710: ${WRAP_GOAL_TIMEOUT_S
1283: ${WRAP_
4. `Bash: {"command": "F=/tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh; sed -n 176,192p $F; echo ---; sed -n 1268,1312p $F; grep -nE 'WRAP_LIVE_REPO|WRAP_RESIDENT_TIMEOUT|WRAP_LAND_INFLIGHT' $F | head"}`
   → #   non-zero with a stderr note and NEVER prints RUNG=✅. A consumer that can't get a ledger must
#   treat that as "cannot confirm", not as "complete". Pure-read of the REPO: the only bytes this
#   writes are its own memo under TMPDIR (below) — which is why the live-layer read never fetches
#   (se
5. `Bash: {"command": "F=/tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh; grep -n 'WRAP_CACHE\\b\\|WRAP_CACHE:' $F; sed -n 382,386p $F; grep -n 'WL_TRANSCRIPT' $F | head; sed -n 2141,2150p $F"}`
   → 188:#                    WRAP_CACHE · WRAP_CACHE_DIR · WRAP_CACHE_WAIT_MS · WRAP_CACHE_WAIT_TRIES ·
276:# Kill switch: WRAP_CACHE=off|0|no ⇒ never read, never write (the benchmark's control arm).
280:# CACHE-KEY variable and `WRAP_CACHE=off` BLANKS it (below) — so a term that read the transcript
379
6. `Bash: {"command": "mkdir -p /tmp/tokeff-regate/f2/out/B10-r6 && cat > /tmp/tokeff-regate/f2/out/B10-r6/answer.md <<'EOF'\n# Kill switches in scripts/wrap-ledger.sh\n\nThere are 3 kill switches. Each one defaults to on and turns off one section of the ledger.\n\n| # | Variable | Line | Accepted \"off\" val`
   → (Bash completed with no output)
7. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B10-r6/answer.md", "headline": "wrap-ledger.sh has 3 kill switches: WRAP_CACHE (line 379; off/0/no turns off the memo cache), WRAP_RESIDENT (line 1160; off turns off the resident-teammate check) and WRAP_BUSY (line 2137; off turns off the session-busy probe`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
