---
status: in-progress
---
# Agent peer wake + origin retirement into a live successor

Scope (frozen): give agents two capabilities so the operator stops doing hand-steps between sessions — (1) wake an IDLE peer session so it takes a turn and reads its inbox, and (2) let an operator-launched (origin) pane retire itself into a VERIFIED LIVE successor that has provably read the handover — built, tested, landed on origin/main and converged live.

Operator, 2026-10-03: "You need to have the behavior … to be able to have the agency to act on this
proactively yourself; you need to have the permissions and allowlist of commands so you have the
ability to do this yourself."

## Phase 0 — orchestration

- **Execution locus: L (lead-inline), one wave.** Why: three tightly coupled edits (a new bin, a
  cc-notify call site, one new self-close class) whose contracts must be designed against each other.
  Each one is small, and splitting them would cost more in briefs than it saves.
- Lead context budget: finish inside this session. The succession point is after landing; acceptance
  is two live calls.

## Step 0 — why `mailbox-wake-arm.sh` did not wake pane claude-infrastructure-83 (measured)

| fact | evidence |
|---|---|
| pane 83 (pid 5541, sid b671b47e) was born 2026-10-02 22:56:55 and went idle at 22:57:17 | `ps -o lstart`; `cc-beats/b671b47e….json` `kind=stop t=1790999837 seq=2` |
| its birth watcher armed at SessionStart, and a watch lasts 14340 s (3h59m), so it lapsed at ~02:56 | `hooks/mailbox-wake-arm.sh` `_to=14340`; no `.watchers/83.*` and no `83.watching` now |
| pane 10's pings landed at 11:47:41 and 11:50:45, about nine hours after the watch lapsed | `mailbox/83.md` lines 16-17; `seen=acked=15` |
| **the Stop re-arm was never live.** Migration 0012 (the hook registered on `Stop`) is still `staged`, never run, in all five config dirs | `autonomy/migrations/staged/0012-…json`; `jq` count of Stop entries = 0 in every `settings.json` |

So the mechanism is built correctly but was never turned on. **Two gaps remain even after 0012 runs:**
1. Stop re-arms once per idle, and the watch still lapses after 3h59m. A session idle longer than that
   is deaf again, and no Stop arrives to re-arm it.
2. A wake that depends on the receiver can never reach a receiver that is already deaf, like pane 83
   today. Only the SENDER can close this one.

## The transport: Claude Code's own messaging socket, not keystrokes

The v1 keystroke transport was removed because typing raced the operator's live input
(TWO_WAY_SESSION_COMMS_PLAN.md:8-12, 212-214). Claude Code ≥2.1.224 binds a per-session socket at
`/tmp/cc-socks/<pid>.sock` and publishes `~/.claude*/sessions/<pid>.json` (sessionId, procStart,
status idle|busy|waiting, messagingSocketPath). `docs/research/wake-socket-repricing-2026-09-10.md`
proved external delivery. The 2.1.284 bundle, read on 2026-10-03, gives the wire format:
`{"type":"user","session_id":…,"from":…,"message":{"content":…},"priority":"next"}`. A
`session_id` mismatch is dropped, and the record is queued `isMeta:true, skipSlashCommands:true`.
**It never touches the composer**, so an operator's half-typed draft is untouched by construction.
That removes the race which killed v1, and the brief's "type into a peer" guards become unnecessary
rather than merely satisfied: no keystroke path is added.

## Capability 1 — `bin/cc-wake <target>`

Gates, all fail-closed. Each refusal is exit 1 and nothing is sent:
- **W1 identity:** the target resolves through `cc-registry` to a pane, sid and pid, and the pid is alive.
- **W2 anti-reuse:** some `sessions/<pid>.json` has `sessionId == sid` and `procStart ==` the live
  `ps -o lstart=`. The socket is a socket owned by us.
- **W3 idle, from two independent producers:** the vendor reports `status == "idle"`, AND our beat
  (`session_busy_live`) reads IDLE-*, AND no permission prompt is pending (`sb_permpend`).
- **W4 something to read:** the target's keyset has unacked mail. Nothing is sent over an empty inbox.
- **W5 rate:** at most one wake per sid per `CC_WAKE_MIN_GAP_S` (120 s).
- The payload is FIXED text: a count, the sender and one instruction to make a tool call. The message
  body never travels this way, so delivery still goes through `mailbox-drain` and the cursors.
- **Verify by effect:** `--wait S` (default 240) polls `mailbox_receipt` for the newest unacked line
  until it reads `read`. Exit 0 means READ. Exit 3 means sent but not READ, and is never reported as success.
- `--no-wait` is the fire-and-forget form that cc-notify uses.

**Agency:** `cc-notify`, after a successful enqueue to a live target that has NO watcher armed, calls
`cc-wake --no-wait` itself. Opt out with `--no-wake` or `CC_NOTIFY_WAKE=0`. Every ping to a deaf idle
peer now wakes it, with no agent or operator remembering to. cc-notify also writes
`mailbox/.sent-lines/<own>` (`ts box line target`), a NEW store that leaves the field-counted `.sent`
format untouched.

## Capability 2 — self-close class `verified-successor`

A fourth named admissible class, beside `assignee` and `transplanted-source`. It is a named class
with its own preconditions, not a widened `--allow-origin-close`. It is evaluated only for
`--successor`, never `--terminal`, only for a local close, and only when the fired-peer stamp is not
valid. All of the following must hold:
- **V1 handover READ:** the newest `.sent-lines/<this pane>` row whose box is in the successor's keyset
  has `mailbox_receipt == read`. Delivered or surfaced is not enough.
- **V2 tree clean** (tracked files). `--allow-dirty` and `--dirty-owner` refuse with this class.
- **V3 custody:** `cc-custody count --open --cwd $PWD` is 0. If it cannot be read, the class refuses.
- **V4 successor alive and engaged:** the existing successor gate, which runs for every close.
  `--successor-assume-engaged` refuses with this class.

If any check fails, the session falls through to the unchanged origin refusal, with the failed check
named. `--terminal` stays refused for origin sessions, and `--allow-origin-close` stays the operator's
override. Kill switch: `CC_ORIGIN_SUCCESSOR_CLOSE=0`.

## Permissions

The new migration `migrations/00NN-cc-wake-allow.sh` (class c10, staged) adds `Bash(cc-wake:*)` and
`Bash(~/.claude/bin/cc-wake:*)` allow rules. The operator also runs 0012, which has been staged since
August. Both go in one handed script.

## Tests (planted input; each must fail without its guard)

`tests/cc-wake.bats`: one test per gate W1-W5, plus the payload shape (a fake socket server records
the frame), the session_id pin, and the receipt-wait outcomes (READ gives 0, timeout gives 3).
`tests/self-close-verified-successor.bats`: V1 unread / surfaced / read, V2, V3, the `--terminal`
refusal, and the kill switch.

## Acceptance (live, after converge)

(a) Wake pane claude-infrastructure-83, and its receipt for pane 10's pings goes READ.
(b) Ping tm2-plan-replan-10 that capability 2 is live, so that pane can run
`self-close --successor <83>`.

## Status

- [x] plan committed (`4a1857af7`) · [x] cc-wake + 18 bats, every gate mutation-checked red
  (`88e01f983`) · [x] cc-notify wiring + `.sent-lines` + 6 bats, cc-notify.bats still green 117/117
  (`e3286a961`) · [x] migration 0052 (`e7c577f70`) · [ ] self-close class + bats · [ ] landed ·
  [ ] converged · [ ] acceptance (a) · [ ] acceptance (b)
- Built differently from the brief's sketch: there is no keystroke path at all. Every "type into a
  peer" guard the brief lists exists to make a keystroke safe. The socket never reaches the composer,
  so those guards had nothing left to guard.
- Pre-existing, not caused by this work: `scripts/typed-send-lint.sh` exits 1 on trunk with or without these files.
