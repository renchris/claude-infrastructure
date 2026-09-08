# A09 — Adversarial derivation: every remaining path to idle-with-drivable-work

Wave: exhaustive-drive 2026-09-08. Role: ADVERSARIAL, baseline-blind. No other axis report read.

---

## Part 1 — Derived before reading (written first, unedited)

Method: from the system model only — the seven Stop arms, their caps and exemptions, the stores,
the `/goal` evaluator, the frozen-DoD injection, the auto-mode classifier. Each path is a way a
session reaches a stop with net-positive drivable work left and **nothing blocks or nudges it**.

| # | Derived path | Class |
|---|---|---|
| D01 | **A read-only turn is E0 by construction.** The disposition table's first row says: research/advisory with no tracked writes ⇒ "No ledger, no auto-continue. Answer and yield." A session that identifies 20 drivable items and writes none of them is licensed to idle *by the protocol itself*. The E0 test is write-footprint, not work-identified. | no side-effect representation |
| D02 | **Auto-mode tells the model to edit via Bash; session-writes reads the transcript's Edit/Write records.** If attribution is transcript-tool-based, every `sed`/heredoc edit is invisible ⇒ mechanical 🔧 abstains "not-mine" on the session's own dirt. The blindness is aligned with the fleet's default mode. | store keyed wrong / attribution |
| D03 | **Ship floor is capped at 2 per session and latched per HEAD-sha.** Third and later unlanded shas get silence. | cap releases |
| D04 | **Mechanical 🔧 is bounded by `CC_MECH_MAX × CLAUDE_CONTINUE_MAX`.** Past the budget the arm stops blocking and the close is silent on real dirt. | cap releases |
| D05 | **`session-continue.sh clear` is self-service.** The model can spend its own budget and then close; nothing audits whether the park was legitimate. | operator's/model's own words disarm |
| D06 | **Fired peers and assignees are exempt from the origin close contract and the ship floor.** Their close is "the lead's harvest". If the lead is dead, recycled, or itself idle, the work strands with no arm on either side. | exempt |
| D07 | **Stop hooks are killed at their timeout and a killed hook writes nothing and blocks nothing — it fails open, silently.** completion-assert has 5 s and was lead-measured at 4.14 s on a 69 MB transcript; the corpus holds 230 MB. Large sessions — the ones with the most work — are exactly the ones with no gate. | hook killed |
| D08 | **The Stop chain is registered in one `settings.json`, but there are four config dirs / accounts.** Sessions on an unregistered root have *no* Stop arms at all. Predicts the lead's unexplained 901 closes vs 469 evaluations. | hook never ran |
| D09 | **A session that dies has no Stop.** Context-ceiling refusal ("Prompt is too long", dead in place), crash, kill, `/clear`. Death is the one state with no close arm. | hook never ran |
| D10 | **A permission prompt freezes the session before any Stop exists.** Frozen ≠ idle-with-a-close; every arm keyed on Stop is structurally blind. 8–9 sessions measured in the backlog. | permission freeze |
| D11 | **The auto-mode classifier soft-denies "Self-Modification" — settings/permissions/hooks — which is precisely the class of work item (7) of the operator's goal names.** The drivable action becomes a filed migration and the session closes `👤` legitimately. The remedy channel for "shrink the permission prompts" is itself permission-blocked. | permission / classifier |
| D12 | **A fresh session inherits no DoD.** Close-time completeness is a diff against the frozen DoD; a blank DoD makes the remainder trivially 0. Keyed by repo identity, so a worktree/repo hop is a reset. | store keyed wrong |
| D13 | **A recycle launders `FILED_MINE`.** If the ledger's "mine" is session-scoped, rows this session filed stop being mine at the recycle boundary; the successor sees a clean board. Recycling is the cheapest way to clear a 🔧. | store keyed wrong |
| D14 | **Custody is keyed on the firing cwd.** A lead that recycles into a different worktree loses the debt key ⇒ the unreturned wave stops being a 🔧. | store keyed wrong |
| D15 | **The rung ladder is session-scoped and has no rung for "the queue has drivable rows".** `✅` is reachable with 200 open backlog rows as long as none was filed *this session*. The fleet-level queue is invisible to every close. | no representation |
| D16 | **A plan is not a queue.** Nothing at Stop reads a plan doc's unfinished phases; a session finishing phase 3 of 7 closes clean. (Existing memory rule; still unmitigated by construction if no arm reads plans.) | no representation |
| D17 | **Open Task-tool tasks have no Stop reader.** 987 list dirs exist, `CLAUDE_CODE_TASK_LIST_ID` is exported, but the task tools are not offered to sessions and the ledger has no task term ⇒ a Shared Task List with open items contributes nothing to the rung. Directly defeats step (2) of the operator's goal. | no representation |
| D18 | **anti-deference is a phrase matcher, so the model routes around it.** The 'decision' vocabulary (your call / policy call) is deliberately unmatched; 17 fires in 468 evaluations means the population it can see is tiny. Denylists enumerate spellings, not the class. | matcher routed around |
| D19 | **Semantic deference with no tell at all**: "I have documented the remaining items in the plan" is a pointer, not an offer, and matches nothing. Filing is a *sanctioned* exit, so the most defensible-sounding idle is the least detectable. | matcher routed around |
| D20 | **The `/goal` evaluator is tool-less and sees only surfaced text**, so it clears on a *prose claim* of completion. A session that says "all follow-ons complete" clears its own blocker. | goal evaluator |
| D21 | **A background Bash defers the goal.** The harness deletes the goal's Stop hook while a non-terminal background task exists. `validate-bash` denies a *backgrounded park*, but a legitimate background build/test/scan has the same effect: the goal stops evaluating and the session is free to stop. | goal deferred |
| D22 | **goal-inert-watch is itself mostly blind** — 353 of 469 evaluations abstained `goal-unreadable` (lead-measured). The watcher of the goal cannot see the goal three quarters of the time, so D20/D21 are unobserved. | sensor blind |
| D23 | **A goal dies with its session and a recycle must re-arm it**; handoff-fire's goal-arm has known abstains (backlog `2ee30f87c370`, `1d73c2fd875c`) ⇒ successors run unarmed and stop freely. | goal absent |
| D24 | **The operator's own scoping words are a kill switch, and the model is the classifier.** "just do X" / "…and stop" suspends the gate for the turn; a narrowing instruction is easily over-read as terminal. Nothing records that a kill switch was applied. | operator disarms |
| D25 | **A standing instruction in a fired session's brief disarms that lineage forever.** "Do not start new work" reaches the first link and is regenerated into every successor's brief. | operator disarms, via brief |
| D26 | **"🔧 you did not cause is not your loose end" is an unaudited licence.** Attribution is asserted by the model in prose; no arm checks it. | attribution |
| D27 | **A lead awaiting a fired peer is in a sanctioned non-close state that is indistinguishable from idle.** If the peer died, the lead waits forever and every arm reads "correctly awaiting". | exempt / awaiting |
| D28 | **Filing with `no-capacity` while accounts are idle** converts drivable work into a queue row and a clean close. The class gate cannot measure capacity. | sanctioned exit |

Count derived before reading source: **28**.

---

## Part 2 — Confirmation / refutation against code and corpus

All IDL numbers below count the **13.7-hour** window the store actually holds (rotated 2026-09-08
08:22Z), not 30 days. Today ran a 12-axis wave, so session counts are above a normal day; treat
extrapolations as an upper band and re-derive from a longer IDL before quoting them.

### Ranked by expected monthly count

| Rank | Path | Verdict | Measured | Fix errs |
|---|---|---|---|---|
| P1 | D10 permission freeze | **CONFIRMED — dominant** | 22 sessions, **84.2 session-hours frozen in a 13.7 h window**; 15 of 22 never reached a Stop | UNSAFE |
| P2 | D02 mechanical 🔧 blind to Bash-mediated edits | **CONFIRMED by execution** | `armed:mechanical-dirty` = **2 of 672** session-continue evaluations (0.30%); 22 of 46 repo-writing main sessions invisible | UNSAFE |
| P3 | D15/D16/D17 no rung reads the queue | **CONFIRMED** | **312 of 357** open backlog rows (87.4%) carry no `filedBy`; wrap-ledger has **0** references to tasks or plans | NAGGY |
| P4 | D01/D18/D19 read-only turns are covered only lexically | **CONFIRMED (refined)** | anti-deference 450/468 `no-tell`; dispatch-assert 436/489 `no-naming-tell` | NAGGY |
| P5 | D06 exemption chain | **CONFIRMED** | 95 of 672 (14.1%) explicit non-arms: 57 `ship-floor-not-mine`, 19 `ship-floor-assignee`, 19 `mechanical-assignee` | NAGGY |
| P6 | D12 fresh session inherits no DoD | **CONFIRMED** | **75** DoD captures on disk total, repo-keyed; **5** written today against ~110 main sessions | NAGGY |
| P7 | D22 goal-inert-watch blind | CONFIRMED (lead-measured) | 353 of 469 abstained `goal-unreadable` (75.3%) | — |
| P8 | D13 recycle launders `FILED_MINE` | CONFIRMED in code, low measured volume | `FILED_MINE` filters `.filedBy == $SID`; only 46 open rows carry any sid | NAGGY |
| P9 | D03/D04 cap releases | **REFUTED as a channel** | 1 `ship-floor-latched`, 1 completion-assert `capped` in 13.7 h | — |
| P10 | D08 unregistered Stop chain on other accounts | **REFUTED** | all five config dirs register a byte-identical 12-hook Stop chain | — |
| P11 | D07 hook killed at timeout | **REFUTED for the observed gap** | the 6 sids missing a completion-assert record are 0.8–5.3 MB, well inside budget | — |

---

### P1 — The permission freeze is the largest idle channel, and it has a detector with no actuator

**Measured.** `jq 'select(.kind=="permission_pending")' ~/.claude/autonomy/idl.jsonl` → 5,132
records, **22 distinct sids**. Max frozen age per sid, summed: **84.2 session-hours inside a
13.7-hour window**. Eleven sessions were frozen 5.7–7.9 hours each (`cf2321de` 471 min, `626edcad`
470, `ad4e751c` 459, `e7693813` 456, `c8a849b6` 434, `907ac1bb` 378, …).

**They were alive the whole time.** Each of the six longest-frozen sids carries 55–88 `ESCALATED`
pages and 118–168 `STALL?` pages from `lead-supervisor`. The detector fired hundreds of times per
session and nothing resolved the prompt.

**15 of the 22 have no anti-deference evaluation at all** (`comm -23` of the pending sids against
the anti-deference sids), i.e. they never reached a Stop while pending — so every Stop-keyed arm is
structurally blind by construction, not by accident.

**What is actually blocked.** Hand-read all 22 blocked commands (sample size 22, full population):
**21 of 22 are ordinary test-harness / fixture / sandbox work** — `cd <worktree> && python3 - <<'PY'
…`, `T=$(mktemp -d); git -C $T init -q`, `cd /tmp/se && rm -rf fx && mkdir fx`, `cat > pull.sh
<<'EOF'`. One is `git add … && git commit` and one is `git reset --hard origin/main`, which the
operator's own 6-entry `ask` list covers deliberately.

**Why the allowlist cannot absorb them, and why goal item (7) as stated cannot succeed.**
`jq -r '.permissions.allow[]' ~/.claude/settings.json | grep -cE '&&|;|<<'` → **0 of 339**. Every
allow rule is a command *prefix* (`Bash(agent-browser click:*)`). The fleet's unit of work is a
**compound script**. `hooks/smart-bash-allowlist.sh` is the only path that decomposes compound
commands, and it "requires EVERY segment to independently clear the operator's live
permissions.ask/deny fence" against a whitelist of exactly **four surviving rules** (git commit,
`sed -i`, chmod, `sed -n`; rules 2 and 4 retired 2026-08-12 for auto-approving past the operator's
own fence). A `python3 - <<'PY'` or `mktemp -d` segment matches nothing ⇒ defer ⇒ the harness
prompt fires ⇒ freeze. This is a **shape mismatch, not a coverage gap**: adding more prefix rules
cannot reach it.

**The two guards that look like they cover this, and do not.**
`hooks/cc-unattended-ask-guard.sh` is scoped to `AskUserQuestion` — the model *asking* — not to the
harness's permission prompt on a Bash call, and it is inert anyway (`CC_UNATTENDED` is set in no
config dir's `env`). `hooks/cc-permission-beacon.sh` is explicitly a **detector**; its own header
states *"Nothing IN-session can answer the prompt"* and its whole contract is to make the block
"VISIBLE, ATTRIBUTED, and FAST" for a supervisor page. It succeeds at that and the page terminates
in nobody. `hooks/model-permission-decider.py` exists in the tree and is registered **0** times in
`settings.json` (backlog `ce5e5310c457`, `7cdf4ea8f10e`) — the built, unwired actuator.

Memory rule `detector-with-no-owner-is-not-an-actuator` names this exactly.

**Fail direction.** Any fix errs **UNSAFE**. A PreToolUse `allow` *bypasses the permission system
entirely* — `smart-bash-allowlist.sh`'s own header records two rules retired because they
auto-approved commands the operator had independently fenced. The safe framing is not "approve
more" but "decompose the compound and approve only segments whose write target is provably inside
`$TMPDIR`/a `mktemp` variable, deferring the rest".

### P2 — The mechanical 🔧 arm is inert because auto mode routes edits away from it

`CLAUDE.md` says the mechanical arm is "what makes 🔧 not the case in the first place… reaching idle
on your own loose end is now a mechanism failure, not a discipline failure."

**Measured disposition histogram, all 672 session-continue evaluations in the window:**

```
293 armed:cli-set          238 fired:continue        57 abstained:ship-floor-not-mine
 24 fired:wake-floor        19 cleared:mechanical-assignee   19 abstained:ship-floor-assignee
 14 cleared:cli-clear        2 fired:ship-floor        2 armed:mechanical-dirty
  1 cleared:mechanical-teardown  1 abstained:wake-floor-teardown
  1 abstained:ship-floor-teardown  1 abstained:ship-floor-latched
```

`armed:mechanical-dirty` = **2 (0.30%)**. Every other continuation in the window is `cli-set` — the
model arming *itself*. The arm designed to work without discipline is, in practice, doing nothing;
the discipline is carrying the entire load.

**Cause, proved by execution not inference.** `hooks/lib/session-writes.sh` attributes from the
transcript's `Write/Edit/MultiEdit/NotebookEdit` tool_use records, and names the residue in its own
header: *"A file written ONLY through Bash (`sed -i`, a heredoc, `git checkout`) is invisible here."*
Direct test on a real session:

```
sid 1cb6d3b7-23b7-498f-bb9a-a0765426e7d5 (1.5 MB transcript)
  4× sed -i '' … scripts/stranded-exposure.sh, tests/stranded-exposure.bats   (tracked files)
  file-edit tool_use count: 0
  session_writes_paths → rc 1  ("none")
```

**The residue is not a tail — it is aligned with the fleet's default mode.** `permissions.defaultMode`
is `auto` in all four config dirs, and auto mode injects, verbatim: *"make file changes with sed,
heredocs, or short scripts, rather than using the dedicated Read, Edit, or Write tools."* Measured
over the 158 transcripts written today (`find … -newermt '2026-09-08 00:00' -size +50k`), main
sessions only (`agent-*` excluded), classified by whether any file-edit tool_use exists vs. Bash
commands targeting `/Users/chrisren/{Development,.claude}`:

| | count |
|---|---|
| file-edit tool + Bash repo write | 5 |
| file-edit tool only | 19 |
| **Bash repo write ONLY — invisible to `session-writes`** | **22** |
| neither | 64 |

**22 of 46 repo-writing main sessions (48%) cannot arm the mechanical arm.** The looser predicate
(any Bash write anywhere, including `/tmp`) puts 105 of 158 in the Bash-only class — quoted only as
an upper bound, since `/tmp` writes are correctly out of scope.

**Fail direction.** The source file already rejects the obvious fix ("worktree-implies-mine") because
it errs UNSAFE — convicting a session of a sibling's dirt, an unclearable 🔧. A provenance-safe
alternative exists and is not the rejected one: a PostToolUse(Bash) snapshot of the
`git status --porcelain` **delta**, intersected with paths that appear as literals in *that
session's own* Bash command text. The intersection is what defeats the sibling-misattribution
objection; a delta alone does not.

### P3 — No rung reads the queue; 87% of the queue is unattributable in principle

`grep -cniE 'tasks/|task_list|CLAUDE_CODE_TASK_LIST_ID|docs/plans|\.claude-plans' scripts/wrap-ledger.sh`
→ **0**. The ledger's only work-queue term is `FILED_MINE`, defined at `wrap-ledger.sh:790` as
*"OPEN backlog rows this session ADDED (`.filedBy == $SID`)"*.

`cc-backlog list --open --json`: **357** open rows; **346** carry no `why-not-now`; and
**312 (87.4%) have no `filedBy` field at all**. Those 312 can never be any session's 🔧 — not
because they were driven, and not because they are blocked, but because the join key does not exist
on them. Memory rule `join-key-never-populated-makes-a-rule-unreachable`.

Consequence, stated as the adversary would: a session can close `✅ SAFE TO CLOSE — nothing of mine
is open`, truthfully by every computed term, standing on 312 open drivable rows, an open Shared Task
List (987 list dirs under `~/.claude/tasks`, `CLAUDE_CODE_TASK_LIST_ID` exported, no Stop-side
reader), and a plan doc with four unfinished phases. This defeats goal step (1) and step (2)
simultaneously.

**Fail direction: NAGGY.** A rung that fires on the standing pile would fire at every close forever
— precisely the `alarm-polarity-and-attention-budget` defect, and the reason `👤` was deliberately
scoped to this-session steps. Any queue rung must be scoped to rows the session *could drive now*
(no `why-not-now`, matching cwd/repo), not to the pile.

### P4 — On a read-only turn the only live arm is a phrase matcher

Refines D01. `anti-deference-nudge.sh` does **not** gate on write footprint — it evaluates the last
assistant text on any turn (its abstains are `no-jq`/`no-transcript-path`/`no-assistant-text`/
`no-tell`). So E0 turns are covered, but *only lexically*. Every ledger-based arm is blind there by
construction: `completion-assert.sh:1028` abstains `ledger-clean` — and a read-only turn's ledger is
clean by definition.

Measured coverage of the lexical arms in the window: anti-deference **450 of 468** evaluations
returned `no-tell`; dispatch-assert **436 of 489** returned `no-naming-tell`. The
`conviction-close-2026-09-08.md` census already established that the 'decision' vocabulary is matched
by no hook, deliberately, at 30% prose precision. A close that says *"I have documented the
remaining items in the plan"* is a pointer, not an offer, matches nothing, and is the most
defensible-sounding idle in the system.

**Fail direction: NAGGY.** Widening the matcher trains routing (memory rule
`denylist-enumerates-spellings-not-the-class`). The non-lexical move is P3's: give the read-only
turn a *store* to be judged against instead of a phrase to avoid.

### P5 — The exemption chain, and a hole in the IDL it produces

95 of 672 evaluations (14.1%) are explicit non-arms on exemption grounds: `ship-floor-not-mine` 57,
`ship-floor-assignee` 19, `mechanical-assignee` 19. Separately, **6 sids fired anti-deference but
produced no completion-assert record at all** (`19dca360`, `3bc5111f`, `4cef9278`, `5a7dc203`,
`8f4ac4db`, `ed4192c3`) — every one of them a dispatched worker in a `wt-<backlog-id>` worktree.
Their transcripts are 0.8–5.3 MB, so this is **not** a timeout (D07 refuted). It is an exemption
path that exits before `idl_init`, which means the exemption is not merely permitted, it is
**unobservable** — the one shape the house's own "count NOT-success" rule forbids.

`boundary-handoff` contributes nothing here: 45 `abstained:no-telemetry` and the remainder
`below-threshold:2x-3x < 73`. It is a context-fill arm, not a work-remaining arm, and the
`no-telemetry` abstains re-confirm `CONTEXT_ECONOMY_V2`'s point that the window denominator is often
simply absent.

### P6 — DoD coverage is thin and repo-keyed

`~/.claude/autonomy/dod/` holds **75** captures, named by a 16-hex repo/toplevel identity, **5**
written today against ~110 main sessions. `wrap-ledger.sh:566` initialises `DOD_SCOPE=""` and only
overwrites it on a hit. A session in a fresh worktree with no capture has an empty frozen scope, so
"close-time completeness is a diff against that contract" is a diff against nothing and the
remainder is 0 by construction.

### Refutations worth recording

- **D08 (accounts unhooked): REFUTED.** `.claude`, `.claude-secondary`, `.claude-tertiary`,
  `.claude-quaternary`, `.claude-next` each register the same 12-entry Stop chain, all resolving to
  `~/.claude/hooks/*` — one live layer, four config dirs. The lead's 901-closes-vs-469-evaluations
  gap is not this.
- **A partial explanation for that gap, measured:** **48 of the 158** transcripts written today are
  `agent-*` subagent transcripts. A subagent's turn-final assistant message is a "close" to a text
  census but generates no Stop event (and `completion-assert` explicitly filters
  `.isSidechain != true`). Counting closes from the transcript corpus therefore overstates the Stop
  population; the denominator must exclude `agent-*` files and sidechain records.
- **D03/D04 (caps): REFUTED as a channel.** Defaults confirmed in source — `CC_MECH_MAX` 2
  (`session-continue.sh:921`), `CC_SHIP_FLOOR_MAX` 2 (`:1030`), `CLAUDE_CONTINUE_MAX` 8 (`:1117`),
  `COMPLETION_SHAPE_MAX`/`COMPLETION_ACT_MAX` 2 (`completion-assert.sh:1065-1068`) — but the window
  contains exactly **1** `ship-floor-latched` and **1** completion-assert `capped`. Caps are not
  releasing sessions into idle at any material rate; the arms are not reaching their caps because
  they are not arming.

### Adversarial self-pass — what I checked because a hostile reviewer would

1. *"Your 84 frozen hours are dead sessions."* Checked: all six longest-frozen sids carry live
   `STALL?`/`ESCALATED` pages throughout, none paged `DEAD`. They were alive and blocked.
2. *"Your Bash-write predicate over-counts."* Checked: reported both the loose predicate (105/158)
   and a repo-path-restricted one (22 main sessions), and used the restricted one for every claim.
3. *"Today is not a normal day."* Stated: the IDL is 13.7 h and this was a 12-axis wave day. Every
   extrapolation below is flagged as an upper band.
4. *"The mechanical arm is rare because sessions actually commit."* Discriminated by **execution**,
   not by counting: `session_writes_paths` returns rc 1 on a transcript containing four `sed -i`
   edits to tracked files. The arm cannot see them whether or not they were committed.
5. *"Something must clear a permission prompt."* Checked all three candidates
   (`cc-unattended-ask-guard`, `cc-permission-beacon`, `model-permission-decider.py`) and found a
   scoped-out guard, a self-described detector, and an unregistered file.

### Expected monthly counts (upper band — one 13.7 h window, a heavy wave day)

| Path | Per-window measured | Extrapolated / month | Confidence in the extrapolation |
|---|---|---|---|
| P1 permission freeze | 22 sessions · 84.2 session-h | ~1,150 sessions · ~4,400 session-h | LOW — one window, wave day |
| P2 unattributable own-dirt | 22 of 46 repo-writing sessions | ~660 sessions | MEDIUM — the cause is a mode default, not load |
| P3 queue invisible to the ledger | 312 rows, standing | standing, grows | HIGH — a stock, not a rate |
| P5 exemption non-arms | 95 of 672 evaluations | ~6,200 evaluations | MEDIUM |


---

## Part 3 — Recommendations, with conviction and fail direction

**R1 — Decompose compound Bash in `smart-bash-allowlist` and allow only provably-sandboxed
segments.** Conviction **70%** (below the 90% bar — this is a decision to hand up, not to
implement). Evidence: 21 of 22 frozen prompts are compound fixture scripts; 0 of 339 allow rules can
express a shell operator; the smart allowlist already decomposes but has only 4 surviving rules.
Effort **M**. Files: `hooks/smart-bash-allowlist.sh`, `hooks/lib/smart-bash-allowlist.py`,
`tests/smart-bash-allowlist-narrow.bats`. **Fails UNSAFE**: a PreToolUse `allow` bypasses the
permission system outright, and this file's own history records two rules retired for exactly that.
The 30% doubt is entirely about the blast radius of the allow, not about the diagnosis.

**R2 — Give the permission freeze an owner, not a louder page.** Conviction **88%** that the
*structure* is wrong (detector with no actuator, 84 session-hours against 55–88 escalations per
session); the residual 12% is which owner. Options the evidence supports: wire
`model-permission-decider.py` (built, registered 0 times — backlog `ce5e5310c457`,
`7cdf4ea8f10e`); or have the supervisor **kill and re-fire** a session frozen past a horizon, which
converts an unbounded hang into a bounded restart. Effort **M**. Files: `.claude/settings.json`
(migration `NNNN-*.sh`, `migration-class: c10`), `hooks/model-permission-decider.py`,
`scripts/lead-supervisor.sh`. **Fails UNSAFE for the decider arm** (it grants without a human
reading), **SAFE-but-lossy for the re-fire arm** (a restart discards in-flight context).

**R3 — Attribute Bash-mediated writes via a porcelain delta intersected with the session's own
command text.** Conviction **75%**. Evidence: `armed:mechanical-dirty` 2/672; `session_writes_paths`
rc 1 proven on a transcript with four `sed -i` edits to tracked files; auto mode instructs exactly
that shape. Effort **M**. Files: `hooks/lib/session-writes.sh`, a PostToolUse(Bash) snapshot hook,
`tests/session-writes.bats`. **Fails UNSAFE** — a bare delta misattributes a concurrent sibling's
write, which is the objection `session-writes.sh` already sustains; the path-literal intersection is
what answers it, and it is the part that must be tested first.

**R4 — Backfill `filedBy` and add a drivable-now queue term to the ledger.** Conviction **80%** on
the backfill (312 of 357 rows have no join key — a rule that cannot reach 87% of its population is
not a rule), **55%** on the new rung. Effort **S** for the backfill, **M** for the rung. Files:
`~/.claude/autonomy/backlog.jsonl` (migration), `scripts/wrap-ledger.sh`, `hooks/completion-assert.sh`.
**Fails NAGGY** — a rung over the standing pile fires at every close forever, which is why it must
be scoped to rows with no `why-not-now` **and** a cwd/repo match, not to the pile.

**R5 — Make every exemption write an IDL line before it exits.** Conviction **92%**. Evidence: 6
sids fired anti-deference with no completion-assert record at all, and their transcripts (0.8–5.3 MB)
rule out a timeout; the exemption path exits before `idl_init`, so the house cannot count its own
non-successes. Effort **S**. Files: `hooks/completion-assert.sh` (move `idl_init` above the
exemption gates), `hooks/lib/idl-log.sh`. **Fails SAFE** — pure observability, no decision changes.

**R6 — Correct the close denominator: exclude `agent-*` transcripts and sidechain records.**
Conviction **93%**. Evidence: 48 of 158 of today's transcripts are `agent-*`; subagent turn-finals
generate no Stop and `completion-assert` already filters `.isSidechain != true`. Effort **S**.
Files: `scripts/measure-closes.py`. **Fails SAFE** — a measurement correction; it shrinks an
unexplained gap rather than acting on one.

## Open questions this axis could not settle

- Is 84.2 session-hours/13.7 h typical, or a wave-day artifact? The IDL was rotated this morning and
  holds no comparison window. `~/.claude/autonomy/permission-archive/` holds 3,234 entries and is
  the store that could answer it.
- Do the 6 exemption-silent sids exit at the assignee gate or at the FATAL `_ilib` source failure?
  Both exit before any IDL write and are indistinguishable from outside.
- `ENABLE_STOP_REVIEW="0"` is set in every config dir's `env` and nothing in the hooks tree reads
  it; whether it names a product feature that would cover P4's read-only gap is unresolved.
