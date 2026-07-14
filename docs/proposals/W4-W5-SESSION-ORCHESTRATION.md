# §8 filled instance — doc_classifier W4 / W5 session orchestration

**Proposal, handed to the operator/orchestrator.** A filled `C00-SECTION-8-TEMPLATE.md` for the two
live waves. **Written here (`claude-infrastructure/docs/proposals/`) as a proposal — NEVER written
into `doc_classifier` (its W4 lead owns that repo; this is a hand-off the orchestrator applies).**

Everything below runs in **manual mode today** (the named `cc-*` / `git` commands exist); it upgrades
as the `SESSION_AUTONOMY_RESEARCH.md` primitives land. Grounded in `doc_classifier/docs/BUILD_LOG.md`
facts (W4 opened on `next`, `spawn base 3bb2e08`, blocked by the W3-EXIT queue RULED at `3bb2e08`;
orchestrator pane `99261468-A46A-498A-AE9B-F39473E5E7AE` **as of the 2026-07-14 epoch — a historical
fact, NOT a send target**; it recycles, so resolve `<orchestrator>` at send-time). **Live constraints
(verify at apply-time):** the Fable window closes
**2026-07-15T00:00Z**; **next3 is weekly+fable-exhausted → only 3/4 accounts routable.**

---

## W4 — lifecycle + gates + export + ReviewApp + handoff (~10 teammate slots)

| § | Element | Filled value | Manual action today |
|---|---|---|---|
| E1 | Lead placement | account `next`, `claude-next --model fable --probe`, `claude-fable-5` @ **xhigh** (judgment-dense: B02-driver wiring, calibration, viewer-overlay) | verify Fable window OPEN + `next` routable: `claude-accounts --rank fable`; after spawn `ps -eo command \| grep -- --effort` shows `xhigh` |
| E2 | Budget + succession | `start_clean 25 / mid_soft 50 / boundary_recycle 60 / hard_handoff 73` | at each merge boundary read `cc-context <W4-lead-sid>`; hand off past 60% **at a committed+green boundary**, never mid-slot |
| E3 | Write-fence | `write_fence: ancestor(3bb2e08, integration)` | before the first W4 `git worktree add`: `git merge-base --is-ancestor 3bb2e08 integration && echo CLEAR` |
| E4 | Placement source | Fable-gated → requires a Fable-window-OPEN account; recompute armed on the 2026-07-15T00:00Z window edge | if the window closes mid-wave, re-rank and place the *next* spawn (downgrade to `claude-opus-4-8 @ max` if no Fable account) |
| E5 | Back-channel | 10 teammates → W4-lead mailbox (pull-verified before any reap: `cc-sessions`); W4-lead → **`<orchestrator>`** (ROLE — resolve to a pane at SEND-TIME, never cache) via `cc-notify`, **R-PING armed** (`--notify-back`) for the W4-exit ping | W4-lead pairs `cc-await-ping <own-uuid>` (background) after arming. **Resolve `<orchestrator>` at send-time** from the newest self-close-log `successor=` chain / the announce in your mailbox — the orchestrator pane **recycles across epochs** (it did on 2026-07-14) and any uuid written here is stale the moment it does |
| E6 | Gate manifest | **in-class (auto-ratify+stamp):** as-built spec-deviation ratifications · W4-exit erratum-queue additions · merge-gate SME config bundles (e.g. the B20 `physical_file_name` drop, natural-key restructure). **out-of-class (STOP-ASK):** any destructive `contracts/` change · a roster slot beyond the R5 driver · anything on the money-path (C6) | operator pre-signs the in-class set at W4 start (one signature) |
| E7 | Isolation | W4-lead worktree distinct from the `<orchestrator>`'s checkout | `git worktree list` — confirm W4-lead ≠ orchestrator cwd |
| E8 | Readiness | run the 7-box checklist before cutting W4's lead | fence CLEAR · placement fresh · 60/73 declared · UUIDs known · manifest signed · worktree isolated · effort=xhigh verified |
| E9 | Telemetry | W4-lead self-reads `cc-context --me` each boundary; orchestrator watches all leads via the telemetry table | until `cc-board` lands, `cc-context` (table mode) is the multi-session view |

**W4 succession sub-rows** (a wave can span leads — the W3 pattern was `163b5ffa` → `31bcd087` at
exit): if the W4-lead crosses `boundary_recycle` (60%) mid-wave at a green slot-merge boundary, it
stamps its progress, fires `handoff-fire.sh self-close --successor <fresh-W4-lead-pane>`, and the
successor resumes under the same §8 row (same account/model unless E4 recompute fired).

## W5 — corpus-scale rehearsal (~3 spawns, lighter judgment density)

| § | Element | Filled value |
|---|---|---|
| E1 | Lead placement | **conditional on the Fable window:** if OPEN at W5 start → `claude-fable-5 @ xhigh`; if CLOSED (past 2026-07-15T00:00Z) → **`claude-opus-4-8 @ max`** (E4 recompute) — the per-wave variation the old one-line status string could not express |
| E2 | Budget + succession | same thresholds; a single fresh lead likely suffices (small wave, clean post-W4 context) → succession trigger = "terminal unless context climbs past 73%" |
| E3 | Write-fence | `write_fence: ancestor(<W4-exit-stamp>, integration)` — hold W5 spawns until W4's exit ratification lands |
| E4 | Placement | re-rank at W5 start (the Fable window will likely have closed — plan for the Opus fallback) |
| E5 | Back-channel | 3 teammates → W5-lead → orchestrator, R-PING armed on the W5-exit (final) ping |
| E6 | Gate manifest | in-class = rehearsal-scale acceptance ratifications; out-of-class = any corpus-scale data-integrity finding (money-path / schema) |
| E7–E9 | as W4 | — |

---

## Apply-now checklist (what the orchestrator can do immediately, before any code lands)

1. **W4 succession discipline** — the W4-lead reads `cc-context <sid>` at each slot-merge boundary and
   hands off past ~60% at a green boundary (this alone would have prevented the §3b premature-relief:
   the operator no longer eyeballs a lying gauge; the honest `used_pct` drives it).
2. **Write-fence** — `git merge-base --is-ancestor 3bb2e08 integration` gate before W4 worktree creates.
3. **Pre-signed W4 gate manifest** — operator signs the in-class ruling set once at W4 start; the lead
   STOP-ASKs only out-of-class → the "RATIFY ALL 7" batch moves from wave-exit interrupt to
   wave-start signature.
4. **Back-channel** — W4-lead arms `--notify-back` to **`<orchestrator>`** (resolved at send-time, never a cached uuid) + a background `cc-await-ping`; the
   orchestrator's wait for the W4-exit becomes event-driven, not a manual pane-poll.
5. **Account placement** — rank once (`claude-accounts --rank fable`), remember next3 is exhausted;
   spread ≤2 tracks/account; watch the Fable window edge (2026-07-15T00:00Z).

## Caveats / blockers (state at apply-time)

- **`cc-wave-plan` (axis d) not built yet** → E4 placement is hand-filled from `claude-accounts
  --rank`; the recompute trigger is operator-watched.
- **Boundary hook (axis h) not built yet** → E2 succession is hand-run via `cc-context`, not
  auto-advised. The honest number is available NOW (`cc-context` / `1b8d671` parity); only the
  auto-injection is pending.
- **D2 effort** — verify `ps | grep -- --effort` on the first W4 teammate spawn: if teammates show
  the lead's effort, per-member `set-teammate-effort.sh` is INERT on this runtime → control the LEAD's
  effort (xhigh) to set the wave.
- **`.git/gate-green` marker + `session-spawn-readiness.sh`** are proposed, not built → E8 is a manual
  checklist until then.

---

_Template: `C00-SECTION-8-TEMPLATE.md`. Derivation + per-primitive build spec:
`docs/research/SESSION_AUTONOMY_RESEARCH.md`. Ground truth: `docs/research/W0-W3_INTERVENTION_AUDIT.md`._
