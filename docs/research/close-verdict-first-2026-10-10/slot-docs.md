# CLOSE_VERDICT_FIRST: slot docs, question (e)

Slot: docs inventory and exact replacement text for candidates B and C. Read-only on tracked files. Every draft below was applied to scratch copies (`/tmp/cvf-docs/{B,C}/`) by `/tmp/cvf-docs/tools/apply.py`. That script asserts each OLD string occurs exactly once in the current worktree, and all 31 do. The patched copies were then checked as described in § 5.

## 0. Candidate definitions as drafted

- B, conditional swap. A yes close keeps today's shape: line 1 is the READOUT rung line and line 2 is `Good to close: yes — …`. A no close swaps the two lines: line 1 is `Good to close: no — <what remains + who owns it>` and the rung line drops to line 2. Rationale: both READOUTs D6 applies to read as done (`✅ Complete & live on trunk — nothing to do.`, `👤 My side is done & landed — …`; source `scripts/wrap-ledger.sh:2277,2408-2441`). So "forbid a done-reading line 1 when the verdict is no" cannot be met while the rung glyph stays on line 1. The rung has to move.
- C, verdict-first with the verdict's own glyph. Line 1 is always the verdict: `<rung glyph> Good to close: yes — …` or `❌ Good to close: no — …`. Line 2 is the READOUT rung line. Slot names S1 and S2 are kept and only their line positions change, so references like "S2's `follow-on:` clause" and "S1's ⛔ rung" stay valid. That also keeps the edit count low.
- Both keep the literal substring `Good to close: yes` / `Good to close: no`. This is load-bearing. `bin/cc-pane-close:99` (`re.compile(r"Good to close: (yes|no)")`, gate 3, which auto-closes husk panes) and `hooks/lead-crash-watchdog.sh:1382` (`pane_last_close`) both parse it from the last assistant text. A form like `❌ Not good to close —` would read as `-` in both. That fails closed, but it silently ends auto-close on these panes.

## 1. Inventory: every place that states or depends on line 1 = rung, verdict on line 2, `Good to close` placement, or the close template

Found by grep over the paths in the brief, plus `core/`, `hooks/lib/why-tier.sh`, `bin/cc-pane-close`, `hooks/lead-crash-watchdog.sh` and `scripts/measure-closes.py`, which the grep surfaced. "Edit" refers to the passage ids in § 4.

| File:line | What it states or depends on | Edit |
|---|---|---|
| `CLAUDE.rules.slim.10-session-close.md:22` | Origin close contract: rung glyph on line 1 (`line-1-rung`), verdict on line 2 | R1 |
| `…10-session-close.md:129-140` | six-slot heading "in this order"; table rows S1 = line 1, S2 = line 2 | R2 |
| `…10-session-close.md:142` | "which is why the verdict sits on line 2" (CC_ACT_WINDOW=3) | R3 |
| `…10-session-close.md:146` | "Line 1 carries one rung …; stays out of line 1" | R4 |
| `…10-session-close.md:148` | S2 "on line 2 and never as the last line"; certificate does not replace it | R5 (+O1 offset) |
| `…10-session-close.md:8` | close certificate `✅ SAFE TO CLOSE`, computed from git | none; R5 states that the verdict takes precedence |
| `…10-session-close.md:86` | close question answers `Good to close: no` | none; pinned by `tests/research-program-exemption-rules.bats:35` and still true |
| `…10-session-close.md:90` | readout "as slot S1 describes"; priority ladder line | none; the ladder is pinned by `tests/wrap-ledger.bats` parity for the full text and `/wrap` |
| `…10-session-close.md:144,150` | S1 relay rule (no line number given); S3 "third, … never welded into line 1" | none; still true under B and C |
| `CLAUDE.global.slim.md` | no close-placement text (only `:22` points at Ship policy) | none |
| `CLAUDE.global.md:516-521` | certificate "verdict FIRST … the one line the model cannot fake" | G0 |
| `CLAUDE.global.md:546-552` | floors (3) Origin close contract: line-1-rung plus "verdict on the SECOND line" | G1 |
| `CLAUDE.global.md:876-881` | six-slot heading and table rows S1/S2 | G2 |
| `CLAUDE.global.md:887-890` | "verdict at line 2 is exactly what keeps the act's marker at line 3" | G3 |
| `CLAUDE.global.md:892-903` | S1, the relay rule | G4 (one sentence on position) |
| `CLAUDE.global.md:905-911` | ONE rung, UNHEDGED; "does not appear in line 1" | G5 |
| `CLAUDE.global.md:916-926` | S2 "on line 2, never last", plus the measurement | G6, G7 (adds the 2026-10-10 evidence) |
| `CLAUDE.global.md:743` | history: `✅ Complete & live` at line 1 hid "two things remain yours" | none (history; supports the change) |
| `commands/wrap.md:38-40` | relay order "below the rung line, the `Good to close:` line …" | W1 |
| `commands/wrap.md:45-47` | "the close is the rung line, the verdict line, …" | W2 |
| `commands/wrap.md:166-168` | "the close message must END with the operator's two standing answers" (stale: it contradicts "never last") | W3 |
| `commands/wrap.md:172-175` | pulls `close_shape_template`; "Line 1 stays wrap-ledger's rung readout, verbatim" | W4 |
| `commands/wrap.md:59,186` | three-axes table; "welded into line 1, 4%" | none |
| `commands/are-we-done.md:39-45` | emitted shape: rung line 1, `Good to close: yes` line 2 | A1 (outside the plan's literal file list, but it is the `/are-we-done` "good to close?" answer and would keep teaching the old shape) |
| `commands/are-we-done.md:58` | "that IS the rung, and it belongs on line 1" | A2 |
| `commands/are-we-done.md:90` | acceptance: lines 1 and 2 answer the question | none; still true |
| `hooks/lib/close-shape.sh:19` | "wrap-ledger.sh keeps sole ownership of line 1" | K1 |
| `hooks/lib/close-shape.sh:44-49` | CC_VERDICT_WINDOW=0 because only 1.1% of 613 closes put the verdict at position ≤3 | K2 |
| `hooks/lib/close-shape.sh:117-124` | `close_shape_template`: S1 line 1, verdict line 2 | K3 |
| `hooks/lib/close-shape.sh:214-222` | `close_act_template` first line "<line 1 = the ledger rung readout>" | K4 |
| `hooks/lib/close-shape.sh:243` | `close_shape_reason`: "Put it on the SECOND line … line-1-rung means line 1 …" | K5 |
| `hooks/lib/why-tier.sh:80-92` | `--why hedge`: "does not appear in line 1" | Y1 (keeps the `HEDGE —` prefix pinned by `tests/why-tier.bats:55-68`) |
| `hooks/lib/why-tier.sh:165-184` | `--why shape`: line-1 rung glyph; "PUT THE VERDICT ON THE SECOND LINE" | Y2 |
| `hooks/lib/why-tier.sh:186-200` | `--why act`: "verdict at line 2 keeps the marker at line 3" | Y3 |
| `hooks/lib/why-tier.sh:56` | topic list: "the rung glyph and the Good-to-close verdict" | none; still true |
| `hooks/completion-assert.sh:1414` | D3 reason prose "Line 1 answers 'is it safe to close?' with no qualifier" | D3R (prose only) |
| `hooks/completion-assert.sh:317-318,334,1046-1058` | CA_SETTLED/CA_RETRACT on the first line; D3 fires on settled AND retract | code, hooks slot: H1 |
| `hooks/completion-assert.sh:1245-1266` | D6: `case "$ca_first" in *"$RUNG"*` is the line-1-rung containment test | code, hooks slot: H2 |
| `hooks/completion-assert.sh:1311-1312` | D7 `close_act_ok` within CC_ACT_WINDOW=3 | none; both orders verified (§ 5) |
| `hooks/operator-readout.sh:1127-1140,1287-1297,1870` | renders `✅ SAFE TO CLOSE — nothing of mine is open` from git, ahead of the pile | none in docs; hooks slot H4 (it cannot see a task-level no) |
| `hooks/anti-deference-nudge.sh` | grep found no line-position or `Good to close` dependency (its opaque-id and category arms read the whole message) | none |
| `bin/cc-pane-close:27,99`; `hooks/lead-crash-watchdog.sh:1373-1395,1557` | parse the literal `Good to close: (yes\|no)` from the last assistant text | constraint: every draft keeps the literal |
| `scripts/measure-closes.py:405-416,507` | `rung_of` takes the first rung glyph in the text; `RE_GOODCLOSE` | none. ❌ is not a rung glyph, and C-no still carries the rung on line 2 |
| `docs/plans/STOPHOOK_MESSAGE_TIERING.md:552` (in-progress) | class table: "`Good to close:` at line 2" | T1 |
| `docs/plans/BACKLOG_DRAIN_24_7.md:35,13321` (open) | incidental quotes | none |
| `core/CLAUDE.core.md:63-71`, `core/commands/autonomy-wrap.md:11-12`, `core/hooks/completion-gate.sh:27-28` | portable autonomy core: "start the close with its READOUT glyph … Line 2 answers `Good to close`" | optional parity, not drafted. Outside the frozen scope, and the core gate abstains on `good to close: no` anywhere, so both candidates pass it |
| `install.sh:1060-1104` | deploys `CLAUDE.global.md` to `CLAUDE.full.md` (not loaded); the selected variant `CLAUDE.global.slim.md` to `CLAUDE.md`; `CLAUDE.rules.slim.*.md` to `rules/<name>.md` (copy, glob) | none; picks up the edits by glob |

Tests that pin doc or template text. All checked against the drafts (§ 5):
- `tests/research-program-exemption-rules.bats:15-38`: concatenates slim and rules, then greps four rules lines. All four survive in both B and C.
- `tests/wrap-ledger.bats:2099-2110`: the `priority … ⛔` ladder line in `CLAUDE.global.md` and `commands/wrap.md`. Untouched, still 1 match.
- `tests/why-tier.bats:55-68`: the `HEDGE —` prefix. Kept.
- `tests/completion-assert.bats:1279-1285,1656-1662`: the D6 token names; `close_shape_ok "$(close_shape_template)"` must be rc≠0 and `close_shape_missing` must print exactly `good-to-close-verdict`. Verified on the B and C templates.
- `tests/cc-pane-close.bats:45,108-112`, `tests/lead-crash-pane-verdict.bats:45`: the literal `Good to close: yes|no`. Kept.
- `tests/install-instructions-variant.bats:66-88`, `tests/deploy-parity.bats:1037-1040`, `tests/tokeff-regate-harness.bats`, `tests/instruction-budget.bats`: fixture text only. They pin deploy mechanics, not repo wording.

## 2. Size budgets a doc edit must respect

- Config `config/instruction-budget.json`: `per_file` 40,000, `conditional_per_file` 40,000, `tiers.user` 60,000, `tiers.repo` 60,000, `session` 120,000. Units are loader chars (UTF-16 units, with frontmatter and column-0 HTML comments stripped).
- Enforcement on these repo files: `hooks/backup-before-write.sh` (Write/Edit gate) and `scripts/ship-land.sh:3867-3890` (`cc-instruction-budget range` land ratchet, `enforce: true`). `classify()` (`hooks/lib/instruction_budget.py:456-480`) gives `CLAUDE.global.slim.md` and `CLAUDE.rules.slim.10-session-close.md` tier `source` through `deploy_sources`. `source` is not in `tiers`, so only the 40,000 per-file cap is enforced at edit and land. The user tier is judged by the fleet auditor.
- Measured by `bin/cc-instruction-budget measure`: `CLAUDE.global.slim.md` 28,078 · `CLAUDE.rules.slim.10-session-close.md` 30,334 · `CLAUDE.global.md` 112,798 (not loaded; unbudgeted).
- Measured by `bin/cc-instruction-budget assert --class user`: `BREACH [user] … user tier 60,696 > 60,000`. That is 28,078 + 30,334 + `rules/00-mission-board.md` 2,284. The breach exists before this change. The config's destination text says "the slim global and its rules are one-in-one-out", so the rules-file edit should be net ≤ 0.
- Rules-file delta, measured by `/tmp/cvf-docs/tools/apply.py` with `instruction_budget.parse`:

  | Candidate | Without offsets | With offsets |
  |---|---|---|
  | B | +154 | −3 (30,331) |
  | C | +151 | −6 (30,328) |

  The offsets are O1, which shortens the S2 paragraph's sentence about the Complication/Solution/Outcome labels, and O2, which drops the parity-auditor sentence from the 🚀 bullet; `CLAUDE.global.md:741` keeps that fact. Per-file headroom is about 9.5k in every case.
- The edits do not touch `CLAUDE.global.slim.md`. Its `derived-from CLAUDE.global.md sha256:cecd5a0c2fa35792` header is already STALE: `shasum -a 256 CLAUDE.global.md` gives 16b96b23f93ed2c4. This is advisory only (`bin/cc-instructions-variant status`), not a gate.
- Unbudgeted: `CLAUDE.global.md` (deploys to the non-loaded `CLAUDE.full.md`) and `commands/*.md` (loaded on invocation). These drafts grow `CLAUDE.global.md` by +1,070 (B) / +971 (C) chars, measured.
- `scripts/rules-hook-budget-lint.sh` governs only `.claude/rules/agent-operating-lessons.md` bullets. It does not apply unless a lesson is added.

## 3. Hook-side facts the drafted text depends on (hooks slot must land them in the same change, or the docs will state something the hooks do not enforce)

- H1, the D3 false FAIL on an honest verdict-first no. This was measured by `/tmp/cvf-docs/d3b.sh` and `/tmp/cvf-docs/tools/shapes.sh`, which copy `CA_SETTLED`/`CA_RETRACT` from `completion-assert.sh:317-318`. All 5 natural no-lines tried trip D3 today, under both B and C: they say "remain", "pending", "yours", "one thing" or "still needs", and the template itself says "what remains". Example: `Good to close: no — two steps remain, owned by pane 182 and this pane.` gives D3=1. D3 needs an exemption for a first line that leads with a negative verdict (`^[^A-Za-z]*(❌[[:space:]]*)?good to close:[[:space:]]*no`). Drafts G5, Y1 and D3R state "naming what remains is not a hedge"; that statement is false until H1 lands.
- H2, D6 `line-1-rung` (`completion-assert.sh:1262-1265`). B-no and C-no put the rung glyph on line 2. The test must accept the glyph on line 2 when line 1 is a verdict line (B: a no-verdict; C: any verdict). C-yes keeps the rung glyph on line 1, so it passes unchanged.
- H3, the refusal the plan's frozen scope asks for. The LEFT screenshot close passes every arm today. `shapes.sh` LEFT-today gives verdict_missing=[] and D3=0, and its line 1 contains ✅, so D6 containment passes too. B and C both need a new D6 token: verdict no while the first line reads as done (✅ / complete / nothing to do / safe to close / leading yes). The RIGHT close (✅ … plus `Good to close: yes`) passes under B as is. Under C it lacks the verdict-first shape, so C has to keep accepting the old yes shape during transition. Otherwise every honest yes close written the old way becomes a false FAIL, which is the brief's worse error. B leaves the yes path byte-identical, so it carries no new false-FAIL risk on yes closes.
- H4, the certificate. `operator-readout.sh:1138` renders `✅ SAFE TO CLOSE — nothing of mine is open` from git plus a DoD remainder, beneath a model `no`. Docs G0 and R5 say the verdict is not overruled by it. Whether the hook should also read the model's verdict is for the hooks slot to decide.
- CC_ACT_WINDOW=3 holds for every drafted shape. `shapes.sh` gives act_missing=[] for B-no, B-yes, C-no and C-yes with `▶ Run this:` on line 3.

## 4. Exact replacement text, per passage (OLD verbatim, then NEW for B and for C)

Passage ids: R = slim rules file · G = full text · W = /wrap · A = /are-we-done · K = close-shape.sh · Y = why-tier.sh · D3R = completion-assert reason prose · T = plan table · O = optional one-in-one-out offsets for the rules file. Line ranges were computed against worktree HEAD `ec25d5cb7`. None of the target files changed between `8c45471db` and `ec25d5cb7`; the only commit in that range is the plan.

### `CLAUDE.rules.slim.10-session-close.md`

#### R1 — § Stop-hook arms — Origin close contract bullet (line 22) — `CLAUDE.rules.slim.10-session-close.md:22-22`

OLD:

~~~~text
- Origin close contract (`completion-assert.sh` arm D6; template in `hooks/lib/close-shape.sh`, shared with `/wrap`): an origin session (no fired-peer stamp; `hooks/lib/origin-identity.sh`) closing ✅ or 👤 after written work puts the ledger's rung glyph on line 1 (`line-1-rung`) and, on line 2, either `Good to close: yes — nothing of mine is open; follow-on: <filed ids|none>` or `Good to close: no — <what remains + who owns it>`. A hedged both-ways answer fails (arm D3). Assignees and fired peers are exempt; their close is the lead's harvest or the notify-back ping.
~~~~

NEW (B):

~~~~text
- Origin close contract (`completion-assert.sh` arm D6; template in `hooks/lib/close-shape.sh`, shared with `/wrap`): an origin session (no fired-peer stamp; `hooks/lib/origin-identity.sh`) closing ✅ or 👤 after written work puts the ledger's rung glyph on line 1 (`line-1-rung`) and `Good to close: yes — nothing of mine is open; follow-on: <filed ids|none>` on line 2. A no swaps them: line 1 is `Good to close: no — <what remains + who owns it>`, the rung line 2, since a ✅ or 👤 line 1 reads as done. Naming what remains is no hedge; a both-ways answer fails (arm D3). Assignees and fired peers are exempt; their close is the lead's harvest or the notify-back ping.
~~~~

NEW (C):

~~~~text
- Origin close contract (`completion-assert.sh` arm D6; template in `hooks/lib/close-shape.sh`, shared with `/wrap`): an origin session (no fired-peer stamp; `hooks/lib/origin-identity.sh`) closing ✅ or 👤 after written work leads with the verdict. Line 1 is `<rung glyph> Good to close: yes — nothing of mine is open; follow-on: <filed ids|none>` or `❌ Good to close: no — <what remains + who owns it>`; line 2 relays the ledger's rung glyph (`line-1-rung`). Naming what remains is no hedge; a both-ways answer fails (arm D3). Assignees and fired peers are exempt; their close is the lead's harvest or the notify-back ping.
~~~~

#### R2 — § The six slots — heading and table rows S1-S3 — `CLAUDE.rules.slim.10-session-close.md:129-137`

OLD:

~~~~text
### The six slots, in this order

Omit a slot that has nothing to say; never pad one.

| Slot | Content | Present when |
|---|---|---|
| S1 STATE, line 1 | the ledger's rung glyph and state clause, relayed, plus one clause naming what the work was | always |
| S2 VERDICT, line 2 | `Good to close: yes\|no — …`, with the follow-on ledger | terminal close (`✅`/`👤`) after real written work |
| S3 ACT, line 3 | the `▶ Run this:` marker, its command on the next line | only when the operator must do something |
~~~~

NEW (B):

~~~~text
### The six slots, in this order

Omit a slot that has nothing to say; never pad one.

| Slot | Content | Present when |
|---|---|---|
| S1 STATE, line 1 (2 on a no) | the ledger's rung glyph and state clause, relayed, plus one clause naming what the work was | always |
| S2 VERDICT, line 2 (1 on a no) | `Good to close: yes\|no — …`, with the follow-on ledger | terminal close (`✅`/`👤`) after real written work |
| S3 ACT, line 3 | the `▶ Run this:` marker, its command on the next line | only when the operator must do something |
~~~~

NEW (C):

~~~~text
### The six slots, verdict first

Omit a slot that has nothing to say; never pad one.

| Slot | Content | Present when |
|---|---|---|
| S2 VERDICT, line 1 | `<rung glyph> Good to close: yes — …` or `❌ Good to close: no — …`, with the follow-on ledger | terminal close (`✅`/`👤`) after real written work |
| S1 STATE, line 2 (1 if no S2) | the ledger's rung glyph and state clause, relayed, plus one clause naming what the work was | always |
| S3 ACT, line 3 | the `▶ Run this:` marker, its command on the next line | only when the operator must do something |
~~~~

#### R3 — § The six slots — the CC_ACT_WINDOW sentence (line 142) — `CLAUDE.rules.slim.10-session-close.md:142-142`

OLD:

~~~~text
S1–S3 are the lines the operator scans; S4–S6 are at most three supporting lines. The act marker must fall within the first 3 non-blank, unfenced lines (`CC_ACT_WINDOW`=3), which is why the verdict sits on line 2.
~~~~

NEW (B and C identical):

~~~~text
S1–S3 are the lines the operator scans; S4–S6 are at most three supporting lines. The act marker must fall within the first 3 non-blank, unfenced lines (`CC_ACT_WINDOW`=3), which is why verdict and state hold lines 1–2.
~~~~

#### R4 — § The six slots — the 'Line 1 carries one rung' paragraph (line 146) — `CLAUDE.rules.slim.10-session-close.md:146-146`

OLD:

~~~~text
Line 1 carries one rung and states a conclusion, not a category (`12 runnable now, 195 need your call`, not `205 manual steps`). It does not hedge, and nothing later in the close withdraws it. If something is parked or is theirs, that is the rung (`📦` / `👤`); if it is immaterial, it stays out of line 1. A qualification goes in S2's `follow-on:` clause, beside the assertion.
~~~~

NEW (B and C identical):

~~~~text
The S1 line carries one rung and states a conclusion, not a category (`12 runnable now, 195 need your call`, not `205 manual steps`). It does not hedge, and nothing later in the close withdraws it. If something is parked or is theirs, that is the rung (`📦` / `👤`); if it is immaterial, it stays out. A qualification goes in S2's `follow-on:` clause, beside the assertion.
~~~~

#### R5 — § The six slots — S2 paragraph (line 148) — `CLAUDE.rules.slim.10-session-close.md:148-148`

OLD:

~~~~text
S2. The `Good to close:` line, in either form given under Origin close contract, on line 2 and never as the last line. The rung does not imply it, and a rendered `✅ SAFE TO CLOSE` certificate does not replace it; an honest no satisfies the contract.
~~~~

NEW (B):

~~~~text
S2. The `Good to close:` line, in either form given under Origin close contract: line 2, or line 1 on a no; never last. The rung does not imply it, and a rendered `✅ SAFE TO CLOSE` certificate (git facts only) neither replaces nor overrules it; an honest no satisfies the contract.
~~~~

NEW (C):

~~~~text
S2. The `Good to close:` line, in either form given under Origin close contract, on line 1 and never last, led by the verdict's glyph. The rung does not imply it, and a rendered `✅ SAFE TO CLOSE` certificate (git facts only) neither replaces nor overrules it; an honest no satisfies the contract.
~~~~


### `CLAUDE.global.md`

#### G0 — § Session Close Protocol — close-certificate bullet (lines 516-521) — `CLAUDE.global.md:519-521`

OLD:

~~~~text
  `👤` rule below). Computed from live git reads, never from prose, so it is the one line in a close
  the model cannot fake. Read-only turns, and any state it cannot verify, stay silent — a
  certificate that fired at every close would carry no information at all.
~~~~

NEW (B and C identical):

~~~~text
  `👤` rule below). Computed from live git reads, never from prose, so it is the one line in a close
  the model cannot fake. Read-only turns, and any state it cannot verify, stay silent — a
  certificate that fired at every close would carry no information at all. It reads git, never the
  task: a close whose own verdict is `no` (a peer still to land, an open plan step) is not overruled
  by it, and its verdict line still leads.
~~~~

#### G1 — § Session Close Protocol — floors (3) THE ORIGIN CLOSE CONTRACT (lines 546-552) — `CLAUDE.global.md:546-551`

OLD:

~~~~text
  closing genuine completion (✅/👤) after real written work must answer, mechanically matched,
  **two** things: line 1 carries the ledger's own **rung glyph** (`line-1-rung`), and the close
  states `Good to close: yes — nothing of mine is open; follow-on: <filed ids|none>` — an honest
  `Good to close: no — <what remains + who owns it>` also satisfies (the contract is that the
  question is ANSWERED; hedging stays D3's defect). *Put the verdict on the SECOND line, not the
  last* — § The close message S2 carries the measurement. 🚨 **`Complication:` / `Solution:` /
~~~~

NEW (B):

~~~~text
  closing genuine completion (✅/👤) after real written work must answer, mechanically matched,
  **two** things: line 1 carries the ledger's own **rung glyph** (`line-1-rung`), and the close
  states `Good to close: yes — nothing of mine is open; follow-on: <filed ids|none>` — an honest
  `Good to close: no — <what remains + who owns it>` also satisfies (the contract is that the
  question is ANSWERED; hedging stays D3's defect, and naming what remains is not a hedge). *Put the
  verdict on the SECOND line, not the last* — **except on a no, where the verdict line IS line 1
  and the rung line drops to line 2** (CLOSE_VERDICT_FIRST, 2026-10-10: a `✅` line 1 reads as done
  before the `no` under it is reached). § The close message S2 carries the measurement.
  🚨 **`Complication:` / `Solution:` /
~~~~

NEW (C):

~~~~text
  closing genuine completion (✅/👤) after real written work must answer, mechanically matched,
  **two** things, **verdict first**: line 1 is the verdict, led by its own glyph —
  `<rung glyph> Good to close: yes — nothing of mine is open; follow-on: <filed ids|none>` or
  `❌ Good to close: no — <what remains + who owns it>` — and line 2 relays the ledger's own
  **rung glyph** and state clause (`line-1-rung` accepts the glyph there). An honest no satisfies
  (the contract is that the question is ANSWERED; hedging stays D3's defect, and naming what
  remains is not a hedge). § The close message S2 carries the measurement.
  🚨 **`Complication:` / `Solution:` /
~~~~

#### G2 — § The close message — six-slot heading, table rows S1/S2, arithmetic paragraph (lines 876-890) — `CLAUDE.global.md:876-881`

OLD:

~~~~text
### The six slots, in this order. Unfilled slots are omitted, never padded.

| | Slot | The one fact | Present when |
|---|---|---|---|
| **S1** | **STATE** — line 1 | the ledger's rung glyph + state clause, relayed, plus ONE clause naming what the work WAS | always |
| **S2** | **VERDICT** — line 2 | `Good to close: yes\|no — …`, with the follow-on ledger | terminal close (`✅`/`👤`) after real written work |
~~~~

NEW (B):

~~~~text
### The six slots, in this order. Unfilled slots are omitted, never padded.

| | Slot | The one fact | Present when |
|---|---|---|---|
| **S1** | **STATE** — line 1 (line 2 on a no) | the ledger's rung glyph + state clause, relayed, plus ONE clause naming what the work WAS | always |
| **S2** | **VERDICT** — line 2 (line 1 on a no) | `Good to close: yes\|no — …`, with the follow-on ledger | terminal close (`✅`/`👤`) after real written work |
~~~~

NEW (C):

~~~~text
### The six slots, verdict first. Unfilled slots are omitted, never padded.

| | Slot | The one fact | Present when |
|---|---|---|---|
| **S2** | **VERDICT** — line 1 | `<rung glyph> Good to close: yes — …` or `❌ Good to close: no — …`, with the follow-on ledger | terminal close (`✅`/`👤`) after real written work |
| **S1** | **STATE** — line 2 (line 1 when no S2 is due) | the ledger's rung glyph + state clause, relayed, plus ONE clause naming what the work WAS | always |
~~~~

#### G3 — § The close message — the 'order is arithmetic' paragraph (lines 887-890) — `CLAUDE.global.md:887-890`

OLD:

~~~~text
S1–S3 are the three lines they scan; S4–S6 are the ≤3 supporting lines (Ch 6 p. 78). **The order is
arithmetic, not taste:** S3 occupies two physical rows (`▶ Run this:` then the command), so the
verdict at line 2 is exactly what keeps the act's marker at non-blank line 3, inside the shipped
`CC_ACT_WINDOW` of 3 — verified by executing `close_act_missing` on this shape.
~~~~

NEW (B):

~~~~text
S1–S3 are the three lines they scan; S4–S6 are the ≤3 supporting lines (Ch 6 p. 78). **The order is
arithmetic, not taste:** S3 occupies two physical rows (`▶ Run this:` then the command), so verdict
and state holding lines 1–2, in either order, is exactly what keeps the act's marker at non-blank
line 3, inside the shipped `CC_ACT_WINDOW` of 3 — verified by executing `close_act_missing` on both
orders.
~~~~

NEW (C):

~~~~text
S2, S1, S3 are the three lines they scan, in that order; S4–S6 are the ≤3 supporting lines (Ch 6
p. 78). **The order is arithmetic, not taste:** S3 occupies two physical rows (`▶ Run this:` then the
command), so verdict and state holding lines 1–2 is exactly what keeps the act's marker at non-blank
line 3, inside the shipped `CC_ACT_WINDOW` of 3 — verified by executing `close_act_missing` on this
shape.
~~~~

#### G4 — § The close message — end of the S1 paragraph (lines 901-903) — `CLAUDE.global.md:901-902`

OLD:

~~~~text
partitions the pile along the groupings that follow instead of naming its size. The one exception is
`⛔`, whose tail is `BLOCKED_WHAT` — the operator's own words — and is kept.
~~~~

NEW (B):

~~~~text
partitions the pile along the groupings that follow instead of naming its size. The one exception is
`⛔`, whose tail is `BLOCKED_WHAT` — the operator's own words — and is kept. On a `no` verdict this
line drops to line 2, under S2.
~~~~

NEW (C):

~~~~text
partitions the pile along the groupings that follow instead of naming its size. The one exception is
`⛔`, whose tail is `BLOCKED_WHAT` — the operator's own words — and is kept. Under an S2 verdict this
line is line 2; with none due it is line 1.
~~~~

#### G5 — § The close message — 'ONE rung, UNHEDGED' paragraph (lines 908-911) — `CLAUDE.global.md:908-911`

OLD:

~~~~text
operator still replied *"Are we good to close?"*. If something is parked or is theirs, **that IS the
rung** (`📦` / `👤`); if it is immaterial it does not appear in line 1 at all. Never both — and
anything that would withdraw the assertion goes in S2's `follow-on:` clause, *beside* it, never below
it.
~~~~

NEW (B and C identical):

~~~~text
operator still replied *"Are we good to close?"*. If something is parked or is theirs, **that IS the
rung** (`📦` / `👤`); if it is immaterial it does not appear in the S1 line at all. Never both — and
anything that would withdraw the assertion goes in S2's `follow-on:` clause, *beside* it, never below
it. A plain `Good to close: no — <what remains + who owns it>` is not a hedge: it is one verdict,
and the remainder is its content.
~~~~

#### G6 — § The close message — S2 heading sentence (line 916) — `CLAUDE.global.md:916-916`

OLD:

~~~~text
**S2 — VERDICT. `Good to close: …`, on line 2, never last.** This line is **not derivable from the
~~~~

NEW (B):

~~~~text
**S2 — VERDICT. `Good to close: …`, on line 2 — line 1 on a `no` — never last.** This line is **not derivable from the
~~~~

NEW (C):

~~~~text
**S2 — VERDICT. `Good to close: …`, on line 1, led by its own glyph, never last.** This line is **not derivable from the
~~~~

#### G7 — § The close message — S2 paragraph, after 'the question is ANSWERED' (lines 925-926) — `CLAUDE.global.md:925-926`

OLD:

~~~~text
of 403 `✅` closes still drew a re-ask.** An honest `Good to close: no — <what remains + who owns it>`
satisfies equally; the contract is that the question is ANSWERED.
~~~~

NEW (B):

~~~~text
of 403 `✅` closes still drew a re-ask.** An honest `Good to close: no — <what remains + who owns it>`
satisfies equally; the contract is that the question is ANSWERED. **A done-reading line above a `no`
defeats it** (operator screenshot, 2026-10-10): two closes side by side both opened `✅ …`; one's
next line said `Good to close: no`, and at a glance both read yes. Lines 1 and 2 render as one
wrapped paragraph, so its opening glyph and words are read as the verdict. Hence a `no` takes line 1
itself, and no `✅`, `complete` or `nothing to do` stands above it.
~~~~

NEW (C):

~~~~text
of 403 `✅` closes still drew a re-ask.** An honest `Good to close: no — <what remains + who owns it>`
satisfies equally; the contract is that the question is ANSWERED. **A done-reading line above a `no`
defeats it** (operator screenshot, 2026-10-10): two closes side by side both opened `✅ …`; one's
next line said `Good to close: no`, and at a glance both read yes. Lines 1 and 2 render as one
wrapped paragraph, so its opening glyph and words are read as the verdict. Hence the verdict owns
line 1 and its glyph: the rung glyph on a yes, `❌` on a no.
~~~~


### `commands/wrap.md`

#### W1 — operator-steps block relay order (lines 38-40) — `commands/wrap.md:38-39`

OLD:

~~~~text
3 ids and carrying its exact listing command. Relay it VERBATIM below the rung line, the
`Good to close:` line (when the close carries one) and the act line — never paraphrase the commands
~~~~

NEW (B):

~~~~text
3 ids and carrying its exact listing command. Relay it VERBATIM below the rung line, the
`Good to close:` line (when the close carries one; on a no it comes first) and the act line — never paraphrase the commands
~~~~

NEW (C):

~~~~text
3 ids and carrying its exact listing command. Relay it VERBATIM below the `Good to close:` line
(when the close carries one), the rung line and the act line — never paraphrase the commands
~~~~

#### W2 — 'the close is …' sentence (lines 45-47) — `commands/wrap.md:46-47`

OLD:

~~~~text
close is the rung line, the verdict line, at most one act line, the relayed block, and at most three
supporting lines.
~~~~

NEW (B):

~~~~text
close is the rung line and the verdict line (swapped on a no), at most one act line, the relayed
block, and at most three supporting lines.
~~~~

NEW (C):

~~~~text
close is the verdict line, the rung line, at most one act line, the relayed block, and at most three
supporting lines.
~~~~

#### W3 — § Origin final close — intro 'must end with' (lines 166-168) — `commands/wrap.md:167-168`

OLD:

~~~~text
oi_origin_class`) closing GENUINE completion (rung ✅/👤) after real written work, the close message
must end with the operator's two standing answers. Render the skeleton from the ONE source and fill
~~~~

NEW (B):

~~~~text
oi_origin_class`) closing GENUINE completion (rung ✅/👤) after real written work, the close message
must answer "good to close?" in its first two lines, never at the end. Render the skeleton from the ONE source and fill
~~~~

NEW (C):

~~~~text
oi_origin_class`) closing GENUINE completion (rung ✅/👤) after real written work, the close message
must OPEN with the answer to "good to close?". Render the skeleton from the ONE source and fill
~~~~

#### W4 — § Origin final close — line-1 sentence after the template (lines 174-175) — `commands/wrap.md:174-175`

OLD:

~~~~text
Line 1 stays wrap-ledger's rung readout, verbatim. An honest `Good to close: no — <what remains +
who owns it>` satisfies the contract; a hedged both-ways answer does not (D3 owns that defect).
~~~~

NEW (B):

~~~~text
Line 1 stays wrap-ledger's rung readout, verbatim — except on a no: then line 1 is `Good to close:
no — <what remains + who owns it>` and the readout is line 2, so a `✅` or `👤` never opens a no. An
honest no satisfies the contract; naming what remains is not a hedge, a both-ways answer is (D3).
~~~~

NEW (C):

~~~~text
Line 1 is the verdict, led by its own glyph: the rung glyph on a yes, `❌` on a no. Line 2 is
wrap-ledger's rung readout, verbatim. An honest `❌ Good to close: no — <what remains + who owns it>`
satisfies the contract; naming what remains is not a hedge, a both-ways answer is (D3).
~~~~


### `commands/are-we-done.md`

#### A1 — § Answer — the emitted shape block (lines 39-45) and the sentence after it — `commands/are-we-done.md:39-47`

OLD:

~~~~text
```
<rung glyph> <state clause> — <one clause naming what the work WAS>
Good to close: yes — nothing of mine is open; follow-on: <filed ids | none>
▶ Run this:                          ← ONLY if a command is genuinely theirs to run

Working | Idling — <cause, one clause>
Mine this session: <what THIS session filed or created, named | nothing unfiled>
```

~~~~

NEW (B):

~~~~text
```
<rung glyph> <state clause> — <one clause naming what the work WAS>
Good to close: yes — nothing of mine is open; follow-on: <filed ids | none>
▶ Run this:                          ← ONLY if a command is genuinely theirs to run

Working | Idling — <cause, one clause>
Mine this session: <what THIS session filed or created, named | nothing unfiled>
```

On a `no`, the first two lines swap: `Good to close: no — <which check, and who owns it>` is line 1
and the rung line is line 2. A `✅` or `👤` line never opens a `no`.

~~~~

NEW (C):

~~~~text
```
<rung glyph> Good to close: yes — nothing of mine is open; follow-on: <filed ids | none>
<rung glyph> <state clause> — <one clause naming what the work WAS>
▶ Run this:                          ← ONLY if a command is genuinely theirs to run

Working | Idling — <cause, one clause>
Mine this session: <what THIS session filed or created, named | nothing unfiled>
```

On a `no`, line 1 is `❌ Good to close: no — <which check, and who owns it>`; the rung line stays
line 2. A `✅` or `👤` never opens a `no`.

~~~~

#### A2 — § Answer — 'it belongs on line 1' (line 58) — `commands/are-we-done.md:58-58`

OLD:

~~~~text
if something is parked or theirs, that IS the rung, and it belongs on line 1.
~~~~

NEW (B and C identical):

~~~~text
if something is parked or theirs, that IS the rung, and it belongs on the rung line.
~~~~


### `hooks/lib/close-shape.sh`

#### K1 — header — 'keeps sole ownership of line 1' (line 19) — `hooks/lib/close-shape.sh:19-19`

OLD:

~~~~text
# this lib is the one code path, and scripts/wrap-ledger.sh keeps sole ownership of line 1.
~~~~

NEW (B):

~~~~text
# this lib is the one code path, and scripts/wrap-ledger.sh keeps sole ownership of the rung line
# (line 1, or line 2 under a NO verdict — CLOSE_VERDICT_FIRST 2026-10-10).
~~~~

NEW (C):

~~~~text
# this lib is the one code path, and scripts/wrap-ledger.sh keeps sole ownership of the rung line
# (line 2 under a verdict, which owns line 1 — CLOSE_VERDICT_FIRST 2026-10-10).
~~~~

#### K2 — CC_VERDICT_WINDOW comment (lines 47-48) — `hooks/lib/close-shape.sh:48-49`

OLD:

~~~~text
# Move the placement via close_shape_template first, re-measure, THEN set the window. The fence
# skip added below is what makes turning it on possible later at all.
~~~~

NEW (B and C identical):

~~~~text
# Move the placement via close_shape_template first, re-measure, THEN set the window. The fence
# skip added below is what makes turning it on possible later at all. CLOSE_VERDICT_FIRST
# (2026-10-10) moved the template's verdict to line 1 or 2; the window stays 0 until a re-measure
# over closes written after that move shows honest closes already sit inside 2.
~~~~

#### K3 — close_shape_template body (lines 119-120) — `hooks/lib/close-shape.sh:119-120`

OLD:

~~~~text
<S1 line 1 = wrap-ledger READOUT's rung glyph and state clause verbatim, then YOUR one clause naming what the work was (or expanding the count the ledger could only count)>
Good to close: <yes — nothing of mine is open; follow-on: <filed ids, each expanded in plain English|none> | no — <what remains + who owns it>>
~~~~

NEW (B):

~~~~text
<S1 line 1 = wrap-ledger READOUT's rung glyph and state clause verbatim, then YOUR one clause naming what the work was (or expanding the count the ledger could only count)>
Good to close: <yes — nothing of mine is open; follow-on: <filed ids, each expanded in plain English|none> | no — <what remains + who owns it>>
<on a NO, swap the two lines above: the no-verdict becomes line 1 and the readout line 2, so a done-reading glyph never opens a no>
~~~~

NEW (C):

~~~~text
<✅ or 👤 on a yes, ❌ on a no> Good to close: <yes — nothing of mine is open; follow-on: <filed ids, each expanded in plain English|none> | no — <what remains + who owns it>>
<S1 line 2 = wrap-ledger READOUT's rung glyph and state clause verbatim, then YOUR one clause naming what the work was (or expanding the count the ledger could only count)>
~~~~

#### K4 — close_act_template first line (line 216) — `hooks/lib/close-shape.sh:216-216`

OLD:

~~~~text
<line 1 = the ledger rung readout, verbatim from wrap-ledger>
~~~~

NEW (B):

~~~~text
<lines 1-2 = the ledger rung readout, verbatim from wrap-ledger, and the good-to-close verdict (verdict first on a no)>
~~~~

NEW (C):

~~~~text
<lines 1-2 = the good-to-close verdict, then the ledger rung readout, verbatim from wrap-ledger>
~~~~

#### K5 — close_shape_reason — placement + line-1-rung sentences (line 243, inside the printf format) — `hooks/lib/close-shape.sh:243-243`

OLD:

~~~~text
Put it on the SECOND line, directly under the rung and BEFORE any supporting detail — 90.7%% of closes bury it as the last line and the operator asks the question anyway. A missing line-1-rung means line 1 does not carry the ledger'\''s own rung glyph: run
~~~~

NEW (B):

~~~~text
Put it on the SECOND line, directly under the rung and BEFORE any supporting detail — 90.7%% of closes bury it as the last line and the operator asks the question anyway. On a NO it goes on line 1 instead, with the rung line under it: a complete-and-live line 1 reads as done before the no is reached. A missing line-1-rung means the rung line (line 1, or line 2 under a no) does not carry the ledger'\''s own rung glyph: run
~~~~

NEW (C):

~~~~text
Put it on the FIRST line, led by its own glyph (the rung glyph on a yes, ❌ on a no), BEFORE any supporting detail — 90.7%% of closes bury it as the last line and the operator asks the question anyway, and a complete-and-live line 1 above a no reads as done. A missing line-1-rung means neither line 1 nor line 2 carries the ledger'\''s own rung glyph: run
~~~~


### `hooks/lib/why-tier.sh`

#### Y1 — --why hedge, last three lines (lines 89-91) — `hooks/lib/why-tier.sh:89-91`

OLD:

~~~~text
If something is parked or is theirs, THAT IS THE RUNG (📦 / 👤). If it is immaterial it does not
appear in line 1 at all. Anything that would withdraw the assertion goes in the `follow-on:` clause
of the Good-to-close line — beside the verdict, never below it.
~~~~

NEW (B and C identical):

~~~~text
If something is parked or is theirs, THAT IS THE RUNG (📦 / 👤). If it is immaterial it does not
appear in the rung line at all. Anything that would withdraw the assertion goes in the `follow-on:`
clause of the Good-to-close line — beside the verdict, never below it. A plain
`Good to close: no — <what remains + who owns it>` is not a hedge: one verdict, and the remainder is
its content.
~~~~

#### Y2 — --why shape, items 1-2 and the placement paragraph (lines 169-180) — `hooks/lib/why-tier.sh:170-179`

OLD:

~~~~text
  1. line 1 carries the ledger's own RUNG GLYPH — run `scripts/wrap-ledger.sh --machine`, take
     READOUT, copy its glyph and state clause verbatim, and replace only the tail with one clause
     naming what the work WAS.
  2. the close states `Good to close: yes — nothing of mine is open; follow-on: <filed ids|none>`.
An honest `Good to close: no — <what remains + who owns it>` satisfies it equally: the contract is
that the question is ANSWERED, not that the answer is yes.
PUT THE VERDICT ON THE SECOND LINE, NOT THE LAST. Measured over 613 closes carrying it, the rung
predicts the verdict only 73.4% of the time, and the line sits LAST in 90.7% of closes today — a
173-word close with ✅ at line 1 whose literal last line answered the question still drew the
operator's entire next message: "Good to close?".
~~~~

NEW (B):

~~~~text
  1. line 1 carries the ledger's own RUNG GLYPH — run `scripts/wrap-ledger.sh --machine`, take
     READOUT, copy its glyph and state clause verbatim, and replace only the tail with one clause
     naming what the work WAS.
  2. the close states `Good to close: yes — nothing of mine is open; follow-on: <filed ids|none>`.
An honest `Good to close: no — <what remains + who owns it>` satisfies it equally: the contract is
that the question is ANSWERED, not that the answer is yes.
PUT THE VERDICT ON THE SECOND LINE, NOT THE LAST — AND ON A NO, ON THE FIRST. Measured over 613
closes carrying it, the rung predicts the verdict only 73.4% of the time, and the line sits LAST in
90.7% of closes today — a 173-word close with ✅ at line 1 whose literal last line answered the
question still drew the operator's entire next message: "Good to close?". And a ✅ line 1 above a
`Good to close: no` on line 2 still reads as yes at a glance (operator screenshot, 2026-10-10), so
on a no the verdict is line 1 and the rung line drops to line 2.
~~~~

NEW (C):

~~~~text
  1. line 1 is the verdict, led by its own glyph: `<rung glyph> Good to close: yes — nothing of
     mine is open; follow-on: <filed ids|none>` or `❌ Good to close: no — <what remains + who owns
     it>`. The contract is that the question is ANSWERED, not that the answer is yes.
  2. line 2 carries the ledger's own RUNG GLYPH — run `scripts/wrap-ledger.sh --machine`, take
     READOUT, copy its glyph and state clause verbatim, and replace only the tail with one clause
     naming what the work WAS.
VERDICT FIRST, NEVER LAST. Measured over 613 closes carrying it, the rung predicts the verdict only
73.4% of the time, and the line sits LAST in 90.7% of closes today — a 173-word close with ✅ at
line 1 whose literal last line answered the question still drew the operator's entire next message:
"Good to close?". And a ✅ line 1 above a `Good to close: no` on line 2 still reads as yes at a
glance (operator screenshot, 2026-10-10).
~~~~

#### Y3 — --why act, window sentence (lines 191-193) — `hooks/lib/why-tier.sh:192-193`

OLD:

~~~~text
the Good-to-close verdict at line 2 is exactly what keeps the marker at non-blank line 3, inside the
shipped CC_ACT_WINDOW of 3.
~~~~

NEW (B and C identical):

~~~~text
the verdict and the rung line holding lines 1-2 is exactly what keeps the marker at non-blank line 3,
inside the shipped CC_ACT_WINDOW of 3.
~~~~


### `hooks/completion-assert.sh`

#### D3R — D3 block reason, last sentence (line 1414) — `hooks/completion-assert.sh:1414-1414`

OLD:

~~~~text
Line 1 answers 'is it safe to close?' with no qualifier."
~~~~

NEW (B and C identical):

~~~~text
Line 1 answers 'is it safe to close?' with no qualifier; a plain 'Good to close: no — <what remains + who owns it>' is a clean answer, not a hedge."
~~~~


### `docs/plans/STOPHOOK_MESSAGE_TIERING.md`

#### T1 — § class table row `shape` (line 552) — `docs/plans/STOPHOOK_MESSAGE_TIERING.md:552-552`

OLD:

~~~~text
| `shape` | completion-assert | the ORIGIN close contract (rung glyph + `Good to close:` at line 2) | 3.3 B7 |
~~~~

NEW (B):

~~~~text
| `shape` | completion-assert | the ORIGIN close contract (rung glyph + `Good to close:` at line 2, line 1 on a no) | 3.3 B7 |
~~~~

NEW (C):

~~~~text
| `shape` | completion-assert | the ORIGIN close contract (`Good to close:` at line 1, rung glyph by line 2) | 3.3 B7 |
~~~~


### `CLAUDE.rules.slim.10-session-close.md`

#### O1 — OFFSET (optional) — S2 paragraph tail (line 148): the C/S/O sentence — `CLAUDE.rules.slim.10-session-close.md:148-148`

OLD:

~~~~text
`Complication:` / `Solution:` / `Outcome:` lines are optional; write one only when it says something the body does not.
~~~~

NEW (B and C identical):

~~~~text
`Complication:` / `Solution:` / `Outcome:` lines are optional.
~~~~

#### O2 — OFFSET (optional) — 🚀 rung bullet (line 96): the parity-auditor sentence, kept in CLAUDE.global.md:741 — `CLAUDE.rules.slim.10-session-close.md:96-96`

OLD:

~~~~text
 A new deployed top-level directory is audited by `scripts/deploy-parity-assert.sh`, not the ledger.
~~~~

NEW (B and C identical):

~~~~text

~~~~


## 5. Verification receipts (all measured; scratch only, no tracked file touched)

- `python3 -I /tmp/cvf-docs/tools/apply.py`: all 31 OLD strings occur exactly once in their files, for both B and C. The script writes patched copies to `/tmp/cvf-docs/B/` and `/tmp/cvf-docs/C/` and prints the char and loader-unit deltas used in § 2.
- `bash -n` passes on the patched `hooks/lib/close-shape.sh`, `hooks/lib/why-tier.sh` and `hooks/completion-assert.sh` for B and C. Bare `shellcheck` is clean on the patched `close-shape.sh` and `why-tier.sh` for B and C (K5 adds no backticks and keeps percent signs doubled).
- Patched `close_shape_template`, B and C:
  - `close_shape_ok "$(close_shape_template)"` is rc≠0;
  - `close_shape_missing` prints `good-to-close-verdict`;
  - the template contains no `▶`.
  This is the MENTION-vs-USE guard pinned by `tests/completion-assert.bats:1656-1662`. Constraint for anyone rewording K3: on every template line, the first `good to close` must be followed by a `<…>` value. A line such as `<on a NO …: "Good to close: no — …">` would make the template pass its own matcher.
- The patched `close_shape_reason` renders with no literal `%%`.
- `bash /tmp/cvf-docs/tools/shapes.sh`, against the current lib:

  | Close | act_missing | verdict_missing | D3 |
  |---|---|---|---|
  | B-no, B-yes, C-no, C-yes (act on line 3) | `[]` | `[]` | 0 |
  | B-no and C-no, naming "remain" | — | — | 1 (H1) |
  | LEFT screenshot | — | `[]` | 0 (H3) |

- The pinned strings in `tests/research-program-exemption-rules.bats:33-37` survive in both patched rules files. The `priority … ⛔` ladder line is still present once in the patched `CLAUDE.rules…` and `CLAUDE.global.md`.

Scratch: `/tmp/cvf-docs/pairs.py` (the edit pairs, which a docs-impl teammate can apply mechanically), `tools/apply.py`, `tools/gen.py` (renders § 4), `tools/shapes.sh`, `d3b.sh`.
