# Critique — D2-one-command · lens: LATENCY

Critic run 2026-09-19, read-only. Repo root `R=/Users/chrisren/Development/claude-infrastructure`;
`HF` = `scripts/handoff-fire.sh`, `CA` = `scripts/lib/capacity-admit.sh`. Every claim is `file:line`,
`U<nn> §<sec>`, or `<command> => <output>` run in this session. Guesses are labelled GUESS.

## Verdict on the three numbers

| target | verdict | one-line reason |
|---|---|---|
| identified < 2 s | **holds for pane-id / sid8 only** (2–12 ms, U07 §6b, U14 §3.1); **refuted as stated** for the screenshot path until C12 lands (W4) AND `install.sh` converges the copy-deployed statusline (U07 §1); the tuple path depends on boot-wiped `/tmp/cc-telemetry` that was absent for 2/5 of today's sids (U09 §4) | the number is right, the reachability is not |
| engaged < 90 s idle | **plausible at p50, asserted without a constant at p100** — the 28–35 s sum rests on U14 §B's *labelled guesses* (teardown 3 s, boot 4 s, first turn 12–15 s "not directly timed"), one Opus measurement (U12 §3: 15 s at 594 K cache_create), and nothing for the Fable-xhigh cold-cache case that was 3 of 5 sessions today | D2's own drill sets p50 ≤ 45 / max ≤ 180 (§5 row 7), which is the honest number |
| engaged < 5 min loaded | **REFUTED under the measured population** — the probe refuses on `active`/`reserve-active` because limit-halted sessions are counted mid-turn; measured live this session: `cc_sp_active => 10`, `cc_sp_operator_state => present` ⇒ refuses on both terms even with net-zero | §R2 below |

---

## Refutations, most severe first

### R1 · FATAL — the driver deadline is an inner/outer-bound inversion, and D2 cites the lesson it repeats

D2 §3 sets a **15 min hard** driver deadline and asserts "sum of every ceiling above ≈ 13.9 min". The
table's own rows sum to: resolver 2 + rank 3 + probe 60 + bundle 30 + `/exit`→shell **600** + relaunch
2×20 = 40 + READY 30 + quiet-pty 8 + pre-inject 0.7 + submit 20+1+10 = 31 + engage **180** = **984.7 s
= 16.4 min > 900 s**. The 13.9 figure is not derivable from the table. Two ceilings that ARE on the
path are absent from the table entirely: the foreground composer-draft gate `CC_RECYCLE_DRAFT_WAIT`
**180 s** (`HF:11634`, verified: `recycle_composer_gate "$RCY_IT2" "$SID" "${CC_RECYCLE_DRAFT_WAIT:-180}" "${CC_RECYCLE_DRAFT_IVL:-15}"`)
and `await_pane_proof` **18 s** (`HF:1652-1660`, `(10+3+5)×5` ticks × 0.2 s). With those the worst
case is **1,183 s = 19.7 min**.

Worse, D2's own C7 recomputes `recycle_await_verdict`'s max as `CC_RECYCLE_DRAFT_WAIT + HF_RECYCLE_SHELL_WAIT_S + 2×20 + RCY_ENGAGE_TIMEOUT + 60` = 180+600+40+180+60 = **1,060 s**, i.e. the await the driver CALLS is bounded above the driver's own 900 s deadline (today's formula at `HF:11788` is `600+180+120 = 900`, verified).

Consequence: the one case D2 §6 explicitly keeps — "a held draft must not be `/exit`ed over … only
the poll quantum moves", i.e. a legitimately slow run sitting in the 600 s shell wait — is marked
`FAILED-TIMEOUT` at 15 min while its watcher is still live and may still engage. That is a FALSE
terminal row over a healthy run, the same shape U04 §1 diagnosed ("the await bound does not cover
the composer gate and can return rc 3 over a still-running watcher"), and the same shape as
`docs/lessons/inner-bound-outer-bound-starves-the-tail.md:5` ("an arm bounded at X inside a pass that
ends itself at Y < X … both bounds are individually CORRECT … assert `max(per-arm bound) < pass
bound`") — which D2 itself cites at U05 §3.4 as the diagnosis of today's failure. **Severity is fatal
for the fault-tolerance promise ("every non-terminal state has a deadline that produces a named
failure"): the deadline produces a WRONG name.**

### R2 · FATAL — "<5 min loaded" is unreachable under the population that exists, because the probe counts limit-husks as mid-turn and never releases

Chain of cited facts:

1. `Stop` does **not** fire when a turn dies on a rate limit — measured 5/5 today (U10 §1a), so
   `hooks/session-beat.sh stop` never runs and the limited session's beat stays `kind:"prompt"` over a
   live pid (U10 §1a last paragraph; U05 §4.1).
2. `cc_sp_active` counts every `kind:"prompt"` beat whose `(pid,lstart)` is alive (`spawn-presence.sh:298-390`, U05 §4.1). A limit-halted TUI is alive. **Every limited session D2 is trying to recover is counted as ACTIVE.**
3. Today's IDL, verbatim (`grep '"caller":"lr-fleet"' ~/.claude/autonomy/idl.jsonl | grep reserve-active`):
   `17:17:43Z refuse reserve-active 7 sessions mid-turn + 1 > active ceiling 8 − operator reserve 1 = 7 (operator present)` ×4 (17:17:43 → 17:18:47), with 5 limit-blocked sessions in the census.
4. Live this session: `. scripts/lib/spawn-presence.sh; cc_sp_active => 10 (2.66 s)`, `cc_sp_operator_state => present (0.22 s)`. So RIGHT NOW `10+1 > 8` refuses the `active` term (CA:832) and `10+1 > 7` refuses `reserve-active` (CA:868); presence is `present` for **900 s** after any operator keystroke (`spawn-presence.sh:424 max="${CC_SP_OPERATOR_MAX_S:-900}"`), which is certain during a manual `/limit-recover`.
5. D2's fix is `CC_ADMIT_NET_ZERO=1` "per U05 §5.5 i". That diff patches **only CA:832**. The `reserve-active` term at **CA:862-872 has its own `[ $(( act + 1 )) -gt "$act_limit" ]`** (verified this session) and is untouched. Even if both were patched, `10 + 0 > 8` still refuses.
6. D2 §6 explicitly **defers** U05 §5.5(ii) (stamp `kind:"limited"` so husks stop counting) — "the right long-term fix … a separate unit of work".
7. The driver's ADMITTED step is `cc_capacity_probe` — **non-charging AND non-releasing AND non-paging** (CA:526-533 verified; U01 §2.2 step 5; CA `_cc_admit_spend` `:925-931`). After 60 s it is `REFUSED-ADMIT`, which D2 §4.4 disposes as "re-run; nothing was moved" — terminal, and C3 pages only on `FAILED-*`, not `REFUSED-*`. Nothing retries. That is the U10 §1g 2 h 37 m idle pattern, re-created with a 60 s timer in front of it.
8. `cc-lr --all` makes it strictly worse: all N probes run BEFORE any `/exit`, so every one of the N husks is counted in every one of the N probes; no probe can admit until a sibling has `/exit`ed, and no sibling `/exit`s until its probe admits.

**Under the exact regime the design is for (5 limited sessions, operator at the keyboard, 2–3 real sessions working), D2's automatic path yields 5 × `REFUSED-ADMIT` at t = 60 s and 0 recoveries.** The "<5 min loaded" claim is asserted with the 60 s constant behind it and the wrong census in front of it.

### R3 · MAJOR — §1.2 cannot print what §2 says the driver computes, inside 2 s

§1.2 line 2: `cc-lr: target next3 (recovery lane: …) admitted headroom-only` — and "Three lines, ≤2 s, exit 0". §2's table says `TARGETED` and `ADMITTED` are advanced by the **driver** (detached). One of the two is false:

- If the foreground computes them: `claude-accounts --rank` is 0.47–1.09 s warm (U14 A5) and its transcript walk is budgeted at **5.0 s** (`bin/claude-accounts:624 KWORK_BUDGET_S = 5.0`, verified) — today's first uncached call hit that budget (`kwork_to=1`, U13 §1); the probe's `cc_sp_active` is **2.66 s warm now** (measured above) and **7.24 s cold** (U05 §4.3). The 2 s bound is gone before the third line prints.
- If the driver computes them: line 2 is not printable at the time §1.2 prints it.

Same inner/outer shape a second time: D2 bounds rank at **3 s** ("over budget ⇒ `REFUSED-TARGET` … never a blind pick") while the callee's own internal walk budget is **5 s** — so under load, precisely when a recovery runs, the rank step fails CLOSED to `REFUSED-TARGET`.

### R4 · MAJOR — the shell-wait early exit (≥3 s, 2 samples) races a healthy launcher and can submit a second prompt into the recovered session

`pane_cc_state` classifies `zsh|bash|sh|…` as `shell` (`HF:3568`, verified). The launcher is `bash <launcher>` → `exec lr-fire-resume.sh` (a bash script) → **before `expect` spawns at `:432`** it runs: D2's new `lr-ingest-verify.sh` (C5: ~6 `jq -e` + `lr-audit.py --ledger-only` 0.13 s + git ≈ 0.5 s), then `cc_capacity_admit` at `:324` whose `cc_sp_active` costs **2.66 s warm (measured now) / 7.24 s cold (U05 §4.3)**. So a HEALTHY launcher reads `shell` for **3–8 s** in the recovery regime — not the "~2 s" D2 quotes from U04 §5 C. U04 §5 C set the floor at **≥9 s** and said "required, not cosmetic"; D2 lowers it to 3 s while simultaneously LENGTHENING the bash phase (C5).

At t=3 s and t=4 s the driver reads two `shell` samples, declares the launcher dead, "joins the IDL row `caller=lr-fire-resume ts>type_ts`" — finds NONE (the gate has not emitted yet) — and retypes. The second `cd … && nocorrect bash …\r` is echo-verified (tty echo stays on under a non-interactive bash) and buffered in the pty; the first launcher's `expect` forwards the outer tty to the composer only at `interact`, i.e. AFTER its own inject+submit, at which point the buffered line and its `\r` are delivered to the recovered session as a **second submitted user prompt**. (GUESS on the last step — the `interact` forwarding is inferred from expect semantics, not executed; the misclassification and retype are cited.) Today this could not fire because the retype came at 45 s, long after the launcher had exited at ~2 s (U04 §0). D2's latency optimization creates the race exactly in the regime it targets.

### R5 · MAJOR — the "wake, don't poll" latency belongs to a channel D2 does not use, and the channel it does use is armed once per session

D2 §1.4: the DONE line "delivers a mailbox line … the same wake path the lead's own fires used today, which beat every one of the lead's blocking polls by 1–5 s (U11 §2)". U11 §2's 1–5 s is the harness **`task-notification`** for a `run_in_background` Bash tool. A driver launched by a foreground `cc-lr` under `setsid` is not a Bash background task and produces no task-notification. D2's actual path is `cc-notify` → `~/.claude/mailbox/<pane>.md` (`bin/cc-notify:29`) → `hooks/mailbox-wake-arm.sh` → `cc-await-ping --interval 15` (`mailbox-wake-arm.sh:198 _iv="${CC_WAKE_ARM_INTERVAL:-15}"`, verified) → exit 2 → synthesized turn. That is **≤15 s of poll + one model turn**, not 1–5 s.

And it is live only while the birth watcher is: `mailbox-wake-arm.sh` is registered on **SessionStart only** — `jq -r '.hooks.Stop[]?.hooks[]?.command' <cfg>/settings.json | grep -c mailbox-wake-arm => 0` in **all five** config dirs (measured). The file's own comment ("Registered on Stop, this hook fires at EVERY idle boundary") describes a registration that is not live; the analogous Stop re-arm for `net-recover-arm` is staged as `migrations/0030` (c10). So a lead that has been idle-woken once already, or was born > 3 h 59 m ago (`_to=14340`), hears the DONE line at its **next human prompt**, not in 30–35 s. The "§4.5" D2 cites for the mechanism does not exist in the document.

### R6 · MAJOR — concurrent `cc-lr --all` has no critical section around pick → assign

C3: "each pick charges `--assign` so the next pick walks down the ranking inside the 90 s cache TTL". `claude-accounts`' flock is single-flight on the **endpoint sweep** (`bin/claude-accounts:141 "flock single-flight"`, lock at `:3860` on the cache file); nothing serializes rank→assign across processes. N drivers fired "at once" (§3 C3 Concurrency) each run `--rank --recovery` (0.5–1 s) before any sibling's `--assign` lands; all N read the same rank[0]. Drill row 4 ("no two Fable sessions on the same account inside one 90 s TTL") fails by construction — the router header's own "burst stacks" warning (U01 §3.3 b) reproduced, now in parallel. Latency-adjacent: the concurrency that buys `≈ max(single)` is unsafe without a lock D2 does not specify.

### R7 · MAJOR — the "~0 s detection-to-fire" hook kick rests on an unestablished harness behaviour

C4: `"$HOME/.claude/bin/cc-lr" "$SID" --from-hook >/dev/null 2>&1 &` inside the `StopFailure` hook (timeout 10, verified in `~/.claude-quaternary/settings.json`), justified by "`cc-lr` itself `setsid`s the driver". But `cc-lr` runs its ≤2 s resolve **inside the hook's process group** before it detaches anything, and the hook exits immediately after the `&`. D2's evidence for group-kill behaviour (`HF:1600-1607`, verified) is about **Bash tool calls**. For hooks, `hooks/mailbox-wake-arm.sh:189-193` records verbatim: whether the harness "KILLS a backgrounded asyncRewake hook is explicitly NOT established by the 2026-07-29 probe". `hooks/session-register.sh:504-510` backgrounds `register` but then `wait`s for it, so it is no precedent for a child outliving its hook. GUESS on direction: if the group is reaped at hook exit, the zero-touch path silently never fires and the only belt is the poller's 600 s tick (C11 `WatchPaths` is c10). The fix is cheap — use `detach()` (start_new_session) in the hook itself — but as written the fastest path in the design is unmeasured on the one property it needs.

### R8 · MINOR — the bgwork dialog and the `waited` schedule are untouched by the quantum change

A source with in-flight background work (pane 114 today, U09 §3 last row; D2 drill "one with an in-flight subagent") gets its `/exit` dialog answered only when `waited % rcy_bgwork_every == 0` with `rcy_bgwork_every=15` (floor 3) — `HF:6616-6618` verified. That is up to **+15 s** D2's table never lists. And D2 changes `HF:6619 sleep 3 → 1` without saying what happens to `waited=$((waited+3))` on the same line: unchanged, `waited` runs 3× fast and the 15 s vanish probe, the bgwork probe and the 60/150/300 s nudges (`HF:6628`, `:6682-6689`) all fire at one third of their designed times; changed to `+1`, the bgwork cadence stays 15 s.

### R9 · MINOR — the resolver's "2 s hard" bound is consumed by a single component, and the non-registry shapes do not fit it

- `kitty @ ls --match` under `timeout 2` spends the whole budget on a socket stall; D2's own drill row 16 concedes "≤ 2.2 s".
- keyword path: 16 panes × `get-text`, each bounded at 2 s ⇒ **32 s** worst case, sequential.
- tuple path: needs `/tmp/cc-telemetry/*.json`, boot-wiped and absent for 2/5 of today's sids (U09 §4) ⇒ (account, cwd) only ⇒ 4-way ambiguous ⇒ refuse. Correct behaviour, but "instant from a screenshot" is then unreachable until C12 (W4 of 5) plus `install.sh`.
- C12 also requires `statusLine.refreshInterval: 5` — a `settings.json` edit (U07 §3d: not set today; `jq .statusLine` ⇒ `{"type":"command","command":"~/.claude/statusline.sh"}`), which contradicts §6's "No new hook registration and no `settings.json` edit — both are c10".

### R10 · MINOR — the idle-box sum understates its own accepted costs

D2 sums "bundle 3" while §6 accepts "5–7 s is noise (U12 §1)": `lr-handoff.sh:388-390` runs the FULL `lr-audit.py --json --md --salvage-dir` (verified), measured 7.04 s by U12 §1 on the same transcript U02 timed at 1.1 s. `await_armed` ≤5 s and pane-proof ≤18 s are absent. The first real turn is n=1 (Opus, 15 s); the Fable-xhigh cold-cache case is unmeasured and was 60 % of today's population.

### R11 · MINOR — failure naming latency and alarm polarity

`FAILED-DRIVER-DIED` is found by `status --sweep` on the poller's 600 s tick after a 3 min grace ⇒ named up to ~13 min after the death, against U14 §4.1's "within 10 s of the deciding event" that D2 adopts elsewhere. `REFUSED-*` states page nobody (C3 pages on `FAILED-*` only), so the R2 outcome is a silent terminal row.

### R12 · MINOR (GUESS) — auto-mode classifier

Memory `auto-mode-classifier-denies-acting-on-a-live-session`: the boundary is "the TARGET being a live Claude session, not the verb" (kill / cc-teardown / a cc-notify saying `/exit` all refused). `cc-lr 117` targets a live pane. Today's `lr-fleet --one … --source-pane 112` from a Bash tool passed (U11 §3), so a wrapper spelling likely passes; unmeasured for the new one.

---

## Keeps — what survives this lens

- **Registry-first resolution for pane id / sid8**: 2 ms / 12 ms measured (U07 §6b, U14 §3.1); refusal on ambiguity rather than a guess (U07 §6c rule 4). This is the real "<2 s" and it is 400× inside the target.
- **`kill -0 <registry pid>` as liveness, never telemetry age** (U07 §4: pane 126 was 52.5 min stale while alive).
- **Every `kitty @` call bounded and its timeout treated as INDETERMINATE** (U07 §5: 10.06 s hang + truncated payload; U08 §6).
- **`setsid` detach of the driver** via the proven `detach()` (`HF:1608-1616`, verified) — the invoking Bash tool call is never held.
- **Fire and END THE TURN** in `/limit-recover` (C14): removes the 24.4 min of lead polling and the 86.9 min of queued screenshots (U11 §2, §7 #1) — this stands on its own regardless of R5's wake-path correction.
- **C5 launcher exports** (`CC_ADMIT_LOAD_TERM=off`, `CC_ADMIT_BUDGET=1`, per-run `CC_ADMIT_BUDGET_KEY`): U04 §5 A + U05 P1/P3; converts today's 4/5 arithmetic husks; the only channel that reaches the pane's fresh process tree (U04 §2, U01 §5.1).
- **C7 `:6878-6880` row + alarm** on the H8 arm (U04 §3, U01 §4.1) — the one branch that fired 4/4 and wrote nothing.
- **C6 transcript-record submit oracle, and ENGAGED only after the SUBMITTED timestamp** (U03 §4; U11 §0 B's `No response requested.` false positive).
- **Per-run state store + `events.jsonl`, `FAILED-*` carrying evidence** — the shape is right; only its deadline arithmetic (R1) is wrong.
- **C10: `lr_transplanted_to` necessary-not-sufficient for retirement** (U02 §2c) — closes the anti-swept husk.
- **Non-slash fast-path prompt gated on `INGEST-VERIFIED.txt`** (U12 §6) — 6–9 round trips → 1, ~26 K resident tokens → ~0.1 K.
- **Poll quantum reductions where the poll is a cheap read**: engage 5 → 1 s (a transcript `tail`, 19 ms), await 5 → 0.5 s, shell-settle `sleep 2` → poll. A 1 s `pane_cc_state` cadence is affordable (`ps -axo pid=,ppid=` = 0.05 s measured). What does NOT survive is the ≥3 s early-exit floor (R4).
- **C9 recovery-lane floors** (U13 §3b) — orthogonal to latency, correct.
- **§6's deliberate non-changes** (transplant, `S_CUT`, `HF_RECYCLE_SHELL_WAIT_S 600` / `CC_RECYCLE_DRAFT_WAIT 180` as protections) — sound, provided the driver deadline is recomputed to sit ABOVE them (R1).

## The three arithmetic corrections that would make the design internally consistent

1. Driver deadline ≥ 180 (composer) + 18 (pane proof) + 600 (shell) + 40 + 38 + 31 + 180 + slack ≈ **20 min**, or drop the 600 s ceiling to something the deadline covers — but never both a 900 s outer and a 1,060 s inner.
2. Rank bound ≥ `KWORK_BUDGET_S` (5 s) + quota fetch, or pass `--no-kwork`-class flag; probe budget must fit `cc_sp_active` cold (7.2 s) per tick.
3. Shell-wait early-exit floor ≥ measured launcher pre-expect time under load (≥ 9 s per U04 §5 C, and larger with C5's `lr-ingest-verify`), or replace the timing heuristic with U04 §5 D's positive IDL discriminator ONLY — a missing IDL row is "not yet decided", never "dead".

And the population correction R2 needs is not arithmetic: either land U05 §5.5(ii) (`kind:"limited"` beats do not count) in W1, or exempt the recovery probe from `active`/`reserve-active` the way `HF:8270` already exempts the recycle from `capacity_gate` — one net-zero operation, one gate.
