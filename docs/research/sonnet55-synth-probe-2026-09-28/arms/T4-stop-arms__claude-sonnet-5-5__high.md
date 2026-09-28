# When `hooks/session-continue.sh` blocks a Stop

Everything below is from code I read. All paths are relative to `/tmp/s55/repo-47c3317eb`.

- The brief names `/tmp/o55probe-repo-47c3317eb`. I read the pinned snapshot at `/tmp/s55/repo-47c3317eb`, as instructed.
- I did not read `bin/cc-custody`'s internals, `scripts/wrap-ledger.sh` beyond header and grep hits, or the body of `mailbox_resolve_key`. I did not run anything.

## 0. Entry, ordering, and payload count

**Actuation mode.**
- The hook only actuates when `$1` is not `--why`, `set`, `clear` or `status` (`hooks/session-continue.sh:105`, `:138-304`). It then reads the Stop JSON from stdin (`:308`).
- `cwd` comes from the stdin `.cwd`, falling back to `$PWD` (`:309-310`). `cur_sid` comes from stdin `.session_id`, falling back to `$CLAUDE_CODE_SESSION_ID` (`:312-313`).
- The sentinel path is `<CLAUDE_CONFIG_DIR|~/.claude>/state/continue-<first 16 hex of shasum(cfgdir|cwd)>` (`hooks/lib/continue-sentinel.sh:17-27`). It is keyed on config dir and cwd, not on session.

**The single condition that gates the floors.** The two floors and the mechanical arm are reached only when no sentinel file exists at `$f` (`hooks/session-continue.sh:1205`). If one exists, the hook goes straight to the armed path (`:1225` onward) and no floor is evaluated. The comment at `:1201-1202` says the same.

**Order within one Stop.**
1. `rm -f "$f.blocked"` (`:332`) and the unconditional mail lag-ack (`:467`). Neither can block.
2. If there is no sentinel:
   - `rm -f .count .sid .cwd` (`:1206`).
   - `mechanical_arm` (`:1207`).
   - If it did not arm, `ship_floor` (`:1208`), then `wake_floor` (`:1213`).
3. If there is a sentinel, or `mechanical_arm` just wrote one: kill-switch (`:1228`), SID-BIND (`:1246`), cap (`:1258`), mail fold (`:1284`), then one block (`:1329-1335`).

**How many block payloads.** At most one.
- Ship floor blocks, prints, `exit 0` (`:1208-1212`).
- Wake floor blocks, prints, `exit 0` (`:1213-1217`).
- The armed path has one `jq … decision:"block"` call (`:1329-1335`).
- On the wake floor's non-blocking exits, its stdout is at most a single `systemMessage` object, printed at `:1218`. The cap path also prints only a `systemMessage` (`:1264`).
- The hook always exits 0. The block travels in the JSON (`:1211`, `:1267`, `:1344`).

## 1. Agent-armed sentinel (and the shared armed path)

**(a) Trigger.**
- A sentinel file exists for `(config-dir, stdin cwd)` (`:1205` false).
- The sentinel was written by `session-continue.sh set`, which writes the step text, resets `.count`, and stamps `.sid` and `.cwd` (`:139-156`). It also fires for a mechanically written sentinel (see §2).
- No kill phrase is in the last genuine user message (`:1228`).
- The stored sid does not contradict the current sid (`:1245-1246`).
- `.count < MAX` (`:1258`).
- Nothing in the armed path looks at the working tree, the ledger rung, mail, or dispatched work. A sentinel armed for a tree that has since gone clean keeps blocking until it hits the cap or the agent runs `clear`. The "self-clearing" claim at `:922-923` is true only of re-arming, not of an already-armed sentinel.

**(b) Bound.**
- Counter file `${f}.count`, keyed on the sentinel hash. It is incremented at `:1269-1270`.
- `CLAUDE_CONTINUE_MAX`, default `8` (`:1255`). A non-numeric value makes the `-ge` test error and evaluate false, so blocking continues. That is my inference from the shell semantics, not something the code handles.
- A fresh `set` deletes `.count` (`:142`). Re-arming each turn therefore never reaches the cap.
- At the cap the hook deletes the sentinel and its sidecars, prints a `systemMessage` naming the re-arm lever, and allows the stop (`:1258-1267`).
- Setting `CLAUDE_CONTINUE_MAX=0` would clear and allow on the first Stop. That is inference; no code names it as a switch.

**(c) Ownership.**
- The only session attribution is SID-BIND: `.sid` is compared with `cur_sid`.
- It clears and allows only when both sids are non-empty and differ (`:1246`).
- The rules:
  - No `.sid` (bare-shell arm) → block.
  - Empty `cur_sid` → block.
  - Mismatch → clear and allow, logged as `sid-mismatch` (`:1247-1251`).
- No library is involved.
- `set` records `CLAUDE_CODE_SESSION_ID` or `CLAUDE_SESSION_ID` only if set, otherwise it removes the `.sid` (`:145-146`).

**(d) Exemptions.**
- Kill-switch: `KILL_RE` (`:348`) matched by `kill_switch_active` against `last_user_msg` (`:351-395`). The message is the last `type=="user"`, `isMeta != true` record read from `transcript_path`, and matching is `grep -iqE`. It clears the sentinel and allows (`:1228-1233`).
- The kill phrases in the regex:
  - "and [then] stop"
  - `no[ _-]?auto[ _-]?continue`
  - "just do X"
  - "stop here"
  - "come back to this"
  - a bare "stop" or "halt"
- Not exempted on this path: team assignee, teardown marker, headless, live `/goal`. None of those are consulted in `:1225-1344`.
- Operator escape hatch: `session-continue.sh clear`. It deletes the sentinel and sidecars, and always spends the mechanical budget (`:253-261`).
- No env var disables this arm. Setting `CLAUDE_CONTINUE_MAX=0` would neutralise it, as noted in (b).
- Missing `continue-sentinel.sh` makes the hook inert with `exit 0` (`:125-131`).

## 2. Mechanical uncommitted-writes arm

This arm never prints a block itself. It writes the sentinel and returns 0, and the armed path emits the block.

**(a) Trigger.** All of these must hold, checked in this order in `mechanical_arm` (`:938-1079`):
1. No sentinel (outer `if`, `:1205`).
2. `CC_MECH_CONTINUE` is not the string `0` (`:939`), and `jq` is present (`:940`).
3. No kill phrase in the last user message (`:950`), which is logged as `mechanical-kill-switch`.
4. Not a team assignee: `agent_assignee_argv` matches, and `agent_team_member_confirms` returns 0 or 2 (`:967-981`).
5. No fresh teardown marker naming this session (`:983`).
6. `session-writes.sh` is sourced (`:985-998`), and a `wrap-ledger.sh` is found (`:1006-1012`).
7. `bash wrap-ledger.sh --machine`, run in `cwd`, returns non-empty output with `RUNG=🔧` (`:1013-1017`). The ledger reaches 🔧 for a dirty tree, a gate that is stale on HEAD, a DoD remainder, or open custody (`scripts/wrap-ledger.sh:25`, `:1002`).
8. `session_dirty_mine "$TP_MECH" "$cwd"` returns rc 0 with non-empty output, meaning at least one dirty path was written by this session (`:1022-1028`).
9. The mechanical budget is not spent (see (b)).

**(b) Bound.**
- File `${f}.mech`, content `"<sid> <count>"`, keyed on the sentinel hash plus the sid inside it (`:1053-1060`, written at `:1068`).
- A different sid reads as count 0 (`:1060`).
- It is not deleted when the sentinel is cleared or capped, and `:1206` does not remove it.
- `CC_MECH_MAX` default is `2` at `:1053`.
- Once `mcnt >= mmax` the arm logs `mechanical-budget` and returns 1 (`:1062-1067`).
- It also inherits `CLAUDE_CONTINUE_MAX` (default 8), so the worst case is 2 × 8 = 16 consecutive blocks per session. The code comment says the same (`:1046-1051`).
- One quirk in `CC_MECH_MAX`: a non-numeric value would make the `-ge` test error and evaluate false, so the budget never binds. I found no digit sanitising at `:1053`, unlike the other budgets.

**(c) Ownership.** `session_dirty_mine` in `hooks/lib/session-writes.sh:277-361`.
- **What it does.**
  - It takes the session's edit-recorded paths from `session_writes_paths` (`:200`, `:135-193`). That reads Write, Edit, MultiEdit and NotebookEdit `tool_use` records in the transcript, plus `<session>/subagents/**/*.jsonl` (`:124-129`, `:145-147`).
  - It canonicalises those paths, runs `git status --porcelain -z -uall` in the repo top level, and intersects the two sets (`:317-357`).
- **Return codes:**
  - rc 0: at least one dirty path was written by this session.
  - rc 1: no session write, or none of them dirty.
  - rc 2: cannot tell (no git, no jq, unreadable transcript, git failure).
- **Which rc permits a block:** only rc 0 (`hooks/session-continue.sh:1023`). rc 1 and rc 2 both return 1 and no block results. The `session-writes.sh` header states the same (`:13-15`).
- **Blind spot.** A file written only through Bash is invisible to this oracle (`:41-44`).

**(d) Exemptions.**
- `CC_MECH_CONTINUE=0` disables the arm outright. It must be exactly `0`.
- Kill-switch, assignee (rc 0 or 2), and teardown marker each log and return 1 (`:950`, `:977-979`, `:983`).
- No headless or live-`/goal` check here. I found none in `:938-1079`.
- After arming, the armed path's own kill-switch, SID-BIND and cap still apply (`:1221-1222`).
- The mechanical arm writes `.sid` only if `cur_sid` is non-empty (`:1071`).

**The bare-shell `clear` does not spend the budget.**
- `clear` writes `"<sid-or-?> ${CC_MECH_MAX:-3}"` to `.mech` (`:260-261`).
- The arm treats a `.mech` whose sid differs from `cur_sid` as count 0 (`:1060`).
- So a bare-terminal `clear` (which records `?`) does not spend the budget for a real session. An agent's `clear` does, because the session id is exported into the shell.
- This is my reading of `:260-261` against `:1060`. I did not run it.

## 3. Ship floor

**(a) Trigger.** `ship_floor` (`:1098-1199`), reached only when no sentinel exists and `mechanical_arm` returned non-zero. It emits a block only if all of these hold:
1. `CC_SHIP_FLOOR` is exactly `1` (`:1099`), and `jq` is present.
2. No kill phrase (logged `ship-floor-kill-switch`).
3. Not an assignee (rc 0 or 2), and no teardown marker (`:1102-1110`).
4. The ledger sample is the cached `SC_LED_CACHE` from the mechanical arm, or a fresh `wrap-ledger.sh --machine` run (`:1115-1126`).
5. `RUNG` is `📦` or `🚀` (`:1128`).
6. Attribution passes (see (c)).
7. The HEAD-sha latch and budget pass (see (b)).

**(b) Latch and budget.**
- File `${f}.ship`, content `"<sid> <head-sha> <count>"`, keyed on the sentinel hash plus the sid inside it (`:1160-1171`, written at `:1179`).
- A different sid resets count and sha (`:1170`).
- Same sid and same HEAD sha logs `ship-floor-latched` and does not block, so it fires at most once per HEAD (`:1172-1173`).
- `CC_SHIP_FLOOR_MAX` default is `2` (`:1162`), and a non-numeric value falls back to 2.
- When `pcnt >= maxs` it logs `ship-floor-budget` and does not block (`:1174-1178`).
- The counter is written before the block is emitted (`:1179`).

**(c) Ownership.**
- **Rung 📦.**
  - It needs `session_unlanded_mine "$TP_MECH" "$cwd" "$trunk"` (`:1146-1151`, defined at `hooks/lib/session-writes.sh:375-433`).
  - `TRUNK` is read from the ledger, and an empty or `none` trunk returns silently (`hooks/session-continue.sh:1148-1149`).
  - Return codes:
    - rc 0: a file changed in `<trunk>..HEAD` was written by this session. This is the only rc that lets the floor fire.
    - rc 1: not mine.
    - rc 2: cannot tell (missing trunk, no git, unreadable transcript, or a failed or timed-out git diff) (`session-writes.sh:377-383`, `:415-417`).
  - The caller's `|| {…}` catches any non-zero, so rc 1 and rc 2 both log `ship-floor-not-mine` and abstain (`session-continue.sh:1150-1151`).
- **Rung 🚀.**
  - It needs `session_writes_paths "$TP_MECH"` to return rc 0, meaning any edit-recorded write anywhere in the session (`:1153-1155`).
  - This check is not scoped to the repo or to the unlanded commits. rc 1 and rc 2 both abstain.

**(d) Exemptions.**
- `CC_SHIP_FLOOR=0` (or any value other than `1`).
- Kill-switch, assignee, and teardown marker.
- Rung other than 📦 or 🚀, or a missing ledger, library or trunk (silent).
- Not present: headless and live-`/goal` checks. I found none in `:1098-1199`.

## 4. Wake, mail and custody floor

**(a) Trigger.** `wake_floor` (`:603-895`) runs only after the mechanical arm and ship floor both declined. The steps, in order:

1. **Preconditions** (`:604-607`).
   - `CC_WAKE_FLOOR` is exactly `1`.
   - `jq` is present.
   - `mailbox_wake_armed` is defined, meaning the mailbox lib sourced.
   - `$_ouid` is a safe filename component.
2. **Already armed** (`:614`).
   - If `mailbox_wake_armed "$_ouid"` is true, it deletes `$sf` and returns. That resets the budget.
   - `mailbox_wake_armed` (`hooks/lib/mailbox-pending.sh:291-301`) needs `<box>/<uuid>.watching` to exist. Its mtime must be within `CC_WATCH_FRESH_S` (default `90`, `:297`). A recorded pid must be alive.
3. **Headless abstain** (`:656-664`): `CC_PANE_ID` set and `ITERM_SESSION_ID` empty.
4. **Live goal** (`:692-704`).
   - `goal_live_condition` returns 0 when the last `goal_status` attachment in the transcript has `met` and `failed` both false (`hooks/lib/goal-state.sh:60-73`).
   - If a goal is live and mail is pending, it abstains.
   - If a goal is live and no mail is pending, it continues, and only the instructed command changes (`session-continue.sh:827-833`).
5. **Custody count** (`:731-766`), explained under (c).
6. **Teardown abstain** (`:776-798`), explained under (d).
7. **Fire eligibility** (`:805`): `cnt == 0` (first idle) **or** `pend > 0` **or** `cust > 0`.
8. **Budget** (`:836-843`): `cnt >= maxa` logs `wake-floor-budget`, emits a `systemMessage`, and does not block.
9. **TTL** (`:845-848`): `now - ts < ttl` logs `wake-floor-ttl` and does not block.
10. **Kill-switch** (`:850-854`): emits a `systemMessage`, logs `wake-floor-kill-switch`, and does not block.
11. **Fire** (`:856-894`): it writes the state file, then prints `{decision:"block",reason,systemMessage}`.

**(b) Bound.**
- File `${CC_MAILBOX_DIR:-$HOME/.claude/mailbox}/<_ouid>.wakefloor` (`:610-611`), with `sid=`, `count=` and `ts=` lines. It is keyed on the resolved mailbox key, with the sid inside.
- A different non-empty sid resets `cnt` and `ts` (`:627`).
- Env vars and literal defaults:
  - `CC_WAKE_FLOOR_MAX`: `2` (`:807`).
  - `CC_WAKE_FLOOR_TTL_S`: `600` (`:808`).
  - `CC_WAKE_FLOOR_TIMEOUT_S`: `14400` (`:821`). This only affects the command text.
  - `CC_WATCH_FRESH_S`: `90` (`hooks/lib/mailbox-pending.sh:297`).
  - `CC_WAKE_FLOOR_TEARDOWN`: `1` (`session-continue.sh:776`).
  - `CC_WF_TEARDOWN_FRESH_S`: `1800` (`:555`).
  - `CC_TEARDOWN_DIR`: `$HOME/.claude/watchdog/teardown` (`:553`).
  - `CC_WF_MAX_HOPS`: `8` (`hooks/lib/agent-identity.sh:46`).
- The budget is reset whenever a watcher is armed (`:614`). A compliant session that arms, then loses its watcher, then idles again gets a fresh budget. The hook's own comments describe this (`:478-483`).

**(c) Ownership.**
- **Mail.**
  - The box is the pane's mailbox, keyed by `CC_PANE_ID` or the tail of `ITERM_SESSION_ID`. That key is rewritten by `mailbox_resolve_key` to the session-keyed box when an alias exists (`:420`, `:453-466`).
  - `pend = mailbox_pending_count` (`:629`), which is `lines - seen` clamped at 0 (`hooks/lib/mailbox-pending.sh:245`).
- **Custody.** It uses `$_opane`, the raw pane key kept before canonicalisation (`:425`). `bin/cc-custody list --open --cwd "$cwd" --json` is filtered in `jq` (`:743-758`):
  - `cust_mine` counts rows with `originatorPane == pane`, `notifyBack == pane`, or `notifyBack` ending in `-<pane>`. Rows must carry at least one of those fields.
  - `cust_unk` counts rows that carry neither field. They still count toward `cust`, and the message hedges (`:756-758`, `:878-885`).
  - Otherwise, `count --open --cwd` is used and all rows are treated as unknown (`:759-765`).
  - `cust = cust_mine + cust_unk`, and `cust > 0` makes the floor eligible (`:805`).
- **Return codes.** There are no return codes here, only counts. Both `cust_mine` and `cust_unk` permit a block. `cust_unk`'s message says the rows may not be this session's.

**(d) Exemptions, abstains and kill switches.**
- **Kill switch:** `CC_WAKE_FLOOR=0`, or any value other than `1`.
- **Headless** (`:656-664`). This abstain also emits a `systemMessage` when mail is pending.
- **Live `/goal` with pending mail** (`:697-703`).
- **Teardown gate** (`:776-798`):
  - Assignee: `agent_assignee_argv` returns an id, and `agent_team_member_confirms` returns 0 (confirmed) or 2 (argv evidence only). rc 1 (refuted) does not abstain.
  - Fresh teardown marker: `wf_teardown_marked` (`:551-568`), described below.
  - Setting `CC_WAKE_FLOOR_TEARDOWN` to anything other than `1` turns off both of these for the wake floor only. The mechanical arm and ship floor have no such switch.
- **Assignee identity.** `agent_assignee_argv` (`hooks/lib/agent-identity.sh:33-77`) walks the process ancestry from `$$` for up to `CC_WF_MAX_HOPS` hops. It needs all three flags on one process (`--agent-id`, `--agent-name`, `--team-name`) with a self-consistent `name@team`. `agent_team_member_confirms` (`:93-124`) then checks the team config:
  - rc 0: a non-lead member of that name exists.
  - rc 1: the config exists and has no such member.
  - rc 2: no readable config, or a bad id shape.
  - If `agent-identity.sh` cannot be sourced, stubs make it "not an assignee" and rc 2 (`session-continue.sh:539-542`).
- **Teardown marker.** `wf_teardown_marked` (`:551-568`) looks in `$CC_TEARDOWN_DIR` for `<cur_sid>.json` or `<pane>.json`, fresher than 1800 s. A sid-keyed file counts on its filename. A pane-keyed file counts if its `"sid"` field is empty or equals `cur_sid`.

## 5. Direct answers

- **Order and gate.** Order is mechanical arm, then ship floor, then wake floor. Together they are reached only when no sentinel file exists at `$f` (`:1205`). If one exists, none of them run.
- **Block payloads.** At most one per invocation (see §0).
- **The arm that blocks without printing a block.** The mechanical arm (§2). It returns 0 after writing the sentinel and log line (`:1068-1078`), and the code falls out of the `if` at `:1223`. Through the shared armed path it inherits:
  - the kill-switch (`:1228`),
  - SID-BIND (`:1246`),
  - the `CLAUDE_CONTINUE_MAX` cap, default 8 (`:1255`),
  - the mail fold,
  - the `mark_blocked continue` marker,
  - the `fired/continue` IDL row.
  - It also carries its own `.mech` budget (`CC_MECH_MAX`, default 2), which the armed path does not know about.
  - `.count` is deleted at `:1206` before the mechanical arm runs, so each arm starts a fresh 8-turn chain.
- **Unread peer mail alone.** Yes, through the wake floor only, and the block does not deliver the mail.
  - It needs `pend > 0`, which bypasses the "first idle only" latch at `:805`.
  - It also needs no live watcher, no headless or teardown/assignee abstain, no live goal, `cnt < 2`, the TTL elapsed, and no kill phrase.
  - What it blocks with is an instruction to arm `cc-await-ping`. `wake_floor` never takes or reads the mail; it only counts it.
  - With a live watcher, or a goal plus mail, unread mail alone does not block.
- **What the mail fold does and does not do.** The fold is at `:1272-1324`, with the commit at `:1336-1340`.
  - **It does:**
    - It runs only on the armed path, after the cap check.
    - It claims the drain lock, peeks `(seen, EOF]` via `mailbox_window_end … 0` (`0` means to EOF, `mailbox-pending.sh:518-527`), and prepends the mail to the block reason.
    - It adds a `systemMessage`.
    - It commits `.seen` only after the block JSON is written (`session-continue.sh:1337-1338`).
    - It releases the claim.
  - **It does not:**
    - It does not create a block. It rides an already-decided one.
    - It does not run on the floors' paths.
    - It does not run when the cap fires. That `exit 0` at `:1267` precedes it.
    - It does not run if the drain claim is refused.
    - The lag-ack at `:467` is separate. It runs on every Stop and only promotes `acked` to `seen`.
- **Env var with two different literal defaults.** `CC_MECH_MAX`.
  - The `clear` verb writes `${CC_MECH_MAX:-3}` (`:261`).
  - The mechanical arm reads `${CC_MECH_MAX:-2}` (`:1053`).
  - The comment at `:1046-1051` says the default was lowered from 3 to 2, so `clear`'s literal is stale.
  - Mismatch effect: with no env var set the spent marker (3) is still ≥ 2, so it works. If the hook runs with a higher `CC_MECH_MAX` than the shell that ran `clear`, the marker is below the hook's max and the budget is not spent.

## 6. Stale or misleading comments I checked

- **`:963-966`** says wake_floor "also exempts argv-only and treats REFUTED rc 1 as non-exempt" as though this differed from the ship floor. The code at `:778-785` and `:1103-1109` behaves identically. Both exempt on rc 0 and rc 2 and not on rc 1. The comment is wrong.
- **`:944-947`, `:967-975`** cite `ship_floor :969`, `wake_floor :732-736` and `:974`. The actual lines are `:1101`, `:849-854` and `:1106`. Stale.
- **`:1204`** says at most one floor emits per Stop. That is true of blocks (§0) and is what I verified.
- **`:427-443`** cite `mailbox-drain.sh` and floor line numbers (`:416`, `:224`). I did not verify these.
- **`hooks/lib/session-writes.sh:407-408`, `:420-421`** say session-continue.sh sets `-o pipefail`. `hooks/session-continue.sh` sets no shell options; the only hit for "set -o" is a comment at `:364`. The claim is false for this file.
- **`hooks/session-continue.sh:315-316`** cites `hooks/hook-chain.sh:78` for "every member always runs". The text is at `hooks/hook-chain.sh:77-78` (item 3), so it is accurate to within a line.
- **`settings-templates/settings.example.json:447`** describes the Stop chain as ordered and lists `session-continue.sh` at `:466`. I did not read the surrounding entries, so the "position 4 of the Stop chain" claim (`:323-325`) is unverified.
- **`CLAUDE.global.md:605` and `:1025`** say `CLAUDE_CONTINUE_MAX` "bounds only the MECHANICAL arm". The cap code at `:1255-1268` applies to any armed sentinel. What differs is that an agent's `set` zeroes `.count` (`:142`). I read those docs only via grep hits.
