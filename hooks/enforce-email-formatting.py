#!/usr/bin/env python3
"""
enforce-email-formatting.py — PreToolUse hook for readable outbound email.

Fires on the ms365 mail send/draft tools. Blocks the call when the message body
would render as a "wall of text".

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

Fail-OPEN: this is a quality gate, not a security gate. Any unexpected error
allows the send (so a script bug can never strand the user) but prints a
warning to stderr. Contrast curl-gate.py, which fails closed.

Kill switch: env CLAUDE_EMAIL_FORMAT_GATE_DISABLED=1 -> allow everything.
"""

import json
import os
import re
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
    "mcp__ms365__create-draft-email",
    "mcp__ms365__create-forward-draft",
    "mcp__ms365__forward-mail-message",
}

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


# Injected into context on EVERY matched ms365 write call, so the model never has to
# recall it. Each rule below cost a real defect: the threading rule 2026-06-12 (a "RE:"
# fresh-send that silently did not thread); the quote-source and verification rules
# 2026-08-12 (the Vista Real pesticide reply, where get-mail-message's text/plain output
# was mistaken for lost HTML three separate times — once causing a good draft to be
# deleted and rebuilt, once flattening the entire quoted chain into one unbroken wall).
# Full provenance: memory feedback_email_formatting.
RECIPE = """ms365 email recipe (auto-injected — settled, do not re-derive):

1. THREADING. To continue a chain, reply on the ORIGINAL message: create-reply-all-draft /
   reply-all-mail-message with its messageId. NEVER send-mail or create-draft-email with a
   "RE:"/"FW:" subject — that makes a detached message with no In-Reply-To/References and
   silently breaks the chain.

2. FORMATTING. Pass Message.body {contentType:"html"} wrapped in an inline
   font-family:Calibri,Arial,sans-serif;font-size:11pt style, with real <p>/<ul>/<ol>.
   Never put more than ~300 chars in `Comment` — Graph strips its newlines into one
   paragraph.

3. VISIBLE QUOTED CHAIN. Passing Message.body REPLACES the auto-quote, so the visible
   history disappears. To keep it, append the prior message's HTML — and take that HTML
   from get-mail-message-mime parsed with Python's email module (walk to the text/html
   part, strip html/head/body/meta wrappers). NEVER from get-mail-message: it returns
   text/plain, and pasting plain text into HTML collapses every paragraph, table and
   nested reply into one unreadable wall.

4. VERIFYING. get-mail-message ALWAYS reports contentType "text". That is the READER
   handing back the text/plain alternative — it is NOT evidence the HTML was lost. The
   only valid check is get-mail-message-mime. Drafts have no MIME, so to check a draft do
   a DRY RUN: build it, swap recipients to the user alone, send, inspect that copy's MIME.
   Do this before any high-stakes threaded reply, and make the dry run byte-identical to
   the real body INCLUDING the quote block — a dry run that omits the risky part tests
   nothing.

5. SENDER. Set from = ren.chris@outlook.com; Graph otherwise defaults to the ichris96
   alias. Display name is not settable per-message on this account."""


def allow():
    """Emit an explicit allow and exit. (Silence would also allow, but being
    explicit keeps the transcript readable and matches the documented contract.)"""
    print(
        json.dumps(
            {
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "allow",
                    "permissionDecisionReason": "email-format gate: body OK (or nothing to judge)",
                    "additionalContext": RECIPE,
                }
            }
        )
    )
    sys.exit(0)


def deny(reason: str):
    print(
        json.dumps(
            {
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "deny",
                    "permissionDecisionReason": reason,
                }
            }
        )
    )
    sys.exit(0)


def dig(d, *keys):
    """Safe nested .get; returns None if any level is missing/not a dict."""
    cur = d
    for k in keys:
        if not isinstance(cur, dict):
            return None
        cur = cur.get(k)
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


def main():
    if os.environ.get("CLAUDE_EMAIL_FORMAT_GATE_DISABLED") == "1":
        allow()

    raw = sys.stdin.read()
    if not raw.strip():
        allow()

    data = json.loads(raw)
    tool_name = data.get("tool_name", "")
    if tool_name not in GATED_TOOLS:
        allow()

    tool_input = data.get("tool_input")
    if not isinstance(tool_input, dict):
        allow()

    # Threading guard: a fresh-send tool carrying a reply/forward subject would start a
    # detached message instead of continuing the thread. Steer to a reply tool.
    if tool_name in FRESH_SEND_TOOLS:
        body = tool_input.get("body")
        subj = ""
        if isinstance(body, dict):
            s = (
                dig(body, "Message", "subject")
                if tool_name == "mcp__ms365__send-mail"
                else body.get("subject")
            )
            subj = s if isinstance(s, str) else ""
        if _REPLY_SUBJECT_RE.match(subj):
            deny(
                f"BLOCKED: {tool_name.split('__')[-1]} creates a NEW message, but the subject "
                f"'{subj.strip()[:60]}' is a reply/forward. A fresh send has no In-Reply-To/"
                f"References headers, so it will NOT continue the thread — it starts a detached "
                f"message (this broke the UBC Sleep Clinic chain 2026-06-12). To continue the "
                f"conversation, reply on the ORIGINAL message via create-reply-draft / "
                f"reply-mail-message, passing the body as Message.body contentType:'html' "
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
    except Exception as exc:  # fail OPEN — never strand a legit send on a hook bug
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
