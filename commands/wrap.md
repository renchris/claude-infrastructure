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

The ledger emits the worst-open FACT rung (priority ⛔ > 📤 > 🔧 > 📦 > ✅):

| Rung | Fact that produced it | Your next verb |
|---|---|---|
| 🔧 | dirty tree ∨ gate stale on HEAD ∨ frozen-DoD remainder > 0 | **continue** — finish · run-gate · commit (explicit paths) |
| 📦 | clean ∧ committed-but-unlanded (`ahead>0` ∨ `git cherry '+'`) | **`/ship`** — and per §Session Close's ship policy you FIRE it yourself in every repo except `reso-management-app`, where each land bills an Amplify + Fly deploy so it stays the operator's call |
| ✅ | clean ∧ not-stale ∧ landed ∧ remainder = 0 | complete — nothing to do |

Two rungs the ledger CANNOT derive from git — they are model-state you overlay when true, and
they dominate the fact rung:

- **⛔ Blocked** — you need a decision (destructive migration / auth / nav / timeout) or external
  info only the operator has. Surface it: `⛔ Blocked — need your call: <decision>.`
- **📤 Handoff** — out of context with work remaining: `📤 Out of context — /handoff.`

**Never emit ✅ from memory.** If the ledger says 🔧 or 📦, the work is not done — drive it (📦 ⇒
`/ship`; ship/land of verified work is the desk's job, not a hold). If it reports **no durable
DoD**, completeness is unverifiable — freeze one (`~/.claude/autonomy/dod/<hash>.md`) rather than
asserting a bare ✅. `--full` prints the dense per-field SESSION LEDGER block.

Machine consumers (Stop hooks) call `scripts/wrap-ledger.sh --machine` and parse the
`RUNG=` / `DIRTY=` / `UNLANDED=` / `REMAINDER=` / `DOD=` lines.
