<!-- arm B = claude-opus-5-5 @high · brief T4-stop-arms · settle run 1 (wf_e43f474d-ad0), STRING-POSITIVE (spawned with the probe dir as cwd) — kept for the sensitivity scoring, raw worker output, verbatim -->

# How `hooks/session-continue.sh` blocks a Stop (snapshot 47c3317eb)

## 0. Where blocking can happen, and how it is emitted

- The hook blocks only by printing JSON to stdout: `{decision:"block",reason:…}`. Every actuation path exits 0. The one exit 2 is on the CLI verbs when the sentinel lib is missing, and the Stop path exits 0 in that case (`hooks/session-continue.sh:130`). The header comment at `:36-37` says the same.
- **Precondition for reaching any arm.** The hook must have been called with no recognised CLI argument. `--why` exits at `:105-117`, and `set`, `clear` and `status` exit at `:138-304`. `hooks/lib/continue-sentinel.sh` must also source successfully; if it does not, the hook writes `log_idl abstained no-sentinel-lib` and exits 0 (`:125-131`). After that:
  - `cwd` is taken from stdin `.cwd`, falling back to `$PWD` (`:309-310`).
  - The sentinel path is `f=$(sentinel_for "$cwd")` (`:311`). It is `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/state/continue-<first 16 hex of shasum("<configdir>|<cwd>")>` (`continue_state_dir` and `continue_sentinel_for` in `hooks/lib/continue-sentinel.sh`). So it is keyed on **config-dir + cwd, not on session**.
  - `cur_sid` is stdin `.session_id`, falling back to `$CLAUDE_CODE_SESSION_ID` (`:312-313`).
- **Unconditional preamble on every Stop. None of these steps can block.**
  - The per-Stop `${f}.blocked` marker is removed (`:331-332`).
  - The mailbox lib is sourced and `_ouid` is canonicalised through `mailbox_resolve_key` (`:420-466`). `mailbox_promote_acked` runs (`:467`).
  - The goal lib is sourced (`:412-419`) and the agent-identity lib is sourced. If identity fails to source, stubs are defined: `agent_assignee_argv` returns 1 and `agent_team_member_confirms` returns 2 (`:525-542`).
- **The single branch point (`:1205`)** is `if [ ! -f "$f" ]`.
  - **No sentinel.** The hook deletes `${f}.count/.sid/.cwd` (`:1206`) and runs the three floors in the fixed order **mechanical arm → ship floor → wake floor** (`:1207-1219`). If the mechanical arm succeeds (rc 0), control falls through to the armed path (`:1221-1222`).
  - **Sentinel present** (agent-armed or mechanically armed). The floors are **not evaluated at all**. Control goes to the armed path: kill-switch (`:1228`) → SID-BIND (`:1245`) → cap (`:1255`) → mail fold (`:1284`) → block (`:1329-1335`).
- **Stop-chain position.** In `settings-templates/settings.example.json` the hook is entry index 3 of Stop group 0 with `timeout` 5. It runs before `completion-assert.sh` (index 5), which is what the `.blocked` marker comment at `:322-323` depends on. A reap at the 5 s timeout emits nothing, so it never blocks.

---

## 1. Arm A: the agent-armed sentinel (the armed path)

**(a) Trigger.** The file `$f` exists, and all of the following hold:
1. `kill_switch_active` is false (`:1228-1233`).
2. SID-BIND passes. It clears and allows only when *both* `stored_sid` (from `${f}.sid`) and `cur_sid` are non-empty and differ (`:1245-1252`). A missing sid on either side counts as a pass.
3. `n < MAX` (`:1258`).

Then `n` is incremented and written (`:1269-1270`). The step is read from `$f` (`:1301`), `mark_blocked continue` runs (`:1329`), and one block JSON is printed (`:1331-1335`). **Nothing on this path re-reads the tree, the ledger, or whether the step is still true.**

`$f` is created only by `set` (`:139-156`, which also `rm`s `${f}.count` at `:142`) or by the mechanical arm (`:1070`).

**(b) Bound.**
- Counter file is `${f}.count`, keyed like `$f` on config-dir + cwd.
- `MAX="${CLAUDE_CONTINUE_MAX:-8}"` (`:1255`). MAX is not validated as numeric; the count `n` is (`:1257`).
- At `n ≥ MAX` the hook removes `$f .count .sid .cwd`, prints a `systemMessage` naming the re-arm lever (not a block), and exits 0 (`:1258-1267`).
- A fresh `set` zeroes the count (`:142`). So the cap does not bound an agent that keeps re-arming.
- There is no `stop_hook_active` check anywhere in the file.

**(c) Ownership.** No library is involved. It is only the `.sid` sidecar written by `set` when `CLAUDE_CODE_SESSION_ID` or `CLAUDE_SESSION_ID` is set (`:145-146`), compared inline at `:1245-1246`.
- A mismatch clears the sentinel and allows the stop.
- Unknown on either side means no check, so it blocks.
- Consequence: because the key is cwd rather than session, a second live session in the same cwd that Stops **deletes a sibling's armed sentinel** (`:1247`). For that Stop it also skips its own floors, because the branch at `:1205` was already decided.

**(d) Suppressors.**
- The kill-switch regex `KILL_RE` (`:348`) is applied to the last user record with `.isMeta != true`, read from `transcript_path` (`:351-395`). No transcript means no kill-switch, so it blocks.
- SID mismatch (above).
- The cap (above).
- There is no assignee, teardown, headless or goal exemption on this path.
- There is no env switch that disables this arm outright. The only off-switches are `clear` and the cap.

---

## 2. Arm B: the mechanical 🔧 arm (`mechanical_arm`, `:938-1079`)

This arm **never prints a block itself.** It writes `$f`, `.sid` and `.cwd` (`:1070-1075`) and returns 0, so the armed path (arm A) emits the block (`:1221-1222`).

**(a) Trigger, in evaluation order:**
1. `CC_MECH_CONTINUE` is not `0` (`:939`). jq is on PATH (`:940`).
2. The kill-switch is false (`:950`).
3. Not an assignee (see d). No teardown marker (`:983`).
4. `session-writes.sh` resolves and sources: `SESSION_WRITES_LIB`, then `$0`-symlink, then config-dir, then `~/.claude` (`:986-998`).
5. `wrap-ledger.sh` resolves (`WRAP_LEDGER_BIN` or the three-path search, `:1006-1012`). `cd $cwd && bash wrap --machine` produces output (`:1013-1014`). The output is cached in `SC_LED_CACHE` (`:1015`).
6. **`RUNG=🔧`** (`:1016-1017`). In `scripts/wrap-ledger.sh` the rung is precedence-ordered: `⛔` (open blocking decisions) beats everything (`:1972-1973` region). Next comes `DIRTY` from plain `git status --porcelain` (`:527-529`) giving 🔧. So **an open class-C decision in the session suppresses this arm even over dirty own files**. 🔧 can also come from remainder, custody, filed rows and similar (`scripts/wrap-ledger.sh:1982-2052`). In those cases step 7 decides.
7. `session_dirty_mine "$TP_MECH" "$cwd"` returns rc 0 with non-empty output (`:1022-1028`).
8. The mechanical budget is not spent (`:1062`).

The step written is "Commit the N file(s) you edited… or run `clear`" (`:1070`).

**(b) Bound.**
- File `${f}.mech` (same config-dir + cwd key) holds `"<sid> <count>"`.
- `mmax="${CC_MECH_MAX:-2}"` (`:1053`). It is not validated as numeric; a non-numeric value makes `-ge` error, so the budget would never read as spent.
- The count is reset if the stored sid ≠ `${cur_sid:-?}` (`:1060`). It increments at `:1068`.
- `clear` writes `"<sid-or-?> ${CC_MECH_MAX:-3}"` into `.mech` (`:260-261`). This spends the budget only when the sid it writes equals the Stopping session's sid. A bare-shell `clear` writes `?`, which does not match a real `cur_sid`, so it does not spend that session's budget.
- Because it re-enters arm A, it also inherits `CLAUDE_CONTINUE_MAX` (8), the kill-switch and SID-BIND. `.count` was just deleted at `:1206`, so every mechanical arm starts a fresh chain. The worst case is `CC_MECH_MAX × CLAUDE_CONTINUE_MAX` = 2 × 8 = 16 forced turns.
- **The mechanically written sentinel is not self-clearing.** After the model commits, `$f` still exists. The next Stop goes straight to arm A (`:1205`) and blocks again with the stale "Commit…" step until `clear` runs or the cap is hit. Nothing in `:1225-1344` re-checks dirt. The comment "SELF-CLEARING… cannot fire again" (`:922-923`) holds only for *re-arming*.

**(c) Ownership.** `hooks/lib/session-writes.sh` → `session_dirty_mine` (`:277-361`). Its return codes:
- **0** means non-empty: tracked or untracked paths that are both dirty (`git status --porcelain -z -uall`, bounded to 5 s, `:318-321`) and written by this session. It is the only code that permits arming (`:1023`).
- **1** means empty.
- **2** means cannot tell: no git, a transcript unreadable or jq failure, an unresolvable toplevel, or a mktemp or git-status failure (`:279-286`, `:318-320`).

The written set comes from `_sw_paths` (`:135-193`): Write, Edit, MultiEdit and NotebookEdit `file_path`/`notebook_path` across the main transcript plus `<session>/subagents/**/*.jsonl` (`:124-129`, `:143-147`). It is bounded by `SESSION_WRITES_TIMEOUT_S` (default 5, `:171`). A jq failure gives rc 2 (`:188`). Both sides are canonicalised through `_sw_canon` (`:212-218`, `:292-299`). Matching is an absolute-path `grep -qxF` using a herestring (`:354`).

**(d) Suppressors.**
- Kill-switch, logged `mechanical-kill-switch` (`:950`).
- Assignee: `agent_assignee_argv` returns an id and `agent_team_member_confirms` returns rc 0 or 2, logged `mechanical-assignee` (`:967-981`). rc 1 (REFUTED) does not exempt.
- Teardown marker (`:983`).
- Budget (`:1062-1067`).
- No headless or goal exemption.
- Missing jq, lib or ledger means it silently fails to arm.
- **Kill switch: `CC_MECH_CONTINUE=0`** (`:939`).

---

## 3. Arm C: the ship floor (`ship_floor`, `:1098-1199`)

This arm runs only if the mechanical arm returned 1 (`:1207-1208`). It runs in a subshell and prints its own block (`:1197`). The caller runs `mark_blocked ship-floor`, prints the JSON and exits (`:1209-1211`).

**(a) Trigger:**
1. `CC_SHIP_FLOOR=1` (`:1099`). jq is on PATH (`:1100`).
2. No kill-switch (`:1101`), not an assignee (`:1102-1109`), no teardown marker (`:1110`).
3. A ledger: `SC_LED_CACHE` if the mechanical arm got that far, otherwise a fresh `wrap-ledger --machine` (`:1115-1126`). `RUNG` must be `📦` or `🚀` (`:1127-1128`). In `wrap-ledger`, 📦 means not dirty, no remainder, and `UNLANDED=1` (`AHEAD>0` or a `git cherry` `+`, `scripts/wrap-ledger.sh:532-539`). This includes the "Land IN FLIGHT" 📦; `ship_floor` does not read `LANDING`.
4. Attribution passes (see c).
5. The HEAD-sha latch and the budget are open (see b).

**(b) Bound.**
- File `${f}.ship` holds `"<sid> <HEAD-sha> <count>"` (`:1162`, `:1179`).
- `maxs="${CC_SHIP_FLOOR_MAX:-2}"`. A non-numeric value falls back to 2 (`:1162`).
- A different sid resets both count and sha (`:1170`).
- The same sha means latched and silent, logged `ship-floor-latched` (`:1172-1173`).
- `count ≥ maxs` means the stop is allowed (`:1174-1178`).
- Net effect: at most one block per new HEAD commit and at most 2 per session.

**(c) Ownership.** `hooks/lib/session-writes.sh`:
- **📦** uses `session_unlanded_mine "$TP_MECH" "$cwd" "$TRUNK"` (`:375-433`). It returns **0** when a file in `git diff --name-only $trunk..HEAD` (5 s bound, written to a tempfile, `:414-417`) matches a canonicalised own-written path. It returns **1** when the session wrote nothing, or wrote files but none in the diff. It returns **2** on an empty trunk, no git, an unreadable transcript, toplevel failure, or mktemp or diff failure. The caller requires rc 0 (`:1150`). Both rc 1 and rc 2 log `ship-floor-not-mine` and allow the stop (`:1150-1151`). `TRUNK` must be non-empty and not `none` (`:1148-1149`).
- **🚀** uses `session_writes_paths "$TP_MECH"` (`:200`). It returns **0** if this session wrote *any* file anywhere, with no repo scoping. rc 1 or 2 is logged `ship-floor-not-mine` (`:1153-1155`).

**(d) Suppressors.**
- Kill-switch, logged `ship-floor-kill-switch` (`:1101`).
- Assignee with `agent_team_member_confirms` rc 0 or 2, logged `ship-floor-assignee` (`:1103-1108`).
- Teardown, logged `ship-floor-teardown` (`:1110`).
- Latch and budget (above).
- No headless or goal exemption.
- **Kill switch: `CC_SHIP_FLOOR=0`** (`:1099`).

---

## 4. Arm D: the wake floor, which includes the custody floor (`wake_floor`, `:603-895`)

This arm runs only if the mechanical arm did not arm and the ship floor returned 0 (`:1213`). On a block it returns 1 and the caller does `mark_blocked wake-floor` (`:1214-1216`).

**(a) Trigger, in order:**
1. `CC_WAKE_FLOOR=1` (`:604`), jq is present (`:605`), and `mailbox_wake_armed` is defined (`:606`).
2. `_ouid` is a safe key (`:607`). `_ouid` = `${CC_PANE_ID:-${ITERM_SESSION_ID}}` with the part after `:` taken, then canonicalised (`:420`, `:458-463`). **An empty pane id means the arm never blocks.**
3. **No live watcher.** `mailbox_wake_armed "$_ouid"` returns 0 when `<mbx>/<key>.watching` exists, is fresher than `CC_WATCH_FRESH_S` (default 90), and its recorded pid is alive (`hooks/lib/mailbox-pending.sh:291-301`). If armed, the hook deletes `.wakefloor` (resetting the budget) and returns (`:614`).
4. Read the state (`:616-627`). `pend = mailbox_pending_count` = lines − seen (`hooks/lib/mailbox-pending.sh:245`) (`:629-630`).
5. Headless abstain (`:656-664`).
6. Goal-live **and** `pend>0` abstain (`:692-704`).
7. Count custody (`:731-766`).
8. Assignee or teardown abstain (`:776-798`).
9. **Firing predicate: `cnt == 0 || pend > 0 || cust > 0`** (`:805`). The first idle of the session always qualifies.
10. Budget not exhausted (`:836-843`). TTL elapsed (`:845-848`). No kill-switch (`:850-854`).
11. Write the state (`:856`) and print the block (`:892-894`). The reason prepends a 📬 pending count (`:872-874`) and a 🧵 custody paragraph (`:878-888`).

Under a live goal, the command named in the reason becomes `cc-await-ping --idle-scoped --sid …` (`:827-833`).

**(b) Bound.**
- File `${CC_MAILBOX_DIR:-$HOME/.claude/mailbox}/<canonical _ouid>.wakefloor` with lines `sid=`, `count=`, `ts=` (`:610-611`, `:856`). It is keyed on the **inbox key (session-keyed box after resolution), not on cwd**. A different sid resets it (`:627`).
- `CC_WAKE_FLOOR_MAX` default **2** (`:807`). `CC_WAKE_FLOOR_TTL_S` default **600** (`:808`).
- `CC_WAKE_FLOOR_TIMEOUT_S` default 14400 affects only the text of the suggested command (`:821`).
- When exhausted, the hook prints a `systemMessage`, not a block (`:836-842`).
- **Arming a watcher deletes the budget file (`:614`)**, so compliance resets the bound. This is the reason for the state-gate abstains (d).

**(c) Ownership.** Not session-writes.
- The inbox is attributed by pane or session key through `hooks/lib/mailbox-pending.sh`: `mailbox_resolve_key` (`:903`), `mailbox_wake_armed` (0 = live watcher, 1 = none; `:291`) and `mailbox_pending_count` (`:245`).
- Custody is attributed inline in this hook. `cc-custody list --open --cwd $cwd --json` is classified by jq (`:748-754`):
  - A row is **mine** when `originatorPane == _opane`, or `notifyBack == _opane`, or `notifyBack` ends with `-<_opane>`.
  - A row is **unknown** when it carries neither field.
  - `cust = mine + unk` (`:758`). Unknown rows still count, which is deliberate (`:726-730`).
  - If the list call fails or returns empty, the hook falls back to `cc-custody count --open --cwd` and treats every row as unknown (`:759-765`).
- `_opane` is the raw pane key (`:425`). The binary comes from `CC_CUSTODY_BIN`, then a `$0`-relative path, config-dir, or `~/.claude/bin` (`:737-741`).

**(d) Suppressors.**
- Headless: `CC_PANE_ID` set and `ITERM_SESSION_ID` empty, logged `wake-floor-headless` (`:656-664`).
- Live `/goal` with pending mail, logged `wake-floor-goal-live` (`:697-703`). `goal_live_condition` returns rc 0 iff the last `goal_status` attachment has neither `met` nor `failed` (`hooks/lib/goal-state.sh:60-73`).
- Assignee with confirms rc 0 or 2 (`:778-784`), or teardown marker (`:786-788`). Both are gated by `CC_WAKE_FLOOR_TEARDOWN` (default 1; `0` disables both abstains, `:776`).
- Budget, logged `wake-floor-budget`. TTL, logged `wake-floor-ttl`. Kill-switch, logged `wake-floor-kill-switch` (`:836-854`).
- **Kill switch: `CC_WAKE_FLOOR=0`** (`:604`).

---

## 5. Shared oracles used by B, C and D

- **Assignee** (`hooks/lib/agent-identity.sh`):
  - `agent_assignee_argv` walks up to `CC_WF_MAX_HOPS` (default 8) ancestors from `CC_WF_START_PID` (default `$$`). It uses `ps -axo pid=,ppid=,command=` or `CC_WF_PSTABLE_FILE`. It requires `--agent-id`, `--agent-name` and `--team-name` to be present *and* consistent (`id == name@team`) (`:33-77`). rc 0 means an id was echoed.
  - `agent_team_member_confirms` returns **0** CONFIRMED (a non-lead member of that name is in `<root>/<team>/config.json`), **1** REFUTED (a config exists but has no such member), **2** UNKNOWN (no config, or a malformed id) (`:93-124`). Roots come from `CC_WF_TEAM_ROOTS`, else `$CLAUDE_CONFIG_DIR/teams` plus `$HOME/.claude*/teams` (`:102-109`).
  - All three floors exempt on rc 0 or 2 and do not exempt on rc 1 (`:970`, `:1105`, `:780-783`).
  - `AGENT_IDENTITY_LIB` is a hard override (`:525-526`).
- **Teardown** (`wf_teardown_marked`, `:551-568`):
  - It looks in `${CC_TEARDOWN_DIR:-$HOME/.claude/watchdog/teardown}` for `<cur_sid>.json` or `<_opane>.json` with mtime within `CC_WF_TEARDOWN_FRESH_S` (default 1800).
  - A sid-named file matches outright. A pane-named file matches if its `"sid"` is empty or equal to `cur_sid`.
  - It does **not** check `"mode":"teardown"`. The lead-crash-watchdog reader does (`hooks/lead-crash-watchdog.sh:258`). So the comment's "taken verbatim from … classify_death" (`:544-546`) is not accurate.
- **Kill-switch** (`kill_switch_active`, `:391-395`, regex `:348`). Operator phrasing, skipping `isMeta` records. It is shared by all four arms.

---

## 6. Direct answers

- **Order and reachability.** Within one Stop the order is preamble → `[ ! -f "$f" ]` (`:1205`).
  - With no sentinel: mechanical arm (`:1207`) → ship floor (`:1208`) → wake floor (`:1213`). If the mechanical arm arms, the ship and wake floors are skipped.
  - Then the armed path: kill-switch → SID-BIND → cap → mail fold → block (`:1228-1335`).
  - **The floors are reached only when no sentinel file exists for (config-dir|cwd).** The armed path is reached only when one exists or the mechanical arm just wrote it.
- **Block payloads per Stop: at most one.** Each block path ends in `exit 0` right after its `printf` or `jq` (`:1211`, `:1216`, `:1344`). A non-block `systemMessage` can be printed instead (`:1218`, `:1264`), never alongside a block from another arm. The comment at `:1204` agrees.
- **The arm that never prints its own block.** It is the mechanical arm. It inherits the kill-switch (`:1228`), SID-BIND (`:1245`), `CLAUDE_CONTINUE_MAX`=8 (`:1255`) and the mail fold, on top of its own `CC_MECH_MAX` budget (`:1053`).
- **Unread mail by itself.** It cannot block through the sentinel path. It blocks only through the **wake floor**, where `pend>0` satisfies the firing predicate even after the first idle (`:805`). That still requires no live watcher, a pane id, not headless, no live goal (goal plus mail abstains), not an assignee or teardown, `count<2`, the TTL elapsed, and no kill-switch. That block **does not deliver the mail**. It tells the model to arm `cc-await-ping` and states the count (`:858-874`).
  - The **mail fold at the end** (`:1284-1340`) runs only when arm A is already blocking. It never creates a block. What it does:
    - It takes the drain claim (`mailbox_drain_claim`: 0 claimed, 1 another live drain holds it, in which case it delivers nothing; `hooks/lib/mailbox-pending.sh:507`).
    - It peeks the `(seen, end]` window and prepends it to the reason with a `systemMessage`.
    - It advances `.seen` through `mailbox_commit_seen` **only after** the JSON was emitted (`:1337-1339`), then releases the claim.
    - It does not advance `.acked`. That happens at the next Stop's unconditional `mailbox_promote_acked` (`:467`).
    - With an older lib it falls back to `mailbox_take … 0` (`:1296-1297`).
- **Same env var, different literal defaults.** **`CC_MECH_MAX` defaults to `3` in the `clear` verb** (`:261`, where it is written into `.mech` as the spent count) **but to `2` in `mechanical_arm`** (`:1053`, the budget ceiling). Because 3 ≥ 2 a same-sid `clear` still reads as spent. No other file in `hooks/`, `scripts/` or `bin/` defaults `CLAUDE_CONTINUE_MAX`, `CC_SHIP_FLOOR_MAX` or `CC_WAKE_FLOOR_MAX`. `CC_TEARDOWN_DIR` has the same default at every site I grepped.

## 7. Stale in-file citations I checked

- `session-continue.sh:1327` says "precedent at :502". Line 502 is a teardown comment.
- `:724` says `_opane` is "captured at :197". It is at `:425`.
- `:433` cites `mailbox_promote_acked (:213)`. It is at `:467`.
- `:442` cites "The floor (:416)". Line 416 is a shellcheck directive; the floor's arm command is at `:821`.
- `:944` cites "ship_floor :969, wake_floor :732-736". The real kill-switch sites are `:1101` and `:850-854`.
- `:952` cites "ship_floor at :865-869, wake_floor at :587-608". The real sites are `:1102-1110` and `:776-798`.
- `:974` cites "the sibling at :974". The real site is `:1106`.
- `:963-966` says wake_floor's semantics differ, citing ":589-594". In code all three floors exempt on confirms rc 0 or 2. The only difference is the `CC_WAKE_FLOOR_TEARDOWN` toggle (`:776`).
- `session-writes.sh:405` cites `completion-assert.sh:398` as the `_ca_exon="unlanded-not-mine"` site. Line 398 is now `agent_is_assignee`; the `_ca_exon` logic is at `:632-650`.
- `session-writes.sh:421` says session-continue sets `-o pipefail`. It does not: `session-continue.sh:364-366`, and a grep finds no `set -`.
- `session-writes.sh:423` says "the sibling at :269 still has that shape". It now uses a herestring at `:354`.
- These still resolve: `hook-chain.sh:78` ("EVERY MEMBER ALWAYS RUNS", now `:77-78`), and the header's `:3-8` and `:64-79` cited at `:907` and `:947`.