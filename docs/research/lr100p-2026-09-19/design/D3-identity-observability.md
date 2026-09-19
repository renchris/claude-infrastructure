# D3 — Identity + Observability first: the design for "screenshot → one command → recycled in place, verified, never a husk"

Designer: D3-identity-observability · 2026-09-19 · built on research units U01–U14 (all under `scratchpad/lr/research/`) and re-verified against the live tree at `/Users/chrisren/Development/claude-infrastructure` (paths below are repo-relative unless absolute). Every line number below was re-read this session; a claim marked **GUESS** is one I could not measure without writing or firing.

---

## 0. The thesis, in four sentences

1. **Identification is a key problem, not a speed problem.** The registry (`~/.claude/cc-registry/<pane>.json`, one JSON per live pane, all four accounts in one dir — `hooks/session-register.sh:282-288`) already maps pane → sid → account → cwd → pid in ~2 ms (U14 §3.1); what the screenshot lacks is a key that appears in that file. The statusline has both keys in hand at zero cost — `PAY_SID` is already parsed at `statusline.sh:77-86`, `KITTY_WINDOW_ID` is inherited env — and rendering `⌗117 cb227486` left-anchored costs **+1.2 ms/render** (U07 §3c). That single change makes a screenshot an O(1) lookup and removes the 4-way ambiguity U14 §3.2 measured.
2. **Recovery is a state machine that today has no state.** Today's chain writes its verdicts into five stores that do not join (U04 §3: `handoffs.jsonl` intents with no outcome row, `results.tsv`, a `$TMPDIR` watcher log wiped at boot, the IDL, the pane's own scrollback), and the branch that fired 4 of 4 times writes to none of them (`scripts/handoff-fire.sh:6878-6880`). The design's spine is ONE state record per recovery run, written by ONE function, with a budget per state and a named owner for every breach.
3. **The four failure sinks of 2026-09-19 are each one file:line.** Launcher env (`scripts/limit-recover/lr-handoff.sh:586-593` exports two variables and no `CC_ADMIT_*`) · the 2-attempts-vs-3-budget arithmetic (`handoff-fire.sh:6811-6816` vs `scripts/lib/capacity-admit.sh:581`) · the 600 s non-charging probe that can never release (`lr-fleet.sh:282-291`) · the ranker's unrecorded pick (`lr-fleet.sh:301`). Each is fixed in place; none needs a new subsystem.
4. **The invoking session must never wait.** 38.8 of 68.9 tool-minutes today were the lead watching a file, and every one of those polls exited 1–5 s after a `task-notification` that would have woken it anyway (U11 §2). The driver returns a run id in <1 s and the run's terminal state arrives as a `cc-notify` message.

---

## 1. Ground truth this design stands on (do not re-derive)

| fact | measured | unit |
|---|---|---|
| Identify from screenshot is structurally ambiguous: panes 122/124 render byte-identical lines; `account+cwdbase+sha+effort` collides 3/16; `cwd basename` collides 6/16 (now 10 in the registry) | U07 §4, U14 §3.2 | U07 U14 |
| Registry read 2 ms (pane) / 12 ms (sid8) / 177 ms (full join with telemetry) vs `lr-fleet --locate` 40–86 s (99.8 % fork overhead; single-pass python does the same in 0.148 s) | U14 §0, U07 §6b | U14 U07 |
| Detection already happens: `StopFailure` fires sub-second, `hooks/stop-failure-marker.sh` wrote all five sids to `~/.claude/autonomy/stop-failure/rate_limit__next4.jsonl` starting 11:58:33, 3 min before the first `/limit-recover`; the record carries `quotaLimits.resetsAt` (epoch) and `rateLimitType` | U10 §1c-1d | U10 |
| `Stop` does NOT fire on a limit death (5/5), so `cc-beats` keeps `kind:"prompt"` and every beat-based sensor reads a limited pane as BUSY | U10 §1a, U05 §4 | U10 U05 |
| The 4 PARTIALs are arithmetic: watcher = 2 launcher attempts in 90 s; `CC_ADMIT_BUDGET=3` releases on the 4th evaluation (`n > budget`); the one success inherited a counter at 2 from two days earlier | U01 §5.3, U02 §0, U03 §1, U04 §0, U05 §3.4 | all |
| `CC_ADMIT_LOAD_TERM=off` in the driver's shell cannot reach the pane: the relaunch is typed text into the pane's own zsh (`handoff-fire.sh:10143` carries no `${PREFIX}`), and the launcher exports only two vars | U02 §2b, U04 §2 | U02 U04 |
| Pre-launch pipeline (audit+bundle+transplant+launcher) ≈ 3 s; transplant 0.45 s on 6 MB; the 2.5 min per `--one` is entirely fixed watcher waits; irreducible floor ≈ 21 s (CC teardown ~3 s, boot ~4 s, one model round-trip ~14 s) | U02 §1, U14 §2.2 | U02 U14 |
| Ingest delivered by the expect layer 0/5 today; `resume_engaged` was satisfied by a queued `task-notification` turn (pane 112) — "RECOVERED" did not mean "ingested" | U03 §0, U11 §0 | U03 U11 |
| `cc-pane send` is hardcoded to iTerm2 AppleScript (dead on kitty); `it2 session send CR` typed the letters `C`,`R`; `kitty @ send-key ctrl+u` encodes CSI-u under the kitty keyboard protocol CC pushes; `send-text` + `\x15`/`\r` is the sanctioned wire; `send-text` rc is always 0 | U08 §3 | U08 |
| The poller (`lr-reset-poller.sh`) has no cross-account arm; `:896` gates every action behind the reset; `:902-905` retires a parked record on lock+transcript alone, i.e. writes a husk off as recovered | U06 §1, §3; U02 §2c | U06 U02 |
| Ranker: fable lane's top two were within one working session's worth of the concurrency term (12.5 %); `next` at 2 pp of weekly hit 100 % 1 h 54 m after being named; `--rank`'s reasons go to stderr and are discarded at `lr-fleet.sh:301` | U13 §1-2 | U13 |
| Operator screenshots queued 13.5 / 38.1 / 35.2 min behind the lead's own foreground polls; 24.4 min of polls bought zero information | U11 §2 | U11 |
| `~/.claude/statusline.sh` is a copy-deployed real file, not a symlink — a landed change needs `install.sh` / `deploy-live` | U07 §1 | U07 |

---

## 2. Design invariants (each is a rule a reviewer can refuse a diff on)

- **I1 — One key in the pixels.** Every rendered statusline carries the pane id and sid8, left-anchored so a 30-column pane still shows them. Identification never falls back to a group key (account, cwd, sha) without printing the candidates and refusing.
- **I2 — One record per run, one writer.** Every recovery has exactly one durable state document under `~/.reso/limit-recover/recoveries/` (never `/tmp` — this box wipes it at boot, commit `e2d8c9816`), written only through `lr_state_set` (lr-lib.sh). A component that knows a verdict writes it; nothing infers a verdict from another component's silence.
- **I3 — Every state has a budget and an owner.** A state older than its budget becomes a NAMED alarm class (`lr-stalled-<state>`) plus one automatic repair, then a page to the requester. There is no state whose breach is silent.
- **I4 — The transplant is the irreversible step, so nothing irreversible precedes an admission the launcher will honour.** The driver's probe and the pane's launcher evaluate the same term set; the probe's admit is carried into the launcher as a one-shot token (U05 P2).
- **I5 — The driver never blocks the invoker.** `cc-lr recover` returns in <1 s with a run id; verdicts arrive by `cc-notify` (mailbox), never by polling.
- **I6 — Verification is transcript-first.** "Submitted" = a `type:"user"` record carrying the run token in the TARGET transcript; "engaged" = a non-error assistant record AFTER that user record. Screen reads only decide whether to press Enter, never whether it worked (U08 §4.3).
- **I7 — Truthful labels.** `DUPLICATE` means two live processes after overlap subtraction; `RECOVERED` means engaged-in-target; `HUSK` is a first-class disposition with an owner and a next command. No label may describe a strictly better state than the disk shows.
- **I8 — Never keystrokes into a live composer for a MESSAGE.** Messages go through `cc-notify` (its own header rule). Keystrokes are only for `/exit`, the shell relaunch line, and the one ingest prompt into a freshly booted, empty composer — each with the emptiness pre-gate (U08 §5).

---

## 3. The spine: the recovery state machine

### 3.1 States

```
located ─► targeted ─► transplanted ─► exited ─► relaunched ─► alive ─► submitted ─► engaged ─► resumed
   │           │            │            │           │            │          │           │
   └ failed:*  └ parked:    └ (irrev.)   └ exit-     └ refused:   └ failed:  └ failed:   └ stalled:
     no-key       no-target                 deferred     capacity     no-proc    submit      engaged
                                            (composer)   (term)       (husk)
```

| state | meaning | evidence stored |
|---|---|---|
| `located` | (sid, pane, source cfg, cwd, tier, death uuid, reset epoch) resolved from the registry + transcript tail | registry row copy, `lr_last_api_error` tuple |
| `targeted` | target account chosen | ranker stdout + stderr verbatim, `--assign` receipt |
| `transplanted` | lock + copy + sha + tombstone done (`lr-transplant.sh`) | `transplant.json` path, sha256 |
| `exited` | pane at a positively-confirmed shell after `/exit` | watcher's `pane_cc_state == shell` line + elapsed |
| `exit-deferred` | composer held a draft; `/exit` NOT typed | composer snapshot (first 200 chars) — a named wait, not a failure |
| `relaunched` | launcher line echo-verified and CR'd into the shell | `it2_type_verified` rc 0, the exact command |
| `refused:capacity` | launcher ran, `cc_capacity_admit` said 9 | the IDL row (`term`, `detail`, refusal n/budget) — written by `lr-fire-resume` itself |
| `alive` | a `claude` pid on the pane's tty | pid + lstart |
| `submitted` | the ingest/continue prompt is a `type:"user"` record in the TARGET transcript carrying the run token | record uuid + ts |
| `engaged` | a non-error, content-bearing assistant record newer than `submitted` | record uuid + ts + first 80 chars |
| `resumed` | terminal success; registry row shows target account + live pid; `cc-notify` delivered to requester | registry row copy, notify receipt |
| `failed:<step>:<cause>` | terminal failure with a cause the watchdog could name | cause + the `next` command |
| `stalled:<state>` | budget breached, repair attempted | breach ts, repair action, repair result |
| `parked:no-target` | ranker excluded every account (reasons recorded) | reasons verbatim |

### 3.2 Store layout (all durable, all under `${LR_STATE_DIR:-$HOME/.reso/limit-recover}`)

```
recoveries/
  <sid>/<run-id>.json          the run document (one JSON object; atomic tmp+mv on every write)
  by-pane/<pane> -> ../<sid>/<run-id>.json     the in-flight run for a pane (symlink; one run per pane; removed at terminal)
  ledger.jsonl                 append-only, one line per transition: {ts,run,sid,pane,state,evidence,next,writer}
requests/<sid>.json            (existing) — the hook's request (C3) or the driver's enqueue
results/<sid>.{json,log}       (existing) — the poller's drain receipt
locks/<sid>.lock               (existing, unchanged) — the split-brain lock
tokens/<sid>.token             (new, C4) — the one-shot admission token
```

Run document (fields fixed; extra fields are legal, missing ones are not):

```json
{"run":"lr-20260919T175207Z-cb227486","sid":"cb227486-…","sid8":"cb227486","pane":"117",
 "source":{"acct":"next4","cfg":"/Users/chrisren/.claude-quaternary","cwd":"/Users/chrisren/Development/claude-infrastructure","tier":"claude-fable-5-1/xhigh","death_uuid":"…","reset_at_epoch":1789846800,"rate_limit_type":"five_hour"},
 "target":{"acct":"next2","cfg":"/Users/chrisren/.claude-secondary","rank_out":"…","rank_err":"…","assigned":true},
 "requested_by":{"pane":"127","sid":"11569d45-…","kind":"operator|hook|poller"},
 "bundle":"…/bundle-20260919T175254Z","launcher":"/var/folders/…/lr-launch-cb227486-XXXX.sh",
 "token":"…/tokens/cb227486-….token","watcher_log":"…","watcher_pid":48158,"watchdog_pid":48160,
 "state":"engaged","states":[{"state":"located","ts":"…","evidence":"…","next":"…"}, …],
 "budgets":{"located":3,"targeted":3,"transplanted":10,"exited":30,"relaunched":10,"alive":15,"submitted":45,"engaged":90,"run":300},
 "verdict":null}
```

### 3.3 The one writer — `lr_state_set` (new, `scripts/limit-recover/lr-lib.sh`, ~40 lines)

```
lr_state_set <run-doc> <state> <evidence> [<next-command>]
```

- Reads the doc, appends to `states[]`, sets `state`, writes tmp+`mv -f`, appends one line to `ledger.jsonl` with `writer=$0:$$`.
- Idempotent on the same state (a second `alive` write is recorded as a heartbeat, not a transition).
- Never exits non-zero into its caller (`|| true` at every call site; a state write must never take down the thing it describes).
- `lr_state_get <run-doc> [.field]` and `lr_state_age_s <run-doc>` are its two readers; the watchdog uses only these.

### 3.4 Who writes which state (the process that KNOWS writes)

| writer | states |
|---|---|
| `cc-lr recover` (driver, foreground, <1 s) | `located`, then detaches |
| `lr-fleet.sh --one` (detached) | `targeted`, `transplanted`, `parked:no-target`, `failed:transplant:*` |
| `handoff-fire.sh __recycle` watcher | `exited`, `exit-deferred`, `relaunched`, `alive`, `failed:relaunch:*` (with the cause read from the run doc, not the screen) |
| the generated launcher → `lr-fire-resume.sh` | `refused:capacity` (with the IDL row), `submitted`, `failed:submit:*` |
| `resume_engaged` (called by the watcher) | `engaged` |
| watcher on success | `resumed` + the `cc-notify` |
| `lr-watchdog` (detached per run) and the poller backstop | `stalled:*`, `repaired:*`, `failed:*:watchdog-gave-up` |

---

## 4. Components

### C1 — Identity by construction: statusline, telemetry row, kitty user_vars

**Files:** `statusline.sh` (repo root; deployed copy `~/.claude/statusline.sh` — copy, not symlink, U07 §1), `tests/statusline-identity.bats` (layer 2), `hooks/session-register.sh`.

**Change 1 — the render (7 lines, +1.2 ms, +14 cols; prototype at `scratchpad/lr/sl-id.sh`).** After `GLYPH_PREFIX` is composed (`statusline.sh:430`) and before the emit at `:486`:

```bash
_pane="${KITTY_WINDOW_ID:-}"; [ -n "$_pane" ] || { _pane="${ITERM_SESSION_ID:-}"; _pane="${_pane##*:}"; }
ID_SEG=""
[ -n "$_pane" ] || [ -n "$PAY_SID" ] && ID_SEG="${NEXT_NUM}⌗${_pane:-?} ${PAY_SID:0:8}${RESET} "
echo -e "${GLYPH_PREFIX}${ID_SEG}${PCT_SEG}${OUTPUT}${RESET}"
```

Rendered: `(3) ⌗117 cb227486 45% · claude-infrastructure (b80f9408e) · xhigh`. At 30 columns: `(3) ⌗117 cb227486 45% · claud` — both keys survive (U07 §2b). `⌗` (U+2317) is outside the East-Asian-Ambiguous set `statusline.sh:365-397` documents kitty downsampling; **pin at the operator's eyes in a real 30-col pane before landing** (four glyph designs were reverted before — `tests/statusline-identity.bats:25-30`); ASCII `#` is the zero-risk fallback. Reading `ITERM_SESSION_ID` for its VALUE is fine; using it as a terminal claim is the banned move (`statusline.sh:412-418`).

**Change 2 — the telemetry row (0 forks; same `jq` at `statusline.sh:149-156`).** Add `pane: $pane`, `session_name: .session_name`, `model_name: .model.display_name`, `rate_limits: .rate_limits` (via `--arg pane "$_pane"`). This makes `/tmp/cc-telemetry/<sid>.json` the live-state half of the identity join (U07 §6a) and lets `cc-lr find --keyword` match the conversation title without opening a transcript. **GUESS to falsify first:** that `session_name` and `rate_limits` are present in the live payload on a Max subscription (U07 §7) — one render with the new `jq` answers it; the fields are `// null` so an absence costs nothing.

**Change 3 — `statusLine.refreshInterval: 5`** in settings (operator c10, since `~/.claude/settings.json` is agent-forbidden): a halted pane renders zero times today, so its telemetry row froze 52 min stale while alive (U07 §4). With a refresh, the frozen row is at most 5 s old — and `rate_limits.five_hour.used_percentage` becomes visible on the pane BEFORE it hits the wall.

**Change 4 — kitty user_vars (belt; registry-independent).** `kitty @ set-user-vars` exists on this kitty (`kitty @ --help` lists it). In `hooks/session-register.sh` after the row write (`:282-288`), when `KITTY_LISTEN_ON` is set: `kitty @ --to "$KITTY_LISTEN_ON" set-user-vars --match "id:$pane" cc_sid="${sid:0:8}" cc_acct="$acct" >/dev/null 2>&1 || true`, bounded by `timeout 3`. `user_vars` is `{}` on all 16 windows today (U07 §5); this makes `kitty @ ls` a second sid→pane index that survives a stale registry. No tty write (memory `foreign-tty-write-is-sized-in-syscalls`).

**Tests:** `tests/statusline-identity.bats` layer 2 gains two field assertions (pane id renders; sid8 renders; each red when its source var is unset — the suite's own history says seven single-line mutants left it green, so each new case must be mutation-checked). `tests/session-registry.bats` gains one case: the `set-user-vars` call is made with the pane id and is bounded.

### C2 — `bin/cc-lr`: the one command (resolver · driver · status)

New file, bash, ~350 lines, sourcing `lr-lib.sh`. Static, repeatable verbs; every verb prints one line per row, machine-readable with `--json`.

```
cc-lr find  <pane|⌗pane|sid8|--keyword K|--tuple acct=N,cwd=B,effort=E,pct=P>   → ONE row or REFUSE
cc-lr find  --limited                                                            → every currently limit-blocked live session (no census)
cc-lr recover <pane|sid8> [--target A] [--dry-run]                               → run id in <1 s; detaches
cc-lr recover --all [--target A]                                                 → N concurrent runs, one line each
cc-lr status [run|pane|sid8|--all|--last]                                        → the state table
cc-lr repair <run>                                                               → run the named `next` command for a stalled/failed run (what the watchdog does, by hand)
cc-lr census --deep                                                              → the full-store scan (U14's single-pass python, 0.15 s), for the case the fast index misses
```

**`find` — resolution rules (U07 §6c), in order:**
1. pane id → `cat $REG/<pane>.json` (2 ms). sid8 → `grep -l` over registry (12 ms). Exact, single hit.
2. keyword → registry ⋈ telemetry (`session_name`) ⋈ `kitty @ ls` `.title` (bounded 3 s, treat timeout as INDETERMINATE not empty — `kitty @ ls` timed out at 10.06 s with a truncated payload 1 of 4 times, U07 §5).
3. tuple → filter on (account ordinal, cwd basename, effort); NEVER on sha (it moves under the session — measured `b80f9408e → 0194d9cb1` in 25 min, U07 §2a) and never exactly on pct; rank by `|pct − live pct|`; **REFUSE and print all candidates with pane + title when the top two are within 12 points** (p90 drift at 40 min, U07 §4).
4. Liveness: `kill -0 <pid>` per candidate (authoritative; telemetry age is not). A registry row whose pid is dead is printed as `STALE` and never chosen (26 rows vs 16 live panes today, U14 §3.2).
5. Output row: `PANE SID8 ACCT CWD PID ALIVE TIER STATE TITLE` where `STATE` ∈ {`working`,`idle`,`limited(<type>, resets <hh:mm>)`,`recovering(<run> <state>)`,`recovered→<acct>`,`husk`} — `limited` from the transcript tail (`lr_last_api_error`, `lr-lib.sh:129-159`, 128 KB tail, ~10 ms) and the stop-failure marker; `recovering/recovered/husk` from `recoveries/by-pane/<pane>`.

**`find --limited`** = the cheap fleet locate: union of (a) sids in `~/.claude/autonomy/stop-failure/rate_limit__*.jsonl` newer than 6 h, (b) `parked/*.json`, (c) `requests/*.json`, each joined to a live registry row and confirmed by `lr_last_api_error` on that transcript's tail. ~0.5 s for the whole fleet vs 40–86 s for `--locate`. `--deep` remains for the case a session never registered.

**`recover <key>` — the driver (foreground part, <1 s):**
1. `find` → exactly one row, else exit 2 with the candidates (never guess; that is how the wrong pane gets recycled).
2. Refuse if `by-pane/<pane>` exists and its run is not terminal (one recovery per pane); print that run's status instead.
3. Mint `run=lr-<utc>-<sid8>`, write `located` with evidence, record `requested_by` = this pane (`KITTY_WINDOW_ID`) and this sid (`CLAUDE_CODE_SESSION_ID`).
4. `detach` (the `start_new_session` idiom, `handoff-fire.sh:1608-1616`) two processes: `lr-fleet.sh --one <sid> --source-pane <pane> --run <run> --no-await [--target A]` and `lr-watchdog --run <run>`.
5. Print ONE line and exit 0:
   `lr <run> · pane 117 cb227486 · next4 → (ranking) · detached · status: cc-lr status <run> · you will be notified here when it ends`

**`recover --all`:** `find --limited` → one `recover` per row, all detached at once (no shared resource but the per-sid lock and the account store; the `--assign` phantom in C10 spreads targets). The census→N-concurrent change turns 5 × 150 s into ≈ max(single) (U14 §2.3).

**`status`:** renders `RUN · PANE · SID8 · ACCT→ · STATE · AGE · BUDGET · NEXT` from the run docs; `--last` prints the most recent run's full transition list with per-state durations — this is the block the invoking session relays verbatim in its close.

### C3 — Detection → request, at the instant (U10 §2, adopted whole)

**File:** `hooks/stop-failure-marker.sh` — ARM 2 appended after the marker append at `:130`, ~35 lines, guarded by `CC_SF_REQUEST=on|off` (default **on**; every path exits 0 and prints nothing on stdout — the file's own fail-open contract, `:31-33`). Registered already on `StopFailure` in all five config dirs (five real files, U10 §1c), so no settings edit.

- Only for `error ∈ {rate_limit, rate_limit_error}`; a `server_error` has the byte-identical envelope and a transplant is the wrong cure (U10 §3d).
- Latch on `<sid>.<death_uuid>` (`set -C`), never on sid: `e442434c` fired 3× in 16 s and again 28 min later; a new death uuid in the same session is a NEW cap and gets a new request (LR-i, `limit-reset-safety-gate.sh:65`).
- Skip if `locks/<sid>.lock` or `<sid>.HANDOFF.json` exists (already moved).
- Skip assignees: `agent_assignee_argv` (`hooks/lib/agent-identity.sh:33`) or `agentName` in the transcript head → `teammate-skip/<sid>`.
- Write `requests/<sid>.json` with `{sid, target:"auto", source_pane:$KITTY_WINDOW_ID, requested_by:"stop-failure-marker", ts, account, cwd, tier (lr_tier_from_transcript, 79 ms), transcript_path, reset_at_epoch, rate_limit_type, death_uuid, origin_class (oi_origin_class, hooks/lib/origin-identity.sh:237)}` — the existing consumer at `lr-reset-poller.sh:648-661` reads only four keys and ignores the rest (forward-compatible).
- **Also write the `located` state** (`lr_state_set` with `requested_by.kind=hook`) so `cc-lr find` shows `limited · request written` the moment the operator looks.
- Extend `lr_last_api_error` (`lr-lib.sh:129-159`) to also emit `quotaLimits.resetsAt` and `rateLimitType` — two lines in one SSOT; `lr-audit.py:82`'s prose regex becomes the fallback, not the source.
- Wake the driver: `[ "${CC_SF_REQUEST_KICK:-0}" = 1 ] && launchctl kickstart -k gui/$(id -u)/com.reso.lr-reset-poller` (a kick of a loaded job; kept behind the flag until the operator rules), and file the plist `WatchPaths` on `requests/` as the operator's `c10` step (the repo already ships `WatchPaths` in `launchd/com.claude.browse-mirror.plist`; `scripts/launchd-parity-lint.sh` asserts live == SSOT).

**Policy tier (stated, not hidden):** with the flag off, the request is a breadcrumb the operator's `cc-lr recover` finds; with it on and `LR_POLLER_AUTORECOVER=1` in the plist env, the poller drains the request within seconds and the operator's screenshot finds a session already `engaged`. Ship the first; the 5-session drill (§8) run twice clean is the evidence for flipping the second.

**Tests:** `tests/stop-failure-marker.bats` (15 cases today) gains SF-a…SF-h from U10 §2g, each red-proofed against the unpatched hook.

### C4 — The launcher env block and the gate (U05 P1 + P2 + P3, U04 A)

**File:** `scripts/limit-recover/lr-handoff.sh:586-593` — the heredoc is the ONLY channel that survives into the pane's fresh process tree (U04 §2). It becomes:

```bash
cat > "$LAUNCHER" <<EOF
#!/bin/bash
# Resume the handed-off session $(printf '%q' "$SID") on account $(printf '%q' "$TARGET") with the ingest prompt.
# Regenerable: bundle at $(printf '%q' "$BUNDLE")   ·   run: $(printf '%q' "$LR_RUN")
export CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH="\${CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH:-1}"
${SRC_TASK_LIST:+export CLAUDE_CODE_TASK_LIST_ID=$(printf '%q' "$SRC_TASK_LIST")}
export LR_RUN=$(printf '%q' "$LR_RUN") LR_STATE_DIR=$(printf '%q' "$STATE")
export CC_ADMIT_LOAD_TERM="\${CC_ADMIT_LOAD_TERM:-off}"    # the retracted term (capacity-admit.sh:149-160); off on the Agent tool since Wave D
export CC_ADMIT_NET_ZERO=1                                 # a recycle replaces a session: never charge the replacement as +1 (capacity-admit.sh:832)
export CC_ADMIT_BUDGET="\${CC_ADMIT_BUDGET:-1}"             # the release must land INSIDE the watcher's window (was 3 vs 2 attempts)
export CC_ADMIT_BUDGET_KEY=$(printf '%q' "$SID")           # per-recovery counter, never per-caller-per-box (the one success today ran on an inherited count)
${ADMIT_TOKEN:+export CC_ADMIT_TOKEN=$(printf '%q' "$ADMIT_TOKEN")}
exec $(printf '%q ' "${FIRE_ARGV[@]}")
EOF
```

**`scripts/lib/capacity-admit.sh` changes (three, each with a red-proof test in `tests/capacity-admit.bats`, whose harness already pins overrides and `CC_ADMIT_RESERVE_TERM=off`, `:26-72`):**
- `_cc_admit_state_file` (`:509-514`) keys `<caller>[.<CC_ADMIT_BUDGET_KEY>]`, so one recovery's release cannot reset another's counter (U05 P3).
- `CC_ADMIT_NET_ZERO=1` makes the active-term delta 0 instead of +1 at `:832` (U05 §5.5(i); written as an `if/else` assignment, not the inline `&&/||`).
- The admission token: `cc_capacity_token_mint <path> <sid>` (called by `lr-fleet.sh` only on a probe ADMIT) and `_cc_admit_token_redeem` (one-shot, TTL 180 s, uid-checked, sid-named, probes never redeem) with `basis:"token"` as an eighth basis value — verbatim from U05 P2, including tests 15/15b/15c. **Why 180 s:** the measured probe→launcher gap is 11–16 s (U05 §3.3); the whole `/exit`→shell→type path is bounded at 30+10 s by §5; 180 s leaves 4× slack and is shorter than any load regime change that matters.

**`scripts/limit-recover/lr-fleet.sh:286`:** the probe runs with the SAME term switches (`CC_ADMIT_LOAD_TERM="${CC_ADMIT_LOAD_TERM:-off}" CC_ADMIT_NET_ZERO=1 cc_capacity_probe lr-fleet "$1"`), mints the token on ADMIT, and passes `--admit-token` to `lr-handoff`. Ratchet test T3 (U05 §6): the two files enable identical term sets. `LR_FLEET_CAP_WAIT_S` 600 → **60** and `LR_FLEET_CAP_IVL_S` 20 → **5**: with the load term off, what remains (headroom 4 GB, segments 50 %, active ≤ 8, reserve) is a genuinely hot box, and a 60 s park is the point at which the watchdog's repair loop (C8) takes over on a 30 s cadence up to the 5-minute run ceiling — the driver no longer sits in anyone's foreground.

**`scripts/limit-recover/lr-fire-resume.sh:324-329`:** unchanged gate, but on refusal it now writes `refused:capacity` to the run doc with the IDL row (`cc_capacity_admit_reason`) BEFORE `exit 9`, and on admit writes `admitted` with the basis. The pane still prints `✗ …`; the watcher no longer needs to read it.

### C5 — The watcher (`scripts/handoff-fire.sh` recycle region `:6786-6881`)

Seven edits, all inside the resume-mode branch; the fire path is untouched.

1. **Settle by poll, not sleep.** `:6786` `sleep 2` → poll `at_shell` every 0.3 s, cap 5 s (the 2 s was a fixed cost on every run).
2. **State on type.** After `:6800` (`→ relaunch typed into …`) → `lr_state_set "$LR_RUN_DOC" relaunched "$(cat "$CMDFILE")"`.
3. **Positive discriminator instead of 45 s of polling a corpse.** The wait at `:6811` becomes: check first, then sleep 0.5 s, cap 30 ticks = 15 s; break EARLY on `lr_state_get … .state == refused:capacity` (the launcher wrote it ~2 s after the type — pane 111: typed 17:22:14, IDL row 17:22:17, U04 §0). U04's option D (`jq` over the IDL for a `lr-fire-resume` refuse row newer than `RELAUNCH_TS`) is the fallback when the run doc is absent (an older launcher).
4. **Attempts under the budget.** With `CC_ADMIT_BUDGET=1` the existing single retype at `:6814` IS the release (U04 option A); keep the `at_shell` affirmative gate on it. Add `HF_RECYCLE_RELAUNCH_TRIES` (default 2) so a future budget change cannot silently re-create the 2-vs-3 hole, and add the T2 ratchet test (U05 §6) that compares the two constants across files.
5. **The no-process branch (`:6878-6880`) gets what its siblings have** (`:6796-6798`, `:6873-6875`): `emit_recycle_event recycle-dead 0 "$RSID" "<cause>"`, `goal_unreachable recycle-dead`, `hf_alarm recycle-dead …` (`hf_alarm` at `:5220` writes `~/.claude/handoff-alarms/alarm-*.json`, which `scripts/autonomy-sweep.sh:1921` already sweeps by class), `lr_state_set … failed:relaunch:<cause>` — where `<cause>` is the run doc's `refused:capacity` detail when present, else `no-process`. The message prints the REAL elapsed and whether the retype ran (today it says "90s" unconditionally, U04 §1).
6. **Engagement.** `RCY_ENGAGE_INTERVAL` 5 → 1 s (a transcript tail read, ~20 ms); `RCY_ENGAGE_TIMEOUT` stays 180 s inside the watcher but the run budget (C8) names `stalled:engaged` at 90 s. On engaged: `lr_state_set engaged` then `resumed`, then `cc-notify <requested_by.pane> "<one line>"`.
7. **`--await` becomes optional for the fleet path.** `lr-handoff.sh:621` adds `--await` unconditionally when `--source-pane` is given; `lr-fleet --one --no-await` drops it, and `recycle_await_verdict`'s `HF_RECYCLE_AWAIT_IVL` 5 → 0.5 s for callers that still await (`:11801`).

The `at_shell`-before-any-retype rule, the composer gate (`CC_RECYCLE_DRAFT_WAIT` 180 s — now surfaced as `exit-deferred`, not an opaque wait), and the pane-proof handshake are unchanged.

### C6 — Submit verification from the target transcript (U03 §4, adopted)

**Files:** `scripts/limit-recover/lr-fire-resume.sh:549-583`, new `scripts/limit-recover/lr-submit-probe.sh` (~25 lines), `scripts/limit-recover/lr-preseed-env.sh:115-117`.

- The prompt carries the run id as its token (`LR_SUBMIT_TOKEN=$LR_RUN`) — short, unique, present verbatim in the `type:"user"` record whether the prompt is `/limit-recover ingest …` or the C11 plain line.
- Replace the 5 blind CRs (`:572-576`) with the Tcl poll that `exec`s `lr-submit-probe.sh <cfg> <sid> <t0> <token>` every 3 s for 60 s, ONE re-CR on miss, then a loud verdict; write `submitted` / `failed:submit` to the run doc; exit **12** on failure so the launcher's rc means something.
- The READY gate: drop the dead `shift+tab to cycle` alternative (0 hits in 2.1.260); replace `timeout {}` at `:560` with an 8 s quiet-pty settle that injects anyway and says so (`READY-BY-QUIET`), and on total failure prints `✗ READY NEVER SEEN — prompt NOT typed: <prompt>` and writes `failed:submit:no-ready`.
- Preseed: add `fullscreenUpsellSeenCount` and `fullscreenDownsellSeenCount` to `UPSELL_FLOOR` (both real keys in 2.1.260; both sit at 3 in `.claude-secondary` and `.claude-tertiary` today) — remove the question rather than answer it.
- `tests/lr-fire-resume-submit.bats` (new): the probe finds the record; a missing record within the window yields rc 12; the quiet-pty fallback fires when READY is absent. Today: zero test coverage of the submit loop (U03 §2c).

### C7 — The engagement oracle keyed on the submitted record

**File:** `scripts/handoff-fire.sh:3680-3715` `resume_engaged`. It accepts a 4th argument `<token>`; when given, the qualifying assistant record must be newer than the LAST `type:"user"` record containing the token (not merely newer than `RCY_T0`). Pane 112's `ENGAGEMENT CONFIRMED` was a queued `<task-notification>` turn while the ingest never arrived (U03 §0, U11 §0) — this is the exact false positive the token closes. The synthetic `No response requested.` exclusion stays. Evidence written to the run doc: the assistant record's uuid, ts, first 80 chars.

`tests/handoff-recycle-remote-resume.bats` (30 cases) gains: a fixture with a task-notification assistant turn BEFORE the token's user record and none after must NOT engage; the same fixture with an assistant record after it must.

### C8 — The run watchdog, the poller backstop, the husk predicate, the repairs

**New `scripts/limit-recover/lr-watchdog.sh` (~150 lines), detached per run by `cc-lr recover`; lifetime = run budget (300 s) + 60 s grace.** Loop every 1 s: read the run doc; if `state` is terminal → exit; if `age > budgets[state]` → write `stalled:<state>`, raise `hf_alarm lr-stalled-<state> <pane> <sid> "" "<one line with the next command>"`, perform the repair for that state ONCE, then keep polling; at the run ceiling → `failed:<state>:watchdog-gave-up` + `cc-notify` to the requester with the exact manual command. Repairs (each bounded, each recorded as `repaired:<state>:<action>:<result>`):

| stalled state | repair | never |
|---|---|---|
| `targeted` (rank returned nothing) | re-rank once with reasons captured → `parked:no-target` + page | never pick a `none` |
| `exited` (no shell after `/exit`) | re-send `/exit` once via the existing `as_write` path; if the composer holds a draft → `exit-deferred` with the snapshot (a named wait) | never `/exit` over a non-empty composer |
| `relaunched` / `refused:capacity` | every 30 s: `at_shell` → retype the launcher (the token/budget make the 2nd attempt the release); the IDL term is quoted each time | never type when `pane_cc_state` is `unknown` |
| `alive` (no `submitted` in 45 s) | `cc_tui_submit_verified` (C12) with the run's prompt, once; rc 3 (composer held) → named, no retype | never a blind CR into an unknown composer |
| `submitted` (no assistant turn in 90 s) | re-check every 15 s to the ceiling; then alarm `lr-engaged-timeout` with `kitty @ get-text` tail as evidence | never retype — the session may be working (`:6861-6866`'s reasoning) |
| watcher pid dead with a non-terminal state | the husk repair below | — |

**The husk predicate (U04 §3, made executable as `lr_is_husk <sid> <pane>` in lr-lib.sh):** lock + tombstone exist ∧ no live registry row for the sid on the target ∧ `resume_engaged` false in the target ∧ (`pane_cc_state` ≠ `cc` ∨ registry pid dead). A husk is written as `failed:relaunch:husk` with `next = "cd <cwd> && nocorrect bash <launcher>"`, and the repair is to type exactly that once through `it2_type_verified` when `at_shell`.

**Poller backstop (`scripts/limit-recover/lr-reset-poller.sh`):**
- `:902-905` — retirement of a parked record requires `lr_recovery_state <sid> ∈ {engaged, resumed}` OR a live registry row on the target cfg; a lock+transcript alone (today's predicate) is a husk in 4 of 5 cases (U02 §2c). A run in `failed:*`/`stalled:*` is re-driven through the request arm instead of retired.
- A `§0b RECOVERIES` arm after the request drain: for every run doc under `recoveries/` that is non-terminal and whose `watchdog_pid` is dead → adopt it (spawn `lr-watchdog --run <run> --adopt`). One `find` + one `kill -0` per run; bounded.
- The request arm (`:657-661`) gains `fire_fail_note "$sid" request-rc$_rq_rc` on non-zero rc, and a reaper: `results/<sid>.json` with `rc != 0`, or `requests/*.json` older than 2 ticks, becomes a named alarm (U06 §4 gap 3).
- `MAX_PER_WT=1` (`:289`) applies to SPAWNS only; in-place recycles are not bounded by it (U06 §5 H).

### C9 — Census truthfulness (`scripts/limit-recover/lr-fleet.sh`, `lr-lib.sh`)

- `lr-fleet.sh:217` — subtract the registry pid from the argv census exactly as `:494-499` already does; DUPLICATE only when a second LIVE pid remains (I7). Today it labelled two successfully recovered sessions DUPLICATE and `--recover` refused to touch them (`:399`, `worst=1`).
- New dispositions: `RECOVERED→acct` (run doc engaged/resumed, or live registry row on the target with a non-error assistant turn after the transplant), `RECOVERING(<run> <state>)`, `HUSK` (the C8 predicate), replacing the over-broad `TRANSPLANTED→acct`.
- `lr_config_dirs` (`lr-lib.sh:20-27`) dedupes by `pwd -P` of `projects/` before the scan — `~/.claude-next/projects` is a symlink to `~/.claude/projects`, so 421 of 2,579 files are scanned twice today (U01 §1.2).
- `--one SID` (`:426`) tries the cheap resolver (`:428-433`, 0.039 s) FIRST and runs `lf_locate` only on a miss (U14 §2.3).
- `lf_locate` itself: the per-file `tail | grep | grep` loop (`:187-196`, 61 s alone) is replaced by U14's single-pass python (0.148 s on 2,158 files; artifact under `scratchpad/lr/`); kept as `cc-lr census --deep`.
- `lf_one` (`:335-338`) writes the watcher's cause into `results.tsv` (`PARTIAL — launcher refused term=load 2.51/core (refusal 2 of 3)`), read from the run doc (U05 P4).
- The `pane_after` column is derived from the registry row AFTER the run (account + pid changed, pane same), not copied from the input variable (`:327` — a proof that cannot fail, U09 gap #3).

### C10 — Ranker: the recovery lane, the recorded rationale, the spread (U13 §4, adopted)

- `bin/claude-accounts`: `--recovery` modifier (never a fourth lane) adds survival floors to `_excluded` — `RECOVERY_W_FLOOR 0.10` (weekly ≥ 90 excluded; = 9 h of survival at the worst observed burn 1.10 pp/session-h), `RECOVERY_S_CEIL 0.60` (reuses `DESK_5H_FLOOR`; note `S_CUT` 0.85 is already stricter than the 0.90 first proposed), `RECOVERY_F_FLOOR 0.05` (fable ≥ 90; also closes the float-ULP at weekly 98). Kill switch `CC_ROUTE_RECOVERY=off` is byte-identical to today. `route-meta` gains `recovery=1`.
- `lr-fleet.sh:294-309` `lf_pick_target`: `--rank <lane> --recovery 2>"$rdir/rank.$lane.stderr" | tee "$rdir/rank.$lane.stdout"`; on empty, the parked note carries the router's own reasons (not "returned nothing past $acct"); on a pick, `--assign "$t" --src lr-fleet` (skipped on `--dry-run`) so N concurrent recoveries walk DOWN the ranking inside the 90 s cache TTL (handoff-fire skips `--assign` on `--recycle` at `:9296` on a premise that is false for a cross-account recycle). Evidence goes into the run doc's `target`.
- Tests: `tests/account-recovery-lane.bats` and three fleet cases, verbatim from U13 §5, with the three named mutation arms.

### C11 — Ingest: the verified fast path (U12 §6, adopted)

- New `scripts/limit-recover/lr-ingest-verify.sh <bundle>` — every ingest step-1 assertion is a shell predicate (config dir, sid, lock target, transcript path, source tombstone, branch ≠ `pool/*`, `session-continue.sh clear`) plus the `gaps_at_handoff == 0 ∧ counts.gaps == 0 ∧ waiting == 0 ∧ open delegations == 0` clauses from `MANIFEST.json`/`audit.json`, plus a 0.13 s `--ledger-only` re-check; receipt `INGEST-VERIFIED.txt`.
- `lr-handoff.sh:464`: on rc 0 the prompt is the one-line non-slash form (template in U12 §6.2, carrying `run:<id>` as the token); on rc ≠ 0 the prompt stays `/limit-recover ingest <bundle> — lr-ingest-verify FAILED: <clause>` (fail-closed, named in the prompt). A non-slash prompt also removes the slash-autocomplete class of swallowed CRs (`lr-fire-resume.sh:564-567`).
- `HANDOFF-CONTEXT.md` emits the LAST DoD entry plus a pointer (86,888 B → ~1 KB); `MANIFEST.json` drops the 3.8 KB `source_argv` env dump, which is wrong about the tier in 3 of 5 (U02 §1).
- Measured stake: 6 → 1 model round-trips, ~26.5 K → ~0.1 K permanently resident tokens per recovered session, −4 min across today's three ingests (U12 §6.3). Scope limit stated: all five of today's bundles were `gaps == 0`; the `gaps > 0` branch keeps the full ingest unchanged.

### C12 — The pane transport lib (U08 §4), used only by C8's repairs and C6

New `scripts/lib/cc-tui.sh` with `cc_tui_sid <pane>`, `cc_tui_type <pane> <file>`, `cc_tui_submit_verified <pane> <file>` (rc 0/1/2/3/4/5 as U08 §4.3), `cc_tui_clear <pane>` — lifted from `handoff-fire.sh`'s private `composer_scrub_verified` (`:2491-2517`), `composer_content` (`:2392`), `paste_readback_ok` (`:2646`), `marker_in_user_record` (`:2956`). Wire = `kitty @ send-text --match id:N --from-file <f> --bracketed-paste=enable` (byte-exact; the repo uses `--from-file` nowhere, and its absence is the likely cause of the 5 "stochastic" MANGLED read-backs — falsifier: grep those payloads for a backslash). Never `send-key`; never `session run` for a message; emptiness pre-gate mandatory; `\x15` is the clear (ESC also interrupts a running turn). `bin/it2-kitty` gains one verb `session tui-submit -s <id> --from-file <f>` so there is still one seam. `bin/cc-pane send` is documented as unavailable on kitty until it grows a kitty driver (its text path is hardcoded to iTerm2 AppleScript, `scripts/lib/cc-type-verified.sh:126`).

### C13 — What reaches the operator: notify, status, close

- **Terminal notify** (watcher on `resumed`; watchdog on `failed:*`): `cc-notify <requested_by.pane> "lr <run>: ENGAGED — pane 117 cb227486 next4→next2 in 38 s (exit 4 s · boot 5 s · submit 3 s · first turn 14 s) · cc-lr status <run>"` or `"lr <run>: FAILED at relaunched — capacity refused (segments 61% > 50%) · pane 117 is at a SHELL (not a husk: watchdog retrying every 30 s until 12:31) · manual: cd … && nocorrect bash <launcher>"`. Delivered as a message at a safe boundary — the mailbox wake U11 §2 measured to the second — never as keystrokes.
- **`commands/limit-recover.md`** gains a `fleet --fast` section that says, in this order: `cc-lr find <what the screenshot shows>` → `cc-lr recover <pane>` → **END THE TURN** (the operator's queued prompts dequeue; the notify wakes you) → relay `cc-lr status --last` verbatim in the close. A foreground `until` loop in this command is a defect, named as such.
- **The close block** is the `cc-lr status --last` render (rendered, relayed verbatim per the close rules), one row per session: `PANE · SID8 · ACCT→ · STATE · ELAPSED · EVIDENCE(assistant uuid) · NOTE`.

---

## 5. Every timeout, with its justification

| constant | value | where | why this number |
|---|---|---|---|
| `cc-lr find` kitty RPC bound | 3 s | C2 | `kitty @ ls --match id:N` is 37 ms; bare `ls` 80–500 ms; one 10.06 s timeout observed (U07 §5) — 3 s separates "slow" from "hung" and the result is INDETERMINATE, never "gone" |
| driver foreground | < 1 s | C2 | registry 2–12 ms + state write + two detaches; measured parts sum to ~0.3 s |
| budget `located→targeted` | 3 s | run doc | `claude-accounts --rank` 0.47–1.09 s (U14 A5) |
| budget `targeted→transplanted` | 10 s | run doc | pipeline ≈ 3 s (U02 §1); 241 MB tail case ≈ 5 s (U14 §1.3) |
| budget `transplanted→exited` | 30 s (or `exit-deferred`) | run doc | shell confirmed in 3–15 s in all 8 logs (U04 W2); `HF_RECYCLE_SHELL_WAIT_S` 600 stays as the watcher's own cap, but a stall is NAMED at 30 s |
| composer gate | 180 s / 15 s (unchanged) | `handoff-fire.sh:11634` | an operator draft must never be submitted; now surfaced as `exit-deferred` with the snapshot |
| shell settle | poll 0.3 s, cap 5 s | C5.1 | replaces a fixed 2 s |
| budget `exited→relaunched` | 10 s | run doc | `it2_type_verified` sub-second; 2 tries × 3 s |
| process wait | 0.5 s ticks, cap 15 s, early-exit on `refused:capacity` | C5.3 | CC boot ≈ 4 s (GUESS, U14 B); a refusal writes its state ~2 s after the type; today's 45 s+45 s polled a corpse |
| relaunch attempts | 2, gated on `at_shell` | C5.4 | with `CC_ADMIT_BUDGET=1` attempt 2 is the release; `HF_RECYCLE_RELAUNCH_TRIES` guards the arithmetic |
| admission token TTL | 180 s | C4 | probe→launcher gap 11–16 s; 4× the `/exit`→type path bound |
| `LR_FLEET_CAP_WAIT_S` / `_IVL_S` | 60 s / 5 s | C4 | load term off ⇒ remaining terms are real; beyond 60 s the watchdog's 30 s repair cadence owns it; nothing sits in a foreground |
| budget `alive→submitted` | 45 s | run doc | READY typically 2–4 s after boot; probe returns <1 s; 20 × 3 s poll + one re-CR (U03 §4.2) |
| budget `submitted→engaged` | 90 s | run doc | first turn ≈ 12–15 s irreducible (GUESS, U14 B); 5–10 s on all 4 successes today; `RCY_ENGAGE_TIMEOUT` 180 stays inside the watcher, the stall is named at 90 |
| `RCY_ENGAGE_INTERVAL` | 1 s | C5.6 | a 20 ms tail read |
| `HF_RECYCLE_AWAIT_IVL` | 0.5 s | C5.7 | adds ≤ 0.5 s to any awaited verdict instead of ≤ 5 s |
| watchdog repair cadence (capacity) | 30 s | C8 | matches the 20–30 s probe interval the fleet used today; a genuinely hot box changes on that scale, not faster |
| run ceiling | 300 s | run doc | U14 §4.1's "< 5 min under load"; after it, the run is `failed:*:watchdog-gave-up` with the manual command and a page |
| watchdog lifetime | ceiling + 60 s | C8 | one extra minute to deliver the notify and write the terminal state |
| poller backstop | 600 s (unchanged) | C8 | second line only — for a watchdog that died; `WatchPaths` on `recoveries/` is the operator's c10 step that makes it event-driven |
| stop-failure ARM 2 | ≤ 0.35 s of a 10 s hook budget | C3 | measured 0.19–0.25 s today + 79 ms tier + 10 ms tail |
| `statusLine.refreshInterval` | 5 s | C1 | a halted pane renders 0 times today; 5 s keeps the telemetry row ≤ 5 s stale at 89 ms/render |

---

## 6. Verification per step — transcript over screen

| step | oracle | store | cost |
|---|---|---|---|
| located | registry row pid `kill -0` + `lr_last_api_error` envelope (`isApiErrorMessage`, never text — the skill listing quotes the limit string in every transcript) | registry + 128 KB transcript tail | ~15 ms |
| targeted | `claude-accounts --rank --recovery` stdout row + stderr reasons recorded | run doc | 0.5–1 s |
| transplanted | `transplant.json` `ok:true` + sha256 match (unchanged `lr-transplant.sh:85-89`) | bundle | 0.45 s |
| exited | `pane_cc_state == shell` (affirmative only; `unknown` is not a shell) | watcher log + run doc | 3 s ticks today → 0.3 s |
| relaunched | `it2_type_verified` nonce echo read back + CR (unchanged `bin/it2-kitty:531-575`) | run doc | sub-second |
| admitted / refused | the launcher's own `cc_capacity_admit` verdict, written by `lr-fire-resume` with the IDL row | run doc + IDL | ~2 s after type |
| alive | `cc_alive` (a `claude` on the pane's tty) | run doc | 0.5 s ticks |
| submitted | a `type:"user"` record in the TARGET transcript containing the run token (U03 §4; record shape verified on pane 117's real ingest record) | target transcript tail | <1 s |
| engaged | a non-error, content-bearing assistant record newer than the submitted record (C7) | target transcript | 20 ms per poll |
| resumed | registry row `account` = target ∧ `pid` alive ∧ `session_id` = sid ∧ pane unchanged; `cc-notify --receipt` for the delivery | registry + notify | ms |
| husk | the C8 4-read predicate | lock, tombstone, registry, target transcript | ~50 ms |

No verdict is derived from `send-text`'s rc (always 0), from telemetry age (52 min stale while alive), from a `#` comment typed into a pane, or from a `$TMPDIR` log.

---

## 7. What the operator sees, step by step

1. **Before the limit** — statusline: `(4) ⌗112 d02d8feb 52% · wt-cc-095358-75429 (06ce6fee5) · xhigh` (+ with C1 change 2/3, the pane's own 5-hour % is on the row it will halt on).
2. **At the limit** — the pane shows CC's own `You've hit your session limit · resets 2:40pm`. Nothing is typed into it. Within 1 s the hook has written `requests/d02d8feb.json` and state `located`; `cc-lr find 112` prints `112 d02d8feb next4 …/wt-cc-095358-75429 70909 ALIVE fable/xhigh limited(five_hour, resets 14:40) request-written`.
3. **The one command** — the operator attaches the screenshot (or types the pane id) and the session runs `cc-lr recover 112`. One line back in <1 s: `lr lr-…-d02d8feb · pane 112 d02d8feb · next4 → (ranking) · detached · status: cc-lr status lr-… · you will be notified here`. The session ends its turn.
4. **In the recovered pane** — `/exit`, the shell prompt, the typed relaunch line, then `lr-fire-resume`'s own lines (`-- capacity-admit: ADMIT (admission token, 9s old …)`, the resume menu answered, `lr-fire-resume: prompt SUBMITTED — user record present`), then Claude Code with the first assistant turn on the new account. Same window id, same title, same uuid; the statusline now reads `(2) ⌗112 d02d8feb …`.
5. **The wake** — a `cc-notify` message lands in the invoking session: `lr <run>: ENGAGED — pane 112 d02d8feb next4→next2 in 38 s (…) · cc-lr status <run>`. The session relays `cc-lr status --last` verbatim and closes.
6. **On any failure** — the same channel, naming the state, the cause, whether the pane is a shell or a husk, what the watchdog is doing and until when, and the one manual command. The alarm class is also in `~/.claude/handoff-alarms/` for the desk sweep.
7. **Fleet** — `cc-lr recover --all`: N lines, N runs, ONE notify per run, and `cc-lr status --all` as the table.

---

## 8. Acceptance — the 5-session drill (measurable, repeatable)

**Setup (no real 429 needed; the hook arm has its own bats fixtures SF-a…h and is exercised for real at the next genuine limit):** launch 5 throwaway sessions on next4 in fresh kitty OS-windows (the plan's E2E shape, `docs/plans/LIMIT_RECOVER_100P.md` § 6 "E2E RE-RUN"), 3 in the shared checkout and 2 in worktrees (today's shape), each takes one real turn. `cc-lr recover --all --drill` treats them as limited (the drill flag bypasses only the "last assistant word is a limit" gate; every other predicate, gate and write is the production path).

**Expected numbers (idle box; every one is read from disk, not from the drill's own prose):**

| measure | expected | read from |
|---|---|---|
| `cc-lr find <pane>` per session | ≤ 0.3 s, exactly one row | `time` |
| `cc-lr recover --all` foreground | ≤ 1.5 s total, 5 run ids | `time` |
| invoking session tool calls after the fire | ≤ 2 (`recover`, then `status --last` after the notify) | transcript |
| per-session `located→engaged` | ≤ 40 s (≈ 26 s budget + slack) | run doc `states[]` |
| fleet wall (5 concurrent) | ≤ 60 s = max(single), not 5× | ledger first `located` → last `engaged` |
| `engaged` | 5/5, each with a `type:"user"` record carrying the run token and an assistant record after it in the TARGET transcript | `jq` over the 5 target transcripts |
| runs without a terminal state | 0 | ledger |
| `recycle-intent` rows without a later outcome row for the same `target_pane` | 0 (today: 4) | `~/.claude/logs/handoffs.jsonl` |
| husks (`lr_is_husk`) | 0 | predicate |
| `cc-lr find --limited` after | 0 rows; `cc-lr find <pane>` shows `recovered→next2/next3` with the new pid | registry |
| kitty window count before == after | equal; the 5 ids unchanged | `kitty @ ls` |
| registry rows for the 5 panes | account = target, pid alive, session_id unchanged | registry |
| target spread | no two Fable sessions on an account whose weekly ≥ 90; rationale files present for every pick | `rank.*.std{out,err}` |
| tokens in the recovered sessions' first turn | 1 model round-trip on the `gaps == 0` path (C11) | `message.usage` dedup by `message.id` |

**Fault-injection arms (each must produce a NAMED state, an alarm class, and no husk):**
- (a) `CC_ADMIT_SEGMENT_OVERRIDE=99` in one launcher → `refused:capacity(segments)` within 5 s of the type, `stalled:relaunched` at 10 s, watchdog retries at 30 s, alarm `lr-stalled-relaunched`, pane at a shell with the reason printed; remove the override → `engaged`.
- (b) `kill -TERM <watcher_pid>` mid-run → the run's watchdog adopts (`repaired:<state>:adopt`); kill the watchdog too → the poller backstop adopts within one tick.
- (c) a held draft in one composer → `exit-deferred` with the snapshot; nothing typed; clear the draft → proceeds.
- (d) `CC_ROUTE_RECOVERY` floors excluding every account (seeded rows) → `parked:no-target` with the router's reasons verbatim, one page, no transplant (the irreversible step never ran).
- (e) replay today's pane-112 shape: a queued task-notification turn before the token record → NOT `engaged` until the real record arrives.

**Red-proof discipline:** every new bats case is run once against the unpatched tree and must fail there (T1 fails with status 9, T2 with `2 -ge 3` false, T3 on the LOAD row, the DUPLICATE case with the old OR); a case green in both arms is an equivalence guard, not evidence (`docs/lessons/green-in-both-arms-…`).

---

## 9. What I deliberately do NOT change, and why

- **`scripts/limit-recover/lr-transplant.sh`** — 0.45 s, sha-verified, correct ordering (lock → copy → tombstone → rename). The two `python3 -c realpath` starts (0.09 s) are not worth a diff in the one file whose correctness is the whole split-brain guarantee.
- **`hooks/handed-off-session-guard.sh`, the tombstone, the lock, `tests/lr-resume-tombstone-guard.bats`** — the protections that kept both incidents merely untidy. The husk predicate READS them; nothing weakens them.
- **The `at_shell` affirmative-only gate before any keystroke into a pane** (`handoff-fire.sh:6805-6812`) and the composer emptiness pre-gate — U08 §5: the operator-typing race cannot be removed, only detected; these are the detectors.
- **`cc_capacity_probe`'s never-spend contract** (`capacity-admit.sh:519-533`) — test 15c keeps the token from turning it into a spend.
- **The headroom / segments / active terms and their ceilings** — `:721-727` says 50 % is provisional and gives the re-derivation; `:790-800` forbids moving 8 as an arithmetic consequence. Only the load term's default for these callers, the net-zero delta, and the counter key change.
- **The ranker's scoring function** (`score_fable`, `score_general`) — the deadline-dominant urgency is the operator's own use-it-or-lose-it rule; only ELIGIBILITY gets a recovery modifier.
- **`cc-notify` as the only message channel into a live session** — no design here types a message into a composer.
- **Iron rule 7** — a recovery never lands, ships or deploys.
- **`kitty @ send-key`** — never used; unobservable encoding, constant rc 0.
- **The poller's reset-wait for the genuinely no-target case** — waiting for the source account's reset is correct when every other account is excluded by the survival floors; the design makes that case NAMED (`parked:no-target`) instead of silent.
- **No new launchd plist.** A new plist is an operator install step; the per-run watchdog is detached by the driver and the poller is the backstop. The two plist edits that ARE proposed (`WatchPaths` on `requests/` and `recoveries/`, `LR_POLLER_AUTORECOVER`) are filed as `c10` steps, not assumed.
- **`~/.claude/settings.json`** — `statusLine.refreshInterval` is proposed as a c10 step, never written by an agent.
- **`scripts/wrap-ledger.sh`** (9.1 s) stays off every recovery path (U14 A6).
- **`HANDOFF-CONTEXT.md`'s UNRECONSTRUCTED marker** — load-bearing for the driver-authored case; only its 87 KB DoD dump is trimmed.

---

## 10. Implementation order, sizes, tests (each wave lands and converges on its own; the live layer is a per-file symlink farm plus the copy-deployed `statusline.sh`)

| wave | components | files | est. lines | tests |
|---|---|---|---|---|
| W1 — stop the bleeding (one land) | C4 launcher env + budget key + net-zero + token; C5.3/C5.5 discriminator + no-process branch emits; C9 DUPLICATE overlap; C7 token oracle | `lr-handoff.sh`, `capacity-admit.sh`, `lr-fleet.sh`, `handoff-fire.sh`, `lr-fire-resume.sh` | ~180 | capacity-admit T1/15b/15c/T4, T2 ratchet (new `tests/lr-relaunch-bound.bats`), T3 in `capacity-admit-coverage.bats`, lr-fleet DUPLICATE case, remote-resume token case |
| W2 — identity | C1 statusline + telemetry + user_vars | `statusline.sh`, `hooks/session-register.sh`, `install.sh`/deploy-live | ~40 | statusline-identity layer 2 (+2), session-registry (+1); the 30-col eyes check |
| W3 — the spine | §3 state store + `lr_state_set`; C2 `bin/cc-lr`; C8 `lr-watchdog.sh` + husk predicate + poller retire fix + adopt arm; C13 notify | `lr-lib.sh`, new `bin/cc-lr`, new `lr-watchdog.sh`, `lr-reset-poller.sh`, `lr-fleet.sh` (`--run`, `--no-await`, results cause) | ~750 | new `tests/lr-state.bats`, `tests/cc-lr.bats` (find/refuse/recover-detach/status), `tests/lr-watchdog.bats` (budgets, repairs, adopt, husk), poller retire + reaper cases |
| W4 — detection | C3 hook ARM 2 + `lr_last_api_error` fields; plist `WatchPaths` filed as c10 | `hooks/stop-failure-marker.sh`, `lr-lib.sh`, `com.reso.lr-reset-poller.plist` (SSOT) | ~60 | stop-failure-marker SF-a…h |
| W5 — submit + ingest + ranker | C6 probe + quiet-pty + rc 12 + preseed keys; C11 fast path; C10 recovery lane + rationale + assign; C12 lib | `lr-fire-resume.sh`, new `lr-submit-probe.sh`, new `lr-ingest-verify.sh`, `lr-handoff.sh`, `bin/claude-accounts`, `accounts.json`, new `scripts/lib/cc-tui.sh`, `bin/it2-kitty` | ~450 | `lr-fire-resume-submit.bats`, `lr-ingest-verify.bats`, `account-recovery-lane.bats`, fleet target cases, `cc-tui.bats` |
| W6 — census speed + docs | C9 single-pass census, config-dir dedupe, `--one` order; `commands/limit-recover.md` fleet --fast; the 5-session drill as `tests/lr-drill.sh` | `lr-fleet.sh`, `lr-lib.sh`, `commands/limit-recover.md` | ~200 | lr-fleet/lr-lib cases; the drill's expected-numbers table as assertions |

W1 alone converts today's 4 PARTIALs into RECOVERED (U02 §5, U04 §5A) and makes the failing branch visible; W2 makes the screenshot a key; W3 is what the operator asked for by name ("if something goes wrong along the way, can we easily identify it"); W4 removes the 2 h 37 m of post-detection idle (U10 §1g); W5 makes RECOVERED mean ingested; W6 is the last 40–86 s.

---

## 11. Risks and open measurements (labelled)

- **GUESS:** CC teardown ≈ 3 s, boot ≈ 4 s, first turn ≈ 12–15 s (U14 B) — the state budgets in §5 derive from them; the drill's `states[]` timestamps are the measurement, and budgets are env-overridable (`LR_BUDGET_<STATE>_S`) so a wrong guess is a config change.
- **GUESS:** `session_name` / `rate_limits` present in the live statusline payload on a Max plan (U07 §7). Falsified by one render; absence costs nothing (`// null`).
- **Unmeasured:** whether `StopFailure` fires inside an Agent-Teams assignee (U10 §3c; 0/10 today were teammates) — SF-e is the fixture; until then the arm skips assignees by both oracles.
- **Unmeasured:** whether a transplanted session's first hour burns faster than the 0.39 pp/session-h fleet median (U13 §6) — if so `RECOVERY_W_FLOOR` rises; the re-derivation command is in U13 §3a.
- **Residual race:** the operator typing into a pane between `/exit` and the relaunch line — not removable (U08 §5); the emptiness gate and echo-verified nonce detect it and leave the composer clean.
- **`kitty @` socket flakiness** (1 hard failure in ~12 calls, one 10 s timeout with a corrupt payload): every RPC is bounded and an error is INDETERMINATE; no RPC sits on the driver's <1 s path except the registry read.
- **Statusline glyph:** `⌗` may downsample in kitty like the four reverted designs; ASCII `#` is the fallback and the choice is pinned at the eyes before landing.
- **The `--drill` flag** must be impossible to set from a request file or the hook (argv only, refused under `--from-daemon`), or a drill could transplant a working session.
- **Two plist edits and one settings key are operator `c10` steps**; until they land, detection→drive latency is bounded by the operator's own `cc-lr recover` (≈ 1 s) rather than the poller (≤ 600 s) — which is still the target the operator set.
