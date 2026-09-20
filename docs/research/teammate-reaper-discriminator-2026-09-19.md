# The duplicated teammate discriminator was a redundant pre-filter, not a weaker check

**2026-09-19 · `hooks/teammate-auto-shutdown.sh:320` · `hooks/lib/agent-identity.sh:53` ·
`tests/operator-surface-scope.bats:269` · resolves decision packet `73329c873224`**

## The finding, and the wrong turn that preceded it

`tests/operator-surface-scope.bats` — *"LINT: the discriminator exists in exactly ONE place"* — was
red on trunk (measured with any candidate diff stashed: 20 ok / 1 not ok), naming
`hooks/teammate-auto-shutdown.sh` from `3cdaa2552`. It blocks any land touching an operator-surface
hook, so it was blocking lands fleet-wide rather than only the one that found it.

🚨 **My first read of this was WRONG, and it is recorded here because the error is the instructive
part.** I compared the copy's three-flag line against the canonical one, saw that
`lib/agent-identity.sh` follows its three-flag test with a CROSS-FIELD CONSISTENCY tail (whose own
comment records a measured false positive — bare co-presence is satisfiable by PROSE, because `ps`
flattens argv and a brief that merely DISCUSSES the flags carries all three as apparent words), and
concluded the copy omitted that hardening. On that reading the copy was a *weaker* predicate driving
a *reaper*, which I was one step from escalating to the operator as a safety decision.

It is false. Eight lines further down, the copy does exactly the same consistency test:

```awk
at = index(id, "@")
if (at > 1 && substr(id, 1, at - 1) == nm && substr(id, at + 1) == tm && nm == who) { print p; exit }
```

**The lesson: a duplicated predicate is only "weaker" if you read to the END of both copies.** I
diffed the line the lint named and stopped there, because the lint names a LINE. The lint's subject
is a regex; the semantics live in the block around it.

## The actual fix, and why it needed no ruling

With the consistency test present, the three-flag line above it is **pure redundancy**: when the
flags are absent, `id`/`nm`/`tm` stay empty, `index("", "@")` is 0, and `at > 1` already rejects the
row. Deleting it is semantically inert, removes the second copy of the discriminator regex, and
restores the single definition the lint exists to enforce.

Measured after deletion: `tests/teammate-auto-shutdown.bats` **67/67 green** (behaviour unchanged,
as the redundancy argument predicts) and `tests/operator-surface-scope.bats` **21/21 green**.

So packet `73329c873224` was framed correctly all along — it is a duplication question, not a
safety one — and it dissolves rather than needing a ruling: the copy the author deliberately wrote
is still there in full, minus a line that never did anything.

## Method note: `git stash` on a clean tree is a silent no-op

While A/B-ing this red against trunk I ran `git stash` with an already-clean tree. It saved nothing
and printed nothing that stopped me. The later `git stash pop` therefore popped **another
session's** parked stash into this worktree — the stash stack is per-repository and shared across
every linked worktree — conflicting on a file I had never touched. No work was lost (`pop` keeps the
entry on conflict, and the file was restored byte-identical to trunk), but the near-miss is the
point: **to A/B a working tree against trunk, use a second worktree or `git stash push -- <paths>`
with explicit paths, never a bare `git stash`/`pop` pair in a repo other sessions share.**
