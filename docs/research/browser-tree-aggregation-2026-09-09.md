# The idle-browser-tree aggregation gap — cc-backlog `6c55ce7364d4`, REFUTED as filed

**Date:** 2026-09-09 · **Item filed:** 2026-08-20T12:48:11Z (20 days stale at dispatch)
**Verdict:** premise REFUTED on both load-bearing halves; a **different**, real gap found and closed.

---

## The claim under test

> An idle agent-browser tree holds ~976 MB across 11 processes indefinitely and NO rung watches
> aggregate per-tree memory. … Invisible to every existing rung BY CONSTRUCTION. This is an
> AGGREGATION gap — 11 individually-innocent processes summing to a real footprint.

Its evidence: `ps -Ao rss=,command= | grep agent-browser | awk sum` = 976 MB, called "~1.5x
capacity-alarm's own `per_session_mb_est` of 636 MB".

## Half 1 — the MAGNITUDE is an instrument artifact (REFUTED)

976 MB is summed per-process `ps rss`. `scripts/capacity-alarm.sh` already bans that instrument for
exactly this use, in its own header:

> `ps rss` summed over sessions OVERCOUNTS ~2.34x (it double-counts shared pages) — **do not use it
> to decide anything.** It is fine for per-process comparison, **wrong for a fleet total.**

A browser tree is the maximal case for that error: every helper maps the same ~84 MB Chrome
`__TEXT` segment and `ps rss` bills each one for it. Measured this session on a live agent-browser
tree spawned for the purpose (`agent-browser navigate https://example.com`, 11 procs — the item's
own count):

| instrument | reading |
|---|---|
| summed `ps rss` (the item's method) | **1155 MB** |
| `footprint(1)`, shared pages counted ONCE, identical pid set | **393 MB** |
| per-process `phys_footprint` sum (independent cross-check) | 398 MB |

**Overcount factor 2.94x.** The true idle footprint of an agent-browser tree is ~393 MB, not 976 MB.

The "~1.5x of 636 MB" comparison compounds the error rather than escaping it: 636 MB is *itself* the
mean of summed `ps rss` (`capacity-alarm.sh` ~line 1338), self-labelled **KNOWN-BIASED** and kept
deliberately as an **UPPER BOUND** so `est_room_sessions` errs toward under-promising headroom. Both
sides of the comparison were produced by the banned instrument.

Priced against the rung that actually decides whether the box swaps: 393 MB against a measured
**29.54 GB** reclaimable headroom — **1.3%**, with the warn floor at 8 GB.

## Half 2 — "invisible BY CONSTRUCTION" is false, and the refutation predates the filing (REFUTED)

`ca6b067b7` (**2026-08-19** — *one day before this item was filed*) added the per-coalition
footprint instrument to the same file: `read_coalition_true()` (libproc `PROC_PIDCOALITIONINFO` for
true membership) and `read_coalition_footprint()` (`footprint(1)` for shared-aware bytes).

Measured live, with the agent-browser tree up:

- all **10/10** tree pids — including the `ppid==1` daemon root — sat in coalition **117714**;
- `capacity-alarm.sh --json` reported `coal_id=117714 coal_fp_mb=4087 coal_fp_src=measured`.

The item's `ppid==1` premise creates no blindness: **a coalition keeps reparented orphans**, so
reparenting to launchd does not evict a process from the aggregate. The bytes were being measured,
with shared pages counted once, into a durable JSON field, the day the item was filed.

What *is* true and survives: **no threshold reads `coal_fp_mb`.** That is deliberate, documented,
and calibration-blocked — `ca6b067b7`'s own header says it "MEASURES ONLY … no threshold reads it",
because its fatal evidence is n=1 (an ORDERING, not a cutoff) and two attempts to mint a threshold
from it were already reverted (`a7ededdad`, `96c2932af`). So the item's own proposed remedy is the
thing that commit forbids doing without a calibration population.

### Why the item was filed at all — the proximate cause, now fixed

The coalition rung's header still said, 600 lines above the working instrument:

> Re-nouning needs a per-coalition FOOTPRINT instrument **that does not exist yet**.

Stale since 2026-08-19. A reader performing exactly the right premise check reads the *header*, not
the implementation 600 lines down, and concludes there is no aggregate instrument. This is the
repo's own `resident-policy-must-not-restate-perishable-facts` class occurring *inside a single
file*. Corrected in place (never deleted — the claim is the record of what was believed).

## Half 3 — the gap that IS live, on a population the item did not name

The brief's own branch applies: *"if the condition is still live but against a DIFFERENT set … that
different set IS the work."*

`read_coalition_true()` only ever considers a coalition containing a process whose `comm` is in
`TERMS = (iTerm2, kitty, ghostty, Ghostty)`. Measured 2026-09-09: **1 of 535 live coalitions had a
terminal member.** So one coalition was ever a candidate for the footprint sample, and a
browser-automation tree whose owning terminal app is gone is in **no aggregate the file records**.

A live instance, found by the sweep and still running:

```
coal=82373  members=11  no terminal member  →  visible_to_instrument = False
  66982  ppid=1   node  sevenrooms-bridge/sidecar/dist/index.js      1h30m  0.0% CPU
  74373  ppid=66982  Google Chrome --user-data-dir=~/.sevenrooms-automation-profile
                                   --remote-debugging-port=0
  + 5 renderers/helpers + 2 MTLCompilerService + 2 framework helpers
  summed ps rss = 1359 MB   ·   TRUE footprint = 528 MB
```

It is the item's *described shape* exactly — ppid-1 daemon, ~11 procs, idle at 0.0% CPU, holding
real memory unwatched — and it is **not agent-browser**. The item's own `grep agent-browser` matches
**0 of those 11 pids**, so the filing could not have found it.

Confirmed blind spots for this tree, all measured:

| rung | reading | why it misses |
|---|---|---|
| `browser-spin-guard.sh` | `verdict=clean pegged=0` | keys on pcpu ≥ 80 sustained; tree is 0.0% |
| capacity-alarm rung 4 | `max_proc_gb=1.31` vs `proc_warn_gb=3` | per-process; largest helper is 84 MB |
| capacity-alarm rung 6 + `coal_fp_mb` | coalition 117714 only | 82373 has no terminal member |
| `cc-reaper` | — | carries no memory field at all (0 hits in 3,224 lines) |

### The fix shipped

`capacity-alarm.sh` gains `read_automation_coalition()` and four **strictly additive** fields —
`auto_coal_procs`, `auto_coal_id`, `auto_coal_fp_mb`, `auto_coal_fp_src`. Live reading on the tree
above: `auto_coal_procs=11 auto_coal_id=82373 auto_coal_fp_mb=528 auto_coal_fp_src=measured`.

Design constraints, each pinned by a test:

- **The predicate is `--remote-debugging-port` in argv, not "looks like a browser."** That flag *is*
  the agent-driven signature; a human's browser lacks it and an automation daemon cannot work
  without it. It separates cleanly here: coalition 82373 matches, and Discord's 11-member Electron
  coalition — which a comm-based "is it Chrome" test **does** hit — does not.
- **Terminal coalitions are subtracted**, so this can never return the coalition the existing
  instrument already measures (a duplicate reading wearing a new field name). Mutant `M-A5`.
- **It measures only.** No threshold, no verdict change — same n=1 reason as `ca6b067b7`. Source
  invariant `AC4`, sibling of `CF4`.
- **Own damping stamp**, so the two expensive `footprint(1)` samples cannot starve each other.
- Own kill switch `CC_CAP_AUTO_COAL=0`; fails silent and separate; a box with no automation tree
  reports `none`, never a fabricated `0`.

## What was deliberately NOT done

**No aggregate-memory threshold was minted.** The item's remedy ("a rung that watches aggregate
per-tree memory") is precisely what `ca6b067b7` forbids pending a calibration population, and what
was reverted twice before. Conviction that a threshold should be built now: ~10%. The recorder is
what makes a future calibration possible; the threshold is a later pass with a population behind it.

## Reusable lesson

**An instrument ban in a header is a claim with a shelf life, and so is the absence it justifies.**
Two independent staleness failures produced this item: a *number* produced by an instrument the same
file bans (2.94x high), and a *sentence* asserting an instrument does not exist one day after it
landed. Neither is a defect in the analysis that filed it — both are defects in what the analysis
could read. When you ship an instrument, grep the file for prose that says it does not exist.

Second, separable: **a filter chosen for one population silently defines the limit of every
aggregate built on it.** `TERMS` was correct for the 2026-07-31 *terminal* coalition panic, and it
quietly made 534 of 535 coalitions unmeasurable. When an instrument selects its subject, ask what
share of the world that selector excludes — here it was 99.8%, and one line of measurement showed it.
