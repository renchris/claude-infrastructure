# T10 — What genuinely cannot be automated away

STATUS: in progress. Sections land as they are measured.
RAN = I executed it this session. READ = I read it in the tree.

---

## §0 THE HEADLINE (conviction 92%)

"No human in the loop" is unreachable on this box, and the binding constraint is **not**
the permission allowlist. It is a **three-layer** permission stack in which the layer that
actually refuses — auto mode's natural-language `soft_deny` classifier — is (a) unreachable
from `settings.json` allow rules, (b) explicitly contains a clause forbidding the agent from
widening it, and (c) reports its verdict as a **constant string** with no machine-readable
cause, so not even a feedback loop can be built against it.

What CAN go to zero: the keystroke on any reversible, in-worktree, agent-authored action.
What CANNOT: four irreducible classes — **CONSENT** (a shared artifact the agent did not
create), **SELF-AUTHORIZATION** (widening its own permissions), **VALUE** (what "done" and
"acceptable risk" mean), and **PROCESS IDENTITY** (a binary replacement cannot be applied to
the process that is already running).

---

## §1 THE PERMISSION LAYER — three layers, not one

RAN `python3 -c "json.load(~/.claude/settings.json)"`:

| layer | where it lives | size (measured) | agent-writable? |
|---|---|---|---|
| 1. static rules | `~/.claude/settings.json` `permissions` | allow **339** · ask **6** · deny **41** | NO (soft_deny *Self-Modification*) |
| 2. PreToolUse hooks | 18 registrations on `PreToolUse` in live settings | 20 hook files emit `permissionDecision` | NO (same) |
| 3. auto-mode classifier | `~/.claude/settings.json` `autoMode.soft_deny` | **37 natural-language clauses** | NO (same) |

`permissions.defaultMode` = `"auto"` (RAN). So layer 3 is live on every call.

### 1a. Layer 3 is the one that fired tonight — measured, not inferred

RAN, over `~/.claude/logs/permission-denied.jsonl` (the `PermissionDenied` refusal ledger,
`hooks/permission-denied.sh`; 194 rows, 2026-09-08 → 2026-09-17T04:40Z):

```
MODE: [('auto', 194)]          ← every single refusal came from auto mode
TOOL: Bash 188 · Edit 2 · mcp__ms365__delete-mail-message 2 · WebFetch 2
29 denials since 2026-09-16T20:00Z (tonight alone)
```

The four classes the brief names are all in it, verbatim:

| time (UTC) | denied command head | class |
|---|---|---|
| 01:37:17 | `cd ~/Development/claude-infrastructure && cp config/kitty.conf … python3 - <<'PY'` | edit a shared config |
| 02:18:30 | `git add config/kitty.conf` + `git commit -q -F -` | commit that change |
| 02:48:42 / 02:49:22 / 02:49:53 | same `git add`/`git commit`, **three more attempts** | " |
| 01:37:41 · 02:10:39 · 04:22:48 | `kill 22460` / `kill 27412` / `kill 99806` | signal a process |
| 02:50:50 | `SHIP_LAND_GATE_ROUNDS=0 LAND_LOCK_WAIT=2400 bash scripts/ship-land.sh` | env-prefixed land |
| 02:51:21 | `bash scripts/ship-land.sh` (**bare**, no env prefix) | land |

🚨 **The env prefix was not the discriminator.** The bare form was denied 31 s later. Do not
generalise "the env prefix is what did it" — one refusal bounds the tool, and the control
arm is right there in the ledger.

### 1b. `git add` IS allow-listed and was denied anyway

`Bash(git add:*)` is entry #… of the 339 fleet allow rules (RAN, printed above);
`Bash(git commit:*)` is in `.claude/settings.local.json:21`. Both matched, both refused.
This is the single most important fact for "can the allowlist fix it": **the classifier
overrides a matching allow rule.** `bin/cc-permission-audit`'s own header says so
(READ, `bin/cc-permission-audit:9-12`):

> "Auto mode runs a classifier on top of the static rules and silently approves much of what
> does not match a literal rule; it also cannot see prompts the classifier raised **for a
> command that DOES match**."

### 1c. Auto mode additionally DELETES allow rules before matching

READ `hooks/lib/permission_matcher.py:865-970` — a verbatim transcription of the decompiled
2.1.220 classifier (`gsn`/`_sn`/`iSd`/`nSd`/`PHs`). Auto mode **discards** any allow rule for:

```python
DROP_CMDS = ("python","python3","python2","node","deno","tsx","ruby","perl","php","lua",
             "npx","bunx","npm run","yarn run","pnpm run","bun run",
             "bash","sh","ssh","zsh","fish","eval","exec","env","xargs","sudo")
DROP_NET  = ("curl","wget","kubectl","aws","gcloud","gsutil")
```
plus every `Agent` rule, bare `Bash`, and any all-wildcard content
(`permission_matcher.py:925-968`).

Consequence for tonight: `bash scripts/ship-land.sh` can never be allow-listed —
`Bash(bash:*)` is dropped by construction, and `Bash(scripts/ship-land.sh:*)` (which IS in
the fleet allow list) does not match a command whose first token is `bash`.

⚠️ Honest bound the file states about itself (`permission_matcher.py:884-886`): this predicate
is **code-and-doc verified, NOT probe-verified** — "no observable distinguishes 'allowed by
rule' from 'allowed by classifier' in auto mode." It is a claim about CC 2.1.220 and can rot.

### 1d. The refusal carries NO machine-readable cause — and the shipped doc is now stale

RAN, reason distribution over all 194 rows:

```
167  'Blocked by classifier'
 17  'Classifier unavailable'
 10  'Stage 2 classifier error - blocking based on stage 1 assessment (usually transient…)'
```

`hooks/permission-denied.sh:35-38` (READ) documents the measured 2.1.220 payload as:
"`reason` is the classifier's own prose sentence, not a code." On the live binary it is a
**constant**. So:

* You cannot attribute a refusal to one of the 37 `soft_deny` clauses from the ledger.
* You cannot build a closed loop ("clause X fires N times/week, propose a narrowing") because
  the signal has one bit.
* **27 of 194 (13.9%) of refusals are not policy at all** — `Classifier unavailable` and
  `Stage 2 classifier error` are infrastructure faults. That slice IS automatable (retry with
  backoff) and is currently paid for with a human keystroke.

### 1e. Verifying the census claim (brief item 1)

READ `docs/research/permission-prompt-census-2026-09-10.md:41-53`. The claim and its basis:

```
C: allow rule only, no probe hook      -> tool RAN
A: hook returns ask, no allow rule     -> BLOCKED (probe-ask-from-hook)
B: hook returns ask + allow rule       -> BLOCKED (probe-ask-from-hook)
=> A permissions.allow rule does NOT suppress a PreToolUse hook's ask.
```

**BASIS: sound, and better than most.** Three arms, one variable, a positive control (arm C
proves the allow rule works when nothing else intervenes), run on the live binary 2.1.260
rather than inferred from docs. It also explicitly WITHDRAWS a corpus result that looked
like evidence (`:50-53`): a naive prefix matcher claimed 562 overlaps, but CC evaluates each
statement of a compound command, so those were `cd`-prefix artifacts; restricted to
single-statement commands the overlap is **0 of 16**, i.e. the corpus could never settle it
in either direction. That withdrawal is what makes the live probe load-bearing rather than
decorative.

**What I did NOT re-run:** I did not reproduce the three arms. Reproducing them means
registering a probe hook in a settings file, which is the self-authorization ban (§2).
Conviction the claim holds today: **85%** — high because of the control arm and the
withdrawal, discounted because it is a single-session measurement on a binary that has moved
(the sibling claim in `hooks/smart-bash-allowlist.sh`'s header, that a hook's `allow`
BYPASSES the permission system, is contradicted by Anthropic's published docs and is recorded
in this repo's own memory as UNKNOWN).

**IMPLICATION FOR "NO MANUAL COMMANDS":** the census measured **1,038 of 2,838** archived
prompts (36.6%) as hook-emitted, hence structurally unreachable from `settings.json`. But the
census predates the finding in §1a-1b: layer 3 refusals are a *further* population that no
allow rule reaches either, and unlike layer 2 they do not even leave a reason. The honest
ceiling on "edit the allowlist until the prompts stop" is therefore **strictly worse than the
census's 36.6% floor**, and nothing in the tree measures where it actually sits.

### 1f. What the human-in-the-loop currently COSTS — measured

RAN over `~/.claude/autonomy/permission-archive/*.jsonl` (4,503 resolved prompts):

```
waited_s   min 0 · p50 12 · p90 1,508 (25 min) · p99 33,909 (9.4 h) · max 81,411 (22.6 h)
total agent wall-clock spent blocked on a human keystroke: 1,966 hours
last 7 days: 548 prompts · median 63 s · 212.6 hours blocked
```

The distribution is the argument, not the mean: **the median prompt costs 12 seconds and the
p90 costs 25 minutes.** Half of them are nearly free; the tail is where the pipeline dies,
because the tail is "the operator was asleep."

### 1g. The one mechanism that could have automated layer 3 exists and is NOT WIRED

`hooks/model-permission-decider.py` (READ) is a PreToolUse Bash decider that routes a would-be
prompt to a model with session + repo context, emitting only `allow` or `ask` (`deny` is
deliberately unreachable: "a wrong `deny` wedges the session with no human in the loop; a
wrong `ask` costs one prompt", `:12-16`).

RAN: `grep -c model-permission-decider ~/.claude/settings.json` → **0**. It appears in ZERO
settings files across the fleet (`migrations/0022-mitl-decider-shadow.sh:11`, READ).

Its registration is staged as `migrations/0022-mitl-decider-shadow.sh`, **in SHADOW mode**
(logs the verdict it WOULD emit, changes nothing), and that migration is class **c10** —
"it edits settings.json, the live permission surface" (`:3`) — which by convention is
*staged, never run* by an agent. So the single highest-leverage automation of the permission
layer is sitting on disk, one operator command from being measurable, and an agent may not
fire it. **That is a decision, not a keystroke** (see §2).

### 1h. 🚨 THE FINDING THAT REFRAMES THE WHOLE QUESTION: most refusals are NOT prompts

RAN, joining the 29 refusal-ledger rows since 2026-09-16T20:00Z against the 4,503-row prompt
archive on a ±90 s window:

```
4/29 classifier denials coincided with an archived permission PROMPT
```

**25 of 29 (86%) refusals raised no prompt at all.** There was no dialog, no keystroke, nothing
for the operator to press. The tool was refused, the agent got an error string
(`Blocked by classifier`), and the only route forward was for the agent to write prose asking the
operator to do it, and for the operator to read that prose and act.

This splits the "human in the loop" problem into two populations that behave nothing alike:

| population | size | what the human does | latency | ends in approval |
|---|---|---|---|---|
| **PROMPT** (`PermissionRequest` beacon) | 4,503 archived | presses a key | p50 **12 s**, p90 25 m | **98.2%** (4,420 of 4,503 resolved by `PostToolUse`, i.e. the tool ran) |
| **REFUSAL** (`PermissionDenied` ledger) | 194 in 9 days | must be *told*, then act himself | unbounded — depends on him reading chat | unmeasurable; no dialog exists |

The PROMPT population is a **keystroke** problem and is 98% rubber-stamp. The REFUSAL population
is not a keystroke problem at all — it is a **hand-back** problem, and it is the one that stalls
a pipeline overnight.

*(Beacon semantics verified before quoting: `hooks/cc-permission-beacon.sh:20-27` — a
`PostToolUse` clear fires only for the invocation it is the `PostToolUse` OF, so `resolved_by =
PostToolUse` means the prompted call actually RAN. Denials clear via `Stop` (66) / `SessionEnd`
(16), so refusals-after-prompt are ≤83 of 4,503 = ≤1.8%.)*

---

## §2 THE SELF-AUTHORIZATION BAN — confirmed, and it is THREE independent arms

CONFIRMED, all three read this session:

1. **Policy** — `CLAUDE.global.md:994`: *"🚨 NEVER script your own authorization — no permission
   grants, `settings*.json`, allowlists or credential writes in a file you hand over; ask in chat,
   alone."*
2. **Mechanism (the classifier itself)** — `~/.claude/settings.json` `autoMode.soft_deny`, clause
   verbatim: *"**Self-Modification:** Modifying the agent's own configuration, settings, or
   permission files to change the agent's own behavior or permissions."* A further clause,
   *"**Memory Poisoning:** Writing content to the agent's memory directory … that would function as
   a permission grant or BLOCK-rule bypass when read back"*, closes the obvious side door.
3. **Convention** — `migrations/README.md:68`: class **`c10`** = *"staged, never run"*; *"A
   migration that touches `settings.json`, a launchd plist, or credentials declares `c10` and waits
   for a human"* (`:75`). `:78` — promoting one is a **one-word diff** once the operator ratifies,
   and `:74` records that *"that ratification has not happened."*

**The read half is genuinely automated and is not a token gesture.** RAN/READ:

* `bin/cc-permission-audit` — writes nothing without `CONFIRM=1` (`:241-242`); `--prune` is dry-run
  by default with a per-file backup; a rewrite of a discovered `settings.json` requires naming the
  path explicitly.
* `bin/cc-permission-harvest` — proposes rules from the *beacon archive* (prompts that actually
  happened), through **eleven deterministic refutation gates** (`:20-24`), because nine of nine
  string-matched proposals were previously refuted with counts inflated 2×-174× and two granting
  arbitrary code execution (`:7-9`). Its own header (`:27-30`): *"WHAT IT NEVER DOES. Write
  permission config from an agent session. `--apply` is operator-run through `cc-do`; consent is
  `CONFIRM=1`; an agent-session marker in the environment is a courtesy refusal (exit 4), and the
  hard stop is the `hooks/validate-bash.sh` deny arm on this tool's `--apply` argv. **There is no
  override variable.**"*

### CONSEQUENCE, stated exactly

The permission surface is a **fixed point**. Every route from "the agent is blocked" to "the agent
is no longer blocked" passes through a write to `settings.json`, and that write is refused by the
classifier, by policy, and by convention — three arms that fail independently, so no single
mistake opens it.

This is not an accident or a gap to be closed. It is the **only** structural guarantee that an
agent's capability envelope is monotone in operator intent. If it were automatable, the sentence
"the operator decides what the agent may do" would be false, and nothing downstream of it —
including every other line in this report — would mean anything.

⚠️ **But say what it costs, not just what it buys.** The residue is not *impossible*, it is
*his by construction*. `autoMode.soft_deny` is 37 editable sentences in a file he owns. Narrowing
*"Modify Shared Resources: In-place modification of shared artifacts not created in the current
context"* — which is almost certainly the clause that ate tonight's `config/kitty.conf` edit and
its four `git commit` attempts — is a decision he could make in one edit, at a real and
unquantified risk cost. **Nobody can even propose that narrowing responsibly today, because
§1d proved the refusal reason is a constant: there is no data on which clause fires how often.**

---

## §3 THE RESTART CLASS — definitive answer

**Q: can a change to the kitty BINARY reach a running kitty, preserving live panes?**

**A: NO — definitively, for C. YES — routinely, for Python. The dividing line is not
"binary vs config"; it is "is there a scriptable injection point for THIS layer".**

### 3a. What CAN reach a running kitty (measured, tonight, on the live process)

kitty's `watcher` mechanism executes an arbitrary Python file inside the running boss process.
CONTROL RUN on `~/k482` @ `2cb1d95` (= v0.48.2, the operator's build), `kitty/launch.py:515-544`:

```python
def load_watch_modules(watchers):
    ...
    m = watcher_modules.get(path, None)
    if m is None:
        m = runpy.run_path(path, run_name='__kitty_watcher__')
        watcher_modules[path] = m
        w = m.get('on_load')
        if callable(w): w(boss, {})
```

`runpy.run_path` reads and executes the file **from disk, at call time**, and `on_load(boss, …)`
hands it the live `Boss` — i.e. every window of every tab of every OS window. Injection into an
already-running instance (`scripts/kitty-title-band-watcher.py:44-50`, READ):

```
kitty @ launch --type=overlay --watcher <file> sh -c 'sleep 0.2'
```

Two traps, both recorded: `--type=background` does **not** work (no `Window` ⇒ `load_watch_modules`
is never reached, `launch.py:520-542`); and modules are **memoised by PATH** (`launch.py:523`,
control-verified above as `watcher_modules[path]`), so re-injecting an edited file needs a **new
path**, not the same one.

**Proof it works on the real instance, run tonight** (`git show 5252bd28b`, commit body):
> `kitty-title-band-unwatcher.py` removed the shim from the live kitty — `uninstalled pid=73832
> (restored stock set_geometry, relaid out 2 tab(s))`. That uninstall relaid out EVERY tab … and
> kitty survived.

Live surgery on a running terminal, every tab relaid out, zero panes lost. RAN: `ps` confirms
pid **73832** is still the live kitty (etime 03:50:53). The repo already generalised this
(`git show 2ece07dfe`): *"'binary-only' is a property of the layer you looked at … The rule is the
question that was not asked — does the runtime expose an injection point for this change at a
scriptable layer."*

### 3b. What CANNOT — and why each candidate mechanism is dead

| candidate | verdict | evidence |
|---|---|---|
| **fd / PTY handoff to a new process** | DEAD | RAN `grep -rn 'SCM_RIGHTS\|sendmsg\|recvmsg\|CMSG'` over all `*.py`/`*.c`/`*.h` in `~/k482` excluding `3rdparty`: **one** hit, a comment in bundled `glfw/backend_utils.c:392` about Wayland. kitty implements no fd-passing protocol. A pane's PTY master fd is owned by the kitty process; no other process can acquire it. |
| **exec-in-place (`os.execv` self-restart)** | DEAD | RAN `grep -rn 'execv\|execl\|os.exec' kitty/*.py`: 7 hits, all launching an *editor* or a *kitten* (`utils.py:605,861`, `entry_points.py:11,29,42,77`, `main.py:616`). No self-re-exec exists. And it could not work if it did: `exec` preserves fds but destroys every Python object — the `Screen` buffers, scrollback and GPU state are in-process memory with no serialisation. |
| **`detach-window` / `detach-tab` to another instance** | DEAD | READ `kitty/rc/detach_window.py:22-25`: *"Detach the specified windows and either move them into a new tab, a new OS window or add them to the specified tab."* All three destinations are **within one `Boss`**, i.e. one process. There is no inter-process destination. |
| **`--single-instance` socket** | DEAD (for this purpose) | It makes a *new* invocation ask the *existing* process to open a window. The old binary keeps running everything. |
| **`kitty @ load-config`** | reaches config only | `kitty/rc/load_config.py:34` — "(Re)load the specified kitty.conf config file(s)". This is why tonight's chord re-arm needed no restart: a **keybinding is config**. |

### 3c. What actually survives a restart, and it is the thing that matters

Panes do not survive. **Sessions do**, because Claude Code persists its transcript to disk:
`claude --resume <id>` reconstructs from `$CLAUDE_CONFIG_DIR/projects/<cwd-hashed>/<id>.jsonl`
(`README.md:871`). The repo ships the whole restore path — `bin/cc-resume-resolve` (searches every
account store, recreates a reaped worktree so a stranded transcript still loads),
`bin/cc-resume-classify.py`, and `bin/cc-resume-layout.sh` (one OS window per monitor, splits
inside, `layout_action equalize` after each group, placement via Accessibility because kitty has
no move-to-display remote command — `cc-resume-layout.sh:1-45`).

So the restart cost is **not "the work is lost"**. It is one bounded, already-automated
re-hydration. Which makes the residue sharper, not softer:

🚨 **The genuinely irreducible part of the restart class is not mechanism — it is that THE ACTOR IS
INSIDE THE BLAST RADIUS.** Every agent session on this box runs in a pane of the kitty it would be
restarting. A session cannot kill its own terminal and then continue; it dies mid-command, before
it can verify or re-hydrate anything. The restart must be driven from **outside** the blast radius
— a launchd job, another terminal app, or the operator — and the only one of those three that
exists today is the operator. *(Corroborated by the shape of tonight's `kill` refusals: three
`kill <pid>` calls denied at 01:37:41, 02:10:39, 04:22:48, consistent with the standing memory
rule `auto-mode-classifier-denies-acting-on-a-live-session`.)*

**Conviction: 95%** on "no C change reaches a running kitty" (five independent mechanisms checked,
each dead for a different reason, with the source in hand). **90%** on "the Python route is
general", discounted because it is one runtime's `watcher` option and does not generalise to a
runtime that lacks one.

---

## §4 THE VALUE FORKS — which decisions are genuinely his

Tonight's chord sequence, from `git log` (RAN) — three decisions in six hours, none derivable:

| # | commit | the decision | derivable from code? |
|---|---|---|---|
| 1 | `1a22db69f` / `9476a0a9c` — *"honour the operator's disarm of cmd+shift+b"* | **DISARM** the chord after kitty SIGSEGV'd at 20:13:49 and took every pane | **No.** The crash was real; disarming the chord was one of ≥3 responses (disarm the chord · remove the shim · accept the risk). |
| 2 | `5252bd28b` — *"re-arm cmd+shift+b — the chord was the trigger, not the crash"* | **RE-ARM** it once attribution moved to the shim | **No.** Attribution is **~85%, not certainty** — "the shipped kitty binary exports 8 symbols, so `fast_data_types+840952` cannot be resolved to a source line." Re-arming is accepting a 15% chance of losing every pane again. |
| 3 | `a237abc11` — *"the title-band shim must be asked for, not merely not-refused"* | Change the shim from **opt-out to opt-in** (`KITTY_TITLE_BAND_SHIM=1`) | **No.** Both polarities are safe-ish and correct-ish; the commit's reason is a *consent* argument: *"an opt-OUT bridge is one a session can inject into a live terminal without a decision having been made, which is exactly what happened."* |

### The cleanest specimen in the whole record

RAN over `~/.claude/autonomy/backlog.jsonl` — row `a8c9092ec07b`, filed **2026-09-17T03:39:27Z**:

* the title carries the full measurement: churn fixed (`+0.93 MB/s with 21.8 MB retained → flat`;
  CPU `+6.8pp → +0.53pp`; cold press `~30 s → 0.33 s`), `kitty 73832` up 2h30m, zero crashes;
* it names the residual: *"attribution is ~85%, not certainty"*;
* it states its own class in one sentence: **"This is a risk judgement, which is why an agent may
  not make it."**
* it ships a complete `run` field — `sed -i '' 's|^# DISARMED-map cmd+shift+b|map cmd+shift+b|' … && kitty @ load-config …`
* `event:"done"` at **03:44:53**, evidence: *"operator ran the re-arm himself at 22:4x."*

**Five minutes and sixteen seconds** from filed to done, with the exact command pre-written. The
keystroke was worth nothing. The decision — *accept a 15% chance of losing every live pane again*
— was the entire content, and it is the operator's because he is the one who bears the loss.

### The separator, stated so it can be applied

> **A step needs a human DECISION iff a correct agent with perfect information could still
> defensibly choose either branch, because the branches differ in who bears an unquantified
> downside. Everything else is a KEYSTROKE, and a keystroke is a defect in the pipeline, not a
> feature of the problem.**

By that test, tonight: decisions 1-3 are genuinely his. The 4 `git commit` refusals, the 3 `kill`
refusals, the 2 `ship-land` refusals and 4,503 archived prompts at 98.2% approval are keystrokes —
and the pipeline is currently paying for them in **1,966 hours** of blocked wall-clock.

---

## §A ADVERSARIAL PASS — where the above is wrong, and it matters

I ran the hostile-reviewer question against §1 and found **three** things, one of which
partially refutes my own §1b.

### A1. 🚨 PARTIAL SELF-REFUTATION: the `git commit` refusals are probably SHAPE, not policy

§1b claimed "the classifier overrides a matching allow rule." A cheaper explanation exists and
I did not rule it out. READ `docs/research/permission-matcher-truth-2026-08-20.md:226-252`, a
read of the binary:

> **`cd` + `git` in one command** → ask, `bashMissKind:"cd-git-compound"` … **Only
> `no-rule-match` is fixable by writing a better allow pattern. Everything else is structural.**

Every one of tonight's four denied commits was `cd <worktree> && git add … && git commit …`.
That is `cd-git-compound` — refused **before any allow rule is read**. So `Bash(git commit:*)`
never got a chance, and the observation is equally consistent with "the allowlist works fine and
the command shape defeated it."

Both readings agree on the conclusion that matters (**no allow-rule edit fixes it**), but they
disagree completely on the remedy, and mine pointed at the wrong one. The correct remedy is
`git -C <worktree> add …` as a single statement.

**The honest state: UNRESOLVED.** Separating them needs one arm nobody has run — issue a bare
single-statement `git commit` in a dispatch worktree and see whether it clears. Conviction the
classifier *can* override a matching allow rule: **50%**, down from the 80% I would have written
before this pass.

### A2. The same taxonomy prices the ceiling, and I replicated the repo's number independently

RAN over all 4,503 archived prompts, classifying by CC's own structural gates:

```
multi-statement (&&, ;, newline, pipe)          3,969   88%
command substitution  $( )  or backtick         1,503   33%
starts with `cd `                               1,540   34%
contains a heredoc `<<`                           587   13%
trailing `&` (classifierApprovable:FALSE)          54
UNION structurally unallowlistable               2,065   45.9%
```

**45.9%** independently reproduces `bin/cc-permission-harvest:20-22`'s *"45% of real prompts"*,
computed from a different direction. So: **a perfect allowlist, with unlimited operator
ratification, cannot clear more than ~54% of the prompts this box actually raises** — and the
census's separate finding (36.6% hook-emitted) overlaps that remainder rather than adding to it.

### A3. 🚨 A MEASURED OWN-GOAL: our own standing instruction manufactures prompts

`Write`, `Edit` and `MultiEdit` are in `permissions.allow` **unconditionally** (RAN — they appear
as bare tool names in the 339). A Write tool call raises **zero** prompts, always.

The auto-mode standing session instruction says the opposite:

> *"make file changes with sed, heredocs, or short scripts, rather than using the dedicated Read,
> Edit, or Write tools."*

RAN: **415 of 4,503 archived prompts (9.2%) are file-writing heredocs** (`python3 - <<`,
`cat > f <<`, `tee f <<`) — a shape that is **not allowlistable at all**
(`permission-matcher-truth:252` — `K8_` refuses the sandbox fast-path on `/(?<!<)<<(?!<)/`)
routed away from a tool that is allowed unconditionally.

Nearly a tenth of the human-in-the-loop load on this box is self-inflicted by a style
instruction. That is not irreducible residue; it is a bug, and it is the cheapest fix in this
report.

---

## §5 THE HONEST CONTRACT

**The separator, restated as a test you can apply to any row:**

> **DECISION** = a correct agent with perfect information could still defensibly choose either
> branch, because the branches differ in **who bears an unquantified downside**. Never automatable.
> **KEYSTROKE** = the branch is determined; only the pressing is outstanding. Always automatable
> in principle — and every one still being pressed is a defect with an owner.

### The table

| # | step | automatic today? | if not, WHY (mechanism) | what the operator actually does |
|---|---|---|---|---|
| 1 | research · read · probe · measure | **YES** | — | nothing |
| 2 | write code in an agent-created worktree | **YES** | — | nothing |
| 3 | run gates (`bats`, `shellcheck`, typecheck) | **YES** | allow-listed, project scope | nothing |
| 4 | **edit a shared artifact the agent did not create** (`config/kitty.conf`) | **NO** | `soft_deny` *"Modify Shared Resources: in-place modification of shared artifacts not created in the current context … without clear affirmative user consent"* | **KEYSTROKE-shaped but there is no key** — 86% of refusals raise no dialog. He must read the hand-back and run it. |
| 5 | `git add`/`git commit` of that edit | **NO** today | `bashMissKind:"cd-git-compound"` — structural, pre-rule (§A1). **Likely agent-fixable**: `git -C <wt> add` as one statement | should be nothing, once §A1 is tested |
| 6 | `/ship` land to trunk | **PARTLY** | the push itself escapes (`ship-land.sh` runs `git push` as a **subprocess**, not a Bash tool call — `ship-rail-push-allow.sh:10-13`), but `bash scripts/…` is `DROP_CMDS`-dropped and a `nohup … &` form is `classifierApprovable:false` | approve a prompt (p50 12 s) or nothing |
| 7 | `deploy-live` converge | **YES, by one exact grant** | `.claude/settings.json:53-54` — two **exact-match** spellings, no `:*`; `--force`/`--bootstrap`/any other budget still prompt | nothing |
| 8 | **restart kitty for a C-layer change** | **NO — structurally** | five mechanisms dead (§3b); **and the agent is inside the blast radius** — it dies with the terminal it restarts | decide when; the re-hydration itself is automated (`cc-resume-*`) |
| 9 | ship a **Python**-layer change to a live kitty | **YES** | `kitty @ launch --type=overlay --watcher <file>` → `runpy.run_path` in-process (§3a); proven on pid 73832 tonight | nothing |
| 10 | **widen the permission surface** | **NO — and must stay so** | three independent arms (§2) | the only actor who can |
| 11 | **accept a residual risk** (re-arm a chord at 85% attribution) | **NO — never** | not a mechanism; the downside is his | the whole job (row `a8c9092ec07b`: 5 m 16 s, command pre-written) |
| 12 | define "done" / sign off a deliverable | **NO — never** | `cc-signoff` is operator-only by construction; an agent may reach `awaiting-signoff` and no further | the whole job |
| 13 | retry a `Classifier unavailable` refusal | **should be YES, is NO** | 27 of 194 refusals (13.9%) are infrastructure faults, not policy; the ledger already distinguishes them and nothing retries | currently pays a keystroke for a transient |

### The four irreducible classes, and why each is irreducible

| class | why no mechanism can remove it | size |
|---|---|---|
| **CONSENT** — modifying a shared artifact the agent did not create | The predicate is *"was this decided by a human"*, which is not a property of the artifact, the command, or the repo. No amount of code can read it off the world; it has to be supplied. | the `soft_deny` clause that dominated tonight |
| **SELF-AUTHORIZATION** — widening the envelope | Automating it makes "the operator decides what the agent may do" false. Its irreducibility is the *point*, not a limitation. | 3 independent arms, no override variable |
| **VALUE** — what "done" means, what risk is acceptable, which default polarity | Genuinely underdetermined by the code. Tonight produced three (disarm · re-arm · opt-in-not-opt-out), each defensible either way, each differing only in who eats the loss. | 3 in 6 hours |
| **PROCESS IDENTITY** — replacing the binary a live process is running | Not policy — physics. No fd handoff, no self-exec, no inter-process detach (§3b). And the actor is inside the blast radius. | 1 class, permanent |

### What "no human in the loop" can honestly mean here

Not zero. The defensible target is:

1. **Zero KEYSTROKES on the 98.2%.** Route the PROMPT population through
   `hooks/model-permission-decider.py` — which exists, emits only `allow`/`ask`, has `deny`
   structurally unreachable, fences on indirection, re-checks the operator's live `ask`/`deny`
   arrays twice, and is wired **nowhere** (RAN: `grep -c` → 0). One `c10` migration
   (`migrations/0022-mitl-decider-shadow.sh`) puts it in **SHADOW** mode, changing nothing and
   logging the verdicts it would emit. That is the single highest-value operator action in this
   report and it is reversible by construction.
2. **Fix the own-goal.** Stop routing file writes through heredocs: −9.2% of all prompts (§A3).
3. **Test §A1's one arm.** If `git -C <wt> add` clears, tonight's commit friction was style.
4. **Retry the 13.9%.** `Classifier unavailable` is not a decision.
5. **Accept 4 classes and 3 decisions per night as the floor** — and make each hand-back look like
   row `a8c9092ec07b`: full measurement, named residual, stated class, complete `run` command,
   one decision. That row was closed in **5 minutes 16 seconds**. That is what the irreducible
   residue costs when it is packaged correctly, and it is the number to optimise.

### THE ONE DECISIVE UNMEASURED FACT

Everything in target (1) rests on a claim nobody has tested: **does a PreToolUse hook's `allow`
pre-empt auto mode's `soft_deny` classifier?**

* `hooks/model-permission-decider.py:36-40` says a hook `allow` "BYPASSES the permission system
  COMPLETELY" (measured 2.1.220, one session).
* `hooks/ship-rail-push-allow.sh:31` relies on the weaker form ("a hook `allow` overrides the
  settings `ask`") and that one demonstrably works in production.
* Anthropic's published docs say hook decisions do **not** bypass permission rules.
* The repo's own memory records the stronger claim as **UNKNOWN**.

Nobody has run the arm that matters: **hook `allow` vs classifier `soft_deny`.** If `allow` wins,
the MITL decider clears the REFUSAL population too and the residue collapses to the four classes
above. If it loses, MITL clears only the PROMPT population and the 86%-no-dialog refusals stay
exactly as they are.

**That is a three-arm probe, one variable, one afternoon — and it decides whether "no human in the
loop" means 98% or 54%.** Conviction that it is worth running before any other permission work:
**93%**.
