# FRONTIER_HOLES — claude-infrastructure

Unknown-unknown ledger for the frontier tier (currently Fable 5). Capture holes here without
burning frontier tokens inline; `/frontier-run` spends the window on them. INTEGRATE — never
overwrite history. Statuses: `OPEN` → `IN-PANEL <date>` → `CONFIRMED-BY-PANEL` / `REFUTED` /
`SOLVED-PATH-KNOWN` / `ESCALATED`; closed holes move to `## Resolved` with one-line provenance.

---

## Open

_(none)_

## In-Panel

### H-DSH-1 — Deterministic recycle ACTUATION (advisory → fire) · IN-PANEL 2026-07-19
- **Confidence: high** (grounded in disk truth this session)
- **Seam:** `hooks/waiting-recycle.sh` (detection+advisory) ⟷ `scripts/handoff-fire.sh --recycle`
  (actuator). Today the hook only ADVISES the model; it has fired **0 / 2419** times in prod (the
  fire path is unproven). The deliberate design ("only the model can capture live state") is the
  wall the task wants to move past.
- **Question:** Can a deterministic mechanism (hook or hook-armed sidecar) FIRE
  `handoff-fire.sh --recycle` WITHOUT depending on the model noticing/complying, while preserving
  the actuator's `/exit`-queue-boundary timing semantics (designed around being the model's OWN
  Bash tool call — see `handoff-fire.sh:648-658`, the catnav incident)? Which channel/architecture:
  (i) hook execs it directly, (ii) armed-payload sentinel the model refreshes while healthy + a
  dumb actuator fires it (session-continue.sh pattern), or (iii) advisory-first with deterministic
  fire on K-ignored escalation? Where does state-capture live so the successor is never task-less?

### H-DSH-2 — The safe-fire GATE (idle vs active-coordination; no-double-fire) · IN-PANEL 2026-07-19
- **Confidence: high**
- **Seam:** the FIRE predicate's SAFE clause (`waiting-recycle.sh:188-196`) vs the desk's true
  coordination state. Current proxy = clean-git-tree AND no-open-decision-in-last-message. That
  misses "mid-merge between clean states" and "a sub-session is BLOCKED waiting on THIS desk."
- **Question:** From DISK signals only (telemetry `/tmp/cc-telemetry`, `~/.claude/wait-contracts`,
  live-session registry, cc-board, roles, pending pings), how does a hook distinguish
  recycle-SAFE idle-babysitting (watch state reconstructible → recycle desirable) from
  recycle-UNSAFE active-coordination (mid-wave dispatch/merge, or a sub-session blocked on this
  desk's reply)? And how is no-double-fire guaranteed across the recycle boundary (two panes, the
  cooldown/arm keying, the successor inheriting the arm)?

## Resolved

_(none yet)_

## Seam Registry

| Seam | Components | Last swept | Depth | Verdict |
|---|---|---|---|---|
| desk self-recycle spine | `waiting-recycle.sh` · `handoff-fire.sh --recycle` · `/tmp/cc-telemetry` · `wait-contracts` | 2026-07-19 | design panel (H-DSH-1/2) | in-panel |

## Campaign Candidates

_(none)_
