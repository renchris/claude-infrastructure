# Map: `bin/cc-decide`, its classifier, and every consumer of decision packets

Slot: cc-decide · ruling d610f8473106 · 2026-10-24 · read-only investigation (nothing under `~/.claude` written).
Measured numbers name the command. "Estimated" numbers name the method. Line numbers are for this worktree at
`958b23030`.

## 0. Findings that change the design (read these first)

1. **The same question had already been ruled 9 days earlier, and nothing surfaced it.** Packet `eb3dbe1e5e94`
   (class B, created 2026-10-14T03:19Z by session 7046d8d0) asked: "Keep looping until a round confirms nothing at
   all before you paste, or paste once a round has no turn and no wrong item…". Its default was
   `"keep looping until dry (the scope as written)"`, with deadline 2026-10-15T15:00Z. It went `expired-actioned`
   at 2026-10-15T15:06:34Z (`jq . ~/.claude/autonomy/decisions/eb3dbe1e5e94.json`). That makes it a standing ruling
   by silence: keep looping. The B13 lead then re-asked the same fork as class C (`e869fac7eb34`, 2026-10-24T02:36Z).
   `grep -c eb3dbe1e5e94` on the incident transcript returns 0. A keyword search at `open` time ranks it first
   among the other packets (9 keyword hits; §6).
2. **When a default fires, the filing session is not told.** The fired default went to the wrong place. The sweep
   filed backlog row `df779857c4ff` ("class-B default fired: keep looping until dry…") under project
   **claude-infrastructure** (the host fallback, because `subject_project` was empty). The row went to a cold cloud
   worker, which closed it with `docs/research/class-b-loop-until-dry-unworkable-2026-10-15.md:1-50` ("unworkable
   as dispatched, and it actuates no change"). Source: `grep df779857c4ff ~/.claude/autonomy/backlog.jsonl`, which
   shows add 15:06:37Z, venue cloud, claim, and done 16:04:17Z. Session 7046d8d0 was never told.
3. **The re-filed class-B packet repeats the same defect.** `b4780d7bb60e` (open, deadline 2026-10-31T23:00Z) has
   `default_effect: ""` and `subject_project: ""` (`jq` on the packet). At the deadline, `autonomy-sweep.sh:589-596`
   will read it as `change` and file another "keep running rounds" row under claude-infrastructure. That is
   estimated from the code path at `:567-597` and the precedent in item 2.
4. **`cc-decide open` never calls the classifier.** Class is whatever the filer passes. The only link to
   `gate-classify.sh` is a comment (`bin/cc-decide:13`). The classifier routes **both incident packets to B**, and
   33 of the 48 open class-C packets to B (measured, §5). It also misses a real money decision (`a247b7288149`
   routes B) and under-detects the checkpoint set by about 70%, as measured in
   `research-pending-implementation-close-2026-10-18/slot-H-gates-recycle.md:85,95`. So the classifier cannot
   serve as a refusal predicate. Any category check has to be declared by the producer.
5. **The rule that sends every held decision to class C dates from the day class C became the only ⛔ sensor.**
   That was 2026-08-07: commit `b08601974` (wrap-ledger reads class C only) and the `CLAUDE.global.md:1000`
   "Corollary — a decision you are holding IS the rung" text from the same day (`git log -S`, §8). The
   B/C semantics in `cc-decide:13-19` were never changed. Only the rule text widened C.

## 1. `bin/cc-decide` end to end (655 lines)

| Lines | What |
|---|---|
| 1-85 | Header and usage (printed by `usage()` at :93 from `sed -n '2,/^set -uo/p'`). Class definitions at :13-19, verbs at :21-55, producer-declared fields rationale at :57-80, exit codes at :84-85 (0 ok, 2 usage or schema refusal, 3 unknown id or not open, 4 recheck inside a research program). |
| 88 | `CC_SHA256` is `/sbin/sha256sum`, with a fallback. |
| 90-91 | Store `DECISIONS_DIR=${CC_DECISIONS_DIR:-~/.claude/autonomy/decisions}` and `IDL=${CC_IDL:-~/.claude/autonomy/idl.jsonl}`. |
| 97-98 | **`mk_id`** = `printf '%s\037%s\037%s' class sid what \| sha256 \| cut -c1-12`. |
| 102-130 | Conviction protocol helpers. `valid_conviction` takes an integer 0..100. `conviction_ask_max` uses `CC_CONVICTION_ASK_MAX`, default 90. `valid_receipt` accepts an existing file or `"<cmd> => <output>"`, both sides non-empty. These helpers are shared byte-for-byte with `bin/cc-backlog:1250-1262`. |
| 140-141 | `CELL`, the TSV pad, which keeps an empty cell from shifting columns (TSV_FIELD_COLLAPSE). |
| 154 | `SFOLD`: an absent or empty `.status` reads as `open`. |
| 157-161 | `log_idl`, a best-effort IDL row `{ts,tool:"cc-decide",verb,id,class,status}`. |
| 163-361 | **`cmd_open`** (§3) |
| 364-390 | `cmd_transition` for `veto` and `action`. Moves open to `vetoed` or `actioned`, sets `.resolved`, and optionally `.evidence` and `.resolved_by`. **It does not check the current status**, so it can re-transition a terminal packet. The file is never deleted. |
| 395-402 | `self_path`, which follows symlinks. |
| 411-492 | `cmd_recheck` appends `{sid,ts,conviction,receipt,recommendation,tier}` to `.rechecks[]` on an OPEN packet. The receipt must be a file outside tmp that contains the id. Refused inside a research program (rc 4). Nothing else changes. |
| 501-506 | `LIST_SELECT`: the one select predicate for `list`. Modes are `all`, `open` (via the fold) and `expiring` (open ∧ B ∧ deadline non-empty). |
| 508-594 | `cmd_list`. `--json` emits the full packets as one array with the status folded. A single jq pass falls back to a per-file loop when a parse error occurs (:555-582). The table mode is :584-593. |
| 615-642 | **`cmd_expire_sweep`** (§4) |
| 644-655 | Requires jq. Verb dispatch: `open|veto|action|recheck|list|expire-sweep|help`. There is **no** `update`, `withdraw`, `reclass` or `supersede` verb (:311-312 says so). |

## 2. Exact packet schema

### 2.1 Written by `cmd_open` (`bin/cc-decide:344-354`)

```
{ id, created (ISO Z, now_iso), class: "A"|"B"|"C",
  session_sid, session_pane_uuid, what_plain, subject_project,
  options: [ {label, outcome_in_operator_terms} ],     # from --option "label::outcome" (:331-339)
  recommendation, default_if_no_veto, default_effect, veto_deadline,
  staged_artifact_path, route_around_taken,
  status: "open",
  conviction: number|null, receipt: string }
```

Every unset string field is written as `""`. Only `conviction` uses null (`--argjson conviction "${conviction:-null}"`, :349).

### 2.2 Added later

- `veto` and `action` add `.status` (`vetoed`|`actioned`), `.resolved`, and optionally `.evidence` and `.resolved_by` (:381-384).
- `expire-sweep` adds `.status="expired-actioned"` and `.resolved` (:635).
- `recheck` adds `.rechecks[]` (:485-486).

### 2.3 Census of the live store

Measured with `jq -r 'keys[]' ~/.claude/autonomy/decisions/*.json | sort | uniq -c`.

The store holds 697 directory entries: 691 `*.json` and 6 non-json side files (`.bak`, receipts). Key counts across the 691 packets:

- 691: `id`, `class`, `status`, `what_plain`, `options`, `recommendation`, `default_if_no_veto`.
- 682: `created`, `session_sid`, `veto_deadline`, `staged_artifact_path`, `route_around_taken`.
- 674: `session_pane_uuid`.
- 633: `resolved`.
- 578: `subject_project`, `default_effect`.
- 500: `conviction`, `receipt`.
- 483: `evidence`.
- 84: `resolved_by`.
- 78: `rechecks`.

The rest are legacy or extra keys:

- `matched` 17, `session_id` 9, `staged` 9, `producer` 6. These come from the `shipland-esc-*` packets written directly by `scripts/ship-land.sh:649-700`, which bypasses `cc-decide open`.
- `unblocks` 6 and `why_gated` 6 (hand-written in July, e.g. `33e4a598de8c`).
- `superseded_note` 1 and `history` 1.

**`options` is not always an object array.** `ship-land.sh:686-690` writes plain strings, and so do some July packets. A jq reading `.options[].outcome_in_operator_terms` errors on 19 files (measured: the jq errors from the §6 simulation).

Census by class and status (measured, `jq -r '[.class,.status]|@tsv' … | sort | uniq -c`):

| class | open | actioned | expired-actioned | vetoed | total |
|---|---|---|---|---|---|
| A | 0 | 3 | 0 | 0 | 3 |
| B | 10 | 30 | 110 | 16 | 166 |
| C | 48 | 451 | 0 | 23 | 522 |

All 48 open C packets and all 10 open B packets carry a `session_sid` and a conviction. All open B packets have a deadline and no open C packet has one (measured). Only 10 packets of 691 carry a non-empty `session_pane_uuid` (measured), so a pane address is not usable as a wake key. The session id is.

## 3. `open` validation rules, per class (`bin/cc-decide:189-260`)

| Rule | A | B | C | Line |
|---|---|---|---|---|
| `--class` ∈ A\|B\|C | ✓ | ✓ | ✓ | :190-193 |
| `--what` non-empty | req | req | req | :194 |
| unknown flag → rc 2 | ✓ | ✓ | ✓ | :185 |
| `--default` | opt | **req** | **refused** | :196, :199-201 |
| `--deadline` | opt | **req, format NOT validated** | opt (unused) | :197 |
| `--default-effect` ∈ change\|no-change | opt | opt | **refused** | :206-214 |
| `--conviction` integer 0..100 when present | ✓ | ✓ | ✓ | :221-223 |
| `--conviction` > 90 refused ("implement it… a class-A packet records a decision you made") | **refused even on A** | refused | refused | :224-229 |
| `--receipt` valid when present | ✓ | ✓ | ✓ | :230-235 |
| `--conviction` + `--receipt` required | — | **req** (ruling aa19d7b7a693, commit 1caac9ceb) | **req** | :253-260, :236 |
| ≥2 `--option` | — | — | **req** | :236-245 |
| `--project`, `--session-pane`, `--staged-artifact`, `--route-around`, `--recommendation` | unvalidated | unvalidated | unvalidated (the header :19 says C "carries a staged artifact", but it is not required) | — |
| `--id` | overrides `mk_id`. Unvalidated: used raw as a filename `$DECISIONS_DIR/$id.json` (:296-297) | | | |
| session sid ladder `--session-sid` > `CLAUDE_SESSION_ID` > `CLAUDE_CODE_SESSION_ID` > `CC_SESSION_ID` | ✓ | ✓ | ✓ | :291-293 |
| packet exists → echo the id, rc 0, never overwrite. Warns on stderr only when receipt or conviction differ | ✓ | ✓ | ✓ | :313-328 |

Side observations:

- **The class-A conviction cap is inconsistent.** The >90 refusal at :224 is not scoped by class. The "file class A" packet that the refusal message recommends is itself refused when it states its >90 number, so a class-A trail must omit `--conviction`. This is minor, but a design that asks for "class A citing the prior ruling" (fix 4 of the report) must not pass `--conviction 95`.
- **The deadline is never validated, and the sweep compares it as a string.** The comparison is `.veto_deadline < $now` (:626). A non-ISO deadline would never fire, because "t…" sorts after "2…". Measured: 7 packets carry a non-`YYYY-MM-DDTHH:MM:SSZ` deadline (`2026-09-30`, `…T00:00:00` with no Z, `…-07:00`). Those still order roughly right; free text would not.

## 4. How class-B default firing really works

**Who runs it.**

- `cc-decide expire-sweep` is called from exactly one place, `scripts/autonomy-sweep.sh` `class_b_actuate` (:557-605, called at :606). `grep -rn expire-sweep scripts bin hooks launchd commands` finds no other caller (ship-land's mention at :656 is a comment).
- `autonomy-sweep.sh` runs from launchd `com.chrisren.autonomy-sweep` with `StartInterval 300`, via `taskpolicy -c utility` (`launchd/com.chrisren.autonomy-sweep.plist:5,20-27`). The job is listed live by `launchctl list` (pid present) and in `launchd/fleet.manifest:461`.
- The actuator was hoisted to run right after `strand_rung` on 2026-10-19 because 39 of 40 ticks were self-terminating before reaching it (`autonomy-sweep.sh:546-552`).

**What it does.**

1. `cmd_expire_sweep` scans every file. For an open class-B packet with a non-empty deadline `< now` (string compare, :626), it sets `status=expired-actioned` and `resolved=now` (:635), writes an IDL row (:639), and prints `fired\t<id>\t<subject_project|->\t<change|no-change>\t<default>` (:640). It executes nothing (:52-55, :596-597).
2. `class_b_actuate` reads those lines (:562-602).
   - A `no-change` effect is counted and nothing more (:565-579).
   - Anything else (including an absent `default_effect`, which is normalised to `change` at :629) becomes `cc-backlog add --title "class-B default fired: $ddef" --project <subject_project or CC_SWEEP_PROJECT or claude-infrastructure> --source autonomy-sweep --dod-ref decision:<id>` (:589-597).
   - **No `cc-notify`, no `session_sid` read, no pane read.**

**Latency, measured** (jq over `expired-actioned` packets, `resolved − veto_deadline`):

- n=105, minimum 0 min, p50 6 min, p90 458 min, maximum 5,719 min (≈95 h).
- Class-B windows (`deadline − created`, n=151): p50 12 h, p90 164 h, maximum 335 h.

**What the filing session learns when its default fires: nothing addressed to it.**

- `wrap-ledger.sh` reads class C only (header :47-49; `count_blocking_decisions` :1502 queries `list --open --class C`).
- `operator-readout.sh:1561-1590` prints a **global** "N class-B default(s) auto-fire ≤24h" line, not scoped by session.
- `cc-digest:153-165` lists fired defaults globally for the operator.
- The backlog row carries no session and is usually filed under the wrong project (finding 2).
- The session would see the change only by re-running `cc-decide list`.
- The design intent was different. P15 §3.2 named "surviving sessions" as readers that "route around" open packets (`docs/research/desk-audit-2026-07-18/p15-escalation.md:153-156`), and §3.3 step 1 checks that `route_around_taken` is set (:162-163). Neither reader was built: no consumer greps `route_around_taken`, and it is set on only 47 of 166 class-B packets (measured).

**Where a wake could come from, without new hook registration.**

- `scripts/lead-supervisor.sh:546-565` `advise_subject` already mails a session by uuid (`cc-notify <sid> …`, uuid-shape guarded at :550, damped by a marker file).
- `class_b_actuate` could do the same when `session_sid` is a uuid: one notify per fired packet, idempotent because the status flips exactly once (:553-554).
- That needs reading `session_sid` (not in the 5-field line today) or a 6th padded field. The emitter must stay padded and structured-before-free-text (:599-609), so `session_sid` would go before `<default>`, and `autonomy-sweep.sh:562` `read -r tag did dproj deffect ddef` would need to change in lockstep. That is an interface change with two ends, and `tests/autonomy-sweep.bats` plus `tests/cc-decide.bats:127-145` pin the current shape.

## 5. The classifier: `scripts/gate-classify.sh` (142 lines; `~/.claude/rules/gate-classify.sh` → `scripts/gate-classify.sh`)

- Routing: C is checked first, then A, else B (:41-58). C is never demotable to A, and "ANY doubt routes B" (:11-15).
- `C_SURFACE` (:34) covers settings/hooks/launchd/plist/permission/allowlist/credential/password/api key/secret/token/login/cookie/purchase/pay…/invoice/checkout/self-modif/sudo/chmod/activate. `A_SETTLED` is at :37.
- A selftest is at :81-135. Tests are in `tests/gate-classify.bats`.
- **Callers: none in code.** It is prose-only: `hooks/cc-unattended-ask-guard.sh:63` (a recipe printed to stderr) and `commands/limit-recover.md:550`. `bin/cc-decide:13` mentions it in a comment. slot-H recorded the same (`slot-H-gates-recycle.md:38-39`).

Measured with `bash scripts/gate-classify.sh "$(jq -r .what_plain <packet>)"`:

| packet | filed class | router |
|---|---|---|
| e869fac7eb34 (stop the loop?) | C | **B** |
| 290215743799 (Codex review?) | C | **B** |
| a247b7288149 (pay per use / upgrade plan, a money path) | C | **B** (false negative: "pay per use", "upgrade" are not in `C_SURFACE`) |
| d610f8473106 (change rules and hooks) | C | C (" hooks ") |
| all 48 open class-C | C | 33 B, 15 C |

## 6. Feasibility: a ruling search at `open` time

**Corpus.** Answered packets, meaning status ≠ open: 633 measured (3+30+110+16+451+23). Searchable text is `what_plain`, `evidence` (on 483 packets), and the option outcomes, which must be guarded for string options.

**Simulation** (`/tmp/ccd-map/rulesearch.sh`, a read-only jq keyword overlap: tokens of 4+ letters minus stopwords, ≥2 hits):

- Query from `290215743799`: the true precedent `a247b7288149` ranks **2nd of the other packets** with 5 hits (chatgpt, code, codex, openai, plan). It sits behind `bbf99ddd45e4`, a generic 6-hit packet (claude, code, committed, findings, reviews, through).
- Document frequency over answered packets (measured, grep -c over the same text): chatgpt 2, codex 4, openai 5, reviews 3 against claude 143, plan 154, code 78. Rare-term (IDF) weighting would put `a247b7288149` first (estimated from those counts).
- Query from `e869fac7eb34`: `eb3dbe1e5e94`, the same fork expired to "keep looping", ranks **1st of the other packets** with 9 hits.
- Cost: 0.578 s wall for one run over 691 files, including tokenising (measured, `time`). `list --json` alone takes 0.065 s per `docs/research/exhaustive-drive-2026-09-08/W2-B2-stop-path-hot-term.md`, as cited at `bin/cc-decide:535-538`.

**Hint versus refusal.**

- **A stderr hint is safe.** stdout carries the id, and callers depend on that: `gate_sweep.py:161-163` takes the last stdout line, and `lr-reset-poller.sh` captures the whole stdout as the id (:1179-1196). stderr is free. `anti-deference-nudge.sh` (`open_packet_B`, :130-137) discards stderr, so the Stop hook path gains nothing from the hint and should skip the search, either by an env opt-out or by searching only when the class is C or the caller is a session. Its cost is then confined to the Bash-tool call.
- **Refusal on similarity is a false-block risk.** Raw overlap ranked an irrelevant packet above the true ruling. No human is present to override, and rewording `--what` defeats it trivially.
- **A declaration-based refusal is feasible.** It mirrors the receipt precedent (:230-245): class C (and optionally B) must carry `--prior <id>[,<id>]|none`, and `open` prints the top-N matches on stderr when `none` is passed. The refusal is then on the *absence of a declaration*, never on a similarity score. The `--prior` value is validated as an existing packet id. `cc-backlog`'s `ruled` pointer already checks "packet exists ∧ status ≠ open" (`bin/cc-backlog:1960-1964`); reuse that predicate.
- **An expired-actioned class-B packet is a ruling by silence for its default.** `eb3dbe1e5e94` is the live example. The rule text at `10-session-close.md:68` should say so. The `cc-backlog ruled` predicate already treats any non-open status as ruled (:1963).

## 7. A "gates" field (`--gates all|<items>`): what it would cost

- **Id stability: unaffected if it stays out of `mk_id`.** That is the existing law: "mk_id is class+sid+what ONLY — deliberately NOT the new fields. Annotating an existing decision … must not mint a SECOND packet" (:341-342). The consequence: a re-open that changes `--gates` is silently dropped, so the drift warning at :313-327, which covers receipt and conviction only, must also cover `gates`. There is no update verb. Narrowing gates over time would need a `recheck`-style append (`.gates_history[]`, effective = last) to keep inv7 (:404-410).
- **Item-list form is not machine-checkable.** Frozen-scope items have no stable ids, and a loop scope ("loop until dry") has no items at all. The ledger can verify only an enum. Recommended shape: `--gates all|partial`. With `partial`, require a non-empty `--continues "<the in-scope work that proceeds meanwhile>"`.
- **Do not reuse `route_around_taken`.** It already means "what the desk did INSTEAD to keep moving" (P15 §3.2 `p15-escalation.md:150`), but on the 14 class-C packets that carry it the polarity is mixed: "none — requires your authenticated session" (`2b9d23a05157`) against "the non-auth levers … are all being driven without this decision; nothing is blocked on it" (`b1614375d051`) (measured, jq). Those two packets, and `aa19d7b7a693` ("nothing is lost while this is open"), show that filers already declare partial gating in prose, with no effect on any machine.
- **Back-compat over 691 packets.** Fold an absent field to `all` on the read side, like SFOLD (:143-154). Then all 48 open class-C packets keep ⛔ and no gate weakens. The `shipland-esc-*` direct writer (`ship-land.sh:672-700`) needs no change: absent means all, which is correct, since a land-block gates the land.
- **Consumers.** Exactly one reader computes the rung: `wrap-ledger.sh` `count_blocking_decisions` (:1502-1561, jq at :1527-1546). Everything else consumes RUNG and never reads the store:
  - `completion-assert.sh:1196-1199` says so explicitly;
  - `session-continue.sh:1078-1090` reads the ledger;
  - `boundary-handoff.sh` reads the rung;
  - `operator-readout.sh:1160-1164`, `bin/cc-do:270-280` and `bin/cc-digest:135-160` show every open C for the operator board, and should keep doing so.

  To keep cc-decide the arbiter (`wrap-ledger.sh:42-46`; `cc-decide:494-498`), add the predicate as a `list` mode (e.g. `--blocking`, meaning open ∧ C ∧ `(gates // "all") == "all"`) rather than a second jq in the ledger. A `partial` class-C packet should then become the filer's 🔧 (keep driving), not ⛔. That is the same fold the UNCONVICTED split already does (`wrap-ledger.sh:1368-1393`, `:1517-1533`).
- **Making it required on class C.** Precedent for fail-closed C fields is the conviction, receipt and two-option gate (:236-245). Precedent against required fields is the B header (:76-80): "would rc-2 every legacy producer at exactly the moment a session is trying to escape a STOP-ASK". The class-C producers are:
  - sessions, via the rules;
  - `scripts/research-kit/lib/gate_sweep.py` (`file-packet --class C`, :586, building args at :120-160), which must be updated in the same land;
  - `ship-land.sh`, which bypasses `open`.

  Tests: 61 `open --class C` call sites under `tests/` (measured, `grep -rn 'open --class C' tests | wc -l`), 41 of them in `tests/cc-decide.bats` (76 `@test`s). Requiring the flag means editing all of them, or folding absent to `all` with a stderr nudge. **The incident lead filed without any such flag, so only a required flag (or a required category, §8) would have changed its rung.** A fold-only field would not.

## 8. Can `open` refuse a class-C packet that is not C10, C6 or a permission denial?

**What field would prove the category: none today.**

- The class is self-declared (finding 4). `why_gated` exists on 6 hand-written July packets (e.g. `33e4a598de8c`: "arming an autonomous self-recycle is a C10 self-modification"), and no consumer reads it (`grep -rn why_gated scripts hooks bin` is empty).
- Feasible design: a required, closed enum on class C, declared by the producer like `--default-effect` (:202-214, closed-value refusal; doctrine :57-80 "the producer states it; nothing reads the default's wording to guess"):
  - `--ceiling self-mod|money|permission|credential|all-scope`;
  - `all-scope` is the legitimate "this decision gates ALL remaining in-scope work" stop the constraints allow, and implies `gates=all`.
- On refusal, the message would route the filer to class B: "a judgment call with a status-quo course is class B: `--default "<the frozen-scope course>" --deadline <ISO> --default-effect no-change --project <repo>`".
- **The classifier should cross-check on stderr only.** When `gate-classify` says B and the declared ceiling is self-mod, money, permission or credential, print the disagreement. Refusing on it would false-block real money and self-mod packets: `a247b7288149` routes B, and the checkpoint set is under-detected by about 70% (slot-H :95).
- **The residual risk is honest mis-declaration.** A lead can still declare `all-scope` for "stop the loop?". The incident lead wrote "No round 27 until you answer", which is effectively that claim. The closing check for that belongs to the ledger, with a loop-scope floor so that `loop until|repeat until` counts as ungated work. That is the wrap-ledger slot. An `all-scope` declaration on a packet whose options include the status quo cannot be detected mechanically.

## 9. Prior design and the rationale for the B/C split

- **P15 §3.1** (`docs/research/desk-audit-2026-07-18/p15-escalation.md:127-133`):
  - B is "R-4 only: external-info-shaped OR a value-fork the values don't settle, AFTER route-around failed … write ONE decision packet, push-notify early-veto, **PARK that item, pull next backlog item (desk keeps moving)**".
  - C is "R-1 C10 self-mod/persistence · R-2 C6 money-path · R-3 permission-system denial … NEVER retry, NEVER route around the ceiling".
  - Design stance (:122-125): "must NOT let the queue become a re-ask crutch (anti-deference: route-around FIRST, queue is last resort)".
  - Asymmetric bias (:135-136): "any doubt → B or C, never A".
- **P15 §3.2 schema** (:141-159): `default_if_no_veto` is "what the agent WILL do at the deadline absent a veto (class B only)"; `route_around_taken` is "what the desk did INSTEAD to keep moving". Readers named there: the digest and "surviving sessions … route around them (never re-derives, never re-asks)" (:154-156).
- **P15 §3.3** (:161-166): the desk confirms `route_around_taken` on every class-B packet, then "Class-B default_if_no_veto fires automatically at veto_deadline (async early-veto, not sync approval) … Class-C waits".
- **The residual hard-reds R-1..R-4** come from SESSION_AUTONOMY_RESEARCH and P8-GO (`p15-escalation.md:84-91,101-105`). C10 is "permanent human-only".
- **Built as:**
  - `c634b83bc` (2026-07-18, "cc-decide unattended decision-queue packets (P15 §3.2)");
  - header `bin/cc-decide:13-19`;
  - router `scripts/gate-classify.sh:5-15`;
  - roadmap `docs/plans/ORCHESTRATOR_DESK_24X7_PLAN.md:95` (P0-6).
- **Why the ledger reads class C only:** `b08601974` (2026-08-07), commit body: "Class C only — a class-B default fires itself, so it is not a blocker". Also `wrap-ledger.sh:47-49`.
- **Where the rule text widened class C:**
  - `CLAUDE.global.md:1000` ("Corollary — a decision you are holding IS the rung, and filing it is what makes it one. Open it … `cc-decide open --class C …`"), first added 2026-08-07 (`git log --all -S'a decision you are holding IS the rung'` → `0c3566d1e`/`2c0b40853`/`e52e19270`);
  - carried into the slim variant at `CLAUDE.rules.slim.10-session-close.md:160` (`b191aa48f`, 2026-09-23; split in `cbe90eb63`, 2026-10-03);
  - and into `commands/wrap.md:140-144`.

  The text conflates "a held decision" with "a C10, C6 or permission gate" because ⛔ was wired only to class C.
- **Class B gained conviction and receipt** by operator ruling `aa19d7b7a693` (landed `1caac9ceb`, 2026-09-08; `bin/cc-decide:247-260`). The measurement then was 19 class-B packets in 30 days, 11 defaults fired unruled.
- **Filers already over-use C.** Of 57 live class-C packets, 45 route B (`slot-H-gates-recycle.md:85`).
- **The unattended recipe** (`hooks/cc-unattended-ask-guard.sh:59-75`) already says: gate-classify, then `cc-decide open --class B … --default … --deadline …`, then "**PROCEED on that default NOW** — the deadline is the operator's async early-veto window, not a synchronous approval gate". That is the behaviour ruling d610f8473106 asks for, applied today only when `CC_UNATTENDED` is set.

## 10. Every consumer of decision packets

Found with `grep -rn 'cc-decide\|autonomy/decisions\|CC_DECISIONS_DIR' scripts hooks bin commands skills launchd`.

| Consumer | Reads | Uses |
|---|---|---|
| `scripts/wrap-ledger.sh:1344-1352,1502-1561,2603-2610,2724,3062-3101` | `list --open --class C --json`, session_sid, conviction, receipt, producer, created, rechecks | ⛔ rung (BLOCKED), UNCONVICTED_PKTS → 🔧, BLOCKED_RECHECKED |
| `hooks/completion-assert.sh:1218-1240` | wrap-ledger RUNG and BLOCKED (never the store) | `blocked-answered` excuse |
| `hooks/session-continue.sh:1078-1103` | wrap-ledger rung | arms only on 🔧 |
| `hooks/operator-readout.sh:246,1148-1200,1548,1561-1590,1848-1851,1928,2000,2106` | store directly (dec_jq) | operator board: open C, plus B with no default and no deadline; global class-B due or overdue line |
| `hooks/anti-deference-nudge.sh:90-138,456-488` | writes `open --class B` (default "park … continue other work", no-change, 12 h) on a genuine-blocker close not matching CLASS_C_GENUINE | producer |
| `hooks/dispatch-assert.sh:60,197-202` | any packet `created ≥ turn start` | discharges "follow-on named" |
| `hooks/cc-unattended-ask-guard.sh:59-75` | — | prints the class-B recipe |
| `hooks/lib/why-tier.sh:313` | — | prose `cc-decide open --class C` |
| `scripts/autonomy-sweep.sh:72,186,557-606,1360-1370` | expire-sweep output; open packets → surfaced to desk/OS banner | class-B actuator; desk paging |
| `scripts/ship-land.sh:649-700` | — | direct writer of class-C `shipland-esc-*` |
| `scripts/limit-recover/lr-reset-poller.sh:1156-1199` | — | producer, class B monthly-spend, `--default-effect change` |
| `scripts/research-kit/lib/gate_sweep.py:48-163,333-470`, `gate.py:43`, `cli_records.py:643-674`, `cli_jobs.py:93`, `cli_core.py:155` | `list`, `open`, `action`; expired-actioned → applies default | research-program packets |
| `scripts/c10-batch.sh:16,54` | packet `actioned` gates a migration batch | consumer |
| `scripts/kitty-sitting.sh:43-44`, `bin/kitty-fullscreen-guard:73`, `bin/cc-settings-parity:75,95` | specific ids | consumers |
| `bin/cc-backlog:1960-1964` | `ruled` pointer: packet exists ∧ status ≠ open | ruling predicate (reusable for §6) |
| `bin/cc-do:96,263-280,377-378` | open C, plus B with no default and no deadline | operator queue |
| `bin/cc-digest:37,135-165,237` | open (all classes); expired-actioned in the last 24 h | digest |
| `bin/cc-permission-harvest:2393-2432` | — | classifies `cc-decide` verbs |
| `scripts/conviction-census.py:34,377`, `scripts/measure-harvest-latency.py:154`, `scripts/growth-coverage.conf:67` | store | measurement and coverage |
| `commands/wrap.md:57,140-144`, `commands/explain-decisions.md:11-18`, `commands/limit-recover.md:545-590`, `skills/research-program/SKILL.md:69,94` | — | instructions |

## 11. Design constraints this map implies

1. stdout of `open` must remain exactly the id. Any hint goes to stderr (§6).
2. New fields stay out of `mk_id` (:341-342), and the drift warning (:313-327) must cover them.
3. Read-side folds for absent fields must preserve today's rung: absent gates means `all`, absent ceiling means legacy C, which stays ⛔ (§7).
4. The one store predicate stays in cc-decide (`list` mode). wrap-ledger consumes it, and hooks consume RUNG.
5. The class-B wake has two ends: the `expire-sweep` 5-field TSV and the `autonomy-sweep.sh:562` read. Change both together, with padding, and keep the free-text default last.
6. Class-B producers asking a loop or continuation question must pass `--default-effect no-change --project <repo>`, or the fired default misroutes (df779857c4ff; b4780d7bb60e is pending).
7. Classifier output is advisory only (§5, §8).
8. `gate_sweep.py` and 61 test call sites are the cost of any new required class-C flag.
