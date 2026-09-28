I couldn't complete this task because I couldn't read the brief.

- `Read /tmp/o55-briefs/T2-recycle-goal.md` returned "File does not exist."
- `ls` on `/tmp/o55-briefs/` was blocked. This session only allows listing `/private/tmp/o55probe-repo-47c3317eb` and `/tmp/o55probe-repo-47c3317eb`, and the brief sits outside both.
- A search of the repo for any file with "recycle" in its name found nothing, so there is no copy of the brief inside the snapshot.

The brief is the whole task, and I don't know the question. Guessing a "recycle goal" from the repo would mean inventing findings and citations, so I haven't researched or cited anything. I used 4 of my 25 tool calls.

To unblock this, do one of these:
1. Put the brief inside `/tmp/o55probe-repo-47c3317eb`, or add `/tmp/o55-briefs` to the session's allowed directories, and re-run.
2. Paste the brief's text into the conversation.
3. Confirm the correct path, in case the filename or location is different.

Once I can read it, I'll do the research and write the cited answer.
