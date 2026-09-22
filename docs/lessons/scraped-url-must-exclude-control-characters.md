# A URL scraped from terminal output must exclude control characters

**The rule.** When you lift a URL (or any token) out of another program's *terminal*
output, bound the match with a class that excludes control characters —
`[^\s\x00-\x20\x7f]`, never `\S`. `\S` means "not whitespace", and every C0 control
byte qualifies: BEL, ESC, NUL. Terminal output is not plain text, and the escape
sequences in it are made of exactly those bytes.

## The incident (2026-09-22, `cc-relogin next2`)

`cc-relogin` scrapes the authorize URL out of the login CLI's transcript:

```python
OAUTH_URL_RE = re.compile(r"https://\S*?(?:oauth/authorize|/authorize\?)\S*")
```

The CLI does not print a bare URL. It prints an **OSC 8 hyperlink**, whose wire form is

```
ESC ] 8 ; ; <uri> BEL <visible label> ESC ] 8 ; ; BEL
```

and the visible label is *the same URL again*. BEL is not whitespace, so `\S*` ran
straight across it and returned both copies concatenated: every query parameter
doubled, and a literal `%07` spliced into the middle of `login_hint`.

That URL was then driven to claude.ai, which answered `/login`. `cc-relogin` reads a
`/login` landing as "this auth-profile has no live claude.ai web session" and returned
**exit 6, `fallback-required`** — handing the operator a manual browser sign-in.

## Why it is worth a lesson

The tool reported a fact about **the world** (your web session is cold) that was
manufactured by **its own parser**. Nothing in the verdict pointed at the parser: the
exit code, the message, and the remedy were all coherent, and the remedy — go sign in
by hand — would have "worked", concealing the defect indefinitely. Compare
[a refusal bounds the TOOL, not the world]; this is the same shape one level down,
where the instrument does not refuse but *answers*.

The residue matters too: after a wrong exit 6, whether the session was genuinely cold
is **unknown**, not false. A corrupted instrument does not license the opposite
conclusion — it licenses re-measuring.

## Why the suite could not see it

The fixture wrote plain newline-delimited text:

```python
open(p, "w").write("Or visit: https://claude.ai/oauth/authorize?code_challenge=MANUAL&state=s1\n")
```

It reproduced the *content* of the transcript and not its *shape*, so the one byte that
carries the bug was absent by construction, and the case would have passed against any
regex at all. The repaired case replays the real bytes from `/tmp/cc-relogin-next2.out`
and reds against the old pattern with exactly the production string.

**Generalisation:** a fixture for a parser must reproduce the *encoding* of the real
input, not a clean-room rendering of its meaning. Where the producer is a terminal
program, that means its escape sequences — the shape the bug lives in — and this is
the same failure as [fixture shape hides address bugs].

## Where else this bites

Any scrape of a program's terminal output. OSC 8 hyperlinks are now emitted by default
by a growing set of CLIs, and they are invisible in a terminal and in most editors —
`cat -v`, `xxd`, or a Python `repr()` is what makes them visible. Suspect one whenever
a scraped value looks *doubled*.

Fixed in `e7f752832`.
