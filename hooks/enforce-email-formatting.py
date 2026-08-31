#!/usr/bin/env python3
"""
enforce-email-formatting.py — PreToolUse hook for SAFE, readable outbound email.

Fires on the ms365 mail send/draft tools. Three independent guard families:

  R1  DRAFTS ONLY (2026-08-25). Every programmatic SEND is denied outright. A Graph
      send is immediate and irreversible — there is no unsend window on this path
      (Outlook's "undo send" is a client-side delay that does not exist over Graph).
      The agent composes into Drafts; the OPERATOR presses send. Cost: 2026-08-24,
      three sends in one evening, only the first authorized, the third a legally
      operative Cal. Civ. Code §1950.5(f) notice in a live deposit dispute.

      R1 IS ABSOLUTE — it is checked BEFORE the kill switch and has no override.
      An escape hatch conditioned on "the user said to send it" would be worthless,
      because a model asserting that consent IS the failure that already happened.
      The break-glass is the operator pressing Send in Outlook, which costs one tap.
      The fail-open handler at the bottom also re-denies sends: a crash must never
      resurrect the one class of call that cannot be undone.

  R2  ALIAS CONTINUITY (2026-08-25). This mailbox has two aliases —
      ichris96@hotmail.com and ren.chris@outlook.com. An outgoing message must use
      the alias the counterparty already has for THAT thread. Enforced here: a
      `from`/`sender` outside those two addresses is denied. NOT enforceable here:
      whether the chosen alias matches the thread — see ALIAS NOTE below.

  R3  FORMATTING / THREADING (pre-existing). Wall-of-text, lost-quote and
      detached-thread guards, unchanged in substance.

  R4  PRE-WRITE FRESHNESS (2026-08-25). A draft WRITE is denied unless this session has
      listed RECEIVED mail in the last CC_MS365_FRESHNESS_MIN (default 10) minutes.
      Sends are human-executed now, so the draft write is the last agent operation in an
      email flow — the only point a hook can still stand on. Rationale, and why only a
      list of received mail counts, at the R4 block below.

ALIAS NOTE — why R2 is half-enforced, stated plainly so nobody reads more coverage
into it than exists. A PreToolUse hook receives ONLY tool_name + tool_input. Graph's
RESPONSES are structurally invisible to it, and a reply's tool_input carries just a
messageId — never the original's recipients. So the thread's alias cannot be derived
here at all. The alternative, having this hook call Graph itself, is rejected: it
fires on EVERY ms365 call across five account config dirs, so it would add network
latency and a hang risk to every mail operation, and would need its own auth. The
thread-match half therefore lives in RECIPE rule 5 (prose) and is mitigated
structurally by R1 — under drafts-only, every outgoing message is reviewed in Outlook,
which displays the From address before the operator sends.

Root cause of the formatting rules (confirmed against the mailbox 2026-06-12): the
reply/forward `Comment` field is the trap. Microsoft Graph STRIPS newlines from a
Comment on a plain-text reply, so a multi-paragraph Comment collapses into one
unreadable paragraph — that is what broke the UBC Sleep Clinic reply. The reliable
path is to put the reply text in `Message.body` with contentType:'html' and <p>…</p>
per paragraph.

Root cause (confirmed against the mailbox 2026-06-12): the reply/forward
`Comment` field is the trap. Microsoft Graph STRIPS newlines from a Comment on a
plain-text reply, so a multi-paragraph Comment collapses into one unreadable
paragraph — that is what broke the UBC Sleep Clinic reply. The reliable path is
to put the reply text in `Message.body` with contentType:'html' and <p>…</p> per
paragraph; Graph preserves those breaks (it down-converts to a text body with
\\r\\n\\r\\n when the original was plain text). A pure-text `Message.body` /
send-mail body DOES preserve \\n. So the break signal depends on WHICH field
carries the text.

Decision matrix (per extracted body, once visible text > MIN_LEN):
  - source == Comment                      -> DENY  (newlines unreliable; use Message.body HTML)
  - Message/draft body, contentType html   -> need <p>/<br>/block tags, else DENY
  - Message/draft body, text (or unset)    -> need a \\n break, else DENY
  - Long body with too few breaks (density) -> DENY (e.g. one giant <p>…</p>)
  - Otherwise / short / unparseable        -> allow

Body is read from whichever field the tool uses:
  - tool_input.body.Comment                 (reply / reply-all / forward comment)  [newlines stripped]
  - tool_input.body.Message.body.content    (send-mail, reply*/forward with full Message)
  - tool_input.body.body.content            (create-draft-email)

Fail-OPEN, EXCEPT for R1. The formatting rules are a quality gate, not a security
gate: any unexpected error allows the call (so a script bug can never strand the
user) but prints a warning to stderr. R1 is the one exception — it fails CLOSED,
because the failure it prevents is unrecoverable and a crash is not consent.

Kill switch: env CLAUDE_EMAIL_FORMAT_GATE_DISABLED=1 -> allow everything EXCEPT R1.
"""

import json
import os
import pathlib
import re
import tempfile
import time
import sys

# --- tunables -------------------------------------------------------------
MIN_LEN = 300  # bodies at or under this many visible chars are never blocked
DENSITY_FLOOR = 700  # only apply the "too few breaks for length" rule above this
DENSITY_DIVISOR = 700  # require >= visible_len // DENSITY_DIVISOR structural breaks

# Tools whose body we inspect. (send-draft-message has no body to judge — the
# body was set at draft-creation time, which IS gated below.)
GATED_TOOLS = {
    "mcp__ms365__send-mail",
    "mcp__ms365__reply-mail-message",
    "mcp__ms365__reply-all-mail-message",
    "mcp__ms365__create-reply-draft",
    "mcp__ms365__create-reply-all-draft",
    "mcp__ms365__create-draft-email",
    "mcp__ms365__create-forward-draft",
    "mcp__ms365__forward-mail-message",
    "mcp__ms365__update-mail-message",
    "mcp__ms365__send-draft-message",
}

# --- R1: drafts only ------------------------------------------------------
# Every tool here transmits mail the instant it is called. Each maps to the
# draft-creating tool that does the same composition WITHOUT transmitting, so the
# deny can tell the model what to call instead — a refusal that leaves the model
# guessing just gets retried in a slightly different shape.
SEND_TOOLS = {
    "mcp__ms365__send-mail": "create-draft-email",
    "mcp__ms365__reply-mail-message": "create-reply-draft",
    "mcp__ms365__reply-all-mail-message": "create-reply-all-draft",
    "mcp__ms365__forward-mail-message": "create-forward-draft",
    # send-draft-message transmits an ALREADY-composed draft, so there is nothing to
    # re-route to: the draft it would send is exactly what the operator should press
    # Send on themselves. None -> the deny text says that instead of naming a tool.
    "mcp__ms365__send-draft-message": None,
}

# --- R4: pre-write freshness ----------------------------------------------
# Reading the thread when you START composing is not reading it when you FINISH. On
# 2026-08-25 a dispute letter was reviewed for 23 minutes — MIME parsed, indentation and
# font verified twice — while the counterparty's automated acknowledgement, a written
# 24-hour commitment, sat unread in the inbox. It had arrived 23 minutes before the send.
# The letter went out saying "I was not given a callback time": true of the phone call,
# false of the record. Verifying the ARTIFACT is not verifying the SITUATION.
#
# WHY A LIST OF RECEIVED MAIL, AND NOTHING ELSE, SATISFIES THIS. In the final 20 minutes
# before that send the mailbox was queried SIX times. Every one was either scoped
# `isDraft eq true` or a get-mail-message-mime on our OWN draft. A gate that accepted "any
# mailbox read" would have passed all six and caught nothing.
#
# This is DELIBERATELY STRICTER than "a read of any message that is not our own draft".
# A PreToolUse hook sees only tool_name + tool_input, so on get-mail-message it has a
# messageId and no way to know whether that id is a draft this session just created — and
# reading back your own draft is step 4 of the RECIPE, i.e. the single most likely read to
# be sitting in the window. Counting it would reopen the exact hole. So single-message
# reads do not satisfy the gate; only a LIST that is not scoped to drafts does. That is
# cheap to satisfy (one call) and impossible to satisfy by accident.
FRESHNESS_ENV = "CC_MS365_FRESHNESS_MIN"
FRESHNESS_DEFAULT_MIN = 10

INBOUND_LIST_TOOLS = {
    "mcp__ms365__list-mail-messages",
    "mcp__ms365__list-mail-folder-messages",
    "mcp__ms365__list-mail-folder-messages-delta",
}

# The last AGENT operation in an email flow. Sends are human-executed now, so the draft
# WRITE is the only point a hook can still stand on.
DRAFT_WRITE_TOOLS = {
    "mcp__ms365__create-reply-draft",
    "mcp__ms365__create-reply-all-draft",
    "mcp__ms365__create-forward-draft",
    "mcp__ms365__create-draft-email",
    "mcp__ms365__update-mail-message",
}

_DRAFT_FILTER_RE = re.compile(r"isdraft\s+eq\s+true", re.IGNORECASE)
_DRAFTS_FOLDERS = {"drafts", "draftroot"}


def _is_draft_scoped(tool_input) -> bool:
    """True if this list call was restricted to our own drafts — the blind read."""
    folder = tool_input.get("mailFolderId")
    if isinstance(folder, str) and folder.strip().lower() in _DRAFTS_FOLDERS:
        return True
    for key in ("filter", "search"):
        value = tool_input.get(key)
        if isinstance(value, str) and _DRAFT_FILTER_RE.search(value):
            return True
    return False


def _freshness_marker():
    if not _SESSION_ID:
        return None
    return pathlib.Path(tempfile.gettempdir()) / f"cc-ms365-inbound-{_SESSION_ID}"


def record_inbound_read(tool_name: str, tool_input) -> None:
    """Stamp 'this session has looked at RECEIVED mail' — best effort, never fatal."""
    if tool_name not in INBOUND_LIST_TOOLS or not isinstance(tool_input, dict):
        return
    if _is_draft_scoped(tool_input):
        return
    marker = _freshness_marker()
    if marker is None:
        return
    try:
        marker.touch()
        os.utime(marker, None)
    except OSError:
        pass  # unwritable tmp -> the gate below fails open, which is the documented posture


def freshness_age_seconds():
    """Seconds since the last inbound read, or None if there has not been one."""
    marker = _freshness_marker()
    if marker is None:
        return None
    try:
        if not marker.exists():
            return None
        return max(0.0, time.time() - marker.stat().st_mtime)
    except OSError:
        return None


def _writes_content(tool_name: str, tool_input) -> bool:
    """update-mail-message is also how a message gets flagged or marked read. Only a call
    that actually sets a BODY is a compose step; gating the rest would be pure friction."""
    if tool_name != "mcp__ms365__update-mail-message":
        return True
    return bool(dig(tool_input, "body", "body", "content"))


# --- R2: alias continuity -------------------------------------------------
# The two aliases on this mailbox. Anything else in a `from`/`sender` is a typo, a
# hallucinated address, or another account's identity — all denied. This set is the
# ONLY part of R2 that is mechanically checkable here (see ALIAS NOTE in the module
# docstring: a PreToolUse hook cannot see which alias the thread is on).
KNOWN_ALIASES = {"ichris96@hotmail.com", "ren.chris@outlook.com"}

# What Graph uses when `from` is omitted. VERIFIED 2026-08-25, and it is the reason
# "just leave from unset" is NOT a safe rule: a reply draft created on a thread
# addressed to ren.chris@outlook.com came back from ichris96@hotmail.com. Graph
# applies the MAILBOX DEFAULT, not the thread's alias.
MAILBOX_DEFAULT_ALIAS = "ichris96@hotmail.com"

# Tag-open patterns that introduce a visible line/paragraph break in HTML.
_BREAK_TAG_RE = re.compile(
    r"<\s*(br|/p|p|div|/div|li|tr|h[1-6]|ul|ol|table|blockquote)\b", re.IGNORECASE
)
_TAG_RE = re.compile(r"<[^>]+>")
_WS_RE = re.compile(r"\s+")

# Fresh-message tools create a NEW message with no In-Reply-To/References headers.
# If the subject already carries a reply/forward prefix, a fresh send breaks the
# conversation chain (verified 2026-06-12: a create-draft-email "RE:" send did NOT
# thread; create-reply-draft DOES set In-Reply-To + References). Steer to a reply tool.
FRESH_SEND_TOOLS = {"mcp__ms365__send-mail", "mcp__ms365__create-draft-email"}
_REPLY_SUBJECT_RE = re.compile(r"^\s*(re|fw|fwd)\s*:", re.IGNORECASE)

# Reply/forward tools: Graph auto-quotes the prior message ONLY when you pass Comment.
# Passing Message.body REPLACES that auto-quote, so the chain threads correctly at the
# protocol level (In-Reply-To/References are still set) but arrives VISUALLY ORPHANED —
# the recipient sees a bare note with no history. Cost a real defect 2026-08-24: an
# A to Z reply went out threaded but with no visible chain, and the operator caught it
# in Outlook, not here. The pre-existing guard only inspected FRESH_SEND_TOOLS, so a
# reply carrying Message.body was never checked at all.
REPLY_TOOLS = {
    "mcp__ms365__reply-mail-message",
    "mcp__ms365__reply-all-mail-message",
    "mcp__ms365__create-reply-draft",
    "mcp__ms365__create-reply-all-draft",
    "mcp__ms365__create-forward-draft",
    "mcp__ms365__forward-mail-message",
}
# Any ONE of these in the body means a quoted chain was deliberately appended.
_QUOTE_MARKERS = (
    "<blockquote",
    "divrplyfwdmsg",  # Outlook's own reply/forward separator div
    "-----original message-----",
    "________________________________",  # Outlook's horizontal rule above a quote
    "wrote:",
    "from:",  # a quoted header block
)


def has_quoted_chain(content: str) -> bool:
    """True if the body appears to carry the prior message's text."""
    low = (content or "").lower()
    return any(m in low for m in _QUOTE_MARKERS)


# Injected into context on EVERY matched ms365 write call, so the model never has to
# recall it. Each rule below cost a real defect: the threading rule 2026-06-12 (a "RE:"
# fresh-send that silently did not thread); the quote-source and verification rules
# 2026-08-12 (the Vista Real pesticide reply, where get-mail-message's text/plain output
# was mistaken for lost HTML three separate times — once causing a good draft to be
# deleted and rebuilt, once flattening the entire quoted chain into one unbroken wall).
# Full provenance: memory feedback_email_formatting.
RECIPE = """ms365 email recipe (auto-injected — settled, do not re-derive):

0. NEVER SEND. You compose into DRAFTS; the operator presses Send. A Graph send is
   immediate and irreversible — there is no unsend on this path. send-mail,
   reply-mail-message, reply-all-mail-message, forward-mail-message and
   send-draft-message are DENIED and have no override; do not look for one, and do
   not ask for permission to send. Use create-draft-email / create-reply-draft /
   create-reply-all-draft / create-forward-draft, then tell the operator the draft is
   in Drafts and ready. update-mail-message still works for revising a draft in place.

1. THREADING. To continue a chain, reply on the ORIGINAL message: create-reply-all-draft /
   reply-all-mail-message with its messageId. NEVER send-mail or create-draft-email with a
   "RE:"/"FW:" subject — that makes a detached message with no In-Reply-To/References and
   silently breaks the chain.

1b. WHICH FIELD — this is the one that bites. Graph auto-quotes the original ONLY when you
   pass **Comment**. Passing **Message.body REPLACES that auto-quote**, so the reply threads
   correctly but arrives with NO VISIBLE HISTORY — it reads to the recipient as a brand-new
   email. So: **short reply (<=300 visible chars) -> use Comment.** Longer or formatted ->
   **the placeholder splice (rule 3)**, which gets you both. Do NOT hand-type a quote block.
   Hook-enforced: a reply tool passing Message.body with no quote block is now DENIED.
   ⚠️ **Comment INHERITS THE ORIGINAL SENDER'S CARRIER DOCUMENT** — Graph drops your text inside
   their <body> tag AND copies their <style> blocks into the draft's <head> (measured
   2026-08-25). Two things leak, not one: `body{color:red}` (Montway's confirmation carries it,
   so a Comment reply renders ENTIRELY RED) and generic element rules like `p{margin:0}`, which
   silently collapse YOUR paragraph spacing. **The splice does not fix this by itself** — the
   carrier document is above the cut. The fix is to make your own fragment self-defending: an
   explicit `color:#000000` on your wrapper div and an explicit inline `margin` on EVERY block
   element. Inline styles beat both an inherited body colour and a copied stylesheet rule.
   ms365-reply-splice.py warns when your fragment omits either.

2. FORMATTING. Pass Message.body {contentType:"html"} wrapped in an inline
   font-family:Calibri,Arial,sans-serif;font-size:11pt style, with real <p>/<ul>/<ol>.
   Never put more than ~300 chars in `Comment` — Graph strips its newlines into one
   paragraph.

3. LONG + FORMATTED + GENUINE MULTI-LEVEL CHAIN — THE PLACEHOLDER SPLICE. Let Graph build
   the quote, then replace only YOUR half. Never hand-author a quote block: a hand-typed
   quote is an assertion, Graph's is the record, and a rebuilt one was rejected outright in
   a live dispute (2026-08-25). Four steps:
     a. create-reply-all-draft with a SHORT placeholder Comment (e.g. "."). Graph returns a
        draft carrying its OWN quote — as many levels deep as the original already was.
     b. download-bytes-to-file on /me/messages/<THAT DRAFT'S id>/$value, to disk. MIME works
        on drafts, and going to disk keeps a 30KB body out of context.
     c. $HOME/.claude/bin/ms365-reply-splice.py --draft-mime d.eml --body yours.html --out spliced.html
        --placeholder . --assert-depth N. It cuts at Graph's own <div id="divRplyFwdMsg">
        and keeps everything below byte-identical. It REFUSES on a missing separator, a
        surviving placeholder, or a chain shallower than N.
     d. update-mail-message with the spliced body. Verified 2026-08-25: In-Reply-To and
        References survive the PATCH, and recipients + the `from` alias can be set in the
        SAME call (see rule 5).
   ⚠️ DEPTH IS A PROPERTY OF THE MESSAGE YOU REPLY TO, not of this flow. Graph quotes that
   one message, whose own HTML supplies every deeper level. An auto-generated confirmation
   or receipt quotes NOTHING, so replying to one can only ever yield 1 level, no matter what
   you do. To get N levels, reply to the message that ACTUALLY carries the chain.
   ⚠️ Graph SANITISES what it quotes (strips MSO conditional comments, drops some <body>
   attributes). That is Outlook's own reproduction — the same thing a human clicking Reply
   gets — not a defect, and not something to "fix" by substituting the raw original.

4. VERIFYING — ON THE DRAFT ITSELF, no send involved. get-mail-message ALWAYS reports
   contentType "text": that is the READER handing back the text/plain alternative, NOT
   evidence the HTML was lost. The valid check is get-mail-message-mime — and it WORKS
   ON A DRAFT. Verified 2026-08-25: a draft messageId returned full RFC-822 source with
   both MIME parts plus From:, In-Reply-To: and References:. So build the draft, then run
   get-mail-message-mime on THAT DRAFT'S OWN id and inspect what you get.
   ⚠️ The old rule here said "Drafts have no MIME" and told you to DRY RUN by swapping
   recipients to yourself and SENDING. Both halves are dead: the premise was false, and
   sending is denied outright (rule 0). Verifying a draft costs one read now.

5. SENDER ALIAS — MATCH THE THREAD. This mailbox has TWO aliases: ichris96@hotmail.com
   and ren.chris@outlook.com. THE INVARIANT: an outgoing message uses the alias the
   counterparty already has for THAT thread. Derive it — read the original's
   toRecipients/ccRecipients and see which of the two they wrote to. Never default.
   ⚠️ Graph will NOT do this for you. A reply inherits the MAILBOX DEFAULT
   (ichris96@hotmail.com), not the thread's alias — verified 2026-08-25 on a thread
   addressed to ren.chris, whose reply draft came back from ichris96. So: thread on
   ichris96 -> the default is already correct, leave from unset. Thread on ren.chris ->
   you MUST set the alias explicitly.
   ⚠️ This used to add "Comment mode CANNOT set from, so a ren.chris thread needs
   Message.body". That inference is DEAD (measured 2026-08-25): the create call cannot set
   `from`, but update-mail-message CAN — a PATCH carrying {"from": …, "ccRecipients": […]}
   on a Comment-created draft was read back with both applied. So a ren.chris thread is no
   longer a reason to abandon the auto-quote: use the rule-3 splice and set the alias on the
   PATCH. Nothing about the alias forces you to hand-build a chain any more.
   Confirm on the finished draft with rule 4 and read its From: header.
   Hook-enforced: a from/sender outside those two addresses is DENIED. The hook CANNOT
   check thread-match — a PreToolUse hook sees only the request, never Graph's response —
   so that half is yours. Your backstop is that the operator sees From in Outlook.
   WHY THIS RULE EXISTS: it used to read "set from = ren.chris@outlook.com" flatly. Every
   Montway email on order #3414154 was addressed to ichris96; the dispatch-hold request
   went out from ren.chris, an address they had never seen on that order. They dispatched
   and charged $1,779 the next morning. The old rule did not merely fail to help — it
   overrode a default that was already correct.
   Display name is not settable per-message on this account.

6. FRESHNESS — RE-READ RECEIVED MAIL BEFORE YOU SAY "READY". Hook-enforced (R4): a draft
   write is DENIED unless this session listed received mail within CC_MS365_FRESHNESS_MIN
   (default 10) minutes. Reading the thread when you START composing is not reading it when
   you FINISH — a letter reviewed for 23 minutes shipped contradicting an acknowledgement
   that had arrived 23 minutes before. Verifying the ARTIFACT is not verifying the SITUATION.
     list-mail-messages  filter: from/emailAddress/address eq '<counterparty>'
                                 and receivedDateTime ge <ISO-8601 UTC when you started>
   ⚠️ Do NOT add `orderby` to that compound filter — Graph returns InefficientFilter for the
   pair. Filter alone works; sort the handful of results yourself.
   ⚠️ A read of your OWN draft does NOT satisfy this, nor does a list scoped `isDraft eq
   true` — six such reads in the last 20 minutes are exactly what missed the message. Only a
   LIST of received mail counts. Anything new: read it and re-check every factual claim in
   the draft before handing it over."""


_SESSION_ID = None

# Set by the R2 alias arm when a call carries an explicit sender. Picked up by allow() so
# the advisory reaches the model on a PERMITTED call — the surfaced half of R2.
_ADVISORY = ""

# The raw stdin payload, stashed at module scope so the crash handler can re-inspect it
# after main() has died — it needs to know whether the dead call was a SEND.
_RAW_PAYLOAD = ""


def _recipe_once() -> str:
    """Return RECIPE the first time this session touches mail, "" afterwards.

    The recipe is ~1.8KB; a mail-heavy session makes dozens of ms365 calls, so
    re-injecting on every one would be pure waste. Once, early, is enough — it lands
    while the model is still reading the thread, before it composes anything.
    """
    if not _SESSION_ID:
        return ""
    marker = pathlib.Path(tempfile.gettempdir()) / f"cc-ms365-recipe-{_SESSION_ID}"
    try:
        if marker.exists():
            return ""
        marker.touch()
    except OSError:
        return ""  # can't track it — stay quiet rather than spam
    return RECIPE


def allow(note: str = ""):
    """Emit an explicit allow and exit. (Silence would also allow, but being
    explicit keeps the transcript readable and matches the documented contract.)

    `note` carries an advisory the model should see even though the call is permitted —
    used for the half of R2 this hook can surface but not enforce. It is appended to the
    recipe rather than replacing it, so a first-touch call still gets both.
    """
    out = {
        "hookEventName": "PreToolUse",
        "permissionDecision": "allow",
        "permissionDecisionReason": "email-format gate: body OK (or nothing to judge)",
    }
    context = "\n\n".join(p for p in (_recipe_once(), note or _ADVISORY) if p)
    if context:
        out["additionalContext"] = context
    print(json.dumps({"hookSpecificOutput": out}))
    sys.exit(0)


def deny(reason: str):
    # Unlike allow(), this ALWAYS carries the recipe: a blocked send is precisely the
    # moment the rules are needed, and it fires at most a handful of times.
    print(
        json.dumps(
            {
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "deny",
                    "permissionDecisionReason": reason,
                    "additionalContext": RECIPE,
                }
            }
        )
    )
    sys.exit(0)


def dig(d, *keys):
    """Safe nested .get; returns None if any level is missing/not a dict.

    Key lookup is case-insensitive at each level. The ms365 server has shipped BOTH
    `Message` and `message` as the envelope key (current tools use lowercase), and a
    case-sensitive lookup silently found neither — which made this whole gate inert on
    the send-mail / reply* paths. Found 2026-08-12 while wiring the recipe injection.
    """
    cur = d
    for k in keys:
        if not isinstance(cur, dict):
            return None
        if k in cur:
            cur = cur.get(k)
            continue
        lk = k.lower()
        match = next(
            (kk for kk in cur if isinstance(kk, str) and kk.lower() == lk), None
        )
        if match is None:
            return None
        cur = cur.get(match)
    return cur


def extract_body(tool_input):
    """Return (content, content_type, source) for the most substantive body field.

    source: "comment" (reply/forward Comment — Graph strips its newlines, so \\n is
    NOT a reliable break here), "message" (send-mail / reply Message.body), or
    "draft" (create-draft-email body). Empty -> ("", None, None).
    """
    body = tool_input.get("body")
    if not isinstance(body, dict):
        return "", None, None

    candidates = []  # (content, content_type, source)

    comment = body.get("Comment")
    if isinstance(comment, str) and comment.strip():
        candidates.append((comment, "text", "comment"))

    msg_content = dig(body, "Message", "body", "content")
    if isinstance(msg_content, str) and msg_content.strip():
        candidates.append(
            (msg_content, dig(body, "Message", "body", "contentType"), "message")
        )

    draft_content = dig(body, "body", "content")
    if isinstance(draft_content, str) and draft_content.strip():
        candidates.append((draft_content, dig(body, "body", "contentType"), "draft"))

    if not candidates:
        return "", None, None

    # The real message is the longest candidate (Graph rejects Comment+Message together).
    return max(candidates, key=lambda c: len(c[0]))


def analyze(content: str):
    """Return (visible_len, html_breaks, newline_breaks) — counted separately because
    only one of them actually renders, depending on the body's content type."""
    html_breaks = len(_BREAK_TAG_RE.findall(content))
    newline_breaks = content.count("\n")

    # Visible length: strip tags, collapse whitespace.
    visible = _TAG_RE.sub(" ", content)
    visible = _WS_RE.sub(" ", visible).strip()
    return len(visible), html_breaks, newline_breaks


def extract_from_alias(tool_input):
    """Return the explicit sender address in this call, lowercased, or None.

    Graph accepts `from` in two envelope shapes — body.Message.from (send-mail, the
    reply/forward drafts) and body.from (create-draft-email / update-mail-message) — and
    `sender` is a second, rarer spelling of the same thing. All are checked; dig() is
    case-insensitive, which is what makes this reach the `Message` vs `message` variants
    the ms365 server has shipped at different times.
    """
    body = tool_input.get("body")
    if not isinstance(body, dict):
        return None
    for path in (
        ("Message", "from", "emailAddress", "address"),
        ("Message", "sender", "emailAddress", "address"),
        ("from", "emailAddress", "address"),
        ("sender", "emailAddress", "address"),
    ):
        value = dig(body, *path)
        if isinstance(value, str) and value.strip():
            return value.strip().lower()
    return None


def main():
    global _RAW_PAYLOAD
    raw = _RAW_PAYLOAD = sys.stdin.read()
    if not raw.strip():
        allow()

    data = json.loads(raw)
    global _SESSION_ID
    _SESSION_ID = data.get("session_id") or None
    tool_name = data.get("tool_name", "")

    # ── R1: DRAFTS ONLY ───────────────────────────────────────────────────────────
    # Deliberately ABOVE the kill switch and above the GATED_TOOLS scoping. A Graph send
    # cannot be undone, so this arm may not be disabled by an env var, softened by a
    # short body, or skipped because some later guard would have allowed the call.
    if tool_name in SEND_TOOLS:
        replacement = SEND_TOOLS[tool_name]
        short = tool_name.split("__")[-1]
        if replacement:
            fix = (
                f"Call {replacement} instead — same arguments, same threading, but it "
                f"lands in Drafts rather than transmitting. Then tell the operator the "
                f"draft is ready for review."
            )
        else:
            fix = (
                "There is nothing to re-route to: the draft this would transmit is "
                "already composed, and it is the operator who presses Send on it. Tell "
                "them it is in Drafts and ready. Use update-mail-message to revise it."
            )
        deny(
            f"BLOCKED (R1, drafts only): {short} TRANSMITS mail immediately and a Graph "
            f"send cannot be recalled — Outlook's 'undo send' is a client-side delay that "
            f"does not exist on this path. The agent composes; the operator sends. {fix} "
            f"This rule is ABSOLUTE: there is no env override and no 'the user approved "
            f"it' exception, because a model asserting that approval is precisely the "
            f"failure this prevents (2026-08-24: three sends in one evening, one "
            f"authorized, one a legally operative §1950.5(f) notice in a live dispute). "
            f"Do not retry this call in another shape and do not ask to send."
        )

    tool_input = data.get("tool_input")
    if not isinstance(tool_input, dict):
        tool_input = {}

    # Bookkeeping BEFORE the scoping check: the read tools that satisfy R4 are not in
    # GATED_TOOLS and would exit at the next branch, so recording below it would mean the
    # gate never observed a single inbound read and denied every draft forever.
    record_inbound_read(tool_name, tool_input)

    if os.environ.get("CLAUDE_EMAIL_FORMAT_GATE_DISABLED") == "1":
        allow()

    if tool_name not in GATED_TOOLS:
        allow()

    if not tool_input:
        allow()

    # ── R4: PRE-WRITE FRESHNESS ───────────────────────────────────────────────────────
    # Placed FIRST among the content guards on purpose: checking the situation precedes
    # checking the artifact. A perfectly formatted letter about a fact that changed 23
    # minutes ago is the failure this whole arm exists for.
    if tool_name in DRAFT_WRITE_TOOLS and _writes_content(tool_name, tool_input):
        try:
            window_min = float(os.environ.get(FRESHNESS_ENV, FRESHNESS_DEFAULT_MIN))
        except (TypeError, ValueError):
            window_min = FRESHNESS_DEFAULT_MIN

        marker = _freshness_marker()
        if window_min > 0 and marker is not None:
            # Distinguish "never read" from "cannot record". They both surface as a missing
            # marker, and denying because tmp is unwritable would strand the operator over a
            # hook problem. Probe first; an unwritable tmp fails OPEN.
            try:
                probe = marker.with_name(marker.name + ".probe")
                probe.touch()
                probe.unlink()
            except OSError:
                allow()

            age = freshness_age_seconds()
            if age is None or age > window_min * 60:
                when = (
                    "this session has not listed received mail at all"
                    if age is None
                    else f"the last one was {int(age // 60)} min {int(age % 60)} s ago"
                )
                deny(
                    f"BLOCKED (R4, freshness): you are writing draft content but {when}, and the "
                    f"window is {window_min:g} min. Reading the thread when you STARTED composing "
                    f"is not reading it when you FINISH. On 2026-08-25 a dispute letter was "
                    f"reviewed for 23 minutes while the counterparty's automated acknowledgement — "
                    f"a written 24-hour commitment — sat unread, having arrived 23 min earlier; the "
                    f"letter shipped asserting something the record already contradicted. "
                    f"Verifying the ARTIFACT is not verifying the SITUATION.\n"
                    f"FIX — re-query the counterparty for anything that landed since you began, "
                    f"then retry this call:\n"
                    f"  list-mail-messages  filter: from/emailAddress/address eq '<counterparty>' "
                    f"and receivedDateTime ge <ISO-8601 UTC when you started>\n"
                    f"  (Do NOT add orderby to that compound filter — Graph rejects the pair with "
                    f"InefficientFilter. Filter alone works; sort the few results yourself.)\n"
                    f"Anything new: read it and re-check every factual claim in the draft before "
                    f"telling the operator it is ready. NOTE a read of your OWN draft does not "
                    f"count, and neither does a list scoped `isDraft eq true` — six such reads in "
                    f"the last 20 minutes are exactly what missed the acknowledgement. "
                    f"Override: {FRESHNESS_ENV}=0, or CLAUDE_EMAIL_FORMAT_GATE_DISABLED=1."
                )

    # ── R2: ALIAS CONTINUITY ──────────────────────────────────────────────────────
    # Enforceable half: the address must be one this mailbox actually owns. The
    # thread-match half is NOT checkable here (no access to Graph's response), so a
    # well-formed alias is allowed WITH an advisory rather than waved through silently.
    alias = extract_from_alias(tool_input)
    if alias is not None and alias not in KNOWN_ALIASES:
        deny(
            f"BLOCKED (R2, alias): from/sender is '{alias}', which is not an address this "
            f"mailbox owns. The only two aliases are "
            f"{' and '.join(sorted(KNOWN_ALIASES))}. Graph would reject this outright or "
            f"send under an identity the operator does not control. Pick the alias the "
            f"counterparty already has for THIS thread: read the original's "
            f"toRecipients/ccRecipients and match whichever of the two they wrote to."
        )
    if alias is not None:
        # NOT an early allow(): the formatting, quote and threading guards below still
        # have to run. Stash the advisory so whichever allow() eventually fires carries
        # it. (Returning here would have made "set a from" a bypass for all of R3.)
        global _ADVISORY
        _ADVISORY = (
            f"ALIAS CHECK (advisory — this hook cannot verify it). You set from='{alias}'. "
            f"That must be the alias the counterparty already has for THIS thread, taken "
            f"from the original's toRecipients/ccRecipients — not a default. A reply from "
            f"an address they have never seen on the thread can be filed against no order: "
            f"Montway #3414154 was addressed to ichris96 throughout, the hold request went "
            f"from ren.chris, and they dispatched and charged $1,779 anyway. If the thread "
            f"is on {MAILBOX_DEFAULT_ALIAS} you can simply omit `from` — that is already "
            f"Graph's default. Confirm on the finished draft with get-mail-message-mime "
            f"(it works on drafts) and read its From: header."
        )

    # Quote guard: a reply tool passing Message.body silently REPLACES Graph's auto-quote,
    # producing a message that threads but shows no history. Comment keeps the auto-quote.
    if tool_name in REPLY_TOOLS:
        body = tool_input.get("body")
        if isinstance(body, dict):
            content = dig(body, "Message", "body", "content")
            comment = body.get("Comment")
            if (
                isinstance(content, str)
                and content.strip()
                and not has_quoted_chain(content)
            ):
                visible = len(re.sub(r"<[^>]+>", "", content)).__int__()
                short_hint = (
                    "This reply is SHORT — the one-line fix is to drop Message.body entirely and "
                    "pass Comment instead; Graph then auto-quotes the original for you and you "
                    "need no MIME fetch at all. "
                    if visible <= MIN_LEN
                    else "This reply is long enough that Comment would collapse its newlines, so use "
                    "the PLACEHOLDER SPLICE below rather than shortening it. "
                )
                deny(
                    "BLOCKED: "
                    + tool_name.split("__")[-1]
                    + " with Message.body and NO quoted chain. Passing Message.body REPLACES "
                    "Graph's auto-quote, so this threads correctly (In-Reply-To/References are "
                    "still set) but the recipient sees a bare note with NO visible history — it "
                    "reads as a brand-new email. Caught in Outlook, not here, on 2026-08-24. "
                    + short_hint
                    + "DO NOT hand-author a quote block to satisfy this guard — a typed quote is an "
                    "assertion, Graph's is the record, and a rebuilt one was rejected outright in a "
                    "live dispute (2026-08-25). Use the PLACEHOLDER SPLICE instead: (1) create this "
                    "draft with a short placeholder Comment so Graph builds its own quote, at the "
                    "original's full depth; (2) download-bytes-to-file on the DRAFT's own "
                    "/me/messages/<id>/$value; (3) $HOME/.claude/bin/ms365-reply-splice.py "
                    "--draft-mime d.eml "
                    "--body yours.html --out spliced.html --placeholder . --assert-depth N; "
                    "(4) update-mail-message with the result — In-Reply-To/References survive, and "
                    "recipients and the `from` alias can be set in the same PATCH. Full rationale: "
                    "docs/research/reply-chain-preservation-2026-08-25.md. "
                    "Override for a deliberately quote-free reply: "
                    "CLAUDE_EMAIL_FORMAT_GATE_DISABLED=1."
                )
            if isinstance(comment, str) and len(comment) > MIN_LEN:
                deny(
                    "BLOCKED: Comment is "
                    + str(len(comment))
                    + " chars (>"
                    + str(MIN_LEN)
                    + "). Graph strips newlines from Comment into one unreadable paragraph at "
                    "this length. Use Message.body contentType:'html' instead — and then you "
                    "MUST append the quoted chain yourself, because Message.body replaces the "
                    "auto-quote."
                )

    # Threading guard: a fresh-send tool carrying a reply/forward subject would start a
    # detached message instead of continuing the thread. Steer to a reply tool.
    if tool_name in FRESH_SEND_TOOLS:
        body = tool_input.get("body")
        subj = ""
        if isinstance(body, dict):
            s = dig(body, "Message", "subject") or dig(body, "subject")
            subj = s if isinstance(s, str) else ""
        if _REPLY_SUBJECT_RE.match(subj):
            deny(
                f"BLOCKED: {tool_name.split('__')[-1]} creates a NEW message, but the subject "
                f"'{subj.strip()[:60]}' is a reply/forward. A fresh send has no In-Reply-To/"
                f"References headers, so it will NOT continue the thread — it starts a detached "
                f"message (this broke the UBC Sleep Clinic chain 2026-06-12). To continue the "
                f"conversation, reply on the ORIGINAL message via create-reply-draft / "
                f"reply-mail-message, passing a SHORT reply as Comment (Graph auto-quotes for you) or a long one as Message.body contentType:'html' WITH the quote appended "
                f"(threads AND keeps formatting). "
                f"(Override for a genuine new thread: set env CLAUDE_EMAIL_FORMAT_GATE_DISABLED=1.)"
            )

    content, ctype, source = extract_body(tool_input)
    if not content:
        allow()

    visible_len, html_breaks, newline_breaks = analyze(content)

    if visible_len <= MIN_LEN:
        allow()

    # The reply/forward `Comment` field strips newlines on plain-text replies, so a
    # multi-paragraph Comment collapses into a wall regardless of how many \n it has.
    # \n is NOT a reliable break here — steer to an explicit HTML Message.body.
    if source == "comment":
        deny(
            f"BLOCKED: this is a {visible_len}-char reply in the `Comment` field. "
            f"Microsoft Graph strips newlines from reply comments, so it will send as "
            f"one unreadable paragraph (exactly what broke the UBC Sleep Clinic reply). "
            f"Put the reply text in `Message.body` instead, with contentType:'html' and "
            f"<p>…</p> per paragraph — Graph keeps those breaks. (A Message.body reply "
            f"omits the quoted thread, which is fine for a re-send.) "
            f"(Override for this one send: set env CLAUDE_EMAIL_FORMAT_GATE_DISABLED=1.)"
        )

    # Message.body / draft body: only the break mechanism matching the content type
    # actually renders — HTML tags for html, raw newlines for text.
    if (ctype or "").lower() == "html":
        breaks = html_breaks
        fix = "wrap each paragraph in <p>…</p> or separate them with <br>"
    else:
        breaks = newline_breaks
        fix = "separate paragraphs with a blank line ('\\n\\n')"

    if breaks == 0:
        deny(
            f"BLOCKED: email body is a {visible_len}-char wall of text with NO line "
            f"breaks — it will render as one unreadable paragraph. Fix: {fix}. "
            f"(Override for this one send: set env CLAUDE_EMAIL_FORMAT_GATE_DISABLED=1.)"
        )

    need = visible_len // DENSITY_DIVISOR
    if visible_len > DENSITY_FLOOR and breaks < need:
        deny(
            f"BLOCKED: email body is {visible_len} visible chars but has only "
            f"{breaks} line/paragraph break(s) — too dense to read comfortably "
            f"(expected at least {need}). Fix: {fix}. "
            f"(Override for this one send: set env CLAUDE_EMAIL_FORMAT_GATE_DISABLED=1.)"
        )

    allow()


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception as exc:  # fail OPEN — never strand a legit draft on a hook bug
        # ...EXCEPT for R1. If the crash happened on a send tool we must still deny: an
        # allow here would transmit irreversibly, and "the hook broke" is not consent.
        # Re-read the payload independently of whatever main() was doing when it died,
        # and treat an unreadable payload on this path as a send (deny) rather than
        # guessing. This is the one place the gate is closed rather than open.
        # Substring match on the RAW payload, not a re-parse: the crash may well have BEEN
        # a parse failure, and a send must stay denied even when the JSON is unreadable.
        # Scoping it to the send-tool names keeps a malformed READ payload failing open,
        # so a hook bug can never take the whole mail surface down.
        if any(t in (_RAW_PAYLOAD or "") for t in SEND_TOOLS):
            print(
                json.dumps(
                    {
                        "hookSpecificOutput": {
                            "hookEventName": "PreToolUse",
                            "permissionDecision": "deny",
                            "permissionDecisionReason": (
                                f"BLOCKED (R1, drafts only): the email guard crashed "
                                f"({exc}) on a call that would TRANSMIT mail. Denying "
                                f"rather than failing open — a Graph send cannot be "
                                f"recalled. Use a create-*-draft tool instead."
                            ),
                            "additionalContext": RECIPE,
                        }
                    }
                )
            )
            sys.exit(0)
        sys.stderr.write(
            f"[enforce-email-formatting] non-fatal hook error, allowing: {exc}\n"
        )
        # Emit an explicit allow rather than relying on empty-stdout semantics.
        print(
            json.dumps(
                {
                    "hookSpecificOutput": {
                        "hookEventName": "PreToolUse",
                        "permissionDecision": "allow",
                        "permissionDecisionReason": "email-format gate: hook error, failing open",
                    }
                }
            )
        )
        sys.exit(0)
