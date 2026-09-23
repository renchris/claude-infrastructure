<!-- arm B = claude-opus-5-5 @high · brief T6-choose · settle run 1 (wf_e43f474d-ad0) · raw worker output, verbatim -->

# Stop-blocking `decision:"block"` sites in `hooks/*.sh` and `hooks/*.py` (snapshot 47c3317eb)

## 1. Qualifying sites (10)

| # | Site | Where it sits |
|---|---|---|
| 1 | `hooks/anti-deference-nudge.sh:527` | Top level. The file's only function, `open_packet_B`, ends at `:137`. Followed by `exit 0` at `:528`. |
| 2 | `hooks/boundary-handoff.sh:723` | Top level. The last function, `bh_live_waves`, ends at `:641`. The object also carries `systemMessage`. |
| 3 | `hooks/completion-assert.sh:1286` | Top level. The last function, `_ca_source_close_shape`, ends at `:630`. Followed by `exit 0` at `:1287`. |
| 4 | `hooks/handoff-claim-assert.sh:127` | Top level. Its only function is the one-line `abstain` at `:39`. |
| 5 | `hooks/dispatch-assert.sh:225` | Top level, in the pending-obligation re-check branch (the `p_count` increment is at `:220`). The last function, `discharged_since`, ends at `:205`. |
| 6 | `hooks/dispatch-assert.sh:258` | Top level. This is the first-fire path after the `narrated-not-dispatched` log (`:252-254`). |
| 7 | `hooks/session-continue.sh:893` | Inside function `wake_floor` (`:603-895`); the `jq -nc` call starts at `:892`. The function's stdout is captured by `_wf_json="$(wake_floor)"` at `:1213` and printed to hook stdout by `printf '%s' "$_wf_json"` at `:1215`. |
| 8 | `hooks/session-continue.sh:1197` | Inside function `ship_floor` (`:1098-1199`). It is captured at `:1208` and printed by `printf '%s' "$_sf_json"` at `:1210`. |
| 9 | `hooks/session-continue.sh:1332` | Top level. This is the armed-continue path, used when `_sysmsg` is set. |
| 10 | `hooks/session-continue.sh:1334` | Top level. The `else` branch of the same `if` (no `_sysmsg`). |

None of these files has a self-test function; a grep for `selftest` or `self-test` across all six files returned nothing.

**Excluded after checking:**
- Header and comment mentions are not emissions. Examples: `hooks/anti-deference-nudge.sh:44`, `hooks/boundary-handoff.sh:21`, `hooks/completion-assert.sh:89,817`, `hooks/handoff-claim-assert.sh:17`, `hooks/dispatch-assert.sh:42`, `hooks/session-continue.sh:46,1211,1326`, `hooks/subagent-stop.sh:40`, `hooks/enforce-email-formatting.py:229`.
- `hooks/goal-inert-watch.sh:113` and `hooks/operator-readout.sh:12` are comments stating that the hook never emits a block.
- The other `"decision"` keys are not `"block"`:
  - `hooks/reset-hard-shadow-allow.sh:164` and `hooks/validate-bash.sh:137` write log records with values like `would-allow`/`allow` or `deny`/`ask`.
  - `hooks/curl-gate.py:174` and `hooks/model-permission-decider.py:515` hold allow/deny/ask decisions.
- The only stdout emission in `hooks/plan-agent-teams-default.sh` (`:211`) is a PreToolUse `additionalContext` object.
- The emissions in `hooks/enforce-email-formatting.py` (`:741`, `:748-759`, `:1267-1287`, `:1294-1303`) are PreToolUse `permissionDecision` objects.

## 2. Emissions that fail test (c)

**`hooks/waiting-recycle.sh`** has **8** `decision:"block"` emissions, and every one sets `hookSpecificOutput:{hookEventName:"PostToolUse",…}`. They are at `:1112`, `:1321`, `:1352`, `:1493`, `:1498`, `:1520`, `:1552` and `:1592`. For example, `:1112` reads `'{decision:"block",reason:$s,systemMessage:$s,hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$a}}'`.

Proof that it runs on PostToolUse, not Stop:
- The header says it rides "PostToolUse:Bash, the heartbeat of a polling desk" (`hooks/waiting-recycle.sh:17`).
- It says "Claude Code calls it with NO args + the PostToolUse JSON on stdin → actuation mode" (`:151`).
- Its code section is headed `# ---- PostToolUse actuation mode` (`:633`).
- In `settings-templates/settings.example.json` it is registered under `PostToolUse` (from a `jq` walk of `.hooks`), not under `Stop`.

No other in-scope file fails (c).

## 3. File with the most qualifying sites

**`hooks/session-continue.sh`, with 4** (`:893`, `:1197`, `:1332`, `:1334`). The runner-up is `hooks/dispatch-assert.sh` with 2. At most one of the four prints per Stop: the floors are tried in order and each branch exits (`:1206-1215`), and `:1332`/`:1334` are opposite arms of one `if`.

## 4. Registration under `Stop` in `settings-templates/settings.example.json`

The template's Stop array lists `session-continue.sh`, `anti-deference-nudge.sh`, `completion-assert.sh` and `boundary-handoff.sh`, among others (from a `jq '.hooks.Stop[]?.hooks[]?.command'` read). Two files with qualifying sites are **not** registered there:

- **`hooks/dispatch-assert.sh`.** Its Stop registration lives in `docs/activation/pending-activation/11-dispatch-assert-activate.sh`:
  - `:8` describes registering it "in the Stop obj-0 chain of EVERY config dir's settings.json".
  - `:55` prints the step: append to Stop obj-0, after completion-assert.
  - The section starts at `:82` ("Stop wiring on EVERY config dir").
  - The `jq` idempotency check on `.hooks.Stop` is at `:88`, and the append into `.hooks.Stop[0].hooks` is at `:97`.
- **`hooks/handoff-claim-assert.sh`.** Its registration lives in `migrations/0027-handoff-claim-registration.sh`:
  - `:3` gives the migration step: "register hooks/handoff-claim-assert.sh as a Stop hook".
  - `:32` sets `CMD`.
  - `:44-48` appends it into the first Stop group after completion-assert (`.hooks.Stop = (…)`).
  - `:6` and `:57` verify it through `.hooks.Stop[].hooks[]`.

## 5. Stale in-code line citations near the emission code

**Adjacent to a qualifying emission:**
- `hooks/session-continue.sh:1327`, in the comment right above emissions `:1332`/`:1334`, cites "a universal top-level field, precedent at :502" for `systemMessage`. Line `:502` is actually header prose about the "(B) TERMINATING — a fresh teardown marker naming THIS session" abstain, not a `systemMessage` emission. The real `systemMessage` emissions in this file are at `:660`, `:700`, `:793`, `:840`, `:851` and `:893`.

**In `mechanical_arm` (`:938-1079`), which sits between the two emitting floors and cites their code:**
- `hooks/session-continue.sh:944` cites "ship_floor :969, wake_floor :732-736".
  - `:969` is inside `mechanical_arm` itself (`agent_team_member_confirms "$_ma_aid"; _ma_c=$?`), not in `ship_floor`, which starts at `:1098`.
  - `:732-736` is a comment about the `CC_CUSTODY_BIN` test seam, not a kill-switch release.
- `hooks/session-continue.sh:952` cites "ship_floor at :865-869, wake_floor at :587-608".
  - `:865-869` is inside `wake_floor`'s reason text ("Re-arm after every wake…" and "A /goal is LIVE here…"), not in `ship_floor`.
  - `:587-602` is `wake_floor`'s header comment, and the function only begins at `:603`, so this range points at the documentation more than at the peer-exemption code it claims.

I did not open the ship_floor and wake_floor code that these comments intended to cite, so I cannot give their correct targets. `hooks/session-continue.sh:588` cites "the session-continue.sh:33 shape"; I did not read `:33` (only `:34`, which describes the final `systemMessage`), so I have not judged that citation.

No `:NNN` comment citations appear within 25 lines before or 10 lines after the qualifying emissions in `anti-deference-nudge.sh`, `boundary-handoff.sh`, `completion-assert.sh`, `handoff-claim-assert.sh` or `dispatch-assert.sh`.