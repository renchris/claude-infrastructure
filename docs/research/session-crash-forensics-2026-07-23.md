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
