# Critique — contract and gate-integrity lens (adversarial)

Subject: `DESIGN.md` in this directory (and the slots it cites), worktree `close-status-research` at `36afca47f`.
Scratch: `/tmp/rpic-critique-contract/` (`a1run.sh` A1 sandbox, `patch_a1.py` A1-as-specified, `patch_a1r.py` refined
predicate, `a3_fix.json` A3 jq fixture, `delta.py` budget delta). All runs are read-only to the repo and live stores;
the hook sandbox copies `hooks/` + `scripts/lib/` into a fresh `mktemp -d` and uses the `tests/completion-assert.bats`
seams (stub `WRAP_LEDGER_BIN`, `COMPLETION_STATE_DIR`, `COMPLETION_IDL`, hermetic `CC_BACKLOG_BIN`).

**Verdict: revise.** Two items in "implement now" weaken an existing contract as written (A1, A8), one widens a gate's
escape hatch (A3+A4), and the auto-proceed rule (§4) is not consistent with the items that implement it.

## 1. A1 as specified releases the incident-class false done at ⛔ (HIGH)

A1: skip `contra=1` when `close_verdict_polarity "$MSG" = no` **or line 1 or line 2 begins with ⛔**.

Measured (`/tmp/rpic-critique-contract/a1run.sh`, stub ⛔ ledger, BLOCKED=3; ORIG = `hooks/completion-assert.sh`,
A1 = the same file with exactly that predicate patched in at `:1204-1208`):

| case | close (lines 1–2) | ORIG | A1 as specified |
|---|---|---|---|
| k1 | `❌ Good to close: no — research done, implementation pending…` / `⛔ Research done — …` | fired | abstain (intended) |
| k2 | `⛔ Research done — …` / `ACT: …` | fired | abstain (intended) |
| **h1** | `✅ Good to close: yes — nothing of mine is open; follow-on: none` / `⛔ Research done — …` | fired | **abstain** |
| **h2** | `✅ All done and landed — nothing left to do.` / `❌ Good to close: no — …` | fired | **abstain** |
| **h3** | `Everything is done and landed.` / `⛔ Blocked — 3 decision(s) need your call…` | fired | **abstain** |
| c0 | `✅ Good to close: yes — nothing of mine is open` alone | fired | fired |

- h1 is the shape the protocol *mandates* (verdict line 1, rung line 2 — slim:22, `close-shape.sh:179-180`) carrying a
  **yes over open decisions**, i.e. the incident's own close. The "line 2 begins with ⛔" disjunct exempts it. D3 does not
  catch it (`completion-assert.sh:1332-1338`: pre-anchor text `✅ ` has no CA_RETRACT token; no CA_YES_HEDGE word), and D6
  is gated `RUNG ∈ {✅,👤}` (`:1501-1502`), so nothing else fires.
- The design's CONTROL test (`"✅ Good to close: yes — nothing of mine is open" over ⛔ ⇒ FIRE`) is c0: it passes after A1
  while h1 escapes. The control does not cover the realistic shape.
- A1's justification ("verdict-first (D6) already polices a no under a done-reading line 1") is false at ⛔ — the design's
  own interactions table says D6 is off at ⛔. h2 is that case, and it escapes.
- "`close_verdict_polarity` (the lib is loaded at `:991`)" is wrong: `:991` *defines* `_ca_source_close_shape`; it is only
  *called* at `:1529` (inside D6) and `:1611` (D7) (`grep -n _ca_source_close_shape hooks/completion-assert.sh`). A1 must
  source it at `:1204` and must state the fail direction (lib missing ⇒ keep `contra=1`).

**Fix (measured):** skip iff `(polarity = no ∧ ¬close_line_reads_done "$ca_first") ∨ (ca_first begins ⛔ ∧ polarity = none)`;
drop the line-2 disjunct. `patch_a1r.py` ⇒ k1, k2 abstain; h1, h2, h3, c0 fire (same run). Add h1 and h2 as RED controls.
Also update the D7 comment (`:1594-1595`, "Its ledger term above sets contra=1 for EVERY ⛔ close that gets this far"),
whose premise A1 invalidates, and the ⛔ facts string `:1207` ("decision(s) **filed this session**"), which A3 makes false.

## 2. A8 narrows E0 from "read-only turn" to "research" (HIGH)

- slim:34 `Work the turn itself named is not exempt` → `Research that names work is not exempt`; slim:99 `A read-only turn
  that names drivable work is not E0` → `A turn whose research names work is not E0`. A status/Q&A/audit turn that names
  drivable work is no longer covered by either sentence.
- That rule was introduced by `2c882c549` (2026-09-08, exhaustive-drive W0), whose message states "every anchor below is
  replaced by a **superset** of itself". A8 replaces it with a subset.
- Slim vs full divergence: `CLAUDE.global.md:721` keeps "A read-only turn that NAMES drivable work is not E0"; mirroring
  A8 there would delete the general rule from the full variant too. `tests/research-program-exemption-rules.bats:28` pins
  the full row by its `| _E0_ read-only` label, so a label rewrite also breaks that test.
- slim:90 ("omit it on read-only turns") and the E0 lead ("E0, read-only turn: no readout") are untouched, while new E0
  text demands a ❌ verdict and a ⛔ rung on a turn whose only writes are untracked. That leaves the instruction ambiguous.

**Fix:** keep the general subject and add the research clause: "A read-only turn that names drivable work is not E0: …;
research results it cannot drive are filed (`cc-decide open` / `recheck`) so the rung reads ⛔ …". Re-measure the budget.

## 3. A3 + A4 make ⛔ a cheap store-write escape from the 🔧/📦 floors (MEDIUM-HIGH)

- ⛔ is computed first and outranks DIRTY, REMAINDER and UNLANDED (`wrap-ledger.sh:2504-2525`). At ⛔ the ✅-eligible
  branch never runs, so `count_open_custody` (`:2530`), `count_resident_members` (`:2549`), FILED_MINE and the UNCONVICTED
  sum keep their skip/0 defaults (`:1577`, `:1660`, `:1395`). completion-assert's custody, filed and unconvicted terms
  then read 0.
- `session-continue.sh` mechanical arm: `[ "$rung" = "🔧" ] || return 1` (`:1103`). Ship floor:
  `case "$rung" in "📦"|"🚀") … *) return 0` (`:1217`). Both go silent at ⛔.
- Today, reaching ⛔ costs a new class-C packet with 2 options, conviction and receipt, and it is visible in the pile. A4
  lets any session stamp **any** of the 57 open class-C packets (`cc-decide list --open --class C --json | jq length` ⇒ 57)
  with a conviction ≤90 and any receipt. No relevance check exists, and the pile count does not change. completion-assert
  already names this shape as a defect: "every arm of this hook could be DISCHARGED by writing a row" (`:1110-1112`).
- A9's own flow makes the overlap the common path: step 3 "implement each recommendation above 90%", then step 4 "stamp
  every remaining one". The same turn's uncommitted, unlanded or dispatched implementation is masked by the ⛔ line.

**Fix:** rank the *re-check-attributed* ⛔ variant on the ✅-eligible path, below the DIRTY, REMAINDER, UNLANDED, custody
and resident arms. Filed-by-me ⛔ stays first. Alternatively, have the session-continue floors read DIRTY/UNLANDED instead
of RUNG. Require the recheck receipt to be a durable file this session wrote, and the packet id to appear in it.

## 4. A3's literal jq edit contradicts its own control and misattributes UNCONVICTED (MEDIUM)

- The spec widens `$mine` at `:1500` but leaves the `$ask` filter (`:1501-1503`), which reads the **packet's** top-level
  `conviction`/`receipt`/`created`, not this session's recheck entry. Fixture `a3_fix.json` run through the exact program
  ⇒ `ask=1 [aaaaaaaaaaa1]  unconvicted_pkts=1`:
  - P1 (foreign packet convicted; my recheck entry has no conviction) counts as ⛔. That contradicts A3's
    `CONTROL a re-check entry without conviction or receipt does not count`.
  - P2 (foreign packet unconvicted; my recheck convicted) lands in UNCONVICTED_PKTS. That makes the session 🔧 "item(s)
    **you filed** … carry no stated conviction" (`:2570`), and completion-assert's UNCONV term convicts.
  - Live exposure today: 0 of 57 open class-C packets are post-epoch and unconvicted (measured), so the defect is latent.
- TSV collapse: `IFS=$'\t' read` collapses empty fields (`bash -c 'IFS=$'\t' read -r a b c d <<< $'1\t0\t\tfree text'` ⇒
  `c=[free text]`). The comment at `:1497-1498` holds only because both pre-text fields are "always non-empty digits".
  If `OPEN_C_FOREIGN_IDS` rides that TSV before `what` and is empty (the only open packet is mine), `what_plain` shifts into
  the ids variable. BLOCKED_WHAT then falls back to generic text, which breaks A3's `filed-by-me wording byte-identical`
  control, and D8 reads prose as ids.
- **Fix:** compute `$ask` from `(.rechecks[] | select(.sid==$sid))` for re-check-attributed packets. Emit the ids as a
  separate non-TSV output, or use a non-empty sentinel such as `-`.

## 5. A4's refusal tests pass before the fix (MEDIUM)

Pre-fix, `CC_DECISIONS_DIR=$(mktemp -d) bash bin/cc-decide recheck deadbeef0001 --conviction 91 --receipt "x => y"` exits
rc 2 and prints `usage()` (`sed -n '2,/^set -uo/p'`, `bin/cc-decide:79`). That output contains `implement it` (1),
`REFUSED` (1), `--conviction` (2), `--receipt` (2), `unknown id` (1) and `session` (5). So these tests pass vacuously:
"refuses conviction 91 with 'implement it'", "refuses without --conviction or --receipt", "no resolvable sid is refused",
and "refuses an actioned packet (rc 3/2, byte-identical)" (rc 2 is in the accepted set). Only the two append tests fail
before the fix. **Fix:** assert `! [[ $output == *"unknown verb"* ]]`, pin rc 3 for a non-open id, and assert on refusal
strings that `usage()` does not contain (a `cc-decide recheck:` prefix). Note that adding `recheck` to the header
(`:21-46`) puts it into `usage()` too.

## 6. §4 auto-proceed is inconsistent with the items that apply it (MEDIUM)

- **Self-application.** §4 cites `gate-classify.sh:34` as its source for C territory. Its `C_SURFACE` includes `hooks?/`
  and `(edit|modify|change|patch)…hook`. `bash scripts/gate-classify.sh "change hooks/completion-assert.sh …"` ⇒ `C … ("change hook")`.
  The same holds for close-shape.sh and operator-readout.sh. cc-decide and wrap-ledger route `B`. By §4, therefore, A1, A5,
  A6, A7 and A10 are SIGN-OFF and the others DO-UNLESS-VETOED. §7(a) checks only G2 + settings.json, states no per-item
  conviction (F2: "A decision carries a number"), and A5 rests on n=3 fires. Either carve out "source edits landed via
  this repo's standing `/ship`" from C10 in §4, or state the conviction per item.
- **Weaker in the text.** A9 step 3 and D8's reason say "implement … above 90% that touch no **escalation surface**". In
  the rules that phrase is G2 only (slim:38: destructive migration, auth, navigation pattern, DB timeout). §4's sign-off
  set also includes money, credentials, MCD gate classes, third-party contact and publishing.
- **Unimplementable branch.** §4 routes "≤90, no surface" to class B, but A8 ("file the rest … so the rung reads ⛔") and
  A9 step 4 ("stamp every remaining one") send them to ⛔ sign-off. A4's recheck "never changes … class", so an existing
  class-C packet cannot reach class B at all.

## 7. A6 forks the template from its mirrors and same-hunk-conflicts the sibling (MEDIUM)

- The no-form `<what remains + who owns it>` is mirrored at `CLAUDE.global.md:561,929,944`, slim:22, `commands/wrap.md:176`,
  `hooks/lib/why-tier.sh:92,173` and `commands/are-we-done.md:49,61` (`git grep -n 'who owns it'`). A6 edits only
  `close-shape.sh:179`. The lib's own header says two copies "rot apart invisibly" (`close-shape.sh:15-20`).
- Sibling `22c1dbb7a` on branch `cc-004752-67086` (not on trunk; committed 23:33, after DESIGN.md at 23:30) rewrites the
  same line `:179` (both branches: "nothing drivable is open" and "who drives it") and all of those mirrors. A6 rebased on
  it conflicts in the same hunk. The design's "yes branch untouched; sibling's F2 owns it" no longer describes the sibling.
- **Fix:** sequence A6 after the sibling lands, and edit the no-form in every mirror in one commit.

## 8. A5 (D8) contradicts the constraints it claims to honour (MEDIUM-LOW)

- slot-D §5 constraint 1 ("Do not add a prose detector or a lexicon arm") and constraint 2 ("Do not add a
  block-until-store-write terminal gate"), plus the design's §8 rejection. D8 is a lexicon arm (`DONE_READ` lexicon +
  `[0-9]{2,3} ?%|recommend|conviction`), gated on a store fact, whose demand is a store write (`cc-decide recheck`). The
  design should state this as an override with its evidence (3/1,877), not claim it honours the rejection.
- Its predicate is spelled with `\s`. BSD grep accepts it; `/usr/bin/awk` does not (`printf 'follow-on:  none\n' | awk
  '/follow.?on:?\s*none/'` ⇒ no match; the `[[:space:]]` form matches). The hook uses `[[:space:]]` throughout.
- "Adds no fork" is false: polarity (awk), `close_line_reads_done` (sed + 2 grep) and id extraction (grep -o) are processes.
  The hook already overran its `timeout=5` on the incident Stop (`~/.claude/settings.json` Stop entry ⇒ `timeout=5`), and
  fixing that is a settings.json migration (c10, operator).
- CLASS selection for D6+D8 and D7+D8 co-fires is unspecified. With the existing `elif` order (`:1681-1688`), D6+D8 lands in
  `shape`, the budget the design says D8 never shares.

## 9. Glyph and rule-text consistency (LOW-MEDIUM)

- The ⛔ readout sentence is documented only as `⛔ Blocked — need your call: <decision>.` (slim:92, `CLAUDE.global.md:714`,
  `commands/wrap.md:145`). The research variant from A3 is undocumented, and S1 says copy the state clause verbatim.
- The §3 act line `ACT: …` is legal only in `close-shape.sh:223-225`, for GUI/physical acts. Rules S3 (slim:137) and slim:205
  say the marker is literally `▶ Run this:` and "never another verb". Neither variant documents `ACT:`.
- A2 changes `:2492`/`:2998` but leaves `commands/wrap.md:82` (`complete — nothing to do`, the mirror of `:2998`) and
  `CLAUDE.global.md:720`.
- A11's "itemized … never collapsed" would render 56 rows at the incident's N. That breaks slim:176 ("fits one 24-row pane,
  relayed blocks included"), and the `yours` split it mirrors caps at `YMAX=5` with a `↳` rollup
  (`operator-readout.sh:1534-1539`).

## 10. Budget mechanics (LOW)

- `delta.py` confirms a net of −1 UTF-16 unit (edits −13 / +129 / −56 / −61; the design lists the `:160` cut as −57).
- `judge()` refuses `nt > budget ∧ nt > ct` per edit (`hooks/lib/instruction_budget.py:656`), with `enforce: true`
  (`config/instruction-budget.json`). Applying the +129 E0 edit before the cuts is therefore denied in-session. Order the
  cuts first. Any wording drift beyond 1 unit refuses at the land ratchet.

## Bats-test pre-fix check

| item | test | fails pre-fix? |
|---|---|---|
| A1 | honest no / rung-led | yes (k1, k2 fired pre-fix) — but add h1/h2 RED controls (§1) |
| A2 | readout scope string | yes |
| A3 | foreign rechecked ⇒ ⛔ | yes; but the no-conviction CONTROL **fails post-fix** under the literal spec (§4) |
| A4 | 4 of 6 refusal tests | **no — vacuous** (§5) |
| A5 | incident yes ⇒ FIRE pending; cap | yes; the controls are pins |
| A6 | template carries phrase | yes; polarity and anti-deference are pins only |
| A7 | ⛔ header / empty pile | yes (slot C measured) |
| A8/A9 | text greps | yes, but re-asserted-source tests (test-audit class) |
| A10 | phrase swap | yes |

## Not refuted

- A2, A7, A10 weaken no gate. ✅ SAFE TO CLOSE stays inside the `"✅"` arm and the certificate abstains unless `RUNG=✅`.
- The A6 placeholder stays guarded: the nested `<…<…>…>` still matches `^<.*>$` in `real()` (`close-shape.sh:93`), and
  polarity skips `^<` (`:136`).
- No item edits settings.json. The research-program exemption is preserved: D8 reuses `_ca_rp_active` (`:1397`), and the
  pinned program sentence is kept.
