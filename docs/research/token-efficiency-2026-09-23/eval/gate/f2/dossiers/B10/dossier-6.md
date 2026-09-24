# Dossier 6

## Brief
```
In /tmp/tokeff-gate/f2/tree/scripts/wrap-ledger.sh, which environment variables act as kill switches or off-switches (a variable that, when set to off/0, disables a section or check)? For each give the variable, the line, and what it turns off. numbers: {"kill_switches": <how many>}.
```

## Returned headline
wrap-ledger.sh has 3 kill switches: WRAP_CACHE at line 379 (off/0/no/OFF/NO) turns off the memo cache by blanking WL_TRANSCRIPT; WRAP_RESIDENT=off at line 1160 skips the resident-teammate check in count_resident_members; WRAP_BUSY=off at line 2137 skips the BUSY/permission-pending probe.

## Returned numbers
`{"kill_switches": 3}`

## answer.md
# Kill switches in scripts/wrap-ledger.sh

File: /tmp/tokeff-gate/f2/tree/scripts/wrap-ledger.sh (2444 lines, measured with `wc -l`).
Method (measured): grep for every `${WRAP_*}` / `${CC_*}` reference, every `off`/`0` comparison, and
every "kill switch" comment, then read the code around each hit.

**Count: 3 kill switches.**

| # | Variable | Line(s) | Accepted "off" values | What it turns off |
|---|----------|---------|-----------------------|-------------------|
| 1 | `WRAP_CACHE` | 379 (`case "${WRAP_CACHE:-on}" in off\|0\|no\|OFF\|NO) WL_TRANSCRIPT="" ;; esac`); documented at 276 ("Kill switch: WRAP_CACHE=off\|0\|no ⇒ never read, never write (the benchmark's control arm)") and 280 | `off`, `0`, `no`, `OFF`, `NO` | The ledger memo cache. It blanks `WL_TRANSCRIPT`, the cache-key input, so the `if [ "$MODE" = "machine" ] && [ -n "$WL_TRANSCRIPT" ]` block at line 380 never builds a key. The memo under `$WRAP_CACHE_DIR`/TMPDIR is never read or written. The transcript is still an input to the goal check: it was copied to `GOAL_TRANSCRIPT` at line 285, before the blanking, so the facts reported do not change. |
| 2 | `WRAP_RESIDENT` | 1160 (`[ "${WRAP_RESIDENT:-on}" = "off" ] && { RESIDENT_SRC="none"; return 0; }` in `count_resident_members`) | the literal `off` only | The resident-teammate check. It returns before it reads the team `config.json`, the `ps` table or the dirty-file probe. `RESIDENT_MINE` keeps its default of 0 (line 1130) and `RESIDENT_SRC=none`. |
| 3 | `WRAP_BUSY` | 2137 (`if [ "${WRAP_BUSY:-on}" != "off" ] && [ -f "$_wl_sbl" ]; then`) | the literal `off` only | The working-vs-idling (BUSY) probe. It skips sourcing `session-busy.sh`, the `session_busy_live` call and the `sb_permpend` permission-pending check. The fields keep their defaults from line 2133: `BUSY=0`, `BUSY_STATE=UNKNOWN`, `BUSY_SRC=none`, `PERMPEND=0`. |

## Notes / near-misses (not counted)
- Only `WRAP_CACHE` accepts `0`. For `WRAP_RESIDENT` and `WRAP_BUSY`, setting the variable to `0` has
  no effect: each tests the exact string `off`.
- `WRAP_TIMEOUT_BIN` (lines 763-770): a non-executable value makes the script run with no timeout
  bounder at all. It is a test seam that takes a path, not an off/0 switch, so it is excluded.
- `WRAP_BUSY` does not appear in the "Env seams" header list (lines 181-189), while `WRAP_RESIDENT` and `WRAP_CACHE` do.
- All other `WRAP_*`/`CC_*` variables set paths, timeouts, budgets or binaries (for example
  `WRAP_*_TIMEOUT_S`, `WRAP_LIVE_BUDGET_*`, `CC_*_BIN`). None of them has off/0 semantics that
  disables a section.


## Tool calls (8) with the first 300 chars of each result
1. `Bash: {"command": "wc -l /tmp/tokeff-gate/f2/tree/scripts/wrap-ledger.sh; grep -nE '\\$\\{?[A-Z_][A-Z0-9_]*' /tmp/tokeff-gate/f2/tree/scripts/wrap-ledger.sh | grep -nE 'off|OFF|\"0\"|= *0|:-1|:-on|DISABLE|SKIP|KILL|ENABLE' ; ls /tmp/tokeff-gate/f2/out/B10-r8/ 2>&1", "description": "Scan script for switch-`
   →     2444 /tmp/tokeff-gate/f2/tree/scripts/wrap-ledger.sh
25:379:case "${WRAP_CACHE:-on}" in off|0|no|OFF|NO) WL_TRANSCRIPT="" ;; esac
59:496:  # TRUNK was assigned that bogus ref, and the `[ -n "$TRUNK" ]` guards below then SKIPPED the
64:528:DIRTY_N="$(printf '%s' "$PORC" | grep -c . 2>/dev/null ||
2. `Bash: {"command": "F=/tmp/tokeff-gate/f2/tree/scripts/wrap-ledger.sh; grep -noE '\\$\\{[A-Z][A-Z0-9_]*:-[^}]*\\}' $F | sort -t: -k3 -u | head -80; echo ---; grep -nE '(off|OFF)[|)\"]' $F | head -40; echo ---; grep -nE '\\] *(=|!=) *\"?(0|off)\"?' $F | head -40", "description": "List env vars with defaults`
   → 386:${WRAP_SESSION_ID:-}
946:${CC_BACKLOG_BIN:-$(command -v cc-backlog 2>/dev/null || true)}
1263:${CC_SESSIONS_BIN:-$(command -v cc-sessions 2>/dev/null || true)}
549:${WRAP_LAND_INFLIGHT_LIB:-$(dirname "$0")/../hooks/lib/land-inflight.sh}
2135:${WRAP_SESSION_BUSY_LIB:-$(dirname "$0")/../hooks/lib/
3. `Bash: {"command": "F=/tmp/tokeff-gate/f2/tree/scripts/wrap-ledger.sh; grep -noE '\\$\\{?(WRAP|CC|LR|NO|SKIP|DISABLE)_[A-Z0-9_]*' $F | awk -F: '{print $2}' | sort | uniq -c; echo ---; grep -niE 'kill.?switch|off-switch|disable' $F | head -30", "description": "Enumerate env var references and kill-switch co`
   →    3 ${CC_BACKLOG_BIN
   1 ${CC_CONVICTION_EPOCH
   2 ${CC_CUSTODY_BIN
   1 ${CC_CUSTODY_DIR
   2 ${CC_DECIDE_BIN
   2 ${CC_MIGRATIONS_STATE
   2 ${CC_PANE_ID
   1 ${CC_POSTLAND_DIR
   1 ${CC_SESSIONS_BIN
   2 ${CC_WF_PSTABLE_FILE
   2 ${CC_WF_TEAM_ROOTS
   2 ${WRAP_BACKLOG_TIMEOUT_S
   1 ${WRAP_BUS
4. `Bash: {"command": "F=/tmp/tokeff-gate/f2/tree/scripts/wrap-ledger.sh; sed -n 270,290p $F; echo ....; sed -n 370,384p $F; echo ....; sed -n 1150,1162p $F; echo ....; sed -n 2125,2140p $F; echo ....; grep -nE 'TIMEOUT_S|WRAP_TIMEOUT_BIN|BUDGET|STALE_MAX|ADDS_MAX|WRAP_PROJECT_ROOTS|WRAP_TRUNK|WRAP_DOD_FILE' `
   → #     YOURS/BLOCKED. Keying on the raw INPUTS (all three session sources, not the resolved one)
#     cannot drift out of step with the resolution order below the way a duplicated precedence
#     would.
#   · THE FULL KEY IS STORED IN THE FILE AND COMPARED ON READ, so a cksum collision costs a miss
5. `Bash: {"command": "F=/tmp/tokeff-gate/f2/tree/scripts/wrap-ledger.sh; sed -n 176,195p $F; echo ....; grep -nE '=off|= *off|off\\b.*⇒|WRAP_RESIDENT[^_]|WRAP_BUSY[^_]' $F | head; echo ....; sed -n 760,790p $F; grep -nE '^_bounded\\(\\)' $F", "description": "Read header seams and bounder logic"}`
   → #   non-zero with a stderr note and NEVER prints RUNG=✅. A consumer that can't get a ledger must
#   treat that as "cannot confirm", not as "complete". Pure-read of the REPO: the only bytes this
#   writes are its own memo under TMPDIR (below) — which is why the live-layer read never fetches
#   (se
6. `Bash: {"command": "F=/tmp/tokeff-gate/f2/tree/scripts/wrap-ledger.sh; sed -n 2140,2185p $F | cut -c1-160; echo ....; sed -n 1140,1148p $F; grep -nE '^RESIDENT_MINE=|RESIDENT_SRC=' $F | head -5", "description": "Read busy block and resident defaults"}`
   →   if . "$_wl_sbl" 2>/dev/null && command -v session_busy_live >/dev/null 2>&1; then
    # shellcheck disable=SC2016   # single quotes deliberate: this is the CHILD shell's script,
    # and $1..$4 are its positional parameters, passed after the `_` argv0 placeholder below.
    _wl_sbo="$(CC_BUSY_CUS
7. `Bash: {"command": "mkdir -p /tmp/tokeff-gate/f2/out/B10-r8 && cat > /tmp/tokeff-gate/f2/out/B10-r8/answer.md <<'EOF'\n# Kill switches in scripts/wrap-ledger.sh\n\nFile: /tmp/tokeff-gate/f2/tree/scripts/wrap-ledger.sh (2444 lines, measured with `wc -l`).\nMethod (measured): grep for every `${WRAP_*}` / `${`
   → ok
8. `StructuredOutput: {"answer_path": "/tmp/tokeff-gate/f2/out/B10-r8/answer.md", "headline": "wrap-ledger.sh has 3 kill switches: WRAP_CACHE at line 379 (off/0/no/OFF/NO) turns off the memo cache by blanking WL_TRANSCRIPT; WRAP_RESIDENT=off at line 1160 skips the resident-teammate check in count_resident_members; WRAP_B`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
