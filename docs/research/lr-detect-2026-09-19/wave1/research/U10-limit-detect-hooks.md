# U10 — limit detection at the moment it happens, on the limited session itself

**Headline: the detector already exists, already fired on all five of today's sessions, and its
output is read by nothing.** `~/.claude/autonomy/stop-failure/rate_limit__next4.jsonl` recorded the
first limit at **2026-09-19T16:58:33Z = 11:58:33 CDT — 3 minutes 00 seconds BEFORE the operator's
first `/limit-recover` at 12:01:33** — and all five sessions inside 9 minutes. The screenshot path
was never necessary. What is missing is 40 lines: a request-writing arm and a way to wake the poller
in seconds instead of 600.

---

## 1 · Which hooks fire when `You've hit your session limit · resets 2:40pm` renders

### 1a · `Stop` does NOT fire. Measured 5/5.

`Stop` carries `~/.claude/hooks/notify.sh complete` (`~/.claude/settings.json` `.hooks.Stop[0]`),
which appends one line per firing to `$(getconf DARWIN_USER_TEMP_DIR)/cc-notify/claude-notify.log`
(`hooks/notify.sh:113-115,286`). Debounce is **2 seconds** (`hooks/notify.sh:211`), so absence at a
timestamp is a verdict, not a suppression.

| sid | limit record (UTC) | = CDT | `notify complete` for this sid: last before / next after |
|---|---|---|---|
| `e442434c` | 17:27:19 (and 16:58:33) | 12:27:19 | 11:57:45 / 12:48:55 |
| `d02d8feb` | 16:59:19 | 11:59:19 | 11:56:35 (permission) / 12:44:35 |
| `09e64dcb` | 17:11:29 | 12:11:29 | 11:16:45 / 12:45:37 |
| `28f07827` | 17:14:48 (and 17:07:35) | 12:14:48 | 11:49:08 / — |
| `cb227486` | 17:07:16 | 12:07:16 | 11:50:25 / — |

Positive control on the same instrument, same minutes: `11:57:45 e442434c`, `12:00:36 21446ede`,
`12:03:55 26cd14be`, `12:05:50 4bc1159f` — the log was live and capturing other sessions' Stops
throughout. `~/.claude/logs/session-continue.log` likewise has no row for `d02d8feb` between
17:04 and 17:44.

Independently confirmed in-tree: `docs/research/exhaustive-drive-2026-09-08/A10-idle-visibility-skeptic.md:12`
— *"The Stop chain does not run when a turn ends in an API failure; only `hooks/stop-failure-marker.sh`
(event `StopFailure`) runs."*

Consequence, and it is the one that bit today: `hooks/session-beat.sh stop` never runs, so
`~/.claude/cc-beats/<sid>.json` keeps `kind:"prompt"` on a limited pane — **every beat-based sensor
reads a limit-dead session as BUSY.**

### 1b · `Notification` does not reach anything readable

`.hooks.Notification` has 4 objects, matchers `permission_prompt` / `elicitation_dialog` /
`idle_prompt`. `idle_prompt` routes only to `hooks/push-critical.sh`, which is **inert**
(`hooks/push-critical.sh:22-23` — `[ -z "${PUSHOVER_TOKEN:-}" ] && exit 0`) and writes no log. So
whether `idle_prompt` fires on a limit-parked composer is **UNMEASURED on this box** — no instrument
exists. Do not build on it.

### 1c · `StopFailure` DOES fire, at the instant, with the error in the payload

Registered in **all five** config dirs (they are five separate real files, not symlinks —
`shasum`: `0b821d7f8d9d / dd573fb56e47 / 5882a9fdd305 / 698b98ea21fc / b451255fc78d`), each as
`~/.claude/hooks/stop-failure-marker.sh`, timeout 10.

```
jq -r '(.hooks.StopFailure//empty)|[.[].hooks[].command]|join(",")' ~/.claude-quaternary/settings.json
=> ~/.claude/hooks/stop-failure-marker.sh
```

Payload shape, measured on 2.1.220 and quoted at `hooks/stop-failure-marker.sh:23-27`:

```json
{"session_id":"…","transcript_path":"…","cwd":"/private/tmp/hs/scratch",
 "prompt_id":"…","effort":{"level":"high"},"hook_event_name":"StopFailure",
 "error":"authentication_failed","last_assistant_message":"Not logged in · Please run /login"}
```

`prompt_id` and `effort` were absent from a second capture in the same run ⇒ **OPTIONAL**. Nothing
in the payload names the account, the pane, or the reset time.

**Today's receipts** — `~/.claude/autonomy/stop-failure/rate_limit__next4.jsonl`, 12 lines, 5 sids:

```
16:58:33Z e442434c  /Users/chrisren/Development/claude-infrastructure
16:58:43Z e442434c
16:58:49Z e442434c
16:59:19Z d02d8feb  /Users/chrisren/Development/.worktrees/wt-cc-095358-75429
17:01:34Z 09e64dcb  /Users/chrisren/Development/claude-infrastructure
17:07:16Z cb227486  /Users/chrisren/Development/claude-infrastructure
17:07:35Z 28f07827  /Users/chrisren/Development/.worktrees/wt-cc-100046-36511
17:09:46Z 28f07827
17:09:50Z 28f07827
17:11:29Z 09e64dcb
17:14:48Z 28f07827
17:27:19Z e442434c
```

Each row: `{ts, error:"rate_limit", account:"next4", config_dir, session_id, cwd, transcript_path,
hook_event_name:"StopFailure", last_assistant_message:"You've hit your session limit · resets 2:40pm
(America/Chicago)"}` (`hooks/stop-failure-marker.sh:122-128`).

Second instrument, same event: `~/.claude/autonomy/idl.jsonl` carries
`{"hook":"stop-failure-marker","sid":"09e64dcb-…","disposition":"fired","reason":"marker-appended"}`
at **`ts:"2026-09-19T17:11:29Z"`** — the same second as that session's limit record
(`17:11:29.347Z`). Latency from limit to hook completion is **sub-second**.

**The hook re-fires per limited turn**, not once per session: `e442434c` 3× in 16 s, then again 28
minutes later. `09e64dcb` fired twice, 10 minutes apart — the second because a queued
`task-notification` ran a turn while blocked, the exact shape recorded at
`docs/research/lr100p-2026-09-09/00-context.md:13` (*"the TUI input+turn loop is alive in the
limit-blocked state"*). Any request writer therefore needs an event-keyed latch (§2d).

### 1d · Can a hook read the error from the transcript's last assistant record? Yes — and the
### structured `quotaLimits` block is better than the text everything currently parses.

Verbatim record, `~/.claude-quaternary/projects/-Users-chrisren-Development--worktrees-wt-cc-095358-75429/d02d8feb-1f9d-42bb-8487-80b726c88950.jsonl.handed-off`
line **1130 of 1141**:

```json
{"parentUuid":"560745b8-…","isSidechain":false,"type":"assistant",
 "uuid":"fd4db9e3-ce7d-423e-a885-a61e1aef5817","timestamp":"2026-09-19T16:59:19.471Z",
 "message":{"id":"66c56f1c-…","model":"<synthetic>","role":"assistant",
            "stop_reason":"stop_sequence","stop_sequence":"","type":"message",
            "usage":{"input_tokens":0,"output_tokens":0,…},
            "content":[{"type":"text","text":"You've hit your session limit · resets 2:40pm (America/Chicago)"}]},
 "requestId":"req_011CfD9uNPRAP7DE2ZMo8fL6",
 "quotaLimits":{"status":"rejected","resetsAt":1789846800,
                "unifiedRateLimitFallbackAvailable":false,"rateLimitType":"five_hour",
                "overageStatus":"rejected","overageDisabledReason":"org_level_disabled",
                "isUsingOverage":false},
 "error":"rate_limit","isApiErrorMessage":true,"apiErrorStatus":429,
 "session_id":"d02d8feb-…","userType":"external","entrypoint":"cli",
 "cwd":"/Users/chrisren/Development/.worktrees/wt-cc-095358-75429",
 "sessionId":"d02d8feb-…","version":"2.1.260","gitBranch":"cc-095358-75429"}
```

The next record (line 1131) is `{"type":"system","subtype":"turn_duration","durationMs":282694}` —
the turn ends, and nothing else runs. Lines 1132-1140 are state records
(`bridge-session`, `cost-state`, `last-prompt`, `ai-title`, `mode`, `permission-mode`, `atis-latch`);
line 1141 is the `queue-operation` that enqueued a task-notification at 17:19:50Z which never ran.

**All five sessions carried byte-identical `quotaLimits`**: `resetsAt: 1789846800`,
`rateLimitType: "five_hour"`, `status/overageStatus: "rejected"`,
`overageDisabledReason: "org_level_disabled"`, `unifiedRateLimitFallbackAvailable: false`.
`1789846800` = 2026-09-19T19:40:00Z = 14:40 America/Chicago.

Three things follow, and each is a correctness upgrade over today's code:

1. **`quotaLimits.resetsAt` is an epoch integer.** `scripts/limit-recover/lr-audit.py:82` reverse-engineers
   the reset from prose with
   `r"resets (?:([A-Z][a-z]{2} \d{1,2}) at )?(\d{1,2}(?::\d{2})?(?:am|pm)) \(([^)]+)\)"`.
   That regex has no `resetsAt` fallback. A wording change silently returns no reset, and
   `lr-reset-poller.sh:773` `[[ -n "${reset:-}" ]] || continue` then drops the session entirely.
2. **`rateLimitType` is a closed enum** (`five_hour` here). `lr-audit.py:76-78` classifies by English
   prefix — `("session","You've hit your session limit")`, `("weekly",…)`,
   `("monthly_spend",…)`. `limit-reset-safety-gate.sh:118-121` declares LR-blind precisely because
   "the FABLE-scoped limit message's verbatim shape has never been captured". `rateLimitType`
   closes that blindness without a fixture.
3. **`unifiedRateLimitFallbackAvailable` and `overageStatus`** say whether *waiting* is even an
   option. Nothing in the fleet reads either field today
   (`grep -rn 'quotaLimits\|resetsAt\|rateLimitType' hooks/ bin/ scripts/` ⇒ 0 hits).

The in-tree predicate that already answers "is the last assistant record an api error" is
`lr_last_api_error()` at `scripts/limit-recover/lr-lib.sh:129-159` — tail-bounded at
`LR_TAIL_BYTES:-131072`, gates on the **envelope** (`type=="assistant"` ∧ `isApiErrorMessage`) not
the text, skips `No response requested.` turns, and returns
`"<uuid>\t<error>\t<kind>\t<timestamp>"` where `uuid` is the death record's own uuid — the natural
latch key. **Extend its Python to also emit `quotaLimits.resetsAt` and `rateLimitType`; it is a
two-line change in one SSOT and every caller inherits it.**

### 1e · What `completion-assert.sh` and `session-continue.sh` do with a limit record: nothing

```
grep -n 'isApiErrorMessage\|api_error\|rate_limit\|hit your' hooks/completion-assert.sh  => (no output)
grep -n 'isApiErrorMessage\|api_error\|rate_limit\|hit your' hooks/session-continue.sh   => (no output)
```

Neither hook has any notion of an api-error tail. This is currently harmless *because Stop never
runs on that turn* (§1a) — but it is a latent trap the moment anyone assumes otherwise: if Stop did
run, `session-continue.sh`'s mechanical floor would see uncommitted session writes and block the
stop of a session that cannot take another turn, and `completion-assert.sh` would read the limit
text as the closing assistant message.

### 1f · The other two detectors that also fired, and also did nothing

- **`lr-reset-poller.sh`** (launchd, `StartInterval 600`, `LR_POLLER_AUTOFIRE=1`) PARKED all five:
  `~/.reso/limit-recover/poller.log:2644-2648`, `16:59:23Z / 16:59:25Z / 17:09:45Z / 17:09:47Z /
  17:09:51Z`, each `resets 2026-09-19T19:40:00Z`. Park records at
  `~/.reso/limit-recover/parked/<sid>.json` = `{sid, acct, cfg, cwd, kind, reset_at_utc, parked_at}`
  — **no pane field**, which is why nothing could act in place.
  Its verdict was *wait 2 h 40 m*, and that is correct behaviour for a poller whose only lever is
  time. The operator wanted a **move**, and no detector had a path to one.
- **`hooks/recover-inject.sh`** — built (13,622 B, 2026-09-12), a UserPromptSubmit hook whose header
  says its whole purpose is to replace the paragraph the operator typed seven times in 93 seconds.
  `grep -rn 'recover-inject' ~/.claude/settings.json ~/.claude/settings.local.json` ⇒ **0 hits. It
  is not registered anywhere.** And even registered, UserPromptSubmit only fires when a human types
  — it cannot shorten the detection-to-action gap.

### 1g · The cost of the gap, in minutes

| sid / pane | detected (StopFailure) | first recovery fire | idle after detection |
|---|---|---|---|
| `e442434c` / 121 | 11:58:33 | 12:44:03 | **45m30s** |
| `d02d8feb` / 112 | 11:59:19 | 12:04:50 | 5m31s |
| `09e64dcb` / 111 | 12:01:34 | 12:21:26 | 19m52s |
| `cb227486` / 117 | 12:07:16 | 12:52:07 | **44m51s** |
| `28f07827` / 114 | 12:07:35 | 12:48:51 | **41m16s** |
| | | **total** | **2 h 37 m** |

Fire times from `~/.reso/limit-recover/fleet/one-20260919T17*/results.tsv` run-dir stamps. The two
sessions the operator "discovered" by census at ~12:40 and screenshotted at 12:57/12:59 had been
sitting in a file on disk, named, with cwd and transcript path, since **12:07**.

---

## 2 · The smallest hook that closes it

### 2a · Where it goes

**Do not write a new hook.** Add a second arm to `hooks/stop-failure-marker.sh`, after its existing
marker append (`:130`), guarded by one env kill switch. Rationale:

- It is already registered on `StopFailure` in all five config dirs; a new hook is a five-file
  settings edit, which is an operator `c10` step (`~/.claude/settings.json` is agent-forbidden).
- Measured cost of the existing hook, three runs in a sandboxed `STOP_FAILURE_MARKER_DIR`:
  **real 0.19 / 0.25 / 0.24 s** against a 10 s timeout. There is ~9.7 s of budget unused.
- Its cause-keyed collapsing (`:9-21`) is exactly right for *paging* and exactly wrong for
  *acting* — the request must be per-session. Both live happily in one file.

### 2b · The request protocol it writes

Writer today: `scripts/limit-recover/lr-fleet.sh:444-458`.

```bash
jq -n --arg sid "$sid" --arg target "$TARGET" \
      --arg pane "$([ "$pane" != "-" ] && printf '%s' "$pane")" \
      --arg by "${CLAUDE_CODE_SESSION_ID:-lr-fleet}" --arg ts "$(lf_now)" \
  '{sid:$sid, target:$target, source_pane:$pane, requested_by:$by, ts:$ts}' \
  > "$STATE/requests/$sid.json"
```

`STATE = ${LR_STATE_DIR:-$HOME/.reso/limit-recover}`. Consumer:
`scripts/limit-recover/lr-reset-poller.sh:639-661` — reads only `.sid`, `.target // "auto"`,
`.source_pane`, `.requested_by`, runs

```bash
"$FLEET" --one "$_rq_sid" --target "$_rq_target" ${_rq_pane:+--source-pane "$_rq_pane"} --from-daemon \
  > "$RESULTS/$_rq_sid.log" 2>&1
```

then writes `results/<sid>.json` = `{sid, rc, ts, log, requested_by}` and `rm -f`s the request.
**Extra keys are ignored** (four targeted `jq -r` reads, no schema check), so the schema is
forward-compatible — new fields cost nothing until a reader wants them.

`~/.reso/limit-recover/requests/` is **empty** right now; `results/` holds 5 pairs, newest
2026-09-14. The lane exists and has been exercised.

### 2c · The fields the hook can supply, and where each comes from

| field | source | cost |
|---|---|---|
| `sid` | payload `.session_id` | free |
| `cwd` | payload `.cwd` | free |
| `transcript_path` | payload `.transcript_path` | free |
| `error` | payload `.error` (`"rate_limit"`) | free |
| `last_assistant_message` | payload | free |
| `account` | `CLAUDE_CONFIG_DIR` → `accounts.json` lookup, already done at `stop-failure-marker.sh:82-89` | free |
| **`source_pane`** | `$KITTY_WINDOW_ID` — **verified present in the CC process env**: `ps eww -p 52095` ⇒ `KITTY_WINDOW_ID=112`, `ITERM_SESSION_ID=w0t0p0:112`, `KITTY_LISTEN_ON=unix:/tmp/kitty-73832`, `CLAUDE_CONFIG_DIR=/Users/chrisren/.claude-secondary`. Fallback: `grep -l '"session_id": "<sid>"' ~/.claude/cc-registry/*.json` (row shape `{paneUUID,name,cwd,account,pid,startedAt,session_id,surface,lstart}`) | free / one grep |
| **`tier`** | `lr_tier_from_transcript "$cfg" "$sid"` (`lr-lib.sh:34`) — measured **0.079 s** on the 3.4 MB `d02d8feb` transcript, returning `claude-fable-5-1 xhigh` | 79 ms |
| **`reset_at_epoch`, `rate_limit_type`** | `quotaLimits.resetsAt` / `.rateLimitType` from the tail (§1d), via the extended `lr_last_api_error` | ~10 ms (128 KB tail) |
| **`death_uuid`** | `lr_last_api_error` field 1 — the latch key | same read |
| `target` | `"auto"` — **do not rank here.** `lr-fleet --one --target auto` owns routing, and today's ranker defect (`claude-accounts --rank fable` put `next3` at weekly 11% first while the dry run chose `next` at weekly 98-99%) is a separate unit's problem. A hook that hard-codes a target inherits that bug at 0.2 s latency instead of 2.5 min. | free |

Total added latency ≈ **0.1 s**, taking the hook to ~0.35 s of a 10 s budget.

### 2d · The latch — event-keyed, never session-keyed

`e442434c` fired StopFailure three times in 16 seconds and a fourth 28 minutes later. Without a
latch that is four requests, and the fourth would fire *after* a successful transplant, re-targeting
a session that has already moved.

Use the pattern already proven twice in-tree:

- `recover-inject.sh` latches once per **death record uuid** (header, "THE LATCH"), with
  `lr_last_api_error`'s sha-digest fallback so it can never degrade to a constant key.
- `lr-reset-poller.sh` LR-i latches the `resumed/` marker on the **event** (reset timestamp), never
  the sid — `limit-reset-safety-gate.sh:65`: *"A session resumed once MUST re-park on its NEXT limit
  event … The naive sid-keyed skip is fatal for multi-day runs."*

So: `$STATE/requests-latch/<sid>.<death_uuid>` created with `set -C` (O_EXCL); already present ⇒
abstain with `log_idl passed "request-latched"`. A *new* death uuid in the same session writes a new
request, which is the correct behaviour for a session that hits its 5-hour cap twice in a day.

Second guard, cheap and independent: skip if `$STATE/locks/<sid>` or a `<sid>.HANDOFF.json` tombstone
already exists beside the transcript (both are written by `lr-transplant.sh` / `lr-handoff.sh`;
`d02d8feb.HANDOFF.json` and `d02d8feb.jsonl.handed-off` are on disk in `.claude-quaternary` now).

### 2e · Waking the driver in seconds, not 600

This is the other half, and without it the hook buys detection latency the system then throws away.

- `scripts/limit-recover/com.reso.lr-reset-poller.plist` has `StartInterval 600`, `RunAtLoad true`,
  and **no `WatchPaths`**. Installed copy at `~/Library/LaunchAgents/` differs only in XML
  formatting (verified by `diff`) — same keys, same values.
- `lr-reset-poller.sh:642` claims the driver *"writes a request here and kickstarts this job"*, but
  `grep -rn kickstart scripts/limit-recover/*.sh hooks/*.sh` finds exactly two hits, and the only one
  in `lr-fleet.sh` is at `:464` — an `echo` that **prints** the command for a human. **Nothing in the
  fleet auto-kickstarts the poller.** A request written today waits up to 600 s.

Two fixes, in preference order:

1. **`WatchPaths` = `/Users/chrisren/.reso/limit-recover/requests`** in both the SSOT plist and the
   installed one. launchd fires the job on the close of the write, typically <1 s. This is a launchd
   plist edit ⇒ an operator `c10` step under the build-vs-activation split
   (`limit-reset-safety-gate.sh:34-38`), and `scripts/launchd-parity-lint.sh` already asserts live ==
   SSOT so the pair cannot drift.
2. **In-hook `launchctl kickstart -k gui/$(id -u)/com.reso.lr-reset-poller`**, rate-limited by the
   same latch. This is a kick of an already-loaded job, not `load`/`unload`/autofire, so it does not
   touch the operator-owned activation surface — but it is agent-initiated launchctl and should be
   behind `CC_SF_REQUEST_KICK=${CC_SF_REQUEST_KICK:-0}` until the operator rules. Keep it as the
   fallback that makes the arm useful *before* the plist edit lands.

### 2f · Fault tolerance — the fire-and-forget hole today

`--one` reported `recycle-in-place/PARTIAL` for 4 of 5 sessions today, each with
`transplanted but the relaunch did not verify — source is a tombstoned husk`
(`~/.reso/limit-recover/fleet/one-20260919T17{2126,4403,4851,5207}Z/results.tsv`). The request lane
already produces the receipt that makes that visible: `results/<sid>.json` `{sid, rc, ts, log,
requested_by}` plus a full `results/<sid>.log`. What is missing is that **nobody reads it.** The
hook should therefore also write, beside the request, a `pending/<sid>.<death_uuid>` breadcrumb and
leave it to a reaper arm: a request whose `results/<sid>.json` has not appeared within N minutes, or
whose `rc != 0`, is a named fault with a sid, a pane and a log path — not a husk. This is the
difference the operator asked for, and it costs one `find -mmin` in an existing sweep.

### 2g · Sketch (≈35 added lines, appended to `hooks/stop-failure-marker.sh` after `:130`)

```bash
# ── ARM 2: a RECOVERY REQUEST (per-session), beside the cause-keyed marker (per-cause) ──────────
[ "${CC_SF_REQUEST:-on}" = off ] && exit 0
case "$ERR" in rate_limit|rate_limit_error) : ;; *) log_idl passed "req-not-a-cap"; exit 0 ;; esac

LRSTATE="${LR_STATE_DIR:-$HOME/.reso/limit-recover}"
. "$_RI_DIR/../scripts/limit-recover/lr-lib.sh" 2>/dev/null || { log_idl abstained "req-no-lrlib"; exit 0; }

# classification — §3
if agent_assignee_argv >/dev/null 2>&1 \
   || head -c 8000 "$TP" 2>/dev/null | grep -q '"agentName"'; then
  mkdir -p "$LRSTATE/teammate-skip"; : > "$LRSTATE/teammate-skip/$SID"
  log_idl passed "req-teammate-lead-owned"; exit 0
fi

IFS=$'\t' read -r DUUID _e KIND _ts RESET RLTYPE < <(lr_last_api_error "$TP") \
  || { log_idl abstained "req-no-api-error-tail"; exit 0; }
[ "$KIND" = limit ] || { log_idl passed "req-not-limit-kind"; exit 0; }

mkdir -p "$LRSTATE/requests" "$LRSTATE/requests-latch"
( set -C; : > "$LRSTATE/requests-latch/$SID.$DUUID" ) 2>/dev/null \
  || { log_idl passed "request-latched"; exit 0; }

PANE="${CC_PANE_ID:-${KITTY_WINDOW_ID:-${ITERM_SESSION_ID##*:}}}"
TIER="$(lr_tier_from_transcript "$CFG" "$SID" 2>/dev/null | tr ' ' '/' || true)"
OCLASS="$(oi_origin_class "$PANE" "$CWD" "$TP" 2>/dev/null || echo unknown)"

jq -n --arg sid "$SID" --arg target "auto" --arg pane "$PANE" \
      --arg by "stop-failure-marker" --arg ts "$(date -u +%FT%TZ)" \
      --arg acct "$ACCOUNT" --arg cwd "$CWD" --arg tier "$TIER" --arg tp "$TP" \
      --arg reset "$RESET" --arg rltype "$RLTYPE" --arg duuid "$DUUID" --arg oc "$OCLASS" \
  '{sid:$sid,target:$target,source_pane:$pane,requested_by:$by,ts:$ts,
    account:$acct,cwd:$cwd,tier:$tier,transcript_path:$tp,
    reset_at_epoch:$reset,rate_limit_type:$rltype,death_uuid:$duuid,origin_class:$oc}' \
  > "$LRSTATE/requests/$SID.json" 2>/dev/null || { log_idl abstained "req-write-failed"; exit 0; }

[ "${CC_SF_REQUEST_KICK:-0}" = 1 ] \
  && launchctl kickstart -k "gui/$(id -u)/com.reso.lr-reset-poller" >/dev/null 2>&1
log_idl fired "request-written"
exit 0
```

Every path exits 0 and prints nothing on stdout — the file's existing fail-open contract
(`stop-failure-marker.sh:31-33`), which matters doubly here because a `StopFailure` hook that emits
a stray byte on the death path could be read by a Stop-family consumer as a directive.

**Red-provable acceptance rows**, registered in the style of `limit-reset-safety-gate.sh`:

| | criterion |
|---|---|
| SF-a | a `rate_limit` StopFailure payload with a reset-bearing tail ⇒ exactly one `requests/<sid>.json` carrying sid, pane, account, tier, cwd, `reset_at_epoch`, `death_uuid` |
| SF-b | N further StopFailures on the SAME death uuid ⇒ still exactly one request (latch) |
| SF-c | a NEW death uuid in the same session ⇒ a second request (event-keyed, not sid-keyed — LR-i) |
| SF-d | `error:"authentication_failed"` ⇒ marker written, **no** request (a login cliff has no reset and a different recovery mode) |
| SF-e | a transcript whose head-8k carries `agentName` ⇒ no request, `teammate-skip/<sid>` created |
| SF-f | the limit-recover **skill_listing** text present with no `isApiErrorMessage` envelope ⇒ no request (LR-o, the 2026-07-25 false-positive class; the attachment is at line 29 of today's `d02d8feb` transcript) |
| SF-g | `CC_SF_REQUEST=off` ⇒ marker unchanged, zero request writes |
| SF-h | request-dir unwritable ⇒ abstain logged to IDL, exit 0, marker still written |

---

## 3 · What must stop it firing on a fired peer or a teammate, and how it should classify

### 3a · Why the poller skips teammates, and how it decides

`lr-reset-poller.sh:748-758`:

```bash
# teammate sessions (implicit-team assignees carry "agentName" on their early
# records; leads never do) are recovered by their LEAD via the team-aware
# lr-audit — a bare --resume here would detach them from team semantics
# (inbox/agentName wiring) and duplicate the lead's respawn.
if head -c 8000 "$tx" 2>/dev/null | grep '"agentName"' >/dev/null; then
  ... : > "$STATE/teammate-skip/$sid"; log "SKIP  $sid — teammate session (lead-owned recovery)"
  continue
fi
```

The same test guards the monthly-spend branch at `:718-722`, and LR-n registers it as a proof
obligation (`limit-reset-safety-gate.sh:70`).

### 3b · The three classes a `StopFailure` hook must separate

| class | in-hook oracle | verdict |
|---|---|---|
| **Agent-Teams assignee (teammate)** | `hooks/lib/agent-identity.sh` → `agent_assignee_argv()` — a **three-flag conjunction** (`--agent-id <n>@session-<t>` ∧ `--agent-name` ∧ `--team-name`) over the hook's own process **ancestry**, not a machine-wide `pgrep`. Its header states why: argv carries whole briefs, so any single flag matches every session that merely mentions it (`agent-identity.sh:24-31`; MEMORY `pgrep-f-matches-agent-briefs`). Backstop: the poller's `head -c 8000 \| grep '"agentName"'` on the payload's `transcript_path`. | **No request.** Write `teammate-skip/<sid>` and let the lead own it — an unattached `--resume` detaches the inbox/agentName wiring and duplicates the lead's respawn. |
| **Fired peer (dispatched session)** | `hooks/lib/origin-identity.sh` → `oi_origin_class "$pane" "$cwd" "$transcript_path"` ⇒ `origin` \| `fired-peer`. Stamp store `~/.claude/cc-fired/<pane>.json`; **485 integer-named stamps exist**, so kitty's integer pane ids are the live key, and a `by-cwd/` index is present for the renumber case (`origin-identity.sh:68-135`). Panes 111/112/114/117/121 have **no stamp** ⇒ all five of today's were `origin`. | **Write the request**, and stamp `origin_class:"fired-peer"`. A recycle-in-place is exactly what preserves its pane, worktree and `--notify-back` custody; killing it would strand a `cc-custody` debt. What changes is the *reporting*: on `rc != 0` the originator must be paged, not the pane. |
| **Foreground in-process subagent** | `isSidechain` on its records; it has no separate CC process and fires `SubagentStop`, for which **nothing is registered** (`agent-identity.sh:16-17`; `jq '.hooks.SubagentStop' ~/.claude/settings.json` ⇒ `null`). | Unreachable — the parent's `StopFailure` is the only event, and a request for the parent is the right action. |

### 3c · Measured today: 0 of 10 marker sids were teammates

```
10 distinct sids across ~/.claude/autonomy/stop-failure/{rate_limit__next4,authentication_failed__.claude}.jsonl
"agentName" in first 8 KB   : 0/10
"isSidechain":true in 8 KB  : 0/10
```

So the teammate branch has **never been exercised on this event**. State it as unmeasured rather
than as safe: whether `StopFailure` fires at all inside an assignee session is not established by
this population, and SF-e above is the fixture that must establish it.

### 3d · Three further ways this arm can fire wrongly, each with its guard

1. **No `error` field.** `stop-failure-marker.sh:79` already abstains
   (`[ -n "$ERR" ] || _sf_abstain "no-error-field"`); the request arm must additionally require the
   error to be a cap, not any failure — a `server_error` StopFailure has the *byte-identical envelope*
   (`docs/plans/NONLIMIT_RESUME_LADDER.md:192-195`) and a transplant is the wrong cure for it.
2. **Text without an envelope.** The `/limit-recover` skill description quotes
   `"You've hit your session limit"` verbatim and ships in **every** session's `skill_listing`
   attachment — it is line 29 of today's `d02d8feb` transcript. This minted two false class-B packets
   on 2026-07-25 (`limit-reset-safety-gate.sh:71`, LR-o). The arm is safe by construction only
   because it keys on the payload's `.error` and on `lr_last_api_error`'s envelope gate, never on text.
3. **A session already moved.** A limit re-fires *after* a transplant when a queued
   task-notification runs a turn on the dead account (measured: `09e64dcb` at 17:11:29Z, ten minutes
   after its first). The `HANDOFF.json` tombstone / `locks/<sid>` check in §2d is what stops a request
   being written against a session whose successor is already running.

---

## 4 · What I could not measure

- Whether `Notification { matcher: idle_prompt }` fires on a limit-parked composer. The only
  registered consumer is inert and logs nothing (§1b). A one-line logging arm on `push-critical.sh`
  would settle it; without that the surface is unfalsifiable.
- Whether `StopFailure` fires inside an Agent-Teams assignee session (§3c) — no instance in the
  17-row marker population.
- Whether `quotaLimits` is present on a **weekly** or **Fable-scoped** cap. All five of today's
  records were `rateLimitType:"five_hour"`. LR-blind (`limit-reset-safety-gate.sh:118-121`) stays
  open until one is captured, though `rateLimitType` is the field most likely to close it.
- I did not run `bats tests/lr-reset-poller.bats` (read-only unit; a bats run holds a concurrency
  slot and the gate's own rc-75 deferral path makes an unattended run a non-verdict).
