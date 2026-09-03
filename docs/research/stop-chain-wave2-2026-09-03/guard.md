# 79e2b74796af — compose-guard not extended to completion-assert

Repo: claude-infrastructure @ origin/main `24c598bac` (2026-09-03). READ-ONLY.

## HEADLINE (provisional, being verified)

**The premise is NOT refuted — the double-block is REAL and MEASURED. 33 same-Stop double-fires
across the IDL** (session-continue `fired` + completion-assert `fired`, same sid, ≤1s apart),
39 distinct sids fired both hooks at some point, against a denominator of **1,335
completion-assert Stop evaluations** in the retained IDL window (2026-08-25 → 2026-09-03).
So the harness does NOT short-circuit the Stop chain on a first `decision:"block"`.

(Details, code verification and the guard-shape question below.)

---

## 1 · What the existing compose-guard checks

`hooks/lib/continue-sentinel.sh` (full file, origin/main) is a **pure-function SSOT for one path**:

```
continue_state_dir()      → ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/state
continue_sentinel_for(cwd)→ <state_dir>/continue-<16-hex of shasum("$CFGDIR|$cwd")>
```

Its header records the origin defect (G-P6-6b / a19 I-1): boundary-handoff's guard hardcoded
`~/.claude/hooks/.session-continue-armed`, **a path session-continue never writes**, so the guard
was a dead no-op and "both hooks could inject a `decision:block` on the same Stop."

The consumer — `hooks/boundary-handoff.sh:415-428`:

```
if [ -n "${CC_CONTINUE_SENTINEL:-}" ]; then sc_sentinel="$CC_CONTINUE_SENTINEL"
elif command -v continue_sentinel_for >/dev/null 2>&1; then sc_sentinel="$(continue_sentinel_for "$cwd")"
else sc_sentinel=""     # lib unavailable → skip, never wrongly suppress
fi
{ [ -n "$sc_sentinel" ] && [ -f "$sc_sentinel" ]; } && abstain "continue-hook-armed"
```

**What it checks:** existence of session-continue's cwd-keyed sentinel file — i.e. "is the 🔧
continuation loop ARMED for this cwd".
**What it does when it fires:** `abstain "continue-hook-armed"` — boundary-handoff yields the whole
Stop turn (records an IDL abstain, exits 0, injects nothing). Placed *after* cwd resolution (needs
cwd to compute the hash) but *before* the latch/fire, so an armed session is never advised and the
one-shot latch is not spent.

Sourcing chain, `boundary-handoff.sh:147-153`: checkout `lib/` → `${CLAUDE_CONFIG_DIR}/hooks/lib/`
→ `$HOME/.claude/hooks/lib/`. **`completion-assert.sh` sources it nowhere** (verified: no
`continue-sentinel` / `continue_sentinel_for` reference in the file).

## 2 · Stop-chain order and the load-bearing question

`~/.claude/settings.json` Stop chain, in order:

1. notify.sh complete · 2. cache-expiry-tracker · 3. teammate-checkpoint ·
**4. session-continue.sh** · 5. anti-deference-nudge · **6. completion-assert.sh** ·
7. dispatch-assert · **8. boundary-handoff.sh** · 9. operator-readout · 10. session-beat stop ·
11. goal-inert-watch

session-continue (4) runs BEFORE completion-assert (6) BEFORE boundary-handoff (8).

**Does a first `decision:"block"` short-circuit the rest of the chain? NO — measured, not inferred.**
The IDL contains 33 Stops where session-continue recorded `disposition:"fired"` and
completion-assert recorded `disposition:"fired"` with the SAME sid within ≤1 second. A hook that
never ran cannot write an IDL record, so hook #6 demonstrably still executes after hook #4 fired.

## 3 · Transcript / IDL evidence of a real double-block

Source: `~/.claude/autonomy/idl.jsonl` + 8 rotated `idl.jsonl.*.gz` epochs
(977,474 records total; window 2026-08-25 → 2026-09-03).

| quantity | value |
|---|---|
| completion-assert Stop evaluations (denominator) | **1,335** |
| completion-assert `fired` (false-done block) | 127 |
| session-continue `fired` | 95 (`continue` 71, `ship-floor` 24) |
| **same-sid pairs within 20s (all landed at 0–1s)** | **33** |
| distinct sids that fired both hooks at some point | 39 |
| boundary-handoff `fired` / `abstained` | 64 / 1,689 |

Examples (all `CA reason=false-done`):

```
0s sid=00036c03  SC[ship-floor]@2026-09-02 06:34:35   CA[false-done/ledger]@2026-09-02 06:34:35
0s sid=3c60afff  SC[continue]  @2026-09-02 00:38:27   CA[false-done/ledger]@2026-09-02 00:38:27
0s sid=809e18ad  SC[ship-floor]@2026-08-26 00:22:33   CA[false-done/ledger]@2026-08-26 00:22:33
1s sid=4fce2f1e  SC[ship-floor]@2026-08-26 07:40:20   CA[false-done/ledger+fence]@2026-08-26 07:40:21
1s sid=a15b23d2  SC[continue]  @2026-09-02 06:20:12   CA[false-done/ledger]@2026-09-02 06:20:13
```

Both `continue` (the 🔧 armed loop) and `ship-floor` (📦/🚀) SC arms co-fire with CA's false-done.
So the overlap is not a corner case of one arm.
