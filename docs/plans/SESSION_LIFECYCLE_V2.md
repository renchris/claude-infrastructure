---
status: open
---

# SESSION LIFECYCLE & SUCCESSION — V2 (ground-up rebuild, row 2)

**Scope (frozen):** session lifecycle & succession achieves fire→engaged ≤60s p95 and ZERO
illegible pane exits, under the standing constraint that a watched pane must never vanish without
its continuation being visible — measured, landed, and verified by disk-truth acceptance reads.

Methodology: the `ground-up` skill. Exemplar: [LAND_PIPELINE_V2.md](LAND_PIPELINE_V2.md).
Map row: [GROUND_UP_REBUILD_MAP.md](GROUND_UP_REBUILD_MAP.md) row 2.
Inherited seam item: **M3 close-path drain-or-reroute**, specified in
[CROSS_SESSION_COMMS_V2.md](CROSS_SESSION_COMMS_V2.md) §4 M3 + §8, ruled row 2's on 2026-07-29.

**Owned surfaces:** `scripts/handoff-fire.sh` (fire, `--recycle`, `self-close`, engagement
verification), the `/handoff` skill + command, warm worktree claim, pane succession legibility.

---

## Phase 0 — Agent Team Orchestration

Sequenced deliberately as **lead-only, no teammates.** This is not the default and the reason is
recorded so it is not mistaken for an oversight:

1. **The whole rebuild is ONE file's control flow.** Every mechanism below lands in
   `scripts/handoff-fire.sh` (2,652 lines) — one lifecycle record writer, one category classifier,
   one engagement oracle, one close actuator, all reading each other's state. Disjoint file
   ownership — the precondition for Agent Teams — is unconstructible here. Two teammates in this
   file is the same-hunk overwrite hazard the campaign already paid for
   (`GROUND_UP_REBUILD_MAP.md` learnings 2026-07-29, 581 landed lines saved only by the
   read-before-write guard).
2. **This row's own subject matter is the hazard.** An Agent-Team lead that dies orphans its
   assignees with **no sanctioned resolution path** — failure mode F1 below, the row's headline
   defect. Spawning a team to fix the orphaned-assignee gap risks creating orphaned assignees.
   Read-only researchers carry no such risk: they hold no worktree and write no file.
3. **Read-only fan-out WAS used** — Phase 1's three prescribed axes (archaeology · telemetry ·
   seams), which is the skill's Phase-1 shape, not Phase-4 implementation.

Landing cadence: **continuously, one atomic commit per logical task, landed via the project-local
`scripts/ship-land.sh` as each lands.** Row 3 lost an hour by landing zero; row 5 survived an
unexplained lead death with zero loss because it had landed 11 times. Continuous landing is this
campaign's crash insurance, and this row is the one whose subject is crashes.

---

## §1 Phase 1 — the standing-constraint cell, RE-DERIVED

The map cell for row 2 read: *"a watched pane must never vanish illegibly."* Per the map's own
binding learning, that cell is **the prior session's hypothesis, not a fact**. Row 5's was
FALSIFIED; row 3's was CONFIRMED-BUT-RENAMED.

### Verdict: **CONFIRMED-BUT-RENAMED** — the principle holds; the *binding* failure has moved to its mirror image.

**What confirms it.** The constraint is real and canonical, stated in the
`handoff-succession-legibility` memory from the 2026-07-13 23:03 incident: *"an operator judges a
handoff by what their EYES land on when a pane vanishes. A close whose continuation is not visible
is indistinguishable from a crash, no matter how clean the mechanics were."* That is the correct
principle and nothing in Phase 1 contradicts it.

**What renames it.** The illegible-**exit** half is already heavily enforced — `self-close` carries
**four** independent blocking gates (origin `:1391`, live-teammate `:1425`, successor-liveness
`:1444`, successor-engagement `:1463`) plus a dirty-tree refusal `:1476`. Measured consequence: the
campaign's last 24h produced **zero** illegible exits and **eleven** panes that could not exit at
all. Every incident in `GROUND_UP_DISPATCH.md` §incidents is a pane that **refuses to vanish** or
that **persists in a state the operator cannot classify** — a dead lead's pane sitting at
`Resume this session with: claude --resume …`, seven-then-eleven orphaned assignees with no
resolution path, a teammate parked forever on *"Waiting for team lead approval"* addressed to a dead
process.

This is the row-5 trap in a different costume, and it must be named plainly: **"zero illegible pane
exits" currently reads zero BY CONSTRUCTION, because the gates refuse nearly everything. A metric
satisfied by a gate that refuses is not a performance result.** Designing harder against illegible
exits would be the old design with bigger constants — exactly what Phase 2 forbids.

**The renamed constraint, which the design is built against:**

> **A pane's lifecycle state must be legible at all times — including, and especially, when it does
> NOT vanish.** A pane that cannot retire is as illegible as one that vanishes silently, and it is
> strictly more expensive, because it also consumes the shared box.

The cost term is measured, not asserted: pane count — not agent compute — is the campaign's binding
throughput constraint (`GROUND_UP_DISPATCH.md`: 29 live panes, iTerm2 itself at ~128% CPU while all
11 idle orphan agents together drew **4.9%**; memory `admission-control-needs-a-hardware-term`
measures a pane at ~1.6 cores to draw). So an un-retirable pane is not untidiness; it is the load
that blocked this campaign's own fires for ~45 minutes.

### Consequence for the frozen DoD

The DoD's two numbers stay, and a third is added because the first is **not currently measurable**
(§2 M-2). Restated as falsifiable acceptance (§7 holds the disk-truth reads):

- **fire→engaged ≤60s p95** — requires a producer that does not exist today. The design must ship
  the producer first; until then any p95 claim is unfalsifiable.
- **ZERO illegible pane exits** — retained, but paired with its mirror so it cannot be satisfied
  vacuously: **every retiring pane names a live successor OR is explicitly terminal, AND every
  session category has a sanctioned resolution path** (F1).
- **NEW: zero panes in an unclassifiable lifecycle state.** A pane must always resolve to exactly
  one of the categories in §5.1, each with a named next action.

---

## §2 Measured constants (Phase 1 — every row re-derived from primary disk truth)

Every number below was produced by the command shown, in this session, on 2026-07-29. Nothing here
is inherited from a prior doc's claim.

| # | Constant | Value | Command / citation |
|---|---|---|---|
| **M-1** | Engagement success rate over the whole telemetry window | **139 / 141 = 98.6%** engaged; 2 failures, both `self-retire-peer` | `jq -s 'group_by(.engaged)…' ~/.claude/logs/handoffs.jsonl`; window `2026-07-24T18:49:40Z → 2026-07-29T23:07:23Z` |
| **M-2** | **fire→engaged latency records in existence** | **0 of 141** | The only two timestamps written are `handoffs.jsonl.ts` (`handoff-fire.sh:2613`) and `cc-fired/<pane>.json.firedAt` (`:578`). **Both are written AFTER `verify_engagement` returns** (`:2622`→`:2623`, `:2631`→`:2632`) and are byte-identical for the same fire — verified on this session's own fire: both `2026-07-29T23:07:23Z`. No fire-START timestamp is recorded anywhere. **The row's headline metric has no producer.** |
| **M-3** | Fires whose firing session is unattributable | **73 / 141 = 51.8%** carry `firing_sid:"?"` | `jq -rs 'map(select(.firing_sid=="?"))|length' ~/.claude/logs/handoffs.jsonl` |
| **M-4** | `firing_rss_kb` values ever recorded | **0 of 141** (100% zero) | `jq -rs 'map(select(.firing_rss_kb==0))|length'`. Cause: `:2609` reads `~/.claude/watchdog/${SESSION_ID:-$FIRING_SID}.pid`, absent ⇒ `ps -o rss= -p 0` ⇒ empty ⇒ `0`. A field added to answer "at what firing-session RSS" that has **never once** produced a value — inert by construction (memory `feature-durability-mechanism-not-memory`). |
| **M-5** | Fired-peer stamps, and what they carry | **122 stamps; 100% carry exactly `{cwd, firedAt, firedBy, paneUUID, selfRetire}`** — 0 carry an engagement proof, marker, session id, or successor | `cat ~/.claude/cc-fired/*.json | jq -r 'keys|join(",")' | sort | uniq -c` → single row `122 cwd,firedAt,firedBy,paneUUID,selfRetire` |
| **M-6** | Session categories `self-close` can distinguish | **exactly 2** — fired-peer (stamp present) vs origin (stamp absent) | `handoff-fire.sh:1390-1404`. The oracle is a single `[ ! -s "$SC_FIRED_STAMP" ]` test. |
| **M-7** | Blocking gates on the close path | **4 blocking + 1 dirty refusal** | origin `:1391` (exit 2) · live-teammate `:1425` (exit 4) · successor-liveness `:1444`/`:1448` (exit 3) · successor-engagement `:1463` (exit 3) · dirty tree `:1476` |
| **M-8** | `successor_engaged` oracle's dependency | **row 4's registry row `.session_id`, consumed FAIL-CLOSED** | `:515-524` calls `engagement_seen "$pdir" "" …` with an **empty marker**, disabling path (a); only path (b) remains, which requires `jq -r '.session_id'` from `$regdir/$pane.json` (`:471`). Return 1 (= "never engaged", close ABORTS) is the documented behaviour when the transcript is "unresolvable/unreadable" (`:513-514`). |
| **M-9** | `ensure_registration`'s provisional row fields | `{paneUUID, name, cwd, cmd, provisional}` — **no `session_id`** | `:544-545`. So a pane whose row is provisional can **never** satisfy M-8's path (b): the engagement check false-negatives structurally, not only on resume. |
| **M-10** | Orphaned-assignee resolution paths that work | **0 of 4** | `GROUND_UP_DISPATCH.md` § "Orphaned assignees are NOT agent-reapable": lead `shutdown_request` (channel died) · `cc-teardown`/registry (0 rows) · it2 by cwd (0 panes match) · `self-close --terminal` (**REFUSED** — no fired-peer stamp). Only `--agent-id` process → tty → it2 `session.tty` resolves them at all. |
| **M-11** | `pane-id-lint.sh` enforcement call sites | **0** — the lint exists on trunk (58 lines) and is invoked from nowhere | `git grep -ln 'pane-id-lint' origin/main -- scripts/ hooks/ bin/ tests/` returns only `scripts/pane-id-lint.sh` itself. Orphaned detection, not a gate (memory `enforcement-must-live-at-the-chokepoint`). |
| **M-12** | ~~`payload_lint_gate` coverage of the `/goal` trap~~ | ~~not covered~~ **FALSIFIED — a guard already existed** | The literal reading was right (`payload_lint_gate` lints only the back-channel block) and the **conclusion was wrong**: `check_slash_head` (`:1112`, called in the pre-spawn guard block) has always HARD-FAILED the exact `/goal`-over-4000-chars case, with `FIRE_ALLOW_SLASH_HEAD=1` as its override. **I greped one function and asserted a file-wide absence** — the "negative tool-claim" trap named in this repo's own anti-capture rules. A `payload_slash_gate` was built on this bad premise and has been REMOVED; what F5 actually needed was the refusal *record*, which is F13. Recorded rather than silently deleted, because the method error is the reusable lesson: to claim a guard is absent, grep the FILE for the behaviour, never one plausible function for the code. |
| **M-13** | Row 3's M3 primitive `mailbox_close_disposition` | **DOES NOT EXIST** — docs only | `grep -rn 'mailbox_close_disposition'` over `scripts/ hooks/ bin/ ~/.claude/bin ~/.claude/hooks` returns **only** `docs/plans/CROSS_SESSION_COMMS_V2.md:310`. Its §8 A13 row claims *"primitive landed and tested standalone"* — **that claim is falsified**; the map cell's *"SPECIFIED, NOT BUILT"* is the accurate one. Row 3's *underlying* primitive `mailbox_migrate` **does** exist (`hooks/lib/mailbox-pending.sh:327`, LOCKED, exactly-once by cursor advance). |
| **M-14** | Pre-close mail inventory disposition | **WARN-only, never blocks** | `:684` header states *"best-effort, WARN-only — NEVER blocks the close"*; `:711` warns on unread mail and proceeds. This is row 3's F4 verbatim, and exactly what M3 must convert into an actuator. |
| **M-15** | Deploy reality for row 2's own surface | **LIVE and current** | `~/.claude/scripts/handoff-fire.sh` is a **symlink** into the shared checkout (`ls -la`), and `md5 -q` of the live file **equals** `git show origin/main:scripts/handoff-fire.sh | md5 -q` = `aea3c5cb14855a18e5e6e8c62b2ee477`. `~/.claude/scripts/` holds **85 symlinks in 86 entries**. |
| **M-16** | Live checkout lag | **1 commit behind** origin/main, on branch `main` | `git -C ~/Development/claude-infrastructure rev-list --count HEAD..origin/main` = 1 |
| **M-17** | Postland stamp distribution | **33 stamps: 0 green · 30 red · 2 cut · 1 hung** | `grep -l '"verdict":"<v>"' ~/.claude/autonomy/postland/stamps/*` per verdict |
| **M-18** | launchd disabled-DB, checksummed | **39 labels: 19 disabled + 20 enabled (sums exactly)** | `launchctl print-disabled gui/$(id -u)`, counted on `=> disabled` / `=> enabled`, **never** grepped for `true` |
| **M-19** | Truncated pane ids in the LIVE docs corpus | **28**, across **12+ files owned by other rows** (the coordinator's own `GROUND_UP_DISPATCH.md` ×6, `wake-on-ping-2026-07-26.md` ×4, row 1's `LAND_PIPELINE_V2.md` ×2, …) | `bash scripts/pane-id-lint.sh docs`. **Decides a design choice**: the pane-id gate must be PAYLOAD-scoped, because a corpus-scoped gate would refuse every fire on the box over another author's file (memory `whole-tree-lint-is-a-fleet-wide-hard-stop`). Backlogged, not fixed here — none of the 28 is row 2's. |
| **M-20** | Fired stamps carrying an **empty** `firedBy` | **71 of 133 = 53.4%** | `jq -r 'select((.firedBy // "") == "")' ~/.claude/cc-fired/*.json \| wc -l`. Same root as M-3, measured on the *stamp* side. **Consequence beyond row 2:** `bin/cc-classify`'s `handed-off-lead` cause requires `firedBy == <predecessor sid>`, so those predecessors can never classify handed-off-lead and fall to `finished-operator` (never auto-reap) — the reaper's own north star is defeated for half of all fires. Re-derived here; an independent researcher measured 62/122 earlier the same day, and the ratio holds as the population grew. |
| **M-21** | Recycle-path success oracle | **`ps -o comm=` on the tty only** — `ENGAGE_VERIFY` is hard-wired to `0` for recycles (`:2326`), and the success line claimed `relaunched + CONFIRMED` | `grep -n 'ENGAGE_VERIFY=' scripts/handoff-fire.sh` → only `:205` (init) and `:2326` (`[ "$RECYCLE" = 0 ] && … ENGAGE_VERIFY=1`); claim at `:1408`. Became **F12**. |
| **M-22** | Corpus tests that fail **under load** on the PRISTINE tree | **16** — `handoff-fire-focus` 8 · `handoff-fire-payload-lint` 6 · `fire-engagement` 2 | Ran each suite against `git archive HEAD` at 2.78/core: they invoke the real fire path, the capacity gate refuses with **exit 9**, and their expected statuses (4, 0, …) never occur. At 0.5/core they all pass. **Not row 2's to fix** (the gate is row 13's, the corpus row 1's) and a plausible contributor to the 30-red/0-green stamp condition blocking deploy. Reported to the coordinator. |

### M-15/M-16 correct the brief's deploy premise — recorded because it inverts a planning assumption

This row's fire payload stated the live checkout was *"~56 commits behind trunk … so anything you
land is INERT until row 1's lane unblocks"*, and that failure mode F6 (the `mktemp` collision) was
*"FIXED on trunk but NOT DEPLOYED, so it is still live in ~/.claude/scripts"*.

**Both are falsified as of 2026-07-29T23:1xZ.** The checkout is **1** behind, not ~56; the live
`handoff-fire.sh` is byte-identical to trunk; and the `mktemp` fix is **live** — `grep -n
'handoff-deps' ~/.claude/scripts/handoff-fire.sh` shows `:2048 mktemp
"${TMPDIR:-/tmp}/handoff-deps-XXXXXX"`, the fixed trailing-template form. **F6 is closed on the
live system**, so this rebuild must not spend a line on it.

What *does* survive from the deploy-lag memory, and constrains this design: `~/.claude/scripts/` is a
directory of **per-file** symlinks, so an **edit to an existing file goes live on the next checkout
fast-forward, but a BRAND-NEW file is never linked**. Design consequence, adopted: **every mechanism
below lands as an edit to an already-symlinked file** (`scripts/handoff-fire.sh`,
`hooks/lib/*.sh` — `~/.claude/hooks/lib` exists live). No new top-level script is required, so this
row needs **no deploy-side activation step**. M-17 (0 green stamps) still means the *automatic* lane
is fail-closed; M-15 means row 2's surface is nonetheless current, because the checkout advanced by
another path. Recorded as **ACCRUING → in fact already LIVE for this row's file**; verified by md5,
not by the stamp count.

---

## §3 Phase 1 — branch-graveyard sweep (run before designing anything)

Method: the sweep was given a **positive control first** — it must re-find row 12's known stranded
`scripts/launchd-parity-lint.sh` before any of its other output is believed. It did (`518d61dc`).
The campaign's per-row pointer list was treated as a POINTER, not a fact, and re-verified by
`git cat-file -e` against branch, trunk, and disk.

**The pointer list was incomplete: row 2 has THREE artifacts, not the two named.**

| Artifact | Branch | On trunk? | On disk? | Verdict |
|---|---|---|---|---|
| `tests/pane-id-lint.bats` (76 lines, **9 `@test`**) | `fix/infra-perfection`, `tm/gates` | no | no | **TAKE** — its subject `scripts/pane-id-lint.sh` **is** on trunk (58 lines) and has **zero** enforcement call sites (M-11). A suite whose subject exists is a pure-win regression guard, and its subject is this row's own legibility surface: it pins the all-digit real pane prefix `99261468` as a must-trip case — the exact truncation that caused a `cc-notify` exit-3 hard-fail. Not in the campaign's list. |
| `tests/handoff-fire-daemon-window.bats` (123 lines, 9 `@test`) | `backup/daemon-window` | no | no | **REJECT as-is — its subject is absent.** `git show origin/main:scripts/handoff-fire.sh \| grep -c 'daemon-window'` = **0**. The suite tests a `--daemon-window` mode that does not exist on trunk; landing it lands 9 guaranteed-failing tests. **HARVEST the finding instead:** it documents that the split-right default requires an `$ITERM_SESSION_ID` anchor and so a launchd caller can never fire (`handoff-fire.sh:2400` REFUSES a no-anchor fire). Trunk's sanctioned no-anchor lane is `--window`, a different mechanism. Carried as F9. |
| `hooks/lib/session-evidence.sh` (79 lines) | `feat/session-scoped-close` | no | no | **REJECT on merits, per its own originating doc.** `docs/research/STRANDED_EXPOSURE_2026-07-26.md:529` prescribes **ABANDON** with reasons: the 📦≠✅ doctrine is already on trunk in CLAUDE.md and `completion-assert.sh` is already session-aware (`:54`). This is the case the skill's graveyard rule is careful about — here the originating doc *does* distinguish "rejected design" from "land never happened", and it says rejected. Not taken. |

Nothing is taken from `tm/growth` (0 unique patches; drags a 6-branch chain). The one TAKE is
applied with `cherry-pick -x`.

---

## §4 Phase 2 — INVARIANTS vs ARCHITECTURE

First principles is not amnesia. Every hard-won lesson sorted into properties any design must keep
(numbered requirements, binding) and mechanisms inherited from nothing.

### INVARIANTS (R1-R12) — binding on this design

| # | Invariant | Earned by |
|---|---|---|
| **R1** | **Positive death evidence, never silence.** A stall is not a death. Terminal judgements require pid gone / pane gone / registry row gone. | `GROUND_UP_DISPATCH.md` 529 incident — two duplicate leads created by treating a 6-min silence as terminal; memory `argv-is-sampling-cwd-is-durable` |
| **R2** | **Refusing to close never loses work; closing wrongly does.** Ambiguity resolves toward staying up. | `handoff-fire.sh:1387-1388` |
| **R3** | **A gate that refuses everything is not a passing metric.** A number that reads 0 by construction is not a result. | map learnings (row 5's falsified cell); §1 above |
| **R4** | **Absence must be loud, and only where the producer's world exists.** A detector needs existence evidence. | memory `absence-alarm-needs-existence-evidence`; the `cc-permission-beacon` incident (landed, wired nowhere, "none pending" indistinguishable from "never ran") |
| **R5** | **Consume another row's mechanism FAIL-SOFT.** Landed ≠ deployed ≠ activated ≠ exercised. | map § "What DONE means"; row 4's oracle is landed-but-inert |
| **R6** | **Prove liveness/engagement by durable products, never by mtime or mere existence.** Birth is not engagement. | memory `effect-read-predicate-red-proof`; `handoff-fire.sh:437-442` |
| **R7** | **Enforcement lives at the chokepoint**, not in a lint's own suite. | memory `enforcement-must-live-at-the-chokepoint`; M-11 |
| **R8** | **Every mechanism ships an env kill switch.** Revert-as-plan is not a plan. | `ground-up` skill Phase 3 |
| **R9** | **A field that never produces is inert by construction** and must fail loud rather than log a zero. | M-4; memory `feature-durability-mechanism-not-memory` |
| **R10** | **A close is operator-visible surface.** Continuation must be visible where the operator's eyes land — announce INTO the survivor + move focus. | memory `handoff-succession-legibility` |
| **R11** | **Address by role/session, never by a cached or truncated pane uuid.** Truncated is strictly worse than stale. | memory `handoff-succession-legibility` §Addressing; `cc-notify-session-pane-mapping` |
| **R12** | **A verdict string must name which oracle fired.** A claimed outcome ≠ a checked outcome. | memory `claimed-outcome-vs-checked-outcome`; M-2/F4 |

### ARCHITECTURE — inherited from nothing, and what this design keeps

Kept because measured sound: the four blocking close gates (M-7) — they have each caught a real
orphaning; `mark_fired_peer`'s **spawner-writes-it** oracle (a session can never earn the marker by
behaving like a worker, `:566-569`); the `__selfclose` detached watcher's AppleEvent-free design
(`:917-925` — foreground keystrokes at arm time, ps-polling detached).

Discarded: the assumption that lifecycle facts are **derivable at read time** from foreign state
(row 4's registry, the process table, iTerm2's pane list). That assumption is the root of F1, F2 and
the missing metric, and §5 inverts it.

---

## §5 The design — THE INVERSION

**The incumbent's shape.** Row 2 owns the *actions* (fire, recycle, close) but owns almost none of
the *facts* about them. Every lifecycle question is answered by **inference from a foreign artifact
at read time**: is this successor engaged? → row 4's registry row `.session_id` (M-8), fail-closed.
What category is this pane? → the presence of a 5-field stamp (M-6). Whose assignee is this? → the
process table's argv. What continues after this close? → nothing durable at all. Meanwhile the two
artifacts row 2 *does* own record only that a fire **happened** (M-5), and are both written *after*
the fact they would need to time (M-2).

That is why the failure modes cluster the way they do: a missing category, a false-negative
engagement check, an unmeasurable metric, and half the fleet unattributable are all the same defect
— **row 2 throws away the evidence only row 2 can produce, then re-derives it from state it does not
own.**

> ### The inversion: row 2 keeps ONE durable, append-only-per-transition LIFECYCLE RECORD per pane, written by row 2 at every transition, and every lifecycle decision reads THAT first. Foreign oracles become CORROBORATION, never the primary read.

The record is `~/.claude/cc-fired/<pane>.json` **extended additively** — the same path `cc-reaper`
already consumes, so row 4's consumer keeps working unchanged (jq reads named fields; new keys are
invisible to it). Additive-only is a hard constraint of this design, not a convenience.

### §5.1 The record, and the THIRD CATEGORY (answers F1)

```jsonc
{
  // ── existing, unchanged (cc-reaper's contract) ──
  "paneUUID": "...", "cwd": "...", "firedBy": "<firing pane|sid>",
  "firedAt": "<ISO8601>", "selfRetire": true,

  // ── NEW: what row 2 knew and threw away ──
  "schema": 2,
  "originClass": "fired-peer" | "origin" | "assignee",   // §5.1 classifier
  "originator":  "<sid|pane of the thing that created me>" | null,
  "firedStartedAt": "<ISO8601 — captured BEFORE spawn>",  // the missing half of M-2
  "engagedAt":      "<ISO8601>" | null,
  "engageLatencyS": 42 | null,                            // engagedAt − firedStartedAt
  "engageProof":    "marker:<FIRE_MARKER>" | "registry:<sid>" | "assumed",  // R12
  "marker":         "<FIRE_MARKER>",                      // survives resume (F2)
  "transcript":     "<abs path that proved engagement>",
  // ── written at CLOSE, by the close path ──
  "closedAt": "<ISO8601>" | null,
  "succession": { "kind": "successor"|"terminal"|"orphan-assignee",
                  "successorPane": "<uuid>"|null, "announced": true|false,
                  "mailDisposition": "migrated:<n>"|"deadletter:<n>"|"none" }
}
```

**The category classifier — three categories, not two.** `originClass` is decided once, at the
moment of creation, by the party that knows:

| Category | Oracle (who writes it) | May self-retire? |
|---|---|---|
| `fired-peer` | `handoff-fire` wrote the stamp at fire time with `selfRetire:true` (unchanged, `:570`) | **yes** — pings originator, closes |
| `origin` | no stamp exists ⇒ operator-launched (unchanged, `:1391`) | **no** — stays up, reports |
| **`assignee`** *(NEW)* | the pane's own process argv carries `--agent-id <name>@session-<sid>`; `originator` = that `<sid>` | **only** via the orphan path below |

F1's gap was never a missing feature — it was a **missing category**. An assignee has an originator
that may no longer exist, which is neither of the two states the incumbent models. Giving it a name
gives it a sanctioned resolution:

**`self-close --orphaned-assignee`** — a THIRD sanctioned path, admissible **iff all four hold**:

1. `originClass == "assignee"` — established from **argv at the command position**, never
   `pgrep -f` (memory `pgrep-f-matches-agent-briefs`: argv carries whole briefs, so `pgrep -f X`
   counts sessions that merely *mention* X).
2. The named `originator` is **provably dead** by R1 — pid gone **and** no registry row **and** no
   live process for `session-<sid>`. Silence is never sufficient; an `unknown` verdict REFUSES.
3. Its own tracked tree is clean (existing dirty gate, unchanged).
4. The retirement is **LEGIBLE** (R10): its transcript path and worktree are announced to the
   operator surface before the close, because an assignee's findings live only in its transcript
   (`wave-report-harvest-from-disk`).

This is deliberately **not** `--allow-origin-close`. That override exists to be *almost never
right*, and the coordinator was correct to refuse it for tidiness: forcing a safety gate whose
purpose is to stop closes-without-continuation is the wrong trade. A named category with its own
four preconditions is a *different* thing from an override that bypasses a gate.

### §5.2 Engagement proven from row 2's own record (answers F2, F4, and M-8/M-9)

`successor_engaged` currently passes an **empty marker** (M-8), which disables the content-based
path and leaves it wholly dependent on row 4's registry row carrying a `.session_id` — a field the
provisional row it may itself have written does not have (M-9). It then fails **closed**, aborting
the close of a predecessor whose successor is in fact working.

The record fixes this at the root: the stamp carries the **marker**. So:

- **Primary read:** the marker, found by content in **any** transcript under any account's projects
  dir. A `--resume` writes into the ORIGINAL sid's transcript — and that transcript now **contains
  the marker**, because the resumed session ingested the marked prompt. So F2's false-negative
  dissolves: there is no need for a "new" transcript to exist.
- **Corroboration only:** row 4's registry `.session_id` (R5 — fail-soft; when the oracle is dark
  the marker path still decides).
- **R12:** whichever path fired is recorded in `engageProof` and **printed**. The success line's
  current text — `→ engagement confirmed for the fired session (transcript/registry birth)`
  (`:2624`) — is a **stale string over a correct check**: `assistant_turn_in` (`:443`) has required
  a content-bearing `type=="assistant"` turn since item `ff2d6609a33e`. F4 is therefore a
  *legibility* defect, not a correctness one (see F4 below for the precise, corrected claim).

### §5.3 The metric's producer (answers M-2)

`firedStartedAt` is captured **before `spawn`** and the record is written **at that moment**, then
updated on engagement with `engagedAt` + `engageLatencyS`. Two consequences: fire→engaged latency
becomes derivable for every fire (the DoD's headline number gets a producer), and a fire that
**never engages** leaves a record saying so with a start time — today it leaves `engaged:0` with no
duration and no way to distinguish "slow" from "dead".

`firing_sid:"?"` (M-3, 51.8%) is fixed at the same site: the record's `firedBy` already resolves a
real value in the stamp path, so the telemetry line reads it from the record instead of re-deriving
it. `firing_rss_kb` (M-4, 100% zero) must **stop logging a false 0** — R9: emit `null` when the
pidfile is absent, so "not measured" is distinguishable from "0 KB".

### §5.4 M3 — close-path drain-or-reroute (inherited seam; row 3's contract, implemented not redesigned)

Row 3's written contract (`CROSS_SESSION_COMMS_V2.md:304-311`), quoted: *"The pre-close inventory
becomes an **actuator**: at close, undrained mail is **drained, rerouted, or dead-lettered — before
the close proceeds.** Ordered: successor named → `mailbox_migrate` to it (mandatory, not advisory);
no successor → append to a **dead-letter store that is itself surfaced** on the operator board with
existence evidence (R5), never a silent file."* Kill switch named by the contract:
`CC_CLOSE_MAIL_GUARD=0`.

Implemented exactly as written, at the call site `handoff-fire.sh` (the inventory at `:684-726`,
which is WARN-only today — M-14, row 3's F4):

1. **Successor named** → `mailbox_migrate <closing> <successor>` (row 3's real primitive,
   `hooks/lib/mailbox-pending.sh:327` — LOCKED both boxes, exactly-once by cursor advance, so a
   re-run is a no-op). Mandatory: a non-zero unconsumed count that fails to migrate **blocks the
   close**.
2. **No successor** (`--terminal`) → append to a dead-letter store **with existence evidence** (R4)
   so "no dead letters" is distinguishable from "the store never ran", and surface it on the
   operator board.
3. `mailbox_close_disposition` **does not exist** (M-13) — row 3's §8 A13 claim is falsified, its
   map cell is right. Row 2 therefore writes the disposition *mechanics* here, but the **contract
   is row 3's and is not redesigned**. This is reported to the coordinator, not decided alone.

### §5.5 Enforcement moved to the chokepoint (answers F5, M-11, M-12)

Both of this row's legibility lints are detection without enforcement, and both belong at a
chokepoint row 2 already owns — `handoff-fire`'s own pre-fire gate:

- **F5 `/goal` trap:** `payload_lint_gate` (`:885`) gains a **leading-slash-command** check. A
  payload whose first non-whitespace character is `/` is REFUSED at fire time with the reason. This
  is a gate doing what the campaign has been doing by hand (M-12).
- **M-11 truncated pane ids:** `pane-id-lint.sh` exists and is called from nowhere. Its 9-test
  suite is taken from the graveyard (§3), and the lint is wired so a payload carrying a truncated
  pane uuid is caught before it becomes "a landmine for the next successor" (R11).

---

## §6 Failure-mode table — every observed mode → its structural answer

A mode without an answer is an unfinished design. F1-F8 are the campaign's measured modes as handed
to this row; F9-F11 were found in Phase 1.

| # | Observed failure mode | Structural answer | § |
|---|---|---|---|
| **F1** | `self-close` models exactly TWO categories; an Agent-Team assignee whose LEAD IS DEAD is neither, so no sanctioned resolution exists. Stranded 5 assignees 4+ h, then 7, then 11. `cc-backlog 95281da714f0` (2 confirmed occurrences) | **THIRD CATEGORY** `assignee` with `originator`, and a `--orphaned-assignee` path gated on four preconditions incl. R1 positive death evidence. Not `--allow-origin-close`. **SCOPE, stated precisely: this closes the SELF-close half.** An orphan that is IDLE cannot invoke it, so the population already stranded needs the external actuator — `cc-teardown --assignee-of` exists and its caller is default-off (**R-8**). The category and the death oracle are what row 2 owed; the actuator is one C10 activation away and is not row 2's file. | §5.1, §12 R-8 |
| **F2** | Successor-engagement check FALSE-NEGATIVES on a RESUMED session — `--resume` writes to the ORIGINAL sid's transcript, so there is no "new" transcript to find. `cc-backlog 93a9f880b6fe` | Engagement proven from the **marker in row 2's own record**, found by content in any transcript. The resumed original-sid transcript *contains* the marker. Registry becomes corroboration (R5). Also closes the wider M-9 hole (provisional rows carry no `session_id`). | §5.2 |
| **F3** | A resume restores the SESSION but never the TEAM CHANNEL — assignees keyed `--agent-id <name>@session-<sid>` to the dead PROCESS; every agent-directed send fails permanently; a teammate blocked on lead approval waits forever with no operator fallback | Record `teamChannelDead` at resume and **reroute**: the record names the originator, so an assignee whose originator is dead is classified `assignee`+orphaned (F1's path) rather than left waiting. Mail owed to the dead channel is dispositioned by M3 (§5.4) instead of vanishing. **Bounded:** the approval-fallback beacon itself is row 6's hook surface (`cc-permission-beacon`, `cc-backlog 1e16815bac51`) — row 2 supplies the category and the death verdict, not the hook. | §5.1, §5.4 |
| **F4** | Engagement "confirmed (transcript/registry birth)" is satisfied by attachment/system rows ALONE — a false positive. The real read is `type=="assistant"` + tool_use | **CORRECTED CLAIM — the check is already right; the STRING is wrong.** `assistant_turn_in:443-455` has required a content-bearing `type=="assistant"` turn since `ff2d6609a33e`; the header at `:437-442` names the exact defect. What remains is `:2624` still printing *"(transcript/registry birth)"* over a check that is no longer birth-based — a stale verdict string that misreports its own oracle. Answer: **R12** — print `engageProof`, the oracle that actually fired. (Whether to additionally require a `tool_use` block is deliberately NOT adopted: a legitimately conversational first turn is engagement, and tightening an already-correct oracle on an unmeasured hunch is how false negatives get built.) | §5.2 |
| **F5** | A payload STARTING with `/goal` parses as that slash command and is silently REJECTED over 4000 chars; the pane idles at an empty box while engagement-verify still reports success | **BOTH HALVES WERE ALREADY FIXED — see M-12 for the method error that hid it from me.** The gate exists (`check_slash_head:1112`, hard-fails a `/goal` head over the cap) and engagement no longer reports success for a never-run transcript (F4), so a rejected payload yields no assistant turn and `verify_engagement` FAILS LOUD. **The one real residue: the hard-fail exited before any telemetry, leaving no record of the refused fire** — closed by F13. My duplicate `payload_slash_gate` was removed. | §5.5, F13 |
| **F6** | Cold `--worktree` fires collide on a literal temp filename (BSD `mktemp` substitutes only a TRAILING `XXXXXX`); every fire after the first dies "File exists" | **ALREADY FIXED *AND* DEPLOYED — no work required, premise falsified.** Live `~/.claude/scripts/handoff-fire.sh:2048` reads `mktemp "${TMPDIR:-/tmp}/handoff-deps-XXXXXX"` and is byte-identical to trunk (M-15). The brief's "not deployed" was stale. Recorded, not rebuilt. | §2 |
| **F7** | A cold `--worktree` fire can race the prompt auto-submit — the session never engages while looking fired (0 activity) | Already mitigated by `verify_engagement`'s poll → one re-type → FAIL LOUD (`:487-505`), and M-1 measures **98.6%** engagement. The residue is that a failure is **untimed** — indistinguishable from "slow". Answer: `firedStartedAt` makes the race visible as latency, and the record persists the failure with a duration. | §5.3 |
| **F8** | Two leads in one worktree is an OVERWRITE HAZARD; only the read-before-write guard stopped 581 landed lines being clobbered. A stall is NOT a death | **R1 as a coded precondition, not a discipline.** The `--orphaned-assignee` and any re-fire-into-existing-worktree path require positive death evidence (pid gone ∧ no registry row ∧ no live `session-<sid>` process); `unknown` REFUSES. Warm-worktree claim records the claimant in the record, so a second lead's claim is a *readable conflict* rather than a silent race. | §5.1 |
| **F9** *(Phase 1)* | A **launchd** caller can never fire: the split-right default requires an `$ITERM_SESSION_ID` anchor and `:2400` REFUSES a no-anchor fire. Cost measured elsewhere: 41h / 266 refused fires (memory `headless-caller-anchor-and-failure-bounds`) | Named and **scoped OUT with a reason**, not silently dropped: trunk's sanctioned no-anchor lane is `--window`, and every daemon that would fire is currently **disabled** (M-18: `desk-invariant`, `boot-resume` both disabled — and the campaign warns they are runaway generators that must not be re-enabled without a fleet concurrency ceiling). Re-enabling them is row 12's activation surface, not row 2's. The stranded `--daemon-window` suite is rejected on the same grounds (§3). Backlogged, not built. | §3 |
| **F10** *(Phase 1)* | **51.8% of fires are unattributable** (`firing_sid:"?"`, M-3) — the succession chain cannot be walked for half the fleet, which is precisely the legibility the renamed constraint demands | The record's `firedBy` is resolved once at fire time and the telemetry line reads **the record**, not a re-derivation. | §5.3 |
| **F11** *(Phase 1)* | `firing_rss_kb` has recorded **0 in 141 of 141** — a field that has never once produced a value, logging a false `0` that is indistinguishable from a real zero (R9) | Emit `null`, never a fabricated `0`, when the pidfile is absent. Inert-by-construction fields must read as absent. | §5.3 |
| **F12** *(Phase 1)* | **The RECYCLE path accepts BIRTH where the fire path demands ENGAGEMENT.** `ENGAGE_VERIFY` is hard-wired to `0` for recycles (`:2326`) and the success line printed `→ relaunched + CONFIRMED` on the strength of `ps -o comm=` matching `node\|claude` on the tty (M-21). A recycle whose prompt was rejected or never auto-submitted sits at an empty composer and is reported CONFIRMED — the same insufficiency the fire path already learned (`ff2d6609a33e`), still live on its twin | **R12 — name the oracle, and make it disk-visible.** The line now reads `PROCESS-ALIVE … NOT engagement-verified` and states how to actually confirm; a `class:"recycle-unverified"` event is written so a task-less recycle is findable from disk without being at the pane. **Deliberately NOT overclaimed:** full marker-based verification here runs inside the *detached* `__recycle` watcher under different constraints, so it is named as remainder R-2 rather than half-built. An overclaimed verdict is worse than a modest one, because it stops anyone looking. | §5.2, §12 |
| **F13** *(Phase 1)* | **A REFUSED FIRE LEFT NO TRACE AT ALL.** Every pre-fire gate exits before `spawn` and therefore before `emit_handoff_telemetry`, so `handoffs.jsonl` holds only fires that happened. The capacity gate is **on by default** at ceiling 2.0/core and is **already live** via the `~/.claude/scripts` symlink, and load has ranged 15-41 on 10 cores today — so the fleet can stop firing entirely while the telemetry shows silence rather than a reason. "No fires logged" and "no fires attempted" were the same bits | Every pre-fire refusal writes `class:"refused"` + `refuse_reason` (capacity · `/goal`-cap · truncated pane id · malformed back-channel). **Row 13's ceiling and its admit/refuse DECISION are untouched — only the legibility, which is row 2's.** Vocabulary kept clean: a successful-but-unverified recycle is filed under its OWN class, never `refused`, because `class` is what consumers COUNT and this campaign has already been bitten by a verdict word inverting inside a different predicate | §5.3 |

---

## §7 Acceptance criteria — as DISK-TRUTH READS

Each row is a command whose output decides the claim. Narration is not acceptance.

| # | Claim | Disk-truth read | Passes when |
|---|---|---|---|
| **A1** | The metric has a producer | `jq -r 'select(.schema==2)\|[.firedStartedAt,.engagedAt,.engageLatencyS]\|@tsv' ~/.claude/cc-fired/*.json` | every schema-2 record has non-null `firedStartedAt`; engaged ones have non-null `engagedAt` + `engageLatencyS` |
| **A2** | fire→engaged ≤60s p95 | `jq -rs '[.[]\|select(.engageLatencyS)\|.engageLatencyS]\|sort\|.[(length*0.95)\|floor]'` over the record set | ≤60. **ACCRUING by construction** — needs ≥20 post-land fires; the read is defined now so the number cannot be asserted without it |
| **A3** | Three categories exist and are decidable | `bats tests/handoff-lifecycle-record.bats` | all `@test` pass, incl. an `assignee` case whose originator is dead and one whose originator is ALIVE (must REFUSE) |
| **A4** | Resume no longer false-negatives | RED-proof: `successor_engaged` against a fixture where the registry row has **no** `session_id` and the marker is in an existing transcript | fails on the pristine tree (`git archive`), passes after |
| **A5** | No close loses mail (M3) | `CC_CLOSE_MAIL_GUARD=1`; close with N unread + a successor → `jq .succession.mailDisposition` on the record | reads `migrated:<N>`; successor's inbox grew by N; closing-box cursors at EOF |
| **A6** | Dead-letter store is loud | terminal close with unread mail → dead-letter file **plus** existence evidence | store exists AND its "ran" evidence exists, so empty ≠ never-ran (R4) |
| **A7** | `/goal` payload refused at the gate | `handoff-fire.sh --dry-run --prompt-file <file starting with '/goal '>` | non-zero exit naming the leading-slash reason |
| **A8** | Truncated pane ids gated | `bats tests/pane-id-lint.bats` (9 tests, cherry-picked) + the lint reachable from the fire path | 9/9 pass; call site count > 0 (M-11 → non-zero) |
| **A9** | `cc-reaper`'s contract is unbroken | `bin/cc-reaper` against schema-2 records | reaper behaviour byte-identical on old and new records (additive-only proof) |
| **A10** | No fabricated zeros | `jq -r 'select(.firing_rss_kb==0)' ~/.claude/logs/handoffs.jsonl` on post-land lines | post-land lines carry `null`, not `0`, when unmeasured |
| **A11** | Kill switches work | each switch set to 0 → the mechanism is fully bypassed and the pre-change behaviour returns | one `@test` per switch |

---

## §8 Rejected alternatives (prevents relitigating)

| Rejected | Why |
|---|---|
| **Use `--allow-origin-close` for orphaned assignees** | It exists to be *almost never right*. Forcing a safety gate whose purpose is to prevent closes-without-continuation, for tidiness, is the wrong trade — the coordinator already refused it correctly. A named category with four preconditions is not the same thing as bypassing a gate. |
| **Make `successor_engaged` fail OPEN when the registry is dark** | Inverts R2 — it would close predecessors onto never-engaged successors, stranding work in BOTH panes. The fix is a *better oracle row 2 owns*, not a weaker gate. |
| **A new `~/.claude/lifecycle/` store** | `~/.claude/scripts` is per-file symlinks and a brand-new *directory* would need an activation step (M-15), adding a C10 operator hand-step for zero benefit. Extending `cc-fired/<pane>.json` additively reuses a path `cc-reaper` already reads. |
| **Require a `tool_use` block for engagement (as the brief suggests)** | The oracle is already correct (F4). A legitimately conversational first turn IS engagement; tightening a correct check on an unmeasured hunch builds false negatives — the exact class F2 is about. The real defect was the verdict STRING (R12). |
| **Rebuild the anchor/no-anchor fire lane (`--daemon-window`)** | Its subject is absent from trunk, `--window` is the sanctioned lane, and every daemon that would use it is disabled and warned as a runaway generator (M-18). Backlogged as F9 with the reason, not silently dropped. |
| **Land `tests/handoff-fire-daemon-window.bats` from the graveyard** | 9 tests against a mode that does not exist = 9 guaranteed failures. The *finding* is harvested (F9); the suite is not. |
| **Land `hooks/lib/session-evidence.sh` from the graveyard** | Its own originating doc prescribes ABANDON with reasons (`STRANDED_EXPOSURE_2026-07-26.md:529`) — the doctrine is on trunk and `completion-assert.sh` is already session-aware. A documented rejection, not an un-executed land. |
| **Batch the land at the end** | Row 3 lost an hour landing zero; row 5 survived a lead death with zero loss having landed 11 times. Continuous landing is the campaign's crash insurance. |
| **Spawn Agent-Team teammates for the build** | One file's control flow; disjoint ownership unconstructible; and a team spawned to fix the orphaned-assignee gap can itself create orphaned assignees (Phase 0). |
| **Redesign M3's contract** | Row 3 owns it and it is written. Row 2 implements it; the missing primitive is reported to the coordinator, not re-specified. |

---

## §9 Seams consumed (contracts, not redesigns)

| Seam | Owner | How row 2 consumes it | Behaviour when dark |
|---|---|---|---|
| Mailbox delivery + addressing (session-keyed, pane as alias) | **3** | calls `mailbox_migrate` (`hooks/lib/mailbox-pending.sh:327`) for M3 | no migration attempted; close still records `mailDisposition:"none"` and says so LOUD |
| M3 contract | **3** (spec) / **2** (call site) | implemented verbatim from §4 M3 + §8; `mailbox_close_disposition` absent (M-13) → row 2 writes mechanics only | `CC_CLOSE_MAIL_GUARD=0` restores WARN-only |
| Registry / liveness truth + session-beat oracle | **4** | **corroboration only** (R5) — existence-probed before use, never depended on | marker path decides alone; oracle absence is announced, never silently passed |
| Pane teardown / reaping | **4** | `cc-fired` schema stays additive so `cc-reaper` is unaffected (A9) | n/a |
| Account/quota ranking at fire time | **7** | unchanged call into `claude-accounts`/`cc-route` | unchanged |
| Daemon activation | **12** | row 2 requires **none** (M-15: edits to already-symlinked files) | n/a |
| Approval-fallback beacon (F3's operator fallback) | **6** | row 2 supplies category + death verdict only | out of scope, named |

---

## §10 Kill switches (R8 — every new mechanism)

| Switch | Default | Disables |
|---|---|---|
| `CC_LIFECYCLE_RECORD=0` | on | schema-2 record writes; stamps revert to the 5-field form |
| `CC_CLOSE_MAIL_GUARD=0` | on | M3 actuator; pre-close inventory reverts to WARN-only (row 3's named switch) |
| `CC_ORPHAN_ASSIGNEE_CLOSE=0` | on | the `--orphaned-assignee` path (refuses, as today) |
| `CC_PAYLOAD_SLASH_GATE=0` | on | the leading-slash-command refusal |
| `CC_PANE_ID_GATE=0` | on | the truncated-pane-uuid refusal at the fire chokepoint |
| `CC_ORPHAN_ASSIGNEE_CLOSE=0` | on | the `--orphaned-assignee` path (falls back to the origin refusal) |
| `CC_FIRE_REFUSAL_LOG=0` | on | refusal + recycle-unverified event records (F13/F12) |

`CC_PAYLOAD_SLASH_GATE` was in the design and is **gone** — the mechanism it guarded already existed
as `check_slash_head` (M-12), whose own override is `FIRE_ALLOW_SLASH_HEAD=1`.

---

## §12 Remainders — named, with owner and reason (never silently dropped)

| # | Item | Owner | Why it is not done here |
|---|---|---|---|
| **R-1** | **16 corpus tests fail under load on the PRISTINE tree** (M-22) — they invoke the real fire path and the capacity gate refuses with exit 9 instead of their expected status. Load-dependent by construction, and a plausible contributor to the 30-red/0-green stamp condition blocking the campaign's deploy | **1** (corpus) + **13** (the gate) | Neither file is row 2's, and the fix is a policy call: either the suites set `CC_FIRE_CAPACITY_GATE=off` (they are testing the fire path, not admission) or the gate exempts test invocations. Reported to the coordinator with the measurement. |
| **R-2** | **Marker-based engagement verification on the RECYCLE path** — F12 is made honest and disk-visible here, but not *verified* | **2** (this row) | It runs inside the detached `__recycle` watcher, which deliberately does only AppleEvent-free work and has its own 600s/90s windows. Wiring `verify_engagement` there is a real change that deserves its own RED-proof, and half-building it would have produced exactly the overclaimed verdict F12 is about. |
| **R-3** | **28 truncated pane ids in the live docs corpus** (M-19) | **10** (operator surface) + each file's author | None is row 2's file; the enforcement row 2 adds is payload-scoped precisely so it cannot hold one author answerable for another's. The lint now exists, is hermetically tested, and has a call site — a corpus sweep is an ordinary follow-up task. |
| **R-4** | **`firedBy` empty in 53.4% of stamps defeats `cc-classify`'s `handed-off-lead` cause** (M-20), so those predecessors fall to `finished-operator` and are never auto-reaped | **4** (classify/reap) | Row 2 now records `originator` in schema 2 and stops writing a fabricated `"?"`, which fixes the *producer* going forward. Making `cc-classify` consume the new field is row 4's surface. |
| **R-5** | **Two pane-closers in no row's artifact list** — `hooks/teammate-auto-shutdown.sh:135`, `hooks/lead-crash-watchdog.sh:575`. Both can make a watched pane vanish with **no succession announce** | **unruled** | This is row 2's standing constraint's exact violation surface but not row 2's files. Coordinator ruling requested; not claimed silently, per the map's unowned-surface rule. |
| **R-6** | **Which consumer SURFACES the M3 dead-letter store** on the operator board (`bin/cc-blockers` vs `bin/cc-comms-alarm-sweep`) | **10**, pending ruling | Row 3's M3 clause requires the store be surfaced with existence evidence. Row 2 writes the store **and** the `.ran` evidence at `~/.claude/mailbox/dead-letter/`; choosing the renderer is a seam row 2 must not decide alone. |
| **R-8** | **A SELF-close path cannot rescue an IDLE orphan — the honest limit of F1's fix.** `--orphaned-assignee` requires the assignee to RUN it, and an idle assignee runs nothing. Demonstrated on this row's own three researchers: read-only, reports already harvested from disk, holding no worktree, but process-alive with ancestry tracing to iTerm2 rather than to this session — so they survive its exit as orphans. Note the ordering, which is not a bug: while their originator is alive my own gate correctly REFUSES them ("your originator is ALIVE"); the moment it dies they qualify, and nothing is left to invoke it | **2** (named) + **4/12** (the actuator) | The complete answer needs the EXTERNAL path: `bin/cc-teardown --assignee-of <lead-sid>` already exists (landed `44720884`, 9 tests, resolves an unregistered assignee by it2-liveness + argv — census 134/134 assignee panes have no registry row), but **its only caller `hooks/lead-crash-watchdog.sh:532` is DEFAULT OFF** (`LCW_ORPHAN_CLOSE=1`), staged unactivated at `docs/activation/pending-activation/10-lead-crash-orphan-close-activate.sh`. So F1's self-half is landed here and its actuator-half is one C10 activation away. Row 2 does not own that hook or that activation; naming it rather than reaching across the seam. |
| **R-9** | **A `shutdown_request` does NOT terminate a background subagent** — measured at close: three read-only researchers, each sent a structured `shutdown_request`, all three still process-alive **240s later**. The sanctioned teammate teardown assumes a recipient that is PROCESSING messages; a finished fire-and-forget subagent is not, so the request lands and nothing acts on it. This is why the campaign's orphan census only ever grows | **2** (found here) + **4/12** (actuator) | Deepens R-8 rather than adding a new class: the gap is not that the assignee lacks a category, it is that **nothing with an actuator is watching**. `self-close`'s live-teammate gate correctly REFUSED this session (it did catch all three by `--agent-id`, which is worth knowing — the gate is not `--team-name`-only), and the documented `--allow-live-teammates` override is the sanctioned exit *once work is harvested*, which was verified here by disk: all three reports recovered by `agentName`, zero worktrees held, zero tracked writes. The durable fix is the same one R-8 names — activate `cc-teardown --assignee-of`'s caller. |
| **R-7** | **`_mbx_valid_uuid` is a path-safety validator, not a uuid-shape one** — so `mailbox_migrate` accepts a TRUNCATED address and reports success into a dead box | **3** | Measured while building M3 (a test premise of mine failed on it). R11 says truncated is strictly worse than stale; here it does not even fail loud. Row 3's file; reported, not patched. |

## §11 Status

- **Phase 0** frame — DONE (this doc's header; DoD armed durably via `dod-persist.sh set`)
- **Phase 1** measure — DONE: §1 constraint re-derived (**CONFIRMED-BUT-RENAMED**) · §2 eighteen
  measured constants · §3 graveyard sweep (3 artifacts, 1 TAKE / 2 REJECT with reasons)
- **Phase 2** invariants/architecture split — DONE (§4, R1-R12)
- **Phase 3** design — DONE (§5 inversion · §6 failure modes · §7 acceptance · §8 rejected)
- **Phase 4** build + adversarial proof — **DONE**, five lands, each RED-proved against a pristine
  tree recovered via `git archive` (never a hand-edited approximation):
  | Build | What | Tests | RED vs pristine |
  |---|---|---|---|
  | 1 | schema-2 lifecycle record + the metric's producer | 12 | 10/12 (2 are contract-preservation, green on both trees BY DESIGN) |
  | 2 | the third category + `--orphaned-assignee` | 17 | 16/17 (1 is the origin-gate-untouched contract test) |
  | 3 | M3 close-path drain-or-reroute + the close half of the record | 13 | 13/13 |
  | 4 | payload legibility at the chokepoint + refusal records + graveyard cherry-pick | 15 + 9 | 12/15 (3 are the pre-existing `check_slash_head` behaviours — the honest outcome of M-12) |
  | 5 | F12 recycle honesty + event-class split | 16 | — (extends Build 4's suite) |
  Regression: **253 ok / 0 not-ok** across all handoff + fire suites with the capacity gate neutralised
  so ambient load could not fake a RED.
- **Phase 5** land continuously, close honestly — **five lands, resolved from `origin/main` after
  ship-land's rebase** (a local sha names a commit that is not on trunk — row 3 hit exactly this):
  `91e2c65a` design · `eaa5e269` map · `0dc2b1c0` record+producer · `ad691965` third-category ·
  `f14f7028`→landed `b10ac9a7` M3 · `26787317` payload gates. **No activation step is required**
  (M-15: every change lands in an already-symlinked file), and Builds 1-2 were verified LIVE in
  `~/.claude/scripts/handoff-fire.sh` during the session.

### Own gates catching own defects (the exemplar predicted this; recording it kept it honest)

Five, all fixed at the root rather than by relaxing the check:
1. Adding two helper calls to `emit_handoff_telemetry` broke a suite that sed-extracts that unit
   ALONE — a `127` under `set -e`, violating the function's own documented contract that a telemetry
   hiccup can never affect the fire. Fixed by probing every collaborator, not by patching the test.
2. The land gate RED'd on **test hermeticity** twice (my new suite, then the cherry-picked one) —
   both fixed by fixturing `$HOME`, never by an allowlist entry.
3. The RED-proof exposed a **vacuous assertion of mine**: `jq '.missing|type'` also returns `"null"`,
   so a type-only check passed against pre-v2 code. Now asserts `has()` too.
4. A **doc comment I wrote** contained the literal `capacity_gate || exit 9`, so the capacity suite's
   positional ordering test matched two lines and broke.
5. My own new test caught my own **classifier**: `ps -o command=` flattens argv, so prose quoting
   `--agent-id <name>@session-<sid>` (which every brief in this campaign contains, including the one
   that fired this session) parsed as a real assignee id.
