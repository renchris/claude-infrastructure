# Composer scrub — the instrument, so the claim can be re-measured instead of quoted

`scrub-probe.py` is what refuted P2's *"there is NO safe programmatic scrub"*
(`../recycle-100p-2026-08-22.md` §2.4). It is committed for one reason: a resident
claim about a live binary is a perishable fact, and the fix for that is not a
better sentence but the command that re-derives it.

    python3 -m venv .v && ./.v/bin/pip install pyte
    ./.v/bin/python scrub-probe.py <path-to-claude-binary> "$HOME/.claude-tertiary" <a-trusted-cwd> 12

It spawns a real Claude Code under a PTY, never submits anything, renders the
screen with `pyte`, and parses the composer with the same rule
`handoff-fire.sh :: composer_content` uses (the text between the last two
full-width border rows). It exercises the shipped algorithm — bounded,
read-back-verified Ctrl-U with a backspace when a round stalls — and reports the
rounds each payload shape consumed.

**Run the negative arm too.** With the bound at `1` a 3-line payload must come
back `REFUSE`, and `scrub-probe.py`'s sibling in the session history showed `Esc`
INERT on both binaries. A probe that cannot say *no* proves nothing when it says
*yes* — which is precisely how the original measurement went wrong.

Measured 2026-09-09, bound 12, both binaries, identical results:

| payload | composer before | rounds | verdict |
|---|---|---|---|
| short 1-line paste | inline text | 1 | CLEARS |
| 3-line paste | inline text, 3 rows | 5 | CLEARS |
| 8-line paste | `[Pasted text #1 +7 lines]` | 1 | CLEARS |
| 25-line paste | `[Pasted text #1 +24 lines]` | 1 | CLEARS |
| a `/goal` condition | inline text | 1 | CLEARS |
