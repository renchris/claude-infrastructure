# Wave A notes — items researched and not built (A7, A8, A9)

Scope (frozen, wave A): A1-A6 driven to landed and converged; A7-A9 researched, built only above 90%.
All three stayed at or below 90%, so none was built. Each is filed for the operator with `cc-decide`.
Research was read-only (2026-10-11, at trunk 1c1eb0571), with no live probes. The full evidence
was in a scratch file that is not kept; everything a decision needs is restated here.

## A7 — the reconciler mails `requester_pane` when a record's bucket changes: 75%

**What is confirmed (95%).** `report.py` `mail_requester` (`:736-744`) has no production caller.
`_report` (`__main__.py:~1095-1124`) calls only the page methods. `T.Record` has no requester
field. The request can also be claimed into `claimed/` before `_report` runs in the same pass, so
the requester has to be copied onto the record in `_census`.

**The fix as designed:**
- Add `Record.requester_pane`, copied from a cc-lr request's `requester_pane`. Wave A2 now writes
  that key. Reject flag-shaped values.
- Add `Reporter.requester_mail(cohort, rec, limited_panes)`. Its latch is keyed on
  `mail:<record_id>:<report.bucket>`, and `moving` is excluded.

**Why it stays at 75%:**
- **Mailing can wake a capped session.** A limited subject is woken by a cc-await-ping watcher,
  and the watcher is not gated on limit state. All three of tonight's deaths were
  task-notification wakes that burned a turn into a 429. The fix therefore needs a self-guard
  (`str(rec.pane[1]) == requester_pane`) and a deferral while the requester is itself an open
  LIMITED record.
- **Kitty window ids are reused after a kitty restart.** A mail keyed on a pane hours later can
  land in an unrelated session. The guard would check `requester_sid` against the registry, but it
  is unverified.
- **The latch is written before the emit.** A cc-notify timeout at 10 s under load 300-900 is
  therefore silent forever.
- **Volume is unsettled.** One `recover --all` can produce 4N mails. Whether to mail per record or
  per cohort is open (B3-2).

**Options:**
1. Build as designed, mailing every bucket change except `moving`.
2. Build it mailing only the `done` and `escalated` buckets, after a successful send, with 3 tries.
3. Leave it unbuilt. The requester reads `cc-lr status <sid8>`, which wave A3 now makes terminal.

## A8 — `plan.place` timeout turns every mover into wait-data: 75%

**What is confirmed.**
- `plan.py:216` sets a 30 s timeout. `:243-247` maps `TimeoutExpired` to `wait-data`, returning
  rc 124 for every mover.
- rc 3 has never happened in act mode: there is no `recon/fresh.stamp`. The later WAIT_DATA was
  therefore a non-answer (rc 124 or other) on a box at load 280-950.
- No rc is logged anywhere, which is why this had to be inferred.

**Reject the "keep the previous plan's placements" half.** `plan.movers` never re-places a
PLANNED record, so a timeout cannot erase an account placement. Reusing an account from a stale
plan would bypass `--place`'s batch charging and invariant 13, and across a reset it would be the
pre-reset rank that W6 resolution 11 forbids.

**What the timeout really does:**
- It overwrites an existing WAIT state. WAIT_SLOT becomes WAIT_DATA and restarts the max-age clock.
- A reset-due WAIT_RESET drops out of `_wakes`.

**The fix as designed:**
- On rc 124, leave every mover that already waits as it is.
- Scale the timeout to `min(120, max(30, 30*load1/(4*ncpu)))`. The 120 s cap keeps the watchdog's
  CPU floor satisfied.
- Log a `place` event with the rc and the duration.

**Why it stays at 75%.**
- The watchdog margin at the 120 s cap is computed, not measured.
- An adjacent finding (about 70%) means the fix alone would not have placed or woken the 04:00Z
  cohort. `recon/facts/next.auth.json` is a contradicted auth fact from 2026-10-04 with
  `resets_at:null`.
  - `facts.blocking` treats any auth fact as blocking.
  - After the reset, `census._binding` returns `("auth", None)`.
  - So the cohort reads LIMITED, not STAY, and `settle.rebucket` resets WAIT_RESET to DETECTED
    every pass. That is why 0 `wake` rows appear from 03:00 to 04:40Z.

  It needs its own item: skip a contradicted auth fact in `blocking` and in `_place_fact_live`, or
  have `F.expire` reap it.

**Options:**
1. Build the three-part fix: keep existing waits on no-answer, the load-scaled timeout, the event.
2. Build only the `place` event, to measure the rc before changing behavior.
3. First fix the contradicted-auth-fact defect, which is what actually blocked this cohort.

## A9 — cc-wake refuses a limited session as busy: 80%

**What is confirmed (90%).** `bin/cc-wake:149` requires the last presence beat to be `kind ==
stop`, or it refuses with "a turn is in flight".
- Stop does not fire on a limit turn. StopFailure writes a `limited` beat
  (`hooks/stop-failure-marker.sh:243-255`), and that beat carries no reset time.
- `~/.claude/logs/cc-wake.jsonl` holds three such refusals: e582464c at 04:10:20Z, 6defb493 at
  04:10:24Z and 58d3640a at 04:18:01Z. All three sessions were vendor-idle and past their 04:00Z
  reset.

**The fix as designed:**
- `session-beat.sh` gains `resets_at`.
- `stop-failure-marker.sh` moves its limited-beat call after `_sf_enrich_once` and passes
  `_SF_EN_RESET`.
- cc-wake accepts `limited` only once `now >= resets_at + 120`. Before that it refuses with a new
  word, `refused-limited`. It also adds one resume clause to the frame text.

**Why it stays at 80%, and why it is not this wave's to build.**
- Two of the three files (`hooks/session-beat.sh` and `hooks/stop-failure-marker.sh`) are outside
  wave A's file set.
- The hook reorder touches a death-path file that has its own anchor tests.
- A limited beat left stale under load (its overwriting prompt beat killed by the 3 s cap) is a
  residual hole, the same one a stale `stop` beat already has today.

**Options:**
1. Build the reset-gated fix across all three files in one session that owns them.
2. Change only cc-wake's wording, so the refusal says "limited", not "in flight", with no
   behavior change.
3. Leave it. The reconciler's own in-place reset wake is the designed path, and it is blocked by
   the A8 auth-fact defect above.
