# A recycle can only work in a pane that outlives the session in it

**2026-08-26 · pane 32 · the reso undo session's self-recycle**

## The answer

`--recycle` assumes a shape it never checks: that `/exit` returns the pane to a shell prompt it can
then type the relaunch into. Pane 32 had no shell under its session — its argv *was* the launcher —
so the `/exit` destroyed the pane itself. The successor was never typed, and because the watcher's
only sensor is the pane's own tty, which no longer existed, nothing said so for ten minutes.

Every gate that existed passed. The incident is not "a gate said no and we ignored it"; it is that
no gate asked this question.

## The chain, from the ledgers

| time (UTC) | fact | source |
|---|---|---|
| `2026-08-25T09:45:55Z` | pane 32 created as a kitty **os-window**, argv `bin/reso-resume-one`, hosting sid `30614274…` in `.worktrees/wt-pool-8` | `~/.claude/logs/pane-spawns.jsonl` |
| `06:21:36Z` | fire admitted — `no CC session id — in-flight-subagent check could not run (recycle)` | `~/.claude/logs/handoffs.jsonl` |
| `06:21:37Z` | `recycle-intent` pane 32, brief `/tmp/fire-undo-continue.txt`, account next3 | same |
| `06:21:38Z` | watcher armed, `tty=/dev/ttys021`; `pane-reachable: 32 … ids=6` | `$TMPDIR/handoff-recycle-32-1787725297-6xwfbV.log` |
| ≈`06:23Z` | `/exit` lands → expect exits → **kitty destroys window 32, releases `/dev/ttys021`** | `it2 session list` at 06:24:36Z lists 27/62/59/60/46/63, no 32; `ls /dev/ttys021` → absent |
| `06:24:12Z` · `06:26:43Z` | `recycle-nudge-held  decision=unknown at 150s / 300s` | `handoffs.jsonl` |
| `06:22:45Z` | `lead-supervisor` reaps the session: `why: clean-completion-shipped-clean-worktree` | `~/.claude/autonomy/idl.jsonl` |
| `06:31:45Z` | `recycle-dead — never reached a confirmed shell in 600s (verdict: unknown)` | `handoffs.jsonl` |

Ten minutes, three holds, one ledger row, and the only human-readable remedy it could offer was
*"relaunch manually in that pane"* — over a pane that had not existed for nine of those minutes.

## Why the pane died

```
bin/cc-resume-layout.sh:303   kitty @ launch --type=os-window … -- "$RESUME_ONE" "$acct" "$wt" "$sid" "$br"
bin/reso-resume-one:395       exec expect -c '… spawn -noecho env … claude --resume $sid … interact'
```

`kitty @ launch -- prog` makes `prog` the window's argv — there is no shell in that pane at all.
`exec expect` then makes expect the pane's terminal process, and `spawn` puts claude on a *nested*
pty. So the process tree is `kitty → expect(ttys021) → claude(ttys022)`, and when claude exits,
expect's `interact` returns, expect exits, and kitty closes a window whose only child is gone.

Compare the shape that works, measured on pane 27 the same night:

```
kitty(1427) → zsh(19848, ttys000) → bash cc-close-attrib(93683) → claude(93721)
```

`bin/cc-pane-runner` already states the invariant for the split path — *"AFTER THE COMMAND, THE PANE
BECOMES AN ORDINARY SHELL"* — and execs an interactive login shell when its command returns. The
resume path never adopted it.

## Why nothing noticed

`pane_cc_state` is the watcher's only sensor and it reads the pane's tty. A released pty has no
processes, and that function returns `unknown` for it — correctly, since `unknown` there means
*"this pane could not be read"* and is returned from seven branches, none of which means *"there is
no shell here"*. It is an **abstention**, so the watcher was right to keep waiting; it simply had no
way to ask the one question that was decidable. `it2 session list` settles it in ~36 ms.

The `admitted` row's `no CC session id` and the intent row's `prev_sid: null` are the same session's
identity being unresolvable from inside an expect-wrapped pane. They are a symptom of the shape, not
a second cause, and they degraded the engagement check that would otherwise have been the backstop.

## What changed

1. **`bin/reso-resume-one`** — runs expect as a child and `exec`s `${SHELL} -l -i` when it returns.
   Resumed panes now survive any way their session ends: a crash, a usage limit, a `/exit`. `-l -i`
   is load-bearing for the same reason cc-pane-runner records — the launcher names a relaunch types
   (`claude3`, `nocorrect claude3 …`) are zsh functions defined only in the interactive rc.
   Guarded so the headless test path (`CC_RR_NO_INTERACT`) and any non-tty caller still exit with
   expect's rc rather than being handed an interactive shell.

2. **`pane_shell_root()` + the survivability gate in `recycle_fire`** — refuses to type `/exit` into
   a pane whose *root* process is not a shell. The test is the root (the process whose parent is not
   itself on this tty, i.e. the pane's argv), never the closure: `bash cc-close-attrib` is a shell
   *inside* every CC and would answer yes for every pane on the box. Refuses only on affirmative
   evidence — an unreadable tty answers `unknown` and proceeds, so the gate can add refusals but can
   never remove a recycle that works today. Kill switch `CC_RECYCLE_SURVIVE_GATE=off`. The refusal
   names the remedy that actually works (fire the successor into its own pane, then `self-close`),
   not a retry that would loop forever on this shape.

3. **`pane_enumerated()` + the pane-VANISHED arm in `__recycle`** — the watcher now re-asks
   `session list` every 15 s while it waits. `absent` requires a listing that succeeded and carried
   *other* panes, so a flaky terminal API costs time and never mints a false "your pane is gone".
   On `absent` it writes `recycle-dead` in seconds instead of 600, escalates with wording that says
   the pane is gone, and names the brief — carried in as positional `$9`, because
   `_resolved_prompt_file` is null by construction inside the re-exec.

`tests/handoff-recycle-pane-survives.bats` (23 tests) pins all three, with the pane-32 process table
as its fixture and a `CC_RECYCLE_SURVIVE_GATE=off` control so the assertions cannot be satisfied by
an implementation that refuses for an unrelated reason.

## Two things this does not fix

- **`bin/boot-resume-launch.sh`** uses the same `kitty @ launch … -- prog` shape
  (`"ARGV, not a typed command line"`, :171). Whether its program falls through to a shell was not
  audited here; the survivability gate covers it either way, by refusing rather than by stranding.
- **A general rule for the fleet.** The durable form is that *any* pane an agent may later be asked
  to recycle must end its command with a shell, and only cc-pane-runner and now reso-resume-one
  state that. The gate turns a silent strand into a loud refusal, which is the right polarity, but
  it is a guard rather than a guarantee.

## The generalisable lesson

Two gates asked *"is a session running here?"* and *"is it safe to type here?"*, and both answered
about the **present**. The recycle contract depends on a fact about the **future**: that the pane
will still exist after the act. A precondition nobody states is not thereby satisfied — and when the
act that violates it also destroys the instrument that would have measured it, the failure is silent
by construction. Ask what the pane *is* before typing something that changes what it *will be*.
