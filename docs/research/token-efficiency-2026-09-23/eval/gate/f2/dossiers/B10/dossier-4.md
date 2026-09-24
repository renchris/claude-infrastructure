# Dossier 4

## Brief
```
In /tmp/tokeff-gate/f2/tree/scripts/wrap-ledger.sh, which environment variables act as kill switches or off-switches (a variable that, when set to off/0, disables a section or check)? For each give the variable, the line, and what it turns off. numbers: {"kill_switches": <how many>}.
```

## Returned headline
wrap-ledger.sh has three kill switches: WRAP_CACHE (line 379; off/0/no/OFF/NO turns off the ledger memo cache), WRAP_RESIDENT (line 1160; off turns off the resident-team-member check) and WRAP_BUSY (line 2137; off turns off the working-vs-idle and permission-pending probe).

## Returned numbers
`{"kill_switches": 3}`

## answer.md
# Kill switches in scripts/wrap-ledger.sh

There are **3** environment-variable kill switches. Each defaults to on and disables a section when set to off.

| # | Variable | Line | Accepted "off" values | What it turns off |
|---|---|---|---|---|
| 1 | `WRAP_CACHE` | 379 (`case "${WRAP_CACHE:-on}" in off\|0\|no\|OFF\|NO) WL_TRANSCRIPT="" ;; esac`); documented at 276 | `off`, `0`, `no`, `OFF`, `NO` | The ledger memo cache. It blanks `WL_TRANSCRIPT`, the cache-key input, and an absent key means no cache (see the comment at 260), so the cache is never read or written. Line 276 calls it the benchmark's control arm. The transcript itself is still an input to the ledger: it was copied to `GOAL_TRANSCRIPT` at line 285, before the blank. |
| 2 | `WRAP_RESIDENT` | 1160 (`[ "${WRAP_RESIDENT:-on}" = "off" ] && { RESIDENT_SRC="none"; return 0; }`, in `count_resident_members`) | `off` only | The resident-team-member check (`RESIDENT_MINE`, RC-2), which finds this session's teammates whose process is still running and lists their dirty files. With the switch off, `RESIDENT_SRC=none` and no 🔧 fires for residents. |
| 3 | `WRAP_BUSY` | 2137 (`if [ "${WRAP_BUSY:-on}" != "off" ] && [ -f "$_wl_sbl" ]; then`) | `off` only | The ⏳ working-vs-idle probe, which sources `session-busy.sh` and runs `session_busy_live`. It fills BUSY / BUSY_STATE / BUSY_AGE / BUSY_SUSPECT and PERMPEND (a pending permission prompt). With the switch off, the fields stay at their defaults: `BUSY=0`, `BUSY_STATE=UNKNOWN`, `BUSY_SRC=none`. |

## Not counted
Other `WRAP_*` and `CC_*` variables are test seams or tuning knobs, not on/off switches:
- **Paths and binaries:** `WRAP_GATE_GREEN`, `WRAP_LIVE_REPO`, `WRAP_LAND_INFLIGHT_LIB`, `WRAP_SESSION_BUSY_LIB`, `CC_*_BIN`.
- **Timeouts and caps:** `*_TIMEOUT_S`, `WRAP_LIVE_ADDS_MAX`, `WRAP_LIVE_STALE_MAX`, `WRAP_LIVE_BUDGET_*`, `WRAP_CACHE_WAIT_*`.
- **`WRAP_TIMEOUT_BIN` (line 768):** a non-executable value pins "no bounder". That is a seam, not an off/0 switch.


## Tool calls (7) with the first 300 chars of each result
1. `Bash: {"command": "F=/tmp/tokeff-gate/f2/tree/scripts/wrap-ledger.sh; wc -l $F; grep -nE '(off|OFF|=0|\"0\"|:-1|:-on)' $F | grep -E '\\$\\{?[A-Z_]+' | head -100", "description": "Find candidate kill-switch variables in wrap-ledger.sh"}`
   →     2444 /tmp/tokeff-gate/f2/tree/scripts/wrap-ledger.sh
379:case "${WRAP_CACHE:-on}" in off|0|no|OFF|NO) WL_TRANSCRIPT="" ;; esac
528:DIRTY_N="$(printf '%s' "$PORC" | grep -c . 2>/dev/null || echo 0)"; case "$DIRTY_N" in ''|*[!0-9]*) DIRTY_N=0 ;; esac
529:DIRTY=0; [ "$DIRTY_N" -gt 0 ] && DIRTY=1
53
2. `Bash: {"command": "F=/tmp/tokeff-gate/f2/tree/scripts/wrap-ledger.sh; grep -noE '\\$\\{[A-Z][A-Z0-9_]*:-[^}]*\\}' $F | sort -t: -k3 -u | awk -F: '{print $1\": \"$2}' | sort -k2 -u; echo ---; grep -nE 'kill.?switch|off-switch|= *\"?off|!= *\"?off|off\\)|\"0\" *\\]|= *0 *\\]' $F | head -60", "description": `
   → 946: ${CC_BACKLOG_BIN
857: ${CC_CONVICTION_EPOCH
1315: ${CC_MIGRATIONS_STATE
396: ${CC_PANE_ID
1758: ${CC_POSTLAND_DIR
1263: ${CC_SESSIONS_BIN
591: ${DHASH
688: ${SID
278: ${TRANSCRIPT_FLAG
2241: ${TRUNK
400: ${UID
2144: ${WRAP_BUSY_TIMEOUT_S
379: ${WRAP_CACHE
400: ${WRAP_CACHE_DIR
376: ${WRAP_CACHE
3. `Bash: {"command": "F=/tmp/tokeff-gate/f2/tree/scripts/wrap-ledger.sh; grep -oE '\\$\\{?(WRAP|CC|CLAUDE)_[A-Z0-9_]+' $F | tr -d '${' | sort | uniq -c; echo ---; grep -nE '(WRAP|CC|CLAUDE)_[A-Z0-9_]+.{0,40}(off|\"0\"|=0|= 0| 0 )' $F | head -40; echo ---; grep -niE 'disable|kill' $F | head -40", "description`
   →    4 CC_BACKLOG_BIN
   1 CC_CONVICTION_EPOCH
   3 CC_CUSTODY_BIN
   1 CC_CUSTODY_DIR
   3 CC_DECIDE_BIN
   4 CC_MIGRATIONS_STATE
   2 CC_PANE_ID
   1 CC_POSTLAND_DIR
   1 CC_SESSIONS_BIN
   3 CC_WF_PSTABLE_FILE
   2 CC_WF_TEAM_ROOTS
   5 CLAUDE_CODE_SESSION_ID
   2 CLAUDE_CONFIG_DIR
   5 CLAUDE_SESS
4. `Bash: {"command": "F=/tmp/tokeff-gate/f2/tree/scripts/wrap-ledger.sh; for v in WRAP_GATE_GREEN WRAP_LIVE_REPO WRAP_LIVE_ADDS_MAX WRAP_LIVE_BUDGET_COMMITS WRAP_LIVE_BUDGET_MIN WRAP_TIMEOUT_BIN WRAP_LAND_INFLIGHT_LIB WRAP_SESSION_BUSY_LIB WRAP_TRANSCRIPT WRAP_PROJECT_ROOTS WRAP_DOD_FILE; do echo \"== $v\"; `
   → == WRAP_GATE_GREEN
181:# Env seams (tests): WRAP_TRUNK (the repo-local, non-test seam is `git config claude.trunk`) · WRAP_DOD_DIR · WRAP_DOD_FILE · WRAP_GATE_GREEN ·
387:    _wl_k="$_wl_k|${WRAP_TRUNK:-}|${WRAP_DOD_DIR:-}|${WRAP_DOD_FILE:-}|${WRAP_GATE_GREEN:-}"
563:GATE_FILE="${WRAP_GATE_GREEN:-$(
5. `Bash: {"command": "F=/tmp/tokeff-gate/f2/tree/scripts/wrap-ledger.sh; sed -n 1276,1290p $F; grep -n 'LIVE_ADDS_MAX' $F; grep -nE 'WRAP_RESIDENT|WRAP_BUSY[^_]' $F; sed -n 1088,1100p $F; sed -n 2110,2127p $F; grep -nE '\"\\$\\{?[A-Za-z_]+\\}?\" *(=|!=) *\"?(off|0|no)\"?' $F", "description": "Check remaining`
   → # The stale scan is O(paths the lag changes), not O(the live tree) — but a pathological range would
# still put a per-path readlink+hash on a Stop-hook path. Past the cap the answer is `?`, never 0.
LIVE_STALE_MAX="${WRAP_LIVE_STALE_MAX:-200}"
# The added-file scan stats one path under $LIVE_ROOT pe
6. `Bash: {"command": "mkdir -p /tmp/tokeff-gate/f2/out/B10-r3 && cat > /tmp/tokeff-gate/f2/out/B10-r3/answer.md <<'EOF'\n# Kill switches in scripts/wrap-ledger.sh\n\nThere are **3** environment-variable kill switches. Each defaults to on and disables a section when set to off.\n\n| # | Variable | Line | Acce`
   → (Bash completed with no output)
7. `StructuredOutput: {"answer_path": "/tmp/tokeff-gate/f2/out/B10-r3/answer.md", "headline": "wrap-ledger.sh has three kill switches: WRAP_CACHE (line 379; off/0/no/OFF/NO turns off the ledger memo cache), WRAP_RESIDENT (line 1160; off turns off the resident-team-member check) and WRAP_BUSY (line 2137; off turns off the`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
