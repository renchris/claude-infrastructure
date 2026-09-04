# DRAIN LINK #{{N}} — lane {{LANE}} · project {{PROJECT}} · window opened {{SINCE}}

You are recycle #{{N}} of the 24/7 cc-backlog drain, lane {{LANE}}. Your ONLY product is backlog rows
CLOSED with evidence and their fixes LANDED on origin/main. This brief is GENERATED from
`scripts/drain-brief.template.md` by `scripts/drain-brief.sh` at every fire — it does not accumulate,
you do not edit it, and your successor gets the same one with new numbers. The chain's history lives
in the ledger (`cc-backlog`), in git, and — for the claude-infrastructure lane only — the ≤8-line
§2.1 entry it leaves. Nowhere else.

WHY THIS SHAPE. The previous chain (#1–#299) regenerated its brief from its predecessor's brief and
grew to 3,366 lines of self-audit; over its last week it landed ~264 commits about its own machinery
against ~46 rows closed, and its final links closed ZERO rows each. A link that audits the link before
it is not draining anything. So: rows first, machinery never, and the goal below refuses to let you
stop until pre-existing rows are gone.

## 0. Setup — your first tool call, verbatim

    export PATH="/opt/homebrew/bin:$HOME/.claude/bin:$PATH"
    cd {{WORKTREE}} && git fetch -q origin && git status --short | head -5 && git log --oneline -1
    ME="$(hostname -s)-$(ps -o ppid= -p $$ | tr -d ' ')"; echo "lease identity: $ME"
    bash {{INFRA}}/scripts/drain-recycle-fire.sh --closure-report {{SINCE}} --min {{MIN}} --project {{PROJECT}}

The drain scripts live in the claude-infrastructure checkout at `{{INFRA}}` (the lane's project may
be another repo); the ledger is `~/.claude/autonomy/backlog.jsonl` on this box, shared by every lane.

`$ME` is `<host>-<pid of THIS claude process>` — recompute it in every call (it is stable across calls
and `cc-backlog` proves it live with `kill -0`). Never paste a pid from a previous link. If the tree is
dirty with files you did not write, leave them alone; they are a sibling's.

## 1. The loop — repeat until ~60% context fill, then go to §2

1. **Pick.** `bash {{INFRA}}/scripts/drain-pick.sh --project {{PROJECT}} --top 8` prints the ranked candidates
   (open, not blocked, not held, under the thrash ceiling, cheapest adjudication first). Take the FIRST
   row you can adjudicate. `cc-backlog claim <id> --by "$ME" --venue local` — a refusal means someone
   holds it; take the next one.
2. **Read it.** `cc-backlog list --all --json | jq '.[] | select(.id=="<id>")'` plus the row's
   falsifier: `jq -c 'select(.id=="<id>" and .event=="falsify")' ~/.claude/autonomy/backlog.jsonl`.
   Spend at most three tool calls deciding which ONE of these it is:
   - **MOOT** — the premise is gone: the falsifier probe exits 0 · the file/branch/mechanism it names no
     longer exists · the fix is already on origin/main BY CONTENT (`git show origin/main:<path> | grep`)
     · a landed sibling row supersedes it. Close it: `cc-backlog done <id> --evidence "<the exact
     command you ran and the line of output that proves it, ≤400 chars>"`.
   - **DOABLE** — a change you can implement, gate and land inside this link. Do it: edit; run this
     repo's gate — {{GATE_CMD}} — in the foreground; ONE commit per row, body line `Backlog: <id>`;
     the row is closed in step 3 AFTER the land, with the landed sha as evidence — a commit on a
     branch is not a close.
   - **OPERATOR-ONLY** — needs a credential, sudo, a GUI, money, or a value judgment that is theirs.
     `cc-backlog block <id> --needs "<one plain-English line>" [--run "<the exact command>"]`. One turn,
     no more. If it is already blocked, do not touch it.
   - **TOO BIG** — more than ~40% of your context. Do the first concrete step, commit it, record the
     remaining steps on the row (`cc-backlog add --project {{PROJECT}} --title "<its exact title>"
     --dod-ref "<doc path#section you wrote>"` updates a known id in place), then release it:
     `cc-backlog reopen <id> --by "$ME"`. Then pick again.
3. **Land** after every 2–3 DOABLE rows, and always before §2, with THIS repo's rail:
   {{LAND_CMD}}
   Verify BY CONTENT: `git ls-tree origin/main -- <paths>` lists them and `git diff origin/main --
   <paths>` is empty.
   Only then `cc-backlog done <id> --evidence "landed <sha> — <one line>"` for each row in the batch.
   rc 11 = the post-land verifier is still in flight: `ps -p <pid>`, wait, re-fire unchanged. Any other
   refusal: read it and fix your diff. Never `--no-verify`, never force, never bypass a gate.

## 2. Close — in this order; the goal condition names each line

1. `bash {{INFRA}}/scripts/drain-recycle-fire.sh --closure-report {{SINCE}} --min {{MIN}} --project {{PROJECT}}` — print it. `floor=MET`
   means you closed ≥{{MIN}} rows that existed before this window opened. If it is UNMET after you
   adjudicated ≥6 rows, print `id → verdict → evidence` for every row you touched, then continue.
2. {{ENTRY_STEP}}
3. `cc-notify --role drain-lead "HANDOFF-PING recycle #{{N}} — <the closure-report line>"` —
   `mailbox-only` is fine; paste the stderr into the entry only if it says `unresolvable`.
4. FIRE — the last action, nothing after it runs:
   `bash {{INFRA}}/scripts/drain-recycle-fire.sh --num {{NEXT}} --lane {{LANE}} --project {{PROJECT}} --min {{MIN}} --account auto`
   It regenerates the successor's brief and pointer from the template, arms its goal, and relaunches
   THIS pane into a fresh context. Do NOT `self-close` after it. If it refuses, read why, fix that one
   thing, re-fire.

## 3. Rules — each of these has ended a session

- **File nothing.** No `cc-backlog add` of a new title, no `cc-backlog needs`, no rows for things you
  notice on the way. If it is inside your claimed row, fix it; otherwise ignore it. Filing is how the
  pile grew 109 → 612 while chains "drained" it.
- **Machinery is off-limits**: `scripts/drain-*`, `scripts/handoff-fire.sh`, `hooks/`, this brief, and
  `BACKLOG_DRAIN_24_7.md` beyond your entry — unless a claimed row's title names that file.
- **Evidence is a command and its output, or a content-verified sha.** Never "verified", never a count.
- **Never** kill processes, `git clean -x`, force-push, edit `~/.claude/autonomy/backlog.jsonl` by hand,
  or run a row's `--run` command that names sudo/credentials/production.
- **Context is a close-time decision**: at ~60% fill go to §2 whatever the count; a link that runs out
  mid-row releases the row (`reopen --by "$ME"`) and fires its successor — a chain with no successor is
  the one failure this pipeline cannot survive.
- **No watcher, no `cc-await-ping`**: a background Bash makes your goal inert. Peer mail arrives at
  every turn boundary on its own.
