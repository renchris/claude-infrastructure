# Slot: arrival lag + in-chat acknowledgement (peer-mail-headline, 2026-10-10)

Read-only research slot. Nothing under `$HOME/.claude`, no settings file and no mailbox, `.seen` or `.acked` file was written. No sender, waker or acker was run. Scratch scripts and their JSON output are in `/tmp/pmh-lag-ack-slot/` (`lag.py`, `box.py`, `classify.py`, `fire.py`), outside the repo.

Every number below is labelled **measured** (with the script that produced it) or **estimated** (with the method).

---

## Answers first

**A: arrival lag.** Most mail surfaces within seconds. Measured over 175 surfaced mail lines in 29 sessions: lag from the sender's stamp to surfacing is p50 **9 s**, p90 **3.3 min**, p99 **4.9 h**. The tail is a few hours-old forwards, not a smooth slope. **The headline should say "arrived N min late" only at 10 minutes or more.** That threshold marks 8 of 175 lines (4.6%), and every one of them is materially late (26 min to 21 h). Lag **must be measured from the innermost (origin) stamp**. The forward stamp is written by the drain itself about 1 s before surfacing, so it hides the age completely.

**B: acknowledgement.** Add one instruction to the drain context. It asks for **one chat line per delivery that contains agent-written mail**, written before anything else in the next message, in this shape:
`📬 pane 225 (lr-investigation), sent 22:59: root causes for 5 unrecovered panes; top one is mine. Acting on it now.`
Measured rate: **0.81 such deliveries per active session-hour** (median session 0.5/h, p90 3.75/h, max 5.2/h, which is a wave lead). Measured today, half of these deliveries (51 of 102) are followed by assistant text that never mentions the mail.

The instruction only works if the drain classifies senders first. **The drain's current noise filter (`hooks/mailbox-drain.sh:852`) matched 0 of 455 direct mail lines in the last 3 days.** Of those lines, 214 (47%) are automated: 167 come from `cc-await-ping` WAKE-PATH-DOWN/CLASS alone. So today's operator digest calls all of them "peer message(s)", and an ack instruction keyed on it would fire on noise.

---

## Corpus and method

| source | what | how chosen |
|---|---|---|
| transcripts | 40 newest top-level `~/.claude*/projects/*/*.jsonl` with mtime < 3 d that contain `📬`, between 20 KB and 60 MB, **deduplicated by session uuid** (largest copy kept) | measured, `/tmp/pmh-lag-ack-slot/sel2.txt`. Of 275 unique sessions with mtime < 3 d, 40 were selected; the oldest selected mtime is 2026-10-10T15:02. 29 of the 40 contain at least one parsable mail line. |
| mailbox store | `~/.claude/mailbox/*.md` and `archive/*.md*` with mtime < 3 d (182 boxes), plus `.seen` cursors (read only) | measured, `box.py`. Every `~/.claude-*/mailbox` is a symlink to `~/.claude/mailbox` (`readlink`), so this is the whole store. |

**Deduplication matters.** The first selection held 7 sessions twice or three times (e.g. `58d3640a…` under `.claude`, `.claude-next` and `.claude-quaternary`), because `cc-lr move` copies a transcript across config dirs. Without deduplication those sessions were double-counted; a mismatch between my batch counter (93) and my mention counter (149) exposed it. All figures below are from the deduplicated set.

**Surfaces parsed** (`lag.py`). Each surface is listed with the record shape it leaves in the transcript:

| surface | transcript record | source of text |
|---|---|---|
| drain, turn boundary | `attachment.type=hook_additional_context`, `hookEvent=UserPromptSubmit` | `hooks/mailbox-drain.sh:835` |
| drain, mid-turn | the same, with `hookEvent=PostToolUse` | `mailbox-drain.sh post-tool` (`:7`, `:171`) |
| drain, session birth | the same, with `hookEvent=SessionStart` | `:169` |
| asyncRewake wake: harness receipt | `type=queue-operation, operation=enqueue`, content holds `📬 Peer mail arrived while you were idle…` | `rewakeMessage` from `migrations/0007…:73` / `0012…:72` + stderr from `hooks/mailbox-wake-arm.sh:211` |
| asyncRewake wake: delivered while idle | `type=user`, string content holding the same text | the same |
| asyncRewake wake: absorbed mid-turn | `attachment.type=queued_command`, `commandMode=task-notification` | the same |
| cc-wake frame | `type=user`, `📬 peer-wake: …` | `bin/cc-wake:190`. It carries no mail stamp, so it is counted but has no lag. |
| stop-hook fold | `📬 INBOX —` | `hooks/session-continue.sh:1461`. **None occurred in this corpus.** |

User records whose content is a `tool_result` were excluded, because they are transcripts quoting other transcripts. Each mail line was matched with the drain's own grammar (`mailbox-drain.sh:786`): optional `<ISO> [forwarded:<pane>] ` hops, then `<ISO> [<from>] <body>`. Lag = the record's `timestamp` (UTC, ms) minus the stamp. **origin lag** uses the innermost stamp (the sender's send time). **outer lag** uses the first stamp (the last forward hop). No negative lags occurred, so there is no clock skew; this is all one machine.

---

## A. Arrival lag

### A1. Distribution per surface (measured, `lag.py` on `sel2.txt` → `rows.json`)

| surface | n | origin lag p50 | p90 | p99 | max | outer-stamp lag p50 / p90 / p99 |
|---|---|---|---|---|---|---|
| **all surfaced** | 175 | **9 s** | **3.3 min** | **4.9 h** | 21.1 h | 1 s / 9 s / 8.9 min |
| drain: all | 161 | 9 s | 3.8 min | 5.2 h | 21.1 h | 1 s / 8 s / 8.9 min |
| drain: UserPromptSubmit | 114 | 7 s | 24 s | 37.5 min | 40.2 min | 1 s / 3 s / 8.9 min |
| drain: PostToolUse (mid-turn) | 35 | 15 s | 66 min | 5.8 h | 6.7 h | 1 s / 2 s / 8 s |
| drain: SessionStart | 12 | 36 s | 3.0 min | 18.8 h | 21.1 h | 9 s / 19 s / 2.8 min |
| wake: delivered (idle turn + absorbed mid-turn) | 14 | 9 s | 31 s | 2.5 min | 2.8 min | 7 s / 13 s / 16 s |
| wake: harness enqueue | 14 | 9 s | 31 s | 2.5 min | 2.8 min | 7 s / 13 s / 16 s |
| agent-written lines only | 110 | 11 s | 5.8 min | 4.2 h | 6.7 h | 1 s / 6 s / 8.2 min |
| automated lines only | 65 | 4 s | 90 s | 8.0 h | 21.1 h | 1 s / 10 s / 14.4 min |

The PostToolUse and SessionStart percentiles rest on n = 35 and n = 12. Read their p99 as "the tail exists", not as a rate.

Counts by origin-lag threshold, all 175 surfaced lines (measured):

| > 2 min | > 5 min | > 10 min | > 15 min | > 30 min | > 1 h |
|---|---|---|---|---|---|
| 22 (12.6%) | 15 (8.6%) | **8 (4.6%)** | 8 | 7 | 5 |

### A2. The tail, line by line (measured, every surfaced line with origin lag > 2 min)

| origin lag | outer lag | surface | fwd | sender: gist |
|---|---|---|---|---|
| 21.1 h | 8 s | SessionStart | yes | agent-context-sync-180: RECYCLE DEFERRED (automated) |
| 6.7 h | 0 s | PostToolUse | yes | wt-675c50ef44d9-185: "DONE, landed daa386b23" |
| 4.3 h | 1 s | PostToolUse | yes | claude-infrastructure-16: "Lead FYI: an lr_recon change…" |
| 4.0 h | 1 s | PostToolUse | yes | agent-context-sync-180: "Lead (pane 180): you sat 47 min…" |
| 103 min | 1 s | PostToolUse | yes | claude-infrastructure-16: "cohort … SETTLED … hold lifted" |
| 40 min | 1 s | UserPromptSubmit | yes | agent-context-sync-180: root cause 3 |
| 39 min | 34.5 min | UserPromptSubmit | yes | cc-await-ping: WAKE-PATH-DOWN (automated) |
| 26 min | 1 s | UserPromptSubmit | yes | agent-context-sync-180: "FYI from lead…" |
| *gap: nothing between 10 and 26 min* | | | | |
| 9.9 min | 1 s | PostToolUse | yes | cc-await-ping: WAKE-PATH-CLASS |
| 9.0 min | 1 s | PostToolUse | yes | claude-infrastructure-4: "Lead: understood…" |
| 8.9 min ×2 | 8.9 min | UserPromptSubmit | no | pane-225 limit-recover → two sessions out of weekly quota |
| 6.9, 6.0, 5.7, 4.8, 3.8, 3.4, 3.0, 3.0, 2.8, 2.8 min | ≤ 3 min | mixed | mostly yes | lead rulings, HANDOFF-PINGs, boot-resume, WAKE-PATH-DOWN |

Two observations decide the design:

1. **The forward hop hides the age.** Of 189 parsed lines, 154 are forwards (measured). Their outer stamp is written by the drain's coverage fold at drain time: outer lag p50 1 s, and 0 to 2 s on every multi-hour row above. A headline that computed lag from the first stamp on the line would call a 6.7 h-old "DONE, landed" message on time. **Use the innermost stamp**, the same one the stale-forward summariser already extracts as `ots` (`hooks/mailbox-drain.sh:786-794`).
2. **There is a natural break at about 10 min.** Below it are ordinary busy-session delays: a long tool call, a session out of quota, a slow re-arm. Above it, after a gap from 9.9 to 26 min, every line is mail that sat in a predecessor's or alias box for 26 min to 21 h and was then forwarded. Those lines are exactly the ones whose content may be stale, which is what "arrived late" must warn about.

### A3. Cross-check against the fleet-wide cursor (measured, `box.py`)

For each of 146 boxes, I took the `.seen` mtime minus the origin stamp of the line at the cursor. The result is p50 **14 s**, which agrees with the transcript p50 of 9 s. Its p90 of 151 h is not usable: a re-commit of an unchanged cursor moves the mtime, so the tail measures re-touches, not lateness. Separately, **72 lines sit beyond `.seen` right now, in 45 boxes, with median age 32 h** (p90 66 h). Only 5 of them are agent-written. That backlog is the reservoir the 4 to 21 h forwards come from. Adopted later, it will surface with the multi-hour lags shown in A2.

### A4. Recommendation

- **Threshold: origin lag ≥ 10 min ⇒ show lateness.** It marks 4.6% of surfaced lines in this corpus, all genuinely stale. A 5-min threshold would mark 8.6% and add the 5 to 9 min busy-loop delays. Those lines' content was still current, and showing the flag on them would teach the operator to ignore it. A 15-min threshold marks the same 8 lines here. 10 min is the more conservative edge of the gap.
- **Always show the sent time; show the lag only past the threshold.**
  - `sent 22:59` for same-day mail, under threshold
  - `sent 22:59 · arrived 14 min late` for 10 to 89 min
  - `sent 18:12 · arrived 4 h late` from 90 min to 36 h, whole hours
  - `sent Oct 9 20:44 · arrived 2 days late` past 36 h; the date is added whenever the sent day is not today
- **Compute "arrived" at emit time in the surfacing process.** For the drain that is `date` at `mailbox-drain.sh:835`. For the wake it is `mailbox-wake-arm.sh` before its `printf` at `:211`. The harness enqueue follows within seconds: the wake's outer lag is p90 13 s / max 16 s (measured), so hook time is a faithful receive time.
- **Per-line, not per-batch.** One drain batch mixed a 4.3 h, a 4.0 h and a 103 min line (`197b48ee:855`). The lag belongs on each line; a batch header can carry the maximum.

---

## B. Acknowledgement in chat

### B1. What the receiving session is told today (read, file:line)

| surface | text the model gets about what to do |
|---|---|
| drain context (`hooks/mailbox-drain.sh:835`) | "delivered as CONTEXT … Already marked delivered. **Triage/act as appropriate; reply to a peer with cc-notify <uuid> "…"**. Notice from peer Claude sessions on this machine." |
| drain operator line (`:858-864`) | `📬 peer mail ◀ N peer message(s) from a,b,c — full text: cc-mail` (systemMessage, operator-only) |
| stop-hook fold (`hooks/session-continue.sh:1461-1466`) | "📬 INBOX — N new peer message(s)… **Triage these first** … reply with cc-notify <uuid> "…" — THEN continue the loop below." (`:1464`). Operator line at `:1473`. |
| asyncRewake (`migrations/0007-mailbox-wake-arm-registration.sh:73`, `0012…:72`; body `hooks/mailbox-wake-arm.sh:211`) | "📬 Peer mail arrived while you were idle — delivered by the inbox watcher, not typed by you: <line>". The operator sees only the static `rewakeSummary` "📬 peer mail". |
| cc-wake frame (`bin/cc-wake:190`) | "📬 peer-wake: you have N unread peer message(s)… Run this once to surface them, **then act on them**: cc-mail --pane … --since 2d --full" |
| no-watcher nag (`mailbox-drain.sh:534`, `session-continue.sh:893`) | about arming, not about replying |

`grep -rn -i "peer mail\|acknowledg"` over `hooks/` and `.claude/rules/`, plus a grep of `CLAUDE.global.md`, found **no existing instruction to tell the operator about mail**. Every surface says "triage / act" and "reply with cc-notify". So a new ack instruction conflicts with nothing. The one thing it must not do is invite a cc-notify reply as the ack (B4).

### B2. Volume (measured)

Mailbox store, direct (non-forward) lines with a stamp in the last 72 h, `box.py` + `classify.py`:

| window | total | agent-written | of which pure "ack/thanks" mail | automated |
|---|---|---|---|---|
| 0 to 12 h ago | 104 | 52 | 2 | 50 |
| 12 to 24 h | 77 to 81 | 44 to 46 | 2 | 31 to 33 |
| 24 to 36 h | 118 to 122 | 63 to 65 | 1 | 54 to 56 |
| 36 to 48 h | 29 | 12 | 1 | 16 |
| 48 to 60 h | 65 | 35 | 0 | 30 |
| 60 to 72 h | 58 | 26 | 1 | 31 |
| **72 h** | **455** | **234 + 7 ack** | | **214 (47%)** |

The two values per row come from the live-store pass and the live-plus-archive pass; the archive added nothing in-window. Forward copies add 317 more lines in 72 h.

**Deviation from the brief.** The brief's "≈750 mail lines per 12 h" is the 2026-07-26 figure quoted in the comment at `mailbox-drain.sh:840`. Measured now, it is **77 to 122 direct lines per 12 h, about 45 to 65 of them agent-written**. That is roughly 4 to 5 agent-written mail lines per hour across the whole fleet (estimated: the 72 h count ÷ 72).

Automated breakdown (measured): `cc-await-ping` 167 (WAKE-PATH-DOWN 120, WAKE-PATH-CLASS 47); agent-named senders with automated bodies (`SHADOW:`, `RECYCLE…`) 22; config-dir sender names `claude` / `claude-next` / `claude-quaternary` 13 (cc-lr move, SELF-CLOSE RETRY, RECYCLE RETRY, CONTEXT 80% FULL); `recycle-watcher` 7; `lr-fire-resume` 2; `cc-resume-debt` 2; `handoff-fire` 1.

The agent-written lines include **115 `HANDOFF-PING`s**, the child-to-lead reports. Those are real content (BLOCKED, decision gate, DONE); 25 of them are "progress" pings. My first classifier wrongly filed `HANDOFF-PING` as automated through a `HANDOFF-` prefix. Any implementation must exempt it.

The heuristic ask-cue regex (`?`, BLOCKED, decision, your call, ruling, hold, …) matches 100 of 234 agent lines (estimated). So roughly 40% ask for something and 60% are reports or FYIs.

Per receiving session, transcript side (`fire.py`, deduplicated corpus, active hours = number of 10-min buckets holding a user or assistant record ÷ 6):

| | value |
|---|---|
| sessions / active hours | 29 / 125.2 h |
| mail deliveries (batches) surfaced | 159, so 1.27 per active hour |
| **deliveries holding ≥ 1 agent-written line** | **102, so 0.81 per active hour** |
| per session, per active hour | p50 **0.50**, p90 **3.75**, max **5.21** (`44091255…`: 25 agent batches in 4.8 h, a wave lead) |
| current behaviour after such a delivery | 51 of 102 followed by assistant text that mentions peer, pane N, mail, lead, ping or inbox; 51 do not (estimated, regex on the first 400 chars of the next text block) |

**So a per-delivery ack fires about once per active hour in the median session and about 4 to 5 times per hour in a busy lead.** Per message would barely differ on average: 110 agent lines across 102 batches. The batch rule matters only for bursts, such as one lead batch carrying 3 lines (`197b48ee:855`), and that is exactly where per-message lines would crowd the chat.

### B3. Scope rules

1. **Acknowledge only agent-written mail, and let the drain decide which that is, not the model.** Extend the existing `_noise` classifier at `mailbox-drain.sh:851-856` from body markers to sender plus body:
   - senders `cc-await-ping`, `claude`, `claude-next*`, `claude-secondary`, `claude-tertiary`, `claude-quaternary`, `recycle-watcher`, `lr-fire-resume`, `cc-resume-debt`, `handoff-fire`, `boot-resume`, `desk-sweep`
   - bodies starting `WAKE-PATH-`, `HANDOFF-` **except `HANDOFF-PING`**, `RECYCLE`, `SELF-CLOSE RETRY`, `STRANDED SESSION`, `SHADOW:`, `⚠️ CONTEXT NN% FULL`, `[restore]`, `cc-lr move`, plus the existing `HANDOFF-HUSK-PANE | REAPER SURFACE | [desk-sweep]`

   Today that filter matches **0 of 455** lines (measured), so the operator's "N peer message(s)" digest includes every WAKE-PATH-DOWN. One classifier should feed the digest, the ack instruction and the headline. The ack instruction is emitted **only when `_sig > 0`**.
2. **One line per delivery, never one per message.** Name every agent sender in that one line, separated by `;`.
3. **Ack FYIs too, in the short form "noted, no action".** Skipping pure FYIs would need a model judgement per message. It would also make silence ambiguous: the operator could not tell "skipped as FYI" from "never saw it", which is today's 50% silent state. At 0.81 per hour the cost is one short line.
4. **Do not acknowledge**:
   - automated or lifecycle lines. The drain already counts them in the operator digest, and custody returns already appear as `custody −N` (`:868-870`).
   - a line already acknowledged in this session. Duplicate redelivery is by design ("a dup, never a loss", `:879`, `mailbox-wake-arm.sh:213`). The key is stamp plus sender.
   - an empty-body wake ("the watcher reported mail but returned no body"). There is nothing to name; the follow-up `cc-mail` read or the next drain gets the ack.
5. **Never acknowledge by mailing the sender.** A cc-notify reply costs the receiver a turn or a wake. Mail that is purely "ack / thanks / understood" is already 7 of 241 agent lines (measured). A sender that needs proof of reading has `cc-notify --receipt`. Reply by mail only with content the sender needs.
6. **Placement.** The ack is the first line of the next assistant text, including mid-turn after a PostToolUse drain, before other prose. It must not use the hook's own `📬 peer mail ◀` prefix, so the operator can tell the session's line from the hook's digest.

### B4. Exact text to add

**Drain context.** Append to the `ctx` printf at `hooks/mailbox-drain.sh:835`, after "…reply to a peer with cc-notify <uuid> "…".", and only when `_sig > 0`:

```
     ACKNOWLEDGE IN CHAT — the operator cannot see this block. Start your next message with ONE line for this whole delivery (not one per message), covering only the session-written mail above (${_sig} of ${n}; automated lines are already counted for the operator — skip them):
     📬 pane <N> (<title>), sent <HH:MM>[, arrived <N> min late]: <what they said, ≤12 words> — <acting on it now | after <current step> | noted, no action | needs you: <the decision>>
     Several senders: one line, entries joined by "; ". Skip a message you already acknowledged. Do not mail the sender just to acknowledge — reply with cc-notify only when they need content from you.
```

**Stop-hook fold.** Add the same sentence to `hooks/session-continue.sh:1464`, which currently reads "Triage these first … — THEN continue the loop below.", so that the in-loop desk (the heaviest consumer, per `:1467-1469`) behaves the same. The ack text should be one shared string in `hooks/lib/mailbox-pending.sh`, not two copies.

**Wake.**
- asyncRewake (`hooks/mailbox-wake-arm.sh:211`): print the same ACKNOWLEDGE sentence on stderr after the body when the body holds a parsed agent line. The `rewakeMessage` prefix lives in `settings.json` and stays as it is.
- cc-wake frame (`bin/cc-wake:190`): append ", then acknowledge them in chat in one line as the inbox block instructs". The frame carries no bodies, so the ack follows the `cc-mail` read.

**Example lines from this corpus.** These are drafted by applying the format to real mail; they are not observed output.
- `📬 pane 225 (lr-investigation), sent 22:59: root causes for 5 unrecovered panes; top one is mine — acting on it now.`
- `📬 pane 16 (FLEET_V2 lead), sent 11:28: GO to land 402248533 — acting on it now; pane 180 (agent-context-sync), sent 06:02, arrived 26 min late: lr_recon evidence FYI — noted, no action.`
- `📬 pane 185 (wt-675c50ef44d9), sent 08:04, arrived 6 h late: DONE, landed daa386b23 — noted, no action.`

---

## Risks and open items

- **Half of all asyncRewake wakes carry no mail line** (measured: 15 of 26 wake enqueue records read "(the watcher reported mail but returned no body — read it with: cc-mail)", 15 distinct sessions, one each). With no line there is no sender, no title and no lag for the headline or the ack. One per session suggests a birth-time race between the SessionStart drain and the birth watcher. That is a **hypothesis, not checked** in this slot.
- **The asyncRewake operator headline is a static `rewakeSummary` ("📬 peer mail")** in `settings.json` (migrations 0007/0012). Sender, title and lag can reach the operator on that path only through what the model writes, which is the B4 ack line, or through a settings change outside this slot.
- **The sample is small and recent.** 175 surfaced lines from 29 sessions, mostly 2026-10-10 to 2026-10-11, under load average 800 to 935 (`uptime` at 23:31: 935.62 / 802.34 / 574.27). The p99 values rest on 2 to 3 lines. The 10-min gap is clear in this sample but should be re-measured on a wider window before it is hard-coded; it belongs in a tunable environment variable.
- **The sender classifier is a pattern list.** It mis-filed `HANDOFF-PING` on the first pass. New automated senders appear over time, and a list in three places will drift, so it needs to be one SSOT function with a bats fixture per sender family.
- **The "half are silent today" figure is a regex estimate** on the next assistant text and can count unrelated "lead" or "pane" mentions. Treat it as an order of magnitude.
- **`.seen`-mtime lag is unusable past p50**, because cursor re-commits re-touch the file. Do not build a lag metric on it.
- **Volume is about 8 times lower than the brief's 750 per 12 h.** Any per-hour budget argument in the headline design should use the measured 77 to 122 per 12 h, not the July figure in the `mailbox-drain.sh:840` comment.
