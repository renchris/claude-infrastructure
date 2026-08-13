---
status: complete
---

**DONE (2026-08-10, this session).** All four waves built + tested in `.worktrees/close-integrity`:
plan `0bde7c17` · W1 origin-identity+spent `277323b8` · close-shape `c51ad0ed` · W2 cc-custody+
producers `46770378` · W2b ship-floor + custody consumers `8b8d6ac3` · W3 dod-path `83e64569` ·
W4 wrap.md `089a114b` + CLAUDE.md `9ea3f7c0`. Suites green this session: origin-identity 17 ·
fired-cwd-index 19 (test 10 un-redded — was red on pristine trunk) · 6× selfclose + fire-engagement
+ lifecycle · cc-custody 9 · ship-floor 10 · wake-floor 44 · session-continue+telemetry+wrap-ledger
95→70 (incl. 3 custody) · completion-assert FULL 73/73 (incl. 6 D6 + 1 custody) · dod-path 7.
Follow-ons FILED: custody v1.1 `d29b73103189` · cc-classify unification `dcf58e1ba056` · G3
attribution `68fdc99b17c7`. Tasks corrected from measurement: #70, #141 (both rewritten to their
surviving true forms). Key learnings: the leak was the DECISION layer (58% of stops assert
nothing; deaths 0.34%); wave-abandonment is the loss signature (62 commits / 21 branches / 5
spikes); a first-writer-seeds DoD migration was rejected for an unbounded shadow window — two read
sources instead; the spent-stamp retry needs the marker proof or a reused kitty id inherits a
self-retiring contract.

# CLOSE INTEGRITY — sessions must not end before complete + landed + live

**Scope (frozen):** root-cause why CC + claude-infrastructure + kitty sessions (esp. ORIGIN
sessions) still end/close before work is complete + landed + deployed-live; fix the confirmed
generators end-to-end; make ORIGIN-session genuine-completion closes deliver the Pyramid
complication/solution/outcome + safe-to-close affirmation via a deterministic rail.
DoD store: `~/.claude/autonomy/dod/079c87e55147d5b7.md` (this worktree) — G2 makes that keying
itself part of the problem; W3 fixes it.

## Phase 0 — Agent Team Orchestration

**EXECUTION LOCUS: L (lead-inline, this session), all waves.** Why (one line): W1/W2/W3 all edit
`completion-assert.sh` + `wrap-ledger.sh` + shared libs — single-owner-per-shared-file forbids
parallel split, and the /goal Stop hook binds this session until resolution. Recon was S-style
(8 background agents, reports in scratchpad/recon/). Lead context budget: commit after EVERY wave;
succession point = any wave boundary via `--recycle` (plan + this doc carry full state).
Worktree: `.worktrees/close-integrity`, branch `fix/close-integrity`, base 90880b95.

## Complication (evidence, 3 agreeing sources: report-stopchain / report-seams / report-adversarial)

1. **Silent closes pass every Stop rail.** All blocking arms key on the close MESSAGE (done-claims,
   deference tells) or on uncommitted OWN writes. `no-close-tell` is the modal outcome (115/199 =
   58% of adjudicated stops). A session that goes quiet in 📦 (committed-unlanded) or 🚀
   (landed-not-live) reaches idle unblocked — session-continue.sh:519-520 refuses 📦 BY DESIGN
   ("the ship policy's business, not a loop"), and the ship policy has no actuator. 53/60 recent
   closes are clean exit-0: sessions end voluntarily; the operator's close of a done-looking pane
   is the last domino, not the generator.
2. **G1 — custody ends at dispatch.** An origin lead that fans work to /handoff sessions has an
   EMPTY write footprint → E0/✅ by construction → every rail correctly waves it through.
   dispatch-assert is discharged by the FIRE; nothing asserts the RETURN was collected. Registry
   rows carry no provenance; no ledger term reads dispatch state. This is the origin-session case
   the operator names, and no pre-existing candidate explained it.
3. **Origin-ness is invisible at Stop.** The one discriminator (fired-peer stamp
   `~/.claude/cc-fired/<pane>.json`; ABSENT ⇒ origin) is read by ZERO Stop hooks. Two divergent
   inline copies of the predicate exist (handoff-fire.sh:2631 by cwd; cc-classify:413 by
   startedAt) — no sourceable lib. The spent-stamp hole (tenancy never reads `closedAt`) lets a
   reused kitty id in the same cwd read `valid` — a genuine ORIGIN can self-close as if fired.
4. **G2 — the DoD dies at the worktree hop.** DoD keyed on toplevel-path hash
   (wrap-ledger.sh:213-218 = dod-persist.sh dod_file_for, two copies of one resolution); a fresh
   worktree ⇒ blank scope ⇒ absent-DoD ✅ ("completeness unverified" caveat only) ⇒ certificate can
   render SAFE TO CLOSE over unverifiable scope. 64 unaggregated per-path files exist.
5. **The close statement the operator wants does not exist as a contract.** operator-readout's
   certificate is `systemMessage` — human-only, TUI-only, dropped headless; it renders BESIDE the
   model's close. No arm checks for complication→solution→outcome or an explicit safe-to-close
   affirmation; none is origin-gated.

Refuted/parked (do not rebuild): kitty rails wholesale-dead (REFUTED — per-transport arms landed
7113e96d; the CLASS recurs → ambient-drift lint is #124's owner) · eval-track hooks-never-fire
(REFUTED today; task #70 rewritten to the surviving defects) · LIVE_ADDS ledger blindness (fixed
83fe0b84 yesterday) · deploy-circle postland-verify-vs-shared-checkout (REAL, owner backlog
7d6b462a468c — verify it does not block THIS session's converge at land time) · cap-exhaustion
(real, narrow: 2 sids/day; mitigation = D6/floors share tight latches, not new budgets) ·
G3 Bash-write attribution (real, 20% exoneration bucket; premises change under worktree rollout
#114 — decide at W4, else file).

## Solution — four waves, one owner

**W1 — libs + the origin Pyramid-close contract (D6).**
- `hooks/lib/origin-identity.sh` (NEW): extract `mark_fired_peer`-adjacent readers from
  handoff-fire.sh (:2391-2460 stamp read, :2631 `fired_stamp_tenancy`, :2657 by-cwd index read);
  handoff-fire sources the lib (behavior-identical), D6 consumes it. Semantics: 3-state
  origin|fired-peer|unknown; pane-id first, by-cwd index fallback (survives resume, seams §1b
  polarity: cwd-hit trustable for the CONTRACT consumer); **`closedAt` set ⇒ stamp SPENT ⇒ never
  fired-peer** (fixes the silent origin-miss AND the origin-self-close hole; handoff-fire tests
  pin both directions). cc-classify unification = filed follow-on (reaper behavior change).
- `hooks/lib/close-shape.sh` (NEW): (i) `close_shape_ok <msg>` — requires the three labeled
  elements (Complication/Solution/Outcome, label-anchored, case-insensitive) + an explicit
  close verdict (safe/good to close · yes/no form); (ii) `close_shape_template <rung> …` — the
  reason/template text. ONE source; consumers: completion-assert D6 (push), commands/wrap.md
  (pull). wrap-ledger keeps line-1 READOUT ownership.
- `completion-assert.sh` D6 arm (LAST, after D5): fires iff close-tell gate passed ∧ NOT assignee
  ∧ origin (lib) ∧ positive write evidence this session (session_writes_paths rc 0) ∧ RUNG ∈
  {✅,👤} ∧ `close_shape_ok` fails. Shares MAX=3 + hash latch. Reason = template. On 📦/🚀/⛔ the
  existing ledger arm already blocks with the drivable action; D6 owns the states where the ledger
  has nothing left to demand but the operator's two questions are unanswered.
**W2 — dispatch custody (G1).**
- `bin/cc-custody` (NEW): jsonl store `~/.claude/autonomy/custody/<cwd-hash>.jsonl`; verbs
  `open` (ts, originator cwd+pane, target pane, marker, slug, notifyBack) · `return <marker|slug>` ·
  `abandon <marker> --why` · `list --open [--cwd]` · `count --open --cwd`. cwd-keyed v1
  (CUSTODY_SRC=cwd; per-session worktrees make cwd unique; shared-checkout collision documented).
- Producers: handoff-fire.sh fire path calls `cc-custody open` beside `mark_fired_peer`;
  return path: `sc_announce_before_retire` + mailbox-drain.sh on `HANDOFF-PING <slug>` call
  `cc-custody return`.
- Consumers: wrap-ledger emits `CUSTODY_OPEN/CUSTODY_SRC` + readout note (NO new rung);
  completion-assert ledger arm gains contra term (custody_open>0 ⇒ "N dispatched session(s) not
  returned — collect/synthesize or mark returned/abandoned"); session-continue wake-floor treats
  custody-open like pending-mail (idle + custody open + no armed watcher ⇒ bounded block: arm
  `cc-await-ping`); operator-readout renders the custody line.
**W2b — the ship floor (the silent-📦/🚀 leak).** session-continue.sh new bounded arm (mirrors
wake-floor): idle turn ∧ ORIGIN ∧ RUNG ∈ {📦,🚀} ∧ unlanded-is-MINE (session-writes intersection,
rc2 ⇒ abstain-strict? NO — for a FLOOR, cannot-tell must abstain: nudging on a sibling's commits
is the #105 defect) ∧ not continue-armed ∧ no kill-switch ⇒ `decision:block`: "idle on
committed-unlanded work — /ship per the ship policy (or park explicitly: session-continue.sh
clear)" / 🚀 variant names deploy-live.sh. Bounds: one-shot per HEAD-sha, `CC_SHIP_FLOOR_MAX=2`
per session, latch dir shared with wake-floor pattern. This deliberately reverses the :519-520
design note — the note stays, amended with why (the adversarial verdict: the "ship policy's
business" had no actuator and 58% of stops assert nothing).
**W3 — repo-keyed DoD (G2).** `hooks/lib/dod-path.sh` (NEW): one resolution fn — key =
sha(origin-URL) when resolvable else sha(toplevel) (legacy); READ order: repo-key file, else
legacy path-hash file (migration-free); WRITE: repo-key path. dod-persist.sh + wrap-ledger.sh both
source it (kills the two-copy PATH CONTRACT). Existing 64 files stay readable via fallback.
**W4 — folds + verification.** commands/wrap.md:49 stale reso-hardcode deleted (perishable-fact
class) + /wrap gains the origin Pyramid-close template step (pull side of close-shape.sh);
CLAUDE.md § Session Close Protocol gains the origin-close contract paragraph (repo copy; then
hand-mirror to the REAL files ~/.claude/CLAUDE.md + ~/.claude-next/CLAUDE.md — verified real, not
symlinks); G3 decision (build worktree-attribution extension iff contained, else backlog); full
bats for every touched surface; gate; land via project-local /ship; `deploy-live.sh` converge
(watch for the deploy-circle refusal — if it refuses, that is 7d6b462a468c live: surface, file,
close 👤, never launder); re-read ledger; report.

## Outcome (target)

An origin session can no longer: idle silently on its own unlanded/unconverged work (W2b), close
"done" over unreturned dispatched waves (W2), or end a genuine completion without the operator's
two answers — Pyramid complication/solution/outcome + explicit safe-to-close (W1). A successor on
a fresh worktree inherits the real scope (W3). All bounded (shared caps/latches, harness cap 8
respected: D6 shares COMPLETION_MAX; floors cap at 2), assignee-suppressed, kill-switch-honoring,
fail-open on any read failure, IDL-logged.

## Decisions + why (do not delete)

- **D6 lives in completion-assert, not a new hook** — both expensive reads already paid there;
  Stop chain measured 3688ms; new hook re-pays both (seams §0.4, option A).
- **Channel = decision:block** — additionalContext costs the same turn + same cap-8 counter and
  is weaker for compliance (final-response-shaping §2b; seams 2a verdict).
- **Floors live in session-continue** — it owns the mechanical/idle arms + counter-file pattern;
  completion-assert owns message-shaped arms. One state model per hook family.
- **No new rung for custody** — await-with-armed-watcher is a LEGITIMATE end-of-turn; custody
  blocks only close-claims (completion-assert) and unarmed idles (wake-floor extension). A rung
  that fired on every in-flight wave would be an always-alarm (alarm-polarity).
- **✅-rung D6 does not fire on quiet mid-conversation turns** — D6 sits BEHIND the close-tell
  gate by design; the silent leak is 📦/🚀 (objectively unfinished) and is W2b's, not D6's. A
  shape demand on every quiet ✅ turn would be an always-alarm.
- **Spent-stamp fix changes handoff-fire behavior deliberately** (stricter: spent ⇒ origin) —
  aligned with the stated invariant (:4560-4572); pinned both directions by tests.
- Recon reports: `scratchpad/recon/report-{stopchain,seams,adversarial}.md` (this session's
  scratchpad); kitty/transcripts/census/ledgers/deaths reports pending — they refine W4/report,
  not W1-W3 shape.

---

## custody v1.1 — the discharge side (item `d29b73103189`, 2026-08-13)

**Complication.** W2 shipped the debt side of the custody ledger and exactly ONE discharge path:
a peer that reaches `handoff-fire.sh self-close`, which returns by MARKER off its own fired-peer
stamp. Two consequences the W2 plan text already anticipated but did not build. (a) Its own
Producers line — "mailbox-drain.sh on `HANDOFF-PING <slug>` call `cc-custody return`" — and its
Consumers line — "operator-readout renders the custody line" — described code that did not exist;
`bin/cc-custody`'s header asserted the first of them as fact. (b) Because self-close was the only
exit, `cc-custody open` had to exclude `--no-self-retire` fires outright (review #5, recorded at
`handoff-fire.sh:8936` as "until custody v1.1 adds the ping-receipt discharger"), and every peer
that finished, pinged, and was then closed by an operator, a reaper or a crash left its
originator's row open forever. An open row is 🔧 in `wrap-ledger.sh`, so a ledger that could only
ever accumulate debt decays into the always-alarm the "no new rung for custody" decision above
exists to prevent.

**Solution.** Three changes, one per surface named in W2:

- **`hooks/mailbox-drain.sh` — the ping-receipt discharger.** A received `HANDOFF-PING <slug>: …`
  discharges the originator's open row for that slug. The slug is the only custody field echoed to
  a peer (`handoff-fire.sh:7100`; `cloud-return.sh` mirrors the shape), so it is the only join key
  a ping can carry. Scoped `--cwd` — unlike `cloud-return.sh`'s store-wide return, which holds a
  globally-unique marker — because a slug is a prompt-file basename that two originators can
  collide on, and the ping's recipient IS the originator by construction. Idempotent (an
  already-discharged key is an rc-0 no-op, so the dup-biased delivery contract cannot double-count),
  bounded (8 slugs/drain, behind a `grep -q` gate), fail-open, `CC_DRAIN_CUSTODY_RETURN=0`.
- **`scripts/handoff-fire.sh` — the self-retire restriction lifted.** The guard now tests only
  "was a return owed" (`NB_ARMED_TARGET` non-empty). Safe because the debt and the discharge key
  are armed by the SAME condition: the trailer that writes `HANDOFF-PING <NB_SLUG>: …` is the
  trailer that sets `NB_ARMED_TARGET`, so every row now opened names a key its own peer was told
  to send back.
- **`hooks/operator-readout.sh` — the custody line.** `wrap-ledger` ranks open custody ahead of
  every remaining arm and short-circuits, so a custody 🔧 reached the renderer with `DIRTY_N=0`,
  `GATE` fresh and `REMAINDER=0` and rendered "🔧 in progress — loose ends": the ledger computed
  the one fact the operator needed and the renderer dropped it. Same class as the 🚀 dispatch
  defect (new-enum-member-falls-into-fail-closed-default), and it survived because the fallback is
  a TRUE sentence. Custody now LEADS `parts` and carries `cc-custody list --open --cwd .`. The
  FIRE PREDICATE is deliberately untouched — a block that fired on every in-flight wave is exactly
  the always-alarm the D-note above rejects.

**DISPROOF — the item's second clause, taken literally, is refuted.** It was filed as
"custody-open for `ENGAGE_VERIFY=0` fires", compressing two adjacent sentences at
`handoff-fire.sh:8933-8937`. Only the self-retire half is real work. `ENGAGE_VERIFY` is 0 iff
`RECYCLE` or `DRY` (`:7028`); a dry run fires nothing, and `--recycle` is *"same pane by
definition"* (`:6386`) — net-zero panes, no dispatched peer. A row opened there keys the firing
session's own cwd against its own pane: self-custody that no peer exists to discharge, blocking the
originator's ✅ until it abandons a debt it owes itself. A default recycle arms no back-channel at
all (`notify-back.bats:169`), and the one spelling that still does — an explicit
`--recycle --notify-back <third-party>`, verified live — is worse, because the ping then goes
somewhere that is not the originator, so even the new drain-side discharge could never run in the
session holding the row. `ENGAGE_VERIFY=0` is therefore CORRECT to skip, not a residual gap; the
comment at the call site now says so instead of flagging it as bounded-and-stated.

**Considered and rejected: `fire_cleanup`'s live-pane branch.** A FIRE-FAILED fire whose pane
survived is stamped, registered and left in its worktree "in case it engages late" — a live peer
with no custody row, which is genuinely the wave-abandonment signature. Rejected because that path
exits non-zero after telling the operator the fire failed: recording a debt there would make every
failed fire block its originator's close until a human ran `cc-custody abandon`. That is the
alarm-polarity failure again, on the one path where the operator has already been told to act.

**Tests.** `mailbox-drain.bats` +8 (discharge · cwd-scoping control · both slug-less ping shapes ·
unmatched slug · kill switch · cheap gate · dup no-double-count · RED-proof vs `origin/main`) ·
`operator-readout.bats` +5 (named cause + command · CUSTODY_OPEN=0 control · absent-field control ·
mixed-cause partition/ordering · RED-proof vs `origin/main`) · `notify-back.bats` +3 (the
slug-bearing recipe on a `--no-self-retire` fire · the `--no-notify-back` control that opens no row
· the guard pin with its RED control).
