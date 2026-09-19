# Critique — D3-identity-observability · lens: LATENCY

Critic: adversarial, read-only · 2026-09-19 · repo `R=/Users/chrisren/Development/claude-infrastructure`.
Inputs: `scratchpad/lr/design/D3-identity-observability.md` (463 lines), research U01–U14 (all read in full), and
the live tree for every line the design cites. Every claim below is `file:line` or `<command> => <output>`;
anything else is labelled GUESS.

## 0. Verdict on the three questions

| target | verdict | one line |
|---|---|---|
| identified < 2 s | **CONDITIONAL — refuted as shipped, holds after W2 + a human-gated deploy** | The pane-id/sid8 path is 2–12 ms and needs no kitty RPC (U14 §3.1, U07 §6b), but it exists only once `statusline.sh` is edited, copy-deployed (`~/.claude/statusline.sh` is a real file, U07 §1), AND "pinned at the operator's eyes in a real 30-col pane before landing" (design C1). Until then a screenshot has no key and the tuple path REFUSES on ties (122/124 render byte-identical, U07 §0). The keyword path's own RPC bound is 3 s > 2 s (design §5 row 1). |
| engaged < 90 s idle | **HOLDS, but the design's ≤ 40 s acceptance number is refuted as stated** | My re-sum of the surviving path is ≈ 32 s (§3 below), so < 90 s is met with margin. But the design's "≈ 26 s budget + slack" omits ≥ 8.5 s of fixed waits it never edits (4 s in `lr-fire-resume.sh:552-556`, ≤ 3 s at `handoff-fire.sh:6619`, 1.5 s at `handoff-fire.sh:11771`) and rests on three GUESSes the design itself labels (teardown 3 s, boot 4 s, first turn 14 s — §11). |
| engaged < 5 min loaded | **REFUTED for "engaged"; holds only for "a named verdict"** | Under sustained refusal on `segments`/`active`, the design's own path ends at 300 s as `failed:*:watchdog-gave-up` (C8) — the session is intact but not engaged. Worse, the pre-transplant capacity park (C4, 60 s) has NO state and NO repair row in C8, so the watchdog mislabels it `stalled:targeted` at 10 s; and the autonomous hook→poller path (C3) inherits `lr-reset-poller.sh:648-661`'s serial-in-lock drain with no watchdog spawned for it. |

Nothing here is FATAL to the design's thesis (key-in-pixels + O(1) registry + detached driver + one state record). The refutations are constants asserted without a constant behind them, sleeps the design missed, and two state-machine holes on the loaded path.

---

## 1. Refutations (most severe first)

### R1 · MAJOR — the pre-transplant capacity park has no state, no repair, and a 10 s budget that fires under it
**Claim (C4):** "`LR_FLEET_CAP_WAIT_S` 600 → 60 … a 60 s park is the point at which the watchdog's repair loop (C8) takes over on a 30 s cadence up to the 5-minute run ceiling — the driver no longer sits in anyone's foreground."
**Evidence:** `lr-fleet.sh:282-291` (`lf_capacity_wait` runs BEFORE `lr-handoff --in-place` at `:321-325`, i.e. before `transplanted`). Design §3.1 states: `located, targeted, transplanted, exited, relaunched, alive, submitted, engaged, resumed, failed:*, stalled:*, parked:no-target` — there is no `parked:capacity` / `waiting:capacity`. Design §3.4: lr-fleet writes `targeted, transplanted, parked:no-target, failed:transplant:*` — nothing for a capacity park. Design C8 repair table rows: `targeted` (re-rank), `exited`, `relaunched/refused:capacity`, `alive`, `submitted`, dead-watcher — none is "lr-fleet is parked on the probe". Design §5: budget `targeted→transplanted` = **10 s**.
**Why:** a run parked at the probe sits in `targeted` for up to 60 s; at 10 s the watchdog writes `stalled:targeted`, raises `lr-stalled-targeted`, pages the requester, and runs the WRONG repair (re-rank) — on every capacity-parked run. If the box stays hot past 60 s, `lf_one` returns rc 1 with a `parked capacity` row (`lr-fleet.sh:320`) and the run doc has no state to move to; the watchdog sits in `stalled:targeted` until the 300 s ceiling → `failed:targeted:watchdog-gave-up`. The sentence "the watchdog's 30 s repair cadence owns it" has no C8 row behind it. **"< 5 min loaded → engaged" is not delivered; "< 5 min loaded → a (mis-named) verdict" is.**

### R2 · MAJOR — the autonomous path (C3 → poller) is serial, in-lock, and unwatched
**Claim (C3):** "with [the flag] on and `LR_POLLER_AUTORECOVER=1` in the plist env, the poller drains the request within seconds and the operator's screenshot finds a session already `engaged`."
**Evidence:** `lr-reset-poller.sh:648-661` — `for _rq in "$REQUESTS"/*.json; do … "$FLEET" --one "$_rq_sid" … --from-daemon > … 2>&1 || _rq_rc=$?` — synchronous, one at a time, inside the self-overlap lock taken at `:178-190` ("SKIP, not queue … a missed tick costs 10 minutes"). `lr-fleet.sh:321-325`: `--one` with `--source-pane` calls `lr-handoff --in-place`, which adds `--await` (U02 §5, `lr-handoff.sh:621`); design C5.7 makes `--no-await` a flag `lr-fleet --one --no-await` passes, but `:657` is not in the design's edit list, so the daemon call keeps `--await` and blocks through `recycle_await_verdict` (`handoff-fire.sh:11786-11803`, `max = 600+180+120`). Design §3.4: `lr-watchdog` is "detached per run by `cc-lr recover`"; the only other spawner is the §0b adopt arm, which runs "after the request drain" (design C8).
**Why:** five requests arriving in a 9-minute burst (today's shape, U10 §1c) drain one at a time, each holding the poller lock for probe (≤ 60 s) + pipeline (3 s) + composer gate (≤ 180 s) + `/exit`+await (≈ 40–60 s on success). 5 × ~60 s ≈ 300 s serial on an idle box; on a loaded box the parks alone are 5 × 60 s before the last transplant starts. During the whole drain none of these runs has a watchdog — the §0b adopt runs only when the drain ends (or next tick, 600 s). U06 §5 item **E** ("drain requests concurrently / off the lock") names this and the design did not adopt it. **The path the design calls "within seconds" is the one path with no per-run watchdog and O(N) serial latency.**

### R3 · MAJOR — 4 s of unconditional `sleep` in `lr-fire-resume.sh` survive, and the design's "every timeout" table does not list them
**Claim (§5, "Every timeout, with its justification"; C6):** C6 replaces the 5 blind CRs at `:572-576` and the `timeout {}` at `:560`; nothing else in the expect program is touched; §9 does not list these as deliberately kept.
**Evidence:** `grep -n 'sleep' scripts/limit-recover/lr-fire-resume.sh => 474 485 495 522 532 545 552 554 556` (see §2 table). `:549-558`: `-re $env(LR_RE_READY) { … sleep 2; send "\025"; sleep 1; send -- $prompt; sleep 1; send "\r" }` — 4 s fixed on EVERY resume that carries a prompt (all of them). U14 §1.4 row 10 and §4.2 item **7** name exactly these as "delete the 3 fixed expect sleeps on the happy path … saves 4 s".
**Why:** 4 s is ~15 % of the design's claimed 26 s floor and sits inside the `alive→submitted` window. A design that enumerates "every timeout" and misses the one its own source unit ranked #7 by seconds is asserting a number without a constant behind it. (`:522 sleep 1` and `:474 sleep 1` are NOT on the happy path — the resume menu is suppressed at the source by `CLAUDE_CODE_RESUME_THRESHOLD_MINUTES=999999999`, `lr-fire-resume.sh:361`; `:532`/`:545` are gated on dialogs preseed removes. Only the 4 s at `:552-556` is unconditional.)

### R4 · MAJOR — the shell-wait quantum `sleep 3` at `handoff-fire.sh:6619` is NOT among C5's seven edits, yet §6 asserts 0.3 s
**Claim (§6 table, row `exited`):** "3 s ticks today → 0.3 s". **(C5.1):** "`:6786` `sleep 2` → poll `at_shell` every 0.3 s, cap 5 s".
**Evidence:** `handoff-fire.sh:6619`: `while [ "$waited" -lt "$rcy_wait_max" ] && ! at_shell; do sleep 3; waited=$((waited+3)); …` — this is the W2 shell-wait loop (U04 §1 W2; U14 §1.5 "the shell-wait poll quantum — hard-coded, not a seam"). `handoff-fire.sh:6786`: `sleep 2   # shell-prompt settle after claude exits` — a DIFFERENT line, after the loop exits. Design C5 edits: (1) `:6786`, (2) after `:6800`, (3) `:6811`, (4) `:6814`, (5) `:6878-6880`, (6) `RCY_ENGAGE_INTERVAL`, (7) `--await`. `:6619` appears nowhere; C5 closes with "the pane-proof handshake [is] unchanged".
**Why:** the loop checks `at_shell` first then sleeps 3 s, so detection after a ~3 s teardown is quantized at 3 s (measured "3–6 s CONFIRMED" in all 8 logs, U04 W2). The 0.3 s in §6 has no edit behind it → refuted by the lens rule. Cost: ≤ 3 s per recovery, plus the design's `exited` verification row is mis-documented.

### R5 · MAJOR — the admission token's 180 s TTL is justified against the wrong bound; I4 fails on the design's own `exit-deferred` path
**Claim (§5, C4):** "**Why 180 s:** the measured probe→launcher gap is 11–16 s (U05 §3.3); the whole `/exit`→shell→type path is bounded at 30+10 s by §5; 180 s leaves 4× slack."
**Evidence:** the token is minted at the fleet probe ADMIT (C4, `lr-fleet.sh:286` edit), BEFORE `lr-handoff` runs the transplant and BEFORE handoff-fire's foreground composer gate. `handoff-fire.sh:11634`: `CC_RECYCLE_DRAFT_WAIT` **180 s** / `_IVL` 15 s — design C5 keeps it ("composer gate 180 s / 15 s (unchanged)", §5) and names it `exit-deferred`, "a named wait, not a failure". `handoff-fire.sh:6605`: `HF_RECYCLE_SHELL_WAIT_S` **600 s** — design §5: "stays as the watcher's own cap". The "30+10 s" the design cites are ALARM budgets (§5 rows `transplanted→exited`, `exited→relaunched`), not bounds on the path. The 11–16 s gap (U05 §3.3) was measured with no composer hold and a 3–6 s shell wait.
**Why:** probe→launcher is bounded by 180 s (composer) + 600 s (shell) + type, not by 40 s. On exactly the `exit-deferred` case the design surfaces as legitimate, the token expires (`_cc_admit_token_redeem`: `age ≤ TTL || return 1`, one-shot even when stale — U05 P2) and the launcher re-evaluates `headroom/segments/active` with `CC_ADMIT_BUDGET=1` → refusal 1 → 15 s process wait (C5.3) → retype → `budget-expired` ADMIT **+ page** (`capacity-admit.sh:948-953`). So I4 ("the probe's admit is carried into the launcher") is false on that path and the degraded path costs ~15–20 s plus a spurious page. Fix is one constant (TTL ≥ 180+600 s, or mint the token AFTER the composer gate clears), but as written the justification is wrong.

### R6 · MAJOR — `located→targeted` budget 3 s is sized on a warm-cache measurement; the cold path is bounded at 12 s + 5 s and there is no `located` repair
**Claim (§5):** "budget `located→targeted` 3 s — `claude-accounts --rank` 0.47–1.09 s (U14 A5)".
**Evidence:** `bin/claude-accounts:3598`: cache `ttl = cfg.get("cache_ttl_s", 90)`; `:791`: `urllib.request.urlopen(req, timeout=12, …)` per account on a sweep; `:624`: `KWORK_BUDGET_S = 5.0` for the transcript walk; U13 §1: today's first uncached call read `kwork_to=1` (the walk timed out) — "whenever the box is pathologically loaded, i.e. exactly when the concurrency count matters most" (`:1946-1948`). U14 A5's 0.47–1.09 s were cached calls (`route-meta … cached=1`, U13 §1). Design C10 adds a second invocation (`--assign`) after the pick. Design C8 repair table has no row for `located`.
**Why:** a cold `--rank` on a loaded box can take up to ~17 s; the run sits in `located` past 3 s → `stalled:located` alarm + page with no repair, on the first run of every burst (the 90 s cache expires between recoveries spaced > 90 s — today's were 2–20 min apart, U11 §3). With `recover --all`, whether the four sibling runs block on the sweep or sweep concurrently is unverified (GUESS: they read the same `/tmp/claude-accounts-cache.json`, `bin/claude-accounts:141`).

### R7 · MAJOR — the invoker keeps BLOCKING through W1 and W2; the #1 measured delay is deferred to W3
**Claim (§10):** "W1 alone converts today's 4 PARTIALs into RECOVERED"; I5 "the driver never blocks the invoker".
**Evidence:** U11 §7 row 1: the largest delay was **86.9 min operator-visible / 24.4 min lead** from the invoker blocking on `until` polls while `task-notification`s beat them by 1–5 s. The non-blocking driver is `bin/cc-lr` (C2) in **W3** (~750 lines, after W2). C5.7 (`--no-await`, a 2-line change at `lr-handoff.sh:621`) is not in W1's component list (W1 = C4, C5.3/C5.5, C9 DUPLICATE, C7). `lr-handoff.sh:621` adds `--await` whenever `--source-pane` is given (U02 §5), and `recycle_await_verdict` blocks up to 900 s (`handoff-fire.sh:11788`).
**Why:** after W1 the invoking session still calls `lr-fleet --one` and still blocks 40–150 s per session in its own Bash tool, and the operator's queued screenshots still dequeue behind it. The fix that removes the largest measured latency (U11 #1) is independent of the spine and costs two lines plus one doc sentence ("END THE TURN") — it belongs in W1.

### R8 · MAJOR — "notified … measured to the second" cites the wrong mechanism; the real wake is a 15 s poll
**Claim (C13, I5):** "Delivered as a message at a safe boundary — the mailbox wake U11 §2 measured to the second — never as keystrokes." "verdicts arrive by `cc-notify` (mailbox), never by polling."
**Evidence:** U11 §2 measured `task-notification` `enqueue` records from a **background Bash task** (`lr-fleet` run as a tracked background tool call). The design's driver DETACHES via `start_new_session` (`handoff-fire.sh:1608-1616`, python3 `subprocess.Popen(start_new_session=True)`), so the run is not a tracked task and emits no `task-notification`. `bin/cc-notify:28-33`: "the INBOX, drained at a safe boundary … An idle session is woken by its own armed `cc-await-ping` watcher". `hooks/mailbox-wake-arm.sh:199`: `_iv="${CC_WAKE_ARM_INTERVAL:-15}"` → `cc-await-ping … --interval 15`. So an idle invoking session sees the verdict ≤ 15 s after the notify lands (plus the asyncRewake turn synthesis), and this path was never measured by any research unit.
**Why:** the "you will be notified here when it ends" latency is 0–15 s, not "to the second", and the claim's citation does not support it. Not on the engaged path; on the operator-sees-it path.

### R9 · MINOR — the pane-id path is < 2 s; the keyword path's own bound is 3 s
**Claim (C2 find rule 2, §5 row 1):** kitty RPC bound 3 s.
**Evidence:** design §5: "`cc-lr find` kitty RPC bound — 3 s"; U07 §5: bare `kitty @ ls` 80–500 ms typical, one 10.06 s timeout with a corrupt payload; U08 §6: bare `ls` 499 ms / 243 KB.
**Why:** a lookup whose worst-case bound is 3 s cannot promise < 2 s on that path; the design says the result is INDETERMINATE, which is honest, but the target line in §8 (`find` ≤ 0.3 s) is for the pane-id path only.

### R10 · MINOR — `resume_engaged` is a whole-file python3 scan, not "a transcript tail read, ~20 ms"
**Claim (C5.6, §6 row `engaged`):** "`RCY_ENGAGE_INTERVAL` 5 → 1 s (a transcript tail read, ~20 ms)"; "20 ms per poll".
**Evidence:** `handoff-fire.sh:3690-3692`: `for f in "$cfg"/projects/*/"$sid".jsonl; do … /usr/bin/python3 - "$f" "$t0" <<'PY' … for line in open(f, errors="replace"):` — the whole file, every poll. Measured this session on an 11,312,741 B transcript, same loop shape: `real 0.10 / 0.08 / 0.09`. Largest transcript in the fleet: `241,368,760 B` (`~/.claude-quaternary/projects/-Users-chrisren-Development-chris-capital-group-contributions/4101dbdf-….jsonl`) → ≈ 2 s per poll (linear GUESS), i.e. > the 1 s interval. U08 §6's 19 ms was `tail -c 400000`, a different read.
**Why:** 1 Hz is still fine on typical sizes (~9 % of a core per watcher; ×5 concurrent ≈ half a core), but the number is 4–5× off and the tail-case overlaps its own interval. C7's token oracle should be written as a tail read from a byte offset (U08 §4.3 step 6) — the design does not say so.

### R11 · MINOR — `lr_last_api_error` is a python3 spawn over a 128 KB tail, ≈ 0.1 s, not "~10 ms"
**Claim (C2 step 5; §5 row "stop-failure ARM 2"):** "~10 ms" / "10 ms tail".
**Evidence:** `lr-lib.sh:132-134`: `tail -c "$bytes" "$f" | /usr/bin/python3 -c '…'`. Measured this session: `real 0.07 / 0.08 / 0.14` on the 11.3 MB transcript (python3 startup alone `real 0.03` ×3).
**Why:** `find --limited` runs it once per candidate serially (design C2), so the "~0.5 s for the whole fleet" number has ~0.5 s of this alone at 5 candidates and grows linearly; the hook's "≤ 0.35 s of a 10 s budget" is closer to 0.45 s. Not a target-breaker; a mis-stated constant.

### R12 · MINOR — the `/exit` path keeps an unconditional `osascript -e 'delay 1.5'` and up to 3×`delay 2`, unlisted in §5
**Evidence:** `handoff-fire.sh:11761-11772`: `for _ in 1 2 3; do if as_write "$SID" "/exit"; then wrote=1; break; fi; osascript -e 'delay 2'; done … osascript -e 'delay 1.5'; as_write "$SID" ""`. Design §5 lists neither; C5 says the handshake is unchanged.
**Why:** ≥ 1.5 s + one osascript spawn on every recycle, inside `transplanted→exited`; up to +6 s when `as_write` retries. Small, but "every timeout, with its justification" does not hold.

### R13 · MINOR — the `submitted→engaged` evidence cites turns the design itself excludes
**Claim (§5):** "first turn ≈ 12–15 s irreducible (GUESS); **5–10 s on all 4 successes today**".
**Evidence:** U11 §0 / U03 §0: the 4 "successes" engaged on `Continue from where you left off.` / `No response requested.` or a queued `<task-notification>` turn — exactly what C7's token oracle rejects. The one measured real first turn: ingest record 17:43:23.755 → first assistant usage record 17:43:38 (U12 §3, `09e64dcb`) ≈ 14.5 s.
**Why:** the 90 s budget still holds; the cited support does not.

### R14 · MINOR — `statusLine.refreshInterval: 5` adds ~0.28 core of continuous load and 3.2 `git status` forks/s, unpriced
**Evidence:** U07 §3c: 89 ms/render, of which `git status` 19.5 ms + `git rev-parse` 11.7 ms on a 219-worktree checkout; U07 §2b: 16 live panes. 16 / 5 s × 0.089 s ≈ 0.28 core. `STe(w){… Math.max(1,H)*1000}` is a timer (U07 §3d), so it re-renders regardless of state change.
**Why:** on the "< 5 min loaded" box this is load the design ADDS. It is a c10 step (operator's), but §5 justifies it only by staleness, never by cost; U07 §6d's companion (replace `git status`/`rev-parse` with payload `worktree.branch`, −19.5 ms/render) is not adopted.

---

## 2. Inventory — every remaining sleep, poll, serial step and blocking invocation on the design's path

Legend: **✎** design changes it · **✗ kept, unlisted** · **✓ kept, deliberately** · **⊘ not on the happy path**

| # | where | constant | value after design | status |
|---|---|---|---|---|
| 1 | `bin/cc-lr recover` (C2) | foreground | < 1 s (registry 2–12 ms + `lr_last_api_error` ≈ 0.1 s + 2× python3 detach ≈ 0.06 s) | plausible; assembly unmeasured |
| 2 | `bin/claude-accounts --rank --recovery` then `--assign` (C10) | cache TTL 90 s; sweep `urlopen timeout=12` (`:791`); `KWORK_BUDGET_S=5.0` (`:624`) | 0.5–1.1 s warm; ≤ ~17 s cold; two invocations serial | ✗ (R6) |
| 3 | `lr-fleet.sh:282-291` `lf_capacity_wait` | `LR_FLEET_CAP_WAIT_S` / `_IVL_S` | 60 s / 5 s (was 600/20) | ✎ but no state/repair (R1) |
| 4 | `cc_sp_active` inside every probe/admit (`spawn-presence.sh:298-`) | jq slurp over `~/.claude/cc-beats` (3,770 files today) | warm 0.2 s / cold 7.2 s (U05 §4.3) | ✗ (design keeps `active` on; token skips it in the launcher only) |
| 5 | `lr-audit.py` + bundle + `lr-transplant.sh` (U02 §1) | — | ≈ 3 s (241 MB tail case ≈ 5 s) | ✓ |
| 6 | `handoff-fire.sh:11634` composer gate | `CC_RECYCLE_DRAFT_WAIT` / `_IVL` | 180 s / 15 s | ✓ (surfaced as `exit-deferred`; but see R5) |
| 7 | `handoff-fire.sh:1621-1660` `await_armed` / `await_pane_proof` | 25×0.2 s / 90×0.2 s | ≤ 5 s / ≤ 18 s (typ. < 1 s) | ✓ |
| 8 | `handoff-fire.sh:11751` freshness composer re-read | wait 0, ivl 1 | ~1 s | ✓ |
| 9 | `handoff-fire.sh:11761-11772` `/exit` retries + anti-strand CR | 3× `osascript delay 2` on failure; `osascript delay 1.5` always | ≥ 1.5 s | ✗ (R12) |
| 10 | `handoff-fire.sh:6619` W2 shell-wait loop | `sleep 3` quantum, cap `HF_RECYCLE_SHELL_WAIT_S` 600 | 3 s quantum, 600 s cap | ✗ (R4) — §6 claims 0.3 s |
| 11 | `handoff-fire.sh:6786` settle | `sleep 2` | poll 0.3 s, cap 5 s | ✎ C5.1 |
| 12 | `handoff-fire.sh:6788-6791` type | 2 tries, `sleep 3` only on failure | ~1 s (`FIRE_TYPE_PRESETTLE` 0.12 + `FIRE_TYPE_SETTLE` 0.5 + read-back) | ✓ |
| 13 | `handoff-fire.sh:6811` process wait | 15×`sleep 3` (sleep-first) | check-first, 0.5 s ticks, cap 15 s, early-exit on `refused:capacity` | ✎ C5.3 |
| 14 | `handoff-fire.sh:6812-6816` retype + second wait | 1 retype + 15×3 s | 1 retype under `CC_ADMIT_BUDGET=1` (= the release) | ✎ C5.4 |
| 15 | launcher gate `lr-fire-resume.sh:324` | token redeem / full eval | ~0.05 s with token; 0.2–7.2 s without (item 4) | ✎ C4 |
| 16 | `lr-fire-resume.sh:433` global expect timeout | 300 s | 300 s | ✓ |
| 17 | `lr-fire-resume.sh:522` + `:474` resume-menu settle + Down | `sleep 1` + `sleep 1`/step + `set timeout 10` readback | ⊘ suppressed at source (`:361`, `CLAUDE_CODE_RESUME_THRESHOLD_MINUTES`) | ⊘ |
| 18 | `lr-fire-resume.sh:532` / `:545` trust / fullscreen | `sleep 1` each + readback | ⊘ preseeded away (C6 adds the two fullscreen keys) | ⊘ |
| 19 | **`lr-fire-resume.sh:552,554,556`** READY → inject | **`sleep 2` + `sleep 1` + `sleep 1`** | **4 s, unconditional** | **✗ (R3)** |
| 20 | `lr-fire-resume.sh:560` `timeout {}` (silent drop) | — | 8 s quiet-pty settle, inject anyway (`READY-BY-QUIET`) | ✎ C6 — note this is a NEW 8 s floor whenever `auto mode on` fails to render (U03 §2a: the only surviving READY alternative in auto mode) |
| 21 | `lr-fire-resume.sh:570-576` submit verify | 5× `set timeout 6` blind CRs = 30 s dead oracle | Tcl poll `exec lr-submit-probe.sh` every 3 s ≤ 60 s + one re-CR | ✎ C6 (−30 s; 3 s quantum remains) |
| 22 | first assistant turn | — | ≈ 14.5 s measured once (U12 §3), "12–15 s" GUESS | ✓ irreducible |
| 23 | `handoff-fire.sh:6845-6859` engagement poll | `RCY_ENGAGE_TIMEOUT` 180 / `RCY_ENGAGE_INTERVAL` 5 | 180 / 1 s; each poll a whole-file python3 ≈ 0.09 s on 11 MB | ✎ C5.6 (R10 on the cost claim) |
| 24 | `handoff-fire.sh:6853` `arm_goal` | `FIRE_GOAL_VERIFY_TIMEOUT` 45 / 3 s | **0 s** — resume mode forces `FIRE_GOAL=""` (`:11703`) and `arm_goal` returns on empty (`:5535`) | ✓ verified non-issue |
| 25 | `handoff-fire.sh:11786-11803` `recycle_await_verdict` | `HF_RECYCLE_AWAIT_IVL` 5 s, max 900 s | 0.5 s for callers that await; fleet path `--no-await` | ✎ C5.7 (but the poller's `:657` call is not edited — R2) |
| 26 | `lr-watchdog` (C8) | 1 s loop; repair cadence 30 s; ceiling 300 s + 60 s | new | ✎ (R1: missing rows) |
| 27 | `cc-notify` → invoker wake | `mailbox-wake-arm.sh:199` `--interval 15` | ≤ 15 s | ✗ (R8) |
| 28 | poller backstop `lr-reset-poller.sh:639-661` request drain | serial, in-lock, `--await` | unchanged | ✗ (R2) |
| 29 | poller tick | `StartInterval 600`; `WatchPaths` = operator c10 | 600 s until c10 lands | ✓ conceded (§11) |
| 30 | `statusLine.refreshInterval` | none → 5 s | +0.28 core continuous (R14) | c10 |

Blocking invocations on the INVOKER after the design: none once W3 lands; **through W1–W2 the invoker still blocks on `lr-fleet --one` + `--await` (R7).**
Serial steps that could be parallel and are not: rank → assign → probe → audit → transplant (U14 §2.3 named rank ∥ census; the design runs them in sequence inside `lr-fleet --one`; ~1–2 s, minor).

---

## 3. Re-sum of the surviving idle-box path (why "engaged < 90 s" holds and "≤ 40 s" is fragile)

| step | s | basis |
|---|---|---|
| driver + detach | 0.3 | item 1 |
| rank + assign (warm) | 1.5 | item 2 |
| probe (warm) + audit + transplant + preseed | 3.5 | items 4–5 |
| composer freshness + `/exit` + `delay 1.5` | 2.7 | items 8–9 |
| CC teardown | 3 | GUESS (U14 B) |
| shell-wait quantum | 0–3 | item 10 (R4) |
| settle poll + type | 1.3 | items 11–12 |
| CC boot | 4 | GUESS (U14 B) |
| gate (token) + READY detect | 0.5 | item 15 |
| **fixed inject sleeps** | **4** | item 19 (R3) |
| submit-probe quantum | 0–3 | item 21 |
| first assistant turn | 14.5 | item 22 (one measurement) |
| engage poll | 0.5 | item 23 |
| **total** | **≈ 32–39 s** | |

< 90 s: yes, with ~2× margin. The design's "≈ 26 s + slack ≤ 40 s" (§8) is met only at the low end and only because 7 s of it is two GUESSes; the 8.5 s of unlisted fixed waits (items 9, 10, 19) are the difference between the design's floor and the re-sum. Operator-visible add-on: + ≤ 15 s (item 27).

---

## 4. Keeps (what survives this lens)

- **Identification is a key problem, and the key is free.** `⌗<pane> <sid8>` costs +1.2 ms/render (U07 §3c, A/B 30×3), registry read 2 ms for a pane id / 12 ms for sid8 (U14 §3.1, U07 §6b), no kitty RPC on the pane-id path (design C2 rule 1). Once W2 is deployed and eyes-checked, `identified < 2 s` is met ~400× over.
- **`find` REFUSES on a tuple tie** instead of guessing (C2 rule 3; U07 §6c) — the fault-tolerance property that costs nothing in latency.
- **The driver returns in < 1 s and detaches** (`detach` is python3 `start_new_session`, `handoff-fire.sh:1608-1616`, measured startup 0.03 s ×3) — I5 holds once C2 exists.
- **C5.3's positive discriminator** (early-exit on `refused:capacity` written by the launcher, U04 option D) converts 88 s of polling a corpse into ~2 s per failure — the single largest per-failure saving after the census.
- **C4's arithmetic fix** (`CC_ADMIT_LOAD_TERM=off` in the launcher heredoc, `CC_ADMIT_BUDGET=1`, per-recovery counter key, net-zero delta) — U01 §0/U02 §0/U03 §1/U04 §0/U05 §3.4 all converge on it; it is the one change that turns 4 PARTIALs into RECOVERED.
- **C6 replacing the 5×6 s dead `esc to interrupt` loop** (U03 §2b: the anchor has 2 hits in 2.1.260, both the retry line) with a transcript probe — −30 s per resume and a true verdict.
- **C9's single-pass census** (0.148 s vs 40–86 s, U14 A3/A4) and `--one` trying the 0.039 s resolver first (U14 §2.3) — the 99.8 % of identification cost, deleted.
- **C11's fast-path ingest** (6 → 1 round trips, −4 min across today's three ingests, U12 §6.3).
- **No in-flight fire lock on the recycle branch** — `hf_inflight_gate` is called at `handoff-fire.sh:10268` (worktree) and `:10345` (cwd) only; the resume-mode `CMD` at `:10143-10144` is a separate `elif` above them, so N concurrent recycles into one cwd do not serialize on it (verified this session). The "fleet wall ≈ max(single)" claim survives on this axis.
- **`arm_goal` is not a hidden 45 s** in resume mode (`:11703` forces `FIRE_GOAL=""`; `:5535` returns on empty) — a step I expected to refute and could not.
- **Transcript-first verification (I6)** at 1 Hz costs ≈ 0.09 s per poll on an 11 MB transcript — cheap enough as a policy, even though the design's "20 ms" is wrong.
- **Every state has a budget and an alarm class (I3)** and the alarm store is already swept (`scripts/autonomy-sweep.sh:1921`, U04 §3) — the observability half is sound; R1 is about two missing rows, not the mechanism.

---

## 5. Measurements taken this session (verbatim)

```
$ for i in 1 2 3; do /usr/bin/time -p /usr/bin/python3 -c 'pass' 2>&1 | grep real; done
real 0.03 / real 0.03 / real 0.03

$ T=…/.claude-tertiary/projects/-Users-chrisren-Development-claude-infrastructure/c46b7d38-….jsonl   # 11,312,741 B
$ for i in 1 2 3; do /usr/bin/time -p bash -c ". scripts/limit-recover/lr-lib.sh; lr_last_api_error '$T'" 2>&1 | grep real; done
real 0.07 / real 0.08 / real 0.14

$ (resume_engaged's python body, verbatim from handoff-fire.sh:3692-3712, on the same 11.3 MB file)
real 0.10 / real 0.08 / real 0.09

$ ls -S ~/.claude-quaternary/projects/*/*.jsonl | head -1 | xargs stat -f '%z %N'
241368760 …/4101dbdf-742b-4751-8de6-fe6d5340c38c.jsonl

$ ls ~/.claude/cc-beats | wc -l
3770

$ grep -n 'sleep\|set timeout' scripts/limit-recover/lr-fire-resume.sh
433 474 485 495 522 532 545 552 554 556 570 582   (values in §2)
```

Not run (would fire or type): any `cc-lr`/`lr-fleet` invocation, any pane write, any `claude-accounts --fresh` sweep. The cold-sweep bound in R6 is read from source (`bin/claude-accounts:791,624`), not timed.
