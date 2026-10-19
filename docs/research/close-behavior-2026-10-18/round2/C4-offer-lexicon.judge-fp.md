# C4 judge, false-positive lens (conditional-permission class in `TELLS` / `CA_OFFER`)

Round 2, 2026-10-18. Adversarial judge for `C4-offer-lexicon.md`, through the false-positive and always-firing lens. The only
repo change I made is this file. I ran everything on the designer's copies (`/tmp/r2-C4/base` = HEAD and `/tmp/r2-C4/new` =
prototype). I used my own copy of the harness, which writes to its own sandbox and its own stub log, so the designer's
evidence files stay untouched. My scripts, labels and outputs are under `/tmp/r2-C4/judge-fp/`. `base/hooks/anti-deference-nudge.sh`
is byte-identical to HEAD `72a18b575` (measured: `diff -q`). Load average was 383-399 during this work (measured: `uptime`). Every
number below is labelled measured (with the command) or estimated (with the method).

**Verdict: refuted as a fix. Conviction that any form of C4 should land: 3%.** I confirm the designer's non-action
conclusion and its headline counts. Through this lens it is worse than the report says. The arm does not just have low
precision: it breaks constraints 1 and 2 **by construction**, and I measured instances of each in the corpus:

- It blocks **⛔ operator decisions** whenever their wording misses `HARD_CORE`. 14 of the 20 ⛔-bearing new fires are
  genuine ≤90 or operator-ruled decisions.
- It blocks **stated parks and waits**, including a fired session parked on its lead's GO.
- It blocks **honest "Good to close: yes, nothing of mine is open" closes** that carry an optional offer.
- Its "reply/say/answer … I'll" predicate also matches **the noun "answer"/"reply" and third-party subjects** ("the lead's
  reply restarts me and I'll …").

My confidence in the non-action conclusion itself is about 92% (estimated). The designer said 88%. The extra evidence
below pushes it up, not down.

## 1. What I re-ran (reproduced)

| Claim | My re-run | Result |
|---|---|---|
| 503 class-matching Stops | `bash /tmp/r2-C4/bin/prefilter.sh /tmp/r2-C4/sent/msgs` | **503, identical id set** (`diff` empty) |
| base → new transitions on the 503 | re-tallied `res/corp-{base,new}.tsv` | 243 + 5 → `conditional-ask`; 102 → `genuine-blocker` (matches §4.4) |
| Harness reproduces fires | my `judge-fp/bin/run.sh` on a fresh 30 of the 233 | **30/30** `no-tell` → `fired/conditional-ask` |
| ~86 extra class-B packets | re-ran the 102 `no-tell → genuine-blocker` messages through both copies | 101/102 reproduce (1 now `genuine-ship-hold`); **81 packet opens for new, 0 for base**, against the designer's net +82; **74 of the 81 carry `--conviction 0`** (measured: `grep -c`/`grep -oE` on `judge-fp/sbx/fake-decide.log`) |
| Counter-example blocked | `run.sh new` on `s002749` | `fired/conditional-ask` on "If you agree, I'll start with step 1 … for join.reso.gl" |
| D4 home 18/60 | `bash /tmp/r2-C4/bin/d4eval.sh msgs hand60.ids` | **18**, byte-identical to `res/d4-hand60.tsv` |
| Pinned test #11 breaks | `bats -f "should i download\|say going\|want to. does not"` on both copies, sandboxed `HOME`/`CLAUDE_CONFIG_DIR` | base `1..3` ok 3; new `1..3` ok 2, **`not ok 2 silent: 'should i download' …`** (line 177) |

I did not re-run the full 20,010-Stop extraction or the 46-turn affirmation labelling. I used the designer's extracted
corpus (`data/stops.jsonl`, `sent/msgs/`).

## 2. Independent precision: a fresh 30 of the 233 (measured run, my labels)

`python3 -I /tmp/r2-C4/judge-fp/sample.py` (`random.seed(20261019)`) draws 30 of the 173 distinct new fires that the
designer did not hand-read. I read each one: the trigger sentence, the full message (head and tail for long ones) and the
operator's next message. The labels and a reason for each are in `/tmp/r2-C4/judge-fp/labels30.tsv`.

| Label | n | Cases |
|---|---|---|
| TP | **2** | s003148 (item stated at 95%, "If you say yes, I'll send it"); s015679 (one-line fix it called "the real cause", "Should I make the `--` fix now?") |
| BORDER | 3 | s007193 (a *peer* asked for a recycle; the agent rightly would not treat a peer message as authority); s007624 and s010973 (write-free Q&A with an optional offer) |
| FP | 25 | filed or ⛔ decisions (s002863, s011061, s011879, s017814, s010299); sign-in or billing (s004899, s005662, s008547, s008582, s013878); operator picks or taste (s013684, s015732, s015736, s015740); stated waits with a watcher armed (s006733); a classifier-refused step (s008794); the operator's own email or QA (s006899, s017487); external info (s006884); clarifying an ambiguous "x" (s001920); others in the TSV |

- **Strict: 2/30 = 6.7%** (Wilson 95% CI 1.8–21.3%). **With borderline: 5/30 = 16.7%** (7.3–33.6%).
- **Pooled with the designer's 60:** 6/90 = **6.7%** (3.1–13.8%) strict, and 13/90 = 14.4% (8.6–23.2%) with borderline.
- My read, done independently on different messages, lands on the same number. "A second reader would move the labels"
  is not a live objection.

## 3. The constraint hunt: which legitimate stops it blocks

### 3.1 ⛔ operator decisions (constraint 2): blocked by construction

Measured by tagging the 233 with `python3 -I /tmp/r2-C4/judge-fp/classify.py`: **20 of the 233 new fires (8.6%) carry
`⛔`**, and I hand-read all 20 (`show.py stop_sign`).

- **14 are genuine operator decisions.** Examples:
  - s011061 and s011218: "⛔ Blocked: should the archive … I recommend that, at 85% conviction. On your answer, I'll hand
    the archive build to a separate session".
  - s001935: a 70% spend.
  - s013463: overriding the operator's own rule.
  - s018309 and s018325: overriding the operator's 2026-10-01 ruling.
  - s000384, s002573, s004910, s005884, s006087, s014710, s015044 and s019064 are the same kind.
- **6 are TP-like.** Five are copies of one ask in one session (s010755–s010759, operator-confirmed). The sixth is s015962,
  a 95% item framed as ⛔. The cap of 3 per session limits the five copies to 3 fires.

The mechanism is structural. The only ⛔ exit is `HARD_CORE`/`SOFTCALL`, and those match vocabulary, not the ⛔ rung.
"On your answer, I'll …" is the natural way to state what happens after a ruling, so every ⛔ that does not also say
"your call", "which do you prefer", "requires approval" and so on now fires. Probe `p09` confirms it (measured, below):
"⛔ Blocked: should X? I recommend yes, at 85% conviction. On your answer, I'll hand the build to a separate session" is
silent on base and **fired** on new.

The block text then tells the agent to "file it as the decision it is (cc-decide open --class C …)". For an
already-filed decision (s002863 has eight ids; s011879 cites `58b53be8dd96`), that pushes the agent toward duplicate filings.
This is the prose twin of the duplicate class-B packet the designer found for a044.

### 3.2 Stated parks and waits (constraint 2)

All measured with `run.sh new` (fires) and hand-read:

- **s011410:** "📦 Done, but only on a branch … **parked on purpose until the lead says GO** … under their ruled
  decision. Once they reply GO, I'll land …". This is a fired session obeying its lead. **Fires.**
- **s006751:** "Still waiting for your answer … I'm now waiting up to about 4 hours, and I'll act as soon as your answer
  comes through." **Fires.**
- **s006733:** "Waiting on the operator's answer to the storyboard … watcher … already running … On a yes: I'll start the
  motion-test session". **Fires.**
- **Probe `p10`:** "Wave 2 is parked until the 24-hour soak finishes on 2026-10-19 … When you confirm the soak is green,
  I'll land wave 2." Silent on base, **fired** on new.

### 3.3 Fired-peer and lead waits: the "reply" predicate has no subject

`CONDASK_REPLY` is meant to catch the imperative "reply go and I'll". It has no subject check, so it also matches the noun
and third parties. `python3 -I /tmp/r2-C4/judge-fp/replynoun.py` finds **7 of the 233 fires (3.0%) that match only this way**:

- s019064: "A wake-up is armed, so **the lead's reply** restarts me and I'll carry out whichever option it picks". A
  research-program member waiting on its lead.
- s011395: "If **the answer** is to hold, I'll leave the branch for them to collect".
- s011410: "Once **they reply** GO, I'll land …".
- s010266: "**The answer** to your question is ready and I'll post it as soon as the land confirms". Not an ask at all.

`agent_is_assignee` (`hooks/lib/agent-identity.sh`) recognises only Agent-Teams teammates by their three CLI flags, not
handoff-fired sessions. So these would fire live too, not just in the sandbox (deduced from reading the lib).

Probes `p11` and `p12` (a fired peer that will ping back) stay **silent**: a third-person "it will ping" carries no assent
token. The peer-ping exposure therefore runs through the noun/third-party "reply/answer", not through peer pings in general.

### 3.4 Honest closes with nothing drivable (constraint 1)

**11 of the 233 fires carry "Good to close: yes"** (measured: `classify.py`), and I read all 11 (`show.py gtc_yes`). Two are
honest closes with nothing open and a courtesy offer:

- s009983: "Good to close: **yes** … custody clean … Safe to close whenever you like — it's your pane, so I'll leave
  retiring it to you."
- s019199: "Good to close: yes. Nothing of mine is open … If you want changes to v2 now, I'll start a fresh session on
  it."

Both **fire** (measured: `run.sh new`). Probe `p14` ("Good to close: yes. Nothing drivable remains … If you want a follow-up
later, say so and I'll pick it up.") also **fires**. The arm consults no drivability signal on this path; the ledger is
read only for ship-hold. So it cannot be "silent when nothing drivable remains".

In fairness, one of the 11 is the incident's own shape, and the arm catches it. s005672: "Good to close: yes for this
session, no to "100/100 implementation" … Say "build it" and I'll write the build plan and start the first wave." That is
the arm's best real case, and it is outside both random samples.

### 3.5 Quoted mentions: safe only when the quote is marked

Probes (measured: `bash judge-fp/bin/run.sh {base,new} probes probes.list jp`; texts in `judge-fp/mkprobes.py`):

| Probe | base | new |
|---|---|---|
| p01 backtick mention, p02 double quotes, p03 `>` blockquote, p04 fenced block | silent | **silent** |
| p05 unquoted mention: "The shape it names is a close that ends with: If you agree, I'll start with step 1." | silent | **fired** |
| p06 italic mention: `*If you agree, I'll start with step 1*` | silent | **fired** |
| p15 a draft written *for* the operator: "Hi Aman, … If you agree, I'll send the contract tomorrow" | silent | **fired** |
| p16 table row: `\| If you approve \| I'll deploy the fix \|` | silent | **fired** |
| p13 write-free Q&A: "The answer is 42 … Should I write this up as a doc?" | silent | **fired** |
| p18 "Say "sign in" and I'll run the login flow." / p19 "$2.88 … Reply go and I'll fire them." | silent | **fired** |
| p20 the pinned fixture "Should I download the larger dataset …?" | silent | **fired** |
| p17 honest done with no ask | silent | silent |

The quote strip protects post-mortems only when they mark quotes. Italic, a colon-introduced paraphrase, a table cell
or an operator-facing draft all fire. Six of the 233 fires are messages that discuss the hook or its tells (measured:
`grep -liE 'anti-deference|TELLS|CA_OFFER|lexicon|…'`). That is small today, but this study writes such messages by the
dozen.

### 3.6 Write-free sessions and turns

- **Sessions:** only **2 of the 233** fires come from sessions with no file-write tool call at all (measured: `classify.py`;
  the proxy counts Write, Edit, MultiEdit and NotebookEdit, plus Bash commits, pushes and redirections). So write-free
  *sessions* are not a material exposure here.
- **Turns:** **140 of the 233 (60.1%)** fire in a turn with no write. That is expected for asks and does not separate true
  from false.

## 4. Always-firing and side effects

- **Volume.**
  - The 233 distinct new blocks in 30 days (≤199 after the cap) compare with 24 `deference` fires in 21 days. These come
    from the designer's measurement, which I reproduced in §1.
  - My independent sample says about **93% of those blocks would land on a legitimate stop** (estimated: 1 − 2/30
    strict, applied to the 233).
  - The arm does not fire on every Stop. Among the designer's 200 random non-affirmed Stops it fired on 1.5%. But at that
    precision, a model would learn to route around it, which is the failure the hook header warns about.
- **Packets.**
  - Shipped as built, the `has_cond` gate lets 101 previously silent messages reach the `HARD_CORE` genuine exit.
  - That opens **81 push-notified class-B packets** where base opens none (measured, §1).
  - 74 of those 81 have no stated conviction (`--conviction 0`).
  - Each one is a notification to the operator about a message that today produces nothing.

## 5. Where I extend the designer

1. **Constraint 2 is violated outright, not just made more expensive.** The report counts ⛔ and filed cases inside its
   FP bucket ("filed ⛔ or ≤90 rulings: 7"). It does not state that the arm blocks ⛔ decisions by construction. §3.1 shows
   14 of 20 ⛔ fires are legitimate.
2. **The reply predicate is mis-specified**: it matches nouns and third parties (§3.3). The report's §5 lists
   `reply/say/answer … and I'll only` as 175 fires and 3 TP in 43. Part of that FP mass comes from this, and it is the
   route by which fired-session and lead waits get blocked.
3. **Constraint 1 is violated on honest "yes" closes** (§3.4). The report labels s009983 "not an ask", but the deeper point
   is that the arm has no drivability input at all.
4. **The mention-vs-use defence holds only for marked quotes** (§3.5).
5. **Packet side effect reproduced** (81 against the designer's net +82), with the extra detail that 74 of 81 carry no
   conviction.

Nothing I found argues for C4. The one real positive the designer did not cite is s005672, the incident's own shape. A
non-lexical detector should use it as a test case. It does not rescue a 6.7%-precision arm.

## 6. Limits

- Labels are one reader's judgement each. Two readers on disjoint samples agree at 6.7% strict, but I did not re-label the
  designer's 60.
- The sandbox ledger stub reports clean with nothing unlanded, and the identity stub reports "not an assignee". Live, some
  ship-hold messages would fire (more FP), and real Agent-Teams teammates would abstain. Neither changes the verdict.
- `classify.py`'s write proxy and feature regexes are heuristics. The ⛔, park and honest-close counts are exact for the
  token match, and every case cited above was hand-read.
- `/tmp/r2-C4/` is the only copy of the method and erodes on reboot, as axis 07's workspace did.
