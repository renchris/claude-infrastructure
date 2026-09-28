# `hooks/session-continue.sh`: every way it blocks a Stop (snapshot 47c3317eb)

The brief gives the path `/tmp/o55probe-repo-47c3317eb`. I read the same snapshot at `/tmp/s55/repo-47c3317eb`, the path I was pointed to. Every citation below is to a line I read.

## 0. How the hook decides, and in what order

**How a Stop reaches the arms.** Claude Code runs the hook with no argument, so none of `--why`, `set`, `clear` or `status` matches (`hooks/session-continue.sh:105`, `:138-304`). The hook also has to load `hooks/lib/continue-sentinel.sh`. If it can't, a Stop exits 0, which lets the stop through (`:125-131`).

**What runs on every Stop before any decision:**
- It reads `cwd` from the Stop JSON's `.cwd`, falling back to `$PWD` (`:309-310`).
- It computes the sentinel path `f` (`:311`).
- It sets `cur_sid` from `.session_id`, falling back to `$CLAUDE_CODE_SESSION_ID` (`:312-313`).
- It deletes the previous `${f}.blocked` marker (`:331-332`).
- It moves the inbox's `.acked` cursor up to `.seen` (`mailbox_promote_acked`, `:467`; `hooks/lib/mailbox-pending.sh:560-567`).

**Where the sentinel lives.** The path is `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/state/continue-<first 16 hex of shasum("<config-dir>|<cwd>")>` (`hooks/lib/continue-sentinel.sh:17-27`). It is keyed on the config dir and the directory, not on the session. Every counter and latch below except the wake floor's is a sidecar file next to it: `.count`, `.mech`, `.ship`, `.sid`, `.cwd`, `.blocked`.

**The one condition that decides which arms run** is `if [ ! -f "$f" ]` (`:1205`):
- **No sentinel for this cwd:** the floors run, in order: mechanical arm, then ship floor, then wake floor (`:1207-1219`). This is a **going-idle** Stop.
- **A sentinel exists** (from before, or just written by the mechanical arm): the floors are skipped entirely. The armed path runs its checks in this order: kill switch (`:1228`), session-id binding (`:1245`), cap (`:1258`), counter increment (`:1269-1270`), mail fold (`:1284-1299`), block (`:1329-1335`).

**What each arm returns:**
- The mechanical arm is called in-process. Return 0 means "armed", and control falls through to the armed path (`:1221-1223`).
- The ship floor and wake floor each run in a subshell. Return 1 means "block": the hook marks the Stop blocked, prints the JSON and exits 0 (`:1208-1217`).
- In actuation mode the hook always exits 0. The block is carried only by `{decision:"block"}` in the printed JSON (`:1211`, `:1344`).

## 1. Arm: the agent-armed sentinel (the "continue" block)

**(a) Trigger.** The sentinel file `$f` exists. The agent writes it with `session-continue.sh set "<step>"`, which:
- writes the step text,
- deletes `.count`,
- writes `.sid` only if `CLAUDE_CODE_SESSION_ID` or `CLAUDE_SESSION_ID` is set,
- writes `.cwd` (`:139-156`).

After that it must pass three checks: no kill phrase (`:1228`), matching session id (`:1246`), and `.count` below the cap (`:1258`).

Nothing in this arm looks at the working tree, the ledger rung, the mailbox or dispatched work. Once the sentinel exists, it blocks on that alone.

**(b) Bound.**
- The counter is `${f}.count`, keyed on the same `(config-dir|cwd)` hash. A non-numeric value reads as 0 (`:1256-1257`, `:1270`).
- `CLAUDE_CONTINUE_MAX` defaults to `8` (`:1255`). At the cap the hook deletes the sentinel and its `.count`, `.sid` and `.cwd` files. It prints a `systemMessage` naming the re-arm command and allows the stop (`:1258-1268`).
- `.count` is reset by:
  - `set` (`:142`),
  - entering the floor path (`:1206`),
  - the cap (`:1260`), the kill switch (`:1229`), a session-id mismatch (`:1247`),
  - `clear` (`:253`).
- `CLAUDE_MAX` is never checked for being numeric. A non-numeric value makes the test at `:1258` error out and read false, so the cap never fires.
- `CLAUDE_CONFIG_DIR` changes both the state directory and the hash key (`hooks/lib/continue-sentinel.sh:18,25`).

**(c) "Is this sentinel mine?"** There is no library call; the check is inline at `:1245-1252`. It compares the stored `.sid` with `cur_sid`, and clears the sentinel and allows only when **both are non-empty and differ**. If either is empty, the block goes ahead. Consequences:
- A sentinel armed from a bare shell (no `.sid`) blocks every session in that cwd.
- Because the key is the cwd, **any sibling session in the same checkout that Stops first deletes another session's live chain** and goes idle itself (`:1247`).
- The only other ownership check is the opt-in `clear --if-mine` CLI guard (`:212-245`), which never runs during a Stop.

**(d) Suppressors.**
- **Kill switch:** `KILL_RE` (`:348`) is matched against the last user record in the transcript that is not an injected slash-command body (`isMeta`) (`last_user_msg`, `:351-388`). A match clears the sentinel and allows the stop (`:1228-1233`). With no `transcript_path` the kill switch cannot fire (`:355`, `:392`).
- **Not in the armed path at all:** team-assignee, teardown, headless and live-`/goal` checks.
- **No env var disables this arm.** The off switch is `clear`. `CLAUDE_CONTINUE_MAX=0` has a similar effect: the cap path fires on every Stop, deleting the sentinel and emitting a `systemMessage` without blocking.

## 2. Arm: mechanical uncommitted-writes (`mechanical_arm`, `:938-1079`)

**(a) Trigger.** Only reached when there is no sentinel. Every step below must pass, in order:
1. `CC_MECH_CONTINUE` is not `"0"` (`:939`), and `jq` is available (`:940`).
2. No kill phrase. A match is logged as `mechanical-kill-switch` (`:950`).
3. The session is not a team assignee (`:967-981`) and has no teardown marker (`:983`).
4. The `session-writes` library is found (`:985-998`), the wrap-ledger script is found and produces output (`:1005-1014`), and that output is cached in `SC_LED_CACHE` (`:1015`).
5. The ledger reports **`RUNG=🔧`** (`:1016-1017`). In `scripts/wrap-ledger.sh`:
   - ⛔ (an open operator decision) is checked first and outranks everything (`:1971-1978`). **Your own dirty files under ⛔ never arm this.**
   - A dirty tree gives 🔧 (`:1979-1980`). Dirty means `git status --porcelain` is non-empty (`:526-529`).
6. `session_dirty_mine "$TP_MECH" "$cwd"` returns 0 with output (`:1022-1028`).
7. The `.mech` budget is not spent (`:1062-1067`).

If all pass, it writes the sentinel with the step "Commit the N file(s)…", plus `.sid` and `.cwd` (`:1070-1075`), and returns 0.

**(b) Bound.**
- The budget is stored in `${f}.mech` as `"<sid> <count>"` (`:1068`), keyed on the cwd hash plus the stored sid. A different sid resets the count to 0 (`:1060`).
- `CC_MECH_MAX` defaults to **`2`** here (`:1053`), with no numeric check. A non-numeric value makes the test at `:1062` error out and read false, so the budget never binds.
- None of the armed path's clears remove `.mech` (`:1229`, `:1247`, `:1260`).
- `clear` marks the budget spent by writing `"<sid> ${CC_MECH_MAX:-3}"` (`:260-261`). A `clear` from a bare shell writes sid `?`, which does not match a real `cur_sid` at `:1060`, so that spend doesn't bind the real session.
- Tuning variables:
  - `SESSION_WRITES_LIB` (`:986`) and `WRAP_LEDGER_BIN` (`:1006`).
  - `SESSION_WRITES_TIMEOUT_S` defaults to `5` (`hooks/lib/session-writes.sh:171`). The `git status` inside `session_dirty_mine` is hard-bounded to 5 seconds (`:319`).
  - The identity and teardown variables listed under the wake floor below. The mechanical arm calls `wf_teardown_marked` **unconditionally**; `CC_WAKE_FLOOR_TEARDOWN` does not gate it here.
- The bounds it inherits are covered in §6, question 3.

**(c) "Is this dirt mine?"** Decided by `hooks/lib/session-writes.sh` `session_dirty_mine` (`:277-361`). It intersects:
- the paths from `git -c core.quotePath=false status --porcelain -z -uall` at the repo top level (`:319`), with
- the paths this session wrote with Write, Edit, MultiEdit or NotebookEdit (`:180`), taken from the main transcript plus its `subagents/*.jsonl` files (`:143-147`, `:124-129`). Both sides are canonicalised to physical paths (`:292-299`).

| rc | Meaning | Blocks? |
|---|---|---|
| 0 | At least one dirty path is mine; repo-relative paths on stdout (`:359`) | **Yes — the only one** (`:1023`) |
| 1 | The session wrote nothing (`:283`), or nothing of mine is dirty (`:360`) | No |
| 2 | Can't tell: no git (`:279`), no jq or transcript, a read error or timeout (`:137-139`, `:188`, `:282`), no repo top level (`:285-286`), mktemp or status failure (`:318-321`) | No |

A file written only through Bash is invisible here, because only those four tool names are selected (`:180`).

**(d) Suppressors.**
- **Disables the arm outright:** `CC_MECH_CONTINUE=0` (`:939`).
- **Kill phrase** (`:950`).
- **Team assignee:** `agent_assignee_argv` succeeds and `agent_team_member_confirms` returns **0 or 2** (`:968-980`). Return 1 (refuted) does not exempt.
- **Teardown marker** (`:983`).
- **Not checked here:** headless and live `/goal`.

## 3. Arm: ship floor (`ship_floor`, `:1098-1199`)

**(a) Trigger.** Only reached when there is no sentinel and the mechanical arm returned 1 (`:1207-1208`). In order:
1. `CC_SHIP_FLOOR` is exactly `1` (`:1099`), and `jq` is available (`:1100`).
2. No kill phrase (`:1101`), not a team assignee returning 0 or 2 (`:1102-1109`), no teardown marker (`:1110`).
3. The ledger, reused from `SC_LED_CACHE` or recomputed (`:1115-1126`), reports **`RUNG` 📦 or 🚀** (`:1127-1128`):
   - **📦** means: not ⛔, not dirty, no DoD remainder, and unlanded. Unlanded means `AHEAD>0` or `git cherry` has a `+` line (`scripts/wrap-ledger.sh:532-539`, `:1983-1984`).
   - **🚀** means: the ✅-eligible branch applies, no custody is open, a trunk is set, and `LIVE_BREACH=1` (`:1990-2056`).
4. Ownership (see c):
   - **📦:** a `TRUNK` value that is present and not `none` (`:1148-1149`), and `session_unlanded_mine` returns 0 (`:1150`).
   - **🚀:** `session_writes_paths` returns 0 (`:1154`). That is any write anywhere in the session; it is not limited to this repo.
5. The current HEAD sha differs from the latched sha (`:1172`), and the count is below the maximum (`:1174`).

Then it writes the budget line (`:1179`) and prints the block (`:1197`).

**(b) Bound.**
- Stored in `${f}.ship` as `"<sid> <HEAD-sha> <count>"` (`:1179`), keyed on the cwd hash. A different sid resets both the count and the sha latch (`:1170`).
- It fires once per HEAD sha (`:1172-1173`).
- `CC_SHIP_FLOOR_MAX` defaults to `2`, and non-numeric values fall back to 2 (`:1162`).
- When the budget is spent it logs and writes to stderr only; the model sees nothing (`:1174-1178`).
- Other tuning variables: `WRAP_LEDGER_BIN`, `SESSION_WRITES_LIB` (`:1117`, `:1133`), plus the identity and teardown variables below.

**(c) "Is this unlanded work mine?"**
- **📦:** `hooks/lib/session-writes.sh` `session_unlanded_mine` (`:375-433`). It intersects `git diff --name-only trunk..HEAD` (`:415`) with the canonicalised paths the session wrote.

  | rc | Meaning | Blocks? |
  |---|---|---|
  | 0 | Some unlanded commit touches a file I wrote | **Yes — the only one** |
  | 1 | I wrote nothing (`:381`), or there is no overlap (`:432`) | No |
  | 2 | Can't tell: no trunk, no git, unreadable transcript, no repo top level, mktemp/diff failure or timeout (`:377-383`, `:414-417`) | No |

  Returns 1 and 2 both go to the same `|| { log "ship-floor-not-mine"; return 0; }` (`:1150-1151`).
- **🚀:** `session_writes_paths` (`:200`). Return 0 = wrote, 1 = nothing, 2 = can't tell. Only 0 blocks (`:1154-1155`).

**(d) Suppressors.**
- **Disables the arm outright:** `CC_SHIP_FLOOR` set to anything other than `1` (`:1099`).
- **Kill phrase** (`:1101`), **team assignee** returning 0 or 2 (`:1105`), **teardown marker** (`:1110`).
- **Already fired** for this sha (`:1172`), or **budget spent** (`:1174`).
- **Not checked here:** headless and live `/goal`.

## 4. Arm: wake / mail / custody floor (`wake_floor`, `:603-895`)

**(a) Trigger.** Only reached when there is no sentinel, the mechanical arm returned 1, and the ship floor returned 0 (`:1207-1213`). In order:
1. `CC_WAKE_FLOOR` is `1` (`:604`), `jq` is available (`:605`), and the mailbox library is loaded (`:606`; it is loaded only if both the file and `jq` exist, `:426-429`).
2. The inbox key `$_ouid` is valid (`:607`):
   - It comes from `CC_PANE_ID`, else `ITERM_SESSION_ID`, taking the part after the last `:` (`:420`).
   - It is then canonicalised with `mailbox_resolve_key` (`:453-466`).
3. **No watcher is armed:** `mailbox_wake_armed` requires a `.watching` file no older than `CC_WATCH_FRESH_S:-90` seconds whose pid is alive (`hooks/lib/mailbox-pending.sh:291-301`). If a watcher is armed, the budget file is deleted (`:614`).
4. Pending mail is counted: `pend` = lines in the inbox file minus the `.seen` cursor (`:629`; `mailbox-pending.sh:245`).
5. **Not headless:** the floor stands down when `CC_PANE_ID` is set and `ITERM_SESSION_ID` is empty (`:656-664`).
6. **Live `/goal`:** if a goal is live and mail is pending, the floor stands down (`:692-704`). If a goal is live with no mail pending, the floor carries on but names the `--idle-scoped` watcher command (`:827-833`).
7. Custody is counted (`:731-766`).
8. **Team-assignee / teardown stand-down** (`:776-798`).
9. **Fire condition:** `cnt==0` **or** `pend>0` **or** `cust>0` (`:805`). In other words: the first idle of the session, mail waiting, or open dispatched work.
10. `cnt` is below `maxa` (`:836`), the TTL has elapsed (`:845`), and there is no kill phrase (`:850`).

Then it writes the budget file (`:856`) and prints the block (`:892-894`).

**(b) Bound.**
- Stored in `${CC_MAILBOX_DIR:-$HOME/.claude/mailbox}/<_ouid>.wakefloor` as `sid=`, `count=` and `ts=` lines (`:610-611`, `:856`). It is keyed on the canonical inbox key, not the cwd. A different sid resets it (`:627`), and an armed watcher deletes it (`:614`).
- `CC_WAKE_FLOOR_MAX` defaults to `2` (`:807`).
- `CC_WAKE_FLOOR_TTL_S` defaults to `600` (`:808`).
- `CC_WAKE_FLOOR_TIMEOUT_S` defaults to `14400`, but only appears in the message text (`:821`).
- `CC_WATCH_FRESH_S` defaults to `90` (`mailbox-pending.sh:297`).
- `CC_MBX_SESSION_KEY` defaults to `1` (`mailbox-pending.sh:906`).
- `CC_CUSTODY_BIN` is a test override (`:737`).
- When the budget is exhausted it prints a `systemMessage` but does not block (`:836-843`).
- Teardown and identity variables:
  - `CC_WAKE_FLOOR_TEARDOWN` defaults to `1` (`:776`).
  - `CC_TEARDOWN_DIR` defaults to `$HOME/.claude/watchdog/teardown` (`:553`).
  - `CC_WF_TEARDOWN_FRESH_S` defaults to `1800` (`:555`).
  - `AGENT_IDENTITY_LIB` is a hard override (`:525`). If it points at a missing file, a stub is used that says "not an assignee" (`:539-542`).
  - In `hooks/lib/agent-identity.sh`: `CC_WF_PSTABLE_FILE` (`:35`); `CC_WF_START_PID` defaults to `$$` and `CC_WF_MAX_HOPS` defaults to `8` (`:46`); `CC_WF_TEAM_ROOTS` (`:103-108`).

**(c) "Is this mine?"**
- **Mail:** there is no attribution step. The inbox key is this session's own, taken from its pane id. `mailbox_resolve_key` (`mailbox-pending.sh:903-913`) returns 1 for an invalid key (echoing it unchanged) and 0 when it resolves. It resolves to the key itself when `CC_MBX_SESSION_KEY=0` or when an un-aliased inbox exists, and otherwise to the alias target, which may be empty. The hook ignores the return code and only adopts an output that is non-empty and correctly shaped (`:459-463`).
- **Custody:** this is inline `jq`, not a library function (`:748-754`). A row is **mine** if `originatorPane == $_opane`, or `notifyBack == $_opane`, or `notifyBack` ends with `-$_opane`. A row is **unknown** if it has neither field. Rows owned by another pane are dropped. Unknown rows still count (`:758`). With no pane id, or if the list call fails, `cc-custody count --open --cwd` is used and every row counts as unknown (`:760-765`).
- **Identity:** `agent_assignee_argv` (`agent-identity.sh:33-77`) returns 0 and prints the id when some ancestor process has a self-consistent `--agent-id n@t --agent-name n --team-name t`; otherwise 1. `agent_team_member_confirms` (`:93-124`) returns 0 (confirmed), 1 (refuted) or 2 (unknown). The wake floor stands down on 0 or 2; **only 1, or argv failing, lets it block** (`:778-784`).
- **Teardown:** `wf_teardown_marked` (`:551-568`) returns 0 when a fresh marker exists either at `<tdir>/<cur_sid>.json`, or at `<tdir>/<pane>.json` with `"sid"` empty or equal to `cur_sid`. Otherwise it returns 1, and only 1 lets the floor block.
- **None of this is needed for the first fire.** When `cnt==0` the floor fires with no mail and no custody (`:805`).

**(d) Suppressors.**
- **Disables the arm outright:** `CC_WAKE_FLOOR` set to anything other than `1` (`:604`).
- **Missing capability:** no `jq`, no library, or an invalid or empty key, e.g. no pane id at all (`:605-607`).
- **Watcher already armed** (`:614`).
- **Headless** (`:656`).
- **Live `/goal` with mail pending** (`:697`).
- **Team assignee (0 or 2) or teardown marker**, only while `CC_WAKE_FLOOR_TEARDOWN=1` (`:776-798`).
- **Already fired once, with nothing pending and no custody** (`:805`).
- **Budget spent** (`:836`) or **TTL not elapsed** (`:845`).
- **Kill phrase:** prints a `systemMessage` instead of blocking (`:850-854`).

## 5. Other things found

- **No other path prints a block.** The ship floor prints nothing when it returns 0. It has no stdout writes on those paths; `:1175` goes to stderr.
- **The double-block marker.** `mark_blocked` writes `${f}.blocked` as `"sid epoch arm"`, where arm is `ship-floor`, `wake-floor` or `continue` (`:333-336`, `:1209`, `:1214`, `:1329`). `hooks/completion-assert.sh:866-869` reads it, records `double-block-yield`, and sets `contra=0`. So this hook's block suppresses a second hook's block; it never adds one. The marker is written before the `jq` emit, so if that emit fails the marker is still set (`:1329-1335`).
- **Chain position.** `settings-templates/settings.example.json:464-477` places this hook 4th and completion-assert 6th in the Stop chain. I checked this against the template, not a live settings file.

## 6. The five explicit questions

1. **Order and the single gate.** Everything is decided by whether `$f` exists (`:1205`).
   - **No sentinel:** mechanical arm (which can only arm), then ship floor, then wake floor. The first to return 1 prints and exits (`:1207-1219`).
   - **A sentinel exists, or the mechanical arm just wrote one:** kill switch, then session-id binding, then cap, then mail fold, then block (`:1228-1335`).
   - Before either branch: the Stop must be in actuation mode and the sentinel library must have loaded (`:125-131`).

2. **How many blocks per Stop: at most one.** Each blocking branch prints a single JSON object and exits (`:1208-1211`, `:1213-1216`, `:1329-1344`). The only other stdout output is a non-blocking `systemMessage`: from the wake floor when it returns 0 (`:1218`), or from the cap (`:1264`). Every exit path prints at most one JSON object in total.

3. **The arm that never prints a block but causes one: the mechanical arm.**
   - It only writes the sentinel (`:1070`). The block itself comes from the armed path.
   - It inherits the armed path's kill switch (`:1228`), session-id binding (`:1245`), and the `CLAUDE_CONTINUE_MAX:-8` cap with its re-arm message (`:1255-1268`). It also inherits the mail fold and the `continue` marker.
   - `.count` starts fresh at every mechanical arm (`:1206`), and the cap deletes the sentinel but not `.mech` (`:1260`). The worst case is therefore `CC_MECH_MAX × CLAUDE_CONTINUE_MAX` = 2 × 8 = **16 blocks**.
   - It does **not** inherit its own exemptions. The sentinel survives from Stop to Stop, and the floors are skipped while it exists, so on later Stops nothing re-checks team-assignee, teardown or dirt. The chain keeps blocking even after the model commits, until `clear`, the cap, a kill phrase or a sid mismatch.

4. **Does unread peer mail block a Stop by itself? No.**
   - Mail matters only to the **wake floor**. There, `pend>0` only lets the floor fire again after its first fire (`:805`). It is still limited by: an already-armed watcher (`:614`), the headless stand-down (`:656`), the live-`/goal` stand-down (which fires *because* mail is pending, `:697`), the team-assignee/teardown stand-down (`:789`), `CC_WAKE_FLOOR_MAX` (`:836`), the TTL (`:845`) and the kill phrase (`:850`).
   - That block delivers no mail. It only tells the model to arm a watcher (`:858-874`).
   - **The mail fold** (`:1284-1340`) runs only inside a sentinel block that has already been decided, i.e. after the cap check. When it runs, it:
     - takes the drain lock (`mailbox_drain_claim`), and delivers nothing if a live drain already holds it (`mailbox-pending.sh:507-510`);
     - reads the new lines from `.seen` to end of file without advancing any cursor (`:1292-1294`; unlimited window, `mailbox-pending.sh:518-526`);
     - adds them to the top of the block reason, plus a `systemMessage` (`:1309-1324`);
     - advances `.seen` only after `jq` has printed the block (`:1337-1339`);
     - releases the lock (`:1340`).
   - The mail fold does **not**:
     - decide whether to block,
     - run on the floor paths,
     - touch `.count` or any budget,
     - advance `.acked` (that happens at the next Stop's `promote`, `:467`).
   - With an older mailbox library the fold uses `mailbox_take …0` instead, which advances `.seen` before the block is printed (`:1296-1297`).

5. **One env var with different defaults: `CC_MECH_MAX`.** The `clear` command writes `${CC_MECH_MAX:-3}` (`hooks/session-continue.sh:261`). The mechanical arm reads it as `${CC_MECH_MAX:-2}` (`:1053`).
   - When unset, both still agree the budget is spent (3 ≥ 2).
   - If it is set in the hook's environment but not in the shell running `clear` (for example 5 vs. the default 3), `clear` no longer spends the budget.
   - Checked and consistent across the tree: `CC_WATCH_FRESH_S` is 90 in three places (`mailbox-pending.sh:297`, `bin/cc-notify:1297`, `bin/cc-await-ping:385`); `CC_TEARDOWN_DIR` and `CC_MAILBOX_DIR` have the same defaults everywhere grep found them.
   - Related, but not an env default: the teardown window here is `CC_WF_TEARDOWN_FRESH_S:-1800` (`:555`), while `hooks/lead-crash-watchdog.sh:257` hard-codes `-mmin -30`. Setting the variable breaks the "same window as the watchdog" contract claimed at `:544-546`.

## 7. Stale citations and comments I checked

| Where | What it claims | What the code shows |
|---|---|---|
| `session-continue.sh:433` | `mailbox_promote_acked (:213)` | The call is at `:467` |
| `:441-442` | "The floor (:416)" | The watcher command is at `:821` |
| `:724` | `$_opane` captured "at :197" | Captured at `:425` |
| `:944` | ship floor kill switch `:969`, wake floor `:732-736` | `:1101`, `:850-854` |
| `:952` | ship floor `:865-869`, wake floor `:587-608` | `:1102-1109`, `:776-798` |
| `:965` | `(:589-594)` | `:780-784` |
| `:974` | "the sibling at :974" logs `{assignee,confirm_rc}` | `:974` is this very comment; the sibling is `:1106` |
| `:1082-1083` | Quotes the mechanical arm's header: "📦 must NOT fire" | No such sentence in `:897-929` |
| `:1326-1327` | "precedent at :502" | `:502` is prose about teardown |
| `:545` | `lead-crash-watchdog.sh classify_death (:255-278)` | Those lines are `retired_by_desk` / `close_record_summary` |
| `:547` | `marker_owns_sid` at `:112-118` | It is at `lead-crash-watchdog.sh:207-213` |
| `session-writes.sh:421-422` | `session-continue.sh` sets `-o pipefail` | It sets no shell options (grep; `:364-365` says so) |
| `session-writes.sh:423` | "the sibling at :269 still has that shape" | The sibling now uses a herestring, at `:354` |

Checked and still accurate: `:1203-1204` ("at most ONE floor emits"), `:323-324` (chain positions, checked against the template), and `:177` ("(:145)"; `.sid` is actually written at `:146`).

**Not verified:**
- `completion-assert.sh:39-49`, `:99-105`, `:236`, `:398`, and `mailbox-drain.sh:8-10`.
- `wrap-ledger`'s `count_blocking_decisions`, custody and live-layer internals.
- `cc-custody` beyond its `--open`/`--cwd`/`list`/`count` flags (`bin/cc-custody:152,162,235,252`).
- `_mbx_valid_uuid`, `mailbox_alias_of`, `_mbx_lock`.
