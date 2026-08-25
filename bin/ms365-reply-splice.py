#!/usr/bin/env python3
"""ms365-reply-splice.py — put a long, formatted body ABOVE Graph's own quoted chain.

THE BIND THIS SOLVES
--------------------
Microsoft Graph gives you two mutually exclusive things on a reply:

  * `Comment`        -> Graph builds the reply body itself and appends the ORIGINAL's
                        full quoted chain, however many levels deep it already was.
                        But: the comment is capped at ~300 usable chars (Graph strips
                        its newlines), and Graph drops your text INSIDE the original
                        sender's <body> tag, so a vendor template's `color:red`
                        becomes YOUR text's colour.
  * `Message.body`   -> arbitrary length and full styling control, but it REPLACES
                        Graph's auto-quote outright. The reply threads (In-Reply-To /
                        References are still set) and shows no history at all.

Hand-typing a quote block to fill that gap is what this script exists to prevent.
A hand-typed quote is an assertion; Graph's is the record. On 2026-08-25 a reply in a
live commercial dispute was rejected by the operator for exactly that reason.

THE MECHANISM
-------------
Create the reply draft with a SHORT placeholder `Comment`. Graph then builds the draft
WITH its native quote. Read that draft back, cut it at Graph's own separator, and keep
everything from the separator down verbatim; replace only the placeholder above it.
PATCH the draft with the result. Nothing in the quoted region is authored by a model.

This script is the cut-and-rejoin step, and only that step. It does no network I/O —
the ms365 MCP server holds the Graph token and there is no supported way to borrow it,
so the two Graph calls stay with the caller. See the module docs in
docs/research/reply-chain-preservation-2026-08-25.md.

USAGE
    ms365-reply-splice.py --draft-mime draft.eml --body new.html --out spliced.html \
        --placeholder PLACEHOLDER_XYZZY --assert-depth 2

Exit codes: 0 ok · 1 usage/IO error · 2 splice refused (marker missing, depth
regression, placeholder survived). A refusal is deliberate: shipping a reply whose
chain silently lost a level is the failure mode this whole flow exists to prevent.
"""

from __future__ import annotations

import argparse
import re
import sys

# Graph's reply separator. Two shapes have been observed on this mailbox and the
# attribute ORDER differs between them, so never anchor on the <hr>'s attributes:
#   <hr tabindex="-1" style="display:inline-block; width:98%"><div id="divRplyFwdMsg" …>
#   <hr style="display:inline-block;width:98%" tabindex="-1">…<div id="divRplyFwdMsg" …>
# The stable anchor is the div's id. We locate that, then walk back to the <hr> that
# immediately precedes it so the horizontal rule stays with the quote.
_RPLY_DIV = re.compile(r'<div\b[^>]*\bid=["\']?divRplyFwdMsg["\']?', re.IGNORECASE)
_HR = re.compile(r"<hr\b[^>]*>", re.IGNORECASE)

# Outlook's other separator, used when the original was plain text or came from a
# non-Outlook client. Checked as a fallback so a plain-text counterparty still works.
_HR_RULE_TEXT = re.compile(r"_{20,}")

_BODY_OPEN = re.compile(r"<body\b[^>]*>", re.IGNORECASE)

# A quoted header block — one per level of nesting. Counted to prove the chain did not
# lose a level. Matches Outlook's own (`<b>From:</b>`) and the plain forms that other
# clients and mailer templates emit inside their own quoted history.
_LEVEL = re.compile(
    r"(?:<b>\s*From:\s*</b>|(?<![\w-])From:\s*(?:&lt;|<|\w))", re.IGNORECASE
)

# A colour declaration on the carrier document that YOUR text would inherit. Graph
# copies the original's <body> attributes AND its <style> blocks into the draft, so a
# vendor stylesheet's `body{color:red}` reaches your paragraphs too.
_INHERITED_COLOR = re.compile(r"color\s*:\s*(?!inherit)([#\w(),.%\s-]+)", re.IGNORECASE)


def read(path: str) -> str:
    if path == "-":
        return sys.stdin.read()
    with open(path, encoding="utf-8", errors="replace") as fh:
        return fh.read()


def html_from_mime(raw: str) -> str:
    """Pull the text/html part out of an RFC-822 message.

    Drafts DO have MIME — `get-mail-message-mime` works on a draft's own id. (The
    older recipe claimed otherwise and sent people down a dry-run-by-sending path.)
    """
    import email
    from email import policy

    msg = email.message_from_string(raw, policy=policy.default)
    for part in msg.walk():
        if part.get_content_type() == "text/html":
            return part.get_content()
    raise SystemExit("error: no text/html part in that MIME source")


def find_cut(draft: str) -> tuple[int, str]:
    """Return (offset where the quoted region begins, which marker matched)."""
    div = _RPLY_DIV.search(draft)
    if div:
        # Walk back to the <hr> immediately before the div, if there is one.
        best = None
        for hr in _HR.finditer(draft, 0, div.start()):
            best = hr
        if best is not None and not draft[best.end() : div.start()].strip():
            return best.start(), "divRplyFwdMsg (with leading <hr>)"
        return div.start(), "divRplyFwdMsg"

    rule = _HR_RULE_TEXT.search(draft)
    if rule:
        return rule.start(), "underscore rule (plain-text original)"

    raise SystemExit(
        "refused: no Graph separator found in the draft body.\n"
        '  Expected <div id="divRplyFwdMsg"> or a run of underscores.\n'
        "  Was this draft really created with a Comment? A draft built from\n"
        "  Message.body has no auto-quote to splice onto — that is the whole bug."
    )


def depth(html: str) -> int:
    return len(_LEVEL.findall(html))


def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    src = ap.add_mutually_exclusive_group(required=True)
    src.add_argument(
        "--draft-mime",
        help="RFC-822 source of the placeholder draft (download-bytes-to-file)",
    )
    src.add_argument("--draft-html", help="the draft's body.content, already extracted")
    ap.add_argument("--body", required=True, help="file holding YOUR new HTML fragment")
    ap.add_argument("--out", required=True, help="where to write the spliced body")
    ap.add_argument(
        "--placeholder",
        help="the Comment text used to create the draft; verified present, then removed",
    )
    ap.add_argument(
        "--assert-depth",
        type=int,
        default=1,
        metavar="N",
        help="fail unless the quoted region still has at least N From: header blocks (default 1)",
    )
    args = ap.parse_args()

    draft = (
        html_from_mime(read(args.draft_mime))
        if args.draft_mime
        else read(args.draft_html)
    )
    new_body = read(args.body)

    cut, marker = find_cut(draft)
    quote = draft[cut:]

    body_open = _BODY_OPEN.search(draft)
    if not body_open:
        raise SystemExit("refused: draft has no <body> tag; cannot place new content")
    head = draft[: body_open.end()]

    if args.placeholder:
        between = draft[body_open.end() : cut]
        if args.placeholder not in between:
            raise SystemExit(
                f"refused: placeholder {args.placeholder!r} is not in the region above the quote.\n"
                "  Either the draft was not created with that Comment, or the cut point is wrong.\n"
                "  Splicing anyway could silently drop real content."
            )

    spliced = f"{head}\n{new_body.rstrip()}\n{quote}"

    if args.placeholder and args.placeholder in spliced:
        raise SystemExit(
            f"refused: placeholder {args.placeholder!r} survives in the output.\n"
            "  It appears inside the QUOTED region, so removing it would edit the record."
        )

    before, after = depth(quote), depth(spliced[len(head) + len(new_body) :])
    if before != after:
        raise SystemExit(f"refused: quoted-region depth changed {before} -> {after}")
    if before < args.assert_depth:
        raise SystemExit(
            f"refused: quoted chain is {before} level(s) deep, expected at least {args.assert_depth}.\n"
            "  The original may not carry the history you think it does — an auto-generated\n"
            "  confirmation quotes nothing, so replying to one can only ever yield 1 level.\n"
            "  Reply to the message that ACTUALLY carries the chain instead."
        )

    with open(args.out, "w", encoding="utf-8") as fh:
        fh.write(spliced)

    # Styling: warn, never silently rewrite. The carrier document is the original
    # sender's, and neutralising it by hand would change how the QUOTE renders too.
    warnings = []
    carrier = _INHERITED_COLOR.search(head)
    if carrier and "color" not in new_body.lower():
        warnings.append(
            f"the carrier document sets '{carrier.group().strip()}' and your fragment sets no colour "
            "-> your text will inherit it. Add an explicit color to your wrapper."
        )
    if re.search(r"<style", head, re.IGNORECASE) and re.search(
        r"<p\b(?![^>]*style=)", new_body, re.IGNORECASE
    ):
        warnings.append(
            "the carrier <head> carries the sender's <style> blocks (vendor templates commonly "
            "set `p{margin:0}`) and your fragment has a <p> with no inline style -> your paragraph "
            "spacing will collapse. Put margins inline on every block element."
        )

    print(f"spliced -> {args.out}")
    print(f"  separator     : {marker}")
    print(
        f"  carried over  : {len(quote)} bytes of quoted chain, {before} level(s) deep, byte-identical"
    )
    print(f"  your content  : {len(new_body)} bytes")
    for w in warnings:
        print(f"  WARNING       : {w}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
