# Held self-recycle leaves `/exit` in the composer (pane 206, 2026-10-10)

Scope (frozen): root cause per question (a)-(d) for the pane-206 held self-recycle written here; the
smallest fix that makes a held recycle leave the composer empty and either complete on retry or say
exactly why not, with a bats test reproducing the incident shape (tall block above the composer,
deferred path) that fails before the fix and passes after; landed on trunk.

## Answer

One regression, one missing take-back. Commit **f14b42653** (17:43 CDT, live in `~/.claude` from
the 18:46:32 CDT fast-forward) added rule (vi) to `composer_content`: a `❯` row at indent 1-4 above
the box is a dialog, so the read is UNKNOWN. Claude Code's slash-command menu, which our own typed
`/exit` opens, draws exactly that row above the box: `  ❯ /exit   Exit the CLI`. From the deploy on,
every `/exit` read-back read `<unreadable>`. `hf_exit_readback` then held without typing anything,
because it sends its five DELs only over a read that ends in `/exit`. It also wrote no residue
receipt, so `/exit` stayed in the box with the menu open. Every later read of that pane stayed
UNKNOWN, and the deferred retry refused after 180 s.

## (a) Why the composer read `<unreadable>`, both times

It was our own `/exit` that opened the menu; the Stop-hook block played no part.

- Attempt 1's last read (`hf_recycle_last_read`, the composer gate at 0 s wait) passed EMPTY
  immediately before `/exit` was typed. Had the screen above the box been unreadable, it would have
  held `unreachable` there. The read went UNKNOWN only after our keystrokes.
- Live capture, throwaway pane (Claude Code 2.1.291, `/exit` typed without Enter):
  `tests/fixtures/recycle-exit-residue/slash-menu-exit-2.1.291.txt`. The menu sits above the box,
  and its highlighted row is `  ❯ /exit` at indent 2.
- Replaying `composer_content` from each revision over that capture: `9e56493ec~1` gives `/exit`,
  `9e56493ec` gives `/exit`, `f14b42653~1` gives `/exit`, and `f14b42653` gives rc 1 (UNKNOWN).
  After five DELs the menu closes and the box reads EMPTY again.
- Attempt 2's mid-turn first look saw the same screen: attempt 1's `/exit` was still in the box
  with the menu open. So it read UNKNOWN and deferred.

## (b) Attempt 2: what typed `/exit`, and the verdict line

Attempt 2 typed nothing. The `/exit` in the operator's screenshot is attempt 1's, at 01:23:54Z. The
defer log does carry a verdict, written at 20:28:06, the same minute as the RECYCLE-HELD mail. The
"no verdict line" reading was taken before the 180 s gate finished:

```
→ deferred: the turn ended after 18s — running the composer gate and the recycle
!! recycle REFUSED after 180s: pane 206's composer could not be READ … Nothing was typed …
→ retry ticket: …/recycle-retry/4d08e115-….json (attempt 1, jobs=-) …
→ retry ticket: wake mail verdict=delivered
```

The waiter (pid 48218) did not die; it exited after writing that verdict. No watcher was alive
afterwards, and that is by design. Attempt 1's hold disarmed its watcher (pid 22979), and attempt 2
never armed one because it refused at the composer gate. In handoffs.jsonl, rows 1134-1144 show
`recycle-held-exit-readback` (01:24:00Z), then `recycle-deferred-turn`, then `recycle-turn-ended`,
then `recycle-held-unreachable` (01:28:06Z).

## (c) Why the residue stayed

`hf_exit_readback` takes its keystrokes back only when the read-back ends in `/exit`
(`case "$HF_EXIT_RB_TEXT" in */exit) …DELs…`). `<unreadable>` matches nothing, so nothing was sent.
The hold message said "five DELs sent to take our /exit back out" anyway, because it was a fixed
string. No receipt was written either: `~/.claude/logs/composer-residue/` holds none for panes 134,
168 or 206. Without a receipt, the gate's own-residue arm (item 1ea55b6ad9f3) cannot attribute the
box to us, even once it can be read. Refusing to type into an unreadable box is deliberate
(FLEET_V2 W6 D7.3) and stays. The missing receipt and the false message were the defects.

## (d) How often today: one cause

These are the handoffs.jsonl rows since the 18:46:32 CDT deploy (23:46:32Z). Every `/exit`
read-back was `<unreadable>` (4 of 4), and no recycle that typed `/exit` completed. Pane 7's
recycle at 23:11Z, before the deploy, completed.

| pane | `/exit` held unreadable | follow-on holds over the residue |
|---|---|---|
| 134 | 00:25:47Z | 01:21:14Z deferred → 01:24:32Z unreachable 180 s |
| 168 | 00:47:22Z (carried text not restored, 00:47:42Z) | 01:11:52Z, 01:24:27Z unreachable 180 s |
| 206 | 01:24:00Z | 01:24:45Z deferred → 01:28:06Z unreachable 180 s |
| 2 | 01:28:24Z | — |

Earlier holds today have other, already-known causes and fall outside this incident: a stalled kitty
socket (05:20Z, panes 14, 3 and 2), an empty read-back on pane 11 (05:50Z), and a last read that
could not see the box on pane 188 (16:24Z, before f14b42653 existed).

## Fix

A sibling session hit the same defect on pane 168 and landed **0584f0720** at 20:26:43 CDT, three
minutes after pane 206's first attempt and before any converge, so it was not live for this
incident. It makes both changes this investigation called for:

1. `composer_content`: a `❯` row above the box that starts with `/` is not a dialog. Kill switch:
   `HF_COMPOSER_SLASH_MENU=off`.
2. `hf_exit_readback`: any read that does not end in `/exit` receipts exactly `/exit`, so on retry
   the gate's own-residue arm (Ctrl-U, read back) scrubs it once the box reads back exactly that.
   The hold message reports the take-back that really happened instead of always claiming five
   DELs.

**This change tightens (1).** With the menu open, a CR submits the menu's highlighted row, not the
box. 0584f0720 exempts any `❯ /…` row, so a box holding `/exit` under a menu that highlights
`/export` reads `/exit`, and the CR that follows would run `/export`. The exemption now holds only
when the highlighted row names the same command as the box's first row (`❯ /<cmd>` at column 0).
Every other selector above the box, a real dialog included, still reads UNKNOWN. Corpus replay
over 1,131 screens (1,061 composer snapshots plus every repo fixture): 0 verdicts change, against
both 1b2b93357 and 0584f0720.

Not changed: the tall-window branch (no slash-menu screen reaches it) and `lr-fire-resume.sh`'s
copy of rule (vi), which reads a resume prompt it typed and never types a slash command.

Test: `tests/recycle-exit-residue.bats`, built on the real 2.1.291 capture under a 30-row Stop-hook
block. It covers the read-back, the deferred retry over our receipted `/exit`, and two fail-closed
controls. The RED-proof is in the file header.
