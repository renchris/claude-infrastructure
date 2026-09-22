<!-- arm A = claude-sonnet-5 @max · brief T6-choose · raw worker output, verbatim -->

## Enumeration of Stop-blocking `decision:"block"` sites — `hooks/*.sh` + `hooks/*.py` (top level only)

Method: full-text scan of all 94 files matching `hooks/*.sh`/`hooks/*.py` for every occurrence of `decision` and of `"block"` (both `"decision":"block"` and jq's unquoted-key `decision:"block"` forms), cross-referenced against every `hookEventName`/`PostToolUse` occurrence in the same file set, then each candidate line was opened in context to classify comment-vs-code, resolve its enclosing function (if any), and trace whether its `jq` output reaches the hook's real stdout directly or via a captured/forwarded variable.

### 1. Exhaustive list of qualifying sites

| # | Site | Where it sits |
|---|------|----------------|
| 1 | `hooks/anti-deference-nudge.sh:527` | Top level — final FIRE block (`jq -nc --arg r "$reason" '{decision:"block",reason:$r}'`), reached after the `if [ "$FIRE_KIND" = … ]` reason-selection chain (hooks/anti-deference-nudge.sh:513-525) |
| 2 | `hooks/boundary-handoff.sh:723` | Top level — final FIRE block (`jq -nc --arg r "$reason" '{decision:"block",reason:$r,systemMessage:$r}'`), after the size/freewin/tok `why=`/`reason=` chain (hooks/boundary-handoff.sh:643-667) and the live-waves/conv-age appends (hooks/boundary-handoff.sh:711-720) |
| 3 | `hooks/completion-assert.sh:1286` | Top level — final FIRE block (`jq -nc --arg r "$reason" '{decision:"block",reason:$r}'`), after the `d1`..`d7` reason-accumulation chain (hooks/completion-assert.sh:1272-1285) |
| 4 | `hooks/dispatch-assert.sh:225` | Top level, inside `if [ -f "$PENDING" ]; then … fi` (the pending-obligation re-check branch), immediately after `log_idl fired "undischarged-obligation" …` (hooks/dispatch-assert.sh:222-224) |
| 5 | `hooks/dispatch-assert.sh:258` | Top level — the "fresh scan" FIRE branch, after the `NAME_TELL` match and the session-total-cap check (hooks/dispatch-assert.sh:246-257) |
| 6 | `hooks/handoff-claim-assert.sh:127` | Top level — final FIRE block, after the `VERDICTS` loop (hooks/handoff-claim-assert.sh:93-99) and the one-shot-latch/hard-cap bookkeeping (hooks/handoff-claim-assert.sh:108-116) |
| 7 | `hooks/session-continue.sh:893` | Inside function `wake_floor()` (defined `hooks/session-continue.sh:603`) — see caveat below |
| 8 | `hooks/session-continue.sh:1197` | Inside function `ship_floor()` (defined `hooks/session-continue.sh:1098`) — see caveat below |
| 9 | `hooks/session-continue.sh:1332` | Top level — the "armed path" mail-delivery branch, `if [ -n "$_sysmsg" ]; then` arm, right after `mark_blocked continue` (hooks/session-continue.sh:1329) |
| 10 | `hooks/session-continue.sh:1334` | Top level — same branch, the `else` arm (no pending-mail systemMessage) |

**Caveat on #7 and #8 (load-bearing, not decorative).** `wake_floor()` and `ship_floor()` each have exactly **one** call site, and both are command-substitution captures, not bare calls:
- `hooks/session-continue.sh:1208`: `if ! _sf_json="$(ship_floor)"; then` — `ship_floor()`'s internal `jq` at line 1197 therefore writes into a pipe captured by `_sf_json`, not directly to the hook's real stdout. The actual stdout write is `printf '%s' "$_sf_json"` at `hooks/session-continue.sh:1210`.
- `hooks/session-continue.sh:1213`: `if ! _wf_json="$(wake_floor)"; then` — same pattern; `wake_floor()`'s `jq` at line 893 is captured into `_wf_json` and forwarded by `printf '%s' "$_wf_json"` at `hooks/session-continue.sh:1215` (and again, for the rc-0-but-non-empty case, at `hooks/session-continue.sh:1217`).

Both are included above because the literal `decision:"block"` object is constructed at those lines and is confirmed (by tracing the sole call site) to reach real stdout unmodified. Under a stricter reading of criterion (a) — "the line" must itself write to the hook's real stdout — lines 893 and 1197 would be excluded (the forwarding `printf` lines would be the qualifying sites instead, but those lines don't themselves spell `"decision":"block"` in source). I'm flagging this rather than silently picking a side because it changes the answer to Q3.

By contrast, `mechanical_arm()` (`hooks/session-continue.sh:938`, called bare at `hooks/session-continue.sh:1207`: `if ! mechanical_arm; then`) is **not** captured, but its body (938-1097) contains no `decision:"block"` emission — sites #9/#10 sit in top-level code reached only when `mechanical_arm` returns true (sentinel already armed), well past its closing brace.

---

### 2. In-scope file(s) whose `decision:"block"` fails test (c)

**`hooks/waiting-recycle.sh`** — every `decision:"block"` emission in this file also sets `hookSpecificOutput.hookEventName` to `"PostToolUse"` in the same object, e.g.:

```
hooks/waiting-recycle.sh:1112:      '{decision:"block",reason:$s,systemMessage:$s,hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$a}}'
```

**8 such emissions**, at `hooks/waiting-recycle.sh:1112, 1321, 1352, 1493, 1498, 1520, 1552, 1592` — all identical in shape (`decision:"block"` + `hookSpecificOutput:{hookEventName:"PostToolUse",…}` in one object).

Proof of the hook event it actually runs on: each emission line is self-proving (the `hookEventName:"PostToolUse"` literal sits in the very same object), and the file's own header states it independently at `hooks/waiting-recycle.sh:151`: `# Claude Code calls it with NO args + the PostToolUse JSON on stdin → actuation mode.` (also `hooks/waiting-recycle.sh:125`: `# The tool has ALREADY run at PostToolUse, so a fire can NEVER break the recycle machinery it triggers`). Consistent with its registration — `settings-templates/settings.example.json:212` registers `~/.claude/hooks/waiting-recycle.sh` outside the `Stop` array entirely.

No other in-scope file emits a top-level `decision:"block"` object that also declares `PostToolUse` — the other four files with a variable-driven `"decision"` key (`hooks/reset-hard-shadow-allow.sh:164`, `hooks/curl-gate.py:174`, `hooks/model-permission-decider.py:515`, `hooks/validate-bash.sh:137`) fail criterion (a) outright (each writes to a **log file**, not stdout — see §5-adjacent findings below) and (b) (their `decision` variables are constrained to `allow`/`would-allow`/`ask`/`deny`, never `block`), so they're excluded from both Q1 and Q2.

---

### 3. File with the most qualifying sites

**`hooks/session-continue.sh` — 4 sites** (893, 1197, 1332, 1334) — the most of any in-scope file, ahead of `hooks/dispatch-assert.sh`'s 2.

Caveat carried forward from §1: if the strict "direct real-stdout write" reading is applied to exclude sites #7/#8 (893, 1197) for their capture-and-forward indirection, `session-continue.sh` drops to **2** direct sites (1332, 1334) — tying `hooks/dispatch-assert.sh` at 2. Under either reading `session-continue.sh` is at least tied for most; under the inclusive reading (which I use as primary) it wins outright at 4.

---

### 4. Stop-array registration in `settings-templates/settings.example.json`

The file's `Stop` array (`settings-templates/settings.example.json:445-500`) contains exactly two hook groups: obj-1 (`notify.sh complete`, `cache-expiry-tracker.sh`, `teammate-checkpoint.sh`, `session-continue.sh`, `anti-deference-nudge.sh`, `completion-assert.sh`, `operator-readout.sh`, `session-beat.sh stop`) and obj-2 (`boundary-handoff.sh`).

| File | Registered in `Stop`? | If not, where its registration actually lives |
|---|---|---|
| `anti-deference-nudge.sh` | ✅ yes (`settings-templates/settings.example.json:471`) | — |
| `boundary-handoff.sh` | ✅ yes (`settings-templates/settings.example.json:496`, obj-2) | — |
| `completion-assert.sh` | ✅ yes (`settings-templates/settings.example.json:476`) | — |
| `session-continue.sh` | ✅ yes (`settings-templates/settings.example.json:466`) | — |
| **`dispatch-assert.sh`** | ❌ no | `docs/activation/pending-activation/11-dispatch-assert-activate.sh` — a staged, operator-run (`CONFIRM=1 bash …`) C10 activation script. It (a) symlinks the hook into the live `~/.claude/hooks/` layer and (b) `jq`-inserts `~/.claude/hooks/dispatch-assert.sh` into `.hooks.Stop[0].hooks` of every live `settings.json` under `~/.claude*` — but only when explicitly run; its own header states "WHY C10 (agent stages; operator runs): step 2 mutates live settings.json and activates a BLOCKING Stop hook. The agent never self-activates hooks." (`docs/activation/pending-activation/11-dispatch-assert-activate.sh:21-22`). It is not present in this repo's committed `settings-templates/settings.example.json` at all. |
| **`handoff-claim-assert.sh`** | ❌ no | `migrations/0027-handoff-claim-registration.sh` — a `migration-class: c10` script (`migrations/0027-handoff-claim-registration.sh:2`) that `jq`-appends `{type:"command",command:"~/.claude/hooks/handoff-claim-assert.sh",timeout:10}` directly onto the **live** `${CC_CLAUDE_DIR:-$HOME/.claude}/settings.json`'s `.hooks.Stop[0].hooks` (`migrations/0027-handoff-claim-registration.sh:30-52`) when run. Same C10 gating as above; not present in `settings-templates/settings.example.json`. |

---

### 5. Drifted in-code `:NNN` line citations near the qualifying emissions

All verified by opening the cited line and comparing it against the claim in the citing comment.

1. **`hooks/session-continue.sh:1327`** (5 lines above qualifying sites #9/#10 at 1332/1334) reads: `# ALONGSIDE the block (a universal top-level field, precedent at :502)` — claiming `session-continue.sh:502` is a prior precedent for `systemMessage` as a universal top-level field. Actual content at `hooks/session-continue.sh:502`: `#      handoff-fire (self-close), cc-teardown (delegated close) and teammate-auto-shutdown` — part of an unrelated "(A)/(B)" discussion of teardown-marker detection strategies. No mention of `systemMessage` anywhere near it. **Drifted.**

2. **`hooks/session-continue.sh:944`** (inside `mechanical_arm()`, which sits directly between `wake_floor()` — containing site #7 — and `ship_floor()` — containing site #8) reads: `# release (ship_floor :969, wake_floor :732-736) and this one did not, so a kill-switch turn on a` — claiming these two ranges are where the sibling floors log their kill-switch release.
   - `hooks/session-continue.sh:969` is `    agent_team_member_confirms "$_ma_aid"; _ma_c=$?` — this line is inside **`mechanical_arm()` itself** (938-1097), not `ship_floor()` (which starts at 1098), and is part of the peer-exemption check, unrelated to any kill-switch logging. **Drifted** (wrong function entirely).
   - `hooks/session-continue.sh:732-736` sits inside `wake_floor()`, but reads `# CC_CUSTODY_BIN is a TEST SEAM, and it is first for the same reason every other oracle in this / # repo has one … the probe below resolves the REAL binary out / # of the checkout …` — about resolving the `cc-custody` binary path, nothing to do with kill-switch release. **Drifted.**

3. **`hooks/session-continue.sh:952`** (same `mechanical_arm()` comment block) reads: `# Both sibling floors stand down for a peer: ship_floor at :865-869, wake_floor at :587-608.` — claiming these ranges hold the "peer exemption" stand-down logic.
   - `hooks/session-continue.sh:865-869` is inside `wake_floor()`, but is literally the idle-watcher `reason=` prose text (`"Re-arm after every wake: …"`, `"A /goal is LIVE here, …"`) — advisory copy shown to the model, not peer-exemption code. **Drifted.**
   - `hooks/session-continue.sh:587-608` is at least topically closer (587-602 is `wake_floor`'s own preamble, discussing "NEVER after an operator kill-switch phrase," and 603-607 is the function's opening), so this half is plausible rather than clearly wrong — noted but not counted as a confirmed drift.

4. **`hooks/dispatch-assert.sh:41`** (the file's own `SAFETY` header, directly above the `FIRE PREDICATE`/`OBLIGATION STATE` sections that lead into qualifying sites #4/#5) reads: `# ── SAFETY (house pattern: completion-assert.sh:22-26) ── F fail-safe: block ONLY via / #   {decision:"block"}; EVERY path exits 0; any read/jq failure → abstain; no `set -e``. This cites `completion-assert.sh:22-26` as the source of that fail-safe pattern. Actual content at `hooks/completion-assert.sh:22-26`: `#   Because the matcher is broad but GATED on ground-truth facts, a TRUE-complete close (clean ∧ / #      landed-by-content ∧ no remainder) abstains no matter how confidently it says "done". / #   ATTRIBUTION runs before the dirty/unlanded terms convict: …` — this is the fire-predicate/attribution discussion, not the fail-safe pattern. The line that actually matches the paraphrase almost verbatim is `hooks/completion-assert.sh:89-91`: `#   F fail-safe: block ONLY via {decision:"block"}; EVERY path exits 0; / #   any read/jq/ledger failure → abstain. No `set -e` (a Stop hook exiting 2 false-blocks).` **Drifted — off by ~65 lines, wrong section of the same file.**
