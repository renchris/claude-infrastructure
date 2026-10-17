# Slot B — resume-debt resurrection of a retired teammate (5423f92a, 2026-10-16)

Seam: lr-upgrade.sh relaunch stage → bin/cc-resume-debt settle → scripts/boot-resume-launch.sh →
bin/reso-resume-one. Question: why did the post-upgrade relaunch path bring back a session its lead
had just retired? READ-ONLY investigation; nothing was run that moves or types into a session.

Times are CDT (UTC-5) unless suffixed Z. Epoch conversions measured with `TZ=America/Chicago date -r`.

## 1. Timeline, each line quoted from a store

| CDT | Event | Quote / source |
|---|---|---|
| 18:24:39 | handoff-fire opens the close debt (debt #1) | custody `~/.claude/autonomy/resume-debt/577d9d5d6231745abaa2cc1d7a1c998e.jsonl`: `{"ts":"2026-10-16T23:24:39Z","kind":"open",...,"targetPane":"217","marker":"resume:5423f92a-...:1792193079",...,"provenance":"handoff-fire --recycle: recycle of pane 217 (resume-launcher, same sid) about to type /exit"}` |
| 18:24:48–51 | relaunch typed into pane 217 | watcher log `/var/folders/.../handoff-recycle-217-1792193062-zkcn0b.log`: `2026-10-16T23:24:48Z type-attempt pane=217 ... verdict=submitted` |
| 18:24:54 | new pid registered **as a teammate** | `~/.claude/logs/lead-crash-watchdog.log:62503`: `registered session=5423f92a-... pid=80169 tty=ttys027 pane=217 teammate=web-next16@session-3cbb68e5` |
| 18:25:15 | recycle ENGAGED | `~/.claude/logs/handoffs.jsonl`: `{"ts":"2026-10-16T23:25:15Z","class":"recycle-engaged","gate":"recycle","engaged":true,"target_pane":"217","prev_sid":"5423f92a-...","detail":"recycled in place; engagement by process (no-prompt relaunch) within 15s",...}`; watcher log: `→ relaunched + ENGAGEMENT CONFIRMED BY PROCESS in 217 (--resume 5423f92a alive 15s past boot; no prompt by design)` / `→ resume-debt discharge: rc 0` |
| 18:25:17 | **debt #1 DISCHARGED — the upgrade succeeded** | custody: `{"ts":"2026-10-16T23:25:17Z","kind":"return",...,"marker":"resume:5423f92a-...:1792193079",...,"why":"recycle engaged in pane 217"}` |
| (handoff-fire) | --await verdict carried back to lr-upgrade | run dir `handoff-fire.log` last line: `→ recycle VERIFIED: → relaunched + ENGAGEMENT CONFIRMED BY PROCESS in 217 ...` |
| 18:25:38 | lead's shutdown_request lands in the teammate transcript | transcript tail (jq of `5423f92a-...jsonl`): `{"t":"2026-10-16T23:25:38.198Z","type":"user","c":"<teammate-message teammate_id=\"team-lead\">\n{\"type\":\"shutdown_request\",\"requestId\":\"shutdown-1792193137331@web-next16\",\"from\":\"team-lead\",\"reason\":\"WEB-14 verifi..."}` — no assistant record after it |
| 18:25:43 | SessionEnd tombstone (neutral: reason=other) | `~/.claude/autonomy/shutdown-tombstones/5423f92a-....json` (mtime `18:25:43 1792193143`): `"pid": 80169, ... "endedAt": 1792193143, "endReason": "other", "hostShutdown": false` |
| 18:25:45 | pid 80169 exits 0, HUP, pane 217 gone | `~/.claude/logs/close-records/80169-1792193092.json`: `"ended_at":"2026-10-16T23:25:45Z","exit_code":0,...,"sig_reached_wrapper":"HUP"` |
| 18:26:00 | **watchdog verdict RECYCLE/retired-teammate, machine-readable** | `~/.claude/logs/claude-crashes.jsonl:5827`: `{"ts":"2026-10-16T23:26:00Z","sid":"5423f92a-...","pid":80169,"class":"RECYCLE","cause":"retired-teammate",...,"exit_code":"0",...}`; watchdog log 62510: `death class=RECYCLE cause=retired-teammate (784KB/201recs ...)` |
| 18:26:10 | lr-upgrade leaves `fire`, enters `relaunch` | run `events.jsonl`: `"stage":"fire","detail":"outcome=ok dur_s=114 ..."` at `23:26:10Z` |
| 18:26:11 | --relaunch-at-shell refused, pane absent | `relaunch-at-shell.1.log`: `!! --relaunch-at-shell REFUSED: REMOTE-PANE-ABSENT ... Nothing was typed.` / `verdict: REFUSED:pane:absent` (lock record `hf-43557-1792193171` = 18:26:11) |
| 18:26:20 | **cc-resume-debt settle re-opens a debt on the retired sid (debt #2)** | custody: `{"ts":"2026-10-16T23:26:20Z","kind":"open",...,"originatorPane":"daemon:settle (no prior debt)","targetPane":"-","marker":"resume:5423f92a-...:1792193180",...}`; `recon/launch.log`: `1792193180 5423f92a-... cc-resume-debt taken pid=45752` / `1792193180 ... boot-resume-launch inherited pid=53834` |
| 18:26:20 | fence and holder checks pass | `~/.claude/autonomy/resume-debt/log/5423f92a-....log`: `lr-recon-fence: verdict=act sid=5423f92a reason=not-owned` ×2, `gate=act ... role=cc-resume-debt lock=taken`, `gate=act ... role=boot-resume-launch lock=inherited`, `boot-resume-launch: capacity-admit: ADMIT (budget expired after 3 consecutive refusals) — load 33.51 ...` |
| 18:26:23 | NEW kitty OS window | `~/.claude/logs/pane-spawns.jsonl`: `{"ts":"2026-10-16T23:26:23Z","surface":"os-window","backend":"kitty","caller":"boot-resume-launch.sh","pid":53834,"ppid":45752,...,"chain":"lr-reset-poller.sh>boot-resume-launch.sh","ancestry":"53834:bash>45752:bash>43997:bash>1:launchd",...,"detail":"boot-resume-launch resume sid:5423f92a-..."}`; `recon/launch.log`: `1792193184 ... reso-resume-one taken pid=56454` |
| 18:26:27 | resurrected pid registered **without team identity** | watchdog log 62517: `registered session=5423f92a-... pid=57630 tty=ttys027 pane=220` (no `teammate=` field, unlike 62503) |
| 18:26:52 | debt #2 "proven", lr-upgrade writes `upgraded` | meta `resume-debt/meta/5423f92a-....json` events: `opened by settle (no prior debt)` @1792193180 → `relaunch rc=0` @1792193183 → `proven LIVE by cc-find` @1792193212; run events: `"stage":"relaunch","detail":"outcome=ok dur_s=42 ... reason=relaunched in a NEW window by cc-resume-debt (pane 217 left at a shell; --relaunch-at-shell REFUSED:pane:absent REFUSED (rc 5; ...)); proven LIVE by cc-resume-debt"` |

Key ordering facts (all measured from the quotes above):
- The upgrade had already **succeeded and been discharged** (18:25:17) 63 s before settle re-opened a debt (18:26:20).
- The machine-readable retired-teammate verdict (claude-crashes.jsonl:5827, 18:26:00) existed **20 s before**
  cc-resume-debt took the sid (18:26:20). Nothing in the relaunch path reads that file.
- The teammate's own transcript held the shutdown_request record from 18:25:38, **42 s before** the take.

## 2. Code path, with the defect at each hop

### 2.1 lr-upgrade.sh — engaged-then-ended is read as "relaunch failed"

- `scripts/limit-recover/lr-upgrade.sh:2671-2674` runs handoff-fire `--recycle ... --await` and captures `hrc`.
  `--await` returns 0 only on `ENGAGEMENT CONFIRMED` in the watcher log (`scripts/handoff-fire.sh:18938-18947`,
  `recycle_await_verdict`). The run's `handoff-fire.log` ends `→ recycle VERIFIED`, so hrc was 0 (UNVERIFIED as a
  literal exit status: the drive does not log hrc on this branch; inferred from the VERIFIED line and `fire outcome=ok`).
- `lr-upgrade.sh:2677`: `if [ "$hrc" = 0 ] && lru_resumed_on ... && lru_proven ...; then` — the only branch that
  honours hrc=0. It fell through. Whichever conjunct failed, by the time of the next reads pid 80169 was dead (18:25:45).
- `lr-upgrade.sh:2683-2721` (step 6 "NOT ENGAGED") **never consults hrc again**. With the old pid gone (`kill -0` false
  at 2685 and 2695) it reaches `lr-upgrade.sh:2710` `if ! lru_resumed_on "$sid" ...; then` → `lru_step relaunch`
  (2711) → `lru_relaunch_gated` (2712; defined 2228) → REFUSED:pane:absent → `*)` arm → `lru_settle_verdict`
  (2718; defined 2012) → `lru_settle` (1993) → `lru_rd settle --sid "$1"` (1996).
  The comment at 2683 calls this branch "NOT ENGAGED", but the session WAS engaged; the code cannot tell
  "never came up" from "came up, was proven by the watcher, then ended on purpose".
- The teammate's "should this exist?" check exists only at census time: `lru_teammate_block`
  (`lr-upgrade.sh:420-439`, called at 699) refuses `teammate-shutdown-pending` when the inbox holds an UNREAD
  shutdown_request. At census (18:24:13) none had been sent (sent 18:25:37). It is not re-run before settle.
- The drive's own launcher author knew this outcome is normal: `lr-upgrade.sh:1844-1847`: "a member's turn ends in the
  harness's idle notification, which woke its lead, and the lead shut the upgraded member down; a member idling also
  arms the house reaper (teammate-auto-shutdown.sh)".
- Team identity is dropped by the fallback: `lr-upgrade.sh:383-385` documents that a teammate relaunched WITHOUT its
  `--agent-id/--agent-name/--team-name` flags and the team env "comes back as a plain session, outside the team".
  The drive's own launcher carries them (`launch.sh`: `--extra-args --agent-id\ web-next16@session-3cbb68e5 ...
  --extra-env CLAUDECODE=1\ CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`); the cc-resume-debt path below never does.

### 2.2 bin/cc-resume-debt — a PROVEN debt is treated as "no prior debt"

- `bin/cc-resume-debt:676-683` (`_settle`):
  ```
  if [ ! -f "$(_meta "$1")" ] || ! _active "$(_get "$1" state)"; then
    [ "$BY" = unknown ] && BY="settle (no prior debt)"
    _open >/dev/null || ...
  ```
  `_active` (`:126`) is `open|retrying|escalated`, so a debt in state `proven` (discharged 63 s earlier by the
  watcher: "recycle engaged in pane 217") counts as **no debt** and is re-opened. The comment at 678-680 justifies the
  re-open for "an older mover closed it, or its open failed" — neither was true here; the mover's debt existed and had
  been PAID.
- `_open` (`:277-312`) overwrites `meta/<sid>.json` wholesale (`> "$cur.tmp.$$" && mv -f` at 312), so debt #1's
  `proven` history is erased from the meta (only the custody jsonl keeps it — see the 18:24:39/18:25:17 rows).
- `_settle` then calls `_step "$1" 1` (now-flag 1): `:664` `{ [ "$2" -eq 0 ] && _recycle_wait "$1"; } || _relaunch "$1"`
  skips both GRACE and the recycle-wait, so the relaunch ran 3 s after the open (meta: open @1792193180, relaunch
  @1792193183).
- `_relaunch` (`:464-517`) asks exactly two questions before typing: the reconciler fence (`:469`, verdict
  `act reason=not-owned`) and H(sid) live holders (`:473`, 0 because the session was dead). **There is no
  retirement / teammate / teardown-marker / crash-verdict check anywhere in cc-resume-debt** (grep for
  `retire|teardown|tomb|teammate|teamName` in bin/cc-resume-debt: no hit other than the unrelated `.HANDOFF`-free text).
  It then runs `CC_RESUME_DEBT_SETTLING=1 $RELAUNCH "$acct" "$cwd" "$1"` (`:509`) — account, cwd, sid only; no
  team identity can travel this interface.
- Header contract (`:5-10`): "Unproven ⇒ one retry in a NEW window with the SAME session id". The store is designed
  for customer sessions that a mover closed; it has no notion of a session whose owner ended it after the proof.

### 2.3 scripts/boot-resume-launch.sh — ownership questions, no "should it exist?"

- The "ONE TYPER PER SESSION" block (`:288-339`) asks three things: PARKED-REBOOT (`:300-311`), the recon fence
  (`:316`, here `inherited` from cc-resume-debt), and H(sid) empty (`:328-332`). `--check-only` exits after these
  (`:339`). None asks whether the session retired on purpose. (grep `retire|teardown|tomb|teammate` in the file:
  only an unrelated comment at :125.)
- The skip-retired logic lives one layer UP, in the orchestrator `scripts/boot-resume.sh:710-830`, which
  cc-resume-debt bypasses by calling the launcher seam directly.

### 2.4 bin/reso-resume-one — refusals are all about the environment

- Its refusals (`bin/reso-resume-one:478-575`, `rr_refused_exit`) concern the worktree, binary, model config, account
  alias, capacity, and the kitty fullscreen guard (`:1025-1039`). No retirement check, and no team flags at all
  (grep `agent-name|agent-id|team-name|AGENT_TEAMS|teammate` in bin/reso-resume-one, boot-resume-launch.sh,
  cc-resume-debt: no hit). Therefore any teammate this path resumes is, by construction, an orphan outside its team
  — confirmed by watchdog log 62517 (`pane=220`, no `teammate=`).

## 3. Why the existing guards did not fire

1. **boot-resume.sh skip-retired** (`scripts/boot-resume.sh:710-830`; tests/boot-resume-skip-retired.bats):
   - Not on this path: it runs only inside boot-resume.sh; cc-resume-debt → boot-resume-launch.sh skips the
     orchestrator entirely.
   - Even if consulted it would have said "keep": its evidence is `$CC_TEARDOWN_DIR/<sid>.json`
     (`:723`, `retired_marker` `:739-748`), and **no marker exists for this sid** (measured:
     `ls ~/.claude/watchdog/teardown/ | grep 5423` → nothing). The vendor teammate-retirement path (lead
     shutdown_request → pane closed) writes none. Its jq also accepts only `mode == terminal|successor|recycle(v2)`
     (`:744-745`), so a `teammate-idle` marker from `hooks/teammate-auto-shutdown.sh:239-255` would be ignored too —
     and that hook was CANCELLED at its 5000 ms timeout at 18:19:39 (brief; not re-verified here).
2. **lead-crash-watchdog RECYCLE/retired-teammate** (`hooks/lead-crash-watchdog.sh:534-539` `retired_teammate`,
   `:784-785`, `:809-813` classifier arm, `:1413`/`:1433` advice "there is nothing to recover or re-spawn",
   `:1701-1724` paint): it is an **observer**. Its only machine-readable output is the appended row in
   `claude-crashes.jsonl` (`:2125`, `:2201-2203`), plus a pane paint that was skipped (`pane verdict NOT PAINTED — the
   pane closed`, log 62511). No relaunch actor reads claude-crashes.jsonl: its readers are `bin/cc-husk-sweep:75` and
   `bin/cc-crash-report:23` only (grep `claude-crashes.jsonl` across bin/ scripts/ lib/). It is also asynchronous (the
   daemon polls; `sleep 30` near `:2121`), so even a reader would race it in general; here it won by 20 s.
3. **cc-husk-sweep TEAMMATE rule** (`bin/cc-husk-sweep:48-49`, `is_teammate` `:338-342`: transcript carries
   `"teamName":"…"`) already states the policy this incident violated — "a retired Agent Teams member; its lead owns it,
   and resuming it re-spawns a member nobody will shut down" — but lives only in cc-husk-sweep.
4. **lr-upgrade `lru_teammate_block`** (`lr-upgrade.sh:420-439`): census-time only; the shutdown_request arrived 84 s
   after census. Inbox read only for UNREAD requests; the request had already been delivered into the transcript.
5. **cc-resume-debt / boot-resume-launch fence + H(sid)** (`cc-resume-debt:469,473`; `boot-resume-launch.sh:316,328`):
   they answer "is anyone else typing / holding it?", correctly "no" for a retired, dead session.
6. **lru_retired_source** (`lr-upgrade.sh:974-985`): the `.HANDOFF.json` tombstone is a transplant retirement, not a
   teammate one; irrelevant here.

## 4. Retirement / tombstone stores today — there is no single one

| Store | Env | Writer(s) | Meaning | This sid |
|---|---|---|---|---|
| `~/.claude/watchdog/teardown/<sid>.json` | `CC_TEARDOWN_DIR` | `scripts/handoff-fire.sh:9021` (self-close terminal/successor/recycle), `bin/cc-teardown:259`, `hooks/teammate-auto-shutdown.sh:239-255` (mode teammate-idle) | pre-exit INTENT to close | **absent** |
| `~/.claude/autonomy/shutdown-tombstones/<sid>.json` | `CC_SHUTDOWN_TOMB_DIR` | `hooks/session-deregister.sh:79-98` on SessionEnd reason=other | "it ended" (shutdown OR pane close; explicitly not a retirement, boot-resume.sh:649-650) | present, 18:25:43, endReason other |
| `~/.claude/logs/claude-crashes.jsonl` | — | `hooks/lead-crash-watchdog.sh:2201-2203` | after-the-fact class/cause incl. `RECYCLE retired-teammate` | row 5827, 18:26:00 |
| `<transcript>.HANDOFF.json` | — | lr-transplant | retired SOURCE of a transplant | n/a |
| transcript `"teamName"` / `<teammate-message>` shutdown_request | — | Claude Code | raw facts both the watchdog and cc-husk-sweep derive from | present |

So the answer to "is there a single retirement store and who writes it?" is **no**: three stores with different
semantics, plus two derived predicates (`retired_teammate`, `is_teammate`) in two different files, and none is
consulted by cc-resume-debt, boot-resume-launch.sh or reso-resume-one.

## 5. Every point where a "should this session still exist?" check could/should happen

1. `lr-upgrade.sh:2683-2721` — before step 6 settles: if hrc=0 (watcher-verified engagement) or the recycle-engaged
   row / discharged debt exists after `t0`, the session WAS upgraded; a missing process now is a post-upgrade end,
   not a failed relaunch. Verdict should be `upgraded` (ended after proof), never settle.
2. `lr-upgrade.sh:2710` / `lru_relaunch_gated:2228` — re-run the teammate gate (shutdown_request in inbox OR in
   transcript after t0; `retired_teammate`) before any relaunch.
3. `bin/cc-resume-debt:681` (`_settle`) — a `proven` debt is not "no debt": do not re-open a debt that was discharged
   after the caller's close (needs the caller's t0 or a freshness window).
4. `bin/cc-resume-debt:464` (`_relaunch`) — refuse (abandon with a reason, not escalate) when the sid is an Agent
   Teams member (this interface cannot carry team flags) or retired on purpose.
5. `scripts/boot-resume-launch.sh:288-339` — add the same question as a 4th ownership check so `--check-only`,
   cc-resume-debt, boot-resume.sh and any operator `cc-do` row all inherit it (exit 5 "not ours to launch").
6. `bin/reso-resume-one` — last line of defence only; better kept dumb.

## 6. Fix candidates (no ranking requested; each with its seam)

- **F1 (lr-upgrade, the trigger):** at `lr-upgrade.sh:2683`, carry hrc/engagement forward: when hrc=0 or a
  `recycle-engaged` row with `prev_sid==sid` and `ts>=t0` exists, never call `lru_relaunch_gated`/`lru_settle_verdict`;
  write `upgraded` with "engaged at <ts>, ended at <ts> after the upgrade (<retired-teammate|closed>)". Test: fixture
  where handoff-fire returns 0 and the resumed pid is gone by the prove — assert no `settle` call.
- **F2 (cc-resume-debt `_settle`, the amplifier):** treat `proven` as proven: `_settle` returns 0 with note
  "already proven at <epoch>" when the debt is `proven` and its proof epoch is within a freshness window or newer than
  a new `--since <epoch>` the caller passes (lr-upgrade passes its `t0`). Keep the re-open only for missing meta /
  `abandoned`. Also stop `_open` from erasing a prior debt's events (append a generation instead).
- **F3 (one shared predicate, the policy):** a single lib (e.g. `lib/session-retired.sh`,
  `cc_session_retired <sid> [cfg] → reason, rc 0`) used by boot-resume.sh, boot-resume-launch.sh (as ownership
  question 4, honoured by `--check-only`), cc-resume-debt `_relaunch`, and lr-upgrade. Ladder: (a) teammate
  transcript (`"teamName":"…"`, `bin/cc-husk-sweep:338-342`) ⇒ never resumable by a team-blind launcher;
  (b) teardown marker newer than last activity (lift `boot-resume.sh:723-748` as-is, and accept `teammate-idle`);
  (c) `retired_teammate` facts from the transcript (lift `teammate_facts`/`retired_teammate` from
  `hooks/lead-crash-watchdog.sh:323-539` into the lib rather than reading the watchdog's async log). In
  cc-resume-debt a retired verdict should `_abandon` with the reason (state `abandoned`, settle rc 4), not escalate.
- **F4 (single tombstone store, the data):** make the retirement durable and synchronous: on
  `RECYCLE retired-teammate`, the watchdog also writes `$CC_TEARDOWN_DIR/<sid>.json` `mode=retired-teammate`; and
  the TeammateIdle/lead shutdown path writes it pre-exit like the other three writers. Readers keep the
  "newer than last activity" discriminator. F3 must not depend solely on F4 (async lag).
- **F5 (tests):** cc-resume-debt.bats — "settle on a debt proven N s ago does not relaunch"; "a teammate transcript
  is abandoned, never relaunched (settle and sweep)". boot-resume-launch.bats — "`--check-only` exits 5 for a teammate
  transcript / a fresh teardown marker". The existing test `tests/cc-resume-debt.bats:281` ("settle with NO prior debt
  opens one ... and relaunches the same sid") pins the current behaviour only for a truly absent meta; add the
  `proven` control beside it.

## 7. UNVERIFIED

- Which conjunct of `lr-upgrade.sh:2677` failed (lru_resumed_on vs lru_proven) and when handoff-fire actually
  returned. The fire stage spans 18:24:16→18:26:10 (114 s); the watcher verified at 18:25:15; pid 80169 lived until
  18:25:45 with a matching registry row (tombstone copy: pid 80169, lstart `Fri Oct 16 23:24:52 2026`), so cc-find
  should have read LIVE in that window. `resume-debt.log` in the run dir is 0 bytes and the drive logs no prove
  result. Either handoff-fire returned after 18:25:45 or the prove failed for a reason not recorded.
- hrc's literal value (inferred 0 from `→ recycle VERIFIED` and `fire outcome=ok`).
- Who/what closed pane 217 with HUP at 18:25:45 though the model never answered the shutdown_request (lead TaskStop,
  vendor pane cleanup, or other) — outside this seam.
- Whether `web-next16` was still in `teams/session-3cbb68e5/config.json` at 18:26:20: the file now holds the leader
  only, but its mtime is 19:24, an hour later.
- The composer junk (XTVERSION/DA1 replies) in the resurrected window — slot D.
