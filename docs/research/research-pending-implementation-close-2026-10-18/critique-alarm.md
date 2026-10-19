# Critique: alarm inflation and false positives in DESIGN.md

Lens: would the proposed signal or rung fire on Q&A, status checks, /accounts, "are we done?", research-program turns, fired peers, subagents or teammates? Would it nag, turn every turn into a sign-off request, block legitimate closes, or loop the Stop hook? Worktree `close-status-research` at `36afca47f`. Scratch and scripts: `/tmp/rpic-critique-alarm/`. Corpus: slot G's census, `/tmp/rpic-G/sig.jsonl`, which holds 1,877 origin-interactive turns in 347 sessions, with turn timestamps spanning 2026-09-28 to 10-19. Decision store: `~/.claude/autonomy/decisions/*.json`. Terminal packets that were compacted are missing from it, so every packet-based count below is a lower bound.

## Verdict: revise

The design measured the alarm it adds (D8: 3 fires in 1,877 turns). It did not measure the alarm it **widens**.

- **What A3 and A9 do.** A3 counts re-check stamps toward ⛔. A9 step 4 stamps "every remaining" open decision on each `/explain-decisions` run. The packets that run re-checks are the long-lived standing pile.
  - Open class-C packets are p50 **18.4 d** old today (n=57).
  - Resolved ones lived p50 0.35 d (n=413).
- **So a stamped session reads ⛔ for weeks.** Through all of that time, the existing ⛔ term in completion-assert convicts every Stop whose text carries any CLOSE token (`done`, `complete`, `landed`, `remains`, `follow-up`, `let me know if` …, `hooks/completion-assert.sh:428`).
- **Replayed over the census** (assumption: A9 as written, each `/explain-decisions` turn stamps the foreign open class-C pile):

| measure | today | after A3+A9 |
|---|---|---|
| turns reading ⛔ | 196 (47 sessions) | **380 (66 sessions)**, 10.4% → 20.2% of turns |
| status-class prompts reading ⛔ | 4 | 12 |
| ⛔-term convictions surviving A1 (uncapped) | 16 | **72** |
| blocks emitted under the assert cap (3 per session) | 16 | **58** |

  Script: `/tmp/rpic-critique-alarm/union.py`.
- **Two of the design's claims are therefore false as consequences.** "Q&A cannot trigger it" (DESIGN:8) and "it does not inflate alarms on Q&A or status turns" (DESIGN:90-92) hold only for *creating* the signal. They do not hold for what the signal does on every later turn.

## Issues (most severe first)

### 1. HIGH: sticky re-check ⛔ multiplies Q&A convictions by the existing ⛔ term

- **Mechanism.**
  - The ⛔ term (`completion-assert.sh:1204-1208`) has no write-turn gate, no turn scope, and no assignee or peer gate. Its only filter is the CLOSE lexicon at `:467-470`.
  - A1 exempts only a no-polarity close, or one with ⛔ leading line 1 or 2.
  - A Q&A answer is neither, so it is convicted.
- **Sandbox** (`/tmp/rpic-critique-alarm/blk.sh`: the DESIGN's `blk.sh` seams, a stub ⛔ ledger, and assistant-text-only transcripts):
  - q1 "…token budget; the upgrade is done." ⇒ `CA=fired:false-done:ledger`
  - q2 "Mostly yes … The rest remains as before." ⇒ fired
  - q3 "📬 pane 57 … It landed" ⇒ fired
  - q4 "Still quiet; the watcher is re-armed … complete." ⇒ fired
  - The facts string is `BLOCKED ON YOU — 3 decision(s) filed this session are open … that IS your rung`.
- **Census upper bound** (`edsticky2.py`): 39 sessions with a later turn after `/explain-decisions`; 251 later turns read ⛔; **60 convictions after A1**. Examples:
  - e416c8f8 "What is CLAUDE_CODE_RIPPLING_TULIP?" → Q&A answer
  - e416c8f8 "(Checking in)" ×2
  - cc94029a "Is question #1 asking …" → "Mostly yes …"
  - 74728043 02:51, the in-pane implementation of an approved item: "It landed".
- **This already happens today.** In the live IDL window 2026-10-18T12:18Z → 10-19T04:32Z, the ⛔ term convicted e52f1f63 04:26 "Yes, the kitty running now is the official one …", a Q&A answer, and 6069b9d3 18:21 "The only open item is your log-retention call … I recommend keeping 90 days", which was honest. A1 leaves both in place (`blkfull.py`).
- **It also starves the assert budget.** Assert-class convictions and the ⛔ term share one budget: `MAX=3` per CFG|SID|CWD (`:132`, `:1625`). In the same window, 254 assert-class rows were `capped:3>=3`, against 46 fires. After the change, 8 of the 26 convicted sessions hit the cap on ⛔ noise alone, which silences later real dirty or unlanded convictions. The code itself documents that starvation at `:1631-1640`.
- **The sibling study rejected both shapes.**
  - "A store-or-silence terminal gate. It nags live conversations about 1:1" (`wt-cc-004752-67086/.../README.md` §6).
  - "Any new arm in the shared assert budget" (same §6).
  - A3 rebuilds both through the existing arm.
- **Fix.**
  - The ⛔ term convicts only on `BLOCKED − BLOCKED_RECHECKED > 0` (session-filed packets). A re-checked-only ⛔ informs the rung and the readout but never blocks.
  - Or scope re-checks to the stamping turn (see issue 3).
  - Pin it with a bats case: a Q&A answer over a ⛔ ledger whose BLOCKED is entirely re-checked ⇒ ABSTAIN.

### 2. HIGH: A9/A8 stamp items as sign-offs that §4 classes as do-unless-vetoed or no-change

- **The count.** §4 tiers the 59 incident decisions: 33 sign-off, 12 reversible ≤90 for class B, 10 where the recommendation changes nothing (`/tmp/rpic-H/tiers.tsv`: 33 T3, 12 T2, 10 T2-nochange).
- **The contradiction.**
  - A9 step 4 says "stamp **every remaining one**", and every stamp counts toward ⛔ (A3).
  - A8 says "file the rest … so the rung reads ⛔".
  - The design's own rendered example is "⛔ Research done — **56** decision(s) await your sign-off" (DESIGN:123). §4 says 33.
  - So N is inflated by about 41%, and the operator is asked to sign off on items the design says should run by default or change nothing.
- **There is no path out.** `recheck` never changes class (A4: "Never changes: status, id, class"), and no C→B verb exists. The §4 class-B tier is unreachable for re-researched packets.
- **Fix.** `recheck --tier signoff|default|nochange`. Only `signoff` counts toward ⛔. `default` needs a C→B transition with a deadline, or a filed class-B successor. `nochange` closes the packet when conviction is >90, or stays in the ◆ pile.

### 3. HIGH: a stamped session can never be "good to close"; the ⛔ survives recycles as a nag and dies as a fact

- **Never good to close.** With the pile at p50 18.4 d, a stamped session reads ⛔ until the operator resolves every stamped packet. The operator memory `feedback-operator-will-not-read-signoffs.md` says he will not read them. So:
  - Every "are we done?" answer is permanently "❌ no", an alarm that always fires and carries no information.
  - The ✅ SAFE TO CLOSE certificate is withheld for the session's life (`operator-readout.sh:2113`).
  - D6 and D7 switch off for every later write turn (`completion-assert.sh:1502` and `:1610` gate on ✅/👤), including the implementation turn after an in-pane approval.
  - boundary-handoff FREE WIN is suppressed for the life of the session, not for the turn (`boundary-handoff.sh:547`).
  - This applies to 39 sessions in the census window (issue 1).
- **The recycle conflict** (inferred from code text). On a recycle, `handoff-fire.sh:16821-16824` writes into the successor brief: "A rung other than ✅ is work that survived the recycle and is now YOURS: collect it before starting anything new."
  - The design's own sign-off → recycle path (§5) recycles a ⛔ research pane with `--goal '… do not touch unapproved items'`.
  - The successor is therefore told both to collect and not to touch the same 50+ packets.
  - Because the sid changes, the successor's ledger reads ✅. A8/A9 then steer it to re-stamp, so the nag propagates down the recycle chain.
- **Fix.**
  - Re-check stamps carry a TTL, or count only until the first no-verdict or ⛔-led close after the stamp. After that, the items render as A11's `◆ [this session]` lines rather than as the rung.
  - The successor-brief stamp says "research sign-offs are the operator's, not yours to collect" when `BLOCKED_RECHECKED == BLOCKED`.

### 4. MEDIUM: the same pile is stamped by many concurrent panes and counted twice in one block

- **Volume.** 73 turns in 48 sessions invoked `/explain-decisions` in the census window (`ed.py`). The reconstructed foreign open class-C pile at each invocation was p50 **65** (min 27, max 75; `edsticky2.py`).
- **Concurrency.** Up to **7** such sessions were live at once (2026-10-06 07:04Z; `overlap.py`). Each would show `OPERATOR ▸ ⛔ Research done — ~65 decision(s) await your sign-off` for the same packets.
- **Repeat citations.** 4 of 36 packets cited with a recommendation were cited by 2–3 distinct sessions; `33620baeb16b` was cited by 3 (`sticky.py` D).
- **Double count.** Inside one block, the A7 header N and the `◆ N decisions — your call` pile count the same packets again. A11, which would separate them, is "optional" (DESIGN:354).
- **Fix.** Make A11 part of A7. Attribute a packet to its most recent re-checker only, so one pane owns the ask.

### 5. MEDIUM: D8's evidence is underpowered, its fire set includes a false positive, and recycle lineage fabricates "foreign" ids

- **"0 of 57 status prompts" has no power.** At D8's base rate of 3/1,877 (0.16%), the expected count on 57 turns is 0.09. The rule-of-three 95% upper bound from 0/57 is 5.3%.
- **The status near-miss.** f583a3fd 10-19T01:54, prompt "What are our current steps/decision from THIS session …?". It cites open foreign class-C `33620baeb16b` "where I recommend B at 77%" on a REC line, with polarity `none`. It abstained only because line 1 reads "There's nothing left to do …" and DONE1 is anchored at `^nothing …`. Line 1 "Nothing left to do from this session" would fire D8 (`statusd8.py`).
- **One of the three fires is a false positive.** d6ae5d72 10-18T06:19, prompt "/Users/chrisren/Downloads/2706 E 3rd St.pdf" (house research). It relays the standing packet `33620baeb16b` (filed by `2809f7c9`, an unrelated lineage) under the sanctioned S2 shape: "✅ Good to close: yes. Nothing of mine is open. Two follow-ons are yours: one decision …".
  - By slot G's own rule, a recap of items that predate the turn is NEGATIVE.
  - Hand precision is 2/3, Wilson 95% [0.21, 0.94], so it is not "measured narrow".
- **The sanctioned template trips it.** The S2 yes-branch is "follow-on: <filed ids>", and it contains the `nothing of mine is open` phrase D8 keys on.
- **The design's own flow trips it** (inferred). §5 says "the sid changes on recycle, so the successor does not own the re-checked packets". Any successor that implements the approved items and closes yes while naming the unapproved ones with recommendations fires D8. Both d6ae5d72 and f583a3fd are "Continuation of the Austin house …" successors.
- **Fix.**
  - Replace the lexical REC-on-line test with a store-side fact: the session read the packet itself (a `cc-decide show/list` Bash call or a Read of the packet file).
  - Or require ≥3 cited ids (incident 17, false positive 1).
  - Re-measure on the census before landing.

### 6. MEDIUM: D8 fires at 👤, can fall into the assert budget, and collides with the sibling's "D8 v2"

- **It fires at 👤.** The predicate has `RUNG∈{✅,👤}` (DESIGN:289). The sibling rejected the prose follow-on arm because "it blocks operator steps at 👤" (sibling README:293-294), and its own F13 "D8 v2" is "Silent on … 👤, ⛔" (README:200).
- **It can be charged to assert.** "It never shares assert" (DESIGN:287) holds only when D8 fires alone. CLASS selection (`completion-assert.sh:1681-1690`) gives a non-assert class only to a lone arm. D8's target closes also trip D4 or D1 (slot B c3 "Say the word…" fires D4; c6 "requires your" fires D1). Then CLASS=assert, which is the starvation the sibling's §6 rejects.
- **It collides in name and in effect.** Two different arms named D8 (`pending` here, `followon` in the sibling) target overlapping yes-closes, each with its own cap of 2. Landed together they double-block one close. DESIGN.md never mentions F13 (grep for `F13`/`followon`/`v2` finds nothing).
- **Fix.** Drop 👤. Set CLASS=pending whenever d8=1 and contra=0, regardless of D1–D5. Merge with or sequence against the sibling's F13 under one name and one cap.

### 7. MEDIUM: A1's "line 2 begins with ⛔" exemption silences the contradiction it should catch

- **The shape it lets through.** A1 skips `contra` when "line 1 or line 2 of the close begins with ⛔" (DESIGN:228). The S1 rule makes agents relay the rung on line 2, so `✅ Good to close: yes — nothing of mine is open; follow-on: none` / `⛔ Research done — …` is exempt.
- **It fires today.** That shape is `blk.sh`'s own c1 fixture, and in the sandbox `c1 ⛔ CA=fired:false-done:ledger`.
- **The test cannot see it.** A1's CONTROL test (DESIGN:237) uses the yes line without the relayed ⛔ line 2.
- **Fix.** Exempt on polarity `no`, or on line 1 beginning with ⛔ **and** polarity ≠ `yes`. Add the c1 fixture as a FIRE control.

### 8. LOW: the ⛔ term's facts become false for re-checked packets

- `:1207` prints "decision(s) **filed this session** are open". A1 says "every other ⛔ case is unchanged", and A3 adds `BLOCKED_RECHECKED` but nothing rewords this string.
- **Fix:** word the facts from `BLOCKED_RECHECKED`.

### 9. LOW: fired peers and assignees are not exempt from the ⛔ term

- **The gap.** `:1204-1208` carries no `_ca_assignee` or origin gate, unlike D6 (`:1502`) and D7 (`:1610`). `handoff-fire.sh:7721-7726` rules that on a fired peer, "filing the operator's decision IS the deliverable" (3 of 3 refusals were wrong).
- **Today.** 6 of 24 ⛔ rows in the IDL window were fired peer `30a68a59` (`blkidl.py`).
- **The widening is small.** 3 of 1,162 fired briefs mention `explain-decisions`, and 4 mention re-checking or `cc-decide list --open`.
- **Fix:** follows from issue 1, plus skip the term for confirmed fired peers when every BLOCKED packet is re-checked.

### 10. LOW: A7's ⛔ header is not write-turn gated

- **Read-only turns render it.** The block renders whenever `total>0`, and `total` includes the standing decision pile (`operator-readout.sh:1446-1447`). So it renders on read-only turns: the incident's read-only turn rendered "◆ 73 decisions — your call", per slot B §1. It re-renders on any change, or after the 900 s TTL (`:320`).
- **The reorder it copies is gated.** A7 mirrors the certified reorder, which is gated on `CERT_WROTE=0` (`:1513`). A7 itself is ungated, so every Q&A Stop in a stamped session leads with "⛔ Research done — …", including turns that did no research.
- **Fix:** gate the ⛔ reorder on the stamping turn, or on `CERT_WROTE=0`.

### 11. LOW: A6 template priming (plausible)

- **Exposure.** The no-branch placeholder now carries "research done, implementation pending" in **every** D6 block reason. That is 8 shape fires in 6 sessions in the 16 h IDL window, most of them not research.
- **Copy risk.** Agents copy that template word for word (slot B §3, measured on `:179`).
- **Fix:** keep the research wording in D8's reason and the A8 rule, and leave the generic D6 placeholder unchanged.

### 12. LOW: no research-program carve-out on the re-check path

- **The gap.** D8 abstains in a program (`_ca_rp_active`), but A3 and A9 do not. A program session running `/explain-decisions` would stamp the pile and go ⛔. The ⛔ term then convicts certificate relays that contain "complete", against the E0 program rule pinned at `research-program-exemption-rules.bats:36`.
- **Fix:** A9 step 4 and A4 refuse, or no-op, when `research-program.sh is-active "$PWD"`.

### 13. LOW: D8's demand can be impossible to satisfy (bounded, not a loop)

- **The impossible part.** D8's reason says "stamp each other one with cc-decide recheck". A4 refuses conviction >90. B6 leaves a 92% auth packet (`b4373234dd78`) unfileable.
- **What remains.** The only exit is to relabel the close "no".
- **The bound.** Caps are assert 3, pending 2, shape 2, verdict 2 and act 2 per CFG|SID|CWD (`:1625`), with a hash latch. That is at most about 11 blocks per session. **No unbounded Stop-hook loop was found.**
- **Fix:** have the reason name the >90 branch: implement the item, or name the surface in line 1.

## What holds up (checked, not refuted)

- **The primary signal needs a write.** Creating it requires an explicit `cc-decide` call, so Q&A, `/accounts` and status turns cannot *create* it.
- **`/accounts` is clean.** It never trips p2s (slot G §6), and 1 of the 251 sticky later turns was an `/accounts` turn.
- **Subagents are out of reach.** completion-assert is registered on `Stop` only (`jq … ~/.claude/settings.json` ⇒ `Stop`) and reads non-sidechain records (`:355`).
- **Self-close is unaffected.** It never refuses on ⛔ (`handoff-fire.sh:7721`, `:14242`).
- **Verbatim readout relays are no live risk yet.** Readout decision rows carry a REC token in only 2 of 57 open class-C sentences (`whatplain.py`), and 0 of 1,877 finals relayed a `[decision X <id>` row (`relay.py`).

## Evidence index (all under /tmp/rpic-critique-alarm/)

`union.py` (today vs after), `edsticky2.py` / `edsticky.py` (upper bound after `/explain-decisions`), `sticky.py` (citations of foreign open class-C ids, packet ages, duplication), `baseline.py`, `overlap.py`, `ed.py`, `statusd8.py`, `blkidl.py`, `blkclose.py`, `blkfull.py` (live IDL ⛔ rows with their closes), `blk.sh` (sandbox; IDL under `sbx/`), `whatplain.py`, `relay.py`.

Measured means a script over the stores or the census, or a hook sandbox run. Inferred: the recycle-chain propagation (issue 3) and template priming (issue 11). The A3/A9 replay assumes agents follow A9 step 4 literally.
