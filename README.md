<div align="center">

<img src="assets/banner/v6c-dusk-line.svg" width="900" alt="An animated banner that loops seamlessly every four minutes. The words claude-infrastructure stand in a dusk sky above the words sessions run each other, legible at every moment of it; a crescent moon and three tiers of stars sit to the left, and banded clouds drift behind. Below, the Claude Code creature — an orange pixel-art figure with two square eyes and four legs — walks a dark ground that scrolls beneath it, leaving one continuous line of footprints. Three things happen. At four seconds it puts on a wizard's hat — a stepped cone rising to a point, a bright band at its base, and a wide brim drooping at the ends — holds out a wand tipped at both ends, flicks it, and a second, smaller creature arrives in a burst of light where the wand was pointing; the walker turns its eyes to watch, hands it a pale letter, and the letter comes back with a green face — the finished work — before the smaller creature leaves in a second burst. At seventeen seconds a gate arm drops across the path ahead; the walker settles, the ground pulls backward by exactly one footprint, the walker re-walks the step it was sent back over, and the ground then runs at double speed to make the distance up. At twenty-six seconds the walker looks up out of the frame at you, and half a second later the whole world stops — six seconds in which nothing moves but three blinks — after which the ground runs at treble speed to clear the time it spent waiting. Two more things happen in the sky, both rare enough to be missed on a short visit. At sixty-two seconds a meteor falls through the open sky away from the type — it brightens, burns out in mid-air rather than leaving the frame, and the faint ionised trail it leaves behind fades on for a second and a half after the head has gone. At two and a half minutes five faint lines draw themselves one after another between six of the stars already in the field, each star brightening as its line arrives; the finished figure holds for a moment and then fades away rather than un-drawing.">

### `~/.claude` becomes a system you deploy — and the sessions become the schedulers.

[![sessions](https://img.shields.io/badge/sessions-5%2C709-d4af37?style=flat-square&labelColor=161b22)](#4-nothing-a-session-did-dies-with-it)
[![hooks](https://img.shields.io/badge/hooks-69%20across%2012%20events-d4af37?style=flat-square&labelColor=161b22)](#3-autonomy-is-bounded)
[![tests](https://img.shields.io/badge/bats%20tests-2%2C358-d4af37?style=flat-square&labelColor=161b22)](#5-the-whole-system-deploys-from-git)
[![accounts](https://img.shields.io/badge/accounts-4%20isolated-d4af37?style=flat-square&labelColor=161b22)](#2-parallel-work-cannot-collide)

[**1 · Sessions run each other**](#1-sessions-run-each-other) · [**2 · No collisions**](#2-parallel-work-cannot-collide) · [**3 · Bounded autonomy**](#3-autonomy-is-bounded) · [**4 · Nothing is lost**](#4-nothing-a-session-did-dies-with-it) · [**5 · Deploys from git**](#5-the-whole-system-deploys-from-git) · [**6 · The next ceiling**](#6-the-ceiling-is-the-interface-not-the-machine) · [**Install**](#install)

</div>

Claude Code reads everything it does — permissions, hooks, commands, agents — from `~/.claude`.
But `~/.claude` is machine state: unversioned, unreviewable, and the moment a second session starts,
the two share one git index, one binary, and one operator's attention. **So how do you run many at
once, safely, unattended?**

Make `~/.claude` a *deployment* of a git repo — and make the sessions themselves the schedulers.
That is this repo: **1,134 files, ~269,000 lines**, held to ground truth by a **4,564-test** bats suite
and exercised across **~6,900 sessions**.

<div align="center">

<img src="assets/demo/handoff-live.webp" width="900" alt="Screen recording of one real iTerm2 window in three captioned beats. One: a real Claude session runs handoff-fire.sh with --split-right --notify-back, and the pane splits. Two: a second Claude session boots in the new pane, reads its brief, gets origin/main = bebd9580, and reports the back-channel ping as verdict=delivered reason=wake-path-armed before running self-close --terminal. Three: the ping arrives inside the originator's own chat as PING RECEIVED FROM PEER with the peer's message, and the peer has closed its own pane — the window is back to one.">

<sub><b>An unedited screen recording — two real Claude sessions, one window.</b> A session fires a peer, the pane <b>splits</b>, the peer answers <code>origin/main = bebd9580</code> and <b>pings back</b>; the ping arrives <b>inside the originator's chat</b> (<code>PING RECEIVED FROM PEER</code>) and the peer <b>closes its own pane</b>. One human keystroke: the first prompt. <a href="assets/demo/handoff-live.mp4">Full-resolution video</a> — 1920×1144, 60 fps.</sub>

</div>

| | The property | What it removes |
|---|---|---|
| **1** | [**Sessions run each other**](#1-sessions-run-each-other) | You are no longer the scheduler. Sessions open, message, and retire one another — and page you only when a human must decide. |
| **2** | [**Parallel work cannot collide**](#2-parallel-work-cannot-collide) | A worktree per writer, an account per lane, and exactly one machine-wide lock on landing. |
| **3** | [**Autonomy is bounded**](#3-autonomy-is-bounded) | 69 hooks on 12 lifecycle events refuse the calls that lose work — including a false "done". |
| **4** | [**Nothing a session did dies with it**](#4-nothing-a-session-did-dies-with-it) | Every Write, plan, task and transcript outlives the pane that made it. |
| **5** | [**The whole system deploys from git**](#5-the-whole-system-deploys-from-git) | No drift, no un-reviewable machine state, and an update that can't break a running session. |

Those five are what the system *has*. [**§6 is what it is still blocked by**](#6-the-ceiling-is-the-interface-not-the-machine) — measured, and it is not the machine.

---

## 1. Sessions run each other

**A session is not a terminal you babysit — it is an addressable process that can open, message, and retire its peers.** The recording above is the whole loop; the mechanics are four commands.

| Touchpoint | Command | What happens |
|---|---|---|
| **Self-open** | `/handoff` → [`handoff-fire.sh --split-right`](scripts/handoff-fire.sh) | Claims a warm worktree (~3 s), ranks the four accounts on live quota, ⌘D-splits **the firing pane** (anchored to `$ITERM_SESSION_ID`, never whatever window is frontmost), then types and submits the brief. |
| **Self-recycle** | `handoff-fire.sh --recycle` | Exits and relaunches **this** pane in place — arm a detached watcher, type `/exit`, let it re-launch into the plain shell once `claude` is gone. |
| **Self-close** | `handoff-fire.sh self-close --successor <uuid>` | Retires the pane once the work is away. The successor must be **verified engaged** — resolvable, `claude` on its tty, *and* a real assistant turn in its transcript — before `/exit` is typed and again at the close instant. Focus lands on the survivor. |
| **Two-way** | [`cc-notify`](bin/cc-notify) · `--notify-back` · [`cc-await-ping`](bin/cc-await-ping) | Peers exchange messages, so a fired session can report completion, a decision gate, or a blocker back to the session that fired it. |

> **Why `/exit` and not `/clear` + a queued payload.** Claude Code's queue is type-asymmetric: a built-in slash command holds until the calling turn ends, but *plain text* is steered into the still-running turn at the next tool-result boundary — which the firing script's own Bash call guarantees. A queued payload therefore ran inline in the **old** context while `/clear` stayed armed behind it. Exit-and-relaunch has no such race.

The same three touchpoints at the command line — every line below is real output from the scripts in this repo:

<img src="assets/demo/handoff-real.webp" width="900" alt="Terminal recording in three scenes. Scene 1, self-open: handoff-fire.sh --dry-run ranks all four accounts by live quota headroom, resolves the split anchor to the firing pane's own session id, and prints the exact composed launch command. Scene 2, two-way: cc-notify --self prints the pane uuid, cc-notify writes a message that appears as one timestamped line in the mailbox file, mailbox-drain.sh emits it as UserPromptSubmit additionalContext, and a second drain returns zero bytes because the seen cursor already consumed it. Scene 3, self-close: a bare self-close is refused for having no succession statement, and self-close --terminal is refused because an origin session was never fired by an originator.">

<sub>Recorded with <a href="https://github.com/charmbracelet/vhs">VHS</a> from <a href="assets/demo/handoff-real.tape"><code>assets/demo/handoff-real.tape</code></a> — re-runnable, so it can never drift from the scripts it documents. The <code>/handoff</code> and <code>self-close</code> scenes run <code>--dry-run</code> (nothing is launched or closed); the mailbox round trip is real and completes against a temp inbox.</sub>

### A message is a file, not a keystroke

`cc-notify` never types into a live input line. It appends one line to the target's inbox; the target drains it at a boundary where nothing can be corrupted, and acks it exactly once.

<!-- Diagram source: assets/diagrams/session-comms.mmd — edit it, run `npm run diagrams`, commit the regenerated SVGs. -->
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/diagrams/session-comms-dark.svg">
  <img src="assets/diagrams/session-comms-light.svg" alt="A message sent with cc-notify to a role is resolved at send time: if the target is live it goes straight to its mailbox file; if the pane recycled it follows a .forward chain to the successor; if the target is gone entirely it is tee'd to the desk tagged with the original uuid. The mailbox holds one line per message. It is drained at a safe boundary — SessionStart or UserPromptSubmit — arrives as context rather than keystrokes on a live input line, and is acked at Stop through an exactly-once cursor. An idle peer running cc-await-ping is woken by the same write.">
</picture>

<details>
<summary>Interactive Diagram</summary>

<!-- mermaid-fence: assets/diagrams/session-comms.mmd (auto-synced by `npm run diagrams`) -->
```mermaid
flowchart TB
    Box[("mailbox/&lt;uuid&gt;.md<br/>one line per message")]
    Send["any session<br/>cc-notify --role peer"] --> Res{"resolved at<br/>SEND time"}
    Res -->|"live"| Box
    Res -->|"pane recycled"| Fwd[".forward chain<br/>→ the successor"]
    Res -->|"gone entirely"| Desk["tee'd to the desk<br/>tagged for:&lt;uuid&gt;"]
    Fwd --> Box
    Desk --> Box
    Box --> Drain["drained at a SAFE boundary<br/>SessionStart · UserPromptSubmit"]
    Drain --> Ctx["arrives as CONTEXT —<br/>never keystrokes on a live input line"]
    Ctx --> Ack["acked at Stop:<br/>exactly-once cursor"]
    Wake["idle peer?<br/>cc-await-ping"] -.->|"the write IS the wake"| Box
    classDef k fill:#2b2410,stroke:#d4af37,color:#e6edf3
    classDef b fill:#0d1d2e,stroke:#58a6ff,color:#e6edf3
    classDef g fill:#12261a,stroke:#3fb950,color:#e6edf3
    class Res,Box k
    class Send,Fwd,Desk,Drain b
    class Ctx,Ack,Wake g
```

<sup><a href="assets/diagrams/session-comms-dark.svg?raw=true">full-screen dark</a> · <a href="assets/diagrams/session-comms-light.svg?raw=true">light</a> · <a href="assets/diagrams/session-comms.mmd">source</a></sup>

</details>

Three failures shaped that design, and each is now structural rather than remembered:

- **A pane UUID is a stale address the moment that pane recycles.** Forensics found 570 pages looping into one dead former-desk inbox for three days. Automated senders now address a **role**, re-resolved at send time; a `.forward` chain follows successions; an undeliverable line is still recorded *and* tee'd to the desk, which is where triage happens.
- **An enqueue to a dead inbox is not a delivery.** Liveness decides the verdict, and a reroute never upgrades it — `cc-notify` reports "mailbox only" honestly, and [`cc-inbox-guard`](bin/cc-inbox-guard) fails loud on mail nothing will ever drain.
- **A drain is not a read.** The `.seen` cursor advances on delivery, but `.acked` only at the Stop *after* a turn provably carried the mail. Dup-biased by design: a crash mid-turn re-surfaces the message instead of silently losing it.

### It pages you only when a human must decide

The same addressing runs outward. Operator-owned steps are rendered as **runnable commands from disk truth**, never prose — a `▶ <exact command>` block at every turn close ([`operator-readout.sh`](hooks/operator-readout.sh)), a one-glance board of everything blocking on you ([`cc-blockers`](bin/cc-blockers)), durable decision packets that survive a recycle ([`cc-decide`](bin/cc-decide)), a daily digest with phone push ([`cc-digest`](bin/cc-digest)), and sound + desktop alerts ([`notify.sh`](hooks/notify.sh)).

<details>
<summary><b>The standing desk — what runs the machine between check-ins</b></summary>

<br>

A standing **desk** session orchestrates; launchd daemons dispatch and watch.

- **Work ledger → dispatch.** [`cc-backlog`](bin/cc-backlog) is an append-only JSONL ledger with event-keyed idempotent ids and claim/reap/thrash guards. It feeds [`cc-dispatch`](bin/cc-dispatch), which plans quota-aware waves via [`cc-wave-plan`](bin/cc-wave-plan) and [`claude-accounts`](bin/claude-accounts) ranking across the four accounts.
- **Lifecycle.** Every session self-registers ([`session-register.sh`](hooks/session-register.sh)) with [`cc-reconcile`](bin/cc-reconcile) backfill healing. [`cc-reaper`](bin/cc-reaper) classifies idle sessions against a cause taxonomy with never-reap defaults; only identity-pinned, landed, clean panes are closed, via [`cc-teardown`](bin/cc-teardown).
- **Crash supervision.** [`lead-crash-watchdog.sh`](hooks/lead-crash-watchdog.sh) classifies per-session death (including binary-version telemetry); [`lead-supervisor.sh`](scripts/lead-supervisor.sh) pages on stalls, permission prompts, and past-threshold runs; [`cc-crash-report`](bin/cc-crash-report) keeps the ledger and dashboard.
- **Agent Teams.** The `TeammateIdle` hook exits code 2 on idle, forcing immediate shutdown so no pane is orphaned; [`bin/it2-wrapper`](bin/it2-wrapper) injects the teammate profile on split and forces modal-free closes.

This layer is audited adversarially — most recently a 15-agent verified audit: [`docs/research/infra-reliability-audit-2026-07-22/`](docs/research/infra-reliability-audit-2026-07-22/synthesis.md).

</details>

---

## 2. Parallel work cannot collide

**Concurrent sessions share one git index and one trunk — so isolation is not a convenience, it is the precondition for everything above.** Every writer gets its own worktree and account; every landing passes through exactly one machine-wide lock.

<!-- Diagram source: assets/diagrams/parallel-lanes.mmd — edit it, run `npm run diagrams`, commit the regenerated SVGs. -->
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/diagrams/parallel-lanes-dark.svg">
  <img src="assets/diagrams/parallel-lanes-light.svg" alt="Sessions A, B and C each work in their own worktree on their own account. All three run an unlocked fast gate — statics, ratchets and a bounded smoke that sheds by skipping under load, never a test corpus — then funnel into a single machine-wide land-lock held for seconds, covering only the compare-and-swap push window. The push is verified by content rather than by commit count before the work reaches origin/main. Behind the trunk, one background verifier runs the full corpus in a fresh cell with host suites partitioned out, and its green stamp is the only thing that lets the deploy autopilot advance the live ~/.claude layer.">
</picture>

<details>
<summary>Interactive Diagram</summary>

<!-- mermaid-fence: assets/diagrams/parallel-lanes.mmd (auto-synced by `npm run diagrams`) -->
```mermaid
flowchart LR
    A["session A<br/>own worktree · acct 1"] --> G
    B["session B<br/>own worktree · acct 2"] --> G
    C["session C<br/>own worktree · acct 3"] --> G
    G["fast gate — UNLOCKED, seconds<br/>statics + ratchets + bounded smoke<br/>(sheds by SKIPPING under load; no corpus, ever)"]
    G --> Lock{"land-lock<br/>held seconds:<br/>the CAS push window only"}
    Lock --> Push["push → verify by CONTENT,<br/>not commit count"]
    Push --> Trunk[("origin/main")]
    Trunk --> V["verifier — ONE, background band<br/>full corpus, fresh cell,<br/>host suites partitioned out"]
    V -->|"green stamp"| D["deploy autopilot<br/>fail-closed on green"]
    D --> Live[("live ~/.claude")]
    classDef w fill:#0d1d2e,stroke:#58a6ff,color:#e6edf3
    classDef k fill:#2b2410,stroke:#d4af37,color:#e6edf3
    classDef t fill:#12261a,stroke:#3fb950,color:#e6edf3
    class A,B,C w
    class G,Lock,Push,V,D k
    class Trunk,Live t
```

<sup><a href="assets/diagrams/parallel-lanes-dark.svg?raw=true">full-screen dark</a> · <a href="assets/diagrams/parallel-lanes-light.svg?raw=true">light</a> · <a href="assets/diagrams/parallel-lanes.mmd">source</a></sup>

</details>

Three traps make naive automation fail. Each is defeated by a mechanism, not by discipline:

- **A shared index means a bare `git commit` sweeps another session's staged files** — plus ref-lock races and shared-file clobber. Every writer therefore gets its **own worktree**, handed out warm (`node_modules`, codegen, `.env.local`, seeded DB already built) in about three seconds.
- **The launchers are zsh functions**, carrying per-account isolation, so no script can `exec` them. `handoff-fire.sh` **types** the launch command into a fresh surface with echo-verified keystrokes — anchored to the firing agent's own window, so the split lands where you are looking. The surface is a real iTerm2 pane or a real kitty pane depending on where you are sitting ([§6](#so-the-question-stopped-being-which-one--it-runs-on-both)); the anchoring and the echo-verification are the same either way.
- **A hot trunk means N landers race — and a per-land test corpus means they starve each other.** A week of measurement proved the frame, not the tree, was the blocker: full-corpus-per-land collapsed P(green) to ~2.3% under fleet load (one branch died 37 straight times on a tree that was never red). So the verdict is **inverted** ([`docs/plans/LAND_PIPELINE_V2.md`](docs/plans/LAND_PIPELINE_V2.md)): [`ship-land.sh`](scripts/ship-land.sh) lands in seconds-to-minutes with only O(diff) statics, ratchets and a ≤120s direct-suite smoke that *skips* under load — nothing heavy can enter [`land-lock.sh`](scripts/land-lock.sh), which holds for seconds around the CAS push window. The full-suite claim belongs to one background verifier ([`postland-verify.sh`](scripts/postland-verify.sh) — fresh cell per run, [`host-suites.manifest`](scripts/host-suites.manifest) partition, progress-keyed stall bound, auto-revert of bisected culprits), and the live layer only ever advances to its green stamp ([`deploy-live.sh`](scripts/deploy-live.sh) on a launchd tick). Landing is still verified **by content** ([`land-verify.sh`](scripts/land-verify.sh)) — a commit-count check reads "landed" for work that was silently dropped, which is exactly how a 5-file commit went missing on 2026-07-11.

> **Portable vs project-specific.** `handoff-fire.sh`, the isolation policy, [`docs/WORKTREE_WORKFLOW.md`](docs/WORKTREE_WORKFLOW.md), and this repo's fail-closed landing rail are the **portable** half and live here. App repos keep their own warm pool and migration-aware `/ship` variants. Account, model and effort routing reads `~/.claude/model-config.yaml`, which is per-machine and deliberately not synced.

### Why 30+ panes freezes iTerm2 — and why the GPU can't fix it

**It isn't a memory leak — it's windows that don't die.** iTerm2 has an open, unfixed upstream bug (#12097, #12645, #12905): closing a tab to zero panes should destroy its `NSWindow`; on iTerm2 it doesn't. One session left 98 "closed" windows alive, and each still costs the compositor real objects: a **window** costs ~28–34 MB of backing store + ~4.9 Mach ports to WindowServer; a **pane** inside an existing window costs almost nothing (~3 IOSurfaces, ~0 net bytes). Spreading 30 sessions across 30 windows costs WindowServer **2.35× more CPU than the same 30 panes gathered into one window** — while iTerm2 itself measured **0.0% CPU** and WindowServer sat at 92–99.9%. The window is the expensive unit; the app's own memory was never the culprit.

**The instinct to fix it by pushing rendering onto the idle GPU makes it worse.** That reasoning assumes more panes → more CPU work → the CPU maxes out → move the work to the underused silicon. But the bottleneck was never a CPU/GPU balance inside one app — it's compositor *objects* — and GPU rendering **adds** objects, it doesn't remove them. iTerm2's Metal path allocates a `CAMetalLayer` plus several dispatch queues *per pane*, on top of the window cost above, and it's capped at 5 GPU panes per tab (foreground tab only) — so lighting up 30 sessions on Metal forces **six separate windows**, multiplying the exact axis that already froze the machine. Every iTerm2 layout pays one of the two costs; none escapes both.

Ghostty proves the same point the other way: it has **no CPU renderer at all** — every pane is Metal, unconditionally. If "more GPU" were the fix, Ghostty should be the cheapest terminal under load. Measured instead, byte-matched at 18 panes / 10 fps: Ghostty burns **27.3% app CPU against kitty's 9.5%** (2.9×), and its thread count **scales linearly, 4.00 threads/pane, with no ceiling** — because submitting frames to a GPU is itself CPU work (encoding commands, servicing a dispatch queue), paid on *every* pane. kitty wins not by avoiding the GPU but by putting **all** panes in **one** window and sharing one small thread pool no matter how many panes it holds — the one thing that actually is free (macOS itself has headroom: 30 panes repainting in one window cost only ~10 percentage-points of a single core).

Full evidence, the hypotheses that got killed along the way, and the migration plan: [`docs/research/terminal-for-30-panes-2026-07-31.md`](docs/research/terminal-for-30-panes-2026-07-31.md).

---

## 3. Autonomy is bounded

**Every prompt, tool call and turn-ending passes through hooks that can refuse it.** This repo ships 60 hook scripts; the live config wires **69 hook entries across 12 lifecycle events**. All exit 0 by default — a hook failure never blocks a tool — *except* deliberate `PreToolUse` denials and fact-bound `Stop` blocks.

<!-- Diagram source: assets/diagrams/guardrail-pipeline.mmd — edit it, run `npm run diagrams`, commit the regenerated SVGs. -->
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/diagrams/guardrail-pipeline-dark.svg">
  <img src="assets/diagrams/guardrail-pipeline-light.svg" alt="A prompt passes through six UserPromptSubmit hooks that deliver mail and nudges, then reaches Claude. Each tool call passes eleven PreToolUse hooks: a refused call never runs, blocked by 41 deny rules, dangerous bash patterns, a wrong worktree, or an unsanctioned push; an allowed call proceeds with every Write backed up first, then ten PostToolUse hooks record the plan version, bash log and context watch before returning to Claude. When the turn tries to end, nine Stop hooks check it: if the live git ledger disagrees the turn is sent back to Claude, and only a genuinely finished turn is allowed to end.">
</picture>

<details>
<summary>Interactive Diagram</summary>

<!-- mermaid-fence: assets/diagrams/guardrail-pipeline.mmd (auto-synced by `npm run diagrams`) -->
```mermaid
flowchart TB
    P(["your prompt"]) --> UPS["UserPromptSubmit — 5 hooks<br/>mail · nudges"]
    UPS --> M(["Claude"])
    M --> Pre{"PreToolUse<br/>12 hooks"}
    Pre -->|"refused"| No["the call never runs<br/>41 deny rules · dangerous bash<br/>wrong worktree · unsanctioned push"]
    Pre -->|"allowed · Write backed up first"| Tool["the tool call"]
    Tool --> Post["PostToolUse — 9 hooks<br/>plan version · bash log · context watch"]
    Post --> M
    M --> Stop{"Stop<br/>9 hooks"}
    Stop -->|"the live git ledger disagrees"| M
    Stop -->|"genuinely done"| End(["turn ends"])
    classDef gate fill:#2b2410,stroke:#d4af37,color:#e6edf3
    classDef no fill:#2b1618,stroke:#f85149,color:#e6edf3
    classDef ok fill:#12261a,stroke:#3fb950,color:#e6edf3
    class Pre,Stop gate
    class No no
    class End ok
```

<sup><a href="assets/diagrams/guardrail-pipeline-dark.svg?raw=true">full-screen dark</a> · <a href="assets/diagrams/guardrail-pipeline-light.svg?raw=true">light</a> · <a href="assets/diagrams/guardrail-pipeline.mmd">source</a></sup>

</details>

| Hook | Fires on | What it refuses, or guarantees |
|---|---|---|
| [`backup-before-write.sh`](hooks/backup-before-write.sh) | Write · Edit | No file is modified before a nanosecond+PID-stamped backup exists; injects the OVERWRITE GUARD and plan rules into context. |
| [`validate-bash.sh`](hooks/validate-bash.sh) | Bash | Pattern-blocks destructive commands, and audit-logs the rest. |
| [`git-worktree-guard.sh`](hooks/git-worktree-guard.sh) | Bash · Write | Refuses writes aimed at the wrong worktree. |
| [`completion-assert.sh`](hooks/completion-assert.sh) | Stop | **Refuses a false "done"** that contradicts the live git and gate ledger. |
| [`operator-readout.sh`](hooks/operator-readout.sh) | Stop | Renders every operator-owned step as a `▶ runnable command`, from disk truth. |
| [`teammate-auto-shutdown.sh`](hooks/teammate-auto-shutdown.sh) | TeammateIdle | Exit code 2 → immediate shutdown; zero orphaned panes. |

<details>
<summary><b>Full hook roster, by lifecycle event</b></summary>

<br>

```
SessionStart (14)     session-start · session-register · live-session-registry · desk-brief-inject · dod-persist ·
                      mailbox-drain · setup-plan/task-symlinks · session-index-start · pre-session-validate ·
                      config-mirror-assert · activation-watch · frontier-status · lead-crash-watchdog
UserPromptSubmit (5)  mailbox-drain · handoff-intent-nudge · research-precognition-nudge · memory-nudge · cache-expiry-warning
PreToolUse (12)       validate-bash · backup-before-write (OVERWRITE GUARD) · git-worktree-guard · agent-teams-enforce ·
                      rm-safe-allowlist · check-edit-boundary · plan-agent-teams-default · frontier-spawn-gate ·
                      cc-unattended-ask-guard · keychain-guard · curl-gate · enforce-email-formatting
PostToolUse (9)       post-file-edit · plan-index-update · plan-version-commit · plan-pin-session · validate-plan-structure ·
                      log-bash · task-mutation-index · teammate-checkpoint · waiting-recycle
Stop (9)              completion-assert (blocks a false "done") · operator-readout · session-continue · boundary-handoff ·
                      anti-deference-nudge · dispatch-assert · teammate-checkpoint · cache-expiry-tracker · notify
SessionEnd (6)        session-end (watchdog handshake) · session-deregister · session-index-end · session-save-id ·
                      live-session-registry · harvest-skill-end
Notification (2)      notify (audio + desktop) · push-critical        PermissionRequest (3)  notify ×3 (Bash · question · plan)
                      cc-permission-beacon is NOT wired — staged only (pending-activation/17-…); cc-blockers raises beacon-inert
PreCompact (3)        dod-persist · compact logging                   TeammateIdle (1)       teammate-auto-shutdown
WorktreeCreate (1)    worktree-setup                                  TaskCompleted (1)      task-quality-gate
```

</details>

<details>
<summary><b>Permissions and auto mode — what the classifier may and may not decide</b></summary>

<br>

`claude --permission-mode auto` lets the classifier resolve `ask`-tier calls instead of prompting you. Every other layer still applies:

| Layer | Count | Behavior in auto mode |
|---|---|---|
| `deny` rules | 41 | **Always enforced** — the classifier cannot override |
| `ask` rules | 6 | Classifier decides instead of prompting (collapsed from 45 as autonomy moved routine calls behind classifier + hook rails) |
| `allow` rules | 350 | Auto-approved: read-only commands, WebFetch domains, Edit/Write, MCP tools |
| PreToolUse hooks | 12 | Always fire — a hook deny is an absolute block |
| PostToolUse hooks | 9 | Always fire — logging, plan versioning, task indexing |

Key deny rules, enforced even in auto mode: `git push --force`, `sudo`/`su`, `eval`/`exec`, `git clean`, `wget`, `dd`, and reads of `.env*` / `*.key` / `*.pem`.

Teammate models must be on the account's auto-mode allowlist, or the spawn silently demotes to `acceptEdits`. That allowlist is deliberately **not** written down here: it lives in `~/.claude/model-config.yaml` under `auto_mode_allowlist`, the single source of truth for model, effort and frontier routing — and [`claude-lint-models.sh`](scripts/claude-lint-models.sh) fails any file in this repo that pins a superseded model literal, this README included. Inspect the classifier with `claude auto-mode defaults | config | critique`.

</details>

---

## 4. Nothing a session did dies with it

**Panes are disposable; their output is not.** Four independent layers outlive the session that produced them.

| What survives | How | Recover it with |
|---|---|---|
| **Every file version** | [`backup-before-write.sh`](hooks/backup-before-write.sh) stamps a backup before every Write/Edit — nanosecond+PID names (parallel-agent-safe), sidecar `.path` files for basename collisions, atomic `mktemp`+`mv` restore, capped at 10/file with a 30-day TTL by [`prune-backups.sh`](scripts/prune-backups.sh) | [`restore-file`](scripts/restore-file.sh) `<path>` · `--diff` · `--pick N` · `--recent 10` |
| **Every plan revision** | [`plan-version-commit.sh`](hooks/plan-version-commit.sh) writes two layers: an append-only `MANIFEST.jsonl` (timestamp, session, SHA256, line count) and full snapshots in a separate git repo | `cd ~/.claude/plan-history && git log` |
| **Every task list** | Claude Code uses UUID task dirs and ignores `CLAUDE_CODE_TASK_LIST_ID`; [`setup-task-symlinks.sh`](hooks/setup-task-symlinks.sh) detects the active list at SessionStart, symlinks it to `.claude-tasks/_current/`, and generates a readable `TASKS.md` beside it | `.claude-tasks/TASKS.md` |
| **Every conversation** | SQLite FTS5 index over all ~6,900 sessions, kept self-maintaining by three hooks — a crash-safe stub at SessionStart, rich metadata at SessionEnd, and a 60-second sweep daemon catching misses | `claude-search "<query>"` · `--fzf` · `--stats` |

```bash
restore-file path/to/file --diff     # unified diff against the latest backup
restore-file --recent 10             # 10 most recent backups across all files
claude-search "replicache mutation"  # full-text across every session, <5 ms
```

Session search is its own project: **[claude-session-search](https://github.com/renchris/claude-session-search)**.

---

## 5. The whole system deploys from git

**The repo is the source of truth; your `~/.claude` is its deployment.** The primary config dir is *symlinked*, so editing a live hook edits this repo and nothing can silently drift out of version control.

<!-- Diagram source: assets/diagrams/deploy-model.mmd — edit it, run `npm run diagrams`, commit the regenerated SVGs. -->
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/diagrams/deploy-model-dark.svg">
  <img src="assets/diagrams/deploy-model-light.svg" alt="The claude-infrastructure repo — 1,134 files under one reviewable history — deploys three ways. install.sh symlinks hooks, commands and scripts into the primary ~/.claude, so editing the live hook is editing the repo. install.sh --config-dir copies the same system into the four billing-isolated account directories. Global surfaces — ~/bin tools, LaunchAgents and the statusline — are copied, and sync.sh pulls hand-edits back.">
</picture>

<details>
<summary>Interactive Diagram</summary>

<!-- mermaid-fence: assets/diagrams/deploy-model.mmd (auto-synced by `npm run diagrams`) -->
```mermaid
flowchart TB
    Repo["claude-infrastructure<br/>1,134 files · one reviewable history"]
    Repo &lt;--&gt;|"install.sh · SYMLINK<br/>editing the live hook IS editing the repo"| Prim["~/.claude<br/>hooks · commands · scripts"]
    Repo -->|"--config-dir · COPY"| Alt["~/.claude-secondary … 4<br/>4 billing-isolated accounts"]
    Repo -->|"COPY<br/>sync.sh pulls hand-edits back"| Glob["~/bin · LaunchAgents<br/>45 tools · 13 daemons · statusline"]
    classDef src fill:#2b2410,stroke:#d4af37,color:#e6edf3
    classDef dep fill:#0d1d2e,stroke:#58a6ff,color:#e6edf3
    class Repo src
    class Prim,Alt,Glob dep
```

<sup><a href="assets/diagrams/deploy-model-dark.svg?raw=true">full-screen dark</a> · <a href="assets/diagrams/deploy-model-light.svg?raw=true">light</a> · <a href="assets/diagrams/deploy-model.mmd">source</a></sup>

</details>

The symlink rule was bought with a real failure: on 2026-07-03 a *copied* `handoff-fire.sh` had drifted +198 lines in the deployment and was one `install.sh` away from being clobbered. The four account dirs stay **copies** so a rate-limited account cannot perturb another; global surfaces are copies too, and `sync.sh` pulls hand-edits of those back.

**Landed is not live — the gap is closed by proof, not by hand.** Because the primary dir symlinks into the checkout, a trunk commit only reaches running sessions when the checkout advances — and it advances *autonomously and fail-closed*: a launchd verifier ([`postland-verify.sh`](scripts/postland-verify.sh), every 5 min) proves each trunk tree with the full corpus in a fresh cell and stamps it; a deploy autopilot ([`deploy-live.sh`](scripts/deploy-live.sh)` --auto`, every 10 min) fast-forwards the checkout **only to a green-stamped tree**, re-runs `install.sh` (so brand-new files get their symlinks), and then runs the [host suites](scripts/host-suites.manifest) against the live layer — the one place suites that assert the deployed world can honestly run. A red trunk auto-reverts its bisected culprit; a dead verifier or a lagging deploy is surfaced by fact-bound alarms in [`cc-blockers`](bin/cc-blockers) rather than assumed healthy.

<details>
<summary><b>What actually lives in <code>~/.claude/</code></b></summary>

<br>

```
~/.claude/                       # config dir — machine state + the deployed system
├── settings.json · .mcp.json    # permissions, hooks, env · MCP servers
├── CLAUDE.md                    # global instructions (synced)
├── model-config.yaml            # model / effort / frontier SSOT (per-machine, NOT synced)
├── hooks/  commands/  scripts/  # SYMLINKED from this repo — edits go live
├── skills/  agents/             # SYMLINKED — 12 skills, 4 custom agents
├── bin/it2                      # teammate pane wrapper (copied) — iTerm2, or kitty via it2-kitty
├── mailbox/  cc-roles/          # per-pane inboxes · role → pane resolution
├── backups/                     # auto-backups (10/file, 30-day TTL)
├── plan-history/                # plan snapshots (its own git repo)
├── session-index.db             # FTS5 session search
└── projects/                    # per-project memory + transcripts

~/.claude-versions/   current -> 2.1.114      # atomically-symlinked installs
~/bin/                claude-latest · claude-update · claude-versions · 45 cc-* fleet tools
~/Library/LaunchAgents/   13 daemons — dispatcher · discovery · reapers · regression · search · …
```

</details>

### Install

```bash
git clone https://github.com/renchris/claude-infrastructure.git
cd claude-infrastructure
./install.sh --dry-run   # preview
./install.sh             # idempotent — safe to re-run
```

It symlinks hooks, commands and scripts into `~/.claude`; copies `bin/` tools, `statusline.sh` and the LaunchAgents; loads the daemons; and validates `settings.json`. For an alternate account: `./install.sh --config-dir ~/.claude-secondary`. Re-run it after every trunk fast-forward — it links **brand-new** files, which per-file symlink directories otherwise never pick up. `--wire-hooks` additively merges the template hook roster into a live `settings.json`, with backup and validation.

**Terminal: iTerm2 or kitty.** `install.sh` runs [`scripts/kitty-setup.sh`](scripts/kitty-setup.sh) automatically whenever kitty is present; run it by hand to wire or inspect kitty on its own:

```bash
scripts/kitty-setup.sh --check   # report only — exits 1 if anything is missing or INERT
scripts/kitty-setup.sh           # apply (idempotent) · --undo reverts
```

It reports **live** state separately from on-disk state, because config present is not config loaded: `allow_remote_control` and `listen_on` are the only two options kitty refuses to reload, so a kitty older than its config is **INERT** and `--check` exits 1 rather than reporting green. It never clobbers a hand-written `kitty.conf`, and `install.sh` does not propagate its exit status — non-zero means *restart kitty*, not *the install failed*. What it wires, and why each piece is load-bearing, is in [§6](#so-the-question-stopped-being-which-one--it-runs-on-both).

```bash
./sync.sh          # pull hand-edits of COPIED surfaces back into the repo
./sync.sh --diff   # preview only
```

### An update can't break a running session

npm overwrites Claude's binary in place, which throws `ENOTEMPTY` when live sessions hold file handles. The fix is Homebrew-style parallel installs — every version in its own directory, one symlink pointing at the active one:

```
~/.claude-versions/
├── 2.1.113/           # rollback target
├── 2.1.114/           # current
└── current -> 2.1.114 # atomic symlink — rename(2), NOT ln -sfn
```

`ln -sfn` is wrong because it is two syscalls (`unlink` + `symlink`) with an ENOENT window between them. The correct swap is atomic:

```bash
ln -s "$new_version" "${current}.tmp_$$"
mv -f "${current}.tmp_$$" "$current"   # rename(2) is POSIX-atomic
```

Running processes survive `rm -rf` of their own version via POSIX vnode semantics — the kernel keeps the `mmap`'d binary alive until the last fd closes. [`bin/claude-latest`](bin/claude-latest) wraps all of it: rotate log → check npm (10-min cache) → clean stale versions *before* install (disk-full resilience) → install under a `mkdir` lock → validate the binary → swap → `exec` with `DISABLE_AUTOUPDATER=1`. GC never deletes the symlink target, skips versions with live processes (`pgrep`), and recovers by scanning for any working version if `current` is broken.

| Command | Purpose |
|---|---|
| `claude` | Auto-update + GC + launch (via `claude-latest`) |
| `claude-update [version]` | Install latest, or pin a specific version |
| `claude-update --cleanup` | Manual GC (keep current + N previous) |
| `claude-versions` | List installed versions with disk usage |
| `CLAUDE_SKIP_UPDATE=1 claude` | Skip the update check once |

### Held to ground truth

**2,358 bats tests across 144 files (31,841 lines)** prove every tree — continuously by the background verifier ([`postland-verify.sh`](scripts/postland-verify.sh), the sole owner of the full-suite claim), plus a nightly full-suite regression daemon. Diagrams have their own guard: `npm run diagrams:check` fails CI if a rendered SVG or an embedded mermaid fence has drifted from its `.mmd` source.

---

## 6. The ceiling is the interface, not the machine

Everything above runs ~30 sessions unattended. At that concurrency this box lags and freezes — and every pane must stay visible, because a blocked permission prompt is found *by eye*. On [Boris Cherny's adoption ladder](https://claude.ai/code/artifact/bfdfaef9-bc62-4dfe-ba9e-c58a26c9accf) that puts this system at **Step 3 in mechanism and Step 2 in human loop**: worktrees, subagents, dynamic workflows, `/loop`, `/batch`, `/goal`, Skills and launchd routines are all here, but the operator is still a *poller*.

**Running 30 sessions is not what lags this box — displaying them is.** Measured 2026-07-31; full evidence in [`docs/research/l3-l4-terminal-and-workflow-2026-07-31.md`](docs/research/l3-l4-terminal-and-workflow-2026-07-31.md).

<!-- Diagram source: assets/diagrams/interface-ceiling.mmd — edit it, run `npm run diagrams`, commit the regenerated SVGs. -->
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/diagrams/interface-ceiling-dark.svg">
  <img src="assets/diagrams/interface-ceiling-light.svg" alt="Thirty sessions running cost about 0.75 cores at roughly 215 MB each, with 93 percent of memory free and zero pageouts — so the fleet is not the expensive part. When a session blocks on a permission prompt the path forks. Today it is found by eye, which requires thirty panes kept visible: a polling interface. That costs iTerm2 122.1 percent plus WindowServer 49.0 percent, about 1.7 cores, which is 2.3 times the fleet it displays, and it leaks 76 mach ports per hour at frozen layout with tuning already exhausted at match 9 drift 0 — so cost scales with sessions running. The other fork already exists: cc-permission-beacon.sh fires on PermissionRequest and writes each blocked session to /tmp/cc-permission-pending/. What is missing is that nothing renders that queue, so the grid stands in for it. The fix is a console rather than a terminal — one row per session, zoom on demand, no VT implementation, driving kitty underneath — after which cost scales with sessions blocked, zero to three.">
</picture>

<details>
<summary>Interactive Diagram</summary>

<!-- mermaid-fence: assets/diagrams/interface-ceiling.mmd (auto-synced by `npm run diagrams`) -->
```mermaid
flowchart TB
    Fleet["30 sessions RUNNING<br/>≈0.75 cores · ~215 MB each<br/>93% memory free · Pageouts 0"]
    Block{"a session BLOCKS<br/>on a permission prompt"}
    Fleet --> Block

    Block -->|"TODAY — found by EYE"| Poll["30 panes kept VISIBLE<br/>a POLLING interface"]
    Block -->|"ALREADY BUILT"| Beacon["cc-permission-beacon.sh<br/>PermissionRequest →<br/>/tmp/cc-permission-pending/"]

    Poll --> Cost["iTerm2 122.1% + WindowServer 49.0%<br/>≈1.7 cores = 2.3× the fleet it displays"]
    Cost --> Leak["+76 mach ports/hr at FROZEN layout<br/>tuning exhausted — match=9 drift=0"]
    Leak --> ScaleN["cost scales with sessions RUNNING"]

    Beacon --> Face["MISSING: nothing RENDERS the queue<br/>so the grid stands in for it"]
    Face --> Console["a CONSOLE, not a terminal<br/>1 row per session · zoom on demand<br/>no VT — drives kitty underneath"]
    Console --> ScaleB["cost scales with sessions BLOCKED — 0 to 3"]

    classDef k fill:#2b2410,stroke:#d4af37,color:#e6edf3
    classDef b fill:#0d1d2e,stroke:#58a6ff,color:#e6edf3
    classDef g fill:#12261a,stroke:#3fb950,color:#e6edf3
    class Block,Fleet k
    class Poll,Cost,Leak,ScaleN b
    class Beacon,Face,Console,ScaleB g
```

<sup><a href="assets/diagrams/interface-ceiling-dark.svg?raw=true">full-screen dark</a> · <a href="assets/diagrams/interface-ceiling-light.svg?raw=true">light</a> · <a href="assets/diagrams/interface-ceiling.mmd">source</a></sup>

</details>

### The machine is not the constraint

The intuitive diagnosis — heaps grow, memory exhausts, the box swaps — is refuted three separate ways on this hardware:

| Evidence | Reading |
|---|---|
| **31 concurrent sessions, live** | **93% memory free · `Pageouts: 0`** — no swapping at the exact scale modelled as fatal |
| **Per-session footprint** | **~215 MB** (211–295 MB across the live fleet), so 30 sessions project to ~6.5 GB — not the ~45 GB the memory theory requires |
| **Panic 2026-07-30** | VM-compressor **segment** exhaustion with **~20 GB free**, `swap_low:0` — structural, not a load threshold |
| **Panic 2026-07-31** | kernel **spinlock timeout** from a research probe's own **8,368-thread** ladder; compressor 0% pages / 7% segments, **OK** — self-inflicted by the instrument, not by the workload |

The whole 15-session fleet costs **≈0.75 cores**. Agent count is not the expensive axis.

### The interface is

| Measurement | Reading |
|---|---|
| **Renderer vs fleet** | iTerm2 **122.1%** + WindowServer **49.0%** ≈ **1.7 cores** — **2.3× the entire agent fleet it displays**, and that is the *conservative* end: five re-samples put the ratio at **2.74–4.08×** (median 2.89×) |
| **Leak, at frozen layout** | **+76 mach ports/hour** while RSS *falls* (−28 MB/hr) — the axis whose unbounded growth characterised the freeze |
| **Tuning headroom** | [`iterm2-perf-parity.sh`](scripts/iterm2-perf-parity.sh) → `match=9 drift=0`, and it still burns 1.2 cores at *half* load ⇒ **configuration is exhausted** |
| **The unit that costs** | the same 30 panes cost **+22.6 pp** of a core across 30 windows vs **+11.2 pp** in one — **windows are 2.35×; panes are nearly free** |

This inverts the obvious remedy **on iTerm2**. It disables Metal for any tab holding ≥6 sessions *and* for every background tab, so its only all-GPU layout for 30 sessions is **6 windows** — which forces you into the expensive unit. On *that* architecture, "more GPU" and "more compositor objects" are the same request, because iTerm2 allocates one `CAMetalLayer` **per pane**. **The cap is protecting you.**

But the axis is not the graphics API — it is **cadence, then windows, then surfaces**, fitted from four compositor arms at identical geometry and pixels/second:

| Axis | Coefficient | Lever at 30 panes |
|---|---|---|
| **Presentation cadence** | **0.480 pp/Hz** | **9.6pp — dominant, 6× the surface lever** |
| OS-window count | 0.4483 pp/window | 13.0pp across 1→30 |
| Surface count *within* a window | 0.0552 pp/surface | 1.60pp ceiling — 8.1× cheaper per unit than a window |
| **Metal vs OpenGL vs CPU** | **—** | **not a term** |

**Ghostty is the falsifier** — and the reason an earlier version of this section, *"maximising the GPU is backwards,"* was wrong as stated. Ghostty is **Metal-native *and* per-pane**, and measures **24 panes in one window at 0.0% idle CPU / 351 MB**. If the API were the cost axis, that reading is impossible. What survives is **surfaces per window**, not *GPU or not* — so the cheapest lever is the one nobody files under "renderer": **drop the 120 Hz display to 60 Hz.** One reversible click, and a text UI gains nothing from 120 Hz.

### Therefore: stop rendering what you do not read

Measured on this box with one ruler — [`scripts/terminal-bench.sh`](scripts/terminal-bench.sh), per-pid threads/RSS/ports from the **second** sample of `top -l 2` (never `ps %cpu`, a lifetime average that misread this box 2.3×). The decisive column is **loaded app CPU**: 18 panes repainting a byte-identical stream, every pane confirmed at 10.00 achieved fps.

| Terminal | **loaded app CPU** (18 panes @ 10 fps) | threads / pane | windows for 30 panes | per-pane scripting | console layer |
|---|---|---|---|---|---|
| **kitty** | **9.5%** — while carrying **22 % more bytes** | flat — 10 at 48 panes | **1** | `kitten @` · `$KITTY_WINDOW_ID` | — |
| iTerm2 | **10.5%** *in the cheap layout* (1 window × 20 panes, CPU renderer) | ~0.87–1.1 | 6 (forced by the Metal gate) | `ITERM_SESSION_ID` | — |
| WezTerm | 24.4% | **4.00, linear** | 1 | `wezterm cli` | — |
| Ghostty | 27.3% — highest, and 3 processes per loaded pane | **4.00, linear** | **1** | **none on macOS** (`performIpc` false; AppleScript only) | — |
| cmux | *not run under load* | **5.18, linear** (`5.18×panes + 10.6`) | 1 | **`CMUX_SURFACE_ID` + full socket API** | **built in** — sidebar row per pane, blue ring on attention, notifications panel, `notify` CLI |

**kitty wins among the challengers by 2.6–2.9× on loaded CPU — not on threads.** The thread-count rationale this section used to lead with is **retired**: WezTerm measured **4.00** threads/pane, not the ~7.0 previously published, and the falsification test written to kill the thread finding **fired** — 87 WezTerm threads produced *fewer* context switches than kitty's 10. Threads were a proxy; loaded CPU is the thing being proxied.

**And the migration is on HOLD, because the incumbent has not been beaten.** The one iTerm2 datapoint taken in the *cheap* layout — one window, 20 panes, CPU renderer — read **10.5% against kitty's 9.5%**: within ~10% on CPU and within one thread. Every other iTerm2 figure above comes from the *expensive* layout it is normally run in, which is a statement about how it is configured, not about what it can do. Two cheaper rungs are live and unmeasured: the eight render knobs have never been benchmarked since passing their own gate, and the dismissal of plain `tmux` rested on a premise since verified **false**. Switching terminals is the expensive move and it is **not yet justified** — see [`terminal-for-30-panes-2026-07-31.md`](docs/research/terminal-for-30-panes-2026-07-31.md) §9.

**cmux does not dominate kitty either**: it wins the console axis — it ships, natively, the *shape* of the exception surface described below — and has not been run under load at all.

#### So the question stopped being "which one" — it runs on both

A HOLD is only tolerable if it is not also a blocker. It stopped being one: **iTerm2 and kitty are both first-class**, and the same session machinery — Agent Teams, handoff, recycling, two-way comms, teardown — runs on either. One command wires the second one:

```bash
scripts/kitty-setup.sh          # idempotent · --check reports · --undo reverts
```

**The lock was never the renderer — it was a process boundary this repo already owned.** Claude Code's Agent-Teams pane backend is not linked against iTerm2 and never handshakes with it. Decompiled from the live 2.1.219 binary, its gate is an **env check plus a PATH lookup** — `TERM_PROGRAM==="iTerm.app" || !!ITERM_SESSION_ID`, then `$SHELL -lc "command -v it2"` — after which it drives panes through exactly five subcommands of whatever `it2` it resolved. So a program answering those five commands against `kitty @` gets **native kitty split panes** for assignee sessions. That is [`bin/it2-kitty`](bin/it2-kitty), and [`bin/it2-wrapper`](bin/it2-wrapper) execs it when `KITTY_WINDOW_ID` is set. No fork of either terminal — which is just as well, since iTerm2 is GPL-2.0-only and kitty is GPL-3.0, i.e. legally uncombinable.

Three seams carry the rest, and each was a measured defect before it was a design:

| Seam | What it does | The defect that proved it necessary |
|---|---|---|
| `ITERM_SESSION_ID = w0t0p0:$KITTY_WINDOW_ID` | gives a kitty pane an id the whole fleet already knows how to read | the **colon is required** — Claude Code derives the leader id as everything after the first colon, and returns `null` without one, silently splitting from whatever pane is active |
| `~/.claude/shims` first on the **login** PATH | wins the lookup Claude Code actually performs | `-lc` is login-but-not-interactive: it reads `.zprofile` and **never `.zshrc`**, and the resolved path is **cached for the process lifetime** — losing that race bypasses the wrapper on iTerm2 too |
| the divert predicate, written once | decides "am I in kitty" identically everywhere | `handoff-fire.sh` and `cc-pane` deliberately resolve the *raw* it2 to inherit a pane's profile. Inside kitty there is no profile to inherit, so that bypass is pure loss — it resolves an iTerm2 client with no iTerm2 to talk to |

That last row is the one that bites, and it is why the predicate is pinned by a test rather than trusted: a handoff that **splits the pane with one binary and addresses it with another** fails in a way no single-file test can see.

**What is verified, and on which terminal.** Every ✅ below names the evidence that earned it; none of them is an inference from reading source:

| Surface | iTerm2 | kitty | Evidence |
|---|---|---|---|
| Agent-Teams assignee panes | ✅ | ✅ | **this change was written by two of them** — see below |
| Pane seam (`cc-pane` address/list/send/close) | ✅ | ✅ | live on this box; `address <gone>` correctly returns an authoritative **NO**, not indeterminate |
| Two-way comms | ✅ | ✅ | delivery is **a file, not a keystroke** (§1) — terminal-agnostic by construction; only the pane-liveness oracle touched a terminal |
| Session register · teardown · crash watchdog | ✅ | ✅ | live registry holds kitty-hosted sessions keyed by bare kitty pane ids across all four accounts; teardown resolves the shim, and the operator page is a macOS notification, not an iTerm2 call |
| Handoff / recycle — **split + type + focus** | ✅ | ✅ | argv verified verb by verb against the contract: `focus-window --match id:`, `close-window`, `send-text` preserving the raw `Ctrl-U` byte, and `run` appending `\r`. `focus` with no target **refuses** rather than hijacking the active pane |
| Handoff — tty / tab / background-tab helpers | ✅ | ✅ | pane→`pid`→`ps -o tty=` for the tty kitty does not expose; `--keep-focus` on the background tab. The **two exit states** are the contract — a failed query and an absent pane must not be confused, or a live successor reads dead — and inverting them is one of the 10 mutations the suite convicts |
| Limit-recovery · boot-resume · pane census | ✅ | ✅ | AppleScript pane-open → `kitty @ launch`. The census was *worse than inert* on kitty: it truthfully reported **0 iTerm2 panes** on a box with a dozen live ones, zeroing the operator's only load-shed lever. Every kitty failure mode now lands on **null**, never `0` |

**The Agent-Teams row is self-demonstrating.** Part of this section's own work was done by two assignee sessions spawned from a kitty pane, and the census taken across that spawn is the evidence: 19 panes before, **21 after**, the two new ones being kitty windows `30` and `31` whose foreground process is `claude.exe --agent-id k2-handoff@…` and `--agent-id k3-recovery@…`. That is the entire chain exercised end to end — Claude Code's pane backend → the login-PATH-resolved `it2` → the wrapper → the divert → `kitty @ launch` — with no stub anywhere in it.

**Two-way comms was already portable and nobody had noticed** — which is the useful lesson. Because a message is a file that hooks read, none of it was ever terminal-coupled; the *only* terminal call in the path was asking "is that pane still alive". When that oracle broke on kitty it returned **unknown** rather than **dead**, so nothing was mis-delivered and nothing went red. **A safe degradation is still a defect** — it was invisible precisely because it failed correctly.

#### The instrument, running — not a table read off somebody's source tree

<div align="center">

<img src="assets/demo/terminal-bench.webp" width="900" alt="Terminal recording of scripts/terminal-bench.sh measuring the live terminals on this machine in five scenes. Scene 1 greps the READ-ONLY contract out of the script's own source. Scene 2 censuses which terminals are actually running, matching on the ps comm basename. Scene 3 runs a full drift row against kitty and prints verdict=OK. Scene 4 runs against the live iTerm2 and prints a GPU to CPU frame ratio below one, showing it renders mostly on the CPU, ending in verdict=PARTIAL. Scene 5 runs against WezTerm, which is not installed, and prints verdict=NO-DATA with exit 3.">

<sub><b>Every number in this README's terminal section came out of this instrument, on this machine.</b> Recorded with <a href="https://github.com/charmbracelet/vhs">VHS</a> from <a href="assets/demo/terminal-bench.tape"><code>assets/demo/terminal-bench.tape</code></a> — re-runnable, so it cannot drift from the script it documents. No <code>--dry-run</code>, no mock-up: <a href="scripts/terminal-bench.sh"><code>terminal-bench.sh</code></a> is <b>read-only by construction</b> (creates no panes, closes none, writes no preference), which is the only reason it is safe to aim at a live fleet mid-session. <a href="assets/demo/terminal-bench.mp4">Full-resolution video</a> — <b>1920×1080, 60 fps</b>, an unedited <code>screencapture</code> of the same sequence at display refresh. The inline image is the VHS render; the two take different routes for a measured reason, in <a href="assets/demo/terminal-bench.tape">the tape header</a>.</sub>

</div>

**Why three different verdicts are on camera.** An instrument that cannot say *"I did not measure this"* is worthless, because a reader then cannot tell a measured zero from a run that never happened. So `verdict=` has three terminal states and the clip shows all three: `OK` (both readings + GPU profile resolved), `PARTIAL` (**every number real, but one reading cannot support a leak verdict** — so the OK token is refused rather than overclaimed), and `NO-DATA` at exit 3 (the app is not running).

**The readings behind the table**, verbatim from that run, 2026-07-31, against this machine's own live fleet of 13 Claude Code sessions:

| live app | CPU | threads | mach ports | RSS | **GPU:CPU frame ratio** | verdict |
|---|---|---|---|---|---|---|
| **iTerm2** (incumbent) | **106.9%** | 12 | 700 | 800 MB | **0.53 : 1 — draws mostly on the CPU** | `PARTIAL` |
| **kitty** | **0.0%** | **8** | 362 | 321 MB | **50.0 : 1** | `OK` |
| Ghostty | 0.0% | 8 | 338 | 84 MB | 16.0 : 1 | `OK` |
| WezTerm | — | — | — | — | — | `NO-DATA` (not installed **at the time of that run**) |
| cmux | — | — | — | — | — | **not driveable by this instrument** — see below |

**WezTerm is no longer NO-DATA — it was measured under the films** (2026-08-01), and the two
instruments agree: **27.2% app CPU, 82 threads (4.56/pane), 177 MB, GPU:CPU 107.5 : 1** at 18 panes
of the same load, against the candidate table's independently-derived 24.4% and 4.00 threads/pane.
Those columns are not the same experiment as the idle row above it — the rows above are the LIVE
fleet at rest, these are 18 panes under load — so they are reported here rather than merged into a
table that would then be mixing two regimes. The same run puts kitty at **10.4% / 10 threads** and
Ghostty at **31.7% / 139 threads**, each with the row committed beside its film.

**cmux is absent because this instrument cannot drive it, and that is a property of cmux, not an
omission.** Two independent blockers, both measured 2026-08-01: its control socket refuses processes
that did not start inside cmux (`Access denied - only processes started inside cmux can connect`,
with `socketPassword` empty in `~/.config/cmux/cmux.json`), and `cmux new-split` accepts no
`--command`, so even an authorised caller cannot put the load into the panes it creates — only
`workspace create` takes one, which yields a single loaded pane and seventeen idle shells. Filming
it would mean writing the operator's cmux settings to mint a socket password AND reverse-engineering
the `--layout` JSON schema, which is a disproportionate change to a running app for a screen
recording. Its **thread cost is still in the candidate table above** (5.18/pane, linear), measured
by the earlier structural pass that did not need per-pane commands.

That `0.53 : 1` is the finding the whole section rests on, and it is **measured by profile, not read off a flag** — `sample` symbol counts, because a loaded GPU driver and a warm shader cache can only ever refute *"absent"*, never establish *"used"*. iTerm2 ships a Metal renderer and was still resolving 235 CPU frames to 125 GPU frames while burning a full core.

**The leak axis — where the evidence genuinely runs out.** iTerm2 was measured at **+76 mach ports/hour** at frozen layout. kitty over the same instrument read **+0 ports, +0 windows, +0 offscreen** — but read that with its resolution attached: a 45-second window cannot resolve a rate finer than ~80 ports/hr, so it **cannot exclude iTerm2's +76/hr**. It is a real reading and a weak bound.

A 30-minute run was taken to get a sharp one (at 1800 s, one port is 2/hr) and **it did not deliver a clean bound either** — the window census fell 36 → 19 while it held, so the layout was not constant and its `+5 ports` cannot be separated into leaked-versus-released. Recorded as still-open in [`terminal-for-30-panes-2026-07-31.md`](docs/research/terminal-for-30-panes-2026-07-31.md) §6.1 rather than quoted as a bound it is not. What that run *does* show is churn: **the window population fell by 17 and offscreen fell by 18** (−17 total, −18 offscreen ⇒ onscreen actually *rose* by 1 — the drift row's `windows` column is the on+off total, so this read "−17 onscreen" until 2026-07-31) for +5 ports and +20 MB — kitty gave the windows back, where iTerm2 had **98 windows survive `close()`** ([upstream #12097](https://gitlab.com/gnachman/iterm2/-/issues/12097), open since 2025-01-01).

**So the sustained-runtime question is open, and it is the largest gap in the terminal case** — stated here rather than papered over. It compounds with the HOLD above rather than being offset by it: the challenger is ahead of its rivals on loaded CPU, level with the incumbent in the incumbent's cheap layout, and unproven over hours. **That is exactly why the move below is a seam and not a migration** — a `CC_PANE_ID` abstraction costs the same whichever terminal eventually wins, and stops the question from having to be answered before anything else can proceed.

**Reproduce any row yourself** — it is one read-only command per terminal, and it will refuse to invent a number:

```bash
scripts/terminal-bench.sh --app kitty  --interval 1800   # full row + drift  → verdict=OK
scripts/terminal-bench.sh --app iTerm2 --interval 0      # single reading    → verdict=PARTIAL
scripts/terminal-bench.sh --app wezterm --interval 0     # not running       → verdict=NO-DATA, exit 3
```

The first command is the one that failed above, and **it can no longer fail that way quietly**. `verdict=OK` never certified the constant-layout precondition — it attested that two readings and a GPU profile were obtained, and nothing about whether panes opened underneath the run — so the instrument now measures the precondition itself, re-checks it every `--watch` seconds, and **aborts with `verdict=LAYOUT-DRIFT` (exit 4) instead of printing a confounded row**. The gate keys on the *onscreen* count, and on offscreen only when offscreen **falls**: a *rising* offscreen count is the leak being measured, so a gate keyed on the `windows` total would make a leaking terminal abort its own measurement and become structurally unable to report the leak.

**The raw transcripts are committed**, so every number above is auditable against the run that produced it rather than against this table: [`bench-live-3way-2026-07-31.txt`](docs/research/data/bench-live-3way-2026-07-31.txt) (the kitty/Ghostty/cmux readings) and [`kitty-drift-30min-2026-07-31.txt`](docs/research/data/kitty-drift-30min-2026-07-31.txt) (the 30-minute run, including the window census that invalidates it as a drift bound).

Full method, per-candidate rows and the falsification plan: [`terminal-for-30-panes-2026-07-31.md`](docs/research/terminal-for-30-panes-2026-07-31.md) · adjudication of the two outside reports: [`l3-l4-terminal-and-workflow-2026-07-31.md`](docs/research/l3-l4-terminal-and-workflow-2026-07-31.md) · the plan this feeds: [`TERMINAL_AGNOSTIC_L3_L4.md`](docs/plans/TERMINAL_AGNOSTIC_L3_L4.md).

#### And the renderers themselves, under the load — one film per terminal

The section above films the *instrument*. This films the *subject*: 18 panes of the identical
Ink-shaped load ([`tui-load.sh`](scripts/tui-load.sh) — alternate screen, 24-bit colour, full-frame
repaint at 10 fps) repainting in each candidate, recorded at **1920×1080, 60 fps**, with that
terminal's [`terminal-bench.sh`](scripts/terminal-bench.sh) row taken **during the same take** so the
film and the numbers describe one event rather than two.

<div align="center">

<img src="assets/demo/renderer-grid.webp" width="900" alt="An animated clip, three terminals stacked, each showing an 18-pane window repainting under the same synthetic load. Colour ramps shift row by row in every pane. kitty's panes form an even grid; WezTerm's and Ghostty's form uneven binary split trees. Each pane header shows its own measured column-by-row geometry.">

<sub><b>The films themselves, playing — 18 panes, one window, the same load, this machine.</b> 3 s of each take at 10 fps, 900 px per tile; the panes are repainting at 10 fps, so this is the real cadence, not a slideshow. <b>Full 1080p60 masters</b> (1920×1080, 60/1, ~15 s): <a href="assets/demo/renderer-kitty.mp4">kitty</a> · <a href="assets/demo/renderer-wezterm.mp4">WezTerm</a> · <a href="assets/demo/renderer-ghostty.mp4">Ghostty</a> — GitHub strips <code>&lt;video&gt;</code>, so an inline image is the only thing that can move here and the masters are links by necessity. Measurement row taken during each take: <a href="assets/demo/renderer-kitty.txt">kitty</a> · <a href="assets/demo/renderer-wezterm.txt">WezTerm</a> · <a href="assets/demo/renderer-ghostty.txt">Ghostty</a>. Reproduce: <a href="assets/demo/renderer-film.sh"><code>renderer-film.sh --app kitty</code></a>, then <a href="assets/demo/renderer-grid.sh"><code>renderer-grid.sh</code></a>.</sub>

</div>

**What the films are evidence of, and what they are not.** They show that the load really ran, in
that terminal, on this box — not that one terminal beat another on looks. Three things a reader
should know before drawing anything from them:

- **The pane geometry differs because the terminals differ.** kitty is run with its `grid` layout,
  which is what an 18-pane kitty user would actually use; WezTerm and Ghostty have no grid layout, so
  they get their own binary split trees and their cells come out uneven. That asymmetry is a property
  of the candidates, and it is disclosed rather than equalised away.
- **Each pane's header shows its own measured geometry** (`62x19`, `94x22`, `79x40`…) — and that is
  there because it was wrong. `tui-load.sh` sized itself with `tput cols`, which inside a command
  substitution reports the terminfo default **80×24** instead of the pane, so every WezTerm pane
  painted a fixed small frame while kitty painted full-size ones. The generator whose entire purpose
  is an *identical* load across candidates was not delivering one, and nothing said so — 80×24 is a
  plausible size, not an error. Fixed to read `stty size`; the geometry and which probe answered are
  now recorded per pane.
- **Ghostty's row is app-wide, not per-pane.** Ghostty is a single shared process that was already
  running the operator's own surfaces, so its totals include panes these films did not create. The
  row says so; the per-pane division there is an upper bound.

**The incumbent is missing, and the reason is worth more than the film would have been.** iTerm2 is
the terminal this whole section argues about, and it is the one not filmed. The guard was "film it
only when iTerm2 is not running" — no live sessions present, none disturbed — and that guard passed.
**Launching iTerm2 restored the operator's windows anyway.** Window restoration reopened three
windows that had not existed a second earlier, the driver's `current window` resolved to one of
*theirs*, and 18 splits landed in restored sessions before the take was aborted and the app returned
to not-running. The resurrection happens **at launch**, before any check can run — so
[`renderer-film.sh`](assets/demo/renderer-film.sh) now refuses iTerm2 outright and points at
[`iterm-metal-bench-app.sh`](scripts/iterm-metal-bench-app.sh), which clones iTerm2 under its own
bundle id and defaults domain and is the only route that restores nothing.

**Stalls are measured at the source, and every candidate has none.** ScreenCaptureKit emits a frame
only when the window's content changes, so the gap between delivered frames *is* how long that window
sat unchanged: kitty, WezTerm and Ghostty each recorded **0 gaps over 1.5 s**, with longest gaps of
**0.07 s, 0.06 s and 0.04 s**. An earlier pixel-based reading off ffmpeg `freezedetect` said otherwise
and was **withdrawn** — it averages over the whole frame, so on sparse coloured text it called an
entire 20-second film "frozen from t=0" while 808 distinct frames sat in it, and its verdict moved
with how much letterboxing each window's shape happened to need, which made it non-comparable across
the very candidates being compared.

But the renderer is the *second*-order fix. A 30-pane grid is a **polling** interface — its cost scales with agent count, which is precisely the cost saturating the compositor. Exception routing does not scale with agent count at all. And the notifier that replaces it **already exists**: [`cc-permission-beacon.sh`](hooks/cc-permission-beacon.sh) is wired on `PermissionRequest` and writes every blocked session to `/tmp/cc-permission-pending/`. **It simply has no face** — nothing renders that queue as the operator's primary surface, so the grid stands in for it. Caught live while this section was written: two sessions blocked at once under full three-monitor visibility, one unattended for **6.6 minutes**.

Nor can the allow-list close the gap: **88.3% of prompting Bash calls are compound**, so a `Bash(prefix:*)` list caps at ~2.4% coverage regardless of rule count — already at `defaultMode: auto` with **350 allow / 6 ask / 41 deny**. The residue is the guardrail working. The defect is not that it blocks; it is that *discovering* the block costs a full-screen poll.

#### Driving it: every pane gesture, and the two the keyboard cannot reach

<div align="center">

<img src="assets/demo/kitty-panes.webp" width="900" alt="Screen recording of a single kitty window running the pane-management sequence. A narration pane on the left prints each chord as it fires; the window splits right, then below, into three coloured panes. A pane then swaps places with its neighbour, another is thrown to the top edge, per-pane title bars appear across the tops of the panes, and finally one pane leaves the split entirely and a tab bar appears at the bottom of the window holding it.">

<sub><b>One kitty window, one sequence, every chord below.</b> The narration pane prints each chord as it fires, so the frame that shows a change already names the action that caused it. Nothing is simulated: each beat is the mappable action the chord is bound to, driven over that window's own remote-control socket — <b>keystrokes are deliberately not synthesised</b>, because macOS sends them to the frontmost process and on this box that is usually one of ~30 live agent panes. <a href="assets/demo/kitty-panes.mp4">Full-resolution video</a> — <b>1920×1080, 60 fps</b> (the window-scoped capture delivered <b>41.7 fps</b> of distinct frames; the container is 60). Reproduce with <a href="assets/demo/kitty-panes-capture.sh"><code>assets/demo/kitty-panes-capture.sh</code></a>.</sub>

</div>

**The chords.** All of them live in [`config/kitty.conf`](config/kitty.conf) and are pinned by
[`tests/kitty-conf-bindings.bats`](tests/kitty-conf-bindings.bats) against kitty's *own* config
loader — so a rename in a future kitty fails there rather than under your fingers. After editing,
`kitten @ load-config` applies everything except `allow_remote_control` and `listen_on`.

| | Chord | Action | Note |
|---|---|---|---|
| **Split** | ⌘D · ⌘⇧D | `launch --location=vsplit\|hsplit` | right · below, inheriting the cwd |
| | ⌘W | `close_window` | last pane closes the tab, then the window |
| | ⌘⇧↩ | `toggle_layout stack` | zoom one pane to fill the tab |
| **Focus** | ⌘⌥←→↑↓ | `neighboring_window` | split-aware; ⌘] ⌘[ cycle |
| **Move the pane** | ⌘⇧←→↑↓ | `move_window` | a **swap** with the neighbouring slot |
| | ⌘⌃←→↑↓ | `layout_action move_to_screen_edge` | the placement a swap cannot express |
| | ⌘⌃R · ⌘⌃E | `layout_action rotate` · `equalize` | flip a split's axis · even them out |
| | ⌘R | `start_resizing_window` | arrows, then Esc |
| **Leave the tab** | ⌘⇧O | `detach_window ask` | chooser — **this is the cross-monitor move** |
| | ⌘⌥O · ⌘⌃O | `detach_window` · `detach_tab ask` | into a new OS window · move the whole tab |
| **Mouse** | drag a divider | resize | needs `window_drag_tolerance` above kitty's 2 pt |
| | ⌘⇧B, then drag a title bar | re-order | ⌘⇧B is what *draws* the handle |

**Three things that are not guessable, and cost the time this section exists to save.**

- **`move_window` is a swap, and a silent no-op with no neighbour.** In a two-pane side-by-side
  tab, ⌘⇧↑ and ⌘⇧↓ are correctly dead — no beep, no message, nothing — which is indistinguishable
  from a binding that failed to load. `move_to_screen_edge` is the action for "put it *there*".
- **kitty has no action that sends a window to a display.** A pane's monitor is simply wherever its
  OS window sits, so the route to the other screen is to *detach into a window that is already
  there* — ⌘⇧O, pick the tab. Measured on kitty 0.48.2: window id and child pid are **unchanged**
  across a detach into a new OS window and then into an existing tab, so a running Claude Code
  session moves with its pty, scrollback and process intact.
- **The mouse can drag a pane only by a title bar kitty does not draw** — hence ⌘⇧B — and only
  **tabs**, never panes, can be dragged *between* OS windows. That gesture also needs
  `tab_bar_min_tabs 1`, which is deliberately off here: a permanently visible tab bar costs one
  text row in every OS window, and at 30 panes that row is screen space this repo will not spend.

### Roadmap

| When | Move | Why it is sized this way |
|---|---|---|
| **Now** | Do **not** cap V8 heaps; stop the automation minting **windows**; add a window-count rung to `capacity-alarm.sh` (warn 25 / page 60, measured as *drift*) | free, reversible, and windows are the 2.35× unit |
| ~~**Next**~~ **Done** | ~~Migrate the renderer to **kitty**~~ → **support both**, behind one seam ([§6](#so-the-question-stopped-being-which-one--it-runs-on-both)) | the migration framing was wrong: a seam costs the same and does not require winning the argument first. `scripts/kitty-setup.sh` wires it in one command |
| **Then** | Give the beacon a face — **a console, not a terminal**: one row per session, a queue fed by the beacon, zoom-to-full-screen on demand, a dispatch composer | implements no VT at all; rendering then scales with sessions *blocked* (0–3), not sessions *running* (30+) |

**Writing a terminal from scratch was considered and rejected.** WindowServer is the ceiling and it is Apple's — 30 panes in one window cost ~+11.2 pp of a core inside the compositor, the floor for *any* application, and kitty already sits on it. A from-scratch emulator's best case is matching something already installed, while owning VT correctness under Ink's alternate-screen/resize/wide-char usage forever.

---

<details>
<summary><b>Reference</b> — daemons, browser automation, shell aliases, agents and commands</summary>

<br>

**13 launchd daemons** (`launchd/`, all low-priority; `install.sh` copies and loads them):

| Plist | Schedule | Purpose |
|---|---|---|
| `com.claude.dispatcher` | 15 min | open backlog → quota-aware wave plan → fire worker sessions |
| `com.claude.discovery` | 60 min | scan ledgers, plans and gates for new work → feed the backlog |
| `com.chrisren.autonomy-sweep` | 5 min | alarms, pages and decision-packet sweep → operator escalation |
| `com.claude.desk-invariant` | 5 min | desk liveness + recycle-armedness fail-loud monitor |
| `com.claude.boot-resume` | 5 min | post-reboot ghost-session detection + consolidated resume |
| `com.claude.team-orphan-reaper` | 10 min | archive dead teammate panes and worktrees (identity-pinned) |
| `com.claude.postland-verify` | 5 min | assert a landing actually reached trunk, by content |
| `com.claude.log-rotation` | 60 min | size-gated rotation of `idl.jsonl` + bash command logs |
| `com.claude.caffeinate-floor` | KeepAlive | sleep-prevention floor while sessions run |
| `com.claude.power-policy-verify` | 60 min | assert pmset/caffeinate continuity posture |
| `com.claude.nightly-regression` | 4 am | full bats suite against the live deployment |
| `com.claude.session-search-sweep` | 60 s | catch missed session transcripts |
| `com.claude.session-search-backfill` | Sun 3 am | full backfill of all sessions |

**Status line.** [`statusline.sh`](statusline.sh) shows `dir (commit) branch* · N%`. The context percentage applies a 48% offset to the input-only token share to approximate what is actually left (output buffer ~32%, auto-compact ~6.5%, warning ~10%). Under 60% gray, 60–90% default, over 90% red. [`notify.sh`](hooks/notify.sh) pairs a system sound with a desktop alert that **names the session it came from** — `Permission · <dir>` over `<session> · <tool>` over the actual blocked command — debounced 2 s **per session**, so two sessions blocking at once are two alerts rather than one. Funk for a permission request, Blow for a question, Glass for a plan ready to review, Purr for task completion (sound only).

**Browser automation.** [`bin/browsermcp-wrapper.sh`](bin/browsermcp-wrapper.sh) wraps [BrowserMCP](https://browsermcp.io) to load the NVM environment consistently — which fixes most MCP connection failures — registered in `~/.claude/.mcp.json`:

```json
{ "mcpServers": { "browsermcp": { "command": "~/bin/browsermcp-wrapper.sh", "timeout": 15000 } } }
```

Workflow: `navigate → snapshot → click/type` by element ref. `agent-browser` is the CLI fallback when the MCP server is unavailable.

**Shell aliases** (`~/.zshrc`): `claude` (auto-update + auto mode + task-list persistence) · `claude-default` (no auto mode) · `claude-plan` (plan mode + "ultrathink") · `claude2`/`3`/`4` (isolated `CLAUDE_CONFIG_DIR` per account) · `claude-fable*` (frontier tier) · `claude-which` (active config dir).

**19 commands** (`commands/`) — `/handoff`, `/ship`, `/wrap`, `/desk`, `/accounts`, `/limit-recover`, `/research`, `/review`, `/commit`, `/harvest-skill` and more. **15 skills** (`skills/`) — agent-teams, research-subagents, frontier-routing, coding-standards, plan-conventions, cc-upgrade-gate and others. **4 agents** (`agents/`) — `deep-research` (frontier/adversarial research), `deep-research-sonnet` (bulk-fan-out worker, currently benched), `frontier-derivation` (baseline-blind derivation panelist for `/frontier-run`), `research-decomposition-critic` (pre-spawn decomposition critic). Deployed by COPY into each config dir's `agents/`, never by symlink.

**Editing the diagrams.** Sources live in `assets/diagrams/*.mmd` and render through [beautiful-mermaid](https://www.npmjs.com/package/beautiful-mermaid) — the ELK-based engine behind Cursor's agent panel — into per-mode SVGs, because GitHub cannot swap its own dagre renderer. Edit the `.mmd`, run `npm run diagrams`, commit the regenerated SVGs.

**Re-recording the demos.** `assets/demo/handoff-real.webp` regenerates from its committed tape — `vhs assets/demo/handoff-real.tape`, then `gif2webp -m 6 -min_size` — so the command output in the README can never drift from the scripts. `assets/demo/handoff-live.webp` is a screen recording of an actual `/handoff`; it is captured by hand (`screencapture -v`, cropped to the iTerm2 window with `ffmpeg`) because it depends on a live fleet, so there is no script for it, and it is encoded `img2webp -near_lossless 40`. Both are WebP but by different routes, and the reason matters: the VHS clip is flat terminal output, so `gif2webp` converts it losslessly and 10.6 % smaller, whereas the live recording must be **near-lossless** — an ordinary lossy WebP encodes each frame as a partial update rectangle, and the flat grey of an unfocused pane re-quantizes differently inside that rectangle than outside, leaving a visible vertical seam at its edge. Near-lossless costs 21 % more than the GIF it replaced and buys ~3× better colour fidelity. Measurements in the `demo-recording` skill.

`assets/demo/terminal-bench.*` is the third, and it is the only one needing **two** routes. The inline WebP takes the VHS path like the first — `vhs assets/demo/terminal-bench.tape`, then `gif2webp -m 6 -min_size -mt`. The linked MP4 **cannot**: VHS 0.11 ignores `Set Framerate` for its mp4 muxer and emits 25 fps whatever the tape asks — probed directly, since a tool's documented option silently not applying is exactly the kind of thing that ships as a false caption. So the 1080p60 master is a real `screencapture` of [`terminal-bench-capture.sh`](assets/demo/terminal-bench-capture.sh) at display refresh, and the tape deliberately emits no mp4 that could overwrite it. GitHub's sanitizer strips `<video>`, so the MP4 is only ever a link beside the image.

**That capture route can film the operator's screen, and three separate leaks were caught by the mandatory contact sheet — none by any encoder error.** `screencapture -l<window-id>` does *not* scope **video** to that window (it recorded the whole display, Dock and other windows — use `-R x,y,w,h` with your own window covering the rect); a macOS notification banner carrying live session ids landed in the top-right (banners are right-aligned — keep the rect's right edge clear of them); and the window closed before the `-V` budget expired, so the tail filmed the desktop. Scan **every** second for that last one rather than sampling — mean luma separates the states unambiguously (terminal ≈ 6.4k, wallpaper ≈ 22.8k of 65535). Rect geometry and the full recipe are in the tape header.

Unlike the other two, this clip has a **live dependency it does not control**: it measures whatever terminals are running when it is recorded, so a re-record on another day legitimately produces different numbers, and the `verdict=NO-DATA` scene stays honest only while WezTerm is genuinely absent. Re-check the scene comments against reality first. And note `pgrep -x iTerm2` **cannot see iTerm2 on macOS** — its accounting name is the first 16 chars of its full path — which is why the script and the tape both match on the `ps` comm basename.

`assets/demo/kitty-panes.*` is the fourth, and it settles the capture problem the one above only worked around. It is filmed **window-scoped** — `tools/terminal-bench/window-film.swift` (ScreenCaptureKit, compiled with `swiftc`; interpreted, the same call aborts inside swift-frontend), resolved by title through `window-rect.swift`, exactly as [`renderer-film.sh`](assets/demo/renderer-film.sh) does. That is a **safety property, not a convenience**: a `-R` rect films whatever is on top of it, and the first attempt at this very demo recorded the operator's browser — their tabs, their mail, their home address — because the demo window was behind it. That take was deleted unused. Positioning the window to fix the rect is not available either: it needs Accessibility, and `osascript` here answers *"not allowed assistive access"* (-1719). The window-scoped filter composites the window's own content, so occlusion, the Dock and notification banners become **impossible** to film rather than something a contact sheet has to catch — and it works while the window is on no visible Space at all, which is where a freshly launched window on this four-display box actually lands.

It also takes **two routes for one sequence**, for a measured reason. The linked 1080p60 master is filmed with the panes running [`tui-load.sh`](scripts/tui-load.sh) at 60 Hz, because ScreenCaptureKit is **change-driven**: with still panes the same take delivered **26 frames in 38 s (0.68 fps)** while the container could still be muxed at 60, which would have made "1080p60" true of the file and false of the pixels. With the panes repainting it delivers **41.7 fps**, and the caption states that number beside the container's. The inline WebP is built from a **still-pane** take (`CC_PANES_STATIC=1`) because that same 60 Hz churn is close to incompressible — the animated WebP of the moving take came out **38 MB**, against **167 KB** for the still one, whose 144 sampled frames the encoder merges into **11** stored frames with no loss of anything the image exists to show: the pane moves are discrete state changes, not motion.

**Rebuilding the banner.** It is generated, never hand-drawn: `python3 tools/banner/gen.py --out assets/banner`. The generator refuses to emit rather than ship a subtly wrong asset — periods that do not divide the master loop, a loop whose first and last frame differ, a stride that drifts out of lock with the ground it walks on. Verify one with `scripts/banner-verify.sh <asset> --period <P>` (six checks, all able to fail; the hero loop is `--period 240`), and prove every beat is actually VISIBLE with `scripts/banner-beat-ink.py assets/banner/v6*.svg` — it renders each beat whole and again with that beat suppressed, and requires a real pixel difference at the README's own 838 px width. That gate exists because every other one is structural: a meteor trail once shipped painting **zero pixels** — a horizontal path's bounding box has no height, so the gradient filling it was never drawn — and the markup parsed, the animation was singular and the loop still sealed shut. Sabotage every gate at once with `scripts/banner-gate-redproof.py` (34 cases, each required to fire on its own message). **The animated SVG is the deliverable, not a fallback** — GitHub serves it through camo as an image, and CSS animations inside an SVG loaded as an image do run, which is why the inline asset is vector.

</details>

<div align="center">
<sub>Structure of this README derived with the full Minto Pyramid Principle — audit trail in <a href="docs/research/README-rewrite-2026-07-28.pyramid-worklog.md"><code>docs/research/README-rewrite-2026-07-28.pyramid-worklog.md</code></a>, and <a href="docs/research/README-section6.pyramid-worklog.md"><code>README-section6.pyramid-worklog.md</code></a> for §6</sub>
</div>
