---
status: in-progress
---

# Two-Way Session Comms — Implementation Plan

> **v2 (2026-07-20) — eliminate keystroke injection.** The v1 feature below is landed and works, but its
> transport is the problem v2 fixes: every delivery (`cc-notify`, reaper surface, supervisor page,
> `--notify-back`, `cc-announce`) lands via **it2 keystroke injection** into the target pane, which RACES
> the user's live input — at a bash prompt the surface text runs as a command (`(eval):1: parse error`,
> dozens hit the operator today); at a Claude prompt it corrupts their half-typed message + cursor. v2
> moves delivery to a **durable inbox drained at a safe boundary via hooks** (arrives as context, never as
> keystrokes) with the **existing `cc-await-ping` background watcher** as the non-keystroke idle-wake. See
> **§ v2 — Eliminate keystroke injection** at the end of this doc. The v1 sections below are unchanged
> (historical); read them for the mailbox/registry primitives v2 builds on.

**Created**: 2026-07-10 · **Repo**: `claude-infrastructure` · **Research**:
[`docs/research/HANDOFF_BACKCHANNEL_2026-07-10.md`](../research/HANDOFF_BACKCHANNEL_2026-07-10.md)
(verdict: YES, live-proven; the it2 pane-injection transport already exists — this is the *plumbing*).

**Status**: ✅ **COMPLETE — landed on `origin/main`, verified green** (2026-07-18). All four components
shipped via clean commits (NOT the stale `feat/two-way-session-comms` branch — see Status log for SHAs
and the do-not-land warning). Re-verified this session: `bats` **38/38 pass**, `shellcheck` **clean**.
Nothing left to build.

**Scope (frozen)**: build a clean, performant, general **any-session → any-session message primitive**,
with `/handoff`'s `--notify-back` as its first consumer. A session (fired, teammate, or standalone)
can ping ANY other live session by a friendly name (or raw pane UUID) at any time, waking an idle
originator or queuing into a busy one, with a modal-safe mailbox fallback. 100th-percentile bar:
reuse the proven transport, zero new heavyweight deps, graceful degradation, tested.

**Non-goals**: no new transport (the it2 python-API shim is the transport, proven detached); no
cross-machine delivery (pane UUIDs are machine-local by design); no persistent message queue/broker
(mailbox files are the async fallback — "fix observed problems," not a broker).

---

## Design (4 components)

1. **Session registry** — each CC session records `{paneUUID, name, cwd, account, pid, startedAt}`
   on `SessionStart` (hook → append/update `~/.claude/sessions/<paneUUID>.json`), and prunes its
   entry on `SessionEnd`/exit. Gives name→UUID resolution + a `cc-sessions` lister. Stale entries
   (pane gone per `it2 session list`) are swept lazily on read. Name defaults to the cwd basename +
   short-UUID; user-overridable.
2. **`cc-notify` CLI** (`bin/cc-notify`, symlink → `~/.claude/bin/`) — the general primitive:
   `cc-notify <name|uuid|--self> "<message>"`. Resolves the target via the registry (raw UUID passes
   through), delivers via the it2 shim (`session send -s <uuid> "<msg>"` then `session send -s <uuid>
   $'\r'` — **`\r` not `\n`**, CC's Ink composer only submits on CR, research §mechanism), and ALSO
   appends to `~/.claude/mailbox/<uuid>.md` as the fallback record. Flags: `--list` (sessions table),
   `--self` (print own pane UUID), `--mailbox-only` (skip injection), `--from <name>` (attribution).
   Target pane closed/recycled → it2 exits non-zero → cc-notify still writes the mailbox and exits 0
   with a "delivered to mailbox only" note (never a hard failure).
3. **`--notify-back [name|uuid]` in `handoff-fire.sh`** — sugar for the handoff case. Forwards the
   originator's pane UUID (`FIRING_SID`, already computed at `handoff-fire.sh:496`; defaults to it)
   into a COPY of the fired prompt as a back-channel trailer telling the fired session the exact
   `cc-notify <uuid> "HANDOFF-PING <slug>: <status>"` recipe to run on completion / decision-gate /
   blocker. Research §"exact handoff-fire.sh change" has the ~10-line spec — implement it via
   `cc-notify` (not raw it2), so the recipe is one clean line.
4. **Originator-side await helper** `cc-await-ping [<uuid>]` — a `run_in_background`-friendly poller
   on `~/.claude/mailbox/<uuid>.md` (default: own UUID) that exits when a new line lands, so the
   harness's task-completion notification wakes the originator even if composer injection mislands
   (the modal-safe pull complement to the push). Bounded timeout, prints the new line(s).

**Data dirs**: `~/.claude/sessions/` (registry), `~/.claude/mailbox/` (fallback records). Both
git-ignored, created on first use.

---

## Step 0 — setup + baseline

1. `cd /Users/chrisren/Development/claude-infrastructure`; `git switch -c feat/two-way-session-comms`
   (branch — do not commit to `main` directly).
2. Read `docs/research/HANDOFF_BACKCHANNEL_2026-07-10.md` (transport, the `\r`-not-`\n` gotcha, the
   `--notify-back` spec, the mechanism table) + `scripts/handoff-fire.sh` (how it uses the it2 shim
   today: `FIRING_SID:496`, injection recipe `:141-145,176-178`, arg parser `:277-284`).
3. Inspect `~/.claude/bin/it2 --help` / its source to confirm the exact `session send` / `session
   list` subcommand surface before coding against it.

---

## Phase 0 — orchestration

The 3 build tasks are **tightly sequential** (T2 needs T1's registry format; T3 needs T2's CLI) and
total ~350 LOC of bash in ONE repo/domain — so a **single focused implementation session building
T1 → T2 → T3 in order** is the clean choice (Agent-Teams coordination overhead buys nothing when the
tasks can't parallelize). IF splitting is preferred, use 3 sequential teammates (one per phase,
spawn-after-merge), never parallel — the deps forbid it. Either way: commit per phase, gate each
(shellcheck + the bats tests), no push.

---

## Phase 1 — session registry + `cc-sessions`

- `hooks/session-register.sh` (SessionStart): write `~/.claude/sessions/<paneUUID>.json` with
  `{paneUUID, name, cwd, account(CLAUDE_CONFIG_DIR basename), pid, startedAt}`. Pane UUID from
  `$ITERM_SESSION_ID` (strip the `wNtNpN:` prefix → the bare UUID the it2 shim wants). Name =
  `$(basename "$PWD")-<short-uuid>` unless `CC_SESSION_NAME` is set.
- `hooks/session-deregister.sh` (SessionEnd): remove the file.
- Register both in the settings-template hooks wiring (`settings-templates/`), mirroring existing
  hook registration; document that existing sessions predating this won't be registered until restart.
- `bin/cc-sessions`: list registry entries, sweeping stale ones (cross-check `it2 session list`),
  columns name/uuid/cwd/account/age.
- **Gate**: `shellcheck` clean; a bats test that a fake registry entry lists + a stale one is swept.

## Phase 2 — `cc-notify` CLI

- `bin/cc-notify` per Design §2. Resolution order: exact name → raw-UUID passthrough → `--self`.
  Delivery: it2 `session send` text + CR; ALWAYS also append `~/.claude/mailbox/<uuid>.md`
  (`<ISO> [<from>] <message>`). Closed-pane fallback = mailbox-only, exit 0 + stderr note.
- `--list` delegates to `cc-sessions`; `--self` prints own bare UUID; `--mailbox-only`, `--from`.
- Symlink `~/.claude/bin/cc-notify → bin/cc-notify`.
- **Gate**: shellcheck; bats — name resolves to UUID; raw UUID passes through; `\r` submit uses the
  two-call recipe (assert the it2 invocation shape via a shim stub); closed pane → mailbox-only exit 0.
- **Live smoke** (post-merge, separate — like the research PoC): from a second pane, `cc-notify`
  this session by name; confirm the message lands in the composer.

## Phase 3 — `--notify-back` + await helper + docs + tests

- `handoff-fire.sh`: add `--notify-back [UUID]` (arg parser ~`:284`), and after `FIRING_SID` is
  derived (~`:497`) append the back-channel trailer to a COPY of the prompt file (never mutate the
  caller's), instructing the fired session to run `cc-notify <uuid> "HANDOFF-PING <slug>: <status>"`
  on completion / decision-gate / blocker. Default UUID = firing pane; `__self__` sentinel. Point
  `PROMPT_FILE` at the copy before `QP=` (~`:445`).
- `bin/cc-await-ping [<uuid>]`: bounded background poller on `~/.claude/mailbox/<uuid>.md`; exits on a
  new line. Symlink to `~/.claude/bin/`.
- **Docs**: update `commands/handoff.md` § Autonomous fire — a new bullet documenting `--notify-back`
  + the `cc-notify`/`cc-await-ping` pair (this is the two-way loop the skill's item 1 gap referenced),
  and note the `\r`-not-`\n` invariant. INTEGRATE (Edit), never rewrite.
- **Gate**: shellcheck; bats — `--notify-back` materializes the trailer with the right UUID + recipe
  and never mutates the caller's prompt file.

---

## 100th-percentile requirements (the bar)

- **Reuse, don't reinvent**: the it2 python-API shim is the ONLY keystroke channel (detached-proven;
  raw osascript AppleEvents fail silently detached — research §mechanism, `handoff-fire.sh:141-145`).
- **`\r` not `\n`** everywhere a CC composer is the target (Ink binds Enter to CR only).
- **Graceful degradation**: closed/recycled/missing pane never hard-fails — mailbox fallback + clean
  exit. A stale registry entry is swept, not trusted.
- **Idempotent + fast**: registry writes are single-file, O(1); `cc-notify` is two shim calls + one
  append; no polling in the push path (polling only in the opt-in `cc-await-ping`).
- **No secrets, no PII in mailbox/registry**; both dirs git-ignored.
- **Tested**: shellcheck-clean, bats coverage per phase, + a live cross-pane smoke for cc-notify.

## Constraints (HARD)

- Work on `feat/two-way-session-comms`; commit per phase (atomic, explicit paths); **do NOT push** —
  `/ship` (or `git push`) is the user's call. Never `--no-verify`.
- Do NOT stage the pre-existing `hooks/post-file-edit.sh` change or `accounts.json` (other work).
- Do NOT modify `~/.claude/bin/it2` (the transport is reused as-is unless a gap is proven — if so,
  STOP and surface it).
- INTEGRATE doc edits (Edit `commands/handoff.md`), never rewrite.
- Live smoke tests inject into REAL panes — target only scratch/second panes, never the user's active
  pane without saying so.

## References
- Research + mechanism table + the exact `--notify-back` code:
  `docs/research/HANDOFF_BACKCHANNEL_2026-07-10.md`.
- Transport in use today: `scripts/handoff-fire.sh` (`:141-145`, `:176-178`, `:496`, `:277-284`).

## Status log
- **2026-07-10** — Plan created from the live-proven research. NEXT: fresh-context session runs
  Step 0 → Phase 1 (registry) → Phase 2 (cc-notify) → Phase 3 (--notify-back + docs + tests),
  commits per phase on `feat/two-way-session-comms`, stops for the user's `/ship`.
- **2026-07-18** — ✅ **DONE — all four components landed on `origin/main` and re-verified green.**
  Shipped via **clean, comms-scoped commits** (a subsequent session split the work out of the
  plan's `feat/two-way-session-comms` branch, which had accreted unrelated `accounts`/`limit-recover`
  work, and landed only the comms slice):
  - **Phase 1** — session registry + `session-register.sh` / `session-deregister.sh` + `cc-sessions`
    lister: `827f164`, evolved by the P8 registry-forensics ruling `7b2f701` (see deviation below).
  - **Phase 2** — `cc-notify` general any-session→any-session primitive over the it2 transport:
    `3c232d3`, hardened by `98a3dd9` + `3b12107` (submit-VERIFY: the injected line is confirmed to
    have actually submitted — strand detection, CR retry, `exit 4` on a stranded composer — closing
    the "verifier could only abstain" hole).
  - **Phase 3** — `handoff-fire.sh --notify-back` + `cc-await-ping` + `commands/handoff.md` §8
    ("Two-way — back-channel ping"): `7acef7e`, extended by `5d2eb36` (`cc-await-ping --role`
    per-cycle re-resolve + `wiring-all` bin symlinks).
  - **Verification (this session, `origin/main`)**: `bats tests/{cc-notify,notify-back,session-registry}.bats`
    → **38/38 pass**; `shellcheck` on all delivered bins + hooks + `handoff-fire.sh` → **clean**
    (only info-level SC2009 suggestions). Data dirs (`~/.claude/sessions`, `~/.claude/mailbox`, the
    live `cc-registry`) live outside the repo; `~/.claude/bin/{cc-notify,cc-sessions,cc-await-ping}`
    symlinks are in place.
  - **Deviation from Phase 1 (by design, not a gap)**: the plan said "register **both** hooks in the
    settings template." Only `session-register.sh` is template-wired (`settings.example.json:265`);
    `session-deregister.sh` exists + is tested but is intentionally **not** template-wired. The P8
    ruling (`7b2f701`, "a reaper keyed on deadness erases the forensics") made registry retention an
    **age** decision (`CC_REG_RETAIN_H`, 24h), not an end/liveness one — so you wire *register*
    (accrue evidence) but not *deregister* (don't erase a dead session's row on exit), and the
    self-healing age-sweep in `cc-sessions` keeps addressing correct (a dead pane is hidden from
    resolution, retained for forensics). Full activation of the registration spine is deliberately
    operator-gated per `docs/rulings/P8-GO.md`.
  - **Follow-on already built ON TOP** (separate items, not this plan): the `comms-safety F1–F5`
    layer — `cc-announce` VERIFIED-or-LOUD primitive, channel-ladder law, back-channel payload-lint
    (`08dad8c` → `01b20eb`) — is the hardened application layer over this primitive.
  - **⚠️ Do NOT land `feat/two-way-session-comms`.** It is **stale/superseded** — `origin/main` is
    strictly newer (landing the branch would REVERT the submit-verify + P8 hardening, e.g. −60 lines
    of `cc-notify`), and the branch also carries unrelated `accounts`/`limit-recover`/`hooks` commits
    out of this plan's scope. cc-backlog `9775f356eb03` closed with the landed SHAs as evidence.

## Resume (v1)
**v1 is COMPLETE and landed on `origin/main`** (see the 2026-07-18 Status log entry for SHAs +
verification). Do NOT rebuild v1, and do NOT land the stale `feat/two-way-session-comms` branch
(superseded). v2 (below) is the ACTIVE work. To re-verify v1:
`bats tests/{cc-notify,notify-back,session-registry}.bats` + `shellcheck bin/cc-notify bin/cc-sessions
bin/cc-await-ping hooks/session-register.sh hooks/session-deregister.sh`.

---

# § v2 — Eliminate keystroke injection (2026-07-20)

**Scope (frozen):** a notification to a Claude session ALWAYS lands as a message/context the session
reads, and NEVER injects into the user's live input (text + cursor), whether the pane is at a Claude
prompt OR a bash prompt, and robust to pane state (idle, busy, mid-command, actively typing). Migrate
the delivery paths (`cc-notify` → reaper surface, supervisor page, `--notify-back`, `cc-announce`) onto
the safe channel. Keep a **fail-loud guard** (a dropped/undelivered message alarms, never silently
vanishes). **Preserve the wake** (the desk is still woken to triage) — via a non-keystroke channel.
Tests: delivery-lands-as-message-not-keystroke · delivery-survives-busy-pane · undelivered-alarms.
Land via the project-local `/ship`.

## Research findings — the non-keystroke delivery design space

The corruption source is **`it2 session send`** keystroke injection into the target pane. Three sites:
`bin/cc-notify:133-134` (the primitive — the central chokepoint), `scripts/handoff-fire.sh` (LAUNCH
prompt into a *fresh* pane — legit, no live input to corrupt — plus succession-announce which goes
*through* cc-notify), and `scripts/desk-invariant.sh:141-142` (`reprompt()` — a stall-recovery re-prompt,
a separate last-resort un-stick, NOT a routine notification). **`cc-notify` is the single migration
point:** reaper `notify_desk`, supervisor `page`/`page_permpend`, `--notify-back`, `cc-announce`, dispatch,
boot-resume, autonomy-sweep ALL deliver through it. Fix `cc-notify` → every path is fixed at once.

Candidate channels evaluated (harness semantics confirmed via claude-code-guide + the repo's own
battle-tested hook comments):

| Channel | Wakes idle? | Corrupts input? | Verdict |
|---|---|---|---|
| **it2 `session send`** (today) | yes | **YES (the bug)** | ❌ remove |
| **Inbox + `UserPromptSubmit` `additionalContext`** | no (rides next user turn) | no | ✅ delivery (interactive) |
| **Inbox + `SessionStart` `additionalContext`** | no (rides resume/start) | no | ✅ delivery (resume) |
| **Inbox + `Stop` `decision:block` reason** | keeps an active session awake to triage | no | ✅ delivery (end-of-turn / desk loop) |
| **`cc-await-ping` background watcher → task-completion notification** | **yes** (the only non-keystroke idle-wake) | no | ✅ wake (already built) |
| MCP / Remote-Control / `FileChanged` hook | maybe | no | ⏳ undocumented on our version → not relied on |

**Load-bearing harness facts** (design turns on these):
- **No external process can wake a fully-idle CC session without keystrokes OR a pre-armed in-session
  background task** (confirmed). ⇒ the idle-wake MUST be the target's own armed `cc-await-ping`; there is
  no "push into an idle pane" that is both non-keystroke and external. This is a harness floor, not a
  design gap.
- **A `Stop` `decision:block` continuation does NOT re-fire `UserPromptSubmit`** (confirmed). ⇒ a desk
  looping via `session-continue` (Stop-block) never hits the `UserPromptSubmit` drain, so in-loop mail
  MUST be delivered on the **Stop** channel.
- ~~**`Stop` `additionalContext` is empirically INERT on the running version**~~ (`boundary-handoff.sh:22`,
  learned from a real escape — trumps the doc which says "active"). ⇒ the Stop channel uses
  `decision:block` (which `session-continue`/`completion-assert`/`anti-deference` all rely on), never
  `additionalContext`.
  **SUPERSEDED 2026-08-08 (measured, 2.1.220): `additionalContext` now delivers on Stop.** The
  conclusion is UNCHANGED — keep using `decision:block` — but for a new reason. `additionalContext`
  is not the cheap alternative it would need to be: its own schema says *"the conversation continues
  so the model can act on it"*, so it forces a turn and increments the same consecutive-block counter
  as `decision:block`. It is also weaker for compliance, because the model may read an out-of-band
  hook-attributed injection as a prompt-injection attempt and refuse it (observed).
  Evidence: `docs/research/final-response-shaping-2026-08-08.md`.
- **The cursor already exists**: `~/.claude/mailbox/<uuid>.seen` holds a line-count; `handoff-disposition.sh`
  reads `mailbox_pending` = (`wc -l <uuid>.md` > `<uuid>.seen`) and its `--ack` advances it. The drain
  MUST reuse this SAME cursor, so "delivered" and "pending" agree across both systems by construction.
- **`cc-await-ping` PRINTS the new mailbox line(s) to stdout on wake** — so when it fires, the mail
  content arrives *inside* the task-completion notification. For the idle desk it is delivery **and** wake
  in one; the hooks cover the non-watcher cases.

## The mechanism (chosen)

The mailbox (`~/.claude/mailbox/<uuid>.md`, append-only, `<ISO> [<from>] <message>` per line) is already
written by `cc-notify` on EVERY send (today labeled "fallback"). v2 **promotes the mailbox to the primary
transport** and removes keystroke injection. Delivery = **drain the mailbox at a safe boundary**; wake =
the target's armed watcher. One cursor (`<uuid>.seen`) makes delivery exactly-once across all channels.

1. **`hooks/mailbox-drain.sh`** (NEW) — one script, event-dispatched (arg `session-start`|`prompt`|`stop`):
   reads lines after `.seen`, formats them, and delivers. Advances `.seen` to EOF on delivery (idempotent,
   exactly-once, and consistent with `handoff-disposition`'s `--ack`).
   - `SessionStart` / `UserPromptSubmit` → emit as `additionalContext` (reliable). Advance `.seen`.
   - `Stop` → if pending, `decision:block` with the mail as the reason (wakes an active session to triage;
     the only in-loop channel). Advance `.seen`. **Coexistence:** a shared `hooks/lib/mailbox-pending.sh`
     helper lets the other Stop-blockers yield one turn when mail is pending (see Phase 2) so at most one
     hook blocks — additive, fail-safe (yield = allow-stop = the safe direction).
2. **`bin/cc-notify`** — REMOVE `it2 session send` entirely. New job: resolve target → **enqueue to the
   mailbox** (durable) → classify deliverability for an honest exit code. Liveness via `cc-sessions`
   (live registry) / `it2 session list` (read-only, no keystrokes): target is a LIVE session → exit 0
   "delivered to inbox" (a drain/watcher will surface it); target not live (closed/recycled) → exit 0
   "mailbox only" (a dead inbox — the `cc-announce` alarm path still fires); unresolvable → exit 3;
   **mailbox unwritable → exit 5 LOUD** (a message that can't even persist must alarm, not warn). No more
   "submit VERIFIED"/strand/exit-4 (there is no keystroke to strand).
3. **`bin/cc-announce`** — update `classify()`: VERIFIED = "delivered to inbox (live session)"; MAILBOX
   (target-not-live) / UNRESOLVED / write-fail = LOUD alarm (unchanged VERIFIED-or-LOUD contract; the W5
   "RELOAD ≠ WAKE" lesson holds — a dead inbox is not a delivery). The mailbox-write to a LIVE session IS
   a wake now (the target's watcher pulls it), so mailbox-to-a-live-target is no longer a degrade.
4. **Wake** — unchanged mechanism, now primary: the desk (and any `--notify-back` originator) keeps a
   background `cc-await-ping` armed while idle; a `cc-notify` mailbox write makes it exit → task-completion
   notification re-invokes the session with the mail in the notification body. Non-keystroke, already built.
5. **Fail-loud guard `bin/cc-inbox-guard`** (NEW) — sweeps mailboxes; for any whose owning session is LIVE
   (registered + pane/pid alive) and whose oldest undelivered line (`.seen` < EOF; line ISO timestamp)
   is older than a deadline (default 600s), escalates via `push-send.sh` (the VERIFIED phone leg) + writes
   an alarm record. A message enqueued but never drained CANNOT silently vanish. Wired into the existing
   autonomy/reaper cron; `--selftest` RED-proves the alarm fires.

**Out of scope / noted:** `desk-invariant.sh:reprompt()` (stall-recovery keystroke un-stick — a separate
last-resort actuator, gated by stall detection, not a routine notification; forcing a turn on a *wedged*
session is exactly what inbox-drain cannot do). `handoff-fire.sh` fresh-pane LAUNCH injection (no live
input to corrupt). Both stay; documented so the remaining keystroke sites are explicit, not hidden.

## Phase 0 — orchestration (single focused session, by design)

Same call as v1 Phase 0, same reason: the pieces are **one tightly-coupled contract** — the `.seen` cursor
semantics, `cc-notify`'s new exit codes, `cc-announce`'s `classify()`, the Stop-hook yield-protocol, and
their tests all interlock. Parallel teammates would race the shared contract (exit codes / "verified"
meaning / cursor) and create merge hazard on the exact interfaces that must stay coherent. Total ≈350–450
LOC across `bin/cc-notify` (rewrite ~−40/+40), `bin/cc-announce` (~+15), `hooks/mailbox-drain.sh` (NEW ~120),
`hooks/lib/mailbox-pending.sh` (NEW ~25), 4 safety-hook 2-line guards, `bin/cc-inbox-guard` (NEW ~90),
tests. Under the 500-LOC single-owner threshold and non-parallelizable ⇒ **single session, commit per
phase, gate each** (shellcheck + bats). Research fan-out (already done) used background subagents only.

## Phase 1 — mailbox-drain hook + cursor (delivery, no keystrokes)
- `hooks/mailbox-drain.sh`: shared `drain(uuid)` → lines `(.seen, EOF]`; `SessionStart`/`UserPromptSubmit`
  → `additionalContext`; `Stop` → `decision:block`. Advance `.seen`. Env seams `CC_MAILBOX_DIR`. Fail-safe:
  every path exits 0 except the Stop-block (which is the intended block). No `set -e`.
- `hooks/lib/mailbox-pending.sh`: `mailbox_has_pending <uuid>` + `mailbox_drain_recently_fired <uuid>`
  (breadcrumb `<uuid>.draining`, 2s freshness) → `mailbox_defer_to_drain <uuid>` (0 = should-yield).
- Wire `mailbox-drain.sh` into `settings-templates/settings.example.json` on SessionStart (first),
  UserPromptSubmit (first), Stop (first in obj-1).
- **Gate**: shellcheck; bats — delivery-lands-as-message (additionalContext shape) + cursor advances
  exactly-once + Stop emits decision:block.

## Phase 2 — cc-notify transport swap + Stop-hook coexistence + cc-announce
- `bin/cc-notify`: remove it2 send; enqueue + liveness-classify + exit codes (§ mechanism 2). Keep
  `--mailbox-only`, `--from`, `--self`, `--list`. Update the header contract.
- Add the `mailbox_defer_to_drain` yield-guard (source `hooks/lib/mailbox-pending.sh`) to
  `session-continue.sh`, `completion-assert.sh`, `anti-deference-nudge.sh`, `boundary-handoff.sh` — top of
  the actuation path, additive, exit 0 on yield.
- `bin/cc-announce`: update `classify()` per § mechanism 3.
- **Gate**: shellcheck; bats — cc-notify never calls `session send` (stub asserts 0 invocations),
  delivery-survives-busy-pane (busy/any pane → mailbox written, composer untouched), cc-announce
  VERIFIED-or-LOUD holds on the new outputs; the 4 guards yield when mail pending.

## Phase 3 — fail-loud guard + docs + full gate
- `bin/cc-inbox-guard` + `--selftest`; wire into the autonomy/reaper cron.
- Update `commands/handoff.md` §8 + `bin/cc-notify`/`cc-await-ping` headers: the transport is now
  inbox-drain, NOT keystroke; the `\r`-not-`\n` note becomes historical.
- **Gate**: shellcheck all touched bins/hooks; `bats tests/` green (updated cc-notify/cc-announce/
  notify-back + the 3 new suites); then project-local `/ship`.

## Critique fixes (adversarial red-team, 2026-07-20) — FOLD BEFORE SHIP

A 5-lens adversarial critique (wf_ac5f975e-1c0) of the frozen design returned **14 survivors** — verdict
"sound WITH fixes, not a rethink." The foundation holds (cc-notify IS the single chokepoint; fresh-pane
launch never touches a live composer; the drain jq-escapes peer content; the Phase-1 breadcrumb ordering
closes the basic parallel race). But the fail-loud + wake guarantees and the operator's literal complaint
were NOT fully met. The two architectural fixes SIMPLIFY the design:

- **(A) Split the delivery cursor from the ack/guard cursor.** `<uuid>.seen` = EMITTED (advanced by the
  drain, AFTER emitting — emit-before-advance). `<uuid>.acked` = CONSUMED (advanced only when a boundary
  proves the model took a turn: immediately on the reliable additionalContext channels; lag-one-cycle for
  the Stop channel). The fail-loud guard keys on `acked < EOF`, NEVER the eager `seen`. Closes F2, cures
  F11's guard-blindness, gives F5 its clean "delivered" definition, retires the raw-EOF `--ack` writer.
- **(B) Fold in-loop Stop delivery into `session-continue` (the ONE hook already blocking the in-loop
  desk); DROP the standalone mailbox-drain Stop blocker + the 4-hook yield-guards + the 2 s TTL.** The
  drain handles SessionStart + UserPromptSubmit only. Removes the multi-block blast radius (F10), the
  fragile wall-clock sync, and the re-arm starvation (F14) in one move. Idle/mid-turn mail is caught by
  the F6 watcher on arm; the looping desk by the fold; interactive/resume by additionalContext.

| # | Sev | Defect (file) | Fix |
|---|---|---|---|
| **F1** | must | TOCTOU: concurrent append between the drain's read and `.seen`-advance → silent drop; hot target = desk | `flock` a single atomic snapshot; serialize every `.seen` RMW; standardize `grep -c ''` (not `wc -l`) everywhere |
| **F2** | must | `.seen` advances at emit-time; guard keys on same cursor → dropped mail (hook-kill / double-block) invisible | **(A)** split emitted/acked; emit-before-advance |
| **F3** | must | `cc-announce classify()` fail-open `else VERIFIED` reports exit-5 write-fail as a confirmed wake | rc5→WRITEFAIL (DONE) + flip terminal default to fail-CLOSED (alarm) + selftest/bats exit-5 case (DONE) |
| **F4** | must | exit-5 (inbox unwritable) is swallowed by every fire-and-forget caller → "loud" only in its number | `cc-notify` self-escalates on write-fail: alarm record in a durable dir + best-effort `push-send.sh` |
| **F5** | blocker | VERIFIED = "registered-live" equates liveness with a wake → W5 recreated under a VERIFIED label | Award VERIFIED only on a confirmed WAKE PATH (armed `cc-await-ping` for the uuid, or drain-confirmed via `acked`); live-but-unwatched idle → a distinct degrade `cc-announce` alarms on |
| **F6** | must | idle-desk wake unimplemented: `cc-await-ping` baselines at `wc -l` (off `.seen`), one-shot, nothing re-arms | seed baseline from `mailbox_seen`; advance `.seen` on fire; a SUPERVISED auto-re-arming desk watcher (guard kicks/re-arms before phoning the operator) |
| **F7** | must | `desk-invariant reprompt()` still injects text+Enter into the desk's LIVE composer on the stale branch (gated only on assistant-idle ≈ operator-returns-and-types) — the operator's verbatim complaint | ABORT reprompt if the composer is non-empty/changed since last sweep; for the pure-stale branch, enqueue the resume to the desk's OWN mailbox instead of keystrokes; keystroke only a proven-frozen cap-modal |
| **F8** | high | `cc-inbox-guard` fails SILENT on an unclassifiable owner (not-registered ⇒ treated dead ⇒ no escalation) | liveness by PANE existence (`it2 session list`), run `cc-reconcile` first; INDETERMINATE owner ⇒ ESCALATE (fail-loud) |
| **F9** | high | Stop drain has no cap/latch; a swallowed `.seen`-write failure re-blocks the same mail every Stop forever | (mostly retired by **B**) + `mailbox_advance_seen` RETURNS failure; folded-delivery caps like its siblings; on advance-fail allow-stop + escalate |
| **F10** | med | single-blocker is unenforced convention across 5 files + fragile 2 s TTL | retired by **B** (no competing blocker) |
| **F11** | med | cursor-past-EOF (GC/rotation/recycle) → drop + guard blind | clamp `.seen>cur`→0 re-deliver (DONE in lib) + guard ALSO alarms on `.seen>EOF`; GC = atomic compact-and-reset under the lock |
| **F12** | med | uniform 600 s guard deadline loses v1's instant urgency for confirmed-stuck classes | class-specific short deadline (~0–60 s) for permission-pending / coordination-hang / crashed / DEAD |
| **F13** | minor | multi-line message breaks line==message + ISO-per-line age-parse | collapse newlines→spaces (DONE in cc-notify) |
| **F14** | low | mail Stop replaces `session-continue`'s reason → re-arm reminder starved → `.count` hits cap, loop abandons | retired by **B** (fold keeps the re-arm reminder in the same reason) |

**Ship gate:** none of Phase 2/3 lands until A, B, F1, F3, F4, F5, F6, F7, F8, F9 are in. F10/F13/F14 are
retired by A/B; F11/F12 are cheap hardening folded into `cc-inbox-guard`.

## v2 Status log
- **2026-07-20** — v2 opened. Research → design frozen → Phase 1 built → adversarial critique (14 fixes) →
  **all must-fixes folded + implemented + tested + gate-green.** Commits (branch `feat/twoway-comms-100`):
  - `19b35ae` research+design · `6cb7c7f`+`e420e30` Phase-1 drain+lib+tests · `a721ce0` critique-fixes design.
  - `a1f241e` **(A)** split cursor `.seen`/`.acked` + **(F1)** locked atomic `mailbox_take` + **(B)** fold
    Stop delivery into `session-continue` (drop the standalone Stop blocker + 4-hook yield-guards) +
    **(F6a)** `cc-await-ping` seeds from `.seen` + **(F9)** advance-returns-failure.
  - `8df066a` **(F5)** wake-path VERIFIED (a `<uuid>.watching` heartbeat, not mere liveness — the W5
    lesson) + **(F3)** `cc-announce` fail-CLOSED + **(F4)** `cc-notify` exit-5 self-escalation.
  - `72e0d37` **(F7)** `desk-invariant` re-engages via the inbox, NEVER keystrokes a live composer (the
    operator's literal complaint — the third + last keystroke site eliminated).
  - `1bc1601` **`cc-inbox-guard`** — the fail-loud backstop (F5/F6/F8/F11/F12/F4): undelivered-to-a-live-
    session mail escalates to the phone; keys on `.acked` so an eager `.seen` can't hide a loss.
  - `efb6267` wiring: drain hooks on SessionStart/UserPromptSubmit; guard rides the reaper cadence;
    delivery-survives-busy-pane proof. `6f2f83a` docs §8.
  - **Gate:** `shellcheck -S warning` clean on all touched bins/hooks/scripts; the three required suites
    (delivery-lands-as-message-not-keystroke = cc-notify 17/17 + mailbox-drain 10/10; delivery-survives-
    busy-pane; undelivered-alarms = cc-inbox-guard 12/12) + cc-announce 10/10, desk-invariant 6/6,
    completion-push, handoff-fire, cc-reaper 35/35 all green.
  - **Keystroke sites eliminated (3/3):** `cc-notify` (the chokepoint — reaper/supervisor/notify-back/
    cc-announce all ride it), `desk-invariant reprompt()`, and any composer-inject path. `handoff-fire`'s
    FRESH-pane launch (empty new pane, no live input) is the only remaining `session send` — legitimately
    out of scope.
  - **Post-land (operator C10):** activate the drain hooks in the LIVE `settings.json` across the 4 config
    dirs (the template is wired; the live per-account settings are the operator's step, like boundary-handoff).
    NEXT: land via project-local `/ship`.

---

# § v3 — Delivery SLO + human visibility (2026-07-20)

**Why a v3:** v2 made the transport safe (no keystrokes) and honest (split cursor, fail-loud
guard) — but live forensics the same day show it has **no service level**: 1,788 lines ever sent,
~1,401 (78%) never consumed; 39 of 42 mail-carrying inboxes belong to dead panes (former-desk
boxes: 631/206/155 stranded lines from producers paging stale UUIDs); the live desk sat on 57
unacked pages for 2+ hours with 0 watchers armed fleet-wide; and NOTHING renders delivery to the
human — `additionalContext` is model-only, the guard is loud-to-disk with an inert phone leg, the
Board reads no comms store. Full gap analysis + evidence + design: **`docs/research/cross-session-mail-2026-07-20.md`**
(the SSOT for v3 — elements D1–D13, failure inventory R/S/U, harness capability table).

**Scope (frozen):** cross-session mail is (1) reliably RECEIVABLE — bounded-time delivery to live
sessions (standing wake floor; mid-turn PostToolUse boundary if harness-supported), forward-chain +
succession migration for recycled panes, dead-box lifecycle (archive, never delete); (2) reliably
SENDABLE — `--role` addressing resolved at send time, dead-target reroute-to-desk, producer
damping, v1 doc-drift purged; (3) HUMAN-VISIBLE in the Claude Code UI — `systemMessage` on every
drain, statusline 📬 badge, `cc-thread` adopted into the repo as the first-class reader,
comms-alarms on the Operator Blocker Board.

## Phase 0 — orchestration (v3)

- **P1 = ONE single-owner session** (same ruling as v2 Phase 0: forward-chain semantics,
  `cc-notify` verdicts, drain migration, and their tests are one tightly-coupled contract —
  parallel teammates would race the cursor/verdict interfaces). ≈250–350 LOC touching
  `bin/cc-notify`, `hooks/mailbox-drain.sh`, `hooks/lib/mailbox-pending.sh` (+`.forward`
  primitives), `scripts/handoff-fire.sh` (succession pointer), producers (`bin/cc-reaper`
  `notify_desk`, `scripts/lead-supervisor.sh` `page`), bats. Under the 500-LOC single-owner
  threshold.
- **P2 piggybacks P1's owner** (wake-floor rule text + `cc-wait` arm + drain nudge are small and
  touch the same files); the PostToolUse drain (D5) is a separate ~60-LOC follow-on once the
  harness table confirms support.
- **P3 = Agent Team, 3 teammates, worktree-isolated** (2+ code-writing tasks, all decoupled
  read-only surfaces over the frozen substrate): T1 `cc-thread` adoption + filters + bats · T2
  statusline badge + drain/fold `systemMessage` · T3 Board comms store + lint. Briefs ≤150 lines,
  pre-greped line ranges, verbatim stop-on-issue clause per the agent-teams checklist. D12's
  phone arm stays operator C10 (`04-page-channel`).
- **P4 = single small session** (reaper/teardown sweep + archive + quarantine + backfill), after
  P1 lands (archive must honor `.forward` tombstones).

**Phases** (build order + rationale in the research doc §6):
- **P1 — kill the flooding class:** ✅ **LANDED 2026-07-20** (`e542db4`, branch `mail-v3-p1`) —
  forward chains + succession migration (D1) · `cc-notify --role` + pager migration (D2) ·
  dead-target reroute (D3) · `handoff-fire.sh` trailer rewrite (D8 — done earlier in the
  investigation session, branch `xsession-mail-100`). Single-owner session (cursor/verdict contract
  coupling — same reasoning as v2 Phase 0).
- **P2 — delivery floor:** drain no-watcher nudge (D4) ✅ **LANDED with P1** · producer damping (D7)
  ✅ **LANDED with P1** · **REMAINING:** wake-floor resident rule + `cc-wait` arm contract (D4's
  rule half) · PostToolUse mid-turn drain (D5) — **gated on a live smoke-probe, NOT on the docs**
  (see the §4 verdict below).
- **P3 — human plane (parallelizable):** `cc-thread` adoption + filter + bats (D9) · statusline
  badge (D10) · drain `systemMessage` (D11) · Board comms store + `04-page-channel` phone arm —
  operator C10 (D12).
- **P4 — lifecycle:** archive/GC/quarantine + backfill sweep of the 39 dead boxes (D6, D13);
  1,401 unacked lines are forensic history — archived, never deleted.

## v3 Status log
- **2026-07-20** — v3 opened by the goal-directed investigation session (`xsession-mail-100`):
  research doc written, D8 trailer fix applied, backlog item filed for the P1–P4 build. The
  investigation deliberately did NOT start the coupled P1 build (single-owner session per Phase-0
  discipline).
- **2026-07-20** — **P1 BUILT + LANDED** by the single-owner session (`mail-v3-p1` → `e542db4`,
  gate green: shellcheck + 1308/1308 bats, content-verified on `origin/main`). Shipped: D1 (three
  primitives in `hooks/lib/mailbox-pending.sh` + succession `.forward` at `handoff-fire.sh:1094` +
  SessionStart adoption in `mailbox-drain.sh`) · D2 (`cc-notify --role`, producers migrated) ·
  D3 (dead-target reroute) · D4 nudge · D7 (`hooks/lib/page-damp.sh`, wired into reaper +
  supervisor). New suites: `mailbox-forward.bats`, `page-damp.bats`, `payload-lint-tool-parity.bats`.

  **Learnings (carry into P2–P4):**
  - **§4 harness verdict — docs CONFIRM PreToolUse/PostToolUse `additionalContext` and universal
    `systemMessage`, but that does NOT open the D5 gate.** This repo holds a counter-example in the
    same field: Stop `additionalContext` is in the docs' supported list and is INERT on 2.1.207
    — **and on 2.1.220 it DELIVERS (measured 2026-08-08), which makes this example even stronger:
    the same field read INERT then and live now, so a doc citation dates neither. See
    `docs/research/final-response-shaping-2026-08-08.md`** —
    (`boundary-handoff.sh:21-22`). A citation proves the documented contract, not the running
    binary. **D5's real gate is a live smoke-probe** — a throwaway PostToolUse hook emitting a
    sentinel, confirmed visible to the model — and that is P2's FIRST step. D11 (systemMessage) is
    lower-risk: a shipped in-repo emitter (`session-continue.sh:144`) already proves it renders.
  - **Two test stubs encoded the OLD argv shape and silently pointed at the wrong field** once
    paging moved to `--role`: `tests/cc-reaper.bats` captured `$2`, `supervisor-e2e.sh` captured
    `$1`. Both now capture shape-robustly / resolve `--role` as the real tool does. **Any P3 work
    touching a producer's argv must re-check its stubs** — a positional-index fixture fails silently.
  - **The repo gate runs BARE `shellcheck` (includes `info`), stricter than `-S warning`.** An
    `SC2015` finding turned the first land red. Verify with bare `shellcheck` before landing.
  - **Adoption ordering is load-bearing:** own take → migrate → second take, so inherited mail is
    surfaced in the SAME boundary. Deferring it to the next boundary would reproduce the latency
    the SLO exists to kill.
  - **Damping's whole contract is the fingerprint** — state words only, never a clock/counter. A
    timestamped fingerprint disables damping while looking correctly wired (pinned by a test).
  - Damp state lives under each pager's own `PAGEDIR/damp`, inheriting existing test-isolation
    seams; a live-tree default would have tests writing real markers.

---

# § v4 — Delivery under machine load (2026-07-25/26)

**Backlog:** `0298535c1584` (cc-notify times out under load). Two sessions converged on this incident
independently; the record below is the COMPOSED result, and names which half came from where.

## The incident

2026-07-26T04:40-04:45Z, load 13-14. Three `cc-notify` sends to LIVE peers (`E057D768`, `6AABD5A3`,
`F6D8D465`) each exceeded a 90s caller timeout and delivered **nothing** — verified by grepping each
target's transcript for the message body (0 hits). `cc-notify --list --json` exceeded 120s. The desk
could not warn the fleet at the exact moment contention made warning necessary: the advisory silently
no-op'd and peers kept burning cycles on a theory already refuted. The durable backlog was the only
channel that worked.

## Half 1 — RESOLVER AVAILABILITY (landed by the sibling session: `6991dfa3`, `1bc3cc97`, `65e6bb54`)

Measured root cause: `it2 session list --json` is an IPC call into iTerm2's Python API, which
serializes requests; it exceeded 120s at 2% CPU (blocked, not computing). cc-notify reached it on
**both** hot paths — name resolution and the liveness verdict — so even the documented workaround
("pass the full 36-char UUID") still blocked. Fixed by reading `~/.claude/cc-registry/*.json`
**directly** (liveness by `kill -0`, no fork, no IPC), bounding every remaining it2 call
(`CC_IT2_TIMEOUT_S`, default 5s), and splitting the exit codes so an outage stops being reported as a
user error: **3** = target genuinely unknown · **4** = resolver unavailable · **6** = ambiguous uuid
prefix. Measured 72s+ → 0.048s by name; `--list` 72s+ → 6.5s.

## Half 2 — THE CALLER CONTRACT (this session)

Half 1 made cc-notify's **own** rc honest. It cannot make the rc a **caller** sees honest: `timeout`
reports 124 whatever the child exits with. Reproduced against the post-rewrite binary:

```
$ CC_IT2_TIMEOUT_S=60 timeout -s TERM 3 cc-notify <uuid> "killed mid-send"
rc=124 · stderr: (nothing) · message actually persisted: YES
```

A caller could only guess, and both guesses are wrong in a different direction: "undelivered" re-sends
a message that landed, "delivered" loses one that did not. So every terminal path now prints a
machine-parseable token ahead of the (unchanged) human sentence, and a TERM/INT/HUP trap prints it too
— stderr being the only channel a bound leaves open:

```
cc-notify: verdict=<delivered|mailbox-only|unverified|unresolvable|degraded|ambiguous|undelivered
                    |interrupted> enqueued=<0|1> uuid=<u> [reason=…]
```

`enqueued=1` is the load-bearing field: the message is durably in the inbox whatever happened to the
liveness verdict or to the process. `cc-announce` reads it — rc 124 + `enqueued=1` → recorded degrade
(the delivery stands); without it → alarm as undelivered. Neither retries: whatever killed the send is
not undone by repeating it a second later, and a caller whose own bound just expired has no budget for
a second attempt. `rc 6` (ambiguous) likewise alarms without a retry. **`rc 4` deliberately KEEPS its
retry** — an unreadable registry is transient in a way a wrong name is not, matching cc-notify's own
"retry, do NOT treat as a bad address" guidance. All four are pinned, plus a control proving the retry
loop still exists where a retry can help.

## v4 Status log

- **2026-07-25/26** — Half 1 landed by the sibling session (see the three SHAs above; registry-direct
  resolution, bounded it2, rc 3/4/6, partial-uuid round-tripping).
- **2026-07-26** — Half 2 built here: `verdict=`/`enqueued=` token on every terminal path + the signal
  trap (`bin/cc-notify`), and the rc-124/4/6 classifier + scoped no-retry (`bin/cc-announce`,
  selftest 7 → 12). 10 tests added; 8 RED-proofed against trunk, 2 are controls that must pass on
  both trees.

  **Learnings:**
  - **The convergence itself is the lesson.** This session built a full competing mechanism — bounded
    + memoised + disk-cached probes over `cc-sessions` — before discovering the sibling had landed a
    registry-direct rewrite that removes the IPC entirely. Theirs is strictly better (0.048s vs a
    bounded 5s degrade), so the mechanism half was **stood down**, preserved on
    `wt-0298535c1584-superseded-mechanism`, and only the genuinely-additive half was composed on top.
    Adjudicated the way the parallel-fixer protocol says: by running this session's own tests against
    the sibling's landed code, not by comparing intentions.
  - **The exit codes collided.** Both sessions independently invented an exit code for "the resolver
    did not run" — this one used **6**, the sibling used **4** and gave **6** to ambiguous prefixes.
    A merge that had "resolved" cleanly would have shipped two contradictory meanings for one code.
    Re-fetch and READ the trunk delta before assuming a conflict is textual.
  - **An honest rc is not a reachable rc.** Fixing exit-code semantics inside a tool does nothing for
    a caller that bounds it — `timeout` overwrites the rc unconditionally. Any tool a caller may bound
    needs its outcome on a channel the bound cannot overwrite; stderr plus a trap is that channel.
  - **Verify a bounded-caller claim by REPRODUCING it against the current binary.** The rc-124 gap was
    confirmed by running the sibling's landed code under `timeout -s TERM`, not inferred from reading
    it — which is also how the "message actually persisted: YES" half was established.

---

## v5 — the alarm store was 40% test fixture data (backlog `817faf3a4968`, 2026-07-29)

`~/.claude/autonomy/comms-alarms` held **1287 records, 522 of them (40.5%) written by a bats suite
into the operator's LIVE directory**. Every one was the same literal triple —
`{"kind":"enqueue-failed","target":"AAAAAAAA-1111-2222-3333-444444444444","msg":"cannot persist"}`
— which is what `tests/cc-notify.bats` passes at its three inbox-unwritable tests. The suite
fixtured `CC_REGISTRY_DIR` and `CC_MAILBOX_DIR` but not `CC_COMMS_ALARM_DIR`, so two of those three
tests fell through to the `$HOME` default on every run (2 records/run × ~260 runs).

This is **distinct from the suite-side hermeticity work** (`9cc78e748e7e`, the `$HOME` ratchet). That
work fixes the SUITE. Nothing cleaned the PRODUCT, and the damage outlives the suite fix.

**Measured harm, both real:**
1. `cc-inbox-guard` phones the operator once per `enqueue-fail` record, then marks it `.handled`.
   520 `.handled` fixture records = **520 pages about a failure that never happened**, each filed as
   though triaged.
2. The ground-up rebuild method requires re-deriving every constant from primary disk truth. Rows 3
   (cross-session comms), 5 (autonomy dispatch) and 10 (operator surface) all derive from stores like
   this one, so each silently read a **40%-fixture denominator**. Row 3 caught it only by
   cross-checking; a row that trusted the store would have designed against fabricated failure rates.

**The fix, three parts:**
- **`hooks/lib/comms-alarm.sh` — the write chokepoint.** All three producers (`cc-notify`
  enqueue-fail, `cc-await-ping` cursor-fail, `cc-inbox-guard` undelivered) write through
  `comms_alarm_write`. A write whose actor resolves to a bats/fixture context is stamped
  `test_origin`, **diverted** into `<dir>/test-leak/`, and shouted about on stderr with rc 1.
  Fixture data can no longer reach the live root *at all* — contamination is structurally
  impossible rather than detected late.
- **`test_origin` makes records self-identifying.** `cc-inbox-guard` now excludes them **by field**
  instead of pattern-matching a magic UUID, so the paging harm is closed at the reader too.
- **`bin/cc-comms-alarm-sweep`** — `--audit` / `--assert-clean` / `--sweep [--dry-run]` /
  `--selftest`. Quarantine is **archival**: records move to `quarantine/<stamp>/` with a
  rule-stamped `manifest.jsonl`, non-clobbering, and the source is unlinked only once the
  destination is confirmed present.

**Why the enforcement is the write path and not a lint.** A lint over the tree would make every
author answerable for every other author's suite (the fleet-wide hard stop). A lint over the *store*
would block every land for as long as the operator's live directory stayed dirty. Neither is
enforcement; the chokepoint is. `--assert-clean` exists as an auditable verdict, deliberately **not**
wired into `run_gate` for exactly that reason.

**Learnings:**
- **Two plausible classifiers were built and BOTH rejected on evidence — each would have destroyed
  real operator telemetry.** (a) *"the target appears as a literal in `tests/*.bats`"*: a test author
  had copied a REAL pane UUID into a fixture, so `D08B4FC0-…` (256 genuine `undelivered` records)
  matched. (b) *"the target is structurally synthetic"*: `DESK-UUID-1` is not a UUID at all and owns
  23 genuine records — a real name-keyed mailbox really did sit 17 messages deep for 16896s. So
  origin is decided by **narrow literal rules tied to a producer known to exist (or known not to)**,
  never by the shape of a token. A record matching no rule is KEPT. Under-sweeping leaves a countable
  residue; over-sweeping destroys the only evidence of a real delivery failure.
- **The chokepoint was RED-proved independently of the suite fix.** Original suite + original bin →
  `root=1, leak=0`. Original *unfixed* suite + new bin → `root=0, leak=1`, stamped
  `test_origin:"bats:cc-notify.bats"`. The guarantee does not depend on suite cooperation — which is
  the point, since a leak is by definition a suite that forgot to cooperate.
- **`IFS` set to a control character does not split under bash 3.2.** Joining the sweep list on
  `\001` and iterating `for f in $LIST` yielded ONE joined word with the delimiters deleted, so the
  move loop ran zero times while a *correct* census printed above it — "quarantined 0 record(s)"
  under `R1 enqueue-fail=1`. `bash -n` and shellcheck both pass it, and zsh splits it correctly, so
  an agent's shell tool cannot reproduce it. NUL-separated `read -r -d ''` is the idiom that works.
- **A fail-loud backstop must not be turned into a production abort to fix a test-hygiene problem.**
  Every one of these call sites is fire-and-forget (`|| true`). The divert returns a real rc and
  shouts, but never aborts the caller — and each producer keeps its original inline write as a
  fallback, so the backstop can never become *weaker* than it was before it had a chokepoint.

---

## v6 — the OFF-BOX arm: this stack acquires a network transport, on the send side only (2026-08-07)

**Design + measurements live in `docs/plans/CLOUD_OBSERVABILITY.md` §9** (with §6.1–6.7 for the
evidence and §7.1 for the per-row controls). Recorded here because it changes a premise this whole
plan was built on, and a reader of v1–v5 would otherwise not know to look.

**The premise that changed.** `CONCURRENCY_PROGRAM.md` §S5a established that this stack is
local-filesystem-only and that *"a sandbox can reach none of it"* — `cc-notify` appends to
`~/.claude/mailbox/<pane-uuid>.md`, liveness is `kill -0` on a local pid, and none of it has a network
transport of any kind. Measured 2026-08-07: **the send side now has one.**

```text
claude -p "<message>" --cloud <session-id> --output-format json   →  {"ok":true,"session_id":…,"url":…}
```

Headless, no pty, present on 2.1.215/219/220 (absent on the pinned 2.1.114). Not an accident of
argument parsing — the bundle's own success telemetry is `tengu_remote_send_headless_success` with
`entry_point: "cloud_attach_headless"`.

**What this does and does not change for this plan:**

- **`cc-notify` gains a fourth address KIND, not a fourth resolver layer.** The three layers (role
  file → forward chain → pane uuid) all terminate in a local inbox file; an off-box target has neither
  a pane uuid nor an inbox, so `--cloud <id>` dispatches *before* the liveness classification and
  refuses on an undeclared id (`cc-cloud is-offbox`). Design: §9.2.
- 🚨 **`--receipt` must return UNKNOWN off-box, never 0.** This plan's own DELIVERED-IS-NOT-READ
  invariant is enforced by the `<uuid>.seen` line-count cursor, and there is no cursor off-box.
  `{ok:true}` means **queued**. Treating a queue ack as a read receipt would re-create exactly the
  false-confidence v1–v5 spent five revisions removing.
- **The receive side is unchanged and stays asymmetric.** cloud→here has no push path — this box has
  no reachable endpoint, and a cloud VM may push only its own working branch. It remains `cc-bus`
  shards over git plus `cc-cloud`'s O1–O5 observables: pull, and nothing arrives until someone syncs.
  Do not try to symmetrise it; the asymmetry is network topology, not a design gap.
- **UNPROVEN, and blocked on one operator action.** That a message *reaches* a live session is not
  demonstrated — it needs a real `session_…` id, and no programmatic fire path is open today (CLI
  create is blocked on connecting GitHub at `claude.ai/code`; the routines `/fire` endpoint is proven
  to exist but needs a web-minted bearer token). Interactive attach is refused
  `not enabled for your account` on **all four** accounts — an Anthropic-side rollout. So v6 is a
  *design*, validated only as far as "the transport exists, parses, and needs no TTY".

---

## 2026-08-09 — three MEASURED loop failures in one reso session, and the one that is a design race

A `reso-management-app` lead (`wt-cc-234834-28059-886`) ran the fire → ping → wake loop four times
in one night. **It failed three different ways, none of them the way the docs anticipate.** All three
are measured, not inferred; the fourth fire worked perfectly, which is what makes the contrast usable.

### F-1 · A peer can die without ever reaching the retire mechanism

`wt-rum-iad-endpoints-895` was killed mid-work — last assistant message *"Typecheck green. Lint
reports 126 pre-existing repo-wide errors — attributing before I drive anything."*, then nothing. Its
transcript carries **zero `Prompt is too long`**, `cc-reaper` logged **`keep wt-rum-iad-endpoints-895
[active] — never-reap cause`**, and there was no jetsam/lowmem event. It exited cleanly enough to
print CC's `Resume this session with: claude --resume …` banner, and **its pane stayed open at a
shell prompt**.

That last fact is the discriminator: `self-close` closes the pane and refuses a dirty tree
(`handoff-fire.sh:5621`). An open pane + a dirty tree proves **`self-close` was never invoked at
all** — the peer did not violate the protocol's ordering, it never reached the protocol. It left 339
lines uncommitted with a dead author.

**Consequence for the trailer, and it is small but real:** the SELF-RETIRE directive
(`handoff-fire.sh:5613-5623`) enforces durability (self-close refuses dirty) and ordering
(retire is step 2), but the **announce is a parenthetical** — *"When your work is finished (and you
have pinged back if asked to)"*. Durability and retirement are mechanical; the ping is advisory
prose. **Retire should be conditional on announce the way it is already conditional on a clean
tree** — i.e. `self-close` should refuse, or at minimum warn loudly, when a `--notify-back` was armed
and no ping was ever sent from that pane.

### F-2 · Both ends of the loop were TERMed together, from outside the harness

The lead's own `cc-await-ping` exited **144** at the same moment. `cc-await-ping:41-43` documents
exactly what that means and it is not arithmetic: *"144 = the whole process GROUP was TERMed (the
wrapper died) — a harness sentinel… 144 also proves the SIGTERM came from OUTSIDE the harness:
every harness-initiated kill resolves the task with its own code BEFORE signalling, so it can never
surface as 144."* So an external SIGTERM took the watcher and (on the same minute) the peer.

**The lead did not notice it was deaf.** The tool says the right thing —
*"the wake path for [uuid] is now DOWN … If you are going idle, RE-ARM"* — but that text rides
**stderr of a background task the harness labels `failed`**, and a lead that reads "failed" as noise
stays deaf indefinitely. **A lead must never infer liveness from its own watcher's absence of
complaint.**

### F-3 🚨 · The drain hook and the ping watcher SHARE one cursor, so the watcher is structurally starvable

**This is the design defect, and it is the one that would have hung the lead forever.**

The fourth fire (`wt-rum-iad-resume-897`) executed the protocol **perfectly**: landed `9da394a9c`
content-verified, pinged at `00:56:08`, then self-closed. Durable → announce → retire.

**The lead's armed watcher never fired.** Post-mortem: `886.seen = 3`, `886.acked = 3`,
`mailbox lines = 3`. `hooks/mailbox-drain.sh:13` states the mechanism — *"Deliveries here advance
ONLY the .seen (emitted) cursor"* — and `cc-await-ping` polls that **same shared `.seen` cursor**.
The drain ran first (a `UserPromptSubmit`), surfaced the ping as `additionalContext`, and advanced
`.seen` past it. The watcher then polled an empty delta forever: **alive, armed, and permanently
silent.** `.acked = 3` confirms a turn provably carried the mail.

So the ping was *delivered* and the wake was *lost*, and the two facts are indistinguishable from
the lead's side. The operator surfaced it by asking; nothing in the loop did.

**Why this is not merely "the drain already told you":** the drain's delivery is passive context in
an already-running turn. The watcher's delivery is an **event that re-invokes an idle lead**. A lead
that goes idle *after* a drain-consumed ping is unreachable by either path — the drain has nothing
left to emit and the watcher has nothing left to see. That is the forever-hang.

### What is already BUILT for this, and the premise every implementer must check first

🚨 **Do not build a death-watcher. One exists, is RED-proven, is landed on trunk, and is merely
UN-ACTIVATED.** `docs/NEVER-WAIT-ACTIVATION.md`: *"The five-layer build (L0..L4) is complete,
RED-proven, and landed on trunk; `scripts/wait-safety-gate.sh` is fully GREEN (13 met · 0 failed ·
0 NOT BUILT). What remains is activation — wiring the built tools into the live runtime — which is
C10 (human-only) by policy."* L1 is `bin/cc-deathwatch-kqueue` + `scripts/lead-deathwatch.sh`
(kqueue `EVFILT_PROC`/`NOTE_EXIT`, fires within ~1ms of child exit, with a `{pid,start-time}`
recycling guard so a recycled pid cannot read as false-liveness). Tests: `tests/lead-deathwatch.bats`.

The activation queue confirms it is not live: 6 pending-activation scripts un-run, 5 rotting >24h.

**So the honest split for whoever picks this up:**

| | Status | What is actually needed |
| --- | --- | --- |
| **L1 death-watch** | BUILT, RED-proven, NOT activated (C10 human-only) | stage the activation; do NOT rebuild |
| **F-3 cursor race** | **NOT built — this is the new work** | the drain and the watcher need cursors that cannot starve each other, OR the watcher must wake on drain-consumed mail |
| **F-1 announce-before-retire** | partially enforced (durability yes, announce no) | make the ping a precondition of `self-close`, not prose |
| **F-2 deaf-lead** | tool says the right thing on a channel a lead ignores | a `verdict=killed`/144 must reach the lead as something it ACTS on |

**The transferable rule, stated for the next reader:** *a delivered message and a woken reader are
different events, and a system that conflates them will report success while the reader sleeps.*
