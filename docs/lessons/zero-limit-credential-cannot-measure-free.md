# A spend-incapable credential cannot answer "is this free?" — and one id's price is not the product's price

**2026-09-17.** Measured, self-inflicted, and caught only because the operator pushed back
on a recap. Two independent errors stacked into one confident wrong conclusion that reached
a landed document and a user-facing summary.

## What happened

We minted a deliberately **unfunded** OpenRouter key — `limit: 0`, `is_free_tier: true` —
on the reasoning (correct, and recorded in the dossier) that *an unfunded account's key is
spend-incapable by construction, so a leaked key cannot bill.* Then we used that key to
decide whether a model was free.

1. `stealth/union-alpha` returned **404**, body: *"Thank you for participating in the Stealth
   Union Alpha testing period. This model **was** Unbiased's Pareto. **Use it now**: …"*
   I concluded **"the model is dead."**
2. I looked up the named successor `unbiased/pareto` in `/api/v1/models`, read
   `prompt=0.0000025, completion=0.0000075`, and concluded **"the free premise is gone."**
3. Both pareto ids then returned **403 `Key limit exceeded (total limit)`**, which I read as
   confirmation that they were paid and unreachable.

All three readings were wrong, and the third *felt* like corroboration of the second.

## What was actually true

- **A stealth alias 404-ing at reveal means LAUNCH, not death.** The body says so in its own
  words. The prior precedent in our own dossier (Ox Alpha, a model genuinely *deleted* from
  the catalogue) primed the opposite reading of a byte-identical-looking 404. A 404 is a
  statement about one **identifier**, never about a product.
- **Free access existed the whole time, under a different id.** OpenRouter's own FAQ page:
  *"Is Pareto Code Router free? Yes. The pricing shown on this page for Pareto Code Router is
  zero, so you are not charged for prompt or completion tokens."* — `openrouter/pareto-code`,
  2,000,000 token context. I had read the **direct** model's price and concluded the
  **product** had no free route. Free access was via the **router**.
- **The 403 was about our KEY, not about the price.** A `limit: 0` key permits ids priced
  exactly `0` (three `:free` models returned 200 on the same key in the same minute) and
  refuses anything whose cost is not provably zero at request time. Both pareto ids advertise
  `prompt=-1, completion=-1` — *router-determined*. So the refusal was our own safeguard
  firing, reported with an error message that names a limit rather than a price.

## The rule

**A zero-limit / spend-incapable credential is a BAD INSTRUMENT for the question "is this
free?"** It can only answer the much narrower *"is this identifier's listed price literally
zero."* It is structurally blind to:

- a promotional free period (billing-time discount, listed price unchanged),
- a router or alias whose *effective* price is zero but whose advertised price is variable,
- any free tier gated behind a non-zero limit check.

And it refuses **all** of those identically, with an error naming the KEY. That is the
[[reference-a-refusal-bounds-the-tool-not-the-world]] shape in its most seductive form: the
refusal arrives *after* a plausible pricing reading and is therefore mistaken for
confirmation of it, rather than recognised as the instrument declining to measure.

**Three checks, none expensive:**

1. **Before concluding a product has no free route, enumerate every id it is served under** —
   the direct model, `:free` variants, routers, aliases. A price is a property of an
   identifier; a product may have many, priced differently.
2. **Read the VENDOR'S OWN PRICING PAGE.** Here it was the discriminating instrument and the
   API was not: the FAQ stated the answer in one sentence while `/api/v1/models` reported
   `-1` and the key reported a limit error. A catalogue endpoint tells you what a *row* says,
   not what a *customer pays*.
3. **Never let a deliberately crippled credential adjudicate a market question.** The
   property that makes it safe (it cannot spend) is exactly the property that makes it unable
   to distinguish "costs money" from "costs nothing but is not provably zero."

## The residual, which is real and is a decision, not a bug

The free route and our safeguard are genuinely in tension: reaching a zero-effective-price
router requires raising the key's limit above `0`, which converts spend-incapability from an
**impossibility** into a **cap**. Effective charge ~$0, but no longer *provably* $0. That is
a money-path judgment for the operator, not something to resolve by loosening the key because
the measurement was inconvenient.

## Cross-checks that would have caught it earlier

- The operator's challenge was one sentence and settled it. **A confident conclusion drawn
  entirely from an instrument you chose for its safety properties deserves one cheap
  independent read before it reaches a recap** — here, one HTTP GET of a public page.
- The word **"dead"** did work that no measurement supported. The measurement was
  *"this identifier returns 404"*; the claim was *"this model no longer exists."* Watch for a
  summary verb that outruns its evidence, especially one that closes off a line of work.
