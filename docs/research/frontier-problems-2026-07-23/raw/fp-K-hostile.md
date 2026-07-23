<!-- source: /Users/chrisren/.claude-secondary/projects/-Users-chrisren-Development-claude-infrastructure/b2091ff2-c9bd-4df4-9173-e84d0f04334e.jsonl
 turns=49 assistant_texts=1 last_stop=end_turn mail_injections=[] -->

Saturation reached (three prior audits located, all converging; next reads predictable). Adversarial self-pass on my own critique complete. Composing.

---

## VERDICT

**This investigation is the THIRD multi-agent audit of this infrastructure in 5 days** (`desk-audit-2026-07-18/`, `infra-reliability-audit-2026-07-22/`, and now). All three independently crown the **same #1 root cause** — "last-mile activation/deploy gap" (07-22 `synthesis.md:25`) ≡ "LAST-MILE WIRING (dominant)" (07-18 `synthesis.md` theme A). The 13 axes map almost 1:1 onto the prior audits' P01–P16/A17–A19 lenses. **Convergence here is not truth-signal; it is shared-corpus echo.** The marginal value of a 13th-axis pass is therefore NOT re-confirming the activation gap (real, but triple-counted) — it is the **five problem classes all three audits structurally cannot see because they share one vocabulary (failure-modes: seams/races/silent-failures) and one self-written evidence corpus.** The single sharpest miss: **every audit treats the test suite and the memory corpus as EVIDENCE, but neither is itself audited** — 105 bats tests are green while `a18` proves the live system is full of dead-letters ("gates test CAPABILITY not LIVE WIRING"), and 46 self-written memory files are re-ingested as ground truth when they are prior-agent *conclusions* in the same taxonomy. The investigation cannot verify itself with the instruments it trusts.

---

## RANKED MISSING DIMENSIONS

| # | Dimension | Why high-margin | Evidence path:line | Absorb vs own axis |
|---|---|---|---|---|
| 1 | **Test-oracle validity** (do the 105 bats assert live behavior, or capability?) | Green tests are *why* a18's dead-letters survived 3 audits; false confidence is the failure amplifier | 64/105 bats mock-based, 5 assert live-binary emission; `desk-audit-2026-07-18/a18-liveness-attack.md` "gates test CAPABILITY not LIVE WIRING"; `deploy-parity.bats` guards only a hardcoded symlink list | **Own axis** — no axis targets the verifier's validity |
| 2 | **Security / adversarial-INPUT threat model** (24/7 + push + WebFetch + self-writing memory) | Self-driving system with narrowed-but-real push access, reads untrusted web, re-ingests its own memory — zero documented attack surface | `find -iname '*security*/*threat*'` → EMPTY; injection-defense grep → EMPTY; only control is `hooks/ship-rail-push-allow.sh` (land-shape narrow). a17/a18/a19 are *desk-logic* adversarial (does it stall), NOT attacker-input | **Own axis** — M (permission) covers authz, not injection/exfil/poisoning |
| 3 | **Restore drill + backup SCOPE** | restic backs up `~/.claude/archives/claude-code/` ONLY — not the live autonomy state-stores, not the 46 memory files, not the repo; password loss = unrecoverable; **never restore-tested** | `scripts/restic-claude-archive-backup.sh:9,33`; restore-drill grep → EMPTY; plist not in `launchd/` (live-vs-repo gap) | **Own axis** — J (GC) is deletion, not recovery; L (daemon) is liveness, not data-loss |
| 4 | **Knowledge-layer as a TESTED artifact** (adherence + conflict, not size) | Lazyload review optimized SIZE (1516→290 lines) and *asserted* "no behavior change" — never tested adherence or contradiction; `~/.claude/CLAUDE.md` is a **separate real file** that drifts from the repo copy | `docs/CLAUDEMD_LAZYLOAD_REVIEW.md:18`; `.claude/CLAUDE.md` sync note; 2 resident CLAUDE.mds + 46 MEMORY files auto-loaded | Partially in H; **needs own axis** (rule-conflict is not a token problem) |
| 5 | **Wall-clock / operator-perceived latency** | Goal says "time performance"; H + context-econ measure TOKEN-time (burn/forecast), never prompt→first-token, spawn→engagement, or page→operator-sees latency | H = "context/time/token economics"; latency grep hits incidental only; `p08-quota.md` = quota not latency | **H can absorb** if reframed from token-time to wall-clock UX |
| 6 | Multi-machine / portability & machine-loss migration | Entire model is single-host (symlink from one checkout, keychain creds); p16 covers THIS machine's power/sleep, not a second machine or full-loss migration | `p16-continuity.md` (power/sleep only); 6 files hardcode `/Users/chrisren` in hooks/bin/scripts | Lower rank — own axis if pursued |

**Goal-phrase underservice (compact):** "time performance" → served only as token-time, not wall-clock UX (#5). "UI visibility / quality of detail" → axes G owns whether a channel *delivers*; no axis owns the **information-design quality** of the statusline/readout render (the `feedback-tui-visibility-numbers-first` memory is a DESIGN standard nothing tests against). "session-to-session pass-through" → axis I owns it, but the load-bearing hole (`a19`: frozen DoD "no durable home, no re-injection across compaction/handoff/recycle") is known-and-open, not closed.

---

## FALSE-CONVERGENCE LIST (with discount guidance)

1. **"Last-mile activation / built-but-dormant is the #1 systemic problem."** Both prior audits' dominant theme AND the `desk-autonomy-dormancy` memory. 12 agents WILL re-crown it. **Discount:** real but triple-counted; 244 commits since 07-18 partially closed it (e.g., `c2f7f69` wired session-deregister, `16691b4` fixed the empty-PAGE_TO half). Require every dormancy claim to be re-verified against **live `launchctl`/settings state as of 2026-07-23**, not the 07-18 snapshot. Treat unchanged pending-activation `.done` gaps (`04-page-channel`, `06-desk-bootstrap`, `09-operator-readout`) as the ONLY fresh instances.

2. **"Silent failures / seams are the dominant risk class."** The corpus is *written in* this vocabulary and is self-selected (only logged failures exist). **Discount:** survivorship/observability bias — any "dominant risk = silent failure" claim not backed by a measurement of the *unlogged* failure rate is corpus-echo, not a finding.

3. **The crash / memory-residue thread is ACTIVELY UNSTABLE — distrust any conclusion there.** Three root causes in three days for one symptom: giant-transcript OOM (07-22 inherited) → CC 2.1.207 version-regression (07-22 supersession note) → **~92% teardown-confound artifact, pin-to-183 WITHDRAWN** (`MEMORY.md` session-crash entry, corrected ×2). **Discount:** any axis-B crash-rate claim citing raw "mid-Bash crash" counts is stale; only the corrected organic rate (0.00%→0.24%, flat 207↔215) survives. This axis will likely be re-corrected AGAIN — mark its output provisional.

4. **`cc-classify:205 permanent-ACTIVE` + `PAGE_TO="" dead-letter` will be "independently discovered" 4×.** Axes D, G, L, N all read `a18-liveness-attack.md`. **Discount:** dedupe — multiple axes citing the same file:line = ONE finding. Check `16691b4` already fixed the PAGE_TO half before ranking it open.

5. **The 46-file memory corpus is treated as independent evidence.** It is prior-agent *conclusions* self-written in the shared taxonomy and re-ingested — circular. A wrong distillation compounds (the crash entry was wrong twice before correction). **Discount:** memory entries are hypotheses, not ground truth; demand live re-verification for any load-bearing claim sourced only to MEMORY.md.

---

## CANDIDATE FRONTIER PROBLEMS

**CFP-1 — The self-referential verification gap: nothing audits the auditors.**
- **Evidence:** 105 bats, 64 mock-based, only 5 assert live-binary emission; `a18-liveness-attack.md` "gates test CAPABILITY not LIVE WIRING" — tests stayed green through 3 audits while live backstops were dead-letters. Compounds with `staged-skill-fanout-trap` memory ("never verify the verifier").
- **Mechanism class:** false-green oracle / capability-vs-wiring blindness.
- **Current mitigations + status:** `deploy-parity.bats` (symlink drift, hardcoded list only); ad-hoc "blind-check law." No general live-wiring assertion. OPEN.
- **Why it resists normal fixes:** self-referential — you cannot test the test with another test of the same kind; a live-wiring assertion is itself capability-tested. Adding tests deepens the trusted-but-unverified layer.
- **Quantified cost:** unmeasured. Measure = count backstops that are (green in bats) ∧ (absent from live `launchctl`/settings/hook-chain) — a18 already implies ≥6.
- **Frontier-fix sketch:** a runtime "is-this-actually-wired" attestation that every gate must emit against LIVE launchd/settings/hook-registry, checked from OUTSIDE the test harness (fresh-context verifier, not self-critique).
- **Confidence:** high / stale-risk low (structural).

**CFP-2 — Self-writing memory as a compounding-error substrate.**
- **Evidence:** 46 self-written memory files re-ingested as resident context; the crash entry was wrong twice (OOM→regression→artifact) before correction, each version *shaping the next agent's priors*; no provenance/confidence/decay on entries.
- **Mechanism class:** epistemic feedback loop / corpus poisoning (accidental, not adversarial).
- **Current mitigations + status:** Memory Hygiene anti-capture list (CLAUDE.md) gates WRITES; nothing re-validates or expires PAST entries. OPEN.
- **Why it resists normal fixes:** a corpus that trains its own future readers has no external ground truth; "verify before ingest" is done by an agent whose priors the corpus already set.
- **Quantified cost:** unmeasured. Measure = fraction of load-bearing MEMORY claims that fail live re-verification (the crash entry is one confirmed false-for-a-week instance).
- **Frontier-fix sketch:** provenance + confidence + auto-decay on memory entries; periodic fresh-context re-verification wave that demotes stale/refuted claims; distinguish "observed fact" from "agent conclusion" at write time.
- **Confidence:** medium-high / stale-risk medium.

**CFP-3 — Knowledge-layer rule-conflict and drift under load (undiagnosed).**
- **Evidence:** `docs/CLAUDEMD_LAZYLOAD_REVIEW.md:18` optimized 1516→290 resident lines and asserted "no behavior change" WITHOUT adherence testing; `~/.claude/CLAUDE.md` is a separate real file that must be hand-synced (drift vector); 2 CLAUDE.mds + 46 MEMORY files load every turn for every one of 20–100 concurrent agents.
- **Mechanism class:** lost-in-middle / silent rule-contradiction / resident-copy drift.
- **Current mitigations + status:** lazyload SIZE reduction (done); no conflict or adherence test. OPEN.
- **Why it resists normal fixes:** adherence is probabilistic and load-dependent; you cannot unit-test "did the model follow rule 47 under 250K context" deterministically.
- **Quantified cost:** unmeasured. Measure = adherence-eval harness (inject scenarios that trigger each resident rule; score compliance) + a diff-guard between the two resident CLAUDE.md copies.
- **Frontier-fix sketch:** treat the resident layer as a tested spec — conflict-linter across rules + periodic behavioral adherence eval + single-source-of-truth for the two CLAUDE.md copies.
- **Confidence:** medium / stale-risk medium (partly theoretical — no observed conflict-caused incident yet, only the drift vector is concrete).

*Empirical vs theoretical: CFP-1 and the false-consensus list are empirically grounded (a18 dead-letters, 3-audit convergence, crash whipsaw all disk-verified). CFP-3's harm is theoretical (drift vector concrete, incident not yet observed). Restore-drill and security-model absences are empirically confirmed by EMPTY greps, not inferred.*