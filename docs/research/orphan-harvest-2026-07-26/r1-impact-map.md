# r1-impact-map  (session 27ffbc7c-e8aa-4cdf-8414-cb92d66d7e9e)

Harvested 2026-07-26 from disk after lead a3f68174 self-closed leaving this teammate orphaned.
Last assistant turn: 2026-07-25T22:30:52.287Z
Total records: 307

---


## turn @ 2026-07-25T22:30:52.287Z

## Land-gate test selection — empirical feasibility study

Repo: `claude-infrastructure` @ `f0cfa8c` (analysis tree; `origin/main` = `e2a1def`, 2 commits ahead → 118 suites). All numbers derived from the checkout, not estimated. Read-only: no edits, no commits; the only execution was `bats --timing tests/deploy-parity.bats tests/gate-manifest.bats` (both documented-hermetic) to calibrate a per-test cost constant.

**Verdict up front: FEASIBLE-CONSERVATIVE.** The prior doc's rejection ("tests read docs too") is measurably wrong as stated — every real prose file a suite reads is named by a *literal repo-relative path string* inside the suite, so prose coupling is fully greppable. The real soundness threat is elsewhere (transitive `source`/exec chains ≥2 hops, and cross-suite host-state pollution), and both are addressable.

---

## 1. Naming-convention coverage

117 suites at analysis HEAD; 1579 `@test`s; 19,206 LOC of bats.

| Match class | Count | % |
|---|---|---|
| Exact 1:1 (`tests/X.bats` ↔ `scripts/X.sh` \| `bin/X` \| `hooks/X.sh` \| `hooks/lib/X.sh` \| `lib/X.sh` \| `commands/X.md`) | 79 | 67.5% |
| Longest-prefix trim (`handoff-fire-focus`→`scripts/handoff-fire.sh`; `lr-reset-poller-consolidate`→`scripts/limit-recover/lr-reset-poller.sh`; `desk-brief-ssot`→`commands/desk.md`) | +24 | 88.0% cum. |
| Suffix-extend (`deploy-parity`→`scripts/deploy-parity-assert.sh`, `effort-parity`, `settings-drift`, `power-policy`→`-verify.sh`, `plan-index`→`hooks/plan-index-update.sh`) | +5 | **92.3% cum.** |
| **No source-name counterpart at all** | **9** | 7.7% |

The 9 unnamed are all cross-cutting/integration suites, i.e. exactly the ones a naming map *should* fail on: `comms-drain-activate`, `fire-autonomy`, `fire-engagement`, `install-wire-hooks`, `land-gate-cas`, `lr-team-audit`, `mail-ack-consume`, `mailbox-forward`, `session-registry`. Every one of them is still reachable by the **literal-path** rule (each names its SUTs inline).

Naming alone is not the rule; it is one of five clauses below.

---

## 2. What suites actually read/execute (sample of 25+ hand-read)

Mechanical extraction across all 117 suites: **317 (suite, literal-path) references**, **137 unique existing repo paths**. Minimum 1 real ref/suite (excluding the `#!/usr/bin/env` false positive) — **no suite is path-dynamic**.

Four structural patterns, hand-verified:

**(a) Thin `--selftest` wrappers.** `tests/lead-supervisor.bats:9-11` sets `SUP="$REPO/scripts/lead-supervisor.sh"` and every test is `run bash "$SUP" --selftest` + a `grep -q 'T22b SAME-SWEEP GUARD'` on the output. The real coverage lives in `scripts/supervisor-e2e.sh` — which the bats names only in a **header comment** (line 2). A whole-file grep (comments included) is therefore load-bearing, not incidental. Same shape: `wait-contract-lint`, `settings-drift`, `effort-parity`, `cc-upgrade-gate`.

**(b) Fully hermetic fixture drivers.** `tests/deploy-parity.bats:13-26` builds a fake repo+bindir in `BATS_TEST_TMPDIR` and drives via `CC_PARITY_REPO`/`_BINDIR`/`_STRICT`/`_COPY`. `tests/cc-notify.bats:12-38` isolates via `CC_REGISTRY_DIR`/`CC_MAILBOX_DIR` + an `IT2_BIN` stub. These touch exactly one repo file: the SUT.

**(c) Cross-file *content* assertions** — the dangerous class. Only 4 suites, 8 sites, all literal:

| Suite | Asserts on | Line |
|---|---|---|
| `desk-brief-ssot` | `docs/templates/desk-boot-brief.md` prose (**incl. a negative** `! grep -qE "re-arm the .*cadence Monitor"`) | :33-37, :57-58 |
| `desk-brief-ssot` | that `scripts/desk-invariant.sh`, `hooks/desk-brief-inject.sh`, `lib/desk.zsh`, `commands/desk.md` each contain the SSOT path | :39-50 |
| `desk-assert-wiring` | `docs/activation/wiring-all.sh` contains `desk-assert`; `desk-boot-brief.md` contains `desk-assert <sid` + `--witnessed-ref` | :33, :49-58 |
| `fire-engagement` | `bin/cc-dispatch` contains the literal string `cc-backlog item $id (project $PROJECT)` | :148 |
| `reap-guard` | `hooks/teammate-auto-shutdown.sh` matches `decide .*--session-id "$SESSION_ID"` | :105 |

**(d) Directory-glob / inventory coupling.** `tests/install-wire-hooks.bats:69-88` runs `install.sh --config-dir <tmp>` then iterates `for f in "$REPO"/scripts/limit-recover/*` asserting each was deployed. `install.sh` globs `hooks/*.sh`(:89), `hooks/lib/*.sh`(:93), `commands/*.md`(:102), `scripts/*.sh`(:148), `scripts/limit-recover/*`(:170), `skills/*/`(:193), `bin/cc-*`(:256), `launchd/*.plist`. **A brand-new file matching one of those globs is coupled to a suite that never names it** — this requires an explicit glob clause, not a grep.

Verified NOT a risk: `payload-lint`, `pane-id-lint`, `wait-contract-lint`, `reaper-horizon-lint` all sweep `BATS_TEST_TMPDIR` fixtures, never the real repo. Only 2 suites do any `grep -r` and both target a temp dir.

---

## 3. Reverse-map density + the docs-reading list

**Reverse map (fan-in over depth-2 exec closure), top hot files:**

| Fan-in | File | Nature |
|---|---|---|
| 71/117 | `bin/cc-sessions` | PATH-resolved by ~everything |
| 70/117 | `hooks/lib/mailbox-pending.sh` | sourced by cc-notify/cc-await-ping/mailbox-drain |
| 69/117 | `bin/cc-await-ping` | |
| 66/117 | `scripts/push-send.sh` | invoked by `bin/cc-notify:214` |
| 66/117 | `bin/cc-notify` | the comms hub |
| 52/117 | `hooks/lib/context-econ.sh` | |
| 49/117 | `install.sh`, `accounts.json`, `statusline.sh` | deploy hubs |

But the *selection* fan-out under the proposed rule is far tighter than raw closure fan-in, because most closure edges are comment mentions:

**Per-file fan-out (how many suites ONE changed file selects), over all 390 tracked non-test files:** `min=0 p50=4 p75=7 p90=11 p99=39 max=114`. Only **4 files** are token-pathological (generic basename): `scripts/plan-phase-scan-tests/run.sh` (stem `run` → 114), `lib/desk.zsh`+`commands/desk.md` (stem `desk` → 28 — arguably honest), `commands/commit.md` (28). A 5-word stoplist (`run, common, main, test, commit`) fixes it.

**The docs-reading suite list (the prior doc's objection, measured).** 13 suites textually reference a `docs/`/`commands/` path. Of those, only **9 real repo prose/config files** are actually read (the rest — `docs/plans/done.md`, `p.md`, `x.md`, … — are fixtures created inside `BATS_TEST_TMPDIR`):

| Real prose/doc file read | Read by |
|---|---|
| `docs/templates/desk-boot-brief.md` | `desk-brief-ssot`, `desk-assert-wiring` |
| `commands/desk.md` | `desk-brief-ssot` |
| `commands/limit-recover.md` | `claude-accounts-core`, `cc-unattended-ask-guard` |
| `docs/activation/wiring-all.sh` | `desk-assert-wiring`, `install-wire-hooks` |
| `docs/activation/pending-activation/07-comms-drain-activate.sh` | `comms-drain-activate` |
| `docs/activation/pending-activation/08-session-deregister-activate.sh` | `cc-reconcile` |
| `docs/research/desk-anti-hitl-2026-07-19.md` | `handoff-fire-focus` |
| `docs/plans/SESSION_SPRAWL_CONSOLIDATION_PLAN.md` | `lr-select` |
| `settings-templates/settings.example.json` | `cc-reconcile`, `cc-unattended-ask-guard`, `comms-drain-activate` |

`README.md` appears only as fixture content (`echo base > README.md` in `task-quality-gate`'s temp git repo). No suite reads the repo's own `CLAUDE.md`.

**Decisive measurement**: grepping every suite for dynamic doc-path construction (`$VAR/docs`, computed `.md` names outside `BATS_TEST_TMPDIR`) returns **zero** hits against real repo files. Every one of the 9 is reached via a literal string. So *"tests read docs too"* is true but **not** an obstacle — it is exactly greppable. A prose file selects precisely the suites that name it; unnamed `docs/**.md` is provably inert.

---

## 4. Fifty-land simulation

Rule as implemented (see §6 for pseudocode). Per-land time modelled as `0.195 s × n_tests + Σ literal sleeps` — calibrated on the 41-test hermetic run (8.03 s wall ⇒ 0.196 s/test) and **independently validated**: the model totals **899 s = 15.0 min** for the full suite, matching the brief's stated ~15 min.

**Distribution over the last 50 commits on `origin/main`:**

| Suites selected | Lands | Notes |
|---|---|---|
| **0** | 6 | pure `docs/research/**` + `docs/SAFEGUARD_*.md` commits — provably inert |
| **1–5** | 12 | |
| **6–20** | 19 | |
| **21–50** | 12 | `cc-reaper` / `cc-classify` / `handoff-fire` hub changes |
| **51–116** | 0 | |
| **FULL (117)** | **1** | `f0cfa8c` (`bin/claude-bump-models` — zero test coverage ⇒ fail-closed) |

| Metric | Selected | Full-always | Skip |
|---|---|---|---|
| suite-runs (50 lands) | 653 | 5,850 | **88.8 %** |
| test-runs | 9,610 | 78,950 | **87.8 %** |
| modelled gate seconds | 7,802 | 44,925 | **82.6 %** |
| **median land** | **8 suites · 106 tests · 31 s** | 117 · 1579 · 899 s | — |
| p90 land | — | — | 339 s |

Two suites hold 49 % of total gate time (`cc-reaper` 255 s, `desk-invariant` 182 s — both sleep-heavy), so any `bin/cc-reaper` land still pays ~5 min. That is the honest ceiling, not a defect of the map.

**Depth sensitivity** (closure depth is the one free parameter):

| closure depth | median land | p90 | suite-skip | test-skip | **time-skip** | `push-send.sh` selects |
|---|---|---|---|---|---|---|
| 2 | 31 s | 339 s | 88.8 % | 87.8 % | 82.6 % | 23 suites |
| 3 | 39 s | 568 s | 84.2 % | 82.3 % | 75.9 % | 49 |
| 4 | 213 s | 575 s | 81.9 % | 79.4 % | 72.5 % | 62 |
| **6 (≈ fixpoint)** | **264 s** | 589 s | 76.7 % | 73.6 % | **65.5 %** | 68 |

**Recommendation: run the closure to fixpoint (depth 6).** It removes the depth-cut judgment entirely, still saves **65 % of gate wall-clock**, and cuts the median land from 15 min to 4.4 min. Depth 2's extra 17 points are bought with an unquantifiable soundness bet (see §5, risk R1).

**Recall validation.** Over all 551 commits of history, 237 commits co-changed a source file and a suite (a developer-attested coupling). Feeding the rule **only the non-test files**, it selected the co-changed suite in **237/237 (100 %)**. Restricting to the 26 *non-obvious* pairs (suite name ≠ any changed file's name — e.g. `skills/cc-upgrade-gate/SKILL.md` → `tests/cc-upgrade-gate.bats`): **26/26 (100 %)**.

**Ablation** (which clause carries the recall):

| Rule minus… | recall | 50-land suite-skip |
|---|---|---|
| — (full rule) | 100.00 % | 88.8 % |
| exec-closure | 100.00 %\* | 91.7 % |
| basename-token | 99.58 % | 89.8 % |
| naming-match | 99.16 % | 88.9 % |
| package-dir | 100.00 % | 85.2 % |
| install-glob | 100.00 % | 89.3 % |

\* The co-change oracle **cannot see** the closure's contribution, because the commits that changed `hooks/lib/cc-interactive.sh` also changed `bin/cc-classify` (its only caller). Direct probe: `{hooks/lib/cc-interactive.sh}` alone selects `cc-classify` **only via the closure** — drop it and `tests/cc-classify.bats` (52 tests) is silently skipped. Keep the closure.

**Behaviour on deletions / renames / new files** (spot-tested against real historical deletions):

| Change | Selection |
|---|---|
| delete `scripts/watch-getAppState-fix.sh` | 4 suites |
| delete `hooks/concurrent-writer-guard.sh` + `hooks/reso-writer-lock.py` | **FULL** (one is unmapped ⇒ fail-closed) |
| rename `hooks/lib/mailbox-pending.sh` (del+add) | 39 suites |
| brand-new `bin/cc-brandnew` | 4 suites (install-glob only) — a fail-**open** edge, see R5 |

---

## 5. Residual risk classes the rule cannot catch

**R1 — Deep transitive execution (≥3 hops) [PRIMARY, quantified].** `bin/cc-notify:214` invokes `scripts/push-send.sh`. Enumerating real 3-hop chains gives ~60 `suite → SUT → mid → push-send.sh` paths. At depth 2 the rule selects 23 of them and **skips**: `lead-supervisor.bats → scripts/lead-supervisor.sh → bin/cc-notify → push-send.sh`; `mailbox-drain.bats → hooks/mailbox-drain.sh → bin/cc-notify → push-send.sh`; `session-continue.bats → hooks/session-continue.sh → bin/cc-notify → push-send.sh`; `team-orphan-reaper`, `fire-engagement`, `cc-backlog`, `desk-land`, … *Mitigation: run to fixpoint (68/68 selected).* Cost: 82.6 %→65.5 % time-skip. **Take the trade.**

**R2 — Unresolvable relative `source` paths.** `hooks/validate-bash.sh:24-27` does `LIB_DIR="$(dirname …)/lib"; source "$LIB_DIR/is-true-flag.sh"` — the only textual trace is `lib/is-true-flag.sh` (via a shellcheck directive), which does **not** resolve to the real `hooks/lib/is-true-flag.sh`. Any graph built by string-matching repo-relative paths loses this edge. Latent today (no suite covers `validate-bash.sh`), but it is a live class: the same shape exists in `hooks/session-index-start.sh:12`, `hooks/operator-readout.sh:276`, `hooks/mailbox-drain.sh:28` — those three happen to also carry a fully-qualified fallback line (`…/hooks/lib/X.sh`) that rescues the match. *Mitigation: a `shellcheck source=` + `$LIB_DIR` resolver pass, or a lint requiring every `source` to have one fully-qualified sibling literal.*

**R3 — Cross-suite / host-state pollution (non-compositionality).** This one is **documented in-repo**: commit `7791209` — *"the suite left arm/live/brief markers in the REAL state dir whose recorded cwd was a defunct /var/folders/…bats-run tmpdir… `desk-recycle-durable.bats` setup now exports a fixture HOME so a forgotten [override doesn't leak]"* — and shipped `gc_bats_pollution()` in `hooks/waiting-recycle.sh:72`. Only **6 of 117 suites** export a fixture `HOME`; 39 reference `$HOME`/`~/.claude`; **10 set no isolation at all** (`agent-teams-enforce`, `boot-resume-launch`, `cc-unattended-ask-guard`, `desk-assert-wiring`, `gate-classify`, `handoff-fire-tab-window-typing`, `lead-supervisor`, `reset-hard-shadow-allow`, `rm-safe-allowlist`, `ship-rail-push-allow`). Consequence: **a subset run is not guaranteed to reproduce the full run's verdict in either direction** — a skipped polluter can turn a victim green (false green) or a skipped setup-provider can turn a victim red (false red / new flake class). This is orthogonal to the map and would bite `bats --jobs` too. *Mitigation: a hermeticity lint (every suite must export a fixture `HOME` + its SUT's state-dir override) before enabling selection; it is a 6→117 gap, i.e. real work.*

**R4 — Inductive trunk-greenness under the CAS re-gate.** `scripts/ship-land.sh:217` gates `GATE_BASE..HEAD` — *our* delta only. Today's full-bats run makes trunk's greenness unconditional. Under selection, "trunk is green" becomes an induction whose base case is each previous lander's *scoped* gate. The prior doc's argument (green(ours@old base) ∧ green(theirs) ⇏ green(rebased)) still stands, and now compounds across lands. *Mitigation: a nightly/`--full` unscoped run as the induction re-base; the existing `nightly-regression.sh` is the natural host.*

**R5 — New-file fail-open via the glob clause.** A brand-new `bin/cc-brandnew` maps to 4 suites (install-glob) instead of `unmapped→FULL`. Harmless for *breaking* existing suites, but it means the glob clause converts a fail-closed into a weak-mapped. *Mitigation: evaluate the glob clause only for files present in the pre-change tree; new paths stay `unmapped→FULL`.*

**R6 — Host-state-only RED.** `tests/effort-parity.bats:101-105` runs `effort-parity-assert.sh` against the **real** host with all fixtures unset. (Checked: it accepts exit 0 **or** 1, so it asserts *assertability*, not the floor — the drift-detection loss is smaller than it first looks, but the class is real: a suite whose RED trigger is host state can never be selected by a repo-changed-path map.)

**Oracle limitation (state plainly to the lead).** Co-change recall is a *developer-attestation* oracle, not an execution oracle: it proves the rule selects the suite the author edited, not that it selects every suite that would go RED. The only settling experiment is a **mutation sweep**: for each of K hot files, apply one trivial semantic mutation, run the full 118 suites, record the RED set, and diff against the rule's selection. At 15 min/run that is K×15 min of machine time and zero judgment — the right one-time investment before flipping this on.

---

## 6. The proposed rule (concrete)

Precompute once per tree into `.gate/selectmap.json` (a `git ls-files` + regex pass; ~2 s):

```bash
# ---- build (once per tree, cached by tree-hash) ----
# EDGES: for every tracked text file F, the set of repo paths F names in NON-COMMENT lines,
#        plus bare basenames of bin/* tools it invokes (PATH-resolved).
#   path regex: (scripts|bin|hooks|lib|commands|docs|templates|skills|agents|
#                settings-templates|launchd|usage|evolve-fixtures)/[A-Za-z0-9._/-]+
#   root regex: \b(install\.sh|sync\.sh|statusline(-debug)?\.sh|accounts\.json)\b
# D1[S]   = literal paths named ANYWHERE in tests/S.bats (comments INCLUDED — load-bearing,
#           §2a: lead-supervisor.bats names scripts/supervisor-e2e.sh only in a comment)
# CL[S]   = transitive closure of EDGES from tests/S.bats to FIXPOINT (see §4 depth table)
# PKG[S]  = { dirname(p) : p in D1[S], dirname(p) NOT a top-level dir }   # lib/cc-upgrade-gate, scripts/limit-recover

select_suites() {                       # stdin: git diff --name-only GATE_BASE..HEAD
  local SEL=() FULL=0
  while read -r F; do
    # --- fail-closed hub files: deploy/config surfaces every suite can transitively see
    case "$F" in
      install.sh|sync.sh|accounts.json|statusline.sh|statusline-debug.sh|settings-templates/*)
        FULL=1; continue;;
      tests/*.bats)   SEL+=("$F"); continue;;      # a changed suite runs itself
    esac

    HIT=()
    for S in tests/*.bats; do
      # (a) literal path reference
      grep -qF -- "$F" "$S"                                   && { HIT+=("$S"); continue; }
      # (b) transitive exec closure (fixpoint)  ← catches cc-interactive→cc-classify
      jq -e --arg f "$F" '.[$s] | index($f)' closure.json >/dev/null && { HIT+=("$S"); continue; }
      # (c) package-dir sibling  (skills/cc-upgrade-gate/SKILL.md, lib/cc-upgrade-gate/check07.sh)
      [ -n "$(dirname_pkg "$F")" ] && grep -qF -- "$(dirname_pkg "$F")/" "$S" && { HIT+=("$S"); continue; }
      # (d) basename / stem token, word-boundary, STOPLIST {run,common,main,test,commit}
      grep -qE "(^|[^A-Za-z0-9._/-])$(stem "$F")([^A-Za-z0-9._-]|$)" "$S" && HIT+=("$S")
    done
    # (e) naming convention, both directions + package-dir name
    HIT+=( $(name_match "$F") )                    # tests/<stem>.bats, tests/<stem>-*.bats, tests/<prefix>.bats

    # (f) install.sh deployment globs — inventory coupling (§2d). PRE-EXISTING paths only (R5).
    if git cat-file -e "$GATE_BASE:$F" 2>/dev/null; then
      case "$F" in
        hooks/*.sh|hooks/lib/*.sh|commands/*.md|scripts/*.sh|scripts/limit-recover/*|skills/*|bin/cc-*|launchd/*.plist)
          HIT+=(tests/install-wire-hooks.bats);;
      esac
    fi

    # (g) prose: docs/**.md, README.md, CLAUDE.md are INERT unless clause (a) matched.
    #     MEASURED SOUND: zero suites construct a real doc path dynamically (§3).
    case "$F" in docs/*.md|README.md|CLAUDE.md) [ ${#HIT[@]} -eq 0 ] && continue;; esac

    [ ${#HIT[@]} -eq 0 ] && { FULL=1; continue; }   # unmapped ⇒ FAIL-CLOSED
    SEL+=("${HIT[@]}")
  done
  [ "$FULL" = 1 ] && { printf 'tests/\n'; return; }
  printf '%s\n' "${SEL[@]}" | sort -u
}
```

Wire into `scripts/ship-land.sh:190-193`, reusing the range the gate **already** scopes shellcheck/`bash -n`/`py_compile` by (`run_gate "$GATE_BASE..HEAD"`, :217) — the repo has accepted changed-path scoping for its linters since day one; only `bats tests/` is unscoped. Kill switch: `SHIP_LAND_GATE_SCOPE=off` ⇒ `bats tests/`, byte-identical to today.

**The FULL-trigger allowlist is small and auditable — 24 of 390 tracked non-test files (6.2 %):**
- 8 hub files: `install.sh`, `sync.sh`, `accounts.json`, `statusline.sh`, `statusline-debug.sh`, `settings-templates/{settings,kimi-settings}.example.json`, `settings-templates/zshrc-snippet.sh`
- 16 zero-coverage: `bin/claude-bump-models`, `templates/model-classification.json`, `hooks/tests/validate-bash.test.sh`, 4 × `agents/*.md`, 4 × `evolve-fixtures/pyramid-principle/cases/*.md`, 5 × `scripts/plan-phase-scan-tests/fixtures/*`

That set is small enough to review in a PR and to re-derive on every build, which is what makes this tractable rather than a maintenance liability.

---

## Verdict

**FEASIBLE-CONSERVATIVE** — at fixpoint closure depth, with three preconditions.

The rule achieves **100 % recall on 237/237 developer-attested coupling pairs** (26/26 non-obvious), reduces the median land gate from **15 min to ~4.4 min (65 % wall-clock)**, and degenerates to the full suite on exactly 1 of the last 50 lands. The prior doc's stated objection ("tests read docs too") is **refuted by measurement**: 9 real prose files are read, all by literal path, zero dynamically — prose coupling is the *easiest* part to map, not the blocker.

The three preconditions, in order of load-bearing-ness:

1. **Fixpoint closure, not depth-2.** The `push-send.sh` 3-hop enumeration shows depth-2 silently drops ~45 genuinely-coupled (suite, file) pairs. Pay the 17 skip-points.
2. **Keep the full unscoped suite as a nightly backstop** (`nightly-regression.sh`), to re-base the trunk-greenness induction the CAS re-gate now depends on (R4).
3. **Land the hermeticity lint first** (R3). Cross-suite pollution is repo-documented (`7791209`) and only 6/117 suites isolate `HOME`. Subsetting a non-compositional suite is unsound *independently of the map*, and it is the one risk that gets worse rather than better as the skip rate rises.

Settle the residual with a one-time **mutation sweep** (K hot files × 1 semantic mutation × full-suite run, diff RED-set vs selection) — the only oracle that measures what the gate actually needs to know.
