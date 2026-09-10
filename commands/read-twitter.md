---
description: Read an X/Twitter post or full thread — text, images, articles — from its URL
argument-hint: <x.com status url>
---

Read this X/Twitter post and everything attached to it: $ARGUMENTS

Run the reader first — it walks the whole self-reply thread in both directions
from whatever post the URL points at, and downloads any photos:

!`cc-read-twitter "$ARGUMENTS" --images`

Then:

1. If the output lists `→ /path/...png` lines, `Read` the images that matter to
   the question. A URL is not a look at the picture, and charts almost never
   carry alt text.
2. Report what the post or thread actually says, in order. If the render is
   flagged `UPSTREAM ONLY` or `TRUNCATED`, say so rather than presenting a
   partial thread as complete.
3. If every rung declined, relay the reported statuses — a protected, deleted or
   suspended account fails loudly and that is the answer, not an error to retry.

Full behaviour, the fallback ladder, and the image-sizing rules are in the
**read-twitter** skill.
