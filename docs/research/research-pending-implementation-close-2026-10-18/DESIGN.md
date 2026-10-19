# Design: "research done — implementation pending" as a close status

Inputs: slot-A … slot-H in this directory (all eight read in full). Line numbers are from worktree `close-status-research` at `36afca47f`; trunk `dfdb5c273` is 1 commit ahead and touches none of the cited files (`git diff --stat HEAD origin/main -- <the 13 files>` ⇒ empty). Sibling study `docs/research/close-behavior-2026-10-18/` (branch `cc-004752-67086`, not on trunk) covers the same failure class; its §6 rejections bind here and are honoured. Scratch: `/tmp/rpic-DESIGN/`.

## Answer first

1. **Root cause.** Every ledger term that can say "not done" keys on a record *this session filed*. The research turn filed nothing: it re-checked 74 packets other sessions own and wrote its report to `/tmp`. So the ledger fell through to its default `✅ … nothing to do` (`scripts/wrap-ledger.sh:2492`). The close-shape template then supplied the yes sentence (`hooks/lib/close-shape.sh:179`), and D6 told the agent to relay that ledger line verbatim (`:309`).
2. **Signal.** The agent declares the pending sign-offs in the decision store. A new `cc-decide recheck` verb stamps an existing packet; `cc-decide open` covers new decisions. The ledger counts those declarations as ⛔. Precision is 1.0 by construction, and Q&A cannot trigger it.
   - A narrow backstop arm (D8) catches the undeclared case and demands the declaration. D8 fires on a done-reading close that cites *open class-C packets* with a recommendation.
   - **Measured:** 3 fires in 1,877 turns (0.16%), 0 on 57 status prompts, 2 clear hits and 1 borderline. Every prose heuristic measured (slots F, G) has precision of about 0.33, so none of them is used to render a status.
3. **Shape.** No new glyph. It is a **⛔ sentence variant**:
   - Line 2: `⛔ Research done — N decision(s) await your sign-off: cc-decide list --open`.
   - Line 1: `❌ Good to close: no — research done, implementation pending: …`.
   - **Measured blocker:** today the existing ⛔ term in completion-assert *convicts that correct close* (sandbox `fired:false-done:ledger`). In the live IDL window, 4 of the 6 fires whose only fact was "BLOCKED ON YOU" landed on closes already answering "❌ Good to close: no". Item A1 fixes this first.
4. **Auto-proceed** needs no new gate. It is F2 (>90) ∧ F3/G2 ∧ not a cc-decide class-C surface ∧ not a manual-command-delivery gate class. In the incident, 0 of 59 live decisions qualified. The operator's "lower stakes ⇒ just do it" cannot fire on items at 90% or below unless he rules on the bar (B1).
5. **Sign-off → recycle** already works when he replies in the session: a `handoff-fire.sh --recycle --prompt-file … --goal …` as the last act of the reply turn. New in this design: the `recheck` verb, and a ⛔ the ledger can compute for it. An out-of-band sign-off wake is a ruling (B4).
6. **Signoff memory: the request narrows it** (80%). That rule is scoped to registered research programs, and its object is reading artifacts. The checkpoint here is a one-line yes or no per item, and only on class-C surfaces.

## Phase 0 — agent team orchestration

- **EXECUTION LOCUS PER WAVE:**
  - **S** (one dispatched `/handoff` session) for Waves 1–3 below.
  - Inside that session, Agent-Teams teammates are split by **file owner**:
    - wrap-ledger.sh (A2, A3)
    - completion-assert.sh + close-shape.sh (A1, A6, A5)
    - bin/cc-decide (A4)
    - operator-readout.sh (A7, A11)
    - docs/commands/boundary-handoff text (A8, A9, A10)
  - Each item lands on its own; the per-file serial order is given below.
- **Waves:**
  - W1 (no dependencies): A1, A2, A4, A6, A7, A10.
  - W2: A3, then A5. A5 reads A3's field, but it is inert and fail-open without it.
  - W3: A8, A9, which name the A4 verb. A11 is optional.
- **Lead budget:** the orchestrating lead keeps ≥50% of its window. Succession point: after W1 lands.

## 1. Root cause (file:line)

| # | Cause | Evidence |
|---|---|---|
| R1 | **The ledger has no input for "research produced pending actions".** The default `RUNG="✅"; READOUT="✅ Complete & live on trunk — nothing to do."` survives whenever no arm fires. Every arm that could fire is session-filed: ⛔ `$mine` = `.session_sid == $SID` (`wrap-ledger.sh:1500`), and FILED_MINE / UNCONVICTED / YOURS likewise (`:1298-1327`, `:1396-1450`). | `wrap-ledger.sh:2492`, `:2500-2511`. Of 74 packets, 0 carry sid `74728043`. The session ran 0 `cc-decide`/`cc-backlog` writes before the close (slot A §3, slot E §2). Sandbox: 5 foreign open class-C packets ⇒ `RUNG=✅ BLOCKED=0` (slot A §4 S1–S2). |
| R2 | **The research never reached a store.** The report sat at `/tmp/xd/REPORT.md`. `commands/explain-decisions.md` (8 lines) has no disposition step. cc-decide has no verb to record a re-check: packets keep only the opener's sid (slot E §2 key list). | slot D §3.5, slot E §2 |
| R3 | **The hooks wrote both lines of the false close.** | |
| | – Line 1 came from the template's only finished sentence: `yes — nothing of mine is open; follow-on: <…\|none>` (`close-shape.sh:179`). | |
| | – Line 2 came from D6's order to "relay READOUT's glyph and state clause verbatim" (`:309`). | |
| | – D6 was armed by a `/tmp` scratch Write: `session_writes_paths "$TP"` counts any path, subagents included (`completion-assert.sh:1513`; `session-writes.sh:236-239`). | slot B §3: the agent used the template's yes branch word for word once its agents returned. |
| R4 | **Vacuous scope.** `DOD=present` is set when the file exists (`:905`), and REMAINDER=0 ⇒ `SCOPE=met` (`:938-940`). The repo-key DoD kept 16 inherited blocks with 0 checkboxes, so the close read "Complete" rather than "completeness UNKNOWN". | slot A §3: 74 of 78 DoD files show zero boxes in that view (estimate) |
| R5 | **Nothing checked the claim, and the operator surface agreed with it.** | |
| | – completion-assert abstained `ledger-clean`, then **timed out** (5,337 ms > 5,000) on the final Stop. | slot B §1 |
| | – The readout header led with the machine pile and `✅ live on trunk` (`operator-readout.sh:1355`, `:1491-1515`). | |
| | – The readout has **no ⛔ arm at all** (`case "$RUNG"` at `:1236` handles 📦 🚀 🔧 ✅ only; `grep -c ⛔ hooks/operator-readout.sh tests/operator-readout*.bats` ⇒ 0). | slot C §5 B: a session-owned ⛔ renders `OPERATOR ▸ 4 need your call` |
| R6 | **The protocol gives no report state for this.** | slot D §3 |
| | – slim:34 lists research under "no ledger, no readout". | |
| | – E0 (slim:99) says to drive the passes, but says nothing about how to report the rest. | |
| | – BLOCKED (slim:189) promises a ⛔ the ledger cannot compute for re-checked packets. | |
| R7 | **The downstream recycle inherits the blind spot.** FREE WIN asserts "no operator step outstanding" from ✅ alone (`boundary-handoff.sh:847`). It recycled the predecessor `f06b5e9b` with "Nothing to do unless the operator asks", over 35 + 70 unexecuted disk-cleanup items. | slot E §4 |

## 2. Detection signal

**Measured, from slots F and G** (one labeller each, small n):

| Signal | Source | Result |
|---|---|---|
| s1 packets opened this turn | F, n=91 | strict P 0.23, R 0.14; lenient P 0.62, R 0.30. The incident did not fire it. |
| s2 packets read | F | P 0.23, R 0.14 |
| s3 writes outside git | F | P 0.17, R 0.27. 83% of its fires are briefs, scripts and commit messages. |
| s4 research fan-out, no commit | F | P 0.62, R 0.36 |
| s6 ∨ s7 (`/explain-decisions` ∨ research-only fan-out) | F | strict P 0.59, R 0.59; lenient P 0.77, R 0.63 |
| s7 ∨ s2c, ✅-close subset | F, n=45 | 5/5 recall at P 0.33 |
| p1 research-intent prompt regex | G, 1,877-turn census | R 1/15; 67 of its 90 fires match only a `/research` path |
| p2s close text (recommendation ∧ "nothing of mine is open / follow-on: none / read-only / nothing to do") | G | vs harm labels P 4/12 = 0.33, R 4/4; fires on 47 of 1,877 turns (2.5%) |
| (p2s ∨ p4) ∧ tools≥3 | G | P 0.67, R 0.67, but the threshold was chosen after seeing the false positives |

**Measured by this synthesis** (`/tmp/rpic-DESIGN/d8c.py`):
- **Signal:** slot B's D8 predicate, restricted to class C, replayed over slot G's census: 1,877 turns, 347 origin-interactive sessions, 14 days.
- **Packet open-at-time:** reconstructed from `created`/`resolved`. Terminal packets that were compacted are missing, so the count is a lower bound.

| Measure | Result |
|---|---|
| Fires | **3 of 1,877 (0.16%)**, in 3 sessions; **0 of 57** status prompts |
| In-sample vs G's harm labels (n=90) | TP 2, FP 0, FN 2 |
| In-sample vs the state labels | TP 2, FP 0, FN 13. 11 of the 13 false negatives are closes that already said no or ⛔. |
| Hand review of all 3 fires | the incident (yes, 17 open ids, 80–88%) · `978fd287` 10-06 (line 1 ✅, 2 open decisions at 85–88%) · `d6ae5d72` 10-18 borderline ("✅ Good to close: yes. Nothing of mine is open. Two follow-ons are yours: one decision `33620baeb16b` … 77%") |
| Effect of also counting class B | adds 1 false positive: a 👤 close over two class-B defaults (`2a3224ef`) |

**Choice.**

- **Primary, rung-setting:** a **session-declared store fact**. That is an open class-C packet this session filed (existing), or one it **re-checked** (new `rechecks[].sid`). The ledger counts these as ⛔. The signal is deterministic and session-scoped, and a declaration cannot misfire, so precision is 1.0. Recall is whatever producers declare, which is why A8/A9 make the declaration part of the protocol and of `/explain-decisions`. Slot F found `/explain-decisions` is the main producer of this shape: s6 lenient precision 6/6.
- **Backstop, never renders a status:** D8. It blocks once to *demand* the declaration, and it does not paint a claim on the operator's surface. Slot C reached the same conclusion: heuristics are fit to demand filing, not to render.

**Why it does not inflate alarms on Q&A or status turns.**
- The primary signal needs a write by this session to the decision store. A Q&A turn makes none, which is the same polarity law as YOURS/BLOCKED (`wrap-ledger.sh:46-54`).
- D8 needs four things at once: a done-reading verdict, a 12-hex id that is an **open class-C packet**, a recommendation or conviction token on the same line, and none of the cited packets already being this session's. It fired on 0 of 57 status prompts.

**What stays invisible, stated plainly.**
- Research that ends in **unfiled prose rulings** with no packet id. Example: `99b5cd2f` 10-07, "needs 4 rulings … follow-on: none". It fired no store signal (slot F estimates 66–77% of positives look like this).
- Peer-done research that is only referenced ("five decisions in the report", `6defb493`).
- These are covered only by the protocol and template text (A6, A8), not by a detector. The sibling's §6 and exhaustive-drive 2D (85–90) reject prose lexicons, and p2s's precision of 0.33 confirms that rejection here.

## 3. Rung and verdict shape

**Glyph and place: ⛔. It is a sentence variant of the existing top rung, not a new rung.** The order is unchanged: ⛔ > 📤 > 🔧 > 📦 > 🚀 > 👤 > ✅.

Why ⛔:
- By the protocol's own definitions, a sign-off is a decision, and decisions are filed through cc-decide and are the ⛔ rung (slim:160, :189).
- 👤 is for operator-only *steps* filed with `cc-backlog needs`. A value judgment is explicitly not one (slim, Three dispositions).
- ⛔ is the only rung that may legitimately end a turn holding work (slim:103).

Why not a new glyph:
- 11 RUNG-comparison sites outside the ledger, plus the readout's empty-state trap (`operator-readout.sh:1245-1249`).
- The 2026-10-01 ruling already refused a glyph for the scope variant (`wrap-ledger.sh:2629`).

Why not 🔧 for undriven agent work: the >90, non-surface items are driven in the same turn under F2. A ledger 🔧 for "undriven agent implementation" needs a producer, which is the sibling's F17 Drive-state rows (60, below bar). That is left to it.

**Exact text.**

| Line | Text | Source |
|---|---|---|
| 1 (S2 verdict) | `❌ Good to close: no — research done, implementation pending: <N> decision(s) wait on your sign-off — <the first, in plain English>` | the model, from the template (A6) and the rule (A8) |
| 2 (S1 rung), N>1 | `⛔ Research done — <N> decision(s) await your sign-off: cc-decide list --open` | wrap-ledger READOUT (A3), used when ≥1 counted packet is attributed by re-check |
| 2 (S1 rung), N=1 | `⛔ Research done — implementation awaits your sign-off: <what_plain>.` | same |
| 2 (filed by this session, no re-check) | unchanged: `⛔ Blocked — need your call: …` / `⛔ Blocked — N decision(s) need your call: cc-decide list --open` | `wrap-ledger.sh:2505-2511` |
| 3 (act) | `ACT: reply approve or veto for each decision; on approval this session recycles into implementation.` | the model (the `ACT:` shape, `close-shape.sh:238`) |
| readout line 1 | `OPERATOR ▸ ⛔ Research done — 56 decision(s) await your sign-off: cc-decide list --open`. The pile is demoted to its own `◆` lines. 87 columns. | A7 |

Measured in the sandbox (`/tmp/rpic-DESIGN/blk.sh`, which uses the `tests/completion-assert.bats` seams):
- **anti-deference:** `no-tell` for lines 1–3 under a ⛔ ledger (p1), under a ⛔-led close (p2), and under a ✅ ledger (p3).
- **completion-assert:** `ledger-clean` on p3. **It fires `false-done:ledger` on p1 and p2**, which is the defect A1 fixes.

Lexical traps that must stay out of the prescribed wording (slot B §5, measured):
- `awaiting your` trips TELLS.
- `Want me to` trips TELLS.
- `4 decisions need your sign-off.` trips CATEGORY_TELLS.
- `requires your` trips D1.
- `need your approval` exits through GENUINE.

**Interactions.**

| Surface | Behaviour | Edit needed |
|---|---|---|
| ✅ SAFE TO CLOSE (both surfaces) | Withheld mechanically by any non-✅ rung: the header line lives inside the `"✅")` arm (`operator-readout.sh:1338-1355`), and the standalone certificate abstains unless `RUNG=✅` (`:2113`). | none |
| D6 origin contract | Gated RUNG ∈ {✅, 👤}, so it is **off at ⛔**. The close leads with the ⛔ line (S1) and optionally the ❌ verdict. For an **undeclared** research turn (✅, D6 armed by scratch writes), A6's template offers the no-form above, and D8 backstops a yes. | A6 |
| D3 hedge | Before the anchor there is only `❌`, so CA_SETTLED cannot match. There is no `yes`, so CA_YES_HEDGE cannot match. | none |
| D4 offer / anti-deference | A statement plus an `ACT:` line contains no CA_OFFER or TELLS spelling (measured above). It is pinned by bats so that a future lexicon widening cannot silently convict it. | A6 tests |
| ⛔ term in completion-assert (`:1204-1208`) | **Convicts the correct close today.** Its CLOSE gate matches any `done`/`landed`/`✅` anywhere in the message (`:428`, `:467-470`), so "Research done" alone passes the gate. Then `contra=1`. | **A1** |
| Active research program exemption | Keyed on the registry. D8 abstains inside an active program, reusing `_ca_rp_active` (`:1397`). Program sessions use the kit's implementation signature and delegated acceptance, not `recheck`. The E0 program sentence is kept, and `research-program-exemption-rules.bats:36` pins it. | A5, A8 |
| boundary-handoff FREE WIN | Requires `RUNG=✅` (`boundary-handoff.sh:547`), so a declared research-pending session is never told to recycle "with nothing outstanding". | A10, wording only |
| session-continue | Its header contract already says clear the sentinel on ⛔ (`:13-14`). | none |

## 4. Auto-proceed rule: a composition of existing gates

For each implementation item X that research produces:

```
SIGN-OFF (class C ⇒ ⛔) if ANY holds — checked first, never demotable (gate-classify.sh:9-14 asymmetry):
  G2 / F3 surface: auth/session · destructive migration · navigation pattern · DB timeout
                   (CLAUDE.global.md:612; plus the repo's escalation greps, e.g. reso-management-app/CLAUDE.md:543-546)
  cc-decide class-C territory: C10 self-mod · C6 money · permission/credential   (bin/cc-decide:17-19; gate-classify.sh:34)
  manual-command-delivery gate class: irreversible · production-mutating · money-spending ·
                   credential-writing · classifier/permission-refused            (skills/manual-command-delivery/SKILL.md:26-27)
  operator-only external act: third-party contact · publishing · purchase · public repo  (signoff memory, "acts no agent can do")
DRIVE NOW (no packet; class-A trail optional) iff none of the above AND
  F2 conviction > 90  (bin/cc-decide:210-214 refuses to open above 90: "implement it")
  F1 net-positive · F4 bounded · G3 ship via the repo's sanctioned flow · G4 task-clean
DO-UNLESS-VETOED (class B) otherwise, i.e. no surface, but conviction ≤ 90 or a value fork the standing values do not settle:
  default = the recommendation, a deadline, default_effect change|no-change; actuated by
  cc-decide expire-sweep → autonomy-sweep → cc-dispatch (autonomy-sweep.sh:18-24, 1189-1218)
```

**Applied to the incident** (slot H, hand-coded and inferred, `/tmp/rpic-H/tiers.tsv`):
- Drive now: 0 of 59 live decisions. The only one above 90 is `b4373234dd78` (92), and it is an auth surface.
- Reversible and at or below 90: 12 (convictions 62–88), which go to class B.
- The recommendation changes nothing: 10.
- Sign-off: 33.
- The re-check also proved 15 moot and 3 duplicate. Closing those is hygiene inside the envelope (F1–F4, driven at >90 with evidence). The operator expected it: "close them if you havent already" (slot E rec 548).

**Two gaps, as rulings, not new gates.**
- **(B1)** The >90 bar means "reversible and lower stakes ⇒ just do it" never fires for items at 62–88.
- **(B6)** cc-decide **refuses** a class-C open above 90 (`bin/cc-decide:210`) with no surface guard. So a 92% auth change cannot be filed for sign-off, even though G2 requires one.
- **Caveat:** class-B actuation was measured idle (0 workers fired 2026-10-17T21:57Z → 10-19T00:59Z, sibling axis 05). That is unverified now, so treat class B as "safe to queue", not "will happen".

## 5. Sign-off → self-recycle path

**Exists now** (the incident used half of it on `bb7c893b31ba`, slot H §H2).
1. The research turn persists its report durably: a repo `docs/research/<slug>/`, or `~/.claude/autonomy/research/<slug>/`, never `/tmp`.
2. It files each checkpoint item:
   `cc-decide open --class C --what "<plain English>" --conviction N --receipt <report> --option "approve::<what happens>" --option "veto::<what happens>"`
3. The operator replies in the pane.
4. In the reply turn, the agent writes `/tmp/fire-impl-<slug>.txt`: locate line, report path, approved ids with their recommendations, DoD, gates. Then, **as the last act of the turn**:

```
~/.claude/scripts/handoff-fire.sh --recycle --prompt-file /tmp/fire-impl-<slug>.txt \
    --goal '<approved items> landed on origin/main — proven by git ls-tree origin/main -- <paths> printed; do not touch unapproved items; DoD at <report path>'
```

   - Add `--worktree <impl>` to relocate the recycle.
   - For 2+ independent approved items, the existing rule applies (`commands/handoff.md:456-466`): one non-recycle fire per item, `--worktree <slug> --notify-back "${ITERM_SESSION_ID##*:}" --account auto --split-right --goal …`, with the lead keeping the rest.
5. The successor implements, lands through `/ship`, then runs `cc-decide action <id> --evidence <sha>`.

**Preconditions** (hazards, slot H §H2):
- Pass `--goal` explicitly. A terminal or absent goal is not inherited (`handoff-fire.sh:9707-9724`); the incident had 0 `goal_status` records.
- `cc-custody list --open --cwd .` must be empty, because a recycle kills in-process children.
- Do nothing after the fire in that turn (`:5289-5348`).
- No background `cc-await-ping` in the successor while its goal is live (`goal-inert-watch.sh:42-50`).
- The sid changes on recycle, so the successor does not own the re-checked packets. That is correct: the unapproved ones fall back to the operator's standing `◆` pile.

**New in this design:**
- A4: `cc-decide recheck <id> --conviction N --receipt <report> --recommendation "<one line>"`, for packets that already exist.
- A3: the ledger's research-variant ⛔ that it computes from step 2 or A4.
- A6/A8/A9: the close shape and the `/explain-decisions` disposition step.
- Not built (B4): a sign-off given **outside** the pane. cc-decide has no "approved option X" verb (`action` means carried out, `:37`), and no packet change wakes the filing pane.

## 6. Signoff-memory reconciliation

**Verdict: it narrows. Conviction 80%.** I agree with slot H §H3.
- The memory (`feedback-operator-will-not-read-signoffs.md`) says "research programs run zero human in loop via a one-time delegated acceptance", and "never stop a research **program** to ask the operator to 'read and sign'". Its delegation is keyed on `programs.json`: one program, `truememory-2-0`. The incident cwd is not in a program (`research-program.sh is-active` ⇒ rc 1).
- Its object is *reading content*. The checkpoint here is one line per item: the decision as a sentence, a recommendation and a number. He gave exactly that twice in the incident without opening the 126 KB report (rec 492 and rec 523, where he pasted the line and wrote "Yes delete it").
- The memory's own list of acts to keep with him (third parties, money, publishing, public repos) is a subset of §4's sign-off set. The 10-18 "reversible … lower stake, just do it" restates `feedback-autonomous-to-100-boundary.md` ("routine ⇒ drive; money/auth/destructive ⇒ legitimate checkpoint").
- **Residual 20%:** he meant "zero human in loop" universally. Even then the build is identical. The only behaviour that differs is how items at 90% or below with no surface are handled, which is B1. So this needs a ruling (B2), but does not block the build.

## 7. Implementation split

### (a) Low-stakes, reversible: implement now

None of these touches auth/session, a destructive migration, a navigation pattern, a DB timeout or `settings.json`. Each one adds or corrects; A1 is the one narrowing, and it is justified against its own contract below. Run each item's suite with `bats tests/<file>.bats` and assert the `1..N` plan line (a cc-bats deferral is not a result). Shellcheck runs bare, as the land gate does. All of this runs inside the dispatched session.

**A1. The ⛔ term stops convicting a close that answers no.** *(W1, prerequisite for everything below)*
- **File:** `hooks/completion-assert.sh:1204-1208`, plus its comment at `:1199-1203`, which states an assumption the measurement refutes.
- **Behaviour:** when `close_verdict_polarity "$MSG"` = `no` (the lib is loaded at `:991`), or line 1 or line 2 of the close begins with `⛔`, skip `contra=1`. Record it as `ledger-clean:blocked-answered`. Every other ⛔ case is unchanged.
- **Why it is not a weakening:** the term's documented target is "a close asserting done while a decision it filed is open" (`:1202`). A no verdict is not a done-assertion, and verdict-first (D6) already polices a no under a done-reading line 1.
- **Measured:**
  - IDL window 2026-10-18T12:18Z → 10-19T04:06Z: 1,732 completion-assert rows, 23 on ⛔ (11 fired, 12 capped).
  - Of the 6 fires whose *only* fact was "BLOCKED ON YOU", **4 were on "❌ Good to close: no" closes** (6069b9d3 17:59, d7eb73d2 18:01, 9240c6a9 02:41:39, 04:06). The other 2 named the decision without a verdict and still fire after the fix. Script: `/tmp/rpic-DESIGN/blkfires.py`.
  - The 12 capped rows show the term also spends the shared `assert` budget (the sibling's R3).
- **Tests** (`tests/completion-assert.bats`, after `:1250`, `mkledger` seam):
  - `⛔ HONEST NO: a no-verdict research close over a ⛔ ledger ⇒ ABSTAIN ledger-clean:blocked-answered`. Fixture: line 1/2/3 from §3 plus a body containing "landed". **Fails before the fix** (sandbox p1 ⇒ `fired:false-done:ledger`).
  - `⛔ RUNG-LED: a close whose line 1 is the ⛔ readout ⇒ ABSTAIN`. **Fails before the fix** (p2).
  - `⛔ CONTROL: "✅ Good to close: yes — nothing of mine is open" over ⛔ ⇒ FIRE BLOCKED ON YOU`. Passes before and after.
  - The existing `⛔: a confident done-assertion … ⇒ FIRE` (`:1155`) must stay green.

**A2. The ✅ default readout states what it checked.** *(W1)*
- **File:** `scripts/wrap-ledger.sh:2492`. Change `"✅ Complete & live on trunk — nothing to do."` to `"✅ Complete & live on trunk — nothing this session filed is open."`. At `:2998`, change `complete — nothing to do` to `complete — nothing this session filed is open`.
- **Why:** the ledger reads git and this session's filings, not the world. The old tail is the sentence the operator quoted back with "Huh?", and D6 makes agents relay it (`close-shape.sh:309`).
- **Pins:** one exact-string pin exists, `tests/completion-assert.bats:2297`. It is a *literal input* to a done-reading test, so it stays green. `wrap-ledger.bats:2455` greps only `^READOUT=✅`.
- **Tests** (`tests/wrap-ledger.bats`): `✅ default READOUT names its scope` asserts the new string and `! grep 'nothing to do'`. **Fails before the fix.** Also `--full Next row on ✅ reads 'complete — nothing this session filed is open'`.

**A3. The ledger counts re-checked packets as ⛔, words them as research, and exports the foreign open set.** *(W2)*
- **File:** `scripts/wrap-ledger.sh:1483-1524` (`count_blocking_decisions`).
  - Line `:1500`: `$mine` becomes `select(((.session_sid // "") == $sid) or any((.rechecks // [])[]; .sid == $sid))`.
  - A re-checked packet counts as an ask only if *this session's* entry carries a conviction and a receipt.
  - Add a digits-only TSV field `RECHECKED` (asks attributed only by re-check), before the free-text field, keeping the "count FIRST, free text LAST" rule at `:1493-1498`.
  - Add `OPEN_C_FOREIGN_IDS`: space-joined ids of open class-C packets not in `$mine`, from the **same** jq. No extra fork.
- **Readout:** `:2505-2511`. If `RECHECKED>0`, use the §3 research sentences; otherwise the current text, byte for byte.
- **Emit:** append `BLOCKED_RECHECKED=` and `OPEN_C_FOREIGN_IDS=` after `BLOCKED_SRC` (`:2801`). This is outside the positional BUSY lines 10-17.
- **Fail-open:** an unreadable store gives `BLOCKED_SRC=error` and an empty `OPEN_C_FOREIGN_IDS`, as today.
- **Tests** (new `tests/wrap-ledger-recheck.bats`). It uses the `tests/wrap-ledger.bats:10-79` setup, the real `bin/cc-decide list` against `CC_DECISIONS_DIR` fixtures and `WRAP_SESSION_ID`, as slot A's sandbox did:
  - `foreign open class-C packet re-checked by this session ⇒ RUNG=⛔ 'Research done — implementation awaits your sign-off: <what>.'`. **Before the fix this reads ✅**: slot A §4 S1.
  - `two re-checked ⇒ 'Research done — 2 decision(s) await your sign-off: cc-decide list --open'`.
  - `CONTROL re-checked by another session ⇒ RUNG=✅ BLOCKED=0`, the alarm-polarity guard.
  - `CONTROL a re-check entry without conviction or receipt does not count`.
  - `CONTROL filed-by-me wording byte-identical` (slot A's S6 fixture).
  - `OPEN_C_FOREIGN_IDS excludes class B, resolved packets and mine`.
  - `unreadable store ⇒ BLOCKED_SRC=error, OPEN_C_FOREIGN_IDS empty`.
- **Safety:** additive. ⛔ fires only on an explicit stamp by this session (slot D constraint 8: own attribution, not a widened ⛔).

**A4. `cc-decide recheck` verb.** *(W1)*
- **File:** `bin/cc-decide`. Add it to the verbs header at `:21-46`, add a new `cmd_recheck` after `cmd_transition` (`:350-374`), and add the dispatch line at `:531-535`.
- **Usage:** `recheck <id> --conviction N --receipt R [--recommendation r] [--session-sid s]`. It appends `{sid, ts, conviction, receipt, recommendation}` to `.rechecks[]` on an **open** packet via the tmp+mv pattern (`:366-372`), then `log_idl recheck`.
- **Refusals:**
  - a non-open or unknown id (rc 3/2; the file is unchanged)
  - conviction >90, reusing the `:210-214` message ("implement it")
  - a missing or invalid conviction or receipt (`valid_conviction`/`valid_receipt`)
  - an unresolvable sid, using the `:276-279` ladder; an unattributed stamp is worthless
- **Never changes:** status, id, class or any existing field.
- **Tests** (`tests/cc-decide.bats`):
  - `recheck appends an entry and leaves status/id/what untouched` (diff the other keys before and after)
  - `recheck refuses conviction 91 with 'implement it'`
  - `recheck refuses an actioned packet; file byte-identical`
  - `recheck refuses without --conviction or --receipt`
  - `recheck twice appends two entries; list --open --json carries rechecks`
  - `recheck with no resolvable sid is refused`
  - Each refusal case fails before the fix, because the verb is unknown and exits nonzero with a different message, so assert on the message.
- **Safety:** the store is written only by an explicit call, and `open`'s gates are untouched.

**A5. Completion-assert D8, "research results pending under a done close".** *(W2, after A3; inert without A3's field)*
- **File:** `hooks/completion-assert.sh`.
  - New block after D7 (`:1609-1614`). Add `d8` to the abstain disjunction (`:1619-1621`) and the arm label `pending`.
  - CLASS selection (`:1681-1690`): `CLASS=pending`, `COMPLETION_PENDING_MAX` default 2, claimed only when D8 fires alone, as D7 claims `act`. It never shares `assert` or `shape` (the sibling's R3; this session had spent `shape` 2/2).
  - Kill switch `CC_CLOSE_PENDING=0`.
- **Predicate:** `contra_shape=0 ∧ RUNG∈{✅,👤} ∧ ¬_ca_assignee ∧ origin ∧ ¬_ca_rp_active ∧ DONE_READ ∧ |{12-hex ids on lines matching [0-9]{2,3} ?%|recommend|conviction} ∩ lfield OPEN_C_FOREIGN_IDS| ≥ 1`.
  - `DONE_READ` = polarity `yes`, or (`none` ∧ `close_line_reads_done` line 1), or (not no or mixed ∧ `nothing (of mine )?(is )?(left |still )?open|follow.?on:?\s*none`).
  - Ids are read from `MSG`, not `MSG_UNQ`: the incident cites ids inside backticks, and `:514` strips backtick spans.
  - It consumes the ledger's set, so the hook still never reads the store (`:1191-1197`) and adds no fork.
- **Reason text** (no D3/D4 restatement, per `:1717`): "Your close reads done, but it recommends action on N OPEN decision(s) you re-researched (<ids>). Research done is not nothing to do. Implement the ones above 90% that touch no escalation surface now; stamp each other one with `cc-decide recheck <id> --conviction N --receipt <report>` so the rung reads ⛔; then lead with `❌ Good to close: no — research done, implementation pending: …`. Keep the report out of /tmp."
- **Measured:** §2. 3 fires in 1,877 turns, 0 of 57 status prompts, harm in-sample TP 2 / FP 0 / FN 2.
- **Tests** (`tests/completion-assert.bats`, stub ledger with `OPEN_C_FOREIGN_IDS=8daf14ec04b2 bb7c893b31ba`):
  - `D8: incident-shaped yes close citing two open foreign ids with % over ✅ ⇒ FIRE arm=pending class=pending`. **Before the fix it abstains `ledger-clean`** (slot B replay c0).
  - `CONTROL ids not in OPEN_C_FOREIGN_IDS ⇒ ABSTAIN`
  - `CONTROL the §3 no-verdict close ⇒ ABSTAIN`
  - `CONTROL ids on lines without a recommendation token ⇒ ABSTAIN`
  - `CC_CLOSE_PENDING=0 ⇒ ABSTAIN`
  - `cap: 2 fires then capped:pending:2>=2, assert count unchanged`
  - `active research program cwd ⇒ ABSTAIN`
- **Known limit:** completion-assert can time out on the Stop (5,337 ms on the incident's final Stop). D8 adds no fork, but a cancelled run loses it. The rung path in A3/A7 does not depend on this hook.

**A6. The template offers the research-pending no form.** *(W1)*
- **File:** `hooks/lib/close-shape.sh`.
  - `:179`: the no-branch placeholder `no — <what remains + who owns it>` becomes `no — <what remains + who owns it; research whose results wait on a decision or an implementation is not done: research done, implementation pending: <N> decision(s) wait on your sign-off — <the first, in plain English>>`. It is still a `<…>` placeholder, so the `real()` guard at `:88-94` holds. The yes branch is **untouched**: the sibling's F2 owns it, and 9 test lines pin it.
  - `:309`: after "naming what the work was." insert " The ledger reads git and this session's filings only: research that left decisions or an implementation pending answers no." It stays single-quoted, with no backticks and with `%%` rules kept.
- **Tests:**
  - `tests/completion-assert.bats`: `close_shape_template carries 'research done, implementation pending'`. **Fails before the fix.**
  - `CONTROL close_shape_ok "$(close_shape_template)" still rc 1`.
  - `the §3 line 1 has polarity no and does not read done`.
  - `tests/anti-deference-nudge.bats`: `the §3 research-pending close (lines 1-3) ⇒ abstained no-tell`. Measured no-tell (p1–p3). This pins the wording against future TELLS growth.

**A7. Operator-readout ⛔ arm, answer-first.** *(W1)*
- **File:** `hooks/operator-readout.sh`.
  - `:1236`: add `"⛔") state="$(lf READOUT)"`, truncated so the header stays ≤100 columns (`:1596-1598`).
  - `:1446`: the fire predicate also fires on `RUNG=⛔`.
  - `:1513-1516`: on ⛔, `hdr="OPERATOR ▸ ${state}${_y:+ · $_y}"`, mirroring the certified reorder. Add ⛔ to the `📦/🚀` header branch. The pile keeps its own `◆` lines.
- **Tests** (`tests/operator-readout.bats`, slot C's sandbox scenario B):
  - `⛔: line 1 = 'OPERATOR ▸ ⛔ …' and the pile partition is not on line 1`. **Before the fix: `OPERATOR ▸ 4 need your call`** (measured, slot C §5).
  - `⛔ with an empty pile still renders the block`. Before the fix it is silent.
  - `CONTROL ⛔ never renders SAFE TO CLOSE`.
  - `header ≤100 cols with a 300-char what_plain`.
  - The existing 📦/🚀/🔧/✅ tests stay green.

**A8. Protocol text, net non-positive on the budgeted tier.** *(W3, after A4)*
- **Budget:** the user tier measures `61,104 > 60,000` and enforcement is `true` (`bin/cc-instruction-budget assert` / `enforce`, run this session). So the rules file is one-in-one-out. `CLAUDE.global.md` is not budgeted (`config/instruction-budget.json:14`). `CLAUDE.global.slim.md` carries no close-protocol text (grep for E0 or read-only finds only unrelated lines), so it needs **no edit**; say so in the commit.
- **Edits to `CLAUDE.rules.slim.10-session-close.md`** (measured UTF-16 delta **−1**, python over this tree):
  - `:34`: `| Read-only / advisory / research (no tracked writes) | … Work the turn itself named is not exempt (see E0 below). |` becomes `| Read-only / advisory (no tracked writes) | No ledger, no auto-continue, no readout. Research that names work is not exempt (see E0 below). |` (−13).
  - `:99`: replace "A read-only turn that names drivable work is not E0: run the Follow-On Gate on each item and drive the passes (here, in a subagent, in a team, or in a fired session) before yielding." with "A turn whose research names work is not E0: drive its Follow-On Gate passes (here, a subagent, a team or a fired session), file the rest (`cc-decide open`; `cc-decide recheck <id>` for a re-researched packet) so the rung reads `⛔`, and lead with `❌ Good to close: no — research done, implementation pending: …`." (+129). Keep the program sentence; it is pinned.
  - Cut `:160` " (an unattended ask whose default fires at its deadline)" (−57; cc-decide's help defines class B).
  - Cut `:189` " The counted `◆` line still owns the machine's standing pile." (−61; restated at `:156`).
  - **Do not cut `:146`/`:156`.** Those are the sibling's F1; coordinate with branch `cc-004752-67086`.
- **Mirror in `CLAUDE.global.md`:** the disposition row at `:601` and the `_E0_` row at `:721`, with the same content in full-variant style. Keep `answered by relaying the certificate`.
- **Tests:**
  - New `tests/close-research-pending-rules.bats`: both variants' E0 contain `research done, implementation pending` and `cc-decide recheck`; the slim row at `:34` no longer contains `/ research (no tracked writes)`. **Fails before the fix.**
  - `tests/research-program-exemption-rules.bats` stays green.
  - `bin/cc-instruction-budget range origin/main..HEAD` ⇒ rc 0.

**A9. `/explain-decisions` gets its disposition step.** *(W3, after A4)*
- **File:** `commands/explain-decisions.md`. After the itemize sentence, add:
  1. Write the report to a durable path (repo `docs/research/<slug>/` or `~/.claude/autonomy/research/<slug>/`), never `/tmp`.
  2. Close every packet the re-check proves settled or duplicate at >90%: `cc-decide action <id> --evidence "<why>"`.
  3. Implement each recommendation above 90% that touches no escalation surface.
  4. Stamp every remaining one with `cc-decide recheck <id> --conviction N --receipt <report> --recommendation "<one line>"`.
  5. Close with the §3 lines 1–3.
- **Tests:** new `tests/explain-decisions-command.bats`. It greps for `cc-decide recheck`, `never /tmp` and `research done, implementation pending`. **Fails before the fix.** No test references this command today.

**A10. FREE WIN stops claiming what it did not check.** *(W1)*
- **File:** `hooks/boundary-handoff.sh:847`. Change "no operator step outstanding" to "no operator step filed by this session".
- **Test:** extend the existing free-win case in `tests/boundary-handoff.bats` to assert the new phrase and the absence of the old one. **Fails before the fix.** No test pins the old phrase.

**A11 (optional, after A3). Name session-owned decisions in the readout.**
- **What:** split decisions with `session_sid==$sid` or `rechecks[].sid==$sid` out of the pile, into itemized lines that are never collapsed: `◆ [this session] <what_plain> — <recommendation> <conviction>%   cc-decide show <id>`. This mirrors the `yours` split for backlog rows (`operator-readout.sh:1125`, `:1526-1550`), in the same jq (`:1015-1060`).
- **Tests:** an own packet is itemized and excluded from `◆ N decisions`; a foreign packet stays in the pile.

### (b) Needs an operator ruling

Each item is filed as `cc-decide open --class C` with the conviction and receipt given. Options are written as `label::outcome`.

**B1. Should a reversible change that touches no escalation surface be implemented without asking when my conviction is 62–88%?**
- Example: writing the kitty shortcut into the tracked example config, at 85%.
- **Conviction 65%** for "keep the bar, queue as do-unless-vetoed".
- **Receipt:** `docs/research/research-pending-implementation-close-2026-10-18/slot-H-gates-recycle.md` §H1 and `/tmp/rpic-H/tiers.tsv` (12 such items in the incident).
- **Options:**
  - `keep the 90% bar::each becomes a do-unless-vetoed packet whose default fires at its deadline; the dispatcher that fires it was measured idle for 27 hours on 10-17/18`
  - `lower to 80% for reversible items with a rollback one-liner::7 of the 12 incident items would have been done at once, and you read the trail afterwards`
  - `sign-off for everything at 90% or below::status quo; all 12 wait for you`

**B2. Does your 2026-10-16 "zero human in loop" apply outside registered research programs?**
- **Conviction 80%** for "it narrows".
- **Receipt:** §6 of this file; `feedback-operator-will-not-read-signoffs.md`; `research-program.sh is-active <incident cwd>` ⇒ rc 1.
- **Options:**
  - `narrows::outside programs, only research results touching money, auth, third parties, publishing, self-modification or production get a one-line yes/no; the memory gains one scope line`
  - `universal::no sign-off anywhere; every result is driven or queued do-unless-vetoed, and ⛔ is kept for acts no agent can do`

**B3. Should "Complete" require a scope this session actually wrote?**
- Today a DoD file that holds only other sessions' blocks with zero checkboxes reads "met".
- **Conviction 55%** for changing it.
- **Receipt:** slot-A §3 (74 of 78 DoD files show no boxes in that view); the sibling's F19 (55).
- **Options:**
  - `make it unknown::most closes read 'completeness UNKNOWN' and the SAFE TO CLOSE certificate becomes rare`
  - `leave it::the vacuous 'met' stays; A2's wording already says what was checked`

**B4. Should a sign-off you give outside the pane wake the session that filed it so it recycles into implementation?**
- Examples: cc-decide in your terminal, or another device.
- **Conviction 70%** for building it.
- **Receipt:** slot-H §H2 carrier table.
- **Options:**
  - `build it::a 'cc-decide answer <id> --option <label>' verb plus a sweep that messages the filing pane; it touches live sessions`
  - `in-pane replies only::you answer in the session and it recycles on your reply; nothing new is built`

**B5. After sign-off, should the implementation recycle the research pane, or get its own session per approved item?**
- **Conviction 85%** for the existing rule.
- **Receipt:** `commands/handoff.md:456-466`; incident recs 492 and 566.
- **Options:**
  - `existing rule::one approved track recycles this pane; two or more independent items get one dispatched session each and the lead keeps the rest`
  - `always recycle::one implementation session per research turn; approved items run one after another`

**B6. May a decision above 90% still be filed for your sign-off when it touches auth, money, a destructive migration or production?**
- cc-decide refuses any open above 90% (`bin/cc-decide:210`), so `b4373234dd78` (92%, auth) cannot be filed, even though the escalation rule says to stop and ask.
- **Conviction 85%** for "yes, with a named surface".
- **Receipt:** `bin/cc-decide:206-214`; slot-H §H1 "Gap the rule exposes".
- **Options:**
  - `yes with a named surface::class C accepts a conviction above 90 only with --surface auth|money|migration|production|third-party, and the ledger shows ⛔`
  - `no::above 90% the agent implements even on those surfaces, and the prose escalation rule is the only gate`

## 8. Considered and not proposed

- **Narrowing D6's write gate to tracked writes in the cwd** (`completion-assert.sh:1513` → the certificate's oracle). This would reverse decision P8 (`close-verdict-first-2026-10-10/skeptic-operator-intent.md:178-187`). With A6, D6 firing on a research turn becomes useful: it demands a verdict, and that verdict can now honestly be no. Kept as is.
- **Prose or lexicon detectors** (p2s at P 0.33; s3 at 0.17), a store-or-silence terminal gate (about a 1:1 nag), or a new arm in the `assert` class. The sibling's §6 and exhaustive-drive 2D reject these, and this synthesis does not override those rejections.
- **An umbrella packet** ("approve the 56 recommendations in REPORT.md") as a no-code route. It forces reading the report, which the signoff memory refuses, and it duplicates 56 existing packets. A per-item re-check stamp has neither problem.

**Side findings for the orchestrator.** These are outside this design, drivable, and owned elsewhere.
- completion-assert's kill-switch envelope filter does not list `<agent-message`, so a peer's "and stop" would disarm it (slot B §2).
- The research-precognition regex fires on `Another Claude session sent a message` hand-backs (slot E §3).
- anti-deference reads the previous assistant text (4/4 replayed stops; the sibling's F10).
- A subagent read a Keychain secret (g06, slot E §2).
- `commands/handoff.md:314-315` documents goal inheritance that the code no longer has (slot H).

**Evidence index.**
- Scripts: `/tmp/rpic-DESIGN/d8.py` and `d8c.py` (D8 census replay) and `d8c_fires.txt`; `blk.sh` (hook sandbox, `tests/completion-assert.bats` seams); `blkfires.py` (the ⛔ fires in the IDL window and their closes).
- Upstream data: `/tmp/rpic-G/{sig.jsonl,labels.tsv,sample.json}` and `/tmp/rpic-H/tiers.tsv`.
