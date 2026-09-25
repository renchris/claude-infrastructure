# README rewrite 2026-09-24 — Pyramid worklog

## Session 0 — Intake, classification, routing

- **Mode:** R (review/repair) — reverse-engineer the existing README's pyramid, audit it through
  Sessions 4–8, rewrite in 9, critique in 10.
- **Bounded input body:** `README.md` at `d570ed0bf` — 17,039 words × 1.4 ≈ **24K tokens**, plus the
  Session-3 extraction returns (9–10 slices × ≤2K tokens ≈ 20K). Total ≈ **44K tokens → Tier B**
  (inline spine + the rule-3 extraction fan-out). The rest of the repo (6,311 tracked files,
  2,969 commits since the last structural rewrite on 2026-08-12) is NOT read in bulk: it is sliced
  by subsystem and returned as grounded candidates only.
- **Reader:** a Claude Code power user or engineer landing on the GitHub page (primary); the
  operator and future sessions of this repo (secondary). Many readers, scrolled medium.
- **Medium:** GitHub README (markdown + inline animated SVG/WebP; `<video>` is stripped).
- **What the reader should KNOW/DO after reading:** in 30 seconds — what this is (a git-deployed
  `~/.claude` under which many Claude Code sessions run each other unattended), why it is credible
  (measured, tested, dated), and where to go next (install, the map, the evidence).
- **Route:** 3 (reverse-engineer + extraction fan) → 4 → 5 → 6 → 7 → 8 gate → 9 rewrite → 10.
- **Constraints:** figures re-measured, never quoted; every linked path existence-checked;
  no superseded model literal (claude-lint-models.sh); animated assets generated, never
  hand-drawn, and verified by the repo's own gates.

## Session 3 — extraction returns (fan-out, 10 read-only slices; key facts only)

**Census (slice 8, d570ed0bf):** 5,931 tracked files excl vendor/assets/node_modules; **1,422,360
lines** (README recipe `xargs wc -l | tail -1` was BROKEN — last xargs batch only, 286,907);
756 bats files / **15,570 @test**; live hooks **105 entries / 21 events**; sessions 3,972
top-level transcripts (11,796 incl 7,824 subagent files); bin 121 (101 `cc-*`); hooks/*.sh 90;
scripts 322; commands 25; skills 37; agents 5; migrations 44 numbered (last 0041); launchd 28
top-level plists (26 loaded) + 5 staged; docs 4,076 tracked (research 3,698); tools 38; assets 95
(49 unreferenced); vendor 285; **5,732 commits**, first 2026-03-24; per month 03:4 04:24 05:0
06:19 07:1,519 08:2,360 09(→24th):1,806. No broken relative links in README.

**§2 (slice 2):** land-lock hold 14d n=938 p50 3s / p90 8s / p99 343s; end-to-end land p50 870s /
p90 2609s (n=531) — "seconds-to-minutes" and "fast gate, seconds" are FALSE; smoke budget 180s/suite
cap 900s (966c092f0); deploy-live now edge-triggered by each land (cbcf90b1b, 09-17; before: 40.1%
of advances by hand, median commit→live 2.31h), launchd 600s tick is backstop; interactive lane
described BACKWARDS (da9b186f0: two-key rule, earliest weekly reset among 5h-safe, 15% hysteresis);
this repo ships no warm pool (new-worktree.sh). New: --recovery lane, wire-read limits,
postland bisect keyed on single failing test, land-speed-census.py.

**§3 (slice 3):** deny 41 / ask 3 / allow 344, defaultMode auto; per-event SessionStart 18 ·
UserPromptSubmit 7 · PreToolUse 18 · PostToolUse 15 · Stop 13 · SessionEnd 7 · Notification 5 ·
PermissionRequest 4 · PreCompact 3 · PostToolUseFailure 3 · FileChanged 2 · 10 events ×1.
git-worktree-guard is Bash-only and guards worktree removal/branch deletion of a LIVE session (README
wrong); teammate-auto-shutdown returns {"continue":false} exit 0 (README "exit 2" wrong); template
settings.example.json out of sync (78/14). New guards: validate-bash denies `git commit` in the
shared checkout (1e9acf553); handoff-claim-assert (Stop) blocks a "run this" hand-off the session
could have run itself (165/1,379 refuted, 0 false blocks); conviction gate (asks need a number +
receipt); email drafts-only; kill-selection denies (empty selector once killed kitty + ~17 sessions
in 9 s); handed-off-session-guard; pr-gate.

**Models/launchers (slice 7):** `claude` = Opus 5.5 (`claude-opus-5-5`, since 2026-09-22) on
binary 2.1.280, effort high, auto mode, spawn depth 1; bare `claude` ROUTES to an account
(claude1 pins); `claude-prev` = stable 2.1.114. Frontier = Fable 5.1 (`claude-fable-5-1`, 09-03).
Upgrade gate = **15 checks** (last run 2.1.280 × claude-opus-5-5 GREEN 14 pass/1 skip). Stale in
README: "Opus 5", "13 checks", 2118-hold row (it polls 3 GH issues blocking 2.1.114→2.1.118).
Slim CLAUDE.md A/B: −54% tokens, −34.6% cost, F1 INCONCLUSIVE. LINT: never write `claude-opus-5`
or `claude-fable-5` followed by a non-digit/non-dash; prose "Opus 5" is invisible to the lint.

**Assets (slice 9):** banner gen.py regenerates all 4 variants byte-identical; hero v6c passes
banner-verify 6/6 (27.7 s); redproof is 41 cases (README says 37). timeline gen.py `--check`;
`npm run diagrams[:check]` (node_modules absent in worktree — copy/install first). Tools present:
vhs ffmpeg gif2webp img2webp magick node 22 python3; Playwright headless chrome under
~/Library/Caches/ms-playwright. Last hero change 2026-08-18.

**§1 (slice 1):** mailbox drains at SessionStart, UserPromptSubmit AND PostToolUse (≤1/20 s) —
diagram's "post-tool channel unwired" is FALSE; idle wake is mailbox-wake-arm (asyncRewake);
--recycle takes --worktree/--cwd/--account and re-picks the account; warm worktree only with
--worktree + a repo that ships a pool. New: `cc-lr` front end (find/recover/status/repair/switch/
upgrade); `cc-lr switch` moves a session to another account in place (same uuid); `cc-lr upgrade`
moves idle sessions onto the new binary/model one at a time, never mid-turn; remote in-place
recycle; recycle/self-close refuse (exit 4) while subagents are in flight; `self-close --terminal`
refuses (exit 8) over unlanded commits or an unmet DoD; custody ledger; /goal armed on every fire
after engagement is proven.

**§6 (slice 6):** kitty has been the ONLY working terminal since 2026-08-03 (TERMINAL_AGNOSTIC_L3_L4
§9; 0 iTerm2 processes; iTerm2 retired, seam dormant). "Beacon has no face" is FALSE (cc-queue,
cc-blockers, lead-supervisor doubling ladder) — but oversight is still PULL: operator wait on a
permission block p90 28 min, p95 2.55 h (kitty-pane-attention-2026-09-13). Off-box lane is NOT a
capacity valve (cloud draws the same Max quota; 0 capacity refusals over 297 fires —
cloud-lane-redesign-2026-09-10 §0); kept-and-fixed at 70%. compressor-sentinel escaped 3 more
times (08-24, 09-16 ×2 clang-format swarm) and was hardened; no panic since 2026-09-16 boot. Load
gate still an underived 2.0/core. Keep in README: (1) the ceiling is finding the blocked session,
(2) RAM is not binding, (3) macOS compressor panic + sentinel, (4) load gate/more cores is wrong
purchase. Everything else (terminal tables, films, jcode) → docs/research links.

**§4/§5 (slice 4):** backup names are seconds+PID (not nanosecond); session index 8,660 rows;
plan-history 6,243 commits; deploy-live has four tiers T1/T1H/T2(degraded, lag >25 commits or
>6 h)/T3 (refuse), verifier ~0.17 greens/day so T2 is the common path; deploy convergence checks the
RUNNING bytes (0c34771ca); nightly-regression is loaded live though fleet.manifest says staged
(repo/machine disagree — omit the claim); 28 plists / 26 loaded; migrations 44 (43 c10 staged for
the operator, 1 mechanical; ledger 1 applied / 43 staged / 0 failed); upgrade gate 15 checks;
test lines 271,168; identity-class backups per account (4df511fa0).

**Autonomy (slice 5):** WHAT NEXT — the customer mission board (`cc-mission render` →
~/.claude/rules/00-mission-board.md, loaded by every session) outranks infra; dispatcher 300 s
backstop + kicked by every backlog write, ceiling 12 local / 6 cloud, ≤2 fires/pass, 3 projects;
discovery hourly with 4 critics. WHEN TO STOP — wrap-ledger's seven rungs; completion-assert
blocks a contradicted "done"; ✅ SAFE TO CLOSE only on a written, verified turn. WHEN TO ASK — work
is filed only under 4 impossibility classes (needs-credential · needs-human · not-yet-true ·
no-capacity); an ask needs conviction ≤90 + a receipt; >90 is refused ("implement it"). An agent
may move a mission row to awaiting-signoff only; `cc-signoff` refuses a claude parent process.
Numbers: backlog 3,823 rows (3,589 done · 216 blocked · 18 open); 307 decision packets (27 open).
cc-digest is NOT scheduled (manual) — drop "daily digest with phone push".

**Convergence (slice 10):** both leads stand (4 d, 28 d); no newer priority analysis; Claude Code's
native messaging (v2.1.224; Windows v2.1.234) now runs BESIDE the repo's mailbox (live duplication,
wake-socket-repricing-2026-09-10). /goal and ProposeGoal were Claude Code first. grok-wiki: no saved
wiki for this repo; one `ask` (codex) mostly read the README back — weak evidence; it promotes the
desk/dispatch layer to a subsystem, which agrees with the missing "you only decide" point below.

## Session 3 — the pyramid (mode R: existing structure, then the rebuilt one)

**Existing README, reverse-engineered.** Top: "`~/.claude` becomes a system you deploy — and the
sessions become the schedulers." Key Line = §1–§5 (properties) + §6 (a LIMIT). Defects:
1. "Twice, this repo shipped it first" sits between the intro and the Key Line — answers a question
   (why believe it?) before the reader's question (how?) is answered. Caveat 5 / vertical-logic break.
2. §6 is not a property — misfit in the plural noun; and it is ~45% of the page (terminal tables,
   films, jcode) — reference material posing as argument.
3. The governing thought has three clauses and the Key Line covers two: "you only decide" — the
   autonomy decision layer (close rungs, conviction-gated asks, mission board) — has one paragraph.
4. §5 (the "deploy" half of the top box) comes fifth, after the sessions it deploys.
5. ~40 stale facts (census above), incl. two inverted claims (interactive lane; beacon "has no face")
   and a broken measurement recipe.

**Rebuilt pyramid (top-down).**
- Subject: running Claude Code at fleet scale. Reader's Question: *How do I run dozens of Claude Code
  sessions at once, unattended, without losing work — or becoming the scheduler myself?*
- S: Claude Code reads everything it does from `~/.claude`, and is built for one session a human watches.
- C: Run thirty at once and `~/.claude` is unversioned machine state, the sessions share one git
  index and one trunk, and the human becomes the scheduler — firing, watching panes, finding the
  blocked one, judging "done".
- A (governing thought): **Deploy `~/.claude` from git, and let the sessions run each other — so the
  human is left only the decisions.**
- New Question: How? → Key Line, INDUCTIVE, plural noun = "the three layers of the system", order
  STRUCTURAL, outside-in from what the reader sees running (sessions) → what reaches the reader
  (decisions) → what sits underneath (the deployed system):
  1. **The sessions run each other** — they open, brief, message, move and retire one another.
     Q raised: how, without chaos? → children (time order: the life of one piece of work):
     1.1 a session fires a peer and hears back from it (fire · message · recycle · switch · self-close)
     1.2 each works in its own lane and lands through one lock (worktree · account · land-lock · content-verify)
     1.3 every tool call it makes can be refused (hooks · deny rules)
     1.4 if it dies, nothing it did dies with it (backups · plan history · transcripts · resume)
  2. **You are asked only for decisions** — a session cannot declare itself done, and cannot hand
     you work it could do. Q: how does it know when to stop and when to ask? → children:
     2.1 what to work on next is ranked for it (mission board > backlog → dispatcher)
     2.2 "done" is computed from live git, not claimed (seven rungs · completion-assert · SAFE TO CLOSE)
     2.3 an ask must carry a number and a receipt (4 impossibility classes · conviction ≤90 · packets)
     2.4 what reaches you is one runnable command (operator-readout · cc-do · cc-blockers)
  3. **The whole system deploys from git** — tested, landed and proven live. Q: how do you trust
     code that edits its own controller? → children:
     3.1 `~/.claude` is a symlink deployment of this repo (install.sh · per-account dirs)
     3.2 every land is tested and verified by content (15,570 tests · postland-verify)
     3.3 landed is not live until the running bytes match (deploy-live tiers · edge-triggered)
     3.4 a binary update cannot break a running session (versioned installs · upgrade gate · cc-lr upgrade)
- Coda (answers the question the Answer raises next — "why believe it, and where does it stop?"),
  NOT a Key Line point: **Measured, not claimed — including where it falls short**: convergence
  (2 leads, 3 refuted, 1 loss), the ceiling (finding the blocked session: p90 28 min wait; RAM not
  binding; macOS compressor panic + sentinel).
- Apparatus: Install · Map · Glossary. Reference prose (daemons, launchers, kitty chords, demo
  re-recording, terminal bakeoff) moves VERBATIM-plus-corrections to `docs/README-reference.md`.

Caveats: (1) top-down first ✓; (2) S→C→Q thought in order ✓; (3) intro thought through ✓;
(4) history (the May silence, the vendor dates) kept out of the body — coda only ✓; (5) intro holds
only what a Claude Code user accepts ✓; (6) Key Line inductive ✓. Groupings ≤4 ✓.

**Execution locus.** The hero launch film is a separate implementation track → dispatched session
(pane 733, account next3, xhigh, branch feat/readme-hero-film, goal armed + verified). The lead keeps
README.md, the diagrams and the reference doc. Two fire refusals first: the F3 payload-lint rejects
a brief that names the peer-mail CLI without a resolvable target — the fix was to drop the literal and
let --notify-back materialise the back-channel.

## Session 4 — introductions

- Pattern: "How should we do it?" — new capability (App B: S = we must do X / C = we are not set up /
  Q = how get set up?). Tone: **direct** (A→S→C): a README visitor scans; the hero + the governing
  thought come first, the S-C in three sentences under it. Business-Week test: every S sentence is
  something a Claude Code user already accepts (it reads `~/.claude`; it is built for one watched
  session). The C is the last thing they know (thirty sessions → shared index, unversioned state,
  human as scheduler). No exhibits in the intro — the figures move to the badges and the coda.
- Key Line set out as a three-row table right under the intro (long doc) — each row an idea, each
  with the one thing it removes from the human's job.
- Mini S-C-Q per Key Line section: §1 opens "a session is a process, not a terminal you watch";
  §2 opens "the hard part of autonomy is not starting work but knowing when to stop and when to ask";
  §3 opens "a system that edits its own controller has to be deployable and revertible like any other".

## Session 5 — horizontal logic

- Key Line: I (layers; plural noun ✓; no misfit now that the limit is a coda).
- §1 children: I, "stages in one piece of work's life" (fire → lane → guard → survive). No masquerade.
- §2 children: I, "the four points where the system decides for you or asks you". ✓
- §3 children: I, "the four places deployment could break, and what closes each". ✓
- Coda: D (claims tested → two stand, three fell, one loss published → therefore the lead is close
  to base rate, and it is published anyway). ≤4 points ✓.

## Session 6 — order

- Key Line: structural, outside-in (what runs → what reaches you → what is underneath). Completeness:
  is anything neither a session behaviour, a human interface, nor the substrate? Install / Map are
  apparatus, not ideas ✓.
- §1: time order (life of the work). Missing step? "what it works on next" belongs to §2.1 ✓.
- §2: time order of a close (pick → finish → close/ask → hand over).
- §3: time order of a change (installed → tested/landed → live → binary upgraded).

## Session 7 — summaries (before → after)

| Parent | Before | After |
|---|---|---|
| top | "~/.claude becomes a system you deploy — and the sessions become the schedulers." | "`~/.claude`, deployed from git. The sessions run each other. You only decide." |
| §1 | "Sessions run each other" | "The sessions run each other — and none of them can lose your work" |
| §2 | (absent; one paragraph "It pages you only when…") | "You are asked only for decisions — a session cannot call itself done, and cannot hand you work it could do" |
| §3 | "The whole system deploys from git" | "The whole system deploys from git — and landed is not live until the running bytes match" |
| §6 | "The ceiling is the interface, not the machine" | coda: "Measured, not claimed — including where it falls short" |

## Session 8 — pre-writing gate

A ✓ one thought governs; summaries are true of their children; groupings one kind each; ordered.
B ✓ every heading is an idea; vertical Q/A traced above; no unraised question answered (convergence
moved behind the Key Line). C ✓ top-down, six caveats named in S3. D ✓ direct tone, one Question,
S-C remind only. E ✓ Key Line inductive; coda deductive at low level. F ✓ orders named, ≤4 each.
G ✓ no blank assertions (the old "Five kernel panics…" style counts are either sourced or cut).
H n/a (mode R). I — 30-second test: hero (the film) → governing thought → S-C (3 sentences) →
three-row Key Line table. A cold reader knows what it is, how it works, and where Install is. PASS.

## Session 9 — draft (state at 2026-09-25 10:05)

- README.md rewritten in the worktree (7,899 words incl. alt text, from 17,039). Committed on
  docs/readme-opus55: 83f9d6f44 (docs/README-reference.md — moved detail, corrections marked),
  f67f3c476 (diagrams re-measured + new decision-flow). README.md itself is UNCOMMITTED until the
  Session-10 critique and the hero land.
- The hero block references assets/hero/hero-{dark,light}.webp with HERO_ALT / HERO_CAPTION
  placeholders — to be filled from the film session's ping (pane 733, branch feat/readme-hero-film).
- Checks run: every relative link and anchor resolves except the two pending hero files;
  `npm run diagrams:check` → all 16 SVGs + fences up to date; claude-lint-models rc=0.
- The OVERWRITE GUARD fired on the README write (backup ~/.claude/backups/README.md__20260925-100405-66697.bak);
  this was the requested rewrite, and every removed section is preserved in docs/README-reference.md.

## Session 10 — critique (2 lenses over the frozen draft) and variance log

Lens A (Minto structure) and lens B (cold reader + 24-claim accuracy check), fresh context each.
One repair round applied; round 2 not needed (all checks re-run green below).

| Defect | Owner | Fix |
|---|---|---|
| Governing thought overclaimed "spotting the stuck session" (contradicted by the coda) | S3 | Intro now names that job as still yours and links to where it is measured |
| Key Line order (sessions, decide, deploy) ≠ governing thought order (deploy, sessions, decide) | S6 | Sections reordered to match the hero line: §1 deploy · §2 sessions · §3 decide — structural order bottom-up (substrate → workers → you), and §3 now flows into the oversight coda |
| "Four things keep that from chaos, in the order…", "four points in the life of a close", "three things break", "two claims a reader should doubt" — blank assertions / unnamed | S7 | Each replaced by the idea the items share; the two claims are named |
| Headings with no antecedent ("Each works…", "Every tool call it makes…"); Install nested under §3; lone Glossary heading; non-parallel coda children | S9 | "Every session…", "Any command a session runs…"; Install is an H2; Glossary folded into the Map as a details block; both coda children are claims |
| Headings overclaiming: "Every land is tested…", "Nothing … dies with it", "one runnable command", "The same walls produce the same inventions" | S7 | "Every trunk tree is proven in the background…", "…dies with its pane", "one decision or one command", "…and twice so far this repo got there first" |
| Binary update filed under "deploys from git" without the governing point covering it | S5 | §1's point widened: "versioned, tested and revertible… down to the binary it runs on" |
| `/exit` rationale answered an unraised question; vendor-timing aside in §1; "portable" aside in §1 | S9 | `/exit` → reference doc; vendor aside cut from §1 (kept in the coda); portable note → Install |
| ACCURACY: "every question needs two options" (only class C) | S9 | fixed |
| ACCURACY: "cannot retire its pane over unlanded commits" (only `--terminal`) | S9 | fixed |
| ACCURACY: "a week of measurement found ~2.3%" (a model fitted to 55 runs) | S9 | fixed |
| 6-claims arithmetic (2+3≠6) | S9 | "The sixth was a loss" |
| Jargon at first use (fire, rung, statics, ratchets, fresh cell, drivable, claim/reap/thrash, arrives, pull/push) | S9 | glossed or rewritten in plain words |
| Recipes hidden in an HTML comment | S9 | visible `<details>` block with the recipes |
| No requirements line; 2.1.114 pin unexplained; 4 vs 5 config dirs unclear | S9 | added |

Residuals accepted: badge/session counts are a 2026-09-24 snapshot (the index had grown to 8,754 by
the critique) — stated as "when this was written"; the handoff-live demo was recorded on iTerm2 —
captioned as such.

Checks after repair: links + anchors resolve in README.md and docs/README-reference.md (only the two
hero files pending); `npm run diagrams:check` green; `claude-lint-models.sh` rc 0.
