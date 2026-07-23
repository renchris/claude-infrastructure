<!-- source: /Users/chrisren/.claude-secondary/projects/-Users-chrisren-Development-claude-infrastructure/c52fc6af-4cd6-463a-8ff2-42fe7222f0cf.jsonl
 turns=76 assistant_texts=13 last_stop=end_turn mail_injections=['SCOPE UPDATE'] -->

Saturation reached — the final call is the smoking gun. I have complete signal across all four brief questions. Composing.

---

## Comms + TUI-visibility architecture — LIVE gap map (2026-07-23)

**Method:** disk-truth reads of live stores under `~/.claude/` + transport-script internals + git branch state. All counts read live 2026-07-23 ~09:00Z. **Empirical** = live store read; **theoretical** = design-doc/spec. Nothing sent/acked/mutated.

**Headline:** the v3 P1 senders (forward chains, `--role`, reroute) LANDED (`mail-v3-p1`→`e542db4`), but every downstream plane is inert. Fleet-wide **82.9% unacked** (1899/2291 lines, *worse* than the 78% at v3-design time), the desk role points at a **dead** pane that's being flooded live, **0** wake-watchers across **21** live sessions, the phone leg is **133/133 inert**, and **no human surface renders any of it**.

---

### (a) Channel matrix — with live counts

| Channel | Producer→Consumer | Transport | Human-visible? | Ack semantics | LIVE count (07-23) |
|---|---|---|---|---|---|
| **Cross-session mail** | any session → pane/role → `mailbox-drain.sh` | append `~/.claude/mailbox/<uuid>.md`; drained at SessionStart/UserPromptSubmit → `additionalContext` | **NO** — model-only (`mailbox-drain.sh:103-105` emits `hookSpecificOutput.additionalContext`, **no** `systemMessage`) | split cursor `.seen`/`.acked`; **no sender receipt** | 48 boxes · 2291 lines · **1899 unacked (82.9%)** · acked total 392 |
| **`cc-notify --role`** (D2) | automated pagers → `cc-roles/<name>` → inbox | role file resolved at send | NO | send-side liveness verdict on stderr (read by `cc-announce`, not human) | `desk→D08B4FC0` **(DEAD)**, `operator/orchestrator→D5D419C8` **(DEAD former-desk)** |
| **`cc-await-ping`** wake | model self-arms → polls own inbox; harness task-completion re-invokes | file poll + `.watching` heartbeat | NO (wakes model) | heartbeat = wake-path proof | **0** `.watching` files · **0** mentions in `idl.jsonl` (never exercised) |
| **Supervisor pages** | `lead-supervisor.sh` → `--role desk` + `.page` file | `autonomy/pages/*.page` + `cc-notify` | banner only if attended | `.notified` marker (no ack/resolve) | 178 `.page` / 180 `.notified` · supervisor live: **swept=17 findings=8**/sweep |
| **`cc-inbox-guard`** escalation | guard sweep → `push-send.sh` + alarm | `comms-alarms/undelivered-*.json` + phone | NO | damped per `(uuid,acked:lines)` | **227 undelivered unhandled** + 60 enqueue-fail · 41 guard state files |
| **Phone/push** (Pushover) | guard/completion → `push-send.sh` | HTTP push | phone (if creds) | verdict record | **133/133 "inert / creds unset" · 0 ever "sent"** |
| **Permission banner** | harness `PermissionRequest` → `notify.sh permission` | `osascript` banner + `Funk.aiff` | **at-desk only** (local Mac) | none (ephemeral) | **954 permission + 105 question events / 12 days** (~80/day) |
| **operator-readout** (Stop) | Stop hook → close block | `systemMessage` (human TUI) | **YES** (only reliable human push) | damped by content-hash | reads pending-activation/decisions/blocked-backlog/deploy-lag — **NOT** comms |
| **statusline** | per-refresh | TUI line | YES (own session) | — | context%/effort/location — **no 📬 badge** |
| **cc-board / cc-blockers** | operator pull | terminal | YES (pull) | — | `cc-blockers` **parked on `feat/board-runnable-commands`, not on main, no live deploy**; reads no comms store |

---

### (b) Operator → agent inbound steering

- **Typing into a running pane WORKS** but blind: mid-turn text queues alongside tool results into the running turn (research doc §4 ⚑, demonstrated live). **Three losses:** (1) **no receipt** the model saw/acted on it; (2) it does **not** cross the `UserPromptSubmit` boundary, so `mailbox-drain` doesn't fire — any queued peer-mail stays undelivered; (3) if the pane sits at a **bash-prompt** (shell snapshot) or a **permission modal**, the keystrokes are captured by *that*, not the model (the exact v1-keystroke race that killed composer-injection, `cc-notify:24-27`).
- **`cc-notify` inbound**: enqueues to inbox, drained at a boundary — honest, but **role-addressed pages resolve to the dead desk box** (below), and the only "receipt" is a **send-time liveness prediction** on stderr (`delivered-to-inbox` vs `mailbox-only`), consumed by `cc-announce`, never surfaced. **No read-receipt exists in either direction** — nothing notifies a sender when `.acked` advances.
- **`/goal` trap** (memory `handoff-fire-goal-prefix-trap`): a message starting with `/goal` is parsed as the slash-command (4000-char cap) → long steers **rejected**, session idle-never-engages, silently.
- **Net:** the operator can steer a session *they are watching* by typing; steering an *unattended/background* session has no reliable, receipted path.

---

### (c) Invisibility inventory — background → TUI

| Activity | Visible where | Blind window |
|---|---|---|
| Cross-session mail delivery | model context only (`additionalContext`) | **Always** to the human — 82.9% unacked never rendered |
| Background subagent (no `team_name`, e.g. me) | nowhere until lead synthesizes | Entire run; transcript strands in `projects/*.jsonl` (memory `wave-report-harvest`) |
| Agent-Team teammate | tmux/split pane IF present | Invisible if bg-tab; pane close ≠ status |
| Wave/dispatch progress | `cc-board`/`cc-sessions` **pull** snapshot | Between pulls — no push/ambient fleet view |
| Supervisor findings (8/sweep) | `.page` file + dead desk inbox | **Never reaches a human** — pages the dead `desk` role + inert push |
| Permission stall (unattended) | ephemeral local banner | Until operator returns (beacon unwired — §d) |
| Gate/test runs in a bg session | nowhere | Until Stop-hook close of that session |
| Undelivered-mail alarms | `comms-alarms/*.json` file-only | **227 unhandled**, no surface reads them |

A true live "fleet view" would need a **push** aggregator over already-present stores (`cc-sessions` liveness + statusline `context/*.json` payloads + `pages/` + mailbox `.acked` deltas) rendered to one ambient surface — every input exists; nothing joins+pushes them.

---

### (d) Permission-stall quantification

- **Frequency (empirical):** `/tmp/claude-notify.log` — **954 permission + 105 question** prompts in 12 days (Jul 11→23) ≈ **80 prompts/day**. Each fires `notify.sh permission` → `Funk.aiff` + `osascript` banner (`notify.sh:25-28,74-75`) — **local, at-desk, ephemeral**.
- **Unattended escalation is UNWIRED.** `cc-permission-beacon.sh` is **symlinked live + merged to main**, and `lead-supervisor.sh:421-443` sweeps `/tmp/cc-permission-pending` to page — **but the beacon's `write` hook is in NO settings.json `PermissionRequest` block** (grep-verified; `:887` wires only `notify.sh permission`). Result: the sweep reads a **permanently empty dir** — **0 PERMISSION-PENDING pages, 0 MODAL/STALL in supervisor.log, 0 live beacons.** Classic staged≠loaded / landed≠deployed.
- **Agent's-own-ask backstop** (`cc-unattended-ask-guard.sh`, wired `:501`) converts a blocking `AskUserQuestion` into a `cc-decide` packet under `CC_UNATTENDED` — but **0 of 66 decision packets cite unattended/idle-strand** → unexercised (sessions likely not setting `CC_UNATTENDED`).
- **Actual unattended-stall count: UNMEASURED** (beacon never fired). Only anchor: the documented **133-min `git reset --hard` hang** (`desk-anti-hitl-2026-07-19`). To measure: wire the beacon → count `PERMPEND_DIR` entries aged ≥ `PERMPEND_NOTICE_S` (120s).
- **Compounding:** even if wired, a permission page routes to the **dead desk role** (§CFP-1) + **inert push** (§CFP-3) → it would still rot.

---

### (e) Candidate frontier problems

---
**CFP-1 · Role indirection doesn't survive succession → flooding relocated, not killed**
- **Evidence:** `cc-roles/desk → D08B4FC0` which is **not in the 21 live sessions**; `D08B4FC0.md` grew to Jul 23 01:50 (live `⚠️ SUPERVISOR PAGE … STALL?` lines) while `.acked` **frozen at 386 since Jul 20 09:15** → **423 pending, growing**; **0 `.forward` files** fleet-wide (D1 migration never used in practice).
- **Mechanism class:** distributed addressing / liveness-of-the-indirection-target; succession consistency.
- **Mitigations + status:** D1 forward-chains + D2 `--role` + D3 reroute LANDED (`e542db4`) — but succession neither repoints the role file nor writes a `.forward`; reroute-to-desk is **circular** when the *desk role itself* is the dead target.
- **Why it resists:** a crash/recycle-without-clean-handoff never updates the role or writes a forward; no component owns "is the current role-holder actually draining?" — it's a liveness-consensus gap, not a transport bug.
- **Quantified cost:** 423 stranded+growing on the *live* pager target; the entire supervisor page stream (8 findings/sweep) rots in real time.
- **Fix sketch:** liveness-verified role resolution — `cc-notify --role` refuses/repairs a target with no recent `.acked` advance or `.watching` heartbeat; a reaper re-points `cc-roles/desk` to a live pane on desk death.
- **Confidence:** high (direct live evidence). **Stale-risk:** med — a clean handoff repoints the role, but the pattern recurs on every crash-recycle.

---
**CFP-2 · Entire human plane unshipped — 82.9% unacked is invisible**
- **Evidence:** `mailbox-drain.sh:103-105` emits `additionalContext` only (no `systemMessage`); `statusline.sh` has no 📬 (grep-empty); `operator-readout.sh:59,249` reads only activation/decisions/backlog; `cc-blockers` parked off-main; **1899/2291 unacked**.
- **Mechanism class:** observability / model-only-channel gap (P3 plane D9-D12 all unbuilt).
- **Mitigations + status:** v3 §5-6 SPEC frozen; research doc explicitly "Still open: P3."
- **Why it resists:** `additionalContext` is model-only by harness design; the one proven human-visible Stop channel (`systemMessage`) exists but the drain doesn't use it; fix spans drain + statusline + board, each with its own staleness caveat (`statusline.sh:47-52`: renders 0× inside a long turn).
- **Quantified cost:** 82.9% of all mail + 227 alarms invisible; operator's own words "you see nothing."
- **Fix sketch:** D11 `systemMessage` on drain + D10 statusline badge + D12 board comms store (all spec'd).
- **Confidence:** high. **Stale-risk:** low (spec frozen, just unbuilt).

---
**CFP-3 · Phone/push escalation-of-last-resort has NEVER delivered**
- **Evidence:** `push-records` **133/133 verdict "inert" detail "creds unset", 0 "sent"**, newest 2026-07-23T08:42; `cc-inbox-guard:20,107-111` calls `push-send.sh` as the "VERIFIED phone leg" → inert; **227 undelivered alarms unhandled**; `04-page-channel-activate.sh` pending operator-C10.
- **Mechanism class:** activation gap (creds) + fail-*silent* last-resort channel.
- **Mitigations + status:** guard writes durable alarms + damps; creds activation staged, human-gated.
- **Why it resists:** needs operator to provision Pushover creds (C10); until then every last-resort escalation is a no-op **and nothing surfaces that the escalation channel itself is down** (silent inert) — and the surface that *would* surface it is the same broken set (chicken-egg).
- **Quantified cost:** 100% of phone escalations lost (133/133).
- **Fix sketch:** activate creds; OR fail-loud on inert push into `operator-readout` (the one working human channel).
- **Confidence:** high (empirical). **Stale-risk:** low.

---
**CFP-4 · No standing wake path — 21 live sessions, 0 armed watchers**
- **Evidence:** **0 `.watching`**; `cc-await-ping` mentions in `idl.jsonl` = **0**; harness floor: no external process wakes an idle CC session without keystrokes/pre-armed task (`cc-notify:22-24`).
- **Mechanism class:** harness liveness floor / cooperative-scheduling gap.
- **Mitigations + status:** `cc-await-ping` exists; D4 wake-floor SPEC'd; `mail-v3-p1` shipped a drain-nudge but arming is "owned by nobody."
- **Why it resists:** only the MODEL can arm its own watcher (structural harness floor — an external daemon cannot); nothing forces a session to arm one.
- **Quantified cost:** entire idle fleet unreachable within-poll; mail waits until next human prompt/Stop (unbounded).
- **Fix sketch:** resident-rule + hook that arms `cc-await-ping` on every owned wait; drain appends "no watcher — arm one."
- **Confidence:** high. **Stale-risk:** med (point-in-time zero, but consistent with 07-20's zero).

---
**CFP-5 · Unattended permission stalls — beacon merged+deployed but UNWIRED**
- **Evidence:** `cc-permission-beacon.sh` symlinked live + on main, but **absent from every settings.json `PermissionRequest`** (grep); `:887` wires only `notify.sh permission` (at-desk banner); **0** PERMISSION-PENDING pages, **0** live beacons; **~80 permission prompts/day**; 133-min stall precedent.
- **Mechanism class:** staged≠loaded (deployed-but-inert) + HITL-on-unattended.
- **Mitigations + status:** beacon code + supervisor sweep READY but write-hook unwired → sweep reads an always-empty dir; own-ask guard wired but 0 packets (unexercised).
- **Why it resists:** activation is a human-owned settings.json edit (like the rest of the staged spine); *and* even wired, the page sinks into the dead desk role (CFP-1) + inert push (CFP-3).
- **Quantified cost:** ~80 prompts/day with no unattended escalation; worst-case 2h+ hang (measured once); true stall rate **unmeasured** (beacon never fired — measure via `PERMPEND_DIR` age once wired).
- **Fix sketch:** wire beacon `write`→PermissionRequest, `clear`→PostToolUse/Stop/SessionEnd; then fix the sink (CFP-1/-3).
- **Confidence:** high on the wiring gap (grep-verified). **Stale-risk:** low.

---

**Blockers / uncertainties (explicit):**
- `cc-sessions --json` live-set is my liveness authority for "D08B4FC0 dead"; if it is account-scoped a pane *could* exist elsewhere — but `.acked` frozen 3 days makes it a dead *consumer* regardless (claim is robust).
- `cc-blockers` returned empty on grep because it's **absent from repo `bin/` on main** (parked on `feat/board-runnable-commands`) and has no live deploy — so "board reads no comms store" rests on the research doc + `operator-readout` sharing the same 3 stores, not a direct read of a live `cc-blockers`.
- Permission-stall *frequency* is bounded (80/day prompts) but unattended-*stall* rate is genuinely unmeasured (the instrument was never turned on).
- `idl.jsonl` grep for `cc-await-ping` = 0 is strong but idl may not log arming events at all; corroborated by 0 `.watching` (independent signal), so the "never exercised" claim holds on two legs.

**Adversarial pass integrated:** verified (not assumed) that (1) the desk box is a *live-flooded dead consumer* not a static strand — `.md` mtime Jul 23 vs `.acked` mtime Jul 20 + live SUPERVISOR PAGE tail; (2) operator mid-turn typing *does* reach the model (a working inbound path) so the gap is receipts/boundary not delivery; (3) the beacon's non-firing is a *wiring* gap not a code gap — it's on main + symlinked, just not in settings.json.