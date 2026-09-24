---
name: outbound-drafting
description: Draft a message the user will send to a third party (text, iMessage, email, DM). Load before the first draft when asked to "write a text/email to X", "draft a reply" or "what should I say". Not for your own chat prose, commits or docs.
---

# Drafting messages the operator will actually send

**Apply all seven rules BEFORE the first draft, not after he pushes back.**

🚨 **Brevity is the BYPRODUCT, never the rule.** Every cut below has its own reason. "Make it
shorter" is not one of them — compressing a bad message yields a short bad message.

**The tell that you got it wrong: he edits the draft instead of sending it.** Measured 2026-08-24:
seven consecutive pushbacks on a single text before it was sendable. The target is zero.

---

## 1. One message, one job

A compound ask gets the easy half answered and **the rest dies silently — no refusal, no
acknowledgement, just gone.** Close the ONE thing that *gates* everything else; everything else is
a follow-up **after** they say yes.

❌ A text asking for a date, a DOT number, an insurance certificate, a trailer spec, and who's
driving.
✅ *"Can you pick up Saturday Aug 29? If Saturday works I'm ready to lock it in today."*

*(This is the operator's own prior lesson — he once asked a compound "and/or" question and the
counterparty answered only the easy half.)*

## 2. Read the thread first, then cut every question the record already answers

🚨 **REFETCH IMMEDIATELY BEFORE EVERY DRAFT — not once at the top of the task.** Reading the thread
when you START composing is not reading it when you FINISH. The ms365 recipe hook-enforces exactly
this for email (R4, 10-minute freshness window); the message stores have no hook, so it is on you.
Re-read, then re-check every factual claim in the draft against what came back.

**Read the thread before drafting:**
- iMessage/SMS → `msg with "<phone>"`, or `msg sql "… FROM live.message …"` — **qualify `live.`**;
  a bare `FROM message` reads the 2024-and-older archive. Match handles on DIGITS
  (`h.id LIKE '%4379588%'`) — they are stored E.164, so a formatted number returns `(no matches)`
  while the thread exists.
- **WhatsApp → `./bin/wa`. It is NOT screenshot-only.** `wa chats` finds the session, `wa thread
  <session> <N>` reads it, `wa search "<term>"`. An unnamed group renders in the WhatsApp UI as a
  member's phone number, so the session you want may show as `(unnamed)` in `wa chats` — match it
  by last-activity time, not by name.
- Email → `ms365` list/get
- Genuinely screenshot-only: Messenger **E2EE** threads (`/messages/e2ee/t/` in the URL). A
  `/messages/t/` thread IS recoverable from a `facebook-*.zip` DYI export in `~/Downloads` — check
  there before declaring any channel unreachable.

🚨 **NEVER `tail` A MESSAGE TOOL'S OUTPUT. `msg` and `wa` both print NEWEST-FIRST (`ORDER BY … DESC`),
so `tail` returns the OLDEST rows and silently hides everything recent.** Use `head`, or no pipe at
all. Measured 2026-08-29: `wa thread 684 12 | tail -30` cut off the four newest messages — which held
the counterparty's move-out commitment and an acknowledged payment — and the draft that followed
asserted "nothing today" and quoted a commitment he had never made. **A truncated read is
indistinguishable from an empty one.** Before asserting ANY negative — "he never said", "nothing
arrived", "that channel is empty" — prove you reached the newest end: the top row's timestamp must be
at or after that session's last-activity time from `wa chats`.

**Re-asking is worse than being verbose.** It reads as not having read them, and it spends the
goodwill needed for the real ask. In the 2026-08-24 case the counterparty had already volunteered
the DOT number, the date and the trailer type, *unprompted*, in an email that hadn't been opened.

🚨 **A DRAFT IS NOT AN EVENT.** Never write *"you asked them X"*, *"you told them X"*, or *"they
didn't answer X"* until the message store shows it **sent**. Say *"the draft I gave you"* instead.
This error fired twice in one hour and both times it corrupted the read of the counterparty —
unanswered-because-unasked looks identical to evasive-when-asked.

🚨 **THEN READ IT AGAIN, IMMEDIATELY BEFORE THE SEND.** Reading the thread at draft time is not
enough: the counterparty can move while you are checking the artifact, and a long review is exactly
when they do. **Verifying the artifact is not verifying the situation.**

🚨 **This binds before you say "send it" AND before you tell him what is still outstanding.** A
status claim is an act: he acts on it. Never say "you haven't texted them yet," "they haven't
replied," "that's still open," or hand him a to-do about a counterparty without re-reading that
counterparty's thread FIRST. *(Measured 2026-08-25, the third instance in three days: a to-do was
handed over — "text Matt that the payment went out" — that he had already done three hours earlier,
and better than proposed; the counterparty had replied confirming receipt AND re-confirming the
pickup date. Both facts were sitting in the message store, unread. The to-do was not merely
redundant, it was wrong about the state of the deal.)*

Re-run the SAME channel query from the top of this rule, filtered to *after your draft was composed*
— a new message changes what the message should say, and after it ships you cannot take the sentence
back:

- **Email** → `list-mail-messages` with `receivedDateTime ge <when you started drafting>`.
  ⚠️ It must be an **inbound** read. A query filtered to `isDraft eq true`, or `get-mail-message-mime`
  on your own draft, does NOT count — see the measurement below, where six such queries ran and the
  gate would still have been passed.
- **iMessage/SMS** → `msg with "<phone>"`, or query the live store on digits
  (`handle LIKE '%<last7>%'` — E.164 handles make an exact-string match silently return nothing).
- **Screenshot-only channels** (Messenger/WhatsApp/Slack) → you cannot check. **Say so** and ask
  before he sends; do not let an unverifiable channel pass as a verified one.

🔒 **On the email path only, this is hook-enforced** — the draft-write tools are DENIED unless an
inbound read happened first (`hooks/enforce-email-formatting.py`). **On every other channel there is
no chokepoint to enforce** — you hand him prose and he sends it from his phone, so no tool call
exists to refuse. On those channels this rule is the only thing standing between him and a stale
message. Treat it as binding, not advisory.

*(Measured 2026-08-25. A high-stakes dispute letter was reviewed for 23 minutes — MIME parsed,
indent markup and font sizes verified twice. The counterparty's automated acknowledgement, granting
a written 24-hour commitment, had landed in the inbox 23 minutes before the send and was never
looked at. The letter shipped saying "I was not given a name or a callback time," which was true of
the call and false of the record. The fix — citing THEIR document and THEIR clock instead of
describing a phone call — was strictly better and unrecoverable once sent. Nothing in the formatting
review could have caught it, because it was not a formatting question.)*

## 3. Anchor, don't open

An open question hands them the choice and they pick the one worst for you.

❌ *"What day works?"* → they name the latest possible date
✅ *"Saturday Aug 29 is what I'm aiming for. Monday Aug 31 is the hard wall."*

Name the target **and** the constraint. Reserve open questions for things where you genuinely have
no preference.

## 4. State what you control; ask only what they control

❌ *"Would PayPal work?"* — invites renegotiation of something that was yours to decide
✅ *"I'll send it PayPal Goods and Services."*

## 5. No justification on a routine ask

Supplying a reason **implies the request is unusual, and weakens it.** Asking a carrier for an
insurance certificate before handing over a car is standard practice — it needs no excuse.

❌ *"Can your agent email me the certificate? My insurer wants it on file."* ← also untrue
✅ *"Can your insurance agent email me the cargo certificate with the limit?"*

## 6. No color

Cut anything carrying no information: *"that's exactly what the car needs"*, *"thanks so much"*,
*"just wanted to check"*, *"hope that's okay"*, *"sorry to bother you"*.

## 7. Never invent a reason to soften an ask

Softening is legitimate; **fabricating is not.** If a frame is genuinely needed, use a true one —
or route the question to the party who owes the answer and lacks the incentive to stall
(see the `disclosure-sequencing-gatekeepers` memory).

---

## 8. Format — build the body, never hand-write the markup

Sections 1-7 govern the WORDS. This one governs how they reach the recipient, and it is the half
that had no rules at all until 2026-09-14: a real draft went out as one run-on paragraph, in grey
rather than black, with no signature. Full root cause and the measurements:
`claude-infrastructure/docs/research/email-formatting-2026-09-14.md`.

**For email, you write prose into a file and a tool emits the HTML:**

```
$HOME/.claude/bin/ms365-compose-body.py --text-file reply.txt --signature <id> --out body.html
```

Then pass the contents of `body.html` as the reply tool's **`Comment`** — not `Message.body`,
which would replace Graph's own quoted chain. One API call; Graph appends the quote itself, at the
original's full depth, and no part of the original ever passes through you.

`reply.txt` is plain prose: a blank line between paragraphs, `- ` for a bullet. Nothing else.

**Why a tool and not a handful of tags.** Three things kept going wrong, and none is a matter of
care:

- **Breaks.** Microsoft Graph strips NEWLINES out of a reply Comment. It does not strip MARKUP.
  Prose passed as prose arrives as one paragraph, every time.
- **Colour.** Graph drops your text into a BARE `<body>` as an unstyled text node, while its own
  quote header directly below is explicitly black Calibri 11pt. Unstyled text takes the reading
  client's default, so it renders grey against a black quoted chain. Every block element has to
  state its own font, size and colour — inline, because the fragment lands inside a document the
  other party wrote, whose stylesheet Graph copies into the draft's head.
- **Signature.** Graph never adds one, and no Graph API can read the user's Outlook signature.
  If the tool does not put it in the body, the message ships unsigned.

**The signature is data, not prose.** It lives in `~/.claude/email-signatures.json`, keyed by
sending identity. The tool REFUSES an unknown id rather than filling the gap — if a title or a
phone number is missing, **ask the operator; do not invent one.** An invented job title in a real
business email is worse than no signature at all.

**Structure of the message.** Answer-first. What reads as junior reads that way because it defers
the answer behind context, gratitude, or self-introduction.

| | |
|---|---|
| Greeting | own line, name included — omitting it is the most-disliked opening measured |
| Anchor | ONE sentence that could only have been written to *this* message (§3) |
| Body | 1-3 paragraphs, one idea each. The FIRST carries the answer, not the reasoning |
| The ask | exactly one, own paragraph, concrete (§1) |
| Sign-off | one line, sentence case, comma |
| Signature | 3-5 lines; no quote, no logo, no invented title |

No *"I hope this email finds you well"* — it spends the one sentence a stranger actually reads.
No bullet list unless there are ≥3 genuinely parallel items; prose is the default register of
correspondence, and a list where prose belongs is a machine tell. Neither is `**markdown**`,
which is the highest-signal tell of all because no mail client renders it.

## Ambiguity check before sending

- **Every role named precisely.** *"your agent"* reads as the accounts person; *"your insurance
  agent"* cannot be misread.
- **Every identifier expanded at first use.** Never a bare code, ticket id, or internal label.
- **Every date carries its weekday.** "Saturday Aug 29", not "the 29th".
- **One command / one action per message**, if any.

## 🚨 DRAFTING IS NOT SENDING — authorization does not carry forward

**Default: produce the text and stop.** The operator sends it.

> 🔒 **For EMAIL this is now MECHANICAL, not a matter of discipline (2026-08-25).** The ms365 send
> tools — `send-mail`, `reply-mail-message`, `reply-all-mail-message`, `forward-mail-message`,
> `send-draft-message` — are **denied by a PreToolUse hook**, absolutely, with **no override**.
> Compose with `create-draft-email` / `create-reply-draft` / `create-reply-all-draft` /
> `create-forward-draft`, then tell him the draft is in Drafts and ready.
> **Do not ask for permission to send an email, and do not look for a way around the deny** — the
> answer is always "it goes in Drafts." Asking wastes a round-trip on a decision already made.
> The judgment below still governs every channel the hook cannot reach: **iMessage/SMS, WhatsApp,
> Messenger, Slack, web forms, phone.** Those have no mechanical brake, so *this section is the
> only thing standing there* — read it as being about them now.
> Rationale + evidence: `~/Development/claude-infrastructure/docs/research/email-guardrails-2026-08-25.md`.

**Send on his behalf ONLY when he authorized THAT send.** *"Can you send it?"* about one email is
consent for **that** email — it is not standing consent for the next one, the same evening, to a
different party.

**Email also carries a second irreversible trap: the SENDER ALIAS.** The mailbox has two —
`ichris96@hotmail.com` and `ren.chris@outlook.com` — and a reply must go out on **the alias the
counterparty already has for that thread** (read the original's `toRecipients`/`ccRecipients`).
Graph does *not* do this for you: it applies the mailbox default (`ichris96`), so a thread on
`ren.chris` needs `Message.from` set explicitly. Montway's order #3414154 was on `ichris96`
throughout; a hold request sent from `ren.chris` reached an address they had never seen on that
order, and they dispatched and charged $1,779 anyway.

**Name the mailbox before the alias.** The ms365 server also holds `chris@reso.gl` (the business
mailbox, sending as `chris@`, `hello@`, `info@` and the other reso.gl aliases). Every draft write,
`from` change and send must pass `account` — `ren.chris@outlook.com` or `chris@reso.gl` — because
without it the server silently uses the personal mailbox. The email hook denies the call otherwise.

**A question is not an instruction.** *"So they won't auto-inspect unless we tell them?"* is a
request for information. Answering it by emailing the landlord is not responsiveness — it commits
him to wording, dates and asks he never saw. (2026-08-24: three sends in one evening, only the
first authorized; the third was a legally-operative §1950.5(f) notice in a live deposit dispute.)

**Escalation to watch for in yourself:** one explicit "send it" → a send justified by urgency →
a send with no authorization at all. Each step feels continuous with the last and the distance
from consent compounds.

**Ask before sending when ANY of these is true** — one line, not a paragraph. *(For email the
question no longer arises: it goes to Drafts either way. This list is for the unbraked channels —
iMessage/SMS and anything else you can transmit.)*
- The message is legally operative (statutory notice, contract, dispute correspondence)
- It commits him to a **date, a price, or a term**
- The counterparty is one he has an ongoing relationship or dispute with
- It **raises a question that could be answered "no"** and staying silent was an option
- He asked a question rather than giving an instruction

**Genuinely safe to send unasked:** nothing. Draft it; he sends. The keystroke is not the
bottleneck — his judgment on the wording is the product.

## Output format

Give the message **as plain sendable text — no preamble, no "here's a draft", no framing after
it.** If the operator asks "provide the full text", output the message and nothing else.

## Related

`CLAUDE.md` § Communication Discipline (your own prose — different rules) ·
memories: `feedback_draft_outbound_messages` (provenance) ·
`feedback_quote_the_thread_not_the_recollection` · `feedback_lead_with_the_one_sentence` ·
`disclosure-sequencing-gatekeepers` · skill: `manual-command-delivery` ·
`docs/research/email-formatting-2026-09-14.md` (§8's measurements, and the guard that enforces it)
