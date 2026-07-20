# Cross-session mail to 100th percentile — reliably receivable, reliably sendable, human-visible in the Claude Code UI

**Date:** 2026-07-20 · **Scope (frozen):** investigate making cross-session mail 100th percentile by
making it reliably receivable and sendable and user-Claude-Code-UI present. · **Method:** disk-truth
read of the entire v2 comms substrate + live mailbox forensics + harness-capability verification
(claude-code-guide agent). · **Parent plan:** `docs/plans/TWO_WAY_SESSION_COMMS_PLAN.md` (v1 landed
2026-07-18; v2 landed 2026-07-20 — this doc is the v3 gap analysis + design).

## Verdict

The v2 inbox substrate is **sound as a transport** — append-only per-pane inboxes, exactly-once
split-cursor delivery under a lock, honest sender verdicts, a fail-loud guard riding the reaper
cadence. What it lacks is a **service level**: nothing guarantees a live session ever reaches a
drain boundary (16 live sessions, **0** armed watchers at survey time; the live desk sat on 57
unacked pages for 2+ hours), succession strands whole inboxes (three former-desk boxes hold
631/206/155 permanently-dead lines), and **no surface renders any of it to the human** —
`additionalContext` is model-only, the guard's escalations are loud-to-disk but the phone leg is
inert and the Operator Blocker Board doesn't read comms-alarms. Result on disk today: **~78% of all
mail ever sent (1,401 of 1,788 lines) was never consumed.**

100th percentile = keep the transport, add three planes:
1. **Delivery SLO** (receivable): a standing wake floor, a mid-turn drain boundary, succession
   mail-forwarding, and a dead-box lifecycle.
2. **Addressing that survives recycles** (sendable): role addressing + forward chains + dead-target
   reroute + producer damping.
3. **A human plane** (UI-present): every delivery renders a `systemMessage` line in the Claude Code
   TUI, an ambient unread badge in the statusline, `cc-thread` adopted as the first-class reader,
   and comms-alarms on the Operator Blocker Board.

## 1 · Current substrate (verified, file:line)

| Piece | Role | Key facts |
|---|---|---|
| `bin/cc-notify` | send | appends `<ISO> [<from>] <msg>` to `~/.claude/mailbox/<paneUUID>.md` (`:125-149`); resolves friendly-name→UUID via `cc-sessions`, else raw-UUID passthrough (`:80-98`); newline-collapse keeps 1 msg = 1 line (F13); honest exits 0/2/3/5; exit-5 self-escalates — durable alarm record + phone (F4, `:133-149`); liveness verdicts: wake-armed / live-no-watcher / mailbox-only / unverifiable (`:157-207`, F5) |
| `hooks/mailbox-drain.sh` | receive (reliable boundaries) | SessionStart + UserPromptSubmit → `additionalContext`, immediate ack (`mailbox_take <uuid> 1`); every path exits 0; Stop deliberately NOT here (critique fix B) |
| `hooks/session-continue.sh:150-187` | receive (in-loop desk) | folds pending mail into the `decision:block` reason **only when the continuation sentinel is armed**; lag-ack via `mailbox_promote_acked`; mail is PREPENDED above the re-arm reminder (F14) |
| `bin/cc-await-ping` | wake (armed pull) | polls the same `.seen` cursor (F6a — pending-at-arm fires immediately); heartbeats `<uuid>.watching` each poll (F5 wake-path proof); exit rides the harness task-completion notification back into the model; `--role` re-resolves per poll |
| `hooks/lib/mailbox-pending.sh` | cursor truth | split cursor: `.seen` = emitted, `.acked` = consumed, `acked ≤ seen ≤ lines`; locked atomic `mailbox_take` (mkdir lock, macOS-safe, self-breaking, degrades to dup-not-hang); `grep -c ''` everywhere (F1); past-EOF clamp → re-deliver (F11) |
| `bin/cc-inbox-guard` | fail-loud backstop | keys on **`.acked`** (never the eager `.seen`); class deadlines 60 s urgent / 600 s routine (F12); owner liveness by PANE existence + reconcile-first, INDETERMINATE ⇒ escalate (F8); cursor-past-EOF alarms (F11); enqueue-fail records escalate (F4); damped per (uuid, acked:lines); **scheduled — rides `cc-reaper`** (`bin/cc-reaper:125-130,322`; launchd `com.chrisren.cc-reaper` loaded) |
| Integration | | `waiting-recycle.sh:554-587` holds recycles on inbox activity + dumps mailbox tail into handoff context; `handoff-disposition.sh` exposes `mailbox_pending`; `cc-announce` VERIFIED-or-LOUD rides the verdicts; drain hooks are LIVE in every account's settings.json (07-comms-drain activated, `.done`) |

**Load-bearing harness floors** (from the v2 plan, confirmed against real escapes — trumps docs):
no external process can wake a fully-idle CC session without keystrokes or a **pre-armed in-session
background task**; a Stop `decision:block` continuation does **not** re-fire UserPromptSubmit; Stop
`additionalContext` is inert on the running version.

## 2 · Live evidence (2026-07-20 ~15:45 PT)

- **42** mail-carrying inboxes · **1,788** lines · **~1,401 unacked (78%)** · **39** of 42 boxes
  belong to dead panes. 57 files in the dir (boxes + cursors + junk), no GC ever.
- **Former-desk flooding:** `1EB2C679` 631 lines (570 from `[claude]` automated pagers, Jul 15→18);
  `D5D419C8` 206 (179 `[claude]`; its last line is the SUCCESSOR-LIVE announce for the current desk);
  `99261468` 155. Producers kept paging stale desk UUIDs for days; each box died with everything
  unacked. **Root cause is addressing, not transport** — pane-UUID-keyed boxes + producers that
  don't re-resolve after a recycle.
- **Live-but-idle rot:** the CURRENT desk `D08B4FC0` — live pane, lines=443, seen=acked=386, **57
  pending accumulating since 14:43** (reaper surfaces, supervisor pages, desk-sweep notes) because
  no human typed, the continuation loop wasn't armed, and no watcher was armed. **0 `.watching`
  heartbeats across 16 live sessions** — the entire fleet currently has no wake path.
- **Namespace junk:** `docclf-ci-coverage-blocker.md` — a 192-line status NOTE written directly into
  the mailbox dir (name-keyed; no UUID-keyed drain will ever read it; guard skips non-UUID names,
  `cc-thread` counts it); two `<uuid>.processed.md` variants; orphaned `.acked`-without-`.md`
  cursor files.
- **Guard runs but reaches no human:** `.escalated` markers + 36 `enqueue-failed-escalated` IDL
  records exist; the phone leg is inert until `04-page-channel-activate.sh` (Pushover creds,
  operator C10, still pending) and `cc-blockers`/`cc-board` read **no** comms store. The
  `AAAAAAAA-1111-…` enqueue-fail records were live manual probes of the F4 path (the bats suites
  isolate correctly — `tests/cc-inbox-guard.bats:13`, `tests/cc-notify.bats:92`).
- **Doc drift teaching v1:** `scripts/handoff-fire.sh` BACK-CHANNEL trailer (≈`:1448-1462`) still
  tells fired children that cc-notify "types the line into the originator's composer via the it2
  transport (`\r` submit …) AND records the mailbox as the durable fallback". v2 removed the
  keystroke path entirely; children mis-model delivery ("the injection is the interrupt path") and
  the "durable fallback" phrasing plausibly produced the hand-written name-keyed junk box.

## 3 · Failure inventory (root-caused)

### Receivable
| # | Defect | Evidence | Root cause |
|---|---|---|---|
| R-1 | No standing wake path — live-idle sessions rot | desk 57-pending/2 h; 0 watchers / 16 live | F6's "supervised auto-re-arming watcher" was never built as a standing floor; arming is ad-hoc (`cc-wait:8` calls await "ad-hoc, owned by nobody") |
| R-2 | No mid-turn boundary — long autonomous turns never drain | UserPromptSubmit is human-gated; Stop-fold requires the armed sentinel; fleet sessions run hours-long turns | v2 evaluated only SessionStart/UserPromptSubmit/Stop; PostToolUse was never assessed (§4) |
| R-3 | Succession strands inboxes | 631/206/155-line dead former-desk boxes | mailbox is pane-UUID-keyed; `cc-roles/desk` re-points but pending lines never migrate; no forward pointer exists |
| R-4 | No dead-box lifecycle | 39 dead boxes, 57 files, oldest Jul 15 | `cc-teardown` and `cc-reaper` have zero mailbox handling (grep-verified) |
| R-5 | Non-iTerm sessions have no inbox identity | `own_uuid` derives solely from `ITERM_SESSION_ID` | accepted floor for the iTerm fleet — name it, don't fix it |

### Sendable
| # | Defect | Evidence | Root cause |
|---|---|---|---|
| S-1 | No role addressing — and an ACTIVE lint↔tool contract break | 570 pages to a stale desk UUID; `payload-lint.sh:50` (P0-15) sanctions `--role <role>` as a blessed back-channel form, but `cc-notify` rejects `--role` as an unknown option — every brief written in the lint-blessed flag form fails at ping time | producers snapshot a UUID once; `cc-notify` never implemented the `--role` the lint already blesses; nothing re-resolves at send time |
| S-2 | Dead-target sends succeed silently forever | "mailbox only" exits 0; pagers looped for 3 days | honest verdict exists but automated callers don't read stderr; no reroute/forward |
| S-3 | No producer damping | 570 near-duplicate pages, one box | guard damps ESCALATION per (uuid, acked:lines); nothing damps SEND |
| S-4 | Doc drift (v1 semantics) | trailer text above | `handoff-fire.sh` trailer + `commands/handoff.md` partially updated; trailer missed |

### UI-present
| # | Defect | Evidence | Root cause |
|---|---|---|---|
| U-1 | Delivery invisible to the human | operator: "you see nothing" when sessions talk | `additionalContext` reaches the model only; drain emits no `systemMessage` |
| U-2 | The reader is untracked + unfiltered | `~/.claude/bin/cc-thread` is a real file (today 15:37), not a repo symlink; counts junk boxes | built ad-hoc by a peer session in another repo; never adopted |
| U-3 | No ambient unread signal; alarms reach no human surface | statusline has no mail chip; board reads decisions/backlog/pending-activation only; phone inert | v2 stopped at loud-to-disk |
| U-4 | Success is silent, only failure is loud | guard alarms on drops; working conversations render nowhere | the asymmetry `cc-thread` was built to close — now make it ambient |

## 4 · Harness capability map (provisional — see provenance)

**Provenance:** rows marked ⚑ are proven by THIS repo's battle-tested code/comments (each cite is a
real escape or a shipped mechanism — trumps docs); rows marked ◇ are assistant-knowledge
(Jan-2026 cutoff), pending the `claude-code-guide` verification pass (agent in flight at close;
fold its table here when it reports, and re-check the two ◇ rows D5/D11 depend on before building).

| Surface | Sees it | Fires | Facts + caveats |
|---|---|---|---|
| ⚑ `additionalContext` (SessionStart, UserPromptSubmit) | model only | session start / human prompt submit | the v2 delivery channel (`mailbox-drain.sh:12-13`); renders NOTHING to the human (operator-confirmed) |
| ⚑ `additionalContext` (Stop) | — | — | **INERT** on the running version (`boundary-handoff.sh:22`, learned from a real escape) |
| ⚑ Stop `decision:block` reason | both (model = next-turn input; human sees the blocked-stop notice) | turn end, when a Stop hook blocks | the desk loop + mail fold ride it (`session-continue.sh:189-190`); a `decision:block` continuation does NOT re-fire UserPromptSubmit (v2 load-bearing fact) |
| ⚑ `systemMessage` (hook JSON, top-level) | human (TUI notice) | on the emitting hook's event | already emitted at `session-continue.sh:144` (cap message); the D11 lever — ◇ exact per-event support on SessionStart/UserPromptSubmit needs the guide pass |
| ⚑ background-task completion notification | both — renders in the TUI AND re-invokes the model | when an in-session background task exits | the `cc-await-ping` wake path; the ONLY external-write→model wake (harness floor) |
| ⚑ statusline command | human (ambient) | re-runs on UI/transcript updates — event-driven, NOT timed | proven caveat in `statusline.sh:47-52`: a session inside ONE long operation renders ZERO times (telemetry-staleness lesson) — the 📬 badge (D10) inherits this; fine for idle sessions, which is where the badge matters |
| ⚑ mid-turn user messages | both | queued into the RUNNING turn alongside tool results | demonstrated in this very session (operator's mid-turn pointer); does NOT pass the UserPromptSubmit boundary → the drain does not fire on it |
| ◇ `additionalContext` (PreToolUse / PostToolUse) | model only | every tool call, including hours-long autonomous turns | believed supported on current 2.1.x — **the D5 mid-turn boundary rides on this; VERIFY before building** (D5 is already gated) |
| ◇ Notification hook (permission_prompt / idle_prompt / elicitation_dialog) | outbound only (CC → hook command) | on those TUI events | no inbound external-push-into-transcript channel exists — consistent with the v2 harness floor |
| ◇ external process → rendered transcript message | none | — | no supported API; keystrokes (banned) and context injection at boundaries remain the only external inputs |

## 5 · Design (v3) — the 100th-percentile bar

**Bar (receivable):** every message to a **live** session reaches the model within a bounded time —
≤ 1 poll interval when idle (standing watcher), ≤ next tool boundary mid-turn (if PostToolUse
supports additionalContext), next reliable boundary otherwise; a message to a **dead** session
follows the forward chain to the role successor or reroutes to the desk; nothing sits unowned
(lifecycle + guard). **Bar (sendable):** producers address roles/names that re-resolve at send
time; a dead-target send is never a silent success loop. **Bar (UI-present):** every delivery and
every channel failure renders somewhere a human actually looks (TUI transcript line, statusline,
board, `cc-thread`).

| # | Element | Closes | Sketch |
|---|---|---|---|
| D1 | **Forward chains + succession migration** | R-3, S-2 | handoff/succession writes `<old-uuid>.forward` → `<new-uuid>` in the mailbox dir; `cc-notify` follows chains at send (bounded depth, cycle-safe); the successor's SessionStart drain ALSO takes the predecessor's pending lines (one-shot migration under the lock, cursors advanced, provenance line prepended) |
| D2 | **`cc-notify --role <name>`** | S-1 | resolve `cc-roles/<name>` at send time (same file `cc-await-ping --role` already re-reads); pagers (reaper `notify_desk`, supervisor `page`, autonomy-sweep, desk-invariant) migrate to `--role desk` — the flooding class dies at the source. Also REPAIRS the live P0-15 contract break: `payload-lint.sh:50` already blesses the `--role` form that `cc-notify` today rejects |
| D3 | **Dead-target reroute** | S-2 | not-live target + no forward → tee to the desk role's box tagged `[for:<orig-uuid>]`, verdict "rerouted"; the desk is the standing triager, mail lands where triage happens |
| D4 | **Standing wake floor** | R-1 | the harness floor means only the MODEL can arm its own watcher ⇒ (a) resident-rule + `cc-wait` contract: any owned wait arms `cc-await-ping` (heartbeat proves it); (b) `mailbox-drain` additionalContext appends a one-line nudge when it detects no `.watching` at drain; (c) guard already escalates live-but-unwatched overdue mail → route that page to the DESK (D3) whose loop re-engages the target (`desk-invariant` F7 inbox re-engage, never keystrokes) |
| D5 | **Mid-turn drain boundary** | R-2 | gated on §4: if PostToolUse supports additionalContext, add `mailbox-drain.sh post-tool` (damped: only-when-pending, max-N-lines, once per M minutes) — busy sessions then drain between tool calls, which is where multi-hour autonomous turns live |
| D6 | **Dead-box lifecycle** | R-4 | `cc-reaper` sweep: owner-dead + guard-escalated + grace (48 h) → archive box+cursors to `~/.claude/mailbox/archive/YYYY-MM/` (append-preserving move, tombstone `.forward` kept); orphan-cursor GC; junk (non-UUID names, `.processed`) → `mailbox/quarantine/` |
| D7 | **Producer damping** | S-3 | shared damp helper for automated pagers keyed (target, state-fingerprint) — re-page only on state change or TTL, mirroring the notify-channel go-live pattern |
| D8 | **Trailer + docs to v2 truth** | S-4 | rewrite the `handoff-fire.sh` BACK-CHANNEL trailer: inbox transport, no composer injection, no hand-written fallback; point at `cc-notify --role`/UUID + `cc-await-ping` |
| D9 | **`cc-thread` adoption** | U-2 | move into repo `bin/` (symlink-deployed like siblings), filter to UUID-named boxes + archive/quarantine awareness + `--acked` cursor view, bats + shellcheck, keep read-only-by-construction |
| D10 | **Statusline 📬 badge** | U-3 | statusline.sh renders `📬N` (own uuid + own roles, pending>0) — two tiny file reads per refresh, muted color per TUI-visibility memory (numbers first, no dimming) |
| D11 | **Delivery renders in the TUI** | U-1, U-4 | `mailbox-drain.sh` adds `systemMessage` ("📬 N message(s) from <from-tags> — delivered to context") alongside additionalContext — the human SEES the conversation happen in the Claude Code UI (precedent: `session-continue.sh:144` already emits systemMessage); same line from the session-continue fold |
| D12 | **Board + phone** | U-3 | `cc-blockers` gains a comms store (undelivered-* / enqueue-fail-* / rerouted-to-desk) with `▶ run: cc-thread <uuid>`; operator runs `04-page-channel` (already staged C10) to arm the phone leg |
| D13 | **Hygiene** | U-2, §2 | live probes must set `CC_COMMS_ALARM_DIR`/`CC_MAILBOX_DIR` (convention + a probe wrapper); quarantine sweep is part of D6 |

**Explicitly NOT proposed:** keystroke delivery (v1's corruption bug — stays dead); a push daemon
that types into panes; changing the 1-msg-1-line contract (file-pointer convention covers long
payloads); jj/watchman-style FS watchers inside the harness (the task-notification wake already
exists and is proven).

## 6 · Phasing (v3) — build order

- **P1 — kill the flooding class (senders + succession):** D1 forward+migration · D2 `--role` ·
  D3 reroute · D8 trailer. Single-owner session (cursor/verdict contract coupling, same reasoning
  as v2 Phase 0). This alone converts ~90% of the observed loss class.
- **P2 — delivery floor:** D4 wake-floor rules/rails · D5 PostToolUse drain (if §4 confirms) ·
  D7 producer damping.
- **P3 — human plane:** D9 cc-thread adoption · D10 statusline badge · D11 systemMessage ·
  D12 board store. Parallelizable (read-only surfaces over the frozen substrate).
- **P4 — lifecycle:** D6 archive/GC/quarantine + backfill sweep of today's 39 dead boxes (archive,
  preserving every line — the 1,401 unacked lines are forensic history, never deleted).

Gate per phase: shellcheck + bats (fixture-shape parity with the real producers — one test per
suite consumes a LITERAL live-format line). Land via project-local `/ship`.

## 7 · Fixed / filed inline this session

- **D8 trailer rewrite** — `scripts/handoff-fire.sh` BACK-CHANNEL trailer now states the v2 inbox
  transport (no composer injection, no "durable fallback" hand-write invitation, trust-the-verdict
  guidance). Shellcheck clean; no test pinned the old prose (`payload-lint` asserts block PRESENCE,
  not wording).
- **v3 section + Phase 0 orchestration** integrated into `docs/plans/TWO_WAY_SESSION_COMMS_PLAN.md`.
- **Backlog item `02ba4e52389a`** — "Build v3 cross-session mail: delivery SLO + human visibility
  (P1–P4)", dod-ref = plan § v3 + this doc.
- **NOT started here (deliberate):** the P1 coupled build — single-owner session per Phase-0
  discipline; this session's goal verb is *investigate*.

## Status log

- **2026-07-20** — Investigation session (goal: cross-session mail → 100th percentile). Full
  substrate read + live forensics + harness verification; doc created; v3 design frozen as above;
  plan doc § v3 pointer added; backlog item filed for the P1–P4 build.
