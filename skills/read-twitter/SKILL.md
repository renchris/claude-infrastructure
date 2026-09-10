---
name: read-twitter
description: Read an X/Twitter post — or an entire self-reply thread — with its images, from the URL alone. Use when handed an x.com or twitter.com status link, asked to "read this tweet/thread/X post", to unroll a thread, to summarise or quote what someone posted, to look at a chart or screenshot attached to a post, or to read an X Article. Covers why the built-in WebFetch tool cannot do this (x.com answers it HTTP 402), the three-rung fallback ladder and how each rung is validated by CONTENT rather than status code, how a thread is walked in BOTH directions from any member post, and how an attached image actually gets in front of the model's eyes rather than staying a URL. NOT for posting, replying, liking or any write action, and NOT for reading a protected or logged-in-only account.
allowed-tools: Bash, Read
---

# Reading X/Twitter from a URL

## The one command

```
cc-read-twitter <url-or-id> [--images [DIR]]
```

That is the whole interface for the common case. Hand it any post in a thread —
root, middle, or last — and it prints the **entire** thread as compact markdown.

```
cc-read-twitter https://x.com/AnthropicAI/status/2070528969523499460
cc-read-twitter https://x.com/user/status/123 --images     # then Read each printed path
```

## Why not just WebFetch

`WebFetch` on an x.com status returns **HTTP 402 Payment Required** — measured
2026-09-09. `curl` on the same URL returns 200 and 394 KB of SPA shell with no
post text and no Open Graph tags. There is no built-in tool that reads x.com.
Do not spend a turn rediscovering this.

## What the tool does

| | |
|---|---|
| Thread walking | **Both directions from any member.** The `replying_to_status` pointer only walks *up*, and the post a user links is usually neither the root nor the end. On the test thread the linked post's own stated parent was **three hops below the true root**, with a further self-reply *underneath* the linked post. Chasing `replying_to_status` by hand misses both ends. |
| Long posts | Full note-tweet body. A truncated source is flagged inline, never rendered as if complete. |
| Images | URL + author alt text; `--images` downloads them so they can be `Read`. |
| X Articles | The full article body, headings, lists and inline figures with captions. |
| Video | The direct `.mp4`, capped at 720p (the top rung of the ladder is 4K/25 Mbps — ~120 MB for 38 s). Hand it to the **video-understanding** skill. |
| Also | quote-tweets, polls, community notes, engagement counts. |

## Seeing an image, rather than citing its URL

A URL in the output is not a look at the picture. To actually see one:

```
cc-read-twitter <url> --images        # prints "→ /tmp/x-<id>/<id>-1.png" per photo
```

then `Read` that path. This is verified end to end: a downloaded chart came back
as a rendered image with its title, both panels, axis ticks, legend and bar
values all legible.

- **Size is already right — do not "optimise" it.** The tool fetches
  `?name=medium` (1200 px). `orig` is ~41 % more tokens for zero readable gain,
  because the vision pipeline downscales to ~1568 px regardless.
- **Never `sips -Z` an image before reading it.** On the test image that *grew*
  the file 3.5× (colormap → truecolour re-encode) for identical token cost.
- **Read alt text first.** It is free and roughly 7× cheaper than a vision read
  — but it is absent more often than you would expect, and **charts almost never
  carry it**, which is exactly where vision is needed. Never treat its absence
  as "no image content".
- If a first read is illegible (dense code screenshot, small-print table), re-run
  with `CC_RT_IMG_SIZE=orig`.
- A thread can carry 20 images. Read the ones the question needs, not all of them.

## The ladder, and why every rung is checked by content

Sources are tried in order and each is validated by **reading a field out of the
payload**, never by its status code:

1. **`api.fxtwitter.com/2/thread/<id>`** — one unauthenticated request, both
   directions, alt text, note tweets, article bodies, video ladder. It proxies
   X's private GraphQL with pinned query ids, so an X-side rotation breaks it
   until upstream recaptures (status: `status.fxtwitter.com`). MIT, self-hostable.
2. **`cdn.syndication.twimg.com/tweet-result`** — X's *own* embed CDN, so it
   survives a third-party outage. Needs a computed token; walks **upstream only**
   (its `parent` is exactly one hop) and **silently truncates long posts**. Both
   limits are printed when this rung is used.
3. **`r.jina.ai`** — different origin entirely, degraded output (no post
   boundaries). Returned 403 when last measured; kept as a live escape hatch.

🚨 **A 200 is not a success here.** Mid-session on 2026-09-09 the syndication
endpoint changed under us and began answering **HTTP 200 with a two-byte `{}`**
to tokenless requests. Any check keyed on the status code reads that as healthy
and hands back an empty post. If you extend this tool, validate a *field*.

## Flags

`--single` one post only · `--images [DIR]` download photos · `--json`
normalised JSON · `--raw` the winning source's payload · `--max N` cap posts ·
`--source fxtwitter|syndication|jina` force one rung, no fallback.

Env: `CC_RT_IMG_SIZE` (default `medium`), `CC_RT_TIMEOUT` (20),
`CC_RT_MAX_VIDEO_HEIGHT` (720).

## Limits worth stating rather than discovering

- **Protected, deleted and suspended accounts are unreadable** by every rung.
  The failure is loud (all three rungs report their status), not a blank post.
- A thread where the author **interleaves replies to other people** may render
  those interleavings; the tool reports what the upstream thread endpoint
  returns and does not re-filter by author.
- **A thread that continues inside a quote-tweet** is shown as a quote, not
  followed. Re-run on the quoted URL to continue.
- Article output is unbounded — a long article is genuinely long (~16 KB on the
  test fixture). Use `--max` or read the first post only if that matters.
- This is **read-only by construction**. There is no auth, no cookie, and no
  write path anywhere in the tool.
