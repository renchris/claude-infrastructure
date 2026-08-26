---
description: Session-Close ledger from LIVE git/gate/DoD reads (never self-report)
disable-model-invocation: false
allowed-tools: Bash(scripts/wrap-ledger.sh*), Bash(*/wrap-ledger.sh*), Bash(hooks/operator-readout.sh*), Bash(*/operator-readout.sh*), Read
argument-hint: [--full]
---

Compute the Session-Close readout from FACTS, not memory. This is the "un-fakeable ledger"
the resident CLAUDE.md §Session Close Protocol refers to: `scripts/wrap-ledger.sh` runs the
git/gate/DoD reads itself, so the rung reports ground truth.

## Run

- Default (one-line readout): !`scripts/wrap-ledger.sh 2>&1 || true`
- Goal liveness (◎ — prints NOTHING unless a `/goal` is live): !`scripts/wrap-ledger.sh --goal 2>&1 || true`
- Full ledger (with `--full`): !`[ "$ARGUMENTS" = "--full" ] && scripts/wrap-ledger.sh --full 2>&1 || true`
- Operator steps (silver-platter block): !`hooks/operator-readout.sh --render 2>&1 || true`

(If the repo root differs, the launcher resolves the script under the repo — `scripts/wrap-ledger.sh`.)

⚠️ **The `👤` rung and the `yours` step class are NOT computed on this pull path.** Both count
operator-only steps filed by THIS session (`cc-backlog needs`), which requires the session id — and
`CLAUDE_SESSION_ID` is **unset** in a shell (verified 2026-08-01). Only the Stop-hook path resolves
it, from the hook's own stdin JSON. So `/wrap` reports `YOURS_SRC=none` and a rung of at most `✅`,
where the Stop hook would correctly say `👤`. Deliberately NOT guessed from
`<config-dir>/projects/<hash>/.last-session-id`: that file holds whichever pane wrote LAST, so in
this repo's normal multi-session state it would attribute a SIBLING session's steps to you — a false
`👤` is worse than a missing one, because the whole point of the rung is that the operator can trust
it. Read the Stop-hook block as authoritative for what is yours; `/wrap` is the git/gate view.

The operator-steps block is the SAME renderer the `operator-readout.sh` Stop hook pushes at turn
close (one code path — the push and pull surfaces cannot drift): one state line, then the collapsed
step lines from disk truth — `▶ cc-do` for everything runnable (deploy-lag · pending activations),
one `◆ <n> …` counted line per judgment class (open decisions · blocked backlog), each naming up to
3 ids and carrying its exact listing command. Relay it VERBATIM at the top of your close — never
paraphrase the commands into prose (the silver-platter rule).

**Hand over ONE command, not a list.** Whatever the block shows, the operator gets a single fenced
thing to paste — `cc-do` runs the runnable set after one confirm (`cc-do --list` to look first,
`cc-do <stem>` for exactly one). Per CLAUDE.md §Session Close, the close itself is capped at the
governing line + ≤3 supporting facts + that one command block.

## Read the rung, then act on it

The ledger emits the worst-open FACT rung (priority ⛔ > 📤 > 🔧 > 📦 > 🚀 > 👤 > ✅):

| Rung | Fact that produced it | Your next verb |
|---|---|---|
| 🔧 | dirty tree ∨ gate stale on HEAD ∨ frozen-DoD remainder > 0 | **continue** — finish · run-gate · commit (explicit paths) |
| 📦 | clean ∧ committed-but-unlanded (`ahead>0` ∨ `git cherry '+'`) | **`/ship`** — auto-fired by default in every repo per §Session Close's ship policy; held back to an OFFER only where the TARGET repo's own `CLAUDE.md` says landing spends money (a perishable fact this file deliberately does not restate — read that repo's `CLAUDE.md` + its status tool; the old reso hardcode here went stale in three days) |
| 🚀 | landed on trunk, but the ENFORCING STORE does not carry it — `LIVE_ADDS` > 0 (the lag contains files the live layer does not have AT ALL: **no budget**, breaches at lag 1), or the live layer is past its converge budget (`LIVE_SRC=behind` ∧ `LIVE_LAG` > `WRAP_LIVE_BUDGET_COMMITS`, or the commit **the live layer is on** older than `WRAP_LIVE_BUDGET_MIN` — that arm read this session's own HEAD until 2026-08-26, which made it strictly weaker: an active session resets it at every commit), or `MIG_FAILED` > 0 | **converge** — `bash <repo>/scripts/deploy-live.sh`, then re-read the ledger. A land moved a git ref; it did not move the bytes the machine runs |
| 👤 | landed ∧ operator-only step(s) THIS session filed are unrun | surface the `OPERATOR ▸` block — **not computed on this pull path**, see above |
| ✅ | clean ∧ not-stale ∧ landed ∧ remainder = 0 | complete — nothing to do |

`🚀` **is** fully computed on this pull path, unlike `👤`: it reads the live checkout's git state plus
the migrations ledger, needing no session id. It is BUDGETED **for an EDIT** — lag *inside* the
converge budget is a normal `✅` carrying a converging note, so the rung does not fire at every close
after a land. **An ADD is not budgeted at all.** `~/.claude` is per-file symlinks into the live
checkout, so an edited file rides its link and merely runs OLD at lag N, while a file the landed diff
ADDS has no link and is in no tree the box can reach: every `[ -f x ] && . x` / `command -v fn` guard
silently skips, and the feature is a no-op rather than a stale one. `LIVE_ADDS` > 0 therefore breaches
at lag 1 (2026-08-09, backlog `99b715f31a98` — measured on `scripts/lib/pane-spawn-log.sh`, where this
ledger read "BEHIND 7, within budget (25)" over a feature that was doing nothing at all).

**The budget has TWO arms and the ledger now says WHICH one decided** (2026-08-26, recycle #236).
`LIVE_BREACH_WHY` carries `migration` · `diverged` · `adds` · `commits` · `time` out of the ladder
that computes the rung, so a TIME breach no longer renders in COMMIT units — it used to read "the
live layer is 1 commit(s) behind and past its converge budget" against a commit budget of 25, which
contradicts itself and contradicts `deploy-live.sh`'s own banner over the identical lag (the two arms
genuinely disagree for up to an hour, because that one truncates its hours to integers and trips at
an effective 7h). And the clock itself now takes `?` when it cannot be read: `LIVE_AGE` is the age in
seconds of the commit the live layer sits on, and a failed read used to leave 0 — the *freshest*
value expressible, so a dead sensor cleared the close and the readout said "inside the time budget"
about a comparison nothing had made. Both live-side reads go through one bound against one repo, so
they fail together; the added-file read runs in YOUR repo and is what still answers.

## ◎ Goal liveness — is your `/goal` actually being EVALUATED?

**Not a rung, and deliberately so.** A live `/goal` is a normal state of a working session, so a
rung on it would fire at every close of every goal-armed session (the alarm-polarity law that
bounds `👤`/`⛔`/`🚀`). What the `◎` line adds is a MEASUREMENT nothing else on disk carried:
`/goal` registers a `type:"prompt"` Stop hook, and CC deletes it for the duration of any Stop where
the task registry holds non-terminal background work — restoring it in a `finally`, so the registry
reads healthy before and after and is wrong only *during*. Measured across 84 goal sessions, **47
had ZERO evaluations**, and that class could not be decomposed after the fact: a goal deferred
behind a real subagent or build is the mechanism working as designed, a goal starved for hours
behind a parked 4-hour `cc-await-ping` is the defect, and nothing distinguished them
(`docs/research/goal-safe-2way-comms-2026-08-13.md` §2, E5 → §9 B5).

The oracle is two facts, both already in the transcript — how many NON-SENTINEL `goal_status`
attachments (evaluations) exist **since the last arm**, and what the most recent one said:

| What you see | What it means | What to do |
|---|---|---|
| `◎ goal: 0 evals · armed@12:31 (142m ago) — armed but NEVER judged` | the **starvation pole**: the goal has been live for over two hours and the evaluator has never run | look for the parked background task deferring it (`goal-inert-watch` names it when it can); kill it, or keep the session going with `~/.claude/hooks/session-continue.sh set "<next step>"`, which the deferral cannot touch |
| `◎ goal: 3 eval(s) · last unmet@14:07 (12m ago)` | healthy — the goal is being judged, and it is not met yet | nothing; the count is the evidence the mechanism is live |
| a high count over a world that has not changed | the **spin pole** (measured worst case: 90 unmet evaluations in 76 minutes, one forced turn every ~51s) | 82% of met goals are met on evaluation #1 and the met rate falls to 27% at ≥10 — re-judging an unchanged world is grinding, not converging. Re-scope the condition or clear it |
| *(nothing printed)* | no `/goal` is live in this session | nothing |

`--full` carries the same fact as a `Goal (◎):` row in **every** state — including `none armed in
this session` and `unknown` — because a row that vanished on the quiet cases would answer "is this
being judged?" with a silence indistinguishable from a broken reader. `--machine` emits
`GOAL_SRC` / `GOAL_EVALS` / `GOAL_LAST` / `GOAL_LAST_T` / `GOAL_AGE_MIN` / `GOAL_LINE`.

Unlike `👤`, this **is** computed on the pull path: with no `--transcript`, the ledger resolves one
from `$CLAUDE_CODE_SESSION_ID` (set in a tool-call shell, where `$CLAUDE_SESSION_ID` is not). That
is not the `.last-session-id` guess rejected above — the harness names the calling session itself,
and a miss can only fail to find a file, never attribute a sibling's goal to you. The Stop path
never does that search: it uses the `$WRAP_TRANSCRIPT` it already exports for the memo key.

Two rungs the ledger CANNOT derive from git — they are model-state you overlay when true, and
they dominate the fact rung:

- **⛔ Blocked** — you need a decision (destructive migration / auth / nav / timeout) or external
  info only the operator has. Surface it: `⛔ Blocked — need your call: <decision>.`
- **📤 Handoff** — out of context with work remaining: `📤 Out of context — /handoff.`

**Never emit ✅ from memory.** If the ledger says 🔧, 📦 or 🚀, the work is not done — drive it (📦 ⇒
`/ship`; 🚀 ⇒ run the converger, then re-read; ship/land of verified work is the desk's job, not a
hold). Enumerate the rung you actually got: a rung missing from this list must NOT fall through as
"done" — that is the fail-OPEN direction, and it is how a close asserted `✅ Complete & live on
trunk` while the machine ran older bytes. If it reports **no durable DoD**, completeness is
unverifiable — freeze one (`~/.claude/autonomy/dod/<hash>.md`) rather than asserting a bare ✅.
`--full` prints the dense per-field SESSION LEDGER block.

Machine consumers (Stop hooks) call `scripts/wrap-ledger.sh --machine` and parse the
`RUNG=` / `DIRTY=` / `UNLANDED=` / `REMAINDER=` / `DOD=` lines. Those seven call sites are ONE Stop
event, so they pass `--transcript`/`$WRAP_TRANSCRIPT` and share one memoized snapshot (measured
2026-08-11: 133 → 19 git subprocesses per close; `scripts/wrap-ledger-memo-bench.sh` re-runs it).
**`/wrap` itself passes no transcript and therefore always computes** — a pull surface the operator
invoked is a fresh question, not a replay of the last Stop.

## Origin final close — the Pyramid contract (CLOSE_INTEGRITY W1, 2026-08-10)

When this is an ORIGIN session (operator-started — no fired-peer stamp; `hooks/lib/origin-identity.sh
oi_origin_class`) closing GENUINE completion (rung ✅/👤) after real written work, the close message
must end with the operator's two standing answers. Render the skeleton from the ONE source and fill
it — never restate it from memory (push and pull share this code path; completion-assert D6 blocks a
shape-missing close, latched + capped):

!`bash -c '. ~/.claude/hooks/lib/close-shape.sh 2>/dev/null || . "$(git rev-parse --show-toplevel 2>/dev/null)/hooks/lib/close-shape.sh"; close_shape_template' 2>/dev/null || true`

Line 1 stays wrap-ledger's rung readout, verbatim. An honest `Good to close: no — <what remains +
who owns it>` satisfies the contract; a hedged both-ways answer does not (D3 owns that defect).

## The act line (CLOSE_SCANNABILITY W2, 2026-08-23)

When the rung is `👤`, one line — inside the first 3 non-empty unfenced lines — must BE the single
next physical act, and nothing else may be that line. Same one-code-path rule as above (push =
completion-assert D7, pull = here):

!`bash -c '. ~/.claude/hooks/lib/close-shape.sh 2>/dev/null || . "$(git rev-parse --show-toplevel 2>/dev/null)/hooks/lib/close-shape.sh"; close_act_template' 2>/dev/null || true`

Measured over 300 closes (`docs/research/close-scannability-2026-08-23.md`): when the act is its own
line the operator acts 35% of the time; welded into a sentence, 9%; **welded into line 1, 4% — the
worst case of all**, so moving it earlier is not the fix, making it a line is. A fenced block (the
rendered `OPERATOR ▸` readout, reproduced verbatim per the Silver-Platter rule) is skipped by the
matcher and does not count against the window — relaying it neither satisfies this nor costs you.
