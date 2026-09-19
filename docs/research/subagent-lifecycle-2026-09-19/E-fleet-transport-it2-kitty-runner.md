# E · Fleet transport — `it2-kitty`, `cc-pane-runner`, and what a finished teammate leaves behind

Read-only measurement, 2026-09-19. Source tree = `~/Development/.worktrees/wt-research-subagent-lifecycle-2026-09-19`
(= origin/main). Live box: kitty 0.48.2, pid **73832** (socket `unix:/tmp/kitty-73832`, up since 2026-09-16 20:13).
Log: `~/.claude/logs/teammate-lifecycle.log` (4.16 MB, `2026-04-03 02:12:59` → `2026-09-19 11:02:12`).

**Every claim below is marked `[E]` empirical (I ran the read) or `[I]` inferred (from source, not executed).**

---

## 0. The four verdicts

| # | Verdict |
|---|---|
| **V1** | A teammate pane's whole lifecycle is **file mode**: `split` arms it, `run` drops the command as a file, the runner execs it, and on return the runner **unconditionally** execs `$SHELL -l -i` (`bin/cc-pane-runner:83`, reached from `:213`). The pane survives its agent as a bare login shell with a real prompt. |
| **V2** | **`rc=67` is not one defect — it is three, sequentially, and only the third is live.** 166 refusals all-time, bucketed against the actual landing times of the three composer-guard branches, each era is dominated by exactly the case the *next* commit fixed. Today's residual (45 events since 2026-08-10 11:28, most recent 2026-09-17) is **80 % one cause: a pane narrower than 20 columns**. `[E]` |
| **V3** | **No consumer requires a CC-spawned teammate pane to hold a prompt after its command returns.** The one tool that types into a post-exit shell — `bin/cc-husk-sweep:229` — *excludes* live agents by construction and would, on a former teammate pane, be a false positive rather than a dependency. Closing teammate panes on exit removes a population from it; it breaks nothing. `[E]` for the grep, `[I]` for "nothing else". |
| **V4** | **The discriminator is already present at launch, in three independent forms, and the runner consults it for the *run* decision but not for the *exit* decision.** `CC_PANE_CMD_INTERACTIVE` already selects `eval` vs `$SHELL -l -i -c` at `cc-pane-runner:208-212`; the same variable is never read at `:213`. No new plumbing is needed to make the exit behaviour differ by caller. `[E]` |

---

## 1. `vendor it2 call → shim action → pane state afterwards`

The vendor contract is decompiled and pinned in `bin/it2-kitty:10-48`. Dispatch is one `case "$verb"` at `:948`.

| Vendor call (ITermBackend) | Shim line | kitty command actually run | Pane state afterwards |
|---|---|---|---|
| `it2 session split -v -s <leader>` (first teammate) | `:984` + `:1068` | `kitty @ launch --type=window --location=vsplit --cwd=current --keep-focus --match window_id:<s> --next-to id:<s> --source-window id:<s> [--env …] -- $SHELL -l -i -c 'exec "$CC_PANE_RUNNER"'` | Window exists, running **cc-pane-runner blocked on a 50 ms poll** for `$CMD_DIR/<id>.cmd`. No shell, no line editor, no prompt. A `<id>.armed` marker is stamped with the kitty generation at `:1078`. Stdout is exactly `Created new pane: <id>` (`:1088`) — the regex the backend parses. |
| `it2 session split -s <prev>` (later teammates) | same, `loc=hsplit` | as above, `--location=hsplit` | as above. Teammates stack **down a column on the right** of the leader (`:35-38`). |
| `it2 session list` | `:1091` | `kitty @ ls` → python → raw ids, one per line (`--json` gives `[{id,title,cwd,pid}]` for in-repo callers) | unchanged. Ids are **full and untruncated**, deliberately better than the real it2, whose `rich` 80-col truncation makes CC's `stdout.includes(id)` liveness test always read "dead". |
| `it2 session send -s <id> $'\x15'` (Ctrl-U) | `:1142` | **nothing** — `armed "$SESSION" && exit 0` | unchanged. An armed pane has no line to clear; the requested effect already holds. Exit 0 is honest, not a lie. |
| `it2 session send …` on a **non**-armed pane | `:1144` | `kitty @ send-text --match id:<id> -- <text>` (after `prove_target`) | text sits in the pane's line buffer, no Enter. |
| `it2 session run -s <id> <cmd>` **on an armed pane** | `:1199` | **no keystroke at all** — `deliver_argv` writes `$CMD_DIR/<id>.cmd` (tmp+`mv`), then polls ≤ `CC_KITTY_SPAWN_VERIFY_S` (20 s) for the runner to *delete* it | runner reads it, `rm -f`s **both** `.cmd` and `.armed` (`cc-pane-runner:253`), echoes the command, arms `cc-wedge-watch`, then runs it. Pane is now the agent. Non-zero here ⇒ CC throws a real spawn failure. |
| `it2 session run …` on a **live TUI** | `:1209` | `type_verified` abstains (rc 2) ⇒ `kitty @ send-text -- <text>\r` | text submitted into the composer. |
| `it2 session type -s <id> <text>` (in-repo only, 2026-09-17) | `:1179` | `kitty @ send-text -- <text>\r`, **always typed**, no armed check | the message-not-command seam. `handoff-fire.sh:1438` uses it for `/exit`. |
| `it2 session close -f -s <id>` | `:1213` | `identity_ok` (if pinned) → **composer guard** → `kitty @ close-window --match id:<id>` (`:1261`) | window gone — **or** `exit 66` (pin unmet, `:1227`) / **`exit 67`** (composer guard, `:1257`), in which case the pane survives untouched and a screen snapshot is written to `~/.claude/logs/composer-snapshots/`. `-f` is accepted and ignored; kitty has no running-job modal. |
| `it2 session focus\|read -s <id>` | `:1285-1286` | `kitty @ focus-window` / `kitty @ get-text` | unchanged. A missing `-s` is **exit 64**, not a bare rc 1 — that collision is what made backlog `bd1086f74866` blame the read path for a usage error. |
| anything else | `:1290` | — | `exit 64`. |

### Delivery modes — env vs file

Decided in one `if/elif` at `it2-kitty:1035-1063`, and the two modes are *not* symmetric:

| | **ENV mode** (predelivered) | **FILE mode** (armed) |
|---|---|---|
| Trigger | `CC_PANE_CMD` non-empty in the shim's own env | `CC_PANE_CMD` unset (the CC protocol: split first, command later) |
| Launch `--env` | `CC_PANE_CMD`, `CC_PANE_CMD_INTERACTIVE`, `CC_PANE_RUNNER` (`:1039-1042`) | `CC_PANE_CMD_DIR`, `CC_PANE_RUNNER` (`:1057-1058`) |
| `.armed` marker | **never written** — nothing further is delivered, and a stale marker would swallow the next legitimate `run` | written at `:1078`, stamped with `kitty_generation` |
| Runner path | `cc-pane-runner:225` fires before the dir/id checks — env mode needs neither | `:230-245` poll loop, `CC_PANE_CMD_WAIT_S` default 300 s |
| Race window | **none** — argv and env in one atomic launch | ~one `run` round-trip, proven closed by `deliver_argv`'s pickup ack |
| Users | `handoff-fire.sh:1076` and `:11110`; `limit-recover/lr-lib.sh:327` | Claude Code teammates, exclusively |

Marker hygiene is now double-locked: the runner consumes `.armed` on **every** exit path (`cc-pane-runner:81` inside `_fallback`, not only at `:253`), and `armed()` (`it2-kitty:377-389`) refuses a marker from another kitty generation or older than `CC_PANE_CMD_WAIT_S + 60`. **`[E]`** live state: exactly one marker on disk, `~/.claude/run/kitty-pane-cmd/105.armed`, content `73832\n` — *this* kitty's generation, but written 2026-09-18 17:09 (≈ 18 h old) for a window that no longer exists. Generation pin passes; **the TTL is what makes it inert.** That is the 2026-09-17 `KITTY_RECYCLE_TRANSPORT` defect's exact shape, caught by the second lock.

---

## 2. `rc=67` — mechanism, and the three-era decomposition

### The predicate

`composer_state()` (`it2-kitty:777-946`) returns one of seven states from **one** `kt ls --match id:<n>` plus **one** `kt get-text --ansi`, both through the same `kt()` socket the close travels. `close` passes `EMPTY|NO-TUI|AGENT-PANE|AGENT-NO-BOX|DEAD-PANE` (`:1237`) and refuses everything else with `exit 67` (`:1257`).

The screen half, verbatim in substance:

```
thresh  = max(20, cols // 2)                       # cols from kitty
is_rule = a line with >= thresh box-drawing glyphs, OR a line that is nothing but
          box-drawing + a single @token and whose total length >= thresh
rules   = indices of is_rule lines
body    = lines[rules[-2]+1 : rules[-1]]  if len(rules) >= 2  else []
if body and "❯" in body[0]:  -> EMPTY / NON-EMPTY   (dim SGR-2 runs are NOT content)
else:
  agent_pane = agent != "-" and len(rules) == 1 and ("@"+agent) in flat[rules[0]]
  no_box     = agent != "-" and len(rules) == 0 and not any("❯" in l for l in flat)
  print(AGENT-PANE/AGENT-NO-BOX if alt and passing else ("UNKNOWN" if alt else "NO-TUI"))
```

`agent` is PROOF 1 (`:800-812`): a foreground process whose argv contains `--agent-id` **and** whose
`basename(argv[0])` matches `claude(\.exe)?$`; its `--agent-name` value must then appear in the footer (PROOF 2).
`alt` is `in_alternate_screen is not False` — an identity test, so a *missing* field reads as "a TUI may be up".

**Why a teammate pane is structurally the hard case:** a CC agent pane paints **one** rule (its `──── @name ──`
footer) and **no composer box**, so `len(rules) >= 2` fails, `body` is empty, `alt` is True — and before
2026-08-09 that landed straight in the UNKNOWN arm written for permission modals. The one population that
provably holds no operator draft was the one population the guard convicted.

### Counts `[E]`

`/usr/bin/grep -c 'rc=67' ~/.claude/logs/teammate-lifecycle.log` → **166**, against **1270** `✓ closed pane`
and **16268** `Auto-shutdown idle teammate` fires. All 166 say *"composer state is UNKNOWN"* — **zero** are
`NON-EMPTY`, i.e. **not one refusal in the fleet's history was a real operator draft.** Other close failures:
rc=1 × 27, rc=124 × 7, rc=3 × 6, rc=4 × 5. Total failed closes 211.

Per day (anchored on the line-start timestamp — a greedy `.*` grabs the trailing `incident 2026-08-07` from
every line and reports a false `166 on 2026-08-07`; fleet memory *greedy-anchor-matches-the-longer-token*):

```
2026-08-07  46    2026-08-12   3    2026-09-04   5    2026-09-11   4
2026-08-08   1    2026-08-17   3    2026-09-08  13    2026-09-15   3
2026-08-09  24    2026-08-30   1    2026-09-09   2    2026-09-17   4
2026-08-10  57
```

### The decomposition that matters

The three guard branches landed at three distinct times (`git log -S`, local clock, same clock as the log):

| commit | landed | added |
|---|---|---|
| `fe7b675ad` | 2026-08-07 01:16 | the composer guard itself |
| `d3951e5e3` | 2026-08-09 22:41 | `AGENT-PANE` (one rule + label + argv proof) |
| `5f5fd7270` | 2026-08-10 11:05 | `AGENT-NO-BOX` + `DEAD-PANE` (a finished agent paints no footer) |
| `2a352788b` | 2026-08-10 11:28 | `is_rule`'s label-aware second form (a narrow pane hides its own footer) |

Re-classifying all 166 refusals by their own screen snapshot, bucketed by era `[E]`:

| era | n | dominant cause | share |
|---|---|---|---|
| **1** guard only | 71 | **1 rule carrying an `@label`** — the `AGENT-PANE` case | 48 (68 %) |
| **2** +`AGENT-PANE` | 50 | **0 rules, no `❯`** — the finished-agent case | 44 (88 %) |
| **3** +`AGENT-NO-BOX`/`DEAD-PANE` | 0 | — | — |
| **4** all branches landed | 45 | **0 rules + a `❯` on screen** — the narrow-pane residual | **36 (80 %)** |

Each era's dominant cause is precisely what the *next* commit was written to fix, and **that cause then drops
to zero.** Era 4 carries **no** `0-rules-no-glyph` cases at all, so there is no live evidence that PROOF 1 ever
fails to identify a real teammate — a hypothesis I raised and then refuted. Era 4's remainder: 4 unreadable
`get-text`, 4 one-rule-without-a-label, 1 snapshot missing.

### The live cause, named

**A teammate pane narrower than ~20 columns whose composer glyph is still painted.** `thresh` has an absolute
floor of 20, so on a 14-column pane a full-width footer rule carries 14 glyphs and *cannot* clear it under
either `is_rule` form — `2a352788b`'s label-aware branch also ends in `len(s) >= thresh` and is equally floored.
`rules` is therefore `[]`, `AGENT-NO-BOX` is blocked by its own `not any("❯")` proof, and the verdict is UNKNOWN.

`[E]` The six most recent refusals (2026-09-17 22:18–22:25, windows 89 `rc-consumer-audit` and 90
`t17-resident-reload`) have snapshots of 324–338 bytes with **max line width 14, max box-drawing glyphs per
line 14, one `❯`, an `@rc-consumer-audit` footer, and `✻ Cooked for 10s · done`** — a live, finished, labelled
agent pane the guard could read perfectly if the floor were `min(20, cols)` instead of `max(20, …)`.

`[I]` This is *documented as deliberate* at `it2-kitty:938-941`: *"a composer that IS rendered but whose rules
fell under the `max(20, cols//2)` floor on a narrow pane still shows its glyph, so this abstains there instead
of destroying it."* It is a designed abstain, not a bug — but its population is now 80 % of all residual
refusals, and the measured population of NON-EMPTY refusals across the guard's entire life is **zero**.

### Is the refusal ever retried or escalated? **No. `[E]`**

`close_and_log` (`teammate-auto-shutdown.sh:279-330`) handles 67 in the generic failure arm (`:320`):
log `✗ pane close FAILED (rc=67)`, `retract_teardown_marker`, and `_page_desk_damped` keyed on
`CLOSE-FAILED:<pane>:<who>:rc67` — **state, not a clock**, so the *same* stuck pane never pages twice.
There is no second attempt, no `CC_CLOSE_COMPOSER_GUARD=off` retry (the only two references to that variable
in the whole tree are `it2-kitty:725` and `:1234` — no caller sets it), no `kitty @ close-window` fallback,
and no path that escalates to a kill. Repeats in the log are **re-fires of the hook on the next TeammateIdle
event**, not retries: win 182 `antigravity-probe` × 5, win 744 `bin-sweep` × 5, win 448 `fleet-silences` × 4.
`rc=66` is handled separately and ahead of everything (`:305`) because it means *"I did not act"*.

The measured cost of the refusal, from the source's own record (`it2-kitty:743-747`): ten `claude.exe`
children surviving **5 h 16 m** past completion, **5.9 GB RSS**, closed 160 times and refused every time.

---

## 3. Live census `[E]` — `kitty @ ls` + `ps -axo pid,ppid,lstart,tty,etime,comm`, 2026-09-19 ~11:25

**7 windows. Zero teammate panes. Zero former-agent panes.**

| win | cols×lines | alt | foreground | cwd | age |
|---|---|---|---|---|---|
| 110 | 51×47 | True | `…/.claude-260/node_modules/.bin/claude` (+`caffeinate`, `ms-365-mcp-server`, `tee`, `bash cc-close-attrib`) | `sevenrooms-bridge` | 11 h 45 m |
| 111 | 51×47 | True | same shape | `claude-infrastructure` | 11 h 42 m |
| 112 | 51×47 | True | same shape | `reso-management-app` | 1 h 27 m |
| 114 | 51×47 | True | same shape | `reso-management-app` | 1 h 20 m |
| 117 | 156×48 | True | same shape | `claude-infrastructure` | 26 m |
| 121 | 51×47 | True | same shape | `claude-infrastructure` | 15 m |
| **120** | 51×47 | **False** | **`/bin/zsh -l`** (pid 7934, ppid 73832 = kitty) | `claude-infrastructure` | 20 m |

Classification:
- **`claude.exe --agent-id` teammate panes: 0.** All six agents are the *interactive launcher* spelling
  `node_modules/.bin/claude`. The two families are measured disjoint (`capacity-alarm.sh:661`,
  `hooks/lib/agent-identity.sh:14`).
- **Bare shell descended from `cc-pane-runner`: 0.** Window 120 is a bare shell, but it is **not** a former
  agent pane — its kitty window `env` carries **no** `CC_PANE_CMD_DIR`, **no** `CC_PANE_CMD`, **no**
  `CC_PANE_RUNNER`, and its argv is `/bin/zsh -l` (one flag), where the runner's fallback execs
  `$SHELL -l -i` (`cc-pane-runner:83`). It is an operator-opened kitty window.
- **Other Claude sessions: 6**, ages 15 m → 11 h 45 m.

`ppid` is useless for this question and the census does not use it: the runner chain is
`kitty → zsh -l -i -c 'exec …' → cc-pane-runner → exec agent → exec zsh -l -i`, all one pid whose parent is
kitty — identical to a plain kitty window. **The kitty window `env` is the discriminator that survives**
(see §5).

---

## 4. (b) The exec-shell-after-exit decision, and who actually depends on it

`bin/cc-pane-runner:46-51` states the rationale: *"Exact parity with the pane this replaced… That also keeps
every LATER `it2 session run/send` against this pane behaving as it always did (there is a real prompt to type
at again), which is what makes this change safe for the multi-send callers that legitimately type."*

The exec is at `:83` inside `_fallback()`, reached from **six** places: the four early bail-outs
(`CC_PANE_CMD_DIR` unset `:227`, `KITTY_WINDOW_ID` unset `:228`, wait-loop timeout `:241`, empty command `:255`)
and — the one that matters — `_launch`'s unconditional tail `_fallback ""` at `:213`, i.e. **the normal path
after a successful agent run**. It reads no variable and takes no branch.

### Enumerated consumers of a prompt in an agent pane after the command returns

| Consumer | site | Needs a post-exit prompt? | Population |
|---|---|---|---|
| `bin/cc-husk-sweep` | `:229` types `nocorrect CC_ACCOUNT_PINNED=1 <launcher> --resume <sid>` via echo-verified `type_line` | **YES — this is the only one** | panes where `has_claude_under "$pid"` is **false** (`:195`), i.e. a bare shell over a dead session |
| `scripts/handoff-fire.sh` `as_write` | `:1406-1442` | **No** — targets a *live* CC composer; uses `session type` precisely because `run`'s armed path can only fail there | handoff/recycle/self-close panes |
| `bin/reso-keepalive` | `:217-219`, `:231-233` | **No** — nudges *idle live* panes (keys on "esc to interrupt" absence); its own header notes `send` no-ops on an armed pane | recovered/quota-burner reso sessions, re-discovered by worktree marker |
| `bin/cc-pane` `send`/`spawn` | `:146,:149,:221` | **No** — sets `CC_KITTY_ARGV_SPAWN=0` and owns its own typing | its own spawns |
| `hooks/teammate-auto-shutdown.sh` | `:198` | **No** — closes, never types | teammates |
| `bin/cc-teardown`, `scripts/assignee-pane-residency.sh`, `bin/cc-spawn-verify` | — | **No** — all key on **`ps`**, explicitly not on the pane. `cc-spawn-verify:113-117`: *"WHY NOT `foreground_processes`… it is a sample with no stability guarantee"* | teammates |
| `bin/cc-wedge-watch` (armed by the runner at `:182`) | — | **No** — runs *during* startup, not after exit | claude-verb panes |

### Adversarial pass — I went looking for the consumer that would break

The brief asked me to hunt for one. `cc-husk-sweep` is the only candidate and it **inverts**:

1. Its filter (`:195`) selects panes with **no** claude under them — so it can only ever see a teammate pane
   *after* the runner has dropped to a shell. A teammate pane closed on exit is never in its input.
2. Its resolver (`:97-143`) tries registry → scrollback → transcript. A teammate pane has **no cc-registry
   row at all** (134/134 — `cc-pane-runner:136` citing `hooks/lib/lead-crash-watchdog.sh:596`), and the
   scrollback leg's regex is `claude[0-9]\{0,1\} --strict-mcp-config` (`:125`), which **cannot** match the
   teammate spelling `claude.exe --agent-id …`. Only the transcript leg (`:143`, newest `*.jsonl` for the
   pane's cwd across four account stores) could answer — and it would answer with the *lead's* launcher and a
   sid it inferred from a shared worktree.
3. So a surviving teammate husk in `cc-husk-sweep --resume` is a **false positive that spends quota
   resurrecting a finished teammate**, not a capability. `[I]` — I did not execute `cc-husk-sweep` (it types
   into panes; out of bounds), so this is a source-and-population argument, not an observed run.

**Nothing else reads or writes a teammate pane after its command returns.** The residency/reap/verify/teardown
family all key on `ps` by design, so the pane's continued existence is not their evidence. The `✓ closed pane`
outcome metric is verified by **absence** from `session list` (`teammate-auto-shutdown.sh:297-307`), which a
closed pane satisfies. The teardown marker is written **before** the close (`:275`) and read from disk, not
from the pane.

**Answer to (b): a CC-spawned teammate pane (file mode, `CC_PANE_CMD_INTERACTIVE` unset) has no consumer of
its post-exit prompt.** The `exec $SHELL -l -i` is load-bearing for the *handoff/recycle* population and for
the four *failure* bail-outs (where a pane at a prompt is a readable diagnostic, per `:64-66`); for the
teammate population it is parity with a shape nobody depends on, and it is the mechanism F-c names as the
reason external `close-window` is mandatory.

---

## 5. (e) Does the runner see the difference at launch? **Yes — three ways, already.** `[E]` on source

| Signal | CC teammate | handoff fire | Where it is set / read |
|---|---|---|---|
| Delivery mode | **FILE** (armed) | **ENV** (predelivered) | `it2-kitty:1035` vs `:1046`; runner `:225` vs `:230` |
| Launch `--env` | `CC_PANE_CMD_DIR`, `CC_PANE_RUNNER` | `CC_PANE_CMD`, **`CC_PANE_CMD_INTERACTIVE=1`**, `CC_PANE_RUNNER` | `it2-kitty:1057` vs `:1039-1041`; `handoff-fire.sh:1076`, `:11110` |
| `$CMD_DIR/<id>.armed` | **written** (`:1078`) | **never written** (by design — nothing further is delivered) | — |
| Run shell | `eval "$1"` (bash) | `$SHELL -l -i -c "$1"` | `cc-pane-runner:208-212` |
| Launch verb | `claude.exe`, argv carries `--agent-id`/`--agent-name`/`--team-name` | `claude4` / `nocorrect claude4 …` (a zsh **function**, which is why `-i` is load-bearing) | `cc-pane-runner:161-165`; `:89-97` |
| Persists in `kitty @ ls` `env`? | yes — the launch env is static | yes | `[E]` verified: all 7 live windows report **absent** `CC_PANE_CMD_DIR`, correctly, because none is an agent pane |

**The discriminator is not merely present — it is already consumed once.** `cc-pane-runner:200` reads
`_interactive="${CC_PANE_CMD_INTERACTIVE:-0}"` and branches the *execution* shell on it at `:208`. The same
variable is in scope thirteen lines later at `:213` and is not read. A caller-dependent exit disposition
therefore needs **no new plumbing, no new env var, and no sniffing** — only a branch at `:213`.

Two cautions on any such change `[I]`:
- `_interactive` is `unset` at `:201` *before* `_arm_wedge_watch` and the command run, so the value must be
  captured (it already is, in the local) rather than re-read after.
- The four **failure** bail-outs must keep execing a shell. `:64-66` is explicit: *"A pane that vanishes
  because a variable was unset takes its diagnostic with it."* Only `:213` — the *successful-return* path —
  is the candidate, and only for the file-mode/teammate arm.

---

## 6. Corrections to the record

| Claim | Status |
|---|---|
| `docs/plans/TEAMMATE_SELFCLOSE_INVESTIGATION.md:15` — *"`rc=67` has not recurred since 2026-08-17"*, cited as a cleared falsifier arm in a **COMPLETE 2026-08-20** front matter | **FALSE `[E]`.** 32 refusals after 2026-08-17: `08-30 ×1, 09-04 ×5, 09-08 ×13, 09-09 ×2, 09-11 ×4, 09-15 ×3, 09-17 ×4`. It was true on the day it was written; the doc has no path to learn otherwise. Re-derive: `grep 'rc=67' ~/.claude/logs/teammate-lifecycle.log \| sed -E 's/^\[([0-9-]+).*/\1/' \| sort \| uniq -c` |
| Same doc, F-c at `:588` — *"`bin/cc-pane-runner:115` `exec`s an interactive login shell when the agent command returns"* | **Conclusion correct, citation stale `[E]`.** The exec is now `cc-pane-runner:83` (reached from `:213`); line 115 today is prose inside the wedge-watch header. Fleet memory *insertions break line citations*. |
| `~/.claude/bin/it2` "is the kitty shim" | **No `[E]`.** `~/.claude/bin/it2` is a **real 14,433-byte bash file** (the iTerm2 wrapper, three interceptions, 30 s process bound) — *not* a symlink. `~/.claude/bin/it2-kitty` **is** a symlink into the checkout. `command -v it2` → `/Users/chrisren/.claude/bin/it2`. The kitty adapter is reached *through* the wrapper, which is exactly the confusion `reso-keepalive:23-27` records ("There is no bin/it2"). |
| Era boundaries = commit times | **Lower bound only `[I]`.** `~/.claude/bin/it2-kitty` symlinks the shared checkout, so a commit goes live on the next `deploy-live` fast-forward, not at commit. The clean era-by-era separation is itself evidence the lag was short here, but I did not measure it. |

---

## 7. Uncertainties, named

1. **Snapshot fidelity.** The refusal snapshot is taken *after* the verdict, with `kt get-text` **without**
   `--ansi`, while `composer_state` read **with** `--ansi`. Plain text is identical, so rule/glyph counting is
   sound; **dim-vs-content cannot be re-derived from a snapshot.** This does not affect the era-4 conclusion
   (those cases never reach the body read).
2. **`cols` proxy.** I used each snapshot's max line width where the guard uses kitty's `columns`.
   `maxwidth ≤ cols` ⇒ my `thresh ≤` the real one ⇒ my rule count is an **over**-estimate. A measured
   "0 rules" is therefore certainly 0 rules; a measured "1 rule" could have been 0. Direction is safe for
   every conclusion drawn.
3. **17 of 844 snapshots cited by rc=67 lines are 0 bytes** (644 of all 844 are — most belong to *other*
   guard callers, not this hook). A 0-byte file means `kt get-text` failed or printed nothing; the log line
   would then read `screen snapshot: (not captured)`, which occurs **once** in 166. So the 0-byte files are
   mostly genuine empty reads, not failed captures — but I cannot separate "blank screen" from "RPC returned
   empty" retroactively.
4. **No teammate pane was live during the census**, so PROOF 1's behaviour on a real `claude.exe --agent-id`
   pane is `[I]` from source plus the era-4 *absence* of `0-rules-no-glyph` refusals, not `[E]` from a
   reading. A wave running under this kitty would settle it in one `kt ls --match`.
5. **cc-husk-sweep's transcript leg on a teammate pane is untested** — running it would type into panes,
   which is out of bounds. Its registry and scrollback legs are refuted from source with high confidence; the
   transcript leg is the residual.

## 8. Alternatives considered and ruled out

- **"PROOF 1 misses live teammates because `foreground_processes` is a sample."** Raised, then refuted:
  `cc-spawn-verify:115-117` measured it **over**-reporting (29/29 live panes contained `claude`), and era 4
  contains zero `0-rules-no-glyph` refusals, which is the signature that failure would leave.
- **"The 2026-08-07 spike is the whole story."** Artifact of a greedy `sed` — every rc=67 line ends with
  `incident 2026-08-07 06:41Z`. Corrected by anchoring on `^\[`.
- **`ppid` / process ancestry as the former-agent-pane discriminator.** Dead on arrival: the runner chain is
  four `exec`s in one pid whose parent is kitty, identical to a plain window. The kitty window `env` is the
  surviving signal.
- **`-f` as a guard bypass.** Explicitly refused at `it2-kitty:725`: every automated caller passes `-f`, so
  an `-f` exemption is a guard that never runs.
