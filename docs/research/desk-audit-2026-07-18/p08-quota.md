# P8 — Quota / Account / Model Sustainability (fuel for 24/7)

**Verdict**: The desk has a **build-complete but runtime-inactive** limit-survival stack. Every
recovery *primitive* is written, tested, and gate-GREEN — but the ONE mechanism that would wake a
**limit-killed** session with no human present (`lr-reset-poller`) is **not loaded** and defaults to
**notify-only**. A usage-limit wall that kills a session today = a guaranteed strand until a human
notices. "Net-positive" is **not measured anywhere** — only survival/capacity is.

Goal legend: **(a)** survive usage-limit walls unattended · **(b)** survive account/auth failures
unattended · **(c)** measure net-positive cost-vs-value.
Coverage: read the code of **22** in-scope assets directly + ran 5 gates/selftests live; **4** more
(`lr-audit.py` full body, `lr-transplant.sh`, `docs/KIMI_METERED_INTEGRATION.md`, the 3 `.bats`
suites) verified transitively via GREEN gate runs / caller code, not line-read.

---

## 1. Inventory

Wiring legend: **launchd** = scheduled job · **transitive** = fires as a side-effect of another
call · **prompt-only** = a live agent must choose to invoke · **manual-only** = a human must invoke ·
**dead** = no invoker at all. (Nothing in scope is dead.)

| Asset | Role in desk loop | Wiring | Depends on | Verified by | Goal | Gap |
|---|---|---|---|---|---|---|
| `scripts/limit-recover/lr-reset-poller.sh` | Detect limit-parked sessions across 4 accts, ledger reset times, resume at reset | launchd (600s) **— NOT LOADED**; AUTOFIRE=0 → notify-only | lr-audit.py, claude-accounts --json, lr-fire-resume.sh, osascript/iTerm2 | limit-reset-gate GREEN (build); poller.log = real notify-only cycle 2026-07-12 | a | G-P8-1,3 |
| `com.reso.lr-reset-poller.plist` | launchd unit for the poller | **not in ~/Library/LaunchAgents** | — | inspection | a | G-P8-1 |
| `scripts/limit-recover/lr-fire-resume.sh` | expect-driven `claude --resume`, auto-answers resume/trust/upsell, injects `/limit-recover` | prompt-only / called by poller(off) + lr-handoff | lr-preseed-env.sh, `$HOME/.claude-183` binary, expect | code-read; used by lr-handoff | a | G-P8-3,8 |
| `scripts/limit-recover/lr-preseed-env.sh` | Kill the 2 out-of-PTY resume blockers (iTerm2 clear-scrollback NSAlert; folder-trust) at source | transitive (called by fire-resume + handoff) | defaults(iTerm2), target `.claude.json` + its lock | code-read; lock-guarded, atomic | a | — |
| `scripts/limit-recover/lr-handoff.sh` | Same-session cross-account transplant + salvage + split-pane relaunch | prompt-only (`/limit-recover handoff`) | claude-accounts --route, lr-audit, lr-transplant, lr-preseed, osascript | code-read | a | G-P8-2 |
| `scripts/limit-recover/lr-transplant.sh` | Copy transcript/session dir to target acct under same uuid, sha-verify, lock+tombstone | transitive (handoff) | git, jq, python3 | inferred via caller + command doc | a | (uncert.) |
| `scripts/limit-recover/lr-audit.py` (37K) | Disk-truth audit: per-slot verdict ledger, reset-time parse, salvage | prompt-only (`/limit-recover` Step 0) | transcripts, workflow journals | argparse (non-interactive), exit 0/1/2 | a | — |
| `commands/limit-recover.md` | Agent recovery skill: audit→re-run→re-audit fixpoint OR handoff | prompt-only | all lr-* scripts | code-read | a | G-P8-2 |
| `tests/lr-reset-poller.bats` | RED-proof LR-a..i | run by gate | bats | limit-reset-gate GREEN | a | — |
| `scripts/limit-reset-safety-gate.sh` | Un-hold bar for the poller build | manual/CI | bats suite | **ran: exit 0 (1 met)** | a | — |
| `bin/cc-route` | slot→{model,acct,lead-effort} from live reads; cliff=STOP(exit4) | **prompt-only, NO standing invoker** | claude-accounts --route, model-config.yaml | **selftest 15/15; live `lead`→next2 Opus@max** | a | G-P8-6 |
| `scripts/route-safety-gate.sh` | RT-a..f bar | manual/CI | cc-route selftest, bats | **ran: exit 0 (2 met)** | a | — |
| `bin/cc-respawn` | Effect-verified respawn protocol (checkpoint→verify-stopped→verify-spawned) | **prompt-only; phases 2&4 are the LEAD/harness** | git plumbing, ps | **selftest 16/16** | a | G-P8-6 |
| `scripts/respawn-safety-gate.sh` | RS-a..f bar | manual/CI | cc-respawn selftest | **ran: exit 0 (2 met)** | a | — |
| `bin/claude-accounts` (37K) | SSOT quota/auth: --json/--route/--rank + headless heal | **transitive** (any caller sweeps; heal on stale+k==0) | keychain, usage endpoint, official `claude auth login` | memory; code-read heal():235-267, collect():294-340 | a,b | G-P8-4,9 |
| `accounts.json` | Acct SSOT + router constants (KMAX=8) + frontier coupling | config | — | parsed | a,b | — |
| `skills/account-relogin/SKILL.md` | Re-auth: Phase1 headless RT → Phase2 Dia-OAuth → Phase2b email-code | prompt-only | claude-accounts, dia-agent, MS Graph | code-read | b | G-P8-4 |
| `bin/claude-kimi` | Isolated **metered** Kimi K3 launcher (outage/limit hedge) | **manual-only; NOT activated (no key)** | Moonshot key, `$HOME/.claude-183` binary | **selftest ref; status = not wired** | a | G-P8-5 |
| `~/.claude/model-config.yaml` | Model/effort SSOT; Fable 5 **permanent** (no window) | read by cc-route/claude-accounts | — | read live | a | — |
| `bin/cc-board` | All-sessions glance: ctx% × quota% × liveness × next-acct | prompt-only (`watch cc-board`) | statusline telemetry, claude-accounts --json | telemetry-e2e GREEN | (a) | G-P8-7 |
| `scripts/telemetry-e2e.sh` | Regression guard for statusline/cc-context/cc-board | manual/CI | bats-less | code-read | (a) | G-P8-7 |
| `scripts/never-stuck-gate.sh` | Composition audit (7 gates + state/failure-class/runtime legs) | manual/CI | all sibling gates | code-read; LEG4 reports poller NOT loaded as "never a failure" | a | G-P8-1 |
| `bin/cc-reaper` | Idle-session reaper; **excludes rate-limited** from reap | launchd (LOADED, `com.chrisren.cc-reaper`) | cc-classify | code-read :24 | (a) | — |
| `scripts/lead-supervisor.sh` | **Page-only** stall/limit backstop (alerts human) | launchd (**LOADED**, `com.claude.lead-supervisor`) | cc-board | launchctl | a,b | — |

---

## 2. Mechanism — the limit-hit → recover → continue chain ([HUMAN] = human touchpoint)

### Scenario A — session is LIVE when the wall hits (an agent can act)
1. A spawn/route attempt meets the cliff: `cc-route <slot>` → `claude-accounts --route general`
   returns policy-none (exit 2) → **cc-route exits 4** with "run /limit-recover", NO plan
   (`bin/cc-route:147-151`). *Prompt-only: presumes a live lead was routing through cc-route —
   which nothing forces it to do (G-P8-6).*
2. A live agent runs `/limit-recover` (`commands/limit-recover.md`). Step 0 = `lr-audit.py`
   disk-truth audit (agent-runnable, non-interactive).
3. **Wait-vs-switch decision** (`limit-recover.md:90-95`): if session/weekly ≥100%, the command
   says **STOP and present** reset time + escape hatch — **[HUMAN decision]** — *"only if the user
   already told you to continue autonomously (e.g. a /goal), fire the handoff yourself."* So without
   a standing /goal, even a live session halts for a human (G-P8-2).
4. Autonomous branch (standing /goal present): `lr-handoff.sh --target auto` →
   `claude-accounts --route` picks a fresh acct → audit+salvage+transplant (`lr-transplant.sh`) →
   `lr-preseed-env.sh` → `lr-fire-resume.sh` fires a **split pane** via osascript/iTerm2
   (`lr-handoff.sh:150-177`). Agent-runnable; **requires a GUI iTerm2**.
5. Target session runs `/limit-recover ingest <bundle>`, re-runs gap slots to fixpoint.

### Scenario B — the limit KILLED the session (no live agent) — **THE 24/7 STRAND**
1. Session is dead/idle. **Nothing live exists to run `/limit-recover`.** cc-reaper leaves it alone
   (rate-limited excluded from reap, `cc-reaper:24`) — so it sits idle indefinitely.
2. The ONLY designed re-animator is `lr-reset-poller` (launchd 600s): detects the parked transcript
   (tail grep "You've hit your … limit" + lr-audit confirm), ledgers `reset_at_utc`, and at
   reset+headroom resumes via `lr-fire-resume`. **BUT today**: **[not loaded]** (launchctl has no
   `com.reso.lr-reset-poller`) **AND** `LR_POLLER_AUTOFIRE=0` default → even when loaded it only
   **macOS-notifies once** and spawns nothing (`lr-reset-poller.sh:27,129-134`; plist:20-23). Its
   one real run (2026-07-12) went `PARKED → READY notify-only`; `resumed/` is **empty** — the
   autofire resume path has **never fired in production**.
3. Backstop: `lead-supervisor` (LOADED) **pages the human** on stall — **[HUMAN alerted]**, at page
   latency, not autonomous repair.

**Chain conclusion**: Scenario A is autonomous *only* under a standing /goal and *only* with a GUI;
Scenario B has **no autonomous path at all today**. The missing links, precisely: (i) the poller
plist is not installed; (ii) AUTOFIRE is not flipped; (iii) the autofire resume is GUI/iTerm2-bound
and unexercised. All three are the operator's hand-steps in `docs/activation/wiring-all.sh` ①.

### Account/auth-failure chain (goal b)
- **Stale token** (expired access token, refresh token valid): `collect()` auto-heals opportunistically
  — `bin/claude-accounts:313-314` calls `heal()` (`:235-267`) = headless `claude auth login` with
  `CLAUDE_CODE_OAUTH_REFRESH_TOKEN`, gated **k==0** (no live session) + flock, 90s timeout. Fully
  agent-runnable, fires transitively from any `--json/--route/--rank` sweep. **Memory: UNEXERCISED**
  (all 4 accts had fresh tokens on build day).
- **True logout / revoked RT**: `account-relogin` Phase 2 = Dia CDP browser OAuth → **[HUMAN gate:
  dia://inspect remote-debugging consent]**, and if webmail is also out, **[HUMAN email-code]** (MS
  Graph covers only 1 of 4 mailboxes). **Not headless.** One revoked RT = that account down until a
  human acts.

### Overflow-to-Kimi (goal a hedge)
- `claude-kimi` is a **manual launcher**, fully isolated (own config dir, bearer token, cannot touch
  Max creds). **Not activated** (`status` = "not wired", no key file/env). **No automated routing to
  it exists anywhere** — not in cc-route, not in accounts.json `router`. Engaging the hedge is
  entirely **[HUMAN: set-key + launch]** (`claude-kimi:259`).

### Net-positive (goal c)
- **Not measured.** `cc-board`/`telemetry-e2e`/`cc-context` quantify only **ctx fill %**, **acct
  5h/weekly/Fable %**, and **liveness** (OK/DUE/LIMIT/DEAD/STALL?). The only "value"-shaped string in
  the whole `bin/` tree is `cc-classify:265`, which uses "commits landed" purely as a **reap
  heuristic** (is this idle session finished?), not a value score. Spend is computable
  (`token-usage-from-transcripts` memory) but is **never joined to value produced**. Quota-survival
  is the sole metric; a net-*negative* loop (burning quota on churn) is undetectable by the desk.

---

## 3. Gaps & fragilities

| ID | file:line | FM | Sev | Failure scenario | Fix sketch |
|---|---|---|---|---|---|
| G-P8-1 | launchctl (absent) · `com.reso.lr-reset-poller.plist:16-23` · `lr-reset-poller.sh:27` | 24x7 | **P0** | A limit-**killed** session strands forever: poller not loaded, so nothing detects the reset; and even loaded it defaults notify-only. Guaranteed unattended strand on the FIRST weekly/5h kill. | Install plist to ~/Library/LaunchAgents + `launchctl load -w`; flip `LR_POLLER_AUTOFIRE=1` after one eyeballed cycle (wiring-all.sh ①). |
| G-P8-2 | `commands/limit-recover.md:90-95` | 24x7 | **P0** | A LIVE session at the wall defaults to **STOP-ASK** (wait vs switch = user's call) unless a standing /goal pre-authorized autonomy → halts for a human even though the switch is fully scripted. | A durable standing-autonomy flag (or always-on /goal) that authorizes `lr-handoff auto` at the cliff without asking. |
| G-P8-3 | `lr-reset-poller.sh:126` (osascript iTerm2) · `resumed/` empty | 24x7 | P1 | Autofire is **unexercised** end-to-end and **GUI-bound**: `osascript tell iTerm2 create window` fails headless/SSH/locked-screen; the one real cycle only notified. | Add a headless spawn path (detached tmux / `claude -p`) as the autofire default; prove one real auto-resume (resumed/ row). |
| G-P8-4 | `claude-accounts:240` (k==0 gate) · `account-relogin` Phase 2 | FM | P1 | Heal is **Phase-1-only + unexercised**; a real logout/revoked RT needs a **human** (Dia consent + email code, Graph covers 1/4 mailboxes) → an account down until noticed. | Device-code sign-in for the other 3 mailboxes (headless email-code); live-exercise the heal path; alert on `logged-out`. |
| G-P8-5 | `claude-kimi:259` (no key) | 24x7 | P1 | The outage/limit **hedge cannot engage without a human** (no key, no auto-route). A full Anthropic cap or outage = zero overflow capacity. | `claude-kimi set-key`; add a cliff→kimi fallback rule (offer or auto) in cc-route/limit-recover. |
| G-P8-6 | `bin/cc-route` · `bin/cc-respawn` (no invoker; only planning docs ref them) | 24x7 | P1 | The cliff-STOP and respawn-GO machinery is **gate-green but never invoked by machinery** — it relies on the lead *remembering* to run it. A drifted/tired/naive lead fires blind past the cliff the tool exists to stop. | Wire cc-route as a standing pre-spawn gate (hook/command wrapper); reference cc-respawn in the respawn runbook the lead auto-loads. |
| G-P8-7 | `cc-board:56-68` · `telemetry-e2e.sh` (no value axis) | none | P1 | **Net-positive is unmeasurable** (goal c): no join of value (commits landed / tasks closed) to spend (tokens/quota). The desk cannot self-detect a net-negative churn loop. | Add a value×spend row to cc-board: {landed commits, tasks closed}/window ÷ tokens, per account. |
| G-P8-8 | `lr-fire-resume.sh:65` · `claude-kimi:105` (`$HOME/.claude-183`) | FM | P2 | Hardcoded pinned-binary path → a CC track bump (2.1.183→next) **silently breaks resume + kimi**. | Resolve the claude binary from one SSOT (already partially done in claude-kimi via `claude-latest` fallback); apply same to lr-fire-resume. |
| G-P8-9 | `claude-accounts:341` ("rate-limited" label) | FM | P2 | A usage-endpoint **poll-throttle 429** renders identically to a real cap → false cliff / false park / desk misdiagnosis (cost one on 2026-07-16, per memory). Fix staged, not landed. | Land the `poll_throttled ↻` relabel + cache-fallback + distinct `--json` field. |
| G-P8-10 | `limit-reset-safety-gate.sh:65-72` (LR-blind) | 24x7 | P2 | The **Fable-scoped** limit-message shape was never captured; a novel-shape Fable limit classifies as `other_api_error` → **never parked** → poller blind to it. Covered only by the supervisor page. | Fixture-ize the first real Fable-limit transcript into the bats suite. |

---

## 4. Task candidates

| ID | Action | Acceptance criterion | Depends-on |
|---|---|---|---|
| T-P8-1 | Install poller plist + flip AUTOFIRE=1 (operator hand-step, wiring-all.sh ①) | `launchctl list` shows `com.reso.lr-reset-poller`; a parked test session auto-resumes (a `resumed/` row + a running pane appear) | G-P8-1,3 |
| T-P8-2 | Give the poller a **headless** autofire path (tmux/`claude -p`) replacing osascript-iTerm2-window | An autofire cycle resumes a parked session with iTerm2 quit / over SSH | G-P8-3 |
| T-P8-3 | Standing autonomous wait-vs-switch policy for LIVE cliffs | A live session at cliff fires `lr-handoff auto` without STOP-ASK under the policy; still STOP-ASK on genuine decision forks | G-P8-2 |
| T-P8-4 | Wire cc-route as the enforced pre-spawn gate (not lead-discretionary) | A spawn attempt at a quota cliff is **blocked by machinery** (exit 4 honored), logged to route.jsonl | G-P8-6 |
| T-P8-5 | Add value×spend axis to cc-board | cc-board shows a per-account net-positive column {commits landed, tasks closed}÷tokens for the window | G-P8-7 |
| T-P8-6 | Activate + auto-route the Kimi hedge | `claude-kimi status` = WIRED; a quota-cliff offers/auto-selects Kimi overflow | G-P8-5 |
| T-P8-7 | Land the "rate-limited"→"poll throttled" relabel + device-code sign-in for the 3 uncovered mailboxes | 429 poll-throttle no longer renders as a cap; all 4 mailboxes fetch codes headlessly | G-P8-9,4 |
| T-P8-8 | Single-SSOT claude binary resolution in lr-fire-resume | A CC track bump does not break resume (resolved via `claude-latest`/config, not `.claude-183`) | G-P8-8 |
| T-P8-9 | Live-exercise the account heal path (force one stale token at k==0) + capture a real Fable-limit transcript | heal log shows one real OK; LR-blind fixture added | G-P8-4,10 |

---

## 5. Cross-beat dependencies
- **Reaper/lifecycle beat**: cc-reaper correctly **excludes** rate-limited sessions from reap
  (`cc-reaper:24`) — no strand-worsening interaction; but the poller resumes into a *new* pane, so
  the parked pane's fate is irrelevant. Confirm the reaper/poller don't both act on the same sid.
- **Idle-standoff beat (FM2)**: a limit-parked session *looks* idle. That beat's idle detectors must
  **not** treat a limit-park as a nudgeable idle — it needs reset-wait, not a nudge. This beat owns
  the distinction (transcript "You've hit your … limit" + reset-bearing lr-audit event).
- **Supervisor/paging beat**: `lead-supervisor` (LOADED) is the load-bearing **page-only** backstop
  that this beat's blind spots (Fable-limit shape, autofire-off) fall through to. Its liveness is a
  shared dependency — if it's unloaded, the fallbacks are silent.
- **Routing/model beat**: cc-route reads `model-config.yaml` SSOT (Fable **permanent** as of
  2026-07-20) via the same key-anchored parse discipline; shares the frontier-window SSOT rule.
- **Handoff/session-close beat**: `/limit-recover handoff` reuses the split-pane handoff-fire
  mechanics (memory `feedback-handoff-splitright-default`).

---

## 6. Adversarial self-pass (what a hostile reviewer would catch — then covered)
- **"You called cc-route/cc-respawn dead."** Corrected: they are deployed, gate-GREEN, and
  live-working (I ran `cc-route lead` → real plan on next2). The accurate finding is **no standing
  invoker** — a grep of commands/skills/agents/hooks/launchd found them only in a **planning doc**
  and the deploy script. Risk = non-invocation, not deadness (G-P8-6).
- **"Is the poller really the only backstop?"** No — `lead-supervisor` IS loaded and pages the human.
  So the system is not *blind*, but a page is a **human summons**, so the *no-human 24/7* claim still
  fails for Scenario B. Reclassified the supervisor as a live page-only backstop, not autonomous.
- **"Heal is never wired."** Corrected: heal fires **transitively** from any `collect()` sweep
  (`:313`), so it *is* opportunistically exercised on every cc-board/cc-route/handoff call; only the
  specific stale-token+k==0 branch is memory-flagged unexercised.
- **"Does the reaper kill parked panes?"** Checked: `cc-reaper:24` excludes rate-limited from reap —
  no negative interaction.
- **"Any value metric you missed?"** Grepped bin/scripts/hooks/statusline for
  net-positive|value|landed|tasks-closed|roi|productivity — only `cc-classify:265` (a reap heuristic)
  and a `claude-kimi` comment. Net-positive genuinely unmeasured.

## 7. Uncertainties
- `lr-audit.py` full body (37K) not line-read — role + non-interactivity confirmed via argparse +
  command doc; verdict-classification *correctness* assumed from GREEN usage, not audited.
- `lr-transplant.sh` behavior inferred from its `lr-handoff` caller + command doc (sha-verify +
  lock + tombstone), not line-read.
- Kimi K3 model id / endpoint correctness taken from code + memory (no network verification).
- Whether a **standing /goal is currently active** (which would flip Scenario A to autonomous) is a
  runtime state I cannot observe — the capability exists; engagement now is unknown.
- Poller AUTOFIRE headless viability: `osascript tell iTerm2` needs an Aqua GUI session; behavior
  under locked-screen/SSH untested (asserted from the API's known constraints, not run).
