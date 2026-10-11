# Critic: refutation pass over the five slots, and one integrated design

Worktree `peer-mail-headline` @ 110ea9a64, 2026-10-11. Read-only toward the repo code, `$HOME/.claude`,
every settings file and every mailbox, `.seen` and `.acked` file. Nothing was sent, woken or acked. No
bats suite was run (the suites drive cc-notify), so every test verdict here is **static**.

Scratch scripts are outside the repo in `/tmp/critic-pmh/`:
- `corpus.py`: a read-only pass over the 1,010 live `~/.claude/mailbox/*.md` files.
- `t0_score.py`: re-scores titles from the title slot's own judgment files in `/tmp/slot-title/`.

Every number is labelled **measured** (with the command) or **estimated** (with the method).

**Citation base.** Every `file:line` cites the committed HEAD 110ea9a64. During this run another actor
began uncommitted edits in this worktree:
- `bin/cc-notify`, about +31 lines above :1146;
- `hooks/mailbox-drain.sh`;
- `hooks/mailbox-wake-arm.sh`;
- a new `hooks/lib/mail_headline.py`.

So working-tree line numbers have shifted (for example, the cc-notify write is now at :1177). §7 compares
that in-progress diff, read without modification, with this design.

## 0. Verdict per slot

| slot | recommendation | verdict |
|---|---|---|
| compat | encoding A `[from] [@v1;k=v] body`, rules R1-R4 | **Stands, with three amendments.** R3's stated reason is refuted (§1.3). A forgery hole needs a rule R5 (§1.4). The census misses one constraint on drain edits (§1.2). |
| identity | pane and title captured at send from the registry row plus the transcript tail; `⟦…⟧` delimiter; capture even under `--from` | **The capture stands. The delimiter is rejected** (§1.5). It also needs a stale-row guard that costs O(1) (§5.2). |
| rewake | no per-wake `rewakeSummary` for a settings hook on 2.1.293 | **Backed by code-reading evidence, but the live run was never done** (§2). **Moot for the goal anyway**: the drain re-delivers 13 of 14 woken lines 1-35 s later, with its own operator line (§2.3). |
| title | algorithm A4.1, plus optional `--subject` written as ` ¶ ` | **Counts reproduce exactly. The two conclusions drawn from them do not.** Out of sample, frozen A4 does not beat the 72-character head (A0). The "7-day" corpus is mislabelled. A rule built from A0 plus four prefix strips ties A4.1 (§3). ` ¶ ` is rejected in favour of a meta key. |
| lag-ack | flag lateness at origin lag ≥ 10 min; ack once per delivery in chat | **The threshold stands; its numbers reproduce. The ack rule can double-fire and stack up** (§4). It is amended to: drain-only, at most one line per assistant text block, and disposition only. |

## 1. Check 1: does the encoding leave every reader working? (an independent census)

### 1.1 Method

I grepped `bin hooks scripts lib skills commands autonomy bus core tools statusline.sh launchd agents
prompts templates` for `mailbox_file|mailbox_peek|mailbox_take|MAILBOX_DIR|/mailbox/|mailbox_dir|CC_MAILBOX_DIR`,
excluding `*.md`. That gave **40 code files** (measured). Every file that compat's table (rows 1-21) did not
cover was opened at its hits. I also grepped:
- the callers of `mailbox_take*` and `mailbox_peek*`;
- `*.py`, `*.js` and `*.ts` files mentioning mailbox;
- tests that compare a whole inbox line or grep a subject's source.

### 1.2 Readers and constraints the compat slot missed

None of these breaks under A. One of them constrains where the new code may go.

- **`tests/mailbox-drain.bats:1116-1140` is a source-anchored mutation control.** It requires:
  - exactly one `^_shown="$body"$` (drain:770) and one `^_block=…"$_shown"` (drain:834);
  - every other `_shown` to sit between :770 and the `esac` at :833.

  It cuts that region out with awk and asserts `grep -c '_shown' == 0` on the result. If a headline
  renderer touches `_shown` anywhere else, this test goes red. **Constraint: compute headlines from
  `$body` into a new variable. Leave :770-:834 alone.**
- `hooks/waiting-recycle.sh:1254-1262` dumps `tail -40` of the box into the recycle dossier. Cosmetic: the meta
  shows up there verbatim.
- `bin/cc-wake-headless:155-160` tells the model to `cat` the box, so the model sees meta in the raw text. This is harmless.
- `statusline.sh:146-152` counts lines. `scripts/lib/restore-heartbeat.sh:245` reads `.watching` only.
  `bin/cc-escalations:179` and `hooks/operator-readout.sh:496` list dead-letter files without parsing lines.
  `scripts/headless-precondition-probe.sh:150-158` is path only. None of these is affected.
- **A gap in compat's own row 8.** `bin/cc-inbox-guard:378-382` takes both the age stamp and the class tag
  from the line start, so a forwarded page gets `tag=forwarded:XXXX`. That loses the urgent deadline for
  every forwarded `SUPERVISOR PAGE` or `permission` line. This bug exists today and is independent of the
  encoding. When the first-bracket readers are fixed, the guard must take the **tag from the origin** but
  keep the **age from the outer stamp**. The guard measures time unread in *this* box, so origin age would
  make every adopted old line instantly overdue.

No test compares a whole inbox line for equality (measured: grep of `tests/*.bats` for `.md")" =` and `-x`
patterns found only non-mailbox files). This agrees with compat.

### 1.3 R3's rationale is refuted by the fixtures

Compat's R3 says "no meta on `--from`" is needed to keep `cc-notify.bats:232` and `restore-note.bats:68` green.
In both tests the sender **has no registry row**, so a rule of "emit only when the own row resolves" already
emits nothing:
- `cc-notify.bats` setup (:12-60) points `CC_REGISTRY_DIR` at a temporary directory. The only row in it is the
  *target* `AAAAAAAA-…`. The :229 test exports no own pane, so `own_uuid` is the runner's leaked
  `ITERM_SESSION_ID`, which has no row there.
- `restore-note.bats:23` runs `unset KITTY_PID KITTY_LISTEN_ON KITTY_WINDOW_ID ITERM_SESSION_ID CC_PANE_ID`, so
  `own_uuid` is empty.

So R3 throws away pane identity on every `--from` send from inside a registered pane for no test benefit. The
affected senders are `cc-bus`, `cc-announce`, `handoff-fire`, `recycle-watcher`, `desk-invariant` and
`cc-resume-debt` (identity slot §1). R3 is replaced by the emission rule in §5.2.

The same reading exposes a **hermeticity hole that new tests must seal**. `cc-notify.bats` setup leaks the
runner's `ITERM_SESSION_ID` and `CLAUDE_CODE_SESSION_ID`, so whether meta is emitted depends on the runner.
Seal both, plus `KITTY_WINDOW_ID` once the fallback below lands (lesson: *Nth source un-seals old fixtures*).

### 1.4 New hole: forged identity (rule R5)

A reader that trusts `[@v1;pane=…]` right after `[from] ` can be fed a forgery in two ways:
- **A body that begins with `[@v1;pane=16;title=lead]`.** Today cc-notify passes the body through untouched
  (`bin/cc-notify:1095` only maps CR/LF).
- **A `--from` value that begins with `forwarded:` or contains `]`.** `--from` is taken raw at
  `bin/cc-notify:566-567`. Every chain-stripping reader (`_mbx_origin` lib:912-914, drain:786) then
  attributes the line to whatever "origin" the body claims.

Measured with `corpus.py`, over 14,725 live lines:
- 0 bodies begin with `[@`;
- 0 direct bodies begin with `<ISO> [`;
- 0 lines contain `[@`, `⟦` or ` ¶ `.

So a writer-side escape costs no existing traffic.

### 1.5 The rejected alternatives

- **Identity's `⟦p= s= t=⟧`.**
  - The reason given for it is a misreading. In drain:786, group 3 `(\[[^\]]*\] )?` is the `[from]` bracket
    itself, not an optional second tag, so a `[@…]` token cannot be swallowed there.
  - It also gains nothing. Once a test registers its sender, the nine `grep -q '\] <body>'` assertions
    (cc-notify.bats:134, 142, 152, 163, 282, 525, 599, 1190, 1265) need `] ` directly before the body.
    `[@…] ` keeps that true; `⟧ ` does not.
- **Title slot's `<subject> ¶ <body>`.** This is a second encoding *inside* the body. Readers would have to
  guess whether a ` ¶ ` within the first 120 characters is the sender's subject. The subject belongs in meta
  as `subj=`.

### 1.6 Atomicity cost of a longer line

Lesson: *Append atomicity ends at the stdio buffer*, which is 4,096 B.

Measured (`corpus.py`):
- 33 of 14,725 live lines already exceed 4,096 B, so those are already non-atomic.
- 13 lie within 160 B of the boundary, so a maximal meta token could push them over: **0.09% of lines**.

Keep the 160-byte token cap. Write the line with one `printf`, as today.

## 2. Check 2: is the rewake conclusion evidence or inference?

### 2.1 What it rests on

It rests on a **static read of the 2.1.293 bundle** (slot-rewake §1-§4). The report quotes the completion handler:
- the stdout JSON scan runs only `if (Y)`, where `Y` is the pluginId;
- it is gated by `vye(Y)`, the official-marketplace check;
- `Ye = Ie ?? G ?? "Stop hook feedback"` picks the summary.

That is direct code evidence, not inference. It is consistent with:
- the repo's own 2.1.219 read, where the summary came from config only
  (`docs/research/mechanical-wake-asyncrewake-2026-07-29.md:243-251`);
- the W0 live probe, in which the config summary rendered as `⏺ W0 probe: mailbox wake`
  (same doc :128-129).

### 2.2 What is not established

- **The live negative-control run was never done** (slot §6). By the repo's own lesson (*Unrun arm goes in
  the verdict*), the verdict should read "settings-hook `rewakeSummary` is static **per the 2.1.293 code;
  the live probe is unrun**".
- **I could not re-read the cited byte offsets.** A bounded seek-read of the binary was **denied by the
  permission classifier**, and I did not work around it.
- **The public web is silent.** A web search found nothing on `rewakeSummary` or `asyncRewake`; the fields
  are `@internal`.

The conclusion is therefore single-source code evidence: not refuted, not independently re-verified.

### 2.3 Why it does not block the goal (measured)

The wake path *peeks*: it never advances `.seen` (`bin/cc-await-ping:1391`, `mailbox_peek_from` at :1570).
So the drain re-delivers every woken line.

Measured on the lag slot's `rows.json`: of the 14 wake-delivered lines, **13 were delivered again by the
drain in the same session, 1-35 s later**:
- 7 idle wakes were followed by a `UserPromptSubmit` drain within 1-2 s;
- 3 mid-turn wakes were followed by a `PostToolUse` drain within 7-35 s;
- 1 woken birth turn was followed by its `SessionStart` drain 2 s later;
- the 14th line was surfaced by a drain first and by the wake 6 s later.

Each drain emits its own `systemMessage`. So the per-mail headline reaches the operator through the drain
seconds after the static `● 📬 peer mail` row. **Leave the asyncRewake summary static.**

The drain *firing* on the woken turn is measured. That its `systemMessage` *renders* on that turn rests on the
repo's 2026-07-26 claim at drain:837-845 and was not observed here.

## 3. Check 3: are the title numbers measured?

- **The tallies reproduce exactly** (measured: inline python over `/tmp/slot-title/judge_final_{sample,holdout}.txt`):
  - sample: A0 54/80/134, A2 12/16/28, A4 55/87/142, A4.1 57/87/144;
  - holdout: A0 18/37/55, A4 15/41/56, A4.1 19/42/61.

  The judgments themselves come from one unblinded judge (slot §8).
- **Out of sample, the derivation does not beat the trivial baseline.** These paired tests are measured, but
  the slot never reported them (`t0_score.py`):
  - On the 70-line holdout, frozen A4 against A0 gives 6 A4-only usable lines and 5 A0-only: **exact
    two-sided p = 1.0**.
  - On agent lines alone it gives 5 against 1, p = 0.22.
  - On automated lines A4 is worse: 15/20 against A0's 18/20.
  - The slot's "real but modest gain, p ≈ 0.008" pools the 100 tuning lines, which A4 and A4.1 were fitted to.
- **The "7-day" corpus is not 7-day mail.** `load.py` selects *files* with mtime under 7 days (slot §1). Over
  those 6,908 lines (measured):
  - all 2,742 `SUPERVISOR PAGE` lines have origin stamps no later than **2026-09-24**;
  - by origin stamp, the last 7 days hold **0** SUPERVISOR PAGE and **0** REAPER SURFACE lines among 1,596.
    They do hold 421 cc-await-ping WAKE-PATH lines and 493 lines containing HANDOFF-PING.

  So the class table, the 85%/15% mix and the "about 93% weighted" estimate describe a stale population.
  The proposed `cc-reaper --subject` fix targets a class that sent nothing in the last 7 days.
- **A minimal rule ties A4.1.** T0 is A0 run on the stripped body, with UUIDs shortened to 8 hex and up to four
  passes stripping leading `[for:…]`/`[restart]`/`[lead]`/`[restore]`, status glyphs and
  `HANDOFF-PING <slug>: `. Measured with `t0_score.py`:

  | rule | sample (auto/agent/all) | holdout (auto/agent/all) |
  |---|---|---|
  | T0 | 57/87/**144** of 160 | 19/41/**60** of 70 |
  | A4.1 (as reported) | 57/87/144 | 19/42/61 |

  Of the 230 lines, 196 inherit the slot judge's verdict because T0's output is identical to A0's or A4.1's.
  I judged the other 34 on the slot's rubric (second judge, not blind); 31 were U and 3 were N, those 3
  being buried-lede lines that A0 and A4.1 also missed.

  Cost: T0 0.043-0.072 ms/line against A4.1 0.058-0.208 ms/line, over the 1,842-line working set across two
  runs at load 339 and 566. More importantly, T0 needs no sentence splitter and no quote-depth state, so it
  fits in BSD awk and the drain avoids a python fork.

## 4. Check 4: can the ack design flood the chat?

The slot's rule: one ack line per delivery holding agent mail, requested from the drain context, from the
wake's stderr and from the cc-wake frame. It fails four ways.

1. **Double request from wake plus drain.** Measured: 13 of 14 wake-delivered lines were re-delivered by
   the drain 1-35 s later (§2.3). In the 3 mid-turn cases (7-35 s gap), the model may already have written its
   ack when the drain asks again. Dedupe is left to the model's memory ("skip a message you already
   acknowledged"), which does not survive compaction.
2. **Several deliveries per text block.** PostToolUse drains run per tool call while mail is pending, up to
   20 lines each (drain:33). "Start your next message with ONE line for this delivery" asks for one line
   *per delivery*. Three deliveries before the next text block yield three lines.
3. **Adoption bursts.** A SessionStart adoption can surface up to 200 lines (`CC_MBX_ADOPT_MAX_LINES`,
   drain:375), most of them predecessor backlog. The slot measured 72 lines with a median age of 32 h. "Name
   every agent sender" turns that into one very long line.
4. **Classifier.** The slot's automated-sender list includes `claude` and `claude-*`. The identity slot
   measured real agent mail (`[lead] …`, HANDOFF-PING) signed with those account names when the pane had no
   row. Acking only "agent" mail would silently skip it.

The rates are reproduced and are not the problem:
- the drain noise filter matches **0 of 455** direct 72-hour lines (measured: `corpus.py`, the same 455 as the slot);
- 15 empty-body wakes occurred in 15 distinct sessions (measured from the slot's `rows.json`);
- the slot measured 0.81 agent deliveries per active hour (median 0.5, p90 3.75, max 5.2).

The flood risk is in the multiplicity rules, and §5.5 fixes them.

## 5. Integrated design

### 5.1 Encoding: A, amended

```
line  = stamp SP "[" from "]" SP [ meta SP ] [ "[for:" key "]" SP ] body
meta  = "[@v1" *( ";" mkey "=" mval ) "]"      ; mkey ∈ {pane, sid, title, subj, by}; readers accept [@v<digits>
```

- **R1 (placement), from compat.** Meta goes after `[from] ` and before `[for:…] `. Only `bin/cc-notify:1146` and
  `:1514` write it. The other writers never emit meta: the direct writers at `cc-await-ping:1014/:1057` and
  the migrate prefix at lib:722-725, which copies the origin line verbatim.
- **R2 (escaping), from compat.** In values, `%`, `[`, `]`, `;`, `=`, C0 and DEL are written as `%XX`; CR, LF and TAB
  become a space first. Caps: title 48 bytes, subj 80, whole token 160. Truncate on a UTF-8 boundary and never
  inside a `%XX`. Do it byte-wise under `LC_ALL=C`, which is safe because every escaped byte is ASCII.
- **R3′ (emission).** Replaces compat's R3. See §5.2.
- **R4 (defang), from compat.** Percent-encode the first byte of each reserved word in a value:
  `HANDOFF-PING`, `HANDOFF-HUSK-PANE`, `SUPERVISOR PAGE`, `REAPER SURFACE`, `PERMISSION-PENDING`, `WAKE-PATH`,
  `desk-sweep`. These are the needles at drain:676/:709/:855, cc-mail:63 and cc-await-ping:1395-1403.
  Keep the list as one constant beside `hooks/lib/handoff-ping-terminal.sh`.
- **R5 (anti-forgery), new.**
  - Sanitise FROM: map `[`, `]` and newline to `_`, and refuse a leading `forwarded:`.
  - If the one-line body begins with `[@` or with `^[0-9]{4}-[0-9]{2}-[0-9]{2}T`, prefix it with one literal
    escape character (for example `\`).

  0 live lines are affected today (measured, §1.4).
- **Sent time and lag need no field.** The origin stamp survives forwards byte for byte (identity slot §5,
  scratch two-hop test).

### 5.2 Identity rule

- **Own key.** `CC_PANE_ID → ITERM_SESSION_ID → KITTY_WINDOW_ID`, stripped to the part after the last `:`. This is
  the order `hooks/session-register.sh:173` and `bin/cc-wake:187` already use; today cc-notify:581 lacks the
  kitty fallback.
- **Row.** `$CC_REGISTRY_DIR/<key>.json`.
  - `pane` = `.paneUUID`. Never parse it out of `.name`.
  - `sid` = the first 8 characters of `.session_id`.
  - `title` = the newest `customTitle`, else `agentName`, else `aiTitle`, from the last 64 KB of
    `~/.<row.account>/projects/*/<session_id>.jsonl`. Extract it with `jq -r` or one python call, never
    `[^"]*`.
- **Emit only if** the row exists, `.session_id` is non-empty, and `$CLAUDE_CODE_SESSION_ID` is either unset
  or equal to `.session_id`.
  - This O(1) guard rejects a reused kitty window id and a background fork that outlived its session.
  - Measured once (n = 1): in this worker's Bash, `CLAUDE_CODE_SESSION_ID` equals `cc-registry/233.json`'s
    `session_id`.
- **`--from` does not suppress meta.** It adds `by=flag`, so the renderer can show the voice and the seat.
- **Best effort.** The whole capture gets a budget of about 200 ms. The identity slot measured 30-131 ms
  under load ~850 for jq plus tail plus grep. A miss drops `title` (or the whole token) and never fails a send.
- **Forwards.** Readers strip `(\S+ \[forwarded:[^\]]*\] )*` and then parse the inner `[from] [@…]`, so the
  original sender survives any depth of forwarding.

### 5.3 Title rule: T0, plus an optional `subj`

- If meta carries `subj`, the title is that value. It is set by a new optional `cc-notify --subject <s>`, which
  is never required.
- Otherwise the title is T0 on the innermost body, after the chain, the meta and `[for:…]` are removed:
  1. Collapse whitespace.
  2. Shorten UUIDs to 8 hex.
  3. Up to 4 times, strip a leading `[for:…]`/`[restart]`/`[lead]`/`[restore]`, a status glyph from a literal
     alternation (BSD awk is byte-wise, so no bracket class), and `HANDOFF-PING <slug>: ` using drain:716's
     slug charset.
  4. Cap at 72 at a word boundary with `…`.
  5. If the result is empty, fall back to the raw head.
- Measured: 144/160 and 60/70 (§3). Pin it with a bats fixture built from real lines of each current class.

### 5.4 Lag threshold

- Origin lag = surfacing time minus the **innermost** stamp, computed by `_MBX_AWK_ORIGIN` (lib:894-915) when
  the drain or fold emits.
- **Flag "late" at ≥ 10 min**, tunable as `CC_MAIL_LATE_MIN=10`. Measured (my recompute of `rows.json`):
  - 8 of 175 surfaced lines are at or above 10 min, ranging from 26 min to 21.1 h;
  - nothing falls between 9.9 and 26 min;
  - more than 2/5/15/30/60 min: 22/15/8/7/5.
- Always show `sent HH:MM`. Add the date when the day is not today, and the offset when it differs from the
  drain's own `%z`.
- Above the threshold: `N min late` up to 89 min, `N h late` up to 36 h, then `N days late`.

### 5.5 Ack rule

- **The operator's headline is deterministic, and the model's ack is optional and short.** The drain's
  `systemMessage` carries items (1)-(3) of the goal by itself. The model adds only a disposition.
- **Where.** The ack instruction goes only in the drain's `additionalContext` (drain:835) and the stop fold
  (session-continue.sh:1464). Both commit a cursor, so each line reaches them once. It goes **neither** in
  the wake's stderr (`mailbox-wake-arm.sh:211`) **nor** in the cc-wake frame, because the drain re-delivers
  those lines 1-35 s later (13 of 14, measured).
- **When.** Only if the delivery holds at least one agent-written line whose origin age is under
  `CC_DRAIN_STALE_FORWARD_H` (24 h).
  - Agent-written means: meta present without `by=flag`, **or** the body contains `HANDOFF-PING`, **or** the
    sender is not on the daemon-label list.
  - Never classify on the `claude*` account fallback alone.
- **What.** At the start of the next assistant text, write **at most one line per text block**, merging
  everything delivered since the last 📬 line: `📬 <pane>: <acting on it now | after <step> | needs you: <decision> | noted>`.
  - Entries are joined by `; `, at most 3, then `+N more`.
  - The drain prints the pane labels to copy, so the model never invents a pane number.
  - Never acknowledge with cc-notify.
- **Bound.** At most one line per assistant text block. Upstream delivery rate (lag slot, `fire.py`,
  measured): 0.81 per active hour, p90 3.75.

### 5.6 Operator headline (the `systemMessage` body)

```
📬 pane 225 · /limit-recover pane recovery gap ▸ DONE — root causes for 5 unrecovered panes; top one is mine · sent 22:59 · 26 min late
📬 ⚙ recycle-watcher (pane 77) ▸ RECYCLE DEFERRED: the draft in this pane's composer was not… · sent 23:02
📬 +2 more · 4 automated (cc-await-ping ×3, lead-supervisor ×1) — full text: cc-mail
```

- Show at most 3 agent headlines. Show the session title at most 32 characters wide. Count automated lines; do
  not name each one.
- Legacy lines without meta show the raw origin `[from]`, which is no longer `forwarded:XXXX`.

### 5.7 Files to change

| file | change |
|---|---|
| `bin/cc-notify` | :581 add the `KITTY_WINDOW_ID` fallback. :555-575 add `--subject`. After `resolve_from` (:1090) build `META` (§5.1-5.2) and apply R5 to FROM and `MSG_1LINE` (:1095). :1146 becomes `'%s [%s] %s%s\n'` with `$META`. :1514 becomes `'%s [%s] %s[for:%s] %s\n'`. :1101 fix the stale `resolve_from` line citation. |
| `hooks/lib/mailbox-pending.sh` (or a new sibling `mailbox-headline.sh`) | One awk renderer `mailbox_headline` that reuses `_MBX_AWK_ORIGIN`: chain strip, meta parse and `%XX` decode, T0, sent and lag, agent/automated class. One reserved-word constant for R4. The shared ack sentence. |
| `hooks/mailbox-drain.sh` | :851-866 build `msg` from `mailbox_headline "$body"` (§5.6). Keep the existing `_names` digest as the fallback when the lib is absent. :835 append the ack sentence only when the agent count is above 0. **Do not touch :770-:834** (mutation control, §1.2). Update the stale 751-per-12h comment at :840. |
| `hooks/session-continue.sh` | :1470-1473 build `_mfrom`/`_sysmsg` with the same renderer. :1464 add the shared ack sentence. |
| `bin/cc-mail` | :64 parse the chain and meta. Time column from the origin stamp. :100 sender column `pane N (title)`. `--from` also matches pane and title. Keep meta out of the body preview. |
| `bin/cc-inbox-guard` | :378-382 take the class tag from the origin `[from]` after the chain; keep the age from the outer stamp (§1.2). |
| `bin/cc-await-ping` | No change needed: R4 protects `_line_class` (:1395-1403). Optionally source the R4 constant. |
| `bin/cc-thread` | :52-58 optionally skip `[@…] ` before the 168-character cut. |
| `hooks/mailbox-wake-arm.sh`, `bin/cc-wake`, `migrations/*`, `settings*.json` | **No change.** The asyncRewake summary stays static (§2). |
| `tests/cc-notify.bats` | In setup, seal `ITERM_SESSION_ID`, `KITTY_WINDOW_ID` and `CLAUDE_CODE_SESSION_ID`. New cases:<br>• meta with a registered sender, plus a pinned session id and a transcript title fixture;<br>• no meta when the row is absent or the session id mismatches;<br>• `--from` gives `by=flag`;<br>• escaping of `]`, `;`, `=`, `%` and newline;<br>• R4 defang leaves `_line_class` on the body's class;<br>• R5 on a forged body and a forged `--from`;<br>• the `[for:]` order on the desk tee. |
| `tests/mailbox-drain.bats` | Headline from a 2-hop forwarded line shows the origin pane and title. Lag flag at 9 and 11 min. Automated lines counted, not named. Ack sentence present only when agent mail is present. Custody discharge unchanged when meta precedes the ping. |
| new `tests/mailbox-headline.bats` | T0 against real lines of each current class (WAKE-PATH, HANDOFF-PING, SESSION DEATH, RECYCLE…, cc-lr). |

## 6. Residual risks (each stated, none hidden)

- **Test verdicts are static.** No bats run was allowed. Run `tests/cc-notify.bats`, `restore-note.bats`,
  `mailbox-drain.bats`, `mailbox-forward.bats`, `mailbox-session-key.bats`, `cc-await-ping.bats` and
  `payload-lint-tool-parity.bats` before landing.
- **Rewake** rests on one code read with its live arm unrun, and I could not re-verify it (permission denied).
  The design does not depend on it.
- **T0 judgments.** 34 of the 230 are mine, the rest the slot judge's, and neither judge was blind. The
  holdout is n = 70.
- **The 10-minute threshold** rests on 8 lines above it. Keep it tunable and re-measure on a wider window.
- **Session-id guard.** The `CLAUDE_CODE_SESSION_ID` equality is measured once. If a future CC stops exporting it, the
  guard degrades to row-only, which is today's behaviour.
- **Classifier drift.** The daemon-label list and R4's word list are pattern lists. Pin one bats fixture per
  sender family.
- **Atomicity.** 0.09% of lines move closer to the 4,096 B non-atomic boundary (§1.6).
- **Not checked here:**
  - the title-capture cost when `projects/*/` holds many transcripts (the glob over `projects/*`);
  - headless rows, whose pane is a non-numeric `CC_PANE_ID`. Render them as `headless <8>`.

## 7. The in-progress implementation against this design

This compares the uncommitted working-tree diff, seen at the end of this run. It is a snapshot of edits
another actor is still making, and I read only `git diff` and parts of `hooks/lib/mail_headline.py`. The
encoding matches §5.1 (`[@v1;pane;sid;title;subj]` after `[from]` and before `[for:]`, R4 word list,
emitted under `--from`). Where it diverges:

1. **The ack goes in both the wake and the drain.**
   - Where: `mailbox-wake-arm.sh` (new `wake` mode) prints the ACK sentence; `mail_headline.py` mode `wake`
     prints `ACK` (around :425-428). The drain `context` mode prints it as well.
   - Why it matters: this is exactly the double-request path in §4.1. 13 of 14 woken lines are re-delivered
     by the drain 1-35 s later (measured).
   - Fix: drop ACK from `wake`.
2. **The ACK text is per delivery.** "Begin your next reply with ONE line for this whole delivery"
   (mail_headline.py:328-333) is the multiplicity problem in §4.2. Reword it to one line per text block,
   merging everything since the last 📬 line.
3. **There is no stale-row guard.**
   - Where: `_meta_pane="${own_uuid:-${KITTY_WINDOW_ID:-}}"` takes the row with no check of
     `CLAUDE_CODE_SESSION_ID` against `.session_id`.
   - Why it matters: a reused window id or an orphaned fork would sign as the pane's new tenant.
   - Fix: add the §5.2 guard.
4. **python forks per hook.**
   - Where: the drain now runs `python3 mail_headline.py` twice per delivery (`context` and `digest`),
     after the existing stale-forward python. cc-notify runs one more per send. The `python3` call has no
     time bound, though the comment says "never delays the send".
   - Cost: python start-up was not measured here, so it is unpriced at load ~800.
   - Fix: either measure it, or move to the awk renderer in §5.3/§5.6; at minimum bound each call.
5. **The meta regex is version-locked.** `META = r"^\[@v1;…"` (mail_headline.py:155) would push a future
   `[@v2;…]` into the body. Accept `\[@v\d+;`.
6. **No R5 is visible in the diff.** cc-notify does not sanitise FROM, and a body beginning with `[@` passes
   through (§1.4). I did not read every line of `mail_headline.py`; its `CLASS_WORDS` defangs only the
   *values*.
7. **The drain's mutation control is respected.** The new `_heads` code sits after :834 and never reads
   `_shown` (§1.2).
8. **The digest is narrower than §5.6.** It is `digest … | head -1`, a single line that carries the first
   message's headline. §5.6 asks for up to 3 agent headlines plus a count.
