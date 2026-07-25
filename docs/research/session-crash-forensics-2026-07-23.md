# Session-crash forensics — the night the monitor manufactured its own crisis (2026-07-23)

**Scope (frozen):** investigate the most recent session crash (`04eb0a05`, itself the session
investigating today's abrupt-crash storm; the operator's screenshot = its crash notification), and
investigate claude-infrastructure for bugs/issues such as memory leaks — especially in the 2-way
communication and `/handoff` self-opening/closing session management — that cause unreliability
and unexpected crashes/closures.

**Method:** lead-side disk forensics (crash ledger → transcript tails → live process census), then
an 8-axis read-only research wave (2 adversarial slots) + 1 pending daemon-census axis, with the
highest-stakes axis (the version-regression confound) run as a full-population census, not a
sample. Builds on — and corrects — [`handoff-memory-review-2026-07-22.md`](handoff-memory-review-2026-07-22.md)
and composes with [`infra-reliability-audit-2026-07-22/synthesis.md`](infra-reliability-audit-2026-07-22/synthesis.md).

---

## TL;DR (answer-first)

1. **Tonight's 19 recorded crashes were 0 real crashes.** The ledger's rows decompose into:
   **16** = one research wave's subagents *finishing their briefs* (lead `5aef2d9d`'s
   reliability-audit fan-out; 14 delivered full reports, every one ran SessionEnd — a 16-for-16
   "Session ended" wall in sessions.log) · **1** = that wave's verifier finishing (`0bfdb182`) ·
   **1** = an orderly close of an unrelated personal session (`e181de17`) · **1** = `04eb0a05`
   **deliberately retiring itself** via sanctioned `handoff-fire.sh self-close --terminal` after
   landing its work. `mem_free` held 87–88 % throughout; jetsam zero; no OOM anywhere.

2. **The operator-alarming notification (Image #1, 00:51) was a false page:** `04eb0a05` completed
   100 % of its goal (landed `65d533b`, content-verified, reported to the desk) and self-closed;
   the stale watchdog classified the pane-kill as `CRASH abrupt-unknown` and played Basso.

3. **The "CC version regression" headline is ~92 % measurement artifact.** A full census of all
   8,489 transcripts shows 96/104 "mid-Bash crashes" end in a literal `handoff-fire`
   self-close/recycle command — the pane-kill interrupts the in-flight Bash, so the `tool_result`
   never lands, forging the exact crash signature the prior scan keyed on. Organic abnormal-end
   rates: **2.1.183 = 0.00 % (0/5,051** — the single "crash" behind its 0.02 % was itself a
   teardown**) · 2.1.207 = 0.24 % (4) · 2.1.215 = 0.24 % (3)** — flat across the "broken"
   versions, ~20× below the reported 4.76 %. The gradient that looked like a regression is the
   **self-close adoption curve** (1 teardown-tail in the whole 183 era → 47/day by Jul 19). A
   small residual elevation vs 183 is statistically real (Fisher p<0.01) but is an **upper bound**
   (the 7 organic cases include possible sleep/⌘W/subprocess deaths), and its mechanism stays
   unproven until stderr capture runs on the right track (see 4).

4. **The prior review's launcher attribution is inverted, and its forensic lever misses its
   target.** Live truth: stable `claude`/`cc` → **2.1.114** (safe; MANIFEST default-deny blocks
   auto-jump). Eval `claude-next*`/`claude-fable*` → `~/.claude-183/` which — despite its name —
   contains **2.1.215** (a deliberate, MANIFEST-recorded advance on 2026-07-20). And the new
   stderr capture lives in the `claude-latest` wrapper, which the eval track **bypasses**
   (`.zshrc:387`) — post-deploy it instruments only the track that wasn't producing abnormal ends.

5. **"Pin CC to 2.1.183" — the #1 pending operator decision — is no longer supported by the
   evidence.** The 4.76 % number it rests on is the artifact above. Recommendation: **do not
   re-pin**; deploy, fix the signal integrity, wire eval-track stderr, and re-decide from honest
   data if organic events recur (§ Operator decisions).

6. **The real systemic finding: crash-signal integrity.** One undeployed root fix + a prose-grep
   classifier + a `claude.exe`-only process count let the monitoring subsystem manufacture three
   generations of crisis: the a1–a15 wave's completions paged as 16 crashes → the operator spawned
   `04eb0a05` to investigate → its self-close paged as a crash → the operator spawned this
   investigation. **The monitor was the malfunction.** Fixes shipped this session (§ Fix wave).

7. **On the actual "memory leak" question:** the `/handoff` watchers are bounded and
   self-terminating (≤180 s / ≤600 s — no process or fd leak); the whole machine has exactly **2
   leaked processes** (an orphaned `tail -F` from Jul 19, an orphaned perl probe from Jul 13).
   The genuine leaks are **unowned state stores** (watchdog dir 2,170 entries; 9 unrotated logs
   94 MB @ +2 MB/day; `session-index.db` 45 MB no-vacuum; `refs/checkpoints` 1,853 @ +47/day;
   mailbox 75 boxes append-only) plus **message-loss race windows** in the team-inbox JSON-array
   appends and an **ack-on-surface** design gap in mailbox drain — all itemized with fixes below.

---

## Part 1 — Tonight, reconstructed (ledger ↔ transcripts ↔ sessions.log)

Timeline (UTC; local = UTC-7):

| window | ledger says | disk truth |
|---|---|---|
| 06:42:32–06:53:50 | 16 × CRASH abrupt-unknown, `n_claude` 7→0 | Lead `5aef2d9d` (next2, claude-infrastructure, 2.1.215, alive 06:12→08:07 — *never crashed*) ran the registered-state-family reliability wave: ~18 `deep-research` subagents (roster `a1-handoff-open` … `a15-locks`, `a14-hostile`, `a14b-invariants`, `v1-verify`). Workers finished one-by-one as separate processes; 14 full `end_turn` reports; **16 unpaired "Session ended" lines match 16-for-16** → SessionEnd fired for every exit; the deployed hook just doesn't reap the watchdog pidfile, so each orderly exit became a CRASH row 14–40 s later. Two work-level anomalies (not crashes): `02b1add7` (a4-notify) exited orderly mid-research with **no report** right after a failed `ToolSearch select:SendMessage`; `6638f300` (a14-hostile) hit a Fable-5 refusal and idled to teardown. |
| 07:04:07 | 1 × CRASH (`0bfdb182`) | The wave's verifier `v1-verify` finishing cleanly (`end_turn`, explicit OASIS stop; "Session ended" 8 s before the row). |
| 07:50:07 | 1 × CRASH (`e181de17`) | Unrelated personal-project session; orderly close ("Session ended" 07:49:43) ~4 min after its last answer. ⌘W or idle exit — either way not a crash. |
| 07:51:13 | 1 × CRASH (`04eb0a05`) | The crash-investigation session **self-closing on purpose** after landing `65d533b` to origin/main (content-verified, 0 stranded) and reporting to the desk. Final Bash: `handoff-fire.sh self-close --terminal`. |

The self-close false-CRASH is a 3-fault chain (2 faults still live until deploy):
(1) `self-close`/`--recycle` type `/exit` into their **own** pane → the in-flight Bash tool is
interrupted and its process group SIGKILLed → the `tool_result` never lands → transcript ends
mid-Bash (`handoff-fire.sh:1135-37` says exactly this; confirmed at `:1154-57`, `:2001`);
(2) `classify_death` greps the tail for **prose** (`lead-crash-watchdog.sh:69`) and the real
disposition text ("retiring my own pane", "Self-retiring now") matches nothing — the classifier
missed the very session that wrote it; (3) the SessionEnd pidfile reap (`b026894`) is landed but
**not deployed** (live `session-end.sh` has zero reap lines).

## Part 2 — The teardown confound, quantified (full census, 8,489 transcripts)

| version | transcripts | abnormal ends | teardown-tail | organic | organic rate | (previously reported) |
|---|---|---|---|---|---|---|
| 2.1.183 | 5,051 | 1 | 1 | **0** | **0.00 %** | 0.02 % |
| 2.1.207 | 1,684 | 81 | 77 | **4** | **0.24 %** | 4.76 % |
| 2.1.215 | 1,269 | 22 | 18 | **3** (+1 = a live session scanned mid-flight) | **0.24 %** | 1.56 % |

- Every teardown-tail matched the **literal `handoff-fire` token** (zero loose-regex matches);
  all 7 organic cases individually verified as genuine mid-work dead-ends (ffmpeg, git rebase,
  ruff, shellcheck…). Teardown adoption: 1 event in the entire 183 era → 47 (Jul 19) and 25
  (Jul 20) per day.
- Residual 183→207/215 elevation: Fisher p = 0.0039 / 0.0081 — real but tiny (~1 in 420
  sessions), **an upper bound on binary crashes** (subprocess/⌘W/sleep can produce the same
  dangling end), and **flat between 2.1.207 and 2.1.215**.
- Second false-positive class for any future scan: **live sessions scanned mid-flight** (exclude
  recent-mtime transcripts whose `tool_result` later arrives).
- The operator's lived symptom (TUI → error text → **bare shell, tab survives**) can only be an
  organic process death — a pane-close takes the pane with it. Real crashes exist as a class;
  they are just ~20× rarer than the prior scan concluded, and tonight contained zero.

## Part 3 — Launcher / deploy truth (corrects handoff-memory-review §"Open decisions" #1)

| surface | resolves to | version today | exposure |
|---|---|---|---|
| `claude`, `cc`, `claude-x/h`, `claude2/3/4` | shell fn → `claude-latest` wrapper → `~/.claude-versions/current` | **2.1.114** | safe; MANIFEST marks 2.1.215 `skip` (default-deny); `DISABLE_AUTOUPDATER=1` |
| `claude-latest` (direct) | `~/bin/claude-latest` (real copy, **stale Apr 17**) | 2.1.114 | gets stderr capture only after `install.sh` |
| `claude-next*`, `claude-fable*` (all 4 accounts) | `.zshrc:387` → `~/.claude-183/node_modules/.bin/claude` **bypassing the wrapper** | **2.1.215** (deliberate advance 2026-07-20, MANIFEST-recorded) | **no stderr capture even after deploy** — the instrumented wrapper is not in this path |

Two consequences: (a) the prior doc's "interactive `claude` auto-updates to broken 2.1.215;
claude-next* pin safe 183" is **inverted** on both halves; (b) `concurrent_claude`
(`lead-crash-watchdog.sh:145`) greps `[c]laude\.exe` and counts **zero** of the
`node_modules/.bin/claude` processes — tonight's ledger showed `n_claude=0` while 8 sessions ran.

Deploy state: checkout (= live `~/.claude` symlink layer) is **11 commits behind origin/main**
(`ef7f7a4..fe52c1f`), cleanly FF-able; every changed hook/script/bin in the range is an
already-existing symlink (goes live on ff) except `bin/claude-latest` (real copy → `install.sh`);
no new-file-unlinked gap in this batch (all `A` files are docs/tests). The infra-audit's separate
finding of **39 tracked files unlinked live** (its root cause 1) predates this range and stands.

## Part 4 — Defect ledger (new findings this session; CONFIRMED unless noted)

| # | defect | where | fix status |
|---|---|---|---|
| 1 | Self-close/recycle forge the mid-Bash crash signature; no deterministic teardown evidence exists | `handoff-fire.sh:1154-57, :2001`; `lead-crash-watchdog.sh:51-76` | **fix wave T1+T2** — teardown marker contract (`~/.claude/watchdog/teardown/<sid|pane>.json` written before `/exit`; classifier reads it after jetsam, before prose) |
| 2 | `classify_death` prose-list misses real dispositions (missed `04eb0a05`) | `lead-crash-watchdog.sh:69` | subsumed by #1 (marker outranks prose) |
| 3 | `concurrent_claude` counts only `claude.exe` — all eval-track sessions invisible | `lead-crash-watchdog.sh:145` | **fix wave T2** |
| 4 | Watchdog and team-orphan-reaper do unlocked JSON-array RMW on the same crashed-lead inbox → last-`mv`-wins loses a shutdown/deny envelope exactly at recovery time | `lead-crash-watchdog.sh:272-279`; `team-orphan-reaper.sh:97-106` | **fix wave T2+T3** — shared `"$inbox.lock.d"` mkdir mutex |
| 5 | Ack-on-surface: drain acks mail before the model consumes it; mid-turn death = silent loss the guard cannot see | `mailbox-drain.sh:46,75`; promote fn unused at `mailbox-pending.sh:138` | **fix wave T3** — seen-at-drain, acked-at-Stop-fold (dup-biased) |
| 6 | Handoff telemetry `engaged` is a constant 1 (failed engagements never recorded); `firing_rss_kb` reads a pane-keyed pidfile that is sid-keyed → always 0 | `handoff-fire.sh:2118, 2131-33, 2104, 1596` | **fix wave T1** |
| 7 | Pid-identity gap in the daemon (`kill -0` only): no ACTIVE zombie right now (direct census: 18/18 live pidfiles = real live sessions; 81 dead-pid files, 0 reused-by-other), but the hazard is quantified — the OS reused single pids up to **5×** across historical pidfiles, and registration is spawn-unguarded (3,274 spawns / 3,110 sids; 164 sids >1×, max 27×). Also: the watchdog arms **ephemeral subagents** (73 % of today's registrations — each wave mints N daemons + 3 files/sid), and `handle_crash` reaps `.pid`/`.id` but leaks `.count` (L177/191) | `lead-crash-watchdog.sh:113-123, :271` | backlog → registered-state-family campaign (identity = pid+lstart; per-sid spawn guard; skip arming for agent sessions; count-reap on crash path) |
| 8 | Eval track has no stderr capture (wrapper bypassed) — the one artifact that can name a real crash mechanism misses the active track | `.zshrc:387` vs `bin/claude-latest` | operator step (§ decisions) — dotfile edit or wrapper re-route |
| 9 | idl.jsonl hash-seal chain broken by rotation (chain 6,910 > log 1,304 lines; `cc-idl seal/verify` have zero callers — feature operationally dead) | `rotate-autonomy-logs.sh` vs `cc-idl` | decision: wire a rotation-epoch re-seal or retire the chain |
| 10 | Unowned growth stores: watchdog dir 2,170 entries (GC only for archived team leads); 9 unrotated `~/.claude/logs/*.log` 94 MB @ +2 MB/day; `session-index.db` 45 MB no VACUUM; `refs/checkpoints` 1,853 @ +47/day; mailbox 75 append-only boxes; alarm/page/sweep/push stores | wF census | backlog (sweep + retention owners); rotation-broaden is the prior doc's decision #3 |
| 11 | 2 leaked processes machine-wide: `tail -n0 -F …ship-land.log` (Jul 19), `perl probe.pl` (Jul 13) | wF | trivial kill + add to reaper scope |
| 12 | Crash scans must exclude in-flight sessions (1 live session counted as a dangling end) | scan methodology | recorded here for future scans |

**Verified healthy (do not spend fix effort):** handoff watchers bounded + self-terminating
(`__selfclose` ≤180 s at :672, `__recycle` ≤600 s at :710, `setsid` detach at :285); mailbox
cursor lib sound (O_APPEND single-line writes; mkdir-mutex with stale-break; dup-biased by
design); idl rotation wired and running (00:35, create-mode); `/tmp` handoff litter bounded ~7 d;
projects JSONL native-bounded (~30–35 d); watchdog daemon *count* ≈ 1/live-session (the leak is
state files, not processes); `archives/claude-code` 971 MB is intentional frozen-version storage.

## Part 5 — Relationship to the prior documents

- **`session-crash-diagnosis-2026-07-22.md`** (per-session bloat → OOM): already superseded; this
  review re-confirms jetsam-zero and adds that transcript size never predicted anything.
- **`handoff-memory-review-2026-07-22.md`**: its root fixes, telemetry, and accumulation findings
  **stand** (deploy them); its Part 5 version-regression rates are **~92 % teardown artifact**
  (Part 2 above); its launcher attribution ("Open decisions" #1) is **inverted** (Part 3); its
  Part 4 claim A4 ("self-close → SessionEnd → pidfile removed cleanly") is refuted by its own
  Part 3 and by `04eb0a05` — Part 3's version is correct.
- **`infra-reliability-audit-2026-07-22/`** (~90 defects, 4 root causes): fully composes with
  this review; its supersession note (which imported the version-regression story mid-audit)
  should now read: *the crash class is rarer than believed and mostly signal-integrity noise;
  the audit's own root causes 1 (last-mile activation gap) and 4 (unguarded hot paths) are the
  operative reliability problems.* Its size-recycle demotion stands.
- The irony for the record: the a1–a15 wave (that audit's own data collection) generated the 16
  false crash pages; the session that landed the false-crash *fix* generated the 17th on its way
  out; each alarm spawned the next investigation. Crash-signal integrity is not cosmetic — it
  steers operator attention and multi-session compute.

## Phase 0 — fix-wave orchestration (team `crash-signal-integrity`, spawned this session)

| teammate | worktree / branch | scope | depends on |
|---|---|---|---|
| tm-fire | `/tmp/wt-fix-fire` · `fix/teardown-marker-fire` | `handoff-fire.sh`: teardown markers (self-close + recycle) + telemetry `engaged=0` + rss key | marker contract v1 (shared) |
| tm-watchdog | `/tmp/wt-fix-watchdog` · `fix/watchdog-classify-marker` | `lead-crash-watchdog.sh`: marker branch in `classify_death` + marker GC + `concurrent_claude` fix + inbox mutex | marker contract v1; lock-dir name shared with tm-mail |
| tm-mail | `/tmp/wt-fix-mail` · `fix/mail-ack-consume` | `mailbox-drain.sh` ack-on-consume + `session-continue.sh` Stop-fold verify + `team-orphan-reaper.sh` mutex | lock-dir name shared with tm-watchdog |

Merge order: smallest-diff first, rebase-onto-origin/main + gate per branch, land via the
project-local `/ship` flow (standing-land). Contracts: marker =
`~/.claude/watchdog/teardown/<KEY>.json` (KEY = `$SESSION_ID` else pane uuid; single-line JSON
`{key_kind,pane,sid,mode,ts}`; written before `/exit`; read fresh-≤30 min; GC'd only inside the
watchdog's pid-match-guarded cleanup); lock dir = literal `"$inbox.lock.d"` in both writers.

## Operator decisions & exact commands (silver-platter)

```bash
# STEP 1 — deploy all landed commits (symlinked hooks/scripts/bin go live instantly)
cd ~/Development/claude-infrastructure && git fetch origin && git merge --ff-only origin/main

# STEP 2 — activate the stale real-copy (stderr capture for the stable launcher) + wire staged hooks
~/Development/claude-infrastructure/install.sh --wire-hooks

# STEP 3 — cycle the supervisor so pre-fix in-memory code reloads (backlog 7f9a3d014b10's third step)
launchctl kickstart -k gui/$(id -u)/com.claude.lead-supervisor
```

(These are the same three steps the blocked backlog item `7f9a3d014b10` "activation sweep" is
waiting on; note its "load log-rotation plist" clause is already satisfied — rotation is loaded
and ran 00:35 today. Landing this session's fix wave BEFORE running step 1 folds those fixes into
the same deploy.)

1. **Deploy (steps 1–2, do now).** Activates: SessionEnd pidfile reap (ends the dominant
   false-crash class — proven tonight by 16 orderly exits logged as crashes), the rm-race disarm
   guard ("125 cross-incarnation disarms" class), `/tmp` straggler GC, `claude_version` +
   `stderr_log` ledger fields, the crash-by-version histogram, per-handoff telemetry, and the
   worktree-safe deploy-parity assert.
2. **CC version pin — recommend NO re-pin.** The 4.76 % basis is ~92 % artifact; organic rates
   are 0.24 % and flat across 2.1.207/215; the `.claude-183` advance to 2.1.215 was deliberate.
   If you still want it: `npm install --prefix ~/.claude-183 @anthropic-ai/claude-code@2.1.183`.
   Re-decide only if organic events recur once the signal is honest.
3. **Wire stderr capture for the eval track** (the active one): either route the `claude-next`
   shell fn through the instrumented wrapper, or replicate the 12-line tee block from
   `bin/claude-latest` into the fn. One-line dotfile decision — operator-owned (`~/.zshrc:387`).
4. **idl seal chain:** wire a rotation-epoch re-seal or retire `cc-idl` sealing (zero callers
   today; any `verify` false-alarms tamper). Decision, not urgent.
5. **Log-rotation broaden + store retention** (prior doc's decision #3, still open): the 9
   unrotated logs and the wF store table are the remaining growth owners.

## Residual uncertainties

- The 7 organic abnormal ends are an upper bound: binary crash vs ⌘W-mid-Bash vs subprocess kill
  vs sleep is not distinguishable from transcripts; eval-track stderr capture (decision 3) is the
  discriminator for the next event.
- Whether CC runs SessionEnd on an interrupt-`/exit` after a self-close remains inferred
  (THEORETICAL) — the teardown marker makes the question moot for classification.
- The daemon-census axis (wB) landed post-draft and is integrated in defect #7: today's daemon
  population is healthy (every daemon joins to a live session; the "8-day orphan" suspected
  earlier is a genuinely-live 8-day lead session), so the pid-reuse/zombie class is a
  frequency-backed *hazard*, not a present incident.
- The desk memory `session-crash-per-session-bloat` requires its second correction (this doc is
  the source of truth); done alongside this landing.

---

## 2026-07-24 addendum — "resolved yesterday" was only half the story: the reaper reaps live operator conversations

Yesterday's verdict ("the crashes were 0 real — teardown artifacts, sanctioned self-closes") fixed
the SIGNAL: closures are now correctly attributed. What it did not fix is that one class of those
"sanctioned" closures was **not sanctioned by the operator**: `com.chrisren.cc-reaper` (launchd,
every 300 s) tore down two sessions the operator was actively conversing with:

| session | operator's last prompt | reaped | cause | idle at reap |
|---|---|---|---|---|
| Danny-Studio-60 (wt-pool-1-4EC4DA5D, drafting a message to Danny re Studio 60 nightclub) | 17:58:41Z ("Provide final message to Danny"; draft delivered 17:59) | 18:13:15Z | finished-teammate | 817 s |
| Opus-5-upgrade (claude-infrastructure-D6BE7CE7, "do we need to upgrade Claude Code?" answered 18:28) | ~18:27 | 18:40:22Z | finished | 675 s |

(The third teardown today — CC91E257, coordination-abandoned, idle 26 h — was legitimate.) <!-- pane-id-lint:allow -->

**Root cause (structural, not a bug in any one gate):** every gate held exactly as designed.
`cc-classify`'s notion of idle is *seconds since the last assistant turn*, and its "done" evidence
is *clean tree + content on trunk*. Between operator prompts an interactive conversation satisfies
all of it — a Q&A session that writes nothing is ALWAYS clean & 0 ahead — and `wt-pool-1`'s cwd
alone branded it a teammate (`*/.worktrees/*` ⇒ finished-teammate, no fired-peer stamp required).
The classifier read WHEN the last turn happened, never WHO drove it. The reaper's 600 s settle
window then made any >10-min coffee break fatal.

**Fix (landed as `fix(session-reaper)`, this branch):**
1. *Operator-interaction hold* (cc-classify step 4.7): a REAL operator-typed prompt (isMeta/auto-
   traffic/tool_result excluded — semantics mirror `ce_last_interactive_age`) within
   `CC_CLASSIFY_INTERACTIVE_HOLD_S` (default 21600 s = 6 h) ⇒ `owned-wait`, never-reap. For a
   spawner-stamped fired worker only prompts AFTER `firedAt`+300 s count (the fire brief itself
   arrives as a user prompt via it2 keystrokes and must not hold worker GC). Placed after
   handed-off-lead so a fired self-handoff with a live successor still reaps its dead pane.
2. *Stamp gate* (cc-classify): `finished`/`finished-teammate` now require the spawner's
   `cc-fired/<pane>.json` stamp. An unstamped "done" pane is the new **`finished-operator`** —
   surfaced to the desk for confirm-close, never auto-reaped (extends T-P3-4's own principle:
   "an operator/role session carries no marker and is NEVER promoted" — previously applied only
   to the finished-shared-review promotion, now to all done-causes).
3. *Reaper belt* (cc-reaper): independently refuses finished/finished-teammate reaps without the
   stamp (guards against a stale/foreign classifier); `finished-operator` joins SURFACE_PAGE_RE.

**Known accepted tradeoffs:** a desk-nudged stamped worker (cc-notify arrives as a real user
prompt) now lingers up to the 6 h hold after its last nudge instead of 10 min — lingering panes
are strictly cheaper than killed operator conversations; tune via `CC_CLASSIFY_INTERACTIVE_HOLD_S`.
Unstamped genuinely-finished workers (spawn paths that bypass handoff-fire) surface for
confirm-close rather than auto-GC. `coordination-abandoned` keeps its own multi-legged basis
(dead partner + 2 h horizon + live co-cwd owner + landed) and is not stamp-gated.

**Ops note:** the fix was applied to the live shared checkout's working tree at ~18:55Z (the live
`~/.claude/bin/cc-{classify,reaper}` are per-file symlinks into it), so the daemon has run the
safe code since then; the landing makes it durable. RED-proof: 36/36 cc-classify.bats +
54/54 cc-reaper.bats.

## 2026-07-25 addendum — hardening the CLASS: it was never just the reaper

The 2026-07-24 fix (`c063ca0`) closed the reaper *instance*. This pass closes the **class**:
"a session closed itself for no reason." Branch `fix/shutdown-hardening`, based on `origin/main`
at `0098a41`. Every change below either narrows what can be closed or leaves it unchanged; every
new guard fails CLOSED on ambiguity; each landed with a `.bats` test seen RED before and green
after.

### Why the 2026-07-23 pass did not cover it — the durable lesson

The 2026-07-23 pass landed ~20 commits between 00:00 and 03:00 PDT, and **every one of them was
crash-signal INTEGRITY, not closure PREVENTION**: `lead-crash-watchdog` teardown-marker
classification (`4d0c85a`, `75283a7`, `7c67321`, `f63e712`); `handoff-fire` teardown markers for
self-close/recycle (`97db72a`, `8ec9bb7`); `session-end` GC (`b2e8e1f`, `b026894`); `afdca00`
concluding "tonight's 19 crashes were 0; the version regression is ~92% teardown artifact." Every
change made the *measurement* more honest and **not one of them could prevent a session from being
closed.** Worse, by teaching the watchdog to file marker-carrying teardowns as deliberate/benign,
that pass made the reaper's own closures *more* invisible: a reaper close IS a deliberate teardown,
so it filed as expected behavior and vanished from the crash signal. The pass answered "were there
crashes?" (correctly: no) while the operator's symptom was "sessions keep closing" (correctly: yes —
deliberately, by the reaper). **The lesson: a false-DONE is not a crash. "Is the crash signal
honest?" and "can anything close a live conversation?" are orthogonal questions; a session-lifecycle
audit must ask the second, over the whole set of closers, not just the one that paged.**

### The three residual gaps (brief-scoped) — closed

**Gap 1 — the blind-spot self-check mis-counts (`936b857`).** The brief's premise (a live pane not
registering, Δ+1) did **not** reproduce on disk (2026-07-24 ~15:2x PDT): `cc-reconcile --dry-run`
accounted for all 18 live panes (17 present + 1 healed, **0 backfilled**) — no unregistered pane
existed. The real defect was the opposite and durable: `cc-reaper`'s `live_pane_count` and
`cc-reconcile`'s `live_claude_pids` (the self-check's *independent* truth signal) matched only
`claude`/`*/claude`/`cli.js` as an interactive argv0, **silently dropping every `claude.exe`** — the
eval-track (`.claude-183`, claude-next) install's own binary (`…/@anthropic-ai/claude-code/bin/claude.exe`).
Ground truth: **18 `claude` + 6 `claude.exe`** live procs, but `live_pane_count` reported 18.
`session-register.sh:63` *does* register `claude.exe` (`claude|claude.exe|claude-*`), so those panes
were enumerated but the self-check under-counted them — biasing the `live−enum` delta in BOTH
directions (a false-negative here that desensitizes the blind-spot detector; a false-positive Δ at a
different session mix, which is what the brief observed). Fix: align both argv scans to the register's
process-identity definition. Touches **no reap path** (self-check + reconcile only page/backfill).
*Method note: the brief's Gap-1 hypothesis was a moment-in-time symptom; disk truth reclassified it.*

**Gap 2 — independent second legs for `coordination-abandoned` + `handed-off-lead` (`7c286ea`).**
The `cc-reaper` stamp belt gated only `finished`/`finished-teammate`. `coordination-abandoned` rested
on cc-classify's decision alone — and specifically on the §4.7 operator hold being *ordered before*
the `coordination-abandoned` branch (returns at `cc-classify:404`, before `:440`): load-bearing and
undefended. `handed-off-lead` rested on the classifier's live-successor finding with no act-time
re-verify. Each now gets its own leg: `coordination-abandoned` → the reaper re-reads operator adoption
via `ce_last_interactive_age` (a *separate* implementation from cc-classify's inlined copy, so the two
legs can't share a bug), fail-closed on an unresolvable transcript; `handed-off-lead` → the reaper
re-verifies the named successor is *still a live row* in the same classify set at act time. Plus a
classifier branch-order guard test that fails if §4.7 is moved after (or its early-return removed
from) the `coordination-abandoned` branch (RED-proven by neutering it). Both legs strictly narrow.

**Gap 3 — suspend-guard: never reap on a sweep that spans machine sleep (`454a711`).** `pmset -g log`
confirmed the machine sleeps every ~15-17 min on battery (Sleep Service / Maintenance / Clamshell);
`cc-reaper.log` shows a single sweep spanning **19:37→22:03Z (2h26m)** across a suspend and a 15.5 h
overnight gap. Across a suspend the classify idle values are untrustworthy (a session idle 9 min
pre-sleep reads idle 3 h post-wake) AND the settle window bought zero real self-close running-time —
so a session can be reaped on the first post-wake sweep before the operator (lid just opened) can
touch it. The guard detects an inter-sweep gap (persisted sweep-end heartbeat) OR an intra-sweep span
exceeding `CC_REAPER_SUSPEND_S` (900 s, ≫ the ~4 min normal sweep) and reaps nothing that sweep —
surface/defer only; the next fresh sweep reaps normally. RED-proven with a file-seamed clock (a
durable value, not an mtime; the classify mock advances it mid-sweep to simulate the intra case).

### The derivation — every closer, not just the reaper (frontier tier)

The mission's core: `cc-reaper` was one closure mechanism; **enumerate every code path that can
terminate a session and prove operator-adoption protection for each.** Escalated to Fable 5 via
`/frontier-run` (2 baseline-blind `frontier-derivation` panelists, ~$5-12; fed the mechanism list +
the "reads WHEN never WHO" failure shape). **Both panels independently converged** — convergence =
high confidence. Every finding below was re-verified against disk by the lead (not relayed):

| Closer | Predicate | Operator-conversation verdict | Disposition |
|---|---|---|---|
| **`hooks/teammate-auto-shutdown.sh` (TeammateIdle)** | clean tree + no busy-marker + reap-guard pass; then modal-suppressed `it2 close -f` + `worktree remove --force` | **VULNERABLE — both panels' #1.** 0 who-check tokens (vs cc-classify 16); reap-guard reads WHEN/WHAT, never WHO. Wired LIVE. | **FIXED `092e823`** |
| **`scripts/team-orphan-reaper.sh`** | `is_lead_alive` false (no watchdog pidfile ⇒ "assume dead") → `mv` whole team dir incl. live inboxes | **VULNERABLE — both panels' #3.** `leadSessionId` rebound by nothing; a recycle-in-place makes a LIVE team read dead. `:151` pane check "skip for v1". | **FIXED (sibling `24722de`)** |
| **`hooks/waiting-recycle.sh` Stage-2** | fill ≥ idle threshold; S6 conversation hold = **900 s SOFT** (vs reaper 21600 s) + blind past a 2 MB transcript tail | **VULNERABLE — both panels' #2.** Armed live for 22 desk cwds; `/exit`-recycles the operator's own desk mid-compose. | **CAMPAIGN** (see below) |
| **cc-classify §4.7 + the new Gap-2 leg + reap-guard R-d — R1** | operator-adoption read from `tail -c 2000000` | **RESIDUAL (panel R1).** >2 MB of records after the operator's prompt evicts it ⇒ hold silently absent ⇒ a stamped adopted worker reaps. | **CAMPAIGN** |
| **`bin/cc-teardown` (the final actuator)** | G-b done-evidence = any non-empty caller string (selftest passes literal `"x"`) | **VULNERABLE-BY-CALLER (negative space).** The only who-check in the whole stack is cc-classify §4.7; nothing forces a fresh machine verdict at the kill. | **CAMPAIGN** |
| `bin/cc-reconcile` prune · `scripts/lead-supervisor.sh` · `hooks/lead-crash-watchdog.sh` (pid death) · `hooks/session-end.sh` · `hooks/boundary-handoff.sh` · `scripts/lead-deathwatch.sh` · `scripts/boot-resume.sh` | fail-closed prune / page-only / real pid death / dead-pid GC / advisory-only / kqueue NOTE_EXIT / pre-boot ghosts | **PROTECTED** (both panels; several refuted their own predictions here) | — |

Falsifiable probes the lead ran to confirm (not relay): `grep -c` who-tokens on
teammate-auto-shutdown.sh + reap-guard.sh = **0/0** (baseline cc-classify = 16); `waiting-recycle.sh`
`CONV_HOLD_S=900` + `hold soft`; `cc-classify:56` + `context-econ.sh:110` `tail -c 2000000`;
`team-orphan-reaper.sh:38` "no record — assume dead" + `:151` "skip for v1".

### Derivation fixes landed

**Fix #1 (the CRITICAL one) — operator-adoption hold R-d on the TeammateIdle path (`092e823`).**
The incident class *verbatim* on a hook the c063ca0 fix never touched. Added guard **R-d** to
`scripts/reap-guard.sh` (the pluggable reap-decision module — extends its gate without editing the
hook's close logic, the repo's own C10 pattern), reading operator interaction via
`ce_last_interactive_age`. A real operator prompt AFTER the spawn brief (excluded via
`spawn+BRIEF_SLACK`) and within the interactive hold ⇒ DEFER. Fail-closed on an unresolvable
transcript. Engages only when the hook passes the teammate's `--session-id` (now wired at
`teammate-auto-shutdown.sh:359`, pinned by a wiring test). RED-proof: `tests/reap-guard.bats`
(adopted→DEFER, brief-only→REAP, unresolvable→fail-closed, no-sid→back-compat) + 2 inline `--selftest`
checks (6→8). **This is the single highest-value change in the pass** — it was the unguarded twin of
the reaper the whole investigation started from.

**Fix #3 — orphan-reaper live-team protection (CONVERGENCE — landed as sibling `24722de`).** A
*second* session independently reached the same finding and landed the more-thorough fix on
origin/main first: three-state liveness where a **missing/empty watchdog pidfile is UNKNOWN, not
"assume dead"** (surfaced + operator-paged, never archived — the common recycle-in-place shape), plus
a cc-sessions **registry cross-check** (a live session whose cwd sits inside a member worktree OR whose
name matches a member/lead ⇒ KEEP) and malformed-config/degradation tolerance. This branch's own
`a8b9fb8` (a `team_has_live_member` **process** witness — an `--agent-name` process for a member ⇒
KEEP) was **dropped at rebase** as redundant and *slightly less safe* (it still archived the
no-pidfile case that `24722de` correctly surfaces). Two sessions converging on "a dead lead pid is not
a dead team" is strong confirmation. **Narrow residual/follow-up:** `24722de`'s registry cross-check
misses a live-but-**unregistered** teammate process (registration-timing gap) under a dead-lead
*pidfile*; adding the dropped process-liveness witness as an additional OR-signal to `24722de` closes
that last edge — filed as a small follow-up, not a mid-rebase merge of two safety-critical fixes.

### Residuals → frontier campaign candidate (recorded in `FRONTIER_HOLES.md`)

Both panels converged on ONE elegant fix for the remaining three (waiting-recycle S6, R1 tail-eviction,
cc-teardown caller-trust): **a single "who-drove-the-last-turn" / session-ownership oracle** that every
actuator MUST consult pre-disruption — adoption-hold + fired-stamp + a sticky adoption marker (so
eviction past the 2 MB tail can't lose it) + composer-unknowable ⇒ hold. It dissolves R1 (sticky
marker replaces the tail read), #2 (the 900 s-vs-21600 s window collapses to one constant), and the
caller-trust gap (a machine verdict ≤N-min old required at the kill), and every FUTURE closer inherits
it. Deliberately NOT point-fixed here: naively hardening waiting-recycle's empty-tail case would
*deadlock the desk's own self-recycle* (its reason to exist), and a rushed multi-file tail-fallback in
just-shipped safety code is the exact risk these constraints guard against. **R1 is a known residual in
the guards shipped this pass** (§4.7, the Gap-2 leg, and reap-guard R-d all read the 2 MB-bounded
signal) — surfaced here so it is not silently lost. Negative-space items also filed: the consent-free
`it2 close -f` transport (nobody owns "which closes deserve the modal back"), composer-draft
invisibility fleet-wide, and `leadSessionId` having no lifecycle owner.

### Ops note

All changed files (`bin/cc-{classify,reaper,reconcile}`, `scripts/reap-guard.sh`,
`scripts/team-orphan-reaper.sh`, `hooks/teammate-auto-shutdown.sh`) are existing per-file symlinks
into the shared checkout — landing on the trunk fast-forward deploys them; there is no new tracked
*runtime* file to link (the new `tests/*.bats` are not deployed). Post-land: verify the symlinks
resolve to the landed content and exercise the live path.

---

## 2026-07-25 addendum II — the ocean-boil: full closer audit, residual fixes, and the convergence

The operator escalated "sessions abruptly close by themselves" to a boil-the-ocean goal. An 8-axis
parallel audit (6 mechanism auditors + an adversarial verify of the `c063ca0` fix + a negative-space
sweep) established the following.

### Verdict on causes — the organic rate is zero

The negative-space sweep over 1,826 transcripts / 7 days / all 4 account roots found **TRUE-ORGANIC =
0**: zero CC-binary crashes (0 DiagnosticReports), zero OOM victims (JetsamEvents hit only non-CC
processes), zero quota-kills that closed a session, and 1 iTerm2 crash (undetectable in-band). Every
abnormal end was our own infrastructure: sanctioned teardown/recycle (83) or the reaper class.
"Sessions close by themselves" was **entirely first-party** — which is the good case, because
first-party closers are all fixable.

### Adversarial verify of `c063ca0` — 4 residual paths, all CONFIRMED, all now fixed

R1 stale pane-keyed stamp + the 2 MB interactive-tail asymmetry (re-opens the incident on heavy
transcripts) · R2 `handed-off-lead` bypasses the hold + stamp · R3 the 6 h expiry is by-design ·
R4 `env=0` silently disables the hold. Each was confirmed against code before being fixed — the
verify pass earned its keep by finding that the *published* fix was necessary but not sufficient.

### What landed (this wave)

| Unit | Commits | Fix |
|---|---|---|
| **U1** | `8705318` `2508319` `8cf3fec` | `hooks/lib/cc-interactive.sh` — THE shared who-drove-the-last-turn primitive (tail fast-path + whole-file fallback + image-only pastes); fired-stamp tenancy binding (`CC_FIRED_BOOT_MAX_S`, stale-tenancy stamps GC'd); hold evaluated BEFORE `handed-off-lead`; `handed-off-lead` successor requires a `firedBy`-linked stamp; hold floor (<60 s ⇒ default+warn). |
| **U2** | `f9f2ed0` `e2a1def` | `teammate-auto-shutdown`: fail-closed on an unresolved WORKTREE (defer→surface, never an ungated close) + operator-adoption hold via the lib. `cc-teardown`: adoption belt REFUSE rc=2 (+ `--force-adopted`, operator-CLI-only). |
| **U3** | `ca03d41` `e009799` | `handoff-fire` self-close: successor ENGAGEMENT gate (birth ≠ engagement), close-instant successor re-verify in `__selfclose` (dead successor ⇒ no close), pre-close inventory WARN. |
| **U4** | `24722de` `7791209` | `team-orphan-reaper`: three-state liveness (no pidfile = UNKNOWN-surface, never archive) + cc-sessions registry cross-check. `waiting-recycle`: recent-conversation extended grace (`CC_WR_CONV_RECENT_S` / `CC_WR_RECENT_GRACE_S`), bats-pollution GC + fixture isolation. |
| **U5** | `1937ed7` `6c9bd6e` `8b7bba7` `05aa8cf` | Close attribution: `bin/cc-close-attrib` exit-code+stderr wrapper (fail-open, kill-switch `CC_CLOSE_ATTRIB_DISABLED`); `lead-crash-watchdog` close-record join (clean-exit / killed-oom-or-force / binary-crash / error-exit); C10 activation `10-close-attrib-activate.sh` (PATH shim; **operator runs**). |
| **U6** | `f19e8bd` (+ sibling `e34ab65`) | Desk self-restore completion on top of `e34ab65`'s `--window`+`FIRE_ERR`: role-file heal from the cc-fired stamp on a successful replacement fire + `paged-*-stale` >7 d sweep. Ends the 41 h silent no-desk fire-failed loop for good. |
| **U7** | `83cf353` | `cc-teardown` teardown-markers: a DELEGATED close now drops the same contract-v1 marker `handoff-fire` got on 2026-07-23, so deliberate closes stop reading as CRASHes. |
| **U8** | `f8dc6b7` | `teammate-auto-shutdown` teardown-markers (`mode=teammate-idle`): the TeammateIdle closer was the last *unmarked* one. `lead-crash-watchdog` is a SessionStart hook with **no matcher** — it arms on every session, teammates included — so every idle-teammate close fell through the whole classify ladder to CRASH. |
| **U9** | `d8e36fa` | `lead-crash-watchdog`: a pane-keyed marker must **name** the session it absolves. An in-place `--recycle` leaves the predecessor's marker on a pane the registry now resolves to the *successor*, so a genuine successor crash inside the 30-min window was classified RECYCLE — a **silent** miss. Empty-sid markers stay honoured (the 2026-07-23 self-close shape). |

**U8/U9 — and the move that found them.** U1-U7 all came from the 8-axis audit's closer list. U8 and
U9 came from *refusing to trust that list*: a sweep of every pane-closing / process-killing call site
in `bin/ hooks/ scripts/` (twice, with two different pattern families), then walking the reader's
ladder against each writer. That surfaced the one live closer nobody had enumerated (TeammateIdle)
and the one case where the reader trusts a marker that was never about the session it is judging.

U9 is the more interesting of the two because it is the **mirror** of the bug this whole class is
about. Everything up to U8 fixed *false CRASHes* — noisy, self-announcing, and therefore eventually
noticed. U9 fixes a *false RECYCLE*: a real crash quietly absolved by someone else's teardown marker
and never surfaced at all. A detection system's dangerous failure is the silent one, so
"every close class is attributable" was not true until the reader stopped accepting evidence that was
never about the session in front of it.

**Generalisable:** an audit that enumerates *mechanisms* will miss an actuator — enumerate *call
sites*. And when you add a producer to a contract, re-check the **consumer's** logic against every
producer, not just the one you added.

**U7 detail** (the last leg of the *writer* side). `handoff-fire` was fixed on 2026-07-23 for the *self*-close
path; the *delegated* close — desk or reaper calling `cc-teardown`, which kills the target's process
and closes its pane — still looked exactly like a crash to the **target's own** watchdog. `cc-teardown`
now writes the dual-keyed marker (`<sid>.json` + `<pane>.json`, `mode=teardown`) that
`lead-crash-watchdog.sh` `classify_death` already reads. Placement is the load-bearing decision:
**after every gate, immediately before the first kill**. A REFUSE/DEFER leaves the target ALIVE, and a
pre-gate marker would mask a genuine crash of that live session for the reader's whole 30-minute
freshness window — so the invariant "no marker on a pane that survives" is itself RED-proven, not just
the happy path. The cross-file contract is asserted end-to-end: the bats drive the REAL `cc-teardown`
and then the REAL watchdog, sid-keyed and pane-keyed (registry reverse-lookup), so neither side can
drift into a green-but-wrong fixture.

### C-SC-1 status — the oracle exists now

The campaign's target ("one shared who-drove-the-last-turn oracle every actuator consults + a sticky
adoption marker") is **substantially BUILT**: the oracle nucleus is `hooks/lib/cc-interactive.sh`,
consumed by `cc-classify`, `teammate-auto-shutdown`, and the `cc-teardown` belt; the 2 MB-tail blinding
is closed by the whole-file fallback; `cc-teardown` caller-trust is closed by the belt; waiting-recycle
S6 got the extended-grace hold. **Remaining for the campaign:** migrate reap-guard R-d from
`ce_last_interactive_age` to the lib (they coexist today by design), a STICKY adoption marker surviving
transcript rotation, and unifying context-econ's `ce_` with `ci_`.

### Convergence note (process)

THREE independent streams fixed this class in one night: this goal session's wave; the
shutdown-harden crew (`fc633b5` / `6aeea93` / `a47bef7` / `893cd58`); the desk-respawn crew
(`e34ab65`). Reconciliation was by **COMPOSITION** — keep both behaviour sets, single-owner-per-file,
the pre-existing `--window` surface beat a proposed new flag, and duplicate holds coexist as
belt+suspenders. The landing lock serialized ~10 lands without a bad merge; its
full-suite-inside-the-lock cost (~17 min/land, queues >40 min) was fixed separately in-flight
(`190c839` gate-outside-the-lock + CAS push window; backlog `ee453a792903`). The generalized lesson is
recorded as the `parallel-stream-convergence-protocol` memory.

### Detection coverage now — the closer inventory

The completeness claim is only worth as much as the enumeration behind it, so here is the full list
of paths that can end a session, each with its attribution status (swept twice over `bin/ hooks/
scripts/` with two different pattern families; every other `kill`/`close` hit in the repo targets a
script's own helper or fixture pid, never a session):

| Closer | Marker | Status |
|---|---|---|
| `handoff-fire` self-close (`__selfclose`) | ✓ written by the parent for `SC_SID` before the first `/exit` | landed 2026-07-23 |
| `handoff-fire --recycle` | ✓ `mode=recycle` | landed 2026-07-23 |
| `handoff-fire` focus-restore failure | n/a — closes an UNTYPED child pane; nothing launched, no session, no watchdog | correct by construction |
| `cc-teardown` (desk + `cc-reaper` delegated close) | ✓ `mode=teardown` | **U7** |
| `teammate-auto-shutdown` (TeammateIdle) | ✓ `mode=teammate-idle` | **U8** |
| `session-register` `kill -9` | n/a — kills its own watchdog helper, never a session | correct by construction |
| `handoff-selfclose-e2e.sh`, `reaper-e2e.sh` | n/a — test-fixture cleanup | correct by construction |

With the writer side complete and the reader no longer accepting another session's marker (**U9**),
every close class is attributable: reaper closes (logged + gated), deliberate teardowns (markers on
**all three** closers), involuntary deaths (close-record exit-code join — **pending its C10
activation**, the one real gap left), orphan archives (surface-first). The next "a session closed by
itself" report has a named cause within one watchdog sweep, or it is iTerm/hardware.

### Ops note (addendum II)

`bin/cc-teardown`, `hooks/teammate-auto-shutdown.sh` and `hooks/lead-crash-watchdog.sh` are all
existing per-file symlinks into the shared checkout — the trunk fast-forward deploys them; no new
tracked runtime file needs linking (the `tests/*.bats` are not deployed). Landed ≠ deployed: the
shared checkout lags `origin/main` between ff-syncs, so confirm with
`git -C ~/Development/claude-infrastructure rev-list --count HEAD..origin/main` (expect 0) before
concluding a fix is live.

The operator-owned steps this wave leaves open are U5's `10-close-attrib-activate.sh` (C10) — until
it runs, the close-record rung of the ladder is inert and involuntary deaths stay unattributed — and
the ff-sync above whenever the checkout has drifted.
