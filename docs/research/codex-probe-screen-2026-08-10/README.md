# Adversarial screen fallout — 11 reports, 7 DEFECTIVE (2026-08-10)

**Provenance:** produced incidentally by W1 of `docs/plans/CODEX_ADVERSARIAL_SLOT_PROBE.md`, while
looking for *clean* files to serve as negative controls in the probe corpus. **These were not the
deliverable.** They are preserved here because they were written to a fired session's scratchpad,
that session has retired, and this machine runs a `scratchpad-reaper` — the evidence had a
deletion clock on it and no store.

**Status: UNTRIAGED.** Each carries executed evidence, but none has been independently re-verified
by a second pass, and none is filed as a defect. Do not act on one without re-verifying it — a
screen is a first look, and this repo's own history is mostly defects that survived a first look.

| Report | Verdict |
|---|---|
| `screen-branch-reaper` | DEFECTIVE |
| `screen-cc-config-slot` | DEFECTIVE |
| `screen-cc-recover-safeguard` | DEFECTIVE |
| `screen-gate-memo` | DEFECTIVE |
| `screen-mailbox-forward` | DEFECTIVE |
| `screen-session-writes` | DEFECTIVE |
| `screen-worktree-memory-link` | DEFECTIVE |
| `screen-origin-identity` · `screen-origin-identity-sh` · `screen-pane-modal` · `screen-pool-floor` | CLEAN |

**Read `screen-session-writes` first.** It indicts `hooks/completion-assert.sh:326`
(`session_unlanded_mine`) for returning "not mine" (rc 1) where the truthful answer is
cannot-tell (rc 2) — a **fail-GREEN** in the arm that decides whether a session is idling on its
own unlanded work. If it holds, the close-integrity floor can silently exonerate. That is the one
with the widest blast radius, and it is worth noting that this same hook adjudicated the closes of
the session that preserved these files.

## The finding that reshaped the probe's own method

W1 set out to pick 2 negative controls from files with no subsequent commits — the intuition being
"untouched ⇒ clean". **An adversarial screen convicted 9 of 13 such candidates**, one of them
already an open MED-HIGH in this repo's red-team notes and one a 100%-CPU arg-parse spin.

So *"a globally clean real file"* may not exist in this repo, and **absence of subsequent commits
is not evidence of correctness** — it is equally consistent with nobody having looked. The corpus's
clean briefs were therefore re-specified from *clean* to **screened-and-not-convicted, with the
screen's findings recorded** — an honest, weaker, checkable claim rather than an unfalsifiable one.

**Consequence for W2, load-bearing:** each brief must be run in a **FRESH context with NO repo
access**. A model that can read the tree can find the sibling evidence the corpus deliberately
pinned inert, and every control collapses at once.
