# Dossier 5

## Brief
```
In /tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh, which environment variables act as kill switches or off-switches (a variable that, when set to off/0, disables a section or check)? For each give the variable, the line, and what it turns off. numbers: {"kill_switches": <how many>}.
```

## Returned headline
wrap-ledger.sh has 3 environment-variable kill switches: WRAP_CACHE (line 379, turns off the ledger memo cache when set to off, 0 or no), WRAP_RESIDENT (line 1160, turns off the resident-members check when set to off) and WRAP_BUSY (line 2137, turns off the busy/idle probe when set to off). I found them by grepping every ${VAR:-...} default and reading each hit in context.

## Returned numbers
`{"kill_switches": 3}`

## answer.md
# Kill switches in scripts/wrap-ledger.sh

File: /tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh (2444 lines, measured with `wc -l`).

The script has **3** environment-variable kill switches (measured: I grepped every `${VAR:-...}` default and every off/0/no comparison, then read each hit in context).

| # | Variable | Line | Test | What it turns off |
|---|----------|------|------|-------------------|
| 1 | `WRAP_CACHE` | 379 | `case "${WRAP_CACHE:-on}" in off\|0\|no\|OFF\|NO) WL_TRANSCRIPT="" ;; esac` | The machine-mode ledger memo cache. The line blanks the cache-key transcript `WL_TRANSCRIPT`, so the cache is never read and never written. The comment at line 276 calls it the "Kill switch" and the benchmark's control arm. The transcript still reaches goal facts through `GOAL_TRANSCRIPT`, which is set at line 285 before this line runs. Default: on. |
| 2 | `WRAP_RESIDENT` | 1160 | `[ "${WRAP_RESIDENT:-on}" = "off" ] && { RESIDENT_SRC="none"; return 0; }` | The resident-members check (`count_resident_members`, called at line 2016). This check finds live teammate processes this session started and never ended, and feeds the 🔧 arm. When the switch is set, the function returns early with `RESIDENT_SRC=none` and the result stays at 0. Only the exact value `off` works. Default: on. |
| 3 | `WRAP_BUSY` | 2137 | `if [ "${WRAP_BUSY:-on}" != "off" ] && [ -f "$_wl_sbl" ]; then` | The WORKING vs IDLING busy probe. It sources `hooks/lib/session-busy.sh` and runs `session_busy_live`. When the switch is set, the BUSY and PERMPEND fields keep their defaults: `BUSY=0`, `BUSY_STATE=UNKNOWN`, `BUSY_SRC=none`. Only the exact value `off` works. Default: on. |

## Variables I checked and left out
- `DRAIN_SCOPE` (line 942, `${DRAIN_SCOPE:-0}`) is not an environment switch. The script sets it itself at line 601 (`DRAIN_SCOPE=0`) and line 627, from the DoD scope.
- `WRAP_TIMEOUT_BIN` (lines 763-769): a non-executable value pins "no bounder". It is a seam that picks a timeout binary, not an off-switch.
- The numeric thresholds (`WRAP_LIVE_STALE_MAX`, `WRAP_LIVE_ADDS_MAX`, `WRAP_LIVE_BUDGET_COMMITS`, `WRAP_LIVE_BUDGET_MIN`, `*_TIMEOUT_S`): setting them to 0 makes the checks stricter or shorter. It does not disable them.
- Path and binary seams (`WRAP_CACHE_DIR`, `WRAP_GATE_GREEN`, `WRAP_LIVE_REPO`, `CC_*_BIN`, and so on) change where the script reads from. They do not turn anything off.


## Tool calls (9) with the first 300 chars of each result
1. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/scripts && wc -l wrap-ledger.sh && grep -n '\\${\\?[A-Z_][A-Z0-9_]*' wrap-ledger.sh | grep -niE 'off|:-0|:-1|== *\"?0|= *\"?0|disable|kill' ; ls /tmp/tokeff-regate/f2/out/B10-r1/ 2>&1", "description": "Find env-var off-switch candidates in script"}`
   → Exit code 1
    2444 wrap-ledger.sh
9:279:# The transcript as an INPUT, kept out of the cache kill-switch's reach. $WL_TRANSCRIPT is a
25:379:case "${WRAP_CACHE:-on}" in off|0|no|OFF|NO) WL_TRANSCRIPT="" ;; esac
37:400:      WL_DIR="${WRAP_CACHE_DIR:-${TMPDIR:-/tmp}/cc-wrap-ledger.${UID:-0}}"
64:528
2. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/scripts && grep -nE '\\$\\{[A-Z_][A-Z0-9_]*:-(on|1|0|off|yes|no)\\}' wrap-ledger.sh; echo ---; grep -nE '\"?off\"?|off\\|' wrap-ledger.sh | grep -v '^\\s*#' | head -60", "description": "Grep all env default-on/off patterns"}`
   → 379:case "${WRAP_CACHE:-on}" in off|0|no|OFF|NO) WL_TRANSCRIPT="" ;; esac
400:      WL_DIR="${WRAP_CACHE_DIR:-${TMPDIR:-/tmp}/cc-wrap-ledger.${UID:-0}}"
942:  [ "${DRAIN_SCOPE:-0}" -eq 1 ] || { CLOSE_FLOOR_SRC="n-a"; return 0; }
1160:  [ "${WRAP_RESIDENT:-on}" = "off" ] && { RESIDENT_SRC="none"; ret
3. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/scripts && grep -noE '\\$\\{?(WRAP|CC|WL|NO|SKIP|DISABLE)_[A-Z0-9_]*' wrap-ledger.sh | awk -F: '{print $3}' | sort | uniq -c; echo ---; grep -nE 'DISABLE|SKIP|NO_[A-Z]' wrap-ledger.sh | head; echo ---; sed -n 270,285p wrap-ledger.sh; sed -n 370,382p wrap-le`
   →  120 
---
496:  # TRUNK was assigned that bogus ref, and the `[ -n "$TRUNK" ]` guards below then SKIPPED the
2352:           # The rows half is read only on the ✅-eligible path; on a worse rung it was SKIPPED, and
---
#     YOURS/BLOCKED. Keying on the raw INPUTS (all three session sources, not the 
4. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/scripts && grep -oE '\\$\\{[A-Z][A-Z0-9_]*:-' wrap-ledger.sh | sort | uniq -c; echo ---; grep -nE 'DRAIN_SCOPE' wrap-ledger.sh | head; grep -nE 'WRAP_BUSY|WRAP_RESIDENT' wrap-ledger.sh", "description": "Enumerate env vars with defaults, check DRAIN_SCOPE"}`
   →    3 ${CC_BACKLOG_BIN:-
   1 ${CC_CONVICTION_EPOCH:-
   2 ${CC_CUSTODY_BIN:-
   1 ${CC_CUSTODY_DIR:-
   2 ${CC_DECIDE_BIN:-
   2 ${CC_MIGRATIONS_STATE:-
   2 ${CC_PANE_ID:-
   1 ${CC_POSTLAND_DIR:-
   1 ${CC_SESSIONS_BIN:-
   1 ${CC_WF_PSTABLE_FILE:-
   1 ${CC_WF_TEAM_ROOTS:-
   2 ${CLAUDE_CODE_SESS
5. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/scripts && grep -nE 'WRAP_GATE_GREEN|WRAP_LIVE_ROOT|WRAP_LIVE_REPO' wrap-ledger.sh; echo ---; grep -oE '\\$[A-Z][A-Z0-9_]*' wrap-ledger.sh | sort -u | tr '\\n' ' '; echo; sed -n 150,215p wrap-ledger.sh | grep -niE 'off|kill|disable|switch'", "description": `
   → 83:#   $WRAP_LIVE_REPO's `origin` URL is byte-equal to THIS repo's. Different origin ⇒ LIVE_SRC=n-a
181:# Env seams (tests): WRAP_TRUNK (the repo-local, non-test seam is `git config claude.trunk`) · WRAP_DOD_DIR · WRAP_DOD_FILE · WRAP_GATE_GREEN ·
182:#                    WRAP_SESSION_ID · CC_BACKLO
6. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/scripts && grep -nE 'LIVE_ADDS_MAX|LIVE_STALE_MAX|LIVE_BUDGET_(COMMITS|MIN)|CC_CONVICTION_EPOCH|WRAP_TIMEOUT_BIN' wrap-ledger.sh | grep -v '^3[89][0-9]:'", "description": "Check numeric thresholds for zero-disables semantics"}`
   → 91:#   PAST the converge budget is news: WRAP_LIVE_BUDGET_COMMITS (25) or WRAP_LIVE_BUDGET_MIN (360,
183:#                    WRAP_LIVE_BUDGET_COMMITS · WRAP_LIVE_BUDGET_MIN · CC_MIGRATIONS_STATE ·
763:# Seam: WRAP_TIMEOUT_BIN — an explicit path, and a NON-executable value pins "no bounder", which i
7. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/scripts && sed -n 1085,1100p wrap-ledger.sh; echo ...; sed -n 2112,2124p wrap-ledger.sh; grep -n 'count_resident_members' wrap-ledger.sh", "description": "Read resident and busy section descriptions"}`
   → }

# ── RESIDENT MEMBERS — live teammate processes THIS session started and never ended (the 🔧 arm) ──
# RC-2 of docs/plans/SUBAGENT_LIFECYCLE_ROOT_CAUSE.md, measured in
# docs/research/SUBAGENT_LIFECYCLE_ROOT_CAUSE_2026-09-19.md §3: the vendor requires the LEAD to end
# its members, and 58% of lead
8. `Bash: {"command": "mkdir -p /tmp/tokeff-regate/f2/out/B10-r1 && cat > /tmp/tokeff-regate/f2/out/B10-r1/answer.md <<'EOF'\n# Kill switches in scripts/wrap-ledger.sh\n\nFile: /tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh (2444 lines, measured with `wc -l`).\n\nThe script has **3** environment-variable k`
   → (Bash completed with no output)
9. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B10-r1/answer.md", "headline": "wrap-ledger.sh has 3 environment-variable kill switches: WRAP_CACHE (line 379, turns off the ledger memo cache when set to off, 0 or no), WRAP_RESIDENT (line 1160, turns off the resident-members check when set to off) and WRA`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
