# Critique of D4 (minimal sufficient), lens: loop and false-block

Reviewer slot: loop-false-block. Design under review: `designs/D4-minimal-sufficient.md` (cited as `D4:n`).
Read-only review. The only repo file written is this one. Scratch lists were written under `/tmp`
(`/tmp/lf-tx.txt`, `/tmp/lf-loop.txt`, `/tmp/lf-drain.txt`, `/tmp/b13-bh.tsv`, `/tmp/b13-ca.tsv`). That is a
deviation from "read-only except the delivery file" and is reported here.

Abbreviations:
- `TX:n` is line n of the B13 transcript (`~/.claude-quaternary/projects/-Users-chrisren-Development-agent-context-sync/666022fd-….jsonl`).
- `IDL` is `~/.claude/autonomy/idl.jsonl` plus `idl.jsonl.20261024T050411Z.gz` and `idl.jsonl.20261021T132649Z.gz`.
- `CUST` is `~/.claude/autonomy/custody/cb2bdf30d6a495298cb26b459fd886e4.jsonl` (B13's cwd).
- Every number says whether it is **measured** (with the command) or **estimated** (with the method).

---

## 0. Verdict

**Unsound as written, under this lens.** The skeleton is right: one actuator in `session-continue.sh`, the per-Stop
marker, the predicate read from the ledger rather than from prose, and the in-flight abstains. But the safety claim
"worst case 2 forced turns per decision state, 4 per decision set" (D4:584, D4:589) is false in two ways:

1. **The budget is reset by the very action K3 demands** (§1.1). K3 says "run the next round". A round that lands
   through `ship-land.sh` and hits its escalation scan files a new class-C packet carrying the lead's own session id.
   That changes `BLOCKED_IDS`, which is both the key and the set key, so both budgets start again from zero. Nothing
   bounds the chain except the number of rounds. The repo's own comment names this failure:
   `hooks/session-continue.sh:1119-1129` ("a budget the demanded action RESETS never binds").
2. **The latch file is per cwd, not per session** (§1.2). Two sessions on the same account in the same checkout,
   both with an open loop, reset each other's counter on every Stop. B13 shows the precondition: an origin session
   that hands off and stays alive.

There are also measured false blocks on the incident session itself (§2.1), a ladder placement that weakens four
existing gates (§2.2), and a discharge the model can game with one DoD edit (§3.1). The fixes are small. With them,
D4's K3 and K4 are the right shape to graft.

---

## 1. Infinite-loop paths

### 1.1 BLOCKER: the demanded action resets the budget (ids joining the set)

**State.** A lead with `LOOP_OPEN=1` and nothing in flight, in a repo where the round's own land hits `esc_scan`.
- K3's key is `cksum(sid|BLOCKED_IDS|LOOP_HEAD)` and its set key is `cksum(sid|BLOCKED_IDS)` (D4:308-309).
- A new key zeroes `pc` (D4:315). A new set zeroes `psc` (D4:314).
- The no-progress guard runs only when `pc ≥ 1` (D4:320), so it never runs on a fresh key.

**How a new id appears without the operator:**
- `scripts/ship-land.sh:5840-5848`: on an escalation-scan hit, ship-land writes packet `shipland-esc-$(git rev-parse --short HEAD)`.
- The packet is `"class": "C"`, `"producer": "ship-land"`, and `"session_sid": os.environ.get("SID")`, with
  `SID="${CLAUDE_CODE_SESSION_ID:-}"` (`scripts/ship-land.sh:674`; fields read from `write_decision_packet`).
- A non-empty producer puts it in `$ask` (`scripts/wrap-ledger.sh:1527-1533`), so it counts in BLOCKED and in the
  new `BLOCKED_IDS` cell.
- Measured: 17 `shipland-esc-*` packets exist in the store (`ls ~/.claude/autonomy/decisions | grep -c shipland-esc`).

**The cycle.**
1. K3 fires: "run the next round as scoped".
2. The round's commits stack on the parked range. The next land re-scans `BASE..HEAD`, hits the same surface, and
   files `shipland-esc-<newHEAD>`.
3. `BLOCKED_IDS` changes, so the key and the set are both fresh, and K3 fires again.
4. K4's marker is keyed on the floor row's key (D4:396), so K4 also resets to three fresh nudges.

The same happens when the model, in the forced turn, files a new convicted class-C packet instead of working. Each
packet re-arms the floor. No session-level ceiling exists anywhere: D4:267 and D4:584 rule out a lifetime bound on
purpose.

**Bound needed.** Re-arm a key only when an id **leaves** the set (the operator answered), never when one joins.
Add a per-session ceiling as a backstop, for example ≤6 loop-floor fires per sid per 24 h. The ceiling must survive
both key and set changes.

### 1.2 MAJOR (unbounded across sessions): one latch line shared by every session in the cwd

- `kf="${f}.loop"` (D4:310). `f` is `state/continue-<sha1(config-dir|cwd)>` with no session id
  (`hooks/lib/continue-sentinel.sh:29-33`).
- The file holds ONE line, and a foreign key zeroes both counters (D4:312-316).
- Two sessions A and B (same `CLAUDE_CONFIG_DIR`, same cwd, both `LOOP_OPEN=1`, nothing in flight) therefore
  re-arm each other on every interleaved Stop.
- The no-progress guard is also skipped, because `pc` was zeroed.
- The harness cap does not bound this: it resets whenever a tool runs (maps/stop-hooks.md §1; `bin/claude-latest:344-355`).

**The precondition is real in B13** (measured from the transcripts and the DoD store):
- `1e7dc0e1 → 666022fd` was a same-account recycle on `.claude-quaternary` in the same cwd. The transcript spans
  meet at 2026-10-22T07:41.
- Origin sessions cannot retire themselves. TX at 2026-10-24T20:21:40Z reads: "Self-close refused. This pane is an
  origin session".
- 666022fd kept taking turns after its 20:22Z handoff. It was woken at 20:27:36Z and at 21:23:33Z.
- Its successor 502bd860 ran on `.claude-next`, so the two did not share the latch this time. A same-account
  handoff would have shared it.

The ship and mechanical floors copy the same one-line, sid-reset pattern (`hooks/session-continue.sh:1146`, `:1258`).
Those are lifetime budgets, so the damage there is smaller. K3's whole safety argument is its count, so it cannot
inherit the pattern.

**Fix.** Use a per-sid latch: `${f}.loop.${cur_sid}`, or a multi-line file keyed by sid.

### 1.3 Paths that ARE bounded (credit)

- **K3 alone, one session, stable ids.** ≤2 per key and ≤4 per set (D4:317-319). The latch is written before the
  block, and an unwritable latch means no block (D4:323-324).
- **K4 ↔ K3.** The woken turn's Stop is a budget abstain. K4 stops at 3 per key (D4:397).
- **K3 ↔ mechanical arm / ship floor.** K3 runs only on the unarmed path (`hooks/session-continue.sh:1316-1328`). 📦
  and 🚀 abstain (D4:295).
- **The memo cannot serve a stale `LOOP_OPEN` after a discharge.** The memo key carries the transcript mtime
  (`scripts/wrap-ledger.sh:637`, `$_wl_ms`), and a discharge `set` writes the transcript before the next Stop.
- **The discharge's session provenance works.** `CLAUDE_CODE_SESSION_ID` reaches Bash tool commands (measured:
  `echo $CLAUDE_CODE_SESSION_ID` in this session prints the id), and `set` stamps it (`hooks/dod-persist.sh:498`).

---

## 2. False blocks of a legitimate stop (constructed or measured)

### 2.1 MAJOR, measured on B13: the per-round fire window, and the budget spent a day early

K2 turns every ✅ of a session with an own loop line into 🔧 (D4:218-222). D4's replay assumes the machinery is live
from 2026-10-22 (D4:535) but replays only 10-24. On 10-23 the lead fired each round's lanes from a **background Bash
job** and closed while the job was still engaging lanes.

| Stop (Z) | Ledger rung (measured) | Custody at the Stop (measured, CUST) | Live wave | What K3 would do |
|---|---|---|---|---|
| 10-23 05:15:50 | ✅ (boundary-handoff fired free-win "the ledger reads ✅", IDL) | 0. First open at 05:16:46Z | 0 (free-win fired, which requires `live_waves=0`, `hooks/boundary-handoff.sh:907-909`) | **FIRE 1/2.** It says "Nothing is in flight … run the next round" while the fire job is launching round 24. The lead's own text at 05:15:53Z: "the fire script is still running as my own background job" |
| 10-23 05:15:59 | ✅ | 0 | 0 | The forced turn ran `cat …/fire.log`, a read-only verb, so the no-progress guard abstains (estimated replay) |
| 10-23 15:46:53 | ✅ (completion-assert IDL row `rung:✅` at 15:46:55) | 0. First open at 15:47:54Z | 0 | **FIRE 2/2.** The turn was opened by a task-notification (15:46:33Z), not by K3 |
| 10-23 23:40:13 | ✅ | 0. First open at 23:41:11Z | 0 | `loop-floor-budget`, ungated:1 |

Commands:
- `jq` over the boundary-handoff and completion-assert IDL rows for sid 666022fd;
- `jq -r '[.ts,.kind,.slug]' CUST`;
- the transcript text before each feedback record.

Consequences:
1. **Two false blocks.** The instruction "run the next round" arrives while the current round's lanes are being fired.
2. **The budget for key (666022fd, "-", loop head) is spent by 15:46:53Z on 10-23** (estimated replay from the
   measured rows above). D4 claims that in the "rules followed" counterfactual (a class-B re-file, so `BLOCKED=0`)
   "K3 fires the same way on 🔧" (D4:558-562). That is false. At 06:44:40Z on 10-24 the key is the same, so K3 abstains
   with `loop-floor-budget`. Only K4 remains. With the decision state stable for days, the "per decision state"
   budget is in fact the per-lifetime budget D4 itself condemns (D4:267).
3. D4 lists "a background Bash task the floor cannot see" as a rare residual (D4:584). It is this lead's normal
   dispatch pattern: once per round, 3 times on 10-23.

**Fixes.**
- Abstain on a live non-watcher background Bash task. The evidence is a `tool_use` with `run_in_background:true`
  whose task id has no terminal `<task-notification>`. Exclude `cc-await-ping`: the watcher was armed at F1 and F2,
  and a blanket background abstain would make K3 inert there. turn-scan's `ro_word` already treats `cc-await-ping`
  as non-work (`hooks/lib/turn-scan.sh:44`).
- Re-arm the per-key count on a wall-clock epoch (for example 2 per 6 h), not only on an id or scope change, and keep
  the per-sid ceiling from §1.1.

### 2.2 MAJOR: the LOOP branch masks 🚀, the re-check ⛔ and 👤, which weakens existing gates

D4 places `elif [ "$LOOP_OPEN" = 1 ]` between CLOSE_FLOOR (`scripts/wrap-ledger.sh:2670`) and `-z TRUNK` (`:2674`)
(D4:217-223). It claims "The loop becomes a 🔧 only where ✅ would otherwise be computed" (D4:46). The actual ladder
below that point is:
- no-trunk 🔧 (`:2674`);
- **🚀 LIVE_BREACH (`:2685`)**;
- **re-check ⛔ (`:2717`)**;
- **👤 (`:2726`)**;
- ✅ (`:2735` onward).

A loop session therefore never reads 🚀, re-check ⛔ or 👤. Each of these drives an existing gate:
- the ship floor's 🚀 arm (`hooks/session-continue.sh:1216`, which needs 📦 or 🚀);
- completion-assert's 🚀 contradiction (`hooks/completion-assert.sh:1166`);
- completion-assert's ⛔ branch for re-check closes (`:1218`);
- the shape arm, gated to ✅/👤 (`:1535`);
- the act arm on 👤 (`:1643`);
- the operator-readout 👤 block.

This breaks the hard constraint "never weaken an existing gate", and K3 then replaces a 🚀 "converge it now" with
"run the next round".

**Fix.** Insert the branch after `elif [ "$YOURS" -gt 0 ]` (`:2726-2734`) and before `elif [ "$DOD" = "absent" ]`
(`:2735`). `DOD=absent` cannot co-occur with `LOOP_OPEN=1`.

### 2.3 MAJOR, measured: a handed-off predecessor keeps `LOOP_OPEN=1` for life

- The predecessor's own loop line is newest-own forever: `## 2026-10-24T20:15:35Z (manual-set) … session=666022fd…`
  (`~/.claude/autonomy/dod/repo-7030c1939664b2e4.md:26-27`).
- K1 never overrides it (D4:114-117). K2 reads only own lines (D4:162-171).
- The only "handed off" abstain is the teardown marker, fresh for 1800 s (`hooks/session-continue.sh:599-617`).
  666022fd's marker is dated 2026-10-23 10:56 (measured: `ls -la ~/.claude/watchdog/teardown/`), so it is stale.
- After its 20:22Z handoff the predecessor was woken by peer mail at 20:27:36Z and 21:23:33Z.
- K3 stayed silent then only because the rung was 📦 (the successor's unlanded `f04c61db` in the shared checkout).
- Once the successor lands and its lanes return, the predecessor's next wake reads ✅→🔧 (loop). K3 then tells it
  "run the next round as scoped", and K4 nudges it up to 3 times: **two leads driving one loop in one checkout.**
- 502bd860, the successor, gets the same loop line through K1 (measured: its TX line 12 is `origin.kind:"human"` and
  carries `Scope (frozen): loop until dry…`).

**Fix.** In K2, mark a loop line superseded when the unfiltered repo store holds a newer block with the identical loop
line from another session. The successor's K1 capture writes exactly that. Then set `LOOP_SRC=superseded` and
`LOOP_OPEN=0`.

### 2.4 MAJOR: a loop ended by an operator answer stays "open"

- B13's real frozen scope reads "repeat until a round confirms nothing new **(or the operator answers decision
  b4780d7bb60e 'stop')**. Then tell the operator to paste the current prompt (v33)" (`repo-7030c1939664b2e4.md:27`).
- `b4780d7bb60e` is class B with options stop / keep looping (measured, `jq` on the packet).
- K2 ends a loop only on a newer own Scope line (D4:190). It reads no class-B packet and no resolution.
- The K3 reason offers only a "hold until <id> is answered" discharge (D4:342-351). It has no "the loop is finished
  or was stopped" discharge.
- So after the operator answers "stop", or after a round confirms nothing new, the lead closes ✅. It then gets
  2 forced turns (K3) plus 3 wakes (K4), each saying "run the next round as scoped", **against the operator's
  ruling**. "operator ruling d610f8473106" in the text lends that instruction authority.

**Fixes.**
- Abstain when any 12-hex packet id named in `LOOP_HEAD` is resolved.
- Add the discharge "the loop's stop condition is met or was ruled: freeze the next contract" to both the K3 and K4
  texts. The 🔧 READOUT already says it (D4:222); the block reason does not.

### 2.5 MAJOR, measured: the loop regex fires on a scope that quotes the words

The real input to K2 is K1's extractor over transcripts, not the store D4 measured (F5, 1 of 362). Measured over the
**1,646** transcripts larger than 20 KB modified in the last 14 days under `~/.claude*/projects`: 23 contain a
loop-shaped Scope line (raw grep). K1's own extractor yields `LOOP_OPEN=1` for **9** of them.
- 8 are B13 leads (7046d8d0, b351c528, f1997ec3, 98214164, 1e7dc0e1, 666022fd, e739e5b5, 502bd860).
- **1 is a false positive: this fix's own implementer session, 3d1dc252** (lead-idle-fix). Its frozen scope, "PHASE 1
  — research, before any edit…", contains goal (e)'s text `including a loop scope ("loop until ...") that has no
  checkboxes` at character 779 of 1,644.
- Its prompt records carry no `origin` field, and `(.origin.kind // "human")` (D4:108) counts them as human.
- It is not a research program (measured: `scripts/lib/research-program.sh is-active <cwd>` rc=1).
- So a research-then-await-approval session gets a permanent false 🔧, K3, and K4.

**Fix.** Anchor the syntax. The loop verb must open the scope (`Scope (frozen): loop until …`, or a structured
`Loop-until:` field that R:26 defines). Do not use a substring anywhere in a 1.6 KB brief. Consider requiring
`origin.kind=="human"` exactly: TX:14 has it.

### 2.6 MINOR: no exchange window, so a read-only answer gets a forced round

boundary-handoff holds its arm during an exchange (`CONV_S=900`, `hooks/boundary-handoff.sh:164`, `:846-848`). K3
has no such hold. An operator question mid-loop, answered read-only with nothing in flight, gets "run the next round"
while the operator is still typing. B13's controls at 18:25-18:31Z were saved only by the live round-27 wave (F8).
Fix: abstain while the last human prompt is younger than `CONV_S`.

### 2.7 MINOR: other "nothing in flight" misses

- **Live teammates.** `RESIDENT_MINE` is computed only on the ✅ path (`scripts/wrap-ledger.sh:2648-2649`, inside the `else` at `:2622`), and K3
  does not read it.
- **A watcher.** The text "so nothing will wake you" is false whenever a watcher is armed, as it was at F1 and F2.
  This is text only.

### 2.8 Controls D4 gets right (credit, checked)

- **Teammate.** Abstains on assignee rc 0 or 2 (D4:289-293).
- **Fired lane.** K1 picks the lane's own scope, not the lead's loop (measured on b13-r27-rb, -r27-b, -r27-d, -r27-e
  and -r4-p, -r4-b: all `LOOP=0`).
- **Money-landing repo at 📦.** 📦 is decided before the ✅-eligible path, so a loop never masks it (`scripts/wrap-ledger.sh:2615`), and K3
  abstains on 📦 (D4:295).
- **Genuine gate in a non-loop scope.** `LOOP_OPEN=0`, so no block and no nudge.
- **Research program.** `RESEARCH_PROGRAM` is computed in `--machine` before the ladder (`scripts/wrap-ledger.sh:2594`),
  so the abstain at D4:296 sees it.

---

## 3. Gaming by the model

### 3.1 MAJOR: the discharge is a self-declared DoD edit, handed over in the block text

- The block reason gives the exact escape: `dod-persist.sh set "Scope (frozen): hold until <decision id> is answered
  — <the act each round needs>"` (D4:349).
- K2 accepts any newer own line without "loop until" as the end of the loop (D4:190, D4:354). There is no check that
  the id is open, that it is the session's, or that it is class C.
- After the edit, every floor row is `loop-floor-no-loop ungated:0` (D4:284), so **K4 never fires** (D4:395).
- The B13 lead's stated belief was exactly the discharge condition: "No round 27 until e869fac7eb34 is answered"
  (TX:4270, 02:36:34Z), repeated at TX:4437, 4726, 4728 and 4749.
- D4's replay assumes the non-compliant lead "re-closes ⛔ with no write" (D4:549). The lead that the as-filed
  premise describes is more likely to run the offered command and idle again, silently.
- This is the same self-declaration D4 rejects for `--gates all` (D4:43, D4:597-601), except that this one has no
  flag to audit.

**Fixes.**
- Accept a hold only if it names an id in `BLOCKED_IDS`.
- Make it a **pause, not an end**: the loop resumes automatically when that id resolves.
- Log `loop-floor-held` with the id, and surface the claim once to the operator.

### 3.2 MAJOR: K3's own text becomes the contract at the next compaction

- K3's reason, a Stop-hook feedback record (`type:"user"`, `isMeta:true`; measured on 16 such records in TX), carries
  a literal `Scope (frozen): hold until <decision id> is answered — <the act each round needs>`.
- PreCompact's `extract_scope` reads every user and assistant text record with **no isMeta filter**
  (`hooks/dod-persist.sh:142-149`). It takes the newest line and persists it with session provenance (`:619-631`).
- If the lead has not restated a Scope line since the block (B13 never did after TX:14), the next compaction makes the
  template the session's newest own Scope line. That silently sets `LOOP_OPEN=0`, and SessionStart re-injects a "hold"
  contract.
- D4's F3 (D4:75) is true of the incident transcript only because no hook text then contained a Scope line.

**Fixes.**
- No hook or supervisor text may contain the literal `Scope (frozen):`. Add a `dod-persist.sh hold <id> "<act>"` mode
  that writes the line itself.
- Add `.isMeta != true` to `extract_scope`.

### 3.3 Not gameable (credit)

- **Checking a box or editing REMAINDER.** LOOP is kept out of REMAINDER (D4:192).
- **`--gates all`.** Nothing reads it.
- **Changing the packet class.** K3 does not read class.

---

## 4. K4 (supervisor nudge) defects

1. **MINOR→MAJOR: a stale oracle after an operator stop.** The oracle is the newest **loop-floor** row (D4:390). The
   floors run only on the unarmed path (`hooks/session-continue.sh:1316`). Suppose a lead armed `set` under ⛔, as the
   new R:217 tells it to, and the operator then types "…and stop":
   - the armed path clears on the kill switch and writes `cleared kill-switch`, not a loop-floor row;
   - the newest loop-floor row stays at its older `ungated:1`;
   - K4 then sends up to 3 nudges saying "run the next round as scoped now" against an explicit operator pause
     (legit-stops C11).

   The same staleness applies to a row written in a fire window (§2.1).

   **Fix.** The oracle should be the newest session-continue row of any reason for the sid. Re-check custody and the
   kill phrase at send time.
2. **MINOR: duplicate nudges with no cap under load.** The marker is written only on `rc=0` (D4:407).
   - cc-notify's caller contract says a bounded call can return 124 after the line was enqueued, and that callers
     must read `enqueued=` (`bin/cc-notify:95-111`, `:469`).
   - The bound is 20 s (`SUP_NOTIFY_TIMEOUT_S`, `scripts/lead-supervisor.sh:76`).
   - A timeout after enqueue leaves no marker and no back-off, so the line is resent at each STALL? cadence and never
     reaches `NUDGE_MAX`.

   **Fix.** Write the marker when `enqueued=1`, and count attempts.
3. **MINOR.** The gz fallback `"$1".*.gz` also matches `idl.jsonl.chain.*.gz` (both rotated families exist,
   measured by `ls ~/.claude/autonomy`). That is a fail-closed miss.

---

## 5. Smaller defects

- **`_lf_log` default.** `"${4:-{\}}"` expands to `{\}` under `/bin/bash` 3.2 (measured:
  `/bin/bash -c 'f(){ printf "[%s]" "${4:-{\}}"; }; f a b c'` prints `[{\}]`, and jq rejects it with "invalid JSON
  text passed to --argjson"). Every row logged without a 4th argument, including the `loop-floor-no-progress`
  ungated:1 row, then loses `ungated` and `key`. Hooks resolve Homebrew bash 5.3 here (measured), so this is latent.
- **K1 runs for every session with no own capture**, not just loops (D4:282). It therefore feeds DRAIN_SCOPE and
  CLOSE_FLOOR (`scripts/wrap-ledger.sh:945`, `:1490-1500`), and so completion-assert's CLOSEF contradiction
  (`hooks/completion-assert.sh:1144`) for any session whose human brief says "backlog" or "drain". D4's "K1 … No (it
  writes the DoD only)" (D4:582) is false transitively. Measured population: see §7.
- **K3 overrides the ledger's own action on any 🔧.** On 🔧 from UNCONVICTED, FILED_MINE or CLOSE_FLOOR, K3's
  "run the next round" replaces the action the readout names (D4:295 accepts any 🔧).

---

## 6. Best ideas to graft

1. **K3's shape.** One floor in `session-continue.sh`, using `mark_blocked` so completion-assert yields; a predicate
   from ledger fields and stores, never prose; and the ship floor's abstain set reused.
2. **In-flight abstains** on custody, LANDING and live workflow waves, with `bh_live_waves` moved verbatim into
   `hooks/lib/live-waves.sh` so the two hooks share one reader. F8 shows that control C2 needs it.
3. **The no-progress guard** through `turn_scan` (`.b` names our block and `.w=false`).
4. **K1's human-origin, Stop-time capture.** It is measured correct on B13 TX:14 and on 6 lane transcripts; it fixes
   *when* capture runs, not *what* it extracts.
5. **K2's own-session-only loop fact**, computed before the ladder and visible under ⛔, with the kill-switch seam in
   the memo key and `v1→v2`.
6. **K4 keyed on the floor's own IDL row** (`ungated:1`), so legitimate stops are never woken; a direct `cc-notify`
   to the subject; a marker that survives `clear_page`.
7. **B-3 logging** of every ⛔ stand-down (`loop-floor-no-loop`), closing the "never ran vs abstained" ambiguity.
8. **C1's ruling hint**: stderr only, stdout unchanged, the useful line printed last for `| tail` filers, and the
   Stop-hook producer opted out.
9. **No packet-class read and no ⛔ demotion.** The 48 legacy class-C packets keep today's behaviour.

---

## 7. Measured population of K1's DRAIN_SCOPE side effect

- 338 of the 1,646 recent transcripts contain a Scope line mentioning backlog or drain (measured:
  `grep -qE 'Scope \(frozen\):[^"]{0,600}([Bb]acklog|BACKLOG|[Dd]rain)'` per file).
- Running K1's own extractor (D4:107-111) over those 338, **182** yield a capture and **6** of those captured lines
  match `backlog|drain` (measured, same `jq` as D4:108 plus `grep -qiE 'backlog|drain'`).
- So K1 can newly turn on DRAIN_SCOPE, and with it the CLOSE_FLOOR 🔧 plus completion-assert's CLOSEF arm, for at
  most 6 sessions in 14 days. That is an upper bound: some of them already had a PreCompact or `set` capture.
- The side effect is real but small, so it stays **minor**. It still means D4:582's "K1 cannot extend a turn" is
  wrong as stated.
- The same replay shows K1 writing a new DoD capture for up to 182 sessions in 14 days in this subset alone (an upper
  bound). The design should state that fleet-wide write volume, and its effect on SessionStart injection, rather
  than describe K1 as loop-only.
