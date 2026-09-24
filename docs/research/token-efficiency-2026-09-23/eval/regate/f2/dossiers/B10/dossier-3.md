# Dossier 3

## Brief
```
In /tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh, which environment variables act as kill switches or off-switches (a variable that, when set to off/0, disables a section or check)? For each give the variable, the line, and what it turns off. numbers: {"kill_switches": <how many>}.
```

## Returned headline
wrap-ledger.sh has 3 kill switches: WRAP_CACHE (line 379, off/0/no turns off the machine-ledger memo cache), WRAP_RESIDENT (line 1160, only the exact value "off" skips the resident-teammate check), and WRAP_BUSY (line 2137, only the exact value "off" skips the session-busy and permission-pending probe).

## Returned numbers
`{"kill_switches": 3}`

## answer.md
# Kill switches in scripts/wrap-ledger.sh

**Answer: 3 environment variables act as kill switches.** All three default to `on` and are checked with `${VAR:-on}`.

| # | Variable | Line | Off values | What it turns off |
|---|---|---|---|---|
| 1 | `WRAP_CACHE` | 379 (documented at 276: "Kill switch: WRAP_CACHE=off\|0\|no ⇒ never read, never write (the benchmark's control arm)") | `off`, `0`, `no`, `OFF`, `NO` | The memo cache of the `--machine` ledger. `case "${WRAP_CACHE:-on}" in off\|0\|no\|OFF\|NO) WL_TRANSCRIPT="" ;; esac` blanks the cache-key transcript, so the `if [ "$MODE" = "machine" ] && [ -n "$WL_TRANSCRIPT" ]` block (line 380 on) never builds a key, reads or writes the cache under `WRAP_CACHE_DIR`. The goal check still gets the transcript through `GOAL_TRANSCRIPT`, which is copied at line 285, before the blanking. |
| 2 | `WRAP_RESIDENT` | 1160 | `off` only (exact string) | The resident-team-member check in `count_resident_members()`: `[ "${WRAP_RESIDENT:-on}" = "off" ] && { RESIDENT_SRC="none"; return 0; }`. RESIDENT_MINE stays 0, so no 🔧 is raised for teammates still running, and their dirty files are not listed. This is the "Kill switch `WRAP_RESIDENT=off`" named in the global CLAUDE.md. |
| 3 | `WRAP_BUSY` | 2137 | `off` only (exact string) | The session-busy / permission-pending probe: `if [ "${WRAP_BUSY:-on}" != "off" ] && [ -f "$_wl_sbl" ]; then` skips sourcing `hooks/lib/session-busy.sh` and `session_busy_live`. The fields keep their defaults (BUSY=0, BUSY_STATE=UNKNOWN, BUSY_SRC=none, PERMPEND=0). |

## Not counted
- `WRAP_TIMEOUT_BIN` (lines 763–769): setting it to a non-executable value pins "no bounder". It is a test seam that changes how timeouts are enforced. It is not an on/off switch that skips a section.
- `WRAP_LIVE_STALE_MAX` / `WRAP_LIVE_ADDS_MAX` (lines 1278, 1283), `WRAP_LIVE_BUDGET_*`, and the `*_TIMEOUT_S` variables: these are caps, budgets and timeouts. Setting one to 0 changes a threshold; for example a 0 cap makes the scan answer `?`. It does not disable a check.
- The other `WRAP_*` and `CC_*` variables are path or seam overrides (see the "Env seams" header, lines 181–189).


## Tool calls (7) with the first 300 chars of each result
1. `Bash: {"command": "F=/tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh; wc -l $F; grep -nE '(=|==|!=) *\"?(off|0)\"?|:-on|:-1\\}|kill.switch|Kill switch|off-switch' $F | head -100", "description": "Search wrap-ledger for kill switch patterns"}`
   →     2444 /tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh
30:#     ✅  clean ∧ not-stale ∧ landed ∧ remainder = 0 ∧ no unrun operator step from this session
52:#   that cannot (MEMORY.md alarm-polarity). Unresolvable session ⇒ BLOCKED=0 + BLOCKED_SRC=none;
53:#   unreadable store ⇒ BLOCKED=0 + BLOCK
2. `Bash: {"command": "F=/tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh; grep -nE '\\$\\{[A-Z_]+:-(on|1|yes|true)\\}' $F; echo ---; grep -nE '\"\\$\\{?[A-Z][A-Z0-9_]*\\}?\" *(=|!=) *\"?(off|0|no)\"?|\\$\\{[A-Z][A-Z0-9_]*:-[^}]*\\}\" *(=|!=) *\"?(off|0|no)' $F; echo ---; grep -niE 'kill|switch|disable' $F |`
   → 379:case "${WRAP_CACHE:-on}" in off|0|no|OFF|NO) WL_TRANSCRIPT="" ;; esac
1160:  [ "${WRAP_RESIDENT:-on}" = "off" ] && { RESIDENT_SRC="none"; return 0; }
2137:if [ "${WRAP_BUSY:-on}" != "off" ] && [ -f "$_wl_sbl" ]; then
---
1160:  [ "${WRAP_RESIDENT:-on}" = "off" ] && { RESIDENT_SRC="none"; return 
3. `Bash: {"command": "F=/tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh; sed -n 270,300p $F; sed -n 370,395p $F; grep -nE 'WRAP_CACHE|WRAP_RESIDENT|WRAP_BUSY' $F; echo ---; grep -oE '\\$\\{[A-Z][A-Z0-9_]*:-[^}]*\\}' $F | sort | uniq -c", "description": "Inspect cache section and all defaulted env vars"}`
   → #     YOURS/BLOCKED. Keying on the raw INPUTS (all three session sources, not the resolved one)
#     cannot drift out of step with the resolution order below the way a duplicated precedence
#     would.
#   · THE FULL KEY IS STORED IN THE FILE AND COMPARED ON READ, so a cksum collision costs a miss
4. `Bash: {"command": "F=/tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh; sed -n 175,195p $F; grep -nE 'WRAP_LIVE_ADDS_MAX|WRAP_LIVE_STALE_MAX|WRAP_LIVE_BUDGET|WRAP_TIMEOUT_BIN|_MAX\\b' $F | head; sed -n 1155,1162p $F; sed -n 2125,2140p $F", "description": "Check header env seams and other possible switches`
   → # ── LAW ── fail-LOUD, never fail-silent-open: outside a git repo (or on a read error) this exits
#   non-zero with a stderr note and NEVER prints RUNG=✅. A consumer that can't get a ledger must
#   treat that as "cannot confirm", not as "complete". Pure-read of the REPO: the only bytes this
#   wri
5. `Bash: {"command": "F=/tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh; sed -n 1272,1290p $F; grep -nE 'LIVE_ADDS_MAX|LIVE_STALE_MAX' $F; sed -n 1160,1170p $F | head -3; grep -n 'WRAP_BUSY\\|BUSY_SRC=' $F | head", "description": "Check whether caps disable at 0"}`
   → # LIVE_ROOT = the tree of per-file symlinks the box actually executes from. It is the OTHER half of
# LIVE_REPO and until 2026-08-31 nothing here read it: every live-layer sensor asked a question of
# the git graph, and none asked what is at the end of a link. Seamed so a test can point it.
LIVE_ROO
6. `Bash: {"command": "mkdir -p /tmp/tokeff-regate/f2/out/B10-r2 && cat > /tmp/tokeff-regate/f2/out/B10-r2/answer.md <<'EOF'\n# Kill switches in scripts/wrap-ledger.sh\n\n**Answer: 3 environment variables act as kill switches.** All three default to `on` and are checked with `${VAR:-on}`.\n\n| # | Variable | `
   → (Bash completed with no output)
7. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B10-r2/answer.md", "headline": "wrap-ledger.sh has 3 kill switches: WRAP_CACHE (line 379, off/0/no turns off the machine-ledger memo cache), WRAP_RESIDENT (line 1160, only the exact value \"off\" skips the resident-teammate check), and WRAP_BUSY (line 2137,`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
