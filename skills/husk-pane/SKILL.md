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
  non-shell process means it is not a husk. `cc-pane-close` gate 2 checks this; a manual close
  must check it too (step 4).
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
# the session's LAST close, assistant text only (CLAUDE.md quotes both forms, so never grep the file)
jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="text") | .text' "$T" \
  | grep -E 'Good to close: (yes|no)' | tail -1
cc-custody list --json | jq -c --arg p "$P" '.[] | select(.targetPane==$p)'   # open, then return/abandon = collected
```

Reading the self-close row: `verdict` `closed` = it worked; `STILL-PRESENT-rc70` = the
fullscreen guard refused at that moment (rc 3 to the caller, no retry); `refused-*` = an identity
or ownership gate. Reading the closer row: the `reason` string is the exact gate that refused.

## Step 2 — whose dirt is it? (the usual cause of a wrong "resume" screen)

`cc-pane-close` gate 4 and `cc-pane-verdict --recompute` count **every** uncommitted file in the
session's cwd. In a shared checkout (`~/Development/personal`, the infra checkout) that is mostly
sibling sessions' work, so a session that finished cleanly reads as "stopped mid-task · N unsaved".
Separate the session's own paths from the rest:

```bash
CWD=$(jq -r 'select(.cwd) | .cwd' "$T" | tail -1)
jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use")
       | select(.name|test("^(Write|Edit|MultiEdit|NotebookEdit)$")) | .input.file_path // .input.notebook_path' "$T" \
  | sort -u > /tmp/husk-$P-own.txt
git -C "$CWD" status --porcelain -- $(sed "s|^$CWD/||" /tmp/husk-$P-own.txt) | head
git -C "$CWD" status --porcelain | wc -l                                       # everyone's
```

Own paths clean ⇒ the dirt is not this session's and does not block its close. Files it wrote
through Bash (`sed -i`, `cat >`) are invisible to this list, so also read its last commits
(`git -C "$CWD" log --since=<session start> --author=…`) before ruling "own paths clean".

## Step 3 — decide

| Facts | Decision |
|---|---|
| A live non-shell process in the window | **Leave it.** Not a husk. |
| Sweep says `COLLECTED`, `TEAMMATE`, `RECYCLED→`, `MOVED→`, `TRANSPLANTED→`, or `DONE` | **Close** |
| Last close `Good to close: yes` (or a self-close stamp) and own paths clean | **Close**, even if the cwd holds sibling dirt |
| Last close `Good to close: no`, or own paths dirty, or killed mid-task (sweep `RESUME`) | **Resume** |
| Sweep `UNKNOWN` (no close found) and own work open or unprovable | **Resume** (a session that cannot be shown done is not done) |
| Sweep `DUPLICATE` | Neither yet: find which pane really ran the sid (`cc-find <sid8>`), close the other |
| Sweep `RESUME` only because of sibling dirt, but the close says yes | **Close** — this is the pane-289 defect, the sweep's dirt read is too wide |

## Step 4 — act

**Resume:** `cc-husk-sweep --resume --yes --pane "$P"`, then confirm the pane shows a live
session (`cc-pane-close --pane "$P" --dry-run` now refuses with "its claude … is still running").

**Close, when the dry run says WOULD CLOSE:** `cc-pane-close --pane "$P"` and read its verdict line
(`CLOSED`, or `CLOSED … kitty has not reaped it` = kitty wedged, the pane redraws when kitty recovers).

**Close, when the dry run refuses only at gate 4 on sibling dirt** (step 2 proved own paths clean):

```bash
TO=$(~/.claude/bin/cc-kitty-socket)                    # unix:/tmp/kitty-<running kitty pid>
kitty @ --to "$TO" ls | jq -r --argjson p "$P" '.[].tabs[].windows[] | select(.id==$p)
  | .foreground_processes[].cmdline | join(" ") | .[0:80]'              # must be a shell alone
kitty @ --to "$TO" ls | jq -r --argjson p "$P" '.[].tabs[] | select(any(.windows[]; .id==$p))
  | "panes in this tab: \(.windows|length)"'
~/.claude/bin/kitty-fullscreen-guard --window "$P" --to "$TO" --scope pane --mode refuse --tool husk-pane; echo "guard rc=$?"
```

Close only if the foreground processes are a shell alone (`-zsh`, `zsh`, `login`) **and** the
guard printed rc 0. Then `~/.claude/bin/it2 session close -f -s "$P"` (the shim re-asks the guard
and the composer guard) and verify by effect: the window id is absent from `kitty @ ls`.
- guard rc 3 `refused-fs`: last pane of a fullscreen window. Repaint it truthfully
  (`cc-pane-verdict --pane "$P" --state DONE --sid "$SID" --guard fullscreen`) and file the ⌘W for the
  operator: `cc-backlog needs "close pane $P with ⌘W (finished session ${SID:0:8}, last pane of a fullscreen window)" --class needs-human`.
- guard rc 4: the window is already gone. Done.
- any other rc: the guard could not read the window; retry once after a few seconds, then repaint and file.

**After any close that could not happen,** repaint the pane with the truth so nobody resumes a
finished session: `cc-pane-verdict --pane "$P" --state DONE --sid "$SID"` (row 1 "finished · nothing
to resume"). Never leave a `⛔ resume` paint on a session whose own close said yes.

## Step 5 — report

One line per pane: `pane N · <sid8> · <closed|resumed|left: live|operator ⌘W filed> · <the fact that decided it>`.
If the closer, the sweep and the painter disagreed, say which one was wrong and add the pane to
`docs/research/husk-history-2026-10-24/CENSUS.md` § recurrence if it is a new shape.
