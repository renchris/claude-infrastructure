# Map: `scripts/wrap-ledger.sh` and the ⛔ (Blocked) rung

Slot: wrap-ledger. Scope: how the ledger turns an open decision into ⛔, why a "loop until …" scope reads as
complete, what a loop-scope floor could reuse, what every consumer reads (the blast radius), the memo cache, the
fail-open rules, and two candidate ledger designs. Read-only research; nothing was implemented.

All line numbers are from this worktree at `958b23030` unless a path says otherwise. "Measured" means the command is
named. "Estimated" means the reasoning is named.

---

## 0. Bottom line

1. The ⛔ rung is checked **first and unconditionally** (`scripts/wrap-ledger.sh:2595-2610`). Any open class-C
   packet this session filed outranks dirty files, unfinished DoD items and unlanded commits. The ledger has no
   way to tell whether the decision gates the remaining work, because a packet has no field that says what it
   gates (measured: `jq -r 'keys' ~/.claude/autonomy/decisions/e869fac7eb34.json`, which lists `class, conviction,
   created, default_effect, default_if_no_veto, evidence, id, options, receipt, recommendation, resolved,
   route_around_taken, session_pane_uuid, session_sid, staged_artifact_path, status, subject_project, veto_deadline,
   what_plain`).
2. A "loop until …" scope reads as **0 remaining for three separate reasons**, and the third is the one that would
   have defeated a loop-scope floor during the incident:
   - REMAINDER counts only lines that start with an unchecked `- [ ]` box (`:935-941`). A frozen scope is one line
     of prose.
   - dod-persist stores only one-line `Scope (frozen):` / `Scope (grown):` captures (`hooks/dod-persist.sh:140`,
     `:143-150`, `:486-487`), so a captured contract never carries boxes. Measured across the live store: **0 of 78**
     DoD files hold any unchecked box (shell loop with `grep -cE '^[[:space:]]*[-*][[:space:]]+\[[[:space:]]\]'` over
     `~/.claude/autonomy/dod/*.md`). The 38 checked `- [x]` boxes sit in 4 legacy files. The REMAINDER 🔧 arm is
     close to inert in practice.
   - **The B13 loop scope was not in the DoD store while the lead sat idle.** The operator gave it in a user
     prompt (transcript line 14, 2026-10-22T07:41Z). dod-persist runs only on PreCompact and SessionStart (measured:
     `jq` over `~/.claude/settings.json` hooks), and the session never compacted (measured:
     `grep -c '"compact_boundary"'` returns 0). The only capture of it is `2026-10-24T20:15:35Z (manual-set) · session=666022fd…`
     (`~/.claude/autonomy/dod/repo-7030c1939664b2e4.md:26-27`), about two hours after the operator's 18:11Z reply.
     During the idle, the ledger's `DOD_SCOPE` resolved to a **2026-10-08 contract from a different session** in the
     same toplevel ("when the operator pastes the corporate Mac's v9 …", same file :8-9). Measured by replaying the
     ledger's own filter read-only: `. hooks/lib/dod-path.sh; dod_filter_for "$PWD" <file> | grep -E '^## |Scope \('`
     from `/Users/chrisren/Development/agent-context-sync`.
3. DRAIN_SCOPE and CLOSE_FLOOR give a template for **where** to detect an open-ended scope: the same filtered stream,
   at no extra fork (`:912`, `:924-928`, `:945`). They do not give the **completion predicate**. CLOSE_FLOOR is
   discharged by "this session closed one backlog row" (`:1498`), and a loop has no equivalent. A loop floor needs
   its own end marker: a newer `Scope (frozen):` line, or a new `Scope (done):` line (§3).
4. Demoting ⛔ changes the rung string that **9 consumers** read. Only three of them change behaviour on it:
   session-continue (arms only on 🔧 or 📦/🚀), completion-assert (its ⛔ arm and the `blocked-answered` excuse) and
   boundary-handoff (free-win only on ✅). The handoff-fire self-close refusal deliberately reads fields, not the
   rung (`scripts/handoff-fire.sh:8628-8650`). **No ledger change alone would have stopped the B13 idle.**
   completion-assert abstained with `no-close-tell` before it read the ledger (measured: idl.jsonl row
   `2026-10-24T06:44:41Z completion-assert … "reason":"no-close-tell"`; gate at `hooks/completion-assert.sh:469-471`).
   session-continue's 🔧 arm also needs dirty files this session wrote (`hooks/session-continue.sh:1103-1110`).
5. A new field needs **no memo-key change** as long as it adds no new environment variable. It must be emitted
   **after line 18 (`LIVE=`)**, or it breaks the BUSY splice position check (`:575-599`).

---

## 1. The ⛔ rung, exactly

### 1.1 Header contract

- Ladder and the meaning of ⛔: "an open class-C decision packet THIS SESSION filed" (`:20-24`).
- Why ⛔ exists: a close rendered "✅ SAFE TO CLOSE" while the model held a blocking decision (`:36-41`).
- Store and predicate: `cc-decide list --open --class C --json`, keeping rows where `.session_sid == SID`
  (`:42-46`).
- Class C only. Class B "carries a default that FIRES at its deadline … so it resolves itself and is not a
  blocker" (`:47-49`). So refiling a judgment call as class B (goal b) **removes it from ⛔ with no ledger change.**
- Scoped to this session, because the box holds about 21 open decisions at any time (alarm polarity, `:49-52`).
  Measured today: 48 open class-C packets across 23 sessions (`jq -s` over `~/.claude/autonomy/decisions/*.json`).
- Cost: one bounded fork per close, paid unconditionally because ⛔ outranks everything (`:55-60`).

### 1.2 Code

- `_resolve_decide_bin` (`:1344-1352`): `CC_DECIDE_BIN`, then the sibling `bin/cc-decide`, then `~/.claude/bin`, then
  PATH.
- `count_blocking_decisions` (`:1502-1564`):
  - Unresolvable SID ⇒ `BLOCKED=0 BLOCKED_SRC=none` (`:1503`).
  - No binary, no jq, a non-zero exit or a timeout ⇒ `BLOCKED=0 BLOCKED_SRC=error` (`:1508-1511`).
  - One jq pass (`:1527-1546`) splits this session's packets into `$ask` and the rest. `$ask` holds packets with a
    `.producer`, packets older than `CC_CONVICTION_EPOCH`, and packets with both conviction and receipt. `$ask`
    counts as BLOCKED. The rest are `UNCONVICTED_PKTS`, which go to the filer's own 🔧, not ⛔ (`:1381-1393`).
  - `BLOCKED_WHAT` is the packet's `what_plain`, set only when there is exactly one (`:1554-1562`).
  - The same fork emits `RC` rows for **foreign** packets whose last re-check is this session's
    (`:1538-1546`). `count_rechecked` (`:1568-1619`) keeps those stamped since the last genuine human prompt.
- The ladder (`:2595-2610`):
  ```
  count_blocking_decisions
  if [ "$BLOCKED" -gt 0 ]; then RUNG="⛔" …            # :2604-2610
  elif [ "$DIRTY" -eq 1 ]; then RUNG="🔧" …           # :2611
  elif [ "$REMAINDER" -gt 0 ]; then RUNG="🔧" …       # :2613
  elif [ "$UNLANDED" -eq 1 ]; then RUNG="📦" …        # :2615
  else  # ✅-eligible: custody, live layer, YOURS, FILED_MINE, CLOSE_FLOOR, UNCONVICTED, resident …
  ```
- **Precedent for a demoted ⛔ already exists.** The re-check variant (`BLOCKED_RECHECKED`) is placed on the
  ✅-eligible path just above 👤, "a store write must not mask agent-drivable work, so dirty, remainder, unlanded,
  custody, resident, filed, unconvicted, floor, no-trunk and 🚀 all still win over it" (`:2599-2602`, arm at
  `:2717-2725`). Only the filed-by-me ⛔ outranks everything.
- Side effect of ⛔ coming first: on a ⛔ close, **none of the ✅-eligible terms is computed**. CUSTODY, YOURS,
  FILED_MINE, CLOSE_FLOOR, RESIDENT, UNCONVICTED_ROWS and LIVE all stay at `*_SRC=skip` (`:2622-2648`).
  `emit_full` says so: "not counted (a worse rung governs)" (`:3021`, `:3027`, `:3038`, `:3047`). Only the
  pre-ladder facts DIRTY/DIRTY_N (`:840`), AHEAD/UNLANDED (`:843-850`), REMAINDER/DOD_SCOPE/DRAIN_SCOPE (`:906-945`)
  and GATE (`:874-879`) are real under ⛔.
- The model-facing text under ⛔:
  - READOUT: "⛔ Blocked — need your call: <what>." / "… N decision(s) need your call: cc-decide list --open"
    (`:2607`, `:2609`).
  - `rung_next`: "STOP-ASK — put the decision in line 1 and hand it back; **nothing below it closes**"
    (`:3098-3102`).
  - These strings are relayed verbatim. The close template puts READOUT on line 2 (`hooks/lib/close-shape.sh:180`,
    `:278`), and operator-readout prints it as the state (`hooks/operator-readout.sh:1548`). **The ledger itself
    tells the model to stop.** That matters for design (ii) below.

---

## 2. REMAINDER, SCOPE, DRAIN_SCOPE: how they are computed and from which store

### 2.1 Store resolution

- Library: `hooks/lib/dod-path.sh`, found next to the script, then through its symlink, then under `~/.claude`
  (`:885-891`). Fallback: the legacy path-hash formula (`:896-905`).
- `dod_path_for "$PWD" write` gives `${WRAP_DOD_DIR:-~/.claude/autonomy/dod}/repo-<sha16 of the repo identity
  URL>.md`. Local-only repos use the legacy `<hash(toplevel)>.md` (`hooks/lib/dod-path.sh:266-279`).
- `dod_read_files` lists the repo-key file and then this toplevel's legacy file, summed (`dod-path.sh:283-305`).

### 2.2 The per-file loop (`:913-944`)

- `dod_filter_for "$PWD" "$file"` (`:923`) drops blocks whose `## … · toplevel=X` header names a toplevel outside
  `dod_lineage_ancestors` (this toplevel plus its recorded predecessors). Blocks with no provenance are kept
  (`dod-path.sh:212-246`). **It filters by worktree, not by session.** Every session in one checkout shares one
  contract.
- `DOD_SCOPE` is the newest `Scope (frozen):` line in the filtered stream (`:924`, `:928`).
- `REMAINDER` is the sum over files of `grep -cE '^[[:space:]]*[-*][[:space:]]+\[[[:space:]]\]'` (`:935-941`).
- `SCOPE` is `unknown` with no DoD, `open` when REMAINDER > 0, and `met` otherwise (`:946-950`). It is reported and
  never moves RUNG (header `:175-178`).
- **Plan files are never read.** No line of the script opens `docs/plans/*` (measured: `grep -n
  'docs/plans\|plan file\|PLAN' scripts/wrap-ledger.sh` finds only comments, at `:280`, `:486`, `:654`, `:1713`).
  Plan checkboxes count only if someone pasted them into the DoD with `dod-persist.sh set "<multi-line>"`.
  For B13, the plan `agent-context-sync/docs/plans/bring-back-ocr.md` has 0 unchecked boxes anyway (measured:
  `grep -c '^\s*- \[ \]'`).

### 2.3 Why "loop until …" reads 0

- The scope is one prose line with no boxes, so REMAINDER = 0 by construction (`:936`).
- dod-persist writes only `Scope (frozen|grown):` lines (`hooks/dod-persist.sh:140`, `:143-160`, `:172-194`). Its own
  comment says the ledger counts boxes only (`:170`).
- With REMAINDER = 0 and SCOPE = met, a clean landed tree reads ✅. The incident report's claim that even without
  the decisions the ledger would have read ✅ is consistent with this, though it is estimated, not replayed.
- The incident-specific gap (§0 point 2): the B13 contract was never captured while the lead idled. Rule
  `CLAUDE.rules.slim.10-session-close.md:26` says "restate the ask as one line, `Scope (frozen): …` … (`dod-persist.sh`
  captures it)". In fact capture happens only at PreCompact or by an explicit `dod-persist.sh set`.
- **Reading the transcript is not a usable fallback.** Measured: 24 lines of the B13 transcript contain
  `Scope (frozen):`, mostly dispatched-lane briefs and injected context (`grep -n 'Scope (frozen):' <transcript>`
  gives lines 14, 27, 889, 1737, … 5130). The newest is a lane's "PHASE 1 — research" scope, not the lead's
  contract. A raw `grep | tail -1` would name the wrong contract. Speed is not the problem (13 ms on 9 MB, measured
  with `time`).

### 2.4 DRAIN_SCOPE and CLOSE_FLOOR (`:945`, `:1471-1500`)

- `DRAIN_SCOPE=1` when DOD_SCOPE matches `backlog|drain` case-insensitively (`:945`). This is a substring match.
  Measured: 50 of 362 frozen lines in the store contain `backlog` or `drain`.
- `compute_close_floor` (`:1490-1500`) fails open four ways, each named in `CLOSE_FLOOR_SRC`:
  - `n-a`: the scope is not about the backlog.
  - `none`: no SID.
  - `error`: the backlog store could not be read.
  - `binary-old`: the cc-backlog binary does not stamp `closedSession`.

  Otherwise `CLOSE_FLOOR=1` iff `CLOSED_MINE == 0`.
- Where it sits: inside the ✅-eligible branch (`:2645-2646`), at the same rank as FILED_MINE (`:2670-2673`). It is
  **never computed under ⛔ or 🔧** because it needs `FILED_SRC`, which comes from the expensive
  `cc-backlog list --all` (about 2.3 s at load ~300, `:1420-1424`).
- Consumer: completion-assert, as a done-claim contradiction (`hooks/completion-assert.sh:1142-1144`). It carves out
  confirmed assignees, because the DoD is keyed by repo and teammates inherit their lead's scope (`:1137-1141`).

### 2.5 Can a LOOP_SCOPE floor reuse it?

**Reuse the detection site, not the completion predicate.**

- Detection (reuse as is). Match `DOD_SCOPE` on the same line as `:945`, from the same filtered stream. This costs
  zero forks and runs **before the ladder**, so the result is visible under ⛔ as REMAINDER is. CLOSE_FLOOR is not.
  The regex must be tight:
  - Measured: `loop until` matches 1 of 362 frozen lines and `repeat until` matches 1.
  - Looser words false-positive heavily: "fix/gate-runaway-loop", "until landed", "dry-run", "DEFAULT-OFF until …"
    (sampled from the store with `grep -oiE '.{0,30}\b(until|repeat|loop|keep going|dry)\b.{0,40}'`).
  - Suggested pattern: `(^|[^a-z-])(loop|repeat|iterate|keep (going|looping|running))[[:space:]]+until([^a-z]|$)|until[[:space:]]+(dry|nothing new|a round confirms)`.
- Completion. CLOSE_FLOOR's predicate (`CLOSED_MINE==0`) has no loop meaning. Options for what marks the loop
  finished:
  - (a) **A newer `Scope (frozen):` line** in the lineage stream. This works today with no new syntax, because
    DOD_SCOPE is "the newest frozen line" (`:924`). The lead ends the loop by freezing the next contract, for
    example "paste v33 to the operator". This is also how DRAIN_SCOPE ends.
  - (b) **A `Scope (done): <evidence>` line newer than the newest frozen line.** It is cheap to read: change the
    `:924` grep to `grep -E 'Scope \((frozen|done)\):' | tail -1` and branch on which one is last, still one fork.
    It needs a dod-persist change, because `set` currently rewrites any other prefix to
    `Scope (frozen): Scope (done): …` (`hooks/dod-persist.sh:487`). That would make the done line the new contract
    text. It works by accident, but the readout would then print a garbled DOD_SCOPE.
  - (c) **A plan line.** Rejected. The ledger reads no plan, and the DoD store is the declared contract store
    (`dod-persist.sh:20-23`, rules `:26`).
  - (d) **A decision id named inside the scope.** The 20:15Z capture says "(or the operator answers decision
    b4780d7bb60e 'stop')" (`repo-7030c1939664b2e4.md:27`). The ledger could treat "named packet resolved with the
    stop option" as done. That is too semantic for this script. Record it only as an operator-level convention.
- Session scoping, which the alarm-polarity rule requires (`:49-52`, `:66-68`). DOD_SCOPE is shared by every session
  in the toplevel (§2.2). An unscoped loop floor would mark **every later session in agent-context-sync** 🔧 until
  someone writes (a) or (b). DRAIN avoids this because one action discharges it. Proposal: count the loop floor only
  when the block that carries the newest frozen line has a header `· session=<sid>` equal to `SID`, or a sid on this
  pane's alias trail (dod-persist already derives that lineage: `_dod_lineage_sids`, `hooks/dod-persist.sh:273`).
  Otherwise `LOOP_SRC=foreign|unattributed`, and the floor is not counted (fail-open).
- The capture gap from §2.3 must close **outside the ledger**, or the floor is inert for the exact incident shape.
  Two routes: a rule requiring `dod-persist.sh set "Scope (frozen): …"` at intake, or a registered Stop or
  SessionStart hook capturing the newest operator-authored `Scope (frozen):`. The second must not use the raw
  transcript grep (§2.3). No new hook registration is allowed, so it would have to ride an existing Stop hook such
  as session-continue.

---

## 3. Blast radius: every consumer of `--machine` fields

Measured with `grep -rn -- '--machine' hooks scripts bin commands` and per-file field greps. The brief's grep
(`led_field\|lfield\|READOUT\|RUNG`) finds the helpers. Each consumer parses `KEY=` lines by name, so **an added
field is invisible to every existing consumer** (`session-continue.sh:340-346` `led_field`; `completion-assert.sh:656-662`
`lfield`; operator-readout `kv_first`; `anti-deference-nudge.sh:511` `grep -E "^$1="`; `boundary-handoff.sh:653-655`
`case RUNG=*`; `handoff-fire.sh:8605-8614` case arm).

| Consumer (call site) | Fields read | Effect of RUNG ⛔ today | If ⛔ dropped below 🔧 when ungated work remains |
|---|---|---|---|
| `hooks/session-continue.sh:1099-1103` mechanical 🔧 arm (`WRAP_BUSY=off`) | RUNG | ⛔ ⇒ `return 1` silently, no IDL row | 🔧 passes the rung check, but the arm **also needs dirty files this session wrote** (`:1107-1110`, `session_dirty_mine`). So dirty + open-C now arms (wanted: "commit in-progress work first"). A loop-only 🔧 (clean tree) still does **not** arm. The header refuses REMAINDER-driven arming as the infinite-loop case (`:997-1002`). Loop risk is bounded by the existing armed path (CLAUDE_CONTINUE_MAX, SID-bind, kill switch, `:1019-1022`) and self-clears on commit. |
| `hooks/session-continue.sh:1203-1216` ship floor | RUNG, TRUNK (`:1236`), AHEAD (`:1269`), SHAS | ⛔ ⇒ `return 0` | Unchanged **only if ⛔ stays above 📦/🚀**. If 📦 outranked ⛔, the ship floor would demand `/ship` over an open C6/C10 packet, where **landing is the gated act** (false block). Design (i) therefore keeps ⛔ above 📦. |
| `hooks/completion-assert.sh:646-669` (ledger read), `:1103` (REMAINDER), `:1108` CUSTODY, `:1117` FILED, `:1128` UNCONV, `:1142` CLOSE_FLOOR, `:1167-1190` 🚀, `:1218-1238` ⛔ | RUNG, DIRTY, DIRTY_N, UNLANDED, AHEAD, REMAINDER, TRUNK, LANDING, LANDING_PID, CUSTODY_OPEN, FILED_MINE, UNCONVICTED_MINE, CLOSE_FLOOR, MIG_FAILED, LIVE_LAG, LIVE_ADDS, BLOCKED, BLOCKED_RECHECKED | ⛔ arm: "❌ Good to close: no" with no done reading ⇒ `blocked-answered` excuse (`:1220-1231`) | Under 🔧 the ⛔ arm is skipped, and DIRTY/REMAINDER contradictions apply as before. **But closes shaped like B13's never reach the ledger**: no CLOSE token plus a no-verdict ⇒ `abstain "no-close-tell"` at `:469-471` (measured in the IDL for 06:44Z). Neither rung order nor a new field changes that unless the gate is changed. Also, CUSTODY/FILED/CLOSE_FLOOR arrive as 0 on any ⛔ close (§1.2), so they are blind there today. |
| `hooks/boundary-handoff.sh:629-660` `free_win_now` | RUNG only | ⛔ ⇒ no recycle advice; logged `freewin=⛔` (measured: idl row 06:44:42Z `below-threshold:64<73;freewin=⛔`) | 🔧 ⇒ still no free-win (it needs ✅). Neither order fixes the advice to recycle an idle Blocked session. That is a separate boundary-handoff change. |
| `hooks/operator-readout.sh:1407-1550` render block | RUNG, AHEAD, SHAS, LIVE_LAG, MIG_FAILED, LIVE_ADDS, DIRTY_N, GATE, REMAINDER, CUSTODY_OPEN, RESIDENT_MINE(_NAMES), READOUT (⛔ only, `:1548`), BLOCKED_RECHECKED | ⛔ ⇒ state = READOUT verbatim | Under 🔧 the parts list (`:1509-1514`) has **no loop term and no decision term**. A loop-only 🔧 would render "🔧 in progress — loose ends", the "new cause dropped by renderer" defect the file itself records (`:1480-1488`). It needs a `parts` term. The "N decision(s) are yours" header comes from the decision store, not the ledger (`:1715`), so it is unaffected. |
| `hooks/operator-readout.sh:551-562` `_or_busy_read` (`WRAP_BUSY_SPLICE=on`) | BUSY_* , PERMPEND* | none | none (splice position constraint, §4) |
| `hooks/operator-readout.sh:2458-2480` certificate | RUNG (= ✅ required), TRUNK, DOD, REMAINDER, SCOPE | ⛔ ⇒ `cert-rung-moved` abstain | none |
| `hooks/operator-readout.sh:532-545` `scope_of` | SCOPE, else DOD/REMAINDER | — | If LOOP_OPEN were folded into SCOPE=open, the ✅ certificate is withheld (`cert-scope-open`). That is the desired effect, and it also hits the inherited-contract sessions of §2.5. |
| `hooks/anti-deference-nudge.sh:500-521` | DIRTY, UNLANDED, REMAINDER, RUNG (log only, `:513-516`) | rung only recorded | none, unless REMAINDER is inflated (then `contradiction=1`, `:521`) |
| `scripts/handoff-fire.sh:8558-8625` retirement stamp, `:8664-8689` self-close refusal | RUNG, REMAINDER, UNLANDED, GOAL_SRC, GOAL_LAST | ⛔ annotate-only; refusal keys on **fields** REMAINDER/UNLANDED, never RUNG (`:8628-8650`: ⛔ fired 3/44 on legitimate fired-peer retires) | Rung order: none. **If LOOP_OPEN were folded into REMAINDER, a loop-scoped fired peer could not retire** until it wrote an end marker. That is a new refusal class. Keep it a separate field. |
| `hooks/lib/session-busy.sh:483-499` `sb_render_line` (via `--busy`, operator-readout `:2422`) | RUNG (arg 7) | rung ≠ ✅ + IDLE-DEAF ⇒ "IDLE with no wake path armed … (rung ⛔)" | same for 🔧 |
| `hooks/lib/close-shape.sh:180,278,309` (D6/D7 reasons, `completion-assert.sh:1759-1760`) | RUNG glyph in text | text only | text only |
| Not ledger readers (checked): `bin/cc-classify`, `hooks/notify.sh`, `bin/cc-notify`, `scripts/lead-supervisor.sh`, `hooks/dispatch-assert.sh`, `hooks/goal-inert-watch.sh`, `hooks/mailbox-wake-arm.sh`, `hooks/idle-keepalive.sh` (no `wrap-ledger` invocation, measured by grep) | — | — | The memo comment's "operator-readout, notify, cc-classify" BUSY readers (`:652-653`, `session-continue.sh:1097`) is stale for notify and cc-classify. |

Tests and docs that pin the order:

- `tests/wrap-ledger.bats:1933-1959` ("⛔ outranks 🔧", "⛔ outranks 📦") must change under design (i). This is a
  deliberate change of policy and a self-modification.
- `tests/wrap-ledger-recheck.bats:157` pins the re-check ⛔ below dirty and unlanded.
- The rung-parity test checks that emitted ⊆ documented (`tests/wrap-ledger.bats:2060-2075`). It is unaffected
  unless a **new glyph** is introduced. Do not add one: every renderer `case` would drop it (the
  `operator-readout.sh:1543-1546` history).
- Ladder text stating strict ⛔ > 🔧 priority: `CLAUDE.global.md:710`, `CLAUDE.rules.slim.10-session-close.md:90`,
  `commands/wrap.md:74`, `hooks/lib/why-tier.sh:83`.

---

## 4. The memo cache

- Key (`:630-688`):
  `v1|transcript|mtime size|PWD|--session|WRAP_SESSION_ID|CLAUDE_SESSION_ID|WRAP_TRUNK|WRAP_DOD_DIR|WRAP_DOD_FILE|WRAP_GATE_GREEN|CC_BACKLOG_BIN|CC_DECIDE_BIN|CC_CUSTODY_BIN|CC_CUSTODY_DIR|pane|CC_FIRED_DIR|WRAP_LIVE_*|CC_MIGRATIONS_STATE|WRAP_LAND_INFLIGHT_LIB|WRAP_RESEARCH*|WRAP_BUSY`.
  It is scoped to the event, never to store content (`:330-337`). A content key over the decision directory's mtime
  served a stale ⛔ after a veto (FAILURE 2, `:321-328`). A new turn appends to the transcript, so the key changes.
- Active only with `--machine` and a transcript. Off when `WRAP_CACHE=off` (`:630-631`, `:338-343`).
- Single-flight `mkdir` lock with doubling waits (`:690-760`). Memo files are swept after 240 minutes (`:450`).
- **Does a new field need a key change? No**, if it is derived from inputs already covered: the DoD files (read
  under the same event key as REMAINDER), SID, and the decision store (same fork as BLOCKED). **Yes**, for any new
  environment seam (a kill switch such as `WRAP_LOOP_FLOOR=off`, or an override regex `CC_LOOP_SCOPE_RE`). The rule
  is "a caller that overrides one is asking a different question" (`:634-636`), so it must join `_wl_k`.
- **Emit position is constrained.** `_wl_splice_print` requires line 9 to be `LANDING_PID=`, lines 10-17 to be the
  BUSY-off defaults, and line 18 to be `LIVE=` (`:575-599`, `emit_machine :2844-2857`). Otherwise it treats the
  body as a miss. New fields go after `LIVE=`, ideally next to `DRAIN_SCOPE/CLOSE_FLOOR` (`:2905-2907`) or
  `BLOCKED` (`:2908-2913`).
- Cross-version serve: the key carries no script version. During a live-layer fast-forward in the middle of an
  event, a body in the old shape can be served to a new consumer for at most that one Stop event. Consumers must
  read an absent field as 0, which all current consumers already do (`case ''|*[!0-9]*) x=0`). Optionally bump the
  `v1|` prefix to `v2|` (`:637`) when the emit shape changes.

---

## 5. Fail-open conventions to keep

- An unresolvable sensor never manufactures a rung (`:52-54`, `:69-70`, `:84-86`). Each term carries
  `*_SRC ∈ {skip, none, error, n-a, …}`. `skip` means "a worse rung governs", so not counted, which is different
  from a counted zero (`:3056-3064`).
- BLOCKED fails open: an unreadable store leaves the rung exactly where it was (`:1354-1356`).
- CLOSE_FLOOR fails open four named ways (`:1485-1488`).
- Lineage filter polarity: when unsure, keep the block, so counts can only err toward "too many" (`:929-933`).
- Failing loud means outside a repo the script exits non-zero and **never prints `RUNG=✅`** (`:191-195`).
- Consumers: a non-numeric field becomes 0. An empty ledger means "cannot confirm", which completion-assert records
  as `no-ledger` or `ledger-uncomputable` (`completion-assert.sh:653`, `:664`). boundary-handoff records
  `no-answer` (`:660`).
- For any new field the safe direction is: an unreadable or ambiguous input means the field reads 0 or "gated", so
  ⛔ keeps governing as today. **Never weaken**: an absent `gates` value on a packet must read as "gates all".

---

## 6. Two candidate ledger mechanics (proposals only, not implemented)

### (i) New rung order: drivable in-tree work outranks the filed-by-me ⛔; ⛔ still outranks 📦/🚀/👤/✅

```
count_blocking_decisions            # still unconditional, one fork (unchanged cost)
compute_loop_floor                  # pre-ladder, zero forks: LOOP_SCOPE/LOOP_OPEN/LOOP_SRC from DOD_SCOPE (§2.5)
if   BLOCKED_HARD > 0      → ⛔      # producer packets (.producer set, e.g. ship-land escalation) or .gates=="all"
                                     # or legacy packets with no .gates field (fail toward today's ⛔)
elif DIRTY                 → 🔧  (+ "· N decision(s) pending, not gating: <what>")
elif REMAINDER > 0         → 🔧  (+ same clause)
elif LOOP_OPEN = 1         → 🔧  "frozen scope is a loop (<scope head>) not ended by a newer Scope line; keep running
                                  rounds as scoped while <what> is open"
elif BLOCKED > 0           → ⛔      # everything else: ⛔ still above 📦, so ship floor never fires over a decision
elif UNLANDED              → 📦 …    # rest unchanged
```

- Why ⛔ stays above 📦. A C6 or C10 gate often **is** the land (money path, self-modification). Ranking 📦 above
  it would arm the ship floor (`session-continue.sh:1216`) to demand the gated act.
- What it fixes:
  - The rung line no longer says "STOP-ASK … nothing below it closes" (`:3101`) while a loop is open.
  - Dirty work under an open decision now arms session-continue's commit loop.
  - The original 2026-08-07 defect (✅ over a held decision, `:36-41`) cannot come back: 🔧 is never a close
    certificate, and its READOUT must name the pending decision.
- What it does not fix:
  - completion-assert's `no-close-tell` abstain (`:469-471`). A "❌ no" close with no CLOSE token still ends the
    turn unchallenged.
  - A loop-only 🔧 does not arm session-continue (needs dirty files this session wrote).
  - boundary-handoff free-win (✅ only).

  Each needs its own hook change, so a 🔧 that nothing enforces is still an idle.
- Prerequisite: `cc-decide open --class C` gains `--gates all|<items>`, stored as `.gates`. Without it, the ledger
  cannot tell a decision that gates everything from one that gates a part. The B13 lead believed decision 1 gated
  everything ("No round 27 until … answered", report :79-81). So this design leans on goal (b): such calls go to
  class B, which ⛔ never counts (`:47-49`). It also leans on a rule saying what "gates" means.
- Blast radius: tests `wrap-ledger.bats:1933-1959` must be rewritten, the four ladder docs need a conditional
  clause, and operator-readout needs 🔧 `parts` terms for the loop and for pending decisions. handoff-fire is
  unaffected (it keys on fields).
- Cost: zero extra forks (the loop floor reads the existing `_wl_ff` stream; BLOCKED_HARD rides the existing jq at
  `:1527-1546`).

### (ii) Keep RUNG; add fields that consumers opt into: `UNGATED_REMAIN`, `LOOP_OPEN`, `BLOCKED_GATES`

All are computed before the ladder or in the existing ⛔ fork, emitted after `LIVE=`, and need no memo-key change
unless a kill-switch seam is added.

- `LOOP_SCOPE` (0|1), `LOOP_OPEN` (0|1), `LOOP_SRC` (`n-a|own|foreign|unattributed|done|error`): as in §2.5.
- `UNGATED_REMAIN` = `DIRTY_N + REMAINDER + LOOP_OPEN + UNLANDED`, meaning in-scope work known without any store
  read. These are exactly the facts that are real under ⛔ (§1.2). FILED_MINE, CUSTODY and RESIDENT are **not**
  computed under ⛔ (they would cost the `cc-backlog list --all` fork, about 2.3 s at load ~300, `:1420`). The
  field's comment must say they are excluded, rather than imply a zero.
- `BLOCKED_GATES`: of this session's BLOCKED packets, how many gate everything (`.gates=="all"`, or `.producer`
  set, or **no `.gates` field**, which keeps legacy packets at today's force). `BLOCKED_PARTIAL` = BLOCKED −
  BLOCKED_GATES. It is one extra `map(select(…))` in the jq at `:1527-1537`, placed before the free-text cell so
  free text cannot shift it (`:1514-1520`).
- READOUT and `rung_next` change wording when `RUNG=⛔ ∧ BLOCKED_GATES=0 ∧ UNGATED_REMAIN>0`:
  "⛔ Decision open — need your call: <what>. It does not gate <N> in-scope item(s) (loop scope open); keep
  driving them." and `rung_next` "drive the ungated scope; the decision rides". The glyph is unchanged, so the
  parity tests and renderers are untouched. This alone removes the ledger's own "nothing below it closes"
  instruction.
- Consumers (each opt-in, each bounded):
  - session-continue: a new arm on `RUNG=⛔ ∧ BLOCKED_GATES=0 ∧ UNGATED_REMAIN>0`, through the existing armed path
    (cap, SID-bind, IDL). The once-per-key damper should be keyed on `(sid, HEAD, decision ids)`, as the ship floor
    keys on HEAD. A loop round that lands moves HEAD and re-arms once. A session that cannot progress stops at the
    cap. This also closes the "stood down silently" gap: log the stand-down.
  - completion-assert: grant `blocked-answered` only when `UNGATED_REMAIN=0 ∨ BLOCKED_GATES>0`. Effective only if
    the `no-close-tell` gate (`:469-471`) lets a no-verdict ⛔ close through to the ledger.
  - boundary-handoff: free-win may accept `⛔ ∧ UNGATED_REMAIN=0` (a genuinely gated idle is the cheapest recycle).
    Do **not** accept ⛔ with ungated work, or the advice becomes "recycle" instead of "keep working".
  - operator-readout: append "N in-scope item(s) not gated" to the ⛔ state (`:1548`).
- Pros:
  - No rung-semantics change: the tests pinning ⛔ > 🔧 and the ladder docs stay true.
  - handoff-fire's field-keyed refusal is untouched (keep LOOP_OPEN out of REMAINDER).
  - Each consumer can be shipped and measured on its own.
- Cons:
  - Enforcement exists only where a consumer reads the field.
  - It adds 5-6 machine fields.
  - The `gates` judgment still comes from the filer (the cc-decide flag).

### Shared requirements for both

- The loop scope must be in the DoD store while the work runs (§2.3). Otherwise LOOP_OPEN reads 0 for the exact
  B13 shape. Capture at intake (rule) or a capture by an already-registered Stop hook. Never the raw transcript.
- Session-scope the loop floor by the capture's `session=` header (§2.5), or it becomes an alarm that fires on every
  close in that checkout.
- End marker: a newer `Scope (frozen):` line works today. `Scope (done):` needs `hooks/dod-persist.sh:487` to accept
  the prefix.
- Keep class B out of ⛔ (`:47-49`). Goal (b) is the biggest lever and needs no ledger change.
