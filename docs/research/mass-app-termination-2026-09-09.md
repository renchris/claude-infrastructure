# Mass application termination — 2026-09-09 18:55:16 local (23:55:16Z)

**One sentence.** A session's process census used an env-prefix assignment
(`LA_PAT='…' ps … | awk -v p="$LA_PAT" …`), which binds the variable to `ps` and **not to the
shell**, so `awk` read an empty pattern; `index($0,"")` is 1 on every line, the census returned
**every process on the box**, and the `kill` loop beneath it SIGTERMed Kitty, Dia, Discord,
Hammerspoon, ~17 Claude Code sessions and most of the user's launchd agents in nine seconds.

**It was not a logout, not memory pressure, not a watchdog, and not load.** Each of those is
refuted below with the arm that could have confirmed it.

---

## 1. The command

`~/.claude/logs/bash-commands.log`, entry `[2026-09-09T23:55:14Z]`, session
`e2cc5a62-de40-4844-8396-1689b9d0c977`, worktree `ed-w3-eng-late-arm`:

```bash
count() { LA_PAT='handoff-fire.sh late-arm' ps -axo pid=,command= | awk -v p="$LA_PAT" 'index($0,p)' ; }
echo "=== before ==="; count | wc -l
for i in 1 2 3; do
  for p in $(count | awk '{print $1}'); do kill "$p" 2>/dev/null || true; done
  sleep 1
done
```

The intent was correct and the session was obeying a real rule. Its *previous* command, at
`23:55:02Z`, used `grep -F 'handoff-fire.sh late-arm'` and completed `Exit: 0`; that form puts the
pattern in `grep`'s own argv, where `ps` prints it, so the census matches itself (memory:
`argv-census-must-not-carry-its-pattern-in-argv`). The rewrite moved the pattern to an env prefix to
fix exactly that. **The fix for the self-match bug introduced the empty-pattern bug.**

### Why the pattern was empty

`VAR=value cmd` puts `VAR` in *that command's* environment only. `awk` is the **next pipeline
stage** — a different command — so `"$LA_PAT"` there expands from the *shell*, which never had it.

### Reproduction, both arms, one variable moved

Run on this machine 2026-09-10, `kill` replaced by a counter so nothing was signalled:

| arm | census | selected |
|---|---|---|
| **A — as written** | `LA_PAT='…' ps -axo pid=,command= \| awk -v p="$LA_PAT" 'index($0,p)'` | **875 of 878** |
| **B — control**, pattern actually reaches awk | `local P='…'; ps … \| awk -v p="$P" …` | **2** |
| **C — the predicate alone** | `printf 'alpha\nbeta\ngamma\n' \| awk -v p="" 'index($0,p)'` | all 3 lines |

`LA_PAT` was confirmed `<UNSET>` in the shell after the prefix form. Arm C isolates the amplifier:
awk's `index($0, "")` returns 1, which is truthy, so an empty pattern is a **universal** selector.

---

## 2. The kernel's own tell

```
18:55:16.228280  kernel[0]: (Sandbox) System Policy: zsh(66592) deny(1) signal initproc signum:15
18:55:16.229454  kernel[0]: (Sandbox) System Policy: zsh(66592) deny(1) signal same-sandbox [suhelperd(748)] signum:15
18:55:16.277170  launchd[1]: [gui/501/com.apple.coreservices.sharedfilelistd [1105]:] exited due to SIGTERM | sent by zsh[66592]
18:55:16.312828  launchd[1]: [gui/501/application.org.hammerspoon.Hammerspoon…[1961]:] exited due to SIGTERM | sent by zsh[66592]
18:55:16.373986  launchd[1]: [gui/501/com.claude.caffeinate-floor [1938]:]        exited due to SIGTERM | sent by zsh[66592]
```

`signal initproc signum:15` is the loop attempting to SIGTERM **pid 1**. The eleven `deny` lines are
not a target list — they are exactly the subset the sandbox refused (XProtect, `system_installd`,
`suhelperd`, `softwareupdated`, `ScreenTimeAgent`, `dmd`, …). A broadcast iterating every process is
the only shape that produces that scatter *plus* an attempt on init.

`zsh[66592]` is the Claude Code Bash tool's shell — the tool runs **zsh** on this box (memory:
`interactive-grep-is-ugrep-not-usr-bin-grep`). It is dead now, killed by its own broadcast.

**Corroboration from an absence:** the `23:55:14Z` command has **no entry** in
`~/.claude/logs/bash-execution.log`. Every other command in the window recorded its `Exit:` line.
The shell was killed by its own broadcast before the post-hook could log the result.

### Sender census, 18:50:00–18:56:30

| sender | signals | verdict |
|---|---:|---|
| **`zsh[66592]`** | **78** | the broadcast — this incident |
| `launchd[1]` | 43 | consequence: `during teardown of process-scoped services after host exited` |
| `mds[634]` | 18 | Spotlight reaping its own mdworkers — routine |
| `bash[17385]` | 2 | see §4 |
| `runningboardd` / `PAH_Extension` / `avconferenced` | 1 each | routine |

---

## 3. The logout hypothesis — REFUTED on ordering

The evidence pack's leading hypothesis was an orderly user-session teardown. It is consistent with
the *symptoms* and wrong about the *cause*, and the discriminator is timing:

| event | time | |
|---|---|---|
| first broadcast signal | **18:55:16.228** | cause |
| first `SACShieldWindowShowing` | **18:55:17.558** | **1.33 s LATER** |

- **`loginwindow[680]` never exited.** Through the whole window it only logs
  `invalidated because the client process (pid …) either cancelled the connection or exited` — it
  was watching its clients die, not dying or tearing down.
- The shield is drawn by `usernotificationsd[66893]`, `callservicesd[66983]`, `distnoted[66928]` —
  **pids just above 66592**, i.e. processes launchd *respawned* after the broadcast killed them.
  The shield is the session agents re-establishing, which is a consequence.
- The two `com.apple.logoutContinued` hits are `distnoted … register name:` at 18:55:37 and
  18:56:21 — a respawned daemon *registering interest* in a notification, 21 s and 65 s after the
  fact. Not a logout request.
- **`kitty[1427]` exited `exit(0)`** at 18:55:17.631, having `ran for 1086728859ms`. The pack's
  "graceful AppKit window close" is kitty *handling SIGTERM cleanly* — which is what a well-behaved
  app does when broadcast a TERM. It needs no logout to explain it. Same for secd's
  "SIGTERM, exiting when clean": that line names the signal it received.

**No `reallyLogout`, no restart request, no shutdown.** Uptime confirms 15 days, no panic file.

**Independent corroboration** (originating session `claude-infrastructure-1`, reached separately and
received mid-investigation). Three further disproofs of the logout reading, and one datum that is
positive evidence *for* the broadcast: `loginwindow` is **pid 680, running continuously since
Aug 25** — it never restarted, so no user session was ever torn down; `clearing logout in progress`
is routine `PersistentAppsSupport` bookkeeping that also fires at 18:50/18:51/18:52, well before the
event; and the operator confirms they were simply **away from the keyboard**, so the shield is the
ordinary idle screen lock and is coincidence. The positive datum: **launchd-MANAGED apps respawned
in the same second** (Dock and Finder both restarted at 18:55:16) **while UNMANAGED ones stayed
dead** (kitty, all ~16 Claude sessions). That split is precisely what a mass SIGTERM to user-owned
processes produces and no logout does — a logout does not bring Finder straight back up.

## 3b. Memory pressure and watchdog — REFUTED with counts

- Actual jetsam/memorystatus **kills: 0**. The 2,216 `jetsam` and 405 `memorystatus` substring hits
  are routine process-state chatter; counting *mentions* instead of *kills* is how this gets
  misread. The 4 `EXC_RESOURCE` lines are 15 MB **high-watermark notices** on `com.apple.dock.e`,
  `DockHelper` and `heard`, all at 18:55:19 or later — after the kill wave, and a notice is not a
  kill.
- The 43 `SIGKILL | sent by launchd[1]` events all carry
  `during teardown of process-scoped services after host exited` and begin at 18:55:16.28 — launchd
  escalating on children whose hosts the broadcast had just terminated. Consequence.
- `watchdog` hits resolve to the daemon name `watchdogd` in routine lines.

## 3c. Load — CONTRIBUTOR TO THE MOTIVE, not to the mechanism

Load was 115.16 / 117.07 / 71.40 with 465 user processes; the proc table was **not** exhausted
(limit 10666). Load is **not causal**: `index($0,"")` returns 1 at any load, and arm A reproduced
875/878 today at load ≈18. Its real role is upstream of the code — the session had proliferated its
own detached late-arm watchers during a bats run, and that pile is *why* it was writing a
census-and-kill loop at all. A quieter box would have run the same command to the same end.

---

## 4. `bash[17385]` — not this incident

Two signals only, 33 s earlier, both targeted at our own overrunning launchd jobs:

```
18:54:43.787  com.chrisren.autonomy-sweep [93222] exited due to SIGTERM | sent by bash[17385], ran for 2035691ms  (33.9 min)
18:54:45.253  com.claude.cc-gc            [77335] exited due to SIGTERM | sent by bash[17385], ran for 1219229ms  (20.3 min)
```

That is a supervisor bounding two jobs that had massively overrun — correct behaviour, blast radius
2, and it cannot account for 78 signals or for any GUI application. **Residual uncertainty, stated
rather than papered over:** the exact script behind pid 17385 is not pinned. `cc-reaper`'s bound
helper `_rp_bounded` (`bin/cc-reaper:522-526`) shells out to `timeout(1)`, so the signal would be
attributed to `timeout`, not `bash` — so 17385 is some other long-lived bash supervisor. It is
bounded as harmless by its own record and was not pursued further.

---

## 5. The fix

**Chokepoint, not a new lint.** `hooks/lib/kill-selection.py` already evaluates a selection live —
but only when the census verb is `pgrep`/`pkill`/`killall`. This line used a bare `kill` over a
hand-rolled `ps | awk` census, so it was outside that gate entirely. Widening the gate's *verb list*
would repeat `denylist-enumerates-spellings-not-the-class`; the fatal property was not the verb but
that **the selector was provably empty at its use site**, which is decidable statically with no fork.

- `hooks/lib/is-true-flag.sh :: empty_prefix_expansion_scan` — convicts a variable that is set by an
  env prefix and read from a *different* command of the same line.
- `hooks/lib/is-true-flag.sh :: signals_in_command_position` — quote-stripped position test, so a
  `kill` inside a commit message is a string; includes `xargs kill`.
- `hooks/validate-bash.sh` — denies only on the **conjunction**. A provably-empty selector that
  signals nothing is a measurement bug, not this gate's business. Seam:
  `CC_EMPTY_SELECTOR_GATE=off`; denials recorded to `~/.claude/logs/empty-selector-gate.jsonl`.

### Deliberate abstentions (it refuses to guess)

- a bare `NAME=value`, or `export`/`local`/`declare`/`typeset`/`readonly NAME=`, anywhere in the
  command — the value *does* reach the shell;
- the reference must lie across a `|`, `;`, `&` or newline from the assignment, so
  `FOO=bar sh -c 'echo $FOO'` (correct — sh reads its own environment) is untouched;
- a reference *before* the assignment is somebody else's variable.

### Tests — `tests/empty-selector-kill.bats`, 17/17, plan == count

Regression: `tests/pkill-scope.bats` 36/36, `hooks/tests/validate-bash.test.sh` 96/96. No existing
gate was weakened.

**Mutation proof — one mutant per site, run against the FINAL 17-test file with a green
baseline asserted first, each subject restored byte-identical by sha256:**

| mutant | predicted red | actual | |
|---|---|---|---|
| M1 separator test always continues | 1,2,3,4,5 | 1,2,3,4,5 | MATCH |
| M2 bare-assignment abstention removed | 10 | 10 | MATCH |
| M4 `xargs` arm removed from signal test | 4 | 4 | MATCH |
| M5 kill switch ignored | 17 | 17 | MATCH |
| M6 both abstention arms removed | 10,11 | 10,11 | MATCH |
| M3 export/local arm removed **alone** | none | none | **inert — see below** |

Two findings from the mutants worth keeping:

1. **The first mutation round changed nothing and every test stayed green** — the replacements had
   silently failed to apply through nested-heredoc quoting, so five "MISMATCH" rows were reporting
   on an unmutated file. The harness now *asserts* the anchor count is 1 and that the file's sha256
   actually moved, and exits non-zero otherwise. A mutant that does not apply is a green suite
   claiming credit it has not earned.
2. **M3 is inert, and that is a fact about the code, not a gap in the tests.** The export/local arm
   is subsumed by the bare-assignment arm, because the boundary before `FOO=` in `export FOO=x;` is
   a space and the bare regex matches it too. It is kept as defence in depth; test 11 asserts the
   behaviour so a future edit cannot make it DENY, and is labelled in the file as an **equivalence
   guard, not a red-proof** (memory: `green in both arms is an equivalence guard`).

### One more instrument trap, paid for during this work

The first land was refused `rc=6 GATE RED` on **my own** new code: `SC2020` on
`tr ';\n' '\n\n'` (the second mapping is a no-op; the house form one gate up is `tr ';' '\n'`,
and the two are byte-identical on `od -c`). I had run shellcheck before committing and it printed
nothing — because I ran `shellcheck -S warning` while the gate runs bare `shellcheck`, and SC2020 is
a `note`. Measured after the fact: **0** lines from my invocation, **1** real finding from the
gate's. This is the repo's own `prescribed-repro-weaker-than-the-harness` rule, hit live: *match the
INVOCATION, not just the tool.* Pre-flight a gate with the gate's own command line, or the green you
get is a fact about your flags.

Tests 6–9 likewise do not credit the abstention: a `NAME=value;` is never a prefix-assignment
*candidate*, so the abstention never runs on them. Tests 10–11 were added specifically to reach it.

---

## 6. Auto-recovery — considered, and deliberately NOT built

17 sessions died and the operator had to ask what happened. The recovery path already exists
(`/resume-sessions`, `bin/lr-fleet --locate`, `limit-recover`). An automatic mass-relaunch triggered
by a mass-death signal is the wrong answer *here* on this incident's own evidence:

- it would re-launch sessions into a box that had just been driven to load 115, which is how a
  second incident starts;
- the trigger would have to fire on "many sessions died at once", and a recovery path that re-arms
  on one healthy sample kills every damping layer above it (memory: `recovery-needs-hysteresis`);
- most importantly, **prevention dominates**: the shape is now refused before it runs, and the
  denial names the variable and the remedy, so the next occurrence costs one blocked tool call
  instead of a 20-minute reconstruction.

The residual — an over-broad kill whose selector is *not* provably empty — is not closed by this
work and is not claimed to be.
