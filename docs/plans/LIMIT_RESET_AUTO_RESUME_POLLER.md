# Limit-reset auto-resume poller — design (build-ready, NOT yet installed)

> **STATUS: BUILT + PROVEN — activation C10-queued (2026-07-15, Track-B B1-d).**
> `scripts/limit-reset-safety-gate.sh` GREEN (LR-a..LR-i, registered RED-first); proofs in
> `tests/lr-reset-poller.bats` (10/10), suite RED-proven against the as-shipped poller. The poller
> had run ONE live notify-only cycle 2026-07-12 (PARKED 6802c9b8 → READY notified — poller.log),
> satisfying the "eyeball one cycle" precondition below. **Two real bugs found by the proofs and fixed:**
> 1. **Blind headroom guard (§3i instance):** `account_has_headroom` captured the accounts JSON into
>    `$j` but ran `python3 - <<PY` whose `sys.stdin.read()` was EMPTY (stdin consumed as program text)
>    → the except branch exited 0 on EVERY call — the guard never once observed a quota; the poller
>    WOULD have resumed into capped accounts. Caught by LR-c firing RED. JSON now piped in.
> 2. **Sid-keyed forever-skip:** `resumed/<sid>.json` blocked ALL future parking of that sid — a
>    session resumed once could never re-park on its NEXT limit (fatal for multi-day endurance, where
>    the 5h limit recurs every window). Now EVENT-keyed (LR-i): a newer reset REPARKs; the same event
>    never double-fires.
>
> **THE DECISION (resolved, zero-HITL agent-default):** notify-first-then-flip was the proposed default;
> the notify-only live cycle has RUN (2026-07-12). The flip to auto-fire is an ACTIVATION, hence C10:
> the operator installs the plist + sets `LR_POLLER_AUTOFIRE=1` via the consolidated `/tmp/wiring-all.sh`
> bundle (hand-steps printed, never agent-run). Recency window stays 48h; limit types: session/weekly
> proven; fable-scoped message shape is a DECLARED blindness (no real capture exists — covered by the
> weekly prefix if it matches, else by the supervisor stall page; fixture-ize on first real capture).

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

## 2026-07-18 addendum — teammate sessions are SKIPped (lead-owned recovery)

Incident (team `session-44f5331d`): an Agent-Team wave's assignee sessions 429'd on the
monthly-spend cap mid-wave. Assignee transcripts match the poller's limit pre-filter, but a bare
`--resume` of a teammate would detach it from team semantics (inbox/agentName wiring) and duplicate
the lead's respawn. The poller now skips any transcript whose head carries `"agentName"` (teammate
marker; leads never have it), logs `SKIP <sid> — teammate session (lead-owned recovery)` once
(marker: `~/.reso/limit-recover/teammate-skip/<sid>`), and leaves recovery to the team-aware
`lr-audit.py` (per-member verdicts + `salvage/teams/<team>/<member>.json` verbatim respawn briefs
— see `/limit-recover` § Teams). Regression: `tests/lr-team-audit.bats` test 3; LR-a..LR-i stay GREEN.
