# The Anthropic "Claude Code power user" box — there is no condition to meet

**Date:** 2026-09-05 · **Method:** 27-agent dynamic workflow (`wf_bcbce0d8-58b`), 10 independent
source angles → 232 claims → 12 adversarially verified → completeness critic → synthesis.
4.48M subagent tokens, 1,167 tool calls, 0 agent failures.

## The answer

**The box is real, and nothing you can do makes it arrive.** Anthropic mails an unsolicited package
to individually selected Claude Code users. The card inside reads: *"We're making it official:
you're a Claude Code power user… one of Claude Code's top users."* That sentence is the only
criterion Anthropic has ever stated anywhere, and it is operationalised nowhere — no threshold, no
plan tier, no application, no nomination, no opt-in, no waitlist.

Treat it as discretionary marketing outreach, not a tier that can be qualified for.

## Why "no earnable criterion" is a finding and not a shrug

The negative axis is what carries this conclusion, and it rests on a **control group inside a single
thread**. In [r/ClaudeCode 1vx5t8a](https://www.reddit.com/r/ClaudeCode/comments/1vx5t8a/received_a_plushy_from_anthropic/)
(u/KDamage, 2026-08-24, 1.3k upvotes, 185 comments — read in full via a redlib mirror after
reddit.com, old.reddit, r.jina.ai, allorigins and a real Chrome all hit Reddit's network-security
wall):

| | Received the box | Did **not** receive it |
|---|---|---|
| Usage | OP: 614k in / **85M out**. u/Impressive_Ad111: **28M tokens** | 21.2B · 38B · 44.0B · 49.7B · 53.8B · 100B+ tokens |
| Tenure / tier | OP: Max, **5 months**, subscription only, no API | u/Foreskin_Mafia: Max 20x **nearly a year**, all compute every week. u/Professional_Ad705: Max 20x since launch, ~200 repos. u/_ireadthings: **three** Max20 subs since launch |
| Spend | — | u/FreiherrCat: ~$1500+/mo plus API |

A recipient at 28M tokens beside non-recipients at 100B+ is a **three-order-of-magnitude inversion**.
Any volume-based criterion is dead on this evidence alone. OP, asked directly how selection works:
*"I have genuinely no idea :x"* and *"I wish I could transmit how selection pops up!"*

## The correlate table, honestly graded

| Proposed condition | Verdict | Basis |
|---|---|---|
| Heavy Claude Code usage | **plausible, not sufficient, not necessary** | The inversion above |
| Public advocacy / visible Claude Code content | **plausible — but circular** | All identifiable recipients posted publicly; they are identifiable *because* they posted. Selection on the dependent variable |
| High monthly spend | **folklore** | Traces to two June-2026 posts whose bodies are unreadable |
| Follower count | **refuted** | Recipients span 8K → 394K followers |
| US residency | **refuted** | OP: *"Nope, overseas actually!"* Recipients in Brazil, Taiwan, India, France, US |
| Plan tenure | **refuted** | 5-month subscriber in; year-plus Max 20x out |
| Repo contributions | **refuted** | Zero recipients author `anthropics/claude-code` issues |
| Data-sharing / transcript donation | **unresolved — see below** | Not sufficient; requirement status unknown |

### The data-sharing correction

A sweep agent claimed the recipient *does not* share usage data, citing his *"Nope, we have a clause
for this internally"*. **The verifier refuted it and the refutation is right.** That "Nope" answers
the narrower question of the account-level *setting*. Elsewhere in the same thread, to
u/bensyverson's description of approving session-transcript sharing, OP replies *"Yes same."* — he
**does** sometimes donate transcripts. Separately, u/bensyverson donated many transcripts and
received nothing, so donation is **not sufficient**. Whether it is *required* is unknown. Neither
direction is established.

*(Note the same source is internally inconsistent — OP says "I'm on Max" to one commenter and calls
it "a pro account" to another. n=1 anonymous self-report.)*

## The mechanism

Invitation email containing a form → recipient supplies a shipping address → box arrives in a few
business days. **No way to apply or request it.** OP: *"Received a mail to fill a form, checked a few
antiscam things, and then answered. Came in a few business days."*

Contents, photographed: printed card · black cap with embroidered Clawd · orange Clawd plush ·
sticker pack · enamel pin. Ships internationally. Rolling, not a one-off — instances span 2025-12 to
2026-08.

**The invitation is scam-shaped** — an unsolicited email asking for a home address. The only relevant
Anthropic guidance is its
[official marketing sender-address list](https://support.claude.com/en/articles/10416553-official-anthropic-marketing-email-addresses).
Anthropic's Privacy Policy (effective 2026-07-08) **never mentions a shipping or mailing address**,
so if addresses are systematically collected for this, that collection is undisclosed.

## What is not true

- **There is no "Claude Power User" programme.** The phrase appears officially only in a
  [workflow-tips help article](https://support.claude.com/en/articles/14554000-claude-code-power-user-tips)
  — advice, no gift, no membership.
- **The sticker easter egg is dead.** Asking Claude Code for stickers once opened a shipping form
  (first ~1,000 people, US-only — Boris Cherny, Threads, 2025-03-09); non-functional since mid-2025.
  `/stickers` now opens a **paid** Sticker Mule store with no plush, and is undocumented in the
  public command reference.
- **The plush's documented distribution is in-person conference swag** (Code with Claude, SF, May
  2025), one per attendee. Every purchasable "Claude plush" is fan-made and disclaims affiliation.
- **A "free 10,000-pack" Sticker Mule giveaway could not be verified** — coupon-aggregator snippets
  only, no primary source.
- **Max tier buys nothing physical.** Operator's own records: four Max accounts, 18 months of
  receipts, Fable-5 early access — zero swag contact across 98 Anthropic emails and 214,870 messages.

## The only Anthropic swag path with published criteria

[Claude Community Ambassadors](https://claude.com/community/ambassadors) lists swag as a benefit,
gated on organising local events plus hands-on Claude Code experience: application → screening call
→ signed agreement. **It is a different programme** — no recipient of the mailed box has been linked
to it. (A sweep claim that this is the *only* official swag promise was refuted: the count was
wrong, and `claude.com/community` lists two programmes in its main body, not four.)

## What the instrument could not see

Recorded because the shape of the blindness bounds the conclusion — 121 dead ends logged, the
load-bearing ones being:

- **`x.com/AnthropicAI` returned HTTP 402** — Anthropic's own social account was never read. A swag
  announcement there would be invisible to this investigation.
- **Reddit, Etsy and eBay search are bot-walled.** Reddit was recovered through a redlib mirror;
  eBay sold-listing enumeration and Etsy pages were not. Resale provenance ("received from Anthropic
  for…") is therefore unsampled.
- **"Clawd" appears nowhere on any Anthropic domain** as a mascot name. Every reference is
  third-party.
- **The help centre returns zero articles** for "stickers" and zero for "merchandise".
- **No official rules document exists** for any power-user gift or giveaway — notable because
  Anthropic does publish promotional rules when it runs promotions (the Holiday 2025 Usage Promotion
  article now 404s).
- **The Claude Code CHANGELOG has never mentioned** stickers, swag, merch, plush or gifts.

## Confidence

**High** that no earnable criterion is publicly stated. **Medium** on the correlates — n ≈ 6
identified recipients, every one self-selected by having posted publicly, and the two richest source
populations (X, Reddit search) largely unreadable.

**What would change it:** an Anthropic employee stating criteria, or anyone publishing the
invitation email's full text. Neither exists as of 2026-09-05.

## Method note worth keeping

The completeness critic and the adversarial verifiers earned their cost here. Three claims that read
as solid findings died on inspection — one by a false quantifier ("the ONLY official…"), one by
mis-threaded Reddit comment attribution (a question the OP never saw, parsed as his answer), and one
by an inverted quote (`"Yes same."` cited as proof of the opposite). All three would have shipped as
fact from the sweep layer alone.
