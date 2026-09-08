# The postland corpus SIGKILL sender — named, cured, and verified cured

Closes backlog row `b6f03adab3f9` ("postland corpus is SIGKILLed from OUTSIDE, sender still
unnamed", filed 2026-08-10). Measured 2026-09-08 against trunk `624be66ec`.

## Answer

The sender was `bin/cc-reaper`'s **stuck-wrapper arm**, and it was cured on trunk by
**`9f9a64bb4`** (2026-09-02T09:01:49Z, *"stuck-wrapper matched a command line, not a name — and it
was eating postland-verify"*). The row was already open on that mechanism as `b83f4a2ba219`
(filed 2026-08-24, still claimed); this doc adds the part that row could not have: **six days of
post-fix data showing the cure holds.**

Mechanism, from the cure's own diff:

```
- args[p] ~ /cc-close-attrib/                              # unanchored SUBSTRING over whole argv
+ args[p] ~ /^([^ ]*bash )?[^ ]*cc-close-attrib( |$)/      # the command WORD
```

`postland-verify` runs its corpus as one command line naming all ~558 suite paths, one of which is
`tests/cc-close-attrib.bats`. So the predicate `comm==bash && args ~ /cc-close-attrib/ && secs>=1800`
matched **the corpus itself**, every time it ran past 1800 s. `garbage_sweep` does
TERM → `sleep 3` → KILL, which is why one sender produced both signal 15 and signal 9.

## Verification that it is cured

| window | runs | signal-killed | rate |
|---|---|---|---|
| 2026-08-20 .. 09-02 | 281 | 154 | **55%** |
| 2026-09-03 .. 09-08 | 33 | **0** | 0% (rule of 3: true rate < 9%) |

Last signal-kill: **2026-09-02T10:58:08Z**, ~2 h after the cure landed. P(0 kills in 33 trials at
the prior 55%) ≈ 3e-12.

Two controls, because a quiet box would produce the same zero:

- **Load confound — refuted in the opposite direction.** Peer lands per day nearly *doubled* across
  the cliff (mean 89.9/day for 08-20..09-02 → **167.0/day** for 09-03..09-08, `~/.claude/land.log`).
  Kills went to zero while the load that was supposed to cause them rose.
- **The mitigation is not doing the work.** `launchctl getenv CC_REAPER_GARBAGE` reads **empty** —
  the temporary `CC_REAPER_GARBAGE=0` mitigation named in `b83f4a2ba219` is *not* in force. The
  garbage arm is armed and still not killing, so the code fix is what holds.

Liveness: `~/.claude/bin/cc-reaper` is a per-file symlink into the shared checkout, whose HEAD
contains `9f9a64bb4`. Landed **and** live.

## What the filed row got wrong

**Its named suspect does not exist.** The row cited `ship-land.sh:676` recording a worktree-UNSCOPED
`pkill -9 -f bats-core/bats` "as a measured peer-killer class". There is no `pkill` anywhere in
`scripts/ship-land.sh`; it was removed by **`497bd796a` (2026-07-26)** — *two weeks before this row
was filed*. What survives at `ship-land.sh:1679` is a **comment** describing that historical
incident, and `hooks/validate-bash.sh:679` DENIES the unscoped form at the chokepoint
(`c57851064`, same day). The row read a post-mortem comment as a live call site.

**The prescribed correlation refutes the peer-land hypothesis.** The row's next step was to correlate
kills with peer `/ship` gate windows. Run over n=254 signal-killed cuts against every land's
`[ts - total_s, ts]` window:

| population | ≥1 peer land live at that instant |
|---|---|
| signal-killed cuts (n=254) | **29%** |
| non-signal cuts (n=129) | 36% |
| random instants (n=2000, negative control) | **31%** ← base rate |

Kills are at *or slightly below* the base rate. A live peer land carries no signal about the kill.
Correct, in hindsight: the real sender was a launchd daemon on a timer, not a peer's gate.

**Its consequence clause is stale.** "last-green has not moved since 10:31Z" and "every advance goes
through T2's absence-of-evidence door" are both false now. Newest GREEN is 2026-09-03T16:23:25Z, and
since 09-03 the corpus reaches a **real verdict on nearly every sweep** — 27 REDs, no truncations.
The remaining blocker is a genuine rotating red band (`cc-reaper`, `compressor-sentinel`,
`handoff-fire-completion-push`, `idle-slope-sweep`, `goal-inert-watch`, `deathwatch-watchfile`),
which is a different problem with different owners — not an absence of evidence.

## The transferable lesson

**A comment describing a killer reads exactly like the killer.** Two of this row's three clauses
came from grepping a term and landing on prose *about* a past incident: `ship-land.sh:1679` for the
`pkill`, and the "SIGSTOP-only" exclusion of `compressor-sentinel` (which gained a real SIGKILL rung
in `9d5e64de7` on 2026-08-24, though its `^node` comm filter still exonerates it — it never sends
TERM at all). A grep hit is a *string*, and a repo that documents its own post-mortems in place will
hand you the string long after the code is gone. **Check that the match is a call site before
treating it as one** — `git log -S` on the pattern answers it in one read, and here it would have
said "deleted 2026-07-26" before any of the twelve measurements were taken.

The instrument that finally named it was in-band, not forensic: `rc_why()` in `postland-verify.sh`
prints the signal number per cut into `runner.log`, and `cut_why` (landed `c4294e9ff`,
2026-09-08T00:19Z) now carries the same reason into the stamp store, so a recurrence is
self-naming rather than needing a session like this one.
