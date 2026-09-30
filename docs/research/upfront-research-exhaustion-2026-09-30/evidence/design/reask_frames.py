#!/usr/bin/env python3
"""Re-derive the operator's re-ask frame tally (reality-contact.md §3 P0 I5) from loop_asks.json.

Written 2026-09-30 after the reboot deleted the original ad-hoc tally. The regexes are crude by
design: a frame counts once per ask if its pattern appears anywhere in the ask text. Counts are
indicative only ("implemented" and "complete" are inflated by the operator's catchphrase).
Run: python3 /tmp/rescomp/design/reask_frames.py
"""
import json
import re

ASKS = json.load(open("/tmp/rescomp/loop_asks.json"))

FRAMES = [
    ("correct/complete/covering", "V1", r"\bcomplete\b|\bcorrect\b|\bcovering\b|\bcomprehensive\b"),
    ("researched/exhausted", "V1", r"research|exhaust"),
    ("deployed and live", "V6/V7", r"\bdeploy|\blive\b|production|\bprod\b"),
    ("good to close/done", "V9", r"good to close|safe to close|\bdone\b|finished"),
    ("decisions/steps outstanding", "V2", r"decision|next step|current step|outstanding|remaining"),
    ("optimum (nothing else can beat it)", "V8", r"optim|\bbeat\b|best possible|nothing else can|can't be beaten|cannot be beaten"),
    ("catchphrase: 100th percentile / perfection", "(frame-free)", r"100th|perfect"),
    ("no loose ends/follow-ons", "V5", r"loose end|follow[- ]?on|left on the table|nothing left"),
    ("no take-backs/final", "V4", r"take[- ]?back|no redo|final\b|once and for all"),
    ("all waves/master plan", "V6", r"all waves|master plan|every wave|whole plan"),
    ("saved/persisted", "G7", r"\bsaved\b|persist|committed|landed"),
]

n = len(ASKS)
print(f"asks: {n}")
for name, axis, pat in FRAMES:
    rx = re.compile(pat, re.I)
    hits = sum(1 for a in ASKS if rx.search(a.get("text", "")))
    print(f"{hits:>3}  {name:<38} -> {axis}   /{pat}/")
