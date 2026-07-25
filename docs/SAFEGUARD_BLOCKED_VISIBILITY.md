# Safeguard-Blocked Session Visibility + Recovery

**Scope (frozen):** A fired /handoff peer session can be silently dead-on-arrival when the
model's **content safeguards** refuse its first turn. It churns ~3 s, then sits IDLE at an
empty prompt. Nothing detects it; the originator only learns of it if a human eyeballs the
pane. Build detection → surfacing → (opt-in) recovery so such a session is caught, surfaced to
its originator, and can be closed + re-fired on a different model.

**Live instance that motivated this (2026-07-25):** a Fable design session fired via /handoff
hit *"API Error: Fable 5's safeguards flagged this message … Claude Code can't respond to this
request with Fable 5"*, churned, and idled. Pane `725A269A-BEC0-4FCA-8B85-BC359E73579A`,
worktree `.worktrees/wt-pool-2`, account `claude-quaternary`, fired by `05B1B368-…`.

## The gap (why it was invisible — and WORSE than invisible)

Ground truth from the real blocked transcript (`a402c9f3-….jsonl`), tail:

| # | record | note |
|---|--------|------|
| … | `{type:"assistant", isApiErrorMessage:null, content:[{type:"thinking", thinking:""}]}` | **empty** thinking block — an aborted turn |
| … | `{type:"system", subtype:"model_refusal_no_fallback", content:""}` | **structural refusal marker** |
| … | `{type:"assistant", isApiErrorMessage:true, content:[{type:"text", text:"API Error: Fable 5's safeguards flagged this message … can't respond to this request with Fable 5 …"}]}` | the refusal text |
| … | `system(turn_duration)`, `bridge-session`, `last-prompt`, `file-history-snapshot` | trailing, non-conversational |

`cc-classify` (bin/cc-classify) reads `last_assistant_ts` which **excludes** `isApiErrorMessage`
but **not** the empty-thinking block — so it *does* compute an idle. That fired peer in a
worktree therefore classified as **`finished-teammate`** and, once idle past the reaper's settle
window, was **auto-reaped as if it had completed its work** — when it did *nothing*. The brief
silently never runs and the originator is never told. Detection must fire **before** that
misclassification.

## Detection signals (both robust)

1. **Structural (primary corroborator):** a `system` record with
   `subtype == "model_refusal_no_fallback"` in the transcript tail. Deterministic.
2. **Text (the required configurable matcher, case-insensitive):**
   an `isApiErrorMessage:true` assistant record whose text matches any configured signature.
   Defaults: `safeguards flagged this message` · `can't respond to this request with` ·
   `may flag safe, normal content`.

**Transient churn vs. STALL:** the refusal must be the **terminal conversational event** — no
*real* user prompt or *real* (non-error, content-bearing) assistant turn appears AFTER the last
refusal record. If a later real turn exists, the session recovered → NOT blocked.

## CONTRACT (SSOT — every component depends on exactly this)

### C1 — `cc-classify` new cause `safeguard-blocked`
- Placed in the decision tree **after `crashed`/`rate-limited`, before `active` and the
  finished/finished-teammate branches** — so it beats both the `active` fail-safe (no readable
  assistant ts) and the `finished-teammate` misclassification.
- Idle is computed from the **refusal record's own timestamp** (independent of
  `last_assistant_ts`), so it works even with no prior assistant turn.
- Fires only when the refusal is terminal (per above) AND idle ≥
  `CC_CLASSIFY_SAFEGUARD_IDLE_S` (default 120 — brief transient tolerance).
- NEVER-REAP. It is a surface cause.
- JSON output adds two fields when (and only when) the cause is `safeguard-blocked`:
  - `blocked_model` — best-effort model name parsed from the refusal text (e.g. `Fable 5`), else `null`.
  - `refusal` — the refusal text, truncated to 240 chars, single-lined; else `null`.
- Env knobs: `CC_CLASSIFY_SAFEGUARD_SIGNATURES` (`|`-separated, case-insensitive),
  `CC_CLASSIFY_SAFEGUARD_SUBTYPE` (default `model_refusal_no_fallback`),
  `CC_CLASSIFY_SAFEGUARD_IDLE_S`.

### C2 — `cc-reaper` disposition of `safeguard-blocked`
- Added to the **surface** set (never reap). On `--reap`, for each `safeguard-blocked` session:
  1. **Notify the ORIGINATOR** — `firedBy` read from the fired marker
     (`$CC_FIRED_DIR/<pane>.json`), via `cc-notify <firedBy> "<msg>"`, **damped** (one send per
     `(pane, cause)` — same D7 damp as the desk page). Message = one glance: fired slug, account,
     blocked model, refusal text, recovery command.
  2. **Operator-board row** — an IDL row (`$CC_REAPER_IDL`) `kind:"safeguard-blocked"` with
     `{pane, name, account, blocked_model, refusal, firedBy, recover_cmd}`.
  3. **Desk page** — the existing damped desk page (same cadence as other surface causes).
  4. **Opt-in auto-recovery** — only if `CC_REAPER_SAFEGUARD_AUTORECOVER=1` (default `0`/OFF):
     invoke `cc-recover-safeguard <pane> --execute`. Default: surface only, desk decides.
- Never auto-reaps `safeguard-blocked` regardless of the autorecover flag (recovery = re-fire +
  sanctioned self-close, not a reap).

### C3 — fired-brief persistence (`scripts/handoff-fire.sh`)
- At fire time, alongside `mark_fired_peer`, persist the **final fired prompt** (post-trailers)
  to `$CC_FIRED_DIR/<pane>.prompt`. This is the robust brief source for recovery. Additive,
  best-effort, never blocks a fire.

### C4 — `bin/cc-recover-safeguard` (new)
`cc-recover-safeguard <blocked-pane> [--model M] [--dry-run|--execute] [--originator UUID]`
- Brief source: `$CC_FIRED_DIR/<pane>.prompt` if present, else the blocked transcript's first
  non-meta user message (verbatim), else refuse loudly.
- **Model swap:** target model defaults to `opus`; if the blocked model *was* opus, falls to
  `sonnet`. Never re-fires on the model that was blocked.
- Prepends a short re-route note: *"⟳ RE-ROUTED: the prior model's safeguards declined this
  brief; re-firing on <model>. Original brief follows verbatim."*
- Constructs TWO sanctioned commands:
  1. **Re-fire:** `handoff-fire.sh --prompt-file <reworded-brief> --model <target> --cwd <blocked-cwd>`.
  2. **Sanctioned self-close of the blocked pane:** run from the blocked cwd (so the dirty-guard
     checks the right tree): `handoff-fire.sh self-close --session-id <blocked-pane>
     --successor <new-pane> --dirty-owner successor` (succession = the re-fired session), or
     `--terminal` if the re-fire could not establish a live successor.
- `--dry-run` (**default**) prints both commands + the carried brief and exits without side
  effects. `--execute` runs the re-fire, waits for the new pane's claude to be live, then runs
  the self-close. NEVER a raw it2 close, never a hand-typed /exit, never a composer keystroke.

### C5 — `bin/cc-blockers` (new, read-only)
One-glance operator view: renders the `kind:"safeguard-blocked"` IDL rows —
`SLUG · ACCT · MODEL · REFUSAL · RECOVER-CMD`. `--json` for machine reads. Read-only; no actions.

## Phase 0 — orchestration decision (single coherent implementer)

This is **one tightly contract-coupled feature**: the classify cause, the reaper disposition,
and the recovery helper share the SSOT above; the detection logic, decision-tree placement, and
self-close targeting are subtle **safety** code (it governs auto-close of real sessions). The
project's "depth-coordination / one coherent task → single agent" carve-out applies: the lead
holds the complete, ground-truth-verified design (the real blocked transcript, exact record
shapes, self-close semantics) and verifies each component against that ground truth as it lands.
Implemented as **atomic commits per component**, `bats tests/` gating each; if lead context runs
short, `/handoff` with this doc as the contract. Rationale recorded here per Session-Close G1.

**Sequence** (each an atomic, independently-safe commit):
1. C1 cc-classify detection + `tests/cc-classify.bats` (safe alone: reaper treats an unknown
   surface cause as never-reap "keep", so the misclassification-into-reap is already closed).
2. C2 cc-reaper disposition + `tests/cc-reaper.bats`.
3. C3 handoff-fire.sh brief persistence + `tests/handoff-fire*.bats`.
4. C4 cc-recover-safeguard + `tests/cc-recover-safeguard.bats`.
5. C5 cc-blockers + `tests/cc-blockers.bats`.

## Test plan (bats — the gate is `bats tests/`)
- **Detection:** real-block fixture (literal refusal text + `model_refusal_no_fallback`) → blocked;
  normal completion → not blocked; transient-then-recovered (refusal then a real user+assistant
  turn) → not blocked (no false positive); a fired-peer-in-worktree block that previously read
  `finished-teammate` now reads `safeguard-blocked`.
- **Recovery command construction:** model swap (target ≠ blocked model), succession statement
  present (`--successor`/`--terminal`), brief carried verbatim, re-route note prepended, dry-run
  emits both sanctioned commands and touches nothing.
- **Reaper disposition:** `safeguard-blocked` is surfaced, never reaped; originator notified
  (firedBy), IDL row written; autorecover OFF by default (helper not invoked).
- **Board:** `cc-blockers` renders a safeguard row; empty when none.

## Status — LANDED (2026-07-25)

All five components implemented + bats-tested, each an atomic commit, gate `bats tests/` green:

| # | Component | Commit | Tests |
|---|-----------|--------|-------|
| C1 | `bin/cc-classify` — `safeguard-blocked` cause | `f0cf468` | +8 in `cc-classify.bats` (52 total) |
| C2 | `bin/cc-reaper` — surface disposition | `7507dc6` | +5 in `cc-reaper.bats` (70 total) |
| C3 | `scripts/handoff-fire.sh` — brief persistence | `e4de989` | +2 in `fire-engagement.bats` (23 total) |
| C4 | `bin/cc-recover-safeguard` (new) | `f237f37` | 12 in `cc-recover-safeguard.bats` |
| C5 | `bin/cc-blockers` (new) | `dbc7646` | 8 in `cc-blockers.bats` |

**C1 verified against the REAL blocked transcript** (`a402c9f3`): idle≥120 → `safeguard-blocked`,
`blocked_model:"Fable 5"`, refusal captured; idle<120 → `active` (transient tolerance).
**C4 dry-run verified against the REAL blocked pane** `725A269A`: brief carried verbatim,
model swap opus≠Fable, sanctioned self-close constructed.

### Implementation decisions / learnings (durable)
- **Re-fire uses `--no-self-retire`**: the carried brief (persisted `.prompt` or transcript
  first-user-message) is the *post-trailer* payload — it already holds the original fire's
  self-retire + notify-back directives, so re-adding would duplicate them. The recovered session
  self-retires + pings the same originator via the carried directives.
- **New bins auto-deploy**: `install.sh` globs `"$REPO_DIR"/bin/cc-*` (line ~256) → `cc-recover-safeguard`
  + `cc-blockers` symlink into `~/.claude/bin/` on the next `install.sh` run. No registration edit needed.
- **macOS bash 3.2 quirk**: a literal apostrophe (`can't`) inside `"${VAR:-default}"` breaks parsing
  → build the signature default in a single-quoted var first (`_SG_SIG_DEFAULT`), then reference it.
- **jq `$arr | index(.)` rebinds `.`** to the array — bind the pane to a named var
  (`.paneUUID as $pu | … ($seen | index($pu))`) for the new-pane discovery in `--execute`.

### Operator activation (C10 — agent stages, operator runs)
1. **Deploy the new bins**: run `install.sh` (globs `bin/cc-*` → `~/.claude/bin/`), so `cc-blockers`
   and `cc-recover-safeguard` are on PATH and the reaper can resolve the recovery helper.
2. **(Optional) enable auto-recovery**: set `CC_REAPER_SAFEGUARD_AUTORECOVER=1` in the reaper's
   launchd env ONLY if the desk wants automatic re-fire+close. Default OFF = surface-and-decide.
Until step 1, detection + originator/desk paging + the board row all work from the repo checkout;
only the operator-run `cc-blockers` glance and opt-in auto-recovery need the deployed symlinks.
