# C4: widen the offer lexicon (`CA_OFFER` / anti-deference `TELLS`) with a conditional-permission class

Round 2, 2026-10-18. Candidate from axis 07 (RC2, F2) and its skeptic (§S2 F2, §S4.3). Read-only in the repo; every
script, copy and test run lives under `/tmp/r2-C4/`. Every number is labelled measured (with the command) or
estimated (with the method).

Status: complete. Every measurement below ran, including the bats A/B in §7.

## 1. Answer first

- **Verdict: C4 does not clear 90%, and no variant I measured comes close. Do not widen `CA_OFFER` or `TELLS`
  with a conditional-permission class.**
  - Conviction that any measured form of the widening should land: **5%**.
  - Conviction that leaving it out (the non-action) is right: **88%**.
- **Why.** I built the structural class the brief describes and ran it as a real arm of a copy of
  `hooks/anti-deference-nudge.sh` over 30 days of Stops. A conditional ask is the form agents use for nearly every
  legitimate operator question too: "once you pick", "when you say sign in", "tell me when the call is over",
  "answer by id". In a seeded random sample of 60 of its 233 new firings I hand-read every message. **4 were
  drivable deference (6.7%, Wilson 95% CI 2.6–15.9%)**, 4 were borderline, and 52 were legitimate operator asks
  (measured: `/tmp/r2-C4/data/labels60.tsv`).
- **It fires on the case axis 07 said must stay able to stop.** The counter-example
  (`58d3640a…:3380`, "If you agree, I'll start with step 1 … for join.reso.gl", where the operator then chose the
  other page) is blocked by the widened arm (measured: `run.sh new msgs quoted.list q1` → `s002749 fired
  conditional-ask`).
- **Volume and a side effect.**
  - The arm would add **233 distinct blocking fires in 30 days**, at most 199 after the per-session cap of 3. The live
    `deference` arm fired 24 times in 21 days (measured; §3 and §4.4).
  - The widened tell also routes about **86 more messages a month into the genuine-blocker exit, which opens a class-B
    `cc-decide` packet for each one**. That includes a duplicate packet for an already-filed ⛔ decision (a044).
- **The D4 home is no better.** Run through D4's own gate and its "(b) named remaining work" half, 18 of the 60
  sampled messages still fire, and 2 of those are true (11%, CI 3.1–32.8%). D4 also runs after the ledger read, on
  the slow path that hits the 5-second Stop timeout (axis 07 §S0).
- **The narrowings fail too** (§5):
  - "Should I …" sentences: 4 of 10 true.
  - Bare-assent forms only ("if you agree/approve", "say go and I'll"): 0 of 6 true in the sample.
  - Requiring a stated conviction above 90% in the same message: 4 fires in 30 days, and both sampled ones were
    false, because the number belonged to a different item than the ask.
- **It breaks a pinned test.** The existing suite on the prototype copy reads `1..61` with 55 ok, against 56 ok on
  the HEAD copy. The one new failure is #11, "silent: 'should i download' does not match 'should i do'", a case the
  hook's authors deliberately pinned silent (§7).
- **The recall premise is weaker than axis 07 assumed.** I hand-labelled all 46 assistant turns that preceded a short
  operator "yes / proceed / do it" (my rebuilt set; axis 07 had 42).
  - 28 were legitimate asks: spend, sign-in, a filed ⛔ decision, a ≤90% handover, a publish, a value pick.
  - 10 were real defects, and only 5 of those 10 used any permission-ask form.
  - The widened arm catches 2 of the 10, at a cost of 2 false fires and 3 borderline ones on the same set.
- **Remaining work** (§6). The defect inside the affirmed set is mostly **a >90% recommendation handed over as a
  question**: a000 at 93% framed as "⛔ One decision needs you", a002 at 92% as "answers still yours", a005 at 95%.
  - That is a per-item property: the number and the ask sit in the same list item.
  - A lexical offer tell cannot see it. The write-time refusal in `cc-decide open` (N > 90) already blocks it for
    filed asks.
  - The prose form needs a per-item parser, which is a separate candidate and not designed here.

## 2. Setup facts

- **Repo and hooks.** HEAD is `f12dd4b12` (2026-10-18 16:28 -0500; measured, `git log -1`). The hooks were read at
  that revision.
  - `hooks/anti-deference-nudge.sh` (641 lines): `TELLS` at `:168`; the genuine carve-out `HARD_CORE`/`SOFTCALL` and
    the class-B packet exit at `:453-491`.
  - `hooks/completion-assert.sh` (1,660 lines): `CA_OFFER` at `:1280`, D4 at `:1272-1287`, the close-tell gate at
    `:394-397`, the ledger read at `:573`.
- **The axis 07 workspace is gone.** `/tmp/should-census/` (its scripts and `out.json`) no longer exists; the 16:34
  reboot cleared `/tmp` (measured, `ls` → "No such file or directory"). I rebuilt the corpus with
  `/tmp/r2-C4/bin/extract.py` (`python3 -I`). Its counts are this pass's own.
- **Corpus.** Measured with `python3 -I /tmp/r2-C4/bin/extract.py`, which printed `files=2555 stops=20010 affirms=56`.
  - Files: the main-session transcripts modified in the last 30 days under
    `~/.claude{,-secondary,-tertiary,-quaternary,-next,-next4}/projects/*/*.jsonl`.
  - Exclusions: `-private-*` harness projects and subagent files.
  - De-duplication is by real path, so the `~/.claude-next/projects` symlink to `~/.claude/projects` is read once.
    Axis 07's 3,294 files counted it twice.
  - **Population = Stop events.** One `system/stop_hook_summary` row is one Stop. MSG is the last main-agent
    assistant record with text before that row, with its text blocks joined by `\n`, which is how both hooks extract
    it (`anti-deference-nudge.sh:159-162`, `completion-assert.sh:282-285`). There are 20,010 Stops, de-duplicated by
    `(sessionId, uuid)`.
  - **Affirmation set.** These are the real operator messages of ≤80 characters that match an affirmation regex,
    paired with the last assistant text before each one.
    - 56 matched. 5 were copies of the same exchange in a second transcript, and 5 were not affirmations ("Okay so …
      ?" questions).
    - That leaves **46** (ids in `/tmp/r2-C4/data/aff_ids.json`).
    - Of the brief's seven quoted phrasings, three are in the 46: "If you say yes, I'll" (a005), "Should I build this
      set?" (a006) and "Reply "go" and I'll" (a016).
    - The other four are in the Stop corpus: "If you agree, I'll" (s002749, s011057, s011214, s017520); "Shall I
      build it" (s016132, rs13); "Say if you want it added" (s010388, rs09); "If you want me to drive it, say so"
      (s006415).
- **Which grep the hooks get.** In this agent's zsh, `grep` is a shell function that runs Claude Code's embedded
  ugrep. The hooks run under bash, where `grep` is `/usr/bin/grep` (BSD 2.6.0). That is measured: `type grep` in
  zsh, then `bash -c 'type grep'`. Every regex count here uses `/usr/bin/grep` explicitly.
- **Hook runs.**
  - Harness: `/tmp/r2-C4/bin/run.sh`. It runs a hook copy (`base/` = HEAD, `new/` = patched) once per message in a
    one-record synthetic transcript, under `env -i`.
  - Sandboxed env: `HOME`, `CLAUDE_CONFIG_DIR`, `ANTIDEF_STATE_DIR` and `ANTIDEF_IDL` all point at
    `/tmp/r2-C4/sbx`.
  - Stubs: `WRAP_LEDGER_BIN` is a stub that reports a clean ledger, `ANTIDEF_DECIDE_BIN` is a stub that only logs
    its argv, and `AGENT_IDENTITY_LIB` is a stub that says "not an assignee".
  - Settings: `CC_JEV_RETIRED=1`, `ANTIDEF_MAX=99`, and a fresh state directory per batch.
  - Live state was not touched: `grep -c 'sid-new-a0\|sid-base-a0' ~/.claude/autonomy/idl.jsonl` returned 0.

## 3. Baseline: what the lexicons catch today (measured)

| Lexicon | 46 pre-affirmation turns | 20,010 Stops (raw text match) |
|---|---|---|
| `CA_OFFER` (`completion-assert.sh:1280`) | **0** | 73 |
| `TELLS` (`anti-deference-nudge.sh:168`) | 2: a038 (`awaiting your`), a040 (`say go`) | 89 |

Commands: `/usr/bin/grep -ilE "$(cat re_caoffer.txt)" aff/*.txt` and the same with `re_tells.txt`, plus `-ril`
over `msgs/`. Both regexes were cut from the hook files with `sed -n 1280p` / `sed -n 168p`. The 0 of 42 in axis 07
reproduces as 0 of 46 here.

The two `TELLS` hits are both legitimate asks. a040 asks for $8.64 of paid image draws ("Say go and I'll fire
them"), and today's `deference` arm **already fires on it** (base run: `a040 fired deference`). a038 is a 70% value
decision, which the live hook lets stop through `genuine-ship-hold`. So the existing spelling list already carries a
false fire of the kind measured below.

Live arm volume (measured over the rotated IDL with `gzip -dc ~/.claude/autonomy/idl.jsonl.2026*.gz` plus the live
file, filtered to `anti-deference-nudge`): 15,947 records from 2026-09-28 to 2026-10-19. Fires by kind:

| Kind | Fires |
|---|---|
| opaque-identifier | 301 |
| deference | 24 |
| false-done | 19 |
| category-not-idea | 18 |
| pane-step-handback | 4 |
| peer-owner-deferral | 3 |

## 4. The candidate as built, and what it does

### 4.1 Design (structural class, not a spelling list)

The class is judged per SENTENCE, on the quote-stripped view the hook already uses for its pane and peer arms
(`PANE_STRIP_AWK`). That way a close that quotes an ask stays silent. It fires on any one of three predicates:

1. **Assent condition plus own act.** An operator-assent condition and a first-person future act in the same
   sentence.
   - The condition is `(if|once|when|whenever|as soon as|after) you … (agree|approve|confirm|ok|say|want|reply|answer|decide|give|green-light|sign off|like|prefer|accept|pick|choose|rule|are happy)`
     or `on your (yes|go|ok|word|signal|approval|nod|say-so|answer|confirmation)`.
   - The act is `I( will|'ll) <verb>`.
2. **Assent imperative.** `(reply|say|answer|respond|tell me|type) … (and|then|,) I'll`.
3. **Permission question.** A sentence that opens `(shall|should) I <verb>`.

It is a new `FIRE_KIND="conditional-ask"`, ordered after every existing kind so that no fire that exists today
changes kind (verified: re-running the 46 after the reorder, a016 stays `opaque-identifier`). Every existing
carve-out still applies: the `HARD_CORE`/`SOFTCALL` genuine exit, team-assignee, ship-hold, the latch and the cap.
The kill switch is `ANTIDEF_COND_ASK=off`. The prototype diff is `/tmp/r2-C4/c4.diff` (78 lines, +33), applied by
`/tmp/r2-C4/bin/patch.py`. Its regexes are in `/tmp/r2-C4/condask.vars`.

It is the brief's option (a), and it reuses the hook's existing strip and split code. No second copy of a matcher is
introduced.

### 4.2 Recall on the 46 pre-affirmation turns (measured run, hand-labelled)

Run: `bash bin/run.sh base aff aff.list aff1` vs `bash bin/run.sh new aff aff.list aff2`. Labels come from reading
each turn in full. In the label set, TP means the agent should have driven the work: it held the item above 90%, or
it was drivable with no operator gate. GEN means a legitimate operator ask. BORDER means the rules allow either
reading.

| Label | n | Widened arm fires on |
|---|---|---|
| TP (should have driven) | 10: a000 (93%, framed ⛔), a002 (92% "yours"), a005 (95%), a017 ("whenever you want it picked up"), a034, a039, a041 ("Committing and landing." then stopped), a043, a045, a046 (85% recommendation, no ask) | **2**: a005, a045 |
| BORDER (all items ≤90%, or a peer-requested pane move) | 3: a006 (78/82/70%), a018 (90/80%), a021 | 3 |
| GEN (spend, sign-in, filed ⛔/decision id, ≤90 handover with options, publish, value pick, permission dialog, mailbox) | 28 | **2**: a003 (asks the operator to approve a classifier-refused command), a032 (mailbox writes at 80%) |
| No ask (weekly-limit "continue", status) | 5 | 0 |

- **Recall** is 2 of 10 true defects. Only 5 of the 10 carry any permission-ask form. The rest are plain
  recommendations, or an announced-then-stopped step, which no offer lexicon can see.
- a000 and a029 carry the form, but they abstain at `genuine-ship-hold` (a SOFTCALL plus a ship verb, over a ledger
  with nothing unlanded). a002's ask spans two sentences.
- **Precision on this set** is 2 of 7 strictly (28.6%, CI 8.2–64.1%), or 5 of 7 counting the borderline turns.
- **Premise check.** 28 of the 46 asks that the operator answered "yes" to were legitimate questions. Axis 07 read the
  42 as "the round trip this costs", which overstates the defect population about 4x.

### 4.3 False fires: random 200 non-affirmed Stops (measured run, every fire hand-read)

Population: 19,749 Stops with text whose next operator message is not a short affirmation. The sample is
`random.seed(20261018)`, 200 Stops (`/tmp/r2-C4/sample200.list`).

| Result | Count |
|---|---|
| Unchanged (base = new) | 197: 166 `no-tell`, 25 `opaque-identifier`, 4 `done-ledger-clean`, 1 `pane-step-handback`, 1 `genuine-ship-hold` |
| **New `conditional-ask` fires** | **3** (1.5% of Stops) |

The three new fires:

- `s006578`, tpg: "Tell me if any page needs changes and I'll edit the source in brand-kit/ and rebuild." This is a
  review request on a PDF the operator is reading. **FP.**
- `s007257`, wt-cc-142226: "Once you've picked, I'll copy your choices into references/." The operator's image picks
  are the gate. **FP.**
- `s010973`, claude-infrastructure: "Good to close: yes … If you want codex-security added as lens G to
  /exhaust-improvements, say so and I'll do it — that's a reso-side edit and a design call …". This is the incident's
  own shape: a yes verdict with an offer. **BORDER.**

Precision in the sample is 0 of 3 strictly (CI 0–56%). The sample is too small to bound precision, which is why §4.4
exists.

### 4.4 Full-corpus volume and a 60-fire hand-read (measured)

- **Matches.** 503 of 20,010 Stops match the class text (measured: `bash bin/prefilter.sh sent/msgs`, which applies
  the hook's own regex to the hook's own sentence split).
- **Base vs new over those 503** (`run.sh base|new msgs cond_hits.list corp1`):

| Base → new | Stops |
|---|---|
| `no-tell` → **`conditional-ask`** | **243** |
| `no-tell` → **`genuine-blocker`** | **102** |
| `opaque-identifier` → `opaque-identifier` | 61 |
| `deference` → `deference` | 42 |
| `no-tell` → `genuine-ship-hold` | 35 |
| `genuine-blocker` → `genuine-blocker` | 7 |
| `done-ledger-clean` → **`conditional-ask`** | **5** |
| `genuine-ship-hold` → `genuine-ship-hold` | 4 |
| `pane-step-handback` → `pane-step-handback` | 3 |
| `done-ledger-clean` → `genuine-ship-hold` | 1 |

- **New blocking fires: 248, or 233 distinct (session, message) pairs across 118 sessions.** At most 199 remain after
  the per-session cap of 3; that is an upper bound, because the cap is shared with the other kinds. That is about 6.6
  a day, against about 1.1 a day for today's `deference` arm.
- **Side effect: class-B packets.** The 102 new `genuine-blocker` exits call `open_packet_B`. The `cc-decide` stub
  logged **86** packet opens for the new copy, against 4 for base on the same 503 messages (measured: `grep -c` on
  `sbx/fake-decide.log`). Shipped as built, the widening would file about 86 more class-B decision packets a month.
  One of them, a044, duplicates an already-filed ⛔ decision (`75ea14d27d0f`).
- **Precision.** I hand-read a seeded random 60 of the 233 (`random.seed(4242)`). For each I read the triggering
  sentence, about 1,100 characters of context, and the operator's next message. Labels are in
  `/tmp/r2-C4/data/labels60.tsv`.

| Label | n | What they were |
|---|---|---|
| TP | **4** | s002498 asks permission to *research* a 75% fix, and F2 says research is drivable; s007176 is a free token count it could run through `agent-secrets`; s010755 and s010756 are where the operator replied "Why do you need human in the loop to say what you already know what we should say?" |
| BORDER | 4 | a recommended session parked for machine load with a stated reason; "record your ruling"; a one-line live-email deploy; a firewalled-site rule change at 70% |
| FP | **52** | operator picks or taste (voice, headline, wordmark, images: 15); sign-in, login or billing (8); waiting on a real-world event such as a call ending, an email arriving or a text sent (8); filed ⛔ or ≤90 rulings (7); operator-only acts such as a signature, a permission setting or a dialog (6); paused after an operator interrupt, an explicit pause (3); spend (2); research-program relay turn (1); mailbox (1); not an ask ("safe to close whenever you like", 1) |

**Precision: 4/60 = 6.7% (Wilson 95% CI 2.6–15.9%) strict; 8/60 = 13.3% (6.9–24.2%) counting borderline.**

### 4.5 The D4 home (widened `CA_OFFER`, measured on the same 60)

`bin/d4eval.sh` applies D4's real conditions with the hook's own regexes (`ca.vars`, cut from
`completion-assert.sh:355,360,372,400,1281`):

1. the close-tell gate (`CLOSE`, or a `CA_SETTLED` line 1 that is not `CA_VERDICT_NO`);
2. `¬GENUINE`;
3. the widened offer on the quote-stripped `MSG_UNQ`;
4. `CA_WORKLEFT` on the lines that remain after the offer lines are removed (D4's half (b)).

Results:

- 18 of the 60 pass all four: 2 TP, 1 BORDER, 15 FP. That is 11.1% strict (CI 3.1–32.8%), or 16.7% counting the
  borderline one.
- On the 46 affirmed turns it fires on a000, a016, a029, a032, a040 and a045. Of those, 2 are TP (a000, a045); the
  rest are filed rulings, a ≤90% decision, mailbox writes and spend.
- **Half (b) does not discriminate.** A legitimate ask almost always lists what is waiting, so `CA_WORKLEFT` (list
  markers, "remaining", "still open") matches it as readily as a deferral.
- **The home is worse on timing.** D4 sits after the ledger read at `:573`, which is the path that the 5-second timeout
  kills on 18.1% of 30-day completion-assert runs (axis 07 §S0).

## 5. Narrowed variants (measured), and why none reaches 90%

| Variant | Distinct new fires / 30 d | Sampled precision (strict / with borderline) |
|---|---|---|
| Full class (§4) | 233 | 4/60 = 6.7% / 13.3% |
| Assent condition plus own act only | 84 | 1 TP among 26 sampled (comp: `bin/comp.sh`) |
| `reply/say/answer … and I'll` only | 175 | 3 TP among 43 sampled |
| `Shall/Should I <verb>` only (every one hand-read) | 11 (10 distinct texts) | 4/10 = 40% (CI 16.8–68.7%) / 7/10 = 70% (CI 39.7–89.2%) |
| Bare assent only (`if you agree/approve/say yes`, `on your yes/go`, `say "go" and I'll`, on raw text) | 24 | 0/6 strict, 1/6 with borderline; on the 46 it hits 11, of which 2 are TP |
| Full class AND a stated conviction >90% in the message | 4 | 0/2 (both s006087/s006096: the 92% belonged to another item; the ask was the 75% Pushover set-up, which needs operator tokens) |

The mechanism behind every row is the same. **The lexical form of a conditional ask does not carry the property
that decides whether asking was right.** That property is the content of the gate, and the agents' asks fall into
three groups:

- **Nothing more to say (TP):** "say so and I'll run the free count".
- **Waits on an operator-only input:** "say "sign in" and I'll …", "tell me when the call is over and I'll …",
  "once you pick, I'll …".
- **A handover the rules sanction:** "answer by id … I recommend yes, at 85%" (F2: ≤90 goes to the operator with the
  number).

Separating those three needs a veto list of operator-only gates: pick or choose or rank, sign-in or login or billing,
an event arriving, ⛔ or a decision id, a percentage of 90 or below, a dollar amount, a dialog or settings change. A
list of spellings is exactly what the denylist warnings forbid (`docs/research/exhaustive-drive-2026-09-08/SYNTHESIS.md`
§2D; memory `denylist-enumerates-spellings-not-the-class`). It also fails on the data in two ways:

- **The vetoes also remove the true positives.**
  - s010756, an operator-confirmed TP, opens "⛔ Still blocked on your work order".
  - s002498 states "My confidence is about 75%".
  - a000 is a ⛔-framed 93% item.
  - A ⛔ veto or a ≤90% veto silences them along with the false positives.
- **The quote strip that keeps the arm from firing on citations also erases the assent token.** `Say "go" and I'll`
  and `Say "sign in" and I'll` both become `Say   and I'll`, so the harmless and the credential cases cannot be told
  apart on the view the arm must read.

Mention-vs-use is a real constraint here, not a nicety. This report quotes a dozen asks, and so will any future post-mortem.

## 6. Remaining work

C4 is closed as a non-action. Polarity: do NOT add a conditional-permission class to `TELLS` or `CA_OFFER`;
conviction 88% that this is right. It rests on the 6.7% precision, the counter-example fire, the about 86 extra
class-B packets a month, and the D4 home measuring no better. What the measurement says the defect actually is, and
who could take it:

1. **A >90% recommendation handed over as a question** (a000 93%, a002 92%, a005 95%: 3 of the 10 affirmed-set
   defects).
   - The predicate is item-level: one list item, or one sentence, carries both "N% with N > 90" and an ask or a
     "yours" or ⛔ handover.
   - The message-level conjunction misattributes the number (§5, last row), so this needs a per-item parse of the
     numbered or bulleted structure the agents use. It is a new candidate; I have not designed it, and estimate
     about 50% that it can clear 90%, because n=3.
   - It is axis 07's F4. Note that F4's threshold must be >90, not ≥90 (axis 07 §S2).
2. **The existing `TELLS` already has a measured false fire of the same kind:** `say go` on a $8.64 paid fire (a040,
   base `fired deference`). Before anyone widens it, measure its own precision the way §4.4 does. That is not done
   here, to stay inside C4.
3. **Any text arm inherits the stale-MSG race** (axis 07 §S4.2). C1 (`round2/C1-last-assistant-message.md`) is the
   upstream fix, whatever happens to C4.
4. **If anyone revives C4 anyway, it must not route through `open_packet_B`.** As built, a conditional-ask-only
   message that also matches `HARD_CORE`/`SOFTCALL` takes the genuine exit and files a class-B packet (§4.4). The gate
   would have to be `has_tell || has_done || has_cat` for the packet, so the packet producer stays byte-identical.

## 7. Tests (bats on the copies)

C4 does not clear, so there is no diff to land and no new bats tests are proposed. As a sanity A/B of the prototype,
I ran the existing suite under the same sandboxed env on both copies (cc-bats passed the call through to bats-core
1.13.0). The commands differ only in the copy path:

```
env -i HOME=/tmp/r2-C4/sbx/bhome CLAUDE_CONFIG_DIR=/tmp/r2-C4/sbx/bcfg PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin LANG=en_US.UTF-8 TMPDIR=/tmp/r2-C4/sbx/ /opt/homebrew/bin/bats /tmp/r2-C4/{base,new}/tests/anti-deference-nudge.bats
```

`HOME` and `CLAUDE_CONFIG_DIR` are sandboxed, so `cc-decide` does not resolve and no packet is opened anywhere. The
copies also carry no `scripts/wrap-ledger.sh`. Tests that need either one therefore fail in both copies alike.

### 7.1 Results (measured)

`res/bats-base.tap` and `res/bats-new.tap` under `/tmp/r2-C4/`:

| Copy | Plan line | ok | not ok |
|---|---|---|---|
| base (HEAD) | `1..61` | 56 | 5 (#26, #30, #31, #33, #34) |
| new (C4 prototype) | `1..61` | 55 | 6 (the same five, plus **#11**) |

The five shared failures are the sandbox. #26, #30 and #31 need the live ledger, which the copies lack (no
`scripts/wrap-ledger.sh`). #33 and #34 need a resolvable `cc-decide`, which the sandboxed `HOME` removes on purpose.
They fail identically in both copies, so they say nothing about C4.

**The one difference is a regression the suite was written to prevent:**
`not ok 11 silent: 'should i download' does not match 'should i do'`. Its fixture is "Should I download the larger
dataset for this analysis?" (`tests/anti-deference-nudge.bats:175-178`), and the prototype's `Shall/Should I <verb>`
predicate fires on it.

So the hook's authors already decided that a generic "Should I X?" is not a tell. The suite header lists it among
the "substring traps" that must stay silent, and `TELLS` accepts only `should i (proceed|do|go)`. The question-form
variant that came out best in §5 (40% strict) is therefore also the one that breaks a pinned design decision. Fixing
it with a verb list would turn the class back into a spelling list.

## 8. Limits

- **The affirmation set is a rebuild.** Axis 07's `affirm.py` is gone. My regex is wider (46 against 42), and the
  hand labels are one reader's judgement. I recorded each label's reason in `labels60.tsv`, and in §4.2 for the 46.
- **The sandbox ledger is a stub reporting clean and nothing unlanded.** Any message whose outcome depends on
  `ship_hold ∧ drivable` (a SOFTCALL or PUSHHOLD phrase plus a ship verb) is therefore judged as a non-drivable hold
  (`genuine-ship-hold`). Live, a clean tree with own commits ahead would make some of them fire. That leans toward
  under-counting fires, which only strengthens the verdict.
- **The latch and cap are modelled per (transcript, message hash) with a cap of 3,** as an upper bound. Live, the cap
  is shared with `opaque-identifier`, which fired 301 times in 21 days. So a real session often has less than 3 left,
  and live recall would be lower still.
- **The 60-fire precision sample is random over distinct messages, not over sessions.** The bottle-photography and
  personal sessions contribute several each.
