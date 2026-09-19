# Critique — D3-identity-observability · lens: safety-blast-radius

Critic: adversarial, read-only · 2026-09-19 · repo cites are against `/Users/chrisren/Development/claude-infrastructure` at `3cdaa2552` (`git rev-parse --short HEAD => 3cdaa2552`). Research cites are `U01…U14` under `scratchpad/lr/research/`. Design cites are `D3 §/C` of `scratchpad/lr/design/D3-identity-observability.md`. A claim without a cite is marked **GUESS**.

## The question, answered in one paragraph

D3 keeps every existing hard guard (lock, tombstone, prompt guard, affirmative-shell gate, composer gate, non-charging probe, iron rule 7) and adds nothing that lands, ships or deploys. What it ADDS is a second actor — a per-run watchdog with repair verbs that type into panes — and a per-sid one-refusal budget, and those two additions are where the blast radius grows. Six of the seven questions get a "no, but": the design does not /exit a pane it cannot relaunch **because it makes every relaunch admissible on the second try**, which is the same fact as bypassing the gate; it does not create two writers **except through two sibling auditors (`lr_is_husk` and `bin/cc-husk-sweep`) that disagree about what a husk is**; it never types a *message* into a live composer **but it types Ctrl-U into a shell the operator may be composing in, up to ten times over five minutes**; it skips teammates in the hook **and not in the resolver `recover --all` uses**. One finding is fatal: as waved, the watchdog's `exited` repair re-sends `/exit` inside the normal timing envelope of a healthy recycle, and a `/exit` that lands after the relaunch exits the recovered session.

---

## Refutations (most severe first)

### R1 — FATAL · The watchdog's `exited` repair re-sends `/exit` on a state-store inference, inside the healthy timing envelope, and as waved the watcher never writes the state that would stop it

**Claim refuted:** I2 "nothing infers a verdict from another component's silence" and I3's repair for a stalled `exited` — "re-send `/exit` once via the existing `as_write` path" (D3 C8 repair table, row `exited (no shell after /exit)`; D3 §5 "budget `transplanted→exited` 30 s … a stall is NAMED at 30 s").

**Why it fails, three ways:**

1. **The budget sits inside the normal window.** Foreground `recycle_fire` runs the composer gate (0–180 s, `handoff-fire.sh:11634` `CC_RECYCLE_DRAFT_WAIT 180 / IVL 15`, U04 §1 F2), `await_pane_proof` ≤ 18 s (U04 F6 → `handoff-fire.sh:1652-1660`), the freshness re-read, then `/exit` ×3 with `delay 2` (`handoff-fire.sh:11761-11768`), then CC teardown (≈3 s, a GUESS the design itself labels at §11), then the watcher's shell poll. On a healthy idle box that is 10–26 s **before** the composer gate spends a single interval; on the loaded box that is this design's stated regime it exceeds 30 s routinely. The run doc's `budgets` map (D3 §3.2) even keys the number on the *destination* state (`"transplanted":10,"exited":30`) while the loop reads `budgets[state]` on the *current* state (C8: "if `age > budgets[state]`"), so the stall may fire at **10 s**, inside the composer gate's first 15 s interval.
2. **Where the second `/exit` lands.** `as_write` is `it2 session type` = text + `\r` (`handoff-fire.sh:1406-1431`). If the old CC is still tearing down: harmless. If the pane is at a shell: `zsh: no such file: /exit`, harmless. If the relaunch has been typed and the NEW CC is booting or at READY — which is the case whenever `exited`/`relaunched` are unrecorded for ≥10–30 s — the composer gate the repair promises ("never `/exit` over a non-empty composer") reads a **fresh, empty** composer and passes, and `/exit` exits the recovered session. `lr-fire-resume`'s expect owns the pty at that moment, so the bytes queue in expect's stdin and are delivered at `interact` (`lr-fire-resume.sh:584`, U03 §2) — after the ingest submits, the session exits mid-first-turn. *(Mechanism of the stdin queueing is inferred from expect semantics — **GUESS**; the ordering hazard is arithmetic from the design's own numbers.)*
3. **As waved, the state is never written.** `exited`, `relaunched`, `alive`, `engaged` are assigned to "the `handoff-fire.sh __recycle` watcher" (D3 §3.4) and to edits C5.2 / C5.6. W1's file list carries `handoff-fire.sh` for "C5.3/C5.5" only; W3 (the spine + the watchdog) lists `lr-lib.sh, bin/cc-lr, lr-watchdog.sh, lr-reset-poller.sh, lr-fleet.sh` and **not** `handoff-fire.sh` (D3 §10 table). No wave carries C5.2/C5.6. So at W3 every run sits at `transplanted` while the pane goes exited → relaunched → alive, and at 10–30 s the watchdog re-sends `/exit` into every successful recovery. The same state arises later from any `lr_state_set` failure (`|| true` at every call site, D3 §3.3) and from the documented live-layer lag between two waves — `~/.claude/scripts/handoff-fire.sh` is a per-file symlink into a shared checkout that runs behind trunk (`docs/lessons/launcher-runs-the-live-layer.md`; CLAUDE.md § 🚀 measured 104 commits behind).

**Evidence:** `scripts/handoff-fire.sh:11634` (composer gate constants), `:11745-11772` (teardown marker, freshness re-read, `/exit` via `as_write`), `:1406-1431` (`as_write` = `session type`), `:6786-6791` (shell settle + relaunch type), `:6605` (`HF_RECYCLE_SHELL_WAIT_S` 600); U04 §1 F2/F6/F9/W2 (composer 180 s, pane proof ≤18 s, shell 3–15 s measured); D3 §3.2 `budgets`, §3.3 `|| true`, §3.4 writer table, C8 repair table, §5 rows `transplanted→exited` and `composer gate`, §10 wave table.

**What would discharge it:** the watchdog must never emit a keystroke on a run-doc inference alone — before ANY repair it reads the pane live (`pane_cc_state`, `handoff-fire.sh:3532-3576`) and the TARGET transcript, and a live `cc` on the pane whose registry row names the target account is `alive` whatever the doc says; the `exited` repair should be deleted outright (the existing watcher already re-nudges `/exit` at 60/150/300 s, `handoff-fire.sh:6682-6689`); and C5.2/C5.6 must land in W1 or W3 with a red-proof that the watchdog stays silent on a healthy run.

---

### R2 — MAJOR · `CC_ADMIT_BUDGET=1` per-sid turns every remaining capacity term into a ~15–30 s delay, and `recover --all` multiplies it N-way; the design's own fault-injection arm (a) contradicts its own C4

**Claim refuted:** D3 §9 "The headroom / segments / active terms and their ceilings — … Only the load term's default for these callers, the net-zero delta, and the counter key change"; §8 arm (a) "`CC_ADMIT_SEGMENT_OVERRIDE=99` → `refused:capacity(segments)` … watchdog retries at 30 s … remove the override → `engaged`".

**Why:** `_cc_admit_spend` is the single sink for **every** refusing term — load, headroom, segments (`capacity-admit.sh:727-728`), active (`:831-833`), reserve-headroom/active — and `cc_hw_budget_charge` releases at `n > budget` (`:381-395`), after which `_cc_admit_spend` returns 0 with `basis:"budget-expired"` and a page (`:948-953`). With `CC_ADMIT_BUDGET=1` and `CC_ADMIT_BUDGET_KEY=$SID` (D3 C4 launcher block), the first typed attempt is "refusal 1 of 1" and the second — the watcher's retype at ~15 s (C5.3/C5.4) or the watchdog's at 30 s (C8) — ADMITS whatever term refused. So arm (a) as written is false: with the override still at 99 %, the second attempt admits; "remove the override → engaged" describes the pre-design budget-3 behaviour. More importantly the 50 % segments ceiling that `capacity-admit.sh:700-712` calls PROVISIONAL and the 4 GB headroom floor become a one-attempt delay for this caller.

**The multiplier:** `cc-lr recover --all` fires "N concurrent runs, all detached at once" (D3 C2), each with its own counter key. The admission **token** compounds it: the fleet probe is non-charging (`capacity-admit.sh:526-533`, U05 §1.3), so N probes fired within one second all read the same box and all mint (D3 C4 "mints the token on ADMIT"); N launchers then redeem N tokens and admit *before any term is evaluated* (U05 P2 redeem sits "immediately after the CC_ADMIT_GATE=off branch"). The gate was designed as one evaluation per spawn, serialized (`docs/plans/LIMIT_RECOVER_100P.md` §4 hard constraint, U09 gap #6 "MUST sequence against it"); D3 de-sequences it and the token makes the de-sequencing invisible to the gate. Today's box had load rise 41→67 during ONE recovery (U05 §3.5); five concurrent `claude --resume` boots of 3–12 MB transcripts on a box the segments term would have refused is the resurrection shape the poller caps exist for (`lr-reset-poller.sh:820-822` "8.8 GB of resurrected sessions took the machine down") — and D3 C8 removes `MAX_PER_WT` for in-place recycles on the memory argument alone (U06 §5 H), without replacing it with any fleet-wide admission bound.

**Evidence:** `scripts/lib/capacity-admit.sh:381-395, 526-533, 700-712, 727-728, 831-833, 929-963`; U05 §1.2, §3.4, P2, P3(a); U04 §5A ("admits into a genuinely hot box one attempt sooner"); D3 C2 `recover --all`, C4, C8 last bullet, §8 arm (a), §9.

**What would discharge it:** (i) fix arm (a) to state the true behaviour and add a `16c` red-proof: segments 99 % + budget 1 → second attempt admits with `basis:"budget-expired"` and a page; (ii) a fleet-wide admission semaphore — mint at most one token per `lf_capacity_wait` window until the previous run reaches `alive`, or cap tokens at `ceiling − act`; (iii) keep `CC_ADMIT_BUDGET=1` only for the term the retraction covers, i.e. leave budget 3 for segments/headroom (a per-term budget is one `case` in `_cc_admit_spend`).

---

### R3 — MAJOR · The irreversible transplant precedes the only gate that can defer — an operator's held draft strands the session after it has already moved

**Claim refuted:** I4 "nothing irreversible precedes an admission the launcher will honour"; C5 "the composer gate … unchanged"; §9 "`lr-transplant.sh` … do NOT change".

**Why:** `lr-handoff.sh:512-519` runs `lr-transplant.sh` (lock at `lr-transplant.sh:59-66`, tombstone + rename at `:91-100`, U02 §1 step 10) and only then calls `handoff-fire.sh --recycle` (`lr-handoff.sh:613-628`), whose `recycle_composer_gate` (`handoff-fire.sh:11634`, `:2419-2430`) waits up to 180 s for an empty composer and then refuses "leaving the session alive and the draft intact". D3 renames that refusal `exit-deferred` "a named wait, not a failure" (C8, §3.1) — but by then the source transcript is `.jsonl.handed-off`, the tombstone exists, and `hooks/handed-off-session-guard.sh:66-72` will `exit 2` the operator's draft the moment they press Enter. The "wait" has no exit: the pane holds a live `cc` (so `lr_is_husk`'s `pane_cc_state ≠ cc` clause is false → no repair), the run ceiling turns it into `failed:exited:watchdog-gave-up`, and the operator is told their draft blocked a session that no longer exists on that account. U10 §1f records the operator typing into limited panes "seven times in 93 seconds"; a draft in a limited pane is the common case, not the exotic one. The composer read costs 40 ms (`kitty @ get-text`, U08 §6) and nothing in D3's driver (C2 recover steps 1–5) or fleet path (C4) reads it before the transplant.

**Evidence:** `scripts/limit-recover/lr-handoff.sh:512-519, 605-611, 613-628`; `scripts/limit-recover/lr-transplant.sh:55-66, 91-100`; `scripts/handoff-fire.sh:11634, 2419-2430`; `hooks/handed-off-session-guard.sh:1-12, 66-72`; U02 §2a ("Ordering is deliberate: the transplant … runs before the recycle"); U04 §1 F2; D3 I4, C2, C4, C5, C8, §9.

**What would discharge it:** one pre-transplant `composer_content` read in `cc-lr recover` (or `lf_one`) — non-empty ⇒ `parked:held-draft` with the snapshot and a `cc-notify`, before the lock is written. Reversible, ~5 lines, and it is the one place I4 can actually be true.

---

### R4 — MAJOR · The repairs type Ctrl-U into a shell the operator may be composing in, up to ten times over five minutes, and the adopt arm can do it hours later

**Claim refuted:** I8 (scoped to "a MESSAGE"); §11 "Residual race: the operator typing into a pane between `/exit` and the relaunch line — … the emptiness gate and echo-verified nonce detect it and leave the composer clean".

**Why:** the emptiness gate is a *TUI composer* gate (`composer_content`, `handoff-fire.sh:2392`). The shell-side type path is `it2_type_verified` → `bin/it2-kitty type_verified`, which gates on `shell_prompt_pane` — a read of `in_alternate_screen` only (`bin/it2-kitty:511-529`) — and then sends `\x15` **unconditionally** "scrub any partial line" (`bin/it2-kitty:552`) before the nonce wire. `at_shell`/`pane_cc_state` is process-based (foreground pgid is shells only, `handoff-fire.sh:3557-3574`), so a shell with a half-typed operator command reads `shell`. Today the watcher does this once at 45 s (`handoff-fire.sh:6812-6814`). D3 does it: at the retype (C5.4), every 30 s for `relaunched`/`refused:capacity` up to the 300 s ceiling (C8 table), once for a husk (C8 predicate), and again from the poller's **adopt** arm for "every run doc … non-terminal and whose `watchdog_pid` is dead" (C8 backstop) — whose age check is unspecified, so a run left non-terminal by a crashed watchdog is repaired on the next tick, up to 600 s later, into a pane the operator may by then be using as an ordinary shell. Every one of those wipes whatever the operator has typed on that prompt line.

**Evidence:** `bin/it2-kitty:511-529, 531-575` (`shell_prompt_pane`, `type_verified`, the `\x15` at `:552`); `scripts/handoff-fire.sh:3532-3576` (`pane_cc_state`), `:6812-6814`; U08 §5 (the pty "has no notion of who typed"); D3 C5.4, C8 repair table + backstop, §11.

**What would discharge it:** kitty's `at_prompt` and the prompt line's content are both readable (`kitty @ ls` field list, U08 §3c(i); `get-text` last line) — require the shell line EMPTY before the scrub, exactly as the composer gate requires the composer empty; bound the repair count (`LR_REPAIR_MAX`, default 2) and give `--adopt` a hard rule: never repair a run older than its own ceiling.

---

### R5 — MAJOR · `find --limited` / `recover --all` have no teammate exclusion; the hook's skip does not protect the resolver's source (a)

**Claim refuted:** the implicit claim that D3 never touches a lead-owned assignee (only C3 skips them: D3 lines 197, 456; `grep -n teammate|assignee|agentName` over D3 hits nothing else).

**Why:** `cc-lr find --limited` is the union of (a) sids in `~/.claude/autonomy/stop-failure/rate_limit__*.jsonl`, (b) `parked/*.json`, (c) `requests/*.json`, "each joined to a live registry row" (D3 C2). (b) and (c) are teammate-clean — the poller skips `agentName` transcripts at `lr-reset-poller.sh:748-758` and C3 skips assignees — but (a) is not: `hooks/stop-failure-marker.sh:122-130` appends the marker row for every `StopFailure` BEFORE the arm D3 adds "after `:130`", so the marker file carries teammate sids whenever `StopFailure` fires in an assignee (U10 §3c: unmeasured, 0/10 today). Assignees DO hold registry rows — `hooks/session-register.sh:427` consults `agent_is_assignee` only inside the backlog-reclaim path, and the row write at `:282-288` is unconditional. So `recover --all` enumerates a limited teammate, transplants it (lock, tombstone, rename), `/exit`s its pane and resumes it detached from its lead — the exact outcome U10 §3b names ("an unattached `--resume` detaches the inbox/agentName wiring and duplicates the lead's respawn"). `lr-fleet --locate` had this test at `lr-fleet.sh:211`; C2's five resolution rules do not.

**Evidence:** `hooks/stop-failure-marker.sh:118-130`; `hooks/session-register.sh:282-288, 420-431`; `scripts/limit-recover/lr-reset-poller.sh:748-758`; `scripts/limit-recover/lr-fleet.sh:211` (U01 §1.1 row TEAMMATE); U10 §3b/§3c; D3 C2 rules 1–5, `find --limited`, `recover --all`.

**What would discharge it:** rule 0 in `find`: `head -c 8000 <transcript> | grep -q '"agentName"'` ⇒ row printed as `TEAMMATE (lead-owned)` and never chosen; `recover` refuses it with exit 2 unless `--force-teammate` is passed with the lead's sid.

---

### R6 — MAJOR · Two husk auditors, one population, opposite state models — `bin/cc-husk-sweep --resume` types the SOURCE account's launcher into the same pane `lr_is_husk` would repair with the TARGET's

**Claim refuted:** I7 "`HUSK` is a first-class disposition with an owner and a next command".

**Why:** D3 makes the run doc + `lr_is_husk` the owner (C8). But `bin/cc-husk-sweep` already owns the same panes: it resolves a husk by registry row → scrollback → newest transcript across the four stores and `--resume` types `nocorrect CC_ACCOUNT_PINNED=1 <launcher> --resume <sid>` (`bin/cc-husk-sweep:1-35, 218-229`). It reads neither the split-brain lock nor the tombstone (`grep -n 'HANDOFF.json\|locks/\|lr_transplanted_to' bin/cc-husk-sweep => (no output)`). After a PARTIAL the registry row still names the SOURCE account and the dead pre-`/exit` pid — the row is rewritten only on a `SessionStart` (`hooks/session-register.sh:282-288`, U07 §4), and no successor has started in that pane (U04 §3 residual #1 "cc-registry row UNCHANGED") — so cc-husk-sweep resolves account = source and resumes there — into a store whose transcript is `.jsonl.handed-off` and may hold a re-created stub (U04 W4 "fold the re-created source stub"). That is a `claude --resume <sid>` on the source account while the successor runs on the target: the split brain `handed-off-session-guard.sh` was written for (its header incident, 2026-08-16), now with the guard blocking prompts but not the process. U09 §5 Q2 flagged exactly this composition as untested; D3 neither tests it nor reconciles the two tools. Memory `sibling-auditors-must-share-the-state-model` is this defect by name.

**Evidence:** `bin/cc-husk-sweep:1-35, 85-87, 115-119, 218-229`; `hooks/handed-off-session-guard.sh:5-12`; `scripts/limit-recover/lr-lib.sh:262-273` (`lr_transplanted_to`, the one call cc-husk-sweep needs); U04 §3 residual table #1, W4; U09 §5 Q2; D3 I7, C8 husk predicate.

**What would discharge it:** cc-husk-sweep consults `lr_transplanted_to "$sid" "$cfg"` and `recoveries/by-pane/<pane>` before resolving an account — a transplanted husk is printed `TRANSPLANTED→<target> (owned by run <id>)` and never resumed from the sweep; and `lr_is_husk` gains the `lr_resume_procs "$sid"` conjunct (`lr-lib.sh:233-255`) so a live `--resume <sid>` anywhere — tmux, headless, a manual pane that did not register — defeats the husk verdict. `lr-fire-resume.sh` itself has no duplicate-resume guard (`grep -n 'lr_resume_procs\|pgrep' scripts/limit-recover/lr-fire-resume.sh => (no output)`; its tombstone check at `:171-216` is source-side only), so nothing downstream catches a second resume on the target.

---

### R7 — MAJOR · `cc-lr recover --all --drill` has no population selector; with the limit gate bypassed, `--all` is every live pane on the box

**Claim refuted:** D3 §8 "launch 5 throwaway sessions on next4 … `cc-lr recover --all --drill` treats them as limited (the drill flag bypasses only the 'last assistant word is a limit' gate; every other predicate, gate and write is the production path)".

**Why:** `--all` is defined as `find --limited → one recover per row` (C2), and `find --limited`'s three sources are all limit-keyed. Bypassing the limit gate leaves no source at all — or, if `--drill` widens `--all` to the registry, every live row including the operator's own session and this critic's. D3 §11 restricts *where* `--drill` may be set (argv only, refused under `--from-daemon`) but not *what* it may select. The transplant that follows is irreversible (R3), and the drill is specified to run twice before flipping `LR_POLLER_AUTORECOVER` (C3 policy tier).

**Evidence:** D3 C2 (`find --limited`, `recover --all`), §8 setup paragraph, §11 last-but-one bullet; `scripts/limit-recover/lr-transplant.sh:91-100` (irreversibility).

**What would discharge it:** `--drill` takes an explicit manifest (`--drill <file>` of sids the drill launched, written by the drill's own spawn step) and `recover` refuses any sid not in it; `--all` and `--drill` are mutually exclusive.

---

### R8 — MAJOR · C8's 45 s `alive→submitted` repair fires inside C6's own ≥63 s submit window — two injectors on one composer

**Claim refuted:** I8 "the one ingest prompt into a freshly booted, empty composer"; §5 "budget `alive→submitted` 45 s".

**Why:** C6 polls `lr-submit-probe.sh` "every 3 s for 60 s, ONE re-CR on miss" (D3 C6; U03 §4 `for {set i 0} {$i < 20 …} … sleep 3` + re-CR + re-poll) — a ≥63 s window inside `lr-fire-resume`'s expect, AFTER the READY gate (up to 8 s quiet settle, C6) and the 4 s of fixed sleeps (`lr-fire-resume.sh:552-556`, U14 §1.4). C8's watchdog, at 45 s after `alive`, runs `cc_tui_submit_verified` with the run's prompt if `submitted` is absent. On a loaded box (boot > 4 s, READY late) the launcher has not yet written `submitted` at 45 s, so the watchdog types the same prompt from outside via `kitty @ send-text` while expect is still inside its window. The watchdog's emptiness pre-gate reads the relayed TUI screen — empty in both the "not yet injected" and "already submitted, turn running" cases — so it passes in both. `docs/lessons/inner-bound-outer-bound-starves-the-tail.md` inverted: the outer bound fires before the inner completes. Net effect: a duplicate ingest line (one full-context cache read, ~640 K tokens per U12 §3) or, per U03 (c), a CR into whatever expect has on screen at that instant. *(Whether the second copy lands as a queued prompt or merges is a **GUESS** about expect's stdin handling; the 45 < 63 arithmetic is the design's own.)*

**Evidence:** D3 C6, C8 repair table row `alive`, §5 rows `alive→submitted` and `submitted→engaged`; U03 §4.2 (the 20×3 s loop); `scripts/limit-recover/lr-fire-resume.sh:549-584`; `scripts/lib/capacity-admit.sh` n/a; U12 §3 (cost per round trip).

**What would discharge it:** the watchdog never types a prompt while the launcher's expect is alive on the pane's tty (one `pgrep -t <tty> expect`); the `alive` budget is set ≥ C6's window + slack (≥ 80 s) and the repair is `failed:submit:launcher-silent` + notify, not a retype.

---

### R9 — minor · The C8 "re-drive a failed run through the request arm" path is dead at the transplant lock — safe today, but `--force` is one flag away from the two-writers vector

`lr-fleet --one` → `lr-handoff --in-place` always transplants (`lr-handoff.sh:225-235` forbids `--no-transplant` with `--in-place`; `:512-519` runs it), and `lr-transplant.sh:59-66` REFUSES on an existing lock (`:55-57` on an existing destination) unless `--force`, which `lr-handoff.sh:516` passes straight through. So a re-drive fails at rc 2 before any keystroke — the design's "re-driven … instead of retired" (C8 backstop) is a no-op, and the husk it means to recover stays a husk (U04 §3). An implementer who "fixes" it with `--force` overwrites the lock and, when a source stub was re-created (U04 W4), copies the stub over the successor's transcript. **Discharge:** `lr-handoff` gains `--resume-run <run>` that skips straight to the recycle when `lr_transplanted_to` already names the target and the target transcript's sha matches `transplant.json`.

### R10 — minor · `lr-ingest-verify.sh` clause D runs `session-continue.sh clear` from the launcher, $PWD-keyed, with no session identity — in the shared checkout that disarms every sibling's continuation

`hooks/session-continue.sh:156-172`: `clear` keys the sentinel on `$PWD`, `rm -f`s it and its `.sid` sidecar unconditionally, and stamps `.mech` with `SC_SID="?"` when `CLAUDE_CODE_SESSION_ID` is unset — which it is inside the generated launcher before `exec` (U12 §6.1 "inside the generated launcher … before the exec"). 6–10 live sessions share `/Users/chrisren/Development/claude-infrastructure` (U07 §2a, U14 §3.2), so one recovery's launcher clears whichever sibling had armed a continuation there and spends that cwd's mechanical budget. Pre-existing in spirit (today's ingest step 1 does it from inside the session), but D3 moves it to an unattended path and drops the session identity. **Discharge:** run clause D from inside the resumed session (it is one line in the C11 prompt) or pass `CLAUDE_CODE_SESSION_ID=$SID` and make `clear` refuse when `.sid` names another session.

### R11 — minor · Overrides: three are not reversible from the pane, and two new actors have no kill switch

`export CC_ADMIT_NET_ZERO=1` in the launcher (D3 C4) is hardcoded — no `${:-}` — so the pane's shell cannot restore the +1 charge the way it can restore the load term (`"\${CC_ADMIT_LOAD_TERM:-off}"`) or the budget. The watchdog (C8), its adopt arm, and the `find --limited`→`recover --all` fan-out carry no named switch, against the house pattern every other D3 component follows (`CC_SF_REQUEST`, `CC_SF_REQUEST_KICK`, `CC_ROUTE_RECOVERY`, `LR_FLEET_CAP_WAIT_S`). `MAX_PER_WT` is removed for in-place recycles (C8) with nothing put in its place. **Discharge:** `"\${CC_ADMIT_NET_ZERO:-1}"`; `CC_LR_WATCHDOG=off` (no repairs, alarms only) and `CC_LR_ADOPT=off`; `LR_RECOVER_MAX_CONCURRENT` (default 2, per R2).

### R12 — minor · Liveness on bare pids where the repo's own idiom is (pid,lstart)

The run doc stores `watcher_pid` / `watchdog_pid` and the adopt arm keys on `kill -0` (C8). `hooks/session-register.sh:270-282` records why that is wrong on this box ("pid counter advanced 2,568 in 5 s … the space wraps in well under an hour"), and `docs/lessons/a-stale-pid-does-not-decay-into-harmlessness-it-decays-into-a-gu.md` is the lesson. A reused pid makes a dead watchdog read alive → the run is never adopted → I3's "no state whose breach is silent" fails silently. **Discharge:** store `lstart` beside each pid and compare both.

### R13 — minor · The token's sid is recorded, not enforced, and the token path is inconsistent across sections

U05 P2's `_cc_admit_token_redeem` (adopted "verbatim" by C4) reads the token's sid into `CC_ADMIT_TOKEN_SID` and returns 0 with no comparison against the caller's sid; the prose "it names the sid it was issued for, so it cannot be replayed onto a different spawn" is not implemented and test 15 only asserts the detail string contains `sid-abc`. Separately, C4 mints under `${CC_ADMIT_STATE_DIR}/tokens/$2.token` (U05 P2 fleet diff) while D3 §3.2 lists `tokens/<sid>.token` under `~/.reso/limit-recover/`. **Discharge:** pass the expected sid to redeem and refuse on mismatch (one `[ "$sid" = "$want" ]`); pick one path.

### R14 — minor · The 60 s capacity park lands in a state whose repair is about ranking

C4 cuts `LR_FLEET_CAP_WAIT_S` to 60 s and says "beyond 60 s the watchdog's 30 s repair cadence owns it", but `lf_capacity_wait` runs before the transplant (`lr-fleet.sh:320` before `:321`, U01 §2.2) so a park returns from `lf_one` with no launcher; the run is stuck at `targeted`, whose C8 repair is "re-rank once → `parked:no-target`" — the wrong verdict for a box that is merely hot. Safe (nothing irreversible ran) but mis-labelled. **Discharge:** a `parked:capacity` state with the probe's `term`/`detail`, repaired by re-probing on the 30 s cadence up to the ceiling.

### R15 — minor · Two small load contributions the design adds to the box the gate measures

`statusLine.refreshInterval: 5` (C1 change 3) renders 16 panes × 89 ms every 5 s ≈ 0.28 core continuously, 35 % of it `git status`/`rev-parse` against a 219-worktree checkout (U07 §3c) — a c10 step, so the operator decides. `WatchPaths` on `recoveries/` (C8 backstop) would kickstart the poller on every `lr_state_set` heartbeat write (§3.3 "a second `alive` write is recorded as a heartbeat") during a run; also c10. Neither is a blast-radius fault; both belong in the c10 packet's cost line.

---

## Keeps (what survives this lens, with the cite that makes it survive)

- **The split-brain lock and tombstone are unchanged and still refuse a second transplant.** `lr-transplant.sh:55-57` (destination exists), `:59-66` (lock exists) both `exit 2` without `--force`; D3 §9 leaves the file alone. This is the single guarantee that a re-run cannot mint two copies, and it holds.
- **`hooks/handed-off-session-guard.sh` blocks prompts in a transplanted source** (`:66-72`, exit 2 on the tombstone) and D3 §9 keeps it. Every husk D3 can produce is a pane whose prompts are refused, not a second writer of turns.
- **Iron rule 7 holds: nothing in D3 lands, ships, deploys or commits.** `commands/limit-recover.md:454` "the fleet never lands a recovered session's work" is restated at D3 §9; C11's git use is read-only (`git branch --show-current`, `pool/*` refusal); the launcher is `bash <launcher>`, never `exec` (`lr-handoff.sh:605-611`); no D3 component writes a tracked file in the shared checkout. U11 §5's incident (a commit on `main` in the shared checkout) was the lead's, not the tooling's, and D3 adds no path that could repeat it.
- **The affirmative-shell gate before any keystroke is kept and is process-based, not screen-based.** `pane_cc_state` (`handoff-fire.sh:3532-3576`) walks the tty's process closure; `unknown` never types (`:11614-11619`); D3 C5 and §9 keep it. R4 narrows this (the shell may be non-idle), it does not refute it.
- **The composer gate stays the polarity it has**: an operator draft defers, never gets typed over (`handoff-fire.sh:11634-11640`, `recycle_composer_gate` `:2419-2430`, freshness re-read `:11751-11759`). R3 is about ordering, not about the gate.
- **`cc_capacity_probe` stays non-charging and test 15c keeps the token from becoming a spend** (`capacity-admit.sh:526-533`, U05 T1 15c). A probe still cannot force the third refusal.
- **The transplant never runs without a target**: `lf_pick_target` precedes `lf_capacity_wait` precedes `lr-handoff` (`lr-fleet.sh:313-321`, U01 §2.2); D3 arm (d) "no transplant (the irreversible step never ran)" is true by construction.
- **The 60 s probe park is still before the irreversible step** — R14 is a labelling defect, not a safety one.
- **`find` refuses ambiguity and never picks a stale row**: rule 3 "REFUSE and print all candidates … when the top two are within 12 points"; rule 4 `kill -0` liveness with `STALE` never chosen (D3 C2; U07 §6c; U14 §3.2's 26-vs-16). The wrong-pane recycle is closed at the resolver.
- **Never `send-key`; `send-text --from-file --bracketed-paste=enable` for payloads; emptiness pre-gate mandatory** (D3 C12; U08 §3c, §4.3). The `^[[117;5u` class and the escape-interpretation class are both closed.
- **Messages go through `cc-notify`, never a composer** (I8, C13). Correct and kept.
- **No agent write to `~/.claude/settings.json` or any plist**: `refreshInterval`, `WatchPaths` ×2 and `LR_POLLER_AUTORECOVER` are all filed as operator `c10` steps (D3 C1 change 3, C3, C8, §9). `launchctl kickstart` stays behind `CC_SF_REQUEST_KICK` defaulting to 0 (C3).
- **`--drill` is argv-only and refused under `--from-daemon`** (§11) — R7 is about its selector, not its reachability.
- **New alarm classes need no registration**: `scripts/autonomy-sweep.sh:1921-1930` folds handoff alarms by whatever class string they carry, so `lr-stalled-<state>` is swept the moment it is written.
- **`kitty @ set-user-vars` is an RPC, bounded by `timeout 3`, not a tty write** (C1 change 4) — respects memory `foreign-tty-write-is-sized-in-syscalls`.
- **The statusline change is reversible and its deploy path is stated**: copy-deployed real file, `install.sh`/`deploy-live` (U07 §1; D3 C1, §10). Reading `ITERM_SESSION_ID` for its value, not as a terminal claim (`statusline.sh:412-418`), is the right side of that file's own history.
- **Every kill switch that exists is byte-identical-off**: `CC_ROUTE_RECOVERY=off` (C10, U13 §4b test), `CC_SF_REQUEST=off` (C3, SF-g), `${CC_ADMIT_LOAD_TERM:-off}` / `${CC_ADMIT_BUDGET:-1}` honour a pre-set pane value (C4). R11 lists the three that are missing; the ones present are correctly shaped.
- **`lr_last_api_error` keys on the envelope, never the text** (`lr-lib.sh:129-159`, U10 §1d, §3d(2)); the skill-listing false-positive class (LR-o) stays closed in C3.
- **The per-sid budget key fixes a real cross-recovery contamination** — the one success today ran on a counter another session had spent (U05 §3.4). R2 objects to the *value* 1 composed with N-way fan-out, not to the key.

## Severity roll-up

| id | severity | one line |
|---|---|---|
| R1 | **fatal** | watchdog re-sends `/exit` on a run-doc stall inside the healthy window; as waved the state it waits for is never written |
| R2 | major | budget 1 per-sid + N tokens from N simultaneous probes = every capacity term becomes a 15–30 s delay, N-way |
| R3 | major | transplant (irreversible) precedes the composer gate; a held draft strands a session that has already moved |
| R4 | major | repairs Ctrl-U a shell the operator may be composing in, ≤10× over 5 min, and from the adopt arm later |
| R5 | major | `find --limited` source (a) carries teammate sids; `recover --all` transplants a lead-owned assignee |
| R6 | major | `cc-husk-sweep --resume` and `lr_is_husk` disagree on the same pane; the former resumes on the SOURCE account |
| R7 | major | `--all --drill` has no population selector |
| R8 | major | C8's 45 s submit repair fires inside C6's ≥63 s window — two injectors |
| R9–R15 | minor | dead re-drive path · per-cwd `clear` from an unattended launcher · missing/irreversible overrides · bare-pid liveness · token sid unenforced + path mismatch · park mis-labelled · two load contributions |
