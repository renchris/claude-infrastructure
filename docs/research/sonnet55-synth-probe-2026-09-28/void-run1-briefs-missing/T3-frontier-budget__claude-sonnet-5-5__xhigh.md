# Brief not found: no answer produced

I couldn't read the brief, so I have no task to synthesize. Your instructions say the brief "is the whole task", and I won't guess at its contents.

## What I tried
- `Read /tmp/o55-briefs/T3-frontier-budget.md` returned "File does not exist."
- `Read /private/tmp/o55-briefs/T3-frontier-budget.md` returned the same error. On macOS `/tmp` resolves to `/private/tmp`, so this is the same location.
- `ls /tmp/o55-briefs/` was blocked. Only `/private/tmp/o55probe-repo-47c3317eb` and `/tmp/o55probe-repo-47c3317eb` are allowed, and your rules also confine me to the repo path.
- `find` inside the repo for `*T3*`, `*frontier*` and `*brief*` found no brief. The only brief-like path is `tests/fixtures/codex-probe/briefs`, and it's an empty directory.
- I used 5 tool calls, well under the 25-call limit.

## What the repo has
`find` matched four directories whose names contain "frontier": `skills/frontier-run`, `skills/frontier-hole`, `skills/frontier-campaign` and `skills/frontier-routing`. I did not open any of them. They might relate to a "frontier budget" topic, but that's only a guess from the filenames. I have no citations because I read no repo lines.

## What I need
Any one of these would let me continue:
1. Put the brief at a path inside `/tmp/o55probe-repo-47c3317eb`, or paste its text into the conversation.
2. Confirm that `/tmp/o55-briefs/T3-frontier-budget.md` should exist, and re-run once it has been written. It may not have been created before this worker started.
3. Tell me explicitly to work from the `skills/frontier-*` directories. Then I'd read them and answer a question about frontier budgeting, but you'd need to state the question.
