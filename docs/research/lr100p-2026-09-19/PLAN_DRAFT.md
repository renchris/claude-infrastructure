# LIMIT_RECOVER_100P — reopen draft, 2026-09-19 (the second incident)

Synthesizer: this draft is the INTEGRATION PAYLOAD for `docs/plans/LIMIT_RECOVER_100P.md`. It was
built from 14 research units (U01–U14), 3 designs (D1 zero-touch · D2 one-command · D3
identity-observability) and 9 critiques (3 lenses × 3 designs) under
`scratchpad/lr/{research,design,critique}/`, re-verified against the live tree at `226b73888`
(`git rev-parse --short HEAD`, 16:02 today — the tree moved under the corpus: `226b73888
fix(limit-recover): a limit corpse inflates the census …` landed `lf_phantom_actives()` in
`lr-fleet.sh:307` AFTER every unit and design was written; § 9.3 below records what that changes).
Every `file:line` was re-read this session; a claim I could not measure is marked **GUESS**.

---

## 0. How this draft integrates into `docs/plans/LIMIT_RECOVER_100P.md` (INTEGRATE, never overwrite)

The existing plan (sections 1–8, two "§ 6 Status log" blocks, `status: complete`) is history and
stays byte-for-byte. Four edits, all `Edit`-tool insertions:

1. Frontmatter: `status: complete` → `status: open` (the plan-open falsifier must be able to fire
   again; the 2026-09-10 close was an n=1 acceptance — U09 §0, gap #17).
2. Insert **§ Phase 0** (below) as the FIRST section after the title/Scope block — the plan
   conventions require Phase 0 first for any plan with 2+ code-writing tasks; the closed plan never
   had one.
3. Append **§ 9 – § 16** (below) after the last "§ 6 Status log (continued)" entry.
4. Append the **§ 6 status-log entry** (last block below) to "§ 6 Status log (continued)".

Scope (grown, 2026-09-19): `+ the operator's second target — identify a halted pane from a
screenshot/keyword in <2 s; ONE non-blocking command transplants it to a ranker-chosen account and
recycles it IN PLACE, verified ENGAGED on the prompt we sent; every failure is a named, re-drivable
row within 30 s; zero silent husks in a 5-session drill; the invoking session is never blocked;
minimal tokens.` The frozen 2026-09-08 scope ("every limited session located, continued in its own
pane, no husk, no orphan, no ambiguity") is unchanged and was NOT met on 2026-09-19 (§ 9).

---

## Phase 0 — Agent Team Orchestration (execution locus per wave)

**EXECUTION LOCUS PER WAVE — S (dispatched `handoff-fire.sh` session) for every wave.** No wave is
T or L: each wave is 90–300 lines across ≤ 5 files with its own bats DoD, and the lead's context is
the scarce resource (this reopen already consumed one lead to a next3 limit at 19:53Z — see § 9.2).
Fire each wave with `--goal '<the wave's acceptance line> — proven by <the bats command it runs and
prints>; do not touch a live pane; full brief in the prompt, DoD at docs/plans/LIMIT_RECOVER_100P.md
§ 12.<n>'`, `--worktree lr100p-w<n>`, `--split-right --notify-back`. The lead does NOT park on
`cc-await-ping` (a `/goal` is live in the firing pane; CLAUDE.md § Agent Teams).

**Lead's own context budget + succession point.** The lead holds ≥ 50 % of its window for
adjudicating wave returns and the drill; it fires W1 ∥ W4 ∥ W6a in ONE message (independent
files), then W2, then W3 on W2's land, then W5, then W6b + W7. Succession: at ~60 % fill or after
W3 lands, whichever first, `handoff-fire.sh --recycle --worktree lr100p-lead-2` with this file as
the bridge (`Recycle` row of § Context Stewardship — everything is on disk).

**Roster and worktrees** (one branch per wave, off `origin/main`; land via the project-local
`/ship`; converge with `CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh` after each land —
the launcher execs the LIVE `lr-fire-resume.sh` (`lr-handoff.sh:162`), so an unconverged land is
inert and `lr-handoff`'s preflight (`:497`) will refuse it):

| wave | branch | owns (no other wave writes these hunks) | depends on |
|---|---|---|---|
| W1 | `lr100p-w1-nonblocking` | `lr-fleet.sh` (`--detach`, rc-4 note, parked note), `handoff-fire.sh:6878-6880` only, `scripts/lib/detach.sh` (new), `commands/limit-recover.md` front section | — |
| W2 | `lr100p-w2-one-decision` | `capacity-admit.sh` (token, budget key), `lr-lib.sh` (`lr_state_append`, `lr_capacity_probe_corrected`), `lr-handoff.sh` (pre-checks, mint, launcher), `lr-fire-resume.sh:320-333` + spawn line, `handoff-fire.sh:6786-6816` (boot wait) + a read-only `--probe-recycle-preconditions` verb | W1 landed (shared file `handoff-fire.sh`, different hunks — rebase, never merge) |
| W3 | `lr100p-w3-submit-ingest` | `lr-fire-resume.sh:549-583`, `lr-submit-probe.sh` (new), `lr-ingest-verify.sh` (new), `lr-handoff.sh:464` + HANDOFF-CONTEXT/MANIFEST trim, `lr-preseed-env.sh:115-117`, `handoff-fire.sh:3680-3715` (`resume_engaged` token arg), `hooks/session-continue.sh` `clear` sid-guard | W2 landed |
| W4 | `lr100p-w4-identity` | `statusline.sh`, `bin/cc-find` (new), `lr-fleet.sh:217` + `--one` registry-first, `lr-lib.sh:20-27`, `tests/statusline-identity.bats` | — (parallel with W1/W2) |
| W5 | `lr100p-w5-lane-state-reaper` | `hooks/stop-failure-marker.sh` ARM 2, `lr-reset-poller.sh` (§0 claim+detach, §0b reaper, `:896`/`:902-905`), `lr-transplant.sh` (lock custody), `bin/cc-husk-sweep` guard, `bin/cc-lr` (new), `scripts/lib/cc-tui.sh` (new), plist SSOT | W1–W3 landed |
| W6a | `lr100p-w6a-ranker` | `bin/claude-accounts` `--recovery`, `accounts.json .router`, `tests/account-recovery-lane.bats` (new) | — (parallel) |
| W6b | `lr100p-w6b-pool` | `lr-fleet.sh` `lf_pick_target` + serialized admit section + `--all` pool | W5 + W6a |
| W7 | `lr100p-w7-census-drill` | `lr-fleet.sh` `lf_locate` single-pass, `tests/lr-drill.sh` (new), `commands/limit-recover.md` | W5 |

**Brief discipline** (agent-teams skill): ≤ 150 lines per brief, pre-grepped line ranges embedded
(all cited below), "Stop on issue, message lead" verbatim, no visual verification inline (the
30-column glyph check in W4 is an OPERATOR step), no wave > 500 LOC (W5 is the largest at ~300;
if it grows past 400 split the reaper into W5b).

**Dependency graph:** W1 → W2 → W3 → W5 → {W6b, W7}; W4 and W6a are leaves off `origin/main`.
Spawn order: {W1, W4, W6a} → W2 → W3 → W5 → {W6b, W7}.

---

## 9. Reopened 2026-09-19 — the second incident, measured

### 9.1 The morning event (next4 five_hour cap, 5 sessions) — the "before" column

Source: the lead transcript (U11 §1–§3), `~/.reso/limit-recover/fleet/one-20260919T17{0450,1910,
2126,4403,4851,5207}Z/results.tsv` (re-read this session), `~/.claude/autonomy/idl.jsonl`,
`~/.claude/logs/handoffs.jsonl`.

| quantity | before (2026-09-19 morning) | source |
|---|---|---|
| wall, first `/limit-recover` → last land | **98.7 min** (12:01:33 → 13:38) | U11 §1 |
| tool calls / minutes inside tool calls | 146 / 68.8 min (70 % of wall) | U11 §1 |
| lead turn-minutes spent in foreground `until` polls | **24.4 min**, 17 polls, every one exited 1–5 s AFTER a `task-notification` that would have woken it | U11 §2 |
| operator-visible: screenshots queued behind those turns | **86 min 52 s** cumulative (13.5 / 38.1 / 35.2 min) | U11 §2 |
| per-session `lr-fleet --one` wall | 115 / 148 / 152 / 155 / 158 s; **658 s** when parked | U14 §2.1 |
| in-place success | **1 / 5** — and that one was an artefact: its first launcher call read `refusal 3 of budget 3` on a counter a 2-day-old refusal had pre-spent (`idl.jsonl` 2026-09-17T23:58:51Z → 17:19:59Z `budget-expired`) | U01 §5.3, U03 §1, U05 §3.4 |
| husks with a ledger row or alarm | **0 / 4** — `handoff-fire.sh:6878-6880` is the only terminal arm that emits neither | U04 §3, U01 §4.1 |
| ingest delivered by the expect layer | **0 / 5** (1 auto-submitted by hand-retype, 2 by hand, 2 never); "ENGAGEMENT CONFIRMED" on pane 112 was a queued `<task-notification>` turn | U03 §0, U11 §0 |
| identification | `lr-fleet --locate` 40–86 s (99.8 % fork overhead; one Python pass = 0.148 s); statusline carries no pane id / sid; `account+cwdbase+sha+effort` collides 3/16, panes 122/124 byte-identical | U14 §0, U07 §0, §4 |
| manual repair of the 4 PARTIALs | ~34 min total (pane 111: 17.1 min, 13.1 of it polling an unsubmitted prompt; `cc-pane send` rc 0 delivered nothing — its text path is iTerm2 AppleScript and iTerm2 is not running; `it2 session send CR` typed the letters C,R; `kitty @ send-key ctrl+u` rendered `^[[117;5u` because CC pushes the kitty keyboard protocol) | U11 §3, §7; U08 §3 |
| detection → first fire idle | 2 h 37 m across 5 (StopFailure had all five on disk by 12:07; the poller parked all five by 12:09; nothing read either) | U10 §1g, U06 §2 |
| resident tokens added by ingest | ~26.5 K per recovered session, 6–9 model round trips; 88 KB `HANDOFF-CONTEXT.md` read and discarded | U12 §3 |
| ranker | fable lane put `next` (weekly 98 %) at rank[0] — a 40× urgency term cancelling a 24× headroom deficit; `next` hit weekly 100 % 1 h 54 m after being named; the pick's stderr rationale is discarded at `lr-fleet.sh` `lf_pick_target` (`2>/dev/null`) | U13 §1, §3a, D2 |

Per-sink, in scope for this plan (U11 §7): #1 polls/queued screenshots 24.4 (lead) / 86.9
(operator) · #2 capacity park 11.1 · #3 pane-111 submit 17.1 · #5 4 × PARTIAL + repair ~10 ·
#7 six censuses 4.2 · #8 zero-byte run 1.8 = **68.6 lead-minutes per 5-session event ≈ 13.7 min per
recovery**, plus 17.4 min per recovery of operator-visible queue latency. Out of scope, named so they
are not laundered into the after column: #4 ship-land polling 12.5 min and #6 the `git reset --hard`
permission prompt 7.7 min were the LEAD's own commit-on-`main`-in-the-shared-checkout (U11 §5), not
the tooling's.

### 9.2 The afternoon event (next3 five_hour cap, 8 sessions incl. this plan's lead) — it recurred

Measured this session, all read-only:

- `~/.claude/autonomy/stop-failure/rate_limit__next3.jsonl`: 12 rows 19:52:33Z → 20:29:28Z for
  8 sids (`98f02458 09e64dcb 11569d45 65186f1f 8843bcf3 4bc1159f 26cd14be 07e30aeb`); the poller
  PARKED all 8 (`poller.log` 19:54:10Z → 20:35:06Z) and waited for `21:30:00Z`.
- Transplants 20:47–21:02Z (`locks/` mtimes 15:47–16:02 local). `idl.jsonl`, `caller=lr-fire-resume`:
  `20:47:49 refuse active` → `20:48:38 admit active budget-expired`; `20:53:38 / 20:54:27 / 20:56:11
  refuse active` → `20:57:00 admit budget-expired`; `20:58:06 / 20:59:48 / 21:00:37 refuse active` →
  `21:02:18 admit budget-expired`. The fleet PROBE admitted every one (`caller=lr-fleet … admit …
  measured`, 20:47:38 → 21:02:05) because `226b73888`'s `lf_phantom_actives` subtracts limit-corpse
  beats on the probe side — **and the launcher, which never saw that correction, refused on the same
  term.** The probe/launcher split moved from the load term (morning) to the active term
  (afternoon). It is structural, not per-term (§ 11.1 invariant I4).
- `handoffs.jsonl` today: **15 `recycle-intent` · 7 `recycle-engaged` · 1 `recycle-held-draft` ⇒
  8 intents with no terminal row.**
- **Pane 147 (sid `07e30aeb`) is a live stranded-draft husk on the box right now**: lock
  `{"from":".claude-tertiary","to":".claude-secondary","ts":"2026-09-19T20:49:39Z"}`; tombstone
  `07e30aeb….HANDOFF.json` + `….jsonl.handed-off` (1,157,520 B) in the SOURCE store; the target copy
  present on `.claude-secondary`; then `recycle-held-draft` at 20:52:42Z (`composer non-empty for
  180s`); a **re-created 2,886 B `07e30aeb….jsonl` stub beside the tombstone** (mtime 15:52 — the
  live TUI appending by path after the rename); pid 84167 ALIVE on next3 (`ps -p 84167` ⇒ `claude
  --permission-mode auto --model claude-opus-5`), kitty 147 `in_alternate_screen: true`, title
  `✳ Bottle image review for Studio60 menu` — a mission-board customer session. The operator's next
  Enter in that pane is refused by `hooks/handed-off-session-guard.sh`. This is D1-FT R5 / D2-FT R1
  / D2-safety R2 / D3-FT R2 / D3-safety R3 — six critiques predicted it from the ordering at
  `lr-handoff.sh:517` (transplant) → `:628` (handoff-fire, whose composer gate is `:11634`) — live.
  **W2 fixes the ordering; the live pane is a `cc-backlog needs` row with the manual relaunch
  (`bash <launcher>` in pane 147 once the draft is cleared) — filed by W2's session, not here.**

### 9.3 What already landed today, and what it changes

`226b73888` (`lr-fleet.sh:307` `lf_phantom_actives`, `LR_FLEET_PHANTOM_CORRECTION=off` kill switch,
33/33 `tests/lr-fleet.bats`, mutation-verified) — the probe no longer deadlocks on the limited
sessions it exists to recover (D2-FT R2, D3-FT R1, D2-latency R2 are DISCHARGED on the probe side
by this commit). Consequences for the synthesis: (a) `CC_ADMIT_NET_ZERO` (all three designs) is
DROPPED — it would double-discount with this subtraction (D1-safety R2/R9, D2-safety R8) and it
patched only one of the two `act + 1` sites (`capacity-admit.sh:789` and `:839`) while the
subtraction corrects `act` itself for both; (b) the `kind:"limited"` beat (D1 C1) is DROPPED for
the same reason and because the commit body records the census discriminator as an open design
call ("filed, not guessed at here"); (c) the admission TOKEN is now demonstrably NECESSARY, not a
deferred residual as D2 §6 argued — the afternoon's launcher refusals are exactly a probe
correction that never reached the launcher. `docs/research/limit-recover-capacity-park-2026-09-19.md`
(`b80f9408e`) correctly names the env-override split; its "designed trade-off, not a defect"
verdict on the park is right for the park and wrong for the husk: the launcher must honour the
probe's decision, or there is no decision.

Live-layer state at synthesis: `wrap-ledger.sh --machine` ⇒ `LIVE_LAG=0 LIVE_ADDS=0` (converged).

---

## 10. What the research refuted in the closed plan (compact; full table U09 §2)

| closed-plan claim | refuted by | class |
|---|---|---|
| "engagement proven by a fresh non-error assistant turn" (plan § 7.7, § 8) | pane 112: a queued `<task-notification>` turn satisfied `resume_engaged`; ingest never arrived (U03 §0) | wrong oracle |
| "no husk, no orphan" (Scope frozen) | 4 husks in one run; 8 dangling intents today; pane 147 live | ordering + a silent arm |
| "the fleet report proves it per session (pane before == pane after)" (§ 7.7) | `pane_after="$pane"` is copied from the input (`lr-fleet.sh` `lf_one`); it reads identical on total failure | vacuous proof |
| "recoveries run one at a time behind the NON-charging probe; the 3-refusal budget is never spent by asking" (§ 7.8, § 4) | the caller that SPENDS the budget is `lr-fire-resume`, in the pane, un-probed; the watcher makes 2 attempts against a budget that releases on the 4th evaluation | wrong side of the pane boundary |
| capacity gate "refuses above 2.0 load/core" treated as the thing to sequence against (§ 4) | `capacity-admit.sh:149-160` documents the load term as WRONG INPUT and it is off on the Agent tool (`hooks/agent-teams-enforce.sh:229`) and the operator's fire (`handoff-fire.sh:6075`); it is still ON for `lr-fire-resume` (`capacity-admit.sh:555,601,636`) — 10/10 morning refusals were `term=load` | retracted term on the recovery path |
| acceptance n = 1 (§ 6, pane 695) | a fresh OS-window one turn old on a quiet box; today's population: long-lived panes, worktrees, an in-flight subagent, 2.1–6.7 load/core | control never reached the bug's regime |
| `WatchPaths` DROPPED "to buy ≤10 min" (§ 8 Filed) | the daemon path is the only non-blocking, classifier-immune one, and the 600 s tick is now its binding latency | the dropped item is the operator's ask |
| non-blocking invocation, screenshot identification, latency/token budget | absent from the plan entirely (the word "screenshot" appears once, in the operator quote) | never in scope |

---

## 11. The architecture that survives the critiques

### 11.1 One paragraph

The chain's real work is ~3 s (audit + bundle + transplant + launcher mint, U02 §1) and the four
things that turned it into 98.7 minutes are each one seam: (1) the relaunch is re-gated in a process
the driver cannot reach, so the probe's admission is not the launcher's — fixed by ONE admission
decision carried as a one-shot token minted after every pre-irreversible read and redeemed
call-scoped inside `lr-fire-resume`, with the probe's phantom correction (already landed) as the
only census correction and no per-term patching; (2) the transplant precedes the reads that could
refuse it — fixed by moving the pane-state, composer, limit-kind, teammate and subagent reads BEFORE
`lr-transplant.sh`, keeping handoff-fire's own gate as the freshness belt and the tombstone as the
`/exit` authorization exactly as today; (3) the one watcher branch that fires on every gate refusal
writes nothing, and the daemon then retires the husk as "the successor carries it" — fixed by making
every terminal arm write a state line + `hf_alarm` + a tty paint, replacing the 90 s corpse-poll with
positive discriminators (`relaunch.rc`, the IDL row, `cc_alive`) and INDETERMINATE-never-re-drive,
and by retiring only on RECOVERED or a live target registry row; (4) the invoker polls files instead
of ending its turn — fixed by detaching the driver (`setsid`) and delivering the verdict through
`cc-notify`'s mailbox. Around that spine: verification is transcript-first (`submitted` = a
`type:"user"` OR `queue-operation enqueue` record carrying the run token in the TARGET transcript;
`engaged` = a non-error assistant record AFTER it), identification is a key in the pixels
(`⌗<pane> <sid8>` left-anchored, +1.2 ms/render) resolved by a registry read that REFUSES on
ambiguity, detection is the StopFailure hook writing a request atomically (policy-gated drain), the
state store is an append-only `events.jsonl` in the run's own bundle dir with a per-sid mutex, there
is exactly ONE actuator per pane (the watcher while it lives; the daemon's reaper only after the
watcher is proven dead by (pid,lstart) AND a live re-read of pane + registry + target transcript),
and the ranker gains survival floors with a serialized pick→assign→probe→mint section so N
recoveries walk down the ranking instead of stacking.

### 11.2 Invariants (a reviewer refuses a diff on any of these)

- **I1 — No irreversible step before every refusable read.** Order in `lr-handoff --in-place`:
  registry bind (exists, `:266-284`) → `lr_last_api_error` kind = limit on the SOURCE transcript →
  teammate test → `pane_cc_state == cc` (affirmative; `unknown` refuses) → composer EMPTY →
  in-flight subagent census recorded → ranker pick + `--assign` → corrected probe → **mint token** →
  `lr-transplant.sh` → `handoff-fire --recycle` (its composer gate re-reads as the freshness belt;
  the tombstone stays the `/exit` authorization, `lr-handoff.sh:605-611`). A refusal before the
  transplant leaves NOTHING moved and writes `HELD:<why>` / `REFUSED:<why>`.
- **I2 — One admission decision.** The launcher's `cc_capacity_admit` redeems the token (one-shot,
  TTL, uid-checked, **sid-enforced**, probe-inert) and evaluates fresh ONLY when the token is absent
  or expired — then with the same term switches as the probe (T3 ratchet) and a per-RUN budget key;
  a fresh refusal is `FAILED:gate:<term>` in ≤ 3 s, never a 90 s wait. Nothing per-operation is
  `export`ed into the recovered session's environment (`env -u` on the spawn line).
- **I3 — One actuator per pane.** While the recycle watcher's (pid,lstart) is alive nothing else
  types into that pane. The reaper reads; it re-drives only by writing a request the daemon claims,
  and only after a live re-read proves the pane is at an affirmative shell (or, for a prompt repair,
  a live TUI with an empty composer and no `expect` on its tty).
- **I4 — A timeout is INDETERMINATE, never a verdict.** Every FAILED needs a positive discriminator;
  a bound expiring yields `STALE:<stage>` + alarm + page + re-read on the next tick.
- **I5 — Transcript over screen.** `submitted`/`engaged` are transcript records; a screen read only
  decides whether to press Enter. `send-text`'s rc (always 0), telemetry age, a `#` comment, and a
  `$TMPDIR` log are never verdicts.
- **I6 — Every terminal state is a row + an alarm + a paint.** `events.jsonl` line, `hf_alarm`
  (swept by `scripts/autonomy-sweep.sh:1026+`), one write to the pane's tty path (repo lesson
  `dead-session-verdict-belongs-in-the-pane`; single `write()`, no escapes), and `cc-notify` to a
  live requester with its `verdict=` token recorded.
- **I7 — Never guess a pane.** `cc-find` refuses a tuple/keyword tie and a stale row; a pane id
  that resolves to a non-limited or teammate session is refused at CLAIM, not transplanted.
- **I8 — A recovery never lands, deploys, commits, or touches the shared checkout.** Iron rule 7;
  all state under `~/.reso/limit-recover/` and `~/.claude/`.
- **I9 — Kill switches exist and are byte-identical-off**: `CC_SF_REQUEST`, `LR_FLEET_PHANTOM_CORRECTION`,
  `CC_ROUTE_RECOVERY`, `LRH_PRECHECK` (new), `CC_LR_REAPER` (new, alarms-only), the
  `autorecover.on` file (operator-owned).

### 11.3 State machine and store

```
requested → claimed → checked → targeted → admitted(token) → transplanted → exit-typed → shell
          → relaunch-typed → gate-admitted → ready → submitted|queued → engaged ≡ RECOVERED
holds (non-terminal, nothing moved):  HELD:draft · HELD:subagents? (no — recorded, not held) · PARKED:capacity:<term> · PARKED:no-target
terminal failures:                     FAILED:<stage>:<cause>   (row + alarm + paint + notify; re-drivable)
reaper verdicts:                       STALE:<stage>            (watcher dead, no positive evidence)
```

Store (all under `${LR_STATE_DIR:-$HOME/.reso/limit-recover}`; the run id IS the bundle dir the
chain already mints, so no parallel tree):

```
<sid>/bundle-<TS>/events.jsonl      append-only, one ≤1 KB jq-encoded line per transition {ts,state,stage,detail,writer,attempt}
<sid>/bundle-<TS>/relaunch.rc       written by lr-fire-resume on any PRE-expect exit (gate refuse 9, arg error) — the positive discriminator
<sid>/bundle-<TS>/INGEST-VERIFIED.txt   W3
<sid>/bundle-<TS>/lr-launch-<sid8>.sh   the launcher (moved out of $TMPDIR, which this box wipes at boot)
runs/by-sid/<sid>.active/           mkdir MUTEX: one live run per sid (holds the bundle path); removed at any terminal state
requests/<sid>.json                 existing lane; claimed by mv → claimed/
requests-latch/<sid>.<death_uuid>   O_EXCL, per DEATH RECORD, taken AFTER the request file is in place
locks/<sid>.lock                    existing; gains custody semantics (§ 11.4 C10)
~/.claude/autonomy/capacity-admit/tokens/<run-ts>-<sid8>.token   one-shot admission token
```

Readers compute `state` as: the last line of the current `attempt`; a terminal line is sticky
against later NON-terminal lines from a stale writer, and `RECOVERED` (positive evidence) overrides
a prior `FAILED`/`STALE` (D2-FT R4's orphan-watcher case). No index file (`status` globs
`*/bundle-*/events.jsonl`, ms); no `|| true` on the write — a failed append goes to `hf_alarm` and
stderr (D3-FT R10). Two async writers (the watcher outside the pane, `lr-fire-resume` inside) are
legal; `stage` ordering is NOT an acceptance criterion (D1-FT R12).

### 11.4 Components — grafted from D1/D2/D3, each with the critique that shaped it

| # | component | grafted from | shaped by | file:function |
|---|---|---|---|---|
| C1 | `--detach` driver + verdict by `cc-notify` mailbox; `/limit-recover` fires and ENDS THE TURN | D2 §4.1, D3 I5, D1 C12 | wake is `mailbox-wake-arm` (SessionStart-registered in all 4 dirs, 15 s poll) — 0–15 s + one turn, not "to the second" (D2-latency R5, D3-latency R8) | `lr-fleet.sh` `lf_one` under `scripts/lib/detach.sh` (lifted verbatim from `handoff-fire.sh:1608-1616`); `commands/limit-recover.md` |
| C2 | the `no claude process` branch emits row + alarm + IDL-joined cause + REAL elapsed + tty paint | U04 §3, all designs | D1-FT R8: desk role dead ⇒ paint the pane tty too | `handoff-fire.sh:6878-6880` |
| C3 | pre-irreversible reads in `lr-handoff` via a new read-only handoff-fire verb | D1-FT R5, D2-safety R2 (a), D3-safety R3 — none of the designs had it | keeps `pane_cc_state`/`composer_content` in ONE implementation | `handoff-fire.sh --probe-recycle-preconditions --source-pane P --source-session S` (prints JSON: `{pane_state, composer, live_subagents, registry_ok}`); `lr-handoff.sh` new `lrh_precheck()` before `:517` |
| C4 | admission token: mint after C3 + probe, redeem in `lr-fire-resume` call-scoped, sid-enforced, `env -u` on spawn; TTL 300 s | U05 P2, D1 C6, D3 C4 | D1-safety R1 (no `export` of admission flags), R4 (mint after the gate — here the pre-check makes the 180 s gate the exception, TTL 300 > 180 + 15 + boot), D3-safety R13 (sid enforced), D3-safety R2 (N probes mint N — serialized in W6b) | `capacity-admit.sh` `cc_capacity_token_mint` / `_cc_admit_token_redeem` (after `:514`, in `cc_capacity_admit` after the `CC_ADMIT_GATE=off` branch); `lr-fire-resume.sh:324` `CC_ADMIT_TOKEN="$LR_ADMIT_TOKEN" CC_ADMIT_LOAD_TERM="${LR_LOAD_TERM:-off}" CC_ADMIT_BUDGET_KEY="$LR_RUN" cc_capacity_admit …`; spawn line `:463/:465` gains `-u LR_RUN -u LR_RUN_DIR -u LR_ADMIT_TOKEN -u LR_SUBMIT_TOKEN -u LR_LOAD_TERM` |
| C5 | per-RUN budget key; budget VALUE untouched (3) | U05 P3, D2 C5, D3 C4 | D2-safety R1 (the key does not exist yet — it is a named change to `_cc_admit_state_file:509-514`); D3-safety R2 (budget 1 makes every term a one-attempt delay — NOT adopted) | `capacity-admit.sh:509-514` keys `<caller>[.<CC_ADMIT_BUDGET_KEY>]` |
| C6 | the probe with phantom correction, load term OFF, as ONE function shared by lr-fleet and (W6b) the serialized section | `226b73888` + U05 P1 | T3 ratchet: probe and launcher enable the same term set | `lr-lib.sh` `lr_capacity_probe_corrected` (moves `lf_phantom_actives` + the `CC_SP_ACTIVE_OVERRIDE` wrapper out of `lr-fleet.sh:307-359`); `lr-fleet.sh` `lf_capacity_wait` calls it with `LR_FLEET_CAP_WAIT_S` 600 → **120**, ivl 20 |
| C7 | launcher: `LR_*` exports only, lives in the bundle, `lr-ingest-verify` runs INSIDE it (W3) | D1 C7, D2 C5, U12 §6.1 "inside the generated launcher" | D1-latency R3 (placement at `:464` is before the facts exist); `relaunch.rc` written by `lr-fire-resume` pre-expect, NOT by un-`exec`ing the launcher (D1-FT R2 (a)) | `lr-handoff.sh:586-593` heredoc; `lr-fire-resume.sh:324-329` writes `$LR_RUN_DIR/relaunch.rc` before `exit 9` |
| C8 | watcher boot wait: time-bounded, cheap `cc_alive` at 0.5 s, positive discriminators only, NO retype, INDETERMINATE on timeout | U04 §5 C/D, D1 C9, D2 C7, D3 C5.3 | D1-FT R2, D1-safety R5 (`rm -f relaunch.rc` before typing; mtime ≥ typed-at), R6 (no `shell-stable` heuristic), D1-latency R2 (`pane_cc_state` is 0.5–0.6 s under load — never in the tick loop), R8 (`$_` is not the loop var) | `handoff-fire.sh:6786-6816` |
| C9 | `submitted`/`queued` transcript probe; `engaged` after the submitted record; dead `esc to interrupt` oracle deleted; fixed sleeps 4 s → 0.7 s; quiet-pty ⇒ LOUD state, inject only after an affirmative screen read | U03 §4, D1 C8, D2 C6, D3 C6/C7 | D1-FT R4 (a queued prompt is an `enqueue` record until dequeue), R3 + D1-safety R13 (no `exit 11/12` from expect — the TUI would die; verdicts are state lines; expect proceeds to `interact`), D1-safety R10 / D3-FT R6 (no blind CR) | `lr-fire-resume.sh:549-583`; new `lr-submit-probe.sh`; `handoff-fire.sh:3680-3715` `resume_engaged` 4th arg |
| C10 | lock custody: a second hop is legal when the new `--from` equals the lock's `to`; the hook's skip keys on the tombstone beside THIS transcript, never the global lock | D1-safety R3, D3-FT R5 | closes "a re-limited target can never be recovered" | `lr-transplant.sh:59-69`; `hooks/stop-failure-marker.sh` ARM 2 |
| C11 | request lane: hook ARM 2 writes tmp+`mv` THEN latches; no `cc-lr` kick from the hook; `launchctl kickstart` (no `-k`) only if `autorecover.on` exists | U10 §2g, D1 C1, D3 C3 | D1-FT R6 (latch-before-write loses the uuid), D2-latency R7 / D2-safety R3+R12 (a hook's child may be reaped; inherits `CLAUDE_CODE_SESSION_ID` and skips the source rename at `lr-transplant.sh:97`), D1-safety R11 (kick default off, operator flag) | `hooks/stop-failure-marker.sh:130` (+~45 lines); `lr-lib.sh:129-159` `lr_last_api_error` +`resetsAt`/`rateLimitType` |
| C12 | poller: §0 CLAIM (per-sid `mkdir` mutex, `mv` to `claimed/`) + DETACH the worker (tick returns in seconds, lock released); hook-originated requests drained only under `autorecover.on`; §0b REAPER (read-only; acts only after the watcher is dead by (pid,lstart) and a live re-read); retire at `:902-905` only on RECOVERED or a live target registry row; failed runs re-driven ABOVE `:896`; `MAX_PER_WT` not applied to in-place recycles | D1 C3, D2 C10, D3 C8, U06 §5 A/E/F/H | D1-FT R1 / D1-latency R6 (reaper inside the lock it bounds), D3-safety R1/R4/R8 (watchdog keystrokes), D3-FT R3 (two actuators), D2-safety R5/D1-FT R7 (per-sid mutex), D3-FT R14 (`failed:*` behind the reset gate) | `lr-reset-poller.sh:639-661`, new `§0b`, `:896`, `:902-905`, `:289` |
| C13 | `bin/cc-lr` (thin): `find` → `cc-find`; `recover <ref>` → resolve → claim mutex → `lr-fleet --one --detach` → 3 lines; `status` → renders `events.jsonl`; `repair <run>` → writes a `mode:relaunch|prompt` request (never types itself) | D2 C1, D3 C2 | one engine (`lr-fleet`), one seam | new `bin/cc-lr` (~200 lines) |
| C14 | `scripts/lib/cc-tui.sh`: `cc_tui_type / cc_tui_submit_verified / cc_tui_clear` via `kitty @ send-text --from-file --bracketed-paste=enable`, `\x15` never ESC, never `send-key`, emptiness pre-gate, six-state rc; used ONLY by the daemon's `mode:prompt` repair under I3 | U08 §4, D2 C13, D3 C12 | D1-FT R3 (the pane-111 class needs a component); `it2 session tui-submit` as the single seam | new `scripts/lib/cc-tui.sh` (~150), `bin/it2-kitty` +1 verb |
| C15 | identity: `⌗<pane> <sid8>` left-anchored; telemetry row +`pane`; `bin/cc-find` (pane 2 ms · sid8 12 ms · tuple 0.18 s REFUSE on tie · keyword ≤ 2 s bounded); liveness by (pid,lstart); teammate rule 0 | U07 §6, D1 C10, D2 C2, D3 C1/C2 | D3-FT R12 / D2-safety R10 (bare `kill -0`), D2-safety R6 / D3-safety R5 (teammate on the explicit path), D3-latency R14 (`refreshInterval` DROPPED: +0.28 core) | `statusline.sh:77-86` / `:486`; new `bin/cc-find` |
| C16 | ranker `--recovery` floors (`RECOVERY_W_FLOOR 0.10 · S_CEIL 0.60 · F_FLOOR 0.05`), POLICY reasons, `CC_ROUTE_RECOVERY=off`; `lf_pick_target` keeps stderr, `--assign`, `--max-wait 3`; serialized pick→assign→probe→mint under `flock $STATE/admit.lock`; pool `LR_RECOVER_MAX_CONCURRENT` = 2 | U13 §4, all designs | D2-latency R6 / D3-FT R9 (rank→assign unserialized stacks), D1-latency R7 (`--max-wait`), D3-safety R2 (N simultaneous mints) | `bin/claude-accounts:3170-3205` `_excluded`, `:3459-3489` `score_fable`; `accounts.json .router`; `lr-fleet.sh` `lf_pick_target`, `lf_one` |
| C17 | census: single-pass Python `lf_locate` (0.148 s), `realpath` dedupe (`~/.claude-next/projects` → `~/.claude/projects`), `--one` registry-first, DUPLICATE overlap subtraction, `pane_after` read from the registry AFTER the run | U14 §4.2, U01 §7, D3 C9 | U09 gap #3 (vacuous proof) | `lr-fleet.sh:217`, `lf_locate`, `lf_one`; `lr-lib.sh:20-27` |
| C18 | `bin/cc-husk-sweep` consults `lr_transplanted_to` before resolving an account; a transplanted husk prints `TRANSPLANTED→<target>` and is never resumed | D3-safety R6, U09 Q2 | two auditors, one state model | `bin/cc-husk-sweep` (0 tombstone refs today) |
| C19 | ingest fast path in the launcher: `lr-ingest-verify.sh` clauses A–D under the TARGET cfg; `killed_inflight > 0` ⇒ fail-closed full ingest; `session-continue.sh clear` with `CLAUDE_CONFIG_DIR=$TCFG CLAUDE_CODE_SESSION_ID=$SID` and a `.sid`-mismatch refusal in `clear`; one-line non-slash prompt with `run:<sid8>:<TS>` token; HANDOFF-CONTEXT → last DoD entry; MANIFEST drops `source_argv` | U12 §6, U02 §4, D1 C7, D3 C11 | D2-FT R6 / D3-FT R7 (killed subagent certified "nothing owed"), D1-safety R9 / D2-safety R9 / D3-safety R10 (`clear` on a sibling's sentinel) | new `lr-ingest-verify.sh`; `lr-handoff.sh:404-458, :464-477, :586-593`; `hooks/session-continue.sh:156-172` |

### 11.5 Every timeout, with its justification (the survivors; today's value in brackets)

| stage | bound | why |
|---|---|---|
| StopFailure hook ARM 2 | ≤ 0.5 s of a 10 s budget | measured 0.19–0.25 s + `lr_tier_from_transcript` 0.116 s on 5.7 MB, 0.863 s on the 241 MB box maximum (D1-latency M1) |
| kickstart / QueueDirectories wake | ~1 s; `ThrottleInterval 5` | launchd; under a running tick the drain's re-scan covers it; c10 |
| rank (+ `--max-wait 3`) | 3 s warm; first uncached ≤ 5 s (`KWORK_BUDGET_S`, `bin/claude-accounts:624`) | over budget ⇒ `PARKED:no-target` with the router's reasons, never a blind pick |
| corrected probe (`lf_capacity_wait`) | **120 s** total, 20 s ivl [600/20] | load OFF + phantom subtraction ⇒ remaining refusable terms are headroom (0/127 ever), segments, reserve; 120 s covers a transient spike without holding a worker 10 min; past it `PARKED:capacity:<term>` — nothing moved, re-probed each tick |
| token TTL | **300 s** | pre-check makes the composer gate (180 s, `handoff-fire.sh:11634`) the exception; shell wait measured 3–15 s in 8/8 logs (U04 W2); expiry ⇒ named `FAILED:gate:token-expired` ⇒ re-drive with a fresh probe |
| composer gate (belt) | 180 s / 15 s [unchanged] | an operator draft is theirs; now surfaced as `HELD:draft` pre-transplant (C3) so this gate rarely waits |
| `/exit` → shell | `HF_RECYCLE_SHELL_WAIT_S` 600 [unchanged], poll quantum 3 s → **1 s** with `waited` kept in wall seconds (D2-latency R8) | the bgwork dialog's 60/150/300 s nudges live here; `sleep 2` at `:6786` → poll `at_shell` 0.3 s cap 5 s |
| relaunch typed → tui-up / rc / IDL row | **60 s** at 0.5 s on `ps -o comm= -t $TTY`; then INDETERMINATE to 180 s at 5 s with `pane_cc_state`; no retype | refusal lands as `relaunch.rc` in ~2 s (U04 §0); boot ~4 s is a **GUESS** (U14 B) — the drill measures it; 60 s is 15× |
| READY | 300 s expect global; quiet-pty 8 s ⇒ `READY-NOT-SEEN` state (loud); inject only after an affirmative empty-composer read | `auto mode on` is the one surviving READY phrase on 2.1.260 (U03 (a)); a blind CR on a menu is destructive (U03 (c)) |
| inject sleeps | 0.3 + 0.2 + 0.2 s [2+1+1] | READY already proved the composer (U14 item 7) |
| submit probe | 1 s ≤ 30 s; `queued` extends to the engage window; ONE screen-verified re-CR then 10 s | the user record is written at submit; an `enqueue` record at type time behind a running turn (D1-FT R4) |
| engage | 180 s [unchanged], 1 s ivl [5] | one model turn on a ~365 K context, 14.5 s measured once (U12 §3); `resume_engaged` is a whole-file read ≈ 0.09 s on 11 MB (D3-latency R10) — 1 Hz is affordable |
| `recycle_await_verdict` (interactive `--one` only) | `CC_RECYCLE_DRAFT_WAIT + HF_RECYCLE_SHELL_WAIT_S + 60 + 180 + 60` = **1080 s**, ivl 0.5 s [900/5] | the outer bound must exceed the sum of the inner ones (D2-FT R4, D2-latency R1) |
| reaper stage bound | stage bound + 60 s, evaluated per tick (600 s) | a dead watcher is caught ≤ 600 + bound + 60; `STALE` is a page, never a keystroke |
| re-drive budget | 3 per sid (`fire_fail_note`, `lr-reset-poller.sh:251-282`) | the 3rd pages `needs-human` with the bundle path and the manual command; note the latch expires in 6 h (D1-safety R14) — fine for a pane that may come back |
| `cc-find` kitty RPC | 2 s, ×2, INDETERMINATE | one 10.06 s timeout with a truncated payload observed (U07 §5) |
| notify → invoker wake | ≤ 15 s + one turn | `mailbox-wake-arm.sh:199` `--interval 15` |

Honest latency re-sum, idle box (D3-latency §3 + C9's 4 s removed): driver 0.3 + rank 1.5 + probe/
audit/transplant 3.5 + freshness+`/exit` 2.7 + teardown 3 (GUESS) + shell quantum ≤ 1 + type 1.3 +
boot 4 (GUESS) + token/READY 0.5 + inject 0.7 + submit ≤ 1 + first turn 14.5 + engage 0.5 ≈
**35 s p50**, `< 90 s` with ~2.5× margin; +≤ 15 s until the invoker hears it. Loaded box: +≤ 120 s
probe park ⇒ `< 5 min` to ENGAGED or to a NAMED `PARKED:capacity:<term>` with nothing moved.

---

## 12. Waves — ordered by leverage (minutes saved per recovery ÷ lines), with dependencies

Leverage uses the § 9.1 per-recovery sinks (13.7 lead-min + 17.4 operator-min per recovery).

### W1 — non-blocking invocation + a verdict that reaches someone (leverage 0.059; ~90 lines)

**Goal.** `/limit-recover <ref>` costs the invoking session ONE Bash call that returns in ≤ 3 s; the
verdict arrives as a `cc-notify` mailbox line; the one silent terminal arm writes a row, an alarm,
the IDL-joined cause and a pane paint.

**Files/functions.**
- `scripts/lib/detach.sh` (new, 12 lines): `detach <log> <cmd…>` lifted verbatim from
  `handoff-fire.sh:1608-1616` (`start_new_session=True`).
- `scripts/limit-recover/lr-fleet.sh` `lf_one`: `--detach` runs the existing body under `detach`
  and prints `run=<bundle-or-pending> log=<path>`; on exit the detached body appends the
  `results.tsv` row (exists) and runs `cc-notify <requester-pane> "<row>"` recording the
  `verdict=` token; `--source-pane` given ⇒ `lr-handoff` is called WITHOUT `--await` (`:621`) only
  under `--detach` (the interactive form keeps `--await`).
- `lr-fleet.sh` rc-4 arm (`lf_one` `4)`): join the last `caller=="lr-fire-resume"` IDL row after
  `T0` into the note (`launcher refuse term=<t> — <detail>`); the `parked` row carries
  `cc_capacity_admit_reason` (U05 P4).
- `scripts/handoff-fire.sh:6878-6880`: before `exit 1` — `emit_recycle_event recycle-dead 0 "$RSID"
  "<IDL cause or no-process>"`, `goal_unreachable recycle-dead`, `hf_alarm recycle-relaunch-refused
  …` (the 3 lines its siblings at `:6796-6798` / `:6873-6875` already have), print the REAL elapsed
  and whether the retype ran, and one `printf` of the verdict to `$TTY_PATH` (single write, no
  escapes) instead of the `it2 session run "# …"` line (whose armed-pane branch writes a `.cmd` file,
  `:1419-1431`).
- `commands/limit-recover.md`: a front section — resolve → `lr-fleet --one <sid> --source-pane P
  --detach` → END THE TURN; foreground `until` loops, `cc-pane send`, `it2 session send/run` for
  messages and `kitty @ send-key` are banned by name (U08 §3).

**Acceptance (numbers).** `time bash scripts/limit-recover/lr-fleet.sh --one <sid> --source-pane P
--detach` ≤ 3 s wall, prints a log path, the caller's shell is free; the detached run's
`results.tsv` row appears and a `cc-notify` row for the requester pane carries `verdict=`;
`tests/handoff-recycle-remote-resume.bats` +2: the no-process arm writes a `recycle-dead` row whose
detail contains the IDL `term=` and an alarm file in `$CC_HANDOFF_ALARM_DIR` (red on the unpatched
tree — today it writes neither); `tests/lr-fleet.bats` +2: rc-4 note carries `term=load` from a
fixture IDL; `--detach` returns before a stub `lr-handoff` that sleeps 10 s finishes. `grep -c
'until \[' commands/limit-recover.md` ⇒ 0.

**Minutes saved per recovery.** 4.9 lead (24.4/5) + 0.4 (zero-byte run named) ≈ **5.3**; 17.4
operator-visible.

**Depends on.** —

### W2 — one admission decision, and nothing irreversible before every refusable read (leverage 0.018; ~240 lines)

**Goal.** A relaunch is never refused by a gate the driver did not evaluate; a held draft, an
unknown pane state, a non-limited or teammate session, and a hot box all refuse BEFORE the
transplant with nothing moved; a refusal after the transplant is named in ≤ 3 s and is re-drivable.

**Files/functions.**
- `scripts/lib/capacity-admit.sh`: after `:514` `cc_capacity_token_mint <path> <sid>` +
  `_cc_admit_token_redeem` (one-shot `rm -f` on read whatever the verdict; TTL
  `CC_ADMIT_TOKEN_TTL_S` 300; `-O` uid; **`[ "$tok_sid" = "$CC_ADMIT_WANT_SID" ]` enforced**;
  probes never redeem); `basis:"token"` as the eighth basis, recorded with age; `_cc_admit_state_file`
  `:509-514` keys `<caller>[.<CC_ADMIT_BUDGET_KEY>]`. `CC_ADMIT_LOAD_TERM` default stays `on` in
  the library (no global change); the recovery callers pass `off` call-scoped.
- `scripts/limit-recover/lr-lib.sh`: `lr_state_append <bundle> <state> <stage> <detail>` (one
  `printf '%s\n' "$(jq -cn …)" >>`, ≤ 1 KB, `writer=$0:$$`, `attempt`); `lr_capacity_probe_corrected
  <caller> <what>` (moves `lf_phantom_actives` + the override wrapper here, `CC_ADMIT_LOAD_TERM=off`
  call-scoped); `lr_state_current <bundle>`.
- `scripts/handoff-fire.sh`: new read-only verb `--probe-recycle-preconditions --source-pane P
  --source-session S` ⇒ JSON `{registry_ok, pane_state (cc|shell|unknown), composer (empty|held:<80
  chars>|unreadable), live_subagents:N}` from `hf_remote_source_bind`, `pane_cc_state` (`:3532-3576`),
  `composer_content` (`:2392`), `live_subagents_of` (`:4870-4903`); exit 0 always (verdict in JSON).
- `scripts/limit-recover/lr-handoff.sh`: new `lrh_precheck()` before `:517`, gated
  `LRH_PRECHECK=on`: registry bind (`:266-284`, exists) → `lr_last_api_error "$SRC_TX"` kind=limit
  (else `REFUSED:not-limited`, exit 6) → `head -c 8000 | grep -q '"agentName"'` (else
  `REFUSED:teammate`) → the verb above: `pane_state != cc` ⇒ `REFUSED:pane:<state>`; `composer` held
  ⇒ `HELD:draft` (exit 6, nothing moved, notify); `live_subagents` recorded as `killed_inflight`
  → `lr_capacity_probe_corrected lr-handoff` (bounded `LR_FLEET_CAP_WAIT_S` when called from the
  fleet; 0 wait interactively ⇒ `PARKED:capacity:<term>`) → `cc_capacity_token_mint
  "$CC_ADMIT_STATE_DIR/tokens/<TS>-<sid8>.token" "$SID"` → then `:517` transplant. Launcher heredoc
  `:586-593`: `export LR_RUN=<bundle> LR_RUN_DIR=<bundle> LR_ADMIT_TOKEN=<path> LR_SUBMIT_TOKEN=run:<sid8>:<TS>
  LR_LOAD_TERM=off` (all `%q`), the launcher file lives in `$BUNDLE/` (not `$TMPDIR`); live-parser
  preflight (`:497`) also greps the live `lr-fire-resume.sh` for `LR_ADMIT_TOKEN` and the live
  `capacity-admit.sh` for `_cc_admit_token_redeem` (refuse exit 5 before anything moves).
- `scripts/limit-recover/lr-fire-resume.sh:324-329`: `rm -f "$LR_RUN_DIR/relaunch.rc"` is NOT here
  (the watcher does it before typing); gate call becomes `CC_ADMIT_TOKEN="${LR_ADMIT_TOKEN:-}"
  CC_ADMIT_WANT_SID="$SID" CC_ADMIT_LOAD_TERM="${LR_LOAD_TERM:-on}" CC_ADMIT_BUDGET_KEY="${LR_RUN##*/}"
  cc_capacity_admit lr-fire-resume …`; on refusal `lr_state_append "$LR_RUN" FAILED gate
  "$(cc_capacity_admit_reason)"` + `printf 9 > "$LR_RUN_DIR/relaunch.rc"` before `exit 9`; on admit
  `lr_state_append … gate-admitted`; every other pre-expect exit path writes its rc to
  `relaunch.rc`; spawn lines `:463/:465` add `-u LR_RUN -u LR_RUN_DIR -u LR_ADMIT_TOKEN
  -u LR_SUBMIT_TOKEN -u LR_LOAD_TERM`.
- `scripts/handoff-fire.sh:6786-6816` (resume mode): `sleep 2` → poll `at_shell` 0.3 s cap 5 s;
  `rm -f "$LR_RUN_DIR/relaunch.rc"` + `typed_at=$(date +%s)` before `it2_type_verified`; replace
  `:6811-6816` with a `date`-bounded loop (60 s, 0.5 s): `ps -o comm= -t "$TTY_PATH" | grep -q
  -m1 -E '^(claude|node)'` ⇒ `tui-up`; `relaunch.rc` newer than `typed_at` ⇒ `FAILED:relaunch:rc=<n>`
  with the IDL join; an IDL `lr-fire-resume` row with `ts > typed_at` and `verdict=refuse` ⇒ same;
  no retype ever; at 60 s `INDETERMINATE:boot` then `pane_cc_state` every 5 s to 180 s; at 180 s
  `STALE:boot` + alarm + paint (via C2's arm). `:6619` `sleep 3` → 1 s with `waited=$((waited+1))`.
  `recycle_await_verdict` `:11788` max → `${CC_RECYCLE_DRAFT_WAIT:-180} + ${HF_RECYCLE_SHELL_WAIT_S:-600} + 60 + ${RCY_ENGAGE_TIMEOUT:-180} + 60`, ivl 0.5 s; grep gains
  `FAILED:relaunch|STALE:boot`.
- `lr-fleet.sh` `lf_capacity_wait`: delegate to `lr_capacity_probe_corrected`; default 600 → 120.

**Acceptance (numbers).** `tests/capacity-admit.bats` + T1/15b/15c (token one-shot / expired /
probe-inert) + a sid-mismatch case, each red on the unpatched lib (status 9, no token support);
`tests/capacity-admit-coverage.bats` + T3 ratchet (lr-fleet's probe and lr-fire-resume's admit
enable identical term switches — red on the LOAD row today); `tests/lr-handoff-launcher-quoting.bats`
+4: precheck refuses `pane_state=unknown` / `composer=held` / non-limit tail / `agentName` head
with NO transplant (assert no lock, no tombstone — red today: all four transplant); launcher
heredoc carries the five `LR_*` exports `%q`-rendered and none of `CC_ADMIT_*`; a fixture where the
live `capacity-admit.sh` lacks `_cc_admit_token_redeem` ⇒ exit 5 pre-transplant.
`tests/handoff-recycle-remote-resume.bats` +4: `relaunch.rc=9` ⇒ `FAILED:relaunch` within 3 s with
the IDL term in the alarm; a stale `relaunch.rc` older than `typed_at` is ignored; 60 s with no
evidence ⇒ `INDETERMINATE:boot`, never a retype (`grep -c it2_type_verified` in the log = 1);
`tests/lr-relaunch-bound.bats` (new): asserts the await max ≥ the sum of its inner bounds
(computed from the same constants). Mini-drill (operator-launched, 2 throwaway sessions on one
account, box under a background `bats`): both ENGAGED ≤ 90 s; one with `CC_ADMIT_HEADROOM_OVERRIDE=0`
baked into its launcher ⇒ `FAILED:gate:headroom` row ≤ 3 s after `relaunch-typed`, alarm present,
nothing typed twice.

**Minutes saved per recovery.** (11.1 park + ~10 PARTIAL-window/repair) / 5 ≈ **4.2**, plus the
88 s dead-wait per failure and the pane-147 class.

**Depends on.** W1 (shared `handoff-fire.sh`; rebase).

### W3 — RECOVERED means "submitted, then engaged" (leverage 0.026; ~200 lines)

**Goal.** The engagement oracle cannot be satisfied by a stale notification turn; a prompt sitting
unsubmitted is named within 40 s (or held as `queued` behind a running turn); the fast-path ingest
costs 1 model round trip, ≤ 0.2 K resident tokens, and refuses when a subagent was killed.

**Files/functions.**
- `scripts/limit-recover/lr-submit-probe.sh` (new, ~30): `<cfg> <sid> <t0> <token>` ⇒ prints
  `submitted <ts>` (a `type:"user"` record after `t0` containing the token), `queued <ts>` (a
  `queue-operation` `enqueue` record whose `content` contains it), or `none`; a `tail -c 400000`
  scan (19 ms on 12 MB, U08 §6).
- `scripts/limit-recover/lr-fire-resume.sh:549-583`: capture `LR_T0` before `spawn`; inject arm
  sleeps 0.3/0.2/0.2; delete `shift+tab to cycle` from `LR_RE_READY` (0 hits in 2.1.260); replace
  `timeout {}` at `:560` with an 8 s quiet arm that runs `it2 session read` via `exec`, injects ONLY
  if the read shows an empty composer box and no `❯` selector line, else `lr_state_append … READY-NOT-SEEN`
  + `send_user "✗ READY NEVER SEEN — prompt NOT typed: …"` and falls through to `interact`;
  replace `:563-583` with a Tcl poll of the probe (1 s ≤ 30 s; `queued` ⇒ keep polling to
  `RCY_ENGAGE_TIMEOUT`; `none` at 30 s ⇒ ONE re-CR only after a screen read shows the prompt text
  in the composer, 10 s more) ⇒ `lr_state_append submitted|queued|FAILED:submit`; **never `exit`
  from the expect program** — always `interact`.
- `scripts/handoff-fire.sh:3680-3715` `resume_engaged <cfg> <sid> <t0> [<token>]`: with a token,
  the qualifying assistant record must be newer than the LAST user record containing the token;
  `:6845-6860`: in resume mode call the probe first, emit `recycle-submitted`, then engage with
  that ts; `RCY_ENGAGE_INTERVAL` 5 → 1.
- `scripts/limit-recover/lr-ingest-verify.sh` (new, ~60): U12 §6.1 A–D as `jq -e`/shell
  predicates run INSIDE the launcher with `CLAUDE_CONFIG_DIR="$TCFG"`; clause A adds
  `killed_inflight == 0` read from `events.jsonl`; clause D runs `CLAUDE_CONFIG_DIR="$TCFG"
  CLAUDE_CODE_SESSION_ID="$SID" ~/.claude/hooks/session-continue.sh clear`; receipt to
  `$BUNDLE/INGEST-VERIFIED.txt`; rc 0/1.
- `scripts/limit-recover/lr-handoff.sh`: `:464` becomes a placeholder; the launcher heredoc
  composes `PROMPT` at run time (`if lr-ingest-verify …; then PROMPT="$(tail -1 receipt)"; else
  PROMPT="/limit-recover ingest $BUNDLE — lr-ingest-verify FAILED: <clause>"; fi`), the fast-path
  line is U12 §6.2's template with `run:<sid8>:<TS>` appended; `:404-410,:443-444` emit only the
  LAST DoD entry + a pointer; `:366,:472,:477` drop `source_argv` (keep `runtime_model/effort`).
- `hooks/session-continue.sh:156-172` `clear`: refuse (rc 0, one log line) when `${f}.sid` exists
  and names a different sid than `CLAUDE_CODE_SESSION_ID`.
- `scripts/limit-recover/lr-preseed-env.sh:115-117`: add `fullscreenUpsellSeenCount` /
  `fullscreenDownsellSeenCount` to `UPSELL_FLOOR` (sit at 3 in `.claude-secondary`/`-tertiary`).

**Acceptance (numbers).** `tests/lr-fire-resume-submit.bats` (new): probe returns `submitted` on a
fixture with the token in a user record, `queued` on an `enqueue` record, `none` on a
`<task-notification>` user record without it (red: today's oracle is a screen phrase);
`tests/handoff-recycle-engagement.bats` +2: a fixture with a notification assistant turn BEFORE the
token record does NOT engage, one AFTER does (red today); `tests/lr-ingest-verify.bats` (new): rc 0
on today's five bundles (all `gaps 0`), rc 1 when `events.jsonl` carries `killed_inflight:1`
(pane 114's shape), rc 1 on `pool/*`; `tests/lr-handoff-launcher-quoting.bats` +2: the launcher's
composed prompt is the one-line form and contains `run:`; the fail-closed prompt names the clause;
`grep -c 'esc to interrupt' lr-fire-resume.sh` ⇒ 0; `grep -c 'exit' ` inside the expect program's
post-inject block ⇒ 0. Measured on the next real recovery: `HANDOFF-CONTEXT.md` ≤ 2 KB, MANIFEST ≤
1 KB, first turn 1 message / 0 tool calls (U12 §6.3's row).

**Minutes saved per recovery.** 17.1/5 (pane-111 class) + 30 s dead oracle + 4 min/3 ingests ≈
**5.2**, plus ~26 K resident tokens per session.

**Depends on.** W2 (`lr_state_append`, `LR_*` exports, `relaunch.rc`).

### W4 — identity in the pixels and a resolver that refuses (leverage 0.009; ~180 lines)

**Goal.** A screenshot (or a pane id / sid8 / keyword) resolves to exactly one live session in
< 2 s, or refuses with the candidates; no full-store census on the hot path.

**Files/functions.**
- `statusline.sh`: after `:86`, `_pane="${KITTY_WINDOW_ID:-}"; [ -n "$_pane" ] || _pane="${ITERM_SESSION_ID##*:}"`;
  `ID_SEG="⌗${_pane:-?} ${PAY_SID:0:8} "`; emit at `:486` between `GLYPH_PREFIX` and `PCT_SEG`
  (left-anchored: survives the 30-column panes where 9/16 today amputate sha and effort, U07 §2b);
  the telemetry `jq` at `:149-156` gains `pane`. `⌗` (U+2317) is outside the East-Asian-Ambiguous
  set the file documents (`:365-397`); **operator eyes-check in a real 30-col pane before landing;
  `#` is the fallback**. `~/.claude/statusline.sh` is a copy-deployed real file (identical today) —
  the land must be followed by `install.sh`/`deploy-live`.
- `bin/cc-find` (new, ~100, from `scratchpad/lr/cc-find-full.sh`): input shapes pane / `⌗pane` /
  sid8 / `--tuple acct=N,cwd=B,effort=E,pct=P` / `--kw`; rule 0 teammate (`agentName` in the head 8
  KB ⇒ printed `TEAMMATE`, never chosen); liveness `(pid,lstart)` from the registry row (`hooks/
  session-register.sh:278`), never bare `kill -0` and never telemetry age; tuple filters on
  (account, cwd basename, effort), never sha, ranks by `|pct − live|`, **refuses** when the top two
  are within 12 points; `kitty @ ls --match id:N` bounded 2 s ×2, timeout ⇒ `liveness:unverified`;
  output one TSV row `pane sid account cwd pid alive tier state title`, rc 2 on ambiguity with all
  candidates printed; `--limited` lists sids from `stop-failure/rate_limit__*.jsonl` (6 h) ∪
  `parked/` ∪ `requests/` joined to live rows and confirmed by `lr_last_api_error` on the tail.
- `scripts/limit-recover/lr-fleet.sh:217`: subtract registry pids from the resume-proc set as the
  `--duplicates` arm already does; `--one`: registry/store resolver FIRST, `lf_locate` only on a
  miss; `lf_one`'s `pane_after` read from the registry row after the run (`account` changed, `pid`
  alive, `session_id` unchanged) — a proof that CAN fail.
- `scripts/limit-recover/lr-lib.sh:20-27`: dedupe config dirs by `pwd -P` of `projects/`.

**Acceptance (numbers).** `time bin/cc-find 117` ≤ 0.3 s, one row; `time bin/cc-find cb227486` ≤
0.3 s; a fixture registry with the 122/124 byte-identical statuslines ⇒ `cc-find --tuple …` exits 2
and prints both; a row whose pid is reused (fixture: pid of `$$` with a different `lstart`) is
`STALE`; a teammate fixture is `TEAMMATE` and `cc-find` refuses it for `recover`;
`tests/statusline-identity.bats` layer 2 +2 assertions (pane and sid8 present; each red when its
source var is unset — mutation-checked, the suite's own history says 7 mutants left it green);
`tests/lr-fleet.bats` +3: DUPLICATE with one registry pid that IS the resume pid ⇒ RECOVERABLE (red
today); `--one` with a registry hit runs no census (stub `lf_locate` that `exit 99`s is not
reached); `pane_after` differs from `pane` when the registry row is absent after the run.
`bash statusline.sh < scratchpad/lr/payload.json` renders `(2) ⌗<pane> <sid8> 52% · …` in ≤ 95 ms
(baseline 89 ms, U07 §3c).

**Minutes saved per recovery.** 4.2/5 (censuses) + 4/5 (the two stale-screenshot turns T3/T4) ≈
**1.6**; and the < 2 s identification target.

**Depends on.** — (parallel with W1/W2; touches `lr-fleet.sh:217` and `--one` only).

### W5 — the request lane, the state store's readers, one actuator per pane (leverage ≥ 0.007 manual, up to 0.10 with auto-recover on; ~300 lines)

**Goal.** A limit writes its own request within a second; the daemon claims and drives it OFF its
lock (policy-gated for hook-originated requests); every non-terminal run past its bound is named
and re-driven without a second actuator; a failed run is never retired as recovered; a re-limited
target can be moved again; the husk auditors agree.

**Files/functions.**
- `hooks/stop-failure-marker.sh` after `:130` (ARM 2, ~45 lines): gate `$ERR ∈ {rate_limit,
  rate_limit_error}`; source `lr-lib.sh`; `lr_last_api_error "$TP"` ⇒ death uuid, kind=limit,
  `resetsAt`, `rateLimitType` (extend `lr-lib.sh:129-159` by two fields); teammate test
  (`agent_assignee_argv` ∨ `agentName`) ⇒ `teammate-skip/<sid>`; skip if `$(dirname "$TP")/$SID.HANDOFF.json`
  exists (beside THIS transcript — never the global lock); write `requests/.<sid>.tmp` then `mv` into
  place, THEN `( set -C; : > requests-latch/$SID.$DUUID )` (write-then-latch; a latch that
  already exists after a successful `mv` means a concurrent writer won — abstain); request schema =
  today's four keys + `account cwd tier transcript_path reset_at_epoch rate_limit_type death_uuid
  origin_class source_pane`; `[ -e "$STATE/autorecover.on" ] && launchctl kickstart
  "gui/$(id -u)/com.reso.lr-reset-poller"` (no `-k`; `hooks/validate-bash.sh` has no launchctl rule
  and this is neither `load` nor `unload`); `CC_SF_REQUEST=off` kill switch; every path `exit 0`,
  stdout empty. **No `cc-lr` kick from the hook.**
- `scripts/limit-recover/lr-reset-poller.sh:639-661` (§0): per request — hook-originated
  (`requested_by == stop-failure-marker`) requires `autorecover.on` else `continue` (the file is a
  breadcrumb for `cc-find --limited`); `mkdir "$STATE/runs/by-sid/$sid.active"` (else log
  `SUPERSEDED-BY-LIVE-RUN`, `rm` the request); `mv` to `claimed/`; `detach "$RESULTS/$sid.log"
  "$FLEET" --one "$sid" --target … --source-pane … --from-daemon --detach-inner`; the tick continues
  in seconds. New `§0b REAPER` (~60 lines, `CC_LR_REAPER=on|alarms-only|off`): for each
  `runs/by-sid/*.active` → bundle → `events.jsonl`; non-terminal past bound+60 s ⇒ read the
  watcher's (pid,lstart) from the run; alive ⇒ nothing; dead ⇒ re-read registry row
  (`session_id == sid ∧ account == target ∧ (pid,lstart) live` ⇒ append `RECOVERED`, release mutex),
  else `pane_cc_state`/`get-text` (bounded) + target transcript ⇒ `STALE:<stage>` + `hf_alarm
  lr-stale-<stage>` + tty paint + `cc-notify` (desk if hook-originated, else the requester) + a
  `mode:relaunch` request iff the pane reads an affirmative `shell` (or `mode:prompt` iff `cc` with
  an empty composer, no `expect` on its tty, and no submitted record — the C14 repair) —
  `fire_fail_note` bounds re-drives at 3. Run ABOVE `:896`. `:902-905`: retire only when
  `lr_state_current == RECOVERED` or a live registry row under the TARGET cfg names the sid;
  otherwise log `HUSK <sid> (run <bundle> state <S>)` and leave the record. `:289` `MAX_PER_WT`
  applies to spawns only. `lr-fleet.sh:463-464` stops printing `kickstart -k`.
- `scripts/limit-recover/lr-transplant.sh:59-69`: the lock gains `owner` (= `to`); an existing
  lock is accepted when `"$FROM"` realpaths to the lock's `to` (a second hop: rewrite from/to/owner,
  keep `ts_first`), refused otherwise; the `mv "$SRC" …handed-off` guard `:97` stays.
- `bin/cc-husk-sweep`: before resolving an account, `lr_transplanted_to "$sid" "$cfg"` ⇒ print
  `TRANSPLANTED→<target>` and never resume from the sweep.
- `bin/cc-lr` (new, ~200): `find` (→ `cc-find`), `recover <ref> [--target A]` (resolve → refuse
  teammate/ambiguous/non-limited → `mkdir` mutex → `lr-fleet --one … --detach` → print the 3 lines
  of D2 §1.2 with the bundle path as the id), `status [ref|--all]` (one row per `events.jsonl`,
  ≤ 0.1 s, `CAUSE / NEXT` columns), `repair <bundle>` (writes a `mode:relaunch|prompt` request with
  `requested_by=<this pane>` and kicks; never types). `/limit-recover <ref>` ⇒ `cc-lr recover
  <ref>` + END THE TURN.
- `scripts/lib/cc-tui.sh` (new, ~150) + `bin/it2-kitty` `session tui-submit -s <id> --from-file <f>`:
  U08 §4 verbatim (composer emptiness pre-gate, `--from-file --bracketed-paste=enable`, `\x15`
  scrub with read-back, transcript oracle from a byte offset, rc 0/1/2/3/4/5). Used only by the
  daemon's `mode:prompt` worker under I3.
- `scripts/limit-recover/com.reso.lr-reset-poller.plist` (SSOT): `QueueDirectories` =
  `~/.reso/limit-recover/requests`, `ThrottleInterval 5`, `StartInterval 600` kept — **operator
  c10** (`cc-backlog needs … --run "cp … && launchctl bootout … ; launchctl bootstrap …"`);
  `launchd-parity-lint.sh` asserts live == SSOT. `QueueDirectories`, not `WatchPaths`: it keeps
  the job alive while the dir is non-empty and re-launches on exit with a non-empty dir, closing
  both the missed-event and the re-scan-tail holes (D1-latency R1, `man launchd.plist`).

**Acceptance (numbers).** `tests/stop-failure-marker.bats` + SF-a…SF-h (U10 §2g) + SF-i (write
happens before the latch: a stub that kills the hook after the latch is impossible to reproduce, so
assert file order: request present ⇒ latch present, latch present ⇒ request present) + SF-j (a
request written from the hook yields `source_retired:1` when replayed through `lr-transplant.sh`
under `env -u CLAUDE_CODE_SESSION_ID` — red today: `lr-transplant.sh:97` skips the rename);
`tests/lr-reset-poller-requests.bats` (new): claim atomicity under two ticks (one `SUPERSEDED`),
hook-originated request NOT drained without `autorecover.on`, drained with it, tick returns ≤ 5 s
with a stub worker sleeping 60 s, reaper marks `STALE:boot` for a dead watcher (fixture pid+lstart)
and writes NOTHING when the watcher is alive, reaper appends `RECOVERED` when the registry fixture
shows the sid under the target, `:902-905` does NOT retire a bundle at `FAILED:*` (red today);
`tests/lr-resume-tombstone-guard.bats` +2: a second hop from the lock's `to` succeeds and rewrites
the lock; from any other cfg is refused; `tests/cc-lr.bats` (new): `recover` refuses a teammate /
ambiguous / non-limited ref with rc 2 and creates no mutex; `status` renders ≤ 0.1 s over 20
fixture bundles; `tests/cc-tui.bats` (new): rc 3 on a held composer fixture, rc 5 on no record.
Drill (§ 12 W7) rows 5–10.

**Minutes saved per recovery.** Manual mode: the re-drive of a named failure by one command vs
today's hand relaunch ≈ **2** (bounded by W2 making failures rare); auto-recover on: up to **31**
(2 h 37 m / 5 of post-detection idle, U10 §1g) — see § 15 decision 1.

**Depends on.** W1–W3.

### W6a — the ranker's recovery lane (leverage ~0.01 expected; ~110 lines) — parallel leaf

**Files/functions.** `bin/claude-accounts`: `recovery_floors(R)`, `_excluded(…, recovery=False)`
adding `recovery-5h-thin` (projected 5 h ≥ `RECOVERY_S_CEIL 0.60`), `no-weekly-data` (fail closed),
`recovery-weekly-thin` (`w_rem < RECOVERY_W_FLOOR 0.10`); `score_fable(…, recovery=)` with floor
`max(FABLE_FLOOR, RECOVERY_F_FLOOR 0.05)` (also closes the float-ULP admit at weekly 98);
`--recovery` argv modifier (never a fourth lane); reasons classed POLICY (all-thin ⇒ exit 2);
`route-meta` gains `recovery=1|0`; kill `CC_ROUTE_RECOVERY=off`. `accounts.json .router`: the three
keys + `_recovery` rationale (U13 §4a verbatim). **Acceptance:** `tests/account-recovery-lane.bats`
(U13 §5's eight cases incl. THE INCIDENT — weekly 98 / reset 11 h is rank[0] for dispatch and
`recovery-weekly-thin` for recovery — and the three mutation arms each turning exactly one case
red); `--rank fable` without `--recovery` byte-identical. **Saves:** a re-limit cycle (~20 min) at
the measured probability that the dispatch pick would have hit 100 % inside the recovered
session's first hours (`next`: 1 h 54 m) — call it 0.5 × 20 / 5 ≈ **2** per recovery, honestly a
risk figure. **Depends on:** —.

### W6b — fleet pool with a serialized admit section (leverage 0.01; ~60 lines)

**Files/functions.** `lr-fleet.sh` `lf_pick_target`: `--rank <lane> --recovery --max-wait 3
2>"$rdir/rank.<lane>.stderr"`, validate the token against `lib/account-map.generated.sh`, `--assign
"$t" --src lr-fleet` unless `--dry-run`, park note carries `LF_RANK_WHY`; `lf_one`: the section
rank → assign → `lr_capacity_probe_corrected` → mint runs under `flock "$STATE/admit.lock"` (~1–2 s
warm; a cold `cc_sp_active` is 7.2 s, U05 §4.3 — the lock serializes it, it does not hide it);
`--recover`/`--all`: a POOL of `LR_RECOVER_MAX_CONCURRENT` (default 2) detached `lf_one`s, next
claimed the moment one exits (not a group `wait`); `handoff-fire.sh:9296` `--assign` guard: skip
only when the recycle stays on the same account (or leave it and let lr-fleet charge — one, not
both). **Acceptance:** `tests/lr-fleet.bats` +4 (`--recovery` asked; `--assign` charged once per
pick and not under `--dry-run`; empty rank parks with the router's own reasons, not "returned
nothing past"; two `lf_one`s with a 3 s stub rank serialize — the stub's log shows no overlap);
drill row 4 (targets spread across ≥ 2 accounts inside one 90 s TTL). **Saves:** 5 × 150 s →
≈ 60 s fleet ⇒ 7.5/5 = **1.5** per recovery. **Depends on:** W5 (mutex, detach), W6a.

### W7 — census speed, the 5-session drill, docs (~180 lines)

**Files/functions.** `lr-fleet.sh` `lf_locate`: the per-file `tail | grep | grep` + 4 python
spawns per hit (`:187-214` in the pre-`226b73888` numbering) → one Python pass over the deduped
file set (0.148 s vs 40–86 s, U14 A3/A4); `lr_tier_from_transcript` reads a tail, not the whole
file. `tests/lr-drill.sh` (new, operator-launched — it spends quota and types into panes): five
throwaway sessions on ONE account (3 in the shared checkout, 2 in worktrees, one with an in-flight
subagent), box under `nice -n 19 taskpolicy -c background bats` load, `--drill <manifest>` (an
explicit sid list the drill itself wrote — `--all` and `--drill` are mutually exclusive, D3-safety
R7); every later stage byte-identical to production except `lr-ingest-verify` accepting a
non-limit tail. Fault arms: (a) headroom override in one launcher ⇒ `FAILED:gate:headroom` ≤ 3 s,
re-driven; (b) `kill -9` the watcher after `transplanted` ⇒ reaper `STALE` next tick, no keystroke
while a fixture watcher pid is alive; (c) a held draft ⇒ `HELD:draft` with NOTHING moved (no lock,
no tombstone) — the arm that could not pass in any of the three designs; (d) a queued
`<task-notification>` on one session ⇒ `queued` then `engaged`, not `FAILED:submit`; (e) seeded
all-thin accounts ⇒ `PARKED:no-target` with reasons, no transplant. `commands/limit-recover.md`:
the fleet section rewritten around `cc-lr`. **Acceptance:** the drill's expected-numbers table
(§ 13) as assertions, written to its own `results.tsv`; `time lr-fleet --locate` ≤ 2 s. **Saves:**
≈ **0.3** per recovery after W4; the drill is the DoD instrument. **Depends on:** W5.

---

## 13. DoD — a diff against the operator's target

| target (operator, 2026-09-19) | before (measured) | after (this plan; the number the drill asserts) | proven by |
|---|---|---|---|
| identify < 2 s from screenshot fields / pane / sid8 / keyword | `--locate` 40–86 s; no key on screen; 4-way ambiguous; 122/124 identical | pane id 0.007 s · sid8 0.012 s (both now ON the statusline) · tuple 0.18 s and REFUSES a tie · keyword ≤ 2 s bounded | `time bin/cc-find …`; `tests/cc-lr.bats`; statusline render `(N) ⌗<pane> <sid8> …` |
| ONE command | `lr-fleet --one` ×5 + 4 hand relaunches + 3 transport fights | `cc-lr recover <pane|sid8>` (or `/limit-recover <ref>`), one Bash call | transcript: 1 tool call per fire |
| detached / non-blocking | 24.4 min foreground polls; screenshots queued 13.5 / 38.1 / 35.2 min | call returns ≤ 3 s; verdict by mailbox ≤ 15 s + one turn; 0 `until` loops in the command | drill row 11; `grep -c 'until \[' commands/limit-recover.md` = 0 |
| engaged in place on the ranker's target, < 90 s idle / < 5 min loaded | 115–158 s, 1/5 engaged (falsely); 658 s parked | p50 ≤ 45 s, max ≤ 90 s idle (re-sum 35 s); loaded: ENGAGED ≤ 300 s or a NAMED `PARKED:capacity:<term>` with nothing moved; same kitty window id, same uuid, registry `account` = target | drill rows 5–7, 10 |
| every failure named in a status view within 30 s and re-drivable | 0/4 husks had a row or alarm; verdict only in a `$TMPDIR` log | gate refusal ≤ 3 s (`relaunch.rc`); submit ≤ 40 s (or `queued`); every terminal arm = row + `hf_alarm` + tty paint + notify; `cc-lr status` ≤ 0.1 s; re-drive by `cc-lr repair` or the daemon under I3 | fault arms (a)–(e); `handoffs.jsonl` intents with a terminal row 5/5 (today 7/15) |
| zero silent husks in a 5-session drill | 4/5 husks; 8 dangling intents today; pane 147 live | `lr_is_husk` = 0; every `recycle-intent` has a terminal row; kitty window count unchanged | drill rows 8–9 |
| no teammate touched | hook-only guard; explicit-ref path had none | `cc-find` rule 0 + hook skip + precheck refusal; SF-e fixture | `tests/cc-lr.bats`, SF-e |
| no recovered work landed | held (iron rule 7) | held; `grep` proof over the recovery scripts for `git (commit|push|merge|reset|checkout)` = 0 | W7 doc + grep |
| minimal tokens and time | ~26.5 K resident + 6–9 round trips per session; 344 lead messages | ≤ 0.2 K resident, 1 round trip on the `gaps 0` path; lead: 1 short turn per fire + 1 on the notify | drill row 12; `message.usage` dedup by `message.id` |

---

## 14. Dropped, with the reason

- **`CC_ADMIT_NET_ZERO`** (D1 C6, D2 C3/C5, D3 C4) — double-discounts with `226b73888`'s
  probe-side subtraction; patched one of two `act + 1` sites (`capacity-admit.sh:789`, `:839`);
  as an `export` it leaked into every hook of the recovered session for its whole life (D1-safety
  R1 FATAL, R2, R9; D2-FT R2; D2-safety R8; D3-FT R1).
- **`kind:"limited"` beat** (D1 C1) — same double-discount; the census discriminator is an open
  design call recorded in `226b73888`'s body; `lf_phantom_actives` already does the job for this
  caller.
- **`CC_ADMIT_BUDGET=1` in the launcher** (D2 C5, D3 C4) — makes every remaining term a
  one-attempt delay + page (D3-safety R2); with the token the launcher rarely evaluates; the per-run
  KEY is kept, the value is not lowered.
- **Retype in the watcher** (today's `:6812-6815`, D2 C7's N-attempt loop, D3 C5.4) — re-ran the
  identical command against a counter advanced by one (U02 §2d); with the token a refusal is real
  and is re-driven by the daemon with a fresh probe.
- **`shell-stable` heuristic / 20 s boot bound / `$_` loop floor** (D1 C9) — a false FAILED that
  `/exit`s a working session (D1-FT R2, D1-safety R6, D1-latency R2/R8).
- **`exit 11/12` verdict codes from the expect program** (D1 C8, D2 C6, D3 C6) — an `exit` before
  `interact` kills the TUI; after it, nothing reads the rc until the nested zsh exits
  (`lr-fire-resume.sh:598-606`) (D1-FT R3, D1-safety R13).
- **Quiet-pty blind inject** (all three designs) — a CR onto a parked menu takes its default
  (D1-safety R10, D3-FT R6); a quiet pty licenses a LOUD state and an affirmative-read inject only.
- **The reaper inside the poller's drain / group-`wait`ed workers** (D1 C3) — the reaper cannot
  bound the thing it runs inside (D1-FT R1, D1-latency R1/R6); workers are detached, the tick returns
  in seconds.
- **A per-run watchdog with keystroke repairs, the `exited` re-`/exit` repair, the 45 s submit
  repair, the adopt arm** (D3 C8) — two actuators on one pane; the `exited` repair `/exit`s a
  healthy recovery inside its own window (D3-safety R1 FATAL, R4, R8; D3-FT R3, R8); I3 replaces it
  with the daemon's read-only reaper that re-drives only through a claimed request.
- **`cc-lr … &` kicked from the hook** (D2 C4) — the hook's child may be reaped; it inherits
  `CLAUDE_CODE_SESSION_ID` so `lr-transplant.sh:97` skips the source rename (D2-latency R7,
  D2-safety R3/R12, D1-FT R6). The hook only writes.
- **Hook kick default ON** (D1 C1 at a self-stated 88 %) — below the F2 90 % bar and asymmetric to
  reverse (D1-safety R11); replaced by the operator-owned `autorecover.on` file (§ 15).
- **`cc-custody return` at DONE** (D2 C3) — discharges an originator's debt over a peer that
  merely resumed (D2-safety R4).
- **`index.jsonl` upsert; a `runs/` tree parallel to the bundle** (D2 §4.2) — unlocked
  read-modify-write (D2-FT #16); the bundle dir already exists per run.
- **`lr_state_set` read-modify-write doc with `|| true`** (D3 §3.3) — lost updates and silent
  failure (D3-FT R10); append-only lines, loud on failure.
- **`statusLine.refreshInterval: 5`** (D2 C12, D3 C1) — +0.28 core continuous on the box the gate
  measures (D3-latency R14); liveness is (pid,lstart), not telemetry age, so it buys nothing.
- **kitty `user_vars` belt** (D3 C1 change 4) — registry is 400× faster and rewritten on every
  SessionStart; deferred, not needed for the DoD.
- **`lr-ingest-verify` at `lr-handoff.sh:464`** (D1 C7) — 48 lines before the facts it checks
  exist (D1-latency R3); it runs in the launcher.
- **The global lock as the hook's "already moved" guard** (D1 C1, D3 C3) — never released, so a
  re-limited target could never be recovered (D1-safety R3, D3-FT R5); the guard is the tombstone
  beside THIS transcript, and the lock gains custody semantics.
- **`WatchPaths`** (D1 C2, D2 C11) in favour of `QueueDirectories` — Apple's own text calls
  WatchPaths race-prone; QueueDirectories re-launches on a non-empty dir (D1-latency R1).
- **`recover --all` at unbounded concurrency with N simultaneous probes** (D2 C3, D3 C2) — N
  probes mint N tokens and N ranks stack on rank[0] (D3-safety R2, D2-latency R6, D3-FT R9); a pool
  of 2 with a serialized admit section.
- **`repair --from EXITED`** naming (D2 §4.4) — the re-entry for a failed `/exit` is
  TRANSPLANTED (D2-FT #9); `cc-lr repair` writes a request instead.
- **`CC_SF_REQUEST_KICK` env default** — replaced by the file flag so enable and disable are the
  same operator action.
- **`bin/cc-pane send` kitty driver** — off the happy path; documented UNAVAILABLE on kitty until
  it grows a driver (U08 §3a); `cc-tui.sh` is the one outside-the-pty typer and it is used only by
  the daemon's `mode:prompt` repair.

---

## 15. Open decisions — operator value forks ONLY (everything else above is decided)

1. **Auto-recover policy (spend).** Should a session limit trigger a transplant onto another
   account with no human in the loop? It spends the other accounts' quota by the recovered
   session's own burn (0.30–1.10 pp per session-hour measured, U13 §3a), bounded by the recovery
   lane's survival floors and the 2-wide pool. The operator's stated target was screenshot → ONE
   command (manual-initiated); zero-touch is beyond the ask. **Shipped default: OFF** —
   `~/.reso/limit-recover/autorecover.on` absent; the hook still writes the request (so
   `cc-find --limited` is instant and the one command needs no census). Flip = `touch` that file
   after two clean drills; conviction the lane is safe with it ON: 85 % pending drill fault arms
   (b) and (c) — below the 90 % bar, so it is theirs.
2. **Thin-account policy (spend vs wait).** When the recovery lane excludes every account (weekly
   ≥ 90 % everywhere), park until the source resets (today: 2 h 41 m) or admit the least-thin
   account for its last ≤ 10 %? U13 §3b declined the "imminent reset rescues a thin account" rule
   because it re-imports the deadline reasoning that caused the mis-pick and the stall is invisible
   to every watchdog. **Shipped default: PARK** (`PARKED:no-target` with the router's reasons, the
   reset-wait arm as the floor). Conviction 80 % — a value call about whether an hour of a thin
   account is worth more than an hour of a parked session.

Operator STEPS (not decisions; filed by the implementing wave with `cc-backlog needs … --run`):
the plist `QueueDirectories` install (W5); the 30-column glyph eyes-check (W4); the `autorecover.on`
flag if decision 1 is yes; the manual relaunch of pane 147 (`07e30aeb`) once its draft is cleared
(W2 files it with the exact `bash <launcher>` line).

---

## 16. Risks and unmeasured hinges (labelled)

- **GUESS:** CC teardown ≈ 3 s, boot ≈ 4 s, first turn 12–15 s (U14 B); every stage bound is
  env-overridable (`LR_BUDGET_<STAGE>_S`) and the drill's `events.jsonl` timestamps are the
  measurement.
- **Unmeasured:** whether `StopFailure` fires inside an Agent-Teams assignee (0/10 marker sids were
  teammates, U10 §3c) — SF-e is the fixture; until then both oracles skip assignees.
- **Unmeasured:** `quotaLimits` on weekly / Fable-scoped caps (all today were `five_hour`) —
  `rateLimitType` is carried with the prose regex as fallback.
- **Unmeasured:** the kitty socket 1-in-12 timeout rate under two concurrent recycles; every RPC is
  bounded and INDETERMINATE.
- **Unmeasured:** whether a queued prompt typed mid-turn lands as `enqueue` or is
  `absorbed_mid_turn` (both shapes exist in pane 112's transcript, D1-FT §5.5); the probe accepts
  either.
- **Token TTL 300 s** rests on the composer pre-check making the 180 s gate the exception; a
  bgwork dialog that holds the shell wait past 300 s yields a named `FAILED:gate:token-expired` and
  a re-drive, never a silent husk — the residual is one extra probe.
- **`RECOVERY_W_FLOOR 0.10`** rests on one 2.43 h burn window, n = 4 (U13 §6); a transplanted
  session's cold first hour may burn faster — re-derive from the drill's `account-utilization.jsonl`.
- **Live-layer convergence between waves:** the launcher execs the LIVE `lr-fire-resume.sh`; W2's
  preflight refuses a token-less live lib, so an unconverged land is a refusal, never a husk.
- **The pane-147 stub** (`07e30aeb….jsonl`, 2,886 B beside its tombstone) is a split-brain in
  waiting if anything resumes the source uuid; `handed-off-session-guard.sh` blocks prompts but not
  a process (D3-safety R6) — C18 closes the one auditor that would.

---

## § 6 Status log (continued) — entry to append

- 2026-09-19T21:xxZ · **REOPENED.** The 2026-09-10 close was an n = 1 acceptance. Two fleet
  events today: morning next4 (5 sessions, 98.7 min, 1/5 recovered — on a stale counter — 4 husks
  with no row; U11) and afternoon next3 (8 sessions incl. this plan's lead; the probe/launcher
  split moved from the load term to the active term after `226b73888`; pane 147 `07e30aeb` is a
  live stranded-draft husk). 14 research units, 3 designs, 9 critiques under
  `scratchpad/lr/` → this reopen's §§ Phase 0, 9–16. Waves W1–W7 fired per Phase 0; the DoD is
  § 13's after column, proven by `tests/lr-drill.sh`.
