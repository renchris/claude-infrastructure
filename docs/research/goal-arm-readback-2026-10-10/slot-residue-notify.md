# Slot: residue and notification (questions 3 and 4)

Worktree `goal-arm-readback`, read 2026-10-10. Line numbers are from the working tree, which by the
time this slot ran already carried the lead's uncommitted D1 change to `composer_content`
(`git diff --stat`: `scripts/handoff-fire.sh | 40 +`). In that change `FIRE_COMPOSER_READLINES_MAX`
defaults to 200, not the 120 the brief names. Every number below is labelled: **measured** (with the
command) or **estimated** (with the method).

---

## Q3: what happens to an unsubmitted /goal after MANGLED

### 3.1 The mechanism, traced

| Piece | Where | What it does |
|---|---|---|
| `composer_scrub_verified` | handoff-fire.sh ~4403 | Reads the box, sends Ctrl-U (with a backspace when a round stalls) up to 12 rounds, and re-reads after each round. rc 0 = proven empty. rc 1 = could not clear (prints what is left). **rc 2 = box unreadable, returned before any keystroke.** |
| `composer_residue_record` | ~4454 | Writes `<ts>\t<content>` to `~/.claude/logs/composer-residue/<pane>`. Has no TTL. |
| `composer_residue_forget` | ~4462 | Deletes the receipt. |
| `composer_residue_is_ours` | ~4470 | rc 0 only when the receipt's content is **byte-equal** to the composer's current space-stripped content. |
| Mangle site, `it2_paste_submit_verified` rc 4 | ~4686-4699 | Scrubs immediately. Scrub rc 0: `forget`. rc 2: `record "$FIRE_PASTE_LAST_READBACK"`. rc 1: `record "${scrub_left:-…}"`. |

Every consumer of the store, found with `grep -rn composer-residue|composer_residue scripts hooks bin`:

1. **Recycle composer gate**, `recycle_composer_block` (~17150-17230). This is the only place that
   reads a receipt to authorise a scrub. If `composer_residue_is_ours` matches, it runs
   `composer_scrub_verified`; on success it calls `forget`, emits `recycle-residue-scrubbed` and the
   recycle goes ahead. Otherwise the composer counts as a foreign draft: the gate waits 180 s, emits
   `recycle-held-draft`, pages the desk with "RECYCLE BLOCKED…", sends the pane "RECYCLE DEFERRED"
   and exits 1. An unreadable box (rc 2) gets `rcy_composer_unreadable`, `hf_recycle_defer`, a retry
   ticket, and exit 1.
2. **`--probe-recycle-preconditions`** (the limit-recover `lr-handoff` precheck, ~11780). It
   classifies a readable non-empty composer with `composer_unintended_class`. A `/goal…full brief in
   the prompt above…` body is class `rail-goal` (scripts/lib/composer-intent.sh:61). For that class
   it writes a receipt with the **exact content read** plus a discard note, and the recycle gate
   above then scrubs it.
3. **`scripts/lib/cc-tui.sh` `cc_tui_submit`**. Callers are the lr-reset-poller nudge and request
   prompt mode, the lr-fleet nudge-in-place, lr-upgrade's switch, and `it2-kitty session tui-submit`.
   Its pre-gate clears any `rail-goal` content **once** (`cc_tui_clear`), logs it to
   `~/.claude/logs/composer-discarded.log`, and then pastes its own payload. It does not read the
   receipt store; it writes to it only on its own mangle.
4. **`scripts/limit-recover/lr-upgrade.sh`**. `lru_file_rail_receipt` writes receipts for its own
   rail markers. Those markers do not include `/goal`. `lru_receipt_drop` reads one back.
5. **hooks/** and **bin/**: no consumer. `grep -rn composer-residue hooks bin` returns nothing that
   touches the store.

**Nothing anywhere re-submits or retries the /goal.** No code path sends the CR later, and no hook
reads `class:"goal-arm"` rows from `handoffs.jsonl`. The only reader is the operator's jq query in
commands/handoff.md:325. `inherit_recycle_goal` re-arms on a successor only from a predecessor's
**live `goal_status`** attachment. A goal that never armed has none, so **one mangle drops the goal
for every later link of a `--recycle` chain**, unless a caller passes `--goal` explicitly. No
limit-recover script does (`grep -l -e --goal scripts/limit-recover/*.sh`: none).

What does happen to the residue, by path:

- **Mangle site**: the residue is cleared only if the scrub can read the box. In every live incident
  it could not.
- **Recycle gate**: the residue is cleared only if the receipt matches byte for byte (see 3.2: it
  never does).
- **Limit-recover precheck, and `cc_tui_submit` callers**: the residue is cleared as `rail-goal`
  junk, but only through a parse that can see the box. The precheck uses the same `composer_content`.
  `cc_tui_composer` reads `--extent screen` (the whole screen, not the last 24 rows), so the cc-tui
  path could already read a tall box before the fix.
- **Anything else**: the residue stays until a human presses Enter or Ctrl-U.

### 3.2 Defect found: the live incidents wrote receipts that can never authorise anything

**Measured** (`ls ~/.claude/logs/composer-residue/` and `cat` of each file): there are 8 receipts.
**7 of the 8 hold the literal string `<unreadable>`** (panes 2, 25, 70, 175, 176, 202, 203). The
eighth (pane 137) is a scrolled-tail fragment of a goal. The rc 2 branch records
`$FIRE_PASTE_LAST_READBACK`, which is a sentinel and not content. `composer_residue_is_ours` compares
byte for byte. Replayed:

```
composer_residue_is_ours 203 "<472-char payload parsed from the evidence screen>"  → rc 1 (not ours)
composer_residue_is_ours 203 "<unreadable>"                                        → rc 0
```

So the scrub note printed on that branch is false today: "A residue receipt was recorded so a later
recycle can clear it once the modal is gone." No later recycle can ever match it. Separately, the
`CC_COMPOSER_SCRUB=off` branch and cc-tui's rc 4 branch record a value truncated to 120 characters
(`%.120s`), which also cannot equal a longer composer. The rc 1 branch is the only correct one: it
records the full `scrub_left`.

**Measured** (`jq 'select(.class=="goal-arm")|.verdict' ~/.claude/logs/handoffs.jsonl | sort | uniq -c`):
47 set, 5 mangled, 3 unverified. All 5 mangled rows say `saw: <unreadable>` (panes 70, 175, 176,
202, 203).

### 3.3 Today, before the fix: rc 2 everywhere, and the residue blocks its own pane's recycle

At the mangle site the scrub's first `composer_content` call has the same 24-row blindness, so it
returns rc 2 and sends nothing. That part is correct fail-closed behaviour; the receipt it writes is
the useless kind from 3.2.

At a later recycle of that pane, the box is still 22 rows tall (the text is still there), so the
gate reads UNKNOWN. That means rc 2: refuse, defer, file a retry ticket. **A mangled long goal in a
narrow pane therefore blocks every self-recycle of that pane until a human clears it.** That includes
the lead in pane 203, whose own plan has it recycle or close after the land.

### 3.4 After the fix: what would happen instead

**Measured**, by replaying the evidence screen through the stub `/tmp/gar/it2stub`:

| `composer_content` version, 24-row default | rc | content |
|---|---|---|
| HEAD (`git show HEAD:scripts/handoff-fire.sh`) | 1 | — |
| working tree (D1) | 0 | 472 stripped chars, the `/goal…` payload |
| `composer_unintended_class` on that content | 0 | `rail-goal` |

- **The arm itself.** The polled read-back now parses the box, `paste_readback_ok` matches the inline
  form (the lead measured the parse equal to the exact payload), and the CR is sent. **No residue is
  created**, so the scrub never runs for this cause. My own `paste_readback_ok` replay is circular
  (it uses the parsed text as the payload), so it only shows that the function accepts this shape;
  the equality proof is the lead's.
- **A real mismatch over a readable box** (for example, an operator keystroke landing during the
  poll window). The scrub can now read the box and runs Ctrl-U rounds. It succeeds (rc 0, receipt
  forgotten) if Ctrl-U kills a whole logical line. **Unmeasured:** whether Ctrl-U kills a logical
  line or a visual row in a wrapped composer. The 2026-09-09 scrub probe tested a one-row `/goal` at
  100 columns. If it is per visual row, a 22-row goal needs at least 22 rounds against the bound of
  12. The scrub then returns rc 1 and records the full remainder (a correct receipt), and the recycle
  gate finishes the job. No CR is ever sent on this path. Nothing on the scrub path sends a CR; only
  `paste_readback_ok` passing does.
- **A real modal** (the fail-closed case). D1 condition (iii) requires a `❯` row directly under the
  top rule, so a modal still reads UNKNOWN. The scrub returns rc 2, nothing is typed, and the
  `<unreadable>` receipt from 3.2 is written again. **That residue is still never cleared by the
  recycle gate.** Once the modal is answered the box is readable but does not match the receipt, so
  the gate treats it as a **foreign draft**. After 180 s it pages the desk with "RECYCLE BLOCKED… NOT
  this rail's own residue", which is a false statement, and refuses. Only the limit-recover precheck,
  through its `rail-goal` re-receipt, or a `cc_tui_submit` caller would clear it.
- **Leftover residue already on disk** (panes 202 and 203 today, plus any earlier ones not yet
  cleared). Once the fix is deployed, the recycle gate reads those boxes as foreign drafts, for the
  same reason, and refuses with a desk page. I could not check whether the text is still there: at
  22:05Z `it2 session read -s 202|203` returned `read unix ->/tmp/kitty-64211: i/o timeout`.

### 3.5 Recommendation

**Clear the residue, do not retry it automatically, and fix the receipt. No new subsystem is
needed.**

1. **Do not add an automatic later re-submit.** A `/goal` starts a turn the moment it is submitted,
   and it installs a Stop-blocker that only `/goal clear` or a met or impossible verdict removes.
   Submitting it at an arbitrary later time, into a session whose state is unknown (finished, about
   to recycle, holding an operator draft), is worse than not arming. The 8-try poll at the arm site
   is the retry. Once the read is fixed it is enough for the measured cause: 5 of 5 mangles were the
   unreadable read. Later, if the `ProposeGoal` tool is adopted (watched by
   `autonomy-sweep.sh 2b-iii-b-propose-goal-arm`), the fired session could arm its own goal from the
   condition in its inbox. That is the right retry path, and it involves no keystrokes.
2. **Clearing is already the design**: scrub at the mangle site, where attribution is free. The
   condition text is not lost by clearing, because it is in the GOAL-ARM inbox message, in the
   `handoffs.jsonl` detail, and in the discard log. Keep that design.
3. **Fix the rc 2 receipt** (a small change inside the existing mechanism). On a scrub rc 2, record
   the **expected stripped payload** (the `want` from `paste_readback_ok`) instead of
   `$FIRE_PASTE_LAST_READBACK`. Better still, have `composer_residue_is_ours` accept the same forms
   `paste_readback_ok` accepts (inline, or the tail of at least 64 characters). Then, once the modal
   is gone, the recycle gate can attribute and scrub it. That is what the scrub note already
   promises. Also stop recording `%.120s`-truncated values on the scrub-off branch.
4. **Pass the scrub outcome out to `arm_goal`.** For example, set an out-parameter like
   `FIRE_PASTE_SCRUB=scrubbed|receipted-unreadable|receipted-stuck`. Today `arm_goal`'s rc 4 stderr,
   its ledger detail and its inbox message all say the text "sits UNSUBMITTED" and "press Enter to
   arm it", even when the scrub has just cleared it. After the fix that will be the common rc 4
   outcome. If the operator follows the message after a successful scrub, Enter submits an empty
   composer, a no-op, and the user is misled.
5. **Clear the existing debris before the fix goes live.** Panes 202 and 203 hold `/goal` text the
   fix will read as foreign drafts. A human presses Enter (to arm, if wanted) or Ctrl-U in each pane
   before the lead self-recycles. The 7 `<unreadable>` receipts are inert and can be deleted, which
   the operator should do; this slot deleted nothing.

---

## Q4: who is told today

| Audience | Fresh fire (`--goal`, arm in the foreground fire process) | `--recycle` (arm in the detached watcher) |
|---|---|---|
| **Firing pane's stderr** | `⚠ goal NOT armed — post-paste read-back did not match, CR NOT sent; the /goal text sits UNSUBMITTED in pane $pane's composer. goal-arm verdict=mangled reason=readback-mismatch` (~8508), preceded by `⚠ verified paste MANGLED — 8 read-back(s) saw '<unreadable>' … CR NOT sent. The scrub was NOT attempted …` (~4699). | Goes to the watcher log only. The firing session **is** the one being replaced, so no one reads it (handoff-fire.sh ~4674-4676 says this outright). |
| **Firing session's transcript** | **Yes, measured.** Session 247fdf36 (`close-verdict-first`, the session that fired panes 202 and 203) has both lines in Bash `tool_result`s at 18:17:40Z and 18:27:41Z (`jq` over its transcript). It relayed them to the operator in its reply ("No goal armed… If you want the goal armed there, click pane 202 and press Enter"). | No. |
| **Operator** | Only if the firing session chooses to relay it, as 247fdf36 did. No page, no alarm. | Nobody, unless the fired session relays it. `hf_alarm` and the desk page are never called on any goal-arm verdict. |
| **Ledger** | A `handoffs.jsonl` row: `{class:"goal-arm", verdict:"mangled", detail:"post-paste read-back mismatch for pane N; CR withheld, paste left unsubmitted; saw: <unreadable>"}` (`emit_goal_event`, ~863). Nothing consumes it automatically. | Same. |
| **Fired session** | A cc-notify inbox line, ~8510 (exact text below). **Delivered to its context, measured**: the 203 lead transcript (bd0889f1) holds it inside a "📬 Peer mail arrived while you were idle — delivered by the inbox watcher" system-reminder. `~/.claude/mailbox/{202,203,175,176}.md` each hold one GOAL-ARM line, 70 holds 3, 25 holds 2. | Same. |

The exact mangled-path inbox text (handoff-fire.sh ~8510; the only `GOAL-ARM MANGLED` string in the
repo outside this research dir):

> `GOAL-ARM MANGLED (no harm done): a /goal paste landed in your composer but the read-back did not match, so it was NOT submitted. If the composer shows only the /goal line, press Enter to arm it; otherwise clear the composer and submit exactly: /goal $cond`

### What is missing

1. **The fired session cannot act on its message.** It is written for a human ("press Enter",
   "clear the composer and submit"). A model has no keyboard, and `/goal` is a TUI built-in it cannot
   invoke itself. Unlike the ABSTAINED text (~8515), it does not say "You are running WITHOUT the
   goal backstop: … drive the brief to its stated end state yourself", and that is the one
   instruction the session can follow. "(no harm done)" also understates the cost: until a human
   acts, the residue blocks this pane's recycle (3.3), and any operator keystroke into the pane
   appends to the `/goal` and submits a hybrid condition.
2. **On `--recycle`, no human is told at all.** The firing session is gone, there is no desk page,
   and the ledger row has no reader. This is the same "fail-loud into a log nobody reads" shape the
   code comments name for the recycle-blocked case, which they fixed there with a desk page and did
   not fix here.
3. **The messages say the text is still there even when the scrub removed it** (Q3.5 item 4). After
   the fix that will be the usual rc 4 outcome.
4. **The contract in the docs is out of date.** commands/handoff.md § Autonomous fire item 1 (line
   207) lists `goal-arm verdict=set|unverified|abstained`. The code also emits `held`, `mangled` and
   `unreachable`. goal-in-handoff-2026-08-08.md §3.2's fail-closed table has no row for "paste sent,
   read-back mismatched, CR withheld". The intended contract ("the fire still succeeds; the session
   has its brief and is working", "read back, never claimed") **is** kept: no CR without proof, and
   the brief was delivered.

Suggested remedy for Q4: reuse existing mechanism only. Rewrite the rc 4 inbox text so it is
truthful about the scrub outcome and carries the ABSTAINED-style "you are running without the goal
backstop; drive to the end state yourself" line. On the recycle path, page the desk once
(`cc-notify --role desk`, as the RECYCLE BLOCKED branch already does). Add `held|mangled|unreachable`
to handoff.md line 207 and a mangled row to the §3.2 table.
