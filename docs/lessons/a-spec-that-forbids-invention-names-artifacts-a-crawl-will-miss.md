# A spec that forbids invention names artifacts a crawl will miss

**The rule.** When a corpus says *"use ONLY these exact N variants — never invent new
ones"*, it is naming **derived artifacts**, not base resources. A crawl that captures
the base and every linked document still misses them, and the prohibition is what makes
the miss unrecoverable: a later reader obeying the rule has nothing it is permitted to
use, and obeying correctly is precisely what hides the gap. Grep any mirrored corpus for
its own "only these" clauses and capture what they enumerate.

## The incident (2026-09-20, assets.ui.sh)

The ui.sh mirror was, by every check applied to it, complete: 99 markdown files by BFS,
link-closure verified 88/88, 77 binary assets, sha256 manifest with 0 failures, and two
prose-named skills probed to `Skill resource not found`. Asked to affirm the endpoint
was maximally extracted, checking rather than affirming found this in
`placeholder-content.md`:

> For feature section screenshots, use only these exact cropped variants — never invent
> new crop parameters:
> `?top=900&left=1200&position=bottom-right` … (six enumerated)

The mirror held `screenshots/1.webp` and its five colourways. It held **zero of the six
crops**. They are query-parameter derivations of a resource already captured, so no
link-closure check could see them — nothing links to them; a *prose rule* mandates them.

## Why this shape is worse than an ordinary omission

The omission is silent in both directions. Nothing in the mirror is missing a *link*, so
every completeness check passes. And after the CDN dies, an agent following the rule
correctly finds six URLs that 404 — while the same rule forbids substituting its own
crops. Obedience produces a dead end; only disobedience produces output. The gap becomes
visible exactly when it has become unfixable.

## The generalisation, and its limit

Two kinds of thing hide behind a parameterised endpoint, and they need different answers:

- **Enumerable derivations** — a spec lists them, or the parameter is closed (45 named
  wallpaper variants, 5 named colourways, 6 named crops). **Capture them.**
- **Generators** — the parameter space is open. The same ui.sh asset API composes a
  wordmark from *arbitrary text* across 6 fonts and bakes the glyphs to vector paths
  server-side. Infinite by construction; no crawl can hold it. **Record what makes it
  re-implementable** (the base glyph, the font list with sourcing URLs, one specimen per
  font to fix proportion and baseline) and say plainly that convenience dies while
  capability does not.

Sorting a parameter space into those two buckets is the audit. Everything else in that
corpus fell into a third, easiest bucket — locally derivable from what was already held
(logo fill swaps, avatar resize/grayscale) — which is worth checking first because it
costs nothing.

## Companions

- [[lookup-miss-is-not-absence]] — a miss is not proof the thing does not exist.
- [[zero-claim-must-name-its-excluded-strata]] — a completeness claim must name what it excluded.
- [[mirroring-a-corpus-is-not-using-it]] — the sibling failure from the same session.
