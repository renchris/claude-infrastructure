# Slot C — operator-readout, session-continue, boundary hooks on a read-only research close

Worktree `/Users/chrisren/Development/.worktrees/close-status-research` @ 36afca47f. Incident transcript
`T` = `~/.claude-quaternary/projects/-Users-chrisren-Development--worktrees-wt-cc-192325-42328/74728043-bcb8-4e66-8cdb-62189f61c848.jsonl`
(710 lines when read; line numbers below are record numbers in T). Scratch: `/tmp/rpic-C-readout/`.

## 0. Answer

Yes, a surface already shows the decisions waiting on the operator. It rendered on the incident's
final Stop as `◆ 73 decisions — your call   cc-decide list --open` (T:467). It did not help, for
four reasons:

1. It counts the **machine-wide** pile. Nothing in it comes from this session.
2. It looked almost the same as the block shown before the research started (T:86, `◆ 74 decisions`).
3. Line 1 led with the pile partition (`3 runnable now, 253 need your call`) and then `✅ live on trunk`.
4. The model's prose, which renders above the block, said "nothing of mine is open".

Every hook in this slot keys "is anything left?" on git/ledger state and on records filed by
**this session** (backlog `.session`, packet `.session_sid`). The research turn filed nothing, so
every arm read the turn as done.

There is also a separate defect, measured in the sandbox in §5. Suppose the session had filed the
sign-off as its own class-C packet. The ledger would compute ⛔, but the readout has **no ⛔
arm**, and its decisions leg never reads `session_sid`. So line 1 would read `OPERATOR ▸ 4 need
your call`, and the session's own checkpoint would sit unnamed inside the pile.

The fix (§6) has three parts:
- A durable record filed by the session (a class-C packet, or a `cc-backlog needs` row) is the trigger.
- The readout splits session-owned decisions out the way it already splits `yours` backlog rows.
- A research-signoff record puts `Research done — implementation pending your sign-off: <N>` on
  line 1 and demotes the pile.

Pure Q&A files nothing, so nothing prints.

## 1. How a read-only turn is handled (code)

### operator-readout.sh

- **Fire predicate.** Fires when there are steps, or RUNG is 📦/🚀, or the queue is non-empty, or
  there are research or fire-loop lines. Otherwise it is silent:
  - header `hooks/operator-readout.sh:18-27`: "✅/read-only needs no block (protocol: suppress on read-only)" (:23).
  - code `:1446-1447`.
- **Three-state write-turn oracle.**
  - `CERT_WROTE=2` is the default (`:815-817`): "0 wrote · 1 read-only · 2 cannot tell". The pull
    surface `--render` has no transcript, so it never claims a write turn.
  - It is resolved once in hook mode, `:1855-1879`: `session_wrote_here_this_turn "$TP" "$CWD"; CERT_WROTE=$?` (:1877).
  - The lib is `hooks/lib/session-writes.sh:370-392`. It is scoped to the turn AND the cwd tree: a
    write to `/tmp` or another tree is rc 1 (rationale `:353-368`; three states `:30-37`).
  - Only file-edit tool_uses count. Bash writes are invisible (`:39-44`).
- **Verdict read.** Only on CERT_WROTE=0 (`:1887-1904`). `CERT_VERDICT=no` withholds the certificate.
- **✅ state arm** (`:1338-1355`):
  - CERT_WROTE=0, scope met, verdict not "no": `✅ SAFE TO CLOSE — nothing of mine is open`.
  - CERT_WROTE=0, scope unknown: `✅ clean & landed — completeness UNKNOWN`.
  - **Anything else, including every read-only turn: `✅ live on trunk`** (:1355).
- **Rung arms that exist:** 📦 `:1237`, 🚀 `:1240`, 🔧 `:1292`, ✅ `:1338`. There is **no ⛔ arm and
  no 👤 arm** (`grep -n '^      "[^"]*")' hooks/operator-readout.sh` ⇒ 1237, 1240, 1292, 1338 only).
  - 👤 has no arm on purpose: "1 step(s) are yours" carries it (tests/operator-readout.bats:955-961).
  - ⛔ leaves `state=""`. Nothing names a session-owned decision (§5 scenario B).
- **OPERATOR ▸ header (line 1).** In collapse mode it is `OPERATOR ▸ <_lead> · <state>` (`:1491-1504`).
  - `_lead` = `"<yours> step(s) are yours"` first, then `"N runnable now, M need your call"`.
  - Only the certified case reorders to answer-first and demotes the pile (`:1505-1515`, gated on
    `RUNG=✅ ∧ CERT_WROTE=0 ∧ verdict≠no`). **A read-only turn never gets that reorder**, so line 1
    leads with the machine's pile.
  - When the research program is the only signal, the header is `OPERATOR ▸ ${state:-research
    program awaiting you}` (`:1518-1520`).
- **◆ research-program line** (`:638-722`, rendered `:1751-1753`).
  - Source: `cc-research pending --json` over the research-kit registry
    (`~/.claude/autonomy/research/programs.json`). It is **machine-wide and program-scoped**:
    pending concerns or a priced menu.
  - It has no notion of "this session's research produced N recommendations".
  - In the incident it rendered `◆ research truememory-2-0: 0 pending concern(s) — menu: …`, an
    unrelated program. That line was 252 chars, the longest in the block (§4).
- **Standalone close certificate** (`:2032-2162`).
  - Fires only when the block is empty, RUNG=✅, CERT_WROTE=0, scope met and verdict≠no.
  - The read-only path abstains with the old token `nothing-to-surface` (`:2115-2119`).
  - Comment `:2042-2047`: "never assert safe-to-close on an unknown … rc 1 (read-only) and rc 2 both stay silent".
- **`yours` class** (the existing session-owned channel).
  - Defined at `:35-46`: blocked backlog rows whose `.session` equals this SID.
  - Split happens in the same jq, `:1125`. Itemized first, outside the budget (`:1526-1550`).
  - The decisions leg has **no equivalent split**. `grep -n session_sid hooks/operator-readout.sh` ⇒
    no match. The decisions jq (`:1015-1060`) selects open C / hard-B regardless of filer.
- **Damping.** A content-hash latch with a 900 s TTL (`:29-32`, `:2164-2186`), plus a cheap pre-render
  stamp over `ACT_DIR`, `DEC_DIR`, `BLG_FILE`, HEAD, dirty count and trunk (`:1987-2025`). Filing a
  packet or a needs row moves `DEC_DIR`/`BLG_FILE`, so the stamp moves and the block re-renders at
  the next Stop (inferred from `cheap_stamp`).

### session-continue.sh

- With no sentinel armed, the hook tries three floors, then allows the stop (`:1288-1329`):
  - **Mechanical 🔧:** only on `RUNG=🔧` with this session's own dirty files (`:1018-1103`; rung gate at :1103).
  - **Ship floor:** only on 📦/🚀 with own writes (`:1168-1243`; rung gate at :1219).
  - **Wake floor:** inbox reachability.
- Header contract `:13-14`: the agent arms only on 🔧 and clears "on ✅/📦/⛔/📤, read-only".
- **No arm looks at "research done, action pending".** A read-only turn at ✅ with no sentinel goes
  straight to `exit 0`.
- In the incident it produced no output. It **timed out** at T:241, 259, 276 and 316 (hook_cancelled,
  timedOut).

### boundary-handoff.sh

- The **free-win arm** (`:468-562`, `T_FREEWIN=35` at :513) advises a recycle when context is ≥35%
  and RUNG=✅. Its rationale (:847) prints "clean, landed, no DoD remainder, **no operator step
  outstanding**".
- In the research-pending state that sentence is false. If it fires there, it tells the session to
  recycle while the research judgment sits only in context.
- In the incident it abstained on every Stop: `below-threshold:8..22<73;freewin=below-floor`
  (IDL rows 25378 … 31819, `grep 74728043-bcb8 ~/.claude/autonomy/idl.jsonl`).
- This arm is the natural actuator for the operator's "after sign-off, self-recycle into
  implementation". Today it would fire **before** the sign-off, not after.

### waiting-recycle.sh

- PostToolUse:Bash. `grep -n 'read-only\|✅\|RUNG' hooks/waiting-recycle.sh` ⇒ no rung or read-only logic.
- Not involved at Stop.

### grep scope

- `grep -lc 'CERT_WROTE' hooks/*.sh hooks/lib/*.sh` ⇒ operator-readout.sh only.
- `read-only` appears in 14 hook files. The only close-relevant one besides the above is
  completion-assert (`:814-817` research subagent; `:866-877` read-only session in the shared
  checkout). That hook belongs to another slot.

## 2. What rendered on the incident's Stops (measured)

Method: `python3 -I /tmp/rpic-C-readout/hooks.py T`, which lists every Stop-hook attachment,
stop_hook_summary record and Stop-feedback record. IDL reasons come from `grep 74728043-bcb8
~/.claude/autonomy/idl.jsonl`.

| T line | time (Z) | what |
|---|---|---|
| 86 | 21:18:38 | readout fired (recycle start, before any research): `OPERATOR ▸ 3 runnable now, 245 need your call · ✅ live on trunk` · `◆ 74 decisions` |
| 97–98 | 02:15:42 | human `/explain-decisions`: "explain each itemized decision, provide your recommendation, and your conviction %" |
| 243, 260 | 02:21–02:22 | readout **timed out** (hook_cancelled) |
| 278 | 02:31:45 | readout fired: `… 253 need your call · ✅ live on trunk` · `◆ 73 decisions` |
| 293, 310 | 02:32 | completion-assert `false-done` arm=shape ×2 (IDL 29218/29226): "this session wrote real work and the ledger reads ✅, but the close is missing [good-to-close-verdict line-1-rung]". It demanded the `Good to close:` line, and the model answered "yes" |
| 314–391 | 02:32–02:34 | interim closes, each `✅ Complete & live on trunk — nothing to do. This was read-only research, so no repo changed.` (the line the operator quoted). Readout abstained `stamp-unchanged-ttl:43s…183s<900s` on all 8 (IDL 29216…29316) |
| 465 | 02:37:19 | final close: `✅ Good to close: yes — nothing of mine is open; follow-on: none` / `✅ Complete & live on trunk — nothing to do. The 74 open decisions were re-checked …` |
| 466/467 | 02:37:24 | **final readout, fired** (IDL 29424 `steps-surfaced rung ✅ steps_total 256 steps_shown 0`). Block below. completion-assert **timed out** (T:468, 5337 ms > 5000) |
| 567 | 02:50:55 | operator: quotes the ✅ line, "Huh?" |

Final block (T:467, verbatim; 15 lines):
```
OPERATOR ▸ 3 runnable now, 253 need your call · ✅ live on trunk
 ▶ cc-do --run --expect 3:3867814045   [3 runnable]
 ◆ 73 decisions — your call   cc-decide list --open
 ◆ 180 blocked backlog — work keeps stopping at these 2   cc-backlog list --blocked
   ◆ b13ef5862c83  blocked 7× · unchecked 7d — Apply the 5 harvested allow rules…
   ◆ a8f3c6eaa960  blocked 6× · unchecked 18d — BytePlus ModelArk US-territory…
   ─ 104 of 180 last re-checked >14d ago — premise unverified
 ⚠ 3 stranded session(s) — closed by a mover, relaunch failed:
   ▶ cc-do 87df20238deb   [40b80c03 · c3-40b80c03 · next4]
   ▶ cc-do 6d3f1d6cd329   [6507a980 · wt-feat-dwell-telemetry · next4]
   ▶ cc-do 09123f46c397   [a2601c01 · lr-stranded-husk · next4]
 ⟳ lr-recon: 2 cohorts open · 0 moving · 4 waiting · 0 held · 0 escalated
 ◆ 1135 escalation record(s) unseen — cc-escalations ack --all
 ◆ research truememory-2-0: 0 pending concern(s) — menu: … (252 chars)   cc-research verdict truememory-2-0
 ─ board: cc-blockers
```

- **No `SAFE TO CLOSE` rendered on any Stop.** `grep -c 'SAFE TO CLOSE' T` ⇒ 1, and that one is
  the injected instructions at T:24, not a hook render. The model's `✅ Good to close: yes` was
  its own prose.
- **Why the state read `✅ live on trunk`:** CERT_WROTE was 1. I replayed the oracle on T truncated
  at the final close (`head -465 T`) with `bash /tmp/rpic-C-readout/cw.sh`:
  - `session_writes_paths_turn` ⇒ rc_turn=1.
  - `session_wrote_here_this_turn … wt-cc-192325-42328` ⇒ rc_here_turn=1.
  - Session scope ⇒ `/tmp/xd/g99.md`, rc 0: the only main-thread write, in /tmp.
- **Why the final Stop rendered at all inside the 900 s latch** (339 s after T:278): the only line
  that differs between T:278 and T:467 is `◆ 1133` → `◆ 1135 escalation record(s)`
  (`diff /tmp/rpic-C-readout/b278.txt b467.txt`). The block reached the operator on the final close
  because two unrelated escalations arrived and changed the hash. With an unchanged hash it would
  have abstained `latched-ttl`.
- **The injected instructions primed "nothing of mine".** T:24, the instructions attachment, says:
  - "The machine's standing pile stays counted: it renders as one `◆` line in the `OPERATOR ▸` block … and is not re-prosed".
  - "`wrap-ledger.sh` computes `⛔` from this session's open class-C packets … an unfiled decision is invisible to it".

  The model followed the first literally. It filed nothing, so the second applied.

## 3. Why the ◆ decisions line was insufficient

1. **Wrong denominator.**
   - The line counts every open class-C packet plus every hard-B packet machine-wide (`:1015-1060`):
     73 at T:467.
   - This session's output was 74 re-checked, 18 closable, 56 real, 4 urgent, 9 changed. That lives
     only in `/tmp/xd/REPORT.md` and prose. No store holds it.
   - Live store now: 623 packets, 60 open, 59 class-C/hard-B (`python3 -I /tmp/rpic-C-readout/dec.py`).
2. **Indistinguishable from wallpaper.**
   - At session start, before the research, the same line read `◆ 74 decisions` (T:86).
   - After the research it read `◆ 73` (T:467): a one-count drift on a line the operator sees at
     every close. The latch design itself states the polarity law: an alarm that always fires
     carries no bits (`:2042-2044`; wrap-ledger.sh:49-51).
3. **Line 1 contradicted it.**
   - The header partition `3 runnable now, 253 need your call` is the pile again.
   - `· ✅ live on trunk` is the session verdict, and the model relayed it as "Complete … nothing to do".
4. **No attribution channel for decisions.**
   - The readout's session split (`yours`) covers backlog rows only (`:1125`).
   - Packets carry `session_sid` (614/623 measured, dec.py), but the readout never reads it.
   - Even a correctly filed checkpoint packet folds into the pile (§5 B).
5. **Position.**
   - The systemMessage renders as `⎿ Stop says:` in TUI grey #999, after the assistant message
     (docs/research/tui-systemmessage-render-2026-08-22.md:47-54; the order is T:465 → T:467).
     Its line 1 is not "the top" of what the operator reads. The model's line 1 is.
   - Inferred, not measured: on a long close the bottom-pinned viewport shows the block, and the
     model's line 1 has scrolled off. So line 1 of the block is the top line the operator sees
     without scrolling.

## 4. Render budget

- **Block size (measured, `/tmp/rpic-C-readout/b467.txt`):** 15 lines. Widths: 68 53 55 87 89 87 65
  66 62 74 67 79 66 **252** 23 chars (awk length).
- **Estimated rows:** at a 120-col pane the 252-char research line wraps to 3 rows, so the block
  is about 17 visual rows of a 24-row pane, plus a 1-row `⏰` line when due72 is set (it was at T:86).
- **Line limit:** a new line 1 must stay at most 100 columns, the renderer's own no-wrap bound
  (`:1596-1598`).
- **Headroom:** the proposal reuses the existing header row and adds at most one itemized row (the
  sign-off). The worst case goes from 17 to 18 rows. Demoting the pile partition off line 1 costs
  no row, because the `◆ 73 decisions` / `◆ 180 blocked` lines already carry those counts.
- **Further reduction, optional:** truncate the `◆ research` program line to 100 cols. It wraps
  today and was the least relevant row.
- **CC_ACT_WINDOW=3** (`hooks/lib/close-shape.sh:236-243`, completion-assert.sh:1727) governs the
  **model's prose**, not this block:
  - The act marker must be within the first 3 non-blank, unfenced lines: verdict, rung, act.
  - A relayed OPERATOR block inside a fence is skipped and uncounted (`close-shape.sh:227-234`).
  - So a top-of-block readout line does not consume the act window.
  - For the model's own line 1 to carry "research done — implementation pending" inside the
    window, the verdict line itself must change (`Good to close: no — research done; implementation
    pending your sign-off: N`). That is completion-assert and close-shape territory (another slot).

## 5. Sandbox: what each existing channel renders (measured)

Script `bash /tmp/rpic-C-readout/sandbox.sh`. It copies the env seams of
`tests/operator-readout.bats:13-73` into a temp git repo, uses real `scripts/wrap-ledger.sh` and
`bin/cc-decide`/`bin/cc-backlog` as readers, and hand-written fixture packets and backlog rows (no
`open`/`needs` verbs were run). Ran `--render --cwd w --sid sess-research-1`.

| scenario | ledger | OPERATOR ▸ line 1 |
|---|---|---|
| A: incident shape, 3 open C packets filed by other sessions, nothing filed here | `RUNG=✅ YOURS=0 BLOCKED=0` | `OPERATOR ▸ 3 need your call · ✅ live on trunk` |
| B: A + 1 C packet with `session_sid`=this session | `RUNG=⛔ BLOCKED=1 READOUT=⛔ Blocked — need your call: Decision bbbbbbbbbbb1…` | `OPERATOR ▸ 4 need your call`: **⛔ lost, own packet folded into `◆ 4 decisions`** |
| C: A + 1 blocked backlog row, `.session`=this session | `RUNG=👤 YOURS=1` | `OPERATOR ▸ 1 step(s) are yours · 3 need your call`, then line 2 `◆ [this session ccccccccccc1] Sign off: …` |

So C is the only existing channel that names a session-owned operator checkpoint at the top of the
block. B, the semantically correct primitive (class C means human-gated), is broken in the readout.

I could not run the bats pins for C's header (tests/operator-readout.bats:945-961, :1848-1953).
`bats tests/operator-readout.bats -f …` ⇒ `cc-bats: REFUSED — 2 concurrent bats execution
root(s) … this is a DEFERRAL, not a test result`. I did not take the waiver, because it writes
`~/.claude/state/bats-waivers.jsonl`.

## 6. Proposal: where the line renders, its trigger, how Q&A stays silent

**Where.** Line 1 of the `OPERATOR ▸` block (the `hdr` composition, `:1491-1523`). It gets the same
answer-first reorder the certified case gets (`:1513-1515`):

```
OPERATOR ▸ Research done — implementation pending your sign-off: 56 decisions · ✅ live on trunk
 ◆ [this session <id>] <what_plain: e.g. "Approve the 56 recommendations in /tmp/xd/REPORT.md">   cc-decide show <id>
 ◆ 73 decisions — your call   cc-decide list --open          ← standing pile, unchanged, demoted
 …
```

- The header text fits in 100 cols: 95 chars at N=56 with the state clause (measured: python `len()` of the string).
- Line 2 uses the existing `yours` idiom: itemized, never collapsed, exempt from MAX (`:1526-1550`).

**Trigger.** A durable record THIS session filed. Never prose, never transcript shape.

1. **Primary:** an open class-C packet with `.session_sid == SID`. This is the human-checkpoint
   primitive, and the ledger already makes it ⛔ (wrap-ledger.sh:2500-2511). Needed in the readout:
   - (a) A decisions-leg session split mirroring `:1125`: `session_sid == $sid` goes to class
     `yours-decision`, otherwise `decision`. Same single jq, so the exclusion stays structural.
   - (b) A `"⛔")` state arm. Today it is missing, so `state=""` (§5 B). That is the
     new-enum-member-falls-into-the-default class this file already warns about (`:1246-1249`).
   - (c) When a session-owned packet carries a research marker, the header reads `Research done —
     implementation pending your sign-off: <N> <unit>`. The marker is a field such as
     `producer:"research"` plus `items:N`, or a dedicated `kind`. It must be read back through the
     consumer (closed-vocabulary lesson, `.claude/rules/agent-operating-lessons-situational.md:72`).
     Without the marker the header reads `⛔ your call: <what_plain>`.
2. **Fallback, already working:** a `cc-backlog needs … --session SID` row (scenario C). The research
   wording applies when the row carries the same marker.
3. **Lifecycle:**
   - `cc-decide action|veto <id>` resolves the packet. The line disappears, because the stamp moves
     on `DEC_DIR` and the hash moves on the content.
   - The session then recycles into implementation. The `--recycle` actuator is the session's, after
     the ruling. boundary-handoff's free-win arm should key its "no operator step outstanding"
     claim (:847) on `BLOCKED=0 ∧ YOURS=0`, so it cannot fire before the sign-off.
   - Reversible, non-breaking, lower-stakes work: no packet is filed, the agent just implements, and
     no line renders. This matches the operator's carve-out.

**Why pure Q&A cannot print it.**
- By construction: the line exists only if this session wrote a packet or row. Q&A writes none.
- This is the same polarity law as YOURS/BLOCKED: an unresolvable session never manufactures a rung
  (wrap-ledger.sh:52-54, :70).
- It does not depend on CERT_WROTE. A research turn is CERT_WROTE=1 by nature, so gating on it
  would silence exactly this case.

**What is NOT proposed for the readout:** a transcript heuristic deciding to render. Measured with
`python3 -I /tmp/rpic-C-readout/freq.py` over 1206 main transcripts (all 6 stores, mtime ≤7 d,
<60 MB), main-thread `isSidechain=false`, 1485 human-origin `cli` turns, where "no-edit" means no
Edit/Write/MultiEdit/NotebookEdit in the turn:

| no-edit turns that… | count | share of 1485 |
|---|---|---|
| spawned ≥1 Agent | 17 | 1.1% |
| spawned ≥3 Agents | 3 | 0.2% |
| cite ≥1 backticked 12-hex id | 62 | 4.2% |
| cite ≥3 such ids | 14 | 0.9% |
| say "recommend" and a conviction % | 31 | 2.1% |

- Sampled hits (`freq3.py`) include ⛔-waiting closes and plain answers, for example "Not
  automatically, but up to the full $4,000 is at risk …". So the signal is noisy.
- The incident's own research turn misses the "no-edit" test, because its main thread wrote
  `/tmp/xd/g99.md`. A heuristic would need the cwd-scoped oracle.
- Conclusion: the heuristic is fit only to **demand a filing** (a completion-assert arm: research
  shape, no session-owned packet or row, verdict "yes" ⇒ block once and ask for the packet). It is
  not fit to render a claim on the operator's surface.

## 7. Evidence index

- Code: `hooks/operator-readout.sh` :18-27, :35-46, :638-722, :815-820, :1015-1060, :1125, :1237-1355,
  :1446-1447, :1491-1523, :1526-1550, :1751-1753, :1855-1904, :1987-2025, :2032-2162.
- Lib: `hooks/lib/session-writes.sh` :30-44, :83-104, :353-392.
- `hooks/session-continue.sh` :13-14, :1018-1103, :1168-1243, :1288-1329.
- `hooks/boundary-handoff.sh` :468-562, :513, :847.
- `scripts/wrap-ledger.sh` :40-56, :1483-1500, :2500-2511, :2619-2625.
- `hooks/lib/close-shape.sh` :227-243.
- Transcript T: records 24, 86, 97-98, 241-278, 293, 310, 314-413, 465-469, 567.
- IDL: `~/.claude/autonomy/idl.jsonl` rows 25378-31822 for sid 74728043.
- Scratch scripts: `/tmp/rpic-C-readout/{scan2,hooks,dump,cmp,cw,inc,dec,freq,freq3,sandbox}.*`.
