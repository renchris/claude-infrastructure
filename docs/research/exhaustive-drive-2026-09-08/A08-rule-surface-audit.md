# A08 — Rule-surface audit: CLAUDE.md vs the 7-step exhaustive-drive workflow

Wave: exhaustive-drive 2026-09-08. Read-only. Every number below carries its command and population.
Surfaces read: `~/.claude/CLAUDE.md` (918 lines, 84,249 B) · worktree `CLAUDE.md` (byte-identical —
`diff` empty, both 84,249 B) · `.claude/CLAUDE.md` (30 lines) · `commands/wrap.md` (158) ·
`commands/are-we-done.md` (the "are-we-done skill" is a **command**, not a skill:
`find … -name '*are-we-done*'` returns only `commands/are-we-done.md`; `~/.claude/skills/are-we-done/`
does not exist) · `commands/handoff.md` (744) · `migrations/README.md`.

---

## VERDICT

The rule surface **covers steps 1, 4 and 6 well and mechanically**, **contradicts step 5 outright**,
and **has no rule text at all for steps 2, 3 and 7**. The single most damaging finding is not a
missing rule but a *live mechanism that silently disarms the enforcement the workflow depends on*:
the kill-switch regex matched **29 user messages in 8 days, of which 26 were machine-authored**
(subagent briefs, fire/recycle briefs, teammate mail, task-notifications) and **0 were a genuine
operator stop order**. Its 3 genuine-operator hits are the strings `Count to 1 and stop.`,
`Count to 2 and stop.`, `Count to 3 and stop.` — throwaway probes.

---

## 1. Coverage table — operator step → rule text → enforcing arm

| Step | Rule text that covers it (verbatim anchor) | Enforcing arm | Verdict |
|---|---|---|---|
| **1** follow-on/loose-end items are mandatory, never optional | `CLAUDE.md:577` *"**Only ⛔ and 📦-in-reso may end a turn holding work.**"* · `:580` *"**🔧 never yields.** Ending a turn on 🔧 is a defect… 'I have identified the remaining items' is not a close; the items are the work."* · `:493` Follow-On Gate F1–F4 · `:817` *"Offering is the defect"* | `hooks/session-continue.sh` (mechanical 🔧 + ship floor + wake floor), `hooks/completion-assert.sh` (false-done), `hooks/anti-deference-nudge.sh` (deference tell) | **COVERED — but only on WRITE turns.** Every floor in `session-continue.sh` is gated on `session_writes_paths` / pending mail / an armed sentinel (`:1021-1023`, `:1019` `ship-floor-not-mine`). A read-only turn that *identifies* ten drivable items trips nothing. See §2-C1. |
| **2** multiple todo items → **Shared Task List** | **NOTHING.** `grep -ic` over all six surfaces: `Shared Task List` = 0, `task list` = 0, `TaskCreate` = 0, `TodoWrite` = 0 (only hit anywhere in `skills/ commands/ agents/`: `commands/limit-recover.md`) | Hooks **already registered** in `settings.json`: `setup-task-symlinks.sh` (SessionStart), `task-mutation-index.sh` (PostToolUse), `task-quality-gate.sh` (TaskCompleted); `hooks/lib/task-helpers.sh`; 987 list dirs under `~/.claude/tasks` (lead-measured) | **MECHANISM WITHOUT RULE.** The inverse of prose-only: the store, the symlinks, the index and the TaskCompleted typecheck gate all exist and are wired; no rule tells any agent to use them, and the tools are not offered to this session (lead-measured, row `ebe84950e98a`). |
| **3** research exhaustively; **Dynamic Workflows usually optimal** | `CLAUDE.md:498` (F2) carries *"research exhaustively"* — but only inside the quoted conviction ruling, about a decision already held. `Dynamic Workflow` = **0 hits in CLAUDE.md**, 2 in `commands/handoff.md` (`:198`, `:389` — both about the `ultracode` keyword and model pinning, neither an authorization) | none | **NO AUTHORIZING RULE.** The only sanctioned Workflow-tool authorization on the box is `commands/limit-recover.md:21`: *"Invoking this command IS the authorization to call the Workflow tool for resume/re-run of the session's own workflow runs."* The harness-shipped `workflow-authoring` skill says *"Load before authoring a script for a workflow the user already opted into; **it does not itself authorize running one**"* (verbatim, present in ≥5 transcripts under `~/.claude-quaternary/projects/`). |
| **4** ≥90% convicted → send them off | `CLAUDE.md:498` F2 *"if conviction of a decision is not >90% then research exhaustively, and then implement if now >90% or then ask the user if below"* | **Fully mechanical.** `bin/cc-backlog:1783-1785` refuses an add with `conviction > CC_CONVICTION_ASK_MAX` (default 90) — *"implement it, do not file it"*; `bin/cc-decide:100` same threshold; `scripts/wrap-ledger.sh` + `hooks/completion-assert.sh` carry `UNCONVICTED_MINE` | **COVERED, best-enforced rule on the surface.** Landed today (`4ddbd77d9`, `68410ce31`). |
| **5** present the **itemized** decisions, answer-first, Pyramid/SCQA/MECE | `CLAUDE.md:828` *"**ONE COMMAND, never a list**"* · `:854` *"**Judgment items are counted, not itemized.**"* · `:813` ⛔ *"stated as **the one decision** you need"* · `:772` corollary computes ⛔ from open class-C packets | `hooks/lib/close-shape.sh` (`line-1-rung`, `close_act_missing`, `CC_ACT_WINDOW`), `hooks/operator-readout.sh` (the counted `◆` line) | **DIRECT CONTRADICTION.** `:854` says *counted, not itemized*; the operator asks for *itemized*. `:813` admits exactly one decision per close; step 5 says *decisions*, plural. The close-shape contract is built for the one-decision case. |
| **6** only stop after 1–5 | `CLAUDE.md:577`, disposition table `:445-451`, `:898` kill-switch | `completion-assert.sh` D6 origin close contract, `close-shape.sh` | **COVERED in text; blind in practice.** Measured on the IDL below: 71.4% of `completion-assert` evaluations abstain `no-close-tell` and 96.3% of `anti-deference-nudge` abstain `no-tell` — the contract is unreachable on 3 of 4 stops. |
| **7** run every command it can; **move permission prompts to the allowlist** | `CLAUDE.md:907` *"🚨 **NEVER script your own authorization** — no permission grants, `settings*.json`, allowlists or credential writes in a file you hand over"* | `settings.json` `autoMode.soft_deny`: *"**Self-Modification:** Modifying the agent's own configuration, settings, or permission files to change the agent's own behavior or permissions."* · `migrations/README.md:68,83` — a settings-touching migration **must** declare `c10` = *"staged, never run"* | **TRIPLE-BLOCKED, no sanctioned path.** Three independent arms refuse the allowlist half of step 7. Nothing forbids the *read* half: `bin/cc-permission-audit` writes nothing without `CONFIRM=1` (its own header) — and **no rule text anywhere mentions it** (`grep -rn cc-permission-audit CLAUDE.md .claude/CLAUDE.md commands/*.md skills/*/SKILL.md` → 0 hits). |

---

## 2. Contradictions, ranked by measured damage

### C1 — `E0 answer and yield` is the licence step 1 exists to revoke  *(anchor `CLAUDE.md:532`)*

> `| _E0_ read-only (no tracked writes) | — | **no readout** — answer and yield |`

`answer and yield` is a *disposition*, not merely a readout-suppression, and it is the only row in the
table that authorizes ending a turn with work identified. Confirmed mechanically: `session-continue.sh`
gates every floor on session writes (`:1021-1023`), pending mail, or an armed sentinel, and
`operator-readout.sh:1416-1418` cites E0 by name as the reason the certificate stays silent on rc 1
(read-only) *and* rc 2 (cannot tell). **A read-only turn that names ten drivable items is invisible to
every arm on the box.** This is the exact shape of the ~300 closes/30 d that parked drivable work
(`docs/research/conviction-close-2026-09-08.md`).

The rule text is *right about the readout* and *wrong about the yield*: suppressing a state readout on
a turn with no state is correct (alarm polarity); yielding on identified work is the defect.

### C2 — the kill-switch is disarmed almost exclusively by our own machine  *(anchor `CLAUDE.md:898`)*

Measured over **1,489 transcripts** modified since 2026-09-01, across all four roots
(`find $r/projects -name '*.jsonl' -newermt 2026-09-01`, deduped), **3,182 non-meta user messages**
(the exact population `hooks/completion-assert.sh:186-197` reads):

| | count | share |
|---|---|---|
| non-meta user messages | 3,182 | — |
| matching `CA_KILL_RE` (`completion-assert.sh:161`) | **29** | 0.91% |
| …of which reach a real Stop hook (`isSidechain != true`) | **14** | — |
| …of which are `just do X` | **3** | 0.094% |
| **genuine operator stop orders** | **3** — `Count to 1 and stop.` / `Count to 2 and stop.` / `Count to 3 and stop.` | 0.094% |

Hand-read all 29 (sample = population): 26 are machine-authored — subagent briefs (incl. **this
wave's own A08 brief**, which quotes the phrase `"just do X"` while discussing it), fire/recycle
briefs (`You are the SUCCESSOR of session 53f08288`, `Continue HOOK_SURFACE_100P`), plan-implementation
briefs (`Implement **W3 / Phase 3** …`), `<teammate-message>` records, and **3 `<task-notification>`
records** — i.e. *a subagent's returned report can disarm the lead's close gate*.

The hook's `isMeta` filter was built for exactly this class and stops at command/skill bodies; its own
comment concedes the residual and calls it correct: *"all 9 are fire/recycle briefs, i.e. genuine
instructions TO this session, which SHOULD disarm"* (`completion-assert.sh:180-182`). Under the
exhaustive-drive goal that judgement inverts. The reader takes the **last** non-meta user record, and
in a fired autonomous session the brief *is* the last one for the session's whole life — so one `and
stop` inside a 13,000-character brief turns off the close gate permanently. This is the
`pgrep-f-matches-agent-briefs` memory rule at a second site.

**Failure direction:** the hook's stated bias is *detect* (`:158-160`) — "a false positive costs one
un-asserted close". On this population the false-positive rate is 26/29 = 89.7% and each one is
session-lifetime, not one close. The bias is now sized for the wrong population.

### C3 — step 5 asks for a list the close rules forbid  *(anchors `CLAUDE.md:854`, `:813`)*

> `:854` *"`▶ cc-do [N runnable]` row is its only admissible form. **Judgment items are counted, not itemized.**"*
> `:813` *"it IS S1's rung (`⛔`), stated as **the one decision** you need"*

Both were derived from measurements about *runnable operator steps* and *a session holding one
decision*. Step 5 is a different object: the terminal presentation, after exhaustion, of the residual
set that genuinely needs the operator — plural by construction. There is no rule text for it, so the
existing rules apply by default and forbid the very shape the operator asked for. `commands/are-we-done.md`
inherits the same single-decision shape.

### C4 — "never add verification you were not asked for" vs "research exhaustively"  *(anchor `CLAUDE.md:358`)*

> `- **Never add verification you were not asked for.** Opus 5 already checks its own work; a "double-check before responding" or "spawn a subagent to verify" step *compounds* with that and burns tokens for no quality gain.`

Prose-only (no identifier appears in `hooks/ scripts/ bin/`). Read literally it bans exactly the move
step 3 mandates — spawning a research fan-out to lift conviction. The clause already carries the
distinction that resolves it (*"Verify because the task's risk earns it — never as ceremony"*), but the
banned example is `"spawn a subagent to verify"`, which is what F2's *"research exhaustively"* now
requires. **Failure direction of leaving it:** it errs toward *silence in the dangerous state* — an
agent below 90% conviction cites this line to skip the research and file the row instead.

### C5 — the resident rule's own subagent count contradicts all three of its downstream surfaces

| Surface | Number |
|---|---|
| `CLAUDE.md:228` | *"Default **N=12** for typical complex research"* |
| `skills/research-subagents/SKILL.md:4` | *"default **N=10** (anchor band 8-12)"* |
| `commands/research.md:2` and `:62` | *"Default **N = 10** … Anchor band 8–12"* |
| `hooks/research-precognition-nudge.sh` (live UserPromptSubmit, injected into context) | *"Default **N=10** (band 8-12)"* |

One resident line, three downstream surfaces, two numbers. The hook injects `N=10` into the model's
context on the very prompt where the count is chosen; the resident file then says 12. (This wave is
N=12 — the resident line wins, which is the direction that matters: the *unenforced* number beat the
*injected* one.)

### C6 — `📦-in-reso` contradicts the ship-policy table 107 lines above it

`:470` *"🚨 **This table names NO repo, deliberately.** Landing cost is a PERISHABLE FACT…"* — and then
`:577` names one: *"Only ⛔ and **📦-in-reso** may end a turn holding work."* The same defect the
`resident-policy-must-not-restate-perishable-facts` memory rule was written for, surviving inside the
paragraph that states the rule.

---

## 3. Prose-only census

Method: for each named rule, a distinguishing identifier grepped across `hooks/ scripts/ bin/`
(`grep -rl --include='*.sh' --include='*.py' --include='cc-*' -F <pat>`). 55 rules classified.
**45 carry at least one mechanical arm; 10 are prose-only.** Hand-checked, not just counted — several
automated MECH hits are loose-pattern false positives (F1's `net-positive`, F3's `F3 `) and are
reported below as prose-only in substance even where a string matched.

**Prose-only (no arm anywhere):**

1. `S4 OUTCOME` — state the goal, not the increment
2. `S6 WAITING` — named, never counted *(the one protective feature measured, −6.9pp)*
3. `disposition DRIVEN`
4. **`parallelize by default`** — the 🚨 operator standing directive at `:174`; no hook counts a
   serialized lead that had a clean fan-out
5. **research depth 150–250K / ceiling 500K** (`:236`)
6. **`Never add verification you were not asked for`** (`:358`) — see C4
7. **`NEVER script your own authorization`** (`:907`) — enforced only by the *classifier*, not by us
8. `manual-command-delivery` — hand-off is a PROGRAM not a worksheet (`:903`)
9. `brevity / chat discipline` (`:352-356`)
10. `G2 escalation surface` / `G3 local action` / `G4 task-clean` — the auto-continue gates; G1 alone
    has an arm (`dod-persist.sh`, `wrap-ledger.sh`)

**Blind-in-practice (arm exists, abstains on most of the population).** Measured from
`~/.claude/autonomy/idl.jsonl` (45,824 lines; span verified `2026-09-08T08:22:09Z → 21:42:29Z` =
**13.3 h, not 30 d**), `jq -rc 'select(.hook) | [.hook,(.reason//"-")]|@tsv' | sort | uniq -c`:

| hook | evaluations | dominant abstain | blind share |
|---|---|---|---|
| `anti-deference-nudge` | 489 | `no-tell` 471 | **96.3%** |
| `completion-assert` | 440 | `no-close-tell` 314 | **71.4%** |
| `operator-readout` | 354 | `continue-armed` 215 | **60.7%** |
| `waiting-recycle` | 7,608 | — | — |

Every close-shape contract (S1/S2/S3, false-done, opaque-identifier) is reachable only through a
lexical close-tell. On 3 of 4 stops there is no tell, so those rules are **prose-only for the majority
population** even though the code exists.

---

## 4. Proposed Edit-only integrations

All five are `Edit` (targeted replacement of a quoted anchor), never `Write` — these files accumulate
dated decisions and rationale across sessions (§ File Update Rule); a rewrite destroys the "why"
paragraphs that make each rule auditable. Each keeps the existing sentence and *appends* the new
clause, so nothing is deleted.

### E1 — E0 gets an exception clause  *(highest value)*

**Anchor (`CLAUDE.md:532`, verbatim):**
```
| _E0_ read-only (no tracked writes) | — | **no readout** — answer and yield |
```
**Replacement:**
```
| _E0_ read-only (no tracked writes) | — | **no readout** — answer and yield. 🚨 **`yield` is about the READOUT, never about identified work.** A read-only turn that NAMES drivable work is not E0: run the Follow-On Gate on each item and drive the passes (here, in a subagent, in a team, or by firing a session) before you yield. No arm on this box can see this case — every `session-continue.sh` floor is gated on session WRITES (`:1021-1023`), so a research turn that identifies ten items trips nothing and closes clean. |
```
**Failure direction:** errs toward *nagging on a legitimate read-only answer* — deliberately, because
the clause is scoped to turns that already named work in their own prose; a pure Q&A turn names none
and is untouched. The opposite framing (silence on identified work) is the defect measured at ~300
closes/30 d.

### E2 — the kill-switch clause states its population  *(anchor `CLAUDE.md:898`)*

**Anchor (verbatim):**
```
**Kill-switch:** any per-prompt "…and stop", "no auto-continue", or "just do X" suspends
auto-continue for that turn — surface and yield instead.
```
**Replacement:** same sentence, then append:
```
🚨 **It must be the OPERATOR's per-prompt instruction — a machine-authored brief is not one.** Measured 2026-09-08 over 1,489 transcripts / 3,182 non-meta user messages: the regex matched 29, of which **26 were machine-authored** (subagent briefs, fire/recycle briefs, `<teammate-message>`, `<task-notification>` — including a brief that merely QUOTED the phrase) and 3 were genuine operator prose, all of them `Count to N and stop.` probes. `completion-assert.sh:186` reads the LAST non-meta user record, so in a fired session the brief IS that record for the session's whole life: one `and stop` inside a 13,000-character brief disarms the close gate permanently. **Never write a kill phrase into a brief, a peer message, or a report you hand back.**
```
**Failure direction:** prose alone errs toward *the operator saying stop and being ignored* if a future
hook change narrows the matcher. This edit does not narrow the matcher — it is a discipline clause
plus the measurement a later mechanical fix would be built on (that fix is A-other-axis work: exclude
`<task-notification>` / `<teammate-message>`-prefixed records, and require the phrase in the first
~500 characters).

### E3 — step 5's itemized terminal presentation gets a slot  *(anchor `CLAUDE.md:854`)*

**Anchor (verbatim):**
```
`▶ cc-do [N runnable]` row is its only admissible form. Judgment items are counted, not itemized.
```
**Replacement:** keep both sentences, append:
```
**One exception, and it is the terminal one:** when the session has driven every F1-F4 pass and every ≥90%-conviction item and what REMAINS is a set of genuine operator decisions, those are **itemized, answer-first** — one line per decision, each stating the decision as a sentence (never a label as subject), its conviction number, and its measured options. That is the `⛔` close and it may carry more than one row; `:813`'s "the one decision you need" describes the ordinary mid-work `⛔`, not the exhaustion close. The counted `◆` line still owns the machine's STANDING pile — the itemized set is only what THIS session drove to the wall.
```

### E4 — resolve C4 in place  *(anchor `CLAUDE.md:358-359`)*

**Anchor (verbatim, first two lines):**
```
- **Never add verification you were not asked for.** Opus 5 already checks its own work; a
  "double-check before responding" or "spawn a subagent to verify" step *compounds* with that and
```
**Replacement:** unchanged, plus a trailing sentence in the same bullet:
```
  🚨 **This bans CEREMONY, never RESEARCH.** A fan-out fired to move conviction under F2 (`§Follow-On Gate`) is the task's risk earning it, not a re-check of work already done — the ban is on verifying what you already did, and F2's "research exhaustively" is about what you have NOT yet decided. Below 90% conviction, the fan-out is mandatory and this bullet does not reach it.
```

### E5 — the Shared Task List gets its first rule  *(anchor: append after `CLAUDE.md:232`, the Research Subagents section's closing line `Use \`Explore\` for fast terminal codebase lookups.`)*

New paragraph, appended (never replacing):
```
## Shared Task List (All Projects)

Two or more open work items in one session are TRACKED, not remembered: `TaskCreate` / `TaskUpdate` / `TaskList` (store `$CLAUDE_CONFIG_DIR/tasks/<listId>/`, list id `CLAUDE_CODE_TASK_LIST_ID`, exported by the launcher). The wiring is already live and unused: `setup-task-symlinks.sh` (SessionStart), `task-mutation-index.sh` (PostToolUse), `task-quality-gate.sh` (TaskCompleted — runs typecheck in the teammate's worktree and rejects the task on failure), `hooks/lib/task-helpers.sh`. ⚠️ **The tools are not currently offered to every session** — gated behind `CLAUDE_CODE_ENABLE_TODO_TOOLS=1` or the remote flag (backlog `ebe84950e98a`). Where they are absent, the plan doc's own task table is the list; do not treat their absence as licence to hold the set in context. A todo set that lives only in a context window dies with it.
```
**Failure direction:** errs toward *ceremony on a two-item turn*. Mitigated by the "2+ open items"
threshold and by the fact that a hook-backed store already exists — this rule spends no new machinery.

### E6 — delete the reso hardcode  *(anchor `CLAUDE.md:577`)*

**Anchor (verbatim):** `**Only ⛔ and 📦-in-reso may end a turn holding work.** Everything else the agent drives:`
**Replacement:** `**Only ⛔, and 📦 in a repo whose OWN `CLAUDE.md` says landing spends money, may end a turn holding work.** Everything else the agent drives:` — matching `:470`'s "this table names NO repo, deliberately", which this line contradicts.

---

## 5. Adversarial self-pass

*What would a hostile reviewer say I did not check?*

1. **"Your prose-only count is a grep artifact."** Fair — a loose pattern (`F3 `, `net-positive`)
   matches an unrelated comment. I hand-verified the 10 prose-only rows and re-classified three
   automated MECH hits (F1, F3, research-subagent-N12) rather than reporting the raw count. The
   count is **10 of 55 hand-checked**, and the more important number is the *blind-in-practice*
   table in §3 — a rule with an arm that abstains 96% of the time is prose for 96% of closes.
2. **"You assumed the resident CLAUDE.md is loaded."** Verified two ways: it is present verbatim in
   this subagent's own context, and `~/.claude/rules/agent-operating-lessons.md` (also loaded) states
   the interactive-vs-`-p` split explicitly. The worktree copy and the live copy are byte-identical
   (`diff` empty, 84,249 B both), so an Edit to the worktree copy still needs the post-land manual
   sync `.claude/CLAUDE.md` describes — `~/.claude/CLAUDE.md` is a real file, not a symlink.
3. **"E1 will make every read-only turn nag."** This is the alarm-polarity objection and it is the
   right one. The clause is scoped to *turns that named work in their own prose* — which is a
   model-side judgement with no arm, so E1 is honestly a **prose fix to a prose gap**, not a
   mechanical one. Stated plainly: it errs toward over-firing in the model's own head and cannot
   over-fire in a hook, because there is no hook. A mechanical version (a Stop-hook arm that reads
   the turn's own text for enumerated drivable items on a read-only turn) is a different axis's
   proposal and would need its own false-positive measurement before it ships.
4. **"cc-permission-audit might write."** Checked its header: `--prune` "writes NOTHING" without
   `CONFIRM=1`; discovery is read-only. So the agent-runnable half of step 7 exists today and no rule
   points at it — that is a rule gap, not a capability gap.

---

## 6. Open questions for the lead

- **Does step 7's allowlist half get a sanctioned path, or stay operator-only?** Three arms refuse it
  (soft_deny `Self-Modification`, `CLAUDE.md:907`, migration class `c10`). The C10 rescope
  (*"operator can revert"* replacing *"operator runs"*) is **unratified** (`migrations/README.md:72`)
  and is exactly the decision that would unblock it. This is a genuine operator value call.
- **Which number is the default subagent count — 10 or 12?** One of the four surfaces in C5 is wrong
  and all four are load-bearing.
- **Should a Workflow-tool authorization live in the resident rules at all,** given the shipped skill
  says it "does not itself authorize running one"? Today the only two authorizations are
  `/limit-recover` and the `ultracode` keyword.
