# REPORT: "research done, implementation pending" as a close status

**Verdict.**
1. **What is wrong.** The close read `✅ … nothing to do` because every ledger input that can say "not done" keys on a record *this session filed* (`scripts/wrap-ledger.sh:1500`). The research re-checked 74 packets that other sessions own and wrote its report to `/tmp`. So the ledger fell to its default (`:2492`), and the close-shape template supplied the "yes" sentence (`hooks/lib/close-shape.sh:179`).
2. **The fix is a declaration, not a detector.** A new `cc-decide recheck` verb lets the research turn stamp each packet it leaves pending. The ledger reads those stamps as `⛔ Blocked — research done, implementation pending: N decision(s) need your call`, but only for the turn that made them and only once the agent's own work is clean. Line 1 of the close becomes `❌ Good to close: no — research done, implementation pending: …`.
3. **Implement now:** nine critic-revised items (A1–A4, A7–A10, A12), in one dispatched session. Every one is above 90% and is reversible.
4. **Needs you:** six rulings (B1–B6). The first is how a reversible change at 62–88% conviction proceeds without a sign-off.
5. **Dropped after critique:** the prose backstop arm (D8) and the template edit (A6). The two HIGH defects the critics measured are fixed and re-measured:
   - Sticky ⛔ convicting Q&A turns: 16 → 72 convictions in the critic's replay.
   - A1 releasing a "yes" over ⛔.

**What changed from DESIGN.md** (each item is traced in §8):
- The re-check ⛔ is **turn-scoped** and ranks **on the ✅-eligible path**, below every agent-drivable floor.
- Its wording now uses the documented `⛔ Blocked — …` state clause.
- A1 uses the critic's refined, measured predicate.
- `recheck` gains `--tier` and a durable-receipt check.
- D8 goes to the sibling study's C3 lane.
- A6 is dropped.
- A11 is folded into A7.
- A8 keeps E0 as a superset of today's rule.
- A12 is new.
- B1 absorbs the class-B route.

Line numbers are from worktree `close-status-research` at `36afca47f`. Trunk `580eada96` is 2 commits ahead and touches only `tests/lr-recon-watchdog.bats` among the cited files (`git diff --stat HEAD origin/main -- <cited files>`). Scratch for this report: `/tmp/rpic-REPORT/`.

---

## 1. Root cause (file:line)

| # | Cause | Evidence |
|---|---|---|
| R1 | **No ledger input for "research produced pending actions".** `RUNG="✅"; READOUT="✅ Complete & live on trunk — nothing to do."` (`wrap-ledger.sh:2492`) survives whenever no arm fires. Every arm that could fire is session-filed: ⛔ `$mine` = `.session_sid == $sid` (`:1500`); FILED_MINE, UNCONVICTED and YOURS (`:1298-1327`, `:1396-1450`) are the same. | 0 of 74 packets carry sid `74728043`. 0 `cc-decide`/`cc-backlog` writes before the close (slot A §3, slot E §2). Sandbox with 5 foreign open class-C packets ⇒ `RUNG=✅ BLOCKED=0` (slot A §4 S1–S2). |
| R2 | **The research never reached a store.** The report was at `/tmp/xd/REPORT.md`. `commands/explain-decisions.md` has no disposition step, and cc-decide has no verb to record a re-check: a packet keeps only its opener's sid. | slot D §3.5; slot E §2 (packet key list) |
| R3 | **The hooks wrote both lines of the false close.** Line 1 = the template's only finished sentence, `yes — nothing of mine is open; follow-on: <…\|none>` (`close-shape.sh:179`). Line 2 = D6's order to "relay READOUT's glyph and state clause verbatim" (`close-shape.sh:309`). D6 was armed by `/tmp` scratch writes: `session_writes_paths` counts any path, subagents included (`completion-assert.sh:1513`; `session-writes.sh:236-239`). | D6 blocked twice, 02:32:26Z and 02:32:43Z (shape 1/2, 2/2). The agent then used the yes branch word for word (slot B §1, §3). |
| R4 | **Vacuous scope.** `DOD=present` is set when the DoD file exists (`:905`), and REMAINDER=0 ⇒ `SCOPE=met` (`:938-940`). The repo-key DoD kept 16 inherited blocks with 0 checkboxes. | slot A §3. Estimate: 74 of 78 DoD files show zero boxes in that view. |
| R5 | **Nothing checked the claim.** completion-assert timed out on the final Stop (5,337 ms > 5,000). operator-readout led with the machine-wide pile and `✅ live on trunk` (`operator-readout.sh:1355`), and **it has no ⛔ arm** (`case "$RUNG"` at `:1236` handles 📦 🚀 🔧 ✅). | slot B §1; slot C §2, §5 B: a session-owned ⛔ renders `OPERATOR ▸ 4 need your call` and the ⛔ is lost |
| R6 | **The protocol has no report state for this.** slim:34 files research under "no ledger, no readout". E0 (slim:99) says "drive", not what to report. BLOCKED (slim:189) promises a ⛔ the ledger cannot compute for re-checked packets. | slot D §3 |
| R7 | **The downstream recycle inherits the blind spot.** FREE WIN asserts "no operator step outstanding" from ✅ alone (`boundary-handoff.sh:847`). It recycled the predecessor `f06b5e9b` "with nothing to do" over 35 + 70 unexecuted disk-cleanup items. | slot E §4 |

## 2. Detection signal and its measured precision and recall

**Candidate heuristics, measured.** Labels came from one labeller per slot, with no second rater. Small n.

| Signal | Source / denominator | Result |
|---|---|---|
| s1 packets opened this turn | F, n=91 stratified (40 fired-SRS, 35 unfired-SRS, 15 oversample, the incident) | strict P 0.23 R 0.14. The incident did **not** fire it. |
| s2 packet store read | F | P 0.23 R 0.14. It fires on every check-in that re-lists decisions. |
| s3 writes outside git | F | P 0.17 R 0.27. 83% of its fires are briefs, scripts and commit messages. |
| s4 research fan-out, no commit | F | P 0.62 [Wilson 0.36, 0.82] R 0.36. The no-commit clause drops research that commits its report. |
| s6 ∨ s7 (`/explain-decisions` ∨ research-only fan-out) | F | strict P 0.59 R 0.59; lenient P 0.77 R 0.63. s6 alone: lenient P 6/6 [0.61, 1.00]. |
| p1 research-intent prompt regex | G census: 1,877 turns, 347 origin-interactive sessions, 14 days | R 1/15. 67 of its 90 fires match only a `/research` path. |
| p2s close text ("recommend/%/conviction" ∧ "nothing of mine is open / read-only / follow-on: none / nothing to do") | G, n=90 stratified | vs harm labels: P 4/12, R 4/4. Fires on 47 of 1,877 turns (2.5%). |
| D8 (DESIGN's backstop: a done-reading close that cites an open foreign class-C id with a recommendation) | DESIGN replay over G's census | 3 of 1,877 fires (0.16%). Hand precision 2/3 (Wilson [0.21, 0.94]); FP `d6ae5d72`, a recap of a standing packet. 0 of 57 status prompts fired, but that has no power: the expected count was 0.09, and the rule-of-three bound is 5.3% (critique-alarm §5). |
| Sibling's D8 v2 (C3, the same arm family) | sibling `round2/C3-*` on branch `cc-004752-67086` | Three adversarial judges scored it 30, 25 and 30 (designer: 40). Held-out precision 20% for the incident class and 32% under the contract. About a third to a half of target Stops time out before the arm runs. |

**FP summary.**
- s1 and s2 fire on status and dispatch turns, and on MIX turns that already led with ⛔ (27 of 40 s1 finals).
- s3 fires on teammate helper scripts, handoff briefs and eval workers.
- s4 and s7 fire on non-research Workflow use (smoke tests, film render, implementation lanes).
- p1 fires on recycled successor briefs that cite `docs/research/`.
- p2s and p4 fire on recaps of items that predate the turn.
- D8 fires on a ✅ recap of a standing packet.
- Detail: slot F §4, slot G §5.

**Choice: the rung-setting signal is a session-declared store fact.**
- **Declared:** an open class-C packet this session filed (existing), or an open packet whose **latest** `rechecks[]` entry carries this session's sid, a conviction and a receipt, with a `ts` **after this session's last genuine human prompt** (new; A3/A4).
- **Precision is 1.0 by construction:** a stamp is the producer declaring the state. Recall is whatever producers declare. That is why A9 builds the stamp into `/explain-decisions`, the main producer (s6 lenient P 6/6), and A8 builds it into the protocol.
- **No prose heuristic renders a status.** Every one measured has precision ≤0.33 on the harm population, and the sibling's §6 and exhaustive-drive 2D reject lexicon arms at 85–90.

**Exposure under turn scope (measured this report, `/tmp/rpic-REPORT/`):**
- **Boundary detector on the incident transcript** (849 records, `lasthuman.jq`, 0.03 s):
  - At the T1 close cut (`head -465`): `2026-10-19T02:15:42.541Z`, the `/explain-decisions` prompt. Stamps made at about 02:36 count.
  - After the operator's replies (`head -560`): `02:47:35.032Z`. Stamps fall out of scope.
  - Task-notification hand-backs (02:21–02:36Z) and Stop-hook feedback are **not** boundaries, so a block cannot push a stamp out of scope.
- **The `origin` field is not universal.** In a sample of 200 of the 1,544 transcripts from the last 14 days, 836 of 1,213 main-chain user records carry `origin` (69%), and 92 of the 200 files carry none. A fallback filter on the machine-envelope prefix (`completion-assert.sh:314-322`, widened to `Another Claude session sent a message`, `Stop hook feedback`, `<bash-…>`, `[Request interrupted`, `<agent-message`) is therefore required (`originprobe.py`).
- **Upper bound on turns that can read the re-check ⛔.** Only turns that stamp can. Under A9 that is at most the 74 `/explain-decisions` turns in G's census, 3.9% of 1,877, in 48 sessions. The critic's sticky replay had 380 turns reading ⛔.
  - Of the 57 status prompts, at most 1 (a status prompt that itself invoked `/explain-decisions`).
  - Today 196 turns read ⛔, all from filed packets, and that is unchanged.
- **⛔ term on those stamping turns, under refined A1** (`pol2.sh` over the 74 finals):
  - 20 already lead with an honest no or with ⛔, so they abstain.
  - About 18 carry a CLOSE token and would be asked **once** to lead with the answer.
  - 36 carry no CLOSE token.
  - This is an approximation: the CA_SETTLED path through line 1 was not replayed.
  - The critic's sticky replay had 72 convictions.

**What stays invisible, stated plainly.**
- Research that ends in unfiled prose rulings with no packet id (e.g. `99b5cd2f` 10-07, "needs 4 rulings … follow-on: none"; slot F estimates 66–77% of positives look like this).
- Research done by a peer and only referenced (`6defb493`, "five decisions in the report").
- Covered only by A8's rule text, A9's command, and A2's honest READOUT wording. No detector covers them.

## 3. The new state

**Glyph and order.** ⛔. It is a sentence variant of the existing top rung, not a new glyph. There are 11 RUNG-comparison sites outside the ledger, an empty-state trap at `operator-readout.sh:1245-1249`, and a 2026-10-01 ruling against a scope glyph at `wrap-ledger.sh:2629`. The ladder becomes:

```
⛔ filed-by-me (unchanged, first) > 🔧 dirty > 🔧 remainder > 📦 unlanded
  > [✅-eligible] 🔧 custody > 🔧 resident > 🔧 filed > 🔧 unconvicted > 🔧 floor > 🔧 no-trunk > 🚀
  > ⛔ research (NEW, turn-scoped) > 👤 > ✅ variants > ✅
```

- **Why the re-check ⛔ ranks on the ✅-eligible path** (critique-contract §3).
  - At ⛔ the ✅-eligible branch never runs, so custody, resident, FILED_MINE and UNCONVICTED keep their skip/0 defaults (`:1577`, `:1660`, `:1395`).
  - session-continue's floors also go silent at ⛔ (`:1103`, `:1217`).
  - A store write must not mask agent-drivable work. A filed-by-me ⛔ still outranks everything (`:2500-2511`).
- **Why ⛔, not 👤:** a sign-off is a decision, and the protocol files decisions through cc-decide as ⛔ (slim:160, :189). 👤 is for operator *steps* (Three dispositions).
- **Why turn-scoped** (critique-alarm §1, §3, §10). Open class-C packets are p50 18.4 days old. A session-scoped stamp would read ⛔ for weeks, and the existing ⛔ term would convict every later Q&A answer. Measured: q1–q4 fire both before and after A1 under a ⛔ ledger (`blk.out`). After the next human prompt the rung returns to the git state, and the session's still-open asks stay named in the readout by A7's `◆ [this session]` lines.

**Exact close lines** (prescribed by A8/A9; measured in the sandbox, `/tmp/rpic-REPORT/blk.out`):

| Line | Text | Source |
|---|---|---|
| 1 (S2 verdict) | `❌ Good to close: no — research done, implementation pending: <N> decision(s) wait on your sign-off — first, <decision in plain English>, <conviction>%.` | the model, per A8/A9 |
| 2 (S1 rung), N>1 | `⛔ Blocked — research done, implementation pending: <N> decision(s) need your call: cc-decide list --open` | wrap-ledger READOUT (A3) |
| 2 (S1 rung), N=1 | `⛔ Blocked — research done, implementation pending; need your call: <what_plain>.` | same |
| 2, filed by this session | unchanged, byte for byte: `⛔ Blocked — need your call: …` / `⛔ Blocked — N decision(s) need your call: cc-decide list --open` | `wrap-ledger.sh:2505-2511` |
| 3 (S6 waiting) | `Reply approve or veto for each; on approval this pane recycles into implementation.` | the model. It is not an `ACT:` line: `ACT:` is legal only for GUI/physical acts (`close-shape.sh:223-225`), and S3 is literally `▶ Run this:`. |
| readout line 1 | `OPERATOR ▸ ⛔ Blocked — research done, implementation pending: 56 decision(s) need your call` (91 columns), then up to 5 `◆ [this session · <tier>] <what> — <rec> <conv>%   cc-decide show <id>` lines, then `↳ +K more this session (S sign-off, L low-stakes): cc-decide list --open`. The pile excludes them. | A7 |

The S1 rule "copy the glyph and state clause verbatim; under ⛔ keep the tail" (slim:144) applies unchanged, because the state clause is the documented `Blocked` (slim:92). No rule text documents a new shape.

**Sandbox results** (`blk.sh`; seams from `tests/completion-assert.bats`; ORIG = today's hook, A1r = refined A1; ledger stub `RUNG=⛔ BLOCKED_RECHECKED=3`):

| Case | Close (lines 1–3) | ORIG | A1r | anti-deference |
|---|---|---|---|---|
| r1 | line 1 + line 2 + line 3 above | fired `false-done:ledger` | **abstained** `blocked-answered` | no-tell |
| r2 | line 2 + line 3 (led by the rung) | fired | **abstained** | no-tell |
| r3 | line 1 + A2's ✅ READOUT, under a ✅ ledger (the undeclared case) | abstained | abstained | no-tell |
| h1 | `✅ Good to close: yes — nothing of mine is open; follow-on: none` / ⛔ line | fired | **fired** | no-tell |
| h2 | `✅ All done and landed …` / `❌ Good to close: no …` | fired | **fired** | done-ledger-clean |
| h3 | `Everything is done and landed.` / `⛔ Blocked …` | fired | **fired** | done-ledger-clean |
| c0 | yes line alone | fired | fired | no-tell |
| q1–q4 | Q&A answers carrying a CLOSE token | fired | fired | no-tell |

The q1–q4 rows are why the re-check ⛔ must be turn-scoped: no polarity predicate separates a Q&A answer from a done-claim.

**Interactions.**

| Surface | Behaviour | Edit |
|---|---|---|
| ✅ SAFE TO CLOSE (both surfaces) | Withheld by any non-✅ rung: the header lives inside the `"✅")` arm (`operator-readout.sh:1338-1355`), and the standalone certificate abstains unless `RUNG=✅` (`:2113`). | none |
| D6 origin contract | Gated on RUNG ∈ {✅, 👤} (`completion-assert.sh:1501-1502`), so it is off on the stamping turn. On an undeclared research turn (✅, armed by scratch writes) it is unchanged. A2 makes the relayed line honest ("nothing this session filed is open"). | A2 |
| D3 hedge / D4 offer / anti-deference | r1–r3 above: no CA_SETTLED before the anchor, no CA_OFFER, no TELLS. Avoid these measured traps: `awaiting your`, `Want me to`, `N decisions need your sign-off.` (CATEGORY_TELLS), `requires your` (D1), `need your approval` (exits via GENUINE) (slot B §5). | pinned in A1 tests |
| ⛔ term (`completion-assert.sh:1204-1208`) | **Today it convicts the correct close.** The CLOSE gate matches `done` anywhere (`:428`, `:467-470`), so "Research done" alone reaches the term. A1 fixes this. Turn scope bounds the re-check variant to stamping turns. | A1 |
| Research-program exemption | `recheck` refuses inside an active program, so the arm can never fire there. The E0 program sentence is kept (pinned at `tests/research-program-exemption-rules.bats:28,36`). | A4, A8 |
| boundary-handoff FREE WIN | Requires `RUNG=✅` (`:547`), so it is suppressed on the stamping turn only. The wording stops claiming more than it checked. | A10 |
| session-continue | Its header contract already says clear on ⛔ (`:13-14`). Its floors still fire, because the re-check ⛔ ranks below 🔧, 📦 and 🚀. | none |
| `--recycle` successor brief | `handoff-fire.sh:16822-16824` says "A rung other than ✅ is … now YOURS: collect it". A research ⛔ is the operator's, so the brief says so. | A12 |

## 4. Auto-proceed rule, built from existing gates

For each implementation item X that research produces, checked in this order. Sign-off is checked first and can never be demoted (`scripts/gate-classify.sh:9-14` asymmetry).

```
SIGN-OFF (class C ⇒ ⛔) if ANY of the sign-off classes holds:
  escalation surface (G2): auth/session · destructive migration · navigation pattern · DB timeout
                     (CLAUDE.global.md:612; plus the repo's escalation greps, e.g. reso-management-app/CLAUDE.md:543-546)
  money · credentials or permissions · self-modification  (bin/cc-decide:17-19; gate-classify.sh:34)
  irreversible · production-mutating · classifier/permission-refused   (skills/manual-command-delivery/SKILL.md:26-27)
  third-party contact · publishing · purchase · public repo            (feedback-operator-will-not-read-signoffs.md)
DRIVE NOW iff none of the above AND F2 conviction > 90 (bin/cc-decide:210-214) AND F1, F4, G3, G4.
OTHERWISE (no sign-off class, conviction ≤ 90): stamp `--tier default` (or `nochange`) and route per ruling B1.
```

- **Carve-out for this repo's own source** (critique-contract §6). `gate-classify.sh "change hooks/completion-assert.sh …"` ⇒ `C ("change hook")`, while the cc-decide, wrap-ledger and command edits ⇒ `B`. In this repo hook and rule-text edits land under the project's standing-land authorization (`.claude/CLAUDE.md`, § Standing-land):
  - 85 hook commits landed on trunk in 14 days, 19 of them on the five files this design edits.
  - 5 slim-rule commits landed in 30 days, e.g. `445749840`.
  - C10 in gate-manifest is "self-modification/persistence, harness-enforced" (`scripts/gate-manifest.sh:15-17`). Here that is settings.json and migration application (e.g. `92f4c6f81`, "c10, unapplied"), which no item below touches.
  - Each item still states its own F2 number in §7.
- **Applied to the incident** (slot H, hand-coded and inferred, `/tmp/rpic-H/tiers.tsv`):
  - Drive now: 0 of 59 live decisions. The only one above 90 is `b4373234dd78` (92), an auth surface.
  - Reversible and at or below 90: 12 (convictions 62–88).
  - Recommendation changes nothing: 10.
  - Sign-off: 33.
  - 15 moot and 3 duplicates are hygiene, driven at >90. The operator expected it: "close them if you havent already" (slot E rec 548).
- **Caveats.**
  - Class-B actuation was measured idle for 27 h on 10-17/18 (sibling axis 05), so treat class B as "safe to queue", not "will happen".
  - Packets carry no reversibility field: only 1 of 59 has a `staged_artifact_path` (slot H). The `--tier` stamp is the filer's declaration, the same precedent as `default_effect` (`cc-decide:48-69`).

## 5. Sign-off → self-recycle path

**Exists now.** The incident used half of it on `bb7c893b31ba` (slot H §H2): the operator replied, a session was fired, it landed, and `cc-decide action` was run.
1. The research turn writes its report to a durable path (a repo's `docs/research/<slug>/` or `~/.claude/autonomy/research/<slug>/`, never `/tmp`), drives the >90 non-sign-off items, closes the settled ones, and stamps the rest (A9).
2. The operator replies approve or veto, in the pane.
3. In the reply turn the agent:
   - runs `cc-decide veto <id> --evidence "operator in-pane <ts>"` for each veto;
   - writes `/tmp/fire-impl-<slug>.txt` (locate line, report path, approved ids with their recommendations, DoD, gates);
   - as **the last act of the turn**, runs:
```
~/.claude/scripts/handoff-fire.sh --recycle --prompt-file /tmp/fire-impl-<slug>.txt \
    --goal '<approved items> landed on origin/main — proven by git ls-tree origin/main -- <paths> printed; do not touch unapproved items; DoD at <report path>'
```
   Add `--worktree <impl>` to relocate. For 2+ independent approved items, use one non-recycle fire per item (`commands/handoff.md:456-466`).
4. The successor implements, lands via `/ship`, and runs `cc-decide action <id> --evidence <sha>`.

**Preconditions** (slot H §H2 hazards):
- Pass `--goal` explicitly. A terminal or absent goal is not inherited (`handoff-fire.sh:9707-9724`), and the incident had 0 `goal_status` records.
- `cc-custody list --open --cwd .` must be empty, because a recycle kills in-process children.
- Do nothing after the fire (`:5289-5348`).
- The successor must not run a background `cc-await-ping` while its goal is live (`goal-inert-watch.sh:42-50`).
- The sid changes on recycle. The successor does not own the stamps, and the unapproved packets fall back to the standing pile. The turn scope means the reply turn already reads the git rung.

**New:**
- `recheck` (A4), the ledger's research ⛔ (A3), the readout ⛔ and its session lines (A7), the disposition step (A9), and the successor-brief sentence (A12).
- **Not built (ruling B4):** a sign-off given outside the pane. cc-decide has no "approved option X" verb (`action` means carried out), and no packet change wakes the filing pane.

## 6. Signoff-memory reconciliation

**Verdict: the request narrows the memory. Conviction 80%**, so it is a ruling (B2), not a blocker: the build is identical either way.

- **Scope.** `feedback-operator-will-not-read-signoffs.md` scopes itself to research **programs** ("never stop a research **program** to ask … 'read and sign'"). Its delegation is keyed on `programs.json` (one program, `truememory-2-0`). The incident cwd is not in a program: `research-program.sh is-active <cwd>` ⇒ rc 1.
- **Object.** The memory concerns *reading artifacts*. This checkpoint is one line per item: the decision as a sentence, a recommendation and a number. He gave exactly that twice without opening the 126 KB report (rec 492; rec 523, "Yes delete it").
- **Consistency.** The memory's own keep-with-him list (third parties, money, publishing, public repos) is a subset of §4's sign-off classes. The 10-18 "reversible … lower stake, just do it" restates `feedback-autonomous-to-100-boundary.md`.
- **Residual 20%.** He may have meant "zero human in loop" universally. Even then, only the handling of items at 90% or below with no sign-off class differs, and that is ruling B1.

## 7. Implementation split

**Execution locus.**
- **S** (default): one dispatched `/handoff` session runs all of §7(a). Inside it, Agent-Teams teammates own one file each, 5 teammates (cap 6):
  - ① `scripts/wrap-ledger.sh` (A2 → A3)
  - ② `hooks/completion-assert.sh` (A1)
  - ③ `bin/cc-decide` (A4)
  - ④ `hooks/operator-readout.sh` (A7)
  - ⑤ text: A8, A9, A10, A12
- **Waves:**
  - W1: A1, A2, A4, A10, A12, which share no file.
  - W2: A3 (after A2, same file), A7 (reads A3's field names and is fail-open without them).
  - W3: A8, A9, which name A4's verb and so land after it.
- **The orchestrating lead** keeps ≥50% of its window. Succession point: after W1 lands.
- **Gates for every item:**
  - `bats tests/<file>.bats`, asserting the `1..N` plan line (a cc-bats deferral is not a result).
  - Bare `shellcheck` as the land gate runs it.
  - Land via the project `/ship`, then converge with `CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh`.
- **Coordination.**
  - The sibling `22c1dbb7a` (branch `cc-004752-67086`, not on trunk) edits slim:22/146/156, `close-shape.sh:179` and `CLAUDE.global.md`. A8's hunks (slim:34/99/160/189; global:601/721) do not overlap it, so rebase whichever lands second.
  - No item edits `close-shape.sh`.

### (a) Implement now

Every item is additive or corrective. None touches auth/session, a destructive migration, a navigation pattern, a DB timeout, settings.json or a migration. Each "fails pre-fix" claim is either measured, or follows from the code: a missing verb, field or string.

**A1. The ⛔ term stops convicting a close that answers no.** *(W1. Conviction 93%. Receipt: `/tmp/rpic-REPORT/blk.out`; DESIGN §7 A1 live IDL count.)*
- **File:** `hooks/completion-assert.sh:1199-1208`, plus the D7 comment at `:1594-1595`.
- **Behaviour:**
  - Inside the term, call `_ca_source_close_shape` (defined `:991`, today called only at `:1529`/`:1611`). If the lib is unavailable, keep `contra=1`, so detection is the fail direction.
  - Skip iff `(close_verdict_polarity "$MSG" = no ∧ ¬close_line_reads_done "$ca_first") ∨ ("$ca_first" begins ⛔ ∧ polarity = none)`, and record `blocked-answered` in `_ca_exon`. **There is no line-2 disjunct.**
  - Facts: if `BLOCKED>0`, today's text. Else, from `BLOCKED_RECHECKED`: "BLOCKED ON YOU — N decision(s) you re-researched this turn are open (cc-decide list --open); that IS your rung; lead with `❌ Good to close: no — research done, implementation pending: …`".
  - Rewrite the refuted comment at `:1199-1203` and the D7 premise at `:1594-1595`.
- **Measured:**
  - IDL window 2026-10-18T12:18Z → 10-19T04:06Z: 23 ⛔ rows (11 fired, 12 capped).
  - Of the 6 fires whose only fact was "BLOCKED ON YOU", 4 landed on `❌ Good to close: no` closes.
- **Tests** (`tests/completion-assert.bats` after `:1250`, `mkledger` seam):
  - `⛔ HONEST NO: research-pending close (r1) ⇒ ABSTAIN …blocked-answered`. **Pre-fix: fired** (measured).
  - `⛔ RUNG-LED (r2) ⇒ ABSTAIN`. **Pre-fix: fired.**
  - FIRE controls `h1` (yes over a ⛔ line 2), `h2` (done line 1 over a no line 2), `h3`, `c0`. All fire before and after.
  - `⛔ facts for a re-check-only ledger name 're-researched this turn'` (`BLOCKED=0 BLOCKED_RECHECKED=3`, a yes close). Fails pre-fix on the string.
  - `CLOSE_SHAPE_LIB pointing to a missing file ⇒ an honest no over ⛔ still FIRES`.
  - The existing `:1155` case stays green.
  - `tests/anti-deference-nudge.bats`: `research-pending close lines 1-3 ⇒ no-tell` (measured), a pin against TELLS widening.

**A2. The ✅ default readout states what it checked.** *(W1. 96%. Receipt: slot A §1; the only pin is a literal input at `tests/completion-assert.bats:2297`.)*
- **Files:**
  - `scripts/wrap-ledger.sh:2492` → `"✅ Complete & live on trunk — nothing this session filed is open."`
  - `:2998` → `complete — nothing this session filed is open`
  - Mirrors: `commands/wrap.md:82`, and `CLAUDE.global.md:720` (today it reads `— safe to close, nothing unsaved.`).
- **Tests** (`tests/wrap-ledger.bats`):
  - `✅ default READOUT names its scope`: new string present, `! grep 'nothing to do'`. Fails pre-fix.
  - `--full Next row on ✅`. Fails pre-fix.
  - `wrap-ledger.bats:2455` (greps `^READOUT=✅`) stays green.

**A3. The ledger counts this turn's re-checks as ⛔ on the ✅-eligible path.** *(W2, after A2. 91%. Receipts: the boundary measurement in §2; slot A §4 sandbox; critique-contract §3–4.)*
- **Producer read:** `scripts/wrap-ledger.sh:1499-1508`.
  - Leave the main `@tsv` line and `$mine`/`$ask` **byte-identical**.
  - In the same jq, after that line, emit one `RC\t<id>\t<ts>\t<tier>` line per open packet where `(.session_sid//"") != $sid`, `(.rechecks//[])|last|.sid == $sid`, and that last entry has a non-null conviction and a non-empty receipt.
  - Parse the TSV from line 1 only, so no empty cell can collapse into the free text (critique-contract §4). Every RC field is non-empty by construction.
- **Turn bound.** Only when RC lines exist:
  - Resolve the transcript the way the YOURS peer code does (`:1285-1287`).
  - Read the last genuine human prompt's timestamp with a bounded tail (4 MiB, as `hooks/lib/turn-scan.sh`) and the jq in `/tmp/rpic-REPORT/lasthuman.jq`:
    - `type:user ∧ ¬isMeta ∧ ¬isSidechain ∧ no tool_result ∧ (origin.kind=="human" or, if origin is absent, ¬machine-envelope)`, or
    - `attachment.queued_command` with `commandMode:"prompt"`.
  - Keep the RC rows whose epoch is ≥ that bound. Compare epochs, not strings.
  - Fail-open: no transcript, no bound or a jq error ⇒ `BLOCKED_RECHECKED=0`, with `RECHECKED_SRC` = `none` or `error`.
- **Ladder:** a new `elif [ "$BLOCKED_RECHECKED" -gt 0 ]` immediately before `elif [ "$YOURS" -gt 0 ]` (`:2618`), with the §3 sentences.
  - Amend the `:2500-2503` comment: the re-check variant deliberately rides the ✅-eligible path.
- **Emit:** `BLOCKED_RECHECKED=`, `RECHECKED_IDS=` and `RECHECKED_SRC=` after `BLOCKED_SRC` (`:2801`), outside the positional BUSY lines.
- **Tests:** new `tests/wrap-ledger-recheck.bats`, using the `tests/wrap-ledger.bats:10-79` setup, the real `bin/cc-decide list` over `CC_DECISIONS_DIR` fixtures, `WRAP_SESSION_ID`, and a `WRAP_TRANSCRIPT` fixture.
  - `stamp after the last human prompt ⇒ RUNG=⛔ 'Blocked — research done, implementation pending'`. **Pre-fix ✅** (slot A S1).
  - `a later human prompt ⇒ RUNG=✅ BLOCKED_RECHECKED=0`.
  - `a later queued prompt attachment ⇒ ✅`.
  - CONTROL: `a later task-notification or 'Stop hook feedback' record ⇒ still ⛔` (a block cannot launder a stamp).
  - CONTROL: `latest re-checker is another session ⇒ not counted`.
  - CONTROL: `my entry lacks conviction or receipt ⇒ not counted and UNCONVICTED_PKTS unchanged`.
  - CONTROL: `dirty + stamp ⇒ 🔧` and `unlanded + stamp ⇒ 📦`.
  - CONTROL: `filed-by-me + stamp ⇒ filed wording byte-identical, BLOCKED_WHAT from the filed packet`.
  - `two stamps ⇒ '2 decision(s) need your call: cc-decide list --open'`.
  - `no transcript ⇒ RECHECKED_SRC=none, ✅`.
  - `unreadable store ⇒ BLOCKED_SRC=error, BLOCKED_RECHECKED=0`.

**A4. `cc-decide recheck` verb.** *(W1. 93%. Receipts: `bin/cc-decide:350-374`, `:528-538`; the pre-fix probe below; 74 of 74 ids cited in the real persisted report.)*
- **Usage:** `recheck <id> --conviction N --receipt FILE [--recommendation r] [--tier signoff|default|nochange] [--session-sid s]`.
  - It appends `{sid, ts, conviction, receipt, recommendation, tier}` (tier defaults to `signoff`) to `.rechecks[]` on an **open** packet, via the tmp+mv pattern (`:366-372`), then logs `log_idl recheck`.
  - Header line at `:21-46`; `cmd_recheck` after `cmd_transition`; dispatch at `:531-535`.
- **Refusals,** each prefixed `cc-decide recheck:`:
  - unknown id (rc 2)
  - not open (**rc 3**, file byte-identical)
  - conviction >90 ("implement it"; held until ruling B6)
  - missing or invalid conviction
  - receipt that is not an existing regular file, is under `/tmp`, `/private/tmp` or `/var/folders`, or does not contain the id (`grep -F`)
  - an unknown tier
  - an unresolvable sid (the `:276-279` ladder)
  - an active research program (`research-program.sh is-active "$PWD"` rc 0 ⇒ rc 4, "program sessions use the kit's implementation signature")
- **Never changes** status, id, class or any other field.
- **Tests** (`tests/cc-decide.bats`):
  - append leaves `del(.rechecks)` identical before and after
  - two calls append two entries, and `list --open --json` carries `rechecks`
  - each refusal above, asserting `*"cc-decide recheck:"*`, `! *"unknown verb"*`, and rc 3 for non-open
- **Vacuity guard, measured pre-fix:** `CC_DECISIONS_DIR=$(mktemp -d) bash bin/cc-decide recheck deadbeef0001 --conviction 91 --receipt "x => y"` ⇒ rc 2, `unknown verb recheck`, plus `usage()` text containing `implement it`, `REFUSED` and `unknown id`. A test that grepped only those strings would pass before the fix.

**A7. Operator-readout: ⛔ arm, answer-first research header, session-owned decision lines** *(A11 merged in). (W2. 92%. Receipt: slot C §5, scenario B.)*
- **File:** `hooks/operator-readout.sh`.
  - `:1236`: add `"⛔") state="$(lf READOUT)"`, truncated so the header stays ≤100 columns (`:1596-1598`).
  - `:1446`: the fire predicate also fires on `RUNG=⛔`.
  - Decisions jq (`:1015-1060`): split out `mine-decision` (`session_sid==$sid` or latest `rechecks[].sid==$sid`) in the same jq, mirroring the `yours` split (`:1125`), and exclude those from `◆ N decisions — your call`.
  - Render them after the `yours` block (`:1526-1550`) as `◆ [this session · <tier>] <what_plain> — <recommendation> <conviction>%   cc-decide show <id>`, with `YMAX=5` and a `↳ +K more this session (S sign-off, L low-stakes): cc-decide list --open` rollup.
  - Header: the research ⛔ gets the answer-first reorder (`hdr="OPERATOR ▸ ${state}${_y:+ · $_y}"`, as at `:1513-1515`). A filed ⛔ is appended as state, the way 📦/🚀 are.
- **Tests** (`tests/operator-readout.bats`):
  - `research ⛔: line 1 is 'OPERATOR ▸ ⛔ Blocked — research done…' and the pile partition is not on line 1`. **Pre-fix: `OPERATOR ▸ 4 need your call`** (slot C, measured).
  - `filed ⛔ state is rendered`. Pre-fix lost.
  - `⛔ with an empty pile still renders`. Pre-fix silent.
  - `an own packet is itemized and excluded from the pile; a foreign packet stays in it`.
  - `8 own packets ⇒ 5 lines + '↳ +3'`.
  - `header ≤100 cols with a 300-char what_plain`.
  - `⛔ never renders SAFE TO CLOSE`.
  - The existing 📦/🚀/🔧/✅ tests stay green.

**A8. Protocol text: E0 stays a superset, net −16 loader units.** *(W3. 92%. Receipts: `/tmp/rpic-REPORT/delta.py`; `bin/cc-instruction-budget measure` ⇒ 30,317 → 30,301; user tier 60,998 > 60,000 with `enforce: true`.)*
- **`CLAUDE.rules.slim.10-session-close.md`.** Apply the **cuts first**: `judge()` refuses an edit whose new total is over budget and over the current total (`hooks/lib/instruction_budget.py:656`).
  - :34: `| Read-only / advisory / research (no tracked writes) |` → `| Read-only / advisory (no tracked writes) |` (−11). The second sentence is unchanged.
  - :160: delete ` (an unattended ask whose default fires at its deadline)` (−56), and change `, and it outranks every other rung;` to `;` (−34). The priority order is stated at :90.
  - :189: delete ` The counted `◆` line still owns the machine's standing pile.` (−61; restated at :156).
  - :99: after `before yielding.` insert ` What it cannot drive it files (`cc-decide open`/`recheck <id>`) so the rung is `⛔`; its verdict: `no — research done, implementation pending: …`.` (+146). "A read-only turn that names drivable work is not E0" stays, and so does the program sentence.
- **`CLAUDE.global.md`** (not budgeted, `config/instruction-budget.json` `deploy_sources`):
  - :601: drop ` / research` from the row label.
  - :721: after "before you yield." add the same rule in the full style.
  - Keep the `| _E0_ read-only` label and "answered by relaying the certificate" (pinned at `research-program-exemption-rules.bats:28`).
- `CLAUDE.global.slim.md` carries no close-protocol text, so it needs no edit. Say so in the commit.
- **Tests:** new `tests/close-research-pending-rules.bats`. These pins guard a contract a past draft nearly narrowed, the same pattern as `research-program-exemption-rules.bats`.
  - Both variants' E0 still contain "A read-only turn that names drivable work is not E0" (case-folded) **and** `recheck` **and** `research done, implementation pending`. Fails pre-fix.
  - `bin/cc-instruction-budget range origin/main..HEAD` ⇒ rc 0.
  - `research-program-exemption-rules.bats` stays green.

**A9. `/explain-decisions` gets its disposition step.** *(W3, after A4. 92%. Receipts: slot D §3.5; slot F s6 lenient P 6/6.)*
- **File:** `commands/explain-decisions.md`. After the existing paragraph, add:
  1. Write the report to a durable path (a repo's `docs/research/<slug>/` or `~/.claude/autonomy/research/<slug>/`), never `/tmp`. It is the receipt.
  2. Close each packet the re-check proves settled or duplicate at >90%: `cc-decide action <id> --evidence "<why>"`.
  3. Implement each recommendation above 90% that is in none of the sign-off classes: escalation surface, money, credentials or permissions, self-modification, irreversible or production-mutating, third-party contact or publishing.
  4. Stamp every remaining open packet: `cc-decide recheck <id> --conviction N --receipt <report> --recommendation "<one line>" --tier signoff|default|nochange`.
     - An item above 90% that is in a sign-off class cannot be stamped (ruling B6). Name it first on line 1.
     - Skip this step inside an active research program.
  5. Close with the §3 lines 1–3.
- **Test:** new `tests/explain-decisions-command.bats` greps for `cc-decide recheck`, `never` + `/tmp`, and `research done, implementation pending`. Fails pre-fix; no test references this command today.

**A10. FREE WIN stops claiming what it did not check.** *(W1. 97%.)*
- `hooks/boundary-handoff.sh:847`: "no operator step outstanding" → "no operator step filed by this session".
- **Test:** the existing free-win fire case in `tests/boundary-handoff.bats` asserts the new phrase and the absence of the old one. Fails pre-fix; nothing pins the old phrase.

**A12. The recycle successor brief does not hand the operator's sign-offs to the successor.** *(W1. 92%. Receipt: critique-alarm §3; `handoff-fire.sh:16822-16824`.)*
- After the "collect it" sentence, add a static `printf`: "A ⛔ that reads "research done, implementation pending" is the operator's sign-off, not yours: leave those packets alone unless this brief names them."
- **Test:** `tests/handoff-fire-ledger-stamp.bats` test 5 (`:189`), where the recycle brief carries the stamp, also asserts the new sentence. Fails pre-fix.

**Dropped from implement-now:**
- A5 (D8): handed to the sibling C3 lane (§8 rows A-5, A-6, C-8).
- A6 (template edit): critique rows A-11 and C-7.

### (b) Needs an operator ruling

Each is to be filed as `cc-decide open --class C` with the conviction and receipt shown. Options are written as `label::outcome`.

**B1. When research finds a reversible change in none of the sign-off classes, and my conviction is 62–88%, how does it proceed?**
- Example: writing the kitty shortcut into the tracked example config, at 85%.
- **Conviction 60%** for "do-unless-vetoed".
- **Receipt:** `slot-H-gates-recycle.md` §H1; `/tmp/rpic-H/tiers.tsv` (12 such items in the incident: 62, 65, 70, 70, 75, 80, 80, 82, 85, 85, 88, 88); `critique-alarm.md` §2 (no class C→B path exists).
- **Options:**
  - `ask::it stays class C and waits for you; the re-check only labels it low-stakes (today)`
  - `do-unless-vetoed::the agent files a class-B successor whose default (its recommendation) fires at a deadline unless you veto; the dispatcher that fires defaults was measured idle for 27 hours on 10-17/18`
  - `act now at 80% or above with a rollback one-liner::7 of the 12 incident items would have been done at once; you read the trail afterwards`

**B2. Does your 2026-10-16 "zero human in loop" apply outside registered research programs?**
- **Conviction 80%** for "narrows".
- **Receipt:** §6; `feedback-operator-will-not-read-signoffs.md`; `research-program.sh is-active <incident cwd>` ⇒ rc 1.
- **Options:**
  - `narrows::outside programs, only results in a sign-off class (money, auth, third parties, publishing, self-modification, production) get a one-line yes/no; the memory gains one scope line`
  - `universal::no sign-off anywhere; every result is driven or queued do-unless-vetoed, and ⛔ is kept for acts no agent can do`

**B3. Should "Complete" require a scope this session actually wrote?**
- Today a DoD holding only other sessions' blocks, with 0 checkboxes, reads "met".
- **Conviction 55%** for changing it.
- **Receipt:** `slot-A-ledger.md` §3 (74 of 78 DoD files show no boxes in that view); sibling F19.
- **Options:**
  - `make it unknown::most closes read 'completeness UNKNOWN' and the SAFE TO CLOSE certificate becomes rare`
  - `leave it::the vacuous 'met' stays; A2's wording already says what was checked`

**B4. Should a sign-off you give outside the pane wake the session that filed it so it recycles into implementation?**
- Examples: cc-decide in your terminal, or another device.
- **Conviction 70%** for building it.
- **Receipt:** `slot-H-gates-recycle.md` §H2 carrier table.
- **Options:**
  - `build it::a 'cc-decide answer <id> --option <label>' verb plus a sweep that messages the filing pane; it touches live sessions`
  - `in-pane replies only::you answer in the session and it recycles on your reply; nothing new is built`

**B5. After sign-off, should implementation recycle the research pane, or get its own session per approved item?**
- **Conviction 85%** for the existing rule.
- **Receipt:** `commands/handoff.md:456-466`; incident recs 492 and 566.
- **Options:**
  - `existing rule::one approved track recycles this pane; two or more independent items get one dispatched session each and the lead keeps the rest`
  - `always recycle::one implementation session per research turn; approved items run one after another`

**B6. May a decision above 90% still be filed or stamped for your sign-off when it is in a sign-off class (auth, money, destructive migration, production)?**
- Today cc-decide refuses any `open` above 90% (`bin/cc-decide:210`), and `recheck` copies that refusal. So `b4373234dd78` (92%, auth) cannot be filed, though G2 says stop and ask.
- **Conviction 85%** for "yes with a named class".
- **Receipt:** `bin/cc-decide:206-214`; `slot-H-gates-recycle.md` §H1, "Gap the rule exposes".
- **Options:**
  - `yes with a named class::open and recheck accept a conviction above 90 only with --surface auth|money|migration|production|third-party, and the ledger shows ⛔`
  - `no::above 90% the agent implements even on those surfaces, and the prose escalation rule is the only gate`

## 8. Critic issues and their dispositions

**critique-alarm.md**

| # | Issue | Disposition | Evidence |
|---|---|---|---|
| A-1 | HIGH. A sticky re-check ⛔ multiplies Q&A convictions (critic replay: 16 → 72; 196 → 380 turns reading ⛔). | **Accept the second fix (turn scope). Reject the first** ("re-check-only never convicts"): on the stamping turn it would release the incident shape, a yes over stamped decisions (`h1` fires only because the term convicts). | Boundary measured on the incident (§2). Exposure ≤74 turns, all stamping turns. ≤18 one-time asks on them. q1–q4 fire under any ⛔, so only scope can protect them (`blk.out`). |
| A-2 | HIGH. Stamps label default and nochange items as sign-offs (56 vs §4's 33). | **Accept in part:** `--tier`, shown per item and in the rollup (A4, A7). **Reject "only signoff counts":** under today's rules every stamped class-C packet still waits on the operator (class C has no default, `bin/cc-decide:18-19`), so counting fewer would understate what waits, which is the incident's own failure. The C→B route is ruling B1. | `bin/cc-decide:13-19`; `/tmp/rpic-H/tiers.tsv` |
| A-3 | HIGH. A stamped session is never good to close, and the recycle brief says "collect it". | **Accept:** turn scope (the rung returns to git state at the next human prompt) and A12. | `handoff-fire.sh:16822-16824`; boundary at `head -560` ⇒ 02:47:35Z |
| A-4 | MEDIUM. Concurrent panes stamp the same pile, and the header and pile double-count it. | **Accept:** latest-re-checker attribution (A3, A7). A11 is merged into A7, which excludes own packets from the pile count. | critique-alarm §4 (up to 7 concurrent) |
| A-5 | MEDIUM. D8 is underpowered, has an FP, and fabricates "foreign" ids through recycle lineage. | **Accept:** D8 is removed from implement-now and handed to the sibling's C3 (D8 v2) lane, with its predicate and these measurements. | 3/1,877, precision 2/3 [0.21, 0.94]; sibling C3 judges 25–30 |
| A-6 | MEDIUM. D8 fires at 👤, falls into the assert budget, and collides with the sibling's D8 v2. | **Accept; moot after A-5.** Hand-over notes: drop 👤; own class whenever `d8=1 ∧ contra=0`; one name and one cap with F13. | sibling README F13 row (silent on 👤/⛔) |
| A-7 | MEDIUM. A1's "line 2 begins with ⛔" disjunct lets the contradiction through. | **Accept:** refined predicate, no line-2 disjunct, with the h1/h2/h3 FIRE controls. | `blk.out`: h1/h2/h3 fire under A1r |
| A-8 | LOW. The ⛔ facts text says "filed this session" for re-checked packets. | **Accept:** the facts are chosen from `BLOCKED` vs `BLOCKED_RECHECKED` (A1). | `completion-assert.sh:1207` |
| A-9 | LOW. Fired peers and assignees are not exempt from the ⛔ term. | **Accept in part:** the re-check path is covered, because the prescribed close abstains and self-close never refuses on ⛔ (`handoff-fire.sh:7721`). Convictions of peers over packets the peer filed are pre-existing and unverified as wrong (6 of 24 ⛔ IDL rows were peer `30a68a59`), so they are listed as a side finding. | critique-alarm §9 |
| A-10 | LOW. A7's ⛔ header is not gated on the write turn. | **Accept:** the answer-first reorder applies only to the research ⛔, which is turn-scoped by construction. A filed ⛔ is appended as state, the same as 📦/🚀 today. | `operator-readout.sh:1505-1516` |
| A-11 | LOW. A6 primes the D6 template on every shape fire. | **Accept:** A6 is dropped. The research wording lives in A8 and A9. | 8 shape fires in 6 sessions in 16 h (critic) |
| A-12 | LOW. No research-program carve-out on the re-check path. | **Accept:** A4 refuses inside an active program, and A9 skips the stamp. | `scripts/lib/research-program.sh is-active` |
| A-13 | LOW. The demand is impossible above 90%. | **Accept:** A9 names the >90 branch (implement it, or name it first if it is in a sign-off class), and B6 decides the filing. | `bin/cc-decide:210` |

**critique-contract.md**

| # | Issue | Disposition | Evidence |
|---|---|---|---|
| C-1 | HIGH. A1 as specified releases h1, h2 and h3. The lib is not loaded at the term. | **Accept:** refined predicate; the lib is sourced inside the term with a fail-toward-detection fallback; the `:1199-1203` and D7 `:1594-1595` comments are corrected. | `blk.out`; `_ca_source_close_shape` is called only at `:1529`/`:1611` (grep) |
| C-2 | HIGH. A8 narrows E0 from "read-only turn" to "research". | **Accept:** the general sentence is kept and the research clause is appended. Re-measured: −16 net. | `delta.py`; `cc-instruction-budget measure` 30,317 → 30,301 |
| C-3 | MED-HIGH. ⛔ becomes a cheap store-write escape from the 🔧/📦 floors. | **Accept:** the research ⛔ ranks on the ✅-eligible path after custody, resident, filed, unconvicted, floor, no-trunk and 🚀. The receipt must be a durable file that contains the id. | `wrap-ledger.sh:2504-2530`; 74 of 74 ids appear in the real persisted `REPORT.md` |
| C-4 | MEDIUM. A3's jq contradicts its control and misattributes UNCONVICTED; TSV collapse. | **Accept:** `$ask` is unchanged; re-check rows come from this session's latest entry and are emitted as separate `RC` lines, never in the TSV. | `a3_fix.json` (critic); `IFS=$'\t' read` collapse |
| C-5 | MEDIUM. A4's refusal tests pass vacuously before the fix. | **Accept:** tests assert the `cc-decide recheck:` prefix, the absence of "unknown verb", and rc 3. | Pre-fix probe: rc 2, `unknown verb recheck`, usage contains `implement it`, `REFUSED`, `unknown id` |
| C-6 | MEDIUM. §4 is inconsistent with the items that apply it (gate-classify says C for hooks); vocabulary; class-B branch. | **Accept:** repo carve-out with evidence; per-item F2 numbers in §7; one sign-off-class vocabulary in §4 and A9; the class-B branch becomes ruling B1. | `gate-classify.sh` probes; 85 hook commits / 14 d; 5 slim-rule commits / 30 d |
| C-7 | MEDIUM. A6 forks the template from its mirrors and conflicts with sibling `22c1dbb7a`. | **Accept:** A6 dropped. The template is owned by the sibling's C5 commit. | `git show 22c1dbb7a -- hooks/lib/close-shape.sh` |
| C-8 | MED-LOW. D8 is the lexicon arm the constraints reject; `\s` in awk; "no fork" is false; co-fire class unspecified. | **Accept:** D8 dropped (A-5). | slot D §5 constraints 1–3 |
| C-9 | LOW-MED. The research ⛔ wording is undocumented; `ACT:` is not legal here; A2's mirrors were missed; A11 breaks the 24-row pane. | **Accept:** the READOUT uses the documented `⛔ Blocked — …` clause; the `ACT:` line is replaced by the S6 line (measured no-tell); the mirrors are in A2; YMAX=5 + `↳` rollup. | `close-shape.sh:223-225`; slim:92, :137; `operator-readout.sh:1534-1539` |
| C-10 | LOW. Budget order. | **Accept:** cuts are applied before the addition in the same commit. | `instruction_budget.py:656` |

**Side findings for the orchestrator** (outside this design, owned elsewhere):
- completion-assert's kill-switch envelope filter does not list `<agent-message`, so a peer's "and stop" would disarm it (slot B §2).
- The research-precognition regex fires on peer hand-backs that start `Another Claude session sent a message` (slot E §3).
- anti-deference reads the previous assistant text (4 of 4 replayed stops; slot B §2).
- A subagent read a Keychain secret (g06; slot E §2).
- `commands/handoff.md:314-315` documents goal inheritance the code no longer has (slot H).
- The ⛔ term convicts fired peers over packets they filed (6 of 24 IDL ⛔ rows; critique-alarm §9; unverified as wrong).
- The ⛔ term shares the `assert` budget (12 of 23 ⛔ rows capped). Its own cap class belongs with the sibling's F11/C2 per-fact latch.

## 9. Method

| Slot | Question | Read / ran | Limits |
|---|---|---|---|
| A ledger | How does wrap-ledger compute the rung, and why ✅? | `scripts/wrap-ledger.sh` in full; a sandbox mirroring `tests/wrap-ledger.bats:10-79` with the real `cc-decide list` (S1–S6); a DoD scan of 78 files | The vacuous-`met` prevalence is an estimate (simulated view) |
| B assert | Did completion-assert or close-shape force the yes? Is D8 viable? | A replay of the first 464 incident records plus candidate closes through the real hooks; the regex inventory | bats refused (cc-bats concurrency) |
| C readout | What did the operator surface show, and why did it not help? | Stop records of the incident; a sandbox with scenarios A–C; a 1,206-transcript frequency scan | bats refused |
| D protocol | Which rules govern, and what prior art binds? | slim + full § Session Close; `git log -S`; docs, backlog, decisions and memory search | slim:86 "lost to the template" is inferred from timing |
| E incident | Timeline, the operator's words, the artifacts | The incident transcript (snapshot of 710 records), 9 subagent files, the predecessor `f06b5e9b` | none |
| F store signals | Precision and recall of s1–s7 | 1,040 turns from a 400-session cap (seed 20261018); 91 + 45 hand labels | one labeller; teammates and workers inflate TN |
| G close-text signals | Precision and recall of p1–p4; alarm inflation | **census** of 350 origin-interactive sessions, 1,877 turns, 14 days; 90 labels | one labeller; 158 heartbeat finals |
| H gates and recycle | Stakes rule, recycle path, signoff memory | gate tables; 7 `gate-classify` probes; `handoff-fire.sh` recycle code; hand-tiered 74 rows | the tiers are inference; goal bats refused |
| DESIGN | Synthesis | All slots; D8 census replay; ⛔ IDL fires | — |
| critique-alarm / -contract | Adversarial: alarm inflation; contract integrity | Census replays (`union.py`, `edsticky2.py`); A1 and A3 sandboxes; budget delta | the replays assume A9 is followed literally |
| this REPORT | Resolve every critic issue; re-measure the revised design | `blk.sh` (13 cases × ORIG/A1r/anti-deference); `lasthuman.jq` on the incident transcript; `originprobe.py` (200 of 1,544 transcripts); `pol2.sh` over the 74 `/explain-decisions` finals; `delta.py` plus `cc-instruction-budget measure/assert`; the pre-fix `cc-decide recheck` probe; `gate-classify` probes; git history counts; the sibling C3/C5/C6 verdicts | bats deferred (`cc-bats: REFUSED — 2 concurrent bats execution root(s)`); the waiver writes `~/.claude/state/bats-waivers.jsonl`, so it was not used. The `pol2.sh` count skips the CA_SETTLED path through line 1. A3 is a new design that no critic has reviewed: its turn-scope bound is measured on one incident transcript and its exposure bound comes from the census, so conviction is held at 91%. |

**Measured vs inferred.**
- Measured: the rung and readout behaviour, the sandbox verdicts, the census counts, the boundary timestamps, the budget numbers, the git counts, and the pre-fix probe.
- Inferred:
  - slot H's tiers;
  - the effect of A3 on live sessions beyond the census bound;
  - that A9 makes `/explain-decisions` sessions stamp (it is protocol text, not a gate);
  - the critic's recycle-chain propagation and template-priming risks (both now designed out rather than measured away).

## Appendix: index of inputs

| File | Content |
|---|---|
| `slot-A-ledger.md` | ladder order, the incident inputs, sandbox S1–S6, insertion points |
| `slot-B-assert.md` | arm map, incident replay, D8 proposal, the lexical-trap table (c1–c12) |
| `slot-C-readout.md` | readout render at each incident Stop, the ⛔-arm defect (scenario B), render budget |
| `slot-D-protocol.md` | governing rule text, the three meanings of read-only, prior art, design constraints |
| `slot-E-incident.md` | timeline, operator quotes, artifacts, the predecessor `f06b5e9b` instance |
| `slot-F-signal-decide.md` | store-side signals s1–s7, n=91 + 45 labels |
| `slot-G-signal-prompt.md` | prompt and close-text signals p1–p4, 1,877-turn census |
| `slot-H-gates-recycle.md` | stakes composition, recycle mechanics and hazards, signoff-memory verdict |
| `DESIGN.md` | pre-critique synthesis (superseded where §8 says so) |
| `critique-alarm.md` | alarm-inflation critique (13 issues) |
| `critique-contract.md` | contract and gate-integrity critique (10 issues) |
| `/tmp/rpic-REPORT/` | `blk.sh` + `blk.out`, `lasthuman.jq`, `originprobe.py`, `pol.sh`, `pol2.sh`, `ed_finals.jsonl`, `delta.py`, `slim.after.md`, `patch_a1r.py` (the critic's refined A1, applied to a scratch copy) |
