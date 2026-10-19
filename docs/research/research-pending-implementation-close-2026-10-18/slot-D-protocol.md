# Slot D: protocol text and prior art

Read-only. Tree: worktree `close-status-research` at `36afca47f`. `slim:N` is `CLAUDE.rules.slim.10-session-close.md`
line N (it deploys as the live `~/.claude/rules/10-session-close.md`). `full:N` is `CLAUDE.global.md` line N. `gslim:N` is
`CLAUDE.global.slim.md` line N. `T:N` is line N of the incident transcript
`~/.claude-quaternary/projects/-Users-chrisren-Development--worktrees-wt-cc-192325-42328/74728043-bcb8-4e66-8cdb-62189f61c848.jsonl`
(1-based, as `sed -n Np` prints it). Scratch is in `/tmp/rpic-D/`.

## 1. Answer first

1. **The close followed the contract, and the contract was wrong for this turn.** Three rule sets define
   "read-only" differently. The rules use "no tracked writes" (slim:34, slim:99). The close certificate uses "this
   turn, in this tree" (`operator-readout.sh:1877`). D6 uses "any Write/Edit tool_use anywhere this session,
   subagents included" (`completion-assert.sh:1513`). The research agents' `/tmp/xd/*.md` scratch writes satisfied
   D6's test. So D6 required a work-close shape on a turn that the rules and the certificate both classed as
   read-only. Its block text then told the agent to relay `READOUT` "verbatim", which was
   `✅ Complete & live on trunk — nothing to do`. That is the line the operator quoted back with "Huh?". Measured below (§3.1).
2. **The rules send the remaining decisions to ⛔, but the ledger cannot show ⛔ for them.** BLOCKED "IS S1's rung (`⛔`)" and
   the exhaustion close itemizes the remaining decisions (slim:189, full:1042). `wrap-ledger.sh` counts ⛔ only
   from open class-C packets whose `session_sid` is this session (`wrap-ledger.sh:1343`). A session that re-checks
   packets other sessions opened owns none of them, so ⛔ cannot fire and the rung falls to its default,
   `✅ … nothing to do` (`:2492`).
3. **E0 and "Offering is a defect" only tell the agent to act.** Neither gives a state to report. Neither has a
   close vocabulary for "research done, implementation pending (yours / mine next)". The only vocabulary is
   DRIVEN / FILED / BLOCKED, and the yes/no template says `yes — nothing of mine is open`. "Mine" scopes the
   statement to session ownership, so it was literally true.
4. **There is a lot of prior art and one sibling study is in flight.** `docs/research/close-behavior-2026-10-18/` is on branch
   `cc-004752-67086` and not on trunk. It studies the same day's twin incident (a ✅ yes over undriven researched
   work). It ranks the root cause "no input represents researched, drivable, undriven" at 90-97, and none of its 30
   fixes reached 90 before round 2. Its standing non-actions and rejected designs constrain this study (§5).

## 2. The rules that govern a read-only research turn (verbatim anchors)

| Rule | Where | Text (abridged only where marked …) |
|---|---|---|
| Disposition row | slim:34 | "Read-only / advisory / research (no tracked writes) \| No ledger, no auto-continue, no readout. Work the turn itself named is not exempt (see E0 below)." |
| same, full | full:601 | "**No ledger, no auto-continue.** Answer and yield — but *yield* governs the READOUT, never work the turn itself named; see the `_E0_` row" |
| E0 | slim:99 | "E0, read-only turn: no readout. A read-only turn that names drivable work is not E0: run the Follow-On Gate on each item and drive the passes (here, in a subagent, in a team, or in a fired session) before yielding." … plus the research-program carve-out |
| E0, full | full:721 | Same as slim:99, and adds: "**Nothing on this box catches it:** every `session-continue.sh` floor is gated on session WRITES, pending mail, or an armed sentinel, and `operator-readout.sh` cites E0 by name as the reason the certificate stays silent — so a research turn that identifies ten items trips no arm and closes clean." |
| Certificate | slim:8 | "on a write turn whose ledger is ✅ … Read-only turns, unverifiable states and a close answering no get none." |
| Origin close contract D6 | slim:22; full:556-566 | "an origin session … closing ✅ or 👤 after written work this session leads with the verdict: line 1 `✅ Good to close: yes — nothing of mine is open; follow-on: <filed ids\|none>` or `❌ Good to close: no — <what remains + who owns it>`, line 2 the ledger's rung glyph (`line-1-rung`)." |
| S1 relay | slim:144 | "Copy the glyph and state clause verbatim and replace the tail with one clause naming what the work was." |
| S1 no-withdraw | slim:146 | "Neither it nor the verdict hedges, and nothing later withdraws either. … A qualification goes in S2's `follow-on:` clause" |
| Done requires | slim:84 | "Done this turn … requires: scope complete … no pending decision." |
| Close question | slim:86 | "A close question … asks about the task, not about what this session wrote. … 'This session changed nothing' is never grounds for ✅ … No findable scope is an unknown, not a ✅." **Not present in full** (`grep -n 'asks about the task\|changed nothing' CLAUDE.global.md` => only full:729, an unrelated sentence). It was added to slim alone by `4fefb87ea` (2026-09-24, "slim variant restores the close contract that T10 failed"). |
| F2 number rule | slim:68 | "At or below 90%, research exhaustively, then implement if you are now above 90%; otherwise hand it to the operator with the number, the research receipt and the measured options … Above 90% there is nothing to ask: implement." |
| Three dispositions | slim:178-189; full:1036-1042 | "Every open item ends as exactly one of these; 'say the word' is not a disposition." DRIVEN = "done this turn … S4 … receipt in S5". FILED = "the exception … Mint a row only if (a) named impossibility (b) still true after p90 ~9 days (c) who it is for". BLOCKED = "a genuine operator-only gate … It is S1's `⛔` rung … At the exhaustion close … itemize only the decisions this session drove to the wall, one line each, answer-first: the decision as a sentence, its conviction number, its measured options." |
| Offering is a defect | slim:191; full:1044-1047 | "Offering researched, in-scope remaining work ('say the word and I'll pick up either') is a defect; the Follow-On Gate already settled it. Drive it or drop it; filing needs a named impossibility class." (full adds the operator ruling 2026-08-01: "the answer will always be yes — the job is not done until the job is done.") |
| Hold rule | slim:103 | "Only ⛔, and 📦 in a repo whose own `CLAUDE.md` says landing spends money, may end a turn holding work." |
| ⛔ filing | slim:160 | "`wrap-ledger.sh` computes `⛔` from this session's open class-C packets … an unfiled decision is invisible to it, and `✅ SAFE TO CLOSE` would render over the open question." |
| Recycle-to-implement precedent | gslim:135-139 | Frontier ladder: "T-b: there is an implementation for the answer to feed" … stage (3) "recycle back with `--model opus` and implement there". This is the only standing rule that already recycles a research result into implementation. Open decision `2c7259995a6b` asks whether it should fire automatically. |

## 3. The contradiction and gaps that made the incident close look compliant

### 3.1 G1: three meanings of "read-only", and D6 used the widest (measured)

- The rules key on **tracked** writes (slim:34, full:601, full:721) and on the **turn** (slim:99 "read-only turn").
- `hooks/lib/session-writes.sh:2` titles the oracle "which tracked files did THIS session write?". Its rc 0 is
  "at least one file-edit tool_use" (`:31`) on any path, with subagent transcripts deliberately included (`:74`).
- The certificate uses `session_wrote_here_this_turn "$TP" "$CWD"` (`operator-readout.sh:1877`), whose own header
  says: "Scratchpad writes are the same class: protocol E0 turns on TRACKED writes, and a /tmp file is not tracked
  work in any tree" (`session-writes.sh:355-365`). That class was found and fixed for the certificate on 2026-08-03.
- D6 still calls the session-wide, any-path `session_writes_paths "$TP"` (`completion-assert.sh:1513`). Its own comment
  says "write-free session → research/Q&A must never be forced into a work-close shape" (`:1486`).
- Measured on the incident (transcript cut at the final close, `head -n 465` with the `subagents/` dir linked
  beside it, `bash /tmp/rpic-D/sw2.sh`):
  `session_writes_paths => rc=0` (it lists `/tmp/xd/g00..g08.md` from the subagents and `/tmp/xd/g99.md`),
  `session_writes_paths_turn => rc=1`, `session_wrote_here_this_turn <wt-cc-192325-42328> => rc=1`.
  So the rules and the certificate both said read-only, and D6 said "wrote real work".
- Effect (measured, T:293 and T:310): D6 blocked twice with "this session wrote real work and the ledger reads ✅,
  but the close is missing [good-to-close-verdict line-1-rung] … run scripts/wrap-ledger.sh --machine, relay
  READOUT's glyph and state clause verbatim". `READOUT` was `✅ Complete & live on trunk — nothing to do.` (T:297,
  T:462). From then on every close carried that line as line 2, even under `❌ Good to close: no` (T:314, :329, :345,
  :368, :379, :391). The operator's quote, "✅ Complete & live on trunk — nothing to do. This was read-only research,
  so no repo changed.", is the T:314-T:391 line 2 (T:560).
- **Prior art on this exact mismatch.** `docs/research/close-verdict-first-2026-10-10/skeptic-operator-intent.md:178-187`,
  P8: "'after written work' reads as this turn; the hook means this session … The rules say read-only turns carry no
  readout (lines 34 and 99)." The fix chosen was to change the rule text to "after written work **this session**"
  (now slim:22), not to narrow the hook. That narrowed the turn mismatch in prose. It did not touch the path mismatch
  (`/tmp` and subagent scratch), which this incident shows.

### 3.2 G2: the BLOCKED disposition promises a ⛔ that the ledger cannot compute here

- In prose, remaining operator decisions are BLOCKED: "it IS S1's rung (`⛔`)" (full:1042, slim:189).
- In code, ⛔ is "open class-C decision packets whose .session_sid == $SID" (`wrap-ledger.sh:1343`). That asks
  "is it MINE?", so a re-check of existing packets cannot reach it.
- Measured now: `python3` over `~/.claude/autonomy/decisions/*.json` => 58 open (57 C, 1 B), and 0 of them carry the
  incident sid. At the close the ledger therefore fell to its default
  `RUNG="✅"; READOUT="✅ Complete & live on trunk — nothing to do."` (`wrap-ledger.sh:2492`).
- The operator pile did render, as a `systemMessage`: "◆ 73 decisions — your call" (T:467). That line is labelled
  standing, not blocking, by design (full:526-533), and a `systemMessage` never reaches the model (full:514-516).
- So the remaining decisions were the BLOCKED disposition by the prose, but the agent was mechanically made to put ✅ at the top.

### 3.3 G3: the S2 yes payload is about ownership and the template has no third answer

- `yes — nothing of mine is open; follow-on: <filed ids|none>` (slim:22; template `hooks/lib/close-shape.sh:179`) is
  true of a session that owns no packets, commits and dirt. The close at T:465 used it word for word, then
  itemized 56 decisions in the body. Line 1 and the body therefore disagree, and slim:146 forbids a later line
  withdrawing the verdict.
- The only verdict tokens are yes and no (close-shape matcher). No token says "research done, the next step is
  implementation, which needs your go / which I am firing now". slim:86 and slim:84 ("no pending decision") would have
  required `no`. They lost to the ownership-scoped template, which a Stop hook pushes at the moment of closing, while
  slim:86 and slim:84 are prose read once at session start.
- The sibling study ranks this "contract supplied the shape" at 80 (`close-behavior-2026-10-18/README.md` §2 R4,
  branch `cc-004752-67086`) and proposes retyping the payload to `nothing drivable remains` (its F2, at 65-70).

### 3.4 G4: E0 tells the agent to act but gives the operator no state, and nothing checks it

- E0 suppresses the readout and orders "drive the passes". Neither E0 nor the disposition row says what the operator
  is shown when the passes are **not** the agent's: decisions at 90% or below (F2 sends them to the operator), or
  passes waiting on a human go. In the incident every recommendation was at 88% or below (T:465 tables: 80, 85, 88,
  85, 70 …). So F2 made them the operator's, and E0's "drive" had no PASS to drive. Its "no readout" then left the
  turn with **no defined status line at all**, and D6 filled that gap with the git rung (G1).
- full:721 says outright "Nothing on this box catches it". The token-efficiency slimming deleted that sentence from slim
  as "history" (`docs/research/token-efficiency-2026-09-23/audit/C4.labels.md:81`). So the resident rule no longer
  says that no arm enforces E0.

### 3.5 G5: the explain-decisions command has no close step

- `commands/explain-decisions.md` (8 lines) says "itemize … recommendation … conviction % … If exhaustive research
  moves your conviction … exhaustively research now." It has no disposition step: nothing writes the re-checked
  conviction back onto the packets, fires the at-or-above-90 items, or names which items wait on a go. The turn
  produced 9 `/tmp/xd/g*.md` files and a table, and wrote no store fact. (Closing the 18 settled packets and firing two
  sessions happened only after the operator asked, T:472-T:593.)

### 3.6 Is the turn's close consistent with the rules? Rule by rule

| Rule | Incident close (T:465) | Verdict |
|---|---|---|
| slim:34 / slim:99 (no readout on a read-only turn) | A readout was printed, because D6 demanded it (G1) | rules contradict the hook |
| slim:22 D6 template | Followed word for word | compliant |
| slim:86 close question (session changed nothing ≠ ✅) | "✅ Good to close: yes", body says "This was read-only research, so no repo changed" | violated. D6 asks a close question the operator did not type, so it is unclear whether slim:86 governs a hook-demanded verdict (the sibling's F5 targets exactly this) |
| slim:84 "no pending decision" | 56 pending | violated |
| slim:189 BLOCKED exhaustion close | Body itemized answer-first with conviction, which fits the shape; the rung was ✅, not ⛔ | half: shape yes, rung impossible (G2) |
| slim:191 Offering | The body ends without an offer | compliant |
| slim:68 F2 | All items at 88% or below, so the operator's | compliant, and that is why E0's "drive" had nothing to drive |

## 4. Prior art: every hit

`C` = constrains the design. `I` = informs it only. `—` = not relevant (counted for the denominator).

### 4.1 Docs and git history

| # | Path / sha | Gist | C? |
|---|---|---|---|
| 1 | `docs/research/close-behavior-2026-10-18/` (branch `cc-004752-67086`, tip `84d63e3af` 2026-10-18 21:29 -0500; `git merge-base --is-ancestor 989bbc271 origin/main` => NOT-ON-MAIN) | Same-day sibling study of a ✅ yes over undriven researched work. R1 "no input represents researched, drivable, undriven" at 90-97. 30 fixes F1-F30, none at 90 or above. Round-2 C1-C6 in progress, including **C6 "a machine-readable disposition marker on research recommendations"** and C3 follow-on store-discharge (efficacy judge: 30). | **C**: same problem class. Coordinate, don't fork. Its §6 rejected list binds (see §5). |
| 2 | `…/close-behavior-2026-10-18/README.md` §5.4 F23-F25, F27 | F23: research synthesis emits `docs/plans/<slug>.md status: open` (70). F24: an "enact floor" in session-continue (55). F25: an Enact step in the research recipe (45; but 9-13% of syntheses load the research skill, per C6 §1). F27: context-preserving self-goal (unscored). | **C**: candidate mechanisms already scored for research→implementation |
| 3 | `…/round2/C6-doc-disposition-marker.md` §1 | 54 sessions wrote a research synthesis in 14 days; 5-7 loaded the research skill; 33 of 54 (61%) used Workflow with lead-written synthesis prompts | **C**: an opt-in skill/template fix misses most research turns |
| 4 | `docs/research/exhaustive-drive-2026-09-08/A08-rule-surface-audit.md:40-50` (C1) | "`E0 answer and yield` is the licence step 1 exists to revoke … A read-only turn that names ten drivable items is invisible to every arm on the box." The E0 row was rewritten from it (in full by `367e42f26` 2026-09-10 lineage). | **C**: origin of E0. It fixed the *drive* half only, never the *report* half. |
| 5 | `…/exhaustive-drive-2026-09-08/SYNTHESIS.md:113-150` (2C, 2D) | Rejected: A02 R1 store-or-silence terminal gate (25; nags live conversations about 1:1); A02 R2 bind line-1-rung on silent origin closes (35; same about 1:1 nag). Non-actions: no NAME_TELL widening (85), no lexical decision arm (85), no prose detector for the unfiled close (90), no agent-type Stop hook (78-80). | **C**: a new status must not be a prose detector or a block-until-store gate |
| 6 | `git show b94ecb90e:docs/research/exhaustive-drive-2026-09-08/A06-research-then-dispatch.md` (removed from tree by `9bd5873c4`) | "What is missing is not research — it is the **edge from a researched row back to a dispatchable one**." No verb fires research from a row. The research recipe writes nothing back to any row. | **C**: same gap, stated 2026-09-08 for backlog rows |
| 7 | `docs/research/close-verdict-first-2026-10-10/skeptic-operator-intent.md:178-187` (P8) | D6 is session-scoped while the rules say a read-only turn has no readout. The fix taken was text only ("after written work this session") | **C**: a prior decision to keep D6 session-scoped. Any change to D6's oracle must reverse it explicitly. |
| 8 | `docs/research/close-verdict-first-2026-10-10/design.md:81` (cited by #1) | "The yes path is not tightened at all" | I |
| 9 | `docs/research/conviction-close-2026-09-08.md:12-26` | `Good to close: yes — nothing of mine is open; follow-on: ae75073ef319 (… your policy call)` drew "is it net-positive? if so, why is this not proactively done and instead idling" | **C**: second instance of the same template producing a false-done |
| 10 | `docs/research/method-exhaust-then-proceed-2026-10-16/REPORT.md` "The ruling" | Operator verbatim 2026-10-16: "not to research and then park and idle spinning our wheels; we have to research exhaustively until we cant no more and then instead of stopping we need to proceed" | **C**: operator ruling. Research must proceed into implementation by default. |
| 11 | `1d8feb56c` 2026-10-05 "feat(research-sign): the implementation signature — operator-only, pinned to the built certificate" | Inside registered research programs there is already a research→sign→implement state machine (`research:<slug>/implementation`, `handoff-fire --gate-after-signoff`) | **C**: a precedent and a mechanism to reuse or avoid duplicating. It covers registered programs only (`programs.json` holds `truememory-2-0` only, per #1 §4). |
| 12 | `scripts/wrap-ledger.sh:1049-1064, 2496-2498` (`compute_research`) | A research-program verdict is a **report the ladder never reads**, printed beside the rung, in `--machine`/`--full` only | **C**: precedent for a non-rung status line in the ledger |
| 13 | `gslim:135-139` frontier ladder | Recycles a research document into an implementing session (`handoff-fire.sh --recycle … --prompt-file`) | I: the recycle precedent the operator asked for |
| 14 | `4fefb87ea` 2026-09-24 | Added slim:86 (close question asks about the task) because slim failed T08/T10 false "safe to close" in eval; 5/5 restored. Never ported to full. | I: the rule exists and was measured effective offline, yet lost here to the hook-pushed template |
| 15 | `docs/research/token-efficiency-2026-09-23/audit/C4.labels.md:80-81` | Kept E0 in slim and deleted "Nothing on this box catches it" as history | I |
| 16 | `docs/research/exhaustive-drive-2026-09-08/A02-close-taxonomy.md:81,95` | F5 "silent on a read-only turn (E0)" is 673 closes (32.9%), legitimately no readout; C5 "E0 read-only turn ending with named work" was folded into C3/C4 and not counted separately | **C**: about a third of closes are read-only, so a new status that fires on every read-only turn would flood (alarm polarity) |
| 17 | `git log --all -S 'read-only research'` | 40+ hits, all checkpoint commits or unrelated research (startup-hooks, prompt-audit, research-calibration, launch-film) | — |
| 18 | `git log --all --diff-filter=A --name-only \| grep -i -E 'research\|readonly\|read-only\|e0'`, filtered to close/drive/E0 names | Added files: `docs/lessons/a-read-only-surface-must-not-be-able-to-hold-state.md`, `a-research-probe-that-drives-real-ui-writes…` (unrelated: probe safety); the close-* and exhaustive-drive sets above | — beyond those listed |
| 19 | `grep -rl` over `docs/research docs/plans docs/lessons` for "implementation pending / research complete … implement / research-only / enact" | 0 hits for a pending-implementation state | — (absence) |

### 4.2 Backlog and decision stores

- `cc-backlog list --json` => 192 rows. Regex over every row for read-only, research-only, E0, research complete,
  implementation pending, good to close, nothing of mine, follow-on, close status, undriven => 6 hits, all false
  matches on "read-only" in unrelated rows (`9ecddab54254`, `35cae65a8d2d`, `820e8fb74044`, `8cd519503918`,
  `88e47aaff3eb`, `b0812ecccb52`). **No backlog row proposes a research-pending-implementation state.**
- `cc-decide list --open` => 60 lines. No open packet asks about close status for research turns. Related: `2c7259995a6b`
  (should the sub-90% frontier ladder fire automatically). A full-text grep over every packet for
  `read-only (turn|research)|research.{0,40}implementation|good to close` gave 9 packets (`103f40b25f01`, `4ce9ba5e709b`,
  `377d59cb7668`, `d6050f1765a2`, `e226c8fedc6c`, `b914a9fbc103`, `bcef8d8c892a`, `c2694bf242ab`, `ccae4d860e63`). All are
  route-around packets that store a close text as `what_plain`, and none is a ruling. `103f40b25f01` (2026-10-11) holds
  the same `✅ Good to close: yes — nothing of mine is open; follow-on: none / ✅ Complete & live on trunk — nothing to do`
  pair, which shows the shape recurring. **No operator ruling on this question exists in the packet store.**

### 4.3 Memory store (`cc-memory-search`, bm25 over 1,080 project docs)

| Query | Hit | Gist | C? |
|---|---|---|---|
| research pending implementation | `…/-Users-chrisren-Development-doc-classifier/memory/feedback-zero-hitl-implementation.md` | Operator standing law 2026-07-14: multi-day implementation runs end-to-end autonomous, no program fence | **C**: favours auto-proceed |
| same | `…/reso-management-app/memory/feedback-exhaustive-research-before-implementation.md` | In reso payments, exhaustive research (weeks) before any production implementation | **C**: some domains require the checkpoint (money) |
| same | `…/reso-management-app/memory/full-scale-implementation-methodology.md` | 5-phase pipeline research → persistence → implementation | I |
| same | `…/claude-infrastructure/memory/desk-autonomy-dormancy-staged-not-loaded.md` | Auto-drive spine built but inert because activation is C10 | I: an enact path that needs C10 activation stays dormant |
| same | `…/sevenrooms-bridge/memory/recovery-owner-must-notify-the-session-it-took-over.md` | — | — |
| read-only close | `…/reso-management-app/memory/feedback-a-review-programme-is-not-closed-by-a-green-ledger.md` | "good to close" is NO until every item is signed off, whatever the ledger says; answer against the programme's tracker | **C**: same failure in a review programme, 2026-09-27 |
| same | `.claude/rules/agent-operating-lessons-situational.md:222,226`; `closed-vocabulary-field-swallows-an-unrecognized-value.md`; `iterm2-teammate-no-prompt.md` | Unrelated close/teammate items | — |
| E0 | none | `cc-memory-search E0 => No match (1080 documents, scope=project)` | — |
| signoff human checkpoint (added) | `…/claude-infrastructure/memory/feedback-operator-will-not-read-signoffs.md` | Operator 2026-10-16: "I WILL NOT look at any of the contenet for said sign off … zero human in loop". Replaced by a one-time `cc-signoff 'research:*/delegate'` | **C, the strongest**: contradicts a content-reading checkpoint. The incident session itself flagged this tension (T:623). |
| same | `…/claude-infrastructure/memory/feedback-autonomous-to-100-boundary.md` | Routine decisions drive silently; only money, auth or destructive work is a legitimate GO checkpoint | **C**: matches the operator's "reversible, non-breaking, lower-stakes → just do it" |
| same | `…/reso-landing-design-research/memory/feedback-visual-signoff-not-markdown.md` | Sign-offs must be a one-page visual, never a long markdown | **C**: the checkpoint's form |
| research then park (added) | `…/claude-infrastructure/memory/remedy-gate-must-cover-the-occasion.md` | A remedy gated on turn type never fires on the turn the problem happens (the certificate fires only on ✅ write turns) | **C**: the new status must fire on research turns, which every current arm excludes by design |
| same | `goal-idle-has-two-failure-poles.md`, `landedness-oracle-is-blind-to-intent.md` | I | I |

## 5. Constraints on the design that the prior art sets

1. **Do not add a prose detector or a lexicon arm** for "research done, implementation undriven" (exhaustive-drive 2D at 85-90;
   close-behavior §6 at 88). Key the status on a **store fact** or a **write-time field**, not on close wording.
2. **Do not add a block-until-store-write terminal gate**: about 1:1 nag on live conversations (A02 R1, 25; A02 R2, 35).
3. **Do not put a new arm in completion-assert's shared `assert` cap class**: it starves (close-behavior R3, §6).
4. **Keep the research-program exemption**, `programs.json`-keyed (slim:74-80; ruling `83adb541ea19`). Reuse or stay
   clear of the program kit's existing implementation-signature state machine (`1d8feb56c`) rather than build a second one.
5. **The checkpoint must not ask the operator to read content** (memory `feedback-operator-will-not-read-signoffs`). A
   one-line, answer-first yes/no on a named implementation, or a one-time standing delegation, fits. Routine,
   reversible work proceeds with no checkpoint (memory `feedback-autonomous-to-100-boundary`, ruling 2026-10-16 #10).
   Money, auth and destructive work keeps a GO.
6. **Alarm polarity.** About 33% of closes are legitimately silent read-only turns (A02 F5: 673 at 32.9%, measured by A02; the base of about 2,045 is estimated as 673 / 0.329). A status
   that renders on every read-only turn carries no information. It must fire only when the turn produced
   implementation-bearing findings.
7. **D6's session scope was chosen deliberately** (verdict-first P8). Narrowing D6 to tracked writes in the turn's tree
   (the certificate's oracle) is a reversal and must say so. The alternative is to keep D6 and give it a third
   verdict form.
8. **⛔ ownership** (`wrap-ledger.sh:1343`, "is it MINE?") was chosen so that one session's pile does not convict another.
   A "decisions this session re-checked" term needs its own attribution (for example, packets this session updated),
   not a widened ⛔.
9. **Rule-text budget**: the user tier measures 60,998 against 60,000 (close-behavior §5, measured by its authors), so any
   added rule text must be paid for by a cut in the same commit.

## 6. Method and denominators

- Rule text: a full read of slim (226 lines) and full § Session Close Protocol (full:501-1060), plus a grep of gslim.
- Transcript: every record of T scanned (`python3 -I /tmp/rpic-D/tx.py`, `tx2.py`; 671 lines). Write tool_uses in the main
  transcript: 1 (`/tmp/xd/g99.md`, T:230). The session-scope oracle adds 9 subagent writes.
- Git: `git log --all` with `-S` on three phrases, plus `--diff-filter=A` names. Docs: `grep -rl`/`-rn` over `docs/research`,
  `docs/plans`, `docs/lessons`, `commands`, `skills`.
- Measured vs inferred: §3.1 oracle rcs, §3.2 packet counts, and the T:N quotes are measured. That slim:86 "lost to the
  template because the hook pushes it at close time" (§3.3) is an inference from timing (T:293/T:310 blocks precede
  every later close), not a controlled test.
