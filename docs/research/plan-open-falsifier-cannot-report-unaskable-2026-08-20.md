# The plan-open falsifier cannot say "I could not ask" — measured 2026-08-20

**Origin:** dispatch of backlog `83f44615f0eb` ("advance /handoff — capture the high-value
information a succession currently drops"), whose plan had been **complete on trunk since
2026-08-19** and which was dispatched anyway.

**Status:** finding + reproduction. **No fix applied** — the fix belongs to its own item, filed
against this doc (see §5). Per the dispatch premise-check rule, the disproof is the deliverable;
acting on the refuted part is not.

---

## 1. What was dispatched, and why it should not have been

`docs/plans/HANDOFF_HIGH_VALUE_CAPTURE.md` on `origin/main`:

```yaml
status: complete
resolution: research complete — verdict CHANGE NOTHING in commands/handoff.md (R5 success outcome)
findings: docs/research/handoff-high-value-capture-2026-08-19.md
```

Landed by `cf7a5490` (2026-08-19) together with the 708-line findings doc. `commands/handoff.md`
was never opened for editing — the plan's own W3 row records that, and git agrees: the file's last
touch is `9b5ffdb6`, the same drain commit that landed the `--falsify` verb, not a handoff edit.

So the item's premise — "this plan still holds work to advance" — was false at dispatch time. The
item was minted before `cf7a5490` flipped the frontmatter and nothing re-read it, which is the
exact decay shape `cc-discover`'s C2 critic already documents (`bin/cc-discover:220-225`, citing
`a50e6ab779e8` sitting open twelve days under a stale title).

## 2. Why the stored falsifier did not retract it

The item carries the probe `cc-discover` mints for **every** plan-open candidate
(`bin/cc-discover:274`):

```sh
[ "$("$HOME/.claude/scripts/plan-phase-scan.sh" '<plan>' --falsify 2>/dev/null)" = FALSIFIED ]
```

Run against **this checkout's** copy of the scanner, that probe exits **0** — clause (a) of
`--falsify` reads the frontmatter, sees `complete`, prints `FALSIFIED`. The retraction the design
intends is available and correct.

The dispatch brief instead reported:

> Falsifier re-run just now: NOT REFUTED (exit 1) — the probe declined to retract this item.
> output: (silent)

`(silent)` is the tell. Clause (a) prints `FALSIFIED`; clause (b) prints nothing but exits 1; an
older scanner without the verb prints a JSON section dump; an absent scanner prints nothing. Only
the last two are consistent with silence + exit 1, and both mean **the deployed scanner did not
answer the question**. `--falsify` landed in `9b5ffdb6` on 2026-08-19 — one day before this
dispatch — so a live layer that had not yet fast-forwarded is the ordinary explanation, and it is
the skew `cc-discover`'s own comment predicts ("a session running THIS cc-discover from a worktree
while ~/.claude has not converged CAN [skew]").

## 3. The structural defect: the wrapper flattens the answer

`bin/cc-premise` already knows that "could not ask" and "asked, answered no" are different facts.
It keeps a band for it (`bin/cc-premise:228`) and renders a distinct sentence for it
(`bin/cc-premise:1322`):

```python
_FALSIFIER_UNASKABLE_RCS = frozenset((2, 124, 126, 127))   # 2 could-not-ask · 124 timeout
                                                           # 126 not executable · 127 not found
```

That machinery exists because of backlog `f401935c0bd4` (2026-08-14), where rendering a
could-not-ask as "this premise is current" cost one dispatch slot on a fix that had already landed.

**It cannot fire for a plan-open probe.** `[ ... ]` is a test on a *string*; it discards the inner
command's exit code entirely and yields 0 or 1 only. Every unaskable state arrives at cc-premise
as exit 1 — a genuine "asked, answered no".

Reproduction, under `/bin/sh -c` (the runner cc-premise actually uses), against the same complete
plan:

| inner state | inner rc | probe rc seen by cc-premise | rendered as |
|---|---|---|---|
| scanner missing | 127 | **1** | NOT REFUTED |
| scanner not executable | 126 | **1** | NOT REFUTED |
| scanner predates `--falsify` (dumps JSON, rc 0) | 0 | **1** | NOT REFUTED |
| current scanner, plan complete | 0 | **0** | FALSIFIED ✅ |

Commands used:

```sh
P=docs/plans/HANDOFF_HIGH_VALUE_CAPTURE.md
/bin/sh -c '[ "$("$HOME/.claude/scripts/plan-phase-scan.sh" '"'$P'"' --falsify 2>/dev/null)" = FALSIFIED ]'
# with $HOME/.claude/scripts absent → exit 1, output silent
/bin/sh -c '[ "$(./scripts/plan-phase-scan.sh '"'$P'"' --falsify 2>/dev/null)" = FALSIFIED ]'
# control, scanner present → exit 0
```

`2>/dev/null` closes the last channel: the inner script's own diagnostics never reach the brief
either, so `output: (silent)` is all a worker gets.

## 4. Why the affirmative-token design is still right

The token test is not the bug, and reverting it would be worse. `plan-phase-scan.sh` takes its
format as a second positional with a **silent default**, so an older copy handed `--falsify` prints
a section dump and exits **0** — which the falsifier contract reads as "the premise is GONE".
Testing the word rather than the code is what stops an old binary from silently retiring live work,
and both files document that choice deliberately (`scripts/plan-phase-scan.sh:80-88`,
`bin/cc-discover:234-242`).

The defect is narrower: the design chose **fail-open at mint**, which is correct there — a
discovery feed that stopped filing looks exactly like an empty backlog. It then reused the same
collapsed shape at **claim**, where fail-open has a different price: a dispatched worker slot spent
on finished work. Mint and claim want the same *direction* and different *legibility*.

## 5. The fix, specified but NOT applied

Make the minted probe preserve the inner rc when it is one cc-premise can read, while keeping the
affirmative token as the only path to 0:

```sh
out=$("$HOME/.claude/scripts/plan-phase-scan.sh" '<plan>' --falsify 2>/dev/null); rc=$?
[ "$out" = FALSIFIED ] && exit 0
case $rc in 2|124|126|127) exit $rc ;; esac
exit 1
```

Exit 0 still requires the token, so the version-skew guard is untouched; 126/127/124/2 now reach
`_FALSIFIER_UNASKABLE_RCS` and render as **COULD NOT ASK — this premise is UNVERIFIED**, which is
the true statement. An old scanner that dumps JSON at rc 0 still lands on `exit 1`, unchanged.

**Gates it must clear before shipping** — none of which are available from a cloud checkout, which
is why this is filed rather than done:

1. A negative control (R4's rule): run the new probe against a plan that **should** stay live and
   observe exit 1, and against an absent scanner and observe 127 reaching the renderer.
2. It changes the probe stored on every future plan-open item — re-run `cc-discover` against a
   fixture store and diff the minted records.
3. Existing pins: `tests/cc-premise-falsifier.bats` already pins 127 as fail-open at the exception
   path; confirm the live-exit-code path agrees rather than double-counting.
4. Decide whether already-stored probes are re-written (`cc-backlog falsify <id> --probe …`) or left
   to age out. Rewriting touches an append-only ledger's semantics and is the operator's call.

## 6. What a worker should take from this

**`NOT REFUTED (exit 1)` with `output: (silent)` on a plan-open item is not evidence the premise
holds.** It is consistent with the deployed scanner not knowing the question. Read the plan's
frontmatter on `origin/main` yourself before acting — which is what the dispatch rails already say,
and what turned this dispatch into a close rather than a diff.
