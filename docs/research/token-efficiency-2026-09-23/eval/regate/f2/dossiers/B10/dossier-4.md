# Dossier 4

## Brief
```
In /tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh, which environment variables act as kill switches or off-switches (a variable that, when set to off/0, disables a section or check)? For each give the variable, the line, and what it turns off. numbers: {"kill_switches": <how many>}.
```

## Returned headline
wrap-ledger.sh has 3 kill switches: WRAP_CACHE (line 379; off, 0 or no turns off the --machine memo cache read/write and lock), WRAP_RESIDENT (line 1160; off skips the resident-teammate check) and WRAP_BUSY (line 2137; off skips the session-busy and permission-pending probe).

## Returned numbers
`{"kill_switches": 3}`

## answer.md
# Kill switches in scripts/wrap-ledger.sh

There are **3** environment-variable kill switches in `/tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh`.

| # | Variable | Line | Off values | What it turns off |
|---|---|---|---|---|
| 1 | `WRAP_CACHE` | 379 (documented at 276, 280) | `off`, `0`, `no`, `OFF`, `NO` (default `on`) | The `--machine` memo cache. It blanks `WL_TRANSCRIPT`, so no cache key is built (lines 380-406). With no `WL_KEY`, the script skips the cache read (`_wl_cache_serve`), the single-flight `mkdir` lock and wait ladder, and the cache write. The header calls it "never read, never write (the benchmark's control arm)". `GOAL_TRANSCRIPT` is copied before this line (285), so the goal check still reads the transcript. |
| 2 | `WRAP_RESIDENT` | 1160, in `count_resident_members()` | `off` only (default `on`) | The resident-member (RC-2) check. The function returns right away with `RESIDENT_SRC=none`. It skips the team-config lookup, the `ps` census of live `--agent-id <name>@session-<team>` members, and their dirty-file read, so `RESIDENT_MINE` never adds a 🔧. The global CLAUDE.md names this as the "Kill switch `WRAP_RESIDENT=off`". |
| 3 | `WRAP_BUSY` | 2137 | `off` only (default `on`) | The session-busy probe. It skips sourcing `hooks/lib/session-busy.sh` and the calls to `session_busy_live` and `sb_permpend`. `BUSY`, `BUSY_STATE`, `BUSY_SUSPECT`, `BUSY_AGE`, `BUSY_SAMPLE`, `PERMPEND` and `PERMPEND_AGE` keep their defaults (`BUSY=0`, `BUSY_STATE=UNKNOWN`, `BUSY_SRC=none`). |

Not counted:
- `DRAIN_SCOPE` (line 942) looks like a switch but is not an environment variable. It is set inside the script (lines 601 and 627) from the DoD text.
- The tuning knobs are also left out: `WRAP_CACHE_WAIT_TRIES` (0 means no wait), the `WRAP_*_TIMEOUT_S` values, `WRAP_LIVE_*` budgets and `WRAP_CACHE_LOCK_STALE_S`. They set sizes or bounds; none is an on/off switch for a section.
- The test seams (`WRAP_TRUNK`, `WRAP_DOD_*`, `WRAP_GATE_GREEN`, `CC_*_BIN` and the others) are left out for the same reason.
- `WRAP_RESIDENT` and `WRAP_BUSY` react only to the literal `off`. Setting them to `0` does not turn them off. Only `WRAP_CACHE` also accepts `0` and `no`.


## Tool calls (7) with the first 300 chars of each result
1. `Bash: {"command": "F=/tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh; wc -l $F; grep -nE '(:-on|:-1|:-0|= *\"?off\"?|!= *\"?off\"?|== *\"?0\"?|\"off\"|kill.?switch|Kill switch)' $F | head -80"}`
   →     2444 /tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh
276:# Kill switch: WRAP_CACHE=off|0|no ⇒ never read, never write (the benchmark's control arm).
279:# The transcript as an INPUT, kept out of the cache kill-switch's reach. $WL_TRANSCRIPT is a
280:# CACHE-KEY variable and `WRAP_CACHE=off` BL
2. `Bash: {"command": "F=/tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh; grep -noE '\\$\\{[A-Z_][A-Z0-9_]*:-[^}]*\\}' $F | sort -t: -k3 -u | awk -F: '{print $1\": \"$2}' | sort -k2 -u | head -120"}`
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
3. `Bash: {"command": "F=/tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh; grep -noE '\\$\\{?[A-Z][A-Z0-9_]{2,}' $F | awk -F: '{print $2}' | sort | uniq -c | sort -rn | head -80; echo ---; grep -nE 'off|disable|kill' $F | head -80"}`
   →   22 $SID
  20 $TRUNK
  20 $HOME
  15 $LIVE_REPO
  13 $PWD
  12 $LIVE_ADDS
  10 $WL_DIR
  10 $LIVE_ROOT
  10 $HEAD_SHA
  10 ${WRAP_LIVE_TIMEOUT_S
   8 $LIVE_SHA
   8 ${SID
   7 $WL_FILE
   7 $LIVE_SRC
   7 $LIVE_LAG
   7 $LIVE_AGE
   7 $FILED_SRC
   7 $CUSTODY_MINE
   7 ${LIVE_LAG
   6 $WL_LOCK
   5
4. `Bash: {"command": "F=/tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh; grep -nE 'WRAP_[A-Z_]+|DRAIN_SCOPE|CC_[A-Z_]+' $F | grep -vE '^\\s*[0-9]+:\\s*#' | head -80; echo; sed -n 270,300p $F; sed -n 370,445p $F"}`
   → 278:WL_TRANSCRIPT="${TRANSCRIPT_FLAG:-${WRAP_TRANSCRIPT:-}}"
376:  [ $((now - lm)) -gt "${WRAP_CACHE_LOCK_STALE_S:-30}" ]
379:case "${WRAP_CACHE:-on}" in off|0|no|OFF|NO) WL_TRANSCRIPT="" ;; esac
386:    _wl_k="v1|$WL_TRANSCRIPT|$_wl_ms|$PWD|$SESSION_FLAG|${WRAP_SESSION_ID:-}|${CLAUDE_SESSION_ID:-}"
5. `Bash: {"command": "F=/tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh; grep -niE 'env seam|=off|off\\b' $F | head -30; sed -n 1150,1165p $F; sed -n 2125,2160p $F"}`
   → 136:#   DESCENDS from live HEAD) or T1H (an OFF-BOX hermetic green with no on-box RED). Neither reads
181:# Env seams (tests): WRAP_TRUNK (the repo-local, non-test seam is `git config claude.trunk`) · WRAP_DOD_DIR · WRAP_DOD_FILE · WRAP_GATE_GREEN ·
218:# anti-deference-nudge, boundary-handoff, oper
6. `Bash: {"command": "mkdir -p /tmp/tokeff-regate/f2/out/B10-r3 && cat > /tmp/tokeff-regate/f2/out/B10-r3/answer.md <<'EOF'\n# Kill switches in scripts/wrap-ledger.sh\n\nThere are **3** environment-variable kill switches in `/tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh`.\n\n| # | Variable | Line | Off v`
   → (Bash completed with no output)
7. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B10-r3/answer.md", "headline": "wrap-ledger.sh has 3 kill switches: WRAP_CACHE (line 379; off, 0 or no turns off the --machine memo cache read/write and lock), WRAP_RESIDENT (line 1160; off skips the resident-teammate check) and WRAP_BUSY (line 2137; off sk`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
