---
status: complete
---

# LIVENESS DETECTOR FAIL-NEGATIVE — five measured instances of "it didn't happen" about things that did

**Created:** 2026-08-11 · **Backlog:** `1364bc327ccf` · **Origin:** measured incidentally across one
long session (2026-08-10/11) while running the Codex adversarial-slot probe.

**Scope (frozen):** find the shared mechanism behind two independent liveness detectors that both
answer NOT-HAPPENED about events that demonstrably happened, and resolve it so that
*happened* · *did-not-happen* · *cannot-tell* are three distinct verdicts rather than two.

---

## Phase 0 — Agent Team Orchestration

**EXECUTION LOCUS PER WAVE:**

| Wave | Locus | Why |
|---|---|---|
| W1 Derive the shared mechanism | **S** (dispatched session, Fable) | default; this is a derivation task, not an evidence sweep |
| W2 Fix + prove both detectors | **S** | default |

**BOTH WAVES DONE 2026-08-11**, in one dispatched session on branch `detector-derive`. W1's derivation
refuted the plan's own "both are time windows" premise (see below), so W2 did NOT split into two
independent fixes — one mechanism, three sites. Read-only breadth (the third-detector sweep) ran as
three parallel research subagents on three orthogonal axes; all implementation stayed on the session.

**Dependency:** W1 → W2. W1 may conclude the two detectors share NO mechanism, in which case W2
splits into two independent fixes — that conclusion is itself a valid W1 deliverable.

---

## The five instances (all measured, all in one session)

| # | Detector | Claimed | Actually |
|---|---|---|---|
| 1 | `self-close` announce-before-retire | "fired with `--notify-back` but NO ping was ever sent from this pane" | the pane had sent **two** `cc-notify` messages, each returning `verdict=delivered ... reason=wake-path-armed` |
| 2 | `handoff-fire` engagement detector | `FIRE FAILED — never engaged` (pane 296) | pane had ingested the brief and was mid-preflight (its transcript holds the brief as a user message + 3 assistant turns) |
| 3 | `handoff-fire` engagement detector | `FIRE FAILED — never engaged` (pane 297) | same — ingested, working, and it went on to produce the session's most valuable report |
| 4 | peer 296 `self-close` | "never sent its own status ping" | it had just sent a detailed completion ping that was delivered |
| 5 | `handoff-fire` engagement detector | `FIRE FAILED — never engaged` (pane 346) | ingested; already building blinded panel bundles |

## Why this is expensive, and why the DIRECTION is the bug

Both detectors fail toward **NOT-HAPPENED**. That asymmetry is the defect, not the individual
misreads:

- A fail-POSITIVE is noise a human discards.
- A fail-NEGATIVE **manufactures work**. Instance 2 caused a re-fire for work already running:
  two sessions in one worktree, a duplicated 36-run paid model grid (Fable + Codex), and a
  guaranteed collision on a single `index.json`. It was caught only because a human-directed check
  read the transcript instead of trusting the verdict.
- Instances 1/4 make a peer's close report its status as UNREPORTED when it reported fully —
  which then instructs the *reader* to go re-verify work that was already verified.

**The pattern to test in W1:** each detector appears to assert a NEGATIVE from the absence of a
signal within a TIME WINDOW, on a box whose load ranged 13–24 during every instance. Absence of
evidence inside a window is being encoded as evidence of absence. That is the same shape as
`lookup-miss-is-not-absence` and `probe-that-acts-on-absence-must-confirm-presence` in MEMORY.md —
check whether those entries' remedy applies here, or whether this is a genuinely distinct third case.

## Constraints on any fix

1. **Do NOT simply lengthen the timeout.** It trades one wrong answer for a slower wrong answer, and
   the load that produced every instance will recur.
2. **Do NOT make either detector always answer yes.** A genuinely never-engaged pane and a genuinely
   unsent ping must still be caught — that is the positive control.
3. **Prefer the durable artifact over the window.** Engagement = "the session's transcript contains a
   user message carrying the brief" (a file on disk). Ping = "the target mailbox holds a line from
   this pane" — and `cc-notify` already returns a parseable `verdict=` token, so consume it rather
   than re-deriving the fact.
4. **Where a window is unavoidable, make the non-verdict distinct.** "Could not tell within 120s" and
   "did not happen" must not share an exit code or a message.

## Open question for W1 (the derivation, not a sweep)

Is there a THIRD detector on this box with the same shape that has not yet produced a visible
instance? The two found here were discovered only because their false negatives happened to be
expensive and observed. A detector whose fail-negative is cheap would never surface at all — which
is exactly the class this investigation exists to find.

---

# W1 — THE DERIVATION (2026-08-11, DONE)

## The answer: ONE mechanism, and it is NOT the time window

The question this session was given was *"both detectors assert a NEGATIVE from the absence of a
signal inside a TIME WINDOW, on a box whose load ran 13-24 during every instance — is that one
mechanism or two coincidences?"* The premise is half wrong, and finding out which half is what
locates the real mechanism.

**Detector 1 has no time window at all.** `sc_announce_before_retire`
(`scripts/handoff-fire.sh:2498`) does a single `grep -qF "$nb" "$mdir/.sent/$pane"` and, on a miss,
prints *"NO ping was ever sent from this pane"*. There is no polling, no clock, no `sleep`. Its
false negative is **deterministic and load-independent** — it fires 100% of the time whenever the
armed back-channel is a session NAME, which is the normal case.

So the shared mechanism is one level up from the window:

> **A detector whose question has three answers — happened · did-not-happen · cannot-tell — is
> implemented as a control flow with TWO exits, and the negative verdict is the FALL-THROUGH.
> Every distinguishable reason for "I could not observe it" therefore drains into the same
> `return 1` as "it did not happen." The fall-through POSITION is what makes the direction always
> fail-negative.**

The window is not the mechanism; it is one of several **absence-generators** feeding it. The three
found here are different in kind, which is exactly why "one mechanism or two coincidences" reads as
a coincidence from the outside:

| # | Detector | Absence-generator | Load-dependent? |
|---|---|---|---|
| 1 | `sc_announce_before_retire` | **resolution asymmetry** — writer records the RESOLVED key, reader searches the ARMED alias | no — deterministic |
| 2 | `verify_engagement` / `engagement_seen` | **window expiry** while the pane is merely slow, plus a **swallowed read failure** | yes — the load amplifies it |
| 3 | `session_unlanded_mine` | **swallowed command failure** (rc structurally unobservable) | partly |

Box load 13-24 is therefore an **amplifier, not a cause**. It raises the rate of every generator
(slower boots, slower git, more contention) and, because they all drain into one exit, it raises the
fail-negative rate without ever changing the verdict's shape. That is why the two detectors looked
like the same bug and behaved like different ones.

## Claim-by-claim, with file:line

### D1 — `sc_announce_before_retire`, `scripts/handoff-fire.sh:2498-2521` (instances 1 and 4)

- The reader tested `grep -qF "$nb" "$mdir/.sent/$pane"`, where `$nb` is the stamp's `notifyBack` —
  the address **as armed at fire time**, a project-qualified session name.
- The writer, `bin/cc-notify` `_record_send:863-870`, recorded `_record_send "$uuid"` — only what
  that name **resolved to** (`bin/cc-notify:874`, and `$uuid` is the resolved mailbox key).
- **Reproduced from the operator's live store, four days after the fact.** `cc-fired/11.json` carries
  `notifyBack=claude-infrastructure-6`; `mailbox/.sent/11` carries two real delivered sends recorded
  as bare `6`, at 15:27:20 and 15:27:47 — *the two pings instance 1 says the pane sent*. Running the
  detector's exact test against that pair misses, and prints the instance-1 message verbatim.
- Corroborated fleet-wide: `grep -rlE 'wt-|w[0-9]-|cloud-' ~/.claude/mailbox/.sent/` returns **nothing
  across all 72 files**, while `notifyBack` values are slugs of exactly that shape. The content miss
  is total, not occasional.
- **Correction to an earlier reading of mine.** I first suspected the *key* was also mismatched
  (`self_pane_id` vs `CC_PANE_ID`). Measured: `CC_PANE_ID` is unset here, so both sides evaluate
  `${ITERM_SESSION_ID##*:}` and agree; all 72 `.sent` keys are that shape. The key mismatch is
  **latent** (it needs `cc-pane-headless`), not live. Only the content miss is live.

### D2 — `verify_engagement` + `engagement_seen`, `scripts/handoff-fire.sh:2127` / `:2066` (instances 2, 3, 5)

- `engagement_seen`'s marker scan was `done <<EOF … $(find … -exec grep -lF …) … EOF`
  (`:2082-2086` pre-fix). **A command substitution inside a heredoc body has no observable exit
  status** — the value is interpolated and the rc discarded. A failed enumeration, an unreadable
  file, or a killed grep produced an empty list, the loop body never ran, and control fell through
  to `return 1`. A read that FAILED and a search that genuinely found nothing were the same answer.
  This is structurally identical to `hooks/lib/session-writes.sh:312`, found independently.
- `verify_engagement` polled that oracle for `FIRE_ENGAGE_TIMEOUT` (120s) + `FIRE_ENGAGE_RETRY`
  (60s) and returned `1` on expiry — the **same code a never-born pane gets**. It already spent
  separate codes on two *diagnosable* causes (2 PARKED, 4 WEDGED); the residual "I looked and did
  not see it" was still spelled as the definite negative.
- The consumer's remedy for `1` is a re-fire (`:8677`). **The file already documents the resulting
  harm, in its own `fire_cleanup` header at `:6875-6882`:** *"the operator is told to re-fire; the
  orphan meanwhile engages; two live sessions on one task and nothing can GC either."* The remedy
  was understood as prose while the verdict it depends on stayed wrong. It also, correctly, refuses
  to kill the pane on a negative read — so the blast radius is duplicated work, not a destroyed
  worktree.

### D3 — `session_unlanded_mine`, `hooks/lib/session-writes.sh:308-314` (candidate instance #6: **CONFIRMED**)

Confirmed, and independently convicted twice more during this session's sweep — from the
swallowed-rc axis and the window axis separately, plus the original codex screen. Same heredoc'd
command substitution; any git failure fell through to `return 1` = "not mine".

**The blast radius is the load-bearing part, and it is fail-GREEN:** `hooks/completion-assert.sh:398`
turns rc 1 into `_ca_exon="unlanded-not-mine"` (the false-done guard stops blocking) and
`hooks/session-continue.sh` turns it into `return 0` (the SHIP FLOOR never fires), while rc 2 is
documented three lines above as *"cannot-tell — stay strict"*. So a git read that merely failed let a
session close ✅ over unlanded work. Its own sibling `session_dirty_mine:250-255` runs the same class
of read through a tempfile specifically to `return 2` — that asymmetry inside one file settles intent.

## Why the existing controls did not catch any of this

Each detector already had tests. They were **vacuous on the axis that fails**, in three different ways:

- **D1** — `tests/announce-before-retire.bats` had 10 tests, 4 labelled CONTROL. Every fixture used
  ONE string (`$ORIG`) for both the armed address and the recorded target, so the alias-vs-resolved
  axis — the entire defect — was never expressed. A control that cannot fail proves nothing.
- **D2** — the suite pinned `engagement_seen`'s two states thoroughly and correctly. There was no
  third state to pin, so nothing was missing *from the suite's own model*; the model was the defect.
- **D3** — had **no tests at all**. The screen doc had already noted this: *"no test exercises a
  FAILING `git diff` in `session_unlanded_mine`, which is why defect #1 has no control catching it."*

## The prize: detectors with the same shape whose failure is SILENT

The brief's highest-value ask was the instance nobody has seen — a detector of this shape whose
false negative nobody would ever observe. A three-axis sweep (swallowed-rc · window-collapse ·
identity-miss) found these. **None is fixed here**; each is named with file:line as the brief allows,
and the top ones are filed. Ranked by how invisible the failure is:

| Rank | Site | Shape | What makes it SILENT |
|---|---|---|---|
| **1** | `scripts/comms-strand-report.sh:97-115` | box key (session uuid) compared against `it2 session list` (pane ids) | Counts **live** sessions' inboxes as dead-pane boxes and sums them into `dead_never_surfaced`, labelled *"the honest loss figure"*. Measured `{"dead_boxes":326,"dead_never_surfaced":14774}` — **including this very session's own inbox**. Its positive control PASSES because it controls the pane-list axis and is structurally blind to the box-key axis. Declared "THE CITATION" for a design doc, so wrong numbers steer a decision. |
| **2** | `scripts/stranded-sweep.sh:61-66,115-141` | swallowed `git cherry`; and `--mine` keys on a `Session-Id` trailer **nothing writes** (0 of the last 500 commits carry it) | Prints `✓ 0 stranded`, exit 0 — the designed pass of the auto-land crux, feeding `sweep_field="clean"` into `ship-land.sh`'s land attestation. **14 stranded commits measured live across 60 branches.** This is the detector for the `dfacccd` incident `.claude/CLAUDE.md` names by sha — it re-creates that incident inside the net built to catch it. |
| **3** | `scripts/handoff-disposition.sh:132-137` | `pgrep -f "cc-await-ping.*$uuid"` vs `session-continue.sh:490`, which arms the watcher with **no id in argv, deliberately** | Reports `await_ping_running:false` → one of 7 stay-OPEN reasons goes false → `🔚 DISPOSITION: CLOSE` → a pane parked awaiting a peer **self-closes**. Both watcher forms measured live simultaneously; one is invisible. |
| **4** | `scripts/worktree-gc.sh:711-716` | `recheck_live()` swallows `$(claude_cwds)`; "no live claude" and "lsof could not answer" are byte-identical | Gates `git worktree remove` at `:803,:928,:973` — **deletes a directory**, including gitignored content the script's own log says git records nowhere else. Its `ORACLES=0 → exit 3` refusal only tests `command -v`, so a present-but-failing lsof passes it. |
| **5** | `scripts/wrap-ledger.sh:712` (`LIVE_ADDS`) | `_bounded 5 git diff --diff-filter=A … \|\| true` ⇒ `0` | The correct non-verdict `"?"` exists four lines below and the timeout bypasses it. Per this repo's own rule an ADD gets **no** converge budget and breaches at lag 1 — so this converts the one lag with no budget into the one that is invisible, rendering `✅` where `🚀` is true. |
| 6 | `bin/it2-kitty:352-362` | 20s window ⇒ "the agent did NOT start" — **and it `rm`s the pending command file** at `:359` | The detector *manufactures* the failure it reports: `cc-pane-runner` is still polling for exactly that file for up to 300s, so deleting it guarantees the fallback to a bare shell. |
| 7 | `bin/cc-recover-safeguard:148-166` | 60s ⇒ `self-close --terminal` instead of `--successor "$NEW"` | Succession and the dirty hand-over are silently dropped; a genuine "no pane created" takes the identical branch. |
| 8 | `scripts/worktree-gc-infra-run.sh:168-178` | swallowed `git worktree list` ⇒ prints `0 0` | Its own header forbids exactly this: *"an unknown must never be mistaken for a healthy 0"*. `--assert` takes the numeric arm and reports `OK bounded and fresh`. |
| 9 | `scripts/postland-verify.sh:880-893` | swallowed `git ls-files` ⇒ empty `SYNTAX_BAD`, no floor | The green-stamp producer stamps `verdict:"green"` with a syntax error in the tree. |
| 10 | `hooks/lib/mailbox-pending.sh:376-381` | `_mbx_strict_uuid` demands 8-4-4-4-12 hex; on kitty every pane id is an integer | `.forward` succession is **structurally unwritable** for 100% of panes; the `return 1` reads as "a role simply gets no pointer". All 9 `.forward` files on disk are pre-kitty uuids. |

Also named, lower blast radius: `handoff-fire.sh:3574` `goal_live_for_sid` (a failed read relaunches a
successor with **no `/goal`**), `:967` `kitty_headless` (memoises the wrong answer; the file's own
header names this failure verbatim), `:2392` `recycle_engaged`, `hooks/lib/engagement.sh:132`,
`handoff-disposition.sh:112-126` (reads the PANE inbox while unread mail lives in the SESSION inbox —
measured: 1 unread reported as 0), `bin/cc-custody:22-23` (a second discharger that exists only in
prose), `bin/cc-spawn-verify:396-411`, `bin/cc-wedge-watch:262-311`.

**Cleared after reading both sides** (so the list is not merely everything that looked suspicious):
`cc-custody count --open` is correct (`|| _die "store unreadable" 3`) and is the one `wrap-ledger.sh`
calls, so the ✅-certificate path is safe; `mailbox_keyset`, `cc-await-ping`'s `_keys`/`_claim_live`,
`origin-identity.sh`'s by-cwd index, `dod-path.sh`, `lead-crash-watchdog`, `autonomy-sweep` D4,
`cc-sessions`/`cc-reconcile`/`cc-classify`/`cc-reaper` (all pane-vs-pane, all fail toward surface).

---

# W2 — THE FIX (2026-08-11, DONE — landed with W1)

Three detectors now return three verdicts. Per the constraints: **no timeout was lengthened**, no
detector was made always-yes, each reads a durable artifact rather than a clock where one exists, and
every non-verdict has its own exit code *and* its own message.

| Detector | happened | did-not-happen (positive control preserved) | cannot-tell (new) |
|---|---|---|---|
| `sc_announce_before_retire` | whole-FIELD match on either spelling | record exists in the new format, no match | record unreadable, **or** a legacy record that cannot answer an alias query |
| `engagement_seen` | marker + assistant turn → 0 | every read succeeded, nothing found → 1 | read FAILED → 2 · brief ingested as a **user message**, not yet running → 3 |
| `verify_engagement` | 0 | nothing ever born after the full window → 1 | 5, and it **does not re-send the brief** |
| `session_unlanded_mine` | 0 | diff succeeded, no intersection → 1 | git read failed → 2 |

Three design points worth keeping:

1. **The writer changed, not just the reader** (`bin/cc-notify:863`). `_record_send` now records the
   resolved key **and** the address as given. Re-resolving the alias at read time was the
   alternative and is strictly worse: resolution is live, so by the time a peer retires the
   originator may be gone and the name unresolvable — the reader would then fail to confirm a ping
   that provably happened, which is the same false negative wearing a different cause. A record
   carrying both spellings is answerable forever, because it is a fact about the past.
2. **A legacy record is cannot-tell, not "never pinged."** Every `.sent` file already on disk holds
   only resolved keys. Calling those "never pinged" would re-commit this item's own defect against
   the store's own history.
3. **State 3 is gated on a USER record** (`marker_in_user_record`, `handoff-fire.sh`). This was
   caught by the existing suite and it matters: a pane whose first prompt was REJECTED (the /goal
   >4000-char cap) also has the marker in its transcript — in attachment/system rows — and idles
   **forever**. Telling the operator "do not re-fire" there would strand a dead session. Only a brief
   that arrived as a user message earns the benefit of the doubt, which is exactly the durable
   artifact the DoD named. `verify_engagement` additionally **abstains from the re-send** in that
   state: typing the brief into a session that demonstrably holds it is the duplicate-work generator,
   not a recovery.

## Proof, both ways

`tests/announce-before-retire.bats` (16) · `tests/fire-engagement.bats` (32) ·
`tests/session-writes.bats` (29) — **77 pass, 0 fail.**

The controls are shown to have teeth by reverting the three subjects to `HEAD` and re-running with
the new tests in place. **8 of the new tests go RED pre-fix and green post-fix:**

- D1 — legacy-record → UNKNOWN · unreadable-record → UNKNOWN · the mutation
- D2 — the measured instance → 3 not 1 · unreadable tree → 2 · the mutation
- D3 — unresolvable trunk ref → 2 not 1 · the mutation

Each detector also carries one **mutation test** that rebuilds it with the pre-fix polarity and
asserts the original bug reappears on demand: D1 restores the substring `grep` and replays the real
legacy artifact; D2 collapses state 3 back into 1; D3 reverts the failure conversion to `return 1`.

**One control does not discriminate, and is labelled as such in the test file rather than counted as
evidence.** The D3 *timeout* case passes against pre-fix code too (measured: revert
`hooks/lib/session-writes.sh` to HEAD, run that test alone → `ok`). It therefore does not reproduce
the screen doc's measured claim for that specific trigger (*"sleeps 30 s → returns after 5.2 s with
rc 1"*); in this harness the pre-fix code answers 2. I did not find the cause, and the difference is
most likely in the shim rather than the subject. The **bad-ref** trigger is independently confirmed
defective and is what the D3 fix is justified by; the timeout test is kept as a regression pin.

## Known limitations, stated

- `successor_engaged` (`handoff-fire.sh`) was taught the new codes and **deliberately still
  fail-closed** on all of 1/2/3: it gates *retiring a pane into a successor*, where a false positive
  loses a session and a false negative costs an inspection. The asymmetry runs opposite to
  `verify_engagement`'s, which is why one oracle gets two consumer rules.
- `session_dirty_mine:269` still has the `printf | grep -qxF` shape that returns 141 under
  `pipefail` when a match short-circuits (needs ~64 KB / ~2400 written paths). Same fail-negative
  direction, measured as rare. Named here and left unchanged so this diff stays attributable to the
  read it fixes; the line I *did* rewrite uses a herestring.
- `tests/cc-notify.bats` has one pre-existing failure on the `--cloud` sidecar path
  (`DECLARED + {ok:true}`). Verified red on pristine `HEAD` — not caused by this change.

---

# CLOSE-OUT VERIFICATION (2026-08-14, DONE)

Re-verified from `origin/main` before closing, because two of this plan's own claims were
filing-day snapshots that nothing had re-read: *"W2 landed"* and *"the top ones are filed"*.

## Why the landed shas do not resolve, and what replaced them

`6509abd2` (the W2 fix) and `ca50a87b` (plan creation) are **local-machine shas and are not
ancestors of `origin/main`.** The GitHub trunk is a squashed import: `d3dda7b4` is a **root commit**
(no parents, 1840 files, 535,646 insertions, 2026-08-13) that carries the whole tree as of that
date, and trunk holds 50 commits total. So sha-matching is structurally impossible here and
**content-verification is the only valid method** — which is what this repo's own `.claude/CLAUDE.md`
already mandates (*"verify landings by CONTENT (`git ls-tree`), never by count"*), for a different
reason that happens to bite the same way.

## The three subjects, content-verified present on trunk

| | Site on `origin/main` | The fix, observed |
|---|---|---|
| D1 | `bin/cc-notify` `_record_send` | signature is `<resolved-key> [<target-as-given>]`; writes both spellings, collapses whitespace, omits a redundant duplicate field. The 24-line header naming instance 1/4 is present. |
| D2 | `scripts/handoff-fire.sh:2085,2122,2181,2252,2294` | `marker_in_user_record` exists; `engagement_seen` documents *"0 engaged / 1 none / 2 cannot-tell / 3 ingested-not-running"* and `return 3` is reached only via the user-record gate; `verify_engagement` returns `5`. |
| D3 | `hooks/lib/session-writes.sh:289,299-306` | docstring *"rc: 0 mine · 1 not mine · 2 cannot-tell"*; every git read carries an explicit `|| return 2`. |

All three landed. **The plan's frozen DoD is discharged** — `happened · did-not-happen · cannot-tell`
are three distinct verdicts, with distinct exit codes and distinct messages, in all three detectors.

## The prize list was a snapshot too — 6 of 10 are now fixed, 4 are still live

The list was written as *"None is fixed here … the top ones are filed"*. Three days on, later waves
had reached most of it. Re-measured on trunk, rank by rank:

| Rank | Site | State on trunk 2026-08-14 |
|---|---|---|
| 1 | `comms-strand-report.sh` | **FIXED** — an `ORACLE` positive control now compares the *same key shape* the walk uses; `control-failed`/`unknown` ⇒ `verdict:"unknown"`, exit 3, and it refuses to report any strand number. |
| 2 | `stranded-sweep.sh` | **FIXED** — `cherry_out="$(git cherry … 2>&1)"; cherry_rc=$?`, rc observable; `--mine` re-keyed onto identity that exists. |
| 3 | `handoff-disposition.sh:129-136` | **FIXED** — uuid-scoped `pgrep` with a documented bare-`pgrep` fallback for the no-id-in-argv watcher form. |
| 4 | `worktree-gc.sh:731-747` `recheck_live` | 🔴 **STILL LIVE** |
| 5 | `wrap-ledger.sh:721-724` `LIVE_ADDS` | **FIXED** — the `"?"` non-verdict is now produced, and all six consumers guard `!= "?"` before comparing. |
| 6 | `bin/it2-kitty` `deliver_argv` | **FIXED** — `pane_exists` rc 2 keeps waiting; the header cites the repo-wide indeterminate convention by name. |
| 7 | `bin/cc-recover-safeguard:157-167` | **ADDRESSED** — no longer one silent branch: successor-refused and no-pane-registered are distinct, announced arms, and a failed re-fire preserves the blocked pane. The `--terminal` fallback for a slow-registering pane remains, but it is now visible. |
| 8 | `worktree-gc-infra-run.sh:169-178` `stranded_scan` | 🔴 **STILL LIVE** |
| 9 | `postland-verify.sh:975-979` `shell_files` | 🔴 **STILL LIVE** |
| 10 | `hooks/lib/mailbox-pending.sh:376-381` `_mbx_strict_uuid` | 🔴 **STILL LIVE — but now argued.** The canonical 8-4-4-4-12 demand is unchanged; a header added since defends it as deliberate (a permissive check would route mail into a garbage box). That defence is sound and the consequence this plan named still holds: on kitty, pane ids are integers, so `.forward` remains structurally unwritable for them. It needs a decision — widen the address grammar or accept no forwarding on kitty — not a swallowed-rc repair. |

**The four still-live sites are the same one-line shape this plan already fixed three times** — a
command substitution inside a heredoc body, whose rc is discarded, feeding a `return`/print that
reads as a healthy negative:

- `worktree-gc.sh:741` — `done <<EOF` / `$(claude_cwds)`. Gates `git worktree remove` at `:829`,
  `:954`, `:999`. **Highest blast radius of the four: it deletes directories**, including gitignored
  content the script's own `log_disposal` header says git records nowhere else.
- `worktree-gc-infra-run.sh:177` — `$(git worktree list --porcelain …)`. Prints `0 0`, and
  `--assert` takes the numeric arm and reports healthy. The `n-a n-a` non-verdict already exists
  four lines up for the *deadline* case and is simply bypassed by this path — the identical
  structure rank 5 had before it was fixed.
- `postland-verify.sh:978` — `$(git -C "$WORKTREE" ls-files …)`. Empty list ⇒ empty `SYNTAX_BAD` ⇒
  the green-stamp producer stamps `verdict:"green"` over a tree it never read. No floor.

**Not fixed here, deliberately, and this is the carry-forward.** Repairing them means changing what
three consumers do at a `git worktree remove` and at the green stamp; the honest gate for that is
their bats suites (`tests/worktree-gc.bats`, `tests/postland-verify.bats`; **`worktree-gc-infra-run`
and `mailbox-pending` have no suite at all**), and shipping a verdict change without running its
control is the exact defect this plan was opened to indict. They are named here with file:line and
current-as-of-2026-08-14 state so a successor starts from measurement rather than from the
2026-08-11 snapshot.

## Status log

- **2026-08-20** — D1 follow-up (backlog `016174e64121`, closed on this evidence). The row was a
  SIXTH measured instance of D1, filed 2026-08-11T18:37Z — twenty minutes before `6509abd23` landed
  at 18:57Z. Its artifacts survive and settle it: `mailbox/.sent/349` holds `2026-08-11T11:36:35-0700
  345`, the ping the row says was sent; replaying the pre-fix substring read against that real line
  with an alias `want` returns *not-sent* (the row's `(auto, unannounced retire)` verbatim) while the
  landed reader returns cannot-tell. **Fixed, not open.**
  **But D1's rc-3 branch called itself "the transitional honesty term", and it is not transitional.**
  `_record_send` deliberately omits the redundant third field when the caller's spelling already WAS
  the resolved key (pinned by `tests/announce-before-retire.bats` — *"and one when they do not"*), so
  the current writer keeps minting one-spelling lines: **82 of 243** such lines in the live store were
  written AFTER the both-spellings fix landed. The verdict was right and the MESSAGE was wrong — it
  told the operator the record predated a format it postdates, implying a remedy (wait for the rollout)
  that does not exist. Message and comment corrected; two green tests in one suite had asserted the two
  halves and nothing drove a single record through both, so an interaction case now does.
- **2026-08-14** — Close-out. W1 + W2 content-verified present on `origin/main`; frozen DoD
  discharged; plan set `status: complete`. Prize list re-measured: ranks 1/2/3/5/6 fixed by later
  waves, 7 addressed, **4/8/9/10 still live** and carried forward above. No code changed by this
  close-out — it is a verification and a currency correction.
- **2026-08-11** — Plan created from five measured instances. Not started. Related but distinct:
  `docs/research/codex-probe-screen-2026-08-10/screen-session-writes.md` independently indicts
  `hooks/completion-assert.sh:326` (`session_unlanded_mine`) for returning "not mine" where the
  truthful answer is "cannot tell" — the SAME three-state collapse, in a third place, found by a
  different method. Treat it as a candidate instance #6 and verify it.
