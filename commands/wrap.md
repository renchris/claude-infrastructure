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
| 🚀 | landed on trunk, but the ENFORCING STORE does not carry it — `LIVE_ADDS` > 0 (the lag contains files the live layer does not have AT ALL: **no budget**, breaches at lag 1), or the live layer is past its converge budget (`LIVE_SRC=behind` ∧ `LIVE_LAG` > `WRAP_LIVE_BUDGET_COMMITS`, or HEAD older than `WRAP_LIVE_BUDGET_MIN`), or `MIG_FAILED` > 0 | **converge** — `bash <repo>/scripts/deploy-live.sh`, then re-read the ledger. A land moved a git ref; it did not move the bytes the machine runs |
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
`RUNG=` / `DIRTY=` / `UNLANDED=` / `REMAINDER=` / `DOD=` lines.

## Origin final close — the Pyramid contract (CLOSE_INTEGRITY W1, 2026-08-10)

When this is an ORIGIN session (operator-started — no fired-peer stamp; `hooks/lib/origin-identity.sh
oi_origin_class`) closing GENUINE completion (rung ✅/👤) after real written work, the close message
must end with the operator's two standing answers. Render the skeleton from the ONE source and fill
it — never restate it from memory (push and pull share this code path; completion-assert D6 blocks a
shape-missing close, latched + capped):

!`bash -c '. ~/.claude/hooks/lib/close-shape.sh 2>/dev/null || . "$(git rev-parse --show-toplevel 2>/dev/null)/hooks/lib/close-shape.sh"; close_shape_template' 2>/dev/null || true`

Line 1 stays wrap-ledger's rung readout, verbatim. An honest `Good to close: no — <what remains +
who owns it>` satisfies the contract; a hedged both-ways answer does not (D3 owns that defect).
