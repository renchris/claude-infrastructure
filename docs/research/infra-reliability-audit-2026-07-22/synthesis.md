# Infra Reliability Audit — 2026-07-22

**Scope (frozen):** investigate claude-infrastructure for bugs/issues such as memory leaks — especially in the 2-way communication and /handoff self-opening/closing session management — that may cause unreliability and unexpected crashes/closures.

**Method:** 15-agent research wave (14 component axes + 1 blind invariants slot) gated by a decomposition critic, deduped against the known-issue register (raw/a12.md, commit-verified), spot-verified by an independent verification agent (raw/ = full per-axis reports). Base: checkout == origin/main @ `ef7f7a4`. All probing read-only. The Fable adversarial slot was safety-flagged mid-run (raw/a14.md); its replacement ran on Opus (raw/a14b.md) and the frontier-tier adversarial pass was performed at lead level instead.

**Verdict in one line:** the wave found ~90 defects clustering into four systemic root causes — the largest (last-mile activation/deploy gap) silently disarms even fixes that already landed — while the operator-felt crash class was re-diagnosed MID-AUDIT by a sibling session as a CC binary regression (supersession note below), demoting this audit's size-recycle lever from crash-fix to defense-in-depth.

**Supersession note (2026-07-23, post-verification):** a sibling session's root-cause review (memory `session-crash-per-session-bloat` — corrected entry; doc `docs/research/handoff-memory-review-2026-07-22.md`, branch-side at write time) attributes "crash to shell" to a **CC 2.1.207 version regression** (crash rate by version 0.02%→4.76%→4.76%→1.56%; 100/100 crashes mid-Bash; median crashed transcript 1.27MB; jetsam-zero) — superseding the giant-transcript OOM theory (K01/K02) this audit inherited from the 07-22 diagnosis. Our verifier's #10 refutation (zero >60MB transcripts live while crashes had continued) independently corroborates the supersession. Primary crash lever = **pin CC to 2.1.183**. Consequences here: roadmap item 2 (size-triggered recycle) demotes to bounded-state defense-in-depth (invariant I5 — unbounded transcripts remain a real leak class); the crash-watchdog accuracy findings in root cause 4 (clean-end-as-death, count inflation, jetsam mis-attribution) COMPOSE with that review's branch-side fixes (false-crash pidfile reap, stderr tee, rm-race) — dedupe against that branch before building them.

---

## Findings at a glance

| Sev | Count | Of which NEW (not in the known register) |
|---|---|---|
| S1 | 19 | 12 |
| S2 | ~40 | ~30 |
| S3 | ~30 | ~25 |

Coverage: every axis returned a checked-clean list (see raw/aN.md tails); the register (raw/a12.md) bands 62 known items K01–K62 with git-verified statuses.

---

## Root cause 1 — Last-mile activation/deploy gap (the failure *generator*)

Fixes and safety nets land in the repo, go gate-green, and then never take effect live: new files are never symlinked (per-file-symlink live layer), plists are authored but never `launchctl` loaded, activation scripts sit in pending-activation without `.done`, and long-running daemons keep pre-fix code in memory. This one cause converts "fixed" into "still broken" across every other component.

| Finding | Evidence | Status |
|---|---|---|
| **39 tracked files unlinked live** (verified 07-23: 18 scripts, 12 bin, 8 hooks, 1 commands; 0 stale copies — clean linked-or-not binary; a11 measured 43 a day earlier) | a11 sweep + v1 re-sweep of hooks/ bin/ scripts/ commands/ skills/ vs ~/.claude | NEW S1 (class = K26) |
| **log-rotation plist never loaded → idl.jsonl 72–82MB** (regrew after the K39 "fixed" rotation landed; 183MB historic incident) | `launchd/com.claude.log-rotation.plist` absent from `launchctl list`; a10/a8/a9/a13 concur | NEW S2 — a Band-D "FIXED" item live-inert |
| **lead-deathwatch (L1) + lead-reconciler (L4) dormant** — built, tested, never loaded | a8; `docs/activation/wiring-all.sh:163-166`; launchctl-confirmed absent | KNOWN staged (K15/K16) |
| **operator-readout.sh unwired in all 4 config dirs** — the silver-platter Stop close-block is inert | a13/a11; code landed `652f66d` | KNOWN staged (K19) |
| **boot-resume auto-resume chain dead-on-activation** — its new files never symlinked | a9 (same class for power-policy-verify) | NEW S1 (instance of K26) |
| **Watchdog de-conflate fix has zero live effect until daemons cycle** — bash parses at spawn; running daemons predate the fix | a8, hooks/lead-crash-watchdog.sh | NEW S2 |
| Stop hooks wired by ABSOLUTE shared-checkout path → run whatever branch is checked out | K12, desk-audit p01 G-P1-3 | KNOWN open |

**Implication:** any fix from this audit must ship WITH its activation (symlink + load + restart), or it joins this list.

## Root cause 2 — Per-session resources with no lifecycle owner (the *memory leaks*)

Every session mints resources (mailbox, registry row, watchdog daemon+pidfile, worktree, TMPDIR, transcript, markers); almost nothing reaps them. GC exists only where an incident forced one.

| Store | Measured NOW | Owner? | Status |
|---|---|---|---|
| **/tmp/claude-501 harness TMPDIRs** | **21 GB across 60 per-session dirs**, never GC'd on session end (v1-verified) | none | NEW S2 |
| Transcript stores | 1.8 GB total; **0 transcripts >60 MB at verification** (largest 20 MB — the 07-22 giants rotated away; nothing caps regrowth) | none (no retention) | K01 class open; NEW S2 on retention |
| idl.jsonl | **85 MB at verification** (still growing during the audit; 183 MB historic) | rotation exists, unloaded | NEW S2 |
| Linked worktrees | **34 of 43 fully merged to origin/main, leaked** | none for this repo | NEW S2 |
| Watchdog pid files | **93 pid files, 83 stale (exact), 2,144 total dir entries** (v1-verified) | only crash-path GCs | NEW S2 |
| cc-registry rows | 20 of 42 stale (dead pid) | reaper partial; deregister staged (K20) | KNOWN + NEW numbers |
| Mailboxes | 39 dead boxes / 1,401 unacked (78%); +285 unacked in name-keyed boxes OUTSIDE the guard | none (cc-reaper/cc-teardown have zero mailbox handling) | KNOWN open (K04) + NEW S1 (guard bypass) |
| teammate-checkpoint.log + refs | 13 MB + 1,832 loose refs | none | NEW S2 |
| session-index.db | unbounded; no prune path exists | none | NEW S2 |
| .page files / alarm dirs | 181 .page; write-only dirs | damping landed, GC absent (K14) | KNOWN open |
| /tmp litter | ~40 wt-* dirs (3–6d), 27 claude-*-cwd pointers, handoff-recycle artifacts, launcher scripts, PF_NB brief copies | none | NEW S3 (brief copies carry content) |
| ~/.claude/state nudge-counts | one per session ever, never GC'd | none | NEW S3 |

## Root cause 3 — Liveness/identity verified on the wrong key (the *unexpected closures*)

The system repeatedly proves "alive/dead" using a key that survives identity changes (pane UUID, pid slot, name, mtime, process-pattern) instead of the actual identity (sessionId × live CC process × real assistant turns). In-place recycle — where the pane persists but the session swaps — defeats most of these checks.

| Finding | Evidence | Status |
|---|---|---|
| **Successor "liveness" gate matches ANY node-path process, not a live Claude** | a2; `scripts/handoff-fire.sh:1049` (siblings 662, 1139, 1976) | NEW S1 |
| **Successor verified once; detached watcher closes the caller up to ~180s later with no re-check** (verify→close TOCTOU) | a2; handoff-fire.sh:1044 vs :681-690 | NEW S1 |
| **Teardown identity pin is OPT-IN and has a narrow dead-pid race** — reaper path RED-proven safe; for un-pinned callers the exposure (v1 #6) is the pre-re-registration window where the row still holds the DEAD old pid: the lstart clause is vacuous on an empty lstart, and the pane-close leg (not a process kill) shuts the just-booted successor's pane; once session-register writes the successor's live pid, the pin correctly REFUSES | a7 + a14b V5 + v1 #6; bin/cc-teardown:199-206, 257 (pin passed only by cc-reaper:435-436) | NEW S2 (narrowed from S1 by verification) |
| **FIRE-FAILED leaves a live task-less pane orphaned** (invisible to reaper; duplicate-fire bait) + **warm-pool slot claimed pre-spawn, never released on failure** + **cold worktree+branch stranded on any later failure** | a1 (three S1s) | NEW S1 ×3 |
| **--recycle engagement still checks process-birth, not an assistant turn** — the K32 fix covered only cold non-recycle fires | a1 | NEW S2 |
| Non-/goal slash-command-headed brief only WARNS and fires → silent dead fire | a1 | NEW S2 |
| live-session-registry is write-only — no consumer reads it; the flaky-lsof reap it was built to prevent is not prevented | a6; hooks/live-session-registry.sh | NEW S2 |
| team-orphan-reaper liveness = bare `kill -0`, no identity pin (pid-reuse never-archives; missing pidfile archives the living) | a7 | NEW S2 |
| self-close dirty-guard inspects the CALLER's cwd, not the target's | a2; handoff-fire.sh:1060-1066 | NEW S2 |
| pre_trust read-modify-writes the shared `.claude.json` of the target account (concurrent fires lose updates) | a1 | NEW S2 |

## Root cause 4 — Unguarded hot paths and single points of failure (the *stalls and silent deaths*)

| Finding | Evidence | Status |
|---|---|---|
| **Supervisor sweep has ZERO timeout guards — one hung git/find ends all supervision silently** | a8; `scripts/lead-supervisor.sh:452-467`, `:178-200`; last-exit −9 observed with 0-byte logs | NEW S1 |
| **Per-session watchdog daemons are themselves unsupervised, with no single-instance guard** → daemon accumulation + sessions silently unwatched; one death recorded up to 5× (count inflation) | a8/a13; hooks/lead-crash-watchdog.sh:95-268 | NEW S1 |
| **Stall detection ignores teammate/worktree liveness → false ESCALATE of a healthy owned-wait** | a8; lead-supervisor.sh:385-390 | NEW S1 (the desk memory documents the semantics; unimplemented in code) |
| **Clean session end is processed as a death** (no clean-exit signal to the watchdog) | a8 | NEW S2 |
| **--backfill jetsam attribution uses a NOW-relative window → recycles flip to CRASH/jetsam-oom** (accuracy of the brand-new crash dashboard) | a8; lead-crash-watchdog.sh:61 | NEW S2 |
| **waiting-recycle is the only un-timeouted hook on the hot PostToolUse Bash slot; desk path spawns 10–30 subprocesses per Bash call** | a13 | NEW S2 |
| **page() wrapper swallows cc-notify exit 2/3/5 → safety pages to unresolvable targets silently dropped, then damped (`.notified` written on the false 0) so never retried** | a4 + v1 #11; `scripts/lead-supervisor.sh:97/100/102→143-144`; cc-notify:205's own comment says exit 5 is inert because "every fire-and-forget caller swallows it" | NEW S2 |
| **completion-push stamps `verdict=verified` on cc-announce rc 0, which includes the common no-watcher degrade** — false delivery confidence | a4 | NEW S2 |
| **cc-await-ping advances `.acked`=EOF on an unproven wake → silent drop that blinds the fail-loud guard** | a4 | NEW S2 |
| **session-index mkdir lock has no stale reap → one SIGKILL/OOM permanently wedges ALL session indexing** | a15 | NEW S2 |
| **cc-backlog compact is an unlocked read-rewrite-mv → concurrent append lost** | a15 | NEW S2 |
| Duplicate Stop-hook firings (boundary-handoff ×2, notify complete ×2 per Stop) | a11/a13 | NEW S3 |
| Unescaped shell→JSON interpolation in decision emitters (user-derived values) | a13 | NEW S2 (security-adjacent — prompt fix) |

## Cross-component violations (blind invariants slot — raw/a14b.md)

The invariants reviewer derived 10 invariants architecture-first, then verified at seams. Beyond confirming K02 (V2, the trigger-metric/failure-metric decorrelation) and refining the teardown pin (V5, integrated above):

| Finding | Evidence | Status |
|---|---|---|
| **V1 [S2] The claim ledger is worker-liveness-blind** — cc-dispatch claims `--by <host>-$$` = the cron dispatcher's pid, which exits seconds later; `claimer_live` therefore ~always false, so reap decides on claim-age alone (90-min heuristic). A live 91-minute worker gets its item reopened → double-dispatch → land-race → item BLOCKED; a worker dead at minute 5 strands its claim 85 min. | cc-dispatch:58,261; cc-backlog:357-359,420,447-448 | NEW S2 |
| **V3 [S2] Supervisor's world-view can be empty while sessions are live** — sweep iterates `/tmp/cc-telemetry/*.json` only (reboot-cleared; statusline stops emitting on backgrounded/long-turn sessions); unlike cc-reaper (independent live-pane self-check, cc-reaper:308-335) the supervisor has no telemetry↔pane reconciliation → live sessions invisible to every pager path. | lead-supervisor.sh:44,452-467,365-394 | NEW S2 |
| **V6 [S2] Watcher daemons have no launchd KeepAlive — "absence is the alarm" has no reader** — supervisor/reconciler/deathwatch each write heartbeats whose absence should page, but no KeepAlive job or absence-consumer exists; a crashed supervisor stays dead and the fleet silently loses its pager (matches the observed −9 last-exit with 0-byte logs). | lead-supervisor.sh:113-120; lead-reconciler:83-86; launchd/ (absent) | NEW S2 |
| **V4 [S3, latent S2] Mailbox exactly-once degrades to at-least-once** — the mkdir lock self-breaks after ~2s and `mailbox_take` proceeds lock-free (`_mbx_lock … || true`) → duplicate delivery under contention. Benign while the channel is advisory; double-acts the day any mail is imperative. | hooks/lib/mailbox-pending.sh:18-21,127 | NEW S3 |

**Seams verified WELL-DEFENDED (do not spend fix effort here):** reaper×handoff identity pin (classify `{pid,lstart}` → reaper `--expect-*` → teardown REFUSES on mismatch, RED-proven); recycle×mailbox identity continuity (pane-UUID-addressed mail; `.forward` + role repoint written BEFORE the self-close watcher arms, handoff-fire:1114-1143; SessionStart adoption backstop) — the a5 S1 applies to the CRASH path only, where no graceful chain runs; pane-typed delivery×modal (cc-notify v2 is file-inbox, non-keystroke; permission hangs get the unspoofable beacon → supervisor page).

**Dimensions per-component review is structurally blind to (M1-M5):** trigger-metric vs failure-metric decorrelation across a boundary (M1→K02); ledger-key semantics written by one component, resolved by another (M2→V1); divergent world-view SOURCES for one fleet — registry vs telemetry vs it2, only the reaper self-checks its blindness (M3→V3); timestamp format as a system-wide contract — one local-time producer corrupts every downstream age gate, scar already in-tree at cc-reaper:67 (M4); top-of-chain watcher liveness living in launchd/operator wiring, not in any script a reviewer reads (M5→V6).

## The goal's two focus areas, mapped

**2-way communication — where a message can be lost today (a5/a4):**
1. **Live-idle-no-watcher** (S1, NEW): delivery is folded into Stop-hook flow; a live but idle session with no armed continuation receives nothing — the dominant receive-side loss (`hooks/session-continue.sh:93-96,150-170`).
2. **Crash-stranded boxes** (S1, NEW): only the graceful handoff path writes a `.forward` (`scripts/handoff-fire.sh:1116` is the sole caller); mail to a crashed-then-recycled session is lost, not followed.
3. **Name-keyed boxes bypass the inbox-guard** (S1, NEW): 285 unacked lines with no fail-loud backstop (`bin/cc-inbox-guard:162` + `bin/cc-notify:141-147`).
Plus: no GC anywhere in the mail layer (K04), F12 urgency classification dead in production, forwarded lines lose class tags and reset age, guard floods on growing dead boxes, >PIPE_BUF messages can tear under concurrent append. The human plane (K03) remains model-only.

**/handoff self-opening/closing — lifecycle defect timeline (a1/a2/a7):**
- Fire: pre-spawn side effects (slot claim, worktree, pane) commit before any abortable step; every post-claim failure leaks them (3× S1).
- Engage-verify: cold non-recycle path fixed (K32); --recycle path still birth-based; slow cold `pnpm install` overruns the window → FALSE "FIRE FAILED" → retry pastes the brief into a shell mid-install (S2).
- Close: successor gate = any-node-process (S1); verified once, closed up to 180s later (S1); no-CC branch detaches the watcher with no pid capture → silent strand (S2); watcher steals operator focus unconditionally (S2).
- Post-close: teardown's dead-pid hole can collaterally close a recycled successor and log it clean (S1); worktrees/tmp artifacts persist (root cause 2).

## KNOWN-vs-NEW ledger

The register (raw/a12.md) is authoritative: K01–K14 open, K15–K25 staged-not-activated, K26–K30 recurring-structural, K31–K60 fixed 07-18→20, K61–K62 campaign. This wave: (a) re-confirmed K01/K02 as the top operator-facing risk (mechanism verified; no live giant at verification time); (b) caught one Band-D regression-by-inertness (K39 rotation fixed-in-repo, unloaded live); (c) added ~65 NEW findings, concentrated in root causes 2–4; (d) measured the K26 class at 39 concrete unlinked files (v1-verified).

## Fix roadmap (priority-ordered)

1. **Activation & deploy sweep** — one operator pass dissolves ~10 findings: run the staged pending-activation scripts, `launchctl` load com.claude.log-rotation (+ deathwatch/reconciler plists), symlink the 43 unlinked files (adopt `link-live.sh` into the ff-sync flow so the class dies), restart the stale watchdog/supervisor daemons so landed fixes take effect. Mostly C10 operator-gated; the board should carry it as runnable commands.
2. **Size-triggered recycle (K02)** — wire transcript-size/RSS thresholds into waiting-recycle Stage-1/2 with an emergency page fallback; the dead `input_tokens` burn-history signal (a3) is a ready size proxy. Post-supersession: this is bounded-state defense-in-depth (I5), no longer the crash-class fix — the crash lever is the CC version pin (supersession note).
3. **handoff-fire lifecycle correctness** — successor gate pinned to (pane UUID × live CC process × sessionId) with a T-0 re-verify before close; FIRE-FAILED cleanup (close-or-mark pane, release slot, remove cold worktree); recycle-path engagement = real assistant turn; slash-command-headed briefs hard-fail pre-fire.
4. **GC franchise** — one sweeping reaper with per-store adapters: mailboxes (K04 lifecycle), merged worktrees, watchdog pidfiles, /tmp/claude-* TMPDIRs, transcript retention, session-index prune, .page files, /tmp handoff artifacts. Registry deregister is already staged (K20) — activate it.
5. **Supervision hardening** — timeout-wrap every external call in lead-supervisor; watchdog single-instance guard + clean-exit signal + pid-dedup; fix the jetsam backfill window; teammate-liveness-aware stall detection; pin supervisor/reconciler/deathwatch under launchd KeepAlive so "absence is the alarm" has an OS-level reader (V6); give the supervisor a telemetry↔live-pane delta self-check like the reaper's (V3).
6. **Comms truthfulness** — page() honors cc-notify rc; completion-push records watcher-verified vs degraded; await-ping advances only on proven wake; name-keyed boxes enter the guard; forward-chain writes on ALL replacement paths (crash-recovery included); application-level message-id dedupe (or an enforced advisory-only contract) so the lock-break at-least-once path stays harmless (V4).
7. **Worker-keyed claims (V1)** — the fired session re-claims the backlog item under its own identity on engagement (or the claim records the worker paneUUID and `claimer_live` resolves it via cc-sessions), ending age-only reaping of live work and 85-minute strands of dead work.
8. **Lock hygiene** — adopt the a15 pattern table: owner-verified stale-reap for mkdir locks, flock timeouts, tmp+mv for every registry/backlog rewrite; system-wide UTC timestamp contract lint (M4).

## Method appendix

- Wave: 15 axes (see raw/); critic gate REVISE→addressed (added locks axis A15, launchd static review, seam ownership). Adversarial: blind-invariants slot + lead-level negative-space + independent 13-claim verification (verdicts below).
- Incident during the audit itself, worth recording: the Fable-5 adversarial slot was AUP-safety-flagged on a defensive-security brief (raw/a14.md carries the error verbatim); rerun on Opus succeeded. Separately, all 15 workers' final reports STRANDED in their transcripts (this runtime's fire-and-forget subagents have no SendMessage; idle_notification ≠ result delivery) — reports were harvested from `~/.claude-secondary/projects/<proj>/*.jsonl` by agentName, which is itself a live example of the comms-layer gap this audit documents.
- Verification verdicts: integrated below and into the body (numeric drifts corrected in place).

### Verification table (v1-verify, 2026-07-23 — full text in raw/v1.md)

| # | Claim | Verdict |
|---|---|---|
| 1 | Successor gate matches any node on the pane tty (`handoff-fire.sh:1049` + 662/1139/1976) | **CONFIRM** — `ps -o comm= -t <tty> \| grep -qE 'node\|claude'`, not session-pinned |
| 2 | Verify-once, close up to 180s later, no re-check (`:1044-1053` vs `:660-686`) | **CONFIRM** — watcher polls the CALLER tty only; successor never re-verified |
| 3 | FIRE-FAILED leaks pane + pool-slot claim + cold worktree (`:2115-2116`; claim `:1541`; add `:1547`) | **CONFIRM** — no trap, no release, no worktree remove on any failure branch |
| 4 | Recycle chain is used_pct-only; zero size/RSS triggers | **CONFIRM** (`waiting-recycle.sh:51,53-55`; `boundary-handoff.sh:65`) |
| 5 | Burn-history `input_tokens` col-3 is written, never read | **CONFIRM** (`context-econ.sh:35,44,48` write; `ce_burn:74-77` reads $1,$2 only) |
| 6 | Teardown dead-pid hole | **CONFIRM, narrowed** — pre-re-registration race, pane-close leg only; pin REFUSES once the successor re-registers |
| 7 | Supervisor has zero timeout guards | **CONFIRM** — no timeout/gtimeout anywhere; in-code comment admits a ~5-min `find` hang, mitigated with `-prune` not a timeout |
| 8 | Watchdog: no singleton guard; clean end runs death path; pid-file leak | **CONFIRM** — measured 93 pid files / 83 stale / 2,144 dir entries |
| 9 | log-rotation plist unloaded; idl.jsonl unbounded | **CONFIRM** — plist exists, absent from launchctl; idl.jsonl **85 MB** |
| 10 | /tmp/claude-501 ~21GB no-GC; 2 transcripts >60MB | **PARTIAL** — 21 GB / 60 dirs CONFIRMED; >60MB transcripts **REFUTED today** (largest 20 MB) |
| 11 | page() swallows cc-notify rc 2/3/5 | **CONFIRM** — locus `lead-supervisor.sh:97/100/102→143-144`; damped after the false success, never retried |
| 12 | Live-idle-no-watcher mail gate | **CONFIRM** — `session-continue.sh:93-96` exits before the mail fold (`:156-170`) |
| 13 | 43 unlinked tracked files | **PARTIAL** — **39** today (18 scripts/12 bin/8 hooks/1 commands); phenomenon holds |

Verifier's meta-note: treat specific integers as time-sensitive, phenomena as verified; #6 was the one over-stated claim (narrowed above).
