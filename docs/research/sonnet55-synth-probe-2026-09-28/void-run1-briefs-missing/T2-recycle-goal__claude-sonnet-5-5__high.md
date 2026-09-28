I couldn't complete this task because the brief isn't readable, and I haven't done any analysis.

- `Read` on `/tmp/o55-briefs/T2-recycle-goal.md` returned "File does not exist".
- `ls` on `/tmp/o55-briefs/` was blocked. This session only allows listing under `/private/tmp/o55probe-repo-47c3317eb` and `/tmp/o55probe-repo-47c3317eb`.

The brief is the whole task, so I don't know what question to answer. I haven't guessed at it or searched the repo for something plausible. Anything I wrote would be invented and not tied to the brief.

To unblock, any one of these would work:
- Put the brief at a path inside `/tmp/o55probe-repo-47c3317eb`, or allow `/tmp/o55-briefs` as a working directory.
- Check that `T2-recycle-goal.md` exists at that exact path, since the file may not have been created.
- Paste the brief text into the conversation.

I'll then do the work within the 25-tool-call bound and cite `path:line` for every claim.
