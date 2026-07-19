# Re-observe: `anti-deference-nudge` — VERDICT: NOT inert (false-positive flag)

**Disposes** cc-backlog `6bc2d518c8cb` — *"inert hook anti-deference-nudge: re-observe"*
(source `wiring-inert`, dodRef `~/.claude/autonomy/idl.jsonl`, filed 2026-07-19T02:55:03Z).
**Re-observed** 2026-07-19. **Evidence:** the live IDL (319 `anti-deference-nudge` eval records,
2026-07-17T20:02:10Z → 2026-07-19T02:52:13Z).

## TL;DR

The hook is **healthy, not inert**. The C3 `wiring-inert` critic flagged it on a **false
positive**: it re-reads the same D9 "abstained==100% over N≥10" signal that motivated the original
audit findings (G-P6-1, G-P6-2) — but that history is **pre-fix**. Since the P0-4 extraction fix
landed (2026-07-18T23:14:06Z, `49de48c`) the hook's blind-rate collapsed and it **fired for real**.
The flag survives only because of two defects in the *critic*, not the hook. Corrective action
belongs on C3 (filed separately); the hook needs **no change**.

## What the flag was built on (the motivating findings)

- **G-P6-1** (`p06-completeness.md`): *0 lifetime fires / 156 evals; 116/156 (74%) abstain
  `no-assistant-text`* — the old `tail -1` extraction grabbed a mid-turn / sidechain record at Stop
  time instead of the main agent's final text. This was a **real** extraction bug.
- **G-P6-2** (`p06-completeness.md`): the hook's own self-check (*"Alarm on abstained==100% over a
  long window would mean the tells stopped matching reality"*, `anti-deference-nudge.sh:45-47`) was
  tripped and **nothing watched it**; the audit operationalized the alarm as *abstained==100% over
  N≥10*. The C3 `wiring-inert` critic is the consumer later built for exactly that alarm — and it is
  what filed this item.

Both findings were correct **at the time**. P0-4 (`49de48c` "triple fix — extraction,
ship-narrowing, done-tells" + `74d304c` genuine-3 packet) fixed the extraction. The re-observe
question is whether the fix *worked in production*.

## The measurement — split at the fix boundary (P0-4 landed 2026-07-18T23:14:06Z)

| Window | Evals | abstained | **fired** | `no-assistant-text` | vs. P0-4 bar (<10%) |
|---|---:|---:|---:|---:|:--|
| **PRE-fix** (old `tail -1` extraction) | 257 | 257 (100%) | **0** | 189/257 = **73.5%** | ✗ (this is what C3 sees) |
| **POST-fix** (main-agent-scoped) | 62 | 61 | **1** | 2/62 = **3.2%** | ✓ **meets bar** |

- **Blind-rate fixed:** `no-assistant-text` fell **73.5% → 3.2%**, inside the P0-4 acceptance bar
  (`ORCHESTRATOR_DESK_24X7_PLAN.md` P0-4: *"live `no-assistant-text` <10%"*).
- **The positive branch fires:** first-ever real fire on 2026-07-19T00:26:47Z —
  `sid 4b6f66dd-1d27-4638-abda-e272c9e4d509`, `disposition:fired`, `reason:deference`,
  `tell:"want me to"`, `count 1/3`. The hook is demonstrably **not** inert-by-construction.
- **The remaining post-fix abstains are legitimate**, dominated by `no-tell` — the session's final
  message carried no deference tell, so there was correctly nothing to nudge. These are
  **fire-condition-not-met** outcomes, *not* evaluation failures.

The aggregate "60% no-assistant-text / 318-of-319 abstained" that trips the D9 rule is an artifact
of averaging **257 dead pre-fix records** into 62 healthy post-fix ones.

## Why the critic still flags a healthy hook — two C3 defects (root cause)

Reproducing `critic_wiring_inert` (`bin/cc-discover:176-191`) verbatim on the live IDL flags **all
four** conditional Stop hooks *right now* — `anti-deference-nudge`, `boundary-handoff`,
`completion-assert`, `waiting-recycle`:

1. **Line-based windowing dilutes genuine fires out of the window.** C3 reads `tail -n 5000` of the
   **shared** IDL and requires a hook's records in that slice to be 100% abstained. But the IDL is
   flooded by high-frequency `lead-supervisor` telemetry (~40K lines in ~2.5h — 29 sweeps × ~22
   findings every 30s). The real fire is now **42,900 lines deep** — far outside the 5000-line
   window. Inside the last 5000 lines `anti-deference-nudge` shows **12/12 abstained** → flagged.
   The window is measured in *total IDL lines*, but should be measured in *that hook's own evals*.

2. **Reason-blind abstain counting conflates two opposite meanings.** C3 counts every `abstained`
   record identically. But for a *conditional* hook, an abstain splits into:
   - **degraded / blind** (`no-jq`, `no-transcript-path`, `transcript-missing`, `no-assistant-text`,
     `no-skey`, `no-hash`) — the hook *couldn't evaluate*. This is the true D9 "inert" signal.
   - **fire-condition-not-met** (`no-tell`, `no-fire`, `done-ledger-clean`, `genuine-blocker`,
     `genuine-ship-hold`, `latched-already-fired`, `capped`) — the hook evaluated fine and correctly
     chose not to fire. This is the hook **working**.

   A correctly-quiet conditional hook legitimately abstains ~100% for *fire-condition-not-met*
   reasons (most sessions simply don't defer). Even a perfect **per-hook recent window** would still
   flag `anti-deference-nudge` — 47 evals have occurred since its fire, all healthy `no-tell`
   abstains — because C3 can't tell "nothing to nudge" from "can't see the transcript."

The D9 rule was authored for a **verifier** (`cc-notify`) whose *every* abstain was a degradation
(`W0-W3_INTERVENTION_AUDIT.md` D9). Applied unmodified to a conditional Stop hook, "100% abstained"
is a **category error**, not an inertness proof.

## Disposition

- **Hook:** no change. `anti-deference-nudge` is healthy — blind-rate in spec, positive branch
  proven, abstains legitimate.
- **This item (`6bc2d518c8cb`):** closed `done`. Durable against re-flagging: `cc-backlog add` is a
  no-op on an existing id (`bin/cc-backlog:108`), so C3's hourly re-`add` of the same
  (project+title+source) key cannot re-open it.
- **Root cause → separate item (C3 critic).** Two options for the critic owner — this is a **design
  question, not a mechanical bug**, because the discovery feed was deliberately built as a *coarse
  tripwire* that appends candidates for human/agent disposition (this re-observe *is* that
  disposition step):
  - *(a) per-hook windowing* — group by `.hook`, evaluate each hook's own last-N evals, so global
    IDL volume can't flood a hook's fires out of view; and
  - *(b) reason-aware counting* — count only degraded/blind abstains toward the D9 signal, so a
    correctly-quiet conditional hook is never flagged as inert.
  Filed as its own cc-backlog item so the owner can weigh coarse-tripwire-by-design against a
  smarter critic. **The same fix clears the false positive on all four sibling `re-observe` items.**

## One-line masking caveat (for the C3 follow-up, not this item)

Because the id keys on (project+title+source) and `add` is a no-op on existing ids, dismissing this
false positive `done` **also permanently masks a future *genuine* inertness of the same hook** (same
title → same id → no new candidate). That is a property of the idempotency keying shared by every
discovery candidate, out of scope here — noted so the C3 follow-up can decide whether inert
candidates should carry a re-observation epoch in their key.
