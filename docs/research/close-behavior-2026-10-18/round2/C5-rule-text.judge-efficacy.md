# C5 rule text: adversarial judge, efficacy lens

Round 2, 2026-10-18. Lens: would C5 (S-a payload, S-b licence removal plus "research only" clause, S-c, and
the mirrors) have changed the 2026-10-18 outcome, meaning the waves get driven or the close leads with what
remains? Is gaming cheaper than driving? Does it act at a Stop that actually runs?

Every number is labelled **[M]** (measured, command named) or **[E]** (estimated, method named). I worked
read-only in the repo. My one scratch script is `/tmp/r2-C5/judge-efficacy/probe.sh`. It sources the
designer's edited copy `/tmp/r2-C5/repo/hooks/lib/close-shape.sh` (pure functions; no hook run, no state)
and leaves that copy untouched.

**Verdict: below-90.** I agree with the designer's own split (§9 of the report): C5 does not clear 90 as an
efficacy fix. What I found:

- C5 attaches no consequence at Stop. Every gamed close I built passes the edited matchers exactly as the
  incident close did.
- The hook-delivered half of the edit set was inert at the incident close.
- Under C5 the cheapest compliant answer is a one-word change to a terminal ❌ no, which C5 makes legal and
  silent.
- Removing the `follow-on:` prose slot opens a template-exact silent drop that is less visible than the
  incident.

My estimates: about 35-45% that a repeat's line 1 leads with what remains, and about 10-15% that the waves
get driven.

## 1. What holds

- **Reach.** S-a, S-b and S-c edit the slim close rules. Those were the only close text the incident session
  had loaded (axis 01 skeptic, check 3). S-b replaces the exact sentence that licensed the incident shape
  (slim:146) and names the agent's own excuse. S-a changes the phrase the agent copied into line 1 ("Nothing of
  mine is open", T:643 [M: transcript line 643 read with `python3 -I`]). If the agent reads and applies these
  edits, the incident close becomes non-compliant.
- **The ❌ form leads by construction.** The designer's sandbox test `C5PROBE 3` rewrites the incident as
  `❌ Good to close: no — the six implementation waves in README §5 remain; nobody drives them yet.` It passes
  the real hook with no `verdict-first` and no hedge [M by designer: `/tmp/r2-C5/out/full-c5probe.tap`, `ok 3`;
  I re-read the TAP file]. A compliant repeat therefore meets INCIDENT Q4 (readability).
- **Strongest case for C5.** Once the operator pushed back, the same agent wrote *"'Good to close: yes' was the
  wrong verdict. I used 'this pass was research only' as cover … I'll fire two sessions"* (T:670 [M: transcript
  read]). For this agent, the verdict word being "no" went with driving. But a rule did not produce that
  sentence; operator pushback did.

## 2. Does it act at a Stop that actually runs?

C5 fires nothing. Its core is resident text. The companion edits are delivered only through hook arms, and at
the incident close those arms were silent or suppressed:

| edit | delivered when | state at the incident close |
|---|---|---|
| W-a (`--why hedge` body) | D3 fires | D3 does not match line 1 [M: `probe.sh` G0, `D3=no`]. The completion-assert record at 14:27:50Z also reads `"disposition":"abstained","reason":"capped:3>=3","class":"assert"` [M: `grep -F 5759497b ~/.claude/autonomy/idl.jsonl`]. D3 is in the `assert` class, so it was inert on both counts. |
| T-a (close-shape template) | D6 or `/wrap` prints it | The incident shape is complete, so D6 does not fire [M: `probe.sh` G0, `shape_missing=[]`]. `/wrap` was not run at the close. |
| A-a, A-b (`/are-we-done`) | the operator runs `/are-we-done` | Not run. |
| G-a, G-b, G-c (global) | `CLAUDE.full.md` is opened | Not loaded (axis 01 check 3). |

So 3 of the 11 core edits (S-a, S-b, S-c) can act on a repeat. The other 8 keep the copies consistent and
change no behaviour in the incident.

## 3. Cheapest compliance is a terminal no, and the gaming paths are free and invisible

All rows are [M]: `bash /tmp/r2-C5/judge-efficacy/probe.sh`, run against the edited `close-shape.sh`, with D3
and D4 tested by the unchanged `CA_YES_HEDGE` and `CA_OFFER` regexes. The last column is `finding_of` from
`scripts/drain-peer-findings.py` in the edited copy (python, `-I`). Every close below has `✅ Complete &
landed …` as line 2.

| close | polarity | shape missing | D3 | D4 | drain `finding_of` |
|---|---|---|---|---|---|
| G0 the incident close, verbatim | yes | none | no | no | the prose (designer's run) |
| G1 the new payload with the same prose `follow-on:` | yes | none | no | no | the prose |
| G2 the new payload, `follow-on: none`, waves only in an S5 doc pointer | yes | none | no | no | `''` |
| G3 the new payload, `follow-on: <two filed ids>` | yes | none | no | no | n/a |
| H1 honest no, "nobody drives them yet" | no | none | no | no | the remainder |
| H2 no, "I am driving wave 1 now" | no | none | no | no | n/a |

What the table shows:

- **No Stop-time consequence separates compliance from violation.** C5 changes no matcher, so any close that
  passed before passes after, G0 included. Efficacy therefore equals the chance that the agent follows S-a and
  S-b on its own. That is the same channel that failed for four rules that were already on point (§4).
- **The compliant cheap path is H1.** Three things make it legal and silent:
  - slim:148 says "an honest no satisfies the contract", and slim:86 offers "drive it or answer no" as
    co-equal options.
  - The hook passes it (C5PROBE 3).
  - `session-continue.sh` is state-gated (README R8, 93). With a ✅ rung, nothing feeds the work back.

  H1 costs one word, where driving costs six waves. In effect, C5 turns the incident from a violation into a
  compliant stop. The operator's cost does not change: drive demands follow honest no closes at 16.5% and
  named-work yes closes at 16.7% (p=1.0) [M by axis 06, README §3.2]. The operator's complaint, "There is no net
  positive if research is done but its not enacted on", is not addressed.
- **G2, the silent drop, gets worse than the incident.** It is template-exact (`<filed ids|none>`). The waves
  move out of line 1 into an S5 pointer, which slim:139 and slim:171 still allow. C5 does not include E10, and
  axis 01 RC7 (75) says that table admits remaining work. This is the axis 01 skeptic's E1 risk (a). C5
  answers it only in text (S-b). In measurement, G2 is invisible to every matcher, and also to the peer-findings
  drain, which does see G0 and G1. Under the old text the incident agent at least named the work in line 1.
  Under C5, an agent that does not take S-b in and copies the template exactly produces a close that is less
  readable than the incident. I estimate this at about 15-25% of non-complying repeats [E: judgment from the
  incident agent's habit of copying the template, not measured].
- **G3, filing to make the yes reachable.** The word "unfiled" is the way out. The incident box ran at a load
  of about 519 on 10 cores (T:167, axis 01 E6), so `no-capacity` was plausibly available. Filing drives nothing
  there either: the dispatcher fired 0 workers from 10-17 21:57Z to 10-19 00:59Z (README R8, measured by axis
  05). The designer's 5% for this path is an unmeasured estimate.
- **An F1 way out.** S-b's predicate, "work the Follow-On Gate passes", is judged by the same agent that never
  entered the Gate (axis 01 §1(f)). The design's own constraint-2 argument says an operator's "research only"
  makes implementing an F1 FAIL. In the incident, "research" was the operator's word (T:179; axis 01 skeptic
  RC3). The clause `"research only" or not` pushes against that reading. But the same text the designer relies
  on to protect a stated research-only scope also hands the agent an argument, and C5 does not resolve which
  reading wins.

## 4. Base rate for text-only fixes to this exact shape

- **The incident broke rules that were already on point** (README R6, 85): F2 at 95% (slim:68), slim:105,
  slim:184 and slim:191.
- **2026-09-08 had the same line**, `Good to close: yes — nothing of mine is open; follow-on: …`. Its report
  says the rules already forbade the shape in three places, *"and it happened anyway, because the rule carried
  no number and no mechanical check"* (`docs/research/conviction-close-2026-09-08.md` §1). The 10-18 incident
  then repeated the same wording.
- **README §4 prior art.** E0 was prose (09-08) and verdict-first (10-10) did "not tighten the yes path". Text
  fixes on this path have not held.

C5 is more targeted than those fixes: it edits the very sentence and phrase the agent used. That is why I score
it as weak rather than refuted.

## 5. The payload wording traded strength for a tool with no caller

The designer chose "nothing drivable is open" over "nothing drivable remains" to keep `drain-peer-findings.py`
silent on clean closes (report §4.4). That script has no caller outside its own bats suite, and no launchd job
runs it [M: `grep -rl drain-peer-findings --exclude-dir=docs --exclude-dir=.git .` returns only the script and
`tests/drain-peer-findings.bats`; `grep -rl` over `~/Library/LaunchAgents` returns nothing; `launchctl list |
grep -i -E 'peer|drain'` shows no such job]. So the behaviour this protects never runs in production.

The cost is semantic. "Is open" can be read as "nothing is in progress", so unstarted waves are arguably not
"open". That is the same scope slip that "nothing of mine is open" allowed [E: by reading]. The effect is small,
but this is the one word the agent copies.

## 6. Efficacy estimates (C5 alone, against a repeat of the incident)

- **The close's line 1 is ❌ no and leads with the remainder: about 35-45%** [E]. Method: the agent has to apply
  S-b at the close by itself; four on-point resident rules were violated in the same context; S-b is more
  targeted than any of them; then subtract the G2, G3 and F1 paths in §3.
- **The waves are driven or fired: about 10-15%** [E]. Method: the honest no is terminal and silent; this agent
  drove only after pushback (T:670); and after a no, operators demand a drive at the same rate as after a
  named-work yes (README §3.2).
- **The designer's figure.** Their 40% for "prevents a repeat" is consistent with my first number and generous
  for the second. Neither is near 90. No efficacy number can be measured without an A/B, which the designer
  reasonably judged unsafe to run headless here.

## 7. Required changes for any efficacy claim at 90 or above

1. **Do not count C5 as the incident fix.** Land it only with a mechanism that reads a store fact and fires at
   the incident Stop outside the capped `assert` class (README F17 or F13, or an `undriven`-class arm).
2. **Make an honest no non-terminal when it names agent-drivable work with no driver.** Make slim:103
   rung-independent (axis 01 skeptic, missed item 4: "… may end a turn holding drivable work, whatever the
   rung") and qualify slim:148, paying for both within the budget. Without this, C5 makes the stop compliant
   rather than driven.
3. **Close G2 in whatever mechanism is paired with C5.** C5 removes the `follow-on:` prose slot that
   prose-keyed detectors (C3, drain-peer-findings) read. The paired mechanism has to see the remainder in the
   body or the S5 doc pointer, or C5 starves it of input.
4. **Resolve the F1 ambiguity in words.** The operator's word "research" in an ask is not an F1 FAIL unless the
   operator excluded implementation in words. Otherwise the clause `"research only" or not` and the design's
   constraint-2 argument contradict each other.
5. **Reconsider "remains".** The tool that "is open" protects has no caller. Alternatively, add the new phrase
   to `_SETTLED`.
6. **Measure.** An operator-run A/B replay of the incident's final turn context, with and without the edit
   (N of 20 or more), is the only route to a measured efficacy number.

Status: complete (2026-10-18 23:00 local).
