# Critique — D1-zero-touch · lens: LATENCY

Critic: adversarial, latency lens · 2026-09-19 · read-only. Repo `R=/Users/chrisren/Development/claude-infrastructure`.
Design under test: `scratchpad/lr/design/D1-zero-touch.md` (§ numbers below are its sections). Ground truth: U01–U14.
Every number I add is a `<command> => <output>` in § M at the bottom, run today at **load average 102.96 on 10 cores
(10.3/core)** — i.e. the "box under load" regime the design's R3 is written for.

---

## 0. Verdict on the three questions

| question | verdict | why (one line) |
|---|---|---|
| **identified < 2 s** | **HOLDS for the resolver, UNBUDGETED for the screenshot** | `cc-find` pane/sid8 = 0.007/0.012 s (U07 §6b). But R6 says *screenshot* → identified ≤ 0.3 s; the screenshot→`⌗112 d02d8feb` step is a model vision turn the design never prices (§4 C12 has the session "read it off the line"). |
| **engaged < 90 s, idle box** | **PLAUSIBLE on the happy path; the design's own 33 s p50 / ≤35 s R2 is REFUTED** | §12 omits: the `sleep 2` at `handoff-fire.sh:6786` it never removes (+2 s), the foreground `recycle_fire` legs F1/F5/F6/F8/F10 (+3–5 s, U04 §1), a `pane_cc_state` that costs 0.5–0.6 s per call while §7 polls it at 0.5 s (§ R2 below), an uncached `--rank` whose transcript walk has a 5 s budget (`bin/claude-accounts:624`), and a 58 % per-recycle chance of one 10 s kitty RPC timeout (U08 §6 rate × ~10 RPCs, `handoff-fire.sh:894`). Honest p50 ≈ 45–60 s idle; < 90 s survives, 35 s does not. |
| **< 5 min, loaded** | **NOT PROVEN — "≤ 155 s" has no constant behind it** | §7's 120 s probe bound is real, but every watcher loop is ITERATION-bounded with a 0.6 s probe inside a 0.5 s "quantum", and the shell-wait `waited` counter (`handoff-fire.sh:6619`) counts sleeps, not wall — so "120 s" is ~2× wall under load. Add the composer gate's 15 s quantum on a failed read (`:11634`, kept "unchanged"). < 300 s probably holds on the happy path; 155 s is an assertion. |

**Biggest single finding (not a timeout — a placement):** C7 runs `lr-ingest-verify.sh` at `lr-handoff.sh:464`, which is **48 lines BEFORE the transplant at `:512-519`**. U12 §6.1's clause C asserts the transcript sits under the target cfg, the lock names the target, and the source is tombstoned — none of which is true yet at `:464` — so the verifier FAILS on every run, the design's own fail-closed rule keeps the `/limit-recover ingest …` slash prompt, and R9's "1 message, 0 tool calls, ≤ 0.1 K resident" is unreachable **by construction**. That drags back the 41 KB command body, the 6–9 round trips (U12 §3) and the `/`-headed autocomplete CR-swallow class (U03 (b)) the design claims to have "removed outright".

---

## 1. Refutations (ranked; each cites the design line AND the evidence)

### R1 · [MAJOR] "limit → recovery STARTED ≤ 2 s (WatchPaths)" — no constant, and false for every request but the first of a burst

- Design §1 R1, §7 row 2 ("~1 s"), §12 line 2 ("+1.0 [launchd; kick ~0.2]"). No measurement anywhere in U01–U14 or the design of WatchPaths → job-start latency; "~1 s" is asserted.
- `man launchd.plist` (§ M6): *"Use of this key is highly discouraged, as filesystem event monitoring is highly race-prone, and it is entirely possible for modifications to be missed."* The design's fallback for a miss is the 600 s tick (§16 bullet 1) — so R1's real bound is its own backstop clause.
- **ThrottleInterval 5 (C2) is a FLOOR the design sets on itself**: *"jobs will not be spawned more than once every 10 seconds"* (§ M6). A request that lands inside 5 s of the previous tick's exit waits out the throttle. Rare (ticks are ~2–5 s per 600 s; § M5), but "≤ 2 s" is wrong in that window.
- **Burst case — today's shape.** Five StopFailures over 9 minutes (U10 §1c: 16:58:33, 16:59:19, 17:01:34, 17:07:16, 17:07:35). Request 1 starts the poller and its drain. Requests 2–5 arrive while the drain runs: `launchctl kickstart` is a no-op on a running job (design C1 says so), WatchPaths cannot start a running job (§16), and the poller's own lock makes any independent start `exit 0` silently (`lr-reset-poller.sh:170-192`, § M2 — "SKIP, never queue"). They are picked up only by C3's "re-scan after the group finishes". So **start latency for request N>1 = time-to-end of the running GROUP** — up to 120 s (capacity park, §7) or 180 s (engagement bound) — not 2 s.
- **Group-wait, not a pool.** C3: workers are *"`wait`ed as a group"*, then re-glob. With concurrency 3 and 5 requests, requests 4–5 are not even CLAIMED until the slowest of 1–3 finishes. R4's "5 sessions ≤ 90 s" and §12's "two waves ≈ 70 s" assume every wave-1 member finishes in ~33 s; one 120 s park in wave 1 makes the 5-session wall ≥ 150 s. A pool (claim the next request the moment any worker exits) is the same code with a different `wait` — the design chose the slower form.
- **A request can still be LOST for a tick.** After the last re-scan finds `requests/` empty, the poller runs the reaper, DETECT (108 files, 1.7 s prefilter, § M5), CONSOLIDATE and RESUME before exiting. A request landing in that ~2–5 s tail is neither re-scanned nor a WatchPaths start (job running) → waits for the 600 s tick. Small window; nonzero; unmentioned.
- The primitive shaped like this queue is **`QueueDirectories`** — *"keeps the job alive as long as the directory … [is] not empty"* (§ M6): a job that exits with `requests/` non-empty is re-launched, which closes both the re-scan tail and the missed-event case. The design does not consider it.

### R2 · [MAJOR] `pane_cc_state` costs 0.5–0.6 s per call under load; C9/§7 poll it at "0.5 s" as if it were free — every watcher bound is iteration-bounded and its wall is ~2× the number in the table

- Design C9 (`for _ in $(seq 1 40) … sleep 0.5` = "20 s"), §7 rows "/exit → shell 120 s, poll 0.5 s" and "relaunch typed → tui-up 20 s, poll 0.5 s", §12 lines "+3.5" and "+1.0". The design cites U14 for the quantum; U14 § B says verbatim *"`pane_cc_state` … is presumably comparable [to 36 ms], but I did not time it."* The design inherited a guess.
- Measured now (§ M3), extracted `pane_cc_state` + `pid_is_cc` from `handoff-fire.sh:3475-3577`, against a live CC pane's tty, 5 runs: **0.59 / 0.57 / 0.61 / 0.63 / 0.51 s**. Mechanism: `ps -o pid= -t`, `ps -o tpgid= -t`, a **full-table `ps -axo pid=,ppid=`** (1,429 processes), an awk fixpoint, then up to 2 `ps` forks per closure pid in `pid_is_cc` (`:3479,:3484`), then `ps -g` — 8–15 forks per call. `cc_alive`/`at_shell` are one-liners over it (`:6598-6599`).
- Consequences, all arithmetic: the C9 boot loop is 40 × (0.6 + 0.5) ≈ **44 s wall, not 20**; the "≥ 3 s floor before trusting `at_shell`" (`[ "$_" -ge 6 ]`) is ≈ 6.6 s wall; the shell-wait loop keeps `waited=$((waited+N))` (`handoff-fire.sh:6619`, sleep-counted), so a "120 s" bound is **≈ 264 s wall** when each probe costs 0.6 s; and the T2-style ratchet the design proposes ("`HF_RECYCLE_BOOT_WAIT_S ≥ 3 × measured boot`") asserts a constant that is not the loop's duration. Three concurrent workers at 2 Hz issue ~30 `ps` forks/s, one third of them full-table, on a box the recovery itself is loading (U05 §3.5: load rose 41→67 between two refusals *"driven by the recovery machinery itself"*).
- Fix shape (not mine to design, but it is one line): bound by `date +%s`, not by iteration count; poll `cc_alive` via a cheap `ps -o comm= -t $TTY | grep -q claude` and reserve the full closure walk for the affirmative `shell` verdict only.

### R3 · [MAJOR] The C7 fast path is placed BEFORE the facts it checks — R9 (1 message · 0 tool calls · ≤ 0.1 K resident) is unreachable as written

- Design C7: *"Ingest prompt (`:464`): run `lr-ingest-verify.sh "$BUNDLE"` … U12 §6.1 clauses A–D … on rc 0 the prompt is the ONE-LINE non-slash text … on rc ≠ 0 it stays `/limit-recover ingest $BUNDLE …` (fail-closed)."*
- `lr-handoff.sh:464` is `INGEST_PROMPT="/limit-recover ingest $BUNDLE"` (§ M4a); the transplant is `:512-519` (§ M4a). U12 §6.1 clause C: `[ -f "$TCFG/projects/$PROJ/$SID.jsonl" ]` (target copy), `jq -e … .target_cfg == $t` on `locks/$SID.lock` (lock), `[ -f "$SRC_CFG/…/$SID.HANDOFF.json" ]` (tombstone) — all three are WRITTEN by `lr-transplant.sh:59-100` (U02 §1 steps 5, 10), i.e. after `:512`. Clause C's `[ "$CLAUDE_CONFIG_DIR" = target_cfg ]` is evaluated in the DAEMON's process, whose `CLAUDE_CONFIG_DIR` is not the target. Clause D `session-continue.sh clear` keys the sentinel on `$PWD` + a sid-bind (`hooks/session-continue.sh:134-143`, § M7) — from the daemon it clears the wrong sentinel or nothing. U12 §6.1 itself says *"Where it runs: inside the generated launcher, before the `exec lr-fire-resume …` line."* The design moved it upstream and broke it.
- Cost of the fall-through, from U12 §3/§6.3 and U03 (b): 41,464 B command body resident (~10 K tokens) + 6–9 model round trips + ~26.5 K permanently resident tokens per recovered session, and the `/`-headed prompt re-enters the autocomplete CR-swallow class (`lr-fire-resume.sh:563-583` comment; `handoff-fire.sh:6867`). R9 and the "removes the CR-swallow class outright" sentence in C7 are both false as placed.

### R4 · [MAJOR] The per-death-uuid latch mints up to 3 requests per limit event; claim-by-rename does not dedupe them, and the transplant lock turns the extras into spurious `FAILED` pages that also burn worker slots

- Design C1: latch `requests-latch/$SID.$DUUID` *"per DEATH RECORD, never per sid"*; §11: *"Never two writers on one uuid — latch per death uuid (C1); claim-by-rename (C3); the transplant lock (exists)."*
- U10 §1c, measured: `e442434c` fired StopFailure **3× in 16 s** (16:58:33, :43, :49) and `09e64dcb` twice 10 min apart — one limit event, re-fired by queued turns in the still-live TUI. Each is a new death uuid ⇒ a new request (U10 §2d's stated intent was "twice in a DAY"; today's shape is three times in 16 s).
- Timeline under the design: request #1 written at :33, claimed (mv to `claimed/`) within ~1–2 s; request #2 at :43 creates a NEW `requests/<sid>.json` (the first is gone); the drain re-scan claims it ⇒ a **second worker for the same sid**, then a third. C1's second guard (skip if `locks/$SID.lock` or `HANDOFF.json` exists) only closes after the TRANSPLANT — and the pre-transplant window is claim + rank + probe, up to 120 s under §7. Two of three workers then hit `lr-transplant.sh:55-69`'s lock ⇒ `FAILED:transplant:<msg>` + page, which §10 routes to *"none automatic — a lock means another writer; human reads it."* Net: 2 of 3 concurrency slots wasted on one sid, two false pages, and R7's "every failure named" fires on non-failures. A per-sid guard on `claimed/<sid>.json` (merge, never re-claim) is absent from C3.

### R5 · [MAJOR] Every kitty RPC in the watcher stays bounded at 10 s, and the composer gate keeps its 15 s quantum — one 1-in-12 socket timeout costs 10–25 s, and the median recycle takes one

- Design §7 has no row for RPC timeouts; C10 bounds `cc-find`'s calls at 3 s ×3 but leaves `HANDOFF_IT2_TIMEOUT_S=10` (`handoff-fire.sh:894`, U14 §1.5) and the composer gate `CC_RECYCLE_DRAFT_WAIT/IVL 180/15` *"unchanged (`:11634`)"* (§7).
- Rates, measured under today's load: 1 hard `i/o timeout` in ~12 mixed `kitty @` calls (U08 §6), 1 in 4 `kitty @ ls` at 10.06 s (U07 §5). C3 itself counts ~10 RPCs per recycle. P(≥ 1 timeout in 10 calls at 1/12) = 1 − (11/12)^10 ≈ **58 %**, i.e. the MEDIAN recycle eats a 10 s timeout the §12 budget does not carry. Where it lands matters: in the composer gate a failed `composer_content` read (rc 1 on empty, `:2396`) is followed by a 15 s interval ⇒ +25 s; in `as_write`'s `/exit` (3 attempts, `delay 2`) ⇒ +12 s; in `it2_type_verified` (4 inner attempts) ⇒ +10 s and a possible degraded 4th send.
- Concurrency 3 was chosen to keep the rate "where today's single-stream success rate was measured" (C3) — but three streams triple the RPC rate on the same socket and the design's own §16 admits the resulting rate is untested.

### R6 · [MAJOR] The reaper lives inside the poller it would reap; a hung tick swallows every wake with `exit 0`, and zero-touch has no health check on the poller at all

- Design §10 row "poller not loaded / dead": detected by *"`lr-fleet --request` checks `launchctl print`; `desk-invariant` sweeps the LaunchAgent."* The zero-touch path (C1) never calls `lr-fleet --request`; it writes the file and `kickstart`s. `launchctl print` cannot see a LOADED job whose instance is wedged, and `desk-invariant` checks loaded-ness.
- `lr-reset-poller.sh:170-192` (§ M2): a live holder (`kill -0` + lstart match) ⇒ `exit 0`, comment *"SKIP, never queue"*. So while any tick is alive — including one whose worker is parked 120 s on the probe, or wedged on a `wait` — every WatchPaths start and every `kickstart` exits silently. The design's reaper (`lrp_reap`, C3) runs *inside* that tick. R7's "≤ 15 min for a stalled driver" therefore has no detector when the stalled driver is the poller: nothing outside it pages, and the state files it would mark `STALE` stay at their last non-terminal line indefinitely. (`fire_fail_note`/`page-damp` are also in-process.)
- Arithmetic on the row that does exist: a worker killed mid-recovery is caught "per tick + end of drain" (§7) ⇒ next tick ≤ 600 s + stage bound (READY is 300 s) + 60 s = **960 s = 16 min > R7's 15**.

### R7 · [MINOR] §12's "+1.5 s claim · rank · probe · token" cites a CACHED rank; the uncached first pass of a fleet event has a 5 s transcript-walk budget, and §7's "rank 15 s — its own `--max-wait`" names a bound that is only present when passed

- U14 A5 (0.47–1.09 s) and U13 §1 were taken with `cached=1 quota_age_s=38` (U13 §1 verbatim). `bin/claude-accounts:624` `KWORK_BUDGET_S = 5.0` (§ M8) bounds the per-rank working-concurrency walk; U13 §1 recorded today's FIRST uncached call hitting it (`kwork_to=1`). `--max-wait` is `None` unless passed (`bin/claude-accounts:5376`, comment *"absent ⇒ None ⇒ every existing caller byte-identical"*); C3/C5 never pass it. Realistic first-pass rank under load: ~0.7 s sweep + ≤ 5 s walk ≈ 6 s, not 1.5.
- Same line, the probe: `cc_sp_active` is one `jq -rs` over 3,767 beat files + a `ps -p` of 1,694 pids — **7.24 s cold, 0.18–0.20 s warm** (U05 §4.3). The design keeps the active term ON (§11), so the cold case is on the path and unbudgeted.

### R8 · [MINOR] C9's shell-stable floor is dead code as written — `$_` is not the loop variable

- Design C9 code block: `for _ in $(seq 1 40); do cc_alive && …; … [ "$_" -ge 6 ] && at_shell …`. In bash `$_` is rewritten after EVERY simple command to that command's last argument; after `cc_alive` (whose body ends in `[ "$(pane_cc_state …)" = cc ]`) it reads `cc`, so `[ "cc" -ge 6 ]` is an "integer expression expected" error ⇒ false ⇒ the arm never fires. On a refused launcher the loop then runs all 40 iterations (~44 s, R2) unless `relaunch.rc` lands. (It is a sketch; but the ≥ N-iteration floor is the mechanism U04 §5 C called *"required, not cosmetic"*, and the design lowered U04's ≥ 9 s to a nominal 3 s without measuring the launcher's bash prologue under load — with R2's real per-iteration cost it accidentally lands near 6.6 s.)

### R9 · [MINOR] `sleep 2` at `handoff-fire.sh:6786` survives; §12 charges U14 step 7's "achievable 3.5 s", which required removing it

- C9 lists changes at `:11761-11768, :6754, :6800, :6843, :6848, :6811-6816, :6878-6880, :6845-6860, :6619, :11786-11805`. `:6786` (`sleep 2  # shell-prompt settle after claude exits`, § M1) is not among them; U14 §4.2 item 8 is the line the 3.5 s figure assumed. +2 s on every recycle.

### R10 · [MINOR] Foreground `recycle_fire` overhead is ~3–5 s, budgeted as 1.5 s

- §12 "composer freshness · /exit typed +1.5 [:11751-11772]". U04 §1 F1–F10: pane-state probe (one `pane_cc_state`, 0.6 s under load — R2), composer gate read (`get-text` 0.03–0.43 s, U08 §6), `await_armed` 0.2 s tick, `await_pane_proof` (`session list` 36 ms + 0.2 s tick), teardown marker, freshness re-read (another `get-text`), `/exit` via `as_write`, `delay 1.5` + anti-strand CR. Sum ≈ 3–5 s before any RPC timeout.

### R11 · [MINOR] "+14 s irreducible first assistant turn" is n = 1 and cache-write-dominated; "engaged" fires on a thinking block

- §12 cites U14 §2.2 step 12; U14 § B labels 12–15 s *"not directly timed."* The one measurement on disk is U12 §3: user record 17:43:23.755 → first assistant usage record 17:43:38 = ~14 s, with `cache_creation 593,843` — the write of a ~600 K context. Larger contexts scale it. Separately, `resume_engaged` (`handoff-fire.sh:3680-3715`, § M9) serialises `content` with `json.dumps` and accepts any non-empty list, so a Fable xhigh session's first `thinking` block satisfies it — good for the clock, but "engaged" then means "the model started", not "text was produced". State it.

### R12 · [MINOR] R6's 0.3 s is the resolver, not the screenshot; the tuple path depends on telemetry rows that were absent for 2 of 5 sessions today

- §1 R6 "screenshot/keyword → (sid, pane, …) ≤ 0.3 s". `cc-find` is 0.007–0.6 s (U07 §6b); the screenshot → `⌗112 d02d8feb` step is a model turn in the `/limit-recover` session (C12 step 1) — seconds to tens of seconds, plus the queued-prompt latency U11 §2 measured at 13–38 min when the lead was busy. The tuple resolver ranks on `|pct − live|` from `/tmp/cc-telemetry/<sid>.json`, which is wiped at boot and was missing for `e442434c`/`28f07827` today (U09 §4). Behaviour on a missing row is unspecified.

### R13 · [MINOR] C7 ("no `--await` from the daemon") and C3 ("workers `wait`ed as a group") do not say who waits for the terminal state, or who writes `results/<sid>.json` and pages the requester

- If the worker returns after the `/exit` (no `--await`), the group finishes in ~10 s and the re-scan is fast (good for R1) — but then S5's `results/<sid>.json`, the requester notify and the `RECOVERED` decision need a state-file poller with an interval and a bound the design does not give. If the worker instead polls the state file to terminal, the group-wait cost in R1 stands in full. §9's launcher banner *"request→engaged 31 s"* is printed *before* `exec` and cannot know the engaged time.

### R14 · [MINOR] `RCY_ENGAGE_INTERVAL 5 → 1` is justified as "a 19 ms tail read" — `resume_engaged` is a full-file python read

- C9 cites U14 item 9; the 19 ms figure is U08 §6's `tail -c 400000`. `resume_engaged` does `for line in open(f)` (§ M9) — 0.12 s on a 5.7 MB transcript (§ M1 median), fine at 1 Hz, but the citation is to a different implementation. Nil latency impact; noted so the constant is not defended with the wrong number.

---

## 2. What SURVIVES on this lens (keeps)

- **S0 request writer in the StopFailure hook (C1).** Cost claim verified with margin: `lr_tier_from_transcript` = **0.116 s on 5.7 MB, 0.863 s on the 241 MB box-maximum** (§ M1) — the `"assistant"` substring prefilter keeps the full-file read cheap; live-account 48 h transcripts are p50 1.4 MB / max 6.9 MB. The hook stays well inside its 10 s budget on any transcript on the box.
- **`kickstart` (no `-k`) as the sub-second wake for the FIRST request** of a burst; the `-k` removal is correct (a drain in flight would die).
- **Registry-first `--one`, never censusing** (C5) — 40–86 s → 0.039 s (U14 items 1–2); `lr-lib.sh` realpath dedupe.
- **Admission token + load OFF + NET_ZERO (C5–C8).** Removes the two biggest measured costs: the 600 s foreground park (658 s today) and the 2-vs-3 arithmetic that made 4 of 5 husks (U04 §0, U05 §3.4). `relaunch.rc` as the positive discriminator turns a 90 s dead-wait into ~2 s (U04 §0).
- **No retype** (U02 §2d — provably re-runs the same command against a counter advanced by one).
- **Transcript-based submit probe + engagement after the nonce'd user record** (C8/C9) — deletes the dead 30 s `esc to interrupt` oracle (U03 (b)) and the `No response requested.` false positive (U11 §0(B)).
- **Inject sleeps 4 s → 0.7 s** (C8).
- **`⌗<pane> <sid8>` left-anchored on the statusline (+1.2 ms/render) and `cc-find`** (C10) — the identification target is met by the resolver 6–400× over.
- **Ending the manual turn after `--request`** (C12) — the single largest operator-visible number in the corpus: 24.4 min of lead polling and 87 min of queued screenshots (U11 §2).
- **HANDOFF-CONTEXT trimmed to the last DoD entry; `source_argv` dropped** (C7) — 86,888 B → ~1 KB (U02 §4).
- **Bundle-time `lr-audit.py`** — re-measured today at **1.17 s at load 103** (§ M4b), matching U02 §1; U12's 7.04 s was the `--transcript` form under a different moment and is not the cost on this path.
- **Claim-by-rename atomicity and the append-only ≤ 1 KB state line** — correct primitives; the defect in R4 is a missing per-sid guard, not the rename.
- **Rank once per pass, `--assign` per pick, `--recovery` floors** (C3/C11) — the spread mechanism U13 §3c derived; keep, but pass `--max-wait` (R7).

---

## M. Measurements taken for this critique (verbatim; all read-only)

**M1** `bash -c '. scripts/limit-recover/lr-lib.sh; time lr_tier_from_transcript ~/.claude-quaternary 4101dbdf-…'` on the 241,368,760 B transcript
`=> claude-opus-5 xhigh / real 0m0.863s`; on a 5,673,518 B transcript `=> real 0m0.116s`.
Live-account transcripts touched in 48 h: `find -H … -mmin -2880 -exec stat -f %z` ⇒ `n=107 p50=1440030 p90=3801164 p99=5232309 max=6942952`.

**M2** `sed -n 160,200p scripts/limit-recover/lr-reset-poller.sh` ⇒ the self-overlap lock: `if ! mkdir "$LOCKD"; … kill -0 "$_hp" && lstart match ⇒ exit 0  # a genuine live tick holds it — skip this one`. Request arm at `:639-661` runs after it, inside it.

**M3** `pane_cc_state` + `pid_is_cc` extracted verbatim from `scripts/handoff-fire.sh:3475-3577`, run against pane pid 64457 / `ttys012`, `/usr/bin/time -p`, 5 runs:
`cc real 0.59 · cc real 0.57 · cc real 0.61 · cc real 0.63 · cc real 0.51` (user 0.08–0.09, sys 0.18–0.20). `uptime => load averages: 102.01 83.51 65.02`; `ps -axo pid= | wc -l => 1429`. The four fixed `ps` calls alone: `real 0.14 / 0.06 / 0.10`.

**M4a** `sed -n 455,470p scripts/limit-recover/lr-handoff.sh` ⇒ `:464 INGEST_PROMPT="/limit-recover ingest $BUNDLE"`; `sed -n 508,522p` ⇒ `:512 if [[ $NO_TRANSPLANT -ne 1 ]]; … :518 "$LR/lr-transplant.sh" "${TARGS[@]}" > "$BUNDLE/transplant.json"`. Audit call at `:388` uses `--session` form.
**M4b** `time python3 scripts/limit-recover/lr-audit.py --config-dir ~/.claude-tertiary --session 09e64dcb-… --cwd … --json … --md … --salvage-dir <scratch> --quiet` ⇒ `1.172 total`, rc 0; `--ledger-only` ⇒ `0.090 total`; `uptime => load averages: 102.96 83.39 64.87`.

**M5** DETECT-arm population and prefilter: `find -H <4 project dirs> -maxdepth 2 -name '*.jsonl' -mmin -2880 | wc -l => 108`; the `tail -c 20000 | grep -E` loop over them ⇒ `1.680 total`. `launchctl print gui/501/com.reso.lr-reset-poller` ⇒ `state = not running · runs = 407 · last exit code = 0 · run interval = 600 seconds`.

**M6** `man launchd.plist | col -b`: ThrottleInterval — *"by default, jobs will not be spawned more than once every 10 seconds"*; WatchPaths — *"IMPORTANT: Use of this key is highly discouraged, as filesystem event monitoring is highly race-prone, and it is entirely possible for modifications to be missed"*; QueueDirectories — *"keeps the job alive as long as the directory or directories specified are not empty."*

**M7** `grep -n 'clear)' hooks/session-continue.sh => 156:  clear)`; `:134 sentinel_for() { continue_sentinel_for "$1"; }`; `:139 f=$(sentinel_for "$PWD")`; `:142 # (b) sid-bind: stamp the arming session so a same-cwd successor can't inherit`.

**M8** `grep -n '^KWORK_BUDGET_S' bin/claude-accounts => 624:KWORK_BUDGET_S = 5.0`; `:5376 max_wait = _num_flag(args, "--max-wait")` with the comment *"absent ⇒ None ⇒ every existing caller byte-identical"*.

**M9** `sed -n 3680,3716p scripts/handoff-fire.sh` ⇒ `resume_engaged`: `for line in open(f, errors="replace"): … txt = c if isinstance(c, str) else (json.dumps(c) if c else "") … if not txt.strip() or txt.strip() == "No response requested.": continue; sys.exit(0)`.

**M10** `sed -n 50,70p hooks/session-beat.sh` ⇒ `kind="${1:-prompt}"` with no enum check (a `limited` kind is written as given); `scripts/lib/spawn-presence.sh:319` selects `.kind == "prompt"` — C1's `kind:"limited"` beat does stop the census counting the husk, as claimed.

**Labelled guesses (not measured):** idle-box `pane_cc_state` cost (the 4 fixed forks read 0.06–0.14 s idle-ish; the full function was only timed under load); launchd WatchPaths → start latency; whether launchd re-fires a WatchPaths job for a modification that occurred while it was running (Apple's text says events may be missed; I did not test).
