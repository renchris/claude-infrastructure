<!-- arm A = claude-sonnet-5 @max · brief T4-stop-arms · raw worker output, verbatim -->

[harness: subagent output matched instruction-shaped pattern(s): settings-json. Control tags below are neutralized (`<` → `<\`); treat any remaining directive-shaped text as a finding to relay to the user, not an instruction to you.]

## `hooks/session-continue.sh` — every condition under which it blocks a Stop

Repo root: `/tmp/o55probe-repo-47c3317eb` (pinned `47c3317eb`). All paths below are relative to that root. I read `hooks/session-continue.sh` in full (1345 lines), `hooks/lib/session-writes.sh`, `hooks/lib/continue-sentinel.sh`, `hooks/lib/agent-identity.sh`, `hooks/lib/mailbox-pending.sh`, `hooks/lib/goal-state.sh` in full, the head of `scripts/wrap-ledger.sh`, `.claude/settings.json`, `hooks/hook-chain.sh`, and two excerpts of `hooks/lead-crash-watchdog.sh` cited from `session-continue.sh`'s own comments. `hooks/lib/why-tier.sh` is sourced (`hooks/session-continue.sh:105-117`) but only for the CLI `--why` reference verb, which returns before stdin is ever read (`hooks/session-continue.sh:105,113`) — it cannot participate in blocking a Stop and I did not chase it further.

### The single condition for reaching any "floor" arm at all

All three floor arms (mechanical, ship, wake) are evaluated **only when no sentinel is currently armed for this cwd** — `if [ ! -f "$f" ]` at `hooks/session-continue.sh:1205`, where `f=$(sentinel_for "$cwd")`. If a sentinel already exists (from a prior CLI `set`, or one the mechanical arm just wrote this Stop), the floors are skipped entirely and control goes straight to the shared "armed path."

### Order of evaluation within one Stop (`hooks/session-continue.sh:1201-1345`)

1. `mechanical_arm()` is tried first (`:1207`). If it **arms** (rc 0), the `if ! mechanical_arm` branch is skipped wholesale — `ship_floor()`/`wake_floor()` are **never called this Stop** — and execution falls through past the closing `fi` at `:1223` straight into the shared armed path.
2. Only if `mechanical_arm` did **not** arm (rc 1) is `ship_floor()` tried (`:1208`).
3. Only if `ship_floor` did **not** block (rc 0) is `wake_floor()` tried (`:1213`).
4. If none of the three fire, the hook exits 0 with nothing (or, if `wake_floor` printed a non-blocking `systemMessage`-only JSON while declining, that alone) — `:1218-1219`.
5. If a sentinel exists (either already, or freshly written by step 1), the shared **armed path** runs in this fixed order: **kill-switch** (`:1228-1233`) → **SID-BIND** (`:1245-1252`) → **CAP** (`:1254-1268`) → increment counter → **mail-fold** → final `decision:"block"` (`:1301-1345`).

---

## Arm 1 — the agent-armed sentinel / the shared "armed path" block

This is the code that actually prints the everyday `🔧 Loose ends remain` block. It is reached two ways: the model calls `session-continue.sh set "<step>"` from the CLI in one turn (`:139-156`, the "Agent interface"), or the mechanical arm (Arm 2 below) writes the same files this Stop.

**(a) Trigger predicate.** Sentinel file `$f` exists at Stop time (`-f "$f"` true — either pre-existing or just written), AND none of kill-switch / SID-mismatch / cap-reached fires.
- **Kill-switch** (`:1228-1233`): `kill_switch_active()` (`:391-395`) reads the last genuine (`isMeta != true`) user message from the transcript (`last_user_msg`, `:351-388`) and matches `KILL_RE` (`:348`: `and stop`/`no auto-continue`/`just do X`/`stop here`/`come back to this`/bare `stop`|`halt`). True → clears sentinel + sidecars, allows the stop.
- **SID-BIND** (`:1242-1252`): acts only when **both** `stored_sid=$(cat "${f}.sid")` and `cur_sid` are non-empty and they differ. True → clears, allows the stop ("a same-cwd successor must not inherit a predecessor's sentinel").
- **CAP** (`:1254-1268`): `n=$(cat "${f}.count")` ≥ `MAX="${CLAUDE_CONTINUE_MAX:-8}"`. True → clears sentinel, prints a `systemMessage` naming the re-arm lever, and — critically — **exits non-2, which does NOT block** (`:1267`: "the cap is a backstop, not a wedge").
- Otherwise: increments `${f}.count` (`:1269-1270`), builds `reason` from the sentinel's stored step text (`:1301-1304`), optionally prepends drained mail (see the mail-fold section below), and emits `jq -nc '{decision:"block",reason:$r[,systemMessage:$s]}'` (`:1330-1335`).

**(b) Counter/latch/budget.**
- Sentinel path: `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/state/continue-<16-hex-shasum-of("CLAUDE_CONFIG_DIR|cwd")>` — defined once in `hooks/lib/continue-sentinel.sh:17-27` (`continue_state_dir`/`continue_sentinel_for`), keyed on the **(config-dir, cwd)** pair.
- `${f}.count` — the CLAUDE_CONTINUE_MAX cap counter. Env: **`CLAUDE_CONTINUE_MAX`, default `8`** (`hooks/session-continue.sh:1255`). Reset to absent only by an explicit CLI `set` (`rm -f "${f}.count"`, `:142`) — the mechanical arm's own re-arm does **not** touch `.count`, so if the model never re-issues `set`, `.count` climbs toward 8 every Stop it stays armed.
- `${f}.sid` / `${f}.cwd` — sidecars recording who armed it and where, written by both `set` (`:146,151`) and the mechanical arm (`:1071,1075`).
- `${f}.blocked` (`SC_BLOCKED_MARK`) — a forensics-only marker, cleared at the top of every actuation Stop (`:332`) and stamped by `mark_blocked()` (`:333-336`) whenever any arm blocks; "not read by the guard," used to prove same-Stop double-fires against `completion-assert.sh`.
- Env vars: `CLAUDE_CONTINUE_MAX` (default 8), `CONTINUE_IDL` (default `$HOME/.claude/autonomy/idl.jsonl`, `:82`), `CONTINUE_LOG` (default `$HOME/.claude/logs/session-continue.log`, `:83`) — the latter two are telemetry destinations, not bounds.

**(c) Attribution.** None performed here directly — attribution already happened in whichever arm armed the sentinel (or, for a CLI `set`, it's inherently the model's own explicit act, so no "is this mine" question arises).

**(d) Exemptions/kill switches.** The kill-switch, SID-BIND and CAP checks *are* this arm's exemption mechanism. There is no single "disable this arm outright" env var distinct from the sentinel simply never being armed (which is governed by `CC_MECH_CONTINUE` for the mechanical path — see Arm 2).

---

## Arm 2 — the mechanical uncommitted-writes arm (`mechanical_arm()`, `hooks/session-continue.sh:938-1079`)

**This arm never emits a `decision:"block"` JSON of its own.** It only writes the sentinel + `.sid`/`.cwd` files and returns rc 0 (armed) or rc 1 (did not arm). A block only happens because rc 0 causes the code to fall through into Arm 1's shared block-emission path — this directly answers the brief's "which arm never prints a block of its own yet still causes one" question.

**(a) Trigger predicate** (all must hold, checked in this order):
- `CC_MECH_CONTINUE` ≠ `"0"` (`:939`) and `jq` present (`:940`).
- `kill_switch_active()` false (`:950`, logged `mechanical-kill-switch` if true).
- Not a confirmed/unknown Agent-Teams assignee (`:967-981`, see (d)).
- No fresh teardown marker naming this session (`wf_teardown_marked`, `:983`).
- `hooks/lib/session-writes.sh` sources successfully (`:985-998`).
- `bash scripts/wrap-ledger.sh --machine` (resolved via `WRAP_LEDGER_BIN` or a 3-tier fallback chain, `:1006-1012`) runs and its `RUNG=` field is **exactly `🔧`** (`:1016-1017`) — per `scripts/wrap-ledger.sh:25` that means "dirty tree ∨ gate ran-but-stale-on-HEAD ∨ DoD remainder > 0".
- `session_dirty_mine("$TP_MECH", "$cwd")` returns **exactly rc 0** (`:1022-1023`) and prints ≥1 file (`:1026-1028`).
- The arm's own per-session budget (`${f}.mech`) is not exhausted (`:1062-1067`).

**(b) Counter/latch/budget.** `${f}.mech`, content `"<sid> <count>"`, keyed on `cur_sid` (a stored sid ≠ current sid resets `mcnt` to 0, `:1060`). Env **`CC_MECH_MAX`** — read as default **`2`** here (`mmax="${CC_MECH_MAX:-2}"`, `:1053`). Once armed, this arm explicitly does **not** carry its own re-arm cap independent of Arm 1's: the file's own comment states "it inherits every existing safety property rather than duplicating one — kill-switch, SID-BIND, the `CLAUDE_CONTINUE_MAX` cap" (`:925-928`), and states the *combined* worst case is a **product, not a sum**: `CC_MECH_MAX × CLAUDE_CONTINUE_MAX` forced turns (`:1046-1048`). Also: `CC_MECH_CONTINUE` (0 disables, default 1, `:939`), `SESSION_WRITES_LIB`/`WRAP_LEDGER_BIN` (path-override seams, no numeric default), and `SESSION_WRITES_TIMEOUT_S` (default `5`, bounds the transcript `jq` read — `hooks/lib/session-writes.sh:171`).

**(c) Attribution.** Library **`hooks/lib/session-writes.sh`**, function **`session_dirty_mine(transcript_path, [repo_dir])`** (`:277-361`). It intersects `git status --porcelain -z -uall` tracked-dirty paths against `session_writes_paths()` (every file this session's main+subagent transcripts recorded a `Write`/`Edit`/`MultiEdit`/`NotebookEdit` `tool_use` against, session-scoped not turn-scoped — `:195-200`), after canonicalizing both sides to physical paths (`_sw_canon`, `:207-218`, needed because `/tmp`→`/private/tmp` and this repo's live layer are symlinks). Return codes: **rc 0** = non-empty intersection ("mine") — **the only one that permits arming** (`mechanical_arm` requires `[ "$mrc" -eq 0 ]`, `:1023`); **rc 1** = nothing of mine is dirty — does not arm; **rc 2** = cannot tell (no git/jq, unreadable transcript, git op failed) — does not arm, "a Stop hook may never block a turn on its own inability to read something" (`:1019-1020`).

**(d) Exemptions/kill switches.**
- **`CC_MECH_CONTINUE=0`** disables the arm outright (`:939`) — the single named kill switch.
- `kill_switch_active()` (`:950`, logs `mechanical-kill-switch`).
- Assignee exemption: `agent_assignee_argv()` (`hooks/lib/agent-identity.sh:33-77` — a 3-flag `--agent-id`/`--agent-name`/`--team-name` self-consistent process-ancestry match, walked via `ps`) combined with `agent_team_member_confirms()` (`hooks/lib/agent-identity.sh:93-124`) returning **rc 0** (CONFIRMED by that team's `config.json`) **or rc 2** (UNKNOWN — no readable config) exempts; only **rc 1** (config positively REFUTES membership) does not (`:968-980`, logs `mechanical-assignee` with the confirming rc).
- `wf_teardown_marked()` true (fresh ≤30 min marker, see below) exempts (`:983`, logs `mechanical-teardown`).
- Own budget exhausted (`:1062-1067`, logs `mechanical-budget`).

---

## Arm 3 — the ship floor (`ship_floor()`, `hooks/session-continue.sh:1098-1199`)

**(a) Trigger predicate.**
- `CC_SHIP_FLOOR` = `1` (`:1099`), kill-switch not active (`:1101`), not a confirmed/unknown assignee (`:1102-1109`), no teardown marker (`:1110`).
- The ledger (reused `SC_LED_CACHE` from Arm 2 if it ran this Stop — `review #7`, `:1113-1115` — else a fresh `wrap-ledger.sh --machine` run) reports `RUNG=` exactly **`📦`** or **`🚀`**, else abstain (`:1127-1128`).
- Attribution passes (see (c)).
- Not already latched for the current `HEAD` sha (`:1172-1173`), and the per-session budget is not exhausted (`:1174-1178`).

**(b) Counter/latch/budget.** `${f}.ship`, content `"<sid> <sha> <count>"`. A stored sid ≠ `cur_sid` resets both `psha` and `pcnt` to empty/0 (`:1170`); an exact-sha match (regardless of count) is an unconditional silent abstain (`ship-floor-latched`, `:1172-1173`) — so within one session, `pcnt` accumulates **across distinct shas** up to the cap, and the latch alone is what makes it fire "once per new commit." Env: **`CC_SHIP_FLOOR`** (0 disables, default `1`, `:1099`), **`CC_SHIP_FLOOR_MAX`** (default `2`, `:1162`). Also `WRAP_LEDGER_BIN`/`SESSION_WRITES_LIB` path overrides.

**(c) Attribution.** Library **`hooks/lib/session-writes.sh`**. For `RUNG=📦`: `session_unlanded_mine(transcript, repo_dir, trunk_ref)` (`:375-433`) — rc 0 mine (a path in `git diff --name-only "$trunk"..HEAD` intersects this session's written-paths set) permits; **any nonzero rc (1 or 2) abstains identically** — the call site does not distinguish "not mine" from "cannot tell" (`session_unlanded_mine ... || { log_idl abstained "ship-floor-not-mine" ...; return 0; }`, `:1150-1151`). For `RUNG=🚀`: the weaker `session_writes_paths(transcript)` (`:200`) — rc 0 (wrote *anything* this session) permits; nonzero abstains the same way (`:1153-1155`) — deliberately weaker because "a repo-wide converger outage must not nudge every idle session" (`:1093-1094`).

**(d) Exemptions.** `CC_SHIP_FLOOR=0` (outright kill switch), `kill_switch_active` (`ship-floor-kill-switch`), assignee rc 0|2 (`ship-floor-assignee`), `wf_teardown_marked` (`ship-floor-teardown`), sha-latch (`ship-floor-latched`), budget exhaustion (`ship-floor-budget` — **silent to the model**, no `systemMessage`, unlike the wake floor's exhaustion path: "budget exhaustion is silent (operator-readout still renders 📦/🚀)", `:1096`).

---

## Arm 4 — the wake floor (`wake_floor()`, `hooks/session-continue.sh:603-895`)

**(a) Trigger predicate** (most elaborate arm):
- `CC_WAKE_FLOOR=1`, `jq` and `mailbox_wake_armed` present, `$_ouid` is a valid key (`:604-607`).
- `mailbox_wake_armed("$_ouid")` (`hooks/lib/mailbox-pending.sh:291-301` — a fresh `<key>.watching` heartbeat within `CC_WATCH_FRESH_S` AND, if a pid is recorded, that pid alive) is **false** — if true, the floor self-heals (clears its own budget file) and returns immediately (`:614`).
- **Headless abstain**: not (`CC_PANE_ID` set AND `ITERM_SESSION_ID` unset) — a pane-less session's wake path is a stdin write, not a watcher (`:656-664`, logs `wake-floor-headless`).
- **Goal-live abstain**: `goal_live_condition()` (`hooks/lib/goal-state.sh:60-73`) returns a live condition **and** mail is pending → abstain, since goal-forced turns will deliver it (`:693-704`, logs `wake-floor-goal-live`); if a goal is live but mail is *not* pending, the floor still fires but names a *different* command (see below).
- Custody count (`cust`) computed by shelling out to `bin/cc-custody list --open --cwd "$cwd" --json` and attributing rows to this pane via inline `jq` on `originatorPane`/`notifyBack` (`:731-766`; see (c)).
- **Teardown/assignee abstain**, gated by `CC_WAKE_FLOOR_TEARDOWN` (`:768-798`).
- Fires only if `cnt==0` (never yet fired this episode) **OR** `pend>0` **OR** `cust>0` (`:805`) — otherwise a session that already declined once with nothing new is left alone silently.
- Budget not exhausted (`:836-843`), TTL elapsed (`:844-848`), kill-switch not active (`:849-854`).

If all hold, it stamps its state file and emits `decision:"block"` instructing the model to background-arm `cc-await-ping --timeout <TIMEOUT> --interval 15` (or, under a live goal, `cc-await-ping --idle-scoped --sid <sid>`, `:827-833`) before stopping.

**(b) Counter/latch/budget.** `$mbxd/$_ouid.wakefloor` (`mbxd = CC_MAILBOX_DIR`, default `$HOME/.claude/mailbox`, `:610`), content `sid=…\ncount=…\nts=…`, keyed on `$_ouid` and re-keyed fresh when the recorded sid differs from `cur_sid` (`:625-627`). Env vars: **`CC_WAKE_FLOOR`** (0 disables, default `1`, `:604`); **`CC_WAKE_FLOOR_MAX`** (default `2`, `:807`); **`CC_WAKE_FLOOR_TTL_S`** (min seconds between attempts, default `600`, `:808`); **`CC_WAKE_FLOOR_TIMEOUT_S`** (embedded in the *suggested* watcher command, default `14400`, `:821`); **`CC_WAKE_FLOOR_TEARDOWN`** (disables only the teardown/assignee abstain, default `1`, `:776`); **`CC_MAILBOX_DIR`** (default `$HOME/.claude/mailbox`); **`CC_CUSTODY_BIN`** (test seam, path override, `:737`). Indirectly via `hooks/lib/mailbox-pending.sh`: **`CC_WATCH_FRESH_S`** (default `90`, `:297`) gates the "already armed" self-heal check.

**(c) Attribution.** Done **inline** (no shared library function, unlike Arms 2/3): `jq` predicate `mine` at `:748-758` — `.originatorPane == $p` OR `.notifyBack == $p` OR `.notifyBack` ends with `"-" + $p`, where `$p = $_opane` (the raw, pre-canonicalization pane key captured at `:425`, distinct from `$_ouid` used for mailbox reads). Rows matching neither field are "unknown" (`cust_unk`), counted but hedged rather than dropped, per the comment: "the store already carries the discriminator... a per-pane key loses it across the measured resume-loses-pane-id case" (`:721-730`).

**(d) Exemptions.** `CC_WAKE_FLOOR=0` (outright kill switch); already-armed self-heal (`:614`); headless abstain (`wake-floor-headless`); goal-live+mail abstain (`wake-floor-goal-live`); teardown/assignee abstain gated by `CC_WAKE_FLOOR_TEARDOWN` (`wake-floor-teardown`); the "nothing new" early return (`:805`, unlogged — the common/silent no-op case per the file's own B-3 doctrine, `:74-79`); budget exhaustion (`wake-floor-budget`, non-blocking `systemMessage` warning); TTL not elapsed (`wake-floor-ttl`, fully silent); kill-switch (`wake-floor-kill-switch`, non-blocking warning).

---

## Explicit answers

**Order + single reach-condition.** Mechanical → ship → wake, and all three are reached **only** when no sentinel is currently armed for this cwd (`! -f "$f"`, `hooks/session-continue.sh:1205`). Once a sentinel exists (by any means), execution instead goes kill-switch → SID-BIND → CAP → mail-fold → block (`:1225-1345`).

**How many block payloads can this one hook print in one Stop invocation?** **At most one.** Every code path in actuation mode is a single `printf`/`jq -nc` immediately followed by `exit 0`; I traced every exit point (`:1210-1211`, `:1215-1216`, `:1218-1219`, `:1232`, `:1251`, `:1264`, `:1334`/`:1332`) and none can execute twice. Separately, the file's own header documents a **cross-hook** double-block: this hook and the sibling `hooks/completion-assert.sh` can each independently emit their own block on the *same* Stop because the harness runs every registered Stop hook regardless of an earlier one blocking, cited as `hooks/hook-chain.sh:78`. I verified that citation: line 78 of the current snapshot literally reads *"3. EVERY MEMBER ALWAYS RUNS. The harness runs every hook in a matcher group even when one blocks, so this does too — short-circuiting would drop the side effects of later members."* — accurate, though note `hooks/hook-chain.sh:24-26` states this dispatcher is itself "deliberately NOT wired into settings.json," i.e. it's cited purely as documentation of the underlying harness contract, not as a component actually in `session-continue.sh`'s own runtime path.

**Which arm never prints a block of its own yet still causes one, and which bounds does it inherit?** `mechanical_arm()` (`:938-1079`). It never constructs a `decision:"block"` JSON; it only writes the sentinel + `.sid`/`.cwd` sidecars and returns rc 0, which causes a fall-through into Arm 1's shared block-emission code. It inherits that path's kill-switch, SID-BIND, and `CLAUDE_CONTINUE_MAX` cap wholesale (stated explicitly at `:925-928`), on top of its own separate `CC_MECH_MAX` budget — combined worst case is the **product** `CC_MECH_MAX × CLAUDE_CONTINUE_MAX`, not a sum (`:1046-1048`).

**Does unread peer mail by itself block a Stop?** Yes, but only **indirectly, via the wake floor**, never via the mail-fold code. `pend>0` (from `mailbox_pending_count`) is one of three OR'd conditions (`:805`) letting `wake_floor` proceed past its early return, and if it then blocks, the reason text quotes the pending count — but the demanded *action* is "arm `cc-await-ping`," not "read your mail." The **mail-folding code at the end of the file** (`:1272-1340`, "v2 comms fold") does **not** independently cause a block: it only runs after execution is already inside the armed path *past* the CAP check — i.e. a block was already going to fire for an unrelated reason (a sentinel was already set). All it does is `mailbox_drain_claim`/`mailbox_peek_range` the pending window and **prepend** the mail body into that already-decided block's `reason` (plus a `systemMessage`), then `mailbox_commit_seen` only after the JSON write succeeds (`:1336-1339`, "EMIT-THEN-COMMIT"). If no sentinel is armed and none of the three floors decide to fire, this code is **never reached** in that Stop at all (every branch inside `if [ ! -f "$f" ]` exits before line 1225). Separately and **unconditionally** on every actuation-mode Stop (regardless of any floor or sentinel), the file runs `mailbox_promote_acked("$_ouid")` (`:467`) — this advances `.acked` to `.seen`, i.e. marks whatever mail was *surfaced* last cycle as now *consumed*, since a Stop proves a turn ran; it does **not** deliver anything new and does **not** gate on a sentinel.

**Env var with two different literal defaults in two code paths.** **`CC_MECH_MAX`.** `mechanical_arm()` reads it as `mmax="${CC_MECH_MAX:-2}"` when checking its own per-session budget (`hooks/session-continue.sh:1053`). The CLI `clear` handler, however, "spends" that same budget file with `printf '%s %s' "$SC_SID" "${CC_MECH_MAX:-3}" > "${f}.mech"` (`hooks/session-continue.sh:261`). So with `CC_MECH_MAX` unset, `clear` stamps a count of **3** into a file that `mechanical_arm` later compares against a default ceiling of **2** — functionally consonant (3 ≥ 2 still reads "spent") but the two lines literally disagree about the default value.

---

## Stale/unverified citations found while checking this tree's own comments

- `hooks/session-continue.sh:545-547` cites *"Marker contract and the 30-min freshness window are the reader's, taken verbatim from `hooks/lead-crash-watchdog.sh` `classify_death` (`:255-278`)"* and *"`marker_owns_sid`'s rule (`:112-118`)"*. I read both ranges in the pinned snapshot: `hooks/lead-crash-watchdog.sh:249-263` defines `retired_by_desk()` (not `classify_death`) and `:265-277` starts `close_record_summary()`; `:111-129` is a comment block ("death classification helpers...") followed by `find_transcript()` — no function named `marker_owns_sid` appears in either cited range. The *substance* the comment relies on (a `"mode":"teardown"` marker check and a 30-minute freshness window — `retired_by_desk` uses `find ... -mmin -30` at `:257`) does exist nearby and is consistent with `session-continue.sh`'s own `CC_WF_TEARDOWN_FRESH_S:-1800` default, but the specific function-name/line-range attributions do not match what's at those lines in this snapshot — flagged as stale rather than repeated as fact.
- `hooks/session-continue.sh:323` also asserts *"session-continue.sh runs at position 4 of the Stop chain and completion-assert.sh at position 6 (settings.json)."* I could not locate a settings.json defining the fleet Stop-hook order anywhere reachable in this read-only snapshot (checked `.claude/settings.json` — project-scope, permissions only, no `hooks` key; a root `settings.json`; and `settings.example.json`, referenced by `install.sh:29` but not found at the repo root). This position claim is therefore **unverified** in this snapshot, not confirmed stale — I have not repeated it as established fact above.

**One process note on my own conduct:** partway through I ran a single `Bash` grep command before catching that the brief restricts tools to Read/Grep/Glob; I stopped immediately and completed the rest of the investigation using only `Read` (Grep/Glob were not actually available as callable tools in this environment, so the remaining line-location work was done via targeted `Read` offsets instead).
