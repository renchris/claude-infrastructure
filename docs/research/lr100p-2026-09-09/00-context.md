# LIMIT_RECOVER_100P research wave — shared context (lead-verified facts, 2026-09-09T02:00Z)

Plan: docs/plans/LIMIT_RECOVER_100P.md (read it first). Worktree: /Users/chrisren/Development/.worktrees/lr100p (branch lr100p).
Terminal: the fleet lives in KITTY. A "pane id" is a kitty window id (integer); the login shim synthesises
ITERM_SESSION_ID="w0t0p0:<KITTY_WINDOW_ID>" so the it2 shim (bin/it2-kitty) drives kitty via `kitty @`.
Clock now: 2026-09-09T01:55Z. Local box TZ = CDT (UTC-5). Registry `lstart` fields render in UTC.

## Live state (measured by the lead; do NOT act on any of these panes — read-only research)
- Windows 615 and 618 (the two husks in the plan) are GONE from `kitty @ ls` — closed after the plan was written.
- Pane 616 = session 52e35019 (next2/.claude-secondary). Root process pid 79094 = `/bin/zsh -l` (SHELL-ROOTED).
  claude pid 80874 (argv has NO --resume: it was a fresh launch), registry row ~/.claude/cc-registry/616.json names it.
  It hit the 5h limit at 23:09:09Z and again at 23:57:29Z when a queued task-notification was SUBMITTED and RAN a
  turn while blocked (transcript shows queue-operation → user → assistant isApiErrorMessage). So the TUI input+turn
  loop is alive in the limit-blocked state.
- At 00:51:50Z the reset poller (launchd, autofire) RESUMED 52e35019 "on next2 (autofire, tmux)": tmux session
  `lr-resume-52e35019`, expect pid 76500 → claude pid 77720 `--resume 52e35019` on ttys045. The transcript from
  00:51:53Z on is written by THAT process (CC logged "Remote Control not started here · another Claude Code on
  this machine (started 3h ago) already has Remote Control for this conversation"). Pane 616's TUI is now a
  SAME-ACCOUNT husk with no tombstone; typing into it would fork the session. The poller could not see 616's
  process because its liveness test is `pgrep -f "resume $sid"` (lr-reset-poller.sh + lr-select.py is_running)
  and 616's argv carries no --resume.
- Same shape for 0edc7e64: pane 630 (registry pid 63284 alive) AND tmux `lr-resume-0edc7e64` (claude 76781).
- SEVEN tmux `lr-resume-*` sessions are alive (Aug 29: 94d58849, 609597db, 9e3074fc; Sep 5: 1bd8904c, 3c4bdc06;
  Sep 8: 0edc7e64, 52e35019), 325-813 MB RSS each, invisible to the operator. Cause: lr-reset-poller.sh
  spawn_gui() requires $KITTY_WINDOW_ID in its own env (a launchd job has none) and falls through to spawn_tmux;
  lr-handoff.sh got the cc-kitty-socket daemon-context dispatch on 2026-08-07 (see its "DAEMON-CONTEXT DISPATCH"
  block), the poller did not.
- Panes 625 (b418b97a→next3) and 632 (6e29fee9→next4) were fired by lr-handoff.sh: kitty launched
  `-- /bin/bash <launcher>` whose last line is `exec expect …`, so their ROOT process is expect (pids 15577/17632,
  ppid 1427 = kitty). pane_shell_root → no. A /exit typed there closes the WINDOW (kitty closes a window when its
  launched process exits) — see handoff-fire.sh recycle_fire's SURVIVABILITY GATE and the 2026-08-26 pane-32 strand.
- Tombstones: b418b97a and 6e29fee9 have `<sid>.HANDOFF.json` beside the retired transcript in .claude-secondary
  plus locks in ~/.reso/limit-recover/locks/. 52e35019 has NONE (never transplanted).
- Accounts now (claude-accounts --json): next 5h=11 wk=25 · next2 5h=25 wk=58 · next3 5h=2 wk=20 · next4 5h=14 wk=21.
  There is currently NO limit-blocked session anywhere. A live limit cannot be manufactured.

## Mechanism facts (verified in source)
- handoff-fire.sh --recycle (recycle_fire, ~:10202): resolves the pane's tty (as_tty_classified), requires
  pane_cc_state=cc, SURVIVABILITY gate (pane_shell_root must not be `no`), COMPOSER gate (recycle_composer_gate:
  refuses /exit over a held draft — /exit into a non-empty composer MERGES with the draft), detaches a
  session-detached `__recycle` watcher (:5696) that pane_proofs the pane, ps-polls the tty until pane_cc_state=shell
  (≤600 s, CR/retype nudges @60/150/300 s, vanish check), then it2_type_verified's the relaunch CMD into the shell
  (bracketed paste + echo-verify + CR), waits for claude on the tty, then verifies ENGAGEMENT (recycle_engaged:
  registry ROW-CHANGE / marker). The FOREGROUND types /exit via as_write (it2 shim `session run` = kitty send-text)
  only after the watcher's heartbeat + pane proof. CMD shape (:8982-9143):
  `cd <dir> && <launcher> <flags> "$(cat <prompt-copy>)"`.
- Ownership gate (verify_self_pane :1782, pane_ownership :1718): on kitty a pane is MINE iff `kitty @ ls`'s launched
  pid for that window is an ancestor of the calling process. An EXPLICIT --session-id that is not mine is REFUSED
  (caller bug, no repair); a DEFAULTED id is corrected to own_pane_id. `unknown` proceeds. Both --recycle (:7870)
  and self-close (:6446) consume it. Protects the 2026-07-30 c5f80b8b incident (memory handoff-succession-legibility).
- self-close already has a REMOTE form that REPLACES the ownership gate with a registry binding:
  `self-close --source-pane P --source-session S --transplanted-source --successor N` (:6288-6440): the row
  ~/.claude/cc-registry/P.json must carry session_id == S; plus the transplanted-source class needs the tombstone
  (handed_off_to ≠ the source config dir), the split-brain lock still held, a live --successor (never --terminal).
  Tests: tests/handoff-selfclose-transplanted-source.bats (remote: cases from :481). lr-handoff.sh --close-source
  --source-pane P uses it (advance check :185-220, close after the fire).
- lr-transplant.sh: copies <sid>.jsonl + <sid>/ dir to the target config dir (same uuid), sha-verifies, writes lock
  ~/.reso/limit-recover/locks/<sid>.lock {sid,from,to,ts,pid,host} and tombstone <src-dir>/<sid>.HANDOFF.json
  {handed_off_to,target_transcript,ts,lock}; renames the source to .jsonl.handed-off UNLESS
  CLAUDE_CODE_SESSION_ID == SID or --keep-source. A live CC keeps appending by PATH and re-creates <sid>.jsonl in the
  retired store (2026-08-16 incident) — hooks/handed-off-session-guard.sh (UserPromptSubmit, exit 2) is what stops
  a husk taking prompts: it acquits the TARGET (transcript under handed_off_to, or same ACCOUNT via the
  .claude/.claude-next mirror) and blocks the SOURCE. lr-fire-resume.sh lr_tombstone_verdict (:166) refuses a resume
  on any account other than the transplant target while the successor transcript exists (exit 3, --force-split
  overrides); tests/lr-resume-tombstone-guard.bats pins it.
- lr-fire-resume.sh: `<account|cfg> <worktree> <sid> [--prompt P] [--model M] [--effort E] [--branch B] [--summary]
  [--force-split]`; runs lr-preseed-env, the tombstone verdict, resolves the claude binary, calls cc_capacity_admit
  (exit 9 on refusal; budget-released after CC_ADMIT_BUDGET consecutive refusals), then `exec expect` which spawns
  `env … CLAUDE_CONFIG_DIR=$cfg $bin --permission-mode auto --model $model --effort $effort --resume $sid` and
  answers the resume menu / injects --prompt with a verified submit.
- lr-reset-poller.sh (launchd com.reso.lr-reset-poller, StartInterval ~600 s, autofire on): §1 parks limit-hit
  sessions (lr-audit over transcripts) into ~/.reso/limit-recover/parked/<sid>.json {sid,acct,cfg,cwd,kind,
  reset_at_utc}; §2 at reset: lr-select consolidation (one per worktree), `pgrep -f "resume $sid"` liveness,
  account_has_headroom, MAX_PER_RUN, mints /tmp launcher `exec lr-fire-resume.sh <acct> <cwd> <sid> --prompt
  /limit-recover`, spawn_resume: gui (kitty os-window if $KITTY_WINDOW_ID set; else iTerm2 osascript) → tmux.
  It has NO tombstone awareness (relies on lr-fire-resume refusing) and deliberately SKIPs teammate sessions.
- scripts/lib/capacity-admit.sh: cc_capacity_admit <caller> <what> → 0/9, terms: 1-min load/core vs 2.0
  (CC_ADMIT_MAX_LOAD_PER_CORE), headroom GB, compressor segment %, ACTIVE session ceiling (CC_ADMIT_ACTIVE_CEILING 8,
  reserve 1); a refusal CHARGES a per-caller budget (CC_ADMIT_BUDGET, 3) and the next evaluation ADMITS + pages.
  Today it refused a resume at 161/10.
- Auto-mode classifier (memory auto-mode-classifier-denies-acting-on-a-live-session, 2026-09-04): from a session's
  Bash tool it DENIES `kill <claude pid>`, `cc-teardown <pane>`, and a cc-notify telling a peer to /exit — the
  boundary is "the TARGET is a live Claude session", not the verb. `kill` of a watcher was allowed; the originator
  reports `kitten @ close-window` on husk windows 627/628 ran with no prompt. A LaunchAgent has no classifier.
  Repo-side: hooks/validate-bash.sh has its own denies (read it).
- Operator ruling relayed 2026-09-09 by the firing session: question 3 of the plan is a REQUIREMENT — a fleet
  recovery must retire a provably-retired source pane ITSELF (tombstone present and/or the guard already blocking
  its prompts is the proof) while keeping the ownership gate for a LIVE session; and the design cannot rely on the
  driver closing panes that still host a working TUI (the classifier wall).

## The lead's working design sketch (critique it; do not assume it is right)
ONE actuator, `scripts/limit-recover/lr-recover-inplace.sh <sid> --target <acct|auto>`, callable by the poller
(launchd, no classifier, no pane) and by `/limit-recover fleet` from a driver session:
 1. bind pane P ↔ sid S by the registry row (like the remote self-close), pid alive on P's tty, pane_cc_state=cc;
 2. transplant S to the target (lr-transplant, writes lock + tombstone) → S is now PROVABLY retired at P;
 3. if P is SHELL-ROOTED: remote recycle = type /exit into P (composer gate first), watcher waits for the shell,
    types `lr-fire-resume.sh <target> <cwd> <sid> --prompt '/limit-recover ingest <bundle>'` (NOT exec'd, so the
    shell survives for the next recycle), verifies engagement → SAME window id, same uuid, new account;
    if P is LAUNCHER-ROOTED (expect): REPLACE in place = `kitty @ launch --type=window --location=vsplit
    --next-to id:P` a shell-rooted successor running the resume, verify engagement, then close P (a husk by then);
 4. sequence N sessions one at a time, engagement-gated, waiting on a NON-charging capacity read (never spend the
    3-refusal budget); 5. report: per session → pane before/after, account before/after, verdict.
Poller reconciliation: liveness by REGISTRY row + live pid (not pgrep --resume); parked records with a tombstone
are retired as TRANSPLANTED; at reset with the original pane alive → NUDGE in place, never spawn; spawn only when
the pane is gone, and then into a VISIBLE shell-rooted kitty window (cc-kitty-socket dispatch), never tmux while a
kitty is live. /limit-recover fleet = audit → plan → enqueue requests (~/.reso/limit-recover/requests/) → kickstart
the poller (or run the actuator directly when the classifier permits) → wait for per-request results → report.
