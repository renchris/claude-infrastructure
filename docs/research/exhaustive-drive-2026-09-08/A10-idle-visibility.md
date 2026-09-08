# A10 — Idle visibility: working / idling / needs-you at the pane level

Wave: exhaustive-drive 2026-09-08. Read-only research. Every number below carries the command that
produced it and the population it counts.

---

## Answer first

**The working-vs-idling sensor D8 designed does not need to be built from the process table — it is
already on disk, has been since SESSION_REGISTRY_V2, and covers more of the fleet than the store
D8's successors were reading.** `~/.claude/cc-beats/<sid>.json` carries `kind: "prompt" | "stop"`,
written at both turn boundaries by `hooks/session-beat.sh` in ~2 ms. `kind=="prompt"` means a turn
started and has not ended — that IS `BUSY`. Measured: it covers **25 of 27** live `claude*`
processes against the statusline telemetry's **19 of 27**, and on 11 of 12 panes it called BUSY, the
transcript had been written within 252 s.

**The twelfth pane is the finding.** Pane 614 (`c520f71a`) read `kind=prompt` with a beat age of
3,357 s and a transcript untouched for 2,846 s. Independently: `/tmp/cc-permission-pending/c520f71a…
.json` showed a `Bash` permission prompt pending **2,888 seconds — 48 minutes**. Meanwhile its
*statusline telemetry was 71 s fresh*, so every liveness surface keyed on telemetry age read that
wedged pane as healthy. The three-way disagreement (fresh telemetry · frozen transcript · stale
`prompt` beat · live beacon) is the whole answer to what the operator sees: **within one pane the
three states are visually distinct (spinner / input box / modal); across 27 panes on four displays
nothing aggregates them, and "idle holding a decision" has no renderer at all.**

**And the decision half is worse than unrendered — it is structurally unreachable.** `wrap-ledger`
computes `⛔` only from open class-C packets whose `.session_sid == $SID`
(`scripts/wrap-ledger.sh:900`). Measured: **28 open class-C packets, median age 13 days, p90 50,
max 51 — and exactly 1 has an author session alive right now.** 27 of 28 can never render `⛔`
again for the rest of their lives; they fall into the standing `◆` line that global CLAUDE.md
explicitly labels *"standing, not blocking this close"*.

The oldest of them closes the circle: `f91a9701ed21`, opened **2026-07-18 (51 days)** — *"Pushover
credentials: every page and alarm is currently silent."* The decision that would make idleness
visible is itself invisible for exactly the reason it states.

---

## 1. What the operator actually sees, per state

| state | in the pane | across panes | out of band |
|---|---|---|---|
| **(a) working** | native spinner + "esc to interrupt" + token counter | nothing — no tab title, no badge, no aggregate. `bin/cc-where` exists to *find a lost pane on request*, not to advertise state | nothing |
| **(b) idle, holds a decision** | **nothing.** A class-C packet is a JSON file; the pane shows an ordinary input box | nothing | `◆ N blocked backlog — your call`, counted, in the `OPERATOR ▸` block, at a close, labelled *not blocking this close* |
| **(c) idle, done** | input box | nothing | `✅ SAFE TO CLOSE …` from `hooks/operator-readout.sh:1460`, **only on a `✅` write-turn close** |
| **(d) blocked on a permission modal** | the modal, in that pane only | nothing | one `Purr.aiff` at t=0 (`hooks/notify.sh permission`), then a `lead-supervisor` page at t+2 min → **to the desk session's mailbox**, not to the human |

Measured surface inventory (`LC_ALL=C /usr/bin/grep -rln 'set-title\|setTitle\|badge\|\]1337' bin
scripts hooks`): **2 hits, neither a writer** (`scripts/unattended-path-lint.sh`,
`scripts/banner-storyboard.py`). `grep -c badge ~/.zshrc` → **0**. There is no tab-title or badge
producer anywhere in this repo. `bin/cc-where`'s own header records why that matters: kitty labels a
tab with its *active* pane's title only, and at the 2026-08-07 incident **9 of 21 session panes sat
in non-active tabs** — "invisible AND unnamed, which is indistinguishable from deleted."

### The statusline cannot host the indicator

`~/.claude/statusline.sh` renders: instance glyph · context % · dir (commit) branch* · effort. No
state field. Two independent reasons it is the wrong host:

1. **It only re-renders when Claude Code re-renders it.** Its own header records the measurement:
   *"telemetry AGE is the only liveness signal, and age cannot tell a stalled session from a healthy
   one inside a single long operation: BOTH render zero times (proved 2026-07-14 — a respawn sat
   RUNNING 1h25m with 78m-stale telemetry)."* Live confirmation today: pane 583's telemetry was
   **7,430 s stale** on a demonstrably live pid.
2. **Its payload has no state field.** Keys consumed at `statusline.sh:149-155`: `session_id`, `cwd`,
   `transcript_path`, `model.id`, `effort.level`, `context_window.*`, `exceeds_200k_tokens`. Nothing
   says busy.

### The away-summary is the inverse of what is wanted

`CLAUDE_CODE_ENABLE_AWAY_SUMMARY` (gate `tengu_sedge_lantern`) is a *return-to-pane* recap fired on
terminal focus. Its documented suppression ladder
(`docs/research/recap-prompt-extraction-2026-08-23.md:76-90`) includes **`background work pending`
— `pendingAgents > 0 || pendingWorkflows > 0`**. It is silent in exactly the BUSY state, one line,
in-transcript, focus-triggered only, and kitty focus-event support gates it entirely. It is not a
candidate.

---

## 2. The measurement: 19 live panes, right now

`bash /tmp/a10-beats.sh` — population: every `/tmp/cc-telemetry/*.json` whose `.pid` answers
`kill -0`; beat read from `~/.claude/cc-beats/<sid>.json`.

```
live_panes=19  BUSY(kind=prompt)=13  IDLE(kind=stop)=6  no_beat=0
```

Cross-checked against transcript mtime (`bash /tmp/a10-cross.sh`), sorted by beat age:

| pane | sid8 | kind | beat age | telemetry age | transcript age | cwd |
|---|---|---|---|---|---|---|
| 621 | 34288f07 | prompt | 12 | 0 | 0 | wt-763522029afd |
| 616 | 52e35019 | prompt | 79 | 5 | 28 | claude-infrastructure |
| 615 | b418b97a | prompt | 170 | 25 | 26 | claude-infrastructure |
| 596 | c7543d28 | prompt | 187 | 102 | 102 | wt-8ea3acef7d64 |
| 597 | 21c27691 | prompt | 202 | 1 | 1 | wt-193ae8ddce72 |
| 330 | 001d0654 | prompt | 218 | 7 | 5 | claude-infrastructure (**the desk**) |
| 538 | ad4e751c | prompt | 1113 | 1038 | 252 | hammerspoon-config |
| 620 | 2bf8233b | prompt | 2164 | 52 | 52 | wt-99dbf659930c |
| 595 | 48737dce | prompt | 2174 | 261 | 129 | wt-925d843f6665 |
| 618 | 6e29fee9 | prompt | 2651 | 0 | −1 | wt-9002948eb52c |
| 299 | dfd512c4 | prompt | 3014 | 9 | 8 | lane-infra |
| **614** | **c520f71a** | **prompt** | **3357** | **71** | **2846** | **wt-32d4d093f78a** |
| 578 | b0bf12dc | stop | 10 | 10 | 0 | wt-991fcb666976 |
| 535 | 4cef9278 | stop | 45 | 45 | 35 | wt-da839cd0d89e |
| 314 | 28fea442 | stop | 3236 | 3236 | 1229 | wt-pool-2 |
| 447 | c628947c | stop | 5870 | 2081 | 2672 | personal |
| 46 | 541bd306 | stop | 5873 | 5873 | 1065 | sevenrooms-bridge |
| 583 | a7f30dbb | stop | 11032 | 7430 | 2414 | wt-f4863408f038 |
| 482 | 05b501f4 | stop | 13861 | 10270 | 1345 | personal |

**11 of 12 BUSY panes wrote their transcript within 252 s** — a genuinely-working population. The
outlier, pane 614, is the incident. A long beat age on `kind=prompt` is not noise; it is the signal.

### Sensor coverage — the beat beats the store D8's readers use

`bash /tmp/a10-cov.sh`; population = every live process whose argv[0] basename matches `^claude`.

```
live claude pids=27  covered_by_beat=25  covered_by_telemetry=19  covered_by_neither=2
```

Corroborated by the supervisor's own self-check in `~/.claude/autonomy/supervisor.log`:
`2026-09-08T22:07:43Z self-check BLIND live=27 enum=22 delta=5`. Any pane census keyed on
`/tmp/cc-telemetry` is blind to ~30% of the fleet. The beat store is blind to ~7%.
*(Caveat on the denominator: 27 counts processes whose argv[0] starts with `claude`, which includes
launcher shims; it is an upper bound on sessions, and the ratio is what matters.)*

---

## 3. Two discriminators, measured and FALSIFIED

D8's addenda already falsified the naive process-scan (negative control returned 9, not 0 — all
wake/watchdog infrastructure). Two more, measured here so nobody re-proposes them:

**Claude-process CPU delta.** `bash /tmp/a10-cpudelta.sh`, 19 live pids.

| window | range across 19 panes |
|---|---|
| 10 s | 0–3 s; **11 of 19 burned ≥1 s while idle** |
| 60 s | 0–7 s |

No threshold separates the populations. `ps -o time=` has 1-second resolution and the Claude Code
TUI's idle render loop plus the statusline (0.15–0.37 Hz per pane, its own header) sits on top of
that floor. Load average was 16–22 on 10 cores, which compresses the working end further. **Rejected
— it fails toward IDLE, the dangerous direction.**

**Telemetry freshness.** Refuted by the incident itself: pane 614 was wedged on a permission modal
for 48 minutes with a **71 s** telemetry age. The statusline keeps rendering behind a modal.
**Rejected — it reads HEALTHY in the one state that needs a human.**

**Beat `kind`, with the constraint that is already measured.** `bin/cc-await-ping:954` names the beat
kind field a *"measured-refuted discriminator"* — for a **different question**: distinguishing a
recycle-exit from a still-live sender. A frozen beat from a dead session reads `prompt` forever. That
is exactly the false-BUSY hazard, and the same file already shows the cure: `cc-await-ping:535` uses
`.kind == "prompt"` as a positive signal but **only alongside a seq advance and two reads separated
in time**. So the rule is `kind=="prompt"` AND `(pid,lstart)` still matches — both fields are already
in the beat JSON. Not a hypothesis; the upstream refutation and its remedy are both on disk.

---

## 4. D8 conflated two questions, and only one of them needs a process scan

| | question | truth condition | right sensor |
|---|---|---|---|
| **Q1** | "is this pane working or idling?" — asked mid-flight, out of band, the operator's verbatim first axis | the session is inside a turn | **beat `kind`** — O(1), 92.6% coverage, already deployed |
| **Q2** | "did I leave a backgrounded job running?" — asked at Stop, in-session | a descendant job of mine is executing | the D8 process scan, composed rule + fail-toward-BUSY + sample attached |

D8's design answers Q2. The incident that motivated it — *"Both times the question was asked in the
wake-path session, no close was happening"* — is Q1. At Stop the model is by definition not thinking,
so beat `kind` cannot answer Q2; away from Stop, a descendant scan is blind to a session that is
merely thinking, so the scan cannot answer Q1. **Both are needed. Build Q1 first: it is free,
exact, and already producing.**

This is a correction to `docs/plans/CLOSE_SCANNABILITY_2026-08-23.md` D8 and to backlog
`a3eaa0dc1be2`, whose build order opens with a refactor of `gate-cleanup.sh:69-92`'s kill-scoping
helpers — a genuinely risky change to a `SIGKILL` selector — for the *lower-value* half of the
sensor. That refactor is still correct for Q2; it is no longer step 1.

---

## 5. Why "idle with a decision" has no renderer — and the 51-day loop

`bash /tmp/a10-dec4.sh` over `~/.claude/autonomy/decisions/*.json`:

```
open class-C total=28  with_session_sid=17  author_session_alive_now=1
ages (days): n=28 min=-1 median=13 p90=50 max=51
```

`scripts/wrap-ledger.sh:900` — `[ .[] | select((.session_sid // "") == $sid) ] as $mine`. The `⛔`
rung is by construction the *author session's* rung. Global CLAUDE.md calls `⛔` "the safest rung
measured, at 27.4% failure against `✅`'s 37.2%" and says it "outranks everything". **It is
unreachable for 96% of the standing decision inventory** — not by a bug, by the join key.

That design choice is defensible per-close (a session should not be convicted by a sibling's
question). The consequence is not: nothing else escalates a decision, ever. There is no re-offer,
no aging, no owner. `filed-blocker-is-never-revalidated` in MEMORY.md already names this shape —
"a blocked row is filed once, never re-checked — a dead premise demands action forever" — and here
the premise is *alive* and demands action nobody is shown.

**The closed loop, all four legs measured:**

1. Pane 614 blocked on a permission prompt, **2,888 s** (`/tmp/cc-permission-pending/c520f71a….json`).
2. `lead-supervisor` (running, pid 31716) paged at t+2 min — `~/.claude/autonomy/pages/c520f71a….permpend.notified`, mtime 16:24 vs beacon ts 16:22. **23 such pages fired today**; 114 all-time; the daily trend is 8 → 14 → 22 → 23 over 2026-09-05…08 (`find ~/.claude/autonomy/pages -name '*.permpend.notified' -exec stat -f '%Sm' -t '%Y-%m-%d' {} \;`).
3. `send_page` (`scripts/lead-supervisor.sh:337`) delivers to `PAGE_TO_FILE=~/.claude/cc-roles/desk` = **pane 330 — another Claude session**, with an osascript digest as fallback only when no live desk. The human is not on the primary path.
4. The one channel that *is* the human's — `hooks/push-critical.sh`, wired to the `idle_prompt` /
   `permission_prompt` / `elicitation_dialog` matchers — exits at line 22 because `PUSHOVER_TOKEN`
   is unset. Verified: `env | grep -c PUSHOVER` → 0; `grep -c PUSHOVER ~/.zshenv ~/.zshrc` → 0, 0.
   **The `idle_prompt` matcher registers exactly one hook, and that hook is inert. The idle channel
   delivers nothing today.**
5. The fix is open class-C `f91a9701ed21`, created 2026-07-18 — 51 days — whose author session
   `44f5331d` is long dead, so it renders as one unit inside a counted `◆` line and never as `⛔`.

The product side of the channel is real, so this is a config gap and not a missing feature. From the
2.1.260 binary (`tail -c +181200749 claude.exe | head -c 520`):

```
sendIdleNotification:()=>{tv({message:"Claude is waiting for your input",notificationType:"idle_prompt"}, …)}
```

gated on `getLastInteractionTime` / `isDialogOnScreen` / `hasPendingLoopWakeup` /
`hasArmedQuotaAutoResume` / `getIdleNotifThresholdMs`.

### Four notification types the harness emits and settings.json does not register

Same binary, offset 156692984 — the full `notificationType` enum:

```
["permission_prompt","idle_prompt","auth_success","elicitation_dialog","agent_needs_input",
 "agent_completed","elicitation_url_dialog","worker_permission_prompt","push_notification",
 "computer_use_enter","computer_use_exit","quota_auto_resume_fired","quota_auto_resume_stale","quota_…"]
```

`jq -c '.hooks.Notification' ~/.claude/settings.json` registers exactly three matchers:
`permission_prompt`, `elicitation_dialog`, `idle_prompt`. **Unregistered and free: `agent_needs_input`,
`worker_permission_prompt`, `agent_completed`, `elicitation_url_dialog`** — precisely the
teammate/assignee "needs you" events, in a fleet whose default implementation unit is a dispatched
session. This is a settings-only change (migration class c10), not code.

---

## 6. Build spec

### 6.1 `hooks/lib/session-busy.sh` — three states, and only the third needs a scan

Pure reader, no writes, bash 3.2 + jq, fail-open, mirrors `hooks/lib/cc-beat.sh`'s contract
(empty + non-zero on every miss).

```
sb_state <sid>        → one of: BUSY | IDLE-ARMED | IDLE-DEAF | GONE | UNKNOWN
sb_detail <sid>       → "<state> <age_s> <evidence>"    — evidence is NEVER omitted
sb_busy_jobs [<dir>]  → "<n> <sample-argv>" or empty    — the D8 Q2 scan, separate entry point
```

**BUSY**, in strict order, first match wins:

1. `beat.kind == "prompt"` AND `kill -0 beat.pid` AND `ps -o lstart` under `TZ=UTC` matches
   `beat.lstart` (MEMORY `process-start-time-renders-in-ambient-timezone`) ⇒ **BUSY**, evidence
   `beat:prompt/<age>s`.
2. `sb_busy_jobs` returns non-empty ⇒ **BUSY**, evidence `job:<sample-argv>`. This is the Stop-time
   arm; it is what catches a backgrounded gate after `kind` has flipped to `stop`.

**BUSY-SUSPECT** is not a fourth state, it is a qualifier on BUSY that the renderer must print:
`kind=="prompt"` AND transcript mtime age > `CC_BUSY_SUSPECT_S` (default **900 s**; the incident sat
at 2,846 s and every honest BUSY today was ≤252 s, so 900 s sits ~3.5× above the observed working
population and ~3× below the incident). Evidence line must name the permission beacon when
`/tmp/cc-permission-pending/<sid>.json` exists — that is the resolved cause, and printing it turns a
suspicion into an instruction.

**IDLE-ARMED vs IDLE-DEAF — no process scan required.** Every arm already has an O(1) reader:

| arm | reader that exists today |
|---|---|
| live `/goal` | `hooks/lib/goal-state.sh` `goal_live_condition()` — and `wrap-ledger` already exports `GOAL_SRC`/`GOAL_EVALS`/`GOAL_AGE_MIN` |
| continue sentinel armed | `hooks/lib/continue-sentinel.sh` |
| undrained peer mail | `hooks/lib/mailbox-pending.sh` `mailbox_has_pending <uuid>` |
| open custody debt | `bin/cc-custody` (already folded into the ledger) |

Any one ⇒ **IDLE-ARMED**. None ⇒ **IDLE-DEAF**. Collapsing them re-creates the wake-floor blindness
D8 named. A narrow `cc-await-ping --sid <sid>` process check may be added later; it is **not** step 1,
and if added it must be argv-position-anchored (MEMORY `pgrep-f-matches-agent-briefs`: argv carries
whole briefs and a substring match once selected a live peer for `SIGKILL`).

**Fail direction, stated on purpose.** Unknown ⇒ **BUSY**, and D8's rule that makes that safe is
kept verbatim: *the renderer always names the evidence*. A false BUSY showing `job:caffeinate` or
`beat:prompt/12s` is self-diagnosing in one glance. A false IDLE is silent and actively misleading —
it is the state that told an operator nothing was happening for 48 minutes today. The one exception:
`GONE` (pid dead / lstart mismatch) must never render as BUSY; a frozen beat from a dead session is
the measured false-BUSY (`cc-await-ping:954`), and it is caught by the liveness leg, not by a timeout.

### 6.2 `wrap-ledger` fields, beside `LANDING`

`BUSY` (0|1) · `BUSY_STATE` (BUSY|IDLE-ARMED|IDLE-DEAF|GONE|UNKNOWN) · `BUSY_SRC` (beat|job|scan-error|none) ·
`BUSY_AGE` · `BUSY_SAMPLE` · `BUSY_SUSPECT` (0|1) · `PERMPEND` (0|1) · `PERMPEND_AGE`.
Fail-open exactly like `YOURS`/`BLOCKED`: any failure ⇒ `BUSY_SRC=error`, never a manufactured state
(`scripts/wrap-ledger.sh:756`, the house rule).

**Do not add a rung.** The rung ladder is `⛔ > 📤 > 🔧 > 📦 > 🚀 > 👤 > ✅` and it is MECE against
the disposition table. Busy-ness is orthogonal to it: a session can be BUSY at any rung. A "working"
rung would fire on every turn of every session forever — the alarm-polarity failure. These are
machine fields and a renderer line, not a rung.

### 6.3 `operator-readout` — render where it is silent today, edge not level

Current gate (`hooks/operator-readout.sh:18-27`): fire iff `steps>0 ∨ RUNG=📦 ∨ open-queue>0`, else
the `✅` certificate on a write turn, else silence. The inverse gate is: **when the block would be
empty AND the state is `IDLE-DEAF` AND there is anything owed** — an open class-C packet in this
cwd's project, a live permission beacon, or `👤` steps — say so. Reuse the existing hash-latch
damping (`operator-readout.sh:1380-1394`, TTL 900 s) so an unchanged line re-asserts at most every
15 min, which is the `copy_drift_notice` edge-not-level treatment D8 asked for.

`BUSY-SUSPECT` is the one state that should fire *unconditionally* on an otherwise-empty block,
because it is by definition news:

```
⏳ BUSY 48m with nothing written for 47m — blocked on a permission prompt since 16:22:
   Bash: cd /Users/…/wt-32d4d093f78a && …
```

### 6.4 `/wrap` renders all three axes from the same code

`/wrap` is the operator's typed fallback for the verbatim three-axis question. One renderer, per the
repo's own rule — a second implementation is the rejected alternative in D8 and stays rejected.

### 6.5 The pane-level surface: a `cc-panes` verdict line, not a statusline field

The statusline is disqualified (§1). The right surface is a **pull** command the operator or the desk
runs, rendering one row per live pane from the beat store — 25/27 coverage, zero process scans, and
`bin/cc-where` already owns the "where is that pane" half:

```
PANE  STATE          FOR     NEEDS YOU  WHAT
614   BUSY-SUSPECT   56m     1          permission: Bash (48m)   ▶ focus: cc-where --go c520f71a
330   BUSY            4m     0          desk
482   IDLE-DEAF      3h51m   2          2 open decisions (51d, 29d)
578   IDLE-ARMED      10s    0          goal live
```

`NEEDS YOU` is per-pane and composed from three O(1) reads: permission beacon present · open class-C
packets with that `session_sid` · that session's filed `👤` steps. **This is the surface that makes
"idle with decisions" unmistakable, and it is the only place the 27 orphaned packets can be
re-attached to a pane** — by cwd/project when the author session is dead.

For a genuine push channel there is exactly one measured gap and it is config, not code: the four
unregistered notification matchers in §5, plus the Pushover credentials that decision `f91a9701ed21`
has been waiting 51 days for.

---

## 7. Adversarial pass — what I checked because a hostile reviewer would

- **"Beat `kind` is refuted upstream."** It is — for a *liveness* question, not a *busy* question,
  and the same file uses it positively at line 535. Cured by the `(pid,lstart)` leg. §3.
- **"Your census is keyed on the blind store."** It was, initially. Re-ran against `ps` and found
  27 live vs 19 telemetry vs 25 beat; the supervisor's own `self-check BLIND live=27 enum=22` agrees.
  The beat is the better store, which strengthens rather than weakens the recommendation. §2.
- **"CPU is the obvious discriminator and you assumed it away."** Measured at 10 s and 60 s. Falsified
  both times. §3.
- **"Long `prompt` beats are just lost Stop beats."** Tested against transcript mtime: 11 of 12 BUSY
  panes wrote within 252 s. The one exception is a real 48-minute wedge, independently confirmed by
  the permission beacon. §2.
- **"Maybe the pages already reach the operator."** They fire (23 today) but route to the desk
  *session's* mailbox; the human-facing arm is inert for want of a credential. §5.
- **Not checked:** whether kitty/iTerm2 can be driven to set a per-pane title cheaply enough to host
  a level indicator. `bin/cc-where` proves the addressing exists (`kitty @ focus-window`, the it2
  API); the write path and its cost were not measured. Open question below.

---

## 8. Open questions

1. **Who owns an orphaned class-C packet?** 27 of 28 have no live author. Re-attaching by
   `subject_project` → the newest live pane in that cwd is the obvious answer and is a *policy* call
   about whose close a stranger's question may block. Conviction 65% — below the 90% bar, so it is
   the operator's, and it should be filed with a receipt rather than guessed.
2. **Is a per-pane tab title cheap enough to be a level surface?** Unmeasured. If a `kitty @
   set-tab-title` write costs <10 ms it changes the §6.5 recommendation from pull to push.
3. **The 2 live panes covered by neither store.** Both sensors depend on `jq` being on `PATH`;
   `statusline.sh:55-61` repairs PATH for exactly this reason and `hooks/session-beat.sh` does not.
   That is a one-line fix worth confirming before anyone treats 92.6% as the ceiling.

---

## Appendix — commands

| number | command |
|---|---|
| 19 live panes, 13 BUSY / 6 IDLE | `bash /tmp/a10-beats.sh` |
| beat vs telemetry vs transcript ages | `bash /tmp/a10-cross.sh` |
| 27 / 25 / 19 / 2 coverage | `bash /tmp/a10-cov.sh` |
| CPU delta 10 s and 60 s | `bash /tmp/a10-cpudelta.sh` |
| 28 open class-C, 1 live author, ages | `bash /tmp/a10-dec4.sh` (feeds off `/tmp/a10-open-dec.tsv` from `/tmp/a10-dec2.sh`) |
| 48-minute permission wedge | `jq . /tmp/cc-permission-pending/c520f71a-84f3-4f14-9694-4b929119ec53.json` |
| 23 permission pages today | `find ~/.claude/autonomy/pages -name '*.permpend.notified' -newermt "2026-09-08 00:00:00" \| wc -l` |
| Pushover unset | `env \| grep -c PUSHOVER` · `grep -c PUSHOVER ~/.zshenv ~/.zshrc` |
| notificationType enum | `LC_ALL=C /usr/bin/grep -a -b -o idle_prompt claude.exe` then `tail -c +<off-260> claude.exe \| head -c 520` |
| no tab-title/badge writer | `LC_ALL=C /usr/bin/grep -rln 'set-title\|setTitle\|badge\|\]1337' bin scripts hooks` |
| 50 wrap-ledger fields, 0 busy | `bash scripts/wrap-ledger.sh --machine \| cut -d= -f1` |

**Note on the scratch scripts:** `/tmp/a10-*.sh` are ephemeral and will not survive a reboot. Every
one is ≤25 lines and reconstructible from the table above; the durable claims are the numbers and
their populations, not the scripts.
