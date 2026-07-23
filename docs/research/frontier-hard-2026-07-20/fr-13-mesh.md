# FR-13 — The hook & skill mesh as a configuration/composition system

**Verdict: accretion with a partial, silently-degraded compile layer.** The mesh is not
incoherent — set-level parity is genuinely good (permissions 350/41/6 identical across all 5
dirs; registered-script sets identical across all 5). What has accreted is everything the
existing detector normalizes away, everything the existing mirror silently skips, and
everything no detector can see at all. A compile-from-SSOT layer is the right generator-class
fix, but the report's sharpest finding is that **the current drift detector reports GREEN while
three real divergences are live**, because its normalization is the exact complement of the
drift that survives.

---

## 1. Mesh matrix + counts

**Scale.** 55 hook scripts in `hooks/` (`*.sh`+`*.py`); 55 in live `~/.claude/hooks`; **50
distinct scripts registered**; **346 total hook registrations** (`.claude` 70 + 4 × 69).
12 events in use.

| Event | entries (`.claude`) | notes |
|---|---|---|
| SessionStart | 12 | largest chain; `config-mirror-assert`, `session-register`, `frontier-status` |
| PreToolUse | 11 | incl. 3 untracked gates (below) |
| PostToolUse | 9 | |
| Stop | **9** | all other dirs: **8** — the one set-visible asymmetry |
| Notification | 8 | |
| PermissionRequest | 6 | |
| SessionEnd | 5 | |
| UserPromptSubmit | 4 | |
| PreCompact | 3 | 2 are inline `date` echoes, not scripts |
| TeammateIdle / WorktreeCreate / TaskCompleted | 1 each | |

**Config-dir registration.** All 5 dirs register the **identical set** of 50 scripts
(`missing=[] extra=[]` for secondary/tertiary/quaternary/next vs `.claude`). The a19 pathology
(desk on `.claude-secondary` lacking `boundary-handoff` entirely) is **RESOLVED** — confirmed
both by the matrix and by `hooks/boundary-handoff.sh:44-52`, whose own header records the
re-observation.

**Path resolution.** 60 registrations use `~/.claude/hooks/…`, 9 use the machine-absolute
`/Users/chrisren/.claude/hooks/…`, **1 uses a repo-absolute path**
(`/Users/chrisren/Development/claude-infrastructure/hooks/boundary-handoff.sh`, `.claude`
Stop obj-1). **0 broken references** — every registered path resolves.

Consequence worth stating plainly: because every command hardcodes `~/.claude/hooks/…`, the
per-dir `hooks/` directories (52 symlinks each in secondary/tertiary/quaternary/next) are
**never invoked**. All 5 accounts execute the same `~/.claude/hooks/*` files. Hook *content* is
therefore already single-source; only *registration* drifts.

**Drift instances: 3 — all invisible to `settings-drift-assert.sh`.**

1. `.claude` Stop registers `boundary-handoff.sh` **twice** (obj-0 via `~/.claude`, obj-1 via
   repo-abs). → the 9-vs-8 delta.
2. `keychain-guard.sh` / `rm-safe-allowlist.sh` **order-swapped** between {`.claude`,
   `.claude-next`} and {secondary, tertiary, quaternary} (PreToolUse idx 3/4).
3. `handoff-intent-nudge.sh` / `research-precognition-nudge.sh` **order-swapped** between
   {`.claude`, quaternary} and {secondary, tertiary, next} (UserPromptSubmit idx 2/3).

**Intentional asymmetry (real, must be preserved):** `effortLevel` =
high/low/medium/low/high; `tui: fullscreen` on tertiary+next only; `enableAllProjectMcpServers`
present on all except `.claude`. Nothing else diverges outside `hooks`.

**Inert-but-registered:** 1 (`boundary-handoff` obj-1 — §FR-13-2).
**Built-but-unregistered: 8** — `cc-permission-beacon.sh`, `cc-unattended-ask-guard.sh`,
`ship-rail-push-allow.sh` (the three most recent hook builds: `b7db06c`, `12259b6`, `9d2bf16`
— and these three are additionally **absent from `~/.claude/hooks` entirely**, not even
symlinked), plus `migrate-plans-index.sh`, `session-deregister.sh`, `session-index-sweep.sh`,
`smart-bash-allowlist.sh`, `task-completed-index.sh`. Wiring is C10 operator-gated
(`65e1d6e`), so "landed" ≠ "live" by design — but nothing measures the gap.

**Registered-but-untracked: 3** — `curl-gate.py`, `enforce-email-formatting.py`,
`keychain-guard.sh`. Real files in `~/.claude/hooks` (not symlinks), registered as PreToolUse
gates in **all 5 dirs**, and `git ls-files` returns **empty** for all three. Two are
security-class (network egress; keychain/credential).

**Observability coverage: 5 of 50 registered scripts (10%)** emit IDL
(`boundary-handoff`, `anti-deference-nudge`, `completion-assert`, `waiting-recycle`,
`teammate-auto-shutdown`). 207,147 IDL records total.

---

## 2. Ranked frontier rows

| # | Problem | Evidence | Why default-tier insufficient | Solution shape | Confidence |
|---|---|---|---|---|---|
| **FR-13-1** | **The drift detector's normalization is the exact complement of the drift that survives — it reports GREEN over 3 live divergences — and it is not wired.** | `scripts/settings-drift-assert.sh:33-38`: `sig_hooks()` terminates in `\| sort -u`, and `norm_cmd()` reduces to basename+args. That erases **order**, **multiplicity**, and **path spelling** — precisely drift instances 1/2/3. Live run today: `settings-drift-assert: GREEN — deny/ask/hooks agree across 5 config dirs`, exit 0. Not scheduled: `grep -c drift scripts/nightly-regression.sh` = **0**; no `settings-drift-assert` plist in `~/Library/LaunchAgents` (only desk-invariant, nightly-regression, discovery, dispatcher, lead-supervisor, cc-reaper are loaded). It exists only in the *pending* `docs/activation/wiring-all.sh:58`. It also ignores `permissions.allow` (350 entries; synced today by luck, unasserted by contract). | The failure is not visible from reading the detector or from its selftest — both are internally consistent and pass. It is only visible by building the ground-truth matrix *independently* and noticing GREEN ≠ no-drift. Default-tier reflex is to treat a green assert as evidence; the load-bearing move is distrusting the oracle's normalization. Compounding: `hooks/boundary-handoff.sh:51` and `scripts/settings-dedup-stop.sh:10-13` each document *one* blindness (duplicates) while the *order* blindness is undocumented anywhere in the repo. | SSOT manifest → compiled `settings.json`. Drift check becomes byte-identity of `compile(manifest, overlay[dir])` vs on-disk, not a normalized set-compare. Order and multiplicity stop being detectable-in-principle problems and become non-representable. | **High** |
| **FR-13-2** | **Silent hook-loss channel: a second matcher-absent object in an event array does not execute — undocumented, and it inverts the premise the dedup tooling was built on.** | `.claude` Stop is 2 objects; obj-1 is `{"hooks":[{...boundary-handoff, no timeout}]}` with **no `matcher` key**. IDL forensics over 334 evals: `boundary-handoff` = **334**, `anti-deference-nudge` = **334**, `completion-assert` = **334**, and **0 duplicated `(sid,ts)` pairs** for any of them. **25 of 73** distinct sids resolve to `~/.claude/projects` (account 1 — the only dir with the duplicate). If obj-1 executed, boundary-handoff would exceed its obj-0 siblings by ~34%; it is exactly equal. → obj-1 is **inert**. Meanwhile `scripts/settings-dedup-stop.sh:8-9` states the hook "**double-fires** on every turn close" — empirically false in-window. Anthropic's docs specify **none** of this: multi-hook execution order, multi-block arbitration, exit-2 cascade, and hook-array merge across settings layers are all confirmed **undocumented** (code.claude.com/docs/en/hooks.md, /settings.md). | Requires deriving a falsification experiment from telemetry against a behavior the vendor never documented, then overturning an existing in-repo narrative that a landed commit encodes. Default-tier accepts the repo's own stated premise. The generalized hazard is what matters: a *new* hook wired into a second matcher-absent object is silently dead — and being dead, it emits no IDL, so FR-13-4's detector cannot see it either (compounding blindness). | Manifest compiles to **exactly one matcher-absent object per event**; multiplicity becomes unrepresentable. Add a conformance-probe tier: registered-hook count reconciled against observed distinct-hook IDL/exec count per event. | **Med-High** (inference is strong; the residual is that no account-1 session might have Stopped in-window — refuted by the 25/73 sid attribution, but stated for honesty) |
| **FR-13-3** | **No closure invariant over the mesh: `registered ⊄ version-controlled` and `built ⊄ wired`. Two security gates exist only as untracked live files.** | `curl-gate.py`, `keychain-guard.sh`, `enforce-email-formatting.py`: registered PreToolUse in all 5 dirs, real (non-symlink) files in `~/.claude/hooks`, `git ls-files` **empty**, `find` over the repo returns nothing. The SSOT does not contain the network-egress gate or the keychain gate. Converse direction: 8 built-but-unregistered (§1), 3 of them the newest hook builds, not even symlinked into live. **Latent landmine:** `settings.json` is **not** in any `_CC_ISOLATE` set in `~/.claude/lib/config-mirror.zsh:17-21`, and that file's own comment (`:60`) calls it "the **SHARED** settings.json" — i.e. the design intends a symlink. Safe-mode skips forked real files silently (`:41-44` — `(( convert )) \|\| continue`, no warning), which is why 5 forks persist. A future `--convert` run would `mv` each to `.premirror-bak` and symlink them to `~/.claude/settings.json`, **silently collapsing the intentional per-account `effortLevel`/`tui` asymmetry**. | Each half looks benign alone; the invariant is only visible when both directions are enumerated against a third source (git). The `--convert` landmine specifically requires reading the mirror's *skip* branch and connecting it to the intentional-asymmetry table — the skip is a bare `continue` with no log line, so no telemetry will ever surface it. | Manifest declares the full closure: every registered command resolves to a tracked path; every tracked hook declares wired/deliberately-inert with a reason. `settings.json` moves into an explicit isolate-or-generated set so the mirror can never claim it. CI assert on both directions. | **High** |
| **FR-13-4** | **Inert-detection covers 10% of the mesh because observability is opt-in per hook.** | `cc-discover` C3 (`bin/cc-discover:206-225`) keys on IDL `disposition`; only 5 of 50 registered scripts call `log_idl` (`grep -ln 'log_idl\|cc-idl' hooks/*.sh` = 4 files + `waiting-recycle`). The other **45 registered hooks are structurally undetectable as inert** — a broken matcher, a changed event name, or a silently-dead object (FR-13-2) produces no signal. C3 has been carefully refined (per-hook windows, reason-aware dormancy — `1228506`, selftests at `:344-377`) — i.e. effort has gone into precision on the 10%, not into coverage of the 90%. | The instinct is to keep improving C3's reason-awareness (which the repo has done well). Seeing that the *coverage denominator*, not the precision, is the ceiling requires counting emitters against registrations rather than reading C3. | Invert instrumentation: a generated wrapper (`hook-run <name> -- <cmd>`) that the compiler emits around every registered command, logging invoke/exit/duration. Coverage goes 10% → 100% with zero per-hook edits, and gives FR-13-2's reconciliation for free. Cost: one exec layer per hook — measure against the 5s/10s timeouts before adopting. | **High** |

---

## 3. Design-sketch assessment (brief question c)

**The proposed shape is right**, with three corrections.

- **Not hard: enable-conditions.** Today there is exactly one conditional dimension in practice
  (wired / deliberately-inert / staged-pending-C10). A three-valued `state:` field with a
  mandatory `reason:` covers the observed inventory. Don't build a predicate language.
- **Not hard: per-account asymmetry — but it is REAL and must be first-class.** Only 3 keys
  diverge intentionally (`effortLevel`, `tui`, `enableAllProjectMcpServers`), and none are hooks.
  A `base.yaml` + `overlay/<dir>.yaml` with a **closed allow-list of overlayable keys** is
  sufficient, and it converts FR-13-3's `--convert` landmine into a compile error. Pure
  symlink-sharing is *wrong* and must be explicitly rejected — it would clobber `effortLevel`.
- **Genuinely hard: the compile target's semantics are undocumented.** You can make the emitted
  `settings.json` deterministic; you **cannot assert the harness consumes it as intended**.
  Order, multi-block arbitration, exit-2 cascade, and cross-layer array merge are all
  unspecified (FR-13-2). Therefore a "per-event order contract" as a *compile output* is
  necessary but **not sufficient** — array position is not an enforceable priority mechanism.
  Two consequences: (i) any real priority ordering must be arbitrated **in-band** by the hooks
  themselves (a shared lock/priority file), not by array index; (ii) the manifest needs a
  **runtime conformance tier** (observed-execution reconciliation, FR-13-4) alongside the static
  compile, because static correctness is unverifiable against an unspecified consumer.
- **Also hard, and under-appreciated: ownership arbitration.** Three writers currently touch
  live `settings.json` — `install.sh --wire-hooks` (additive-only, cannot remove:
  `settings-dedup-stop.sh:7-9`), `settings-dedup-stop.sh` (subtractive), and `config-mirror.zsh`
  (would symlink under `--convert`). A compiler must become the **sole** writer or it will fight
  all three. This is the migration's real risk, not the schema.

**Ordering exposure is currently latent, not realized** — of 23 turns where a block-emitting
Stop hook fired, **0** had ≥2 firing simultaneously (`completion-assert` 17, `anti-deference`
5, `boundary-handoff` 1). Rank the ordering work accordingly: it is a correctness-of-contract
problem, not an active incident.

---

## 4. The skills layer (brief question d)

**28 skills live, 9 tracked in the repo → 19 untracked (68%)** — the same
`registered ⊄ version-controlled` breach as FR-13-3, an order of magnitude wider.
(`~/.claude/skills` is a real dir; the sibling dirs symlink to it, so skills are content-shared.)

**Trigger reliability is two separable layers, and the repo currently enforces neither.**

*Statically conformable (measurable, enforceable — and already failing):*
- `pyramid-principle/SKILL.md` has **no YAML frontmatter at all** (file opens `# Pyramid
  Principle Prompt (Compressed)`) and **no `description:` field**. It is structurally
  un-auto-triggerable.
- `plan-update/SKILL.md` opens with an HTML `<!-- markdownlint-configure-file … -->` comment
  **before** the `---` fence. Its real description exists at line 4 but never reaches the
  trigger layer — **confirmed live**: the harness-rendered skill listing shows plan-update's
  description as the markdownlint JSON, not its authored text. A leading comment silently
  destroys the trigger contract.
- Description lengths span **7 → 1605 chars** (`frontier-routing` 1605, `outlook-cleanup` 210)
  with no floor, no ceiling, and no required "NOT for" disambiguator — though the best-written
  ones (`research-subagents`, `agent-teams`, `frontier-routing`) already follow a consistent
  triggers-plus-NOT-for shape that a linter could simply codify from existing practice.

*Inherently probabilistic:* whether the model loads the right skill for a given prompt. Not
enforceable, but it **is** measurable.

**Harness shape (two tiers, matching the hook design):**
1. **Lint (deterministic, CI):** frontmatter at line 1; `description` present, ≥N chars,
   contains ≥1 explicit trigger phrase and a "NOT for" clause; name matches dir; no duplicate
   names across staging/active. Catches both live defects today.
2. **Replay (statistical, nightly):** a fixture set of ~5 prompts per skill (positive) plus
   cross-skill negatives, scored on which skill loaded. Report per-skill precision/recall and
   a **collision matrix** over overlapping pairs — the real risk set is visible by inspection:
   `research-subagents`↔`agent-teams` (both fire on "spawn"), `frontier-routing`↔`frontier-run`
   ↔`frontier-hole`↔`frontier-campaign` (4-way), `browsermcp`↔`agent-browser`↔`dia-agent`
   ↔`autonomous-authenticated-web-access` (4-way), `pyramid-principle`↔`pyramid-principle-full`,
   `plan-conventions`↔`plan-update`, `grok-wiki-cli`↔`grok-wiki-custom`. Treat as a regression
   baseline, never a hard gate.

---

## 5. NOT frontier → routing

| Item | Route |
|---|---|
| Wire `settings-drift-assert.sh` (launchd or nightly-regression) | Backlog — mechanical, but **only after** FR-13-1's normalization is fixed; wiring it as-is institutionalizes a false GREEN |
| Remove `.claude` Stop obj-1 (repo-abs `boundary-handoff`) | Operator/C10 — `settings-dedup-stop.sh` already exists and is idempotent + backs up. Re-label the rationale: the hazard is **inertness**, not double-fire |
| Track the 3 untracked hooks into `hooks/` | Backlog, near-term — security-class, no design work needed |
| Normalize the 9 machine-absolute `/Users/chrisren/.claude/…` paths to `~/.claude/…` | Cosmetic today; free once a compiler emits them |
| Wire or formally retire the 8 built-but-unregistered hooks | Backlog — needs a per-hook C10 decision, not a design |
| `frontier-status.sh` / `activation-watch.sh` SessionStart cost | Not investigated — see §6 |

---

## 6. Could not determine

- **Whether obj-1 is inert by harness rule or by in-window accident.** The 25/73 account-1 sid
  attribution makes accident unlikely, but the clean experiment (register a distinct marker
  script in a second matcher-absent object and observe) is a **write** — out of scope here.
  Recommend it as the first conformance probe if FR-13-2 is picked up.
- **Whether hook-array merge across settings layers unions or replaces.** Undocumented, and
  unobservable here: no `settings.local.json` exists in any of the 5 config dirs, so the layer
  is untested in this environment. The repo *project* dir does carry
  `.claude/settings.local.json` (1206 b) — its interaction with the user-level hook arrays was
  not exercised.
- **Per-hook latency budget.** Timeouts are declared (5s/10s) but no observed-duration telemetry
  exists, so FR-13-4's wrapper cost cannot be sized against current headroom. SessionStart runs
  12 hooks serially (if serial — itself unspecified); this is the chain most exposed to a
  wrapper's overhead.
- **Whether `enableAllProjectMcpServers` absent on `.claude` is intentional or drift.** It is
  the only non-hook key where `.claude` is the odd one out; no rationale found in repo docs.
