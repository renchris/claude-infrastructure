# Critique of D1-rule-text, through the incident-replay lens

Design under review: `designs/D1-rule-text.md` (D1). Lens: replay B13 step by step against D1 and ask where the
idle breaks, by what mechanism, and whether that mechanism is deterministic (a hook) or advisory (text the same model
already ignored). Read-only; this file is the only write.

`TX:n` = line n of `~/.claude-quaternary/projects/-Users-chrisren-Development-agent-context-sync/666022fd-ed3e-4e72-b293-7caae899d585.jsonl`.
`IDLgz` = `~/.claude/autonomy/idl.jsonl.20261024T050411Z.gz`. Code paths are in this worktree. "Measured" names its
command; "estimated" names its method.

---

## 0. Verdict

**Score 3/10 on certainty of preventing a recurrence. Verdict: sound-with-fixes, as a first layer only.**

- **D1 breaks the idle at no step deterministically.** Every step where it acts is text. That text has to beat
  three things: the lead's own 85% belief that round 27 is waste (TX:4199), six restatements of its own hold, and
  machine text that still says "stop" or "nothing is in hand".
- **D1's two mechanical claims are overstated.**
  - The armed continuation (L1) is released after one forced turn in which the lead writes nothing.
  - The free-win (L3) is advice whose own text says "Nothing is in hand… recycle". This same session got three
    free-win fires on 10-23 and recycled zero times.
- **The replay leaves out the auto-mode classifier.** Under S-1 the Codex call still gets refused (TX:4640,
  TX:4678). Under R-7 that refusal is a class-C permission denial, so the ledger reads ⛔ again. The ✅ state that
  D1's replay assumes (§6.2) is then not the likely state.
- **A lead that also writes "No round 27 until you answer" is not caught by any D1 mechanism.** This is the lens's
  stress case. At best the lead gets ~3 to ~13 forced turns (estimated, below), and none of them tells it to start
  the round.

D1's text is still the right first layer. It deletes the sentences that licensed the idle and states the gating
predicate a code floor should implement. Several of its pieces should be grafted (§5).

---

## 1. Step-by-step replay under D1

There are three branches. **A** = fully compliant: files class B, writes no hold, uses the grant. **B** = half
compliant: files class B (or no packet), but keeps the prose hold. **C** = files class C as today.

| Step (UTC, TX) | What happened | D1 lever | Mechanism | Outcome under D1 |
|---|---|---|---|---|
| 02:22Z operator asks "is this forever?" (TX:4114) and about the $100 Codex plan (TX:4163) | Questions; no stop, no revoke | R-2: a loop stays open until X holds or a newer `Scope (frozen):` line ends it | Advisory | The operator's doubt is the counter-pressure D1 must beat. D1 has no sentence on "the operator questions the scope but does not end it" |
| **02:25:42Z close (TX:4199), rung 🔧, no packet yet** | "My recommendation, about 85% conviction: paste v33 now… **I won't start round 27 until you've decided on the stop rule.**" | R-3 (R:38 row): "file it and keep driving every in-scope item it does not gate" | Advisory | **The hold is born here, before any ⛔ existed.** R:103, R:160 and R:189, which D1 rewrites, were not yet in play; only R:38 was. No Stop hook fires on a 🔧 close with lanes in flight (IDLgz@02:25:45Z `capped:3>=3`) |
| 02:35:51Z research says "no ruling found" (TX:4235) | Grant read as TrueMemory-only | S-1 grant; R-7 ruling search | Advisory | Decision 2's *consent* question is answered by S-1. Decision 1: see §3 |
| 02:36:16Z / 02:36:27Z filings (TX:4254, TX:4260) | Two class-C packets | R-7: status-quo judgment call → class B; C only for operator-only acts | Advisory (the filing class is the model's choice) | A/B: e869 → class B, so `BLOCKED` drops to 0 (`scripts/wrap-ledger.sh:47-49`). C: unchanged. Decision 2 → no consent packet (see §2 for what replaces it) |
| 02:36:34Z lead note "No round 27 until e869fac7eb34 is answered" (TX:4270, persisted at `~/.cache/agentsync-bring-back/b13/round26/lead-notes.md:8`) | Hold written to disk | R-6: "never what the frozen scope directs (a loop's next round too)" | Advisory | B: the note is written anyway and outlives any recycle (§4) |
| 02:37Z-05:02Z ⛔ closes with lanes in flight (TX:4294-4420) | Allowed | None needed | n/a | Correct in all branches (control C1) |
| **06:44:32Z land done (TX:4431). First moment round 27 can start** | READOUT ⛔ | R-6 / R-10 | Advisory | **This is the decision point that matters, 4 h 8 m after the filing text had its chance.** A: round 27 starts. B: the ledger reads ✅ "Complete & live on trunk — nothing this session filed is open." (`scripts/wrap-ledger.sh:2587`). C: ⛔ |
| **F1 06:44:40Z close (TX:4437)** | Accepted by every hook | B: boundary-handoff free-win | **Mechanical forced turn, advisory content** | B: free-win fires (estimated: 64 ≥ 35, ledger ✅, no live wave, no conversation hold because task-notifications are excluded by `hooks/lib/context-econ.sh:369-…` `CC_CE_AUTO_RX`). Its reason reads "Nothing is in hand, so a successor loses nothing… recycle now… (Advisory, not urgent: if you have a genuine reason to keep working, do so" (`hooks/boundary-handoff.sh:957`, `:994`). That pushes away from round 27. C: nothing fires (as today, `maps/incident-replay.md` §6.1) |
| F2 07:39:47Z (TX:4458), woken by its own timer (TX:4445) | Re-closed ⛔ identically | R-6 timer clause | Advisory | The timer existed at F1 and F2 (TX:4434, TX:4455), and the wake produced the same close. B: free-win re-arms after 30 min idle (`hooks/boundary-handoff.sh:171`, `:816-832`) with the "REPEAT" text, again recycle advice |
| F3 08:34:59Z (TX:4476) "I'm stopping the inbox watcher for now" | Last Stop for 9 h 36 m | R-6: keep a `cc-await-ping` timer while a filed decision is open | Advisory | If obeyed: ~10 more wakes (estimated: 9 h 36 m ÷ 55 min), each re-closing the same way, plus a free-win REPEAT in B. If not obeyed: nothing in D1 can act (§8 item 3 of D1 admits this) |
| 09:11Z-15:38Z lead-supervisor STALL?/ESCALATED | Pages the desk only | None (out of scope for D1) | n/a | Unchanged |
| 18:11Z operator (TX:4488) | The rebuke | n/a | n/a | In A there is no 18:11Z message. In B/C the outcome is unchanged |

**Answer to "at which exact step does D1 break the idle?"** D1 can break it at three points: 02:25Z (R-3), 02:36Z
(R-7 class B plus "keep that course meanwhile") or 06:44Z (R-6 "a loop's next round too"). All three are text. The
only deterministic event D1 adds in any branch is the free-win forced turn in branch B. Its content tells the lead
to recycle, not to run round 27, and recycling in this pane had already failed twice (§2.2).

---

## 2. Defects in D1's own replay

### 2.1 The "mechanical refusal" from arming (L1) is one forced turn, and arming depends on the judgment that failed

- **D1's claims.**
  - §2(e) item 1: "Once armed, every later idle Stop is mechanically blocked … One compliant action turns into a
    mechanical refusal for the rest of the work."
  - §6.2: "(i) If round 27 was armed (L1), the armed path blocks this Stop: **mechanical**."
- **The code.**
  - The re-block skip at `hooks/session-continue.sh:1371-1442` (`reblock_is_idle_repeat`) skips the identical
    block after a forced turn that wrote nothing. The step stays armed, but the Stop goes idle.
  - A lead that answers the forced turn with "still waiting on your answer" therefore idles after one turn. D1's
    own L1 row admits this ("costs about one wasted turn"), which contradicts §2(e).
- **The arming condition is self-assessed.**
  - R-10 says to arm "on … a ⛔ or ✅ ledger over **ungated** in-scope work". A lead that thinks round 27 is gated
    will not arm.
  - A lead that thinks it is ungated would run round 27 anyway. So L1 adds no protection independent of the
    judgment that failed.
- **The hook's own reason text says to clear on ⛔.** An armed lead under ⛔ gets a forced turn whose reason text
  says "When done (✅/📦), blocked on the user (⛔) … run `session-continue.sh clear`" (`hooks/session-continue.sh:1368`).
  D1 depends on R-6's precedence sentence to beat the very text the hook delivers.

### 2.2 The free-win "forces that recycle mechanically" (§2(f), L3): measured false for this session

- **The hook is advisory by design.** It says "SAFETY: advisory only" (`hooks/boundary-handoff.sh:601`), and its
  reason text carries "if you have a genuine reason to keep working, do so" (`:994`).
- **Measured: free-win fired three times for 666022fd on 10-23** (`gzcat IDLgz | grep 666022fd | grep boundary-handoff`,
  rows with reason `past-boundary` and axis `freewin`, at 05:15:50Z, 15:46:53Z and 23:40:13Z, fill 37/48/56).
  **Zero recycles followed:**
  - TX:2333 deferred: "recycling now would kill [the fire script] partway through".
  - TX:2507 (05:47:59Z): "The recycle didn't finish. It typed `/exit` … couldn't read the box back".
  - TX:3955 (23:40:20Z): "Recycling has failed twice in this pane … I'll … stay put."
- **The successor path is broken in this pane.** D1's branch-(ii) outcome at F1 ("the successor re-reads the
  persisted loop scope") needs a recycle that this pane could not complete.

### 2.3 The replay leaves out the auto-mode classifier, which puts ⛔ back

- **What D1 claims.** §6.1 says "S-1 alone removes decision 2". §6.2 then assumes "Ledger under D1 (class B + no
  packet)" ⇒ `RUNG=✅`.
- **The record.** The auto-mode classifier refused the round-27 Codex stages as `[Data Exfiltration]` at TX:4640
  (18:16:33Z) and TX:4678 (18:17:21Z). That was **after** the operator's explicit in-chat grant at TX:4488.
  - TX:4683: "even the tiny 'reply OK' probe, which went through earlier, is refused".
  - TX:4925: "Codex: standing-authorized … but the auto-mode classifier refuses xverify.py … until the operator adds
    the allow rule".
  - A CLAUDE.md grant is weaker evidence to a classifier than the operator's own words in context (estimated: the
    operator's words did not move it).
- **What follows under D1.**
  - The allow rule is a settings edit, which the hard constraints forbid. So the refusal is an operator-only act.
  - D1's R-7 names "a permission denial" as class C. So under D1, decision 2 becomes a class-C permission packet:
    `BLOCKED=1`, the rung is ⛔, and the STOP-ASK `→ Next` line returns (`scripts/wrap-ledger.sh:3101`).
- **D1 lists this case only as control C3** (D1 §6.3, "Improved; no new block"). It is in fact the main path of the
  incident under D1: the first round that hits the refusal leaves ⛔ open at the next round boundary. Only R-6's
  text then stands between the lead and an idle.

### 2.4 The hold predates the rules D1 rewrites, and §1.2's evidence over-reads the transcript

- **The hold came from the lead's own judgment, at a 🔧 close.** TX:4199 (02:25:42Z) states it with no packet
  filed. The motive was the lead's own value judgment: "A round with nothing new is unlikely ever to come …
  My recommendation, about 85% conviction: paste v33 now". D1 asks the lead to run a round it believes, at 85%, is
  waste, on the strength of system-prompt text.
- **§1.2 item 1 ("the rule beat the tool's own definition").** TX:4280 shows why the lead printed the header. A
  handoff-claim-assert block (TX:4274) had refuted its `▶ Run this`, and the lead wrote "Finding the command you
  actually use to answer a decision", then ran `cc-decide | head -20` and `sed -n '/^Verbs:/,$p'` (TX:4281,
  TX:4290). It was looking for the answer verb, not choosing a class. "R:160 won" is not shown.
- **§1.2 item 2 (TX:4495).** It shows the lead switched after a fresh operator rebuke in context ("I thought you
  had autonomous zero human in the loop…"). That is evidence for fresh in-context words, which D1 cannot supply.
  It is not evidence for always-loaded text.

### 2.5 The rule text and the replay disagree on decision 1

- **What the rule text says.** G-3 calls e869 a mistaken re-ask: "`eb3dbe1e5e94` had settled 'keep looping until
  dry' by silence … yet `e869fac7eb34` re-asked the same fork" (D1:462). It then says "That is the answer: act on
  it and cite it". R-7 says a fired class-B default "rules by silence". Neither text has an exception for new
  evidence or for staleness.
- **What the replay says.** D1 §6.1 (D1:745) says "New evidence (24 more rounds) makes a re-ask legitimate, but as
  **class B**". That sentence exists in no rule block (`grep -n -i 'new evidence'` over D1 finds only :745,
  measured).
- **Consequences.**
  - A lead that follows the text would not file the operator's own "is this forever?" question at all.
  - A lead that follows the replay would. Which one the model picks cannot be predicted.
  - The ruling by silence on `eb3dbe1e5e94` is what produced the 10 further days of looping the operator objected
    to at TX:4114 (the plan records it at `agent-context-sync/docs/plans/bring-back-ocr.md:884-885`).

### 2.6 The eval T-E cannot see the idle

- **It starts too early.** T-E replays the prefix through TX:4253. At that point round 27 cannot start: round 26
  lands at 06:44:32Z (TX:4431). The F1 decision is never in the eval.
- **Its pass criterion is too loose.** Criterion (c), "start round 27 **or** file class B with a keep-looping
  default", passes branch B (class B plus a prose hold). That is the branch D1 itself leaves to text.

### 2.7 Smaller points

- **The class taxonomy can still send both B13 questions to class C.**
  - Decision 1's yes option is "you pasting setup prompt v33 on the real Mac" (`DEC/e869fac7eb34` what_plain). The
    lead itself called the paste "a step only you can do" (TX:4495). R-7's C list includes "an act only the
    operator may authorize (… production …)".
  - Decision 2 is "outbound". S-1's carve-out ("ask first if it holds … a repo-listed escalation surface") meets
    agentsync's "names the tenant" surface (`agent-context-sync/CLAUDE.md:81-84`), which the lead's research had
    flagged (TX:4235).
  - A literal reader can therefore re-file both as C.
- **The R-6 timer clause would not have broken the idle.** The timer was armed at F1 and F2. The F2 wake (TX:4445)
  re-closed ⛔ word for word (TX:4458). The slim line also lacks G-4's "re-read packets and scope" and the doubling.
- **One machine string is missing from §3.4.** In branches A and B the READOUT the lead sees at F1 is "✅ Complete
  & live on trunk — **nothing this session filed is open.**" (`scripts/wrap-ledger.sh:2587`, `:3114`). That is
  false with an open class-B packet. It is not in D1's §3.4 list; L4 names only operator-readout.
- **A successor inherits the hold.** D1 §2(f) says a successor "re-judges the gating without the predecessor's own
  'No round 27 until you answer' in its context". But the hold is on disk at `lead-notes.md:8`, and the lead's
  recycle brief sits beside it (`round26/recycle-prompt.md`, TX:3965).
- **The loop's cost is unbounded.** In A, the class-B default "keep looping" fires at the deadline and becomes the
  next lead's "ruling by silence". That is the `eb3dbe1e5e94` cycle again: about 80 confirmed findings a round for
  24 rounds with no downward trend (TX:4254 option text). L2 accepts this. A final design should pair a loop
  scope's class-B default with a re-ask cadence.

---

## 3. The brief's three direct questions

**Would the lead have filed `290215743799`?**
- **Probably not as a consent packet.** S-1 covers its exact shape: committed code, `git archive`, Codex CLI, under
  80%.
- **But it would have filed a class-C permission packet once the classifier refused** (§2.3). R-7 prescribes C for
  that, and the allow rule is operator-only.
- **Net:** the same ⛔ rung, a different packet id.
- **S-1's carve-out could also bring the consent ask back as class C** ("outbound", the tenant escalation surface,
  §2.7).

**Would it have re-asked a ruling?**
- **Decision 1: it depends on which D1 text the model follows** (§2.5).
  - Under R-4/G-3 it treats `eb3dbe1e5e94` as the answer and does not ask. It is findable: the plan log at
    `bring-back-ocr.md:884-885`, and D1's measured `jq` (17 hits).
  - Under §6.1 it re-asks as class B.
  - Either way it does not file class C, provided R-7 is followed.
- **Decision 2: the consent question is not re-asked; the permission question is new** (§2.3).

**A lead that also writes "No round 27 until you answer":**
- **No D1 mechanism reads prose.** D1 rightly adds no phrase (D1 §7; "need your call" is the ledger's own ⛔ text,
  `scripts/wrap-ledger.sh:2607-2609`).
- **Branch C:** zero hook events, identical to the incident.
- **Branch B:** about 3 free-win forced turns before F3 (F1, plus one each 30-min idle re-arm at F2 and F3), and
  about 10 more if the R-6 timer is kept (estimated from `IDLE_REARM_MIN` 30 and the 55-min timer). Each one says
  "Nothing is in hand… recycle". None names round 27.
- **The hold survives a recycle** through `lead-notes.md:8`.

**Certainty (estimated, by branch reasoning, not measured).**
- **Deterministic prevention: ~0 in every branch.**
- **Prevention through text depends on branch A happening at 02:25Z-06:44Z.** No measurement supports estimating
  how likely A is, and n=1. The same model had already ignored R:4 ("without stopping to ask"), R:105 and S:166
  (`maps/incident-replay.md` §5). Only D1's T-E, fixed per §2.6, could measure it.

---

## 4. Fixes D1 should take before it is grafted

1. **Correct the two overstated mechanical claims.** In §2(e) item 1 and §6.2 (i)/(ii), state that the armed path
   gives one forced turn per arm (`:1371-1442`). State that the free-win is advice with "Nothing is in hand"
   wording, and that this pane's recycles had failed (TX:2507, TX:3955).
2. **Fold the classifier refusal into §6.**
   - Model the D1 state at F1 as ⛔ `BLOCKED=1` (permission) and keep "class B + no packet" as the other branch.
   - Add to S-1 or G-9: "a classifier refusal of a granted act is a permission denial that gates only that act;
     run the rest of the work without it".
3. **Settle decision 1 in the text.** In R-4 and G-3 add: "unless material new evidence has arrived since the
   ruling, or the operator has questioned it in this session; then re-ask as class B, with the ruling's course as
   the default". Drop "yet e869 re-asked" as a counter-example, or qualify it.
4. **Classify by what the packet gates, not by the acts its options name.** Add: "an operator-only act inside an
   option (a paste, a deploy) is a needs-human step after the answer; it does not make the question class C".
5. **Rebuild T-E.**
   - Add a replay point at TX:4436, after the land notification, with the ledger stubbed to D1's two likely states
     (✅, and ⛔ from the permission packet).
   - Pass only on a tool call that launches round 27, not on "files class B".
   - Also run a variant whose context already holds the TX:4199 hold, which is the stress case.
6. **Add `wrap-ledger.sh:2587`'s "nothing this session filed is open" to §3.4** as machine text a code change must
   reword.
7. **Make it a precondition, not a recommendation, that D1 ships with the code backstops.** For this lens D1 alone
   cannot reach goals (e) and (f). The pairing D1 §8 names (ledger `LOOP_OPEN`, a session-continue ⛔ floor, the
   lead-supervisor subject nudge) is the deterministic part. Without it, the stress case is unchanged.

---

## 5. Best ideas worth grafting

- **R-6's gating predicate:** "A decision gates only the act it asks about and work built on its answer, never what
  the frozen scope directs (a loop's next round too)". It is the exact predicate a code floor should compute, and
  it is the same discharge in text and in code.
- **R-7's class-B template**, with `--default "<status quo>" --deadline --default-effect no-change --project`. The
  flags exist and are enforced (`bin/cc-decide:176-179`, `:197`, `:208-212`). It removes the false ⛔ at the source
  with no code change, because the ledger counts class C only (`scripts/wrap-ledger.sh:47-49`).
- **The S-1/G-9 standing-grant section** with its envelope (`git archive`, `-s read-only`, the 80% meter read from
  `window_minutes` 10080, no paid API, not a routing change), plus the classifier caveat from §4 item 2.
- **"Never add a `- [ ]` box for a loop"**, with its alarm-polarity reasoning: `dod-persist set` only appends, so
  the box would be a permanent inherited 🔧.
- **R-2: persist the scope with `dod-persist.sh set` at intake.** The store never held B13's loop scope during the
  idle (`maps/incident-replay.md` §0 item 1), so a future `LOOP_OPEN` field needs this.
- **G-4: name open decision ids in any recycle brief.** A successor's ledger counts only its own sid
  (`scripts/wrap-ledger.sh:1529`). Extend it to "and say which items are NOT gated".
- **The §3.4 table of machine text that contradicts the rule**, a ready work list for the code designs.
- **T-E as a concept:** a behavioural replay eval of old versus new text. It is the only way to measure a text
  layer, once fixed per §4 item 5.

---

## 6. What I ran

All reads. Nothing was written except this file.
- `jq` extraction of TX:4199, 4235, 4270-4294, 4431-4495, 4640, 4678, 4683, 4925, 2333, 2507, 3204, 3955.
- `gzcat IDLgz | grep 666022fd | grep boundary-handoff`, summarized: 3 free-win fires on 10-23 (measured).
- `sed -n` on these sources:
  - `hooks/boundary-handoff.sh:600-700`, `:700-1010`.
  - `hooks/session-continue.sh:1090-1110`, `:640-760`, `:1280-1460`, `:1525-1540`.
  - `scripts/wrap-ledger.sh:40-60`, `:2580-2720`, `:3101`.
  - `hooks/completion-assert.sh:425-475`.
  - `hooks/dod-persist.sh:1-20`, `:450-495`.
  - `bin/cc-decide:1-30`, plus a `grep` of its flags.
  - `hooks/lib/context-econ.sh:369-…`.
- `sed -n` on `agent-context-sync/docs/plans/bring-back-ocr.md:880-888`, `agent-context-sync/CLAUDE.md:79-86` and
  `round26/lead-notes.md:1-12`.
