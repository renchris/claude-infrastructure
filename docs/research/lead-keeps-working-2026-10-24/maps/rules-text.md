# Map: the rule-text layer (slot rules-text)

Worktree `lead-idle-fix` at `958b23030`. Every line number below is in this worktree unless prefixed
with `~/`. "Measured" means a command was run here; "inferred" means read from code without running.
Everything was read-only except this file.

Short labels used throughout: `R` = `CLAUDE.rules.slim.10-session-close.md` (deployed as
`~/.claude/rules/10-session-close.md`), `S` = `CLAUDE.global.slim.md` (deployed as `~/.claude/CLAUDE.md`),
`G` = `CLAUDE.global.md` (deployed as `~/.claude/CLAUDE.full.md`, which no session loads).

---

## 1. What every session loads, and how it gets there

| Repo source | Deployed to | Mechanism | Loaded? |
|---|---|---|---|
| `S` | `~/.claude/CLAUDE.md` | install.sh copies the selected variant as a real file, never a symlink (`install.sh:1132-1139`). The variant comes from registry line `global <v>` in `~/.claude/instruction-variants`, default slim (`install.sh:1105-1112`). | Yes, every session on every account |
| `R` | `~/.claude/rules/10-session-close.md` | install.sh globs `CLAUDE.rules.<variant>.*.md` and copies each one to `rules/<name>.md`, only when the variant is not `full` (`install.sh:1113-1131`). The copy runs before CLAUDE.md "so a session starting mid-install sees the section twice rather than not at all" (`:1115-1116`). | Yes, every session |
| `G` | `~/.claude/CLAUDE.full.md` | `install.sh:1080-1087`, which says "not loaded by any session" (`:1083`) | No |
| (generated) | `~/.claude/rules/00-mission-board.md` | written by `cc-mission render`, and exempt from the stray-rule sweep (`install.sh:1148`) | Yes |

Measured live state:
- `~/.claude/instruction-variants` is 0 bytes, so the default slim applies (`ls -la`, `wc -c`).
- `cmp ~/.claude/CLAUDE.md CLAUDE.global.slim.md` matches, and so does `cmp ~/.claude/rules/10-session-close.md CLAUDE.rules.slim.10-session-close.md`.
- `~/.claude/rules/` holds exactly `00-mission-board.md` and `10-session-close.md` (`ls -la`).
- `~/.claude-{next,secondary,tertiary,quaternary}/rules` are symlinks to `~/.claude/rules`, and those accounts' `CLAUDE.md` are symlinks to `~/.claude/CLAUDE.md` (`ls -la`).

So one real file in each location reaches all five accounts.

**Stray sweep.** Anything in `~/.claude/rules/` that is neither the variant's rule set nor the mission board is moved to `backups/rules-retired/` on every install (`install.sh:1142-1156`). Tests pin both directions:
- `tests/install-instructions-variant.bats:66-78`: a slim rule deploys as a copy and survives the sweep.
- `tests/install-instructions-variant.bats:80-89`: under `global full` the slim rule set is not deployed, and an already-deployed copy is retired.

**Convergence.** `scripts/deploy-live.sh` runs install.sh after its fast-forward (`deploy-live.sh:52`), and the project CLAUDE.md confirms the degraded tier "still runs `install.sh` so brand-new tracked files get their symlinks" (`.claude/CLAUDE.md:53-54`). A rule edit therefore goes live at the next converge, not at land.

**Subagents.** A `workflow-lean` slot "loads no CLAUDE.md, rules, memory or skills" (`S:117`). Any grant or rule text added here reaches leads and default agents only.

---

## 2. Quote catalogue: every sentence that bears on stopping while a decision is open

Each row gives the effect, file:line, a verbatim quote (trimmed with …), and a note.

Effect codes:
- **STOP**: licenses stopping or yielding
- **→C**: routes a decision to class C (or to an unclassed ⛔)
- **DRIVE**: forbids stopping, or says to keep working
- **MEAN**: says what to do meanwhile
- **RULING**: about finding or recording an existing ruling

### 2a. `R` (the close rules, always loaded)

| Effect | Where | Verbatim | Note |
|---|---|---|---|
| DRIVE | R:4 | "Drive in-scope work to a finished, verified, committed state … without stopping to ask; surface everything else" | Top-level mandate, but nothing says how it interacts with an open decision |
| STOP | R:26 | "If the scope cannot be reconstructed, stop and ask." | Not the incident: the scope was explicit |
| **STOP** | **R:38** | "\| Needs a decision (destructive migration, auth, navigation pattern, DB timeout) or information \| Stop and ask, overriding auto-continue; commit in-progress work first. \|" | **The core license.** "Overriding auto-continue" applies to the whole session, not to the items the decision gates. The parenthetical lists G2 escalation surfaces, but it reads as examples, not a closed list |
| STOP | R:39 | "Security or data-integrity issues: stop and surface now." | Legitimate stop |
| STOP | R:43 | "Auto-continue requires all four; otherwise surface or ask:" | G1-G4 gate one item, but "otherwise surface or ask" has no scope qualifier |
| STOP | R:49 | "Explicit pauses ("stop here", "come back to this") are terminal-valid parked WIP." | Operator-only |
| STOP | R:62 | "a `/ship` that refuses to land … is a ⛔ to surface, not a silent 📦." | Legitimate |
| **→C / STOP** | **R:68** | "At or below 90%, research exhaustively, then implement if you are now above 90%; otherwise hand it to the operator with the number, the research receipt and the measured options in operator terms. … `cc-decide open --class C` refuse[s] without `--conviction N --receipt …`" | **Licenses the hand-over** (B13: 85 and 75). It never says to keep the status-quo course meanwhile, and it names only class C as the vehicle. No step says to search for an existing ruling first |
| DRIVE | R:72 | "stop and ask only for a genuine fork or escalation. Asking the operator to re-affirm a PASS is a defect" | "Genuine fork" is undefined, so a loop stop-rule reads as one |
| RULING | R:74 | "Active research program exemption (operator ruling 2026-10-01, decision packet `83adb541ea19` …)" | The only place `R` records an operator ruling with its packet id. This is the precedent format for a standing grant |
| STOP | R:84 | "Done … requires … no pending decision. Otherwise hedge … ("blocked on your decision: DROP X")" | Correct: it governs the done-claim, not working |
| STOP | R:92 | "⛔ Blocked: a decision or information is needed. `⛔ Blocked — need your call: <decision>.`" | **Prescribes the literal phrase "need your call:"** (see §5 hazard 1) |
| →C | R:99 | "What it cannot drive it files (`cc-decide open`/`recheck <id>`) so the rung is `⛔`; its verdict: `no — research done, implementation pending: …`" | E0 routes undrivable findings to ⛔, and through R:160 that means class C |
| **STOP** | **R:103** | "Only ⛔, and 📦 in a repo whose own `CLAUDE.md` says landing spends money, may end a turn holding work." | **The second core license.** It has no clause saying ⛔ may end a turn only if the decision gates all remaining work |
| DRIVE | R:105 | "🔧 does not end a turn. Keep going … Naming the remaining items is not a close." | B13's loop scope had no checkboxes, so the ledger never read 🔧 |
| DRIVE | R:108 | "Do not idle waiting on the user because context is low." | Idle is forbidden for context, not for decisions |
| STOP | R:144 | "Under `⛔` keep the tail: it is `BLOCKED_WHAT`, the operator's own words." | |
| **→C** | **R:160** | "File a decision you are holding the moment you have it; filing is what makes it the `⛔` rung: `cc-decide open --class C --what … --conviction N --receipt R --option … --option …`. A class-B packet also carries `--conviction N --receipt R` … `wrap-ledger.sh` computes `⛔` from this session's open class-C packets" | **Every held decision goes to class C.** Class B appears only as a field note, with no criterion for choosing it and no mention of `--default`/`--deadline` |
| RULING | R:184 | "`needs-human` (a value call that is theirs; requires `--conviction N --receipt R` with N ≤ 90, and the row is born blocked)" | A backlog twin of R:68 |
| **STOP** | **R:189** | "BLOCKED: a genuine operator-only gate (credential, sudo, destructive migration, a real value fork). … At the exhaustion close — every Follow-On Gate pass and every item at 90%+ conviction driven, only operator decisions left — itemize only the decisions this session drove to the wall" | "A real value fork" is broad enough to cover B13. **The exhaustion close already encodes "drive everything else first"**, but only for the terminal close, not for an ordinary mid-work ⛔ |
| DRIVE | R:191 | "Offering researched, in-scope remaining work … is a defect … Drive it or drop it" | |
| →C | R:193 | "a value judgment goes through `cc-decide open`, not `cc-backlog needs`" | Unclassed, so it inherits class C from R:160 |
| **STOP** | **R:217** | "On 🔧, and only on 🔧, arm the continuation … Clear it … as soon as the state becomes ✅ / 📦 / ⛔ / 📤" | **Tells the lead to disarm its own continuation the moment it files a class-C packet** |
| STOP | R:223 | kill-switch: "…and stop", "no auto-continue", "just do X" | Operator-only |

### 2b. `S` (the global slim, always loaded)

| Effect | Where | Verbatim | Note |
|---|---|---|---|
| STOP | S:17 | "If you are unsure whether a file belongs, ask." | |
| STOP | S:27 | "A permission refusal … is an answer for that action. … stop and hand the refused command back to the user as it was." | A genuine gate. **Slim-only: `G` has no matching sentence** (`grep 'split, reworded' CLAUDE.global.md` finds nothing) |
| RULING | S:47 | "Run `cc-memory-search <terms>` first … and update an existing entry rather than adding a near-duplicate." | Search-first exists only for **writing memory**, never before asking |
| MEAN | S:48 | "A new entry that replaces a practice the operator stated needs the operator's ruling, and until it is given the entry carries `Replaces: <practice> — ruling pending`." | **The one existing "keep going while a ruling is pending" pattern**: the work proceeds and records that a ruling is pending |
| STOP | S:56 | "stop at the first rejection" (Dia browser actions) | |
| STOP | S:77 | "Adding a host widens a security bound, so ask the operator first." | Egress, so a genuine gate. Relevant to a Codex grant: Codex is a subscription CLI, not an `agent-secrets` API host |
| DRIVE | S:81 | "Parallelize without waiting to be asked (operator standing directive). … A peer's goal or ownership … claims the files … not the outcome: do the rest now" | **The precedent for "an owner or gate claims only what it covers; do the rest now"**, written for peers, not decisions |
| MEAN | S:100 | "`mailbox-wake-arm` wakes an idle session." | |
| STOP→model | S:134 | "before asking the operator about a decision still below 90% conviction, escalate the model." | Frontier ladder T-a..T-c |
| DRIVE | S:137 | "Without headroom the stage-1 document is the deliverable; report the degrade, do not block." | |
| MEAN | S:139 | "(whether it should be is an open operator decision, `docs/plans/NONLIMIT_RESUME_LADDER.md` § W3.6)" | A live example of the rules running normally while an operator decision is open |
| DRIVE | S:166 | "Idle (waiting or watching) at 35% or more … recycle or hand off now" | B13 sat at 64% for 11 h (incident report, boundary-handoff `freewin=⛔`) |
| STOP | S:197 | irreversible, money-spending steps are gated | Genuine money gate |
| STOP | S:203 | "If what remains is a decision, there is no script; ask it as the `⛔` rung." | "What remains" is the right scoping word, but it governs the manual-command hand-over only |

### 2c. `G` (the full text: not loaded, but the reference the slim says to read, `S:3`)

| Effect | Where | Verbatim |
|---|---|---|
| STOP | G:595 | "Unreconstructable scope is itself a STOP-ASK, never a guess." |
| **STOP** | **G:605** | "\| Needs a **decision** (destructive migration / auth / nav pattern / timeout) or **info** \| **STOP-ASK** (overrides auto-continue); commit in-progress work first. \|" (the twin of R:38) |
| →C | G:657 | "`cc-backlog add --why-not-now "needs-human: …"` and `cc-decide open --class C` both REFUSE without `--conviction N --receipt …`" (the twin of R:68) |
| STOP | G:667-668 | "STOP-ASK only for a genuine fork/escalation" |
| STOP | G:714 | "\| ⛔ **Blocked** \| needs a **decision** (destructive migration / auth / nav / timeout) or **info** \| `⛔ Blocked — need your call: <decision>.` \|" |
| →C | G:721 | E0 row: "What it **cannot** drive it FILES — `cc-decide open` … so the rung is `⛔`" |
| **STOP** | **G:766-767** | "**Only ⛔, and 📦 in a repo whose OWN `CLAUDE.md` says landing spends money, may end a turn holding work.** Everything else the agent drives:" (the twin of R:103) |
| DRIVE | G:791-793 | "**never idle waiting on the user because you are low**" |
| **→C** | **G:1000-1002** | "**Corollary — a decision you are holding IS the rung, and filing it is what makes it one.** Open it … (`cc-decide open --class C …` — and a class-B packet, the unattended ask whose default fires at its deadline, carries the same `--conviction N --receipt R` …); `wrap-ledger.sh` then computes `⛔` from your own session's open class-C packets and **it outranks everything**." |
| STOP | G:1004-1006 | "(`⛔` is also the *safest* rung measured, at 27.4% failure against `✅`'s 37.2% …)": a measured argument in favor of ⛔ closes |
| **STOP** | **G:1042** | BLOCKED row: "a genuine operator-only gate — credential · sudo · destructive migration · a real value fork … 'the one decision you need' describes **the ordinary mid-work `⛔`**, not the exhaustion close". This names the mid-work ⛔ as a normal, sanctioned state |
| STOP | G:1122 | ledger template `→ Next: <ONE verb: continue · commit · run-gate · STOP-ASK · /handoff …>` |
| **STOP** | **G:1126-1128** | "**Clear it** … the instant the state becomes ✅ / 📦 / ⛔ / 📤 … — **those MUST stop.**" (stronger than R:217) |

### 2d. Tool text the rules defer to (class semantics)

| Where | Verbatim | Note |
|---|---|---|
| `bin/cc-decide:13-19` | "A AUTO-DECIDE + audit trail — the agent already ruled + ACTED … B QUEUE-FOR-REVIEW — a value-fork/external-info the values don't settle, AFTER route-around failed: carries a default_if_no_veto + veto_deadline; the default FIRES at the deadline … C HARD-BLOCK (human-only) — C10 self-mod / C6 money-path / permission denial: WAITS, has NO default" | **The class definitions contradict R:160.** Class B is defined as exactly the value fork that R:189 calls BLOCKED |
| `bin/cc-decide:103-104` | "A class-C packet is the ⛔ rung: it ends a session's turn holding work and hands the operator a question." | The tool's own comment restates the license |
| `bin/cc-decide:195-200` | B needs `--default` and `--deadline`, and C must not carry `--default` | Mechanical |
| `scripts/gate-classify.sh:2-9` | "route a STOP-ASK boundary to EXACTLY ONE decision class … B QUEUE-REVIEW DEFAULT … C HARD-BLOCK a C10/authority-ceiling surface" | **The router exists and defaults to B, but no always-loaded rule names it.** `git grep gate-classify` finds it only in `commands/limit-recover.md:550,585` |
| `scripts/gate-classify.sh:33` | `C_SURFACE='…\|permission\|…\|purchase\|…\|token\|…\|login\|…\|hooks?…'` | Over-inclusive by design (`:12-15`). The text of a Codex-review question ("plan we paid for", "token") could route to C. That needs checking before any rule tells sessions to run it |

---

## 3. Gaps against the ruling's goals (rule text only)

| Goal | What the rule text says today | Edit point |
|---|---|---|
| (a) keep working on ungated in-scope items | Nothing scopes a decision to the items it gates. R:38/G:605 override auto-continue for the session. R:103/G:766 let ⛔ end a turn unconditionally. R:217/G:1127 say to disarm the continuation on ⛔. G:1042 sanctions the "ordinary mid-work ⛔". Only the exhaustion close (R:189/G:1042) and S:203 ("what remains") carry the right idea | R:38, R:103, R:189, R:217 and their G twins (G:605, G:766, G:1042, G:1127) |
| (b) judgment calls → B, C only for cc-decide's reserved set | R:160/G:1001 hard-code `--class C`. R:68/G:657 name only C. R:193 and R:99 are unclassed. No rule cites `cc-decide:13-19` or `gate-classify.sh` | R:160, R:68 and their G twins (G:1001, G:657); optionally R:99 |
| (c) find an existing ruling before asking | The search-first rule exists only for memory writes (S:47). F2 (R:68/G:657) requires research but not a precedent search. No rule says an answered packet or purchase counts as a ruling. `cc-memory-search` already searches "every `type: feedback` topic in EVERY store" by default (`~/.claude/bin/cc-memory-search` docstring), and the agentsync grant file is `type: feedback` (`~/.claude/projects/-Users-chrisren-Development-agent-context-sync/memory/cross-vendor-review-standing-grant.md:6`). So a cross-project search would now find it | R:68 (append) and G:657 |
| (d) standing operator grants every session loads | None exist: `grep -i 'codex\|cross-vendor\|openai\|chatgpt'` over S and R returns nothing (measured). The only standing grants in any loaded file are project-scoped (`.claude/CLAUDE.md:18-37` Standing-land, `:39-83` Standing-converge) and the parallelize directive (S:81) | See §6 |
| (e) refuse a Blocked idle while ungated in-scope work remains, including a loop scope | R:26 freezes scope as one line, and R:86 says "an open plan item is open work", but nothing says a `loop until`/`repeat until` scope stays open until its stop condition is recorded | R:86 (close-question paragraph) or R:26, plus the hook/ledger slots |
| (f) wake the stalled session itself | Rule text has no wake duty. S:100 names `mailbox-wake-arm`. S:166 idle-recycle is the only rule an idle lead self-applies | Hook slot. Rule text only needs to stop licensing the idle |

---

## 4. Parity: what keeps slim and full in sync

1. **No automated content-parity check exists between `S`+`R` and `G`.** The slim header records `derived-from CLAUDE.global.md sha256:cecd5a0c2fa35792` (`S:1`). The only consumer is `cc-instructions-variant status` (`bin/cc-instructions-variant:143-160`), which prints STALE and changes nothing. Measured: `shasum -a 256 CLAUDE.global.md` gives `73bc55b340402a66…`, so the stamp is already stale. The slim also carries slim-only text (S:27). Parity is a convention.
2. **Per-rule content pins in both variants** are the working pattern, and the template for any new rule:
   - `tests/close-research-pending-rules.bats:11-43` greps the E0 row in `G` and the E0 bullet in `R`, and asserts the same clauses in each.
   - `tests/research-program-exemption-rules.bats:15-16` concatenates `CLAUDE.global.slim.md` with `CLAUDE.rules.slim.*.md` (a glob, so a new rules file joins automatically). Then `:24-40` asserts the pointer in each variant's paragraph, `:42-58` checks the definition, and `:60-74` runs the cited command against a planted registry.
3. **Byte parity between live and repo** (deploy, not content):
   - `scripts/deploy-parity-assert.sh:1350-1372` globs `CLAUDE.rules.<v>.*.md` and reports `CLAUDEMD` drift on an absent or diverged copy (`tests/deploy-parity.bats:1067-1080`).
   - `CLAUDE.rules.*.md` and `CLAUDE.global.*.md` are `want=0` in the per-file leg (`deploy-parity-assert.sh:914-926`), because they are renamed copies.
   - `wrap-ledger.sh:2124-2140` delegates its "is this add deployed?" test to that table. So a new root rules file should not produce a permanent 🚀 (inferred from code, not run).
4. **Test selection at land.**
   - `scripts/gate-select.sh:250-256` treats `CLAUDE.global.md` as prose. Measured: `gate-select.sh --explain 01ba2fcf6^..01ba2fcf6` selected 18 suites via `prose-literal:CLAUDE.global.md`, and `close-research-pending-rules.bats` via `literal:CLAUDE.rules.slim.10-session-close.md`. Overall verdict FULL, because of other files in that commit.
   - A new rule's pin test is picked up when it names the file literally.

---

## 5. Cross-layer hazards found while mapping

1. **"need your call:" is the prescribed ⛔ readout.** R:92, R:144 and G:714 prescribe `⛔ Blocked — need your call: <decision>.`, and `scripts/wrap-ledger.sh:2607,2609,2722,2724` renders it. Adding `need your call:` to `hooks/anti-deference-nudge.sh` `TELLS` (`:170`) would fire on every legitimate ⛔ close. The incident report's own phrase list (`until you answer|nothing (more )?runs until|no round [0-9]+ (starts )?until`) avoids it. Any rewording of R:92 changes what that hook and `operator-readout.sh:1548` match.
2. **The rules tell the lead to disarm its own continuation on ⛔**: R:217 and G:1127 ("those MUST stop"). Any hook change that keeps a ⛔ session working must change this text in step, or the rule and hook fight. The model sees "clear it on ⛔"; the hook re-arms it.
3. **The tool comment `bin/cc-decide:103`** ("A class-C packet is the ⛔ rung: it ends a session's turn holding work") will contradict any new rule text unless it is edited too.
4. **gate-classify over-inclusion** (`scripts/gate-classify.sh:33`). If the new rule says "classify with gate-classify", a Codex-review question can match `purchase|token|login|permission` and come back C. Measure it on the B13 `--what` texts (transcript lines 4254, 4260) before citing the tool in a rule.
5. **The grant's scope differs between stores.** The agentsync memory grants "ChatGPT Codex plan (and Gemini/Antigravity)" (`cross-vendor-review-standing-grant.md:3`). Ruling d610f8473106's goal (d) names only the Codex plan, git-archive exports, and the 80% weekly-meter stop. The packet's evidence quotes the operator's yes, but not the envelope (`~/.claude/autonomy/decisions/d610f8473106.json`). The always-loaded text must pick one scope.

---

## 6. Instruction budget

**Config** (`config/instruction-budget.json`):
- `per_file` 40,000; tiers `user` 60,000, `ancestor` 0, `repo` 60,000; `session` 120,000; `enforce: true`.
- Units are "loader chars: UTF-16 code units after YAML frontmatter and column-0 HTML comment blocks are stripped" (`_what`). A provenance comment at column 0 therefore costs nothing.
- `deploy_sources` maps only `CLAUDE.global.slim.md` and `CLAUDE.rules.slim.10-session-close.md`.
- `destinations.user`: "the slim global and its rules are **one-in-one-out**".

**Measured** (`python3 -I hooks/lib/instruction_budget.py measure …`; `cc-instruction-budget measure` is the same lib):

| File | Bytes (`wc -c`) | Loader chars | Per-file headroom to 40,000 |
|---|---|---|---|
| `S` | 29,000 | 28,503 | **11,497** |
| `R` | 30,958 | 30,287 | **9,713** |
| `~/.claude/rules/00-mission-board.md` | — | 2,284 | — |
| `G` (not loaded) | 118,348 | 116,486 | n/a: classify returns `[]` |

**User tier.** Measured with `instruction_budget.py assert --class user --days 1`:
`BREACH [user] [.claude,.claude-next,.claude-quaternary,.claude-tertiary,.claude-secondary] user tier 61,074 > 60,000`.
- That is 28,503 + 30,287 + 2,284 = 61,074, **already 1,074 over before any edit**.
- The hourly auditor (`scripts/autonomy-sweep.sh:685-708`) logged `instruction_budget_rc:"1"` at 2026-10-24T20:20:53Z (idl.jsonl).
- The original user-tier row `473335c307b2` was closed `done` on 2026-10-04 at 59,515. The tier has since grown through the mission board and slim edits.

**What the land gate actually enforces** (`scripts/ship-land.sh:4086-4120`):
- The arm fires when the land's diff touches `:(glob)**/CLAUDE*.md` or `**/.claude/rules/**`. It runs the selftest, then `cc-instruction-budget range <range>`.
- `range_findings` classifies with `cfgdirs=[]` (`hooks/lib/instruction_budget.py:839-878`). A repo file named in `deploy_sources` classifies as tier `source` (`:474-480`), and `judge` skips any tier not in `tiers` (`:647-651`). **So at land only the 40k per-file cap applies to `S` and `R`; the 60k user-tier total is not checked.**
- Measured by in-memory simulation of `judge(..., cfgdirs=[])`:
  - `S` +2,000 chars → no finding; `S` +12,000 → `file 40,503 > 40,000`.
  - `R` +2,000 → no finding; `R` +10,000 → `file 40,287 > 40,000`.
- **A brand-new `CLAUDE.rules.slim.<name>.md` classifies to `[]`** (measured: `classify(CLAUDE.rules.slim.20-standing-grants.md)` returns `[]`), because it is not in `deploy_sources` and is not a `CLAUDE.md`/`.claude/rules/` path (`owning_dir`, `:440-453`; `RULES_SEG = "/.claude/rules/"`, `:68`). It is unbudgeted at land until someone adds it to `deploy_sources`.

**Other gates:**
- The Write/Edit gate (`hooks/backup-before-write.sh:150-172`) uses the same predicate, with the same `source` classification for the repo files.
- `scripts/rules-hook-budget-lint.sh` (`ship-land.sh:3870-3912`) arms only on `.claude/rules/*.md`, the repo-local lessons files. It never sees `S` or `R`.

**Re-gate debt.** `docs/plans/INSTRUCTION_BUDGET.md` (Known issues, starting at :116; the line itself is :127) records: "2026-10-04: the operator ruled to defer the run until the next slim edit". That run is the held-out F1 re-gate, about $403 list, about 37-58 weekly pp, and it needs the operator's go-ahead. Measured: `git log --since=2026-10-04 -- CLAUDE.global.slim.md CLAUDE.rules.slim.10-session-close.md` shows 10 slim edits since then with no re-gate, so the deferral has not acted as a gate in practice. A rules change of this weight is the kind of edit the deferral named. Flag it, don't decide it.

---

## 7. Where a "standing operator grants" section could live

| Option | Deploy plumbing | Budget cost | Reaches | Risks |
|---|---|---|---|---|
| **A. New `## Standing operator grants (All Projects)` section in `S`**, after Frontier Tier Routing (S:130-145), with the same text in `G` | None new: the existing copy leg (`install.sh:1132-1139`), live at the next converge | Draws on S's 11,497-char per-file headroom (measured). Widens the existing user-tier breach (61,074 → ~62k+ for a ~900-char section, estimated from the report's draft length). The land ratchet does not refuse it, but the hourly auditor keeps reporting, and the config's one-in-one-out policy asks for an equal cut elsewhere in S or R | Every session on all 5 accounts | Mixes a growing ledger of grants into the global prose. Each new grant is a slim edit (re-gate debt above). Needs a pin bats test over both `S` and `G` (pattern: `tests/research-program-exemption-rules.bats`) |
| **B. New rules file `CLAUDE.rules.slim.20-standing-grants.md` → `~/.claude/rules/20-standing-grants.md`** | **Deploys automatically**: the install.sh glob (`:1119-1127`) copies it, adds it to `_instr_rules`, and the sweep keeps it (`:1150`). `~/.claude-*/rules` symlink to `~/.claude/rules` (measured), so all accounts get it. Parity coverage is automatic (`deploy-parity-assert.sh:1357` glob), and the research-program-exemption pin's concat (`:16`) includes it. **But under `global full` it is not deployed and an existing copy is retired** (`install.sh:1117`; `tests/install-instructions-variant.bats:80-89`), so `G` must carry the same text | Its own 40k per-file budget, so S's headroom is untouched. Same user-tier growth as A. **Unbudgeted at land unless `config/instruction-budget.json` `deploy_sources` gains `"CLAUDE.rules.slim.20-standing-grants.md": "~/.claude/rules/20-standing-grants.md"`** (measured `classify` → `[]`) | Every session, all accounts | A file-name number orders the load after `10-session-close.md` (inferred: the loader reads `rules/` in directory order, not verified). It is a clean home for a list that will grow, and a grant edit stops being a close-protocol edit |
| **C. Data file (for example `config/standing-grants.json`, or a store under `~/.claude/autonomy/`) read by an already-registered hook or CLI** | No settings change if folded into existing code: a child of `hooks/session-start-dispatch.sh` (it merges 9 children into one `additionalContext`; the per-hook context cap is 10,000 chars, `session-start-dispatch.sh:11-13`), or `memory-nudge.sh` (UserPromptSubmit), or **`bin/cc-decide open` printing or refusing on a matching grant**, which is the point where an ask is made (not a hook, no registration) | Zero instruction budget. Context cost only when injected | SessionStart injection reaches every session that runs hooks. The `cc-decide` check reaches exactly the sessions about to ask | Injected context is not instructions. A hook bug fails silently (the "absent feature is a no-op" pattern, `G:737-746`). Not visible to `workflow-lean` slots (same as A and B) |
| D. `G` only | install.sh:1080-1087 | 0 | **Nobody**: CLAUDE.full.md is "not loaded by any session" (`install.sh:1083`) | Rejected as the sole home |
| E. Project memory | — | 0 | One project's sessions, plus `cc-memory-search`'s default cross-store `type: feedback` scope (§3(c)) | This is where the grant lives today (agentsync only). The incident proved it is not "where every session loads them" |

**Reading the costs together (my synthesis, not a recommendation the brief asked for):**
- B plus a `G` twin plus one `deploy_sources` line is the only always-loaded placement that costs S nothing and adds no deploy code.
- A is the smallest diff but spends scarce headroom.
- C is the only placement that can also enforce goal (c) at the moment of asking, and it can sit beside A or B.
- Any always-loaded choice grows a user tier that is already over budget (measured 61,074 > 60,000).

---

## 8. Sentences that would have to change, by goal

These are rule-text edit points only; wording is for the design synthesis.

- (a) **R:38** (+ G:605): scope the stop to the items the decision gates.
- (a) **R:103** (+ G:766): add "⛔ ends a turn only when every remaining in-scope item waits on an open decision".
- (a) **R:189** (+ G:1042): narrow "a real value fork", and stop calling the mid-work ⛔ "ordinary".
- (a) **R:217** (+ G:1126-1128): keep the continuation armed on ⛔ while ungated work remains.
- (a) `bin/cc-decide:103` comment: match the new rule.
- (b) **R:160** (+ G:1000-1002): a judgment call with a status-quo course goes to class B with `--default` (the frozen-scope course) and `--deadline`; class C only for `cc-decide:15-19`'s set.
- (b) **R:68** (+ G:657): name class B beside class C.
- (b) R:193 and R:99: no change needed if R:160 carries the class choice.
- (c) **R:68** (+ G:657): before handing a call over, run `cc-memory-search` and `cc-decide list --all --json`. An answered packet or a purchase made for the same purpose is a ruling: act on it and file class A.
- (d) §7.
- (e) **R:86** or **R:26** (+ G:592-595 / the close-question text): a `loop until` / `repeat until` scope is open work until its stop condition is recorded.
- Pins: one new bats test in the shape of `tests/close-research-pending-rules.bats`, asserting each new clause in both `R` (or `S`) and `G`. Cite `CLAUDE.rules.slim.10-session-close.md` literally so `gate-select.sh` selects it.
