# W2-B1 — would a self-close REFUSAL have refused legitimate retires?

**3 of 44 (6.8 %) — and all three are the `⛔` arm, all three would have been WRONG.
`📦` fires 0/44 and `REMAINDER≠0` fires 0/44. 10 unresolvable.**

| arm of the proposed predicate | fires | of those, legitimate retires refused |
|---|---|---|
| `📦` (unlanded at retire) | **0 / 44** | — |
| `REMAINDER≠0` (frozen-DoD remainder) | **0 / 44** | — |
| `⛔` (open class-C packet this session filed) | **3 / 44** | **3 of 3** |

**Verdict for W3 — split, and the split is the finding.**

- **`📦` + `REMAINDER≠0`: CROSSES 90 (conviction 93).** Measured cost over 44 real retirements is
  exactly zero refusals, and the loss class they guard is the one CLOSE_INTEGRITY already priced
  (62 content-stranded commits across 21 abandoned branches). A guard that costs nothing and
  covers the top measured loss class is a free win.
- **`⛔`: REFUTED as specified (conviction 90 that it must stay annotate-only on a fired peer).**
  Its three fires are its whole population, and every one is a session that did its job: it landed
  its commits, filed the operator's decision as a class-C packet — which is the deliverable the
  brief asked for — and retired. Refusing those closes strands the pane on a question nobody on
  the box can answer, because the operator is away; that premise is the whole exhaustive-drive
  programme. The polarity is structural, not bad luck: `⛔` counts open class-C packets **this
  session filed**, and a fired peer filing one is compliance, not a loose end. `hooks/lib/
  origin-identity.sh` already computes the fired-peer stamp, so the exemption is one predicate.

## The number, and the two ways to get it wrong

| reading | refused / resolvable | unresolvable | verdict |
|---|---|---|---|
| **fields, frozen at-retire ledger, 54 retires** (primary) | **3 / 44 = 6.8 %** | 10 | CROSSES 90 |
| fields, frozen, newest 20 only | 1 / 16 = 6.2 % | 4 | CROSSES 90 |
| **rung** (`RUNG ∈ {📦,⛔,🔧}`), same 54 | **5 / 44 = 11.4 %** | 10 | **STAYS ANNOTATE** |
| brief-literal: `wrap-ledger.sh --machine` run TODAY in each cwd, newest 20 | 1 / 12 = 8.3 % | 8 | CROSSES 90 |

**Reading the RUNG instead of the FIELDS moves the answer across the decision threshold.** `🔧` is
a compound — dirty ∨ gate-stale ∨ `REMAINDER>0` ∨ `FILED_MINE>0` ∨ `DRAIN_SCOPE` ∨ custody. Both
`🔧` retires in the window were raised by terms the rule never named (`wt-35de32d78364`:
`FILED_MINE=1`, `DIRTY=0 AHEAD=0`; `cwdchanged-slot`: `CLOSED_MINE=0`, the drain-scope arm), and
neither had `REMAINDER>0`. W3 must key the refusal on `UNLANDED`/`AHEAD`/`CHERRY`, `BLOCKED` and
`REMAINDER` — never on `RUNG`. `--rung-mode` in the script reproduces the wrong reading on demand,
and the selftest pins the distinction with a `🔧`-from-`FILED_MINE` fixture that must PASS on
fields and REFUSE on the rung.

## Method — re-runnable

▶ `python3 scripts/measure-selfclose-rung.py --limit 54`
(`--selftest` for the 7-case control, `--rung-mode` for the naive reading, `--json` for the rows.)

**The instrument is the transcript, not a ledger run today.** `UNLANDED` is `origin/main..HEAD`;
over a worktree whose HEAD has been frozen since the retire that count can only **shrink** as
origin/main advances, so a session that retired on `📦` reads `✅`/`🚀` today. Every Stop-hook close
emits `RUNG=<glyph>\nREADOUT=…` (often with the machine block) *into* the transcript, so the last
such block before the self-close is the session's own at-retire reading. Staleness of that reading:
**median 56 s, p90 146 s**, one outlier at 2084 s.

A **retire** is a `handoff-fire.sh self-close` Bash `tool_use` with **no `tool_result`** and nothing
but teardown `queue-operation` records after it — a successful self-close kills the pane inside the
tool call. Eight invocations in the window *returned* (e.g. `!! self-close needs $ITERM_SESSION_ID`)
and are attempts, not retires; they are excluded. The invocation regex is anchored so that a brief
merely *quoting* `handoff-fire.sh self-close` — which every fired peer's brief does — is not counted
(memory `pgrep-f-matches-agent-briefs`).

## Population and every excluded stratum

Window **2026-09-08T00:08Z → 2026-09-09T03:47Z** (~28 h), four transcript roots (6,272 `.jsonl`;
2,453 mention `self-close`; newest 400 by mtime scanned; 62 carry a real invocation).

| stratum | n | disposition |
|---|---|---|
| clean retirements via `self-close` | **54** | the population |
| …with a frozen at-retire ledger | 44 | **the denominator** |
| …with none (no `RUNG=` block before the retire) | **10** | **UNRESOLVABLE — never "would pass"** |
| self-close invocations that returned (refused / needed `--session-id`) | 8 | not retires |
| cwd no longer exists (worktree-gc) | 41 of 54 | why the live-ledger method resolves only 12 |
| ORIGIN sessions | **0** | 54/54 are fired peers — see fail direction (d) |

Frozen rung distribution over the 44: `🚀` 21 · `✅` 11 · `👤` 7 · `⛔` 3 · `🔧` 2 · `📦` **0**.

Two of the 10 unresolvable still have a live cwd (`wt-763522029afd`, `wt-9002948eb52c`); today's
ledger reads `🚀 UNLANDED=0` for both and their own close prose says landed and content-verified
(`LANDED f222e3bde → origin/main; content-verified; sweep=clean`). That is corroboration, reported
and **not counted** — the two-verdicts trap (A11-skeptic; memory
`discriminator-scoped-to-a-window-yields-two-verdicts`) is that an unresolvable sensor must never
manufacture a verdict in either direction.

## What a wrong reading would look like — the fail directions

**(a) The one the brief names: a ledger run today over a worktree that has since landed reads `✅`
for a session that retired on `📦`.** Exposure is **all 12** resolvable cwds under the brief-literal
method — not a subset, because `origin/main` advances machine-wide while the retired worktree's HEAD
is frozen, so the drift is **one-directional toward PASS**. Measured on the 10 sessions carrying
*both* readings: the rung differs in 4 (`✅`→`🚀` ×3, `👤`→`🚀` ×1, all live-layer lag accruing after
the retire) but the refuse/pass decision differs in **0**. The frozen instrument avoids the drift
entirely, which is why it is the primary and the live run is reported as the cross-check.

**Can the rung be read from the custody row or the stamp instead? Not today.** A custody row is
`{ts, kind, cwd, originatorPane, targetPane, marker, slug, notifyBack, why, provenance}`
(`bin/cc-custody:16-17`) — no ledger field of any kind. The rank-5 STAMP is precisely the record
that would make this measurement first-class, and it does not exist for any of these 54 retires.
**That is an ordering argument: land the stamp (rank 5) before any refusal**, so W3's own
re-measurement reads a purpose-built field instead of scraping hook output out of transcripts.

**(b) Rung vs fields** — 6.8 % against 11.4 %, i.e. the threshold, decided by which of two
defensible readings of "refuse on 📦/⛔/REMAINDER≠0" an implementer picks. Named above.

**(c) Frozen-reading staleness.** The at-retire block precedes the self-close by a median 56 s; a
state change inside that gap would be invisible. It cannot manufacture a `⛔` (a class-C packet
needs the operator to close it) and the `📦` direction is guarded by the sessions' own close prose.

**(d) The population is 100 % fired peers.** The rule's cost on an **ORIGIN** self-close is
unmeasured here, and the `⛔` exemption argued above is explicitly scoped to a fired peer.

**(e) The unresolvable stratum is large enough to matter.** 10 of 54. If every one of them had
retired on `📦` the answer would be 13/54 = 24 % and the whole item would be refuted. Nothing
suggests that — `📦` is 0 in 44 observed retires and 4 of the 10 self-report a clean landed close in
their own final message — but the bound is honest and the stratum is never folded into "would pass".
