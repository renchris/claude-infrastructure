# Re-pricing the 2.1.221–2.1.237 hold — the hold is gone, the cost it named is not

**Date:** 2026-09-10 · **Item:** cc-backlog `7d0c581fe2fb` · **Supersedes on the facts:**
`docs/research/function-hooks-91870-2026-09-03.md` §2b(iii), action 4 · **Status:** research, no code change

## The answer

The item asks us to re-price a hold. **There is no hold left to price.** It was discharged on
2026-09-08 (`~/.claude-versions/MANIFEST.jsonl`, the 2.1.260 row) and this box has run **2.1.260**
as its live binary since 2026-09-03. The premise of §2b(iii) — *"it needs 2.1.224+; MANIFEST holds
the band"* — was already false when the item was filed.

**But the cost the item named survived the hold's death, on a different cause.** §2b(iii) priced the
wake subsystem as a *forgone option*: we could not have the socket, so we paid to hand-build one.
That is no longer the shape. We **have** the socket — it is exported into this session's own Bash
environment — and we still run the hand-built subsystem beside it. The cost is now **live duplication,
not a forgone option**, and it is the larger of the two. (Same shape as the corpus rule
*cause refuted ≠ effect discharged*: refuting the cause does not discharge the effect.)

## What was measured, first-hand, on the binary we run

| Claim | Measurement |
|---|---|
| Live binary | `2.1.260` — `CLAUDE_CODE_EXECPATH=~/.claude-260/…/claude.exe`, `AI_AGENT=claude-code_2-1-260_agent` |
| Socket present | `CLAUDE_CODE_MESSAGING_SOCKET=/tmp/cc-socks/<pid>.sock` + `_TOKEN` exported **into the Bash tool env** |
| A/B control | `strings` on the bundle: 2.1.260 = 12 hits / 2.1.220 = **0**. The prior pin genuinely lacked it |
| Socket path | `/tmp/cc-socks/<PID>.sock` — derivable by any external process from `ps`, no secret needed |
| **Auth on darwin** | `function jEt(){return P()==="windows"}` — `authRequired` defaults **false** off Windows. The guard is `srw-------` (0600) + peer-uid checks, **not** the token |
| **External delivery** | **PROVEN.** A plain `python3`, with `CLAUDE_CODE_MESSAGING_TOKEN` unset from its env, connected to a live session's socket and delivered a message that arrived in the conversation |
| Directory | `~/.claude*/sessions/<pid>.json` — `sessionId`, `procStart`, `name`, `status: idle\|busy\|waiting\|shell`, `messagingSocketPath`, `peerFeatures:["notify_idle",…]` |
| Token on disk | `~/.claude*/sessions/<pid>.<sha256>.key`, mode 0600, holds `peerToken` + `procStart` + `pidDomain` |
| Wire format | newline-delimited JSON. `{"type":"user","message":{"content":"…"},"priority":"now"}`; `type:"control"` carries `notify_when_idle`, `peer_idle_notice`, `rename` |
| Enqueue | `Routed user message to queue (priority=…)` → `onEnqueue()`; the record is stamped `isMeta:true`, `skipSlashCommands:true` |
| Anti-pid-reuse | the server records `verifiedPeerPid` **and** `verifiedPeerProcStart`; a sender may pin `session_id` and a mismatch is dropped |

The vendor independently arrived at two disciplines this repo learned the hard way: the `(pid,
procStart)` pin, and a `status` enum that separates *busy* from *idle* from *waiting* — the latter
is `hooks/lib/session-busy.sh`, which we landed on 2026-09-09 (`ec4b53daa`), one day before this read.

### Coverage — and two denominator errors it cost to avoid

Naive counts are wrong in both directions here, so the numbers below are leaf-corrected (wrapper
processes excluded: a resume runs under a wrapper carrying the same argv, and counting both doubles
the population) and registry-union across all five config dirs (**the registry is sharded per config
dir** — `.claude=6 .claude-next=6 .claude-secondary=3 .claude-tertiary=6 .claude-quaternary=5`).

- **19 leaf sessions · 18 with a bound socket (94%) · 18 in the registry (94%).**
- **46 socket files, 26 of them STALE** (no live pid). There is no sweep; a consumer must
  liveness-check, which is why the binary ships its own 250 ms connect-probe.

Two readings were rejected on the way here, both from bad denominators: **38%** (registry rows in
*one* config dir against leaf sessions in *all* of them) and **62%** (registry rows against socket
*files*, 26 of which are dead — comparing a live-only store to a store with no sweep manufactures a
gap). The corpus rule *police the denominator* applies to this measurement specifically.

## Tracker: the reason to stay away in August has mostly closed

The 2026-08-12 MANIFEST row held five open inbox bugs against adoption. Re-checked live today:

| Issue | Aug 2026 | 2026-09-10 |
|---|---|---|
| #85886 daemon-hosted bg session binds no socket | OPEN | **CLOSED** 2026-08-17 |
| #85412 silent bind failure, multiple sessions at once | OPEN | **CLOSED** 2026-09-08 |
| #85690 SendMessage self-delivery | OPEN | **CLOSED 2026-09-10 (today)** |
| #85497 registry row written, socket never bound | OPEN | **OPEN**, last touched 2026-08-20 |
| #85764 ListAgents omits in-process subagents | OPEN | **OPEN** |

Three of five closed. Neither survivor is a delivery-correctness defect on an established socket:
#85497 is a bind race (its failure mode is exactly the *stale/absent* case a liveness check already
covers) and #85764 is agent enumeration, not session-to-session delivery. The surface is under
active repair through 2.1.267 — 2.1.260 fixed a ListAgents phantom twin, 2.1.261 fixed an offline
Remote Control send reading as delivered, 2.1.265 fixed a `--bg` session retired mid-turn by an
arriving message.

**The containment discharge still holds, on its original evidence.** Nothing in 2.1.238–2.1.267
restores a spawn cap or touches `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`; the discharge came from
reading the binary's own `de>=be` comparison, not from a changelog line, and that reading is
unchanged. npm today: `stable=2.1.236`, `latest=2.1.267`, `next=2.1.268` — the dist-tag divergence
remains a standing property, not an anecdote.

## The partition — what the socket can and cannot take

Measured by a census agent over the real population (`handoff-fire.sh` is **12,047 LOC**, not the
10,622 §2b(iii) quotes — that figure was already stale):

- **~36% of subsystem LOC (8,708 / 24,177)** is transport the socket can carry.
- **~60% (14,563)** it structurally cannot.
- The single load-bearing row it cannot carry: **delivery to a session that is not running yet.**
  There is no listener, no store-and-forward, and no local spawn primitive — the binary *reaps* dead
  sockets rather than queueing for them. That row alone is why `handoff-fire.sh` exists, and 133
  files call it.
- Also structurally out of reach, unchanged from the 2026-09-03 analysis: pane placement and the
  whole terminal side, worktree provisioning, account/model/effort launch identity (fixed at exec),
  and custody / notify-back / goal arming.

**The churn inverts the LOC argument, which is the finding that matters for cost.** Over 90 days the
subsystem took 352 commits (216 `fix`). Transport files took 129 of them; `handoff-fire.sh` alone
took **202**. Inside handoff-fire, `git log -L` splits **23** commits in the composer/engagement
region against **86** in the spawn region. So the socket would remove ~36% of the lines and ~37% of
the commits **and leave the most-repaired file untouched.** Migrating the transport does not buy
down the maintenance the item is worried about; the maintenance lives in spawn, not in delivery.

One population claim in §2b(iii) is refuted outright: *"10 files doing keystroke injection"* —
`typed-send-lint.sh` runs clean at **one** grandfathered raw site (`handoff-fire.sh::as_write`)
across 417 files. What is actually large is the layer built to *verify* a keystroke landed.

## Verdict

1. **The hold: nothing to do.** Discharged 2026-09-08 and correctly recorded. No new MANIFEST row is
   warranted — the 2.1.260 entry already says what is true, and adding a row that restates it would
   be noise in the ledger the next audit reads.
2. **The re-priced cost: the item's own framing is refuted, and the corrected number is worse for the
   status quo but not decisive for migration.** We are not forgoing a socket; we are running a
   duplicate of one. But the duplication sits in the ~36% of the subsystem that has *already* been
   cheap to maintain, while ~60% — including the only primitive our fleet actually depends on,
   waking a session that does not exist yet — has no vendor equivalent.
3. **A wholesale migration is refuted by the same measurement that motivated it.** Nobody should
   re-derive it from §2b(iii)'s framing.

### Conviction

**~85%** that the correct posture is **additive, not migratory**: keep `handoff-fire.sh` as the
spawn/fleet layer, and let the socket become an *additional* delivery path for the narrow case it is
strictly better at — a live, registered peer, addressed by `sessionId` with a `procStart` pin, where
we currently pay a keystroke-injection round trip. That is below the 90% bar, so it is **not**
implemented here and it is **not** filed as agent work either: the two arms that would move it are
named below, and both are cheap.

What would move it above 90%: (a) one `socat`/`nc -U` send against a **throwaway** session proving
receipt shape and `notify_when_idle` end-to-end — this analysis proved delivery **into this
session's own socket** and reasoned to peers from identical uid/mode/code path, because the auto-mode
classifier correctly denied probing other operators' live sockets and that denial was **not**
worked around; (b) whether headless (`-p`) sessions bind at all — if they do not, the partition moves
against the socket again.

## Instrument warnings for whoever picks this up

- **Do not quote §2b(iii)'s numbers.** `handoff-fire.sh` LOC (10,622 → 12,047), the "10 keystroke
  files" claim, and the "MANIFEST holds the band" premise are all now false. Its *reasoning* stands;
  its *facts* have decayed, which is the published-figure-decay rule doing what it says.
- **The registry is per-config-dir.** Any census that reads one `~/.claude/sessions` and divides by a
  fleet-wide session count will understate coverage by roughly 5×.
- **Socket files are not a liveness signal** — 26 of 46 were stale at the time of writing.
