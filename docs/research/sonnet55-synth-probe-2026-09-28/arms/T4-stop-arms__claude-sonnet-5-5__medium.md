# When `hooks/session-continue.sh` blocks a Stop

I read `hooks/session-continue.sh` in full and the function bodies of `hooks/lib/session-writes.sh`. I read `hooks/lib/continue-sentinel.sh`, the relevant parts of `hooks/lib/mailbox-pending.sh` and `hooks/lib/agent-identity.sh`, and the rung ladder in `scripts/wrap-ledger.sh`. Everything below comes from code, not comments.

## Order of evaluation and the single gate

- **Sentinel path, computed first.** The sentinel is `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/state/continue-<16-hex of shasum(config-dir|cwd)>` (`hooks/lib/continue-sentinel.sh:19-27`). The Stop hook computes it from stdin's `.cwd`, falling back to `$PWD` (`hooks/session-continue.sh:309-311`).
- **The gate.** The three floors run only when the sentinel file is absent: `if [ ! -f "$f" ]` (`hooks/session-continue.sh:1205`).
  - Inside the gate, `.count`, `.sid` and `.cwd` are deleted first (`:1206`).
  - Then the order is `mechanical_arm` (`:1207`), `ship_floor` (`:1208`), `wake_floor` (`:1213`).
  - A floor that blocks prints its JSON and exits 0 (`:1209-1211`, `:1214-1216`).
- **Sentinel present.** The floors are never reached. Control goes straight to kill-switch (`:1228`), then sid-bind (`:1246`), then cap (`:1258`), then the block (`:1329-1335`).
- **Mechanical arm.** It never prints a block itself. If it returns 0, control falls out of the `if` and into the same armed path (`:1221-1222`).
- **Exit code.** Every path ends `exit 0`. The block is carried in the JSON, not in the exit status (`:1211`).

**Block payloads per invocation: at most one.**
- The armed path emits exactly one `jq -nc` block (`:1332` or `:1334`).
- `ship_floor` and `wake_floor` each emit a block only on their own rc 1, and the caller then exits (`:1209-1216`).
- Non-block `{systemMessage}` JSON can also appear. `wake_floor` prints it on its abstain and exhausted paths, and the cap path prints one. None of these carries `decision:block`.
- `ship_floor` prints no JSON on rc 0. Its stdout is captured in `_sf_json` and dropped if the floor returns 0.

## Arm 1 — agent-armed sentinel (`decision:block`, `:1329-1335`)

**(a) Trigger**
- Something ran `session-continue.sh set "<step>"` (`:139-156`) or the mechanical arm wrote the file. In both cases the sentinel file for this cwd exists.
- The last genuine user message does not match `KILL_RE` (`:1228`).
- The stored sid and `cur_sid` are not both known and different (`:1245-1252`).
- The count is below the cap (`:1258`).
- No assignee, teardown, headless or goal check exists anywhere between `:1225` and `:1335`. That path has no identity exemption.

**(b) Bound**
- **File and key:** `${f}.count`, keyed on the config-dir|cwd hash. It is incremented at `:1269-1270`.
- **Variable and default:** `CLAUDE_CONTINUE_MAX`, default `8` (`:1255`). It is not validated. `0` makes the first check `0 -ge 0` true, so the hook never blocks. A non-numeric value makes `[ -ge ]` error, which reads as false, so the cap never trips.
- **At the cap:** the hook deletes the sentinel, `.count`, `.sid` and `.cwd`, prints a `systemMessage` naming the re-arm lever, and allows the stop (`:1258-1267`).
- **Resets:** `set` runs `rm -f ${f}.count` (`:142`). The block text tells the model to re-`set` each turn (`:1304`).
- **Mail fold:** if `_ouid` is a valid key, a peer-mail window is peeked or taken and prepended to the reason (see the mail section below).

**(c) Ownership**
- **How it is decided:** it is decided by sid-bind, inline at `:1245-1252`. There is no library function.
- **What `set` records:** `set` writes the arming session id to `${f}.sid` when one exists (`:145-146`). The mechanical arm writes the same file (`:1071`).
- **Effect:** the sentinel is cleared and the stop allowed only when both sids are non-empty and differ. An empty sid on either side means no evidence, so no clear, and the sentinel proceeds to block.
- **Return codes:** there are none. The sid check is binary.

**(d) Suppression**
- Kill phrase in the last user message (`:1228-1233`). `kill_switch_active` reads the last non-`isMeta` user record via `jq` (`:380-385`) and greps `KILL_RE` (`:348`, `:394`).
- Sid mismatch (`:1246`).
- Cap (`:1258`).
- The CLI `clear` verb (`:157-291`).
- There is no env var that disables this arm. The only lever is `CLAUDE_CONTINUE_MAX=0`, which is a side effect of the cap, not a switch.

## Arm 2 — mechanical uncommitted-writes arm (`mechanical_arm`, `:938-1079`)

**(a) Trigger.** It fires only when there is no sentinel. All of these must hold:
- `CC_MECH_CONTINUE` is not `0`, and `jq` is present (`:939-940`).
- No kill phrase is active (`:950`, logged as `cleared/mechanical-kill-switch`).
- The session is not an assignee. `agent_assignee_argv` matches and `agent_team_member_confirms` returns 0 or 2 (`:968-980`). Return 1 (refuted) does not exempt.
- There is no fresh teardown marker (`wf_teardown_marked`, `:983`).
- The library, `jq` and the ledger script resolve (`:985-1014`).
- `wrap-ledger.sh --machine`, run in `$cwd`, prints `RUNG=🔧` (`:1013-1017`). A rung of ⛔, 📦, 🚀 or ✅ ends it. The ledger sets 🔧 for any of several causes (`scripts/wrap-ledger.sh:1979-2037`), so the rung alone does not prove this session's dirt.
- `session_dirty_mine "$TP_MECH" "$cwd"` returns 0 with non-empty output (`:1022-1024`).
- The budget is not spent (`:1062`).

On arming, it writes the sentinel text, `.sid` and `.cwd` (`:1070-1075`) and logs `armed/mechanical-dirty`.

**(b) Bound**
- **Own budget:** `${f}.mech` holds `"<sid> <count>"`. It is keyed on session id inside the cwd-hash file (`:1053-1068`). It is not deleted when the sentinel clears, and a different sid resets it (`:1060`).
- **Its variable and default:** `CC_MECH_MAX`, default `2` (`:1053`). It is not validated.
- **Inherited bound:** the armed path's `CLAUDE_CONTINUE_MAX` (default 8). `.count` is zeroed at `:1206` before each arm, so the worst case is 2 × 8 = 16 blocks. The comment at `:1046-1049` says this too.
- **Budget spend:** the CLI `clear` spends this budget by writing `"$SC_SID ${CC_MECH_MAX:-3}"` to `${f}.mech` (`:261`).

**(c) Ownership**
- **Function:** `session_dirty_mine <transcript> <dir>` in `hooks/lib/session-writes.sh:277-361`.
- **How it works:** it intersects two sets.
  - The paths this session wrote, from `session_writes_paths`. That is Write, Edit, MultiEdit and NotebookEdit `tool_use` records in the main transcript plus subagent transcripts (`:171-183`).
  - `git status --porcelain -z -uall`, with both sides canonicalised (`:277-361`).
- **Return codes:**

| rc | Meaning | Blocks? |
|---|---|---|
| 0 | some dirty path was written by this session | only this one permits arming |
| 1 | nothing of this session's is dirty (`:283`, `:360`), or no writes | no |
| 2 | cannot tell (no git, unreadable transcript, git failure) (`:279`, `:282`, `:286`, `:320`) | no |

  The code is `[ "$mrc" -eq 0 ] || return 1` (`session-continue.sh:1023`).

**(d) Suppression**
- Kill phrase.
- Assignee (rc 0 or 2).
- Teardown marker.
- Spent budget.
- Non-🔧 rung.
- Attribution rc 1 or 2.
- Disabled outright by `CC_MECH_CONTINUE=0`. Only the literal `0` disables it (`:939`).
- There is no headless or goal check in this arm.
- Once armed, it inherits the armed path's checks.

## Arm 3 — ship floor (`ship_floor`, `:1098-1199`)

**(a) Trigger.** No sentinel, and the mechanical arm returned 1. All of these must hold:
- `CC_SHIP_FLOOR` equals `1`, and `jq` is present (`:1099-1100`).
- No kill phrase is active (`:1101`).
- The session is not an assignee (rc 0 or 2, `:1103-1109`).
- There is no teardown marker (`:1110`).
- A ledger is available. It reuses `SC_LED_CACHE` from the mechanical arm or reruns `wrap-ledger.sh` (`:1115-1126`).
- The rung is 📦 or 🚀 (`:1128`).
- Attribution passes:
  - For 📦, `session_unlanded_mine "$TP_MECH" "$cwd" "$trunk"` returns 0. `TRUNK` from the ledger must be non-empty and not `none` (`:1146-1151`).
  - For 🚀, `session_writes_paths "$TP_MECH"` returns 0 (`:1152-1155`).
- It is not latched (same session and same HEAD sha) and the budget is not spent (`:1172-1178`).

**(b) Bound**
- **File:** `${f}.ship`, holding `"<sid> <HEAD sha> <count>"`. It is keyed on the cwd hash, then on sid and HEAD sha inside the file (`:1162-1179`). A different sid zeroes the count and the sha (`:1170`).
- **Variable and default:** `CC_SHIP_FLOOR_MAX`, default `2`. It is validated: a non-numeric value falls back to 2 (`:1162`).
- **Latch:** one fire per HEAD sha per session.

**(c) Ownership.** Both functions are in `hooks/lib/session-writes.sh`.
- **`session_unlanded_mine` (`:375-432`).** It intersects session-written paths with `git diff --name-only <trunk>..HEAD`.

| rc | Meaning |
|---|---|
| 0 | a commit ahead of trunk touches something this session wrote |
| 1 | not this session's |
| 2 | cannot tell |

  At the call site, any non-zero return is treated as "not mine". It logs `abstained/ship-floor-not-mine` and returns 0 (`session-continue.sh:1150-1151`). So only rc 0 permits a block.
- **`session_writes_paths` (for 🚀).** rc 0 means it wrote something. rc 1 and rc 2 both abstain (`:1154`).

**(d) Suppression**
- Kill phrase, assignee, teardown, latch, budget, not-mine, and a rung that is neither 📦 nor 🚀.
- Disabled outright by `CC_SHIP_FLOOR` set to anything other than `1`.
- There is no headless or goal check in this arm.
- Budget exhaustion is logged and prints a stderr line. It emits no `systemMessage`.

## Arm 4 — wake / mail / custody floor (`wake_floor`, `:603-895`)

**(a) Trigger.** No sentinel, and the mechanical arm and the ship floor did not block.

Preconditions:
- `CC_WAKE_FLOOR` equals `1`.
- `jq` is present.
- `mailbox_wake_armed` is defined.
- `_ouid`, the canonicalised box key, is a safe filename (`:604-607`).

It does not block if any of these apply:
- A live watcher is armed. `mailbox_wake_armed` returns 0 when a fresh `.watching` file exists and its pid is alive (`hooks/lib/mailbox-pending.sh:291-301`). In that case the floor deletes its budget file and returns (`session-continue.sh:614`).
- The session is headless: `CC_PANE_ID` is set and `ITERM_SESSION_ID` is empty (`:656-664`).
- A `/goal` is live **and** mail is pending (`:697-703`).
- The session is an assignee (rc 0 or 2 both abstain, rc 1 does not) or has a fresh teardown marker (`:776-798`).

It then requires at least one of:
- `cnt == 0` (first idle of the session).
- Pending mail: `pend > 0`, from `mailbox_pending_count`, which is lines minus seen (`mailbox-pending.sh:245`).
- Open custody: `cust > 0` (`:805`).

Custody is counted through the `cc-custody` binary (`:737-766`):
- With a pane id and `jq`, it counts rows that have `originatorPane`, or `notifyBack` equal to the pane or ending in `-<pane>`, as `cust_mine`.
- Rows carrying neither field count as `cust_unk`.
- With no pane id, it uses the old whole-cwd count as `cust_unk`.

Then it requires all of:
- `cnt < maxa` (`:836`).
- At least `ttl` seconds since the last attempt (`:845`).
- No kill phrase (`:850`).

When it fires, it writes the state file, then emits the block with `systemMessage` (`:856-893`).

**(b) Bound**
- **File:** `$CC_MAILBOX_DIR/<_ouid>.wakefloor`, holding `sid=`, `count=` and `ts=`. `CC_MAILBOX_DIR` defaults to `$HOME/.claude/mailbox`. It is keyed on the canonical mailbox key, not on the cwd (`:610-611`).
- **Fresh budget:** a different non-empty sid resets `count` and `ts` (`:627`).
- **Budget-clearing case:** an armed watcher deletes the file (`:614`).
- **Variables and defaults:**
  - `CC_WAKE_FLOOR_MAX` = `2` (`:807`).
  - `CC_WAKE_FLOOR_TTL_S` = `600` (`:808`).
  - `CC_WAKE_FLOOR_TIMEOUT_S` = `14400`. It affects only the watcher command text (`:821`).
  - `CC_WAKE_FLOOR_TEARDOWN` = `1` (`:776`).
  - `CC_WF_TEARDOWN_FRESH_S` = `1800` (`:555`).
  - `CC_TEARDOWN_DIR` = `$HOME/.claude/watchdog/teardown` (`:553`).
  - `CC_WATCH_FRESH_S` = `90`, which is `mailbox-pending.sh:296`.
- **Exhausted budget:** the floor prints a `systemMessage` and allows the stop (`:836-843`).

**(c) Ownership**
- **Mail:** there is no per-session attribution. The box is resolved from the pane by `mailbox_resolve_key` (`:458-466`).
- **Custody:** ownership is by pane, using the `jq` predicate at `:748-754`.
- **Assignee identity:** `hooks/lib/agent-identity.sh`.
  - `agent_assignee_argv` (`:33`) returns 0 and echoes the agent id when the session is an assignee, and 1 otherwise.
  - `agent_team_member_confirms` (`:93`) returns 0 when the team config confirms the member, 1 when refuted, and 2 when it cannot tell.
  - With the library missing, stubs return 1 and 2, meaning not an assignee (`session-continue.sh:539-542`).

**(d) Suppression**
- Headless, live goal with pending mail, assignee, teardown, an armed watcher, kill phrase, TTL, spent budget.
- Disabled outright by `CC_WAKE_FLOOR` set to anything other than `1`.
- `CC_WAKE_FLOOR_TEARDOWN=0` turns off only the floor's assignee and teardown abstains (`:776`).
- The other two floors call `wf_teardown_marked` directly (`:983`, `:1110`), and that call is not gated by this variable.
- A live goal without pending mail does not suppress the floor. It swaps the command to `cc-await-ping --idle-scoped --sid …` (`:827-833`).

## Direct answers

**Which arm never prints its own block but still causes one?** The mechanical arm (`:1207` then `:1221-1222`).
- **It inherits:**
  - the kill-switch check (`:1228`);
  - sid-bind (`:1246`);
  - the `CLAUDE_CONTINUE_MAX` cap and its `.count` (`:1258`);
  - the mail fold (`:1284-1324`);
  - the `.blocked` marker written by `mark_blocked continue` (`:1329`).
- **It does not inherit:** the assignee and teardown exemptions. Those are the mechanical arm's own checks at `:967-983`, and the armed path has none.

**Does unread peer mail by itself block a Stop?** Only through the wake floor.
- It needs pending mail, no armed watcher, no headless abstain, no assignee or teardown abstain, `cnt < 2`, the TTL elapsed, and no kill phrase.
- The block text tells the model to arm a watcher. It does not deliver the mail.
- The sentinel path does not block on mail. Mail is only carried inside a block that already exists.
- The floor's `systemMessage` about pending mail appears only on its abstain and exhausted paths.

**What the mail fold does and does not do** (`:1284-1340`):
- **It does:**
  - It runs only in the armed path, after `.count` is incremented.
  - It claims the drain lock, peeks a window from `mailbox_seen` (`mailbox_drain_claim`, `mailbox_peek_range`), and prepends the mail to the reason with an INBOX header.
  - It sets a `systemMessage` naming the senders.
  - It calls `mailbox_commit_seen` only after the `jq` write succeeds, then releases the claim.
  - It falls back to `mailbox_take "$_ouid" 0` on an older library.
- **It does not:**
  - It does not cause a block, and it does not run in any floor.
  - It does not ack. `.acked` advances on the next Stop, via the unconditional `mailbox_promote_acked` at `:467`.
  - It skips silently if `_ouid` is invalid or the claim fails.

**Env var with two different literal defaults: `CC_MECH_MAX`.**
- The CLI `clear` verb uses `${CC_MECH_MAX:-3}` (`:261`).
- The mechanical arm uses `${CC_MECH_MAX:-2}` (`:1053`).
- With the variable unset, `clear` writes 3, which is at least 2, so the budget is still spent.

## Stale or inaccurate comments I checked

| Where | What it claims | What the code shows |
|---|---|---|
| `hooks/session-continue.sh:963-966` | The mechanical arm's exempt set differs from the wake floor's, which also exempts argv-only and treats rc 1 as non-exempt. | The wake floor abstains on rc 0 and rc 2 and not on rc 1 (`:780-784`). The sets are identical. |
| `:944-945` | Kill-switch lines for `ship_floor :969` and `wake_floor :732-736`. | They are at `:1101` and `:850-853`. |
| `:974` | A sibling that "already logs {assignee,confirm_rc}". | The `ship_floor` log is at `:1106`. |
| `:724`, `:429` | `_opane` is "captured at :197". | It is set at `:425`. |
| `:1049` | "old default of 3" for `CC_MECH_MAX`. | `clear` at `:261` still uses 3. |
| `:1328` | "precedent at :502". | `:502` is comment text. |
| `CLAUDE.global.md:605` and `:1025` | `CLAUDE_CONTINUE_MAX` bounds only the mechanical arm. | The cap at `:1255-1268` applies to every sentinel, including agent-armed ones. |

I did not check citations to other files, such as `hooks/hook-chain.sh:78` or `session-writes.sh:13-22`, so I have not relied on them.
