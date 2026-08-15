# Adversarial screen fallout — 11 reports, 7 DEFECTIVE (2026-08-10)

**Provenance:** produced incidentally by W1 of `docs/plans/CODEX_ADVERSARIAL_SLOT_PROBE.md`, while
looking for *clean* files to serve as negative controls in the probe corpus. **These were not the
deliverable.** They are preserved here because they were written to a fired session's scratchpad,
that session has retired, and this machine runs a `scratchpad-reaper` — the evidence had a
deletion clock on it and no store.

**Status: TRIAGED 2026-08-15 → [`TRIAGE-2026-08-15.md`](TRIAGE-2026-08-15.md).** All 7 DEFECTIVE
screens were independently re-verified against `origin/main` at `2d7b125d`, one verifier per screen,
none of whom wrote the screen it checked. **No verdict was overturned; 20 of the 21 named findings
still reproduce.** One screen is discharged by a landed fix; the other 6 are live and unfiled. The
original warning below still applies to the 4 CLEAN reports, which have *not* been re-verified.

| Report | Verdict | Re-verified 2026-08-15 |
|---|---|---|
| `screen-branch-reaper` | DEFECTIVE | **3 of 3 live** — file byte-identical to what was screened |
| `screen-cc-config-slot` | DEFECTIVE | **2 of 2 live**, + a third variant the screen missed |
| `screen-cc-recover-safeguard` | DEFECTIVE | **4 of 4 live** — file byte-identical to its only commit |
| `screen-gate-memo` | DEFECTIVE | **2 of 2 live** — the stale-green reproduced end-to-end |
| `screen-mailbox-forward` | DEFECTIVE | **2 of 2 live** — screen's own citations corrected |
| `screen-session-writes` | DEFECTIVE | **#1 FIXED** by `6509abd2`; **#2 live** (deferred on the record) |
| `screen-worktree-memory-link` | DEFECTIVE | **6 of 6 live** — encoding claim upgraded from inference to proof |
| `screen-origin-identity` · `screen-origin-identity-sh` · `screen-pane-modal` · `screen-pool-floor` | CLEAN | not re-verified |

**Read `screen-session-writes` first.** It indicts `hooks/completion-assert.sh:326`
(`session_unlanded_mine`) for returning "not mine" (rc 1) where the truthful answer is
cannot-tell (rc 2) — a **fail-GREEN** in the arm that decides whether a session is idling on its
own unlanded work. If it holds, the close-integrity floor can silently exonerate. That is the one
with the widest blast radius, and it is worth noting that this same hook adjudicated the closes of
the session that preserved these files.

> **Triage outcome on that one:** it held, and it is **fixed**. `6509abd2` (2026-08-11) rewrote the
> read through a tempfile with an explicit `|| return 2` and added 5 tests including a mutation
> control, citing this screen by name — landing 12 hours after the triage item that sent someone to
> re-derive it. The consumer line has moved to `hooks/completion-assert.sh:335`. The screen's
> *secondary* finding (the `printf | grep -qxF` SIGPIPE at `session-writes.sh:278`) was deliberately
> left unfixed and is still live; see `docs/plans/LIVENESS_DETECTOR_FAILNEG.md:286-289`.

## The finding that reshaped the probe's own method

W1 set out to pick 2 negative controls from files with no subsequent commits — the intuition being
"untouched ⇒ clean". **An adversarial screen convicted 9 of 13 such candidates**, one of them
already an open MED-HIGH in this repo's red-team notes and one a 100%-CPU arg-parse spin.

So *"a globally clean real file"* may not exist in this repo, and **absence of subsequent commits
is not evidence of correctness** — it is equally consistent with nobody having looked. The corpus's
clean briefs were therefore re-specified from *clean* to **screened-and-not-convicted, with the
screen's findings recorded** — an honest, weaker, checkable claim rather than an unfalsifiable one.

*Corroborated by the 2026-08-15 triage:* four of the seven convicted subjects have **exactly one
commit in their entire history**, and every finding against all four is still live. A fifth is
byte-identical to what was screened. Stronger still, **every suite covering a convicted file is
green on trunk while its defects are live** — these are not untested files, they are files whose
tests do not discriminate, and `tests/worktree-memory-link.bats` recomputes its subject's own bug.

**Consequence for W2, load-bearing:** each brief must be run in a **FRESH context with NO repo
access**. A model that can read the tree can find the sibling evidence the corpus deliberately
pinned inert, and every control collapses at once.
