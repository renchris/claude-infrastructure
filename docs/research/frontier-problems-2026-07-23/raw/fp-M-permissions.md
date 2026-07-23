<!-- source: /Users/chrisren/.claude-secondary/projects/-Users-chrisren-Development-claude-infrastructure/c424033a-5dc1-4e6c-b89f-0de5ecc8a30e.jsonl
 turns=77 assistant_texts=11 last_stop=end_turn mail_injections=[] -->

Saturated. Final confirms: `b7db06c` (permpend consumer) **is on main** and `cc-permission-beacon.sh` **is tracked on main** — but wired 0/3, so producer never fires. supervisor.log (20,129 lines, 8 days) logs **only sweep summaries** (`swept=N findings=M`) — **zero** typed finding records (permpend/STALL/MODAL/DEAD all 0 keyword hits). The stall *type* is durably recorded **nowhere**. Predict-next-call test fails (reading remaining hooks would add detail, not change any conclusion). Composing.

---

# Permission/Authorization Architecture — Autonomy + Visibility Surface

**Scope note / brief correction:** Two premises in the brief are now **stale-resolved** and I verified so: (1) *"desk cannot self-land"* — RESOLVED 2026-07-20 (Part D); `Bash(~/.claude/scripts/handoff-fire.sh:*)` + `Bash(scripts/ship-land.sh:*)` are in the live allow array, land runs as a subprocess of one allow-listed call (`desk-anti-hitl-2026-07-19.md:51-59`). (2) The supervisor is **not dormant** — `com.claude.dispatcher/discovery/team-orphan-reaper` are `launchctl`-loaded and `supervisor.log` is fresh (09:01Z, `swept=17 findings=8`). Empirical vs. theoretical is marked per claim.

## (a) Decision Stack for a Bash tool call — halt points + visibility

Evaluation order (empirical, from `~/.claude/settings.json` hooks array + `permissions`):

```
Bash("git reset --hard origin/main")  in defaultMode:auto
│
├─0. PreToolUse HOOKS (run FIRST, independent of settings; first non-empty decision wins, deny>all)
│    live Bash chain = curl-gate.py → validate-bash.sh → git-worktree-guard.sh
│                     → keychain-guard.sh → rm-safe-allowlist.sh   [settings.json PreToolUse]
│    ├ validate-bash.sh:33 deny()  → HARD DENY, no prompt   (rm -rf /, --no-verify, DDL, git add -f)
│    │                                VISIBILITY: none needed (command never runs; model sees reason)
│    ├ validate-bash.sh:46 warn()  → ASK  (git reset --hard :130, rm non-safe-target :145, clean -x:136)
│    │                                ⟵ HALT POINT A (hook-issued ask)
│    ├ rm-safe-allowlist.sh        → ALLOW (affirmative, state-checked) — REMOVES a would-be ask
│    └ (unwired, would sit here: smart-bash-allowlist, reset-hard-shadow-allow, ship-rail-push-allow)
│
├─1. settings.permissions.deny  (41 rules; 30 Bash / 11 Read) → HARD DENY, no prompt
│                                                                 (git push --force, sudo, eval, rm -rf ~)
├─2. settings.permissions.ask   (6 rules) → PROMPT  ⟵ HALT POINT B (settings ask)
│      fly deploy · git push · git reset --hard · git restore · git stash clear · git stash drop
├─3. settings.permissions.allow (350 rules) → ALLOW, no prompt
│
├─4. autoMode.soft_deny CLASSIFIER (30 NL categories in settings.json) → PROMPT  ⟵ HALT POINT C
│      catches what static prefixes can't: "Production Deploy" (push-to-main), "Self-Modification"
│      (edit settings.json), "Code from External" (curl|bash), "Create Unsafe Agents"
│      (--dangerously-skip-permissions). skipAutoPermissionPrompt:true suppresses the low-risk auto-prompt.
│
└─5. SANDBOX — NOT a layer here (no `sandbox`/`enableSandbox` key; only appears inside soft_deny text). [empirical]
```

**Halt points and their operator visibility (the core finding):**

| Halt | Trigger | Fires a signal? | Signal is… | Durable? |
|---|---|---|---|---|
| **A** hook ask | `validate-bash.sh` warn (`:130`,`:145`) | `PermissionRequest`→`notify.sh permission` + `push-critical.sh` | macOS sound + desktop banner; Pushover **INERT** (`push-critical.sh:21` — no `PUSHOVER_TOKEN`) | **No** |
| **B** settings ask | one of 6 ask rules | same as A | same as A | **No** |
| **C** classifier | `soft_deny` match | same `permission_prompt` Notification path | same as A | **No** |
| **modal/idle** (no answer) | session hangs mid-turn | supervisor sweep → `STALL?` page at `STALL_S=1800` (30 min) | `pages/<sid>.page` (ts only) + notify | ts-only, **untyped** |

**Empirical visibility verdict:** every halt point emits only **ephemeral, local** signals — a `notify.sh` sound + `osascript` desktop banner (`notify.sh:74-76`) that require the operator to be **at the machine**. The mobile break-through (`push-critical.sh`) is **inert**. There is **no durable, typed, queryable record** of any halt (see §b). A permission hang on an unattended session is therefore **invisible for ≤30 min**, then surfaces as a **detail-free generic `STALL?`** — exactly the failure the (unwired) beacon was built to fix.

## (b) Stall quantification

| Metric | Value | Source (empirical) |
|---|---|---|
| Longest documented permission hang | **133 min** (detected 30 min, resolved **2h13m**) | `desk-anti-hitl-2026-07-19.md:22` (incident 731f0968) |
| Documented permission-hang incidents | **N=1** (well-attested); no denominator | doc §B; no ledger exists |
| `git reset --hard` in current cmd log | **0** | `logs/bash-commands.log` grep |
| `git push` (recurs; genuine ask) | **121** | same |
| `git restore` / stash drop/clear / fly deploy | 4 / 0 / 0 / 0 | same |
| `rm -rf` (mostly hook-auto-allowed now) | **224** | same |
| `.page` files (all sessions, all time) | **177**, content = **unix ts only, no type** | `~/.claude/autonomy/pages/` |
| `supervisor.log` lines (Jul 15→23, 8 days) | **20,129**, all **`swept=N findings=M` summaries** | `~/.claude/autonomy/supervisor.log` |
| Typed finding records (permpend/STALL/MODAL/DEAD) in supervisor.log | **0** each | grep of supervisor.log |
| Real `permission_pending` beacon events | **0** — `/tmp/cc-permission-pending` **never created** | beacon unwired |
| `idl.jsonl` dispositions | 484 waiting-recycle-abstained, 33 anti-deference, 33 completion-assert; **~0 real permission** | parsed `autonomy/idl.jsonl` |

**"Fraction of STALL? pages that were permission-gates" = UNMEASURABLE by construction.** Neither `pages/` (sid→ts) nor `supervisor.log` (summary counts) records the finding *type*. The rate can only be reconstructed by replaying transcripts. This is itself a finding (frontier row F2).

## (c) Config-dir census + drift

**5 independent config dirs** (SSOT = `accounts.json`; corrects the "next2/3/4" naming):

| Dir | Launcher / account | settings.json | permissions md5 |
|---|---|---|---|
| `~/.claude` | bare `claude`/`cc` (default) | yes | `027a64764e3c` |
| `~/.claude-next` | acct1 (next) | yes | `027a64764e3c` |
| `~/.claude-secondary` | acct2 | yes | `027a64764e3c` |
| `~/.claude-tertiary` | acct3 | yes | `027a64764e3c` |
| `~/.claude-quaternary` | acct4 | yes | `027a64764e3c` |
| `~/.claude-183` | *binary dir* (`claude-cli/2.1.183` bin, node_modules) — **not** config | no settings | — |
| project `.claude/settings.local.json` | repo overrides (1206 B) | yes | (repo-scoped) |

**Drift finding (empirical): ZERO drift today.** All 5 dirs have **byte-identical** permission sets (350 allow / 41 deny / 6 ask, md5 `027a64764e3c`). The 2026-07-16 memory's "next4 missing a `Read(*secret*)` deny" is **resolved**. The live ask array is **narrower** than that memory records: no blanket `rm:*` or `git reset:*` — only `git reset --hard` and scoped stash subcommands. **What polices consistency: nothing.** No `settings-drift-assert` hook exists (grep of hooks/bin/scripts = none). Sync is a manual machine-wide edit-all-5 discipline; the invariant currently holds by luck/recency, not by an enforced gate. **Self-edit boundary:** the `autoMode.soft_deny` "Self-Modification" category is what blocks agents from editing any `settings.json` — so all 5-dir changes route through an operator-run script (silver-platter path). That delivery IS wired for *allow-list additions* (`fewer-permission-prompts` skill, `cc-decide --run`), but **not** for hook-wiring activations (see §d / F1).

## (d) Routine-vs-genuine halt catalog

| Ask/halt | Freq | Class | Correct disposition | Status |
|---|---|---|---|---|
| `git push` (feature branch) | high | **routine** | auto-allow non-trunk | ✅ handled by `smart-bash-allowlist.sh` (excludes trunk) — but that hook is **unwired**; currently still asks |
| `git push origin HEAD:<trunk>` (land) | med | **routine-but-sensitive** | provably-safe auto-allow | ⚠️ `ship-rail-push-allow.sh` built, **staged** (`05-ship-rail-push-allow-activate.sh`, **no `.done`**), unwired; desk path bypassed via `desk-land` subprocess |
| `rm -rf <build-artifact>` (224×) | high | **routine** | state-checked auto-allow | ✅ `rm-safe-allowlist.sh` **wired 3/3** — solved |
| `git reset --hard origin/main` (clean tree, worktree) | rare | **routine (reflog-reversible)** | state-predicated auto-allow | ⚠️ `reset-hard-shadow-allow.sh` built, **shadow-only, unwired** — the 133-min incident class |
| blocking `AskUserQuestion` under 24×7 | occasional | **routine** (should route to decision packet) | `cc-decide` class-B + deadline | ⚠️ `cc-unattended-ask-guard.sh` built, **unwired** |
| `fly deploy`, prod DB migration | rare | **GENUINE** | stay human | ✅ ask + classifier "Production Deploy" — keep |
| `git push --force` / force-with-lease | rare | **GENUINE** | stay denied | ⚠️ `--force`/`-f` hard-denied; **`--force-with-lease` NOT hard-denied** (falls to ask) |
| `--dangerously-skip-permissions` / `--no-sandbox` | rare | **GENUINE (disables the layer)** | executably block | ❌ **prose-only** (`settings.json:985`); classifier "Create Unsafe Agents" soft-catches; **0 hooks block it** |
| edit any `settings.json` | rare | **GENUINE** | stay blocked | ✅ classifier "Self-Modification" — keep |

**Pattern:** the routine, high-frequency asks are already solved (`rm`) or have a built-but-unwired fix (`push`, `reset`, `ask-guard`). The genuine high-risk gates are correctly retained. The gap is **deployment**, not design — every provably-safe auto-allow primitive the design calls for **exists on main as a file and is wired 0/3**.

**Primitives that would make every remaining halt loud + bounded** (design-doc §B.1-5, mostly built):
- state-predicated auto-allow hook (opt-in per shape, fail-closed, shadow→arm) — `reset-hard-shadow-allow.sh`, `ship-rail-push-allow.sh` ✅ built
- `PermissionRequest` beacon → supervisor pages typed `PERMISSION-PENDING <cmd>` in **120s** not 30min — `cc-permission-beacon.sh` ✅ built + `lead-supervisor.sh:160-174` consumer ✅ landed
- ask→`cc-decide` class-B packet + async veto deadline — `cc-unattended-ask-guard.sh` ✅ built
- Pushover break-through wired — 1 env var, ❌ inert

## (e) Candidate Frontier Problems

---

**F1 — The permission autonomy/visibility layer is built-and-landed but wired 0/5 (producer/consumer split-brain)**
- **Evidence:** `cc-permission-beacon.sh` tracked on main (`git ls-tree main` → blob `55a61fe4`) + consumer landed (`b7db06c` is-ancestor main; `lead-supervisor.sh:57-174` `page_permpend`) yet `/tmp/cc-permission-pending` **never created** and beacon wired in **0/3** account settings; `reset-hard-shadow-allow.sh`/`ship-rail-push-allow.sh`/`cc-unattended-ask-guard.sh`/`smart-bash-allowlist.sh` all wired 0/3.
- **Mechanism class:** deploy-gap / half-deployed safety feature (code-on-main reads as "done"; inert in production). Same family as memory `desk-autonomy-dormancy-staged-not-loaded`.
- **Current mitigations + status:** consumer live; producer file present; `05-ship-rail-push-allow-activate.sh` **staged, no `.done`**; beacon wiring **not even staged**. Blocked by the (correct) `autoMode.soft_deny` "Self-Modification" rule → agents can't self-wire settings; requires operator activation script that doesn't fully exist.
- **Why it resists normal fixes:** the fix is *editing the 5 settings.json* — the one act the safety model forbids the agent from doing. Landing more code doesn't help; there's no agent-reachable path from "file on main" to "wired in 5 dirs," and the silver-platter delivery is wired for allow-list rows, not hook-array wiring.
- **Quantified cost:** the 133-min hang class recurs with **0** typed early page; `git push`/`reset` routine asks still block 24×7 sessions. Broader rate **unmeasured** (see F2).
- **Frontier-fix sketch:** a single operator-run `activate-permission-layer.sh` that (a) inserts the 4 hook wirings into all 5 dirs idempotently, (b) shadow-arms reset/ship-rail, (c) exports Pushover creds, (d) content-verifies + prints a receipt; plus a `settings-wiring-assert` gate that fails closed if any of the 5 dirs lacks a required hook. Generalizes the `fewer-permission-prompts` silver-platter from *allow-rows* to *hook-arrays*.
- **Confidence:** High (all wiring states directly observed). **Stale-risk:** Medium — an operator activation run could flip several of these to `.done` any day; re-verify the 0/3 wiring before acting.

---

**F2 — Permission-stall rate is unmeasurable by construction (no typed durable ledger)**
- **Evidence:** `pages/*.page` content = **unix ts only** (177 files, all timestamps); `supervisor.log` = **20,129 summary lines**, `permpend/STALL/MODAL/DEAD` keyword count **0/0/0/0**; `idl.jsonl` carries recycle/nudge dispositions, ~0 real permission events.
- **Mechanism class:** observability gap — the apparatus pages but never records *why*.
- **Current mitigations + status:** none. `page_permpend` *would* write typed `idl permission_pending` records (`lead-supervisor.sh:163`), but only once the beacon (F1) feeds it.
- **Why it resists normal fixes:** the type is computed at page-time and discarded to an ephemeral notification; reconstructing history means replaying every transcript. You cannot set an SLO on, or trend, a quantity nothing logs.
- **Quantified cost:** **unmeasured — how to measure:** wire the beacon (F1), have `page_permpend` append `{ts,sid,type,cmd,age_s}` to a hash-chained `permission-stalls.jsonl`, then report weekly stall count / p95 age / routine-vs-genuine split. Today: N=1 anecdote, no denominator.
- **Frontier-fix sketch:** make every page write a typed, appended record (reuse the `cc-idl` hash-chain from `f83705b`); a `cc-audit` view renders stall-rate + longest-open. Turns anecdote into a managed metric and lets F4's routine/genuine split be *data-driven*, not hand-curated.
- **Confidence:** High. **Stale-risk:** Low.

---

**F3 — No scalable "routine ask → provably-safe auto-allow" generator; each shape is hand-coded, one exists**
- **Evidence:** the binding verdict "desk must NEVER press '1'" (`desk-anti-hitl-2026-07-19.md:24`) is correct (unbounded loss: rewritten trunk/prod/exfil). Its only sanctioned alternative is per-shape state-predicated hooks — but only **one** incident shape is drafted (`reset-hard-shadow-allow.sh`, still shadow), and it required a full 3-conjunct hand-proof (shape ∧ clean-tree ∧ sanctioned-worktree, `:SAFETY MODEL`).
- **Mechanism class:** design-completeness / scaling limit — safety proof is bespoke per command shape.
- **Current mitigations + status:** `rm-safe` (done), `reset-hard` (shadow), `ship-rail` (staged), `desk-land` subprocess-laundering (done). Each is a one-off.
- **Why it resists normal fixes:** a general "is this reversible/safe?" predicate is the hard part; the safe set is command-specific (reflog-reversibility, refspec semantics, worktree provenance) and adversarially fragile (metachar/TOCTOU/substitution). A generic allow-classifier would reintroduce the spoof surface the keystroke ban exists to avoid.
- **Quantified cost:** every new routine-but-gated shape = a bespoke hook + bats + shadow-soak; unmeasured backlog of un-hooked routine asks (`git push` feature, `git restore --staged`, etc.).
- **Frontier-fix sketch:** a *reversibility-predicate library* — small, composed, individually-proven primitives (`is-reflog-reversible`, `is-clean-tree`, `is-sanctioned-worktree`, `is-anchored-single-command` from `ship-rail-push-allow.sh:48`) that new shape-hooks assemble declaratively, plus a shared metachar/anchoring guard, so adding a shape is config not code, and the proof surface is audited once.
- **Confidence:** Med-High (extrapolated from the existing hooks' shared structure). **Stale-risk:** Medium — active area; new hooks may land.

---

**F4 — Deny-floor is softer than the ops that disable the whole permission layer**
- **Evidence:** live `deny` has `git push --force:*`/`-f:*` but **not `--force-with-lease`** (`python` check → `False`) nor `+`-refspec; `--dangerously-skip-permissions` is **prose-only** at `settings.json:985`, blocked by **0 hooks**, only soft-caught by classifier "Create Unsafe Agents." Deny lives in *settings* → **bypassed entirely in `bypassPermissions` mode**, leaving only the `validate-bash.sh` hook deny (which also lacks force-with-lease).
- **Mechanism class:** gap in the fail-closed floor / mode-dependent safety.
- **Current mitigations + status:** classifier soft_deny is the only catch for these three; it prompts rather than hard-denies, and is the layer a `--dangerously-skip-permissions` invocation is designed to remove.
- **Why it resists normal fixes:** these are meta-ops (they turn *off* the gate), so gating them in the same settings layer they'd disable is circular; the durable block must be a hook (mode-independent) not a settings rule.
- **Quantified cost:** low frequency, high severity (one `--force-with-lease` to trunk = rewritten history; one `--dangerously-skip-permissions` child = un-gated agent). Unmeasured occurrence.
- **Frontier-fix sketch:** add to `validate-bash.sh` a hard-deny for `--force-with-lease`, `+<ref>:` refspecs, `--mirror`, and any `--dangerously-skip-permissions`/`--no-sandbox` token (hook-level = survives `bypassPermissions`); mirror into all 5 dirs via F1's activation script.
- **Confidence:** High (gaps directly verified live). **Stale-risk:** Low.

---

**Blockers / uncertainties (explicit):**
- Whether a permission prompt fires a `PermissionRequest` *event* vs. only a `Notification[permission_prompt]` in this harness build is inferred from the settings wiring (both are wired to `notify.sh permission`); I did not trigger a live prompt. The beacon's contract assumes `PermissionRequest` exists (`cc-permission-beacon.sh:15`).
- `skipAutoPermissionPrompt:true` semantics (exactly which auto-classified allows it suppresses) inferred from name + the "auto already permits non-ask" behavior, not from harness source.
- Supervisor *runs* (log fresh) but I did not confirm which launchd job invokes `lead-supervisor.sh assess` (no `com.claude.supervisor` in `launchctl`; likely folded into dispatcher/reaper) — doesn't affect the beacon-unwired conclusion.
- `allow` count is 350 live vs 349 in the 2026-07-19 doc (+1 drift, immaterial).