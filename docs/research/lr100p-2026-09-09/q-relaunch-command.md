# Q: the exact relaunch an in-place recovery types

Research artifact · wave LIMIT_RECOVER_100P · 2026-09-09 · read-only on the live machine.
Every fact below is labelled **MEASURED** (I ran it / read it on this box today) or **INFERRED**
(derived from source that I read, but not executed).

---

## Verdict

**Type this, into the source pane's own surviving interactive zsh, without `exec`:**

```
nocorrect env CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1 CLAUDE_CODE_TASK_LIST_ID=<source's own value> \
  /Users/chrisren/.claude/scripts/limit-recover/lr-fire-resume.sh <target> <cwd> <sid> \
  --model <source's RUNTIME model> --effort <source's RUNTIME effort> \
  --prompt '/limit-recover ingest <bundle>'
```

Four claims, each measured, that decide the design:

1. **The tier must be read from the TRANSCRIPT, not from argv, not from the registry, not from a
   default.** The registry row carries no model/effort field at all (MEASURED). The process argv
   carries only the LAUNCH tier. On pane 616 right now, argv says `--model claude-opus-5 --effort
   high` while the session has been running `claude-fable-5-1` at `xhigh` since 22:09Z — a
   model-**family** divergence, in the exact session this brief names (MEASURED, § Tier carry).
   The brief's own premise ("model claude-opus-5, effort high") is the bug.

2. **`--resume <sid>` preserves the uuid.** `--fork-session` is documented as *"When resuming,
   create a new session ID instead of reusing the original"* — so the bare form reuses it
   (MEASURED, `~/.claude-260/.../claude --help`), and the live tmux resume of 52e35019 is appending
   to the same `.jsonl` under the same `sessionId` (MEASURED).

3. **`exec` vs no-`exec` is not a style choice; it is a 130× measured difference and it decides
   whether the pane is recyclable next time.** Under a non-tty stdin (a Claude Bash tool call)
   `expect … interact` returns in **0.047 s with rc 0** and the spawned child is dead; under an
   allocated pty the identical program runs **6.096 s** and waits (MEASURED, § The literal line).
   `exec bash <launcher>` typed into an interactive shell replaces that shell, so the pane's ROOT
   becomes expect and `pane_shell_root` reports `no` — `handoff-fire.sh:10281-10290` then REFUSES
   the next recycle. Live proof: windows 625 and 632, both fired by `lr-handoff.sh`, have `expect`
   as their root process today (MEASURED) and are permanently un-recyclable. **Each recovery in the
   current shape makes the next recovery impossible.**

4. **`handoff-fire.sh --recycle --account <target> --extra "--resume <sid>"` is a trap, and only a
   transplant disarms it.** The account launcher runs `_cc_resume_pin`, which calls
   `bin/cc-resume-resolve` and OVERRIDES `CLAUDE_CONFIG_DIR` with wherever the transcript actually
   lives (`~/.claude/lib/cc-resume-shell.sh:119-130`). `CC_ACCOUNT_PINNED=1` does not gate it —
   that flag stops the interactive ROUTER only (`handoff-fire.sh:8567-8578`). MEASURED:
   `cc-resume-resolve 52e35019` → `account=next2` (the limited one); `cc-resume-resolve b418b97a`
   → `account=next3` (post-transplant, because the source was renamed `.jsonl.handed-off`). So a
   pre-transplant recycle onto next3 silently resumes on **next2**.

---

## Tier carry

### Source-of-truth order (use the first that answers; never skip to a default)

| # | Source | model | effort | perm-mode | Durable? | Verdict |
|---|---|---|---|---|---|---|
| 1 | **Transcript assistant entries** — `message.model` + top-level `effort`, per turn | ✅ | ✅ | ✗ | ✅ — and it is the artifact the transplant COPIES | **USE THIS** |
| 2 | `/tmp/cc-telemetry/<sid>.json` — `.model`, `.effort` | ✅ live | ✅ live | ✗ | ✗ wiped on reboot | cross-check only |
| 3 | `ps -Eww -p <pid>` / `ps -o command=` argv | launch-time only | launch-time only | ✅ | ✗ dies with the pane | **perm-mode only** |
| 4 | `<cfg>/autonomy/session-window.jsonl` — `{sid,window,model,ts}` | launch-time | ✗ | ✗ | ✅ | last resort |
| 5 | `~/.claude/cc-registry/<pane>.json` | ✗ | ✗ | ✗ | ✅ | **carries neither** |

**Rung 1 is authoritative and I proved rungs 3 and 5 wrong on live data.**

- MEASURED — registry row `~/.claude/cc-registry/616.json` is exactly
  `{paneUUID,name,cwd,account,pid,startedAt,session_id,surface,lstart}`. Schema pinned at
  `hooks/session-register.sh:282-289`. **No model, no effort, no permission-mode.** Its value is
  the `(pid,lstart)` identity and the `account` field, not the tier.
- MEASURED — `ps -o command= -p 80874` (pane 616's claude) prints
  `… --permission-mode auto --model claude-opus-5 --effort high`.
- MEASURED — that same session's transcript
  (`~/.claude-secondary/projects/-Users-chrisren-Development-claude-infrastructure/52e35019-….jsonl`,
  848 lines) carries per-assistant-turn `(model, effort)`:
  `(claude-opus-5, high) ×19` → **switch at 2026-09-08T22:09:08Z** → `(claude-fable-5-1, xhigh) ×116`.
  The limit fired at 23:09Z, i.e. **while on Fable at xhigh**. `isSidechain` is `false` on every
  one of the 166 rows, so these are the LEAD's turns, not a subagent's.
- MEASURED — `/tmp/cc-telemetry/52e35019-….json` at 01:50:05Z reads
  `"model":"claude-fable-5-1","effort":"xhigh","pid":80874`. It agrees with the transcript and
  disagrees with argv. Writer: `statusline.sh:150` (`model: .model.id, effort: .effort.level`),
  whose own comment at `:297-299` calls it *"live observability for the launcher-injected default
  and in-session `/effort` changes"*.
- MEASURED — the transcript also carries `version` per turn: `2.1.260` on all 166 rows. That is
  the build-parity field (§ The `--resume` binary).

### The natural experiment already on disk — three recoveries, one broke

| session | tier at the limit (transcript) | relaunch argv (the actual `/tmp` launcher file) | tier after |
|---|---|---|---|
| `b418b97a` | `claude-fable-5-1 / max` | `… next3 … --branch main --model claude-fable-5-1 --effort max --prompt '/limit-recover ingest …'` | `claude-fable-5-1 / max` ✅ |
| `6e29fee9` | `claude-opus-5 / high` | `… next4 … --branch wt-… --effort high --prompt '/limit-recover ingest …'` (no `--model` ⇒ SSOT `opus_latest`) | `claude-opus-5 / high` ✅ |
| `52e35019` | `claude-fable-5-1 / xhigh` | `… next2 … --prompt /limit-recover` — **no `--model`, no `--effort`** | `claude-opus-5 / max` ❌ |

All MEASURED: launcher files still present and readable at
`$(getconf DARWIN_USER_TEMP_DIR)/lr-launch-*.sh` and `…/lr-poller-launch-*.sh`; post-transplant tiers
read out of each target-account transcript.

The two that carried did so because a thinking session passed `--model`/`--effort`
(`commands/limit-recover.md:292-296` demands exactly this). The one that broke is the **poller's**,
and the poller cannot think: `lr-reset-poller.sh` mints `exec lr-fire-resume.sh <acct> <cwd> <sid>
--prompt /limit-recover` with no tier flags at all. `lr-fire-resume.sh:216` then defaults
`effort="max"` and `:236-244` resolves `model` from `versions.opus_latest`. **Every unattended
recovery of a Fable session silently lands on Opus.** That is the defect the whole in-place actuator
must close, and it is a two-line fix given rung 1.

### Also unmistakably split-brained right now (MEASURED — read before designing the actuator)

52e35019's transcript tail interleaves `(claude-fable-5-1, xhigh)` and `(claude-opus-5, max)` turns
every ~30 s from 01:42Z, all `isSidechain=false`, all `sessionId=52e35019-…`. Those are **two live
writers appending to one file by path**: pane 616's claude (pid 80874, in-session Fable) and the
poller's tmux resume (pid 77720, `--resume`, Opus/max). The only discriminator in the file is the
`(model, effort)` pair. Consequence for rung 1: **read the last assistant entry BEFORE the
`isApiErrorMessage` synthetic block**, not the file tail — the tail may belong to a rescuer.

### Permission mode and the flags nobody carries

- `--permission-mode auto` is hardcoded in the spawn (`lr-fire-resume.sh:427/429`) and matches the
  launcher default `_perm="${CLAUDE_PERM_MODE:-…:-auto}"` (`~/.zshrc:494`). Carrying it is correct
  today; if a source ran `--permission-mode plan`, rung 3 (`ps -Eww`) is the only source and it dies
  with the pane. **Snapshot argv into the bundle MANIFEST at audit time** or it is unrecoverable.
- MEASURED, and this is the sharpest env finding: `ps -Eww -p 16212` (the claude inside
  lr-handoff-fired window 625) has **45** env vars against **55** for the shell-launched pane 616.
  Missing and load-bearing:

  | var | consequence of its absence |
  |---|---|
  | `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1` | the deliberate nested-subagent runaway bound (`~/.zshrc:484`, GH #68619) is **not applied** — every lr-fire-resume'd session runs at the product default depth 3 |
  | `CLAUDE_CODE_TASK_LIST_ID` | the session joins no shared task board; the transplanted `tasks/<id>/` dir (`lr-transplant.sh:79-81`) is on disk and unreachable |
  | `ITERM_SESSION_ID` | `hooks/session-register.sh:127` reads `${CC_PANE_ID:-${ITERM_SESSION_ID:-}}` and returns 0 without it — no registry row |

  The cause is structural: `~/.zshrc:694-695` synthesises `ITERM_SESSION_ID="w0t0p0:$KITTY_WINDOW_ID"`
  **only in an interactive zsh**, and a `kitty @ launch -- /bin/bash <launcher>` window has no shell
  anywhere in its ancestry. MEASURED corroboration: window **632 has no registry row at all** while
  its retired predecessor husk **618 still does** — the fleet's cross-account address table names
  the dead pane and not the live one.
  *Caveat, stated because it refutes a clean story:* window 625 DOES have a row (written 11 min
  after launch, rewritten at 00:56Z). I could not establish the path by which it registered. Treat
  registration of a launcher-rooted window as **unreliable, 1 of 2 measured**, not as absent.
- MCP: `handoff-fire.sh:8485/8512` compose `--strict-mcp-config --mcp-config=<pass>` plus a project
  approval decision (`scripts/lib/mcp-noinherit.sh:139`, rationale in `tests/mcp-no-inherit.bats:1-20`).
  **`lr-fire-resume.sh` composes none of it** and its expect block has no arm for the *"N new MCP
  servers found in this project"* modal — so a recovery into a repo with a tracked `.mcp.json` parks.
  MEASURED: `claude-infrastructure` has no `.mcp.json`, so 616's case is safe today; this is a
  latent class, not a live one (INFERRED for other repos).
- `CLAUDE_CODE_TASK_LIST_ID` must be **copied, never recomputed**: the launcher uses the inline
  `_cc_tlid` at `~/.zshrc:88` (repo-**and-branch**) while `bin/cc-tlid` returns repo only. MEASURED
  in the 616 cwd: `_cc_tlid` → `claude-infrastructure-main`, `bin/cc-tlid` → `claude-infrastructure`.
  Pane 616's live env carries `claude-infrastructure-main`. Read it off `ps -Eww` before the /exit.

---

## The literal relaunch line

### Why `exec` kills it from a Bash tool and not from the pane's own shell

`lr-handoff.sh`'s `_LRH_FB` (`:520-535`) says *"running it from an existing shell kills the resumed
session when that command returns."* That is true, and the reason is narrower and more useful than
the wording: **it is about stdin, not about `exec`.**

MEASURED, from this subagent's Bash tool (`test -t 0` → NO):

```
timeout 12 expect -c 'set timeout 10; spawn -noecho /bin/sleep 8; interact'   → 0.047 s, rc 0, child GONE
timeout 12 script -q /dev/null expect -c '…same…'                            → 6.096 s, child ran to completion
```

`interact` bridges expect's **own stdin** to the spawned pty. A Bash tool call gives it a pipe/devnull,
which delivers EOF immediately; `interact` returns, expect exits, the pty master closes, the spawned
`claude` takes SIGHUP. Sub-100 ms — **and rc 0**, so a driver that checks `$?` reads GREEN over a dead
session. Typed into the pane's interactive zsh, stdin is the pane's tty, nothing closes it, and expect
blocks for the life of the session.

The `exec` axis is separate and governs the **pane**, not the session:

| form typed into an interactive zsh | pane root after launch | `pane_shell_root` | recyclable next time |
|---|---|---|---|
| `bash <launcher>` (launcher's own internal `exec` is harmless — it replaces the forked bash) | `zsh` | `yes` | ✅ |
| `exec bash <launcher>` | `expect` | `no` | ❌ — `handoff-fire.sh:10281-10290` refuses; window dies with the session |

`lr-handoff.sh` types the second form (`osa_type_verified "$NEWPANE" "exec /bin/bash $LAUNCHER"`,
~`:535`) and prints it as the manual fallback. **Dropping that one word makes every future fired
pane recyclable.**

### FORM A — typed into the source pane's surviving shell (the primary path)

Preconditions, in order, each already implemented somewhere in the tree:
`pane_cc_state == cc` → `pane_shell_root != no` (`handoff-fire.sh:10269-10291`) → composer gate
(`:10305-10320`) → `/exit` → watcher ps-polls to `pane_cc_state == shell` → **transplant** →
verified type.

For pane 616 (`sid 52e35019-17e8-40f6-a54f-3a04de70d2e6`, cwd `/Users/chrisren/Development/claude-infrastructure`,
target `next3`), with the tier taken from the transcript rather than from the brief:

```
nocorrect env CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1 CLAUDE_CODE_TASK_LIST_ID=claude-infrastructure-main /Users/chrisren/.claude/scripts/limit-recover/lr-fire-resume.sh next3 /Users/chrisren/Development/claude-infrastructure 52e35019-17e8-40f6-a54f-3a04de70d2e6 --model claude-fable-5-1 --effort xhigh --prompt '/limit-recover ingest /Users/chrisren/.reso/limit-recover/52e35019-17e8-40f6-a54f-3a04de70d2e6/bundle-<TS>'
```

Line-by-line justification:

- **no `exec`** — § above.
- **`nocorrect`** — a zsh reserved word, never itself correction-eligible, per-command, does not
  mutate the operator's shell (`handoff-fire.sh:8580-8622`). Redundant when typed through
  `it2_type_verified`, which types `unsetopt correct correct_all` as its own echo-verified line first
  (`:1993`); mandatory on any hand-typed or manual-fallback form.
- **`env VAR=… …`** — restores the three vars `lr-fire-resume`'s
  `env -u CLAUDE_CODE_CHILD_SESSION DISABLE_AUTOUPDATER=1 CLAUDE_CONFIG_DIR=$cfg` whitelist drops.
  `ITERM_SESSION_ID` needs no restoration on this form: it is ambient in the pane's interactive zsh
  and rides through bash→expect→`env`→claude (INFERRED from the whitelist-by-override spawn at
  `lr-fire-resume.sh:427/429` plus MEASURED presence in shell-launched pane 616).
- **absolute path to `lr-fire-resume.sh`, not the account launcher** — this is the whole point of
  bypassing `handoff-fire --recycle`. `lr-fire-resume` sets `CLAUDE_CONFIG_DIR` explicitly and never
  consults `_cc_resume_pin`, so the target account cannot be silently rewritten back to the limited
  one (§ Verdict claim 4).
- **`--model claude-fable-5-1 --effort xhigh`** — the RUNTIME tier from the transcript. `xhigh` is a
  valid value: `--effort` choices are `low, medium, high, xhigh, max` (MEASURED, 2.1.260 `--help`).
  Note the routing coupling: a Fable carry must pick its target with `claude-accounts --route fable`,
  not `--route general` (`lr-handoff.sh:249`). MEASURED headroom today —
  `next 10% · next4 13% · next3 28% · next2 53%` fable-weekly — so next3 is a valid Fable target.
- **`--prompt '/limit-recover ingest <bundle>'`** — single-quoted; `lr-fire-resume.sh:325` collapses
  newlines because the composer submits on CR.
- **NOT `--branch`** — only used to recreate a reaped worktree (`:263-269`); the cwd exists.

### FORM B — replacement window argv (source pane launcher-rooted, or gone)

**Do not pass the launcher as the window's argv.** Launch a login shell and type into it:

```
kitty @ launch --type=window --location=vsplit --match window_id:<anchor> --next-to id:<anchor> \
  --cwd /Users/chrisren/Development/claude-infrastructure \
  --title 'lr 52e35019 → next3 (was pane 616)' \
  --var lr_continuation_of=52e35019-17e8-40f6-a54f-3a04de70d2e6 \
  --var lr_source_pane=616 --var lr_target=next3 \
  -- /bin/zsh -l
```

then `it2_type_verified` FORM A into the returned window id, then `recycle_engaged`-style
verification, then close the source.

Four properties FORM B buys that `-- /bin/bash <launcher>` does not (all MEASURED unless noted):

1. `/bin/zsh -l` sources `~/.zshrc:694-695`, which synthesises `ITERM_SESSION_ID` from
   `KITTY_WINDOW_ID` — so `hooks/session-register.sh` writes a real row with `surface=pane`.
   Passing `--env CC_PANE_ID=<id>` instead is wrong: it makes `surface=headless`
   (`session-register.sh:142-146`), and `bin/cc-sessions` then declines to cross-check a row that
   is in fact enumerable.
2. The window root is a shell ⇒ `pane_shell_root == yes` ⇒ **the successor is itself recyclable**,
   which is what breaks the compounding failure of panes 625/632.
3. Every refusal below stays on screen instead of vanishing with the window (§ Failure visibility).
4. `--var` lands in `kitty @ ls`'s per-window `user_vars` (MEASURED — this fleet already carries
   `CC_MENU_LABEL` there), giving the plan's Q5 an un-fakeable provenance channel that survives a
   recycle and needs no new store. `--title` is cosmetic and is overwritten by the TUI; the user
   var is not.

`--hold` exists (MEASURED) and is the minimum-effort alternative for property 3 alone — it keeps a
dead window readable but leaves no shell, so it buys neither 1 nor 2.

### Ordering — and why the plan sketch's step 2/3 order is wrong

The lead's sketch transplants (step 2) **before** the `/exit` (step 3). That re-opens the 2026-08-16
resurrect-by-path incident named in `00-context.md`: a live CC keeps appending by PATH and re-creates
`<sid>.jsonl` in the retired store. Correct order:

1. bind pane ↔ sid by the registry row, `(pid,lstart)` alive on the pane's tty;
2. read the tier off the transcript **and** `ps -Eww` (argv + `CLAUDE_CODE_TASK_LIST_ID`) — this is
   the last moment the process env exists;
3. survivability + composer gates; `/exit`; wait for `pane_cc_state == shell`;
4. **then** transplant (rename → copy → sha → lock → tombstone);
5. verified-type FORM A;
6. verify engagement; report.

Step 2 before step 3 is non-negotiable — `--permission-mode` and the task-list id are unrecoverable
once the process is gone.

---

## Bundle/context when driven by a third party

`lr-handoff.sh:293-295` already has the right shape and the right default:

```
[[ -n "$CONTEXT" ]] && cp "$CONTEXT" "$BUNDLE/HANDOFF-CONTEXT.md"
# else:
'# HANDOFF-CONTEXT missing … Derive them from audit.md + the transplanted transcript,
 and treat scope as UNRECONSTRUCTED (STOP-ASK before assuming).'
```

`commands/limit-recover.md:320-321` honours it: *"if it says UNRECONSTRUCTED, ask before assuming."*
So the marker semantics are **already built and already load-bearing** — the driver must not
paper over them.

**A driver must never author narrative.** `HANDOFF-CONTEXT.md:2` calls the operator-written file
*"the one artifact only you can write"*; a driver that invents scope is the tainted-completion
failure `commands/limit-recover.md:11` opens with. The driver quotes disk and marks the rest.

Generic driver-written `HANDOFF-CONTEXT.md`, all fields mechanically derivable:

| field | source | if absent |
|---|---|---|
| header | `UNRECONSTRUCTED — written by the recovery driver, not by the session` | — |
| `Scope (frozen)` | the dod-persist capture, keyed by repo identity via `hooks/lib/dod-path.sh` | literal `UNRECONSTRUCTED` |
| last assistant message | last `type=assistant` text block **before** the first `isApiErrorMessage` — not the file tail (§ split-brain) | — |
| tier at the limit | `(message.model, effort)` of that same entry, verbatim | — |
| worktree state | `git status --porcelain` + `git log --oneline -15` — already written by `lr-handoff.sh:298-299` | — |
| open gaps | `audit.json .counts.gaps`, already in `MANIFEST.json:308` | — |
| next action | **must read** `UNRECONSTRUCTED — the source session could not be asked` | — |

Two additions the current `MANIFEST.json` (`lr-handoff.sh:303-313`) should carry, both cheap and
both otherwise unrecoverable: **`source_argv`** (the full `ps -Eww -o command=` line, for
permission-mode) and **`source_task_list_id`**. `MANIFEST` already has a `model` field but it holds
the lr-handoff *argument* (`opus`/`fable`), not the measured runtime id — that is the same
launch-vs-runtime confusion as rung 3 and should be renamed or corrected.

**The ingest step's own verification survives the change unaltered.** `commands/limit-recover.md:314-317`
checks `$CLAUDE_CONFIG_DIR == target_cfg` and `$CLAUDE_CODE_SESSION_ID == sid` — both hold for a
same-uuid resume into the target config dir (claim 2), so an in-place recovery needs no new contract.

---

## Failure visibility

What the operator actually sees, per refusal class. The column that matters is the last one: on
FORM A stderr lands in a **surviving shell** and stays; on today's `-- /bin/bash <launcher>` argv
form the window dies and takes the message with it (the defect `40c7e5cfd` just fixed on the
*announcement* side — the message itself is still lost).

| class | site | exit | what prints | FORM A | today's FORM B |
|---|---|---|---|---|---|
| capacity refused (load/core, RAM, active ceiling) | `lr-fire-resume.sh:317-322` | **9** | `✗ <reason>` + "shed load, re-run this exact command" + the two override envs | visible in the pane, command re-runnable from history | **window vanishes** |
| tombstone — already transplanted elsewhere | `:255-259` (verdict `:166`) | **3** | `REFUSED — … went to: <acct>`, successor path, last activity, tombstone path | visible | vanishes |
| claude binary unresolvable | `:289-293` | **1** | `✗ cannot resolve the claude binary` + `CC_CLAUDE_BIN=` hint | visible | vanishes |
| `versions.opus_latest` unreadable | `:238-243` | **1** | `✗ cannot resolve versions.opus_latest` + "refusing to guess" | visible | vanishes |
| unknown account / missing cfg dir | `:227,246` | **2** | `unknown account '<x>'` / `config dir … missing` | visible | vanishes |
| worktree missing, no `--branch` | `:267` | **2** | `worktree … missing and no --branch to recreate it` | visible | vanishes |
| resume menu selector unconfirmed | `:471-473` | — (parks) | `WARNING — could not confirm the selector …; sent NOTHING.` then waits for a human | **the pane is where the human already is** | pane exists but is not a shell |
| injected prompt not submitted | `:536-553` | — | 5 CR retries against `esc to interrupt`, then `WARNING — prompt may not have submitted; press Enter` | actionable | actionable |
| MCP project-approval modal | no arm exists | — (parks) | the modal, silently | parks | parks |
| zsh spell-correction `[nyae]` | `cc-type-verified.sh:8-14` | — (parks forever) | an unanswerable prompt | prevented by `nocorrect` + the disarm line | n/a (argv form) |
| typed line mangled by ZLE | `handoff-fire.sh:2020-2050` | rc 1 | nonce echo-verify fails ⇒ **CR never sent**, line scrubbed, retried ≤4× | fails loud, nothing executed | n/a |

**One recommendation follows directly:** for the argv form, `--hold` (MEASURED to exist) or, better,
FORM B's login shell. A recovery whose whole job is to lose nothing currently loses its own error
message on six of eleven classes.

---

## Tests to red-proof

Each names the mutant that must go red pre-fix. Existing suites to extend rather than duplicate:
`tests/lr-resume-tombstone-guard.bats`, `tests/lr-resume-answer-width.bats`,
`tests/kitty-recovery-launch.bats`, `tests/handoff-recycle-expect-probe.bats`.

1. **Tier carry from the transcript.** Fixture a transcript whose entries switch
   `(claude-opus-5,high)` → `(claude-fable-5-1,xhigh)` and then carry an `isApiErrorMessage` block.
   Assert the resolver emits `claude-fable-5-1 / xhigh`. *Mutant:* read the process argv ⇒ must
   yield opus/high and go RED. *Second mutant:* read the file TAIL ⇒ with an interleaved
   Opus/max rescuer appended, must yield opus/max and go RED. Both are real, both happened today.
2. **Poller tier flags.** Assert the poller's minted launcher contains `--model` and `--effort`.
   *Mutant:* today's `lr-reset-poller.sh` line ⇒ RED. Positive control: a source session that
   genuinely ran the default must still produce the SSOT-resolved model, so the test must not pass
   by merely requiring the flags to be non-empty.
3. **`exec` absent from every typed relaunch.** Grep the composed command in `lr-handoff.sh`'s
   iTerm2 arms and the new actuator for a leading `exec`. *Mutant:* restore `exec /bin/bash …` ⇒ RED.
   Pair it with a `pane_shell_root` assertion over a fixture tty whose roots are `expect` (`no`) vs
   `zsh` (`yes`) — `handoff-fire.sh:3137` already has the predicate and a suite.
4. **`interact` needs a tty.** Assert `expect -c 'spawn -noecho /bin/sleep 3; interact'` under a
   redirected stdin returns in < 1 s **with rc 0** and the child dead, and under `script -q
   /dev/null` takes ≥ 3 s. This is the rc-0-lies control; it is the one that stops a future driver
   from `bash <launcher>`-ing from a tool call and believing it worked.
5. **Cross-account resume must not be rewritten.** Fixture two config dirs, put the transcript in
   the SOURCE one, and assert the composed command does not route through a launcher that calls
   `_cc_resume_pin`. *Mutant:* `handoff-fire --recycle --account <target> --extra "--resume <sid>"`
   ⇒ resolves to the source account ⇒ RED. Assert the post-transplant case resolves to the target,
   so the test proves the ORDERING and not merely a refusal.
6. **Env restoration.** Assert the composed line carries `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` and
   `CLAUDE_CODE_TASK_LIST_ID`, and that the task-list value is COPIED from a fixture `ps` stub
   rather than recomputed. *Mutant:* recompute with `bin/cc-tlid` ⇒ yields
   `claude-infrastructure` against a measured `claude-infrastructure-main` ⇒ RED.
7. **Replacement window is shell-rooted and registers.** Against a kitty stub, assert the launch argv
   is `-- /bin/zsh -l` and that the relaunch arrives by verified typing. *Mutant:* `-- /bin/bash
   <launcher>` ⇒ RED. Include the `--var lr_continuation_of=<sid>` assertion — provenance must be
   part of the same gate or it will be dropped as cosmetic.
8. **Engagement for a SAME-UUID recycle.** `recycle_engaged`'s row-change leg
   (`handoff-fire.sh:3209-3227`) compares `newsid != oldsid` and is **structurally blind** when the
   uuid is preserved — it can only ever pass via the marker leg. Assert a same-uuid engagement
   oracle keyed on `(pid,lstart)` change **plus** `account` change on the same `paneUUID`, plus an
   assistant turn with a timestamp after the /exit. *Mutant:* the existing sid-comparison ⇒ RED.
9. **Launcher-file sweep.** `hooks/session-end.sh:99` sweeps `handoff-selfclose-*.log`,
   `handoff-recycle-*`, `handoff-prompt-nb-*` at +2 d and **not** `lr-launch-*` / `lr-poller-launch-*`.
   MEASURED litter right now: 5 files, oldest 2026-09-05. Add the two globs; assert a >2 d fixture
   file is removed and a fresh one survives.

---

## Open risks

1. **Rung 1 has no answer for `--permission-mode`.** The transcript records model and effort but not
   permission mode; argv is the only source and it dies with the pane. Until `source_argv` is in the
   MANIFEST, an in-place recovery of a `--permission-mode plan` session silently promotes it to
   `auto`. Same shape as the tier bug, one axis over. *(Severity: low frequency, high blast radius —
   `auto` can act where `plan` could not.)*
2. **52e35019 cannot be recovered as-is today.** It has a live split-brain: pane 616's claude
   (pid 80874) and the poller's tmux `lr-resume-52e35019` (pid 77720) are both appending. No
   tombstone exists, so `lr_tombstone_verdict` will NOT refuse — the guard is blind to this shape
   because it keys on the tombstone, and only a transplant writes one. The actuator needs a
   **pre-flight live-writer census** (registry pid + `pgrep -f "resume $sid"` + the tmux session
   list) before any /exit, or it will retire one writer and leave the other.
3. **Seven invisible tmux `lr-resume-*` sessions (325–813 MB each)** are consuming the same accounts
   the recovery is about to route onto. `cc_capacity_admit`'s ACTIVE-session ceiling
   (`CC_ADMIT_ACTIVE_CEILING` 8, reserve 1) may or may not count them; if it does not, a fleet
   recovery will be admitted into a box that is already over. Unverified — I did not read
   `capacity-admit.sh`'s session enumerator.
4. **A driver cannot run the relaunch itself, and the failure is silent-green.** § FORM A's
   measurement: rc 0 in 47 ms with the session dead. Any actuator must type into a pane, never
   execute; and its success oracle must be engagement, never the launcher's exit status. This is the
   single easiest way for the new code to reproduce the old bug in a new place.
5. **The MCP modal has no expect arm.** Latent for `claude-infrastructure` (no `.mcp.json`, MEASURED)
   and live for any repo that has one. `lr-preseed-env.sh` pre-accepts folder trust and raises five
   upsell `*SeenCount` gates but touches nothing MCP. A recovery into such a repo parks at a modal
   with no watcher.
6. **`lr-fire-resume` never `--assign`s the target account**, so a fleet recovery firing N resumes
   is invisible to `claude-accounts`' spread math (`handoff-fire.sh:8567-8571` does assign at pick
   time). Sequencing N recoveries against a non-charging capacity read — the plan's step 4 — will
   read stale headroom.
7. **The `CLAUDE_CODE_RESUME_THRESHOLD_MINUTES=999999999` suppression is version-coupled** to an
   internal 2.1.220 symbol (`lr-fire-resume.sh:349-355`), and 2.1.260 is what runs now. MEASURED:
   window 625's live env carries the var, so it was set — but that proves it was *exported*, not
   that the binary still reads it. The expect menu fallback is wired and tested with
   `LR_RESUME_SUPPRESS=off`; nothing asserts which arm actually fired in production. A silent
   regression here costs a `/compact` and the session's `/goal` on every recovery.
8. **Registration of a launcher-rooted window is unexplained.** 625 has a row, 632 does not, same
   launch shape. I could not identify the path by which 625 registered, so the FORM B recommendation
   rests on removing the uncertainty (a login shell always registers) rather than on having
   diagnosed it. Worth 20 minutes before anyone "simplifies" FORM B back to an argv launch.
9. **Build parity is currently perfect and silently so.** `cc-claude-bin --explain` resolves
   `~/.claude-260/node_modules/.bin/claude` from the `~/.zshrc:496` `_bin` pin (MEASURED), and every
   transcript entry reads `version: 2.1.260` (MEASURED) — a resume lands on the same build the
   source ran. But that is a coincidence of the moment: `cc-claude-bin` reads the **launcher's**
   current pin, not the build the **source session** ran, and the transcript's `version` field is
   the only record of the latter. If the operator repoints the launcher mid-session, the next
   recovery resumes a 2.1.260 transcript on a different build with no warning. Cheap fix: compare
   the transcript's last `version` against `cc-claude-bin --explain` and say so.
10. **A `--goal` cannot replace the ingest prompt.** `handoff-fire.sh:4554-4556` states it plainly —
    *"the goal is never the carrier of the brief"* — and the mechanism agrees: the evaluator is
    tool-less and only re-judges at a Stop, so it can never make a session READ the bundle. `arm_goal`
    is MESSAGE 2, armed after engagement, and `lr-fire-resume` has no second-message channel (its
    `interact` hands the pty to the human). A goal is available to the in-place actuator only as a
    separate `it2_paste_submit_verified` after engagement — worth doing, never a substitute for
    `/limit-recover ingest`.

---

ARTIFACT: /Users/chrisren/Development/.worktrees/lr100p/docs/research/lr100p-2026-09-09/q-relaunch-command.md
