<!-- arm C = claude-opus-5-5 @xhigh · brief T4-stop-arms · raw worker output, verbatim -->

# How `hooks/session-continue.sh` blocks a Stop: every arm, gate and bound (snapshot 47c3317eb)

**Answers to the five explicit questions:**
- **Evaluation order.** The floors run only when no sentinel file exists for this config dir and payload cwd (`hooks/session-continue.sh:1205`). They run in a fixed order, and the first to arm or block wins: mechanical 🔧 → ship floor → wake floor. If the sentinel exists, or the mechanical arm just wrote it, the armed path runs instead.
- **Block payloads per invocation:** at most one. No two JSON objects are ever printed together.
- **The arm that blocks without printing its own block:** the mechanical arm. It inherits the armed path's kill switch, SID-bind, `CLAUDE_CONTINUE_MAX` cap (default 8) and the mail fold. It adds its own `CC_MECH_MAX` budget on top.
- **Does unread mail block a Stop by itself?** No. Pending mail only widens when the wake floor may fire. The mail fold at the end of the file only attaches to a block the sentinel path was already going to send.
- **Different literal defaults:** `CC_MECH_MAX` defaults to 3 in the `clear` command (`:261`) and to 2 in the mechanical arm (`:1053`).

## 0. What must be true before any arm is reached

| Step | Code | Effect |
|---|---|---|
| Mode dispatch | `hooks/session-continue.sh:105-117` (`--why`), `:138-304` (`set` / `clear` / `status`) | Actuation mode means any other argument or none, with the Stop JSON on stdin (`:306-308`). |
| Sentinel-path library must load | `:118-131` | If `continue-sentinel.sh` fails to source, the hook logs `no-sentinel-lib` and exits 0 (`:129-130`). No arm can fire. |
| Payload parse | `:308-313` | `cwd` comes from `.cwd`, else `$PWD`. `f` is the sentinel path. `cur_sid` comes from `.session_id`, else `CLAUDE_CODE_SESSION_ID`. Only `.cwd`, `.session_id` and `.transcript_path` are ever read (`:309, :312, :353, :695, :930`). **`stop_hook_active` is never consulted.** All loop bounds are the hook's own files. |
| Sentinel path | `hooks/lib/continue-sentinel.sh:17-27` | `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/state/continue-<first 16 chars of shasum("<cfgdir>\|<cwd>")>`. Keyed on (config dir, cwd), never on the session. |
| Double-block marker cleared | `:331-336` | `${f}.blocked` is deleted on every Stop. `mark_blocked` rewrites it only on a block (`:1209, :1214, :1329`). |
| Mailbox lag-ack (runs every Stop) | `:467` → `hooks/lib/mailbox-pending.sh:560-567` | Sets acked = seen. It advances no delivery and prints nothing. |
| Libraries loaded | goal-state `:412-419`; agent-identity `:525-542` | If agent-identity fails to load, stubs are defined: `agent_assignee_argv` returns 1 and `agent_team_member_confirms` returns 2 (`:539-542`). The fail direction is "not an assignee". |

Every actuation path exits 0. The block travels as `{"decision":"block"}` on stdout (`:1211`). The only `exit 2`s are in CLI or `--why` modes (`:116, :130, :216`).

## 1. Evaluation order and the single gating condition

```
if [ ! -f "$f" ]; then                  # :1205  — NO sentinel for (cfgdir|payload-cwd)
  rm -f .count .sid .cwd                # :1206
  mechanical_arm → rc0 ⇒ fall through to armed path            # :1207
  else ship_floor  → rc1 ⇒ print its block, exit             # :1208-1212
  else wake_floor  → rc1 ⇒ print its block, exit             # :1213-1217
  else print wake_floor's systemMessage (if any), exit 0      # :1218-1219
fi
armed path: kill-switch → SID-bind → cap → count++ → mail fold → block   # :1228-1344
```

- **The one condition:** the three floors are reached only when `${f}` does not exist (`:1205`). A session with an armed sentinel never reaches a floor on that Stop, even with pending mail or unlanded work.
- The armed path is reached when `${f}` exists, or when `mechanical_arm` returned 0 after writing it (`:1221-1222`).
- The floors short-circuit. A ship-floor block pre-empts the wake floor on the same Stop (`:1208-1211`).

## 2. The arms

### A. Agent-armed sentinel (the armed path, `:1225-1344`)

**(a) Trigger.** Both of these must hold:
- `${f}` exists. It is written by `set` using the shell's `$PWD` (`:140-141`), or by the mechanical arm (`:1070`).
- Actuation keys on the payload's `.cwd` (`:309-311`), not the shell's `$PWD`. So a `set` run from a different directory arms a sentinel that the Stop never sees.

Then, in order:
1. The kill switch is not active (`:1228`).
2. There is no SID mismatch (`:1245-1246`).
3. `.count` is below `MAX` (`:1255-1258`).
4. After that, `.count` is incremented (`:1269-1270`) and the block is emitted (`:1329-1335`).

The block is emitted only if `jq` runs. Without `jq`, `.count` still increments but nothing is printed, so nothing blocks (`:1332`/`:1334` are `jq … && _emitted=1`).

**(b) Bound.**
- Counter file: `${f}.count`, keyed like the sentinel on (config dir, cwd).
- `CLAUDE_CONTINUE_MAX` defaults to `8` (`:1255`). It has no digit guard, so a non-numeric value makes `[ "$n" -ge "$MAX" ]` error, which reads as false. The chain is then unbounded.
- `.count` is reset by `set` (`:142`), by every Stop with no sentinel (`:1206`), and by the cap, kill-switch and SID-mismatch exits (`:1260, :1229, :1247`). `clear` also resets it (`:253`).
- So an agent that re-runs `set` each turn is never capped. The block text tells it to do exactly that (`:1304`).
- At the cap, the hook deletes the sentinel, emits a non-blocking `systemMessage`, and allows the stop (`:1258-1268`).

**(c) Ownership.**
- No library function answers ownership. The path is keyed only on (config dir, cwd) (`hooks/lib/continue-sentinel.sh:11-12, 23-27`).
- The only session binding is the `.sid` sidecar check at `:1245-1252`. It acts only when both the stored and current sid are non-empty and differ, and then it **clears and allows**.
- If either sid is empty, there is no check, and any session stopping in that cwd under that config dir is blocked by the sentinel.
- If two known sids differ, the Stopping session **deletes the other session's sentinel** (`:1247`). A sibling sharing the cwd silently ends your chain.

**(d) Exemptions.**
- Kill switch (`:1228-1233`), SID mismatch, the cap, and a missing `jq`.
- **No** assignee, teardown, headless or live-`/goal` exemption on this path.
- There is no dedicated disable variable. `CLAUDE_CONTINUE_MAX=0` has that effect: `n=0 ≥ 0` hits the cap on the first actuation.
- Kill-switch regex (`:348`): `…and [then] stop`, `no auto-continue`, `just do <x>`, `stop here`, `come back to this`, bare `stop`/`halt`. It is matched against the last user record that is not `isMeta` and carries text (`:380-387`). An unreadable transcript means "not active", so the block proceeds (`:355, :392`).

### B. Mechanical 🔧 arm (`mechanical_arm`, `:938-1079`)

**(a) Trigger.** No sentinel exists (`:1205`), and all of the following hold:
- `CC_MECH_CONTINUE` is not `"0"` (`:939`), and `jq` is available (`:940`).
- The kill switch is not active (`:950`).
- The session is not an assignee (`:967-981`) and has no teardown marker (`:983`).
- The session-writes library resolves and sources (`:985-998`).
- `wrap-ledger.sh` resolves (`:1006-1012`) and `--machine`, run in `cwd`, returns output (`:1013-1014`).
- **`RUNG=🔧`** (`:1016-1017`).
- `session_dirty_mine` returns rc 0 with at least one path (`:1022-1028`).
- The `.mech` budget is not spent (`:1062`).

Only then does it write the sentinel, `.sid` and `.cwd` (`:1070-1075`) and return 0.

The ledger ladder (`scripts/wrap-ledger.sh:1962-2117`) is: ⛔ if `BLOCKED>0` (`:1971-1973`) → 🔧 if `DIRTY` (`:1979`) → 🔧 if `REMAINDER>0` (`:1981`) → 📦 if `UNLANDED` (`:1983`) → otherwise the ✅-eligible branch. That branch has its own 🔧 sources: open custody, resident members, filed-undriven rows, unconvicted asks, the close floor, and no trunk (`:1997-2052`). Two consequences:
- A session holding an open class-C decision (⛔) never gets the mechanical arm, even over its own dirty files.
- Stale gate state no longer yields 🔧 (`:1941-1961`).

**(b) Bound.**
- Budget file: `${f}.mech`, containing `"<sid> <count>"` (`:1052-1068`), keyed on (config dir, cwd) with the sid inside.
- `CC_MECH_MAX` defaults to `2` (`:1053`), with no digit guard. A non-numeric value makes the `-ge` test false, so the budget never binds.
- The count resets to 0 when the stored sid differs from `cur_sid` (`:1060`). The file is never deleted by the sentinel-clear paths.
- The arm then inherits the armed path's bounds (see §3), so the worst case is `CC_MECH_MAX × CLAUDE_CONTINUE_MAX = 2 × 8 = 16` blocks.

Two consequences read directly from the code:
1. **Blocks continue after the commit.** Once armed, the sentinel persists. The armed path never re-checks the tree, so it keeps blocking with the "Commit the N file(s)…" step until `clear`, `set` or the cap.
2. **One compliant `clear` spends the budget for good.** The `clear` that the block tells the model to run writes `"<sid> ${CC_MECH_MAX:-3}"` (`:260-261`). With the default of 2 that means spent, so the mechanical arm cannot fire again for that sid in that cwd.

   A bare-shell `clear` with no session id writes `? 3`. That binds nothing for a real sid (`:1060`).

**(c) Ownership.** `hooks/lib/session-writes.sh` → `session_dirty_mine` (`:277-361`).
- rc 0: some tracked path is both dirty and written by this session. **This is the only rc that permits a block.**
- rc 1: nothing of mine is dirty.
- rc 2: cannot tell (no git, no transcript, git status failed or timed out, `:279-286, :318-321`).
- The caller refuses anything but 0 (`:1023`).
- Written paths come from `session_writes_paths`, which is session-scoped and includes subagent transcripts (`:124-129, :143-147`). It covers only the tools `Write|Edit|MultiEdit|NotebookEdit` (`:180`), so a file written only through Bash is never attributed.
- Both sides are canonicalised (`:212-218, :292-299`).
- The dirty set is `git status --porcelain -z -uall`, bounded to 5 s (`:319`), matched with a herestring `grep -qxF` (`:354`).

**(d) Exemptions and kill switch.**
- Disabled outright by `CC_MECH_CONTINUE=0`, literally `"0"` (`:939`).
- Kill switch, logged as `mechanical-kill-switch` (`:950`).
- Assignee: `agent_assignee_argv` non-empty **and** `agent_team_member_confirms` rc 0 or 2 (`:968-980`).
- Teardown marker (`:983`).
- No headless or `/goal` exemption.
- Test seams: `SESSION_WRITES_LIB` (`:986`), `WRAP_LEDGER_BIN` (`:1006`), `AGENT_IDENTITY_LIB` (`:525`).

### C. Ship floor (`ship_floor`, `:1098-1199`), with separate 📦 and 🚀 sub-arms

**(a) Trigger.** No sentinel exists, `mechanical_arm` returned 1 (`:1207-1208`), and:
- `CC_SHIP_FLOOR` is `1` (`:1099`), and `jq` is available (`:1100`).
- The kill switch is not active (`:1101`).
- The session is not an assignee (`:1102-1109`) and has no teardown marker (`:1110`).
- A ledger is available: the cached `SC_LED_CACHE` (`:1015, :1115`) or a fresh run (`:1116-1125`).
- `RUNG` is 📦 or 🚀 (`:1127-1128`).

The two sub-arms then differ:
- **📦**: `TRUNK` is not empty or `none` (`:1148-1149`), and `session_unlanded_mine` returns 0 (`:1150`).
- **🚀**: `session_writes_paths` returns 0 (`:1154`).

Both then need the HEAD latch to be clear (`:1172`) and the budget not spent (`:1174`) before the block is emitted (`:1184-1198`).

What the ledger requires for each rung:
- **📦** = no ⛔, clean tree, `REMAINDER=0`, `UNLANDED=1` (`scripts/wrap-ledger.sh:1971-1984`).
  - This includes `LANDING=1`, a land already in flight (`:1985-1986`). `ship_floor` never reads `LANDING`, so it tells the model to "/ship it NOW" while the ledger's own readout says "do NOT fire a second /ship."
- **🚀** = the ✅-eligible branch (`:1990`) with `CUSTODY_OPEN=0` (`:1998`), no resident, filed, unconvicted or close-floor 🔧, a non-empty `TRUNK`, and `LIVE_BREACH=1` (`:2017-2056`).
  - `LIVE_BREACH` comes from a failed migration, divergence, added files, or the budget arms (`:1878-1897`).

**(b) Bound.**
- Latch and budget file: `${f}.ship`, containing `"<sid> <HEAD sha> <count>"` (`:1160-1179`).
- `CC_SHIP_FLOOR_MAX` defaults to `2` and is digit-guarded (`:1162`).
- Same sid and same HEAD means latched: log only, no block (`:1172-1173`).
- A different sid resets the count and the latched sha (`:1170`).
- HEAD comes from `git rev-parse HEAD`, or `?` on failure (`:1161`).
- Net effect: at most one block per new HEAD, and at most 2 per session per (config dir, cwd).

**(c) Ownership.** `hooks/lib/session-writes.sh`:
- **📦** uses `session_unlanded_mine` (`:375-433`), which intersects `git diff --name-only TRUNK..HEAD` (tempfile, bounded, `:414-417`) with this session's canonicalised written paths.
  - rc 0 means mine, and **only rc 0 permits a block**.
  - rc 1 (not mine) and rc 2 (cannot tell) both abstain, and both are logged as `ship-floor-not-mine` (`:1150-1151`). The log does not distinguish them.
- **🚀** uses only `session_writes_paths` (`:200`). rc 0 means this session wrote any file, anywhere, including a `/tmp` scratch file. The check is not scoped to the repo.

**(d) Exemptions and kill switch.**
- Disabled outright when `CC_SHIP_FLOOR` is anything other than `1` (`:1099`). `CC_SHIP_FLOOR_MAX=0` has the same effect.
- Kill switch (`:1101`), assignee rc 0 or 2 (`:1105`), teardown (`:1110`), the HEAD latch, and budget exhaustion. Exhaustion goes to stderr and IDL only, with no systemMessage (`:1174-1178`).
- No headless or `/goal` exemption.

### D. Wake floor, including its mail and custody inputs (`wake_floor`, `:603-895`)

**(a) Trigger.** No sentinel exists, mechanical did not arm, and the ship floor returned 0 (`:1207-1213`). Then, in this order:

1. `CC_WAKE_FLOOR` is `1` (`:604`).
2. `jq` is available, and the mailbox library defines `mailbox_wake_armed` (`:605-606`).
3. There is a valid box key `_ouid`: `CC_PANE_ID`, else the suffix of `ITERM_SESSION_ID` (`:420`), canonicalised (`:458-465`). Otherwise the floor is silently skipped (`:607`).
4. No live watcher (`:614`). "Live" means `.watching` is at most `CC_WATCH_FRESH_S` (default 90) seconds old and its pid is alive (`hooks/lib/mailbox-pending.sh:291-301`).
5. Not headless: `CC_PANE_ID` set with `ITERM_SESSION_ID` empty means abstain (`:656-664`).
6. Not (a live `/goal` **and** pending mail > 0) (`:692-704`). A live goal with no pending mail still blocks, but instructs `cc-await-ping --idle-scoped --sid …` (`:827-833`).
7. Not an assignee (rc 0 or 2) or teardown-marked, when `CC_WAKE_FLOOR_TEARDOWN=1` (`:776-798`).
8. `cnt==0 || pend>0 || cust>0` (`:805`): the first idle, or mail pending, or custody open.
9. `cnt < CC_WAKE_FLOOR_MAX` (`:836`).
10. At least `CC_WAKE_FLOOR_TTL_S` since the last fire (`:845`).
11. No kill switch (`:850`).
12. Write state (`:856`), then emit the block (`:892-894`).

The floor does not look at the ledger rung at all. It can block a fully ✅ session on its first idle.

**(b) Bound.**
- State file: `${CC_MAILBOX_DIR:-$HOME/.claude/mailbox}/<key>.wakefloor`, containing `sid=` / `count=` / `ts=` (`:610-611, :856`).
- It is keyed on the canonical mailbox key, not on the config dir, unlike `.count`, `.mech` and `.ship`.
- `CC_WAKE_FLOOR_MAX` defaults to `2` and `CC_WAKE_FLOOR_TTL_S` to `600`, both digit-guarded (`:807-808`).
- The budget resets on a sid change (`:627`) and whenever a live watcher is seen (`:614`, `rm -f`).
- Budget exhaustion and the kill switch each emit a non-blocking `systemMessage` warning (`:836-843, :850-854`).
- `CC_WAKE_FLOOR_TIMEOUT_S` (default `14400`) only changes the command text the block suggests (`:821`).
- Teardown seams: `CC_TEARDOWN_DIR` (default `$HOME/.claude/watchdog/teardown`, `:553`) and `CC_WF_TEARDOWN_FRESH_S` (default `1800`, `:555`).

**(c) Ownership.** It does not use session-writes. Ownership is decided in three places:
- **Mailbox key.** `mailbox_resolve_key` (`hooks/lib/mailbox-pending.sh:903-913`) returns the key itself if a box exists with no alias; otherwise it returns the alias-trail tip (`mailbox_alias_of`, `:804-810`). rc 1 means only an invalid key. The hook adopts the result only if it is a safe filename (`:463`). `mailbox_pending_count` is lines − seen (`:245`).
- **Custody**, decided by an inline jq filter in `hooks/session-continue.sh:748-754`, not by a library function:
  - A row is "mine" if `originatorPane == raw pane` (`$_opane`, `:425`), or `notifyBack == pane`, or `notifyBack` ends with `-pane`.
  - Rows carrying neither field count as `cust_unk` and **still count toward firing** (`:753, :758`).
  - Rows naming another pane are excluded.
  - With no pane id, no `jq`, or an empty list, it falls back to `cc-custody count --open --cwd` and treats everything as unattributed (`:759-765`).
  - Stale rows still count (`bin/cc-custody:48-49`).
- **Budget sid** (`:627`).

**(d) Exemptions and kill switch.**
- Disabled outright when `CC_WAKE_FLOOR` is anything other than `1` (`:604`).
- `CC_WAKE_FLOOR_TEARDOWN` other than `1` turns off both the assignee and the teardown abstain for this floor only (`:776`).
- Headless (`:656`), goal plus pending mail (`:697`), no pane id (`:607`).
- Unlike the other arms, the kill switch is checked **last**, after the budget and TTL (`:850`).

## 3. The arm that causes a block without printing one

**The mechanical arm.** It only writes the sentinel files and returns 0 (`:1070-1078`). The block is printed by the armed path (`:1329-1335`). It therefore inherits:
- the re-checked kill switch (`:1228`);
- SID-bind (`:1245-1252`), which it passes trivially because it stamps `cur_sid` itself (`:1071`);
- the `CLAUDE_CONTINUE_MAX` cap (default 8, `:1255-1268`), starting a fresh chain because `.count` was removed at `:1206`;
- the `jq` requirement to emit, the mail fold, and the `continue` marker.

On top of those it adds its own `CC_MECH_MAX` budget. The resulting worst case is the product of the two, as stated in the comment at `:1046-1048`.

## 4. Block payloads per invocation: at most one

- `decision:"block"` is printed at exactly three sites: the ship floor (`:1197`), the wake floor (`:892-893`), and the armed path (`:1332` or `:1334`).
- Each is followed by `exit` or a `return` that leads straight to `exit`. None of them can be combined.
- The non-blocking `systemMessage` outputs are also mutually exclusive with a block, and with each other, in one invocation:
  - wake-floor abstains (`:659, :699, :792, :840, :851`), printed via `:1218`;
  - the cap message (`:1264`).
- No function called in the main shell (`mechanical_arm`, `mailbox_promote_acked`, the mail primitives) writes to stdout. I checked `hooks/lib/mailbox-pending.sh:507-567` and `hooks/lib/agent-identity.sh:117-118`.

## 5. Does unread peer mail block a Stop by itself? No.

- Mail matters only in the **wake floor**. `pend>0` lifts the "first idle only" gate (`:805`) and adds a 📬 prefix (`:872`). The block asks the model to **arm a watcher**; it does not deliver the mail (`:858-866`).
- A live watcher short-circuits before `pend` is even read (`:614`). Headless, goal-live plus mail, assignee and teardown all abstain (with at most a systemMessage). The budget, TTL and kill switch still bind.
- **The fold at the end of the file** (`:1284-1340`):
  - It runs only on the armed path, after the kill-switch, SID-bind and cap exits.
  - It takes a non-waiting drain claim (`mailbox_drain_claim` → `_mbx_lock … 0`, `hooks/lib/mailbox-pending.sh:507-510`).
  - It peeks the whole window with no size cap (`:1293`, max 0 → `mailbox_window_end` `:518-526`).
  - It prepends the mail and adds a `systemMessage` (`:1309-1323`).
  - It advances `.seen` **only after** the `jq` emit succeeds (`:1337-1339`), then releases the claim (`:1340`).
  - With an older library it falls back to `mailbox_take … 0`, which advances `.seen` before the emit (`:1296-1297`, `hooks/lib/mailbox-pending.sh:370-386`).
- **What the fold does not do:**
  - It never creates a block. It never runs on the floor path or on the kill-switch, SID-mismatch or cap exits.
  - It never advances `.acked`; that happens unconditionally at `:467`.
  - It delivers nothing while another drain holds the claim.
  - It does not bound the size of what it folds in.

## 6. An environment variable with two different literal defaults

- **`CC_MECH_MAX`**: `clear` writes `${CC_MECH_MAX:-3}` (`hooks/session-continue.sh:261`), while `mechanical_arm` reads `${CC_MECH_MAX:-2}` (`:1053`). The comment at `:1049` ("the old default of 3") shows the `clear` path was never updated.
- These are harmless when both processes share the same environment (3 ≥ 2 counts as spent). They diverge when `clear` runs without the variable and the hook runs with `CC_MECH_MAX ≥ 4`.

I also checked three candidates that turned out to agree:
- `CC_TEARDOWN_DIR`: `hooks/session-continue.sh:553` and `hooks/lead-crash-watchdog.sh:251` use the same default.
- `CC_MAILBOX_DIR`: `hooks/session-continue.sh:610` and `hooks/lib/mailbox-pending.sh:110` use the same default.
- Teardown freshness: 1800 s (`<=`) versus a hard-coded `find -mmin -30`, the same window.

## 7. Cross-session leakage when sessions share one checkout

All of the following are keyed on (config dir, cwd):
- `.count` is deleted by any session's unarmed Stop (`:1206`).
- A known foreign `.sid` makes the next Stopper delete the sentinel (`:1247`).
- `.mech` and `.ship` are overwritten with the last writer's sid. That resets a sibling's budget when it next stops (`:1060, :1170`).

Two points about the assignee check:
- All three floors call the raw `agent_assignee_argv` plus `agent_team_member_confirms` and exempt on rc 0 or 2 (`:779-784, :969-970, :1104-1105`). None of them uses `agent_is_assignee`, which adds a shape gate (`hooks/lib/agent-identity.sh:133-150`).
- An id not shaped `*@session-*` returns rc 2 (`:95`), which the floors treat as exempt. The awk requirement that id equal name@team (`:70-71`) is the remaining guard.

## 8. Stale line citations I checked and relied on

| Claim | Actual |
|---|---|
| `session-continue.sh:432` "mailbox_promote_acked (:213)" | `:467` |
| `:441` "The floor (:416)" | the no-argument arm is at `:821` |
| `:724` "`$_opane` … captured at :197" | `:425` |
| `:944` "ship_floor :969, wake_floor :732-736" | `:1101`, `:850-854` |
| `:952` "ship_floor at :865-869, wake_floor at :587-608" | `:1102-1109`, `:776-798` |
| `:963-965` wake floor "also exempts argv-only and treats a REFUTED rc 1 as non-exempt (:589-594)" | Wrong line **and** wrong substance: the wake floor exempts exactly rc 0 and rc 2, the same as the other two floors (`:780-784`) |
| `:974` "The sibling at :974" | points at itself; the sibling is `:1106` |
| `:545-547` "lead-crash-watchdog.sh classify_death (:255-278)", "marker_owns_sid (:112-118)", "taken verbatim" | `:111-118` is a comment block. The reader is `retired_by_desk` at `:249-263`. It requires `"mode":"teardown"` (`:258`) and keys on pid and sid. `wf_teardown_marked` has no mode check and keys on sid and pane (`:557-566`), so it is **not** verbatim |
| `:1327` "precedent at :502" | `:502` is a teardown comment |
| `mailbox-pending.sh:151` "session-continue.sh:328" (`stat -f %m`) | the idiom is at `:559` |
| `session-writes.sh:423-425` "sibling at :269 still has that shape" | `session_dirty_mine` now uses a herestring (`:354`) |
| `session-writes.sh:420-421` "session-continue.sh … sets pipefail" | False. The file sets no shell options (`:36-37`; `:364-365` says so itself) |
| `wrap-ledger.sh:25` "🔧 = dirty ∨ gate stale ∨ remainder" | Gate staleness no longer produces 🔧 (`:1941-1961`), and 🔧 has six more sources (`:2006-2052`) |
| `session-continue.sh:1082-1083` quotes the mechanical header saying "📦 must NOT fire" | That text is no longer in `:897-929` |

These citations check out: `:318` → `hook-chain.sh:77-78`, `:178` "(:145)", `:587` "(:33)", and `session-writes.sh:405-407` on the ship floor's use of rc 1.

## 9. Not verified from code

- The session id that the hook's ledger resolves. `session-continue` passes neither `--session` nor `WRAP_SESSION_ID`; it only exports `WRAP_TRANSCRIPT` (`:937`).
  - `wrap-ledger` keys on `WRAP_SESSION_ID` and `CLAUDE_SESSION_ID` (`scripts/wrap-ledger.sh:386`), and states that only completion-assert passes `--session` (`:268-270`).
  - If the hook environment lacks `CLAUDE_SESSION_ID`, then ⛔, filed-row and unconvicted 🔧 all read as "none". In that case ⛔ cannot suppress the mechanical arm or the ship floor.
  - Whether the harness exports `CLAUDE_SESSION_ID` to hooks cannot be seen in code.
- Whether `wrap-ledger`'s `DIRTY` counts untracked files the same way `session_dirty_mine`'s `-uall` does. I did not read that part of the ledger.
