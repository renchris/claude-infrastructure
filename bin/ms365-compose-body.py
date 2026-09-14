#!/usr/bin/env python3
"""ms365-compose-body.py — turn plain text into the house HTML fragment for an email body.

WHY THIS EXISTS
---------------
Before this, an agent drafting mail hand-wrote the HTML. Three things went wrong every
time, and all three are structural rather than careless:

  1. ONE RUN-ON PARAGRAPH. Greeting, body, ask and sign-off fused into a single line,
     because the text was passed as prose and Microsoft Graph strips newlines out of a
     reply `Comment`. The break has to be MARKUP; nothing else survives.

  2. GREY TEXT, NOT BLACK. Graph drops the reply text into a BARE `<body>` with no
     styling at all — measured 2026-09-14 on this mailbox, the comment arrives as a
     naked text node while Graph's own quote header right below it is explicitly
     `<font face="Calibri, sans-serif" color="#000000" style="font-size:11pt">`. So the
     reply inherits whatever the READING CLIENT defaults to and the quoted history
     below it is explicitly black — which is exactly the "ours looks grey, theirs looks
     black" complaint. A fragment that states its own colour cannot drift.

  3. NO SIGNATURE. Graph never adds one: the ms365 server's own tool description says
     "Signatures are added by the Outlook client only, not via Graph", and the Outlook
     client does not add one to a draft that an API created. If the agent does not put
     it in the body, the message goes out unsigned.

THE RULE THIS ENCODES: every block element carries its own inline style. Not because
inline CSS is elegant, but because the fragment is pasted into a document somebody else
wrote — the original sender's carrier document, whose `<style>` blocks Graph copies into
the draft's `<head>`. A vendor stylesheet's `p{margin:0}` silently collapses your
paragraph spacing, and a `body{color:…}` recolours your prose. Inline wins over both.

USAGE
    ms365-compose-body.py --text-file reply.txt --signature chris-reso --out body.html
    printf 'Hi Harry,\\n\\nThanks for reaching out.\\n\\nBest regards,\\nChris' \\
        | ms365-compose-body.py --signature chris-reso --out body.html

INPUT FORMAT — deliberately not a markup language. Paragraphs are separated by a blank
line. A run of lines each beginning "- " becomes a <ul>. That is all; a business reply
is prose, and every extra construct is another thing to render wrong in Outlook.

Exit codes: 0 ok · 1 usage/IO error · 2 refused (empty input, or a signature id that is
not in the signature file — a silently unsigned email is the defect this prevents).
"""

from __future__ import annotations

import argparse
import html
import json
import os
import pathlib
import re
import sys

# A REFUSAL is not a usage error, and a caller must be able to tell them apart: exit 1
# means "you invoked me wrong", exit 2 means "I looked, and I will not do this".
# The module docstring has always promised 2; raise SystemExit(str) exits 1, so this
# promise was broken from the first commit and every caller branching on it was wrong.
_REFUSE_RC = 2


def refuse(msg: str):
    print(msg, file=sys.stderr)
    raise SystemExit(_REFUSE_RC)

# The house type stack. NOT chosen from documentation — MEASURED off a message this
# operator's own Outlook composed and sent (2026-09-02), read out of its MIME:
#
#     <div style="font-family: Calibri, Helvetica, sans-serif; font-size: 12pt;
#                 color: rgb(0, 0, 0);" class="elementToProof">
#
# so a reply we draft is typographically indistinguishable from one he typed. Two
# corrections are baked in here, and both were wrong in the first draft of this file:
#
#   * 12pt, not 11pt. The brief and this file both said 11pt. A survey of 25 real
#     Outlook-composed messages found 182 declarations of 12pt against 6 of 11pt, and
#     this mailbox agrees. (11pt appears in the SAME file — it is what Outlook uses for
#     the quote HEADER it generates, which is not the compose size.)
#   * Calibri, not Aptos. Aptos is the Microsoft 365 default since 2024, and a doc-led
#     choice lands there; this CONSUMER Outlook.com mailbox still composes in Calibri.
#     An M365 mailbox will differ, which is why the stack is per-identity below.
#
# Size in pt because Outlook states its own in pt; mixing pt above the separator with px
# below it is visibly inconsistent inside one message. Never add an @font-face to "make
# Aptos work": an element using an @font-face font ignores the whole stack and falls back
# to Times New Roman in Outlook Windows 2007-2016.
DEFAULT_FONT = "Calibri,Helvetica,sans-serif"
DEFAULT_SIZE = "12pt"
DEFAULT_COLOR = "#000000"
# Declared as a PAIR with the colour, or not at all. A fragment spliced into someone
# else's document has exactly ONE dark-mode lever — the colours it states — because every
# published mechanism (<meta name="color-scheme">, :root{color-scheme}, prefers-color-scheme,
# [data-ogsc]) needs a <head>, a :root, or a <style> block that a fragment cannot deliver.
# Declaring a colour ALONE is the shape that goes invisible: a client doing PARTIAL inversion
# darkens the background it inherited and keeps the text colour you stated, which is how black
# text ends up on a dark background. Stating both means they are inverted together or preserved
# together, and either outcome is readable. Measured under Chrome's force-dark (a FULL-inversion
# engine) both shapes render correctly, so that instrument cannot separate them — this default
# follows the contrast arithmetic instead: across four backgrounds, NO single text colour clears
# WCAG AA on both white and a dark-mode ground, so "pick a safe grey" is not available.
# --no-background exists for a fragment going somewhere a white slab would be wrong.
DEFAULT_BG = "#ffffff"

# Space between paragraphs. 12pt is Outlook's own "space after" for a default paragraph.
PARA_MARGIN = "0 0 12pt 0"

SIG_FILE_ENV = "CC_MS365_SIGNATURES"
DEFAULT_SIG_FILE = "~/.claude/email-signatures.json"


def esc(text: str) -> str:
    """HTML-escape, then restore nothing. Text in must render as text out."""
    return html.escape(text, quote=False)


def load_signatures(path: str | None):
    p = pathlib.Path(os.path.expanduser(path or os.environ.get(SIG_FILE_ENV) or DEFAULT_SIG_FILE))
    if not p.exists():
        return {}, p
    try:
        with open(p, encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError) as exc:
        raise SystemExit(f"error: cannot read signature file {p}: {exc}")
    if not isinstance(data, dict):
        raise SystemExit(f"error: {p} must hold a JSON object keyed by signature id")
    return data, p


def render_signature(sig: dict, font: str, size: str, color: str) -> str:
    """Render a signature block.

    Stacked <div>s, not a <table>: a table signature is a marketing-email idiom and
    Outlook's Word engine reflows narrow table cells unpredictably. Every line carries
    its own inline style for the same reason the paragraphs do.

    The name line is the only emphasised one. No image, no legal boilerplate, no quote —
    those are what make a signature look like a template rather than a person.
    """
    lines = []
    name = sig.get("name")
    if name:
        lines.append(
            f'<div style="margin:0;font-family:{font};font-size:{size};color:{color};">'
            f"<b>{esc(name)}</b></div>"
        )
    for key in ("title", "company"):
        value = sig.get(key)
        if value:
            lines.append(
                f'<div style="margin:0;font-family:{font};font-size:{size};color:{color};">'
                f"{esc(value)}</div>"
            )
    for key, prefix in (("phone", ""), ("email", ""), ("website", "")):
        value = sig.get(key)
        if not value:
            continue
        if key == "email":
            shown = esc(value)
            lines.append(
                f'<div style="margin:0;font-family:{font};font-size:{size};color:{color};">'
                f'<a href="mailto:{esc(value)}" style="color:{color};">{shown}</a></div>'
            )
        elif key == "website":
            href = value if value.startswith(("http://", "https://")) else f"https://{value}"
            lines.append(
                f'<div style="margin:0;font-family:{font};font-size:{size};color:{color};">'
                f'<a href="{esc(href)}" style="color:{color};">{esc(value)}</a></div>'
            )
        else:
            lines.append(
                f'<div style="margin:0;font-family:{font};font-size:{size};color:{color};">'
                f"{prefix}{esc(value)}</div>"
            )
    if not lines:
        return ""
    # One blank line of separation above the block, matching a paragraph gap.
    return (
        f'<div style="margin:12pt 0 0 0;font-family:{font};font-size:{size};color:{color};">'
        + "".join(lines)
        + "</div>"
    )


_BULLET = re.compile(r"^\s*[-*]\s+(.*)$")


def render_blocks(text: str, font: str, size: str, color: str) -> str:
    """Paragraphs separated by blank lines; a run of '- ' lines becomes a <ul>."""
    out = []
    for chunk in re.split(r"\n\s*\n", text.strip()):
        lines = [ln for ln in chunk.split("\n") if ln.strip()]
        if not lines:
            continue
        if all(_BULLET.match(ln) for ln in lines):
            items = "".join(
                f'<li style="margin:0 0 4pt 0;font-family:{font};font-size:{size};color:{color};">'
                f"{esc(_BULLET.match(ln).group(1).strip())}</li>"
                for ln in lines
            )
            # margin-left, NOT padding-left. classic Outlook renders through Word, where
            # padding is supported on table cells ONLY — a padded <ul> simply loses its
            # indent there, silently, while looking correct everywhere else.
            out.append(
                f'<ul style="margin:0 0 12pt 24px;">{items}</ul>'
            )
        else:
            # A single newline INSIDE a paragraph is a soft break — that is how a
            # sign-off ("Best regards,\nChris") is written, and it must not become a
            # paragraph gap.
            body = "<br>".join(esc(ln.rstrip()) for ln in lines)
            out.append(
                f'<p style="margin:{PARA_MARGIN};font-family:{font};font-size:{size};'
                f'color:{color};">{body}</p>'
            )
    return "".join(out)


def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument("--text-file", help="plain-text source; omit to read stdin")
    ap.add_argument("--out", help='write here instead of stdout ("-" means stdout)')
    ap.add_argument("--signature", help="signature id from the signature file")
    ap.add_argument("--signature-file", help=f"default: ${SIG_FILE_ENV} or {DEFAULT_SIG_FILE}")
    ap.add_argument("--no-signature", action="store_true", help="omit the signature block")
    # Default None, not the constant: the signature entry may carry its own font/size
    # (an M365 identity composes in Aptos where a consumer one composes in Calibri), and
    # an explicit flag must still beat it. Resolving below keeps that precedence readable.
    ap.add_argument("--font", default=None, help=f"default: the identity's, else {DEFAULT_FONT}")
    ap.add_argument("--size", default=None, help=f"default: the identity's, else {DEFAULT_SIZE}")
    ap.add_argument("--color", default=DEFAULT_COLOR)
    ap.add_argument("--background", default=DEFAULT_BG)
    ap.add_argument(
        "--no-background",
        action="store_true",
        help="omit background-color; see DEFAULT_BG for why the pair is the default",
    )
    ap.add_argument(
        "--list-signatures", action="store_true", help="print the known signature ids and exit"
    )
    args = ap.parse_args()

    sigs, sig_path = load_signatures(args.signature_file)

    if args.list_signatures:
        if not sigs:
            print(f"no signatures defined ({sig_path} is missing or empty)")
        for key, val in sorted(sigs.items()):
            print(f"{key}\t{val.get('name','?')} · {val.get('email','-')}")
        return 0

    text = (
        open(args.text_file, encoding="utf-8").read()
        if args.text_file
        else sys.stdin.read()
    )
    if not text.strip():
        refuse("refused: empty body text")

    sig = sigs.get(args.signature) if args.signature else None
    font = args.font or (sig or {}).get("font") or DEFAULT_FONT
    size = args.size or (sig or {}).get("size") or DEFAULT_SIZE

    blocks = render_blocks(text, font, size, args.color)

    sig_html = ""
    if not args.no_signature:
        if not args.signature:
            refuse(
                "refused: no --signature given. An unsigned business email is the defect\n"
                "  this tool exists to prevent, so the omission has to be deliberate:\n"
                f"  pass --signature <id> (see --list-signatures, file {sig_path})\n"
                "  or --no-signature if this message genuinely should not carry one."
            )
        if args.signature not in sigs:
            refuse(
                f"refused: signature id {args.signature!r} is not in {sig_path}.\n"
                f"  Known ids: {', '.join(sorted(sigs)) or '(none)'}\n"
                "  Do NOT invent a name, title or phone number to fill the gap — ask the\n"
                "  operator for the real ones and add them to that file."
            )
        sig_html = render_signature(sigs[args.signature], font, size, args.color)

    # The outer wrapper restates font/size/colour so that anything NOT covered by a
    # block rule above (a stray text node, a nested inline element) still inherits from
    # us rather than from the carrier document.
    bg = "" if args.no_background else f"background-color:{args.background};"
    fragment = (
        f'<div style="font-family:{font};font-size:{size};color:{args.color};{bg}">'
        f"{blocks}{sig_html}</div>"
    )

    if args.out and args.out != "-":
        with open(args.out, "w", encoding="utf-8") as fh:
            fh.write(fragment)
        visible = len(re.sub(r"<[^>]+>", "", fragment))
        print(f"wrote {args.out}: {len(fragment)} bytes of HTML, {visible} visible chars")
    else:
        sys.stdout.write(fragment)
    return 0


if __name__ == "__main__":
    sys.exit(main())
