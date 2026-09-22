<!-- arm B = claude-opus-5-5 @high · brief T4-stop-arms · raw worker output, verbatim -->

# Every condition under which `hooks/session-continue.sh` blocks a Stop (snapshot 47c3317eb)

## 0. How the hook works

- **Output channel.** The hook blocks by printing `{"decision":"block",…}` to stdout. Every path through actuation mode exits 0 (`hooks/session-continue.sh:36-37`, `:1211`, `:1216`, `:1219`, `:1344`).
- **Library load.** If `hooks/lib/continue-sentinel.sh` cannot be sourced, actuation logs `abstained no-sentinel-lib` and exits 0, so it never blocks (`:125-131`).
- **Sentinel path.** The path is `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/state/continue-<first 16 hex of shasum("$CLAUDE_CONFIG_DIR|<cwd>")>` (`hooks/lib/continue-sentinel.sh:17-27`). The `<cwd>` is the Stop payload's `.cwd`, falling back to `$PWD` (`:309-311`). Everything is keyed on (config dir, cwd), not on the session.
- **Session id.** `cur_sid` is the payload's `.session_id`, falling back to `$CLAUDE_CODE_SESSION_ID` (`:312-313`).
- **Per-Stop marker.** At the top of every Stop the hook deletes `${f}.blocked` (`:331-332`). `mark_blocked` rewrites it only on a block (`:333-336`).
- **Unconditional mail step.** Before any arm runs, `mailbox_promote_acked` runs on every Stop (acked = seen) (`:426-469`, `hooks/lib/mailbox-pending.sh:560-567`). It never prints to stdout.

### Evaluation order and the one gating condition

Everything turns on whether the sentinel file `$f` exists (`:1205`).

- **No sentinel** (`[ ! -f "$f" ]`). The hook deletes stale `.count/.sid/.cwd` (`:1206`), then runs the floors in this order:
  1. `mechanical_arm` (`:1207`)
  2. if that did not arm: `ship_floor` (`:1208`)
  3. if the ship floor did not block: `wake_floor` (`:1213`)
  4. otherwise it prints the wake floor's non-blocking `systemMessage`, if any, and exits (`:1218-1219`).
- **Mechanical arm succeeds.** Control falls through to the armed path (`:1221-1222`).
- **Sentinel exists.** The floors are never evaluated. The armed path runs: kill-switch (`:1228`), then SID-bind (`:1245`), then cap (`:1255`), then the mail fold (`:1284`), then the block (`:1329-1335`).

So the floors are reached only when no sentinel exists for this (config dir, cwd) at Stop time. A session that has armed the sentinel is never evaluated by the ship or wake floor.

### How many block payloads per Stop

At most **one JSON object**, and so at most one `decision:block`:
- A ship-floor block exits immediately (`:1209-1211`).
- A wake-floor block exits (`:1214-1216`).
- The wake floor's non-block branches print one `systemMessage` each (`:659`, `:699`, `:792`, `:840`, `:851`), and it is relayed once (`:1218`).
- In the armed path, the kill-switch and SID-mismatch exits print nothing on stdout. The cap exit prints one `systemMessage` (`:1264`). The block prints one object (`:1331-1335`).
- `ship_floor` never prints on rc 0 (`:1098`, all rc-0 returns are silent), and `log_idl` writes only to files (`:85-95`).
- The header comment claims "At most ONE floor emits per Stop" (`:1203-1204`), and the code bears it out.

---

## 1. Arm A: agent-armed sentinel (the continuation block)

**(a) Trigger.**
- `$f` exists. It was written by `session-continue.sh set "<step>"` (`:139-156`) or by the mechanical arm (`:1070`).
- The last genuine user message has no kill phrase (`:1228`).
- The stored `.sid` does not conflict with the current session id (`:1245-1246`).
- `.count` < `MAX` (`:1255-1258`).
- If all hold, `.count` is incremented (`:1269-1270`) and the hook blocks with "🔧 Loose ends remain — … Next: <step>" (`:1301-1304`, `:1329-1335`).
- No tree, ledger, mailbox or custody state is consulted.

**(b) Counter.**
- File: `${f}.count`, keyed on (config dir, cwd).
- Env var: `CLAUDE_CONTINUE_MAX`, default `8` (`:1255`). It is **not sanitised**: a non-numeric value makes `[ "$n" -ge "$MAX" ]` error to false, so the cap never fires.
- Counting: blocks happen while n ∈ {0..7}. At n = 8 the hook clears `$f/.count/.sid/.cwd`, prints the cap `systemMessage`, and allows the Stop (`:1258-1268`).
- Reset: every `set` deletes `.count` (`:142`). This is the documented way around the cap, which is why a compliant chain is unbounded.

**(c) Ownership.**
- There is no library call. The only check is the `.sid` sidecar written at `set` time, and only when a session id exists (`:145-146`).
- The Stop-time check is `[ -n "$stored_sid" ] && [ -n "$cur_sid" ] && [ "$stored_sid" != "$cur_sid" ]`. If true, the hook clears the sentinel and allows the Stop (`:1245-1252`).
- Consequences, which follow from the code:
  - A different session's Stop in the same cwd **destroys** that sibling's armed sentinel.
  - A sentinel armed with no sid (for example the operator's bare-shell `set`) blocks **any** session stopping in that cwd, because missing evidence never clears it.

**(d) Exemptions.**
- **Kill-switch.** `kill_switch_active` (`:391-395`) reads the last `type=="user"` record that is not `isMeta` (`:380-387`) and matches `KILL_RE` (`:348`): "…and [then] stop", "no auto-continue", "just do X", "stop here", "come back to this", or a bare stop/halt. If there is no transcript path, it cannot read and does not fire (`:355`).
- **SID mismatch**, described above.
- **Not exempt:** assignee, teardown, headless and live `/goal` are not consulted on this path at all.
- **Disable switch:** there is no dedicated one. `CLAUDE_CONTINUE_MAX=0` turns every armed Stop into the cap path (clear and allow), which neutralises the arm.

---

## 2. Arm B: mechanical uncommitted-writes arm (`mechanical_arm`, `:938-1079`)

This arm **never prints a block of its own.** On success it writes the sentinel and returns 0 (`:1070-1078`), and the armed path (Arm A) emits the block. It therefore inherits Arm A's second kill-switch check, its SID-bind (trivially passed, since it writes `cur_sid` into `.sid` itself at `:1071`) and its `CLAUDE_CONTINUE_MAX` cap (default 8). Because the no-sentinel branch has already deleted `.count` (`:1206`), each mechanical arming starts a fresh chain of up to 8 blocks.

The mail fold also rides on it, and the marker it leaves is `mark_blocked continue` (`:1329`), which cannot be told apart from an agent-armed block.

**(a) Trigger, all of the following:**
- No sentinel exists.
- `CC_MECH_CONTINUE` ≠ `"0"` (`:939`).
- `jq` is on PATH (`:940`).
- No kill phrase (`:950`).
- Not an assignee (`:967-981`).
- No fresh teardown marker (`:983`).
- `session-writes.sh` is resolvable. Resolution order: `SESSION_WRITES_LIB`, then `$_scd/lib`, then the target of `$0`'s symlink, then the config-dir lib, then `~/.claude` lib (`:986-998`).
- `wrap-ledger.sh --machine`, run in `$cwd`, returns output. Resolution order: `WRAP_LEDGER_BIN`, then `../scripts`, then the config dir, then `~/.claude` (`:1006-1014`). `WRAP_TRANSCRIPT` is exported (`:936-937`).
- The ledger's `RUNG=` is exactly `🔧` (`:1016-1017`).
- `session_dirty_mine "$TP_MECH" "$cwd"` returns rc 0 with non-empty output (`:1022-1028`).
- The budget is not spent (`:1062`).

Notes on the ledger rung:
- The ledger puts ⛔ ahead of 🔧 (`scripts/wrap-ledger.sh:1971-1980`). An open class-C decision filed by this session therefore suppresses the arm even over this session's own dirt.
- The ledger has many other 🔧 causes: DoD remainder, open custody, resident teammates, filed-but-undriven rows, unconvicted rows, the backlog close floor, no trunk (`scripts/wrap-ledger.sh:1979-2052`). These only satisfy the rung half. The block still needs dirty paths that this session wrote.

**(b) Budget.**
- File: `${f}.mech`, containing `"<sid> <count>"` and keyed on (config dir, cwd) (`:1053-1068`).
- Env var: `CC_MECH_MAX`, default **`2`** here (`:1053`). It is not sanitised: a non-numeric value makes `-ge` false, so the budget never binds.
- A different sid resets the count to 0 (`:1060`).
- `.mech` is never deleted when the sentinel is cleared, which is deliberate (`:1040-1045`).
- Worst case: `CC_MECH_MAX × CLAUDE_CONTINUE_MAX` = 2 × 8 = 16 blocks (`:1046-1051`).
- The `clear` verb spends the budget by writing `"$SC_SID ${CC_MECH_MAX:-3}"` (`:260-261`). `SC_SID` there comes from `CLAUDE_CODE_SESSION_ID`/`CLAUDE_SESSION_ID`, or `?`. A bare-shell `clear` therefore writes sid `?`. When the Stop payload carries a session id, `msid ≠ cur_sid` resets the count to 0 (`:1060`), so a bare-shell clear does **not** spend that session's budget.
- Other env vars: `SESSION_WRITES_TIMEOUT_S` (default 5; `hooks/lib/session-writes.sh:171`), plus `CC_WF_TEARDOWN_FRESH_S` and `CC_TEARDOWN_DIR` (section 5).

**(c) Ownership: `hooks/lib/session-writes.sh` `session_dirty_mine` (`:277-361`).**
- Return codes:
  - rc 0: a path both dirty in `git status --porcelain -z -uall` **and** written by this session's Write/Edit/MultiEdit/NotebookEdit tool calls (main transcript plus `subagents/**` files: `:143-147`, `:124-129`, `:171-185`). Both sides are canonicalised (`:292-299`, `_sw_canon :212-218`).
  - rc 1: nothing of mine is dirty. This includes when `session_writes_paths` returns 1 because there were no edit tool calls (`:283`).
  - rc 2: cannot tell. No git, no jq, no transcript, jq failure or timeout, `rev-parse` failure, `mktemp` failure, or a failed git status (`:279`, `:282`, `:285-286`, `:318-321`; `_sw_paths :137-139`, `:188`).
- **Only rc 0 permits the block** (`hooks/session-continue.sh:1023`).
- Blind spot: files written only through Bash are invisible (`hooks/lib/session-writes.sh:40-44`).

**(d) Exemptions.**
- Kill-switch (`:950`, logs `cleared mechanical-kill-switch`).
- Assignee: `agent_assignee_argv` succeeds and `agent_team_member_confirms` returns 0 (confirmed) **or** 2 (unknown). A return of 1 (refuted) is not exempt (`:968-980`).
- Teardown marker (`:983`).
- Budget spent (`:1062-1067`).
- **Not exempt:** headless and live `/goal`. Neither is consulted.
- **Disable switch:** `CC_MECH_CONTINUE=0`. Only the literal `"0"` disables it (`:939`).
- **Once armed, the arm does not clear itself.** The armed path never re-checks the tree. After the model commits, the persisted sentinel keeps blocking with the stale "Commit the N file(s)…" step (`:1070`) until the model runs `clear` or the cap hits. The header's "SELF-CLEARING" (`:922-923`) is true only of the arming predicate.

---

## 3. Arm C: ship floor (`ship_floor`, `:1098-1199`)

**(a) Trigger, all of the following:**
- No sentinel, and the mechanical arm did not arm.
- `CC_SHIP_FLOOR` is `"1"` (default 1; anything else disables) (`:1099`).
- `jq` is present.
- No kill phrase (`:1101`).
- Not an assignee (rc 0 or 2 exempts) (`:1103-1109`).
- No teardown marker (`:1110`).
- Ledger output is available. It reuses `SC_LED_CACHE` from the mechanical arm, or recomputes (`:1115-1126`).
- `RUNG` is `📦` or `🚀` (`:1127-1128`). In the ledger, 📦 requires not ⛔, not dirty, remainder 0, and `UNLANDED=1` (`scripts/wrap-ledger.sh:1972-1984`). 🚀 is `LIVE_BREACH` on the ✅-eligible branch (`:2053-2084`).
- Ownership passes (part c).
- `HEAD` differs from the last-nudged sha for this session (`:1172`).
- The count is below the maximum (`:1174`).
- On block: it writes the sidecar (`:1179`) and emits the 📦 or 🚀 reason (`:1184-1197`).

**(b) Budget and latch.**
- File: `${f}.ship`, containing `"<sid> <HEAD-sha> <count>"` and keyed on (config dir, cwd) (`:1160-1179`).
- A different sid resets both count and sha (`:1170`).
- Same sha: the floor is latched and silent (`:1172-1173`).
- Env var: `CC_SHIP_FLOOR_MAX`, default `2`, sanitised (`:1162`). Also `WRAP_LEDGER_BIN` and `SESSION_WRITES_LIB`.

**(c) Ownership.**
- 📦 case: `session_unlanded_mine "$TP_MECH" "$cwd" "$trunk"` from `hooks/lib/session-writes.sh:375-433`. It needs `TRUNK` to be non-empty and not `none` (`:1148-1149`).
  - rc 0: `git diff --name-only trunk..HEAD` intersects this session's edit paths.
  - rc 1: no edit paths, or no intersection.
  - rc 2: no trunk, no git, unreadable transcript, `rev-parse` or `mktemp` failure, or diff failure or timeout (`:377-383`, `:414-417`).
- 🚀 case: `session_writes_paths` must return rc 0, meaning any edit ever made in the session (`:1153-1155`).
- **Only rc 0 permits the block.** rc 1 and rc 2 both log `ship-floor-not-mine` and abstain (`:1150-1151`, `:1154-1155`). A missing function also abstains silently (`:1147`, `:1153`).

**(d) Exemptions.**
- Kill-switch, assignee (0 or 2), teardown, not-mine, latched and budget-spent (silent to the model, stderr only; `:1175`).
- **Not exempt:** headless and `/goal`. Neither is consulted.
- **Disable switch:** `CC_SHIP_FLOOR` ≠ `1`.

---

## 4. Arm D: wake floor, which also carries the mail and custody signal (`wake_floor`, `:603-895`)

The checks run in this order.

**(a) Trigger.**
1. `CC_WAKE_FLOOR` is `"1"` (default 1) (`:604`).
2. `jq` is present (`:605`).
3. `mailbox_wake_armed` is defined, meaning the mailbox library was sourced (`:606`).
4. `_ouid` is a safe key (`:607`). `_ouid` is `CC_PANE_ID`, else `ITERM_SESSION_ID##*:`, canonicalised via `mailbox_resolve_key` (`:420`, `:453-466`).
5. If already armed, the floor deletes its budget file and returns (`:614`). "Armed" means `<mbx>/<key>.watching` has an mtime within `CC_WATCH_FRESH_S` (default 90, not sanitised) and its recorded pid is alive, or no pid is recorded (`hooks/lib/mailbox-pending.sh:291-301`).
6. It reads its state and computes `pend = lines − seen` (`:616-630`; `mailbox-pending.sh:245`).
7. Headless abstain (`:656-664`).
8. Live `/goal` with pending mail: abstain (`:692-704`).
9. It counts open custody (`:731-766`).
10. Assignee or teardown abstain (`:776-798`).
11. **Fire condition:** `cnt == 0` (first idle) **or** `pend > 0` **or** `cust > 0` (`:805`).
12. If `cnt ≥ max`, it prints a `systemMessage` only and allows the Stop (`:836-843`).
13. If less than the TTL has passed since the last attempt, it abstains (`:845-848`).
14. Kill-switch: prints a `systemMessage` only (`:850-854`).
15. It writes its state and **blocks** with "🔔 WAKE FLOOR … arm `cc-await-ping --timeout ${CC_WAKE_FLOOR_TIMEOUT_S:-14400} --interval 15`" (`:856-894`). Under a live goal the instruction becomes `--idle-scoped --sid` (`:827-833`). The reason is prefixed with the pending count and a custody note (`:872-888`).

**(b) Budget.**
- File: `${CC_MAILBOX_DIR:-$HOME/.claude/mailbox}/<canonical key>.wakefloor`, with lines `sid=`, `count=`, `ts=` (`:610-611`, `:856`).
- A new sid resets the count (`:627`).
- Env vars:
  - `CC_WAKE_FLOOR_MAX` default `2` (sanitised; `:807`)
  - `CC_WAKE_FLOOR_TTL_S` default `600` (`:808`)
  - `CC_WAKE_FLOOR_TIMEOUT_S` default `14400` (text only; `:821`)
  - `CC_WATCH_FRESH_S` default 90
  - `CC_CUSTODY_BIN` (test seam; `:737`)
  - `CC_WAKE_FLOOR_TEARDOWN` default 1 (`:776`)
  - `CC_MAILBOX_DIR`
- Arming a watcher deletes the budget file (`:614`). As the comment at `:478-483` explains, this self-healing means compliance resets the cap.

**(c) Ownership (custody).**
- Inline jq over `cc-custody list --open --cwd "$cwd" --json`, using the raw pane key `_opane` (`:743-758`).
  - "Mine": `originatorPane == pane`, or `notifyBack == pane`, or `notifyBack` ends with `-<pane>`.
  - "Unknown": the row has neither field.
  - Rows naming another pane are **dropped**.
- With no pane id, no jq or an unreadable store, it falls back to `cc-custody count --open --cwd` and treats all rows as unknown (`:759-765`).
- `cust = mine + unk`, and **either one alone** satisfies the fire condition. Stale rows count (`bin/cc-custody:45-49`).

**(d) Exemptions.**
- **Headless:** `CC_PANE_ID` is set **and** `ITERM_SESSION_ID` is empty (`:656`).
- **Live `/goal` with pending mail:** `goal_live_condition` from `hooks/lib/goal-state.sh:60-73` (the last `goal_status` attachment has neither met nor failed) and `pend > 0` (`:697`).
- **Assignee:** rc 0 or 2 exempt; rc 1 does not (`:778-785`).
- **Teardown:** `wf_teardown_marked` (`:786`). Both of these are gated by `CC_WAKE_FLOOR_TEARDOWN=1`.
- Budget exhausted, TTL and kill-switch, as listed above.
- **Disable switch:** `CC_WAKE_FLOOR` ≠ `1`.

### Does unread peer mail block a Stop by itself?

**Not through delivery.**
- In the no-sentinel path, pending mail only **re-opens the wake floor's fire condition** (`:805`). The resulting block asks the model to *arm a watcher*. It carries a count ("📬 N message(s) are pending", `:872-874`) and none of the message bodies. It is still bounded by budget, TTL, kill-switch, headless, goal and assignee/teardown.
- If a watcher is already armed, pending mail does nothing (`:614`).

**What the mail fold at the end of the file does (`:1284-1343`):**
- It runs only in the armed path, after the cap check. So it only piggy-backs on an Arm A or Arm B block and never causes one.
- It claims a non-waiting drain lock (`mailbox_drain_claim` = `_mbx_lock "<key>.drain" 0`; `mailbox-pending.sh:507-510`).
- It peeks the whole window without a line cap (`mailbox_window_end … 0`, `:1293`).
- It prepends the bodies to the block reason and adds a `systemMessage` (`:1309-1324`).
- It advances `.seen` only after the jq emit succeeds (`:1336-1339`), then releases the claim (`:1340`).

**What it does not do:**
- It does not ack. `.acked` is promoted only on the next Stop (`:467`).
- It does not deliver when another drain holds the claim; mail stays empty for this Stop.
- It never runs on floor blocks, cap exits, kill-switch exits or SID-mismatch exits.
- With an older library it falls back to `mailbox_take … 0` (`:1296-1297`).

---

## 5. Shared ownership and exemption helpers

**Assignee check: `hooks/lib/agent-identity.sh`.**
- `agent_assignee_argv` (`:33-77`) walks up to `CC_WF_MAX_HOPS` (default `8`) ancestors from `CC_WF_START_PID` (default `$$`). It uses `CC_WF_PSTABLE_FILE` when set, else `ps`.
  - It requires all three flags `--agent-id`, `--agent-name` and `--team-name`, and requires `id == name@team`.
  - rc 0 means matched (the id is echoed); rc 1 means not matched.
- `agent_team_member_confirms` (`:93-124`) scans `CC_WF_TEAM_ROOTS`, else `$CLAUDE_CONFIG_DIR/teams` plus `~/.claude*/teams`.
  - rc 0 = CONFIRMED (the config lists a non-lead member with that name).
  - rc 1 = REFUTED (a config exists without that member).
  - rc 2 = UNKNOWN (no config, or the id is not shaped `*@session-*`).
- If the library is missing, stubs return "not an assignee" and `2` (`hooks/session-continue.sh:539-542`).
- All three floors call the raw pair. None uses `agent_is_assignee`'s shape gate (`agent-identity.sh:143-147`). So an argv match whose team name does not start with `session-` returns 2 and is **exempt** in all three.
- The override `AGENT_IDENTITY_LIB` bypasses the lookup chain entirely (`:525-533`).

**Teardown marker: `wf_teardown_marked` (`:551-568`).**
- It looks for `${CC_TEARDOWN_DIR:-$HOME/.claude/watchdog/teardown}/{<sid>,<pane>}.json` with an mtime within `CC_WF_TEARDOWN_FRESH_S` (default `1800`, sanitised).
- A sid-named file matches outright. A pane-named file matches if its `"sid"` field is empty or equals this session's.
- It does **not** check `"mode":"teardown"`. The watchdog that the comment claims to mirror does check it (`hooks/lead-crash-watchdog.sh:258`).

---

## 6. Environment variables with different literal defaults

- **`CC_MECH_MAX`:** default `3` in the `clear` verb (`hooks/session-continue.sh:261`), default `2` in `mechanical_arm` (`:1053`). A default-configured `clear` therefore writes a count of 3 against a maximum of 2.
- **Teardown freshness:** not the same variable, but the two readers diverge. The code this reader claims to copy uses a hardcoded `-mmin -30` plus a `mode` check (`hooks/lead-crash-watchdog.sh:257-258`). This hook uses a tunable `CC_WF_TEARDOWN_FRESH_S:-1800` with no `mode` check.

I read no other file that uses a conflicting default. I had no search tool, so the rest of the tree is unchecked.

---

## 7. Stale or false citations and claims (checked)

| Where | Claim | Reality |
|---|---|---|
| `session-continue.sh:424`, `:724` | `_opane` captured at `:197` | It is at `:425` |
| `:433` | `mailbox_promote_acked (:213)` | It is at `:467` |
| `:441` | "the floor (:416)" | The floor's arm command is at `:821` |
| `:545-546` | the watchdog's `classify_death (:255-278)` | Those lines are the end of `retired_by_desk` and `close_record_summary` (`lead-crash-watchdog.sh:249-277`) |
| `:944` | `ship_floor :969`, `wake_floor :732-736` | Actually `:1101` and `:850-854` |
| `:952` | `:865-869`, `:587-608` | Actually `:1103-1109` and `:776-798` |
| `:965` | wake floor at `:589-594` | Actually `:778-785` |
| `:974` | "sibling at :974" | Actually `:1106` |
| `:1327` | "precedent at :502" | `:502` is a comment line |
| `:963-966` | the wake floor's assignee semantics differ from the other two | False in code: all three exempt on 0 or 2 and do not exempt on 1 (`:780-783`, `:970`, `:1105`) |
| `:922-923` | "SELF-CLEARING" | True only of the arming predicate, not of the armed sentinel (section 2) |
| `hooks/lib/mailbox-pending.sh:151` | the `stat -f` idiom is at `hooks/session-continue.sh:328` | It is at `:559` |
| `hooks/lib/session-writes.sh:421` | `session-continue.sh` sets `-o pipefail` | The file sets no shell options (`session-continue.sh:364-366`) |
| `hooks/lib/session-writes.sh:423-424` | "the sibling at :269 still has that shape" | `session_dirty_mine` now uses a herestring (`:354`) |
| `session-continue.sh:318` | `hook-chain.sh:78` says "every member always runs" | The text is at `hooks/hook-chain.sh:77-78`, but that dispatcher is not wired into `settings.json` (`:24-25`). The claim therefore rests on the harness, not on code here |

**Not verified:** the Stop-chain positions (session-continue 4th, completion-assert 6th; `:323`), because I could not find a `settings.json` in the snapshot.
