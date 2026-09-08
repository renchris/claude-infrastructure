---
description: The three close questions — current steps/decisions · working or idling · 100% complete and safe to close
disable-model-invocation: false
allowed-tools: Bash(scripts/wrap-ledger.sh*), Bash(*/wrap-ledger.sh*), Bash(hooks/operator-readout.sh*), Bash(*/operator-readout.sh*), Bash(cc-custody*), Bash(*/cc-custody*), Bash(cc-sessions*), Bash(*/cc-sessions*), Bash(git fetch*), Bash(git status*), Bash(git ls-tree*), Bash(git diff*), Bash(git merge-base*), Bash(git log*), Read
---

The operator's standing close question, saved verbatim:

> What are our current steps / decisions; are we working or are we idling; are we 100% complete
> with no loose-ends or follow-ons and can gracefully close?

Answer all THREE parts, from the live reads below — never from memory, never from what you
remember doing this session. This is `/wrap` plus the axis `/wrap` cannot see: **whether anything
is still in flight**. A session that reads `✅` locally while a dispatched peer holds its work is
exactly the false close the custody ledger exists to catch.

## Read

- State rung: !`scripts/wrap-ledger.sh 2>&1 || true`
- Goal liveness (prints NOTHING unless a `/goal` is live): !`scripts/wrap-ledger.sh --goal 2>&1 || true`
- Steps + decisions the operator owns: !`hooks/operator-readout.sh --render 2>&1 || true`
- Work dispatched from here and not returned: !`cc-custody list --open --fresh 2>&1 | head -10 || true`
- …and the stale tail (open >24h — supersede or return, never ignore): !`cc-custody count --open --stale 2>&1 || true`
- Live sibling sessions: !`cc-sessions 2>&1 | head -20 || true`

Also check YOUR OWN in-flight work before answering part 2 — background Bash tasks, spawned
agents, an armed `session-continue.sh` step. Those are yours and they are not on disk.

## Answer — the VERDICT FIRST, then its two supports

🚨 **The three questions are answered in ONE order and it is not the order they were asked in.**
The operator asks *steps · working · done*; you answer **done · working · steps**. Their question
is a checklist of what they want covered, never a running order — and a verdict that arrives after
two paragraphs of process has already cost the round-trip this command exists to prevent.

Emit exactly this shape. Nothing above line 1, no preamble, no restatement of the question:

```
<rung glyph> <state clause> — <one clause naming what the work WAS>
Good to close: yes — nothing of mine is open; follow-on: <filed ids | none>
▶ Run this:                          ← ONLY if a command is genuinely theirs to run

Working | Idling — <cause, one clause>
Mine this session: <what THIS session filed or created, named | nothing unfiled>
```

**Report the verdict, NOT the audit trail.** You run every check below; you SHOW a check only when
it FAILS or reads UNKNOWN. `DIRTY=0 · AHEAD=0 · REMAINDER=0`, an `ls-tree` that returned blobs, a
custody marker that did not match, a port you stopped — those are how you know, and the operator
asked what you know. A green check is worth zero words.

`yes` requires ALL of: the rung is `✅` (or `👤` with every step FILED, not prosed) · clean tree ·
landed verified **by content** (`git ls-tree origin/main -- <your paths>`, never by a commit
count — a sibling's rebase reads 0 and proves nothing) · your diff's gates ran green THIS turn ·
frozen-DoD remainder 0 · custody carries no row with YOUR marker. Any one unknown ⇒
`Good to close: no — <which check, and who owns it>`. Never hedge a `yes` with a trailing caveat:
if something is parked or theirs, that IS the rung, and it belongs on line 1.

### On `yes`, RETIRE THE PANE — do not offer to

🚨 **"I'll close on your word" is the defect this section exists to delete.** The operator asked
whether the work is exhaustively done; if it is, the pane retiring is the rest of that same
sentence, not a follow-up they should have to type. Answer, then act:

| This pane is | On `yes`, do this |
|---|---|
| a **fired peer** (a handoff-engagement marker in its prompt) whose work is landed and collected | Announce (`cc-notify <originator> "…"`), then **self-close yourself**: `$HOME/.claude/scripts/handoff-fire.sh self-close --terminal`. No `▶ Run this:` line — there is nothing for them to run. |
| the **operator's own pane** (no engagement marker) | Say plainly that it is exhaustively done and safe to close, and stop. Retiring their pane is theirs; do NOT self-close, and do not leave a command they did not ask for. |

Either way say the word **exhaustively** only when it is literally true — landed by content, gates
green this turn, DoD remainder 0, custody clean, nothing filed against this session. It is the
operator's own word for the state they are asking about, and it must not degrade into a pleasantry.

### Two things NOT to print

- **The `OPERATOR ▸` block.** `operator-readout.sh` renders it at Stop on this very turn, so
  relaying it here puts the same ten lines on screen twice. Read it, act on anything of yours in
  it, and let the Stop hook be the one renderer. (The silver-platter rule bans *paraphrasing* a
  rendered block — it never asked for a second copy. If you must point at it, one clause: "the
  standing pile below is not from this session.")
- **The derivation.** How you established the verdict — which command you ran, what it printed,
  what you compared it against — belongs in the tool calls the operator can already see, not in
  the answer.

**Acceptance:** the whole reply fits well inside one 24-row pane, and its first two lines answer
the question on their own. If the operator can read line 1 and line 2 and know both the state and
whether to close, the rest is optional by construction — which is the only test that matters here.
