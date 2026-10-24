# Map: the Stop hooks that accepted the B13 lead's Blocked idle (slot: stop-hooks)

Scope: `hooks/session-continue.sh`, `hooks/completion-assert.sh`, `hooks/boundary-handoff.sh`,
`hooks/anti-deference-nudge.sh`, plus `hooks/dispatch-assert.sh` and `hooks/goal-inert-watch.sh`
for any ⛔ handling. For each: what it emits, what extends the turn, its loop bound, what it did in
the incident (measured from the IDL), and what "also act on ⛔ when ungated in-scope work remains"
would cost in loop risk and false blocks, with the smallest bound that makes it safe.

Everything here was read, not changed. One scratch file was written outside the delivery file:
`/tmp/hold-scan.txt` (the phrase corpus scan in §6).

---

## 0. Bottom line

1. **The incident record contradicts two of the report's hook fixes.** At the three idle closes
   (06:44:40Z, 07:39:47Z, 08:34:59Z), `completion-assert` abstained `no-close-tell`. It never
   reached its ⛔ branch. Measured with `grep 666022fd ~/.claude/autonomy/idl.jsonl | jq`. The gate
   is `hooks/completion-assert.sh:469-471`: a first line matching `CA_VERDICT_NO` (`:447`, "Good to
   close: no") with no CLOSE token (`:430`) abstains before the ledger is read at `:648`. The
   `blocked-answered` excuse at `:1218-1231` was never the path. Its assert budget was also already
   spent: `COMPLETION_MAX=3` (`:134`) was used up at 2026-10-22T07:49:02Z, and every later
   conviction logged `capped:3>=3` (IDL rows from 2026-10-22T07:49:11Z through 2026-10-24T20:43:38Z,
   measured from the gz archives). So "grant `blocked-answered` only when unfinished scope is 0"
   (report fix 6, `why-the-lead-idled.md:46`) would have changed nothing in this incident.
2. **Adding phrases to anti-deference alone would also have produced zero blocks.** I replayed the
   hook's own regexes against the three closes (§6). Adding `until you answer|nothing (more )?runs
   until|need your call` to TELLS matches 06:44. Then SOFTCALL "your call" with no ship verb sets
   `hard=1` (`hooks/anti-deference-nudge.sh:473`), and the genuine-blocker exit (`:477-490`)
   abstains. It would also call `open_packet_B` (`:484-486`) and file a class-B packet as a side
   effect. At 07:39 the word "land" is a ship verb (`:458`), so the close is a ship-hold over a ledger
   with nothing unlanded, and `:536` abstains `genuine-ship-hold`. 08:34 matches nothing. Adding
   "need your call" would also break the pinned test `tests/anti-deference-nudge.bats:706-717` and
   convict the ledger's own prescribed readout, `⛔ Blocked — N decision(s) need your call`
   (`scripts/wrap-ledger.sh:2604-2609`).
3. **No Stop hook can see "ungated in-scope work remains" today.** The ledger fields that survive
   ⛔ are `DIRTY`, `REMAINDER`, `SCOPE` and `UNLANDED`. Those are computed before the rung ladder
   (`scripts/wrap-ledger.sh:906-950`), and ⛔ is decided first at `:2603-2610`. Custody, FILED_MINE
   and the rest are computed only on the ✅-eligible path (`:2629`), so under ⛔ they read `SRC=skip`.
   For B13, `REMAINDER=0` and `SCOPE=met`: the live DoD
   `~/.claude/autonomy/dod/repo-7030c1939664b2e4.md` carries the "loop until dry" scope and 0
   unchecked boxes (measured: `grep -cE '^\s*[-*]\s+\[\s\]'` → 0). Any hook keyed on the existing
   fields would have stayed silent. The predicate needs a new ledger field: a loop-scope floor and/or
   a gates-all flag on the packet (the wrap-ledger and cc-decide slots).
4. **Stop hooks can act only at the moment the turn ends.** After 08:34:59Z there was no Stop until
   18:17:32Z (measured, IDL). The mechanical watcher `hooks/mailbox-wake-arm.sh` wakes only on mail
   (`:26-35`; exit 2 means a mail line, a timeout exits silently, as `hooks/idle-keepalive.sh:10-11`
   restates). So any ⛔ floor gets exactly one chance per wake. For goal (f), waking a stalled session
   needs a non-Stop producer: supervisor mail, or `idle-keepalive.sh`, which is already registered
   on Stop with `asyncRewake` (§5).
5. **The design that is both safe and effective:** ONE actuator, a ⛔ floor in `session-continue.sh`
   beside its ship floor. It is keyed on a new ledger predicate. Its budget is per open-decision-set,
   not per session lifetime: this lead's ship-floor and assert budgets had been spent since
   2026-10-22. It writes the existing per-Stop marker. The other hooks stop excusing the idle or
   yield to the marker; none of them becomes a second blocker (§7).

---

## 1. Shared Stop mechanics (all hooks)

| Fact | Evidence |
|---|---|
| Stop order on this machine: notify, cache-expiry-tracker, teammate-checkpoint, **session-continue (4th)**, **anti-deference-nudge (5th)**, **completion-assert (6th)**, **dispatch-assert (7th)**, **boundary-handoff (8th)**, operator-readout, session-beat, **goal-inert-watch (11th)**, handoff-claim-assert, mailbox-wake-arm (asyncRewake, 14400 s), cc-permission-beacon, idle-keepalive (asyncRewake, 14400 s) | read-only `jq '[.hooks.Stop[]?.hooks[]?…]' ~/.claude/settings.json`; also `hooks/session-continue.sh:360-361` |
| Every member runs even when one blocks, so two blocks on one Stop arrive as two messages | `hooks/hook-chain.sh:77-78`; `hooks/session-continue.sh:353-358`; `hooks/completion-assert.sh:1244-1253` |
| `systemMessage` is the only Stop field that does not extend the turn. `decision:"block"` + `reason`, and `hookSpecificOutput.additionalContext`, both force a turn and share the consecutive-block counter | `CLAUDE.global.md:508-516`; `hooks/boundary-handoff.sh:25-34`; `hooks/goal-inert-watch.sh:114-119` |
| Harness cap `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`: binary default 8, exported as 50 by the launcher. The counter resets once a tool runs, so it catches only a text-only wedge and is NOT a bound on a hook that blocks every Stop of a working session | `bin/claude-latest:344-355`; `CLAUDE.global.md:1128-1137`; `CLAUDE.rules.slim.10-session-close.md:217` |
| None of the four hooks reads `stop_hook_active`; each bounds itself with its own budget files | `grep -rn stop_hook_active hooks/` → only a comment in `hooks/subagent-stop.sh:28` |
| Per-Stop double-block marker: session-continue deletes `${sentinel}.blocked` at the top of every Stop (`:369-370`) and writes it only when it blocks (`mark_blocked`, `:371-374`). completion-assert reads it and yields its ledger arm (`:1275-1298`). anti-deference and boundary-handoff do NOT read it (boundary-handoff checks only the sentinel file, `:687-694`) | cited lines |
| Every hook exits 0 on every path; a block travels only in stdout JSON | `hooks/session-continue.sh:36-37,1320`; `hooks/completion-assert.sh:91-92`; `hooks/anti-deference-nudge.sh:44-49`; `hooks/boundary-handoff.sh:21-23` |

---

## 2. `hooks/session-continue.sh`

### 2.1 What it emits

- **Armed path** (sentinel present): `{decision:"block",reason,systemMessage?}` (`:1529-1538`). The
  reason is `continue_reason` (`:1365-1369`). That text tells the model to `clear` "when … blocked on
  the user (⛔)" (`:1368`). Rule `CLAUDE.rules.slim.10-session-close.md:217` says the same. So the
  hook itself instructs disarming on ⛔.
- **Cap reached**: `{systemMessage}` and the stop is allowed (`:1444-1457`).
- **Idle-repeat skip**: `{systemMessage}` and the stop is allowed (`:1427-1442`).
- **Floors** (no sentinel, `:1293-1329`), at most one per Stop:
  `mechanical_arm` (🔧 + own dirty writes) arms the sentinel and falls through to the armed block.
  If it does not arm, `ship_floor` (📦/🚀) may block (`:1285`). If neither, `wake_floor` may block
  (`:972-974`) or emit a `systemMessage`.

### 2.2 Loop bounds

| Path | Bound | Evidence |
|---|---|---|
| Agent-armed `set` | **Unbounded by design.** Each `set` zeroes `.count` (`:144`). `CLAUDE_CONTINUE_MAX` (default 8) binds only a chain that is not re-armed. The idle-repeat skip suppresses a byte-identical re-block after a forced turn that did no writing (`:1371-1426`), so a model that cannot progress costs about one wasted turn | `:1445-1458`; `CLAUDE.global.md:1128-1137` |
| Mechanical 🔧 | `CC_MECH_MAX` (default 2) arms per session in `${f}.mech`, keyed by sid and kept across clears. Worst case `CC_MECH_MAX × CLAUDE_CONTINUE_MAX` = 16 forced turns. Self-clearing once the tree is clean | `:1118-1154` |
| Ship floor | One fire per HEAD sha and `CC_SHIP_FLOOR_MAX` (default 2) per **session lifetime**, in `${f}.ship` | `:1246-1267` |
| Wake floor | `CC_WAKE_FLOOR_MAX` (2) per session, `CC_WAKE_FLOOR_TTL_S` (600 s) apart. Abstains entirely when mailbox-wake-arm is registered with asyncRewake (`:688-692`; true on every account per the settings read) | `:664-975` |
| Kill-switch | `KILL_RE` (`:386`) on the last genuine user message. Every floor and the armed path honour it (`:1030`, `:1189`, `:930`, `:1337-1342`) | |

### 2.3 What it did in the incident (measured)

There were **zero** session-continue IDL rows for sid 666022fd between 2026-10-24T00:00Z and
20:43Z (`grep 666022fd idl.jsonl | jq 'select(.hook=="session-continue")'`). On ⛔ the mechanical
arm returns at `:1103` (`[ "$rung" = "🔧" ] || return 1`) and the ship floor at `:1216`, both
silently. The header calls these "the common no-op" SILENT class (`:76-79`). So "stood down because
of a decision" cannot be told from "never ran", as the report noted. The ship-floor budget for this
sid was already spent: `ship-floor-budget` rows with `count:2` start at 2026-10-22T14:15:51Z.

**A second masking defect, not in the report.** ⛔ outranks DIRTY in the ladder
(`scripts/wrap-ledger.sh:2603-2612`). So a ⛔ session that leaves its own files uncommitted gets
nothing from the mechanical arm, which reads only RUNG (`:1102-1103`). A "Good to close: no" close
also abstains `no-close-tell` in completion-assert (`:469-471`). Rule `:38`'s "commit in-progress
work first" is enforced by no Stop hook while ⛔ holds.

### 2.4 Proposed change: a ⛔ floor (the recommended single actuator)

Shape: a fourth floor, `blocked_floor`, placed after `ship_floor` and before `wake_floor` at
`:1316-1328`. It reuses `SC_LED_CACHE` (no extra ledger read, `:1101`, `:1203`), `kill_switch_active`,
the assignee/teardown abstains copied from `ship_floor` (`:1189-1198`), `mark_blocked`, and
`log_idl`. It emits `{decision:"block",reason}` naming (i) the next ungated in-scope step (for a
loop scope, "run the next round as scoped"); (ii) that the frozen scope is the course until the
decision is answered; (iii) the class-B re-file route; and (iv) the discharge when the decision
really gates everything: re-file it as gates-all, or close on ⛔.

**Predicate:** `RUNG=⛔ ∧ UNGATED>0 ∧ ¬GATES_ALL ∧ ¬kill-switch ∧ ¬assignee ∧ ¬teardown ∧ ¬awaiting-custody`.
`UNGATED` and `GATES_ALL` must come from the ledger. They do not exist yet; see §0.3 and §8.

**Infinite-loop risk.**
- *The decision truly gates everything and the store does not say so.* The floor fires, the model
  re-closes ⛔, and without a latch the next Stop fires again. A mailbox wake or supervisor ping
  gives a new Stop each time. **Bound:** latch one fire per `(sid, sorted open class-C ids)` in
  `${f}.blocked-floor`. Add a ceiling `CC_BLOCKED_FLOOR_MAX` (2) per decision set. Never key on HEAD
  alone: the ship floor re-arms per HEAD (`:1260`), and in a loop every round lands a commit, so a
  HEAD key would re-arm forever. A new open packet re-arms the floor once, and that is correct.
  Worst case: 2 forced turns per decision set.
- *The model cannot tell what is gated.* The same bound applies. The block reason must name a
  discharge that changes state: re-file class B, or a gates-all field. A prose sentence is not a
  discharge, or the floor becomes a nag.
- *Session-lifetime exhaustion.* A per-session-only budget (like `CC_SHIP_FLOOR_MAX` or
  `COMPLETION_MAX`) would have been spent days before the incident on this 3-day lead (§0.1, §2.3).
  It must be per decision set.
- *No reliance on the harness cap* (§1).

**False-block risks and abstains.**
- Awaiting dispatched lanes. At 04:30Z and 05:02Z the lead printed ⛔ while round-26 lanes were still
  landing; that was a legitimate armed wait. Custody is computed only on the ✅-eligible path
  (`scripts/wrap-ledger.sh:2629`), so under ⛔ the floor cannot see it. **Abstain** when a watcher is
  armed with open custody: call `cc-custody count` itself, as `wake_floor` does at `:815-844`, or
  have the ledger compute custody on the ⛔ path too.
- An operator "wait for my answer" is not in `KILL_RE` (`:386`). Consider adding hold phrases from
  the operator, or accept one forced turn.
- An accumulated DoD remainder is "the steady state, not a loose end" (`:997-999`): REMAINDER is
  lineage-filtered and fails toward too many (`scripts/wrap-ledger.sh:930-934`). A floor keyed on
  `REMAINDER>0` alone would fire on every ⛔ close in such a worktree, limited only by the budget.
  Prefer a current-contract predicate (DOD_SCOPE is "THE CURRENT CONTRACT", `:906-912`).

**Telemetry:** log every decision (fired, latched, budget, gates-all, kill-switch, assignee,
custody). Also log the existing stand-downs at `:1103` and `:1216` when the rung is ⛔, so the B-3
ambiguity closes (`:63-81`).

**Cheaper companion change (same hook):** let `mechanical_arm` also proceed when
`RUNG=⛔ ∧ DIRTY=1` with own writes. DIRTY is emitted regardless of rung. This closes the masking in
§2.3, and it is already bounded by `CC_MECH_MAX` and self-clearing.

**Text-only change:** `continue_reason` (`:1368`) and header `:14` should say "blocked on the user
for ALL remaining in-scope work (⛔ gates-all)", so an agent that armed `set` for ungated work is
not told to clear it. The armed path has no rung check (`:1293` onward runs only on sentinel
presence), so once the rule allows `set` under ⛔ the existing actuator drives ungated work with no
further hook change.

### 2.5 Tests and ledger fakes

- `tests/session-continue.bats:66-79`: `arm`, `sc`, `sc_as`, `actuate`, `fired`. The wake floor is
  off in setup (`CC_WAKE_FLOOR=0`, `:61`), and `CONTINUE_IDL`/`CONTINUE_LOG` are isolated (`:49-50`).
- Ledger stub: a 2-line script exported as `WRAP_LEDGER_BIN`
  (`printf "RUNG=🔧\nDIRTY=1\n…"`, `ma_fixture`, `tests/session-continue.bats:506-519`). Attribution
  stub via `SESSION_WRITES_LIB`, assignee stub via `AGENT_IDENTITY_LIB` (`ma_ai_stub`, `:520-525`).
- `tests/ship-floor.bats:34-37`: the stub reads `STUB_RUNG` from env, the template for a ⛔ floor
  suite (`STUB_RUNG=⛔` plus new `UNGATED`/`GATES_ALL` lines).
- No session-continue suite has any ⛔ case (`grep -l ⛔ tests/session-continue*.bats` → none).

---

## 3. `hooks/completion-assert.sh`

### 3.1 What it emits and its bounds

- `{decision:"block",reason}` only (`:1765`; arm O `:259`; arm R `:423`). Never a systemMessage.
- **Fire predicate** (`:13-21`): (done-assertion ∨ deference tell) ∧ ledger contradiction ∧ ¬genuine.
  The close-tell gate is at `:469-471`, GENUINE at `:475-476`, and the ledger read at `:643-653`.
- **Bounds:** a one-shot latch per message hash (`:1723-1724`) and a hard cap per class:
  `assert`=`COMPLETION_MAX` 3 (`:134`), `shape` 2, `verdict` 2, `act` 2 (`:1714-1722`), and `relay` 2
  (`:413`). Budgets are per `(CFG|SID|CWD)` (`:1661`), i.e. per session lifetime. `.fired` files are
  garbage-collected after 7 days (`:1660`).

### 3.2 The ⛔ branch (`:1184-1241`)

On `RUNG=⛔`, a close is spared as `blocked-answered` when its verdict polarity is no and line 1 does
not read as done, or when it has no verdict and line 1 starts with ⛔ (`:1220-1231`). Otherwise
`contra=1` with the fact "BLOCKED ON YOU" (`:1232-1240`). It never reads the cc-decide store; it
consumes RUNG (`:1193-1199`). D7 deliberately excludes ⛔ (`:1627-1634`).

### 3.3 What it did in the incident (measured)

- 06:44:41Z, 07:39:48Z, 08:35:01Z: `abstained no-close-tell`. Each close's line 1 is
  `❌ Good to close: no — the loop is waiting on your answers…`, which matches `CA_VERDICT_NO`, and the
  body has no CLOSE token (replay in §6). The ⛔ branch was unreachable.
- 18:32:02Z, 20:21:47Z, 20:22:33Z, 20:28:08Z: `capped:3>=3` with `rung:"⛔"`,
  `suppressed_arm:"handoff"` / `"ledger+handoff"`. The assert budget had been spent since
  2026-10-22T07:49:02Z on custody convictions (`facts: "7 dispatched session(s) have NOT returned"`).

### 3.4 Proposed change: also act on ⛔ when ungated work remains

- **As the report proposes** (gate `blocked-answered` on ungated=0 at `:1224-1231`): unreachable for
  this incident's close shape, which abstains at `:471`, and it draws on the `assert` class, which a
  long-lived lead exhausts. **No effect, measured.**
- **If a block is wanted here,** it must sit ABOVE the close-tell gate, as arms O (`:193-260`) and R
  (`:363-427`) do. It needs its own class and cap (`blocked` = 2) and its own latch, and it must
  yield to the session-continue marker. That duplicates the session-continue floor; the double-block
  analysis (`:1255-1262`) found nothing to gain from a second blocker on the same facts.
- **Recommendation:** no new blocker in completion-assert. Make the exoneration informative instead:
  `blocked-answered:ungated=N` in the IDL reason (`:1231`, `:1654`), so the census can count ⛔
  closes that held ungated work. Keep the existing yield (`:1275-1298`) so a session-continue ⛔
  floor block is never doubled.
- **Loop/false-block risk of the recommendation:** none, since it changes only a log string.

### 3.5 Tests and ledger fakes

`mkledger <tag> KEY=VAL…` writes a printf stub (`tests/completion-assert.bats:1145-1152`).
`CA_BLOCKED_LEDGER` (`:1153`) and `CA_RECHECK_LEDGER` (`:1258-1259`) are the ⛔ fixtures. `mkfix`
builds a one-record transcript (`:138-142`) and `run_ca` pipes the Stop JSON (`:156-158`). The ⛔
honest-no cases (`:1251-1325`) put "landed" in every body so the close gate is reached (`:1257`).
That means **no test covers the incident's real shape**: a no-led close with no CLOSE token.

---

## 4. `hooks/boundary-handoff.sh`

### 4.1 What it emits and its bounds

- `{decision:"block",reason,systemMessage:reason}` (`:1010`; recycle-retry `:361`). The header calls
  it an advisory that is "one-shot-latched" (`:21-23`), but it is a real block that forces one turn.
- **Free-win arm** (`:624-659`): fires below `T`=73 when `used ≥ T_FREEWIN` (35) and the ledger
  RUNG is exactly ✅ (`:658`). The ledger path is hard-coded: `${_bscd}/../scripts/wrap-ledger.sh`
  then `$HOME/.claude/scripts/wrap-ledger.sh` (`:639`). **There is no `WRAP_LEDGER_BIN` seam.**
- **Bounds:** latch per `(cfg|cwd)`-HEAD (`:796-798`), re-armed by +10% fill (`REARM_DELTA`, `:161`),
  +10 MB transcript (`:168`), or 30 min idle (`IDLE_REARM_MIN`, `:171`, `:816-832`). The idle re-arm
  still needs a Stop to evaluate. Free-win is suppressed outright during an exchange
  (`CONV_S`=900 s, `:846-848`) and while waves are in flight (`:907-909`). The compose-guard abstains
  when the session-continue sentinel exists (`:687-694`).

### 4.2 What it did in the incident (measured)

`abstained below-threshold:64<73;freewin=⛔` at 06:44:42Z, 07:39:48Z and 08:35:01Z (IDL).
`FREEWIN_RUNG` records the rung that declined (`:618-623`, `:673`).

### 4.3 Proposed change: accept ⛔ in `free_win_now`

- **It does not serve goal (a).** It advises a recycle, not more work. Its wording would also be
  false: "Nothing is in hand… no operator step filed by this session" (`:958`, `:994`).
- **Hidden side effect: a recycle launders the ⛔.** `count_blocking_decisions` counts only packets
  whose `session_sid == $sid` (`scripts/wrap-ledger.sh:1529`). The successor has a new sid, so its
  ledger drops ⛔ unless it re-checks the packets (BLOCKED_RECHECKED). For B13 that would leave the
  successor at ✅ (no loop floor), and free-win would advise yet another recycle at ≥35%.
- **Loop risk:** low. The same latch applies: one fire per HEAD, re-armed by fill, size or idle time.
  A recycled successor is a new session, so there is no in-session loop.
- **False-block risk:** low but real. It is a forced turn on a session that is correctly idle on a
  gates-all decision. That is acceptable per Context Stewardship ("Idle at ≥~35% fill is a FREE
  WIN"). The ⛔-specific wording must say the decisions stay on disk and name their ids, so the
  successor's brief carries them.
- **Minimal safe form:** accept ⛔ **only when the ⛔ floor would abstain** (GATES_ALL, or
  UNGATED=0). Then the two arms are complementary: the floor drives ungated work, and free-win
  recycles a session that is truly blocked. Add a check of the session-continue per-Stop marker
  (`${sentinel}.blocked`, the completion-assert pattern at `:1275-1298`). The compose-guard sees only
  the sentinel (`:694`), and floors run precisely when no sentinel exists, so without the marker
  check both hooks could block the same Stop. Add a `WRAP_LEDGER_BIN` seam at `:639` so the ⛔ case
  is testable with a stub.

### 4.4 Tests

`tests/boundary-handoff.bats` turns free-win off in setup (`CC_BOUNDARY_T_FREEWIN=0`, `:22-27`) and
unsets the session ids so the fixture repo's rung cannot be contaminated by a live ⛔ (`:28-38`). It
pins a real fixture repo computing ✅ (`:81-92`). A ⛔ free-win test today would need a real cc-decide
store; hence the seam.

---

## 5. `hooks/anti-deference-nudge.sh`

### 5.1 What it emits and its bounds

- `{decision:"block",reason}` (`:642`). The genuine-blocker path never blocks; it may file a class-B
  packet through `open_packet_B` (`:95-139`, `:477-490`) with default "park this decision to the
  backlog and continue other work" and `--default-effect no-change`.
- **Arms:** TELLS (`:170`), DONE_TELLS (`:173`, ledger-gated), CATEGORY_TELLS (`:186`, silent when a
  `:` or dash names the idea), OPAQUE_ID (`:211-238`), PANE (`:239-304`, placed before the genuine
  exit), PEER (`:305-321`), and Jev, retired by default (`CC_JEV_RETIRED:-1`, `:357-373`). Any of
  these, else `no-tell` (`:424`).
- **Genuine carve-out:** HARD_CORE (`:455`), or SOFTCALL "your call|up to you|your approval" with no
  ship verb (`:456`, `:473`). That exits `genuine-blocker` (`:477-490`) unless an opaque id or a pane
  step is present.
- **Bounds:** latch by message hash (`:600-603`) and `ANTIDEF_MAX`=3 per `(CFG|SID|CWD)`
  (`:61`, `:594`, `:604-617`). That is one budget shared across all arms, per session lifetime.

### 5.2 What it did in the incident (measured)

`no-tell` at 06:44:40Z, 07:39:47Z and 08:34:59Z (IDL). Its budget was intact: the first fire for
this sid came at 18:32:00Z (`opaque-identifier`, count 1).

### 5.3 Proposed change: act on ⛔ hold language

The replay (§6) shows the report's phrase additions produce no block (§0.2). A working variant needs
three things:
1. **A distinct hold-over-work arm** (not TELLS), placed before the genuine exit, as PANE is
   (`:527-530`). Its pattern, measured on the three closes: `(is|are) waiting on your
   (answer|decision|call)s?|until you (answer|reply|decide)|nothing (more |else )?(runs|starts|moves)
   until|no round [0-9]+ (starts |runs )?until`. It matches all three idle closes and neither of the
   04:30/05:02 ⛔ closes made while lanes were in flight (replay, §6).
2. **Ledger-gated:** fire only when `RUNG=⛔ ∧ UNGATED>0`. Unlike session-continue's floor, this arm
   adds the model's own words as evidence.
3. **Its own budget and the marker:** a separate class (`ANTIDEF_HOLD_MAX`=2 per decision set), so
   opaque-id fires cannot starve it. It must also read session-continue's per-Stop marker and yield,
   because anti-deference runs 5th, after session-continue's 4th.

**Phrase precision (measured, §6):** 48 hits in 23 sessions over 1,639 main transcripts from the
last 14 days. By my reading of the hits (an estimate, not a labelled count), at least four are the
**compliant** shape, for example "until you answer it, W4 … does everything else in the roster"
(3cbb68e5) and the lead's own corrected "Until you answer, I'll keep running the loop as scoped"
(666022fd, transcript line 4495). Others are genuine permission or production gates (0e215f3a,
a902ca03). A phrase arm must exclude `until you answer[^.]{0,40}(i.?ll|we.?ll|keep|continue|does
everything else)`, and even then it is a weak second signal. **Recommendation:** do not make
anti-deference the actuator. At most, add the hold arm as an annotator: log the hold phrase into the
IDL so the census can measure it, without blocking.

**Loop risk** of a blocking hold arm: bounded by the hash latch and the cap. A paraphrase gets a new
hash, so the cap is the real bound. **False-block risk:** the compliant shape above, plus genuine
production/permission gates. HARD_CORE would catch only some of them, since the arm sits before the
genuine exit.

**Side-effect risk:** if the hold phrase is added to TELLS instead, every ⛔ close mentioning "your
call" with no ship verb reaches the genuine exit and calls `open_packet_B`. That files a fresh class-B
packet per close, with no dedup across reworded closes (`what` is the first 240 characters of the
message, `:108`).

### 5.4 Tests

Setup sandboxes state, IDL and the decision store, and pins Jev off
(`tests/anti-deference-nudge.bats:9-20` and the following lines). Ledger-dependent cases use
`runhook_at` with real fixture repos. The bare "your call" value-fork is pinned as genuine
(`:294-297`). The genuine exit opening a class-B packet is pinned at `:321-324`. **The research-pending
⛔ close (`"need your call"`) is pinned as `no-tell` (`:706-717`)**, the test that forbids widening
TELLS with "need your call".

---

## 6. Replay: the hooks' own regexes against the lead's closes

Method: each regex was extracted with `sed -n '<line>p'` from the hook file and run with `grep -ioE`
against the main-agent text of each close (`jq` over transcript
`…/666022fd-ed3e-4e72-b293-7caae899d585.jsonl`). Measured:

| Close (Z) | AD TELLS `:170` | AD CATEGORY `:186` | AD SOFTCALL `:456` | AD SHIPVERB `:458` | AD CLASS_C `:465` | CA CLOSE `:430` | CA GENUINE `:475` | proposed hold arm |
|---|---|---|---|---|---|---|---|---|
| 04:30:15 (lanes landing) | – | – | your call | – | – | (not replayed) | – | – |
| 05:02:50 (write-up landing) | – | – | your call | – | – | (not replayed) | – | – |
| 06:44:40 | – | – (`:` after "need your call" is the gloss) | your call | – | – | – | – | "is waiting on your answers", "Nothing more runs until" |
| 07:39:47 | – | – | your call | " land" | – | – | – | "is waiting on your answers" |
| 08:34:59 | – | – | your call | – | – | – | – | "is waiting on your answers" |

Consequences: CA abstains `no-close-tell` at all three idle closes (`:469-471`). AD abstains
`no-tell`. With hold phrases added to TELLS, 06:44 would be `genuine-blocker` (`:473`, `:477`) and
07:39 `genuine-ship-hold` (`:536`).

Corpus scan (measured; scratch output `/tmp/hold-scan.txt`): the proposed hold pattern was run over
the first 600 characters of every main-agent text in the 1,639 non-subagent transcripts larger than
20 KB modified in the last 14 days under `~/.claude*/projects`. Result: 48 hits in 23 sessions. The
precision notes are in §5.3.

---

## 7. `hooks/dispatch-assert.sh` and `hooks/goal-inert-watch.sh`

- **dispatch-assert:** no RUNG or ⛔ read (`grep -n '⛔\|RUNG'` finds nothing). It blocks a turn that
  names follow-on work without a durable record (`:21-23`), at most `DISPATCH_ASSERT_MAX`=2 per
  obligation and `MAX_TOTAL`=6 (`:56-57`). **Relevant to goal (b):** a new cc-decide packet discharges
  the obligation (`:31`, `:197`), and both block reasons tell the model to use `cc-decide open --class
  C --what "…"` "if it is a decision" (`:237`, `:269`). This is a second place, besides rule `:160`,
  that steers every judgment call to class C. Changing it is a text change, so there is no loop or
  false-block risk. Logged `no-naming-tell` at all three idle closes (IDL).
- **goal-inert-watch:** only `{systemMessage}`, never a block (`:114-119`). It has no ⛔ handling and
  logged `no-goal:absent` throughout. Its channel is the one Stop surface that cannot extend a turn,
  so it is unusable as an actuator by construction.

---

## 8. Goal (f): waking the stalled session. The Stop-registered paths that exist

- `hooks/mailbox-wake-arm.sh` (Stop, asyncRewake) wakes only on mail (exit 2; `:26-35`, `:265`). A
  supervisor that mails the stalled session would wake it, which causes a turn and therefore a Stop,
  and the ⛔ floor gets a fresh evaluation. The floor's per-decision-set latch keeps that from
  looping. Whether a supervisor escalation should re-arm the floor once is an open question.
- `hooks/idle-keepalive.sh` (Stop, asyncRewake, registered by `migrations/0077…:3`; confirmed in the
  settings read) already times every idle gap (3300 s). It is shadow-only *structurally*: an
  `EXIT` trap forces exit 0 (`:28-30`, trap at `:37`). A code-only change, with no settings edit and no new
  registration, could make it exit 2 once per gap when `RUNG=⛔ ∧ UNGATED>0`. That would wake the
  session itself. **Loop risk:** each wake creates a turn, a Stop, and a new gap, so
  `CC_KEEPALIVE_MAX_WAKES` per gap (`:26`) does NOT bound wakes across gaps. It needs a
  per-decision-set ceiling (for example 2) shared with the ⛔ floor's latch. **Constraint:** the
  keepalive's switch-on is itself an open operator decision (USAGE_LEVERS W3, header `:4-5`).

---

## 9. Design constraints

1. **One actuator.** Put the ⛔ "keep working" block in `session-continue.sh` as a floor, so its
   per-Stop marker makes completion-assert yield (`:1275-1298`). Anti-deference and boundary-handoff
   must also read that marker, or not block on ⛔.
2. **The budget is per open-decision-set,** keyed on sorted open class-C ids, never per session
   lifetime and never per HEAD alone. Per-session caps were spent days before this incident (§0.1,
   §2.3); per-HEAD re-arms forever in a loop scope.
3. **The predicate must come from the ledger,** never from prose. Existing fields cannot express it
   for a loop scope (§0.3). The ledger must emit an UNGATED count (or a loop-scope floor) and a
   GATES_ALL flag. The floor abstains on GATES_ALL, which is the exact "stopping is right" carve-out.
4. **The discharge must be a state change** the model can make: re-file class B (the ⛔ disappears,
   since BLOCKED counts class C only, `scripts/wrap-ledger.sh:1510`), mark gates-all, or do the work.
   Never a sentence.
5. **Abstain under ⛔ while awaiting custody.** The ledger skips custody on ⛔ (`:2629`), so the floor
   needs its own read or a ledger change.
6. **Keep every existing abstain:** kill-switch, assignee rc 0/2, teardown, B-3 logging of each
   stand-down. Do not weaken existing gates (the blocked-answered spare stays; only its log changes).
7. **Do not widen anti-deference TELLS with "need your call"** (`tests/anti-deference-nudge.bats:706-717`;
   wrap-ledger readout `:2604-2609`).
8. **Fix the instruction text that tells agents to disarm on ⛔ or file class C:**
   `hooks/session-continue.sh:14,1368`, `hooks/dispatch-assert.sh:237,269`,
   `CLAUDE.rules.slim.10-session-close.md:160,217`.
9. **Testability:** follow `tests/ship-floor.bats` (`STUB_RUNG`) for the floor. Add a
   `WRAP_LEDGER_BIN` seam to `boundary-handoff.sh:639`. Add a completion-assert fixture for the
   no-led, CLOSE-token-free close.

## 10. Open questions

- Should a supervisor ESCALATED mail re-arm the ⛔ floor once (a fresh decision-set latch epoch), or
  should the floor stay spent until the open-packet set changes?
- Is GATES_ALL a cc-decide packet field (`--gates all|<items>`) or a ledger inference? A packet field
  is honest and auditable but relies on the filer; an inference cannot know what is gated.
- Should a boundary-handoff ⛔ free-win recycle hand the packet ids to the successor, so its ledger
  keeps ⛔ (via BLOCKED_RECHECKED), or is dropping ⛔ on succession the intended reset?
- Should `idle-keepalive.sh` get a ⛔-only wake branch ahead of its own shadow-period decision
  (USAGE_LEVERS W3)?
