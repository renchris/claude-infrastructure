---
status: open
---

# Account-agnostic agent state — audit + repair

> **Scope (frozen):** classify every per-account surface under `~/.claude*/` as MUST-ISOLATE /
> MUST-SHARE / SAFE-EITHER; close the gaps for MUST-SHARE; un-strand the 13 projects whose memory
> is currently invisible to the other accounts, losing nothing on either side.
>
> **Why it matters (operator, 2026-08-22):** *"we use accounts indiscriminately cycling between for
> usage"* — so any KNOWLEDGE surface coupled to one account is silently lossy. The operator does not
> choose an account per project; the router picks by live quota headroom.

## Phase 0 — orchestration

| Wave | Locus | Why |
|---|---|---|
| **W1 audit** — classify every surface | **S** (dispatched session) | Read-heavy across 4 config dirs + the mirror SSOT; the classification is the deliverable and must not be a lead's guess |
| **W2 linker fix** — the safe-move gap | **S** | One file (`lib/config-mirror.zsh`), needs its own bats coverage; the land gate is strict here |
| **W3 backfill** — un-strand 13 slugs | **S**, AFTER W2 | Data migration over the operator's live memory; must run once, verified, with a reversible step |

Lead context budget: the lead holds the classification verdict and the go/no-go on W3 only.
Succession point: after W2 lands, before W3 touches real memory.

## The measured state (2026-08-22 — do not re-derive, verify if stale)

**The architecture is already right, and my first read of it was wrong.** `lib/config-mirror.zsh`
:153-180 implements per-slug memory sharing deliberately: `projects/` is ISOLATED (transcripts are
per-account, correctly) while `projects/<slug>/memory/` is symlinked to account 1's canonical copy.
The mirror's own SessionStart banner states the intent — *"knowledge-layer mirror re-asserted
(auth/.claude.json/sessions isolated)"*.

Surfaces, measured:

| | Surface | Today |
|---|---|---|
| **SHARED** (symlink → `~/.claude`) | `memory` `skills` `hooks` `commands` `agents` `scripts` `bin` `todos` `tasks` | correct |
| **ISOLATED** (real per account) | `projects` `sessions` `session-env` `shell-snapshots` `history.jsonl` `statsig` `telemetry` `teams` `state` `ide` `file-history` | intent is auth/session identity — **W1 must confirm each is deliberate, not incidental** |

### The defect: safe mode never converts, so a new project strands forever

```zsh
if [[ -d "$d" && ! -L "$d" ]]; then     # dst has its own real memory
  (( convert )) || continue             # safe mode: don't merge under a live session
```

`config-mirror-assert.sh` runs the mirror in **default (safe) mode** at SessionStart. So:

1. session starts on a non-primary account; the slug exists nowhere → nothing to link;
2. the session writes memory → `projects/<slug>/memory/` becomes a **real dir**;
3. every later run sees a real dir and `continue`s — **forever**, waiting for a `--convert` that no
   automation ever issues.

The skip is right for the genuinely risky case (both sides hold memory → needs the union merge).
It is **wrong for the case where canonical does not exist at all**: there is nothing to merge, so a
move-and-link is lossless. The code lumps the two together.

Proven by hand on `sevenrooms-bridge` (2026-08-22): `mv` to canonical + symlink back made three
stranded memories visible from every account, with the writing session still reading them live.

### The 13 stranded slugs

**SAFE-MOVE** (canonical absent — pure move, no merge): `agent-workstation` (quaternary),
`emilia-resume`, `marko-resume`, `renchris-marquee` (secondary), `agent-secrets`,
`agent-workstation` (tertiary), `dj-software`, `music-links`, `technical-analysis` (tertiary).

**MERGE-NEEDED** (both sides hold memory — union required):
`chris-capital-group-contributions`, `doc-classifier`, `reso-web-app` (secondary),
`mistral-4-fable-ocr` (tertiary).

🚨 **`agent-workstation` is stranded on TWO accounts at once.** Whichever moves first becomes
canonical, and the second then reclassifies SAFE-MOVE → MERGE-NEEDED. W3 must re-evaluate per slug
*after each move*, never from a list computed up front.

### A second, smaller defect: MEMORY.md placement is unpinned

The canonical layout is `projects/<slug>/memory/MEMORY.md` — **32 projects** use it. Two do not,
and one was written by this session, because the memory instructions say "add a one-line pointer in
`MEMORY.md`" without a path. The mirror's merge logic only knows `$d/MEMORY.md` *inside* `memory/`,
so an index written one level up is invisible to the merge **and** to the mirror. W2 should pin the
path where the instruction is authored, not only fix the survivors.

## Wave briefs

**W1 — audit.** For each ISOLATED surface, answer with evidence: does isolation protect an identity
(auth, a session id, a pane registry) or is it incidental? `teams`, `state`, `telemetry` and
`file-history` are the suspicious ones — a teammate roster and accumulated telemetry look like
knowledge, not identity. Output: the table above, completed, one line of justification per row.

**W2 — linker fix.** Split the skip: when `$c` does not exist, MOVE `$d` → `$c` and symlink (safe in
default mode); when both exist, keep the current `--convert`-only merge. Add bats coverage for both
branches plus the two-accounts-one-slug ordering case. Follow the repo's gate — run
`scripts/ship-land.sh --precheck` BEFORE committing (this session landed a commit gate-red by
running only bats; shellcheck is part of the gate).

**W3 — backfill.** Un-strand all 13, re-evaluating per slug after each move. Every MERGE-NEEDED slug
keeps its `*.premirror-bak`. Verify each by reading the memory back from a *different* account than
the one that wrote it.

## Status log

- **2026-08-22** — Defect found while writing session memory that landed only on `.claude-quaternary`.
  Measured the surface split, the linker's safe-mode skip, and the 13 stranded slugs. Fixed
  `sevenrooms-bridge` by hand (move + symlink, lossless) and corrected its `MEMORY.md` placement.
  Plan created; W1–W3 not started.
