I couldn't do this task: the brief file doesn't exist, so I have no question to answer.

- `/tmp/o55-briefs/T2-recycle-goal.md` returned "File does not exist" when I tried to read it, and so did `/private/tmp/o55-briefs/T2-recycle-goal.md`.
- Listing `/tmp/o55-briefs/` was blocked because it's outside the directories this session is allowed to read, so I can't tell whether the brief is there under another name.
- Searching the repo snapshot for `*recycle*goal*` and `T2-*` found nothing, so the brief wasn't placed inside the repo either.

The brief is the whole task, and I didn't want to guess what "recycle-goal" is asking and risk answering the wrong question. I used 4 of the 25 tool calls and made no claims about the repo.

To go ahead, I need one of these:
1. Recreate the brief at `/tmp/o55-briefs/T2-recycle-goal.md` and add `/tmp/o55-briefs` to this session's allowed directories.
2. Paste the brief's text into the message.
3. Put the brief somewhere inside `/tmp/o55probe-repo-47c3317eb`.
