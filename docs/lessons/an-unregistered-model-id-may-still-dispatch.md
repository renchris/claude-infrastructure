# An id missing from the pinned binary is unRECOGNISED, not necessarily unDISPATCHABLE — probe with a live call

**2026-09-28** (evidence `docs/research/sonnet55-utilization-2026-09-28/notes/probe-ultracode-trust.md` §Q1).

The upgrade runbook's binary gate read "new id absent from the pinned binary ⇒ the harness cannot resolve it ⇒
staged". That was true for Opus 5.5 on 2.1.260 — the API refused it BY NAME with a 400 naming the minimum Claude
Code version. It was false for Sonnet 5.5 on 2.1.280: the byte scan found the id 0 times (positive control
present), yet `claude -p --model claude-sonnet-5-5` returned HTTP 200 with the model in `modelUsage`; the only
trace was a client-side `[claude-code:unrecognized_model]` log line. The server gates some releases on the client
version and not others.

What "unrecognised" still costs, so the binary advance was right anyway: the context window the client assumes
(200K, not 1M), alias resolution (`sonnet` still meant Sonnet 5 on 2.1.280), and routing that keys on known ids
(Explore falls back to Opus for an unrecognised session model).

**Rule.** Registration is two facts, not one. The byte scan answers "does the client know this id"; a single live
`-p --model <id> --output-format json` call answers "will the API serve it to this client". Record both, and
decide the staging from what the missing recognition actually breaks, not from the scan alone.
