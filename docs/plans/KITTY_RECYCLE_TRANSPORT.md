---
status: complete
---

# KITTY_RECYCLE_TRANSPORT — `--recycle` and `self-close` cannot type `/exit` in a kitty pane

**Status:** COMPLETE · filed 2026-09-17 · fixed, landed and converged the same day.
**Scope (frozen):** make `handoff-fire.sh --recycle` and `self-close` deliver `/exit` to a kitty
pane, land it on `origin/main`, and converge it to the live layer. No behaviour change on iTerm2.

---

## Phase 0 — Agent Team Orchestration

**EXECUTION LOCUS: S — one dispatched handoff session** (the default; no justification required).
The work is one subsystem, one file pair, with a heavy existing test surface — it does not decompose
into independent parallel tracks, and a teammate wave would put the whole merge loop in a lead's
context for no gain.

| Wave | Locus | Owner | Deliverable | blockedBy |
|---|---|---|---|---|
| W1 | S | the dispatched session | Reproduce + confirm the mechanism below on this box | — |
| W2 | S | same | Decide the fix site (see § Design fork) and record the decision here | W1 |
| W3 | S | same | Implement + tests | W2 |
| W4 | S | same | Land on `origin/main`, then `bash scripts/deploy-live.sh` | W3 |

**Lead context budget:** this is a single-session job; recycle at the § Context Stewardship
thresholds and continue rather than spawning a team.

---

## The defect

`handoff-fire.sh --recycle` **never completes in a kitty pane.** It arms its relaunch watcher, fails
to type `/exit`, kills its own watcher, and exits 1 — leaving the session alive and the operator
hand-driving the succession. `self-close` fails by the same path.

Measured 2026-09-17 on pane 17 (`TERM=xterm-kitty`, `KITTY_WINDOW_ID=17`,
`KITTY_LISTEN_ON=unix:/tmp/kitty-73832`), two consecutive real `--recycle` attempts.

### Mechanism

1. `in_kitty()` — `scripts/handoff-fire.sh:966` — is TRUE here (`KITTY_WINDOW_ID` set,
   `IT2_WRAPPER_NO_KITTY` unset), so `as_write()` (`:1394`) takes its kitty branch.
2. That branch routes the text through
   `"${REAL_IT2:-$HOME/.claude/bin/it2}" session run -s <pane> "<text>"`. Its own comment asserts
   this is *"byte-for-byte the transport every other kitty caller in this repo already uses
   (text + \r, --match id:<n>)"*.
3. **That assertion is stale.** `bin/it2-kitty`'s `run` verb is **launch-and-verify**: it sends the
   text, then waits `VERIFY_S` (20s) for evidence that an *agent started*, and otherwise errors at
   `bin/it2-kitty:356` — `pane <n> never picked up its launch command within 20s — the agent did
   NOT start.`
4. `/exit` **by definition starts no agent**, so the verification can never pass. `as_write` returns
   non-zero 3×, and `:11733` (recycle) / `:8127` (self-close) kill the armed watcher and abort.
5. `bin/it2-kitty` exposes only `split` (`:882`), `list` (`:1019`), `run` (`:1076`), `close`
   (`:1106`). **There is no send-only verb** — that is the actual gap.

### Two things that are NOT the cause (ruled out on the box)

- **Not the kitty control channel.** `kitty @ --to unix:/tmp/kitty-73832 ls` returns panes
  16, 17, 33, 13, 6, 32; `it2-kitty session list` sees pane 17. The read path is healthy.
- **Not the `it2` shim indirection.** Re-running the recycle with
  `REAL_IT2=$HOME/.claude/bin/it2-kitty` fails identically. It is the verb, not the wrapper.

### A second, separable defect — the error message lies

Both call sites print *"BOTH transports failed 3x (osascript AppleEvents and the it2 shim's session
run)"*. When `in_kitty` is true the kitty branch `return`s early and **AppleEvents is never
attempted**. The message sends the next reader hunting a transport that did not run — the exact
failure class the comment at `:8124` says it was written to prevent.

---

## W1 CORRECTION — the mechanism above is right about the SYMPTOM and wrong about the CAUSE

**Measured 2026-09-17 in the dispatched session, both arms, before any edit.** §5 of the diagnosis
says *"`bin/it2-kitty` exposes only `split`, `list`, `run`, `close`. There is no send-only verb —
that is the actual gap."* Both halves are false, and the second one sent the fix at the wrong file.

- **`send` has existed all along** (`bin/it2-kitty:1062`), and so do `focus` and `read`. `send` is
  text with NO newline, which is why it is not what `as_write` needs — but "there is no send-only
  verb" is not the reason.
- **`run` does not always launch-and-verify.** Its three dispositions are named in its own comment:
  ARMED ⇒ `deliver_argv` (the 20s proof at `:356`), TUI ⇒ `type_verified` abstains and the text is
  typed, SHELL ⇒ verified typing. **Only the ARMED branch reaches the proof that failed.** On a pane
  that is not armed, `run -s <id> "/exit"` types `/exit` and submits it, today, unchanged.

So the question the diagnosis never asked is *why was a live Claude Code pane classified ARMED*.

**Because the arming marker outlived everything it stands for.** `armed()` was a bare
`[ -f "$CMD_DIR/<id>.armed" ]`, and the marker leaks two ways:

1. `bin/cc-pane-runner` consumed it only on the path where a command actually ARRIVED (`:239`).
   Its wait loop timing out — the ordinary outcome for a pane nobody ever `run`s into — exec'd a
   shell via `_fallback` and left the marker on disk forever. A runner KILLED outright leaves it too
   and can never clean up.
2. A kitty window id is a **per-process counter that restarts at 1 with every kitty** — exactly the
   hazard § CLOSE-TARGET IDENTITY PIN already documents for the close path, which grew a
   `--expect-generation` pin for it. The ARM path never had one, so a marker minted for the previous
   kitty's pane 8 answers for this kitty's pane 8.

**The live evidence, read without typing anything into any pane:**

```
$ ls ~/.claude/run/kitty-pane-cmd            # 12 markers
   8 9 10 14 15 17 18 29 30 31 34 487
$ comm -12 <(it2-kitty session list | sort) <(ls … | sed 's/\.armed$//' | sort)
   17                                        # ← the ONE live pane, and it is the pane §Mechanism measured
$ stat -f %Sm ~/.claude/run/kitty-pane-cmd/17.armed
   2026-09-16T19:09                          # 19 HOURS old, against a runner wait budget of 300s
```

Eleven of the twelve markers are orphans for panes that no longer exist; the twelfth sat over a live
Claude Code session. `session run -s 17 "/exit"` therefore wrote `/exit` into `$CMD_DIR/17.cmd`, a
file no runner was reading, and failed `deliver_argv`'s pickup proof — which is precisely the
`:356` error §Mechanism recorded.

**Both arms of the control, run in the dispatched session:**

| arm | result |
|---|---|
| stale marker present, `session run -s <id> "/exit"` | takes `deliver_argv`; text goes to a FILE; proof fails |
| same command, marker absent | takes `prove_target` → typing path; refuses only because the probe id is not a live pane |

*Lesson for the record (it cost the first hour): the plan reasoned from `run`'s NAME and its error
MESSAGE, both of which describe the launch path, and neither of which is a claim about which branch
was taken. The branch is decided by a file on disk that nothing in the diagnosis looked at.*

## W2 DECISION — Option A, and a second, independent lock

**Both defects are fixed, because either one alone leaves a live failure mode.**

**A. `session type` — a send-only verb (the plan's Option A).** Text + `\r`, typed, unconditionally.
`as_write`'s kitty branch points at it. Rationale beyond the plan's: `run`'s own header already says
*"`run`'s traffic is NOT one population"* and names `as_write`'s `/exit` as the second population —
a MESSAGE into a live composer, not a command. Every mechanism `run` carries is built for a command
(argv delivery, the launch proof, the nonce echo-verify that the same header calls **destructive**
on a TUI). Giving the message path its own verb stops it depending on a classification it never
needed. Option B (`--no-verify` on `run`) was rejected as the plan recommended: it overloads a verb
whose whole contract is "the agent started", and every future caller must remember the flag.

**B. The marker's lifetime — the generator.** Fixing only A would leave `run` and `send` still
mis-routing into a dead file for every other caller, and Claude Code's own teammate spawn uses both.
So:

- `cc-pane-runner`'s `_fallback` removes its own marker before exec'ing the shell — the leak at its
  source.
- `armed()` gains two pins, **both of which fail toward the legacy typing transport** (the path that
  works on a live pane), so neither can withhold delivery — only re-route it:
  - **GENERATION** — the marker records the kitty it was minted against, taken for free from the
    control socket's own name (`unix:/tmp/kitty-<pid>`). No extra RPC; nothing on the hot spawn path.
  - **AGE** — the marker stands for "a runner is waiting", and the runner gives up at
    `CC_PANE_CMD_WAIT_S` (300s). Past that budget there is provably nobody behind it. `+60s` slack
    because the marker is created BEFORE the launch, so its age always exceeds the runner's own
    elapsed wait.

**Residual, stated rather than hidden:** a kitty that restarts and re-mints an id *within ~6 minutes*
of a spawn would still match on age, and a marker written before this change carries no generation to
check. Judged acceptable — the generation pin covers every marker minted from now on, and it was
never the observed failure.

**C. The message that lied.** `as_write_transports()` derives the clause from the SAME `in_kitty`
predicate the branch is taken on, so the two cannot drift. Inside kitty it now reads
*"the it2 shim's session type (kitty; AppleEvents not attempted here)"*.

**One defect found by the tests, worth recording because it would have made the pin silently inert:**
`local sock="$X" gen="${sock##*-}"` reads an EMPTY `sock` — bash declares every name on a `local`
line before expanding the later initialisers — so `kitty_generation` returned 1 for every generation.
Caught by its own paired control (matching generation still arms), which is the only reason it was
not shipped as a no-op.

## Design fork — decided above; kept for the record

**Option A — add a send-only verb to `bin/it2-kitty`** (e.g. `session send`), and point `as_write`'s
kitty branch at it. Keeps "one seam" (as_write's own stated principle), fixes self-close for free,
and leaves `run`'s launch proof intact for the callers that genuinely launch agents.

**Option B — suppress the launch proof on `run` via a flag** (e.g. `--no-verify`). Smaller diff, but
overloads a verb whose whole contract is "the agent started", and every future caller must remember
the flag.

Recommendation: **A**. Record the decision and its why here before implementing.

## Hard constraints

- **`in_kitty()` is textually pinned** across `tests/handoff-fire-kitty.bats` and
  `tests/kitty-divert-real-it2.bats`, and its comment says it **"must not change shape"**. Prefer a
  fix that does not touch it.
- **~30 kitty test suites exist** (`tests/*kitty*.bats`), including `it2-kitty-composer-guard.bats`,
  `it2-kitty-operator-safety.bats` and `it2-kitty-terminal-guard.bats`. Read the composer/operator
  guards before adding a verb that types into a pane — a send-only path must not become a way to
  hijack the operator's active pane (`bin/it2-kitty:283` refuses exactly that).
- **No behaviour change on iTerm2.** The AppleEvents branch and the it2-shim branch stay as they are.
- **Do not weaken any existing gate** to get green.
- The fix must keep `/exit` delivery FOREGROUND and the watcher `setsid`-detached — see
  `handoff-fire.sh`'s own hard-won constraints (a nohup'd watcher dies with the `/exit` group-kill).

## Definition of done

1. `bash scripts/handoff-fire.sh --recycle --cwd <dir> --prompt-file <f>` from a kitty pane exits 0
   and the pane actually relaunches.
2. `self-close --successor <uuid>` likewise.
3. The misleading "BOTH transports" message names only the transport(s) actually attempted.
4. Every `tests/*kitty*.bats` suite green, plus whatever new test pins the send-only path.
5. **Landed on `origin/main`** via `scripts/ship-land.sh` (from a dedicated worktree — the shared
   checkout refuses to land on `main`).
6. **Live:** `bash scripts/deploy-live.sh` run and the change observable in the live layer. This repo
   IS the live layer's source, so landed ≠ live (CLAUDE.md § the `🚀` rung).

## Why this matters more than one pane

CLAUDE.md § Context Stewardship makes **Recycle the DEFAULT succession move** ("reach for Recycle
first; Handoff is for what a pane cannot become"). On a kitty box it has silently never worked, so
every long-horizon session either idles holding nothing or gets hand-driven by the operator. The
2026-09-17 occurrence was a session trying to move itself from `fde-endpoint-business-case` to this
repo and being unable to.

## Status log

- **2026-09-17** — Diagnosed from a live failure (two real `--recycle` attempts, pane 17). Mechanism
  above confirmed by direct probe of `it2-kitty session run -s 17 ""` → the `:356` launch-proof
  timeout. Not fixed: the in-session workaround (a `/tmp` send-only shim pointed at by `REAL_IT2`)
  was blocked by the auto-mode classifier, correctly — it is an executable that drives the terminal.
  Filed as this plan and dispatched to a dedicated session.
