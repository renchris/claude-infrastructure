# Slot B: completion-assert and close-shape on the 2026-10-18 "nothing of mine is open" close

Scope: `hooks/completion-assert.sh` (1733 lines), `hooks/lib/close-shape.sh` (311), and `hooks/anti-deference-nudge.sh` (641) for the deference question. Every line number is from the worktree at `36afca47f`.

## 0. Answer first

1. **Nothing forced a "yes", but the yes sentence was written by the hooks.** The agent could have answered "no". D6 accepts either polarity (`close-shape.sh:10-12`, `:105`). Two pieces of the incident close were still copied word for word from hook output:
   - **Line 1.** D6 blocked the session twice, at 02:32:26Z and 02:32:43Z. Each time its block reason carried the template `close-shape.sh:179`: `Good to close: <yes — nothing of mine is open; follow-on: <…|none> | no — …>`. Line 1 of the close is that template's yes branch, filled with `none`.
   - **Line 2.** It is wrap-ledger's ✅ READOUT, `scripts/wrap-ledger.sh:2492` `"✅ Complete & live on trunk — nothing to do."`. The agent pulled it twice (tool_use at 02:32:29Z and 02:36:53Z; both tool_results returned `READOUT=✅ Complete & live on trunk — nothing to do.`) because D6's `line-1-rung` demand says "relay READOUT's glyph and state clause verbatim" (`close-shape.sh:309`).
   - So the template offers a pre-written yes sentence, and the ledger's READOUT puts "nothing to do" into the close for any ✅ rung.
2. **No arm checks "nothing of mine is open / follow-on: none" against what the session produced.**
   - "Mine" means filed by this session's sid, in every store that is consulted:
     - ⛔ / BLOCKED: `wrap-ledger.sh:1343` (`.session_sid == $SID`)
     - FILED_MINE: `completion-assert.sh:1115`
     - UNCONVICTED_MINE: `:1126`
     - D1 backlog `.session == $s`: `:1313`
   - Measured: the close cites 17 unique 12-hex decision ids. All 17 were open at 02:37:19Z: 13 are still `open` now, and the other 4 were `resolved` 02:53:53Z–02:55:50Z, after the close. 0 of 17 carry `session_sid == 74728043…`; they were filed by 9 other sessions.
   - So every arm is blind by construction, and both live hooks waved the close through. IDL rows for this sid: `completion-assert abstained ledger-clean` at 02:37:24Z, `anti-deference-nudge abstained no-tell` at 02:37:19Z.
3. **A new arm "research produced actionable results but the close says nothing to do" fits as D8.**
   - **Position:** after D7 (`:1609-1614`) and before the ledger-clean abstain (`:1619-1621`).
   - **Class:** its own cap class. It must not use D6's `shape` class (this session had spent `shape` 2/2 by 02:32:43Z), and it must not use D6's write-evidence gate.
   - **Predicate:** a done-reading close (verdict polarity `yes`, or a line 1 that reads as done) that cites at least one OPEN cc-decide packet on a line that also carries a recommendation or conviction. §4 has the full predicate and its abstain paths.
4. **A correct "research done, implementation pending your sign-off" close passes D3, D4, D1 and anti-deference.**
   - Shape: a ❌ "no" verdict on line 1, stated rather than asked, decisions named after a colon, and an `ACT:` line.
   - Measured in the sandbox: case c1 and case c12 pass both hooks.
   - Six natural spellings of the same message do get flagged; see §5.

## 1. Incident evidence

- Transcript (686 records when copied): `~/.claude-quaternary/projects/-Users-chrisren-Development--worktrees-wt-cc-192325-42328/74728043-bcb8-4e66-8cdb-62189f61c848.jsonl`. The close is line 465, an assistant record at 2026-10-19T02:37:19.374Z, 34 lines long. It is extracted to `/tmp/rpic-B-assert/close.txt`.
- Line 1 is `✅ Good to close: yes — nothing of mine is open; follow-on: none`.
- Line 2 starts with `✅ Complete & live on trunk — nothing to do.`
- The body has tables of 56 live decisions, each with a recommendation and a conviction (for example `| … (\`8daf14ec04b2\`) | Refuse; text the promoter today | 80% |`). It also includes "OK the quick fix now (branch dossier-swap)". Measured: `grep` finds 14 lines with an id plus `%`/recommend/conviction, and 20 lines with `%`/recommend/conviction.
- The report lives at `/tmp/xd/REPORT.md`, which a reboot wipes.
- Stop-hook record at 02:37:24.801Z: `hookErrors: []`. The `hook_cancelled` record says completion-assert had `durationMs 5337, timedOut true, timeoutMs 5000`. Its IDL row (`abstained ledger-clean`) was still written, so the verdict was abstain. Any block it had printed at that point would have been lost (inferred from the cancel).
- operator-readout's systemMessage on that same Stop: `OPERATOR ▸ 3 runnable now, 253 need your call · ✅ live on trunk … ◆ 73 decisions — your call`. So the operator surface itself said "73 decisions — your call" while the close said nothing was open. That is a cross-surface contradiction, and nothing compares the two.
- Session write footprint, measured: the main chain has 1 Write (`/tmp/xd/g99.md`, 02:21:25Z). The 9 subagents wrote 48 times to `/tmp/xd/g00..g08.md`. Every path is scratch under `/tmp/xd/`, and no tracked repo was touched.
- D6 fired twice on this session (IDL `fired false-done arm=shape class=shape count=1/2` at 02:32:26Z and `count=2/2` at 02:32:43Z). Its reason text both times was "this session wrote real work", and both carried the `:179` template. Those two block-feedback user records are transcript lines 293 and 310.

## 2. Arm map and incident replay

Replay method: `/tmp/rpic-B-assert/replay.sh`.
- Hermetic environment copied from `tests/completion-assert.bats:13-89`: state, IDL, fired, custody, registry, research-registry, cc-backlog and cc-decide stubs, `AGENT_IDENTITY_LIB` missing, and `CC_JEV_RETIRED=1` with `ANTIDEF_DECIDE_BIN` stubbed so no packet can open.
- The real `scripts/wrap-ledger.sh` runs over a throwaway landed repo. It returned `RUNG=✅ DIRTY=0 UNLANDED=0 REMAINDER=0 YOURS=0 BLOCKED=0`. The live incident ledger was also ✅, per D6's reason "ledger reads ✅".
- Transcript fed to the hooks = the incident's first 464 records + one assistant record carrying the candidate text. The sid is fake, so no live latch or route record is touched.
- Output: `/tmp/rpic-B-assert/replay.out` and `replay2.out`.
- The c0 replay matches the live verdict exactly: `completion-assert abstained ledger-clean`.

| Arm | Where | Predicate (abridged) | Incident close |
|---|---|---|---|
| Outbound source read | `:217-262` | fixed-string grep for outbound-drafting / ms365 draft tools | inert (no match) |
| Operator kill-switch | `:279-341` (`CA_KILL_RE` :279) | last human prompt matches "and stop", "just do X", … | not matched. The last non-meta user record is a peer `Another Claude session sent a message: <agent-message …>`. The envelope filter at `:322` does not list `<agent-message`, so a peer's "and stop" would disarm this hook (side finding). |
| **R** research relay | `:381-425` | only when a route-state record exists for the sid; then `router.py relay-check` | **inert**: `~/.claude/autonomy/research/route-state/74728043-….json` does not exist (200 route-state files present), so the `_ca_no_route` fast exit is taken |
| Close-tell gate | `:428` `CLOSE`, `:467-470` | the message must contain a CLOSE token, or line 1 must be settled | **passes**: ✅, `complete`, `nothing … to do`, `remaining` all match |
| GENUINE | `:473-474` | `need (your\|the)[^.]{0,40}(…\|approval)`, `which (do you\|…)`, … | not matched |
| Ledger terms | `:1022-1208` | dirty / unlanded / REMAINDER / CUSTODY_OPEN / FILED_MINE / UNCONVICTED_MINE / CLOSE_FLOOR / 🚀 / ⛔ | all 0. ⛔ counts only packets with this session's sid (`wrap-ledger.sh:1343`), and 0 of 17 have it |
| D2 bare command | `:1275-1299` | column-0 operator verb without code styling | 0 (table rows start with `\|`) |
| D1 handoff prose | `:540`, `:1304-1316` | `CA_HANDOFF` on the quote-stripped text, then backlog `.session==SID` | 0. No CA_HANDOFF spelling is present, so `CA_D1_WANT=0` |
| **D3** hedge | `:433-446`, `:1332-1343` | verdict line: `CA_SETTLED ∧ CA_RETRACT` on the text **before** the anchor, or `CA_YES_HEDGE` | **0**. The pre-anchor text is `✅ `, which has no CA_RETRACT word. `yes — nothing` is not a hedge word |
| **D4** offer | `:1353-1361` | `CA_OFFER` ∧ `CA_WORKLEFT` on the non-offer lines | **0**. There is no offer phrase, and `remaining` alone cannot fire it |
| Active-research-program exemption | `:1377-1416` | D4 only. Exempts when the cwd or the last prompt resolves to an ACTIVE registry program | **moot**: d4=0. The registry has one program (`truememory-2-0`, certified) and it does not cover this cwd |
| D5 placeholder | `:1443-1475` | a `<x>` inside a run-marked line | 0 |
| **D6** origin close contract | `:1477-1571` (abstain policy `:1484-1490`, write gate `:1504-1513`) | `contra=0 ∧ RUNG∈{✅,👤} ∧ ¬assignee ∧ session_writes_paths rc0 ∧ origin`; missing = `close_shape_missing` ∪ `line-1-rung` ∪ `verdict-first` | **gate open** (rc 0 from the scratch writes; origin, since it fired live). Missing = ∅: the verdict anchor is present with value `yes — …` (`close-shape.sh:88-106`), line 1 contains ✅, and `close_verdict_not_first` is false because polarity is `yes`. Result **0**. In the sandbox the write-free variant (c0-wf, Write tool_use stripped) gives the same `ledger-clean` |
| **verdict-first** | `close-shape.sh:149-161` | polarity = no ∧ line 1 reads done | 0 (polarity yes) |
| **line-1-rung** | `:1549-1557` | lines 1–2 must contain the `$RUNG` glyph | satisfied (✅ on both lines) |
| D7 act line | `:1609-1614` | RUNG=👤 only | not in scope (✅) |
| **Write-free abstain** (~1486) | `:1486-1488` policy, `:1513` code | `session_writes_paths` rc 1/2 ⇒ `_d6_ok=0` | **did not apply**. `_sw_paths` (`hooks/lib/session-writes.sh:216-293`) counts ANY Write/Edit path, `/tmp` scratch and subagent files included (`:236-239`). So a read-only research session that writes scratch notes is "wrote real work" to D6 |
| **Ledger-clean abstain** (~1621) | `:1619-1621` | none of contra, d1..d7 set | **taken**. Live IDL `ledger-clean`, no `:exonerated:` / `:research-program-exempt:` suffix; the sandbox reproduces it |
| Caps | `:1681-1708` | per class: assert 3, shape 2, verdict 2, act 2 | at the incident, `shape` was spent 2/2 and `assert` 0/3 (IDL) |

Anti-deference on the same text, sandbox replay: `abstained done-ledger-clean`.
- `DONE_TELLS` (`anti-deference-nudge.sh:171`) matches "nothing to do", and its false-done arm needs `dirty ∨ unlanded ∨ remainder` (`:519`), all 0.
- **The live row said `no-tell`, not `done-ledger-clean`.** I replayed anti-deference on each text alone (`/tmp/rpic-B-assert/adstale.sh`). On the 4 stops where the current and previous text give different verdicts, the live IDL verdict matched the **previous** assistant text in 4/4. completion-assert matched the current text in the same stops.

  | Stop | Live verdict | Current text gives | Previous text gives |
  |---|---|---|---|
  | 02:34:45 | done-ledger-clean | no-tell | done-ledger-clean |
  | 02:37:19 | no-tell | done-ledger-clean | no-tell |
  | 02:46:12 | done-ledger-clean | no-tell | done-ledger-clean |
  | 03:32:13 | no-tell | genuine-blocker | no-tell |
- Inferred: anti-deference reads the transcript before the final text record is flushed. Either way it reads stale text, so a check added to anti-deference would be blind on exactly this close.

## 3. Does the origin contract force the "yes" line?

- **Forced:** that a verdict line exists, when the D6 gate is open. The verdict can be either polarity: "an honest NO satisfies the contract" (`close-shape.sh:12`), and `close_shape_missing` only checks that the anchor's value is not a `<placeholder>` (`:88-94`).
- **Not forced:** a yes. In this session D6 is not even live on a truly read-only turn: its write gate (`:1513`) closes when no Write/Edit is recorded.
- **What the hooks do push:**
  - The yes branch of the only template the agent was shown is a finished sentence, `yes — nothing of mine is open; follow-on: <…|none>` (`close-shape.sh:179`). `commands/are-we-done.md:40` prints the same string as the default first line of its shape.
  - The no branch, `no — <what remains + who owns it>`, gives no wording for a pending result at all.
  - The ✅ READOUT `wrap-ledger.sh:2492` hard-codes "nothing to do", and D6's `line-1-rung` demand tells the agent to relay it verbatim (`close-shape.sh:309`).
  - So once the ledger reads ✅, the hooks themselves supply the "nothing to do" wording. Measured in this session: the agent first answered `❌ … no` while agents were running, then switched to the template's yes branch word for word once they returned.
- "mine" in the template has no definition anywhere a hook can check. The `follow-on:` value is free text. `real()` only checks that it is not `<…>`.

## 4. Proposed arm D8: research output pending, but the close reads done

**Position:** insert after D7 (`:1614`), before the abstain disjunction (`:1619`); add `d8` to that disjunction, to the `arm` list (`pending`) and to CLASS selection. Reasons:
- It needs `contra_shape` (`:1242`) and `RUNG`.
- It must run after the close-tell gate (`:467`) and after GENUINE (`:474`): a close that names an operator-only gate is already honest.
- It must be its own class, `pending`, with `COMPLETION_PENDING_MAX` default 2, claimed when it fires alone, the way D7 claims `act` (`:1686-1688`). If it shared `shape` it would have been capped in this very session (2/2 at 02:32:43Z, measured).
- It must NOT sit inside D6's write gate. The target turn is write-free, or writes only scratch.

**Predicate:**
```
d8 := CC_RESEARCH_PENDING≠0 ∧ contra_shape=0 ∧ RUNG∈{✅,👤} ∧ ¬_ca_assignee ∧ origin(oi_origin_class)
      ∧ DONE_READ ∧ CITED_OPEN ≥ 1
DONE_READ  := close_verdict_polarity(MSG)=yes
              ∨ (polarity=none ∧ close_line_reads_done(ca_first))
              ∨ (polarity∉{no,mixed} ∧ MSG ~ 'nothing (of mine )?(is )?(left |still )?open|follow.?on:?[[:space:]]*none')
CITED_OPEN := |{ id ∈ 12-hex tokens of MSG (NOT MSG_UNQ — the incident cites ids inside backticks,
                 and :514 strips backtick spans as "mention") : id is OPEN in cc-decide
                 ∧ id's line also matches '[0-9]{2,3} ?%|recommend|conviction' }|
```
- Incident inputs, measured: polarity `yes`, line 1 reads done, 17 ids, 17 open at close time, 14 id lines carrying `%`/recommend. So **d8=1**.
- The c11 control (`yes — research done; follow-on: 56 decisions await your sign-off`) passes every existing arm today (`ledger-clean` / `done-ledger-clean`, measured) and would fire D8. That is intended: a "yes" over pending sign-offs is the same defect.
- Fail-safe controls: the honest closes c1, c7 and c12 have polarity `no`, so they abstain.

**The open-packet oracle.** `cc-decide list --open --json` measured `real 0.92` s, 60 open. Choice:
- (a) Prefetch it beside the ledger as D1's read is prefetched (`:625-630`), with a 2 s bound. Or
- (b) Have wrap-ledger export the open-id set (it already reads the store at `:1500`).
- (b) keeps `:1191-1197`'s rule that this hook never reads the cc-decide store itself (make-the-actuator-the-arbiter). (a) is simpler.
- Either way, timing matters. completion-assert already ran 5337 ms against a 5000 ms timeout on the incident Stop, and a cancelled hook's block is discarded (inferred). An un-prefetched serial read could turn a fire into a silent cancel.

**Abstain paths, each logged with its own reason:**
1. `CC_RESEARCH_PENDING=0`. Operator kill-switch (`:327-341`, already above).
2. `contra_shape=1`: the ledger arm already blocks with a drivable action (the D6/D7 rule).
3. Polarity `no` or `mixed`: the close already says it is not done. This is the compliant path, and it must stay silent (c1/c7/c12).
4. GENUINE matched (`:474`, earlier): an operator-only gate is named. Note this also exits on "need your approval" (c10, measured `genuine-blocker`).
5. Confirmed assignee, or a fired peer whose close is the notify-back. The originator's close carries it.
6. An active research program (`_ca_rp_active` / `_ca_rp_prompt_active`, `:1397-1410`). Arm R and the certificate govern relays, and a program's named residuals are filed, not open (ruling 83adb541ea19).
7. Store unreadable, timeout or unparseable ⇒ cannot tell ⇒ no fire (D1's fail-open, `:1311-1314`).
8. Cited ids all non-open (actioned/vetoed this turn), or ids with no recommendation on their line (a passing mention, not output).
9. Relay turn (ARM R rc 3) and latch/cap, as for every arm.

**Reason text, sketch:**
- "Your close reads done ('nothing of mine is open', 'nothing to do'), but it recommends action on N OPEN operator decisions (ids, each expanded). Research complete is not nothing to do."
- "Line 1: `❌ Good to close: no — research done; N decisions await your sign-off; M implementations ready`."
- "If a change is reversible, non-breaking and low-stakes, implement it now instead. Otherwise write an `ACT:` line naming the sign-off; on approval, recycle into implementation (`scripts/handoff-fire.sh --recycle`)."
- "Make the result durable: write each new recommendation into its packet, not only `/tmp`."
- It must not restate D3/D4 correctives (`:1717` ordering rule).

**Optional second term (unmeasured):** a branch named in the close ("branch dossier-swap") that exists with unlanded commits counts as an implementation that is ready. Branches are cross-repo, so this needs a repo resolver. I did not build it.

## 5. Would a correct "research done, implementation pending your sign-off" close trip D4 or anti-deference?

Regexes, quoted:
- `CA_OFFER` (`:1353`): `say the word|if you want (me|a|another)|want me to|shall i|let me know if you.?d? ?(like|want)|happy to (pick|take|go|proceed|do|continue)|i can pick (it|these|either) up|clean stopping point|otherwise (this|that) is a|for a next (thread|session)|if you.?d? ?like me to|ready when you are`
- `CA_WORKLEFT` (`:1354`): `^[[:space:]]*([-*+•]|[0-9]+[.)])[[:space:]]+|remaining|parked|stranded|still open|not done|left to do|next thread|older frozen dod|unlanded|outstanding`
- `CA_SETTLED` (`:433`): `✅|safe to close|good to close|^[^A-Za-z]*yes([^a-z]|$)|complete|all done|nothing (left|more) to do`
- `CA_RETRACT` (`:434`): `parked|unlanded|still (needs|to|open|parked)|remains?([^a-z]|$)|except|(^|[^a-z])but([^a-z]|$)|aside from|one thing|with one|yours|pending|caveat`
- `CA_YES_HEDGE` (`:446`): `good[[:space:]]+to[[:space:]]+close[^a-z]*yes[^a-z]+(but|except|aside from|apart from|other than|once|until|pending|provided|as long as|if|with one thing)([^a-z]|$)`
- `CA_HANDOFF` (`:540`): `remains? yours|are yours|is yours|on your (end|side)|you.?ll need to|you will need to|requires your|needs your|still needs (a|the|your|to be)|left (to|for) you|for you to (run|do)|keep an eye on|worth (watching|keeping)|i.?d recommend you|up to you|your call to|manual step`
- `GENUINE` (`:473`): includes `need (your|the)[^.]{0,40}(credential|password|secret|token|key|access|permission|approval)`
- anti-deference `TELLS` (`:168`): `say the word|say go…|give me the word|on your word|want me to|shall i|should i (proceed|do|go)…|let me know if you|holding for your|otherwise (i.?ll|i will|i.?d) (hold|wait|…)|your steer|do you want me to|awaiting your|…`
- anti-deference `CATEGORY_TELLS` (`:184`): `(^|[^a-z])(one|two|three|four|a few|some|several|[0-9]{1,3}) (item|thing|step|task|decision)s?[^.!?:—–-]{0,30}((is|are) yours|needs? your (call|attention|decision|input|sign.?off)|(is|are) for you|remains? yours)[^.!?:—–-]{0,20}([.!?]|$)`

Sandbox results (`replay.out`, `replay2.out`; RUNG ✅, writes present):

| Case | Line-1 / key phrase | completion-assert | anti-deference |
|---|---|---|---|
| c1 | `❌ Good to close: no — research done; 56 decisions … wait on your sign-off …` + `ACT: approve or veto …; on approval this session recycles …` | abstain ledger-clean | abstain no-tell |
| c12 | `❌ … no — research done, implementation pending: 4 urgent decisions need your sign-off: refuse …, OK …` + `ACT:` | abstain ledger-clean | abstain no-tell |
| c7 | `❌ … no — 56 decisions wait on your sign-off` + READOUT line with "nothing to do" | abstain ledger-clean | abstain done-ledger-clean |
| c2 | `✅ Research complete — implementation pending your sign-off` (no verdict anchor) | **fired hedge+shape** (D3: CA_SETTLED ✅/complete ∧ CA_RETRACT pending; D6: no verdict) | no-tell |
| c3 | `Say the word and I'll implement …` + `- the remaining 23 …` | **fired offer** (D4) | **fired deference** |
| c4 | `Want me to implement the 3 ready fixes?` | abstain (no CA_WORKLEFT token left once the offer line is removed) | **fired deference** |
| c5 | `… implementation is awaiting your sign-off` | abstain | **fired deference** (`awaiting your`) |
| c6 | `… requires your sign-off` | **fired handoff** (D1: `requires your`, backlog stub `[]`) | no-tell |
| c8 | `4 decisions need your sign-off.` | abstain | **fired category-not-idea** |
| c9 | `✅ Good to close: yes, once you sign off …` | **fired hedge** (CA_YES_HEDGE `once`) | no-tell |
| c10 | `… the 3 ready fixes need your approval` | abstain **genuine-blocker** (skips every arm) | no-tell |
| c11 | `✅ Good to close: yes — research done; follow-on: 56 decisions await your sign-off` | abstain ledger-clean | done-ledger-clean (**gap D8 closes**) |

Compliant shape (c1/c12), which a D8 reason should prescribe and a bats test should pin against D1/D3/D4/anti-deference:
- (1) A ❌ **no** verdict on line 1. Never a ✅/"complete" line 1 carrying "pending" (D3), and never a conditional yes (D3 hedge).
- (2) State it, don't ask it. None of the CA_OFFER or TELLS spellings ("say the word", "want me to", "awaiting your", "let me know if you", "if you'd like me to").
- (3) Name the decisions after a colon, so CATEGORY_TELLS' `[^.!?:—–-]` window breaks.
- (4) Avoid CA_HANDOFF spellings ("requires your", "needs your", "up to you") unless the step is filed via `cc-backlog needs` under this session (D1 then sees the row, `:1313`).
- (5) Put the sign-off on an `ACT:` line (`close-shape.sh:238`), saying what happens on approval: the recycle.

The lexical trap is real: "wait on your sign-off" passes, "awaiting your sign-off" fires anti-deference, and "need your approval" exits completion-assert entirely through GENUINE.

The policy conflict in D4 is also real: its premise is "the answer will always be yes" (`:1345-1350`, `:1724`), while the operator now wants a human checkpoint for research→implementation when the stakes are not low. D4 does not fire on a statement plus an `ACT:` line, so the two can coexist. The cleanest resolution is to make the checkpoint a store fact (a needs-human row or the packets themselves, filed by this session). The rung then reads 👤 and D7's act-line contract (`:1610`) binds mechanically. That is slot A's ledger question.

## 6. Not done / caveats

- `bats tests/completion-assert.bats` was **not run**: `cc-bats: REFUSED — 2 concurrent bats execution root(s) … AND 1-min load/core at or above 2.0` (rc 75). The waiver writes to `~/.claude/state/bats-waivers.jsonl`, a live store, so I did not use it. The sandbox replay mirrors the suite's `setup()` instead.
- The sandbox ledger's READOUT reads `completeness UNKNOWN` (no DoD); the live one read `Complete & live on trunk — nothing to do`. Both are RUNG ✅, which is all the arms read.
- The origin class was not re-derived in the sandbox. That it was origin live is inferred from D6 firing live. D8's need for an origin gate is a design choice.
- The anti-deference stale-read result (4/4 stops) was measured by replaying each text, not by reproducing the race. The flush-timing cause is inferred.
