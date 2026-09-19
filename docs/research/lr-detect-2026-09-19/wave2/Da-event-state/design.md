# Da — EVENT-SOURCED STATE: one per-session document, born at the instant of death, transitioned by every later actor; the census is a directory read

Designer key: `Da-event-state` · written 2026-09-19T21:15Z–21:45Z · repo `claude-infrastructure` @ `226b73888` · read-only unit · every number below is either `cmd => output` measured this session or cites a research unit / refutation entry by name. UNMEASURED is written where it applies.

## 0. The anchor in one sentence, and what it buys

`hooks/stop-failure-marker.sh` already runs within ~1 s of every cap death (IDL join 126/128 records, p50 0 s, p95 1 s — digest P1) and today writes ONE cause-keyed line that nothing consumes. Arm 2 makes that same hook write ONE per-session document — `~/.reso/limit-recover/state/<sid>.json` — carrying the six facts every downstream actor re-derives today at ~1 s/hit of python+jq forks (sid · pane · account · cap class · reset epoch · death uuid), and every later actor (transplant, fleet, poller, reaper, ack) TRANSITIONS that document instead of re-scanning 2,591 transcripts. The census becomes `read the directory (1.0 ms/40 docs) + one ps (29.6 ms) + kill -0 (0.12 ms/40)` — measured, § 11.4 — so "which sessions need limit recovery, right now, per account, with pane ids" is answered in ≤ 0.09 s with no screenshot and no transcript opened.

What the anchor does NOT claim: the document is not the truth about liveness or engagement. Those are derived at READ time from stores that already exist (registry + ps, beats) and are never stored — § 4.3. A document can only lie about the past; the overlays keep it honest about the present.

## 1. The measured premises this design stands on (receipts)

| # | premise | receipt |
|---|---|---|
| 1 | The hook is registered on StopFailure in all 5 config dirs ⇒ arm 2 needs NO settings edit (no c10) | `jq '.hooks.StopFailure[]…command' <5 dirs>` => `~/.claude/hooks/stop-failure-marker.sh` ×5 (this session); `hooks/config-mirror-assert.sh:54-60` asserts the registration |
| 2 | The hook and every lr-* script are SYMLINK class — live on save | `readlink ~/.claude/hooks/stop-failure-marker.sh` => `…/claude-infrastructure/hooks/stop-failure-marker.sh`; same for session-beat.sh, lr-fleet.sh, lr-lib.sh, lr-reset-poller.sh, lr-transplant.sh, bin/cc-notify. `~/.claude/statusline.sh` => COPY |
| 3 | The hook's cost today, sandboxed (`STOP_FAILURE_MARKER_DIR`/`STOP_FAILURE_IDL` pointed at my bench dir) | `/usr/bin/time -p bash hooks/stop-failure-marker.sh < payload.json` ×3 => `real 0.14 / 0.10 / 0.09` against a 10 s timeout |
| 4 | `KITTY_WINDOW_ID` / `ITERM_SESSION_ID` / `CLAUDE_CONFIG_DIR` are in the hook's inherited env and unread | U07 §3b (`ps eww -p 89760`); `grep -n 'KITTY_WINDOW_ID' hooks/stop-failure-marker.sh` => no output |
| 5 | The death record carries `quotaLimits.{resetsAt,rateLimitType}` on the five_hour/seven_day caps and NOTHING structured for the Fable cap | verbatim, this session: `~/.claude-tertiary/projects/…/09e64dcb-….jsonl:1934` => `{"uuid":"fcf01ffb-687e-…","error":"rate_limit","apiErrorStatus":429,"quotaLimits":{"resetsAt":1789853400,"rateLimitType":"five_hour",…},"version":"2.1.260"}`; `~/.claude-quaternary/projects/…/2d71c6d8-….jsonl:1252` => `quotaLimits` ABSENT, `errorDetails` present, text `You've reached your Fable limit. Run /usage-credits to continue or switch models with /model.` |
| 6 | Markers re-fire per retry and are undeduped | `jq -r '[.ts,.session_id[0:8],…]' rate_limit__next3/next4.jsonl \| sort` => 26 rows, 14 distinct sids (11569d45 ×3, e442434c ×4, 28f07827 ×4, 09e64dcb ×2, 65186f1f ×2, 98f02458 ×2) |
| 7 | The registry is a 32 ms resolver but cannot ENUMERATE: 5 of today's 14 marker sids have no row | python join this session => `marker sids 14 · with registry row 9 · with lock 12`; rowless = 28f07827, e442434c, 98f02458, 4bc1159f, 26cd14be |
| 8 | Stop never fires on a limit turn ⇒ `kind:"prompt"` freezes ⇒ `cc_sp_active` counts the corpse | `scripts/lib/spawn-presence.sh:319` selects `.kind == "prompt"`; live `~/.claude/cc-beats/07e30aeb-….json` => `"kind":"prompt","t":1789851164` on a pane whose last record is the cap; digest P4 A/B: 10 → 7 |
| 9 | `session-beat.sh` accepts the kind as `$1`, derives `who` only for `prompt`, carries `operatorT`/`seq` forward | `hooks/session-beat.sh:58, 62, 98-108, 124` |
| 10 | The poller's request lane exists, drains, and is kickstarted by nothing | `ls ~/.reso/limit-recover/requests/` => empty; `results/` newest 2026-09-14; `grep -n kickstart lr-fleet.sh lr-reset-poller.sh` => `lr-fleet.sh:534` (an `echo` for a human), `lr-reset-poller.sh:642` (a comment). The digest cites `:464`; the file has grown — it is `:534` today |
| 11 | Poller job health and plist shape | `launchctl print gui/501/com.reso.lr-reset-poller` => `runs = 416 · last exit code = 0 · run interval = 600 seconds · PATH => /usr/bin:/bin:/usr/sbin:/sbin`; `plutil -p scripts/limit-recover/com.reso.lr-reset-poller.plist` => keys {EnvironmentVariables, Label, ProgramArguments, RunAtLoad, StandardErrorPath, StandardOutPath, StartInterval} — no WatchPaths, no QueueDirectories, no ThrottleInterval |
| 12 | `~/.claude-secondary` EXISTS — the digest R7 sentence "next2 -> ~/.claude-secondary row points at a directory that does not exist" does NOT reproduce | `ls -d ~/.claude-secondary ~/.claude-secondary/projects` => both exist; `jq '.accounts[]\|select(.name=="next2")\|.config_dir'` => `~/.claude-secondary`. The ONLY accounts.json defect is the absent `~/.claude` row (`stop-failure-marker.sh:82-89` then names the account `.claude`; `authentication_failed__.claude.jsonl` is on disk) |
| 13 | The `poller.launchd.err` defect named in the brief is STALE | mtime `Sep 15 19:48`; `bash -n ~/.claude/lib/account-map.generated.sh` => SYNTAX-OK; today's 7 `parked/*.json` carry `acct:"next3"` so `acct_of_cfg` resolved. The unguarded `break` at `lr-reset-poller.sh:293-296` is still a latent fault — fixed in § 7.4 |
| 14 | The prototype, re-run at 21:15Z | `python3 cc-limited-proto.py` => 0.050 s wall / 0.021 s self-timed; `next3: 7 blocked` (6 MOVED, 1 TRANSPLANTED), `next4: 6 blocked` (4 MOVED, 2 RESET-PASSED/NO-PANE), `1 dropped as re-engaged/gone` — that drop is 07e30aeb, the row digest P5 names |
| 15 | Micro-costs for the census budget | bench (this session, one python process): `read40=1.0ms kill0x40=0.12ms ps=29.6ms lines=1326`; `time jq -cn '{a:1}'` => 0.003 s |
| 16 | Legacy population for backfill | `~/.claude/autonomy/idl.jsonl` => 90,236 rows, 33 `stop-failure-marker`; 8 gz archives 2026-09-09..09-17 => 571 `stop-failure-marker` rows via `gunzip -c`; 48 `*.jsonl.handed-off` carcasses across the stores |
| 17 | Registry liveness with the lstart pin, now | 31 rows, `13 LIVE` by (pid ∈ ps ∧ lstart equal); pane→sid8 for today's marker sids: 111→09e64dcb, 127→11569d45, 121→65186f1f, 149→8843bcf3, 147→07e30aeb (all LIVE), 112→d02d8feb, 117→cb227486, 143→fff83638, 145→0e2567ee (all dead) |

## 2. The store

`${LR_STATE_DIR:-$HOME/.reso/limit-recover}/state/<sid>.json` — one document per sid, **replace-on-write via tmp + `mv`**, **born with O_EXCL** (`set -C`), never appended.

Why this directory and not `~/.claude/autonomy/`: every store the recovery chain already owns lives under `LR_STATE_DIR` (`parked/ locks/ requests/ results/ resumed/ teammate-skip/ fire-fail/ fire-claims/` — `ls ~/.reso/limit-recover/` this session), and every lr-* bats suite already fixtures that seam (`tests/lr-fleet.bats:11 export LR_STATE_DIR`). It sits outside every config dir, so a transplant that renames the transcript under one config dir and copies it under another (`lr-transplant.sh:74, 99`) can never move or orphan the document. The sid is globally unique and account-independent (digest R3: one sid carried markers under two accounts), which is exactly why the document, not the account, is the key.

Why one document and not a per-sid event log: the reader must be a directory read with no reduce step. Events are kept INSIDE the document as a bounded array (`events[]`, cap 32, § 3) so the audit trail survives without the census folding N lines per sid — the `wc -l` over-count digest P1 measured (22/42 sessions re-fire, up to 30 rows, one gap of 2 h 52 m) is precisely the fold this avoids.

Why the marker file stays untouched: `rate_limit__<acct>.jsonl` remains the append-only EVENT LOG (its burst clustering IS the "many sessions, one account" answer — digest P5 fix) and the page/alarm path keeps reading it. The document is STATE; the marker is HISTORY. Nothing in the existing hook above `:130` changes, so every property `tests/stop-failure-marker.bats` pins (collapse, concurrency, silence, not-a-pager) is preserved by construction.

## 3. Document schema v1 (field · provenance · mutability)

```json
{
  "v": 1,
  "sid": "09e64dcb-16c7-4c65-8b11-fd854d50f299",
  "state": "LIMITED",
  "since": "2026-09-19T19:53:38Z",
  "death": {
    "ts": "2026-09-19T19:53:38.683Z",
    "uuid": "fcf01ffb-687e-453d-8161-68b35bb2d3a1",
    "error": "rate_limit",
    "cap": "five_hour",
    "reset_epoch": 1789853400,
    "reset_source": "quotaLimits",
    "recoverable_by_waiting": true,
    "text": "You've hit your session limit · resets 4:30pm (America/Chicago)",
    "cli_version": "2.1.260"
  },
  "origin": {
    "account": "next3",
    "config_dir": "/Users/chrisren/.claude-tertiary",
    "cwd": "/Users/chrisren/Development/claude-infrastructure",
    "transcript_path": "/Users/chrisren/.claude-tertiary/projects/-Users-chrisren-Development-claude-infrastructure/09e64dcb-16c7-4c65-8b11-fd854d50f299.jsonl",
    "pane": "111",
    "pid": 37018,
    "lstart": "Sat Sep 19 19:32:08 2026",
    "origin_class": "origin",
    "teammate": false,
    "entrypoint": "cli",
    "tier": null
  },
  "current": {
    "account": "next3",
    "config_dir": "/Users/chrisren/.claude-tertiary",
    "transcript_path": "/Users/chrisren/.claude-tertiary/projects/-Users-chrisren-Development-claude-infrastructure/09e64dcb-16c7-4c65-8b11-fd854d50f299.jsonl"
  },
  "claim": null,
  "events": [
    {"ts": "2026-09-19T19:53:38Z", "actor": "stop-failure-marker", "from": null, "to": "LIMITED", "note": "death fcf01ffb"}
  ]
}
```

| field | provenance | mutable by |
|---|---|---|
| `sid` | payload `.session_id` (`stop-failure-marker.sh:70`) | never |
| `state`, `since` | the last transition | any writer, only via `lr-state transition` (§ 7.5) |
| `death.*` | ONE read of the transcript tail through the SSOT predicate (§ 10): `uuid` = the record's uuid, else `lr_last_api_error`'s sha fallback (`lr-lib.sh:150-151` — never a constant); `cap` ∈ {five_hour, seven_day, fable, monthly_spend, unknown}; `reset_epoch` = `quotaLimits.resetsAt` (an epoch, 408/408 agree with the prose — digest P3), else the prose reset parsed in the NAMED zone, else null; `recoverable_by_waiting` = `reset_epoch != null` — fable and monthly_spend carry no reset anywhere in the record, so they must route to /model or to the operator, never be parked forever | replaced wholesale on a NEW death uuid (re-cap); never edited otherwise |
| `origin.account` | `CLAUDE_CONFIG_DIR` → `accounts.json`, the hook's own resolution at `:82-89` — the ONLY per-death account evidence (digest R7) | never |
| `origin.pane` | `${CC_PANE_ID:-${KITTY_WINDOW_ID:-${ITERM_SESSION_ID##*:}}}` from the hook's inherited env — the ONE field the payload lacks (digest R0) | never |
| `origin.pid`, `origin.lstart` | the claude ancestor walked from `$PPID` exactly as `hooks/session-beat.sh:80-88` does, rendered `TZ=UTC LC_ALL=C ps -o lstart=`; identity is (pid, lstart), never pid — `cc-registry/580.json.stale-1787629385` (digest R6) is a 617-h-old row whose pid now belongs to a Cursor helper and still passes `kill -0` | never |
| `origin.origin_class` | `oi_origin_class "$pane" "$cwd" "$tp"` (`hooks/lib/origin-identity.sh:237`) ⇒ origin \| fired-peer; `unknown` on any error | never |
| `origin.teammate` | `agent_assignee_argv` (`hooks/lib/agent-identity.sh:33`, the three-flag conjunction over ancestry) OR `head -c 8000 "$tp" \| grep -q '"agentName"'` (the poller's own test, `lr-reset-poller.sh:751`) | never |
| `origin.entrypoint` | the death record's `entrypoint` (`cli` \| `sdk-cli`) — recorded so the census can SAY why a `-p` death has no pane instead of guessing (digest P1: `sdk-cli` deaths emit no StopFailure, so this is populated only by backfill, § 14) | never |
| `origin.tier` | **null at birth** — `lr_tier_from_transcript` is 79 ms of python (U10 §2c) and only a recovery actor needs it; the first actor that computes it writes it back with `lr-state set-tier` | first recovery actor |
| `current.*` | = origin at birth; rewritten by TRANSPLANTED (§ 7.1) to the successor's config dir and transcript path. `current.transcript_path` is the ONLY path any reader may open — the marker's `transcript_path` is a snapshot that dies on transplant (16/31 rows stale, all with a `.handed-off` sibling, digest R2) | lr-transplant, lr-state |
| `claim` | `{actor, run, ts, deadline, log}` while a recovery is in flight; null otherwise | lr-fleet, poller, reaper |
| `events[]` | appended per transition, oldest dropped past 32 | every writer |

Everything the census renders is either a field above or an OVERLAY computed at read (§ 4.3). A reader never renders a marker field verbatim (the digest's R-mandate): once the document exists the census does not open the marker at all.

## 4. The state machine

### 4.1 States

| state | meaning | terminal? |
|---|---|---|
| `LIMITED` | died on a cap; no recovery claimed; successor unknown | no |
| `REQUESTED` | `requests/<sid>.json` exists (written by `lr-fleet --enqueue` or by hand) — awaiting the poller's drain | no |
| `RECOVERING` | an actor holds a claim with a deadline (`claim` non-null) | no |
| `TRANSPLANTED` | `locks/<sid>.lock` written and the successor transcript exists under `current.config_dir`; the successor still CARRIES the death record until it takes a turn (digest P5: a transplant copies the death record forward) | no — non-terminal by construction |
| `RECOVERED` | a real assistant turn AFTER `death.ts` on the current copy (engaged) | yes (GC after grace) |
| `RESET_PASSED` | `reset_epoch <= now`, not recovered, not claimed — the poller's spawn-at-reset domain | no |
| `FAULT` | a claim expired with no live successor process and no engagement — NAMED (sid · pane · log path); or a poller LISTED write-off | yes, until `lr-state ack` |
| `CLOSED` | origin process dead, no successor, no claim, and (reset passed ≥ 1 h OR cwd gone) — nothing in-place to recover | yes (GC after grace) |

### 4.2 Transitions (who writes, on what evidence, at which line)

| from → to | actor | evidence / insertion point |
|---|---|---|
| ∅ → LIMITED | `stop-failure-marker.sh` arm 2 | payload `error == rate_limit` ∧ the predicate's tail read; § 5 |
| any → LIMITED (re-cap) | same | a NEW `death.uuid` (event-keyed latch, LR-i: `limit-reset-safety-gate.sh:65`); `death.*` replaced, `events[]` keeps the prior state |
| LIMITED → REQUESTED | `lr-fleet.sh:514-528` enqueue | `requests/<sid>.json` written |
| LIMITED / REQUESTED / RESET_PASSED → RECOVERING | `lr-fleet.sh:380 lf_one` (before `lf_capacity_wait` at `:390`) · poller NUDGE `:928` / SPAWN `:966` | claim = {actor, run, deadline}: lr-fleet `now + LR_FLEET_CAP_WAIT_S(600) + 300`; poller `now + CLAIM_TTL_MIN + LR_ENGAGE_SETTLE_MIN(3) min` |
| RECOVERING → TRANSPLANTED | `lr-transplant.sh` after the tombstone at `:93-95` | `locks/<sid>.lock` + `<sid>.HANDOFF.json`; `current` ← `{to, target_transcript}` |
| TRANSPLANTED / RECOVERING → RECOVERED | (a) lr-fleet on rc 0 (`lf_one`'s RECOVERED verdict is engagement-proven: a fresh non-error turn in the target's copy, `commands/limit-recover.md:404+`) · (b) the poller's engagement audit `:298-373` reading ENGAGED · (c) the census overlay (beat `kind:"stop"` with `t > death.ts`, § 4.3), persisted with `--by census-overlay` | |
| RECOVERING → FAULT | lr-fleet rc 4 (`lr-fleet.sh:336-338` PARTIAL "tombstoned husk") · poller `NOT-ENGAGED` at `:373` · the reaper (§ 8) | `claim.log` names the stderr / results log |
| RESET_PASSED → FAULT (write-off) | poller `LISTED` at `:958-959` (the `MAX_PER_WT=1` retirement U06 §3 calls a silent write-off of two of five) | note "consolidated; resume by sid" — visible, never silent |
| LIMITED → RESET_PASSED | the poller tick persists the overlay `reset_epoch <= now` | |
| LIMITED / RESET_PASSED → CLOSED | reaper/GC (§ 9) | origin (pid, lstart) dead ∧ no successor ∧ (reset passed ≥ 1 h ∨ `!isdir(cwd)`) |
| FAULT → CLOSED | `lr-state ack <sid> --why …` (agent or operator) | the only exit from FAULT |

### 4.3 Overlays — derived at read, NEVER stored

| overlay | source | cost |
|---|---|---|
| `alive` | `origin.pid` ∈ one `TZ=UTC LC_ALL=C ps -eo pid=,lstart=` ∧ lstart equal after whitespace normalisation | 29.6 ms, once per census |
| `pane_owner` | `~/.claude/cc-registry/<origin.pane>.json` → `.session_id == sid` ⇒ IN-PLACE; `!= sid` ⇒ PANE-REUSED (98f02458's shape); file absent ⇒ UNADDRESSABLE-NOW | ~1 ms for all 31 rows |
| `moved` | any registry row with `session_id == sid` ∧ `account != origin.account` (both spellings normalised through accounts.json: `claude-tertiary` ↔ `next3`) ∧ `startedAt > death.ts` ⇒ MOVED (digest R5: registry.startedAt lands ~1 min after the `.handed-off` rename and always after the marker) | same read |
| `engaged` | beat `~/.claude/cc-beats/<sid>.json`: `kind=="stop" ∧ t > death.ts` ⇒ engaged · `kind=="limited"` ⇒ still dead · `kind=="prompt" ∧ t > death.ts` ⇒ a turn STARTED after death (it will either re-cap — a new StopFailure — or engage; render `ENGAGING?`) | 0.1 ms per named sid |
| `reset_in` | `death.reset_epoch − now` (null for fable / monthly_spend) | 0 |
| `cwd_ok` | `isdir(origin.cwd)` at read (digest R6: cwd DECAYS under the worktree reaper mid-census) | 0.01 ms |
| `title` | last `"aiTitle"` in the 128 KB tail of `current.transcript_path` (P10 R3: within 33,389 B of EOF, 30/30) — ONLY under `--titles` / `--verify`, the one overlay that opens a transcript | 0.2 ms/file |

The rendered DISPOSITION is a pure function of (state, overlays): `RECOVERABLE` = LIMITED ∧ alive ∧ pane_owner == IN-PLACE ∧ ¬moved ∧ ¬engaged · `NO-PANE` = LIMITED ∧ ¬alive ∧ pane absent/reused · `MOVED` = moved ∨ (TRANSPLANTED ∧ successor alive) — rendered as a tally line, never a row (the 38% pure-noise rows digest P5 scored the prototype for) · `TRANSPLANTED-BLOCKED` = TRANSPLANTED ∧ successor's beat still `limited` ∧ no successor pane (98f02458, which the prototype hid as MOVED) · `UNADDRESSABLE` = no registry row ever (report by sid + cwd; never queue for in-place recovery) · `TEAMMATE` = `origin.teammate` · `HEADLESS` = `entrypoint == sdk-cli` · `FAULT`, `RESET-PASSED`, `CLOSED` as stated.

### 4.4 The latch

Keyed on `death.uuid`, never on sid. Arm 2 creates `state/<sid>.json` under O_EXCL; if the document exists and `death.uuid` equals the new record's uuid ⇒ `log_idl passed "state-latched"` and nothing is written (this collapses e442434c's 3 fires in 16 s and the 30-record session of digest P1); if it differs ⇒ a genuine second cap in the same session (the multi-day case LR-i exists for) ⇒ `death` replaced, event pushed, state ← LIMITED, claim ← null. A document in FAULT is NOT overwritten by a re-cap — the fault stays named and the re-cap is appended as an event: a husk that re-caps is still a husk.

## 5. Writer 1 — arm 2 in `hooks/stop-failure-marker.sh`

### 5.1 Insertion point and contract

After the marker append at `:122-128` and `log_idl fired` at `:130`, before `exit 0` at `:131`. Everything above `:130` is byte-identical. The arm inherits the file's fail-open contract (`:31-33`): no `set -e`, every write `|| true`, exit 0 always, stdout empty always — this is Stop-family, and a stray byte on the death path can be read as a directive. Kill switch `CC_SF_STATE=off`. Test seams: `LR_STATE_DIR`, `CC_BEAT_DIR`, `CC_SF_KICK=0`, `LR_LIB` (path to lr-lib.sh).

### 5.2 The arm (≈45 lines; a sketch — the shipped form must pass § 16)

```bash
# ── ARM 2 (Da): the per-session STATE document — beside the per-cause marker, never instead of it ──
[ "${CC_SF_STATE:-on}" = off ] && exit 0
case "$ERR" in rate_limit|rate_limit_error) : ;; *) log_idl passed "state-not-a-cap"; exit 0 ;; esac
SDIR="${LR_STATE_DIR:-$HOME/.reso/limit-recover}/state"
mkdir -p "$SDIR" 2>/dev/null || { log_idl abstained "state-dir-unwritable"; exit 0; }
_lrlib="${LR_LIB:-$(dirname "$_sflib")/../../scripts/limit-recover/lr-lib.sh}"   # same ladder as :47-52
[ -r "$_lrlib" ] || _lrlib="$HOME/.claude/scripts/limit-recover/lr-lib.sh"
. "$_lrlib" 2>/dev/null || { log_idl abstained "state-no-lrlib"; exit 0; }
# ONE tail read through the SSOT: uuid · error · kind · ts · cap · reset_epoch · reset_source · entrypoint
IFS=$'\t' read -r DUUID _e _k DTS CAP RESET RSRC ENTRY < <(lr_last_api_error "$TP" 2>/dev/null) \
  || { DUUID="sha-$(printf '%s' "$SID$LAST" | shasum -a 256 | cut -c1-24)"; DTS="?"; CAP=unknown; RESET=""; RSRC=none; ENTRY="?"; }
PANE="${CC_PANE_ID:-${KITTY_WINDOW_ID:-${ITERM_SESSION_ID##*:}}}"
walk="$PPID"; CPID=""; i=0                       # claude ancestor — the idiom of hooks/session-beat.sh:80-88
while [ -n "$walk" ] && [ "$walk" -gt 1 ] 2>/dev/null && [ "$i" -lt 12 ]; do
  c=$(ps -o comm= -p "$walk" 2>/dev/null); c="${c##*/}"
  case "$c" in claude|claude.exe|claude-*) CPID="$walk"; break ;; esac
  walk=$(ps -o ppid= -p "$walk" 2>/dev/null | tr -d ' '); i=$((i + 1))
done
[ -n "$CPID" ] || CPID="$PPID"
LSTART="$(TZ=UTC LC_ALL=C ps -o lstart= -p "$CPID" 2>/dev/null | tr -s ' ' | sed 's/^ *//;s/ *$//')"
TEAM=false; { agent_assignee_argv >/dev/null 2>&1 || head -c 8000 "$TP" 2>/dev/null | grep -q '"agentName"'; } && TEAM=true
OCLASS="$(oi_origin_class "$PANE" "$CWD" "$TP" 2>/dev/null || echo unknown)"
DOC="$SDIR/$SID.json"; NOWZ="$(date -u +%FT%TZ)"
if [ -f "$DOC" ] && [ "$(jq -r '.death.uuid // ""' "$DOC" 2>/dev/null)" = "$DUUID" ]; then
  log_idl passed "state-latched"; exit 0         # the SAME death re-firing (3 in 16 s) — nothing to add
fi
prior='{}'; [ -f "$DOC" ] && prior="$(jq -c . "$DOC" 2>/dev/null || echo '{}')"
jq -cn --argjson prior "$prior" --arg sid "$SID" --arg now "$NOWZ" --arg dts "$DTS" --arg duuid "$DUUID" \
   --arg err "$ERR" --arg cap "$CAP" --arg reset "$RESET" --arg rsrc "$RSRC" \
   --arg last "$(printf '%s' "$LAST" | cut -c1-200)" --arg acct "$ACCOUNT" --arg cfg "$CFG" --arg cwd "$CWD" \
   --arg tp "$TP" --arg pane "$PANE" --arg lstart "$LSTART" --arg oc "$OCLASS" --argjson team "$TEAM" \
   --arg entry "$ENTRY" --argjson pid "$CPID" '
  {v:1, sid:$sid,
   state:(if ($prior.state // "") == "FAULT" then "FAULT" else "LIMITED" end), since:$now,
   death:{ts:$dts, uuid:$duuid, error:$err, cap:$cap,
          reset_epoch:(if $reset=="" then null else ($reset|tonumber) end), reset_source:$rsrc,
          recoverable_by_waiting:($reset!=""), text:$last},
   origin:($prior.origin // {account:$acct, config_dir:$cfg, cwd:$cwd, transcript_path:$tp, pane:$pane,
           pid:$pid, lstart:$lstart, origin_class:$oc, teammate:$team, entrypoint:$entry, tier:null}),
   current:($prior.current // {account:$acct, config_dir:$cfg, transcript_path:$tp}),
   claim:null,
   events:((($prior.events // []) + [{ts:$now, actor:"stop-failure-marker", from:($prior.state // null),
            to:"LIMITED", note:("death " + $duuid[0:8])}]) | .[-32:])}' > "$DOC.$$.tmp" 2>/dev/null \
  && mv -f "$DOC.$$.tmp" "$DOC" 2>/dev/null \
  || { rm -f "$DOC.$$.tmp" 2>/dev/null; log_idl abstained "state-write-failed"; exit 0; }
# the beat — kind:"limited" — is what un-phantoms cc_sp_active (§ 6); it self-backgrounds under 3 s
_sf_beat="$(dirname "$_sflib")/../session-beat.sh"; [ -x "$_sf_beat" ] || _sf_beat="$HOME/.claude/hooks/session-beat.sh"
printf '%s' "$input" | bash "$_sf_beat" limited >/dev/null 2>&1 || true
# the trigger lr-reset-poller.sh:642 documents and nothing implements — bare kickstart, absolute path, never -k
if [ "${CC_SF_KICK:-1}" = 1 ] && [ "$TEAM" = false ]; then
  /bin/launchctl kickstart "gui/$(id -u)/com.reso.lr-reset-poller" >/dev/null 2>&1 || true
fi
log_idl fired "state-$([ "$prior" = '{}' ] && echo born || echo recap)" \
  "$(jq -cn --arg p "$PANE" --arg c "$CAP" --arg a "$ACCOUNT" '{pane:$p,cap:$c,account:$a}')"
exit 0
```

Four properties, each a test in § 16: (a) a FAULT document survives a re-cap (state stays FAULT, `death` replaced, event appended); (b) `origin.*` is written ONCE — a re-cap after a transplant keeps the birth origin and the transplant's `current`; (c) `authentication_failed` writes the marker and NO document (a login cliff has no reset and a different cure — U10 SF-d); (d) the arm runs only after the marker append, so a document can never exist without its marker line — the marker stays the audit of record. The IDL `extra` object on the fired row carries pane/cap/account so `operator-readout.sh`'s pull surface can render the birth without opening the document.

### 5.3 Cost

hook baseline 0.09–0.14 s (§ 1 #3) + one python start inside `lr_last_api_error` (~0.03 s — the proto's 0.050 s wall vs 0.021 s self-timed is the interpreter) + ≤ 4 `ps` (~5 ms each) + 3 `jq` (3 ms each) + the `agent_assignee_argv` ancestry walk (UNMEASURED; `agent-identity.sh:24-31` says ancestry only, no machine-wide pgrep) ⇒ **≤ 0.25 s of the 10 s timeout**. That is U10 §2c's 0.35 s estimate with the 79 ms tier read deferred. `session-beat.sh` self-backgrounds under a 3 s hard cap (`:124-131`) and adds no wall to this hook. `launchctl kickstart` is UNMEASURED here (rule 4 forbids running it); it is one Mach message to an already-loaded job, and the latency it buys is bounded on the POLLER side by ThrottleInterval (10 s default, `man launchd.plist`), not on the hook side.

### 5.4 What arm 2 deliberately does NOT do

It does not page (the hook's own header `:9-16`: ~30 concurrent deaths would be 30 pages of ONE fact; paging is § 13's, damped per (account, reset_epoch)). It does not rank a target account (U10 §2c: today's ranker/chooser disagreement is a separate unit's defect, and a hook that hard-codes a target inherits it at 0.2 s latency instead of 2.5 min). It does not write `requests/<sid>.json`: 30 concurrent requests would drain as 30 serial ~45 s `--one` runs inside one lock (U06 §4 gap 2); the kick wakes the poller and § 0.5 decides from the documents. It does not read the tier. It records `teammate:true` and stops — a teammate's recovery is the lead's (`lr-reset-poller.sh:748-758`).

## 6. The beat / `cc_sp_active` phantom fix

It is the one `session-beat.sh limited` line in § 5.2 and NO consumer edit. `scripts/lib/spawn-presence.sh:319` selects `.kind == "prompt"`, so `limited` is not counted mid-turn by construction; `hooks/lib/session-busy.sh:335, 342` renders it IDLE-DEAF (true, mis-named — a LIMITED member for session-busy's enum and its renderers is a separate change, digest P4); `bin/cc-await-ping:570` reads it as "not a new turn" (correct). `session-beat.sh:62` skips the `who` derivation for any non-prompt kind and `:98-108` carries `operatorT` and `seq` forward, so the limited beat can neither forge nor erase operator presence. Recovery-chain consequence, noted not designed: digest P4's A/B over a copy of today's beat dir took `cc_sp_active` 10 → 7, and `scripts/lib/capacity-admit.sh:782-792` (`act + 1 > 8`) flips from REFUSE to ADMIT — the exact term that parked a recovery at 9 > 8 today. The lr-fleet phantom-correction shim (`lr-fleet.sh:293-335`, "Correct the ACTIVE term for limit-corpse beats before each probe") becomes redundant once every limited session carries the kind; retire it in the same change with its bats case inverted to prove the beat alone suffices.

Two load-bearing tests go into the EXISTING suites: `tests/spawn-presence.bats` "kind=limited is NOT counted mid-turn" plus a `kind=zzz` tolerance case pinning the CONTRACT (unknown ⇒ not counted), and `tests/session-beat.bats` "the limited write preserves operatorT and who=auto".

## 7. Writers 2–5 — every later actor transitions the same document

### 7.1 `scripts/limit-recover/lr-transplant.sh` (+4 lines, after the tombstone write at `:93-95`)
`lr-state transition "$SID" TRANSPLANTED --by lr-transplant --current-cfg "$TO" --current-tp "$DST" --note "lock $LOCK"`. Idempotent: a second transplant of a successor (the re-cap-then-move case, digest R3: 09e64dcb next4 → next3) appends an event and rewrites `current`; `origin` is never touched. The `--keep-source` and same-cfg refusal paths (`:62-65`) write nothing.

### 7.2 `scripts/limit-recover/lr-fleet.sh`
- `lf_one` (`:380`): before `lf_capacity_wait` (`:390`) — `lr-state claim "$sid" --by lr-fleet --run "$RUN" --deadline $(( $(date +%s) + ${LR_FLEET_CAP_WAIT_S:-600} + 300 )) --log "$rdir/$sid.stderr"` ⇒ RECOVERING. After `$HANDOFF` returns (`:396-405`): rc 0 ⇒ `transition RECOVERED`; rc 4 ⇒ `transition FAULT --note "husk: $note"`; other ⇒ `FAULT --note "lr-handoff rc=$rc"`; the two parked returns (`:383-384` no target, `:390` capacity) ⇒ `lr-state release` (claim ← null, state unchanged).
- `one)` (`:488-512`): read `state/<sid>.json` FIRST for cfg/acct/pane/cwd (one file); run `lf_locate` only when no document exists. Today `:496` pays the full 40–86 s census unconditionally even when the caller handed it `--source-pane` (U14 §4.2 item 2).
- `enqueue)` (`:514-528`): after the request write at `:527`, `transition REQUESTED`; delete the `echo "launchctl kickstart -k …"` at `:534` — the hook's bare kickstart is the trigger and `-k` kills a tick mid-recovery (`man launchctl`; digest P6).
- `locate)` (`:435`): `exec "$CENSUS" --tsv` (§ 15) — the per-file `tail` + 2 `grep` + 3 python loop at `:187-217` retires. Its `DUPLICATE` boolean at `:217` (`[ "$n" -gt 1 ] || lr_resume_procs`) — which parked a single-process session permanently (digest P5) — is replaced in the census by `|{registry live pids} ∪ {resume leaf pids}| > 1`.

### 7.3 `scripts/limit-recover/lr-reset-poller.sh`
- NUDGE `:928` / SPAWN `:966`: `lr-state claim … --by lr-reset-poller --deadline` from `CLAIM_TTL_MIN + LR_ENGAGE_SETTLE_MIN`. `NOT-ENGAGED` at `:373` ⇒ `transition FAULT --note "no assistant turn within ${LR_ENGAGE_SETTLE_MIN}m (why=…)" --log "$LOG"`. `LISTED` at `:958-959` ⇒ `transition FAULT --note "consolidated by MAX_PER_WT=1; resume by sid"`.
- TRANSPLANTED-retire `:902-905`: also `transition TRANSPLANTED` when the document still reads LIMITED (a transplant made before § 7.1 landed).
- PARKED write `:786-789`: keep writing `parked/<sid>.json` for one release (readers exist: boot-resume, resume-sessions, the proto), but take the candidate set from `state/*.json` with `state ∈ {LIMITED, RESET_PASSED} ∧ recoverable_by_waiting` BEFORE the four-store scan at `:743-747`; the `:746` grep and the `:771` allowlist migrate to the SSOT (§ 10).

### 7.4 Poller observability — the three fixes digest P6 orders BEFORE any plist edit
(i) `:180` bare `exit 0` ⇒ `log "TICK-SKIP held by pid $_hp"` first. (ii) One `log "TICK start"` after the lock so "ran and found nothing" ≠ "never ran" — today's log has ticks at 20:04:26 / 20:14:43 / 20:35:06 with a missing ~10 min tick nothing attributes. (iii) `scripts/gen-account-map.sh:117` writes `$OUT.tmp` then `mv -f`, and `lr-reset-poller.sh:293-296` gates its `break` on `source … && declare -F cc_acct_name_for_dir_basename`, with `log "FATAL account map unusable"; exit 1` after the loop — a tick can never skip the whole detection pass while exiting 0.
- NEW § 0.5, between the request drain (`:639-661`) and § 1 DETECT: `lr-state reap` (§ 8) then `lr-state page` (§ 13). Pure directory reads plus bounded writes; ≤ 50 ms.

### 7.5 `scripts/limit-recover/lr-state.sh` — the transition CLI (new, ≈220 lines; bash, one `jq` per mutation)
`lr-state transition <sid> <STATE> [--by A] [--note N] [--current-cfg C --current-tp T] [--log L]` · `claim <sid> --by A --run R --deadline EPOCH --log L` · `release <sid>` · `set-tier <sid> <model/effort>` · `ack <sid> --why W` (FAULT → CLOSED) · `reap` · `gc` · `page` · `backfill [--since ISO]` · `show <sid>`. Every mutation is tmp + `mv`, appends an event, and logs to the IDL under hook name `lr-state` (`idl_init "$CC_IDL" lr-state SID`, `hooks/lib/idl-log.sh:64`) so state changes share the `disposition/reason` grammar the fleet already audits. Illegal transitions (RECOVERED → RECOVERING without a new death, CLOSED → anything) exit 5 and write nothing — a document changing state without an event is a bug, and exit 5 is the bug's name. Nothing except `gc` deletes a document.

## 8. The reaper — fault visibility

Rule (`lr-state reap`; run by poller § 0.5 every tick, and evaluated by the census at every read, persisted only under `--reap`): for every document in RECOVERING or REQUESTED — if `claim.deadline < now` (REQUESTED: `since + 2 × StartInterval` = 1200 s, the "two ticks" U06 §4 gap 3 names) ∧ no live process holds the sid (a live registry row for the sid on `current.account`, or an `lr_resume_procs` leaf — `lr-lib.sh:239-260`) ∧ the beat is not engaged ⇒ `transition FAULT` with note `claimed by <actor> <run> at <ts> · deadline <ts> passed · no live process · log <path>`. The log path is whichever exists: `claim.log` (lr-fleet's `$rdir/$sid.stderr`), `results/<sid>.log` (the daemon lane, `lr-reset-poller.sh:657`), or `poller.log` at the `NOT-ENGAGED` line.

The shape it names, on today's measured case (U10 §1g: 09e64dcb's 12:21:26 CDT fire = run `one-20260919T172126Z`; U14 §2.1: PARTIAL, 148 s, rc 4):
```
FAULT  #111  09e64dcb  claimed by lr-fleet one-20260919T172126Z at 17:21:26Z · deadline 17:36:26Z passed · no live process for sid on next3 · beat kind=limited
       log: ~/.reso/limit-recover/fleet/one-20260919T172126Z/09e64dcb-16c7-4c65-8b11-fd854d50f299.stderr
       last: "!! relaunch typed but no claude process appeared within 90s — fallback comment typed into pane"
```
A FAULT renders FIRST in every census, above the account groups, and no rendering mode hides it. It leaves only through `lr-state ack`. Its IDL row is `{disposition:"fired", reason:"fault-named", sid, pane, log}`, countable by `operator-readout.sh`.

Why this satisfies the operator's "a claimed resume that produced nothing must be NAMED": today the four PARTIALs are legible only by opening a `.stderr` under `fleet/<run>/` (U14 §4.4) and the daemon lane's `rc=4` is "a file nobody reads" (U06 §4 gap 3). Both lanes now converge on one document, and the reaper is its one reader.

## 9. GC and bounds

- `RECOVERED` and `CLOSED` documents are removed 24 h after `since` (via a `.done` sibling touched at the transition, so mtime GC never parses JSON). `FAULT` is never auto-removed. `LIMITED` / `RESET_PASSED` with a dead origin, no successor, and reset passed ≥ 1 h (or cwd gone) ⇒ CLOSED by `reap`, GC'd 24 h later. This keeps a seven_day cap's document alive for its whole window — the marker's 1440-min TTL cannot (digest P5 fix) — while still retiring reaped worktrees (fff83638 / 0e2567ee: pid dead, `wt-cc-142546-79030` gone).
- Cap 500 documents (mirrors `STOP_FAILURE_CAP`); past it arm 2 still writes (a full store must never read as "no limits") but runs `gc` inline first.
- Concurrency: 30 concurrent births write 30 DISTINCT files, so there is no shared read-modify-write — the same argument the marker's header makes at `:18-21` for append-only. The only shared write is one sid's re-cap replace, and two StopFailures for one sid are serial by construction (one process per session).

## 10. The shared limit predicate (SSOT) and the migration of its copies

### 10.1 The module
`scripts/limit-recover/lr_predicate.py` (pure, importable, ≈120 lines) exposing `classify_record(d) -> {membership, kind, cap, reset_epoch, reset_source, model, raw_error, uuid, ts, entrypoint}` and `classify_tail(bytes)`; `scripts/limit-recover/lr-lib.sh:129-159 lr_last_api_error` becomes a thin caller that prints the same four fields it prints today PLUS `cap · reset_epoch · reset_source · entrypoint` (column-append only — every existing `IFS=$'\t' read -r _uuid _err _kind _ts` caller keeps working, because tab-split reads into 4 names fold the remainder into the LAST variable, `_ts`; the shipped callers use `_ts` only for display, `hooks/recover-inject.sh:94-96`). Three tiers, in the digest P9 shape: **T0** envelope `type=="assistant" ∧ isApiErrorMessage` — mandatory, never relaxed (the limit-recover skill description quotes the limit strings verbatim into every session's `skill_listing`; LR-o, 2026-07-25); **T1** structural `error=="rate_limit"` ⇒ membership=limit (≡ `apiErrorStatus==429`, 490/490 both directions — digest P3), `quotaLimits.rateLimitType` five_hour→five_hour / seven_day→seven_day, `quotaLimits.resetsAt`→`reset_epoch` (source `quotaLimits`); also `authentication_failed`→auth_cliff, `server_error`+529→server_529, `server_error`+no status→network; **T2** text fallback ONLY when T1 leaves `cap` unresolved: `re.search(r"You've (?:hit|reached) your (?P<scope>session|weekly|fast|monthly spend|[A-Z][a-z]+) limit")` — the open-ended scope group catches `Fable` today and the next model-scoped cap without an edit — with the prose reset parsed in the NAMED timezone (`resets\s+(?:([A-Z][a-z]{2} \d{1,2}) at )?(\d{1,2})(?::(\d{2}))?\s*(am|pm)\s*\(([^)]+)\)`), never the local one, source `prose`; none ⇒ `reset_epoch=null`, source `none`. Vocabulary out of both arms is ONE set: `five_hour | seven_day | fable | monthly_spend | unknown`; `source` is carried for audit only, so no consumer branches on provenance.

### 10.2 The copies, with the line each lives at (all read this session unless marked digest)
| # | site | today | migration step | blast radius |
|---|---|---|---|---|
| 1 | `scripts/limit-recover/lr-lib.sh:152` `"limit" if "You've hit your" in txt else "other"` (inside `lr_last_api_error`) | Fable-blind; `hooks/recover-inject.sh:98` inherits it and tells the operator a Fable cap is "NOT a quota message" | step 4: delegate to the module | recover-inject fixed by inheritance |
| 2 | `scripts/limit-recover/lr-lib.sh:55` `if "hit your" in txt or "reached your" in txt` (inside `lr_tier_from_transcript`) | already Fable-aware, 97 lines from a copy that is not | step 4 | none — de-dup |
| 3 | `scripts/limit-recover/lr-fleet.sh:108` `LIMIT_RE`, `:123` `NET_RE`, `:143` `lf_kinds_of` | 100% recall (209/209, digest P9) — the widest copy | step 5, last: `--locate` output must stay byte-identical on `tests/lr-fleet.bats` fixtures; retired entirely once `locate)` delegates (§ 7.2) | pure de-dup |
| 4 | `scripts/limit-recover/lr-reset-poller.sh:746` `grep -E "You've hit your (session\|weekly) limit"` | 19/209 miss (9.1%) — the Fable spelling | step 3: `error=="rate_limit"` ∧ envelope via the module | closes the poller's Fable blind spot |
| 5 | `scripts/limit-recover/lr-reset-poller.sh:771` allowlist `kind in ('session','weekly','fable')` | `'fable'` is dead — the producer (`lr-audit.py`) has no such kind (`grep -c fable lr-audit.py` => 0, digest P9) | step 3: "kind has a reset" | retires a consumer written for a producer change that never landed |
| 6 | `scripts/limit-recover/lr-audit.py:75-79 LIMIT_PREFIXES` + `:244 classify_limit_text` (`startswith`) | Fable-blind; `startswith` | step 2, ALONE (the only `startswith`→`search` behaviour change) | the authoritative producer |
| 7 | `scripts/limit-recover/lr-audit.py:80 SERVER_529 = "API Error: Server is temporarily limiting requests"` | matches 0 of 924 api-error events (digest P3); the real string is `API Error: 529 Overloaded…` | step 2: delete, or map T1 `server_error`+529 | dead code removal |
| 8 | `scripts/limit-recover/lr-audit.py:81 RESET_RE` + `:211 parse_reset` (`return None` when ZoneInfo missing; `:239-240` swallows ValueError/KeyError/OSError) | English prose through zoneinfo for the 86% of records that already carry an epoch | step 2: `quotaLimits.resetsAt` first, prose second | reset becomes an integer |
| 9 | `scripts/limit-recover/lr-reset-poller.sh:566 SPEND_RE` | monthly-spend only | step 3 | de-dup |
| 10 | `bin/cc-classify:312` `grep -qiE 'session limit\|weekly limit\|usage limit\|limit ·\|resets\|monthly spend limit\|spend limit\|billing'` (→ `:817` `rate-limited`, NEVER reap) | Fable-blind veto | step 6: UNION with the module — never replace (a veto must not lose coverage; its safe failure direction is the opposite of the census's) | decides whether a Fable-capped pane is reapable — the recovery-chain prerequisite |
| 11 | `scripts/desk-invariant.sh:156 cap_stunned` (envelope deliberately dropped, `:149-152`) | same regex family, no envelope | step 6: UNION | observer, not decider |
| 12 | `scripts/handoff-fire.sh:9236`, `scripts/cloud-ceiling-probe.sh:212`, `scripts/lib/cloud-create.sh:174` | CLI-stdout copies, a different domain (digest P9) | leave, with a comment naming the SSOT; add a lint asserting no NEW transcript-JSONL limit regex outside the module | none |

Order: (1) land the module + `tests/lr-predicate.bats` with NO call sites; (2) `lr-audit.py`; (3) poller `:746/:771/:566`; (4) `lr-lib.sh:55/:152`; (5) `lr-fleet.sh`; (6) the two vetoes UNION; (7) the lint. Each step lands alone with a strictly decreasing blast radius. Arm 2 (§ 5) depends on step 4 only for the `cap`/`reset_epoch` columns; it ships with `cap=unknown` if the module is absent (the read at § 5.2 falls through to the sha latch), so the arm can land before step 4 without losing detection — only classification.

### 10.3 The red-proof fixtures (verbatim shapes, one per blind spot)
F1 `fable-park`: the 2.1.260 record at `~/.claude-quaternary/projects/-Users-chrisren-Development-hammerspoon-config/2d71c6d8-….jsonl:1252` (`quotaLimits` absent, `errorDetails` present) ⇒ `cap=fable, reset_epoch=null, recoverable_by_waiting=false` — parks under /model, never under a wait · F2 `fable-no-reap`: `bin/cc-classify` must answer `rate-limited` on that tail (highest consequence) · F3 `next-model`: a synthetic `You've reached your Sonnet limit` — RED even against lr-fleet's widened `LIMIT_RE`, proves the open scope group · F4 `structural-reset`: a `quotaLimits`-only record with no prose `resets …` — today `RESET_RE` finds nothing, `:773 [[ -n "$reset" ]] || continue` drops it, never parked · F5 `no-zoneinfo`: `ZoneInfo` forced None, reset still resolves from the epoch · F6 spend packet · F7 `529 Overloaded` is NOT a limit · F8 `ENOTFOUND` is NOT a limit · F9 the skill-listing text with BOTH spellings and NO envelope ⇒ not a limit — the suite's FIRST assertion, because every widening above is legal only while T0 is mandatory and F9 is the only test that can catch a T0 regression · F10 `Not logged in · Please run /login` ⇒ auth_cliff, marker written, no state document.

## 11. The census contract — `bin/cc-limited`

### 11.1 Shape
One python3 process, no subprocess except the single `ps` (and `kitten @ ls` under `--titles` only). Inputs, in read order: `LR_STATE_DIR/state/*.json` (the enumerator) · `CC_REGISTRY_DIR/[0-9]*.json` (pane · pid · lstart · account · startedAt · cwd) · one `TZ=UTC LC_ALL=C ps -eo pid=,lstart=` · `CC_BEAT_DIR/<sid>.json` for the named sids only · `LR_STATE_DIR/locks/<sid>.lock` for TRANSPLANTED corroboration · `~/.claude/accounts.json` (both spellings) · under `--verify`, the 128 KB tail of each `current.transcript_path` through the SSOT (salvage: `UNKNOWN-STUB` when a copy holds zero assistant records — the 2,886-byte 07e30aeb stub, digest P5 — is its own state and is never read as RE-ENGAGED). NEVER read: the marker files, `parked/`, any transcript not named by a document, the full project trees.

Modes: `cc-limited` (human table, per account) · `--json` · `--tsv` (the 11-field `lr-fleet --locate` row, byte-compatible: sid · cfg · account · pane · pid · cwd · tier · disposition · kind · kinds · err_age_s) · `--all` (also list MOVED / RECOVERED / CLOSED rows instead of tallying them) · `--titles` · `--verify` · `--reap` (persist FAULT/RESET_PASSED/CLOSED overlays via `lr-state`; otherwise a census is a pure read) · `<query>` (resolver, § 11.3).

### 11.2 Columns and exit codes
Human table: `PANE · SID8 · DISPOSITION · CAP · RESET · SINCE · ALIVE · TIER · TITLE/CWD`. JSON: `{generated_at, elapsed_ms, store:{docs, faults, unaddressable, moved, closed}, faults:[…], accounts:{<acct>:{cap, reset_epoch, reset_in_s, needs_recovery:N, sessions:[{sid, pane, pid, state, disposition, cap, reset_epoch, since, alive, moved_to, teammate, entrypoint, cwd, cwd_ok, title, doc}]}}}`. Every row carries `doc` (the document path) so a reader can `lr-state show` it.
Exit codes: **0** nothing needs recovery · **1** ≥ 1 session needs recovery (RECOVERABLE / NO-PANE / TRANSPLANTED-BLOCKED / UNADDRESSABLE / RESET-PASSED) · **2** usage · **3** ambiguity refused (resolver ≥ 2 hits, or one sid held by > 1 live process — both rows printed with pane · sid8 · account · title) · **4** a store unreadable (state dir missing, `ps` failed, or a document that fails to parse — NEVER an empty list at exit 0: `lr-fleet.sh:439-445` records how a silent width gate once returned a valid empty `--json` that every consumer read as "no blocked sessions") · **5** FAULT present (outranks 1: a named fault is the first thing the operator must see).

### 11.3 The resolver (`cc-limited <query>`), from P10
Exact pane id or sid prefix ⇒ resolve. Else case-insensitive substring over title (last `"aiTitle"` in the tail, or the glyph-stripped kitty title from ONE unmatched `kitten @ ls` when `--titles` — 29 ms whole fleet, never `--match id:N` per pane at 347 ms/15) then over cwd. 1 hit ⇒ resolve; 0 ⇒ NO-MATCH exit 1; ≥ 2 ⇒ REFUSE, exit 3, candidates printed — never disambiguated by recency. The live fleet has two panes on DIFFERENT accounts both titled "limit-recover optimization" (P10), and guessing the account is the expensive mistake. `kitten @ ls` stays OFF the default hot path: it timed out at 10.06 s once in four with a truncated payload (U07 §5).

### 11.4 Latency budget per stage, with the measurement behind each
| stage | budget | measurement |
|---|---|---|
| death → StopFailure delivered | ≤ 1 s | IDL join, 126/128: min 0, p50 0, p95 1, max 1 s (digest P1) |
| hook baseline | 0.09–0.14 s | `/usr/bin/time -p` ×3 this session (§ 1 #3) |
| arm 2: tail read + SSOT (one python start) | +0.03–0.05 s | proto 0.050 s wall vs 0.021 s self-timed ⇒ ~0.03 s interpreter; U10 §2c ~10 ms parse |
| arm 2: doc write (2 jq + mv) | +0.006 s | `jq -cn` 0.003 s |
| arm 2: ≤ 4 ps + ancestry walk | +0.02 s | `ps -o …` ~5 ms each (bench `ps -eo` full table 29.6 ms) |
| arm 2: beat | 0 on the hook's wall (backgrounded, 3 s cap) | `session-beat.sh:124-131` |
| arm 2: kickstart | UNMEASURED (rule 4) | poller-side floor = ThrottleInterval 10 s |
| **event → document on disk** | **≤ 0.25 s** | sum; 10 s timeout |
| census: state dir read (40 docs) | 1.0 ms | bench |
| census: registry read (31 rows) | ~1 ms | bench proxy (same shape) |
| census: `ps -eo pid=,lstart=` | 29.6 ms | bench, 1,326 lines |
| census: kill -0 / lstart compare ×40 | 0.12 ms | bench |
| census: beats ×14 | < 1 ms | 0.1 ms/file (P10) |
| census: python start | ~30 ms | proto |
| **census total** | **≈ 0.05–0.09 s** | proto 0.050 s wall today over the same stores; U14 A4 0.148 s for a 2,158-file scan the census no longer does |
| `--titles` (one `kitten @ ls`) | +29 ms typical; may hang 10 s | P10 R8; U07 §5 |
| `--verify` (14 × 128 KB tails) | +~15 ms | 0.2 ms/file tail parse (P10) + read |
| **event → pull-visible** | **≤ 0.35 s** | sum |
| **event → push** | **≤ ~12 s** | kickstart + ThrottleInterval floor 10 s + § 0.5 (< 50 ms); today mean 323 s / max 609 s (digest P6) |
| backfill (one-shot) | ≈ 0.3 s | 0.14 s glob over 2,172 files (digest P4 R5) + 14 tails |
Against the shipped `lr-fleet --locate`: 35.5 s (lead) / 43.6 s (digest P5) / 40–86 s (U14) — a ~500–1,000× reduction, and, more importantly, a census window (≈ 50 ms) shorter than the fleet's own state-change interval, where `--locate`'s 43.6 s window straddled a transplant (digest P5).

### 11.5 Per-account output mock — today's fleet at the lead's 20:55Z snapshot
Dispositions reproduce the lead's tally (next3: 6 RECOVERABLE with pane ids + 1 TRANSPLANTED; next4: 4 moved + 2 reset-passed); pane ids are the registry rows measured at 21:15Z (§ 1 #17); titles are the P10 R4 tail reads. The 8th next3 row (07e30aeb) is the one the prototype dropped.
```
cc-limited · 2026-09-19T20:55:12Z · 14 docs · 0 faults · 0.061 s

next3  five_hour · resets 21:30Z (in 0h34m) · 8 limited: 6 RECOVERABLE · 1 TRANSPLANTED-BLOCKED · 1 UNADDRESSABLE
  PANE  SID8      DISPOSITION          SINCE  ALIVE  TIER               TITLE · CWD
  #111  09e64dcb  RECOVERABLE          1h01m  yes    opus-5/high        /limit-recover optimization and investigation · claude-infrastructure
  #127  11569d45  RECOVERABLE          1h01m  yes    fable-5-1/xhigh    limit-recover optimization · claude-infrastructure
  #121  65186f1f  RECOVERABLE          0h57m  yes    -                  Subagent lifecycle root cause implementation · impl/subagent-lifecycle-w0
  #149  8843bcf3  RECOVERABLE          0h56m  yes    -                  Weekly limit exhaustion display · claude-infrastructure
  #147  07e30aeb  RECOVERABLE          0h25m  yes    -                  Bottle image review for Studio60 menu · wt-cc-143039-68221
  -     4bc1159f  RECOVERABLE?         0h54m  ?      -                  W1b floor-plan first frame soft nav · claude-infrastructure   ← no registry row: sid+cwd only, not queueable in place
  -     26cd14be  UNADDRESSABLE        0h50m  no     -                  reso-management-app worktree sync strategy · claude-infrastructure   ← pid 64409 died between samples (P4)
  -     98f02458  TRANSPLANTED-BLOCKED 0h57m  no     -                  Kitty Terminal split pane auto-even on move · wt-pool-2   → successor on next2 still carries the cap, NO pane
next4  five_hour · reset 19:40Z passed 1h15m ago · 6 limited: 4 recovered (moved: 3→next2, 1→next3; hidden, --all lists) · 2 RESET-PASSED
  #143  fff83638  RESET-PASSED         1h27m  no     -                  (untitled) wt-cc-142546-79030   ← process dead, worktree reaped → CLOSED on --reap
  #145  0e2567ee  RESET-PASSED         1h27m  no     -                  (untitled) wt-cc-142549-10206   ← same
exit 1  (8 need recovery: 6 in place on next3 · 1 successor without a pane · 1 unaddressable)
```
The same census at 21:15Z (§ 1 #14) collapses next3 to `8 limited: 7 recovered (moved →next2) · 1 TRANSPLANTED-BLOCKED` and prints ONE row, which is the noise suppression rule working: a MOVED row is a tally, never a line.

## 12. Statusline identity — an IDENTIFICATION primitive, never a DETECTION one

`~/.claude/statusline.sh:486` (`echo -e "${GLYPH_PREFIX}${PCT_SEG}${OUTPUT}${RESET}"`) gains a left-anchored `ID_SEG` between `GLYPH_PREFIX` and `PCT_SEG`: `#<pane> <sid8> · `. Sources, zero forks: `_pane="${KITTY_WINDOW_ID:-}"; [ -n "$_pane" ] || _pane="${ITERM_SESSION_ID##*:}"` and `${PAY_SID:0:8}` from the single `jq` pass already at `:77-88`. Glyph is `#` (U+0023, Monaco-covered) — NOT `⌗` (U+2317: `fc-list ':charset=2317' | grep -c ^Monaco` => 0, the same downsample class as the twice-reverted `①`, digest P7). Measured cost −0.2 ms CPU/render (digest P7), +16 columns; the binary truncates right-edge (`<Text wrap="truncate">`), so at the 30-col panes (5 of 16 live, U07 §2b) the chip survives and the sha/effort tail is what is spent. Do NOT set `statusLine.refreshInterval` to 1 (16 panes × 61 ms CPU = one core, forever); 10–30 s only if a freshness tick is ever wanted. Detection never routes through this surface: `rate_limits` vanishes from the payload once `resets_at` passes, and a limited pane re-renders zero times (U07 §3d) — the chip only closes the marker→pane join the registry closes anyway; its value is the screenshot/eyeball case the operator is trying to leave behind, and the `cc-limited <pane>` resolver (§ 11.3) is what it feeds. Converge: § 17.

## 13. The push / notification surface

Producer: `lr-state page`, run only from poller § 0.5 (never from the hook — § 5.4). One page per **(account, reset_epoch) group**, fingerprinted through `hooks/lib/page-damp.sh` `damp_should_send "lr-limited" "<acct>:<reset_epoch>:<N>"` (TTL 1800 s; fail-open) so 30 deaths on one account become one page, and a second page fires only when N changes or the TTL lapses. Two sinks, both already shipped: `bin/cc-notify --role desk "<line>"` (role-addressed so a recycled desk pane is followed, `cc-notify:12-14`) and the poller's own bounded `osascript display notification` (`lrp_bounded`, `lr-reset-poller.sh:278`). `hooks/push-critical.sh` stays inert (`:22-23`, no PUSHOVER_TOKEN) — recorded, not depended on. The line: `⛔ next3: 6 sessions capped (five_hour, resets 21:30Z in 0h34m) · panes 111 127 121 149 147 · 1 successor without a pane · cc-limited` — the identical fact the census prints, so the page and the pull surface can never disagree. FAULT is paged separately, undamped by group (fingerprint = sid+claim.run), because it is a per-session fact.

## 14. Legacy back-fill — deaths before the arm existed, once

`lr-state backfill [--since 2026-09-17T00:00Z]` (default: 48 h, the poller's `RECENCY_MIN`; idempotent; O_EXCL create so a hook-born document always wins). Sources, in order: (1) `~/.claude/autonomy/stop-failure/rate_limit__*.jsonl` grouped by sid, MAX(ts) — 26 rows → 14 sids today; (2) the IDL for `hook=="stop-failure-marker" ∧ disposition=="fired"` beyond the marker's 24 h TTL — live file plus `gunzip -c ~/.claude/autonomy/idl.jsonl.*.gz` (33 + 571 rows, § 1 #16); (3) for each sid without a document: resolve the transcript by globbing ALL config dirs for `<sid>.jsonl` ∪ `<sid>.jsonl.handed-off`, dedupe by `os.path.realpath` (`~/.claude-next/projects` → `~/.claude/projects`), order `.handed-off` last then size desc, take the newest copy with ≥ 1 assistant record (P10 R2, digest P5 fix 1); classify its tail through the SSOT for `death.*` (uuid from the record — the latch stays valid); `origin.account` from the MARKER row when one exists (the dying process's own config dir), else from the account the transcript's live copy sits under, marked `origin.account_source:"scan"` so a reader can see it is weaker; `origin.pane`/`pid`/`lstart` from a registry row whose sid matches — else **null, never guessed**; `locks/<sid>.lock` ⇒ state TRANSPLANTED with `current` from the lock's `to`; `parked/<sid>.json` ⇒ `reset_epoch` corroboration; `entrypoint` from the record (this is the only way an `sdk-cli` death — invisible to StopFailure, digest P1 — ever gets a document, rendered HEADLESS). Every backfilled document carries `events:[{actor:"backfill"}]`. Cost ≈ 0.3 s (§ 11.4). It runs once from the deploy step (§ 17) and is safe to re-run at any time; the poller does NOT run it per tick.

## 15. How the consumers read the ONE census
- `lr-fleet.sh --locate` (`:435`) ⇒ `exec "${LR_CENSUS_BIN:-$LR/cc-limited}" --tsv` (+ `--json` passthrough). `lf_locate` / `lf_kinds_of` / `lf_err_age_s` / `lf_dedup_mirror` (`:143-262`) retire; `tests/lr-fleet.bats` locate cases move to `tests/lr-census.bats` with byte-identical expected rows.
- `lr-fleet.sh --one` (`:488-512`) reads `state/<sid>.json` first (§ 7.2); `--recover` (`:456`) iterates the census rows; `--enqueue` writes REQUESTED; `--duplicates` reads the census's live-pid cardinality.
- `lr-reset-poller.sh` § 1 DETECT takes candidates from `state/` (§ 7.3), § 0.5 reaps and pages (§ 7.4). Its `parked/` becomes a view of `state ∈ {LIMITED, RESET_PASSED} ∧ recoverable_by_waiting` after one release.
- `/recover` and `/limit-recover` (`commands/recover.md:101`, `commands/limit-recover.md:410`): the "read KIND per unit from `lr-fleet.sh --locate`" sentence points at `cc-limited --json`; the docs' step 4 kickstart line (`:437`) drops `-k`.
- `bin/cc-classify:817 recent_api_limit` UNIONs `[ -f "$LR_STATE_DIR/state/$sid.json" ] ∧ state ∈ {LIMITED, RECOVERING, TRANSPLANTED, RESET_PASSED}` (one stat) with its regex — never-reap gets a structured second leg.
- `bin/cc-sessions` (30.4–41.0 s, no sid column — U07 §0): out of scope, but the census JSON is the drop-in its `NAME UUID ACCOUNT AGE CWD` table lacks.
- `cc-limited-proto.py` is retired by `bin/cc-limited`; its four measured defects (marker `transcript_path` trusted at `:34`; `last is None` folded into RE-ENGAGED at `:48`; bare lock existence at `:59`; MOVED terminal at `:68`) are each a named test in § 16.

## 16. Tests — bats, red-proofs, fixtures named from real sids

All hermetic in the style the existing suites already use: `HOME`, `LR_STATE_DIR`, `CC_REGISTRY_DIR`, `CC_BEAT_DIR`, `STOP_FAILURE_MARKER_DIR`, `STOP_FAILURE_IDL`, `STOP_FAILURE_ACCOUNTS` under `BATS_TEST_TMPDIR` (`tests/stop-failure-marker.bats:23-33`, `tests/lr-fleet.bats:6-16`), `ps` stubbed the way `tests/spawn-presence.bats` stubs it for census cases, clocks pinned (`CC_BEAT_NOW`, `LR_NOW`). Fixture transcripts are 3–6 verbatim records cut from the real sids named below (uuids, timestamps and `quotaLimits` kept; content bodies truncated).

**`tests/stop-failure-marker.bats` (+~90 lines, arm 2)** — SA1 a `rate_limit` payload for `09e64dcb` with `KITTY_WINDOW_ID=111` and a fixture tail carrying record `fcf01ffb-…` ⇒ exactly one `state/09e64dcb-….json` with `state=LIMITED, death.uuid=fcf01ffb-…, cap=five_hour, reset_epoch=1789853400, origin.pane="111", origin.account="next3"` (accounts fixture maps `~/.claude-tertiary`→next3) · SA2 the same payload ×3 ⇒ one document, `events|length==1`, IDL `passed state-latched` ×2 · SA3 a second payload whose tail's last record has a NEW uuid ⇒ `events|length==2`, `death.uuid` replaced, `origin` byte-identical · SA4 a document pre-set to `FAULT` + re-cap ⇒ `state` still FAULT, event appended · SA5 `authentication_failed` ⇒ marker line written, NO document · SA6 the Fable text (F1 fixture) ⇒ `cap=fable, reset_epoch=null, recoverable_by_waiting=false` · SA7 `agentName` in the first 8 KB ⇒ document with `origin.teammate=true`, NO kickstart call (stub `launchctl` via PATH, assert not invoked) · SA8 `CC_SF_STATE=off` ⇒ marker unchanged, zero documents · SA9 state dir unwritable ⇒ marker still written, IDL `abstained state-dir-unwritable`, exit 0, EMPTY stdout · SA10 after the hook, `beats/<sid>.json` has `kind=="limited"` and a pre-existing `operatorT` is preserved · SA11 the existing CONTROL (`:171`, session-keyed mutant goes red) still passes — the arm must not have widened the write footprint of the marker half · **CONTROL SA-red**: a mutant latching on `sid` instead of `death.uuid` must FAIL SA3.

**`tests/spawn-presence.bats` (+2)** — "kind=limited is NOT counted mid-turn" (one live stubbed pid, three beats prompt/limited/stop ⇒ ACTIVE=1) · "kind=zzz is NOT counted (the contract: unknown ⇒ not active)". **`tests/session-beat.bats` (+1)** — "the limited write preserves operatorT and who=auto".

**`tests/lr-state.bats` (new, ~80 lines)** — every legal transition from § 4.2 writes exactly one event and updates `since`; each illegal one exits 5 and leaves the file byte-identical; `claim`/`release` round-trip; `ack` FAULT→CLOSED and refuses on any other state; `reap` on a RECOVERING document with `deadline < LR_NOW` and no live pid (stubbed `ps`, empty registry) ⇒ FAULT with `claim.log` in the note; `reap` on the same with a LIVE successor pid ⇒ unchanged; `gc` removes a RECOVERED doc aged 25 h and keeps a FAULT aged 30 d.

**`tests/lr-census.bats` (new, ~200 lines)** — fixtures: documents for 09e64dcb (pane 111, alive), 65186f1f (registry row on a DIFFERENT account with `startedAt > death.ts`, alive ⇒ MOVED tally, never a row — digest R4's decision-bearing case), 98f02458 (lock `to` = another cfg, successor beat `limited`, no pane ⇒ TRANSPLANTED-BLOCKED row), 07e30aeb (`current.transcript_path` → a 3-record stub with zero assistant records ⇒ UNKNOWN-STUB under `--verify`, NEVER RE-ENGAGED; beat `limited` ⇒ RECOVERABLE without `--verify`), e442434c (no registry row ⇒ UNADDRESSABLE, rendered), fff83638 (pid dead, cwd absent, reset passed ⇒ RESET-PASSED; `--reap` ⇒ CLOSED), one sdk-cli backfilled doc (HEADLESS), one teammate doc (TEAMMATE). Assertions: grouping by `origin.account` + `reset_epoch`; MOVED is a tally; FAULT first; exit code matrix 0/1/3/4/5 including "a document that fails to parse ⇒ exit 4, never an empty list"; `--tsv` rows are 11 fields and byte-equal to the `lr-fleet.bats` locate expectations; the resolver: pane id exact, sid8 exact, two panes with the same title ⇒ exit 3 with both candidates printed; `backfill` over a marker fixture with 31 rows / 19 sids + a pre-existing hook-born doc ⇒ 18 new docs, the hook-born one untouched, second run ⇒ 0 new; `--titles` with a stubbed `kitten` that emits a truncated payload ⇒ the census still exits with its table and marks titles `?` (the 10 s corruption case, U07 §5).

**`tests/lr-predicate.bats` (new, ~90 lines)** — F1…F10 from § 10.3, F9 first.

**Red-proof discipline** (`tests/spawn-presence.bats:11-15` records why): each new suite is run once against pristine trunk (`226b73888`, the arm absent) and the RED output is pasted into the suite's `# RED-PROOF` footer; the mutant controls (SA-red; the census's "MOVED rendered as a row" mutant; the predicate's "T0 dropped" mutant that makes F9 pass) must each turn exactly their named case red.

## 17. Deploy / converge, and the operator-owned steps

Agent-side, live on save (symlink classes, § 1 #2): `hooks/stop-failure-marker.sh`, `hooks/session-beat.sh` (no change), `scripts/limit-recover/{lr-lib.sh, lr-fleet.sh, lr-reset-poller.sh, lr-transplant.sh}`, `bin/cc-notify` (no change). **Adds** (`scripts/limit-recover/lr-state.sh`, `scripts/limit-recover/lr_predicate.py`, `bin/cc-limited`) are NOT live until the converger creates their symlinks (`LIVE_ADDS` rule, global CLAUDE.md § 🚀): land, then `CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh` (agent-runnable per `.claude/CLAUDE.md:35-47`), then `bash scripts/deploy-parity-assert.sh` must print no `MISSING`/`COPYSTALE`. `statusline.sh` is a COPY class: `install.sh:960 copy_file`, repaired ONLY on deploy-live's advance path (`scripts/deploy-live.sh:1310-1333, 1770`) — confirm an advance actually ran, else `deploy-parity-assert.sh:1141` reports COPYSTALE and nothing automatic clears it. Then `lr-state backfill` once. Order: predicate module → arm 2 → lr-state + cc-limited → converge → backfill → consumer delegation (§ 15).

Operator-owned c10 steps (agent must NOT run these):
1. `~/.claude/accounts.json`: add `{"name":"next","config_dir":"~/.claude", …}` as an alias row (or an `aliases_config_dirs` field the hook's `:85-87` jq also matches) so the default dir stops naming a fifth account `.claude`. NOT the next2 row — § 1 #12.
2. `~/Library/LaunchAgents/com.reso.lr-reset-poller.plist` + the SSOT `scripts/limit-recover/com.reso.lr-reset-poller.plist`: `plutil -insert QueueDirectories -json '["/Users/chrisren/.reso/limit-recover/requests"]'`, `plutil -insert ThrottleInterval -integer 5`, then `launchctl bootout gui/$(id -u)/com.reso.lr-reset-poller && launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.reso.lr-reset-poller.plist`. Keep `StartInterval 600` as the floor; never `WatchPaths` (`man launchd.plist:330-338`, "entirely possible for modifications to be missed"). Only after § 7.4's three observability fixes have landed. `scripts/launchd-parity-lint.sh` asserts live == SSOT.
3. If a `LIMITED` member is wanted in `session-busy.sh`'s enum and its renderers — a separate decision (digest P4).
No `settings.json` edit anywhere: the arm rides the existing StopFailure registration.

## 18. LOC per file, and every file:line touched (all read this session)
| file | change | LOC |
|---|---|---|
| `hooks/stop-failure-marker.sh` (131 lines) | arm 2 inserted at `:130-131`; `:82-89` jq extended to match an alias field | +48 |
| `scripts/limit-recover/lr_predicate.py` (new) | § 10.1 | +120 |
| `scripts/limit-recover/lr-lib.sh` (369) | `:129-159 lr_last_api_error` delegates, +4 output columns; `:55` and `:152` delegate | +18 / −6 |
| `scripts/limit-recover/lr-state.sh` (new) | § 7.5 | +220 |
| `bin/cc-limited` (new, python3) | § 11 | +260 |
| `scripts/limit-recover/lr-fleet.sh` (584) | `:380-405` claims; `:435` delegate; `:488-512` doc-first; `:514-534` REQUESTED + delete `-k` echo; `:143-262` and `:293-335` retired | +30 / −140 |
| `scripts/limit-recover/lr-reset-poller.sh` (1033) | `:180` skip log; tick log after `:190`; `:293-296` guard; § 0.5 after `:661`; `:373`, `:786-789`, `:902-905`, `:928`, `:958-959`, `:966` transitions; `:746`, `:566`, `:771` → SSOT | +55 / −10 |
| `scripts/limit-recover/lr-transplant.sh` | after `:95` | +4 |
| `scripts/limit-recover/lr-audit.py` (2362) | `:75-81` → module; `:80` deleted; `:244` `search` | +10 / −8 |
| `scripts/gen-account-map.sh` | `:117` tmp + mv | +2 |
| `bin/cc-classify` | `:312`, `:817` UNION | +6 |
| `scripts/desk-invariant.sh` | `:156` UNION | +3 |
| `statusline.sh` (486) | ID_SEG before `:486` | +7 |
| `commands/limit-recover.md`, `commands/recover.md` | `:410-437`, `:101` | +12 / −4 |
| tests: `stop-failure-marker.bats` +90 · `spawn-presence.bats` +16 · `session-beat.bats` +10 · `lr-state.bats` +80 · `lr-census.bats` +200 · `lr-predicate.bats` +90 · `lr-fleet.bats` −60 (locate cases moved) | | +486 / −60 |
| **total** | | **≈ +1,280 / −230** |

## 19. The anchor's trade-offs, honestly
- **A stored document can go stale in a way a read-time join cannot.** Mitigation is structural: nothing the census renders as CURRENT (alive, pane owner, moved, engaged, reset_in, cwd_ok) is stored — § 4.3. What IS stored is the past (death, origin) and the claims, and the reaper is the actor that reconciles claims against the present every tick. The residual: a transition the writer forgot (e.g. a future recovery tool that does not call `lr-state`) leaves a document in RECOVERING; the reaper then names it FAULT after the deadline — a false FAULT is loud and cheap (`ack`), a silent husk is what the operator forbade. This is the deliberate polarity.
- **Two stores for one fact during migration** (marker + document; `parked/` + document). The marker stays by design (§ 2); `parked/` is a view after one release. A reader that consults both and finds them disagreeing must say so (`cc-limited --verify` prints `DISSENT`), never pick silently — the lesson of `lr-fleet.sh:210/:215` welding next2's transcript to next3's pane (digest P5).
- **The hook grows.** From 0.09–0.14 s to ≤ 0.25 s on the death path, still 40× inside its timeout; every added path abstains to the IDL and exits 0. The tier read (79 ms) was the one item worth deferring, and it is deferred.
- **Headless deaths stay invisible to the event.** `sdk-cli` sessions emit no StopFailure (0/2, digest P1); the document store therefore has them only through backfill, marked HEADLESS. The design says so rather than claiming coverage.
- **Subagent-slot losses stay with the transcript/workflow audit** (323 slot deaths under one sid produced 117 parent fires and zero per-slot identity, digest P1). The document is session-level, like the event.
- **Against the read-time-join alternative** (marker × registry × beat at every read, no state): that shape needs the marker to be complete and un-rotted, and it is neither — 24 h TTL loses the weekly cap, `transcript_path` rots on transplant, and it holds no claim, so no reaper can name a husk from it. The document is the only place a CLAIM can live, and the claim is what makes fault visibility possible.

## 20. Recovery-chain dependencies — noted, not designed
(a) `scripts/lib/capacity-admit.sh:782-792` ceiling 8 — partially dissolved by § 6 (10 → 7 on today's beats) but the load term (`CC_ADMIT_LOAD_TERM`, `:555/601/636`) and `lr-fire-resume.sh:322`'s second gate (exit 9, the 4 PARTIALs) are untouched. (b) `handoff-fire.sh:6811/6815` 90 s dead-waits and `:6879`'s unattributed verdict — the reaper NAMES the husk; it does not shorten the wait. (c) The ranker/chooser disagreement (`claude-accounts --rank fable` vs lr-fleet's dry run, U10 §2c) — `target:"auto"` is passed through unchanged. (d) `lr-select`'s `MAX_PER_WT=1` write-off — made visible as FAULT, not removed. (e) The teammate branch has never fired on this event (0/10 today, U10 §3c); SA7 is the fixture that establishes it. (f) `session-busy.sh` LIMITED enum — c10 item 3.

## 21. UNMEASURABLE / not measured here
`launchctl kickstart` cost and whether the ThrottleInterval floor is 10 s on this box (rule 4: not run); whether `StopFailure` fires inside an Agent-Teams assignee (no instance in the corpus); whether `quotaLimits` is ever emitted for `monthly_spend` on 2.1.260 (no such event since 2026-07-25, digest P3); the `agent_assignee_argv` ancestry walk's wall time on a loaded box; `session_name` presence in the live statusline payload (U07 §7 labelled guess). The design degrades on each: `CC_SF_KICK=0` leaves detection intact; a missing teammate fire leaves the lead's audit; a missing `quotaLimits` falls to T2 prose; a slow ancestry walk is bounded by the hook's 10 s and abstains to the IDL.
