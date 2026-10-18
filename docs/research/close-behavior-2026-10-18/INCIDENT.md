# Close-behavior incident, 2026-10-18 — "Good to close: yes" over undriven follow-on work

Scope (frozen): find why agents declare "good to close" (or idle) while researched follow-on work or
implementation is still drivable, and why closes do not lead with what remains; then build and land
the fixes (rules, hooks, ledger, close contract) so a session continues exhaustively until no
drivable research or implementation remains, and a close names any remaining work first.

## The incident (session 5759497b, pane 398, worktree wt-cc-004752-67086)

- Transcript: `~/.claude-secondary/projects/-Users-chrisren-Development--worktrees-wt-cc-004752-67086/5759497b-3947-4fd7-9d8b-e095bf134dbf.jsonl`
  (earlier part of the same session ran on `~/.claude-quaternary`, same uuid).
- 09:19 local: after landing a 25-agent startup-hooks study (`docs/research/startup-hooks-2026-10-18/README.md`,
  landed `55f4d910b` + `1e7461db7`), the session closed with:
  `✅ Good to close: yes. Nothing of mine is open. Follow-on: the implementation waves in README §5
  haven't started, because this pass was research only.`
  README §5 held six agent-drivable implementation waves (Waves 1-5, 7), several at ≥85% conviction,
  one bug fix at 95% (mailbox-drain losing peer mail). Nothing was driven, filed or fired.
- Operator, verbatim: "Yes here is a 'good pause point to close' but this is detrimental for not
  clearly surfacing this for agent continuation behavior or leading with the answer user
  readability. There is no net positive if research is done but its not enacted on."

## Earlier instances in the same session (same pattern, smaller)

1. After diagnosing the missing startup board, the reply ended "I didn't change anything. The fix is
   … I'm about 70% sure" — no research to raise conviction, no drive.
2. Asked "should we investigate startup hook performance?", the reply listed "What I'd do, in order"
   (steps 1-3, step 1 at >90% conviction) and stopped instead of doing step 1.
3. Asked "should we investigate the load / make a skill?", the reply recommended both and again
   stopped without starting either.

## Mechanisms that fired, and what they were blind to

- `session-continue.sh` ship floor (2x) and `completion-assert.sh` (3x) all fired on LANDEDNESS
  (committed-but-unlanded). None fired on "a doc this session wrote lists undriven implementation".
- The `Scope (frozen): research only …` line written at intake was then used as the reason the
  implementation was out of scope — the frozen-DoD mechanism legitimised the stop.
- The close contract's line 1 (`✅ Good to close: yes — …; follow-on: …`) let undriven work ride in a
  trailing clause of a YES verdict. `wrap-ledger.sh` computed ✅ from git state alone.
- Memory `a-plan-is-not-a-queue.md` already records that nothing reads plans for unfinished work and
  the rung cannot see the frozen DoD.

## Questions for the research session

1. Root cause: which rules/hooks/contract text make "yes" reachable with drivable follow-on? Census
   across recent transcripts: how often a ✅/"Good to close: yes" close carried a non-empty follow-on
   or was followed by operator pushback.
2. Detection: how can the ledger/Stop hooks see undriven follow-on (research docs with implementation
   waves, "next steps", plan rows) without an always-firing alarm?
3. Continuation: what makes a session keep going (drive, fire a session, or hand off) instead of
   idling or offering, when drivable work remains — including after a "should we …?" question.
4. Readability: a close must lead with the answer the operator needs — what is still open and who is
   driving it — not with a verdict that reads as done.
