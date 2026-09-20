# A transient fault is explained by whatever was standing — and the remedy inherits its permanence

cc-backlog item `2f9396f050bc` (the correction), closing `86f564bc7f4f` (the refuted row),
2026-09-20.

## The incident

At 06:05Z a session measured kitty's remote-control channel from pane 343 and found it dead:
`it2 session list --json` returned **rc=124, 0 bytes, 0 pane ids**, twice, bounded 8 s and 10 s. In
the same breath it measured a standing fact: kitty's main process (pid 73832) sits in the Darwin
**BACKGROUND QoS band at PRI 4** while its kittens run at PRI 31. It filed row `86f564bc7f4f`
joining the two:

> its remote-control channel is **consequently** DEAD … OPERATOR-ONLY because the only reliable
> remedy is restarting kitty … it is the same restart row `b015a245aa4f` already needs for the
> patched build, so the two can be taken together.

**A kitty restart closes every pane and every agent session in them.** The row sat `blocked` in the
operator's queue for four hours, paired with an unrelated row that makes the restart look cheap.

Three independent measurements refute the causal claim:

| when | pid | PRI | RC probe | load |
|---|---|---|---|---|
| 06:05Z — the filing | 73832 | 4 | rc=124, 0 bytes, 0 ids (×2) | not recorded |
| 10:15Z — the filer re-measures | 73832 | **4** | **rc=0**, 3312 bytes, panes enumerated | not recorded |
| 15:29Z — this item re-measures | 73832 | **4** | **rc=0**, 3063 bytes, ×2 at 8 s and 10 s | 7.89 9.99 12.16 |

Same process, same band, no restart (`etime` 3-14:15:42, started Wed 16 Sep 20:13:53). **PRI 4 is
not sufficient for RC death**, so the remedy rested on nothing.

The cause was measured independently, by a different investigation that landed as `90eda0040`
(`tests/handoff-remote-pane-term.bats`, on trunk): the same socket on the same box, **load 197 on
10 cores** when it timed out and **0.06 s over 3 consecutive calls at load 17**. The fault is
saturation. Note what that commit is careful to say — the *symptom* was real and the socket
genuinely did not answer; what is refuted is only the **cause**, and therefore the **remedy**.

## The mechanism — why the standing property gets named

At the moment a transient fault is observed, the only properties still available to explain it are
the **standing** ones. Load at 06:05Z was gone by the time anyone asked; PRI 4 was still there, and
still there at 10:15Z, and still there now. A standing property is present at every probe by
definition, so it survives into the write-up **by construction**, not by evidence. That is the
whole inferential defect: co-observation was read as causation because the co-observed thing was
the only thing left to read.

Then the remedy inherits the property's permanence. A transient fault wants *wait and retry*; a
standing fault wants *change the standing thing*. Because the diagnosis named a standing thing, the
remedy became irreversible and fleet-wide — and it was addressed to the one actor who cannot
evaluate it, the operator, in a queue that does not re-check its own premises.

Two probes 8 s and 10 s apart are **one moment**, not a timescale. They were reported as `twice`,
which reads like replication and is not: replication across a fault's own timescale is what
separates a spike from a property, and both probes sat inside the same spike.

## The rule

**A remedy's blast radius sets the evidentiary bar for the diagnosis underneath it.** Before filing
a remedy that destroys live state:

1. **Record the transient covariates at the fault, not just the standing ones.** `uptime`,
   contention, queue depth. The one number that would have settled this — load — was free to
   capture at 06:05Z and unrecoverable afterwards.
2. **Re-measure across the fault's own timescale.** Probes inside one spike are one sample. The
   filer's own 4-hour re-measure is the cheapest possible control and it is what caught this.
3. **Price the remedy against the evidence.** "Two 8-second timeouts" does not buy "kill every
   agent session on the box." If it is destructive and the evidence is a moment, it is not a
   remedy, it is an observation.
4. **Never let a destructive row ride along with an unrelated one.** `86f564bc7f4f` pointed at
   `b015a245aa4f` so "the two can be taken together" — which converts a restart the operator had
   already accepted for a font into cover for a restart nothing justified.

## Companions

- [Two causes, one rc](two-causes-one-rc-ask-a-lower-layer.md) — the diagnostic half, and the cure:
  `kitty_socket_accepting` asks connect(2), which cannot drift, and retries the accepting-but-silent
  state. That is what "measure whether the socket answers under load" now means in code.
- [Cause refuted ≠ effect discharged](cause-refuted-effect-discharged.md) — the payload here is the
  EFFECT (an unreachable RC channel corrupts fire/teardown identity: three fires reported rc=124 and
  ran cleanup while their sessions launched anyway, leaving two unstamped W4 twins with no custody
  rows, plus a self-close aborting on `pane NOT among the 0 id(s) enumerated`). That effect is real
  and is cured for the pane resolver by `90eda0040`; it did not die with the refuted cause.
- [A cure is verified only under the load that caused it](a-cure-is-verified-only-under-the-load-that-caused-it.md)
  — the mirror image: a clean reading on a quiet box is a fact about the box.
- `filed-blocker-is-never-revalidated` (memory) — the systemic half. A blocked row is filed once and
  never re-checked, so a dead premise demands action forever. This incident is that rule with the
  demanded action made **irreversible**.

## What was NOT rewritten

Row `dbb994e2878e` attributes its self-close aborts to a missing successor pane↔tty binding.
`86f564bc7f4f` suggested that was "a SYMPTOM of the dead channel". That suggestion rests on the same
refuted premise and was deliberately **not** applied — `dbb994e2878e`'s record carries `add`,
`block`, `link` and no `update`. A refuted row must not be allowed to re-diagnose its neighbours on
the way out.
