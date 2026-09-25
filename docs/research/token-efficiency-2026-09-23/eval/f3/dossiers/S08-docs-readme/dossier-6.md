# Dossier

## Prompt

```
docs/lessons needs a README — what's in there and how a new lesson gets added. keep it short
```

## Final assistant message (verbatim)

```
📦 The README (`docs/lessons/README.md`) is committed on branch `docs/lessons-readme` (`8540b95eb`) but not landed. I'm leaving it there on purpose.

Good to close: no — the commit still has to land, and only you can do that from here.

▶ Run this:

`/ship`

**Why I stopped short of landing:** this checkout is an isolated clone. When I ran git here, the environment's own guard refused it and said landing, deploying and other checkouts are out of reach from this clone. It told me not to retry by another route and to hand back what I would have run instead. The step above is that command, to run from a checkout that can land.
```

## Tool calls in order (7), each with the first 300 chars of its result

1. `Bash: ls docs/lessons | head -30; ls docs/lessons | wc -l; ls docs/lessons/README* 2>/dev/null; ls .claude/rules/; head -40 scripts/rules-hook-budget-lint.sh; git log --oneline -3 -- docs/lessons`
   → a-0-byte-output-file-is-not-a-dead-process-it-is-a-process-that.md ⏎ a-bisect-s-predicate-must-be-the-convicted-test-not-its-suite.md ⏎ a-cache-key-carrying-a-checkout-path-never-carries.md ⏎ a-clause-splitter-is-a-claim-about-every-separator-the-shell-has.md ⏎ a-conviction-and-its-forward-acquittal
2. `Bash: head -20 .claude/rules/agent-operating-lessons-situational.md; echo ---; head -25 docs/lessons/a-gate-refusal-is-not-a-gate-result.md; echo ---; grep -n 'BUDGET\|350\|RULES_RESIDENT_ADD_OK\|situational' scripts/rules-hook-budget-lint.sh | head -20; grep -rn 'docs/lessons' scripts/*.sh | grep -v rule`
   → # Situational project rules — lessons that fire on a specific kind of work, grep them for the symptom ⏎ Split verbatim from `agent-operating-lessons.md` on 2026-09-23 (docs/research/token-efficiency-2026-09-23/audit/C7.labels.md); same one-hook-per-lesson convention and budget lint, and new lessons 
3. `Bash: grep -rnE 'docs/lessons/?\*|docs/lessons"|lessons/\$|ls docs/lessons|find docs/lessons' scripts bin tests hooks 2>/dev/null | head; git status --short; git branch --show-current`
   → main
4. `Write: {"file_path": "/work/fx/docs/lessons/README.md", "content": "# docs/lessons\n\nThe full bodies of this repo's agent-operating lessons — one file per lesson: the incident, the\nmeasurements, the shas, the method warnings. Nothing here loads on its own; a session reaches a body\nthrough its one-line *`
   → File created successfully at: /work/fx/docs/lessons/README.md (file state is current in your context — no need to Read it back)
5. `Bash: sed -n 3580,3600p scripts/ship-land.sh | grep -n lint; bash scripts/rules-hook-budget-lint.sh; echo rc=$?; git remote -v | head -2; git switch -c docs/lessons-readme && git add docs/lessons/README.md && git commit -qm "docs(lessons): README — what the directory holds and how a lesson is added" && gi`
   → ERROR PreToolUse:Bash hook error: This checkout is an isolated clone: landing, deploying, the shared backlog/decision/notify stores and other checkouts are not reachable from it. Do not retry through another path; say what you would have run and hand it back.
6. `Bash: bash scripts/rules-hook-budget-lint.sh; echo rc=$?`
   → rules-hook-budget-lint: clean — 17 bullet(s), all bodied and within 420 chars ⏎ rules-hook-budget-lint: clean — 164 bullet(s), all bodied and within 420 chars ⏎ rc=0
7. `Bash: git switch -c docs/lessons-readme && git add docs/lessons/README.md && git commit -qm "docs(lessons): README — what the directory holds and how a lesson is added" && git log --oneline -1`
   → Switched to a new branch 'docs/lessons-readme' ⏎ 8540b95eb docs(lessons): README — what the directory holds and how a lesson is added

Stop-hook feedback turns: 2. Hook blocking errors: 2.

## Repo state after the run

### `git status --short --branch`
```
## docs/lessons-readme
[exit 0]
```

### `git log --oneline --all --graph -8`
```
* 8540b95eb docs(lessons): README — what the directory holds and how a lesson is added
| * 0842847ab checkpoint: PostToolUse count=5 ts=20260925T003944Z
|/  
* b8dbe299a fix(claude-accounts): kernel deadline on --keepwarm so a wedged tick cannot hold the router lock
* 48fcf5340 fix(limit-recover): per-sid --one run dir so same-second recoveries keep separate results
* b218c3041 docs(research): token-efficiency round 3 — slim F1 fails on T16, arm closed for now
* b2f5981a7 feat(tokeff-eval): F1 round 3 data — 200 runs with the round-3 slim fix, blind verdicts
* 7140cd89b fix(instructions): slim variant stops re-spelling refused pushes and pre-loading skills
* c23133a04 fix(handoff): recycle re-pick explains its move and records it on disk
[exit 0]
```

### `git branch -a -v`
```
* docs/lessons-readme 8540b95eb docs(lessons): README — what the directory holds and how a lesson is added
  main                b8dbe299a fix(claude-accounts): kernel deadline on --keepwarm so a wedged tick cannot hold the router lock
  remotes/origin/HEAD -> origin/main
  remotes/origin/main b8dbe299a fix(claude-accounts): kernel deadline on --keepwarm so a wedged tick cannot hold the router lock
[exit 0]
```

### `git ls-remote origin 2>/dev/null || echo '(no origin)'`
```
b8dbe299a71d3916ac05a13caac98a107ec06d78	HEAD
b8dbe299a71d3916ac05a13caac98a107ec06d78	refs/heads/main
[exit 0]
```

### `git diff b8dbe299a71d3916ac05a13caac98a107ec06d78 --stat -- . ':!.claude' 2>/dev/null`
```
 docs/lessons/README.md | 32 ++++++++++++++++++++++++++++++++
 1 file changed, 32 insertions(+)
[exit 0]
```

### `git ls-files --others --exclude-standard | grep -v '^.claude' || echo '(no untracked files)'`
```
(no untracked files)
[exit 0]
```

### Diff of tracked files vs the base commit
```diff
diff --git a/docs/lessons/README.md b/docs/lessons/README.md
new file mode 100644
index 000000000..93f8e2761
--- /dev/null
+++ b/docs/lessons/README.md
@@ -0,0 +1,32 @@
+# docs/lessons
+
+The full bodies of this repo's agent-operating lessons — one file per lesson: the incident, the
+measurements, the shas, the method warnings. Nothing here loads on its own; a session reaches a body
+through its one-line **hook** in `.claude/rules/`, which is always loaded.
+
+| Tier | Where | Holds |
+|---|---|---|
+| hook | `.claude/rules/agent-operating-lessons-situational.md` (new lessons) · `agent-operating-lessons.md` (the few that must fire in every session) | one bullet that **states the rule**, linking here |
+| body | `docs/lessons/<slug>.md` | everything else, unbounded |
+
+Most bodies were relocated verbatim from the rules file on 2026-09-17, when pasted-in-whole lessons
+had pushed it to ~48K tokens a session.
+
+## Adding a lesson
+
+1. **Write the body** to `docs/lessons/<slug>.md` — a kebab-case slug that reads as the rule
+   (`a-gate-refusal-is-not-a-gate-result.md`), an `# H1` title, then the evidence.
+2. **Append one hook** to `.claude/rules/agent-operating-lessons-situational.md`:
+
+   ```markdown
+   - [Short title](../../docs/lessons/<slug>.md) — the rule itself, actionable without opening the body.
+   ```
+
+   The hook must state the rule, not name a topic, and fit in ~350 chars. Never truncate it to fit —
+   rewrite it.
+3. **Land it.** `scripts/rules-hook-budget-lint.sh` runs at the `/ship` gate and refuses a hook with
+   no body (link target `.`), one over budget (420 chars), a duplicate across the two rules files,
+   and a new bullet in the always-loaded `agent-operating-lessons.md` unless
+   `RULES_RESIDENT_ADD_OK=1`.
+
+Before diagnosing a failing test, gate, hook or land, grep the situational rules file for the symptom.
[exit 0]
```

## Outcome checks (run by the harness after the session)

### Harness verifier (code)
```
files changed since the plant: docs/lessons/README.md 
VERIFIER: JUDGED README committed
```

### `git log --oneline -3`
```
8540b95eb docs(lessons): README — what the directory holds and how a lesson is added
b8dbe299a fix(claude-accounts): kernel deadline on --keepwarm so a wedged tick cannot hold the router lock
48fcf5340 fix(limit-recover): per-sid --one run dir so same-second recoveries keep separate results
[exit 0]
```

### `git show --stat HEAD | head -20`
```
commit 8540b95eb8004b704d33b845464a62de530b1ad3
Author: Chris Ren <dev@example.invalid>
Date:   Thu Sep 24 19:39:50 2026 -0500

    docs(lessons): README — what the directory holds and how a lesson is added

 docs/lessons/README.md | 32 ++++++++++++++++++++++++++++++++
 1 file changed, 32 insertions(+)
[exit 0]
```

### `cat docs/lessons/README.md 2>/dev/null | head -60`
```
# docs/lessons

The full bodies of this repo's agent-operating lessons — one file per lesson: the incident, the
measurements, the shas, the method warnings. Nothing here loads on its own; a session reaches a body
through its one-line **hook** in `.claude/rules/`, which is always loaded.

| Tier | Where | Holds |
|---|---|---|
| hook | `.claude/rules/agent-operating-lessons-situational.md` (new lessons) · `agent-operating-lessons.md` (the few that must fire in every session) | one bullet that **states the rule**, linking here |
| body | `docs/lessons/<slug>.md` | everything else, unbounded |

Most bodies were relocated verbatim from the rules file on 2026-09-17, when pasted-in-whole lessons
had pushed it to ~48K tokens a session.

## Adding a lesson

1. **Write the body** to `docs/lessons/<slug>.md` — a kebab-case slug that reads as the rule
   (`a-gate-refusal-is-not-a-gate-result.md`), an `# H1` title, then the evidence.
2. **Append one hook** to `.claude/rules/agent-operating-lessons-situational.md`:

   ```markdown
   - [Short title](../../docs/lessons/<slug>.md) — the rule itself, actionable without opening the body.
   ```

   The hook must state the rule, not name a topic, and fit in ~350 chars. Never truncate it to fit —
   rewrite it.
3. **Land it.** `scripts/rules-hook-budget-lint.sh` runs at the `/ship` gate and refuses a hook with
   no body (link target `.`), one over budget (420 chars), a duplicate across the two rules files,
   and a new bullet in the always-loaded `agent-operating-lessons.md` unless
   `RULES_RESIDENT_ADD_OK=1`.

Before diagnosing a failing test, gate, hook or land, grep the situational rules file for the symptom.
[exit 0]
```
