I'm wrapping up. I've checked every candidate line, the Stop registrations, and the `:502` pointer.

## 1. Qualifying sites (10)

All are `jq -nc … '{decision:"block",…}'` calls with no `hookSpecificOutput`, so they pass test (c).

| Site | Where it sits |
|---|---|
| `hooks/anti-deference-nudge.sh:527` | top level (its only function, `open_packet_B`, closes at `:137`) |
| `hooks/boundary-handoff.sh:723` | top level (last function closes at `:641`) |
| `hooks/completion-assert.sh:1286` | top level (last function closes at `:630`) |
| `hooks/dispatch-assert.sh:225` | top level, inside an `if` block (the re-check path, followed by `exit 0`); the last function closes at `:205` |
| `hooks/dispatch-assert.sh:258` | top level (first-fire path, followed by `exit 0`) |
| `hooks/handoff-claim-assert.sh:127` | top level (followed by `exit 0`) |
| `hooks/session-continue.sh:893` | inside `wake_floor()` (`:603-895`); the `jq` starts on `:892` and the object is on `:893` |
| `hooks/session-continue.sh:1197` | inside `ship_floor()` (`:1098-1199`) |
| `hooks/session-continue.sh:1332` | top level, the `systemMessage` branch of the final `if` |
| `hooks/session-continue.sh:1334` | top level, the `else` branch of the same `if` |

Two boundary calls on what I excluded:
- **Comments:** `decision:"block"` also appears in comments and headers, for example `hooks/session-continue.sh:46`, `hooks/completion-assert.sh:89`, `hooks/goal-inert-watch.sh:113` and `hooks/operator-readout.sh:12`. These fail test (a).
- **Other files:** `hooks/reset-hard-shadow-allow.sh` and `hooks/validate-bash.sh` write `decision` fields, but the values are `allow`, `would-allow` or a variable, not `block`.

## 2. Files that fail test (c)

**`hooks/waiting-recycle.sh` has 8 emissions that fail (c).** All 8 have `hookSpecificOutput:{hookEventName:"PostToolUse",…}`. They are at `:1112`, `:1321`, `:1352`, `:1493`, `:1498`, `:1520`, `:1552` and `:1592`.

One example, `hooks/waiting-recycle.sh:1592`:

`'{decision:"block", reason:$s, systemMessage:$s, hookSpecificOutput:{hookEventName:"PostToolUse", additionalContext:$a}}'`

Proof of the event it runs on:
- The header says the hook delivers "`{decision:"block"}` + hookSpecificOutput.additionalContext … confirmed delivered on PostToolUse" and that "The tool has ALREADY run at PostToolUse" (`hooks/waiting-recycle.sh:123-125`).
- It is registered under the `PostToolUse` array, not `Stop`: the array starts at `settings-templates/settings.example.json:176` and the command is at `:212`.

No other in-scope file has a `decision:"block"` emission that fails (c).

## 3. Most qualifying sites

**`hooks/session-continue.sh` has 4** (`:893`, `:1197`, `:1332`, `:1334`). `hooks/dispatch-assert.sh` has 2. The other four files have 1 each.

## 4. Stop registration

Registered under `Stop` in `settings-templates/settings.example.json`:
- `session-continue.sh` (`:466`)
- `anti-deference-nudge.sh` (`:471`)
- `completion-assert.sh` (`:476`)
- `boundary-handoff.sh` (`:496`, in the second Stop group)

**Not registered there:**
- **`hooks/dispatch-assert.sh`:** the template has no entry for it. Its Stop registration is staged in `docs/activation/pending-activation/11-dispatch-assert-activate.sh`. The script appends the hook to "the Stop obj-0 chain of EVERY config dir's settings.json" (`:8`, `:55`, wiring at `:82-92`). It is a staged, operator-run step (`:21-22`), so nothing in the snapshot shows it applied.
- **`hooks/handoff-claim-assert.sh`:** the template has no entry for it. Its registration lives in `migrations/0027-handoff-claim-registration.sh`, which sets `CMD="~/.claude/hooks/handoff-claim-assert.sh"` (`:32`) and appends it to the first Stop group after `completion-assert.sh` (`:44-52`). The migration's verify line checks `.hooks.Stop[]` (`:6`).

## 5. Drifted in-code citation

**`hooks/session-continue.sh:1327`** says `systemMessage` is "a universal top-level field, precedent at :502". Line 502 is not a `systemMessage` emission. It is comment text about the "(B) TERMINATING" teardown marker: `(handoff-fire (self-close), cc-teardown (delegated close) and teammate-auto-shutdown` (`hooks/session-continue.sh:500-504`).

The actual `systemMessage` emissions in that file are at `:660`, `:700`, `:793`, `:840`, `:851`, `:893` and `:1264`. The closest precedent for `systemMessage` alongside a block is `:893`, inside `wake_floor()`. I inferred that from the file; the comment doesn't say which line it meant.

I checked the comment lines around the other qualifying emissions for `:NNN` pointers and found no others adjacent to them. The `completion-assert.sh:113-123` pointer at `hooks/boundary-handoff.sh:135` and `hooks/completion-assert.sh:110` is not adjacent to an emission, and I did not verify it.
