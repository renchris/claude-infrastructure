# When `hooks/session-continue.sh` blocks a Stop

Read at sha 47c3317eb under `/tmp/s55/repo-47c3317eb`. The brief names `/tmp/o55probe-repo-47c3317eb`, but I read only the path I was given. Every claim below comes from code lines I read. Comment claims that turned out wrong are flagged in the last section.

## 0. Shape of the hook

- **Entry.** The Stop harness runs the hook with no args and JSON on stdin. The hook reads only three stdin fields: `cwd` (`hooks/session-continue.sh:309`), `session_id` (`:312`) and `transcript_path` (`:353`, `:695`, `:930`). It never reads `stop_hook_active`, so loop-prevention is only its own counters.
- **CLI modes never block a Stop.** `set` (`:139-156`), `clear` (`:157-291`), `status` (`:292-303`) and `--why` (`:105-117`) are agent-run verbs. The only `exit 2` sites are `:116`, `:130` (only for `set|clear|status`) and `:216`. Every actuation path ends `exit 0` (`:1211`, `:1216`, `:1219`, `:1232`, `:1251`, `:1267`, `:1344`).
- **What counts as blocking.** Only a printed `{decision:"block",…}` JSON blocks. Those are emitted at `:892-893` (wake floor), `:1197` (ship floor) and `:1332`/`:1334` (armed path). The hook never blocks by exit code.
- **Chain position.** The Stop chain in the template puts `session-continue.sh` fourth (`settings-templates/settings.example.json:464-468`) and `completion-assert.sh` sixth (`:474-478`). Both entries carry `timeout: 5`. That is the template, not necessarily the live settings.

## 1. Order of evaluation, and how many blocks per Stop

Each Stop runs these steps in order:

1. **Unconditional prelude.** It deletes `${f}.blocked` (`:331-332`) and, if the mailbox lib and `jq` are present, runs `mailbox_promote_acked` on the box key (`:467`).
2. **Dispatch on the sentinel file.** Everything turns on `[ ! -f "$f" ]` at `:1205`.
   - **No sentinel file.** The session is treated as going idle. It removes orphan `.count`, `.sid` and `.cwd` sidecars (`:1206`) and runs the floors in order:
     1. `mechanical_arm` (`:1207`). Its rc 0 means "armed", and control falls to the armed path.
     2. `ship_floor` (`:1208-1212`).
     3. `wake_floor` (`:1213-1217`).
   - **Sentinel present.** The floors are never evaluated. The comment at `:1201-1202` says a sentinel-blocked stop is not idle. Control goes straight to the armed path.
3. **Armed path.**
   1. Kill-switch (`:1228`).
   2. SID-BIND (`:1245`).
   3. Cap (`:1255`).
   4. Mail fold (`:1284-1324`).
   5. Block (`:1329-1335`).

**Single condition to reach the floors:** the sentinel file for `continue_sentinel_for($cwd)` does not exist (`:1205`).

**Block payloads per invocation: at most one.** Each floor's block is followed by `exit 0` (`:1211`, `:1216`), and the armed path prints one `jq` object and exits at `:1344`. The floors only print non-blocking `{systemMessage}` JSON on their abstain paths. Each such path `return`s straight after printing, so a floor's captured stdout is never a mix of a note and a block (`:657-663`, `:698-702`, `:791-796`, `:837-842`, `:851`). Rc 0 from `wake_floor` prints its captured JSON at `:1218`. Rc 0 from `ship_floor` discards its stdout (`:1208-1212`).

**Sentinel path and key.** `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/state/continue-<first 16 hex of shasum("<config-dir>|<cwd>")>` (`hooks/lib/continue-sentinel.sh:17-19`, `:23-27`). `cwd` comes from stdin, falling back to `$PWD` (`:309-311`). All sidecars (`.count`, `.sid`, `.cwd`, `.mech`, `.ship`, `.blocked`) hang off this path, so they are keyed on config-dir plus cwd, not on the session.

## 2. Arm A — the agent-armed sentinel (armed path)

**(a) Trigger.**
- The file `$f` exists. The agent creates it with `session-continue.sh set` (`:139-156`), or the mechanical arm creates it (arm B).
- It is not cleared by the kill-switch (`:1228-1233`).
- It is not cleared by SID-BIND: `.sid` is non-empty, `cur_sid` is non-empty, and they differ (`:1245-1252`).
- The count is under the cap: `n < MAX` (`:1258`).
- Then it blocks with "🔧 Loose ends remain… Next: ${step}" (`:1301-1304`).

Nothing in this path re-checks the working tree, the ledger rung, mail or custody. It is a dumb actuator.

**(b) Counter, latch and budget.**
- **Storage.** `${f}.count`, incremented at `:1269-1270`.
- **Cap.** `MAX="${CLAUDE_CONTINUE_MAX:-8}"` (`:1255`). This is the only env var tuning this arm, and it is not numeric-validated. A non-numeric value makes `[ "$n" -ge "$MAX" ]` error, which reads as false, so the cap never fires.
- **Reset.** `set` deletes `.count` (`:142`), so a re-arming agent never reaches the cap.
- **At the cap.** It clears `f`, `.count`, `.sid` and `.cwd`, prints a `systemMessage` naming the re-arm lever, logs, and allows the stop (`:1258-1267`).

**(c) Ownership.** There is no library function. The check is inline SID-BIND: `.sid`, written by `set` only if `CLAUDE_CODE_SESSION_ID`/`CLAUDE_SESSION_ID` is set (`:145-146`), is compared with the stdin `session_id` (`:1245-1246`).
- A mismatch clears and allows.
- If either side is empty, no check runs and the block proceeds. The comment says "no evidence = never a wrong clear" (`:1243-1244`).
- An operator's bare-shell `set` therefore leaves a sentinel that any session in that cwd obeys.

**(d) Exemptions and kill switches.**
- **Operator phrasing.** `kill_switch_active` (`:391-395`) greps the last non-`isMeta` user record for `KILL_RE` (`:348`), case-insensitively. The phrases are "and [then] stop", "no auto-continue" (the space, `_` or `-` between words is optional), "just do <word>", "stop here", "come back to this", and a bare `stop` or `halt` line. With no readable `transcript_path` the switch is inactive (`:355`).
- **SID-BIND** (above) and **the cap** (above).
- **Not exempt, by code.** The armed path has no assignee, teardown, headless or live-`/goal` check anywhere in `:1225-1344`.
- **Env kill switch.** I found none for this arm. `CC_MECH_CONTINUE`, `CC_SHIP_FLOOR` and `CC_WAKE_FLOOR` do not touch it. `CLAUDE_CONTINUE_MAX=0` is a de facto off switch (an inference from `:1258`): the first Stop clears the sentinel and allows the stop.

## 3. Arm B — mechanical uncommitted-writes arm (`mechanical_arm`, `:938-1079`)

**(a) Trigger.** All of these must hold, in this order:
1. The sentinel is absent (`:1205`).
2. `CC_MECH_CONTINUE` is not the literal `0` (`:939`), and `jq` is present (`:940`).
3. `kill_switch_active` is false (`:950`). Otherwise it logs `cleared/mechanical-kill-switch`.
4. It is not an assignee: `agent_assignee_argv` yields an id and `agent_team_member_confirms` returns rc 0 or 2 (`:968-980`). It logs `mechanical-assignee`.
5. `wf_teardown_marked` is false (`:983`).
6. `lib/session-writes.sh` resolves and sources (`:985-998`).
7. The wrap-ledger script is found and `--machine` output is non-empty (`:1006-1014`). It runs as `cd "$cwd" && bash "$wrap" --machine` and is cached in `SC_LED_CACHE` (`:1015`).
8. `RUNG=` equals `🔧` (`:1016-1017`).
9. `session_dirty_mine "$TP_MECH" "$cwd"` returns rc 0 with non-empty output (`:1022-1024`), and the file count is above 0 (`:1026-1028`).
10. The mech budget is not spent (`:1062`).

Then it writes the budget, the sentinel text ("Commit the N file(s) you edited…"), `.sid` if `cur_sid` is non-empty, and `.cwd` (`:1068-1075`). It logs `armed/mechanical-dirty` and returns 0.

**On the rung.** The ladder puts ⛔ first (`scripts/wrap-ledger.sh:1972`), so pending blocking decisions mask this arm even with dirty own files. Dirty is `git status --porcelain` non-empty (`:527-529`) and yields 🔧 next (`:1979-1980`). Other 🔧 causes exist: DoD remainder (`:1981`), custody (`:1998-2010`), resident members (`:2017-2029`), no trunk (`:2042-2052`). The others sit under the `DIRTY=0` branches, so `session_dirty_mine` would find nothing to intersect. In practice the arm needs a dirty tree and no ⛔. That last sentence is my inference from the ladder.

**(b) Budget.**
- **Storage.** `${f}.mech` holds `"<sid> <count>"` (`:1053-1068`). It is keyed on the sentinel path (config-dir plus cwd) and stores the session id inside.
- **Cap.** `mmax="${CC_MECH_MAX:-2}"` (`:1053`). It is not numeric-validated.
- **Session change.** A different session id reads as count 0 (`:1060`).
- **Not reset.** The count is deliberately not cleared when the sentinel clears (`:1032-1045`).
- **Exhaustion.** It logs `mechanical-budget` and returns 1 (`:1062-1067`). The floors still run afterwards, so a spent mech budget does not by itself allow the stop.
- **`clear`.** The `clear` verb spends this budget by writing `"$SC_SID ${CC_MECH_MAX:-3}"` (`:261`). That default differs from the arm's (see §8).
- **Worst case.** With defaults, 2 mech arms times 8 continuations is 16 forced turns (`CLAUDE_CONTINUE_MAX` from `:1255`).

**(c) Ownership.** `session_dirty_mine` in `hooks/lib/session-writes.sh:277-361`.
- **Written paths.** It intersects the session's written paths with `git status --porcelain -z -uall` for the repo top-level of `cwd` (`:319`), with both sides canonicalised.
- **Written-path source.** The paths come from the transcript's Write, Edit, MultiEdit and NotebookEdit `tool_use` records (`:180`). The session's subagent transcripts are read too (`:145-147`). The read is bounded by `SESSION_WRITES_TIMEOUT_S`, default 5 (`:171`).
- **Return codes.**
  - rc 0: the intersection is non-empty. This is the only code that permits a block (`session-continue.sh:1023`).
  - rc 1: nothing of mine is dirty, or the session made no edit-recorded writes (`session-writes.sh:283`, `:360`).
  - rc 2: cannot tell. Causes are no git or `jq`, an unreadable transcript, a toplevel failure, `mktemp` failure, or a failed `git status` (`:279`, `:282`, `:285-286`, `:318-321`).
- **Blind spot.** Bash-only writes are invisible, and that degrades toward not blocking.

**(d) Exemptions.**
- Operator phrasing (`:950`).
- Assignee, rc 0 or 2 (`:968-980`).
- Teardown marker (`:983`).
- Any ledger, lib or transcript absence, and rc 1 or 2 from the oracle.
- **Not exempt:** headless and live `/goal`. The function body has neither check.
- **Off switch:** `CC_MECH_CONTINUE=0`. Only the literal `0` disables it (`:939`).

**Never prints a block of its own.** This is the answer to the "which arm never prints a block" question. `mechanical_arm` prints no JSON. After it returns 0, the `if ! mechanical_arm` at `:1207` is false, the floor branch is skipped, and control falls through `:1221-1223` into the armed path.
- The block is emitted at `:1332`/`:1334`, and `mark_blocked continue` is recorded (`:1329`).
- **Bounds inherited from arm A:** the kill-switch re-check (`:1228`), SID-BIND (`:1245`, which cannot mismatch on the arming Stop because `.sid` was just written from `cur_sid`, and which is skipped if `cur_sid` is empty, `:1071`), the `CLAUDE_CONTINUE_MAX` cap (`:1255`), the mail fold, and the IDL row.
- **`.count` starts at zero.** `:1206` deleted `.count`, so the first block is `n=1` and the cap cannot fire on it.
- **The sentinel persists.** Later Stops go directly to the armed path. The tree is not re-checked, so committing does not end the chain. Only the model's `clear`, the cap, the kill-switch or a sid mismatch does. The comment at `:920-923` ("SELF-CLEARING") is true of re-arming, not of a sentinel already armed.
- **A `set` converts the chain.** The block text tells the model to re-run `set` (`:1304`), and `set` zeroes `.count` (`:142`). A compliant model doing so turns a mechanical chain into an agent-armed one with no `CC_MECH_MAX` bound. That is my inference from the code.

## 4. Arm C — the ship floor (`ship_floor`, `:1098-1199`)

**(a) Trigger.** All must hold, in this order:
1. `CC_SHIP_FLOOR` equals `1` (`:1099`) and `jq` is present.
2. No kill phrase (`:1101`).
3. Not an assignee with rc 0 or 2 (`:1103-1109`).
4. No teardown marker (`:1110`).
5. A ledger is available (the cached `SC_LED_CACHE`, or a fresh run; `:1115-1126`).
6. `RUNG` is `📦` or `🚀` (`:1128`).
7. Attribution says the work is this session's (below).
8. The latch and budget allow it (below).

**Ledger fields used.** The hook reads only `RUNG`, `TRUNK`, `AHEAD` and `SHAS` (`:1127`, `:1148`, `:1181-1182`). Nothing here reads the ledger's in-flight-land state, so a 📦 that the ledger marks "Land IN FLIGHT" (`wrap-ledger.sh:1985-1986`) still qualifies as far as this hook is concerned.

**Rung meanings.** 📦 means unlanded commits with a clean tree and no ⛔ (`wrap-ledger.sh:1983-1984`). 🚀 means live-layer breach, ranked after the custody, resident and no-trunk arms (`:2053-2056`).

**(b) Latch and budget.**
- **Storage.** `${f}.ship` holds `"<sid> <head_sha> <count>"` (`:1162-1179`).
- **Cap.** `CC_SHIP_FLOOR_MAX`, default `2`, numeric-validated (`:1162`).
- **Latch.** The same sid and same HEAD sha latches silently, logging `ship-floor-latched` (`:1172-1173`). A new commit re-arms it.
- **Budget.** At `count >= max` it abstains and logs `ship-floor-budget` (`:1174-1178`).
- **Successor sessions.** A different sid resets the count and the sha (`:1170`).
- **Write timing.** The count is written before emission (`:1179`).
- **`clear` does not touch it.** `clear` removes `f`, `.count`, `.sid` and `.cwd` (`:253`) and rewrites `.mech`, but never `.ship`.

**(c) Ownership.**
- **📦.** `session_unlanded_mine "$TP_MECH" "$cwd" "$trunk"` (`session-writes.sh:375-433`). It intersects `git diff --name-only <trunk>..HEAD` with the canonicalised session-written paths (`:415`, `:428`). Return codes:
  - rc 0: the commits touch something this session wrote. Only this permits the block (`session-continue.sh:1150`).
  - rc 1: not mine, or no session writes (`session-writes.sh:381`, `:431-432`).
  - rc 2: cannot tell (`:377-378`, `:380`, `:383`, `:414-417`).
  - The hook's `|| {…}` treats rc 1 and rc 2 identically and logs both as `ship-floor-not-mine` (`:1150-1151`).
- **🚀.** `session_writes_paths "$TP_MECH"` must return rc 0, meaning any edit-recorded write this session, anywhere (`:1153-1155`). rc 1 and rc 2 both abstain with the same log label.
- **Extra 📦 guards.** It requires a trunk other than `none` (`:1148-1149`).

**(d) Exemptions.** Kill-switch, assignee (rc 0 or 2), teardown marker, and not-mine. Headless and live `/goal` are not checked. **Off switch:** `CC_SHIP_FLOOR` set to anything other than `1` (`:1099`).

## 5. Arm D — the wake / mail / custody floor (`wake_floor`, `:603-895`)

**(a) Trigger.** All must hold:
1. `CC_WAKE_FLOOR` equals `1` (`:604`), `jq` is present, and `mailbox_wake_armed` is defined, meaning the mailbox lib sourced (`:605-606`).
2. `_ouid` is a safe non-empty key (`:607`). It comes from `CC_PANE_ID`, else `ITERM_SESSION_ID` with the prefix stripped (`:420`). It is then rewritten to the session box key by `mailbox_resolve_key` when a valid one resolves (`:453-466`).
3. No live watcher: `mailbox_wake_armed "$_ouid"` is false (`:614`).
   - The watcher marker `<key>.watching` must be fresher than `CC_WATCH_FRESH_S` (default 90) and its pid must be alive (`hooks/lib/mailbox-pending.sh:291-301`).
   - Rc 0 means armed. It then deletes the budget file and returns without blocking (`session-continue.sh:614`).
4. Not the pane-less headless shape: `CC_PANE_ID` set and `ITERM_SESSION_ID` empty (`:656-664`). This abstain is logged, and it prints a `systemMessage` if mail is pending.
5. Not (live `/goal` and pending mail) (`:692-704`). A live goal with no mail continues to the floor, but the command it names becomes `cc-await-ping --idle-scoped --sid …` (`:827-833`).
   - `goal_live_condition` (`hooks/lib/goal-state.sh:60-73`) returns rc 0 iff the last `goal_status` attachment has `met` and `failed` both false. Every failure returns rc 1, which does not suppress anything.
6. Not (assignee or teardown-marked), while `CC_WAKE_FLOOR_TEARDOWN` equals `1` (`:776-798`).
7. The gate holds: `cnt == 0` (first idle) or `pend > 0` or `cust > 0` (`:805`).
8. Budget (`:836-843`), TTL (`:845-848`) and kill-switch (`:850-854`) all allow it. These are the three `return 0` steps just before the block is built.

**Mail and custody definitions.**
- `pend = mailbox_pending_count = lines − seen` (`mailbox-pending.sh:245`).
- **`cust`.** The floor shells out to `cc-custody`, searching in this order: `$CC_CUSTODY_BIN`, `<hook dir>/../bin/cc-custody`, `$CLAUDE_CONFIG_DIR/bin`, then `$HOME/.claude/bin` (`:737-741`).
  - With a pane id and a readable `list --open --cwd <cwd> --json` (`:743-744`), `cust_mine` counts rows whose `originatorPane` or `notifyBack` equals the pane, or whose `notifyBack` ends in `-<pane>`. `cust_unk` counts rows with neither field. `cust` is their sum (`:748-758`).
  - Otherwise `cust_unk = count --open --cwd` (`:762-764`).
  - `count --open` includes stale rows (`bin/cc-custody:256-257`).

**(b) Budget.**
- **Storage.** `$CC_MAILBOX_DIR:-$HOME/.claude/mailbox` plus `/<box-key>.wakefloor`, with lines `sid=`, `count=` and `ts=` (`:610-611`, `:856`). It is keyed on the canonicalised mailbox key.
- **Successor sessions.** A different sid resets count and ts (`:627`).
- **Env vars and defaults.**

| Env var | Default | Site |
|---|---|---|
| `CC_WAKE_FLOOR_MAX` | `2` | `:807` |
| `CC_WAKE_FLOOR_TTL_S` | `600` | `:808` |
| `CC_WAKE_FLOOR_TIMEOUT_S` | `14400` | `:821` |
| `CC_WATCH_FRESH_S` | `90` | `mailbox-pending.sh:297` |
| `CC_WF_TEARDOWN_FRESH_S` | `1800` | `:555` |
| `CC_TEARDOWN_DIR` | `$HOME/.claude/watchdog/teardown` | `:553` |
| `CC_WF_MAX_HOPS` | `8` | `agent-identity.sh:46` |
| `CC_MAILBOX_DIR` | `$HOME/.claude/mailbox` | `:610` |
| `CC_CUSTODY_BIN` | unset (no default) | `:737` |

- **Order quirk.** The budget check runs before the TTL check.
- **Exhaustion is loud.** It prints a `systemMessage` naming the arm command, logs `wake-floor-budget`, and allows the stop (`:836-843`).
- **The bound is defeated by compliance.** Arming clears the budget file (`:614`). The comment at `:478-483` says so, and the teardown abstain exists because of it.

**(c) Ownership.** No transcript oracle is used here. Ownership is by key:
- **Mail.** `mailbox_resolve_key` (`mailbox-pending.sh:903-915`) maps a pane to its box key. It returns the input unchanged with rc 1 if it is not a valid uuid, otherwise the pane itself (if a box exists with no alias) or its alias target. The hook ignores the rc and adopts only a valid-shaped result (`:463`).
- **Custody.** By the raw pane key `_opane` (`:425`, `:748-753`).
- **Assignee.** `agent_assignee_argv` (`agent-identity.sh:33-77`) walks the hook's process ancestry, at most `CC_WF_MAX_HOPS` hops, looking for `--agent-id`, `--agent-name` and `--team-name` with matching fields. `agent_team_member_confirms` (`:93-124`) returns 0 if confirmed, 1 if the team config refutes it, and 2 if unknown or no readable config.
- **Which returns permit a block.** For the assignee abstain, rc 1 (refuted) is the only non-exempting result. In this file, rc 0 and rc 2 both exempt at `:781-783`, `:970` and `:1105`.
- **Teardown marker.** `wf_teardown_marked` (`:551-568`) looks for a `<cur_sid>.json` or `<pane>.json` in `$CC_TEARDOWN_DIR`, with mtime within `CC_WF_TEARDOWN_FRESH_S`. A pane-keyed hit needs its `"sid"` empty or equal to `cur_sid`.

**(d) Exemptions.**
- Headless (`:656`).
- Live goal plus pending mail (`:697`).
- Assignee, rc 0 or 2, and teardown marker, both gated on `CC_WAKE_FLOOR_TEARDOWN` (`:776`).
- Budget, TTL and kill-switch.
- An armed watcher.
- **Off switch:** `CC_WAKE_FLOOR` set to anything other than `1` (`:604`).
- `CC_WAKE_FLOOR_TEARDOWN=0` only removes the assignee and teardown abstains. It is not an off switch.
- **Exemption scope.**
  - The teardown marker exempts all three of arms B, C and D. Arm D reads it only under `CC_WAKE_FLOOR_TEARDOWN` (`:776-788`). The other two call `wf_teardown_marked` unconditionally (`:983`, `:1110`).
  - The assignee exemption covers B, C and D but not the armed path.
  - Headless and live `/goal` apply to D only.

## 6. Does unread peer mail by itself block a Stop?

It can, but only through arm D, and only under all the conditions above. The block asks the model to arm a watcher. It does not deliver the mail: the reason text carries only a count line (`:872-874`).

- Mail widens the gate at `:805`, so a session that already declined once is still blocked while mail is pending. The count and TTL limits still apply.
- Mail does not block when a live watcher exists, the session is headless, an assignee or terminating, the budget is spent, the TTL has not elapsed, or a kill phrase is present.
- Mail does not block if a live goal is present, because that case abstains outright (`:697-703`).

**What the fold at the end of the file does:**
- It runs only on the armed path, after the kill-switch, SID-BIND and cap have not cleared the sentinel, and after the counter increment (`:1269-1270`, `:1284-1324`).
- It takes the box's unseen lines via `mailbox_drain_claim`, `mailbox_window_end` and `mailbox_peek_range`, or `mailbox_take` on an older lib (`:1288-1298`).
- It prepends them to the block reason and adds a `systemMessage` (`:1309-1323`).
- It commits `.seen` only after the JSON is written (`:1337-1339`).
- It releases the drain claim (`:1340`).

**What it does not do:**
- It creates no block of its own.
- It is never reached on the cap, kill-switch or sid-mismatch exits, or in any floor.
- It does not reset or skip the continuation counter (`:1269-1270` runs first).
- It does nothing if the drain claim is held elsewhere (`:1290`).

The lag-ack promote at `:467` is separate and runs on every Stop.

## 7. Exemption and kill-switch matrix

| | Kill phrase | Assignee | Teardown | Headless | Live `/goal` | Env off switch |
|---|---|---|---|---|---|---|
| A: agent-armed | clears sentinel (`:1228`) | no | no | no | no | none (cap at 0 is de facto) |
| B: mechanical | `:950` | rc 0 or 2 (`:968-980`) | `:983` | no | no | `CC_MECH_CONTINUE=0` |
| C: ship floor | `:1101` | rc 0 or 2 (`:1103-1109`) | `:1110` | no | no | `CC_SHIP_FLOOR≠1` |
| D: wake floor | `:850` (after budget and TTL) | rc 0 or 2 (`:778-785`) | `:786` | `:656` | pending mail only (`:697`) | `CC_WAKE_FLOOR≠1` |

## 8. Env var with two different literal defaults

`CC_MECH_MAX`:
- **`:-3`** in the `clear` verb (`hooks/session-continue.sh:261`).
- **`:-2`** in the mechanical arm (`:1053`).

Unset, both spend the budget, since 3 is at least 2. If the arm's process sees a larger value than the process that ran `clear`, `clear` stamps less than the max and does not spend it. The comment at `:1046-1051` records the default dropping from 3 to 2, and the `clear` site was not updated.

`CC_WATCH_FRESH_S` is the same everywhere I found it: `90` in `mailbox-pending.sh:297`, `bin/cc-notify:1297` and `bin/cc-await-ping:385`. My grep excluded tests and docs, and I did not search every file type, so I cannot rule out other divergent defaults.

## 9. Stale or wrong pointers I checked

**In `hooks/session-continue.sh` comments:**
- `:944` cites "ship_floor `:969`, wake_floor `:732-736`". The real kill-switch sites are `:1101` and `:849-854`.
- `:955-956` cites "ship_floor at `:865-869`, wake_floor at `:587-608`". The real sites are `:1103-1109` and `:776-798`.
- `:963-966` says the wake floor "also exempts argv-only" and treats a refuted rc 1 as non-exempt, and that mech differs. In code both exempt rc 0 and rc 2 and leave rc 1 non-exempt (`:781-783` versus `:970`, `:1105`). There is no difference.
- `:974` cites the sibling logging at `:974`. It is at `:1106`.
- `:424` cites the pane capture at `:197`. It is at `:420-425`.
- `:432` cites `mailbox_promote_acked (:213)`. It is at `:467`.
- `:441` cites the floor advertising no id at `:416`. It is at `:821`.
- `:1327` cites "precedent at `:502`", which is unrelated comment text in this file.
- `:1096` says budget exhaustion is silent. The code prints to stderr and logs `ship-floor-budget` (`:1175-1176`).

**In `session-writes.sh`:**
- `:424` says the sibling at ":269" still has the `printf | grep` shape. `session_dirty_mine` now uses a herestring at `:354`, and `:269` is comment text.

**In `CLAUDE.global.md`:**
- `:605` and `:1025-1026` say `CLAUDE_CONTINUE_MAX` "bounds only the MECHANICAL arm". The cap at `session-continue.sh:1255-1268` applies to every armed-path Stop regardless of who armed it. What differs is that `set` zeroes `.count` (`:142`).

**Verified correct:** `session-continue.sh:145` (the `.sid` write), the `:3-8` header, and the `:1203` floor-order comment, which matches `:1207-1217`.

**Not checked:** citations into `lead-crash-watchdog.sh`, `hooks/session-register.sh`, `bin/cc-pane-headless`, `completion-assert.sh:398`, `commands/ship.md:42` and `wrap-ledger.sh:140`.
