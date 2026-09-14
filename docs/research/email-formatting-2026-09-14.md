# Agent-drafted email: the formatting standard

**Date:** 2026-09-14 · **Repo:** claude-infrastructure · **Status:** landed (hook + tooling + tests)

The operator's words that opened this: *"We need a dedicated research session to improve our email
formatting. We have zero."* The evidence was a live draft — a reply to a ByteDance partnership
approach — that was one run-on paragraph, rendered grey rather than black, and carried no
signature. This document is the root cause of all three, the standard that replaces them, and the
alternatives that were rejected with the measurement that rejected them.

---

## 1. THE STANDARD — the one page an agent follows

**Build the body with the tool. Pass it as the `Comment`. Never hand-write the markup.**

```
▶ Run this:

`$HOME/.claude/bin/ms365-compose-body.py --text-file reply.txt --signature chris-reso --out body.html`
```

Then `create-reply-draft` / `create-reply-all-draft` with the contents of `body.html` as
`body.Comment`. That is the whole mechanism: **one API call**, Graph appends its own quoted chain
at the original's full depth, and no part of the original ever passes through the model.

`reply.txt` is PROSE, not markup — a blank line between paragraphs, `- ` for a bullet. The tool
emits the HTML.

### Structure of the message itself

| # | Element | Rule |
|---|---|---|
| 1 | Subject | Don't touch it. Reply; let the client prepend `Re:`. Editing it forks the thread in both Gmail and Outlook. |
| 2 | Greeting | Present, own line, name included. `Hi <First>,`. No greeting is the single most-disliked opening measured (53%, Perkbox n=1,928). |
| 3 | Anchor | ONE sentence that could only have been written to *this* message — name the thing they proposed. It replaces the pleasantry, it does not accompany it. |
| 4 | Body | 1–3 paragraphs, one idea each, 2–4 sentences. **The first body paragraph carries the answer, not the reasoning.** |
| 5 | The ask | Exactly one, own paragraph, concrete. |
| 6 | Sign-off | One line, sentence case, comma. `Best regards,` |
| 7 | Name | Own line under the sign-off. |
| 8 | Signature | 3–5 lines: name, company, one reachable channel. No quote, no logo, no invented title. |
| 9 | Quote | Below everything, untouched. Graph writes it; you never do. |

**The load-bearing rule: a senior professional's reply is answer-first.** What reads as junior
reads that way because it defers the answer behind context, gratitude or self-introduction.

Not in the anatomy, deliberately: no *"I hope this email finds you well"* (it spends the one
sentence a stranger actually reads); no self-introduction unless the inbound shows they need one;
no bullet list unless there are ≥3 genuinely parallel items; no PS.

### Typography

The tool's defaults are **measured, not chosen from documentation** — read out of the MIME of a
message this operator's own Outlook composed and sent (2026-09-02):

```html
<div style="font-family: Calibri, Helvetica, sans-serif; font-size: 12pt; color: rgb(0, 0, 0);"
     class="elementToProof">
```

so a reply the agent drafts is typographically indistinguishable from one he typed. The tool emits
the same three declarations (in hex rather than `rgb()`, see below):

```css
font-family: Calibri,Helvetica,sans-serif;
font-size:   12pt;
color:       #000000;   background-color: #ffffff;
/* on every block element, not just the wrapper. margin:0 0 12pt 0 on each <p>. */
```

**Two things the obvious, documentation-led answer gets wrong**, and the first draft of this
standard got both:

- **12pt, not 11pt.** The brief said 11pt and so did my first version. A survey of 25 real
  Outlook-composed messages found **182 declarations of 12pt against 6 of 11pt**, and this mailbox
  agrees. 11pt is a real number in the same file — it is the size Outlook uses for the **quote
  header it generates** (`<font face="Calibri, sans-serif" color="#000000" style="font-size:11pt">`),
  which is exactly what makes reading it off a reply draft an easy and wrong inference.
- **Calibri, not Aptos.** Aptos is the Microsoft 365 default since 2024, and a documentation-led
  choice lands there — my first version shipped an Aptos-first stack. This **consumer**
  Outlook.com mailbox still composes in Calibri. An M365 mailbox (`chris@reso.gl`) will differ,
  which is why the stack is **per-identity** in the signature file rather than global.
  Microsoft's own support page, meanwhile, still says "the default font is Calibri in black" —
  stale prose sitting beside a still-correct value.

- **The family is client-dependent; the SIZE and COLOUR are not.** A second sent message from the
  same mailbox, composed on **Outlook mobile**, reads
  `font-family: Aptos, Aptos_MSFontService, -apple-system, Roboto, Arial, Helvetica, sans-serif;
  font-size: 12pt; color: rgb(0, 0, 0);` — a different family from the web client's Calibri, with
  **identical 12pt and identical black**. So there is no single family that matches everything this
  operator sends, and 12pt/`#000000` are the load-bearing constants. The default is Calibri-first
  because that is what the **web** client composes and the web client is where drafts get reviewed;
  the per-identity `font` key is how the other cases are handled rather than argued about.
- **Never add `@font-face` to "make Aptos work".** An element using an `@font-face` font ignores
  the whole stack and falls back to **Times New Roman** in Outlook Windows 2007-2016. It is the
  highest-severity failure in this area and it is triggered by the obvious fix.
- **pt, not px.** Outlook states its own sizes in pt; mixing pt above the separator with px below
  it is visibly inconsistent inside one message.
- **An explicit colour, on every block.** See §2 — this is the grey defect.
- **Inline on every element, never a `<style>` block.** See §3 — the fragment lands inside a
  document someone else wrote. (Outlook's own compose emits a
  `<style>P{margin-top:0;margin-bottom:0}</style>` reset and spaces paragraphs with empty `<div>`s;
  a fragment cannot rely on a `<style>` block, so explicit inline margins do the same job more
  robustly.)
- **`margin` only. NEVER `padding` on a `<div>`, `<p>` or `<ul>`.** Classic Outlook renders through
  Word, where padding is supported on **table cells only** — a padded list silently loses its
  indent there and nowhere else, so it looks correct in every client you can easily check. A
  horizontal rule must be an `<hr>`, not a `border-top`, for the same reason.
- **Hex colours, never whitespace-syntax `rgb()`.** A `style` attribute containing
  `rgb(31 35 41)` has **the whole attribute stripped** by Gmail, and a modern token
  (`oklch()`, `lab()`) removes *every* inline style on that element. `rgb(31 35 41)` and
  `rgb(31,35,41)` are the difference between a styled fragment and an unstyled one, with no
  warning. The tool emits hex; a test pins it.

Both of these are pinned by `tests/ms365-compose-body.bats`, the padding one with a mutant,
because each is invisible in the clients a session can actually render.

---

## 2. ROOT CAUSE — all three defects, measured on the live thread

Measured by creating a real reply draft on the actual ByteDance message
(`lijiajun.07@bytedance.com`, 2026-09-01) and reading the draft's own MIME back off disk.

**What Graph actually produces from a `Comment`:**

```html
<html><head><meta http-equiv="Content-Type" content="text/html; charset=utf-8"></head><body>
CCPLACEHOLDER7X2Q
<hr tabindex="-1" style="display:inline-block; width:98%">
<div id="divRplyFwdMsg" dir="ltr"><font face="Calibri, sans-serif" color="#000000" style="font-size:11pt">
<b>From:</b> Harry Li &lt;lijiajun.07@bytedance.com&gt;<br>…
```

Read that carefully, because all three defects are visible in it:

**(a) GREY, NOT BLACK.** The `<body>` is **bare** — no attributes, no `<style>`, no font. Our text
is a **naked text node** inside it. Graph's own quote header, on the very next line, is explicitly
`color="#000000"` Calibri 11pt. So the reply inherits whatever the *reading client* defaults to
while the quoted chain below it is explicitly black — which is precisely "ours looks grey, theirs
looks black". Rendered locally the bare body also falls back to a **serif** face, because nothing
names one.

*This refutes the hypothesis in the brief.* The suspected cause was the Lark carrier document's
inline `color: rgb(31,35,41)` spans leaking into our text. They do not: the original ByteDance mail
has **no `<html>`, no `<head>`, no `<body>` and no `<style>` block at all** — it is a bare Lark
fragment whose every style sits inline on its own spans (43 instances of `color: rgb(31,35,41)`,
61 `font-family` declarations). Graph wraps it in a *clean* `<html><body>`. Nothing leaks. The grey
is an **absence of styling on our side**, not an inheritance from theirs.

The carrier-leak mechanism is real — it was measured on a different thread in 2026-08 where a
vendor template carried `body{color:red}` and `p{margin:0}` — but it is not what happened here.
The cure is the same either way, which is why it went unnoticed: state your own styling.

**(b) ONE RUN-ON PARAGRAPH.** Graph strips newlines out of a `Comment`. Prose passed as prose
arrives with no breaks at all. See §3 for what does survive.

**(c) NO SIGNATURE.** Graph never adds one. The ms365 server's own tool description says it:
*"Signatures are added by the Outlook client only, not via Graph."* And there is no Graph API to
read the user's Outlook signature — see §5.

### Before / after

Both rendered from real draft HTML in headless Chrome at 980px:

| | |
|---|---|
| `render-before.html` | greeting, body, ask and sign-off fused into one serif paragraph; no signature |
| `render-after.html` | six paragraphs, bullet list, sans-serif, black, signature block, Graph's quote below the rule byte-identical |

---

## 3. THE MECHANISM — the finding that dissolves the problem

> **Microsoft Graph strips NEWLINES from a reply `Comment`. It does not strip MARKUP.**

Measured 2026-09-14. A `Comment` of

```html
<div style="color:#C00000"><p>para one</p><p>para two here</p></div>
```

came back in the draft's own MIME as, byte for byte:

```html
<body>
<div style="color:#C00000">
<p>para one</p>
<p>para two here</p>
</div>
<hr tabindex="-1" style="display:inline-block; width:98%"><div id="divRplyFwdMsg" …>
```

Inserted **verbatim**, above Graph's own quote, at the original's full depth.

**Why this matters so much.** The previous recipe had read the first fact and inferred the second.
Because a long formatted reply was believed impossible in `Comment`, every such reply was pushed
onto one of two bad paths:

- `Message.body` — which **replaces Graph's auto-quote**, producing a reply that threads correctly
  but arrives with no visible history. That cost a real defect on 2026-08-24.
- A four-step placeholder splice — create a placeholder draft, download its MIME, cut at
  `divRplyFwdMsg`, PATCH the result back. It works, but the PATCH puts the whole ~38 KB spliced
  body back through the model's own tool call. That is what made the ByteDance reply get written
  under a 300-character cap in the first place.

Neither is necessary. The HTML-Comment path is one call and strictly safer than the splice, for a
reason that is not obvious: **it never reads the quoted region back.** Graph filters unsafe HTML on
*read* by default, so the splice's read-then-write round trip permanently replaces the stored quote
with its sanitised form. A path that never reads the quote cannot lose anything in it.

### The 300-character cap was ours, not Graph's

No such limit is documented on any Microsoft Learn reference page. The number was our own hook
constant (`MIN_LEN`) doing double duty. Two plausible origins for the folklore, both cited in the
research: `bodyPreview` is documented at exactly **255** characters, and there is a documented known
issue where the `comment` parameter *"isn't part of the body of the response message draft"*, which
makes a comment *look* absent. Neither is a length cap.

### Lark publishes its own mail-HTML spec, and it documents this exact failure

`larksuite/cli`'s `lark-mail` reference shows Lark's compose-path lint rewriting `<p>正文</p>` into
`<div style="margin-top:4px;margin-bottom:4px;line-height:1.6"><div dir="auto" style="font-size:14px">…`
— your margins and font-size replaced, your `<p>` gone. It also confirms `rgb(31,35,41)` as Lark's
documented body-text token (which is exactly what the ByteDance original is full of), and documents
an inline-style property whitelist that silently deletes non-members. That is Lark's *outbound*
path, which is why the original looks the way it does; whether Lark's reader applies the same
treatment to *our* mail is untested. `lark-cli mail +lint-html --body-file <f> --show-lint-details`
is read-only, makes no API call, and returns `cleaned_html` — it would settle it in one command.

**Honest limit on this claim:** "no documented cap" is not the same as "measured unlimited". The
largest `Comment` exercised here is ~3 KB. The governing documented limit is the global **4 MB**
Graph write cap, which a 38 KB body uses 0.9% of.

---

## 4. WHAT THE GUARD NOW ENFORCES

`hooks/enforce-email-formatting.py`, unchanged in its safety semantics (no compose-and-send,
turn-gated send, alias continuity, freshness):

| Body shape | Verdict | Why |
|---|---|---|
| `Comment`, block markup present | judged as HTML (breaks + density + block size) | markup survives |
| `Comment`, plain prose, > 300 visible chars | **DENY** | newlines genuinely strip |
| `Comment`, plain prose with `\n\n`, long | **DENY** | newlines are not breaks here |
| any body, one paragraph > 600 visible chars | **DENY** (new) | see below |
| reply with `Message.body` and no quote block | **DENY** (unchanged) | replaces the auto-quote |

**`MAX_BLOCK_CHARS` closes a hole the change would otherwise have opened.** The pre-existing
density rule is a whole-body *average*: one enormous `<p>` inside a wrapper `<div>` scores four
"breaks" and passes at any length. That was harmless while a long `Comment` was refused outright on
raw length; opening `Comment` to HTML would have inherited it. It applies to `Message.body` too,
where the hole predates this change.

---

## 5. SIGNATURES — why per-draft injection, and it is not a close call

| Mechanism | Exists? | Visible in Drafts? | Verdict |
|---|---|---|---|
| Graph signature API | **No** | — | Microsoft stated on the record (2024-08-11): *"We have no plans to support roaming signature management in the Microsoft Graph API."* `mailboxSettings` has no signature property in v1.0 or beta. |
| `Set-MailboxMessageConfiguration -SignatureHtml` | Cmdlet exists | n/a | Microsoft documents it as **non-functional**: *"This parameter doesn't work if the Outlook roaming signatures feature is enabled"* — and roaming is default-on for M365 *and* Outlook.com. |
| Exchange transport rule | Yes (tenant only) | **No** | Microsoft's own Limitations: cannot *"insert the signature directly under the latest email reply"* and cannot show it in Sent Items. On a reply it lands below the entire quoted chain, and the operator has no artifact anywhere showing what shipped. |
| **Per-draft injection** | **Yes** | **Yes** | The only mechanism visible at review, correct on a reply, and available on both mailbox types. For the personal Outlook.com mailbox it is the only option at all — no tenant, so no transport rule. |

Signature content lives in `~/.claude/email-signatures.json` (template shipped at
`templates/email-signatures.example.json`), keyed by sending identity.
`ms365-compose-body.py` **refuses an unknown id (exit 2) rather than inventing a name, title or
phone number** — an invented job title in a real business email is worse than no signature.

The `chris-reso` entry is deliberately incomplete: name, company, email, website. **No title and no
phone, because nobody has told me what they are.** Those are the operator's to supply.

### Two open items on signatures — one now CLOSED by measurement

- **Double signature: RESOLVED for this mailbox, risk is zero.** The question was whether opening
  an API-created draft in Outlook makes the client add its *own* signature on top. Rather than
  reason about compose-initiation semantics, I read two messages this operator's own Outlook
  composed and sent. The compose region of each contains **only a `<br>`, then an empty
  `<div id="appendonsend"></div>`** — the very element Outlook would populate — and then the quote.

  **No client signature is configured on this mailbox at all.** So nothing can be doubled. It also
  means the "no signature" defect was never the agent dropping one: **every message from this
  mailbox has been going out unsigned**, and per-draft injection is not restoring a signature, it
  is supplying the first one. Whoever configures a client signature later re-opens this question —
  that is the trigger to re-measure, and this paragraph is the record of how.
- **Statutory footers.** "No legal boilerplate" is wrong for a whole class of sender: UK Companies
  Act 2006 s.82 requires registered name, number, place of registration and registered office on
  business emails. If Reso is ever UK-incorporated that is an operator decision and belongs in a
  transport rule as a footer, separate from the sign-off block.

---

## 6. REJECTED ALTERNATIVES

| Option | Why rejected |
|---|---|
| `Message.body` with a hand-authored quote | Replaces Graph's auto-quote. A hand-typed quote is an assertion; Graph's is the record. One was rejected outright by the operator in a live commercial dispute (2026-08-25). |
| Placeholder splice as the DEFAULT | Still correct, still shipped, now the fallback. Four calls, 38 KB through the model's tool call, and a read-then-write round trip that lets Graph's read-time sanitiser permanently rewrite the stored quote. |
| A local CLI holding its own Graph token | The ms365 MCP server holds the token; borrowing it out of its cache is not a supported path and is the operator's call, not mine. Moot now — the one-call path needs no local token. |
| Passing the body from a FILE via the MCP | **Does not exist.** Verified against the installed 0.143.0 source: no file-path parameter on any tool, no `@file`, no streaming, zero MCP resources registered. This was the binding constraint, and the one-call path is what removes it. |
| `MS365_MCP_MESSAGE_SIGNOFF_SUFFIX` for the signature | Read the source: with a suffix set, an HTML body is re-serialised through parse5 (not byte-exact), and the appliers read lower-case `comment`/`message` while the schemas expose `Comment`/`Message` — so it likely misses reply/forward payloads entirely. |
| `MS365_MCP_BODY_FORMAT` | Read-path only (`dist/graph-tools.js:780-786`, gated on `method === "GET"`). Changes nothing you write. |

---

## 7. VERIFICATION

How a session proves a draft renders right, in order of cost:

1. **`get-mail-message-mime` on the draft's own id** — works on drafts. `get-mail-message` always
   reports contentType `text`; that is the reader handing back the text/plain alternative, NOT
   evidence the HTML was lost.
2. **`download-bytes-to-file` to disk, then parse locally.** Keeps a 38 KB body out of context.
   This is how everything in this document was measured.
3. **Headless Chrome render** of the extracted `text/html` part, light and dark:
   `--headless --screenshot --window-size=980,1250`. Deterministic and needs no auth.
4. **The operator's own eyes in Outlook** — the only instrument that sees Outlook's rendering.

### Dark mode

**A fragment has exactly one dark-mode lever: the colours it states.** Every published mechanism —
`<meta name="color-scheme">`, `:root{color-scheme}`, `prefers-color-scheme`, `[data-ogsc]` — needs
a `<head>`, a `:root`, or a `<style>` block that a fragment spliced into someone else's document
cannot deliver. All the usual dark-mode advice is simply inapplicable here.

**And "pick a dark-mode-safe text colour" is arithmetically impossible.** Across four backgrounds,
no fixed colour clears WCAG AA on both white and a dark-mode ground (best case `#858585` at
3.69:1). Lark's own `rgb(31,35,41)` — the grey this whole investigation started from — scores
**1.04–1.15:1 on dark, i.e. invisible, and worse than pure black.**

So the rule is: **declare `color` and `background-color` as a pair, or declare neither.** Colour
alone is the shape that goes invisible under *partial* inversion, where the client darkens the
background it inherited and keeps the text colour you stated. Stating both means they are inverted
together or preserved together, and both outcomes are readable. The tool now does this;
`--no-background` opts out.

**What my own instrument could and could not decide, stated honestly.** Chrome's force-dark
inverted the colour-only fragment cleanly. I then ran the control that would have made *that* a
rule — the same fragment additionally pinning `background-color:#ffffff` — expecting it to break,
and it did not: Chrome inverted the declared background too. Two arms that do not separate decide
nothing. Chrome force-dark is a *full*-inversion engine and cannot reproduce the partial-inversion
clients where black-on-black actually arises. The pair rule above therefore rests on the contrast
arithmetic, not on my render — which is why it is stated with its evidence class rather than as a
measurement.

---

## 8. THINGS THAT BIT, WORTH NOT RE-LEARNING

- **`create-reply-draft` ignores `select` and returns the full body** — ~30 KB straight into
  context. Pass `excludeResponse: true` and read the body back via MIME to disk.
- **`createReply` flips the SOURCE message's `isRead` to true.** Acknowledged by Microsoft staff,
  no opt-out. A probe on an unread thread marks it read.
- **The placeholder must be unique.** The old recipe suggested `"."` — a lone `.` appears in every
  quoted chain, so the splicer's own survives-in-output check can never pass with it.
- **Both scripts documented exit 2 for a refusal and actually exited 1** (`raise SystemExit(str)`),
  so every caller branching on it was wrong. Fixed.
- **A third-party address is neither alias.** This thread was addressed to `chris@reso.gl` and
  forwarded into the personal mailbox; Graph defaulted the reply `from` to `ichris96@hotmail.com`.
  Recipe rule 5 covers "which of our two aliases" and has no case for "neither". Flagged, not fixed
  — it needs the operator's call on which identity should answer a forwarded reso.gl thread.
- **`graph-batch` is a real hole around every name-keyed mail guard** — `z.object({}).passthrough()`,
  reaches `POST /me/sendMail`, and `--allowed-scopes` can never disable it. Already filed as
  backlog `d47516537344`; re-confirmed live in this session's server. Not exploited here.
- **EWS is blocked 2026-10-01**, so any EWS-based signature option is dead within the month.

---

## 9. PROPOSED CONFIG CHANGES — operator-owned, NOT applied

I did not edit `settings.json` or any permission/matcher, per the brief. Two changes are proposed:

**(a) A second ms365 server entry for the work mailbox.** One server instance cannot hold both a
personal (`consumers` authority) and a work (tenant authority) account — they are mutually
exclusive at `dist/auth.js:30`. A second entry needs its own token cache and selected-account path:

```jsonc
"ms365-work": {
  "command": "npx",
  "args": ["-y", "@softeria/ms-365-mcp-server", "--org-mode"],
  "env": {
    "MS365_MCP_TENANT_ID": "efbe6659-e57e-4c5b-96d1-88c6636be130",
    "MS365_MCP_TOKEN_CACHE_PATH": "~/.ms365-mcp/work-token-cache.json",
    "MS365_MCP_SELECTED_ACCOUNT_PATH": "~/.ms365-mcp/work-selected-account.json"
  }
}
```

The guard hook matches on `mcp__ms365__*`, so a server named `ms365-work` emits
`mcp__ms365-work__*` and **every mail guard would stop firing on it.** The matcher must be widened
in the same change, or the work mailbox is ungoverned. That is the operator's edit; this is the
diff, not the action.

**(b) `CC_MS365_SIGNATURES`** may point `ms365-compose-body.py` at a signature file elsewhere.
Default `~/.claude/email-signatures.json`; no settings change needed.

---

## 10. SOURCES

Live measurement against `ren.chris@outlook.com` and the real ByteDance thread (§2, §3, §7) —
reproducible from the commands in §7. Documentation research in six parallel passes; the full
per-claim files with evidence labels (DOC / EMPIRICAL / UNVERIFIED) are cited inline above. Primary
sources are learn.microsoft.com for every Graph and Exchange claim; the installed
`@softeria/ms-365-mcp-server` 0.143.0 source for every MCP claim, read at `file:line`; Purdue OWL,
Federal Plain Language Guidelines, Perkbox (n=1,928) and three academic email-corpus studies for
§1's structure.

Two corrections worth propagating, because both are widely repeated and both are wrong:
Campaign Monitor's CSS support guide (named in the brief) is from 2017 and carries a 2013 claim
that 2026 data contradicts — use caniemail's dataset instead; and *"Gmail strips all `<style>`
tags"* is false, tracing to a 2014 article whose own 2016 update reverses it. Also: *"classic
Outlook loses support October 2026"* is false — Microsoft's opt-out stage is April 2026 and
support runs to **at least 2029**, so the Word engine still has to be coded for.

**Where the research disagreed with the brief, the brief lost:** the grey was not carrier
inheritance (§2), the 300-char cap is not Graph's (§3), and the splice is not required (§3).
**Where it disagreed with the research, the measurement won:** the Graph agent flagged
"is HTML in `comment` interpolated or escaped?" as the one test that would delete its own
recommendation. It is interpolated. It did.
