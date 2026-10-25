# S08 — Terms and policy exposure of mid-turn account moves

Slot: S08-terms-and-policy. Author: worker agent, 2026-10-25. Read-only web research plus one grep of the extracted CC 2.1.293 source.
Scratch dir: /tmp/mtam/S08-terms-and-policy/ (downloaded pages, the `strip.py` HTML-to-text helper, tweet JSON).

Every quote below is copied verbatim from the fetched primary source unless it is marked SECONDARY or INFERENCE.
"Fetched" means fetched on 2026-10-25 by me.

---

## 1. Method (commands and their key output)

All shell commands used `timeout`. Downloads used curl with an ordinary Chrome UA. HTML was turned into text with `/tmp/mtam/S08-terms-and-policy/strip.py`, which removes script and style tags and then all tags. For Sanity-rendered anthropic.com pages, I also regex-read the embedded JSON payload.

| # | Command (abridged) | Key output |
|---|---|---|
| 1 | `curl -sL -A UA https://www.anthropic.com/legal/consumer-terms` | 200, 545431 B; the page shows "Effective Oct 8, 2025". The embedded versionHistory says `2025-10-08 isLatest:true` |
| 2 | `curl -sL -A UA https://www.anthropic.com/legal/aup` | 200, 1023621 B; the page shows "Effective Nov 12, 2026". versionHistory: `fbaea72f… 2026-11-12 isLatest:true`, `22742366… 2025-09-15 isLatest:false`, so the 2026 text is NOT yet in force on 2026-10-25 |
| 3 | `curl … https://www.anthropic.com/legal/archive/22742366-2ef0-4c7a-a833-6523f10d3944` | 200; the in-force AUP (effective Sep 15, 2025). Its "Do Not Abuse our Platform" bullets came from the JSON payload at byte offsets 212963 to 214544 |
| 4 | `curl … https://docs.claude.com/en/docs/claude-code/llm-gateway` | redirected to https://code.claude.com/docs/en/llm-gateway, 200 |
| 5 | `curl … https://code.claude.com/docs/en/legal-and-compliance` | 200 (current, undated page) |
| 6 | `curl … https://code.claude.com/docs/en/{llm-gateway-protocol,llm-gateway-connect,authentication,gateways}.md` | all 200 |
| 7 | Wayback `id_` snapshots of legal-and-compliance at 20260301135226, 20260610022333 and 20260903205410 (`--compressed`) | 200 each; the auth paragraph changed between March and June 2026 (quotes in §2.4) |
| 8 | `curl … techcrunch.com/2025/07/28/anthropic-unveils-new-rate-limits-to-curb-claude-code-power-users/` | 200; dated "12:21 PM PDT · July 28, 2025" |
| 9 | `curl https://cdn.syndication.twimg.com/tweet-result?id=<id>` for 1949898502688903593, 2024212378402095389, 2024212380142752025, 2024230184287949207, 2040206440556826908 | 200 each; texts and created_at quoted below |
| 10 | `curl … techcrunch.com/2026/04/04/anthropic-says-claude-code-subscribers-will-need-to-pay-extra-for-openclaw-support/`, `curl … theregister.com/software/2026/04/06/anthropic-closes-door-on-subscription-use-of-openclaw/5222854`, piunikaweb 2026-02-19, gigazine 2026-02-20 | 200 each |
| 11 | `curl … support.claude.com/en/articles/11145838-…` | 200; `"dateModified":"2026-10-24T00:08:23Z"` |
| 12 | `curl … support.claude.com/en/articles/11014257-about-claude-s-max-plan-usage` | **404**. That article's current text was not retrieved |
| 13 | `python3 -I` regex over /tmp/mtam/cc293-src.js for `user_id` near `account` | one hit at byte 8876959 (function KWe, quoted in §4) |

WebSearch queries (standard or extended) covered: Consumer Terms multiple accounts; 2026 OAuth third-party harness ban; Max plan help article; weekly limits July 2025; "multiple Max accounts" employee statement; the "This credential is only authorized for use with Claude Code" error; Boris Cherny April 2026; the Nov 12 2026 AUP update; account switcher bans.

---

## 2. What the sources say (quotes and dates)

### 2.1 Consumer Terms of Service (US/RoW, effective Oct 8, 2025, still `isLatest:true` on 2026-10-25)
URL: https://www.anthropic.com/legal/consumer-terms

- §2 Account: "You may not share your Account login information, Anthropic API key, or Account credentials with anyone else. You also may not make your Account available to anyone else. You are responsible for all activity occurring under your Account…"
- §3 Use of our Services, prohibited uses:
  - "…or resell the Services."
  - "Except when you are accessing our Services via an Anthropic API Key or where we otherwise explicitly permit it, to access the Services through automated or non-human means, whether through a bot, script, or otherwise."
  - "You also must not abuse, harm, interfere with, or disrupt our Services, including, for example, … bypassing any of our systems or protective measures."
- Capacity: "We may sometimes add or remove features, increase or decrease capacity limits…"
- Termination: "We may suspend or terminate your access to the Services (including any Subscriptions) at any time without notice to you if we believe that you have breached these Terms…"
- **TEXT FINDING:** the current Consumer Terms contain **no** clause that limits a person to one account, and no clause that names rotating accounts to stretch usage limits. `grep -i 'technical limitation|usage limit'` returned no match. The only nearby hooks are "bypassing any of our systems or protective measures" and the bot/script clause.

### 2.2 Usage Policy (AUP)

**In force on 2026-10-25: version effective Sep 15, 2025** (https://www.anthropic.com/legal/archive/22742366-2ef0-4c7a-a833-6523f10d3944). "Do Not Abuse our Platform":
- "Coordinate malicious activity across multiple accounts to avoid detection or circumvent product guardrails or generating identical or similar inputs that otherwise violate our Usage Policy"
- "Utilize automation in account creation or to engage in spammy behavior"
- "Circumvent a ban through the use of a different account, …"
- "Intentionally bypass capabilities, restrictions, or guardrails established within our products for the purposes of instructing the model to produce harmful outputs (e.g., jailbreaking or prompt injection) without prior authorization from Anthropic"
- This version has no resell or proxy bullet.

**Published, effective Nov 12, 2026, 18 days from now** (https://www.anthropic.com/legal/aup, internal name "AUP (US+RoW, 2025-11-12) - 2026 Update"; a Classmethod blog post reproduces an AWS Health notice confirming the date: https://dev.classmethod.jp/articles/anthropic-usage-policy-update-bedrock-health/). "Do Not Abuse Our Platform" now reads:
- "Coordinate malicious activity across multiple accounts, **or create multiple accounts**, to avoid detection, circumvent product guardrails, or generate identical or similar inputs that otherwise violate our Usage Policy"
- "Intentionally bypass or interfere with capabilities, restrictions, or guardrails established within our products, **including by circumvention of the account sign-up or log-in process** or by instructing the model to produce harmful outputs (e.g., jailbreaking or prompt injection), without prior authorization from Anthropic"
- NEW: "**Resell, proxy, or otherwise provide access to Claude through unauthorized means, including services that route requests through consumer subscriptions or misrepresent the product or client being used**"
- **TEXT vs INFERENCE:** neither version defines "product guardrails" or "restrictions". Whether per-account usage limits count as "restrictions … established within our products" is not stated (INFERENCE: a plain reading could include them; Anthropic has never said so). The new "create multiple accounts … to circumvent product guardrails" branch drops the "malicious" qualifier for account creation.

### 2.3 Weekly-limits announcement (July 28, 2025)
- @AnthropicAI, 2025-07-28T18:23:25Z (status 1949898502688903593, read via the syndication API): "We're rolling out new weekly rate limits for Claude Pro and Max in late August. We estimate they'll apply to less than 5% of subscribers based on current usage." (The rest of the thread is an image and was not retrieved as text.)
- TechCrunch, Maxwell Zeff, 2025-07-28 (SECONDARY report of Anthropic's statements): "curb usage among subscribers who are running … Claude Code, 'continuously in the background, 24/7.' Anthropic says the rate limits also aim to stop a handful of users who are violating Claude's usage policy by sharing accounts and reselling access to Claude Code." Also: "Max subscribers can purchase additional usage, beyond what the rate limit provides, at standard API rates."
- VentureBeat (SECONDARY, from the search summary only; I did not fetch it): Anthropic statement "we've also seen policy violations like account sharing and reselling access".
- **TEXT FINDING:** the named abuses are 24/7 background use, *sharing* and *reselling*. Using several accounts you own and pay for is not named.

### 2.4 Claude Code "Legal and compliance" page, authentication paragraph, in three dated versions
URL: https://code.claude.com/docs/en/legal-and-compliance

- **Wayback 2026-03-01** (the "docs clean up" text added around Feb 18–19, 2026): "OAuth authentication (used with Free, Pro, and Max plans) is intended exclusively for Claude Code and Claude.ai. Using OAuth tokens obtained through Claude Free, Pro, or Max accounts in any other product, tool, or service — including the Agent SDK — is not permitted and constitutes a violation of the Consumer Terms of Service. … Anthropic does not permit third-party developers to offer Claude.ai login or to route requests through Free, Pro, or Max plan credentials on behalf of their users. Anthropic reserves the right to take measures to enforce these restrictions and may do so without prior notice."
- **Wayback 2026-06-10:** the text is softened to "OAuth authentication is intended exclusively for purchasers of Claude Free, Pro, Max, Team, and Enterprise subscription plans and is designed to support ordinary use of Claude Code and other native Anthropic applications." A banner adds: "Starting June 15, 2026, Agent SDK and claude -p usage on subscription plans will draw from a new monthly Agent SDK credit, separate from your interactive usage limits."
- **Wayback 2026-09-03 = current fetch 2026-10-25:** the same softened sentence, plus: "Anthropic does not permit third-party developers to offer Claude.ai login into their own applications, or to route requests through Free, Pro, or Max plan credentials on behalf of their users. Moreover, **developers may not collect, store, or intermediate Claude.ai credentials or session tokens — sign-in to a Claude account must complete through Anthropic's own flow.**" Also: "**Advertised usage limits for Pro and Max plans assume ordinary, individual usage of Claude Code and the Agent SDK.**" and "Anthropic reserves the right to take measures to enforce these restrictions and may do so without prior notice." The page also says: "Nor does it prevent an end user from signing in to the unmodified Claude Code binary with their own Claude subscription".
- **TEXT vs INFERENCE:** the grammatical subject of the credential sentences is "developers" or "third-party developers" acting "on behalf of their users". Whether one subscriber moving his own tokens among his own clients counts as "intermediate" is not addressed (INFERENCE).

### 2.5 Anthropic staff statements on multiple accounts (Feb 18, 2026)
Read via the syndication API:
- @trq212 (Thariq Shihipar, Claude Code team), 2026-02-18T21:10:58Z, status 2024230184287949207, replying to a post saying Anthropic was "going after people with multiple paid Max accounts": "a bit confused by the post, were they banned? I'll reach out on Reddit but we haven't changed anything here / **it's not against terms of service to have multiple MAX accounts, though sometimes people are using multiple MAX accounts to do things like resell tokens which of course is**" (the text is truncated at a note_tweet boundary; the remainder was not retrieved).
- @trq212, 2026-02-18T20:00:13Z (2024212378402095389): "Apologies, this was a docs clean up we rolled out that's caused some confusion. Nothing is changing about how you can use the Agent SDK and MAX subscriptions!"
- @trq212, 2026-02-18T20:00:14Z (2024212380142752025): "We want to encourage local development and experimentation with the Agent SDK and claude -p. If you're building a business on top of the Agent SDK, you should use an API key instead."
- Status: informal employee posts, not terms. PiunikaWeb (2026-02-19, SECONDARY) reports user bans in the same week ("I was banned after just renewing for 12 months for making a usage tracker Mac app with Claude Code").
- Official docs explicitly support several accounts on one machine. authentication.md (fetched 2026-10-25), "Log in with multiple accounts": "To stay signed in to multiple accounts at once, such as work and personal accounts, give each account its own configuration directory. … set the CLAUDE_CONFIG_DIR environment variable … Each directory has its own settings, session history, and claude.ai login or API key." Line 211: "…keys the macOS Keychain entry to that directory too, so a session with a different CLAUDE_CONFIG_DIR reads a different entry."

### 2.6 2026 enforcement against third-party harnesses using subscription OAuth
- ~Jan 9, 2026, server-side rejection of subscription OAuth from non-Claude-Code clients. SECONDARY only (WinBuzzer 2026-02-19, an OpenClaw docs commit dated 2026-01-09, Moltis docs). The error string reported is "This credential is only authorized for use with Claude Code". No Anthropic primary source was found.
- Feb 18–19, 2026: the legal-page text in §2.4 (March snapshot), then the "docs clean up" apology (§2.5).
- @bcherny (Boris Cherny, head of Claude Code), 2026-04-03T23:14:55Z, status 2040206440556826908: "Starting tomorrow at 12pm PT, Claude subscriptions will no longer cover usage on third-party tools like OpenClaw. You can still use these tools with your Claude login via extra usage bundles (now available at a discount), or with a Claude API key."
- TechCrunch 2026-04-04, quoting the customer email: subscribers will "no longer be able to use your Claude subscription limits for third-party harnesses including OpenClaw", and the policy "applies to all third-party harnesses and will be rolled out to more shortly."
- The Register 2026-04-06, Anthropic spokesperson statement: "Starting April 4, third-party tools will draw from extra usage instead of subscription limits … **Using Claude subscriptions with third-party tools isn't permitted under our Terms of Service**, and they put an outsized strain on our systems." The article adds: "Claude subscriptions continue to apply to Claude.ai, Claude Code, and Cowork."
- **TEXT FINDING:** every 2026 enforcement item targets *non-Anthropic clients* (harnesses) using subscription credentials. None targets the official client being pointed at a different one of the user's own accounts.

### 2.7 LLM gateway docs (current; the docs.claude.com URL redirects to code.claude.com/docs/en/llm-gateway)
- "Subscriptions and gateways": "While a gateway credential variable or apiKeyHelper is active, requests carry that credential in place of a developer's claude.ai subscription login, and the subscription's usage limits don't apply to them. … billed per token to whoever owns the credential the gateway forwards…"
- "**ANTHROPIC_BASE_URL is the variable that points Claude Code at the gateway. Setting only that variable, without a gateway credential, doesn't replace the subscription. Requests still route through the gateway, but a saved claude.ai login remains the active credential, so its usage limits and billing apply. Gateways that pass this traffic on to Anthropic must forward the OAuth capability in anthropic-beta**".
- llm-gateway-protocol.md: the `anthropic-beta` row says "When the developer authenticates with a claude.ai login, which is possible when ANTHROPIC_BASE_URL is set without a gateway credential variable, this header also carries an OAuth capability that the upstream requires, and stripping it fails those requests with 401". `anthropic-ratelimit-unified-*`: "Forward the upstream's values unchanged … to show usage against plan limits to developers signed in with claude.ai".
- llm-gateway-connect.md: "Remote Control is also disabled while ANTHROPIC_BASE_URL points at a non-Anthropic host".
- Also: "Anthropic doesn't endorse, maintain, or audit third-party gateway products".
- **Answer to (d):** a gateway or proxy in the path is documented as working with subscription (claude.ai) auth **only as pass-through of the client's own saved login**. Billing-substitution gateways are documented only with API keys, cloud-provider credentials or apiKeyHelper bearer credentials, all billed per token. No doc describes a gateway that *swaps in a different claude.ai subscription token*.

### 2.8 Help center
- "Use Claude Code with your Pro or Max plan" (support.claude.com/en/articles/11145838, dateModified 2026-10-24): "Both Pro and Max plans have a five-hour session limit and a weekly limit. … These limits are shared across Claude and Claude Code". When you hit limits the article suggests upgrading or using extra usage or API credits, or "Allow your usage period to reset before continuing". It says nothing about using a second account (neither allowed nor forbidden).
- "About Claude's Max plan usage" (11014257): returned **404** on 2026-10-25; current text not read.
- No help-center article on owning several personal accounts was found. Related articles exist for Claude plus Console accounts on one email (8987223) and individual plus Team switching.

---

## 3. Answers to (a)–(d)

- **(a) Owning several paid Max accounts.** No term forbids it (Consumer Terms Oct 8, 2025; AUP Sep 15, 2025). Docs show several accounts per machine via CLAUDE_CONFIG_DIR. An Anthropic Claude Code team member said on 2026-02-18: "it's not against terms of service to have multiple MAX accounts". That is an informal statement, not a contractual one.
- **(b) Rotating own accounts to extend limits.** No primary source addresses it directly. The named abuses are sharing, reselling and 24/7 background use (2025-07-28). The hooks that could be read against rotation are: Consumer Terms "bypassing any of our systems or protective measures"; the legal page "Advertised usage limits … assume ordinary, individual usage"; and, from 2026-11-12, AUP "create multiple accounts, to … circumvent product guardrails" and "Intentionally bypass … restrictions … established within our products". Whether usage limits are "guardrails", "restrictions" or "protective measures" is undefined (INFERENCE: it is a live ambiguity, and it gets worse after Nov 12).
- **(c) Subscription OAuth outside the official client or via proxy.** Forbidden for third-party harnesses and tools. Text: the March 2026 legal page "not permitted and constitutes a violation of the Consumer Terms of Service". Spokesperson, April 2026: "isn't permitted under our Terms of Service". Enforcement: billing cutover on 2026-04-04 for all third-party harnesses, plus the SECONDARY ~2026-01-09 server-side rejection. The current legal page bars developers from "collect, store, or intermediate Claude.ai credentials". From Nov 12, 2026 the AUP bars "Resell, proxy, … including services that route requests through consumer subscriptions or misrepresent the product or client being used".
- **(d) Gateway.** Supported with subscription auth only as pass-through of the client's own saved login (forward `anthropic-beta`). Credential-replacing gateways are documented only with API, cloud or helper credentials billed per token.

---

## 4. Rating the three mechanisms (operator's own four accounts only)

The exposure scale runs from Low (no text reads on it; it matches documented use) to High (the text plausibly reads on it, and enforcement is active against close cousins).

**M1. Restart the session on another of his own accounts** (today's practice: /exit, then `claude --resume <uuid>` with a different CLAUDE_CONFIG_DIR).
- TEXT basis for low exposure: the documented "Log in with multiple accounts" flow; the official, unmodified client; each token signed in through Anthropic's own flow; "it's not against terms of service to have multiple MAX accounts" (employee, 2026-02-18).
- TEXT basis for residual exposure: "ordinary, individual usage" (it is individual; "ordinary" is arguable for 4×Max 24/7). The Nov 12, 2026 AUP adds "create multiple accounts, to … circumvent product guardrails". The cc-lr automation types into the client, against Consumer Terms "automated or non-human means, whether through a bot, script" unless "explicitly permit[ted]" (INFERENCE: the docs explicitly support scripted Claude Code use, so this is weak).
- **Rating: Low (to low-moderate after 2026-11-12). Conviction 75%** that M1 is not a breach under the text in force today. 65% for after Nov 12, because "product guardrails" might be read to cover usage limits.

**M2. Localhost proxy (ANTHROPIC_BASE_URL) injecting a different own account's OAuth token per request** into requests the official client generated.
- TEXT basis: pass-through of the client's *own* login through a gateway is documented (§2.7). Substituting a different subscription credential is documented nowhere. The current legal page: "developers may not collect, store, or intermediate Claude.ai credentials or session tokens — sign-in to a Claude account must complete through Anthropic's own flow". March 2026 legal page: "Using OAuth tokens … in any other product, tool, or service … is not permitted" (the proxy is such a tool). Nov 12, 2026 AUP: "Resell, **proxy**, or otherwise provide access to Claude through unauthorized means, including services that **route requests through consumer subscriptions**…". The 2026 enforcement program is aimed at exactly the "subscription token held by a non-Anthropic component" pattern.
- INFERENCE (mitigating): the "developers … on behalf of their users" and "provide access" framing targets serving others; M2 serves only the account owner, and the request is native Claude Code traffic.
- INFERENCE (aggravating, technical): CC 2.1.293 puts the logged-in account into every request's metadata. /tmp/mtam/cc293-src.js byte 8876959, function `KWe`: `w={…device_id:sI(),account_uuid:…||iL()?.accountUuid||Mn()?.accountUuid||"",session_id:K(),…};…return{user_id:_(T)}`. A proxy that swaps the bearer token without rewriting this sends requests where token-owner ≠ metadata account_uuid, which is a server-visible mismatch. Rewriting it to hide the mismatch moves toward "misrepresent the product or client being used".
- **Rating: Moderate-High. Conviction 70%** that M2 falls within at least one current or imminent text in a way Anthropic could cite (legal-page "intermediate" sentence and/or the Nov 12 AUP proxy bullet). **45%** that it is an unambiguous violation of the text in force today (2026-10-25), given the "developers / on behalf of users" framing.

**M3. Rewrite the keychain item `Claude Code-credentials-<hash>` that a running official client reads,** so its wA()/y$() paths adopt another own account's token.
- TEXT basis: the client is unmodified ("The Claude Code binary must not be modified" is not touched); the token comes from Anthropic's own sign-in flow on the owner's own account; no non-Anthropic component sends traffic. authentication.md: "Claude Code manages .credentials.json through /login and /logout" is descriptive, not a prohibition. Residual hooks: the same limit-circumvention ambiguity as M1. Nov 12, 2026 AUP "circumvention of the account sign-up or log-in process" (INFERENCE: copying a token into a slot instead of running /login could be characterised that way). Legal page "store, or intermediate Claude.ai credentials" (its subject is "developers").
- INFERENCE (technical, raises the detection profile): the same metadata `account_uuid` mismatch as M2 if `iL()`/`Mn()` keep returning the original config dir's account. Copying one refresh token into two slots risks refresh-token rotation conflicts (cf. the lead's jhr() invalid_grant clear path), which could look like token misuse to the server. I did not verify either point.
- **Rating: Low-Moderate. Conviction 60%** that it is not a breach of current text. It sits between M1 and M2: closer to M1 on text, closer to M2 on server-visible signals.

**Relative ordering (conviction 80%):** M1 < M3 < M2 in policy exposure.

---

## 5. Mechanisms noticed (one line each)
- Official `/login` inside a running session: authentication.md line 243 says "If you run /login while the variable is set, Claude Code switches the current session to the new login". This is an Anthropic-flow live credential swap. It overwrites that config dir's stored login; mid-turn behaviour is unverified.
- `ANTHROPIC_BASE_URL` pass-through proxy that keeps the client's own token (documented; no account change by itself) versus one that swaps the token (M2).
- `CLAUDE_CODE_OAUTH_TOKEN` env/FD token with BRs() polling for a rotated token (lead's finding). It is documented for CI/scripts via `claude setup-token`, so the token is minted through Anthropic's flow.
- `apiKeyHelper` "for dynamic or rotating credentials". Its values are sent as `x-api-key` and `Authorization: Bearer`; the docs only cover API or gateway credentials (subscription limits "don't apply"). Using it with subscription OAuth tokens is undocumented.
- Keychain or `.credentials.json` rewrite under a running client (M3), adopted via wA()/y$().
- Restart on another CLAUDE_CONFIG_DIR with `--resume` (M1).

## 6. Open questions
- Does "product guardrails" / "restrictions … established within our products" (AUP effective 2026-11-12) cover per-account usage limits? No Anthropic statement found.
- The full text of Thariq's truncated 2026-02-18 reply (note_tweet) was not retrieved.
- The current text of help article 11014257 (Max plan usage) is unknown; the URL returned 404.
- The ~2026-01-09 server-side block has only secondary sourcing. What fingerprint does it use (client headers, system prompt, metadata), and would an M2 proxy carrying genuine CC requests trip it?
- Does `iL()`/`Mn()` (metadata account_uuid) refresh when the keychain token changes under a running client (M3)? I did not check this in the source.
- After M1, does `--resume` reuse the same `session_id` across accounts, making cross-account continuity server-visible? Probably yes (INFERENCE), unverified.

## 7. Sources (all fetched 2026-10-25)
- Consumer Terms (eff. 2025-10-08): https://www.anthropic.com/legal/consumer-terms
- Usage Policy (eff. 2026-11-12, published): https://www.anthropic.com/legal/aup
- Usage Policy (eff. 2025-09-15, in force): https://www.anthropic.com/legal/archive/22742366-2ef0-4c7a-a833-6523f10d3944
- AWS Health notice of the Nov 12, 2026 AUP (SECONDARY): https://dev.classmethod.jp/articles/anthropic-usage-policy-update-bedrock-health/
- CC legal page, current: https://code.claude.com/docs/en/legal-and-compliance ; Wayback: https://web.archive.org/web/20260301135226/https://code.claude.com/docs/en/legal-and-compliance , …/20260610022333/… , …/20260903205410/…
- Gateway docs: https://code.claude.com/docs/en/llm-gateway , https://code.claude.com/docs/en/llm-gateway-protocol.md , https://code.claude.com/docs/en/llm-gateway-connect.md , https://code.claude.com/docs/en/gateways.md
- Auth docs: https://code.claude.com/docs/en/authentication.md
- Help: https://support.claude.com/en/articles/11145838-use-claude-code-with-your-pro-or-max-plan (modified 2026-10-24)
- @AnthropicAI 2025-07-28: https://x.com/AnthropicAI/status/1949898502688903593 ; TechCrunch 2025-07-28: https://techcrunch.com/2025/07/28/anthropic-unveils-new-rate-limits-to-curb-claude-code-power-users/
- @trq212 2026-02-18: https://x.com/trq212/status/2024230184287949207 , https://x.com/trq212/status/2024212378402095389 , https://x.com/trq212/status/2024212380142752025
- PiunikaWeb 2026-02-19: https://piunikaweb.com/2026/02/19/anthropic-claude-max-ban-agent-sdk-clarification/ ; Gigazine 2026-02-20: https://gigazine.net/gsc_news/en/20260220-anthropic-third-party-block
- @bcherny 2026-04-03: https://x.com/bcherny/status/2040206440556826908 ; TechCrunch 2026-04-04: https://techcrunch.com/2026/04/04/anthropic-says-claude-code-subscribers-will-need-to-pay-extra-for-openclaw-support/ ; The Register 2026-04-06: https://www.theregister.com/software/2026/04/06/anthropic-closes-door-on-subscription-use-of-openclaw/5222854
- WinBuzzer 2026-02-19 (SECONDARY, Jan 9 block): https://winbuzzer.com/2026/02/19/anthropic-bans-claude-subscription-oauth-in-third-party-apps-xcxwbn/
