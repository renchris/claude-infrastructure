# An alarm describes the tier it measures, not the whole ladder

**2026-09-20.** A handoff arrived with a blocker stated as settled fact, and a decision built on top
of it:

> W5's DoD demands "deploy-live.sh output shows an ADVANCE". That cannot be met today:
> `cc-blockers` ⇒ `trunk-red PERSISTENT-NOT-GREEN`, `deploy-wedged NO-GREEN-AHEAD` (green
> `c08dc78ae590` sits 205 commits behind live HEAD). **The live layer stays pinned until a green
> exists, so a converge kick cannot clear it** — the fault is the failing suites, not launchd.
> DECIDE FIRST whether to (a) fix enough of that to earn one green, or (b) record the converge half
> as blocked.

Both offered options were expensive: (a) is repairing six unrelated suites; (b) is shipping a wave
with half its DoD unmet. The real answer was neither, and it took one read-only command:

```
$ CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh --dry-run
deploy-live: !! DEGRADED deploy — no GREEN stamp among the newest 200 commits of origin/main;
             taking the newest NOT-RED commit instead
deploy-live: DRY RUN — would fast-forward 6a0a05f8c344 → 7c7a5261b947
```

The converge then ran and advanced, and `deploy-parity-assert.sh` came back clean.

## Why the alarm was right and the conclusion was wrong

`NO-GREEN-AHEAD` is a true statement about **tier T1**, which requires a GREEN stamp. The converger
is a **ladder** — T1 / T1H / T2 / T3 — and T2's door is *absence of evidence*: it takes the newest
**NOT-RED** commit. "No green exists" is precisely the condition under which T2 is the operative
tier, so the alarm's own text names the state in which the thing it appears to forbid is available.

The alarm is not at fault. It reports the health of the preferred path, which is what an alarm
should do. The error is reading a tier-scoped signal as a statement about the whole mechanism — and
the reason that reading is so easy is that the alarm's KIND is phrased as a property of the world
(`deploy-wedged`) rather than of the tier it measured.

This is [a refusal bounds the TOOL, not the world] one level up: here nothing even refused. A
*monitor* was read as a *verdict*.

## The rule

**Before accepting that an actuator is blocked, run the actuator's own dry-run.** An alarm, a
status tool and a dashboard all report on a path; only the actuator knows how many paths it has.
The dry-run is the cheapest possible instrument — read-only, seconds — and it answers the question
the alarm cannot: *given today's state, what would you actually do?*

Corollaries worth carrying:

- **A multi-tier mechanism needs its tier named in any claim about it.** "The converge is wedged" is
  unfalsifiable; "T1 is unreachable because no green stamp exists" is true, checkable, and does not
  imply the conclusion.
- **Inherited blockers are claims, not measurements** — the same as
  [a pre-existing red is a claim, not a measurement](a-pre-existing-red-is-a-claim-not-a-measurement.md).
  A handoff that hands you a decision built on one has already spent its own verification budget;
  re-run the cheap arm before spending yours on the expensive options it offers.
- **Watch for a framing that offers only costly options.** Two expensive choices and no cheap one is
  itself evidence that a premise upstream has not been tested.
