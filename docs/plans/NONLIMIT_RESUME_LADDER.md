# Non-limit resume + the Opus→Fable→Teams escalation ladder

Opened 2026-09-09 from an operator ask in session `d79f408b`. **Status: RESEARCH CAPTURED, design
NOT started.** Implementation is deliberately withheld pending a Fable 5.1 discovery pass — see
§ Phase 0.

`Scope (frozen):` establish whether `/limit-recover` covers NON-quota interruptions (network drop,
reconnect, agent stall) with the same no-partial-results discipline; capture the disk truth
exhaustively; hand the design to Fable 5.1 rather than implementing at Opus reach; and separately
investigate making the three-stage Opus→Fable→Teams ladder the CLAUDE.md default.

---

## Phase 0 — Agent Team Orchestration (EXECUTION LOCUS PER WAVE)

| Wave | Locus | Model / effort | Why |
|---|---|---|---|
| W0 research capture | **L** (lead-inline, DONE) | Opus 5 / high | Disk-truth measurement is decomposable but small; the lead already held the audit context. Capacity gate refused fan-out (13 sessions mid-turn) and instructed serial execution. |
| W1 discovery | **S** — self-recycle | **Fable 5.1** / xhigh | Operator directive: the reachable fruit is picked; what remains is the unknown-unknown class Opus 5 is blind to. NOT a re-verification of W0 (that would be banned ceremony) — it is design of what W0 could not reach. |
| W2 implementation | **S** → in-session teammates | Lead Opus 5 / max; assignees Opus 5 / **stepped-down** effort | Implementing a SOLVED design needs less intelligence than discovering an unsolved one. |
| W3 ladder-as-default | **S** — separate session | Opus 5 / high | Distinct subject (CLAUDE.md policy), must not share W1's context. |

**Lead context budget:** W0 lead closed at ~50%; succession point is this document.

---

## The task table — THIS IS THE SHARED LIST

`TaskCreate`/`TaskList` are gated behind `CLAUDE_CODE_ENABLE_TODO_TOOLS=1`, unset in all five config
dirs (migration `0022`, operator-owned). Until it lands, per global CLAUDE.md, this table is the list.
Nothing here may be held in a context window.

| # | Task | State | Owner | Notes |
|---|---|---|---|---|
| T1 | Establish whether the audit engine is limit-specific | **DONE** | W0 | It is not. See § Finding 1 |
| T2 | Establish whether the fleet census is limit-specific | **DONE** | W0 | It was. Fixed + verified, `3a63bfd43` |
| T3 | Capture exact on-disk record shapes for network/stall deaths | **DONE** | W0 | § Finding 2 |
| T4 | Measure the live blast radius | **DONE** | W0 | 29 network vs 35 limit; 6 live panes |
| T5 | Fable 5.1 discovery pass on 100th-pct design | **OPEN** | W1 | Brief in § Handoff brief |
| T6 | Implement the design via Agent Teams | **BLOCKED on T5** | W2 | Do not start before T5 returns |
| T7 | Investigate the ladder as CLAUDE.md default | **OPEN** | W3 | Separate session, § W3 brief |
| T8 | Resume the 6 live network-blocked panes | **OPEN** | operator/W2 | List in § Finding 4 |

---

## Finding 1 — the audit engine was ALREADY interruption-agnostic; only its trigger was quota-shaped

`lr-audit.py` classifies each delegated unit from disk terminal state, and the verdict never consults
the *reason* for the death:

- `slot_verdict` (`:279-282`) returns **NULL on ANY `api_error`**. `classify_limit_text` is called
  only to LABEL the evidence string — it does not gate the verdict.
- A non-limit error is classified `other_api_error` and **excluded from `limit_events`** (`:336`,
  `:662`). So a network kill yields **`limit_events: []` and a fully correct gap ledger**. Reading the
  empty event list as "nothing was interrupted" is the trap.
- Bare subagents route through the same predicate (`:534`); teammates via `last_kind == "api_error"`
  → NULL/PARTIAL (`:868-870`).
- Workflow runs are discovered from BOTH `session_dir/workflows/wf_*.json` and
  `session_dir/subagents/workflows/wf_*` (`:1322-1329`), so a stalled Dynamic Workflow is reachable.

**Consequence:** the whole audit → forced re-run → re-audit fixpoint, the verdict table, the Teams
member table and Iron rules 1-6 already apply verbatim to a network death. What does NOT apply is
Mode:recover step 1 (headroom check, wait-vs-switch, reset time), handoff/transplant, fleet
transplant, and the login-cliff branch — all of which presuppose the account is the problem.

**So the gap was DISCOVERY, not capability.** The command's frontmatter `description:` names only
quota and auth-cliff triggers, so "(Reconnected to internet, continue)" loads none of it, and the
operator lands in exactly the failure the command's own opening paragraph refutes: *the model
reconciles from CONTEXT, which still holds the pre-kill narrative and reads plausible, satisfices on
the units it remembers, and smooths the gaps into the conclusion.*

## Finding 2 — measured record shapes (quoted, not inferred)

**Network death**, `.claude-tertiary/projects/…wt-2ee30f87c370/137f37fe-….jsonl` line 1098:

```json
{"type":"assistant","message":{"model":"<synthetic>","role":"assistant",
 "content":[{"type":"text","text":"API Error: Can't reach the API server — check your internet or DNS (ENOTFOUND)"}]},
 "error":"server_error","isApiErrorMessage":true,"version":"2.1.260"}
```

The envelope is **identical to a cap's**. `model:"<synthetic>"` + `isApiErrorMessage:true` is the
structural discriminator that makes a text-widened predicate safe: a session merely *discussing*
ENOTFOUND in prose (this repo does constantly, including the session that wrote this document) is not
a synthetic api-error record and cannot match.

**Workflow stall** arrives differently and this matters: it is NOT an assistant api-error at all. In
`52e35019` (the operator's screenshotted pane) it lands as a `queue-operation` record followed by a
**`type:"user"` `<task-notification>`** carrying an `<output-file>` pointer. Operator-visible text:
`agent stalled on all 6 attempts (no progress for 180000ms each)`. The subagent variant is
`Agent stalled: no progress for 600s (stream watchdog did not recover)`.

⚠️ **`stalled` / `stream watchdog` appear NOWHERE in `scripts/limit-recover/`.** A stalled workflow
is therefore unmodelled at the census layer, and the lead's context simply holds "the workflow
failed" — which is precisely how the screenshotted session ended up parked at `> wait for it to
finish` for 11h 53m.

## Finding 3 — the census was blind, and is no longer (T2, landed `3a63bfd43`)

`lr-fleet.sh:86` gated every row on `LIMIT_RE` as the LAST assistant word. Six panes killed by one DNS
outage produced `(no limit-blocked session anywhere)`. Widened to a `BLOCK_RE` union keeping the
structural envelope, with `KIND` as a first-class column because it decides which recovery is *legal*:

| kind | recovery |
|---|---|
| `limit` | account out of quota ⇒ transplant (`--recover`) |
| `network` | account is FINE, pane usually still alive ⇒ **RESUME-IN-PLACE**; a transplant would spend an account move on a problem that no longer exists |

`--recover` and `--enqueue` both refuse network rows by default rather than "helpfully" moving them.

## Finding 4 — live blast radius, measured 2026-09-09

**29 network-blocked vs 35 limit-blocked sessions.** The network half was entirely invisible before
T2. Six distinct live panes are resumable in place right now:

```
553ff801  next   716  claude-opus-5/high  /Users/chrisren/Development/.worktrees/classify-beacon
fd1ab61c  next   694  claude-opus-5/high  /Users/chrisren/Development/.worktrees/reland-rowkey
2878d5d2  next   679  claude-opus-5/high  /Users/chrisren/Development/claude-infrastructure
9a547759  next3  719  claude-opus-5/high  /Users/chrisren/Development/.worktrees/rules-union-merge
bfe42820  next3  715  claude-opus-5/high  /Users/chrisren/Development/.worktrees/wt-09f8bb68dbf3
d85264e5  next4  672  claude-opus-5/high  /Users/chrisren/Development/claude-infrastructure
```

## Finding 5 — a hazard the quota path never had to model

A quota kill ends the session. **A network drop usually does not** — the TUI stays alive and a
delegated unit may still be running or retrying past the outage. The audit gives *teammates* a
`RUNNING` verdict for exactly this (active < 5 min ⇒ never respawn over a live member). **Bare
subagents and workflow slots have no `RUNNING` verdict**, so a still-live one reads PARTIAL and a
blind re-run doubles it. Any resume design must resolve this before it re-fires anything.

---

## Handoff brief — W1, Fable 5.1 discovery (T5)

Everything above is the *reachable* fruit, found at Opus 5 / high. **Do not re-verify it** — that is
banned ceremony. Design what it could not reach:

1. **The RUNNING gap (Finding 5).** What is the correct predicate for "this non-teammate unit is
   still alive" when the harness gives no liveness signal, the process may be mid-retry, and jsonl
   mtime is a stamp written at *record* time? Prior art in this repo says a stamp cannot be a
   liveness proxy and orphanhood is not discriminating.
2. **Stall is a third class, not a network variant.** A 6×180s stall means the harness already
   exhausted its own retries. Is re-firing correct, or does it reproduce the stall? What
   distinguishes a stall that will clear from one that is deterministic?
3. **The trigger problem is general.** Every future non-quota death class will be invisible the same
   way. Is there a formulation that does not enumerate spellings? (This repo's own rule: a denylist
   enumerates spellings, not the class.)
4. **Should this be a mode of `/limit-recover` at all**, or is `limit-recover` now a misnomer for a
   general *interrupted-work recovery* command?
5. **The operator's actual ask is prompt-free automation.** They currently type a paragraph. What is
   the design where a reconnect needs ZERO paragraph — and what is the failure mode of making it
   automatic?
6. **Unknown-unknowns.** What is wrong with this framing that Opus 5 could not see?

## W3 brief — the ladder as CLAUDE.md default (T7)

Operator directive, verbatim intent: research exhaustively at Opus 5, distill to a document, recycle
into **Fable 5.1** for the unreachable class, then recycle into **Agent Teams** with an Opus 5 max
lead and stepped-down-effort Opus 5 assignees — *"this should be the default behavior out of the box
with CLAUDE.md without having to explicitly prompt."*

Open questions: how does this interact with the existing § Frontier Tier Routing (which today makes
Fable **opt-in only** and says the lead never runs on it)? What is the trigger predicate for "this
problem is generator-class enough to earn the ladder" vs routine work where the ladder is pure cost?
Does `/frontier-campaign` already encode part of this?
