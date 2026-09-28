# Stop-blocking `decision:"block"` sites in `hooks/*.sh` and `hooks/*.py`

I read the emission lines and their surrounding code. I did not check every line-number pointer in every comment block. The one drifted citation I found is in item 5.

## 1. Qualifying sites (10)

Each site is a `jq -nc … '{decision:"block",…}'` call that writes to stdout. I found them by grepping `hooks/*.sh` and `hooks/*.py` for `decision` next to `block` and reading the hits. `hooks/*.py` has no emitter of this shape.

| Site | Where it sits |
|---|---|
| `hooks/anti-deference-nudge.sh:527` | Top level, final emission. The `open_packet_B()` function starts at `:93`, well before this line. |
| `hooks/boundary-handoff.sh:723` | Top level. The last function definitions I saw are at `:394` and `:613`; the emission is after them. |
| `hooks/dispatch-assert.sh:225` | Top level. It is the re-check branch, and `exit 0` follows. The last function defined earlier is `discharged_since()` at `:162`. |
| `hooks/dispatch-assert.sh:258` | Top level. It is the first-fire "narrated-not-dispatched" branch, followed by `exit 0`. |
| `hooks/handoff-claim-assert.sh:127` | Top level. The only function in the file is `abstain()` at `:39`. |
| `hooks/session-continue.sh:893` | Inside `wake_floor()`, which starts at `:603`. The comment at `:603` says it echoes JSON on stdout when it wants to block. It is followed by `return 1`. |
| `hooks/session-continue.sh:1197` | Inside `ship_floor()`, which starts at `:1098`. It is followed by `return 1`. |
| `hooks/session-continue.sh:1332` | Top level. This is the `systemMessage` branch of the final `if`. |
| `hooks/session-continue.sh:1334` | Top level. This is the `else` branch of the same `if`. It is a separate emission and counts separately. |
| `hooks/completion-assert.sh:1286` | Top level, final emission. |

Excluded because they fail test (a):
- Comments and header lines that mention `decision:"block"`: `anti-deference-nudge.sh:44`, `boundary-handoff.sh:21`, `dispatch-assert.sh:42`, `handoff-claim-assert.sh:17`, `completion-assert.sh:89`, `session-continue.sh:46` and `:1211`.
- Comments that say a hook never blocks: `goal-inert-watch.sh:113`, `operator-readout.sh:12`, `subagent-stop.sh:40`.
- `session-continue.sh:660`, `:700`, `:793`, `:840`, `:851` and `:1264` print only `{systemMessage:…}`, with no `decision` field.

## 2. Files that write `decision:"block"` but fail test (c)

The file is `hooks/waiting-recycle.sh`. It has 8 such emissions: `:1112`, `:1321`, `:1352`, `:1493`, `:1498`, `:1520`, `:1552` and `:1592`.

- Example: `hooks/waiting-recycle.sh:1112` prints `{decision:"block",…,hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$a}}`.
- The event it actually runs on:
  - The header says it "fires on … PostToolUse:Bash" (`hooks/waiting-recycle.sh:17`).
  - `:123` describes its delivery as `{decision:"block"}` plus `hookSpecificOutput.additionalContext`, delivered on PostToolUse.
  - `:443` and `:828` say it "rides PostToolUse:Bash".
  - `settings-templates/settings.example.json:212` registers it inside the `"PostToolUse"` array that opens at `:176`.

## 3. File with the most qualifying sites

`hooks/session-continue.sh` has the most, with 4: `:893`, `:1197`, `:1332` and `:1334`. `hooks/dispatch-assert.sh` is next with 2, and the other four files have 1 each.

## 4. Stop registration per file

The `Stop` array in `settings-templates/settings.example.json` runs from `:445` to about `:501`.

| File | In the template's `Stop` array? |
|---|---|
| `session-continue.sh` | Yes, `:466` |
| `anti-deference-nudge.sh` | Yes, `:471` |
| `completion-assert.sh` | Yes, `:476` |
| `boundary-handoff.sh` | Yes, `:496` |
| `dispatch-assert.sh` | **No.** |
| `handoff-claim-assert.sh` | **No.** |

The template's Stop entries at `:445-:501` do not include either file, so I am reading its Stop array from the commands listed there.

- **`dispatch-assert.sh`** is registered by a staged activation script, `docs/activation/pending-activation/11-dispatch-assert-activate.sh`.
  - Step 2 there is "register it in the Stop obj-0 chain of EVERY config dir's settings.json" (`:8`), and `:55` says "append $HOOK_CMD to Stop obj-0 (timeout 10, after completion-assert)".
  - Step 2 mutates the live `settings.json`, so the operator has to run the script (`:21`). I found no evidence in the repository that it has been run.
- **`handoff-claim-assert.sh`** is registered by `migrations/0027-handoff-claim-registration.sh`.
  - Its step registers the hook as a Stop hook (`:3`).
  - Its verify command checks `.hooks.Stop[].hooks[]?` for the command (`:6`).
  - It uses `CMD="~/.claude/hooks/handoff-claim-assert.sh"` (`:32`) and skips if the command is already registered (`:36`).

## 5. Drifted in-code line citation

`hooks/session-continue.sh:1327` says systemMessage rides alongside the block ("a universal top-level field, precedent at :502"). That comment sits right above the emissions at `:1332` and `:1334`.

- Line `:502` is not a precedent. It is a comment inside the wake-floor teardown-marker discussion: "(B) TERMINATING — a fresh teardown marker naming THIS session…" (`hooks/session-continue.sh:502`).
- The real `systemMessage` emissions are at `:660`, `:700`, `:793`, `:840`, `:851` and `:893`.
- The closest to a real precedent is `:893`, which is itself a `decision:"block"` with `systemMessage`.
