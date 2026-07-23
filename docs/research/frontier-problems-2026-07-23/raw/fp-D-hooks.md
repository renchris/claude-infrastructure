<!-- source: /Users/chrisren/.claude-secondary/projects/-Users-chrisren-Development-claude-infrastructure/309f570a-da52-4ee2-a49c-9b51bed73cf3.jsonl
 turns=63 assistant_texts=13 last_stop=end_turn mail_injections=[] -->

Saturation reached — teammate-checkpoint.sh gates the 16 git calls behind `/tmp/worktree-*` CWD detection (header lines 17-20, "every N tool uses"), so it's ~3-jq-cheap on the common path, not the top offender (next-call falsifiability: reading further would confirm the `case $CWD` bail, answer-invariant). Composing.

---

# Hook-Layer Event-Chain Integrity Audit — 61-hook layer

**Wiring truth = live `~/.claude/settings.json`** (identical `~/.claude-secondary/`). Repo `.claude/settings.json` carries **no `hooks` block** — only permissions. Hook *scripts* are per-file symlinks into the checkout; the *wiring* (event→hook, order, timeout) is **un-versioned, live-only**.

**⚠️ Load-bearing caveat (adversarial pass, foregrounded):** two of my four interference findings hinge on whether Claude Code runs same-event hooks **in parallel** (its documented model) vs sequentially in array order. No repo doc states either (`grep` for hook-order = empty). The repo's own design *hints* the authors assume no ordering guarantee — boundary-handoff checks session-continue's sentinel at runtime (line 156-163) rather than relying on array position. **Every racy latch below has zero `flock`**, so even a narrow parallel window bites. Where a finding is order-conditional I mark it `[order-dep]`.

## (a) Chain map — event | hooks in fire-order | block? | timeout | every-turn?

| Event | Hooks (settings order) | Blocking channel | Timeout(s) | Every-turn? |
|---|---|---|---|---|
| **PreToolUse:Bash** | curl-gate.py → validate-bash.sh → git-worktree-guard.sh → **keychain-guard.sh** → rm-safe-allowlist.sh | deny via exit-2/JSON | 5,10,10,**null→60**,5 | **hot** (every Bash) |
| PreToolUse:Write\|Edit\|MultiEdit | backup-before-write → check-edit-boundary → plan-agent-teams-default | deny | 10,10,5 | on edits |
| PreToolUse:Agent | agent-teams-enforce → frontier-spawn-gate | deny | 5,5 | on spawn |
| PreToolUse:mcp__ms365__* | enforce-email-formatting.py | deny | 10 | email only |
| **PostToolUse:Bash** | log-bash.sh → **waiting-recycle.sh** | advisory (block+addl) | 5,**null→60** | **hottest** |
| PostToolUse:* (all tools) | teammate-checkpoint.sh | none | 10 | **every tool** |
| PostToolUse:Write\|Edit | post-file-edit → plan-index-update → validate-plan-structure → plan-version-commit | none | 30,5,10,10 | on edits |
| **UserPromptSubmit:*** | cache-expiry-warning → memory-nudge → handoff-intent-nudge → research-precognition-nudge → mailbox-drain prompt | addlContext | 5×5 | **every prompt** |
| **Stop:*** | notify.sh complete → cache-expiry-tracker → teammate-checkpoint → session-continue → anti-deference-nudge → **notify.sh complete (dup)** → completion-assert → boundary-handoff → **boundary-handoff (dup, abs path)** | **4× decision:block** | 5,5,10,5,5,5,5,5,**null→60** | **every Stop** |
| SessionStart:* | session-start → setup-plan-symlinks → setup-task-symlinks → pre-session-validate → **lead-crash-watchdog** → session-register → activation-watch → dod-persist → session-index-start → config-mirror-assert → frontier-status → live-session-registry → mailbox-drain | addlContext | 5-10 (13 hooks) | per start/resume/clear |
| SessionEnd:* | session-end → session-index-end → session-save-id → harvest-skill-end → live-session-registry | none | 10,10,5,10,5 | per end |
| Notification:permission | **notify.sh permission ×2 (dup)** → push-critical.sh ×2 | none | 5,5,6,6 | per prompt |
| Notification:elicitation/idle | notify.sh ×2 + push-critical ×2 | none | 5-6 | per event |
| PermissionRequest:Bash/Ask/Exit | **notify.sh ×2 (dup)** per matcher | none | 5 | per request |
| TeammateIdle:* | teammate-auto-shutdown.sh | none | 5 | per idle |
| WorktreeCreate:* | worktree-setup.sh | none | 180 | per worktree |
| TaskCompleted:* | task-quality-gate.sh | none | 120 | per task |
| PreCompact:auto | date-echo → dod-persist.sh | none | 5,10 | per compact |

**Duplicate wirings (literal, not near-dup):** `notify.sh complete` ×2 on Stop; `notify.sh <kind>` ×2 on every Notification/PermissionRequest; `push-critical.sh` ×2 on Notification; `boundary-handoff.sh` ×2 on Stop (**same inode 255812777**, verified). Every permission prompt → 2× OS-notify + 2× `afplay` (notify.sh:67-69, backgrounded); every Stop → 2× completion notify.

## (b) Latency — fixed per-turn cost (no measurement exists)

**There is ZERO hook timing telemetry** (grep for timing/duration/latency/EPOCHREALTIME/`date +%s%N` across all hooks = empty). Everything below is static estimate; the "how to measure" is a settings-level timing shim (see FP-1).

| Hook (hot path) | Subprocess floor (common/non-target session) | Est. wall-cost | Notes |
|---|---|---|---|
| waiting-recycle.sh (PostToolUse:Bash) | **~8-11 spawns** even when abstaining: 1 `cat` stdin + **4× separate `jq`** parse (lines 307-310) + 1 `jq` IDL-write per abstain (288) + file-stats (KILL/disarm/arm/role) | ~0.1-0.2s/Bash | 795 lines, 155 subprocess-tokens, but arm-gate (line 342 `not-armed`) bails builders early; full pipeline only for the armed desk |
| teammate-checkpoint.sh (every PostToolUse, all tools) | ~3 `jq` + `case $CWD` bail | ~30-50ms/tool | 16 git calls **gated** behind `/tmp/worktree-*` detection (hdr 17-20) — cheap off-worktree |
| UserPromptSubmit chain (5 hooks) | 5 procs × 1-4 jq/grep each | **~0.1-0.3s/prompt** | all advisory |
| Stop chain (9 entries) | ~9 procs × 2-4 jq/grep; boundary's **6 git** only if ≥73% (git starts line 165, after line-142 below-threshold abstain); completion-assert greps transcript every Stop | **~0.3-0.8s/Stop** common; +0.3-0.8s near-boundary | dominated by process-spawn count, not any one hook |
| SessionStart (13 hooks) | 13 procs, several spawn bg subshells | ~0.3-1s/start | one-time per start/resume/clear |

**Worst offenders:** (1) the **4×-jq JSON-parse antipattern** in waiting-recycle (should be one `jq` extracting all fields) multiplied by every Bash call; (2) the **process-spawn count** on Stop (~20-30 subprocesses across 9 hooks) — no single hook is slow, the fan-out is. **Tail risk:** three `null`-timeout hooks default to **60s** — `keychain-guard.sh` (PreToolUse:Bash, **blocking**, un-auditable — live-only), `waiting-recycle.sh`, `boundary-handoff.sh`(dup). A hang in the blocking keychain-guard stalls every Bash for up to 60s with no telemetry to catch it.

## (c) Seam table — hook:line | seam | fail-behavior | visibility

| Seam | fail open/closed | visibility |
|---|---|---|
| **~54/60 hooks lack `set -e`** (only task-completed-index, session-index-{start,end}, post-file-edit, notify, migrate-plans have it) | fail-**open** (by design — avoids accidental exit-2 block) | **none** — mid-script failure → continues → `exit 0`, no trace |
| **Only 2 files use `flock`** (lib/session-index-helpers, lib/mailbox-pending); every latch in waiting-recycle/boundary/session-continue/completion-assert/anti-deference is check-then-write **unguarded** | fail-open, races silently | none |
| boundary-handoff.sh:196-212 latch check→write, **no flock**, **double-wired same inode** `[order-dep]` | open; TOCTOU → double `decision:block`+systemMessage (human-visible double page) | human (if it races) / else silent redundant abstain |
| **5 hooks append idl.jsonl, no flock** (boundary/anti-deference/completion-assert/operator-readout/waiting-recycle) | open — relies on O_APPEND <PIPE_BUF atomicity | **inverted**: boundary hdr 104-105 — one torn line aborts the `jq -rs` audit slurp → "no records" → **detector silently flips GREEN** |
| lead-crash-watchdog.sh:95-101 spawns daemon with **no pre-spawn liveness guard**; pidfile holds **lead** PID not daemon PID; SessionStart fires on startup\|resume\|clear | open — stacks N daemons per session | log only (`teammate-checkpoint.log`/watchdog log); duplicate crash-handling on actual crash |
| Stop: **4 hooks emit `decision:block`** (session-continue:—, completion-assert:126, anti-deference, boundary:227); only boundary guards (checks session-continue sentinel line 163). completion-assert & anti-deference guard **neither** `[order-dep]` | — contradictory advice possible (continue-work vs handoff-now vs stop-deferring) | model (merged block reasons); merge rule is harness-defined & unverified |
| curl-gate.py, **keychain-guard.sh**, enforce-email-formatting.py wired live-only, **absent from checkout** | keychain-guard is **blocking** PreToolUse:Bash @ null/60s — un-versioned, un-audited | none in-repo |
| **Wiring un-versioned** (no hooks block in any tracked settings) | a hook silently dropped from the array → **no eval → no IDL → reads as "healthy-dormant" not "broken"** (boundary hdr 52-60 documents exactly this past incident: C3 critic couldn't tell inert-from-dropped) | none — no git baseline to diff |
| notify.sh ×2 + push-critical ×2 on every Notification/Stop | open — double OS-notify + double afplay + double push | human (audible/visible double-fire) |
| 6 fire-and-forget `) &` bg subshells (lead-crash-watchdog:268, session-register:89/91, plan-version-commit:80, session-end:54, session-index-start:78, teammate-auto-shutdown:477) | open — no `wait`, no exit-check | none — bg failure invisible |

**Empirical vs theoretical:** double-inode wiring, no-`set -e` count, no-flock count, 4×-jq parse, 4 block-emitters, no-timing-telemetry, live-only gates, un-versioned wiring = **empirically verified** (read from disk). Parallel-execution → active TOCTOU, and the multi-block *merge* outcome = **theoretical** (harness behavior I cannot execute read-only). Daemon-stacking = code-confirmed; cross-refs a known incident.

---

## (d) CANDIDATE FRONTIER PROBLEMS

**FP-1 — The every-turn hook tax is completely unobservable**
- **Evidence:** grep for any hook timing (`EPOCHREALTIME`/`date +%s%N`/duration/latency) across all 61 hooks = **empty**; waiting-recycle.sh:307-310 spawns 4 separate `jq` per Bash call + IDL-write (288); three `null`-timeout hooks default to 60s incl. blocking keychain-guard.sh.
- **Mechanism class:** unobservability / missing-telemetry (trigger==failure has no meter).
- **Current mitigations + status:** per-hook IDL disposition lines exist for ~5 hooks (fired/abstained) but carry **no wall-clock**; nothing else. Status: **unmitigated**.
- **Why it resists normal fixes:** retrofitting timing into 60 heterogeneous scripts is invasive and self-inconsistent; the harness exposes no hook-timing surface; a slow hook only manifests as diffuse "Claude feels laggy," never attributed.
- **Quantified cost:** unmeasured. **How to measure:** wrap every command via one settings indirection — `command: "hook-time.sh <real-hook>"` where hook-time records `t0/t1` + event to a single `hooks-timing.jsonl`; alarm on p95 > timeout×0.5. One shim, zero per-hook edits.
- **Frontier-fix sketch:** a timing shim + a per-event budget assertion (sum of fixed spawns) surfaced in the same IDL the audit already trusts.
- **Confidence:** high / stale-risk low (telemetry absence is structural).

**FP-2 — Stop-event `decision:block` collision with no arbiter**
- **Evidence:** session-continue.sh, completion-assert.sh:126, anti-deference-nudge.sh, boundary-handoff.sh:227 all emit `{decision:block}` on the *same* Stop; only boundary self-suppresses (line 163 checks session-continue's sentinel). completion-assert & anti-deference check neither.
- **Mechanism class:** distributed coordination without a mutex (emergent fan-in conflict; each hook independently correct).
- **Current mitigations + status:** exactly **one pairwise guard** (boundary→session-continue). No global priority. Status: **partial**.
- **Why it resists normal fixes:** each hook is individually valid and independently authored; the contradiction (e.g., completion-assert "drive the remainder" vs boundary "handoff now" at 74% + open item) is only visible across the whole fan-in, and the merge outcome is harness-defined — you can't unit-test the conflict from any one hook.
- **Quantified cost:** unmeasured — how to measure: grep idl.jsonl for same-(sid,ts) `fired` rows across ≥2 Stop hooks; each is a live collision.
- **Frontier-fix sketch:** a single Stop *arbiter* hook (or a priority field in a shared lock dir) that collects intents and emits ONE block by precedence ⛔>📤>🔧>📦; the 4 hooks write intent, don't each block.
- **Confidence:** high on structure / medium on runtime impact (order-dep) / stale-risk medium (a CC version could define merge semantics).

**FP-3 — IDL append-race silently greens the un-gameable detector**
- **Evidence:** 5 hooks `>> $IDL` with no flock (boundary/anti-deference/completion-assert/operator-readout/waiting-recycle); boundary hdr 104-109 states one malformed line aborts the cc-audit `jq -rs` slurp → reads as "no records" → alarm GREEN.
- **Mechanism class:** write-contention with inverted blast radius (low-prob fault disables the very detector meant to catch faults).
- **Current mitigations + status:** every field is `jq`-encoded to prevent *self*-malformed lines (boundary 106-108) — but that does **nothing** against two hooks' writes *interleaving* on one Stop. Status: **partially mitigated, race unaddressed**.
- **Why it resists normal fixes:** single-line O_APPEND is *usually* atomic (<PIPE_BUF), so it passes every test and fails only under real concurrent Stop-fan-out — invisible in CI, and when it fails it fails *silent-green*.
- **Quantified cost:** unmeasured — how to measure: `jq -c . idl.jsonl >/dev/null` in a cron; count parse errors/week.
- **Frontier-fix sketch:** route all IDL writes through one `flock`'d appender in lib (the pattern already exists in lib/mailbox-pending.sh); or a lock-free per-hook shard + merge-on-read.
- **Confidence:** medium-high / stale-risk low.

**FP-4 — Un-versioned wiring makes "dropped hook" indistinguishable from "healthy-dormant"**
- **Evidence:** no `hooks` block in any tracked settings (grep empty); wiring lives only in live `~/.claude/settings.json`; 3 PreToolUse gates (keychain-guard.sh et al.) exist live-only, absent from checkout; boundary hdr 52-60 documents a real past instance where a hook read as "0 IDL / never evaluates" and the C3 critic could not tell inert-vs-dropped.
- **Mechanism class:** config drift with no baseline + fail-silent-on-omission.
- **Current mitigations + status:** config-mirror-assert.sh (SessionStart) checks *some* mirror invariants; IDL "abstained==100%" alarm exists but false-positives on rarely-firing advisories (boundary hdr 58-60). Status: **weak**.
- **Why it resists normal fixes:** the deploy model is per-file symlinks + hand-edited live JSON (per repo memory `deploy-lag-checkout-behind-origin`); a hook removed from the array leaves no artifact — no eval, no IDL, no error — so monitoring keyed on hook *output* can't see an absent hook.
- **Quantified cost:** unmeasured — how to measure: snapshot `jq .hooks ~/.claude/settings.json` into the repo; CI-diff against a committed golden; alarm on any hook present-in-repo-scripts but absent-from-wiring.
- **Frontier-fix sketch:** commit the wiring as a golden fixture + a SessionStart assertion that every symlinked hook script is either wired or explicitly retired; treat "script exists, unwired" as a fail.
- **Confidence:** high / stale-risk low.

**FP-5 — Daemon-stacking in lead-crash-watchdog (already-registered; code-confirmed)**
- **Evidence:** lead-crash-watchdog.sh:95-101 writes pidfile=**lead** PID then unconditionally `setsid`-spawns the daemon with **no pre-spawn liveness check**; wired SessionStart:* (fires on startup|resume|clear) → each re-entry stacks another daemon watching the same PID. Cross-ref: MEMORY.md `session-crash-per-session-bloat` — "daemon-stacking → registered-state-family campaign" (one line, per brief).
- **Mechanism class:** idempotency failure under event re-entry.
- **Current mitigations + status:** daemon self-exits when pidfile gone (line 115) / lead gone (117), bounding lifetime — but N stacked daemons all fire handle_crash on a real crash → duplicate respawn/page. Status: **registered, code-unmitigated** (recent commits abc29f4/1ce427c addressed crash *classification*, not the spawn guard).
- **Why it resists normal fixes:** the natural guard (pidfile) stores the wrong PID (lead, not daemon), so a correct guard needs a *daemon* pidfile + `kill -0` before spawn — a change the crash-classification commits didn't make.
- **Quantified cost:** unmeasured — how to measure: `pgrep -fc lead-crash-watchdog` per session after 2+ resumes.
- **Frontier-fix sketch:** write a daemon-PID lockfile; `kill -0` it before spawn; single-daemon-per-sid invariant.
- **Confidence:** high (code) / stale-risk medium (a state-family campaign is registered and may land a fix).

**Blockers/uncertainties:** (1) parallel-vs-sequential same-event execution is unverifiable read-only — gates FP-2 and the boundary-latch TOCTOU; (2) 3 PreToolUse:Bash gates (incl. blocking keychain-guard.sh @60s) are live-only, un-auditable from the checkout; (3) multi-`decision:block` merge semantics on Stop are harness-defined and could shift by CC version.