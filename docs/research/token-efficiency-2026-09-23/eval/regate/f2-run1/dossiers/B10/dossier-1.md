# Dossier 1

## Brief
```
In /tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh, which environment variables act as kill switches or off-switches (a variable that, when set to off/0, disables a section or check)? For each give the variable, the line, and what it turns off. numbers: {"kill_switches": <how many>}.
```

## Returned headline
wrap-ledger.sh has 3 kill switches (found with grep and by reading the code). WRAP_CACHE at line 379 accepts off, 0 or no and disables the ledger memo cache. WRAP_RESIDENT=off at line 1160 skips the resident team-member count. WRAP_BUSY=off at line 2137 skips the session-busy probe.

## Returned numbers
`{"kill_switches": 3}`

## answer.md
# Kill switches in scripts/wrap-ledger.sh

File: /tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh (2444 lines, measured with `wc -l`).

I found 3 kill switches. Method: I ran `grep` for `${VAR:-...}` defaults and for comparisons against off/0/no, then read the code around each hit.

| # | Variable | Line | Accepted "off" values | What it turns off |
|---|----------|------|-----------------------|-------------------|
| 1 | `WRAP_CACHE` | 379 (the header comment at line 276 calls it the "Kill switch") | `off`, `0`, `no`, `OFF`, `NO` | The ledger memo cache. It sets `WL_TRANSCRIPT=""`, so the machine-mode cache block (`if [ "$MODE" = "machine" ] && [ -n "$WL_TRANSCRIPT" ]`, line 380) never runs, and the cache is never read or written. This is the benchmark's control arm. `GOAL_TRANSCRIPT` is copied before this line, so the transcript input itself is unaffected. |
| 2 | `WRAP_RESIDENT` | 1160 (inside `count_resident_members`) | exactly `off` | The resident team-member count. The function returns early with `RESIDENT_SRC="none"` and skips the teams-config lookup and the `ps` scan. |
| 3 | `WRAP_BUSY` | 2137 | exactly `off` (tested as `!= "off"`) | The BUSY / session-busy probe. It skips sourcing `hooks/lib/session-busy.sh` and calling `session_busy_live`. BUSY stays at `BUSY=0`, `BUSY_STATE=UNKNOWN`, `BUSY_SRC=none`, and the permission-pending fields stay at their defaults. |

Notes:
- Only `WRAP_CACHE` accepts `0` or `no`. `WRAP_RESIDENT=0` and `WRAP_BUSY=0` do nothing, because both are compared against the literal string `off`.
- `DRAIN_SCOPE` (line 942, `${DRAIN_SCOPE:-0}`) is not an environment kill switch. The script sets it internally at lines 601 and 627 from the DoD scope text.
- The `*_TIMEOUT_S`, `*_BIN`, `*_DIR`, `*_LIB` and budget variables change values or paths. They do not turn sections off, so I did not count them.


## Tool calls (6) with the first 300 chars of each result
1. `Bash: {"command": "wc -l /tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh; grep -nE '\\$\\{?[A-Z_][A-Z0-9_]*' /tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh | grep -nE 'off|\"0\"|=0|:-' | head -80; ls /tmp/tokeff-regate/f2/out/B10-r5/ 2>&1", "description": "Inspect env var usages in script"}`
   → Exit code 1
    2444 /tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh
8:278:WL_TRANSCRIPT="${TRANSCRIPT_FLAG:-${WRAP_TRANSCRIPT:-}}"
13:335:  [ "${first:-}" = "#WLKEY $WL_KEY" ] || return 1
24:376:  [ $((now - lm)) -gt "${WRAP_CACHE_LOCK_STALE_S:-30}" ]
25:379:case "${WRAP_CACHE:-on}" in off|0|no|O
2. `Bash: {"command": "F=/tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh; grep -nE '(off|OFF|no\\)|\"0\"|= *0\\b|-eq 0|:-on|:-1\\})' $F | grep -E '\\$\\{[A-Z_]+' | grep -vE '_TIMEOUT_S|\\|\\*\\[!0-9\\]'", "description": "Find env vars compared to off/0"}`
   → 379:case "${WRAP_CACHE:-on}" in off|0|no|OFF|NO) WL_TRANSCRIPT="" ;; esac
1160:  [ "${WRAP_RESIDENT:-on}" = "off" ] && { RESIDENT_SRC="none"; return 0; }
2033:    RUNG="🔧"; READOUT="🔧 Loose ends — ${FILED_MINE} backlog row(s) you filed this session are still open with no reason you could not drive t
3. `Bash: {"command": "F=/tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh; grep -oE '\\$\\{[A-Z][A-Z0-9_]*:-[^}]{0,6}' $F | sort | uniq -c | sort -rn | head -100; echo ---; grep -nE 'WRAP_[A-Z_]*|CC_[A-Z_]*' $F | grep -iE 'disable|kill|skip|off' | head -30", "description": "List env var defaults and off-rela`
   →   10 ${WRAP_LIVE_TIMEOUT_S:-5
   3 ${WRAP_RESIDENT_TIMEOUT_S:-5
   2 ${WRAP_TRUNK:-
   2 ${WRAP_SESSION_ID:-
   2 ${WRAP_DOD_FILE:-
   2 ${WRAP_CUSTODY_TIMEOUT_S:-5
   2 ${WRAP_BACKLOG_TIMEOUT_S:-5
   2 ${TRUNK:-none
   2 ${SID:-
   2 ${CLAUDE_SESSION_ID:-
   2 ${CC_PANE_ID:-${ITER
   2 ${CC_DECIDE_
4. `Bash: {"command": "F=/tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh; grep -nE '\"\\$[A-Z][A-Z0-9_]*\" *(=|!=) *\"?(off|0|no)' $F; grep -nE 'DRAIN_SCOPE=' $F | head; sed -n 270,285p $F; sed -n 376,383p $F; sed -n 1150,1162p $F; sed -n 2125,2145p $F", "description": "Read context around kill switches"}`
   → 597:# captures (the same line hooks/dod-persist.sh:210 injects as "THE CURRENT CONTRACT"). DRAIN_SCOPE=1
601:DOD_SCOPE=""; DRAIN_SCOPE=0
627:case "$DOD_SCOPE" in *[Bb][Aa][Cc][Kk][Ll][Oo][Gg]*|*[Dd][Rr][Aa][Ii][Nn]*) DRAIN_SCOPE=1 ;; esac
2227:  printf 'DRAIN_SCOPE=%s\n' "$DRAIN_SCOPE"
#     YOURS/B
5. `Bash: {"command": "mkdir -p /tmp/tokeff-regate/f2/out/B10-r5 && cat > /tmp/tokeff-regate/f2/out/B10-r5/answer.md <<'EOF'\n# Kill switches in scripts/wrap-ledger.sh\n\nFile: /tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh (2444 lines, measured with `wc -l`).\n\nI found 3 kill switches. Method: I ran `gre`
   → (Bash completed with no output)
6. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B10-r5/answer.md", "headline": "wrap-ledger.sh has 3 kill switches (found with grep and by reading the code). WRAP_CACHE at line 379 accepts off, 0 or no and disables the ledger memo cache. WRAP_RESIDENT=off at line 1160 skips the resident team-member count`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
