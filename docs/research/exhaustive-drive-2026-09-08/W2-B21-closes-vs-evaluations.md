# W2-B21 — closes vs evaluations, one definition of "close"

**The unexplained deficit is 0.0 % of closes for five of the six Stop hooks, on every binary
version, over 1,854 closes in 3 days — and the two non-zero residuals are 1.8 % (dispatch-assert,
2.1.260) and 41.1 % (session-continue, 2.1.260), both fully attributed below. C5 is RESOLVED: there
is no unexplained closes-vs-evaluations gap.**

| version | closes | anti-deference | completion-assert | operator-readout | goal-inert-watch | dispatch-assert | session-continue |
|---|---:|---:|---:|---:|---:|---:|---:|
| **2.1.260** | 1,648 | **0.0 %** | **0.0 %** | **0.0 %** | **0.0 %** | **1.8 %** (30) | **41.1 %** (677) |
| **2.1.220** | 186 | **0.0 %** | **0.0 %** | **0.0 %** | **0.0 %** | **0.5 %** (1) | **8.1 %** (15) |
| **2.1.114** | 20 | **0.0 %** | **0.0 %** | **0.0 %** | **0.0 %** | **0.0 %** | **0.0 %** |

Window `2026-09-06T04:00:00Z … 2026-09-09T04:00:00Z`, 202 sessions, 397 in-window transcripts across
the four account roots. The lead's original 14 h window (`2026-09-08T08:22Z … 22:22Z`, 65 sessions,
529 closes) gives the same shape: on 2.1.260, 0.0 % for the five, 3.1 % for dispatch-assert, 23.0 %
for session-continue.

## The two residuals, named

**dispatch-assert — an ATTRIBUTION artifact, not a missing evaluation.** Every one of its unattributed
rows is a `team-assignee:` abstain, and every one of those carries `sid:"?"`: over 3 days,
`(team-assignee, sid unset)` = 34 / 34, `(other, sid set)` = 1,808 / 1,808 — a perfect 1:1 split. The
cause is line ordering: `hooks/dispatch-assert.sh:97` runs the assignee guard's `abstain` **before**
`:101` parses `session_id`, so the row lands with the `SID="?"` initialised at `:60` and cannot join
to a session. The hook evaluated; the join lost it. `hooks/operator-readout.sh:1273-1276` is the same
guard with the parse already moved above it, and its comment states this exact reason — *"SID is
parsed above, before the assignee guard, so that guard's abstain is ATTRIBUTABLE"*. dispatch-assert is
the un-fixed copy of a fix that already shipped in a sibling.

**session-continue — DESIGNED silence, documented in the hook's own header.**
`hooks/session-continue.sh:53-56`: *"Deliberately NOT logged: the disarmed steady state (actuation
with no sentinel). That is the common case on EVERY Stop of EVERY session."* Its 41.1 % is that case.
Two further terms make its raw row count misleading in the opposite direction and are subtracted
before the shortfall is computed: 691 of the 1,514 rows joined to an in-window session are `cli-set` / `cli-clear`
(769 across the whole IDL) — agent Bash calls to `session-continue.sh set "<next step>"`, which are
not Stop evaluations at all —
and 243 of its 2.1.260 shortfall is covered by `hook_cancelled` timeout kills. Net of both, on
2.1.260, 762 Stop-path rows stand against 1,612 observed Stop receipts — 850 Stops with no row, which
is the documented steady state.

## Method — one committed script, one command

```
python3 scripts/measure-close-vs-idl.py --from 2026-09-06T04:00:00Z --to 2026-09-09T04:00:00Z \
        --count-excluded --crosscheck
python3 scripts/measure-close-vs-idl.py --selftest      # 17 cases, incl. the 4 KB-record trap
```

`scripts/measure-close-vs-idl.py` (committed, with the selftest). Three populations, kept apart:

- **END_TURN** — every main-chain assistant record with `message.stop_reason == "end_turn"`. The
  critic's C5 definition.
- **CLOSE** — END_TURN restricted to turn-final, byte-for-byte `scripts/measure-closes.py`'s rule
  (collapse consecutive assistant records sharing `message.id`; no `tool_use` block; the next
  assistant/user event is neither an assistant record nor a `tool_result`). `--crosscheck` re-counts
  through that module's own `extract_closes`.
- **STOP receipt** — a `type:"system", subtype:"stop_hook_summary"` record. The harness's own receipt
  that the chain ran, naming every hook in `hookInfos`. Nothing before this measurement used it.

`shortfall(hook) = Σ_sessions max(0, closes − Stop-path rows)` — **session-wise**, so one session's
shortfall can never net against another's excess (the netted form printed misleading negatives).
Then `unexplained = shortfall − write-failed − no-receipt`, where **write-failed** is a
`hook_cancelled` attachment with `hookEvent:"Stop"` for that hook (the hook ran, was killed at its
timeout, its row never landed) and **no-receipt** is a close for which no `stop_hook_summary` exists.

The IDL is read **line by line with `json.loads`, never `jq -s`** (B17): one 4 KB `autonomy-sweep`
record aborts a slurp mid-archive and the census then reads short and clean. Over 3 days that reader
crossed **2 unparseable lines / 6,812 bytes** out of 297,914 and reported them as their own stratum
instead of stopping. Sources: the live `idl.jsonl` plus every rotated `.gz` whose rotation stamp is
later than the window start.

## Population and every excluded stratum

| stratum | 14 h window | 3 d window | disposition |
|---|---:|---:|---|
| in-window transcripts, `<root>/<project>/*.jsonl` | 139 | 397 | the corpus |
| sessions (distinct `sessionId`) | 65 | 202 | mixed-version: 0 |
| CLOSE (turn-final END_TURN) | 529 | 1,854 | the denominator |
| END_TURN not turn-final | 1 | 3 | excluded — no Stop occasion by construction |
| turn-final with `stop_reason != end_turn` | 4 | 36 (34 `stop_sequence`, 2 `tool_use`) | excluded — `measure-closes.py` counts these, so its total is 1.9 % wider (1,890) |
| sidechain records inside main-chain files | 0 | 0 | excluded by `isSidechain` |
| **subagent transcripts (`…/<sid>/subagents/agent-*.jsonl`)** | **5 files / 1 end_turn** | **11 files / 2 end_turns** | **structurally outside the glob — see the fail direction** |
| IDL rows whose sid has no in-window transcript | 187 | 304 | reported, never counted into any hook's rows |
| IDL parse failures | 0 | 2 lines / 6,812 B | own stratum |
| IDL rows from a CLI (non-Stop) path | 308 | 769 | subtracted from session-continue before the shortfall |

## Why a ~14 % deficit appeared — and the evidence that separates it from the struck causes

**The gap is a close-DEFINITION artifact: counting transcript RECORDS instead of messages.** One API
response is written to the transcript once per content block (MEMORY.md
`transcript-lines-repeat-one-billed-response`), and every one of those records carries the same
`stop_reason`. Measured on the identical corpus, inside the critic's own window
(`08:22Z … 19:02Z`, the same 139 in-window files that reproduce their session count of 128 + 11 exactly):

| close definition | closes | anti-deference rows | deficit |
|---|---:|---:|---:|
| per **record** (`stop_reason == end_turn`, un-collapsed) | 416 | 376 | **40 = 9.6 %** |
| per **message** (collapsed on `message.id`) | 377 | 376 | **1 = 0.27 %** |

Definition alone moves the deficit by an order of magnitude, at the magnitude in dispute, on the same
clock and the same files. Nothing outside the definition is needed to produce a double-digit gap.
This separates cleanly from the two causes the critic struck:

- **not the rotation boundary** — the identity is not exact in either direction at any read; the
  residual after real strata is 0, not a coincidence of counts.
- **not 2.1.220** — 2.1.220 carries 186 closes over 3 days and its unexplained residual is **0.0 %**
  on five hooks. Its *raw* deficits are large (completion-assert 73, operator-readout 135) and are
  **entirely `hook_cancelled` timeouts** (66 and 128) — a real and separate finding, an execution
  problem on those four old processes, not a missing-evaluation one.
- **not `agent-*` files** — refuted twice over: by construction (the glob is one level deep;
  subagent transcripts sit at depth 4) and now by magnitude (11 files, **2** end_turns in 3 days).

**Honest limit.** I could not reproduce the critic's absolute figures (2.1.260: 632 closes / 542
rows). Over the file set that matches their session count exactly, in their window, I measure 416
records / 377 messages / 376 rows. Their corpus or record filter is not reconstructable from what is
on disk; the ratio they reported (rows/closes = 0.858) is close to the per-record ratio measured here
(376/416 = 0.904) and far from the per-message one (376/377 = 0.997).

## Verdict for W3

**C5 RESOLVED — conviction 96 %.** The deficit is not evidence of Stop hooks failing to evaluate. On
one stated definition, five of six hooks show a 0.0 % unexplained residual on every binary version,
and the two non-zero residuals have named, verified causes.

W3 consequences, in the order they matter:

1. **A 1-line ordering fix in `hooks/dispatch-assert.sh`**: move the `SID=` parse (`:101`) above the
   assignee guard (`:88-99`), matching `operator-readout.sh:1273-1276`, which already carries the fix
   and the reason. 34 rows / 3 days become attributable; no behaviour changes. Conviction **94 %**.
   This is instrumentation, not a gate.
2. **No remedy for session-continue's 41.1 %** — it is the documented design, and the row that would
   remove the ambiguity (`ship-floor-not-mine`) already exists. Any future census of this hook must
   subtract `cli-*` rows first; 769 of 1,513 rows over 3 days were agent CLI calls, not evaluations.
3. **The real 2.1.220 finding is timeouts, not silence.** 66/73 completion-assert and 128/135
   operator-readout shortfalls on 2.1.220 are `hook_cancelled` kills. That is B15's population
   (`hook_cancelled` as a counted `wrap-ledger` term) and it should be read against those four old
   processes, not against the fleet.
4. **B21's own conviction (85) is discharged** — it was a measurement row and the measurement is done.
   Nothing in the implement-now set depends on a deficit that does not exist.

## What a wrong reading would look like (the fail direction)

**Counting an `agent-*` transcript's end_turns as closes re-creates the 14 %.** This walk excludes
them structurally, not by a filter that could be forgotten: `iter_transcripts` globs
`<root>/<project>/*.jsonl`, one level deep, while subagent transcripts live at
`<root>/<project>/<sid>/subagents/agent-*.jsonl`, four levels deep. `--count-excluded` measures what
that excludes rather than asserting it: **11 files and 2 end_turn records** in the 3-day window
(5 files / 1 end_turn in the 14 h window), out of 3,744 such files on disk. Adding all of them would
move a 1,854-close denominator by 0.1 % — so A09's attribution fails on magnitude as well as on
construction.

The second wrong reading is the one that produced the number in dispute: **counting per record rather
than per message**, which inflates closes by 12.8 % (598 records vs 530 messages in the 14 h window)
while the IDL side is unaffected — a deficit manufactured entirely on the numerator.

The third is subtler and is why the netted table was replaced: **letting one session's excess rows
cancel another's shortfall**. Netted, anti-deference reads −3.7 % (an impossible "surplus") while
sessions with genuine shortfalls sit underneath it. Session-wise, both are visible: shortfall 14,
excess 2.
