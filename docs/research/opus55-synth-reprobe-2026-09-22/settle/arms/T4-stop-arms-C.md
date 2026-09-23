<!-- arm C = claude-opus-5-5 @xhigh · brief T4-stop-arms · settle re-run (wf_a8c18432-bb3), clean cwd · raw worker output, verbatim -->

# Every way `hooks/session-continue.sh` blocks a Stop (snapshot 47c3317eb)

The hook has **four arms that can block a Stop, and only three of them print the block themselves.** The agent-armed sentinel, the ship floor and the wake floor each print `{decision:"block"}`. The mechanical 🔧 arm prints nothing: it writes the sentinel and then falls into the sentinel's code path. The hook always exits 0. A block reaches the harness only as JSON on stdout (`hooks/session-continue.sh:1211`, `:1216`, `:1344`).

## 0. Whether any arm runs, and in what order

**Preconditions for every arm:**
- The hook must be called as a Stop hook. The CLI verbs `--why`, `set`, `clear` and `status` exit before any Stop logic runs (`:105-117`, `:138-304`).
- `lib/continue-sentinel.sh` must source. If it does not, the hook logs `no-sentinel-lib` and exits 0 (`:125-131`).
- In the shipped template the hook is Stop-chain member #4 with `"timeout": 5` (`settings-templates/settings.example.json:466-467`). completion-assert is member #6 (`:476`). This is a template copy; the live settings file is not in the tree. The harness killing the hook at the timeout means nothing is printed, so nothing blocks.

**Setup, in order, for one Stop:**
1. Parse stdin: `cwd` = `.cwd`, else `$PWD`; `f = continue_sentinel_for(cwd)`; `cur_sid` = `.session_id`, else `$CLAUDE_CODE_SESSION_ID` (`:308-313`).
2. Delete last Stop's `${f}.blocked` marker (`:331-332`).
3. Source `goal-state.sh` and `mailbox-pending.sh`, then run `mailbox_promote_acked` (`:412-469`).
4. Source `agent-identity.sh`. If it fails to source, stub functions are installed that never report an assignee (`:525-542`).
5. Export `WRAP_TRANSCRIPT` (`:936-937`).

**The one condition that gates all three floors: `[ ! -f "$f" ]` (`:1205`), meaning no continuation sentinel exists for this config-dir and cwd.** When it holds, the hook:
- deletes `.count`, `.sid` and `.cwd` (`:1206`);
- runs `mechanical_arm` in the main shell;
- only if that returns 1, runs `ship_floor` in a subshell, printing its block and exiting if it blocks (`:1208-1212`);
- then runs `wake_floor` the same way (`:1213-1217`);
- otherwise prints the wake floor's advisory `systemMessage` if it produced one, and exits 0 (`:1218-1219`).

If the sentinel exists, or the mechanical arm just created it, the sentinel path runs in this order: kill switch (`:1228`) → SID check (`:1245`) → cap (`:1255`) → counter bump (`:1269-1270`) → fold in mail (`:1284`) → block (`:1329-1335`).

## 1. Agent-armed sentinel ("continue" path)

**(a) What triggers it**
- The file `f` exists. Its path is `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/state/continue-<first 16 hex chars of shasum("CLAUDE_CONFIG_DIR|cwd")>` (`hooks/lib/continue-sentinel.sh:17-27`).
- `set` writes it using the caller's `$PWD` (`:140-141`). The Stop looks it up with the stdin `.cwd` (`:309-311`), so arming from a different directory arms a sentinel this Stop never sees.
- Nothing else is checked: not the ledger rung, dirt, mail, goal, headless state or assignee status.
- The block's reason is the stored step plus `(continuation n/MAX)` (`:1301-1304`).

**(b) Counter and budget**
- The counter lives in `${f}.count` (`:1256`, `:1270`), keyed on the same config-dir+cwd hash.
- `MAX="${CLAUDE_CONTINUE_MAX:-8}"` (`:1255`).
- At `n ≥ MAX` the hook deletes `f`, `.count`, `.sid` and `.cwd`, prints a `systemMessage` naming the re-arm lever, and does not block (`:1258-1267`).
- `set` zeroes the counter (`:142`). So does every Stop that finds no sentinel (`:1206`), and so does `clear` (`:253`).
- `MAX` is never checked for being a number. A non-numeric value makes the `-ge` test error, the test reads false, and the cap never fires.

**(c) Which session owns it**
- There is no library function; ownership is inline. `set` writes the arming sid to `${f}.sid` (`:145-146`), and the mechanical arm does the same (`:1071`).
- At Stop: if both the stored sid and `cur_sid` are non-empty and they differ, the hook **deletes the sentinel and allows the stop** (`:1245-1251`). If either is blank, there is no check and the hook blocks.
- Consequence: a sibling session on the same config dir and cwd does not just abstain. Its Stop deletes this session's armed sentinel.

**(d) What suppresses it**
- The kill switch: `KILL_RE` (`:348`) matched against the last non-meta user record that carries text (`:351-395`). If the transcript cannot be read, the kill switch reads as inactive.
- A SID mismatch, and the cap.
- `clear [--if-mine]` (`:157-291`).
- This path has no assignee, teardown, headless or `/goal` exemption.
- There is no on/off variable. `CLAUDE_CONTINUE_MAX=0` disables it in effect: `n=0 ≥ 0` clears the sentinel and allows the stop.

## 2. Mechanical 🔧 arm (uncommitted files this session wrote)

**(a) What triggers it.** It is reached only when no sentinel exists (`:1207`). Every gate below must pass, in order (`:938-1078`):
- `CC_MECH_CONTINUE` is not `"0"` (`:939`), and `jq` is on PATH (`:940`).
- The kill switch is off (`:950`).
- The session is not an assignee (`:967-981`) and has no fresh teardown marker (`:983`).
- `session-writes.sh` sources (`:985-998`).
- `wrap-ledger.sh --machine` is found and prints something (`:1005-1014`).
- `RUNG=🔧` (`:1016-1017`). In the ledger that means `DIRTY=1` from `git status --porcelain` (`scripts/wrap-ledger.sh:527-529`, `:1979-1980`), with nothing pending that outranks it. `BLOCKED>0` gives ⛔ first (`:1972-1973`), so **a pending ⛔ decision suppresses this arm even over this session's own dirty files.**
- `session_dirty_mine` returns 0 with non-empty output (`:1022-1028`).
- The budget allows it (`:1052-1067`).

On success it bumps `.mech`, writes the step "Commit the N file(s)…" to `f`, writes `.sid` (only if `cur_sid` is set) and `.cwd`, and returns 0 (`:1068-1078`).

**(b) Budget**
- `${f}.mech` holds `"<sid> <count>"`, keyed on the sentinel path, with the sid stored inside. A different sid resets the count (`:1060`).
- `CC_MECH_MAX` defaults to **2** here (`:1053`) and is not checked for being a number. A non-numeric value means the budget is never spent.
- `.mech` survives both `clear` and the cap. `clear` writes `"<env sid> ${CC_MECH_MAX:-3}"` into it (`:260-261`) to spend the budget. The sid it writes comes from `CLAUDE_CODE_SESSION_ID`/`CLAUDE_SESSION_ID`, or `?`, while the arm compares against the stdin session_id. If they differ, `clear` fails to spend the budget.
- It also inherits `CLAUDE_CONTINUE_MAX` (see §6).

**(c) Which session owns the files**
- `hooks/lib/session-writes.sh` `session_dirty_mine` (`:277-361`). A dirty file counts as "mine" when its absolute path (`$top/$rel` from `git status --porcelain -z -uall`) exactly equals a canonicalised path that a `Write`/`Edit`/`MultiEdit`/`NotebookEdit` call wrote, in this transcript or its `subagents/*.jsonl` files (`_sw_paths` `:135-193`, `:124-129`).
- **rc 0**: at least one match; the matching relative paths are printed. **Only rc 0 permits the arm.**
- **rc 1**: this session wrote nothing (`:283`), or none of its writes are dirty (`:360`).
- **rc 2**: undecidable — no git (`:279`); no jq, transcript missing, or jq failed/timed out (`:137-139`, `:188`); not a repo (`:285-286`); mktemp or git-status failure (`:318-321`).
- Tuning: `SESSION_WRITES_TIMEOUT_S:-5` (`:171`); git status is capped at 5 s (`:319`).
- Files changed through Bash are never attributed to the session.

**(d) What suppresses it**
- `CC_MECH_CONTINUE=0` turns the arm off outright. The kill switch also suppresses it.
- **Team assignee:** `agent_assignee_argv` returns 0 and `agent_team_member_confirms` returns **0 or 2** (`:967-981`).
  - `agent_assignee_argv` (`hooks/lib/agent-identity.sh:33-77`) walks up to `CC_WF_MAX_HOPS:-8` ancestor processes looking for argv with `--agent-id name@team`, `--agent-name` and `--team-name`. rc 0 prints the id; rc 1 means none found.
  - `agent_team_member_confirms` (`:93-124`) returns 0 when the team config lists the member (and it is not the leader), 1 when a config exists without that member, and 2 when the id is not `*@session-*`, is malformed, or no config is found.
- **Teardown:** `wf_teardown_marked` (`:551-568`) finds `${CC_TEARDOWN_DIR:-$HOME/.claude/watchdog/teardown}/<sid|pane>.json` modified within `CC_WF_TEARDOWN_FRESH_S:-1800` seconds.
- A ledger rung other than 🔧, or no ledger.
- There is no headless or `/goal` exemption.

## 3. Ship floor (📦 / 🚀)

**(a) What triggers it.** It is reached when no sentinel exists and `mechanical_arm` returned 1 (`:1207-1208`). The gates:
- `CC_SHIP_FLOOR` is `1` (`:1099`), and `jq` is on PATH.
- The kill switch is off; not an assignee; no teardown marker (`:1101-1110`).
- The ledger is available: it reuses `SC_LED_CACHE` if the mechanical arm already ran it, else runs it (`:1115-1126`).
- Rung is 📦 or 🚀 (`:1127-1128`):
  - **📦**: `UNLANDED=1`, meaning `AHEAD>0` or `git cherry` shows a `+` (`wrap-ledger.sh:532-539`), with nothing blocked, dirty or remaining in the DoD (`:1972-1984`). This includes the "Land IN FLIGHT" readout (`:1985-1986`), which `ship_floor` never tells apart, so it can block while a land is in flight.
  - **🚀**: no open custody rows (`:1997-1998`), no resident, filed, unconvicted or close-floor items, trunk resolved, and `LIVE_BREACH=1` (`:2053-2056`).
- Ownership passes (`:1146-1156`), and the latch and budget allow it (`:1160-1178`).

**(b) Latch and budget**
- `${f}.ship` holds `"sid headsha count"` (`:1160-1179`). A different sid resets count and sha (`:1170`).
- **Latch:** the same HEAD sha as the last fire means abstain (`:1172`).
- `CC_SHIP_FLOOR_MAX:-2`, checked for being a number (`:1162`).
- `.ship` is never deleted: not by `clear`, and not at `:1206`. So `clear` does not spend it.

**(c) Which session owns the work**
- **📦** uses `session_unlanded_mine(TP, cwd, TRUNK)` (`session-writes.sh:375-433`). **rc 0** (permits): a file in `git diff --name-only $trunk..HEAD` is one this session wrote. rc 1: no writes, or no overlap. rc 2: no trunk, no git, writes undecidable, not a repo, or the diff failed (`:377-383`, `:414-417`).
  - The two-dot diff compares trees, so files that trunk changed since the fork also count.
- **🚀** uses only `session_writes_paths(TP)` rc 0 (`:1153-1155`): the session (or its subagents) wrote *any* file, anywhere. It is not scoped to this repo.

**(d) What suppresses it:** `CC_SHIP_FLOOR` set to anything but `1` (turns it off outright), the kill switch, assignee status (rc 0 or 2), a teardown marker, the latch, or the budget. There is no headless or `/goal` exemption.

## 4. Wake floor (no watcher armed; mail and custody feed it)

**(a) What triggers it.** It is reached when there is no sentinel, the mechanical arm returned 1, and the ship floor returned 0 (`:1213`). The checks, in order:
1. `CC_WAKE_FLOOR` is `1`; `jq` is on PATH; the mailbox lib loaded (`:604-606`).
2. `_ouid` is valid (`:607`). It is `${CC_PANE_ID:-${ITERM_SESSION_ID:-}}` with everything up to the last `:` stripped (`:420`), then resolved to a mailbox key (`:453-466`).
3. **No live watcher.** `mailbox_wake_armed` looks for `<key>.watching`, modified within `CC_WATCH_FRESH_S:-90` seconds, whose pid is alive (`mailbox-pending.sh:291-301`). If a live watcher is found, the hook deletes the floor's state file and returns (`:614`).
4. Pending mail `pend` = inbox lines minus the seen cursor (`:629`; `mailbox-pending.sh:245`).
5. **Headless abstain:** `CC_PANE_ID` is set and `ITERM_SESSION_ID` is empty (`:656-664`).
6. **Goal abstain:** a live `/goal` *and* `pend>0` (`:692-704`). `goal_live_condition` reads the last `goal_status` attachment where neither `met` nor `failed` is set (`goal-state.sh:60-80`).
7. Count custody rows (`:731-766`).
8. Assignee/teardown abstain, but only while `CC_WAKE_FLOOR_TEARDOWN=1` (`:776-798`).
9. **Eligibility: `cnt==0 || pend>0 || cust>0`** (`:805`).
10. Budget (`:836-843`), TTL (`:845-848`), kill switch (`:850-854`).
11. Write state and block (`:856-894`).

**(b) Budget**
- The state file is `${CC_MAILBOX_DIR:-$HOME/.claude/mailbox}/<key>.wakefloor` with lines `sid=`, `count=` and `ts=` (`:610-611`, `:856`). It is keyed on the pane's mailbox, not the session. A new sid resets it (`:627`).
- **It is deleted whenever a live watcher is seen (`:614`), so the budget is per unarmed stretch, not per session.**
- Tuning: `CC_WAKE_FLOOR_MAX:-2` (`:807`); `CC_WAKE_FLOOR_TTL_S:-600` minimum gap between fires (`:808`); `CC_WAKE_FLOOR_TIMEOUT_S:-14400` only changes the suggested watcher command (`:821`).

**(c) Whose custody rows count**
- Rows come from `cc-custody list --open --cwd "$cwd" --json` (`:743-744`). A row is open when its latest event per marker (or slug+targetPane) has kind `open` (`bin/cc-custody:106-110`).
- The jq filter (`:748-754`) counts a row as *mine* if `originatorPane == pane`, `notifyBack == pane`, or `notifyBack` ends in `-pane`. It counts a row as *unknown* if neither field is set. Rows that name another pane are excluded.
- `cust = mine + unknown` (`:758`). With no pane id, or if the list call fails, it falls back to `count --open`, and every row counts as unknown (`:759-765`).
- The session-writes attribution is not used here.

**(d) What suppresses it:** `CC_WAKE_FLOOR` set to anything but `1` (turns it off outright), no jq or mailbox lib, an empty or invalid pane id, a live watcher, headless, a live goal with pending mail, assignee or teardown (only while `CC_WAKE_FLOOR_TEARDOWN=1`), ineligible, budget spent, TTL not yet passed, or the kill switch. A live goal *without* mail does not suppress it; the suggested command changes to `--idle-scoped` instead (`:827-833`).

## 5. Direct answers

- **Order:** mechanical → ship floor → wake floor, and all three only when `[ ! -f "$f" ]` (`:1205`). When the mechanical arm arms, the sentinel path runs next: kill switch → SID → cap → block.
- **Payloads per invocation:** at most **one** block, and at most one JSON object of any kind. Every block path prints and exits immediately (`:1210-1211`, `:1215-1216`, `:1332-1344`). Each wake-floor path prints at most one `systemMessage`.
  - Across the whole Stop chain, completion-assert reads `${f}.blocked` (written by `mark_blocked` at `:1209`, `:1214`, `:1329`) and withdraws its own contradiction block (`hooks/completion-assert.sh:868-871`).
- **The arm that blocks without printing:** the mechanical arm. It inherits:
  - the kill-switch re-check (`:1228`);
  - the SID check (`:1245`), which passes trivially because it just wrote `cur_sid`;
  - the `CLAUDE_CONTINUE_MAX` cap (`:1255`), with `.count` starting fresh because `:1206` deleted it;
  - the mail fold.
  
  The worst case is therefore `CC_MECH_MAX × CLAUDE_CONTINUE_MAX` = 2 × 8 = 16 forced turns per sid. Once armed, its sentinel keeps blocking on later Stops without re-checking for dirt, even after a commit, until `clear` or the cap. The comment at `:1044-1045` ("a clean tree cannot reach this line") is true only of the arm itself.
- **Does unread mail alone block a Stop? No.** Mail's only route to a block is the wake floor, and there it is neither required nor sufficient:
  - Not required: `cnt==0` passes eligibility with no mail at all.
  - Not sufficient: a live watcher (`:614`), headless, goal+mail, assignee/teardown, budget, TTL or the kill switch each abstain.
  - What mail does: it keeps the floor eligible after the first fire (`:805`), and puts "📬 N message(s)" at the top of the reason (`:872-874`).
- **What the mail fold at the end of the file does (`:1284-1340`):** it runs only on the sentinel path, after the cap check and counter bump.
  - It claims the drain lock and peeks at lines (seen, EOF] without consuming them. The window has no size cap: `window_end` is called with max 0 (`:1293`).
  - It puts the mail at the top of the reason and adds a `systemMessage` (`:1309-1323`).
  - It advances `.seen` only after the block JSON has been printed (`:1337-1339`), then releases the lock (`:1340`). If another drain holds the lock, it delivers nothing this time.
  - The legacy `mailbox_take` fallback consumes the mail before the block is printed (`:1296-1297`).
  - **It does not** create a block, run on any floor path or on the kill/SID/cap exits, or advance `.acked`. `mailbox_promote_acked` sets `acked := seen` at the top of every Stop (`:467`; `mailbox-pending.sh:560-567`).
- **Environment variables with different literal defaults:**
  - **`CC_MECH_MAX`**: `:-3` in `clear` (`:261`) versus `:-2` in the arm's budget check (`:1053`).
  - The pane-id fallback chain: `${CC_PANE_ID:-${ITERM_SESSION_ID:-}}` in this hook (`:420`) versus `${CC_PANE_ID:-${ITERM_SESSION_ID:-${KITTY_WINDOW_ID:-}}}` in `hooks/session-register.sh:134`. A pane known only by `KITTY_WINDOW_ID` therefore has the wake floor and mail fold switched off here.
  - I checked `CLAUDE_CONTINUE_MAX`, `CC_WATCH_FRESH_S`, `CC_SHIP_FLOOR_MAX`, `CC_WAKE_FLOOR_*`, `CC_WF_TEARDOWN_FRESH_S`, `SESSION_WRITES_TIMEOUT_S`, `CC_TEARDOWN_DIR`, `CC_MAILBOX_DIR` and `CC_WF_MAX_HOPS` across `hooks/`, `scripts/` and `bin/`. Each has a single default.

## 6. In-file citations I checked

**Stale (the cited line no longer says what the comment claims):**
- `session-writes.sh:110` → `wrap-ledger.sh:140`, which now discusses deploy-live's lag budget.
- `session-writes.sh:405` → `completion-assert.sh:398`, which is now `aid="$(agent_is_assignee …)" || return 1`.
- `session-continue.sh:519` → `completion-assert.sh:236`, which is now the `WRAP_TRANSCRIPT` memo block.
- `session-continue.sh:990` → `completion-assert.sh:99-105`, which is now the `--why` tier comment and `set -uo pipefail`.
- `session-continue.sh:455` and `:643` → `bin/cc-pane-headless:124`/`:197`, which are now a `--name` argument case and a bare `fi`.

**Still accurate:**
- `:317` → `hook-chain.sh:77-78`.
- `:325-326` (Stop-chain positions 4 and 6), checked against `settings.example.json:466` and `:476`.
- `:961` → `session-writes.sh:13-22`.
- `:587` → `:33-34`, roughly.