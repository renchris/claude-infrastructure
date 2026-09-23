<!-- arm A = claude-sonnet-5 @max · brief T6-choose · settle run 1 (wf_e43f474d-ad0) · raw worker output, verbatim -->

## Stop-blocking `decision:"block"` emissions in `hooks/*.sh` / `hooks/*.py`

Scope: top-level `hooks/*.sh` + `hooks/*.py` only (`hooks/lib/`, `hooks/tests/` excluded). Repo pinned at `47c3317eb`.

### 1. Exhaustive list of qualifying sites (10)

| path:line | location |
|---|---|
| `hooks/completion-assert.sh:1286` | top level |
| `hooks/boundary-handoff.sh:723` | top level |
| `hooks/anti-deference-nudge.sh:527` | top level |
| `hooks/dispatch-assert.sh:225` | top level (inside the `if [ -f "$PENDING" ]` pending-obligation re-check block, hooks/dispatch-assert.sh:206-227) |
| `hooks/dispatch-assert.sh:258` | top level (the fresh-scan FIRE block, after the `NAME_TELL` match) |
| `hooks/handoff-claim-assert.sh:127` | top level |
| `hooks/session-continue.sh:893` | inside function `wake_floor()` (defined hooks/session-continue.sh:603, closes :936) |
| `hooks/session-continue.sh:1197` | inside function `ship_floor()` (defined hooks/session-continue.sh:1098, closes :1199) |
| `hooks/session-continue.sh:1332` | top level |
| `hooks/session-continue.sh:1334` | top level |

Each is a `jq -nc … '{decision:"block",reason:$r[,systemMessage:…]}'` invocation (jq's stdout is the hook's stdout), on the live execution path (verified no enclosing `self-test`/fixture function exists in any of these 6 files — `grep -l 'selftest\|self_test\|self-test'` over all six returned nothing), immediately followed in every case by `exit 0` / `return 1` that ends the hook run. No other construction of a top-level `"decision":"block"` object exists anywhere in the 92 in-scope files — confirmed by cross-checking every `"decision"`/`decision:`/`decision=` occurrence in scope (hooks/curl-gate.py:174 and hooks/model-permission-decider.py:515 both build a `decision` field but only inside dicts written to an on-disk **log file**, not stdout — curl-gate.py:191-192 `AUDIT_LOG.open("a",...)`, model-permission-decider.py:477 `open(STATE_DIR / f"decisions-...jsonl","a")` — and neither's actual stdout payload uses a top-level `decision` key, only `hookSpecificOutput.permissionDecision`; hooks/validate-bash.sh:137 and hooks/reset-hard-shadow-allow.sh:164 are likewise log-file `printf`s, not stdout, per hooks/validate-bash.sh:140 `>> "$_f"` and hooks/reset-hard-shadow-allow.sh:167 `>> "$LOG_FILE"`).

### 2. File failing test (c)

**`hooks/waiting-recycle.sh`** — 8 runtime emissions of `{decision:"block",...}` that also set `hookSpecificOutput.hookEventName:"PostToolUse"` in the same object, at lines `1112, 1321, 1352, 1493, 1498, 1520, 1552, 1592`. Example (hooks/waiting-recycle.sh:1112):
```
'{decision:"block",reason:$s,systemMessage:$s,hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$a}}'
```
Proof of which hook event it actually runs on: the file's own header, **hooks/waiting-recycle.sh:17** — "This hook is the IN-SESSION carrier for exactly that case: it fires on the desk's MONITORING CADENCE — **PostToolUse:Bash**, the heartbeat of a polling desk" (corroborated at hooks/waiting-recycle.sh:443 and :828: "rides PostToolUse:Bash ... under an explicit fork budget"). By contrast the sibling it explicitly distinguishes itself from, `boundary-handoff.sh`, is named at hooks/waiting-recycle.sh:12 as firing "on the **Stop** event" — i.e. waiting-recycle.sh is deliberately *not* a Stop hook, so none of its `decision:"block"` sites are Stop-blocking hook decisions at all, consistent with rule (c) excluding them.

### 3. File with the most qualifying sites

**`hooks/session-continue.sh` — 4 sites** (lines 893, 1197, 1332, 1334). Next-highest is `hooks/dispatch-assert.sh` with 2; all other qualifying files carry exactly 1.

### 4. Stop-array registration in `settings-templates/settings.example.json`

The `"Stop"` array (settings-templates/settings.example.json:445-497) contains exactly: `notify.sh`, `cache-expiry-tracker.sh`, `teammate-checkpoint.sh`, `session-continue.sh`, `anti-deference-nudge.sh`, `completion-assert.sh`, `operator-readout.sh`, `session-beat.sh stop` (obj-1), plus `boundary-handoff.sh` (obj-2).

| Qualifying file | Registered under `Stop`? |
|---|---|
| completion-assert.sh | ✓ (settings-templates/settings.example.json:471) |
| boundary-handoff.sh | ✓ (settings-templates/settings.example.json:490) |
| anti-deference-nudge.sh | ✓ (settings-templates/settings.example.json:466) |
| session-continue.sh | ✓ (settings-templates/settings.example.json:461) |
| **dispatch-assert.sh** | **✗ NOT registered** |
| **handoff-claim-assert.sh** | **✗ NOT registered** |

Where their real Stop registration lives instead:
- **`dispatch-assert.sh`** — `docs/activation/pending-activation/11-dispatch-assert-activate.sh`, a staged/unapplied C10 activation script whose step 2 (lines ~65-90) appends `~/.claude/hooks/dispatch-assert.sh` to `.hooks.Stop[0].hooks` of every config dir's *live* `settings.json`, immediately after `completion-assert`, via `jq`. It is explicitly not yet applied (`Mark done: touch …/11-dispatch-assert-activate.sh.done`).
- **`handoff-claim-assert.sh`** — `migrations/0027-handoff-claim-registration.sh`, a `migration-class: c10` script (its own header: "it edits settings.json, which is C10") whose body (`migrations/0027-handoff-claim-registration.sh:36-42`) appends `~/.claude/hooks/handoff-claim-assert.sh` to `.hooks.Stop[0].hooks` of the live `settings.json`, after `completion-assert.sh`.

Neither change is reflected in the checked-in `settings-templates/settings.example.json` template.

### 5. Stale in-code line citations near qualifying emissions

**`hooks/session-continue.sh:1327`** (comment sitting directly above, and covering, the qualifying emissions at `:1332`/`:1334`):
```
# ALONGSIDE the block (a universal top-level field, precedent at :502) so the human sees the delivery the
```
This claims line `:502` is the precedent for `systemMessage` riding alongside `decision:"block"`. But **hooks/session-continue.sh:502** actually reads:
```
# transition this hook was preventing, so its teardown marker is written AFTER an idle that never
```
— part of the unrelated `wake_floor()` discussion of asymmetric fail-safe teardown direction (hooks/session-continue.sh:495-509: "(B) TERMINATING", "FAIL-SAFE DIRECTION IS ASYMMETRIC…"). Nothing at or near line 502 mentions `systemMessage` or `decision:"block"`. The citation is stale.

**`hooks/anti-deference-nudge.sh:472`** (same file as qualifying site `:527`, part of the same unbroken top-level FIRE flow):
```
# instead. A TRIGGER of "" would make the fired row unreadable, and the suppressed-record
# lesson at :353 applies with equal force here.
```
claims a "suppressed-record lesson" sits at `:353`. But **hooks/anti-deference-nudge.sh:353** actually reads:
```
# ── (P0-4b) Genuine carve-out, SPLIT so ship/land is CONDITIONAL, not blanket (G-P11-2 / I-3:
```
— the section header for the HARD_CORE/SOFTCALL genuine-carve-out logic (hooks/anti-deference-nudge.sh:353-360), unrelated to any "suppressed-record" concept. This citation is also stale.