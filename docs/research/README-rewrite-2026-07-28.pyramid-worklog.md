# README rewrite — Pyramid Principle worklog (2026-07-28)

Audit trail for applying the full Minto methodology (`pyramid-principle-full`) to
`README.md`. Every session appends below; nothing here is rewritten.

---

## Session 0 — Intake, classification, routing

**Bounded input body** (Execution contract, rule 1):

| Item | Measure |
|---|---|
| `README.md` (the document under repair) | 3,067 words × 1.4 ≈ **4.3K tokens** |
| Ground-truth reads: per-dir file/LOC census, live `settings.json` hook+permission roster, `handoff-fire.sh` option block, `cc-notify` / `mailbox-drain.sh` / `cc-await-ping` headers, launchd roster, session-index count | ≈ **6K tokens** |
| **Total declared input** | **≈ 10K tokens → Tier A** (inline, no subagents at all) |

Scoped to the *governing* surfaces only: the document itself plus the disk facts it
asserts. The 117K-line repo is deliberately **not** the input body — the README's
message is governed by what the system *is*, which the census answers, not by every
implementation file.

**Mode: R — Review/repair.** An existing document to audit and rewrite. Route:
reverse-engineer its pyramid in Session 3 → Sessions 4–8 as audit gates → Session 9
rewrite → Session 10 critique.

**Reader.** An engineer who has just landed on the GitHub repo page, cold and
skeptical, with ~30 seconds of attention before they bounce. Secondary reader: the
operator of this machine, using the README as the top-level reference index.

**Medium.** GitHub README. Minto's rule (Part 4 intro, p. 168) — short message, many
readers → dot-dash memo / lap visual, i.e. an answer-first document whose key line is
*visible as a unit*, not prose the reader must assemble. This maps to: hero assertion,
S-C-Q intro, one key-line table above the fold, five body sections whose headings *are*
the key-line assertions.

**What the reader should KNOW or DO after reading.** Know that `~/.claude` can be a
version-controlled system whose sessions schedule each other; and be able to run
`./install.sh` to get it.

**Exit checklist**
- [x] Input body named, measured, tier selected (A)
- [x] Reader, medium, desired end-state recorded
- [x] Mode + route recorded
- [x] Worklog created

---

## Session 3 — Build the pyramid (mode R: reverse-engineer, then rebuild)

### 3a. The pyramid the current README actually has

**Governing thought (from the hero line, l. 5):** "Make one machine behave like a fleet
— dozens of parallel Claude Code sessions across four accounts, versioned so updates
never break a running session, with every Write recoverable and every past session one
search away."

**Key line (from the "What's inside" table, l. 60–72):** seven subsystems — Parallel
sessions · Versioned updates · Lifecycle hooks · Backup & recovery · Plan & task
persistence · Session search · Autonomous fleet ops.

### 3b. Defects found (each names the rule it breaks)

| # | Defect | Rule broken |
|---|---|---|
| D1 | The governing thought is **four ideas comma-spliced**, not one summarizing idea. A reader cannot repeat it back. | Ch 1 p. 9 — ideas at any level must be a *summary* of those below |
| D2 | The key line is **not the same kind of idea**: "Session search" is a feature (delegated to another repo) sitting beside "Autonomous fleet ops" (an entire layer); "Lifecycle hooks" is a *mechanism*, not a problem removed. | Ch 1 p. 9 — one plural noun per grouping |
| D3 | Key line is **not MECE**: "Backup & recovery" and "Plan & task persistence" are two instances of one idea (nothing you did is lost). | Ch 6 p. 78 |
| D4 | **17 top-level sections at one altitude** — far past the ~7 ceiling, ~4–5 preferred. | Ch 6 p. 78 |
| D5 | Headings **"What's inside"**, **"Stats"**, **"Sync"** are intellectually blank categories. | Ch 4 p. 42; Ch 10 p. 175 |
| D6 | **No introduction.** The document opens on an assertion; there is no Situation → Complication → Question the answer answers. | Ch 4 |
| D7 | **30-second test fails**: the key line is buried at l. 60, behind a deploy-model section and a collapsible. | Ch 3 p. 29 |
| D8 | Stale facts vs disk: "59 hooks", "43,000+ lines / 470+ files", "1,398 bats tests", "5,200+ sessions", "39 bin tools", "12 daemons", "30+ hooks across 8 events". | ground truth |

### 3c. The rebuilt pyramid

**Question the document answers:** *How do you run many Claude Code sessions at once on
one machine, safely, without a human scheduling them?*

**Governing thought (the answer):**

> Make `~/.claude` a deployment of a git repo, and make the sessions themselves the
> schedulers — they open, address, and retire one another.

**Key line** — one plural noun: **the five properties that let one machine behave like a
fleet**. Inductive grouping (Session 5 confirms). Ordered by **degree** — most
distinctive first, most conventional (and the call to action) last.

| # | Key-line idea | Absorbs (old sections) |
|---|---|---|
| K1 | **Sessions run each other** — they open, message, and retire without a human scheduler, and page the human only when a human must decide | Autonomous fleet ops · half of Parallel sessions · Agent Team support · Status line and notifications |
| K2 | **Parallel work cannot collide** — a worktree per writer, an account per lane, one machine-wide lock on landing | half of Parallel sessions |
| K3 | **Autonomy is bounded** — 69 hook entries on 12 lifecycle events refuse the calls that lose work | Lifecycle hooks · Auto mode and permissions |
| K4 | **Nothing a session did dies with it** — every Write, plan, task and transcript outlives the pane | Backup & recovery · Plan & task persistence · Session search |
| K5 | **The system deploys from git** — symlinked live, 2,307 tests, 13 daemons, versioned binaries | Deploy model · Never break a running session · Install · Sync |

**MECE check.** K1 = *agency* (who drives a session). K2 = *isolation* (can two run at
once). K3 = *restraint* (what an action is refused). K4 = *persistence* (what survives).
K5 = *substrate* (how the thing itself is delivered). The one live overlap —
`/handoff` bridges context *and* opens a session — is cut deliberately: the **mechanism**
(fire / split / recycle / close) is K1; the **artifacts that survive the pane** (plans,
tasks, transcripts, backups) are K4.

**Every old section maps in** (nothing is dropped, D3 collapses two into one, and the old
key line's #1 and #7 merge into K1+K2). Browser automation and the daemon roster are
*reference*, not argument: they move below the key line into a reference section, per
Session 7's rule that reference material must not dilute the key line.

**Exit checklist**
- [x] Governing thought is ONE idea, repeatable in a breath
- [x] Key line is one plural noun, 5 members (≤ the 4–5 ceiling)
- [x] Every member is a summary of the section beneath it
- [x] Structured only one level below the key line before drafting (Part 2 intro, p. 73)
- [x] All old content mapped — nothing silently dropped

---

## Session 4 — Craft the introduction (S-C-Q)

The introduction must **remind, never inform** (Ch 4 p. 48) — every element must be
something the reader already accepts, so the only new thing in the document is the answer.

| Element | Content | Why the reader won't question it |
|---|---|---|
| **S — Situation** | Claude Code reads everything it does — permissions, hooks, commands, agents — from `~/.claude`. | Documented behavior; any user knows it. |
| **C — Complication** | But `~/.claude` is machine state: unversioned, unreviewable, and the moment a second session starts they share one git index, one binary, and one operator's attention. | Anyone who has run two sessions has hit it. |
| **Q — Question** | So how do you run many at once, safely, unattended? | Follows inevitably from C. |
| **A — Answer** | The governing thought. | The document. |

No exhibits in the introduction; no claim the reader would stop to challenge.

**Exit checklist**
- [x] S, C, Q each contain only what the reader already accepts
- [x] Q is the question the governing thought answers — not a broader or narrower one
- [x] No exhibit, table, or statistic inside the introduction
- [x] Reads as narrative, ≤ 4 sentences

---

## Session 5 — Horizontal logic: deduction vs induction

The key line is **inductive**: five members of one plural noun ("properties that let one
machine behave like a fleet"), each independently supporting the governing thought.
It is **not** mixed with deduction at that level — there is no "therefore" chain across
K1→K5, and the members can be read in any order without breaking the argument (the chosen
order is a reader-service, Session 6, not a logical dependency).

Deduction is used *within* sections, at one level down, where it belongs — e.g. K2:
*concurrent sessions share one git index* → *a bare commit therefore sweeps another
session's staged files* → *therefore every writer gets its own worktree*. Each such chain
is ≤3 steps, per Ch 5's warning against long deductive ladders in written form.

**News-is-not-thinking check (Ch 5 p. 72).** Two candidate members were cut for sharing no
subject/predicate similarity with the rest: the LaunchAgent roster and the BrowserMCP
wrapper are *inventory*, not properties — demoted to reference.

**Exit checklist**
- [x] Each grouping is purely inductive OR purely deductive, never both
- [x] Inductive members are the same kind of idea (one plural noun)
- [x] Deductive chains are ≤3 steps and live below the key line
- [x] Non-inferring "news" items demoted out of the argument

---

## Session 6 — Impose logical order

Of the only four available orders (deductive, time, structural, degree), the key line
takes **degree**: descending distinctiveness.

| Rank | Member | Why here |
|---|---|---|
| 1 | K1 Sessions run each other | The claim no other setup makes; also the reader's reason to keep reading. |
| 2 | K2 Parallel work cannot collide | The precondition K1 would be reckless without. |
| 3 | K3 Autonomy is bounded | The second precondition — broader than K2 (every call, not just concurrent ones). |
| 4 | K4 Nothing dies with the session | Durability: valuable, but conventional in kind. |
| 5 | K5 Deploys from git | Most conventional, and doubles as the call to action (`./install.sh`). |

**Time order was considered and rejected.** A life-of-a-work-unit sequence (start → run →
hand off → land → recall) is equally valid logically, but it buries the distinctive claim
in position 3, and a README reader who bounces at 30 seconds would never reach it. Degree
order is a reader-service decision, recorded here so it is not mistaken for the only
option.

Within sections, order is structural (parts of a whole) or time (a sequence of events) as
the content dictates — never arbitrary.

**Exit checklist**
- [x] Key-line order is one of the four, named and justified
- [x] The rejected alternative order is recorded with its reason
- [x] Within-section orders are named, not accidental

---

## Session 7 — Summarize insightfully

**Rule applied:** no heading may be a category. Every section heading is rewritten as the
key-line assertion it stands for, so a reader who skims only the headings receives the
whole argument.

| Old heading | Verdict | New heading |
|---|---|---|
| "What's inside" | Blank category (D5) | *deleted* — its table becomes the key line, headed by the governing thought |
| "Stats" | Blank category (D5) | *deleted* — numbers move into the hero badges and the key-line rows where they are evidence |
| "Sync" | Blank category (D5) | folded into K5: "Edits to a live hook land in this repo" |
| "Deploy model" | Category-ish | K5: "The system deploys from git — and can't drift" |
| "Run unlimited parallel sessions" | Idea ✓, but imperative | K2: "Parallel work cannot collide" |
| "Lifecycle hooks on every tool call" | Idea ✓ but states the mechanism, not the judgment | K3: "Autonomy is bounded — 69 hooks refuse the calls that lose work" |
| "Every Write is recoverable" | Idea ✓ | absorbed into K4 |
| "Autonomous fleet operations" | Category | K1: "Sessions run each other" |

**Intellectually-blank-assertion sweep (Ch 7 p. 94).** "Seven subsystems, each fixing one
way a single-machine Claude workflow breaks down" tells the *kind* of idea, not the idea.
Replaced with the governing thought, which carries the judgment.

**Exit checklist**
- [x] No heading is a category label
- [x] Headings read alone as the complete argument
- [x] No "there are N things" assertions remain

---

## Session 8 — Pre-writing gate

| Gate | Result |
|---|---|
| Governing thought is one idea, and answers the Q raised in the introduction | **pass** |
| Key line members are the same kind of idea, MECE, ≤5 | **pass** (5) |
| Each member summarizes, not labels, its section | **pass** |
| Logical order named and justified | **pass** (degree) |
| Horizontal logic pure per grouping | **pass** (inductive key line) |
| Introduction reminds only; no exhibits | **pass** |
| No category headings, no blank assertions | **pass** |
| **30-second test** — introduction + main point + key line inside the first screen | **pass by construction**: hero assertion → S-C-Q (4 sentences) → 5-row key line, all above the first section |
| Every factual claim re-derived from disk this session | **pass** — D8 stale figures corrected (see Session 9) |

**Gate passed → drafting authorized.**

---

## Session 9 — Reflect the pyramid in the output

**Fact corrections applied** (D8 — every number re-derived from disk on 2026-07-28, not
carried over):

| Claim | Old README | Disk truth | Source |
|---|---|---|---|
| Files | 470+ | **601** | `git ls-files \| wc -l` |
| Lines | 43,000+ | **117,628** | `git ls-files -z \| xargs -0 wc -l` |
| Hooks | 59 ("30+ across 8 events" elsewhere) | **60 scripts, 69 wired entries, 12 events** | `ls hooks/*.sh`; live `settings.json` |
| Tests | 1,398 in 16,500 lines | **2,307 in 30,656 lines, 144 files** | `grep -c '@test' tests/*.bats` |
| `bin/` tools | 39 | **45** | `ls bin \| grep -v __pycache__` |
| Daemons | 12 | **13** | `ls launchd/*.plist` |
| Sessions indexed | 5,200+ | **5,709** | `sqlite3 session-index.db` |
| Permissions | 350 / 6 / 41 | **unchanged — verified** | live `settings.json` |

**Visual system.** Diagrams are pre-rendered through the `beautiful-mermaid` pipeline
(`beautiful-mermaid-docs` skill) so GitHub shows the ELK-based renderer instead of its own
dagre output: `assets/diagrams/*.mmd` → `-dark.svg` + `-light.svg`, embedded in
`<picture>` with a collapsed native-mermaid fence beneath for zoom/pan/select. The
handoff choreography — self-open, two-way mail, self-close — is a hand-authored **animated
SVG**, because pane choreography is a *motion* fact that no static diagram carries.

**Exit checklist**
- [x] Document order == pyramid order
- [x] Headings == key-line assertions
- [x] Every number traced to a disk read performed this session
- [x] Diagrams carry argument, not decoration

---

## Session 10 — Post-output critique

**Round 1 of 2** (the loop is capped at 2 — Execution contract, rule 4).

### Vertical relationship — does each section answer the question its heading raises?

| Heading | Question it raises | Answered by | Verdict |
|---|---|---|---|
| 1. Sessions run each other | *How?* | four touchpoints table · comms model · operator paging | pass |
| 2. Parallel work cannot collide | *Why can't it?* | lanes diagram · the three traps, each with its mechanism | pass |
| 3. Autonomy is bounded | *Bounded how, and by what?* | guardrail pipeline · 6 named hooks · permission tiers | pass |
| 4. Nothing a session did dies with it | *What survives, and how do I get it back?* | four layers, each with its recovery command | pass |
| 5. The whole system deploys from git | *How do I get it, and what stops it drifting?* | deploy model · install · atomic version swap · tests | pass |

### Defects found and fixed in this round

| # | Defect | Fix |
|---|---|---|
| C1 | Coverage audit against the old README found four items compressed away that carried real value: the `~/.claude` directory tree, the `prune-backups.sh` link, `claude-update --cleanup`, and the notification sound mapping. | All four restored — the tree as a `<details>` in §5, the rest inline. |
| C2 | "60 hook scripts are wired as 69 entries" conflates two different sets — not every repo script is wired, and some wired entries are not repo scripts. | Restated: "ships 60 hook scripts; the live config wires 69 entries across 12 events." |
| C3 | `com.claude.postland-verify` was described as firing "on land"; its plist is `StartInterval 300`. | Corrected to 5 min. Also sharpened "weekly" → "Sun 3 am" from the plist. |
| C4 | Two mermaid nodes (`Lock`, `Box`) were referenced before their labels were defined and rendered as bare ids. | Definitions moved ahead of first use. |
| C5 | `deploy-model`'s dashed back-edge made ELK rank `~/.claude` *above* the repo, inverting the hierarchy. | Replaced with a bidirectional edge carrying the same meaning. |
| C6 | Two diagrams were wide enough that GitHub's column scaled their text to illegibility. | Converted to `TB`; the widest is now 909 px, the tallest 552 px wide. |
| C7 | In the animation, the act-3 scrim fired at 76% — over the self-close lines the viewer had not yet read — and at 0.72 opacity left dimmed text bleeding through. | Retimed to 82–88% and raised to 0.96. |

### Incident during verification (recorded because the lesson is durable)

Reading the daemon schedules, I ran `plutil -extract <key> json <file>` **without `-o`**, which rewrites the plist in place. It destroyed `com.claude.nightly-regression.plist` and `com.claude.session-search-backfill.plist` (−76 lines). Both were restored from git (`git checkout --` on the two explicit paths; `launchd/` verified clean) and re-read with `grep` instead. This is the exact failure already recorded in memory `plutil-extract-clobbers-input.md` — the read-only-looking form of a mutating command. **Use `plutil -extract k json -o - <file>`, or don't use `plutil` to read.**

### Variance log — deliberate omissions, not oversights

- **The session-index source-priority table** (`sessions-index.json (100) > session-end (50) > sweep (25) > stub (0)`) is implementation detail of a subsystem that lives in [its own repo](https://github.com/renchris/claude-session-search). Omitted under the minimum-volume constraint; the three-hook mechanism it explains is retained.
- **"Reference" is a category heading**, which Session 7 otherwise forbids. It is a deliberate appendix holding the material Session 5 demoted as non-inferring "news" (daemon roster, browser wrapper, aliases). Labelling an appendix honestly beats pretending it argues something.
- **`<picture>` + `prefers-color-scheme` follows the reader's OS/browser setting, not GitHub's theme toggle.** A reader in OS-light with GitHub-dark sees the light SVG on a dark page. This is a platform limit with no workaround; both variants are legible on both backgrounds, which is why the palette was hand-tuned per mode rather than auto-derived.

### Final gates

| Gate | Result |
|---|---|
| 30-second test — introduction + governing thought + key line above the first section | **pass** (verified in a rendered screenshot, not by inspection of the source) |
| Headings read alone as the complete argument | **pass** |
| Every anchor and every relative path resolves | **pass** — programmatic sweep, 0 bad |
| Diagrams deterministic + fences in sync | **pass** — `npm run diagrams:check` green; double-render byte-identical |
| Both color variants visually verified | **pass** — headless Chrome on `#0d1117` and `#ffffff` |
| Animation verified across its three acts | **pass** — sampled at t=3 s, 8 s, 12 s, 15 s |
| Every number traced to a disk read from this session | **pass** |

**Round 2 not required — no defect survived round 1.** Rework loop closed at 1 of 2.

---

## Land attempt — blocked by a pre-existing trunk red (not this work)

`handoff-fire.sh land --worktree …` → `scripts/ship-land.sh`. Both ratchets clean, the
full 144-suite bats corpus ran, and the rail exited **6 (gate red)** without pushing —
correct fail-closed behaviour.

**The red is not this branch's.** `tests/test-walltime-lint.bats` tests 1–2 assert the
**whole tree** is clean, and the ratchet reports `cc-relogin-status.bats` as *fixed but
still grandfathered* — its fixture was converted to a relative seed in `2a979c15`, but its
line was never deleted from `EMBEDDED_ALLOWLIST`, and the ratchet only shrinks.

Proven pre-existing, not assumed: a detached control worktree at pristine `origin/main`
(`ea6f7b5a`, none of this work present) reproduces the identical 2 failures. This diff
contains no `.bats` file, and the lint's own **own-scope** leg correctly rated this land
advisory-clean — it is the suite's whole-tree assertion that blocks.

**Stood down rather than fixing it.** The one-line deletion already exists as `11925061`
on `land-pipeline-v2` — 11 commits ahead of trunk, last commit 16 minutes old, three live
sessions, actively red-proofing the land pipeline. Duplicating a same-hunk one-liner into a
competing land is the exact convergence anti-pattern ([[parallel-stream-convergence-protocol]]):
on being the duplicate, stand down. Their stack lands it.

**Re-land verbatim once trunk is green** (the branch is committed, clean, and needs no
further edit):

```
~/.claude/scripts/handoff-fire.sh land \
  --worktree /Users/chrisren/Development/.worktrees/wt-readme-pyramid \
  --repo /Users/chrisren/Development/claude-infrastructure
```

**Systemic note for whoever owns the land pipeline:** the own-scope fix
([[whole-tree-lint-is-a-fleet-wide-hard-stop]]) was applied to `test-walltime-lint.sh` but
not to the whole-tree assertion inside its own bats suite — so a stale ratchet entry still
reds the gate fleet-wide for every author, which is precisely the failure own-scope existed
to end.
