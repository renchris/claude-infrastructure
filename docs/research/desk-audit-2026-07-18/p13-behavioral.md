# P13 — Behavioral Layer: Encode-vs-Enforce Map (Orchestrator Desk)

**Beat:** rules that live in prompt-space, and where context rot defeats them.
**Method:** all claims read from files (empirical) unless tagged (inferred). Repo =
`~/Development/claude-infrastructure` (symlink source for `~/.claude`). Live `~/.claude/CLAUDE.md`
verified byte-identical to repo `CLAUDE.md` (288 lines, 21165 B, same mtime — FF5 deploy in parity).

## Central thesis (verified, load-bearing)

Mid-session, the model is reachable by **exactly three injection channels**: `UserPromptSubmit.additionalContext`,
`PostToolUse.additionalContext` (confirmed delivered @2.1.183 — waiting-recycle.sh:44), and a `decision:"block"`
`reason` on Stop/PostToolUse (fed back as the next turn). **Stop-hook `additionalContext` is INERT** (memory-nudge.sh:5-8
cites GH #37559; boundary-handoff.sh:21 "additionalContext is inert/probe-gated on 2.1.207"). Therefore:

- A rule with a **deterministic trigger** on one of those channels is **re-injected at the relevant seam → context-rot-RESISTANT.**
- A rule that is **resident-only** (read once at token 0) or **never-triggered** decays with fill and is **context-rot-EXPOSED.**

The lazy-load restructure (commits 90e003f, df2cdf5, a0f80ff) therefore *improved* rot-resistance for the triggered
rules and **left the Session Close Protocol — the primary anti-FM1/FM2 rule — resident-only and untriggered.** That is
the single biggest behavioral-layer exposure.

---

## §1 Encode-vs-Enforce Table

Legend — Enforcement: **HARD** = hook can `deny`/`exit 2`/block; **ACTUATE** = Stop/PostToolUse `decision:block` re-injects
(advisory, agent must comply, capped); **INJECT** = additive `additionalContext` nudge (advisory); **NONE** = prompt-only.

| # | Rule / behavior | Where encoded | Enforcement (file) | On context-rot drop | FM exposure |
|---|---|---|---|---|---|
| R1 | **Session Close: frozen DoD** (restate ask as `Scope (frozen:)`) | CLAUDE.md:204-208 | **NONE** — no hook stores/reads the DoD | completeness re-judged fresh → scope drift or premature ✅ | **FM1 (primary)** · 24×7 |
| R2 | **Session Close: readout / ✅-vs-📦-vs-🔧** (worst-open rung) | CLAUDE.md:237-283 | **NONE** — "/wrap computes ledger" (L279) but `/wrap` does not exist (§3) | readout self-reported, not git-verified → false ✅ | **FM1** · 24×7 |
| R3 | **Session Close: auto-continue G1-G4** (drive in-scope work) | CLAUDE.md:223-227 | **ACTUATE** `session-continue.sh` (Stop) — but agent-armed opt-in only | if rot drops it, agent never arms → stops with work left | **FM1+FM2** · 24×7 |
| R4 | **Anti-deference / drive-by-default** (don't present drivable work as a question) | CLAUDE.md:270-279; memory feedback-drive-by-default | **ACTUATE** `anti-deference-nudge.sh` (Stop, cap 3, 3-genuine carve-out) | fires only on regex defer-*tell*; a silent stop w/o tell is missed | **FM2** · 24×7 |
| R5 | **Boundary handoff at context fill** | CLAUDE.md:196-201 (implied); hook | **ACTUATE** `boundary-handoff.sh` (Stop, ≥73%, latch+Δ10 re-arm) | B-1 blind: a hung-mid-turn never Stops → never fires (:8-11) | FM2 · 24×7 |
| R6 | **Monitoring-desk recycle when purely waiting** | operator rule 2026-07-17; hook | **ACTUATE** `waiting-recycle.sh` (PostToolUse:Bash, ≥55% OR rot-tell, armed, cap 3) | armed opt-in; a builder never covered; rot-tell regex-bounded | **FM2** · 24×7 |
| R7 | **Agent-Teams = default for 2+ code files** | CLAUDE.md:121-150 | **HARD** (partial) `agent-teams-enforce.sh` — DENY bg-impl≥2kw (:112-123); INJECT nudge fg-impl (:126-137) | bg-impl still denied; fg path is nudge-only | FM1 (uncoordinated work) |
| R8 | **Teammate brief ≤150 lines + pre-grep ranges** | CLAUDE.md:126-133; agent-teams skill | **NONE** — hook injects a *pointer* (:75-78), never counts lines | oversized brief → `/compact` teammate crash (GH #49593) → wave stall | **FM2** (wave stall) |
| R9 | **Teammate concurrency cap = 6** | CLAUDE.md:135 | **NONE** — no hook counts live teammates | over-spawn → contention | FM2 (adjacent) |
| R10 | **Teammate model on Max auto-mode allowlist** | agent-teams; SSOT model-config.yaml | **HARD** `agent-teams-enforce.sh:34-65` DENY off-allowlist | (enforced regardless of rot) | — (closed) |
| R11 | **Worktree isolation for 2+ writers** | CLAUDE.md:176-194 | **NONE** for the *decision*; **HARD** for reap safety `git-worktree-guard.sh` (branch -D / worktree remove of live cwd) | agent may share checkout → index races; but destructive reap blocked | FM1 (clobber) |
| R12 | **Never commit/land in shared checkout** | .claude/CLAUDE.md:1-15 | **NONE** — prose only | commits onto wrong branch; sibling `/ship` drops it (incident 2026-07-11) | FM1 (silent loss) |
| R13 | **Land via project-local `/ship`; verify by CONTENT not count** | .claude/CLAUDE.md; memory reference-landing-safety | **HARD** at `/ship` (land-lock+stranded-sweep); **NONE** on ad-hoc `git rev-list` count checks | false "looks landed" (count=0 while files absent) | **FM1** (silent loss) |
| R14 | **Frontier tier = opt-in, bounded autonomous escalation** | CLAUDE.md:172-174; frontier-routing skill | **HARD** `frontier-spawn-gate.sh` DENY window-closed (:64-67) + per-session cap (:58-61, reserve-halve) | (enforced regardless of rot) | — (closed) |
| R15 | **Research: decompose-before-count, N=10, no cap** | CLAUDE.md:152-170; research-subagents skill | **INJECT** `research-precognition-nudge.sh` (UserPromptSubmit on intent) + spawn-time pointer | UPS nudge re-injects pre-cognition; strong | FM1 (under-spawn) low |
| R16 | **Memory hygiene / anti-capture** | CLAUDE.md:87-109 | **INJECT** `memory-nudge.sh` (UserPromptSubmit every 12) | periodic re-inject; decent | low (memory rot) |
| R17 | **File Update: INTEGRATE never overwrite (OVERWRITE GUARD)** | CLAUDE.md:60-86 | **INJECT/backup** `backup-before-write.sh` (PreToolUse) auto-backs up + warns | backup always taken; warn advisory | FM1 (history loss) low |
| R18 | **Plan docs: Phase 0 + INTEGRATE** | CLAUDE.md:111-113; plan-conventions skill | **INJECT** `plan-agent-teams-default.sh` (non-blocking, plan paths) + `validate-plan-structure.sh` (PostToolUse) | injected on plan edits only | low |
| R19 | **Spawned-session lifecycle** (notify-back + completion push + sweep) | memory desk-spawned-session-lifecycle | **HARD backstop** `cc-reaper` + `team-orphan-reaper` (launchd) — but the *notify-back/completion-push* convention is **NONE** | reaper cleans orphans; missed completion-pushes = silent | FM2 (spawn leak) |
| R20 | **Teammate edit stays in-worktree** | agent-teams | **HARD (opt-in)** `check-edit-boundary.sh` (freeze/focus deny) — off by default | if unarmed, cross-worktree edits possible | FM1 (clobber) |
| R21 | **Teammate task green before complete** | agent-teams; Session Close "behaviorally green" | **HARD (partial)** `task-quality-gate.sh` (TaskCompleted exit 2) — **tsc-only, team-only, reso-path-bound** (:37,90-92); no-op on bash/python/desk-own work | desk's own "gate green" claim = self-report | FM1 (false-green) |

---

## §2 Lazy-Load Reliability

**Mechanism.** The restructure (CLAUDEMD_LAZYLOAD_REVIEW.md) cut the always-resident knowledge layer **1516→288 lines
(−80%)** by moving 7 detail blocks to skills, each behind a trigger (review doc :50-58). Two trigger *classes*:

- **Deterministic** = a hook injects a skill pointer / status at a fixed event (Agent-spawn PreToolUse, SessionStart,
  backup-before-write on plan edits, UserPromptSubmit). Re-injects at the seam → rot-resistant.
- **Description-match** = the harness/model chooses to invoke `Skill` from the YAML `description`. Model-discretion,
  **no runtime proof of firing.**

Every resident pointer also carries the **core directive** (graceful degradation, review doc :75-78) → a trigger-miss
degrades to "core-only", never "absent" — but "core" is itself resident-only and rot-exposed.

| Desk-critical skill | Trigger | Class | Reliability | Miss mode |
|---|---|---|---|---|
| `agent-teams` | `agent-teams-enforce.sh` injects pointer on every `team_name` spawn (:75-78) | Deterministic | **High** — but fires *at* spawn, **late for brief-sizing/count** decision | pointer loads full discipline only after the sizing choice already made |
| `research-subagents` | `/research` invokes it; `research-precognition-nudge.sh` (UPS, intent regex); spawn-time pointer | Deterministic (2 seams) | **High** — UPS nudge precedes the count-choice | ad-hoc research with no intent-marker + not via /research → UPS miss |
| `frontier-routing` | `frontier-status.sh` (SessionStart one-liner) + `frontier-spawn-gate.sh` HARD deny | Deterministic | **High** — silent when window closed & no holes (zero-cost) | SessionStart line rots by mid-session; gate still HARD-catches stale spawns |
| `plan-conventions` | `plan-agent-teams-default.sh` + backup-before-write inject on plan paths | Deterministic (path-scoped) | **Med-High** | fires only on recognized plan paths (CLAUDE.md:111 list); non-standard plan path misses |
| `coding-standards` | description-match only (+ resident pointer names core rules) | **Description** | **Low** | model doesn't invoke → operates on resident 6-conv pointer; teammates get agent-teams pointer not this (FF1 folded 6 convs into brief) |
| `browsermcp` | description-match only (+ resident "not Playwright") | **Description** | **Low** | model doesn't invoke; mitigated by browser-tool-error trigger phrasing |
| `manual-command-delivery` | description-match only (+ **resident pointer states the whole rule**) | **Description** | **Low-but-safe** | full rule is resident, so a miss is harmless |

**Trigger-MISS mid-session behavior.** Because skills load *fresh* when triggered, a Tier-1 skill is **more** rot-resistant
than an equivalent resident rule. The exposure inverts to: (a) description-match skills (no deterministic fire), and
(b) the **untriggered resident rules** — chiefly Session Close (§1 R1-R3), which has no trigger on any channel.

**Verdict:** lazy-load is **sound and net-positive for rot-resistance** on the 4 deterministic skills; the 3 description-match
skills are acceptable *only because* their resident pointers carry the core. The restructure did **not** touch the real
weak point (Session Close is resident-only both before and after). Review doc's own FF3 relocated the never-land para to
`.claude/CLAUDE.md` (project-only) — correct, but it stayed prose (R12).

---

## §3 Desk-Verb Inventory

| Verb | Impl kind | File | Notes |
|---|---|---|---|
| `/handoff` | command + script + hook | commands/handoff.md; scripts/handoff-fire.sh; boundary-handoff.sh | full rails: split-right fire, --recycle |
| `/ship` | command (2×: global + project-local) | commands/ship.md (skill list shows a project-local `/ship` too) | land-lock + stranded-sweep + content-verify |
| `/accounts` | command + skill | commands/accounts.md; skills/accounts | cross-account quota/auth |
| `/research` | command | commands/research.md | invokes research-subagents skill (df2cdf5) |
| `/compact-memory` | command | commands/compact-memory.md | |
| `/harvest-skill` | command | commands/harvest-skill.md + harvest-skill-end.sh (SessionEnd) | |
| `/cleanup-team` (teardown) | command + bin | commands/cleanup-team.md; bin/cc-teardown (+safety-gate) | |
| `/limit-recover` (recover) | command + skill | commands/limit-recover.md | |
| `/resume-sessions` (resume) | **skill** | ~/.claude-secondary/skills/resume-sessions | crash/compact recovery |
| `/dia` | **skill** | skills/dia-agent | |
| `/frontier-hole` `/frontier-run` `/frontier-campaign` | **skills** | skills/frontier-{hole,run,campaign} | + frontier-spawn-gate HARD bound + frontier-status SessionStart |
| **`/wrap`** | **PHANTOM** | — none — | CLAUDE.md:200 "Mechanism = this rule + a `/wrap` command"; :254 `/wrap --full`; :279 "/wrap computes the ledger from live git/gate reads". **No wrap.md in repo/, ~/.claude/, or ~/.claude-secondary/.** The ledger is thus **hand-computed by the model = self-report**, defeating the protocol's "reports facts, not self-report" claim (:197). |
| **`/goal`** | **PHANTOM (on disk)** | — none — | Brief states this session has a "live goal Stop hook." Exhaustive search (hooks/scripts/bin/commands/launchd/settings across all config dirs) finds **no `goal` implementation** — only an English-word comment in premortem-gate.sh. Inference: runtime-injected (launcher `--append-system-prompt` or session-local settings) OR a loose description of `session-continue.sh`'s armed sentinel. Either way it is **unversioned / not durable** → fragile. |
| **`/investigate`** | **PHANTOM** | — none — | research skill/command steer "for depth-first debugging use `/investigate`" — no investigate.md exists anywhere. Dangling reference. |

---

## §4 Memory → Code Promotion Status

Several operational memory rules are **ALREADY promoted** (the operator has been doing exactly this beat):

| Memory entry | Promoted? | Enforcement |
|---|---|---|
| Drive-by-default / operator values | ✅ | `anti-deference-nudge.sh` (Stop) |
| desk-monitor: fixed-HEAD-ref | ✅ (design baked into) | `boundary-handoff.sh` B-2 latch + Δ re-arm (:12-16, :97-107) — same failure class |
| Landing-safety (verify by content, land via /ship) | ✅ partial | land-lock + stranded-sweep + project `/ship`; **ad-hoc count-checks still NONE** (R13) |
| Frontier-window SSOT discipline | ✅ | `frontier-spawn-gate.sh` reads SSOT live, deny stale |
| Effect-read predicate RED-proof; blind-check stdin/sid-keys | ✅ (as authoring law) | applied across boundary-handoff/waiting-recycle/anti-deference IDL+latch design |
| Spawned-session lifecycle | ✅ backstop only | `cc-reaper`+`team-orphan-reaper` (launchd); **notify-back/completion-push convention = NONE** |

**STILL prompt-only** (runtime disciplines, no hook), with enforcement sketch:

| Memory entry | Still prompt-only | Enforcement would look like | FM |
|---|---|---|---|
| cc-notify sessionId-only pane resolution | property of `bin/cc-notify` — verify it resolves by `--list --json` sessionId in code (not agent discipline). If code already does it → closed; if agent-chosen → wrap in cc-notify | mis-route nudge | FM2-adjacent |
| read-transcript-before-causal-claim | **Yes** — epistemic discipline | hard to mechanize; a Stop/PostToolUse lint that flags causal words ("because","rate-limited") in a turn with no transcript Read is possible but noisy | FM1 (wrong WHY → wrong action) |
| event-keyed (not subject-keyed) idempotency | **Yes** — authoring law | code-review/lint-time (`reaper-horizon-lint.sh` style), not runtime | low |
| fixed-HEAD-ref monitors | mostly baked in | lint monitors for `BASE=$(git rev-parse HEAD)` recompute-on-rearm pattern | FM2 (false stall) |

---

## §5 Gaps

```
G-P13-1 | CLAUDE.md:204-283 (Session Close) | FM1 | P0 | The frozen-DoD completeness check + readout are prompt-only with NO trigger on any mid-session channel; at high fill the model re-judges "done" fresh and can assert ✅ prematurely (purpose-loss). No mechanism verifies "done" vs frozen scope, and 📦-vs-✅ (committed≠landed) is exactly the split most likely to be mis-asserted. | Stop-hook that reads the model's own readout claim and contradicts it from live git (trunk..HEAD, dirty tree, gate-green sha) — block ✅ when git disagrees.
G-P13-2 | commands/ (absent) | FM1 | P0 | `/wrap` is referenced 3× as the ledger COMPUTER (CLAUDE.md:200,254,279) but does not exist → the "un-fakeable state readout" is hand-computed = fakeable self-report. | Ship a `/wrap` command (or a wrap.sh the readout calls) that emits the ledger from live git/gate reads; wire it into the Stop-hook of G-P13-1.
G-P13-3 | ~/.claude (no goal impl) | FM1/FM2 | P1 | The "live goal Stop hook" is not on disk → the session-purpose anchor (the thing that should re-assert the goal under rot) is unversioned/runtime-only and cannot be relied on across recycles. | Make goal a durable mechanism: a sentinel (like session-continue) that a Stop/UPS hook re-injects the frozen goal from, versioned in hooks/.
G-P13-4 | agent-teams-enforce.sh:75-78 | FM2 | P1 | Brief-≤150-lines + pre-grep are pointer-only; oversized brief → teammate /compact crash (GH #49593) → wave stall (FM2). The hook fires AT spawn and injects a pointer but never COUNTS the brief. | In agent-teams-enforce.sh, measure `prompt` line count; if >150 with team_name, INJECT a hard warning (or deny) naming the split rule.
G-P13-5 | scripts/lead-supervisor.sh (no launchd) | FM2 | P1 | The out-of-session "past-threshold ∧ not-Stopping" backstop that boundary-handoff/waiting-recycle explicitly defer to (waiting-recycle.sh:16) exists as a script but has NO launchd plist (only team-orphan-reaper is scheduled). If unscheduled, a hung-mid-turn desk past its boundary has NO carrier. | Add a launchd plist for lead-supervisor.sh (confirm it isn't cron-driven first); else the B-1 blind spot is uncovered.
G-P13-6 | task-quality-gate.sh:37,90-92 | FM1 | P2 | "Behaviorally green before complete" is enforced ONLY for TS teammate tasks against a hardcoded reso path; bash/python/desk-own work no-ops (exit 0) → the desk's own "gate green" close claim is unverified self-report. | Generalize the gate to run the repo's declared gate (per-project CLAUDE.md "Session Close" gate names) not just tsc; apply to desk-own commits, not only team tasks.
G-P13-7 | coding-standards/browsermcp (description-match) | none/low | P2 | 3 skills fire only on model-discretion with no runtime proof; a miss silently drops detail (mitigated by resident core). | Accept for browsermcp/manual-cmd (safe cores); for coding-standards add a PostToolUse:Write nudge on *.ts/*.py when authoring new files.
G-P13-8 | R13 landing count-check | FM1 | P2 | verify-by-content is enforced in /ship but ad-hoc `git rev-list origin/main..HEAD` count checks (the 2026-07-11 false-"landed" incident) remain a prompt-only discipline. | A git wrapper / post-land assert that checks `git ls-tree origin/main -- <paths>` by content, warns on count-only reasoning.
```

## §6 Task Candidates

```
T-P13-1 | Build `/wrap` (command + wrap.sh) emitting the Session-Close ledger from live git/gate reads | Running /wrap prints Scope/Done&verified/Committed/Landed(trunk..HEAD)/Blocked with values from `git status`+`git rev-list`+gate-green sha, zero model input | none (unblocks T-P13-2)
T-P13-2 | Stop-hook `session-close-assert.sh`: contradict a ✅/📦 readout that live git refutes | Given a transcript whose last msg asserts "complete & live on trunk" while `trunk..HEAD>0` or tree dirty, hook fires decision:block naming the contradiction; clean state → silent; capped+latched like anti-deference | T-P13-1
T-P13-3 | Durable `/goal` anchor: sentinel + Stop/UPS re-injection of the frozen goal | `goal set "<purpose>"` writes a versioned sentinel; a UserPromptSubmit hook re-injects it every N prompts; survives /handoff recycle | none
T-P13-4 | agent-teams-enforce.sh: brief-line-count guard | A team_name spawn whose `prompt` >150 lines gets a HARD warning/deny citing the split rule + GH #49593; ≤150 passes silently | none
T-P13-5 | Schedule lead-supervisor.sh via launchd (after confirming current invocation path) | A plist exists + loaded; a synthetic past-threshold-not-Stopping desk gets paged within the interval | G-P13-5 triage
T-P13-6 | Generalize task-quality-gate to the repo's declared gate + desk-own commits | On a bash/python repo the gate runs that repo's lint/test (not tsc no-op) and can exit 2; desk-own close is gated | none
```

## §7 Adversarial Self-Pass + Uncertainties

**Hostile-reviewer gaps I chased (with tool calls, not assumptions):**
1. *"You read the repo CLAUDE.md, not what agents load."* → Verified live `~/.claude/CLAUDE.md` is byte-identical (288 lines, 21165 B, same mtime). Parity holds **now**; FF5 made install.sh deploy it, but it's a **copied regular file, not a symlink** → future drift is possible (config-mirror-assert.sh SessionStart is the guard).
2. *"`/goal` must exist somewhere."* → Exhaustive grep across hooks/scripts/bin/commands/launchd/settings in all 3 config trees: only an English-word comment hit. Genuinely absent on disk → runtime-injected/unversioned (G-P13-3).
3. *"Is UserPromptSubmit really the only mid-session channel?"* → Corrected: **three** channels (UPS.additionalContext, PostToolUse.additionalContext, Stop/PostToolUse decision:block reason). Stop.additionalContext is inert (GH #37559). Precise statement used throughout.
4. *"lead-supervisor may cover the boundary blind spot."* → It exists but has **no launchd plist** (only team-orphan-reaper does) → the deferred-to backstop may be unscheduled (G-P13-5).

**Uncertainties (named):**
- U1 — Whether description-match skills (coding-standards/browsermcp/manual-cmd) actually fire at runtime is **unproven**; the review doc tested only the two hook-injected pointers by payload. No harness log inspected here.
- U2 — cc-notify sessionId-only resolution: not confirmed whether it's code-enforced in `bin/cc-notify` or an agent discipline (didn't read the script). If code-enforced, R19/§4 row is already closed.
- U3 — lead-supervisor.sh invocation path (cron? keepalive? manual?) not traced — G-P13-5 needs that triage before adding a plist.
- U4 — `/ship` appears twice in the skill/command listing (a global and a claude-infrastructure-local). Did not diff them; the project-local one is the safe path per .claude/CLAUDE.md.
- U5 — Effort/model of a desk session is not readable from these files; the "300K-deep desk forgets token-0 rule" premise is asserted by the operator (waiting-recycle.sh:6-8 cites rot "noticeable ~40-50%") — consistent with, but not independently measured in, this pass.
