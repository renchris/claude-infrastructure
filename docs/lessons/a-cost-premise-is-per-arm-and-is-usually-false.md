# A "it would spend the operator's quota" premise is per-ARM, and it is usually false

**The rule.** Before filing a probe as operator-gated on cost, ask which of its arms actually have
to talk to the real service. For a probe about the HARNESS rather than the model, the answer is
usually "the controls only, for a few seconds" — and often "none", because a dummy credential plus a
local endpoint reaches the same code path.

## The incident (claude-infrastructure, 2026-09-17)

`docs/plans/NONLIMIT_RESUME_LADDER.md` task T9 sat **eight days** marked `👤 ON-BOX ONLY`, gating
the plan's last implementation item. Its stated reasons:

> The probe needs a live interactive session whose turn is ended by a forced api error, plus an
> `asyncRewake` hook registered in a settings.json, and **it would spend the operator's quota
> unattended**.

All three parts were softer than they read:

- **The quota half is false for the arms that matter.** Point `ANTHROPIC_BASE_URL` at a local
  endpoint and the FAILING arms never reach the API at all. Only the two controls need the real
  service, one trivial turn each on the cheapest model. Measured total: ~2 haiku turns.
- **The settings.json half never applies.** `--settings <file>` declares hooks for a single run
  without touching the live config, so the C10 "never edit settings.json in place" rule is not in
  play. (It has its own trap — see below.)
- **The credential half dissolves too.** The clean rig needs a throwaway `CLAUDE_CONFIG_DIR` holding
  only the hook under test, and on this fleet that answers `Not logged in` because auth is
  keychain-backed. I filed *that* as needing the operator's call on credentials — and it also was
  not true: **`ANTHROPIC_API_KEY=<any string>` makes the client take the API-key path**, and a local
  two-mode endpoint (a valid SSE turn, or an HTTP error with an `api_error` body) supplies both
  arms. No credential, no quota, and full isolation.

## The trap that made the shortcut necessary

`--settings <file>` **merges with** the live config dir rather than replacing it. So the fleet's own
hooks still run, and in a probe measuring *"was a turn synthesized"* their forced turns are
indistinguishable from the thing under test — one record in the contaminated run read literally
`Stop hook feedback: 🔔 WAKE FLOOR …`. An overlay is fine when you are reading your OWN hook's log
file; it is useless when the observable is the session's own record stream. That is what forces the
throwaway config dir, which is what forces the dummy-key question, which is where the "needs the
operator" conclusion came from.

## Why this is worth a rule rather than a note

A cost premise written at filing time is never re-derived. Nothing re-reads it, no falsifier fires
on it, and its effect is to convert *drivable* work into a row that waits for a human — which is the
most expensive possible outcome for a claim that took one command to refute. The generalisable form:
**a blocker whose stated reason is a RESOURCE is a claim about the experiment's design, and a
different design usually has a different bill.**

## Companion

Related but distinct: [[a-probe-s-unrun-arm-belongs-in-the-verdict-line]] — the same probe's other
failure, about writing a verdict broader than the arms you ran.
