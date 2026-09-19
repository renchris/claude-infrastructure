# "Free" names a price, and a rate limit is a separate gate

**The rule.** A vendor's free window tells you what a call **costs**, never how many you may
**make**. Before designing anything around a promotional period, establish the *throughput* terms
separately from the *price* terms — and before a capability is called available, check whether it is
gated by **plan** rather than by code, because no amount of correct implementation reaches a plan
gate.

## The incident (2026-09-19, claude-infrastructure)

Vercel announced Jev "free on AI Gateway until Sept 25". A per-turn Stop-hook integration was
designed, built, tested against a mock (27 assertions, all green), landed, and converged on that
basis. The first real calls found **two** gates, neither of them about price:

| gate | verbatim | needs |
|---|---|---|
| Zero Data Retention | `403 — Zero Data Retention (ZDR) is only available for Pro and Enterprise plans. Current plan: hobby.` | a Pro plan |
| Throughput | `429 — Free tier requests on this model are rate-limited. Upgrade to paid credits… for unrestricted access.` | paid credits |

Roughly a dozen calls in, four consecutive requests were refused 429 and a later single request was
still refused. Calls that did succeed were correct and fast (P = 0.01 on a true negative, ~770 ms).

**The consequence was not a nuisance, it was a wrong answer waiting to happen.** The pilot built to
measure the model fires ~40 calls. Unpaced on a rate-limited tier it would have collected mostly
429s and reported *"the model missed the labels"* — a confident wrong verdict in the disqualifying
direction, produced by measuring **our own request rate** and attributing it to the subject. It now
paces between calls and backs off once on a `rate-limited` reason, which is the one abstain class
whose correct response is to slow down rather than to give up.

## What to do instead

1. **Read the promo's terms for a throughput clause before building**, and if there isn't one, treat
   throughput as unknown rather than as unlimited.
2. **Give rate limiting its own classification.** Folding 429 into a generic transport failure makes
   a self-inflicted burst indistinguishable from a broken route.
3. **Any measurement harness that fans out must pace**, or it measures itself. This is
   `positive-control-the-denominator` in a new coat: the number you get is real, and it is a number
   about the wrong thing.
4. **Ask which gates are PLAN-gated** early. A plan gate is invisible to every test that does not
   make a real call with the real credential — a mock will happily return whatever you told it to.

## Companions

- `a-wrapper-renames-your-own-timeout-into-a-foreign-fault` — the sibling defect from the same
  first-contact session.
- `a-cost-premise-is-per-arm-and-is-usually-false`.
- `crippled-credential-cannot-price` — one credential's terms are not the product's terms.
