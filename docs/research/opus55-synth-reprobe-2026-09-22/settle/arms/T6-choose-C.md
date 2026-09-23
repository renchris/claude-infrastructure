<!-- arm C = claude-opus-5-5 @xhigh · brief T6-choose · settle run 1 (wf_e43f474d-ad0) · raw worker output, verbatim -->

# Stop-blocking `decision:"block"` emissions in `hooks/*.sh` and `hooks/*.py` at 47c3317eb

**Method.** I searched every non-comment line of `hooks/*.sh` and `hooks/*.py` for `decision…block` in any quoting style. I also searched for `"block"` values emitted without the word `decision` on the same line, and for variable-valued `decision` keys. The second and third searches found nothing more: the `.py` hooks only emit `permissionDecision` values of allow/deny/ask (`hooks/curl-gate.py:217`, `hooks/model-permission-decider.py:465`). The only `decision…block` hits in `hooks/lib/` are comments (`hooks/lib/continue-sentinel.sh:8`, `hooks/lib/session-writes.sh:158`). I then opened every candidate line and checked what surrounds it.

## 1. Qualifying sites (10 sites in 6 files)

| # | Site | Where it sits |
|---|---|---|
| 1 | `hooks/anti-deference-nudge.sh:527` | top level, the final emission after the reason is picked by `FIRE_KIND` (514-525) |
| 2 | `hooks/boundary-handoff.sh:723` | top level, final emission; the object also carries `systemMessage:$r` |
| 3 | `hooks/completion-assert.sh:1286` | top level, final emission after the reason is assembled (1274-1284) |
| 4 | `hooks/dispatch-assert.sh:225` | top level, inside the `if [ -f "$PENDING" ]` re-check block (208-227) |
| 5 | `hooks/dispatch-assert.sh:258` | top level, the fresh-scan FIRE path (249-259) |
| 6 | `hooks/handoff-claim-assert.sh:127` | top level, final emission |
| 7 | `hooks/session-continue.sh:893` | in `wake_floor()` (603-895). The `jq` starts at 892. `$(wake_floor)` captures the output at 1213 and prints it at 1215. |
| 8 | `hooks/session-continue.sh:1197` | in `ship_floor()` (1098-1199). `$(ship_floor)` captures the output at 1208 and prints it at 1210. |
| 9 | `hooks/session-continue.sh:1332` | top level, the `_sysmsg` branch (`{decision:"block",reason:$r,systemMessage:$s}`) |
| 10 | `hooks/session-continue.sh:1334` | top level, the `else` branch (`{decision:"block",reason:$r}`) |

**Lines that mention the pattern but do not qualify, because they are comments:**
- `hooks/session-continue.sh:1211`, a trailing comment on `exit 0`.
- `hooks/session-continue.sh:1326`.
- `hooks/handoff-claim-assert.sh:17`, a header line.
- `hooks/waiting-recycle.sh:123`.

**Relay lines, not listed as sites:** `hooks/session-continue.sh:1210`, `:1215` and `:1218` are `printf '%s'` calls that print captured output. The object itself is written in the functions at sites 7 and 8.

## 2. The file that fails test (c): `hooks/waiting-recycle.sh`

- **Example emission:** `hooks/waiting-recycle.sh:1112`, which reads `'{decision:"block",reason:$s,systemMessage:$s,hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$a}}'` (its `jq` starts at 1111).
- **Count:** 8 runtime emissions, at lines 1112, 1321, 1352, 1493, 1498, 1520, 1552 and 1592. All 8 set `hookEventName:"PostToolUse"`. `grep -c` reports 9 lines, but the ninth is the comment at line 123.
- **The event it actually runs on is PostToolUse:**
  - Registration: `settings-templates/settings.example.json:212` registers it under `"PostToolUse"` (line 176) with `"matcher": "Bash"` (line 203). It has no Stop registration.
  - Code: `hooks/waiting-recycle.sh:633-634` is the `# ---- PostToolUse actuation mode` section, which reads stdin at 634.
  - Header: `hooks/waiting-recycle.sh:17` says it "fires on … PostToolUse:Bash".

No other in-scope file has a `decision:"block"` object carrying `hookSpecificOutput`.

## 3. The file with the most qualifying sites

`hooks/session-continue.sh` has exactly **4** (893, 1197, 1332, 1334). `hooks/dispatch-assert.sh` is next with 2.

## 4. Registration under `Stop` in `settings-templates/settings.example.json`

The `Stop` array starts at line 445.

**Registered (4 files):**
- `session-continue.sh` at 466
- `anti-deference-nudge.sh` at 471
- `completion-assert.sh` at 476
- `boundary-handoff.sh` at 496

**Not registered (2 files).** A search of every `*.json` file in the repository found no registration of either hook. Their Stop wiring exists only as staged shell edits:

- **`hooks/handoff-claim-assert.sh`**
  - Registration lives in `migrations/0027-handoff-claim-registration.sh`: `CMD` is set at :32, and the `jq` at :46-52 appends `{type:"command",command:$c,timeout:10}` to `.hooks.Stop[0].hooks` (:47-50). It is verified at :57.
  - The file is `migration-class: c10` (:2), meaning the operator runs it.
  - Drift: the comment at :44 says "after completion-assert.sh where present", but :50 always appends to the end of group 0.
- **`hooks/dispatch-assert.sh`**
  - Registration lives in `docs/activation/pending-activation/11-dispatch-assert-activate.sh`: `HOOK_CMD` is set at :39, and step 2 at :82-103 inserts it into `.hooks.Stop[0].hooks` after completion-assert (:96-101).
  - It is staged for the operator to run, not self-activated (:21-22).

## 5. Stale in-code line citations in or next to the emission code

| Citing line | What it claims | What is actually there |
|---|---|---|
| `hooks/session-continue.sh:1327`, next to sites 9 and 10 | `systemMessage` beside a block has a "precedent at :502" | `hooks/session-continue.sh:502` is a comment in the "(B) TERMINATING" teardown-marker block (501-504). The real in-file precedent is `wake_floor`'s `{decision:"block",reason:$r,systemMessage:$m}` at 892-893. |
| `hooks/session-continue.sh:724`, inside `wake_floor()` with site 7 | `$_opane` is "captured at :197" | `hooks/session-continue.sh:197` is a comment about a `tests/completion-assert.bats` A/B. The capture is `_opane="$_ouid"` at `hooks/session-continue.sh:425`, whose comment block at 421-424 describes it. |
| `hooks/session-continue.sh:643-644`, inside `wake_floor()` | `cc-pane-headless:124` mints `hdl-<16hex>` and `:197` exports it | `bin/cc-pane-headless:124` is `--name) name="${2:-}"; shift 2 ;;` and `:197` is a bare `fi`. The mint is at `bin/cc-pane-headless:145` and the export at `:218`. |
| `hooks/anti-deference-nudge.sh:481`, in the latch-set block before site 1 (527) | the `-mtime +7` GC "mirrors memory-nudge.sh:26" | `hooks/memory-nudge.sh:26` is a comment about the append-time budget. The GC it means is at `hooks/memory-nudge.sh:60-61`, and that one uses `-mtime +1`, not `+7`. |

**One citation checked that still holds:** `hooks/handoff-claim-assert.sh:15` cites `anti-deference-nudge.sh:30`. That sentence starts at `hooks/anti-deference-nudge.sh:30`, and the quoted phrase "a nagging hook trains the model to route around it" is on :31. This is a header line, not code next to an emission.