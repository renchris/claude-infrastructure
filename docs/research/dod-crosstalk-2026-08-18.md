# Repo-keyed DoD crosstalk — the fix needs an identity this tree does not record

Row `4de3d0f9c0e1` (master-session-lifecycle), "review #10b". Investigated 2026-08-18.

**Verdict as first written (2026-08-18, recycle #24): the defect is REAL and reproduced; the remedy
is NOT buildable from state this tree records.** Filed as the design question rather than shipped as
a read-side heuristic, because every rule buildable *then* either kept the crosstalk or re-broke the
worktree hop that `hooks/lib/dod-path.sh` exists to make work.

> **CLOSED 2026-08-18 (recycle #26). The verdict above was right about the READ side and that is why
> it holds up: no read-side rule could ever have worked, because the distinguishing fact was not in
> the tree.** The fix was to *record* it — prerequisite 1 (per-capture provenance, #24) then
> prerequisite 2 (the succession edge, #26). §3's table needs no new row: it enumerates attempts to
> DERIVE the distinction, and §5.2 now carries the proof that no such derivation exists. Both
> red-proof cases are unskipped and green. **Everything below is preserved as the reasoning that
> produced the fix, not as current state** — read §5 for what shipped.

## 1. The red proof

Two worktrees of one repo, both freezing their own scope. `tests/dod-path.bats` cases 7–8, gated
off by default (they are red on purpose):

```
$ CC_DOD_CROSSTALK_REDPROOF=1 bats tests/dod-path.bats
1..9
not ok 7 CROSSTALK: wave B's REMAINDER counts ONLY its own frozen items, not a concurrent wave A's
# wave B summed a concurrent sibling's boxes: REMAINDER=2 (want REMAINDER=1)
not ok 8 CROSSTALK: a concurrent wave A's frozen scope is not injected into wave B as binding
# wave B was handed a concurrent sibling's scope as binding
```

The axis is pinned inert on the legacy side — neither worktree has a legacy path-hash file, so both
observations come from the repo-key store alone. Case 1 in the same file (the succession hop) stays
green throughout: **the two behaviours are one mechanism observed from two sides.**

## 2. Live blast radius, measured

| Fact | Value |
|---|---|
| worktrees of this repo sharing one scope file | **101** (`git worktree list`) |
| captures in `~/.claude/autonomy/dod/repo-86523465733a9afe.md` | **15** distinct frozen scopes, 2026-08-10 → 08-16 |
| unchecked `- [ ]` boxes in that file | **0** |

**Corrected measurement — the row's two halves are not equally live.** The REMAINDER-inflation half
is *latent*: real in the mechanism (case 7), but zero live captures carry checkboxes, so nothing is
currently being red-runged by it. The **injection half is active every session**: `dod-persist.sh`
SessionStart `cat`s the whole file, so a session in any of those 101 worktrees is handed all 15
waves' contracts under the frame *"Every 'Scope (frozen):' line below is binding … do NOT narrow
scope or declare done until ALL of it is met."*

## 3. Why no read-side rule fixes it

The reader would have to separate *a wave from its own successor*. Every discriminator available:

| Candidate | Why it fails |
|---|---|
| key on git toplevel | exactly the pre-W3 scheme the lib was built to replace — reds case 1 |
| key on branch | a recycle to a fresh worktree off origin/main is a NEW branch, so predecessor ≠ successor — reds case 1 the same way |
| writer liveness (inherit only a dead wave's scope) | the recommended pattern **fires the successor before the predecessor exits** (`MEMORY.md` → *Fire the recycle first*), so the predecessor is alive at the successor's SessionStart and the successor would exclude its own inheritance — reds case 1 |
| recency / last-writer-wins | `get` already does this; REMAINDER *sums*, and recency cannot tell a sibling's newer capture from a parent's |

## 4. The two things that would have to exist first

1. **Per-capture provenance.** `persist_dod` (`hooks/dod-persist.sh:82-93`) records the writing cwd
   only in the file HEADER — i.e. for the *first* writer. Each capture block is `## <ts> (<label>)`
   and carries no worktree, session id or wave. **No reader can attribute a capture to a wave**,
   so no read-side rule has an input to key on, however clever.

2. **A lineage token.** The nearest existing record is the fired-peer stamp
   (`scripts/handoff-fire.sh` `mark_fired_peer`, schema 2), and it does not close the gap twice
   over:
   - it records `cwd` (the fired session's OWN) and `firedBy` (the firing **pane id**) — never the
     firing session's cwd, which is the edge a worktree-scoped store needs;
   - it is written only when `WANT_SELF_RETIRE=1`, and `handoff-fire.sh:7358` reads
     `[ "$SELF_RETIRE" = 1 ] && [ "$RECYCLE" = 0 ] && WANT_SELF_RETIRE=1` — **so `--recycle`, which
     CLAUDE.md names the DEFAULT succession ("Reach for Recycle first"), writes no stamp at all.**

   `~/.claude/logs/handoffs.jsonl` is written for every fire but carries `firing_sid` / `prev_sid` /
   `target_pane` — session and pane ids, never a cwd pair, and never the fired session's own id.

So the lineage edge *predecessor-worktree → successor-worktree* is recorded **nowhere**, and least
of all on the path that carries most successions.

## 5. Recommendation

Sequenced, because (1) is a precondition for any version of (2):

1. **Stamp provenance at capture** — add the writing toplevel (and session id when known) to each
   `## <ts>` block in `persist_dod`. Strictly additive, INTEGRATE-safe, changes no reader today.
   **DONE 2026-08-18 (drain recycle #24).** Each block now reads
   `## <ts> (<label>) · toplevel=<writing worktree> · session=<sid>`; the session field is OMITTED
   rather than emitted blank when neither the hook payload nor `CLAUDE_CODE_SESSION_ID` knows one,
   so a reader can tell *"no session recorded"* from *"session recorded as nothing"*. Six cases in
   `tests/dod-persist.bats` (20–25), each attributed by its own mutant: the per-block stamp (M1),
   the blank-session field (M3), **first-writer memoization — the precise §4.1 defect — which reds
   case 24 alone (M5)**, and a reader-neutrality control proven able to fail (M4: a stamp that
   manufactures a `- [ ]` box reds it). `dod-persist`+`dod-path` 34/34, `wrap-ledger` 75/75,
   `completion-assert` 91/91.
2. **Mint a lineage token on the succession paths**, `--recycle` included, recording the *firing
   cwd* alongside the fired cwd — then a reader can inherit along the lineage and exclude everything
   else. Only at that point do cases 7–8 become fixable; unskip them there. ~~STILL OPEN~~
   **DONE 2026-08-18 (drain recycle #26) — cases 7–8 unskipped and green; the gate and
   `CC_DOD_CROSSTALK_REDPROOF` are deleted, because a permanently-skipped case reports nothing.**

   **The edge.** `hooks/lib/dod-path.sh` gained `dod_lineage_record` / `dod_lineage_ancestors` and
   a block filter; `scripts/handoff-fire.sh` calls the writer at the ONE site every dir-changing
   succession passes through — where `LAUNCH_DIR` resolves (`:7841-7845`), which covers an ordinary
   `--worktree`/`--cwd` fire, a self-routing fire, and `--recycle --worktree` (the relocating
   recycle, `RECYCLE_RELOC=1` at `:6690`, which falls through to the `$WT` arm). §4.2's objection is
   answered rather than worked around: `mark_fired_peer` is not reused, precisely because it records
   the fired session's own cwd plus the firing PANE id and is gated on `WANT_SELF_RETIRE=1`.
   **A same-dir `--recycle` needs no edge at all** — a measurement that simplified this materially:
   `LAUNCH_DIR` *is* `$PWD` on that path (`:7841`, first arm), so the toplevel identity is unchanged
   and the writer drops the self-loop itself. The "`--recycle` records nothing" problem was only ever
   about the RELOCATING form.

   **Why §3's table did not need a new row.** Every candidate there fails by trying to *derive* the
   distinction from the repo. The proof that none can: **cases 1 and 8 have the same setup — A
   freezes a scope, B reads it — and opposite required answers.** No function of that setup
   satisfies both, so the fix was never a cleverer rule; it was a missing input. Case 1 therefore
   mints the succession edge in its setup now. That is not a narrowed falsifier — it is the input
   the case was always missing, and it makes case 1 state the invariant it always *claimed*
   (a SUCCESSOR inherits) rather than the weaker "any worktree of the repo inherits" it could
   express before. The un-recorded direction is pinned separately (case 11) so neither answer is
   assumed.

   **Fail-open, and the cost that buys.** A capture with no `toplevel=` stamp is unattributable —
   every capture written before prerequisite 1 — and is ALWAYS inherited (case 10). The filter can
   only drop a block that positively *names* a foreign wave, so it fails toward "keeps the
   crosstalk", never toward "loses a contract you own": the same direction the lossless legacy
   read-fallback chose. **The accepted cost, pinned as case 11 rather than left to be discovered:**
   a worktree nobody fired — a hand-made `claude -w` sibling — has no edge, is treated as
   concurrent, and re-freezes its own scope. *Considered and rejected:* grandfathering by "the
   writing toplevel no longer exists on disk". It would soften the transition window, but it
   re-introduces a liveness discriminator §3 already refuted, for a one-time benefit — so the rule
   stays minimal and the cost stays visible.

   **Attribution.** Nine mutants, one per site, control green before and after, none uncaught:
   unfiltered REMAINDER reds case 7 alone · unfiltered injection reds 8 alone · a depth-1 lineage
   walk reds 9 alone · dropping unattributable blocks reds {3,10} · **restoring the pre-fix
   "always keep" reds {7,8,11} — the whole defect** · removing both cycle guards reds 12 alone ·
   recording the self-loop reds 13 + intent-5 · removing the writer call reds intent-4 alone ·
   letting `--dry-run` record reds intent-6 alone. Gates: `dod-path` 14/14, `dod-persist` 30/30,
   `wrap-ledger` 75/75, `completion-assert` 91/91, `handoff-recycle-intent` 6/6.

   **No new file, deliberately.** The lineage lives in `hooks/lib/dod-path.sh`, which is already
   symlinked into the live layer, so this land carries `LIVE_ADDS=0` — a new lib would have been
   absent from every consumer's `[ -f … ]` guard until the converger ran, i.e. a silent no-op.

### Instrument note — `grep -q` under `pipefail` inverts a filter's verdict

Two defects surfaced in this change, and **both were caught by the existing suites and fixed in the
code rather than in the assertion.**

1. `dod_filter_for "$cwd" "$f" | grep -qF -- "$g"` in the grown-line dedup. `hooks/dod-persist.sh`
   runs under `set -uo pipefail`, and `grep -q` **exits on the first match** — so the upstream
   filter takes SIGPIPE and the pipeline reports FAILURE *on the very input it just matched*. The
   dedup then re-appended every grown line on every compaction, forever. `tests/dod-persist.bats`
   case 16 counts the appends and caught it. The live form is the same count idiom the `!`-liveness
   note below already prescribes: `n="$(… | grep -c … || true)"; [ "$n" -eq 0 ]`.
2. **A fixture keyed on prose the change made false.** The SessionStart frame said *"full
   INTEGRATE-only history"*; the filter made "full" untrue, and `tests/dod-persist.bats` keyed a
   `sed -n "1,/$HIST_MARK/p"` range on that phrase. **A stale sed marker does not fail — it
   inverts**, because `sed -n '1,/nomatch/p'` selects the WHOLE input, so every "…is not above the
   history" assertion silently widens to the whole document. Marker narrowed to the wording-stable
   core, plus `_hist_mark_live`, which asserts the marker exists *before* anything slices on it.

**Adjacent finding, separate row.** Independent of wave identity, SessionStart injects the file's
*entire* monotone history as binding — 15 contracts today, unbounded tomorrow. Even a legitimate
successor inheriting from a legitimate predecessor is handed every scope the repo ever froze. That
is a bounding question about the injection, not about identity, and is fixable on its own.

**DONE 2026-08-18 (drain recycle #24) — and it needed no ruling, because the frame contradicted its
own store.** `get` and `last_recorded_scope` have always returned the NEWEST `Scope (frozen):` line
only; only the SessionStart frame claimed *all* of them bind. The injection now names that newest
line as `THE CURRENT CONTRACT` and labels the rest prior context, `NOT additional binding scope`,
pointing at the `## ` block's new `toplevel=` stamp as the way to tell your own captures from a
sibling's. **LOSSLESS** — the full history is still injected verbatim; nothing is dropped, so a
legitimate inheritance cannot go missing. This is the *active* half of §2 closed; the latent
REMAINDER-inflation half still needs wave identity and is unchanged. Cases 26–30 in
`tests/dod-persist.bats`, each attributed: oldest-instead-of-newest reds 26 alone, dropping the
history reds the lossless case 28 alone, losing the re-ask licence reds 29.

### Instrument note — a dead assertion class this repo's own analyzer does not flag

Found by measurement while writing case 27, and it cost two wrong diagnoses first. Bash's errexit
rule states the shell does not exit *"if the command's return value is being inverted with `!`"*.
So under bats a bare **`! cmd` is a live assertion ONLY as a test's FINAL command** (where bats
takes the body's exit status); as an **intermediate** line it is DEAD and passes regardless of the
truth. Measured with a positive control (`negprobe.bats`: `! true` as the last line DOES fail),
and confirmed on the real case — `! printf … | grep -qF "<a string that was provably present>"`
passed pre-fix. `scripts/bats-assert-liveness-fix.py --dry-run` reports **no dead assertions** on
that same file, so the class is outside what it detects (it caught the sibling `A && B && C` form
in the same land). The live form used here is a count: `n="$(… | grep -c … || true)"; [ "$n" -eq 0 ]`.
Not filed as a row — this recycle closed none, and filing would end it net-positive on filings;
recorded here and in memory `negated-assertion-dead-unless-final` so it is not re-derived.
