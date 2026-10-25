# Critique of D2 (hook and ledger enforcement), lens: loop / false-block

Reviewer slot: loop-false-block. Subject: `designs/D2-hook-enforcement.md` (cited `D2:<line>`). Code anchors are
`path:line` in this worktree at `b6b53ea89`. Nothing in the repo or under `~/.claude` was written. Scratch inputs for
the measurements live in `/tmp/d2crit/` (outside the repo). Every number is labelled **measured** (command named) or
**estimated** (method named).

## Verdict

**Unsound as written (4/10 on this lens). It becomes sound with local fixes.** The architecture is right: the
ledger owns the predicate, there is one actuator, the budget is per decision state, and every discharge is a state
change. But two loop paths have no mechanical bound, which contradicts the design's own bound claim
(`D2:957`, `D2:964`: "worst case 2 forced turns per decision state", "5 model turns").

1. **The latch is a single slot.** Any change of key resets both the count and the HEAD latch (`D2:483-490`).
   The supervisor ladder has the same single slot, and its back-off drops to zero on a key change (`D2:659-663`).
   An A→B→A sequence therefore re-arms A. No per-session ceiling exists.
2. **The design's own discharge re-arms the floor.** The ownership parse is unanchored and tests `frozen` before
   `held`/`done` (`D2:172-174`). A `Scope (held):` or `Scope (done):` line that quotes `Scope (frozen): …` is
   parsed as a new frozen line. The loop stays open, the hold is cleared, the head changes, the key changes and
   the budget resets (measured, §1.2). Compliance creates a fresh decision state each time the wording varies.

Five major false-block paths (§2) and several minor ones (§3) follow. §4 lists the bounds the design already gets
right. §5 lists the ideas worth grafting.

---

## 1. Loop paths with no bound

### 1.1 The single-slot state turns "2 per decision state" into "2 per key change" (blocker)

- **State shape.** `sfile` holds one line, `skey head_sha count`. `[ "$pkey" = "$skey" ] || { psha=""; pcnt=0; }`
  (`D2:483-485`) wipes both the latch and the count whenever the key differs from the last one written. The key
  is `sid|ids|kind|head` (`D2:478`).
- **Sequences that revisit a key.** Every packet cycle moves a loop session ⛔{X} (`kind=blocked`) → 🔧-loop
  (`kind=loop`, ids `-`) → ⛔{Y} → 🔧-loop. The 🔧-loop key is the same each time it comes back, and it gets a
  fresh 2-block budget on every return, because ⛔{Y} overwrote the slot in between.
- **A flip that needs no model action.** The ledger's cc-decide read has its own 5 s bound. On a timeout it sets
  `BLOCKED=0, BLOCKED_SRC=error` (`scripts/wrap-ledger.sh:1510-1511`). The session-continue Stop timeout is 10 s
  (measured: `jq … ~/.claude/settings.json` → `10 /usr/bin/env bash ~/.claude/hooks/session-continue.sh`), so the
  hook can complete with BLOCKED read as 0. RUNG then falls to the ✅-eligible branch, where the proposed loop-🔧
  arm (`D2:283-286`) fires with `kind=loop`. The next good read flips back to `kind=blocked`. Each flip is a new
  key, so each flip fires. How often under load is **estimated**, not measured: cc-decide list measures 0.065 s
  idle (`bin/cc-decide:538`), and this hook was hitting its old 5 s cap on 45-59% of Stops at load
  (`hooks/session-continue.sh:1093-1095`).
- **The supervisor amplifies it.** `.nudged` is single-slot too: `[ "$pk" = "$key" ] || { pc=0; pl=0; }`
  (`D2:660`). The back-off applies only when `pc > 0` (`D2:662-663`), so after a key change the next nudge is
  immediate. STALL? re-qualifies about every STALL_S, which is 1800 s (`scripts/lead-supervisor.sh:139`,
  `:1046-1048`). So a session whose rows alternate keys is woken roughly every 30 min with no count cap. The only
  fleet bound is NUDGE_SWEEP_MAX=3 per sweep, and it is fleet-wide, not per session (`D2:642`).
- **The design's tests pin the reset but never the revisit.** S4 asserts "change BLOCKED_IDS ⇒ blocks again 1/2"
  (`D2:1071`). No test alternates A,B,A.
- **Bound needed.**
  - One line per key, never reset by switching away: a small map file, or `${f}.scope.<sid>.<key>`.
  - A per-session rolling ceiling that is independent of key, for example `CC_SCOPE_FLOOR_SESSION_MAX=4` per
    24 h. This must sit beside the per-state cap; it does not replace it.
  - In the supervisor, a per-sid daily cap of 3 and a back-off that is never reset to 0 by a key change.
  - Test S18: keys A,B,A at one HEAD ⇒ A fires at most twice in total, and the session ceiling holds.

### 1.2 Discharges that quote the scope are parsed as new contracts (blocker)

The ownership awk tests `/Scope \(frozen\):/` first and unanchored, and its `sub(/^.*Scope \(frozen\):…/)` is
greedy (`D2:172`). `held` and `done` are tested only after it (`D2:173-174`). `dod-persist.sh set` will now accept
any text containing `Scope (held):` or `Scope (done):` verbatim (`D2:333-334`).

Measured by replaying the design's awk verbatim (`D2:169-178`) with macOS awk 20200816 on three own-session
fixtures, `/tmp/d2crit/dod{A,B,C}.md`:

| own capture after `Scope (frozen): loop until dry. Each round = rehearse` | parsed result |
|---|---|
| `Scope (done): round 33 confirmed nothing new, so Scope (frozen): loop until dry is met` | `loop=1 done=0 head=[loop until dry is met]` (still open, new head) |
| `Scope (held): e869fac7eb34 — every round of Scope (frozen): loop until dry needs the answer` | `loop=1 held=[] head=[loop until dry needs the answer]` (hold erased, new head) |
| `Scope (frozen): write the v33 summary` | `loop=0` (loop silently closed, no done line) |

- **The loop.** The floor tells the model `set "Scope (held): <id> — <what it gates and why>"` (`D2:530`), and the
  nudge text says the same (`D2:697`). "What it gates" is the loop scope, so quoting it is the natural answer. Each
  quoting discharge changes `head` and therefore the key (§1.1), so the floor fires again with a fresh budget. An
  identical repeat is latched; a re-worded one is not. Only the model's wording bounds this. It is the
  "a budget the demanded action RESETS never binds" class that `hooks/session-continue.sh:1118-1124` documents.
- **Spill-over into existing readers.** `last_recorded_scope` (`hooks/dod-persist.sh:140`) and the ledger's
  DOD_SCOPE read both use an unanchored `grep -o 'Scope \(frozen\):.*'`. A quoting held or done line therefore
  also becomes the toplevel's "THE CURRENT CONTRACT" for every session in the checkout. Today only frozen and
  grown lines are ever written, so this exposure is new.
- **Bound needed.**
  - Anchor every rule to line start (`/^Scope \(frozen\):/` and the same for done and held).
  - Test `done`/`held` before `frozen`.
  - Make `dod-persist.sh set` refuse, with rc 2 and a reason, a held or done line that contains `Scope (frozen):`.
  - Pin all three fixtures above.

---

## 2. False blocks of legitimate stops (major)

### 2.1 A recycled or fired successor inherits the loop but cannot inherit the hold

**State.** Predecessor P runs a loop. It files class C X (for example a C6 money gate that every round needs) and
correctly writes `Scope (held): X — …`. P recycles, through boundary-handoff at ≥73% or through /handoff. Its brief
carries `Scope (frozen): loop until …`, which is exactly B13's `TX:14` shape.

1. **The successor S captures the loop.** S's first Stop runs the intake, which copies the loop line under S's sid
   (`D2:363-394`).
2. **The hold does not carry over.** HELD looks only at S's own blocks after S's own frozen line, and must name an
   id in S's own open class-C set (`D2:59-61`, `D2:243-246`). `count_blocking_decisions` counts only packets with
   `session_sid == $sid` (`scripts/wrap-ledger.sh:1529`). X is P's packet, so S can never hold on it.
3. **S's ledger reads 🔧-loop, even if S re-checks X.** The re-check ⛔ rides the ✅-eligible path at
   `scripts/wrap-ledger.sh:2717`. The proposed loop arm sits at CLOSE_FLOOR's rank (`D2:278-283`), which is above
   :2717. So 🔧-loop outranks the re-check ⛔.
4. **The floor and the supervisor push S anyway.** The floor's 🔧 case does not consult HELD (`D2:456`). Result:
   2 floor blocks plus 3 supervisor nudges per successor generation, each pushing rounds that every one needs the
   gated act.
5. **S has no honest discharge.** It can file a duplicate class-C packet for the operator and then hold on that,
   or write a false `Scope (done)`.

The designer saw this path but closed it only for the optional P5 free-win (`D2:584-586`).

**Fix.**
- HELD accepts any open class-C id from any session, plus RECHECKED_IDS.
- The loop-🔧 arm honours HELD.
- Rank the loop arm below the re-check ⛔ (after `:2717`), or abstain `kind=loop` when BLOCKED_RECHECKED>0.
- The intake skips the capture when a lineage predecessor's store blocks (dod lineage trail,
  `hooks/dod-persist.sh:208-214`) hold a held or done line after the same frozen text.

### 2.2 The supervisor's oracle is a stale row, so it wakes sessions that are finished

- **The floor writes no row on most rungs.** It is SILENT on ✅, 📦, 👤, on a non-loop 🔧, and on a re-check ⛔
  (`D2:454-458`). Test S16 pins that silence (`D2:1083`).
- **The supervisor reads the last row anyway.** It takes the session's last `scope-floor*` row whenever it appears
  (`D2:649-656`).
- **STALL? covers every idle session.** It fires for every live owner whose telemetry and transcript are both
  ≥1800 s stale, whatever its rung (`scripts/lead-supervisor.sh:1046-1048`).

**State.** The floor fires (row `scope-floor`, ungated 1). The lead does the work, records `Scope (done):`, lands,
and closes ✅. Or, in a money-landing repo, it parks on 📦, which R:58/R:103 make terminal-valid. Neither close
writes a new row. After 30 min idle, the supervisor sends "keep driving the ungated scope … run the next round"
three times over about 6 h (`D2:693-698`). These are false wakes on two legitimate stop types the brief lists.

**Fix**, any one of these:
- (a) On a non-firing rung, when `${f}.scope.<sid>` exists, delete it and log `scope-floor-clear`. The oracle then
  sees that row.
- (b) At nudge time, re-run `WRAP_SESSION_ID=<sid> wrap-ledger.sh --machine` in the session's cwd, bounded, and
  require `SCOPE_UNGATED>0 ∧ RUNG∈{⛔,🔧}` live.
- (c) Require the row's `ts` to be no older than that sid's newest Stop-hook row.

### 2.3 The loop classifier and the intake extractor flag sessions that are not looping

- **The pattern matches scope sentences that describe loop work.** Measured with awk 20200816 over
  `/tmp/d2crit/lines.txt`, using `D2:72-73` verbatim:

  | Scope sentence | Result |
  |---|---|
  | "add the loop until dry floor to session-continue" | MATCH |
  | "build the 'loop until …' scope floor (D2)" | MATCH |
  | "review why a loop until dry lead idled 11 h" | MATCH |
  | "port the keep looping until pattern to cc-fire" | MATCH |

  These are the scopes of this fix's own implementation and review sessions. They reach the store through `set`
  (new R:26 tells every writing session to use it, `D2:751`) and through PreCompact, which captures the newest
  frozen line in any user or assistant text (`hooks/dod-persist.sh:143-150`, `:624-630`).
- **The intake takes the first quoted scope, not the session's own.** It uses `grep -m1 -oE
  'Scope \(frozen\):.*'` with no line anchor (`D2:379`). Measured on `/tmp/d2crit/brief.txt`, a brief whose
  background line quotes the B13 scope inside backticks and whose next line is `Scope (frozen): write the
  critique…`. It returns `Scope (frozen): loop until dry. Each round = rehearse\` and idled 11 h.`, and the
  anchored pattern then matches it.
- **Effect.** A read-only or implementation session reads 🔧-loop instead of ✅. It gets 1 floor block (2 if HEAD
  moves) plus 3 nudges saying "run the next round", until it writes `Scope (done)`.
- **Base rate.** Low today. Measured: 189 transcripts under `~/.claude*/projects` modified in the last 2 days;
  9 contain a loop-scope literal anywhere; only the B13 lineage (`666022fd`, `502bd860`) has it in user or
  assistant text. The round-27 lanes have it only in tool results, which PreCompact does not read. The risk grows
  as follow-on briefs quote the incident and its test fixtures (`D2:1044`, `D2:1090`).
- **Fix.**
  - Line-anchor the intake: `^[[:space:]>*-]*Scope \(frozen\):`.
  - Require the loop verb as the scope's first word (drop the ≤40-character object prefix), or use an explicit
    marker such as `Scope (frozen, loop): …`.
  - Add negative fixtures for the four phrasings above.

### 2.4 Operator holds and stops are mostly missed, and nudges then override the operator

- **Measured coverage: 2 of 10.** I ran `SCOPE_HOLD_RE` (`D2:441`) and the existing KILL_RE
  (`hooks/session-continue.sh:386`) through `/usr/bin/grep -iqE` under `/bin/bash`, the grep a hook resolves
  (`/tmp/d2crit/holdtest.sh`).
  - Matched: "wait for my answer before round 27", "don't run round 27 until I've looked".
  - Missed: "hold off until I review the results", "wait until I reply", "pause until I'm back tonight",
    "stop the loop and paste v33", "let's discuss the classifier first, don't do anything yet",
    "park this until tomorrow", "no more rounds for now", "hold on, I need to think about this".
- **Effect of a miss.** The floor forces a round, and the rows it writes (`fired`/`latched`) qualify for 3
  supervisor nudges (`D2:655`). That is forced work against an explicit operator pause or stop: the D-8 class this
  hook exists to prevent (`hooks/session-continue.sh:25-28`, `:437-438`). R:49 makes explicit pauses
  terminal-valid.
- **"Stop the loop" is the incident's own decision answered yes.** The loop stays open until the model writes
  `Scope (done)`, so the first close after the operator's ruling is pushed to "run the next round".
- **No conversation hold.** The floor has none. boundary-handoff suppresses its free-win during an exchange
  (`CONV_S`, `hooks/boundary-handoff.sh:846-848`).
- **Hard-to-diagnose environment.** In this machine's interactive zsh, `grep` is a shell function backed by ugrep,
  which rejects `SCOPE_HOLD_RE` as "exceeds complexity limits". Hooks resolve `/usr/bin/grep` (measured: `type
  grep`; `/bin/bash -c 'command -v grep'`), so this affects only hand reproduction.
- **Fix.**
  - Abstain while the last genuine human message is younger than CONV_S, when the operator is present. This does
    not touch B13 F1, whose last operator message was hours old.
  - Widen the hold set: `hold off|wait until I|pause|park|no more rounds|stop the loop|don.?t do anything`.
  - Never let the supervisor nudge when the newest genuine operator message is newer than the floor row it is
    acting on.

### 2.5 New R:217 and R:103 arm a continuation on every ⛔ without a held line, including the ones with nothing to do

- **What the rules say.** New R:217: "On 🔧, and on a ⛔ that is not held, arm the continuation" (`D2:800`). New
  R:103: "Only a held ⛔ … may end a turn holding work" (`D2:772`).
- **What the hook says.** For every non-loop session (no boxes: 0 in the store, `D2:48`) the floor computes
  `SCOPE_UNGATED=0` and stays silent (`D2:960`, C4 `D2:995`).
- **Where they disagree.** The C2 legit stops (`maps/legit-stops.md` §4: 43055acd, e582464c, c56c729c, 79076bcf,
  fd91140d) and the 23 sessions holding 48 open class-C packets (`D2:997`) have no held line, so the rule tells a
  compliant model to `set` a step on every close.
- **Cost.** The armed path blocks the first time. The idle-repeat skip cuts only the second, identical, idle repeat
  (`hooks/session-continue.sh:1400-1426`). The cap is 8 per chain (`:1445-1458`), and each `set` resets it (`:144`).
  So about 1 wasted forced turn per ⛔ close, repeated on every close. For a watcher-polling session (e582464c,
  hourly) that is about 1 per hour, indefinitely. **Estimated** from those code paths.
- **Fix.** Tie both rules to the ledger's clause: "on a ⛔ whose readout says 'Not gated by it: …'". A ⛔ with
  nothing ungated may end the turn without a held line.

### 2.6 Gaming is invisible to the operator (major for the gaming half of this lens)

- **One command zeroes the predicate.** `set "Scope (held): <any open id> — …"`, `set "Scope (done): …"`, or a
  plain new non-loop `Scope (frozen): …` each do it. The last one is the normal intake gesture and leaves no trace:
  measured, `dodC` → `loop=0`.
- **The claimed visibility is not where the operator looks.** §9 relies on visibility (`D2:1139-1143`). But with
  HELD=1 the READOUT is pinned byte-identical to today's (`D2:1045`), so the operator block, which prints READOUT
  verbatim (`D2:618-619`), never shows the hold. The claim is visible only in the session's own SessionStart
  injection and the store file.
- **One hold covers later packets.** A single held line naming X also covers any later packet Y while X is open,
  because the match is "any open id is named" (`D2:243-245`).
- **Fix.**
  - READOUT and operator-readout render `held: <reason>`, `loop stopped: <evidence>` and `loop superseded without
    a recorded stop`.
  - Log an IDL row `scope-held-after-block` when a held or done line lands within N s after a scope-floor block
    with no commit in between, so cc-audit can count escapes.

---

## 3. Minor

1. **Fail-open is not uniform.**
   - `RESEARCH_PROGRAM` stays `none` when the research lib or registry read fails (`scripts/wrap-ledger.sh:1066`,
     `:1073`). The research abstain (`D2:465-466`) then lets the floor block inside a program. Emit a
     `RESEARCH_SRC` and abstain on `error`.
   - `scope_hold_active` reads `_sc_lum`, which only the kill memo sets (`D2:510`). Under the documented seam
     `CC_SC_KILL_MEMO=0` (`hooks/session-continue.sh:1311`) the hold check is silently off.
2. **In-flight blind spots.**
   - The abstain counts custody, LANDING, residents and workflow waves (`D2:467-475`). It does not count
     `run_in_background` Bash tasks, background Agent subagents, or peers reached by `cc-notify` without custody.
     No existing helper counts them either (measured: grep for `background` in `hooks/session-continue.sh` finds
     only the /goal notes at :458, :680-685 and :745).
   - Effect: one "run the next round" push while a round is still running, which can start a concurrent duplicate
     in the same worktree. Bounded at 1 per (key, HEAD).
   - Fix: count started-but-unnotified background tasks from the transcript as in flight.
3. **P5 ⛔ free-win re-fires on every idle wake.** The latch re-arms whenever it is ≥ IDLE_REARM_MIN old and no
   interactive turn is recent (`hooks/boundary-handoff.sh:823-831`), and no count caps it. A held ⛔ that is woken
   hourly gets a forced recycle advisory every hour until the operator answers. `D2:960` calls this "a forced
   turn". Fix: cap the ⛔ free-win at 1-2 per decision state.
4. **Shadow is not shadow for the nudge.** The supervisor counts `scope-floor-shadow` rows as nudge-worthy
   (`D2:655`). With the floor in shadow and the supervisor live, sessions get real wakes from a floor that was
   deliberately not blocking. Fix: exclude shadow rows unless the supervisor is in shadow too.
5. **A genuine all-gating gate in a loop session still costs 1 forced turn** before `Scope (held)` is written.
   It is bounded and a state change discharges it, but the floor cannot know in advance. Grafting the packet-level
   `--gates all` composition (`D2:1004-1005`) removes that turn when the filer knows at filing time.
6. **At ≥73%, two blocks on one Stop can contradict each other.** The scope floor says "run the next round" while
   boundary-handoff's threshold advisory says "recycle". Its compose-guard checks only the sentinel
   (`hooks/boundary-handoff.sh:687-694`), and the design adds the marker yield to the free-win arm only
   (`D2:600-601`). This is not a loop. The fix is to extend the marker yield to the threshold arm, or have the
   floor yield at ≥T.

---

## 4. Bounds the design gets right (verified against code)

- **Mechanical arm on ⛔** (`D2:400-416`). It reuses the per-sid `.mech` budget (`hooks/session-continue.sh:1138-1154`),
  times CLAUDE_CONTINUE_MAX. `clear` spends that budget rather than deleting it (`:263`), and the floor's state file
  is untouched by `clear` (`:255`). So clearing is an off switch, not a snooze.
- **Floor scope.** The floor runs only when no sentinel exists (`hooks/session-continue.sh:1293`), at most one floor
  per Stop. It fails closed on an unwritable state file (`D2:490-491`). The hash binary `/sbin/sha1sum` exists
  (measured `ls`), the same one boundary-handoff already uses (`hooks/boundary-handoff.sh:797`).
- **Intake capture.** The marker is written before any work (`D2:369`), so a failure never repeats per Stop.
- **No hidden recycle trap from the loop-🔧 rung.** handoff-fire refuses on fields, never on RUNG
  (`scripts/handoff-fire.sh:333`, `:8645`). completion-assert convicts on fields (`hooks/completion-assert.sh:1103-1144`),
  and its shape arm is limited to ✅/👤 (`:1535`). Anti-deference's false-done reads DIRTY, UNLANDED and REMAINDER
  only (`hooks/anti-deference-nudge.sh:512-521`).
- **LANDING** is computed before the ladder, unconditionally (`scripts/wrap-ledger.sh:859-871`), so the in-flight
  abstain does see a land under ⛔.
- **Wakes do not mask an operator hold.** A socket-wake frame is queued isMeta (`bin/cc-wake:18`), and
  `last_user_msg` drops isMeta and machine envelopes (`hooks/session-continue.sh:426-433`).
- **Latch ids are deterministic.** They are read in glob order (`bin/cc-decide:558`), so the key cannot change
  from ordering alone.

---

## 5. What a loop-safe D2 needs (minimum)

1. Per-key state that switching never resets, plus a per-session rolling ceiling (§1.1).
2. Line-anchored `Scope (…)` parsing in the ledger, plus a refusal in `dod-persist.sh set` (§1.2).
3. Treat unknown as abstain: `BLOCKED_SRC=error`, `RECHECKED_SRC=error` and a research read error mean no floor
   and no loop-🔧 arm (§1.1, §3.1).
4. A supervisor that re-verifies the predicate live, caps per sid per day, never zeroes its back-off, and skips
   shadow rows (§1.1, §2.2, §3.4).
5. A conversation hold and a wider operator-hold set (§2.4).
6. Successor-safe holds: any open or re-checked id counts, and the loop arm honours HELD and ranks below the
   re-check ⛔ (§2.1).
7. Rule text tied to the ledger's "Not gated by it" clause (§2.5).
8. Operator-visible held, done and superseded states (§2.6).
