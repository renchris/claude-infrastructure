# Map: live husk sweep + cc-husk-sweep verdict derivation (2026-10-24/25)

Read-only. No `--resume`, no closes, no sends. Every number is labelled with its command.

## 1. Live prevalence: zero husks at measurement time

- `cc-husk-sweep` and `cc-husk-sweep --json` at 2026-10-25T01:54:09Z (measured) both printed
  `cc-husk-sweep: no husk panes — every pane holds a claude, or none is enumerable`, rc 0.
- That message is ambiguous by design (bin/cc-husk-sweep:597). I ruled out "none is enumerable":
  `~/.claude/bin/it2 session list --json` returned **46 panes**, rc 0 (measured, `jq length`).
- Independent census (`python3 -I /tmp/sweep-census.py`, ps tree walk with unbounded depth,
  matching the real binary `@anthropic-ai/claude-code/bin/claude.exe` / `node_modules/.bin/claude`
  rather than the sweep's loose `*claude*` glob at bin/cc-husk-sweep:208): **46/46 panes hold a real
  claude binary** (measured). So the true live husk count is 0, not an enumeration failure.
- **Pane 289 no longer exists.** It was closed by hand at 2026-10-25T01:46:25Z by the parent
  session 0e2799a9: bash-commands.log line `K=$(bash ~/.claude/bin/cc-kitty-bin); timeout 15 $K @ --to
  unix:/tmp/kitty-1881 close-window --match id:289`. No closer recorded it: pane-close.jsonl's next
  289 row is `{"ts":"2026-10-25T02:03:08Z","pane":"289","verdict":"gone","reason":"not in kitty 1881's
  window list"}`.
- Since none of the 46 panes is a husk, there is no live row to classify. §3 classifies the husks that
  existed in the current kitty generation instead (kitty pid 1881, socket created Oct 21 14:55 CDT =
  19:55Z, `ls -la /tmp/kitty-1881`).

## 2. How cc-husk-sweep derives a verdict (bin/cc-husk-sweep)

Pipeline per pane (main loop :549-579):
1. **Enumerate**: `it2 session list --json` (:197-199). A failed list or non-array is exit 2 (:542-545).
2. **Husk test**: `has_claude_under <pid>` (:201-215) walks 4 generations of children and returns
   "live" if ANY descendant's command line contains the substring `claude`. Weakness: any helper
   with `claude` in its path (`~/.claude/bin/...`, `cc-await-ping` under `~/.claude`) hides a husk.
   Today it agreed with the strict census (46/46), but it is a loose test.
3. **Resolve sid** (`resolve`, :358-409), first hit wins, source printed:
   - `watchdog`: last `registered session=<sid> … pane=<N>` in lead-crash-watchdog.log since the
     running kitty's start (:249-259; `tty=none` headless rows excluded). A sid that is live elsewhere
     gives `live-elsewhere`, unresolved.
   - `registry`: `~/.claude/cc-registry/<pane>.json` (:370-379).
   - `scrollback`: last `claudeN --resume <sid>` line in `it2 session read -n 600`, only if no launch
     line came after it (:381-406). A failed read is `read-failed` (no fall-through).
   - Unresolved → row `UNKNOWN` with no sid, never resumed (:556).
4. **settle** (:415-439): the store holding `projects/*/<sid>.jsonl` names the account and launcher.
   The transplant check (`lr_transplant_target`) runs here.
5. **Facts**: `death_of` = last `.cause` for the sid in claude-crashes.jsonl (:440-444).
   `facts_of` = last `Good to close: <x>` in ASSISTANT text only, plus the session's last recorded cwd
   (:451-506, 30 s alarm, a cut read reports `-`). `work_of` (:507-514) runs **`git status
   --porcelain` over the whole cwd**: any line gives `dirty`. Otherwise `origin/main..HEAD` count >0
   gives `unlanded:N`, else `clean`.
6. **verdict_of** (:515-518): `dirty|unlanded` → RESUME (wins over a "yes"). close `no` → RESUME;
   `yes` + clean → DONE; `yes` + not clean → UNKNOWN; anything else → UNKNOWN.
7. **Overrides**, applied in this order, so the LAST one wins: COLLECTED (custody discharged since the
   transcript started; :567-568) → TRANSPLANTED→acct (:569) → lineage RECYCLED/MOVED (:572-573) →
   TEAMMATE (:574). Then DUPLICATE for any sid that two husks claim, unless the verdict is already
   never-resumable (:582-589).
8. `--resume` types `nocorrect CC_ACCOUNT_PINNED=1 <launcher> --resume <sid>` into RESUME and UNKNOWN
   rows, and into DONE rows too with `--all`. It never types into TRANSPLANTED, RECYCLED, MOVED,
   DUPLICATE, TEAMMATE or COLLECTED rows (:606-608).

**Same shared-checkout defect as cc-pane-close gate 4.** `work_of` counts the WHOLE checkout. On
`~/Development/personal` (a shared checkout, no worktree) every session reads `dirty` because of its
siblings' files. That makes `verdict_of` say RESUME even for a session whose last close said
`Good to close: yes`. Only the COLLECTED override (custody) rescued pane 289. A fired peer with no
custody row in a shared checkout would read RESUME, and `--resume` would revive a finished session.

**Cost.** A replay of one husk (pane 289, `CC_HUSK_PANES_JSON` seam with a fake pid 999999 so it is
not live) took **46.5 s wall** (measured, `time`). A 14-pane replay hit `timeout 250` (rc 124,
measured). The sweep is O(husks × ~45 s) and cannot keep up with a mass-husk event inside a bounded
caller.

### Replay of pane 289 (list mode, read-only seam)
`CC_HUSK_PANES_JSON=/tmp/sweep-fake-289.json cc-husk-sweep --json` →
`{"pane":"289","sid":"7555024a-…","launcher":"claude4","death":"clean-exit","close":"yes","work":"dirty","verdict":"COLLECTED","cwd":"/Users/chrisren/Development/personal","source":"watchdog"}`
COLLECTED comes from custody: open `fire-evolve-short-C` 2026-10-24T23:23:41Z (originator pane 13),
`return` 2026-10-24T23:51:57Z (`~/.claude/autonomy/custody/*.jsonl`, filtered by targetPane 289).

## 3. Three auditors, three state models, for the same pane 289

| Tool | Reads | Says |
|---|---|---|
| bin/cc-pane-close | gate 3 passes on `close=yes` (:497), then gate 4 counts the whole cwd, `git status --porcelain \| grep -c .` (:509-511) | REFUSED "138 uncommitted change(s)", 9 rows in pane-close.jsonl and 21 attempts in pane-close-retry.log (11 of them rc 124 with no output) |
| bin/cc-pane-verdict --recompute | substring of the closer's line, `*"uncommitted change"*` → RESUME (:86-87) | painted `⛔ resume 7555024a` / `✗ 7555024a stopped mid-task · 138 unsaved files` / `▶ cc-husk-sweep --resume --yes --pane 289` (pane-say.jsonl ts 1792886414 = 00:00:14Z) |
| bin/cc-husk-sweep | the same dirty fact, then the custody override | COLLECTED, "never resumed; close the pane" |

The painted action is a dead end. `cc-husk-sweep --resume --yes --pane 289` skips COLLECTED rows
(:607) and prints "nothing to resume". The pane's own screen points at a command that does nothing.

**The paint flip-flopped three times in 7 min** (pane-say.jsonl, epochs converted with `date -u -r`):
- 23:53:36Z DONE `⌘W closes it · last pane of a fullscreen window` (cc-pane-runner, at the
  fullscreen-guard refusal);
- 23:55:00Z CANTTELL `◆ can't tell if 7555024a finished` (lead-crash-watchdog; its own detail row
  says `ended cleanly … last close verdict: yes … dirty:138`);
- 00:00:14Z RESUME (cc-pane-retry → cc-pane-verdict --recompute from the gate-4 refusal).
The state store still holds the RESUME paint: `~/.claude/run/pane-verdict/1881-289.json`.

**Attribution of the 138** (measured, `git -C ~/Development/personal status --porcelain`): 138 lines
now, **0** under `reso-walkthrough/short/C-scenes` (the session's own commit f8258e8 touched only
that tree). The top owners are other sessions' trees: `deadlines/items` 59 and `launch-film-2026/*` 29+.

**Why the pane outlived the self-close.** kitty-pane-actions.jsonl:1441-1442: at 23:53:36-38Z
kitty-fullscreen-guard read window 289 as `os_window_id 25, panes 1, state FS, onscreen false` →
`refused-fs` rc 3. That is close-attrib's `STILL-PRESENT-rc70` at 23:53:38Z. By 00:51:05Z the same
OS window 25 held 4 panes (kitty-pane-actions row for wid 293). But cc-pane-close never re-asked the
guard, because gate 4 refuses BEFORE the ACT step where the guard lives (:509-515). So the transient
reason was replaced by a permanent, wrong one.

**How the retry row ended**: pane-close-retry.log 01:45:55Z `husk pane=289 its tty was typed in
since  — the operator owns it; row removed, never closed`. The timestamp is empty because
`pcq_get "$row" first_ts` returned nothing (scripts/pane-close-retry.sh:279), a minor logging
defect. The tty atime moved, from an unattributed reader: the operator was looking at the pane.

## 4. Classification of every husk in the current kitty generation (since 2026-10-21T19:55Z)

Sources: newest pane-close.jsonl row per pane, newest cc-pane-verdict paint in pane-say.jsonl, last
`pane=<N>` line in pane-close-retry.log (one shell loop over the 39 panes, measured). **39 distinct
panes** have pane-close rows in this window. None is alive now (none is among the 46 enumerated ids).

| Pane(s) | Newest pane-close | Paint | End | Class |
|---|---|---|---|---|
| 289 (7555024a) | refused ×9 "138 uncommitted" | RESUME (wrong) | closed by hand, kitty @ close-window 01:46:25Z, 1h53m after self-close | **should-have-closed** (yes + custody returned + own paths clean) |
| 282 (b5027c23) | refused-fs ×2 | DONE ⌘W | "pane gone" 23:30:15Z, ~49 min after rc70 at 22:41:35Z | **should-have-closed**; the guard was correct and only the operator could close it |
| 280 (00fe933b) | closed-kitty-unreaped 22:36:07Z | DONE ⌘W | closed when its window changed, 64 min after rc70 at 21:32:09Z | **should-have-closed** |
| 165 (e1436762) | refused-fs ×26 | DONE ⌘W | "pane gone" 21:17:55Z, about 8h17m after rc70 at 2026-10-23T13:01:14Z | **should-have-closed** |
| 144 (6713197c) | closed-kitty-unreaped after 53 rows | CANTTELL (wrong, it was a teammate) | closed 2026-10-23T18:49:42Z | **should-have-closed** (retired teammate) |
| 145, 146, 147 | closed-kitty-unreaped after 48/44/43 rows | NOTHING | closed 2026-10-23T17:12Z | **should-have-closed** (launch never started claude, rc 124) |
| 135 | refused ×6 "never started … tty unknown" | NOTHING | pane gone 04:20Z | should-have-closed |
| 141, 142 | refused "no session registration" | CANTTELL | pane gone 11:23Z | should-have-closed (nothing ran); the operator cleared them |
| 42, 85 | closed-kitty-unreaped 2026-10-23T01:16Z | none | closed | should-have-closed (custody returned / yes) |
| 26-32, 48-51, 63, 72-90, 101-109, 139 (teammate path) | refused "no session registration" | none | retry log `teammate pane=N ✓ pane gone` or `closed and verified gone` | should-have-closed (team member panes) |
| 54, 56, 133 | refused "remote control down + fullscreen" | none | dropped "row predates the running kitty" (56) | should-have-closed; the reason was transient |

Totals for this window: **0 should-be-running, 0 genuine-human-call, all 39 should-have-closed**
(estimated from the per-pane rows above). Not one husk in this generation was a crash that needed a
human decision. Every one was a pane whose session meant to end (or never started) and whose close
stalled.

Self-close outcomes since kitty start (`jq` over close-attrib.jsonl, site=self-close, measured):
closed 8, unverified-rc124 7, **STILL-PRESENT-rc70 6**, closed-rc67 6, closed-rc1 5, closed-rc124 1.
All six rc70 rows (panes 54, 56, 165, 280, 282, 289) became husks.

pane-close.jsonl lifetime totals (`jq -r .verdict | sort | uniq -c`, measured): refused 361,
would-close 24, closed-kitty-unreaped 9, nothing-to-close 5, failed 3. Refusals by class: never
started + tty unknown 130, no registration (+no exit record) 159, remote control down + fullscreen 23,
refused-fs 17, **uncommitted 9 (all pane 289)**, "nothing says session meant to end" 13.

Stale state: `~/.claude/run/pane-verdict/` holds 11 paint records (1881-135 … 1881-289) for panes
that no longer exist (measured, `ls` against the 46 live ids). Nothing reaps them.

## 5. Findings in one line each
- F1 (sweep): live husk prevalence is 0/46 at 01:54Z. Pane 289 was closed by hand at 01:46:25Z, not by
  any automated closer.
- F2: the "whole cwd is dirty" fact appears in TWO tools: cc-pane-close gate 4 (:509-511) and
  cc-husk-sweep `work_of` (:507-514). On a shared checkout it is always true.
- F3: cc-pane-verdict re-derives state from a substring of the closer's text (:83-91). An
  "uncommitted" refusal becomes RESUME even when the session said yes and custody was returned. That
  disagrees with cc-husk-sweep's COLLECTED.
- F4: the RESUME paint names `cc-husk-sweep --resume --yes --pane 289`, which skips COLLECTED. The
  remedy on screen does nothing.
- F5: the fullscreen refusal is not re-evaluated once the window gains panes, because gate 4 runs first.
- F6: cc-husk-sweep costs about 46 s per husk. A 14-husk replay timed out at 250 s.
- F7: `has_claude_under` uses the substring `*claude*` over 4 generations. That is a false-live risk
  (no false-live today).
