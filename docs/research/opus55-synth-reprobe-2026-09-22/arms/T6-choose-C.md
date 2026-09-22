<!-- arm C = claude-opus-5-5 @xhigh · brief T6-choose · raw worker output, verbatim -->

**Coverage note.** Grep and Glob weren't available in this session, and the brief ruled out Bash, so I opened files by name. I read these in full:
- all 9 hooks in the `Stop` array of `settings-templates/settings.example.json:445-500`
- `waiting-recycle.sh`, `relay-verbatim.sh`, `hook-chain.sh`, `subagent-stop.sh`, `mailbox-wake-arm.sh`
- `mailbox-drain.sh:1-40`

I didn't open any other `hooks/*.sh` or `hooks/*.py`. The site list is complete for every file I read. A decision emitted by some other hook that is registered on Stop only outside the template would not be in it.

## 1. Qualifying sites (7)

| Site | Where it sits | Emitted object |
|---|---|---|
| `hooks/session-continue.sh:893` | inside `wake_floor()`. The `jq` call starts at :892; the output is captured at :1213 and printed at :1215 | `{decision:"block",reason:$r,systemMessage:$m}` |
| `hooks/session-continue.sh:1197` | inside `ship_floor()`. Captured at :1208, printed at :1210 | `{decision:"block",reason:$r}` |
| `hooks/session-continue.sh:1332` | top level: the sentinel-armed continuation when inbox mail is folded in | `{decision:"block",reason:$r,systemMessage:$s}` |
| `hooks/session-continue.sh:1334` | top level: the same continuation with no mail | `{decision:"block",reason:$r}` |
| `hooks/completion-assert.sh:1286` | top level | `{decision:"block",reason:$r}` |
| `hooks/anti-deference-nudge.sh:527` | top level | `{decision:"block",reason:$r}` |
| `hooks/boundary-handoff.sh:723` | top level | `{decision:"block",reason:$r,systemMessage:$r}` |

**Not counted separately:**
- `session-continue.sh:1210` and `:1215` only print objects built at :1197 and :893.
- `session-continue.sh:1218` prints `_wf_json` only when `wake_floor` returns 0. On that path it has only produced systemMessage-only objects (:659-660, :699-700, :792-793, :840, :851).

**Checked and excluded:**
- `operator-readout.sh` only emits `{systemMessage:$m}`, at :1577, :1623 and :1663. This matches its header at :12 ("NEVER {decision:"block"}").
- `teammate-checkpoint.sh` writes no JSON. Every exit is a bare `exit 0` (:38, :105, :112, :140, :297, :347, :365, :381).
- `notify.sh`, `cache-expiry-tracker.sh` (which only writes a timestamp file at :8) and `session-beat.sh` (output sent to `/dev/null` at :127) emit nothing to stdout.
- `subagent-stop.sh` writes nothing to stdout. All its writes go to files (:63-67, :114-119), and its header at :39-42 says so.
- `mailbox-wake-arm.sh` signals with stderr and `exit 2` (:211-214). It emits no JSON.
- `hook-chain.sh` only relays member output (:239). It ranks `permissionDecision` only (:154-162) and is not wired (:24-25).
- `relay-verbatim.sh` emits `hookEventName:"PostToolUse"` with no `decision` field (:35-44).
- Comment or prose mentions only: `session-continue.sh:46`, `:316`; `boundary-handoff.sh:21`; `completion-assert.sh:89`, `:817`; `anti-deference-nudge.sh:44`; `subagent-stop.sh:40`; `waiting-recycle.sh:123`.

## 2. The file that fails test (c): `hooks/waiting-recycle.sh`

It has **8** `decision:"block"` emissions, all at top level, and every one sets `hookSpecificOutput:{hookEventName:"PostToolUse",…}`:
- :1112 (RSS-only page)
- :1321 (busy page)
- :1352 (busy pause-point nudge)
- :1493 (Stage-2 refused)
- :1498 (Stage-2 fired)
- :1520 (Stage-2 shadow)
- :1552 (wedge escalation)
- :1592 (Stage-1 advisory)

Example, `waiting-recycle.sh:1592`:
`'{decision:"block", reason:$s, systemMessage:$s, hookSpecificOutput:{hookEventName:"PostToolUse", additionalContext:$a}}'`

**Proof that it runs on PostToolUse:**
- Header :123-126: "confirmed delivered on PostToolUse … a PostToolUse hook must never cost a session".
- :151: "Claude Code calls it with NO args + the PostToolUse JSON on stdin".
- :633: `# ---- PostToolUse actuation mode`.
- `settings.example.json:203-213` registers it under `PostToolUse`, matcher `Bash`, at :212.

One contradicting line: the FATAL message at :660 says "the desk Stage-2 poll does not run this Stop". None of the files I read registers this hook on Stop.

## 3. The file with the most sites

`hooks/session-continue.sh`, with **4** (:893, :1197, :1332, :1334).

## 4. Registration under `Stop` in `settings-templates/settings.example.json`

All four files are registered, so none is missing:

| File | Template line |
|---|---|
| `session-continue.sh` | :466 |
| `anti-deference-nudge.sh` | :471 |
| `completion-assert.sh` | :476 |
| `boundary-handoff.sh` | :496, in a separate Stop object at :491-500 |

- `boundary-handoff.sh`'s header (:101-112) records that the live setup once wired it only on `~/.claude`, through a machine-absolute path. :115-125 says that wiring is now done.
- The one Stop hook I found outside the template is `mailbox-wake-arm.sh`: registered "on `Stop` (migration 0012)" per its :5. It has no qualifying site.

## 5. Line citations that have drifted

**Right next to the emission code:**
- **`session-continue.sh:1327-1328`**, just above the emission at :1332, says "(a universal top-level field, precedent at :502)".
  - Line :502 is actually the teardown-marker comment ("handoff-fire (self-close), cc-teardown (delegated close) and teammate-auto-shutdown").
  - The real in-file precedent for a systemMessage beside a block is `wake_floor` at :892-893.
- **`anti-deference-nudge.sh:472`**, in the TRIGGER code that feeds the reason at :514-525 and the emission at :527, says "the suppressed-record lesson at :353".
  - Line :353 is `  fi`, closing the assignee guard.
  - The lesson is at :458-462.
- **`session-continue.sh:724-725`**, inside `wake_floor`, says "`$_opane` is the RAW pane key captured at :197".
  - Line :197 is a comment in the `clear` CLI block about `env -u CLAUDE_CODE_SESSION_ID`.
  - The capture is at :425 (`_opane="$_ouid"`).

**In the code that decides whether these emissions fire:**
- **`session-continue.sh:944-945`** (`mechanical_arm`) says "ship_floor :969, wake_floor :732-736".
  - :969 is `agent_team_member_confirms "$_ma_aid"; _ma_c=$?` inside `mechanical_arm` itself, and :732-736 is the `CC_CUSTODY_BIN` comment.
  - The real kill-switch sites are :1101 (ship floor) and :850-853 (wake floor).
- **`session-continue.sh:952`** says "ship_floor at :865-869, wake_floor at :587-608".
  - Those ranges are wake-floor reason text and header comments.
  - The assignee exemptions are at :1103-1109 and :776-798.
- **`session-continue.sh:965`** says "(:589-594)". The logic it describes is at :778-785.
- **`session-continue.sh:974`** says "The sibling at :974 already logs". That line points at itself; the sibling is :1106.
- **`completion-assert.sh:695`** says "the LIVE-PEER-OWNED comment at :431".
  - :431 is `  local lib rc`.
  - The comment is at :503-528.
- **`completion-assert.sh:724`** says "D1 `:774`".
  - :774 is a comment in the landed-but-not-live (🚀) block about new files missing from the live layer (`LIVE_ADDS`).
  - D1 is at :926-961.
- **`completion-assert.sh:837`** says "boundary-handoff.sh:415-428".
  - Those lines are the end of `free_win_now` and the threshold `if` block.
  - The compose-guard is at `boundary-handoff.sh:437-450`.
- **`boundary-handoff.sh:403`** (inside `free_win_now`, which sets `freewin` for the :723 emission) says "`_bscd` is this hook's own resolved dir (:103)".
  - :103 is header prose about `.claude-secondary`.
  - `_bscd` is assigned at :171.

**Further from the emission code (headers), also drifted:**
- `completion-assert.sh:171` cites session-continue :971, :745, :656 and :863. The real kill-switch sites are :1228-1233, :950, :1101 and :850.
- `completion-assert.sh:177` cites session-continue :187-208. The real range is :348-395.
- `completion-assert.sh:189` cites ":157-160". The message extractor is at :243-246.
- `completion-assert.sh:378` cites session-continue :874-884 and :1009-1012. The real assignee exemptions are :967-981, :1103-1109 and :776-798.
- `boundary-handoff.sh:70` cites ":201". The line it means is :295.
- `boundary-handoff.sh:85` cites ":353". The line it means is in :502-524.

**Checked and still accurate:**
- `session-continue.sh:316-317` and `completion-assert.sh:818` cite `hook-chain.sh:78`. The sentence they quote is at `hook-chain.sh:77-78`.
- `session-continue.sh:578` cites `mailbox-drain.sh:8-10`. The text is at :9-11.
- `completion-assert.sh:663` cites ":101", which is `set -uo pipefail`.
