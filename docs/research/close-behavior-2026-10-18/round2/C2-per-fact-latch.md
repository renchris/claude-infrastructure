# C2: a per-fact latch for completion-assert's `assert` class (cap starvation)

Round 2, 2026-10-18 (written 2026-10-19T01:00Z). Candidate from axis 02 skeptic, "An unconsidered
alternative" and "Missed by the axis" item 4. Read-only in the repo. Every prototype, data extract
and test run is on copies under `/tmp/r2-C2/`. Every number is labelled measured (with the command)
or estimated (with the method).

Status: complete, 2026-10-18 (local). Repo untouched: every edit below is on `/tmp/r2-C2/` copies.

## 0. Setup facts

- The self-repro file the brief names, `/tmp/close-behavior-lead/self-repro-idl.txt`, **does not exist**
  (measured: `ls -la /tmp/close-behavior-lead/` ⇒ `No such file or directory`). The 16:34 reboot cleared
  `/private/tmp`. Everything below is re-derived from the IDL itself.
- Clock (measured, `date -u`): `2026-10-19T01:00:19Z`. The 14-day window used throughout is
  `2026-10-05T01:00:00Z → 2026-10-19T01:00:00Z`.
- Data (measured): completion-assert records extracted read-only from `~/.claude/autonomy/idl.jsonl` and
  the eight `idl.jsonl.2026*.gz` rotations into `/tmp/r2-C2/data/` (`gzip -dc … | grep '"hook":"completion-assert"'`).
  Retained span 2026-09-28T17:20Z → 2026-10-19T00:58Z, so the 14-day window is fully covered.
  In-window: 10,089 records, 466 `fired`, 9,623 `abstained`, of which 492 `capped:3>=3` and 29
  `capped:shape:2>=2` (measured: `jq` tally over `ca14.jsonl`).

## 1. Answer first

1. **The starvation is real and common, and a per-fact latch removes it cleanly.** Over 14 days, 70
   sessions spent 3 or more fact-bearing `assert` fires. In 45 of them, at least 3 fires were on one
   byte-identical facts string, and in 56 on one number-normalized string. Overall, 144 of 331
   fact-bearing fires (43.5%) repeated a string already convicted in the same session (measured, §2.1).
   58% of those repeats came within 60 s of the previous fire on the same fact (median 35 s). That is
   the block → "not done, still waiting" reply → block loop.
2. **Repeating a conviction on an unchanged fact almost never helps.** Over 14 days there were 27
   repeat fires on the same unlanded fact at the same HEAD sha, with the sha recovered from
   session-continue's own `ship-floor-latched` record on the same Stop. I read every close they
   convicted. Each one says the commits are not landed yet and gives the reason: the gate is running,
   the land is queued on the shared lock, it is parked under a brief or ruling, or auto mode refused
   the land. **One** of the 27 plausibly caused a ship: the incident's own fire #2, which led the
   agent to land from a separate worktree. For fire #3, 0 of 11 caused a ship. One of the 11 was followed
   by a ship call, and that was the incident's land, already in flight (§3: measured counts, hand-read cause).
   So the latch allows **one** fire per (fact, HEAD).
3. **What the latch would have recovered over 14 days.** Replaying the observed sequence with
   key = (normalized facts, HEAD sha), K=1: assert-class fires go from 345 to 265 (−23%). 43 of the
   492 `capped:3>=3` suppressions would have fired, in 32 sessions. 123 repeat fires go silent
   (estimated: counterfactual replay, §2.2). By arm, the recovered fires are ledger 🔧 19, ledger ⛔ 10,
   ledger 📦 6, ledger+handoff ⛔ 3, ledger+handoff 🔧 2, handoff ✅ 2 (the incident close is one) and
   hedge 📦 1. The design as diffed adds the ⛔ guard from item 4, and with it the figures are 345 → 256
   blocks (−26%), with 41 suppressions recovered in 31 sessions (§7).
4. **The freed budget mostly goes to more false positives, so C2 alone does not satisfy constraint
   (2).** Most recovered fires convict closes that already say "not done":
   - 12 have a ❌/"no" verdict, 4 lead with ⛔, and 14 are worded as a wait or park.
   - The one-fact pattern underneath is that **27 actual fires in 14 days convicted a close whose rung
     line already carried ⛔** with "BLOCKED ON YOU … that IS your rung" (measured, §2.3). The hook's
     own comment says that case "abstains at the close-tell gate". It does not, because the
     close-tell `CLOSE` regex matches "landed", "remains" or ✅ anywhere in the body.

   C2 without a guard would keep 23 of those 27, and 8 of the 23 are newly recovered. So the design
   ships with one companion guard on the existing ⛔ term: the term is answered when the close's
   rung line (D6's rule, line 1, or lines 1-2 under a verdict line) carries ⛔. That guard drops
   all 27.
5. **For the incident, C2 is necessary but not sufficient.** With the latch, fires 2 and 3 latch, and the
   14:27:50Z close reaches the arms with 2 `assert` slots left. The arm that then fires is D1
   `handoff`, aimed at the 70% settings.json step, not at the §5 waves (axis 02 RC5; replay §5.4).
   C2 makes a future follow-on arm reachable. It does not make the incident close drive §5.
6. **Conviction (honest, post-measurement): 82%** that C2 plus the ⛔ guard is a net-positive change
   that meets constraints 1-6 as far as §8 claims. The support, all measured:
   - noise reduction and repeat uselessness;
   - one mechanism that copies the ship floor's own per-HEAD discipline;
   - an incident replay that turns `capped:3>=3` into a live fire;
   - `completion-assert.bats` green: 181 unchanged + 17 new or rewritten = 198;
   - `-forks` 8/8 (+3 processes, budget margin 53 ≥ 40) and `-assignee-shared-cwd` 9/9;
   - `-durations` 6/8, with its two wall-clock reds reproduced on the unmodified tree at the same load (§6).

   It is **below 90%** for two measured reasons:
   - About 90% of the 41 fires the latch recovers from the cap are false positives on wait, park or
     status closes. A hand-read of all 41 found 3-4 true positives (§7). C2 stops the repeats, but it
     cannot stop the ledger arm's *first* conviction of a stated park.
   - The incident close would still have drawn the wrong demand.

   **It does not clear the 90% bar, and as a fix for the incident it is necessary but not sufficient.**
   The ⛔ guard on its own sits higher, at 95%. A hand-read of the 27 closes it exonerates found every
   one a genuine "⛔ Blocked — need your call" close (§2.3).

## 2. Measurements on the IDL (14 days, read-only)

All scripts are in `/tmp/r2-C2/bin/`. Inputs are in `/tmp/r2-C2/data/`: `ca14.jsonl` (completion-assert, 14 days),
`sc14.jsonl` (session-continue, same window) and `events.jsonl` (each assert-class `fired` or
`capped:3>=3` record, annotated with the first two lines of the close it judged). The close lines come from
the session transcript under `~/.claude*/projects/*/<sid>.jsonl*`, read-only (`annotate.py`). All 837 events
matched a transcript and a close text (measured).

### 2.1 How often one fact spends the budget (measured)

`jq … ca14.jsonl | python3 -I -c …` (inline in the run log) over every `fired`, `class:"assert"` record
with a non-empty `facts`:

| quantity | value |
|---|---|
| sessions with a fact-bearing assert fire | 146 |
| sessions with ≥3 such fires | 70 |
| … of which ≥3 on one byte-identical facts string | 45 |
| … of which ≥3 on one number-normalized string (`[0-9]+`→`N`) | 56 |
| fact-bearing fires | 331 |
| fires repeating an identical string already convicted in the session | 144 (43.5%) |
| fires repeating a normalized string | 165 (49.8%) |
| gap between a repeat and the previous fire on that normalized fact | p10 8 s · p25 12 s · median 35 s · p75 1,637 s · p90 9,031 s; ≤60 s: 96 (58%) |

This re-measures the axis-02 skeptic's figure (19 of 30 sessions, 10-16..10-18) over the full 14 days.
It is the same shape and larger. The ≤60 s mass is the block → rewritten-reply → block loop. The
message-hash latch cannot see it, because each reply hashes fresh.

The incident session, read directly (`jq 'select(.sid|startswith("5759497b"))'` over completion-assert and
session-continue):

| ts (Z) | completion-assert | session-continue |
|---|---|---|
| 13:18:18 | — | `fired ship-floor` (📦; new sha) |
| 13:18:34 | `fired` ledger 1/3, "1 commit(s) YOU wrote are committed-but-unlanded" | `ship-floor-latched` sha 5094a913e |
| 13:19:02 | `fired` ledger 2/3, same facts | `ship-floor-latched` sha 5094a913e |
| 13:19:40 | `fired` ledger 3/3, same facts | `ship-floor-latched` sha 5094a913e |
| 14:27:50 | `abstained capped:3>=3`, `suppressed_arm:"handoff"`, rung ✅ | (14:19:10 `ship-floor-budget`) |

So the two hooks disagreed about the same fact on the same sha. The ship floor said it once and stayed
silent. completion-assert said it three times in 66 s, and the closes it convicted read: "I'm holding the
land on purpose…", "This isn't done, and I'm not claiming it is…" and "…is landing from a separate worktree".

**The brief's live-session self-repro is a different shape.** The repro file is gone (§0), so I read
this session's own records (sid `ce527c7b`, `ca.live.jsonl`). Its three assert fires (20:47:54,
21:28:12, 21:30:13Z) were on **three different facts at two different HEADs**: 2 commits unlanded at
3db370e48, then dirty + 3 unlanded, then 4 unlanded at f12dd4b12. A per-(fact, HEAD) latch would not
have saved a slot there. A per-session normalized-fact key would have collapsed #1 and #3 (§2.2,
key `sess`). That is spend across new commits, the territory the ship floor already re-arms on.

### 2.2 Counterfactual replay of the cap (estimated)

Method (`sim2.py`): per session, segmented where the live `count` resets (a new latch key, e.g. a CFG move),
replay every assert-class evaluation that reached the cap stage (`fired` + `capped:3>=3`) in time order. A
ledger-only evaluation whose key has already fired K times is `fact-latched` (silent, no slot). Any other
evaluation fires if fewer than 3 slots are spent, and is capped otherwise. This is a replay of the
observed sequence. It cannot model how a recovered or suppressed block would have changed what the
model said next, so every number here is an estimate.

Keys: `sess` = normalized facts per session; `exact` = byte-identical facts; `head` = normalized facts + the
HEAD sha session-continue logged on the same Stop (`ship-floor-latched.sha`, ±5 s; 63 of 115 unlanded
fires carry one), falling back to `exact` when no sha was logged.

| key, K | assert fires (actual 345) | capped → would fire | repeat fires → silent | sessions with a recovered fire |
|---|---|---|---|---|
| sess, 1 | 228 | 31 | 148 | 24 |
| exact, 1 | 257 | 41 | 129 | 31 |
| **head, 1 (the design)** | **265** | **43** | **123** | **32** |
| head, 2 | 335 | 31 | 41 | 25 |

What the 43 recovered evaluations (head, K=1) would have suppressed, by the arm the record names:

| suppressed arm · rung | n |
|---|---|
| ledger · 🔧 (custody, dirty) | 19 |
| ledger · ⛔ (BLOCKED ON YOU) | 10 |
| ledger · 📦 (unlanded) | 6 |
| ledger+handoff · ⛔ | 3 |
| ledger+handoff · 🔧 | 2 |
| handoff · ✅ (one is the incident close, 5759497b 14:27:50Z) | 2 |
| hedge · 📦 | 1 |

The shape of the close line 1 for those 43 (classified from the transcript): prose 17, ❌/"no" verdict 12,
other rung glyph leading (📦 🔧 📤 📬) 8, ⛔-led 4, ✅/"yes"-led 2. 14 are worded as a wait or park
(`on purpose|deliberate|waiting|queued|in flight|still running|watcher|land lock|not landed yet|park`).

**Hand-read precision of the recovered set** (31 rows of the `sess` replay, close lines printed by
`closeat.py`, read one by one): about 4 to 6 are true positives:
- 2328e32b 09:46, "✅ Good to close: yes … follow-on: the Panda decision below" over an open decision;
- 2328e32b 07:03, a done-reading close over an open decision;
- 36b81fea `hedge`;
- the incident close (a real defect, though the wrong arm fires; §5.4).

The rest are status or wait closes, or ⛔-led closes, for example:
- `⛔ Blocked — 2 decisions need your call …` (7913752f, c5cd1b06, e131c8d2, 9fd1dbab, 4f7d7e9e, 407a191d, 69778275, 094a1ced);
- `❌ Good to close: no. Three kit fixes are still running … the watcher is armed` (6207f5b4);
- `📦 Waves A, B and D are still running; I'm waiting …` (5a6b8a40);
- a time-zone answer (46a0fdc8).

**Precision of the ledger arm as it stands** (all 345 actual fires, same classifier):
- 222 (64%) convicted a close worded as a wait or park;
- 97 (28%) convicted a close with a ❌/"no" verdict;
- 9 convicted a ⛔-led close.

The cap is currently working as the arm's false-positive limiter. That is why freeing budget
recovers mostly false positives.

### 2.3 The ⛔ term convicts closes that already state ⛔ (measured)

Count of actual fires whose facts carry `BLOCKED ON YOU` and whose rung line already contains ⛔ (`sim2.py
… -dump` + the inline `blk_on_glyph` count). The rung line is line 1, or lines 1-2 under a verdict line,
which is D6's rule at `completion-assert.sh:1476-1484`:

| | n |
|---|---|
| actual fires, 14 days | **27** |
| under C2 without a guard | 23 (8 of them newly recovered from the cap) |
| under C2 + the stated-⛔ guard | 0 |

The block they received says "your close reads as done/complete … BLOCKED ON YOU … that IS your rung".
It went to closes such as `⛔ Blocked, need your call (decision b18c74a4f8e1) …` (e131c8d2). That is the
"never block a genuine operator decision" constraint, broken by the existing term. The term's comment
(`:1126-1129`) says such a close "abstains at the close-tell gate above". It does not when the body carries any
`CLOSE` token, and `CLOSE` includes `landed`, `remains`, `✅` and `📦` anywhere in the message (`:355`).
The capped tail is larger still: 229 of the 492 `capped:3>=3` records judged a ⛔-led close. 211 of them
come from one session (c1296add) that re-closed `⛔ Still not landed … Auto mode refused my land of commit
0b7421363 …` 211 times from 14:09 to 16:17Z, with the land operator-only. The cap silenced it, and under C2 the latch silences it as well (all 211 become `fact-latched`).

## 3. Is repeating a conviction ever useful? (measured, then hand-read)

Method (`ttship.py`): take every actual ledger fire on the unlanded fact (115 in 14 days). Index it by its
repeat number on (session, normalized facts), and separately on (session, normalized facts, HEAD sha) where
session-continue logged the sha on the same Stop. Then look in the transcript for the next ship-ish tool call
(`ship-land`, `/ship`, `git push`, `deploy-live`) and ask whether it came before the session's next Stop.
That is the window in which the call could be a response to this block.

| repeat on (session, fact) | fires | ship call before next Stop | any later ship call | median s to next ship call |
|---|---|---|---|---|
| #1 | 68 | 20 (29%) | 50 | 857 |
| #2 | 30 | 6 (20%) | 23 | 806 |
| #3 | 17 | 2 (12%) | 13 | 2,980 |

| repeat on (session, fact, **same HEAD sha**), sha known | fires | ship call before next Stop |
|---|---|---|
| #1 | 36 | 10 |
| #2 | 16 | 5 |
| #3 | 11 | 1 |

"Before the next Stop" is correlation, not cause, so I read all 27 same-HEAD repeat fires (#2 and #3,
`ttship.py -v`, close line 1 plus the transcript around each ship call). **Every one convicted a close that
already said why the land was not done**:

| what the convicted close said | sessions |
|---|---|
| the gate is still running | 8850897d, 080db1b6 (×2), a3cd5943 (×2), 63125ce9, a6fe7087 |
| the land is queued on the shared lock / in flight | 6237b592 (×2), 6db28068 (×2), 85904bdf, f6e47f22 (×2) |
| a stated park under a brief or ruling | e1a70544 (×2, the operator's piggyback ruling), 3776f14b (×2), c577dd04 (×2), 1a813e5f (waiting on the lead's GO) |
| auto mode refused the land (operator-only) | 5e5e1a38 (×2), c1296add (×2) |
| the incident | 5759497b (×2) |

The five "ship before next Stop" #2 cases, read in the transcript:
- 8850897d, 63125ce9, 85904bdf: the planned land after the gate finished.
- 1a813e5f: "The lead's GO … arrived. Landing now" at 19:17:18. The GO came from the lead, not from the block (`window.py`).
- 5759497b: after fire #2 the agent read `ship.md`, made a separate worktree and started `ship-land.sh` 31 s later.

So **one of 27** same-HEAD repeats plausibly caused a ship, and even that one only moved a land the agent had
already promised ("I'll ship once, after the workflow finishes", 13:18:32). The ship floor would have
re-armed on the next commit anyway (it fired again at 13:20:47 on the new sha 87a5169a). The 7 new-HEAD
repeats (k=2 at ksha=1) show the same pattern: 0 of 7 were followed by a ship before the next Stop, and all
are "gate running / watcher armed / waiting".

Repeats on the 5e5e1a38 and c1296add rows are worse than useless. Auto mode had refused the land, so a
re-conviction pushes the agent to retry an operator-gated action. That is the constraint-(2) failure.

**Verdict: K=1.** One conviction per (fact, HEAD). A second fire on an unchanged fact has a measured yield
of 1/27 and a measured cost of 26 blocks on stated parks or in-flight lands.

## 4. Interaction with session-continue's ship floor

- **Same unit, now the same rule.** The ship floor already fires once per HEAD sha (≤ `CC_SHIP_FLOOR_MAX`=2
  per session, `session-continue.sh:1250-1261`). Its sidecar is `<sid> <sha> <count>`, and its text tells the
  model "this floor is already spent for the current commit and re-fires at most once per NEW commit". C2 gives
  completion-assert's ledger arm the same once-per-(fact, HEAD) discipline. Over 14 days the ship floor wrote
  1,367 `ship-floor-latched` records against 221 fires (measured: `jq -r .reason sc14.jsonl | sort | uniq -c`).
  It already treats "same sha, said once" as the normal state.
- **No new double-block.** C2 only removes completion-assert fires. The double-block yield is untouched: when
  session-continue blocks on this Stop, `contra=0`, `FKEY` stays empty, nothing is recorded, and it still runs
  first (`:1137-1192`). After C2, a 📦 fact is nagged at most twice per sha: the ship floor on the idle Stop,
  and completion-assert once on the first done-reading close. Today it is the floor plus up to 3.
- **The HEAD is read the way the floor reads it** (`git -C "$CWD" rev-parse HEAD`, the same read as
  `session-continue.sh:1249`'s `cd "$cwd" && git rev-parse HEAD`), and only on the contradiction path. 79% of Stops abstain `no-close-tell` before the
  ledger, and those pay nothing. A non-repo cwd keys on `?`, which is what the ⛔ and stub-ledger fixtures run in.
- **What C2 cannot do:** the ship floor's budget (2 per session) and this hook's budget (3) stay separate. A
  session that commits again on a new HEAD gets a fresh conviction from both. That is intended: a new commit is
  a new fact. It is also why the live self-repro (§2.1, three HEADs) still caps.

### 4.1 A measured extension, not in the diff: let the ship floor's own latch count as the conviction (C2-SF)

Every one of the 63 unlanded fires whose HEAD sha I could recover got that sha from a `ship-floor-latched`
record on the same Stop. That means **the ship floor had already fired on that sha in that session**. 36 of them
were completion-assert's *first* fire on the sha, which C2 keeps. Their close line 1 (`ttship.py -v`, 36 rows):
31 match the park/wait wording above. The other 5 are:
- "bats run … still going" (a wait);
- "📬 … noted" (an ack);
- "❌ … auto-mode safety …" (operator-only);
- "No speedup is available: the box is packed …" (a wait);
- "WP-1, WP-5, WP-6 and WP-7 are all green on the wave branch" (57fab48d). This one shipped 23 s later, so it
  is the one plausible true positive.

So after the floor's "/ship it, or say the park is deliberate", completion-assert's first unlanded conviction on
the same sha is about 1 true positive in 36 (estimated: hand-read of line 1).

A variant would seed the per-fact latch from the floor's sidecar. When the facts are unlanded-only and
`$(continue_sentinel_for "$CWD").ship` reads `<SID> <HEAD> <n>`, abstain `latched-ship-floor`. The double-block
yield already resolves that sentinel path on this same `contra=1` path (`_ca_scs`), so the read is free.
Estimated effect: about 34 more stated-park blocks removed per 14 days, for about 1 true positive lost.

I did not put it in the diff. It makes completion-assert read session-continue's private sidecar format
(`<sid> <sha> <count>`, `session-continue.sh:1250-1270`), and the double-block arm's own history warns how two
hooks drift about a file format. It wants its own review and a parity test that drives the real session-continue.
Conviction that it is net-positive: 80% (estimated).

## 5. The design and the exact diff

### 5.1 Predicate

```
FKEY := "f:" + sha1( facts with every [0-9]+ → "N"  +  "|"  +  (git -C $CWD rev-parse HEAD || "?") )[:16]
        computed only when contra = 1 and facts ≠ "" and CC_CA_FACT_LATCH ≠ 0
latched-same-fact := FKEY ≠ "" ∧ arm = "ledger" (no prose arm fired on this message)
                     ∧ some line of $STATE_DIR/<SKEY>.fired has field 3 = FKEY
on fire:  append "<msg-hash> <class> <FKEY>" (FKEY omitted when empty ⇒ the legacy two-column line)

⛔ term:  RUNG = ⛔ ∧ CC_CA_BLOCKED_STATED ≠ 0 ∧ rung line contains ⛔  ⇒  exonerate "blocked-rung-stated"
          rung line := _ca_rung_line = line 1, or lines 1-2 when line 1 matches CA_VERDICT_ANCHOR
          (the D6 rule, moved into one memoised helper that D6 now calls too)
```

What it leaves alone:
- The message-hash latch and the per-class caps and their reason strings.
- Every arm's predicate.
- The double-block yield. When it fires, `contra` is 0, so `FKEY` is empty and nothing is recorded.
- The IDL shape of `fired` and `capped` records. The new `latched-same-fact` record carries the same six fields
  as a capped one: `suppressed_arm`, `rung`, `facts`, `class`, `count`, `max`.
- The 7-day `.fired` GC.

Cost: three extra processes (`git rev-parse`, `sed`, `shasum`), and only on the contradiction path. One more `awk`
runs only when a latch file exists. The rung-line `grep` used to run inside D6. It now runs at most once per Stop,
on the ⛔ path or the D6 path (memoised, main shell).

### 5.2 `hooks/completion-assert.sh` (measured: `diff -u base/ final/`, 85 changed lines: 71 added, 14 removed)

Prototype at `/tmp/r2-C2/final/hooks/completion-assert.sh`. Patch file: `/tmp/r2-C2/C2-hook.diff`.

```diff
--- a/hooks/completion-assert.sh	2026-10-18 16:28:56
+++ b/hooks/completion-assert.sh	2026-10-18 20:17:28
@@ -83,7 +83,9 @@
 #   hook must never block the turn on its own misconfiguration.
 #
 # ── SAFETY (mirrors anti-deference-nudge.sh:26-41,90-104) ──
-#   L one-shot latch (a fired MSG hash never re-fires) · C hard cap PER CLASS: `assert` (every
+#   L one-shot latch (a fired MSG hash never re-fires) · P per-fact latch (a ledger-only fire whose
+#   digit-folded facts already convicted at this HEAD abstains `latched-same-fact` and spends no
+#   slot — see the block above the cap) · C hard cap PER CLASS: `assert` (every
 #   conviction arm) = COMPLETION_MAX (default 3), `shape` (D6) = COMPLETION_SHAPE_MAX (default 2),
 #   `verdict` (D6 verdict-first alone) = COMPLETION_VERDICT_MAX (default 2), `act` (D7 alone) =
 #   COMPLETION_ACT_MAX (default 2),
@@ -102,7 +104,9 @@
 #   CC_VERDICT_FIRST / COMPLETION_VERDICT_MAX (CLOSE_VERDICT_FIRST — D6's `verdict-first` token and
 #   D3's conditional-yes verdict-line branch; CC_VERDICT_FIRST=0 silences every FAIL that land
 #   added, and `verdict` is its own cap class for the reason the latch block gives) ·
-#   PEER_OWNED_LIB / CC_REGISTRY_DIR (LIVE-PEER-OWNED attribution — see the block at that term)
+#   PEER_OWNED_LIB / CC_REGISTRY_DIR (LIVE-PEER-OWNED attribution — see the block at that term) ·
+#   CC_CA_FACT_LATCH (0 disables the per-fact latch) · CC_CA_BLOCKED_STATED (0 makes the ⛔ term
+#   convict even a close whose rung line already states ⛔)
 set -uo pipefail
 
 # ── `--why <topic>` REFERENCE TIER (backlog 1031594b6327; docs/plans/STOPHOOK_MESSAGE_TIERING.md §3) ──
@@ -378,6 +382,21 @@
   if [ -z "$ca_first" ]; then ca_first="$ca_t"; continue; fi
   ca_second="$ca_t"; break
 done <<< "$MSG"
+# THE RUNG LINE — line 1, or lines 1-2 when line 1 is a verdict line (CLOSE_VERDICT_FIRST). ONE
+# definition for its two readers, D6's line-1-rung token and the ⛔ term's stated-rung exoneration,
+# because two copies of "which line is the rung line" would drift (hooks/lib/close-shape.sh:15-20).
+# Memoised into $_ca_rl and called in THIS shell, never inside `$( )`, so the grep runs at most once
+# per Stop and only on a path that needs it (most Stops abstain long before either reader).
+_ca_rl=""; _ca_rl_done=0
+_ca_rung_line() {
+  [ "$_ca_rl_done" -eq 1 ] && return 0
+  _ca_rl="$ca_first"
+  if printf '%s' "$ca_first" | grep -iE "$CA_VERDICT_ANCHOR" >/dev/null; then
+    _ca_rl="$ca_first
+$ca_second"
+  fi
+  _ca_rl_done=1
+}
 
 # A SETTLED-VERDICT FIRST LINE is a close by definition, even when the body carries none of the
 # CLOSE tokens: the real 2026-08-01 exchange answered "Good to close?" with "Yes — with one thing
@@ -1123,15 +1142,25 @@
 # the cc-decide store itself (MEMORY.md make-the-actuator-the-arbiter,
 # sibling-auditors-must-share-the-state-model).
 #
-# This cannot become a standing gate on the CORRECT close: a close whose line 1 actually IS the ⛔
-# rung carries no done-assertion, so it abstains at the close-tell gate above and never reaches
-# here — and one that names an irreducible operator-only blocker abstains earlier still at GENUINE.
+# A CLOSE THAT ALREADY STATES ⛔ HAS ANSWERED THIS TERM (2026-10-18, close-behavior round 2 C2). The
+# claim this block used to make — that a ⛔-led close "abstains at the close-tell gate above" — is
+# false whenever the body carries ANY `CLOSE` token ("landed", "remains", a ✅ on a later line), and
+# nearly every real ⛔ close does: 27 fires in 14 days told a close whose rung line already read ⛔
+# that "⛔ IS your rung" (docs/research/close-behavior-2026-10-18/round2/C2-per-fact-latch.md §2.3).
+# The rung line is D6's — line 1, or lines 1-2 under a verdict line 1 — read through the ONE helper
+# both use (_ca_rung_line). An exoneration, not a silence: the ledger-clean record names it.
+# Kill switch: CC_CA_BLOCKED_STATED=0 restores the unconditional term.
 # What is left is precisely the target: a close asserting done while a decision it filed is open.
 # Bounded by this hook's own per-session cap (MAX), like every other term.
 if [ "$RUNG" = "⛔" ]; then
   _ca_blocked="$(lfield BLOCKED)"; case "$_ca_blocked" in ''|*[!0-9]*) _ca_blocked="?" ;; esac
-  contra=1
-  facts="${facts}BLOCKED ON YOU — ${_ca_blocked} decision(s) filed this session are open (cc-decide list --open); that IS your rung; "
+  _ca_rung_line
+  if [ "${CC_CA_BLOCKED_STATED:-1}" != 0 ] && case "$_ca_rl" in *"⛔"*) true ;; *) false ;; esac; then
+    _ca_exon="${_ca_exon}blocked-rung-stated "
+  else
+    contra=1
+    facts="${facts}BLOCKED ON YOU — ${_ca_blocked} decision(s) filed this session are open (cc-decide list --open); that IS your rung; "
+  fi
 fi
 
 # ── THE DOUBLE-BLOCK YIELD (backlog 79e2b74796af) ────────────────────────────────────────────────
@@ -1472,12 +1501,9 @@
     # contra=0 above, so it cannot reach a mid-wave message.
     #   UNDER A VERDICT LINE 1 (CLOSE_VERDICT_FIRST, 2026-10-10) the rung line is line 2, so the
     # containment test reads lines 1-2. Every close that does not lead with a verdict keeps today's
-    # line-1 strictness.
-    _d6_rl="$ca_first"
-    if printf '%s' "$ca_first" | grep -iE "$CA_VERDICT_ANCHOR" >/dev/null; then
-      _d6_rl="$ca_first
-$ca_second"
-    fi
+    # line-1 strictness. The rule lives in _ca_rung_line (shared with the ⛔ term).
+    _ca_rung_line
+    _d6_rl="$_ca_rl"
     case "$_d6_rl" in
       *"$RUNG"*) : ;;
       *) _d6_missing="${_d6_missing:+$_d6_missing }line-1-rung" ;;
@@ -1619,6 +1645,37 @@
 N=0
 [ -f "$FIRED" ] && N="$(awk -v c="$CLASS" '{ k = ($2 == "" ? "assert" : $2); if (k == c) n++ } END { print n+0 }' "$FIRED" 2>/dev/null || printf 0)"
 case "$N" in ''|*[!0-9]*) N=0 ;; esac
+# ── PER-FACT LATCH (2026-10-18, close-behavior round 2 C2) — one conviction per fact per HEAD ──
+# The message-hash latch above cannot see that two DIFFERENT closes carry the SAME contradiction:
+# the model answers a ledger block with a rewritten close ("not done — the gate is still running"),
+# that rewrite hashes fresh, and the unchanged fact convicts again, 35 s later at the median. Each
+# re-conviction spends an `assert` slot, so a session's whole budget went on ONE fact and the later,
+# DIFFERENT defect arrived `capped:3>=3` — the 2026-10-18 incident close, whose three slots went on
+# "1 commit(s) YOU wrote are committed-but-unlanded" in 66 s while the ship floor, latched on the
+# same sha, stayed silent each time. Measured over 14 days (C2-per-fact-latch.md §2-§3): 144 of 331
+# fact-bearing fires repeated a fact already convicted in the session, and the 27 same-fact
+# same-sha repeats convicted closes that each said why the land was not done yet (gate running,
+# lock queued, a stated park, auto mode refusing it); one of the 27 preceded a ship.
+#   So a ledger-ONLY fire whose fact was already convicted at this HEAD abstains `latched-same-fact`
+# and spends nothing. The key is the facts string with every digit run folded to N (a count that
+# moves — 2 sessions out, then 1 — is the same demand) plus HEAD, the unit session-continue's ship
+# floor already latches on: a new commit is a new fact and convicts afresh. A message on which ANY
+# other arm also fired is never latched here — its prose demand is new — and the record of every
+# ledger fire carries the key as a THIRD column, so legacy two-column lines read exactly as before.
+# Kill switch: CC_CA_FACT_LATCH=0 (per-message re-conviction, as before).
+FKEY=""
+if [ "$contra" -eq 1 ] && [ -n "$facts" ] && [ "${CC_CA_FACT_LATCH:-1}" != 0 ]; then
+  _ca_head="$(git -C "$CWD" rev-parse HEAD 2>/dev/null)" || _ca_head=""
+  FKEY="$(printf '%s|%s' "$(printf '%s' "$facts" | sed -E 's/[0-9]+/N/g')" "${_ca_head:-?}" | shasum 2>/dev/null)"
+  FKEY="${FKEY:0:16}"; FKEY="${FKEY:+f:$FKEY}"
+fi
+if [ -n "$FKEY" ] && [ "$arm" = ledger ] && [ -f "$FIRED" ] \
+   && awk -v f="$FKEY" '$3 == f { hit = 1 } END { exit(hit ? 0 : 1) }' "$FIRED" 2>/dev/null; then
+  log_idl abstained "latched-same-fact" "$(jq -cn --arg arm "$arm" --arg rung "$RUNG" --arg facts "$facts" \
+      --arg class "$CLASS" --argjson count "$N" --argjson max "$CLASS_MAX" \
+    '{suppressed_arm:$arm,rung:$rung,facts:$facts,class:$class,count:$count,max:$max}' 2>/dev/null)"
+  exit 0
+fi
 if [ "$N" -ge "$CLASS_MAX" ]; then
   # The assert-class reason is byte-identical to the pre-split one (its consumers, and the RED
   # proof of the cap itself, key on that exact string); a shape cap names its own class.
@@ -1635,7 +1692,7 @@
 fi
 
 # ── FIRE: record hash + class, log, block with the contradicting FACTS. ──
-printf '%s %s\n' "$HASH" "$CLASS" >> "$FIRED" 2>/dev/null || true
+printf '%s %s%s\n' "$HASH" "$CLASS" "${FKEY:+ $FKEY}" >> "$FIRED" 2>/dev/null || true
 log_idl fired "false-done" \
   "$(jq -cn --arg facts "$facts" --arg rung "$RUNG" --arg arm "$arm" --arg class "$CLASS" \
             --argjson count "$((N+1))" --argjson max "$CLASS_MAX" \
```

### 5.3 `tests/completion-assert.bats` (4 tests changed, 13 added: 185 → 198, measured `bats --count`; 176 lines added, 1 removed)

Patch file: `/tmp/r2-C2/C2-tests.diff`.

The four existing tests below are the ones C2 flips. That was predicted by reading and then measured (§6): the
patched hook against the unmodified suite gives exactly these four `not ok` and nothing else. Each one asserted
that a *rewritten close over one unchanged fact* spends a slot, which is the behaviour C2 removes. Each is
rewritten to reach the cap through *distinct facts* (a new commit, or a second ledger fact), so the cap is still
proven.

| test (base line) | why it flips | rewrite |
|---|---|---|
| `cap: distinct false-dones fire to the cap then go silent` (:247) | 3 messages, 1 unlanded fact, 1 HEAD | a commit between closes (new HEAD = new fact); also asserts `capped:2>=2` |
| `⛔ CAP: distinct ⛔ closes fire to COMPLETION_MAX then go silent` (:1219) | 2 messages, 1 BLOCKED fact | 2nd close over `CA_BLOCKED_DOD_LEDGER` (BLOCKED + a DoD item) |
| `⛔ CAP: the capped record names the SUPPRESSED arm, the rung and the facts` (:1235) | same | same |
| `CAP SPLIT: mid-wave convictions spend the assert cap; the TERMINAL close still gets its shape demand` (:1698) | 3 messages, 1 custody fact | a commit between closes, then `git push` before the terminal close; asserts 3 `class:assert` fires |

`D7 CLASS` (:1894), the test the axis-02 skeptic said pins against the `surface`-class alternative, is
**not** flipped by C2 (measured green, §6). C2 changes no class assignment.

```diff
--- a/tests/completion-assert.bats	2026-10-18 16:28:56
+++ b/tests/completion-assert.bats	2026-10-18 20:25:10
@@ -244,15 +244,132 @@
 }
 
 # ── CAP: halts after COMPLETION_MAX distinct fires ──
+# Distinct FACTS, not only distinct messages: since the per-fact latch (close-behavior round 2 C2) a
+# rewritten close over the SAME unchanged fact is `latched-same-fact` and spends nothing, so the cap
+# is reached through new commits (a new HEAD is a new fact) — the population the cap still bounds.
 @test "cap: distinct false-dones fire to the cap then go silent" {
   export COMPLETION_MAX=2
   local w; w="$(mkrepo_unlanded cap)"
   run run_ca "$(mkfix "Everything is done.")"        "$w" "cap-s"; fired "$output"
+  ( cd "$w" && echo y > y.txt && git add y.txt && git commit -q -m "more unlanded work" ) >/dev/null 2>&1
   run run_ca "$(mkfix "All complete, nothing to do.")" "$w" "cap-s"; fired "$output"
+  ( cd "$w" && echo z > z.txt && git add z.txt && git commit -q -m "yet more" ) >/dev/null 2>&1
   run run_ca "$(mkfix "Finished — that was the main ask.")" "$w" "cap-s"
+  [ "$status" -eq 0 ]; [ -z "$output" ]
+  grep -q '"reason":"capped:2>=2"' "$COMPLETION_IDL"
+}
+
+# ── PER-FACT LATCH (close-behavior round 2 C2): one conviction per fact per HEAD ──
+# The 2026-10-18 incident: three ledger fires in 66 s on "1 commit(s) YOU wrote are committed-but-
+# unlanded", each on a REWRITTEN close (so the message-hash latch above never matched), spent the whole
+# assert budget, and the terminal close's different defect arrived capped:3>=3.
+@test "FACT LATCH: a rewritten close over the SAME unchanged fact is latched and spends no slot" {
+  export COMPLETION_MAX=3
+  local w; w="$(mkrepo_unlanded flatch)"
+  run run_ca "$(mkfix "Everything requested is done.")" "$w" "flatch-s"; [ "$status" -eq 0 ]; fired "$output"
+  run run_ca "$(mkfix "This isn't done, and I'm not claiming it is — the land is queued.")" "$w" "flatch-s"
+  [ "$status" -eq 0 ]; [ -z "$output" ]
+  run run_ca "$(mkfix "Still landing; nothing is done until it is on trunk.")" "$w" "flatch-s"
+  [ "$status" -eq 0 ]; [ -z "$output" ]
+  [ "$(grep -c '"reason":"latched-same-fact"' "$COMPLETION_IDL")" -eq 2 ]
+  local row; row="$(grep -F '"reason":"latched-same-fact"' "$COMPLETION_IDL" | tail -1)"
+  [ "$(printf '%s' "$row" | jq -r '.suppressed_arm')" = "ledger" ]
+  printf '%s' "$row" | jq -e '.facts | test("unlanded")' >/dev/null
+  [ "$(printf '%s' "$row" | jq -r '.count')" = "1" ]
+  # exactly ONE slot spent, and its line carries the fact key in a third column
+  local f; f="$(ls "$COMPLETION_STATE_DIR"/*.fired)"
+  [ "$(wc -l < "$f" | tr -d ' ')" -eq 1 ]
+  awk '$2 == "assert" && substr($3, 1, 2) == "f:" && length($3) == 18 { ok = 1 } END { exit(ok ? 0 : 1) }' "$f"
+}
+
+@test "FACT LATCH: a new commit is a new fact — it convicts afresh, on the slot the latch saved" {
+  export COMPLETION_MAX=2
+  local w; w="$(mkrepo_unlanded fhead)"
+  run run_ca "$(mkfix "Everything requested is done.")" "$w" "fhead-s"; fired "$output"
+  run run_ca "$(mkfix "All complete, nothing to do.")"  "$w" "fhead-s"; [ -z "$output" ]
+  ( cd "$w" && echo y > y.txt && git add y.txt && git commit -q -m "more unlanded work" ) >/dev/null 2>&1
+  run run_ca "$(mkfix "Finished — that was the main ask.")" "$w" "fhead-s"
+  [ "$status" -eq 0 ]; fired "$output"
+  printf '%s' "$output" | grep -q '(completion-assert assert 2/2)'
+}
+
+# The incident, end to end: the repeated fact latches, so the TERMINAL close — a different defect
+# (D1, over a ✅ ledger) — is still asserted against instead of arriving capped. Pre-C2 this is
+# `capped:3>=3` with suppressed_arm "handoff", the exact live record of 2026-10-18T14:27:50Z.
+@test "FACT LATCH: the terminal close's DIFFERENT defect still fires after one fact was re-closed three times" {
+  export COMPLETION_MAX=3
+  export CC_BACKLOG_STUB_JSON='[]'
+  WRAP_LEDGER_BIN="$(mkledger fl-blk "${CA_BLOCKED_LEDGER[@]}")"; export WRAP_LEDGER_BIN
+  run run_ca "$(mkfix "✅ Complete & live on trunk — landed, all green, nothing unsaved.")" "$BATS_TEST_TMPDIR" "fl-inc"
+  fired "$output"
+  run run_ca "$(mkfix "All complete — nothing to do.")" "$BATS_TEST_TMPDIR" "fl-inc"; [ -z "$output" ]
+  run run_ca "$(mkfix "Done — everything landed.")"     "$BATS_TEST_TMPDIR" "fl-inc"; [ -z "$output" ]
+  WRAP_LEDGER_BIN="$(mkledger fl-ok DIRTY=0 DIRTY_N=0 UNLANDED=0 AHEAD=0 REMAINDER=0 \
+                            TRUNK=origin/main BLOCKED=0 RUNG=✅)"; export WRAP_LEDGER_BIN
+  run run_ca "$(mkfix "✅ Good to close: yes. Nothing of mine is open.
+The one change that needs your hand is raising the dispatcher's timeout.")" "$BATS_TEST_TMPDIR" "fl-inc"
+  [ "$status" -eq 0 ]; fired "$output"
+  grep -q '"arm":"handoff"' "$COMPLETION_IDL"
+  ! grep -q '"reason":"capped:' "$COMPLETION_IDL"
+}
+
+# Digit runs fold to N: a count that moves on the same HEAD (2 sessions out, then 1; 1 decision open,
+# then 2) is the same demand, not a new one.
+@test "FACT LATCH: numbers are folded — '2 decision(s)' after '1 decision(s)' on one HEAD is one fact" {
+  WRAP_LEDGER_BIN="$(mkledger fl-n1 "${CA_BLOCKED_LEDGER[@]}")"; export WRAP_LEDGER_BIN
+  run run_ca "$(mkfix "✅ Complete & live on trunk — landed, all green, nothing unsaved.")" "$BATS_TEST_TMPDIR" "fl-num"
+  fired "$output"
+  WRAP_LEDGER_BIN="$(mkledger fl-n2 DIRTY=0 DIRTY_N=0 UNLANDED=0 AHEAD=0 REMAINDER=0 \
+                            TRUNK=origin/main BLOCKED=2 RUNG=⛔)"; export WRAP_LEDGER_BIN
+  run run_ca "$(mkfix "All complete — nothing to do.")" "$BATS_TEST_TMPDIR" "fl-num"
   [ "$status" -eq 0 ]; [ -z "$output" ]
+  grep -q '"reason":"latched-same-fact"' "$COMPLETION_IDL"
 }
 
+# A different fact on the same HEAD is a different demand: the latch keys on the facts, not the rung.
+@test "FACT LATCH CONTROL: a DIFFERENT fact on the same HEAD convicts" {
+  WRAP_LEDGER_BIN="$(mkledger fl-d1 "${CA_BLOCKED_LEDGER[@]}")"; export WRAP_LEDGER_BIN
+  run run_ca "$(mkfix "✅ Complete & live on trunk — landed, all green, nothing unsaved.")" "$BATS_TEST_TMPDIR" "fl-diff"
+  fired "$output"
+  WRAP_LEDGER_BIN="$(mkledger fl-d2 DIRTY=0 DIRTY_N=0 UNLANDED=0 AHEAD=0 REMAINDER=0 \
+                            TRUNK=origin/main BLOCKED=1 CUSTODY_OPEN=2 RUNG=⛔)"; export WRAP_LEDGER_BIN
+  run run_ca "$(mkfix "All complete — nothing to do.")" "$BATS_TEST_TMPDIR" "fl-diff"
+  [ "$status" -eq 0 ]; fired "$output"
+  printf '%s' "$output" | grep -q 'dispatched session(s) have NOT returned'
+}
+
+# A message on which a PROSE arm also fires carries a new demand, so the ledger half never mutes it.
+@test "FACT LATCH: a close that ALSO fires a prose arm is not latched" {
+  export CC_BACKLOG_STUB_JSON='[]'
+  WRAP_LEDGER_BIN="$(mkledger fl-p "${CA_BLOCKED_LEDGER[@]}")"; export WRAP_LEDGER_BIN
+  run run_ca "$(mkfix "✅ Complete & live on trunk — landed, all green, nothing unsaved.")" "$BATS_TEST_TMPDIR" "fl-prose"
+  fired "$output"
+  run run_ca "$(mkfix "All complete — nothing to do.
+Two things remain yours, and I have written them up above.")" "$BATS_TEST_TMPDIR" "fl-prose"
+  [ "$status" -eq 0 ]; fired "$output"
+  grep -q '"arm":"ledger+handoff"' "$COMPLETION_IDL"
+}
+
+@test "FACT LATCH KILL SWITCH: CC_CA_FACT_LATCH=0 restores per-message re-conviction" {
+  export CC_CA_FACT_LATCH=0
+  local w; w="$(mkrepo_unlanded fkill)"
+  run run_ca "$(mkfix "Everything requested is done.")" "$w" "fkill-s"; fired "$output"
+  run run_ca "$(mkfix "All complete, nothing to do.")"  "$w" "fkill-s"; [ "$status" -eq 0 ]; fired "$output"
+  ! grep -q '"reason":"latched-same-fact"' "$COMPLETION_IDL"
+}
+
+# A pre-C2 latch file (two columns, no fact key) latches nothing by fact and counts exactly as before.
+@test "FACT LATCH COMPAT (green both sides): a two-column latch line is read unchanged" {
+  export COMPLETION_MAX=2
+  local w; w="$(mkrepo_unlanded fcompat)"
+  run run_ca "$(mkfix "Everything requested is done.")" "$w" "fcompat-s"; fired "$output"
+  local f; f="$(ls "$COMPLETION_STATE_DIR"/*.fired)"
+  awk '{print $1, $2}' "$f" > "$f.tmp"; mv "$f.tmp" "$f"
+  run run_ca "$(mkfix "All complete, nothing to do.")" "$w" "fcompat-s"
+  [ "$status" -eq 0 ]; fired "$output"
+  printf '%s' "$output" | grep -q '(completion-assert assert 2/2)'
+}
+
 # ── FAIL-SAFE: every degenerate input exits 0 silent (a block must never come from an error) ──
 @test "fail-safe: missing transcript_path ⇒ silent exit 0" {
   run bash -c 'printf "{\"session_id\":\"x\",\"cwd\":\"/tmp\"}" | bash "$1"' _ "$HOOK"
@@ -1215,13 +1332,17 @@
   /usr/bin/grep -q '"reason":"latched-already-fired"' "$COMPLETION_IDL"
 }
 
-# …and so does COMPLETION_MAX, on DISTINCT closes (which the latch cannot bound).
+# …and so does COMPLETION_MAX, on DISTINCT closes (which the latch cannot bound). The second close
+# carries a second fact (a DoD item) so it is a new demand: a rewrite over the SAME unchanged fact is
+# `latched-same-fact` since the per-fact latch, and never reaches the cap (the FACT LATCH cases).
+CA_BLOCKED_DOD_LEDGER=(DIRTY=0 DIRTY_N=0 UNLANDED=0 AHEAD=0 REMAINDER=1 TRUNK=origin/main BLOCKED=1 RUNG=⛔)
 @test "⛔ CAP: distinct ⛔ closes fire to COMPLETION_MAX then go silent" {
   export COMPLETION_MAX=1
   WRAP_LEDGER_BIN="$(mkledger blk7 "${CA_BLOCKED_LEDGER[@]}")"; export WRAP_LEDGER_BIN
   run run_ca "$(mkfix "✅ Complete & live on trunk — landed, all green, nothing unsaved.")" \
              "$BATS_TEST_TMPDIR" "blk-cap"
   [ "$status" -eq 0 ]; fired "$output"
+  WRAP_LEDGER_BIN="$(mkledger blk7b "${CA_BLOCKED_DOD_LEDGER[@]}")"; export WRAP_LEDGER_BIN
   run run_ca "$(mkfix "All complete — nothing to do.")" "$BATS_TEST_TMPDIR" "blk-cap"
   [ "$status" -eq 0 ]; [ -z "$output" ]
   /usr/bin/grep -q '"reason":"capped:1>=1"' "$COMPLETION_IDL"
@@ -1238,6 +1359,7 @@
   run run_ca "$(mkfix "✅ Complete & live on trunk — landed, all green, nothing unsaved.")" \
              "$BATS_TEST_TMPDIR" "blk-capx"
   [ "$status" -eq 0 ]; fired "$output"
+  WRAP_LEDGER_BIN="$(mkledger blk8b "${CA_BLOCKED_DOD_LEDGER[@]}")"; export WRAP_LEDGER_BIN
   run run_ca "$(mkfix "All complete — nothing to do.")" "$BATS_TEST_TMPDIR" "blk-capx"
   [ "$status" -eq 0 ]; [ -z "$output" ]
   local row; row="$(/usr/bin/grep -F '"reason":"capped:1>=1"' "$COMPLETION_IDL" | tail -1)"
@@ -1246,8 +1368,55 @@
   [ "$(printf '%s' "$row" | jq -r '.rung')" = "⛔" ]
   [ "$(printf '%s' "$row" | jq -r '.class')" = "assert" ]
   printf '%s' "$row" | jq -e '.facts | length > 0' >/dev/null
+}
+
+# ── ⛔ STATED: a close whose rung line already reads ⛔ has answered this term (round 2 C2) ──────────
+# 27 fires in 14 days told a close LED by ⛔ that "⛔ IS your rung", because the close-tell gate passes
+# any body carrying a CLOSE token ("landed", ✅ on a later line). The rung line is D6's: line 1, or
+# lines 1-2 under a verdict line 1 (_ca_rung_line, one helper for both readers).
+@test "⛔ STATED: a ⛔-led close over a ⛔ ledger is exonerated, not convicted" {
+  WRAP_LEDGER_BIN="$(mkledger blks1 "${CA_BLOCKED_LEDGER[@]}")"; export WRAP_LEDGER_BIN
+  run run_ca "$(mkfix "⛔ Blocked — 1 decision waits on your ruling: keep or retire pane 182.
+Everything else is landed and live.")" "$BATS_TEST_TMPDIR" "blk-stated"
+  [ "$status" -eq 0 ]; [ -z "$output" ]
+  /usr/bin/grep -q '"reason":"ledger-clean:exonerated:blocked-rung-stated"' "$COMPLETION_IDL"
 }
 
+@test "⛔ STATED: under a verdict line 1 the rung line is line 2" {
+  WRAP_LEDGER_BIN="$(mkledger blks2 "${CA_BLOCKED_LEDGER[@]}")"; export WRAP_LEDGER_BIN
+  run run_ca "$(mkfix "❌ Good to close: no — one decision waits on your ruling.
+⛔ Ruling needed on the retire-or-keep question; the rest is landed.")" "$BATS_TEST_TMPDIR" "blk-stated2"
+  [ "$status" -eq 0 ]; [ -z "$output" ]
+  /usr/bin/grep -q 'blocked-rung-stated' "$COMPLETION_IDL"
+}
+
+# CONTROL: ⛔ only in the body is not a stated rung — the done-reading line 1 is still convicted.
+@test "⛔ STATED CONTROL: a ⛔ below the rung line still convicts" {
+  WRAP_LEDGER_BIN="$(mkledger blks3 "${CA_BLOCKED_LEDGER[@]}")"; export WRAP_LEDGER_BIN
+  run run_ca "$(mkfix "✅ Complete & live on trunk — landed, all green.
+All suites pass.
+⛔ one decision is below.")" "$BATS_TEST_TMPDIR" "blk-stated3"
+  [ "$status" -eq 0 ]; fired "$output"
+  printf '%s' "$output" | /usr/bin/grep -q 'BLOCKED ON YOU'
+}
+
+# The exoneration is the ⛔ term's alone: another contradiction on the same close still convicts.
+@test "⛔ STATED: a ⛔-led close with a SECOND contradiction still convicts on that one" {
+  WRAP_LEDGER_BIN="$(mkledger blks4 "${CA_BLOCKED_DOD_LEDGER[@]}")"; export WRAP_LEDGER_BIN
+  run run_ca "$(mkfix "⛔ Blocked — 1 decision waits on your ruling. Everything else is landed.")" "$BATS_TEST_TMPDIR" "blk-stated4"
+  [ "$status" -eq 0 ]; fired "$output"
+  printf '%s' "$output" | /usr/bin/grep -q 'frozen-DoD item(s) remain'
+  ! printf '%s' "$output" | /usr/bin/grep -q 'BLOCKED ON YOU'
+}
+
+@test "⛔ STATED KILL SWITCH: CC_CA_BLOCKED_STATED=0 convicts the ⛔-led close as before" {
+  WRAP_LEDGER_BIN="$(mkledger blks5 "${CA_BLOCKED_LEDGER[@]}")"; export WRAP_LEDGER_BIN
+  CC_CA_BLOCKED_STATED=0 run run_ca "$(mkfix "⛔ Blocked — 1 decision waits on your ruling: keep or retire pane 182.
+Everything else is landed and live.")" "$BATS_TEST_TMPDIR" "blk-stated5"
+  [ "$status" -eq 0 ]; fired "$output"
+  printf '%s' "$output" | /usr/bin/grep -q 'BLOCKED ON YOU'
+}
+
 # ── D6 — the ORIGIN Pyramid-close contract (CLOSE_INTEGRITY W1) ─────────────────────────────────
 # The one close every other arm waves through: ledger ✅, real written work, a close-shaped
 # message — and the operator's two standing questions (Complication/Solution/Outcome + an explicit
@@ -1701,9 +1870,15 @@
   # MID-WAVE: a clean landed tree with dispatched peers still out ⇒ the ledger arm convicts.
   STUB="$BATS_TEST_TMPDIR/capsplit-stub"; printf '%s\n' '#!/usr/bin/env bash' 'echo 2' > "$STUB"; chmod +x "$STUB"
   export CC_CUSTODY_BIN="$STUB"
+  # Three DISTINCT facts (a new commit each time), because a rewrite over one unchanged fact is
+  # `latched-same-fact` and spends nothing since the per-fact latch (close-behavior round 2 C2).
   run run_ca "$(mkfix "Everything requested is done — the wave is running.")" "$w" "capsplit-s"; fired "$output"
+  ( cd "$w" && echo a > a.txt && git add a.txt && git commit -q -m "wave a" ) >/dev/null 2>&1
   run run_ca "$(mkfix "All complete, nothing left to do here.")"             "$w" "capsplit-s"; fired "$output"
+  ( cd "$w" && echo b > b.txt && git add b.txt && git commit -q -m "wave b" ) >/dev/null 2>&1
   run run_ca "$(mkfix "Finished — that was the main ask.")"                  "$w" "capsplit-s"; fired "$output"
+  [ "$(grep -c '"class":"assert"' "$COMPLETION_IDL")" -eq 3 ]
+  ( cd "$w" && git push -q origin main ) >/dev/null 2>&1
   unset CC_CUSTODY_BIN
   # TERMINAL: the wave has returned (custody 0 ⇒ ✅), real writes, shape missing. The assert budget
   # is spent — the shape demand must NOT be.
```

### 5.4 The incident, replayed through both copies (measured)

`/tmp/r2-C2/bin/replay.sh <base|patched> <interp> <tag>`. This feeds the incident's four Stops through a copy of
the hook. The state seams all point under `/tmp/r2-C2/replay/<tag>/`: `COMPLETION_STATE_DIR`, `COMPLETION_IDL`,
`CC_IDL`, `CLAUDE_CONFIG_DIR`, `TMPDIR`, `CC_FIRED_DIR`, `CC_REGISTRY_DIR`, `CC_CUSTODY_DIR`,
`CC_CONTINUE_SENTINEL` and `CC_BACKLOG_BIN` (a `[]` stub). The ledger is stubbed through `WRAP_LEDGER_BIN`:
📦 with one unlanded commit for Stops 1-3, then ✅ all-zero for Stop 4, which are the live rungs. The cwd is a
fixture repo with a fixed HEAD.

The close texts are the transcript's own:
- 13:18:32Z: "I'm holding the land on purpose…"
- 13:18:59Z: "This isn't done, and I'm not claiming it is…"
- 14:27:47Z: the incident close.

Stop 3 needs a caveat. The literal 13:19:37Z text carries no `CLOSE` token, and my replay abstains `no-close-tell`
on it in both copies. The live 13:19:40Z Stop nevertheless fired, so the live hook read a different message. That
is plausibly the transcript-tail lag that candidate C1 studies. To reproduce the live third fire, Stop 3 uses the
13:18:59Z text plus one line, which gives a fresh hash on the same fact.

| Stop | base (`/bin/bash` 3.2) | patched (`/bin/bash` 3.2 and bash 5.3.15: identical) |
|---|---|---|
| 1 | `fired` ledger 1/3 | `fired` ledger 1/3 |
| 2 | `fired` ledger 2/3 | `abstained latched-same-fact`, count 1 |
| 3 | `fired` ledger 3/3 | `abstained latched-same-fact`, count 1 |
| 4 (incident close) | `abstained capped:3>=3`, `suppressed_arm:"handoff"`, rung ✅ (**the live record**) | `fired` **handoff** 2/3 |

The latch file after the patched run holds `f40f157dba60da01 assert f:0eeffa3721e588fa` and
`7da823a14a6b6d81 assert`. That is one ledger slot with its fact key, plus one prose slot.

**What Stop 4's block says** is D1's text: "An operator-only step is not an escape hatch … If you can run it, run
it now … File each operator-only step — `cc-backlog needs …`". It fires because of "needs your hand", which is
the 70% settings.json timeout, and it names nothing in README §5. This matches axis 02 replay A. So C2 turns the
silent incident close into a block, but not into the block the operator wanted. The §5 waves needed an arm that
reads the follow-on clause, or the DoD seam (axis 02 "Missed" item 7). C2 is what lets either one reach a long
session's terminal close with budget left.

## 6. Test runs (measured)

The copies come from `git archive HEAD` (f12dd4b12):
- `/tmp/r2-C2/base`: unchanged;
- `/tmp/r2-C2/patched`: the hook diff only;
- `/tmp/r2-C2/final`: the hook diff plus the test diff;
- `*-git` twins, made with `git init` plus a read-only `objects/info/alternates` onto the main repo's object store,
  so the forks and durations suites can rebuild their SHF_BASE trees.

State seams for every run: `CLAUDE_CONFIG_DIR=/tmp/r2-C2/sbx/cfg`, `TMPDIR=/tmp/r2-C2/sbx/tmp`,
`WRAP_LINK_STRAY_CACHE` and `CC_IDL` under `/tmp/r2-C2/sbx`. The suites pin the rest themselves.

`cc-bats` shed with rc 75 (`REFUSED — 2 concurrent bats execution root(s) … load/core ≥ 2.0`; load
91 → 370 on 10 cores during this work). The Cellar `bin/bats` is the same shim. Per the brief, the runs used plain
bats through cc-bats's documented kill switch, `CC_BATS_QOS=off`, with the utility band re-applied by hand
(`taskpolicy -c utility`). Every run was serial, with no `--jobs` (`/tmp/r2-C2/bin/runbats.sh`, `runbats2.sh`).

| run | plan | ok | not ok | wall |
|---|---|---|---|---|
| base hook + base `completion-assert.bats` | 1..185 | 185 | 0 | 267 s |
| **patched hook + unmodified suite** | 1..185 | 181 | **4**: #11 `cap: distinct false-dones…`, #83 `⛔ CAP: distinct ⛔ closes…`, #84 `⛔ CAP: the capped record names…`, #111 `CAP SPLIT: mid-wave convictions…` | 323 s |
| final hook + final suite, the 19 tests matching `FACT LATCH\|⛔ STATED\|⛔ CAP\|CAP SPLIT\|^cap:` (13 new, 4 rewritten, 2 unchanged CAP SPLIT) | 1..19 | 19 | 0 | 1,477 s |
| base-git + `completion-assert-forks.bats` (parity and process budget against SHF_BASE e1fbd8a5a) | 1..8 | 8 | 0 | 3,107 s |
| final-git + `completion-assert-forks.bats` | 1..8 | 8 | 0 | 1,309 s |
| final-git + `completion-assert-assignee-shared-cwd.bats` | 1..9 | 9 | 0 | 93 s |
| final-git + `completion-assert-durations.bats` (SHF_BASE 4b1224be5) | 1..8 | 6 | **2**: #3 `A3 … BESIDE the ledger`, #7 `C4 D1's backlog read runs BESIDE the ledger` | 3,658 s |
| base-git + the same two durations tests (`--filter '^A3 \|^C4 '`), the control | 1..2 | 0 | **2**: the same two. A3 "prefetch off 58135 ms, on 98207 ms"; C4 failed at `cmp dserial dnew` (dserial empty) | 1,583 s |

The four reds in row 2 are exactly the four predicted by reading (§5.3). Neither the ⛔ guard nor the D6 helper
move flipped anything else, and that includes `D7 CLASS` and every D6 `line-1-rung` / verdict-first case. The final
198-test suite is therefore measured green in two parts: the 181 unchanged tests (row 2, with the hook byte-identical
to final, `diff -q`) and the 17 new or rewritten ones (row 3). `bats --count` on the final file gives 198. A single
198-test run did not fit this session at load 370 (row 3 ran at about 78 s per test). Treat it as the implementer's
first check, together with the land gate's own run.

**The two durations reds are wall-clock tests that the load made unrunnable, not C2** (measured):
- `A3` compares two arms of the *same* hook that differ only in `CC_CA_PREFETCH`. Its line reads "prefetch off
  73731 ms, on 83989 ms (pre-change hook 228251 ms)". The test plants 2 s sleeps and expects about 4 s vs about
  2 s, but at load 360 each Stop took 1-4 minutes. C2's +3 processes sit identically in both arms.
- `C4` failed its parity `cmp`. Under the planted 2 s `sleep` wrappers, the old arm answered a 👤 `act` block and
  both new arms (prefetch on and off) answered nothing.
- The same C4 Stop, run hook-only through **base and final** without the sleep wrappers, from a blank state each
  time (`/tmp/r2-C2/bin/c4ab.sh`, twice per arm), gives a byte-identical 1,006-byte `act` block with rung 👤 from
  both. So C2 does not change C4's answer. The empty answers come from the slowed reads under load, which is
  plausibly the ledger's own bounded backlog read.
- **The base tree fails the same two tests in the same load regime** (control row above). They are red on
  unmodified HEAD at this load.

**Process budget (measured, the forks suite's own `# done claim, ledger computed` line).**
- SHF_BASE: 155 external calls; base HEAD: 99; final: **102**. The +3 is exactly `git` 19→20, `shasum` 6→7 and
  `sed` 3→4: the fact-key read on the contradiction path.
- The suite's floor is "at least 40 fewer than SHF_BASE". The margin goes from 56 to 53, so it holds.
- The parity tests (same stdout, stderr, IDL rows and state file names as SHF_BASE on a first fire) are green on
  final. The third latch column changes a file's contents, not its name, and the first fire's IDL record is
  unchanged.

RED-proofs without bats, hook-only, `/bin/bash` 3.2, same seams:
- `redproof.sh`, the four Stops of `FACT LATCH: the terminal close's DIFFERENT defect…`. Base: fired 1, 2, 3,
  then `capped:3>=3` with `suppressed_arm:"handoff"`. Final: fired 1, `latched-same-fact` ×2, then `handoff` fires 2/3.
- `redproof2.sh`, the three `⛔ STATED` texts. Base: all three fire `ledger`. Final: the ⛔-led close and the
  verdict + ⛔-line-2 close abstain `ledger-clean:exonerated:blocked-rung-stated`, and the control (⛔ only on
  line 3) still fires.

**Trunk moved during this work** (measured). origin/main is now dfdb5c273. It carries b0f3971b8 (arm O,
"outbound source read", +73 lines in `hooks/completion-assert.sh` and a new `tests/completion-assert-outbound.bats`).
That commit is not in this worktree's history. Both C2 diffs apply cleanly to trunk's two files: `patch --dry-run`
against `git show origin/main:<file>` copies in `/tmp/r2-C2/trunk/` (`--verbose`) applies every hunk with no fuzz;
hook hunks 3-7 land at offset +73. The two arms do not
interact. Arm O writes two-column `<hash> outbound` lines into the same `.fired` file, and the fact latch reads
field 3 only, while the assert count counts `assert` lines only. That is by reading; `completion-assert-outbound.bats`
was not run.

Static (measured): `shellcheck hooks/completion-assert.sh`, bare as the land gate runs it, gives rc 0 with no
findings on both base and final. `/bin/bash -n` (3.2) is OK. The incident replay (§5.4) is identical under
`/bin/bash` 3.2.57 and bash 5.3.15.

## 7. Net effect of the design as diffed: latch (head, K=1) + stated-⛔ guard (estimated replay + hand-read)

`sim2.py events.jsonl sc14.jsonl --key head --k 1 --guard blocked`, 14 days:

| quantity | today (measured) | with C2 (estimated) |
|---|---|---|
| assert-class blocks | 345 | 256 (−89, −26%) |
| … on closes worded as a wait or park | 222 | 148 |
| … on closes with a ❌/"no" verdict | 97 | 59 |
| … BLOCKED-ON-YOU on a close whose rung line already says ⛔ | 27 | 0 |
| `capped:3>=3` evaluations that would fire | — | 41, in 31 sessions |
| repeat or ⛔-stated fires that go silent | — | 130 |

**Hand-read of all 41 recovered fires** (close line 1 from the transcript; listing in the run log). Plausible true
positives:
- 36b81fea 10-05T03:56, `hedge`: "now complete … except P3a-ii, which is still building";
- 2328e32b 10-16T07:03: done-reading over an open decision;
- 5759497b 10-18T14:27: the incident close, a real defect, though the wrong arm fires;
- e7ed8439 10-14T22:38: D1 on "follow-on: the Otto call is yours", which counts as half at most.

That is **about 3.5 of 41 (≈9%)**. The rest are waiting leads and honest ❌/🔧/📦/👤 closes, 📬 acks,
conversation ("Yes, it's correct. Leave it as it is."), and three ⛔ closes on which D1 still fires once the
ledger half is exonerated (e131c8d2, 9fd1dbab, 69778275).

**Lost true positives**: about 1 of the 27 same-HEAD unlanded repeats (§3). The custody, dirty and BLOCKED repeats
that make up the other ~100 silenced fires are, by the §2.2 classifier, overwhelmingly on wait-worded closes.
I did not hand-read every one of those.

So by this estimate C2 removes about 128 false-positive blocks and adds about 37, while true positives change by
roughly +3.5 / −1. It is clearly net-positive on operator-facing noise and roughly neutral-to-positive on catches.
**What it does not do** is make the ledger arm respect a stated park on its first conviction. That defect sits in
the arm's close-tell gate, not in its budget.

## 8. Constraints

| # | constraint | status | evidence |
|---|---|---|---|
| 1 | silent when nothing drivable remains; not always-firing | **met** | C2 adds no firing condition. It removes fires (−26%) and only redistributes cap budget among fires the existing predicates already make. With an empty ledger `contra=0` ⇒ `FKEY=""` ⇒ no path changes. |
| 2 | never blocks a genuine ⛔ decision or a deliberate stated park | **partly met** | ⛔-stated closes go from 27 blocks to 0 (guard). Repeat blocks on stated parks go away (the latch). The **first** ledger conviction of a stated park remains, as it does today. 148 wait-worded blocks remain per 14 days versus 222, about 14 of them recovered from the cap. §4.1 (C2-SF) would remove about 34 more for unlanded facts. |
| 3 | no settings.json edits | **met** | none. The hook is already registered. |
| 4 | rule text must not grow the resident budget | **met** | no rule-text change at all: 0 bytes to `CLAUDE.rules.slim.10-session-close.md` and `CLAUDE.global.slim.md`. |
| 5 | do not edit the six named files | **met** | the diff touches `hooks/completion-assert.sh` and `tests/completion-assert.bats` only. |
| 6 | one matcher per concept; reuse libs | **met** | no new matcher. The fact key is the facts string the arm already builds. The HEAD read is the ship floor's own command. The rung-line rule moved from D6's inline block into one memoised helper that both D6 and the ⛔ term call, so the two readers cannot drift. |

## 9. Open risks

1. **Counterfactual replay.** Every "would have fired" number replays the observed Stop sequence. A recovered block
   changes what the model writes next, and a silenced one changes it the other way. Both are bounded by the
   unchanged per-class caps.
2. **The recovered fires are mostly false positives** (≈9% precision, §7). The latch frees budget, and the ledger
   arm's close-tell gate spends it on honest wait closes. The structural fix is in that gate (see 3), not here.
3. **A known gate defect, out of scope and not fixed.** The ledger arm convicts closes whose verdict is "no"
   (97 of 345 fires) because `CLOSE` matches `landed`, `remains`, ✅ or 📦 anywhere. The hook's own
   CLOSE_VERDICT_FIRST comment states the policy that "a negative verdict line 1 is not a done-tell", but it is
   enforced only when the body has no `CLOSE` token. That is a separate candidate. It trades away continuation
   pushes on honest "no — not shipped yet" closes, so it needs its own measurement.
4. **The guard covers the glyph only.** One BLOCKED fire in 14 days convicted a "❌ Good to close: no … waiting on
   your … call" close with no ⛔ glyph (6069b9d3). Adding `CA_VERDICT_NO` on line 1 to the guard would cover it.
   It is left out because it is 1 case in 14 days and would add a fork on the ⛔ path.
5. **Normalization folds every digit run**, including shas inside the "authorship UNRESOLVED (shas)" variant. HEAD
   is in the key, so two different unlanded sets on one HEAD cannot occur. Two dirty sets on one HEAD *do* fold:
   "3 files" and "5 files" are one demand, on purpose (§5.1).
6. **Session-level spend across HEADs is unchanged.** The live self-repro (three facts, two HEADs) still caps.
   Whether a lead that commits mid-wave should be re-convicted per commit is a policy question. C2 answers it the
   way the ship floor already does: yes, once per commit.
7. **Process budget.** C2 adds 3 processes on the contradiction path. The measured count is 99 → 102 (§6), still 53
   under SHF_BASE against a floor of 40. It adds no process on the 79% of Stops that end at `no-close-tell`. If the
   3 ever matter, `sed` can become a builtin: `shopt -s extglob; ${facts//+([0-9])/N}` parses and folds correctly
   under `/bin/bash` 3.2 (measured). That would cost an extglob toggle around one line.
8. **Fixture texts.** The new ⛔ STATED tests avoid D1's `needs your` / `is yours` spellings so that each case names
   one arm. Real ⛔ closes often say "need your call" (no s), which D1 does not match.

## 10. Operator-only steps

None for the change itself: no settings.json change, no credential, no launchd change. Landing it is the ordinary
agent-driven `/ship` of two files. A Stop hook that is a symlink into the checkout goes live on the fast-forward
(`install.sh` adds no new file).

## Appendix A. The measurement scripts, verbatim

`/tmp/r2-C2` does not survive a reboot. This session's own §0 found the lead's repro file gone for exactly that
reason, so the three scripts that carry the numbers are reproduced here. Inputs:
- `ca14.jsonl` = `cat` of `gzip -dc ~/.claude/autonomy/idl.jsonl.2026*.gz | grep '"hook":"completion-assert"'`
  plus the same grep on `idl.jsonl`, filtered with `jq -c 'select(.ts >= "2026-10-05T01:00:00Z")'`;
- `sc14.jsonl`, built the same way for `"hook":"session-continue"`;
- `transcripts.txt` = `find ~/.claude*/projects -maxdepth 2 -name '*.jsonl*' -newermt 2026-10-04 | grep -v subagents`.

Run with `python3 -I`.

### A.1 `annotate.py`: attach each assert-class event's close lines and the next ship call

```python
import json, sys, os, re, bisect, collections
# Annotate assert-class fired/capped events with the close text's first two lines and the
# session's later ship-ish tool calls. Reads transcripts read-only.
# usage: annotate.py <ca14.jsonl> <transcripts.txt> > events.jsonl
ca, idx = sys.argv[1], sys.argv[2]
paths = [l.strip() for l in open(idx)]
bysid = collections.defaultdict(list)
for p in paths:
    b = os.path.basename(p)
    bysid[b[:36]].append(p)
evs = collections.defaultdict(list)
for l in open(ca):
    r = json.loads(l)
    if (r.get("disposition") == "fired" and r.get("class") == "assert") or r.get("reason") == "capped:3>=3":
        evs[r["sid"]].append(r)
SHIP = re.compile(r'ship-land|(^|[\s"/])/ship\b|git push|"skill":\s*"ship"|deploy-live', re.I)
for sid, rs in evs.items():
    texts = []; ships = []; stopfb = []
    for p in bysid.get(sid, []):
        try: fh = open(p, errors="replace")
        except OSError: continue
        for line in fh:
            try: r = json.loads(line)
            except Exception: continue
            t = r.get("timestamp") or ""
            if not t or r.get("isSidechain"): continue
            ty = r.get("type")
            content = (r.get("message") or {}).get("content")
            if ty == "assistant" and isinstance(content, list):
                txt = "\n".join(c.get("text", "") for c in content if isinstance(c, dict) and c.get("type") == "text")
                if txt.strip(): texts.append((t, txt))
                for c in content:
                    if isinstance(c, dict) and c.get("type") == "tool_use":
                        s = json.dumps(c.get("input", {}))
                        if SHIP.search(s) and "git push" not in s[:0]:
                            ships.append((t, s[:160]))
            elif ty == "user":
                s = content if isinstance(content, str) else json.dumps(content)
                if "Stop hook feedback" in s[:200]:
                    stopfb.append((t, s[:120]))
    texts.sort(); ships.sort(); stopfb.sort()
    tkeys = [t for t, _ in texts]
    for r in rs:
        ts = r["ts"][:19]
        i = bisect.bisect_right(tkeys, ts + "~") - 1
        l1 = l2 = ""; tt = ""
        if i >= 0:
            tt, txt = texts[i]
            ls = [x.strip() for x in txt.splitlines() if x.strip()]
            l1 = ls[0] if ls else ""; l2 = ls[1] if len(ls) > 1 else ""
        nxt_ship = next(((t, s) for t, s in ships if t[:19] >= ts), None)
        out = dict(r)
        out.update({"close_t": tt, "l1": l1[:300], "l2": l2[:300], "found": bool(bysid.get(sid)),
                    "next_ship_t": nxt_ship[0] if nxt_ship else None,
                    "next_ship_cmd": nxt_ship[1] if nxt_ship else None})
        print(json.dumps(out, ensure_ascii=False))
```

### A.2 `sim2.py`: the cap replay (§2.2, §7)

```python
import json, sys, re, collections
from datetime import datetime
# Cap replay over annotated events, with a fact-key choice and optional guards.
# usage: sim2.py <events.jsonl> <sc14.jsonl> --key sess|exact|head --k N --guard none|blocked [-dump file]
args = sys.argv[3:]
def opt(n, d):
    return args[args.index(n) + 1] if n in args else d
KEY = opt("--key", "head"); K = int(opt("--k", "1")); GUARD = opt("--guard", "none"); DUMP = opt("-dump", "")
MAX = 3
ev = [json.loads(l) for l in open(sys.argv[1])]
sc = [json.loads(l) for l in open(sys.argv[2])]
def T(s): return datetime.strptime(s[:19], "%Y-%m-%dT%H:%M:%S")
shas = collections.defaultdict(list)
for r in sc:
    if r.get("sha"): shas[r["sid"]].append((T(r["ts"]), r["sha"]))
def sha_at(sid, ts):
    t0 = T(ts); best = None
    for t, s in shas.get(sid, []):
        d = abs((t - t0).total_seconds())
        if d <= 5 and (best is None or d < best[0]): best = (d, s)
    return best[1] if best else None
def norm(f): return re.sub(r'[0-9]+', 'N', f)
VERD = re.compile(r'good\s+to\s+close', re.I)
NOV = re.compile(r"good to close[^a-z]*(\*\*)?\s*(no([^a-z]|$)|not)|not (yet )?good to close", re.I)
PARK = re.compile(r"on purpose|deliberate|waiting|queued|in flight|still running|is running|watcher|land lock|not landed yet|park", re.I)
def rung_line_has(r, g):
    l1, l2 = r.get("l1", ""), r.get("l2", "")
    return g in l1 or (bool(VERD.search(l1)) and g in l2)
def lead(r):
    l1 = r.get("l1", ""); l2 = r.get("l2", "")
    if NOV.search(l1 + "\n" + l2) or "❌" in l1: return "no-verdict"
    s = l1.lstrip("*#>-• ")
    if s.startswith("⛔"): return "⛔-led"
    if s[:1] in ("📦", "🔧", "👤", "📤", "⏳", "📬", "🚀"): return "other-rung-led"
    if re.search(r"good to close[^a-z]*(\*\*)?\s*yes", l1, re.I) or s.startswith("✅"): return "yes/✅-led"
    return "prose"
bysid = collections.defaultdict(list)
for r in ev: bysid[r["sid"]].append(r)
res = []
for sid, seq in bysid.items():
    seq.sort(key=lambda r: r["ts"])
    segs = []; cur = []; prev = 0
    for r in seq:
        kind = "fired" if r["disposition"] == "fired" else "capped"
        c = r.get("count", 0)
        if kind == "fired" and c <= prev and cur: segs.append(cur); cur = []
        cur.append(r); prev = c if kind == "fired" else prev
    if cur: segs.append(cur)
    for seg in segs:
        n = 0; keys = collections.Counter()
        for r in seg:
            kind = "fired" if r["disposition"] == "fired" else "capped"
            arm = (r.get("arm") if kind == "fired" else r.get("suppressed_arm")) or ""
            facts = r.get("facts") or ""
            parts = arm.split("+") if arm else []
            guarded = False
            if GUARD == "blocked" and "ledger" in parts and "BLOCKED ON YOU" in facts and rung_line_has(r, "⛔"):
                rest = re.sub(r'(; )?BLOCKED ON YOU — .*?that IS your rung', '', facts).strip("; ")
                guarded = True
                facts = rest
                if not rest: parts = [p for p in parts if p != "ledger"]
            if not parts:
                new = "guarded-abstain"
            else:
                key = None
                if "ledger" in parts and facts:
                    if KEY == "sess": key = norm(facts)
                    elif KEY == "exact": key = facts
                    else:
                        h = sha_at(sid, r["ts"]); key = (norm(facts), h) if h else ("exact", facts)
                prose = [p for p in parts if p != "ledger"]
                if key is not None and keys[key] >= K and not prose:
                    new = "fact-latched"
                elif key is not None and keys[key] >= K and prose:
                    # ledger half latched; the prose arms still demand on their own
                    new = "fired-prose-only" if n < MAX else "capped"
                    if n < MAX: n += 1
                elif n >= MAX: new = "capped"
                else:
                    new = "fired"; n += 1
                    if key is not None: keys[key] += 1
            res.append(dict(ts=r["ts"], sid=sid, kind=kind, new=new, lead=lead(r), park=bool(PARK.search(r.get("l1","") + " " + r.get("l2",""))),
                            arm=arm, rung=r.get("rung"), facts=(r.get("facts") or "")[:70], l1=r.get("l1","")[:150], guarded=guarded))
fires_new = [x for x in res if x["new"] in ("fired", "fired-prose-only")]
fires_old = [x for x in res if x["kind"] == "fired"]
rec = [x for x in res if x["kind"] == "capped" and x["new"] in ("fired", "fired-prose-only")]
lost = [x for x in res if x["kind"] == "fired" and x["new"] not in ("fired", "fired-prose-only")]
C = collections.Counter
print(f"key={KEY} K={K} guard={GUARD}")
print(f"  fires: actual {len(fires_old)} -> new {len(fires_new)}  (recovered {len(rec)}, lost {len(lost)}, guarded-abstain {sum(1 for x in res if x['new']=='guarded-abstain')})")
print("  actual fires by lead:", dict(C(x["lead"] for x in fires_old)))
print("  new fires by lead:   ", dict(C(x["lead"] for x in fires_new)))
print("  actual fires on park/wait-worded closes:", sum(x["park"] for x in fires_old), " new:", sum(x["park"] for x in fires_new))
print("  recovered by arm/rung:", C((x["arm"], x["rung"]) for x in rec).most_common())
print("  recovered by lead:", dict(C(x["lead"] for x in rec)), " park-worded:", sum(x["park"] for x in rec))
print("  sessions with a recovered fire:", len({x["sid"] for x in rec}))
if DUMP:
    with open(DUMP, "w") as fh:
        for x in res: fh.write(json.dumps(x, ensure_ascii=False) + "\n")
```

### A.3 `ttship.py`: repeat index vs ship response (§3)

```python
import json, sys, re, collections, bisect
from datetime import datetime
# For every ledger fire on the unlanded fact: its repeat index on (sid, normalized facts),
# the HEAD sha session-continue logged on the same Stop, and whether a ship call followed
# before the session's next Stop.
ev = [json.loads(l) for l in open("/tmp/r2-C2/data/events.jsonl")]
ca = [json.loads(l) for l in open("/tmp/r2-C2/data/ca14.jsonl")]
sc = [json.loads(l) for l in open("/tmp/r2-C2/data/sc14.jsonl")]
def T(s): return datetime.strptime(s[:19], "%Y-%m-%dT%H:%M:%S")
stops = collections.defaultdict(list)
for r in ca: stops[r["sid"]].append(r["ts"])
for v in stops.values(): v.sort()
shas = collections.defaultdict(list)
for r in sc:
    if r.get("sha"): shas[r["sid"]].append((r["ts"], r["sha"]))
def sha_at(sid, ts):
    best = None
    for t, s in shas.get(sid, []):
        d = abs((T(t) - T(ts)).total_seconds())
        if d <= 5 and (best is None or d < best[0]): best = (d, s)
    return best[1] if best else None
def norm(f): return re.sub(r'[0-9]+', 'N', f)
ev.sort(key=lambda r: r["ts"])
rep = collections.Counter(); rep_sha = collections.Counter()
out = []
for r in ev:
    if r["disposition"] != "fired": continue
    if "committed-but-unlanded" not in (r.get("facts") or ""): continue
    if "ledger" not in (r.get("arm") or ""): continue
    sid = r["sid"]; key = (sid, norm(r["facts"]))
    rep[key] += 1
    h = sha_at(sid, r["ts"])
    rep_sha[(key, h)] += 1
    st = stops[sid]; i = bisect.bisect_right(st, r["ts"])
    nxt_stop = st[i] if i < len(st) else None
    ns = r.get("next_ship_t")
    dt = (T(ns) - T(r["ts"])).total_seconds() if ns else None
    before_next = bool(ns and (nxt_stop is None or ns[:19] <= nxt_stop[:19]))
    out.append(dict(ts=r["ts"], sid=sid[:8], k=rep[key], ksha=rep_sha[(key, h)], sha=(h or "?")[:9], dt=dt, before_next=before_next, l1=r.get("l1","")[:90]))
by = collections.defaultdict(list)
for o in out: by[o["k"]].append(o)
print("unlanded ledger fires:", len(out), " with a same-Stop HEAD sha from session-continue:", sum(1 for o in out if o["sha"] != "?"))
for k in sorted(by):
    xs = by[k]; dts = sorted(o["dt"] for o in xs if o["dt"] is not None)
    med = dts[len(dts)//2] if dts else None
    print(f" fire #{k}: n={len(xs)}  ship call before next Stop={sum(o['before_next'] for o in xs)}  any later ship call={len(dts)}  median s to next ship call={med}")
byk = collections.defaultdict(list)
for o in out: byk[o["ksha"]].append(o)
print(" same (fact, HEAD sha) repeat index, sha-known only:")
for k in sorted(byk):
    xs = [o for o in byk[k] if o["sha"] != "?"]
    print(f"   #{k}: n={len(xs)} ship-before-next-Stop={sum(o['before_next'] for o in xs)}")
if "-v" in sys.argv:
    for o in out: print("  ", o["ts"], o["sid"], "k=%d ksha=%d" % (o["k"], o["ksha"]), o["sha"], "dt=%s" % o["dt"], "B" if o["before_next"] else "-", o["l1"])
```
