# U04 — handoff-fire.sh remote in-place recycle: timeline, transport, husk state, engagement oracle, retry fix

All paths relative to `/Users/chrisren/Development/claude-infrastructure` unless absolute.
`HF` = `scripts/handoff-fire.sh` (12,383 lines). `CA` = `scripts/lib/capacity-admit.sh`.

---

## 0. THE HEADLINE — measured, not derived

**The relaunch is attempted exactly 2 times; `lr-fire-resume`'s capacity budget releases only on the
4th. `2 < 3 + 1`, so on a loaded box the recycle CANNOT succeed, by arithmetic, and the 4 PARTIALs
today were that arithmetic — not bad luck, not load.**

- Launch attempts per watcher = **2** (first type `HF:6788-6791`, one guarded retype `HF:6814`).
- `CC_ADMIT_BUDGET` default = **3** (`CA:581`); `cc_hw_budget_charge` releases at `n > budget`
  i.e. on the **4th** consecutive refusal (`CA:366-370`), and **any admit resets the counter to 0**
  (`CA:516`, `_cc_admit_reset`).
- Evidence — `~/.claude/autonomy/idl.jsonl`, `caller:"lr-fire-resume"`, 2026-09-19:

| sid (pane) | refusal 1 | refusal 2 | watcher gave up | 3rd (human) invocation |
|---|---|---|---|---|
| 09e64dcb (111) | 17:22:17 `refusal 1 of budget 3` load 2.57/core | 17:23:07 `refusal 2 of budget 3` 2.54 | 17:23:53 | 17:26:24 **admit** basis=`measured` (load fell to 1.61) |
| e442434c (121) | 17:44:55 `1 of 3` 2.42 | 17:45:45 `2 of 3` 2.51 | 17:46:35 | 17:47:14 **admit** basis=`headroom-only` (`load term off`) |
| 28f07827 (114) | 17:49:47 `1 of 3` 2.05 | 17:50:37 `2 of 3` 2.12 | 17:51:26 | 17:51:43 **admit** `headroom-only` |
| cb227486 (117) | 17:53:06 `1 of 3` 4.15 | 17:53:55 `2 of 3` 6.73 | 17:54:45 | 17:55:00 **admit** `headroom-only` |
| d02d8feb (112) | 17:19:59 **`refusal 3 of budget 3`** 2.86 | — | — | 17:20:48 **admit** basis=`budget-expired` → **RECOVERED** |

112 is the control that proves the mechanism: it entered the watcher with a refusal count of 2
already on the counter (spent by the 17:04–17:15 parked fire), so its **retype** was refusal #4 →
`budget-expired` → admit → `recycle-engaged … within 10s`. The other four entered at count 0 and
died at count 2. *(`~/.claude/autonomy/capacity-admit/lr-fire-resume.refusals` is a single shared
per-CALLER integer — not per-pane, not per-sid — so panes also poison each other's counters.)*

Second, independent finding: **the 90 s wait is ~88 s of polling for a process that exited at ~2 s.**
Pane 111's relaunch was typed at ≈17:22:14 and its capacity refusal row is stamped **17:22:17**.

Third: **`CC_ADMIT_LOAD_TERM=off` in the driver's environment cannot reach `lr-fire-resume`** — the
resume-mode relaunch line carries **no env prefix at all** (§2). That is why the lead's override
worked for every hand-typed repair (`basis: headroom-only`, 3 rows above) and for nothing the
watcher typed.

---

## 1. Exact timeline of a remote in-place recycle (every constant cited)

### Foreground (`recycle_fire`, `HF:11517-11784`) — before anything irreversible

| # | step | bound | cite |
|---|---|---|---|
| F0 | `capacity_gate` **SKIPPED** for recycles | n/a | `HF:8270` — `if [ "$RECYCLE" = 0 ]; then capacity_gate \|\| exit 9; fi` |
| F1 | pane-state probe; only `cc` falls through, `shell` types immediately, `unknown` REFUSES | — | `HF:11604-11619` |
| F2 | composer gate — wait for an EMPTY composer | `CC_RECYCLE_DRAFT_WAIT` **180 s**, interval `CC_RECYCLE_DRAFT_IVL` **15 s** | `HF:11634`, `recycle_composer_gate` `HF:2419-2430` |
| F3 | `rcy_old_sid`, goal inherit (**forced empty in resume mode**), `RCY_T0="$(date -u +%FT%T)"` | — | `HF:11688-11706` |
| F4 | `detach` watcher (`start_new_session=True`, log in `$TMPDIR`) | — | `HF:11723`, `detach` `HF:1608-1616` |
| F5 | `await_armed` — grep `^→ armed:` in the log | **≤ 5 s** (25 × 0.2 s) | `HF:1621-1628` |
| F6 | `await_pane_proof` — grep `^→ pane-reachable:` / `^!! pane-UNREACHABLE:` | **≤ 18 s** (`(HF_TIMEOUT_S 10 + 3 + 5) × 5` ticks × 0.2 s) | `HF:1652-1660` |
| F7 | `write_teardown_marker "$SID" recycle` — **before** the /exit | — | `HF:11745`, `HF:5174-5194` |
| F8 | freshness composer re-read (wait 0, ivl 1) | ~1 s | `HF:11751` |
| F9 | `/exit` via `as_write`, 3 attempts, `delay 2` between | ≤ ~3 × (transport) + 4 s | `HF:11761-11768` |
| F10 | anti-strand empty CR after `delay 1.5` | 1.5 s | `HF:11771-11772` |
| F11 | `--await` (remote form only) → `recycle_await_verdict` | **≤ 900 s** = `HF_RECYCLE_SHELL_WAIT_S 600 + RCY_ENGAGE_TIMEOUT 180 + 120`, polled every `HF_RECYCLE_AWAIT_IVL` **5 s** | `HF:11776-11801` |

### Watcher (`__recycle`, `HF:6574-6881`) — after the /exit

| # | step | bound | cite | measured today |
|---|---|---|---|---|
| W1 | `pane_proof` | `HF_TIMEOUT_S` 10 s | `HF:6587` | `listing rc=0 in 0s shape=json` |
| W2 | wait for a **positively confirmed shell** (`pane_cc_state == shell`); vanish probe every 15 s; content-gated nudges at 60/150/300 s | `HF_RECYCLE_SHELL_WAIT_S` **600 s**, tick 3 s | `HF:6605-6691` | **3–15 s** in all 8 logs |
| W3 | `sleep 2` shell-prompt settle | 2 s | `HF:6786` |
| W4 | resume-mode: fold the re-created source stub into `.handed-off` | — | `HF:6762-6770` | logged in 5 of 8 |
| W5 | type the relaunch — `it2_type_verified`, **2 outer tries, `sleep 3` between**; each try = up to `FIRE_TYPE_ATTEMPTS` **4** inner echo-verified attempts (Ctrl-U scrub, `presettle` 0.12 s, bracketed paste, `settle` 0.5 s, re-read ≤500 lines, CR only on exact nonce match; the 4th degrades to a plain char-send) | 2 × 4 × bounded 10 s worst case | `HF:6788-6791`, `_it2_type_line` `HF:2282-2311`, `it2_type_verified` `HF:2313-2323` | 1 try, sub-second |
| W6 | **process wait #1** — `for _ in $(seq 1 15); do sleep 3; cc_alive && break; done` | **45 s** (min 3 s) | `HF:6811` | full 45 s, 5 of 8 logs |
| W7 | **the one retype** — gated on `up=0` **AND** `at_shell` (affirmative shell only); then **process wait #2**, another `seq 1 15` | **+45 s ⇒ 90 s total** | `HF:6812-6816` | `⚠ no claude on /dev/ttysNNN 45s after relaunch — retyping once` in **5 of 8** logs |
| W8a | on `up=1`: **engagement poll** | `RCY_ENGAGE_TIMEOUT` **180 s** (env-overridable), `RCY_ENGAGE_INTERVAL` **5 s** | `HF:6781-6782`, `HF:6845-6860` | engaged within **5–10 s** on all 4 successes |
| W8b | then `arm_goal` verify | `FIRE_GOAL_VERIFY_TIMEOUT` **45 s**, interval 3 s | `HF:5534` | one `verdict=unverified` after 45 s (pane 114, 13:18) |
| W9 | on `up=0`: `hf_bounded "$IT2" session run -s "$RSID" "# HANDOFF RELAUNCH FAILED — run manually: <cmd>"` (errors swallowed by `\|\| true`), `echo … >&2`, `exit 1` | — | `HF:6878-6880` | 4 of 8 |

**Answer to "45 s or 90 s?" — BOTH, and the message can lie.**
The first wait is **45 s**. The retype at `HF:6812` fires only when `at_shell` is *affirmatively*
true; `pane_cc_state` returns `unknown` from seven branches (`HF:3532-3576`, and the enumeration at
`HF:6734`), and on `unknown` the retype is **skipped** — but the terminal message at `HF:6879` still
says **"within 90s"** unconditionally. So an `unknown` pane is reported as a 90 s failure after 45 s.
All four of today's failures did take the full 90 s (the `⚠ …45s…` line is present in each).

**Worst-case wall for one remote recycle today:** 180 (F2) + 5 (F5) + 18 (F6) + 600 (W2) + 2 + 90
(W6+W7) + 180 (W8a) ≈ **1,075 s**; the `--await` caller gives up at **900 s** (`HF:11788`), i.e. the
await bound does **not** cover the composer gate and can return rc 3 over a still-running watcher.
**Typical measured today:** ~6 s shell + 90 s dead wait = **~100 s to a PARTIAL**, ~15 s to a
RECOVERED.

---

## 2. How the relaunch is typed, and whether the driver's env reaches it

**Transport: neither `it2 session run` nor `cc-pane-runner`. It is `it2 session send`, keystroke by
keystroke, echo-verified.**

- `it2_type_verified $IT2 $RSID "$(cat $CMDFILE)"` where `IT2="$HOME/.claude/bin/it2"` (`HF:6585`,
  `HF:6789`). Under kitty that shim execs `bin/it2-kitty` (`HF:1408-1412`).
- `_it2_type_line` (`HF:2282-2311`) sends: `Ctrl-U` (0x15) scrub → `${BP_START}: <nonce>; <cmd>${BP_END}`
  bracketed paste → `session read -n 500` → `grep -qF` the whitespace-stripped nonce+command →
  **only then** a bare `\r`. 4 attempts, the last un-bracketed.
- **`cc-pane-runner` is NOT on this path.** `HF_ARGV`/`CC_PANE_CMD` (`HF:1027-1076`) is the
  *pane-creation* transport for **new** panes on the fire path; a recycle creates no pane.
- `session run` appears on this path exactly once, at `HF:6878`, for the `#`-comment fallback — and
  per `HF:1419-1431` `run` is the LAUNCH verb whose armed-pane branch writes to
  `$CMD_DIR/<id>.cmd` instead of typing, so even that line is not guaranteed to reach the screen.

**The command text (resume mode), `HF:10143`:**

```sh
CMD="cd $(printf %q "$RCY_CWD") && ${NC}bash $(printf %q "$RESUME_LAUNCHER")"
```

with `NC="nocorrect "` (`HF:9770`). Verbatim from today's log (pane 111):

```
cd /Users/chrisren/Development/claude-infrastructure && nocorrect bash /var/folders/…/T/lr-launch-09e64dcb-6SGtgQ.sh
```

**Do the driver's env vars reach it? NO — and in resume mode there is no seam at all.**

- Every other arm bakes `PREFIX="CC_ACCOUNT_PINNED=1 "` (`HF:9725`, `+ CLAUDE_ISOLATION_SKIP=1` at
  `HF:9726`) into `CMD` (`HF:10180/10183/10334/10336/10346/10350`). **The resume arm at `HF:10143`
  uses `${NC}` only — no `${PREFIX}`, no env assignment.**
- The line is typed into the pane's **interactive zsh**, a process that never inherited the driver's
  environment. `CC_ADMIT_LOAD_TERM=off` exported in the lead's Bash tool is therefore structurally
  unreachable by `lr-fire-resume`.
- The only three seams that *can* reach it today:
  1. the minted launcher's own `export` lines — `scripts/limit-recover/lr-handoff.sh:590-591`
     already exports `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` and `CLAUDE_CODE_TASK_LIST_ID`;
  2. the pane shell's rc;
  3. a global settings/env file.

**Where the gate actually lives:** `scripts/limit-recover/lr-fire-resume.sh:321-333` sources
`scripts/lib/capacity-admit.sh` and calls `cc_capacity_admit lr-fire-resume "resume $SID on $ACCT"`;
refusal prints `✗ capacity-admit: REFUSING …` and **`exit 9`** (`:328`). handoff-fire's own
`capacity_gate` is skipped for recycles (`HF:8270`), so this is the *only* gate on the path and it
sits in a process handoff-fire cannot parameterise.

---

## 3. What the `no claude process appeared` arm leaves behind (`HF:6878-6880`)

**It is the ONLY terminal arm of the watcher with neither a ledger row nor an alarm.** Compare the
three siblings: relaunch-write-failed emits `recycle-dead` + `hf_alarm recycle-relaunch-failed`
(`HF:6796-6797`); pane-vanished emits `recycle-dead` + `hf_alarm` (`HF:6698-6699`); never-engaged
emits `recycle-dead 0` + `goal_unreachable` + `hf_alarm recycle-dead` (`HF:6873-6875`). This arm
emits **nothing**.

### Residual state, enumerated (all verified on disk 2026-09-19)

| # | artifact | state after this arm | verification |
|---|---|---|---|
| 1 | **cc-registry row** `~/.claude/cc-registry/<pane>.json` | UNCHANGED — still names the transplanted sid and the **dead** pre-/exit pid | pane 117 → `{"name":"claude-infrastructure-117","session_id":"cb227486-…","pid":82206,…}` |
| 2 | **transplant tombstone** | present: `<cfg>/projects/<slug>/<sid>.HANDOFF.json` + `<sid>.jsonl.handed-off` | all 4 sids, `~/.claude-quaternary/projects/…` |
| 3 | **split-brain lock** | still held: `~/.reso/limit-recover/locks/<sid>.lock` | 4 files, mtimes 12:19–12:52 |
| 4 | **teardown marker** `~/.claude/watchdog/teardown/{<pane>,<sid>}.json` `mode:"recycle"` | present, written **before** the /exit (`HF:11745`) | `{"key_kind":"pane","pane":"111","sid":"09e64dcb-…","mode":"recycle","ts":"2026-09-19T17:22:07Z"}` |
| 5 | **handoffs.jsonl** | **`recycle-intent` only, no outcome row** | 5 intents today (112/111/121/114/117); only 112, 121(18:03), 114(18:16) ever got a `recycle-engaged`. **111 and 117's intents are permanently orphaned.** |
| 6 | **handoff-alarms** | **NONE, all day** | `ls ~/.claude/handoff-alarms \| grep 20260919` → empty |
| 7 | **goal** | `goal_unreachable` NOT called here (it is at `HF:6840` and `HF:6874`) — a goal armed for this recycle is silently lost | code read |
| 8 | **$TMPDIR** | `handoff-recycle-cmd-<pane>-<ts>-XXXX.sh`, `lr-launch-<sid8>-XXXX.sh`, `handoff-recycle-<pane>-<ts>-XXXX.log` all survive | 5 launchers + 8 logs present |
| 9 | **the verdict itself** | ONLY in the `$TMPDIR` watcher log — a `/tmp`-class path this box wipes at boot | `handoff-recycle-111-1789838526-F3pUsW.log` |
| 10 | **fleet ledger** | `results.tsv` PARTIAL row — written by lr-handoff/lr-fleet, **not** by handoff-fire | `~/.reso/limit-recover/fleet/one-20260919T172126Z/results.tsv` |
| 11 | **the pane** | a shell with a `#` comment on it and no claude; `handed-off-session-guard.sh` blocks the husk's prompts if anything resumes the source uuid | `hooks/handed-off-session-guard.sh` |

**#4 is what makes the husk invisible.** The teardown marker says `mode:"recycle"` — a *planned*
teardown — so the crash watchdog correctly declines to page. Combined with #5 (no outcome row) and
#6 (no alarm), **nothing on the box knows the pane is dead.**

### What a later automated pass would need

There is **no single record that says "husk."** The cheapest sound predicate available today is a
4-read join, and **nothing in the tree performs it** — `grep -rn 'recycle-intent' bin scripts hooks`
returns only `HF:634`, `HF:822`, `HF:11542` (the emitter) and one comment in
`scripts/drain-recycle-fire.sh:8`. Proposed predicate:

1. `handoffs.jsonl`: a `class:"recycle-intent"` row for pane P with **no**
   `recycle-{engaged,unverified,dead,relaunch-failed,bgwork-answered}` row for P at a later ts,
   older than ~3 min ⇒ **candidate**;
2. `<src cfg>/projects/*/<sid>.HANDOFF.json` exists AND `<sid>.jsonl.handed-off` exists ⇒ the
   session really was transplanted;
3. `resume_engaged "$RCY_RESUME_CFG" "$sid" "$RCY_T0"` is false in the TARGET cfg ⇒ it never took a
   turn there;
4. registry pid dead **or** `pane_cc_state $(tty of P) != cc` ⇒ the pane holds no session.

**Minimal fix (3 lines, copied from the sibling at `HF:6796-6798`)** — insert before `HF:6879`:

```sh
emit_recycle_event recycle-dead 0 "$RSID" "relaunch typed ${rcy_relaunch_tries:-2}x; no claude process appeared (the launcher exited — most often lr-fire-resume capacity-admit rc 9)" || true
goal_unreachable recycle-dead || true
hf_alarm recycle-dead "$RSID" "${RCY_OLD_SID:-}" "" "HANDOFF-RECYCLE-DEAD (NO PROCESS): pane $RSID is at a bare shell with NO claude — the transplant is DONE and this pane is a tombstoned husk. Relaunch: $(cat "$CMDFILE")" || true
```

Also fix the false "90s": print the real elapsed figure and say whether the retype ran.

---

## 4. What "engagement verified by a new assistant turn" actually reads

Two different oracles; the branch is `RCY_RESUME_SID` (`HF:6846-6847`).

### Resume mode (today's limit-recover path) — `resume_engaged`, `HF:3680-3715`

- Globs `"$cfg"/projects/*/"$sid".jsonl` where `cfg` = `--resume-cfg` (the **target** account's dir).
- Runs an inline `/usr/bin/python3` over the file; a line counts as engagement **only if all** hold:
  `d["type"]=="assistant"` · **not** `d["isApiErrorMessage"]` (a re-limit on the target is excluded) ·
  `d["timestamp"] > t0` where `t0 = RCY_T0` (`date -u +%FT%T`, stamped in the foreground at
  `HF:11706` *before* the /exit) · non-empty content that is not the literal `"No response requested."`.
- `RECYCLE_VERIFY` is **forced 0** in resume mode (`HF:9831` — `[ -z "$RESUME_LAUNCHER" ]`), so **no
  marker is embedded**; the sid does not change either. The fresh non-error assistant turn is the
  only signal, which is exactly the thing a husk cannot fake.

### Ordinary recycle — `recycle_engaged`, `HF:3717-3761`

Two OR'd signals: (a) **marker** — `find $pdir -name '*.jsonl' -mmin -${CC_ENGAGE_SCAN_WINDOW_MIN:-240} -exec grep -lF -- "$marker"`, excluding the old sid's own file, then `assistant_turn_in`; the
marker `HANDOFF-RECYCLE-$$-<epoch>-$RANDOM` is appended only to the launch-time prompt COPY
(`HF:9952-9958`). (b) **row change** — `cc_sid_for_pane` differs from `$rcy_old_sid`, then
`assistant_turn_in` on both the flat and the nested `<pdir>/*/<newsid>.jsonl` layouts.

### Polling

`while rcy_t < RCY_ENGAGE_TIMEOUT` with `sleep RCY_ENGAGE_INTERVAL` — **180 s / 5 s**, both
env-overridable (`HF:6781-6782`, `HF:6845-6859`). Measured today: **5–10 s** to confirm on all four
successes (`recycled in place; a real assistant turn within 10s`). On expiry it deliberately does
**not** retype (`HF:6861-6866`) and writes `recycle-dead 0` + `hf_alarm` (`HF:6873-6875`).

**Tri-state, and it is honest:** when neither a marker nor a baseline sid nor a resume sid was
handed to the watcher (`HF:6828`), it prints `PROCESS-ALIVE … NOT engagement-verified`, emits
`recycle-unverified` with `engaged` **absent** (not `false`) and exits **0** (`HF:6832-6841`).
Note `recycle_await_verdict` treats that string as a FAILURE (`HF:11794`) while the watcher exits 0 —
a foreground/watcher disagreement worth knowing about.

---

## 5. The minimal change: make the relaunch retry under the capacity budget

Four options, ascending in size. **A is the true one-liner; A+C is the recommended pair.**

### A — one line in the minted launcher (`scripts/limit-recover/lr-handoff.sh:586-593`)

The heredoc already emits `export` lines. Add one:

```sh
export CC_ADMIT_BUDGET="${CC_ADMIT_BUDGET:-1}"
```

Then attempt 1 = `refusal 1 of budget 1`, and the **existing** retype at `HF:6814` is the release
(`n=2 > budget=1` ⇒ `cc_hw_budget_charge` rc 10 ⇒ `basis:"budget-expired"` ADMIT **+ page**,
`CA:948-953`). **Zero watcher change, zero added latency, the page is preserved, and today's 4
PARTIALs all become RECOVERED.** `lr-fire-resume.sh:306-309` already states this caller's contract —
*"a limit-recovery resume must be delayable but never permanently blockable"* — so narrowing its
budget is inside the design, not a bypass. Residual: it lowers the bound for this caller only and
admits into a genuinely hot box one attempt sooner; the page is what makes that visible.

### B — make the retype an N-attempt loop (`HF:6810-6816`)

Replace the single guarded retype with `N = ${HF_RECYCLE_RELAUNCH_TRIES:-$(( ${CC_ADMIT_BUDGET:-3} + 1 ))}`
attempts, each keeping today's `at_shell` affirmative gate (never type onto an unconfirmed pane):

```sh
up=0; rcy_try=1
rcy_tries="${HF_RECYCLE_RELAUNCH_TRIES:-$(( ${CC_ADMIT_BUDGET:-3} + 1 ))}"
while :; do
  for _ in $(seq 1 "${HF_RECYCLE_PROC_TICKS:-15}"); do sleep 3; if cc_alive; then up=1; break; fi; done
  [ "$up" = 1 ] && break
  [ "$rcy_try" -ge "$rcy_tries" ] && break
  at_shell || break                     # unknown ⇒ never type; unchanged polarity
  rcy_try=$((rcy_try + 1))
  echo "⚠ no claude on $TTY_PATH after attempt $((rcy_try-1))/$rcy_tries — the shell is back, so the launcher already exited (most often lr-fire-resume capacity-admit rc 9); retyping"
  it2_type_verified "$IT2" "$RSID" "$(cat "$CMDFILE")" || true
done
```

Cost **without** C: worst case 4 × 45 s = 180 s instead of 90 s. Safety is unchanged — every retype
still requires the affirmative `shell` verdict.

### C — kill the 43 s of dead polling (the latency half)

`lr-fire-resume` refuses in **~2 s** (relaunch typed ≈17:22:14 → refusal row 17:22:17), then the
watcher polls a corpse for 43 s. Exit the wait as soon as the shell is back **and stable**:

```sh
shell_back=0
for _ in $(seq 1 "${HF_RECYCLE_PROC_TICKS:-15}"); do
  sleep 3
  if cc_alive; then up=1; shell_back=0; break; fi
  if [ "$waited_since_type" -ge 9 ] && at_shell; then
    shell_back=$((shell_back + 1)); [ "$shell_back" -ge 2 ] && break
  else shell_back=0; fi
  waited_since_type=$((waited_since_type + 3))
done
```

The ≥9 s floor and the 2-consecutive-sample rule are required, not cosmetic: `pane_cc_state`
classifies **`bash`** as `shell` (`HF:3568`), and the launcher's own `bash`→`exec lr-fire-resume.sh`
prologue *is* bash for its first ~2 s; it only becomes `unknown` once it `exec expect`s. With C, a
4-attempt loop costs ~4 × 12 s ≈ **48 s — less than today's 90 s** — and succeeds.

### D — positive discriminator instead of the heuristic (strictly better than C's timing rule)

After typing the relaunch, read the gate's own ledger rather than the screen:

```sh
jq -c --arg t0 "$RELAUNCH_TS" 'select(.caller=="lr-fire-resume" and .verdict=="refuse" and .ts > $t0)' \
   "${CC_ADMIT_IDL:-$HOME/.claude/autonomy/idl.jsonl}" | tail -1
```

(`CA:395-400` writes this row on every evaluation.) A hit is **positive** proof the launcher already
died on capacity, names the term and the refusal index, and needs no screen read and no timing
heuristic. This is also what the watcher should quote in its failure message so the operator is told
*why* rather than *that*.

### E — the structural note (not minimal, but it is the real shape)

`HF:8270` exempts recycles from handoff-fire's own `capacity_gate`, and `HF:10143` gives the resume
relaunch no env prefix, so **the only admission decision on this path is taken inside a process the
driver cannot parameterise, cannot observe synchronously, and whose exit code it never sees** (the
watcher sees only "no `claude` on the tty"). Any 100th-percentile rebuild should either (i) have the
driver run `cc_capacity_probe` (the non-charging form, `CA:526-532`) *before* typing `/exit` and park
instead of killing the session, or (ii) give the resume CMD a `${PREFIX}` slot so admission policy is
set once, by the caller, at the point the decision is actually understood.

---

## Appendix — verbatim strings a rebuild must match or replace

- `!! relaunch typed but no claude process appeared within 90s — fallback comment typed into pane` (`HF:6879`)
- `⚠ no claude on $TTY_PATH 45s after relaunch — retyping once` (`HF:6813`)
- `→ pane $RSID CONFIRMED at a shell prompt after ${waited}s — typing relaunch` (`HF:6754`)
- `→ relaunched + ENGAGEMENT CONFIRMED in $RSID (a real assistant turn, not just a process)` (`HF:6848`)
- `!! RECYCLE FAILED — never engaged: …` (`HF:6867`)
- `✗ capacity-admit: REFUSING … (refusal N of budget 3)` (`lr-fire-resume.sh:325`, `CA:957`)
- `lr-handoff: --in-place: the recycle did NOT verify (handoff-fire rc=1). The transplant is DONE …` (fleet stderr)
- `recycle_await_verdict` failure grep: `RECYCLE FAILED|VANISHED|never reached a CONFIRMED shell|relaunch write failed|no claude process appeared|PROCESS-ALIVE` (`HF:11794`)
