# O2 — What does the operator ACTUALLY oversee today?

Measured 2026-08-19 06:19–06:45 local, on MacBookPro18,2 (M1 Max, 10 cores, 64 GiB), Claude Code
2.1.220, kitty 587 + iTerm2 3.6.11 + a detached tmux server. All reads were read-only: no pane was
closed, no process signalled, no config edited.

---

## 1. Verdict

**No — the operator does not oversee 15 sessions. He oversees 3.75 at a time, and "15" is not a
machine limit, it is his own touch rate times his own staleness tolerance: 3.75 sessions/active hour
× 4 hours ≈ 15.** At this instant 18 Claude Code processes are alive; 12 have a pane painted on a
display, 3 sit in a HIDDEN iTerm2 and 3 in a DETACHED tmux server with no window anywhere. 11 of the
14 live sessions I can read (79%) have had no human input for over four hours; four have never had
any. The three screens are already 99.3% covered in kitty, so SEE cannot be bought with more glass.
And the one channel that could replace looking — an interrupt — is off: kitty's `needs_attention`
reads False on 12/12 panes and `preferredNotifChannel` is unset in every settings file, so oversight
today is 100% poll-driven. **Sessions past ~15 do not fail; they age out of the operator's revisit
interval and nothing says so.**

---

## 2. The numbers, with the command behind each cell

### 2.1 VISIBILITY — panes that exist vs. panes a human can see

| Quantity | Value | How measured |
|---|---|---|
| Live Claude Code processes | **18** | `COLUMNS=100000 ps -axww -o pid,ppid,etime,rss,command \| grep -E 'node_modules/(\.bin/claude\|@anthropic-ai/claude-code/bin/claude\.exe)' \| grep -v cc-close-attrib` — MEASURED |
| …of which in a **kitty pane** | **12 (67%)** | `kitten @ --to unix:/tmp/kitty-587 ls`, then ancestor-match each CC pid against every pane's `foreground_processes[].pid` — MEASURED |
| …in **hidden iTerm2** | **3 (17%)** | ancestor walk → `iTermServer-3.6.11` → `iTerm.app`; ttys007/026/034 — MEASURED |
| …in **detached tmux** | **3 (17%)** | ancestor walk → `tmux` pid 24649; `tmux list-sessions` shows `lr-resume-855b332e`, `lr-resume-8843d236`, `lr-resume-8ad3a9d2`, none `(attached)`; `tmux list-clients` returns exactly one client, on the unrelated `dev` session — MEASURED |
| kitty OS windows / tabs / panes | **3 / 3 / 12** | `kitten @ ls` — each window has exactly one tab; every pane is in an active tab — MEASURED |
| kitty windows **on screen, un-occluded** | **3 of 3** | `CGWindowListCopyWindowInfo(.optionOnScreenOnly)` via a 12-line Swift probe: kitty windows at (2203,−1440,2560×1440), (−357,−1440,2560×1440), (0,37,1728×1080) — three displays, zero overlap — MEASURED |
| iTerm2 windows **on screen** | **0 of 13** | same probe: `.optionOnScreenOnly` lists 4 kitty windows and **no** iTerm2 window; `.optionAll` lists 13 iTerm2 windows. Positive control: kitty appears in both lists. `osascript -e 'tell application "System Events" to tell process "iTerm2" to return {visible, frontmost}'` → **`false, false`** — the app is hidden — MEASURED |
| Displays | 3 — built-in Liquid Retina XDR 3456×2234 (logical 1728×1117) + 2× DELL S2725QC 5120×2880 (logical 2560×1440) | `system_profiler SPDisplaysDataType` — MEASURED |
| Desktop area already spent on kitty | **99.3%** (9,239,040 of 9,302,976 logical pt²) | window rects above ÷ display rects above — MEASURED |
| Total visible terminal **rows** across all 12 panes | **635** | sum of `lines` from `kitten @ ls`: win1 = 77 + 4×19; win2 = 4×77; win4 = 3×58 — MEASURED |
| Smallest live pane | **19 rows × 95 cols** (4 of the 12) | same — MEASURED |

**The headline is not occlusion — it is substrate.** Every kitty pane really is painted: three
windows, three displays, no overlap, one tab each. The invisible third of the fleet is invisible for
a *structural* reason: it is not in kitty at all. A detached tmux session has no window by
construction, and iTerm2 has been ⌘H-hidden with three live sessions inside it. `tmux
list-sessions` shows `lr-resume-8ad3a9d2` created Mon 17 Aug 22:35 — **37 hours old, last transcript
write 31.9 hours ago** (`stat -f %m` on its `.jsonl`), a process alive and producing nothing, seen by
no one.

**Legibility at the small end.** `kitten @ get-text --match id:2 --extent screen` on a 19-row pane
returned 18 non-blank rows containing a static recap block and exactly **one** line of live state
(`✻ Crunched for 27s · 1 shell still running`) — no input box, no status line, no context %. The
other three 19-row panes did render the 2-row status line, leaving ≤13 rows of transcript. So at 19
rows the Claude Code TUI is at the edge of showing its own state at all.

### 2.2 LATENCY OF NOTICE — how long a blocked session waits for the human

Instrument: `~/.claude/autonomy/permission-archive/*.jsonl`, written by
`hooks/cc-permission-beacon.sh`. The harness (not a worker) records `ts` when a permission prompt
appears and `resolved_ts` when it clears, so `waited_s` is the wall time a session sat frozen.

```
cd ~/.claude/autonomy/permission-archive && python3 -c "...glob('*.jsonl'), json.loads per line..."
```

| | n | p50 | p75 | p90 | p95 | p99 | max |
|---|---|---|---|---|---|---|---|
| **Permission block → resolved** | 1543 events / 440 sessions / 2026-07-31→2026-08-19 | **37 s** | 4.3 m | **28.3 m** | **2.55 h** | 9.57 h | **22.6 h** |

Bucketed: `<10 s` 33.4% · `10–60 s` 23.1% · `1–5 m` 20.2% · `5–30 m` 13.4% · `30–60 m` 2.0% ·
`1–4 h` 3.5% · `>4 h` 4.3%. **7.8% of every permission block this fleet has ever raised waited more
than an hour.** `resolved_by` = PostToolUse 1524 / SessionEnd 14 / Stop 5.

**Positive control that the tail is the human and not a machine timeout** — median and p90 wait by
hour-of-day the block *started*:

| hour | 03 | 04 | 05 | 06 | 08 | 14 | 15 |
|---|---|---|---|---|---|---|---|
| median wait | 16 s | 72 s | 20 s | 19 s | **6122 s** | 11 s | 11 s |
| p90 wait | 13993 s | **33909 s** | 6978 s | 5308 s | 12463 s | 763 s | 294 s |

A block raised at 04:00 waits 9.4 h at p90; one raised at 14:00 waits 763 s. That is a sleeping
human, which is what makes this a measurement of *notice* rather than of the harness.

Second, independent instrument — **idle → next human word**, from the transcripts: for every
human-typed prompt, the gap since the preceding `assistant` record in that session.

| | n | p25 | p50 | p75 | p90 | p95 | max |
|---|---|---|---|---|---|---|---|
| **Session finished a turn → human spoke** | 1220 | 72 s | **274 s (4.6 m)** | 24 m | **1.72 h** | 3.87 h | 25.3 h |

Distribution: `<30 s` 10.6% · `30 s–2 m` 23.5% · `2–10 m` 28.7% · `10–60 m` 24.1% · `1–4 h` 8.3% ·
`4–12 h` 4.1% · `>12 h` 0.7%.

### 2.3 ATTENTION SWITCHING — how often the operator moves between sessions

Discriminator, read out of the transcript format itself: a record with `type:"user"`,
`promptSource:"typed"` **and** `origin:{"kind":"human"}` is the harness's own label for a message the
human typed. Verified against this session's own transcript (`grep -o '"origin":{[^}]*}'` →
`{"kind":"human"}` 6, `{"kind":"task-notification"}` 3).

🚨 **Our own fire machinery types into panes, so `typed` over-counts the human.** `handoff-fire.sh`
delivers briefs by keystroke, and those arrive as `typed`/`human`. Length separates them cleanly:
the >1500-char band is 100% machine ("`TASK — …`", "`[locate] You are THE LOCAL DRAIN — recycle #43…`"
at 57,751 chars), the ≤400-char band is conversational human ("`do it`", "`(Checking in)`",
"`Go for all of it as you recommend.`"). Classifier: MACHINE if `len>1500` or head starts with
`TASK —` / `[locate]` / `You are THE`.

> **2165 typed prompts in the 14-day window → 1343 HUMAN (62.0%) · 822 MACHINE-fired (38.0%).**

Human-only, over 331 clock hours (2026-08-05 → 2026-08-19), 173 of them (52%) containing at least
one human prompt:

| | median | p75 | p90 | p99 | max | mean |
|---|---|---|---|---|---|---|
| **Distinct sessions touched per ACTIVE hour** | **3** | 5 | 7 | 10 | 17 | **3.75** |
| Human prompts per ACTIVE hour | 7 | 10 | 16 | 24 | 27 | 7.76 |
| Distinct sessions per hour, **all** clock hours | — | — | — | — | — | **1.96** |
| Human prompts per hour, **all** clock hours | — | — | — | — | — | 4.06 |

Histogram of distinct-sessions-touched-per-active-hour: 1→31 h, 2→36, 3→25, 4→30, 5→15, 6→14, 7→7,
8→7, 9→3, 10→3, 12→1, **17→1**. The operator has touched more than 10 distinct sessions in an hour
**twice in 173 active hours**.

Distinct sessions touched per calendar day: 11, 16, 37, 29, 24, 28, 21, 28, 12, 18, 14, 29, 27, 9, 9
— **median 21/day**.

### 2.4 THE UNATTENDED FRACTION — the live fleet, right now

Per live session: last human-typed (machine-fired excluded) prompt, from its own transcript.

| session | where | age | last activity | **last HUMAN input** |
|---|---|---|---|---|
| 17d66411 | kitty w4/p131 drain recycle-11 | 19 m | 0 m | **NEVER** |
| f6653073 | kitty w4/p396 teammate `effort-survey` | 17 m | 13 m | **NEVER** |
| ee2b25fc | kitty w2/p392 teammate `A10-hostile-reviewer` | 2.0 h | 2.0 h | **NEVER** |
| 161874bb | kitty w2/p394 handoff-capture | 2.0 h | 0 m | **NEVER** |
| f285654f | kitty w1/p388 (this wave's lead) | 2.1 h | 3 m | 8 m |
| 84bde2e9 | kitty w2/p108 wt-pool-8 | 2.2 h | 27 m | 32 m |
| 020aafc9 | kitty w2/p88 wt-pool-2 | 2.0 h | 32 m | 37 m |
| 6b720014 | kitty w4/p102 claude-infrastructure | 15.0 h | 16 m | **13.4 h** |
| 855b332e | **detached tmux** lr-resume-855b332e | 30.3 h | 14.1 h | **14.3 h** |
| c5763bd4 | kitty w1/p82 lakehouse-lecture | 22.5 h | 3 m | **18.3 h** |
| 8ad3a9d2 | **detached tmux** lr-resume-8ad3a9d2 | 37.0 h | **32.8 h** | **34.9 h** |
| 34cebf8a | kitty w1/p2 claude-infrastructure | 127.7 h | 1.4 h | **35.0 h** |
| 8843d236 | kitty w1/p257 personal *(+ a DUPLICATE process on the same conversation in detached tmux)* | 45.7 h | 1.4 h | **37.0 h** |
| 9d874911 | kitty w1/p148 chris-resume | 51.1 h | 1.4 h | **45.8 h** |
| 450c1586 / 7aa069e9 / e0ebc3bb | **hidden iTerm2**, launched 04:37–04:38 (~1 h 45 m ago) | — | — | **no transcript exists anywhere** |

- **11 of 14 readable live sessions (79%) have had no human input in the last hour — and the same 11 in the last four hours.** There is no middle band: a session is either in the current conversation or it is a day old.
- **4 of 14 (29%) have never received a single human word.** Three are agent-spawned (teammates / drain recycle); one is a fired peer.
- Counting the three iTerm2 sessions (no transcript ⇒ certainly no human turn): **14 of 17 = 82%**.
- `8843d236` has **two live processes on one conversation** — pane 257 (pid 53709) and detached tmux `lr-resume-8843d236` (pid 21952, `--resume 8843d236`). A limit-recover transplant resumed a session that was still running. Nothing surfaced the duplicate.

### 2.5 FLEET SIZE OVER TIME — is "15" even the number?

`~/.claude/logs/capacity-alarm.jsonl`, field `sessions` (= `sessions_binclaude` + `sessions_exe`),
17,127 samples over 14 days:

| min | p25 | p50 | p75 | p90 | p95 | p99 | max | mean |
|---|---|---|---|---|---|---|---|---|
| 1 | 8 | **13** | 18 | 25 | 37 | 53 | **54** | 14.6 |

**The fleet is already above 15 for 35.2% of samples, above 20 for 22.7%, above 25 for 10.6%.**
Per-day medians range 3 → 34; 2026-08-10 sat at a median of 34 with a max of 54. The operator's felt
"~15" is close to the *median*, and the fleet has been double it for whole days without that being
a felt event — which is itself this axis's finding.

### 2.6 WHAT THE EXISTING REGISTRIES CAN SEE (coverage of the 18)

| Instrument | Sees | Misses | Command |
|---|---|---|---|
| kitty topology | 12/18 (67%) | 3 iTerm2, 3 tmux | `kitten @ ls` |
| our `~/.claude/cc-registry/` | 15/18 (83%), **+2 dead rows** (panes 355, 359 — pids gone) | all 3 tmux | `for f in ~/.claude/cc-registry/*.json` + `kill -0` |
| CC's native `~/.claude*/sessions/<pid>.json` | **10/18 (56%)**, +1 **ghost** | both teammates, all 3 tmux, all 3 iTerm2 | `python3 -c "json.load(glob('~/.claude*/sessions/*.json'))"` |

Two defects in CC's own registry, both MEASURED and both load-bearing for any design that leans on it:

1. **It is not reliably self-GC'ing.** `~/.claude/sessions/1378.json` claims an interactive session
   `voiceink-6b`, `status:"idle"`, cwd `~/Development/voiceink`. `ps -p 1378` →
   **`postgres: walwriter`**. The pid was recycled; `updatedAt` is **5.4 days** stale; a naive
   `kill -0` liveness check certifies it alive.
2. **`status` goes stale on genuinely live sessions.** pid 43029 (chris-resume, real, transcript
   written 1.4 h ago) carries `status:"busy"` with `updatedAt` **2.13 days** old. Live values seen:
   `idle` / `busy` / `shell`.

### 2.7 THE INTERRUPT CHANNEL IS OFF (this is the binding one)

| Fact | Value | Command |
|---|---|---|
| kitty `needs_attention` | **False on 12/12 panes** | `kitten @ ls` → per-pane field |
| kitty `has_activity_since_last_focus` | **False on 12/12 panes** | same |
| kitty is wired to *render* it | `tab_title_template "…{bell_symbol}{activity_symbol}…"` | `grep -n bell ~/.config/kitty/kitty.conf` → line 386 |
| CC 2.1.220 has a notification channel | `preferredNotifChannel` ×15, `terminal_bell` ×10, `notifyBell` ×9, `inputNeededNotifEnabled`, and the enum neighbours `ghostty` / `iterm2` / `disabled` | `LC_ALL=C strings -a -n 6 ~/.claude-220/…/claude.exe \| grep -c …` — positive control `promptSource` ×9 in the same dump |
| It is configured | **nowhere** | `grep -o '"preferredNotifChannel"[^,}]*' ~/.claude*/settings*.json ~/.claude.json` → empty |
| Our own hooks/bin ever emit BEL | **none** | `grep -rlE '\\a|\\007|\\x07' hooks/ bin/` → empty |

The renderer is wired, the harness has the emitter, and nothing rings it. **Oversight on this box is
100% pull: the human must go and look.** That is why the attention rate in §2.3 *is* the capacity.

---

## 3. What I could NOT measure, and why

- **Whether the operator's eyes were on a painted pane.** Geometry proves the pixels exist; it cannot
  prove foveation. Three displays spanning x = −357 → 4763 logical points cannot be read at once by
  one person, so 12 painted panes is an upper bound on SEE, never the realised value.
- **Per-pane focus *history*.** kitty exposes only `last_focused_at` (a single scalar, and it is set
  by *automatic* focus-on-split too, not just by the operator) plus an ordered
  `active_group_history` with no timestamps. There is no per-pane focus-event log on disk, so
  §2.3 is derived from *typing*, not from *looking* — it therefore **undercounts** attention spent
  reading a pane without typing into it. Task #144 established DECSET-1004 per-pane focus events are
  received; nothing persists them.
- **Why the three iTerm2 sessions have no transcript.** Their session ids appear in
  `~/.claude-secondary/session-env/`, `~/.claude/mailbox/`, `~/.claude/watchdog/`, but a
  `find ~/.claude*/projects -name '<id>-*.jsonl'` across all four account roots returns nothing. They
  are ~1 h 45 m old. Blocked at a first prompt is the obvious hypothesis; I did not read their ttys,
  because that is not read-only.
- **The default value of `preferredNotifChannel` when unset.** Establishing it would mean writing a
  config variant and restarting a session. The *observable* consequence is measured instead:
  `needs_attention` False on 12/12, including panes unfocused for 1.7 h.
- **Whether `<10 s` permission resolutions (33.4%) are human or auto-approval.** `waited_s` has 1 s
  resolution and `resolved_by` is `PostToolUse` for both. This only affects the left tail; the p90/p95
  and the diurnal control are unaffected.
- **Coverage caveat on §2.3/§2.4.** The typed-prompt marker exists on 1235 of 3130 transcripts
  modified in the last 14 days (39%). It is **not** version-gated — 2.1.220 appears on both sides of
  the split (1235 with, 1806 without; only 10 files at 2.1.114 and 79 with no version, so instrument
  coverage is 97.2%). The 1806 without are subagents, teammates and fired sessions that genuinely
  never received a typed prompt. Fleet-wide the marker exists on 2125 of 6939 transcripts (30.6%);
  everything in §2.3/§2.4 is scoped to the 14-day window and should not be extrapolated past
  2026-08-03, when the first `origin:{"kind":"human"}` record appears in this corpus.

---

## 4. The design constraint this axis imposes

**The operator's attention budget is 3.75 distinct sessions per active hour (median 3, p90 7,
observed ceiling 17 once in 173 hours), across a 52% duty cycle of active hours. That is the number
any design must beat, and it is a rate, not a count.**

Three constraints follow, in the order they bind:

**C1 — Capacity is a rate × a tolerance, and "15" is that product.**
`units_overseeable = touch_rate × staleness_tolerance` = 3.75 /h × 4 h ≈ **15**. The operator's felt
ceiling is not memory, CPU or quota — it is arithmetic on his own behaviour. A design reaches 30
units only by changing one of the two terms: raising the touch rate (cheaper per-unit interaction) or
raising the tolerance (making a 8-hour-stale unit *safe*, which means STOP and AUDIT must hold
without SEE). **Adding units without moving either term does not add oversight; it lengthens the
revisit interval, which is exactly what 79%-unattended already looks like.**

**C2 — SEE cannot be bought with more screen; it must be bought with aggregation.**
99.3% of a three-display, 9.3 Mpt² desktop is already kitty, showing 635 terminal rows across 12
panes. Each CC pane spends ~6 rows on irreducible chrome (separator + input box + 2-row status), and
the 19-row panes are already at the point where one of them rendered *no* status line at all. At 30
units the same glass gives 21 rows each — every pane becomes the pane that could not show its own
state. **Therefore any design past ~15 must derive per-unit state from a store, not from a rendered
TUI**, and must reserve the glass for the units that are *asking for something*.

**C3 — The pull-only interface is the defect, and it is one setting plus one convention away from
being fixed.** Oversight today has zero push: `needs_attention` False on 12/12 while kitty already
renders `{bell_symbol}` in the tab title, `preferredNotifChannel` unset while the 2.1.220 binary
carries `terminal_bell` / `notifyBell` / `inputNeededNotifEnabled`, and not one script in
`hooks/` or `bin/` emits a BEL. The consequence is measured: a permission block waits 28 minutes at
p90 and 2.55 hours at p95, and 7.8% of all blocks wait over an hour — a session frozen mid-turn,
with the operator two feet away, because nothing told him. **INTERRUPT is the cheapest term in C1:
it converts the 3.75/h *scan* budget into a 3.75/h *response* budget, which is worth far more per
unit.**

**C4 — Any unit census must be substrate-agnostic, and no existing one is.** Of 18 live units, kitty
sees 12, our pane-keyed `cc-registry` sees 15 (plus 2 dead rows), and CC's own `sessions/<pid>.json`
sees 10 plus one ghost row pointing at `postgres: walwriter`. Nothing sees all 18, nothing noticed
that two processes are driving one conversation (`8843d236`), and nothing noticed a session alive for
37 hours that has written nothing for 32. A design that adds units on a *new* substrate — in-process
agents, `--bg` daemons, Workflow agents, cloud — inherits this blindness by default. **A unit that a
census cannot enumerate cannot be seen, stopped, or audited, whatever its cost.**
