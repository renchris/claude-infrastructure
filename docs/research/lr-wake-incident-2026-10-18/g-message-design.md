# G: message design for pane banners and the Stop readout (lr wake incident, 2026-10-18)

Slot G of the lr-wake-incident research. Read-only investigation. The repo is at trunk `b2a295c94`
(worktree `wt-cc-125908-4435`). The live kitty state was read once at 13:16 CDT (18:16Z) with
`kitten @ ls` and `kitten @ get-text` on all 54 windows. Scratch copies: `/tmp/gmd-ls.json` and
`/tmp/gmd-all.txt` (not durable).

---

## 1. Answer first

**Root cause.** Each of about 12 producers writes its own banner into the pane, in its own
style, with no shared renderer and no rule that one event gets one line. Each banner prints its
diagnosis (paths, counters, env knobs, timestamps) where the verdict should be. Several banners
also say something that is false at the moment the operator reads them:

- the capacity refusal promises a "next evaluation" that never runs in that pane;
- "CLOSED CLEANLY … safe to close" is painted 23 s before the closer refuses to close;
- the refusal's override hint names the wrong knob;
- class-B rows that already fired are listed as "auto-fire ≤24h".

**The fix.** Add one sourced helper, `lib/cc-say.sh`, that every producer calls. It is bash 3.2
and zsh safe, with a Python twin. It prints exactly one line: `glyph · verdict · ▶ one action`,
in explicit truecolor (never SGR-2). The full diagnosis goes to a JSONL log, and a terminal shows
it only under `CC_SAY_VERBOSE=1`. Then migrate the 6 most frequent banners and the Stop readout
to it. On the readout:

- line 1 is about this session only;
- the standing piles collapse into one footer of counts;
- every row fits a 57-column pane.

---

## 2. Evidence (measured)

### 2.1 What is on screen right now

Lines counted with `grep -c` over `/tmp/gmd-all.txt`, which holds the visible screens of all 54
kitty windows captured at 13:16 CDT.

| Banner (producer) | Lines on screen now | Notes |
|---|---|---|
| `-- lr-fire-resume: …` (scripts/limit-recover/lr-fire-resume.sh) | 18 | 14 of them are the same `tombstone check: this IS the transplant target … — the successor resuming itself` (:370) |
| `lr-preseed: …` (scripts/limit-recover/lr-preseed-env.sh:136) | 15 | all `trust + upsell gates already set for <path>` |
| Echoed launch line (bin/cc-pane-runner:310 `printf '%s\n' "$1"`) | 14 husks (16 incl. prompt-typed) | length min 73 / **median 335** / max 435 chars (measured `awk length`). At 57 cols that is 6–8 rows |
| `cc-pane-runner: the fleet launch line exited N — keeping a shell…` (:180) | 14 | **13 × `exited 9`** (capacity refusal), 1 × `exited 1` (bad `cd`) |
| Stop readout `⎿ Stop says: OPERATOR ▸ …` (hooks/operator-readout.sh) | 14 panes | **20 rows at 76 cols, 27 rows at 57 cols** (two captures, §2.3) |
| `✗ capacity-admit: REFUSING …` plus 2 advice lines (lr-fire-resume.sh:789-791) | 13 blocks = 39 lines | all 13 are the **active-ceiling** term (`N sessions mid-turn + T token(s) in flight + 1 > active ceiling 8`) |
| `[cc-close-attrib] / [lr-fire-resume] session ended … staged successor <path>` | 3 + 2 | full `~/.claude/run/pane-successor/ttys000.claimed.NNNN` path |
| `config-mirror: N file(s) in .claude-next shadow ~/.claude …` (lib/config-mirror.zsh:221) | 3 | re-printed at every launch in the same pane (pane 1 shows it again after each successor) |
| `◆ claude pid N has not registered a session after 20s …` (bin/cc-close-attrib:501) | 2 | 230+ chars, ends in a log path |
| `✅ CLOSED CLEANLY — …` block (hooks/lead-crash-watchdog.sh:1733) | 2 | 7–15 rows, 80-char rules |

Pane widths, from `jq '[.[].tabs[].windows[].columns]|group_by(.)'`: 37 cols × 6, 45 × 10,
57 × 10, 76 × 7, 115 × 2, 231 × 19. **26 of 54 panes are 57 columns or narrower.** A banner that
does not fit 57 columns wraps in half the fleet.

### 2.2 A refusal husk, verbatim (pane 435, OS window 18 tab 173)

```
Last login: Sun Oct 18 05:49:00 on ttys087
cd /Users/chrisren/Development/personal && nocorrect CC_ACCOUNT_PINNED=1 /tmp/lr-rescue/resume-2e9ed9f2.sh --strict-mcp-config --mcp-config=/var/folders/…/cc-mcp-userscope-.claude-tertiary.json --settings=/var/folders/0s/t55z…   (≈400 chars)
-- lr-fire-resume: tombstone check: this IS the transplant target (/Users/chrisren/.claude-tertiary) — the successor resuming itself
lr-preseed: trust + upsell gates already set for /Users/chrisren/Development/personal
✗ capacity-admit: REFUSING resume 2e9ed9f2-9e21-4161-a0f7-10b329ade8f0 on next3 — 8 sessions mid-turn + 1 > active ceiling 8 (refusal 3 of 3; once the budget is spent the next evaluation ADMITS and pages)
  Shed load first (close finished panes / let the wave drain), then re-run this exact command.
  Override for one resume: CC_ADMIT_GATE=off ; raise the bar: CC_ADMIT_MAX_LOAD_PER_CORE=<n>
cc-pane-runner: the fleet launch line exited 9 — keeping a shell for diagnosis/resume
➜ claude-infrastructure git:(main)
```

That is 7 lines (about 20 rows at 57 cols) for one fact: *2e9ed9f2 did not start, and nothing will
retry it here.* Three of the statements in it mislead:

- **"re-run this exact command."** The command is the 400-char echo, which has scrolled and wrapped.
- **"refusal 3 of 3; once the budget is spent the next evaluation ADMITS."** Nothing in this pane
  evaluates again: the runner keeps a bare shell (`bin/cc-pane-runner:180`).
- **"raise the bar: CC_ADMIT_MAX_LOAD_PER_CORE."** The refusing term is the active ceiling, whose
  knob is `CC_ADMIT_ACTIVE_CEILING` (scripts/lib/capacity-admit.sh:1446). The hint is hard-coded
  at scripts/limit-recover/lr-fire-resume.sh:791, although the gate already exports which term
  refused, in `CC_ADMIT_REFUSAL="${term} ${n} ${budget}"` (capacity-admit.sh:1638).

The same 2e9ed9f2 refusal appears in panes 425, 426 and 435 (refusals 3/3, 2/3, 3/3). That is
three husks for one session.

### 2.3 The Stop readout, verbatim

First capture, 76 cols:

```
  ⎿  Stop says: OPERATOR ▸ 3 runnable now, 234 need your call · ✅ live on
     trunk
      ▶ cc-do --run --expect 3:3867814045   [3 runnable]
      ◆ 67 decisions — your call   cc-decide list --open
      ◆ 167 blocked backlog — work keeps stopping at these 2   cc-backlog
     list --blocked
        ◆ b13ef5862c83  blocked 7× · unchecked 7d — Apply the 5 harvested
     allow rules…
        ◆ a8f3c6eaa960  blocked 6× · unchecked 17d — BytePlus ModelArk
     US-territory…
        ─ 103 of 167 last re-checked >14d ago — premise unverified
      ⚠ 3 stranded session(s) — closed by a mover, relaunch failed:
        ▶ cc-do 87df20238deb   [40b80c03 · c3-40b80c03 · next4]
        ▶ cc-do 6d3f1d6cd329   [6507a980 · wt-feat-dwell-telemetry · next4]
        ▶ cc-do 09123f46c397   [a2601c01 · lr-stranded-husk · next4]
      ⟳ lr-recon: 3 cohorts open · 1 moving · 3 waiting · 1 held · 0
     escalated
      ◆ 1156 escalation record(s) unseen — cc-escalations ack --all
      ◆ research truememory-2-0: 0 pending concern(s) — menu: the one extra
     round set (1 per program) (1 certification round (8 reviewer reads)) ·
     reopen certified scope (operator-caused) (a new certificate version)
     cc-research verdict truememory-2-0
      ─ 3 class-B default(s) auto-fire ≤24h (earliest 2026-10-18T05:00:00Z)
     — veto: cc-decide veto <id> · board: cc-blockers
```

The second capture, at 57 cols, rendered the same block in **27 rows**, with
`⚠ lr-recon: reconciler heartbeat stale 14m25s` in place of the ⟳ row.

Measured defects in it:

- **Line 1 leads with the standing pile.** "234 need your call" is not this session's, and the
  header code says so itself (hooks/operator-readout.sh:1505-1512). The demotion only happens on
  the certified-✅ path.
- **The class-B row prints a deadline that has already passed.** It says `earliest
  2026-10-18T05:00:00Z` as "auto-fire ≤24h", but `date -u` returned 18:17Z. The filter is
  `.veto_deadline <= $h` with no lower bound at NOW (operator-readout.sh:1366-1368, 1372-1374).
- **The escalation pile drifts between panes:** 1156 in one capture and 1088 in another. It is a
  standing pile with no per-session action, yet it takes 1–2 rows every time.
- **The research menu row wraps to 4 rows** for a program with 0 pending concerns.
- **Rate.** `grep operator-readout ~/.claude/autonomy/idl.jsonl` covers 12:18Z–18:17Z today:
  1155 invocations, 156 `fired`, 926 `stamp-unchanged-ttl` abstains. The damping works; the volume
  per fire is the problem.

### 2.4 The CLOSED CLEANLY banner contradicts the closer (pane 1 and pane 242)

`~/.claude/logs/lead-crash-watchdog.log`:

```
[2026-10-18 02:07:23] [watchdog e52f1f63-…] pane verdict PAINTED on ttys000 (pane 1): ✅ CLOSED CLEANLY — Claude session e52f1f63 exited on its own (reason: -); nothing relaunched here
[2026-10-18 02:07:46] [watchdog e52f1f63-…] pane close of 1 via cc-pane-close rc=1: pane 1: REFUSED — nothing says session e52f1f63 meant to end (last close: -; not a teammate; no custody ruling) — resume or triage it instead: cc-husk-sweep --pane 1
[2026-10-18 05:40:33] [watchdog 0d7c9a19-…] pane verdict PAINTED on ttys005 (pane 242): ✅ CLOSED CLEANLY — …
[2026-10-18 05:40:54] [watchdog 0d7c9a19-…] pane close of 242 via cc-pane-close rc=1: pane 242: REFUSED — nothing says session 0d7c9a19 meant to end …
```

- **The pane and the log disagree.** The pane says "✅ … This pane holds nothing: safe to close".
  The closer's verdict, which says the opposite, goes only to the log. The banner's "cleanly" rests
  on `reason: -` and `last close verdict: -`, which is no evidence either way
  (hooks/lead-crash-watchdog.sh:1733-1745, 1792-1793).
- **e52f1f63 was then the target of a rescue in pane 413, which was refused** (§2.1 table, `refusal
  2 of 3`). So the session the banner calls "closed cleanly" was the one the fleet was still trying
  to resume.
- **The block renders as fragments at 57 cols.** In pane 1, the hard 80-char `rule`
  (lead-crash-watchdog.sh:1676) wraps to 2 rows, and the body comes back mid-word
  (`✅ CLOSED CLEANLY — Claude session e52f1f63 e` / ` own (reason: -)…`).

### 2.5 The colour palette is already forked

`grep -rhoE '38;2;[0-9]+;[0-9]+;[0-9]+' bin lib hooks scripts | sort | uniq -c` finds five
different "gray" values (153,153,153 · 150,150,160 · 150,150,150 · 140,140,140 · 125,133,144),
two ambers (255,193,7 · 255,217,89) and two reds (255,107,107 · 255,95,95). The never-SGR-2 rule
is written down in four places (bin/claude-accounts:8054, bin/cc-where:48, bin/cc-offload:122,
lib/config-mirror.zsh:220) and broken in two: `bin/cc-lid:127` (`d=$'\e[2m'`) and
`scripts/kitty-setup.sh:158` (`\033[2m·`). No shared renderer exists:
`grep -rln 'cc_say\|render helper'` over lib/, hooks/lib/, bin/, scripts/lib/ and docs/plans/
found none (one hit was bin/cc-blockers, which is unrelated).

### 2.6 Tests that pin today's strings

These will need edits during migration (counted with `grep -rlF` over tests/):

| String | Test files |
|---|---|
| `OPERATOR ▸` | 10 files |
| `class-B default` | 7 |
| `escalation record` | 5 |
| `stranded session` | 4 |
| `tombstone check` | 2 (lr-fleet.bats, lr-fire-resume-direct-invocation.bats) |
| `bounds: move` | 2 (lr-move-plan.bats, cc-lr-front.bats) |
| `CLOSED CLEANLY` | 1 (lead-crash-pane-verdict.bats) |
| `keeping a shell for diagnosis` | 1 (pane-close-from-inside.bats) |
| `config-mirror:` | 1 (config-mirror-assert.bats) |
| `Shed load first` | 0 |
| `lr-preseed:` | 0 |
| `has not registered a session` | 0 |

---

## 3. Causal chain

1. **Origin (overnight).** lr movers and agent-written rescue scripts (`/tmp/lr-rescue/resume-*.sh`,
   seen in panes 403/409/413/426/435) fired resumes into new kitty tabs of OS window 18. That window
   holds tabs 156–167 and 173, one shell pane each. They fired while next2/next3 were at the active
   ceiling of 8.
2. **Mechanism, step 1.** Every resume runs a pipeline in which each stage prints its own status
   to the pane's stderr:
   - `cc-pane-runner` echoes the whole launch line (:310);
   - lr-fire-resume prints its tombstone check (:370);
   - lr-preseed prints (:136);
   - the capacity gate prints a 3-line refusal (:789-791);
   - `cc-pane-runner` prints its exit line (:180).

   No stage knows whether another already reported the outcome, and none has a "one line, verdict
   first" contract.
3. **Mechanism, step 2.** After a refusal (rc 9) the runner keeps a bare shell. So the banner stays
   on screen indefinitely, and its "re-run this exact command" and "next evaluation ADMITS" become
   standing false promises.
4. **Mechanism, step 3.** The watchdog paints its verdict before the closer decides
   (lead-crash-watchdog.sh:1790 paints; :1793 then calls `pane_verdict_close`). When the closer
   refuses, the pane is left showing "safe to close".
5. **Mechanism, step 4.** The Stop hook renders the machine-wide standing piles (decisions,
   blocked backlog, escalations, research, class-B) in every session that fires. It does so at
   fixed text widths of ~70–90 chars, in panes that are 37–57 cols.
6. **Visible state.**
   - 13 refusal husks and 1 bad-`cd` husk, each with 7+ lines of text.
   - 2 "CLOSED CLEANLY" husks that the closer refused to close.
   - 14 sessions whose last turn ends in a 20–27-row readout, most of which is not about that
     session.
   - The operator sees walls of text that do not answer "do I need to do anything, and what?".

INFERRED, not measured: the producers grew one incident at a time, and each fix added a line
explaining itself (the code comments at these sites are incident narratives). Without a shared
renderer there was no place to enforce a budget.

---

## 4. Immediate remediation for the live state (describe only; nothing was done)

1. **The 13 refusal husks**: panes 409 410 412 413 414 416 417 418 419 425 426 435 (OS window 18)
   and 428 (OS window 24).
   - Each refused session is **not running** from that pane.
   - For each sid8 on screen (5232121f, e52f1f63, 2e9ed9f2, 509e3aad, …), first confirm where it
     lives now: `cc-lr find <sid8>`. Several panes name the same sid (2e9ed9f2 ×3).
   - Resume each distinct sid **once**, via `cc-lr recover <sid8>`, only when the target's active
     count is under the ceiling.
   - Then close all of these husk panes. They hold nothing but text.
2. **Pane 403** (bad `cd $'whose\n/Users/…'`, exit 1): the rescue line was garbled when it was
   generated. Close it after confirming 5232121f is live somewhere (`cc-lr find 5232121f`).
3. **Panes 1 and 242** ("✅ CLOSED CLEANLY", closer REFUSED): run `cc-husk-sweep --pane 1` and
   `cc-husk-sweep --pane 242`. Resume only if the sweep finds the session is not live elsewhere
   (e52f1f63 was itself a rescue target). Then close the panes.
4. **Panes 401 and 332** (operator-typed shell and an ended lr session): close them, or reuse them
   on purpose.
5. **No change to message rendering is needed to unblock anything.** Three small fixes are safe to
   land ahead of the full migration (§5.4 items Q1–Q3): the wrong override knob, the class-B
   past-deadline filter, and the watchdog painting "safe to close" before the closer has ruled.

---

## 5. Long-term fix

### 5.1 Design rules (apply to every banner)

| Rule | Statement |
|---|---|
| R1 One event, one line | The stage that knows **why** prints the verdict. Every other stage stays silent about that event: the runner prints nothing after rc 9, because the gate already spoke. |
| R2 Answer first | Each line has this shape: `glyph verdict-in-≤6-words · the one fact that matters · ▶ action`. No action needed ⇒ no `▶`, and the line is gray. |
| R3 One action | At most one `▶` per line. It must be a pasteable command of ≤ 40 chars, using a sid8 or a batch id, never a 400-char launch line. The command bytes carry no SGR, so a drag-selection copies clean (already the readout's rule, operator-readout.sh:124-125). |
| R4 Fits 57 cols | Pane lines ≤ 56 cells. Stop-readout rows ≤ 52 cells (usable width = pane − 5, per docs/lessons/sessionstart-systemmessage-accepts-sgr.md finding 6). Row 1 ≤ 38 cells after the `⎿  Stop says: ` prefix. Truncate prose with `…`; never truncate a command. If a command does not fit, it moves to its own indented row. |
| R5 Detail goes to a log | Paths, counters, knobs, timestamps, the full command and "why" go to `~/.claude/logs/pane-say.jsonl` (one record per call: ts, tool, sid, pane, kind, verdict, action, detail). The terminal shows them only with `CC_SAY_VERBOSE=1` (or the tool's `--verbose`), as gray rows indented by 2. |
| R6 Truthful tense | Never promise a future step the current process will not take ("re-run", "next evaluation", "safe to close"). The verdict is computed after the decision it reports (fixes §2.4). |
| R7 No rules, no boxes | Drop the 80-char `────` rules: they wrap at 57 cols. Separation comes from the glyph's colour. |
| R8 Standing piles are not banners | Counts of machine-wide piles never appear in a pane, and only as one footer row in the Stop readout. A row is itemised only if it is this session's, new since the operator last saw it, or due in the future within 24 h. |

**Glyphs.** Use only single-cell glyphs in panes, because emoji are 2 cells and break the width
math at 37–57 cols. This reuses the readout's existing vocabulary and adds no new mark:

| Glyph | Meaning |
|---|---|
| `✓` | done |
| `⟳` | in progress, nothing to do |
| `⏸` | waiting, something will retry |
| `✗` | failed, nothing will retry |
| `⚠` | look at this |
| `▶` | run this exact command |
| `◆` | judgment |
| `─` | footer |

Keep `▸` reserved for the readout header (operator-readout.sh:94). The OSC-2 window title may keep
`✅/⛔`.

**Colour.** Explicit truecolor only. **Never SGR-2 (`\e[2m`)**, and never `\e[0m` inside a
systemMessage: Ink normalises it, and a full reset turns the rest of the row from the harness gray
to white. Inside the Stop readout, end with `\e[39m\e[22m`, or re-assert `38;2;153;153;153`.

| Role | RGB | Used for | Origin |
|---|---|---|---|
| ok | 107,243,133 | `✓` and the verdict word | bin/cc-offload `C_OK`, bin/cc-where `on` |
| warn | 255,193,7 | `⚠ ⏸` and the verdict word | Claude Code's own `⚠` amber; operator-readout.sh:381 |
| bad | 255,107,107 | `✗` and the verdict word | cc-offload `C_BAD` |
| act | 138,180,248 | the `▶` glyph only (command bytes stay plain) | cc-offload `C_HEAD` |
| meta | 150,150,160 | facts after `·`; verbose rows; whole line when no action | cc-offload `C_META` |
| quiet | 125,133,144 | the Stop-readout footer (must differ from the harness's 153 gray) | lib/config-mirror.zsh:220 |

Colour goes on when the target is a tty (`[ -t 2 ]`), when the tool writes to a `/dev/ttysNNN`
by path (the watchdog), or for a systemMessage. `NO_COLOR` or `CC_SAY_COLOR=0` turns it off.

### 5.2 The shared helper: `lib/cc-say.sh` (new) plus `lib/cc_say.py` (twin)

It is a sourced file with no side effects at load, written in the shell subset that both bash 3.2
and zsh accept: no arrays, no `local -a`, no `[[ =~ ]]`. One file therefore serves bin/, scripts/
and `lib/config-mirror.zsh`. It forks nothing on the hot path; the log append is one `printf >>`.

```sh
# cc_say KIND VERDICT [FACT] [ACTION]   — prints ONE line to fd 2 (or $CC_SAY_FD); always rc 0
#   KIND    ok | wait | run | fail | warn | info        (→ glyph + colour, per §5.1)
#   VERDICT ≤ 6 words, answer first ("2e9ed9f2 not resumed")
#   FACT    the one fact that makes the verdict true ("next3 full 9/8")   — meta gray
#   ACTION  one pasteable command ≤ 40 chars ("cc-lr recover 2e9ed9f2")   — printed byte-plain after ▶
# env: CC_SAY_TOOL (log tag) · CC_SAY_DETAIL (free text → log only, or a gray row under VERBOSE)
#      CC_SAY_VERBOSE=1 · CC_SAY_COLOR=auto|1|0 · NO_COLOR · CC_SAY_WIDTH (default: $COLUMNS, else 56)
#      CC_SAY_TARGET=tty|sm (sm = systemMessage: no \e[0m, re-assert 153 gray) · CC_SAY_LOG (path)
cc_say()        { … }   # the one renderer
cc_say_detail() { … }   # append a detail record without printing (for stages that must stay silent per R1)
cc_say_width()  { … }   # the cell budget the line was fitted to (tests assert against it)
```

Python twin `lib/cc_say.py`: `say(kind, verdict, fact="", action="", detail="")` with the same
contract and the same log. It is for `lr-preseed-env.sh`'s inline Python (:95-151), `lr_recon`
(`readout.line`), and `bin/claude-accounts` (whose `c()` at :8053 becomes a thin wrapper).

The readout keeps its own composer, because it renders a multi-row block, but builds every row
with `cc_say` under `CC_SAY_TARGET=sm`. It keeps its NSTEPS anchors (`^ [0-9]+ (▶|◆|✎)`), so the
colour still starts after the mark (operator-readout.sh:2186-2190).

### 5.3 Per banner: what the operator decides, the after state, what moves out

#### A. Echoed launch line — bin/cc-pane-runner:310 (`_launch`)

**Decides:** nothing.

**After:**

```
⟳ resuming 2e9ed9f2 · next3 · personal
```

(meta gray), or `⟳ starting <verb> · <cwd basename>` for a non-lr command.

**Moves out:** the full command goes to the log, and appears under `CC_SAY_VERBOSE=1`.

**Must-verify:** the comment at :383-385 says a `kitty @ get-text` progress probe anchors on the
echo. Grep its consumers before shortening it. If one matches command text, give it a stable token
in the short line instead (the sid8).

#### B. Runner exit lines — bin/cc-pane-runner:176-220

**Decides:** whether the pane closes, which the operator rule says it always should unless a
session runs.

**After:**

- rc 9 or rc 3 from an lr launcher: **silent** (R1, because the gate spoke).
- Other non-zero rc:

  ```
  ✗ launch failed (exit 1) · shell kept · ▶ cc-husk-sweep --pane 403
  ```

- rc 0 and closing: silent.
- Kept because of the fullscreen guard:

  ```
  ⚠ last pane of a fullscreen window · kept · close it by hand
  ```

**Moves out:** the `CC_PANE_CLOSE_ON_EXIT=0` hint and the guard path go to the log.

#### C. lr-fire-resume preflight — lr-fire-resume.sh:370, :636, :647, :675, :703, :771, :799, :839, :867, and lr-preseed-env.sh:62, :95, :136, :145, :151

**Decides:** nothing in all 18 measured lines.

**After:** stay silent until a decision exists. Then print **one** line just before `claude`
starts:

```
⟳ resuming 2e9ed9f2 on next3 · checks ok
```

A non-fatal anomaly turns it amber and names only that anomaly:

```
⚠ resuming 2e9ed9f2 on next3 · no submit proof
```

**Moves out:** every `-- …` and `lr-preseed:` line becomes a `cc_say_detail` record, written to
the log and to `$LR_RUN_DIR/preflight.log` (the run dir already exists, :121).

**Stays visible:** the `✗`/`REFUSED` paths at :360-379, :485-499, :548-573, :629-687 and :722 —
each reduced to one line with one action.

#### D. Capacity refusal — lr-fire-resume.sh:789-791 (the text itself comes from capacity-admit.sh:1637)

**Decides:** a real one. The session is not running.

**After**, when nothing retries (today's truth for an in-pane refusal):

```
✗ 2e9ed9f2 not resumed · next3 full 9/8 · ▶ cc-lr recover 2e9ed9f2
```

**After**, when a driver will retry (reconciler cohort):

```
⏸ 2e9ed9f2 queued · next3 full 9/8 · retries when a slot frees
```

**Moves out:** the budget arithmetic ("refusal N of 3 … ADMITS and pages"), "Shed load first …",
and the override goes to verbose. The override is picked from `CC_ADMIT_REFUSAL`'s term:
active → `CC_ADMIT_ACTIVE_CEILING`, load → `CC_ADMIT_MAX_LOAD_PER_CORE`, headroom →
`CC_ADMIT_MIN_HEADROOM_GB`.

Needs a short form of the gate reason: add `cc_capacity_admit_short` to capacity-admit.sh, next
to :425. It should return `next3 full 9/8`, or `load 14.2/core > 12`, or `4.1 GB free < 6`.

#### E. Pane verdict — lead-crash-watchdog.sh:1676 and :1700-1786 (all classes)

**Decides:** close, resume, or triage.

**After:** run the closer's predicate **first**, then paint (R6):

| Case | Pane text |
|---|---|
| closer will close | `✓ e52f1f63 ended cleanly · closing in 20s` |
| closer refused | `⚠ e52f1f63 ended, reason unknown · ▶ cc-husk-sweep --pane 1` |
| dirty work | adds one amber row: `⚠ uncommitted work in wt-cc-000146-45877` |
| crash | `✗ e52f1f63 killed (external-sigterm) · ▶ cc-husk-sweep --pane 1` |
| retired | `✓ retired by desk · closing in 20s` |

**Moves out:** the 80-char rules, "verdict painted <ts>", the full cwd path, "its last close
verdict: -", the pinned resume line, and Claude's own "Resume this session" disclaimer. The resume
line moves to the 2nd row only when the sweep says resume. The OSC-2 title stays.

#### F. config-mirror — lib/config-mirror.zsh:183, 211, 221, 226, 242, 279

**Decides:** nothing now. It can be fixed only with that account's panes closed.

**After:** print nothing in panes. Write one record per account per day to the log. Surface it as
part of the Stop readout footer count (`1 config fork`), and in `claude-accounts`.

**Exception:** the :279 auth-key line stays, as `⚠ next: auth key in settings.json · move to
settings.local.json`, because it is a correctness fault.

#### G. Launch stall — bin/cc-close-attrib:501

**Decides:** nothing. "Not killed; it resumes."

**After:** `⏸ claude 33120 waiting on keychain · 20s · no action` (meta gray).

**Moves out:** the log path and the secd explanation go to verbose.

#### H. Session-ended lines — bin/cc-close-attrib:596/599 and lr-fire-resume.sh:1855/1859

**Decides:** nothing.

**After:** `⟳ e52f1f63 ended · starting successor` (meta gray). The 1859 case is
`⚠ session ended · pane kept · close it (Ctrl-D)`. Better still, the pane closes, which is
another slot's fix.

**Moves out:** the `ttys000.claimed.NNNN` path goes to the log.

#### I. `cc-lr move` output — bin/cc-lr:335, 1354-1364, 1422, 1629, 1677

**Decides:** wait, or come back later.

**After** (answer first, one status command, deadline in local time):

```
⏸ f06b5e9b moves next → next2 when idle · due 02:20
  ▶ cc-lr move --status 20261018T065519Z-next-next2-70106
```

The table prints only when there is more than 1 row or with `--verbose`.

**Moves out:** the `bounds:` line (:1422, 250 chars of internal knobs) goes to `--verbose`. The
three repetitions of `cc-lr move --status <batch>` (:335, :1629, :1677) become one.

#### J. Stop readout — hooks/operator-readout.sh

Covered in §5.3.1 below.

#### 5.3.1 Before/after mockups

These are the 6 most frequent banners by on-screen line count (§2.1), plus the Stop readout. All
"after" lines are ≤ 56 cells. Colours are noted on the right.

**1. lr-fire-resume preflight** (18 lines on screen)

```
BEFORE  -- lr-fire-resume: tombstone check: this IS the transplant target (/Users/chrisren/.claude-tertiary) — the successor resuming itself
        lr-preseed: trust + upsell gates already set for /Users/chrisren/Development/personal
        -- lr-fire-resume: resume-summary prompt suppressed at the source — resuming FULL AS-IS
AFTER   ⟳ resuming 2e9ed9f2 on next3 · checks ok                [⟳ meta gray, whole line meta]
```

**2. lr-preseed:** folded into #1. It goes from 15 lines to 0.

**3. Echoed launch line** (14 husks, median 335 chars)

```
BEFORE  cd /Users/chrisren/Development/personal && nocorrect CC_ACCOUNT_PINNED=1 /tmp/lr-rescue/resume-2e9ed9f2.sh --strict-mcp-config --mcp-config=/var/folders/…  (6–8 rows)
AFTER   (merged into #1's line; the full command is in pane-say.jsonl / CC_SAY_VERBOSE=1)
```

**4. Runner exit** (14)

```
BEFORE  cc-pane-runner: the fleet launch line exited 9 — keeping a shell for diagnosis/resume
AFTER   (silent — the refusal line already said it, R1)
BEFORE  cc-pane-runner: the fleet launch line exited 1 — keeping a shell for diagnosis/resume
AFTER   ✗ launch failed (exit 1) · ▶ cc-husk-sweep --pane 403   [✗ red · verdict red · fact meta · ▶ blue · cmd plain]
```

**5. Capacity refusal** (13 blocks × 3 lines)

```
BEFORE  ✗ capacity-admit: REFUSING resume 2e9ed9f2-9e21-4161-a0f7-10b329ade8f0 on next3 — 8 sessions mid-turn + 1 > active ceiling 8 (refusal 3 of 3; once the budget is spent the next evaluation ADMITS and pages)
          Shed load first (close finished panes / let the wave drain), then re-run this exact command.
          Override for one resume: CC_ADMIT_GATE=off ; raise the bar: CC_ADMIT_MAX_LOAD_PER_CORE=<n>
AFTER   ✗ 2e9ed9f2 not resumed · next3 full 9/8
          ▶ cc-lr recover 2e9ed9f2                              [command on its own row at 57 cols, R4]
```

**6. config-mirror** (3, repeated per launch)

```
BEFORE  config-mirror: 1 file(s) in .claude-next shadow ~/.claude (statusline.sh) — with its panes closed: _cc_sync_account --convert /Users/chrisren/.claude-next
AFTER   (pane: silent; Stop footer counts it as "1 config fork"; detail in the log)
```

**Also measured, less frequent: CLOSED CLEANLY (2) and launch stall (2)**

```
BEFORE  ──────────────────────────────────────────────────────────────────────────────── (wraps)
        ✅ CLOSED CLEANLY — Claude session 0d7c9a19 exited on its own (reason: -); nothing relaunched here (verdict painted 2026-10-18T10:40:33Z).
           work in /Users/chrisren/Development/.worktrees/wt-cc-233108-87354: clean · its last close verdict: -
           This pane holds nothing: safe to close (Ctrl-D). To reopen the session instead:
        ▶ nocorrect CC_ACCOUNT_PINNED=1 claude --resume 0d7c9a19-0b8b-4cfc-ac61-5f30e12aedbe
        ────────────────────────────────────────────────────────────────────────────────
AFTER   ⚠ 0d7c9a19 ended, reason unknown · not closed
          ▶ cc-husk-sweep --pane 242                            [⚠ amber · cmd plain]
BEFORE  ◆ claude pid 19489 has not registered a session after 20s: likely blocked in the keychain/system-CA query (secd). Not killed; it resumes when the query returns. Log: /Users/chrisren/.claude/logs/launch-stall.jsonl
AFTER   ⏸ claude 19489 waiting on keychain · 20s · no action   [whole line meta gray]
```

**Stop readout**

```
BEFORE  (20 rows @76 cols / 27 rows @57 cols — §2.3 verbatim)

AFTER   ⎿  Stop says: OPERATOR ▸ ✅ live on trunk · none yours  [▸ header; ✅ ok green]
             ⚠ 3 stranded on next4 · ▶ cc-do 87df20238deb       [⚠ amber; cmd plain]
               ↳ +2 · cc-resume-debt list --escalated           [meta]
             ⟳ lr: 1 moving · 3 waiting · 1 held                [meta; ⚠ amber if heartbeat stale]
             ─ 3 run · 67 decide · 167 blocked · 1156 esc       [quiet gray]
               ↳ board: cc-blockers                             [quiet gray]
```

That is 6 rows, each ≤ 52 cells. Rows that change it:

- **This session filed a step:** it gets a `▶`/`◆` row under the header, and the header becomes
  `▸ 1 step is yours`.
- **A class-B veto window is open:** one amber row `⚠ class-B fires 14:00 · ▶ cc-decide veto <id>`.
  This requires a deadline in the future, which is the Q2 fix.
- **Something new since the last readout:** e.g. `◆ +12 new escalations · cc-escalations ack --all`.
- **Research ruling owed:** only the program name and `▶ cc-research verdict <p>`. The menu prose
  goes to the board.

Damping: hash only these semantic rows (yours, urgent, stranded, lr state), not the footer counts.
A count that ticks from 1088 to 1156 then no longer re-renders the block.

### 5.4 Migration list

**Quick fixes, land first:**

- **Q1** — scripts/limit-recover/lr-fire-resume.sh:791. Name the knob from
  `CC_ADMIT_REFUSAL`'s term. Today it says `CC_ADMIT_MAX_LOAD_PER_CORE` for active-ceiling refusals
  (13/13 measured). The same advice text is at scripts/handoff-fire.sh:10317.
- **Q2** — hooks/operator-readout.sh:1366-1368 and :1372-1374. Add
  `and .veto_deadline >= $now` (pass `--arg now "$(epoch_to_iso "$NOW")"`). A past deadline is
  "fired" (or "overdue") and is never rendered as "auto-fire ≤24h".
- **Q3** — hooks/lead-crash-watchdog.sh:1790-1793. Evaluate `cc-pane-close --dry-run` (or the
  closer's predicate) before painting. If the closer will refuse, do not paint "holds nothing /
  safe to close". Paint the ⚠ triage line instead (§5.3 E).

**Helper:**

- **M0** — new `lib/cc-say.sh` and `lib/cc_say.py`, plus `tests/cc-say.bats`. Wire them into the
  `~/.claude/lib` symlink farm via the existing install path. Fix the two SGR-2 sites:
  `bin/cc-lid:127` and `scripts/kitty-setup.sh:158`.

**Migrations:**

- **M1** — bin/cc-pane-runner:100, 176, 180, 189, 193, 204, 211, 215, 220 (exit lines) and :310
  (echo). Update `tests/pane-close-from-inside.bats` and `tests/handoff-fire-argv-launch.bats`.
- **M2** — scripts/limit-recover/lr-fire-resume.sh:370, 424, 473, 636, 647, 675, 703, 771, 799,
  802, 839, 867, 869, 919, 979, 1855, 1859, 1868 become `cc_say_detail` plus one summary line.
  Lines 360-362, 377-379, 485, 498-499, 548, 558, 573, 629, 641, 648, 662, 678, 687, 722-723 and
  789-791 become one-line `cc_say fail`. Update `tests/lr-fleet.bats` and
  `tests/lr-fire-resume-direct-invocation.bats` (`tombstone check`).
- **M3** — scripts/limit-recover/lr-preseed-env.sh:62, 95, 136, 145, 151 become `cc_say.say(...)`
  detail-only.
- **M4** — scripts/lib/capacity-admit.sh:425 (add `cc_capacity_admit_short`), :1605, :1629 and
  :1637. Keep `CC_ADMIT_REASON` verbatim for logs and pages; panes use the short form.
- **M5** — hooks/lead-crash-watchdog.sh:1665-1786 (`pane_verdict_text`): the rule at :1676 goes;
  all class bodies become 1–2 `cc_say` lines; colour is on because the target is `/dev/ttysNNN`.
  Update `tests/lead-crash-pane-verdict.bats`.
- **M6** — lib/config-mirror.zsh:183, 211, 221, 226, 242: log only, plus a counted fact for the
  readout footer. :279 becomes a one-line `cc_say warn`. Update `tests/config-mirror-assert.bats`.
- **M7** — bin/cc-close-attrib:501, 596, 599.
- **M8** — bin/cc-lr:335, 1022-1028, 1354-1364, 1422, 1629, 1677, 1787, 2948. The verdict line
  goes first; the table and bounds go behind `--verbose` when there is one row. Update
  `tests/lr-move-plan.bats` and `tests/cc-lr-front.bats` (`bounds: move`).
- **M9** — hooks/operator-readout.sh:
  - :1504-1523: the header is this session's state only, with the standing pile out of line 1;
  - :598-603: `stranded_sessions`, 1 row plus `↳`;
  - :629: `lr_recon_line`, shortened;
  - :710-716: research, program plus command only;
  - :1375: class-B;
  - :1637, :1645, :1664, :1749, :1765-1778: the footer collapses into one counts row;
  - :2167: hash the semantic rows only;
  - :379-386: colour moves to the cc-say palette under `CC_SAY_TARGET=sm`.

  Update the 10 `OPERATOR ▸` test files, 7 `class-B` files, 5 `escalation record` files and
  4 `stranded session` files (§2.6).
- **M10** — scripts/limit-recover/lr_recon (`_report` → `readout.line`): ≤ 40 cells, the same
  vocabulary.

### 5.5 Tests that would have caught it

1. **`tests/cc-say.bats`** (new). Source the helper under `/bin/bash` 3.2 and under `zsh`, then
   assert:
   - exactly 1 line per call;
   - `grep -c $'\e\[2m'` is 0 in every output;
   - the ACTION bytes appear unmodified, with no SGR between `▶ ` and end of line;
   - the line is ≤ `CC_SAY_WIDTH` cells for widths 37, 45 and 57, and an over-long command wraps
     to its own row instead of being cut;
   - verbose-off writes the detail only to `CC_SAY_LOG`;
   - `CC_SAY_TARGET=sm` emits no `\e[0m`.
2. **`tests/pane-husk-screen.bats`** (new). This replays the measured pane-435 sequence:
   - Run `lr-fire-resume.sh` in a sandbox with `CC_ADMIT_ACTIVE_CEILING=0`, so the gate refuses,
     through `bin/cc-pane-runner` in env mode, and capture fd 2.
   - Assert: at most 2 non-empty lines; the first starts with `✗` and contains the sid8; a `▶`
     command of ≤ 40 chars exists; no line contains `re-run this exact command`; the override
     named in verbose output matches the refusing term.

   This would have failed on all four §2.2 defects.
3. **`tests/lead-crash-pane-verdict.bats`** (add case). Use a stub `CC_PANE_CLOSE_BIN` that exits 1
   with REFUSED. The painted block must not contain `holds nothing` or `safe to close`, and must
   contain `cc-husk-sweep --pane`. This would have caught §2.4.
4. **`tests/operator-readout.bats`** (add cases), with a fixture of 234 standing items, 1156
   escalations and 3 stranded sessions, plus a class-B row whose deadline is NOW − 1 h. Assert:
   - at most 7 rows;
   - every row ≤ 52 cells, and row 1 ≤ 38 cells after the prefix;
   - row 1 contains no standing-pile count;
   - the past-deadline class-B row is not rendered as `auto-fire ≤24h`;
   - changing only the escalation count does not change the damping hash.

---

## 6. Confidence

**80%** that this is the right root cause and fix for the message-readability complaint.

What it rests on:

- Every "before" text in this file is a measured screen or log capture.
- Every file:line was read at `b2a295c94`.
- The frequency ranking is one snapshot (13:16 CDT, 54 windows) and not a time series.

What would change it:

- **The launch echo has a dependent probe.** If a probe matches on the echoed command text
  (cc-pane-runner:383-385), M1 needs a stable token, not a pure shortening. I did not trace every
  `get-text` consumer.
- **The refusal may be retried after all.** If some driver re-fires refusals (reconciler cohorts),
  the after state for those panes is `⏸ queued`, not `✗ not resumed`. That needs the per-run
  `relaunch.rc` consumer read for each path; I did not do this.
- **The width budget assumes today's layouts.** If the operator's 4-pane layout is normally ≥ 76
  cols and the 37–57-col panes are an overnight artefact of the tab sprawl, the budget can relax to
  70 cells. The rules stay the same.
- **Out of scope.** Whether husk panes should exist at all (they should not, per the operator's
  rule) belongs to the pane-lifecycle slots. This design keeps them truthful and one line while
  they do.

Deviation note: one scratch script was written to `/tmp/gmd-cap.sh` with a heredoc to capture pane
screens. It was a read-only capture helper, not a repo edit. No pane was typed into, focused or
closed.

---

## Adversarial verification

Verifier pass, 13:20-13:30 CDT (18:20-18:30Z), read-only, trunk `b2a295c94`.

**Verdict: not refuted.** The root cause holds for the readability complaint: there are many
producers, none shares a renderer, and none has a one-line contract. Most citations say what the
file claims. But two of the four "false banner" defects come from a different mechanism than the
one given here. A shared renderer alone would not have fixed either of them, and one proposed
action may itself be a false promise.

### V1. Citations re-opened (MEASURED, `sed -n` at `b2a295c94`)

These citations are correct:

- `bin/cc-pane-runner:180` (the rc!=0 "keeping a shell" line) and `:310` (`printf '%s\n' "$1"`).
- `:383-385` (the get-text probe comment).
- `lr-fire-resume.sh:370` (tombstone) and `:789-791` (the 3-line refusal, with the knob hard-coded at :791).
- `capacity-admit.sh:425`, `:1446`, `:1637` and `:1638`.
- `lead-crash-watchdog.sh:1676` (the 80-char rule), `:1733` (the CLOSED CLEANLY headline), `:1790` (paint) and `:1793` (the close call after the paint).
- `operator-readout.sh:1366-1374` (no lower bound at NOW) and `:1505-1512` (the pile is demoted only on the certified path).
- `bin/cc-lid:127` and `scripts/kitty-setup.sh:158` (SGR-2).
- `lr-preseed-env.sh:136`, `config-mirror.zsh:220-221` and `cc-close-attrib:501`.

The watchdog log lines in §2.4 match `~/.claude/logs/lead-crash-watchdog.log:63740,63743,63865,63866`
verbatim. Watchdog timestamps are local CDT, so 02:07:23 is 07:07:23Z.

### V2. Corrections

1. **CLOSED CLEANLY is a misclassification, not a paint-before-decide ordering bug.** In
   `~/.reso/limit-recover/e52f1f63-…/bundle-20261018T065243Z/events.jsonl` the lr move for
   e52f1f63 (`assign_id=20261018T064955Z-next4-next2-7738`) has these events:
   - `recycle-armed … the recycle is firing on pane 1` at 07:01:41Z;
   - `state:"STRANDED" … the recycle did not verify (handoff-fire rc=1): the transplant is DONE`
     at **07:06:55Z**.

   The watchdog then classified the death as `class=RECYCLE cause=clean-exit` (log line just
   above 63740) and painted "exited on its own … safe to close" **28 s after** lr had recorded
   STRANDED. 5232121f (pane 21) went the same way at the same second; this file misses that
   third instance. The closer's REFUSED ("nothing says session meant to end") was the **correct**
   safety behaviour. The code expects the two to disagree: `lead-crash-watchdog.sh:1812` says
   "The banner stays: if the closer refuses, it is still right."

   So Q3 (`cc-pane-close --dry-run` before painting) would turn the false ✅ into
   `⚠ ended, reason unknown`. The reason **is** known, though. The real fix is a facts join:
   - `pane_verdict_text` / `classify_death` must read the lr lock, the bundle `events.jsonl` and
     `faults/<sid>.json` for the sid;
   - on a STRANDED or claimed-not-live state it must paint
     `✗ e52f1f63 moved next4→next2, relaunch failed · ▶ <recover cmd>`, never RECYCLE/clean-exit.
   - Test: add a `lead-crash-pane-verdict.bats` case that seeds a bundle whose last event is
     STRANDED, then asserts that neither `CLOSED CLEANLY` nor `safe to close` is painted.

   This is also the user's item (a), "failed self-recycle", in pane 1.

2. **"Next evaluation ADMITS" is not false. It is true, and an agent acted on it.** The
   budget-release logic (`capacity-admit.sh:1626-1631`, rc 10) does admit the 4th evaluation.
   `~/.claude/logs/handoffs.jsonl` holds **10** `rescue relaunch` fires, all with
   `firing_sid:"344"` and `surface:"bg-tab"`, into panes 376, 377, 409, 410, 412, 413, 414, 425,
   426 and 435:
   - 8 of them have `engaged:"0"`;
   - 3 are labelled "retry after capacity refusal" or "capacity-refusal retry";
   - the driver is `/tmp/lr-rescue/fire-round.sh`, which runs `handoff-fire.sh … --tab` in
     parallel.

   So the refusal text worked as a retry instruction for an agent. Each retry opened a new tab and
   left one more husk. This feeds the user's items (b) tabs and (c) husks. The message fix must:
   - drop retry-inviting budget arithmetic from text an agent can read;
   - and the lifecycle fix matters more: a pane that was created only to run a launch that then
     exits rc 9 holds nothing and should close, not keep a shell (`cc-pane-runner:179-181`);
   - and handoff-fire should refuse `--tab` rescue loops that repeat a gate refusal (it already
     reasons this way at `handoff-fire.sh:12141`: "a second identical command cannot clear a real
     refusal").

   Missing test: replay pane-344's loop and assert that the second refused fire for the same sid
   does not open a new pane.

3. **Class-B past deadline: the defect is real, but the measurement is wrong.** The three items
   (`46676a666732`, `716598eca43f`, `de3b237d964e`, `veto_deadline 2026-10-18T05:00:00Z`) are now
   `status:"expired-actioned"`, `resolved:"2026-10-18T17:13:00Z"` (file mtime 12:13 CDT). At the
   18:17Z capture they were no longer open. The rows on screen were scrollback painted earlier, so
   comparing them with the capture time proves nothing.

   The defect window is 05:00Z-17:13Z: about 12 h in which the readout showed an overdue item as
   "auto-fire ≤24h" while **nothing auto-fired**. Q2 must therefore render
   `overdue · nothing fired`, not "fired", and not drop the row. A separate question for another
   slot: why the class-B actuator did not act at the deadline.

4. **Q1 knob mapping is incomplete. The defect is stronger than stated.**
   - On the lr path the load term is off by default: `lr-fire-resume.sh` passes
     `CC_ADMIT_LOAD_TERM="${LR_LOAD_TERM:-off}"`, and `lr-handoff.sh:1765` exports it as `off`. The
     `CC_ADMIT_MAX_LOAD_PER_CORE` hint can therefore never name the refusing knob there.
   - The active term's knob is `CC_ADMIT_RESTORE_R` when it is set (`capacity-admit.sh:1451-1453`,
     label `restore budget R=`). The reserve terms (`reserve-headroom`, `reserve-slots`) and the
     segment term need entries too.
   - `handoff-fire.sh:10317` is **not** the same bug. It is a load gate, and its knob
     `CC_FIRE_MAX_LOAD_PER_CORE` is correct. Leave it out of Q1.

5. **Pane attribution.** `handoffs.jsonl` says pane 425 was fired with `prompt-22a76c8a.txt` (and
   pane 414 too). §2.2 says 2e9ed9f2 appears in 425, 426 and 435. Per the fire log, 2e9ed9f2 is
   426 and 435. I could not re-check the screen (see 7).

6. **The proposed `▶ cc-lr recover <sid8>` needs proof first.** `cmd_recover` refuses a
   non-LIMITED sid unless `cl_husk_pane` matches (`bin/cc-lr` around :639-641). These sids are
   transplanted (STRANDED), not limit-blocked. If recover refuses them, the new one-line banner is
   the same false promise in fewer characters.
   - Add a test: for each refusal class, the printed `▶` command, run with `--dry-run`, must not
     refuse.
   - The readout already uses `cc-do <id>` for stranded sessions, so use one vocabulary.

7. **§4 remediation is stale.** `kitten @ ls` at about 13:27 CDT shows 10 OS windows with 1 tab
   each, and OS window 18 now holds only windows 433 and 434 (both running claude). Panes 409-435
   no longer exist. Someone else has already closed the refusal husks. Re-read `kitten @ ls` before
   acting on §4.

   Closing any husk is safe for data: every transplanted transcript lives under the target config
   dir (for example `transplant.json` `target_transcript` under `.claude-secondary`). No pane holds
   the only copy of a session.

### V3. What the fix gets right and what it would not have prevented

- **Right:** R1, one event one line; R5, detail to a log; R6, truthful tense; the width budget;
  the palette.
- **Not prevented by cc-say alone:**
  - (a) the watchdog's wrong class, which needs the lr-state join (V2.1);
  - (b) the agent retry loop and the tab sprawl, which need a lifecycle and fire-policy change
    (V2.2);
  - (c) class-B never firing (V2.3).

Treat M5 and Q3 as dependent on V2.1, and Q1 as dependent on V2.4.

**Confidence after verification: 65%** (down from 80%) that "no shared renderer" is *the* root
cause of the visible message problems. It remains the right cause for the volume and readability
of the walls of text. It is not the cause of the two most consequential false banners.
