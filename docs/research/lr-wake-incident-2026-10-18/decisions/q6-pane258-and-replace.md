# Q6 (pane 258, 9f6593c5) and decision 56c6862291f2 (replace a launcher-rooted pane)

Read-only research, 2026-10-18 23:30–23:50 CDT (2026-10-19 04:30–04:50Z). Nothing was typed into any pane, and nothing was moved, closed or killed. The only write outside this file was one `git fetch -q origin main` in the session's worktree, which updated its remote-tracking ref. The brief named the session's own worktree check, so the fetch was in scope.

## Answer first

| # | Decision | Recommendation | Conviction |
|---|---|---|---|
| Q6 | 9f6593c5 (pane 258 before the reboot, **kitty window 19 now**) | **Close the session and keep its worktree.** It has been a pure waiter since 10-11 05:26Z. It is waiting for your ruling on the Church decks and section tints. That wait is already recorded in three places: backlog `0f487bba36d4`, decision `8e0ccb1f19ed` and the tracker on trunk. Nothing is unlanded: 0 commits ahead and a clean tree. To close it, type `/exit` in window 19. `reso-resume-one` then closes the pane itself. Do **not** start a replacement beside it, and do **not** remove `wt-cc-141442-81738`. | **80%** (report said 65%) |
| 56c6862291f2 | Should `cc-lr move` replace a launcher-rooted pane by default? | **Keep the hold. Do not flip to "replace by default."** Change two things instead. (a) After one `HELD:no-shell`, the hold becomes terminal for that pane: it is skipped in plan selection and gets one operator row, instead of being retried every hour. (b) Close the spawn-side gap that created the pane: `kitten @ launch … /tmp/<script>` is still allowed, because `73949af55` denies only `handoff-fire --launcher <tmp>`. | **75%** against replace by default. The filing was 80% for it. |

Why the answers moved:
- **The problem has already healed itself.** After today's 16:34 reboot, boot-resume brought 9f6593c5 back in a pane whose shell survives a recycle. The probe now reads `shell_root: yes`, so `HELD:no-shell` cannot recur for it.
- **Only one session was ever affected.** Across 14 days of limit-recover evidence, exactly one session hit `HELD:no-shell`: this one, 7 times, all on 10-18. That pane had been created by a hand-built `/tmp` rescue launcher.
- **Replace cannot keep the same pane.** A kitty window closes when its root process exits, so a replace always produces a new window id. The `lr-handoff` split arm also has no pane-count check.

## 1. What 9f6593c5 was doing

Transcript: `~/.claude-next/projects/-Users-chrisren-Development--worktrees-wt-cc-141442-81738/9f6593c5-fa6d-45eb-babd-5f3be41cd18f.jsonl`, 123 lines and 1.06 MB. A copy of the same size is under `~/.claude/projects/`.

```
jq -r '[.type,(.subtype//"")]…' | sort | uniq -c
  8 assistant · 5 user (1 prompt + 4 tool results) · 35 attachment · 1 turn_duration · 1 stop_hook_summary · ~70 bookkeeping (mode, bridge-session, cost-state, ai-title…)
```

- **There was one turn in total.** The only prompt arrived at 2026-10-11T05:25:26Z: *"Resume the Insomniac Denver floor-plan layer-by-layer sign-off. Read …church-layer-review-RESUME.md … The operator's next message will be his ruling on the Table areas (decks)…"*. The session itself is a successor of an earlier session. The resume note names `73e925ff` as the original owner of step `0f487bba36d4`.
- **The final assistant message was at 05:26:12Z**, verbatim in its first line: *"I'm caught up and waiting for your ruling on the Church main floor's Table areas (decks) and Section tints + names. Nothing is written yet."* It also said: *"Branch: rebased onto the current trunk (`dfd34bbdb`). It's clean and nothing on it is unlanded."*
- **There is no close verdict.** The session ended in a wait for the operator, not in a close. The programme it serves is still open. On trunk, `git show origin/main:docs/floor-plan/open.md` lines 132–140 show the Church main floor row as `decks ⏳ … awaiting his sign-off`. Every later layer, the Church balcony and all Club Vinyl rows are `—`. The tracker's last edit was `29182d869`, on 2026-09-30.
- **The pending ruling is stored durably, independent of the session:**
  - backlog `0f487bba36d4`: `block`, `needs-human`, conviction 85. Its `needs` field reads: "Church main floor, Table areas (decks) layer: sign off OC-21 … or name what is wrong". Its `run` field opens `wt-cc-141442-81738/.floorplan-iterations/layers/decks-review.html`.
  - decision `8e0ccb1f19ed`, listed as LIVE in `~/.claude/autonomy/research/decision-recheck-2026-10-18/REPORT.md:497-502`.
  - `wt-cc-141442-81738/.claude-plans/church-layer-review-RESUME.md`, which ends: *"Do nothing until the operator speaks."*
- **Worktree state:**

```
git -C wt-cc-141442-81738 status -sb       → ## cc-141442-81738...origin/main [behind 75]   (clean)
git rev-list --count origin/main..HEAD     → 0
git rev-list --count HEAD..origin/main     → 75
remote: git@github.com:renchris/reso-management-app.git
```

The session is committed and landed: nothing in it is unlanded. Two parts of the worktree are git-ignored: `.claude-plans/` (`.gitignore:82`) and `.floorplan-iterations/` (`.gitignore:187`). They hold the resume note and the review HTML and PNGs that the backlog row opens. **Removing the worktree would lose them.**

## 2. Is it alive after the 16:34 reboot? Yes. Boot-resume brought it back as window 19.

```
sysctl kern.boottime                         → Sun Oct 18 16:34:02 2026 (1792359242)
ps: 79176 (started 19:50:03) …/.claude-293/…/claude --permission-mode auto --model claude-opus-5-5 --effort high … --resume 9f6593c5-fa6d-…
    chain: login 77409 (kitty) → -zsh -ic '… reso-resume-one next …wt-cc-141442-81738 9f6593c5… || exec zsh -i' → bash reso-resume-one → expect → bash cc-close-attrib → claude
    exactly one claude process carries --resume 9f6593c5 (no second copy)
kitten @ ls → os_window 5, tab 5 (1 tab, 7 windows), window 19, title "✳ Insomniac Denver church floor-plan layer sign-off", 37×30 cells, not focused
```

The boot-resume event is `~/.claude/autonomy/boot-resume/events/boot-1792359242/`:
- `rows.tsv.tmp`: `next  9f6593c5-…  …/wt-cc-141442-81738  cc-141442-81738  wt-cc-141442-81738-258  claude-opus-5-5  high  …  auto  AT-REST`
- `lost.json` `.sessions["9f6593c5-…"]`: `{"verdict":"AT-REST","why":"tail is a completed assistant turn, 7.7 d idle","items":[]}`
- It appears in `noted` (line 24) and in `launched` (line 17).
- `map`: `cc-resume-layout: map sid=9f6593c5-… wid=19 oswin=1`
- No re-engage prompt was sent. `prompts/` has no 9f6593c5 file, which is correct for an AT-REST session.

The transcript mtime is 19:50 because the resume appended bookkeeping lines. There is still no new user or assistant turn.

**The pane is now shell-rooted.** I extracted the probe function into a file (`sed -n '/^pane_shell_root() {/,/^}/p' scripts/handoff-fire.sh > /tmp/q6-shellroot.sh`) and ran it:

```
pane_shell_root ttys031 (window 19's tty)  → yes
```

The function's root is `login`, whose child is `zsh`. `reso-resume-one:1120-1163` exits 0 only when claude exited 0 *and* no recycle is pending for the pane. Any pending recycle returns non-zero, so `|| exec zsh -i` leaves a shell for `--relaunch-at-shell`. **So the move lane's next pass would reach the in-place recycle, not `HELD:no-shell`.** No move batch has run since the reboot: the last one in `~/.reso/limit-recover/move/` is `20261018T191641Z`, at 14:16 CDT.

Stale references to fix in REPORT:
- "pane 258" is now **window 19**.
- REPORT line 190 says "live panes 19, 27 and 28 have no cc-registry row". Pane 19 is this session.

Window 19 sits in os window 5, which holds **7 panes**: 10, 11 (a bare shell), 12, 16, 17, 18 and 19. That is already over the "4 panes per fullscreen window" rule. Closing 19 takes the window to 6.

## 3. Decision 56c6862291f2: how often the hold fires, what replace does, and what can go wrong

### Population: one session

```
cd ~/.reso/limit-recover; grep -l '"HELD:no-shell"' */bundle-2026100[4-9]*/events.jsonl */bundle-2026101*/events.jsonl | awk -F/ '{print $1}' | sort | uniq -c
   7 9f6593c5-fa6d-45eb-babd-5f3be41cd18f
find … -mtime -14 | xargs grep -l HELD:no-shell   → 29 files: 21 move/…9f6593c5…, 7 9f6593c5 bundles, 1 ledger note (620db313 "move lane --no-replace HELD:no-shell every pass (launcher-rooted pane 258); mailed pane 411 fixer")
grep -c no-shell ~/.claude/logs/handoffs.jsonl    → 0   (the precheck hold never reaches the watcher log)
```

Before F14, the REPLACE path at `lr-handoff:2021` fired only at fire time. Searching for `MOVED-NEW-PANE|REPLACING in place|launcher-rooted` across all bundles in the window found one false hit: `4fe9935f/bundle-20261013T064725Z`, which was an ordinary `SWITCHED-UNPROVEN` in-place recycle. **In 14 days, no session other than 9f6593c5 was launcher-rooted at move time.**

### Every move attempt on 9f6593c5

Source: `move/*/9f6593c5-….json`.

| ts (Z) | pane | from→to | verdict | wall_s | reason |
|---|---|---|---|---|---|
| 10-11 15:48 → 21:42 | 2 | next4→next3 | 5× NOTMOVED, then MOVED | — | target-unverified, intent-invalid, resolver, load ×2, then moved |
| 10-13 01:52 | 2 | next3→next2 | MOVED | 232 | |
| 10-17 08:07 | 7 | next2→next | **STRANDED** | 1353 | "no live process holds the session" |
| 10-18 04:50 | 7/258 | next→next4 | FAILED | 973 | P2: pid 53550 still under `.claude-next` after 300 s |
| 10-18 06:49 | 258 | next→next4 | NOTMOVED | 2602 | REFUSED:not-limited |
| 10-18 07:18 → 18:17 | 258 | next→next3 | NOTMOVED ×10 | — | **HELD:no-shell ×7**, HELD:load ×2, slot-wait ×1 |

On 10-18 there were 12 attempts with 10,962 s (**3.0 h**) of move-worker wall in total. The 7 no-shell holds account for 2,953 s of that, and each held a slot in a 4-wide lane. All of this was spent moving a session that took **zero** turns. Moving an idle session saves no quota until it speaks.

### How pane 258 became launcher-rooted

The cause was a hand-built rescue, which `73949af55` does not cover. In the transcript of session `4736324c`, under `~/.claude-quaternary/projects/-Users-chrisren-Development-claude-infrastructure/`:
- At 2026-10-17T08:24:09Z it wrote `/tmp/resume-9f6593c5-retry.sh`, a 24-try loop of `lr-fire-resume.sh next … --no-prompt`.
- At 08:24:12Z it ran: `kitten @ launch --match id:7 --type=window --hold --cwd …wt-cc-141442-81738 --title "resume 9f6593c5 (next, retrying)" /tmp/resume-9f6593c5-retry.sh`

The window's root was therefore that script, with kitty's `--hold` wrapper around it, and not a shell. `73949af55` (validate-bash, today) denies `handoff-fire --launcher <temp path>`. It does **not** deny `kitten @ launch … /tmp/<script>`, which is exactly the command above. /tmp was cleared by the reboot, so the script no longer exists.

### What "replace" would do

The relevant code is in `scripts/limit-recover/lr-handoff.sh`:
- **`:1462-1470`.** With `--no-replace` and a probe reading `shell_root: no`, the precheck returns `HELD:no-shell` (rc 6) before anything moves: no lock, no tombstone, no keystroke.
- **`:2021-2028`.** Without `--no-replace`, a recycle refused with "has NO shell under its session" sets `LRH_REPLACE=1` and `CLOSE_SOURCE=1`.
- **`:2186-2200`.** The successor is started with `kitty @ launch --type=window --location=vsplit --next-to id:<source> --source-window id:<source> --cwd=current --dont-take-focus`.
- **`:2246-2263`.** If the split fails, the fallback is a new **os-window**, never a tab.
- **`:2337-2372`.** `--close-source` then runs `handoff-fire self-close --successor <new> --transplanted-source --source-pane <src> --source-session <sid>`. It exits 3 and leaves the source open if the new pane id is unknown.

The flag comes from `scripts/limit-recover/lr-move-worker.sh:404`, which always passes `--no-replace`. The same invocation also sets `LR_INPLACE_AWAIT=0`.

### What can go wrong with replace by default

These are measured against the operator rule: no tabs, at most 4 panes per fullscreen window, and replace should reuse the same pane.

1. **Replace cannot reuse the same pane.**
   - A kitty window dies with its root process, and kitty cannot start a new process inside an existing window. A launcher-rooted pane can therefore only be followed by a **new window id**. The filing says as much: "MOVED-NEW-PANE".
   - The window id is what mailbox aliases (`mailbox/.alias/<id>`), cc-registry rows and peer `--notify-back` targets bind to. All of them would need a rebind. cc-registry rows are already inverted (REPORT line 190).
   - The pane's position usually survives, because the successor is a vsplit beside the source and takes its space when the source closes.
2. **No pane cap.** The split arm (`:2186`) has no pane-count check. `grep -n 'MAX_PANES\|pane.cap' lr-handoff.sh` returns nothing. Only `handoff-fire.sh:18319` has `CC_FIRE_MAX_PANES`, and its default is 5, not 4. In the current layout, a replace of window 19 would briefly put **8 panes** in os window 5. If the source close fails or is refused (exit 3 paths), that becomes permanent.
3. **Two live copies of one sid.** The successor resumes on the target account while the source claude is still alive, until `self-close` retires it. A failed or refused close leaves the source alive beside its successor. `LR_INPLACE_AWAIT=0` means the move worker does not wait for engagement.
4. **Load and memory.** During the overlap there is one extra claude, node and expect process tree. Load at the time of measurement was 269.60, 293.25 and 301.10 on 10 cores (`uptime`). The incident record has memory-storm panics on this box.
5. **Benefit near zero.** The only launcher-rooted session in 14 days was idle for 7 days. Moving it saves no quota on the source account.
6. **It hides the cause.** Replacing by default would make hand-built launchers survivable and therefore invisible. The spawn-side deny is the fix that stops new launcher-rooted panes from appearing.

### The alternatives

| Option | Effect | Verdict |
|---|---|---|
| Replace by default (filing) | Moves launcher-rooted panes into a new window id, through a split with no cap | Rejected: breaks "same pane", adds a pane and a two-copy window, and protects n=1 |
| Keep the hold as it is | Correct and safe, but retried hourly; on 10-18 the 7 holds took 2,953 s of the lane's 10,962 s | Close, but wasteful |
| **Keep the hold, make it terminal-once, and close the spawn gap** | After one `HELD:no-shell`, skip the pane in move planning until its `shell_root` reads `yes`. Write one operator row. Add `kitten\|kitty @ launch … <temp path>` to the validate-bash `hf-tmp` deny next to `73949af55` | **Recommended** |
| Replace only when the operator opts in for a named sid | Keeps the REPLACE path for a rare busy case, through a manual `cc-lr move --replace <sid>` | Reasonable add-on; nothing currently needs it |

## Adversarial pass

- *"Closing loses warm context."* The session has one turn of context, and that turn is itself a resume. A fresh `claude --resume 9f6593c5` (account `next`, the transcript is in `.claude-next`) or a new session reading the RESUME note gets back the same state. Nothing is lost.
- *"Does closing break the operator's way into the ruling?"* No, as long as the worktree stays. Backlog `0f487bba36d4`'s `run` line opens a git-ignored file in that worktree, so the advice is to close the session and keep the worktree.
- *"Is there a second live copy?"* No. `ps` shows exactly one claude process with `--resume 9f6593c5`.
- *"Could another launcher-rooted pane exist now, undetected?"* Not checked across all live panes. Only window 19 was probed. Boot-resume panes all use the same `zsh -ic "… || exec zsh -i"` root (`cc-resume-layout.sh:962,1189` and `boot-resume-launch.sh:252`), so every pane boot-resume restored today is shell-rooted by construction.
- *"Why the kitty `--hold` wrapper read as `no`."* This is an inference, not measured: the pane was already gone. `pane_shell_root` (`handoff-fire.sh:7097`) counts a root as a shell only if it is a bare shell or a shell under `login`. A `--hold`-wrapped script is neither.
