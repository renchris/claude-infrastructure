# D1-zero-touch — fault-tolerance critique

Critic lens: fault-tolerance. Read: `design/D1-zero-touch.md` (810 lines), `research/U01–U14`, and the
repo at `/Users/chrisren/Development/claude-infrastructure` (cited `file:line`). Every claim is
`file:line`, a research unit section, or `<command> => <output>`; anything else is labelled GUESS.
Read-only: no file outside `scratchpad/lr` was touched, no pane was written to, no process signalled.

---

## 0. Verdict

D1 is right about where today's 98.7 minutes went and its S0–S2 arms (StopFailure request, WatchPaths
wake, claim-by-rename, load-term-off + admission token, `relaunch.rc`, the IDL join on the
`no claude process` branch) close the four PARTIAL husks and the 658 s park. **Where it fails the lens
is the back half: the design's whole fault-tolerance promise (§10's invariant, R7, R8) rests on a
reaper that (a) runs inside the drain it is supposed to bound, (b) reads exactly one store and
re-drives automatically on whatever that store's last line says, and (c) pages a role that is dead
on this box.** Those three together turn a false-negative verdict — and D1 has at least two cheap ways
to produce one, one of which replays pane 112 exactly — into an automatic `/exit` of a working session
followed by three re-drives and a `needs-human` page nobody receives. Separately, S4's failure
semantics are self-contradictory (`exit 12` with the TUI alive is unreachable from `lr-fire-resume`'s
tail), and the auto-remedy for the class that cost the most manual time today (an unsubmitted prompt,
17.1 min on pane 111) names a mode that has no component. The irreversible-first ordering
(transplant before any pane read) survives unchanged, and the design mis-describes its consequence
("session untouched") for every foreground refusal after the tombstone.

None of this is fatal to the architecture; each has a small fix. But as written, D1 would meet R8
("0 unrecorded husks; every recorded one re-driven automatically") only on the path where nothing
goes wrong after the transplant.

---

## 1. Step enumeration — what fails or hangs, is it VISIBLE, is it RE-DRIVABLE, what is the silent outcome

Legend: VIS = a state row / alarm with an owner exists for this failure as designed; RD = the
design re-drives it from this step; SILENT = what happens with no human watching.

| # | step (D1 ref) | failure / hang | VIS | RD | outcome as designed |
|---|---|---|---|---|---|
| S0.1 | StopFailure hook, arm 1 marker | hook killed by its 10 s timeout (`settings.json` StopFailure `timeout:10`), or `jq` absent | no (a SIGKILL writes no IDL row) | no | marker + request absent; poller DETECT parks at ≤600 s ⇒ **wait-for-reset, 2h40m** (U06 §1). §10 row 1's "IDL abstained" exists only on the surviving path |
| S0.2 | teammate test (`agent_assignee_argv` ∨ `agentName`) | StopFailure inside an assignee is UNMEASURED (U10 §3c: 0/10) | file `teammate-skip/<sid>` | lead's ingest only | acceptable and honest (§16) |
| S0.3 | latch `set -C requests-latch/<sid>.<uuid>` | taken, then the hook dies before the write (see R6) | no | **no — the latch blocks the retry** | request never written for that death uuid ⇒ S0.1's fallback |
| S0.4 | `jq … > requests/<sid>.json` (non-atomic) | reader sees an empty/partial file | `REQUEST-SKIP … malformed` log line only | no | `lr-reset-poller.sh:650-651` MOVES it to `results/<sid>.malformed.json`; the latch prevents a re-request ⇒ S0.1's fallback |
| S0.5 | `kind:"limited"` beat | beat write fails | no | n/a | session stays counted mid-turn ⇒ `active`/`reserve-active` refusals ⇒ `PARKED:capacity` + page after 120 s (visible, delayed) |
| S0.6 | `launchctl kickstart` (no `-k`) | job not loaded ⇒ rc≠0; job running ⇒ EALREADY (GUESS, recalled from launchctl(1), not measured) | not recorded by the hook | n/a | request sits in `requests/` until the next tick or forever; the only external check of "loaded" is a lint (`scripts/never-stuck-gate.sh:138-140`) |
| S1.1 | WatchPaths → poller | write lands after the running drain's last re-glob | no | tick | ≤600 s, ≤1200 s after a skipped tick (R1, R11) |
| S1.2 | self-overlap lock | live holder ⇒ `exit 0` (`lr-reset-poller.sh:179-186`) — skip, never queue | no | tick | every new request, the reaper, DETECT and the reset floor wait for the drain to finish (R1) |
| S1.3 | claim `mv requests/ → claimed/` | second request for the SAME sid (new death uuid) | no | — | `mv` overwrites `claimed/<sid>.json`; second worker on one sid (R7) |
| S1.4 | `--rank --recovery` | exit 2 (all thin) | `PARKED:no-target` + page | each tick | floor = the reset arm below `:896` — a second actuator on the same sid (R10a) |
| S1.5 | probe 120 s | refuses | `PARKED:capacity:<term>` + page | each tick | **session genuinely untouched here** — this is the one hold that is pre-transplant |
| S1.6 | token mint | `tokens/` unwritable ⇒ `LF_ADMIT_TOKEN=""` | not a state detail | — | launcher evaluates fresh with load OFF; degraded but not named |
| S2.1 | live-parser preflight | exit 5 | `results rc 5` + page; no state line (C7 adds only `transplanted`) | after deploy-live | correct and pre-irreversible ✓ |
| S2.2 | `lr-audit.py` + bundle | unbounded on a large transcript (241 MB tail, U14 A9); no `timeout` in C3/C5/C7 | no | — | worker stall ⇒ S1.2 ⇒ R1 |
| S2.3 | transplant | lock exists ⇒ rc 2 (`lr-transplant.sh:60-64`) | `FAILED:transplant` + page | none (honest) | sha mismatch: "FATAL" — whether the lock is removed is NOT verified here (open item) |
| S2.4 | launcher mint (in bundle) | — | — | — | survives reboot ✓ (§6) |
| S3.1 | handoff-fire F1 pane probe | `unknown` ⇒ REFUSE exit 1 (`handoff-fire.sh:11610-11619`) | **no state line** (C9 lists watcher arms only) | reaper at `transplanted` bound | **post-transplant**: source tombstoned + renamed, TUI alive (R5) |
| S3.2 | composer gate 180 s | held draft ⇒ rc≠0 | `HELD:draft` (C9 claims) — but this is a foreground arm | each tick | post-transplant; token TTL 180 expires inside the gate; operator's draft will be BLOCKED by `handed-off-session-guard.sh:60-66` (R5) |
| S3.3 | watcher arm + pane proof ≤18 s | unreachable ⇒ exit | no state line | reaper | post-transplant (R5) — the 2026-09-14 class (U06 §4) |
| S3.4 | teardown marker + freshness re-read | unreadable/non-empty ⇒ abort, watcher killed (`:11751-11759`) | `recycle-held-draft` event; no state line | reaper | post-transplant (R5); teardown marker `mode:"recycle"` already written ⇒ the crash watchdog stays quiet (U04 §3 #4) |
| S3.5 | `/exit` ×3 | untypeable ⇒ watcher disarmed (`:11764-11768`) | no state line | reaper | post-transplant, session alive and blocked (R5) |
| S3.6 | shell wait 120 s | vanish probe `absent` ⇒ `recycle-dead` + alarm ✓ | yes | **no shape** — `mode:recover`/`relaunch` both need the pane; a fresh pane is a fire, not in D1 | named, stranded (minor; all five today had shells) |
| S3.7 | relaunch typed | write failed ×2 ⇒ `recycle-dead` + alarm ✓ + (D1) state + re-drive | yes | yes | ✓ |
| S3.8 | boot wait 20 s | `relaunch.rc` (positive) ✓ · `shell-stable` (heuristic) ✗ · 20 s expiry with no evidence ✗ | yes | **yes, automatically** — on a heuristic (R2) | a slow boot under today's load (U14 B: 4 s is an idle inference) ⇒ `FAILED:relaunch:unknown` ⇒ re-drive `/exit`s the booting session |
| S4.1 | token redeem / gate | refuse ⇒ `FAILED:gate:<term>` state + rc 9 + `relaunch.rc` | yes | yes (`mode:relaunch`, R3 shape) | ✓ the strongest arm in the design |
| S4.2 | READY 300 s / quiet 8 s | "`FAILED:ready` exit 11; TUI alive" | contradictory (R3) | one re-drive | see R3 |
| S4.3 | inject + CR | — | — | — | blind CR budget 1 ✓ |
| S4.4 | submit probe 40 s | prompt QUEUED behind a running turn is invisible to a `type:"user"` probe (R4) | `FAILED:submit` on a working session | "mode `prompt`" — **does not exist** (R3) | false failure; then S4.5 |
| S4.5 | engagement 180 s | no assistant turn after the nonce record | `FAILED:engage` + `recycle-dead` alarm ✓ | none (honest) | page ⇒ R8 |
| S5.1 | results + notify requester | `requested_by=stop-failure-marker` is not a pane | macOS notification only | — | transient |
| S5.2 | page (`cc-notify --page`, desk) | desk role dead, phone unwired | **no live owner** (R8) | — | durable file nobody drains |
| reaper | per tick + end of drain | inside the drain (R1); single store (R2); budget 3 ⇒ `needs-human` page ⇒ S5.2 | — | — | R7's "≤15 min" has no independent enforcer |

---

## 2. Refutations, most severe first

### R1 · MAJOR — the reaper runs inside the thing it bounds, and nothing outside can see a wedged poller

**Claim.** §3 line 100 and C3: "reaper (every tick + end of drain)", workers "`wait`ed as a group",
no per-worker `timeout` anywhere in C3/C5/C7. §7: "whole request 15 min — past it, STALE + page
regardless"; R7: "≤15 min for a stalled driver".

**Why it fails.** The poller's lock is skip-not-queue: a live holder makes the next tick `exit 0`
(`scripts/limit-recover/lr-reset-poller.sh:170-186`, "SKIP (not queue): a missed tick costs 10
minutes"). So while one worker is slow — `lr-audit.py` full mode on a large transcript (U12 §1: 7 s on
6 MB; the fleet's largest is 241 MB, U14 A9; no bound), `lr_tier_from_transcript` (whole-file,
`lr-lib.sh:41`), an `rsync` of a big session dir — the reaper does not run, DETECT does not run, the
reset floor does not run, and every request that lands waits. The 15-min bound is enforced by the
component that is blocked. This is `docs/lessons/inner-bound-outer-bound-starves-the-tail.md`,
which U05 §3.4 already cited against today's watcher; D1 re-creates it one level up. Nothing external
observes the wedge: the plist has no `ExitTimeOut`
(`scripts/limit-recover/com.reso.lr-reset-poller.plist`, keys: Label, ProgramArguments,
StartInterval, RunAtLoad, Standard*Path, EnvironmentVariables), launchd sees a running job, and the
only check of the LaunchAgent in the tree is a lint that asserts "loaded"
(`scripts/never-stuck-gate.sh:138-140`), not "progressing". A dead poller IS covered (stale-steal on
pid+lstart, `:180-185`); a live-but-stuck one is not.

**Consequence for R7.** Even healthy, STALE detection = stage bound + 60 s + up to one tick (600 s),
or 1200 s after a skipped tick — e.g. `transplanted` held by a 180 s composer gate ⇒ 180+60+600 =
14 min best case, 24 min after one skipped tick. R7's "≤15 min" is not met by construction.

**Evidence.** `lr-reset-poller.sh:170-192`; plist (read in full); `never-stuck-gate.sh:138-140`;
D1 §3:100, C3, §7 last rows, R7; U12 §1; U14 A9.

### R2 · MAJOR — a single-store reaper with an automatic re-drive converts a false-negative verdict into a destructive action on a working session

**Claim.** §3: the state file "is the ONLY store the reaper and `lr-status` read." C3: any
non-terminal line past its bound ⇒ `STALE` + re-drive request; C9: `FAILED:relaunch:*` ⇒ a
`mode:"relaunch"` request "so the poller re-drives it". §10: "no non-terminal request survives its
bound without a page and a re-drive."

**Why it fails.** Two cheap false negatives exist, and the reaper never consults the world before
acting on them.

(a) *`shell-stable`.* C9's loop declares failure when `at_shell` reads true twice, 0.5 s apart,
after ≥3 s. `pane_cc_state` returns `shell` whenever the foreground process group is only shells
(`scripts/handoff-fire.sh:3559-3579`, `zsh|bash|sh|…`). Under D1 the launcher is `bash` that no longer
`exec`s (C7 replaces `exec` with `…; rc=$?; printf > relaunch.rc`), so the tree is
`zsh → bash(launcher) → bash(lr-fire-resume)` until `expect` spawns — every instant with no child
subprocess reads `shell`. U04 §5 C measures that window at ~2 s idle; the pre-`expect` work in
`lr-fire-resume.sh:281-330` (account/binary/tombstone validation, the gate) plus C7's new
`lr-ingest-verify.sh` prologue stretch it, and today's box ran at 2.1–6.7 load/core with 10 `bats`
workers (U11 §4). Two samples that both land between subprocesses ⇒ `rcy_verdict=shell-stable` ⇒
`FAILED:relaunch:unknown` ⇒ a `mode:relaunch` request. The re-drive's `handoff-fire --recycle` then
probes the pane, reads `cc` (the TUI is now up), passes the composer gate, and **types `/exit` into
the session that just recovered** — possibly mid-turn on the nonce prompt. The 20 s boot bound has the
same shape with no heuristic at all: U14 B labels the 4 s boot an *idle* inference, "not directly
timed"; a 20 s boot under load ⇒ `FAILED:relaunch:unknown` ⇒ the same re-drive.

(b) *Orphaned engagement.* Once the first watcher has exited on a false verdict, nobody writes
`engaged`: `lr-fire-resume` writes up to `submitted` (C8) and the terminal `engaged` is the watcher's
(C9). The state file ends non-terminal at `submitted`; the reaper marks it `STALE:submitted` at
180+60 s and re-drives again. Bounded by `fire_fail_note` at 3 (`lr-reset-poller.sh:257-266`) ⇒ a
`needs-human` page for a session that has been working the whole time.

The check that would prevent both is already in the tree and costs milliseconds:
`lr_registry_live_rows` (`scripts/limit-recover/lr-lib.sh:210-231`, `kill -0` on the registry pid) and
the design's own `lr-submit-probe`/`resume_engaged` on the TARGET transcript. D1 uses the registry
only for retirement (C3) and forbids the reaper any store but the state file. U08 §4.3's rc 5 —
"CR sent but no record — CANNOT TELL, never failed" — is the contract the watcher should have
inherited; C9 instead names the indeterminate case as a failure and acts on it.

**Evidence.** D1 §3 (ONLY store), C9 loop + `no claude process` branch, C3 reaper; `handoff-fire.sh:3532-3580`,
`:6430-6431`; `lr-fire-resume.sh:281-330`; `lr-lib.sh:210-231`; `lr-reset-poller.sh:251-266`; U04 §5 C;
U14 §B; U11 §4; U08 §4.3.

### R3 · MAJOR — S4's failure semantics are unreachable as written, and the auto-remedy for the unsubmitted-prompt class names a mode that has no component

**Claim.** C8: on submit failure "`lr_state_append FAILED:submit`, `send_user` the prompt, **exit 12**,
TUI left alive"; on READY never seen "`exit 11`". C7: `relaunch.rc` is written "ONLY when the launcher
died before the TUI". §10: "prompt not submitted → `FAILED:submit` exit 12; TUI alive, composer holds
the text; re-drive types the prompt only (mode `prompt`)". C1: `mode` ∈ `recover | relaunch | drill`.

**Why it fails.** `lr-fire-resume.sh` runs `expect -c '…' || lr_rc=$?` (`:428-432`) and then, on a tty,
**always** `exec "${SHELL}" -l -i` (`:584-606`, "a real pane must survive"). So once `expect` has been
reached the launcher's `; rc=$?; printf … > relaunch.rc` line never runs until the nested zsh exits
hours later — exits 11/12 are invisible to the launcher and to the watcher's `relaunch.rc` poll. And an
`exit` inside the expect program closes the spawned pty; the TUI it spawned is the pty's session leader
and is SIGHUP'd (GUESS on the exact signal path — reasoned from pty semantics, not run on this box; the
outcome "TUI not alive in the pane" holds either way, because a process with no controlling terminal
is not a pane's session). So the two halves of the row cannot both hold: either expect continues to
`interact` (TUI alive, **no rc anywhere**, the state line is the only signal) or it exits (TUI gone,
pane at the nested zsh, `relaunch.rc` still unwritten). §10's "TUI alive, composer holds the text" is
only reachable on the first branch — and there the remedy is "re-drive types the prompt only (mode
`prompt`)", which (i) is not in C1's enum, (ii) has no writer in C1–C12 — nothing in D1 types into a
live composer from outside the pty (U08 §4's `cc-tui.sh` is not adopted), and (iii) C12 bans every
primitive that could (`cc-pane send`, `it2 session send/run`, `send-key`). What actually happens on
that branch: the watcher waits `RCY_ENGAGE_TIMEOUT` 180 s, then `FAILED:engage` + `recycle-dead` alarm,
"none automatic" (§10). That is pane 111 today — the composer holding an unsubmitted prompt for 17.1
min (U11 §7 #3) — **named, not remedied**. R8 fails for the class that dominated today's manual time.

**Evidence.** `lr-fire-resume.sh:428-432, :584-606`; D1 C1 request schema, C7 heredoc, C8, §10 rows
"TUI never READY" / "prompt not submitted" / "submitted, never engaged"; U08 §2 ("no public 'type into
a TUI composer and prove it submitted' entry point"), §4; U11 §3 (09e64dcb ledger), §7 #3.

### R4 · MAJOR — replaying pane 112 under D1 yields a FALSE FAILURE: the submit oracle cannot see a QUEUED prompt

**Claim.** C8/§7: "submit probe 30 s, then one re-CR + 10 s … the user record is written at submit
time, sub-second (U03 §4)". §8: submitted = "`type:"user"` record after `t0` containing the nonce".

**Why it fails.** On `--resume`, Claude Code dequeues the session's pending queue at boot. The
d02d8feb target transcript
(`~/.claude-secondary/projects/-Users-chrisren-Development--worktrees-wt-cc-095358-75429/d02d8feb-….jsonl`,
lines 1133-1147): `queue-operation enqueue` 17:20:57.500 (`<task-notification>…`) → `dequeue`
17:20:57.671 → the meta `Continue from where you left off.` user record → the notification's own
`type:"user"` record at 1147 → that turn ran on for many minutes (U12 §5: 68 tool calls, a landed
commit). D1's nonce prompt is injected ~5 s later, after READY, **into a running turn** — it is
queued, not submitted. A queued prompt is on disk immediately, but only as
`{"type":"queue-operation","operation":"enqueue",…,"content":"<the text>"}` (shape verified: `grep -m3
'"queue-operation"'` on that file shows `enqueue` records carrying `content`); its `type:"user"` record
appears at dequeue, i.e. when the notification turn ends. C8's 40 s window expires ⇒ `FAILED:submit`
on a session that is working and will submit the nonce by itself. What follows is R3's fork: expect
exits (kills the working turn) or the watcher pages `recycle-dead` at 180 s. Either way D1 reports the
one session that recovered fastest today as a failure. This is the common case, not the exotic one:
2 of 5 sessions today carried queued notifications (112, 121 — U11 §0(B)), and 09e64dcb's second limit
was itself caused by one running while blocked (U10 §1c). The fix is one clause (accept an `enqueue`
record carrying the nonce as `queued`, a non-terminal hold with the engagement bound, not the 40 s
one); as written the oracle fails.

**Evidence.** transcript lines 1133-1147 (read this session); `queue-operation` shapes incl.
`remove … reason:"absorbed_mid_turn"` (line 2 of the grep — a queued item can also be absorbed
mid-turn, which the probe would then see as a user record; unmeasured which happens to a typed
prompt); U11 §0(B), §3; U12 §5; U10 §1c/§1d line 1141; D1 C8, §7, §8.

### R5 · MAJOR — irreversible-first ordering survives, and the design mis-describes what a post-transplant refusal leaves behind

**Claim.** §7: composer gate "unchanged (`:11634`); a draft is the operator's; state `HELD:draft` says
why". §10: "composer holds an operator draft → `HELD:draft` … re-drive each tick; **session
untouched**". §10 enumerates no row for a pane-probe `unknown`, pane-unreachable, freshness-re-read
abort, or `/exit`-untypeable outcome. C9's state writer list covers the watcher's arms only.

**Why it fails.** `lr-handoff.sh` transplants at `:512-519` — lock, `cp -p`, tombstone, rename to
`.handed-off` — and only then calls `handoff-fire --recycle` (`:619-628`). Every refusal in the
foreground of `recycle_fire` is therefore after the irreversible step: F1 `unknown` ⇒ `exit 1`
(`handoff-fire.sh:11610-11619`), the composer gate (`:11634`), pane proof, the freshness re-read
(`:11751-11759`, "nothing typed, watcher disarmed, session stays alive"), `/exit` untypeable
(`:11764-11768`). "Session stays alive" is true and "session untouched" is false: its transcript has
been renamed, a live CC appends by path and re-creates a stub `<sid>.jsonl` in the retired store
(that is exactly why the watcher folds it, `:6756-6770`), and `hooks/handed-off-session-guard.sh:60-66`
blocks the very draft the composer gate was protecting the moment the operator presses Enter. The
2026-09-14 daemon run is this class — `pane 276 resolved to no tty` ⇒ `rc=2` ⇒ "the source pane is a
tombstoned husk" (U06 §4) — and U09 gap #2 already named the ordering as the husk generator. D1 keeps
the order, gives these arms no state line (the file sits at `transplanted` until the reaper's bound),
and its re-drive for a stale `transplanted` is `mode:relaunch` = "tombstone exists, pane at a shell —
launcher only" (C1) — the wrong shape for a pane that still holds a live, blocked TUI; nothing in C5/C7
specifies a "recycle without transplant" path, and `--in-place` refuses `--no-transplant` today
(`lr-handoff.sh:229-231`). Minor corollary: the admission token's TTL is 180 s (C6) and the composer
gate is 180 s, so the "one decision, redeemed once" guarantee lapses in precisely the held case.

The cheap inversion — run F1, the composer gate and pane proof (all reads) BEFORE `lr-transplant.sh`,
and transplant only on an affirmative `cc` + empty composer — is absent from D1.

**Evidence.** `lr-handoff.sh:225-231, :512-519, :612-652`; `handoff-fire.sh:11604-11619, :11630-11640,
:11745-11768, :6756-6770`; `hooks/handed-off-session-guard.sh:60-66`; U06 §4; U09 gap #2; D1 §7, §10, C1, C9.

### R6 · MAJOR — the hook latches before it writes; a timeout kill between them is a silent, per-uuid permanent loss of the zero-touch path

**Claim.** C1: latch `( set -C; : > "$STATE/requests-latch/$SID.$DUUID" )`; "Every path exits 0";
§10 row 1: "hook cannot write the request → IDL `abstained req-write-failed` … degraded, never lost".

**Why it fails.** C1 adopts U10 §2g "with pins", and §2g's order is: latch (line 348) → `PANE` →
`lr_tier_from_transcript` → `oi_origin_class` → `jq … > requests/<sid>.json` (355-362). The hook has a
10 s budget (`~/.claude/settings.json` `.hooks.StopFailure[0].hooks[0].timeout` ⇒ `10`);
`lr_tier_from_transcript` iterates the **whole** transcript (`lr-lib.sh:41`, `for line in
open(...)`) — 79 ms on 3.4 MB (U10 §2c), unmeasured on the 241 MB tail (U14 A9), on a box at
6.7 load/core. A kill after the latch and before the write leaves the latch with no request and **no
IDL row** — a SIGKILL writes nothing; the `abstained` row §10 cites is emitted only by code that
survived. The next StopFailure on the same death uuid (they re-fire: e442434c 3× in 16 s, U10 §1c)
abstains `request-latched`. Fallback: the poller's DETECT arm parks it at ≤600 s and waits for the
reset (U06 §1) — the 2h40m outcome, with no line anywhere saying the request lane was skipped. Same
class, narrower window: the request is written with `>` (non-atomic); a WatchPaths-started poller or
the running drain's re-scan can read the empty file; `lr-reset-poller.sh:650-651` moves a sid-less file
OUT of `requests/` as `.malformed.json`, and the latch prevents a re-request.

The fix is ordering: write to `requests/.<sid>.tmp`, `mv` into place, and take the latch as the
success of that `mv` (or make the request file itself the O_EXCL target keyed by uuid).

**Evidence.** U10 §2g (sketch lines 343-366); D1 C1; `lr-lib.sh:34-45`; `settings.json` StopFailure;
`lr-reset-poller.sh:650-651`; U10 §1c; U14 A9.

### R7 · MAJOR — claim-by-rename is not a per-sid mutex, and the state machine has no attempt epoch

**Claim.** §11: "Never two writers on one uuid — latch per death uuid (C1); claim-by-rename (C3); the
transplant lock (exists)". §13: "`state/*.jsonl`: transitions in §3 order, no gaps".

**Why it fails.** The latch is per DEATH RECORD by design (C1 pins it so a second cap in one day writes
a second request). A limited session keeps its input loop alive and re-limits when a queued
notification runs a turn — measured: 09e64dcb at 17:11:29, ten minutes after its first; e442434c four
times on two uuids (U10 §1c, §2d). C1's second guard (skip if lock/tombstone exists) only exists
AFTER the transplant, and the design's own holds are where the source stays alive the longest:
`PARKED:capacity` (120 s, then every 600 s tick) and `PARKED:no-target` (until the ranker finds
headroom). A second death uuid during a hold writes a second `requests/<sid>.json` (the first is
already in `claimed/`); the drain's re-scan claims it — `mv` silently overwrites `claimed/<sid>.json`
— and starts a second worker on the same sid. `lr-transplant.sh:60-64` refuses on the lock (good), so
worker 2 appends `FAILED:transplant:lock-exists` — a TERMINAL line — to the same `state/<sid>.jsonl`
while worker 1 is at `exit-typed`. Consequences: `lr_state_current` (= `tail -1`) reads FAILED, the
poller deletes `claimed/<sid>.json` "on terminal state" (C3) out from under worker 1, a `FAILED` page
goes out for a healthy recovery, and `fire_fail_note` charges the sid one of its three re-drives. Even
without a second request, the normal path has two async writers (lr-fire-resume inside the pane,
the watcher outside), so §13's "transitions in §3 order, no gaps" is a flaky acceptance criterion by
construction (`tui-up` vs `gate-admitted`/`ready` ordering is not guaranteed).

**Evidence.** D1 C1 (latch per uuid; second guard), C3 (claim `mv`; "deleted on terminal state"),
§3 (`tail -1`), §11, §13; `lr-transplant.sh:59-64`; U10 §1c, §2d, §3d.3.

### R8 · MAJOR — every D1 page routes to a role that is dead on this box, and the design never checks

**Claim.** §9: "A failure: a page (`cc-notify --page`, desk role) + macOS notification". §10 "named
as … + page" on nine rows; C3 reaper "page once (cause-keyed via `page-damp.sh`)"; the third re-drive
failure "pages `needs-human`".

**Why it fails.** `hf_alarm` records then pushes via `cc-notify --role desk`
(`scripts/handoff-fire.sh:5220-5250`). On this box `~/.claude/cc-roles/desk` = `672` (mtime Sep 9);
`ls ~/.claude/cc-registry/ | grep -c '^672\.json$'` ⇒ `0`; `kitty @ ls --match id:672` timed out at
8 s (rc 124 — INDETERMINATE, the same 1-in-12 socket timeout U07 §5/U08 §6 measured; consistent with,
not proof of, absence). cc-notify's liveness-free leg is the phone (`bin/cc-notify:470-525`), and the
phone is unwired: `hooks/push-critical.sh:22-23` exits on unset `PUSHOVER_TOKEN` (U10 §1b), and
`env | grep -c '^PUSHOVER'` ⇒ `0` in this session. `scripts/autonomy-sweep.sh:1956-1975` documents the
resulting steady state in its own words: "cc-roles/desk holds an … uuid … whose pane has self-closed …
rc 0 with verdict=mailbox-only/unverified FOREVER … permanent SILENT LOSS". So a zero-touch failure
produces a durable JSON nobody drains, one transient `display notification`, and a `#` comment sent
with `it2 session run` — the launch verb whose armed-pane branch writes `$CMD_DIR/<id>.cmd` instead of
typing (U04 §2, `handoff-fire.sh:1419-1431`). The repo's own lesson for exactly this
(`dead-session-verdict-belongs-in-the-pane`, rules file) is to paint the verdict into the pane's tty;
D1 reuses the existing `session run` line. "Visible with an owner" therefore holds only for an operator
who polls `lr-status --all`.

**Evidence.** `handoff-fire.sh:5220-5250`; `~/.claude/cc-roles/desk`; registry listing; `bin/cc-notify:470-525`;
`hooks/push-critical.sh:22-23`; `autonomy-sweep.sh:1956-1975`; U10 §1b; U04 §2/§3 #6; D1 §9, §10, C3.

### R9 · MINOR — `CC_ADMIT_NET_ZERO` double-discounts once the `limited` beat lands; "the budget is not widened" is false by one slot per concurrent recovery

U05 §4.2's argument for `+0` was that the dying session is still in `act` (its `prompt` beat stands
while the TUI lives). C1's `kind:"limited"` beat removes it — `cc_sp_active` selects `kind=="prompt"`
(`scripts/lib/spawn-presence.sh:298`). With both, neither the old session nor its replacement is
charged against `CC_ADMIT_ACTIVE_CEILING` (`capacity-admit.sh:832`, `act + 1`): each in-flight
recovery raises the effective ceiling by one, up to three at concurrency 3. §11's "the budget is not
widened" is false by that amount. Keep one of the two, not both. (Cause refuted ≠ effect discharged,
in reverse: the remedy kept after its premise was removed.)

### R10 · MINOR — two uncoordinated actuators can act on a D1 husk

(a) The reset-poller's arm below `:896` nudges `/limit-recover` into a live pane (`:928-943`) or spawns
`lr-fire-resume` on the SOURCE account when the pane is dead (`:966-1013`). C3 leaves the `parked/`
record in place for a `PARKED:*` sid, and §10 names that arm as the floor for `PARKED:no-target`.
C12's read-state-first guard covers the nudge; the spawn arm has no guard and no knowledge of
`claimed/`. (b) `bin/cc-husk-sweep --resume` resolves a husk from its registry row — which after a
failed relaunch still names the transplanted sid AND the source account (U04 §3 #1) — and has zero
tombstone awareness (`grep -n 'HANDOFF.json\|handed-off\|tombstone\|locks/' bin/cc-husk-sweep` ⇒ no
hits; header `:1-30` "resolves the session AND its account, and types the pinned launcher"). It is
manual (typed-yes) and `handed-off-session-guard` blocks the first prompt, but the boot leaves a stub
transcript and a wrong-account registry row for D1's reaper to misread. D1 does not mention it (U09 Q2
asked).

### R11 · MINOR — the wake path has a 600–1200 s hole the design bounds but then contradicts in R1

WatchPaths does not restart a running job, and a `kickstart` without `-k` on a running service errors
rather than queues (GUESS: EALREADY per launchctl(1), not measured here). C3's re-scan covers a
request that lands during the drain, but one landing after the last re-glob and before process exit
waits for the next tick — and with the skip-not-queue lock (`lr-reset-poller.sh:179`) a long drain
makes that up to 1200 s. R1's "≤2 s … ≤600 s backstop" understates the backstop by one tick.

### R12 · MINOR — two drill assertions cannot fail

"`state/*.jsonl`: transitions in §3 order, no gaps" flakes under two async writers (R7) and is
otherwise unfalsifiable as an ORDER claim. "IDL: 0 `lr-fire-resume refuse term=load` rows" is vacuous
once the term is OFF (`docs/lessons/green-in-both-arms-is-an-equivalence-guard-not-a-red-proof.md`):
the assertion with power is "0 `term=load` rows AND ≥1 `basis:token` row per session".

---

## 3. Replay of today's five sessions against D1

| session / pane | what happened today | under D1 as written | verdict |
|---|---|---|---|
| **d02d8feb / 112** | 658 s park on the load term; relaunch refused (stale counter at 3/3) then `budget-expired` admit; "ENGAGEMENT CONFIRMED" by a queued `<task-notification>` turn; ingest never delivered (U01 §5.3, U03 headline, U11 §0) | Probe admits in ~1.5 s (load OFF, NET_ZERO); token ⇒ launcher admits ✓. `--resume` dequeues the notification at boot (transcript lines 1133-1147) and runs a multi-minute turn; the nonce prompt is QUEUED; C8's `type:"user"` probe expires at 40 s ⇒ `FAILED:submit` (R4) ⇒ R3's fork: expect exits and kills the working turn, or the watcher pages `recycle-dead` at 180 s to a dead desk (R8) | **FALSE FAILURE**, possibly destructive |
| **09e64dcb / 111** | refusal 1 and 2 of 3 ⇒ husk with no row/alarm; 17.1 min hand-submitting the prompt (`cc-pane send` rc 0 delivered nothing, `it2 session send CR` typed "CR") (U02 §0, U11 §3) | Token + load OFF ⇒ admitted ✓; any residual refusal lands in `relaunch.rc` + IDL join in ≤2 s with an alarm and a `mode:relaunch` re-drive ✓ (K7/K8). The unsubmitted-prompt class becomes `FAILED:submit`/`FAILED:engage` with a page — and the "mode `prompt`" remedy does not exist (R3). Its second limit (17:11:29, a queued turn) would arrive after the transplant ⇒ tombstone guard skips ✓; had it arrived during a hold ⇒ R7 | husk closed ✓; manual class **named, not remedied** |
| **e442434c / 121** | PARKED 4× on `reserve-active` (husk-counting), then husk; ingest never delivered even after the hand relaunch (U05 §3.2, U11 §3) | `limited` beat + NET_ZERO clear the `reserve-active` refusals ✓ (over-clears by one, R9). Same S4 exposure as 112 (it too had a queued notification, U11 §0(B)). Its 4 StopFailures on 2 uuids: the 17:27:19 one lands post-transplant ⇒ guard ✓; inside a 120 s `PARKED:capacity` it would mint a second worker (R7) | as 112 |
| **28f07827 / 114** | husk; one in-flight subagent killed by the `/exit` (U09 #17); ingest by hand +6m40s | `lr-ingest-verify` clause A (open delegations) fails ⇒ fail-closed slash prompt — the 41 KB command and the autocomplete-CR-swallow class (U03 (b)) return for exactly this session; the subagent is still killed (no in-flight gate before `/exit`). Three StopFailures in 2 min (17:07:35, 17:09:46, 17:09:50 — uuids unverified) ⇒ up to three requests inside the S1 window (R7) | recovered, correctly degraded; subagent loss unaddressed |
| **cb227486 / 117** | husk at 4.15→6.73/core; the one whose ingest was delivered at 17:57:29 — U11 §0 says auto-submitted, U03's table says by hand: **the research disagrees** | The clean D1 path: token, load OFF, nonce, probe — the ~33 s case IF no queued turn. Load spikes are irrelevant with the term off ✓. But today's load (10 `bats` workers, 3.29–6.73/core) is exactly where the 20 s boot bound (an idle inference, U14 B) and the `shell-stable` heuristic mint a false `FAILED:relaunch` and an automatic `/exit` (R2) | likely ✓; exposed to R2 under today's load |

Net: D1 closes the 4 husks' CAUSE (the gate split) and the 658 s park. It re-creates today's
false-positive engagement as a false-NEGATIVE submit on the same session (112), leaves the
dominant manual-repair class named but unremedied (111), and adds an automatic destructive action
on a working session that today's tooling did not have.

---

## 4. Keeps — what survives this lens and should be carried into the synthesis

- **K1 · StopFailure as the detector + a request-lane writer in the existing hook** (C1) — sub-second,
  registered in all five dirs, fail-open (`hooks/stop-failure-marker.sh:31-33`). Keep, with the
  write-then-latch ordering (R6) and an atomic `mv` into `requests/`.
- **K2 · WatchPaths + kickstart wake** (C2) with `ThrottleInterval 5`; the precedent
  `launchd/com.claude.browse-mirror.plist` is real.
- **K3 · Claim-by-rename** (C3) as the `requests/ → claimed/` step — keep, plus a per-sid driver lock
  (e.g. `mkdir claimed/<sid>.d`) checked BEFORE the `mv`, and an `attempt` id on every state line (R7).
- **K4 · Append-only ≤1 KB state file + `lr-status`** (C4) — keep as the OPERATOR's and the drill's read.
  Not as the reaper's only read (R2).
- **K5 · Registry-first `--one`, `--rank --recovery` + `--assign`, rank stderr kept, account token
  validated** (C5, C11) — U01 §7, U13 §4 verbatim; all pre-irreversible.
- **K6 · Load term OFF on the recovery callers + the one-shot admission token + T3 ratchet** (C6, C7,
  §11) — the fix for 4 of 5 husks; U05 P1/P2 with red-proofs. Keep `NET_ZERO` OR the `limited` beat,
  not both (R9).
- **K7 · `relaunch.rc` as the POSITIVE pre-expect discriminator** (C7) — correct for `exit 9`/arg
  errors, which is what killed today. Its scope must be stated as pre-expect only (R3).
- **K8 · The `no claude process` branch gets the IDL join, a row, an alarm, the real elapsed time**
  (C9) — U04 §3's three lines; the single highest-leverage visibility fix.
- **K9 · Quiet-pty READY fallback + transcript submit probe + blind-CR budget of 1** (C8) — keep;
  extend the probe to `queue-operation enqueue` content (R4) and route its verdict through a state
  line, never an `exit` from expect (R3).
- **K10 · Fastpath ingest with a script-emitted receipt and a fail-closed slash prompt** (C7, U12 §6).
- **K11 · `⌗pane sid8` left-anchored on the statusline + `cc-find` that REFUSES on ambiguity** (C10) —
  what makes the manual fallback safe; U07 §6c's refusal is the fault-tolerant property.
- **K12 · Retire on `RECOVERED` or a live registry row, never on `lr_transplanted_to`** (C3) — U02 §2c's
  "the one daemon that could have caught this does the opposite", fixed.
- **K13 · Bounded, retried kitty RPC with INDETERMINATE as a first-class verdict** (C10) — extend it to
  every watcher verdict (R2): `unknown`/`shell-stable`/timeout ⇒ keep polling or STALE + page, never
  an automatic re-drive without positive evidence.
- **K14 · Landing order** (C6+C8+C9 converge first; C7's live-parser preflight extended) — the
  `launcher-runs-the-live-layer` lesson applied.
- **K15 · Pages and notifications cause-keyed through `page-damp.sh`** — correct polarity; needs a
  live owner (R8) and a pane-tty paint per the repo's own lesson.
- **K16 · The drill's fault injections 1–3** (§13) — right shape; add: a queued notification on one
  session (R4), a kitty timeout injected during the freshness re-read (R5), a slow worker during the
  drain (R1), and a second StopFailure during a `PARKED:capacity` hold (R7).

---

## 5. What I could not establish (labelled)

1. Whether an `exit` inside `lr-fire-resume`'s expect program SIGHUPs the spawned TUI on this box
   (R3) — reasoned from pty semantics; not executed (it would kill a session). The refutation's
   weaker form — no rc reaches the launcher until the nested zsh exits — is verified from
   `lr-fire-resume.sh:584-606` alone.
2. Pane 672's existence: `kitty @ ls --match id:672` returned rc 124 (socket timeout) — R8 rests on
   the registry (no row), the role file's age, and the phone being unwired.
3. `launchctl kickstart` without `-k` on a running service (R11): recalled behaviour, not measured.
4. TUI boot time under today's load (R2): U14 §B labels 4 s an idle inference; no measurement
   under 6.7/core exists.
5. Whether a typed prompt that lands mid-turn is `enqueue`d or `absorbed_mid_turn` (R4): both shapes
   exist in the 112 transcript; the probe as designed sees only the second.
6. `lr-transplant.sh` step 9 "FATAL on sha mismatch" — whether the lock is removed on that path
   (S2.3): not read past `:70`.
7. Whether `StopFailure` fires inside an Agent-Teams assignee (S0.2) — D1 §16 already states this as
   unmeasured; unchanged.
