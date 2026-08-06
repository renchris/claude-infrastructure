## Brief-drift check: CLEAN
Product/design question about the operator's own repo. No entity-as-subject, BD, legal, or competitive framing. Proceeded.

---

# Micro-event source material — ranked

## What the world can already do (constrains every candidate below)

Read from `tools/banner/gen.py` @ `cac9dde2` (branch `feat/banner-showoff`, the live v6 line) and `docs/plans/README_HERO_BANNER.md`:

| Fact | Value | Consequence |
|---|---|---|
| Canvas / ground | `W,H = 1920,600` · `GROUND = 506` · sprite `220×160` @ CELL 20 | Three usable bands: sky `y<82`, mid `y 208–506`, foreground `y 506–600` (94 px, already hosts tufts + the `peek` clip) |
| Master period | `P = 240` s; **every sub-period must divide P exactly** (S2) | Legal: 0.5/2/4/8/10/24/30/60/80/120. A 4 s beat = **1.7 % duty cycle** |
| Wordmark keep-out | `KEEPOUT = (372,82,1548,208)` + soft 130 | Any sky event must clear it; scrolling layers need a **Y**-invariant, not an x-position (`assert_type_clear`) |
| Legibility floor | 12 px/cell (`assets/banner/clawd-reference.svg` ramp) | Bounds creature count per composition |
| Structural rule | one animation per element; phase via keyframe % not `animation-delay` (S8, `banner-shots.sh --lint`) | Every event = a nested single-animation group |
| Existing event vocabulary | `events = ("shootingstar","balloon","birds","peek")` + `rCheer`/`rSleep`/turn-around | **All four carry zero repo semantics.** This is the gap. |
| Existing semantic beat | `second_session()` gen.py:1064 — "a second session walks in from the right, the two meet, both throw their arms up, and the newcomer carries on" | **Precedent: synchrony + co-location conveys relationship with no connector drawn.** |
| `peek` | `<g clip-path="url(#belowGround)">` | **Precedent: enter/exit-frame conveys birth/death with no connector.** |

**Four legal grammars for a relationship without a link:** (1) co-location, (2) phase/synchrony, (3) entering or leaving frame, (4) one creature acting on world furniture. Illegal: any drawn thread, arc, pulse-travelling-a-path, or arrow.

**Emblematic-by-frequency check** (`git log --oneline -600`, scope prefixes): comms 38 · handoff-fire 31 · relogin 28 · ground-up 25 · accounts 19 · ship-land 13 · gate 12 · postland 10 · desk 10 · activation 10 · reaper 9 · daemon-fleet 9. This corroborates the README's five properties and adds one the README under-weights: **the repo spends more effort asking "is my own guard actually running?" than on any single feature.**

---

## Ranking

| # | Behaviour | Emblematic | Legible | No-link | Verdict |
|---|---|---|---|---|---|
| 1 | Daemons tick on uncorrelated periods | ●●● | ●●● | PASS | build first |
| 2 | A finished turn is refused and sent back | ●●● | ●●● | PASS | build |
| 3 | Heavy work yields; foreground pace never changes | ●●● | ●●● | PASS | build |
| 4 | It pages you only for a decision — then waits | ●●● | ●●● | PASS | build |
| 5 | Every write leaves a copy; the oldest ages out | ●●○ | ●●● | PASS | build |
| 6 | Nothing dies without positive evidence of death | ●●● | ●●○ | PASS | build |
| 7 | One opens another, then leaves | ●●● | ●●● | PASS* | extend existing |
| 8 | One narrow spot on the line; the rest wait | ●●○ | ●●○ | PASS | build |
| 9 | Four lanes; one empties, work appears elsewhere | ●●○ | ●●○ | PASS | build w/ care |
| 10 | The light that stays on all night | ●●○ | ●●● | PASS | background invariant |
| 11 | A message lands and waits to be read | ●●● | ●●○ | **CONDITIONAL** | see caveat |
| 12 | Built, staged, not switched on | ●●● | ●○○ | PASS | risky |
| 13 | Landed is not yet live | ●●● | ●○○ | BORDERLINE | risky |
| 14 | A guard that stopped watching flags itself | ●●● | ○○○ | PASS | near-invisible |

---

### 1 · The daemons tick on their own clocks, and rarely line up
**Plain:** thirteen small background jobs each wake on their own schedule, forever, whether or not anyone is watching.
**Evidence:** `launchd/*.plist` (14 files) — `com.claude.session-search-sweep` 60 s · `com.chrisren.autonomy-sweep` 5 min · `com.claude.postland-verify` 5 min · `com.claude.desk-invariant` 5 min · `com.claude.team-orphan-reaper` 10 min · `com.claude.dispatcher` 15 min · `com.claude.discovery` 60 min · `com.claude.nightly-regression` 4 am. Declared in `launchd/fleet.manifest` with an `interval_s` field per label; reconciled by `bin/cc-fleet`.
**Why emblematic:** this is the literal difference between a dotfiles repo and this one — the config has *processes*. It is also **structurally native**: the P=240 divisor rule (S1/S2) is the same mathematics as a cron fleet. `gen.py:606-607` already animates ground tufts at `P/8` (30 s) and `P/10` (24 s) — the mechanism exists and is currently decorative.
**Visual grammar:** *Begin* — nothing; it is the world's baseline pulse. *Middle* — five or six distinct foreground ground-marks (`y 506–560`, below the keep-out entirely) each pulse one cell brighter for ~0.4 s on its own divisor: 8 s, 10 s, 24 s, 30 s, 60 s, 120 s. Never a sweep, never left-to-right. *End* — once per 240 s loop several coincide for a single frame, then scatter again. That coincidence is the only "event"; the rest is texture.
**No-link:** PASSES cleanly — no object ever touches another; the relationship is *arithmetic*, invisible by construction.

### 2 · A session says it is done, and the system sends it back
**Plain:** when a session tries to end while work is still unfinished, the ending itself is refused and the session goes back to work.
**Evidence:** `hooks/completion-assert.sh:129` emits `{"decision":"block"}` when a close-tell is contradicted by the live git ledger (`scripts/wrap-ledger.sh --machine`: `DIRTY`, `UNLANDED`, `REMAINDER`); header names the defect — *"Only a human re-asking 'are you sure?' caught it… This hook IS the mechanical re-ask."* Paired with `hooks/session-continue.sh` (agent arms a sentinel on 🔧; the Stop hook is a "dumb actuator" that blocks and feeds the next step back, capped by `CLAUDE_CONTINUE_MAX`).
**Why emblematic:** it is the repo's sharpest single idea and it appears nowhere else — a hook that refuses a *false claim of completion*. README §3 headlines it ("Refuses a false 'done'"). Not true of any repo.
**Visual grammar:** *Begin* — clawd's walk stride stops; it settles (the existing `rSleep`/eShut geometry, one cell down). *Middle* — one firm, unmistakable beat: the ground rule under its feet flashes once and clawd is nudged back exactly one cell — a refusal with no text. *End* — legs resume the 0.5 s stride. Total ≈3 s, once per 120 s.
**No-link:** PASSES — one creature and the ground it stands on.

### 3 · The heavy work steps aside for you
**Plain:** the system's own test runs demote themselves to the lowest priority band so they can never slow down what you are doing.
**Evidence:** `bin/cc-bats` — a `bats` shim installed earlier on PATH so every invocation self-demotes; header records the census that forced it: *"72 of 103 live bats procs at pri=31… coverage: 30 % of procs, 0 % of CPU."* `scripts/qos-census.sh` calibrates the bands empirically: `nice 19 alone → PRI=31` (**not** demoted); only `taskpolicy -c background → PRI=4`. Also `scripts/postland-verify.sh` ("BACKGROUND QoS with NO admission sleeping"), `com.claude.postland-verify.plist`.
**Why emblematic:** it is the *inversion* the repo is proud of — "stop asking the caller to demote itself (measured to fail 70 % of the time) and make the TOOL demote itself." Distinctive, load-bearing, and it maps onto parallax speed, which is already the scene's native language.
**Visual grammar:** *Begin* — a mid-ground layer (the second cloud band, `y 208–300`) accelerates noticeably for ~1 s. *Middle* — it drops to a visible crawl, ~⅕ speed, and stays there for ~5 s. *End* — resumes normal drift. Clawd's stride is **provably unchanged** throughout — that is the whole content of the beat. Once per 120 s.
**No-link:** PASSES — nothing connects; the statement is about two *rates* in one frame.
**Built, flagged, and the flag may already be spent (2026-08-06).** It exists as `standaside` / THE HEAVY THING YIELDS. It was flagged as hard to notice alongside item 12 in decision `47b392d6e9eb`, which **defaulted to KEEP** on 2026-08-06 — but the dates do not line up cleanly and that matters to whoever rules on it. The "too subtle" defect was diagnosed and fixed in `c5ed9c6c` (fast segment 110 px → 190 px, i.e. 3× baseline → 5.6×), committed **05:31:07Z on 2026-07-31**; the reservation was recorded **05:45:26Z the same morning, fourteen minutes later**, and the session transcript is gone, so whether the author re-watched the boosted version is not recoverable. Post-fix it measures **4.90 % frame movement, 13th of 27** — five times item 12's. Judge it fresh rather than inheriting the flag.

### 4 · It interrupts you only when a human must actually decide — and then it waits
**Plain:** it runs unattended, and the one thing it will not do on its own is make a decision that is yours; it raises a marker and waits indefinitely.
**Evidence:** `bin/cc-decide` — three classes; **class C** ("HARD-BLOCK, human-only: C10 self-mod / C6 money-path / permission denial: WAITS, has NO default"), class B carries `default_if_no_veto` + `veto_deadline` that fires at the deadline. `hooks/operator-readout.sh` renders every operator-owned step as `▶ <exact command>` from disk truth. `bin/cc-blockers` (881 lines) is the one-glance board. `bin/cc-digest` is explicitly *"batched, never an interrupt."*
**Why emblematic:** this is the repo's actual product claim ("pages you only when a human must decide"), and the honest depiction — *it just waits* — is unusual and restrained, which suits a header.
**Visual grammar:** *Begin* — for 200 s of the loop nothing calls out at all. *Middle* — one small marker rises from behind the ground line at the far right (reuse the `belowGround` clip that `peek` already uses), comes to rest a few pixels proud of the horizon, and holds. *End* — **there is no end.** It stays lit for the remaining ~35 s and is still there when the loop wraps, so it appears continuous. Once per 240 s.
**No-link:** PASSES — one object, one surface, no addressee drawn.

### 5 · Nothing is overwritten; every version keeps a copy, and old copies age out
**Plain:** before any file is changed, the previous version is saved; ten are kept, and after thirty days they quietly disappear.
**Evidence:** `hooks/backup-before-write.sh` (PreToolUse Write/Edit; nanosecond+PID names for agent-team race safety; sidecar `.path` files); `scripts/prune-backups.sh:4-8` — *"Keep last 10 backups per basename (3 for .sh)… Delete ALL backups older than 30 days… Skip files modified <5 min ago."* Restore path `scripts/restore-file.sh`.
**Why emblematic:** README property 4 ("Nothing a session did dies with it") and the one guarantee a viewer will instantly understand without knowing what a session is. Weakly distinguishing on its own (backups are common) — its emblematic force is the *stack-and-expire* rhythm, which is unusual to show.
**Visual grammar:** *Begin* — clawd sets a single pixel-block down on the ground line. *Middle* — behind it, a faint offset ghost of the same block appears, then another; three or four accumulate, each dimmer than the last. *End* — the faintest one at the back fades out entirely as a new one is added at the front. Reads as a natural decay, ~6 s, once per 60 s.
**No-link:** PASSES — creature and furniture.

### 6 · Nothing is cleaned up unless it can be *proved* dead
**Plain:** the system closes finished sessions automatically, but it will never close one just because it went quiet.
**Evidence:** `bin/cc-reaper:1-45` — reaps only three provably-terminal causes, requires **all** of: classified cause + work landed (re-verified) + idle past the settle window + WIP checkpointed to `refs/wip/<name>/LAST` + the spawner's `cc-fired` stamp; *"done-evidence is DERIVED from positive signals… NEVER inferred from silence — 'idle ≠ done'."* `scripts/team-orphan-reaper.sh:6-14`: *"A MISSING or empty watchdog pid file is UNKNOWN, not dead… Absence of a pid file is not evidence of death."*
**Why emblematic:** the epistemic signature of the whole repo, stated twice in two independent files. Deeply distinguishing.
**Visual grammar:** *Begin* — a second creature at the frame's edge stops moving mid-stride. *Middle* — a slow, wide dim band passes over the whole scene (a cloud shadow, ~4 s) and the still creature is **not** removed. It stays through the shadow, and through a second one. *End* — only after it has been still across a full 80 s does it fade out in one step. The *not-removing* is the beat; the removal is the punctuation.
**No-link:** PASSES. Needs two creatures but they never interact — the relationship is between a creature and *time*.

### 7 · One session opens another, then leaves
**Plain:** a session can open a fresh one, hand over, and shut itself down — nobody starts the second one.
**Evidence:** `scripts/handoff-fire.sh` (2,652 lines) — `--split-right` anchored to `$ITERM_SESSION_ID`, `--recycle` (relaunch this pane in place), `self-close --successor <uuid>` requiring the successor be *verified engaged* (resolvable + `claude` on its tty + a real assistant turn in its transcript) before `/exit`. README:49-51.
**Why emblematic:** it is the banner's own subtitle. **Caveat (R1):** making the *whole* banner this was rejected; as one micro-event among ten it is in-bounds, and `second_session()` already ships half of it.
**Visual grammar:** *Begin* — a newcomer enters from the right edge, walking. *Middle* — it reaches the resident; both throw arms up on the **same frame** (`pCheer` period == `cheer_period`, already enforced at gen.py:139-141). *End* — **the extension:** the resident walks off the left edge and the newcomer takes over the stride. Once per 240 s.
**No-link:** PASSES — precedent already set in the shipped generator. Synchrony carries the handover; nothing is drawn between them. *Do not* add a pulse, spark, or dotted arc.

### 8 · Many can work at once; exactly one can land at a time
**Plain:** any number of sessions run in parallel, but the moment work is published there is a single machine-wide gate, held for seconds.
**Evidence:** `scripts/land-lock.sh` — one mutex keyed on `--git-common-dir` (shared across all worktrees; header explains why `--show-toplevel` would let two worktrees land concurrently), pid+lstart liveness so a recycled pid cannot fake a live holder, `LAND_LOCK_WAIT` 3600 s queue. README §2 diagram: "held seconds: the CAS push window only."
**Visual grammar:** *Begin* — three creatures walking their own lanes. *Middle* — one reaches a single narrow bright notch in the ground rule; the other two **stop where they are**, mid-stride, for ~2 s. *End* — the notch dims, all three resume. The waiting is the whole picture.
**No-link:** PASSES — the relationship is expressed by *stillness*, not a connector. Risk: with a wide notch it can read as a turnstile diagram; keep the notch a single cell.

### 9 · Four accounts, four windows, each refilling on its own clock
**Plain:** work is spread across four separate accounts, each with a usage budget that empties and refills on its own five-hour clock; when one is empty the work simply happens elsewhere.
**Evidence:** `bin/claude-accounts` (1,709 lines) — per-account 5 h / weekly / Fable buckets with `resets_at` stamps, live-limit ranking (`--rank`), *"exit 2 = data was fine but nothing routable by POLICY (exhausted / 5h cutoff / window) — callers must NOT fire blind"*; `accounts.json` is the SSOT; consumed by `scripts/handoff-fire.sh --account auto` and `bin/cc-wave-plan`.
**Visual grammar:** *Begin* — four ground-marks at four x-positions, each at a different fill height. *Middle* — one visibly drains to nothing over ~8 s; a creature that was in that lane is simply **absent** on the next cycle and a creature appears in a different lane. *End* — the drained mark refills from zero over the following 30 s.
**No-link:** PASSES. **Risk:** four level-indicators is one step from a HUD/bar-chart, which restraint rule 4 and R2 both push against. Only build if the marks are world-objects (stones, tufts) whose *height* changes, never rectangles that read as gauges.

### 10 · One light stays on all night
**Plain:** the machine is deliberately never allowed to fall asleep, so the work continues while nobody is there.
**Evidence:** `scripts/caffeinate-floor.sh` — a RunAtLoad + KeepAlive LaunchAgent that `exec`s `caffeinate -i -s` with **no `-t`**, so the assertion is held forever; header: *"on BATTERY… nothing holds a sleep assertion → the machine idle-sleeps in ~1 min, freezing every session. This is the durable floor."* Plus `com.claude.caffeinate-floor.plist`, `scripts/power-policy-verify.sh` (60 min posture assert), `com.claude.nightly-regression` at 4 am.
**Visual grammar:** not a beat — a **background invariant**. Through the darkest phase of the sky, when the star tiers have dimmed and clawd has run its `rSleep`/Zzz emote, exactly one point of light in the scene never dims. It is the only element exempt from the night dimming.
**No-link:** PASSES. Best used as the composition's quiet constant rather than as a scheduled event.

### 11 · A message arrives as a file and waits to be read — CONDITIONAL PASS
**Plain:** one session leaves a message for another as a line in a file; it waits there until the recipient is at a safe point, and is consumed exactly once.
**Evidence:** `bin/cc-notify:20-31` — appends one line to `~/.claude/mailbox/<uuid>.md`, *"NEVER as keystrokes on its live input line"*; `hooks/mailbox-drain.sh` surfaces it as `additionalContext` at SessionStart/UserPromptSubmit; `.seen` cursor makes delivery exactly-once, `.acked` only at the Stop after a turn provably carried it; `bin/cc-await-ping` — *"the mailbox write is the wake."* 38 `comms(...)` commits, the single most-worked scope.
**Visual grammar:** *Begin* — a small object drops into frame from **off-screen** and lands near a sleeping clawd. *Middle* — it sits, untouched, for ~10 s while clawd stays asleep (this waiting is the semantic payload: it is not an interrupt). *End* — clawd wakes at its own next blink boundary, and the object is gone in one frame.
**No-link:** **PASSES ONLY IF THE SENDER IS NEVER DRAWN.** The instant a second creature is visible as the origin, this becomes precisely the A→B handoff infographic R1 rejected. State this constraint in the build brief or drop the candidate.

### 12 · Built, staged, and waiting for one human hand — RISKY
**Plain:** parts of the system are finished but deliberately switched off until the operator turns them on, and the system says so out loud rather than pretending they are running.
**Evidence:** `docs/activation/pending-activation/` — **23** activation scripts (`01-reap-guard…` through `18-fleet-activate`). `launchd/fleet.manifest`: `expect=staged` → *"Always emits exactly ONE row, state=UNDECIDED — 'declared, decision pending: surfaced, never silent'… ambiguity is DECLARED, never resolved by an agent guessing."* `bin/cc-fleet` six-state function; `hooks/activation-watch.sh`; 10 `activation(...)` commits.
**Why emblematic:** it is the honest core of the repo's autonomy story and its most-recent working front. **Why risky:** "a thing that exists but is not on" has no motion. Any depiction (an unlit shape that stays unlit) is indistinguishable from scenery, which is the decorative-field failure mode.
**Visual grammar (best available):** a short row of small dark blocks at the foreground edge; once per 240 s exactly one of them pulses a single dim frame and returns to dark. Nothing is ever lit.
**No-link:** PASSES. Recommend building only if a stronger candidate fails review.
**Built, and the risk above was borne out — RULING DEFERRED, NOT SETTLED (2026-08-06).** It exists as `staged` / THE UNSWITCHED in `tools/banner/emotes_infra.py`. The "indistinguishable from scenery" risk this section predicted is real and measured: **0.94 % frame movement at its showcase peak, the lowest of all 27 candidates** (`scripts/emote-verify.py --calibrate`), clearing the static-panel tripwire by 0.14 points. A proposal to cut it before the hero-banner promotion was raised on 2026-07-31 (decision `47b392d6e9eb`) and **defaulted to KEEP** when its veto window expired on 2026-08-06 — the chosen option was *"keep all eight on the review page and decide by eye"*, so the cut question is **open and deliberately parked at the artwork**, not closed. Do not re-raise it from this section: it now travels with the candidate, as `Emote.review`, and renders on `scripts/emote-review.py`'s page where the ruling gets made. ⚠️ Treat the movement figure as corroboration of the eye and never as the verdict — `emote-verify.py`'s own calibration measured whole-frame delta **not** to track legibility (two candidates a reviewer rejected scored higher than two he accepted).

### 13 · Work that is finished is still not live until it has been proven — BORDERLINE
**Plain:** code that is published still does not reach the running system until a separate check has proved it green.
**Evidence:** `scripts/postland-verify.sh` (1,270 lines) — every 5 min, tree-keyed green stamp, full corpus in a *fresh disposable worktree* (never in `$REPO`, whose working tree **is** the live `~/.claude` — 176 symlinks), retry ladder 2-of-3, `git bisect run` + auto-revert; `scripts/deploy-live.sh` advances *only* to a green-stamped tree, `--auto` on a 600 s tick, fail-closed; `bin/cc-blockers` carries `deploy-lag` / `never-green` / `verifier-inert` alarms.
**Why emblematic:** README §5's strongest claim, and the current blocking item in the repo's own worklist (`ea13e9c0`, `fa8f15a8`).
**Visual grammar:** an object arrives at the horizon and stops on the far side of the ground rule; a slow band passes over it; only then does it cross into the foreground.
**No-link:** **BORDERLINE.** With a stationary object and a passing band it survives. The moment it becomes "object moves along a path through stations", it is a pipeline diagram — the same failure class as R1. High supervision cost for a beat most viewers will read as "a thing moved".

### 14 · A guard that stopped watching raises an alarm about itself — NEAR-UNBUILDABLE
**Plain:** if one of the system's own checks quietly stops doing anything, that silence is itself detected and reported.
**Evidence:** `bin/cc-digest` Inert-check — *"a hook that abstained on ALL of its recent evals (≥N within the last H hours) AND fired NONE of them is INERT"*; `bin/cc-fleet` states `NEVER-RAN|FAILING|STALLED`; `bin/cc-blockers` `never-green` — *"the board was SILENT through 53 commits of halted deploy"*; `scripts/qos-census.sh` `verdict=SIGNAL-DEAD`.
**Why emblematic:** the single most distinctive thing in this repo. Nobody's dotfiles detect their own inertness.
**Why undepictable at header scale:** the payload is *a beat that did not happen*. At a 1.7 % duty cycle in a peripheral banner, an absent pulse is indistinguishable from an unnoticed pulse. Included because it may be worth one cheap experiment; do not budget for it.

---

## Emblematic but UNDEPICTABLE — and why

| Behaviour | Evidence | Why it cannot be a beat |
|---|---|---|
| Delivered ≠ read | `bin/cc-notify` `.seen` vs `.acked`; *"a claim that a session was told must cite acked≥line, never the send"* | The whole content is a distinction between two invisible internal states. Any drawing collapses them. |
| Verified by CONTENT, not by count | `scripts/land-verify.sh`; the 2026-07-11 incident — a 5-file commit silently dropped while `rev-list` read 0 | The failure and the success **look identical**. A picture that distinguishes them has to show the check, not the outcome. |
| Three-state verdicts | `scripts/qos-census.sh` `NO-BURST/PASS/FAIL/SIGNAL-DEAD`; `postland-verify.sh` `HUNG` vs `CUT`; memory *gate-never-ran ≠ gate-red* | A third state is definitionally the *absence* of a distinguishable appearance. Drawing it as a third colour asserts the opposite of the idea. |
| Atomic version swap | `bin/claude-latest`; README:382-387 — `ln -sfn` is two syscalls with an ENOENT window; the fix is `rename(2)` | Its entire content is that **no intermediate state is ever observable.** Undepictable by construction. |
| The deployment topology | `install.sh` (symlink primary, copy the four account dirs, copy globals), README §5 diagram | A graph of directories. Fails the no-link constraint by definition. |
| 41 deny rules · 350 allow rules · 2,358 bats tests · 5,709 sessions | README badges; `settings-templates/`; `tests/` (164 `.bats` files on disk) | Quantities. The only depiction is a number on screen, which restraint rule 4 forbids. |
| Page damping | `deploy-live.sh` `CC_DEPLOY_DAMP_S` subject+state damping; `cc-reaper` composer-damping | "The alert that correctly did **not** fire again." Nothing happens, on purpose. |

---

## Blockers / uncertainties named

- **The v6 line is on `feat/banner-showoff`, not `main`.** `tools/banner/gen.py` and `assets/banner/v6*.svg` exist only at `cac9dde2`; `main` still carries the v2-era `scripts/banner-build.py`. Any build brief must name the branch or the worker will edit the wrong generator.
- **`docs/plans/README_HERO_BANNER.md` is byte-identical on both branches (501 lines) — v6 has no doc section.** The standing operator ask on record is still the v5 line: *"a from-the-ground-up 'Opus 5 design-quality show-off' pass… Beauty is the remaining work; the constraints are done."* No operator ruling on v6 exists on disk.
- **Warm-worktree "~3 s" is not provable in this repo.** `scripts/worktree-pool.sh` is absent here; `handoff-fire.sh` only calls it if `<repo>/scripts/worktree-pool.sh` exists (it lives in the app repo). Candidate 8/9's isolation framing is safe; a "warm pool" beat would be unciteable here.
- **Candidate 11 is the highest-value/highest-risk item** — most-worked scope (38 commits), and one drawing decision away from re-triggering R1.
- **Volatile numbers avoided.** `deploy-lag`/`0-green-stamp` state is live-machine truth (and `ea13e9c0` retracts a recommendation built on it) — candidate 13 is grounded in the *mechanism*, never in today's counts.