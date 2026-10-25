# Critique: D1-rule-text, through the constraints-feasibility lens

Design: `docs/research/lead-keeps-working-2026-10-24/designs/D1-rule-text.md` (D1 below).
Worktree `lead-idle-fix` at `b6b53ea89`. Labels follow D1: `R` = `CLAUDE.rules.slim.10-session-close.md`,
`S` = `CLAUDE.global.slim.md`, `G` = `CLAUDE.global.md`, `TX:n` = line n of the B13 transcript.
Everything here was read-only. This file is the only write. Each number says whether it was
measured (with the command) or estimated (with the method).

**Verdict: sound-with-fixes. Score 6/10.**

D1 meets the hard constraints as written: no settings edit, no hook registration, no new file to
deploy. Its budget arithmetic reproduces exactly. Its grep pins are red without the change.

Three findings break claims D1 makes about itself:
1. **The standing grant (goal d) cannot be acted on without a settings edit.** The auto-mode
   classifier refused the Codex call twice, even after the operator had spoken. The text grant is
   weaker evidence than those words.
2. **R-10 mutes two existing surfaces.** It asks a loop-scope lead to keep its continuation armed.
   An armed lead gets no boundary-handoff advice, including the 73% context boundary, and no
   operator readout, for the whole life of the loop. Auto-compact is off. D1 §1.3 says "No other
   gate weakens".
3. **No test can go red on the incident's behaviour.** The red tests check only that sentences
   exist.

---

## 1. Hard-constraint checklist

| Constraint | Result | Evidence |
|---|---|---|
| No settings-file edit | **Met by D1's own diff. Not met by goal (d)'s effect** (defect 1) | D1 §7. Codex refused at TX:4640 and TX:4678; the classifier's trust context lives in `~/.claude/settings.json` `.autoMode.environment` |
| No new hook registration | Met | D1 changes no hook (§7) |
| Never weaken an existing gate | **Not fully met** (defects 2, 4, 5) | `hooks/boundary-handoff.sh:694`, `hooks/operator-readout.sh:2257`, S-9, `scripts/wrap-ledger.sh:924-945` |
| Instruction budget | Met: net −4 (measured, reproduced). Still 1,070 over the 60,000 user tier | §3 below |
| Deploy path | Met: existing copy legs, no new file, live at the next converge | `install.sh:1080-1087` (G → CLAUDE.full.md), `:1113-1131` (R → rules/), `:1132-1139` (S → CLAUDE.md) |
| Testability (red without the change) | Grep pins yes. Behaviour no (defect 3) | D1 §9: T7, T9 and T11 are green in both arms by design |
| Files and LOC (more than 6 files needs teammates) | 5 files, about 330-360 LOC (estimated, §5). No teammates needed. Grafting the cheap machine-text fixes (defect 6) makes it 7 | — |
| Loop risk | No new block arm. Existing bounds hold | `hooks/session-continue.sh:1445-1458` (cap), `:1371-1442` (idle re-block skip) |

---

## 2. Defects

### D-1 (major): the standing grant cannot be acted on, and will create new class-C asks in every repo

The S-1 grant says "in any repo, unasked, add non-Claude reviewers … via `codex exec -s read-only`".
D1's replay (§6.1, row 1) says that under S-1 there is "No packet; wire a Codex reviewer into
round 27", and "S-1 alone removes decision 2".

The transcript disproves this.
- The operator's own words came at 18:11:47Z (TX:4488).
- At 18:16:22Z the lead's command note cited the agentsync memory grant.
- The auto-mode classifier still refused the Codex export twice: "Permission for this action was
  denied by the Claude Code auto mode classifier. Reason: [Data Exfiltration]". That was at
  TX:4640 (18:16:33Z) and TX:4678 (18:17:21Z). Measured:
  `grep -n 'auto mode classifier. Reason: \[Data Exfiltration\]'` returns those 2 lines.
- The lead then asked for an allow rule (TX:4683). This is D1's own control C3.

What would let the call through lives in settings, which the brief forbids touching:
- `~/.claude/settings.json` is in `defaultMode: auto` (measured, `jq`).
- `.permissions.allow` has 371 rules and none matches `codex`, `xverify` or `openai` (measured,
  `jq | grep`).
- The classifier's trust context is `.autoMode.environment`. It already carries the precedent: the
  kitty-pane standing ruling of 2026-10-01 is written there, not in CLAUDE.md. `.autoMode.soft_deny`
  lists "Data Exfiltration" and "Trusting Guessed External Services".

So a lead that obeys S-1 will be denied. R-7 then routes "a permission denial" to class C, which
gives a new ⛔ packet for every repo that tries. S-1 does not remove decision 2. It moves it into
every repo in a new form.

D1's own citation points at the lever. Ruling `29d62f1ad390` (cited in G-3) has a second half that
D1 drops: "Permission prompts are virtually always a yes, so improve the allowlist/config so past
command usage is pattern-recognized and allowed" (measured, `jq -r .evidence`).

**Fix:**
- S-1 and G-9 state the prerequisite plainly. The grant becomes actionable once the operator adds
  an `autoMode.environment` line (or an allow rule) for Codex-plan review of `git archive` exports.
  That is a self-modification of settings, class C10, outside this design's constraints.
- File that as ONE operator step, not one per repo.
- On a classifier denial: continue Claude-only, cite that one packet, and file nothing new.
- G-3 quotes `29d62f1ad390` in full.

### D-2 (major): R-10's arming mutes boundary-handoff (73% included) and operator-readout for the whole loop

R-10 and G-7 tell the lead to arm `session-continue.sh set` on a ⛔ or ✅ ledger over ungated work,
"an open loop scope" included. A loop scope stays ungated for its whole life. B13's ran 33 rounds
over three days.

While the sentinel exists, two existing surfaces abstain outright:
- **boundary-handoff.** The compose guard abstains `continue-hook-armed` at
  `hooks/boundary-handoff.sh:694`. Only the below-threshold exit comes before it (`:673`), so every
  path that would advise is muted: free-win and the ≥73% context boundary (`T=73`, `:154`). D1 §5
  L3 notes only the free-win abstain.
- **operator-readout.** It abstains `continue-armed` at `hooks/operator-readout.sh:2257`, so the
  operator's close block never renders while the loop runs.
- **Nothing else bounds context.** `autoCompactEnabled` is `false` (measured, `jq`), and the armed
  path in session-continue has no fill check (`hooks/session-continue.sh:1334-1547`, grep for
  `used_pct|fill` finds none).

This already happens to armed sessions. 15 `continue-hook-armed` rows sit in the IDL archives, for
example sid 6c3d4b86 on 2026-10-14 (measured: `zcat -f idl.jsonl*.gz | grep -c continue-hook-armed`).

B13 itself crossed the boundary while not armed:
- `past-boundary` fired at 20:21:44Z and 21:23:57Z, at 767k-782k tokens (measured, IDL `tok_k`).
- Under D1 it would have been armed, and those advisories would have been muted.

D1 therefore turns states in which the boundary gate runs today into states in which it abstains.
That contradicts §1.3 "No other gate weakens".

**Fix (text, inside D1):** R-10 and G-7 add "at the 73% boundary, or idle at 35% or more (S:166),
clear and recycle or `/handoff` — an armed chain never outlives the boundary". The code designs
should give the armed path a fill check, or let the compose guard yield only below T.

### D-3 (major): testability — nothing turns red on the incident's behaviour

D1's tests:
- The red tests are text pins only: T1-T6, T8, T10 and T12-T14.
- T7, T9 and T11 are green in both arms by design (D1 §9). In this repo's terms that is an
  equivalence guard, not a proof the change does anything
  (`docs/lessons/green-in-both-arms-is-an-equivalence-guard-not-a-red-proof.md`, cited at
  `maps/test-infra.md` §6).
- The only check of D1's effect is T-E, a headless replay. It needs operator go-ahead and quota,
  and D1 gives no cost.

Estimated T-E cost: B13's context was 640-780k tokens over the idle (IDL `tok_k`). So each replay of
the prefix through TX:4253 costs about 0.6M input tokens. N=10 per arm comes to about 12M tokens
(estimated: 2 × N × 0.6M).

Goal (e) asks the close stack to *refuse*. D1 has no refusal, so no bats test can pin one. A land
can go green on sentences alone.

**Fix:** treat D1 as the text half of a combined design. The ⛔-floor and `LOOP_OPEN` tests must
carry the red-without-change proof. Cost T-E before asking for it.

### D-4 (minor): S-9 cuts a money-path condition, not a rationale

The sentence today is "Fable's cost is quota, not dollars (the fleet has no dollar exposure **while**
`accounts.json` has `spend.usage_credits_authorized=false` and `frontier.credits_authorized=false`)"
(`S:141`).
- S-9 deletes the "while" clause. The claim then stands unconditionally in always-loaded text.
- The flags are false today (measured, `jq` over `~/.claude/accounts.json`), so nothing changes now.
- If the operator flips them, every session still reads "not dollars".
- D1 §4.3 says each S cut "removes only rationale". This one is a validity condition on the money
  path, which the brief names as a genuine gate.

S-6 has the same problem on a smaller scale. It cuts "re-measure before quoting", which is an
instruction (`S:141`).

**Fix:** keep a short condition, "(while both `credits_authorized` flags in `accounts.json` are
false)", about 70 units. Drop the S-6 cut.

### D-5 (minor): R-2's intake `dod-persist.sh set` widens cross-session leaks into the drain floor

The mechanism:
- `DOD_SCOPE` is the newest `Scope (frozen):` line in the store filtered by **toplevel**, not by
  session (`scripts/wrap-ledger.sh:924-928`).
- `DRAIN_SCOPE` comes from it (`:945`) and drives `CLOSE_FLOOR` (`:1490-1500`).
- completion-assert treats `CLOSE_FLOOR` as a contradiction of a done-claim
  (`hooks/completion-assert.sh:1142-1144`). Only confirmed assignees are carved out.

The channel is already live:
- 17 of 56 toplevels in the store hold captures from more than one session (measured: awk over
  `^## … toplevel= · session=` headers in `~/.claude/autonomy/dod/*.md`).
- 361 of 362 captures are `manual-set` (measured).

R-2 adds a `set` at every intake. A sibling's "drain the backlog" scope can then switch on a false
floor for this session, or a later non-drain `set` can switch off a real floor. D1 §5 says "Nothing
new can block a Stop".

**Fix:** state the crosstalk in R-2 and G-1. Add "persist from your own worktree (S:147)". Hand
session-scoping of `DOD_SCOPE` to the `LOOP_OPEN` code design, which needs it anyway
(`maps/wrap-ledger.md` §2.5).

### D-6 (minor): machine text that contradicts the new rule is left in place, though some is free to fix

Each string below is fed back to the model while R-6's precedence sentence asks it to read them
differently. A block reason arrives as the next turn on every forced turn.

| String | Where | Pinned by a test? |
|---|---|---|
| "When done (✅/📦), blocked on the user (⛔) … clear" | `hooks/session-continue.sh:1368` | No (measured, `grep -rlF` over `tests/`) |
| `cc-decide open --class C --what` | `hooks/dispatch-assert.sh:237`, `:269` | No (measured) |
| "set … # ONLY on 🔧" and "clear # on ✅/📦/⛔/📤" | `hooks/lib/why-tier.sh:268-269` | Not checked. **Missing from D1 §3.4** |

Editing the first two is text-only and carries no loop risk. The cost is +2 files (7 in total, so
teammates by the brief's rule) and a 23-suite smoke selection for session-continue
(`maps/test-infra.md` §2.3).

**Fix:** graft the session-continue and dispatch-assert strings into the first code change. Add
why-tier to D1 §3.4.

### D-7 (minor): R-6's mandatory self-wake timer has no back-off in the loaded text, and no all-gated exemption

R-6 requires a `cc-await-ping` timer whenever a decision the session filed is open. That includes
class B packets whose deadlines can be days away, and legitimate all-gated stops.
- The doubling back-off is in G only, which no session loads.
- The default timeout is 1800 s (`bin/cc-await-ping:38`), so a 10-hour wait costs about 20 wakes.
- At B13's size each wake past the prompt-cache TTL re-reads about 0.65M tokens: about 13M input
  tokens for the episode. With doubling it is about 4 wakes, about 2.6M (estimated: wakes ×
  `tok_k`).
- S:166 already says recycle when idle at 35% or more, which is cheaper.

**Fix:** move "double `--timeout` after an empty wake" into R (about 40 units). Exempt an all-gated
⛔ in favour of the S:166 recycle.

### D-8 (minor): the R-1 cut narrows a pointer for Stop-hook authors

Old R:4 says: "Before writing or debugging a Stop hook, read … which hook output fields reach the
model and which extend the turn". R-11 replaces it with "before changing, disputing or hooking a rule
here". A Stop hook unrelated to a close rule loses its pointer. The follow-on code designs are all
Stop-hook edits. **Fix:** keep "or writing or debugging a Stop hook" in R-11 (about 30 units).

### D-9 (minor): the edited rule text still disagrees with itself

- R:92 says "⛔ Blocked: a decision or information is needed".
- R:99 says E0 files "so the rung is `⛔`".
- Both stand next to R-7's "Only class C … makes the `⛔` rung".
- R-7 also puts "a credential" in class C, while R:184 and R:186 route credentials to
  `cc-backlog … needs-credential` (👤).

Under class-B routing, a write turn that copies R:92 instead of the ledger glyph earns a D6
`line-1-rung` shape demand (`hooks/completion-assert.sh:1587-1590`). That is bounded by the shape
cap of 2 and is the correct demand. But it is avoidable noise.

---

## 3. Budget, re-measured (not taken from D1)

- **Current units.** `python3 -I hooks/lib/instruction_budget.py measure …` gives S 28,503, R 30,287,
  G 116,486 and the mission board 2,284. That matches `maps/rules-text.md` §6.
- **After D1.** A read-only `python3 -I -c` pass parsed D1's 33 `old`/`new` block pairs. Every old
  text occurs exactly once. Applying them in memory with `instruction_budget.parse(...).units` gives:
  R +393, S −397, G +9,101; S+R 58,790 → 58,786 (−4); user tier 61,074 → 61,070; added text +1,642;
  cuts −1,646. **D1 §4.2 reproduces exactly.**
- **Where the cuts come from.** 945 of the 1,646 cut units (57%) come from sections outside the ruling
  (S-2 246, S-4 99, S-5…S-11 600; arithmetic over D1 §4.2). Dropping D-4's two cuts and adding the
  D-2, D-7 and D-8 text puts the pair about +340 over net-zero (estimated: 140 + 77 + 40 + 30 + about
  50 for the D-2 clause). That must be paid from other duplicated text, or accepted against a tier
  that is already over.
- **What the land gate enforces.** Only the 40k per-file cap. Repo-side S and R classify as tier
  `source`, and `judge` skips it (`hooks/lib/instruction_budget.py:474-480`, `:647-651`). Net-zero is
  policy (`config/instruction-budget.json` `destinations.user`), not a gate. D1 §4.2 says this
  correctly.
- **G's growth matters only under `global full`.** That variant deploys G as `~/.claude/CLAUDE.md`
  (`install.sh:1105-1111`). The live registry is empty, so slim applies (`maps/rules-text.md` §1).

---

## 4. Testability detail

- **Selection.** The new suite names R, S and G literally in executable text, so
  `gate-select.sh --direct` picks it up (`maps/test-infra.md` §2.2). It needs
  `export HOME=$BATS_TEST_TMPDIR/home` in `setup()` (hermeticity rule 1,
  `scripts/test-hermeticity-lint.sh:18-20`).
- **Existing pins survive the edits.**
  - `tests/research-program-exemption-rules.bats:34` needs the F2 bullet to keep "timebox receipt
    satisfies". R-4 and R-5 leave that sentence untouched.
  - `tests/close-research-pending-rules.bats` pins E0, and D1 leaves E0 alone.
  - `tests/cc-memory-search.bats:245-246` pins S:47, which is untouched.
  - `tests/wrap-ledger.bats:2099` pins the G ladder, which is untouched.
  - No test pins a string D1 deletes from S, R or G (measured: `grep -rlF` over
    `tests scripts hooks bin` for each deleted phrase; every hit was the subject code's own copy,
    not a read of the rule files).
- **T9's fixture works.** `dod_path_for` returns `WRAP_DOD_FILE` first (`hooks/lib/dod-path.sh:267`).
  A multi-line `set` holding `Scope (frozen):` is stored unprefixed (`hooks/dod-persist.sh:487`), and
  the dedup compares a whole multi-line scope with a single line, so it appends.
- **T11 pins nothing that could move.** The armed path reads no ledger, so its `RUNG=⛔` stub is never
  read. The test is true, but it cannot detect a regression in anything D1 changes.

## 5. Size (estimated)

| File | Change | LOC (estimated) |
|---|---|---|
| R | 13 single-line edits | about 13 |
| S | 11 edits plus a 4-line section | about 16 |
| G | 9 edits, +9,101 units at about 105 characters a line | about +85 / −20 |
| `tests/lead-keeps-working-rules.bats` (new) | 14 tests | about 200 |
| `tests/session-continue.bats` | T11 | about 15 |

Total: 5 files, about 330-360 LOC. That is under the brief's 6-file threshold. The D-6 graft makes
it 7.

---

## 6. Best ideas worth grafting into the final design

1. **The gating definition.** "A decision gates only the act it asks about and work built on its
   answer, never what the frozen scope directs (a loop's next round too)." It needs no packet field,
   and a ⛔ floor in code can use the same predicate.
2. **Class-B filing template.** `--default "<status quo>" --deadline --default-effect no-change
   --project`. It removes the false ⛔ at its source with no code change. The ledger already ignores
   class B (`scripts/wrap-ledger.sh:47-49`, pinned at `tests/wrap-ledger.bats:1873-1889`), and
   `no-change` files nothing when the default fires (`scripts/autonomy-sweep.sh:576`).
3. **Ruling search before asking.** It names the plan log, `cc-memory-search --all` and
   `cc-decide list --all --json`, and it treats an `expired-actioned` class-B default as a ruling by
   silence. That last point would have caught `eb3dbe1e5e94` (measured: class B, expired-actioned
   2026-10-15).
4. **Reusing an existing actuator.** The rung-blind armed path of session-continue serves as the
   ⛔-with-ungated-work actuator with no new hook (`hooks/session-continue.sh:1334` onward reads no
   rung, verified). It needs D-2's boundary clause.
5. **No `- [ ]` box for a loop scope.** This avoids an alarm that never clears, and T9's
   append-only proof shows why.
6. **Persist the scope at intake (R-2).** `LOOP_OPEN` stays blind to the B13 shape until this
   happens. It needs D-5's caveat.
7. **Budget method.** Apply the blocks in memory and measure with the repo's own
   `instruction_budget.parse`, paying one-in-one-out.
8. **The grant's structure.** Envelope, how to check each limit, "still ask first", and "not a
   routing change" kept apart from `CODEX_ADVERSARIAL_SLOT_PROBE.md`'s "uncertified means unrouted".
   It needs D-1's prerequisite line.
9. **The §3.4 inventory** of machine strings that contradict the rules, for the code designs, with
   why-tier added.

## 7. What I ran (all read-only)

- `jq` over `~/.claude/settings.json`: permissions, `autoMode`, `autoCompactEnabled`.
- `jq` over `~/.claude/accounts.json` and over four decision packets.
- `grep`/`sed`/`jq` over the B13 transcript (TX:4488, TX:4636-4641, TX:4675-4683).
- `grep`/`zcat`/`jq` over `~/.claude/autonomy/idl.jsonl*` and `~/.claude/autonomy/dod/*.md`.
- `python3 -I hooks/lib/instruction_budget.py measure`, and an inline `python3 -I -c` block-apply
  that wrote nothing.
- `sed -n`/`grep` over the hooks, scripts, bin and tests cited above.

No deviations from the brief.
