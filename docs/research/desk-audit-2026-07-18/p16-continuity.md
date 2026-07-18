# P16 — Machine Wake/Power/Network Continuity (the physical 24/7 substrate)

**Machine**: MacBookPro18,2 (M1 Pro **laptop**), Darwin 24.6.0 (macOS Sequoia 15.6), arm64.
**Uptime at audit**: 6 days (boot Sat Jul 11 21:33) — empirically stable on AC.
**Method**: all cells below are a live read (command cited) or a cited plist key. macOS *semantics*
inferred where not locally reproducible are tagged `[semantic]`. Audit 2026-07-18 03:31–03:34 PDT.

Legend for effect columns: **launchd** = the claude/chrisren jobs · **CC** = open iTerm2 Claude Code
sessions · **turn** = an in-flight API turn · **it2** = the it2 python keystroke API.

## (1) Substrate truth table

| Dimension | Current setting (live read) | launchd jobs | CC sessions | in-flight turn | it2 API | Recovery asset |
|---|---|---|---|---|---|---|
| **System sleep — AC** | `sleep 0` (never); `powerd` holds *"Prevent sleep while display is on"* (displaysleep 0); +CC per-turn caffeinate. `pmset -g custom` AC block. | run | survive | survive | survive | None needed on AC. **But policy is manual, not repo-enforced** → G-P16-3. |
| **System sleep — battery** | `sleep 1` (1-min idle sleep!), `womp 0`. `pmset -g custom` Battery block. | suspended during sleep; **1 missed fire coalesced on wake** `[semantic]` | frozen→may die on long sleep | errors if sleep mid-stream | frozen | resume-sessions (manual). Battery profile is **hostile to 24/7** → G-P16-2. |
| **Display sleep** | `displaysleep 0` both profiles. | — | — | — | — | None needed. Also manual/unenforced (rides with G-P16-3). |
| **PowerNap** | `powernap 1`. | user LaunchAgents get **no CPU** in Power Nap; interval jobs coalesce on full wake `[semantic]` | frozen | — | — | Acceptable — idempotent sweeps catch up on wake. |
| **Lid** | `AppleClamshellState = No` (**open now**); 2× external 5K displays online + AC. | — | — | — | — | Clamshell (ext display+AC+kbd) keeps it awake **only while those hold**; not enforced → G-P16-5. Lid-close off-dock/on-battery = immediate sleep; `caffeinate` **cannot** veto lid-close. |
| **Screen lock** | console user `chrisren` logged in; lock is display-only. | run | run | run | **works while locked** (local IPC) | None needed — screen lock is benign to headless work. |
| **Network drop** | `tcpkeepalive 1`; **no** `CLAUDE_CODE_*` retry/timeout env in repo; Anthropic SDK has built-in retry. Empirical: `isApiError`×26 in one transcript that then **continued**. | unaffected (local) | **process survives**; turn retries | brief drop → SDK retries request; **mid-stream drop → turn errors**, then the session's own continue-loop re-drives | unaffected (local) | **In-session retry works** (empirical). Does NOT cover process death. |
| **Reboot** | **auto-login OFF** (`autoLoginUser` absent) + **FileVault ON** + **zero LaunchDaemons** (all jobs are LaunchAgents). | **ALL halt** until a human unlocks FileVault *and* logs into the GUI (aqua) | **ALL die**; iTerm2 does **not** restore (`OpenArrangementAtStartup=0`, `NSQuitAlwaysKeepsWindows=0`) | die | die | resume-sessions (**MANUAL**). lead-supervisor restarts at login but **PAGES only**. Battery=UPS rides through *power blips*. **← WORST HOLE.** |
| **OS update** | `AutomaticallyInstallMacOSUpdates=1`, `CriticalUpdateInstall=1`, `ConfigDataInstall=1`, `AutomaticDownload=1`. | machine **self-reboots overnight** → see Reboot row | mass session death | die | die | macOS *may* FileVault-unlock across an update-triggered reboot (reaches desktop) but still **no iTerm2/CC relaunch**; a *spontaneous* reboot stays FileVault-locked. **P0 in tandem with Reboot.** |
| **Login session** | LaunchAgents only (need aqua). lead-supervisor `KeepAlive=1 RunAtLoad=1` (pid 17867, never exited). cc-reaper/team-orphan-reaper/sweep = interval. | RunAtLoad jobs restart at login; interval jobs resume | **NOT auto-relaunched** | — | — | lead-supervisor auto-restarts; **CC sessions: NONE** (manual resume-sessions). |

## (2) Mechanism notes (per job type used here)

- **All persistence is `~/Library/LaunchAgents` — NO LaunchDaemons** (`/Library/LaunchDaemons` grep for claude/chrisren = empty). LaunchAgents require a **logged-in GUI (aqua) session**; nothing runs at the loginwindow / pre-login stage. So *every* automated actor is gated behind a human FileVault-unlock + login after any reboot.
- **`com.claude.lead-supervisor`** — `KeepAlive=1, RunAtLoad=1`, runs `scripts/lead-supervisor.sh --daemon`. `scripts/lead-supervisor.sh:4` **RULING #1: "it PAGES, never auto-recovers"** — a bash watchdog that detects + checkpoint-preserves + pages `cc-notify`; it *structurally cannot* call in-session tools (`:11` S-3). It reads `/tmp/cc-telemetry/*.json` (`:40`), which a reboot **wipes** → post-reboot it has nothing to page. KeepAlive relaunch is throttled to ≥10s by launchd `[semantic]`.
- **`com.chrisren.cc-reaper`** `StartInterval=300`; **`com.claude.team-orphan-reaper`** `StartInterval=600, RunAtLoad=0`. StartInterval jobs: on wake, one missed fire is run (coalesced), then the cadence resumes `[semantic, launchd.plist(5)]`. Idempotent sweeps → sleep-tolerant.
- **`com.claude.session-search-sweep` / `-backfill`** `StartInterval=60`. **Repo copies contain a raw `&`** (`2>&1` unescaped) → `plutil -p` errors *"unknown ampersand-escape sequence at line 11"*; the **live-loaded** copies are fine (`launchctl print` → `run interval = 60 · last exit 0`). Fragility: a `plutil`-validated reinstall would reject them → G-P16-6.
- **StartCalendarInterval jobs** (`restic-claude-archive` Fri 02:00; `verify-2114-archive` Sun 09:00 + `RunAtLoad=1`; watch-* one-shots at 09:07/09:12): if asleep/off at fire time, launchd runs **one** coalesced fire on wake; multiple missed fires do **not** stack `[semantic]`. If *shut down* (not asleep) at fire time and it's a LaunchAgent, it fires only after next login.
- **CC per-turn caffeinate** — the ~27 `caffeinate -i -t 300` procs are children of `claude --model claude-opus-4-8` (CC builtin), **not repo infra** (repo greps clean; `bin/cc-teardown:139` only *skips* caffeinate in a kill-list). It prevents idle sleep only while a turn runs, releasing 300s after work stops (`TimeoutActionRelease`). **It is a per-turn keepalive, not a machine-awake policy.**
- **Primary awake mechanism on AC** = `sleep 0` + `displaysleep 0` (powerd's "prevent sleep while display on"), **not** caffeinate. This is why 6-day uptime holds even when sessions idle.

## (3) Gaps

| ID | Evidence | Class | Sev | Failure scenario | Fix sketch |
|---|---|---|---|---|---|
| **G-P16-1** | auto-login OFF + FileVault ON + only LaunchAgents; resume-sessions is manual; iTerm2 no-restore | 24x7 | **P0** | Any reboot (panic / power > battery / OS auto-update) lands at FileVault pre-boot lock; even after login nothing relaunches CC → **indefinite full halt until a human acts** | Remove the self-reboot trigger (T-P16-1) + post-login auto-resume chain (T-P16-2) + iTerm2 restore (T-P16-5) |
| **G-P16-2** | `pmset -g custom` battery `sleep 1`, `womp 0` | 24x7 | **P1** | AC loss → battery; all sessions idle >1min → **machine sleeps in 1 min**; if outage > battery runtime → shutdown → FileVault lock | `pmset -b sleep 0` (or explicit awake floor T-P16-4) + decide battery policy |
| **G-P16-3** | no repo pmset/caffeinate writer (install.sh + scripts grep empty) | 24x7 | **P1** | The load-bearing AC `sleep 0` is a manual out-of-band setting; an OS update / SMC-NVRAM reset / new machine silently reverts it to default idle-sleep → machine starts sleeping | install.sh applies `pmset -c sleep 0 disablesleep 0` + a boot verifier re-asserts it (T-P16-3) |
| **G-P16-4** | lead-supervisor telemetry in `/tmp` (`:40`), wiped on reboot; RULING #1 pages-only (`:4`) | 24x7 | **P1** | The only KeepAlive actor is blind right after the exact event (reboot) that most needs recovery | Boot-delta alarm/resume at login (T-P16-2 / T-P16-7) |
| **G-P16-5** | `AppleClamshellState=No` + ext displays, but unenforced | none | **P2** | Lid closed while off-dock or on battery → sleep; `caffeinate` cannot veto lid-close | Document clamshell requirement; or T-P16-4 awake floor + keep docked |
| **G-P16-6** | repo `session-search-*` plists raw `&` → `plutil` lint fails | none | **P2** | A `plutil`-validating reinstall/CI rejects them; silent index-sweep loss | `&` → `&amp;` in the two repo plists; add `plutil -lint` gate |
| **G-P16-7** | mid-stream network drop errors the turn; recovery depends on session continue-loop, not a network layer | FM | **P2** | A long streaming turn that loses its socket errors; if the session's Stop/goal loop is absent (e.g. post-/compact per resume-sessions Phase 3) it sits idle | Rely on keepalive watcher (reso-keepalive) + goal-hook; no infra change if loop present |

## (4) Task candidates — the minimal continuity kit

| ID | Action | Acceptance criterion | Depends-on |
|---|---|---|---|
| **T-P16-1** | Remove the overnight self-reboot trigger: `sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticallyInstallMacOSUpdates -bool false` (keep `CriticalUpdateInstall`/`ConfigDataInstall` for security data, which don't reboot). Adopt manual OS-update discipline. | `softwareupdate --schedule` still on for checks; `AutomaticallyInstallMacOSUpdates=0`; no unattended OS reboot | operator decision (security tradeoff) |
| **T-P16-2** | Post-login auto-resume LaunchAgent (`RunAtLoad=1`): on GUI login, if any transcript's last write < `kern.boottime` (sessions were open at last boot), invoke the resume-sessions flow (`~/.reso/bin/reso-resume-one` per open session) + start `reso-keepalive`. | After a login following a reboot, previously-open sessions are resumed with **zero** human action; verified by fresh commits/turns | resume-sessions skill; reso bin; T-P16-5 |
| **T-P16-3** | Make machine-awake policy repo-managed + idempotent: install.sh runs `sudo pmset -c sleep 0 disablesleep 0 displaysleep 0`; a boot LaunchAgent re-asserts + verifies (`pmset -g custom` diff), pages on drift. | `pmset -g custom` matches intended policy after a reboot; drift pages the operator | install.sh; cc-notify (page channel) |
| **T-P16-4** | Machine-awake **floor** independent of CC turns: RunAtLoad `KeepAlive` LaunchAgent runs `caffeinate -s` (AC) / `-i` so idle-sleep is prevented even when all sessions idle (covers battery `sleep 1` while docked & away). | A `caffeinate` assertion is present in `pmset -g assertions` even with **zero** active CC turns | none |
| **T-P16-5** | iTerm2 session restoration: set `OpenArrangementAtStartup=1` with a saved desk arrangement, OR a login agent that opens iTerm2 + launcher panes. | After login, iTerm2 reopens the desk layout deterministically | T-P16-2 (pairs) |
| **T-P16-6** | Fix malformed repo plists: `2>&1` → `2>&amp;1` in `session-search-sweep`/`-backfill`; add `plutil -lint launchd/*.plist` to the repo gate. | `plutil -lint` passes on all repo plists; CI gate green | none |
| **T-P16-7** | (If T-P16-2 deferred) Boot-delta alarm: login agent pages *"machine rebooted, N sessions were open at last boot"* via cc-notify. | A reboot with open sessions produces exactly one operator page on next login | cc-notify |

**Recommended order / leverage**: T-P16-1 (kills the most likely self-inflicted reboot, ~zero risk) →
T-P16-3 + T-P16-4 (make "stay awake" durable & battery-safe) → T-P16-2 + T-P16-5 (close the human-in-loop
resume gap) → T-P16-6 (hygiene). T-P16-1 alone removes the single most probable path into the P0.

## (5) Cross-beat dependencies

- **Reaper/supervisor beat**: `lead-supervisor` (KeepAlive, pages-only) + `cc-reaper`/`team-orphan-reaper`
  (interval) are the *within-run* watchdogs; T-P16-2 (post-login resume) is their missing *boot-time*
  complement. Do not duplicate reap logic — this beat owns only the boot/power edge.
- **Comms/notify beat**: T-P16-3/-4/-7 all page via `cc-notify` (same channel lead-supervisor uses at
  `scripts/lead-supervisor.sh:66`). Depends on that channel being reboot-durable.
- **Launcher beat**: T-P16-2/-5 must invoke the `claude-nextN`/`claude-fableN` launchers and
  `reso-resume-one` — the exact resume mechanics are owned by the resume-sessions skill; this beat only
  triggers them at the right moment.
- **claude-update beat**: LOW strand risk — running sessions pin their binary by absolute path
  (`~/.claude-183/...`); `claude-update` cleanup explicitly skips versions `in use by running session`
  (`bin/claude-update:60`). A binary bump does not strand live sessions; only a reboot does.

## (6) Adversarial self-pass + Uncertainties

**Adversarial pass — 3 gaps investigated with live reads (not assumed):**
1. *"You assumed a laptop reboots on power loss like a desktop."* — FALSE, checked: battery 100%,
   **Condition Normal, cycle 168, max-capacity 85%** → healthy built-in **UPS**. A power *blip* rides
   through (no reboot) — a genuine mitigant vs a desktop. The residual risk is a *sustained* outage
   exceeding battery runtime, and the hostile battery `sleep 1` profile in the interim (G-P16-2).
2. *"You assumed network drops kill turns."* — Partly FALSE, checked: `isApiError`×26 in one recent
   transcript that then **continued** → transient API/network errors are retried *within a live process*
   (SDK retry + session loop). The real exposure is **process death** (reboot/iTerm quit), not blips.
3. *"You ignored lid-close on a laptop."* — checked: lid **open now**, `AppleClamshellState=No`, 2× external
   5K displays → currently clamshell-safe, but unenforced (G-P16-5); `caffeinate` cannot veto lid-close.

**Uncertainties (explicit):**
- StartCalendarInterval/StartInterval **missed-fire coalescing** and **Power-Nap CPU starvation** are
  stated from launchd/macOS semantics (`launchd.plist(5)`), **not** locally reproduced (machine hasn't
  slept in 6 days). Confidence high but tagged `[semantic]`.
- Whether macOS actually **FileVault-unlocks across an `AutomaticallyInstallMacOSUpdates` reboot** on this
  Sequoia build (via a stashed one-time token) is **version-dependent and not tested** here. A *spontaneous*
  reboot is definitely FileVault-locked; the update-reboot case is the uncertain one. Either way, iTerm2+CC
  do not relaunch — so the recovery gap holds regardless of which way this resolves.
- `autoLoginUser` read without sudo returned "does not exist" (auto-login off). A configuration profile
  could theoretically set it elsewhere; not exhaustively checked. FileVault-On makes classic auto-login
  moot anyway (unlock is required at boot).
- **Mid-stream** turn behavior on TCP reset (does the SSE stream resume or hard-error?) is inferred from
  SDK behavior + the isApiError evidence, not from a forced-drop experiment.
- `SUAutomaticallyUpdate` (iTerm2) read returned no value (key absent) — iTerm2 auto-*install* of updates
  is likely off, but auto-*check* is on (`SUEnableAutomaticChecks=1`); an iTerm2 update prompt could
  appear but should not restart unattended.
