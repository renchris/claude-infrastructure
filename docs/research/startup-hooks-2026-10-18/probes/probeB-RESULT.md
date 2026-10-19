# Probe B: migration 0012 (mailbox-wake-arm on Stop, asyncRewake), Wave 6.4

Date 2026-10-19. Binary 2.1.293 (`cc-claude-bin`). README §2 row #20; A9-beyond-startup.md R3, its skeptic verdict and §6 Q1.

**Recommendation: apply 0012 as fixed in this change. Conviction 78%.** The old script was unsafe on today's fleet layout, so it was rewritten (same commit as this doc, so the two cannot drift) to the 0068 contract and stays staged, unapplied. Apply with:

`bash ~/Development/claude-infrastructure/migrations/0012-mailbox-wake-arm-stop-rearm.sh --confirm settings.json`

| Question | Answer | Conviction | Evidence |
|---|---|---|---|
| (1) Does a Stop-registered asyncRewake hook defer /goal evaluation on 2.1.293? | **No.** | 85% | static read below; fleet scan; a live scratch probe is not possible (below) |
| (2) What would the old 0012 do to the shared settings.json? | Happy path: one correct write, links intact, but a bare `#!` command. **If the first write fails: forks all four accounts.** | measured | `probeB-evidence/0012-{happy,first-fails}.txt` |
| (3) Watcher polling cost | **≈ +30-34 forks/s** at today's fleet size, about half the skeptic's +60 | estimate | below |

## (1) /goal deferral

**Static (binary 2.1.293, read with `grep -aobF` offsets and Python byte slices).** After the Stop hooks run, the goal check-in timer is armed with `getDeferringTasks:()=>xa(j.all())`, where `j` is the session's **task registry**: `function xa(e){return Object.values(e).filter((o)=>!_u(o)&&!(o.type==="local_agent"&&o.agentType==="main-session")&&(zAn(o)||har(o)))}`. The deferral messages ("evaluation has been deferred … because background work is still running") list `local_bash` shells and agents taken from that list. An asyncRewake hook never enters it. In the hook runner, `if((e.async||e.asyncRewake&&so)&&!_e)` hands the process to `PVe(...)`. For `asyncRewake` that function adds the hook's promise to a module-level set (`xrn()`) and returns `true` *before* `r.background(e,{skipSpill:!0})`, the call that registers a background task (a plain `async` hook does reach it). `xrn()` has exactly three references in the binary: its definition, `PVe`, and `d3r()`, which is the headless-exit flush that waits up to 30 s for pending rewake hooks (the cost 0012's header already states). Nothing on the goal path reads it.

**Fleet corroboration (read-only, `probeB-goal-fleet-scan.py`, `probeB-evidence/goal-fleet-scan.txt`).** Every session has run migration 0007's asyncRewake birth watcher on SessionStart since August. Of 124 sessions with a `goal_status` record in the last 48 h, 7 recorded 23 real (`met:false`) evaluations inside the first 4 h and before any mail wake, when their birth watcher would still have been running. Arming is not logged per session, so this corroborates the static read without proving it.

**Why no live probe.** In a scratch config with no credentials (the only kind the constraints allow), the `/goal` turn fails on authentication, Claude Code clears the goal ("Goal cleared after an unrecoverable error (authentication failed)"), and no Stop hook runs (`probeB-evidence/goal-unauth-control.json`: the Stop marker hook never fired). Both arms would look the same, so the rewake arm was not run. A discriminating live run needs a logged-in config, which would mean using a live account's credentials.

## (2) What the old script did to the one shared file

Run in a scratch HOME on a copy of today's `~/.claude/settings.json`, with four account dirs symlinked to it as on the live fleet (`probeB-0012-shared-file.sh`):

- **Happy path.** It registered once in `~/.claude/settings.json`. Each symlinked dir then read the same file through its link and reported "already registered". Links intact, one backup. However, the entry is the bare `~/.claude/hooks/mailbox-wake-arm.sh`: a `#!` exec at every turn end in every session, the kernel-memory leak migration 0070 removes. The c10 batch runs 0070 last and would have rewritten it; a standalone run would not.
- **First write fails** (here, `~/.claude` made read-only, so the backup `cp` fails). The loop `continue`s to `~/.claude-next`. That file reads as unregistered through its link, so the script backs it up in that dir and `mv`s a temp file over the **symlink**. Every account dir ended up as a separate real file with the hook, `~/.claude` without it, and rc 1: a silent fork of the fleet that 0037 exists to prevent.

The script also had no `--confirm` gate (a bare run applied) and no forked-fleet refusal.

**Fix (this change).** 0012 now follows `migrations/0068-ssd-timeout-20.sh`: `--dry-run | --check | --verify | --confirm settings.json`; it resolves the one real file, refuses when `cc-settings-parity check` fails (exit 3), backs up to `~/.claude/backups/`, writes the real file once via a temp file in the real file's dir, and verifies by content (exactly one entry, `asyncRewake:true`, and the document otherwise unchanged). It registers `/bin/bash ~/.claude/hooks/mailbox-wake-arm.sh`. Both readers of the registration (`session-continue.sh` `wake_arm_on_stop_registered`, the header's verify) match that spelling. Preconditions (live hook, claim guard, asyncRewake in every installed binary) are unchanged. `tests/mailbox-wake-arm-migration.bats` runs the 0012 cases on the shared layout: 25/25. The new "never writes through a symlink" test is red against the pre-fix script (replayed from `origin/main`).

## (3) Watcher polling cost

Measured now (read-only `ps`, 2026-10-19 ~15:55Z): **42** `claude` processes, **13** `cc-await-ping` watchers, **all 13** waiting in `cc-kqwait`. The skeptic's +60 forks/s was `(46 − 15) × 31 / 15`: a 31-process poll body every 15 s (`docs/research/load-root-cause-2026-10-17/C-session-daemons.md` §2). Since W4 R2 (2026-10-17) the watcher waits on kqueue and runs that body on each event or on a 30 s heartbeat. So a watcher costs about 31-35 / 30 ≈ **1.0-1.2 forks/s** plus one body per mail or turn event. With 0012 the fleet tends toward one watcher per live session: at most +29 watchers, **≈ +30-34 forks/s** [E]. The 42 counts every `claude` process, including any headless ones the subject's own guard skips, so it is an upper bound.

Against that: README row #20 measured −174 to −180 forced WAKE FLOOR turns and −258k to −263k block chars per 48 h, plus most of the per-prompt "no watcher armed" nags. The 78% is the net of that benefit, the fork cost, and the remaining 15% uncertainty in (1).
