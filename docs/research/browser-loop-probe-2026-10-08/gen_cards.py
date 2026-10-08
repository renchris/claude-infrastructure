#!/usr/bin/env python3
"""Render the three scanned lead cards of the fixed form task as PNGs.

The card text is the ground truth read off the SDK launch video, FIG 3 (frames f-015, f-019, f-023,
f-024; /tmp/browser-sdk/notes/video.md). Card 3 is cursive red ink at a smaller size, as in the
video, so a reader has to enlarge it. Re-running this script reproduces the committed PNGs.

Usage: python3 -I gen_cards.py   (writes fixture/cards/card-{1,2,3}.png beside this file)
"""

import json
import pathlib

from PIL import Image, ImageDraw, ImageFont

HERE = pathlib.Path(__file__).resolve().parent
FONTS = pathlib.Path("/System/Library/Fonts/Supplemental")
TRUTH = json.loads((HERE / "expected.json").read_text())

W, H = 820, 560
PAPER = (247, 243, 232)
PRINT = (70, 78, 92)
INKS = [(24, 40, 120), (20, 20, 24), (176, 28, 36)]
HANDS = [
    ("Bradley Hand Bold.ttf", 30),
    ("Chalkboard.ttc", 27),
    ("SnellRoundhand.ttc", 19),
]
PLANS = ["Starter", "Team", "Enterprise"]


def font(name, size):
    return ImageFont.truetype(str(FONTS / name), size)


def card(n, lead):
    img = Image.new("RGB", (W, H), PAPER)
    d = ImageDraw.Draw(img)
    label = font("Chalkboard.ttc", 15)
    head = font("Chalkboard.ttc", 22)
    hand = font(*HANDS[n - 1])
    ink = INKS[n - 1]

    d.rectangle([8, 8, W - 9, H - 9], outline=PRINT, width=2)
    d.text((28, 22), "NORTHWIND CLOUD", font=head, fill=PRINT)
    d.text((28, 52), f"Booth lead card · DevDays 2026", font=label, fill=PRINT)
    d.text((W - 80, 22), f"#{n:02d}", font=head, fill=PRINT)

    rows = [
        ("Name", lead["name"]),
        ("Company", lead["company"]),
        ("Email", lead["email"]),
        ("Phone", lead["phone"]),
        ("Role", lead["role"]),
    ]
    y = 96
    for key, val in rows:
        d.text((28, y + 8), key, font=label, fill=PRINT)
        d.line([130, y + 34, W - 30, y + 34], fill=(190, 186, 176), width=1)
        d.text((140, y), val, font=hand, fill=ink)
        y += 52

    d.text((28, y + 8), "Interested in:", font=label, fill=PRINT)
    x = 150
    for plan in PLANS:
        d.rectangle([x, y + 8, x + 18, y + 26], outline=PRINT, width=2)
        if plan == lead["plan"]:
            d.line([x + 2, y + 16, x + 8, y + 24], fill=ink, width=4)
            d.line([x + 8, y + 24, x + 22, y + 2], fill=ink, width=4)
        d.text((x + 26, y + 8), plan, font=label, fill=PRINT)
        x += 150
    y += 48

    d.text((28, y + 8), "Team size (seats)", font=label, fill=PRINT)
    d.line([180, y + 34, 320, y + 34], fill=(190, 186, 176), width=1)
    d.text((190, y), str(lead["seats"]), font=hand, fill=ink)
    d.text((360, y + 8), "Follow up by:", font=label, fill=PRINT)
    for i, opt in enumerate(["Email", "Phone"]):
        ox = 480 + i * 100
        d.text((ox, y + 8), opt, font=label, fill=PRINT)
        if opt.lower() == lead["follow_up"]:
            d.ellipse([ox - 10, y, ox + 58, y + 34], outline=ink, width=3)
    y += 52

    d.text((28, y + 8), "Notes", font=label, fill=PRINT)
    d.text((140, y), lead["notes"], font=hand, fill=ink)

    out = HERE / "fixture" / "cards" / f"card-{n}.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    img.save(out, optimize=True)
    return out


if __name__ == "__main__":
    for i, lead in enumerate(TRUTH["leads"], start=1):
        print(card(i, lead))
