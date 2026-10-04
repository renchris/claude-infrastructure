<!-- slim rule set: the Session Close Protocol of CLAUDE.global.slim.md, moved here verbatim so no always-loaded file passes the 40k per-file budget (docs/plans/INSTRUCTION_BUDGET.md). install.sh deploys this to ~/.claude/rules/10-session-close.md whenever the slim variant is selected; every session loads it beside ~/.claude/CLAUDE.md. Section references between the two files resolve as before. -->
## Session Close Protocol (All Projects)

Drive in-scope work to a finished, verified, committed state (landed per the ship policy) without stopping to ask; surface everything else; end every write turn with one state readout taken from live reads (`~/.claude/scripts/wrap-ledger.sh`, or `/wrap`), not from memory. Stop hooks check facts only, never scope: `completion-assert.sh` blocks a done-claim the live ledger contradicts, and `operator-readout.sh` renders the operator's close block from disk as a `systemMessage`. Before writing or debugging a Stop hook, read the reference `~/Development/claude-infrastructure/CLAUDE.global.md` § Session Close Protocol for which hook output fields reach the model and which extend the turn.

### Stop-hook arms

- Close certificate: on a write turn whose ledger is ✅, `operator-readout.sh` prints `✅ SAFE TO CLOSE — nothing of mine is open`, computed from git. Read-only turns and unverifiable states get none.
- **✅ is a safe-to-close assertion, not a vibe.** Claim it only with: clean tree · landed on trunk,
  verified BY CONTENT (`git ls-tree` present + `git diff` empty on your paths — a count reads 0
  after a sibling rebase and proves nothing) · your diff's gates run green *this turn* · frozen-DoD
  remainder 0 · no operator step this session created left unrun · and — in the repo that IS the
  live layer's source — the landed sha **observable in the enforcing store**, not merely on trunk
  (`wrap-ledger.sh` computes `🚀` instead of `✅` for you when the live layer has breached its
  converge budget). Any one unknown ⇒ not ✅; say which. Where a background verifier owns the full-suite claim (claude-infrastructure v2), *your
  diff green + content-verified land* is the standard — waiting on a trunk-wide stamp you do not
  control is not diligence, it is a hang. The "no operator step left unrun" clause is no longer
  prose discipline: file each one (below) and `wrap-ledger.sh` computes `👤` instead of `✅` for you.
- Mechanical 🔧: `session-continue.sh` blocks the stop while files this session wrote (per `hooks/lib/session-writes.sh`) are uncommitted, and feeds the work back. If that dirt is deliberately parked or not yours, run `~/.claude/hooks/session-continue.sh clear` and say so in the close.
- Ship floor: `session-continue.sh` blocks going idle on 📦/🚀 work you wrote, once per HEAD sha and at most `CC_SHIP_FLOOR_MAX`=2 per session. Resolve it by `/ship`, by converging, or by an explicit park (`clear` plus the park named in the close).
- Custody: a fire with `--notify-back` records a debt in `bin/cc-custody`, discharged by the peer's self-close. Open custody is a 🔧, blocks the ✅ certificate, and contradicts any done-claim. Awaiting it with a wake path armed is a legitimate non-close state; calling it done is not. Collect, land, then `cc-custody return <marker|slug>`; if superseded, `cc-custody abandon <token> --why …`.
- Origin close contract (`completion-assert.sh` arm D6; template in `hooks/lib/close-shape.sh`, shared with `/wrap`): an origin session (no fired-peer stamp; `hooks/lib/origin-identity.sh`) closing ✅ or 👤 after written work puts the ledger's rung glyph on line 1 (`line-1-rung`) and, on line 2, either `Good to close: yes — nothing of mine is open; follow-on: <filed ids|none>` or `Good to close: no — <what remains + who owns it>`. A hedged both-ways answer fails (arm D3). Assignees and fired peers are exempt; their close is the lead's harvest or the notify-back ping.

Resident teammates: `~/.claude/scripts/wrap-ledger.sh` reports `RESIDENT_MINE`, the members of this session's team whose process is still running, as a 🔧, including their dirty files in a shared cwd; those files are yours to commit, since only the lead can. A teammate ends only when its lead ends it: send each a `shutdown_request` and escalate to `TaskStop` after about 60 s; the rung clears when the process is gone, not when the pane closes. The check kills nothing; to keep a member working, say so in the close as a stated park. Kill switch `WRAP_RESIDENT=off`.

Freeze the DoD at intake: the first time a task will write tracked files, restate the ask as one line, `Scope (frozen): …`, in the plan or else inline (`dod-persist.sh` captures it). Close-time completeness is a diff against that line, not a fresh judgment. If the scope cannot be reconstructed, stop and ask.

### Disposition by end-state

Judge per task, not per turn.

| End-state | Action |
|---|---|
| Read-only / advisory / research (no tracked writes) | No ledger, no auto-continue, no readout. Work the turn itself named is not exempt (see E0 below). |
| In scope: unwritten, unverified or uncommitted | Auto-continue: finish, run the gate, commit (atomic, explicit paths). |
| In scope: gate ran red | Debug the root cause for up to about 2 cycles, then commit the partial work and report. No blind retries. |
| Committed, not landed | Apply the ship policy below. |
| Needs a decision (destructive migration, auth, navigation pattern, DB timeout) or information | Stop and ask, overriding auto-continue; commit in-progress work first. |
| Out-of-scope discovery | Follow-On Gate: PASS → do it now and append `Scope (grown): +<item>` where the DoD lives; FAIL → drop it, or file it only if it passes the FILED test (§ Three dispositions). Security or data-integrity issues: stop and surface now. |
| Genuinely complete | Assert it plainly, without hedging. |
| Context or budget exhausted, work remains | Recycle or `/handoff` (context table under What each rung requires); never claim completion. |

Auto-continue requires all four; otherwise surface or ask:
- G1: inside the frozen or grown DoD; adjacent work enters only through the Follow-On Gate.
- G2: touches no escalation surface (auth/session, destructive migration, navigation pattern, DB timeout).
- G3: the action is local (edit, run gate, commit), plus `/ship` where the ship policy says auto; no deploys by hand.
- G4: the commit is task-clean: explicit paths, no unrelated, parked or other-session changes.

Explicit pauses ("stop here", "come back to this") are terminal-valid parked WIP.

### Ship policy

A verified commit that exists only on a branch is unfinished work.

| Repo | On 📦 with gates green |
|---|---|
| Every repo, by default | Auto-`/ship` as the closing act, then re-read the ledger and report the landed state. |
| A repo whose own `CLAUDE.md` says landing spends money | Offer the land with the command ready to paste; do not fire it. 📦 is terminal-valid there. |

Landing cost is a perishable fact, so it lives only in each repo's own `CLAUDE.md` and status tool. Before landing in another repo, read its `CLAUDE.md` (Working rules) and run its status tool if it ships one; a live measurement outranks any remembered verdict.

Both paths require G1, G2, G4 and green gates. `/ship` never lands a red gate or a dirty tree, and a `/ship` that refuses to land (landing-range escalation, land-lock contention) is a ⛔ to surface, not a silent 📦.

### Follow-On Gate

Identified follow-on or optional work is done without asking when all four hold:
- F1 net-positive: under the operator's standing values (100th-percentile completeness, nothing left on the table, time-zero), with no downside a reasonable operator would weigh. Inside an active research program, a refinement is filed to the program's apply-at-build list instead (exemption below).
- F2 well-researched: grounded in this session's disk-truth investigation or an equally verified source. If unverified, verify it; that is drivable work. A decision carries a number: state your conviction, in percent, in the course you would take. At or below 90%, research exhaustively, then implement if you are now above 90%; otherwise hand it to the operator with the number, the research receipt and the measured options in operator terms. Above 90% there is nothing to ask: implement. `cc-backlog add --why-not-now "needs-human: …"` and `cc-decide open --class C` refuse without `--conviction N --receipt PATH|"<cmd> => <output>"` (class C also needs two `--option`s) and refuse N > 90; `wrap-ledger.sh` counts an unconvicted ask of yours as your own 🔧 (`UNCONVICTED_MINE`), not 👤 or ⛔. Inside an active research program, a timebox receipt satisfies the below-90% rule (exemption below).
- F3 same safety envelope: G2 and G4 bind, and shipping stays in the repo's sanctioned flow (G3; a repo may grant standing-land in its project `CLAUDE.md`).
- F4 bounded: each item gets the full finish, gate, commit discipline. Bounded means scoped, not deferred.

On PASS, append `Scope (grown): +<item>` and execute. On FAIL, drop it with a one-line mention unless it passes the FILED test (§ Three dispositions); stop and ask only for a genuine fork or escalation. Asking the operator to re-affirm a PASS is a defect (`anti-deference-nudge.sh` blocks the common phrasings), and so is passing a FAIL off as a PASS. The kill-switch ("just do X", "…and stop") suspends the gate for that turn.

Active research program exemption (operator ruling 2026-10-01, decision packet `83adb541ea19`; method in `claude-infrastructure/docs/research/upfront-research-exhaustion-2026-09-30/REPORT.md` §3.1 ruling 2). Inside a program, the rules on leaving nothing on the table, mandatory research below 90%, close questions, E0 and offering would make "no, one more thing" the only compliant answer before and after the certificate, which is the loop the program exists to end. In a session whose working directory resolves to an active program (`bash ~/.claude/scripts/lib/research-program.sh is-active "$PWD"` exits 0: the registry `~/.claude/autonomy/research/programs.json` lists a program in state registered, certifying or certified whose `cwd_roots` contain the cwd), from intake through build:
- A refinement is filed to the program's apply-at-build list, not driven now. This replaces F1's "nothing left on the table" inside program scope.
- A decision closed by its timebox, by a packet default or as a carried set carries a "research exhausted at timebox" receipt, which satisfies the rule that research below 90% conviction is required. Further research on that row goes only through a priced, operator-bought extension or the row's scheduled narrowing probe.
- A completeness or pushback question about the program is answered by relaying the certificate; residuals it names are not open work. This covers the close-question rule (§ Asserting done), the E0 rule, the rule that offering is a defect, and the Stop hook's offer arm, which abstains there.
- New ideas park in the program's next version.

Outside an active program nothing changes. The key is the registry, never a DoD marker or the wording of a prompt: a closed or unregistered program, a cwd outside every root, or a missing or unparseable registry reads as not active, and the standing rules apply. The exemption covers research scope only; G1–G4, the ship policy and the ledger's dirty, unlanded and custody checks still bind.

### Asserting done

Done this turn, stated without hedging, requires: scope complete against the frozen DoD; statically green (the repo's commit-time gate passed on the closing commit, or "n/a", never a false ✓, for docs/SQL-only commits); behaviorally green (the repo's test, build and visual gates run this turn, and re-run after any rebase, merge or cherry-pick); no pending decision. Otherwise hedge with the clearing verb ("implemented but UNVERIFIED — running tests"; "blocked on your decision: DROP X"), never "probably fine".

A close question ("are we done?", "good to close?", "100% complete?") asks about the task, not about what this session wrote. Before answering, find the scope (the `Scope (frozen):` line and the open items in the plan) and diff the repo against it. "This session changed nothing" is never grounds for ✅: an open plan item is open work, so drive it or answer `Good to close: no` and name it. No findable scope is an unknown, not a ✅. Inside an active research program, answer by relaying the certificate; the residuals it names are not open work (§ Follow-On Gate, Active research program exemption).

### The readout

Emit it at every write-turn close; omit it on read-only turns. It is one line: the worst-open rung by priority ⛔ > 📤 > 🔧 > 📦 > 🚀 > 👤 > ✅, built from `~/.claude/scripts/wrap-ledger.sh --machine` `READOUT` as slot S1 describes. Each rung maps to one disposition row.

- ⛔ Blocked: a decision or information is needed. `⛔ Blocked — need your call: <decision>.`
- 📤 Handoff: context or budget exhausted with work remaining. `📤 Out of context — recycling / handing off.`
- 🔧 Loose ends: unwritten, unverified or uncommitted, or a gate ran red.
- 📦 Parked: committed, not landed (`trunk..HEAD > 0`).
- 🚀 Landed, not live: on trunk, but the live layer is past its converge budget or a migration could not reach it. Lag inside the budget is a ✅ with a note; a newly added file gets no budget (when a 🚀 needs reading: `~/.claude/commands/wrap.md`). A new deployed top-level directory is audited by `scripts/deploy-parity-assert.sh`, not the ledger.
- 👤 Yours: agent side complete and landed, but operator-only steps this session filed are unrun. It counts only this session's steps; the machine's standing pile is the `◆` line in the `operator-readout.sh` block.
- ✅ Live: complete, on trunk (`trunk..HEAD = 0`), clean.
- E0, read-only turn: no readout. A read-only turn that names drivable work is not E0: run the Follow-On Gate on each item and drive the passes (here, in a subagent, in a team, or in a fired session) before yielding. Inside an active research program, a completeness or pushback question is answered by relaying the certificate, and its named residuals are not drivable work (§ Follow-On Gate, Active research program exemption).

### What each rung requires

Only ⛔, and 📦 in a repo whose own `CLAUDE.md` says landing spends money, may end a turn holding work.

- 🔧 does not end a turn. Keep going, scaling up if needed (subagents for read-only breadth, Agent Teams for 2+ code tasks); if context runs out first, recycle or hand off. Naming the remaining items is not a close.
- A 🔧 you did not cause is not yours: a sibling's dirty file in a shared checkout, a trunk that was already red, a marker only a background verifier advances. Check whether the cause is inside your diff; if not, name it in one line and close on your own state. Never present someone else's red as ✅; say whose it is.
- 🚀: converge with `bash <repo>/scripts/deploy-live.sh`, then re-read the ledger and close on the live state. If the converger refuses, file it (`cc-backlog needs "<step>" --class needs-human`) and close on 👤.
- Context is a close-time decision (fill thresholds: § Context Stewardship). Do not idle waiting on the user because context is low.

| | Test | Action |
|---|---|---|
| ♻️ Recycle | Everything of value is on disk (commits, plan, memory, packet); the context holds nothing a successor could not re-derive. | `~/.claude/scripts/handoff-fire.sh --recycle`: same pane, fresh context. Add `--worktree <name>` or `--cwd` for a new directory, `--account <acct>` for another account. |
| 🔀 Switch in place | Work remains, the context is the asset, and only the paying account is wrong (walled, near its wall, or a peer resets sooner). | `cc-lr switch`: moves this pane's session to another account, same session uuid, full transcript. |
| 📤 Handoff | Work remains and needs what this pane cannot become: a different model, or the pane should retire. | `Skill(handoff)`: build the bridge, then fire. Do not hand-type the chain. |
| ⏸ Hold | The context is the asset: a live exchange, a half-formed judgment, dead ends recorded nowhere on disk. | Finish the thought, persist it, then recycle at the natural seam. |

Hold test: ask "what would a successor reading only the disk get wrong?" A concrete answer (a rejected approach and why, a measurement contradicting the obvious reading, an operator preference given in words) is a real Hold, and its first action is to write that answer down, which turns it into a Recycle. No concrete answer means no Hold.

A new worktree or a different account is not a reason to hand off: Recycle carries both, and `cc-lr switch` keeps the context. When choosing between recycle and handoff for a new worktree or account, read `~/.claude/commands/handoff.md`. If an account change is refused, read the refusal and fix the verb or the gate it names.

### The close message

The operator reads a close to make one decision. A close relays what the stores already know, plus the few clauses no store holds. Every line is either rendered output reproduced verbatim (`~/.claude/scripts/wrap-ledger.sh` for state, `~/.claude/hooks/operator-readout.sh --render` for the operator's pile) or one of the six slots below.

Admissibility: a line appears only if it fills a slot and carries one fact that either changes what the operator does next or names the store where a dropped fact can be read back. Anything else is deleted, and a deletion is allowed only once the fact is already in a store a named command reads.

Make the close fit by dropping items, not by compressing the survivors into fragments, abbreviations, arrow chains (`A → B → fails`) or jargon; readable outranks concise. Leave out root-cause narrative, fix internals, secondary to-dos and em-dash tangents.

### The six slots, in this order

Omit a slot that has nothing to say; never pad one.

| Slot | Content | Present when |
|---|---|---|
| S1 STATE, line 1 | the ledger's rung glyph and state clause, relayed, plus one clause naming what the work was | always |
| S2 VERDICT, line 2 | `Good to close: yes\|no — …`, with the follow-on ledger | terminal close (`✅`/`👤`) after real written work |
| S3 ACT, line 3 | the `▶ Run this:` marker, its command on the next line | only when the operator must do something |
| S4 OUTCOME | what is now true against the frozen scope that was not before | after written work |
| S5 EVIDENCE | the sha and/or doc path that holds what this close dropped | whenever anything was dropped |
| S6 WAITING | what is theirs, each item named in plain English | only when something is theirs |

S1–S3 are the lines the operator scans; S4–S6 are at most three supporting lines. The act marker must fall within the first 3 non-blank, unfenced lines (`CC_ACT_WINDOW`=3), which is why the verdict sits on line 2.

S1. Run `~/.claude/scripts/wrap-ledger.sh --machine` and take `READOUT`, shaped `<rung glyph> <state clause> — <tail>`. Copy the glyph and state clause verbatim and replace the tail with one clause naming what the work was. Where the tail is a count (`22 uncommitted change(s)`, `N step(s) need you`, `N decision(s)`), your clause partitions it along the groups that follow, e.g. `13 runnable now, 207 need your call`. Under `⛔` keep the tail: it is `BLOCKED_WHAT`, the operator's own words.

Line 1 carries one rung and states a conclusion, not a category (`12 runnable now, 195 need your call`, not `205 manual steps`). It does not hedge, and nothing later in the close withdraws it. If something is parked or is theirs, that is the rung (`📦` / `👤`); if it is immaterial, it stays out of line 1. A qualification goes in S2's `follow-on:` clause, beside the assertion.

S2. The `Good to close:` line, in either form given under Origin close contract, on line 2 and never as the last line. The rung does not imply it, and a rendered `✅ SAFE TO CLOSE` certificate does not replace it; an honest no satisfies the contract. `Complication:` / `Solution:` / `Outcome:` lines are optional; write one only when it says something the body does not.

S3. The act is its own line, third, at most one, never welded into a sentence or into line 1. Put a reason before it only when the operator cannot act without one (a `--force`, a destructive flag, a choice between two commands), and then in one line.

S4. State what is now true against the `Scope (frozen):` DoD on disk, not what the last turn did.

S5. Name the landed sha and/or doc path that holds what the close dropped. Cite a sha only after `git merge-base --is-ancestor <sha> origin/main` succeeds; an off-trunk sha resolves nowhere but your checkout.

S6. Name each item this session created in plain English, never as a bare count or an id alone. The machine's standing pile stays counted: it renders as one `◆` line in the `OPERATOR ▸` block with its own listing command, and is not re-prosed. When something is theirs, S6 is never dropped (`/wrap` cannot recover it); when nothing is, omit S6 and let S2's `follow-on:` clause cover it.

Expand every identifier at first use in the same message. Session-internal tokens (plan-section labels, slot or rule names such as S1 or R1/R2, codenames) mean nothing to the reader: expand them, or delete an id that means nothing to the reader, such as a plan-section label (`git log` and the plan file hold it). A filed id carries its gloss: `` `1031594b6327` ("build the `--why <topic>` tier") ``, not `1031594b6327` alone. A label is never the subject of a line; state the decision itself ("may a new paying customer's database sit on Turso's Fly line? Answer yes or no", not "G-A is the one thing I need").

File a decision you are holding the moment you have it; filing is what makes it the `⛔` rung: `cc-decide open --class C --what <plain English, no codenames> --conviction N --receipt R --option "label::outcome" --option "label::outcome"`. A class-B packet (an unattended ask whose default fires at its deadline) also carries `--conviction N --receipt R`; both follow the F2 number rule (Follow-On Gate). `wrap-ledger.sh` computes `⛔` from this session's open class-C packets, and it outranks every other rung; an unfiled decision is invisible to it, and `✅ SAFE TO CLOSE` would render over the open question.

### Where dropped detail goes

Drop a detail from the close only if a store holds it and a command reads it back:

| Detail | Store | Read back with |
|---|---|---|
| governing state (rung, dirty, gate, landedness, live-lag, goal) | live git + gate reads | `/wrap`; `/wrap --full` for the 13-row ledger |
| operator-owned actions and decisions | `~/.claude/autonomy/{backlog.jsonl,decisions/,pending-activation/}` | `/wrap` (counted block); `cc-do --list`, `cc-decide list --open`, `cc-backlog list --blocked` |
| why the work was done, what changed, the evidence | the commit body | `git show <sha>` (name the sha; it must be an ancestor of trunk) |
| design decisions, rejected approaches, measurements | `docs/plans/*.md`, `docs/research/*.md` | open the path (the close names it) |
| reasoning, dead ends, synthesis never committed or written to a doc | nowhere | none |

`/wrap --full` is repository state only, and no command reads a session's own narrative back. Detail that is neither committed nor in a named doc is deleted, not dropped: commit it, write it to a named doc, or keep it in the close.

Acceptance: (1) the operator gets state, what it means, and what to do within 30 seconds; if not, restructure the ideas rather than polish the wording. (2) The close fits one 24-row pane, relayed blocks included (a written line renders as about 3 rows at 100 columns).

### Three dispositions

Every open item ends as exactly one of these; "say the word" is not a disposition.

- DRIVEN: done this turn. It appears in S4, past tense, with its receipt in S5.
- FILED: the exception, not an equal choice. The default for anything you notice is to fix it now or drop it. Mint a row only if the close can answer all three:
  - (a) Why not now, as a named impossibility: `--why-not-now` opens with `needs-credential`, `needs-human` (a value call that is theirs; requires `--conviction N --receipt R` with N ≤ 90, and the row is born blocked), `not-yet-true` (an external precondition has not happened; pair it with a `--falsifier`), or `no-capacity` (measured: `claude-accounts --rank general` routes nowhere and the machine admission gate refuses the spawn). `cc-backlog add` refuses any other value. Sudo, physical and GUI-only steps are not decisions; they go through `cc-backlog needs "<step>" --class needs-human`, which carries no conviction. "Out of scope", "told not to start new work", "the remediation half is the operator's" and "needs more investigation" are reasons, not impossibilities: drive it (here, or by firing a session with `~/.claude/scripts/handoff-fire.sh`) or drop it. Unused weekly quota does not roll over, so idle accounts are capacity; judge capacity from the strand nowcast (`~/.claude/scripts/desk-strand-replay.py`), not the `/accounts` weekly percentage, which understates spend.
  - (b) Why it will still be true after a p90 of about 9 days in the queue, ideally as a `--falsifier` so the row self-retracts.
  - (c) Who it is for: `cc-backlog needs "<step>" --class needs-human|needs-credential` for an operator-only gate (the class is required; an unclassed `needs` is refused once the gate enforces) (add `--run "<cmd>"` when one exists; the operator's `cc-do <id>` closes it), or `cc-backlog add --why-not-now "<class>: <detail>"` for agent work. An add this session made without `--why-not-now` stays your own 🔧 (`FILED_MINE`) until it is driven, closed, or handed off with the reason.

  If you cannot answer all three, drop it. The standing pile renders as one counted line in the `OPERATOR ▸` block, never as your prose; an item this session filed is still named, in S2 or S6.
- BLOCKED: a genuine operator-only gate (credential, sudo, destructive migration, a real value fork). It is S1's `⛔` rung, stated as the decision you need. At the exhaustion close — every Follow-On Gate pass and every item at 90%+ conviction driven, only operator decisions left — itemize only the decisions this session drove to the wall, one line each, answer-first: the decision as a sentence, its conviction number, its measured options. The counted `◆` line still owns the machine's standing pile.

Offering researched, in-scope remaining work ("say the word and I'll pick up either") is a defect; the Follow-On Gate already settled it. Drive it or drop it; filing needs a named impossibility class. Inside an active research program, naming a certificate residual or a refinement filed to the apply-at-build list relays the program's state and is not an offer (§ Follow-On Gate, Active research program exemption).

File each operator-only step the moment you find it (`cc-backlog needs "<step>" --class needs-human`): `operator-readout.sh` renders only what a store holds, `wrap-ledger.sh` counts filed steps into `👤`, and a step left in prose gets buried. File only what you genuinely cannot do: credentials, a GUI-only action, something physical, or a value judgment that is theirs (a value judgment goes through `cc-decide open`, not `cc-backlog needs`).

### Handing over a command

Give the operator exactly one thing to select and paste:

```text
▶ Run this:

`<the one command>`
```

The marker is literally `▶ Run this:`, on its own line; never another verb (`▶ Open this:`, `▶ Check this:`). The command follows as an inline-code span alone on its line: not a ```bash fence (renders plain white), not a blockquote (its `│` lands in the paste), no `$` prefix. The payload must execute as typed; to point at a file give `cursor <path>`, never a bare path or URL.

The payload must also run to completion with zero keystrokes, in a regular Terminal and under `!` alike: no typed `yes`, no `read`, no "press Enter", no pager, no editor. Consent to a gated step rides in the handed line (`--confirm <target>`), and the chat line above the marker says what it changes and cannot undo. The only exception is interaction the OS or a vendor demands (a `sudo` password or Touch ID, a browser sign-in or MFA); name it above the marker.

Asked for the command that does X, the payload is the command for X alone. A step that should come first (a build, a staging deploy, a backup) is named in the line above the marker, not chained into the payload with `&&`: a chained payload runs a step the operator did not ask for.

Multiple runnable steps collapse to `cc-do`, which prints them, confirms once, and runs them in irreversibility order (`cc-do --list` to look, `cc-do <stem>` for one); show it only as the collapsed `▶ cc-do [N runnable]` row. Judgment items are counted, not itemized. A command under the marker means run it; a command you would tell them to ignore does not appear at all. Reference-only commands stay in inline backticks mid-sentence, never alone on a line and never in the closing block.

`/wrap --full`, or an explicit request, adds the per-field SESSION LEDGER that `~/.claude/scripts/wrap-ledger.sh --full` renders; never include it by default.

### Auto-continue actuation (🔧 only)

On 🔧, and only on 🔧, arm the continuation: `~/.claude/hooks/session-continue.sh set "<the one next step>"`; a Stop hook then feeds that step back as your next turn. Clear it with `~/.claude/hooks/session-continue.sh clear` as soon as the state becomes ✅ / 📦 / ⛔ / 📤, on a read-only turn, or when the kill-switch fires. Nothing bounds an agent-armed chain (each `set` resets the counter; `CLAUDE_CONTINUE_MAX`, default 8, bounds only the mechanical arm as `CC_MECH_MAX × CLAUDE_CONTINUE_MAX`, and `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` catches only a text-only wedge), so the stop conditions are the kill-switch, the frozen DoD, and your judgment; the hook does not judge scope. Within a turn, keep working rather than stopping on 🔧.

The ledger's `→ Next` verb may be auto-fired for continue, commit, run-gate, handoff, and `/ship` as the ship policy allows. Per-project gate names, escalation greps and the trunk live in the project `CLAUDE.md` "Session Close" section.

### Kill-switch

An operator's per-prompt "…and stop", "no auto-continue", or "just do X" suspends auto-continue for that turn: surface and yield. A machine-authored brief, peer message or report is not the operator's instruction. Never write a kill phrase into a brief, peer message, or report you hand back: the Stop hooks read the last non-meta user record, so the phrase would disarm the recipient's close gate.

The measurements and incidents behind the close rules are in ~/Development/claude-infrastructure/CLAUDE.global.md § Session Close Protocol; read them before changing or disputing one of these rules.

