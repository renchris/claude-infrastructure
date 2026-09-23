<!-- arm C = claude-opus-5-5 @xhigh · brief T4-stop-arms · settle run 1 (wf_e43f474d-ad0), STRING-POSITIVE (spawned with the probe dir as cwd) — kept for the sensitivity scoring, raw worker output, verbatim -->

# How `hooks/session-continue.sh` blocks a Stop (snapshot 47c3317eb)

**Short answer.** There are four arms, but only three code paths print `{"decision":"block"}`: the sentinel continuation, the ship floor and the wake floor. The mechanical 🔧 arm never prints a block of its own. It writes the sentinel file and falls through into the continuation path, which prints the block. A Stop gets at most one JSON object from this hook. The three floors run only when no continue-sentinel exists for this config-dir and cwd. Every blocking path exits 0: the block travels in the JSON, never in the exit code (`hooks/session-continue.sh:36-37`, `:1211`, `:1216`, `:1344`).

## Before any arm runs

- **Actuation mode.** The hook actuates only when called with no `set`, `clear`, `status` or `--why` argument (`:105-117`, `:138-304`). Stdin is parsed for `.cwd` (falling back to `$PWD`), `.session_id` (falling back to `CLAUDE_CODE_SESSION_ID`) and `.transcript_path` (`:308-313`, `:930`).
- **Sentinel library.** If `lib/continue-sentinel.sh` cannot be sourced, the hook exits 0 and nothing can block (`:125-131`).
- **Sentinel path.** The file is `f = ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/state/continue-<first 16 hex of shasum("configdir|cwd")>` (`hooks/lib/continue-sentinel.sh:17-27`). Every sidecar (`.count`, `.sid`, `.cwd`, `.mech`, `.ship`, `.blocked`) is keyed on that same path, which means config-dir plus cwd, not the session.
- **Double-block marker.** `${f}.blocked` is deleted at the top of every Stop (`:331-332`). Each blocking path rewrites it (`mark_blocked`, `:333-336`), and `hooks/completion-assert.sh:866-867` reads it.
- **Unconditional mailbox lag-ack.** On every Stop the hook resolves the mailbox key and runs `mailbox_promote_acked` (`:420-469`). This needs the lib, jq and a valid `_ouid`. It is the only mailbox write that happens on every Stop.
- **jq is required for any block.** Every block payload is built by `jq -nc` (`:893`, `:1197`, `:1332-1334`).

## Evaluation order within one Stop

The single gate is `if [ ! -f "$f" ]` (`:1205`). The floors are reached only when no sentinel exists at Stop start. On that path the order is:

1. `rm .count .sid .cwd` (`:1206`)
2. `mechanical_arm` (`:1207`)
3. `ship_floor`, only if the mechanical arm returned 1 (`:1208`)
4. `wake_floor`, only if the ship floor returned 0 (`:1213`)

If the mechanical arm returns 0, control falls into the armed path. If a sentinel already existed, the floors are skipped entirely. The armed path runs: kill-switch (`:1228`) → SID-bind (`:1245`) → cap (`:1258`) → mail fold (`:1284-1299`) → block (`:1329-1335`).

---

## Arm 1: the agent-armed sentinel (the 🔧 continuation)

**(a) Trigger.** The file `f` exists for the Stop payload's cwd and the current `CLAUDE_CONFIG_DIR`. It is written by `set` (`:139-156`) or by the mechanical arm (`:1070`). The block fires if:
- no kill phrase is present (`:1228`);
- it is not the case that both the stored and current sids are non-empty and differ (`:1245-1246`);
- the count read before the increment is below the cap (`:1258`).

Nothing checks the tree, the ledger rung, identity, `/goal` or headless state. The block carries the frozen step text (`:1301-1304`).

**(b) Bound.**
- File: `${f}.count` (`:1256`, `:1270`), capped by `CLAUDE_CONTINUE_MAX`, default `8` (`:1255`).
- Counts 0–7 each produce a block, so there are 8 blocks per chain. At `n ≥ MAX` the hook deletes the sentinel, emits a `systemMessage` and allows the stop (`:1258-1267`).
- `set` resets `.count` (`:142`). A chain the agent keeps re-arming is therefore unbounded by this hook.
- The only related env var in the tree is the harness-level `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`. `bin/claude-latest:353-355` sets it to `50` when unset.

**(c) Ownership.** No library is involved; ownership is the inline SID-bind.
- `.sid` is written at arm time, and only when a sid exists (`:145-146`, `:1071`).
- Actuation clears and allows only when both sids are known and differ (`:1246-1251`).
- If there is no `.sid`, any session in the same cwd and config dir is blocked by the sentinel.

**(d) Suppressors.**
- The kill-switch: `KILL_RE` (`:348`) matched against the last user record with `isMeta != true`, string or text content (`:351-395`). A match clears the sentinel and allows the stop (`:1228-1233`).
- A SID mismatch.
- The cap.
- There is no assignee, teardown, headless or `/goal` exemption on this path.
- **There is no dedicated disable variable.** `CLAUDE_CONTINUE_MAX=0` has that effect: the first check `0 ≥ 0` takes the cap branch (`:1258`).

## Arm 2: the mechanical uncommitted-writes arm (never prints a block itself)

**(a) Trigger (`mechanical_arm`, `:938-1079`).** All of the following must hold:
- no sentinel exists;
- `CC_MECH_CONTINUE` is not `"0"` and jq is present (`:939-940`);
- no kill phrase (`:950`);
- not an assignee and not being torn down (below);
- `session-writes.sh` and `wrap-ledger.sh` resolve (`:985-1012`);
- `wrap-ledger.sh --machine`, run in the cwd, returns output with `RUNG=🔧` (`:1013-1017`);
- `session_dirty_mine` returns rc 0 with a non-empty path list (`:1022-1028`).

Two details matter here:
- `RUNG=🔧` needs no open blocking decision. `⛔` outranks `DIRTY=1` (`scripts/wrap-ledger.sh:1971-1980`). A session holding its own dirty files while an open class-C decision exists therefore gets no mechanical arm.
- `DIRTY` comes from `git status --porcelain` (`wrap-ledger.sh:527-529`).

When all of that holds, the arm writes `f` with a "Commit the N file(s)…" step, plus `.sid` and `.cwd`, and returns 0 (`:1070-1078`). The armed path then blocks.

**(b) Bound.**
- Its own budget is `${f}.mech`, containing `"<sid> <count>"` and keyed on config-dir plus cwd.
- `CC_MECH_MAX` defaults to `2` (`:1053`). A different sid resets the count (`:1060`). A spent budget is logged and allowed (`:1062-1067`). The count increments before arming (`:1068`).
- It inherits `.count` / `CLAUDE_CONTINUE_MAX` (default 8) from the armed path. `.count` is wiped at `:1206`, so each mechanical arm starts a fresh chain. The worst case is 2 × 8 = 16 blocks per session.
- Other tunables:
  - `SESSION_WRITES_TIMEOUT_S` (5) at `hooks/lib/session-writes.sh:171`
  - `WRAP_LEDGER_BIN` and `SESSION_WRITES_LIB` (`:986`, `:1006`)
  - `WRAP_TRANSCRIPT`, which the hook exports itself (`:937`)
  - `AGENT_IDENTITY_LIB`, `CC_WF_PSTABLE_FILE`, `CC_WF_START_PID` (default `$$`), `CC_WF_MAX_HOPS` (8) and `CC_WF_TEAM_ROOTS` (`agent-identity.sh:35-46`, `:103-108`)
  - `CC_TEARDOWN_DIR` (`$HOME/.claude/watchdog/teardown`) and `CC_WF_TEARDOWN_FRESH_S` (1800) (`:553-555`)

**(c) Ownership: `session_dirty_mine`** (`hooks/lib/session-writes.sh:277-361`).
- It intersects paths from `git -c core.quotePath=false status --porcelain -z -uall` (`:319`) with this session's Write/Edit/MultiEdit/NotebookEdit file paths.
- Those paths come from `_sw_paths`: the main transcript plus `<session>/subagents/**.jsonl` (`:124-129`, `:143-147`, `:171-185`).
- Both sides are canonicalised (`:212-218`, `:292-299`).
- Return codes:
  - **rc 0** = own dirty paths found, printed on stdout. This is the only code that permits a block (`session-continue.sh:1023`).
  - **rc 1** = nothing of mine is dirty, including a session that wrote nothing (`:283`, `:360`).
  - **rc 2** = cannot tell: no git or jq, no transcript, a jq failure, or a toplevel, mktemp or status failure (`:279`, `:282`, `:285-286`, `:318-321`).
- Files written only through Bash are invisible, because only those four tool names are selected (`:180`).

**(d) Suppressors.**
- The kill-switch, logged (`:950`).
- An assignee whose `agent_team_member_confirms` returns rc 0 or rc 2, logged (`:967-981`).
- A fresh teardown marker from `wf_teardown_marked` (`:551-568`, `:983`).
- Ledger rung other than 🔧.
- Attribution rc other than 0.
- Budget spent.
- There is no headless or `/goal` exemption.
- **Disable outright:** `CC_MECH_CONTINUE=0` (`:939`).

## Arm 3: the ship floor

**(a) Trigger (`ship_floor`, `:1098-1199`).** No sentinel, the mechanical arm returned 1, `CC_SHIP_FLOOR=1`, jq present, no kill phrase, not an assignee, no teardown marker, and the ledger (reusing `SC_LED_CACHE`, `:1115`) reads `RUNG` of 📦 or 🚀 (`:1128`).
- **📦** requires a clean tree, no DoD remainder, and commits ahead of trunk or cherry-absent (`wrap-ledger.sh:532-539`, `:1979-1984`).
- **🚀** requires everything to be ✅-eligible except that `LIVE_BREACH=1` (`wrap-ledger.sh:1878-1914`, `:2053-2056`).
- The ship floor ignores `LANDING=1`. The ledger still reports 📦 while a land is in flight and tells the session "do NOT fire a second /ship" (`wrap-ledger.sh:1985-1986`). The floor's block text says "/ship it" anyway (`:1185`).

**(b) Bound.**
- File: `${f}.ship`, containing `"<sid> <HEAD sha> <count>"`.
- It latches silently on the same sha (`:1172-1173`).
- `CC_SHIP_FLOOR_MAX` defaults to `2` (`:1162`). A different sid resets the count and the sha (`:1170`). When the budget is spent, the floor logs and allows (`:1174-1178`).
- It shares the ledger, session-writes, agent-identity and teardown tunables listed under Arm 2.

**(c) Ownership.**
- **📦:** `session_unlanded_mine` (`session-writes.sh:375-433`).
  - **rc 0** = some path in `git diff --name-only $trunk..HEAD` (`:415`) is one this session wrote. This is the only code that permits a block.
  - **rc 1** = not mine, including "wrote nothing".
  - **rc 2** = no trunk, no git, an unreadable transcript, or a toplevel or diff failure (`:377-383`, `:414-417`).
  - Plausible over-attribution: the two-dot `git diff A..B` compares trunk's tree against HEAD's, so files that changed only on trunk also appear in the list.
- **🚀:** `session_writes_paths` (`:200`) with rc 0 means any file-tool write by this session, in any repo.
- The caller discards the distinction between rc 1 and rc 2. Both log the same `ship-floor-not-mine` row (`session-continue.sh:1150-1155`).

**(d) Suppressors.**
- The kill-switch (`:1101`).
- An assignee with rc 0 or rc 2 (`:1102-1109`).
- A teardown marker (`:1110`).
- Rung, attribution, latch and budget.
- There is no headless or `/goal` exemption.
- **Disable outright:** `CC_SHIP_FLOOR`. Any value other than `1` disables it (`:1099`).

## Arm 4: the wake floor (mail plus custody)

**(a) Trigger (`wake_floor`, `:603-895`).** No sentinel, and neither earlier floor fired. Then:
- `CC_WAKE_FLOOR=1`, jq present, the mailbox lib loaded (`:604-606`).
- A valid `_ouid` (`:607`). This is `CC_PANE_ID`, else the suffix of `ITERM_SESSION_ID`, canonicalised by `mailbox_resolve_key` (`:420`, `:458-463`; `mailbox-pending.sh:903-911`).
- No live watcher (`:614`). "Live" means `.watching` is at most `CC_WATCH_FRESH_S` (90) seconds old and its pid is alive (`mailbox-pending.sh:291-300`).
- Not headless, where headless means `CC_PANE_ID` is set and `ITERM_SESSION_ID` is empty (`:656-664`).
- Not a live `/goal` with pending mail (`:692-704`).
- Not an assignee (rc 0 or 2) and not tearing down (`:776-798`).
- At least one of: this is the first attempt (`cnt==0`), `pend>0`, or `cust>0` (`:805`).
- The budget is not exhausted (`:836-843`), the TTL has elapsed (`:845-848`), and there is no kill phrase (`:850-854`).

It then writes its state and blocks, telling the model to arm `cc-await-ping` (`:856-894`). Under a live goal it names the `--idle-scoped --sid` form instead (`:827-833`).

**(b) Bound.**
- File: `${CC_MAILBOX_DIR:-$HOME/.claude/mailbox}/<_ouid>.wakefloor`, holding `sid=`, `count=` and `ts=` (`:610-611`, `:856`). A new sid resets the budget (`:627`).
- `CC_WAKE_FLOOR_MAX` = `2` (`:807`) and `CC_WAKE_FLOOR_TTL_S` = `600` (`:808`).
- `CC_WAKE_FLOOR_TIMEOUT_S` = `14400` appears only in the message text (`:821`).
- Also: `CC_WATCH_FRESH_S` = `90` and `CC_MBX_SESSION_KEY` = `1` (`mailbox-pending.sh:297`, `:906`), and `CC_CUSTODY_BIN` (`:737`).
- The budget is deleted whenever a watcher is found armed (`:614`). An agent that complies with the block therefore resets the cap it answers to.

**(c) Ownership.** This arm does not use session-writes. The inbox is identified by the pane or session key in `_ouid`.
- Custody rows count as "mine" when `originatorPane` equals the raw pane key `$_opane`, or when `notifyBack` equals it or ends with `-<pane>` (`:748-755`).
- Rows carrying neither field still count, as `cust_unk` (`:753`, `:758`).
- With no pane or no jq, the arm falls back to `cc-custody count --open --cwd` for the whole cwd (`:760-765`). As a result, a sibling's rows that cannot be attributed can fire this floor.

**(d) Suppressors.**
- Headless (`:656`).
- Goal-live plus pending mail (`:697`), using `goal_live_condition`: the last `goal_status` attachment with neither met nor failed (`goal-state.sh:60-73`).
- An assignee or teardown marker, gated by `CC_WAKE_FLOOR_TEARDOWN` (default `1`, `:776`).
- Budget, TTL and kill-switch. The kill-switch is checked last here, after budget and TTL (`:850`).
- **Disable outright:** `CC_WAKE_FLOOR`. Any value other than `1` disables it (`:604`).

---

## Explicit answers

**Order and entry condition.** The mechanical arm, then the ship floor, then the wake floor, and only when `[ ! -f "$f" ]` (`:1203-1219`). Otherwise the armed path runs directly.

**Payloads per invocation.** At most one JSON object, and so at most one block. Every branch prints one object and exits (`:1210-1219`, `:1264-1267`, `:1332-1334`). Each abstain in `wake_floor` prints at most one `systemMessage`, which is re-emitted at `:1218`.

**The arm that never prints its own block.** The mechanical arm (`:1070`, `:1221-1222`). It inherits:
- the kill-switch;
- the SID-bind (it writes `.sid = cur_sid`, `:1071`);
- the `CLAUDE_CONTINUE_MAX` cap on `.count`;
- the mail fold.

Its own `.mech` budget sits on top, which gives the 16-block product. The sentinel it writes keeps blocking after the tree goes clean, because the armed path never re-checks dirtiness (`:1225-1344`). It stops only on `clear`, a kill phrase or the cap. The "self-clearing" claim at `:922-923` holds for the arm function only, not for the sentinel it leaves behind.

**Does unread mail alone block?** Only through the wake floor. `pend>0` satisfies `:805` even after the first attempt, but only when no watcher is armed and every wake-floor gate passes. That block delivers no mail: it names the count and asks the model to arm a watcher (`:872-874`).

The fold at the end (`:1284-1340`) runs only inside the sentinel block path. It:
- claims the drain lock;
- reads from `.seen` to EOF without consuming (`mailbox_window_end … 0`, `mailbox_peek_range`);
- prepends the mail to the reason and adds a `systemMessage`;
- commits `.seen` only after jq has emitted the block, then releases the claim.

It does not create a block, does not run on no-sentinel stops, and does not advance `.acked`, which is left to the next Stop's `mailbox_promote_acked` (`:467`; `mailbox-pending.sh:560-568`). It also delivers nothing if another drain holds the claim. Older libs fall back to `mailbox_take`, which advances `.seen` before the block is written (`:1296-1297`).

**An env var with two different defaults.** `CC_MECH_MAX`:
- The `clear` CLI writes `"<sid> ${CC_MECH_MAX:-3}"` into `.mech` (`:261`).
- `mechanical_arm` reads the cap as `${CC_MECH_MAX:-2}` (`:1053`).
- With both unset, 3 ≥ 2, so `clear` spends the budget, but only by accident. If the hook's environment sets the value above 3, a `clear` becomes a snooze.
- Separately, a bare-shell `clear` stamps sid `?` (`:260`), which fails the same-session check at `:1060`, so the budget resets anyway.

No other tunable in the tree has two defaults. The disable-switch semantics do differ: `CC_MECH_CONTINUE` disables only on the literal `0` (`:939`), while the other floors require the literal `1` to stay on (`:604`, `:776`, `:1099`).

**Other ownership gaps.**
- `.mech` and `.ship` are keyed on config-dir plus cwd and store one sid. Two sessions stopping alternately in a shared checkout reset each other's budgets (`:1057-1060`, `:1166-1170`).
- The hook calls `agent_assignee_argv` and `agent_team_member_confirms` directly, which skips `agent_is_assignee`'s `*@session-*` shape check (`agent-identity.sh:143-147`). A self-consistent argv id not in `@session-` form gets rc 2 (`:95`) and is exempted.

## Stale in-file citations (checked against the code)

**`hooks/session-continue.sh`:**
- `:433` cites `mailbox_promote_acked (:213)`; the call is at `:467`.
- `:442` cites "the floor (:416)"; the wake floor is at `:603`.
- `:724` says `$_opane` is "captured at :197"; it is captured at `:425`.
- `:944` cites `ship_floor :969` and `wake_floor :732-736`; the kill-switches are at `:1101` and `:850`.
- `:952` cites `:865-869` and `:587-608`; the exemptions are at `:1102-1109` and `:776-798`.
- `:965` (`:589-594`) and `:974` are stale. The claim that the wake floor treats rc 1 differently is also wrong: all three arms exempt on rc 0 or 2 and not on rc 1 (`:780-784`, `:970`, `:1105`).
- `:1326` cites "precedent at :502"; that line is a comment.

**`hooks/lib/session-writes.sh`:**
- `:422` says `session-continue.sh` sets pipefail. It sets no shell options (`session-continue.sh:364-366`; the grep found no `set` line).
- `:423` cites "the sibling at :269"; the sibling is at `:354`, and it already uses a herestring.

**Checked and correct:**
- `:323`, "position 4 / position 6": `settings-templates/settings.example.json` Stop group 0 lists `session-continue.sh` 4th and `completion-assert.sh` 6th. The live `settings.json` is not in the repo.
- `:317` cites `hooks/hook-chain.sh:78`; the text is at `:77-78`.