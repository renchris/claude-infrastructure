<!-- source: /Users/chrisren/.claude-secondary/projects/-Users-chrisren-Development-claude-infrastructure/6cd4dd2b-1747-49ec-bf26-c15a943bfee0.jsonl
 turns=80 assistant_texts=13 last_stop=end_turn mail_injections=[] -->

Complete. Empirically confirmed: the DoD injection bundled **7 frozen-scope lines in one `attachment` record** into ce14bd0a (my earlier "0" was a jq-path artifact — real count 14 occurrences, 7 in the single injection). SessionStart carriers enumerated: only **dod-persist** (mutable scope) + **desk-brief-inject** (durable role, desk-only) carry state across the crash floor; the rest are env/discovery.

Saturation reached — next calls (reading desk-brief-inject fully, a 3rd chain) are predictable and answer-invariant. Composing.

---

# Succession Fidelity — What Survives a Session→Session Handoff

**Scope note (empirical vs theoretical):** All carrier claims are code-confirmed (path:line). Two handoff chains measured from live transcripts. "Crash-floor" behavior is inferred from carrier enumeration + hook trigger conditions (not staged a crash). Brief-drift check: CLEAN — internal-infra research, no entity-as-subject.

## Headline

`handoff-fire.sh` **does not compose the brief** — it is pure transport (account-rank → launcher → surface → recycle/engagement). The brief is **model-authored free-text** written to `/tmp/fire-<slug>.txt` and passed via `--prompt-file` (required, `handoff-fire.sh:1200-1205`). The script mechanically injects **only two** things: `## ACCOUNT STATE` (stranded-account bridge, `:968`) and the `--notify-back` trailer (`:1461-1519`). Consequence: **fidelity is bimodal** — rich when a disciplined model hand-authors a payload with time to spare; bare (frozen-scope only) on any crash/auto-compact where no payload is authored.

## (a) Payload Matrix

| Carrier | State-classes carried | Fidelity | Citation |
|---|---|---|---|
| **Fired brief** `/tmp/fire-*.txt` (model-authored) | task, scope, decisions+why, rejected-hyp, watch-obligations, peer-map, operator-pending — potentially ALL | **LOSSY** — no floor; = model discipline. Rich handoffs carry everything; hurried ones drop silently | `handoff-fire.sh:1200-1205` (`--prompt-file` required); empirical: `/tmp/fire-docclf-recycle.txt` (3142B, carries 3 watch re-arms + peer-map + ledger ptr) vs `/tmp/fire-680e2e0b321c.txt` (templated: task+rails only) |
| **dod-persist.sh** durable DoD | frozen scope + `Scope (grown)` only | **VERBATIM but SINGLE-CLASS** — mechanical, survives crash/compact/recycle via SessionStart re-inject | `dod-persist.sh:108-137`; file `~/.claude/autonomy/dod/ac9e929bcad43e1a.md` |
| **desk-brief-inject.sh** | durable ROLE brief (desk identity) — desk panes ONLY | **VERBATIM, role-keyed** — every start/resume/compact | `desk-brief-inject.sh:1-16` ("carries durable ROLE; dod-persist carries mutable STATE") |
| **cc-dispatch template** (backlog fires) | one task + generic rails + completion/block protocol | **VERBATIM (templated)** — but minimal classes; zero decisions/peer-map | `/tmp/fire-680e2e0b321c.txt`, `/tmp/fire-1b784d80d4d5.txt` (byte-identical boilerplate) |
| **session-continue.sh** sentinel | one next-step | **INTRA-SESSION ONLY** — SID-bound, deliberately CLEARED on succession | `session-continue.sh:67-70,122-132` (sid-bind clears inherited sentinel) |
| **boundary-handoff.sh** | nothing (trigger only) | N/A — advises `/handoff`, carries no state | `boundary-handoff.sh:222-227` |
| **wrap-ledger.sh** | git facts: dirty/ahead/gate-green/DoD-remainder | **COMPUTED FRESH, not carried** — REMAINDER inert (see defect) | `wrap-ledger.sh:86-99` |
| **handoff-disposition.sh** | watch-state: await_ping/fired_peers/mailbox/deliverables/open_tasks | **READER, not carrier** — re-derived live at disposition time from process/mailbox/registry | `handoff-disposition.sh:26-44` |
| **session-index** (SQLite FTS) | prior-session summaries/files/commands | **COARSE / discovery** — cwd-keyed "recent sessions" inject at start; for search, not fidelity | `session-index-start.sh:22-36`, `-end.sh:83-111` |
| **Plan docs** `.claude-plans/`, `docs/plans/` | decisions+why, rejected-hyp, known-issues, phase state | **RICH but POINTER-only + model-discipline** — /handoff mandates pointing not duplicating | `commands/handoff.md:23-27,119-123` |
| **MEMORY.md** | durable generalizable LESSONS + why | **COARSE, filtered** — anti-capture EXCLUDES in-flight/transient/one-off | `memory-nudge.sh:36-42` |

**SessionStart carriers on the crash floor** (enumerated): dod-persist, desk-brief-inject, session-index, + env/setup hooks (session-start, config-mirror, activation-watch, setup-*-symlinks). Only the **first two carry state**; desk-brief-inject only for the one desk pane.

## (b) Measured Chain Traces

**Chain 1 — session-sprawl (planned /handoff, cross-account):** predecessor → successor `74b6d364` (quaternary; first user msg = fire text verbatim, 1789B `/tmp/fire-session-sprawl.txt`).
- Start 22:35:37 → **first productive Edit +3m45s** (22:39:22) → **first commit +9m18s** (22:44:55) → 138 total tool calls, ~54min session.
- **Fidelity WINS:** obeyed BOTH carried anti-patterns — never opened `lr-audit.py` (brief: "is NOT the selector — do not look for the fix there"), did not re-investigate root cause (brief: "EVIDENCED and settled"). Decisions+rejected-hyp crossed intact.
- **Fidelity LOSS:** ~15-17 exploration calls re-deriving code topology (lr-fire-resume.sh, resume-sessions/SKILL.md across 5 config dirs, boot-resume.sh, cc-sessions symlink probes) before first write. The brief carried the *decision* but not the predecessor's *file:line map*. Successor also discovered "selection path is four callers, not one" — a genuine correction the brief couldn't carry (predecessor didn't know it; it was open-question Q1).

**Chain 2 — docclf (--recycle, same pane, idle free-win):** predecessor `e1dd5f7b` (ended 22:59:09) → successor `ce14bd0a` (started 22:59:19) = **10-second recycle gap**; payload `/tmp/fire-docclf-recycle.txt` (3142B).
- **First productive action +42s** (23:00:01): ledger tail → Chrome :9223 sign-in check → Azure ticket paste → re-created both watch scripts → **re-armed `cc-await-ping <peer-UUID>`** → consumed browser-zerohitl fork. Executed the *current* scope precisely.
- **DoD injection stress test:** the SessionStart hook bundled **7 `Scope (frozen)` lines in ONE `attachment` record** (6 stale: task#18, nuke-ai-trailer, README×2, one-click-UX), all framed "binding" (`dod-persist.sh:113`). Successor **ignored all 6 stale** — because the rich hand-authored payload dominated. The stale-scope landmine was *masked*, not absent.
- **Watch-obligations + peer-map crossed only as free-text**: the `cc-await-ping` process died with the recycle; the successor re-armed it solely because the payload's item (3) told it to.

**Cross-chain finding:** high fidelity in BOTH — but both had a **freshly hand-authored rich payload**. The measured cost of the topology-tax (chain 1: ~3.75min/17 calls) and the latent stale-scope risk (chain 2: 6 masked) are the fidelity gaps; both were survivable *because a payload existed*.

## (c) State-Classes With NO Durable/Mechanical Carrier

On the **crash/auto-compact floor** (no hand-authored brief — dod-persist PreCompact runs, session-continue is SID-cleared), ONLY frozen+grown scope crosses. These classes have **no mechanical carrier** and evaporate:

- **Decisions + why** — free-text brief or plan doc only; not in any SessionStart injector.
- **Rejected-hypotheses + why-not** — free-text brief or plan doc only. (The load-bearing "don't chase X" warnings from chain 1 exist nowhere mechanical.)
- **In-flight verification state** (what's mid-test, which gate is pending) — **zero carrier**; session-continue sentinel is explicitly cleared across succession (`session-continue.sh:122-132`).
- **Watch-obligations** (armed `cc-await-ping`, poll loops) — process dies; only free-text re-arm survives; disposition helper READS live state but carries nothing forward.
- **Peer-session map** (which fork pings which UUID) — free-text only; cc-sessions registry is live-only (sweeps dead panes).
- **Operator-pending items** — partial: `cc-blockers` board (3 durable stores) exists but is **not auto-injected at SessionStart** (must be queried); DoD `grown` line + free-text carry a subset.

**Topology/file-map** (predecessor's read/edited file set) — not a "state class" in the brief's list, but the measured #1 re-derivation cost, and carried by nothing.

## (d) CANDIDATE FRONTIER PROBLEMS

**FP-1 · Bimodal fidelity floor — no event-sourced carrier**
- **Evidence:** `handoff-fire.sh:1200-1205` (brief is model-authored `--prompt-file`, script adds only ACCOUNT STATE `:968` + notify trailer); crash-floor SessionStart carriers = dod-persist (scope only) + desk-brief-inject (role only) — `dod-persist.sh:108-137`, `desk-brief-inject.sh:1-16`. Chain-1 vs crash delta: rich brief carried decisions+anti-patterns; a crash would carry neither.
- **Mechanism class:** trigger==failure asymmetry (the state a handoff most needs to carry is exactly what a *crash* handoff cannot author).
- **Current mitigations + status:** dod-persist (scope, shipped); plan-doc pointer discipline (shipped, model-dependent); MEMORY.md (lessons only). No event-sourcing.
- **Why it resists normal fixes:** every point-fix adds another *thing the model must remember to write*. The gap is structural: no carrier is sourced from artifacts the session *already produced* (its commits, tool-calls, decisions).
- **Quantified cost:** unmeasured directly — measure via: sample N auto-compact successors (no /handoff), grep first-20-turns for re-derivation of decisions present in predecessor's last 50 turns; ratio = fidelity loss. Chain-1 topology-tax (3.75min/17 calls) is a lower bound for the *planned* case.
- **Frontier-fix sketch:** event-source a "succession ledger" from artifacts already emitted — commits since fork, files Read/Edited (from transcript tool-calls), `Scope (grown)` lines, armed watchers (from process table), open decisions (from cc-blockers) — auto-materialized at PreCompact/recycle into the durable DoD dir, re-injected alongside scope. Zero per-turn tax (built from residue, not bookkeeping).
- **Confidence:** HIGH. **Stale-risk:** LOW (architecture-level).

**FP-2 · DoD stale-scope accumulation + inert remainder**
- **Evidence:** `ac9e929bcad43e1a.md` holds **6 distinct scopes** (2026-07-20→22, different tasks each); SessionStart re-injects the WHOLE file framing every line "binding" (`dod-persist.sh:111-116`); empirically **7 frozen-scope lines bundled in one injection** into ce14bd0a. **0 of 5 DoD files carry any `- [ ]` checkbox** → `wrap-ledger.sh:97` REMAINDER always 0 → the `REMAINDER>0 → 🔧` completeness rung (`:107-108`) is structurally dead for real DoDs.
- **Mechanism class:** append-only without supersession + shape-mismatch between producer (prose scopes) and consumer (checkbox counter).
- **Current mitigations + status:** dedup skips *identical* consecutive scopes only (`dod-persist.sh:86,126`) — distinct scopes still stack. No supersession marking.
- **Why it resists normal fixes:** "INTEGRATE-never-overwrite" (a19 HOP A) is a hard project rule → can't just truncate. And prose scopes can't be checkbox-counted without a format change that breaks the manual-set CLI ergonomics.
- **Quantified cost:** 6 stale scopes injected per recycle in the doc_classifier worktree; masked in chain 2 only because a rich payload disambiguated. Fires unmasked on any crash-recovery (no payload). Measure: count `Scope (frozen):` per DoD file × injection frequency.
- **Frontier-fix sketch:** mark supersession (newest scope = ACTIVE, priors = `# superseded`), inject only ACTIVE + a one-line history pointer; OR switch consumer to parse the newest scope's sub-items as the remainder. Keeps INTEGRATE (history preserved) while killing the "6 binding scopes" ambiguity.
- **Confidence:** HIGH. **Stale-risk:** LOW-MED (obvious patch could land anytime).

**FP-3 · Engagement-verify has no auto-refire loop; --recycle unguarded**
- **Evidence:** `handoff-fire.sh:429-447` — poll ≤120s → resend prompt **ONCE** into the *same cold pane* → re-poll ≤60s → return 1; failure path `:2132` prints a **manual** warm-refire instruction, no auto-retry. **`:1461` `[ "$RECYCLE" = 0 ] && ENGAGE_VERIFY=1`** — verification entirely OFF for --recycle (the desk's most common path, where the /goal-prefix trap + cold-race live). Point-fixes are pre-fire lints only: `check_goal_length:563`, `check_slash_head:589`.
- **Mechanism class:** incomplete control loop (detect-but-don't-correct) + unguarded highest-traffic path.
- **Current mitigations + status:** 3 shipped point-fixes (goal-length lint, slash-head lint, one-shot resend) + memory entries (`handoff-fire-goal-prefix-trap`, `cold-worktree-fire-autosubmit-race`). Each retires one instance, not the class.
- **Why it resists normal fixes:** the resend re-uses the *same racy cold path* that failed; and it's synchronous in the firing session (blocks ≤180s → serializes waves), so a real retry loop can't live inline.
- **Quantified cost:** unmeasured — measure via cc-fired markers: count fires whose marker never appears in target projects-dir within window ÷ total fires. Recycle fires contribute 0 detections today (verification off).
- **Frontier-fix sketch:** promote engagement to a **detached receipt-watcher** (reuse the proven setsid watcher pattern, `handoff-fire.sh:281`) owning {brief-hash marker, deadline, N-retry}; on miss it re-fires a **fresh warm pane** (not a cold resend), escalating to the desk only after N. Extend to --recycle (arm the same watcher on the relaunch). Retires "fired-but-never-engaged" wholesale + un-blocks the firing session.
- **Confidence:** HIGH. **Stale-risk:** MED (actively-patched area).

**FP-4 · Topology re-derivation tax**
- **Evidence:** chain-1 successor `74b6d364` spent ~15-17 exploration tool-calls (lr-fire-resume.sh, resume-sessions/SKILL.md ×5 dirs, boot-resume.sh, cc-sessions, symlink probes) over **3m45s before first productive Edit**, re-walking a map the predecessor already had. The brief carried the *decision* ("selection lives in resume-sessions SKILL.md") but not the *dependency map*.
- **Mechanism class:** carried-conclusion-without-carried-evidence (the brief passes verdicts, not the file:line graph that grounds them).
- **Current mitigations + status:** /handoff skill step 2 captures git HEAD/branch/worktree (`commands/handoff.md:125-135`) and "4-8 facts + landmines" (`:147-150`) — but the file-map is model-discretionary prose, usually omitted.
- **Why it resists normal fixes:** listing every relevant file bloats the brief past the 4000-char `/goal` cap (`handoff-fire.sh:563-585`) and taxes the author each handoff; some re-derivation is legitimate verification and shouldn't be suppressed.
- **Quantified cost:** ~3.75min + ~17 calls on chain 1 (one data point; measure across N chains as calls-before-first-Edit that re-Read files the predecessor Read).
- **Frontier-fix sketch:** auto-attach the predecessor's **touched-file set** (Read/Edit targets from its transcript tool-calls, deduped, with last-commit-per-file) as a machine-generated "map" section — event-sourced (FP-1 subset), zero author tax, so the successor verifies-not-rediscovers.
- **Confidence:** MED (1 strong chain; plausibly general). **Stale-risk:** LOW.

## Blockers / Uncertainties (explicit)

- **Predecessor-of-record for chain 1 not pinned:** `6cd4dd2b`/`59400fba` that quote the fire text are themselves `<teammate-message>` subagents, not the desk author. Immaterial — the predecessor's *knowledge* is captured verbatim in the surviving `/tmp/fire-session-sprawl.txt` + `session-sprawl-resume.md`, which is what fidelity is measured against.
- **Crash-floor is inferred, not staged:** FP-1's "crash carries scope-only" rests on carrier enumeration + hook triggers, not an induced crash. High confidence but not E2E-observed this session.
- **N=2 chains** — both succeeded (rich payloads existed). The *failure* mode (crash → bare floor) is unmeasured; FP-1/FP-2 predict it but no failed chain was in the sampled window. The measurement recipes are given per-FP.
- **FP-4 generalization** rests on one chain; some of its 17 calls were legitimate verification, so the tax is an upper bound.