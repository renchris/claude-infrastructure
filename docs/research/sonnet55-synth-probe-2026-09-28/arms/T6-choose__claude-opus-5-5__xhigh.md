# Stop-blocking `decision:"block"` emissions in `hooks/*.sh` / `hooks/*.py` (sha 47c3317eb)

**Method:** I searched every in-scope file for `"block"`, for the escaped form `block\"`, and for a `decision:` value set from a variable. I then opened each hit to check that it runs, writes to stdout, and what event name it declares. The two `.py` hooks only ever set `decision` to allow, deny or ask, and they write it to an audit log or a PreToolUse payload (`hooks/curl-gate.py:174`, `hooks/curl-gate.py:215-221`, `hooks/model-permission-decider.py:458-465`). Neither emits a block.

## 1. Qualifying sites (10)

| # | Site | Where it sits |
|---|---|---|
| 1 | `hooks/anti-deference-nudge.sh:527` | top level, after the `FIRE_KIND` if/elif chain (`:514-525`); `exit 0` at `:528` |
| 2 | `hooks/boundary-handoff.sh:723` | top level (`{decision:"block",reason:$r,systemMessage:$r}`); `exit 0` at `:724` |
| 3 | `hooks/completion-assert.sh:1286` | top level, after the reason is assembled (`:1274-1284`); `exit 0` at `:1287` |
| 4 | `hooks/dispatch-assert.sh:225` | top level, inside the `if [ -f "$PENDING" ]` block that re-checks an earlier obligation; `exit 0` at `:226` |
| 5 | `hooks/dispatch-assert.sh:258` | top level, the fresh-scan fire path; `exit 0` at `:259` |
| 6 | `hooks/handoff-claim-assert.sh:127` | top level, after latch and cap (`:111-119`); `exit 0` at `:128` |
| 7 | `hooks/session-continue.sh:893` | inside `wake_floor()` (`:603-895`). The jq call starts at `:892`. Its stdout is captured at `:1213` and printed at `:1215` |
| 8 | `hooks/session-continue.sh:1197` | inside `ship_floor()` (`:1098-1199`). Captured at `:1208` and printed at `:1210` |
| 9 | `hooks/session-continue.sh:1332` | top level armed path, `_sysmsg` branch (`{decision:"block",reason:$r,systemMessage:$s}`) |
| 10 | `hooks/session-continue.sh:1334` | top level armed path, `else` branch (`{decision:"block",reason:$r}`) |

**Rejected because they are only prose:** `hooks/completion-assert.sh:89`, `:817`; `hooks/dispatch-assert.sh:42`; `hooks/boundary-handoff.sh:21`; `hooks/anti-deference-nudge.sh:44`; `hooks/handoff-claim-assert.sh:17`; `hooks/session-continue.sh:46`, `:316`, `:1211`, `:1326`; `hooks/subagent-stop.sh:40`; `hooks/enforce-email-formatting.py:229`. `hooks/operator-readout.sh:12` and `hooks/goal-inert-watch.sh:113` only state that the hook never blocks. `hooks/operator-readout.sh:290` compares `"block"` inside a jq `select`; it is not an emission.

## 2. Files that fail test (c)

**`hooks/waiting-recycle.sh`** is the only one.
- **Example emission:** `hooks/waiting-recycle.sh:1112` has `'{decision:"block",…,hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$a}}'`.
- **Count:** 8 lines carry this object: `:1112`, `:1321`, `:1352`, `:1493`, `:1498`, `:1520`, `:1552`, `:1592`. I read the surrounding code only for `:1112` and `:1591-1592`. The other six are jq filter strings from the search, not comment lines. None of them falls inside the file's helper functions (the last one ends at `:1264`).
- **Event it actually runs on:** PostToolUse, not Stop.
  - In config it is registered under `"PostToolUse"` (`settings-templates/settings.example.json:176`), with `"matcher": "Bash"` at `:203` and the command at `:212`.
  - The file header agrees: "Claude Code calls it with NO args + the PostToolUse JSON on stdin → actuation mode" (`hooks/waiting-recycle.sh:151`), and the section banner reads "PostToolUse actuation mode" (`:633`).

## 3. File with the most qualifying sites

**`hooks/session-continue.sh`, with 4:** `:893`, `:1197`, `:1332`, `:1334`. `dispatch-assert.sh` has 2, and every other file has 1.

## 4. Registration under `Stop` in `settings.example.json` (`Stop` array opens at `:445`)

- **Registered:**
  - `session-continue.sh` at `:466`
  - `anti-deference-nudge.sh` at `:471`
  - `completion-assert.sh` at `:476`
  - `boundary-handoff.sh` at `:496` (still inside `Stop`; `SubagentStop` opens at `:502`)
- **Not registered:**
  - **`hooks/dispatch-assert.sh`:** its Stop wiring is in the operator-run activation script `docs/activation/pending-activation/11-dispatch-assert-activate.sh`:
    - `HOOK_CMD='~/.claude/hooks/dispatch-assert.sh'` at `:39`
    - `(.hooks.Stop[0].hooks) |= (` at `:97`
    - "wired (Stop obj-0, after completion-assert…)" at `:103`
    - `:22` notes "The agent never self-activates hooks."
  - **`hooks/handoff-claim-assert.sh`:** its Stop wiring is in `migrations/0027-handoff-claim-registration.sh`:
    - `CMD="~/.claude/hooks/handoff-claim-assert.sh"` at `:32`
    - `.hooks.Stop = ( (.hooks.Stop // [{}])` at `:47-48`
    - verify step at `:6` and `:57-58`

## 5. Line citations in comments that no longer point at their target

**Inside or next to the emission code:**
- **`hooks/session-continue.sh:1327`**, one line above sites 9 and 10, says systemMessage alongside a block has a "precedent at :502".
  - `:502` is in the middle of the "(B) TERMINATING" teardown-marker comment (`:501-504`), which has nothing to do with systemMessage.
  - The in-file case of systemMessage alongside `decision:"block"` is at `:893`.
- **`hooks/session-continue.sh:724`**, inside `wake_floor()` with site 7, says `$_opane` is "the RAW pane key captured at :197".
  - `:197` is a comment in a test-history note ("GREEN under `env -u CLAUDE_CODE_SESSION_ID`…").
  - The only assignment is `_opane="$_ouid"` at `:425`.

**Further out.** These sit in `mechanical_arm()` (`:938-1079`) but claim to point into the two functions that emit, `ship_floor()` and `wake_floor()`:
- **`:944` says "ship_floor :969".** `:969` is `mechanical_arm`'s own `agent_team_member_confirms "$_ma_aid"`. `ship_floor`'s kill-switch release is at `:1101`.
- **The same line says "wake_floor :732-736".** That range is the `CC_CUSTODY_BIN` test-seam comment. `wake_floor`'s `kill_switch_active` check is at `:850`.
- **`:952` says "ship_floor at :865-869".** Those lines are text inside `wake_floor`'s reason string (e.g. `:866`, "Re-arm after every wake…"). `ship_floor`'s check that stands down for a confirmed team assignee is at `:1103-1108`.
- **The same line says "wake_floor at :587-608".** That range is header comment (`:587-602`) plus `wake_floor`'s opening guards (`:603-607`). `wake_floor`'s assignee check is at `:778-779`.
- **`:974` says "The sibling at :974 already logs {assignee,confirm_rc}".** It points at itself. The sibling that logs those fields is `ship_floor` at `:1106`.

**One more drifted citation, outside the tight window:** `hooks/anti-deference-nudge.sh:472`, 55 lines above site 1, cites "the suppressed-record lesson at :353". `:353` is a bare `fi` that closes the team-assignee abstain block (`:351-352`).
