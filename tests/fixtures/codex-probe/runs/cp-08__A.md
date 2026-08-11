retry" and 2 for "respect the refusal" classifies this outcome as neither — the deferral is silently mis-signaled to the one audience the exit-code contract exists for.

---

**Defect 5 — The tty-exclusivity guard is silently skipped whenever the target pid is already dead, so a pane hosting live foreign processes can be force-closed without the collateral check the header claims always holds.**

**Where** — ≈lines 577–578:
```bash
  # ── 2c. tty-exclusivity — runtime-only guard, meaningful ONLY while the target is LIVE ──────────────
  if pid_alive "$pid"; then
```
against the header's claim, lines 24–25:
```bash
#      decision module); ADD the runtime-only (c) tty-exclusivity guard here (no foreign live process on
#      the pane tty beyond the target claude tree). ALL hold else DEFER+record (exit 10) / REFUSE (exit 2).
```

**Why it is wrong** — Condition: the target claude process has died, but the pane is still open and an operator has live work in it (a vim, an ssh session, a running build in that pane's shell). The idempotent short-circuit does not fire (pane present), all other gates can pass, and because `pid_alive "$pid"` is false the foreign-process check never runs — the code proceeds to `it2 session close -f`, killing the foreign processes. The inline comment's premise ("meaningful ONLY while the target is LIVE") is false: collateral processes on the pane tty exist independently of the target's liveness, and the helper only *derives* the tty from the live pid — the pane's tty is equally obtainable from the it2 list it already consults. The guard therefore does not cover the class ("no collateral close") the step-2 contract says it covers.

---

**Defect 6 — The selftest's REFUSE scenarios assert only exit code and decision, not `reason_kind`, so they pass even when the refusal comes from a different guard than the one under test.**

**Where** — e.g., scenario 5 (missing done-evidence), in `selftest()`:
```bash
  [ "$rc" = 2 ] && [ "$(last_decision)" = REFUSE ] \
```
(the same pattern is used by scenarios 6, 7, 8, and 13).

**Why it is wrong** — Five distinct guards all produce `REFUSE`/exit 2 (unknown-target, self, adoption belt, `beat_or_refuse`, lease, missing done-evidence). Scenario 5's run reaches the adoption belt *before* the safety gate: if `hooks/lib/cc-interactive.sh` fails to source in the environment running the selftest, `beat_or_refuse` refuses with `presence-unprovable` — and the check still shows green, "proving" the done-evidence branch it never reached. That is an assertion that passes for the wrong reason; pinning `reason_kind` (which every refusal already records) is what the records exist to allow, and no scenario uses it.

---

**Summary.** Six defects total. Two can cause materially wrong outcomes: an empty target argument returns a fabricated success (defect 1), and the assignee-adoption identity proof can select — then kill — the wrong process because `ps args=` output cannot distinguish a flag from prose (defect 2). One makes the documented operator interface unusable, contradicting the code's own exemption claim (defect 3). The remaining three are guards or reporting paths that don't do what they claim: never-firing jq fallbacks plus off-contract exit codes on gate failure (defect 4), a collateral-close check bypassed exactly when the target is dead (defect 5), and selftest assertions that can pass via the wrong refusal branch (defect 6). The core act/verify pipeline itself — resolve, identity pin, idempotent path, TERM/KILL escalation, re-observed two-leg verification, and the tri-state pane enumeration — is sound as written; I found no defect in those sections.