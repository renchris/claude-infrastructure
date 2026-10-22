# The 2026-10-18 panic: data.kalloc.1024 reached the zone-map ceiling; `#!` script execs are the leak

Scope (frozen): root-cause the 2026-10-18 16:33 CDT kernel panic, identify long-term improvements,
and identify sessions the crash left unresolved.

Method: one 15-agent workflow (`wf_1edc2b78-c44`, 2026-10-18): panic forensics, alarm-chain
timeline, live re-measurement, origin hunt with on-box A/B, web sweep, prior-work gap, two
independent session audits, an adversarial verifier per research track, and a completeness critic.
The scratch evidence was in `/tmp/panic-1018/` and is lost at the next reboot. The numbers needed to
re-derive each conclusion are inline below.

## Answer

1. **Mechanism (93%).** On macOS 15.7.9 (24G830, xnu-11417.140.69.711.44), every successful
   `execve()` of a `#!` script leaves one 1 KiB element in `data.kalloc.1024` that outlives the
   process. Running the same script as `/bin/bash script` leaves nothing. Upstream reports the same:
   [claude-code#66020](https://github.com/anthropics/claude-code/issues/66020) (25+ reports with the
   identical panic string, all capped near 20-21.3M elements, on Sequoia 15.7.3+ and Tahoe 26.x) and
   [Photon's write-up](https://photon.codes/blog/we-found-a-kernel-memory-leak-in-macos-that-any-shell-script-can-trigger)
   (a `vfs.namei` path buffer, call site AppleSystemPolicy's execve label hook; seen on a SIP-off
   26.6.2 VM only). There is no Apple acknowledgement. macOS 27.0 is reported fixed by 3 short tests.
   Nobody has data for 15.8.x.
2. **Which processes cause it (about 70% that they dominate).** Ours. All 101 hook commands in
   `~/.claude/settings.json` run by bare path, and 99 of them are `#!` scripts. The status line is a
   bare `#!` path too. About 20 hooks fire on every Bash tool call, and the ~570 `#!` executables in
   `hooks/ bin/ scripts/` call each other by path. Ruled out by on-box A/B: sandbox-exec (unique or
   shared profile), setuid `ps`, launchctl, osascript, codesign, `bash -c`, Codex (not running),
   Claude Code's Bash sandbox (off in every settings file), Tailscale/NetworkExtension, and terminal
   rendering (already refuted on 09-30).
3. **Why it panicked (92%).** The zone reached 20,955,520 elements (19.98 GiB) after 18.05 days of
   uptime. `zalloc[3]` is KERN_NO_SPACE from `kmem_alloc` on the zone map's DATA submap, whose range
   is 25.66 GiB (0xfffffe2fae000000-0xfffffe3618000000). Randomized guard chunks use the rest, so the
   **practical ceiling on this box is about 20 GiB / 21M elements**. The 9.89 GB figure quoted by
   the alarm (from panic #5 on 08-24) was never a ceiling: that panic was compressor/watchdog with
   this zone as a bystander. `nesessionmanager` (pid 361) is a victim. Its routine plist save
   (`-[NSDictionary writeToURL:atomically:]` → `rename(2)` → APFS `IOMallocZeroData`) happened to make
   the first 1 KiB allocation that found no room.
4. **The kernel warned for 8 hours.** Between 08:20 and 16:28 the kernel killed 343 idle daemons
   with `osr_code: 9` (JETSAM_REASON_ZONE_MAP_EXHAUSTION), which could free nothing. At 07:56 the
   JetsamEvent report showed zoneMapSize 23.38 GB of a 24.94 GB cap (93.7%). A first `osr_code: 9`
   line in the kernel log means the panic is hours away.
5. **Our defense detected it and nothing acted (88%).** The capacity alarm (rung 8) crossed 4 GB on
   10-04 16:50Z and 6 GB (ALARM) on 10-06 20:01Z. It then read ALARM for 12 days through 10, 12, 15
   and 18 GB, and nobody rebooted. The broken links:
   - Ownership without a trigger: the ticket `a417ab59e8f5` closed "done" on 09-30, with the
     originator still open. The reboot duty sat in two operator-blocked rows (`dbd148b91ffa`,
     `20e5ccab90be`) among about 177, untouched after 10-01. Decision `ee0ad84e8974` (a standing
     reboot rule) has been open since 09-30 with no default.
   - Notification: the page was rewritten 18 times. Each SKIPPED zprint read retracted it, because
     the carry window is 4×900 s. It reached the operator only as one of ~400-560 records in a count
     banner that never said "kalloc". Pushover was never set up, there was no desk role (871 sends
     returned `no-role`), and on the final day the sweep stopped itself before its notify phase.
   - Wrong ceiling: the page text anchored on 9.89 GB. The zone passed that with no panic, so the
     page read as a false alarm.
   - Prep refused: `alarm-reboot-prep.sh` refuses while any land is in flight, and does not retry.
     A reboot on 10-12 was put off for in-flight lands and never revisited. On 10-17 the operator
     was told to reboot for load reasons, with the 18 GB zone not mentioned.
   - The staged root capture (`~/.claude/autonomy/kalloc-root-capture.cmd`) never ran.
6. **The leak is speeding up and the next panic is close.** This boot shows 44-53 elements/s
   (3.6-4.4 GiB/day at load 160-330, during the restore surge). The last boot averaged 13.4/s
   (1.06-1.11 GiB/day). At tonight's rate, 6 GiB arrives about **10-20** and the ~20 GiB ceiling
   about **10-23**. If the rate falls back to last boot's mean, the dates are 10-24 and 11-05.
   Re-forecast from the trailing slope, not from the since-boot mean.

## Correction to the 2026-09-30 conclusion

`kalloc-ratchet-2026-10.md` named kernel credential churn (r = 0.93 with the `cred` zone) as the
driver. That correlation is real, but it is the transient part. `cred` rises and falls with
short-lived sandboxed processes and nets to about zero. The leak is the steady drift in
`data.kalloc.1024 − cred`: +41/s tonight, and +15-25/s in every 09-30 carry-ab class. A `#!` exec
adds about 0 to `cred` and +0.94-1.07 to that residual. On this boot `kalloc.48` no longer
co-moves (r = 0.09). The cred link itself was re-measured at r = 0.76.

## The A/B (origin hunt, interleaved ON/OFF cycles, residual = data.kalloc.1024 − cred)

| Arm | Retained elements per run (±1 SE) |
|---|---|
| `/usr/bin/true` | −0.02 ± 0.02 |
| one `#!` script | +0.94 ± 0.06 (repeat +1.07 ± 0.08) |
| `#!` script that runs a compiled binary | +0.89 ± 0.09 |
| 2 nested `#!` scripts | +1.98 ± 0.13 |
| 3 nested `#!` scripts | +2.86 ± 0.20 |
| `sh leaf.sh` / `bash leaf.sh` | ≈ 0 |
| `sh top.sh` (runs one `#!` inside) | +0.91 ± 0.17 |

96 cycles, mean load 363. Subtracting `cred` cuts the per-cycle residual SD from 636 to 133, which
is what makes the per-op figure readable under fleet load. No-root repro, for the Apple report:

```
printf '#!/bin/sh\nexit 0\n' > /tmp/leaf.sh; chmod +x /tmp/leaf.sh
zprint data.kalloc.1024            # column 7 = inuse
for i in $(seq 10000); do /tmp/leaf.sh; done        # +~9,400 more than the arm below
for i in $(seq 10000); do /bin/sh /tmp/leaf.sh; done
```

## Long-term improvements, ranked

Prevent:
1. Run every hook and the status line through an explicit interpreter (`/bin/bash ~/.claude/hooks/x.sh`)
   across all 5 config dirs. Also convert script-to-script calls on hot paths, and add a land-gate
   lint against bare-path exec of a repo `#!` script on the hook hot path. Verify with
   Δ(data.kalloc.1024 − cred)/s at matched load, before and after.
2. Collapse the ~20 hooks per Bash call into one dispatcher exec. This also lowers load.
3. Move to macOS 27.0.1 (the only reported fix) after a 24 h per-exec probe. 15.8.1 is untested.

Contain:
4. Reboot on the forecast, before ~14 GiB. `fdesetup authrestart` (operator consent) avoids the
   FileVault unlock wait, which cost 3 hours this time.

Detect and act:
5. Tiers at 50/70/85% of the ~20 GiB ceiling, each with a trailing-3-day ETA. Remove the 9.89 GB
   anchor (`scripts/capacity-alarm.sh` chronic advice and page text). Carry the last value on
   SKIPPED instead of retracting. Page on the first `osr_code: 9` kernel line.
6. A dedicated, named channel for this page, re-sent per tier and daily, independent of the sweep's
   tail.
7. `alarm-reboot-prep.sh` waits (bounded) for in-flight lands, or freezes them, instead of refusing.
8. Rule on `ee0ad84e8974` and give it a default.
9. Any session that answers a reboot question prints the zone level and the ETA.

Report upstream:
10. File Apple Feedback with the repro above, the panic file and a `sudo zprint data.kalloc.1024`
    views breakdown. Correct the draft (`apple-feedback-compressor-panic-draft.md`), which says
    kalloc growth is not the panic mechanism.
11. Add this machine's 15.7.9 data point to claude-code#66020.

## The alarm actuator (2026-10-19): improvements 5-7 and the head of 9

Built on `fix/kalloc-alarm-actuator`; the commit body holds the per-file detail.

- Ceiling: `scripts/capacity-alarm.sh` `KALLOC_CEILING_ELEMS=20955520` is the one constant. The
  9.89 GB anchor is gone from the advice and the pages.
- Tiers at 50/70/85% of it. The level, the trailing-3-day least-squares slope over this boot's
  measured samples (`~/.claude/logs/kalloc-zone-series.tsv`) and the ETA go on
  `~/.claude/autonomy/kalloc-zone.page`. That file is beside `pages/`, so no escalation count
  includes it. The same values go to `kalloc-zone.state` for other readers.
- Carry: inside a boot, the last measured value carries at any age. It is no longer dropped after
  4×900 s. A SKIPPED or timed-out read keeps the page up, and only a reading below the floor or a
  reboot retracts it.
- The kernel's warning: a bounded `/usr/bin/log` scan, once every 5 minutes, with a
  memorystatus-category predicate. At load 290 it took 7 s, against 63 s for `sender == "kernel"`.
  It pages on the first `killing_idle_process … osr_code: 9` line. **Naming correction to § Answer
  4:** that line's own verb is `killing_idle_process`, and xnu's `reason.h` names code 9
  `JETSAM_REASON_MEMORY_IDLE_EXIT`, not zone-map exhaustion. It is the idle sweep the kernel runs
  when the zone map or the compressor nears exhaustion; panic #5's spiral began with the same
  lines (`panic-2026-08-24-evidence/log-timeline.md:77`). It is a pre-panic sign either way.
- Notification: the alarm posts its own banner, titled with the zone, the level and the ETA. It
  posts on the first `osr_code: 9` line, on each tier crossing, and every 24 h while the zone is at
  tier 1 or higher. It does not depend on the sweep or a desk role. The phone leg uses `lr-page.sh`
  once the Pushover file from backlog `516d31862158` exists. `hooks/operator-readout.sh` prints the
  zone on its own `⚠` line, and that line by itself is enough to render the operator block.
- `scripts/alarm-reboot-prep.sh` prints the zone level, its share of the ceiling and the ETA as
  line 2. It waits for an in-flight land with a printed deadline (1800 s by default) instead of
  refusing.
- `scripts/compressor-sentinel.sh` takes `panicked_at` from the panic's `Calendar:` epoch
  (`panicked_at_src`). The 10-18 row already in the ledger keeps its report-write time, 19:40:28.
  The true time is 16:33:33 CDT.

Still open, and not this change's to decide: the reboot rule itself (decision `ee0ad84e8974`).

## Untested, cheapest first

1. The intervention A/B in improvement 1. It settles "dominant".
2. One `sudo zprint data.kalloc.1024`: what share sits in the `vfs.namei` view.
3. A 10-minute `eslogger exec` census of `exec.script != null` against the residual growth.
4. Developer Tools exemption for kitty (`spctl developer-mode enable-terminal`), then repeat the
   leaf A/B. If the leak sits in AppleSystemPolicy's exec hook, this may bypass it (about 30%).
5. `data_shared.kalloc.1024` has never been monitored.

## Sessions after the crash (two independent audits, 90-95%)

`scripts/boot-resume.sh` already ran (19:42-20:14 CDT): 41 of 49 recorded sessions resumed, 1
failed to launch (`ed29c5a1`), and 7 Agent Teams teammates were skipped by design. No committed work
was lost. `cc-restore --after-crash` is the wrong tool after a kernel panic: it reads only the
current boot's heartbeat and fails preflight.

| Session | State | Action |
|---|---|---|
| TPG `30c3a88d` (next2, `~/Development/tpg`, not a git repo) | finished 10-06; deliverables on disk; pane is a bare shell | nothing to land; one open operator question: keep the tpg.com copies scraped against the site's Terms of Use (`TPG_BRAND_GUIDELINES.md:92`)? |
| VoiceInk, Club Vinyl panes | absent from `hb.roster.json`, so never considered for resume | resume VoiceInk (it had a live claude); Club Vinyl was already a shell fallback |
| `ed29c5a1` | failed to launch | resume |
| `64973e2f` (B13 round 16 lane D) | announced self-close 19:51, process still alive | lane landed; close the pane |
| `09e18eed` (TrueMemory 2.0 lead) | idle, watcher killed by the reboot | re-engage |
| `a1db6aaa` (SevenRooms app map) | AskUserQuestion open | operator: move the SevenRooms window back on screen |
| `e52f1f63` (kitty crash incident) | waiting for the patched kitty swap | patched build staged, stock 0.48.2 still running |
| `aee892fa` (startup-hooks wave lead) | alive; 7 unlanded commits, 3 + 7 dirty files across its trees | lead holds it; recycling at 49% |
| local-only branches | `tm2-plan` (382 commits) and `tm2-*` (99-210 each) have no remote; Time Machine fails to mount | data-integrity risk: back them up |

The roster gap (live panes missing from `hb.roster.json`) and the panic-blind `cc-restore` are the
two recovery defects this crash exposed.

### Recovery follow-up (2026-10-19, dispatched session `fix/post-panic-recovery`)

| Item | Outcome |
|---|---|
| `ed29c5a1` | Not resumable, and nothing is lost: it never wrote a transcript in any account store (it was an empty session started 10-17 19:40), and its worktree `wt-cc-193636-79736` is clean with 0 commits ahead of trunk. |
| VoiceInk | Its session is `509e3aad` (next4). Resumed as the full session into its recorded pane (kitty window 22). It was at rest, waiting on the operator's dictations, so it was not nudged. |
| `09e18eed` | Had already recycled itself at 23:00 into `9a3088f9` (pane 24, `research-kit-24`), whose brief covers the reboot and re-arming. A note about the dead watcher and the benchmark was delivered to inbox 24. |
| `64973e2f` | Its own self-close had failed to close pane 16 (`/tmp/handoff-selfclose-16-1792371087.log`: four pane-close attempts failed while claude still ran). `cc-teardown 16` closed it, verified (process gone, pane absent). |
| Local-only branches | Bundled and `git bundle verify`-ed in `~/Backups/git-bundles/2026-10-18/`: claude-infrastructure `tm2*` (11 branches), TrueMemory `tm2/2.0` + `tm2/slice`, `personal`, `reso-landing-design-research`. `tpg` (not a git repo) is `tpg.tar.gz`; macOS tar folded 6 real files named `._*` into AppleDouble metadata, so they are copied beside it in `tpg-dot-underscore-files/`, byte-compared. The Time Machine disk is simply not attached (backupd error 18); filed as backlog `f7dedfcc9cef`. |

**Why the roster missed three live panes.** `hb.roster.json` was the registry (`cc-sessions --json`) and
nothing else. TPG (pane 27), Club Vinyl (19) and VoiceInk (28) each registered at SessionStart
(`lead-crash-watchdog.log`, 10-15 and 10-16), and no other session re-registered those panes, no
SessionEnd and no `cc-reconcile` prune is logged for them, yet their rows were gone by the last tick.
They were the three oldest sessions in that kitty: every surviving row had started after 10-17 04:20,
and these three before 10-16 02:15. That matches `cc-sessions` deleting a row it judges stale once
`startedAt` is older than `CC_REG_RETAIN_H` (24 h), the one registry remover that writes no log. The
remover is not proven. The fix does not depend on it: the heartbeat now cross-checks the kitty tree it
already reads, and adds a row for any window holding a live top-level `claude` the roster lacks, with
the session named by Claude Code's own `sessions/<pid>.json` (checked against the pid's start time) or
by `--resume` in its argv.

**Why `cc-restore --after-crash` failed after the panic.** It found kitty 44163's heartbeat, but
boot-resume's event mode looks for a kitty only under the current boot's heartbeat directory and after
the current boot started, so the plan failed with "no heartbeat … nothing to restore from". Restoring
it from the old directory would be worse: the at-boot restore had already launched that fleet under
its own ledger (`events/boot-1792359242/launched`), so a second event could start a session twice.
`--after-crash` now says the kitty died before this boot, names the at-boot event and its state, and
launches nothing (`verdict=EARLIER-BOOT`); with no at-boot event it says to run boot-resume (exit 3).

**The heartbeat froze under load (found during recovery, 2026-10-19 00:20).** From 22:08 every
300 s tick logged `cc-sessions --json failed or did not parse` and wrote nothing, so a crash would
have restored a two-hour-old fleet. Load was 400-500 on 10 cores (ordinary fleet oversubscription,
kalloc.1024 at 0.59 GiB), and the census took 4 min 25 s of wall time for 2.6 s of CPU against a
fixed 30 s bound. The job already runs at utility QoS, so no band change helps. The tick now stretches
the bound with load per core (30 s up to 75 s, under cc-restore's 120 s bound on the whole tick), and
when the census still fails it carries each kitty's last roster (rows whose pid is alive) plus the
kitty-tree backfill, stamps the tick, and records `carried <tick> <last ok tick>` in `hb.census`.

## Implementation of improvement 1 (2026-10-19)

Scope (frozen): the settings template runs every hook and the statusLine through an explicit
interpreter; migration 0070 rewrites the live settings.json of all five config dirs (c10, operator
runs it); a land-gate lint refuses a bare `#!` hook command; the hottest script-to-script `#!` calls
on the hook path are converted; per-exec retention is measured for the converted helpers.

Scope (grown): readers that match hook commands by exact string now compare through one normalizer,
`cmd_bare` (`scripts/lib/hook-cmd-bare.jq`): `install.sh` (its within-event union would otherwise
append every hook a second time, measured: 2 copies of validate-bash on the pre-fix install.sh),
`scripts/settings-drift-assert.sh`, the hook-chain live-parity drift guard, and the 12 still-staged
settings migrations (0012-0069), which after 0070 would otherwise miss their own hook. The c10 batch
runs 0070 after 0024, so a hook an earlier step registers by bare path is rewritten in the same run.

What is where:

| Piece | File |
|---|---|
| rewrite + lint predicate (prefix = the script's own shebang, verbatim; an interpreter `cmd_bare` cannot strip is refused) | `scripts/hook-interp.py` |
| normalizer for string matchers | `scripts/lib/hook-cmd-bare.jq` |
| land-gate arm (fires on lands touching the template, `hooks/` or the lint) | `scripts/hook-shebang-lint.sh`, `scripts/ship-land.sh` |
| live rewrite, symlink-preserving, backup + by-content verify, idempotent | `migrations/0070-hook-explicit-interpreter.sh` |
| Stop-path `shasum` (a `#!/usr/bin/perl` script) run by perl directly | `hooks/lib/shasum-direct.sh` |

Hot-path census (no root): each hook run once under inherited xtrace (`SHELLOPTS=xtrace` from the
environment, so child bash scripts trace too) with a benign payload, every external first word
resolved and its first two bytes read. A positive control (a fixture hook calling `cc-custody` and
`cc-mail` by bare name and `cc-backlog` via `/bin/bash`) reported exactly the two bare calls.
- PreToolUse Bash (11 hooks) and PostToolUse Bash (8): **no nested `#!` exec**. The only candidate
  found by reading, `memory-index-drain.sh`'s `cc-memory-rotate`, runs only when MEMORY.md changed.
  The per-Bash leak is therefore the ~20 hook execs themselves, which 0070 converts.
- Status line: no nested `#!` exec.
- Stop (13 hooks) and UserPromptSubmit (7): `shasum` from `operator-readout.sh` (its `sha16`, six
  call sites) and `session-continue.sh` (via `hooks/lib/continue-sentinel.sh`, `dod-path.sh`,
  `origin-identity.sh`, `deadline-capture.sh`). Converted through `hooks/lib/shasum-direct.sh`.
- Not converted: 57 files call `shasum`; the rest are off the per-turn path.

Improvement 2 (one dispatcher exec instead of ~20) is not filed: once 0070 is live each hook is a
Mach-O `bash` exec that retains about 0, so collapsing them buys load, not leak, and the collapse
(`hooks/hook-chain.sh`) already has an adjudicated history (backlog `05c79abca813`).

Per-exec measurement of the converted helpers (2026-10-19, no root, throwaway inputs; live settings
untouched): interleaved, randomized arms of 150 execs each, residual = data.kalloc.1024 − cred from
`zprint` column 7 before and after each arm, fitted as Δresidual = drift·seconds + per-arm intercept.
Arms: `pr-gate.sh` by bare path vs `/bin/bash pr-gate.sh`, and `/usr/bin/shasum` vs
`/usr/bin/perl /usr/bin/shasum`. Seven cycles at mean load **598** (range 416-798):

| Contrast | Retained per exec (±1 SE) |
|---|---|
| hook: bare `#!` − `/bin/bash` | −1.5 ± 3.8 |
| shasum: bare `#!` − perl | +8.6 ± 3.8 |

**Inconclusive.** At this load one 150-exec arm took 80-440 s, fleet drift was 12.7 ± 4.1 /s, and
the per-exec SE (±3.8) is four times the effect being measured (+0.94); the +8.6 is implausibly
large for one element per exec and reads as arms of unequal duration under a moving load. The
per-exec evidence remains the 96-cycle A/B above. A decisive re-run needs load near the 09-30
carry-ab level (≤ ~200) or root (`sudo zprint` per-view, or `eslogger exec`), and is cheapest
done after 0070 is applied, as the fleet-level Δ(data.kalloc.1024 − cred)/s before vs after.

## Post-0070 fleet measurement (backlog `f0355eff46d5`)

Cutover: migration 0070 rewrote `~/.claude/settings.json` at **1792549362 = 2026-10-21 02:22:42
UTC** (settings mtime; its backup dir `hook-interp-0070-20261020212242` agrees). After it, 80 of 104
hook commands in each of the four config dirs start `/bin/bash`; before it, 2 of 104.

Instrument: `scripts/kalloc-leak-rate.sh`. It fits the zone series capacity-alarm already writes
(`~/.claude/logs/kalloc-zone-series.tsv`, one measured read per ~900 s) by least squares over 24 h
either side of the cutover, and divides each side's growth by its Bash tool calls (from
`bash-commands.log` and its rotated `.gz` siblings over the same span), because the raw rate moves
with how busy the fleet is. Verdict per Bash call: `reduced` at a ratio ≤ 0.5, `partial` below 0.8,
else `unchanged`; `insufficient` (exit 1) while a side spans under 90% of the window. The series is
raw bytes, not the `− cred` residual above; over 24 h `cred`'s rise-and-fall part averages out, and
both sides share the instrument.

Baseline, read 2026-10-21 02:30 UTC (71 rows over 23.1 h):

| Side | GiB/day | elements/s | Bash calls | elements per call |
|---|---|---|---|---|
| before | 1.66 | 20.2 | 32,181 | 52.1 |

The item's quoted ~1.1 GiB/day baseline is from an earlier boot; this boot's pre-0070 day is 1.66.
The after side completes at 2026-10-22 02:22 UTC (plus one ~900 s sample). Run then:

`bash scripts/kalloc-leak-rate.sh --cutover 1792549362`

What to expect: 24 of 104 hook commands still run by bare path, the ~570 `#!` executables in
`hooks/ bin/ scripts/` still call each other by path, and a session that was already running at the
cutover may keep the hook list it loaded at startup (not verified), so a residual floor is expected;
`reduced` is the fix working at fleet scale, `unchanged` refutes the hooks as the dominant source.

The planned reboot for macOS 15.8.1 (shutdown 2026-10-21 13:59 CDT = 18:59 UTC, boot 14:06:30 CDT,
epoch 1792609590) cut the after side at about 16.6 h, under the 90% the instrument needs, and the zone
reset with it. The after side therefore restarts on the new boot, which is post-0070 from its first
exec: read a 24 h fit of this boot's series per Bash call against the 52.1 elements/call baseline
once the boot is 24 h old (from about 2026-10-22 19:10 UTC).

## macOS 15.8.1 does not fix the per-exec leak (2026-10-21)

Measured on 15.8.1 (24H32) at load 184-389 on 10 cores, about 40 minutes after the restore: 6
interleaved pairs of 3000 execs per arm plus 4 idle arms, residual = data.kalloc.1024 − cred, least
squares with a drift term.

| Arm | per exec (elements) |
|---|---|
| `#!` leaf run by path | **1.098 ± 0.104** (fit through zero 1.120 ± 0.082; arm median 1.06, range 0.93-1.48) |
| `/bin/bash leaf.sh` | 0.007 ± 0.101 |

A first run at 300 execs per arm could not beat the drift at this load (spread ~390 elements per
arm) and is not used. The test itself left ~47 MiB in the zone until the next reboot. Raw rows and
the fit: `~/.cache/kalloc-158-ab/` (`rows-n3000.tsv`, `fit.py`).

So 15.8.1 carries no fix: the hook-interpreter mitigation and forecast reboots stay the bridge, and
the only reported fix is macOS 27 (decision `a172a41d0d79`, "upgrade to 27.0.1 now or wait for 27.2").

## Migration 0070 result (24 h, 2026-10-20 21:23 → 2026-10-21 21:23 CDT)

A second, independent read of the same cutover, beside the per-Bash-call fit in "Post-0070 fleet
measurement" above: a dedicated sampler (one `zprint` row per ~60 s, `~/.cache/kalloc-0070/`)
fitting Δ(data.kalloc.1024 − cred)/s by least squares, per boot, binned by load. Its pre-0070
baseline, 20.35/s, matches that section's 20.2/s.

**Verdict (90%): the leak halves; it does not stop.** At matched load the post-migration rate is
45-55% below the same-boot baseline, and it settles at about 9-12 elements/s (0.75-1.0 GiB/day).
Converting the hook commands (80 of 104 now start `/bin/bash`) and the status line therefore removed
about half the leak, not the dominant ~all of it that Answer §2 put at 70%. The remaining half is
not unmigrated sessions: after the reboot every session was new, and the rate stayed where it was.

| Arm | Span | Mean load | Rate | GiB/day |
|---|---|---|---|---|
| pre, boot DF7FC1FF (10-19 10:16 → 10-20 21:23) | 35.1 h | 152 | 20.35/s | 1.68 |
| post, same boot (21:23 → 10-21 14:01) | 16.6 h | 122 | 10.82/s | 0.89 |
| — first half (old sessions still running bare hooks) | 8.7 h | 159 | 11.62/s | 0.96 |
| — second half | 7.9 h | 84 | 9.42/s | 0.78 |
| post, boot DBDBC472 (15:10 → 21:23, every session new) | 6.2 h | 257 | 11.79/s | 0.97 |

Hourly slopes binned by load, pre vs post (elements/s): load 0-99 16.2 vs 9.0 (−45%); 100-199
22.4 vs 10.3 (−54%); 200-299 24.8 vs 14.3 on the new boot (−42%, and the new boot's figure
includes the restore surge). For scale: last boot's mean was 13.4/s (1.06-1.11 GiB/day), and a quiet
hour on 10-19 08:22-09:20 read about 0.75 GiB/day. The 44-53/s peaks in Answer §6 came at load
300+; the new boot ran 5-10/s at load 330-530.

What it changes:
- Forecast at ~1 GiB/day from the 10-21 14:06 boot: 14 GiB (the reboot line in improvement 4) about
  **11-04**, the ~20 GiB ceiling about **11-11**. Re-forecast from the trailing slope; a heavy week
  moves both earlier.
- The remaining half is not on the per-Bash hook path: the census in "Implementation of improvement
  1" found no nested `#!` exec there. Candidates, none measured: the 24 hook commands still run by
  bare path, `#!` scripts that sessions and daemons run directly (`cc-*` tools in Bash tool calls,
  launchd jobs, the ~570 `#!` executables in `hooks/ bin/ scripts/` calling each other off the hook
  path), and other processes on the box. An `eslogger exec` census of `exec.script != null`
  (untested item 3) would rank them.
- Untested item 1 is settled as "about half", not "dominant".

Method caveats:
- Detector. The sampler counts the migration as applied when `0070 --verify` exits 0 (or 0070's
  ledger row exists). The first brief's check (count of `/bin/bash|/usr/bin/env` hook commands
  > 0) was a false positive: at 10-19 18:36 migrations 0071 and 0012 registered two `/bin/bash`
  hooks while 100 of 102 stayed bare. Those rows were reset before any analysis.
- Gaps. 10-19 16:57-17:05 (the first detached sampler died; pre-migration only). 10-21 14:01-15:10:
  the planned reboot into macOS 15.8.1 at 14:06 (not a panic). 15.8.1 keeps the per-exec leak (section
  above), so the new-boot arm compares like with like. The sampler's launchd job does not survive a
  reboot and was relaunched. No slope is fitted across the reboot (the zone
  counter resets), so post-migration coverage is 22.9 h of the 24 h window, in two per-boot fits.
- 0070 reaches only sessions started after it, so the first post-migration hours mix bare and
  migrated hooks; the first-half/second-half split and the new boot bound that effect.
- Load is not controlled, only binned; the hourly bins hold n = 1-16 hours each.
