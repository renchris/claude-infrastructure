# Dossier 6

## Brief
```
In /tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh, which environment variables act as kill switches or off-switches (a variable that, when set to off/0, disables a section or check)? For each give the variable, the line, and what it turns off. numbers: {"kill_switches": <how many>}.
```

## Returned headline
wrap-ledger.sh has 3 kill switches, found by reading the code. WRAP_CACHE at line 379 (off|0|no|OFF|NO) turns off memo-cache reads and writes. WRAP_RESIDENT at line 1160 (=off only) turns off the resident-team-member count. WRAP_BUSY at line 2137 (=off only) turns off the working/idling busy probe. WRAP_TIMEOUT_BIN is a test seam that can remove the timeout bound, so it is noted but not counted.

## Returned numbers
`{"kill_switches": 3}`

## answer.md
# Kill switches in scripts/wrap-ledger.sh

File: /tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh (2444 lines, measured with `wc -l`).
Method: I grepped every `${VAR...}` reference (`grep -oE '\$\{?[A-Z][A-Z0-9_]*'`) and every
comparison against `off` / `0` / `no`, then read the code around each hit.

## Kill switches (3)

| # | Variable | Line | Test | What it turns off |
|---|----------|------|------|-------------------|
| 1 | `WRAP_CACHE` | 379 (documented at 276: "Kill switch: WRAP_CACHE=off\|0\|no ⇒ never read, never write") | `case "${WRAP_CACHE:-on}" in off\|0\|no\|OFF\|NO) WL_TRANSCRIPT="" ;; esac` | Turns off the memo cache for `--machine` mode. Blanking `WL_TRANSCRIPT` stops the cache key (`WL_KEY`/`WL_FILE`/`WL_LOCK`, lines 380-409) from being built, so the script never reads or writes a cache file under `$WRAP_CACHE_DIR` / `${TMPDIR}/cc-wrap-ledger.$UID` and never takes the lock (line 415 onward). This is the benchmark's control arm. The transcript is still available as an input through `GOAL_TRANSCRIPT`, which is copied at line 285 before the blanking. Accepts `off`, `0`, `no`, `OFF` and `NO`. |
| 2 | `WRAP_RESIDENT` | 1160 (listed as an env seam at 186) | `[ "${WRAP_RESIDENT:-on}" = "off" ] && { RESIDENT_SRC="none"; return 0; }` | Turns off `count_resident_members`, the check for resident team members (called at line 2016). It skips the team-config lookup, the `ps` scan, the dirty-file probe and the sessions-bin lookup. `RESIDENT_MINE` stays 0 and `RESIDENT_SRC=none`, so the resident-member 🔧 rung cannot fire. Only the exact string `off` works; `0` does NOT disable it. |
| 3 | `WRAP_BUSY` | 2137 | `if [ "${WRAP_BUSY:-on}" != "off" ] && [ -f "$_wl_sbl" ]; then` | Turns off the ⏳ WORKING-vs-IDLING section, which sources `session-busy.sh` and runs `session_busy_live` and `sb_permpend`. The fields keep their initial values from line 2133: `BUSY=0`, `BUSY_STATE=UNKNOWN`, `BUSY_SRC=none`, `BUSY_AGE=0`, `BUSY_SUSPECT=0`, `PERMPEND=0`. These are reported fields, not a rung. Only the exact string `off` works; `0` does NOT disable it. |

numbers: kill_switches = 3

## Close call, not counted
- `WRAP_TIMEOUT_BIN` (lines 763-770): if it is set to a value that is not executable, the script
  runs with "no bounder", so every `_bounded` call (line 783) runs without a timeout. The comment
  calls it a test seam that picks the timeout binary, not an off-switch for a section or check, so
  I left it out of the count. A value such as `off` or `0` would still have that effect, because
  neither is an executable path.

## Ruled out
The other variables are paths, directories, budgets, timeouts or session and trunk overrides.
Examples: `WRAP_LIVE_BUDGET_*`, `WRAP_*_TIMEOUT_S`, `WRAP_CACHE_WAIT_*`, `WRAP_LIVE_STALE_MAX`,
`WRAP_LIVE_ADDS_MAX`, `CC_*_BIN`, `WRAP_DOD_*`, `WRAP_GATE_GREEN`, `CC_CONVICTION_EPOCH`. None of
them has an off/0 branch. Budget values that are not numbers fall back to the defaults (lines
1311-1312); they are never treated as disabled.


## Tool calls (10) with the first 300 chars of each result
1. `Bash: {"command": "wc -l /tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh; grep -nE '\\$\\{?[A-Z_]+' /tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh | head -100; ls /tmp/tokeff-regate/f2/out/B10-r8/ 2>&1", "description": "Inspect script size and env var references"}`
   →     2444 /tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh
69:#   Session id: --session > $WRAP_SESSION_ID > $CLAUDE_SESSION_ID > unresolvable. Unresolvable ⇒
83:#   $WRAP_LIVE_REPO's `origin` URL is byte-equal to THIS repo's. Different origin ⇒ LIVE_SRC=n-a
98:#   ($CC_MIGRATIONS_STATE/failed/*.jso
2. `Bash: {"command": "F=/tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh; grep -nE 'off\\|0|0\\|off|= *\"?off\"?|= *\"?0\"?.*\\$\\{?[A-Z]|:-on\\}|:-1\\}|kill.?switch|off-switch|disable' $F | head -80", "description": "Search for off/0 switch patterns"}`
   → 276:# Kill switch: WRAP_CACHE=off|0|no ⇒ never read, never write (the benchmark's control arm).
279:# The transcript as an INPUT, kept out of the cache kill-switch's reach. $WL_TRANSCRIPT is a
280:# CACHE-KEY variable and `WRAP_CACHE=off` BLANKS it (below) — so a term that read the transcript
379:ca
3. `Bash: {"command": "F=/tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh; grep -noE '\\$\\{[A-Z][A-Z0-9_]*:-[^}]*\\}' $F | sort -t: -k3 -u | awk -F: '{print $1\": \"$2}' ; echo ---; grep -nE '(WRAP|CC)_[A-Z_]+[^A-Za-z_]' $F | grep -nE '\"0\"|= 0|-eq 0|off|OFF|\"no\"|false' | head -40", "description": "List `
   → 386: ${WRAP_SESSION_ID
946: ${CC_BACKLOG_BIN
1263: ${CC_SESSIONS_BIN
549: ${WRAP_LAND_INFLIGHT_LIB
2135: ${WRAP_SESSION_BUSY_LIB
563: ${WRAP_GATE_GREEN
688: ${SID
396: ${CC_PANE_ID
400: ${WRAP_CACHE_DIR
278: ${TRANSCRIPT_FLAG
1275: ${WRAP_LIVE_ROOT
588: ${WRAP_DOD_DIR
1315: ${CC_MIGRATIONS_STATE
175
4. `Bash: {"command": "F=/tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh; grep -oE '\\$\\{?[A-Z][A-Z0-9_]*' $F | tr -d '${' | sort | uniq -c | sort -rn | awk '{print $2}' | tr '\\n' ' '; echo; sed -n 1150,1165p $F; echo ----; sed -n 1265,1315p $F; echo ---; sed -n 700,720p $F; echo ---; sed -n 2128,2150p $F`
   → SID TRUNK HOME LIVE_REPO LIVE_ADDS LIVE_LAG PWD WRAP_LIVE_TIMEOUT_S WL_DIR LIVE_SHA LIVE_ROOT HEAD_SHA LIVE_AGE WL_FILE LIVE_SRC GOAL_LAST_T FILED_SRC CUSTODY_OPEN CUSTODY_MINE BLOCKED YOURS WL_LOCK MIG_FAILED LIVE_DIVERGED LIVE_BUDGET_COMMITS GOAL_EVALS CUSTODY_UNK WL_TRANSCRIPT UNCONVICTED_MINE SI
5. `Bash: {"command": "F=/tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh; grep -nE 'WRAP_TIMEOUT_BIN|WRAP_PROJECT_ROOTS|CC_WF_PSTABLE_FILE|CC_WF_TEAM_ROOTS|WRAP_LIVE_TIMEOUT_S|WRAP_DECIDE_TIMEOUT_S|WRAP_CUSTODY_TIMEOUT_S|WRAP_BACKLOG_TIMEOUT_S|CLAUDE_CONFIG_DIR|CC_POSTLAND_DIR|_bounded\\(\\)' $F; grep -n '^`
   → 58:#   bounded fork (`WRAP_DECIDE_TIMEOUT_S`, default 5s) per turn close is the price of a rung that
184:#                    WRAP_BACKLOG_TIMEOUT_S · WRAP_DECIDE_TIMEOUT_S · WRAP_TRANSCRIPT ·
185:#                    WRAP_GOAL_TIMEOUT_S · WRAP_PROJECT_ROOTS ·
186:#                    WRAP_RESIDENT 
6. `Bash: {"command": "F=/tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh; sed -n 760,782p $F; echo ---; sed -n 175,195p $F; echo ---; sed -n 270,290p $F; grep -nE 'WRAP_RESIDENT|WRAP_BUSY[^_]' $F", "description": "Read timeout seam and header env list"}`
   → # fail-open default that mimics the healthy state is unfalsifiable by its own output (MEMORY.md
# fail-safe-default-mimics-the-healthy-state): before this, a bounded run and an unbounded one were
# byte-identical in every surface this script emits, which is why the degradation ran unseen.
# Seam: WR
7. `Bash: {"command": "F=/tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh; sed -n 2110,2128p $F; sed -n 2150,2175p $F; sed -n 1120,1138p $F; grep -n 'count_resident_members' $F", "description": "Read context of busy and resident sections"}`
   →       # The mirror image, and it gets its own line for the same reason the one above does: naming
      # the arm that DID clear is the only way the reader can tell an applied budget from an
      # abstained one. "the converge budget" would assert both.
      RUNG="✅"; READOUT="✅ Complete & landed 
8. `Bash: {"command": "F=/tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh; sed -n 1100,1119p $F | head -20; sed -n 2008,2022p $F", "description": "Read resident section header and call site"}`
   → #
# THE MATCH IS THE THREE-FLAG CONJUNCTION, NEVER `pgrep -f <name>` (MEMORY.md
# pgrep-f-matches-agent-briefs; the same trap hooks/lib/agent-identity.sh:24-29 and
# handoff-fire.sh:949-957 each document after being bitten). `ps -o command=` flattens argv, so a
# session whose BRIEF merely MENTIONS 
9. `Bash: {"command": "cat > /tmp/tokeff-regate/f2/out/B10-r8/answer.md <<'EOF'\n# Kill switches in scripts/wrap-ledger.sh\n\nFile: /tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh (2444 lines, measured with `wc -l`).\nMethod: I grepped every `${VAR...}` reference (`grep -oE '\\$\\{?[A-Z][A-Z0-9_]*'`) and ev`
   → (Bash completed with no output)
10. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B10-r8/answer.md", "headline": "wrap-ledger.sh has 3 kill switches, found by reading the code. WRAP_CACHE at line 379 (off|0|no|OFF|NO) turns off memo-cache reads and writes. WRAP_RESIDENT at line 1160 (=off only) turns off the resident-team-member count. W`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
