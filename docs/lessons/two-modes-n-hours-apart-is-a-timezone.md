# Two modes exactly n hours apart is a timezone, not a mechanism

**Rule.** Before joining two stores on time, census the RAW offset between them over the whole
population and require it to be unimodal. A bimodal offset whose modes sit exactly n hours apart is
a clock difference (a zone, a DST edge, a machine that moved) and never a behaviour of the subject;
a median over such a population validates neither mode.

**Incident (2026-09-19, claude-infrastructure, axis G of the subagent-lifecycle wave).** A
measurement joined `~/.claude/logs/teammate-lifecycle.log` (stamped in local time) to teammate
transcripts (UTC) and reported that Claude Code 2.1.260 had multiplied teammate residency after
work finished by ~2,400× — median 0.05 min on 2.1.220 versus 120.05 min on 2.1.260, "perfectly
bimodal, 0 in between", 219.7 teammate-hours of cost. A follow-up on the same instrument then
"found" that the close hook was not invoked at turn end at all and first ran two hours later.
Both were artefacts. The box's `/etc/localtime` had been re-pointed from `America/Los_Angeles` to
`America/Chicago` on 2026-09-06 (symlink mtime), two days after the fleet moved to 2.1.260 on
2026-09-04; the log carried no lines between 09-04 and 09-07, so the two eras never mixed and the
version was a near-perfect proxy for the zone. With the era-aware conversion every one of the 206
closes lands under a minute on both versions (median 3 s); the residency figure fell from 219.7 h to
29.7 h, of which 23.7 h is ordinary turn-end latency summed over members.

**Why the instrument's own checks passed.** The file asserted the join was sound because "the
median offset is +0.1 min over 206 pairs with only 3 negatives" — a median taken over two modes;
and every later corroboration ran inside the contaminated conversion and agreed, because within
each era the conversion is self-consistent. The sibling adversarial axis caught it with one
hand-converted pair (`evgo-policy`: log 19:27:18 CDT = 00:27:18Z, transcript 00:27:20Z, closed 4 s
later), and the lead confirmed on 12 samples with the system zone rules
(`datetime.strptime(...).astimezone().astimezone(utc)`).

**How to apply.**
- Any time a delta between two stores is computed, print the histogram of the raw offset first; a
  second mode at ±1 h, ±2 h, ±7 h is the tell, and a delta distribution with an empty middle is a
  stronger tell than any median.
- Convert local stamps with the zone rules in force **at the stamp's date**, never with a fixed
  offset and never with today's zone alone; on this box `/etc/localtime`'s mtime records when the
  zone changed.
- When a "version effect" coincides with an infrastructure change to within days, test the
  infrastructure change first — it is the cheaper hypothesis and it can masquerade as any effect.
- Companions: `process-start-time-renders-in-ambient-timezone` (the same class, one store),
  `two-producers-one-moment-different-cadences` (a join whose two sides do not share a clock).
