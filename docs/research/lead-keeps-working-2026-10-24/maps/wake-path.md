# Wake path: how machinery (not the operator) can wake a stalled lead

Slot: wake-path · decision d610f8473106 goal (f) · read-only investigation, 2026-10-24.
Line numbers are for this worktree (`lead-idle-fix`, HEAD 958b23030) unless a path says otherwise.
"measured" = read from a store with the named command; "estimated" = reasoning, method named.

## 0. Answer in five lines

1. **The cheapest sound path already exists end to end:** `cc-notify <sid> "<text>"` enqueues the line, and
   because the B13 lead had no live watcher, cc-notify then calls `cc-wake`. cc-wake writes one fixed frame into
   Claude Code's own messaging socket. That starts a turn whose UserPromptSubmit drain surfaces the line.
   This was proven on this exact session at 20:27:36Z (§3). `advise_subject` (lead-supervisor.sh:546-563)
   already makes this exact call. It is only wired to the context-fill branch (:1099).
2. **A stopped watcher does not make the session deaf to mail.** With no live watcher, cc-notify takes the socket
   arm (cc-notify:1520-1525). With a live watcher, the watcher's exit wakes the session. There is one hole: a
   **detached** watcher (B13's `cc-await-ping … &` at 08:34:49Z) reads as "armed" but wakes nobody (§4.3).
3. **lead-supervisor reached nobody, not even the operator.** `CC_PAGE_TO=""` in the plist and no
   `~/.claude/cc-roles/desk` file mean `send_page` returns 1 at :415 before cc-notify is called. So there were
   0 notifications, 0 digests and 0 `.notified` markers, and that missing marker is why STALL?/ESCALATED re-fired
   every sweep (§2.2). The incident report's "pages only you" is wrong: it paged no one.
4. **Recommended:** a new `nudge_subject` in lead-supervisor, a sibling of `advise_subject`. It fires when the
   session's last Stop recorded rung ⛔ and either (a) the first ESCALATED of the episode arrives or (b) a STALL?
   arrives while the last readout says ungated scope remains. It is addressed by session id through cc-notify.
   Damping is keyed on the *decision state*, not the idle episode: about 1 nudge per state, then doubling
   back-off, at most 3 per state, at most 3 per sweep. The marker fails closed. No settings or hook-registration
   change is needed (§5).
5. **Not idle-keepalive.** It is structurally shadow (its EXIT trap forces 0, so it can never wake), it carries
   no content, and it fires at most once per gap. Even made live, a content-free wake re-closes ⛔: B13 was woken
   twice by its own watcher timeouts (07:39Z, 08:34Z) and re-closed ⛔ both times (§4.4).

---

## 1. Wake mechanisms that exist today (what makes an idle pane take a turn)

| # | Mechanism | Trigger | Who arms it | Wakes on | Carries content? | Citation |
|---|---|---|---|---|---|---|
| W-a | `mailbox-wake-arm.sh` asyncRewake watcher | Registered on **SessionStart and Stop**, `asyncRewake:true`, timeout 14400 (read-only check of `~/.claude/settings.json`, which `~/.claude-quaternary/settings.json` symlinks to) | The harness, at every Stop (no model action) | Mail. cc-await-ping exits 0, the adapter exits **2** and the harness synthesizes a turn with stderr | Yes: the mail headlines, as stderr (:255-262) | hooks/mailbox-wake-arm.sh:5-11, :154, :234, :245-265 |
| W-b | Model-armed `cc-await-ping` under `run_in_background` | The model runs it | The model | Mail (exit 0) **or timeout (exit 2)**. Either is a task-completion notification, which re-invokes the model | Mail body, or nothing on timeout | bin/cc-await-ping:5-9, :54-58; session-continue.sh:645-648 ("cc-await-ping's timeout exit is itself a task completion, so it also wakes the model") |
| W-c | **Socket wake** `bin/cc-wake`, called by cc-notify | A cc-notify send to a live pane with **no** watcher armed | The sender (any process, including launchd daemons) | Immediately. One fixed `{"type":"user",…,"priority":"next"}` frame goes into `/tmp/cc-socks/<pid>.sock` and is queued as an isMeta prompt | A fixed pointer text. The real line arrives via mailbox-drain | bin/cc-notify:1477-1496, :1520-1525; bin/cc-wake:14-21, :274-307 |
| W-d | Headless stdin wake `cc-wake-headless` | cc-notify to a `surface=headless` row | The sender | A stream-json write | Fixed text | bin/cc-notify:1443-1475, :1505-1519 |
| W-e | `idle-keepalive.sh` | Stop, asyncRewake | The harness | **Never.** SHADOW is structural: `trap 'exit 0' EXIT`, and only exit 2 wakes | n/a (it logs `kind=wake` rows only) | hooks/idle-keepalive.sh:28-31, :37, :39 |
| W-f | session-continue `wake_floor` | Stop, synchronous | n/a | Blocks the Stop once to tell the model to arm W-b. **Stands down** when W-a is registered on Stop with asyncRewake, which it is | Instruction | hooks/session-continue.sh:652-662, :664-680 |

How a woken turn gets the mail: mailbox-drain runs on SessionStart, UserPromptSubmit and PostToolUse
(hooks/mailbox-drain.sh:5-7, :19-31) and surfaces it as `additionalContext` plus a `systemMessage`. A socket
frame is a queued user prompt, so the UserPromptSubmit drain fires on it. That was measured at 20:27:37Z (§3).

Watcher marker semantics, which matter for §4.3. "Armed" means `<key>.watching` is ≤90 s fresh **and** its pid
is alive (hooks/lib/mailbox-pending.sh:314-324). A watcher stamps **every** key of its keyset, pane and session box
alike (bin/cc-await-ping:478-490; keyset: hooks/lib/mailbox-pending.sh:1183-1206). A sid-addressed send therefore
sees a pane-armed watcher correctly. cc-await-ping only PEEKS: it advances no shared cursor (bin/cc-await-ping:227,
:1524), so a watcher that dies never loses mail.

## 2. What lead-supervisor knew about session 666022fd, and why it told no one

### 2.1 IDL rows (measured: `grep 666022fd ~/.claude/autonomy/idl.jsonl | jq …`)

| actor / kind / state | count | first ts | last ts |
|---|---|---|---|
| lead-supervisor page STALL? | 160 | 05:52:52Z | 15:16:05Z |
| lead-supervisor page ESCALATED | 66 | 11:02:47Z | 15:16:05Z |
| lead-supervisor page_escalate | 66 | 11:02:47Z | 15:16:05Z |
| lead-supervisor page PAST-THRESHOLD | 16 | 20:15:37Z | 20:44:56Z |
| lead-supervisor permission_pending | 6 | 18:59:10Z | 19:09:37Z |
| lead-supervisor gc | 1 | 15:38:18Z (telemetry age 21608 s ≥ GC_S 21600) | n/a |
| lead-supervisor subject_advise | 1 | 20:15:41Z (used 75, notify_rc 0, verdict "refused-busy") | n/a |
| cc-inbox-guard undelivered-escalated | 1 | 10:00:50Z: "36 message(s) enqueued to a NOW-DEAD pane (666022fd-…)", phone `push-rc-3` | n/a |
| hook rows (no actor) | 189 | n/a | n/a |

STALL? by hour (measured, same grep piped to `uniq -c`): 05h 5 · 06h 2 · 09h 5 · 10h 20 · 11h 25 · 12h 32 · 13h 30 ·
14h 24 · 15h 17. ESCALATED: 11h 12 · 12h 15 · 13h 16 · 14h 8 · 15h 15. So 153 STALL? rows fall between 09:11Z and
15:16Z, matching the incident report.

Why the first ESCALATED came at 11:02Z and not ~09:26Z (STALL? 09:11Z plus DEADLINE_S 900): the STALL? clock reset
twice. Telemetry was 1846 s stale at 10:09Z, and the transcript was 1832 s stale at 10:47Z (STALL? detail strings).
Yet the transcript holds no timestamped record between 08:38:11Z (`away_summary`) and 18:11:47Z (measured: `jq`
over the transcript for `timestamp` in that window returns one row). So un-timestamped metadata rewrites and a
statusline re-export reset the STALL_S clock without any turn. (Inference from those two reads; the specific
writer was not identified.)

What the supervisor knew from other actors' IDL rows: the rung. operator-readout logs `{rung,steps_total,…}` at
every Stop (hooks/operator-readout.sh:2537-2539). For this session: rung "⛔" at 06:45:03Z, 07:39:49Z and
08:35:10Z, the last Stop before the 10 h idle (measured: `jq 'select(.rung!=null)'` on the grep). **This row is
the cheapest out-of-session rung oracle that exists.** No new writer is needed to learn "⛔".

### 2.2 The page channel was dead, so the operator was never paged either

- The plist environment is `CC_PAGE_TO => ""` (measured: `plutil -p ~/Library/LaunchAgents/com.claude.lead-supervisor.plist`).
- `~/.claude/cc-roles/` holds no `desk` file. The last desk was archived as
  `archive/desk.672.dead-2026-09-30` (measured: `ls -la ~/.claude/cc-roles/ ~/.claude/cc-roles/archive/`).
- So `send_page` resolves no target and does `[ -n "$target" ] || return 1` (scripts/lead-supervisor.sh:414-415)
  **before** cc-notify runs and **before** the RECORDED → `digest_add` → Notification Center branch (:456-460).
  Nothing is posted and nothing is logged. The no-desk design comment (:273-300) assumes the role file *exists*
  but points at a dead pane. The file being absent instead was never handled.
- Evidence of zero delivery (measured):
  - `grep -c '"kind":"page_digest"'` on the live IDL gives 0, and on the 10-18, 10-21 and 10-24 archives also 0.
  - `page_send_failed` gives 0, because that row is written only after a cc-notify attempt.
  - `ls ~/.claude/autonomy/pages/*.notified` gives 0 files, against 646 entries in the pages dir.
  - supervisor.log has no `page RECORDED`, `digest` or `SEND FAILED` lines in 05-19Z.
- Side effect: page() writes `.notified` only after `send_page` returns 0 (:520-522). With no marker, the
  equality damping (:509-510) and the sticky-ESCALATED rule (:516) never engage. That is why ESCALATED fired on
  **every sweep** from 11:02Z (66 rows), not once.
- Implication for the design: **a subject nudge must not ride `page()`/`send_page`.** It must call cc-notify
  directly at the subject, as `advise_subject` does (:555). The dead desk then cannot mute it. Repairing
  `send_page` is a separate fix: when no target is wired, fall to `digest_add` instead of `return 1`. That
  strengthens a gate and weakens none.

### 2.3 What the supervisor can and cannot see

- **Visible window:** a STALL? candidate needs a live pid that matches `claude`, plus telemetry **and** transcript
  ≥ STALL_S 1800 s stale (:1046-1048). Escalation needs a pre-existing `.page`, DEADLINE_S 900 elapsed, and an
  effects re-read that reads "dark" (:744-752).
- **Hard horizon:** `gc_stale` drops a live-owner telemetry row at GC_S 21600 s (6 h) and clears its pages
  (:146, :903-918). B13's row was GC'd at 15:38:18Z, after which the supervisor could not see the session at all
  until the statusline re-exported. Any nudge must fire inside roughly [30 min, 6 h] of telemetry staleness.
- **Exemptions already before the page** (reuse them as-is): a live permission beacon (:1067-1070) and an
  operator-adopted hold (:1077-1080). The registered-desk exemption sits in the STALL? predicate itself (:1046).
- **Cadence:** `SWEEP=30` s (:89). Measured heartbeats were ~50-63 per hour at 10-16Z (`jq` on
  `kind=="heartbeat"`), i.e. one sweep per ~60-70 s under load. So without a marker, a per-sweep act repeats about
  once a minute.
- **Self-update:** the daemon restarts itself on a changed script sha (:92-104, :1343-1353). A landed change reaches
  it with no plist edit.

## 3. Proof that a mail write wakes an idle pane with NO watcher (this session, today)

- Registry row `~/.claude/cc-registry/134.json`: `name agent-context-sync-134`, `pid 27956`, `paneUUID "134"`,
  `surface "pane"`, `session_id 666022fd-…`.
- `~/.claude-quaternary/sessions/27956.json`: `status "idle"`, `messagingSocketPath "/tmp/cc-socks/27956.sock"`,
  `procStart` = the live pid's start (measured with `jq` and `ps -o lstart`).
- `~/.claude/logs/cc-wake.jsonl` (measured `grep 666022fd | jq`): 58 `refused-busy` rows, each "vendor status is
  'busy'", from round-lane senders 2026-10-22 to 10-24 05:01:54Z. Then **no attempt at all between 05:01:54Z and
  20:15:41Z**. Then `20:27:36Z verdict=sent from=agent-context-sync-271 "frame queued … (38 unread)"`.
- Transcript lines 5065-5069:
  - 20:27:36.699Z: queue-operation carrying the cc-wake text.
  - 20:27:36.729Z: `type:user`, `isMeta:true`, "Another Claude session sent a message: 📬 peer-wake …".
  - 20:27:37.542Z: `hook_additional_context` from **UserPromptSubmit** carrying the pane-271 mail headline.
- Conclusion (measured): the socket path works on this binary and this session, and it surfaces the mail on the
  same turn. During the 10 h idle it was never exercised because **nobody sent mail**. The supervisor's only send
  path was the dead desk.
- Fleet-wide (measured, `jq -r .verdict ~/.claude/logs/cc-wake.jsonl | sort | uniq -c`, since 2026-10-03):
  1752 refused-busy · 38 sent · 1 read · 27 refused-identity · 1 refused-no-socket · 1 refused-no-mail ·
  1 refused-limited. cc-wake is called **only at send time**. A send refused as busy is never retried once the
  target goes idle, so mail that lands mid-turn waits for the next turn the target takes.
- launchd viability: the supervisor → cc-notify → cc-wake chain already runs under launchd. The cc-wake row at
  20:15:41Z (`from "claude"`, refused-busy) has the same second as `subject_advise`. cc-wake's transport uses
  `python3` (bin/cc-wake:291); `/usr/bin/python3` exists and imports `socket` (measured). The transport step itself
  has not yet run *from launchd*: the 20:15Z attempt stopped at W3.

## 4. "If the watcher is stopped, does mail still wake it?" Case by case

### 4.1 No watcher at all (B13 from about 09:30Z, see 4.3): YES, by socket

cc-notify `target_live` matches the registry row by pane **or session id** (cc-notify:1321-1330, `reg_sid_matches`
:1299-1304). It finds no `<sid>.watching` (`wake_path_armed`, :1376-1386, which defers to
`mailbox_wake_armed`). It is not headless, so it calls `_wake_pane`, i.e. `cc-wake <sid> --no-wait`
(:1485-1496, :1520-1525). cc-wake's gates (bin/cc-wake:23-45, :119-168, :244-272):

- W1: exactly one registry row matching the sid. ✓
- W2: sessions/<pid>.json names the sid, its procStart matches, and the socket is owned. ✓
- W3: vendor `status=="idle"` **and** our last presence beat is `stop`, and there is no permission beacon. ✓ while idling at ⛔.
- W4: unacked mail in the keyset. The nudge line itself satisfies this.
- W5: at most 1 wake per 120 s per sid.

Then cc-notify reports `verdict=delivered reason=woken-socket`. Kill switches: `CC_WAKE=off` (cc-wake:60) and
`--no-wake` / `CC_NOTIFY_WAKE=0` (cc-notify:1487). The supervisor must pass neither.

### 4.2 A harness-tracked watcher armed (W-a or W-b): YES, by watcher exit

cc-notify sees `wake_path_armed` and reports `delivered reason=wake-path-armed` (:1501-1503) **without** calling
cc-wake, so there is no double wake. The watcher exits on its next 15 s poll. Under W-a the adapter exits 2 and the
harness synthesizes a turn with the headline on stderr (mailbox-wake-arm.sh:262-265). Under W-b a task
notification arrives.

### 4.3 What B13 actually did at 08:34Z: a DETACHED watcher. NO wake for up to ~55 min (a hole)

- Transcript 4466 (08:34:43Z): the model's own `run_in_background` watcher timed out ("Re-arm the pane 134
  watcher" failed with exit code 2). That timeout is what woke it at 07:39Z and 08:34Z (W-b).
- Transcript 4468 (08:34:49Z): it ran, inside a background Bash,
  `cc-await-ping 134 --timeout 3300 --interval 15 >/dev/null 2>&1 & echo armed`. The background task completed at
  once (exit 0, output `armed`, measured from `tasks/bsi4253i0.output`), so the harness tracks nothing.
- Transcript 4476 (08:34:59Z): "I'm stopping the inbox watcher for now … it was only waking me every 55 minutes
  with nothing to report."
- If that orphan survived (unverified, see the open questions), it stamped `134.watching` and `<sid>.watching` with
  a live pid. Then:
  - mailbox-wake-arm at the 08:35:08Z Stop hit its claim guard (`_armed_already`, mailbox-wake-arm.sh:188-203) and
    exited **without arming**.
  - Any cc-notify in that window would see "armed" and **skip the socket wake** (cc-notify:1501).
  - The orphan's own exit, on mail or at its 3300 s timeout, wakes nobody: it is neither a harness task nor an
    asyncRewake hook, and its stdout is `/dev/null`.
  - Mail is not lost, because the watcher only peeks, but no wake happens until the orphan dies (≤3300 s) plus the
    90 s freshness window.
  - After that, nothing at all is armed, because W-a re-arms only at a Stop and the next Stop came at 18:11Z. So
    from about 09:30Z onward, case 4.1 applies and any mail would have socket-woken it.
- Fix direction (another slot or a backlog row, not needed for the nudge): `hooks/validate-bash.sh` should deny
  `cc-await-ping … &` inside a backgrounded command, the way it already polices `pkill -f cc-await-ping`
  (cc-await-ping:36-38). Alternatively the watcher could stamp its parent kind so `mailbox_wake_armed` can refuse to
  count a detached watcher as a wake path.

### 4.4 Waking is necessary but not sufficient

B13 was woken at 07:39Z and 08:34Z by its own watcher timeouts and re-closed ⛔ each time (transcript 4466-4476;
operator-readout rung ⛔ at 07:39:49Z and 08:35:10Z). A wake with no new content gets the same answer. So the nudge
must **carry the instruction** ("keep driving the ungated scope"), and the close-stack changes from the other slots
(goal e) are what stop the re-close from being accepted. The wake path supplies the turn; the rules and hooks
decide what the turn does.

### 4.5 idle-keepalive and mailbox-wake-arm are not substitutes

- **idle-keepalive** cannot wake: its EXIT trap forces 0 (:37), and it allows at most `CC_KEEPALIVE_MAX_WAKES=1`
  per gap (:85). Its B13 gap row shows `start 08:34:59Z`, `end 18:11:47Z`, `would_wake_at 09:29:59Z`,
  `outcome "wake_insufficient"`, but there is **no** `kind=wake` row for 666022fd (measured `grep 666022fd
  ~/.claude/logs/idle-keepalive.jsonl`). The timer most likely ended at the 08:38:11Z `away_summary` record under
  the pre-6897f9eb2 "file grew" test. That commit (2026-10-24 14:32 -0500, "gap ends only on a turn record") fixes
  exactly this (header :21-24; inference, not a measurement). Making it live would add one content-free wake per
  55 min, which per 4.4 becomes a ⛔ re-close treadmill. It belongs to the cache lever (USAGE_LEVERS W3), not this
  goal.
- **mailbox-wake-arm at Stop** only *arms* a watcher; it never wakes without mail. It is the right receiver and
  needs no change for (f).

## 5. Recommended design: `nudge_subject` in scripts/lead-supervisor.sh

### 5.1 Trigger (inside the existing STALL? branch, after both exemptions)

Insert the call between the `page "$sid" "STALL?"` at :1089 and `resolve_page` at :1090, and in `escalate_page`
(:766-769). The predicate:

1. `SUBJECT_NUDGE` is on: a new `CC_SUP_SUBJECT_NUDGE`, `1|shadow|0`, mirroring `SUBJECT_ADVISE` at :143.
2. The sid is a full dashed uuid: the same regex as :550.
3. **The rung oracle is the IDL.** The last `hook=="operator-readout"` row for this sid has `rung=="⛔"`. Read
   cheaply with `grep -F "$sid" "$IDL" | tail -n 400 | jq -s 'map(select(.hook=="operator-readout"))|last|.rung'`,
   bounded with `sup_bounded`. On a 9.7 MB IDL that is one grep per *candidate*, not per row. Absent or unreadable
   means no nudge (fail closed).
4. **Ungated scope remains.** Wanted: an `operator-readout` IDL field such as `scope_open` (unfinished in-scope
   items, including the new loop-scope floor) plus `gating` (whether the open class-C packets gate all of it). This
   is the other slots' wrap-ledger change surfaced through an already-registered Stop hook, so no settings change.
   Until that field exists, nudge on ⛔ alone and let the nudge text carry the "if truly all-gated, say so and stop"
   escape (5.3).
5. Fire on whichever comes first: the **first ESCALATED** of the episode (effects dark across the deadline), or a
   **STALL? with rung ⛔ and `scope_open>0`**, which fires about 15 min sooner (STALL_S 1800, versus
   1800 + DEADLINE_S 900).

Already excluded upstream, for free: permission prompt (:1067), operator-adopted hold (:1077), registered desk
(:1046), dead pid (:1026). cc-wake adds its own W3 permission check (cc-wake:167-168).

### 5.2 Send

```
sup_bounded "$SUP_NOTIFY_TIMEOUT_S" "$NOTIFY_BIN" "$sid" --from lead-supervisor \
  --subject "keep driving the ungated scope" "<fixed text, 5.3>"
```

The send has no `--no-wake`. cc-notify enqueues, then wakes by watcher (4.2) or by socket (4.1). Log `subject_nudge`
to the IDL with notify_rc, **cc-notify's own** verdict and reason, the decision-key and the attempt number.

Parse bug to avoid, also present in `advise_subject` (:557): `grep -oE 'verdict=[a-z-]+' | head -1` picks up
**cc-wake's** token. `_wake_pane` echoes cc-wake's stderr (cc-notify:1494) *before* cc-notify prints its own
`verdict` line (:1523/:1527). So the 20:15:41Z `subject_advise` row recorded `verdict "refused-busy"` while
cc-notify's real verdict was `delivered reason=no-watcher`. Parse `^cc-notify: verdict=` and `reason=` instead,
and fix advise_subject the same way.

### 5.3 Text (fixed, no operator-authority claims, one line, because cc-notify collapses newlines)

> ⏯ IDLE ON ⛔ WITH SCOPE LEFT (lead-supervisor, machine text, addressed to THIS session; not an operator answer)
> — you have been idle ~Nm holding open decision(s) <ids>. An open decision gates only the items it names: re-read
> your frozen scope and drive every in-scope item it does not gate (a loop scope: run the next round as scoped —
> the frozen scope is the course until the decision is answered). If every remaining in-scope item truly waits on
> it (or it is a money / self-modification / permission gate), reply with one line naming what each packet gates,
> then stop.

`<ids>` come from `cc-decide list --open --class C --json` filtered on `session_sid`, which is read-only. It is the
same source wrap-ledger uses at :1510.

### 5.4 Damping: why it cannot storm or loop

- **Key = decision state, not idle episode:** `sha(sid + rung + sorted open class-C ids + scope_open)`, stored in
  `$PAGEDIR/<sid>.nudged` as `<key> <count> <last_epoch>`.
  - Keying on the episode would loop. Each nudge-woken turn that re-closes ⛔ starts a new episode, the STALL?
    would re-fire 30 min later, and the result is one turn every ~45 min forever. That is the B13 07:39 → 08:34
    pattern.
  - A changed key (a packet answered, scope moved) means new news, so the count resets.
- **Ladder** (estimated, modeled on the permpend doubling ladder at :178-181): attempt 1 at the trigger, attempt 2
  ≥2 h later, attempt 3 ≥4 h after that. **Cap 3 per key.** The 6 h GC horizon (:146) ends observation anyway.
  The worst case is 3 model turns per decision-state per session.
- **Fleet cap:** at most 3 nudges per sweep, oldest stall first.
- **Marker survives recovery.** Neither `clear_page` (:524, which today also deletes `.advised`) nor
  `clear_page_recovered` (:583-609) may delete `.nudged`. Otherwise every woken-then-re-idled turn re-arms the
  nudge. Only a key change or a reap/GC drops it.
- **Fail CLOSED on the marker.** If `.nudged` cannot be written, do not send. This is the opposite of page-damp's
  fail-open (hooks/lib/page-damp.sh:23-24), and deliberately so: a lost page is the worse error for a pager, but
  here the cost of each repeat is a model turn.
- **Floors underneath:** cc-wake W5 allows at most 1 socket wake per 120 s per sid (cc-wake:266-272). The watcher
  claim guard prevents duplicate watchers (mailbox-wake-arm.sh:170-203).
- **Write the marker on cc-notify rc 0** (enqueued), even if the wake did not happen (`reason=no-watcher`). The line
  then sits in the inbox and surfaces at the next turn. Retrying per sweep would only stack duplicate lines. A
  non-zero rc (3/4/5/124) leaves the marker unwritten, and the next sweep retries, bounded by the cap.
- **Infinite-loop check:** the supervisor is out-of-session and blocks no Stop, so it cannot create a Stop-hook
  loop. Each nudge costs at most one turn, there are at most 3 per key, and the key changes only when real state
  changes.
- **False-block check:** not applicable, since nothing is blocked. **False-wake check:** a genuinely all-gated
  session pays at most 3 turns per key and answers in one line. With `scope_open` present (5.1 point 4) and 0, it
  pays nothing.

### 5.5 Shadow first (optional)

`CC_SUP_SUBJECT_NUDGE=shadow` logs `subject_nudge_shadow` with the key and the would-be text, and sends nothing. This
mirrors idle-keepalive's shadow (idle-keepalive.sh:1-5). A replay over 666022fd's rows would have produced one nudge,
between about 09:26Z and 11:02Z (estimated from the §2.1 timeline).

### 5.6 What this does not need

No settings.json edit, no new hook registration and no plist edit. It is a lead-supervisor script change only,
picked up by the sha self-restart (:92-104). The receiver side (mailbox-wake-arm, mailbox-drain, cc-wake) is
already registered and live.

## 6. Secondary findings (pass on, not designed here)

1. `send_page` with no target is silent (:414-415). This is the root of "the supervisor told no one" and of the
   per-sweep re-page churn (§2.2).
2. `cc-inbox-guard` saw this session's sid box with 36 unacked lines at 10:00:50Z. It classed the session NOW-DEAD
   while pid 27956 was alive (bin/cc-inbox-guard:620-628 branch `1`), then tried the phone (`push-rc-3`). It is a
   second out-of-session sensor that could call `cc-wake` for a *live* idle owner (its branch `0`) and does not.
   The NOW-DEAD verdict for a live session was not root-caused here.
3. `666022fd….acked` was last written 2026-10-22 18:12 (local), while `134.acked` was written 2026-10-24 15:27
   (measured with `ls -la ~/.claude/mailbox/`). So the session box's acked cursor is not being promoted. Its
   "unacked" count stays permanently high, which (a) makes cc-wake's W4 always true for this sid and (b) made the
   20:27Z wake claim "38 unread" for mostly already-surfaced lines.
4. cc-wake is called only at send time. 1752 of 1823 attempts (measured) were `refused-busy`, and nothing retries
   when the target later idles. A supervisor sweep "idle (vendor) + unacked fresh mail → cc-wake" would close it.
   That is out of scope for (f) but on the same path.

## 7. Docs and research on wake paths (from `grep -l wake docs/research/*.md`, wake-specific subset)

- docs/research/mechanical-wake-asyncrewake-2026-07-29.md: the asyncRewake proof (cited at mailbox-wake-arm.sh:9-11).
- docs/research/w2-stop-rewake-proof/: the Stop half, including P-W2d's duplicate watchers (mailbox-wake-arm.sh:12, :20-22).
- docs/research/wake-socket-repricing-2026-09-10.md: the socket transport (`status idle|busy|waiting|shell`, wire
  format; :30-32), cited at cc-wake:21.
- docs/plans/AGENT_PEER_WAKE.md: cc-wake capability 1. It says "DONE 2026-10-03, landed `e725334ae`, live"
  (:106-108); acceptance was `cc-wake 83 --wait 300` → `verdict=read` (:116).
- docs/research/goal-safe-2way-comms-2026-08-13.md: idle-scoped watchers under /goal (cc-await-ping:64-73).
- docs/research/wake-on-ping-2026-07-26.md, cross-session-mail-2026-07-20.md, idle-session-occupancy-2026-08-09.md,
  api-error-rewake-proof-2026-09.md, lr-wake-incident-2026-10-18/: listed by the grep but not read for this map.
