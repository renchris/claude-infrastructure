# P2 — Orchestrator-Desk Two-Way Comms & Message Safety

Beat: map every desk↔session comms channel, the channel-ladder law, the verified result-return
path, and every surface where a message or completion result is silently lost.
Coverage: read the actual code of 18 of 18 in-scope assets + 6 outward callers/consumers
(hooks/notify.sh, handoff-disposition.sh, lead-reconciler.sh, cc-wait, settings.example.json,
commands/handoff.md, commands/ship.md). Empirical = read/ran; Theoretical = inferred, labelled.

## HEADLINE (one sentence)
The two-way TRANSPORT (cc-notify composer-wake + mailbox) is live and prompt-wired; the entire
"never-let-completion-go-silent" hardening layer (F1 cc-announce, F3 payload-lint, F4 exit-deadline,
F5 completion-push, F2 channel-ladder) is **built + RED-proven + GREEN-gated + landed but has ZERO
live callers** — activation (C10) never wired the tools into any recipe, hook, or daemon, so the W5
incident it was built to close (a terminal completion reaching the desk 50 min late) is
architecturally UNFIXED in the running loop.

---

## 1. Inventory

| Asset | Role in desk loop | Wiring | Depends on | Verified by | Goal | Gap |
|---|---|---|---|---|---|---|
| `bin/cc-notify` | general any-session→any-session PUSH: it2 composer inject (text+`\r`) + always-mailbox; submit VERIFIED-or-STRANDED(exit4) | prompt-only + script callers (handoff-fire, lead-reconciler page) | it2 shim, cc-sessions (name→paneUUID), jq | tests/cc-notify.bats (isolation, IT2_BIN stub) GREEN | b | G-P2-6 |
| `bin/cc-announce` (F1) | VERIFIED-or-LOUD announce; wraps cc-notify, resolves a ROLE; mailbox-only/stranded/unresolvable → alarm+exit5 | **DEAD in live loop** — only caller is completion-push.sh (itself dead) | cc-notify, `cc-roles/<role>` map | tests/cc-announce.bats + `--selftest` (stubbed cc-notify) GREEN | a | G-P2-1,2,3 |
| `bin/cc-await-ping` | modal-safe PULL: block on own mailbox linecount delta, exit on new line | prompt-only (`Bash(run_in_background)` per commands/handoff.md) | mailbox file | tests/cc-await-ping.bats GREEN | b | G-P2-10 |
| `bin/cc-bind` | BIND tier: durable ruling file + `Acked-Ruling:` content-sha trailer + fail-closed merge gate | manual (git trailer + `cc-bind gate` in a review step) | git log/hash-object | selftest 7-RED+1-GREEN, bind-gate-e2e.sh GREEN | a | — (directives, not results) |
| `scripts/completion-push.sh` (F5) | program-terminal completion → OPERATOR push via cc-announce; capture-before-notify record | **DEAD** — no caller anywhere (notify.sh, handoff-fire `--terminal`, /ship all skip it) | cc-announce, `cc-roles/operator` | tests/completion-push.bats + `--selftest` GREEN | a | G-P2-1 |
| `scripts/payload-lint.sh` (F3) | lint a successor/handoff payload for the back-channel block; SendMessage-terminal-announce → RED | **DEAD** — nothing lints a payload before firing | grep, a payload file | tests/payload-lint.bats + `--selftest` 4/4 GREEN | b | G-P2-5 |
| `scripts/exit-deadline.sh` (F4) | resolve wait/sweep deadline 3600→900 under an exit-sequence flag | **DEAD** — cc-wait/lead-reconciler don't call it; flag never touched | env/flag file | tests/exit-deadline.bats + `--selftest` GREEN | b/c | G-P2-4 |
| `scripts/comms-safety-gate.sh` | RED-provable un-hold bar F1..F5 | manual-only (not launchd/hook/CI) | the 5 tools' selftests | self (5 met·0 fail·0 todo) — CAPABILITY only | a | G-P2-8 |
| `scripts/bind-gate-e2e.sh` | cc-bind deployed-not-just-committed regression gate | manual-only | `which cc-bind` | self GREEN | a | — |
| `scripts/handoff-disposition.sh` | mailbox CONSUMER: `mailbox_pending` = mbox linecount > `.seen` cursor | prompt-only (commands/handoff.md:173,463) | mailbox `.md`+`.seen` | (no dedicated bats found) | b | G-P2-7 |
| `hooks/notify.sh` | Stop/Notification/PermissionRequest hook | **hook-enforced** (settings Stop/Notification) | afplay/osascript | none | — | G-P2-1 (human-only; never pushes desk) |
| `scripts/handoff-fire.sh --notify-back` | materializes back-channel trailer into a prompt COPY (fired peer→originator ping recipe) | prompt-wired (trailer is instructions the fired model must obey) | cc-notify on PATH in fired session | tests/notify-back.bats (dry-run TRAILER TEXT only, not e2e) GREEN | b | G-P2-10 |
| `scripts/lead-reconciler.sh` (L4) | launchd anti-entropy: reconcile 3 pid liveness rosters; page on persistent divergence | **launchd** (com.claude.lead-supervisor.plist) | cc-notify (page), rosters | supervisor-e2e.sh | b | not a completion/alarm consumer (G-P2-3) |
| `bin/cc-wait` | contracted block: `--deadline`+`--on-timeout` REQUIRED; re-observe effect on timeout | caller-supplied (prompt/script) | — | wait-contract-lint.sh | b | G-P2-4 (deadline is caller-hardcoded, not exit-deadline) |
| `~/.claude/cc-roles/{desk,operator,orchestrator}` | role→target map for cc-announce | manual (activation step 2 — DID run Jul 16) | — | — | a | **G-P2-2 (STALE: desk UUID dead)** |
| audit `§8.5 E5` (W0-W3_INTERVENTION_AUDIT.md:681+) | channel-ladder + directive-strength law | DOC (advisory) + implemented in F1/F3 | — | grep-checked by gate F2 | a | advisory except where F1/F3 run (they don't) |
| `~/.claude/mailbox/*.md` | durable RELOAD-signal fallback | written by cc-notify; read by cc-await-ping + handoff-disposition (pull) | — | — | b | G-P2-7,9 |
| `~/.claude/cc-announce-alarms/`, `completion-push/` | LOUD failure records | written by F1/F5 (never, since dead) | — | — | a | **G-P2-3 (no reader)** |

---

## 2. Mechanism (end-to-end)

### 2a. PUSH transport (LIVE, prompt-wired)
`cc-notify <name|uuid|--self> "<msg>"` (bin/cc-notify:132-137): (1) resolve target — friendly-name via
`cc-sessions --json` → `.paneUUID` (bin/cc-notify:84), else raw-UUID passthrough (bin/cc-notify:88), else
`--self` from `$ITERM_SESSION_ID`; (2) ALWAYS append `mailbox/<uuid>.md` (bin/cc-notify:120-124); (3)
`it2 session send -s <uuid> "<msg>"` then `it2 session send -s <uuid> $'\r'` — CR not LF (Ink binds Enter to
`\r`). The composer inject is the WAKE (idle→real user turn) / QUEUE (busy→next tool-result boundary); the
mailbox is the durable fallback. (4) VERIFY the SUBMIT (bin/cc-notify:148-189): capture the pane, `LC_ALL=C
grep -aF` the message head at/after the last `❯` prompt → still there = STRANDED, ≤2 CR retries then exit 4;
clear = exit 0 "VERIFIED"; unreadable = exit 0 "UNVERIFIED" (graceful). Closed pane → it2 non-zero →
"mailbox only", exit 0. Exit codes: 0 delivered/mailboxed · 3 unresolvable · 4 stranded.

### 2b. VERIFIED-or-LOUD announce ladder (BUILT, INERT)
`cc-announce <role> "<msg>"` (bin/cc-announce): resolve_role reads `cc-roles/<role>` → target
(bin/cc-announce:77-84), calls cc-notify, then classify() by stderr+rc (bin/cc-announce:87-99): only
"submit VERIFIED" → VERIFIED(0); MAILBOX/STRANDED/UNRESOLVED → retry once → `write_alarm` + exit 5
(bin/cc-announce:120-125). This IMPLEMENTS the channel ladder (§8.5 E5). It is called by nothing except
completion-push.sh, which is called by nothing.

### 2c. Completion RETURN (the FM1 axis) — transport exists, TRIGGER does not
Intended: terminal completion → `completion-push.sh fire --event …` (scripts/completion-push.sh:53-83):
write a `pending` record (capture-before-notify), push via cc-announce to `operator`, stamp `verified`
(exit 0) or `push-failed` (exit 5, LOUD). **Nothing invokes it.** Verified absent from:
- `hooks/notify.sh` — the Stop hook. `complete` event is a Purr sound only (notify.sh:40-44); desktop
  notification fires ONLY for permission/question/elicitation/plan (notify.sh:74). Never touches the desk.
- `scripts/handoff-fire.sh` `self-close --terminal` — prints "successor: none … nothing continues"
  (handoff-fire.sh:393) and runs the close chain; pushes NOBODY (activation doc: "today the operator is
  NOT pushed").
- `commands/ship.md` — no cc-announce/cc-notify/completion-push. The ship announce is still "remembered".

CONSUME side (works, but is a PULL): a pushed completion lands as (a) a composer user-turn in the desk pane
= autonomous wake IF the role UUID resolves to the live desk pane, + (b) a mailbox line = RELOAD signal.
The mailbox is drained only by `handoff-disposition.sh` (mbox linecount > `.seen`; cursor advances ONLY on
`--ack`, handoff-disposition.sh:94-97) or `cc-await-ping` — both PULL, both prompt-only. No daemon drains it.
lead-reconciler (the one launchd daemon) reconciles pid liveness rosters and pages on divergence
(lead-reconciler.sh:10-23) — it does NOT read mailbox/alarms/completion records.

Desk mid-turn / pane-gone: mid-turn → cc-notify queues into the busy composer; submit VERIFIED proves the
keystroke LANDED, never that the desk PROCESSED it (delivery≠processing, §8.5 E5 directive ladder). Pane
gone → it2 non-zero → mailbox-only → cc-announce MAILBOX → alarm+exit5 → completion-push records
push-failed+exit5 — but the alarm dir has no reader, so "LOUD" is disk-only.

### 2d. Two-way back-channel (--notify-back, LIVE prompt-wired)
`handoff-fire.sh --notify-back [UUID]` copies the prompt and appends a BACK-CHANNEL trailer telling the
fired peer to `cc-notify <originator-uuid> "HANDOFF-PING <slug>: …"` on completion/gate/blocker
(handoff-fire.sh:701-727). Originator arms `cc-await-ping <own-uuid>` via `Bash(run_in_background)` before
idling; the mailbox write wakes it (harness re-invokes on background-task exit), the injection is the
interrupt. Disposition tracked as R-PING (commands/handoff.md:476). Prompt-only both ends; no hook.

### 2e. Channel-ladder law (F2 / §8.5 E5)
Codified in docs/research/W0-W3_INTERVENTION_AUDIT.md:681-720. Two orthogonal ladders: DELIVERY
(cc-announce→cc-notify-VERIFIED > mailbox-only(RELOAD) > alarm; SendMessage-for-non-teammate sits below,
silently degrading = W5 bug) and PROCESSING (in-brief-binding > merge-gate-enforced > mid-stream-best-effort).
Enforcement: DOC (advisory) + F1 implements delivery + F3/a lints SendMessage-terminal RED. All three
enforcement legs are inert in the live loop because F1/F3 have no callers.

---

## 3. Gaps & fragilities

| ID | file:line | FM | Sev | Failure scenario | Fix sketch |
|---|---|---|---|---|---|
| G-P2-1 | completion-push.sh (no caller); notify.sh:40-44; handoff-fire.sh:393; commands/ship.md | FM1 | **P0** | a spawned/terminal session completes or ships → nothing fires completion-push → desk never woken → believes work ongoing, or learns 50 min late on reload/from operator (W5, live-unfixed) | wire `completion-push fire` into handoff-fire `--terminal` close-chain + /ship land-success + a Stop-hook path |
| G-P2-2 | ~/.claude/cc-roles/desk = `1EB2C679…` (ABSENT from live cc-sessions, ran 2026-07-18); activation doc "rebind when a pane recycles" (manual) | FM2 | **P0** | `cc-announce desk` today → dead/reused pane → alarm nobody reads, or (on UUID reuse) completion misrouted into a WRONG session reported VERIFIED (the 3-misrouted-nudge class, memory 2026-07-16) | resolve role→friendly-name→LIVE paneUUID at announce time via cc-sessions sessionId; never store a frozen uuid; auto-rebind |
| G-P2-3 | cc-announce-alarms/ + completion-push/ records — reader grep hits only never-stuck-gate.sh (attestation) | FM1 | P1 | a LOUD alarm/degrade is loud only on disk; desk/operator never sees it → "never silent" is silent-in-practice | statusline badge + lead-reconciler sweep surfacing unread alarms; delete-on-read |
| G-P2-4 | exit-deadline.sh (no caller); cc-wait:15 (caller-supplied deadline); flag never touched | FM2 | P1 | exit-window sweep never tightens 3600→900 → desk detects a stalled/finished exit up to an hour late (the exact W5 window, still open) | cc-wait/lead-reconciler default `--deadline "$(exit-deadline resolve)"`; touch/rm flag in exit + ship recipes |
| G-P2-5 | payload-lint.sh (no caller); handoff-fire.sh never lints PROMPT_FILE | FM1 | P1 | a successor/handoff payload missing the back-channel block fires un-gated (the W5 ROOT) → successor cannot announce → silent completion | lint `PROMPT_FILE` in handoff-fire.sh pre-fire; block on RED |
| G-P2-6 | bin/cc-notify:139-189 (submit-verify = keystroke, not processing); §8.5 E5 | FM2 | P1 | completion pushed to a busy/mid-turn desk is VERIFIED-delivered but may never be ACTED on (queued text can submit into /clear or a different turn context) | require a desk-side process-ACK (cc-await-ping + explicit reply), not verify-alone; treat unacked >N min as divergence |
| G-P2-7 | handoff-disposition.sh:94-97 (.seen advances only on `--ack`); prompt-only | FM1 | P2 | a session that never runs /handoff never drains its mailbox; no daemon does → pushed results rot unread | SessionStart mailbox surface + periodic sweep that flags unread mail |
| G-P2-8 | comms-safety-gate.sh:85 ("activation C10-queued"); tests stub cc-notify (isolation) | FM1 | P1 | a reader trusting "comms-safety GREEN / completion cannot go silent" is MISLED; the live loop is unprotected | add a live-wiring assertion (grep the recipes call the tools) — capability-green ≠ active |
| G-P2-9 | mailbox/*.md unbounded (8-12KB observed, no rotation) | none | P2 | slow growth; linecount deltas stay correct; no functional loss | periodic rotation/GC keyed to `.seen` |
| G-P2-10 | notify-back + cc-await-ping fully prompt-only (no hook); notify-back.bats tests trailer TEXT only | FM2 | P1 | fired model drops the ping recipe OR originator forgets to arm cc-await-ping → loop silently never closes; only tested at trailer-materialization | e2e delivery test; Stop/idle-hook fallback that auto-arms the watcher on a --notify-back fire |

---

## 4. Task candidates

| ID | action | acceptance criterion | depends-on |
|---|---|---|---|
| T-P2-1 | Activate F5: call `completion-push fire` in handoff-fire `--terminal` close-chain, /ship land-success, and a Stop-hook completion path | a terminal completion/ship produces a `completion-push/` record with verdict verified AND a composer wake in the desk pane; RED-proven with a stubbed dead desk → exit 5 | G-P2-2 fixed first (else pushes to a dead uuid) |
| T-P2-2 | Make cc-roles self-healing: resolve role→name→live paneUUID at announce time (or a rebind hook on pane recycle) | `cc-announce desk` resolves to the CURRENTLY-live desk pane even after an in-place /handoff; selftest with a recycled pane still delivers | cc-sessions sessionId resolution (pane-binding beat) |
| T-P2-3 | Surface alarms/degrades: statusline badge + lead-reconciler sweep of cc-announce-alarms/ + completion-push push-failed records | an unread alarm shows in statusline within one sweep; consumed marks it seen | lead-reconciler (wait-contract beat) |
| T-P2-4 | Wire F4: cc-wait + lead-reconciler read `exit-deadline resolve`; exit/ship recipes touch/rm the flag | under CC_EXIT_SEQUENCE the sweep cadence is 900s; flag cleared at exit-end; leak-safe on crash | exit recipe ownership |
| T-P2-5 | Wire F3: handoff-fire.sh lints the materialized PROMPT_FILE pre-fire, blocks on RED | a back-channel-less handoff payload cannot fire (exit non-zero, LOUD) | — |
| T-P2-6 | Upgrade comms-safety-gate to assert LIVE wiring, not just --selftest | gate RED while any of F3/F4/F5 lack a live caller; GREEN only when grep proves each is invoked | T-P2-1,4,5 |
| T-P2-7 | Add a desk-side process-ACK contract for terminal pushes (verify→ack, not verify-alone) | a pushed completion unacked >N min registers as a divergence the reconciler pages on | G-P2-6, wait-contract beat |

---

## 5. Cross-beat dependencies
- **Pane-binding beat (cc-bind/cc-sessions/sessionId):** G-P2-2/T-P2-2 hinge on resolving a role→LIVE
  paneUUID via sessionId (memory cc-notify-session-pane-mapping.md). cc-notify resolves name→paneUUID
  (bin/cc-notify:84), NOT sessionId — the drift fix straddles both beats.
- **Wait-contract / never-wait-on-the-dead beat (cc-wait/lead-reconciler/L2/L4):** F4 (exit-deadline) wires
  into cc-wait + lead-reconciler; the reconciler is the natural alarm-surface consumer (G-P2-3, T-P2-3).
- **Idle-classification / reaper beat (cc-classify/cc-reaper):** G-P2-6 — a completion VERIFIED-delivered but
  unprocessed makes a busy desk look idle; classification must not reap a desk holding queued completions.
- **Teardown/enumeration beat (dccbe99):** INDETERMINATE it2 enumeration is CLOSED for cc-teardown
  (return 2, never false "gone"). cc-notify uses raw-uuid passthrough for roles so DELIVERY bypasses
  enumeration; its `composer_stranded` capture (bin/cc-notify:152) degrades to UNVERIFIED(0) when blind —
  acceptable, but means a blind screen silently downgrades verification.

## 6. Adversarial self-pass
- "completion-push might be called by /wrap, /ship, or the Stop hook you didn't check." Checked all three:
  notify.sh:40-44 (sound only), commands/ship.md (no announce), handoff-fire.sh:393 (--terminal pushes
  nobody). Confirmed dead.
- "The composer-wake IS the consumer — so there's no gap." Correct that the wake path works; the gap is
  PRODUCER-side (no trigger fires completion-push), not consumer-side. Reframed the FM1 root accordingly.
- "cc-roles is fine if UUIDs are stable." Ran cc-sessions live 2026-07-18: `1EB2C679` (cc-roles/desk) is
  ABSENT from the live list. Empirically stale — not a hypothetical.
- "lead-supervisor/reconciler probably consumes the alarms." Read it: reconciles pid rosters, pages on
  divergence (lead-reconciler.sh:10-23); does NOT read mailbox/alarms/completion. Confirmed no consumer.
- "Mailbox write races?" cc-notify append (`printf >>`) is atomic <512B; a >512B message could interleave
  under concurrent senders — noted under G-P2-9 (minor; linecount semantics unaffected).

## 7. Uncertainties
- Whether the operator runs an OUT-OF-BAND activation at exit time (a non-repo script). No in-repo trace of
  steps 3-5; the role map (step 2) DID run (files dated Jul 16). If a private ~/.claude script wires the
  tools, it's invisible to a repo read — but the stale role map + empty alarm/record dirs argue it does not.
- cc-wait's every live caller and its hardcoded deadline constant (confirmed cc-wait REQUIRES --deadline;
  did not enumerate each caller's value).
- iTerm2 pane-UUID reuse policy — determines whether G-P2-2 manifests as dead-pane-alarm (likely) vs
  active-misroute (the worse, reuse-dependent tail). Theoretical on the misroute branch.
