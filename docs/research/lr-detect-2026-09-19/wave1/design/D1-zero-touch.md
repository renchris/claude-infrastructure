# D1 — ZERO-TOUCH limit recovery: the limited session files its own request; a daemon recycles it in place; every transition is a row

Designer: D1-zero-touch · 2026-09-19 · built on research units U01–U14 (cited as `Uxx §n`) and on
the repo at `/Users/chrisren/Development/claude-infrastructure` (cited `file:line`). Nothing here
re-measures what the units measured; where I add a number I say how it was derived.

---

## 0. The verdict in one paragraph

Every stage of today's recovery already exists on this box, and the two that matter most ran
**before the operator lifted a finger**: `StopFailure` recorded all five limits within 9 minutes,
the first at 11:58:33 — three minutes before the first `/limit-recover` (U10 §1c, §1g) — and the
reset poller parked all five, the first 128 s before that same command (U06 §2). Both wrote files
nothing reads. What turned a 3-second pipeline (U02 §1: audit + bundle + transplant + launcher =
1–2 s) into 98.7 minutes was four things, none of them a missing capability: (1) no request writer
at the moment of detection and a 600 s tick with no `WatchPaths` (U10 §2e); (2) a relaunch re-gated
in a process the driver cannot reach, with a 3-refusal budget the 2-attempt watcher can never
release (U01 §0, U04 §0, U05 §3.4 — 4 of 5 husks, arithmetic not luck); (3) a watcher whose failing
branch writes no row and no alarm, and a poller that then retires the husk as "the successor carries
it" (U02 §2c, U04 §3); (4) a lead that blocked its own turn on polls for 24.4 min while the
operator's screenshots queued 87 min behind it (U11 §2). This design closes all four with ~900
lines, 80 % of them in files that already own the concern, one plist edit for the operator, and no
new hook registration. The screenshot becomes a fallback the operator will rarely need, and when
they do it resolves in ≤0.3 s because the pane and the sid are printed on the statusline.

---

## 1. The operator's target, as measurable requirements

| # | requirement | number | source of the number |
|---|---|---|---|
| R1 | limit → recovery **started** without any operator action | ≤ 2 s (WatchPaths) · ≤ 600 s backstop | U10 §2e; plist `StartInterval 600` |
| R2 | limit → **engaged** (a real assistant turn on the prompt we sent), idle box | ≤ 35 s p50, ≤ 60 s p95 | U14 §2.2 floor 21 s + this chain's additions (§12) |
| R3 | same, box under load | ≤ 155 s | §7 probe bound 120 s + R2 |
| R4 | N sessions | ≈ 2 × single at concurrency 3 (5 sessions ≤ 90 s) | §7 |
| R5 | invoking session (manual path) blocked for | ≤ 3 s, then the turn ENDS | U11 §7 #1 |
| R6 | screenshot/keyword → (sid, pane, account, cwd, tier) | ≤ 0.3 s; **refuses** on ambiguity | U07 §6b, U14 §3.3 |
| R7 | any failure named — sid, pane, stage, cause, one re-drive command — within | ≤ 10 s of the deciding event; ≤ 15 min for a stalled driver | §10 |
| R8 | husks | 0 unrecorded; every recorded one re-driven automatically | §10 |
| R9 | tokens on the recovered session's first turn | 1 message, 0 tool calls, ≤ 0.1 K resident | U12 §6.3 |
| R10 | tokens on any lead | 0 (zero-touch) · 1 short turn (manual) | U11 §1 |
| R11 | static, repeatable commands | every step is a script with a fixed argv and a file-backed verdict | §5 |

---

## 2. What exists and is SOUND — reused verbatim

These are not touched, and the design leans on them (each measured by the unit named):

- **`StopFailure` → `hooks/stop-failure-marker.sh`**, registered in all five config dirs
  (`jq '.hooks.StopFailure' ~/.claude*/settings.json` ⇒ `~/.claude/hooks/stop-failure-marker.sh`
  ×5, verified this session), fires sub-second with `error`, `session_id`, `cwd`,
  `transcript_path` (U10 §1c), costs 0.19–0.25 s of a 10 s budget (U10 §2a). Fail-open, exit 0,
  stdout empty by contract (`hooks/stop-failure-marker.sh:31-33`).
- **The request lane**: writer shape `lr-fleet.sh:456-457`, consumer
  `lr-reset-poller.sh:639-661` (reads `.sid .target .source_pane .requested_by`, ignores extra
  keys ⇒ forward-compatible), proven end-to-end 2026-09-14 (U06 §4). Classifier-immune by
  construction — a LaunchAgent is outside every session (`lr-reset-poller.sh:641-643`).
- **`lr-transplant.sh`** — lock, `cp -p`, rsync, sha, tombstone, rename: 0.45 s, 5/5 `ok:true`
  today (U02 §1). Irreversible and correct; unchanged.
- **`hooks/handed-off-session-guard.sh`** + tombstone + `lr-resume-tombstone-guard.bats` — the
  split-brain protections (plan §4). Unchanged.
- **handoff-fire's remote recycle form** — registry binding, transplant evidence, affirmative-only
  typing (`unknown ≠ shell`, `handoff-fire.sh:11610-11619`), composer gate + freshness re-read
  (`:11634`, `:11751`), teardown marker before `/exit` (`:11745`), `it2_type_verified` echo-verified
  typing (`:2282-2323`). Every mechanical step worked 8/8 today (U02 §2d). Unchanged in polarity.
- **`~/.claude/cc-registry/<pane>.json`** — pane→sid→account→cwd→pid, rewritten on every
  SessionStart (`hooks/session-register.sh:282-288`), 0.007 s per pane (U07 §6b), 16/16 joins to
  telemetry (U07 §4). This is the identity index; `lr-fleet --locate` (40–86 s, U14 A1-A2) is not.
- **`~/.claude/autonomy/idl.jsonl`** — every capacity verdict, with `term` and `detail`
  (`capacity-admit.sh:395-420`). The cause of every husk today was here 40 s before the verdict
  (U05 §3.6); the join is what was missing.
- **`resume_engaged` / `lr_engaged_after`** as the *engaged* half of the oracle — kept, but made
  the SECOND predicate behind a *submitted* predicate (§8), because alone it accepted a queued
  `<task-notification>` turn as proof (U03 §0, U11 §0(B)).
- **`bin/claude-accounts --rank / --assign`** — the router; only a `--recovery` modifier is added
  (U13 §4).

---

## 3. Architecture — five stages, one state file per request

```
  limited session                 launchd (outside every session)                 the pane
  ───────────────                 ─────────────────────────────────                ────────
  StopFailure ──► [S0 DETECT]     requests/<sid>.json ──WatchPaths──► poller tick
  arm 2 writes the request        ──► [S1 CLAIM+RANK]  mv → claimed/, one --rank --recovery per pass,
  + latch on death uuid               --assign per pick, cc_capacity_probe (load OFF, NET_ZERO)
  + kind:"limited" beat               → mint ADMISSION TOKEN
                                  ──► [S2 TRANSPLANT]  lr-handoff --in-place: audit·bundle·transplant·
                                      launcher (token + env baked in)            (≈3 s)
                                  ──► [S3 RECYCLE]     handoff-fire --recycle remote form:
                                      composer gate → /exit → shell → type launcher ──────────────► shell runs launcher
                                      poll 0.5 s: cc_alive | relaunch.rc | shell-stable              lr-fire-resume redeems token,
                                                                                                     spawns TUI, READY, injects
                                  ──► [S4 VERIFY]      transcript: user record with nonce (SUBMITTED)  one-line prompt + nonce
                                      then assistant turn after it (ENGAGED) ── state RECOVERED
                                  ──► [S5 REPORT]      results/<sid>.json · pane banner · notify requester
  reaper (every tick + end of drain): any non-terminal state past its bound ⇒ STALE:<stage> + page + re-drive request
```

**The state machine** (append-only, one line per transition, `~/.reso/limit-recover/state/<sid>.jsonl`):

```
requested → claimed → ranked → admitted → transplanted → exit-typed → shell → relaunch-typed
          → gate-admitted → tui-up → ready → submitted → engaged ≡ RECOVERED            (terminal, good)
non-terminal holds:   PARKED:<reason>   HELD:draft                (retried by the next tick / WatchPaths)
terminal failures:    FAILED:<stage>:<cause>                       (paged; re-drive request written when safe)
reaper verdict:       STALE:<last-stage>                           (paged; the driver died or hung)
```

Writers, by stage: the hook (`requested`), the poller (`claimed ranked admitted PARKED STALE`),
`lr-handoff` (`transplanted`), the handoff-fire watcher (`exit-typed shell relaunch-typed tui-up
engaged FAILED:relaunch:*`), `lr-fire-resume` (`gate-admitted ready submitted FAILED:submit`).
All through one 12-line helper (`lr_state_append`, §4 C4), one `printf … >>` of ≤ 1 KB per line
— under the stdio buffer, so O_APPEND stays atomic across concurrent writers
(`docs/lessons/append-atomicity-ends-at-the-stdio-buffer.md`). Existing emitters
(`emit_recycle_event`, `hf_alarm`, `results/<sid>.json`, the IDL) keep writing exactly as today;
the state file is additive and is the ONLY store the reaper and `lr-status` read.

---

## 4. Components — files, functions, lines

Ordered by the stage they serve. "Change at" cites the exact insertion point; "size" is an estimate
of net new/changed lines.

### C1 · S0 DETECT — the request writer (`hooks/stop-failure-marker.sh`, arm 2)

- **Change at** `hooks/stop-failure-marker.sh:130` (after the existing `log_idl fired "marker-…"`,
  before `exit 0`). Append the arm U10 §2g sketches, with these pins:
  - gate on `$ERR` ∈ {`rate_limit`, `rate_limit_error`} — never on text (LR-o: the skill listing
    quotes the limit string in every session, U10 §3d.2); a `server_error` StopFailure has the
    byte-identical envelope and must NOT be transplanted (`docs/plans/NONLIMIT_RESUME_LADDER.md:192-195`).
  - source `scripts/limit-recover/lr-lib.sh`; `lr_last_api_error "$TP"` for the death uuid
    (latch key) and `kind=limit`; **extend `lr_last_api_error` (`lr-lib.sh:129-159`) by two fields**
    — `quotaLimits.resetsAt` and `quotaLimits.rateLimitType` — read off the same tail (all five of
    today's records carried them, U10 §1d). Every caller inherits it.
  - teammate test: `agent_assignee_argv` (`hooks/lib/agent-identity.sh:33`, three-flag conjunction
    over ancestry) OR `head -c 8000 "$TP" | grep -q '"agentName"'` ⇒ write
    `$STATE/teammate-skip/$SID`, no request (U10 §3b; the lead's ingest re-audits its team).
  - latch: `( set -C; : > "$STATE/requests-latch/$SID.$DUUID" )` — per DEATH RECORD, never per sid
    (U10 §2d: `e442434c` fired 4× on two uuids; a sid-keyed latch is fatal for multi-day runs,
    `limit-reset-safety-gate.sh:65`).
  - second guard: skip if `$STATE/locks/$SID.lock` or `$(dirname "$TP")/$SID.HANDOFF.json` exists
    (a re-limit on the dead account after a transplant, U10 §3d.3).
  - pane: `${CC_PANE_ID:-${KITTY_WINDOW_ID:-${ITERM_SESSION_ID##*:}}}` — verified present in the
    CC process env (`ps eww -p 52095` ⇒ `KITTY_WINDOW_ID=112`, U10 §2c).
  - tier: `lr_tier_from_transcript "$CFG" "$SID" | tr ' ' '/'` (79 ms, U10 §2c).
  - origin class: `oi_origin_class "$PANE" "$CWD" "$TP"` (`hooks/lib/origin-identity.sh:237`) —
    a fired peer IS recovered in place (that preserves its custody); only the reporting target
    changes (§9).
  - **also write a `kind:"limited"` beat**: `printf '%s' "$input" | "$_RI_DIR/session-beat.sh" limited`
    (`hooks/session-beat.sh:57` takes `$1` as kind). `cc_sp_active` selects `kind=="prompt"` only
    (`spawn-presence.sh:298-390`), so the limited session stops counting as mid-turn the instant it
    dies instead of until its pid exits — U05 §4.1's husk-counting, closed for 2 lines.
  - wake: `[ "${CC_SF_REQUEST_KICK:-1}" = 1 ] && launchctl kickstart "gui/$(id -u)/com.reso.lr-reset-poller"`
    — **without `-k`**. `-k` kills a running instance first; a drain in flight would die mid-recovery.
    Plain `kickstart` on a running job is a no-op and the running drain's re-scan (C3) picks the
    new file up. This is the sub-second wake until the plist's `WatchPaths` (C2) lands; it kicks an
    already-loaded job and touches no activation surface. Default ON (my conviction 88 % that this
    is inside the agent's remit — it is `kickstart`, not `load`/`unload`/`bootstrap`; if the
    operator disagrees, the flip is one env line and WatchPaths supersedes it either way).
  - request schema (superset of today's; the poller ignores unknown keys):
    ```json
    {"sid":"…","target":"auto","source_pane":"112","requested_by":"stop-failure-marker","ts":"…",
     "mode":"recover","account":"next4","config_dir":"/Users/chrisren/.claude-quaternary",
     "cwd":"…","tier":"claude-fable-5-1/xhigh","transcript_path":"…","death_uuid":"fd4db9e3-…",
     "reset_at_epoch":1789846800,"rate_limit_type":"five_hour","origin_class":"origin"}
    ```
    `mode` ∈ `recover` (transplant + recycle) · `relaunch` (tombstone exists, pane at a shell —
    launcher only) · `drill` (§13).
  - state: `lr_state_append "$SID" requested "pane=$PANE acct=$ACCOUNT reset=$RESET type=$RLTYPE"`.
- **Every path exits 0, stdout empty** — the file's existing contract; a stray byte on the death
  path can be read as a directive (`stop-failure-marker.sh:31-33`).
- **Size**: ~45 lines in the hook, ~6 in `lr-lib.sh`, ~80 in `tests/stop-failure-marker.bats`
  (rows SF-a…SF-h from U10 §2g, each red-provable against the unpatched hook).
- **Measured budget**: +~0.1 s ⇒ ~0.35 s of 10 s (U10 §2c).

### C2 · S0 WAKE — `WatchPaths` on the requests dir (operator step, c10)

- **Change at** `scripts/limit-recover/com.reso.lr-reset-poller.plist:37` (`StartInterval 600`):
  add
  ```xml
  <key>WatchPaths</key><array><string>/Users/chrisren/.reso/limit-recover/requests</string></array>
  <key>ThrottleInterval</key><integer>5</integer>
  ```
  Precedent in this repo: `launchd/com.claude.browse-mirror.plist:16-29` (WatchPaths fast path +
  StartInterval backstop, "the half that survives a quiet fleet"). `StartInterval 600` stays as the
  backstop and as the reaper's cadence. `ThrottleInterval 5` (launchd default 10): five requests
  landing 2 s apart coalesce into one run anyway; 5 keeps a straggler from waiting 10.
- `scripts/launchd-parity-lint.sh` asserts live == SSOT, so the pair cannot drift after install
  (U10 §2e.1). The plan DROPPED this in 2026-09-10 as "an operator step to buy ≤10 min" (plan
  :312-315); U09 gap #15 shows that decision is now the binding constraint on the only
  non-blocking path. It is reinstated.
- **`lr-fleet.sh:463-464`**: stop printing `launchctl kickstart -k …` (the `-k` would kill a
  draining poller); print `lr-status <sid>` instead.
- **Size**: 4 plist lines + 2. Operator step: copy + `launchctl bootout/bootstrap gui/$(id -u)` —
  one `cc-do` row, filed with `--run`.

### C3 · S1/S5 — the poller's drain becomes a concurrent, claiming, reaping driver
(`scripts/limit-recover/lr-reset-poller.sh` §0, `:639-661`)

- **Claim by rename**: `mv "$REQUESTS/$sid.json" "$CLAIMED/$sid.json"` (same filesystem, atomic)
  before anything else; a second poller instance, or a manual `/limit-recover`, cannot double-drive.
  `lr_state_append "$sid" claimed`.
- **Concurrency**: up to `LR_REQ_CONCURRENCY` (default **3**) background workers per pass, each
  `"$FLEET" --one "$sid" --target "$t" --source-pane "$p" --from-daemon --state "$STATE/state/$sid.jsonl"`,
  `wait`ed as a group. Why 3, not 5: a recycle is net-zero on sessions, but each one issues ~10
  `kitty @` RPCs and the socket timed out 1 in 12 calls today (U08 §6) / 1 in 4 `ls` (U07 §5);
  three concurrent recycles keep RPC contention where today's single-stream success rate was
  measured. Env-tunable; the drill (§13) measures 5.
- **Rank once per pass, assign per pick**: one `claude-accounts --rank <lane> --recovery`
  (~0.5–1.1 s, U14 A5) per lane per pass, then `--assign "$t" --src lr-fleet` per pick so N picks
  inside the 90 s cache TTL walk DOWN the ranking (U13 §3c; `bin/claude-accounts:1716-1719`).
  The `--rank` stderr (`route-meta`, exclusions) is saved to `$STATE/runs/<pass>/rank.<lane>.stderr`
  — today it was discarded (`lr-fleet.sh:301` `2>/dev/null`, U13 D2).
- **Re-scan until empty**: after the group finishes, re-glob `requests/`; loop. A request that
  lands mid-drain (WatchPaths cannot re-launch a running job) is drained by the running instance,
  not by the next 600 s tick (U06 §4 gap 2).
- **Off the reset gate**: this whole arm already runs BEFORE §2's `(( now < reset_epoch )) && continue`
  (`:896`), so a request is acted on regardless of reset time — that is the semantic change U06 §5 A
  asks for, and it costs nothing because the request lane is above the gate by construction.
- **Retire on state, not on `lr_transplanted_to`**: at `:902-905` the TRANSPLANTED arm retires a
  parked record when a lock + a target transcript exist — true of every PARTIAL today (U02 §2c,
  "the one daemon that could have caught this does the opposite"). Change the predicate to
  `lr_state_current "$sid" == RECOVERED || lr_registry_live_rows "$sid" (under the target cfg)`;
  otherwise write `requests/<sid>.json` with `mode:"relaunch"` and leave the parked record.
- **The reaper** (new function `lrp_reap`, called after every drain pass and every tick): for each
  `state/*.jsonl` whose last line is non-terminal and older than its stage bound (§7 table) ⇒
  append `STALE:<stage>`, `hf_alarm lr-request-stale`, page once (cause-keyed via
  `hooks/lib/page-damp.sh`), and write a `mode:"relaunch"` (if transplanted) or `mode:"recover"`
  (if not) request so the next pass re-drives it. `fire_fail_note`/`fire_latched`
  (`:251-282`) bound the re-drives at 3 per sid; the third failure pages `needs-human` with the
  state file path. Also: `requests/*.json` older than 2 ticks with no state line ⇒ alarm
  (`REQUEST-SKIP` loop, U06 §4 gap 3); `results/*.json` with `rc != 0` and no `.acked` ⇒ one page.
- **Notify once per fleet event**: on the first claim of a `<error>__<account>` cause key within
  5 min, one macOS notification (`osascript display notification`, the poller's existing
  notify-once at `:1014-1031`): *"next4 five_hour cap — 5 sessions, recovering in place"*.
- **Size**: ~120 lines changed/added; `tests/lr-reset-poller-requests.bats` new (~100): claim
  atomicity under two instances, concurrency cap, re-scan, reaper STALE at bound, retirement gated
  on RECOVERED (red-proof: the unpatched `:902` retires a PARTIAL).

### C4 · the state library + status renderer (new)

- `scripts/limit-recover/lr-state.sh` (~60 lines): `lr_state_append sid state detail` (one
  `printf '{…}\n' >>` of ≤1 KB, jq-encoded), `lr_state_current sid` (`tail -1 | jq -r .state`),
  `lr_state_age_s sid`, `lr_state_is_terminal state`. Sourced by C1, C3, C5, C7, C8, C9.
- `bin/lr-status [sid|pane|--all]` (~60 lines): one line per request — `pane · sid8 · from→to ·
  state · age · cause · next` — from `state/*.jsonl` + `results/`; ≤ 0.1 s. This is what the
  operator (or `/limit-recover`) reads instead of a 40–86 s census.

### C5 · S1/S2 driver — `scripts/limit-recover/lr-fleet.sh` becomes fast and honest

- **`--one SID` must not census** (`lr-fleet.sh:426`): resolve pane/cfg/cwd/tier from the registry
  + store first (the 0.039 s path at `:428-433`, U14 §2.3), run `lf_locate` only on a miss. When
  `--source-pane` is given the census is skipped outright.
- **`lr-lib.sh:20-27`**: dedupe config dirs by `realpath` of `projects/` before the scan
  (`~/.claude-next/projects` is a symlink to `~/.claude/projects`: 421 of 2,579 files scanned
  twice, U01 §1.2, U14 §1.1).
- **`lf_pick_target` (`:294-309`)**: `--rank "$kind" --recovery 2>"$rankerr"`; keep stderr; on an
  empty pick, park with the router's own reasons (`LF_RANK_WHY`), not the tautology at `:313`;
  `--assign` after a non-dry pick (U13 §4c verbatim). Validate the token is a known account name
  (`lib/account-map.generated.sh`), not merely `!= none` (U01 §3.3 c).
- **`lf_capacity_wait` (`:282-291`)**: `CC_ADMIT_LOAD_TERM="${CC_ADMIT_LOAD_TERM:-off}" CC_ADMIT_NET_ZERO=1 cc_capacity_probe lr-fleet …`
  — the same terms the launcher will evaluate (U05 T3), bound `LR_FLEET_CAP_WAIT_S` **120** at
  `LR_FLEET_CAP_IVL_S` **20** (§7); on admit **mint the admission token**
  `cc_capacity_token_mint "$CC_ADMIT_STATE_DIR/tokens/$sid.token" "$sid"` and pass
  `--admit-token` to `lr-handoff` (U05 P2). On park: `lr_state_append … PARKED:capacity:<term>`,
  `parked` row carries `cc_capacity_admit_reason` (U05 P4 companion).
- **The rc-4 arm (`:335-338`)** joins the IDL: last `caller=="lr-fire-resume"` row after `T0` ⇒
  `note="… launcher refuse term=load — <detail>"` (U05 P4). Verdict tokens from the watcher
  (`capacity-refused | vanished | never-engaged | relaunch-write-failed | submit-failed`) land in
  `results.tsv` col 7, since `recycle_await_verdict:11794` already greps them (U14 §4.4).
- **`--locate` DUPLICATE (`:217`)**: subtract registry pids from the resume-proc set exactly as
  `:494-499` already does (U01 §1.3; U09 gap #12).
- **New verb `--request <sid|pane|sid8> [--source-pane N] [--target A] [--mode M]`**: resolves
  via `cc-find` (C10), writes the same request file C1 writes (`requested_by` = the calling
  session's pane so the completion notifies it), latches on the death uuid, kicks the poller,
  prints `lr-status <sid>`, exits 0 in < 1 s. If `launchctl print gui/$(id -u)/com.reso.lr-reset-poller`
  shows the job absent, it says so and offers `--one <sid> --detach` (same drive, `nohup`'d from
  the session, still non-blocking).
- **`--enqueue`** stays as the bulk form of `--request` (already writes the file; now kicks).
- **Size**: ~90 lines; `tests/lr-fleet.bats` +6 cases (registry-first resolve; `--recovery` +
  `--assign` asked; dry run charges nothing; empty rank parks with reasons; rc-4 note carries the
  IDL term; `--request` writes + latches).

### C6 · the capacity gate — one decision, redeemed once (`scripts/lib/capacity-admit.sh`)

- **Admission token** (U05 P2, verbatim design): `cc_capacity_token_mint path sid` (called only
  on a probe ADMIT) and `_cc_admit_token_redeem` (one-shot — unlinked on first read whatever the
  verdict; TTL `CC_ADMIT_TOKEN_TTL_S` **180**; `-O` uid check; names the sid it was issued for;
  **a probe never redeems**). Redemption is recorded as `basis:"token"` with the age, an eighth
  basis value, in the direction `tests/capacity-admit-coverage.bats:336-347` permits. Insert
  after `_cc_admit_state_file` (`:514`) and in `cc_capacity_admit` after the `CC_ADMIT_GATE=off`
  branch (`:565`).
- **`CC_ADMIT_NET_ZERO=1`**: the active term's `+1` at `:832` becomes `+0` — an in-place recycle
  `/exit`s one session and starts one; `handoff-fire.sh:8270` already exempts a recycle for this
  reason and the launcher's second gate double-counted it (U05 §4.2, §5.5 i).
- **Why TTL 180**: the probe→relaunch gap today was 11–16 s (U05 §3.3) and the shell-wait bound in
  §7 is 120 s; 180 = 120 + 60 margin. A token older than that is stale by construction and is
  consumed, not honoured.
- **Why this is not a bypass**: minted only by an evaluation that ADMITTED with every term except
  load ON; grants at most one spawn per probe-admit; expires; cannot be replayed onto another sid;
  and the operation it admits is net-zero. `capacity-admit.sh:149-160` already prices the load term
  as wrong-input and it is OFF on the operator's own fire (`handoff-fire.sh:6075`) and the Agent
  tool (`agent-teams-enforce.sh:229`); this design applies that verdict to the two unattended
  recovery callers its own header names (U05 §2.2).
- **Size**: ~50 lines; `tests/capacity-admit.bats` + T1/T1b/T1c (token), T4/T4b (net-zero) from
  U05 §6, each shown red against the unpatched lib.

### C7 · S2 — `scripts/limit-recover/lr-handoff.sh`: the launcher carries the decision

- **The heredoc (`:586-593`)** gains, beside the two exports it already has:
  ```bash
  export CC_ADMIT_LOAD_TERM="${CC_ADMIT_LOAD_TERM:-off}"   # capacity-admit.sh:149-160 — wrong input, off on every other spawn surface
  export CC_ADMIT_NET_ZERO=1                               # the /exit above made this net-zero
  ${ADMIT_TOKEN:+export CC_ADMIT_TOKEN=$(printf '%q' "$ADMIT_TOKEN")}
  export LR_STATE_FILE=$(printf '%q' "$STATE_FILE") LR_RUN_DIR=$(printf '%q' "$BUNDLE")
  ```
  and replaces `exec …` with
  ```bash
  … lr-fire-resume.sh … ; rc=$?; printf '%s\n' "$rc" > "$BUNDLE/relaunch.rc"; exit $rc
  ```
  `lr-fire-resume` ends in `exec $SHELL -l -i` on the success path (`:598-606`), so the `rc` line
  runs ONLY when the launcher died before the TUI — which makes `relaunch.rc` a positive
  discriminator for "gate refused / arg error", the exact fact the watcher could never see (U04
  §0 third finding). `lr-fire-resume` also writes its own state lines (C8), so `relaunch.rc` is
  belt to that brace.
- **Live-parser preflight (`:496-509`)** extended: also grep the LIVE `lr-fire-resume.sh` for
  `CC_ADMIT_TOKEN` and `LR_STATE_FILE`, and the live `capacity-admit.sh` for
  `_cc_admit_token_redeem` — refuse (exit 5) before the transplant if the live layer cannot run
  what this script writes. This is the plan §6's own cure, applied to this wave (U09 gap #14).
- **Ingest prompt (`:464`)**: run `scripts/limit-recover/lr-ingest-verify.sh "$BUNDLE"` (new,
  ~50 lines, U12 §6.1 clauses A–D, receipt to `$BUNDLE/INGEST-VERIFIED.txt`); on rc 0 the prompt is
  the ONE-LINE non-slash text of U12 §6.2 **plus a nonce** `lr:<sid8>:<TS>` at its end; on rc ≠ 0
  it stays `/limit-recover ingest $BUNDLE — lr-ingest-verify FAILED: <clause>` (fail-closed, the
  degraded path named in the prompt). A non-slash prompt removes the autocomplete CR-swallow class
  outright (U03 (b), `handoff-fire.sh:6867`) and the 41 KB command body from resident context
  (U12 §3).
- **`HANDOFF-CONTEXT.md` (`:404-410, :443-444`)**: emit only the LAST DoD entry plus a pointer to
  the store (86,888 B → ~1 KB, U02 §4); **drop `source_argv`** from the manifest (`:366, :472,
  :477`) — 86 % of the file and wrong about the tier in 3/5 cases; `runtime_model/effort` stay.
- **`--in-place` from the daemon**: when `--from-daemon` (or `--state` given), pass
  `--source-pane … --source-session …` **without `--await`** (`:621`); the verdict arrives through
  the state file and the poller's worker reads it. The interactive `--one` keeps `--await`.
- **State**: `lr_state_append transplanted "to=$TCFG bundle=$BUNDLE"` after `:519`.
- **Size**: ~70 lines + `lr-ingest-verify.sh` ~50; `tests/lr-handoff-launcher-quoting.bats` +4
  (env block present and `%q`-rendered; preflight refuses on a token-less live lib; fastpath prompt
  carries the nonce; fail-closed prompt names the clause).

### C8 · S3/S4 — `scripts/limit-recover/lr-fire-resume.sh`: state, not screen

- After the gate (`:324-330`): `lr_state_append gate-admitted "$(cc_capacity_admit_reason)"`; on
  refusal, `lr_state_append "FAILED:gate:${CC_ADMIT_TERM:-?}" "$(cc_capacity_admit_reason)"` before
  `exit 9`. The refusal text is still printed into the pane (`:325`) — now it is ALSO a row.
- `LR_RE_READY` (`:384`): drop the dead `shift+tab to cycle` alternative (0 hits in 2.1.260, U03
  (a)); keep `auto mode on` | `for shortcuts`; add the **quiet-pty fallback** — replace `timeout {}`
  at `:560` with an 8 s settle arm that injects anyway and logs `ready-by-quiet` (version-proof; a
  status-line phrase is not). On neither within `timeout 300`: `send_user "✗ READY NEVER SEEN — prompt NOT typed: …"`,
  `lr_state_append FAILED:ready`, exit 11.
- Injection (`:549-558`): keep `\025` + text + `\r`; the three fixed sleeps (2+1+1 s) become
  0.3+0.2+0.2 (U14 item 7; the READY match already proves the composer exists).
- **Replace `:563-583` (the dead `esc to interrupt` oracle)** with the transcript probe (U03 (4)):
  `scripts/limit-recover/lr-submit-probe.sh <cfg> <sid> <t0> <token>` (new, ~25 lines: a
  `type:"user"` record after `t0` whose content contains `<token>` — the nonce, or the bundle path
  for the slash form — exit 0/1; a `tail -c 400000` scan, 19 ms on 12 MB, U08 §6). Poll 1 s ≤ 30 s;
  then ONE re-CR and 10 s more; success ⇒ `lr_state_append submitted`; failure ⇒
  `lr_state_append FAILED:submit "prompt=<text>"`, `send_user` the prompt, **exit 12**, TUI left
  alive (nothing is lost — the pane holds a live session with an empty composer).
- `lr-preseed-env.sh:115-117`: add `fullscreenUpsellSeenCount` / `fullscreenDownsellSeenCount` to
  `UPSELL_FLOOR` (the keys exist in the binary, sit at 3 in `.claude-secondary/-tertiary`, U03 §2)
  — remove the question instead of answering it.
- **Size**: ~80 lines + probe ~25; `tests/lr-fire-resume-submit.bats` new (~60): probe finds the
  nonce in a fixture transcript; probe ignores a `<task-notification>` user record without it;
  READY-quiet fallback injects; `exit 12` on no record.

### C9 · S3 — the recycle watcher names its failure in seconds (`scripts/handoff-fire.sh`)

- Accept `LR_STATE_FILE` (env, or a 14th positional) and a 6-line `rcy_state()` that appends when
  set. Called at: `/exit` typed (`:11761-11768` → `exit-typed`), shell confirmed (`:6754` →
  `shell`), relaunch typed (`:6800` → `relaunch-typed`), process up (`:6843` → `tui-up`), engaged
  (`:6848` → `engaged`), every failure branch.
- **Replace `:6811-6816`** (45 s + one retype + 45 s) with a 0.5 s poll, bound
  `HF_RECYCLE_BOOT_WAIT_S` **20**:
  ```sh
  for _ in $(seq 1 40); do
    cc_alive && { up=1; break; }
    [ -s "$LR_RUN_DIR/relaunch.rc" ] && { rcy_verdict="launcher-exited:$(cat "$LR_RUN_DIR/relaunch.rc")"; break; }
    [ "$_" -ge 6 ] && at_shell && { sleep 0.5; at_shell; } && { rcy_verdict="shell-stable"; break; }
    sleep 0.5
  done
  ```
  The `≥ 3 s` floor before trusting `at_shell` and the two-sample rule are required: `pane_cc_state`
  classifies `bash` as `shell` (`:3568`) and the launcher's own bash prologue IS bash for ~2 s
  (U04 §5 C). **No retype**: with the token and the load term off, a refusal is real, and today's
  retype re-ran the identical command against a counter advanced by one (U02 §2d "the retype is
  provably useless"). 20 s = 5× the ~4 s TUI boot (U14 §2.2, labelled inference).
- **The `no claude process` branch (`:6878-6880`)** — the only terminal arm with no row and no
  alarm (U04 §3) — gains, before its `exit 1`: the IDL join (last `caller=="lr-fire-resume"` row
  after `RCY_T0` ⇒ `term`, `detail`), `emit_recycle_event recycle-dead 0 "$RSID" "…"`,
  `goal_unreachable recycle-dead`, `hf_alarm recycle-relaunch-refused …` naming the cause and the
  relaunch command (the 3 lines U04 §3 gives), `rcy_state "FAILED:relaunch:${term:-unknown}"`, and
  a **`mode:"relaunch"` request** written back to `requests/` so the poller re-drives it (§10).
  The message prints the real elapsed seconds and the verdict token, never a fixed "90s".
- **Engagement (`:6845-6860`)**: in resume mode require `lr-submit-probe` (user record with the
  nonce, or the bundle path) AND THEN `resume_engaged` with `t0` = that user record's timestamp —
  so a queued `<task-notification>` turn can no longer satisfy it (U03 §0, U11 §0(B)).
  `RCY_ENGAGE_INTERVAL` 5 → **1** (a 19 ms tail read, U14 item 9). `RCY_ENGAGE_TIMEOUT` stays
  180 (§7).
- **Shell wait**: `HF_RECYCLE_SHELL_WAIT_S` is passed as **120** by `lr-handoff` on this path (env,
  not a global change): measured 3–15 s in 8/8 logs (U04 §1), a limit-blocked TUI takes `/exit`
  on its live input loop (plan §7.1); 120 covers the 60 s CR nudge (`:6682`) and the 15 s vanish
  probes. Poll quantum `:6619` 3 s → 0.5 s.
- `recycle_await_verdict` (`:11786-11805`): the failure grep gains `submit-failed|launcher-exited`;
  `HF_RECYCLE_AWAIT_IVL` 5 → 0.5 (it is a `grep` of a log).
- **Size**: ~70 lines; `tests/handoff-recycle-remote-resume.bats` +5 (rc-file short-circuit in
  ≤3 s with the IDL term in the alarm; no retype; shell-stable verdict; engagement refuses a
  notification-only turn; state lines in order). Plus the arithmetic ratchet U05 T2 rewritten for
  the new shape: `HF_RECYCLE_BOOT_WAIT_S ≥ 3 × the measured boot` is asserted, not the attempt
  count.

### C10 · R6 — identity on the statusline and a 0.3 s resolver

- **`statusline.sh`** (a copy-deployed real file, NOT a symlink — `install.sh`/`deploy-live` must
  run it out, U07 §1): after `:86`, `ID_SEG="⌗${KITTY_WINDOW_ID:-${ITERM_SESSION_ID##*:}} ${PAY_SID:0:8} "`,
  emitted at `:486` between `GLYPH_PREFIX` and `PCT_SEG` — left-anchored so it survives the 30-col
  panes (9 of 16 today truncate the sha and effort, U07 §2b). 0 forks, +1.2 ms/render, +14 cols
  (U07 §3c). `⌗` (U+2317) is outside the East-Asian-Ambiguous set the file documents kitty
  downsampling (`:365-397`); `#` is the fallback — pin at the operator's eyes in a real 30-col pane
  before landing, per that block's four reverted glyphs. Telemetry row (`:149-156`) gains `pane`,
  `session_name`, `rate_limits` — same `jq`, 0 forks — so `/tmp/cc-telemetry/<sid>.json` becomes
  the live-state half of the join and a pane's own approach to the wall is visible.
- **`bin/cc-find <pane|sid8|"tuple"|keyword>`** (new, ~80 lines from `scratchpad/lr/cc-find-full.sh`,
  U07 §6b): pane id → 0.007 s; sid8 → 0.012 s; tuple `{acct#, cwdbase, effort, pct}` → 0.18 s
  ranked by `|pct − live|`, **REFUSES and prints both rows when the top two are inside the p90
  drift for the screenshot's age** (12 points at 40 min, U07 §4) — never on sha (it moves under the
  session) and never exactly on pct; keyword → 0.6 s over the first user prompt + registry `name` +
  telemetry `session_name`. Liveness by `kill -0 registry.pid` (26 rows vs 16 live panes today,
  U14 §3.2), never by telemetry age. Every `kitty @` call bounded 3 s, retried ×3, and a timeout
  is INDETERMINATE (U07 §5, U08 §6). Output: one TSV row `pane sid account cwd pid alive tier topic`.
- `tests/statusline-identity.bats` layer 2 + 2 assertions (id segment present; survives a 30-col
  cut); `tests/cc-find.bats` new (~50: pane exact; sid8; tuple refusal on the 122/124 fixture;
  keyword).
- **Size**: 10 lines in statusline, ~80 in cc-find, ~70 tests.

### C11 · R-target — the ranker's recovery lane (`bin/claude-accounts`, `accounts.json`)

U13 §4 verbatim: `--recovery` modifier (never a fourth lane) adding `RECOVERY_W_FLOOR 0.10`,
`RECOVERY_S_CEIL 0.60` (reuses `DESK_5H_FLOOR`; note `S_CUT 0.85` is already stricter than the
0.90 first proposed), `RECOVERY_F_FLOOR 0.05` in `_excluded`/`score_fable`; reasons
`recovery-weekly-thin | recovery-5h-thin | recovery-fable-thin` classed POLICY (an all-thin fleet
exits 2 and the driver parks loudly); kill `CC_ROUTE_RECOVERY=off` byte-identical. Applied to
today's 17:00 Z snapshot: `next` (98 %) and `next4` (92 %) excluded, `next3` first — and `next`
reached weekly 100 % 1 h 54 m after the dry run named it (U13 §3a). `route-meta` gains
`recovery=1|0`. Size ~40 + `tests/account-recovery-lane.bats` (~60, the eight cases in U13 §5 with
their three mutation arms).

### C12 · the manual fallback — `commands/limit-recover.md`

Rewrite the interactive entry as three lines and delete the polling: (1) `cc-find "<pane|sid8|
keyword>"` — for a screenshot, read `⌗<pane> <sid8>` off the line; if the tuple resolver refuses,
print its two candidates and STOP-ASK (never guess: an ambiguous identification that picks one is
how a wrong pane gets recycled, U07 §6c); (2) `lr-fleet --request <sid> --source-pane <pane>`;
(3) **end the turn** — the daemon does the work and `cc-notify` wakes this session with the verdict
(the `task-notification` path already wakes to the second; the lead must stop pre-empting it, U11
§2/§8.5). `lr-status` is the read. Ingest mode: with the fastpath prompt there is nothing to
ingest; the paranoid case is `cat <bundle>/INGEST-VERIFIED.txt` (1 call), the full ingest stays
for `gaps > 0`. Banned by name in the doc: foreground `until` loops, `cc-pane send`,
`it2 session send/run` for messages, `kitty @ send-key` (U08 §3). Size: −30 K chars.

---

## 5. CLI surface — static, repeatable, file-backed

| command | what | blocks for | verdict lives in |
|---|---|---|---|
| *(none — automatic)* | StopFailure → request → daemon | 0 | `state/<sid>.jsonl`, `results/<sid>.json` |
| `cc-find <pane\|sid8\|keyword\|tuple>` | identify | ≤ 0.3 s | stdout TSV; rc 2 = ambiguous (rows printed) |
| `lr-fleet --request <sid> [--source-pane N] [--target A] [--mode recover\|relaunch\|drill]` | file a request and wake the daemon | < 1 s | `requests/<sid>.json` → state |
| `lr-status [sid\|pane\|--all]` | one line per request | ≤ 0.1 s | reads `state/` |
| `lr-fleet --one <sid> --detach` | drive from a session when the daemon is absent | < 1 s (nohup) | same state file |
| `lr-fleet --one <sid>` / `--recover` | the old synchronous drive (emergency; now ~35 s not 150) | ≤ 3 min | same |
| `lr-fleet --locate` | the deep census (`--deep`), for audits only | 40–86 s today; C5 makes it ~1 s | stdout |
| `bash <bundle>/…/lr-launch-<sid8>-*.sh` | the launcher, by hand, in the pane (last resort) | — | `relaunch.rc`, state |

Every verdict is a file a `cat` can read; every command has a fixed argv; nothing in the chain
asks a question.

---

## 6. State store layout (`~/.reso/limit-recover/`, existing `LR_STATE_DIR`)

```
requests/<sid>.json            the request (C1/C5 write; C3 claims by mv)          exists
claimed/<sid>.json             claimed request, deleted on terminal state           new
requests-latch/<sid>.<uuid>    O_EXCL latch per DEATH RECORD                        new
state/<sid>.jsonl              append-only transitions (§3), the reaper's SSOT       new
results/<sid>.json / .log      final verdict {sid, rc, ts, log, requested_by, state_file, cause}   exists (+2 keys)
results/<sid>.acked            the page for a non-zero result was sent               new
runs/<pass-ts>/rank.<lane>.stderr   the ranker's reasons for that pass               new
locks/<sid>.lock               split-brain lock (lr-transplant)                     exists
parked/<sid>.json              the reset-poller's own ledger                         exists
teammate-skip/<sid>            lead-owned, never requested                           exists
<sid>/bundle-<ts>/             audit.json audit.md MANIFEST.json HANDOFF-CONTEXT.md (last DoD only)
                               INGEST-VERIFIED.txt relaunch.rc lr-launch-*.sh (moved here from $TMPDIR)   exists (+3 files)
~/.claude/autonomy/capacity-admit/tokens/<sid>.token   one-shot admission token       new
```

The launcher moves from `$TMPDIR` (a `/var/folders` path this box wipes at boot, and today all
five are still there uncleaned, U02 §2b) into the bundle, beside the receipt it produces.

---

## 7. Every timeout, with its justification

| stage | bound | poll | why this number |
|---|---|---|---|
| StopFailure hook | 10 s (harness) | — | exists; arm 2 uses ~0.35 s (U10 §2a) |
| WatchPaths → poller start | ~1 s; `ThrottleInterval` 5 | — | launchd; bursts coalesce (C2) |
| kickstart fallback | immediate | — | no-op on a running job; drain re-scan covers it |
| drain concurrency | 3 workers | — | kitty socket 1-in-12 timeouts (U08 §6); env-tunable, drill measures 5 |
| rank | 15 s | — | `claude-accounts` 0.5–1.1 s (U14 A5); its own `--max-wait` |
| capacity probe | **120 s** total, 20 s interval | 6 probes | with load OFF and NET_ZERO the remaining refusable terms are headroom (0 of 127 refusals ever, U05 §7.4) and segments (3 % today); 120 s covers a transient segment spike without holding a worker slot for 10 min (today: 658 s foreground, U05 §3.1). Past it: `PARKED:capacity:<term>` + page; the tick re-probes |
| admission token TTL | 180 s | — | shell-wait 120 + 60 margin (C6) |
| transplant | 60 s sanity | — | 0.45 s measured; 241 MB worst ≈ 5 s (U14 §1.3) |
| composer gate (operator draft) | 180 s, 15 s | — | unchanged (`:11634`); a draft is the operator's; state `HELD:draft` says why |
| /exit → shell | **120 s** | 0.5 s | 3–15 s in 8/8 logs (U04 §1); one CR nudge at 60 s |
| relaunch typed → tui-up / rc / shell-stable | **20 s** | 0.5 s | boot ~4 s (labelled inference, U14 B); rc file lands in ~2 s on refusal (U04 §0); no retype |
| READY | 300 s expect global; quiet-pty 8 s | — | READY typically < 5 s; 8 s of silence means the TUI settled (C8) |
| inject sleeps | 0.3 + 0.2 + 0.2 s | — | READY already proved the composer (U14 item 7) |
| submit probe | 30 s, then one re-CR + 10 s | 1 s | the user record is written at submit time, sub-second (U03 §4); 30 s absorbs a slow disk flush; one re-CR is the whole retry budget (blind CRs accept dialogs, U03 (c)) |
| engagement | 180 s | 1 s | one model round trip on a ~365 K context, 15–60 s observed; 3× the max (U04 §1 W8a) |
| result → notify requester | ≤ 1 s | — | `cc-notify` |
| reaper stage bound | stage bound + 60 s | per tick + end of drain | a driver that died leaves a non-terminal line; +60 s keeps a slow-but-alive stage from being paged |
| whole request | 15 min | — | 2 × (worst loaded case 155 s) + a full tick; past it, STALE + page regardless |
| re-drive budget | 3 per sid (`fire_fail_note`) | — | exists (`:251-282`); the 3rd failure pages `needs-human` with the state path |

Today's constants that these replace, and why each was wrong: `LR_FLEET_CAP_WAIT_S 600` (a
foreground sleep in the lead's tool call, U05 §3.1); `seq 1 15 × sleep 3 × 2` (88 s of polling a
corpse, U04 §0); `RCY_ENGAGE_INTERVAL 5` and `HF_RECYCLE_AWAIT_IVL 5` (each adds up to 5 s to a
verdict that is a `grep`); `esc to interrupt` × 5 × 6 s (a dead oracle, 30 s on every resume, U03
(b)); `HF_RECYCLE_SHELL_WAIT_S 600` (40× the max observed).

---

## 8. Verification per step — transcript evidence over screen-scraping

| step | verified by | screen used for |
|---|---|---|
| requested | `requests/<sid>.json` exists; `state` line; IDL `stop-failure-marker fired request-written` | — |
| claimed | `claimed/<sid>.json` (atomic mv) | — |
| ranked/admitted | `runs/<pass>/rank.*.stderr`; IDL `lr-fleet probe admit` row; token file exists | — |
| transplanted | `transplant.json ok:true`, sha match (exists); tombstone + lock | — |
| exit-typed / shell | `pane_cc_state == shell` affirmative (exists) | the ONLY screen read that is load-bearing, and it is affirmative-only |
| relaunch-typed | `it2_type_verified` nonce echo (exists) | echo read-back, CR only on match |
| gate-admitted | `state` line from `lr-fire-resume`; IDL `basis:token` row | — |
| tui-up | `cc_alive` (process on the tty) | — |
| ready | `state` line (`ready` / `ready-by-quiet`) | expect's status-line match (fallback: quiet pty) |
| **submitted** | `type:"user"` record after `t0` containing the nonce, in the TARGET transcript | — |
| **engaged** | non-error, content-bearing `type:"assistant"` record after THAT user record | — |
| RECOVERED | `state` terminal + `results/<sid>.json rc 0` + registry row under the target account with a live pid + kitty window id unchanged | `kitty @ ls --match id:N` (37 ms) |
| any FAILED | `state` line with stage + cause; alarm file; page | pane tail quoted into the alarm (`get-text --extent screen`, bounded) — evidence, not the verdict |

The two oracles that replace today's: **submitted** (new — today nothing owned "a prompt is
sitting unsubmitted", U09 gap #11) and **engaged after submitted** (today `resume_engaged` accepted
`No response requested.`'s sibling — a notification turn — as engagement on 2 of 5, U11 §0(B)).

---

## 9. What the operator sees

- **Common case (zero-touch)**: the limited pane prints its limit line, ~10 s later the TUI exits
  to a shell, ~5 s later a new TUI boots, the composer receives the one-line resume text and
  submits; the launcher prints one banner before exec:
  `⟳ limit-recover: next4 five_hour cap → resumed in place on next3 · same session d02d8feb · request→engaged 31 s · lr-status d02d8feb`
  One macOS notification per fleet event (cause-keyed): *"next4 five_hour cap — 5 sessions,
  recovering in place"*; one on completion: *"5/5 recovered (next3 ×3, next2 ×2), 71 s"*. No
  screenshot, no command, no lead session.
- **A failure**: a page (`cc-notify --page`, desk role) + macOS notification, one line:
  `⛔ limit-recover d02d8feb pane 112: FAILED:gate:segments after transplant — pane at a shell; re-drive queued (2 of 3); bash …/lr-launch-d02d8feb-*.sh to run it by hand · lr-status d02d8feb`
  and the same line as a `#` comment in the pane (exists, `:6878`). A fired peer's failure pages its
  ORIGINATOR (from `cc-fired/<pane>.json`), because a custody debt is what would strand.
- **A stall**: `⚠ limit-recover 09e64dcb: STALE at relaunch-typed for 6m — driver gone; re-drive queued · lr-status`.
- **`lr-status --all`** at any time:
  ```
  PANE  SID8      FROM→TO      STATE                    AGE    CAUSE / NEXT
  112   d02d8feb  next4→next2  RECOVERED                31s    —
  111   09e64dcb  next4→next3  engaged                   9s    —
  121   e442434c  next4→next3  PARKED:capacity:segments 40s    re-probe on next pass · segments 51% (ceiling 50)
  ```
- **Manual path**: they paste `⌗112 d02d8feb` (or a screenshot the session reads it from) into
  `/limit-recover`; the session runs two commands and ends its turn in < 3 s; the notification
  arrives when the daemon finishes.

---

## 10. Fault tolerance — every way it can go wrong, and what names it

| failure | detected by | within | named as | automatic remedy |
|---|---|---|---|---|
| hook cannot write the request (dir unwritable, no jq) | IDL `abstained req-write-failed` | 0 s | marker still written; the poller's DETECT arm parks it at the next tick | tick fallback (≤ 600 s) — **degraded, never lost** |
| poller not loaded / dead | `lr-fleet --request` checks `launchctl print`; `desk-invariant` sweeps the LaunchAgent | request time / tick | `⛔ poller absent` + `--one --detach` offered | manual drive (non-blocking) |
| WatchPaths does not fire (job running) | drain re-scan | end of the running pass | — | re-scan + 600 s tick |
| ranker empties (all thin) | `--recovery` exit 2 | 1 s | `PARKED:no-target: next=recovery-weekly-thin; …` + page | re-rank each tick; reset-poller's own wait-for-reset arm is the floor |
| probe refuses 120 s | state | 120 s | `PARKED:capacity:<term>` + page | re-probe each tick; session untouched (never /exit'ed) |
| transplant fails (sha, lock exists) | `lr-transplant` rc 2 | < 1 s | `FAILED:transplant:<msg>` + page | none automatic — a lock means another writer; human reads it |
| composer holds an operator draft | composer gate | 180 s | `HELD:draft "<text>"` | re-drive each tick; session untouched |
| /exit not taken in 120 s | watcher | 120 s | `FAILED:exit:not-taken` + alarm; session still alive | re-drive (3 max) |
| launcher refused (gate) | `relaunch.rc` = 9 + IDL row | ≤ 2 s | `FAILED:gate:<term> — <detail>` + alarm + page; **husk recorded** | `mode:relaunch` request → WatchPaths → re-drive in seconds; token re-minted by a fresh probe |
| launcher arg error / live layer behind | `relaunch.rc` ≠ 0,9 | ≤ 2 s | `FAILED:relaunch:rc=<n>` + pane tail | preflight (C7) makes this pre-transplant; if it still happens: re-drive after `deploy-live` |
| TUI never READY | expect 300 s / quiet 8 s | ≤ 300 s | `FAILED:ready` exit 11; TUI alive | one re-drive (relaunch); then needs-human |
| prompt not submitted | submit probe | 40 s | `FAILED:submit` exit 12; TUI alive, composer holds the text | re-drive types the prompt only (mode `prompt`) — or the operator presses Enter; page names it |
| submitted, never engaged | engagement 180 s | 180 s | `FAILED:engage` + `recycle-dead` alarm (exists) | none automatic (a live session mid-something must not be interrupted; `:6861-6866`); page |
| re-limited on the target | `resume_engaged` excludes `isApiErrorMessage`; the target's OWN StopFailure writes a NEW request | sub-second | new `requested` line, `from=next3` | the lane recurses; `--recovery` floors make it rare; `fire_fail_note` bounds it at 3 |
| driver dies mid-recovery | reaper | stage bound + 60 s | `STALE:<stage>` + page | re-drive (`relaunch` if transplanted else `recover`) |
| two drivers (manual + daemon) | claim mv; transplant lock; `/limit-recover` reads state first | 0 | second driver prints the state and exits | — |
| teammate limited | `agent_assignee_argv` / `agentName` | 0 | `teammate-skip/<sid>` | lead's ingest re-audits (exists) |
| kitty socket i/o timeout | bounded RPC ×3 | ≤ 9 s | INDETERMINATE, retried; never "pane gone" | retry; then `FAILED:pane:unreachable` |

The invariant the design can promise: **no request reaches a terminal state without a row, and
no non-terminal request survives its bound without a page and a re-drive.** Today: 4 dangling
`recycle-intent` rows, 0 alarms, 0 re-drives (U01 §4.1).

---

## 11. The four constraints the brief names, and how each is held

- **Never two writers on one uuid** — latch per death uuid (C1); claim-by-rename (C3); the
  transplant lock (exists); the tombstone + guard (exists); `/limit-recover` reads state before
  acting (C12); the poller's retirement keyed on RECOVERED, not on "a lock and a file" (C3).
- **Never `/exit` a pane the relaunch cannot be admitted into** — the probe and the launcher
  evaluate the SAME terms (C5 ↔ C7, ratchet T3), the probe's admit is carried as a one-shot token
  the launcher redeems (C6), and the operation is net-zero. Residual: a token older than 180 s is
  refused and the relaunch evaluates fresh with load OFF — a genuine refusal there is recorded in
  2 s and re-driven (§10), never a silent husk.
- **Teammates are lead-owned** — C1's two-oracle test; `teammate-skip/`; SF-e is the fixture that
  establishes whether StopFailure fires inside an assignee at all (unmeasured today, U10 §3c).
- **The capacity gate protects the box** — headroom, segments, active (net-zero), all three
  reserve terms stay ON; only the load term is OFF, per the library's own retraction
  (`capacity-admit.sh:16-27, 134-160`) and the two surfaces already running that way. The budget
  is not widened; the token cannot admit what the gate did not admit ≤ 180 s earlier.

---

## 12. Latency and token budget

**Zero-touch, one session, idle box** (each line's source in brackets):

```
limit record written ................................  0.0 s
StopFailure → request file + kick ...................  +0.4   [U10 §2a/§2c]
WatchPaths / kick → poller running ..................  +1.0   [launchd; kick ~0.2]
claim · rank(once) · probe · token ...................  +1.5   [U14 A5]
audit · bundle · transplant · launcher ...............  +3.0   [U02 §1]
composer freshness · /exit typed .....................  +1.5   [:11751-11772]
TUI teardown → shell confirmed (0.5 s poll) ..........  +3.5   [U14 §2.2 step 7]
relaunch typed (echo-verified) .......................  +1.0   [:2282]
token redeem · expect spawn ..........................  +0.5
TUI boot → READY .....................................  +5.0   [U14 §2.2 step 9, inference]
inject · CR · user record on disk ....................  +1.5
first assistant turn .................................  +14    [irreducible, U14 §2.2 step 12]
engaged → RECOVERED · notify .........................  +0.5
                                                       ─────
                                                       ≈ 33 s   (today: 115–158 s; 658 s parked)
```

Five sessions, concurrency 3: two waves ≈ **70 s** (concurrency 5: ≈ 40 s). Under load:
+ ≤ 120 s of probe retries ⇒ ≤ 155 s.

**Tokens**: zero-touch — 0 lead tokens (today: 269 K output + 88.9 M cache-read on the lead,
U11 §1). The recovered session pays its unavoidable cache-create (~0.6 M raw for a 365 K context)
and 1 message / 0 tool calls / ~0.1 K resident on the fastpath (today: 6–9 round trips, 3.8–5.7 M
raw, ~26.5 K resident, U12 §3, §6.3). Manual path: one lead turn of two Bash calls (~1 cache read).

**Identification**: pane id 0.007 s · sid8 0.012 s · tuple 0.18 s · keyword 0.6 s (U07 §6b) —
against `cc-sessions` 30–41 s and `lr-fleet --locate` 40–86 s.

---

## 13. Acceptance — the 5-session drill (`tests/lr-drill.sh`, run by a human once per land)

Setup: five throwaway sessions on ONE account, each in its own kitty pane, each having taken one
real turn (the plan's E2E shape, plan :270-287, but n = 5 and the box under a deliberate
`nice -n 19 taskpolicy -c background bats` load like today's, so the load term WOULD refuse).
A real 429 cannot be forced, so the drill files `mode:"drill"` requests
(`lr-fleet --request <sid> --mode drill` ×5 in one second) — every later stage is byte-identical
to the real path except that `lr-ingest-verify` accepts a non-limit `last_api_error`.

Expected, all read from files, none from the screen:

| measure | expected |
|---|---|
| `requests/` → first `claimed` line | ≤ 2 s (WatchPaths) or ≤ 1 s (kick) |
| per-session `requested` → `RECOVERED` | p50 ≤ 40 s, max ≤ 90 s |
| all five RECOVERED (wall) | ≤ 100 s at concurrency 3; re-run at 5 and record |
| `results/*.json rc` | 0 ×5 |
| kitty window count before == after (`kitty @ ls \| jq length`) | equal |
| registry `account` changed, `session_id` unchanged, `pid` alive | 5/5 |
| target transcript: user record with the nonce, then a non-error assistant record | 5/5 |
| `handoffs.jsonl`: every `recycle-intent` has a terminal row | 5/5 |
| `state/*.jsonl`: transitions in §3 order, no gaps, every line ≤ 1 KB | 5/5 |
| target picks spread (`--assign` phantoms) | ≥ 2 distinct accounts across 5 |
| `rank.*.stderr` present per pass | yes |
| notification to each `requested_by` pane | 5 `cc-notify` rows |
| IDL: 0 `lr-fire-resume refuse term=load` rows | 0 |
| launcher files in `$TMPDIR` | 0 (they live in the bundle now) |

Then three injected faults, each expected to be NAMED and RE-DRIVEN, never silent:

1. **Gate refusal after transplant**: drill flag sets `CC_ADMIT_HEADROOM_OVERRIDE=0` inside one
   launcher ⇒ `FAILED:gate:headroom` within 3 s of `relaunch-typed`; alarm class
   `recycle-relaunch-refused` with the IDL detail; a `mode:relaunch` request appears; lift the
   override ⇒ RECOVERED on the re-drive ≤ 30 s later; `fire_fail_note` count 1.
2. **Driver killed mid-recovery**: `kill` the worker between `transplanted` and `exit-typed` ⇒
   reaper marks `STALE:transplanted` at bound+60 s, pages once, re-drives ⇒ RECOVERED.
3. **Held draft**: type a draft into one composer before the drill ⇒ `HELD:draft "<text>"`, the
   session untouched, RECOVERED after the draft is cleared, no `/exit` merged into the draft
   (`handoffs.jsonl` has no `recycle-held-draft` … exit merge).

Pass = every row above at its number, 0 husks, 0 rows without a terminal, and the whole drill
readable afterwards from `lr-status --all` alone.

---

## 14. Deliberately NOT changed, and why

- **`lr-transplant.sh`** — 0.45 s, sound, irreversible in the right order. The two `python3 -c
  realpath` starts and the second `shasum` (U14 item 15, ~0.12 s) are not worth touching a
  correctness-critical file for.
- **The split-brain protections** — tombstone, `handed-off-session-guard.sh`, the SUPERSEDED
  verdict, `lr-resume-tombstone-guard.bats`. Plan §4 forbids weakening them; nothing here needs to.
- **handoff-fire's recycle predicates** — `hf_remote_source_bind/pin`, `hf_transplant_evidence`,
  `unknown ≠ shell`, the composer gate's polarity, `it2_type_verified`. They worked 8/8 today; the
  failures were downstream of them.
- **`capacity_gate()` for fires** and the exemption at `handoff-fire.sh:8270` — correct; the
  design mirrors the exemption downward rather than removing it.
- **`cc_sp_active` reading `kind:"prompt"` beats** — C1's `kind:"limited"` beat makes the limited
  session stop counting; the deeper fix (transcript-aware census) stays a separate unit (U05 §5.5 ii)
  because the census must remain one `jq` + ≤ 2 `ps` (its biggest caller holds a PreToolUse slot).
- **The ranker's γ = 2 urgency** — correct for dispatch (U13 §1); only the recovery eligibility
  set changes. The instrument flip `k_src work↔panes` is left for its own unit (U13 §6).
- **`cc-pane send` on kitty** — dead (`bin/cc-pane:65` iterm2 driver, U08 §3a). Not fixed here;
  the recovery path never uses it and the command doc bans it. A `bin/cc-pane-kitty` driver is a
  separate unit.
- **`kitty @ send-key`** — never used, never will be (unobservable encoding, rc always 0, U08 §3c).
- **`~/.claude/settings.json`** — no new hook; StopFailure is already registered in all five dirs.
  Any settings edit is a c10 operator step and this design needs none.
- **The reset-poller's wait-for-reset arm** (`:896` and below) — it is the correct FLOOR when no
  account can host the session; the request lane simply runs above it.
- **`lr-audit.py`** — 0.13 s `--ledger-only`, 1–7 s full; both stay where they are (bundle time,
  and the `gaps > 0` ingest). Its regex reset parse (`:82`) gets `resetsAt` as a fallback via
  `lr_last_api_error`, nothing else.
- **`ship-land`, git, worktrees** — a recovery never lands (iron rule 7); the 7.7 + 12.5 min in
  today's T5 were the lead's own commit-on-main mistake and a docs-diff gate (U11 §5), outside this
  design's scope.

---

## 15. Landing order and the operator's steps

The launcher names the LIVE layer (`lr-handoff.sh:162`; U02 §2b property 1), so the order is
forced: **C6 + C8 + C9 land and CONVERGE first** (`CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh`,
per this repo's standing-converge grant), then **C7** (its extended preflight refuses until the
live `lr-fire-resume.sh` / `capacity-admit.sh` carry `CC_ADMIT_TOKEN` / `_cc_admit_token_redeem`),
then **C1 + C3 + C4 + C5**, then **C10 + C11 + C12** (independent). `statusline.sh` is copy-deployed
by `install.sh`, which `deploy-live` runs (U07 §1).

Operator steps, both filed as `cc-backlog needs … --run`:
1. **C2** — install the plist: `cp scripts/limit-recover/com.reso.lr-reset-poller.plist ~/Library/LaunchAgents/ && launchctl bootout gui/$(id -u)/com.reso.lr-reset-poller; launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.reso.lr-reset-poller.plist`
   (until it lands, C1's `kickstart` gives the same sub-second wake).
2. **C10 glyph pin** — look at `⌗112 d02d8feb` in a real 30-column pane once; say `#` if it
   renders badly.

Wave locus per the house rule: one dispatched session per component group (C6+C8+C9 · C1+C3+C4+C5
· C7 · C10+C11+C12), each with the bats suites named above as its DoD; the drill (§13) is the
lead's acceptance after convergence.

---

## 16. Risks and unknowns, stated

- **WatchPaths coalescing while the job runs** — launchd does not queue a second start; covered by
  the drain re-scan + 600 s tick; the drill's "5 requests in 1 s" measures it.
- **StopFailure inside an assignee** — unmeasured (0 of 10 marker sids were teammates, U10 §3c);
  SF-e is the fixture; until measured, the lead's re-audit is the only recovery for a limited
  teammate (unchanged from today).
- **`quotaLimits` on weekly / Fable-scoped caps** — all five today were `five_hour`; `rateLimitType`
  is the enum that should close LR-blind (`limit-reset-safety-gate.sh:118-121`) but the text kind
  stays as the fallback.
- **The token's 180 s** — chosen from today's 11–16 s gap and the 120 s shell bound; a genuinely
  hot box inside that window is admitted on a decision up to 3 min old. The operation is net-zero
  and every other term was ON at mint; I rate the residual acceptable and it is the one number
  here most worth re-deriving after the drill.
- **`RECOVERY_W_FLOOR 0.10`** rests on one 2.43 h burn window (U13 §6); a transplanted session's
  first hour may burn faster than 0.39 pp/h. Re-measure from the drill's `account-utilization.jsonl`.
- **Concurrency 3 vs kitty socket** — the 1-in-12 timeout was measured single-stream; three
  streams may raise it. Every RPC is bounded and retried; the drill records the rate.
- **The READY phrase** — `auto mode on` is the single surviving alternative on 2.1.260 in auto
  mode (U03 (a)); the quiet-pty fallback is what makes the next CC bump survivable.
- **Cost of `kind:"limited"`** — one extra `jq` on the death path (~40 ms); the hook has 9.6 s of
  budget unused.
- **A page storm** if the poller itself dies mid-drain with 5 requests claimed — the reaper pages
  cause-keyed through `page-damp.sh`; the drill's fault 2 measures one; five is untested.

**Conviction**: 91 % that this design, landed in the order of §15, meets R1–R11 on the drill. The
9 % is the two unmeasured hinges (assignee StopFailure; WatchPaths under a running job) and the
token TTL, each of which the drill converts into a number.
