<!-- arm B = claude-opus-5-5 @high · brief T4-stop-arms · settle re-run (wf_a8c18432-bb3), clean cwd · raw worker output, verbatim -->

# `hooks/session-continue.sh`: every path that blocks a Stop (snapshot 47c3317eb)

## 0. Entry, ordering, and how many blocks one Stop can print

**Actuation mode.** Actuation runs only when `$1` is not `--why`, `set`, `clear` or `status` (session-continue.sh:105, :139-303). In actuation mode the hook works through these steps in order:

1. It reads stdin and takes `cwd` from `.cwd`, falling back to `$PWD` (:307-310). It takes `cur_sid` from `.session_id`, falling back to `CLAUDE_CODE_SESSION_ID` (:312-313).
2. It computes the sentinel path `f`. The path is `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/state/continue-<first 16 hex of shasum("configdir|cwd")>` (lib/continue-sentinel.sh:17-27). The sentinel is keyed on config dir + cwd, not on the session.
3. It deletes last Stop's double-block marker `${f}.blocked` (:331-332). `mark_blocked` rewrites that marker later (:333-336), and completion-assert reads it to stand down (completion-assert.sh:866-869).
4. It runs `mailbox_promote_acked`, which moves `.acked` up to `.seen` (:467). This runs on every Stop and never blocks.
5. It sources `goal-state.sh` (:412-419) and `agent-identity.sh` (:525-543). If `agent-identity.sh` is missing, a stub stands in whose answer is "not an assignee" (:539-542).

**The single condition that gates the floors.** The floors run only when `[ ! -f "$f" ]`, i.e. no continuation sentinel is armed for this config dir + cwd (:1205). If a sentinel exists, all three floors are skipped and control goes straight to the armed path.

**Order inside the floor block (:1205-1220):**
1. `rm -f ${f}.count ${f}.sid ${f}.cwd` (:1206).
2. `mechanical_arm` runs (:1207). rc 0 means it armed, and control falls through to the armed path at :1228.
3. Otherwise `ship_floor` runs inside `$(...)`. rc≠0 means it blocked: it prints the JSON and calls `exit 0` (:1208-1212).
4. Otherwise `wake_floor` runs inside `$(...)`. rc≠0 means it blocked (:1213-1217).
5. Otherwise, if the wake floor printed a non-blocking `{systemMessage}`, that is printed and the hook exits (:1218-1219).

**Order inside the armed path:**
1. Kill switch: clear and allow (:1228-1233).
2. Sid mismatch: clear and allow (:1245-1252).
3. Cap reached: clear, print a `{systemMessage}` and allow (:1255-1267).
4. Otherwise increment the count (:1269-1270), fold any mail (:1284-1299), and emit the block (:1329-1335).

**How many block payloads per Stop: at most one.** Each floor that blocks prints one JSON object and exits (:1210-1216). The armed path prints one object and exits (:1331-1344). The hook always exits 0 (:1211, :1344), so a block travels only as `decision:"block"` in the JSON. Stdout carries at most one JSON object per Stop, which is either a block or a non-blocking `systemMessage`.

---

## Arm 1: the agent-armed sentinel (the "continue" arm)

**(a) Trigger.** The sentinel file `$f` exists (armed by `set` at :140-155, or written by Arm 2), and all three of these hold:
- No kill phrase is found (:1228).
- The sid check passes: the stored `.sid` is empty, `cur_sid` is empty, or the two are equal (:1245-1246).
- `.count < MAX` (:1258).

It does not look at the working tree, the ledger rung or the mailbox before firing. Mail is only folded into the reason text.

**(b) Bound.**
- Counter: `${f}.count`. It is incremented and written at :1269-1270, and reset by `set` (:142) and by the floor-path `rm` (:1206).
- Cap: `CLAUDE_CONTINUE_MAX`, default **8** (:1255). This value is not sanitised. A non-numeric value makes `[ -ge ]` error, the test reads false, and the hook blocks with no cap.
- Reaching the cap removes the sentinel and all sidecars (:1260) and prints `{systemMessage}` (:1264).
- A fresh `set` zeroes the count (:142), so an agent that keeps re-arming is never capped.

**(c) Ownership.** Nothing is attributed through session-writes here. The only binding is the sid stamp `${f}.sid`, written at :145-146 or :1071. A mismatch clears the sentinel and allows the stop (:1246-1251). If either side is empty, no check is made.

**(d) Suppressors.**
- Kill switch: `kill_switch_active` (:391-395) matches `KILL_RE` (:349) against the last user record that is not `isMeta` (:351-388). Machine-authored briefs still count as user records.
- Sid mismatch, and the cap.
- There is no assignee, teardown, headless or `/goal` exemption on this path.
- No env var disables the arm outright. The closest lever is `CLAUDE_CONTINUE_MAX=0`: the first check reads `0 ≥ 0` and clears.

---

## Arm 2: mechanical uncommitted-writes (`mechanical_arm`, :938-1079)

**(a) Trigger.** All of the following must hold, in this order:
- `jq` is present (:940) and no kill phrase is found (:950).
- The session is not an assignee (:967-975) and has no teardown marker (:983).
- The session-writes lib loads (:989-998) and `wrap-ledger.sh --machine` returns output, run in `cwd` (:1004-1014).
- The ledger reports `RUNG=🔧` (:1016-1017).
- `session_dirty_mine` returns rc 0 with non-empty output (:1022-1024), and the file count is > 0 (:1026-1028).

**(b) Bound.**
- File: `${f}.mech`, holding `"<sid> <count>"`. It is read at :1055-1061; the count resets when the stored sid ≠ `${cur_sid:-?}` (:1060).
- Budget: `CC_MECH_MAX`, default **2** at :1053. Not sanitised, so a non-numeric value makes the budget test fail open.
- Budget exhausted: rc 1, no block (:1062-1066). Otherwise the count is incremented (:1068).
- Seams: `SESSION_WRITES_LIB`, `WRAP_LEDGER_BIN`, and `SESSION_WRITES_TIMEOUT_S` (default 5, session-writes.sh:171).

**(c) Ownership: `session_dirty_mine`** (hooks/lib/session-writes.sh:277-361).
- It collects every `Write|Edit|MultiEdit|NotebookEdit` path from the transcript and its `subagents/*.jsonl` (`_sw_paths`, :135-193; `_sw_subagent_files`, :124-129).
- It canonicalises those paths (:212-217) and intersects them with `git status --porcelain -z -uall` under the toplevel (:318-358).
- Return codes:
  - **0**: at least one dirty path is one this session wrote. The relative paths are printed.
  - **1**: none of the dirty paths is mine, or the session wrote nothing.
  - **2**: can't tell (no git or jq, no transcript, rev-parse, mktemp or git-status failure or timeout).
- Only rc 0 permits the arm (:1023). rc 2 never blocks.

**(d) Suppressors.**
- Kill phrase (:950).
- Team assignee, when `agent_team_member_confirms` returns 0 (confirmed) or 2 (argv evidence only) (:969-974). rc 1 (refuted) does not suppress. See agent-identity.sh:33-62 and :93-123.
- A fresh teardown marker (`wf_teardown_marked`, :551-567).
- No headless or `/goal` exemption.
- **Kill switch: `CC_MECH_CONTINUE=0`** (:939).

---

## Arm 3: the ship floor (`ship_floor`, :1098-1199)

**(a) Trigger.**
- `jq` is present, no kill phrase, not an assignee, no teardown marker (:1100-1110).
- A ledger is available: it reuses `SC_LED_CACHE` from Arm 2 (:1115) or recomputes it (:1116-1125).
- `RUNG` is **📦 or 🚀** (:1128).
- For 📦, the ledger's `TRUNK=` is non-empty and not `none` (:1148-1149).
- The session-writes attribution passes (:1146-1156).
- The current `HEAD` sha differs from the latched sha (:1172).

**(b) Bound.**
- File: `${f}.ship`, holding `"<sid> <head_sha> <count>"`. The count and sha reset when the stored sid ≠ `${cur_sid:-?}` (:1162-1171).
- It fires once per HEAD sha (:1172), up to `CC_SHIP_FLOOR_MAX`, default **2** (sanitised to 2, :1162). Budget spent means no block (:1174-1178).
- The file is written at :1179.

**(c) Ownership.**
- **📦** uses `session_unlanded_mine` (session-writes.sh:375-433). It intersects `git diff --name-only $trunk..HEAD` with the session's write set.
  - rc 0: a mine path is in the unlanded diff.
  - rc 1: none is.
  - rc 2: can't tell.
  - The caller uses `||`, so rc 1 and rc 2 both abstain (:1150-1151). Only rc 0 blocks.
- **🚀** uses only `session_writes_paths` (session-writes.sh:200). rc 0 means the transcript has any write at all; rc 1 means none; rc 2 means unreadable.
  - Only rc 0 blocks (:1154-1155).
  - This is not scoped to the repo or to the landed diff. Any write anywhere in the session qualifies, which is a much weaker attribution than 📦 gets.

**(d) Suppressors.**
- Kill phrase (:1101).
- Assignee rc 0 or 2 (:1103-1109).
- Teardown marker (:1110).
- No headless or `/goal` exemption.
- **Kill switch: any value other than `CC_SHIP_FLOOR=1`** (:1099).

---

## Arm 4: the wake / mail / custody floor (`wake_floor`, :603-896)

**(a) Trigger.**
- `CC_WAKE_FLOOR=1`, `jq` present, `mailbox_wake_armed` defined, and a valid `_ouid` (:604-607).
  - `_ouid` is `CC_PANE_ID`, falling back to `ITERM_SESSION_ID` (:420), then canonicalised to the session key through `mailbox_resolve_key` (:453-464).
- **No live watcher.** `mailbox_wake_armed` checks that a `.watching` heartbeat is ≤ `CC_WATCH_FRESH_S` old (default **90**) and that its pid is alive (lib/mailbox-pending.sh:291-301). A live watcher also deletes the floor's state file (:614).
- It is not headless and not a goal-with-pending-mail case (see (d)).
- Firing condition: **`cnt == 0` OR `pend > 0` OR `cust > 0`** (:805).
  - `pend` = lines minus the seen cursor (mailbox-pending.sh:245; called at :629).
  - `cust` = open `cc-custody` rows for `cwd` (:737-766).
- Then: budget remaining (:836), TTL elapsed (:845), and no kill phrase (:850).

**(b) Bound.**
- File: `${CC_MAILBOX_DIR:-$HOME/.claude/mailbox}/<_ouid>.wakefloor`, holding `sid=`, `count=` and `ts=` (:610-611, :856). The count and ts reset when the stored sid ≠ `cur_sid` (:627).
- Settings:
  - `CC_WAKE_FLOOR_MAX`, default **2** (:807).
  - `CC_WAKE_FLOOR_TTL_S`, default **600** (:808).
  - `CC_WAKE_FLOOR_TIMEOUT_S`, default **14400**. It only shapes the suggested command (:821).
- Test seams: `CC_CUSTODY_BIN` (:737), `CC_WF_PSTABLE_FILE`, `CC_WF_START_PID`, `CC_WF_MAX_HOPS` (default **8**, agent-identity.sh:35-46), `CC_WF_TEAM_ROOTS` (:100), `CC_TEARDOWN_DIR` (:553), and `CC_WF_TEARDOWN_FRESH_S` (default **1800**, :555).

**(c) Ownership.** session-writes is not used. Custody is attributed inline with `jq` (:745-757):
- A row is **mine** when its `originatorPane` or `notifyBack` equals the raw pane `_opane` (:425), or `notifyBack` ends with `-<pane>`.
- A row with no originator field counts as **unknown**.
- `cust = mine + unknown` (:758). Unattributable rows, possibly a sibling's, can therefore keep the floor re-firing, and the message says so (:881-882).
- If `list --json` fails, every row from `count` is counted as unknown (:761-764).

**(d) Suppressors.**
- **Headless:** `CC_PANE_ID` set and `ITERM_SESSION_ID` empty. It abstains, and prints a `{systemMessage}` only if mail is pending (:656-664).
- **Live `/goal`:** `goal_live_condition` returns rc 0 when the last `goal_status` attachment has neither `met` nor `failed` (goal-state.sh:60-73).
  - It abstains only if **`pend > 0` as well** (:697-703).
  - With no mail pending, a live goal just swaps in the `--idle-scoped --sid` watcher command (:822-827), and the floor **still blocks**.
- **Assignee (confirm rc 0 or 2) or teardown marker:** abstain (:776-802). Setting `CC_WAKE_FLOOR_TEARDOWN=0` turns this exemption off, which makes blocking more likely, not less.
- **Kill phrase:** abstains with a `systemMessage` (:850-854). It is checked only after the budget and TTL checks.
- **Budget exhausted:** prints a warning `systemMessage` and allows the stop (:836-843).
- **Kill switch: any value other than `CC_WAKE_FLOOR=1`** (:604).

---

## Explicit answers to the brief's questions

**Which arm never prints a block of its own, yet still causes one?** The mechanical arm. It prints no JSON. It writes the sentinel reason, `.sid` and `.cwd` (:1070-1072), returns 0, and control falls into Arm 1's code (:1228 onward). Its block is therefore Arm 1's block, and it inherits all of Arm 1's bounds:
- The kill-phrase re-check (:1228).
- The sid-bind (:1245).
- `CLAUDE_CONTINUE_MAX` (8). `.count` was just removed (:1206), so the first block is 1/8.
- The mail fold.

On the Stops that follow, the sentinel persists. The armed path keeps blocking **without re-checking the dirt** until the cap, a `clear`, or a kill phrase. Only then does `CC_MECH_MAX` limit how often it can re-arm. Worst case at defaults is CC_MECH_MAX × CLAUDE_CONTINUE_MAX = 2 × 8 = 16 forced turns.

**Does unread peer mail by itself block a Stop?**
- It can, through **Arm 4 only**, and only when all of these hold: no live watcher; not headless; no live goal (a live goal plus pending mail abstains); not an assignee or tearing down; budget and TTL allow; no kill phrase (:805-856).
- The first unwatched idle blocks even with **zero** mail, because `cnt == 0` is enough (:805).
- A live watcher means mail never blocks.

The fold at the end of the file (:1284-1299, :1310-1340):
- **What it does:** only on the armed path, it claims the drain (`mailbox_drain_claim`). It peeks from the `seen` cursor to `mailbox_window_end`, or falls back to `mailbox_take "$_ouid" 0`. It prepends the bodies to the block reason and adds a `systemMessage`. Only after the JSON is emitted does it advance `seen` (`mailbox_commit_seen`, :1337-1338), and then it releases the claim.
- **What it does not do:** it never causes a block, never runs on the floor paths (the wake floor only reports a count), never acks (`.acked` moves only through the next Stop's `mailbox_promote_acked`, :467, lib :560), and delivers nothing if another live drain holds the claim.

**Which env var has different literal defaults on two code paths?** **`CC_MECH_MAX`**:
- `clear` spends the budget by writing `"$SID ${CC_MECH_MAX:-3}"` into `.mech` (:261).
- `mechanical_arm` reads it against `${CC_MECH_MAX:-2}` (:1053).

With both unset, 3 ≥ 2 and the budget is spent, as intended. The two paths run in different processes (the agent's Bash versus the harness hook), though. If the hook's environment sets `CC_MECH_MAX` to 4 or more while the Bash environment leaves it unset, a `clear` no longer spends the budget. There is a related hole: `clear` stamps the sid from `CLAUDE_CODE_SESSION_ID`, or `?` (:260). If that differs from the hook's stdin `session_id`, `mcnt` resets to 0 (:1060) and the `clear` spends nothing. A full grep of `hooks bin scripts` found no other copies of `CLAUDE_CONTINUE_MAX`, `CC_SHIP_FLOOR_MAX`, `CC_WAKE_FLOOR_MAX` or `CC_WATCH_FRESH_S` with a different default. The `CC_WATCH_FRESH_S:-90` default matches in mailbox-pending.sh:297, cc-notify:1297 and cc-await-ping:385.

---

## Stale in-file citations I checked (don't rely on them)

- **session-continue.sh:545-547** says the teardown-marker logic is taken "verbatim from hooks/lead-crash-watchdog.sh classify_death (:255-278)", with `marker_owns_sid` at ":112-118".
  - Actually, `classify_death` is at :402, the marker reader is `retired_by_desk` at :249-262, and `marker_owns_sid` is at :207-213.
  - It is also not verbatim. The watchdog requires `"mode":"teardown"` and uses `find -mmin -30` (:257-258). `wf_teardown_marked` checks no mode field (:551-567).
- **:432** "mailbox-drain.sh … (its :64-68" points at goal-state sourcing. "`mailbox_promote_acked` (:213)" is actually at mailbox-pending.sh:560 (:213 is `_mbx_write_int`). "The floor (:416) and mailbox-drain.sh (:224)": :416 is a shellcheck directive, and drain :224 is a `mailbox_take_n` call.
- **:455** "bin/cc-pane-headless:124/:197": :124 is the `--name)` argv case, and :197 is a bare `fi`.
- **:1327** "precedent at :502": :502 is a teardown comment.
- **:317** "hooks/hook-chain.sh:78": the "every member always runs" text is at :77 (off by one).

**Not verified:** I did not read how `wrap-ledger.sh` computes `RUNG`, `TRUNK`, `AHEAD` or `SHAS`. The rung conditions above are stated as the hook consumes them (:1016, :1127, :1148).