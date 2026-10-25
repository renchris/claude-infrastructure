# D1 — Rule text only: a lead keeps working while a decision is open

Designer slot D1 (angle: always-loaded instruction text only) for operator ruling `d610f8473106`.
Worktree `lead-idle-fix` at `958b23030`. Read-only research; this file is the only write.
Labels: `R` = `CLAUDE.rules.slim.10-session-close.md` (deployed `~/.claude/rules/10-session-close.md`),
`S` = `CLAUDE.global.slim.md` (deployed `~/.claude/CLAUDE.md`), `G` = `CLAUDE.global.md` (deployed
`~/.claude/CLAUDE.full.md`, loaded by no session, `install.sh:1083`). `TX:n` = line n of the incident
transcript `…/666022fd-ed3e-4e72-b293-7caae899d585.jsonl`. Maps are cited as `maps/<name>.md`.
"Measured" names its command; "estimated" names its method.

---

## 0. The design in one screen

D1 changes no hook, no CLI and no settings. It rewrites the six sentences that licensed the idle, adds one
standing-grants section, and pays for the growth inside the same files (one in, one out). Every old/new pair
below is a tagged block (`old:<file>:<n>` / `new:<file>:<n>`) that a script applied and measured against the
real files (§4).

| Goal | Mechanism (text) | Where |
|---|---|---|
| (a) keep working on ungated items | The decision row stops saying "Stop and ask, overriding auto-continue". ⛔ may end a turn only when every remaining in-scope item waits on an open decision. A decision gates only the act it asks about; the frozen scope is the course until the operator changes it | R:38, R:103, R:189, R:217; G twins |
| (b) judgment calls → class B | The filing paragraph that said `--class C` for every held decision now routes by class: a judgment call with a status-quo course is class B with `--default <that course> --deadline --default-effect no-change --project`; class C only for operator-only acts and picks with no status quo | R:160, R:189; G:1000-1002, G:1042 |
| (c) find a ruling before asking | Before filing: the plan's decision log, the grants section, `cc-memory-search --all`, answered packets (an `expired-actioned` class-B default is a ruling by silence). A ruling found is the answer | R:68, R:160; G:657, G Corollary |
| (d) standing grants every session loads | New `## Standing operator grants (All Projects)` in S (operative line) and G (full record, operator's words, envelope, how to check the 80% meter) | S after :145; G after :376 |
| (e) refuse a Blocked idle while ungated work remains, loop scope included | Text cannot make a hook refuse. It does three things a hook then enforces: (1) the agent arms the existing, rung-blind `session-continue.sh set` under ⛔/✅-with-ungated-work, so later idle Stops are blocked by the already-bounded armed path; (2) class-B routing removes the false ⛔ at its source (`BLOCKED` counts class C only, `scripts/wrap-ledger.sh:47-49,1510`); (3) a loop scope is defined as open work and must be persisted with `dod-persist.sh set` at intake | R:26, R:103, R:217 |
| (f) wake a stalled session itself | Text cannot wake an idle session. The always-loaded line keeps the session's own self-wake timer running while a decision it filed is open (B13 stopped its timer at 08:34Z). G adds the rest: no detached `cc-await-ping … &`, doubling back-off, re-read packets and scope at each wake, and name open decision ids in a recycle brief | R:103; G:766 |

Measured budget (§4): the always-loaded pair changes by **−4 units net** (S+R 58,790 → 58,786; user tier 61,074 →
61,070). D1's own text adds 1,642 units; 13 cuts and 3 rewrites that came out shorter remove 1,646. Each cut is
duplicated text, tool-enforced mechanics, or a rationale parenthetical the full text already carries (§4.3).

**Honest headline.** D1 has the smallest blast radius and zero new loop risk, because no hook behaviour
changes. It also guarantees nothing: every lever depends on the model reading and following the text. The B13
lead already had text telling it to keep going (R:4 "without stopping to ask", R:105, S:166 "Idle … at 35% or
more: recycle") and idled at 64% anyway (`maps/incident-replay.md` §5). What D1 removes is the text that told
it the opposite, which won (§1.2). Goal (e) needs the ledger and session-continue changes, and goal (f) needs
the lead-supervisor nudge, to hold without the model's cooperation (§8).

---

## 1. Why rule text first

### 1.1 The text is what licensed the idle, sentence by sentence

| Rule (today) | Verbatim | What it did in B13 |
|---|---|---|
| R:38 | "Stop and ask, overriding auto-continue; commit in-progress work first." | Overrides auto-continue for the whole session, not for the item the decision covers (`maps/rules-text.md` §2a) |
| R:68 | "otherwise hand it to the operator with the number…" | At 85% and 75% (TX:4254, TX:4260) both calls had to go to the operator; nothing said to keep the status-quo course meanwhile or to look for a ruling first |
| R:103 | "Only ⛔, and 📦 in a repo whose own `CLAUDE.md` says landing spends money, may end a turn holding work." | No "gates all remaining work" condition |
| R:160 | "filing is what makes it the `⛔` rung: `cc-decide open --class C …`" | Both judgment calls filed class C (TX:4254, TX:4260), so `wrap-ledger.sh:2604` read ⛔ |
| R:189 | "BLOCKED: a genuine operator-only gate (credential, sudo, destructive migration, a real value fork)" | "A real value fork" covers "stop the loop?" |
| R:217 | "Clear it … as soon as the state becomes ✅ / 📦 / ⛔ / 📤" | Tells the lead to disarm its own continuation the moment it files class C |

### 1.2 Evidence that the always-loaded rule text is the operative instruction

1. **The rule beat the tool's own definition.** At 02:37Z, after filing, the lead printed `cc-decide`'s header
   (TX:4281, TX:4290), which defines B as "a value-fork … carries a default_if_no_veto + veto_deadline" and C as
   "C10 self-mod / C6 money-path / permission denial" (`bin/cc-decide:13-19`; `grep -c 'QUEUE-FOR-REVIEW'` over
   TX:4270-4300 returns 2, measured). It did not re-file. At TX:4294 it closed "No round 27 starts until you
   answer the first question." The tool text conflicted with R:160, and R:160 won.
2. **The same model, under the same rules, worked once the operator's words were in context.** At 18:12:16Z,
   29 s after the operator's 18:11:47Z message, it wrote "Until you answer, I'll keep running the loop as scoped, starting
   round 27 with Codex added." (TX:4495). At 18:31:59Z it kept round 27 running under an open class-C packet
   (`d610f8473106`, TX:4769). The capability exists. What was missing was text saying it applies.
3. **The ruling it missed was on its own disk.** The lead's plan records, from 2026-10-16 (commit `8c06a306`),
   "The operator's stop question (`eb3dbe1e5e94`) expired unanswered on 2026-10-15, so its default holds: keep
   looping until a round confirms nothing" (`agent-context-sync/docs/plans/bring-back-ocr.md:885-886`, measured
   with `git log -S`). The text never told it to look there.

### 1.3 Why this is the lowest-risk layer

- **No new loop.** No hook, ledger or CLI behaviour changes. The only mechanical effects of the text run
  through paths that already exist and are already bounded (§5).
- **No false block.** Nothing new can block a Stop. A text rule the model misapplies costs at most turns the
  existing caps already bound.
- **No settings, no registration, no plist.** The edits reach sessions through `install.sh`'s copy legs
  (`install.sh:1113-1139`) at the next `deploy-live.sh` converge (`scripts/deploy-live.sh:52`).
- **No other gate weakens.** G2 (`R:45`), the `/ship` refusal (`R:62`), money-landing 📦 (`R:58`, `R:103`), the
  research-program exemption (`R:74-80`), explicit pauses (`R:49`), the kill-switch (`R:223`) and "scope cannot
  be reconstructed" (`R:26`) are kept word for word.

---

## 2. Mechanism per goal

### (a) Keep a lead working on every in-scope item an open decision does not gate

- **The decision row** (R:38, G:605) becomes: commit in-progress work, file it, keep driving every in-scope item
  it does not gate; stop and ask only when it gates all remaining in-scope work.
- **The holding-work sentence** (R:103, G:766) becomes conditional, and defines "gates" without needing any
  packet field. In G's words: *a decision gates only the act it asks about and work that builds on one of its
  answers; what the frozen scope already directs (a loop scope's next round included) is not gated, since the
  frozen scope is the course until the operator changes it.* R says the same in fewer words. This is the "never let keep-working implement the gated act" carve-out
  (`maps/legit-stops.md` §6 C3): the gated act itself still waits.
- **A ⛔ with ungated work is a 🔧** for the agent's purposes: drive it and arm the continuation.
- **Precedence over machine text.** One sentence says that any ledger or hook line telling the agent to stop,
  hand back or clear on ⛔ (`wrap-ledger.sh:3101` "STOP-ASK — … nothing below it closes"; `session-continue.sh:1368`
  "blocked on the user (⛔) … clear") means the all-gated ⛔. §1.2 item 1 shows why this matters: when tool text and
  rule text disagree, the model followed the rule.

### (b) Route judgment calls with a status-quo course to class B

- R:160 and G's *Corollary* (G:1000-1002) route by class instead of hard-coding `--class C`:
  - **Class B**: a judgment call with a status-quo course. The default is that course, usually the frozen scope.
    It carries `--default-effect no-change --project <repo>`, so a fired default is not filed as work in the wrong
    project (`df779857c4ff` was filed under claude-infrastructure, `maps/cc-decide.md` §0.2). The agent keeps that
    course meanwhile.
  - **Class C**: waits, has no default, and is the only class the ledger counts as ⛔. It covers an act only the
    operator may authorize (self-modification, money, a permission denial, a credential, a destructive or
    production change, outbound or publishing) and a pick among new options with no status quo.
- **Why class C keeps the escalation surfaces.** `bin/cc-decide:18` defines C as "HARD-BLOCK (human-only)". The
  rule-mandated operator-only acts (`maps/legit-stops.md` §2.2: 33% of the class-C sample) stay class C, at
  today's force, so no gate weakens. Only the judgment calls with a stated status quo move to B (36% of the sample,
  CI about 25-49%, `maps/legit-stops.md` §2.2). Picks with no status quo (14%) stay C (§6 C8 there).
- **Where to read the classes.** The rule names `cc-decide help`, which prints the header with the class definitions
  (`bin/cc-decide:653` → `usage()` at `:93`). The B13 lead tried `cc-decide open --help`, which `open`'s own parser
  rejects as "unknown arg --help" (TX:4249-4250).
- R:189 (BLOCKED) and G:1042 drop "a real value fork" in favour of "an open class-C decision", and add that it
  ends a turn only once nothing ungated is left.
- **The mechanical consequence is free.** `wrap-ledger.sh` already ignores class B (`:47-49`, pinned by
  `tests/wrap-ledger.bats:1873-1889`). Refiling a judgment call as B removes the false ⛔ with no code change.
  D1 makes that the default filing behaviour instead of a remedy after the fact.

### (c) Find an existing ruling before asking

- F2 (R:68) gains *unless a ruling answers it (§ The close message): act on it, citing it.* G:657 spells out what
  counts as a ruling: an answered packet on the same question, a purchase made for it, a standing grant, or the
  operator's words this session. G also cites the operator's universal ruling `29d62f1ad390` (2026-10-20, as little
  human in the loop as possible, everywhere; the packet's evidence field). No file carries it today
  (`grep -n 29d62f1ad390` over S, R and G returns nothing, measured). It stays out of the slim text for budget; F2
  already encodes its operative half (ask only below 90% after exhaustive research).
- R:160 (before filing) names the search: the plan's decision log, § Standing operator grants,
  `cc-memory-search --all`, and `cc-decide list --all --json`. A fired class-B default (`expired-actioned`) is a
  ruling by silence. G adds "match a rare word, read the `what_plain` heads".
- **Measured on B13 decision 1.** Answered packets resolved before 02:36Z: 625. Those whose `what_plain`, default or
  evidence match `\bloop(ing)?\b`: 17, and `eb3dbe1e5e94` is among them, its head reading "The setup-prompt loop
  is not converging…" (measured: `jq -s` over `~/.claude/autonomy/decisions/*.json`, filter
  `status != "open" and resolved < 2026-10-24T02:36Z`). The plan's decision log names it outright
  (`bring-back-ocr.md:885-886`).
- **Measured on B13 decision 2.** `codex|openai|cross-vendor` finds 7 answered packets, `a247b7288149` among them
  (`maps/ruling-discovery.md` §3.3). The lead found that packet anyway (TX:4235) and read it as scoped to
  TrueMemory, so the fix for decision 2 is goal (d), a grant written in general scope, not the search.
- **What the text does not claim.** Raw keyword search is noisy (88-100% unrelated hits on common words,
  `maps/ruling-discovery.md` §4.1). G says to match a rare word and read the `what_plain` heads. The ranked stderr
  hint in `cc-decide open` (`maps/ruling-discovery.md` §6.1) is a code change, outside D1.

### (d) Standing operator grants where every session loads them

- **S** gets the operative section, 860 units (S-1, +541 net). It holds the grant, its envelope (`git archive` of
  committed code, `-s read-only`, the ≥80% weekly-meter stop, no paid API), when to still ask (personal or customer
  data, a repo-listed escalation surface), and that it routes no `model-config.yaml` slot.
- **G** gets the record: the operator's 18:11Z words (TX:4488), the purchase packet, how to read the 80% weekly
  meter (`used_percent` of the `window_minutes` 10080 window in the newest `~/.codex/sessions/**/rollout-*.jsonl`,
  `CODEX_ADVERSARIAL_SLOT_PROBE.md:229-232`), the `-s read-only` rule (:248-249), the personal-data exclusion,
  and the open Antigravity question.
- **The wording is additive** (extra non-Claude reviewers or judges beside the Claude review), so it does not
  collide with "uncertified means unrouted" (`CODEX_ADVERSARIAL_SLOT_PROBE.md:25-31`) or the "blanket 'use Codex
  for adversarial work'" warning (:227-228).
- **Not a new rules file.** A `CLAUDE.rules.slim.20-*.md` would grow the same user tier and would also be unbudgeted
  at land until `config/instruction-budget.json` `deploy_sources` names it (`maps/rules-text.md` §6). It also
  touches a config file, which D1 avoids.
- **Not in workflow-lean slots.** Those load no CLAUDE.md (`S:117`). The lead decides whether to call Codex, so
  that is acceptable.
- **Antigravity is left open.** The agentsync memory names it (`cross-vendor-review-standing-grant.md:3`), but
  goal (d) names only the Codex plan. G records it as open.

### (e) Make a Blocked idle with ungated work, loop scope included, something the close stack refuses

Text cannot add a refusal. It moves three facts into places where existing machinery acts on them:

1. **The continuation actuator, armed by the agent.** `session-continue.sh`'s armed path reads no rung: it runs on
   sentinel presence alone (`hooks/session-continue.sh:1288-1330`, then `:1334` onward). R:217 now tells the agent
   to arm `set "<next step>"` on a ⛔ or ✅ ledger over ungated work. Once armed, every later idle Stop is
   mechanically blocked by the existing path. That path writes `mark_blocked continue` (`:1532`), so
   completion-assert yields its ledger arm (`hooks/completion-assert.sh:1275-1298`). It is already bounded (§5).
   One compliant action turns into a mechanical refusal for the rest of the work.
2. **Class-B routing removes the false ⛔ at the source.** With both B13 packets as class B (or decision 2 not
   filed, under the grant), `BLOCKED=0`. The ledger stops printing "STOP-ASK — … nothing below it closes"
   (`wrap-ledger.sh:3101`), which was the machine text reinforcing the hold.
3. **The loop scope becomes defined, persisted and un-fakeable.** R:26 now says:
   - a loop scope is open work until its condition holds or a newer `Scope (frozen):` line ends it;
   - the ledger reads a loop as met, so `✅`/`SCOPE=met` does not end it;
   - persist the scope with `dod-persist.sh set` at intake. It was never captured during the idle; it reached the
     store at 20:15:35Z (`maps/incident-replay.md` §0.1). R:26's "(`dod-persist.sh` captures it)" was false for a
     session that never compacts (`hooks/dod-persist.sh:6-17`).
   - **Never add a `- [ ]` box for a loop.** A box enters the store only through a multi-line
     `dod-persist.sh set` (a single-line `set` gets a `Scope (frozen): ` prefix, `hooks/dod-persist.sh:487`), and
     `dod-persist set` only appends (`hooks/dod-persist.sh:162` "never overwrite prior
     captures", `persist_dod` at `:172-194`), and `REMAINDER` counts every unchecked box in the lineage stream (`scripts/wrap-ledger.sh:935-941`).
     A box could never be checked off, and every later session in that checkout would inherit a permanent 🔧. That
     is the alarm-polarity failure (`wrap-ledger.sh:49-52`). This rules out the obvious text-only trick of making
     the ledger "see" a loop.

What (e) still lacks, and D1 cannot supply: a refusal when the agent does **not** arm the continuation. In
B13's F1-F3 shape that refusal needs a ledger `LOOP_OPEN`/`UNGATED` field and a session-continue ⛔ floor (the
code designs). §6 shows which F-closes D1 covers and how.

### (f) Wake a stalled session itself

Text cannot wake an idle session: a session that has stopped generates no Stop and reads no text. Five things
are still in reach. The first is always loaded (R-6). The next three are in G only, for budget. The fifth relies on
text that already exists (S:166):

- **No teardown (R-6).** While a decision you filed is open, keep a `cc-await-ping` timer (`run_in_background`,
  unless a `/goal` is live). B13 stopped its timer at 08:34:59Z ("I'm stopping the inbox watcher for now",
  TX:4476), and the next Stop came at 18:11Z (`maps/incident-replay.md` §1). The harness's own `mailbox-wake-arm`
  wakes only on mail, never on a timeout (`maps/wake-path.md` §1 W-a), so the model-armed timer is the only self-wake.
- **No detached watcher (G-4).** Never use `cc-await-ping … &`. It reads as armed and wakes nobody, and it also makes
  `mailbox-wake-arm`'s claim guard skip arming (`maps/wake-path.md` §4.3; `hooks/mailbox-wake-arm.sh:188-203`).
- **Re-read at each wake (G-4).** B13's own timer woke it at 07:39Z and 08:34Z, and it re-closed ⛔ both times
  (`maps/wake-path.md` §4.4). Under D1 each such wake's close meets the new R:103 again.
- **Polling cost (G-4).** Legitimately blocked sessions pay for polling (e582464c re-armed hourly,
  `maps/legit-stops.md` §4). G says to double `--timeout` after a wake that finds nothing new. That is a bound by
  instruction only.
- **A fresh successor is the stronger self-wake.** S:166 already says an idle session at 35% or more recycles. A
  successor re-judges the gating without the predecessor's own "No round 27 until you answer" in its context. Under
  class-B routing the ledger reads ✅, and boundary-handoff's free-win then forces that recycle mechanically (§5 L3).
  G-4 adds that the brief must name the open decision ids, because a successor's ledger counts only its own
  session's packets (`scripts/wrap-ledger.sh:1529`).

The real (f), a supervisor nudge to the subject, belongs to `scripts/lead-supervisor.sh` (`maps/wake-path.md`
§5). It is a code change, outside D1.

---

## 3. File changes (exact text)

Each pair replaces the `old` text with the `new` text; the old text occurs exactly once in its file (checked, §4.1).
Block bodies are byte-exact, including straight quotes inside code spans.

### 3.1 `R` — `CLAUDE.rules.slim.10-session-close.md`

**R-1 (R:4), cut: the Stop-hook pointer folds into R:225's pointer to the same file and section (R-11 adds "or hooking").**
```old:R:1
`operator-readout.sh` renders the operator's close block from disk as a `systemMessage`. Before writing or debugging a Stop hook, read the reference `~/Development/claude-infrastructure/CLAUDE.global.md` § Session Close Protocol for which hook output fields reach the model and which extend the turn.
```
```new:R:1
`operator-readout.sh` renders the operator's close block from disk as a `systemMessage`.
```

**R-2 (R:26): persist at intake; the loop scope is open work; no box.**
```old:R:2
Freeze the DoD at intake: the first time a task will write tracked files, restate the ask as one line, `Scope (frozen): …`, in the plan or else inline (`dod-persist.sh` captures it). Close-time completeness is a diff against that line, not a fresh judgment. If the scope cannot be reconstructed, stop and ask.
```
```new:R:2
Freeze the DoD at intake: the first time a task will write tracked files, restate the ask as one line, `Scope (frozen): …`, in the plan or else inline, and persist it with `~/.claude/hooks/dod-persist.sh set "<that line>"` (a recycled or fired session too). Close-time completeness is a diff against that line, not a fresh judgment. A loop scope ("loop until X") stays open until X holds or a newer `Scope (frozen):` line ends it, though the ledger reads it as met; never add a `- [ ]` box for it. If the scope cannot be reconstructed, stop and ask.
```

**R-3 (R:38): the decision row.**
```old:R:3
| Needs a decision (destructive migration, auth, navigation pattern, DB timeout) or information | Stop and ask, overriding auto-continue; commit in-progress work first. |
```
```new:R:3
| Needs a decision (destructive migration, auth, navigation pattern, DB timeout) or information | Commit in-progress work, file it and keep driving every in-scope item it does not gate; stop only when it gates all of them. |
```

**R-4 (R:68, F2): a ruling found is the answer; handing over pauses nothing ungated.**
```old:R:4
otherwise hand it to the operator with the number, the research receipt and the measured options in operator terms.
```
```new:R:4
otherwise hand it to the operator with the number, the research receipt and the measured options in operator terms, unless a ruling answers it (§ The close message): act on it, citing it.
```

**R-5 (R:68, F2), cut: the tool-refusal mechanics, compressed (the tools enforce and print them).**
```old:R:5
`cc-backlog add --why-not-now "needs-human: …"` and `cc-decide open --class C` refuse without `--conviction N --receipt PATH|"<cmd> => <output>"` (class C also needs two `--option`s) and refuse N > 90; `wrap-ledger.sh` counts an unconvicted ask of yours as your own 🔧 (`UNCONVICTED_MINE`), not 👤 or ⛔.
```
```new:R:5
`cc-decide open` and `cc-backlog add --why-not-now "needs-human: …"` refuse an ask without `--conviction N --receipt PATH|"<cmd> => <output>"` or with N > 90; an unconvicted ask stays your own 🔧.
```

**R-6 (R:103): ⛔ ends a turn only when all is gated; what "gates" means; precedence over machine text; keep the self-wake timer.**
```old:R:6
Only ⛔, and 📦 in a repo whose own `CLAUDE.md` says landing spends money, may end a turn holding work.
```
```new:R:6
Only ⛔ when every remaining in-scope item waits on an open decision, and 📦 in a repo whose own `CLAUDE.md` says landing spends money, may end a turn holding work. A decision gates only the act it asks about and work built on its answer, never what the frozen scope directs (a loop's next round too). A ⛔ with ungated work left is a 🔧, and a ledger or hook line saying to stop or clear on ⛔ means the all-gated one. While a decision you filed is open, keep a `cc-await-ping` timer (`run_in_background`, unless a `/goal` is live).
```

**R-7 (R:160): look for a ruling, then file by class. The old closing sentence ("an unfiled decision is invisible to `wrap-ledger.sh` …") moves to G, which already says it (G:1003-1005).**
```old:R:7
File a decision you are holding the moment you have it; filing is what makes it the `⛔` rung: `cc-decide open --class C --what <plain English, no codenames> --conviction N --receipt R --option "label::outcome" --option "label::outcome"`. A class-B packet also carries `--conviction N --receipt R`; both follow the F2 number rule (Follow-On Gate). `wrap-ledger.sh` computes `⛔` from this session's open class-C packets; an unfiled decision is invisible to it, and `✅ SAFE TO CLOSE` would render over the open question.
```
```new:R:7
Before asking, look for a ruling: the plan's decision log, § Standing operator grants, `cc-memory-search --all`, `cc-decide list --all --json` (a fired class-B default, `expired-actioned`, rules by silence). Else file the decision at once, by class (`cc-decide help`). A judgment call with a status-quo course is class B, and you keep that course meanwhile: `cc-decide open --class B --what <plain English> --default "<that course>" --deadline <ISO> --default-effect no-change --project <repo> --conviction N --receipt R`. Only class C, with no default, makes the `⛔` rung: an act only the operator may authorize (self-modification, money, a permission denial, a credential, a destructive, production or outbound act) or a pick with no status quo (`--class C … --option "label::outcome" --option "label::outcome"`).
```

**R-8 (R:189): BLOCKED is an open class-C decision, and ends a turn only when nothing ungated is left.**
```old:R:8
- BLOCKED: a genuine operator-only gate (credential, sudo, destructive migration, a real value fork). It is S1's `⛔` rung, stated as the decision you need.
```
```new:R:8
- BLOCKED: an open class-C decision. It is S1's `⛔` rung, stated as the decision you need, and ends a turn only once nothing ungated is left.
```

**R-9 (R:215): heading.**
```old:R:9
### Auto-continue actuation (🔧 only)
```
```new:R:9
### Auto-continue actuation
```

**R-10 (R:217): arm on ungated work under ⛔/✅; clear only when nothing ungated is left. The bound sentence keeps its point (only the kill-switch, the DoD and judgment bound an agent-armed chain) and drops the cap arithmetic and a duplicate of R:105; G:1129-1140 keeps both.**
```old:R:10
On 🔧, and only on 🔧, arm the continuation: `~/.claude/hooks/session-continue.sh set "<the one next step>"`; a Stop hook then feeds that step back as your next turn. Clear it with `~/.claude/hooks/session-continue.sh clear` as soon as the state becomes ✅ / 📦 / ⛔ / 📤, on a read-only turn, or when the kill-switch fires. Nothing bounds an agent-armed chain (each `set` resets the counter; `CLAUDE_CONTINUE_MAX`, default 8, bounds only the mechanical arm as `CC_MECH_MAX × CLAUDE_CONTINUE_MAX`, and `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` catches only a text-only wedge), so the stop conditions are the kill-switch, the frozen DoD, and your judgment; the hook does not judge scope. Within a turn, keep working rather than stopping on 🔧.
```
```new:R:10
On 🔧, or a ⛔ or ✅ ledger over ungated in-scope work (an open loop scope), arm the continuation: `~/.claude/hooks/session-continue.sh set "<the one next step>"`; a Stop hook then feeds that step back as your next turn. Clear it with `~/.claude/hooks/session-continue.sh clear` once nothing ungated is left (✅ / 📦 / all-gated ⛔ / 📤), on a read-only turn, or when the kill-switch fires. Only the kill-switch, the frozen DoD and your judgment bound an agent-armed chain (each `set` resets the counter); the hook does not judge scope.
```

**R-11 (R:225): the merged pointer (receives R-1).**
```old:R:11
The measurements and incidents behind the close rules are in ~/Development/claude-infrastructure/CLAUDE.global.md § Session Close Protocol; read them before changing or disputing one of these rules.
```
```new:R:11
The measurements and incidents behind the close rules are in ~/Development/claude-infrastructure/CLAUDE.global.md § Session Close Protocol; read them before changing, disputing or hooking a rule here.
```

**R-12 (R:184), cut: a sentence the same section already states twice (R:186 (c) and R:193 route sudo, physical and GUI-only steps to `cc-backlog needs … --class needs-human`). G:1041 keeps it.**
```old:R:12
Sudo, physical and GUI-only steps are not decisions; they go through `cc-backlog needs "<step>" --class needs-human`, which carries no conviction. 
```
```new:R:12
Sudo, physical and GUI-only steps are not decisions. 
```

**R-13 (R:146), cut: an example that repeats R:144's example two lines up.**
```old:R:13
S1 carries one rung and states a conclusion, not a category (`12 runnable now, 195 need your call`, not `205 manual steps`).
```
```new:R:13
S1 carries one rung and states a conclusion, not a category.
```

### 3.2 `S` — `CLAUDE.global.slim.md`

(Block numbers follow drafting order: S-2 and S-3 come after S-11 below. The apply order does not matter, since no
two old texts overlap.)

**S-1 (after S:145): the standing-grants section.**
```old:S:1
Load the frontier-routing skill when choosing a model tier for a spawn, when work hits a wall that might warrant escalation, or at wrap-up with open holes; it covers `/frontier-hole`, `/frontier-run`, `/frontier-campaign`, the standing duties and per-slot routing. Ledger: per-project `docs/research/FRONTIER_HOLES.md`.
```
```new:S:1
Load the frontier-routing skill when choosing a model tier for a spawn, when work hits a wall that might warrant escalation, or at wrap-up with open holes; it covers `/frontier-hole`, `/frontier-run`, `/frontier-campaign`, the standing duties and per-slot routing. Ledger: per-project `docs/research/FRONTIER_HOLES.md`.

## Standing operator grants (All Projects)

A covered act needs no ask and no packet (record and limits: CLAUDE.full.md, same section).
- Cross-vendor review (2026-10-24, plan bought in `a247b7288149`): in any repo, unasked, add non-Claude reviewers beside Claude's via `codex exec -s read-only` on the Codex plan: a `git archive` export of committed code only, no call at ≥80% of the weekly meter, never the paid API; ask first if it holds personal or customer data or a repo-listed escalation surface. Routes no `model-config.yaml` slot.
```

**S-4 (S:139), cut: a perishable status note on an open operator decision; G:376 keeps it.**
```old:S:4
A session chooses the ladder; it is not automatic (whether it should be is an open operator decision, `docs/plans/NONLIMIT_RESUME_LADDER.md` § W3.6).
```
```new:S:4
A session chooses the ladder; it is not automatic.
```

**S-5 to S-11, cuts: rationale or citation parentheticals that the slim header says belong in the full text (`S:3`), each verified present in G (`grep -c` in `CLAUDE.global.md`: `2.1.224` 1, `opus55-effort-sweep` 1, `find-generic-password -w` 1, `config.lock` 1, `usage_credits_authorized` 1, "`claude()` launcher passes" 1; the source path is also at R:225). Contexts: S:116, S:141, S:74, S:159, S:141, S:132, S:3.**
```old:S:5
Keep it: since 2.1.224 removed the per-session spawn cap, depth is the only runaway bound.
```
```new:S:5
Keep it: depth is the only runaway bound.
```
```old:S:6
 (`docs/research/opus55-effort-sweep-2026-09-22/`; re-measure before quoting)
```
```new:S:6

```
```old:S:7
: `security find-generic-password -w` prints the key into tool output and the transcript, while agent-secrets keeps it encrypted, lists names only and injects it into one child process.
```
```new:S:7
: the Keychain CLI prints the key into tool output and the transcript.
```
```old:S:8
; parallel automated worktree creation has raced on `.git/config.lock` and lost data
```
```new:S:8

```
```old:S:9
 (the fleet has no dollar exposure while `accounts.json` has `spend.usage_credits_authorized=false` and `frontier.credits_authorized=false`)
```
```new:S:9

```
```old:S:10
 (SSOT `~/.claude/model-config.yaml` `opus_latest`; the `claude()` launcher passes `--model claude-opus-5-5 --effort high`)
```
```new:S:10
 (SSOT `~/.claude/model-config.yaml` `opus_latest`)
```
```old:S:11
 (source: ~/Development/claude-infrastructure/CLAUDE.global.md)
```
```new:S:11

```

**S-2 (S:143), cut: the frontier-spawn-gate registration recipe moves to G, which already carries it (`G:376`).**
```old:S:2
A blocked spawn means park, never retry. The session-fire arm counts only once `migrations/0029` has registered the hook on the Bash matcher; that migration edits settings.json (class c10) and is the operator's to run. Before calling that budget enforced, run `jq '[.hooks.PreToolUse[]|select(.matcher=="Bash")|.hooks[]?.command]|any(.=="~/.claude/hooks/frontier-spawn-gate.sh")' ~/.claude/settings.json` and state which case applies when a close depends on it.
```
```new:S:2
A blocked spawn means park, never retry. Its session-fire arm counts only once the operator runs `migrations/0029`; check that before calling the budget enforced (`~/.claude/CLAUDE.full.md` § Frontier Tier Routing).
```

**S-3 (S:203): a decision is filed by class, not "asked as ⛔".**
```old:S:3
- If what remains is a decision, there is no script; ask it as the `⛔` rung.
```
```new:S:3
- If what remains is a decision, there is no script; file it (§ The close message).
```

### 3.3 `G` — `CLAUDE.global.md` (the full text; carries the rationale)

**G-1 (G:592-595): the R-2 twin.**
```old:G:1
**Freeze the DoD at intake.** The first time a task will write tracked files, restate the user's
ask as one line — **`Scope (frozen): …`** (in the plan, else inline). Close-time completeness is
then a *diff against that contract*, never a fresh re-judgment — the brake on scope-metastasis.
Unreconstructable scope is itself a STOP-ASK, never a guess.
```
```new:G:1
**Freeze the DoD at intake.** The first time a task will write tracked files, restate the user's
ask as one line — **`Scope (frozen): …`** (in the plan, else inline) — and persist it with
`~/.claude/hooks/dod-persist.sh set "<that line>"`. dod-persist captures on its own only at PreCompact, so a
session that never compacts leaves its contract where neither the ledger nor a successor can read it (B13
lead `666022fd`, 2026-10-24: its `loop until dry` scope reached the store at 20:15Z, after an 11-hour idle,
while the ledger read another session's 2026-10-08 contract). A recycled or fired session re-freezes the
scope its brief carries the same way. Close-time completeness is
then a *diff against that contract*, never a fresh re-judgment — the brake on scope-metastasis.
**A loop scope** (`loop until X`, `repeat until X`) is open work until X holds or a newer
`Scope (frozen):` line ends it. The ledger counts only `- [ ]` boxes, so it reads a loop as met
(`REMAINDER=0`, `SCOPE=met`). Never add a box for a loop: `dod-persist.sh set` only appends, the box could
never be checked off, and every later session in the checkout would inherit a permanent 🔧.
Unreconstructable scope is itself a STOP-ASK, never a guess.
```

**G-2 (G:605): the R-3 twin.**
```old:G:2
| Needs a **decision** (destructive migration / auth / nav pattern / timeout) or **info** | **STOP-ASK** (overrides auto-continue); commit in-progress work first. |
```
```new:G:2
| Needs a **decision** (destructive migration / auth / nav pattern / timeout) or **info** | Commit in-progress work, **file it** (§ The close message, *Corollary*) and **keep driving every in-scope item it does not gate**; STOP-ASK only when it gates ALL remaining in-scope work (§ *Only ⛔ … may end a turn holding work*). |
```

**G-3 (G:657, inside F2): the R-4 twin, with the B13 precedent.**
```old:G:3
only still-below-90 after exhaustive research is the operator's, and it is handed over WITH the number, the receipt of that research, and the measured options in operator terms.
```
```new:G:3
only still-below-90 after exhaustive research is the operator's, and it is handed over WITH the number, the receipt of that research, and the measured options in operator terms — **unless a ruling already answers it**: an answered packet on the same question (a fired class-B default included), a purchase made for this purpose, a standing grant (§ Standing operator grants), or the operator's own words this session. That is the answer: act on it and cite it. (B13, 2026-10-24: packet `eb3dbe1e5e94` had settled "keep looping until dry" by silence on 2026-10-15 and the lead's own plan recorded it, yet `e869fac7eb34` re-asked the same fork as a hard block; `a247b7288149` had bought the Codex plan for cross-vendor review, yet `290215743799` asked again.) **Handing over never pauses the work the question does not gate** — operator ruling `29d62f1ad390` (2026-10-20): as little human in the loop as possible, everywhere, not only inside research programs.
```

**G-4 (G:766-767): the R-6 twin, with the incident and the legit-stop evidence.**
```old:G:4
**Only ⛔, and 📦 in a repo whose OWN `CLAUDE.md` says landing spends money, may end a turn holding
work.** Everything else the agent drives:
```
```new:G:4
**Only ⛔ when EVERY remaining in-scope item waits on an open decision, and 📦 in a repo whose OWN
`CLAUDE.md` says landing spends money, may end a turn holding work.** A decision gates only the act it
asks about and work that builds on one of its answers; what the frozen scope already directs (a loop
scope's next round included) is not gated — the frozen scope is the course until the operator changes
it. The gated act itself still waits: "keep working" never means building the destructive migration, the
auth change or the deploy the packet asks about (G2 binds). A ⛔ with ungated work left is a 🔧: drive it
and arm the continuation (§ Auto-continue actuation). Where a ledger or hook line says to stop, hand back
or clear on ⛔ (`wrap-ledger.sh`'s `→ Next` "STOP-ASK — … nothing below it closes", `session-continue.sh`'s
reason text), it means this all-gated ⛔. *(Why, 2026-10-24, decision `d610f8473106`: the B13 lead
`666022fd` filed two judgment calls as class C, wrote "Nothing more runs until you answer", and idled
11 h with its frozen `loop until dry` scope ungated; round 27 depended on neither answer, and the same lead
ran it under an open class-C packet once told to. Every Stop hook accepted the idle, because this sentence
let ⛔ end a turn unconditionally. Legit stops are untouched: in 7 of 11 transcript-checked ⛔ idles the lead
had already finished or handed off all ungated work — `docs/research/lead-keeps-working-2026-10-24/maps/legit-stops.md` §4.)*
**Keep a wake path while a decision you filed is open:** the `cc-await-ping` recipe under
`run_in_background` (unless a `/goal` is live), never a detached `cc-await-ping … &`, which reads as armed
and wakes nobody; double `--timeout` after a wake that finds nothing new; at each wake re-read your open
packets (`cc-decide list --open --json`, your `session_sid`) and the frozen scope before closing again
(B13 tore its watcher down at 08:34Z, and its two earlier self-wakes each re-closed ⛔). A recycle or
hand-off names your open decision ids in the brief: a successor's ledger counts only its own session's
packets (`wrap-ledger.sh:1529`). Everything else the agent drives:
```

**G-5 (G:1000-1002): the R-7 twin, the *Corollary* rewritten by class.**
```old:G:5
**Corollary — a decision you are holding IS the rung, and filing it is what makes it one.** Open it
the moment you have it (`cc-decide open --class C --what <plain English, no codenames> --conviction N --receipt R --option "label::outcome" --option "label::outcome"` — and a class-B packet, the unattended ask whose default fires at its deadline, carries the same `--conviction N --receipt R` (extended 2026-09-08 by packet aa19d7b7a693: 19 of 19 class-B packets in the prior 30 days carried neither, 11 defaults fired unruled) — the F2 number rule: a class-C open without the number, the receipt and two measured options is refused, and one filed without them is your own 🔧, not ⛔);
`wrap-ledger.sh` then computes `⛔` from your own session's open class-C packets and it outranks
everything.
```
```new:G:5
**Corollary — a decision you are holding must be FILED, and its CLASS decides whether it is the rung.**
First look for a ruling (F2): the plan's decision log, § Standing operator grants, `cc-memory-search --all
<terms>`, and answered packets — `cc-decide list --all --json`, status not `open`, matched on a RARE word of
the question (common words drown it: 88-100% unrelated hits measured in
`docs/research/lead-keeps-working-2026-10-24/maps/ruling-discovery.md` §4.1), reading the `what_plain` heads;
a fired class-B default (`expired-actioned`) is a ruling by silence. Otherwise open it the moment you have
it, by class (`cc-decide help`; `bin/cc-decide:13-19`):
- **Class B** — a judgment call with a status-quo course (a value fork, a stop rule, a method or scope
  question): `cc-decide open --class B --what <plain English, no codenames> --default "<the status-quo
  course, usually the frozen scope>" --deadline <ISO> --default-effect no-change --project <repo>
  --conviction N --receipt R`. You keep that course meanwhile. The default fires at the deadline
  (`autonomy-sweep.sh` → `cc-decide expire-sweep`); `--default-effect no-change --project` keep the fired
  default from being filed as work in the wrong project (`df779857c4ff`, 2026-10-15).
- **Class C** — waits, has no default, and is the only class `wrap-ledger.sh` counts as `⛔`: an act only the
  operator may authorize (self-modification, a money path, a permission denial, a credential, a destructive
  or production change, outbound or publishing) or a pick among new options with no status quo:
  `cc-decide open --class C --what … --conviction N --receipt R --option "label::outcome" --option
  "label::outcome"`.

Both carry `--conviction N --receipt R` (extended 2026-09-08 by packet aa19d7b7a693: 19 of 19 class-B
packets in the prior 30 days carried neither, 11 defaults fired unruled) — the F2 number rule: an open
without the number and the receipt (and, for class C, two measured options) is refused, and one filed
without them is your own 🔧, not ⛔. `wrap-ledger.sh` computes `⛔` from your own session's open class-C
packets and it outranks everything, but under *Only ⛔ … may end a turn holding work* a `⛔` ends a turn
only when every remaining in-scope item waits on it. *(Why the class matters: from 2026-08-07, the day
class C became the only ⛔ sensor (`b08601974`), this corollary said `--class C` for every held decision;
class C then outgrew class B 522 to 166, and a 58-row audit found about half of class-C packets were
judgment calls, 36% with a stated status quo — class B by `cc-decide`'s own definition
(`maps/legit-stops.md` §2.2, `maps/cc-decide.md` §9). Both B13 packets were of that kind.)*
```

**G-6 (G:1042, BLOCKED row head): the R-8 twin.**
```old:G:6
| **BLOCKED** | a genuine operator-only gate — credential · sudo · destructive migration · a real value fork | it IS S1's rung (`⛔`), stated as the one decision you need.
```
```new:G:6
| **BLOCKED** | an open **class-C** decision — credential · sudo · destructive migration · money · self-modification · a pick among new options with no status quo (a value fork WITH a status-quo course is class B and blocks nothing) | it IS S1's rung (`⛔`), stated as the one decision you need, and it ends a turn only once nothing ungated is left (*Only ⛔ … may end a turn holding work*).
```

**G-7 (G:1125-1128): the R-9/R-10 twin.**
```old:G:7
**Auto-continue actuation (🔧 only).** On the 🔧 state — and ONLY 🔧 — arm the continuation hook so a
turn-close re-prompts you instead of stopping with work left: `~/.claude/hooks/session-continue.sh set
"<the ONE next step>"`. **Clear it** (`~/.claude/hooks/session-continue.sh clear`) the instant the state
becomes ✅ / 📦 / ⛔ / 📤, on a read-only turn, or when the kill-switch fires — those MUST stop.
```
```new:G:7
**Auto-continue actuation.** On the 🔧 state — and on a ⛔ or ✅ ledger over ungated in-scope work, such
as an open loop scope the ledger cannot count — arm the continuation hook so a turn-close re-prompts you
instead of stopping with work left: `~/.claude/hooks/session-continue.sh set
"<the ONE next step>"`. **Clear it** (`~/.claude/hooks/session-continue.sh clear`) the instant nothing
ungated is left — ✅ / 📦 / an all-gated ⛔ / 📤 — on a read-only turn, or when the kill-switch fires; those
MUST stop. (The armed path reads no rung, `hooks/session-continue.sh:1288-1330`, so arming under ⛔ needs no
hook change; its reason text still says to clear when "blocked on the user (⛔)", which means the all-gated ⛔.)
```

**G-8 (G:1172, Manual-Command Delivery tail): the S-3 twin.**
```old:G:8
If the residue is a **decision**, there is no script to write; ask it as the `⛔` rung.
```
```new:G:8
If the residue is a **decision**, there is no script to write; file it by class (§ Session Close Protocol, *Corollary*) — class C is the `⛔` rung.
```

**G-9 (after G:376): the grants record.**
```old:G:9
## Concurrent Sessions — Worktree Isolation (All Projects)
```
```new:G:9
## Standing operator grants (All Projects)

A standing grant is an operator ruling that covers a class of acts in every repo. An act inside its
envelope needs no ask and no decision packet; an act outside it is an ordinary decision (§ Session Close
Protocol, F2). Each entry carries the operator's words, the envelope and how to check each limit. The slim
variant carries the operative line; this section is the record. Adding, widening or revoking a grant is the
operator's: a rule edit is self-modification, class C.

- **Cross-vendor review** (operator, 2026-10-24, decision `d610f8473106`; builds on the 2026-10-11 ChatGPT
  Pro purchase, packet `a247b7288149`, "Upgraded to 100. Continue."). The operator, 2026-10-24 18:11Z:
  *"I thought you had autonomous zero human in the loop proactiveness and permissions to do this with
  accounts; didn't we do this for our truememory review hence getting the $100 codex plan just for these
  adversarial reviews from agents that are not our own claude model class?"*
  - **Grant:** in any repo, on your own initiative, ADD non-Claude reviewers or judges beside the Claude
    review through the ChatGPT Codex plan's CLI (`codex exec -s read-only`). The Claude side still verifies
    what they find.
  - **Envelope:** only a `git archive` export of committed code, unpacked into a fresh temp dir — never the
    live home, the working tree, or a file the repo's rules forbid copying. Keep `-s read-only`; never widen
    it (`docs/plans/CODEX_ADVERSARIAL_SLOT_PROBE.md:248-249`). No new call at 80% or more of the plan's
    weekly meter: before each batch read `used_percent` of the window whose `window_minutes` is 10080 from
    the newest `~/.codex/sessions/**/rollout-*.jsonl` (a file read, no API call; the probe's guard,
    `CODEX_ADVERSARIAL_SLOT_PROBE.md:229-232`). Subscription CLI only: the pay-per-token API
    (`api.openai.com`) is not covered.
  - **Still ask first:** an export that would carry personal messages, mail, customer or guest data, or
    anything a repo's own `CLAUDE.md` lists as an escalation surface (for example a tenant name). Personal-data
    egress to another vendor stayed an operator call (`f2e2c22bb83e`, `e3876aac762d`, `bb16a9bc1350`).
  - **Not a routing change:** it routes no `model-config.yaml` slot. "Uncertified means unrouted" (operator,
    2026-08-10, `CODEX_ADVERSARIAL_SLOT_PROBE.md:25-31`) still governs slots, and a blanket "use Codex for
    adversarial work" is what that probe's REJECT warned against (:227-228). This grant is additive review
    beside Claude, the mixed-vendor judging the probe found real (:263-267).
  - **Open:** whether it also covers Google's Antigravity CLI (`agy`) is not decided here. The agentsync
    memory note names it; the operator's ruling did not.

## Concurrent Sessions — Worktree Isolation (All Projects)
```

### 3.4 Machine text left in place, and why the rules can live with it

D1 touches no code. These strings still say the old thing; R-6 makes the rule govern them, and each should ride
the first code change that touches its file.

| Where | Says | Effect under D1 |
|---|---|---|
| `scripts/wrap-ledger.sh:3101` (`rung_next`) | "STOP-ASK — put the decision in line 1 and hand it back; nothing below it closes" | Printed only on a class-C ⛔. With class-B routing it is absent in the B13 shape. Under a legit class C over a subset (control C2), R-6's precedence sentence applies |
| `hooks/session-continue.sh:14`, `:1368` (`continue_reason`) | "clear … on ✅/📦/⛔/📤"; "blocked on the user (⛔) … clear" | Shown on every armed block. R-6 and G-7 say it means the all-gated ⛔ |
| `hooks/dispatch-assert.sh:237`, `:269` | "`cc-decide open --class C --what "…"` if it is a decision" | Could steer a judgment call to C. R-7's class routing and R-6's precedence govern. The hook is discharged by any packet (`:197`) |
| `hooks/completion-assert.sh:1757` (D4 reason) | "BLOCKED on a genuine operator-only gate (… a real value fork)" | Text only; R-8 redefines BLOCKED |
| `bin/cc-decide:103` (comment) | "A class-C packet is the ⛔ rung: it ends a session's turn holding work" | Not shown to the model unless it reads the source. `cc-decide help` prints `:2-85` only (`usage()`, `:93`) |
| `hooks/operator-readout.sh:1548` | relays the ⛔ READOUT "need your call" | Unchanged and correct: the ⛔ readout is still the prescribed S1 line (R:92) |

---

## 4. Budget: measured

### 4.1 Method

A read-only Python pass (`python3 -I`) parsed the `old:`/`new:` blocks in §3 out of this file. For each block it
checked that the old text occurs exactly once in its file, applied all replacements in memory, and measured
loader units with the repo's own `hooks/lib/instruction_budget.py` (`parse()` → `units`: UTF-16 units after
frontmatter and column-0 comment stripping, `:94-96`, `:163-166`). No file was written.

### 4.2 Result

Measured with the method in §4.1 on this file's final blocks. Columns: count of the old text in its file, then
loader units of the old text, the new text, and the delta.

| Edit | count | old | new | delta |
|---|---|---|---|---|
| R-1 | 1 | 300 | 88 | −212 |
| R-2 | 1 | 309 | 549 | +240 |
| R-3 | 1 | 170 | 224 | +54 |
| R-4 | 1 | 115 | 187 | +72 |
| R-5 | 1 | 303 | 196 | −107 |
| R-6 | 1 | 102 | 530 | +428 |
| R-7 | 1 | 517 | 815 | +298 |
| R-8 | 1 | 155 | 141 | −14 |
| R-9 | 1 | 37 | 27 | −10 |
| R-10 | 1 | 732 | 532 | −200 |
| R-11 | 1 | 198 | 200 | +2 |
| R-12 | 1 | 147 | 53 | −94 |
| R-13 | 1 | 124 | 60 | −64 |
| S-1 | 1 | 319 | 860 | +541 |
| S-2 | 1 | 461 | 215 | −246 |
| S-3 | 1 | 76 | 83 | +7 |
| S-4 | 1 | 149 | 50 | −99 |
| S-5 | 1 | 90 | 41 | −49 |
| S-6 | 1 | 77 | 0 | −77 |
| S-7 | 1 | 185 | 70 | −115 |
| S-8 | 1 | 84 | 0 | −84 |
| S-9 | 1 | 140 | 0 | −140 |
| S-10 | 1 | 123 | 51 | −72 |
| S-11 | 1 | 63 | 0 | −63 |
| G-1 … G-9 | 1 each | 2,341 | 11,442 | +9,101 |
| **R whole file** | — | 30,287 | 30,680 | **+393** |
| **S whole file** | — | 28,503 | 28,106 | **−397** |
| G whole file (loaded by no session) | — | 116,486 | 125,587 | +9,101 |

- **S+R: D1's text adds 1,642 units, the cuts remove 1,646, net −4.** The user tier (S + R + the live
  `00-mission-board.md` at 2,284, `maps/rules-text.md` §6) goes from 61,074 to 61,070. It stays over the 60,000
  budget by the 1,074 it was already over; D1 neither causes nor fixes that.
- Per-file caps hold: R 30,680 and S 28,106, both under 40,000 (`config/instruction-budget.json` `per_file`).
- **Correction to a brief constraint.** The brief says growth of S or R "is denied" at 61,074. The code does not do
  that. Repo-side S and R classify as tier `source` (`hooks/lib/instruction_budget.py:474-480`), and `judge()`
  skips any tier not in `tiers` (`:647-651`). Both the Write/Edit gate (`hooks/backup-before-write.sh:145-175`) and
  the land arm therefore apply only the 40k per-file cap. The binding reasons for net-zero are the config's
  one-in-one-out policy (`destinations.user`) and the hourly auditor's report (`scripts/autonomy-sweep.sh:685-708`).
  D1 meets them anyway.

### 4.3 What the cuts remove, and why each is safe

| Cut | Removed from the loaded text | Still available at |
|---|---|---|
| R-1 + R-11 | A second pointer to the same `CLAUDE.global.md` § Session Close Protocol | R:225, now "before changing, disputing or hooking a rule here" |
| R-5 | The field name `UNCONVICTED_MINE`, "not 👤 or ⛔", "class C also needs two `--option`s" | The tools refuse and print the reason (`bin/cc-decide:236-260`); R-7 shows the two `--option`s; G:657 keeps the full sentence |
| R-7 (tail) | "An unfiled decision is invisible to `wrap-ledger.sh`, and `✅ SAFE TO CLOSE` would render over the open question" | G:1003-1005 (the same point, longer) |
| R-10 | The `CLAUDE_CONTINUE_MAX` / `CC_MECH_MAX` / `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` arithmetic, and "Within a turn, keep working rather than stopping on 🔧" | G:1129-1140 keeps the measured bound text; R:105 already says "🔧 does not end a turn. Keep going" |
| R-12 | "they go through `cc-backlog needs "<step>" --class needs-human`, which carries no conviction" | R:186 (c) and R:193 give the same routing; G:1041 keeps the sentence |
| R-13 | The example "(`12 runnable now, 195 need your call`, not `205 manual steps`)" | R:144, two lines up, gives the same shape (`13 runnable now, 207 need your call`) |
| S-2 | The `jq` registration check for `frontier-spawn-gate.sh` and the migration's class | G:376 (verified: `grep -n 'migrations/0029' CLAUDE.global.md` → line 376) and the frontier-routing skill. The rule that it counts only once the operator runs `migrations/0029` stays in S |
| S-4 | "(whether it should be is an open operator decision, `docs/plans/NONLIMIT_RESUME_LADDER.md` § W3.6)", a perishable status note | G:376 (`grep -c NONLIMIT_RESUME_LADDER` → 2) |
| S-5 … S-11 | Rationale and citations: why depth is the only bound (S:116), the effort-sweep citation (S:141), why the Keychain leaks (S:74, shortened, not removed), the `.git/config.lock` incident (S:159), the `accounts.json` flags behind "no dollar exposure" (S:141), the launcher's flags (S:132), the source path of the full text (S:3) | G, verified per item (heading of the S-5 block). Every instruction those sentences carry stays in S; only the "because" moves |

**Cuts outside the close protocol (S-2, S-4 … S-11) are scope beyond the ruling's letter.** They touch Frontier
Tier Routing, Research subagents, API keys, Worktree isolation and the file header. Each removes only rationale the
full text keeps, but the implementer should name them in the commit body as budget payment. If any owner objects,
dropping that cut leaves a measured overage equal to its delta in the table above.

The land gate would not refuse growth here: repo-side sources classify as tier `source`, and `range` applies only
the 40k per-file cap (`maps/rules-text.md` §6). The one-in-one-out policy (`config/instruction-budget.json`
`destinations.user`) is the reason for the cuts. **Re-gate debt (flag, not decide):** `docs/plans/INSTRUCTION_BUDGET.md:127`
records the operator deferring the held-out F1 re-gate "until the next slim edit" (about $403 list). Ten slim edits
have landed since without it (`maps/rules-text.md` §6). An edit of this weight is the kind the deferral named.

---

## 5. Infinite-loop and false-block analysis

D1 changes no hook, so no hook gains a new block arm. The analysis below covers every **existing** mechanism the
new text causes to fire more often, with its bound.

| # | Mechanism the text now triggers | Can it loop? Bound | Can it false-block? |
|---|---|---|---|
| L1 | Agent arms `session-continue.sh set` under ⛔ or ✅ with ungated work (R-10). The armed path blocks each Stop with the step (`hooks/session-continue.sh:1529-1538`) | The same profile as 🔧 arming today. Bounds: (i) a chain not re-armed stops at `CLAUDE_CONTINUE_MAX`=8 (`:1445-1458`); (ii) an identical re-block after a no-write forced turn is skipped (`:1371-1442`), so a lead that truly has nothing to do costs about one wasted turn; (iii) the kill-switch clears it (`:1337-1342`); (iv) SID-bind. The agent-armed chain is "unbounded by design" (G:1129-1140) only while the agent keeps re-arming, which is the intended driver for real work | No. It blocks only a session whose own model armed it. A wrongly armed session is released by (ii) or (i) |
| L2 | A loop scope drives rounds with no automatic end (R-2, R-6) | **Yes, by design, bounded by the scope.** A non-converging "loop until dry" (B13: 33 rounds, about 80 confirmed items a round, TX:4254 option text) runs until the stop condition holds, the operator answers the class-B packet, or the weekly limit ends the session. That is what the frozen scope and the 2026-10-15 ruling by silence (`eb3dbe1e5e94`) said. The operator's remedy is an answer, which the class-B packet with its deadline asks for. A round that needs an operator-only act gates that round (R-6: "work built on one of its answers"), which releases the loop (`maps/legit-stops.md` §6 C7) | No |
| L3 | Class-B routing makes `BLOCKED=0`. A clean, landed loop session then reads `RUNG=✅` (control C5, `maps/incident-replay.md` §7) | boundary-handoff's free-win may block once per HEAD (`hooks/boundary-handoff.sh:796-798`), re-armed by +10% fill, +10 MB or 30 min idle (`:161-171`, `:816-832`). It abstains when the continuation sentinel exists (`:687-694`), which is L1's state. A recycle is a new session, so there is no in-session loop | **A forced turn, not a false block.** It advises a recycle at ≥35% fill. With R-2 the loop scope is in the store with `session=`, so the same-pane successor gets it back as "THE CURRENT CONTRACT" (`hooks/dod-persist.sh:461-470`). Outcome: a fresh context that keeps looping |
| L4 | `operator-readout.sh` prints `✅ SAFE TO CLOSE` over an open loop scope under L3 | No loop; a `systemMessage` never extends a turn (`maps/stop-hooks.md` §1) | No block, but a **misleading certificate**. The text cannot fix it; the `LOOP_OPEN` ledger field can (`maps/wrap-ledger.md` §6). Named in §8 |
| L5 | `autonomy-sweep.sh` fires the class-B default at its deadline (`:557-605`) | Once per packet: the status flips to `expired-actioned` exactly once (`bin/cc-decide:626-640`) | With `--default-effect no-change` it files nothing (`autonomy-sweep.sh:565-579`). Without it, a misrouted work row (`df779857c4ff`). R-7 makes the flag part of the template |
| L6 | The agent keeps a model-armed `cc-await-ping` timer while a decision is open (R-6) | Each timeout wakes the session once (W-b, `maps/wake-path.md` §1). Bounded by instruction only: G-4 says to double `--timeout` after an empty wake (55 min, then 110, then 220 …); the slim line does not carry the doubling, so a session reading only S/R may keep a fixed timeout (the default is 1800 s, `bin/cc-await-ping:38`). Under a live `/goal` the text exempts it, since a running background Bash suppresses goal evaluation (`S:100`) | No block. Cost in a genuinely all-gated session over a 10 h gap: about 4 turns with doubling (estimated: 55+110+220+440 min ≈ 13.75 h covers it), about 11 at a fixed 55 min, about 20 at the 30 min default (estimated: gap ÷ timeout). The e582464c hourly pattern cost about 10 (estimated, 1 per hour). This is the price of the self-wake; §8 item 3 says why the supervisor nudge is the better (f) |
| L7 | More class-B packets reach the operator's queue | No loop | No block. Each carries a default and a deadline, so it closes itself. That is the P15 design (`docs/research/desk-audit-2026-07-18/p15-escalation.md:127-133`) |

**Gates checked for weakening (none weakened):**
- G2 escalation surfaces stay as they are: R:45 is unchanged, and R-6/G-4 say the gated act still waits.
- Class C keeps every rule-mandated operator-only act (R-7).
- `/ship` refusal is still ⛔ (R:62, unchanged).
- Money-landing 📦 is still terminal-valid (R:58, R:103 keeps the clause).
- The research-program exemption is unchanged (R:74-80), but R-2 does not name it. A program's scope is fixed
  upfront by design (`d7170beba120`, 2026-10-03: the operator chose "an exhaustive upfront fixed scope/goal posts
  strategy" over open-ended review rounds), so a program scope written as a loop is unlikely. Where one exists,
  R:77's more specific rule governs the close question: "answered by relaying the certificate; residuals it names
  are not open work". A code floor would have to abstain on `research-program.sh is-active` (`maps/legit-stops.md`
  §6 C5); text cannot enforce that.
- Explicit pauses (R:49), the kill-switch (R:223) and an unreconstructable scope (R:26, kept) still stop.
- completion-assert's `blocked-answered` exoneration (`hooks/completion-assert.sh:1218-1231`) is untouched. A
  legit all-gated ⛔ close is still honest.

---

## 6. Replay: does D1 prevent the B13 idle?

### 6.1 Decision by decision, at filing time (02:23-02:36Z)

| Moment | Today | Under D1 (if the text is followed) | Lever |
|---|---|---|---|
| 02:23Z, operator asks whether the $100 Codex plan is being used (TX:4163) | Research ends "no ruling found" (TX:4235); `290215743799` filed class C (TX:4260) | § Standing operator grants covers it exactly: committed code, `git archive`, Codex CLI, under 80%. No packet; wire a Codex reviewer into round 27 | S-1 (d) |
| 02:36Z, "stop the loop and paste v33?" at 85% (TX:4254) | Filed class C, "no" option = the frozen scope | (1) Ruling search: the plan's log (`bring-back-ocr.md:885-886`) or the `loop` jq (17 hits incl. `eb3dbe1e5e94`, measured) shows the same fork settled by silence. (2) New evidence (24 more rounds) makes a re-ask legitimate, but as **class B**, default "keep running rounds as scoped", `--default-effect no-change`. That is the shape the lead re-filed itself at 18:31Z (`b4780d7bb60e`, `maps/incident-replay.md` §3.2) | R-4, R-7 (b, c) |
| 02:36:34Z, "No round 27 until e869fac7eb34 is answered" (TX:4270) | Accepted by every hook | Contradicts R-6: a question about changing the frozen scope gates nothing. Round 27 starts; the lead arms `set "run round 27"` | R-3, R-6, R-10 (a, e) |

Each of R-3/R-6, R-7 (class B) and R-4/R-7 (ruling search) independently defeats the hold on decision 1. S-1 alone
removes decision 2.

### 6.2 At the three idle closes (stub state from `maps/incident-replay.md` §5, §7)

| Close | Ledger today | Ledger under D1 (class B + no packet) | What stops the idle under D1 | Mechanical, or text-dependent? |
|---|---|---|---|---|
| F1 06:44:40Z (TX:4437) | `RUNG=⛔ BLOCKED=2` | `BLOCKED=0`, `DIRTY=0`, `REMAINDER=0` ⇒ `RUNG=✅` (estimated from `wrap-ledger.sh:2604-2620`) | (i) If round 27 was armed (L1), the armed path blocks this Stop: **mechanical**. (ii) If not armed, boundary-handoff free-win sees ✅ at 64% ≥ 35% and blocks once with recycle advice (L3, estimated from `boundary-handoff.sh:629-660`; the 900 s exchange window had long passed, since the last operator text was 02:22Z): **mechanical forced turn**, and the successor re-reads the persisted loop scope. (iii) R-2/R-6 tell the model ✅ does not end a loop | (i), (ii) mechanical once the text has done its part at filing time; (iii) text |
| F2 07:39:47Z (TX:4458) | same | same | Only reached if F1 ended idle. Its own timer woke it (TX:4445). The close re-meets R-6's "only ⛔ when every remaining item waits". boundary-handoff's latch holds per HEAD (no new commit), so it is silent unless 30 min idle re-arms it (`:816-832`; the 55-min gap qualifies, estimated) | Text, plus a possible second free-win |
| F3 08:34:59Z (TX:4476) | same | same | R-6 forbids stopping the timer while a decision is open ("I'm stopping the inbox watcher for now") | **Text only.** After this Stop nothing in D1 can act. That is the lead-supervisor gap (§8) |

**And if the lead still files class C (non-compliant on R-7)?** Then the ledger reads ⛔ exactly as today, no hook
blocks, and only R-6/R-10's text stands between the lead and the idle. D1's mechanical help (L1, L3) disappears
in that branch. That is the main residual risk, and why the code designs exist.

### 6.3 Controls (must not change)

| Control | Under D1 | Result |
|---|---|---|
| C1 ⛔ with lanes in flight (TX:4316, 03:09Z) | Lanes are ungated work in flight; R-6 does not require idling or re-arming; R:21 custody "awaiting with a wake path armed" is unchanged | Allowed, unchanged |
| C2 legit class C (`d610f8473106`, self-modification) over a subset, round 27 running (TX:4769) | R-7 keeps self-modification in class C; R-6 says keep driving round 27, which the lead was doing | Unchanged |
| C3 permission denial gating Codex only (TX:4683) | Class C (permission denial). R-6: round 27 continues Claude-only; with nothing in flight it must drive round 27, not idle | Improved; no new block |
| C4 all-gating money or self-mod gate, scope exhausted | Every remaining item waits on it, so R-6's condition holds and ⛔ ends the turn | Allowed |
| C5 the class-B re-file without a loop floor | Ledger ✅; R-2 says a loop is open, and L3 recycles into a successor that keeps the scope | Better than today's estimated outcome (recycle advice with the scope lost); the false certificate remains (L4) |
| Legit stops 43055acd, e582464c, c56c729c, 79076bcf, fd91140d (`maps/legit-stops.md` §4) | Each had no ungated in-scope work at the idle. Their packets were money (L2), a credential (L4), auth/re-key (L5/L6) and a pick with no status quo (L11), all class C under R-7, so the ⛔ close stays valid. e582464c pays the L6 watcher cost, now with doubling | Allowed, unchanged |
| 9240c6a9 on 10-22 (three scope-extension questions with "no" defaults) | Under R-7 these become class B with default "out of scope" and close themselves at the deadline instead of sitting as ⛔ | Improved |

---

## 7. What D1 deliberately does NOT do

- **No hook, ledger, CLI, settings, plist or registration change.** No `LOOP_OPEN`/`UNGATED`/`GATES_ALL` fields,
  no session-continue ⛔ floor, no `--gates`/`--ceiling` flag, no `cc-decide open` ruling hint, no lead-supervisor
  nudge, no boundary-handoff ⛔ arm.
- **No anti-deference phrase.** "need your call" is the ledger's prescribed ⛔ readout (`wrap-ledger.sh:2607-2609`,
  R:92), pinned by `tests/anti-deference-nudge.bats:706-717`.
- **No rewording of the ⛔ readout line** (R:92/G:714). It is pinned (`tests/wrap-ledger.bats:1851`, `:1866-1867`)
  and stays correct for a real class-C ⛔.
- **No `- [ ]` box for a loop scope** (§2(e) item 3): it would be a permanent, inherited 🔧.
- **No new rules file and no `config/` edit** (§2(d)).
- **No change to E0** (R:99): it is pinned by `tests/close-research-pending-rules.bats:15-27`. It still says
  "files … so the rung is `⛔`", which under R-7 holds only for class C. A judgment call it files as B is still
  on record, so E0's purpose (no silent E0) holds.
- **No grant beyond the ruling.** Codex plan only. Antigravity is recorded as open. Personal-data egress stays an
  ask. Slot routing is untouched.
- **No machine-text edits** (§3.4). They are listed for the code designs.
- **No re-file of live packets.** `b4780d7bb60e` (open class B) has `default_effect: ""` and `subject_project: ""`
  (`maps/cc-decide.md` §0.3); fixing it is a `cc-decide` store write, out of scope here.

---

## 8. What text alone cannot guarantee

1. **Compliance.** Every lever is an instruction. The B13 lead ignored existing text that already pointed the
   other way: R:4 ("without stopping to ask"), R:189's exhaustion close (drive everything first), S:81 ("do the
   rest now") and S:166 ("Idle (waiting or watching) at 35% or more … recycle", while it sat at 64%,
   `maps/incident-replay.md` §5). D1 removes the contrary text, which won once (§1.2 item 1), but it cannot show
   the new text will win. **Effectiveness is unmeasured.** n=1 supports no estimate; §9 T-E specifies the eval
   that would measure it.
2. **(e) has no refusal when the agent does not arm.** If the lead files class C and never arms the continuation,
   every Stop hook behaves exactly as at F1-F3 (`maps/stop-hooks.md` §0).
3. **(f) has no wake after the last Stop.** F3 was the last Stop before a 9 h 36 m gap (`maps/incident-replay.md`
   §1). Only an out-of-session sender (lead-supervisor through `cc-notify` → `cc-wake`, `maps/wake-path.md` §5)
   can reach it.
4. **Machine text still contradicts the rules** in the class-C-over-a-subset case (§3.4). The model has to apply
   the precedence sentence against a ledger line saying "nothing below it closes".
5. **The ✅ certificate can be false over an open loop** (L4) until the ledger learns loops.
6. **workflow-lean slots and other runtimes** load no CLAUDE.md (`S:117`), so none of this reaches them.
7. **A rule is live only after converge** (`scripts/deploy-live.sh:52`). A session loads its instructions at
   start, so one started before the converge may keep the old text until it recycles (estimated by analogy with
   the hook-set staleness `maps/incident-replay.md` §0.7 measured; not measured for instruction files).

**Recommended pairing.** Ship D1 first: it is cheap, live at the next converge, and it removes the text that
licensed the idle. Then add the smallest code backstops for items 2, 3 and 5: a ledger `LOOP_OPEN` field plus a
session-continue ⛔ floor keyed on it, and the lead-supervisor subject nudge. D1's text is written so those
backstops agree with it: the same predicate (⛔ ends a turn only when nothing ungated is left) and the same
discharge (re-file as class B, or do the work).

---

## 9. Tests

New file `tests/lead-keeps-working-rules.bats`. It sets `export HOME="$BATS_TEST_TMPDIR/home"` in `setup()`
(hermeticity rule 1, `scripts/test-hermeticity-lint.sh:18-20`), names `CLAUDE.rules.slim.10-session-close.md`,
`CLAUDE.global.slim.md` and `CLAUDE.global.md` as literal paths in executable text so `gate-select.sh --direct`
selects it (`maps/test-infra.md` §2.2), and uses `! cmd || false` for negations (bats-assert-liveness). Pattern:
`tests/close-research-pending-rules.bats`, `tests/research-program-exemption-rules.bats:15-16`. "Red without the
change" means the test fails against `origin/main`'s files. G wraps at about 110 columns, so normalise whitespace
before grepping it (`tr -s '[:space:]' ' ' < "$G" | grep -qF …`).

**Pre-check already run (measured).** A read-only `python3 -I` pass applied this file's blocks in memory and checked
79 positive strings (present after the change) and 12 negative strings (absent after, present before) from T1-T13.
All 79 are present after. 75 are absent before, so those tests are red today. Four already occur elsewhere in their
file (`credential` in R; `model-config.yaml` in S; `customer` and `escalation surface` in G), so T4 and T13 must
grep inside the paragraph or section. All 12 negatives hold.

| # | Name | Fixture | Assertion | Why red today |
|---|---|---|---|---|
| T1 | decision row drives ungated work, both variants | `R`, `G` | the `\| Needs a decision` row of R contains `keep driving every in-scope item it does not gate` and `stop only when it gates all of them`; G's row contains `keep driving every in-scope item it does not gate` and `ALL remaining in-scope work`; R does not contain `Stop and ask, overriding auto-continue`; G does not contain `**STOP-ASK** (overrides auto-continue)` | Old rows contain the removed phrases and lack the new ones |
| T2 | ⛔ ends a turn only when all is gated, both variants | `R`, `G` | both contain `when every remaining in-scope item waits on an open decision` (G: case-insensitive, `EVERY`) and the gate definition `gates only the act it asks about`; neither contains the old unconditional sentence `Only ⛔, and 📦 in a repo` | Old R:103/G:766 is the unconditional sentence |
| T3 | precedence over machine ⛔ text | `R`, `G` | R contains `a ledger or hook line saying to stop or clear on ⛔ means the all-gated one`; G contains `it means this all-gated ⛔` | New sentence |
| T4 | class routing: B for status-quo judgment calls, C reserved | `R`, `G` | the filing paragraph contains `--class B`, `--default`, `--deadline`, `--default-effect no-change`, `--project`, `cc-decide help`; the class-C clause names `self-modification`, `money`, `permission denial`, `credential` and `no status quo` (scope the grep to the paragraph: `credential` already occurs elsewhere in R); R does not contain `filing is what makes it the` and G does not contain `filing it is what makes it one` | Old R:160/G:1000 hard-code `--class C` with those phrases (measured `grep -c` → 1 each) |
| T5 | BLOCKED redefined | `R`, `G` | the BLOCKED bullet (R) and row (G) contain `class-C` and `nothing ungated is left`; no file of S, R, G contains `a real value fork` (today it is at R:189 and G:1042 only, measured `grep -c`) | Old text has "a real value fork" |
| T6 | ruling search before asking | `R`, `G` | both contain `expired-actioned`, `cc-decide list --all --json`, `cc-memory-search --all`, `Standing operator grants`; R's F2 bullet and G's F2 paragraph contain `unless a ruling`; G contains `29d62f1ad390` | New text |
| T7 | the cited ruling search finds a fired class-B default (positive control of the cited command) | `CC_DECISIONS_DIR=$BATS_TEST_TMPDIR/d` with two hand-written packets via `jq -n` (pattern `_raw_pkt`, `tests/cc-decide.bats:180`): an `expired-actioned` class B whose `what_plain` contains "setup-prompt loop" and `default_if_no_veto` "keep looping until dry", and an open class C | `bin/cc-decide list --all --json \| jq -r '.[] \| select(.status != "open") \| select(.what_plain \| test("(?i)\\bloop")) \| .id'` prints exactly the B id; and R contains `cc-decide list --all --json` | Green before and after by design: it pins the contract the rule cites (if `list --json` or the status names change, this goes red and the rule is stale). The pattern is `research-program-exemption-rules.bats:60-74` |
| T8 | loop scope defined, persisted, no box | `R`, `G` | R-2/G-1 text contains `loop until`, ``newer `Scope (frozen):` line ends it``, `dod-persist.sh set`; R contains ``never add a `- [ ]` box``; G contains `Never add a box for a loop` | New text; old R:26 says "(`dod-persist.sh` captures it)" |
| T9 | no-box claim is true (behavioural control) | `WRAP_DOD_FILE=$BATS_TEST_TMPDIR/dod.md` (honoured by both producer and ledger, `hooks/lib/dod-path.sh:268`). A single-line `set` cannot make a box: `set` prefixes `Scope (frozen): ` to any text without a Scope tag (`hooks/dod-persist.sh:487`). So the fixture uses two multi-line sets: `set "$(printf 'Scope (frozen): loop until dry\n- [ ] loop open')"`, then `set "$(printf 'Scope (frozen): loop until dry, ended\n- [x] loop open')"` | `scripts/wrap-ledger.sh --machine` in a fixture repo (the `ok_state` git facts of `tests/wrap-ledger.bats:319-324`) reports `REMAINDER=1` after the second `set` | Green before and after. It proves the rule's reason (append-only, the box never clears) and goes red if dod-persist ever gains a rewrite, at which point the rule should change |
| T10 | auto-continue arms on ungated work under ⛔/✅, both variants | `R`, `G` | R's heading is `### Auto-continue actuation` (no `(🔧 only)`); R contains `a ⛔ or ✅ ledger over ungated in-scope work` and `all-gated ⛔`; G contains `**Auto-continue actuation.**` and `an all-gated ⛔`; neither contains `and only on 🔧` / `and ONLY 🔧` | Old text has "and only on 🔧" and lists ⛔ as a clear state |
| T11 | the armed path really is rung-blind (behavioural control for R-10) | `tests/session-continue.bats` helpers `arm`, `actuate`, `fired` (`:66-98`) plus the `ma_fixture` ledger stub (`:506-519`) printing `RUNG=⛔` | after `arm "run round 27" $SID`, `actuate` on a Stop JSON for `$SID` blocks with the step in `reason` | Green before and after. It pins the hook behaviour R-10 relies on; if a later change adds a rung check to the armed path, this goes red and R-10 must change with it. Goes into `tests/session-continue.bats` (grandfathered, existing helpers) |
| T12 | self-wake timer kept; G carries the detail | `R`, `G` | R's holding-work paragraph contains ``keep a `cc-await-ping` timer`` and `run_in_background`; G contains ``never a detached `cc-await-ping … &` ``, `double`, `re-read your open` and `names your open decision ids` | New text |
| T13 | standing grant present in both variants with its envelope | `S`, `G` | both contain `## Standing operator grants (All Projects)`, `git archive`, `codex exec -s read-only`, `80%`, `a247b7288149`, `customer`, `escalation surface`, `model-config.yaml`; S contains `paid API`; G contains `pay-per-token`, `api.openai.com`, `window_minutes`, `personal messages` and (case-insensitive) `uncertified means unrouted` | Section absent today (`grep -c 'Standing operator grants'` → 0 in all three files). Scope the greps to the section: `model-config.yaml`, `customer` and `escalation surface` already occur elsewhere in S or G |
| T14 | the grant routes no slot | `S`, `G` | the grant text contains `model-config.yaml` and does not contain `research_adversarial` | Guards against a later edit turning the grant into a routing rule |
| T15 | parity | — | Every test above asserts its clause in both variants (R or S, and G). Under `global full` only G deploys and the slim rule file is retired (`install.sh:1117`, `tests/install-instructions-variant.bats:80-89`), so a clause missing from G is missing for that variant | Structural: T1-T14 each fail if either variant lacks the clause |
| T16 | budget does not grow (procedural, not bats) | the files before and after | `python3 -I hooks/lib/instruction_budget.py measure CLAUDE.global.slim.md CLAUDE.rules.slim.10-session-close.md` sum after ≤ before (designed: 58,790 → 58,786); record both in the commit body | A hard-coded total in a bats file would break on every unrelated slim edit, so this is a land-time check |
| T-E | **behavioural eval (the only measure of D1's real effect)** | B13 transcript prefix through TX:4253 (just before the first `cc-decide open`), replayed headless N times under the old and the new `R`+`S`. Precedent: the 24-run blind-judged probe cited at `hooks/dod-persist.sh:195-197` | Count runs that (a) file either question as class C, (b) write a hold over round 27, (c) start round 27 or file class B with a keep-looping default, (d) file decision 2 at all. Pass: (c) in most new-rule runs and a clear drop in (a), (b) and (d) against the old-rule runs | Measures whether the text moves the model. Without it D1's effect is a claim. Costs model quota (N×2 runs), so it needs the operator's go-ahead under the re-gate deferral (§4.3) |

Existing suites the change selects and that must stay green (run them yourself and check the `1..N` plan line; a
`cc-bats` exit 75 is no verdict, `maps/test-infra.md` §1.1): `tests/close-research-pending-rules.bats` (E0 is
untouched), `tests/research-program-exemption-rules.bats` (R:74-80, R:191 untouched), `tests/install-instructions-variant.bats`,
`tests/deploy-parity.bats`, `tests/cc-memory-search.bats`, `tests/tokeff-regate-harness.bats` (selected by
`CLAUDE.global.slim.md`, `maps/test-infra.md` §2.3). Then run `scripts/ship-land.sh --precheck --working` for the
lint arms. After converge, check `diff -q CLAUDE.global.slim.md ~/.claude/CLAUDE.md` and
`diff -q CLAUDE.rules.slim.10-session-close.md ~/.claude/rules/10-session-close.md` are silent
(`maps/test-infra.md` §7).

---

## 10. Implementation notes

- One commit for the rule text (R, S, G together), one for the new bats file plus the T11 case, so a revert of
  the text leaves the pins red and visible. The commit body carries §4.2's numbers and T16's before/after.
- This edits rule text every session loads. Under the ruling it is self-modification, run by the dispatched
  claude-infrastructure session the operator approved (`d610f8473106`, evidence "Yes, upon a comprehensive
  Dynamic Workflow research … before implementing").
- Live only after `CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh` (`maps/test-infra.md` §7).
- G-4 and G-5 cite `docs/research/lead-keeps-working-2026-10-24/maps/*.md`. Those maps were committed on this
  branch during this run (`b6b53ea89`, measured `git log -- …/maps/`), so the citations resolve once that commit
  lands with or before the rule commit. This design file is still untracked.
- Applying the blocks: each `old` body occurs exactly once (§4.2 count column), so an Edit with that exact
  `old_string` per block is safe. Re-run the §4.1 measurement after applying, because any slim edit landed
  between now and then shifts the totals.
