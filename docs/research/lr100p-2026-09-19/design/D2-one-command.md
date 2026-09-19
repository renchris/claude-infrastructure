# D2 — ONE COMMAND: `cc-lr <ref>` — resolve in <2 s, fire detached, return a tracking id

Designer D2-one-command · 2026-09-19 · built on research units U01–U14 (all cited as `U<nn> §<sec>`);
repo paths relative to `/Users/chrisren/Development/claude-infrastructure`; every constant below is
either measured in a unit or justified by one.

---

## 0. The verdict, in five sentences

1. **The chain already does its real work in ~3 s** — audit 1.1 s, bundle, transplant 0.45 s,
   launcher mint (U02 §1). Today's 98.7 min was gates, poll quanta, blindness and a lead that
   polled files instead of ending its turn (U11 §2, §7).
2. **Identification is O(1) once the screen carries a key.** `~/.claude/cc-registry/<pane>.json`
   answers pane→sid in ~2 ms and sid8→pane in 12 ms (U07 §6b, U14 §3.1); the statusline just does
   not print either field, so today's key was 4-way ambiguous (U14 §3.2). Seven lines in
   `statusline.sh` fix that at +1.2 ms/render (U07 §3c).
3. **4 of 5 husks were one off-by-one**: the watcher makes 2 launcher attempts, the capacity
   budget releases on the 4th, and the lead's `CC_ADMIT_LOAD_TERM=off` never reached a process typed
   into another pane's shell (U01 §5.3, U02 §0, U04 §0, U05 §3.4). Three `export` lines in the
   generated launcher close it.
4. **0 of 5 ingests were delivered by the expect layer**, including the one reported RECOVERED
   (U03 §headline, U11 §0). The submit oracle is a screen phrase that 2.1.260 no longer renders;
   the correct oracle is a `type:"user"` record carrying the bundle path in the TARGET transcript,
   and it separates SUBMITTED from ENGAGED (U03 §4, U08 §4.3).
5. **The detector already fired 3 min before the operator did** and wrote it to a file nothing
   reads (U10 §1c, §1g; U06 §2). So the design is: **one state machine, one state store, one
   detached driver, one resolver** — wrapped around the lr-* scripts that are sound, with six named
   line-level fixes to the ones that are not.

---

## 1. CLI surface — `bin/cc-lr` (new)

```
cc-lr <ref> [--target A] [--dry-run]      resolve → plan → fire DETACHED → print id → exit (<2 s)
cc-lr status [<id>|--all|--json|--sweep]  every in-flight / failed / recent run: state · age · cause
cc-lr repair <id> [--from <STATE>]        re-drive from the failed step, with the proven transport
cc-lr find <ref> [--json]                 the resolver alone; prints the candidate set, never picks
cc-lr watch <id>                          block until terminal — for a HUMAN shell, never a Bash tool
cc-lr auto [status|on|off]                the StopFailure → request → driver arm (kill switch)
```

### 1.1 `<ref>` — four shapes, resolved in this order, first unambiguous hit wins

| shape | example | resolver | measured cost | source |
|---|---|---|---|---|
| pane id | `117`, `p117`, `⌗117` | `cat ~/.claude/cc-registry/117.json` | ~2 ms | U14 §3.1 |
| sid prefix (≥6 hex) | `cb227486` | `grep -l '"session_id": "cb227486'` over 26 registry rows; then `parked/<sid>*.json`, `requests/<sid>*.json`, the `rate_limit__*.jsonl` marker | 12 ms | U07 §6b |
| statusline text | `'(2) 45% · claude-infrastructure (b80f9408e) · xhigh'` | one `jq -n '[inputs]'` join of registry + `/tmp/cc-telemetry/*.json`, filter on (account ordinal, cwd basename, effort); rank by `\|pct − live pct\|`; **never** on sha (it moves under the session: `b80f9408e → 0194d9cb1` in 25 min), never exactly on pct | 0.177 s | U07 §4, §6c |
| keyword | `--kw 'guest list'` | `kitty @ get-text --match id:N` over live registry panes, plus `session_name` from telemetry once C12 lands | ~0.7 s (16 panes × 40 ms) | U14 §3.3, U08 §6 |
| none | `cc-lr` | if exactly ONE open `requests/*.json` (or one unclaimed `rate_limit__*` marker line) exists, take it; else print the list and exit 2 | 5 ms | U10 §2b |

**Refusal is a feature.** A tuple or keyword that leaves >1 candidate prints every candidate with
pane id · sid8 · account · cwd · kitty title · liveness and exits 2. It never guesses: panes 122 and
124 rendered byte-identical statuslines today (U07 §0), and "a wrong pane recycled" is the one
failure this tool must be unable to produce (U07 §6c rule 4).

**Liveness is `kill -0 <registry pid>`, never telemetry age** (pane 126 was 52.5 min stale while
alive — U07 §4). `kitty @ ls --match id:N` (37 ms, U08 §6) is consulted only to confirm the window
exists, bounded by `timeout 2` — one call in four today took 10.06 s and returned a payload
truncated mid-string (U07 §5). On timeout the resolver answers from the registry and marks
`liveness: "unverified-kitty-timeout"`; it does not refuse.

### 1.2 What `cc-lr 117` prints, and when it returns

```
cc-lr: 117 → cb227486 (next4 · claude-fable-5-1/xhigh · ~/Development/claude-infrastructure) limit five_hour, resets 14:40
cc-lr: target next3 (recovery lane: next=recovery-weekly-thin next4=source next2=0.000019)  admitted headroom-only
cc-lr: fired  lr-cb227486-20260919T175207Z   → cc-lr status lr-cb227486-20260919T175207Z
```

Three lines, ≤2 s, exit 0. The third line names the ONE command to run next. Nothing else is
printed until the operator asks. The driver runs under `setsid` (§4.1) so the invoking Bash tool
call — and the operator's next prompt — is never held.

### 1.3 Tracking id

`lr-<sid8>-<UTC stamp>` — e.g. `lr-cb227486-20260919T175207Z`. Human-readable, unique per attempt,
sortable, and the `<sid8>` half is exactly the token the resolver accepts, so `cc-lr status` and
`cc-lr repair` accept either the id or the sid8 (latest run wins on a bare sid8).

### 1.4 What `/limit-recover <ref>` becomes

`commands/limit-recover.md` gains a front section: **run `cc-lr <ref>` (one Bash call), print its
three lines verbatim, and END THE TURN.** The driver's terminal event delivers a mailbox line to
the invoking pane (§4.5), which `mailbox-drain` reads at the next turn boundary and
`mailbox-wake-arm` uses to wake an idle session — the same wake path the lead's own fires used
today, which beat every one of the lead's blocking polls by 1–5 s (U11 §2). This one behaviour
change removes 24.4 min of lead polling and ~87 min of queued-screenshot latency (U11 §7 #1).

---

## 2. The state machine

One run = one directory, one `state.json`, one append-only `events.jsonl`. Every transition is a
row; a step that cannot prove its transition inside its budget writes a terminal `FAILED-<step>`
row carrying the evidence it DID read. There is no "pending forever": every non-terminal state has
a deadline that produces a named failure (§3).

```
                       ┌──────────────── pre-irreversible (nothing changed on failure) ────────────────┐
 DETECTED ─► RESOLVED ─► TARGETED ─► ADMITTED ─► BUNDLED ─► TRANSPLANTED ─► EXITED ─► RELAUNCHED ─► SUBMITTED ─► ENGAGED ─► DONE
     │            │           │           │           │            │ irreversible    │            │            │
     ▼            ▼           ▼           ▼           ▼            ▼                 ▼            ▼            ▼
 AMBIGUOUS   REFUSED-    REFUSED-    REFUSED-    REFUSED-     FAILED-EXIT     FAILED-       FAILED-      FAILED-
             RESOLVE     TARGET      ADMIT       BUNDLE       (pane never     RELAUNCH      SUBMIT       ENGAGE
                                                              reached shell)  (no claude;   (no user     (no assistant
                                                                              cause from    record w/    turn after
                                                                              IDL)          token)       SUBMITTED)
 any state ──(driver pid dead, no terminal row)──► FAILED-DRIVER-DIED    (found by `status --sweep`)
```

| state | proven by (evidence written into the row) | who advances it |
|---|---|---|
| `DETECTED` | `requests/<sid>.json` exists, written by the StopFailure hook (C4) or by `cc-lr <ref>` | hook / cc-lr |
| `RESOLVED` | `resolve.json`: sid, pane, cfg, account, cwd, tier, pid, death_uuid, `reset_at_epoch`, `rate_limit_type` (from `quotaLimits`, U10 §1d) | cc-lr (foreground, ≤2 s) |
| `TARGETED` | `rank.json`: ranker stdout **and stderr** (the exclusion reasons U13 D2 says are thrown away today), the pick, `--assign` receipt | driver |
| `ADMITTED` | IDL row `caller=lr-drive basis∈{measured,headroom-only,gate-off}` with load term OFF (U05 P1) | driver |
| `BUNDLED` | `MANIFEST.json` path, `gaps_at_handoff`, `INGEST-VERIFIED.txt` (U12 §6.1) | lr-handoff |
| `TRANSPLANTED` | `locks/<sid>.lock` + `<sid>.HANDOFF.json` + sha match in `transplant.json` (`"ok":true`) | lr-transplant (unchanged) |
| `EXITED` | watcher log `→ pane N CONFIRMED at a shell prompt after Ns` | handoff-fire watcher |
| `RELAUNCHED` | `cc_alive` on the pane's tty AND the registry row for the pane now carries a NEW pid (`session-register.sh` rewrites it on SessionStart, U07 §4) | watcher |
| `SUBMITTED` | a `type:"user"` record newer than `RCY_T0` whose content contains the run's submit token (the bundle path — present verbatim in both the slash and plain forms, U03 §4) in `<target cfg>/projects/*/<sid>.jsonl` | `lr-submit-probe.sh` (C6) |
| `ENGAGED` | `resume_engaged` (non-error, content-bearing assistant turn) **after** the SUBMITTED record's timestamp — never before it, which is what let a stale `<task-notification>` pass on pane 112 (U03 headline) | watcher |
| `DONE` | request removed, `parked/<sid>.json` retired, `results.tsv` row appended, custody discharged if any, mailbox line delivered to the requester | driver |

Two invariants the store enforces, not prose:

- **TRANSPLANTED is the only irreversible edge**, and it is entered only from ADMITTED — the probe
  and the launcher now evaluate the SAME term set (U05 T3) and the release is reachable inside the
  watcher (U05 T2), so "transplanted but never relaunched" needs a genuinely new fault, and when it
  happens it is `FAILED-RELAUNCH` with the IDL cause, a page, and a `repair` path — never a husk.
- **SUBMITTED precedes ENGAGED.** An assistant turn without a submitted token is not engagement;
  it is `FAILED-SUBMIT` with `note: "assistant turn seen but no user record carrying the token —
  session is live on a stale notification, prompt not delivered"` (the pane-112 shape, U11 §0 B).

---

## 3. Every timeout, with its justification

| step | bound | poll | why this number | replaces |
|---|---|---|---|---|
| resolver (`find`) | **2 s** hard | — | registry 2–12 ms; `kitty @ ls --match` 37 ms; the 10.06 s kitty timeout must be bounded and treated as INDETERMINATE (U07 §5, U08 §6) | `lr-fleet --locate` 40–86 s (U14 §0) |
| rank | **3 s** | — | `--rank` 0.47–1.09 s (U14 A5); 90 s cache TTL (U01 §3.2); over budget ⇒ `REFUSED-TARGET` with the timing, never a blind pick | `2>/dev/null` discard (U13 D2) |
| capacity probe | **60 s** total | 5 s | load term OFF (all 41 of today's 55 refusals were load, U05 §3); headroom 0/55 ever fired (U05 §7.4); segments/active move within seconds. 600 s was the 10.1-min foreground block (U05 §3.1) | `LR_FLEET_CAP_WAIT_S` 600 / 20 (`lr-fleet.sh:283`) |
| bundle + transplant | **30 s** | — | measured 1–2 s (U02 §1); 241 MB tail transcript ≈ 5 s (U14 §1.3) | none |
| `/exit` → shell | **600 s** ceiling kept, driver shows `EXITING +Ns` | **1 s** | the 600 s is the composer-draft gate's budget (`HF:11634`, a held draft must not be `/exit`ed over — U04 F2); the quantum is what changes: `HF:6619 sleep 3` → 1 s, `HF:6786 sleep 2` fixed → poll | 3 s quantum + 2 s fixed (U14 §4.2 #5, #8) |
| relaunch → process | **20 s per attempt**, attempts = `CC_ADMIT_BUDGET + 1` = **2** | 1 s | `lr-fire-resume` refuses in ~2 s (U04 §0); the wait exits early when `at_shell` reads true on 2 consecutive samples ≥3 s after the type (`pane_cc_state` classifies the launcher's own `bash` prologue as shell for ~2 s — U04 §5 C); on exit the driver joins the IDL row `caller=lr-fire-resume ts>type_ts` and names the term (U04 §5 D) | 45 + 45 s dead wait, 2 attempts against a budget of 3 (`HF:6811-6816`) |
| READY → inject | **30 s** for the READY phrase, then **quiet-pty 8 s** fallback inject | — | `for shortcuts` does not render in auto mode; `shift+tab to cycle` has 0 hits in 2.1.260; only `auto mode on` survives (U03 §2a); a quiet pty is version-proof | `timeout 300 {}` silent drop (`lr-fire-resume.sh:560`) |
| fixed pre-inject sleeps | **0.3 + 0.2 + 0.2 s** | — | 2 + 1 + 1 s were unconditional (U14 §1.4); the read-back after typing is what proves delivery, not the sleep | 4 s |
| submit verify | **20 × 1 s** transcript poll, then ONE re-CR, then **10 s** more | 1 s | `tail -c 400000` of a 12 MB transcript = 19 ms (U08 §6); the old oracle `esc to interrupt` matches only the API-retry line on 2.1.260, so 5 × 6 s always timed out (U03 §2b) | 30 s dead + 5 blind CRs |
| engage | **180 s** | 1 s | first model turn ~12–15 s idle (U14 §2.2 #12); an xhigh Fable cold context replaying 600 K cache tokens is slower (U12 §3); `RCY_ENGAGE_INTERVAL` 5 → 1 costs nothing (a transcript grep) | 180 / 5 (`HF:6782-6783`) |
| driver deadline | **15 min** hard | — | sum of every ceiling above ≈ 13.9 min; past it the run is `FAILED-TIMEOUT` carrying the last state, not silent | `recycle_await_verdict` 900 s that could not cover the composer gate (U04 §1) |
| husk sweep | **3 min** after `EXITED` with no later row | 600 s tick | the U04 §3 predicate: intent + tombstone + no engaged row + dead pid; 3 min is > relaunch (40 s) + submit (30 s) + engage floor (15 s) with slack | nothing sweeps today (U01 §4.1) |

Sum on an idle box: resolve 0.3 + rank 0.5 ∥ + probe 0.1 + bundle 3 + exit ~3.5 + type 1 + boot ~4 +
inject 0.7 + submit ~1 + first turn ~14 + verdict 0.5 ≈ **28–35 s to ENGAGED**, against 115–158 s
today (U14 §2.2, §4.3). The irreducible floor is ~21 s (CC teardown 3 + boot 4 + one model turn 14).

---

## 4. Components — files, functions, lines

### C1 · `bin/cc-lr` (new, bash 3.2-safe, ~380 lines)

`main` → `lr_resolve` (C2) → write `runs/<id>/{state.json,events.jsonl,resolve.json}` → `detach`
(§4.1) `lr-drive.sh <id>` → print 3 lines → exit. Sub-verbs `status` / `repair` / `find` / `watch` /
`auto` are thin: `status` reads `index.jsonl` + each non-terminal run's `state.json` + `kill -0` on
the driver pid and the pane pid; `repair` re-invokes `lr-drive.sh <id> --from <STATE>`; `auto`
toggles `~/.reso/limit-recover/auto.off` (the hook's kill switch, C4).

**`status` rendering** (one row per run, newest first, colour = explicit truecolor, never SGR-2 —
memory `feedback-tui-visibility-numbers-first`):

```
ID                              PANE  SID       ACCT→ACCT    STATE            AGE    CAUSE / NEXT
lr-cb227486-20260919T175207Z    117   cb227486  next4→next2  ENGAGED          31s    —
lr-09e64dcb-20260919T172126Z    111   09e64dcb  next4→next3  FAILED-RELAUNCH  2m10s  capacity-admit refuse term=load 2.57/core (refusal 1 of budget 1) → cc-lr repair lr-09e64dcb-20260919T172126Z
lr-e442434c-20260919T174403Z    121   e442434c  next4→next3  EXITING          +48s   pane at composer-draft gate (HF:11634) — waiting, ceiling 600s
```

The CAUSE column is the IDL/watcher fact, and the NEXT is the ONE command. `--sweep` additionally
applies the husk predicate (§3 last row) and marks `FAILED-DRIVER-DIED`, then pages once per run id
via `cc-notify --role desk` (latched on `runs/<id>/.paged`).

### C2 · `scripts/limit-recover/lr-resolve.sh` (new, ~130 lines) — the resolver

Pure reads. Emits one JSON object (or a candidate array + rc 2). Sourced by `cc-lr find` and by
`lr-fleet.sh --one` (C8) so both share one implementation. The registry+telemetry join is the
one-`jq` form U07 §6b prints verbatim (0.177 s for 16 live sessions); the pane and sid8 paths are
single file reads. Tier via `lr_tier_from_transcript` (`lr-lib.sh:34`, 79 ms — U10 §2c); reset and
type via the extended `lr_last_api_error` (`lr-lib.sh:129-159`, +2 lines to emit
`quotaLimits.resetsAt` and `rateLimitType` — U10 §1d).

### C3 · `scripts/limit-recover/lr-drive.sh` (new, ~260 lines) — the detached driver

Runs the chain end-to-end under `setsid`, advancing state through one function
`lrd_to <STATE> <evidence-json>` that appends to `events.jsonl`, rewrites `state.json` (tmp+mv), and
upserts `index.jsonl`. It **calls the existing scripts**, it does not fork them:

| step | call | change needed in the callee |
|---|---|---|
| TARGETED | `claude-accounts --rank <kind> --recovery` (C9), stderr captured to `rank.json`; then `--assign <t> --src lr-drive` | C9 |
| ADMITTED | `CC_ADMIT_LOAD_TERM=off CC_ADMIT_NET_ZERO=1 cc_capacity_probe lr-drive "<what>"`, 60 s / 5 s loop | `capacity-admit.sh:832` net-zero delta (U05 §5.5 i) |
| BUNDLED → TRANSPLANTED → EXITED → RELAUNCHED → ENGAGED | `lr-handoff.sh --sid … --in-place --source-pane P --run-id <id>` — which calls `handoff-fire.sh --recycle … --await`; the driver **also** tails the watcher log itself so intermediate states land in `events.jsonl` as they happen | C5, C7 |
| SUBMITTED | the watcher calls `lr-submit-probe.sh` (C6) once `cc_alive`; the driver mirrors it | C6, C7 |
| DONE | `rm requests/<sid>.json`; `mv parked/<sid>.json resumed/`; `lf_row` into `fleet/<RUN>/results.tsv` (compat); `cc-custody return` if a custody debt names this pane; `cc-notify <requester-pane> "lr-<id>: ENGAGED pane P on next3 in 31s"` | none |
| any FAILED-* | `emit_recycle_event` already ran in the watcher for its own arms; the driver adds `hf_alarm`-shaped record + `cc-notify --role desk` + the `results.tsv` row with the CAUSE joined from the IDL (U05 P4) | — |

`--from <STATE>` (for `repair`) enters the chain at that step with the run's own `resolve.json` /
`MANIFEST.json`, never re-transplanting: a second `lr-transplant.sh` on a moved sid is refused by
its own destination-exists guard (`lr-transplant.sh:55-57`, U02 §1), which is the right refusal.

**Concurrency.** N runs are independent except for the per-sid lock (`lr-transplant.sh:60`) and
the account store; `cc-lr --all` fires N drivers at once, so 5 × 150 s becomes ≈ max(single)
(U14 §2.3). Two guards make that safe: the refusal counter is keyed per run
(`CC_ADMIT_BUDGET_KEY=<id>` → `_cc_admit_state_file` at `capacity-admit.sh:509-514` keys
`<caller>.<key>.refusals`) so one run's release cannot reset another's (U05 P3 — today's one
success rode a counter a sibling had pre-spent); and each pick charges `--assign` so the next pick
walks down the ranking inside the 90 s cache TTL (U13 §3c).

### C4 · `hooks/stop-failure-marker.sh` — ARM 2, ≈35 lines after `:130` (U10 §2g verbatim)

Writes `requests/<sid>.json` with `sid, target:"auto", source_pane ($KITTY_WINDOW_ID — verified in
the CC process env, U10 §2c), account, cwd, tier, transcript_path, reset_at_epoch, rate_limit_type,
death_uuid, origin_class`; latched on `requests-latch/<sid>.<death_uuid>` with `set -C` (event-keyed,
never sid-keyed — `e442434c` fired 3× in 16 s and again 28 min later, U10 §1c); skips when a
`HANDOFF.json` tombstone or `locks/<sid>` already exists (a limit re-fires on the dead account when a
queued notification runs a turn — U10 §3d-3); skips teammates (`agent_assignee_argv` ∧ the
`agentName` head-8k backstop) and writes `teammate-skip/<sid>`; then **kicks the driver directly**:

```sh
[ -f "$LRSTATE/auto.off" ] || "$HOME/.claude/bin/cc-lr" "$SID" --from-hook >/dev/null 2>&1 &
```

— `cc-lr` itself `setsid`s the driver, so the hook returns inside its 10 s budget (measured 0.19–
0.25 s today, U10 §2a; +0.1 s for the tier read). This is the **~0 s detection-to-fire path** the
plan dropped when it declined `WatchPaths` (U09 gap #15). Every path exits 0 with empty stdout — the
file's fail-open contract (`:31-33`). No new hook, no settings edit: the hook is already registered
on `StopFailure` in all five config dirs (U10 §1c), and a new registration would be a c10 step.

`cc-lr auto off` writes `auto.off`; the hook then only writes the request (the poller drains it on
its tick, C10). Default is **on**: today the five sessions sat 5–45 min after detection for a total
of 2 h 37 m of idle (U10 §1g), and the operator's target is instant.

### C5 · `scripts/limit-recover/lr-handoff.sh` — the launcher heredoc `:586-593`, +5 lines

```sh
export CC_ADMIT_LOAD_TERM="${CC_ADMIT_LOAD_TERM:-off}"   # U05 P1: the term whose INPUT is wrong; off on the Agent tool since Wave D (agent-teams-enforce.sh:229) and on the operator's own fire (HF:6075)
export CC_ADMIT_NET_ZERO=1                               # U05 §5.5: a recycle /exits one and starts one — never a +1
export CC_ADMIT_BUDGET="${CC_ADMIT_BUDGET:-1}"           # U04 §5 A / U05 P3: release on the watcher's SECOND attempt, page preserved
export CC_ADMIT_BUDGET_KEY=$(printf '%q' "$LR_RUN_ID")   # per-run counter — never inherit a sibling's spend
export LR_RUN_ID=$(printf '%q' "$LR_RUN_ID") LR_SUBMIT_TOKEN=$(printf '%q' "$BUNDLE")
```

This is the only channel that survives into the pane's fresh process tree (U04 §2, U01 §5.1). Also
in this file: `INGEST_PROMPT` at `:464` becomes U12 §6.1's gated form — `lr-ingest-verify.sh` (new,
~40 lines of `jq -e` predicates) writes `INGEST-VERIFIED.txt`; rc 0 ⇒ the one-line **non-slash**
prompt of U12 §6.2 (removes the `/`-headed autocomplete class `HF:6867` names; costs 1 model round
trip instead of 6–9, ~26 K resident tokens → ~0.1 K — U12 §6.3); rc ≠ 0 ⇒ today's
`/limit-recover ingest <bundle>` with the failing clause appended, so the degraded path is visible
in the prompt. `HANDOFF-CONTEXT.md` emits only the LAST DoD entry plus a pointer (86,888 B → ~1 KB,
U02 §4); `MANIFEST.json` drops `source_argv` (86 % of the file and wrong about the tier in 3 of 5,
U02 §1). Add `--run-id` to the argv so the launcher and the recycle carry it.

### C6 · `scripts/limit-recover/lr-fire-resume.sh` `:549-583` + `lr-submit-probe.sh` (new, ~25 lines)

U03 §4 in full: capture `LR_T0` + `LR_SUBMIT_TOKEN` before `spawn`; replace the `esc to interrupt`
loop with a Tcl poll that `exec`s `lr-submit-probe.sh <cfg> <sid> <t0> <token>` (rc 0 when a
`type:"user"` record newer than `t0` contains the token — the shape of pane 117's real record,
U03 §4); one re-CR then one re-poll; on failure print `✗ SUBMIT FAILED` naming the prompt and **exit
12** so `lr-handoff`/`lr-drive` mark `FAILED-SUBMIT` for the right reason. Replace `timeout {}` at
`:560` with the quiet-pty 8 s fallback inject and a loud `✗ READY NEVER SEEN` line; drop the dead
`shift+tab to cycle` alternative; add `fullscreenUpsellSeenCount` / `fullscreenDownsellSeenCount` to
`lr-preseed-env.sh:115-117`'s `UPSELL_FLOOR` (sits at 3 in both target accounts today, U03 §2a).
Fixed sleeps `:552/:554/:556` → 0.3/0.2/0.2 s.

### C7 · `scripts/handoff-fire.sh` — the watcher `:6786-6881`, and the await

- `:6878-6880` (the H8 arm that fired 4/4 today with no row and no alarm — U01 §4.1, U04 §3): add
  the 3 lines its two siblings already have — `emit_recycle_event recycle-dead 0 …`,
  `goal_unreachable recycle-dead`, `hf_alarm recycle-dead …` — with the detail built from the IDL
  join (`jq … select(.caller=="lr-fire-resume" and .verdict=="refuse" and .ts > $t0)`), so the
  message reads `capacity-admit refuse term=load 2.57/core` rather than `no claude process appeared
  within 90s`; and print the REAL elapsed, since the `unknown` pane state skips the retype and the
  line still says 90 s (U04 §1).
- `:6811-6816`: U04 §5 B+C — a `while` over `attempts=$(( CC_ADMIT_BUDGET + 1 ))` (from the launcher
  env; default 2), 1 s ticks, early exit on 2 consecutive `at_shell` samples ≥3 s after the type,
  retype gated on the affirmative `shell` verdict exactly as today.
- `:6786 sleep 2` → poll `at_shell` at 0.5 s (max 5 s); `:6619 sleep 3` → 1 s; `:6783` interval
  5 → 1.
- `:6845-6860`: in resume mode call `lr-submit-probe.sh` first and emit a new `recycle-submitted`
  row (join key `target_pane`, which — measured on today's rows — IS populated on both the intent
  and the engaged rows: `grep '"gate":"recycle"' ~/.claude/logs/handoffs.jsonl | jq
  '{class,target_pane,pane}'` ⇒ `target_pane:"112"` on both, `pane:null` on both; the U01 §4.1
  field-name worry does not bite); only then `resume_engaged` with the SUBMITTED timestamp as the
  baseline.
- `:11786-11804 recycle_await_verdict`: `HF_RECYCLE_AWAIT_IVL` 5 → 0.5 s; `max` becomes
  `CC_RECYCLE_DRAFT_WAIT + HF_RECYCLE_SHELL_WAIT_S + 2×20 + RCY_ENGAGE_TIMEOUT + 60` so it covers
  the composer gate it cannot cover today (U04 §1); add `recycle-submitted` to the grep.
- `:9296` `--assign` guard: `[ "$RECYCLE" = 0 ]` becomes "skip only when the recycle stays on the
  same account" (U13 D3) — or leave it and let `lr-drive` charge (C3); one of the two, not both.

### C8 · `scripts/limit-recover/lr-fleet.sh` — four line-level fixes, kept as the compat surface

- `:426` `--one` runs the full census before the 0.039 s resolver at `:428-433` — invert: call
  `lr-resolve.sh` first, `lf_locate` only on a miss (U14 §4.2 #2).
- `:217` `DUPLICATE` — subtract the registry pid from the resume-proc set exactly as `:494-499`
  already does (U01 §1.3); a recovered session must read RECOVERED, not split-brain.
- `:282-291 lf_capacity_wait` — `CC_ADMIT_LOAD_TERM="${CC_ADMIT_LOAD_TERM:-off}"` on the probe,
  default `LR_FLEET_CAP_WAIT_S` 600 → 60 (U05 P1, U14 #3).
- `:294-309 lf_pick_target` — `--recovery`, keep stderr into `rank.<kind>.stderr`, `--assign` after
  a non-dry pick, park note carries the router's reasons (U13 §4c verbatim). `:333-337` rc-4 arm —
  join the IDL cause into the note (U05 P4).
- `lr-lib.sh:20-27` — skip `~/.claude-next` when `projects` `realpath`s to `~/.claude/projects`
  (16.3 % of the census scanned twice, U01 §1.2); the per-file `tail|grep|grep` loop at `:187-196`
  becomes one Python pass (0.148 s vs 61 s, U14 A3/A4) — this makes the fleet form usable again but
  is NOT on `cc-lr`'s hot path.

### C9 · `bin/claude-accounts --recovery` + `accounts.json` `.router` floors (U13 §4a-b verbatim)

`RECOVERY_W_FLOOR 0.10 · RECOVERY_S_CEIL 0.60 · RECOVERY_F_FLOOR 0.05`, a modifier on `_excluded`
and `score_fable` (never a fourth lane), reason strings `recovery-weekly-thin / -5h-thin /
-fable-thin` classed POLICY so an all-thin fleet exits 2, `route-meta` gains `recovery=1|0`, kill
switch `CC_ROUTE_RECOVERY=off`. Why: `next` at 2 pp weekly was rank[0] in the fable lane on a
40× urgency term and hit weekly 100 % 1 h 54 m after being named (U13 §1, §3a).

### C10 · `scripts/limit-recover/lr-reset-poller.sh`

- `:902-905` — `lr_transplanted_to` is necessary, not sufficient: retire the parked record only
  when a `runs/*/state.json` for that sid reads `DONE`/`ENGAGED`, or `lr_registry_live_rows` shows
  a live pid under the TARGET cfg; otherwise log `HUSK <sid> — transplanted, no live successor
  (run <id> state <S>)` and leave the record (U02 §2c: today it writes the husk off as "the
  successor carries it").
- `:639-661` request drain — replace the in-lock synchronous `lr-fleet --one` (45 s each, serial,
  U06 §4 gap 2) with `cc-lr <sid> --from-request` which returns in <2 s; results are read from
  `runs/`, not from a per-request log nobody reads. Add the reaper arm: any `requests/*.json` older
  than 2 ticks, or any run non-terminal past its deadline, pages once (U06 §4 gap 3, U10 §2f).
- Above `:896` — the reset-wait remains the FALLBACK for "no account has headroom"
  (`claude-accounts --rank … --recovery` exits 2); it is no longer the first branch (U06 §5 A).

### C11 · `com.reso.lr-reset-poller.plist` — `WatchPaths` on `~/.reso/limit-recover/requests`

An operator c10 step (a plist edit, `limit-reset-safety-gate.sh:34-38`); staged as a migration,
`launchd-parity-lint.sh` keeps live == SSOT. Until it lands, C4's direct kick covers the latency
and the poller's 600 s tick is the belt (U10 §2e). `ThrottleInterval 30` like `browse-mirror`.

### C12 · `statusline.sh` — identity segment (U07 §6a, 7 lines) + telemetry fields

`⌗<pane> <sid8>` left-anchored after the account glyph — `${KITTY_WINDOW_ID:-${ITERM_SESSION_ID##*:}}`
and `${PAY_SID:0:8}` are both already in scope (`:77-86`, `:415-416`), 0 forks, +1.2 ms, +14 cols;
survives the 30-col panes where sha and effort are amputated today (9 of 16 live panes, U07 §2b).
Add `pane`, `session_name`, `rate_limits.{five_hour,seven_day}` to the telemetry `jq` at `:149-156`
(same call, 0 forks) so a keyword lookup never opens a transcript and the ranker's inputs are
per-pane facts. Set `statusLine.refreshInterval: 5` so a halted pane keeps rendering (U07 §3d).
**`~/.claude/statusline.sh` is a copy-deployed real file** (`:119-121`, U07 §1) — the land must be
followed by `install.sh` / `deploy-live.sh`, and `tests/statusline-identity.bats` layer 2 gains an
assertion for the new fields. Pin the glyph at the operator's eyes in a real 30-col pane before
landing; ASCII `#` is the zero-risk fallback (U07 §6a).

### C13 · `scripts/lib/cc-tui.sh` (new, ~150 lines, U08 §4) — the ONE pane transport

`cc_tui_type <pane> <file>` (`kitty @ send-text --match id:N --bracketed-paste=enable --from-file`,
after `kitty @ ls --match id:N` proves existence — `send-text` rc is a constant 0),
`cc_tui_clear <pane>` (`composer_scrub_verified` lifted verbatim from `HF:2491-2517`: `\x15` rounds
with read-back, never ESC — ESC interrupts a running turn — never `send-key` — encodes in the kitty
keyboard protocol CC pushed, which is the `^[[117;5u` the operator saw, U08 §3c), and
`cc_tui_submit_verified <pane> <file> <transcript> <token>` with the six-state rc contract
(0 submitted-and-recorded · 1 send failed · 2 abstained · 3 held-draft · 4 mangled-scrubbed ·
5 cannot-tell). Used by `cc-lr repair --from SUBMITTED` and by C7's re-send; `bin/it2-kitty` gains
`session tui-submit` as the single seam; `bin/cc-pane send` is documented UNAVAILABLE on kitty until
it grows a kitty driver (its text path is iTerm2 AppleScript, and iTerm2 is not running — U08 §3a).

### C14 · `commands/limit-recover.md` — front section + ingest fast path

`/limit-recover <ref>` ⇒ `cc-lr <ref>`, print, END THE TURN; `/limit-recover` with an image ⇒ read
the `⌗<pane> <sid8>` off the statusline (or the tuple, refusing on ambiguity), then the same.
`Mode: ingest` step 1's seven identity assertions become `lr-ingest-verify.sh` (U12 §2 — every one is
a shell predicate); the spec requires ONE Bash call when it does run (U12 §7.4).

### C15 · Tests

`tests/cc-lr-resolve.bats` (pane / sid8 / tuple-refuses-on-tie / kitty-timeout-degrades) ·
`tests/cc-lr-state.bats` (every edge writes a row; FAILED-* carries evidence; sweep marks a dead
driver) · `tests/lr-relaunch-bound.bats` (U05 T2: watcher attempts ≥ budget — the ratchet that would
have caught today) · `tests/capacity-admit-coverage.bats` +T3 (probe and launcher enable the same
terms) · `tests/lr-submit-probe.bats` (token present / absent / stale-t0) · `tests/account-recovery-
lane.bats` + `tests/lr-fleet-recovery-target.bats` (U13 §5) · `tests/stop-failure-request.bats`
(SF-a…SF-h, U10 §2g). Red-proof discipline per `tests/capacity-admit.bats:22-25`: every case run once
against the unpatched subject and shown to fail.

---

## 4.1 Detachment — why `setsid`, and how the invoking session is never held

`cc-lr` launches `lr-drive.sh` with the 5-line python `detach()` at `handoff-fire.sh:1608-1616`
(`start_new_session=True`, log fd, stdin devnull) lifted into `scripts/lib/detach.sh`. The reason is
recorded at `HF:1600-1607`: Claude Code SIGKILLs a Bash tool call's whole process GROUP when the
call ends, so a `nohup` child dies with it (observed 2×, reproduced). A `setsid` child has its own
pgid and PPID 1 immediately. `cc-lr` then prints and exits; the Bash tool returns in <2 s; there is
no backgrounded park, so `hooks/validate-bash.sh`'s deny of a backgrounded wait under a live `/goal`
(CLAUDE.md § Agent Teams) is never in play.

## 4.2 The file layout

```
~/.reso/limit-recover/
  requests/<sid>.json               existing lane (U10 §2b); written by C4 and by cc-lr; removed at DONE
  requests-latch/<sid>.<death_uuid> new; O_EXCL event latch
  runs/<id>/state.json              {id,sid,pane,state,since,driver_pid,requester_pane,deadline,cause,next}
  runs/<id>/events.jsonl            {ts,from,to,evidence,cause} — append-only, one row per edge
  runs/<id>/resolve.json            C2 output
  runs/<id>/rank.json               ranker stdout + stderr + pick + assign receipt
  runs/<id>/driver.log              lr-drive stdout+stderr (durable — NOT $TMPDIR, which this box wipes at boot: memory e2d8c9816)
  runs/<id>/watcher.log             copied from $TMPDIR/handoff-recycle-*.log at every state change (same reason)
  runs/<id>/.paged                  sweep latch
  runs/latest → <id>
  index.jsonl                       one line per run, upserted: {id,sid,pane,state,ts} — `status` reads this first
  fleet/<RUN>/results.tsv           kept; the driver appends the compat row so lr-fleet --report still works
  <sid>/bundle-<TS>/                unchanged (audit.json, MANIFEST.json, INGEST-VERIFIED.txt)
  locks/<sid>.lock                  unchanged
  parked/ · resumed/ · results/     unchanged; DONE retires parked→resumed
  auto.off                          C4 kill switch
```

Everything a `status` needs is two small files per run plus two `kill -0`s. No transcript is opened
to render status; the transcript is opened only by the probes that prove SUBMITTED and ENGAGED, and
then as a `tail -c 400000` (19 ms).

## 4.3 What the operator sees, step by step

| moment | where | what |
|---|---|---|
| limit hits | the pane | Claude Code's own `You've hit your session limit · resets 2:40pm` |
| +0.3 s (auto on) | nothing visible | C4 wrote the request and kicked the driver; `cc-lr status` already shows `RESOLVED` |
| operator types `cc-lr 117` (or `/limit-recover 117`) | invoking pane | the three lines of §1.2, back in <2 s |
| +3 s | `cc-lr status` | `TRANSPLANTED` — the point of no return, named as such |
| +5–10 s | the recovered pane | `/exit` banner, shell prompt, the typed `cd … && nocorrect bash …lr-launch-…sh` line |
| +12–18 s | the recovered pane | Claude Code boots on the new account; the prompt is typed and submitted; the statusline now reads `(3) ⌗117 cb227486 …` |
| +30–35 s | invoking pane, at its next turn boundary | one mailbox line: `lr-cb227486-…: ENGAGED — pane 117 continues cb227486 on next3 (31 s); nothing owed` |
| failure at any step | invoking pane + desk page + `cc-lr status` | the state, the cause read from the IDL / watcher / pane tail, and the ONE `cc-lr repair <id>` command |

No page on success — a page that fires at every close carries no information (CLAUDE.md § alarm
polarity). A macOS notification on DONE is optional and off by default.

## 4.4 Fault tolerance — every failure named, none a husk

| fault | detected by | state | operator sees | repair |
|---|---|---|---|---|
| ambiguous ref | resolver | `AMBIGUOUS` | candidate table with pane ids + titles | pick a pane id |
| no routable account | ranker rc 2 | `REFUSED-TARGET` | the router's per-account reasons (`recovery-weekly-thin …`) | wait for reset (poller fallback) or `--target` |
| box refuses on headroom/segments/active for 60 s | probe | `REFUSED-ADMIT` | the term and its value | re-run; nothing was moved |
| `lr-fire-resume` capacity refuse (today's 4/4) | IDL join in the watcher, ≤20 s after the type | `FAILED-RELAUNCH` cause `term=load 2.57/core` — but with C5 the load term is off and budget 1 releases on attempt 2, so this becomes a page-and-admit, not a failure | page + `repair` | `cc-lr repair` retypes via C13 |
| launcher parser skew (live copy behind) | `lr-handoff.sh:496-509` preflight, BEFORE transplant | `REFUSED-BUNDLE` exit 5 | the missing flag | deploy-live, re-run |
| pane never reaches a shell (held draft, modal) | watcher `:6605-6691` nudges | `EXITING +Ns` then `FAILED-EXIT` at 600 s | the composer text / dialog | a human answers the pane; `repair --from EXITED` |
| pane vanished after `/exit` | watcher `:6698` | `FAILED-PANE-GONE` | — | `repair --replace` → `lr-handoff --launch` split beside (existing `LRH_REPLACE` path, `lr-handoff.sh:636-644`) |
| READY never seen / prompt not typed | C6 quiet-pty fallback, then `✗ READY NEVER SEEN`, exit 12 | `FAILED-SUBMIT` | the prompt text | `repair --from SUBMITTED` = `cc_tui_submit_verified` |
| prompt typed, not submitted (today's pane 111) | `lr-submit-probe` no user record in 30 s | `FAILED-SUBMIT` | — | same |
| submitted, no assistant turn in 180 s | `resume_engaged` after the SUBMITTED ts | `FAILED-ENGAGE` | the transcript tail | `repair --from SUBMITTED` re-sends only if the transcript shows the composer idle (never interrupt a running turn — `HF:6861-6866`'s rule stands) |
| driver itself dies | `status --sweep` (`kill -0 driver_pid` false, no terminal row) | `FAILED-DRIVER-DIED` | last state + `driver.log` | `repair --from <last state>` |
| re-limit on the target | `resume_engaged` excludes `isApiErrorMessage`; a new StopFailure on the target writes a NEW request (new death uuid) | `FAILED-ENGAGE` + a fresh `DETECTED` | both runs in `status` | automatic if `auto` on (C9's survival floors make this rare: 9 h of headroom at the worst measured burn, U13 §3b) |
| kitty socket timeout mid-run | every `kitty @` bounded at 2 s, INDETERMINATE never "gone" | the step retries once, then names it | — | `repair` |
| teammate / fired-peer session | C4 classification | `teammate-skip/<sid>` (lead-owned) · fired peer recovered in place and the ORIGINATOR is paged on failure (U10 §3b) | — | — |

## 5. Acceptance — the 5-session drill (`tests/drills/lr-five-session-drill.sh`)

Runs on the live box, operator-launched (it spends quota and types into panes; never from a Bash
tool under a live goal). Five throwaway sessions on one account, each driven to a real `rate_limit`
StopFailure via `CC_ADMIT_LOADAVG_OVERRIDE`-style seams where possible and a real cap where not; three
in `claude-infrastructure`, two in worktrees (the regime the n=1 E2E never reached — U09 gap #17);
one with an in-flight subagent; the box under a background `bats` suite so load reads >2.0/core
(today's regime, U11 §4).

| # | assertion | expected | today |
|---|---|---|---|
| 1 | `cc-lr find <pane>` for each of the 5 | ≤ 0.3 s each, exact | 40–86 s census, 4-way ambiguous |
| 2 | `cc-lr find '<statusline text>'` for the 2 that collide on cwd | **refuses**, lists both with pane ids | picks or guesses |
| 3 | `cc-lr <pane>` ×5 back-to-back | each returns ≤ 2 s; 5 distinct ids; 5 driver pids with PPID 1 | 2.5 min each, serial, blocking |
| 4 | targets | no two Fable sessions on the same account inside one 90 s TTL unless it is the only survivor; every pick has a `rank.json` with stderr | 2 Fable → `next` @98 % |
| 5 | `TRANSPLANTED` for all 5 | ≤ 5 s after fire | — |
| 6 | `SUBMITTED` for all 5, by transcript record | 5/5 | 1/5 auto, 2/5 by hand, 2/5 never |
| 7 | `ENGAGED` for all 5 | p50 ≤ 45 s, max ≤ 180 s, wall for all five ≤ max(single) + 10 s | 115–158 s each, 1/5 verified |
| 8 | husks | **0** panes at a bare shell over a transplanted sid | 4/5 |
| 9 | `handoffs.jsonl` | 5 intent rows, 5 submitted rows, 5 engaged rows, 0 dangling | 4 dangling intents |
| 10 | IDL | 0 `caller=lr-fire-resume term=load` refusals | 8 |
| 11 | invoking session | 1 tool call per fire, turn ends ≤ 5 s after; the wake arrives as a mailbox line, not a poll | 24.4 min polling |
| 12 | recovered sessions' first turn | ≤ 1 model round trip, ≤ 0.2 K resident tokens added, `gaps_at_handoff:0` honoured | 6–9 round trips, ~26 K resident |
| 13 | mutation arm A: launcher env `CC_ADMIT_LOADAVG_OVERRIDE=99 CC_ADMIT_LOAD_TERM=on` on one session | attempt 1 refuses, attempt 2 admits + pages (`basis:budget-expired`), run reaches ENGAGED; `status` shows the refusal as CAUSE history | husk |
| 14 | mutation arm B: `LR_RE_READY` set to a phrase that never renders | quiet-pty fallback injects; SUBMITTED via transcript; if the token never appears, `FAILED-SUBMIT` named ≤ 40 s after RELAUNCHED and `repair --from SUBMITTED` succeeds | silent idle forever |
| 15 | mutation arm C: `kill -9` the driver after TRANSPLANTED | `status --sweep` marks `FAILED-DRIVER-DIED` on the next tick, pages once, `repair` completes the run | invisible |
| 16 | mutation arm D: kitty socket replaced by a sleeping listener for one resolver call | `find` answers from the registry in ≤ 2.2 s with `liveness: unverified-kitty-timeout` | 10 s hang + corrupt payload |
| 17 | `cc-lr status` with all 5 terminal | one read of `index.jsonl` + 5 `state.json`, ≤ 0.1 s, every row shows DONE and its elapsed | — |

Pass = every row; the drill writes its own `results.tsv` and the numbers above are the DoD.

## 6. What this design deliberately does NOT change, and why

- **`lr-transplant.sh`** — 0.45 s, sha-verified, lock + tombstone semantics are what admit a
  third-party driver to type into a pane it does not own (`lr-handoff.sh:605-611`). Sound (U02 §1).
- **`lr-audit.py`** — 5–7 s is noise (U12 §1); the fast path only adds `--ledger-only` (0.13 s).
- **The recycle exemption at `handoff-fire.sh:8270`** — correct: a recycle is net-zero panes. The
  defect was the SECOND gate in the launcher, which C5 now parameterises (U05 §0).
- **`hooks/handed-off-session-guard.sh`** — the husk's only voice; stays as the enforcing store.
- **`S_CUT 0.85`, `KMAX 8`, `CC_ADMIT_ACTIVE_CEILING 8`, `CC_ADMIT_MAX_SEGMENT_PCT 50`** — not
  touched; `capacity-admit.sh:790-800` forbids moving 8 as an arithmetic consequence (U05 §7.3), and
  U13 shows `RECOVERY_S_CEIL 0.60` is TIGHTER than `S_CUT`, not a loosening.
- **`HF_RECYCLE_SHELL_WAIT_S` 600 and `CC_RECYCLE_DRAFT_WAIT` 180** — the composer-draft gate exists
  so an operator's half-typed message is never `/exit`ed over (U04 F2); only the poll quantum moves.
- **The as-is resume default** (`LR_ASIS`) and the read-back `answer_menu` that parks rather than
  guesses (`lr-fire-resume.sh:501-503`) — both are protections, not costs.
- **The reset-wait arm of the poller** — it is the correct fallback when `--recovery` finds no
  survivor; it just stops being the FIRST branch (U06 §5 A).
- **The U05 P2 admission token** — deferred, with the reason stated: after P1 the residual split is a
  headroom/segments/active flip inside the 11–16 s between probe and launcher; headroom has fired 0
  times in 55 refusals, segments only on boot-resume, and net-zero removes active's double count. A
  new `basis` vocabulary and a new one-shot file class for a residual with no observed instance is
  not earned yet; T1 stays written for when it is.
- **`lr-preseed-env.sh`'s iTerm2 half** — dead code on kitty, harmless (U03 §3); not worth a diff.
- **`cc-sessions`** (30–41 s, no sid column) — not fixed, just not used (U07 §0).
- **kitty `user_vars` via OSC 1337** — a free registry-independent index (U07 §5), left as a later
  belt; the registry is 400× faster and is rewritten on every SessionStart.
- **No new terminal transport.** Everything types through `kitty @ send-text`; `send-key` and the
  iTerm2 AppleScript path are banned by measurement (U08 §3).
- **No new hook registration and no `settings.json` edit** — both are c10; C4 rides the hook that is
  already registered in all five config dirs.

## 7. Risks, stated

1. **`session_name` and `rate_limits` presence in the live statusline payload is a GUESS** (U07 §7,
   extracted from the binary, not captured). One-line falsifier before depending on it: add the field
   to the telemetry `jq` and read the next row back.
2. **`statusline.sh` is copy-deployed** — a landed C12 is inert until `install.sh` runs; the parity
   auditor will not see the divergence (U07 §1). The land must carry the converge.
3. **`CC_ADMIT_BUDGET=1` in the launcher lowers this caller's bound** by one refusal; the page on
   `budget-expired` is what keeps that visible (U04 §5 A residual).
4. **Whether `StopFailure` fires inside an Agent-Teams assignee** is unmeasured (0 of 10 marker sids
   were teammates, U10 §3c); SF-e is the fixture that must establish it before C4 is trusted there.
5. **`quotaLimits` on weekly / Fable-scoped caps is unobserved** (all five today were `five_hour`,
   U10 §4); the resolver falls back to the prose regex when the block is absent.
6. **The recovery-lane burn floor is calibrated on one 2.43 h window, n=4** (U13 §6); re-derive
   before quoting, and expect a cold-context first hour to burn faster than the 0.39 pp/h median.
7. **`gaps > 0` transplants were never observed today** (U12 §5); the ingest fast path is gated on
   `gaps_at_handoff == 0` by construction and the full ingest remains the other branch — untested
   here.
8. **A `repair --from SUBMITTED` can only re-send when the composer is provably idle**; a session
   genuinely mid-turn with a slow first response reads the same as a stranded prompt for up to 180 s.
   The state store shows `ENGAGING +Ns` so the operator is not tempted to type into it.
9. **C11 (`WatchPaths`) is an operator step**; until it lands the direct kick in C4 is the only
   sub-second path, and it is agent-initiated `cc-lr` from a hook — bounded by the event latch and
   the `auto.off` switch, but new.

## 8. Order of landing (each wave independently green and shippable)

1. **W1 — stop making husks**: C5 launcher exports + C7 `:6878` row/alarm + C7 attempt loop + C8
   `lf_capacity_wait` load-off + T2/T3 ratchets. Converts today's 4/5 to 5/5 with no new files.
2. **W2 — prove the submit**: C6 + `lr-submit-probe.sh` + C7 `recycle-submitted` + the non-slash
   fast-path prompt (C5/U12). Makes RECOVERED mean what it says.
3. **W3 — one command**: C1 + C2 + C3 + the state store + C13 + `status`/`repair` + C15.
4. **W4 — instant**: C4 arm 2 + C10 poller changes + C12 statusline + C11 staged.
5. **W5 — target right**: C9 + C8 `lf_pick_target`.

W1 is ~40 lines and removes the whole failure class the operator saw; W3 is the operator's ask.
