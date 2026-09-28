# T6 — Stop-blocking `decision:"block"` emissions in top-level `hooks/*.sh` and `hooks/*.py`

I read the snapshot at `/tmp/s55/repo-47c3317eb`, not the `/tmp/o55probe-…` path named in the brief. I ran out of tool-call budget before opening every emission's surrounding lines. The "where it sits" notes below say which are read and which are inferred.

**Method.** I grepped every `hooks/*.sh` and `hooks/*.py` for:
- `decision:"block"` in any quoting;
- `"block"` as a literal;
- `"decision":` keys;
- `decision:$var` and `.decision=` forms.

I then dropped comment lines, header prose, comparison strings and log writers. `hooks/lib/` and `hooks/tests/` were not searched.

## 1. Qualifying sites (10)

| Site | Where it sits |
|---|---|
| `hooks/anti-deference-nudge.sh:527` | Top level. Column-0 `jq -nc … '{decision:"block",reason:$r}'`. Inferred: the file's only function is `open_packet_B` at `:93`. |
| `hooks/boundary-handoff.sh:723` | Top level. Column-0 `'{decision:"block",reason:$r,systemMessage:$r}'`. Inferred: the file's functions are `free_win_now` at `:394` and `bh_live_waves` at `:613`. |
| `hooks/completion-assert.sh:1286` | Top level. Column-0 `'{decision:"block",reason:$r}'`. Inferred from indentation; the `_ca_*` helpers are all defined earlier. |
| `hooks/dispatch-assert.sh:225` | Indented two spaces, inside the "re-check" branch that builds `reason=` at `:224`. Not inside a named function, but I did not open `:162-225`. |
| `hooks/dispatch-assert.sh:258` | Top level, column-0, following the first-fire `reason=` at `:256`. |
| `hooks/handoff-claim-assert.sh:127` | Top level. Column-0 `'{decision:"block",reason:$r}'`. |
| `hooks/session-continue.sh:893` | Inside `wake_floor()`. I read it: the function starts at `:603`, and `:894` is `return 1` and `:895` is `}`. The object is `{decision:"block",reason:$r,systemMessage:$m}`. |
| `hooks/session-continue.sh:1197` | Inside `ship_floor()`. I read it: the function starts at `:1098`, and `:1198` is `return 1` and `:1199` is `}`. |
| `hooks/session-continue.sh:1332` | Top level, in the `if [ -n "$_sysmsg" ]` branch. I read it. It carries `systemMessage:$s`. |
| `hooks/session-continue.sh:1334` | Top level, the `else` branch of that same `if`. I read it. Same object without `systemMessage`. |

**Not sites**
- **Comments and headers.**
  - `anti-deference-nudge.sh:44`
  - `boundary-handoff.sh:21`
  - `completion-assert.sh:89`, `:817`
  - `dispatch-assert.sh:42`
  - `handoff-claim-assert.sh:17`
  - `session-continue.sh:46`, `:66`, `:316`, `:1326`
  - `goal-inert-watch.sh:113` and `operator-readout.sh:12`, which both say "NEVER `{decision:"block"}`"
  - `subagent-stop.sh:40`
- **Trailing comment.** `session-continue.sh:1211` puts `decision:block` in the comment on `exit 0`, not in a printed object.
- **Comparison, not emission.** `operator-readout.sh:290` is a jq `select(.event=="block")` filter.
- **Log writers, not `block`.**
  - `validate-bash.sh:137` and `reset-hard-shadow-allow.sh:164` write `"decision":"%s"` to a JSONL log.
  - `curl-gate.py:174` and `model-permission-decider.py:515` build log records.
  - The `.py` hooks have no literal `"block"` at all.
- **Fails test (c).** The eight `waiting-recycle.sh` emissions (see section 2).

## 2. Files that write `decision:"block"` but fail test (c)

**`hooks/waiting-recycle.sh`.** It has 8 such emissions, at lines 1112, 1321, 1352, 1493, 1498, 1520, 1552 and 1592. One example is `:1592`:

`'{decision:"block", reason:$s, systemMessage:$s, hookSpecificOutput:{hookEventName:"PostToolUse", additionalContext:$a}}'`

Every one of the eight lines sets `hookSpecificOutput:{hookEventName:"PostToolUse",…}` in the same object.

**Proof of the event it runs on**
- `hooks/waiting-recycle.sh:123-125` says delivery is "confirmed delivered on PostToolUse @ 2.1.183" and "The tool has ALREADY run at PostToolUse".
- `settings-templates/settings.example.json:212` registers `waiting-recycle.sh` inside the `PostToolUse` array, which starts at `:176`.
- `README.md:319` lists it under "PostToolUse (12)".

## 3. Most qualifying sites

`hooks/session-continue.sh` has **4** sites: `:893`, `:1197`, `:1332` and `:1334`. `dispatch-assert.sh` has 2, and the other four files have 1 each.

## 4. Stop registration in `settings-templates/settings.example.json`

The `Stop` array runs from `:445` to about `:501`, and `"SubagentStop"` starts at `:502`. I read the whole array. The Stop array contains:
- **Group 1:** `notify`, `cache-expiry-tracker`, `teammate-checkpoint`, `session-continue`, `anti-deference-nudge`, `completion-assert`, `operator-readout`, `session-beat`.
- **Group 2:** `boundary-handoff`.

| File with a qualifying site | In the template's Stop array? |
|---|---|
| `session-continue.sh` | Yes, group 1 |
| `anti-deference-nudge.sh` | Yes, group 1 |
| `completion-assert.sh` | Yes, group 1 |
| `boundary-handoff.sh` | Yes, group 2, whose `_comment` says "obj-2 — boundary-handoff" |
| **`handoff-claim-assert.sh`** | **No** |
| **`dispatch-assert.sh`** | **No** |

- **`handoff-claim-assert.sh`.** Its Stop registration lives in `migrations/0027-handoff-claim-registration.sh`. That file:
  - says at `:3` that it registers the hook "as a Stop hook";
  - has a verify line at `:6` that checks `.hooks.Stop[].hooks[]` for the command;
  - sets `CMD="~/.claude/hooks/handoff-claim-assert.sh"` at `:32`;
  - has a jq edit that appends into the first Stop group of the live `settings.json`.

  So it is registered per machine by a migration, and the template never got it.
- **`dispatch-assert.sh`.** I did not find a committed registration. The only in-repo traces are:
  - `README.md:322`, which lists it under "Stop (12)". That is prose, not code.
  - `tests/deploy-link-parity.bats:91-92`, which stages a pending activation named `11-dispatch-assert-activate.sh`. It appears only in that test fixture.

  A `find` for `*dispatch-assert*` outside `docs/` returned only `hooks/dispatch-assert.sh` and `tests/dispatch-assert.bats`. So the activation script is not in this snapshot. My repo-wide grep for the name was truncated by `head`, so I cannot rule out another registration file.

## 5. Stale in-code line citation next to emission code

**Drifted: `hooks/session-continue.sh:1327`**

- **The citing line.** The comment is directly above the `:1332` and `:1334` emissions: "systemMessage rides ALONGSIDE the block (a universal top-level field, precedent at :502)".
- **What `:502` actually holds.** Lines 501-503 sit in a comment about the (B) TERMINATING teardown marker: "handoff-fire (self-close), cc-teardown (delegated close) and teammate-auto-shutdown (TeammateIdle) all already write". It has nothing to do with `systemMessage` or `decision:block`.
- **Where the precedent really is.** The real precedent for `systemMessage` beside `decision:"block"` is the emission at `session-continue.sh:892-893`.

**Not checked.** These citations are in the emission files but I did not open the target lines, so I make no claim about them:
- `anti-deference-nudge.sh:472` ("lesson at :353")
- `completion-assert.sh:1188`
- `session-continue.sh:944-965`

`boundary-handoff.sh` and `handoff-claim-assert.sh` have no line citations near their emissions. The `dispatch-assert.sh` ones sit in the header at `:41`.

**Caveats**
- I did not grep the six emitting files for self-test wrappers. The `^name() {` scan showed no self-test function in any of them.
- "Top level" for `anti-deference-nudge.sh:527`, `boundary-handoff.sh:723`, `completion-assert.sh:1286` and `handoff-claim-assert.sh:127` is inferred from column-0 indentation. Only `session-continue.sh` and the `dispatch-assert.sh` `:224` context were read directly.
