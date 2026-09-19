# D2-one-command — critique, lens: fault-tolerance

Critic: adversarial, read-only · 2026-09-19 · subject `scratchpad/lr/design/D2-one-command.md`; ground
truth `scratchpad/lr/research/U01–U14`; repo `/Users/chrisren/Development/claude-infrastructure`
(`HF` = `scripts/handoff-fire.sh`, `CA` = `scripts/lib/capacity-admit.sh`, `LRH` =
`scripts/limit-recover/lr-handoff.sh`, `LRT` = `scripts/limit-recover/lr-transplant.sh`). Every claim is
`file:line` or `<command> => <output>`; guesses are labelled.

## 0. Verdict

D2's skeleton is right — a per-run state store, a `setsid` driver, a transcript-keyed submit oracle, and
an alarm row on the one arm that had none — and it would have converted today's four husks into named
failures. But on this lens it has **one husk class it manufactures by construction, one deadlock class it
leaves standing, and one duplicate-driver class it designs in on purpose**, and its own DoD drill
(§5) cannot see any of the three. Specifically:

1. The one pre-irreversible check that prevents the "transplanted but the session is still alive"
   husk — the composer-draft read — runs **after** the transplant in the code D2 keeps (HF:11634 sits
   inside `recycle_fire`, which LRH calls at `:619` after the transplant at `:516`), and D2 mis-cites it
   as the post-`/exit` shell budget. On the zero-touch default (`auto` on) the transplant fires ~0.3 s
   after the limit with nobody asked.
2. D2's `CC_ADMIT_NET_ZERO` patches ONE of the two `act + 1` sites (`CA:789`); the other
   (`CA:839`, `reserve-active`, operator present) is the term that refused today's phase 2 four times
   (U05 §3.2), and a limit-killed session counts as ACTIVE forever (U05 §4, U10 §1a) — so a fleet of
   limited sessions ≥ ceiling−reserve can never recover any of them, and `REFUSED-ADMIT` is terminal.
3. Two designed kick paths (C4 direct + C10/C11 drain) fire on the same request write, and the latch is
   per death-uuid while a limit re-fires per blocked turn — e442434c wrote **three** death uuids in
   16 s today. Nothing in `cc-lr` excludes a second driver on a sid with a live run.

Plus a driver deadline (900 s) that is smaller than the sum of the ceilings it wraps (984–1164 s by
D2's own table) — the exact `inner-bound-outer-bound-starves-the-tail` shape the design cites against
the old code — with a detached watcher that outlives the driver and no rule for who owns the pane
afterwards.

## 1. Every step, its failure, its visibility, its re-drivability

Legend: **V** = visible (a state row with an owner, or a swept alarm) · **R** = re-drivable from this
step · **H/D/L** = the silent outcome if not: Husk / Duplicate writer / Lost session or work.

| # | step (D2 state) | how it fails or hangs | V | R | silent outcome | evidence |
|---|---|---|---|---|---|---|
| 1 | hook kick (`DETECTED`) — C4 `cc-lr … &` from the StopFailure hook | the hook's process group is killed before `cc-lr` reaches its own `setsid` (the resolver is ≤2 s: `timeout 2` on `kitty @ ls`); `cc-lr` dies with nothing under `runs/` | partial — `requests/<sid>.json` exists, `status` shows DETECTED with no driver; the reaper pages after **2 ticks = 20 min** | yes (poller drain, 600 s tick) | none, but the "~0 s" path silently degrades to 600–1200 s | HF:1599-1607 documents the Bash-TOOL group kill; `hooks/waiting-recycle.sh:1445-1457` and `hooks/lead-crash-watchdog.sh:1404` document that a HOOK's group is killed by the pane teardown. Whether CC also reaps a hook's children at hook EXIT is **unmeasured** (labelled guess). |
| 2 | second/third kick for the same sid | StopFailure re-fires per blocked turn with a NEW death uuid; C4's latch is per uuid → N requests → N `cc-lr` kicks; once C11 lands, WatchPaths fires the drain on the same write → +1 driver per event | no — `status` shows N runs, N−1 of them FAILED/REFUSED with a page each, for a sid that is recovering | n/a | **D** (N drivers), N `--assign` phantoms, N spurious desk pages | `python3` over `~/.claude-quaternary/projects/…/e442434c-*.jsonl.handed-off` ⇒ 3 `isApiErrorMessage` records at 16:58:33.848 / :43.293 / :49.027 with uuids `76079a2e…` / `57ec86da…` / `3f08d075…`; `grep e442434c ~/.claude/autonomy/stop-failure/rate_limit__next4.jsonl` ⇒ the same 3 ts. D2 §C4 (latch "event-keyed, never sid-keyed"), §C10 (drain → `cc-lr <sid> --from-request`), §C11 (WatchPaths on `requests/`). No per-sid run lock anywhere in §1–§4.2. |
| 3 | `RESOLVED` (≤2 s) | kitty socket i/o timeout; registry row stale (26 rows / 16 live) | yes — `AMBIGUOUS`/`liveness: unverified-kitty-timeout`, refuses rather than guesses | yes | none | U07 §5, U14 §3.2. **Sound.** |
| 4 | `TARGETED` (rank 3 s, `--assign`) | rank exits 2 (all thin) | yes — `REFUSED-TARGET` with stderr | "wait for reset (poller fallback)" — but the request file is removed only at `DONE` (§4.2), so the 600 s drain re-kicks `cc-lr` every tick → a new run dir + a page per tick until reset (today: 2 h 41 m ⇒ ~16 runs) | alarm-polarity: pages on every tick | D2 §4.2 (`requests/<sid>.json … removed at DONE`), §C10 (drain), §4.4 row 2. |
| 5 | `ADMITTED` — `cc_capacity_probe` 60 s / 5 s, load off, `NET_ZERO` | `reserve-active` (`CA:839`, `act + 1 > ceiling − reserve`, presence=present) is untouched by D2's `:789`-only patch; limit-killed sessions keep `kind:"prompt"` beats and count as active while their pid lives | yes — `REFUSED-ADMIT`, term + value | **no** — terminal, "re-run; nothing was moved"; the probe is non-charging and non-releasing (`CA:923-931`), so no budget release can ever admit it; the count only drops when a limited session is recovered, which this term refuses | **L** for the whole fleet once N_limited ≥ ceiling−reserve (deadlock) | `grep -n 'act + 1' CA` ⇒ `789` (active) and `839` (reserve-active); D2 C3 names only ":832 net-zero delta (U05 §5.5 i)"; U05 §3.2: 17:17:43–17:18:47 four `reserve-active` refusals "7 sessions mid-turn + 1 > 8 − 1 = 7 (operator present)"; U05 §4.1 + U10 §1a (Stop never runs on a limit ⇒ beat stays `prompt`); `lr-fire-resume.sh:306-309` contract "delayable but never permanently blockable". |
| 6 | composer read — **absent from D2's pre-irreversible bracket** | a held operator draft (or an unreadable box) is discovered only by `recycle_composer_gate` at HF:11634 and the freshness re-read at HF:11751 — both inside `recycle_fire`, called by LRH:619 **after** the transplant at LRH:516 | a `recycle-held-draft` row (HF:11757) and LRH rc 4 — D2 maps this to `EXITING`/`FAILED-EXIT` | "a human answers the pane" (§4.4) — **impossible**: the pane is now the tombstoned source and `hooks/handed-off-session-guard.sh` (UserPromptSubmit, exit 2) blocks every prompt in it; the draft can only be discarded | **H** by construction; the session stays alive on the dead account over a moved transcript, and its next write re-creates `<sid>.jsonl` beside the tombstone — the 2026-08-16 split-brain the guard was written for | HF:11625-11650 ("bounded wait, then a loud refusal that leaves the session alive"), HF:11751-11759 (`kill "$WATCHER_PID"`, `emit_recycle_event recycle-held-draft`, `exit 1`), LRH:645-652 ("The transplant is DONE … tombstoned husk"), `hooks/handed-off-session-guard.sh:1-12`. D2 §3 row "/exit → shell" cites HF:11634 as the 600 s shell budget — it is `CC_RECYCLE_DRAFT_WAIT` 180/15, pre-`/exit`; the shell wait is HF:6605. |
| 7 | `BUNDLED` (audit + manifest + launcher) | two drivers in the same second share `bundle-$TS` (second resolution, `mkdir -p`) and the loser's `> "$BUNDLE/transplant.json"` truncates the winner's proof | no | — | winner cannot prove `TRANSPLANTED` (§2 requires `"ok":true` in `transplant.json`) | LRH:384-386, LRH:516. Same-second collision **not observed today** (kicks were 10 s apart) — labelled extension of #2. |
| 8 | `TRANSPLANTED` — LRT | driver dies, or the sha FATAL fires, between the lock write (`LRT:66-69`) and the tombstone (`LRT:91-100`): lock + dest present, source intact, no tombstone | partly — the state store correctly does NOT read TRANSPLANTED (needs all three proofs) | **no** — `repair --from BUNDLED` re-runs LRT, which refuses on `DST` exists (`:55-57`) and on lock exists (`:63-66`); D2 §C3 calls that "the right refusal" and exposes no `--force`; C4 skips a new request when `locks/<sid>` exists | **L** on the one-command path (the sid can only come back via the poller's reset-wait on the SOURCE account, hours later) | `LRT:55-100` read in full; D2 §C3 "never re-transplanting … refused by its own destination-exists guard, which is the right refusal". The sha race is real but narrow: CC keeps appending to the source after the error (d02d8feb: `turn_duration` +7 ms, then 9 untimestamped state records, then a `queue-operation` at 17:19:50 — 20 min later and 5 s AFTER the 17:19:45 cp). |
| 9 | `EXITED` — watcher W2, 600 s | pane never reaches a shell (modal, held `/exit`) | yes — `EXITING +Ns`, then `FAILED-EXIT` | `repair --from EXITED` re-enters AFTER the exit it is trying to redo (naming) | none (visible) | D2 §3, §4.4. Minor. |
| 10 | `RELAUNCHED` — 2 × 20 s | `lr-fire-resume` refuses; `session-register` slow so the registry pid does not turn over inside 20 s | yes — `FAILED-RELAUNCH` with the IDL cause | yes via C13 | none | C5 exports verified as the only env channel (U01 §5.1, U04 §2); `session-register.sh` is in all 5 `settings.json` SessionStart lists (`jq` ⇒ 1/1/1/1/1). **Sound.** |
| 11 | `SUBMITTED` — transcript probe | READY never seen; `/`-autocomplete swallows CR | yes — `FAILED-SUBMIT` ≤ 40 s | yes via `cc_tui_submit_verified` | none | U03 §4; the record shape verified on pane 117. **Sound**, and it correctly rejects 112's `Continue from where you left off.` / `No response requested.` pair (U11 §0 B). |
| 12 | `ENGAGED` | slow first turn on a cold 600 K-token cache | yes — `FAILED-ENGAGE` at 180 s | re-send only if composer idle | none | D2 §4.4 row 9; HF:6861-6866. **Sound.** |
| 13 | driver deadline 15 min | the ceilings D2 itself lists sum to **984 s** without the composer gate and **1164 s** with it (§6 keeps it); C7's own `recycle_await_verdict` max becomes **1060 s** — both exceed the 900 s deadline | `FAILED-TIMEOUT` is written **while the detached watcher is still working** | `repair --from <last state>` starts a SECOND actor on a pane the first watcher still owns | **D** on the pane; a late `recycle-engaged` from the orphan is never translated into the store; a `repair --from SUBMITTED` re-types the ingest prompt into a session that already ingested | D2 §3 (sum claimed "≈13.9 min"; recomputed: 2+3+60+30+600+40+38+0.7+30+180 = 983.7 s), §C7 (`max = 180+600+40+180+60`), HF:11784-11806 (today's 900 s), HF:11723 (watcher is `detach`ed — PPID 1, survives the driver). |
| 14 | `status --sweep` (husk / dead driver) | the sweep is on the poller's 600 s tick; `kill -0 driver_pid` has no `lstart` guard; a dead driver with a LIVE orphan watcher is marked `FAILED-DRIVER-DIED` and repaired over it | 3–13 min late; correct in the common case | yes | **D** in the orphan-watcher case (same as #13) | D2 §3 last row, §C1; `hooks/session-register.sh:278` keys pid liveness on `lstart` (U07 §4) — `state.json` in §4.2 has `driver_pid` only. |
| 15 | `DONE` — request removed, parked retired, mailbox line, `cc-notify --role desk` on failure | `cc-notify` returns an honest `verdict=` token (`delivered|mailbox-only|unverified|…`) that the driver never records | the page is a **claimed** outcome | — | none, but the "page + repair" cell in §4.4 is not evidence of an owner | `bin/cc-notify:61-67, 98-103` (`enqueued=1` is the load-bearing field; a reroute does NOT upgrade to delivered); memory `claimed-outcome-vs-checked-outcome`. The durable store is `hf_alarm` → `~/.claude/handoff-alarms/`, swept by `scripts/autonomy-sweep.sh:1921` — that arm is real. |
| 16 | `index.jsonl` upsert | N concurrent drivers (`cc-lr --all`) read-modify-write one file with no lock | a lost line = a run `status` cannot list | — | invisible run | D2 §4.2 ("upserted"), §C1 (`status` reads `index.jsonl` first); memory `append-atomicity-ends-at-the-stdio-buffer`. |
| 17 | fast-path ingest (C5, `lr-ingest-verify.sh`) | a subagent in flight at `/exit` is killed; the bundle audit and `--ledger-only` both read `spawned == settled, open 0, gaps 0` | no — the run reads `DONE` and the recovered session is told "nothing is owed and nothing re-runs" | — | **L** (work) | `~/.reso/limit-recover/fleet/one-20260919T174851Z/*.stderr:6` ⇒ "recycle proceeding with 1 IN-FLIGHT subagent(s) … being KILLED deliberately"; `jq` over `28f07827…/bundle-20260919T174936Z/audit.json` ⇒ `{"counts":{"subagents":13,"gaps":0,"waiting":0},"deleg":{"spawned":16,"settled":16,"open":0}}`; `MANIFEST.json gaps_at_handoff: 0`. D2 §C5 gates the one-line prompt on exactly those predicates (U12 §6.1 A, B). |
| 18 | reset time, `REFUSED-TARGET` runs | the poller's kept NUDGE arm (`lr-reset-poller.sh:928-943`) types `/limit-recover` into the live pane while the drain's `cc-lr` driver transplants and `/exit`s it | no | — | **D** on the pane | D2 §C10 ("the reset-wait remains the FALLBACK … no longer the first branch") keeps both arms; U06 §1 (NUDGE / SPAWN arms); nothing sequences the two. |

## 2. Refutations, ranked

### R1 · MAJOR — the composer-draft check is on the wrong side of the irreversible edge, and D2 has not noticed
**Claim (D2 §2):** "TRANSPLANTED is the only irreversible edge, and it is entered only from ADMITTED …
pre-irreversible (nothing changed on failure)". **§4.4:** "pane never reaches a shell (held draft,
modal) → EXITING +Ns then FAILED-EXIT at 600 s → a human answers the pane". **§3:** "the 600 s is the
composer-draft gate's budget (HF:11634 …)".

**Why it is wrong.** HF:11634 is `CC_RECYCLE_DRAFT_WAIT` 180 s / 15 s, the *pre-`/exit`* foreground gate
in `recycle_fire`; the 600 s is HF:6605 `HF_RECYCLE_SHELL_WAIT_S`, the *post-`/exit`* watcher wait. D2
conflates them, and the conflation hides the ordering: LRH transplants at `:516` and only then calls
`handoff-fire --recycle` at `:619`, so the draft gate (HF:11625-11650: "bounded wait, then a loud
refusal that leaves the session alive and the draft intact") and the freshness re-read (HF:11751-11759:
kills the watcher, `recycle-held-draft`, `exit 1`) both refuse **over a transcript that has already
moved**. LRH:645-652 then prints "The transplant is DONE … the source pane is a tombstoned husk". The
"human answers the pane" repair is not available: `hooks/handed-off-session-guard.sh` (UserPromptSubmit,
exit 2) blocks every prompt in that pane by design, so the draft cannot be submitted, only discarded —
and the session's next write re-creates `<sid>.jsonl` beside the tombstone, the 2026-08-16 split-brain
in the guard's own header. On the zero-touch default (C4 `auto` on) this fires ~0.3 s after a limit that
hit mid-turn, when a half-typed draft is the realistic composer state.

**Why not fatal:** base rate 0/5 today (all five watcher logs show `CONFIRMED at a shell prompt after
3–6s`); the fix is one 40 ms read. **Why it matters anyway:** D2's DoD row 8 counts "panes at a bare
shell over a transplanted sid" — this husk is at a live CC, so the drill is blind to it.

**Fix:** run `composer_content` (HF:2392, one `it2 session read`) — or `recycle_composer_gate` with
wait 0 — in the driver **before** BUNDLED, add `REFUSED-COMPOSER` to the pre-irreversible set, keep the
freshness re-read as the belt, and re-cite §3's row against HF:6605.

### R2 · FATAL — `NET_ZERO` patches one of two `+1` sites; the other is the term that refused today, and limited husks make it a deadlock
**Claim (D2 §C3, §4.4 row 3):** `CC_ADMIT_NET_ZERO=1` on "`capacity-admit.sh:832` net-zero delta
(U05 §5.5 i)"; a refusal on active "for 60 s → REFUSED-ADMIT → re-run; nothing was moved".

**Why it is wrong.** `grep -n 'act + 1' scripts/lib/capacity-admit.sh` ⇒ **789** (`active`) and
**839** (`reserve-active`: `act + 1 > act_ceiling − act_reserve`, only when `CC_ADMIT_PRESENCE = present`
— i.e. exactly when an operator is running `/limit-recover`). U05 §5.5(i)'s diff, which D2 adopts by
citation, touches the `active` site only. Today's phase-2 refusals were `reserve-active`, four times,
"7 sessions mid-turn + 1 > 8 − 1 = 7 (operator present)" (U05 §3.2). Under D2 that phase replays as
60 s of probes → `REFUSED-ADMIT`, terminal, "re-run".

The re-run cannot succeed on its own: `cc_capacity_probe` is non-charging and **non-releasing**
(`CA:516`, `CA:923-931` — "no budget file touched, no page, no release"), so the only thing that lowers
`act` is a limited session being recovered — which this term refuses. And `act` counts the limited
sessions themselves: Stop never fires on a limit turn (U10 §1a, 5/5 measured), so `session-beat.sh`
leaves `kind:"prompt"` standing over a pid that stays alive idle at the error (U05 §4.1). With
N_limited ≥ ceiling − reserve (7 today, with 5 limited sessions in the census) the fleet is permanently
blocked, the exact state `lr-fire-resume.sh:306-309` forbids ("delayable but never permanently
blockable"). The launcher's `CC_ADMIT_BUDGET=1` release (C5) never gets a chance to fire because the
driver refuses before typing anything.

**Fix:** (a) apply the net-zero delta at `CA:839` too; (b) either the `kind:"limited"` beat stamp
(U05 §5.5 ii) or exclude from `act` any pid whose transcript tail is an api-error, so a limited fleet
does not refuse its own recovery; (c) give `REFUSED-ADMIT` a bounded retry with a page, not a terminal
"re-run".

### R3 · MAJOR — three drivers per limit event, by design, and no per-sid exclusion
**Claim (D2 §C4):** latch "event-keyed, never sid-keyed — `e442434c` fired 3× in 16 s"; **§C3:** "N runs
are independent except for the per-sid lock (`lr-transplant.sh:60`)"; **§C10/§C11:** the drain kicks
`cc-lr <sid> --from-request`; WatchPaths on `requests/` fires the poller on the write.

**Why it is wrong.** The three firings D2 cites are three distinct death uuids:
```
python3 … e442434c-*.jsonl.handed-off  =>  16:58:33.848Z 76079a2e-…  16:58:43.293Z 57ec86da-…  16:58:49.027Z 3f08d075-…
```
so C4 writes three requests (same path, overwritten) and kicks `cc-lr` three times; C11 adds a fourth
kick per write. Every driver passes RESOLVE → TARGET (three `--assign` phantoms, 12.5 % of score each,
U13 §3c) → ADMIT → BUNDLE, and the losers die at LRH:516 (`set -e` on LRT's lock refusal `:63-66`),
which D2 must then record as a failure and page (§C3 "any FAILED-*: … `cc-notify --role desk`"). `status`
shows one recovering sid with two FAILED rows; the desk gets two pages for a success — the alarm-polarity
defect. Same-second kicks would additionally share `bundle-$TS` (LRH:384) and the loser's
`> transplant.json` (LRH:516) would truncate the winner's TRANSPLANTED proof (labelled: not observed
today, kicks were 10 s apart). Neither the drill (§5 fires `cc-lr` by hand ×5) nor DoD row 9 (`0
dangling` — the losers have terminal rows) can see this.

**Fix:** a per-sid active-run lock in `cc-lr` (`set -C` on `runs/by-sid/<sid>.active`, released at any
terminal row); the drain and the hook both go through it; `status` folds the refused duplicates as
`SUPERSEDED-BY <id>`, never FAILED.

### R4 · MAJOR — the driver deadline is smaller than the sum of its own ceilings, and the watcher outlives the driver
**Claim (D2 §3):** "driver deadline 15 min hard — sum of every ceiling above ≈ 13.9 min".

**Why it is wrong.** From D2's own table: 2 + 3 + 60 + 30 + 600 + 40 + 38 + 0.7 + 30 + 180 =
**983.7 s = 16.4 min**, before the `CC_RECYCLE_DRAFT_WAIT` 180 s that §6 explicitly keeps
(**1163.7 s = 19.4 min**). D2's own C7 sets `recycle_await_verdict` max to 180 + 600 + 40 + 180 + 60 =
**1060 s**, larger than the 900 s driver deadline it sits under. This is the
`docs/lessons/inner-bound-outer-bound-starves-the-tail.md` shape U05 §3.4 invokes against the old
watcher, reproduced one layer up. Consequence: any run that legitimately spends its shell wait (a modal,
a held `/exit`) is written `FAILED-TIMEOUT` while the watcher — `detach`ed at HF:11723, PPID 1 — keeps
going and may later write `recycle-engaged`; nobody translates that into `runs/<id>`, `status` says
FAILED over a live engaged pane, the requester's mailbox line says failed, and `repair --from <last
state>` starts a second actor on the pane (a `repair --from SUBMITTED` passes the emptiness gate and
re-types the ingest prompt into a session that already ingested). Two owners, no rule.

**Fix:** deadline = Σ ceilings + slack, computed from the same constants; record `watcher_pid` in
`state.json`; on driver timeout either adopt the watcher (keep tailing its log) or kill it — never leave
both; `repair` refuses while a watcher pid for that pane is alive.

### R5 · MAJOR — a half-transplant is unrepairable on the one-command path
**Claim (D2 §C3):** "`--from <STATE>` … never re-transplanting: a second `lr-transplant.sh` on a moved
sid is refused by its own destination-exists guard (`lr-transplant.sh:55-57`), which is the right
refusal."

**Why it is wrong.** LRT's order is lock (`:66-69`) → `cp` (`:72`) → `rsync` (`:74-83`) → sha FATAL
(`:85-89`, `exit 2`) → tombstone + `mv` (`:91-100`). A driver death or a sha mismatch between `:69` and
`:93` leaves lock + destination copy with the **source intact and not tombstoned** — a session that is
still live-able on its source account. D2's TRANSPLANTED proof correctly does not fire (needs all three),
but every repair entry re-runs LRT and is refused at `:55` and `:63`; `repair` exposes no `--force`; C4
skips any new request because `locks/<sid>` exists. The sid is stranded on the fast path. The sha race
is narrow but real: the source keeps being appended after the error (d02d8feb: `turn_duration` at
+7 ms, nine untimestamped state records, then a `queue-operation` at 17:19:50 — 20 min after the limit
and **5 s after** the 17:19:45 cp; `mtime 17:19:54Z`).

**Fix:** a `TRANSPLANTING` state written before LRT runs; `repair --from TRANSPLANTING` = verify source
sha unchanged, remove the partial dest + lock, re-run; the poller's HUSK arm (C10) already leaves the
parked record for this case — make it page.

### R6 · MAJOR — the ingest fast path certifies "nothing owed" over a subagent the recycle just killed
**Claim (D2 §C5, DoD row 12):** the one-line prompt when `lr-ingest-verify.sh` rc 0; "`gaps_at_handoff:0`
honoured".

**Why it is wrong.** Pane 114's recycle killed one in-flight subagent
(`fleet/one-20260919T174851Z/*.stderr:6`: "recycle proceeding with 1 IN-FLIGHT subagent(s) … being
KILLED deliberately"), and the bundle audit cut seconds earlier reads
`counts.gaps 0, waiting 0, delegations spawned 16 / settled 16 / open 0`, `MANIFEST gaps_at_handoff 0`.
Every predicate in U12 §6.1 A and B passes, so the recovered session is told "nothing is owed and nothing
re-runs" and the run reads `DONE`. The only record of the loss is one stderr line the driver does not
lift into `events.jsonl`. This is a lost-work outcome the state store reads as success. (Today's full
ingest was equally blind — U12 §5 post-move audits read the same numbers — so D2 does not regress it;
it institutionalises it.)

**Fix:** capture LRH's `IN-FLIGHT subagent(s)` line as a `killed_inflight: N` evidence field on
`BUNDLED`; `lr-ingest-verify.sh` must fail (full ingest) when N > 0; the audit's delegation ledger needs
the pid-census instrument the fleet already uses.

### R7 · MAJOR — REFUSED-* states do not consume the request, and the reset-wait arm is a second actor
**Claim (D2 §4.4 row 2, §C10):** no routable account → `REFUSED-TARGET` → "wait for reset (poller
fallback)".

**Why it is wrong.** §4.2 removes `requests/<sid>.json` only at `DONE`. A terminal `REFUSED-TARGET` leaves
it, so every 600 s tick the drain mints a new run and (per §C3) a new page — ~16 of each across today's
2 h 41 m wait — while §C10's reaper pages the same request for being "older than 2 ticks". At reset, the
poller's kept NUDGE arm (`lr-reset-poller.sh:928-943`, types `/limit-recover` into the live pane) and the
drain's `cc-lr` driver (transplant + `/exit` of that pane) act on one pane with nothing between them.

**Fix:** a terminal REFUSED-* row parks the request (`requests/<sid>.json` → `parked/`, with the
reason) and the drain ignores parked sids; at reset the poller picks ONE arm per sid.

### R8 · MINOR — visibility claims that are claimed, not checked
- `cc-notify --role desk` is fire-and-forget in §C3; the tool prints `verdict=<delivered|mailbox-only|…>
  enqueued=<0|1>` precisely so a caller cannot mistake an enqueue to a dead inbox for a delivery
  (`bin/cc-notify:61-67, 98-103`). Record the token in `events.jsonl`. The durable arm — `hf_alarm` →
  `~/.claude/handoff-alarms/`, swept at `scripts/autonomy-sweep.sh:1921` — is real and is what makes
  C7's H8 fix count.
- `index.jsonl` is "upserted" by N concurrent drivers with no lock (§4.2, §C1); a lost line is a run
  `status` cannot list. `status` should glob `runs/*/state.json` and treat the index as a cache.
- `state.json.driver_pid` has no `lstart`; the registry already keys pid liveness on it
  (`hooks/session-register.sh:278`).
- The sweep lives on the poller's 600 s tick with no alarm on its own liveness (memory
  `alarm-must-key-on-the-store-not-the-sensor`); a dead poller is silent.
- C4's `cc-lr … &` runs inside a hook's process group; the repo records that a hook's group IS killed by
  the pane teardown (`hooks/waiting-recycle.sh:1445-1457`). Whether CC also reaps hook children at hook
  exit — before `cc-lr`'s ≤2 s resolve reaches its `setsid` — is unmeasured; the belt (600 s drain)
  exists but the "~0 s" path degrades silently. Measure it before trusting the latency claim.
- `repair --from EXITED` (§4.4 row 6) re-enters after the step it means to redo; the entry for a failed
  `/exit` is `--from TRANSPLANTED`.
- `runs/<id>/watcher.log` is copied "at every state change" by the driver; a dead driver leaves the
  only copy in `$TMPDIR`, wiped at boot (memory e2d8c9816).

## 3. Today's five, replayed against D2 as written

| pane / sid | what happened | under D2 | verdict |
|---|---|---|---|
| 112 `d02d8feb` | phase 1: 658 s park on load; phase 2: 4 × `reserve-active` refusals (7 mid-turn + 1 > 7); `RECOVERED` on a two-day-old counter; ingest never delivered; engagement satisfied by `Continue from where you left off.` / `No response requested.` | load term off removes phase 1. **Phase 2 replays as-is** — `CA:839` is untouched (R2): 60 s → `REFUSED-ADMIT`, terminal. If an operator re-runs after some session leaves, the rest is right: `SUBMITTED` refuses the meta record (no bundle path), no false `ENGAGED`, `FAILED-SUBMIT` ≤ 40 s → `repair`. | **not recovered on first run**; the false RECOVERED is fixed |
| 111 `09e64dcb` | 2 load refusals → husk; hand relaunch; ingest typed but unsubmitted 17 min | C5 admits on attempt 1; READY (`auto mode on`) → inject → transcript probe; one re-CR rescues the `/`-autocomplete swallow; else `FAILED-SUBMIT` at ~40 s with a named repair | recovered, named |
| 121 `e442434c` | 3 limit records in 16 s + 1 at +28 min; 2 load refusals → husk; hand relaunch; composer residue fight; ingest never delivered | **three drivers** (R3): one wins the lock, two die at LRH:516 and page the desk as failures; three `--assign` phantoms. The winner: same path as 111. The +28 min re-fire never happens (pane recycled at ~16:59). | recovered, with 2 spurious failure pages |
| 114 `28f07827` | in-flight subagent killed at `/exit`; 2 load refusals → husk; hand relaunch; hand ingest | 3–4 death uuids (17:07:35, 17:09:46, 17:09:50, 17:14:48) ⇒ R3 again. Recovery path fine. **The fast path certifies "nothing owed" over the killed subagent** (R6); run reads `DONE`. | recovered; lost work invisible |
| 117 `cb227486` | 4.15 → 6.73/core refusals → husk; hand relaunch; ingest arrived +2 m 27 s (U03 says by hand, U11 says the day's one auto-submit — the units disagree; D2's transcript oracle settles it either way) | admitted; `SUBMITTED` proven from the record U03 §4 quotes | recovered, named |

Net: **4/5 recovered on the first run (vs 1/5), 0 husks at a bare shell, but 1 fleet-level refusal that
today's own inputs trigger (R2), 2 spurious failure pages (R3), 1 silently lost subagent (R6)**, and
none of the three is visible to the §5 drill.

## 4. Keeps

- **The skeleton**: one run dir per attempt, `state.json` via tmp+mv, append-only `events.jsonl`, a
  `setsid` driver (`HF:1608-1616` verified; `hooks/validate-bash.sh:49,191-342` keys the live-goal deny
  on `run_in_background`, so a <2 s foreground `cc-lr` is untouched).
- **The submit oracle** (C6, U03 §4): a `type:"user"` record carrying the bundle path in the TARGET
  transcript, and `ENGAGED` only after that record's timestamp. It is the one change that makes
  `RECOVERED` mean something, and it correctly rejects both of today's false engagements.
- **C7's row + alarm on the H8 arm**, copied from its siblings (`HF:6796-6798`, `:6873-6875`);
  `target_pane` joins (D2 measured it). The alarm reaches `autonomy-sweep.sh:1921`.
- **C5's launcher exports** as the only env channel into the pane's fresh process tree (U01 §5.1,
  U04 §2) — with the second `+1` site added (R2).
- **Per-run `CC_ADMIT_BUDGET_KEY`** (`CA:509-514` keys per caller today; today's one success rode a
  sibling's spend).
- **C10's tightened retirement** — `lr_transplanted_to` (`lr-lib.sh:262-273`) reads lock + file only;
  requiring `DONE`/`ENGAGED` or a live registry row under the target is the right predicate.
- **The resolver's refusal on ambiguity** and the 2 s kitty bound with `INDETERMINATE` (U07 §5, §6c).
- **C4's latch semantics** (event-keyed, tombstone/lock skip) — keep, add the per-sid run lock (R3).
- **Not touching `lr-transplant`'s lock/tombstone semantics** — keep, add the `TRANSPLANTING` repair
  entry (R5).
- **`recycle_await_verdict` interval 5 → 0.5 s and `recycle-submitted` in its grep** (C7).
- **Copying the watcher log out of `$TMPDIR`** at every state change (§4.2).
- **The composer-draft gate and the 600 s shell wait themselves** (§6) — right polarity; only their
  position (R1) and their sum (R4) are wrong.
