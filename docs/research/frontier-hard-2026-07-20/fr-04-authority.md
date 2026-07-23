# AXIS 4 — Permission & Authority Architecture

> Frontier-discovery wave, 2026-07-20. Read-only audit of the 4-layer policy system.
> Sibling axes: `docs/research/frontier-hard-2026-07-20/`.

## 1. The four layers as wired TODAY

**L1 — static settings.** `~/.claude/settings.json` `permissions`: **350 allow / 6 ask / 41 deny**, `defaultMode: "auto"`. Byte-identical across all five config dirs — verified by sha1 over sorted arrays: `2202fee81743` for `.claude`, `.claude-secondary`, `.claude-tertiary`, `.claude-quaternary`, `.claude-next`. The mirror invariant **holds**.

`ask` = `fly deploy:*`, `git push:*`, `git reset --hard:*`, `git restore:*`, `git stash clear:*`, `git stash drop:*`. `deny` = 31 Bash shapes + 10 `Read()` secret-path globs.

**A sixth policy file the brief does not count:** `./.claude/settings.local.json` (repo-local, 1206 B, 32 additional allow entries incl. `Bash(python3 -)`, `Bash(git commit:*)`, `Bash(git worktree remove:*)`, `Bash(chmod +x:*)`). It is **not mirrored, not sha-checked, not in the config-mirror invariant**. No `managed-settings.json` exists at `/Library/Application Support/ClaudeCode/` or `/etc/claude-code/` — so there is no enterprise tier above the user layer; **the user layer IS the ceiling**.

**L2 — decision hooks.** Live `PreToolUse[Bash]` chain, in order: `curl-gate.py`, `validate-bash.sh`, `git-worktree-guard.sh`, `keychain-guard.sh`, `rm-safe-allowlist.sh`. Exactly one (`rm-safe-allowlist.sh`) is an *allow*-hook; the rest are deny/ask-hooks.

The wiring state is **worse than "wired nowhere"**:

| Hook | commit | in repo | symlinked live | in any of 5 settings.json |
|---|---|---|---|---|
| `ship-rail-push-allow.sh` | 9d2bf16 | Y | **N** | 0/5 |
| `cc-permission-beacon.sh` | b7db06c | Y | **N** | 0/5 |
| `cc-unattended-ask-guard.sh` | 12259b6 | Y | **N** | 0/5 |
| `smart-bash-allowlist.sh` | — | Y | Y | 0/5 (deliberate: `PART-B1-PERMISSION-HOOK-WIRING.md:9`) |

All three have passing bats suites (`tests/ship-rail-push-allow.bats`, `tests/cc-permission-beacon.bats`, `tests/cc-unattended-ask-guard.bats`). `~/.claude/autonomy/pending-activation/05-ship-rail-push-allow-activate.sh` exists **without a `.done` marker** (01/02/03 have theirs). The checkout is also **6 commits behind `origin/main`** — landed ≠ deployed.

Two live hooks are **duplicated**: `Stop` fires `boundary-handoff.sh` twice (`~/.claude/hooks/` and the absolute repo path — same file via symlink) and `notify.sh complete` twice; `Notification[permission_prompt]` fires `notify.sh permission` and `push-critical.sh` twice each.

**L3 — the auto-mode classifier.** Its policy body is **`settings.json` `autoMode.soft_deny`: 30 natural-language strings**, plus `autoMode.environment`: 7 strings. This is the real L3 surface and it is prose-in-JSON. Load-bearing entries: **#24 "Self-Modification: Modifying the agent's own configuration, settings, or permission files"**; #11 (`--dangerously-skip-permissions`, `--no-sandbox`); #7 (logging/audit tampering); #23 (unauthorized persistence).

**L4 — authority classes.** `scripts/gate-manifest.sh:45-47` (signability map), `:62` — `C10) "self-modification / persistence — settings/hooks/launchd/plist/PATH/creds; HUMAN-ONLY"`, permanent exclusion, never signable or stampable. Manifests are genuinely typed: `classes[]`, `expiry`, `signed_at`, wave scope, IDL-audited (`:98-120`).

---

## 2. Ranked frontier rows

### F1 — C10 is "correct by construction" in the docs and **unenforced in the wiring**; L1 allow silently shadows the only layer that holds it

| | |
|---|---|
| **Evidence** | Corpus asserts C10 is harness-enforced and "the agent *physically cannot*" (`p15-escalation.md:45`; `W0-W3_INTERVENTION_AUDIT.md:754` R-1: "the harness auto-mode classifier **enforces** it"). Its actual enforcement is **`autoMode.soft_deny` #24 and nothing else**: no `deny` rule covers `settings.json`, `hooks/`, `LaunchAgents`, `.plist`, or `PATH`; no live `PreToolUse[Bash]` hook inspects write *targets* for C10 paths (`validate-bash.sh` covers rm/DDL/`--no-verify`/`git add -f` only); `~/.claude/edit-boundary.json` is **absent** → no freeze active. The one hook that treats `.claude/` as a sensitive write target is `curl-gate.py:84`, hard-scoped to `PROJECT_ROOT = ".../reso-management-app"` (`:36`, `:408`) — **inert in the repo that holds the agent's own config**. Meanwhile L1 grants `Bash(tee:*)`, `Bash(python3:*)`, `Bash(find:*)`; `~/.claude/hooks/*.sh` are symlinks into the checkout, writable, and execute as **unchecked arbitrary code** on every Bash call (`log-bash.sh` is `PostToolUse[Bash]`). Chain: `tee ~/.claude/hooks/log-bash.sh` → matched by an L1 `allow` → **terminal permit, classifier never consulted** → arbitrary unchecked execution. Precedence empirically supported below (F2 evidence, 4/4). |
| **Why default-tier insufficient** | Every prior pass read this correctly *within its layer* and concluded "correct by construction." The defect is only visible as a **cross-layer precedence composition**: L1's terminal-permit semantics *disable* the L3 prose that is C10's sole enforcement. Default-tier work has repeatedly audited L1, L2, L3, L4 separately and produced four green verdicts over one red system. This is not an outage story — it is live, with a healthy classifier, today. |
| **Solution shape** | One typed SSOT compiling to all layers. A `c10_surface` predicate (path-set: `settings*.json`, `hooks/**`, `LaunchAgents/**`, `*.plist`, `PATH`, credential stores) emitted into (a) the `deny` array as write-shape rules, (b) a `PreToolUse[Bash]` **write-target** hook that parses redirections/`tee`/`python3 -c`/`find -exec` argv for C10 destinations, (c) the `soft_deny` prose as a restatement, and (d) a conformance test asserting all three agree. Key insight: **deny must be capability-shaped, not command-shaped** — today's `Bash(eval:*)`/`Bash(exec:*)` deny bare shapes nobody types while `Bash(python3:*)` grants the same capability. |
| **Confidence** | **High** on the wiring facts (all directly verified). **Medium-high** on end-to-end exploitability: the bypass was not executed (read-only brief), and the allow-terminal step rests on 4/4 empirical correlation + documented precedence rather than a controlled probe. |

### F2 — Degraded mode and C10 formalization are the **same problem**; building the desk's "keep running model-free" mode first actively removes C10's only enforcement

| | |
|---|---|
| **Evidence** | **New delta on the corpus:** the classifier outage has **two independent trigger classes**, not one. `a17-hostile.md:23` models only the 2026-07-18 monthly-spend cap. Transcripts show an earlier, **quota-independent** outage on **2026-07-11 09:12-09:15Z**: `"claude-opus-4-8[1m] is temporarily unavailable, so auto mode cannot determine the safety of Bash right now"` across three workflow agents (`.claude/projects/-Users-chrisren-Development-doc-classifier/89369003.../subagents/workflows/wf_cb779201-b55/agent-a{6203d3cc,19022137,0ca6fe0d}*.jsonl`). This is a hard external dependency, not a quota-management problem. **Precedence measured:** all 4 denied commands in that window contained a sub-command absent from `allow` (`awk`, `sed`, `sort`); fully-covered compound commands (`grep …; echo …; grep …`) succeeded at 09:12:01/09:12:02 in the same session. → static allow is terminal and bypasses L3. **Degraded surface quantified** over 4,000 real commands from `~/.claude/logs/bash-commands.log` (21,910 lines): **46-62% are classifier-routed** (lower bound = head unmatched; upper = head matched but a later sub-command uncovered, 654/2161). Top coverage-breakers: `git` sub-shapes (197), shell control-flow, `sed` (117), `sort` (63), `bash` (55), `awk` (34). |
| **Why default-tier insufficient** | The obvious fix — "widen the allowlist so the desk survives an outage" — is the **exact action that converts F1 from theoretical to trivial**, and it looks purely beneficial from inside the degraded-mode framing. The coupling is invisible unless both facts are held simultaneously: (i) allow is terminal, so widening allow removes classifier adjudication; (ii) the classifier is C10's sole enforcer. Today C10 held through both outages **only because everything halted** — the halt was total, not targeted. There is no differential: nothing distinguishes "write settings.json" from "run pytest" once the model is gone. A correct degraded mode is therefore **gated on F1 shipping first**. That ordering constraint is the frontier insight; it inverts the intuitive build order. |
| **Solution shape** | Define the degraded surface as a **computed closure**, not a hand-edited list: mine `bash-commands.log` for the desk's actual read-only corpus, machine-generate allow rules, and require every generated rule to pass the `c10_surface` predicate from F1 before emission. Then the "stunned" state machine becomes designable: **runnable model-free** = static-allowed ∧ ¬c10_surface ∧ ¬escalation_surface; **queued** = everything else, with a retry-at-reset scheduler (absent today — `a17-hostile.md:43`: "Nothing anywhere schedules a retry-at-reset"). Add `cc-classify` recognition of the verbatim outage string (`:74-77` currently greps only quota text → misclassifies as `owned-wait`, never reaped, never re-engaged — the 11h inertia). |
| **Confidence** | **High** on the two-trigger-class delta and the coverage measurement (the splitter over-counts shell keywords/heredocs, hence the honest 46-62% band). **High** on the ordering constraint. |

### F3 — The C10 activation ceiling is **self-referential**: it permanently prevents the permission system from being repaired

| | |
|---|---|
| **Evidence** | Three landed, tested permission-safety hooks are 0/5 live and not even symlinked (§1 table). `docs/SHIP-RAIL-PUSH-ALLOW-ACTIVATION.md:1` is titled "**ACTIVATION runbook (C10: human-only)**". `docs/D2-RUNTIME-ACTIVATION.md:4`: "Activating them modifies agent configuration and installs persistence — that is **ruling class C10**." So: every improvement to L1/L2 is *itself* a C10 act, therefore human-only, therefore permanently one human action behind. The staged activator `pending-activation/05-ship-rail-push-allow-activate.sh` sits unrun with no `.done`. This is the memory-indexed `staged≠loaded` dormancy pattern (`desk-autonomy-dormancy-staged-not-loaded.md`) **recurring inside the safety layer itself** — the highest-consequence instance. No conformance test fails on "a landed hook with green tests is not live" (`tests/install-wire-hooks.bats`, `tests/desk-assert-wiring.bats` exist and do not catch it). |
| **Why default-tier insufficient** | Default-tier work correctly identifies each instance and correctly refuses to self-activate — the refusal is *right*. What it cannot do is recognize that the refusal is **generative of the backlog it keeps reporting**, and that the fix is not a permission change but a **change in what the human is asked to consent to**. This is the F1-F4 Follow-On-Gate boundary hitting a genuine hard limit: "no chain of agent-to-agent rulings sums to a human's consent" is correct, and it silently converts safety improvements into an ever-growing dark backlog. |
| **Solution shape** | Move consent from *per-activation* to *per-policy-diff*. The agent produces a **signed activation-intent record** (typed: hook path, predicate summary, test result, diff of effective policy before/after, rollback one-liner); the human ratifies a **batch** with one act, in the shape `gate-manifest.sh sign` already implements (expiry + scope + IDL audit, `:98-120`) — extending the existing typed-delegation machinery to a class it currently excludes by construction, without agent self-signing. Plus a **fail-closed conformance test**: landed hook + green tests + absent from all 5 settings ⇒ CI red. |
| **Confidence** | **High** on the mechanism and the empirical instances; **medium** on whether batched-diff consent genuinely preserves invariant 6 — that is precisely the question worth frontier adjudication. |

### F4 — L3 adjudicates infra actions against a **world model of a different project**

`autoMode.environment` (7 entries) describes reso: Turso/libSQL, Replicache, Amplify Oregon, Fly.io LAX/SIN, `*.reso.gl`, SSM Parameter Store. `soft_deny` #28 (Turso DDL) and #29 (Replicache mutation parallelization) are reso **application** rules. Nothing describes the 4-account org, the desk, worktree isolation, the ship rail, handoff-fire spawning, `launchctl` activation, account rotation, or C1..C10. So when the classifier adjudicates a claude-infrastructure action — spawn a teammate, fire a handoff, rotate an account, land via `/ship` — it has **no environment model to reason from**, and falls back to generic priors. **Solution shape:** `environment` becomes a compiled projection of the same SSOT as F1, per-repo. **Confidence: high** (direct read); **frontier-adjacent** — real, but the fix is mechanical once F1's SSOT exists.

---

## 3. Formalizability verdict (sub-question b)

**Yes — and it is the generator-class item.** One typed SSOT over `{capability grants, escalation surfaces, standing directives (scope+expiry), C-class rulings}` compiling to the 5 (really 6) settings files + hook predicates + conformance tests **dissolves F1, F3, F4, and the entire deny-floor gap list at once**.

**What is genuinely hard, precisely:**

- **State-dependent predicates.** `clean tree ⇒ reflog-reversible` and `cwd IS a sanctioned worktree` are *not* compilable to L1 — the static array has no state. They compile only to L2 hooks, which is why `desk-anti-hitl-2026-07-19.md` Part B §1 is right that the hook must check state **atomically with the decision** (keystrokes cannot). So the SSOT must emit **two different target languages** — pure shape-matching for L1, state predicates for L2 — from one source, with a proof obligation that L1's emission never *widens* past L2's.
- **The precedence inversion is a compile-time obligation, not a lint.** Because allow is terminal, every emitted `allow` rule must carry a proof that it cannot reach a C10 surface. `Bash(tee:*)` and `Bash(python3:*)` are the counterexamples that make this non-trivial: these are *capability-universal* verbs. The compiler must either refuse them or force them through an argv-parsing L2 hook. **This is the hard core of the whole axis.**
- **Identity predicates need a trust root.** "cwd IS a sanctioned worktree" is checked by the same process that could be compromised. Tractable (the harness supplies `cwd` in the hook payload) but must be stated.

**Delegation formalism (sub-question d).** Two systems exist, and the **higher-risk one is the informal one**:

| | typed | scope | expiry | revocation | audit |
|---|---|---|---|---|---|
| C1..C10 manifests (`gate-manifest.sh`) | JSON | wave | **yes** (`manifest_active()`) | expiry | IDL |
| Standing grants (`./.claude/CLAUDE.md:18-27` standing-land; `~/.claude/CLAUDE.md:230-247` Follow-On Gate F1-F4) | **prose** | prose ("this repo only") | **none** | none | none |

Standing-land authorizes **pushing to trunk** — the C9 act — under a prose grant with no expiry and no revocation record, while the typed system permanently excludes C9. A principled record: `{grantor, verbatim_quote, granted_capabilities[], scope{repo,branch,path}, conditions[], expiry, revocation_ref, issued_at}` — machine-readable, consumed by the same predicate compiler, surfaced on `cc-blockers`.

---

## 4. Deny-floor gaps (sub-question e) — patch vs structural

| Gap | Status | Class |
|---|---|---|
| `Bash(tee:*)` → C10 write | **live, unguarded** | **STRUCTURAL** (F1) |
| `Bash(python3:*)`, `Bash(find:*)` → arbitrary exec | live | **STRUCTURAL** (capability-vs-shape) |
| `git push origin +HEAD:main` (plus-refspec force) | no deny token, `validate-bash.sh` silent | **patch** (+ structural: no test) |
| `--force-with-lease` | **contested** — `Bash(git push --force:*)` is a *prefix*, so it plausibly DOES match; `desk-anti-hitl` Part B §4 claims it does not. **No test exists either way** | **STRUCTURAL** (unknown deny-floor is the defect) |
| `--dangerously-skip-permissions` | L3 prose only (`settings.json:986` soft_deny #11); allow-terminal means any allow-listed launcher bypasses | **STRUCTURAL** |
| `git -C <path> push` evades `Bash(git push:*)` prefix | L3-only coverage | **patch** |
| `Bash(eval:*)`/`Bash(exec:*)` deny bare shapes only | live | **patch** (subsumed by capability-shaping) |
| `.claude/settings.local.json` unmirrored, +32 allow incl. `Bash(python3 -)` | live | **patch** (extend mirror sha to project layer) |
| `git push:*` ask still strands autonomous ship (G-P15-3 **UNRESOLVED**) | 9d2bf16 landed, **not live** | **patch** (run the staged activator) — blocked by F3 |

---

## 5. NOT-frontier + routing

- **Run `pending-activation/05-ship-rail-push-allow-activate.sh`** → operator, silver-platter. Resolves the Zero-HITL-DoD ↔ `git push:*` contradiction immediately.
- **`git ff-sync` the 6-commit deploy lag** → operator (desk cannot ff the shared checkout).
- **Dedupe `Stop`/`Notification` double-fired hooks** → routine task; extends 23d2597.
- **Add `+refspec` / `git -C … push` / `--force-with-lease` explicit deny rules + bats** → routine, one teammate.
- **Mirror-sha the project `settings.local.json`** → routine; extend `config-mirror-assert.sh`.
- **`cc-classify` recognition of the classifier-outage string** → routine, high value, unblocks S-0 detection independent of F2.

## 6. Could not determine

- **Exact CC matcher semantics** for `Bash(git push --force:*)` vs `--force-with-lease`, and whether `allow` is *provably* terminal vs. classifier-consulted-anyway. Both need a **live harness probe**, not a file read; the precedence conclusion is 4/4 empirical correlation plus documented ordering. A controlled probe is the single highest-value follow-up and would firm F1/F2 from medium-high to high.
- **Whether the `tee`→hook→exec chain actually executes** — not tested (read-only brief). Each link verified independently; the composition is inferred.
- **Why the three hooks were never symlinked** — `install.sh:89` globs `hooks/*.sh` and would link them, so `install.sh` simply has not been re-run since 9d2bf16. Not confirmed against install logs.
- **Whether any *other* live session widened permissions at runtime** — `.claude.json` (120 KB) not parsed for per-project permission state.
