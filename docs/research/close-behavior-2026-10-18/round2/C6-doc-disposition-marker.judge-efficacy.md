# C6 doc disposition marker: adversarial judge, efficacy lens

Round 2, 2026-10-18. Lens: would C6 (presence duty, Drive-state tokens, `undriven` class) have
changed the 2026-10-18 outcome, meaning the waves get driven or the close leads with what remains?
Is gaming cheaper than driving? Does it fire at a Stop that actually runs?

Every number is labelled **[M]** (measured, command named) or **[E]** (estimated, method named).
I worked read-only in the repo. Scratch work is in `/tmp/r2-C6-judge-eff/`: a copy of the
designer's `/tmp/r2-C6/replay` sandbox with its paths rewritten. The designer's copy was not touched.

**Verdict: below-90.** The delivery mechanism works as claimed. But one line in the doc, with no
store write, restores the incident's exact silent IDL row. And the design's 95-point "laundering is
refused" claim holds only for the `dropped:` token.

## 1. What holds (reproduced)

- **The mechanism fires on the incident.** I re-ran the designer's replay on my copy, with the
  original README and the `assert` budget seeded to 3/3. Result: `fired · false-done ·
  arm ledger+handoff · class undriven · rung 🔧 · 1/2`, and the block names the README
  [M: `/tmp/r2-C6-judge-eff/ca.sh /tmp/r2-C6/mut/hooks/completion-assert.sh j-incident-original-… capped`].
  The `undriven` class does get past the starvation that capped the real close.
- **The Stop runs.** The mutant hook took 1.85-2.55 s real at load about 240
  [M: `/usr/bin/time` inside `ca.sh`, 5 runs]. The incident's real completion-assert took 3.35 s
  [M by axis 04]. Adding the designer's warm delta of +0.28-0.41 s, or the cold +0.7 s, still
  lands under the 5 s Stop timeout. The real risk is overload bursts: the 18.1% of runs at 5 s or
  more (README F29), and a 3 s term bound that fails silent.
  P(the term runs and delivers on the incident Stop) ≈ 0.85-0.92 [E: these timings, plus the
  designer's 20+ runs at normal QoS with no timeout].
- **There was an earlier channel too.** The incident agent ran `wrap-ledger.sh --machine` at
  14:27:32Z, 15 s before it closed. With C6 that read would have been 🔧 "…carries no Drive
  state", so the agent would have met the presence duty before writing its ✅ line.

## 2. Gaming is cheaper than driving, and the ≥90 guard covers one token of six

The verifier `_drive_verify` (report A.1) checks only that a referenced record **exists**. It does
not check provenance (this session made it), linkage (the record is about this doc or row), or
state (open, not done). The ≥90 refusal is applied only to `dropped`. I ran each of these doc-level
lines appended to the unmodified incident README, committed and landed in the sandbox, end to end
through the mutant ledger and then the mutant completion-assert, with `assert` at 3/3
[M: `/tmp/r2-C6-judge-eff/ledger.sh <variant> on`, then `ca.sh … capped`]:

| One added line (no other change) | Store writes | Ledger | completion-assert |
|---|---|---|---|
| none (original) | – | 🔧 `DRIVE_UNMARKED=1` | **fired** undriven 1/2 |
| `Drive state: driven 7f64efd — the research pass is the deliverable; implementation is a later pass` (the README's **own add commit**) | 0 | **✅** OPEN 0, DROPPED 0 | **`abstained capped:3>=3 · rung ✅`**, the incident's real IDL row |
| `Drive state: parked 75b041426dba — research only; implementation parked` (a row **another session** filed about load re-measurement) | 0 | **✅** | **`abstained capped:3>=3 · rung ✅`** |
| `Drive state: dropped: research only, implementation is a separate pass` | 0 | 🔧 OPEN 1 (`dropped-at-conviction-95`) | (would fire) |

What these runs show:

- **`driven <sha>` launders every row, including the 95% mailbox-drain fix.** It needs no store
  write, and it leaves no trace: `DRIVE_DROPPED=0`, so not even the "laundering in writing" signal
  survives. The designer built exactly this fixture, `/tmp/r2-C6/fx/incident-driven-sha.md`, with
  18 rows set to `driven 1e7461db7`, the research commit itself, and the parser marks it VERIFY → OK.
  It does not appear in the report's §3.3 table, in §7 risks, or in the conviction table. So the
  report's line "Laundering of the one-line and ≥90 kinds is refused — 95" is **refuted** for this
  kind.
- **`parked` / `filed` accept any 12-hex string found anywhere in the backlog file**
  (`grep -o -F -f -`). That file has 28,574 lines [M: `grep -c .`]. The designer's own "20:05
  fix-up" fixture cites `75b041426dba` on 6 rows. That row was filed by session `87e54489` about a
  load re-measurement [M: `grep 75b041426dba backlog.jsonl | jq`].
- **`fired <slug>` checks against `cc-custody list --json`, run without `--open` or `--cwd`.**
  That reads the whole fleet's custody log: 3,207 rows (open 1,673, return 1,044, abandon 490) and
  **1,613 distinct slugs**, abandoned ones included [M: `cc-custody list --json | jq`]. Any
  historical slug verifies. An empty list also verifies everything (`have_slug="$slugs"`).

**Cost comparison.** The cheapest honest record route is one `handoff-fire.sh` plus one line. The
cheapest launder is one line, with nothing to run. Driving the waves yourself costs far more than
either. So C6 does not make driving the cheapest compliance. It makes "write a token" the cheapest,
and two of the six tokens need nothing real behind them.

**The likely honest path does not change the outcome either.** Filing or parking is the most
common cure for record-discharged blocks. The C3 efficacy judge measured the dispatch-assert
analog: about 58% of true positives filed and about 17% drove [M by C3 judge,
`after_block2.py`, n≈12]. I found one main-transcript FILED_MINE block (bb817b34, 2026-10-14). The
agent re-filed it as `cc-backlog needs` and closed ❌, so it filed instead of driving [M, n=1,
illustrative only]. cc-dispatch made no fires on 10-18 [M by C3 judge], so a filed or parked row
would not have been driven that day. A verified `filed`/`parked` token also returns the rung to ✅,
and the close comes back in the incident's own shape: "✅ Good to close: yes … follow-on: parked
as <id>".

## 3. Gates and caps the replay did not exercise

- **An uncommitted doc edit makes the next close silent.** The block reason ends "write that into
  the doc's Drive state, then re-close", which says nothing about commit or land. I put the
  `to drive` variant in the README without committing it. The ledger read `RUNG=🔧 ·
  DRIVE_SRC=skip`, because the term runs only on the ✅-eligible path. completion-assert gave
  **`abstained capped:3>=3 · class assert`** [M: `ledger.sh keep on`, then `ca.sh … capped`].
  - In the incident state the session-continue ship floor was also spent: `ship-floor-budget` at
    14:19:10Z, and `mechanical-budget` cleared at 13:28/13:34Z [M: IDL grep].
  - So the second forced turn arrives only if the agent lands the edit on its own initiative.
  - The designer's 2/2 step used `ledger.sh`, which commits **and pushes** each variant, so it
    assumed that landing.
- **The literal path spends half the budget on bookkeeping.** The UNMARKED sentence tells the
  agent to add a column "`to drive` until each row is driven…". If the agent does just that, it
  has spent 1/2 on declaring. Only one "drive now" turn is left, and after it the cap is silent
  (designer's sequence, [M]).
- **After the cap, nothing makes the close lead with what remains.**
  - D6's line-1-rung check is gated to `RUNG ∈ {✅,👤}` (`hooks/completion-assert.sh:1428`), so at
    🔧 a "✅ Good to close: yes" line 1 passes.
  - operator-readout renders a DRIVE-caused 🔧 as `🔧 in progress — loose ends`, with no parts
    term (`hooks/operator-readout.sh:1325-1330`, code read). That is the same contentless fallback
    the custody comment at `:1293-1301` calls a defect.
  - The designer marks the parts term **optional** and did not prototype it.
- **The UNMARKED readout names a missing marker, not the remaining work.** "…carries no Drive
  state" does not tell the operator "six waves, one 95% bug fix, undriven". The readability half of
  the incident (INCIDENT question 4) is only half met even when the term fires.

## 4. Net efficacy on the incident

Every probability in this table is an estimate [E]. Each is anchored on the measurements above and
on the C3 judge's dispatch-assert analog. No model was run against the block.

| Link | P |
|---|---|
| The term runs within the Stop and delivers the block | 0.85-0.92 |
| Given the block: fire or drive (at least the ≥90 rows) | 0.30-0.50 |
| Given the block: file or park with a verified id → ✅ again, incident-shaped close | 0.25-0.40 |
| Given the block: one-line launder (`driven <research sha>`, a foreign id or slug, `dropped` on <90 rows) | 0.05-0.15 |
| Given the block: edit without landing → silent | 0.05-0.15 |
| Given the block: text-only, or arguing | 0.05-0.10 |

From those links [E]:
- **The waves get driven or fired: about 0.30-0.45.**
- **Driven, or a close that leads with what remains: about 0.45-0.60.**

The designer's own figure for eliminating the incident class is about 65% [E]. My lens puts the
incident outcome itself below that. The designer's overall 87 also rests on the refuted 95-point
laundering line.

## 5. What would move it toward 90

1. Verify by **provenance and linkage**, not existence:
   - `driven <sha>`: the commit must touch at least one path outside `docs/research/<dir>/` and
     must not be the commit that added the doc. One batched `git log --no-walk --name-only <shas>`
     does this.
   - `fired <slug>`: read `cc-custody list --open --json` scoped to this session's fires (or fires
     since the session start). Treat an empty list as "not fired".
   - `filed`/`parked <id>`: the row's `filedBy` must equal this SID, or the row must be created
     since the session start, and its id must be the row's `id` field, not any substring of the
     file.
2. Extend the ≥90 guard past `dropped`. A row ranked ≥90 is discharged only by a verified
   `driven`, a session-owned open `fired`, or a `decision`. A `parked`/`filed` token on it stays
   OPEN unless its why-not-now class is `needs-credential` or `needs-human`.
3. Put "commit and land the doc edit, then re-close" in both block texts. Better: let the
   presence duty be satisfied on the 📦 path as well, so an unlanded fix-up is not silent behind
   the spent `assert` budget.
4. Do not spend a forced turn on declaration alone. Name the ≥90 rows directly in the UNMARKED
   fire, or set `COMPLETION_UNDRIVEN_MAX=3`, so that one "drive now" turn always remains.
5. Make the operator-readout parts term part of the design, not optional, so a DRIVE 🔧 names the
   doc and its open count to the operator.
6. Run the designer's own behaviour probe: n ≥ 5 sandboxed resumes of the incident with the block
   injected, with the gaming tokens in the table above available, counting fire/drive against
   file/park against launder. Run it after fixes 1-2, because with today's verifier the probe would
   measure the gaming paths.

## Deviations and disclosures

- My scratch directory is `/tmp/r2-C6-judge-eff/`, not `/tmp/r2-C6/`. I used a separate directory
  so the designer's evidence stayed untouched.
- The copied `ledger.sh` runs `git commit` and `git push` inside the sandbox clone
  `/tmp/r2-C6-judge-eff/replay/wt`, pushing to its own bare `origin.git`. Nothing ran in the repo.
- The mutant ledger and hook ran with `CLAUDE_CONFIG_DIR`, `COMPLETION_STATE_DIR`,
  `COMPLETION_IDL`, `CC_IDL` and `TMPDIR` all in the sandbox.
- Live stores were only read: `~/.claude/autonomy/backlog.jsonl` (the mutant's default
  `CC_BACKLOG_FILE`, read with grep), `cc-custody list --json`, and `~/.claude/autonomy/idl.jsonl`
  (grep).
- I scanned transcripts for a FILED_MINE analog with `rg`. Most of the 21 hits were subagents
  quoting the hook source. One real block was examined (n=1).
