# Decision 600709c5fe4b: the recycle load-hold bound (8/core) after Wave A

Read-only research, 2026-10-18/19. Inputs: `~/.claude/autonomy/decisions/600709c5fe4b.json`, its receipt
`docs/research/lr-inplace-immediacy-2026-10-18/raw/H-typed-relaunch-vs-load.md` (H), this incident's
`REPORT.md` §1 RC1 and §4 K1/K2/K7, and the unlanded Wave A branch (`lrwake-A`, commits `b2813111e` and
`3fb8bd3e6` on top of current `origin/main` `dfdb5c273`). **M** = measured (the command is shown). **I** = inferred.

## Answer

**Raise the commit bound to 24/core, but only after Wave A lands. Keep K7's hysteresis shape at 20/24, not 6/8.
Make the move worker wait on the precheck bound. Close 600709c5fe4b as "raise to 24 after Wave A", and amend
K7's numbers. Do not close it as superseded. Conviction 75%.**

1. **What the hold still prevents once K1/K2 are in.** It prevents exactly one thing: a typed relaunch that
   fails after the commit. That leaves the session at a bare shell with its resume debt open.
   - K1 means the watcher types nothing before `exit-committed`. K2 yields when the subject has already
     gone. A hold therefore no longer strands anything: it is a clean stand-down before any keystroke.
   - Typing is still the risk the hold guards, but the risk is unmeasured only *above ~32/core*. Between
     8 and 32 it is measured at 0 failures:
     - today: 33 of 33 typed lines above 8/core were submitted on the first attempt, across 17 relaunches
       (M, §3a);
     - H: 6 of 6 rows.
   - **H measures nothing hardened above 24.6/core.** Its 32-64 and 64+ buckets are empty. Its only
     failure is F1 at 42-45/core, which came before hardening and has no per-attempt telemetry.
   - Today adds 6 lines from 3 relaunches at 26.3-31.8/core, all submitted first try. The load that
     matters is that of the 1-min average at commit time. From a commit at ≤24/core, the load reached
     F1's band (>42) within 5 min in 0.1% of samples (M, §3d).
2. **K7 vs 24.** The two conflict only in the number. K7's "commit 8" was inherited from ship-land's
   `CC_GATE_MAX_LOAD_PER_CORE`. d-adversarial proposed "for example 6 versus 8" for hysteresis, not from
   typing data (`d-exit-dialog-and-stuck-exit.md:332-333`, `z-critic.md:135-137`).
   - The incident evidence supports raising it:
     - 8 of 11 STRANDED move verdicts today directly follow a commit-time load hold of the same session;
     - every move whose watcher got its relaunch typed despite the load moved: pane 332 at 26/core,
       47 at 20, 8 at 11 (M, §3c).
   - **Wave A as written undercuts any raise.** `HF_PRECHECK_LOAD_PER_CORE` defaults to an absolute 6
     (`lrwake-A:scripts/handoff-fire.sh` `hf_recycle_precheck_load_bound`). With only the commit bound
     raised to 24, every in-place move still holds at the precheck above 6/core.
   - `lr-move-worker.sh` waits on the *commit* bound, not the precheck's (`mw_load_bound`, :276-288, not
     touched by Wave A). Between 6 and 8/core the worker therefore proceeds into a precheck `HELD:load`.
     That hold is final NOTMOVED, because only `HELD:unreachable` is retried (:383). At the worker layer
     the hysteresis is inverted.
3. **Tonight's loads.** Since 2026-10-18T00:00Z, `handoffs.jsonl` has 38 `recycle-held-load` rows at
   8.17-48.89/core:
   - 24 from moves, 7 from the reconciler, 7 others;
   - 10 carry `unconfirm rc 2`;
   - 25 of the 38 were at or below 24/core.

   Move verdicts over the same window:

   | Verdict | Count | Breakdown |
   |---|---|---|
   | MOVED | 9 | 3 above 8/core, each only because the RC1 race bypassed the hold |
   | NOTMOVED HELD:load | 24 | 15 at commit, 6 at the precheck, 3 at the worker's 3,600 s wait |
   | STRANDED | 11 | 8 follow a load hold |
   | FAILED | 1 | |
   | other NOTMOVED (busy, slot, claims) | 119 | |

   The box spent 78% of measured time above 8/core and 35% above 24 (M, `~/.reso/load.jsonl`).
4. **Recommendation.**
   - **Raise to 24 after Wave A, 75%.** Do it as `HF_RECYCLE_HOLD_LOAD_PER_CORE=24` plus
     `HF_PRECHECK_LOAD_PER_CORE=20`, with the worker waiting on the precheck bound. The two code defaults
     need a 5-line change, not an `=off`.
   - Keep 8 is safe after K1, but it turns a loaded box into "moves almost never happen". At 8, only
     209 min of ~20 h measured were below the bound, and only 6 dips lasted 10 minutes or more.
   - Wave S is the endgame and makes the bound moot. It is tier 3, behind A, C, E and H2, and it is
     entangled with Q3 (SIGTERM stops background tasks). It should not gate the bound.
   - Do **not** raise before Wave A lands. Without K1 the 60 s nudge races any slow foreground at any
     bound.

## Evidence

### 1. What the hold guards after Wave A (code, M)

- **The gate's own stated purpose.** It cites F1: pane 44 typed `/exit` at about 45/core, then the typed
  relaunch "failed 16 times and stranded the pane". It holds only when the relaunch will be *typed*,
  meaning no staged successor exists, which is true of every resume recycle and so of every move
  (`lrwake-A:scripts/handoff-fire.sh`, comment above `hf_recycle_load_bound`).
- **Where it sits.** The load hold is at the K2 call site, *before* the resume debt and the K1 marker:

  ```
  rcy_load_rc=0; hf_recycle_load_gate "${tty:-}" || rcy_load_rc=$?
  if [ "$rcy_load_rc" = 1 ]; then
    if hf_recycle_subject_gone; then hf_recycle_subject_yield "at the load hold"; return 0; fi
    hf_recycle_hold load ...
  ...
  date +%s > "$cmdfile.exit-committed"      # K1, after the last hold and the debt
  ```

  So after Wave A a hold happens while the watcher is still waiting for the marker. Per the `b2813111e`
  message, the watcher does no nudge and no bg-work answer before the marker, and on `exit-aborted` it
  stands down.
- **What is left for load to break.** Only the work after the commit: the typed `/exit` (or
  `hf_exit_signal`), then the watcher's typed relaunch.
  - The move lane runs with `LR_ADMIT_MODE=swap` (`lr-move-worker.sh:406`). The launcher's in-pane
    admission therefore does not run (`lr-fire-resume.sh:770-772`), so admission cannot refuse a move's
    relaunch after `/exit`.
  - That leaves the kitty-RC typing transport, which is F1's failure.
- **The transport's load scaling** (`handoff-fire.sh:4508`): `echo deadline = settle × (4 + 2 × load)`,
  capped at `settle × 60`.
  - Telemetry shows settle = 0.5 s: `echo_deadline_ms=28440` at 26.44/core.
  - So the echo wait scales up to 28/core and is flat at 30 s above that.
  - A 24/core bound keeps the commit inside the band where the transport's deadline still grows with
    load (I: this is a margin argument, not a measured failure point).

### 2. What H measures above 24.6/core (M, receipt)

| H bucket | Rows | Outcome |
|---|---|---|
| 16-32 telemetered rows | 3 | max 24.57 |
| 32-64 | 0 | |
| 64+ | 0 | |
| F1, pre-hardening, 42-45/core | 1 | the only load-tracked failure, no per-attempt record |
| bats rows at 32-52 | 4 | excluded: stub transport |

H's own conclusion: "nothing hardened exists above 24.6/core". It also notes that the hold prevents new
samples above 8. Today's RC1 race accidentally produced those samples (§3a).

### 3a. Today's typed attempts (M)

```
jq -r 'select(.ts>="2026-10-18" and .class=="recycle-type-attempt" and .under_test==false) | …' ~/.claude/logs/handoffs.jsonl
rows=43 above8 rows=33 recycles=17 | above24.6 rows=6 recycles=3 | max load=31.84 | verdicts: submitted=43 | non-first attempts=0 | max send_ms=8000
```

The relaunches above 24.6/core:

| Pane | Time | Load (/core) | What it was | Outcome |
|---|---|---|---|---|
| 332 | 03:39Z | 26.44 / 26.28 | move | engaged 03:40:39, MOVED |
| 398 | 10:32Z | 30.32 / 31.84 | reconciler | submitted |
| 393 | 10:41Z | 29.31 / 29.43 | reconciler | submitted |

- Panes 398 and 393 then show `recycle-dead`: `FAILED:relaunch:rc=9 … launcher REFUSED: term=active`.
  The typed command ran, and capacity admission refused it. That is RC2 / Wave B, not typing, and moves
  are exempt from that gate (swap).
- **All 9 `recycle-dead` rows today are launcher admission refusals.** None is a typing failure.

```
jq … 'select(.class=="recycle-dead")' → 9 rows, every detail "FAILED:relaunch:gate|rc=9 — … launcher REFUSED"
```

Combined with H's post-hardening rows, typed lines above 8/core stand at 39 submitted and 0 failed. That
is about 22 relaunches above 8. By the rule of three, the 8-32 failure rate is below about 14% (95%).
Above 24.6 there are only 3 relaunches (26-32/core).

### 3b. `recycle-held-load` since 2026-10-18 (M)

```
jq -r 'select(.ts>="2026-10-18" and .class=="recycle-held-load") | (.detail|capture("load (?<l>[0-9.]+)/core").l|tonumber)' … 
n=38 8-16:21 16-24:4 24-32:9 >32:4        # by source: 24 move, 7 recon, 7 other; 10 carry "unconfirm rc 2"
```

The 24 move rows split 15 at ≤24/core and 9 above. A 24 bound would have let 15 of the 24 move-row holds
and 25 of all 38 rows proceed.

### 3c. Move verdicts since 2026-10-18 (M)

The command: `jq` over every per-session `~/.reso/limit-recover/move/*/<sid>.json` with `ts>="2026-10-18"`
(164 verdicts).

```
   9 MOVED   143 NOTMOVED   11 STRANDED   1 FAILED
  24 NOTMOVED | HELD:load
```

**HELD:load, 24.** Where each hold fired:

| Where | Count | Identified by |
|---|---|---|
| Commit-time | 15 | there is a matching `recycle-held-load` row |
| Precheck | 6 | after `d58bb81d3` landed at 12:14Z, with no row: 12:50, 15:45 ×2, 15:49, 15:50, 16:47 |
| Worker wait | 3 | "stayed above the 8/core recycle bound for 3607s", batch `132615Z` |

The held moves cover 11 distinct sessions. f06b5e9b took 4 holds over about 6 h before it MOVED at 19:24Z.
98e6f890 took 5 holds before it MOVED at 16:51Z. 9f6593c5 never moved.

**STRANDED, 11.** Eight follow a commit-time load hold of the same session within about 7 min:

| Hold at | Pane | Strand at |
|---|---|---|
| 02:08 | 20 | 02:14 |
| 02:21 | 24 | 02:28 |
| 07:06 | 1 | 07:11 |
| 07:06 | 21 | 07:11 |
| 07:23 | 22 | 07:28 |
| 07:24 | 332 | 07:30 |
| 08:45 | 10 | 08:47 |
| 10:39 | 242 | 10:46 |

- Seven of the eight holds carry `unconfirm rc 2`.
- Pane 10's hold carries `unconfirm rc 0`. Its `handoff.log` says "the session is alive in pane 10;
  nothing was typed", yet the worker found no live process. That is RC1's lying line again.
- The other 3 strands are not load holds:
  - 246a91b5 (rc 2, debt proven);
  - e3dedc17;
  - e739e5b5 at 15:49, which is `REFUSED:registry`.

**MOVED, 9.**

| Load at the typed relaunch | Panes |
|---|---|
| above 8/core | 332 at 26.3, 47 at 19.2, 8 at 10.8 |
| near 8/core | 350 at 8.5 |
| below 6/core | 340, 384, 386, 445, 458 |

- Panes 332, 47 and 8 moved only because the watcher's pre-commit `/exit` got Claude out before the
  foreground's hold. Their foregrounds then logged `recycle-subject-exited` (47, 8) or held with
  `unconfirm rc 2` after the move had already engaged (332). Each relaunch was typed and engaged.
- **The pattern.** At the same 11-28/core loads, every session where the hold did not intervene MOVED,
  and the sessions where it did were STRANDED.

### 3d. Load over the window (M, `~/.reso/load.jsonl`, 12 s cadence, 05:00Z 10-18 to 04:39Z 10-19, one 3.1 h gap)

```
n=5194 >6:88% >8:78% >16:46% >24:35% >32:20% >45:7.5%
bound 8:  dips=48 dips>=10min=6  total_below_min=209  longest=26min
bound 24: dips=22 dips>=10min=4  total_below_min=885  (longest run spans the 3.1 h gap; ignore it)
P(load_1m/core > 32 within 300 s | commit at ≤24) = 0.004 ; P(> 42) = 0.001   (n=3343)
```

`capacity-alarm.jsonl` agrees: the max is 70.86/core, and hour-weighted 83% of hours are above 8 and 50%
above 24.

So 24 is no cure-all: on a day like today, moves would still wait about a third of the time. It does open
the 8-24 band where 25 of 38 holds sat.

### 4. K7 as built on `lrwake-A` (M, code)

- `hf_recycle_precheck_load_bound` uses `HF_PRECHECK_LOAD_PER_CORE` with a default of **6**, clamped to
  ≤ the commit bound. Raising only `HF_RECYCLE_HOLD_LOAD_PER_CORE` therefore leaves the precheck at 6.
- `lr-move-worker.sh:276-288` `mw_load_bound` reads `HF_RECYCLE_HOLD_LOAD_PER_CORE` /
  `CC_GATE_MAX_LOAD_PER_CORE` (the commit bound). `git diff origin/main...lrwake-A -- scripts/limit-recover/`
  is empty.
- The worker passes its wait at less than 8. lr-handoff's probe (`HF_PRECHECK_TYPED_RELAUNCH=1`,
  `lr-handoff.sh:1437`) then holds at more than 6. The worker treats that `HELD:load` as final (:383).
  **On the box's 6-8 band (10% of today's samples), every move ends NOTMOVED** without waiting.
- The fix: the worker waits on the precheck bound, and the two defaults move together, for example
  20/24.
- `tests/handoff-recycle-kitty-precheck.bats:354` already exercises `HF_PRECHECK_LOAD_PER_CORE=20`.

## Options assessed

| Option | After Wave A, what fails | Cost on a day like today | Verdict |
|---|---|---|---|
| keep 8 (K7 6/8 as built) | nothing strands | 78% of time held; moves happen only in rare short dips; plus the 6-8 worker/precheck inversion | safe but the lane is effectively off under load |
| **raise to 24 (precheck 20)** | a typed relaunch fails at 8-24: measured 0 of about 22, under 14% at 95%; the result is a shell plus an open resume debt, picked up by the watcher's failure arms and reconciler (I) | 35% of time held | **recommended, 75%** |
| Wave S (keystroke-free) | none from typing, so the bound is moot | 260+260 LOC, tier 3 after A, C, E and H2; needs Q3 answered (SIGTERM kills bg tasks) | the endgame; it does not gate this |
| raise before Wave A | the 60 s nudge still races any slow foreground | | no |

## How to close 600709c5fe4b

Close it as **decided: raise to 24 after Wave A lands**, with K7 amended to "precheck 20/core, commit
24/core, worker waits on the precheck bound, no `=off`".

- **Not "superseded by Wave A + K7".** K7 hard-codes the inherited 8 and adds a 6 that strangles the lane
  further. Wave A does not touch why the number is 8.
- **Not "superseded by Wave S" either.** S is unbuilt, and until it lands this bound governs every move.

Open a backlog follow-up to re-measure once 24 is live. `recycle-type-attempt` rows at 24-32 will
accumulate, because the hold is no longer suppressing them. Revisit if any non-first attempt or any
`echo-unverified` appears above 16/core.

## Adversarial pass

1. **The above-8 samples might not be the move lane's transport.**
   - They are the same watcher typing function, so the same rows and telemetry fields.
   - Panes 332, 47 and 8 are move-lane watchers (`move-…` attempt keys). The 390, 393 and 398 rows are
     reconciler relaunches through the same path.
2. **A dead relaunch might be a hidden typing failure.**
   - All 9 `recycle-dead` rows name a launcher refusal, which is rc 9 written by `lr-fire-resume` itself.
   - That proves the typed command reached the shell and ran.
3. **The load might jump between commit and typing.**
   - Measured: from ≤24, it exceeded 32 within 300 s in 0.4% of samples and 42 in 0.1%.
4. **What was not checked.**
   - Whether the watcher's post-commit failure arms re-type on an echo-unverified line above 28/core,
     where the echo deadline caps. No field sample exists.
   - Whether a strand at 8-24 is auto-recovered without an operator. The reconciler did retry stranded
     sessions today (the `recon:` keys), but this is inferred, not traced end to end.
   - These two keep conviction at 75% rather than 85%.
