# Limit-reset auto-resume poller — design (build-ready, NOT yet installed)

**Gap (from the 2026-07-11 investigation):** a Claude session that hits a 5-hour / weekly /
Fable-weekly limit stays **idle forever** — nothing watches reset times and re-fires it. The
`resume-sessions` keepalive only nudges idle panes of *running* sessions; `lr-audit.py` parses
`resets_at_utc` but nothing schedules off it; no launchd job is limit-aware. (Monthly-spend/credit
caps have NO reset time — out of scope; those need `/usage-credits`.)

**Why feasible now:** the autonomous-resume source fix (`lr-preseed-env.sh` — iTerm2 scrollback
modal + folder-trust pre-accept, see memory `reference-limit-recover-autonomous-resume-preseed`)
makes an unattended `lr-fire-resume` prompt-free. Validated 4/4 cross-account resumes 2026-07-11.

## Design
1. **`lr-reset-poller.sh`** — launchd job, every ~10 min (`StartInterval 600`), kill-switch
   `LR_POLLER_DISABLED`, everything logged to `~/.reso/limit-recover/poller.log`.
2. **Detect** limit-parked sessions (the crux): for each account config dir, take transcripts
   `-mtime -2` whose LAST event is a usage-limit `isApiErrorMessage` (reuse `lr-audit.py`'s
   `RESET_RE` + limit classifier — do NOT hand-roll). Skip if a `resume <sid>` process is already
   live. Parse `reset_at_utc`.
3. **Ledger** `~/.reso/limit-recover/parked/<sid>.json` = {sid, cfg, cwd, reset_at_utc, parked_at,
   prompt}. Idempotent: on resume, move to `resumed/<sid>.json` so it never double-fires.
4. **Resume** when `now >= reset_at_utc` AND `claude-accounts --json` shows that account has
   headroom (never resume into a still-capped account): `lr-fire-resume.sh <acct> <cwd> <sid>
   --prompt "<continue/ingest>"` — headless, autonomous.
5. **Guards:** recency window (default 48h — never auto-revive an abandoned session); per-run cap
   (≤N resumes/tick); `--dry-run` (log only). Fail-open, never crash the daemon.

## THE DECISION for the operator (why this isn't auto-installed)
- **Auto-fire vs notify-first.** Auto-fire = true "no human in the loop" (the stated goal) but
  spawns sessions unattended. Safer v0 = detect + `cc-notify` "session X reset — resume?" and only
  auto-fire once trusted. **Default proposed: NOTIFY-first for one cycle, then flip to auto-fire.**
- **Recency window** (48h default) and **which limit types** (5h/weekly/Fable — all have resets).
- **Runaway guard**: a detector false-positive could re-spawn the wrong session; the recency window
  + idempotency ledger + per-tick cap + log-first bound it, but the operator should eyeball the
  first live cycle's log before enabling auto-fire.

## Files (to build)
`scripts/limit-recover/lr-reset-poller.sh` · `~/Library/LaunchAgents/com.reso.lr-reset-poller.plist`
· wire the kill-switch + log rotation into `install.sh`.
