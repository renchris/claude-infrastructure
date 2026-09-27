# An operator step a fired session files is the FIRER's open item

**2026-09-27.** A lead's close ledger read ✅ over an operator step that was still open, because
the step had been filed by a session the lead fired rather than by the lead itself.

## What happened

Session `5714603f` fired `938aab39` to do part of its work. The peer found an operator-only step
(top up the Vercel account) and filed it to the backlog as `f8f12233f417`, under its OWN session id,
then finished and retired. The lead had filed the same step itself as `c2e6da511e79`. While
de-duplicating, the lead closed its own copy in favour of the peer's. Its ledger went 👤 → ✅,
and the step the operator still had to run was now owned by no live session: the peer had retired,
and the lead's 👤 rung counted only rows whose `.session` was the lead's own id.

## Why it was invisible

`scripts/wrap-ledger.sh` `count_operator_steps` selected `(.session // "") == $SID`. That is the
right scope against the machine's standing pile (a rung that counted all ~200 blocked rows would
fire at every close), but delegation moves work across session ids. The fired-peer stamps
(`~/.claude/cc-fired/<pane>.json`) recorded who fired whom only by PANE — `firedBy` and
`originator` hold a pane number — and panes are reused, so no reader could say which session fired
a peer. The self-close orphan inventory in `scripts/handoff-fire.sh` had the same blindness: its
`.firedBy == our sid` compare was really pane-to-pane and counted every peer any earlier session in
that pane had ever fired.

Census over the prior 30 days (measured 2026-09-27): **83 of 688 operator steps (12%) were filed
by fired sessions; 10 of those were still open.**

## The fix

- The stamp writer records `firedBySid`, the firing session's id (`FIRING_SESSION_SID`, only
  trusted when the fire anchors on the caller's own pane).
- `scripts/lib/fired-peers.sh` is the one matching rule: a stamp is this session's when
  `firedBySid == $SID`; a legacy stamp (no `firedBySid`) is this session's only when
  `firedBy == our pane` AND `firedAt >= our session's start`. The time guard is mandatory — without
  it a later session in the same pane inherits an earlier one's peers.
- 👤 counts rows filed by this session OR by a session it fired, and says how many came from peers:
  `👤 … N step(s) need you, M filed by sessions you fired`.
- The orphan inventory uses the same rule.

## The rule

An operator step a fired session files is the firer's open item until it is run. When
de-duplicating a step filed by both the lead and its peer, keep the LEAD's copy open and close the
peer's — never the other way round: the lead's session is the one still alive to be asked about it.
