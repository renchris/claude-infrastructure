# U03 — lr-fire-resume.sh capacity gate + expect layer

Files read in full: `/Users/chrisren/Development/claude-infrastructure/scripts/limit-recover/lr-fire-resume.sh` (606 L),
`.../lr-preseed-env.sh` (143 L), `scripts/lib/capacity-admit.sh` (~960 L, targeted),
`scripts/handoff-fire.sh` (recycle watcher 6780–6881, `resume_engaged` 3680–3715),
`scripts/limit-recover/lr-handoff.sh` (launcher build 540–600).
Binary under test: `2.1.260` (`bin/cc-claude-bin => /Users/chrisren/.claude-260/node_modules/.bin/claude`; `claude --version => 2.1.260 (Claude Code)`).

---

## HEADLINE — measured, not inferred

**The ingest prompt was delivered by the expect layer in 0 of 5 of today's recoveries, including the
one reported RECOVERED.** And the 4 PARTIALs have a fully deterministic cause that is arithmetic,
not luck: **handoff-fire's relaunch watcher makes exactly 2 attempts; `CC_ADMIT_BUDGET` requires 3
consecutive refusals before it releases. 2 < 3, so a load-refused in-place recycle can never
self-release.** Pane 112 succeeded only because the refusal counter already stood at 2 *from two days
earlier*.

| pane | sid | resume marker in target xcript | ingest `<command-args>ingest …` record | delivered by |
|---|---|---|---|---|
| 112 | d02d8feb | 17:20:49.422Z | **0 — never, to this minute** | — (declared "ENGAGEMENT CONFIRMED") |
| 111 | 09e64dcb | 17:26:26.009Z | 17:43:23.755Z (**+16m58s**) | operator, by hand |
| 121 | e442434c | 17:47:15.825Z | **0 — never** | — |
| 114 | 28f07827 | 17:51:44.609Z | 17:58:24.891Z (**+6m40s**) | operator, by hand |
| 117 | cb227486 | 17:55:02.266Z | 17:57:29.547Z (**+2m27s**) | operator, by hand |

Method: for each sid, the last `type:"user", isMeta:true, "Continue from where you left off."` record
after 17:00Z (that is what `--resume` writes at boot — it lands 1–2 s after the capacity ADMIT in the
IDL, in all five), then a scan for `<command-args>ingest `.
`python3` over `~/.claude-secondary|.claude-tertiary/projects/*/<sid>.jsonl`.

Pane 112 is the important row: `lr-handoff` printed *"engagement verified by a new assistant turn"*
(`~/.reso/limit-recover/fleet/one-20260919T171910Z/d02d8feb….stderr`), and the assistant turn that
satisfied it (17:21:54.358Z) was triggered by a **queued `<task-notification>` at 17:20:57.680Z**, not
by the ingest. `resume_engaged` (handoff-fire.sh:3680) asks only for *a content-bearing non-error
assistant turn newer than t0* — it cannot tell "ingested the bundle" from "answered a stale
notification". That is a false-positive of the only engagement oracle on this path.

---

## (1) The capacity gate at lr-fire-resume.sh:301–333

### Shape
`exit 9` on refusal. **There is no retry, no wait, no sleep, and no backoff anywhere in
lr-fire-resume.sh** (`grep -n sleep lr-fire-resume.sh` => only lines 474/522/532/545/552/554/556, all
inside the expect program, none on the gate path). The gate is one call:

```
324:  if ! cc_capacity_admit lr-fire-resume "resume $SID on $ACCT"; then
325:    echo "✗ $(cc_capacity_admit_reason)" >&2
326:    echo "  Shed load first (close finished panes / let the wave drain), then re-run this exact command." >&2
327:    echo "  Override for one resume: CC_ADMIT_GATE=off ; raise the bar: CC_ADMIT_MAX_LOAD_PER_CORE=<n>" >&2
329:    exit 9
```

Placement is correct and deliberate (lines 301–314: after account/binary/tombstone validation,
immediately before `exec expect`), and an absent library is loud-not-fatal (`332`: `!! …
capacity-admit: ABSENT … spawning UNGATED`).

### Env vars honoured
The gate is `cc_capacity_admit` from `scripts/lib/capacity-admit.sh`; lr-fire-resume adds none of its
own. Full set (capacity-admit.sh:92–98):

`CC_ADMIT_GATE`(on) · `CC_ADMIT_MAX_LOAD_PER_CORE`(2.0) · `CC_ADMIT_MIN_HEADROOM_GB`(4) ·
`CC_ADMIT_MAX_SEGMENT_PCT`(50) · `CC_ADMIT_ACTIVE_CEILING`(8) · `CC_ADMIT_ACTIVE_RESERVE`(1) ·
`CC_ADMIT_BUDGET`(3) · `CC_ADMIT_SYSCTL` · `CC_ADMIT_LOADAVG_OVERRIDE` · `CC_ADMIT_HEADROOM_OVERRIDE` ·
`CC_ADMIT_SEGMENT_OVERRIDE` · `CC_SP_ACTIVE_OVERRIDE` · `CC_ADMIT_STATE_DIR` · `CC_ADMIT_IDL` ·
`CC_ADMIT_NOTIFY_BIN` · per-term switches `CC_ADMIT_LOAD_TERM` / `_HEADROOM_TERM` / `_SEGMENT_TERM` /
`_ACTIVE_TERM` (all default `on`) · `CC_ADMIT_RESERVE_TERM` (capacity-admit.sh:489) ·
`CC_ADMIT_PRESENCE_LIB` · `_CC_ADMIT_PROBE`.

**The load term is ON for lr-fire-resume and OFF for the Agent tool** (capacity-admit.sh:83–90 names
`hooks/agent-teams-enforce.sh` as the caller that disables it). That asymmetry is the whole story of
today: the operator's `CC_ADMIT_LOAD_TERM=off` lived in the *lead's* shell and could not reach a
process the watcher typed into another pane's shell.

### The bound, and why it could not release — the 2-vs-3 arithmetic

`_cc_admit_spend` (capacity-admit.sh:921) charges `cc_hw_budget_charge` and returns 9 while budget
remains; on the (budget+1)-th consecutive refusal it returns 0 with `basis:"budget-expired"` and
pages. **The counter file is keyed on the CALLER ALONE** —
`_cc_admit_state_file` (509–514): `printf '%s/%s.refusals' "$dir" "$1"` ⇒
`~/.claude/autonomy/capacity-admit/lr-fire-resume.refusals`. Not per-session, not per-target. And
**every ADMIT resets it** (`_cc_admit_reset "$caller"` at the tail of `cc_capacity_admit`, and on
every fail-open branch).

The relaunch driver is handoff-fire.sh:6786–6881 and it makes **exactly two attempts**:

```
6789  sleep 2
6790  for _ in 1 2; do  it2_type_verified … "$(cat "$CMDFILE")"  … done      # first type
6811  for _ in $(seq 1 15); do sleep 3; if cc_alive; then up=1; break; fi; done   # 45 s
6812  if [ "$up" = 0 ] && at_shell; then  … it2_type_verified … (retype ONCE) …   # second type
6815    for _ in $(seq 1 15); do sleep 3; if cc_alive; then up=1; break; fi; done # 45 s
6879  echo "!! relaunch typed but no claude process appeared within 90s — fallback comment typed into pane" >&2
```

So the launcher runs **twice**, ~45–50 s apart, each run reaching `exit 9`. With the counter starting
at 0, the two runs produce "refusal 1 of 3" and "refusal 2 of 3" and the watcher gives up one refusal
short of release, **every time, by construction**.

`~/.claude/autonomy/idl.jsonl`, today, `caller:"lr-fire-resume"` — the arithmetic is visible verbatim:

```
17:19:59Z refuse  load 28.65/10 = 2.86/core  (refusal 3 of budget 3)   d02d8feb → next2
17:20:48Z ADMIT   basis:"budget-expired"  "load term over after 3 consecutive refusals — admitting and paging"
17:22:17Z refuse  2.57/core (refusal 1 of budget 3)   09e64dcb → next3
17:23:07Z refuse  2.54/core (refusal 2 of budget 3)   09e64dcb → next3      ← watcher exhausted here
17:26:24Z ADMIT   basis:"measured"  load 1.61/core                          ← operator, by hand
17:44:55Z refuse  2.42/core (refusal 1 of 3)   e442434c → next3
17:45:45Z refuse  2.51/core (refusal 2 of 3)   e442434c → next3             ← watcher exhausted
17:47:14Z ADMIT   basis:"headroom-only"  "load term off"                    ← operator, CC_ADMIT_LOAD_TERM=off
17:49:47Z refuse  2.05/core (refusal 1 of 3)   28f07827 → next2
17:50:37Z refuse  2.12/core (refusal 2 of 3)   28f07827 → next2             ← watcher exhausted
17:51:43Z ADMIT   "load term off"                                           ← operator
17:53:06Z refuse  4.15/core (refusal 1 of 3)   cb227486 → next2
17:53:55Z refuse  6.73/core (refusal 2 of 3)   cb227486 → next2             ← watcher exhausted
17:55:00Z ADMIT   "load term off"                                           ← operator
```

Gaps: 17:22:17→17:23:07 = **50 s**; 17:44:55→17:45:45 = **50 s**; 17:49:47→17:50:37 = **50 s**;
17:19:59→17:20:48 = **49 s**. That is the `sleep 2 + 15×3 s` retype cadence, confirming both refusals
per session are the watcher, not the operator.

**Why pane 112 alone survived:** the last lr-fire-resume record before today is
`2026-09-17T23:58:51Z … (refusal 2 of budget 3)` (`grep lr-fire-resume idl.jsonl | grep -v 2026-09-19 | tail`).
The counter had been sitting at 2 for ~17 hours. Today's first evaluation was therefore "refusal 3 of
3" and the watcher's retype got `budget-expired`. **One session's recovery depended on a stale,
cross-session, cross-day counter.** Every later session started from the reset and could not reach 3.

`~/.claude/autonomy/capacity-admit/lr-fire-resume.refusals` is currently 0 bytes (mtime 12:55), i.e.
reset by the last admit — the next recovery starts the 2-vs-3 trap over again.

Also note the load values themselves were bimodal within a single session's two attempts
(cb227486: 4.15 then 6.73/core), which is exactly the §8.5.7 instability the plan already records as
the reason the load term is a bad proxy.

---

## (2) The expect layer

### Spawn
`expect -c '…'` at :432, **not** `exec expect` — deliberate (:409–428), so the pane outlives the
session; `lr_rc=0 … || lr_rc=$?` at :428/585 is load-bearing under `set -euo pipefail`.
`match_max 200000` (:447) and `set timeout 300` (:433). Spawn line :463/:465:

```
spawn -noecho env -u CLAUDE_CODE_CHILD_SESSION DISABLE_AUTOUPDATER=1 CLAUDE_CONFIG_DIR=$cfg \
      [$wrap] $bin --permission-mode $perm --model $model --effort $effort --resume $sid
```
Two branches only for the `cc-close-attrib` wrapper (:461–466).

### The fullscreen upsell
Handled in-PTY at :544–548 via `answer_menu 1 $LR_RE_FS_RB $LR_RE_FS_RB "fullscreen upsell (Not now)"`
— one Down, then an ordinal-anchored read-back of `❯2. Not now` before the CR; an unconfirmed
selector sends **nothing** and parks (:501–503).

**Gap worth closing at the source.** `lr-preseed-env.sh:115–117` raises six `*SeenCount` gates and
`fullscreenUpsellSeenCount` is **not among them**, although the key is real —
`grep -ao '[Ff]ullscreen[A-Za-z]*' claude.exe` returns `fullscreenUpsellSeenCount` (7) and
`fullscreenDownsellSeenCount` (7) — and it currently sits at **3** in both accounts today's
recoveries targeted (`.claude-secondary`, `.claude-tertiary`; `.claude` and `.claude-quaternary` have
it unset). So the upsell can still render at resume and costs up to `sleep 1 + 1×Down + 10 s readback`
— or a park — on the one path where parking is most expensive. Adding those two keys to
`UPSELL_FLOOR` removes the question instead of answering it, which is the file's own stated doctrine
(:346–353).

### Terminal-query gibberish
Handled *before* expect, in bash, at :279:
`printf '\033[?1000l\033[?1002l\033[?1003l\033[?1006l\033[?1015l'` (disable mouse reporting modes).
There is no in-expect gibberish filter; the width-invariant regex builder `lr_wrap_re` (:94–145)
tolerates interleaved CSI sequences, whitespace and box rules between the characters of a phrase,
which is what makes the arms survive wrapping and Ink's mid-label SGR.

### Prompt auto-submit — where it is emitted and when it silently does nothing

```
549    -re $env(LR_RE_READY) {
550      if {$prompt ne "" && !$injected} {
551        set injected 1
552        sleep 2
553        send "\025"          ;# Ctrl-U clear composer
554        sleep 1
555        send -- $prompt
556        sleep 1
557        send "\r"
558      }
559    }
560    timeout {}
561    eof { exit }
562  }
563  if {$injected} {
571    set timeout 6
572    for {set i 0} {$i < 5 && !$submitted} {incr i} {
573      expect {
574        -re {esc to interrupt} { set submitted 1 }
575        timeout { send "\r" }
576        eof { exit }
578    }
579    if {!$submitted} {
580      send_user "\nlr-fire-resume: WARNING — prompt may not have submitted; press Enter in the pane.\n"
```

**Three independent defects, all live on 2.1.260.**

**(a) The silent-drop path — no warning exists for it.** The `LR_RE_READY` arm carries **no
`exp_continue`** and the sibling `timeout {}` arm at :560 is **empty**. If the ready signal is never
matched within `timeout 300`, expect falls straight out of the block with `injected == 0`, the entire
`if {$injected}` verification block at :563–583 is skipped, and control goes to `interact` (:584).
The session comes up perfectly, the composer is empty, **nothing is typed, and nothing is printed**.
That is exactly the state described for panes 111 / 114 / 121 / 112: alive, idle, no user record, no
warning. The WARNING at :580 is *unreachable* for this failure — it is guarded by the very flag the
failure prevents from being set.

`LR_RE_READY` (:384) is `'for shortcuts' | 'auto mode on' | 'shift+tab to cycle'`.
Measured against 2.1.260: `for shortcuts` 5 hits, `auto mode on` 3 hits, **`shift+tab to cycle` 0
hits** (`LC_ALL=C grep -ac` on `claude.exe`) — one of the three alternatives is already dead wording.
And a live read of a running pane
(`kitty @ --to unix:/tmp/kitty-73832 get-text --match id:110`) shows the footer today is
`⏵⏵ auto mode on · 1 shell · ⌥⏎ for agents` — i.e. in auto mode `? for shortcuts` does **not** render
and the whole gate rests on the single surviving alternative `auto mode on`. In the bundle that string
sits inside ternaries (`…children:"? for shortcuts"` chosen against a chord-rendered alternative), so
it is state-dependent by construction. *Attribution honesty:* I can prove the OUTCOME (0/5 ingests
delivered) and I can prove (b) for pane 117 (it printed the WARNING ⇒ `injected==1`). For 111/114/121
I cannot separate "READY never matched" (a) from "READY matched during hydration and the keystrokes
were dropped" (b) — the pre-TUI scrollback is gone (`kitty @ get-text --extent all` on panes
111/112/114/117/121 returns only the alternate screen, no `lr-fire-resume:` lines). Both are real
bugs in the same arm and both are fixed by the same change (4).

**(b) The submit oracle is STALE on 2.1.260 — and it is the one pattern in the file that is not
width-invariant.** Line 574 is a bare literal `-re {esc to interrupt}`; every other pattern in this
file goes through `lr_wrap_re`, whose 70-line header (:75–93) exists precisely because *"the phrase a
human reads is almost never contiguous in the byte stream"*. Worse, the phrase is now wrong:
`LC_ALL=C grep -aoc 'esc to interrupt' claude.exe => 2`, and **both occurrences are the API-retry
line**, not the running-turn hint:
`` `\xB7 next try in ${Ue} \xB7 attempt ${ut.attempt} \xB7 esc to interrupt` `` inside a
`state=="low_priority_waiting"` branch, plus its sibling entry in the bundled string table
(`retry in … check your network … next try in … attempt … esc to interrupt … Retrying in`).
The ordinary running-turn hint is **assembled, not literal** —
`e(D,{chord:H,action:"interrupt",format:{keyCase:"lower"}})` inside `e(n,{dimColor:!0,…})`, i.e. an
Ink component pair with an SGR boundary. `grep -ao 'esc to [a-z ]*'` ranks `esc to cancel` 13,
`esc to interrupt` 2. **Consequence: on 2.1.260 the verify loop essentially always times out** —
5 × 6 s = **30 s added to every injected resume**, 5 spurious CRs sent, and the WARNING printed
*whether or not the prompt actually submitted*. Pane 117's WARNING is therefore not evidence the
submit failed; it is evidence the oracle is dead. (117's ingest did in fact arrive only at 17:57:29,
2m27s later, typed by the operator — so in that instance it had also genuinely failed.)

**(c) The 5 retry CRs are sent BLIND, contradicting the file's own rule.** `answer_menu` refuses to
send a CR it cannot confirm (*"Refusing to guess: the next option down is destructive"*, :502), yet
:575 sends up to five unconditional CRs into a pane whose state is unknown. A CR onto an open
permission dialog **accepts its default**. Today's resumes ran `--permission-mode auto` so the
exposure was low, but `PERM_MODE` accepts `default` (:388) and the launcher carries the source
session's mode verbatim (lr-handoff.sh:581 `[[ -n "$SRC_PERM" ]] && FIRE_ARGV+=(--permission-mode "$SRC_PERM")`).

### Is "verified submit" implemented on the kitty path?
**It is implemented, and it is not kitty-specific — but it is inert.** The loop at :563–583 is the
only verification, it screen-scrapes an anchor that 2.1.260 no longer renders for a normal turn, and
it has **zero test coverage**: `grep -n 'LR_RE_READY\|esc to interrupt\|submitted\|injected' tests/*.bats`
returns no hit in any of the 17 `tests/lr-*.bats` files. The file's own header (:356–360) boasts that
the *resume-menu* fallback "is exercised by its own test with the suppression FORCED OFF … a fallback
with no test is a fallback we would discover is broken during the next recovery." The submit path is
exactly that untested fallback, and it was discovered broken during this recovery.

---

## (3) kitty vs iTerm2 inside these two scripts

**`lr-fire-resume.sh` has no terminal-specific code at all.** `grep -n -iE 'it2|kitty|osascript|iterm'`
returns three hits, all comments: :282 (iTerm2 modal, delegated to preseed), :412–413 (a comment
explaining that *kitty* closes a window whose only child exited — the reason the script falls through
to `exec zsh -l -i` at :606 instead of `exec expect`), :603 (`ITERM_SESSION_ID` is synthesized from
`KITTY_WINDOW_ID` by `~/.zshrc`, which is why `-l -i` is load-bearing). It is terminal-agnostic by
construction: it inherits whatever pty it is started in.

**`lr-preseed-env.sh` is iTerm2-only, and on this machine that half is dead code.** Lines 56–65 write
`defaults write com.googlecode.iterm2 PreventEscapeSequenceFromClearingHistory -bool true`. The box
runs kitty (`/tmp/kitty-73832`); kitty has no CSI-3-J consent modal, so this branch neither helps nor
hurts — but the header (:9–20) still presents it as one of the two blockers, which mis-describes the
current fleet. Part 2 (trust pre-accept + `*SeenCount` floors in the target `.claude.json`) is
terminal-agnostic and is the half that matters — and it is where `fullscreenUpsellSeenCount` is
missing (see above).

All kitty/iTerm2 dispatch lives one level up: `lr-handoff.sh` has 72 `kitty` mentions
(`grep -ic kitty` => 72), four spawn sites (:61 *"kitty split / iTerm2 split / kitty os-window /
iTerm2 window"*), `lrh_kitty()` at :126, and `lrh_kitty_window_alive()` at :147 — whose header (:130–139)
already records this exact failure class from 2026-09-08: *"The killer was capacity-admit refusing the
resume with exit 9 — a loaded machine is exactly the state a limit recovery runs in, so this is the
common case, not the exotic one."* Today is that same finding, eleven days later, on the in-place path.

---

## (4) Minimal change: verify the submit from the TARGET TRANSCRIPT, not the screen

**The oracle already exists in the tree and needs no new mechanism.** `handoff-fire.sh:3680
resume_engaged()` polls `"$cfg"/projects/*/"$sid".jsonl` for a non-error, content-bearing *assistant*
turn newer than a baseline. The submit check wants the strictly cheaper, strictly earlier, strictly
more specific sibling: a **user** record newer than the baseline that contains the bundle path.

Verified the record shape exists and is unambiguous (pane 117's real one):

```
type=user  isMeta=None  ts=2026-09-19T17:57:29.547Z
<command-message>limit-recover</command-message>
<command-name>/limit-recover</command-name>
<command-args>ingest /Users/chrisren/.reso/limit-recover/cb227486-…/bundle-20260919T175254Z</command-args>
```

The **bundle path is present verbatim**, so one substring test covers both the slash-command form and
a plain-text prompt. It is written at submit time, before any assistant turn — so it separates
SUBMITTED from ENGAGED, which the current design conflates.

### The change, in five parts (~35 lines net)

1. **Capture a baseline in bash before `exec`/spawn**, and export it plus a unique token:
   `export LR_T0="$(date -u +%FT%TZ)"` and `export LR_SUBMIT_TOKEN="${PROMPT##* }"` (the bundle path),
   falling back to the whole prompt when it has no path. Also `export LR_CFG` (already exported, :391).

2. **Replace :563–583 entirely** with a Tcl poll that shells out — expect keeps the pty while `exec`
   runs a child:

```tcl
  if {$injected} {
    set submitted 0
    for {set i 0} {$i < 20 && !$submitted} {incr i} {          ;# 20 x 3s = 60s
      if {![catch {exec $env(LR_SUBMIT_PROBE) $env(LR_CFG) $sid $env(LR_T0) $env(LR_SUBMIT_TOKEN)}]} {
        set submitted 1
      } else { sleep 3 }
    }
    if {!$submitted} { send "\r" ; sleep 3                      ;# ONE re-CR, then re-poll once
      if {![catch {exec $env(LR_SUBMIT_PROBE) …}]} { set submitted 1 } }
    if {$submitted} {
      send_user "\nlr-fire-resume: prompt SUBMITTED — user record present in the target transcript.\n"
    } else {
      send_user "\nlr-fire-resume: ✗ SUBMIT FAILED — no user record for the prompt in $env(LR_CFG) after 63s.\n"
      send_user "  Type it by hand in this pane: $prompt\n"
    }
  }
```

3. **`lr-submit-probe.sh`** (new, ~20 lines) — a near-copy of `resume_engaged`'s python block with
   `type=="user"`, `timestamp > t0`, and `token in json.dumps(record)`; exit 0/1. Put it beside
   `lr-fire-resume.sh` so `$_LR_DIR` resolves it, and fall back to `$HOME/.claude/scripts/limit-recover/`
   (same three-way resolution the script already uses at :316–320). **Fail-LOUD, not open**: probe
   unresolvable ⇒ print that the submit is UNVERIFIED and name the prompt, never a silent pass.

4. **Close the silent-drop hole (a), which the transcript probe alone does not fix** — the probe only
   runs when `injected==1`. Make the ready gate fail loud and add a wording-independent fallback:
   replace `timeout {}` at :560 with a short-timeout settle loop — `set timeout 8; expect { -re $LR_RE_READY {…inject…} timeout { …the pty has been quiet 8 s: the TUI has settled, inject anyway… } }`
   — and on giving up entirely, `send_user` a loud `✗ READY NEVER SEEN — prompt NOT typed: <prompt>`.
   Quiet-pty is version-proof in a way a status-line phrase can never be. Also drop the dead
   `shift+tab to cycle` alternative (0 hits in 2.1.260) and re-derive the list from the binary on each
   CC bump.

5. **Report the verdict upward.** `lr-fire-resume` currently returns expect's rc, which is 0 whether
   or not the prompt landed. Exit non-zero (e.g. 12) on SUBMIT FAILED / READY NEVER SEEN so
   `lr-handoff`/`lr-fleet` can mark the run PARTIAL for the *right* reason instead of inheriting the
   watcher's process-liveness verdict. In parallel, change handoff-fire's recycle path to prefer the
   submit probe over `resume_engaged`, which today accepts an unrelated `<task-notification>` turn as
   proof (pane 112).

### Two adjacent one-line fixes that are strictly necessary for any of this to matter
- **Raise the relaunch attempts above the budget, or park instead of attempting.** Either
  `handoff-fire.sh:6811-6816` gains a third attempt (2 < `CC_ADMIT_BUDGET`=3 is the whole 4-of-5
  failure), or — better — the recycle path exports `CC_ADMIT_LOAD_TERM=off` into the typed command,
  which is what the Agent-tool path already does and what the plan's own §8.5.2/§12.2 retraction says
  the load proxy deserves. A limit recovery runs, by definition, on a box that is busy.
- **Make the pane's failure legible.** `handoff-fire.sh:6879` prints *"no claude process appeared
  within 90s"*, which names a symptom whose cause was already printed **into that same pane** by
  lr-fire-resume:325 (`✗ capacity-admit: REFUSING resume … (refusal 2 of budget 3)`). One
  `kitty @ get-text --match id:$RSID | tail -20 | grep -m1 '^✗'` in the failure branch turns an
  unattributable husk into a named cause.

### Cost of the change at run time
Removes the unconditional 30 s dead-oracle wait; the probe returns in <1 s on success (it is a
`python3` scan of one jsonl). Net: a successful resume gets **~30 s faster** and gains a true verdict;
a failed one is named within ~63 s instead of being silent forever.
