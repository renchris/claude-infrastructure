# Axis 04: wrap-ledger.sh and operator-readout.sh. How the rung is computed, why it read ✅, and where UNDRIVEN_MINE fits

Read-only research slot. Every number below is labelled measured (with the command) or estimated
(with the method). Line numbers are from the worktree at `c19b14ac5`.

## 0. Answer

1. **The ledger could not see the incident.** None of its inputs carries "follow-on work a doc
   this session wrote names". The one input meant to stand for completeness, the frozen-DoD
   remainder, is **structurally 0 on this machine**. It counts `- [ ]` boxes, and no producer
   writes a box: 0 open boxes across all 78 DoD files (measured, §2). Conviction 95%.
2. **`SCOPE=met` at the incident came from other sessions' August scope lines.** The incident
   session never ran `dod-persist.sh set` for the startup-hooks study. The lineage filter keeps
   *unattributable* (pre-provenance) blocks forever (`hooks/lib/dod-path.sh:168`). So every
   worktree of this repo reads `DOD=present`, `REMAINDER=0`, `SCOPE=met` from 16 August blocks
   it never wrote (§2). Conviction 90%.
3. **The ledger said ✅ twenty seconds before the close.** The session ran
   `~/.claude/scripts/wrap-ledger.sh --machine | grep '^READOUT'` and got `READOUT=✅ Complete &
   landed — live layer converging (1 commit(s) behind; 0 executing file(s) stale; within the
   converge budget).` (transcript tool result at 14:27:32Z). The close at 14:27:47Z then read
   `✅ Good to close: yes. …`. Conviction 99%.
4. **operator-readout timed out at the incident Stop, so no certificate or block rendered.**
   Sources: the incident transcript, and fleet timeout rates over 24 h (§5). Any new input must
   reach the agent through **completion-assert.sh**, the Stop hook least likely to time out
   (4.8%, measured), and not through the readout alone. Conviction 90%.
5. **UNDRIVEN_MINE slots into the ✅-eligible 🔧 chain.** It goes after `CLOSE_FLOOR`
   (scripts/wrap-ledger.sh:2571-2574) and before the no-trunk arm (:2575). It is computed beside
   `count_resident_members` (:2549) and emitted after `CLOSE_FLOOR_SRC` (:2799). completion-assert
   consumes it beside `FILED_MINE` (hooks/completion-assert.sh:1042-1043). The ✅ certificate
   then drops out for free: both certificate paths require `RUNG=✅`
   (hooks/operator-readout.sh:2113, :2138, and the governing arm at :1338-1355). Conviction 85%.

## 1. Rung inputs and precedence (scripts/wrap-ledger.sh)

### 1.1 Inputs, in compute order

| Input | Where computed | What it reads | Fail direction |
|---|---|---|---|
| `TRUNK` | :765-812 | `WRAP_TRUNK` > `git config claude.trunk` > `origin/HEAD` > `origin/main` > `origin/master`, each `rev-parse --verify`'d | unresolvable ⇒ `""` ⇒ 🔧 "landing UNPROVEN" (:2575) |
| `DIRTY` / `DIRTY_N` | :829-831 | `git status --porcelain` (refreshing, content-truthful) | read error ⇒ 0 |
| `AHEAD`, `CHERRY` ⇒ `UNLANDED` | :834-841 | `rev-list --count TRUNK..HEAD`, `git cherry` '+' | — |
| `LANDING` | :850-863 | `hooks/lib/land-inflight.sh land_inflight_live` | absent lib ⇒ 0 |
| `GATE` | :866-871 | `<git-common-dir>/gate-green` vs HEAD. **Reported only, never a rung** (:2469-2489) | — |
| `DOD`, `REMAINDER`, `DOD_SCOPE`, `DRAIN_SCOPE`, `SCOPE` | :873-940 | DoD files from `dod_read_files`, lineage-filtered by `dod_filter_for`; REMAINDER = `grep -cE '^[[:space:]]*[-*][[:space:]]+\[[[:space:]]\]'` (:924-929) | absent ⇒ `DOD=absent`, `SCOPE=unknown` |
| `SID` | :950 `_wl_resolve_sid` | `--session` > `WRAP_SESSION_ID` > `CLAUDE_SESSION_ID` > `CLAUDE_CODE_SESSION_ID` | none ⇒ every session-scoped term reads `*_SRC=none`, count 0 |
| goal liveness | :2496 `compute_goal_liveness` | transcript `goal_status` attachments. **Reported only** | — |
| research program | :2499 `compute_research` (machine/full only) | `cc-research verdict`. **Reported only** | `unknown` |
| `BLOCKED` (⛔) | :2504 `count_blocking_decisions` (:1483) | `cc-decide list --open --class C --json`, `.session_sid == SID`, convicted only | error ⇒ 0 |
| `CUSTODY_OPEN` / `_MINE` / `_UNK` | :2530 `count_open_custody` (:1578) | `cc-custody list --open --cwd . --json`, pane-attributed | none ⇒ 0 |
| `LIVE_*`, `MIG_FAILED` ⇒ `LIVE_BREACH` | :2545 `compute_live_layer` (:2107) | live checkout vs trunk, adds, failed migrations | unknown ⇒ no rung |
| `YOURS` / `YOURS_PEER` (👤) | :2545 `count_operator_steps` (:1298) | `cc-backlog list --blocked --json`, `.session == SID` or a fired peer | error ⇒ 0 |
| `FILED_MINE`, `CLOSED_MINE`, `UNCONVICTED_ROWS` | :2546 `count_filed_undriven` (:1396) | ONE `cc-backlog list --all --json` jq pass | error ⇒ 0 |
| `CLOSE_FLOOR` | :2547 `compute_close_floor` (:1471) | `DRAIN_SCOPE` ∧ `CLOSED_MINE=0` ∧ attributing binary | n-a/none/error ⇒ 0 |
| `UNCONVICTED_MINE` | :2548 `sum_unconvicted` (:1442) | rows + class-C packets lacking conviction/receipt | — |
| `RESIDENT_MINE` | :2549 `count_resident_members` (:1689) | team config for SID ∩ `ps` | none ⇒ 0 |

### 1.2 Precedence (the code, not the header)

`RUNG="✅"` default (:2492), then one if/elif chain:

```
:2505 BLOCKED>0                ⇒ ⛔
:2512 DIRTY=1                  ⇒ 🔧 uncommitted
:2514 REMAINDER>0              ⇒ 🔧 frozen-DoD item(s)      ← dead in production (§2)
:2516 UNLANDED=1               ⇒ 📦 (LANDING ⇒ "in flight")
:2523 else  (✅-eligible on git facts)
:2531   CUSTODY_OPEN>0         ⇒ 🔧 custody (short-circuits the rest)
:2544   else: compute live/👤/filed/floor/unconvicted/resident (:2545-2549)
:2550     RESIDENT_MINE>0      ⇒ 🔧
:2563     FILED_MINE>0         ⇒ 🔧
:2567     UNCONVICTED_MINE>0   ⇒ 🔧
:2571     CLOSE_FLOOR=1        ⇒ 🔧
          ── UNDRIVEN_MINE>0   ⇒ 🔧   ← INSERT HERE (§4)
:2575     TRUNK=""             ⇒ 🔧 landing unproven
:2586     LIVE_BREACH=1        ⇒ 🚀
:2618     YOURS>0              ⇒ 👤
:2627     DOD=absent           ⇒ ✅ "completeness UNKNOWN"
:2632     LIVE_SRC=behind      ⇒ ✅ "live layer converging"   ← the incident's READOUT
          (fallthrough)        ⇒ ✅ "Complete & live on trunk"
```

📤 is a model overlay; this script never assigns it (header :21-23). The parity test
`tests/wrap-ledger.bats:2085-2097` pins the emitted set to exactly six glyphs, and :2099-2110
pins it against the ladder lines in `CLAUDE.global.md` and `commands/wrap.md`. **UNDRIVEN_MINE
adds no glyph**, so parity is untouched.

**Cost law.** Terms below `UNLANDED` run only on the ✅-eligible path. The incident's earlier
Stops were 📦 (committed but not landed), so a new term placed there runs exactly when the
session has landed and is about to certify. That is the incident's moment, and it costs nothing
on 🔧/📦 Stops.

## 2. The frozen-DoD remainder, and why it read 0

- **Producer.** `persist_dod` writes exactly `printf '## %s (%s)%s\n%s\n\n' "$ts" "$4" "$prov" "$2"`.
  Here `$2` is the one-line `Scope (frozen|grown): …` string (hooks/dod-persist.sh:108-128, the
  `set` path at :362-373, PreCompact at :475/:490). Its own comment says that readers grep the
  Scope lines and that "wrap-ledger REMAINDER counts `- [ ]` boxes only" (:106). **No producer
  writes a checkbox.**
- **Store census.** In the 78 DoD files, files with any open `- [ ]` box: **0** (measured: loop
  `grep -cE '^[[:space:]]*[-*][[:space:]]+\[[[:space:]]\]'` over `~/.claude/autonomy/dod/*.md`).
  Files with any checkbox at all: 4 (measured: `grep -lE '…\[' … | wc -l`), all checked. The
  repo-key file this worktree resolves to (`repo-86523465733a9afe.md`, 383 lines; measured:
  `. hooks/lib/dod-path.sh; dod_read_files "$PWD"`) has **0** checkbox lines.
- **Tests only exercise a fixture shape that production never writes.** `ok_state` writes
  `- [x] item one` (tests/wrap-ledger.bats:319-325), so the 🔧 REMAINDER arm is reachable only in
  fixtures.
- **Lineage keeps foreign blocks.** `_dod_filter_file` keeps any `## ` header that has no
  ` · toplevel=` stamp: `*) keep=1 ;;   # unattributable (pre-provenance) — inherited, never
  dropped` (hooks/lib/dod-path.sh:168). For this worktree the filtered view holds 16 unattributed
  blocks dated 2026-08-10..2026-08-18, plus this study's 20:04Z block (measured:
  `dod_filter_for "$PWD" <file> | grep '^## '`). At 14:27Z, before the 20:04Z `set`, it held
  only the 16 August blocks. So `DOD=present`, `REMAINDER=0` and `SCOPE=met` (:938-940) all
  described another session's August contract.
- **The incident session froze no DoD for the study.** Its transcripts hold no
  `dod-persist.sh set` before 20:04:35Z (measured: jq over tool_use commands in both
  transcripts). "research only" first appears in the 14:27:47Z close message itself (measured:
  jq text search). This corrects INCIDENT.md's wording: no frozen-DoD *record* legitimised the
  stop. The prose did, and the ledger's `SCOPE=met` gave it nothing to contradict. Conviction 80%,
  because the intake could have been stated somewhere this grep did not read.
- **The same defect today.** `WRAP_BUSY=off WRAP_CACHE=off bash scripts/wrap-ledger.sh --machine
  --session 5759497b-…` gives `DOD=present REMAINDER=0 SCOPE=met` (measured, 15:3x local). The
  current contract ("build and land the fixes …") is plainly not met.

**Consequence for operator-readout.** `SCOPE=met` is the only completeness gate on both
certificate paths (`scope_of` :464, used at :1351 and :2147-2148). In this repo it is
unconditionally `met`, so the 2026-10-01 "withhold on unknown" ruling can never trigger here.

## 3. How operator-readout computes the ✅ SAFE TO CLOSE certificate

Two paths, both gated on `RUNG=✅`:

1. **Governing line inside a rendered block** (render_block, :1338-1355). Needs
   `CERT_WROTE=0` (turn-scoped write oracle `session_wrote_here_this_turn`, :1877),
   `scope=met`, and `CERT_VERDICT != no`. It then prints `✅ SAFE TO CLOSE — nothing of mine is
   open`. The block itself renders only when steps>0 ∨ 📦 ∨ 🚀 ∨ queue>0 (:1446). A 🔧 with no
   operator step renders nothing: "🔧 with no operator step is the MODEL's job" (header :22).
2. **Standalone certificate** when the block is empty (:2112-2163). It needs `RUNG=✅` (:2113),
   `CERT_WROTE=0` (:2118), a **second** ledger read that still says ✅ (:2129-2138), `SCOPE=met`
   (:2147-2148), and `CERT_VERDICT != no` (:2150). The text cites
   `frozen-DoD remainder ${_crem}` (:2151-2154). After §2, that clause certifies a number that
   cannot be anything but 0.

`CERT_VERDICT` comes from `close_verdict_polarity` (hooks/lib/close-shape.sh:124-145) over the
last main-chain assistant text in `tail -n 400` of the transcript (:1890-1897). A YES verdict
that carries prose follow-on still reads `yes`: the follow-on clause is never parsed.

The 🔧 arm of render_block (:1290-1336) composes `parts` from RESIDENT, CUSTODY, DIRTY_N, GATE
and REMAINDER only. **FILED_MINE, UNCONVICTED_MINE and CLOSE_FLOOR have no `parts` term**. When
one of them is the cause, the block falls back to `🔧 in progress — loose ends`. That is the
"new enum member falls into the default" shape the custody note at :1294-1310 describes. A new
UNDRIVEN term must get its own `parts` entry; copy the custody one.

## 4. UNDRIVEN_MINE: design and insertion points

### 4.1 Definition

`UNDRIVEN_MINE = UNDRIVEN_DOCS_N + UNDRIVEN_MSG`, where:

- **UNDRIVEN_DOCS_N** counts docs D that meet all four conditions:
  - (a) D is in `session_writes_paths "$tp"`. This is the SESSION scope, which includes
    `subagents/**` transcripts. The incident README was written by a workflow agent under
    `<sid>/subagents/workflows/`, and `session_writes_paths` returns it: 51 paths, README.md
    among them, rc 0 (measured on the incident transcript).
  - (b) D lies under the repo toplevel, matches `docs/(research|plans)/**/*.md`, and is not
    under `/(axes|slots|notes|evidence|audit|shards?)/` (slot inputs to a synthesis).
  - (c) D carries a follow-on heading, matched by
    `^#{2,4} ([0-9.]+ )?.*(Implementation (waves?|plan|order)|Next steps?|Follow-?on( work)?)\b`.
  - (d) D carries **no disposition line**:
    `^(\*\*)?Follow-on(\*\*)?:` whose value contains a 12-hex store id (a backlog row or a
    cc-decide packet: both ids are `sha256 | cut -c1-12`, bin/cc-decide:84), or `fired <slug>`,
    or `driven|landed` plus a sha.
- **UNDRIVEN_MSG** is 0 or 1. It reads the last main-chain assistant text, the same selector as
  operator-readout :1890-1897. The value is 1 when polarity is `yes`, a `follow-on:` value exists
  in the first 3 lines, and that value (i) is not `none`, (ii) has no 12-hex id, (iii) has no
  fired/custody/dispatched word, and (iv) has no owner word (`you|your|yours|operator|lead|
  decision|session`). It is computed only when a transcript is passed (the Stop path). On the
  pull path it is `UNDRIVEN_MSG_SRC=n-a`.
- **Abstentions.** All of these give `UNDRIVEN_SRC != ok`, count 0, no rung:
  - an active research program (`RESEARCH_PROGRAM != none`: the Follow-On Gate exemption,
    CLAUDE.rules.slim.10-session-close.md:72-79, files refinements to the apply-at-build list);
  - no transcript, or no session-writes lib;
  - `session_writes_paths` rc 2;
  - the `WRAP_UNDRIVEN=off` kill switch.

### 4.2 Why 🔧, and why at that position

- **🔧 is right.** The agent can drive the item itself, so it is the agent's loose end. It is not
  👤: nothing is filed for the operator. It is not ⛔: no class-C packet exists. Precedent: an
  unconvicted ask is "the filer's own 🔧 — same rank as FILED_MINE, outranking 🚀 and 👤"
  (scripts/wrap-ledger.sh:1370-1372).
- **Below FILED_MINE, UNCONVICTED_MINE and CLOSE_FLOOR.** Those name a store row with an exact
  cure. Above `TRUNK=""`, 🚀 and 👤: a "my side is done" 👤 over undriven own work is the same
  false-done that `filed-undriven OUTRANKS 👤` pins (tests/wrap-ledger.bats:2601-2608).
- **⛔ and a stated park still govern.** ⛔ is computed first (:2504-2511), so a genuine operator
  decision always wins. A park filed as a row with `--why-not-now` cites its 12-hex id in the
  disposition line, which clears the doc. FILED_MINE already excuses that row (:1417-1418).

### 4.3 File:line insertion points

**scripts/wrap-ledger.sh**

| # | Where | What |
|---|---|---|
| 1 | header :25 and :30 | add `∨ an undriven follow-on (UNDRIVEN_MINE>0)` to 🔧; add `∧ no undriven follow-on` to ✅ |
| 2 | header Env seams :197-206 | `WRAP_UNDRIVEN · WRAP_UNDRIVEN_GLOBS · SESSION_WRITES_LIB` |
| 3 | memo key :628-639 | append `|${WRAP_UNDRIVEN:-}|${WRAP_UNDRIVEN_GLOBS:-}|${SESSION_WRITES_LIB:-}`. The transcript mtime is already in the key (:627), so new session writes and a new final message re-key it |
| 4 | after `sum_unconvicted` (:1442-1451), before § DRAIN FLOOR (:1452) | state `UNDRIVEN_MINE=0; UNDRIVEN_DOCS_N=0; UNDRIVEN_DOCS=""; UNDRIVEN_MSG=0; UNDRIVEN_SRC="skip"` and `count_undriven_followon()`. Resolve `hooks/lib/session-writes.sh` and `hooks/lib/close-shape.sh` with the dod-path ladder (:877-881): sibling, then `$0`'s symlink, then `$HOME/.claude/hooks/lib`. Transcript = `${TRANSCRIPT_FLAG:-${WRAP_TRANSCRIPT:-}}`, else `GOAL_TP`, else `_wl_find_transcript` off the machine path (the `_wl_fired_peer_sids` pattern, :1285-1287). ONE `grep -lE` over the candidate list for (c), then ONE `grep -LE` for (d) |
| 5 | :2549 | call `count_undriven_followon` after `count_resident_members` |
| 6 | between :2574 and :2575 | `elif [ "$UNDRIVEN_MINE" -gt 0 ]; then RUNG="🔧"; READOUT="🔧 Loose ends — follow-on work you named is not driven, filed, fired or decided: ${UNDRIVEN_DOCS:-your close's follow-on clause}. Drive it now; or fire it (handoff-fire) / file it (cc-backlog add --dod-ref <doc>) / open the decision (cc-decide open --class C …), then record it in the doc as 'Follow-on: <id or slug>'."` |
| 7 | emit_machine, after :2799 `CLOSE_FLOOR_SRC` | `UNDRIVEN_MINE= UNDRIVEN_DOCS_N= UNDRIVEN_DOCS= UNDRIVEN_MSG= UNDRIVEN_SRC=`. **Must come after line 17**: the BUSY splice depends on lines 10-17 keeping their positions (:2747) |
| 8 | emit_full, after :2829 `Frozen DoD:` | `Follow-on:      <n> undriven — <docs>` or `none undriven` or `not checked (<src>)` |
| 9 | rung_next :2987 | the 🔧 text is generic, so nothing to change; optionally add `· drive/fire/file the named follow-on` when `UNDRIVEN_MINE>0` |

**hooks/lib/close-shape.sh**

| # | Where | What |
|---|---|---|
| 10 | after `close_verdict_polarity` (:145) | `close_followon_value <msg>`: the `follow-on:` value from the first 3 unfenced lines. `close_followon_undriven <msg>` returns rc 0 under the rules (i)-(iv) above. Pure awk, same `real()` mention-guard as :32-40 |
| 11 | template :179 | change `follow-on: <filed ids, each expanded in plain English|none>` to `follow-on: <id/slug driving each item, expanded|none>`. This keeps the template's own guarded `<…>` shape |

**hooks/completion-assert.sh**

| # | Where | What |
|---|---|---|
| 12 | after :1043 (the FILEDM pair) | `UNDRIV="$(lfield UNDRIVEN_MINE)"; case … esac; [ "$UNDRIV" -gt 0 ] && { contra=1; facts="${facts}follow-on you named is not driven, filed, fired or decided ($(lfield UNDRIVEN_DOCS)) — 'research only' is not a disposition: drive it, or fire/file/decide it and write 'Follow-on: <id|slug>' into the doc; "; }`. This is the delivery channel that ran at the incident Stop (3350 ms, no timeout) |

**hooks/operator-readout.sh**

| # | Where | What |
|---|---|---|
| 13 | 🔧 arm, `parts` (:1323-1329) | `undriv="$(lf UNDRIVEN_MINE)"` with the same digit guard. Add a `parts` term `${undriv} follow-on item(s) not driven: $(lf UNDRIVEN_DOCS)`, and an action tail like custody's (:1333-1335). This also fixes the existing `loose ends` fallback for this cause |
| 14 | standalone cert :2151-2154 | replace `frozen-DoD remainder ${_crem}` with `follow-on: none undriven` when `_clf UNDRIVEN_SRC` = ok. When the term was not computed, say `follow-on not checked` (do not certify silently) |
| 15 | cert gate after :2148 | belt-and-braces `[ "$(_clf UNDRIVEN_MINE)" = 0 ] || abstain "cert-undriven"`. RUNG already excludes this. The new abstain token gives the IDL a count |

### 4.4 Machine-output keys to add

`UNDRIVEN_MINE` (int) · `UNDRIVEN_DOCS_N` (int) · `UNDRIVEN_DOCS` (space-joined repo-relative
paths, at most 3 then `+N`) · `UNDRIVEN_MSG` (0/1) · `UNDRIVEN_SRC`:

- `skip`: a worse rung governs;
- `none`: no SID or no transcript;
- `n-a`: a research program is active, or the switch is off;
- `error`: no lib, or session-writes rc 2;
- otherwise the `SID_SRC`.

This mirrors `RESIDENT_SRC` (:1644-1647).

### 4.5 How session-written files are known

`hooks/lib/session-writes.sh::session_writes_paths <tp>` (:296, the one reader `_sw_paths`
:217-293):

- It streams the main transcript **plus** `<tp%.jsonl>/subagents/**/*.jsonl` (`_sw_subagent_files`
  :206-211, `find -H`, which covers `subagents/workflows/`).
- It collects `file_path` / `notebook_path` from `Write|Edit|MultiEdit|NotebookEdit` tool_use
  records.
- It returns three states (rc 0 wrote · 1 none · 2 cannot-tell) and is memoised per run
  (`SW_RUN_MEMO`).
- Residue: files written only via Bash are invisible (header :36-41). Here that fails toward
  *missing* a doc, which means no false 🔧. That is the safe direction for this term.
- Paths are logical, so canonicalise both sides through `_sw_canon_lines` before comparing them
  with the toplevel (the same trap noted at :585-589).
- Cost: 0.47 s real for the incident transcript, which carries 51 paths, at load 316 (measured:
  `/usr/bin/time -p bash -c '. hooks/lib/session-writes.sh; session_writes_paths <tp>'`). The
  heading scan adds 0.19 s (measured, the per-file loop; one `grep -lE` over the list is cheaper).

### 4.6 How ✅ SAFE TO CLOSE is suppressed

Nothing new is needed on the gate itself. `UNDRIVEN_MINE>0` ⇒ `RUNG=🔧`, so:

- the standalone path abstains `nothing-to-surface` at :2113;
- the re-read abstains `cert-rung-moved` at :2138;
- the governing arm (:1338) is never reached.

Item 15 adds a named abstain for telemetry, and item 14 stops the certificate citing a dead
number.

## 5. Delivery: which Stop hook actually runs

- Incident Stop 14:27:57Z: `operator-readout.sh durationMs 10048 timedOut true` against
  `completion-assert.sh 3350` and `session-continue.sh 2741` (measured: the `stop_hook_summary`
  record in the incident transcript). In the same transcript, 9 readout `hook_cancelled` against
  15 `stop_hook_summary` (measured: jq counts).
- Fleet, transcripts modified in the last 24 h (measured: grep counts of
  `"command":"~/.claude/hooks/<hook>","durationMs":N,"timedOut":true` and of
  `"subtype":"stop_hook_summary"` over `find ~/.claude*/projects -maxdepth 2 -name '*.jsonl'
  -mtime -1`):

  | Hook | Timeouts | Rate over 3269 Stop events |
  |---|---|---|
  | operator-readout | 632 | 19.3% |
  | session-continue | 409 | 12.5% |
  | completion-assert | 158 | 4.8% |

  The rates are estimated as timeouts divided by Stop events, assuming one run per hook per Stop.
- So completion-assert (item 12) is the primary channel. The readout changes (13-15) are about
  readability and truthfulness, not enforcement. session-continue's mechanical 🔧 arm fires only
  on the session's own dirty files (hooks/session-continue.sh:1102-1110), so it would not drive
  an UNDRIVEN 🔧. That is out of this axis; another slot owns continuation.

## 6. Always-firing risk (measured and estimated)

- **Doc term.** Docs touched under `docs/research|plans` in the last 30 days: 3205 (measured:
  `git log --since=30.days --name-only -- docs/research docs/plans | grep '\.md$' | sort -u`). Of
  those, 10 match the narrow heading set outside slot dirs (measured: the loop in §4.1(c)). Of
  the 9 incident-study `.md` files, only `README.md` matches (measured:
  `grep -lE <pattern> docs/research/startup-hooks-2026-10-18/*.md`).
- **Fire rate.** Estimated at ≤ ~10 sessions per 30 days, each cleared once and permanently by
  one disposition line.
- **Backfill.** 23 tracked docs match today (measured: `git ls-files … | xargs grep -lE … | grep
  -vE <slot dirs> | wc -l`). Backfilling their `Follow-on:` lines when this lands makes the
  pre-existing population zero, so only new research can arm the term.
- **Message term.** 7-day census over 1204 transcripts (measured: `python3 -I
  /tmp/axis04/census.py 7`) found 338 `Good to close: yes` closes in the first 3 lines:

  | Follow-on clause | Closes |
  |---|---|
  | none | 154 |
  | id-cited | 64 |
  | no follow-on clause | 82 |
  | prose, no id | 38 |

  By hand reading of those 38, 33 name an owner (you, your call, operator, lead, a session).
  About 5 have no owner word: the incident, "the owner's reply.", "one test after the next
  reboot, below.", a truncated D1-D3 list, and one whose first line is not the verdict. With
  rule (iv), the message term is estimated to fire on about 1.5% of yes-closes, about 5 a week,
  of which 1 was the incident. Rule (iv) is needed: without it the term fires on 11% of
  yes-closes, mostly at the operator's own steps.

## 7. Tests to copy

| New test | Copy from |
|---|---|
| wrap-ledger: ✅-eligible + a session-written research doc with an `## 5. Implementation waves` table and no `Follow-on:` line ⇒ `RUNG=🔧`, `UNDRIVEN_DOCS_N=1` | `ok_state` (tests/wrap-ledger.bats:319-325) for the clean state; the FILED_MINE quartet (:2556-2625: positive, the why-not-now exclusion, the other-session control, FAIL-OPEN); transcript fixtures via `tx` + `_sub_tx` (tests/session-writes.bats:52-70, :249-253: subagent-only writes still count) exported as `WRAP_TRANSCRIPT` |
| CONTROL: same doc with `Follow-on: filed abcdef123456` ⇒ ✅ | :2575-2582 (why-not-now ⇒ falls through to ✅) |
| outranks 👤: undriven doc + own blocked step ⇒ 🔧 | :2601-2608 |
| ⛔ still wins: undriven doc + convicted class-C packet ⇒ ⛔ | :2835-2845 (`a CONVICTED packet … ⛔ still outranks an unconvicted sibling`) |
| FAIL-OPEN: no transcript ⇒ `UNDRIVEN_SRC=none`; `RESEARCH_PROGRAM` active ⇒ `n-a`; neither is 🔧 | :2610-2625; the research seam `cvf_research` (tests/operator-readout.bats:1891-1901) |
| parity unchanged (6 glyphs) | :2085-2097, already there; it must stay green |
| completion-assert: done-claim over `UNDRIVEN_MINE=1` ⇒ FIRE; CONTROL `=0` ⇒ abstain | tests/completion-assert.bats:2168-2186 (`mkledger … FILED_MINE=1 RUNG=🔧`) |
| operator-readout: 🔧 with `UNDRIVEN_MINE=1` names the doc and drops `loose ends` | custody pair tests/operator-readout.bats:1511-1532 (`custody_env` + `stub_ledger`/`stub_ledger_over` :1162-1171, :1491-1500) |
| operator-readout: the incident replay, a YES close with prose follow-on over a ✅-but-undriven ledger, renders no `SAFE TO CLOSE`, abstain `cert-undriven` | verdict-first `cvf_env`/`cvf_repo`/`cvf_tr`/`cvf_hook` (:1854-1889) and the `cert-verdict-no` test (:1906-1913) |
| close-shape: `close_followon_undriven` on the incident line ⇒ rc 0; on `follow-on: none`, `follow-on: \`d581d5791c68\``, `follow-on: the Otto call is yours` ⇒ rc 1 | `verdict-first UNIT` (tests/completion-assert.bats:2263, `_cs_lib` + `tests/fixtures/close-verdict-first/*.txt`); fixture lines copied from §6 |

## 8. Rule text (budget-neutral)

- `CLAUDE.rules.slim.10-session-close.md:11-12`: replace `frozen-DoD remainder 0` (25 chars) with
  `no undriven follow-on (ledger)` (30 chars).
- Matching cut on :8: `Read-only turns, unverifiable states and a close answering no get
  none.` → `Read-only, unverifiable or "no" closes get none.`. That is about 23 chars shorter, for a
  net of about -18 chars (estimated by character count).
- `CLAUDE.global.md` ✅ row (:720): no glyph change. The parity tests read only the ladder line.

## 9. Two adjacent defects found (not UNDRIVEN, same root)

- **SCOPE=met over foreign blocks.** Make `SCOPE=met` require that the newest `Scope (frozen):`
  line comes from a block stamped with this toplevel or this session. If only unattributable
  blocks survive the filter, read `SCOPE=unknown`. Then the existing 2026-10-01 withhold rule
  works in this repo. No rung changes, so this adds no alarm. Edit point: the loop at
  scripts/wrap-ledger.sh:903-934, which needs the block header in `_wl_ff` (it already has it).
  Conviction 80%.
- **REMAINDER is dead in production.** Either retire it (keep the key at 0 for consumers;
  completion-assert :594/:1028 and operator-readout :1329 read it), or have `dod-persist.sh set`
  accept `- [ ]` items. Do not leave the certificate citing it. Conviction 85% that it is dead;
  60% on which cure.

## Skeptic verdicts

Skeptic pass, read-only, at `c19b14ac5` (same tree as the report). I re-opened every cited
file:line and re-ran the counts. The interactive shell's `grep` is a ugrep wrapper, while the hooks
run `/usr/bin/grep` (BSD). Where that matters, I name which one ran. Scratch scripts went to
`/tmp/sk04_*` (outside the repo), and this append is the only repo write.

### S0. The finding that changes the plan: completion-assert was CAPPED at the incident Stop

The report's delivery argument (§0.4, §5, fix 2) is that completion-assert "ran (3350 ms) at the
incident Stop", so it is the channel to use. It did run, but it said nothing because its budget
was already spent:

- IDL, `~/.claude/autonomy/idl.jsonl`, at 14:27:50Z for sid 5759497b:
  `"disposition":"abstained","reason":"capped:3>=3","suppressed_arm":"handoff","rung":"✅","facts":"","class":"assert","count":3,"max":3`.
- The `assert` budget (`COMPLETION_MAX` default 3, hooks/completion-assert.sh:132) was used up by
  three 📦 landedness fires in 66 seconds: 13:18:34Z, 13:19:02Z and 13:19:40Z, each with
  `"facts":"1 commit(s) YOU wrote are committed-but-unlanded"`. All are in the same IDL.
- An existing arm, **D1 handoff**, *did* match the incident close. It matched "The one change that
  **needs your** hand is raising the dispatcher's timeout" (the `CA_HANDOFF` regex at
  hooks/completion-assert.sh:467), and the cap suppressed it. So the incident close was not
  invisible to completion-assert. It was budget-starved.
- This is the starvation already documented at hooks/completion-assert.sh:1560-1568 (item
  3b464e94b3ff): "the TERMINAL close … arrived at `capped:3>=3`". That defect is why the
  `shape`, `verdict` and `act` classes exist (:1602-1616). It is pinned by
  tests/completion-assert.bats:1691-1700.
- Fix 2 as specified copies the FILEDM pair (`contra=1`, :1042-1043). That makes the class
  `assert` (:1608), which was at 3/3. **So the new term would have been capped at the incident
  too.**
- Measured over 7 days of IDL (`python3 -I /tmp/sk04_idl.py`, the archives from 2026-10-13 on
  plus the live file): 428 `assert`-class cap trips across 46 sessions. 2 of them were at RUNG=✅,
  both suppressing `handoff`: this incident, and 4736324c on 2026-10-17.
- **Repair:** give UNDRIVEN its own class, for example `CLASS=undriven` with
  `COMPLETION_UNDRIVEN_MAX=2`, claimed when UNDRIVEN is the only contradicting fact. Alternatively,
  stop ledger-arm fires on the same unlanded sha from spending more than one `assert` slot.

### S1. Root causes

| # | Verdict | Conviction | Re-check |
|---|---|---|---|
| RC1 REMAINDER always 0 | confirmed, with a qualifier | 88 | wrap-ledger.sh:924-931 and dod-persist.sh:106/:127 are as cited. I re-ran the census: 0 open boxes in 78 files. The 4 files with boxes (44c810f7…, 614c49df…, 740a045d…, a685eb17…, mtimes 2026-08-07..09) hold **hand-written** `- [x]` plan sections, so an agent writing into the DoD file is a dormant producer. "Reachable only in fixtures" is slightly overstated. Independent corroboration: handoff-fire.sh:7713-7714 records W2-B1's replay, "REMAINDER≠0 fires 0 / 44" self-closes. |
| RC2 SCOPE=met from foreign August blocks | confirmed | 88 | dod-path.sh:168 is as cited. `dod_filter_for` reproduces 16 unattributed 2026-08-10..18 blocks plus the 20:04:37Z block (measured). There is no `dod-persist.sh set` before 20:04:35Z: I checked the main transcript, the quaternary `.jsonl.handed-off` and all 38 subagent transcripts, and found no compaction records. The report misses a causal step: with no foreign blocks, `DOD=absent` would have taken the :2627 arm, which ranks above :2632. The agent's own `grep '^READOUT'` at 14:27:32Z would then have read "✅ Clean & landed — completeness UNKNOWN", not "Complete & landed". One correction to §2: "research-only" does **not** first appear in the close. It appears at 06:06:11Z in a *thinking* block (transcript line 201: "I'm scoping this as research-only"). The jq text search skipped thinking blocks. So the intake scope existed, but privately and unrecorded. |
| RC3 no ledger input for doc follow-on | confirmed | 97 | The chain at :2492-2659 is as tabulated (arm lines re-grepped: 2505/2512/2514/2516/2531/2550/2563/2567/2571/2575/2586/2618/2627/2632). The READOUT tool result is at 14:27:32.608Z and the close text at 14:27:47.478Z, so the gap is about 15 s, not 20 s. |
| RC4 polarity-only parser | confirmed | 85 | close-shape.sh:124-145 returns only yes/no/mixed/none, and :179 is the template line. Missed: completion-assert's D3 already parses line 1 of a yes for qualifiers (`CA_YES_HEDGE`, defined at :373 and applied at :1259-1265). That is the natural home for a "yes + undriven follow-on" test, because the message is already in hand there. |
| RC5 readout timed out; least reliable | confirmed, but its conclusion is undercut by S0 | 80 | The stop_hook_summary is as quoted (`timeoutMs 10000`), and the incident transcript has 9 readout cancels out of 15 Stops. Re-measured with a timestamp cut (≥2026-10-17T20:45Z, `/tmp/sk04_timeouts.py`): 3329 Stops; readout 665 (20.0%), session-continue 445 (13.4%), completion-assert 147 (4.4%). The rule file itself (CLAUDE.rules.slim.10-session-close.md:4) says the readout renders "as a `systemMessage`", and every readout output is `{systemMessage:…}` (operator-readout.sh:1959/2107/2160/2200). So it is operator-facing and never reaches the agent, whether or not it times out. "Ran" does not mean "would have delivered": see S0. |
| RC6 🔧 parts lacks FILED/UNCONVICTED/FLOOR | confirmed, low impact | 75 | :1323-1330 is as cited. Measured over transcripts modified in 3 days (`/tmp/sk04_safe.py`): 6 "loose ends" fallbacks in 1952 readout renders. It is operator display only. |

### S2. Fix candidates

**Fix 1, UNDRIVEN_MINE: weakened, 60.**
- *Insertion points:* correct (:1442-1451, :2549, :2571-2575, :2799, BUSY note :2747). The memo
  key is used only when a transcript is set (:621), and completion-assert exports
  `WRAP_TRANSCRIPT` (:277), so the Stop path has its transcript.
- *Missing constraint:* the ledger already sources `session-writes.sh` **only in a bounded child**
  (`_bounded … bash -c '. "$1" …'`, wrap-ledger.sh:1759-1772). The reason given is that it
  "defines names four other hooks also define". Step 4 says "resolve and source", which would
  break that rule.
- *Latency:* `session_writes_paths` took 0.42 s real at load 384 (re-measured: 51 paths, README
  included, rc 0). That lands on the shared ledger inside completion-assert's 5 s timeout
  (settings.json Stop entry), and the incident's completion-assert already took 3.35 s.
- *Always-firing:* low, confirmed, but the report's numbers do not reproduce.
  - Touched in 30 days: **6** of 3214 docs match, not 10. ugrep and BSD grep agree; 3117 of the
    paths still exist.
  - Tracked docs matching: **10**, not 23 (12 with slot dirs included).
- *Recall is the real problem.* The heading set is fitted to the incident.
  - Of 65 synthesis docs (README/REPORT/SYNTHESIS) touched in 30 days, 20 carry a
    plan/fix/recommendation heading, and only 1 (startup-hooks README) matches.
  - Missed headings include: "## 3. Build plan", "## 2. Implementation spec", "### 4.2
    Implementation steps (in order)", "## 7. Implementation brief", "## 3. Fix list", "## Fix
    candidates", "## Not done here (named for the next owner)".
  - "## 7. Follow-ons" (close-verdict-first REPORT) is missed because `Follow-?on( work)?\b`
    cannot match before the plural "s".
- *Laundering:* any 12-hex string in a `Follow-on:` line clears the doc. It is never checked
  against the backlog or decide stores, though the ledger already reads the backlog
  (`count_filed_undriven`). One id also clears a doc with six waves.
- *Operator decision:* ⛔ precedence holds (:2505).
- *Stated park:* the disposition grammar has no park form other than an id, so an operator's
  in-chat "leave the waves" needs a filed row first.
- *Ownership:* a fired research peer, or a lead-scoped "research only; the lead drives the waves",
  is pushed to drive work its lead owns. The owner-word exclusion exists only on the message arm.
- *Message arm:* re-run of the census with rule (iv) as a regex (`/tmp/sk04_census.py`): 337
  yes-closes from 117 sessions; prose 38, of which 34 have an owner word and **4** do not (1.2%).
  Of those 4, 1 is the incident and 2 are not-yet-drivable waits ("one test after the next
  reboot"; a pane "once its window is out of fullscreen"). Precision is therefore about 1 in 4.
  The arm is also bypassed by spelling: it parses only `follow-on:`, so "Follow-ups: none" or no
  clause at all (82 of 337) escapes. A value naming "a later session" passes rule (iv).
- *Placement:* put the message arm in completion-assert (next to D3), not in the ledger.

**Fix 2, completion-assert consumes UNDRIVEN_MINE: weakened, 40.**
- As specified, it is class `assert` and would have been capped at the incident (S0). The claim
  that it is "the primary channel because it ran" is refuted by the IDL.
- It becomes sound with its own class (S0). The test to copy is the CAP SPLIT case
  (tests/completion-assert.bats:1691-1700), in addition to :2168-2186.

**Fix 3, readout parts term and certificate wording: weakened, 50.**
- The parts term is implementable and harmless, but it is operator-display only (RC5, RC6).
- Items 14-15 target a dead path. The standalone certificate (`close-certificate`) fired **0**
  times across the IDL archives since 2026-09-30 plus the live file (measured, grep -c per
  archive). In this repo the block renders every Stop, with `Q_N`>0 and 235 items queued (in the
  hook_success stdout of the incident transcript).
- Item 14 contradicts tests/operator-readout-research.bats:120
  (`[[ "$msg" == *"frozen-DoD remainder 0"* ]]`), which the fix does not list.

**Fix 4, SCOPE=met only from attributed blocks: weakened, 55.**
- The diagnosis is right, but the fix effectively retires the certificate fleet-wide. In 7 days the
  whole DoD store gained **8** attributed captures, all `manual-set`, from 8 sessions, while 117
  sessions wrote yes-closes (measured). So SCOPE=unknown becomes near-universal, and the in-block
  ✅ line becomes a constant "completeness UNKNOWN": an always-on phrase, though not a block.
- Fixture breakage is wider than listed. These all use unattributed `- [x]` DoD fixtures and go
  red: tests/wrap-ledger-research.bats:103-110, tests/operator-readout-research.bats:107-121,
  tests/operator-readout.bats:1859 (`cvf_env`, the very helper fix 3's tests copy) and
  tests/self-certifying-close.bats:235.
- Recorded predecessor worktrees are attributed too, so the predicate should be "this lineage",
  not "this toplevel".

**Fix 5, retire REMAINDER and the rule text: weakened, 50.**
- Line refs are right (rule :8, :11-12). Net is about **-15** chars (python `len`: -23 on :8 and
  +8 on :11-12), not -18.
- The same clause lives in CLAUDE.global.md:850, commands/wrap.md:78 and
  commands/are-we-done.md:60. None is listed, and editing only the slim file desynchronises the
  "moved verbatim" copy.
- REMAINDER consumers missing from the list: scripts/handoff-fire.sh:7700 (the retirement stamp)
  and :7740-7765 (the `--terminal` refusal). Tests pinning it: tests/handoff-fire-ledger-stamp.bats:124,
  tests/completion-assert.bats:171 and tests/anti-deference-nudge.bats:307.
- The rule swap cites a ledger term that does not exist yet, so it must land after fix 1.

### S3. Measurements

| Measurement | Verdict | Re-check |
|---|---|---|
| 0 open boxes / 78 files; 4 with boxes | confirmed | re-ran the loop |
| repo-86523465733a9afe.md 383 lines, 0 checkbox lines | confirmed | `wc -l`, `command grep -cE` |
| filtered view: 16 August blocks + 20:04:37Z | confirmed | `dod_filter_for` |
| no `set` before 20:04:35Z; READOUT at 14:27:32Z | confirmed | jq over main, quaternary `.handed-off` and 38 subagent files |
| incident stop_hook_summary | confirmed | record 651 |
| 9 cancels / 15 Stops | confirmed | jq |
| fleet 24 h timeout rates | confirmed within 1 pp | 20.0 / 13.4 / 4.4% of 3329 (timestamp-cut) |
| ledger run DOD=present REMAINDER=0 SCOPE=met | confirmed by derivation (not re-run) | follows from :938-940 and the filtered view |
| session_writes_paths 0.47 s, 51 paths | confirmed | 0.42 s at load 384, 51 paths |
| 10 of 3205 touched, 23 tracked | **refuted as numbers** | 6 of 3214 touched; 10 tracked. The low-fire direction holds |
| census 338 / 154 / 64 / 82 / 38; 33 of 38 owner | confirmed | 337 / 153 / 64 / 82 / 38; regex gives 34 owner / 4 not |

### S4. Missed by the axis

1. The S0 cap starvation: the existing D1 arm caught the incident close and was capped. The
   cheapest real fix may be the class split, not a new detector.
2. Following from S0: give UNDRIVEN its own completion-assert class, or the term inherits the
   same starvation.
3. Readout output is `systemMessage` only (operator-facing). No readout change can make an agent
   continue.
4. Without the August blocks, the agent's own READOUT grep would have said "completeness UNKNOWN".
5. "research-only" was decided at intake, in a 06:06:11Z thinking block.
6. The doc-arm heading regex has low recall (1 of 20 synthesis docs with plan-like headings) and a
   plural bug ("Follow-ons").
7. Disposition ids are not verified against the stores.
8. Fired peers and lead-owned waves are a park and ownership case the doc arm does not handle.
9. handoff-fire's `--terminal` refusal also keys on the dead REMAINDER and would ignore UNDRIVEN.
10. Fix 4 and fix 5 break more fixtures and docs than they list.
