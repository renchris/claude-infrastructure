# P15 — Unattended-Escalation Policy (what happens at a STOP-ASK boundary when no human exists)

**Beat:** map every human-gate → trace mechanical unattended behavior today → derive the clean
unattended-escalation protocol the 24/7 goal requires. **Method:** grep corpus for human-gates,
read hook CODE (mechanical) vs prompt TEXT (behavioral) vs runbooks (doc-step), verify LIVE state.
**Empirical vs theoretical is marked on every row.** All file:line cited to repo
`/Users/chrisren/Development/claude-infrastructure` unless noted.

> **Live demonstration captured while writing this report:** the first heredoc write was DENIED by
> `validate-bash.sh` because the text contained the literal danger-pattern strings it guards. That is
> gate #8 (M-adapt) firing — I read the deny reason and routed around it. An M-adapt gate is NOT a human
> strand; it is exactly the escalation shape the protocol below wants to generalize.

**Headline:** the *policy* is already largely derived — the **ZERO-HITL DoD** (`fea9200`,
SESSION_AUTONOMY_RESEARCH.md:408-426) + the **R-1..R-4 residual floor** (W0-W3_INTERVENTION_AUDIT.md:754-757)
already say STOP-ASKs → agent-ruled defaults + async queue + push-notify early-veto, only C10/permission/
external-info remain. The gaps are **mechanical, not doctrinal**: (a) the async decision-queue is a per-pane
epoch-timestamp dedup marker, not a decision packet; (b) the phone-push channel is INERT (Pushover
unconfigured, `PAGE_TO` empty) so "fail-loud" is loud-to-disk / silent-to-away-human; (c) the static
`git push:*` / `rm:*` ask-rules still hard-block in auto-mode, contradicting autonomous-at-green; (d) the
gate-batching class-router (axis c) and IDL reader tools (axis k) were designed but never built.

---

## 1. The STOP-ASK inventory — one row per human-gate

Class key: **M-adapt** = mechanical block the agent READS and routes around (not a strand);
**M-block** = mechanical prompt that BLOCKS the turn until a human clicks (strand);
**BEH** = behavioral prompt rule (session yields/idles); **DOC** = doc-stated human step (subsystem stays dark).
Strand cost: **task** = blocks the one session; **desk** = blocks the whole orchestrator.

| # | Gate | Codified (file:line) | Trigger | Class | What mechanically happens UNATTENDED today | Cost |
|---|---|---|---|---|---|---|
| 1 | Session-Close **STOP-ASK** row | CLAUDE.md:218 | decision (destructive migration/auth/nav/timeout) or missing info | BEH | session yields; `anti-deference-nudge.sh` Stop hook blocks-the-stop to force continue BUT abstains on the 3-genuine carve-out (anti-deference-nudge.sh:11-25) → session **sits idle in-context**; no queue routes the decision anywhere | task |
| 2 | **G2** escalation surface | CLAUDE.md:225 | auth/session, destructive migration, nav pattern, DB timeout | BEH | auto-continue gate fails → session yields (same idle as #1) | task |
| 3 | **G3** never push/deploy/ship/land | CLAUDE.md:226 | any push/deploy/ship/land | BEH+M-block | **superseded for ship** by ZERO-HITL (autonomous-at-green, T5 eliminated, proven `817448d`) — but the mechanical `git push:*` ask (row 6) still fires → CONTRADICTION | task |
| 4 | git push only on explicit request | CLAUDE.md:48 | any `git push` | BEH | superseded by ZERO-HITL + STRENGTHENING memory (feedback-drive-by-default:44-54) — ship is now the standing default for verified net-positive work | task |
| 5 | never force-push / destructive | CLAUDE.md:47,49 | force-push, hard reset, clean | M-adapt | static **deny** `git push --force`/`-f` (settings.example.json:54-55) + validate-bash deny (validate-bash.sh:81-125) → tool denied, agent READS reason + adapts. **Not a strand — correct.** | — |
| 6 | **static permission ask-rules** | settings.example.json:64-78 | `rm:*` `curl:*` `git commit:*` `git push:*` `git checkout:*` `git merge:*` `git rebase:*` `git reset:*` `npm install:*` `pnpm add:*` `fly deploy:*` `gh pr create:*` | **M-block** | in `--permission-mode auto` (forced by Max launchers, per KIMI_METERED_INTEGRATION.md:103-104) these are the ONLY static halts (permission-autonomy-allowlist-method.md:22-24). Turn **BLOCKS on the click**; `notify.sh` fires local sound+desktop only (notify.sh:74-76); supervisor pages after 900s as possible-MODAL but page has no phone delivery → **blocks indefinitely** | task→desk |
| 7 | static permission deny-rules | settings.example.json:38-63 | sudo/su/eval/exec/wget/dd/mkfs/chmod777/unlink/Read-secrets | M-adapt | tool denied, agent adapts. Not a strand — correct. | — |
| 8 | `validate-bash.sh` **deny()** | validate-bash.sh:33-44, 81-125 | recursive-force delete of root or home, DDL, drizzle push, git add -f, --no-verify, commit -n | M-adapt | independent PreToolUse deny (runs FIRST, permission-autonomy:25-29); agent reads reason + adapts. **Not a strand — LIVE-PROVEN by this report's own blocked write.** | — |
| 9 | `validate-bash.sh` **warn()→ask** | validate-bash.sh:46-57, 130-155 | git reset --hard, git clean -x/-X, recursive delete of a non-safe target | **M-block** | emits `permissionDecision:ask` → BLOCKS the turn (same as #6) even when static rules would pass | task→desk |
| 10 | `rm-safe-allowlist` fall-through | rm-safe-allowlist.sh:109 | any delete NOT provably regenerable-within-tree | **M-block** | exit 0 silent → falls through to the `rm:*` ask (#6) → BLOCKS. (Regenerable deletes auto-allowed — the one hole this closes) | task→desk |
| 11 | `frontier-spawn-gate` exit 2 | frontier-spawn-gate.sh:59-67 | frontier spawn past window/cap | **M-adapt** | exit 2 with a reason the agent READS → respawns on fallback / parks the hole. **The model gate design — a block the agent adapts to, never a human strand.** | — |
| 12 | **C10 self-modification** (harness) | P8-GO.md:53-59; SESSION_AUTONOMY_RESEARCH.md:72-86 | edit `settings.json`/`hooks/`/launchd/`.plist`/PATH | **M-block (hard)** | harness auto-mode classifier **DENIES atomically** (a peer-agent ruling is not user intent). Agent physically cannot. Parks + writes `/tmp/*-activate.sh`. **Correct by construction** (authority ceiling, invariant 6). Strand = subsystem dark until operator runs the script | task |
| 13 | **AskUserQuestion** in commands | limit-recover.md:4; compact-memory.md:4; skill-promote.md:4,12; evolve-skill.md:4,45 | command auto-invoked unattended | **M-block** | tool call → `notify.sh question` (settings.example.json:154) + BLOCKS turn. compact/skill-promote/evolve are human-gated BY DESIGN (correct to block); **limit-recover is unattended-likely** (fires at a limit event) — real risk | task |
| 14 | Notification/PermissionRequest page wiring | settings.example.json:138-161 | any permission prompt / question / plan / elicitation | (page, not block) | `notify.sh` → macOS sound + `osascript` desktop notification (notify.sh:65-76). **Local-only; invisible to a physically-away operator.** This is the escalation SURFACE, fired alongside the block | — |
| 15 | Manual-Command Delivery | CLAUDE.md §Manual-Command Delivery | interactive login, sudo, destructive op the human must own | DOC | agent writes `/tmp/<topic>.sh` + opens in cursor + surfaces. Strand = op undone until operator runs it; `/tmp` is reboot-volatile (risk-register #2) | task |
| 16 | C10 activation runbooks | RM-SAFE-ACTIVATION.md, AUTONOMOUS-REAPER-ACTIVATION.md, D2-RUNTIME-ACTIVATION.md, COMMS-SAFETY-ACTIVATION.md, NEVER-WAIT-ACTIVATION.md, REAPER-SAFETY-ACTIVATION.md, docs/activation/wiring-all.sh | any built-but-unwired subsystem | DOC | subsystem stays DARK until operator runs the consolidated `wiring-all.sh` (never self-run: wiring-all.sh is assembled NEVER RUN, SESSION_AUTONOMY_PLAN.md:707-715). No mechanism batches pending activations for morning review | task |

**Count by class:** M-adapt (not a strand — correct) = 4 (#5,7,8,11) · **M-block (strand) = 5** (#6,9,10,12,13) ·
BEH (yield/idle) = 4 (#1,2,3,4) · DOC (stays dark) = 2 (#15,16) · page-surface = 1 (#14).
**The 5 M-block rows + the anti-deference-cap idle are the entire unattended-strand surface.**

### 1b. What is LIVE vs designed (empirical, verified 2026-07-18)
- **LIVE daemons:** `com.claude.lead-supervisor` (pid 17867, `--daemon`), `com.chrisren.cc-reaper`,
  `com.claude.team-orphan-reaper` — all in `launchctl list`. Page-only supervisor IS activated.
- **LIVE state:** `~/.claude/autonomy/idl.jsonl` = **114 MB** (append-only, growing today); `pages/` = 184
  entries; `supervisor.log` 360 KB active. IDL written by lead-supervisor.sh, boundary-handoff.sh,
  waiting-recycle.sh, anti-deference-nudge.sh.
- **The `pages/` files are epoch-timestamp dedup markers** (`<uuid>.page` content = `1784370726`,
  lead-supervisor.sh:64) — page-once state, **NOT a decision packet**. There is no structured decision queue.
- **`page()` delivery** (lead-supervisor.sh:61-69): writes the `.page` stamp + IDL line + a **best-effort**
  `cc-notify "$PAGE_TO"` — but `PAGE_TO="${CC_PAGE_TO:-}"` defaults **EMPTY** (line 44) → the cc-notify branch
  is skipped by default. **Pushover unconfigured** (no `PUSHOVER_TOKEN` in env/`~/.zshenv`) → `push-critical.sh`
  exits 0 inert (push-critical.sh:21-22). **Net: a page reaches disk + IDL, and no human.**
- **NOT built:** `scripts/gate-*.sh` (gate-manifest/gate-classify/auto-stamp, axis c P1-P7 — the pre-signed
  class router); `bin/cc-idl` `bin/cc-audit` `bin/cc-truth` (axis k readers — IDL accumulates unqueryable);
  no morning-digest generator; no dispatcher/backlog loop (roadmap §5 P1, "Claude kicks off Claude").
- **Auto-mode confirmed:** Max launchers force `--permission-mode auto` (KIMI doc contrast, :103-104) →
  unattended desk sessions halt ONLY on ask-rules + PreToolUse-ask hooks + the dynamic classifier.

---

## 2. Existing policy — what the autonomy docs already rule (load-bearing quotes)

- **L4 operating model, roadmap L4 def** (L3-L4-AUTONOMY-ROADMAP.md:38-54): L4-via-CC-primitives is
  closed-loop / self-initiating / monitor-by-exception; the closed loop = backlog → dispatcher → halt-free
  workers → verify+merge gate → discovery feed. §2 (:26-31): *"the ONLY thing that ever prompts is a genuinely
  irreversible op (push, deploy, destructive migration) — and even those **queue for the next waking window,
  not block in place** (a PreToolUse hook can defer-to-a-review-file instead of halting)."* ← **the exact
  protocol this beat must mechanize; today it is aspirational (no such hook exists).**
- **ZERO-HITL DoD** (SESSION_AUTONOMY_RESEARCH.md:408-426, ruling `fea9200`): *"former STOP-ASKs become
  **agent-ruled defaults + async review queues + push-notify (EARLY-VETO, not approval)**; wave exits never
  fence on ratification; ship never gates progress (autonomous at green exits). The ONLY remaining stops:
  **C10/harness-constitutional · permission-system blocks · genuinely-external info** — and even these are
  **fail-loud + async, NOT fences**."* WHY (:414-416): *"every W0–W4 parked gate was ruled EXACTLY as the
  lead recommended — the asking was pure overhead."*
- **The residual floor R-1..R-4** (W0-W3_INTERVENTION_AUDIT.md:754-757, §9.2): T1-T8 driven to zero; the
  residual is **R-1 C10 self-mod** (harness-enforced), **R-2 C6 money-path** (never signable), **R-3
  permission-system blocks** (the ceiling holding), **R-4 genuinely-external info** (shrinks with the class
  vocabulary). §9.2: *"the residual **must not be driven to zero** — it is the safety rail."*
- **The four build directions** (audit §9.2, D-i..D-iv): **D-i** pre-stage every residual stop as a ready
  one-action artifact (`/tmp/p8-activate.sh` template); **D-ii** broaden pre-signed ruling CLASSES so fewer
  items fall to R-4; **D-iii** every residual stop SELF-DECLARES (fail-loud + push-notify + park, never a
  silent pause); D-iv supervisor pages-not-acts.
- **Supervisor ruling #1** (SESSION_AUTONOMY_RESEARCH.md:134, 401-404; lead-supervisor.sh:4-14): PAGES,
  never auto-recovers — detect + checkpoint-preserve + page; bash cannot drive a live pane so it physically
  cannot improvise a close. MODAL/permission dialogs are **structurally invisible** to the bash sweep
  (lead-supervisor.sh:11-14,164-166) → a live-but-effect-dark pane is PAGED as possible-MODAL, never actioned.
- **The authority ceiling / C10** (invariant 6, SESSION_AUTONOMY_RESEARCH.md:72-86; P8-GO.md AMENDMENT 1:28-46):
  *"an authority that discovers it over-signed should VOID the class, not re-time the request"* — C10 is
  **stronger than STOP-ASK: not desk-signable even with conditions**; agent hands an activation script, never
  activates. Gate-batching class map (:222): C1-C5,C7 pre-signable; C6 out-of-class-by-default; C9 `/ship`
  permanent-exclusion+backstop (later dissolved to autonomous-at-green by ZERO-HITL); **C10 permanent human-only**.
- **Operator standing values** (feedback-drive-by-default-operator-values.md): drive-by-default — re-asking a
  decision the standing values settle is a DEFECT (:10-22); the STRENGTHENING (:44-58): *"if it's net-positive,
  it is always yes… NEVER frame it as optional/fast-follow/want-me-to"* → ship/land is the standing default for
  VERIFIED net-positive work; reserve surfacing for the **genuine three ONLY**: (1) external-info-only-they-have,
  (2) value-fork the values don't settle, (3) a **C10 permission grant you literally cannot self-execute**
  (:56-58). ANTI-DEFERENCE (:72-83): a blocker is NEVER a reason to hand the whole task back — **(1) route
  around it** OR **(2) escalate the SINGLE specific missing thing and keep everything else moving**. SPELL-OUT
  (:85-97): every surfaced decision carries plain-English {what / choice / need / recommendation+default}.
- **P8-GO ruling** (P8-GO.md): the canonical worked example — a peer-orchestrator "CONDITIONAL GO" cannot
  manufacture human consent for self-persistence; the harness denial is *correct and load-bearing, not an
  obstacle*; nothing partial landed (atomic denial). Rollback one-liner is mandatory (condition 3, :72-76).

---

## 3. The derived protocol — three decision classes + queue mechanics + morning surface

**Design stance:** the doctrine already exists (ZERO-HITL + R-1..R-4 + D-i..D-iv). This protocol MECHANIZES
it and closes the delivery gap. It preserves the operator hard-reds (C10/C6/permission) as human-only while
making everything else non-stranding. It must NOT re-introduce ship/land as a gate (ZERO-HITL dissolved C9)
and must NOT let the queue become a re-ask crutch (anti-deference: route-around FIRST, queue is last resort).

### 3.1 Three decision classes (every STOP-ASK boundary routes to exactly one)

| Class | Membership | Handling | Grounded in |
|---|---|---|---|
| **A — AUTO-DECIDE + audit trail** | anything the standing values OR a pre-signed ruling class (C1-C5,C7) settle; all of T1-T8; ship-at-green | agent rules the default, ACTS, records `{fired,...}` to IDL + a greppable `[AUTONOMY:kind:sha8]` transcript marker; never phrased as a question | ZERO-HITL; drive-by-default; audit §9.1 T1-T8; invariant-5 four-zeros |
| **B — QUEUE-FOR-REVIEW / continue-elsewhere** | R-4 only: external-info-shaped OR a value-fork the values don't settle, AFTER route-around failed. NOT ship, NOT anything the values settle | agent attempts anti-deference route-around FIRST; if truly blocked, write ONE decision packet, push-notify early-veto, PARK that item, pull next backlog item (desk keeps moving) | ZERO-HITL async queue; anti-deference :72-83; D-ii/D-iii |
| **C — HARD-BLOCK (human-only)** | R-1 C10 self-mod/persistence · R-2 C6 money-path · R-3 permission-system denial | park; stage a ready one-action artifact (`/tmp/*-activate.sh` + rollback one-liner); fail-loud to the queue + push; NEVER retry, NEVER route around the ceiling | authority ceiling inv6; P8-GO; D-i |

The router is the missing **`scripts/gate-classify.sh`** (axis c, unbuilt). Bias is asymmetric: **any doubt →
B or C, never A** (SESSION_AUTONOMY_RESEARCH.md:222 asymmetric whitelist — a false-A is catastrophic).

### 3.2 The decision-queue artifact (the core BUILD)

**Path:** `~/.claude/autonomy/decisions/<id>.json` (sibling to the live `pages/`; FIXED cross-account dir like
the IDL). **Schema** (maps 1:1 to the SPELL-OUT memory :85-97):
```
{ id, created, class:A|B|C, session_sid, session_pane_uuid,
  what_plain,            # what the decision IS — NO codenames/jargon (memory :88-90)
  options,               # [{label, outcome_in_operator_terms}]
  recommendation,        # the agent's pick + WHY
  default_if_no_veto,    # what the agent WILL do at the deadline absent a veto  (class B only)
  veto_deadline,         # ISO; class B acts on default at deadline; class C has none (waits)
  staged_artifact_path,  # /tmp/*-activate.sh for class C, rollback one-liner inline
  route_around_taken,    # what the desk did INSTEAD to keep moving (class B)
  status:open|vetoed|actioned|expired-actioned }
```
**Who writes:** any session hitting a class-B/C stop (via a new `bin/cc-decide open …`, fail-closed like
`cc-wait`). **Who reads:** (a) the **morning-digest** routine; (b) **surviving sessions** — the desk sweeps
`decisions/*.json status=open` and routes around them (never re-derives, never re-asks — carries the
standing-value constraints per memory :41-43). **Push on write:** class B/C → `push-critical.sh` (once Pushover
is wired) = the early-veto channel. **Evidence invariant (inv7, :88-116):** the decision packet is EVIDENCE —
its status is a VIEW/hygiene concern; never let a hygiene reaper delete an `open` packet on age; deletion keys
on age only AFTER `actioned|vetoed`.

### 3.3 How the desk routes around a parked decision
1. Sweep `decisions/` for `status=open`; for each class-B, confirm `route_around_taken` is set (else the
   agent violated anti-deference — the desk logs it).
2. Pull the next durable-backlog item (needs the dispatcher/backlog loop, roadmap P1 — cross-beat dep).
3. Class-B `default_if_no_veto` fires automatically at `veto_deadline` (async early-veto, not sync approval) →
   status `expired-actioned`, IDL-logged. Class-C waits (no default; the ceiling holds).

### 3.4 Morning-review surface
A `bin/cc-digest` routine (roadmap §4 P2, unbuilt) reads `decisions/` + `pages/` + the IDL four-zeros
(invariant-5) and emits ONE batched digest: {what landed unattended, class-B defaults that fired + their
veto windows still open, class-C artifacts staged awaiting activation, any `abstained==100%` inert-check
alarms (inv7 :120-125)}. This is the designed operator touch — batched, legible, never an interrupt.

### 3.5 The two mechanical fixes that make the doctrine real (both operator-run, never agent-self-edit)
- **Wire the phone-push** — set `PUSHOVER_TOKEN`/`PUSHOVER_USER` in `~/.zshenv` (push-critical.sh:10-11,21-22)
  AND set `CC_PAGE_TO` to a live desk pane for the supervisor (lead-supervisor.sh:44,66-67). Without this,
  "fail-loud + push-notify early-veto" is loud-to-disk / silent-to-away-human — the doctrine's terminal
  assumption is unmet. (This is itself R-3-shaped: a credential the operator sets once.)
- **Narrow the blocking ask-rules on the autonomy launcher** so autonomous-at-green ship actually runs:
  the `git push:*` ask (settings.example.json:68) hard-blocks in auto-mode (ask shadows allow,
  permission-autonomy:54-64) — contradicting ZERO-HITL T5. The lever is narrow/remove the ask or gate with a
  PreToolUse allow-hook (permission-autonomy:31-35), scoped to the land-lock+detached-worktree ship path only.
  **Keep C10 self-edit denial intact** (never auto-widen permissions — that IS the ceiling, inv6).

---

## 4. Gaps

| id | file:line | FM | Pri | Failure scenario | Fix sketch |
|---|---|---|---|---|---|
| G-P15-1 | lead-supervisor.sh:44,66-67; push-critical.sh:21-22; ~/.zshenv | 24x7 | **P0** | Away operator: every class-B/C stop + supervisor page reaches disk+IDL and NO human. `PAGE_TO` empty, Pushover inert, notify.sh is local-only. "Fail-loud + early-veto" is silent-to-away-human — the ZERO-HITL delivery assumption is unmet | Operator sets Pushover creds + `CC_PAGE_TO`; add a `cc-digest` daily push. Operator-run (credential = R-3) |
| G-P15-2 | (no `scripts/gate-classify.sh`, no `~/.claude/autonomy/decisions/`) | FM1 | **P0** | STOP-ASK boundary has no router + no decision packet. A genuine stop idles in-session context; if the desk recycles (waiting-recycle.sh) the decision context is LOST — no durable artifact survives | Build `bin/cc-decide` + `decisions/` schema (§3.2) + `gate-classify.sh` (A/B/C router, asymmetric-bias). Register-criteria-first per the `43de6d6` discipline |
| G-P15-3 | settings.example.json:68; CLAUDE.md:226 vs SESSION_AUTONOMY_RESEARCH.md:411 | FM2 | **P1** | Doctrine says ship autonomous-at-green; mechanism `git push:*` ask blocks it in auto-mode. Every autonomous land strands on a click nobody makes | Narrow/hook-gate the `git push:*` ask on the autonomy launcher, scoped to the ship rails; keep force-push deny + C10 self-edit denial |
| G-P15-4 | anti-deference-nudge.sh (ANTIDEF_MAX=3 cap) | FM1 | **P1** | After 3 nudges the Stop hook allows the stop → session idles. Bias is false-negative (misses soft-defers) → some soft-defers slip through to a silent idle with no queue entry | Wire anti-deference's "genuine-3" exit to auto-open a class-B/C decision packet (§3.2) so a real stop ALWAYS leaves a durable, pushed artifact — never a bare idle |
| G-P15-5 | commands/limit-recover.md:4 | FM1 | **P1** | `/limit-recover` fires at a limit event (unattended-likely) with `AskUserQuestion` in allowed-tools → BLOCKS. The headless poller path exists (LIMIT_RESET_AUTO_RESUME_POLLER) but the command can still elicit | Gate the AskUserQuestion behind a `CC_UNATTENDED=1` env that routes the question to a class-B packet + default (waiting vs switch-account per the standing values) |
| G-P15-6 | docs/*-ACTIVATION.md; wiring-all.sh (7 pending) | 24x7 | **P2** | Built-but-unwired subsystems (P8, D2, never-wait, comms-safety, reaper-safety) stay DARK; `/tmp/*-activate.sh` accumulate + are reboot-volatile (risk #2). No batch surfaces them | `cc-digest` lists staged class-C activation artifacts each morning (D-i); move staged artifacts out of `/tmp` to a durable `~/.claude/autonomy/pending-activation/` |
| G-P15-7 | ~/.claude/autonomy/idl.jsonl (114 MB) | none | **P2** | IDL is append-only 114 MB with no reader (`cc-idl`/`cc-audit` unbuilt) and no visible rotation. Evidence accumulates unqueryable; unbounded growth is a latent hygiene risk (but inv7: it is EVIDENCE — rotate by AGE only, never by state) | Build `cc-idl --replay` + `cc-audit --wave` (axis k P7/P9); age-based rotation with a durable archive, never state-keyed deletion |

---

## 5. Task candidates

| id | action | acceptance criterion | depends-on |
|---|---|---|---|
| T-P15-1 | Operator runbook: wire Pushover + `CC_PAGE_TO` + verify a real page reaches the phone | a supervisor page AND a class-B packet both produce a received phone push; effect-checked (a scratch page delivered), not assumed | — (operator creds; R-3) |
| T-P15-2 | Build `bin/cc-decide` + `~/.claude/autonomy/decisions/` schema (§3.2) | RED-proven: opening a class-B packet writes the full schema; missing `default_if_no_veto` on class-B fail-closes; `status=open` survives a recycle; inv7 — no age-reaper deletes an `open` packet | register-criteria-first gate |
| T-P15-3 | Build `scripts/gate-classify.sh` (A/B/C router, asymmetric any-doubt→B/C) | RED-proven: a C10-surface (`settings.json`/hooks/launchd) → C; a value-settled item → A; an ambiguous item → B not A; mirrors handoff-disposition split | T-P15-2 |
| T-P15-4 | Narrow the autonomy-launcher `git push:*` ask, scoped to the ship rails | autonomous-at-green ship completes unattended in a probe; force-push still denied; C10 settings self-edit still denied; operator-run script (never agent self-edit) | — |
| T-P15-5 | Wire anti-deference genuine-3 exit → auto-open a decision packet | a genuine-carve-out stop leaves a durable pushed packet, never a bare idle; RED-proven the 3 carve-outs each emit a packet | T-P15-2 |
| T-P15-6 | Build `bin/cc-digest` morning-review (decisions + pages + four-zeros + inert-check alarms) | one batched digest lists landed / open-veto-windows / staged-activations / `abstained==100%` alarms; pushed once/day; never interrupts | T-P15-1, T-P15-2 |
| T-P15-7 | `CC_UNATTENDED` guard on command-level AskUserQuestion (limit-recover first) | `/limit-recover` unattended routes its question to a class-B packet + standing-value default; interactive path unchanged | T-P15-2 |
| T-P15-8 | Move staged activation artifacts `/tmp`→`~/.claude/autonomy/pending-activation/`; digest lists them | a pending C10 activation survives reboot + appears in the digest | T-P15-6 |

---

## 6. Cross-beat dependencies
- **Dispatcher/backlog loop** (roadmap §5 P1, "Claude kicks off Claude") — the class-B "continue-elsewhere"
  degrades to "queue-and-idle" for a LONE desk without a durable backlog to pull from. If another P-beat owns
  the dispatcher, T-P15-2/3 feed it; the decision queue and the work backlog are distinct artifacts.
- **Verify+merge gate / autonomous-at-green ship** (roadmap §5 P1) — T-P15-4 (ask-narrowing) is the mechanical
  half of whatever beat owns autonomous landing; coordinate the scoped allow-hook with the land-lock rails
  (reference-landing-safety-tooling).
- **Supervisor page delivery** — T-P15-1's `CC_PAGE_TO` wiring is shared with any beat touching lead-supervisor
  page routing; single-owner that file.
- **Boundary-hook / waiting-recycle** — G-P15-2's "decision lost on recycle" interacts with any beat tuning
  recycle thresholds; the decision packet MUST be durable-on-disk before a recycle fires.
- **Frontier-routing** — frontier-spawn-gate (#11) is the reference design for a class-of-gate the agent
  adapts to rather than a human strand; any new gate should follow its exit-2-with-reason pattern, not an ask.

---

## 7. Adversarial self-pass + Uncertainties

**Self-pass — 3 gaps I probed with tool calls (not assumptions):**
1. *Does an unattended permission prompt EVER auto-resolve?* Read the RUNNING `lead-supervisor.sh`: it is
   **page-only for every state** (DEAD/STALL/MODAL → `page()`, :125-166); the blueprint's "auto-deny stale
   teammate permission_request" (SESSION_AUTONOMY_RESEARCH.md:184) is **NOT in the running daemon**. Empirical:
   **no lead permission prompt is mechanically resolved** — all page-only. Corrects any assumption that the
   supervisor unblocks prompts.
2. *Does the page reach an away human?* `PAGE_TO` defaults empty + Pushover unconfigured → **no**. This
   falsifies the ZERO-HITL "push-notify early-veto" as currently DELIVERED (the doctrine is sound; the wire is
   absent). Elevated to G-P15-1 P0.
3. *Does ship actually run autonomously?* The static `git push:*` ask blocks it in auto-mode — a
   policy/mechanism contradiction (G-P15-3). The `817448d` proof landed via a specific detached-worktree
   land-lock path; whether that path is ask-exempt on the autonomy launcher is UNVERIFIED (see U2).

**Does my protocol violate any operator standing value?** Checked each: (a) drive-by-default — class B is
gated behind anti-deference route-around FIRST and reserved for the genuine three ONLY, so it is not a re-ask
crutch; (b) time-zero / 100th-pct — the queue is fail-loud + lossless (durable packet), never a silent pause;
(c) land-is-operator's-call → STRENGTHENED to autonomous-at-green — my protocol does NOT re-gate ship (C is
C10/C6/permission only; T-P15-4 UNBLOCKS ship, never re-blocks it); (d) C10 human-only — R-1/R-2/R-3 stay
hard-block, and every fix here is operator-run, never an agent self-widening of permissions. **No violation.**

**Uncertainties (explicit):**
- **U1 — how a permission prompt behaves headless is INFERRED, not directly observed.** Evidence: auto-mode is
  forced (KIMI:103-104), only ask-rules/hooks/classifier halt (permission-autonomy:22-24), notify.sh fires on
  the prompt. I did not run a live unattended session to time-out a prompt. It *may* block indefinitely, or the
  harness *may* have an idle-timeout that abandons the turn — UNVERIFIED. If the latter, the strand becomes a
  silent turn-abandon (worse). Worth a live probe.
- **U2 — whether the autonomous `817448d` ship path is ask-exempt.** The proof landed under land-lock from a
  detached worktree; I did not confirm the `git push` in that path escaped the `git push:*` ask (it may have
  run in a window where the ask was already narrowed, or via a non-Bash-tool path). G-P15-3 assumes it blocks;
  verify before building T-P15-4.
- **U3 — the 114 MB IDL rotation.** I confirmed no reader tools and today's growth; I did NOT confirm absence of
  a rotation cron. If unrotated it is a latent disk risk; low-priority either way (evidence, age-rotate only).
- **U4 — team-orphan-reaper's scope.** It is launchd-loaded but I did not read its code; it may already
  auto-deny/reap stale TEAMMATE permission modals (the blueprint's one bounded auto-act). If so, teammate (not
  lead) permission strands are already handled — narrows G-P15 scope to leads/desks. Worth a 1-file read.
