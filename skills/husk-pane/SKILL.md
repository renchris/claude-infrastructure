---
name: husk-pane
description: "Diagnose and resolve a kitty pane stuck at a bare shell with a ⛔/◆ banner after a Claude session ended: read the sweep, close logs, transcript close and custody, then close the pane safely or resume it with the pinned launcher."
argument-hint: "<kitty window id> [--dry-run]"
---

# Husk pane — diagnose, then close or resume

A **husk** is a kitty pane where a Claude Code session used to run and now only a shell runs,
usually painted by `cc-pane-verdict` (title `⛔ resume <sid8>` or `✓ … finished`, row 2 a `▶` command).
Exactly two end states are correct:

| The session… | Correct end state |
|---|---|
| meant to end (wrote `Good to close: yes`, self-closed, was collected by its originator, is a retired teammate, or moved to a live copy) | the **pane closes** |
| stopped with its own work open (`Good to close: no`, its own files uncommitted, killed mid-task) | the **same pane resumes** the session on its pinned launcher |

A husk that sits for hours is always a disagreement between these tools, never a third answer.
History and why it keeps recurring: `docs/research/husk-history-2026-10-24/CENSUS.md`.
Other recovery skills: whole-fleet crash or reboot → `resume-sessions`; a session hit a limit or
was transplanted between accounts → `/limit-recover` (its `HUSK` is a *live* source pane, the
opposite shape); many husks at once → `cc-husk-sweep` with no `--pane`.

## Hard rules

- **Never close or kill a pane with a live job in it.** A live `claude`, `node`, editor or any
  non-shell process means it is not a husk. `cc-pane-close` gate 2 checks this, and there is no
  other close path (step 3).
- **Never close the last pane of a fullscreen OS window** by any path other than the guard. That
  is the 2026-10-15 kitty crash trigger. The guard's `refused-fs` means only the operator's ⌘W
  can close it. Ctrl-D is not a workaround.
- **Never type a resume line by hand.** The pane's printed `claude --resume <sid>` uses the
  default account and cannot find a transcript in another account's store. Use
  `cc-husk-sweep --resume --yes --pane N`, which is allowlisted and types the pinned launcher
  (`nocorrect CC_ACCOUNT_PINNED=1 claudeN --resume <sid>`).
- **Do not resume over the verdicts the sweep never resumes**: `COLLECTED`, `TEAMMATE`,
  `DUPLICATE`, `RECYCLED→…`, `MOVED→…`, `TRANSPLANTED→…`. Resuming any of them puts a second
  writer on live work or re-arms a finished session's `/goal`.

## Step 1 — the facts, all read-only (run them together)

```bash
P=<window id>
cc-husk-sweep --pane "$P" --json                      # sid, launcher, death, last close, VERDICT
cc-pane-close --pane "$P" --dry-run                   # WOULD CLOSE, or the first gate that refuses
jq -c "select(.pane==\"$P\")" ~/.claude/logs/pane-close.jsonl | tail -5     # closer history
jq -c "select(.id_requested==\"$P\")" ~/.claude/logs/close-attrib.jsonl | tail -5  # self-close tries
jq -c "select(.pane==\"$P\")" ~/.claude/logs/pane-say.jsonl | tail -5       # what was painted, by whom
jq -c "select(.pane==\"$P\")" ~/.claude/logs/husk-sweep.jsonl | tail -3     # past sweep actions
```

Then, with the sid from the sweep:

```bash
SID=<full sid>; T=$(ls ~/.claude*/projects/*/"$SID".jsonl 2>/dev/null | head -1); echo "$T"
# the session's LAST close, assistant text only (CLAUDE.md quotes both forms, so never grep the file);
# context only — the verdict is pe_verdict's (step 2)
jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="text") | .text' "$T" \
  | grep -E 'Good to close: (yes|no)' | tail -1
cc-custody list --json | jq -c --arg p "$P" '.[] | select(.targetPane==$p)'   # open, then return/abandon = collected
```

Reading the self-close row: `verdict` `closed` = it worked; `STILL-PRESENT-rc70` = the
fullscreen guard refused at that moment (rc 3 to the caller, no retry); `refused-*` = an identity
or ownership gate. Reading the closer row: the `reason` string is the exact gate that refused.

## Step 2 — the verdict is computed, not judged here

`cc-pane-close`, `cc-husk-sweep` and the crash watchdog all ask one function, `pe_verdict`
(`lib/pane-end.sh`; design `docs/research/husk-history-2026-10-24/FIX-DESIGN.md` §2). Do not
re-derive it from the transcript or from `git status` by hand — that is how the tools came to
disagree. What it already accounts for:

- **Sibling dirt.** On a clean end (crash log `RECYCLE`, or exit rc 0/75) only the files the
  session wrote (Edit/Write) and its own unlanded commits count, so a shared checkout's other work
  no longer blocks a finished session (pane 289). On a crash or an unknown end every change counts.
- **No transcript.** A registered session that never wrote a record and ended cleanly never had a
  turn: DONE (pane 304).
- **Custody.** A returned/abandoned row since the session started is COLLECTED; an open one makes a
  crash OWNED (its originator is handling it — never resume).

The closer's refusal line ends `[state=DONE|RESUME|CANTTELL|OWNED:<pane>]`; that token is the
verdict. A clean exit is never RESUME.

## Step 3 — act on what the closer says

| `cc-pane-close --pane "$P" --dry-run` says | Do |
|---|---|
| `ALREADY CLOSED` / `NOTHING TO CLOSE` | nothing — it is gone, or kitty has not reaped it |
| `REFUSED — … a live job runs` / `its claude … is still running` | **leave it** — not a husk |
| `WOULD CLOSE` | `cc-pane-close --pane "$P"`, then read its verdict line (`CLOSED`, or `CLOSED … kitty has not reaped it` = kitty wedged) |
| `REFUSED — … refused-fs … [state=DONE]` | last pane of a fullscreen window. If the pane runs `cc-pane-runner` it is **held** and closes itself when its window gains a pane; otherwise repaint and file the ⌘W (below) |
| `REFUSED — … [state=RESUME]` | `cc-husk-sweep --resume --yes --pane "$P"`, then re-run the dry run: it must now refuse with "its claude … is still running" |
| `REFUSED — … [state=OWNED:<M>]` | leave it: pane M holds its custody. Never resume it |
| `REFUSED — … [state=CANTTELL]` | read the reason (it names the session's own files or its end). A clean end is not resumed by the sweep; decide with the operator or `cc-husk-sweep --pane "$P" --resume --all` only after reading it |
| `REFUSED — … STRANDED` | `lr-fleet --one <sid8>` (the session moved and no live copy runs) |

There is no manual close path: never close a pane with raw `kitty @` or `it2` here. Every close goes
through `cc-pane-close`, which asks the fullscreen guard first.

**Repaint after a refusal,** passing the refusal through so the painter renders the closer's state
and its guard row, never a guess:
`cc-pane-verdict --pane "$P" --recompute --closer-out "$(cc-pane-close --pane "$P" --dry-run)"`.
For a fullscreen refusal of a pane that is not held, file the ⌘W for the operator:
`cc-backlog needs "close pane $P with ⌘W (finished session <sid8>, last pane of a fullscreen window)" --class needs-human`.

## Step 4 — report

One line per pane: `pane N · <sid8> · <closed|resumed|left: live|operator ⌘W filed> · <the fact that decided it>`.
If the closer, the sweep and the painter disagreed, say which one was wrong and add the pane to
`docs/research/husk-history-2026-10-24/CENSUS.md` § recurrence if it is a new shape.
