# Lead findings — wave 2 (detection + identification + surfacing), 2026-09-19

Lead session 7f533f05 (next4, Fable 5.1 xhigh, pane 150). Predecessor: 11569d45 (pane 127, next3) —
limit-killed at 19:53Z after its research workflow wf_d48f0e74-15e returned 14/14 research units,
3/3 designs, 8/9 critiques and a NULL synthesis (the synthesize slot itself died on the cap). Its
artifacts are copied to ../lr/ (research/, design/, critique/, cc-find-full.sh, timeline.txt).

## Measured this session (receipts inline)

- `lr-fleet.sh --locate` = **35.5 s wall** (real 35.46 user 18.03 sys 18.83) over 2,591 transcript
  files (.claude and .claude-next are ONE store enumerated twice: 422+422; secondary 625, tertiary 611,
  quaternary 512; ~4.3 GB). Scan-only pass (tail -c 20000 + 2 greps per file) = **10.0 s**; the rest
  is per-hit forks (python ×3 + jq ×37×3 + ps) ≈ 1 s per hit × 20 hits. mtime<8d population = 414
  files; registry-live sids = 32.
- Prototype `cc-limited-proto.py` (markers ∪ parked ∪ registry ∪ beats ∪ 128 KB tail of the NAMED
  transcript only, one python process) = **0.07 s cold / 0.05 s warm** and grouped the same instant's
  fleet correctly: next3 8 blocked (6 RECOVERABLE with pane ids 122/124/127/140/147/149, 1
  TRANSPLANTED 09e64dcb [lock], 1 MOVED 65186f1f [transcript renamed since --locate ran]); next4 6
  (4 MOVED at 19:43Z, 2 RESET-PASSED/NO-PANE). Ratio ≈ 500×.
- **StopFailure fired on every one of today's 10 rate_limit deaths within ~1 s**: IDL
  (`~/.claude/autonomy/idl.jsonl`, hook=stop-failure-marker) rows at 19:28:05/19:28:09 (next4:
  fff83638, 0e2567ee) and 19:52:33 … 20:29:28 (next3: 98f02458, 09e64dcb, 11569d45 ×3, 65186f1f ×2,
  8843bcf3, 4bc1159f, 26cd14be, 07e30aeb); markers in `~/.claude/autonomy/stop-failure/rate_limit__next3.jsonl`
  (12 lines) and `rate_limit__next4.jsonl` (14). 28 IDL rows today. Zero consumers of the marker dir
  (grep: only hooks/config-mirror-assert.sh + scripts/growth-coverage.conf).
- Stop does not fire on a limit turn ⇒ beats stay `kind:"prompt"` (fff83638 beat t=19:28:04 kind=prompt,
  1 s before its error record); cc_sp_active counts them as mid-turn (memory
  reference-a-limit-killed-session-is-a-phantom-mid-turn).
- Record shape (2.1.260): `error:"rate_limit"`, `apiErrorStatus:429`, `quotaLimits:{status,resetsAt
  (epoch), unifiedRateLimitFallbackAvailable, rateLimitType, overageStatus, overageDisabledReason,
  isUsingOverage, lowPriorityOffer, lowPriorityRetryAfterSeconds, lowPriorityMaxWaitSeconds}`.
  Corpus: rateLimitType five_hour ×206, seven_day ×22 (weekly record 2026-09-14T15:28:43Z has the full
  block). **Fable-scoped cap (7193ec2b, 2026-09-10T17:58:36Z, 2.1.260): `quotaLimits: null`**, error
  rate_limit, 429, text "You've reached your Fable limit. Run /usage-credits to continue or switch
  models with /model." — structured-first classification MUST keep a text fallback. monthly_spend:
  no record found in any store (unmeasured).
- Predicate copies: lr-fleet.sh LIMIT_RE (has Fable 'reached'), lr-lib.sh lr_tier_from_transcript
  ('hit your'|'reached your'), lr-reset-poller.sh:746 `You've hit your (session|weekly) limit` (NO
  Fable arm — blind), :566 SPEND_RE, lr-audit.py LIMIT_PREFIXES (session|weekly|monthly_spend, NO
  Fable), limit-reset-safety-gate.sh. Four+ copies, drifted.
- Poller today: PARKED all 8 next3 sessions within 10-25 min of death (19:54:10 … 20:35:06Z); PARKED
  next4's two at 19:32Z (4 min after death); at 19:43Z (after the 19:40Z reset) logged
  `RESUMED 0e2567ee … (autofire, gui) — pane opened` and `RESUMED fff83638 …` — **FALSE GREEN**: IDL
  `capacity-admit refused` at 19:43:36Z and 19:43:49Z (3 s / 2 s after each line); transcripts have
  0 `source=resume` SessionStart records after 19:43Z, end on a zero-usage cost-state; registry rows
  143/145 still carry the ORIGINAL pids (lstart 19:27, dead); kitty windows 143/145 no longer exist;
  `resumed/<sid>.json` written. Two sessions abandoned with no alarm — the class the operator named.
- `poller.launchd.err` "account-map.generated.sh: line 21: syntax error" + "cc_acct_name_for_dir_basename:
  command not found" is HISTORICAL (file mtime Sep 15 19:48; both copies pass `bash -n` now). Not live.
- statusline: copy-deployed real file (`~/.claude/statusline.sh`, not a symlink); renders no pane id /
  sid; payload carries session_name + rate_limits (unread). kitty titles ('✳ <ai title>') are the
  human key: 121 Subagent lifecycle root cause implementation · 147 Bottle image review for Studio60
  menu · 140 W1b floor-plan first frame soft nav · 111 API key export silver platter · 127 /limit-recover
  optimization and investigation · 124 Kitty Terminal split pane auto-even on move · 122
  reso-management-app worktree sync strategy · 149 Weekly limit exhaustion display.
- session-index.db: source=session-start 617 rows, 508 with EMPTY first_prompt — keyword path is a stub
  for live sessions (U07 confirmed).
- Marker transcript_path is a SNAPSHOT: 65186f1f's marker path no longer exists (renamed
  .handed-off after transplant); a census must re-resolve via registry/locks/tombstones.

## Operator's verbatim framing (to the predecessor, 11569d45), preserved
"…attaching a screenshot of the halted session should be relatively instant to look up via ID (is
this clear enough from the status line branch, or do we need to adjust our 'limit reached' command
from Claude Code to attach a session ID with it?) or keyword search, and then it should be one
command pretty instant to identify that session and pane, and self-recycle it into a new appropriate
account in place? … 100.00/100.00 … latency, time, and token usage, and reliable fault-tolerant (ie.
if something goes wrong along the way, can we easily identify it instead of fire-and-forgetting and
having abandoned sessions not restarted?)"
And to this session: "identify all sessions that need to be limit recovered without having to
screenshot image each session one at a time (usually multiple sessions at once are limited from the
same account)".

## Wave-2 workflow
wf_b0f2a31c-e7d (this session): Refute P1-P10 → Design Da/Db/Dc (blind) → Judge 3×3 → Synthesize →
Critic. Outputs under this directory (P*/receipts.md, D*/design.md, SYNTHESIS.md, CRITIC.md).

## Ingest findings — the transplant of THIS session (next4 → next3, 22:30Z), measured from the target side

Three defects observed on my own recovery, each a live instance of a class the research already names:

1. **`lr-audit` misclassifies a SETTLED run's dead slots as `UNSETTLED-INFLIGHT` during ingest.** The
   audit reads "lead process: IN-FLIGHT" because the ingest turn itself is mid-turn (pids 17221 = the
   dead source, 41639 = me), and inherits that onto all 10 dangling slots of `wf_b0f2a31c-e7d` — yet
   the run had ALREADY settled: the `<task-notification>` (`agents_error 10`, status `completed`) is in
   the transcript and every dead agent's jsonl ends on the weekly-limit api-error record. The verdict
   table's "NONE — do not touch" would have parked a resume the evidence licences. Fix: a run whose
   task-notification has arrived is terminal regardless of lead liveness; the wait-verdicts should
   only apply to runs with NO notification record. (Also: the audit counted the SOURCE pid 17221 as a
   live lead — it is a tombstoned husk, see 2.)
2. **The in-place recovery degraded to a spawn, left a live husk, and the successor is unregistered.**
   MANIFEST says `in_place: true, source_pane: 150`; I am in kitty window **186** (title
   `recover-7f533f05`), rooted `kitten run-shell → bash (6-attempt loop) → lr-fire-resume.sh → expect
   → cc-close-attrib → claude` — the expect-rooted, non-recyclable shape U02/U03/U08 describe. Pane
   **150 still holds pid 17221** (next4, argv opus-5, 3h07m, tombstoned `.handed-off`) — a live husk
   with no alarm (U04's silent branch). My claude sits on expect's pty **ttys043** while window 186's
   tty is **ttys042**, so `self-close --transplanted-source --successor 186` cannot pin me
   (`successor_pin` reads the pane's own tty) — the same refusal the tmux-nested successor hit on
   2026-09-09. And **no registry row existed for 186**: expect launched claude with no
   `ITERM_SESSION_ID`/`CC_PANE_ID`, so `session-register.sh` had no address (memory
   `reference-a-relaunched-pane-has-no-address-until-registered`). I registered it by hand
   (`ITERM_SESSION_ID=w0t0p0:186 … session-register.sh` → row written, pid 41639). No fleet
   `results.tsv` row and no `fleet-drive-ledger` row names this recovery — the driver's receipts are
   only the bundle + `lr-launch-7f533f05-jhty8B.sh`.
3. **`claude-accounts` is not on PATH in an expect-launched session** (`command not found`; PATH lacks
   `~/bin`). `commands/limit-recover.md` § recover step 1 says "resolve the binary from PATH, not
   ~/bin" — wrong in exactly the launch shape a recovered session has. The repo path
   `~/Development/claude-infrastructure/bin/claude-accounts` works.

Headroom at fire time (repo binary): next3 5h 9% · weekly 36% · fable 40% · k=9. next4 weekly 100%
(reset 2026-09-20T09:00Z). Resume fired 22:4xZ as task `wnzwqwrl3`, same run id, prefix intact.

### Husk retirement attempted (22:4xZ) — refused by the successor-pin gate
`handoff-fire.sh self-close --transplanted-source --source-pane 150 --source-session 7f533f05… --successor 186`
→ rc 3: *"successor pane 186 resolves to session 7f533f05 (pid 41639) and THAT process is gone — or no
longer owns tty /dev/ttys042"*. Pid 41639 is alive; it owns **ttys043** (expect's pty), and
`successor_pin` (handoff-fire.sh:3435) reads the PANE's tty. Every successor `lr-fire-resume.sh` spawns is
expect-rooted, so **a replaced source can never be retired through the sanctioned path when its
successor came from lr-fire-resume** — the poller hits the same gate. Filed as an operator `cc-do` row
(close window 150). Recovery-chain defect for a LATER wave: `successor_pin` must accept a registry-bound
pid whose controlling pty is a child of the pane's tty (expect/tmux nesting), never a raw close.
