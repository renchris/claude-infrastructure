# Critique of D1 (rule text only) through the loop and false-block lens

Design under review: `docs/research/lead-keeps-working-2026-10-24/designs/D1-rule-text.md` (cited `D1:<line>`).
Worktree `lead-idle-fix` at `b6b53ea89`. Read-only. This file is the only thing written.
Labels: `R` = `CLAUDE.rules.slim.10-session-close.md`, `S` = `CLAUDE.global.slim.md`, `G` = `CLAUDE.global.md`,
`TX:n` = line n of the incident transcript `…/666022fd-ed3e-4e72-b293-7caae899d585.jsonl`.
Every number is labelled measured (with its command) or estimated (with its method).

**Verdict: unsound for this lens (score 4/10).** D1 adds no hook arm, so no hook gains a new way to block.
But D1 changes *when the model arms the existing agent-armed chain*. It also changes *which stop conditions
that chain has left*. The design says the change carries "zero new loop risk" (`D1:33`) and that the
loop is "bounded by the scope" (`D1:714`). Both claims are false in the incident's own state. The repo's own
lesson about this chain is that "the defect was the false claim of a bound, not the absence of one"
(`G:1136-1137`). D1 repeats that defect. It becomes sound-with-fixes once the bounds in §9 are added. All of
them are text-level, plus one small seam for the recommended code pairing.

---

## 1. The unbounded loop path (blocker)

### 1.1 The concrete state

| Fact | Evidence |
|---|---|
| The loop scope cannot converge, by construction | `eb3dbe1e5e94.what_plain`: "confirmed items per round were 127, 85, 99, 79, 77, 79, mostly small wording and doc drift that each round's own fixes create" (measured: `jq … ~/.claude/autonomy/decisions/eb3dbe1e5e94.json`); TX:4254 option text: "about 80 confirmed a round for 24 rounds, no downward trend" (measured: `sed -n 4254p … \| jq`) |
| The scope's only other exit is an operator answer | the persisted scope ends "repeat until a round confirms nothing new (or the operator answers decision b4780d7bb60e 'stop')" (measured: `sed -n 27p ~/.claude/autonomy/dod/repo-7030c1939664b2e4.md`) |
| That exit packet is the D1-shaped class B whose default keeps looping | `b4780d7bb60e`: class B, `default_if_no_veto` "keep running rounds as scoped (loop until a round confirms nothing new)", deadline 2026-10-31T23:00Z (measured, jq). When it fires, the operator-answer exit resolves as "keep running" |
| D1 tells the model that a fired default is the answer and not to re-ask | R-7 "a fired class-B default, `expired-actioned`, rules by silence" (`D1:287`); R-4 "unless a ruling answers it … act on it, citing it" (`D1:263`). The design's nuance that "new evidence (24 more rounds) makes a re-ask legitimate" lives only in §6.1 (`D1:745`). It is in neither R-7 nor R-4 |
| D1 tells the model to arm the chain on ⛔ or ✅ when a loop is open | R-10 (`D1:311`); R-6 "never what the frozen scope directs (a loop's next round too)" (`D1:279`) |

### 1.2 Why every existing bound fails here

| Bound | Why it does not end this chain | Evidence |
|---|---|---|
| `CLAUDE_CONTINUE_MAX`=8 | Each `set` zeroes `.count`, and the hook's own block reason tells the model to "Re-arm each 🔧 turn … reset the continuation counter" | `hooks/session-continue.sh:144`, `:1368`, `:1445-1458` |
| Idle-repeat skip | Fires only when the forced turn made no write *and* the reason is byte-identical. Every round writes (lanes, notes, commits), and the step text changes each round ("run round 28", "run round 29") | `hooks/session-continue.sh:1400-1426` (`.w == false` at `:1417`, reason compare `:1420-1425`) |
| `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` (50 via launcher) | The counter resets once a tool has run, so it catches only a text-only wedge | `bin/claude-latest:344-355`; `G:1134-1135`; `R:217` |
| Kill-switch | Needs the operator, and the premise of the incident is an absent operator. "hold off" or "wait" are not kill phrases | `KILL_RE` at `hooks/session-continue.sh:386` |
| The frozen DoD | Unreachable (row 1). The operator-answer exit turns into "keep running" at the deadline (row 3) | §1.1 |
| The model's judgment | D1's R-4 and R-7 say a fired default *is* the ruling, which shuts the valve the B13 lead actually used (it re-asked at round 26 after `eb3dbe1e5e94` had fired) | `D1:263`, `D1:287` |
| Context fill | boundary-handoff abstains on every axis while the sentinel exists: 73% fill, forecast, 25 MB transcript, 1.5 GB RSS, 700K tokens and free-win. Its recycle-retry also yields | `hooks/boundary-handoff.sh:694` (abstain `continue-hook-armed`, placed before every fire path), `:328` (`keep:continue-hook-armed`) |
| The weekly meter | This is the one real terminator, and it is harmful. A walled account stops every session on it. R:113 also tells a session with work left on a walled account to `cc-lr switch` to another account, so the loop can move across accounts | `R:113` |

Result: in the B13 state, a model that follows D1 (arm on ✅/⛔, never treat the next round as gated, never
re-ask a question a fired default answered) is blocked at every Stop until a person types a kill phrase or the
account meters run out. G already records chains of this kind: "one working chain of 311 blocks" (`G:1133`).

### 1.3 The bound it needs (text, cheap)

1. **A meter stop on loop scopes**, the same shape the operator chose for the Codex grant (`D1:353`, "no call at
   ≥80% of the weekly meter"): *no new round at or above N% of this account's weekly meter, and never `cc-lr
   switch` to continue a loop*.
2. **A re-ask valve.** A fired class-B default answers the question *as it stood*. After K more rounds with
   no move toward the stop condition (a measured count), re-file it as class B with the new evidence. Put
   that in R-7, not only in `D1:745`.
3. **A loop-scope stop the agent can measure** at intake: a round cap or a wall-clock cap written into the
   `Scope (frozen):` line R-2 persists. A scope with no stated cap gets one by default.

---

## 2. The busy-wait path under ⛔ (major)

**State.** The ledger reads ⛔ (a class-C packet is open). The model judges that "ungated work" remains, but
that work is only *waiting*: lanes in flight, a workflow, or an answer. R-10 now licenses arming on ⛔. Today R
says to clear on ⛔ (`R:217`), so this state is closed by the text that is live now. The model arms a wait step,
for example "await round-27 lanes, then collect".

**Why the bound D1 cites does not hold.** `D1:713` says a model with nothing to do "costs about one wasted
turn" because of the idle-repeat skip. That skip needs the forced turn to have made no write. `turn-scan.sh`
counts any Bash command whose first word is not on its read-only list as a write. The list includes
`cc-await-ping`, `session-continue.sh` and `wrap-ledger.sh`. It does **not** include `cc-decide`,
`cc-custody` or `cc-backlog` (`hooks/lib/turn-scan.sh:44`). So a forced turn that runs `cc-custody list` or
`cc-decide list --open --json` counts as a write, and the next Stop blocks again. D1's own G-4 tells the
model to run `cc-decide list --open --json` "at each wake" (`D1:488`). The re-arm then zeroes the counter
(`:144`). The chain re-prompts with no sleep for as long as the wait lasts. If a lane hangs, it never ends.

**This shape is live.** On 2026-10-24T21:17:08Z, session `3d1dc252` (the orchestrator of this research) ran
`cli-set` with the step "await workflow wf_92f51d89-cca (designs+critiques+synthesis), then commit …". It
was blocked once at 21:17:18Z and cleared at 21:17:23Z (measured: `grep 3d1dc252 ~/.claude/autonomy/idl.jsonl
| jq 'select(.hook=="session-continue")'`). A lead armed a wait step. Today's text made it clear the step
5 s later. Under D1's R-10, arming on ⛔ is licensed.

**Bound needed.** R-10 should say: *a step that waits on a person, a lane, a workflow or a packet is never a
continuation step; wait with `cc-await-ping` under `run_in_background`*. This matches the ledger's custody
readout, "await them ARMED (cc-await-ping)" (`scripts/wrap-ledger.sh:2639`, `:2641`). On the code side, add the
`list` verbs of `cc-decide`, `cc-custody` and `cc-backlog` to `ro_word`, so the existing skip applies.

---

## 3. A gate weakened in the always-loaded text (major)

R-6 (slim, loaded by every session) says: "A decision gates only the act it asks about and work built on
its answer, **never what the frozen scope directs**" (`D1:279`). In the legit-stop categories L5, L6 and L7,
the gated act is usually *in* the frozen scope. Examples: "drop the dead column in 8 tenant DBs"
(`c19c50afcb82`), "deploy the fix to live email" (`3f99e3868e9c`) (`maps/legit-stops.md` §3). Read literally,
R-6 says that act is not gated, because the frozen scope directs it.

The carve-out that resolves this, "The gated act itself still waits … G2 binds" (`D1:475-476`), is only in
G-4. G deploys to `CLAUDE.full.md`, which is "not loaded by any session" (`install.sh:1083`). So the sentence
that keeps G2 intact reaches no session. `R:45` (G2) still exists, but the two always-loaded sentences now
conflict. The hard constraint is "never weaken an existing gate". **Fix:** carry the carve-out in R-6:
*"…never what the frozen scope directs, except the act a class-C decision asks about, which waits even when
the scope names it."* (about 90 units).

---

## 4. Gaming and false release (major)

1. **The agent can end its own loop.** R-2: a loop scope "stays open until X holds or a newer `Scope
   (frozen):` line ends it" (`D1:247`). Nothing says who may write that line. `dod-persist.sh set` is an
   agent CLI with no authority check (`hooks/dod-persist.sh:484-500`). So `dod-persist.sh set "Scope
   (frozen): loop paused pending operator"` ends the loop by D1's own definition. The `LOOP_OPEN` ledger
   field that D1 recommends as its backstop (`D1:821`) inherits this hole if it keys on the newest Scope
   line. **Fix:** a loop scope ends only when X is measured to hold or the operator's own words end it, and
   the new line must cite which.
2. **Subagents write into the lead's lineage.** S:116 says a default (non-`workflow-lean`) agent that writes
   code loads the rules. A subagent's Bash carries the parent's `CLAUDE_CODE_SESSION_ID`. Measured: this
   worker's environment has `3d1dc252…`, the sid under which the orchestrating lead's own arming is logged
   (IDL above). `set` stamps that id (`hooks/dod-persist.sh:498`). R-2 tells "the first time a task will
   write tracked files … persist it", so each implementation subagent would append its narrow sub-scope as
   the lead's newest frozen line. Three effects follow:
   - it ends the lead's loop under R-2's "newer line" clause (a false release, which brings the idle back);
   - after compaction it is injected as "THE CURRENT CONTRACT … Do NOT narrow it" (`hooks/dod-persist.sh:462`);
   - a subagent persisting its own "loop until tests pass" would give a future `LOOP_OPEN` a loop that never
     ends for the lead (a false block).

   **Fix:** R-2 says *a subagent or workflow slot never runs `dod-persist.sh set` or `session-continue.sh
   set`; only the session that owns the frozen scope does*.
3. **Escaping to ⛔ by phrasing.** R-7 keeps class C for "a pick with no status quo" (`D1:287`). The B13
   lead could drop its "no::keep running rounds" option (TX:4254) and offer three new options instead. That
   makes the packet class C and the session ⛔, with no check anywhere. cc-decide does not verify the class.
   Any later `--gates`/`GATES_ALL` field can be gamed the same way. **Fix (text):** *if one option is the
   frozen scope or "no change", the packet is class B whatever its other options*. Have the code pairing
   reject `--class C` when an option's outcome restates the scope line.
4. **"Every remaining in-scope item waits"** (`D1:279`) is the model's own assertion. D1 says it has no
   refusal for a non-arming agent (`D1:807-808`). That gap matters for efficacy, not for loops.

---

## 5. False-block amplification through the shared DoD store (minor)

R-2 turns intake capture from occasional (PreCompact, `/handoff`) into something every writing session does.
The ledger reads the store **by worktree, not by session**:
- `dod_filter_for` keeps a toplevel and its predecessors (`hooks/lib/dod-path.sh:236-243`);
- `DOD_SCOPE` is the newest Scope line in that stream (`scripts/wrap-ledger.sh:907-924`).

So in a shared checkout, every session's `DOD_SCOPE` is whichever sibling set a scope last.

One field already turns that into a 🔧: `DRAIN_SCOPE=1` whenever the newest line contains "backlog" or
"drain" (`:945`). The session then gets `CLOSE_FLOOR=1` (`:1491-1498`), which ranks as 🔧 (`:2670`). R-10 says
"On 🔧 … arm".

Measured with an awk/grep pass over `~/.claude/autonomy/dod/*.md`:
- 17 toplevels have scope captures from two or more sessions; `claude-infrastructure` main alone has 23 sessions;
- 50 of 362 frozen lines match `backlog|drain`.

A sibling's drain-scoped intake therefore false-🔧s every other session in that checkout. completion-assert
bounds this at 3 per session (`COMPLETION_MAX`), and the mechanical arm needs dirt. The model, though, is told
to arm. The defect existed before D1; D1 raises the rate. **Graft note:** a `LOOP_OPEN` keyed on `DOD_SCOPE`
would carry the same crosstalk and false-block a sibling's ⛔ close. Key it on the session lineage
(`_dod_lineage_blocks`, `hooks/dod-persist.sh` § lineage), not on the toplevel.

A related case: a reused pane receives up to 3 predecessor sessions' contracts (`CC_DOD_LINEAGE_PANE_MAX`,
`hooks/dod-persist.sh:287`). If an unrelated session in that pane gets the B13 loop as THE CURRENT CONTRACT
before it freezes its own scope, R-2 and R-10 tell it the loop is open work to arm on.

---

## 6. The self-wake timer becomes a polling loop for legitimate stops (major)

R-6 (slim): "While a decision you filed is open, keep a `cc-await-ping` timer" (`D1:279`). The rule has no
condition on having ungated work, and the slim text has no back-off. The doubling is in G-4 only, which no
session loads. The default timeout is 1800 s, and a timeout exits 2, which wakes the session through the
task notification (`bin/cc-await-ping` header, `--timeout … default 1800; exit 2`).

The rule applies to legit all-gated stops (money, credential), to E0 read-only sessions that file decisions
(`R:99`), and to sessions that are finished and hold a 7-day class-B packet (`b4780d7bb60e`).

Measured latency of October class-C packets, `jq -s` over `created`/`resolved`: n=204, p50 7.9 h, p75 22.7 h,
p90 66.7 h. At a fixed 30-minute timer that is about 16 wakes at p50 and about 133 at p90 (estimated: hours ×
2). 48 class-C packets are open right now (measured).

This contradicts the legit-stops constraint C6: wake "only when C1's check says ungated work remains, and cap
it" (`maps/legit-stops.md` §6). It also stacks with boundary-handoff. At ✅ (class B) and ≥35% fill, the
idle re-arm (`IDLE_REARM_MIN`=30, `hooks/boundary-handoff.sh:816-832`) re-fires free-win on each 30-minute
wake, so each wake costs two turns.

The bound today is only that fill grows until S:166's "Idle … at 35% or more: recycle" applies (estimated).
**Fix:** keep the timer only while ungated work in this session waits on the answer; put the doubling in the
slim line; exclude teammates, subagents and E0 turns.

---

## 7. The shared-cwd sentinel undermines L1's "mechanical refusal" (minor)

The continuation sentinel is keyed on `config-dir|cwd` (`hooks/lib/continue-sentinel.sh`,
`continue_sentinel_for`). The armed path has no teammate or assignee abstain. It clears any sentinel whose
stored sid differs from the stopping session's (`hooks/session-continue.sh:1355-1361`).

Under D1 a loop lead stays armed for days, and every Stop of a teammate or peer in the same checkout and
account clears the lead's chain without a trace. A teammate that follows R-10 overwrites the lead's sentinel,
and the lead's next Stop clears it. In the other direction, a subagent `set` (same sid, §4.2) replaces the
lead's step, and the lead is then blocked on a subagent's stale step. That is bounded by the cap of 8 or by
the idle-repeat skip.

D1's claim that "One compliant action turns into a mechanical refusal for the rest of the work" (`D1:177`)
holds only for a lead that is alone in its cwd.

---

## 8. Legit-stop controls, checked one by one

| Control | Under D1 | Verdict |
|---|---|---|
| Genuine C10/C6/permission/credential gate that gates all remaining work | No new hook block. completion-assert's `blocked-answered` is untouched (`hooks/completion-assert.sh:1218-1231`). R-6 permits the stop. Cost: the §6 polling | OK, plus §6 |
| Gated act inside the frozen scope (L5/L6/L7) | The slim R-6 reads it as ungated (§3) | **Weakened** |
| Research-program session | R-2 and R-10 do not name the exemption; R:77 is more specific (`D1:726-731`). A program plan written "repeat until …" now reads as an open loop in R-2 | Minor conflict |
| Fired peer | Its intake `set` enters the shared store (§5). If it holds a decision, it polls (§6) and keeps the lead's custody 🔧 open | Minor |
| Teammate | Sentinel collision (§7). R-6 asks it to keep a timer, but its lead wakes it over the teammate channel (`hooks/session-continue.sh:859`). Whether a teammate's background Bash delays TeammateIdle is unmeasured | Minor, unmeasured |
| Read-only turn | R-10 says clear. R-6's timer still applies to an E0 turn that filed (§6) | Minor |
| Goal with an operator-only conjunct | Unchanged. R-6 exempts the timer under `/goal`. D1 does not fix the non-clearing goal (`docs/lessons/a-goal-condition-containing-an-operator-only-act-never-clears.md`) | Unchanged |
| Money-landing repo at 📦 | 📦 is still terminal (R-6 keeps the clause). ⛔ masks 📦 in the ladder (`scripts/wrap-ledger.sh:2604-2620`), so a ⛔-armed chain there could list "land" as a step. Only the ship-policy text (R:58) stops it | Minor |
| Operator says "hold off" (not a kill phrase) | The armed chain keeps going (`KILL_RE`, `:386`), and R-6's "never what the frozen scope directs" argues against honouring the hold | Minor; G-3 lists "the operator's own words this session" as a ruling, but not in R |

---

## 9. What D1 must add to be sound on this lens

1. Loop meter stop, re-ask valve and intake cap (§1.3) in R-2, R-7 and R-10.
2. "A wait is never a continuation step" in R-10 (§2). In the code pairing, put the `list` verbs of
   `cc-decide`, `cc-custody` and `cc-backlog` in `ro_word`.
3. Port G-4's carve-out ("the gated act itself still waits") into R-6 (§3).
4. Only the scope owner writes `Scope (frozen):`, `session-continue.sh set` or `dod-persist.sh set`; subagents and
   workflow slots never do. A loop ends only on a measured X or the operator's words (§4.1, §4.2).
5. "A packet with a status-quo option is class B" (§4.3).
6. The timer only while ungated work waits on the answer, with doubling in slim (§6).
7. Correct `D1:33` ("zero new loop risk"), `D1:713` (ii) and `D1:714` ("bounded by the scope"). State the
   real bounds and the account-switch hazard. The repo's own rule is that a false bound claim is the defect
   (`G:1136-1137`).
8. For the recommended `LOOP_OPEN` pairing, key it on the session lineage, not on toplevel `DOD_SCOPE` (§5),
   and latch it per (sid, scope-line hash), so that a non-converging loop does not re-arm a floor for ever.

---

## 10. Best ideas worth grafting

- **Class-B routing removes the false ⛔ with no code.** `BLOCKED` counts class C only (`scripts/wrap-ledger.sh:1510`,
  `list --open --class C`), so re-filing a judgment call as B releases the rung mechanically (`D1:121-123`).
- **The "gates" definition** (gates only the act and work built on its answer). Graft it **with** the G-4
  carve-out in the slim text.
- **Never a `- [ ]` box for a loop.** The append-only store would make it a permanent, inherited 🔧
  (`hooks/dod-persist.sh:162`, `persist_dod` at `:172`; behavioural control T9).
- **`--default-effect no-change --project <repo>` in the class-B template**, which closes the misrouted-default
  path (`df779857c4ff`).
- **Standing grants section in S** with the full envelope: `git archive` only, `-s read-only`, 80% weekly-meter
  stop, no paid API, personal data still an ask, and "adding, widening or revoking a grant is class C". It is a
  model for the loop meter stop D1 lacks.
- **Positive-control tests of the cited contracts** (T7 ruling search, T9 append-only store, T11 rung-blind
  armed path). They go red when the machinery the rule relies on changes.
- **Name open decision ids in a recycle brief**, because a successor's ledger counts only its own packets
  (`scripts/wrap-ledger.sh:1529`).
- **Budget one-in-one-out**, measured with the repo's own `instruction_budget.py`.
