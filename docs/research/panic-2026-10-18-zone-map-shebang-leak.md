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
