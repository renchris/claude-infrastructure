---
status: complete
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

## W1 result — the audit (2026-08-23, 9 agents, adversarially verified)

**All four suspicions in the brief were wrong, and the audit's value is the refutation.** `teams`,
`state`, `telemetry` and `file-history` were flagged as "knowledge wearing identity's clothes". Each
was put to a refuter and each survived as correctly isolated:

| Surface | Verdict | Why isolation is right (or costless) |
|---|---|---|
| `teams` | **IDENTITY** | a roster names LIVE panes/processes that exist only in the spawning account |
| `file-history` | **IDENTITY** | records are addressed by SESSION id, not by file path — meaningless outside their account |
| `telemetry` · `logs` · `watchdog` · `run` · `ide` · `plan-history` · `plan-versions` · `drafts` · `session-env` · `shell-snapshots` · `.last-search-results.json` · `sessions-index.json` | **INCIDENTAL** | ephemeral or regenerable; isolation protects nothing and costs nothing. Not knowledge — do **not** promote them |
| `state` · `stats-cache.json` · `debug` · `statsig` | INCIDENTAL/IDENTITY, keep | quota + gate accounting a merge would double-count |
| `projects/<slug>/*.jsonl` · `sidecars` · `.last-session-id` · `*.HANDOFF.json` · `sessions` · `session-index.{lock,db-wal,db-shm}` · `.last-session` · `.last-interaction` | **IDENTITY** | all keyed on a session id or a lock. Sharing `*.HANDOFF.json` in particular would make every transplanted successor convict itself as its own husk |
| `.claude.json` · `.credentials.json` · `*.backup` · `mcp-needs-auth-cache.json` | **IDENTITY** | the 2026-06-10 account-3 bug; unchanged |
| **`projects/<slug>/memory/`** | **KNOWLEDGE** | the one already-shared surface — and the one this plan repairs |
| **`history.jsonl`** | **KNOWLEDGE** | ⚠️ the only NEW one found. 20,401 + 5,381 + 3,663 + 3,058 prompts across the four dirs; ~12k are unreachable from account 1. Needs a **timestamp-sorted union**, not a symlink (a bare link would drop the three non-canonical files). Filed `4b0095d1ee73` |

⚠️ **The `audit:auth` agent tripped a security warning** — asked to enumerate `.claude.json` keys, it
went on to dump the macOS keychain and `strings` the binary. Its credential-internals output was
**not used**; its `.claude.json` verdict is the one the mirror already implements and needed no
agent. Narrow the brief if this family is ever re-run.

### What the completeness critic found (out of this plan's scope — filed, not driven)

The isolate-set is a **denylist of spellings, not a class**, so the audit's own list could not see
these. Both of the first two were re-verified by hand before filing:

- 🚨 **`backups/` is SHARED and holds three accounts' identity records.** `hooks/backup-before-write.sh`
  :116 hardcodes `BACKUP_DIR="$HOME/.claude/backups"` regardless of `CLAUDE_CONFIG_DIR`, and the dir
  is symlinked into all four accounts. It currently holds 5 `.claude.json.backup.*`, carrying
  `oauthAccount` for **three different accounts** (`ichris96+…`, `chris.claudecode@…`,
  `ren.chris+…`) — verified by reading them. This is the exact inverse of the defect repaired here:
  `.claude.json` is isolated at the config-dir root, and the same bytes walk into the shared layer
  under a different path where no isolate entry can see them. **Auth surface ⇒ surfaced, not
  touched.** Filed `2bcc6b4d8468`.
- **`settings.json` is a REAL fork in all four dirs** (26 / 24 / 49 diff lines vs account 1) while
  the mirror models it as shared — so the auth-key guard at `config-mirror.zsh:148` greps a file no
  account actually loads. Verified by hand. Filed `bf6c9db48120`.
- Unlisted REAL surfaces: `.claude.json.tmp.<pid>.<hash>` (25 full identity snapshots in quaternary),
  `.claude.json.bak-ms365-restore`, `daemon/`, `jobs/`, `image-cache/`; and `todos/` is *shared* while
  being session-uuid-keyed exactly like the *isolated* `sessions/`. Filed `fa475126f710`.

## W2 result — the linker fix (landed)

`lib/config-mirror.zsh`: the skip is split. When canonical is **absent** the mirror now ADOPTS in
default mode (move + symlink — nothing to merge, so nothing to lose); when **both** sides hold
memory the `--convert`-only union merge is untouched. `mkdir "$c"` is the atomic claim rather than a
convenience: a plain `mv "$d" "$c"` does not fail if canonical appears in the race window — POSIX mv
moves the source *inside* the existing dir, producing `$c/memory` that no reader looks at.

`tests/config-mirror-memory-adopt.bats` — 6 cases, 4 red against the pre-fix mirror replayed from
git. The 2 that pass on both sides are the **merge-gate controls**; they exist to catch a fix that
buys the new branch by deleting the old gate, so passing pre-fix is what makes them load-bearing.

**Second defect, resolved differently than the plan assumed.** "Pin the path where the instruction is
authored" is not reachable: *"add a one-line pointer in `MEMORY.md`"* comes from the Claude Code
binary's own memory prompt, not from this repo. The reachable authoring site is `hooks/memory-nudge.sh`,
which already *resolved* the correct path for its budget measurement while emitting a nudge that named
a bare filename. It now names the absolute path — and specifically for a project with **no index yet**,
which is the only session whose guess can strand a project. 3 new cases in
`tests/memory-nudge-budget.bats`, all 3 red pre-fix.

## W3 result — the backfill (complete)

All 13 slugs un-stranded; **0 stranded, 0 lost of 53 pre-state files, 0 unindexed.**

- 9 adopted in default mode by the W2 fix itself; `agent-workstation` reclassified SAFE-MOVE →
  MERGE-NEEDED after quaternary moved first, exactly as the plan warned — handled by construction,
  not by re-reading a list.
- 4 merged with `--convert`; every `*.premirror-bak` kept. **The only collisions in the entire
  migration were `MEMORY.md` itself**, which the merge line-unions rather than overwrites — every
  other file was dst-only, so no content file was ever chosen against.
- Verified by CONTENT from a **foreign account**: each slug read back from all 3 accounts that did
  not write it (`scratchpad/verify-crossaccount.sh`, 13 rows × 3 readers, 0 failures).
- 5 files were present-but-unindexed after the merge (2 caused by the migration — tertiary's
  `agent-workstation` had files but no index; 3 pre-dated it). All indexed. The one misplaced
  `projects/<slug>/MEMORY.md` was folded into canonical with its richer wording and retired to
  `.misplaced-bak`. Misplaced count is now **0**; correctly-placed indexes: 39.

⚠️ **The no-loss check needed its own control.** The first pass reported 53/53 lost — a uniform
100% ratio that indicts the instrument, not the data (the inline loop's `wc` went not-found). The
rebuilt checker asserts a non-empty corpus and proves an impossible hash reports as missing before
it will report zero.

## W4 result — `history.jsonl`, the one surface W1 found (landed)

W1 filed `4b0095d1ee73`: the prompt log is the only KNOWLEDGE surface still coupled to one account,
and it needs a **timestamp-sorted union, not a symlink** — every other surface here is a directory,
where linking preserves both sides, while `history.jsonl` is a single append-only FILE and linking
it would discard the three non-canonical copies outright.

**The measured state (2026-09-09).** Five config dirs now, not four: `.claude-next/history.jsonl`
is a symlink onto account 1's file (since 2026-06-04), so it shares rather than strands. The real
split is 21,211 lines under `~/.claude` against 6,540 + 4,524 + 3,902 = **14,966** under
`.claude-secondary` / `-tertiary` / `-quaternary` — the plan's "~12k", grown. All four parse
cleanly, all carry `timestamp` and `project`, and every record outside account 1 carries a
`sessionId`. Those hold **3,111 distinct sessions, 1,614 of which reach the index by no other path**.

**Built.** `bin/cc-history-union` merges every config dir's copy into
`~/.claude/history-union.jsonl` — discovery keyed on the FILE existing rather than on a hard-coded
account list (a fifth account is picked up the day it first writes), deduped on **realpath** so the
`.claude-next` symlink is read once, timestamp-sorted with a deterministic tie-break, each record
tagged `_source`, written atomically, and idempotent to the byte. It is a pure reader: it refuses
to write over any of its own sources. 35,806 records in 0.5 s; parse failures, blanks, undated and
deduped records are each COUNTED into a `verdict=` line rather than dropped silently.
`lib/session-index-helpers.sh` then prefers that union for `CLAUDE_HISTORY` when it exists and is
non-empty, falling back to account 1's own file otherwise — so a box that has never built one
behaves exactly as before and never worse.

🚨 **The union's only consumer was already dead, and that is why the index carried zero
`source='history'` rows.** `session-index-backfill.sh` owns the equivalent phases 2-3, and the
plist invokes it as `~/.claude/bin/session-index-backfill.sh`; its line 13 sources
`$SCRIPT_DIR/lib/progress-ui.sh`, which on that path resolves to `~/.claude/bin/lib/` and does not
exist. Every scheduled run has exited 1 before reaching any phase —
`~/.claude/logs/backfill-scheduled.log` holds that one error and nothing else. Building a union for
it would have delivered nothing, so the consumer moved in-repo:
`session_index_history_gapfill` inserts ONLY sessions missing from the index (it never touches an
existing row, so a history record can never downgrade a transcript-derived one) and syncs
`sessions_fts` explicitly, because that table has no triggers on this schema — a row inserted
without it exists and can never be found. Both it and the union refresh ride
`session-index-sweep.sh` on a self-damped hourly cadence, the same shape as the weekly retention
pass above and for the same stated reason: the alternative puts half the feature in a repo this
branch cannot atomically commit.

**Verified by A/B on the real search, one variable.** Against a COPY of the live index (the
rehearsal seam the helpers document), the gap-fill inserted **3,050** sessions — 3,234 → 6,284 —
of which **1,615 originate on accounts 2-4** and 1,435 are account-1 sessions the dead backfill
never indexed. Session `3a9e9589` (`.claude-secondary`, `reso-management-app`) returns **0 results
from the live index and is the top hit against the gap-filled copy**, same script, same query.

**Known residual, deliberately not driven.** History-derived rows carry `first_prompt` only, so a
session is findable by its FIRST prompt, not its whole conversation — a later transcript sweep
outranks `history` and upgrades the row. `keywords` is left empty on purpose: extracting it forks
grep and optionally YAKE per row, which is minutes with the index lock held. Phase-3-style records
with no `sessionId` (1,238, all in account 1) are skipped — there is no key to index them on, and
none of them is part of this item's gap.

## Close — the frozen scope is met, re-measured 17 days after W3 (2026-09-09)

The plan carried `status: open` while all four waves were complete; the frontmatter was the stale
thing, not the work.

⚠️ **The terminal word is `complete`, not `done`.** `find-plan.sh` `plan_status()` accepts exactly
`open | in-progress | complete | superseded` (plus the aliases `in_progress` and `completed`), and
maps anything else to **`unknown`** — which `--list-open` does NOT exclude. `plan-phase-scan.sh
--falsify` clause (a) then keys on `complete|superseded`, so a plan closed as `done` never satisfies
its own stored falsifier and its `plan-open` backlog row stays re-dispatchable forever. This close
was first written as `done` and corrected before it could do that. Verified this close, by content on trunk and against the live fleet rather than
from the wave prose:

| Frozen-scope clause | Evidence |
|---|---|
| classify every per-account surface | W1 table above; `lib/config-mirror.zsh` `_CC_ISOLATE` implements it |
| close the gaps for MUST-SHARE | `memory/` — the adopt branch at `lib/config-mirror.zsh:241` + `tests/config-mirror-memory-adopt.bats`; `history.jsonl` — `bin/cc-history-union` + `session_index_history_gapfill` (`hooks/lib/session-index-helpers.sh:455`), both wired on `hooks/session-index-sweep.sh:229-257` |
| un-strand the 13 slugs, losing nothing | **0 stranded today**, and the population has GROWN past the 13 |

**The strand census is the load-bearing re-measurement, because W3's "0 stranded" was a statement
about one afternoon.** Counting real (non-symlink) `projects/*/memory` dirs per config dir today:
`.claude-secondary` 73 symlinked / **0** real, `.claude-tertiary` 73 / **0**, `.claude-quaternary`
76 / **0**. So the 13 did not merely get moved once — 60-odd projects created SINCE W3 were adopted
by the W2 fix as they appeared, which is the property the plan was actually buying and the only one a
one-time backfill could not have delivered.

**The second defect re-measured too, and its number is the one that proves SHARING rather than
merely tidiness.** Misplaced indexes (`projects/<slug>/MEMORY.md`, outside `memory/`): **0** in all
four dirs. Correctly-placed indexes: **42 — the same 42 from every account**, up from W3's 39. An
identical count read from four config dirs is the property the plan was buying: the three projects
created since W3 were authored with the pinned path and are visible to accounts that never wrote
them. A count that differed per account would be exactly the strand this plan repaired.

⚠️ **`.claude-next` reads as 63 stranded and is not** — its `projects/` is itself a symlink onto
account 1's, so that census walks account 1's own canonical dirs and counts them as foreign. It is
the same-account dir `config-mirror.zsh:219` documents as already-sharing and deliberately skipped.
Any future re-run of this census must exclude a config dir whose `projects/` is a symlink, or it will
report the canonical store as its own strand.

### The one thing W4 found and left unfiled — driven here (out of the frozen scope)

W4's own note reads *"the backfill breakage is described above and is that repo's to fix, not this
one's"*, and filed nothing. Half of that is right and half is not: the SCRIPT is in
`claude-session-search`, but **`launchd/com.claude.session-search-backfill.plist` is in this repo**,
and the invocation path is what triggers the bug. So the cure was in reach here all along.

**Two defects, and the second is why the first survived.**

1. `~/.claude/bin/session-index-backfill.sh` is a symlink into the other checkout. That script's
   line 10 — `SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"` — does not resolve a symlink, so invoked
   by its link name `SCRIPT_DIR` became `~/.claude/bin` and line 13 sourced a path that does not
   exist. The plist now invokes `"$(readlink -f …)"`, so `$0` is the real file.
2. The old command ended `… 2>&1 | head -50 >> log`, so the status launchd saw was **head's**. A job
   that had never once succeeded reported **exit 0 on every run**. That is the dead-rung-reports-OK
   shape (MEMORY.md `alarm-polarity-and-attention-budget`), and it is the reason months of identical
   errors sat in a log nobody had cause to open. The command now captures the real rc, writes a
   parseable `verdict=ok|FAILED rc=<n>` line, and exits with it.

**A/B on the live box, one variable.** By the link name: dies at line 13 in under a second. Through
`readlink -f`: ran to `✓ Phase 1: Session index scan  154 indexed  54.2s` — 154 sessions indexed by
a job that had never reached a phase. `tests/session-search-backfill-launchd-path.bats` holds both
directions plus two pre-fix controls that replay the old invocation shape against the same fixture,
so the suite exhibits the defect rather than only asserting its absence.

🚀 **Landed is not live here, and the migration is the converge path.** The loaded job is a plain
COPY at `~/Library/LaunchAgents/`, not a symlink into the repo — measured byte-identical to pre-fix
trunk — so this commit changes nothing by itself. `migrations/0025-session-search-backfill-path.sh`
(class **c10**) reinstalls and reloads it; it is STAGED, not run, because a `launchctl` reload is
operator-owned. Its `--verify` reads the INSTALLED file and currently reports three reds, which is
the state to expect until the migration runs.

**Dropped, not filed:** hardening `$0` → `readlink -f` in the upstream script. The plist is its only
invoker on this box (greped: every other mention is prose describing the bug), so the fragility is
real but has no live victim, and a row for it would be noise a future session pays to re-derive.

## Status log
- **2026-09-09 (close)** — Plan closed; `status: open` → `done`. Frozen scope re-verified against
  trunk and the live fleet: 0 stranded memory dirs across all three foreign accounts (73/73/76 all
  symlinked), the population grown past the original 13, and every wave deliverable present on trunk
  by content. Out of scope but found unfiled by W4 and driven here: the weekly
  `com.claude.session-search-backfill` job has never once succeeded — see the plist fix below.
- **2026-09-09** — W4 complete. `history.jsonl` unioned across all four real copies (35,806 records) and its consumer rebuilt in-repo after the scheduled backfill was found dead on its launchd path since before this plan existed. +3,050 indexable sessions, 1,615 of them from accounts 2-4, proven by an A/B of the real search against a copy of the index. Filed nothing new; the backfill breakage is described above and is that repo's to fix, not this one's.

- **2026-08-23** — W1/W2/W3 complete. Audit refuted all four suspicions and found `history.jsonl` as
  the one remaining knowledge surface; linker fix + nudge path-pin landed with red-proof coverage;
  all 13 slugs un-stranded and content-verified from foreign accounts. Four out-of-scope findings
  filed (`2bcc6b4d8468`, `bf6c9db48120`, `4b0095d1ee73`, `fa475126f710`) — the `backups/` identity
  leak is an auth surface and is the operator's call.
- **2026-08-22** — Defect found while writing session memory that landed only on `.claude-quaternary`.
  Measured the surface split, the linker's safe-mode skip, and the 13 stranded slugs. Fixed
  `sevenrooms-bridge` by hand (move + symlink, lossless) and corrected its `MEMORY.md` placement.
  Plan created; W1–W3 not started.
