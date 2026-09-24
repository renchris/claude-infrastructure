# Dossier 7

## Brief
```
In /tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh, which environment variables act as kill switches or off-switches (a variable that, when set to off/0, disables a section or check)? For each give the variable, the line, and what it turns off. numbers: {"kill_switches": <how many>}.
```

## Returned headline
wrap-ledger.sh has 3 kill switches, all defaulting to on: WRAP_CACHE (line 379, accepts off/0/no/OFF/NO) turns off the machine-mode memo cache, and WRAP_RESIDENT (line 1160) and WRAP_BUSY (line 2137) turn off the resident team-member check and the busy/permission-pending probe, but only for the exact string "off", not 0.

## Returned numbers
`{"kill_switches": 3}`

## answer.md
# Kill switches in scripts/wrap-ledger.sh

File: /tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh (2444 lines, measured with `wc -l`).

Method: I ran grep over every `${WRAP_*|CC_*:-...}` expansion and every `off|0` or `= "off"` test,
then read the code around each hit.

## The 3 kill switches (all default to `on`)

| # | Variable | Line | Test | What it turns off |
|---|----------|------|------|-------------------|
| 1 | `WRAP_CACHE` | 379 (documented at 276) | `case "${WRAP_CACHE:-on}" in off\|0\|no\|OFF\|NO) WL_TRANSCRIPT="" ;; esac` | The memo cache for machine mode. Blanking `WL_TRANSCRIPT` means the `if [ "$MODE" = "machine" ] && [ -n "$WL_TRANSCRIPT" ]` block at line 380 never builds a key, so `WL_KEY` stays empty. The cache is then never read or written: no lock, no memo file under `$WRAP_CACHE_DIR`. The header calls this "the benchmark's control arm". The transcript is still available as an input because line 285 copies it into `GOAL_TRANSCRIPT` before the switch runs. |
| 2 | `WRAP_RESIDENT` | 1160 | `[ "${WRAP_RESIDENT:-on}" = "off" ] && { RESIDENT_SRC="none"; return 0; }` | The resident team-member check in `count_resident_members`. The function returns before it reads team config or the process table. `RESIDENT_MINE` stays 0 and `RESIDENT_SRC=none`, so the resident-members arm of the rung ladder (line 2017) can never fire. |
| 3 | `WRAP_BUSY` | 2137 | `if [ "${WRAP_BUSY:-on}" != "off" ] && [ -f "$_wl_sbl" ]; then` | The session busy and permission-pending probe. The script skips sourcing `session-busy.sh`, `session_busy_live` and `sb_permpend`. The fields stay at their defaults: `BUSY=0`, `BUSY_STATE=UNKNOWN`, `BUSY_SRC=none`, `PERMPEND=0`. |

Accepted values differ:
- `WRAP_CACHE` accepts `off`, `0`, `no`, `OFF` or `NO`.
- `WRAP_RESIDENT` and `WRAP_BUSY` accept only the exact lowercase string `off`. Setting them to `0` does NOT disable them.

## Close, but not counted
- `WRAP_TIMEOUT_BIN` (lines 763-770): if you set it to a non-executable value, the script runs with no timeout wrapper (`_bounded` calls the command directly). It is documented as a path seam, not an off switch, and it has no off/0 test.
- The `*_TIMEOUT_S`, `WRAP_CACHE_WAIT_*` and `*_BUDGET_*` variables are numeric tuning knobs. None of them has an off branch.


## Tool calls (9) with the first 300 chars of each result
1. `Bash: {"command": "wc -l /tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh; grep -n -E '\\$\\{?[A-Z_][A-Z0-9_]*' /tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh | head -100; ls /tmp/tokeff-regate/f2/out/B10-r4/ 2>&1", "description": "Inspect script size and env var references"}`
   →     2444 /tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh
69:#   Session id: --session > $WRAP_SESSION_ID > $CLAUDE_SESSION_ID > unresolvable. Unresolvable ⇒
83:#   $WRAP_LIVE_REPO's `origin` URL is byte-equal to THIS repo's. Different origin ⇒ LIVE_SRC=n-a
98:#   ($CC_MIGRATIONS_STATE/failed/*.jso
2. `Bash: {"command": "F=/tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh; grep -n -E 'off\\||\\|0\\||= *\"?0\"?|\"0\"|:-on|:-1\\}|!= *\"?off|= *\"?off' $F | head -60", "description": "Find off/0 switch patterns"}`
   → 30:#     ✅  clean ∧ not-stale ∧ landed ∧ remainder = 0 ∧ no unrun operator step from this session
52:#   that cannot (MEMORY.md alarm-polarity). Unresolvable session ⇒ BLOCKED=0 + BLOCKED_SRC=none;
53:#   unreadable store ⇒ BLOCKED=0 + BLOCKED_SRC=error. An unresolvable sensor NEVER manufactures a
7
3. `Bash: {"command": "F=/tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh; grep -o -E '\\$\\{(WRAP|CC|WL|GOAL|LEDGER)_[A-Z0-9_]*:-[^}]*\\}?' $F | sort | uniq -c; echo ---; grep -n -i -E 'kill|switch|disable' $F | head -50", "description": "Enumerate env var defaults and kill-switch mentions"}`
   →    2 ${CC_BACKLOG_BIN:-}
   1 ${CC_BACKLOG_BIN:-$(command -v cc-backlog 2>/dev/null || true)}
   1 ${CC_CONVICTION_EPOCH:-2026-09-08T17:00:00Z}
   2 ${CC_CUSTODY_BIN:-}
   1 ${CC_CUSTODY_DIR:-}
   2 ${CC_DECIDE_BIN:-}
   1 ${CC_MIGRATIONS_STATE:-}
   1 ${CC_MIGRATIONS_STATE:-$HOME/.claude/autonomy/m
4. `Bash: {"command": "F=/tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh; grep -n -E 'WRAP_BUSY[^_]|WRAP_RESIDENT[^_]|WRAP_CACHE[^_]' $F; echo ---; grep -n -E '(case|\\[\\[?) +\"?\\$\\{?[A-Z_]+' $F | grep -v -E '\\$\\{?(TRUNK|MODE|_|WL_|GATE|DOD|SID|LIVE|RUNG|AHEAD|DIRTY|UNLANDED|CHERRY|n|u|c)' | head -40",`
   → 186:#                    WRAP_RESIDENT · WRAP_RESIDENT_TIMEOUT_S · CC_WF_TEAM_ROOTS ·
188:#                    WRAP_CACHE · WRAP_CACHE_DIR · WRAP_CACHE_WAIT_MS · WRAP_CACHE_WAIT_TRIES ·
276:# Kill switch: WRAP_CACHE=off|0|no ⇒ never read, never write (the benchmark's control arm).
280:# CACHE-KEY va
5. `Bash: {"command": "F=/tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh; sed -n 176,192p $F; echo ----; sed -n 272,286p $F; echo ----; sed -n 1150,1162p $F; echo ----; sed -n 2125,2165p $F", "description": "Read context for each switch"}`
   → #   non-zero with a stderr note and NEVER prints RUNG=✅. A consumer that can't get a ledger must
#   treat that as "cannot confirm", not as "complete". Pure-read of the REPO: the only bytes this
#   writes are its own memo under TMPDIR (below) — which is why the live-layer read never fetches
#   (se
6. `Bash: {"command": "F=/tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh; grep -n -A12 '^_bounded()' $F | head -30; grep -n 'WRAP_TIMEOUT_BIN\\|CC_WF_TEAM_ROOTS\\|CC_WF_PSTABLE' $F", "description": "Check _bounded and other seams"}`
   → 783:_bounded() { local s="$1"; shift
784-  if [ -n "$_WRAP_BOUND_BIN" ]; then "$_WRAP_BOUND_BIN" "$s" "$@"; else "$@"; fi
785-}
786-
787-# YOURS = blocked backlog items whose .session == $SID. ANY failure (no binary, non-zero exit,
788-# no jq, unparseable json, timeout) ⇒ YOURS=0 + YOURS_SRC=error.
7. `Bash: {"command": "sed -n 758,782p /tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh", "description": "Read timeout bin seam"}`
   → #
# Resolved ONCE — the probe is a handful of `[ -x ]` tests — and REPORTED as BOUND_SRC, because a
# fail-open default that mimics the healthy state is unfalsifiable by its own output (MEMORY.md
# fail-safe-default-mimics-the-healthy-state): before this, a bounded run and an unbounded one were
# by
8. `Bash: {"command": "mkdir -p /tmp/tokeff-regate/f2/out/B10-r4 && cat > /tmp/tokeff-regate/f2/out/B10-r4/answer.md <<'EOF'\n# Kill switches in scripts/wrap-ledger.sh\n\nFile: /tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh (2444 lines, measured with `wc -l`).\n\nMethod: I ran grep over every `${WRAP_*|CC_`
   → (Bash completed with no output)
9. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B10-r4/answer.md", "headline": "wrap-ledger.sh has 3 kill switches, all defaulting to on: WRAP_CACHE (line 379, accepts off/0/no/OFF/NO) turns off the machine-mode memo cache, and WRAP_RESIDENT (line 1160) and WRAP_BUSY (line 2137) turn off the resident tea`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
