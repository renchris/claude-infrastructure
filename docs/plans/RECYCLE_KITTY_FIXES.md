---
status: open
---
# Recycle-on-kitty fixes — implementing the 2026-10-10 root-cause report

Source of every fix, file:line and test: `docs/research/recycle-failures-kitty-2026-10-10/REPORT.md` § Ranked fixes (fix numbers below are that list's). Fix 1 already landed (`0e882c9ac`, another session).

Scope (frozen): implement REPORT fixes 2-9, and fix 10 once its throwaway-pane SIGTERM proof passes. Every fix lands through the project `/ship` with a test that is red before it. `scripts/handoff-fire.sh` has exactly one owning wave at a time.

## Phase 0 — Agent Team Orchestration

**Execution locus per wave:** every wave is **S** (a dispatched session, `handoff-fire.sh --prompt-file /tmp/fire-<wave>.txt --worktree <branch> --notify-back <lead> --goal …`). Each one leads its own teammates if its unit spans 2+ files.

**Task size:** each wave is one task, sized for the 40-150K output band (30-75 min, 3-6 files). W2 and W3 sit at the low edge of the band and are kept separate because they share no file.

| Wave | Fixes | Owns (exclusive) | Branch | Blocked by |
|---|---|---|---|---|
| W1 | 2, 3, 4, 5, 6: honest hold text, unreadable-after-own-/exit as receipted residue, defer only on turn-shaped UNKNOWN (distinct exit code), self-lane last-moment re-read, true deferral wording, screen snapshot on holds | `scripts/handoff-fire.sh`, `tests/handoff-recycle-turn-wait.bats`, `tests/handoff-fire-recycle-custody.bats` | `fix/recycle-kitty-w1-composer-defer` | — |
| W2 | 7b: strand-only banner rung before sweep phase 0a | `scripts/autonomy-sweep.sh` + its suite | `fix/recycle-kitty-w2-sweep-strand-rung` | — |
| W3 | 8: zsh `precmd` successor claim, fork-free when nothing is staged | `scripts/kitty-setup.sh` rc block, `scripts/lib/pane-successor.sh` + suite | `fix/recycle-kitty-w3-precmd-claim` | — |
| W5 | 9: converge the composer-parser copies onto the guarded rule (no dialog-over-empty reads EMPTY) | `scripts/lib/cc-tui.sh`, `scripts/lib/lr-composer-snapshot.sh`, lr_recon `observe.py`, `bin/it2-kitty` composer_state, `scripts/limit-recover/lr-fire-resume.sh` LR_SCREEN_SH + one parity suite. **Not** handoff-fire.sh | `fix/recycle-kitty-w5-parser-parity` | — |
| W6 | 10-gate: throwaway-pane proof that SIGTERM at rest exits like `/exit` (transcript intact, bg shell stopped, staged successor claimed, not classed a crash once a teardown marker exists). Measurement + doc only | `docs/research/recycle-sigterm-proof-2026-10-11/` | `research/recycle-kitty-w6-sigterm-proof` | — |
| W4 | 7a (hf_alarm per-record banner with a short handle, before the push), 8b (no `/exit` under extreme load when the successor cannot be claimed), and 10 (SIGTERM exit) **only if W6 proved it** | `scripts/handoff-fire.sh`, `tests/handoff-alarm-records.bats` + new suites | `fix/recycle-kitty-w4-alarm-load-sigterm` | W1 landed, W6 verdict |

**Spawn order:** W1, W2, W3, W5 and W6 fire in parallel; W4 fires once W1 has landed and W6 has reported.

**Lead context budget and succession point:** the lead (this research session, pane of session `f28815ed`) only writes briefs, collects pings and fires W4. It keeps ≥50% of its window for that. Succession point: if the lead passes 50% before W4 fires, it recycles with this plan as the brief.

**Machine constraint at intake (2026-10-11 00:48 local):** load ≈ 53 runnable/core, i.e. F1's regime. Admission is left to `handoff-fire.sh`'s capacity gate. A refused fire is retried, never forced.

## Wave status

(Each wave appends its landed sha and learnings here when it reports.)
