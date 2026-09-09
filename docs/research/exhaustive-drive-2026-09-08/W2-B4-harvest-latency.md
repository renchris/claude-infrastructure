# W2-B4 — harvest latency: does a finding named in a session's last close ever reach a store?

**Permanent loss is 38.3 % (74 of 193 closes) on the most generous reading and 78.8 % (152 of 193)
once same-second self-commits are excluded; the matcher's hand-read precision is 35 %, and every one
of its errors is a FALSE HARVEST, so 38.3 % is a FLOOR, not an estimate. Median harvest latency is
0.07 days, which is itself the finding: 78 of the 119 apparent harvests land within 0.5 days and are
the closing session's own trailing commit, not a later reader picking the work up. CROSSES 90 (95).**

The decision rule this wave carried was: permanent loss < 5 % ⇒ a peer-findings drain producer is
REFUTED; ≥ 15 % ⇒ it crosses 90. Every reading of this population clears 15 % by more than a factor
of two, and the corrections all push the same way.

## The numbers

| quantity | value |
|---|---|
| transcripts with mtime in the 14-day window (four roots) | 820 |
| of those, sessions with ≥1 turn-final close | 518 |
| LAST closes that NAME drivable work as remaining | 208 (40.2 % of closing sessions) |
| measured population (≥1 distinctive token after the df filter) | **193** (15 dropped) |
| harvested within 1 day | 89 / 193 = 46.1 % |
| harvested within 3 days | 105 / 193 = 54.4 % |
| harvested within 7 days | 119 / 193 = 61.7 % |
| **permanent loss (never appeared within 7 days)** | **74 / 193 = 38.3 %** |
| median harvest latency (all hits) | 0.07 days (n = 119) |
| **harvested by a LATER reader (≥ 0.5 d)** | **41 / 193 = 21.2 %** |
| ⇒ **loss once simultaneous hits are excluded** | **152 / 193 = 78.8 %** |
| matcher precision, hand-read sample of 20 | **7 / 20 = 35 %** |

Latency bands, and they are the argument:

```
  0.00-0.02 d :  40 hits (20.7% of the population)
  0.02-0.50 d :  38 hits (19.7%)
  0.50-2.00 d :  22 hits (11.4%)
  2.00-7.00 d :  19 hits ( 9.8%)
```

Two fifths of the population "harvests" inside half a day. A commit landing 0.01 days after a close
was not written by someone who READ that close; it is the same session's own trailing commit, or a
sibling committing concurrently in another worktree. The B4 question is whether a finding a session
NAMED AND LEFT gets picked up by anything later, and for that question only the ≥ 0.5 d stratum
counts: **21.2 %**.

## Method

`scripts/measure-harvest-latency.py` (committed, with `--selftest` green 7/7). It imports
`scripts/measure-closes.py` and reuses that module's `iter_transcripts` and `extract_closes`
verbatim rather than re-deriving the corpus walk or the close definition.

```
python3 scripts/measure-harvest-latency.py --days 14 --sample 20
python3 scripts/measure-harvest-latency.py --selftest
```

For each transcript in the window it takes the session's LAST turn-final close, keeps it if the
matcher fires, lifts up to 3 distinctive tokens (backticked spans, `*.sh|py|md|ts|bats` paths,
kebab/snake identifiers of 3+ parts, 12-hex ids), drops any token appearing in more than 5 % of the
closes themselves, and then looks for the earliest appearance of any token, strictly after the close
and within the horizon, in: `git log --all --no-merges` of the repo named by that transcript's own
`cwd` (subject + body), `~/.claude/autonomy/backlog.jsonl` rows, and `~/.claude/autonomy/decisions/*.json`.

The matcher (`--show-matcher` in the source) fires on a 🔧 or 📦 rung or on
`follow-on | follow-up | backlog | still needs/open/to | remains/remaining | not (yet) done |
left to/for | next step | deferred | parked | unfinished | filed it/as/a | TODO | worth
doing/building/fixing`. It is deliberately **wider** than `completion-assert.sh`'s `CA_HANDOFF`,
which is about work that is the OPERATOR'S; B4 is about work that is anyone's and was named rather
than done.

The selftest is a polarity control, not a smoke test: a hit 2 days out must be found at exactly
2.0 d, must NOT leak into the 1-day horizon, a token absent from the corpus must report nothing, a
commit BEFORE the close must not count as harvesting it, the matcher must fire on 🔧 and must NOT
fire on a clean ✅ close, and token extraction must recover both a path and a 12-hex id.

## Population and every excluded stratum

- **302 of the 820 transcripts had no turn-final close at all** and are excluded. This is the
  largest and most adverse exclusion: a session that died mid-turn cannot have written a close, and
  it is exactly the population whose findings are most likely to be lost. Their exclusion biases the
  measured loss DOWNWARD.
- **15 closes** named work but yielded no token surviving the document-frequency filter; excluded
  because unmeasurable, not because harvested.
- **Sessions whose `cwd` is not inside a git repository** get store-only matching (backlog +
  decision packets, no git corpus). They can only lose hits, never gain them.
- **The backlog and decision stores are read at `~/.claude/autonomy/`** only. That is correct rather
  than partial: the other three account config dirs symlink into it, so it is one store.
- Sidechain (subagent) records are excluded upstream by `extract_closes`; a subagent's prose is not
  a close.

## Verdict for W3 — CROSSES 90 (95)

A peer-findings drain producer is worth building. Between a fifth and a third of sessions that end
by naming drivable work have that work reach no store any later session reads, and the true figure
is above both bounds for the three reasons above. Conviction 95 rather than higher because the
matcher's 35 % precision is measured on 20 pairs, not on the full 119.

**What the number does NOT license.** It does not say a drain producer would recover 78.8 % of
anything: a producer can only act on what a close actually names, and this instrument cannot tell a
named finding that was worth harvesting from one that was correctly dropped. The rate says the
CHANNEL is lossy; it does not price the cargo.

## Fail direction — and it points the other way

The named fail direction was that a token grep matching a common word inflates "harvested". It did,
badly, and the hand read is how it was caught. Of 20 matched pairs: **7 real, 13 spurious**.

Real hits were carried by intrinsically distinctive tokens — a 9-char sha (`4bef0f1af` → the commit
citing it), a 12-hex backlog id (`8945d8e750ba` → that row's own `claim` event at 4.77 d), a coined
slug (`offbox-core-cure`). Spurious hits were carried by tokens that are common in the COMMIT corpus
even when rare among closes: `claude` (twice), `master`, `origin/master`, `opacity`,
`handoff-fire.sh`, `slop-lint.sh`, `MEMORY.md`, `ship-land`. Note `MEMORY.md` and `slop-lint.sh`
specifically: the close's genuinely distinctive token did not match, and a generic sibling token
matched instead — so the pair is scored harvested on evidence about a different piece of work.

**The df filter was measured against the wrong corpus.** It drops a token appearing in > 5 % of the
CLOSES; the inflation comes from tokens that are common in the HAYSTACK. A filter keyed on document
frequency in the git corpus would be strictly better, and is the one improvement to make before this
instrument is re-run.

Because every matcher error is a false POSITIVE harvest, correcting for the 35 % precision moves
permanent loss UP (38.3 % → ~ 79 % uncorrected-stratum, and the ≥ 0.5 d stratum from 21.2 % harvested
toward ~ 7 %). **A wrong reading of this measurement therefore under-states the loss it found; there
is no error direction available that rescues REFUTED.**
