# Bang-command harvest: which `!` commands the agent could have run itself (2026-10-01)

**Answer.** Of the 533 `!` commands the operator has run since 2026-08-17, **17 instances (two
command shapes) were safe for an agent to run**, and they become two allow rules:
`Bash(cc-decide list:*)` and the exact `Bash(cc-do --list)`. The other 516 were handed over for a
reason that an allow rule would delete rather than satisfy: a `--confirm` gate, sudo, a credential, a
production change, a live pane or daemon, an operator queue item, a GUI view, a one-shot script, or
a compound command. A bigger allowlist would not reduce these asks much. The larger lever is
behavioral: the agents hand the operator read-only commands they could run and relay themselves
(§4).

Tool: `cc-permission-harvest --bang` (`bin/cc-permission-harvest`, section "the BANG source").
Suite: `tests/cc-permission-harvest-bang.bats`. Operator step: `CONFIRM=1 cc-permission-harvest
--bang --apply`, which re-runs the pipeline live and writes only what the fresh run reproduces.

## 1. Population

| measure | value |
|---|---|
| `!` commands, unique by record uuid | **533** in 268 of 5,146 top-level transcripts, 237 sessions |
| window | 2026-08-17T12:01Z .. 2026-10-01T05:30Z |
| stores | `~/.claude`, `-next` (a symlink to `~/.claude`), `-tertiary`, `-quaternary`, `-secondary`, `-next4` |
| handed in a `▶ Run this:` block | **474** (89%) |
| handed as inline code | 26 |
| typed unprompted | 33 |
| the agent tried it first and was denied | 5 (all by the classifier: [Create Public Surface] 2, [Security Weaken] 2, [Production Deploy] 1) |
| the agent never tried before handing | **520** (98%) |

The brief's figure of 608 overcounted. That raw count includes tool results, subagent briefs and
greps that QUOTE `<bash-input>`. A bang is a user record whose content **starts with** the marker, in
a top-level transcript. That gives 405 in the four stores the brief named, and 533 once
`~/.claude-secondary` is included.

## 2. Buckets (first match wins, in this order)

| bucket | instances | shapes | why it stays with the operator |
|---|---|---|---|
| consent_gate | 92 | 43 | `--confirm <target>`, `CONFIRM=1`, `CC_DO_ASSUME_YES`, `--yes`, `--force`: the hand-off is the design |
| privilege | 5 | 3 | sudo (`pmset`, `killall coreaudiod`) |
| credential | 43 | 28 | logins, relogins, key and secret scripts |
| production | 63 | 34 | `aws amplify start-job` (7), deploy/release/golive scripts, `git [-C <path>] push`, lands |
| live_session | 41 | 25 | `osascript`, `launchctl kickstart`, `cc-teardown`, `handoff-fire --recycle`, `kitty @ launch/load-config` |
| operator_queue | 38 | 11 | `cc-do <id>` (23+4), `cc-decide action/answer`, `cc-backlog unblock` |
| gui_view | 41 | 21 | `open …/index.html`, `cursor <doc>`: the operator wanted to look at something |
| classifier | 1 | 1 | the agent's own attempt was classifier-denied (see §3) |
| one_shot | 114 | 48 | `bash /tmp/<script>.sh` (56) and other path-named scripts: no reusable prefix exists |
| compound | 46 | 33 | `cd … && …`, `printf 'yes\n' \| …`: rules apply per leaf and structural forms never match |
| **read_only** | **24** | **9** | **the only candidate bucket** |
| unclassified | 25 | 18 | not shown read-only: `git -C … reset --keep`/`branch -f`/`merge`, `cc-lr recover`, `cc-decide show` (not a documented verb) |

Every `git -C <path>` bang in the population (12) mutated something: reset, push, `branch -f`, or
merge. None was a read, so the brief's `git -C <path> log/status` example does not occur here. A
`git -C` rule could not be path-free anyway, and PATH_BOUND refuses a path-bound one.

## 3. The classifier question, answered from the record, not by a probe

**Does a settings allow rule override an auto-mode classifier deny?** Yes, per the vendor docs and
the decompiled order. Allow rules resolve before the classifier: the docs at `/permission-modes`
("actions matching allow/ask/deny rules resolve immediately"), and the full precedence in
`docs/research/permission-matcher-truth-2026-08-20.md:392` (… → allow rules → mode auto-approvals →
auto-mode classifier → prompt). The classifier's own deny text says the same thing: "To allow this
type of action in the future, the user can add a Bash permission rule to their settings."

**The probe-verification was refused.**
- A headless A/B on 2.1.284 (`claude -p --permission-mode auto --setting-sources project`, with and
  without an exact allow rule) was planned on a harmless command the classifier denies.
- Arm A ran twice and showed that the obvious harmless candidates are not denied at all:
  - `kill -0 <live claude pid>` ran;
  - `kitten @ --to unix:/tmp/<absent>.sock close-window` ran and failed only on the absent socket.
- The next arm framed a no-match `close-window` as closing another session's pane. This session's
  own classifier refused to launch it as **[Auto-Mode Bypass]**. That denial covers the outcome, so
  no further spelling was tried.

Conviction that rules override the classifier on 2.1.284: about 85% (documented and decompiled on
2.1.220, not probed on this build).

**Consequence: the classifier bucket is never a candidate.** A rule matching a classifier-denied
shape does not clear a prompt. It switches that check off for the shape in every context, including
the one where the classifier was right. The husk-pane `kitten @ close-window` is the example. It is
refused when aimed at a live session, so it stays the operator's step (or `/tmp/husk-close-panes.sh
--confirm …`), and the fix is to make panes close themselves (husk fix F-a), not to allowlist the
close.

A second refusal happened while building this tool. `cc-permission-harvest --bang --check` against
the live fleet settings was refused once as [Modify Shared Resources], although `--check` writes
nothing and an identical call minutes earlier was allowed. The suite proves `--check` and `--apply`
against fixture settings instead.

## 4. Proposed, refused, and the behavioral finding

**Proposed (both pass all 11 §3.2 gates on a fresh run):**

| rule | kind | evidence | why it is read-only |
|---|---|---|---|
| `Bash(cc-decide list:*)` | prefix | 11 bangs · 10 sessions · 5 weeks; the agent corpus shows 226 agent runs, next token `--open` 204 / `--all` 17 | `list` prints packets; every mutating verb (`open`, `veto`, `action`, `expire-sweep`) is a different second token |
| `Bash(cc-do --list)` | exact | 6 bangs · 6 sessions · 5 weeks | prints the board; every other `cc-do` form RUNS a step, so only the exact string is allowed (exempt from FLAG_HEAD alone) |

**Refused on MIN_EVIDENCE (seen once):** `cc-custody list`, `cc-blockers`,
`claude-accounts --fresh`, `claude-accounts --fresh --readout`, `claude-accounts --route general`,
and a `printf`. Each would pass the other gates; the next harvest proposes them once they recur.

**Already allowed but handed anyway:** `gh repo view … --web` (it opens a browser, so it is a view).

**The behavioral finding.** 98% of the hand-offs were made without the agent trying first. In the
read-only bucket the agents run `cc-decide list` 226 times in the corpus, and the classifier allows
it. So the operator was handed it to *see the output*, not because the agent was blocked. These two
rules make the agent side deterministic (no classifier round trip, no "classifier gave no verdict"
transient). The ask goes away only when agents run read-only commands themselves and relay the
rendered output. The close-protocol rule already says to do that ("Rendered output … reproduce it
verbatim"). This harvest is the measurement that it is not yet the habit.

## 5. Re-derive

```
cc-permission-harvest --bang --json            # report + <out>/bang/latest.json
cc-permission-harvest --bang --check           # read-only preview of the per-file diff
bats tests/cc-permission-harvest-bang.bats     # 13 arms, 2 of them mutants
```

Fixed in passing: the apply rewrite re-serialized settings files with `ensure_ascii=False`. Every
`—` escape became a literal character, so a two-rule apply rewrote about 20 unrelated autoMode
lines in each of the five fleet files. `_rewrite_text` now keeps the file's own escaping, and a
mutant arm pins that.
