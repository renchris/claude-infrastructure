# P1 — Handoff & Spawn Machinery (orchestrator-desk beat)

Coverage: read the code of all 12 in-scope files + the live wiring (settings.json Stop/UserPromptSubmit/
PostToolUse/SessionStart/End, settings.example.json, install.sh), the telemetry producer (statusline.sh),
the out-of-session backstop (lead-supervisor.sh), the in-session monitoring carrier (waiting-recycle.sh),
cc-reaper header, both memory files, and both live repos' `.git/gate-green` + git hooks. Empirical =
read/ran; theoretical = inferred, tagged inline.

## HEADLINE (read first)
1. **boundary-handoff.sh is STRUCTURALLY DEAD in production** — its `gate-green == HEAD` precondition
   (`hooks/boundary-handoff.sh:79`) has **no production writer anywhere**. Only a test fixture
   (`scripts/boundary-hook-e2e.sh:32`) and docs write the marker; `SESSION_AUTONOMY_RESEARCH.md:457`
   explicitly lists it as unbuilt ("B2 no gate-green marker exists — add to commit/`/ship`"). Live check:
   `.git/gate-green` ABSENT in BOTH claude-infrastructure and reso-management-app. So the Stop hook always
   `abstain "gate-not-green-at-head"` → the general-session context-boundary handoff advisory **never
   fires**. All the B-1/B-2/B-3 hardening is downstream of a gate that never opens. → **FM1**.
2. **The cold-worktree auto-submit race is still OPEN** — the non-recycle spawn path (`it2_land`) types
   the launch command + focuses but never verifies the fired session ENGAGED the brief. Only `--recycle`
   post-confirms a process on tty. → **FM2** (looks fired, never engages).
3. The remaining in-session carrier (`waiting-recycle.sh`) is OPT-IN + capped + advisory-only; the
   out-of-session backstop (`lead-supervisor.sh`) is PAGES-ONLY with a default-empty `CC_PAGE_TO`. In a
   no-human 24/7 loop, a non-monitoring builder past-threshold is at best *detected*, never *actioned*.

---

## (1) Inventory

| Asset | Role in desk loop | Wiring | Depends on | Verified by | Serves | Gap |
|---|---|---|---|---|---|---|
| `commands/handoff.md` | The /handoff spec: bridge modes A/B/C, paste block, autonomous fire, disposition contract, self-close, two-way | prompt-only (slash command; symlinked `~/.claude/commands/handoff.md`→repo) | handoff-fire.sh, handoff-disposition.sh, cc-notify/await-ping/sessions | none (doc) | b,c | — |
| `scripts/handoff-fire.sh` | Autonomous launcher: account rank→launcher→model/effort→worktree→surface→type+auto-submit; also `self-close` + `--recycle` + prompt trailers | manual/prompt-invoked; also called by `hooks/waiting-recycle.sh` (advisory text) + e2e scripts | claude-accounts, it2 (real+shim), osascript/iTerm2, jq, worktree-pool.sh, statusline pre-trust | tests/fire-autonomy.bats, notify-back.bats, handoff-splitright.bats, handoff-selfclose-e2e.sh (GREEN by design) | a,b,c | G-P1-2,3,10 |
| `scripts/handoff-disposition.sh` | Un-fakeable mechanical reads (dirty/mailbox/await-ping/peers-alive/open-tasks) → exit 0 close-eligible / 1 stay-open | prompt-only (run by the model each post-fire turn) | jq, cc-sessions, ~/.claude/mailbox, task _summary.json | tests/handoff-disposition.bats (12, GREEN) | c | G-P1-7 |
| `hooks/boundary-handoff.sh` | Stop-hook: at committed+green+past-threshold, advise /handoff before auto-compact | **Stop hook** in live settings.json (ABSOLUTE shared-checkout path) — **absent from settings.example.json/install.sh** | statusline telemetry (/tmp/cc-telemetry/$sid.json), **gate-green marker (NO PRODUCER)**, session-continue sentinel | scripts/boundary-hook-e2e.sh (GREEN — but fixture writes gate-green the real flow never does) | a,c | **G-P1-1**,3,5,9 |
| `hooks/waiting-recycle.sh` | In-session carrier for monitoring desks: PostToolUse:Bash advises /handoff --recycle at moderate fill/rot | **PostToolUse hook** in live settings.json | statusline telemetry, arm sentinel (opt-in), transcript tail | tests/waiting-recycle.bats (referenced) | a,c | G-P1-8 |
| `scripts/handoff-selfclose-e2e.sh` | Live-fire proof of self-close succession chain on real panes w/ fake claude | manual (post-change gate) | it2 shim, osascript, cc-notify, mailbox | self (E2E, 9/9 claimed) | c | — |
| `scripts/boundary-hook-e2e.sh` | Regression gate for boundary-handoff (fire + anti-trigger + B-2/B-3) | manual/CI gate | jq, git | self (9 asserts) | a,c | masks G-P1-1 (fixture writes gate-green) |
| `docs/plans/HANDOFF_DISPOSITION_PLAN.md` | Frozen contract spec + status log for the disposition work | doc | — | — | c | — |
| `tests/fire-autonomy.bats` | pre_trust + config_dir_for_launcher unit tests | CI gate | bats, jq | self (10) | b | — |
| `tests/handoff-splitright.bats` | no-frontmost-drift invariant (d662845) | CI gate | bats | self (9) | b | — |
| `tests/handoff-disposition.bats` | mechanical-read unit tests | CI gate | bats, jq | self (12) | c | — |
| `tests/notify-back.bats` | back-channel + self-retire trailer tests | CI gate | bats | self (10) | c | — |
| `scripts/limit-recover/lr-handoff.sh` | Limit-interrupt cross-account transplant + salvage + fire (distinct from /handoff) | prompt/skill (limit-recover) | lr-audit.py, lr-transplant.sh, lr-fire-resume.sh, claude-accounts --route | (none inline) | b | note only |
| `~/.claude/hooks/handoff-intent-nudge.sh` | Verbal/relayed-handoff PARITY carrier (UserPromptSubmit injects /handoff reminder) | **UserPromptSubmit hook** live | — | none | c | **G-P1-4** (repo-absent/untracked) |
| `scripts/lead-supervisor.sh` | Out-of-session B-1 backstop: detect past-threshold∧not-Stopping → PAGE | **launchd** com.claude.lead-supervisor.plist | statusline telemetry, cc-notify, CC_PAGE_TO | scripts/supervisor-e2e.sh | a,c | G-P1-6 |
| `~/.claude/statusline.sh` | THE telemetry writer (used_pct → /tmp/cc-telemetry/$sid.json) on TUI redraw | statusLine command | jq, CC context | none observed | (dep) | shared SPOF |
| `bin/cc-reaper` | launchd backstop that reaps handed-off-lead / finished panes (peer teardown) | **launchd** com.chrisren.cc-reaper.plist | cc-classify, cc-teardown | cc-reaper selftest | b,c | cross-beat |

---

## (2) Mechanism — end-to-end (file:line)

**A. What /handoff produces (bridge fidelity).** `commands/handoff.md:10-11,23-26` — the bridge is a
STATELESS POINTER to the durable plan, `/tmp` only, never committed. `:132-146` — ≤30 lines: self-locate
header + Mode-A "read `<plan>` § resume, Status, Next" or Mode-B/C bootstrap + 4-8 facts + a pointer to the
plan's resume section, and explicitly **"Do NOT duplicate the plan's content."** The frozen DoD / "what
100/100 means" is NOT carried in the bridge — only "3-6 HARD constraints" are duplicated verbatim
(`:66-69`). Mission fidelity across the bridge therefore rests entirely on (a) the plan doc holding a
clear DoD and (b) the successor reading it — **no mechanism enforces either** (see G-P1-1-adjacent FM1
seam; KEY-Q4).

**B. Fire placement/launch.** `handoff-fire.sh` composes in order: account (`ranked_accounts:547-573` →
`claude-accounts --rank`, halts on rc2 "no routable", degrades to trailing-5h activity proxy on rc3) →
launcher (`launcher_for:575-579`) → model/effort appended last-wins (`:683-694`) → location
(`:762-799`: existing `--cwd`; `--worktree` pool-claim fast-path `:773-776` else cold `git worktree add`
+ PM-detected in-pane install `:788-789`, commit 1608650 — `;` not `&&` so non-Node projects launch) →
pre-trust the launch dir (`pre_trust:596-614`, sets only hasTrustDialogAccepted so the fired peer skips
the workspace-trust dialog) → surface (`spawn:931-964`). Split-right default resolves the FIRING pane via
`$ITERM_SESSION_ID` and splits through the **real** it2 python API (`it2_split:849-856`, parses "Created
new pane"), retry-once-then-**fail-loud**, never drifting to app-frontmost (d662845; `:811-826`,
tests/handoff-splitright.bats). `it2_land:862-872` types `$CMD` raw via `session run` (+CR) and focuses.

**C. Recycle (Mode-A single track).** `recycle_fire:969-1012` — arms a **setsid-detached** watcher
(`detach:188-196`; nohup dies to the /exit group-SIGKILL, 2× 2026-07-13), gates /exit on the watcher's
`await_armed` heartbeat (`:201-208`), types `/exit` foreground (INTERRUPTS the turn), watcher ps-polls the
tty until claude exits then it2-types the relaunch and **post-confirms a claude process on tty**
(`__recycle:262-306`, incl. guarded retype + pane-visible failure comment).

**D. Self-close / succession (commits f137b1b/d8e8aa4 lineage).** `self-close:309-446` — mandatory
succession statement: bare exits 2 (`:333-342`); `--successor` liveness-gated BEFORE any side effect
(pane resolvable + claude on tty, else exit 3 `:349-364`); dirty-tree refuses exit 1 unless
`--dirty-owner successor` (verified-alive owner) or `--allow-dirty` (`:370-384`); announces succession
INTO the successor via cc-notify (`:403-413`), arms watcher, types /exit, watcher closes the pane
(it2 shim) and FOCUSES the successor (`__selfclose:217-253`). **Who closes a fired PEER's pane:** the peer
closes ITSELF via the SELF-RETIRE trailer (`:734-749`, SELF_RETIRE=1 default, `self-close --terminal`),
with cc-reaper as the launchd backstop; the firing desk closes a peer only via remote-relief cc-notify.

**E. Disposition contract.** `handoff.md:438-500` + `handoff-disposition.sh` — every post-fire turn ends
with one `🔚 CLOSE` or `⏳ OPEN — R-CODE…`; the helper reads mechanical reasons (dirty `:70-77`,
mailbox-pending vs .seen cursor `:79-104`, uuid-scoped await-ping `:106-114`, fired_peers_alive substring
∩ cc-sessions `:116-138`, open_tasks `:140-153`) → exit 1 if any exist, else exit 0 close-eligible pending
R-USER/R-DECIDE judgment.

**F. Boundary trigger.** `boundary-handoff.sh` fires on **Stop** only when ALL hold: session-id present
`:49`, continue-sentinel absent `:52-53`, telemetry fresh <180s `:59-63`, used_pct≥73 `:64-66`, cwd a repo
`:69-72`, **clean tree** `:77`, **gate-green==HEAD** `:78-79` (← the dead gate), no live teammates
`:80-84`, optional log-head==HEAD `:90-95`, latch not held unless +10% climb `:97-107`. Delivered as a
one-shot-latched `{decision:block}` (`:113`). Producer of the telemetry it reads = `~/.claude/statusline.sh:87-91`
(writes used_pct from `.context_window.used_percentage` on redraw).

---

## (3) Gaps & fragilities

`ID | file:line | FM | Sev | scenario | fix`

- **G-P1-1 | hooks/boundary-handoff.sh:78-79 (+ absent producer) | FM1 | P0/P1 | gate-green marker has NO
  production writer (only boundary-hook-e2e.sh:32 fixture + docs; SESSION_AUTONOMY_RESEARCH.md:457 flags it
  unbuilt; ABSENT in both live repos) → the Stop-hook boundary advisory ALWAYS abstains "gate-not-green-at-head"
  and NEVER fires; a long non-monitoring builder fills to the 90% auto-compact wall with no handoff prompt →
  context/mission lossy-compacted. | write `git rev-parse HEAD > "$(git rev-parse --git-common-dir)/gate-green"`
  in the repo's commit-time green gate (/ship + pre-push green path); one line closes the whole hook.**
  (Ranked P0 for the autonomy goal — a fully-built, wired, tested safety mechanism is 100% inert — but it does
  not STRAND the loop within a day since CC native auto-compact still fires, hence the P0/P1 straddle.)
- **G-P1-2 | handoff-fire.sh:862-872 (it2_land) + spawn:931-964 | FM2 | P1 | the non-recycle spawn path types
  the launch cmd + focuses and prints "→ fired" with NO engagement check; only --recycle post-confirms a
  process on tty. A cold `--worktree` fire that races CC boot sits at an empty prompt: 0 commits, no ping,
  looks successful (memory cold-worktree-fire-autosubmit-race, still flagged open). | add a post-spawn
  engagement verify (poll the fired session's newest JSONL for a real assistant turn, or grep brief text)
  before the success line; or prefer warm --cwd + a boot-wait.**
- **G-P1-3 | ~/.claude/settings.json Stop entry | 24x7 | P1 | boundary-handoff.sh is wired by ABSOLUTE
  shared-checkout path (…/claude-infrastructure/hooks/boundary-handoff.sh); the ~/.claude symlink resolves
  there too. Project CLAUDE.md warns this checkout "frequently sits on another session's feature branch" →
  EVERY session's Stop hook silently runs whatever branch is checked out, not main. Currently on main (latent).
  | pin the hook to a copy or a main-locked worktree decoupled from the live feature-branch checkout.**
- **G-P1-4 | ~/.claude/hooks/handoff-intent-nudge.sh (repo-absent) | 24x7 | P1 | the verbal/relayed-handoff
  PARITY carrier handoff.md:13-21 leans on is LIVE (real 2352-byte file, wired UserPromptSubmit) but NOT
  tracked in the repo (not a symlink into it; grep-absent) → untested, ungated; a repo reinstall would not
  recreate it; if lost, spoken "hand off / recycle" silently regresses to improvised-from-memory (the exact
  2026-07-13 incident class). | move into repo hooks/, register in settings.example.json, add a smoke test.**
- **G-P1-5 | settings-templates/settings.example.json:128-131 + install.sh | 24x7 | P2 | the template Stop
  block has ONLY notify.sh; the entire live handoff-autonomy layer (session-continue, anti-deference-nudge,
  boundary-handoff, waiting-recycle, handoff-intent-nudge, lead-crash-watchdog, live-session-registry) is
  hand-wired into live settings.json and MISSING from template + install.sh → a fresh machine provisions none
  of the handoff machinery. | sync the template + install.sh to the live hook roster.**
- **G-P1-6 | scripts/lead-supervisor.sh:44,149 | FM1 | P1 | the only out-of-session backstop for the case the
  dead boundary-handoff can't see (past-threshold∧not-Stopping) PAGES ONLY (RULING #1) and its cc-notify page
  needs CC_PAGE_TO (defaults empty :44) → in a no-human loop the page lands in ~/.claude/autonomy/pages/ with
  no consumer and no live pane is driven; the "delegated live session recovers" half is unbuilt. | set
  CC_PAGE_TO to the orchestrator pane AND build a page-consumer that actions/relays it.**
- **G-P1-7 | handoff-disposition.sh:116-138 | FM2 | P1 | fired_peers_alive depends on cc-sessions --names;
  an empty/stale registry (observed empty in the plan's own E2E, status log :138) returns [] → the helper
  reports close-eligible while peers are alive → a desk self-closes believing its wave settled (FM2). Substring
  slug match (:125) can also FALSE-match an unrelated session (false OPEN). | fail-CLOSED to OPEN when
  cc-sessions errors (distinguish "[] because registry empty" from "[] because none match"); word-boundary match.**
- **G-P1-8 | hooks/waiting-recycle.sh:66,148-150 | FM1 | P2 | the in-session monitoring carrier caps at MAX=3
  advisories/session then abstains "capped" forever → a wedged desk that ignores 3 advisories is never nagged
  again and silently rots past the boundary; compounded by advisory-only delivery (model may ignore) + regex
  rot-tell brittleness (:182). | ESCALATE at the cap (page supervisor / stronger surface) instead of silencing.**
- **G-P1-9 | hooks/boundary-handoff.sh:111 (IDL) vs consumer | 24x7 | P2 | B-3 promises "alarm on
  abstained==100% over N≥10" but no live scheduled consumer alarms on the boundary-handoff all-abstain
  signature → the dead hook (G-P1-1) logs "abstained: gate-not-green-at-head" every invocation and stays
  invisible; the observability that would catch a structurally-dead hook is itself unwired. | add a scheduled
  idl.jsonl abstain-rate lint.**
- **G-P1-10 | handoff-fire.sh:707-708,734-749 | FM1 | P2 | SELF_RETIRE=1 default appends `self-close
  --terminal` to every non-recycle peer; a peer that MISjudges "done" self-closes terminal (no successor,
  thread ends), and the trailer only ever offers --terminal — a peer with legitimate follow-on cannot declare
  succession. | have the trailer instruct a disposition-helper run before self-close and permit --successor.**

---

## (4) Task candidates

`ID | action | acceptance | depends-on`

- **T-P1-1 | implement the gate-green producer in the commit-time green gate (/ship + repo pre-push/post green
  path): `git rev-parse HEAD > "$(git rev-parse --git-common-dir)/gate-green"` only when the gate is green |
  fill a live session past 73% on a green HEAD → boundary-handoff emits decision:block (observed in IDL as
  fired, not abstained) | none** (highest value — resurrects a dead safety mechanism with ~1 line + a gate hook)
- **T-P1-2 | add post-spawn engagement verification to handoff-fire.sh non-recycle path | a cold --worktree
  fire that fails to engage returns non-zero/warns (not "→ fired"); transcript-content poll green | none**
- **T-P1-3 | track handoff-intent-nudge.sh in repo hooks/ + register in settings.example.json + smoke test |
  file in repo, wired in template, test green | none**
- **T-P1-4 | sync settings.example.json + install.sh to the live Stop/UserPromptSubmit/PostToolUse/Session
  hook roster | fresh install provisions the full handoff-autonomy layer | none**
- **T-P1-5 | set CC_PAGE_TO to the desk pane AND build a supervisor-page consumer/relay | a past-threshold
  non-Stopping builder is actioned (or its page delivered) with no human | desk-pane identity**
- **T-P1-6 | disposition helper: fail-closed-to-OPEN on cc-sessions error + word-boundary slug match | empty
  registry → OPEN; slug false-match test green | none**
- **T-P1-7 | decouple the wired Stop-hook path from the live feature-branch checkout | Stop hook runs a stable
  version regardless of shared-checkout branch | none**
- **T-P1-8 | waiting-recycle escalate-at-cap | after MAX a wedged desk escalates (page) not silences | none**
- **T-P1-9 | scheduled idl.jsonl abstain-rate alarm (per-hook 100%-abstain over N≥10) | dead-hook signature
  pages | T-P1-1 (else it correctly alarms on today's deadness)**

---

## (5) Cross-beat dependencies

- **statusline.sh telemetry writer** — SHARED SPOF for boundary-handoff + waiting-recycle + lead-supervisor.
  If telemetry goes stale (session backgrounded / TUI not redrawing), ALL THREE context-boundary carriers
  abstain simultaneously. Owned by a statusline/telemetry beat if one exists.
- **cc-classify / cc-reaper / cc-teardown** — peer-pane teardown backstop; disposition helper's
  fired_peers_alive + self-retire depend on their liveness/idle correctness (FM2 surface). Likely a separate
  reaping/idle-classification beat.
- **claude-accounts --rank/--route** — account selection for both handoff-fire and lr-handoff; quota beat.
- **worktree-pool.sh** — warm-slot fast path for `--worktree`; worktree beat.
- **session-continue.sh (Session Close auto-continue)** — Stop-hook ordering: boundary-handoff abstains when
  the continue sentinel is armed (`:52-53`); a session-close beat owns the interaction.
- **/ship + land-lock** — self-retire's trivial tail may push/land; landing beat. **T-P1-1's producer most
  naturally lives in /ship's green gate** — coordinate.
- **cc-notify / cc-await-ping / cc-sessions / mailbox registry** — two-way comms substrate under R-PING +
  succession announce; a comms beat owns registry freshness (feeds G-P1-7).

---

## (6) Adversarial self-pass

- *"You assumed the boundary hook works because it's wired + tested."* — Checked and it does NOT: the E2E is
  GREEN precisely because its fixture writes gate-green the real flow never writes (boundary-hook-e2e.sh:32).
  Green tests MASK the dead dependency. Verified by three independent reads: no producer in repo/~/.claude,
  reso git hooks are git-lfs-only, marker absent live. This inverts the naive "it's hardened" read.
- *"Maybe /ship or a commit hook writes gate-green and you missed it."* — Grepped ship.md (none) + both repos'
  `.git/hooks/*` (reso post-commit = git-lfs; no gate-green). Airtight.
- *"waiting-recycle covers the boundary case, so FM1 is handled."* — No: it's OPT-IN (IDL shows only
  `not-armed` abstains right now — nothing is armed), capped at 3, advisory-only. For an UN-armed builder it
  never fires; boundary-handoff (which would) is dead. The FM1 hole for non-monitoring sessions is real.
- *"The supervisor is the backstop."* — It PAGES ONLY with a default-empty CC_PAGE_TO and no page-consumer →
  in a true no-human loop the detection reaches nobody. Detection ≠ actuation.
- *"Recycle is the fragile part."* — Actually the MOST hardened (setsid, heartbeat gate, tty post-confirm,
  CR nudges). The fragile part is the un-verified NON-recycle spawn (G-P1-2) and the dead boundary gate.

## (7) Uncertainties

- Whether boundary-handoff has EVER fired in production — inferred never (gate-green absent since inception),
  but I did not grep the full idl.jsonl history, only the recent tail (all waiting-recycle `not-armed`).
- Whether any operator/automation consumes ~/.claude/autonomy/pages/ — found the producer, no consumer.
- Exact `/goal` 4000-char enforcement at the RECEIVER — read the doc's account (handoff.md:204-216), not the
  receiver binary; the failure mode (silent dead fire on >4000-char goal) is documented, not re-verified.
- ~/.claude/hooks assembly topology — confirmed a MIX (boundary-handoff symlinked into repo; intent-nudge a
  standalone real file). install.sh has no boundary/intent/Stop wiring (grep empty), so HOW the live hooks
  were assembled is unverified — likely hand-wired, which is itself G-P1-5's provisioning gap.
