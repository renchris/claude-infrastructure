---
description: The three close questions — current steps/decisions · working or idling · 100% complete and safe to close
disable-model-invocation: false
allowed-tools: Bash(scripts/wrap-ledger.sh*), Bash(*/wrap-ledger.sh*), Bash(hooks/operator-readout.sh*), Bash(*/operator-readout.sh*), Bash(cc-custody*), Bash(*/cc-custody*), Bash(cc-sessions*), Bash(*/cc-sessions*), Read
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

## Answer, in this order

**1 — Current steps / decisions.** Relay the `OPERATOR ▸` block VERBATIM (silver-platter rule:
never paraphrase a rendered block back into prose). Then name, in plain English, anything THIS
session created that no store holds yet — and file it (`cc-backlog needs "<step>"` /
`cc-decide open --class C --what "<plain English>"`) rather than prosing it, so the next reader
gets it from the renderer instead of from scrollback.

**2 — Working or idling.** One word, then its cause. You are **WORKING** if any of: a background
task or agent is running · a `/goal` is live · `cc-custody list --open` returns a row · the rung
is `🔧` and the fix is inside your own diff. You are **IDLING** if none of those hold and the
turn ended anyway — and idling with an open rung is a defect, not a status: drive it (§ Session
Close, "🔧 never yields"), or say who owns the part that is not yours.

**3 — Safe to close.** Answer the question, do not hedge it:

```
Good to close: yes — nothing of mine is open; follow-on: <filed ids | none>
Good to close: no  — <what remains + who owns it>
```

`yes` requires ALL of: the rung is `✅` (or `👤` with every step FILED, not prosed) · clean tree ·
landed verified **by content** (`git ls-tree origin/main -- <your paths>`, never by a commit
count — a sibling's rebase reads 0 and proves nothing) · your diff's gates ran green THIS turn ·
frozen-DoD remainder 0 · custody empty. Any one unknown ⇒ `no`, and say which one.

Then close on the six-slot shape (§ Session Close Protocol): rung glyph on line 1, the
`Good to close:` verdict on line **2** — never last, that position is what makes the operator
re-ask — and the one `▶ Run this:` command on line 3 if there is one.
