# AXIS 6 — Verification & Landing: claim→ground-truth

**Verdict.** The landing half of this axis is *genuinely solved* — every P9 gap is closed as code with correct RED-proofs. The completeness half is *structurally open, and worse than a19 left it*: the mechanism built to close D-1/D-5 (`completion-assert`) reads a ground-truth field **that no producer in the repo populates**. It has fired 6 times in production; all 6 were `git status` facts; **zero** were completeness facts. The asymmetry is the finding: verification succeeded exactly where truth is machine-enumerable (git objects, path presence, byte-identity) and failed exactly where it requires interpreting an English scope line.

## (1) Claim→truth map as-of-today

| Claim class | Independent evidence today | Still self-report | File:line |
|---|---|---|---|
| **landed** | ✅ Full. Per-path `ls-tree` presence + `git diff` byte-identity vs trunk, inside the locked child, with bounded auto-retry + rollback | none | `land-verify.sh:52-81`; called `ship-land.sh:224` |
| **land was serialized** | ✅ Mutex keyed on `--git-common-dir` → all worktrees of a repo collide on one lock | none | `land-lock.sh:42-48` |
| **land was attested** | ✅ `land.log` now carries `verify/sweep/esc_scan/exit` | none | `ship-land.sh:104-110` (closes G-P9-10) |
| **nothing stranded** | ✅ `--mine=<sid>` makes ownership machine-decidable (REVIEW→pass/fail) | operator ruling on peer WIP | `stranded-sweep.sh:15-21,40` (closes G-P9-5) |
| **tests-green** | ⚠️ Partial. `gate-green` now has a real producer, but the marker lives at `--git-common-dir` = **one global slot shared by all worktrees**; last lander wins → every other worktree reads `stale` | which tests ran | `ship-land.sh:192,256`; `wrap-ledger.sh:79-84`. Live: marker `6488617` vs HEAD `4052d02` = **STALE** |
| **uncommitted work remains** | ✅ `git status --porcelain` | none | `wrap-ledger.sh:64-66` |
| **committed-but-unlanded** | ✅ `git cherry` content-absence, not `rev-list` count (the dfacccd lesson, as code) | none | `wrap-ledger.sh:69-76` |
| **engaged / alive** | ✅ Grounding triad: transcript last-assistant-turn + `cc-sessions` sid→pane + HEAD vs *fixed* witnessed ref | why it's alive | `desk-assert:56-95` |
| **DoD survives compaction** | ✅ PreCompact capture + SessionStart re-injection, incl. `Scope (grown):` | summarizer fidelity | `dod-persist.sh:107-138`; wired in **all 5** config dirs (a19's asymmetry **closed**) |
| **done / scope-complete** | ❌ **NONE.** The remainder leg is inert (below) | **everything** | `wrap-ledger.sh:97` |
| **evidence untampered** | ❌ Chain covers **3.3%**; `verify` exits 0 saying "OK" | 96.7% of records | `cc-idl:11-17` |
| **value-delivered** | ❌ no mechanism on this axis | all | — |

## (2) The central defect: the completeness leg reads a field nothing writes

- **Consumer**: `wrap-ledger.sh:97` computes `REMAINDER` = count of unchecked markdown checkboxes `^[[:space:]]*[-*][[:space:]]+\[[[:space:]]\]` in the DoD file.
- **Producer**: `dod-persist.sh:76` (`persist_dod`) writes `## <ts> (<source>)\n<prose>\n\n` where prose is a `Scope (frozen): …` sentence. **Never a checkbox.**
- **Airtight**: the only `- [ ]` writers in the repo are `hooks/lib/task-helpers.sh:143` (task summaries) and `commands/pr.md` (a PR template). Neither writes to a DoD path.
- **Live proof**: both DoD files on disk have **0** unchecked items. `wrap-ledger.sh --machine` in the shared checkout returns `DOD=present REMAINDER=0` against a DoD whose newest capture enumerates ~13 open operator actions and 3 in-flight tracks.
- **Empirical proof**: all 6 lifetime `completion-assert` fires — `dirty tree` ×5, `unlanded` ×1. Plus **107 `abstained | ledger-clean`** — 107 done-assertions waved through with completeness never evaluated.

⇒ `completion-assert` reduces to `(close-phrase) ∧ (dirty ∨ unlanded) ∧ ¬genuine`. Its own header (`:2-11`) claims to catch "the CONFIDENT / TELL-FREE false-done… a19 D-1/D-5". **It catches neither in their load-bearing form** — the dangerous variant is *clean tree, landed, 3-of-5 items done*, which is the `ledger-clean` abstain path.

**Why the tests are green while production is blind — fixture-shape-parity, violated in the stack that most needs it.** `tests/wrap-ledger.bats:65` and the D-5 RED-proof `tests/completion-assert.bats:71` both **hand-write** `- [ ] item` fixtures in a shape no producer emits. The single producer↔consumer contract test, `tests/dod-persist.bats:120`, asserts only `DOD=present` — it proves **path** parity and never **shape** parity, while its header claims the contract is "proven end to end." This is precisely the law in memory (*fixture-shape-parity*, learned 2026-07-19 on cc-dispatch 7/7). The law was applied *correctly* to the landing rail — `tests/land-lock.bats:72-95` deliberately un-sets `LAND_LOCK_DIR` to exercise real keying — and *not at all* to the completeness stack.

## (3) a19 D-1..D-12 re-run against today's wiring

| ID | Today | Basis |
|---|---|---|
| D-1 confident false-done | **PARTIAL** — fires iff dirty∨unlanded; **escapes** clean+landed | 6/6 fires were git-hygiene |
| D-2 manufactured value-fork | **ESCAPES** — `which (do you\|would you)…prefer` still buys abstain | `completion-assert.sh:77-78` |
| D-3 spurious C10 | **NARROWED** — ship/land explicitly de-listed from `GENUINE`; credential/sudo/migration still buy silence | `:76-78`; 7 `genuine-blocker` abstains |
| D-4 paraphrase past cap | **ESCAPES** — cap 3, +5 `capped:3>=3` abstains observed | `:115` |
| D-5 codename-buried remainder | **ESCAPES** — this is *exactly* the dead REMAINDER leg | `:103`, `wrap-ledger.sh:97` |
| D-6 rotted model never arms | **ESCAPES (structural centre, unchanged)** — `completion-assert` is model-independent but its only completeness input is model-authored | — |
| D-7 cap exhaustion, no re-arm | **OPEN** | `session-continue.sh` unchanged |
| D-8 stale sentinel vs kill-switch | **OPEN** | unchanged |
| D-9 DoD dies at handoff bridge | **MOSTLY CLOSED** — durable file + SessionStart re-injection, all 5 dirs; residual: DoD is keyed per-worktree-toplevel, so a handoff into a *new* worktree starts with an empty DoD | `dod-persist.sh:33-40` |
| D-10 tool-blind `/goal` | **OPEN** — no tool-using judge landed | — |
| D-11 >4000-char dead fire | **CLOSED** — `payload-lint` pre-fire + empty-prompt reject | `09a41f1`, `e5bf662` |
| D-12 DoD evaporates at auto-compact | **CLOSED** | `dod-persist.sh:118-138` |

**Delta vs p06's thesis** ("Done judgment lives entirely in the model at every layer; `/wrap` does not exist"): `/wrap` now exists and computes 2 of 3 legs from real facts — but the third leg is the only one that answers p06's actual question. **p06's thesis survives intact in its load-bearing form.**

## (4) Frontier rows (ranked)

| # | Problem | Evidence | Why default-tier insufficient | Solution-shape | Conf |
|---|---|---|---|---|---|
| **F1** | **Compiling an English scope into machine-checkable assertions without the compiler being the compromised model.** Every ground-truth mechanism here works on machine-enumerable facts; "did the work meet the ask" has no such representation, so the stack silently substitutes git hygiene for completeness. | Producer/consumer mismatch above; 6/6 fires git-only; 107 `ledger-clean` waves | Default tier *builds the mechanism and mistakes it for the property* — that is literally what happened: a hook whose header cites D-1/D-5, whose tests are green, and which cannot see either. This is generator-class: it dissolves D-1, D-5, D-6, D-10 at once, and no amount of "fix the regex" reaches it. The hard part is not code, it is **who authors the assertions and how their adequacy is checked** — a self-referential design problem | Extend `cc-backlog`'s append-only per-item ledger (`bin/cc-backlog:95-106`, already `id/title/dodRef/status`-folded) with a per-item **`--assert "<cmd>"`**; `wrap-ledger` computes `REMAINDER` from *failing assertions*, not checkboxes. Enforce with the pattern this repo already invented for operator gates: `cc-blockers --lint` is fail-closed on "a mechanical gate surfaced as prose is a defect" — apply verbatim to DoD items. Author-of-assertion ≠ executor-of-work (fresh-context judge writes the asserts at intake, before rot) | **High** |
| **F2** | **The verification recursion terminates in attenuation, not a fixpoint.** Each layer up has strictly weaker actuation than the one below, so the top layer actuates nothing. | L0 gate → blocks a land (strong). L1 `nightly-regression` → ran **once**, `RED (7)` incl. `bats:tests`, `gate-manifest --selftest`; no re-run, no escalation (`~/.claude/autonomy/regression.log`, single line, 2026-07-19T11:07:22Z; launchd `com.claude.nightly-regression` last exit 1). L2 `cc-audit` → **zero consumers** (grep: only comment-mentions in 5 hooks) despite its header "so a gate/sweep/nightly can branch on it". L3 chain → advisory only | This is the invariant-1 extension eating its own tail, and it has a *design* answer, not a patch answer: naive recursion is infinite. Default tier keeps adding an (N+1)th verifier — the repo now has **two divergent D9 implementations**. The question "what makes a verification stack terminate soundly" is a proof-shaped question | Principled fixpoint: a layer may only be added if it **actuates at the same strength as the layer below** (blocks, not logs). Otherwise fold it into the layer below. Concretely: `nightly RED` must open a `cc-decide` packet with `--run`, not append a log line — the repo's own Silver-Platter law, applied to its verifiers | **High** |
| **F3** | **Evidence-integrity theater.** `cc-idl verify` prints `OK … intact` and **exits 0** while covering 3.3% of the record. | 6,910 sealed / 206,524 lines; chain mtime `Jul 19 01:55`, IDL `Jul 20 00:44`; **no scheduled/hooked caller of `cc-idl seal` exists anywhere** (grep over `scripts/ hooks/ bin/ LaunchAgents`) | The failure mode is the exact one `cc-idl`'s own header describes and `cc-audit`'s header calls "the inert-detector trap this layer exists to kill, applied to itself" — reproduced one level up, undetected. Recognizing that a *tamper-evidence* layer has become the thing it detects is an unknown-unknown; the code is correct, the wiring is absent, and the output is reassuring | `verify` must exit non-zero (or report `PARTIAL`) when `unsealed/total` exceeds a threshold — coverage is part of the verdict, never a footnote. Add the missing sealer to the nightly. Note the residual `cc-idl:15-17` already admits: delete-chain-and-reseal is only caught by an independent head-witness that **is not implemented** | **High** |
| **F4** | **A known, written law gets applied unevenly across subsystems, and nothing detects the omission.** Fixture-shape-parity is in memory, was applied *correctly* to `land-lock.bats:72-95`, and *not at all* to the completeness stack — where its violation is load-bearing. | Contrast `tests/land-lock.bats:76` (`unset LAND_LOCK_DIR`, real keying) vs `tests/dod-persist.bats:120` (asserts `DOD=present` only) | Meta-level: the failure is not in any artifact but in **law-propagation across a codebase**. Default tier verifies artifacts against laws it is pointed at; nobody is pointed at "which subsystems has law L *not* reached?" This generates F1's specific mechanism and will generate the next one | A law-coverage sweep: for each durable law in memory, enumerate the subsystems it *should* bind and assert a witness test in each. Fail-closed on unwitnessed subsystems | **Med-High** |

## (5) NOT frontier — routing

| Item | Route |
|---|---|
| `REMAINDER` regex/producer mismatch **as a patch** (make `dod-persist` emit checkboxes, or `wrap-ledger` parse prose) | Agent Teams, 1 teammate, ~60 LOC + a producer-literal bats test. **Do this now** — it is the cheap 80% while F1's assertion model is designed. Do **not** let it close F1 |
| Missing `cc-idl seal` caller in the nightly | Agent Teams, trivial |
| `cc-audit` alarm predicate diverging from the canonical `idl-abstain-alarm.sh` blind/dormant classification, despite a "kept in lockstep, can never disagree" header claim (`cc-audit:10-13`; `grep -c actor` = 1, comment only) | Agent Teams. **Live divergence**: `cc-audit abstain` exits 6 ALARMing `waiting-recycle` (100%/4178, shadow-default = healthy-dormant), while `idl-abstain-alarm` correctly logs `inert=0 dormant100=…`. Harmless today only because `cc-audit` has no consumer — wiring it as-is installs a nightly false RED |
| `cc-audit wave` = `FAIL` in steady state (`unplanned=2`, `orphaned-intent=4`); 2 of the 4 zeros `UNPROVEN` (basis=0) since P2/P5 never landed | Backlog. Flag: a gate red in steady state cannot distinguish newly-broken from always-broken |
| `nightly-regression` RED(7) triage | Agent Teams, per-check |
| `gate-green` single-slot collision across worktrees | Backlog, P2 — fails toward false-🔧 (safe direction, but trains rung-blindness) |
| `task-quality-gate.sh:25` `[ -z "$TEAM_NAME" ] && exit 0` — desk work still bypasses entirely (a19 finding, unchanged) | Backlog |
| D-2/D-4/D-7/D-8 (value-fork carve-out, cap, no-re-arm, kill-switch inversion) | Backlog — mechanical, all identified |

## (6) Could-not-determine

- Whether `nightly-regression` **failed to run** at 04:00 today or ran and failed before logging. `launchctl list` shows last exit 1; only one log line exists. Needs stderr-log inspection I did not run (read-only budget).
- Whether the 5 `capped:3>=3` abstains masked true-positives — would require correlating each with the tree state at that moment.
- Whether `abecaad` (arm-by-default for monitoring desks) has changed `waiting-recycle`'s dormancy class since the last `idl-abstain-alarm` run (2026-07-19T11:03).

## (7) Axis-8 overlap — flagged, not duplicated

Axis 8 owns worker-content→actuation trust. My boundary: I own **artifact/claim** trust. Two genuine seams, both yours-not-mine:

1. **`dodRef` is a pointer, not content.** `cc-backlog` items carry `dodRef` → a plan path (`bin/cc-backlog:95`). Whether a *worker* honored that DoD is axis 8; whether the *ledger* can check it is F1 above. If you propose per-item acceptance criteria from the worker side, F1's `--assert` field is the same object — **coordinate, or we'll build two.**
2. **Claim-clean vs work-clean.** My rail proves bytes reached the trunk; it cannot prove the bytes were the *right* bytes. `ship-land`'s gate runs `bats tests/` (`:151-154`) — so a worker who lands green tests that assert the wrong shape (the F4 class) passes my rail completely. That handoff is exactly where our axes meet.
