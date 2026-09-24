# Dossier 8

## Brief
```
In /tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh, which environment variables act as kill switches or off-switches (a variable that, when set to off/0, disables a section or check)? For each give the variable, the line, and what it turns off. numbers: {"kill_switches": <how many>}.
```

## Returned headline
wrap-ledger.sh has 3 kill switches. WRAP_CACHE (line 379) turns off the memo cache and also accepts 0 and no. WRAP_RESIDENT (line 1160) turns off the resident-teammate check. WRAP_BUSY (line 2137) turns off the working-vs-idling probe. The last two react to "off" only.

## Returned numbers
`{"kill_switches": 3}`

## answer.md
# Kill switches in scripts/wrap-ledger.sh

The file has **3** environment-variable kill switches. Every other `WRAP_*` / `CC_*` variable is a test seam: a path, a timeout, or a budget. None of those turns a section off when set to off or 0.

| # | Variable | Line | Off values | What it turns off |
|---|---|---|---|---|
| 1 | `WRAP_CACHE` | 379 (documented at 276) | `off`, `0`, `no`, `OFF`, `NO` (default `on`) | The ledger's memo cache: "never read, never write" (the benchmark's control arm). It works by blanking `WL_TRANSCRIPT`, the cache-key variable. The memo block at line 380 is gated on `[ -n "$WL_TRANSCRIPT" ]`, so it never runs. `GOAL_TRANSCRIPT` is copied earlier (line 285), so the goal-liveness read keeps working. |
| 2 | `WRAP_RESIDENT` | 1160 (in `count_resident_members`, called at 2016) | `off` only (default `on`) | The resident-team-member check (`RESIDENT_MINE`). This is the 🔧 rung that names live teammates of this session that were never sent a shutdown. The function returns early with `RESIDENT_SRC=none`, so no member is ever reported. |
| 3 | `WRAP_BUSY` | 2137 | `off` only (the test is `!= "off"`; default `on`) | The "WORKING vs IDLING" probe. It stops `hooks/lib/session-busy.sh` from being sourced, so neither `session_busy_live` nor `sb_permpend` runs. `BUSY`, `BUSY_STATE`, `BUSY_SUSPECT`, `BUSY_AGE`, `BUSY_SRC`, `BUSY_SAMPLE`, `PERMPEND` and `PERMPEND_AGE` stay at their defaults (`BUSY=0`, `BUSY_STATE=UNKNOWN`, `BUSY_SRC=none`). These are reported fields only; they never set the rung. |

Notes:
- Only `WRAP_CACHE` accepts `0`/`no`. `WRAP_RESIDENT` and `WRAP_BUSY` react to the literal `off` only.
- These do **not** count as kill switches:
  - `WRAP_TIMEOUT_BIN` (line 768): a non-executable value makes the script run without a timeout wrapper; it disables no check.
  - The `*_TIMEOUT_S` variables and the `WRAP_LIVE_*_MAX` / `WRAP_LIVE_BUDGET_*` variables are bounds. Non-numeric budgets fall back to the defaults (lines 1313-1314), not to "disabled".


## Tool calls (9) with the first 300 chars of each result
1. `Bash: {"command": "F=/tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh; wc -l $F; grep -nE '\\$\\{?[A-Z_][A-Z0-9_]*(:-[^}]*)?\\}?\"? *(=|!=|==) *\"?(off|0|OFF|false|1|on)' $F | head -80"}`
   →     2444 /tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh
1160:  [ "${WRAP_RESIDENT:-on}" = "off" ] && { RESIDENT_SRC="none"; return 0; }
2137:if [ "${WRAP_BUSY:-on}" != "off" ] && [ -f "$_wl_sbl" ]; then
2. `Bash: {"command": "F=/tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh; grep -nE '(off|kill|disable|switch|=[\" ]*0[\"} ]|-eq 0|-ne 0)' $F | grep -E '\\$\\{?[A-Z]' | grep -vE '^\\s*[0-9]+:\\s*#' | head -80; echo ---; grep -nEi 'kill.?switch|off-switch|opt.?out|disable' $F | head -60"}`
   → 379:case "${WRAP_CACHE:-on}" in off|0|no|OFF|NO) WL_TRANSCRIPT="" ;; esac
528:DIRTY_N="$(printf '%s' "$PORC" | grep -c . 2>/dev/null || echo 0)"; case "$DIRTY_N" in ''|*[!0-9]*) DIRTY_N=0 ;; esac
534:  AHEAD="$(git rev-list --count "$TRUNK"..HEAD 2>/dev/null || echo 0)"; case "$AHEAD" in ''|*[!0-9]*
3. `Bash: {"command": "F=/tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh; grep -noE '\\$\\{[A-Z][A-Z0-9_]*:-[^}]*\\}' $F | sort -t: -k3 -u | awk -F: '{print $1\": \"$2}' | sort -u -k2 | head -100"}`
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
4. `Bash: {"command": "F=/tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh; sed -n '268,290p;370,382p;558,570p;1150,1162p;1266,1320p;2128,2140p' $F"}`
   → #   · THE SEAMS ARE IN THE KEY because two consumers do NOT call this identically:
#     completion-assert passes `--session $SID`, the other six do not, and the resolved SID changes
#     YOURS/BLOCKED. Keying on the raw INPUTS (all three session sources, not the resolved one)
#     cannot drift ou
5. `Bash: {"command": "F=/tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh; grep -noE '\\b(WRAP|CC|CLAUDE)_[A-Z0-9_]+' $F | awk -F: '{print $2}' | sort | uniq -c; grep -nE 'WRAP_(RESIDENT|BUSY|CACHE)\\b' $F | head -30; grep -nE '=off|=0 ' $F | head"}`
   →    6 CC_BACKLOG_BIN
   1 CC_BUSY_CUSTODY_OPEN
   2 CC_CONVICTION_EPOCH
   3 CC_CUSTODY_BIN
   1 CC_CUSTODY_DIR
   4 CC_DECIDE_BIN
   2 CC_DEPLOY_MAX_LAG_COMMITS
   3 CC_DEPLOY_MAX_LAG_HOURS
   5 CC_MIGRATIONS_STATE
   2 CC_PANE_ID
   1 CC_POSTLAND_DIR
   2 CC_SESSIONS_BIN
   4 CC_WF_PSTABLE_FILE
   
6. `Bash: {"command": "F=/tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh; sed -n '175,195p' $F; grep -nE 'CC_BUSY_CUSTODY_OPEN|WRAP_TIMEOUT_BIN|_TIMEOUT_S' $F | head -40"}`
   → # ── LAW ── fail-LOUD, never fail-silent-open: outside a git repo (or on a read error) this exits
#   non-zero with a stderr note and NEVER prints RUNG=✅. A consumer that can't get a ledger must
#   treat that as "cannot confirm", not as "complete". Pure-read of the REPO: the only bytes this
#   wri
7. `Bash: {"command": "F=/tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh; sed -n '2110,2128p;2140,2175p' $F; grep -n 'count_resident_members' $F"}`
   →       # The mirror image, and it gets its own line for the same reason the one above does: naming
      # the arm that DID clear is the only way the reader can tell an applied budget from an
      # abstained one. "the converge budget" would assert both.
      RUNG="✅"; READOUT="✅ Complete & landed 
8. `Bash: {"command": "mkdir -p /tmp/tokeff-regate/f2/out/B10-r7 && cat > /tmp/tokeff-regate/f2/out/B10-r7/answer.md <<'EOF'\n# Kill switches in scripts/wrap-ledger.sh\n\nThe file has **3** environment-variable kill switches. Every other `WRAP_*` / `CC_*` variable is a test seam: a path, a timeout, or a budge`
   → (Bash completed with no output)
9. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B10-r7/answer.md", "headline": "wrap-ledger.sh has 3 kill switches. WRAP_CACHE (line 379) turns off the memo cache and also accepts 0 and no. WRAP_RESIDENT (line 1160) turns off the resident-teammate check. WRAP_BUSY (line 2137) turns off the working-vs-idl`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
