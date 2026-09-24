# Dossier 4

## Brief
```
In /tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh, which environment variables act as kill switches or off-switches (a variable that, when set to off/0, disables a section or check)? For each give the variable, the line, and what it turns off. numbers: {"kill_switches": <how many>}.
```

## Returned headline
wrap-ledger.sh has three kill switches, all defaulting to on: WRAP_CACHE (line 379; off/0/no turns off the memo cache), WRAP_RESIDENT (line 1160; only =off, turns off the resident-teammate check) and WRAP_BUSY (line 2137; only =off, turns off the session-busy probe).

## Returned numbers
`{"kill_switches": 3}`

## answer.md
# Kill switches in scripts/wrap-ledger.sh

Three environment variables act as off-switches. Each defaults to `on`.

| Variable | Line | Values that disable it | What it turns off |
|---|---|---|---|
| `WRAP_CACHE` | 379 (documented at 276) | `off`, `0`, `no`, `OFF`, `NO` | The machine-mode memo cache. It blanks `WL_TRANSCRIPT`, so no cache key is built (lines 380-408), `WL_KEY` stays empty, and the cache read (`_wl_cache_serve`), single-flight lock and cache write are all skipped. The ledger is always computed fresh. The header calls this the benchmark's control arm. The goal term reads the transcript through `GOAL_TRANSCRIPT`, which is captured at line 286 before the blanking, so it is unaffected. |
| `WRAP_RESIDENT` | 1160 | `off` only (exact match) | The resident-teammate check in `count_resident_members`. It returns early with `RESIDENT_SRC=none`, which leaves `RESIDENT_MINE=0`. Live team members of this session are therefore never counted into the 🔧 rung. |
| `WRAP_BUSY` | 2137 | anything except `off` keeps it on, so only `off` disables it | The session-busy probe: sourcing `hooks/lib/session-busy.sh` and calling `session_busy_live`. `BUSY`, `BUSY_STATE`, `BUSY_SRC` and the related fields keep their defaults: `BUSY=0`, `BUSY_STATE=UNKNOWN`, `BUSY_SRC=none`. |

Only `WRAP_CACHE` also accepts `0` or `no`. `WRAP_RESIDENT` and `WRAP_BUSY` respond to the literal string `off` and nothing else, so setting either to `0` does nothing.

## Not counted
- Timeout and tuning variables such as `WRAP_*_TIMEOUT_S`, `WRAP_CACHE_WAIT_*`, `WRAP_CACHE_LOCK_STALE_S` and `WRAP_LIVE_BUDGET_*`. They change bounds, not whether a section runs.
- Path and binary seams such as `WRAP_TRUNK`, `CC_BACKLOG_BIN` and `WRAP_SESSION_BUSY_LIB`. They redirect a read; they do not switch it off.

Method: grep of the file for `${VAR:-on}` defaults and for `off`/`0`/`no` comparisons, checked against the header's list of env seams (lines 181-189) and a case-insensitive grep for "kill switch".


## Tool calls (6) with the first 300 chars of each result
1. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/scripts && wc -l wrap-ledger.sh && grep -nE '(=|!=|==) *\"?(off|0|false|no)\"?|:-on|:-1\\}|_OFF|KILL|kill switch|kill-switch|off-switch' wrap-ledger.sh | head -100"}`
   →     2444 wrap-ledger.sh
30:#     ✅  clean ∧ not-stale ∧ landed ∧ remainder = 0 ∧ no unrun operator step from this session
52:#   that cannot (MEMORY.md alarm-polarity). Unresolvable session ⇒ BLOCKED=0 + BLOCKED_SRC=none;
53:#   unreadable store ⇒ BLOCKED=0 + BLOCKED_SRC=error. An unresolvable senso
2. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/scripts && grep -nE '\\$\\{[A-Z_]+:-(on|1|yes)\\}|\"\\$\\{?[A-Z_]+\\}?\" *(=|!=) *\"?(off|0)\"?' wrap-ledger.sh; echo ---; grep -nE '\\$\\{(WRAP|CC|WL)_[A-Z_]+' wrap-ledger.sh | grep -vE 'WL_(KEY|FILE|LOCK|DIR|TRANSCRIPT)' "}`
   → 379:case "${WRAP_CACHE:-on}" in off|0|no|OFF|NO) WL_TRANSCRIPT="" ;; esac
1160:  [ "${WRAP_RESIDENT:-on}" = "off" ] && { RESIDENT_SRC="none"; return 0; }
2137:if [ "${WRAP_BUSY:-on}" != "off" ] && [ -f "$_wl_sbl" ]; then
---
376:  [ $((now - lm)) -gt "${WRAP_CACHE_LOCK_STALE_S:-30}" ]
387:    _wl_k=
3. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/scripts && grep -nE 'WRAP_CACHE[^_]|WRAP_BUSY[^_]|WRAP_RESIDENT[^_]' wrap-ledger.sh; echo ---; grep -nE '\\boff\\b' wrap-ledger.sh | grep -v '^\\s*[0-9]*:\\s*#' | head -40; echo ---; sed -n 270,300p wrap-ledger.sh; sed -n 376,450p wrap-ledger.sh; sed -n 115`
   → 186:#                    WRAP_RESIDENT · WRAP_RESIDENT_TIMEOUT_S · CC_WF_TEAM_ROOTS ·
188:#                    WRAP_CACHE · WRAP_CACHE_DIR · WRAP_CACHE_WAIT_MS · WRAP_CACHE_WAIT_TRIES ·
276:# Kill switch: WRAP_CACHE=off|0|no ⇒ never read, never write (the benchmark's control arm).
280:# CACHE-KEY va
4. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/scripts && sed -n 178,195p wrap-ledger.sh; grep -niE 'kill|disable' wrap-ledger.sh | grep -v shellcheck | head -30"}`
   → #   writes are its own memo under TMPDIR (below) — which is why the live-layer read never fetches
#   (see compute_live_layer).
#
# Env seams (tests): WRAP_TRUNK (the repo-local, non-test seam is `git config claude.trunk`) · WRAP_DOD_DIR · WRAP_DOD_FILE · WRAP_GATE_GREEN ·
#                    WRAP_
5. `Bash: {"command": "mkdir -p /tmp/tokeff-regate/f2/out/B10-r3 && cat > /tmp/tokeff-regate/f2/out/B10-r3/answer.md <<'EOF'\n# Kill switches in scripts/wrap-ledger.sh\n\nThree environment variables act as off-switches. Each defaults to `on`.\n\n| Variable | Line | Values that disable it | What it turns off |`
   → (Bash completed with no output)
6. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B10-r3/answer.md", "headline": "wrap-ledger.sh has three kill switches, all defaulting to on: WRAP_CACHE (line 379; off/0/no turns off the memo cache), WRAP_RESIDENT (line 1160; only =off, turns off the resident-teammate check) and WRAP_BUSY (line 2137; onl`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
