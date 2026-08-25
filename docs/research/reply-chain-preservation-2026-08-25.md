# Preserving a genuine, multi-level quoted chain on an ms365 reply

**Date:** 2026-08-25 · **Status:** mechanism verified against live MIME; shipped into
`hooks/enforce-email-formatting.py` RECIPE rules 1b/3/5 and `bin/ms365-reply-splice.py`.

## The one sentence

Create the reply draft with a short placeholder `Comment` so **Graph** builds the quoted chain,
then PATCH the draft replacing only the placeholder — never hand-author a quote block, because
a typed quote is an assertion and Graph's is the record.

## The bind

Graph offers two mutually exclusive things on a reply, and the reply that triggered this work
needed both:

| | Chain | Length | Styling |
|---|---|---|---|
| `Comment` | ✅ Graph appends the original's **full** chain, at whatever depth it already had | ❌ ~300 usable chars — Graph strips newlines above that | ❌ your text lands inside the **original sender's** carrier document |
| `Message.body` | ❌ **replaces** the auto-quote; threads but shows no history | ✅ arbitrary | ✅ full control |

The defect: a ~3,100-character reply in a live commercial dispute was built with `Message.body`
plus a hand-authored single-level quote. The operator rejected it on sight — *"it looks like the
reply to email was refabricated, we want the full reply chain history"* — and the draft was
deleted. The evidentiary value of that reply depended entirely on the chain being real.

## What the Vista Real precedent actually did

The working precedent is the reply sent 2026-08-12T22:47:26Z, subject
`RE: Pest Control Request - Submission Confirmation`, `ichris96@hotmail.com` →
`service.vistareal@irvinecompany.com`. Pulled via `get-mail-message-mime`:
`multipart/alternative`, `text/plain` 28,595 B + `text/html` 52,357 B, with `In-Reply-To` and a
five-entry `References` chain.

Its HTML, by offset:

| Offset | Content | Authored by |
|---|---|---|
| 97 | `<body>` → `<div style="font-family:Calibri,sans-serif;font-size:11pt">` — the new text, ~7.5 KB of real `<p>`/`<ol>`/`<b>` | **the model** |
| 7620 | plain `<hr>`, then `<p style="font-family:Calibri,…"><b>From:</b> … <b>Sent:</b> … <b>To:</b> … <b>Cc:</b> … <b>Subject:</b> …` | **the model** — one level, hand-typed |
| 7750+ | the original message's own `text/html`, wrappers stripped | Vista Real |
| 9484 | `--------------- Original Message ---------------` + headers | Salesforce mailer |
| 11096 | `<hr style="display:inline-block;width:98%" tabindex="-1">` + `<div id="divRplyFwdMsg">` | Outlook |
| 12692 | `<blockquote class="x_gmail_quote">` | Gmail |

**So the precedent hand-authored exactly ONE level and got levels 2–4 for free**, because they
were already inside the original's HTML. It is not a general method for producing an N-deep
chain — it is the one-level method, which happened to be enough because the message it replied
to already carried the history. That distinction is the whole finding, and it is why the same
approach failed on Montway (see *Limits*).

Note the `<hr>` attribute order here (`style` then `tabindex`) differs from the shape Graph emits
today. Never anchor a splice on the `<hr>`'s attributes.

## The mechanism that works

Verified end to end on a throwaway thread (a marketing email, since the Montway and Vista Real
threads were out of bounds; the draft was deleted afterwards).

**Step 1 — let Graph build the quote.** `create-reply-draft` with
`{"Comment": "PLACEHOLDER_SPLICE_PROBE_XYZZY"}`. The response's `body.content` came back
`contentType: "html"` in exactly this shape:

```html
<head>… the ORIGINAL's <style> blocks, all six of them …</head>
<body bgcolor="#d8d8d8" link="#000001" style="background-color:#d8d8d8">   ← the ORIGINAL's body attrs
PLACEHOLDER_SPLICE_PROBE_XYZZY
<hr tabindex="-1" style="display:inline-block; width:98%">
<div id="divRplyFwdMsg" dir="ltr"><font …><b>From:</b> … <b>Sent:</b> … <b>To:</b> … <b>Subject:</b> …</font></div>
<div>… the original's body …</div>
</body>
```

The create response already carries the full HTML, so **no MIME fetch is strictly required** —
but fetching it with `download-bytes-to-file` keeps a 30 KB body out of the model's context,
which is the better default.

**Step 2 — cut at Graph's own separator.** The stable anchor is `<div id="divRplyFwdMsg"`; walk
back to the `<hr>` immediately preceding it. Fallback for a plain-text original: a run of ≥20
underscores. `bin/ms365-reply-splice.py` does this and refuses if neither is present — a draft
built from `Message.body` has no auto-quote to splice onto, which is precisely the bug.

**Step 3 — PATCH.** `update-mail-message` with `{"body": {"contentType": "html", "content": …}}`.

**Verified on the resulting draft's MIME:**

- `In-Reply-To: <202625081816.6fk1dcw2jsbjj@bt.d.mailin.fr>` and `References:` — **both survive
  the PATCH**. Updating a draft's body does not detach it from the thread.
- `divRplyFwdMsg` present; the `<b>From:</b> / <b>Sent:</b> / <b>To:</b> / <b>Subject:</b>` block
  intact; exactly one `<hr>`.
- New text at offset 725, separator at 1358 — the new content is above the quote.
- Placeholder gone.
- The email-formatting hook **allowed** the PATCH.

### Is the quoted region really the original?

Not byte-identical — **Graph sanitises**. Original body inner HTML 27,211 B → quoted region
26,065 B. It strips MSO conditional comments (`<!--[if mso]>…`), drops some `<body>` attributes
(`text="#100D0D"`, `yahoo="fix"`), and wraps the content in a `<div>`.

This is Outlook's own reproduction — the same thing a human clicking Reply gets — not a
model's paraphrase. That is the property that matters: **nothing in the quoted region was
authored here.** Do not "fix" the sanitisation by substituting the raw original; that would
re-introduce hand-assembly.

## Styling inheritance — the answer, and it is worse than the hypothesis

The hypothesis was that `Comment` inherits the original's `<body>` styling. True, and confirmed:
the Montway order confirmation (`Your Vehicle Order #3414154`, 2026-08-24T23:33:30Z) carries

```html
<body … style="… color: red; font-family: Helvetica,Arial,sans-serif; …">
<style>body{… color:red; …}</style>     ← and again here
```

**Two things leak, not one, and the splice does not fix either by itself** — the carrier document
sits *above* the cut point, so it survives into the spliced result:

1. **`body{color:red}`** — your text inherits it.
2. **Copied `<style>` blocks with generic element selectors.** Graph copied all six of the test
   original's `<style>` blocks into the draft's `<head>`, including `p, h1, h2, h3, h4, ol, ul, li
   { margin: 0 }`. That silently collapses **your** paragraph spacing. This one was not
   hypothesised and is the more insidious of the two, because it produces a wall of text rather
   than an obviously wrong colour.

**The fix is to make your fragment self-defending, not to rewrite the carrier.** Neutralising the
carrier would change how the *quote* renders, which is the one thing that must not change. So:

- explicit `color:#000000` on your wrapper `<div>`;
- explicit inline `margin` on **every** block element you emit.

Inline styles beat both an inherited body colour and a copied stylesheet rule, including one
marked `!important` on a different selector. Verified: the spliced draft's MIME retained five
`color:#000000` declarations under a `<body>` whose own styling was the sender's, with the
vendor's `p{margin:0}` still in the head. `ms365-reply-splice.py` warns when a fragment omits
either defence.

## Recipients and the sender alias

Both are PATCHable on a `Comment`-created draft. A single `update-mail-message` carrying
`{"ccRecipients": […], "from": {…}}` was read back with both applied — `from` and `sender` both
became `ren.chris@outlook.com`, and the Cc landed.

**This corrects RECIPE rule 5.** It used to reason: *"`Comment` mode cannot set `from`, so a
ren.chris thread needs `Message.body`"* — and `Message.body` is what destroys the chain. The
create call indeed cannot set `from`, but the PATCH can, so **the alias requirement no longer
forces anyone into hand-building a chain.** Adding an escalation address such as a `feedback@`
alias works the same way.

## Attachments and inline images

The Montway confirmation has **16 remote `http` images and zero `cid:` inline attachments** — the
"inline logos" are hosted, not embedded. Splicing does not touch them: the `<img src="http…">`
tags ride through inside the quoted region and behave exactly as they would in any quoted reply,
subject to the recipient's remote-image blocking.

**Untested:** an original carrying true `cid:` inline attachments. The referenced parts live in
the original message's MIME, not the draft's, so a spliced quote plausibly renders them as broken
images. Nothing here establishes that either way — check it before relying on it.

## Hook interaction

`update-mail-message` is in `GATED_TOOLS` (formatting/density/alias arms) but **not** in
`REPLY_TOOLS`, so the quote guard does not fire on it. The splice flow therefore passes today
with no hook change, and the PATCH above confirmed that empirically.

**Decision: do not add `update-mail-message` to the quote guard.** A `PreToolUse` hook sees only
`tool_name` + `tool_input`; on a PATCH that is a `messageId` and a body. It cannot tell a reply
draft from a fresh one, so adding it would falsely deny every legitimate revision of a
non-reply draft. The guard's intent — catch the *reply-shaped* call that drops the chain — is
already met at the `create-reply-*` chokepoint, which is where the shape is knowable.

The residual gap, stated plainly: **a second PATCH that drops the quote is not caught.** Splice,
verify, and if you revise again, re-splice rather than PATCHing your text alone.

What did change in the hook is advice, not enforcement: RECIPE rules 1b/3/5 now describe the
splice, and the quote guard's deny message points at it instead of telling the model to
hand-append a quote from MIME — which was the advice that produced the rejected draft.

## Limits

- **Depth is a property of the message you reply to, not of this flow.** Graph quotes exactly one
  message; every deeper level comes from *that message's own HTML*. An auto-generated
  confirmation or receipt quotes nothing, so **replying to it can only ever yield one level.**
  The Montway case wanted confirmation ← hold instruction ← new reply; the confirmation does not
  contain the hold instruction, so no method reaching for it produces three levels. Reply to the
  message that actually carries the chain. `--assert-depth N` exists to make this fail loudly
  instead of shipping a thin chain that looks fine.
- **The PATCH executed in testing carried an abridged quote**, trimmed for transcription safety
  across the tool boundary. The helper's full 26,549-byte output was verified byte-identical on
  disk, and Graph is independently known to store a body this size — the placeholder draft
  round-tripped at 30,155 B. But the specific call that proved PATCH semantics did not carry the
  full quote; nothing observed suggests body size changes those semantics.
- **The helper cannot reach Graph.** The token lives in the MCP server's keychain and reading it
  was blocked, correctly. So the two Graph calls stay with the caller and the spliced body
  transits the tool boundary once. A helper that owned its own Graph credential could remove
  that round-trip entirely; that is the obvious next improvement and is not built.
- **The depth counter is a heuristic** — it counts `From:` header blocks (Outlook's `<b>From:</b>`
  and bare `From:` forms). A quoted message that mentions "From:" in prose would inflate it.
  It is a regression guard, not a parser.
- Verified on one mailbox, on the shapes observed 2026-08-25. Two `<hr>` attribute orders are
  already known; assume more exist and keep anchoring on the div id.

## Appendix — R4, pre-write freshness

A **separate requirement**, landed in the same file because it is the same guardrail surface.

**The failure.** A dispute letter was reviewed for 23 minutes — MIME parsed, indentation and font
verified twice — while the counterparty's automated acknowledgement, a written 24-hour commitment,
sat unread in the inbox. It had arrived 23 minutes before the send. The letter shipped asserting
*"I was not given a callback time"*: true of the phone call, false of the record. **Verifying the
artifact is not verifying the situation.**

**Where the gate stands.** Sends are human-executed (R1), so there is no send call left to gate.
The **draft write** is the last agent operation in an email flow. R4 therefore denies
`create-reply-draft`, `create-reply-all-draft`, `create-forward-draft`, `create-draft-email` and
`update-mail-message` unless the session has listed **received** mail within
`CC_MS365_FRESHNESS_MIN` (default 10) minutes.

**Why only a list of received mail counts — and why this is stricter than the brief.** In the final
20 minutes before that send the mailbox was queried **six times**, and every one was scoped
`isDraft eq true` or was a `get-mail-message-mime` on our own draft. A gate accepting "any mailbox
read" passes all six and prevents nothing.

The brief proposed counting *any read of a message that is not our own draft*. That is not
implementable here: a `PreToolUse` hook receives only `tool_name` + `tool_input`, so on
`get-mail-message` it has an opaque `messageId` and no way to tell whether that id is a draft this
session just created — and reading back your own draft is RECIPE step 4, i.e. **the read most
likely to be sitting in the window**. Counting it would reopen the exact hole. So single-message
reads do not satisfy R4; only a list that is not draft-scoped does. One call, impossible to satisfy
by accident.

**Deliberate non-gates.** `update-mail-message` is gated only when it carries a `body` — it is also
how a message gets flagged or marked read, and gating that is pure friction. Read tools are never
gated. The kill switch and `CC_MS365_FRESHNESS_MIN=0` both disable it. An unwritable marker
location **fails open**: a hook problem must never strand mail for five account dirs.

**The Graph call, and a gotcha worth the test that found it.**

```
list-mail-messages  filter: from/emailAddress/address eq '<counterparty>'
                            and receivedDateTime ge <ISO-8601 UTC when you started>
```

Adding `orderby: receivedDateTime desc` to that compound filter makes Graph return
**`400 InefficientFilter`**. Filter alone works; sort the handful of results yourself. This is in
the deny text and in RECIPE rule 6 because it was hit while verifying the remediation actually runs.

**Residual limits.** R4 proves a *read happened*, not that anything was *understood* — a session
can list received mail and ignore what it says. It is also per-session: a fresh session's first
draft is gated until it reads, which is the intended friction. And it cannot see reads performed
through `download-bytes-to-file`, which is not classifiable as inbound or draft.

## Files

- `bin/ms365-reply-splice.py` — the cut-and-rejoin step, with refusals.
- `tests/ms365-reply-splice.bats` — 13 cases, including a naive-splicer control that goes red if
  the refusals are ever gutted.
- `hooks/enforce-email-formatting.py` — RECIPE rules 1b/3/5/6, the quote-guard deny text, and R4.
- `tests/email-freshness-gate.bats` — 19 cases; the load-bearing pair is a draft-scoped read and an
  inbound read with otherwise identical payloads.
- `tests/email-reply-quote-guard.bats`, `tests/email-drafts-only-and-alias.bats` — each now stamps
  the R4 marker in `setup()` so its own subject is what it tests. Without that, their ALLOW
  controls go red and their DENY cases go green for the wrong reason.
